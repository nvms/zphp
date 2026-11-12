// serialize() and unserialize(): ports of php's php_var_serialize_intern
// (ext/standard/var.c) and php_var_unserialize (var_unserializer.re). the
// reader follows the scanner's rules byte for byte, so a malformed string
// fails at the offset php reports, and back references (R: and r:) number
// the values as php's var_hash does
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const std = @import("std");
const object_properties = @import("../runtime/object_properties.zig");
const class_names = @import("../runtime/class_names.zig");
const types = @import("types.zig");
const value_mod = @import("../runtime/value.zig");
const serialization_generated = @import("serialization_generated.zig");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const ClassDef = @import("../runtime/vm.zig").ClassDef;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const VM = @import("../runtime/vm.zig").VM;
const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

const e_warning = 2;
const e_deprecated = 8192;

pub const entries = .{
    .{ "serialize", native_serialize },
    .{ "unserialize", native_unserialize },
};

// php refuses to serialize the internal classes whose state lives outside
// their properties (connections, handles, reflectors, dom nodes). the list
// php publishes is generated; zphp's own are below
pub const NotSerializable = enum { always, unless_methods };

const zphp_not_serializable = std.StaticStringMap(NotSerializable).initComptime(.{
    .{ "Zphp\\Pool", .always },
    .{ "Zphp\\Future", .always },
});

// the rule for this class or the nearest ancestor that has one
fn notSerializable(vm: *VM, class_name: []const u8) ?NotSerializable {
    // php marks every anonymous class ZEND_ACC_NOT_SERIALIZABLE
    if (class_names.isAnonymous(class_name)) return .always;
    var name: ?[]const u8 = class_name;
    while (name) |n| {
        if (serialization_generated.classes.get(n) orelse zphp_not_serializable.get(n)) |rule| return rule;
        name = (vm.classes.get(n) orelse return null).parent;
    }
    return null;
}

const Direction = enum { serialize, unserialize };

fn refuseNotSerializable(ctx: *NativeContext, class_name: []const u8, direction: Direction) RuntimeError!void {
    const rule = notSerializable(ctx.vm, class_name) orelse return;
    const verb = if (direction == .serialize) "Serialization" else "Unserialization";
    const shown = class_names.display(class_name);
    const msg = switch (rule) {
        .always => try std.fmt.allocPrint(ctx.allocator, "{s} of '{s}' is not allowed", .{ verb, shown }),
        .unless_methods => blk: {
            if (ctx.vm.hasMethod(class_name, if (direction == .serialize) "__serialize" else "__unserialize")) return;
            const methods = if (direction == .serialize) "serialization" else "unserialization";
            break :blk try std.fmt.allocPrint(ctx.allocator, "{s} of '{s}' is not allowed, unless {s} methods are implemented in a subclass", .{ verb, shown, methods });
        },
    };
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("Exception", msg);
    return error.RuntimeError;
}

// php_error_docref's warning: the running internal function's name first
fn docref(ctx: *NativeContext, level: i64, comptime fmt: []const u8, args: anytype) RuntimeError!void {
    const label: []const u8 = if (ctx.vm.native_call) |call| call.label else "unserialize";
    const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): " ++ fmt, .{label} ++ args);
    defer ctx.allocator.free(msg);
    try ctx.vm.raiseError(level, msg);
}

// zend_error: no function name
fn plainError(ctx: *NativeContext, level: i64, comptime fmt: []const u8, args: anytype) RuntimeError!void {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    try ctx.vm.raiseError(level, msg);
}

const incomplete_class = "__PHP_Incomplete_Class";
const magic_member = "__PHP_Incomplete_Class_Name";

fn isIncomplete(obj: *PhpObject) bool {
    return std.mem.eql(u8, obj.class_name, incomplete_class);
}

// php's BG(serialize) and BG(unserialize): a serialize() nested in a
// Serializable::serialize() method shares the outer call's table, so the
// values the outer call has written are back references there; the same
// for unserialize() in Serializable::unserialize(). __serialize, __sleep,
// __unserialize and __wakeup run under serialize_lock, where a nested call
// starts a table of its own
threadlocal var shared_ctx: ?*SerCtx = null;
threadlocal var serialize_lock: u32 = 0;
threadlocal var shared_uctx: ?*UnserCtx = null;
// ======================================================================
// serialize
// ======================================================================

// php's php_serialize_data: the slot number each recorded value took, keyed
// by the object or reference cell; -1 marks an object whose Serializable
// method failed, which later references write as N;
const SerCtx = struct {
    seen: std.AutoHashMapUnmanaged(usize, i64) = .{},
    // the table keeps the objects it records alive until the outermost
    // serialize() ends, as php's does, so a temporary written by a nested
    // Serializable::serialize() can't be freed and its address reused
    kept: std.ArrayListUnmanaged(*PhpObject) = .empty,
    // arrays being written, with the object depth each was entered at, to
    // stop on an array that contains itself with no reference or object in
    // between (php can't build one; zphp aliasing can)
    open_arrays: std.AutoHashMapUnmanaged(*PhpArray, u32) = .{},
    object_depth: u32 = 0,
    n: i64 = 0,
    // the value serialize() was called with, and the references its native
    // call holds to it, which php's refcount doesn't see
    call_value: ?*PhpObject = null,
    call_holds: u32 = 0,

    fn deinit(self: *SerCtx, ctx: *NativeContext) void {
        const a = ctx.allocator;
        for (self.kept.items) |obj| ctx.vm.objRelease(obj);
        self.kept.deinit(a);
        self.seen.deinit(a);
        self.open_arrays.deinit(a);
    }
};

// how a value is reached: through a reference cell another holder shares
// (php's IS_REFERENCE with refcount above 1), or directly
const Via = struct {
    cell: ?*Value = null,
};

fn objectRecorded(ctx: *NativeContext, sctx: *SerCtx, obj: *PhpObject, in_rcn_array: bool) bool {
    if (in_rcn_array) return true;
    const holds: u32 = if (sctx.call_value == obj) sctx.call_holds else 0;
    if (obj.refcount -| holds > 1) return true;
    // __serialize and __sleep may hand the object out again
    return ctx.vm.hasMethod(obj.class_name, "__serialize") or ctx.vm.hasMethod(obj.class_name, "__sleep");
}

// php_add_var_hash: the slot a value already took, or 0 after recording it
fn addVarHash(ctx: *NativeContext, sctx: *SerCtx, val: Value, via: Via, in_rcn_array: bool) RuntimeError!i64 {
    sctx.n += 1;
    const is_ref = via.cell != null;
    if (!is_ref) {
        if (val != .object) return 0;
        if (!objectRecorded(ctx, sctx, val.object.storage(), in_rcn_array)) return 0;
    }
    // a reference to an object is keyed by the object
    const key: usize = if (val == .object) @intFromPtr(val.object.storage()) else @intFromPtr(via.cell.?);
    if (sctx.seen.get(key)) |idx| {
        if (is_ref and idx != -1) sctx.n -= 1;
        return idx;
    }
    try sctx.seen.put(ctx.allocator, key, sctx.n);
    if (val == .object) {
        VM.objRetain(val.object.storage());
        try sctx.kept.append(ctx.allocator, val.object.storage());
    }
    return 0;
}

fn native_serialize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // invokeNative holds each argument twice for the call (a retain and an
    // operand-stack hold); php's argument is one reference
    return try serializeWith(ctx, args[0], 1);
}

pub fn serializeToString(ctx: *NativeContext, val: Value) RuntimeError!NativeResult {
    return serializeWith(ctx, val, 0);
}

// `call_holds`: the references the native call that received `val` holds to
// it beyond the one php's argument has
fn serializeWith(ctx: *NativeContext, val: Value, call_holds: u32) RuntimeError!NativeResult {
    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);
    var own = SerCtx{};
    defer own.deinit(ctx);
    const outer = if (serialize_lock == 0) shared_ctx else null;
    const sctx = outer orelse &own;
    const owner = outer == null and serialize_lock == 0;
    if (owner) shared_ctx = &own;
    defer if (owner) {
        shared_ctx = null;
    };
    const outer_value = sctx.call_value;
    const outer_holds = sctx.call_holds;
    sctx.call_value = if (val == .object) val.object.storage() else null;
    sctx.call_holds = call_holds;
    defer {
        sctx.call_value = outer_value;
        sctx.call_holds = outer_holds;
    }
    try serializeValue(ctx, &buf, sctx, val, .{}, false, true);
    if (ctx.vm.pending_exception != null) return error.RuntimeError;
    return NativeResult.copyString(ctx.allocator, buf.items);
}

// php_var_serialize as a Serializable::serialize() method calls it: values
// written one after another, sharing the reference table of the serialize()
// call that is running (BG(serialize)), or a table of their own
pub const Writer = struct {
    ctx: *NativeContext,
    buf: std.ArrayListUnmanaged(u8) = .empty,
    own: SerCtx = .{},
    owner: bool = false,
    outer: ?*SerCtx = null,

    // call on the writer's final address
    pub fn begin(self: *Writer) void {
        self.outer = if (serialize_lock == 0) shared_ctx else null;
        self.owner = self.outer == null and serialize_lock == 0;
        if (self.owner) shared_ctx = &self.own;
    }

    fn sctx(self: *Writer) *SerCtx {
        return self.outer orelse &self.own;
    }

    pub fn value(self: *Writer, v: Value) RuntimeError!void {
        try serializeValue(self.ctx, &self.buf, self.sctx(), v, .{}, false, true);
        if (self.ctx.vm.pending_exception != null) return error.RuntimeError;
    }

    pub fn raw(self: *Writer, bytes: []const u8) RuntimeError!void {
        try self.buf.appendSlice(self.ctx.allocator, bytes);
    }

    // the written string, which the caller takes
    pub fn finish(self: *Writer) RuntimeError!NativeResult {
        return NativeResult.copyString(self.ctx.allocator, self.buf.items);
    }

    pub fn deinit(self: *Writer) void {
        if (self.owner) shared_ctx = null;
        self.own.deinit(self.ctx);
        self.buf.deinit(self.ctx.allocator);
    }
};

fn writeLong(buf: *std.ArrayListUnmanaged(u8), a: Allocator, i: i64) !void {
    try buf.print(a, "i:{d};", .{i});
}

fn writeString(buf: *std.ArrayListUnmanaged(u8), a: Allocator, s: []const u8) !void {
    try buf.print(a, "s:{d}:\"", .{s.len});
    try buf.appendSlice(a, s);
    try buf.appendSlice(a, "\";");
}

fn writeKey(buf: *std.ArrayListUnmanaged(u8), a: Allocator, key: PhpArray.Key) !void {
    switch (key) {
        .int => |i| try writeLong(buf, a, i),
        .string => |s| try writeString(buf, a, s.bytes()),
    }
}

