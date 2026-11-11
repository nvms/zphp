// php's ext/spl/spl_fixedarray.c: SplFixedArray, and the InternalIterator
// its getIterator() returns (zend_interfaces.c).
//
// the elements live in a hidden packed array. a resize that releases
// elements is php's: a size asked for while one runs is remembered and done
// afterwards, and the constructor and unserializers do nothing then
const std = @import("std");
const object_properties = @import("../runtime/object_properties.zig");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const PhpArray = value_mod.PhpArray;
const PhpObject = value_mod.PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeResult = vm_mod.NativeResult;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const sic = @import("spl_iterator_classes.zig");

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

const P = struct {
    const elements = "__fa_elements";
    // php's cached_resize: -1, or the size asked for while a resize runs
    const resize = "__fa_resize";
};

const MethodSpec = struct { []const u8, vm_mod.NativeFn };

fn registerClass(vm: *VM, a: Allocator, def: ClassDef, comptime name: []const u8, comptime methods: []const MethodSpec) !void {
    var d = def;
    inline for (methods) |m| {
        try d.methods.put(a, m[0], .{ .name = m[0], .arity = 0 });
        try vm.native_fns.put(a, name ++ "::" ++ m[0], m[1]);
    }
    try vm.classes.put(a, name, d);
}

pub fn register(vm: *VM, a: Allocator) !void {
    var fa = ClassDef{ .name = "SplFixedArray", .native_properties = properties };
    inline for (.{ "IteratorAggregate", "ArrayAccess", "Countable", "JsonSerializable" }) |i| try fa.interfaces.append(a, i);
    try registerClass(vm, a, fa, "SplFixedArray", &.{
        .{ "__construct", construct },   .{ "__wakeup", wakeup },
        .{ "__serialize", serializeM },  .{ "__unserialize", unserializeM },
        .{ "count", count },             .{ "toArray", toArray },
        .{ "fromArray", fromArray },     .{ "getSize", count },
        .{ "setSize", setSize },         .{ "offsetExists", offsetExists },
        .{ "offsetGet", offsetGet },     .{ "offsetSet", offsetSet },
        .{ "offsetUnset", offsetUnset }, .{ "getIterator", getIterator },
        .{ "jsonSerialize", toArray },
    });
    if (vm.classes.getPtr("SplFixedArray")) |def| if (def.methods.getPtr("fromArray")) |m| {
        m.is_static = true;
    };

    var ii = ClassDef{ .name = "InternalIterator", .is_final = true, .uncloneable = true };
    try ii.interfaces.append(a, "Iterator");
    try registerClass(vm, a, ii, "InternalIterator", &.{
        .{ "__construct", iiConstruct }, .{ "current", iiCurrent },
        .{ "key", iiKey },               .{ "next", iiNext },
        .{ "valid", iiValid },           .{ "rewind", iiRewind },
    });
    if (vm.classes.getPtr("InternalIterator")) |def| if (def.methods.getPtr("__construct")) |m| {
        m.visibility = .private;
    };
}

// ==========================================
// the array
// ==========================================

fn this(ctx: *NativeContext) RuntimeError!*PhpObject {
    return sic.thisObj(ctx) orelse {
        try sic.raise(ctx, "Error", "Object not initialized", .{});
        return error.RuntimeError;
    };
}

fn elementsOf(obj: *PhpObject) ?*PhpArray {
    const v = obj.get(P.elements);
    return if (v == .array) v.array else null;
}

pub fn sizeOf(obj: *PhpObject) usize {
    const arr = elementsOf(obj) orelse return 0;
    return arr.entries.items.len;
}

fn resizing(obj: *PhpObject) bool {
    const v = obj.get(P.resize);
    return v == .int and v.int >= 0;
}

fn setResize(ctx: *NativeContext, obj: *PhpObject, n: i64) RuntimeError!void {
    try obj.set(ctx.allocator, P.resize, .{ .int = n });
}

fn elementAt(arr: *PhpArray, i: usize) Value {
    const e = arr.entries.items[i];
    return if (e.ref) |r| r.* else e.value;
}

