// php's ext/spl/spl_iterators.c: RecursiveIteratorIterator and
// RecursiveTreeIterator (spl_recursive_it_object), IteratorIterator and the
// iterators built on it (spl_dual_it_object), EmptyIterator, and
// iterator_to_array, iterator_count and iterator_apply.
//
// an iterator reaches the iterator it wraps the way php does, through the
// zend_object_iterator its class hands out (ObjIter below), so user methods
// run in php's order and as often as php runs them: a user iterator's
// current() once per position, internal ones directly. a call into php
// code follows zend_call_method: it is skipped while an exception is
// pending, and an exception it throws stays pending for the native to read
// as php reads EG(exception)

const std = @import("std");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const PhpArray = value_mod.PhpArray;
const PhpObject = value_mod.PhpObject;
const Generator = value_mod.Generator;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeResult = vm_mod.NativeResult;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };
const NativeFn = *const fn (*NativeContext, []const Value) RuntimeError!NativeResult;

// ==========================================
// shared helpers
// ==========================================

fn thisObj(ctx: *NativeContext) ?*PhpObject {
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    return if (v == .object) v.object else null;
}

fn pending(ctx: *NativeContext) bool {
    return ctx.vm.pending_exception != null;
}

// a method's result, or its exception: php returns with EG(exception) set
fn finish(ctx: *NativeContext, result: NativeResult) RuntimeError!NativeResult {
    if (pending(ctx)) {
        if (result.value == .string) result.value.string.release();
        return error.RuntimeError;
    }
    return result;
}

fn finishNull(ctx: *NativeContext) RuntimeError!NativeResult {
    return finish(ctx, NativeResult.scalar(.null));
}

fn raise(ctx: *NativeContext, class: []const u8, comptime fmt: []const u8, args: anytype) RuntimeError!void {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException(class, msg);
}

fn throwNow(ctx: *NativeContext, class: []const u8, comptime fmt: []const u8, args: anytype) RuntimeError!NativeResult {
    try raise(ctx, class, fmt, args);
    return error.RuntimeError;
}

// runs php code the way zend_call_function does from inside a native
fn guarded(ctx: *NativeContext, comptime f: anytype, args: anytype) RuntimeError!Value {
    const vm = ctx.vm;
    if (vm.pending_exception != null) return .undef;
    // a throw below lands here, never in a catch of the code that called
    // this native, as php keeps it in EG(exception) until the native returns
    const floor = vm.handler_floor;
    vm.handler_floor = vm.handler_count;
    defer vm.handler_floor = floor;
    return @call(.auto, f, args) catch |err| {
        if (vm.pending_exception != null) return .undef;
        return err;
    };
}

// zend_call_method: .undef is php's UNDEF result
fn callOn(ctx: *NativeContext, target: *PhpObject, name: []const u8, args: []const Value) RuntimeError!Value {
    if (pending(ctx)) return .undef;
    return guarded(ctx, VM.callMethod, .{ ctx.vm, target, name, args }) catch |err| {
        // a method that isn't there fails without an exception of its own
        if (err != error.RuntimeError or ctx.vm.hasMethod(target.class_name, name)) return err;
        try raise(ctx, "Error", "Call to undefined method {s}::{s}()", .{ target.class_name, name });
        return .undef;
    };
}

fn callValue(ctx: *NativeContext, callable: Value, args: []const Value) RuntimeError!Value {
    return guarded(ctx, NativeContext.invokeCallable, .{ ctx, callable, args });
}

fn resumeGen(ctx: *NativeContext, gen: *Generator) RuntimeError!void {
    _ = try guarded(ctx, resumeGenVoid, .{ ctx.vm, gen });
}

fn resumeGenVoid(vm: *VM, gen: *Generator) RuntimeError!Value {
    try vm.resumeGenerator(gen, .null);
    return .null;
}

fn initGen(ctx: *NativeContext, gen: *Generator) RuntimeError!void {
    _ = try guarded(ctx, initGenVoid, .{ ctx.vm, gen });
}

fn initGenVoid(vm: *VM, gen: *Generator) RuntimeError!Value {
    try vm.ensureGeneratorInitialized(gen);
    return .null;
}

fn rewindGenVoid(vm: *VM, gen: *Generator) RuntimeError!Value {
    try vm.rewindGenerator(gen);
    return .null;
}

fn isInstance(vm: *VM, v: Value, class: []const u8) bool {
    return switch (v) {
        .object => |o| vm.isInstanceOf(o.class_name, class),
        .generator => std.ascii.eqlIgnoreCase(class, "Generator") or std.ascii.eqlIgnoreCase(class, "Iterator") or std.ascii.eqlIgnoreCase(class, "Traversable"),
        else => false,
    };
}

// the class declaring a method resolved on class_name is a user class
fn userMethod(vm: *VM, class_name: []const u8, name: []const u8) bool {
    const full = vm.resolveMethod(class_name, name) catch return false;
    return vm.functions.get(full) != null;
}

// object_init_with_constructor: .undef when it throws
fn construct(ctx: *NativeContext, class_name: []const u8, args: []const Value) RuntimeError!Value {
    if (pending(ctx)) return .undef;
    if (ctx.vm.classes.get(class_name)) |cd| if (cd.is_abstract) {
        try raise(ctx, "Error", "Cannot instantiate abstract class {s}", .{class_name});
        return .undef;
    };
    const obj = try ctx.vm.allocObject(.{ .class_name = try ctx.vm.stableClassName(class_name) });
    try ctx.vm.initObjectProperties(obj, class_name);
    if (ctx.vm.hasMethod(class_name, "__construct")) {
        _ = try callOn(ctx, obj, "__construct", args);
        if (pending(ctx)) return .undef;
    }
    return .{ .object = obj };
}

// a string toPhpString made, handed to the caller
fn ownedResult(v: Value) NativeResult {
    if (v == .string and v.string.owner != null) return NativeResult.takeString(v.string);
    return .{ .value = v };
}

// zval_get_string: .undef when it throws. the caller owns a string result
fn toPhpString(ctx: *NativeContext, v: Value) RuntimeError!Value {
    if (pending(ctx)) return .undef;
    switch (v) {
        .string => |s| {
            s.retain();
            return v;
        },
        .object => |o| {
            const r = try guarded(ctx, objectStringValue, .{ ctx.vm, o });
            return r;
        },
        .array => {
            ctx.vm.emitWarning("Array to string conversion") catch |err| {
                if (!pending(ctx)) return err;
            };
            return .{ .string = try Value.String.create(ctx.allocator, "Array") };
        },
        .null, .undef => return .{ .string = Value.String.borrowed("") },
        else => {
            var buf: std.ArrayListUnmanaged(u8) = .empty;
            defer buf.deinit(ctx.allocator);
            try v.format(&buf, ctx.allocator);
            return .{ .string = try Value.String.create(ctx.allocator, buf.items) };
        },
    }
}

fn objectStringValue(vm: *VM, obj: *PhpObject) RuntimeError!Value {
    return .{ .string = try vm.objectString(obj) };
}

// keeps a value alive across php code; an array is left alone, since a
// release at zero would queue it for freeing while its owner still holds it
fn hold(v: Value) void {
    if (v != .array) VM.retainValue(v);
}

fn unhold(ctx: *NativeContext, v: Value) void {
    if (v != .array) ctx.vm.releaseValue(v);
}

fn releaseString(v: Value) void {
    if (v == .string) v.string.release();
}

// ==========================================
// argument parsing (zend_parse_parameters)
// ==========================================

fn typeError(ctx: *NativeContext, label: []const u8, n: usize, pname: []const u8, expected: []const u8, v: Value) RuntimeError!void {
    try raise(ctx, "TypeError", "{s}(): Argument #{d} (${s}) must be of type {s}, {s} given", .{ label, n, pname, expected, v.valueName() });
}

fn valueError(ctx: *NativeContext, label: []const u8, n: usize, pname: []const u8, comptime what: []const u8) RuntimeError!void {
    try raise(ctx, "ValueError", "{s}(): Argument #{d} (${s}) " ++ what, .{ label, n, pname });
}

// "O": an object of a class
fn argObject(ctx: *NativeContext, label: []const u8, args: []const Value, i: usize, pname: []const u8, class: []const u8) RuntimeError!?Value {
    const v = args[i];
    if (isInstance(ctx.vm, v, class)) return v;
    try typeError(ctx, label, i + 1, pname, class, v);
    return null;
}

// "l"
fn argLong(ctx: *NativeContext, label: []const u8, args: []const Value, i: usize, pname: []const u8, default: i64) RuntimeError!?i64 {
    if (i >= args.len) return default;
    const v = args[i];
    switch (v) {
        .int => |n| return n,
        .bool => |b| return @intFromBool(b),
        .float => |f| {
            if (std.math.isFinite(f) and f >= -9.2233720368547758e18 and f < 9.2233720368547758e18) {
                const n: i64 = @intFromFloat(f);
                if (@as(f64, @floatFromInt(n)) != f) {
                    const msg = try std.fmt.allocPrint(ctx.allocator, "Implicit conversion from float {s} to int loses precision", .{try floatText(ctx, f)});
                    defer ctx.allocator.free(msg);
                    try ctx.vm.raiseError(VM.E_DEPRECATED, msg);
                }
                return n;
            }
        },
        .string => |s| if (Value.isNumericString(s.bytes())) {
            const as_float = Value.toFloat(v);
            if (std.math.isFinite(as_float) and as_float >= -9.2233720368547758e18 and as_float < 9.2233720368547758e18) return Value.toInt(v);
        },
        .null => {
            const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): Passing null to parameter #{d} (${s}) of type int is deprecated", .{ label, i + 1, pname });
            defer ctx.allocator.free(msg);
            try ctx.vm.raiseError(VM.E_DEPRECATED, msg);
            return 0;
        },
        else => {},
    }
    try typeError(ctx, label, i + 1, pname, "int", v);
    return null;
}

// "S": the caller owns the string
fn argString(ctx: *NativeContext, label: []const u8, args: []const Value, i: usize, pname: []const u8) RuntimeError!?Value.String {
    const v = args[i];
    switch (v) {
        .string => |s| {
            s.retain();
            return s;
        },
        .int, .float, .bool => {
            var buf: std.ArrayListUnmanaged(u8) = .empty;
            defer buf.deinit(ctx.allocator);
            try v.format(&buf, ctx.allocator);
            return try Value.String.create(ctx.allocator, buf.items);
        },
        .object => |o| if (ctx.vm.hasMethod(o.class_name, "__toString")) {
            const r = try toPhpString(ctx, v);
            if (r == .undef) return null;
            return r.string;
        },
        .null => {
            const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): Passing null to parameter #{d} (${s}) of type string is deprecated", .{ label, i + 1, pname });
            defer ctx.allocator.free(msg);
            try ctx.vm.raiseError(VM.E_DEPRECATED, msg);
            return Value.String.borrowed("");
        },
        else => {},
    }
    try typeError(ctx, label, i + 1, pname, "string", v);
    return null;
}

fn argCount(ctx: *NativeContext, label: []const u8, n: usize, min: usize, max: usize) RuntimeError!bool {
    if (n >= min and n <= max) return true;
    const few = n < min;
    const bound = if (few) min else max;
    const kind = if (min == max) "exactly" else if (few) "at least" else "at most";
    try raise(ctx, "ArgumentCountError", "{s}() expects {s} {d} argument{s}, {d} given", .{ label, kind, bound, if (bound == 1) "" else "s", n });
    return false;
}

// ==========================================
// state kept in a private array
// ==========================================

fn stateOf(obj: *PhpObject, comptime prop: []const u8) ?*PhpArray {
    const v = obj.get(prop);
    return if (v == .array) v.array else null;
}

fn slot(arr: *PhpArray, i: usize) Value {
    return arr.entries.items[i].value;
}

fn slotInt(arr: *PhpArray, i: usize) i64 {
    const v = slot(arr, i);
    return if (v == .int) v.int else 0;
}

fn setSlot(ctx: *NativeContext, arr: *PhpArray, i: usize, v: Value) RuntimeError!void {
    try arr.set(ctx.allocator, .{ .int = @intCast(i) }, v);
}

fn newState(ctx: *NativeContext, n: usize) RuntimeError!*PhpArray {
    const arr = try ctx.createArray();
    for (0..n) |_| try arr.append(ctx.allocator, .undef);
    return arr;
}

// ==========================================
// ObjIter: php's zend_object_iterator
// ==========================================

// classes whose objects php iterates with an iterator of their own (a
// get_iterator handler) rather than through their methods, as long as no
// user class in between overrides one of the iterator methods
const internal_iterators = [_][]const u8{
    "ArrayIterator",      "RecursiveArrayIterator",     "ArrayObject",      "SplDoublyLinkedList",
    "SplQueue",           "SplStack",                   "SplFixedArray",    "SplHeap",
    "SplMinHeap",         "SplMaxHeap",                 "SplPriorityQueue", "DirectoryIterator",
    "FilesystemIterator", "RecursiveDirectoryIterator", "GlobIterator",     "SimpleXMLElement",
    "SimpleXMLIterator",  "RecursiveIteratorIterator",
};

const iterator_methods = [_][]const u8{ "rewind", "valid", "current", "key", "next" };

// whether php reaches this class through zend_user_iterator, which fetches
// current() once per position
fn userIterated(vm: *VM, class_name: []const u8) bool {
    var current: ?[]const u8 = class_name;
    while (current) |cn| {
        const def = vm.classes.get(cn) orelse return true;
        if (def.is_internal) {
            for (internal_iterators) |name| if (std.ascii.eqlIgnoreCase(name, def.name)) {
                for (iterator_methods) |m| if (userMethod(vm, class_name, m)) return true;
                return false;
            };
            return true;
        }
        current = def.parent;
    }
    return true;
}