// the reference cell another holder shares with an array element
fn sharedEntryCell(entry: PhpArray.Entry) ?*Value {
    const cell = entry.ref orelse return null;
    return if (value_mod.cellOf(cell).binders > 1) cell else null;
}

fn entryValue(entry: PhpArray.Entry) Value {
    return if (entry.ref) |cell| cell.* else entry.value;
}

// the reference cell another holder shares with a property
fn sharedPropertyCell(ctx: *NativeContext, obj: *PhpObject, name: []const u8) ?*Value {
    const index = ctx.vm.ref_index orelse return null;
    const cells = index.prop_rev.get(.{ .object = obj, .class_name = "", .prop_name = name }) orelse return null;
    for (cells.items) |cell| {
        var holders = value_mod.cellOf(cell).binders;
        if (ctx.vm.last_return_ref == cell) holders -|= 1;
        if (holders > 1) return cell;
    }
    return null;
}

// the mangled name php's property tables use
fn mangledName(a: Allocator, name: []const u8, visibility: ClassDef.Visibility, declaring: []const u8) ![]u8 {
    return switch (visibility) {
        .public => a.dupe(u8, name),
        .protected => std.fmt.allocPrint(a, "\x00*\x00{s}", .{name}),
        .private => std.fmt.allocPrint(a, "\x00{s}\x00{s}", .{ declaring, name }),
    };
}

// php_var_serialize_nested_data over an array's elements
fn serializeArrayBody(ctx: *NativeContext, buf: *std.ArrayListUnmanaged(u8), sctx: *SerCtx, arr: *PhpArray, in_rcn_array: bool) RuntimeError!void {
    const a = ctx.allocator;
    try buf.print(a, "{d}:{{", .{arr.entries.items.len});
    var i: usize = 0;
    while (i < arr.entries.items.len) : (i += 1) {
        const entry = arr.entries.items[i];
        try writeKey(buf, a, entry.key);
        const cell = sharedEntryCell(entry);
        const v = entryValue(entry);
        // an element that is the array itself, without a reference
        if (cell == null and v == .array and v.array == arr) {
            _ = try addVarHash(ctx, sctx, v, .{}, in_rcn_array);
            try buf.appendSlice(a, "N;");
            continue;
        }
        try serializeValue(ctx, buf, sctx, v, .{ .cell = cell }, in_rcn_array, false);
        if (ctx.vm.pending_exception != null) return;
    }
    try buf.append(a, '}');
}

fn serializeValue(ctx: *NativeContext, buf: *std.ArrayListUnmanaged(u8), sctx: *SerCtx, val_in: Value, via: Via, in_rcn_array: bool, is_root: bool) RuntimeError!void {
    const a = ctx.allocator;
    if (ctx.vm.pending_exception != null) return;
    var val = val_in;
    if (val == .object and val.object.lazy != null) {
        if (!val.object.lazy.?.skip_serialize) try ctx.vm.triggerLazyInit(val.object);
        val = .{ .object = val.object.storage() };
    }
    const already = try addVarHash(ctx, sctx, val, via, in_rcn_array);
    if (already != 0) {
        if (already == -1) {
            try buf.appendSlice(a, "N;");
        } else if (via.cell != null) {
            try buf.print(a, "R:{d};", .{already});
        } else if (val == .object) {
            try buf.print(a, "r:{d};", .{already});
        }
        if (already == -1 or via.cell != null or val == .object) return;
    }
    switch (val) {
        .null, .undef => try buf.appendSlice(a, "N;"),
        .bool => |b| try buf.appendSlice(a, if (b) "b:1;" else "b:0;"),
        .int => |i| try writeLong(buf, a, i),
        .float => |f| {
            const sp = value_mod.hooks().serialize_precision;
            var tmp: [1100]u8 = undefined;
            const text = @import("formatted_print.zig").gcvt(f, sp, '.', 'E', &tmp);
            try buf.print(a, "d:{s};", .{text});
        },
        .string => |s| try writeString(buf, a, s.bytes()),
        .array => |arr| {
            // through a reference the array is written again (the reference
            // repeats as R: inside it); without one php can't meet it twice
            const entered = sctx.open_arrays.get(arr);
            if (via.cell == null) if (entered) |depth| if (depth == sctx.object_depth) {
                try buf.appendSlice(a, "N;");
                return;
            };
            try sctx.open_arrays.put(a, arr, sctx.object_depth);
            defer if (entered) |depth| {
                sctx.open_arrays.putAssumeCapacity(arr, depth);
            } else {
                _ = sctx.open_arrays.remove(arr);
            };
            try buf.appendSlice(a, "a:");
            try serializeArrayBody(ctx, buf, sctx, arr, !is_root and (in_rcn_array or arr.refcount > 1));
        },
        .object => |obj| {
            sctx.object_depth += 1;
            defer sctx.object_depth -= 1;
            try serializeObject(ctx, buf, sctx, obj);
        },
        .generator, .fiber => refuseNotSerializable(ctx, if (val == .generator) "Generator" else "Fiber", .serialize) catch |err| {
            if (err == error.OutOfMemory) return err;
        },
        // php writes a resource as int 0
        .resource => try buf.appendSlice(a, "i:0;"),
    }
}

fn writeClassHeader(buf: *std.ArrayListUnmanaged(u8), a: Allocator, name: []const u8) !void {
    try buf.print(a, "O:{d}:\"", .{name.len});
    try buf.appendSlice(a, name);
    try buf.appendSlice(a, "\":");
}

fn serializeObject(ctx: *NativeContext, buf: *std.ArrayListUnmanaged(u8), sctx: *SerCtx, obj: *PhpObject) RuntimeError!void {
    const a = ctx.allocator;
    const class_name = obj.class_name;
    refuseNotSerializable(ctx, class_name, .serialize) catch |err| {
        if (err == error.OutOfMemory) return err;
        return;
    };
    if (ctx.vm.classes.get(class_name)) |cdef| if (cdef.is_enum) {
        const case_name = obj.get("name");
        const cn = if (case_name == .string) case_name.string.bytes() else "";
        try buf.print(a, "E:{d}:\"{s}:{s}\";", .{ class_name.len + 1 + cn.len, class_name, cn });
        return;
    };
    // SplFixedArray: its elements as integer-keyed properties
    if (std.mem.eql(u8, class_name, "SplFixedArray")) {
        const data = obj.get("__data");
        if (data == .array) {
            try writeClassHeader(buf, a, class_name);
            try buf.print(a, "{d}:{{", .{data.array.entries.items.len});
            for (data.array.entries.items, 0..) |entry, i| {
                try writeLong(buf, a, @intCast(i));
                try serializeValue(ctx, buf, sctx, entryValue(entry), .{}, false, false);
            }
            try buf.append(a, '}');
            return;
        }
    }
    if (ctx.vm.hasMethod(class_name, "__serialize")) {
        VM.objRetain(obj);
        defer ctx.vm.objRelease(obj);
        serialize_lock += 1;
        const result = ctx.vm.callMethod(obj, "__serialize", &.{}) catch |err| {
            serialize_lock -= 1;
            if (err == error.OutOfMemory) return err;
            return;
        };
        serialize_lock -= 1;
        VM.retainValue(result);
        defer ctx.vm.releaseValue(result);
        if (ctx.vm.pending_exception != null) return;
        if (result != .array) {
            const msg = try std.fmt.allocPrint(a, "{s}::__serialize() must return an array", .{class_names.display(class_name)});
            defer a.free(msg);
            try ctx.vm.setPendingException("TypeError", msg);
            return;
        }
        try writeClassHeader(buf, a, class_name);
        try serializeArrayBody(ctx, buf, sctx, result.array, result.array.refcount > 1);
        return;
    }
    // Serializable::serialize(): a string becomes the C: payload, null an N;
    // that later references to the object repeat
    if (ctx.vm.isInstanceOf(class_name, "Serializable") and ctx.vm.hasMethod(class_name, "serialize")) {
        const result = ctx.vm.callMethod(obj, "serialize", &.{}) catch |err| {
            if (err == error.OutOfMemory) return err;
            try markFailed(ctx, sctx, obj);
            try buf.appendSlice(a, "N;");
            return;
        };
        VM.retainValue(result);
        defer ctx.vm.releaseValue(result);
        if (ctx.vm.pending_exception == null and result != .string and result != .null) {
            const msg = try std.fmt.allocPrint(a, "{s}::serialize() must return a string or NULL", .{class_names.display(class_name)});
            defer a.free(msg);
            try ctx.vm.setPendingException("Exception", msg);
        }
        if (result != .string or ctx.vm.pending_exception != null) {
            try markFailed(ctx, sctx, obj);
            try buf.appendSlice(a, "N;");
            return;
        }
        const payload = result.string.bytes();
        try buf.print(a, "C:{d}:\"{s}\":{d}:{{", .{ class_name.len, class_name, payload.len });
        try buf.appendSlice(a, payload);
        try buf.append(a, '}');
        return;
    }
    const incomplete = isIncomplete(obj);
    if (!incomplete and ctx.vm.hasMethod(class_name, "__sleep")) {
        VM.objRetain(obj);
        defer ctx.vm.objRelease(obj);
        serialize_lock += 1;
        const result = ctx.vm.callMethod(obj, "__sleep", &.{}) catch |err| {
            serialize_lock -= 1;
            if (err == error.OutOfMemory) return err;
            return;
        };
        serialize_lock -= 1;
        VM.retainValue(result);
        defer ctx.vm.releaseValue(result);
        if (ctx.vm.pending_exception != null) return;
        if (result != .array) {
            try docrefSerialize(ctx, "{s}::__sleep() should return an array only containing the names of instance-variables to serialize", .{class_names.display(class_name)});
            try buf.appendSlice(a, "N;");
            return;
        }
        return serializeSleepProps(ctx, buf, sctx, obj, result.array);
    }

    // the property table, as php_var_serialize_class_name and
    // php_var_serialize_nested_data write it: an incomplete object under
    // the name it was read with, less the member that holds that name
    var shown_name = class_name;
    if (incomplete) {
        const stored = obj.get(magic_member);
        if (stored == .string) shown_name = stored.string.bytes();
    }
    var listing = try object_properties.list(ctx.vm, obj, .serialize, a);
    defer listing.deinit(a);
    var count: usize = 0;
    for (listing.items.items) |prop| {
        if (prop.uninitialized != null) continue;
        if (incomplete and prop.key == .name and std.mem.eql(u8, prop.key.name, magic_member)) continue;
        count += 1;
    }
    try writeClassHeader(buf, a, shown_name);
    try buf.print(a, "{d}:{{", .{count});
    for (listing.items.items) |prop| {
        if (prop.uninitialized != null) continue;
        switch (prop.key) {
            .int => |i| try writeLong(buf, a, i),
            .name => |name| {
                if (incomplete and std.mem.eql(u8, name, magic_member)) continue;
                const declaring = if (prop.declaring.len > 0) prop.declaring else class_name;
                const key = try mangledName(a, name, prop.visibility, declaring);
                defer a.free(key);
                try writeString(buf, a, key);
            },
        }
        const cell = switch (prop.key) {
            .name => |name| sharedPropertyCell(ctx, obj, name),
            .int => null,
        };
        try serializeValue(ctx, buf, sctx, if (cell) |c| c.* else prop.value, .{ .cell = cell }, false, false);
        if (ctx.vm.pending_exception != null) return;
    }
    try buf.append(a, '}');
}