// the elements array to change, separated from a clone sharing it
fn writable(ctx: *NativeContext, obj: *PhpObject) RuntimeError!*PhpArray {
    const arr = elementsOf(obj) orelse {
        const fresh = try ctx.createArray();
        fresh.uncounted = true;
        try obj.set(ctx.allocator, P.elements, .{ .array = fresh });
        return fresh;
    };
    if (arr.refcount <= 1) return arr;
    const copy = try ctx.createArray();
    copy.uncounted = true;
    for (0..arr.entries.items.len) |i| try copy.append(ctx.allocator, elementAt(arr, i));
    try obj.set(ctx.allocator, P.elements, .{ .array = copy });
    return copy;
}

// spl_fixedarray_init: `size` nulls
// safe_emalloc's refusal of a size whose byte count overflows (a zval is
// 16 bytes)
fn checkAllocation(ctx: *NativeContext, size: usize) RuntimeError!void {
    if (size <= std.math.maxInt(usize) / 16) return;
    const msg = try std.fmt.allocPrint(ctx.allocator, "Possible integer overflow in memory allocation ({d} * 16 + 0)", .{size});
    defer ctx.allocator.free(msg);
    return ctx.vm.raiseFatal(msg);
}

fn initElements(ctx: *NativeContext, obj: *PhpObject, size: usize) RuntimeError!void {
    try checkAllocation(ctx, size);
    const arr = try ctx.createArray();
    arr.uncounted = true;
    for (0..size) |_| try arr.append(ctx.allocator, .null);
    try obj.set(ctx.allocator, P.elements, .{ .array = arr });
    try setResize(ctx, obj, -1);
}

// spl_fixedarray_resize
fn resize(ctx: *NativeContext, obj: *PhpObject, size: usize) RuntimeError!void {
    const current = sizeOf(obj);
    if (size == current) return;
    if (resizing(obj)) {
        try setResize(ctx, obj, @intCast(size));
        return;
    }
    if (current == 0) return initElements(ctx, obj, size);
    try setResize(ctx, obj, @intCast(size));
    if (size > current) {
        checkAllocation(ctx, size) catch |err| {
            try setResize(ctx, obj, -1);
            return err;
        };
    }
    const arr = try writable(ctx, obj);
    if (size > current) {
        for (current..size) |_| try arr.append(ctx.allocator, .null);
    } else {
        // the cut elements are released last first, their destructors
        // seeing the array at its new size
        var released: std.ArrayListUnmanaged(Value) = .empty;
        defer released.deinit(ctx.allocator);
        while (arr.entries.items.len > size) {
            const e = arr.entries.pop().?;
            try released.append(ctx.allocator, if (e.ref) |r| r.* else e.value);
            if (e.ref) |r| VM.retainValue(r.*);
        }
        arr.next_int_key = @intCast(arr.entries.items.len);
        if (arr.entries.items.len == 0) arr.has_int_keys = false;
        for (released.items) |v| ctx.vm.releaseValue(v);
        ctx.vm.drainPendingDestruct();
    }
    const cached = obj.get(P.resize);
    try setResize(ctx, obj, -1);
    if (cached == .int and cached.int >= 0 and cached.int != size) return resize(ctx, obj, @intCast(cached.int));
}