// three slots of a state array: the iterated object or generator (.undef
// when there is none), the cached current() (.undef when not fetched), and
// whether current() is cached at all
const ObjIter = struct {
    arr: *PhpArray,
    base: usize,

    const width = 3;

    fn target(self: ObjIter) Value {
        return slot(self.arr, self.base);
    }

    fn present(self: ObjIter) bool {
        return self.target() != .undef;
    }

    fn init(self: ObjIter, ctx: *NativeContext, t: Value) RuntimeError!void {
        try setSlot(ctx, self.arr, self.base, t);
        try setSlot(ctx, self.arr, self.base + 1, .undef);
        const cached = t == .object and userIterated(ctx.vm, t.object.class_name);
        try setSlot(ctx, self.arr, self.base + 2, .{ .bool = cached });
    }

    fn clear(self: ObjIter, ctx: *NativeContext) RuntimeError!void {
        try setSlot(ctx, self.arr, self.base + 1, .undef);
        try setSlot(ctx, self.arr, self.base, .undef);
    }

    fn invalidate(self: ObjIter, ctx: *NativeContext) RuntimeError!void {
        if (slot(self.arr, self.base + 1) != .undef) try setSlot(ctx, self.arr, self.base + 1, .undef);
    }

    fn valid(self: ObjIter, ctx: *NativeContext) RuntimeError!bool {
        switch (self.target()) {
            .object => |o| {
                const r = try callOn(ctx, o, "valid", &.{});
                return r != .undef and r.isTruthy();
            },
            .generator => |g| {
                try initGen(ctx, g);
                return g.state != .completed;
            },
            else => return false,
        }
    }

    // get_current_data: .undef stands for php's NULL or UNDEF data
    fn current(self: ObjIter, ctx: *NativeContext) RuntimeError!Value {
        switch (self.target()) {
            .object => |o| {
                const cached = slot(self.arr, self.base + 2) == .bool and slot(self.arr, self.base + 2).bool;
                if (cached) {
                    const have = slot(self.arr, self.base + 1);
                    if (have != .undef) return have;
                }
                const r = try callOn(ctx, o, "current", &.{});
                if (r == .undef) return .undef;
                // the slot holds it either way, so the caller can borrow it
                try setSlot(ctx, self.arr, self.base + 1, r);
                return slot(self.arr, self.base + 1);
            },
            .generator => |g| {
                try initGen(ctx, g);
                if (g.state == .completed or pending(ctx)) return .undef;
                return VM.generatorRoot(g).current_value;
            },
            else => return .undef,
        }
    }

    fn key(self: ObjIter, ctx: *NativeContext) RuntimeError!Value {
        switch (self.target()) {
            .object => |o| return callOn(ctx, o, "key", &.{}),
            .generator => |g| {
                try initGen(ctx, g);
                if (pending(ctx)) return .undef;
                if (g.state == .completed) return .null;
                return VM.generatorRoot(g).current_key;
            },
            else => return .null,
        }
    }

    fn next(self: ObjIter, ctx: *NativeContext) RuntimeError!void {
        switch (self.target()) {
            .object => |o| {
                try self.invalidate(ctx);
                _ = try callOn(ctx, o, "next", &.{});
            },
            .generator => |g| {
                try initGen(ctx, g);
                try resumeGen(ctx, g);
            },
            else => {},
        }
    }

    fn rewind(self: ObjIter, ctx: *NativeContext) RuntimeError!void {
        switch (self.target()) {
            .object => |o| {
                try self.invalidate(ctx);
                _ = try callOn(ctx, o, "rewind", &.{});
            },
            .generator => |g| {
                if (pending(ctx)) return;
                _ = try guarded(ctx, rewindGenVoid, .{ ctx.vm, g });
            },
            else => {},
        }
    }
};

// ce->get_iterator: an Iterator iterates itself, an IteratorAggregate the
// iterator getIterator() returns (zend_user_it_get_new_iterator, again for
// an aggregate that returns another). .undef when it throws
fn iterTarget(ctx: *NativeContext, v: Value) RuntimeError!Value {
    var cur = v;
    var steps: usize = 0;
    while (steps < 64) : (steps += 1) {
        if (pending(ctx)) return .undef;
        switch (cur) {
            .generator => |g| {
                if (g.state == .completed) {
                    try raise(ctx, "Exception", "Cannot traverse an already closed generator", .{});
                    return .undef;
                }
                return cur;
            },
            .object => |o| {
                if (ctx.vm.isInstanceOf(o.class_name, "Iterator")) return cur;
                if (!ctx.vm.isInstanceOf(o.class_name, "IteratorAggregate")) return cur;
                const r = try callOn(ctx, o, "getIterator", &.{});
                if (r == .undef) return .undef;
                const traversable = (r == .object and ctx.vm.isInstanceOf(r.object.class_name, "Traversable") and r.object != o) or r == .generator;
                if (!traversable) {
                    try raise(ctx, "Exception", "Objects returned by {s}::getIterator() must be traversable or implement interface Iterator", .{o.class_name});
                    return .undef;
                }
                cur = r;
            },
            else => return .undef,
        }
    }
    return cur;
}

// an IteratorAggregate that is no Iterator too: php forbids a class both,
// but zphp's SimpleXMLIterator inherits one and implements the other
fn isAggregate(vm: *VM, obj: *PhpObject) bool {
    return vm.isInstanceOf(obj.class_name, "IteratorAggregate") and !vm.isInstanceOf(obj.class_name, "Iterator");
}

// spl_get_iterator_from_aggregate. .undef when it throws
fn fromAggregate(ctx: *NativeContext, obj: *PhpObject, class_label: []const u8) RuntimeError!Value {
    const r = try callOn(ctx, obj, "getIterator", &.{});
    if (r == .undef) return .undef;
    if ((r == .object and ctx.vm.isInstanceOf(r.object.class_name, "Traversable")) or r == .generator) return r;
    try raise(ctx, "LogicException", "{s}::getIterator() must return an object that implements Traversable", .{class_label});
    return .undef;
}

// ==========================================
// spl_dual_it_object
// ==========================================

const DIT = struct {
    const default: i64 = 0; // FilterIterator, RecursiveFilterIterator, ParentIterator
    const limit: i64 = 1;
    const caching: i64 = 2;
    const recursive_caching: i64 = 3;
    const iterator_iterator: i64 = 4;
    const no_rewind: i64 = 5;
    const infinite: i64 = 6;
    const append: i64 = 7;
    const regex: i64 = 8;
    const recursive_regex: i64 = 9;
    const callback_filter: i64 = 10;
    const recursive_callback_filter: i64 = 11;
};

// slots of the "__dit" state array
const D_TYPE = 0;
const D_INNER = 1; // inner.zobject, .undef when none
const D_IT = 2; // ObjIter over the inner object (3 slots)
const D_DATA = 5; // current.data
const D_KEY = 6; // current.key
const D_POS = 7; // current.pos
const D_U0 = 8;
const D_U1 = 9;
const D_U2 = 10;
const D_U3 = 11;
const D_LEN = 12;

// limit
const D_OFFSET = D_U0;
const D_COUNT = D_U1;
// caching
const D_CFLAGS = D_U0;
const D_ZSTR = D_U1;
const D_CHILDREN = D_U2;
const D_CACHE = D_U3;
// append
const D_ARRAYIT = D_U0;
// regex
const D_RFLAGS = D_U0;
const D_PREG_FLAGS = D_U1;
const D_REGEX = D_U2;
const D_MODE = D_U3;
// callback filter
const D_CALLBACK = D_U0;

const CIT_CALL_TOSTRING: i64 = 0x1;
const CIT_TOSTRING_USE_KEY: i64 = 0x2;
const CIT_TOSTRING_USE_CURRENT: i64 = 0x4;
const CIT_TOSTRING_USE_INNER: i64 = 0x8;
const CIT_CATCH_GET_CHILD: i64 = 0x10;
const CIT_FULL_CACHE: i64 = 0x100;
const CIT_PUBLIC: i64 = 0xFFFF;
const CIT_VALID: i64 = 0x10000;

const REGIT_USE_KEY: i64 = 1;
const REGIT_INVERTED: i64 = 2;
const REGIT_MODE_MATCH: i64 = 0;
const REGIT_MODE_GET_MATCH: i64 = 1;
const REGIT_MODE_ALL_MATCHES: i64 = 2;
const REGIT_MODE_SPLIT: i64 = 3;
const REGIT_MODE_REPLACE: i64 = 4;
const REGIT_MODE_MAX: i64 = 5;

const Dual = struct {
    obj: *PhpObject,
    st: *PhpArray,

    fn kind(self: Dual) i64 {
        return slotInt(self.st, D_TYPE);
    }

    fn it(self: Dual) ObjIter {
        return .{ .arr = self.st, .base = D_IT };
    }

    fn get(self: Dual, i: usize) Value {
        return slot(self.st, i);
    }

    fn int(self: Dual, i: usize) i64 {
        return slotInt(self.st, i);
    }

    fn put(self: Dual, ctx: *NativeContext, i: usize, v: Value) RuntimeError!void {
        try setSlot(ctx, self.st, i, v);
    }

    fn isCaching(self: Dual) bool {
        const k = self.kind();
        return k == DIT.caching or k == DIT.recursive_caching;
    }
};

fn dualRaw(obj: *PhpObject) ?Dual {
    const st = stateOf(obj, "__dit") orelse return null;
    return .{ .obj = obj, .st = st };
}

// SPL_FETCH_AND_CHECK_DUAL_IT
fn dualOf(ctx: *NativeContext) RuntimeError!?Dual {
    if (thisObj(ctx)) |obj| if (dualRaw(obj)) |d| return d;
    try raise(ctx, "Error", "The object is in an invalid state as the parent constructor was not called", .{});
    return null;
}

const InnerType = enum { iterator, traversable, recursive };

fn innerClass(t: InnerType) []const u8 {
    return switch (t) {
        .iterator => "Iterator",
        .traversable => "Traversable",
        .recursive => "RecursiveIterator",
    };
}

// spl_dual_it_construct. null when it throws
fn dualConstruct(ctx: *NativeContext, args: []const Value, base: []const u8, inner_type: InnerType, kind: i64) RuntimeError!?Dual {
    const obj = thisObj(ctx) orelse return null;
    var label_buf: [96]u8 = undefined;
    const label = std.fmt.bufPrint(&label_buf, "{s}::__construct", .{base}) catch base;
    if (dualRaw(obj) != null) {
        try raise(ctx, "BadMethodCallException", "{s}::getIterator() must be called exactly once per instance", .{base});
        return null;
    }
    const st = try newState(ctx, D_LEN);
    // owned by the object once it is stored; until then the array is ours
    VM.retainValue(.{ .array = st });
    defer ctx.vm.releaseValue(.{ .array = st });
    const d: Dual = .{ .obj = obj, .st = st };

    if (kind == DIT.append) {
        if (!try argCount(ctx, label, args.len, 0, 0)) return null;
        try d.put(ctx, D_TYPE, .{ .int = kind });
        try d.put(ctx, D_POS, .{ .int = 0 });
        try obj.set(ctx.allocator, "__dit", .{ .array = st });
        const arrayit = try construct(ctx, "ArrayIterator", &.{});
        if (arrayit == .undef) return null;
        try d.put(ctx, D_ARRAYIT, arrayit);
        return d;
    }

    var zobject: Value = .undef;
    switch (kind) {
        DIT.limit => {
            if (!try argCount(ctx, label, args.len, 1, 3)) return null;
            zobject = (try argObject(ctx, label, args, 0, "iterator", innerClass(inner_type))) orelse return null;
            const offset = (try argLong(ctx, label, args, 1, "offset", 0)) orelse return null;
            const count = (try argLong(ctx, label, args, 2, "limit", -1)) orelse return null;
            if (offset < 0) {
                try valueError(ctx, label, 2, "offset", "must be greater than or equal to 0");
                return null;
            }
            if (count < -1) {
                try valueError(ctx, label, 3, "limit", "must be greater than or equal to -1");
                return null;
            }
            try d.put(ctx, D_OFFSET, .{ .int = offset });
            try d.put(ctx, D_COUNT, .{ .int = count });
        },
        DIT.caching, DIT.recursive_caching => {
            if (!try argCount(ctx, label, args.len, 1, 2)) return null;
            zobject = (try argObject(ctx, label, args, 0, "iterator", innerClass(inner_type))) orelse return null;
            const flags = (try argLong(ctx, label, args, 1, "flags", CIT_CALL_TOSTRING)) orelse return null;
            if (!citFlagsOk(flags)) {
                try valueError(ctx, label, 2, "flags", "must contain only one of CachingIterator::CALL_TOSTRING, CachingIterator::TOSTRING_USE_KEY, CachingIterator::TOSTRING_USE_CURRENT, or CachingIterator::TOSTRING_USE_INNER");
                return null;
            }
            try d.put(ctx, D_CFLAGS, .{ .int = flags & CIT_PUBLIC });
            try d.put(ctx, D_CACHE, .{ .array = try ctx.createArray() });
        },
        DIT.iterator_iterator => {
            if (!try argCount(ctx, label, args.len, 1, 2)) return null;
            zobject = (try argObject(ctx, label, args, 0, "iterator", "Traversable")) orelse return null;
            var cast: ?[]const u8 = null;
            var cast_str: ?Value.String = null;
            defer if (cast_str) |s| s.release();
            if (args.len > 1 and args[1] != .null) {
                cast_str = (try argString(ctx, label, args, 1, "class")) orelse return null;
                cast = cast_str.?.bytes();
            }
            if (zobject == .object and !ctx.vm.isInstanceOf(zobject.object.class_name, "Iterator")) {
                const o = zobject.object;
                var ce: []const u8 = o.class_name;
                if (cast) |name| {
                    ctx.vm.tryAutoload(name) catch |err| if (!pending(ctx)) return err;
                    if (pending(ctx)) return null;
                    const known = ctx.vm.classes.contains(name) or ctx.vm.interfaces.contains(name);
                    if (!known or !ctx.vm.isInstanceOf(o.class_name, name) or !ctx.vm.isInstanceOf(name, "Traversable")) {
                        try raise(ctx, "LogicException", "Class to downcast to not found or not base class or does not implement Traversable", .{});
                        return null;
                    }
                    ce = ctx.vm.declaredClassName(name);
                }
                if (ctx.vm.isInstanceOf(ce, "IteratorAggregate")) {
                    const r = try fromAggregateAs(ctx, o, ce);
                    if (r == .undef) return null;
                    zobject = r;
                }
            }
        },
        DIT.regex, DIT.recursive_regex => {
            if (!try argCount(ctx, label, args.len, 2, 5)) return null;
            zobject = (try argObject(ctx, label, args, 0, "iterator", innerClass(inner_type))) orelse return null;
            const regex = (try argString(ctx, label, args, 1, "pattern")) orelse return null;
            defer regex.release();
            const mode = (try argLong(ctx, label, args, 2, "mode", REGIT_MODE_MATCH)) orelse return null;
            const flags = (try argLong(ctx, label, args, 3, "flags", 0)) orelse return null;
            const preg_flags = (try argLong(ctx, label, args, 4, "pregFlags", 0)) orelse return null;
            if (mode < 0 or mode >= REGIT_MODE_MAX) {
                try valueError(ctx, label, 3, "mode", "must be RegexIterator::MATCH, RegexIterator::GET_MATCH, RegexIterator::ALL_MATCHES, RegexIterator::SPLIT, or RegexIterator::REPLACE");
                return null;
            }
            if (try pcre.patternProblem(ctx, regex.bytes())) |problem| {
                defer ctx.allocator.free(problem);
                try raise(ctx, "InvalidArgumentException", "{s}(): {s}", .{ label, problem });
                return null;
            }
            try d.put(ctx, D_RFLAGS, .{ .int = flags });
            try d.put(ctx, D_PREG_FLAGS, .{ .int = preg_flags });
            try d.put(ctx, D_REGEX, .{ .string = regex });
            try d.put(ctx, D_MODE, .{ .int = mode });
        },
        DIT.callback_filter, DIT.recursive_callback_filter => {
            if (!try argCount(ctx, label, args.len, 2, 2)) return null;
            zobject = (try argObject(ctx, label, args, 0, "iterator", innerClass(inner_type))) orelse return null;
            try d.put(ctx, D_CALLBACK, args[1]);
        },
        else => {
            if (!try argCount(ctx, label, args.len, 1, 1)) return null;
            zobject = (try argObject(ctx, label, args, 0, "iterator", innerClass(inner_type))) orelse return null;
        },
    }

    try d.put(ctx, D_TYPE, .{ .int = kind });
    try d.put(ctx, D_INNER, zobject);
    try d.put(ctx, D_POS, .{ .int = 0 });
    try obj.set(ctx.allocator, "__dit", .{ .array = st });
    const t = try iterTarget(ctx, zobject);
    if (t != .undef) try d.it().init(ctx, t);
    return d;
}