fn markFailed(ctx: *NativeContext, sctx: *SerCtx, obj: *PhpObject) !void {
    if (sctx.seen.getPtr(@intFromPtr(obj))) |idx| idx.* = -1;
    _ = ctx;
}

fn docrefSerialize(ctx: *NativeContext, comptime fmt: []const u8, args: anytype) RuntimeError!void {
    const msg = try std.fmt.allocPrint(ctx.allocator, "serialize(): " ++ fmt, args);
    defer ctx.allocator.free(msg);
    try ctx.vm.emitWarning(msg);
}

// a typed property __sleep names that holds no value (uninitialized, or a
// lazy object's pending one), which php leaves out without a warning
fn sleepSkips(vm: *VM, obj: *PhpObject, name: []const u8) bool {
    const decl = vm.propertyDeclaration(obj.class_name, name);
    if (!decl.declared or decl.type_str.len == 0) return false;
    if (obj.isLazySlot(name, decl.defining_class)) return true;
    return obj.rawForScope(name, decl.defining_class) == .undef;
}

const SleepProp = struct { key: []u8, value: Value, cell: ?*Value };

// php_var_serialize_get_sleep_props: each name __sleep returned, found as
// a public, then a private of the object's class, then a protected
// property; a typed one never initialized is left out quietly
fn serializeSleepProps(ctx: *NativeContext, buf: *std.ArrayListUnmanaged(u8), sctx: *SerCtx, obj: *PhpObject, names: *PhpArray) RuntimeError!void {
    const a = ctx.allocator;
    const class_name = obj.class_name;
    var listing = try object_properties.list(ctx.vm, obj, .serialize, a);
    defer listing.deinit(a);
    var props: std.ArrayListUnmanaged(SleepProp) = .empty;
    defer {
        for (props.items) |p| a.free(p.key);
        props.deinit(a);
    }
    for (names.entries.items) |entry| {
        const name_val = entryValue(entry);
        if (name_val != .string) try docrefSerialize(ctx, "{s}::__sleep() should return an array only containing the names of instance-variables to serialize", .{class_names.display(class_name)});
        var tmp: [64]u8 = undefined;
        const name: []const u8 = switch (name_val) {
            .string => |s| s.bytes(),
            .int => |i| std.fmt.bufPrint(&tmp, "{d}", .{i}) catch unreachable,
            .null => "",
            else => try @import("strings.zig").coerceToString(ctx, name_val),
        };
        const forms = [_]ClassDef.Visibility{ .public, .private, .protected };
        var found = false;
        for (forms) |vis| {
            const want = try mangledName(a, name, vis, class_name);
            defer a.free(want);
            // the property table entry under that mangled name
            const hit: ?object_properties.Property = for (listing.items.items) |prop| {
                if (prop.key != .name) continue;
                const declaring = if (prop.declaring.len > 0) prop.declaring else class_name;
                const key = try mangledName(a, prop.key.name, prop.visibility, declaring);
                defer a.free(key);
                if (std.mem.eql(u8, key, want)) break prop;
            } else null;
            const prop = hit orelse continue;
            found = true;
            if (prop.uninitialized != null) break;
            const repeated = for (props.items) |p| {
                if (std.mem.eql(u8, p.key, want)) break true;
            } else false;
            if (repeated) {
                try docrefSerialize(ctx, "\"{s}\" is returned from __sleep() multiple times", .{name});
            } else {
                const cell = sharedPropertyCell(ctx, obj, prop.key.name);
                try props.append(a, .{ .key = try a.dupe(u8, want), .value = prop.value, .cell = cell });
            }
            break;
        }
        if (ctx.vm.pending_exception != null) return;
        if (!found and !sleepSkips(ctx.vm, obj, name)) try docrefSerialize(ctx, "\"{s}\" returned as member variable from __sleep() but does not exist", .{name});
    }
    try writeClassHeader(buf, a, class_name);
    try buf.print(a, "{d}:{{", .{props.items.len});
    for (props.items) |p| {
        try writeString(buf, a, p.key);
        try serializeValue(ctx, buf, sctx, if (p.cell) |c| c.* else p.value, .{ .cell = p.cell }, false, false);
        if (ctx.vm.pending_exception != null) return;
    }
    try buf.append(a, '}');
}
// ======================================================================
// unserialize
// ======================================================================

// where a value is read into, which a later R: or r: names by its slot
// number (php's var_push keeps the zval's address)
const Loc = union(enum) {
    // a slot php cleared after a nested read failed
    none,
    // a value the reader holds itself: unserialize()'s result, a value a
    // Serializable::unserialize() reads, an array key
    temp: *Temp,
    element: struct { array: *PhpArray, key: PhpArray.Key },
    property: struct { obj: *PhpObject, name: []const u8, scope: ?[]const u8, type_str: []const u8 = "", defining: []const u8 = "" },
};

const Temp = struct {
    value: Value = .null,
    // the reference an R: made of it
    cell: ?*Value = null,
};

const Delayed = struct { obj: *PhpObject, data: ?*PhpArray };

const UnserCtx = struct {
    slots: std.ArrayListUnmanaged(Loc) = .empty,
    temps: std.ArrayListUnmanaged(*Temp) = .empty,
    // lowercased names; null takes every class
    allowed: ?std.StringHashMapUnmanaged(void) = null,
    max_depth: i64 = 4096,
    cur_depth: i64 = 0,
    // php delays each __unserialize() and __wakeup() until the whole
    // string is read, even when reading fails (var_destroy)
    delayed: std.ArrayListUnmanaged(Delayed) = .empty,
    // what nested reads returned, which php keeps in the table (var_tmp_var)
    // so a later back reference into it finds it alive
    kept: std.ArrayListUnmanaged(Value) = .empty,

    fn deinit(self: *UnserCtx, a: Allocator) void {
        self.slots.deinit(a);
        for (self.temps.items) |t| a.destroy(t);
        self.temps.deinit(a);
        if (self.allowed) |*m| {
            var it = m.keyIterator();
            while (it.next()) |k| a.free(k.*);
            m.deinit(a);
        }
        self.delayed.deinit(a);
        self.kept.deinit(a);
    }

    fn keep(self: *UnserCtx, a: Allocator, v: Value) !void {
        if (v != .array and v != .object and v != .string) return;
        try self.kept.append(a, v);
        VM.retainValue(v);
    }

    fn temp(self: *UnserCtx, a: Allocator) !*Temp {
        const t = try a.create(Temp);
        t.* = .{};
        errdefer a.destroy(t);
        try self.temps.append(a, t);
        return t;
    }
};

// the cursor over the string being read; php's `p`, which every nested
// read moves, so a failure reports where the innermost one stopped
const Scan = struct {
    s: []const u8,
    p: usize,

    fn at(self: *const Scan, i: usize) u8 {
        return if (i < self.s.len) self.s[i] else 0;
    }
};

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

// the end of [0-9]+ at i, or null when there is no digit
fn digitsEnd(sc: *const Scan, i: usize) ?usize {
    var j = i;
    while (j < sc.s.len and isDigit(sc.s[j])) j += 1;
    return if (j == i) null else j;
}

// iv = [+-]? [0-9]+
fn ivEnd(sc: *const Scan, i: usize) ?usize {
    var j = i;
    if (sc.at(j) == '+' or sc.at(j) == '-') j += 1;
    return digitsEnd(sc, j);
}

// the end of iv, nv or nvexp at i, longest first
fn numberEnd(sc: *const Scan, i: usize) ?usize {
    var j = i;
    if (sc.at(j) == '+' or sc.at(j) == '-') j += 1;
    const int_end = digitsEnd(sc, j);
    var end: ?usize = int_end;
    // nv: [0-9]* "." [0-9]+ | [0-9]+ "." [0-9]*
    const dot = int_end orelse j;
    if (sc.at(dot) == '.') {
        const frac_end = digitsEnd(sc, dot + 1);
        if (frac_end) |f| end = f else if (int_end != null) end = dot + 1;
    }
    const mant = end orelse return null;
    if (sc.at(mant) == 'e' or sc.at(mant) == 'E') {
        if (ivEnd(sc, mant + 1)) |e| return e;
    }
    return mant;
}

// parse_iv2: a signed decimal that warns and saturates past the range
fn parseIv(ctx: *NativeContext, sc: *const Scan, start: usize, end_out: ?*usize) RuntimeError!i64 {
    var i = start;
    var neg = false;
    if (sc.at(i) == '-') {
        neg = true;
        i += 1;
    } else if (sc.at(i) == '+') {
        i += 1;
    }
    while (sc.at(i) == '0') i += 1;
    const digits_start = i;
    var result: u64 = 0;
    var overflow = false;
    while (i < sc.s.len and isDigit(sc.s[i])) : (i += 1) {
        const m = @mulWithOverflow(result, 10);
        const ad = @addWithOverflow(m[0], @as(u64, sc.s[i] - '0'));
        if (m[1] != 0 or ad[1] != 0) overflow = true;
        result = ad[0];
    }
    if (end_out) |e| e.* = i;
    const limit: u64 = @as(u64, std.math.maxInt(i64)) + @intFromBool(neg);
    if (i - digits_start > 19 or overflow or result > limit) {
        try docref(ctx, e_warning, "Numerical result out of range", .{});
        return if (neg) std.math.minInt(i64) else std.math.maxInt(i64);
    }
    if (neg) return if (result == @as(u64, std.math.maxInt(i64)) + 1) std.math.minInt(i64) else -@as(i64, @intCast(result));
    return @intCast(result);
}

// parse_uiv: digits as a size_t, wrapping like c
fn parseUiv(sc: *const Scan, start: usize) usize {
    var result: usize = 0;
    var i = start;
    while (i < sc.s.len and isDigit(sc.s[i])) : (i += 1) result = result *% 10 +% (sc.s[i] - '0');
    return result;
}

// zend_is_valid_class_name: 0-9 a-z A-Z _ \ and bytes from 0x80
fn validClassName(name: []const u8) bool {
    for (name) |c| {
        if (!(std.ascii.isAlphanumeric(c) or c == '_' or c == '\\' or c >= 0x80)) return false;
    }
    return true;
}

fn stringValue(ctx: *NativeContext, bytes: []const u8) !Value {
    return .{ .string = try Value.String.create(ctx.allocator, bytes) };
}