// spl_offset_convert_to_ulong: the index, or null with the exception
// pending. a negative index is out of range
fn offsetIndex(ctx: *NativeContext, offset: Value) RuntimeError!?u64 {
    switch (offset) {
        .int => |n| return @bitCast(n),
        .string => |s| if (canonicalInt(s.bytes())) |n| return @bitCast(n),
        .float => |f| {
            if (!std.math.isFinite(f) or f >= 9.2233720368547758e18 or f < -9.2233720368547758e18) return 0;
            const n: i64 = @intFromFloat(f);
            if (@as(f64, @floatFromInt(n)) != f) {
                const text = try sic.floatText(ctx, f);
                const msg = try std.fmt.allocPrint(ctx.allocator, "Implicit conversion from float {s} to int loses precision", .{text});
                defer ctx.allocator.free(msg);
                try ctx.vm.raiseError(VM.E_DEPRECATED, msg);
                if (sic.pending(ctx)) return null;
            }
            return @bitCast(n);
        },
        .bool => |b| return @intFromBool(b),
        .resource => |r| {
            const msg = try std.fmt.allocPrint(ctx.allocator, "Resource ID#{d} used as offset, casting to integer ({d})", .{ r.id, r.id });
            defer ctx.allocator.free(msg);
            try ctx.vm.raiseError(VM.E_WARNING, msg);
            if (sic.pending(ctx)) return null;
            return r.id;
        },
        else => {},
    }
    try sic.raise(ctx, "TypeError", "Cannot access offset of type {s} on SplFixedArray", .{offset.valueName()});
    return null;
}

// ZEND_HANDLE_NUMERIC: a decimal integer written the canonical way
fn canonicalInt(s: []const u8) ?i64 {
    if (s.len == 0 or s.len > 20) return null;
    var i: usize = 0;
    if (s[0] == '-') i = 1;
    if (i >= s.len) return null;
    if (s[i] == '0' and s.len - i > 1) return null;
    if (s[i] == '0' and i == 1) return null;
    for (s[i..]) |c| if (c < '0' or c > '9') return null;
    return std.fmt.parseInt(i64, s, 10) catch null;
}

fn outOfRange(ctx: *NativeContext) RuntimeError!void {
    try sic.raise(ctx, "OutOfBoundsException", "Index invalid or out of range", .{});
}

// `$a[]`, which the vm hands to offsetGet or offsetSet with a null offset:
// the native was called by the dimension write itself
fn appending(ctx: *NativeContext) bool {
    return ctx.vm.dim_append_depth == ctx.vm.frame_count;
}

fn noArgs(ctx: *NativeContext, label: []const u8, args: []const Value) RuntimeError!void {
    if (!try sic.argCount(ctx, label, args.len, 0, 0)) return error.RuntimeError;
}

// ==========================================
// methods
// ==========================================

fn construct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplFixedArray::__construct";
    if (!try sic.argCount(ctx, label, args.len, 0, 1)) return error.RuntimeError;
    const size = (try sic.argLong(ctx, label, args, 0, "size", 0)) orelse return error.RuntimeError;
    if (size < 0) return sic.throwNow(ctx, "ValueError", "{s}(): Argument #1 ($size) must be greater than or equal to 0", .{label});
    // a second call does nothing
    if (sizeOf(obj) != 0 or resizing(obj)) return NativeResult.scalar(.null);
    try initElements(ctx, obj, @intCast(size));
    return NativeResult.scalar(.null);
}

fn count(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFixedArray::count", args);
    return NativeResult.scalar(.{ .int = @intCast(sizeOf(obj)) });
}

fn toArray(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFixedArray::toArray", args);
    const out = try ctx.createArray();
    if (elementsOf(obj)) |arr| for (0..arr.entries.items.len) |i| try out.append(ctx.allocator, elementAt(arr, i));
    return NativeResult.borrowed(.{ .array = out });
}

fn setSize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplFixedArray::setSize";
    if (!try sic.argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const size = (try sic.argLong(ctx, label, args, 0, "size", 0)) orelse return error.RuntimeError;
    if (size < 0) return sic.throwNow(ctx, "ValueError", "{s}(): Argument #1 ($size) must be greater than or equal to 0", .{label});
    try resize(ctx, obj, @intCast(size));
    return sic.finish(ctx, NativeResult.scalar(.{ .bool = true }));
}