// spl_get_iterator_from_aggregate on a class an object was downcast to: its
// own getIterator(), not an override below it
fn fromAggregateAs(ctx: *NativeContext, obj: *PhpObject, ce: []const u8) RuntimeError!Value {
    const full = ctx.vm.resolveMethod(ce, "getIterator") catch return fromAggregate(ctx, obj, ce);
    const r = try guarded(ctx, VM.callMethodAs, .{ ctx.vm, obj, "getIterator", full, &[_]Value{} });
    if (r == .undef) return .undef;
    if ((r == .object and ctx.vm.isInstanceOf(r.object.class_name, "Traversable")) or r == .generator) return r;
    try raise(ctx, "LogicException", "{s}::getIterator() must return an object that implements Traversable", .{ce});
    return .undef;
}

fn citFlagsOk(flags: i64) bool {
    var n: u8 = 0;
    if (flags & CIT_CALL_TOSTRING != 0) n += 1;
    if (flags & CIT_TOSTRING_USE_KEY != 0) n += 1;
    if (flags & CIT_TOSTRING_USE_CURRENT != 0) n += 1;
    if (flags & CIT_TOSTRING_USE_INNER != 0) n += 1;
    return n <= 1;
}

fn dualFree(ctx: *NativeContext, d: Dual) RuntimeError!void {
    if (d.it().present()) try d.it().invalidate(ctx);
    try d.put(ctx, D_DATA, .undef);
    try d.put(ctx, D_KEY, .undef);
    if (d.isCaching()) {
        try d.put(ctx, D_ZSTR, .undef);
        try d.put(ctx, D_CHILDREN, .undef);
    }
}

fn dualRewind(ctx: *NativeContext, d: Dual) RuntimeError!void {
    try dualFree(ctx, d);
    try d.put(ctx, D_POS, .{ .int = 0 });
    if (d.it().present()) try d.it().rewind(ctx);
}

fn dualValid(ctx: *NativeContext, d: Dual) RuntimeError!bool {
    if (!d.it().present()) return false;
    return d.it().valid(ctx);
}

// spl_dual_it_fetch: true on SUCCESS
fn dualFetch(ctx: *NativeContext, d: Dual, check_more: bool) RuntimeError!bool {
    try dualFree(ctx, d);
    if (!check_more or try dualValid(ctx, d)) {
        const data = try d.it().current(ctx);
        if (data != .undef) try d.put(ctx, D_DATA, data);
        const key = try d.it().key(ctx);
        if (!pending(ctx)) try d.put(ctx, D_KEY, key);
        return !pending(ctx);
    }
    return false;
}

fn dualNext(ctx: *NativeContext, d: Dual, do_free: bool) RuntimeError!void {
    if (do_free) {
        try dualFree(ctx, d);
    } else if (!d.it().present()) {
        try raise(ctx, "Error", "The inner constructor wasn't initialized with an iterator instance", .{});
        return;
    }
    try d.it().next(ctx);
    try d.put(ctx, D_POS, .{ .int = d.int(D_POS) + 1 });
}

fn shareSlot(d: Dual, i: usize) NativeResult {
    const v = d.get(i);
    if (v == .undef) return NativeResult.scalar(.null);
    return NativeResult.share(v);
}

// ==========================================
// IteratorIterator
// ==========================================

fn iiConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = try dualConstruct(ctx, args, "IteratorIterator", .traversable, DIT.iterator_iterator);
    return finishNull(ctx);
}

fn iiGetInnerIterator(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    return shareSlot(d, D_INNER);
}

fn iiRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    try dualRewind(ctx, d);
    _ = try dualFetch(ctx, d, true);
    return finishNull(ctx);
}

fn iiValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    return NativeResult.scalar(.{ .bool = d.get(D_DATA) != .undef });
}

fn iiKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    return shareSlot(d, D_KEY);
}

fn iiCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    return shareSlot(d, D_DATA);
}

fn iiNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    try dualNext(ctx, d, true);
    _ = try dualFetch(ctx, d, true);
    return finishNull(ctx);
}

// ==========================================
// FilterIterator and its kin
// ==========================================

fn filterFetch(ctx: *NativeContext, d: Dual) RuntimeError!void {
    while (try dualFetch(ctx, d, true)) {
        const r = try callOn(ctx, d.obj, "accept", &.{});
        if (r != .undef and r.isTruthy()) return;
        if (pending(ctx)) return;
        try d.it().next(ctx);
    }
    try dualFree(ctx, d);
}

fn filterConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = try dualConstruct(ctx, args, "FilterIterator", .iterator, DIT.default);
    return finishNull(ctx);
}

fn filterRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    try dualRewind(ctx, d);
    try filterFetch(ctx, d);
    return finishNull(ctx);
}

fn filterNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    try dualNext(ctx, d, true);
    try filterFetch(ctx, d);
    return finishNull(ctx);
}

fn rfiConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = try dualConstruct(ctx, args, "RecursiveFilterIterator", .recursive, DIT.default);
    return finishNull(ctx);
}

fn parentConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = try dualConstruct(ctx, args, "ParentIterator", .recursive, DIT.default);
    return finishNull(ctx);
}

// RecursiveFilterIterator::hasChildren, also ParentIterator::accept and
// RecursiveCallbackFilterIterator::hasChildren
fn rfiHasChildren(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    const inner = d.get(D_INNER);
    if (inner != .object) return finishNull(ctx);
    const r = try callOn(ctx, inner.object, "hasChildren", &.{});
    if (r == .undef) return finishNull(ctx);
    return finish(ctx, NativeResult.share(r));
}

fn innerChildren(ctx: *NativeContext, d: Dual) RuntimeError!Value {
    const inner = d.get(D_INNER);
    if (inner != .object) return .undef;
    const r = try callOn(ctx, inner.object, "getChildren", &.{});
    if (r == .undef) return .undef;
    // the children live in a slot of their own until they are handed on
    VM.retainValue(r);
    return r;
}

fn rfiGetChildren(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    const children = try innerChildren(ctx, d);
    if (children == .undef) return error.RuntimeError;
    defer ctx.vm.releaseValue(children);
    const r = try construct(ctx, d.obj.class_name, &.{children});
    if (r == .undef) return error.RuntimeError;
    return finish(ctx, NativeResult.borrowed(r));
}

fn cbfConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = try dualConstruct(ctx, args, "CallbackFilterIterator", .iterator, DIT.callback_filter);
    return finishNull(ctx);
}

fn rcbfConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = try dualConstruct(ctx, args, "RecursiveCallbackFilterIterator", .recursive, DIT.recursive_callback_filter);
    return finishNull(ctx);
}

fn cbfAccept(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    const data = d.get(D_DATA);
    const key = d.get(D_KEY);
    if (data == .undef or key == .undef) return NativeResult.scalar(.{ .bool = false });
    const callback = d.get(D_CALLBACK);
    const r = try callValue(ctx, callback, &.{ data, key, d.get(D_INNER) });
    if (r == .undef) return finish(ctx, NativeResult.scalar(.{ .bool = false }));
    return finish(ctx, NativeResult.share(r));
}

fn rcbfGetChildren(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    const children = try innerChildren(ctx, d);
    if (children == .undef) return error.RuntimeError;
    defer ctx.vm.releaseValue(children);
    const r = try construct(ctx, d.obj.class_name, &.{ children, d.get(D_CALLBACK) });
    if (r == .undef) return error.RuntimeError;
    return finish(ctx, NativeResult.borrowed(r));
}

// ==========================================
// RegexIterator
// ==========================================

const pcre = @import("pcre.zig");

fn rxConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = try dualConstruct(ctx, args, "RegexIterator", .iterator, DIT.regex);
    return finishNull(ctx);
}

fn rrxConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = try dualConstruct(ctx, args, "RecursiveRegexIterator", .recursive, DIT.recursive_regex);
    return finishNull(ctx);
}

fn regexAccept(ctx: *NativeContext, d: Dual) RuntimeError!NativeResult {
    if (d.get(D_DATA) == .undef) return NativeResult.scalar(.{ .bool = false });
    const flags = d.int(D_RFLAGS);
    const subject_src = if (flags & REGIT_USE_KEY != 0) d.get(D_KEY) else d.get(D_DATA);
    if (flags & REGIT_USE_KEY == 0 and subject_src == .array) return NativeResult.scalar(.{ .bool = false });
    const subject = try toPhpString(ctx, subject_src);
    if (subject == .undef) return error.RuntimeError;
    defer releaseString(subject);
    const regex = d.get(D_REGEX);
    const preg_flags: Value = .{ .int = d.int(D_PREG_FLAGS) };
    var matched = false;
    switch (d.int(D_MODE)) {
        REGIT_MODE_GET_MATCH, REGIT_MODE_ALL_MATCHES => {
            try d.put(ctx, D_DATA, .undef);
            const name = if (d.int(D_MODE) == REGIT_MODE_ALL_MATCHES) "preg_match_all" else "preg_match";
            var call_args = [_]Value{ regex, subject, .null, preg_flags };
            const r = try guarded(ctx, VM.callByNameRef, .{ ctx.vm, name, call_args[0..] });
            if (call_args[2] == .array) try d.put(ctx, D_DATA, call_args[2]);
            matched = r == .int and r.int > 0;
        },
        REGIT_MODE_SPLIT => {
            try d.put(ctx, D_DATA, .undef);
            const r = try guarded(ctx, VM.callByName, .{ ctx.vm, "preg_split", &[_]Value{ regex, subject, .{ .int = -1 }, preg_flags } });
            if (r == .array) {
                try d.put(ctx, D_DATA, r);
                matched = r.array.length() > 1;
            }
        },
        REGIT_MODE_REPLACE => {
            const repl_prop = d.obj.get("replacement");
            const replacement = try toPhpString(ctx, repl_prop);
            if (replacement == .undef) return error.RuntimeError;
            defer releaseString(replacement);
            var call_args = [_]Value{ regex, replacement, subject, .{ .int = -1 }, .null };
            const r = try guarded(ctx, VM.callByNameRef, .{ ctx.vm, "preg_replace", call_args[0..] });
            if (r != .string) return finish(ctx, NativeResult.scalar(.{ .bool = false }));
            if (flags & REGIT_USE_KEY != 0) try d.put(ctx, D_KEY, r) else try d.put(ctx, D_DATA, r);
            matched = call_args[4] == .int and call_args[4].int > 0;
        },
        else => {
            const r = try guarded(ctx, VM.callByName, .{ ctx.vm, "preg_match", &[_]Value{ regex, subject } });
            matched = r == .int and r.int > 0;
        },
    }
    if (flags & REGIT_INVERTED != 0) matched = !matched;
    return finish(ctx, NativeResult.scalar(.{ .bool = matched }));
}