// the value a location holds now
fn locValue(loc: Loc) Value {
    return switch (loc) {
        .none => .null,
        .temp => |t| if (t.cell) |c| c.* else t.value,
        .element => |e| blk: {
            const entry = e.array.getPtr(e.key) orelse break :blk .null;
            break :blk entryValue(entry.*);
        },
        .property => |p| p.obj.getForScope(p.name, p.scope),
    };
}

// stores a freshly read value; a string's creation reference passes to it
fn storeLoc(ctx: *NativeContext, loc: Loc, v: Value) RuntimeError!void {
    switch (loc) {
        .none => {},
        .temp => |t| t.value = v,
        .element => |e| {
            defer if (v == .string) v.string.release();
            if (e.array.getPtr(e.key)) |entry| if (entry.ref) |cell| {
                ctx.vm.setCell(cell, v);
                return;
            };
            try e.array.set(ctx.allocator, e.key, v);
        },
        .property => |p| {
            defer if (v == .string) v.string.release();
            try p.obj.setForScope(ctx.allocator, p.name, v, p.scope);
        },
    }
}

// the reference cell a location shares, made a reference when it is none
fn locCell(ctx: *NativeContext, loc: Loc) RuntimeError!*Value {
    switch (loc) {
        .none => unreachable,
        .temp => |t| {
            if (t.cell) |c| return c;
            const cell = try ctx.vm.newReferenceCell(t.value);
            t.cell = cell;
            return cell;
        },
        .element => |e| {
            const entry = e.array.getPtr(e.key).?;
            if (entry.ref) |cell| return cell;
            const cell = try ctx.vm.newReferenceCell(entry.value);
            try bindElement(ctx, e.array, e.key, cell);
            return cell;
        },
        .property => |p| return ctx.vm.propertyReferenceCell(p.obj, p.name, p.scope),
    }
}

// an array element joining a reference set, registered with the vm's
// reference index as `$a[k] = &$r` registers it
fn bindElement(ctx: *NativeContext, arr: *PhpArray, key: PhpArray.Key, cell: *Value) RuntimeError!void {
    if (arr.getPtr(key)) |entry| if (entry.ref == cell) return;
    ctx.vm.detachArrayEntryRef(arr, key);
    try arr.set(ctx.allocator, key, cell.*);
    const entry = arr.getPtr(key) orelse return;
    ctx.vm.setEntryRef(entry, cell);
    if (ctx.vm.ref_index == null) {
        const index = try ctx.allocator.create(value_mod.RefIndex);
        index.* = .{};
        ctx.vm.ref_index = index;
    }
    const index = ctx.vm.ref_index.?;
    if (ctx.vm.persistent_ref_owner == 0) ctx.vm.persistent_ref_owner = index.createOwner();
    try ctx.vm.array_ref_bindings.append(ctx.allocator, .{ .cell = cell, .array = arr, .key = entry.key });
    try index.addOwned(ctx.allocator, ctx.vm.persistent_ref_owner, cell, .{ .array = .{ .array = arr, .key = entry.key } });
    ctx.vm.array_ref_active = true;
}

// a location becoming one more holder of a reference
fn bindLoc(ctx: *NativeContext, loc: Loc, cell: *Value) RuntimeError!void {
    switch (loc) {
        .none => {},
        .temp => |t| {
            t.value = cell.*;
            t.cell = cell;
        },
        .element => |e| try bindElement(ctx, e.array, e.key, cell),
        .property => |p| try ctx.vm.bindPropertyToCell(p.obj, p.name, cell),
    }
}

// zend_verify_prop_assignable_by_ref for a typed property an R: points at
// another slot, strictly: a value the type refuses outright, or one only a
// coercion the reference's own typed property forbids would fit
fn typedReferenceFits(ctx: *NativeContext, target: Loc, dest: Loc) RuntimeError!bool {
    const d = dest.property;
    const v = locValue(target);
    if (try ctx.vm.unserializedPropertyFits(v, d.type_str, d.defining)) return true;
    const a = ctx.allocator;
    const type_text = try ctx.vm.propertyTypeText(d.type_str, d.defining);
    // strictly, only an int a float type would take is a conflict of coercions
    const php_types = @import("../pipeline/php_types.zig");
    const conflict = v == .int and php_types.shape(d.type_str).mask & php_types.DOUBLE != 0;
    const msg = if (target == .property and target.property.type_str.len > 0 and conflict) blk: {
        const t = target.property;
        const source_type = try ctx.vm.propertyTypeText(t.type_str, t.defining);
        break :blk try std.fmt.allocPrint(a, "Reference with value of type {s} held by property {s}::${s} of type {s} is not compatible with property {s}::${s} of type {s}", .{ types.phpTypeName(v), class_names.display(t.defining), t.name, source_type, class_names.display(d.defining), d.name, type_text });
    } else try std.fmt.allocPrint(a, "Cannot assign {s} to property {s}::${s} of type {s}", .{ types.phpTypeName(v), class_names.display(d.defining), d.name, type_text });
    defer a.free(msg);
    try ctx.vm.setPendingException("TypeError", msg);
    return false;
}

fn sameLoc(a: Loc, b: Loc) bool {
    return switch (a) {
        .none => b == .none,
        .temp => |t| b == .temp and b.temp == t,
        .element => |e| b == .element and b.element.array == e.array and b.element.key.eql(e.key),
        .property => |p| b == .property and b.property.obj == p.obj and std.mem.eql(u8, b.property.name, p.name),
    };
}

// php_var_unserialize: a read whose failure clears the slots it pushed, so
// no later read in the same table can name them
fn readTop(ctx: *NativeContext, u: *UnserCtx, sc: *Scan, dest: Loc) RuntimeError!bool {
    const first = u.slots.items.len;
    const ok = try read(ctx, u, sc, dest);
    if (!ok) for (u.slots.items[first..]) |*slot| {
        slot.* = .none;
    };
    return ok;
}

// php_var_unserialize_internal: reads one value at sc.p into dest. false is
// a failure (sc.p where php's scanner stopped; an exception may be pending)
fn read(ctx: *NativeContext, u_opt: ?*UnserCtx, sc: *Scan, dest: Loc) RuntimeError!bool {
    const start = sc.p;
    if (start >= sc.s.len) return false;
    const c0 = sc.s[start];
    if (u_opt) |u| if (c0 != 'R') try u.slots.append(ctx.allocator, dest);
    const c1 = sc.at(start + 1);
    switch (c0) {
        'R', 'r' => {
            if (c1 != ':') return false;
            const de = digitsEnd(sc, start + 2) orelse return false;
            if (sc.at(de) != ';') return false;
            sc.p = de + 1;
            const u = u_opt orelse return false;
            const id = parseUiv(sc, start + 2);
            if (id == 0 or id > u.slots.items.len) return false;
            const target = u.slots.items[id - 1];
            if (target == .none) return false;
            if (c0 == 'R') {
                if (sameLoc(target, dest)) return false;
                if (dest == .property and dest.property.type_str.len > 0) {
                    if (!try typedReferenceFits(ctx, target, dest)) return false;
                }
                const cell = try locCell(ctx, target);
                // the value is the slot php's ZVAL_COPY makes the new holder
                if (dest == .element) {
                    if (dest.element.array.getPtr(dest.element.key)) |entry| if (entry.ref == cell) return false;
                }
                try bindLoc(ctx, dest, cell);
                return true;
            }
            const v = locValue(target);
            if (v != .object) return false;
            try storeLoc(ctx, dest, v);
            return true;
        },
        'N' => {
            if (c1 != ';') return false;
            sc.p = start + 2;
            try storeLoc(ctx, dest, .null);
            return true;
        },
        'b' => {
            if (c1 != ':' or (sc.at(start + 2) != '0' and sc.at(start + 2) != '1') or sc.at(start + 3) != ';') return false;
            sc.p = start + 4;
            try storeLoc(ctx, dest, .{ .bool = sc.s[start + 2] == '1' });
            return true;
        },
        'i' => {
            if (c1 != ':') return false;
            const end = ivEnd(sc, start + 2) orelse return false;
            if (sc.at(end) != ';') return false;
            sc.p = end + 1;
            const n = try parseIv(ctx, sc, start + 2, null);
            try storeLoc(ctx, dest, .{ .int = n });
            return true;
        },
        'd' => {
            if (c1 != ':') return false;
            const rest = sc.s[start + 2 ..];
            const special: ?f64 = if (std.mem.startsWith(u8, rest, "NAN;"))
                std.math.nan(f64)
            else if (std.mem.startsWith(u8, rest, "INF;"))
                std.math.inf(f64)
            else if (std.mem.startsWith(u8, rest, "-INF;"))
                -std.math.inf(f64)
            else
                null;
            if (special) |f| {
                sc.p = start + 2 + (if (std.math.isNan(f) or f > 0) @as(usize, 4) else 5);
                try storeLoc(ctx, dest, .{ .float = f });
                return true;
            }
            const end = numberEnd(sc, start + 2) orelse return false;
            if (sc.at(end) != ';') return false;
            sc.p = end + 1;
            var num_buf: [512]u8 = undefined;
            const text = sc.s[start + 2 .. end];
            const f: f64 = if (text.len < num_buf.len) blk: {
                @memcpy(num_buf[0..text.len], text);
                num_buf[text.len] = 0;
                break :blk strtod(@ptrCast(&num_buf), null);
            } else std.fmt.parseFloat(f64, text) catch 0;
            try storeLoc(ctx, dest, .{ .float = f });
            return true;
        },
        's', 'S' => {
            if (c1 != ':') return false;
            const de = digitsEnd(sc, start + 2) orelse return false;
            if (sc.at(de) != ':' or sc.at(de + 1) != '"') return false;
            const len = parseUiv(sc, start + 2);
            var cur = de + 2;
            const maxlen = sc.s.len - cur;
            if (maxlen < len) {
                sc.p = start + 2;
                return false;
            }
            var bytes: []const u8 = sc.s[cur .. cur + len];
            var decoded: ?[]u8 = null;
            defer if (decoded) |d| ctx.allocator.free(d);
            if (c0 == 'S') {
                // unserialize_str: \hh escapes
                const out = try ctx.allocator.alloc(u8, len);
                decoded = out;
                var i: usize = 0;
                while (i < len) : (i += 1) {
                    if (cur >= sc.s.len) return false;
                    if (sc.s[cur] != '\\') {
                        out[i] = sc.s[cur];
                    } else {
                        var ch: u8 = 0;
                        for (0..2) |_| {
                            cur += 1;
                            const h = sc.at(cur);
                            const d: u8 = switch (h) {
                                '0'...'9' => h - '0',
                                'a'...'f' => h - 'a' + 10,
                                'A'...'F' => h - 'A' + 10,
                                else => return false,
                            };
                            ch = (ch << 4) | d;
                        }
                        out[i] = ch;
                    }
                    cur += 1;
                }
                bytes = out;
            } else {
                cur += len;
            }
            if (sc.at(cur) != '"') {
                sc.p = cur;
                return false;
            }
            if (sc.at(cur + 1) != ';') {
                sc.p = cur + 1;
                return false;
            }
            sc.p = cur + 2;
            try storeLoc(ctx, dest, try stringValue(ctx, bytes));
            if (c0 == 'S') try docref(ctx, e_deprecated, "Unserializing the 'S' format is deprecated", .{});
            return true;
        },
        'a' => {
            if (c1 != ':') return false;
            const de = digitsEnd(sc, start + 2) orelse return false;
            if (sc.at(de) != ':' or sc.at(de + 1) != '{') return false;
            const elements = try parseIv(ctx, sc, start + 2, null);
            sc.p = de + 2;
            const u = u_opt orelse return false;
            if (elements < 0 or elements >= max_elements or fakeCount(elements, sc.s.len - sc.p)) return false;
            const arr = try ctx.createArray();
            try storeLoc(ctx, dest, .{ .array = arr });
            if (elements > 0) {
                if (!try readArrayElements(ctx, u, sc, arr, @intCast(elements))) return false;
            }
            return finishNested(sc);
        },
        'O', 'C' => return readObject(ctx, u_opt, sc, dest, start),
        'E' => return readEnum(ctx, u_opt, sc, dest, start),
        '}' => {
            // fewer elements than the count said
            try docref(ctx, e_warning, "Unexpected end of serialized data", .{});
            return false;
        },
        else => return false,
    }
}