fn fromArray(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const label = "SplFixedArray::fromArray";
    if (!try sic.argCount(ctx, label, args.len, 1, 2)) return error.RuntimeError;
    if (args[0] != .array) {
        try sic.typeError(ctx, label, 1, "array", "array", args[0]);
        return error.RuntimeError;
    }
    const data = args[0].array;
    var save_indexes = true;
    if (args.len > 1) {
        save_indexes = switch (args[1]) {
            .bool => |b| b,
            .int, .float, .string => args[1].isTruthy(),
            .null => false,
            else => {
                try sic.typeError(ctx, label, 2, "preserveKeys", "bool", args[1]);
                return error.RuntimeError;
            },
        };
    }
    const out = try ctx.createArray();
    out.uncounted = true;
    const n = data.entries.items.len;
    if (n > 0 and save_indexes) {
        var max: u64 = 0;
        for (data.entries.items) |e| switch (e.key) {
            .string => return sic.throwNow(ctx, "InvalidArgumentException", "array must contain only positive integer keys", .{}),
            .int => |k| {
                if (k < 0) return sic.throwNow(ctx, "InvalidArgumentException", "array must contain only positive integer keys", .{});
                max = @max(max, @as(u64, @intCast(k)));
            },
        };
        if (max >= std.math.maxInt(u32)) return sic.throwNow(ctx, "InvalidArgumentException", "integer overflow detected", .{});
        for (0..max + 1) |_| try out.append(ctx.allocator, .null);
        for (data.entries.items) |e| {
            const v = if (e.ref) |r| r.* else e.value;
            try out.set(ctx.allocator, .{ .int = e.key.int }, v);
        }
    } else {
        for (data.entries.items) |e| try out.append(ctx.allocator, if (e.ref) |r| r.* else e.value);
    }
    const obj = try ctx.createObject("SplFixedArray");
    try obj.set(ctx.allocator, P.elements, .{ .array = out });
    try setResize(ctx, obj, -1);
    return NativeResult.borrowed(.{ .object = obj });
}

fn offsetExists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    if (!try sic.argCount(ctx, "SplFixedArray::offsetExists", args.len, 1, 1)) return error.RuntimeError;
    const index = (try offsetIndex(ctx, args[0])) orelse return error.RuntimeError;
    if (index >= sizeOf(obj)) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = elementAt(elementsOf(obj).?, @intCast(index)) != .null });
}

// spl_fixedarray_object_has_dimension for isset() and empty()
pub fn hasDimension(ctx: *NativeContext, obj: *PhpObject, offset: Value, check_empty: bool) RuntimeError!bool {
    const index = (try offsetIndex(ctx, offset)) orelse return error.RuntimeError;
    if (index >= sizeOf(obj)) return false;
    const v = elementAt(elementsOf(obj).?, @intCast(index));
    return if (check_empty) v.isTruthy() else v != .null;
}

fn offsetGet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    if (!try sic.argCount(ctx, "SplFixedArray::offsetGet", args.len, 1, 1)) return error.RuntimeError;
    if (appending(ctx)) return sic.throwNow(ctx, "Error", "[] operator not supported for SplFixedArray", .{});
    const index = (try offsetIndex(ctx, args[0])) orelse return error.RuntimeError;
    if (index >= sizeOf(obj)) {
        try outOfRange(ctx);
        return error.RuntimeError;
    }
    return NativeResult.share(elementAt(elementsOf(obj).?, @intCast(index)));
}

fn offsetSet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    if (!try sic.argCount(ctx, "SplFixedArray::offsetSet", args.len, 2, 2)) return error.RuntimeError;
    if (appending(ctx)) return sic.throwNow(ctx, "Error", "[] operator not supported for SplFixedArray", .{});
    const index = (try offsetIndex(ctx, args[0])) orelse return error.RuntimeError;
    if (index >= sizeOf(obj)) {
        try outOfRange(ctx);
        return error.RuntimeError;
    }
    const arr = try writable(ctx, obj);
    try arr.set(ctx.allocator, .{ .int = @intCast(index) }, args[1]);
    return NativeResult.scalar(.null);
}