fn rxAccept(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    return regexAccept(ctx, d);
}

fn rxGetRegex(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    return shareSlot(d, D_REGEX);
}

fn rxGetMode(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    return NativeResult.scalar(.{ .int = d.int(D_MODE) });
}

fn rxSetMode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const label = "RegexIterator::setMode";
    if (!try argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const mode = (try argLong(ctx, label, args, 0, "mode", 0)) orelse return error.RuntimeError;
    if (mode < 0 or mode >= REGIT_MODE_MAX) {
        try valueError(ctx, label, 1, "mode", "must be RegexIterator::MATCH, RegexIterator::GET_MATCH, RegexIterator::ALL_MATCHES, RegexIterator::SPLIT, or RegexIterator::REPLACE");
        return error.RuntimeError;
    }
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    try d.put(ctx, D_MODE, .{ .int = mode });
    return finishNull(ctx);
}

fn rxGetFlags(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    return NativeResult.scalar(.{ .int = d.int(D_RFLAGS) });
}

fn rxSetFlags(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const label = "RegexIterator::setFlags";
    if (!try argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const flags = (try argLong(ctx, label, args, 0, "flags", 0)) orelse return error.RuntimeError;
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    try d.put(ctx, D_RFLAGS, .{ .int = flags });
    return finishNull(ctx);
}

fn rxGetPregFlags(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    return NativeResult.scalar(.{ .int = d.int(D_PREG_FLAGS) });
}

fn rxSetPregFlags(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const label = "RegexIterator::setPregFlags";
    if (!try argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const flags = (try argLong(ctx, label, args, 0, "pregFlags", 0)) orelse return error.RuntimeError;
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    try d.put(ctx, D_PREG_FLAGS, .{ .int = flags });
    return finishNull(ctx);
}

fn rrxGetChildren(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    const children = try innerChildren(ctx, d);
    if (children == .undef) return error.RuntimeError;
    defer ctx.vm.releaseValue(children);
    const r = try construct(ctx, d.obj.class_name, &.{
        children,
        d.get(D_REGEX),
        .{ .int = d.int(D_MODE) },
        .{ .int = d.int(D_RFLAGS) },
        .{ .int = d.int(D_PREG_FLAGS) },
    });
    if (r == .undef) return error.RuntimeError;
    return finish(ctx, NativeResult.borrowed(r));
}

fn rrxAccept(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    const data = d.get(D_DATA);
    if (data == .undef) return NativeResult.scalar(.{ .bool = false });
    if (data == .array) return NativeResult.scalar(.{ .bool = data.array.length() > 0 });
    return regexAccept(ctx, d);
}

// ==========================================
// LimitIterator
// ==========================================

fn limitValidState(ctx: *NativeContext, d: Dual) RuntimeError!bool {
    const count = d.int(D_COUNT);
    if (count != -1 and d.int(D_POS) - d.int(D_OFFSET) >= count) return false;
    return dualValid(ctx, d);
}

fn limitSeekTo(ctx: *NativeContext, d: Dual, pos: i64) RuntimeError!void {
    try dualFree(ctx, d);
    const offset = d.int(D_OFFSET);
    const count = d.int(D_COUNT);
    if (pos < offset) {
        try raise(ctx, "OutOfBoundsException", "Cannot seek to {d} which is below the offset {d}", .{ pos, offset });
        return;
    }
    if (pos - offset >= count and count != -1) {
        try raise(ctx, "OutOfBoundsException", "Cannot seek to {d} which is behind offset {d} plus count {d}", .{ pos, offset, count });
        return;
    }
    const inner = d.get(D_INNER);
    if (pos != d.int(D_POS) and isInstance(ctx.vm, inner, "SeekableIterator")) {
        try dualFree(ctx, d);
        _ = try callOn(ctx, inner.object, "seek", &.{.{ .int = pos }});
        if (!pending(ctx)) {
            try d.put(ctx, D_POS, .{ .int = pos });
            if (try limitValidState(ctx, d)) _ = try dualFetch(ctx, d, false);
        }
    } else {
        if (pos < d.int(D_POS)) try dualRewind(ctx, d);
        while (pos > d.int(D_POS) and try dualValid(ctx, d)) {
            if (pending(ctx)) return;
            try dualNext(ctx, d, true);
        }
        if (try dualValid(ctx, d)) _ = try dualFetch(ctx, d, true);
    }
}

fn limitConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = try dualConstruct(ctx, args, "LimitIterator", .iterator, DIT.limit);
    return finishNull(ctx);
}

fn limitRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    try dualRewind(ctx, d);
    try limitSeekTo(ctx, d, d.int(D_OFFSET));
    return finishNull(ctx);
}

fn limitValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    const count = d.int(D_COUNT);
    const ok = (count == -1 or d.int(D_POS) - d.int(D_OFFSET) < count) and d.get(D_DATA) != .undef;
    return NativeResult.scalar(.{ .bool = ok });
}

fn limitNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    try dualNext(ctx, d, true);
    const count = d.int(D_COUNT);
    if (count == -1 or d.int(D_POS) - d.int(D_OFFSET) < count) _ = try dualFetch(ctx, d, true);
    return finishNull(ctx);
}

fn limitSeek(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const label = "LimitIterator::seek";
    if (!try argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const pos = (try argLong(ctx, label, args, 0, "offset", 0)) orelse return error.RuntimeError;
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    try limitSeekTo(ctx, d, pos);
    return finish(ctx, NativeResult.scalar(.{ .int = d.int(D_POS) }));
}

fn limitGetPosition(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    return NativeResult.scalar(.{ .int = d.int(D_POS) });
}

// ==========================================
// CachingIterator, RecursiveCachingIterator
// ==========================================

fn cachingNext(ctx: *NativeContext, d: Dual) RuntimeError!void {
    if (try dualFetch(ctx, d, true)) {
        try d.put(ctx, D_CFLAGS, .{ .int = d.int(D_CFLAGS) | CIT_VALID });
        if (d.int(D_CFLAGS) & CIT_FULL_CACHE != 0) {
            const cache = d.get(D_CACHE).array;
            try setZvalKey(ctx, cache, d.get(D_KEY), d.get(D_DATA));
            if (pending(ctx)) return;
        }
        if (d.kind() == DIT.recursive_caching) {
            const inner = d.get(D_INNER).object;
            const catch_child = d.int(D_CFLAGS) & CIT_CATCH_GET_CHILD != 0;
            const has = try callOn(ctx, inner, "hasChildren", &.{});
            if (pending(ctx)) {
                if (!catch_child) return;
                ctx.vm.discardPending();
            } else if (has.isTruthy()) {
                const children = try callOn(ctx, inner, "getChildren", &.{});
                if (pending(ctx)) {
                    if (!catch_child) return;
                    ctx.vm.discardPending();
                } else {
                    VM.retainValue(children);
                    defer ctx.vm.releaseValue(children);
                    const r = try construct(ctx, "RecursiveCachingIterator", &.{ children, .{ .int = d.int(D_CFLAGS) & CIT_PUBLIC } });
                    if (r == .undef) {
                        if (!catch_child) return;
                        ctx.vm.discardPending();
                    } else {
                        try d.put(ctx, D_CHILDREN, r);
                    }
                }
            }
        }
        const flags = d.int(D_CFLAGS);
        if (flags & (CIT_TOSTRING_USE_INNER | CIT_CALL_TOSTRING) != 0) {
            const src = if (flags & CIT_TOSTRING_USE_INNER != 0) d.get(D_INNER) else d.get(D_DATA);
            const s = try toPhpString(ctx, src);
            if (s != .undef) {
                defer releaseString(s);
                try d.put(ctx, D_ZSTR, s);
            }
        }
        try dualNext(ctx, d, false);
    } else {
        try d.put(ctx, D_CFLAGS, .{ .int = d.int(D_CFLAGS) & ~CIT_VALID });
    }
}

fn floatText(ctx: *NativeContext, f: f64) RuntimeError![]const u8 {
    const s = try toPhpString(ctx, .{ .float = f });
    defer releaseString(s);
    return ctx.createString(s.string.bytes());
}

// array_set_zval_key
fn setZvalKey(ctx: *NativeContext, arr: *PhpArray, key: Value, data: Value) RuntimeError!void {
    const k: PhpArray.Key = switch (key) {
        .string => |s| .{ .string = s },
        .int => |n| .{ .int = n },
        .null, .undef => blk: {
            try ctx.vm.raiseError(VM.E_DEPRECATED, "Using null as an array offset is deprecated, use an empty string instead");
            break :blk .{ .string = Value.String.borrowed("") };
        },
        .bool => |b| .{ .int = @intFromBool(b) },
        .float => |f| blk: {
            const n = Value.toInt(.{ .float = f });
            if (!std.math.isFinite(f) or @as(f64, @floatFromInt(n)) != f) {
                const msg = try std.fmt.allocPrint(ctx.allocator, "Implicit conversion from float {s} to int loses precision", .{try floatText(ctx, f)});
                defer ctx.allocator.free(msg);
                try ctx.vm.raiseError(VM.E_DEPRECATED, msg);
            }
            break :blk .{ .int = n };
        },
        .resource => |r| blk: {
            const msg = try std.fmt.allocPrint(ctx.allocator, "Resource ID#{d} used as offset, casting to integer ({d})", .{ r.id, r.id });
            defer ctx.allocator.free(msg);
            try ctx.vm.emitWarning(msg);
            break :blk .{ .int = r.id };
        },
        else => {
            try raise(ctx, "TypeError", "Cannot access offset of type {s} on array", .{key.valueName()});
            return;
        },
    };
    if (k == .string) {
        try arr.setCopiedKey(ctx.allocator, k.string.bytes(), data);
    } else {
        try arr.set(ctx.allocator, k, data);
    }
}

fn ciConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = try dualConstruct(ctx, args, "CachingIterator", .iterator, DIT.caching);
    return finishNull(ctx);
}

fn rciConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = try dualConstruct(ctx, args, "RecursiveCachingIterator", .recursive, DIT.recursive_caching);
    return finishNull(ctx);
}

fn ciRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    try dualRewind(ctx, d);
    try clearArray(ctx, d.get(D_CACHE).array);
    try cachingNext(ctx, d);
    return finishNull(ctx);
}

fn clearArray(ctx: *NativeContext, arr: *PhpArray) RuntimeError!void {
    while (arr.entries.pop()) |e| {
        if (e.key == .string) e.key.string.release();
        ctx.vm.releaseValue(e.value);
    }
    arr.string_index.clearRetainingCapacity();
    arr.next_int_key = 0;
    arr.has_int_keys = false;
}

fn ciValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    return NativeResult.scalar(.{ .bool = d.int(D_CFLAGS) & CIT_VALID != 0 });
}

fn ciNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    try cachingNext(ctx, d);
    return finishNull(ctx);
}

fn ciHasNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    const ok = try dualValid(ctx, d);
    return finish(ctx, NativeResult.scalar(.{ .bool = ok }));
}

fn ciToString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    const flags = d.int(D_CFLAGS);
    if (flags & (CIT_CALL_TOSTRING | CIT_TOSTRING_USE_KEY | CIT_TOSTRING_USE_CURRENT | CIT_TOSTRING_USE_INNER) == 0) {
        return throwNow(ctx, "BadMethodCallException", "{s} does not fetch string value (see CachingIterator::__construct)", .{d.obj.class_name});
    }
    if (flags & (CIT_TOSTRING_USE_KEY | CIT_TOSTRING_USE_CURRENT) != 0) {
        const src = if (flags & CIT_TOSTRING_USE_KEY != 0) d.get(D_KEY) else d.get(D_DATA);
        const s = try toPhpString(ctx, src);
        if (s == .undef) return error.RuntimeError;
        return finish(ctx, ownedResult(s));
    }
    const zstr = d.get(D_ZSTR);
    if (zstr == .string) return NativeResult.shareString(zstr.string);
    return NativeResult.literal("");
}

fn fullCacheOf(ctx: *NativeContext, d: Dual) RuntimeError!?*PhpArray {
    if (d.int(D_CFLAGS) & CIT_FULL_CACHE == 0) {
        try raise(ctx, "BadMethodCallException", "{s} does not use a full cache (see CachingIterator::__construct)", .{d.obj.class_name});
        return null;
    }
    return d.get(D_CACHE).array;
}

fn cacheKey(ctx: *NativeContext, label: []const u8, args: []const Value, n_args: usize) RuntimeError!?Value.String {
    if (!try argCount(ctx, label, args.len, n_args, n_args)) return null;
    return argString(ctx, label, args, 0, "key");
}

fn ciOffsetSet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const key = (try cacheKey(ctx, "CachingIterator::offsetSet", args, 2)) orelse return error.RuntimeError;
    defer key.release();
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    const cache = (try fullCacheOf(ctx, d)) orelse return error.RuntimeError;
    try cache.set(ctx.allocator, .{ .string = key }, args[1]);
    return finishNull(ctx);
}

fn ciOffsetGet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const key = (try cacheKey(ctx, "CachingIterator::offsetGet", args, 1)) orelse return error.RuntimeError;
    defer key.release();
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    const cache = (try fullCacheOf(ctx, d)) orelse return error.RuntimeError;
    const k = PhpArray.normalizeKey(.{ .string = key });
    if (!cache.contains(k)) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "Undefined array key \"{s}\"", .{key.bytes()});
        defer ctx.allocator.free(msg);
        try ctx.vm.emitWarning(msg);
        return finishNull(ctx);
    }
    return finish(ctx, NativeResult.share(cache.get(k)));
}