const max_elements: i64 = 0x40000000;

extern fn strtod(s: [*:0]const u8, end: ?*[*:0]u8) f64;

// IS_FAKE_ELEM_COUNT: each element takes at least two bytes
fn fakeCount(elements: i64, remaining: usize) bool {
    return elements > @as(i64, @intCast(remaining / 2));
}

fn finishNested(sc: *Scan) bool {
    if (sc.p >= sc.s.len or sc.s[sc.p] != '}') return false;
    sc.p += 1;
    return true;
}

fn enterNested(ctx: *NativeContext, u: *UnserCtx) RuntimeError!bool {
    if (u.max_depth > 0 and u.cur_depth >= u.max_depth) {
        try docref(ctx, e_warning, "Maximum depth of {d} exceeded. The depth limit can be changed using the max_depth unserialize() option or the unserialize_max_depth ini setting", .{u.max_depth});
        return false;
    }
    u.cur_depth += 1;
    return true;
}

// a key: an int or a string read without the table
fn readKey(ctx: *NativeContext, sc: *Scan) RuntimeError!?Value {
    var key_temp: Temp = .{};
    if (!try read(ctx, null, sc, .{ .temp = &key_temp })) {
        if (key_temp.value == .string) key_temp.value.string.release();
        return null;
    }
    return key_temp.value;
}

// process_nested_array_data
fn readArrayElements(ctx: *NativeContext, u: *UnserCtx, sc: *Scan, arr: *PhpArray, count: usize) RuntimeError!bool {
    if (!try enterNested(ctx, u)) return false;
    defer u.cur_depth -= 1;
    var left = count;
    while (left > 0) {
        left -= 1;
        const key_val = (try readKey(ctx, sc)) orelse return false;
        const key: PhpArray.Key = switch (key_val) {
            .int => |i| .{ .int = i },
            .string => |s| .{ .string = s },
            else => return false,
        };
        defer if (key == .string) key.string.release();
        // a key read again replaces the element, reference or not
        ctx.vm.detachArrayEntryRef(arr, key);
        try arr.set(ctx.allocator, key, .null);
        const entry = arr.getPtr(key).?;
        if (!try read(ctx, u, sc, .{ .element = .{ .array = arr, .key = entry.key } })) return false;
        if (left > 0 and sc.s[sc.p - 1] != ';' and sc.s[sc.p - 1] != '}') {
            sc.p -= 1;
            return false;
        }
    }
    return true;
}

// object ":" uiv ":" ["] for O: and C:
fn readObject(ctx: *NativeContext, u_opt: ?*UnserCtx, sc: *Scan, dest: Loc, start: usize) RuntimeError!bool {
    const custom = sc.s[start] == 'C';
    if (sc.at(start + 1) != ':') return false;
    const de = digitsEnd(sc, start + 2) orelse return false;
    if (sc.at(de) != ':' or sc.at(de + 1) != '"') return false;
    const u = u_opt orelse return false;
    var cur = de + 2;
    const len = parseUiv(sc, start + 2);
    const maxlen = sc.s.len - cur;
    if (maxlen < len or len == 0) {
        sc.p = start + 2;
        return false;
    }
    const name = sc.s[cur .. cur + len];
    cur += len;
    if (sc.at(cur) != '"') {
        sc.p = cur;
        return false;
    }
    if (sc.at(cur + 1) != ':') {
        sc.p = cur + 1;
        return false;
    }
    // runtime definition keys and a leading namespace separator
    if (name[0] == 0 or name[0] == '\\') return false;

    var incomplete = false;
    var class_name: []const u8 = name;
    resolve: {
        if (u.allowed) |allowed| {
            const lc = try std.ascii.allocLowerString(ctx.allocator, name);
            defer ctx.allocator.free(lc);
            if (!allowed.contains(lc)) {
                if (!validClassName(name)) return false;
                incomplete = true;
                break :resolve;
            }
        }
        // zphp's own resource classes have no name php code could declare
        if (value_mod.isResourceClass(name)) {
            incomplete = true;
            break :resolve;
        }
        if (ctx.vm.classes.getKey(name)) |declared| {
            if (!class_names.isAnonymous(declared)) {
                class_name = declared;
                break :resolve;
            }
        }
        if (!validClassName(name)) return false;
        serialize_lock += 1;
        const autoloaded = ctx.vm.tryAutoload(name);
        serialize_lock -= 1;
        autoloaded catch |err| if (err == error.OutOfMemory) return err;
        if (ctx.vm.pending_exception != null) return false;
        if (ctx.vm.classes.getKey(name)) |declared| {
            class_name = declared;
            break :resolve;
        }
        if (ctx.vm.interfaces.getKey(name) orelse ctx.vm.traits.getKey(name)) |declared| {
            class_name = declared;
            break :resolve;
        }
        const callback = ctx.vm.ini_settings.get("unserialize_callback_func") orelse "";
        if (callback.len == 0) {
            incomplete = true;
            break :resolve;
        }
        const arg = try stringValue(ctx, name);
        defer arg.string.release();
        serialize_lock += 1;
        const called = ctx.invokeCallable(.{ .string = Value.String.borrowed(callback) }, &.{arg});
        serialize_lock -= 1;
        if (called) |r| ctx.vm.releaseValue(r) else |err| if (err == error.OutOfMemory) return err;
        if (ctx.vm.pending_exception != null) return false;
        if (ctx.vm.classes.getKey(name) == null) {
            serialize_lock += 1;
            const again = ctx.vm.tryAutoload(name);
            serialize_lock -= 1;
            again catch |err| if (err == error.OutOfMemory) return err;
            if (ctx.vm.pending_exception != null) return false;
        }
        if (ctx.vm.classes.getKey(name)) |declared| {
            class_name = declared;
            break :resolve;
        }
        try docref(ctx, e_warning, "Function {s}() hasn't defined the class it was called for", .{callback});
        incomplete = true;
    }
    sc.p = cur;
    if (incomplete) class_name = incomplete_class;
    if (!incomplete) {
        refuseNotSerializable(ctx, class_name, .unserialize) catch |err| {
            if (err == error.OutOfMemory) return err;
            return false;
        };
    }
    if (custom) return readCustomObject(ctx, u, sc, dest, class_name, name, incomplete);

    if (sc.p >= sc.s.len -| 2) {
        try plainError(ctx, e_warning, "Bad unserialize data", .{});
        return false;
    }
    const at_quote = sc.p;
    var count_end: usize = undefined;
    const elements = try parseIv(ctx, sc, sc.p + 2, &count_end);
    sc.p = count_end;
    if (elements < 0 or fakeCount(elements, sc.s.len - at_quote)) return false;
    if (sc.at(sc.p) != ':') return false;
    if (sc.at(sc.p + 1) != '{') {
        sc.p += 1;
        return false;
    }
    sc.p += 2;

    const has_unserialize = !incomplete and ctx.vm.hasMethod(class_name, "__unserialize");
    if (!incomplete and !has_unserialize and ctx.vm.isInstanceOf(class_name, "Serializable") and ctx.vm.hasMethod(class_name, "unserialize")) {
        try plainError(ctx, e_warning, "Erroneous data format for unserializing '{s}'", .{class_names.display(class_name)});
        return false;
    }
    const obj = (try instantiate(ctx, class_name)) orelse return false;
    try storeLoc(ctx, dest, .{ .object = obj });
    if (incomplete) try obj.setCopiedString(ctx.allocator, magic_member, name);

    if (has_unserialize) {
        if (elements >= max_elements) return false;
        const data = try ctx.createArray();
        VM.retainValue(.{ .array = data });
        var delayed_data = false;
        defer if (!delayed_data) ctx.vm.releaseValue(.{ .array = data });
        if (!try readArrayElements(ctx, u, sc, data, @intCast(elements))) {
            obj.destructed = true;
            return false;
        }
        // __unserialize() runs once the whole string is read
        VM.retainValue(.{ .object = obj });
        try u.delayed.append(ctx.allocator, .{ .obj = obj, .data = data });
        delayed_data = true;
        return finishNested(sc);
    }

    const has_wakeup = !incomplete and ctx.vm.hasMethod(class_name, "__wakeup");
    if (!try readProperties(ctx, u, sc, obj, @intCast(elements), incomplete)) {
        if (has_wakeup) obj.destructed = true;
        return false;
    }
    if (has_wakeup) {
        VM.retainValue(.{ .object = obj });
        try u.delayed.append(ctx.allocator, .{ .obj = obj, .data = null });
    }
    return finishNested(sc);
}

// object_init_ex: the classes php refuses to instantiate throw
fn instantiate(ctx: *NativeContext, class_name: []const u8) RuntimeError!?*PhpObject {
    const kind: ?[]const u8 = if (ctx.vm.interfaces.contains(class_name))
        "interface"
    else if (ctx.vm.traits.contains(class_name))
        "trait"
    else if (ctx.vm.classes.get(class_name)) |cls|
        (if (cls.is_enum) "enum" else if (cls.is_abstract) "abstract class" else null)
    else
        null;
    if (kind) |k| {
        const msg = try std.fmt.allocPrint(ctx.allocator, "Cannot instantiate {s} {s}", .{ k, class_names.display(class_name) });
        defer ctx.allocator.free(msg);
        try ctx.vm.setPendingException("Error", msg);
        return null;
    }
    if (std.mem.eql(u8, class_name, incomplete_class) and !ctx.vm.classes.contains(incomplete_class)) {
        try ctx.vm.classes.put(ctx.allocator, incomplete_class, ClassDef{ .name = incomplete_class });
    }
    const obj = try ctx.createObject(class_name);
    if (obj.slots == null) {
        if (ctx.vm.classes.get(class_name)) |cls| {
            if (cls.slot_layout) |layout| {
                obj.slots = try ctx.allocator.alloc(Value, layout.names.len);
                for (layout.defaults, 0..) |def, i| obj.slots.?[i] = def;
                obj.slot_layout = layout;
            }
        }
    }
    return obj;
}