fn offsetUnset(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    if (!try sic.argCount(ctx, "SplFixedArray::offsetUnset", args.len, 1, 1)) return error.RuntimeError;
    const index = (try offsetIndex(ctx, args[0])) orelse return error.RuntimeError;
    if (index >= sizeOf(obj)) {
        try outOfRange(ctx);
        return error.RuntimeError;
    }
    const arr = try writable(ctx, obj);
    try arr.set(ctx.allocator, .{ .int = @intCast(index) }, .null);
    return NativeResult.scalar(.null);
}

fn wakeup(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFixedArray::__wakeup", args);
    if (sizeOf(obj) != 0 or resizing(obj)) return NativeResult.scalar(.null);
    // the properties unserialize() set become the elements
    var listing = try object_properties.list(ctx.vm, obj, .array_cast, ctx.allocator);
    defer listing.deinit(ctx.allocator);
    defer object_properties.releaseHolder(ctx.vm, listing.takeHolder());
    const arr = try ctx.createArray();
    arr.uncounted = true;
    for (listing.items.items) |p| try arr.append(ctx.allocator, p.value);
    try obj.set(ctx.allocator, P.elements, .{ .array = arr });
    try setResize(ctx, obj, -1);
    for (listing.items.items) |p| switch (p.key) {
        .name => |n| if (obj.removeProperty(ctx.allocator, n)) |old| ctx.vm.releaseValue(old),
        .int => {},
    };
    return NativeResult.scalar(.null);
}

fn serializeM(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFixedArray::__serialize", args);
    const out = try ctx.createArray();
    if (elementsOf(obj)) |arr| for (0..arr.entries.items.len) |i| try out.append(ctx.allocator, elementAt(arr, i));
    const members = try @import("spl_dllist.zig").memberTable(ctx, obj);
    for (members.entries.items) |e| if (e.key == .string) try out.set(ctx.allocator, e.key, e.value);
    ctx.vm.releaseUnheldArray(members);
    return NativeResult.borrowed(.{ .array = out });
}