fn ciOffsetUnset(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    const key = (try cacheKey(ctx, "CachingIterator::offsetUnset", args, 1)) orelse return error.RuntimeError;
    defer key.release();
    const cache = (try fullCacheOf(ctx, d)) orelse return error.RuntimeError;
    const k = PhpArray.normalizeKey(.{ .string = key });
    if (cache.contains(k)) {
        const old = cache.get(k);
        VM.retainValue(old);
        cache.remove(k);
        ctx.vm.releaseValue(old);
        ctx.vm.releaseValue(old);
    }
    return finishNull(ctx);
}

fn ciOffsetExists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const key = (try cacheKey(ctx, "CachingIterator::offsetExists", args, 1)) orelse return error.RuntimeError;
    defer key.release();
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    const cache = (try fullCacheOf(ctx, d)) orelse return error.RuntimeError;
    return NativeResult.scalar(.{ .bool = cache.contains(PhpArray.normalizeKey(.{ .string = key })) });
}

fn ciGetCache(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    const cache = (try fullCacheOf(ctx, d)) orelse return error.RuntimeError;
    return NativeResult.borrowed(.{ .array = try ctx.vm.cloneArray(cache) });
}

fn ciGetFlags(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    return NativeResult.scalar(.{ .int = d.int(D_CFLAGS) });
}

fn ciSetFlags(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const label = "CachingIterator::setFlags";
    if (!try argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const flags = (try argLong(ctx, label, args, 0, "flags", 0)) orelse return error.RuntimeError;
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    if (!citFlagsOk(flags)) {
        try valueError(ctx, label, 1, "flags", "must contain only one of CachingIterator::CALL_TOSTRING, CachingIterator::TOSTRING_USE_KEY, CachingIterator::TOSTRING_USE_CURRENT, or CachingIterator::TOSTRING_USE_INNER");
        return error.RuntimeError;
    }
    const cur = d.int(D_CFLAGS);
    if (cur & CIT_CALL_TOSTRING != 0 and flags & CIT_CALL_TOSTRING == 0) {
        return throwNow(ctx, "InvalidArgumentException", "Unsetting flag CALL_TO_STRING is not possible", .{});
    }
    if (cur & CIT_TOSTRING_USE_INNER != 0 and flags & CIT_TOSTRING_USE_INNER == 0) {
        return throwNow(ctx, "InvalidArgumentException", "Unsetting flag TOSTRING_USE_INNER is not possible", .{});
    }
    if (flags & CIT_FULL_CACHE != 0 and cur & CIT_FULL_CACHE == 0) try clearArray(ctx, d.get(D_CACHE).array);
    try d.put(ctx, D_CFLAGS, .{ .int = (cur & ~CIT_PUBLIC) | (flags & CIT_PUBLIC) });
    return finishNull(ctx);
}

fn ciCount(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    const cache = (try fullCacheOf(ctx, d)) orelse return error.RuntimeError;
    return NativeResult.scalar(.{ .int = cache.length() });
}

fn rciHasChildren(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    return NativeResult.scalar(.{ .bool = d.get(D_CHILDREN) != .undef });
}

fn rciGetChildren(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    return shareSlot(d, D_CHILDREN);
}

// ==========================================
// NoRewindIterator, InfiniteIterator
// ==========================================

fn nriConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = try dualConstruct(ctx, args, "NoRewindIterator", .iterator, DIT.no_rewind);
    return finishNull(ctx);
}

fn nriRewind(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.null);
}

fn nriValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    const ok = try d.it().valid(ctx);
    return finish(ctx, NativeResult.scalar(.{ .bool = ok }));
}

fn nriKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    const k = try d.it().key(ctx);
    if (k == .undef) return finishNull(ctx);
    return finish(ctx, NativeResult.share(k));
}

fn nriCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    const v = try d.it().current(ctx);
    if (v == .undef) return finishNull(ctx);
    return finish(ctx, NativeResult.share(v));
}

fn nriNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    try d.it().next(ctx);
    return finishNull(ctx);
}

fn infConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = try dualConstruct(ctx, args, "InfiniteIterator", .iterator, DIT.infinite);
    return finishNull(ctx);
}

fn infNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    try dualNext(ctx, d, true);
    if (try dualValid(ctx, d)) {
        _ = try dualFetch(ctx, d, false);
    } else {
        try dualRewind(ctx, d);
        if (try dualValid(ctx, d)) _ = try dualFetch(ctx, d, false);
    }
    return finishNull(ctx);
}

// ==========================================
// EmptyIterator
// ==========================================

fn emptyNoop(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.null);
}

fn emptyValid(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = false });
}

fn emptyKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return throwNow(ctx, "BadMethodCallException", "Accessing the key of an EmptyIterator", .{});
}

fn emptyCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return throwNow(ctx, "BadMethodCallException", "Accessing the value of an EmptyIterator", .{});
}

// ==========================================
// AppendIterator
// ==========================================

fn arrayIt(d: Dual) ?*PhpObject {
    const v = d.get(D_ARRAYIT);
    return if (v == .object) v.object else null;
}

fn arrayItValid(ctx: *NativeContext, d: Dual) RuntimeError!bool {
    const ai = arrayIt(d) orelse return false;
    const r = try callOn(ctx, ai, "valid", &.{});
    return r != .undef and r.isTruthy();
}

fn appendNextIterator(ctx: *NativeContext, d: Dual) RuntimeError!bool {
    try dualFree(ctx, d);
    if (d.get(D_INNER) != .undef) {
        try d.put(ctx, D_INNER, .undef);
        try d.it().clear(ctx);
    }
    if (try arrayItValid(ctx, d)) {
        const it = try callOn(ctx, arrayIt(d).?, "current", &.{});
        if (it == .undef) return false;
        try d.put(ctx, D_INNER, it);
        const t = try iterTarget(ctx, it);
        if (t != .undef) try d.it().init(ctx, t);
        try dualRewind(ctx, d);
        return true;
    }
    return false;
}

fn appendFetch(ctx: *NativeContext, d: Dual) RuntimeError!void {
    while (!try dualValid(ctx, d)) {
        if (pending(ctx)) return;
        if (arrayIt(d)) |ai| _ = try callOn(ctx, ai, "next", &.{});
        if (!try appendNextIterator(ctx, d)) return;
    }
    _ = try dualFetch(ctx, d, false);
}

fn appConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = try dualConstruct(ctx, args, "AppendIterator", .iterator, DIT.append);
    return finishNull(ctx);
}

fn appAppend(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const label = "AppendIterator::append";
    if (!try argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const it = (try argObject(ctx, label, args, 0, "iterator", "Iterator")) orelse return error.RuntimeError;
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    const ai = arrayIt(d) orelse return finishNull(ctx);
    if (try arrayItValid(ctx, d) and !try dualValid(ctx, d)) {
        _ = try callOn(ctx, ai, "append", &.{it});
        _ = try callOn(ctx, ai, "next", &.{});
    } else {
        _ = try callOn(ctx, ai, "append", &.{it});
    }
    if (pending(ctx)) return error.RuntimeError;
    if (!d.it().present() or !try dualValid(ctx, d)) {
        if (!try arrayItValid(ctx, d)) _ = try callOn(ctx, ai, "rewind", &.{});
        var guard: usize = 0;
        while (guard < 1 << 20) : (guard += 1) {
            const more = try appendNextIterator(ctx, d);
            if (pending(ctx)) break;
            const inner = d.get(D_INNER);
            if (sameValue(inner, it)) break;
            if (!more) break;
        }
        try appendFetch(ctx, d);
    }
    return finishNull(ctx);
}

fn sameValue(a: Value, b: Value) bool {
    if (a == .object and b == .object) return a.object == b.object;
    if (a == .generator and b == .generator) return a.generator == b.generator;
    return false;
}

fn appCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    _ = try dualFetch(ctx, d, true);
    if (pending(ctx)) return error.RuntimeError;
    return shareSlot(d, D_DATA);
}

fn appRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    if (arrayIt(d)) |ai| _ = try callOn(ctx, ai, "rewind", &.{});
    if (try appendNextIterator(ctx, d)) try appendFetch(ctx, d);
    return finishNull(ctx);
}

fn appValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    return NativeResult.scalar(.{ .bool = d.get(D_DATA) != .undef });
}

fn appNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    if (try dualValid(ctx, d)) try dualNext(ctx, d, true);
    try appendFetch(ctx, d);
    return finishNull(ctx);
}

fn appGetIteratorIndex(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    const ai = arrayIt(d) orelse return NativeResult.scalar(.null);
    const k = try callOn(ctx, ai, "key", &.{});
    if (k == .undef) return finishNull(ctx);
    return finish(ctx, NativeResult.share(k));
}

fn appGetArrayIterator(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const d = (try dualOf(ctx)) orelse return error.RuntimeError;
    return shareSlot(d, D_ARRAYIT);
}

// ==========================================
// RecursiveIteratorIterator, RecursiveTreeIterator
// ==========================================

const RS_NEXT: i64 = 0;
const RS_TEST: i64 = 1;
const RS_SELF: i64 = 2;
const RS_CHILD: i64 = 3;
const RS_START: i64 = 4;

const RIT_LEAVES_ONLY: i64 = 0;
const RIT_SELF_FIRST: i64 = 1;
const RIT_CHILD_FIRST: i64 = 2;
const RIT_CATCH_GET_CHILD: i64 = CIT_CATCH_GET_CHILD;

const RTIT_BYPASS_CURRENT: i64 = 4;
const RTIT_BYPASS_KEY: i64 = 8;

// slots of the "__rit" state array
const R_ITERS = 0; // array of levels, .undef while php's iterators is NULL
const R_MODE = 1;
const R_FLAGS = 2;
const R_MAX_DEPTH = 3;
const R_IN_ITERATION = 4;
const R_HOOKS = 5;
const R_PREFIX = 6; // six prefix parts
const R_POSTFIX = 12;
const R_LEN = 13;

// a level: an ObjIter over its object, then its state
const L_STATE = ObjIter.width;
const L_LEN = ObjIter.width + 1;

// the hooks a user class overrides; php leaves the rest NULL and skips them
const H_BEGIN_ITERATION: i64 = 1;
const H_END_ITERATION: i64 = 2;
const H_CALL_HAS_CHILDREN: i64 = 4;
const H_CALL_GET_CHILDREN: i64 = 8;
const H_BEGIN_CHILDREN: i64 = 16;
const H_END_CHILDREN: i64 = 32;
const H_NEXT_ELEMENT: i64 = 64;

const hook_names = [_]struct { bit: i64, name: []const u8 }{
    .{ .bit = H_BEGIN_ITERATION, .name = "beginIteration" },
    .{ .bit = H_END_ITERATION, .name = "endIteration" },
    .{ .bit = H_CALL_HAS_CHILDREN, .name = "callHasChildren" },
    .{ .bit = H_CALL_GET_CHILDREN, .name = "callGetChildren" },
    .{ .bit = H_BEGIN_CHILDREN, .name = "beginChildren" },
    .{ .bit = H_END_CHILDREN, .name = "endChildren" },
    .{ .bit = H_NEXT_ELEMENT, .name = "nextElement" },
};

const Rec = struct {
    obj: *PhpObject,
    st: *PhpArray,

    fn levels(self: Rec) ?*PhpArray {
        const v = slot(self.st, R_ITERS);
        return if (v == .array) v.array else null;
    }

    fn level(self: Rec) usize {
        const l = self.levels() orelse return 0;
        return l.entries.items.len - 1;
    }

    fn levelArr(self: Rec, i: usize) *PhpArray {
        return self.levels().?.entries.items[i].value.array;
    }

    fn iter(self: Rec, i: usize) ObjIter {
        return .{ .arr = self.levelArr(i), .base = 0 };
    }

    fn zobject(self: Rec, i: usize) Value {
        return slot(self.levelArr(i), 0);
    }

    fn state(self: Rec, i: usize) i64 {
        return slotInt(self.levelArr(i), L_STATE);
    }

    fn setState(self: Rec, ctx: *NativeContext, i: usize, s: i64) RuntimeError!void {
        try setSlot(ctx, self.levelArr(i), L_STATE, .{ .int = s });
    }

    fn int(self: Rec, i: usize) i64 {
        return slotInt(self.st, i);
    }

    fn hook(self: Rec, bit: i64) bool {
        return self.int(R_HOOKS) & bit != 0;
    }

    fn put(self: Rec, ctx: *NativeContext, i: usize, v: Value) RuntimeError!void {
        try setSlot(ctx, self.st, i, v);
    }

    // drops the top level
    fn pop(self: Rec, ctx: *NativeContext) void {
        const l = self.levels() orelse return;
        if (l.entries.items.len <= 1) return;
        const e = l.entries.pop().?;
        l.next_int_key = @intCast(l.entries.items.len);
        ctx.vm.releaseValue(e.value);
    }

    fn push(self: Rec, ctx: *NativeContext, target: Value) RuntimeError!void {
        const l = self.levels().?;
        const lvl = try newState(ctx, L_LEN);
        l.next_int_key = @intCast(l.entries.items.len);
        try l.append(ctx.allocator, .{ .array = lvl });
        try (ObjIter{ .arr = lvl, .base = 0 }).init(ctx, target);
        try setSlot(ctx, lvl, L_STATE, .{ .int = RS_START });
    }
};

fn recRaw(obj: *PhpObject) ?Rec {
    const st = stateOf(obj, "__rit") orelse return null;
    return .{ .obj = obj, .st = st };
}

// the object, with php's iterators set
fn recOf(ctx: *NativeContext) RuntimeError!?Rec {
    if (thisObj(ctx)) |obj| if (recRaw(obj)) |r| if (r.levels() != null) return r;
    try raise(ctx, "Error", "The object is in an invalid state as the parent constructor was not called", .{});
    return null;
}

fn callHook(ctx: *NativeContext, r: Rec, name: []const u8) RuntimeError!Value {
    return callOn(ctx, r.obj, name, &.{});
}