// object_custom: C:len:"name":datalen:{payload}
// gmp_unserialize: the number in base 10, then the properties, read with
// the table the outer call uses
fn readGmpPayload(ctx: *NativeContext, u: *UnserCtx, dest: Loc, payload: []const u8) RuntimeError!bool {
    const obj = (try instantiate(ctx, "GMP")) orelse return false;
    try storeLoc(ctx, dest, .{ .object = obj });
    var sc: Scan = .{ .s = payload, .p = 0 };
    const num = try u.temp(ctx.allocator);
    if (!try readTop(ctx, u, &sc, .{ .temp = num }) or num.value != .string) {
        if (ctx.vm.pending_exception == null) try ctx.vm.setPendingException("Exception", "Could not unserialize number");
        return false;
    }
    try u.keep(ctx.allocator, num.value);
    num.value.string.release();
    const base: Value = .{ .int = 10 };
    const r = ctx.vm.callMethod(obj, "__construct", &.{ num.value, base }) catch |err| {
        if (err == error.OutOfMemory) return err;
        if (ctx.vm.pending_exception != null) {
            if (ctx.vm.takePending()) |pending| ctx.vm.stackRelease(pending);
        }
        try ctx.vm.setPendingException("Exception", "Could not unserialize number");
        return false;
    };
    ctx.vm.releaseValue(r);
    const props = try u.temp(ctx.allocator);
    if (!try readTop(ctx, u, &sc, .{ .temp = props }) or props.value != .array) {
        if (ctx.vm.pending_exception == null) try ctx.vm.setPendingException("Exception", "Could not unserialize properties");
        return false;
    }
    try u.keep(ctx.allocator, props.value);
    for (props.value.array.entries.items) |entry| {
        const name: []const u8 = switch (entry.key) {
            .string => |s| s.bytes(),
            .int => continue,
        };
        try obj.set(ctx.allocator, try ctx.vm.internName(name), entryValue(entry));
    }
    return true;
}

fn readCustomObject(ctx: *NativeContext, u: *UnserCtx, sc: *Scan, dest: Loc, class_name: []const u8, raw_name: []const u8, incomplete: bool) RuntimeError!bool {
    var after: usize = undefined;
    const datalen = try parseIv(ctx, sc, sc.p + 2, &after);
    sc.p = after;
    if (sc.s.len - @min(sc.p, sc.s.len) < 2) return false;
    if (sc.s[sc.p] != ':') return false;
    if (sc.s[sc.p + 1] != '{') {
        sc.p += 1;
        return false;
    }
    sc.p += 2;
    const remaining: i64 = @intCast(sc.s.len - sc.p);
    if (datalen < 0 or remaining <= datalen) {
        try plainError(ctx, e_warning, "Insufficient data for unserializing - {d} required, {d} present", .{ datalen, remaining });
        return false;
    }
    const n: usize = @intCast(datalen);
    if (sc.s[sc.p + n] != '}') {
        sc.p += n;
        return false;
    }
    const payload = sc.s[sc.p .. sc.p + n];
    const serializable = !incomplete and ctx.vm.isInstanceOf(class_name, "Serializable") and ctx.vm.hasMethod(class_name, "unserialize");
    if (!incomplete and std.mem.eql(u8, class_name, "GMP")) {
        if (!try readGmpPayload(ctx, u, dest, payload)) return false;
    } else if (!serializable) {
        try plainError(ctx, e_warning, "Class {s} has no unserializer", .{class_names.display(class_name)});
        const obj = (try instantiate(ctx, class_name)) orelse return false;
        try storeLoc(ctx, dest, .{ .object = obj });
        if (incomplete) try obj.setCopiedString(ctx.allocator, magic_member, raw_name);
    } else {
        const obj = (try instantiate(ctx, class_name)) orelse return false;
        try storeLoc(ctx, dest, .{ .object = obj });
        const arg = try stringValue(ctx, payload);
        defer arg.string.release();
        const r = ctx.vm.callMethod(obj, "unserialize", &.{arg}) catch |err| {
            if (err == error.OutOfMemory) return err;
            return false;
        };
        ctx.vm.releaseValue(r);
        if (ctx.vm.pending_exception != null) return false;
    }
    sc.p += n + 1;
    return true;
}

// the slot a serialized property name stands for: a declared property of
// the object's class (also when its visibility changed since), an
// ancestor's private one by its mangled name, or a dynamic property
const PropSlot = struct {
    name: []const u8,
    scope: ?[]const u8 = null,
    declared: bool = false,
    type_str: []const u8 = "",
    defining: []const u8 = "",
    // the name without its mangling, for messages
    shown: []const u8 = "",
};

fn propertySlot(ctx: *NativeContext, obj: *PhpObject, key: []const u8) RuntimeError!PropSlot {
    var class_part: ?[]const u8 = null;
    var name = key;
    if (key.len > 0 and key[0] == 0) {
        if (std.mem.lastIndexOfScalar(u8, key[1..], 0)) |last| {
            class_part = key[1 .. last + 1];
            name = key[last + 2 ..];
        }
    }
    const class_name = obj.class_name;
    const own = class_part == null or std.mem.eql(u8, class_part.?, "*") or std.ascii.eqlIgnoreCase(class_part.?, class_name);
    if (own) {
        const decl = ctx.vm.propertyDeclaration(class_name, name);
        if (decl.declared and !(decl.visibility == .private and !std.mem.eql(u8, decl.defining_class, class_name))) {
            return .{ .name = try ctx.vm.internName(name), .scope = if (decl.visibility == .private) decl.defining_class else null, .declared = true, .type_str = decl.type_str, .defining = decl.defining_class };
        }
    } else if (class_part) |cp| {
        // an ancestor's private property, by its mangled name
        var current: ?[]const u8 = class_name;
        while (current) |cn| {
            const cls = ctx.vm.classes.get(cn) orelse break;
            if (std.ascii.eqlIgnoreCase(cn, cp)) {
                for (cls.properties.items) |prop| if (prop.visibility == .private and std.mem.eql(u8, prop.name, name)) {
                    return .{ .name = try ctx.vm.internName(name), .scope = cn, .declared = true, .type_str = prop.type_str, .defining = cn };
                };
                break;
            }
            current = cls.parent;
        }
    }
    // undeclared: a dynamic property under the name as read, mangled or not
    return .{ .name = try ctx.vm.internName(key), .shown = name };
}

// process_nested_object_data
fn readProperties(ctx: *NativeContext, u: *UnserCtx, sc: *Scan, obj: *PhpObject, count: usize, incomplete: bool) RuntimeError!bool {
    if (!try enterNested(ctx, u)) return false;
    defer u.cur_depth -= 1;
    var left = count;
    while (left > 0) {
        left -= 1;
        const key_val = (try readKey(ctx, sc)) orelse return false;
        defer if (key_val == .string) key_val.string.release();
        var num_buf: [24]u8 = undefined;
        const key: []const u8 = switch (key_val) {
            .string => |s| s.bytes(),
            // object properties hold no integers
            .int => |i| std.fmt.bufPrint(&num_buf, "{d}", .{i}) catch unreachable,
            else => return false,
        };
        const slot = if (incomplete)
            PropSlot{ .name = try ctx.vm.internName(key), .shown = stripVisibility(key) }
        else
            try propertySlot(ctx, obj, key);
        if (!slot.declared and !incomplete and obj.properties.get(slot.name) == null) {
            switch (ctx.vm.dynamicPropertyRule(obj)) {
                .allowed => {},
                .forbidden => {
                    const msg = try std.fmt.allocPrint(ctx.allocator, "Cannot create dynamic property {s}::${s}", .{ class_names.display(obj.class_name), slot.shown });
                    defer ctx.allocator.free(msg);
                    try ctx.vm.setPendingException("Error", msg);
                    return false;
                },
                .deprecated => {
                    try plainError(ctx, e_deprecated, "Creation of dynamic property {s}::${s} is deprecated", .{ class_names.display(obj.class_name), slot.shown });
                    if (ctx.vm.pending_exception != null) return false;
                },
            }
        }
        const loc: Loc = .{ .property = .{ .obj = obj, .name = slot.name, .scope = slot.scope, .type_str = slot.type_str, .defining = slot.defining } };
        // a property read again replaces the earlier value, leaving any
        // reference the slot took
        try obj.setForScope(ctx.allocator, slot.name, .null, slot.scope);
        if (!try read(ctx, u, sc, loc)) return false;
        if (slot.declared and slot.type_str.len > 0) {
            const v = locValue(loc);
            if (!try ctx.vm.unserializedPropertyFits(v, slot.type_str, slot.defining)) {
                const type_text = try ctx.vm.propertyTypeText(slot.type_str, slot.defining);
                const msg = try std.fmt.allocPrint(ctx.allocator, "Cannot assign {s} to property {s}::${s} of type {s}", .{ types.phpTypeName(v), class_names.display(slot.defining), slot.name, type_text });
                defer ctx.allocator.free(msg);
                try obj.setForScope(ctx.allocator, slot.name, .undef, slot.scope);
                try ctx.vm.setPendingException("TypeError", msg);
                return false;
            }
        }
        if (left > 0 and sc.s[sc.p - 1] != ';' and sc.s[sc.p - 1] != '}') {
            sc.p -= 1;
            return false;
        }
    }
    return true;
}

fn stripVisibility(name: []const u8) []const u8 {
    if (name.len > 2 and name[0] == 0) {
        if (std.mem.lastIndexOfScalar(u8, name[1..], 0)) |last| return name[last + 2 ..];
    }
    return name;
}