fn unserializeM(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplFixedArray::__unserialize";
    if (!try sic.argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    if (args[0] != .array) {
        try sic.typeError(ctx, label, 1, "data", "array", args[0]);
        return error.RuntimeError;
    }
    if (sizeOf(obj) != 0 or resizing(obj)) return NativeResult.scalar(.null);
    const arr = try ctx.createArray();
    arr.uncounted = true;
    const members = try ctx.createArray();
    for (args[0].array.entries.items) |e| {
        const v = if (e.ref) |r| r.* else e.value;
        if (e.key == .int) try arr.append(ctx.allocator, v) else try members.set(ctx.allocator, e.key, v);
    }
    try obj.set(ctx.allocator, P.elements, .{ .array = arr });
    try setResize(ctx, obj, -1);
    try @import("spl.zig").loadProperties(ctx, obj, members);
    return NativeResult.scalar(.null);
}

fn getIterator(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFixedArray::getIterator", args);
    // php's zend_object_iterator is an object of its own, made first and
    // freed with the InternalIterator holding it
    const iter = try ctx.vm.allocObject(.{ .class_name = "InternalIterator" });
    const it = try ctx.createObject("InternalIterator");
    try it.set(ctx.allocator, "__ii_iter", .{ .object = iter });
    try it.set(ctx.allocator, "__ii_target", .{ .object = obj });
    try it.set(ctx.allocator, "__ii_pos", .{ .int = 0 });
    try it.set(ctx.allocator, "__ii_index", .{ .int = 0 });
    try it.set(ctx.allocator, "__ii_rewound", .{ .bool = false });
    return NativeResult.borrowed(.{ .object = it });
}

// ==========================================
// debug view and clone
// ==========================================

// spl_fixedarray_object_get_properties_for: the elements, then the object's
// own properties
fn properties(ctx: *NativeContext, obj: *PhpObject, purpose: object_properties.Purpose) RuntimeError!?*PhpArray {
    if (purpose == .serialize) return null;
    const own = try object_properties.ownTable(ctx.vm, obj);
    const size = sizeOf(obj);
    if (size == 0 and own.length() == 0) return own;
    const t = try ctx.vm.allocArray();
    if (elementsOf(obj)) |arr| for (0..arr.entries.items.len) |i| try t.append(ctx.allocator, elementAt(arr, i));
    for (own.entries.items) |e| try t.set(ctx.allocator, e.key, e.value);
    ctx.vm.releaseUnheldArray(own);
    return t;
}

// foreach's own iterator (spl_fixedarray_get_iterator), kept on the loop's
// marker
pub fn iterRewind(ctx: *NativeContext, marker: *PhpObject) RuntimeError!void {
    try marker.set(ctx.allocator, "__fa_it_pos", .{ .int = 0 });
}

fn markerPos(marker: *PhpObject) i64 {
    const v = marker.get("__fa_it_pos");
    return if (v == .int) v.int else 0;
}

pub fn iterValid(obj: *PhpObject, marker: *PhpObject) bool {
    const pos = markerPos(marker);
    return pos >= 0 and pos < sizeOf(obj);
}

pub fn iterCurrent(ctx: *NativeContext, obj: *PhpObject, marker: *PhpObject) RuntimeError!Value {
    const pos = markerPos(marker);
    if (pos < 0 or pos >= sizeOf(obj)) {
        try outOfRange(ctx);
        return .null;
    }
    return elementAt(elementsOf(obj).?, @intCast(pos));
}

pub fn iterKey(marker: *PhpObject) Value {
    return .{ .int = markerPos(marker) };
}

pub fn iterNext(ctx: *NativeContext, marker: *PhpObject) RuntimeError!void {
    try marker.set(ctx.allocator, "__fa_it_pos", .{ .int = markerPos(marker) + 1 });
}

// ==========================================
// InternalIterator
// ==========================================

fn iiConstruct(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return sic.throwNow(ctx, "Error", "Cannot manually construct InternalIterator", .{});
}

const Ii = struct { it: *PhpObject, target: *PhpObject };

fn iiFetch(ctx: *NativeContext, label: []const u8, args: []const Value) RuntimeError!Ii {
    const it = try this(ctx);
    try noArgs(ctx, label, args);
    const t = it.get("__ii_target");
    if (t != .object) {
        try sic.raise(ctx, "Error", "The InternalIterator object has not been properly initialized", .{});
        return error.RuntimeError;
    }
    // zend_internal_iterator_ensure_rewound
    if (!(it.get("__ii_rewound") == .bool and it.get("__ii_rewound").bool)) {
        try it.set(ctx.allocator, "__ii_rewound", .{ .bool = true });
        try it.set(ctx.allocator, "__ii_pos", .{ .int = 0 });
    }
    return .{ .it = it, .target = t.object };
}

fn iiPos(it: *PhpObject) i64 {
    const v = it.get("__ii_pos");
    return if (v == .int) v.int else 0;
}

fn iiCurrent(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const ii = try iiFetch(ctx, "InternalIterator::current", args);
    const pos = iiPos(ii.it);
    if (pos < 0 or pos >= sizeOf(ii.target)) {
        try outOfRange(ctx);
        return error.RuntimeError;
    }
    return NativeResult.share(elementAt(elementsOf(ii.target).?, @intCast(pos)));
}

fn iiKey(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const ii = try iiFetch(ctx, "InternalIterator::key", args);
    return NativeResult.scalar(.{ .int = iiPos(ii.it) });
}

fn iiNext(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const ii = try iiFetch(ctx, "InternalIterator::next", args);
    try ii.it.set(ctx.allocator, "__ii_pos", .{ .int = iiPos(ii.it) + 1 });
    return NativeResult.scalar(.null);
}

fn iiValid(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const ii = try iiFetch(ctx, "InternalIterator::valid", args);
    const pos = iiPos(ii.it);
    return NativeResult.scalar(.{ .bool = pos >= 0 and pos < sizeOf(ii.target) });
}

fn iiRewind(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const ii = try iiFetch(ctx, "InternalIterator::rewind", args);
    try ii.it.set(ctx.allocator, "__ii_pos", .{ .int = 0 });
    return NativeResult.scalar(.null);
}