fn recValid(ctx: *NativeContext, r: Rec) RuntimeError!bool {
    if (r.levels() == null) return false;
    var lvl: usize = r.level() + 1;
    while (lvl > 0) {
        lvl -= 1;
        if (lvl > r.level()) continue;
        if (try r.iter(lvl).valid(ctx)) return true;
    }
    if (r.hook(H_END_ITERATION) and slot(r.st, R_IN_ITERATION) == .bool and slot(r.st, R_IN_ITERATION).bool) {
        _ = try callHook(ctx, r, "endIteration");
    }
    try r.put(ctx, R_IN_ITERATION, .{ .bool = false });
    return false;
}

// RIT_CATCH_GET_CHILD swallows an exception; false when php returns
fn caught(ctx: *NativeContext, r: Rec) bool {
    if (!pending(ctx)) return true;
    if (r.int(R_FLAGS) & RIT_CATCH_GET_CHILD == 0) return false;
    ctx.vm.discardPending();
    return true;
}

// spl_recursive_it_move_forward_ex
fn recMoveForward(ctx: *NativeContext, r: Rec) RuntimeError!void {
    if (r.levels() == null) {
        try raise(ctx, "Error", "The object is in an invalid state as the parent constructor was not called", .{});
        return;
    }
    const mode = r.int(R_MODE);
    outer: while (!pending(ctx)) {
        if (r.levels() == null) return;
        var lvl = r.level();
        var it_arr = r.levelArr(lvl);
        state: switch (r.state(lvl)) {
            RS_NEXT => {
                try r.iter(lvl).next(ctx);
                if (pending(ctx)) {
                    if (r.int(R_FLAGS) & RIT_CATCH_GET_CHILD == 0) return;
                    ctx.vm.discardPending();
                }
                if (r.levels() == null) return;
                lvl = r.level();
                it_arr = r.levelArr(lvl);
                continue :state RS_START;
            },
            RS_START => {
                // the level's object lives through valid(), which may reenter
                const sub = r.zobject(lvl);
                VM.retainValue(sub);
                VM.retainValue(.{ .array = it_arr });
                const ok = try r.iter(lvl).valid(ctx);
                const reentered = r.levels() == null or r.level() != lvl or r.levelArr(lvl) != it_arr;
                ctx.vm.releaseValue(.{ .array = it_arr });
                ctx.vm.releaseValue(sub);
                if (reentered) return;
                if (!ok) break :state;
                try r.setState(ctx, lvl, RS_TEST);
                continue :state RS_TEST;
            },
            RS_TEST => {
                const ret = if (r.hook(H_CALL_HAS_CHILDREN))
                    try callHook(ctx, r, "callHasChildren")
                else blk: {
                    const z = r.zobject(lvl);
                    break :blk if (z == .object) try callOn(ctx, z.object, "hasChildren", &.{}) else Value.undef;
                };
                if (pending(ctx)) {
                    if (r.int(R_FLAGS) & RIT_CATCH_GET_CHILD == 0) {
                        try r.setState(ctx, lvl, RS_NEXT);
                        return;
                    }
                    ctx.vm.discardPending();
                }
                if (ret != .undef and ret.isTruthy()) {
                    const max_depth = r.int(R_MAX_DEPTH);
                    if (max_depth == -1 or max_depth > @as(i64, @intCast(lvl))) {
                        if (mode == RIT_SELF_FIRST) {
                            try r.setState(ctx, lvl, RS_SELF);
                            continue :state RS_SELF;
                        }
                        try r.setState(ctx, lvl, RS_CHILD);
                        continue :state RS_CHILD;
                    } else if (mode == RIT_LEAVES_ONLY) {
                        // not a leaf, and not to be recursed into
                        try r.setState(ctx, lvl, RS_NEXT);
                        continue :state RS_NEXT;
                    }
                }
                if (r.hook(H_NEXT_ELEMENT)) _ = try callHook(ctx, r, "nextElement");
                try r.setState(ctx, lvl, RS_NEXT);
                if (pending(ctx) and r.int(R_FLAGS) & RIT_CATCH_GET_CHILD != 0) ctx.vm.discardPending();
                return;
            },
            RS_SELF => {
                if (r.hook(H_NEXT_ELEMENT) and (mode == RIT_SELF_FIRST or mode == RIT_CHILD_FIRST)) {
                    _ = try callHook(ctx, r, "nextElement");
                }
                try r.setState(ctx, lvl, if (mode == RIT_SELF_FIRST) RS_CHILD else RS_NEXT);
                return;
            },
            RS_CHILD => {
                const child = if (r.hook(H_CALL_GET_CHILDREN))
                    try callHook(ctx, r, "callGetChildren")
                else blk: {
                    const z = r.zobject(lvl);
                    break :blk if (z == .object) try callOn(ctx, z.object, "getChildren", &.{}) else Value.undef;
                };
                if (pending(ctx)) {
                    if (r.int(R_FLAGS) & RIT_CATCH_GET_CHILD == 0) return;
                    ctx.vm.discardPending();
                    try r.setState(ctx, lvl, RS_NEXT);
                    continue :state RS_NEXT;
                }
                if (child != .object or !ctx.vm.isInstanceOf(child.object.class_name, "RecursiveIterator")) {
                    try raise(ctx, "UnexpectedValueException", "Objects returned by RecursiveIterator::getChildren() must implement RecursiveIterator", .{});
                    return;
                }
                try r.setState(ctx, lvl, if (mode == RIT_CHILD_FIRST) RS_SELF else RS_NEXT);
                try r.push(ctx, child);
                const top = r.level();
                try r.iter(top).rewind(ctx);
                if (r.hook(H_BEGIN_CHILDREN)) {
                    _ = try callHook(ctx, r, "beginChildren");
                    if (!caught(ctx, r)) return;
                }
                continue :outer;
            },
            else => break :state,
        }
        // no more elements at this level
        if (lvl > 0) {
            if (r.hook(H_END_CHILDREN)) {
                _ = try callHook(ctx, r, "endChildren");
                if (!caught(ctx, r)) return;
            }
            if (r.levels() != null and r.level() > 0 and r.level() == lvl and r.levelArr(lvl) == it_arr) {
                r.pop(ctx);
            }
        } else {
            return;
        }
    }
}

// spl_recursive_it_rewind_ex
fn recRewind(ctx: *NativeContext, r: Rec) RuntimeError!void {
    if (r.levels() == null) {
        try raise(ctx, "Error", "The object is in an invalid state as the parent constructor was not called", .{});
        return;
    }
    while (r.level() > 0) {
        r.pop(ctx);
        if (!pending(ctx) and r.hook(H_END_CHILDREN)) _ = try callHook(ctx, r, "endChildren");
    }
    try r.setState(ctx, 0, RS_START);
    try r.iter(0).rewind(ctx);
    const in_iteration = slot(r.st, R_IN_ITERATION) == .bool and slot(r.st, R_IN_ITERATION).bool;
    if (!pending(ctx) and r.hook(H_BEGIN_ITERATION) and !in_iteration) _ = try callHook(ctx, r, "beginIteration");
    try r.put(ctx, R_IN_ITERATION, .{ .bool = true });
    try recMoveForward(ctx, r);
}

fn recConstruct(ctx: *NativeContext, args: []const Value, tree: bool) RuntimeError!void {
    const obj = thisObj(ctx) orelse return;
    const label = if (tree) "RecursiveTreeIterator::__construct" else "RecursiveIteratorIterator::__construct";
    var mode: i64 = undefined;
    var flags: i64 = undefined;
    var iterator: Value = undefined;
    if (tree) {
        if (!try argCount(ctx, label, args.len, 1, 4)) return;
        if (args[0] != .object) return typeError(ctx, label, 1, "iterator", "object", args[0]);
        flags = (try argLong(ctx, label, args, 1, "flags", RTIT_BYPASS_KEY)) orelse return;
        const caching_flags = (try argLong(ctx, label, args, 2, "cachingIteratorFlags", CIT_CATCH_GET_CHILD)) orelse return;
        mode = (try argLong(ctx, label, args, 3, "mode", RIT_SELF_FIRST)) orelse return;
        iterator = args[0];
        if (isAggregate(ctx.vm, iterator.object)) {
            iterator = try fromAggregate(ctx, iterator.object, iterator.object.class_name);
            if (iterator == .undef) return;
        }
        VM.retainValue(iterator);
        defer ctx.vm.releaseValue(iterator);
        const caching = try construct(ctx, "RecursiveCachingIterator", &.{ iterator, .{ .int = caching_flags } });
        if (caching == .undef) return;
        iterator = caching;
    } else {
        if (!try argCount(ctx, label, args.len, 1, 3)) return;
        if (args[0] != .object) return typeError(ctx, label, 1, "iterator", "object", args[0]);
        mode = (try argLong(ctx, label, args, 1, "mode", RIT_LEAVES_ONLY)) orelse return;
        flags = (try argLong(ctx, label, args, 2, "flags", 0)) orelse return;
        iterator = args[0];
        if (isAggregate(ctx.vm, iterator.object)) {
            iterator = try fromAggregate(ctx, iterator.object, iterator.object.class_name);
            if (iterator == .undef) return;
        }
    }
    VM.retainValue(iterator);
    defer ctx.vm.releaseValue(iterator);
    if (!isInstance(ctx.vm, iterator, "RecursiveIterator")) {
        try raise(ctx, "InvalidArgumentException", "An instance of RecursiveIterator or IteratorAggregate creating it is required", .{});
        return;
    }

    const st = try newState(ctx, R_LEN);
    try obj.set(ctx.allocator, "__rit", .{ .array = st });
    const r: Rec = .{ .obj = obj, .st = st };
    try r.put(ctx, R_ITERS, .{ .array = try ctx.createArray() });
    try r.put(ctx, R_MODE, .{ .int = mode });
    try r.put(ctx, R_FLAGS, .{ .int = flags });
    try r.put(ctx, R_MAX_DEPTH, .{ .int = -1 });
    try r.put(ctx, R_IN_ITERATION, .{ .bool = false });
    var hooks: i64 = 0;
    for (hook_names) |h| if (userMethod(ctx.vm, obj.class_name, h.name)) {
        hooks |= h.bit;
    };
    try r.put(ctx, R_HOOKS, .{ .int = hooks });
    if (tree) {
        const parts = [_][]const u8{ "", "| ", "  ", "|-", "\\-", "" };
        for (parts, 0..) |p, i| try r.put(ctx, R_PREFIX + i, .{ .string = Value.String.borrowed(p) });
        try r.put(ctx, R_POSTFIX, .{ .string = Value.String.borrowed("") });
    }
    try r.push(ctx, iterator);
}

fn riiConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    try recConstruct(ctx, args, false);
    return finishNull(ctx);
}

fn riiRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = thisObj(ctx) orelse return NativeResult.scalar(.null);
    const r = recRaw(obj) orelse return throwNow(ctx, "Error", "The object is in an invalid state as the parent constructor was not called", .{});
    try recRewind(ctx, r);
    return finishNull(ctx);
}

fn riiValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = thisObj(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const r = recRaw(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const ok = try recValid(ctx, r);
    return finish(ctx, NativeResult.scalar(.{ .bool = ok }));
}

fn riiKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const r = (try recOf(ctx)) orelse return error.RuntimeError;
    const k = try r.iter(r.level()).key(ctx);
    if (k == .undef) return finishNull(ctx);
    return finish(ctx, NativeResult.share(k));
}

fn riiCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const r = (try recOf(ctx)) orelse return error.RuntimeError;
    const v = try r.iter(r.level()).current(ctx);
    if (v == .undef) return finishNull(ctx);
    return finish(ctx, NativeResult.share(v));
}

fn riiNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = thisObj(ctx) orelse return NativeResult.scalar(.null);
    const r = recRaw(obj) orelse return throwNow(ctx, "Error", "The object is in an invalid state as the parent constructor was not called", .{});
    try recMoveForward(ctx, r);
    return finishNull(ctx);
}

fn riiGetDepth(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = thisObj(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const r = recRaw(obj) orelse return NativeResult.scalar(.{ .int = 0 });
    if (r.levels() == null) return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = @intCast(r.level()) });
}

fn riiGetSubIterator(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const label = "RecursiveIteratorIterator::getSubIterator";
    if (!try argCount(ctx, label, args.len, 0, 1)) return error.RuntimeError;
    const obj = thisObj(ctx) orelse return NativeResult.scalar(.null);
    const r_raw = recRaw(obj);
    const current: i64 = if (r_raw) |r| (if (r.levels() != null) @as(i64, @intCast(r.level())) else 0) else 0;
    var level = current;
    if (args.len > 0 and args[0] != .null) {
        level = (try argLong(ctx, label, args, 0, "level", 0)) orelse return error.RuntimeError;
        if (level < 0 or level > current) return NativeResult.scalar(.null);
    }
    const r = (try recOf(ctx)) orelse return error.RuntimeError;
    return NativeResult.share(r.zobject(@intCast(level)));
}

fn riiGetInnerIterator(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const r = (try recOf(ctx)) orelse return error.RuntimeError;
    return NativeResult.share(r.zobject(r.level()));
}