// "E:" uiv ":" ["]
fn readEnum(ctx: *NativeContext, u_opt: ?*UnserCtx, sc: *Scan, dest: Loc, start: usize) RuntimeError!bool {
    if (sc.at(start + 1) != ':') return false;
    const de = digitsEnd(sc, start + 2) orelse return false;
    if (sc.at(de) != ':' or sc.at(de + 1) != '"') return false;
    if (u_opt == null) return false;
    var cur = de + 2;
    const len = parseUiv(sc, start + 2);
    const maxlen = sc.s.len - cur;
    if (maxlen < len or len == 0) {
        sc.p = start + 2;
        return false;
    }
    const str = sc.s[cur .. cur + len];
    cur += len;
    if (sc.at(cur) != '"') {
        sc.p = cur;
        return false;
    }
    if (sc.at(cur + 1) != ';') {
        sc.p = cur + 1;
        return false;
    }
    const colon = std.mem.indexOfScalar(u8, str, ':') orelse {
        try docref(ctx, e_warning, "Invalid enum name '{s}' (missing colon)", .{str});
        return false;
    };
    const enum_name = str[0..colon];
    const case_name = str[colon + 1 ..];
    if (!validClassName(enum_name)) return false;
    if (!ctx.vm.classes.contains(enum_name)) {
        ctx.vm.tryAutoload(enum_name) catch |err| if (err == error.OutOfMemory) return err;
        if (ctx.vm.pending_exception != null) return false;
    }
    const cls = ctx.vm.classes.get(enum_name) orelse {
        try docref(ctx, e_warning, "Class '{s}' not found", .{enum_name});
        return false;
    };
    if (!cls.is_enum) {
        try docref(ctx, e_warning, "Class '{s}' is not an enum", .{enum_name});
        return false;
    }
    sc.p = cur + 2;
    const declared = ctx.vm.declaredClassName(enum_name);
    const constant = cls.constants.get(case_name) orelse {
        try docref(ctx, e_warning, "Undefined constant {s}::{s}", .{ declared, case_name });
        return false;
    };
    const v = ctx.vm.enumCase(constant);
    if (v != .object) {
        try docref(ctx, e_warning, "{s}::{s} is not an enum case", .{ declared, case_name });
        return false;
    }
    try storeLoc(ctx, dest, v);
    return true;
}

fn runDelayed(ctx: *NativeContext, uctx: *UnserCtx) void {
    var failed = ctx.vm.pending_exception != null;
    for (uctx.delayed.items) |d| {
        if (!failed) {
            serialize_lock += 1;
            defer serialize_lock -= 1;
            const r = if (d.data) |data|
                ctx.vm.callMethod(d.obj, "__unserialize", &.{.{ .array = data }})
            else
                ctx.vm.callMethod(d.obj, "__wakeup", &.{});
            if (r) |v| ctx.vm.releaseValue(v) else |_| failed = true;
            if (ctx.vm.pending_exception != null) failed = true;
            if (failed) d.obj.destructed = true;
        } else {
            d.obj.destructed = true;
        }
        if (d.data) |data| ctx.vm.releaseValue(.{ .array = data });
        ctx.vm.releaseValue(.{ .object = d.obj });
    }
    uctx.delayed.clearRetainingCapacity();
    for (uctx.kept.items) |v| ctx.vm.releaseValue(v);
    uctx.kept.clearRetainingCapacity();
}

// unserialize()'s options, checked as php_unserialize_with_options does
fn applyOptions(ctx: *NativeContext, uctx: *UnserCtx, opts: *PhpArray) RuntimeError!bool {
    const a = ctx.allocator;
    const classes = entryLookup(opts, "allowed_classes");
    if (classes) |cv| {
        if (cv != .array and cv != .bool) {
            const msg = try std.fmt.allocPrint(a, "unserialize(): Option \"allowed_classes\" must be of type array|bool, {s} given", .{types.phpTypeName(cv)});
            defer a.free(msg);
            try ctx.vm.setPendingException("TypeError", msg);
            return false;
        }
        if (cv == .array or !cv.isTruthy()) {
            var set: std.StringHashMapUnmanaged(void) = .{};
            errdefer {
                var it = set.keyIterator();
                while (it.next()) |k| a.free(k.*);
                set.deinit(a);
            }
            if (cv == .array) for (cv.array.entries.items) |entry| {
                const v = entryValue(entry);
                if (v != .string and v != .object) {
                    const msg = try std.fmt.allocPrint(a, "unserialize(): Option \"allowed_classes\" must be an array of class names, {s} given", .{types.phpTypeName(v)});
                    defer a.free(msg);
                    try ctx.vm.setPendingException("TypeError", msg);
                    return false;
                }
                const name = if (v == .string) v.string.bytes() else blk: {
                    if (!ctx.vm.hasMethod(v.object.class_name, "__toString")) {
                        const msg = try std.fmt.allocPrint(a, "Object of class {s} could not be converted to string", .{class_names.display(v.object.class_name)});
                        defer a.free(msg);
                        try ctx.vm.setPendingException("Error", msg);
                        return false;
                    }
                    break :blk try ctx.vm.objectToString(v.object);
                };
                if (!validClassName(name)) {
                    const msg = try std.fmt.allocPrint(a, "unserialize(): Option \"allowed_classes\" must be an array of class names, \"{s}\" given", .{name[0 .. std.mem.indexOfScalar(u8, name, 0) orelse name.len]});
                    defer a.free(msg);
                    try ctx.vm.setPendingException("ValueError", msg);
                    return false;
                }
                const lc = try std.ascii.allocLowerString(a, name);
                const gop = try set.getOrPut(a, lc);
                if (gop.found_existing) a.free(lc);
            };
            uctx.allowed = set;
        }
    }
    if (entryLookup(opts, "max_depth")) |md| {
        if (md != .int) {
            const msg = try std.fmt.allocPrint(a, "unserialize(): Option \"max_depth\" must be of type int, {s} given", .{types.phpTypeName(md)});
            defer a.free(msg);
            try ctx.vm.setPendingException("TypeError", msg);
            return false;
        }
        if (md.int < 0) {
            try ctx.vm.setPendingException("ValueError", "unserialize(): Option \"max_depth\" must be greater than or equal to 0");
            return false;
        }
        uctx.max_depth = md.int;
        // a nested call with its own limit counts from zero
        uctx.cur_depth = 0;
    }
    return true;
}

fn entryLookup(arr: *PhpArray, name: []const u8) ?Value {
    const entry = arr.getPtr(.{ .string = Value.String.borrowed(name) }) orelse return null;
    return entryValue(entry.*);
}

fn iniMaxDepth(ctx: *NativeContext) i64 {
    const text = ctx.vm.ini_settings.get("unserialize_max_depth") orelse return 4096;
    return std.fmt.parseInt(i64, std.mem.trim(u8, text, " "), 10) catch 4096;
}

fn native_unserialize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = @import("string_ports.zig").Args.init(ctx, "unserialize", args);
    const s = try p.str(0, "data");
    if (args.len >= 2 and args[1] != .array) return p.typeError(1, "options", "array");
    if (s.len == 0) return NativeResult.scalar(.{ .bool = false });
    // nested in a Serializable::unserialize() method, the call shares the
    // outer call's table (php's BG(unserialize)) with its own options
    var own = UnserCtx{ .max_depth = iniMaxDepth(ctx) };
    defer own.deinit(ctx.allocator);
    const outer = if (serialize_lock == 0) shared_uctx else null;
    const uctx: *UnserCtx = outer orelse &own;
    const saved_allowed = uctx.allowed;
    const saved_max = uctx.max_depth;
    const saved_cur = uctx.cur_depth;
    if (outer != null) uctx.allowed = null;
    defer if (outer != null) {
        if (uctx.allowed) |*m| if (saved_allowed == null or m != &saved_allowed.?) {
            var it = m.keyIterator();
            while (it.next()) |k| ctx.allocator.free(k.*);
            m.deinit(ctx.allocator);
        };
        uctx.allowed = saved_allowed;
        uctx.max_depth = saved_max;
        uctx.cur_depth = saved_cur;
    };
    const owner = outer == null and serialize_lock == 0;
    if (owner) shared_uctx = &own;
    defer if (owner) {
        shared_uctx = null;
    };
    if (args.len >= 2) {
        if (!try applyOptions(ctx, uctx, args[1].array)) return error.RuntimeError;
    }
    const top = try uctx.temp(ctx.allocator);
    var sc: Scan = .{ .s = s, .p = 0 };
    const ok = try readTop(ctx, uctx, &sc, .{ .temp = top });
    if (!ok) {
        if (ctx.vm.pending_exception == null) try docref(ctx, e_warning, "Error at offset {d} of {d} bytes", .{ sc.p, s.len });
    } else if (sc.p < s.len and ctx.vm.pending_exception == null) {
        try docref(ctx, e_warning, "Extra data starting at offset {d} of {d} bytes", .{ sc.p, s.len });
    }
    if (ok and outer != null) try uctx.keep(ctx.allocator, if (top.cell) |cell| cell.* else top.value);
    // the outermost call runs the queued __unserialize() and __wakeup()
    // calls last, whatever happened while reading; what they do through a
    // reference to the result is in the result
    if (outer == null) runDelayed(ctx, uctx);
    const owned_string = top.cell == null and top.value == .string;
    if (!ok or ctx.vm.pending_exception != null) {
        if (owned_string) top.value.string.release();
        if (ctx.vm.pending_exception != null) return error.RuntimeError;
        return NativeResult.scalar(.{ .bool = false });
    }
    const result = if (top.cell) |cell| cell.* else top.value;
    if (result == .string and !owned_string) result.string.retain();
    return NativeResult.transfer(result);
}

// php_var_unserialize as a Serializable::unserialize() method calls it:
// values read one after another from `s`, sharing the table of the
// unserialize() call that is running (BG(unserialize)), or a table of
// their own
pub const Reader = struct {
    ctx: *NativeContext,
    s: []const u8,
    pos: usize = 0,
    own: UnserCtx = .{},
    outer: ?*UnserCtx = null,
    owner: bool = false,

    pub fn begin(self: *Reader) void {
        self.outer = if (serialize_lock == 0) shared_uctx else null;
        self.owner = self.outer == null and serialize_lock == 0;
        if (self.owner) shared_uctx = &self.own;
    }

    // the next value, or null when the data is malformed there (an
    // exception a constructor or __wakeup throws is error.RuntimeError). a
    // string carries a reference the caller drops once it stored the value
    pub fn value(self: *Reader) RuntimeError!?Value {
        const uctx = self.outer orelse &self.own;
        const t = try uctx.temp(self.ctx.allocator);
        var sc: Scan = .{ .s = self.s, .p = self.pos };
        const ok = try readTop(self.ctx, uctx, &sc, .{ .temp = t });
        // php leaves its cursor where the value went wrong
        self.pos = sc.p;
        if (!ok) {
            if (self.ctx.vm.pending_exception != null) return error.RuntimeError;
            return null;
        }
        const v = if (t.cell) |cell| cell.* else t.value;
        if (t.cell != null and v == .string) v.string.retain();
        try uctx.keep(self.ctx.allocator, v);
        return v;
    }

    pub fn deinit(self: *Reader) void {
        if (self.owner) shared_uctx = null;
        // a table of its own runs its queued calls at the end
        if (self.outer == null) runDelayed(self.ctx, &self.own);
        self.own.deinit(self.ctx.allocator);
    }
};