fn riiCallHasChildren(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = thisObj(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const r = recRaw(obj) orelse return NativeResult.scalar(.{ .bool = false });
    if (r.levels() == null) return NativeResult.scalar(.{ .bool = false });
    const z = r.zobject(r.level());
    if (z != .object) return NativeResult.scalar(.{ .bool = false });
    const ret = try callOn(ctx, z.object, "hasChildren", &.{});
    if (ret == .undef) return finish(ctx, NativeResult.scalar(.{ .bool = false }));
    return finish(ctx, NativeResult.share(ret));
}

fn riiCallGetChildren(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const r = (try recOf(ctx)) orelse return error.RuntimeError;
    const z = r.zobject(r.level());
    if (z != .object) return NativeResult.scalar(.null);
    const ret = try callOn(ctx, z.object, "getChildren", &.{});
    if (ret == .undef) return finishNull(ctx);
    return finish(ctx, NativeResult.share(ret));
}

fn riiSetMaxDepth(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const label = "RecursiveIteratorIterator::setMaxDepth";
    if (!try argCount(ctx, label, args.len, 0, 1)) return error.RuntimeError;
    var max = (try argLong(ctx, label, args, 0, "maxDepth", -1)) orelse return error.RuntimeError;
    if (max < -1) {
        try valueError(ctx, label, 1, "maxDepth", "must be greater than or equal to -1");
        return error.RuntimeError;
    }
    if (max > std.math.maxInt(i32)) max = std.math.maxInt(i32);
    const obj = thisObj(ctx) orelse return NativeResult.scalar(.null);
    const r = recRaw(obj) orelse {
        const st = try newState(ctx, R_LEN);
        try obj.set(ctx.allocator, "__rit", .{ .array = st });
        try setSlot(ctx, st, R_MAX_DEPTH, .{ .int = max });
        return NativeResult.scalar(.null);
    };
    try r.put(ctx, R_MAX_DEPTH, .{ .int = max });
    return NativeResult.scalar(.null);
}

fn riiGetMaxDepth(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = thisObj(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const r = recRaw(obj) orelse return NativeResult.scalar(.{ .int = 0 });
    const max = r.int(R_MAX_DEPTH);
    if (max == -1) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = max });
}

fn riiNoop(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.null);
}

fn rtiConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    try recConstruct(ctx, args, true);
    return finishNull(ctx);
}

fn treeCheck(ctx: *NativeContext) RuntimeError!?Rec {
    const obj = thisObj(ctx) orelse return null;
    if (recRaw(obj)) |r| if (r.levels() != null) return r;
    try raise(ctx, "Error", "The object is in an invalid state as the parent constructor was not called", .{});
    return null;
}

fn prefixPart(r: Rec, i: usize) []const u8 {
    const v = slot(r.st, R_PREFIX + i);
    return if (v == .string) v.string.bytes() else "";
}

// spl_recursive_tree_iterator_get_prefix
fn treePrefix(ctx: *NativeContext, r: Rec, out: *std.ArrayListUnmanaged(u8)) RuntimeError!void {
    try out.appendSlice(ctx.allocator, prefixPart(r, 0));
    const top = r.level();
    for (0..top + 1) |lvl| {
        if (lvl > r.level()) break;
        const z = r.zobject(lvl);
        if (z != .object) continue;
        const has_next = try callOn(ctx, z.object, "hasNext", &.{});
        if (has_next == .undef) continue;
        const yes = has_next == .bool and has_next.bool;
        const part: usize = if (lvl < top) (if (yes) 1 else 2) else (if (yes) 3 else 4);
        try out.appendSlice(ctx.allocator, prefixPart(r, part));
    }
    try out.appendSlice(ctx.allocator, prefixPart(r, 5));
}

// spl_recursive_tree_iterator_get_entry: an owned string, .undef for none
fn treeEntry(ctx: *NativeContext, r: Rec) RuntimeError!Value {
    const data = try r.iter(r.level()).current(ctx);
    if (data == .undef) return .undef;
    if (data == .array) return .{ .string = Value.String.borrowed("Array") };
    return toPhpString(ctx, data);
}

fn rtiSetPrefixPart(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const label = "RecursiveTreeIterator::setPrefixPart";
    if (!try argCount(ctx, label, args.len, 2, 2)) return error.RuntimeError;
    const part = (try argLong(ctx, label, args, 0, "part", 0)) orelse return error.RuntimeError;
    const value = (try argString(ctx, label, args, 1, "value")) orelse return error.RuntimeError;
    defer value.release();
    if (part < 0 or part > 5) {
        try valueError(ctx, label, 1, "part", "must be a RecursiveTreeIterator::PREFIX_* constant");
        return error.RuntimeError;
    }
    const obj = thisObj(ctx) orelse return NativeResult.scalar(.null);
    const r = recRaw(obj) orelse return NativeResult.scalar(.null);
    try r.put(ctx, R_PREFIX + @as(usize, @intCast(part)), .{ .string = value });
    return NativeResult.scalar(.null);
}

fn rtiGetPrefix(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const r = (try treeCheck(ctx)) orelse return error.RuntimeError;
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(ctx.allocator);
    try treePrefix(ctx, r, &out);
    if (pending(ctx)) return error.RuntimeError;
    return NativeResult.copyString(ctx.allocator, out.items);
}

fn rtiSetPostfix(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const label = "RecursiveTreeIterator::setPostfix";
    if (!try argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const value = (try argString(ctx, label, args, 0, "postfix")) orelse return error.RuntimeError;
    defer value.release();
    const obj = thisObj(ctx) orelse return NativeResult.scalar(.null);
    const r = recRaw(obj) orelse return NativeResult.scalar(.null);
    try r.put(ctx, R_POSTFIX, .{ .string = value });
    return NativeResult.scalar(.null);
}

fn rtiGetEntry(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const r = (try treeCheck(ctx)) orelse return error.RuntimeError;
    const entry = try treeEntry(ctx, r);
    if (entry == .undef) return finishNull(ctx);
    return finish(ctx, ownedResult(entry));
}

fn rtiGetPostfix(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const r = (try treeCheck(ctx)) orelse return error.RuntimeError;
    const v = slot(r.st, R_POSTFIX);
    if (v == .string) return NativeResult.shareString(v.string);
    return NativeResult.literal("");
}

fn rtiCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const r = (try treeCheck(ctx)) orelse return error.RuntimeError;
    if (r.int(R_FLAGS) & RTIT_BYPASS_CURRENT != 0) {
        const data = try r.iter(r.level()).current(ctx);
        if (data == .undef) return finishNull(ctx);
        return finish(ctx, NativeResult.share(data));
    }
    const entry = try treeEntry(ctx, r);
    if (entry == .undef) return finishNull(ctx);
    defer releaseString(entry);
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(ctx.allocator);
    try treePrefix(ctx, r, &out);
    try out.appendSlice(ctx.allocator, entry.string.bytes());
    const post = slot(r.st, R_POSTFIX);
    if (post == .string) try out.appendSlice(ctx.allocator, post.string.bytes());
    if (pending(ctx)) return error.RuntimeError;
    return NativeResult.copyString(ctx.allocator, out.items);
}

fn rtiKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const r = (try recOf(ctx)) orelse return error.RuntimeError;
    var key = try r.iter(r.level()).key(ctx);
    if (key == .undef) key = .null;
    if (r.int(R_FLAGS) & RTIT_BYPASS_KEY != 0) return finish(ctx, NativeResult.share(key));
    hold(key);
    defer unhold(ctx, key);
    const key_str = try toPhpString(ctx, key);
    if (key_str == .undef) return error.RuntimeError;
    defer releaseString(key_str);
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(ctx.allocator);
    try treePrefix(ctx, r, &out);
    try out.appendSlice(ctx.allocator, key_str.string.bytes());
    const post = slot(r.st, R_POSTFIX);
    if (post == .string) try out.appendSlice(ctx.allocator, post.string.bytes());
    if (pending(ctx)) return error.RuntimeError;
    return NativeResult.copyString(ctx.allocator, out.items);
}

// php's get_method handlers: a method a dual iterator lacks runs on its
// inner object, one a RecursiveIteratorIterator lacks on the current
// sub-iterator
pub fn forwardTarget(obj: *PhpObject) ?*PhpObject {
    if (dualRaw(obj)) |d| {
        const inner = d.get(D_INNER);
        return if (inner == .object) inner.object else null;
    }
    if (recRaw(obj)) |r| {
        if (r.levels() == null) return null;
        const z = r.zobject(r.level());
        return if (z == .object) z.object else null;
    }
    return null;
}

// where a call of a method obj lacks lands: down the chain of inner
// iterators to the first object with the method (or __call), else the last
// one, which php names in its "Call to undefined method" error. null when
// obj forwards nothing
pub fn forwardFor(vm: *VM, obj: *PhpObject, name: []const u8) ?*PhpObject {
    var t = forwardTarget(obj) orelse return null;
    var steps: usize = 0;
    while (steps < 64) : (steps += 1) {
        if (vm.hasMethod(t.class_name, name) or vm.hasMethod(t.class_name, "__call")) return t;
        t = forwardTarget(t) orelse return t;
    }
    return t;
}

// a RecursiveIteratorIterator php iterates with its own iterator rather
// than its methods: one whose class overrides none of them (a
// RecursiveTreeIterator does)
fn ownIterator(vm: *VM, obj: *PhpObject) bool {
    if (!vm.isInstanceOf(obj.class_name, "RecursiveIteratorIterator")) return false;
    for (iterator_methods) |m| {
        const full = vm.resolveMethod(obj.class_name, m) catch return false;
        if (!std.mem.startsWith(u8, full, "RecursiveIteratorIterator::")) return false;
    }
    return true;
}

// php's iterator refuses an object whose constructor never ran
pub fn foreachRefusal(vm: *VM, obj: *PhpObject) ?[]const u8 {
    if (!ownIterator(vm, obj)) return null;
    if (recRaw(obj)) |r| if (r.levels() != null) return null;
    return "Object is not initialized";
}

// foreach steps a RecursiveIteratorIterator through its own iterator: no
// method call, so no frame of one in a trace
pub fn foreachDirect(vm: *VM, obj: *PhpObject) bool {
    if (!ownIterator(vm, obj)) return false;
    const r = recRaw(obj) orelse return false;
    return r.levels() != null;
}

pub const ForeachStep = enum { rewind, valid, current, key, next };

pub fn foreachStep(vm: *VM, obj: *PhpObject, comptime step: ForeachStep) RuntimeError!Value {
    var ctx = vm.makeContext(null);
    const r = recRaw(obj) orelse return .null;
    var result: Value = .null;
    switch (step) {
        .rewind => try recRewind(&ctx, r),
        .valid => result = .{ .bool = try recValid(&ctx, r) },
        .current => if (r.levels() != null) {
            result = try r.iter(r.level()).current(&ctx);
        },
        .key => if (r.levels() != null) {
            result = try r.iter(r.level()).key(&ctx);
        },
        .next => try recMoveForward(&ctx, r),
    }
    if (pending(&ctx)) return error.RuntimeError;
    return if (result == .undef) .null else result;
}

// ==========================================
// iterator_to_array, iterator_count, iterator_apply
// ==========================================

const ApplyKind = enum { to_array, to_values, count, call };

// spl_iterator_apply over a Traversable object or generator
fn iteratorApply(ctx: *NativeContext, subject: Value, kind: ApplyKind, out: ?*PhpArray, callback: Value, cb_args: []const Value) RuntimeError!i64 {
    const target = try iterTarget(ctx, subject);
    if (target == .undef) return 0;
    if (target == .object) if (foreachRefusal(ctx.vm, target.object)) |msg| {
        try raise(ctx, "Error", "{s}", .{msg});
        return 0;
    };
    const st = try newState(ctx, ObjIter.width);
    VM.retainValue(.{ .array = st });
    defer ctx.vm.releaseValue(.{ .array = st });
    const it: ObjIter = .{ .arr = st, .base = 0 };
    try it.init(ctx, target);
    // php's iterator lets go of the object as the walk ends
    defer it.clear(ctx) catch {};
    var count: i64 = 0;
    try it.rewind(ctx);
    if (pending(ctx)) return count;
    while (try it.valid(ctx)) {
        if (pending(ctx)) return count;
        switch (kind) {
            .to_array, .to_values => {
                const data = try it.current(ctx);
                if (pending(ctx) or data == .undef) return count;
                if (kind == .to_array) {
                    hold(data);
                    defer unhold(ctx, data);
                    const key = try it.key(ctx);
                    if (pending(ctx)) return count;
                    try setZvalKey(ctx, out.?, key, data);
                    if (pending(ctx)) return count;
                } else {
                    try out.?.append(ctx.allocator, data);
                }
            },
            .count => {
                if (count == std.math.maxInt(i64)) return count;
                count += 1;
            },
            .call => {
                count += 1;
                const r = try callValue(ctx, callback, cb_args);
                if (pending(ctx) or !r.isTruthy()) return count;
            },
        }
        try it.next(ctx);
        if (pending(ctx)) return count;
    }
    return count;
}

fn iterableArg(ctx: *NativeContext, label: []const u8, args: []const Value) RuntimeError!bool {
    const v = args[0];
    if (v == .array or v == .generator or (v == .object and ctx.vm.isInstanceOf(v.object.class_name, "Traversable"))) return true;
    try typeError(ctx, label, 1, "iterator", "Traversable|array", v);
    return false;
}

pub fn iteratorToArray(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const label = "iterator_to_array";
    if (!try argCount(ctx, label, args.len, 1, 2)) return error.RuntimeError;
    if (!try iterableArg(ctx, label, args)) return error.RuntimeError;
    const use_keys = if (args.len > 1) args[1].isTruthy() else true;
    if (args[0] == .array) {
        if (use_keys) return NativeResult.borrowed(args[0]);
        const list = try ctx.createArray();
        for (args[0].array.entries.items) |e| try list.append(ctx.allocator, if (e.ref) |cell| cell.* else e.value);
        return NativeResult.borrowed(.{ .array = list });
    }
    const out = try ctx.createArray();
    _ = try iteratorApply(ctx, args[0], if (use_keys) .to_array else .to_values, out, .null, &.{});
    if (pending(ctx)) return error.RuntimeError;
    return NativeResult.borrowed(.{ .array = out });
}

pub fn iteratorCount(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const label = "iterator_count";
    if (!try argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    if (!try iterableArg(ctx, label, args)) return error.RuntimeError;
    if (args[0] == .array) return NativeResult.scalar(.{ .int = args[0].array.length() });
    const n = try iteratorApply(ctx, args[0], .count, null, .null, &.{});
    return finish(ctx, NativeResult.scalar(.{ .int = n }));
}

pub fn iteratorApplyFn(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const label = "iterator_apply";
    if (!try argCount(ctx, label, args.len, 2, 3)) return error.RuntimeError;
    const v = args[0];
    if (!(v == .generator or (v == .object and ctx.vm.isInstanceOf(v.object.class_name, "Traversable")))) {
        try typeError(ctx, label, 1, "iterator", "Traversable", v);
        return error.RuntimeError;
    }
    var buf: [16]Value = undefined;
    var cb_args: []Value = buf[0..0];
    if (args.len > 2 and args[2] != .null) {
        if (args[2] != .array) {
            try typeError(ctx, label, 3, "args", "?array", args[2]);
            return error.RuntimeError;
        }
        cb_args = try ctx.argsFromArray(args[2].array, &buf);
    }
    defer ctx.freeArgs(cb_args, &buf);
    const n = try iteratorApply(ctx, v, .call, null, args[1], cb_args);
    return finish(ctx, NativeResult.scalar(.{ .int = n }));
}

// ==========================================
// registration
// ==========================================

const M = struct {
    name: []const u8,
    arity: u8 = 0,
    f: ?NativeFn,
    abstract: bool = false,
};

fn defineClass(vm: *VM, a: Allocator, comptime name: []const u8, parent: ?[]const u8, interfaces: []const []const u8, comptime methods: []const M) !*ClassDef {
    var def = ClassDef{ .name = name, .uncloneable = true };
    def.parent = parent;
    for (interfaces) |i| try def.interfaces.append(a, i);
    inline for (methods) |m| {
        try def.addMethod(a, .{ .name = m.name, .arity = m.arity, .is_abstract = m.abstract });
        if (m.f) |f| try vm.native_fns.put(a, name ++ "::" ++ m.name, f);
    }
    try vm.classes.put(a, name, def);
    return vm.classes.getPtr(name).?;
}

pub fn register(vm: *VM, a: Allocator) !void {
    _ = try defineClass(vm, a, "EmptyIterator", null, &.{"Iterator"}, &.{
        .{ .name = "current", .f = emptyCurrent },
        .{ .name = "next", .f = emptyNoop },
        .{ .name = "key", .f = emptyKey },
        .{ .name = "valid", .f = emptyValid },
        .{ .name = "rewind", .f = emptyNoop },
    });
    vm.classes.getPtr("EmptyIterator").?.uncloneable = false;

    const rii = try defineClass(vm, a, "RecursiveIteratorIterator", null, &.{"OuterIterator"}, &.{
        .{ .name = "__construct", .arity = 3, .f = riiConstruct },
        .{ .name = "rewind", .f = riiRewind },
        .{ .name = "valid", .f = riiValid },
        .{ .name = "key", .f = riiKey },
        .{ .name = "current", .f = riiCurrent },
        .{ .name = "next", .f = riiNext },
        .{ .name = "getDepth", .f = riiGetDepth },
        .{ .name = "getSubIterator", .arity = 1, .f = riiGetSubIterator },
        .{ .name = "getInnerIterator", .f = riiGetInnerIterator },
        .{ .name = "beginIteration", .f = riiNoop },
        .{ .name = "endIteration", .f = riiNoop },
        .{ .name = "callHasChildren", .f = riiCallHasChildren },
        .{ .name = "callGetChildren", .f = riiCallGetChildren },
        .{ .name = "beginChildren", .f = riiNoop },
        .{ .name = "endChildren", .f = riiNoop },
        .{ .name = "nextElement", .f = riiNoop },
        .{ .name = "setMaxDepth", .arity = 1, .f = riiSetMaxDepth },
        .{ .name = "getMaxDepth", .f = riiGetMaxDepth },
    });
    try rii.constants.put(a, "LEAVES_ONLY", .{ .int = RIT_LEAVES_ONLY });
    try rii.constants.put(a, "SELF_FIRST", .{ .int = RIT_SELF_FIRST });
    try rii.constants.put(a, "CHILD_FIRST", .{ .int = RIT_CHILD_FIRST });
    try rii.constants.put(a, "CATCH_GET_CHILD", .{ .int = RIT_CATCH_GET_CHILD });

    _ = try defineClass(vm, a, "IteratorIterator", null, &.{"OuterIterator"}, &.{
        .{ .name = "__construct", .arity = 2, .f = iiConstruct },
        .{ .name = "getInnerIterator", .f = iiGetInnerIterator },
        .{ .name = "rewind", .f = iiRewind },
        .{ .name = "valid", .f = iiValid },
        .{ .name = "key", .f = iiKey },
        .{ .name = "current", .f = iiCurrent },
        .{ .name = "next", .f = iiNext },
    });

    const filter = try defineClass(vm, a, "FilterIterator", "IteratorIterator", &.{}, &.{
        .{ .name = "accept", .f = null, .abstract = true },
        .{ .name = "__construct", .arity = 1, .f = filterConstruct },
        .{ .name = "rewind", .f = filterRewind },
        .{ .name = "next", .f = filterNext },
    });
    filter.is_abstract = true;

    _ = try defineClass(vm, a, "CallbackFilterIterator", "FilterIterator", &.{}, &.{
        .{ .name = "__construct", .arity = 2, .f = cbfConstruct },
        .{ .name = "accept", .f = cbfAccept },
    });

    _ = try defineClass(vm, a, "RecursiveCallbackFilterIterator", "CallbackFilterIterator", &.{"RecursiveIterator"}, &.{
        .{ .name = "__construct", .arity = 2, .f = rcbfConstruct },
        .{ .name = "hasChildren", .f = rfiHasChildren },
        .{ .name = "getChildren", .f = rcbfGetChildren },
    });

    const rfi = try defineClass(vm, a, "RecursiveFilterIterator", "FilterIterator", &.{"RecursiveIterator"}, &.{
        .{ .name = "__construct", .arity = 1, .f = rfiConstruct },
        .{ .name = "hasChildren", .f = rfiHasChildren },
        .{ .name = "getChildren", .f = rfiGetChildren },
    });
    rfi.is_abstract = true;

    _ = try defineClass(vm, a, "ParentIterator", "RecursiveFilterIterator", &.{}, &.{
        .{ .name = "__construct", .arity = 1, .f = parentConstruct },
        .{ .name = "accept", .f = rfiHasChildren },
    });

    _ = try defineClass(vm, a, "LimitIterator", "IteratorIterator", &.{}, &.{
        .{ .name = "__construct", .arity = 3, .f = limitConstruct },
        .{ .name = "rewind", .f = limitRewind },
        .{ .name = "valid", .f = limitValid },
        .{ .name = "next", .f = limitNext },
        .{ .name = "seek", .arity = 1, .f = limitSeek },
        .{ .name = "getPosition", .f = limitGetPosition },
    });

    const ci = try defineClass(vm, a, "CachingIterator", "IteratorIterator", &.{ "ArrayAccess", "Countable", "Stringable" }, &.{
        .{ .name = "__construct", .arity = 2, .f = ciConstruct },
        .{ .name = "rewind", .f = ciRewind },
        .{ .name = "valid", .f = ciValid },
        .{ .name = "next", .f = ciNext },
        .{ .name = "hasNext", .f = ciHasNext },
        .{ .name = "__toString", .f = ciToString },
        .{ .name = "getFlags", .f = ciGetFlags },
        .{ .name = "setFlags", .arity = 1, .f = ciSetFlags },
        .{ .name = "offsetGet", .arity = 1, .f = ciOffsetGet },
        .{ .name = "offsetSet", .arity = 2, .f = ciOffsetSet },
        .{ .name = "offsetUnset", .arity = 1, .f = ciOffsetUnset },
        .{ .name = "offsetExists", .arity = 1, .f = ciOffsetExists },
        .{ .name = "getCache", .f = ciGetCache },
        .{ .name = "count", .f = ciCount },
    });
    try ci.constants.put(a, "CALL_TOSTRING", .{ .int = CIT_CALL_TOSTRING });
    try ci.constants.put(a, "CATCH_GET_CHILD", .{ .int = CIT_CATCH_GET_CHILD });
    try ci.constants.put(a, "TOSTRING_USE_KEY", .{ .int = CIT_TOSTRING_USE_KEY });
    try ci.constants.put(a, "TOSTRING_USE_CURRENT", .{ .int = CIT_TOSTRING_USE_CURRENT });
    try ci.constants.put(a, "TOSTRING_USE_INNER", .{ .int = CIT_TOSTRING_USE_INNER });
    try ci.constants.put(a, "FULL_CACHE", .{ .int = CIT_FULL_CACHE });

    _ = try defineClass(vm, a, "RecursiveCachingIterator", "CachingIterator", &.{"RecursiveIterator"}, &.{
        .{ .name = "__construct", .arity = 2, .f = rciConstruct },
        .{ .name = "hasChildren", .f = rciHasChildren },
        .{ .name = "getChildren", .f = rciGetChildren },
    });

    _ = try defineClass(vm, a, "NoRewindIterator", "IteratorIterator", &.{}, &.{
        .{ .name = "__construct", .arity = 1, .f = nriConstruct },
        .{ .name = "rewind", .f = nriRewind },
        .{ .name = "valid", .f = nriValid },
        .{ .name = "key", .f = nriKey },
        .{ .name = "current", .f = nriCurrent },
        .{ .name = "next", .f = nriNext },
    });

    _ = try defineClass(vm, a, "AppendIterator", "IteratorIterator", &.{}, &.{
        .{ .name = "__construct", .f = appConstruct },
        .{ .name = "append", .arity = 1, .f = appAppend },
        .{ .name = "rewind", .f = appRewind },
        .{ .name = "valid", .f = appValid },
        .{ .name = "current", .f = appCurrent },
        .{ .name = "next", .f = appNext },
        .{ .name = "getIteratorIndex", .f = appGetIteratorIndex },
        .{ .name = "getArrayIterator", .f = appGetArrayIterator },
    });

    _ = try defineClass(vm, a, "InfiniteIterator", "IteratorIterator", &.{}, &.{
        .{ .name = "__construct", .arity = 1, .f = infConstruct },
        .{ .name = "next", .f = infNext },
    });

    const rx = try defineClass(vm, a, "RegexIterator", "FilterIterator", &.{}, &.{
        .{ .name = "__construct", .arity = 5, .f = rxConstruct },
        .{ .name = "accept", .f = rxAccept },
        .{ .name = "getMode", .f = rxGetMode },
        .{ .name = "setMode", .arity = 1, .f = rxSetMode },
        .{ .name = "getFlags", .f = rxGetFlags },
        .{ .name = "setFlags", .arity = 1, .f = rxSetFlags },
        .{ .name = "getRegex", .f = rxGetRegex },
        .{ .name = "getPregFlags", .f = rxGetPregFlags },
        .{ .name = "setPregFlags", .arity = 1, .f = rxSetPregFlags },
    });
    try rx.constants.put(a, "USE_KEY", .{ .int = REGIT_USE_KEY });
    try rx.constants.put(a, "INVERT_MATCH", .{ .int = REGIT_INVERTED });
    try rx.constants.put(a, "MATCH", .{ .int = REGIT_MODE_MATCH });
    try rx.constants.put(a, "GET_MATCH", .{ .int = REGIT_MODE_GET_MATCH });
    try rx.constants.put(a, "ALL_MATCHES", .{ .int = REGIT_MODE_ALL_MATCHES });
    try rx.constants.put(a, "SPLIT", .{ .int = REGIT_MODE_SPLIT });
    try rx.constants.put(a, "REPLACE", .{ .int = REGIT_MODE_REPLACE });
    try rx.properties.append(a, .{ .name = "replacement", .default = .null, .has_default = true, .type_str = "?string" });

    _ = try defineClass(vm, a, "RecursiveRegexIterator", "RegexIterator", &.{"RecursiveIterator"}, &.{
        .{ .name = "__construct", .arity = 5, .f = rrxConstruct },
        .{ .name = "accept", .f = rrxAccept },
        .{ .name = "hasChildren", .f = rfiHasChildren },
        .{ .name = "getChildren", .f = rrxGetChildren },
    });

    const rti = try defineClass(vm, a, "RecursiveTreeIterator", "RecursiveIteratorIterator", &.{}, &.{
        .{ .name = "__construct", .arity = 4, .f = rtiConstruct },
        .{ .name = "key", .f = rtiKey },
        .{ .name = "current", .f = rtiCurrent },
        .{ .name = "getPrefix", .f = rtiGetPrefix },
        .{ .name = "setPostfix", .arity = 1, .f = rtiSetPostfix },
        .{ .name = "setPrefixPart", .arity = 2, .f = rtiSetPrefixPart },
        .{ .name = "getEntry", .f = rtiGetEntry },
        .{ .name = "getPostfix", .f = rtiGetPostfix },
    });
    try rti.constants.put(a, "BYPASS_CURRENT", .{ .int = RTIT_BYPASS_CURRENT });
    try rti.constants.put(a, "BYPASS_KEY", .{ .int = RTIT_BYPASS_KEY });
    try rti.constants.put(a, "PREFIX_LEFT", .{ .int = 0 });
    try rti.constants.put(a, "PREFIX_MID_HAS_NEXT", .{ .int = 1 });
    try rti.constants.put(a, "PREFIX_MID_LAST", .{ .int = 2 });
    try rti.constants.put(a, "PREFIX_END_HAS_NEXT", .{ .int = 3 });
    try rti.constants.put(a, "PREFIX_END_LAST", .{ .int = 4 });
    try rti.constants.put(a, "PREFIX_RIGHT", .{ .int = 5 });
}