pub fn unserializeFromString(ctx: *NativeContext, s: []const u8) ?Value {
    var uctx = UnserCtx{};
    defer uctx.deinit(ctx.allocator);
    defer runDelayed(ctx, &uctx);
    const top = uctx.temp(ctx.allocator) catch return null;
    var sc: Scan = .{ .s = s, .p = 0 };
    const ok = readTop(ctx, &uctx, &sc, .{ .temp = top }) catch return null;
    if (!ok) return null;
    if (top.cell) |cell| {
        const v = cell.*;
        if (v == .string) v.string.retain();
        return v;
    }
    return top.value;
}
// ======================================================================
// ArrayObject and ArrayIterator's legacy Serializable stream
// ======================================================================

// one reference table spans flags, storage, and members (the separators
// themselves take no slot)
pub fn serializeSplArray(ctx: *NativeContext, obj: *PhpObject) RuntimeError!NativeResult {
    var w = Writer{ .ctx = ctx };
    w.begin();
    defer w.deinit();
    try w.raw("x:");
    const flags = @import("spl.zig").serializedFlags(obj);
    try w.value(.{ .int = flags });
    if ((flags & @import("spl.zig").IS_SELF) == 0) {
        try w.value(obj.get("__data"));
        try w.raw(";");
    }
    try w.raw("m:");
    const members = try splMembers(ctx, obj);
    try w.value(.{ .array = members });
    return w.finish();
}

fn findPropertyVisibility(cls: ClassDef, name: []const u8) ClassDef.Visibility {
    for (cls.properties.items) |pdef| {
        if (std.mem.eql(u8, pdef.name, name)) return pdef.visibility;
    }
    return .public;
}

fn splInternal(name: []const u8) bool {
    return std.mem.eql(u8, name, "__data") or std.mem.eql(u8, name, "__flags") or
        std.mem.eql(u8, name, "__cursor") or std.mem.eql(u8, name, "__iter_class");
}

fn splMember(ctx: *NativeContext, obj: *PhpObject, members: *PhpArray, name: []const u8, val: Value) !void {
    if (splInternal(name) or obj.isUnset(name)) return;
    const cls = ctx.vm.classes.get(obj.class_name);
    const vis = if (cls) |c| findPropertyVisibility(c, name) else .public;
    const key = try mangledName(ctx.allocator, name, vis, obj.class_name);
    defer ctx.allocator.free(key);
    try members.setCopiedKey(ctx.allocator, key, val);
}

fn splMembers(ctx: *NativeContext, obj: *PhpObject) !*PhpArray {
    const members = try ctx.createArray();
    if (obj.slot_layout) |layout| {
        if (obj.slots) |slots| {
            for (layout.names, 0..) |name, i| try splMember(ctx, obj, members, name, slots[i]);
        }
    }
    var it = obj.properties.iterator();
    while (it.next()) |entry| try splMember(ctx, obj, members, entry.key_ptr.*, entry.value_ptr.*);
    return members;
}

pub fn unserializeSplArray(ctx: *NativeContext, obj: *PhpObject, s: []const u8) RuntimeError!NativeResult {
    if (s.len == 0) return NativeResult.scalar(.null); // php treats an empty payload as a no-op
    var r = Reader{ .ctx = ctx, .s = s };
    r.begin();
    defer r.deinit();
    const ok = parseSplArray(ctx, obj, &r) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return error.RuntimeError;
    };
    if (!ok) {
        if (ctx.vm.pending_exception != null) return error.RuntimeError;
        const msg = try std.fmt.allocPrint(ctx.allocator, "Error at offset {d} of {d} bytes", .{ r.pos, s.len });
        defer ctx.allocator.free(msg);
        try ctx.vm.setPendingException("UnexpectedValueException", msg);
        return error.RuntimeError;
    }
    return NativeResult.scalar(.null);
}

fn parseSplArray(ctx: *NativeContext, obj: *PhpObject, r: *Reader) RuntimeError!bool {
    const s = r.s;
    if (!std.mem.startsWith(u8, s, "x:")) return false;
    r.pos = 2;
    const flags = (try r.value()) orelse return false;
    if (flags != .int) return false;
    const spl = @import("spl.zig");
    // the storage takes effect before the members are read; an object php
    // refuses as storage throws once the members are loaded
    var refused = false;
    if ((flags.int & spl.IS_SELF) != 0) {
        try spl.splSetSelf(ctx, obj, flags.int);
    } else {
        if (r.pos >= s.len or (s[r.pos] != 'a' and s[r.pos] != 'O' and s[r.pos] != 'C' and s[r.pos] != 'r')) return false;
        const storage = (try r.value()) orelse return false;
        if (storage != .array and storage != .object) return false;
        if (storage == .array) {
            try obj.set(ctx.allocator, "__data", storage);
            try obj.set(ctx.allocator, "__flags", .{ .int = flags.int & spl.FLAGS_MASK });
            try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
        } else {
            spl.splSetStorage(ctx, obj, storage, flags.int | spl.otherFlags(ctx.vm, storage), "unserialize") catch |err| {
                if (err != error.RuntimeError or ctx.vm.pending_exception == null) return err;
                refused = true;
            };
        }
        if (r.pos >= s.len or s[r.pos] != ';') return false;
        r.pos += 1;
    }
    if (!std.mem.startsWith(u8, s[r.pos..], "m:")) return false;
    r.pos += 2;
    const members = (try r.value()) orelse return false;
    if (members != .array) return false;
    if (refused) {
        const pending = ctx.vm.takePending();
        defer if (pending) |p| ctx.vm.stackRelease(p);
        try spl.loadProperties(ctx, obj, members.array);
        if (pending) |p| {
            ctx.vm.pending_exception = p;
            VM.retainValue(p);
        }
        return error.RuntimeError;
    }
    try spl.loadProperties(ctx, obj, members.array);
    // trailing bytes are ignored, as in php 8.5
    return true;
}

pub fn splArrayState(ctx: *NativeContext, obj: *PhpObject) RuntimeError!NativeResult {
    const state = try ctx.createArray();
    const flags = @import("spl.zig").serializedFlags(obj);
    try state.append(ctx.allocator, .{ .int = flags });
    const data = obj.get("__data");
    // __serialize exposes a value snapshot, not the mutable internal table
    try state.append(ctx.allocator, if (flags & @import("spl.zig").IS_SELF != 0) .null else if (data == .array) .{ .array = try splStorageSnapshot(ctx, data.array) } else data);
    try state.append(ctx.allocator, .{ .array = try splMembers(ctx, obj) });
    try state.append(ctx.allocator, obj.get("__iter_class"));
    return NativeResult.borrowed(.{ .array = state });
}

pub fn restoreSplArrayState(ctx: *NativeContext, obj: *PhpObject, state: Value) RuntimeError!NativeResult {
    if (state != .array) return error.RuntimeError;
    const flags = state.array.get(.{ .int = 0 });
    const storage = state.array.get(.{ .int = 1 });
    const members = state.array.get(.{ .int = 2 });
    const iterator = state.array.get(.{ .int = 3 });
    if (flags != .int or members != .array or (iterator != .null and iterator != .string)) {
        try ctx.vm.setPendingException("UnexpectedValueException", "Incomplete or ill-typed serialization data");
        return error.RuntimeError;
    }
    const spl = @import("spl.zig");
    if (flags.int & spl.IS_SELF != 0) {
        try spl.splSetSelf(ctx, obj, flags.int);
    } else {
        if (storage != .array and storage != .object) {
            try ctx.vm.setPendingException("InvalidArgumentException", "Passed variable is not an array or object");
            return error.RuntimeError;
        }
        try spl.splSetStorage(ctx, obj, storage, flags.int | spl.otherFlags(ctx.vm, storage), "__unserialize");
    }
    try spl.loadProperties(ctx, obj, members.array);
    if (iterator == .string) {
        const name = iterator.string.bytes();
        if (!ctx.vm.classes.contains(name) and !ctx.vm.interfaces.contains(name)) try ctx.vm.tryAutoload(name);
        if (!ctx.vm.classes.contains(name) and !ctx.vm.interfaces.contains(name)) {
            const msg = try std.fmt.allocPrint(ctx.allocator, "Cannot deserialize ArrayObject with iterator class '{s}'; no such class exists", .{iterator.string.bytes()});
            defer ctx.allocator.free(msg);
            try ctx.vm.setPendingException("UnexpectedValueException", msg);
            return error.RuntimeError;
        }
        if (!ctx.vm.isInstanceOf(iterator.string.bytes(), "Iterator")) {
            const msg = try std.fmt.allocPrint(ctx.allocator, "Cannot deserialize ArrayObject with iterator class '{s}'; this class does not implement the Iterator interface", .{iterator.string.bytes()});
            defer ctx.allocator.free(msg);
            try ctx.vm.setPendingException("UnexpectedValueException", msg);
            return error.RuntimeError;
        }
        try obj.set(ctx.allocator, "__iter_class", iterator);
    }
    return NativeResult.scalar(.null);
}

// Decode R: aliases into the same owning cells/registry used by VM array
// references. The registry is request-local; no serializer state escapes.
fn bindDecodedArrayReference(ctx: *NativeContext, source: *PhpArray, source_key: PhpArray.Key, dest: *PhpArray, dest_key: PhpArray.Key) !void {
    const values = @import("../runtime/value.zig");
    const first = source.getPtr(source_key) orelse return;
    const cell = first.ref orelse blk: {
        const owner = try ctx.allocator.create(values.RefCell);
        owner.* = .{};
        try ctx.vm.ref_cells.append(ctx.allocator, owner);
        ctx.vm.setCell(&owner.value, first.value);
        break :blk &owner.value;
    };
    if (ctx.vm.ref_index == null) {
        const index = try ctx.allocator.create(values.RefIndex);
        index.* = .{};
        ctx.vm.ref_index = index;
    }
    const index = ctx.vm.ref_index.?;
    if (ctx.vm.persistent_ref_owner == 0) ctx.vm.persistent_ref_owner = index.createOwner();
    const arrays = [_]*PhpArray{ source, dest };
    const keys = [_]PhpArray.Key{ source_key, dest_key };
    for (arrays, keys) |array, key| {
        const entry = array.getPtr(key) orelse continue;
        if (entry.ref == cell) continue;
        entry.ref = cell;
        values.cellOf(cell).binders += 1;
        try ctx.vm.array_ref_bindings.append(ctx.allocator, .{ .cell = cell, .array = array, .key = key });
        try index.addOwned(ctx.allocator, ctx.vm.persistent_ref_owner, cell, .{ .array = .{ .array = array, .key = key } });
    }
    ctx.vm.array_ref_active = true;
}

fn splStorageSnapshot(ctx: *NativeContext, source: *PhpArray) !*PhpArray {
    const copy = try ctx.createArray();
    for (source.entries.items) |entry| {
        try copy.set(ctx.allocator, entry.key, entry.value);
        if (entry.ref) |cell| {
            if (@import("../runtime/value.zig").cellOf(cell).binders > 1)
                try bindDecodedArrayReference(ctx, source, entry.key, copy, entry.key);
        }
    }
    return copy;
}
