const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const std = @import("std");
const object_properties = @import("../runtime/object_properties.zig");
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

const SerCtx = struct {
    objects: std.AutoHashMapUnmanaged(*PhpObject, usize) = .{},
    arrays: std.AutoHashMapUnmanaged(*PhpArray, usize) = .{},
    cells: std.AutoHashMapUnmanaged(*Value, usize) = .{},
    next_slot: usize = 1,
    // the value serialize() was called with, and the references its native
    // call holds to it, which php's refcount doesn't see
    call_value: ?*PhpObject = null,
    call_holds: u32 = 0,

    // the table keeps the objects it records alive until the outermost
    // serialize() ends, as php's does, so a temporary written by a nested
    // Serializable::serialize() can't be freed and its address reused
    fn deinit(self: *SerCtx, ctx: *NativeContext) void {
        const a = ctx.allocator;
        var it = self.objects.keyIterator();
        while (it.next()) |obj| ctx.vm.objRelease(obj.*);
        self.cells.deinit(a);
        self.objects.deinit(a);
        self.arrays.deinit(a);
    }
};

const AllowedClasses = union(enum) {
    all,
    none,
    list: []const []const u8,
};

const ArrayTarget = struct { array: *PhpArray, key: PhpArray.Key };

const UnserCtx = struct {
    slots: std.ArrayListUnmanaged(Value) = .empty,
    array_targets: std.AutoHashMapUnmanaged(usize, ArrayTarget) = .{},
    allowed: AllowedClasses = .all,
    // set when we threw a user-visible exception (e.g. TypeError on a typed
    // property) so native_unserialize knows to propagate the error instead
    // of swallowing it as a parse-failure `false`
    threw: bool = false,
    // max_depth option for unserialize - matches PHP 7.4+ default of 4096.
    // depth_exceeded flag distinguishes from generic parse errors so the
    // warning text matches PHP exactly
    max_depth: usize = 4096,
    depth: usize = 0,
    depth_exceeded: bool = false,
    // tracks the source offset where parsing first failed, for the
    // 'Error at offset N of M bytes' warning. start at 0 which matches
    // PHP for entirely-bogus input
    err_pos: usize = 0,

    fn deinit(self: *UnserCtx, a: Allocator) void {
        self.array_targets.deinit(a);
        self.slots.deinit(a);
    }

    fn classAllowed(self: *const UnserCtx, name: []const u8) bool {
        return switch (self.allowed) {
            .all => true,
            .none => false,
            .list => |names| blk: {
                for (names) |n| {
                    if (std.ascii.eqlIgnoreCase(n, name)) break :blk true;
                }
                break :blk false;
            },
        };
    }

    fn reserve(self: *UnserCtx, a: Allocator) !usize {
        const idx = self.slots.items.len;
        try self.slots.append(a, .null);
        return idx;
    }

    fn store(self: *UnserCtx, idx: usize, val: Value) void {
        self.slots.items[idx] = val;
    }
};

pub const entries = .{
    .{ "serialize", native_serialize },
    .{ "unserialize", native_unserialize },
};

fn formatPhpFloat(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, f: f64) !void {
    if (std.math.isNan(f)) {
        try buf.appendSlice(a, "NAN");
        return;
    }
    if (std.math.isInf(f)) {
        if (f < 0) try buf.append(a, '-');
        try buf.appendSlice(a, "INF");
        return;
    }
    if (f == 0.0) {
        if (std.math.signbit(f)) {
            try buf.appendSlice(a, "-0");
        } else {
            try buf.appendSlice(a, "0");
        }
        return;
    }
    // match PHP's serialize_precision=-1 shortest-roundtrip algorithm: decimal for
    // magnitudes in [1e-4, 1e17), scientific otherwise
    const abs_f = @abs(f);
    const exp = if (abs_f != 0) @floor(@log10(abs_f)) else 0;
    const use_sci = exp < -4 or abs_f >= 1e17;
    if (use_sci) {
        // scientific notation like PHP: 1.0E-6, 1.0E+16
        var tmp: [64]u8 = undefined;
        const s = std.fmt.bufPrint(&tmp, "{e}", .{f}) catch return;
        // zig outputs like 1e-6 or 1e19, PHP outputs 1.0E-6 or 1.0E+19.
        // transform: uppercase E, ensure decimal point before E, explicit sign after E.
        var i: usize = 0;
        while (i < s.len) : (i += 1) {
            const c = s[i];
            if (c == 'e') {
                // ensure there's a decimal point before E
                const written = buf.items.len;
                var has_dot = false;
                var search = written;
                while (search > 0) : (search -= 1) {
                    if (buf.items[search - 1] == '.') {
                        has_dot = true;
                        break;
                    }
                    if (buf.items[search - 1] == '-' or buf.items[search - 1] == '+') break;
                }
                if (!has_dot) try buf.appendSlice(a, ".0");
                try buf.append(a, 'E');
                // emit explicit sign; if zig didn't provide one the exponent is positive
                if (i + 1 < s.len and (s[i + 1] == '-' or s[i + 1] == '+')) {
                    try buf.append(a, s[i + 1]);
                    i += 1;
                } else {
                    try buf.append(a, '+');
                }
            } else {
                try buf.append(a, c);
            }
        }
    } else {
        var tmp: [64]u8 = undefined;
        const s = std.fmt.bufPrint(&tmp, "{d}", .{f}) catch return;
        try buf.appendSlice(a, s);
    }
}

fn native_serialize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    if (args[0] == .object) {
        if (std.mem.eql(u8, args[0].object.class_name, "Closure")) {
            try ctx.vm.setPendingException("Exception", "Serialization of 'Closure' is not allowed");
            return error.RuntimeError;
        }
    }
    if (args[0] == .generator) {
        try ctx.vm.setPendingException("Exception", "Serialization of 'Generator' is not allowed");
        return error.RuntimeError;
    }
    if (args[0] == .fiber) {
        try ctx.vm.setPendingException("Exception", "Serialization of 'Fiber' is not allowed");
        return error.RuntimeError;
    }
    // invokeNative holds each argument twice for the call (a retain and an
    // operand-stack hold); php's argument is one reference
    return try serializeWith(ctx, args[0], 1);
}

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
    if (@import("../runtime/class_names.zig").isAnonymous(class_name)) return .always;
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
    const msg = switch (rule) {
        .always => try std.fmt.allocPrint(ctx.allocator, "{s} of '{s}' is not allowed", .{ verb, class_name }),
        .unless_methods => blk: {
            if (ctx.vm.hasMethod(class_name, if (direction == .serialize) "__serialize" else "__unserialize")) return;
            const methods = if (direction == .serialize) "serialization" else "unserialization";
            break :blk try std.fmt.allocPrint(ctx.allocator, "{s} of '{s}' is not allowed, unless {s} methods are implemented in a subclass", .{ verb, class_name, methods });
        },
    };
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("Exception", msg);
    return error.RuntimeError;
}

// php's BG(serialize): a serialize() nested in a Serializable::serialize()
// method shares the outer call's reference table, so the objects the outer
// call has written are back references there. __serialize and __sleep run
// under serialize_lock, where a nested call starts its own table
threadlocal var shared_ctx: ?*SerCtx = null;
threadlocal var serialize_lock: u32 = 0;
threadlocal var shared_uctx: ?*UnserCtx = null;

pub fn serializeToString(ctx: *NativeContext, val: Value) RuntimeError!NativeResult {
    return serializeWith(ctx, val, 0);
}

// `call_holds`: the references the native call that received `val` holds to
// it beyond the one php's argument has
fn serializeWith(ctx: *NativeContext, val: Value, call_holds: u32) RuntimeError!NativeResult {
    var buf = std.ArrayListUnmanaged(u8).empty;
    errdefer buf.deinit(ctx.allocator);
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
    try serializeValue(ctx, &buf, sctx, val);
    const result = try buf.toOwnedSlice(ctx.allocator);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result));
}

// a string result carries one reference the caller must release or store
// the object keeps its class name, so it must outlive this call
fn keptClassName(ctx: *NativeContext, class_allowed: bool, orig_class: []const u8) ![]const u8 {
    if (!class_allowed) return "__PHP_Incomplete_Class";
    return ctx.vm.stableClassName(orig_class);
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
        serializeValue(self.ctx, &self.buf, self.sctx(), v) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.RuntimeError;
    }

    pub fn raw(self: *Writer, bytes: []const u8) RuntimeError!void {
        try self.buf.appendSlice(self.ctx.allocator, bytes);
    }

    // the written string, which the caller takes
    pub fn finish(self: *Writer) RuntimeError!NativeResult {
        const result = try self.buf.toOwnedSlice(self.ctx.allocator);
        return NativeResult.takeString(try Value.String.adopt(self.ctx.allocator, result));
    }

    pub fn deinit(self: *Writer) void {
        if (self.owner) shared_ctx = null;
        self.own.deinit(self.ctx);
        self.buf.deinit(self.ctx.allocator);
    }
};

// php_var_unserialize as a Serializable::unserialize() method calls it:
// values read one after another from `s`, sharing the back-reference table
// of the unserialize() call that is running (BG(unserialize)), or a table
// of their own
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
        const saved_err = uctx.err_pos;
        uctx.err_pos = 0;
        defer uctx.err_pos = saved_err;
        const r = unserializeValue(self.ctx, uctx, self.s, self.pos) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            if (uctx.threw or self.ctx.vm.pending_exception != null) return error.RuntimeError;
            // php leaves its cursor where the value went wrong
            self.pos = @max(self.pos, uctx.err_pos);
            return null;
        };
        self.pos = r.pos;
        return r.value;
    }

    pub fn deinit(self: *Reader) void {
        if (self.owner) shared_uctx = null;
        self.own.deinit(self.ctx.allocator);
    }
};

pub fn unserializeFromString(ctx: *NativeContext, s: []const u8) ?Value {
    var uctx = UnserCtx{};
    defer uctx.deinit(ctx.allocator);
    const result = unserializeValue(ctx, &uctx, s, 0) catch return null;
    return result.value;
}

fn emitLenString(buf: *std.ArrayListUnmanaged(u8), a: Allocator, s: []const u8) !void {
    try buf.appendSlice(a, "s:");
    var tmp: [20]u8 = undefined;
    const len_s = std.fmt.bufPrint(&tmp, "{d}", .{s.len}) catch return;
    try buf.appendSlice(a, len_s);
    try buf.appendSlice(a, ":\"");
    try buf.appendSlice(a, s);
    try buf.appendSlice(a, "\";");
}

fn findPropertyVisibility(cls: ClassDef, name: []const u8) ClassDef.Visibility {
    for (cls.properties.items) |pdef| {
        if (std.mem.eql(u8, pdef.name, name)) return pdef.visibility;
    }
    return .public;
}

fn findPropertyType(vm: anytype, class_name: []const u8, prop_name: []const u8) []const u8 {
    var cur: ?[]const u8 = class_name;
    while (cur) |cn| {
        const cls = vm.classes.get(cn) orelse return "";
        for (cls.properties.items) |pdef| {
            if (std.mem.eql(u8, pdef.name, prop_name)) return pdef.type_str;
        }
        cur = cls.parent;
    }
    return "";
}

fn emitObjectPropertyKey(
    buf: *std.ArrayListUnmanaged(u8),
    a: Allocator,
    class_name: []const u8,
    prop_name: []const u8,
    visibility: ClassDef.Visibility,
) !void {
    switch (visibility) {
        .public => try emitLenString(buf, a, prop_name),
        .protected => {
            const total_len = 3 + prop_name.len;
            try buf.appendSlice(a, "s:");
            var tmp: [20]u8 = undefined;
            const len_s = std.fmt.bufPrint(&tmp, "{d}", .{total_len}) catch return;
            try buf.appendSlice(a, len_s);
            try buf.appendSlice(a, ":\"");
            try buf.append(a, 0);
            try buf.append(a, '*');
            try buf.append(a, 0);
            try buf.appendSlice(a, prop_name);
            try buf.appendSlice(a, "\";");
        },
        .private => {
            const total_len = 2 + class_name.len + prop_name.len;
            try buf.appendSlice(a, "s:");
            var tmp: [20]u8 = undefined;
            const len_s = std.fmt.bufPrint(&tmp, "{d}", .{total_len}) catch return;
            try buf.appendSlice(a, len_s);
            try buf.appendSlice(a, ":\"");
            try buf.append(a, 0);
            try buf.appendSlice(a, class_name);
            try buf.append(a, 0);
            try buf.appendSlice(a, prop_name);
            try buf.appendSlice(a, "\";");
        },
    }
}

fn serializeValue(ctx: *NativeContext, buf: *std.ArrayListUnmanaged(u8), sctx: *SerCtx, val: Value) !void {
    const a = ctx.allocator;
    // every value occupies a slot, including references themselves
    const my_slot = sctx.next_slot;
    sctx.next_slot += 1;
    _ = my_slot;

    switch (val) {
        .null => try buf.appendSlice(a, "N;"),
        .bool => |b| {
            try buf.appendSlice(a, if (b) "b:1;" else "b:0;");
        },
        .int => |i| {
            try buf.appendSlice(a, "i:");
            var tmp: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return;
            try buf.appendSlice(a, s);
            try buf.append(a, ';');
        },
        .float => |f| {
            try buf.appendSlice(a, "d:");
            try formatPhpFloat(buf, a, f);
            try buf.append(a, ';');
        },
        .string => |str| try emitLenString(buf, a, str.bytes()),
        .array => |arr| {
            // cycle guard: arrays only appear circular when zphp's limited
            // by-reference support has aliased one into itself; emit a back
            // reference instead of recursing forever
            if (sctx.arrays.get(arr)) |existing_slot| {
                try buf.appendSlice(a, "R:");
                var tmp: [20]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{existing_slot}) catch return;
                try buf.appendSlice(a, s);
                try buf.append(a, ';');
                return;
            }
            try sctx.arrays.put(a, arr, sctx.next_slot - 1);
            defer _ = sctx.arrays.remove(arr);
            try buf.appendSlice(a, "a:");
            var tmp: [20]u8 = undefined;
            const len_s = std.fmt.bufPrint(&tmp, "{d}", .{arr.entries.items.len}) catch return;
            try buf.appendSlice(a, len_s);
            try buf.appendSlice(a, ":{");
            for (arr.entries.items) |entry| {
                // keys do not occupy a slot in PHP's reference counting
                switch (entry.key) {
                    .int => |i| {
                        try buf.appendSlice(a, "i:");
                        const ki = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return;
                        try buf.appendSlice(a, ki);
                        try buf.append(a, ';');
                    },
                    .string => |s| try emitLenString(buf, a, s.bytes()),
                }
                if (if (entry.ref) |cell| (if (@import("../runtime/value.zig").cellOf(cell).binders > 1) cell else null) else null) |cell| {
                    if (sctx.cells.get(cell)) |id| {
                        const ref = try std.fmt.allocPrint(a, "R:{d};", .{id});
                        defer a.free(ref);
                        try buf.appendSlice(a, ref);
                        continue;
                    }
                    try sctx.cells.put(a, cell, sctx.next_slot);
                }
                try serializeValue(ctx, buf, sctx, entry.value);
            }
            try buf.append(a, '}');
        },
        // php writes a resource as int 0, with no back-reference slot of its own
        .resource => try buf.appendSlice(a, "i:0;"),
        .object => |proxy| {
            var obj = proxy;
            if (obj.lazy) |state| {
                if (!state.skip_serialize) try ctx.vm.triggerLazyInit(obj);
            }
            obj = obj.storage();
            try refuseNotSerializable(ctx, obj.class_name, .serialize);
            // emit a back-reference if we've already serialized this object
            if (sctx.objects.get(obj)) |existing_slot| {
                // rewind the slot counter: this r: entry occupies the slot we already consumed
                try buf.appendSlice(a, "r:");
                var tmp: [20]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{existing_slot}) catch return;
                try buf.appendSlice(a, s);
                try buf.append(a, ';');
                return;
            }
            // php's php_add_var_hash: an object nothing else holds can't
            // appear again, so it isn't recorded (and isn't kept alive),
            // unless __serialize or __sleep could hand it out again
            const call_holds: u32 = if (sctx.call_value == obj) sctx.call_holds else 0;
            if (obj.refcount -| call_holds > 1 or ctx.vm.hasMethod(obj.class_name, "__serialize") or ctx.vm.hasMethod(obj.class_name, "__sleep")) {
                try sctx.objects.put(a, obj, sctx.next_slot - 1);
                @import("../runtime/vm.zig").VM.objRetain(obj);
            }

            // enum: emit E:<len>:"Class:Case"; per PHP 8.1
            if (ctx.vm.classes.get(obj.class_name)) |cdef| {
                if (cdef.is_enum) {
                    const name_val = obj.get("name");
                    const case_name: []const u8 = if (name_val == .string) name_val.string.bytes() else "";
                    const total_len = obj.class_name.len + 1 + case_name.len;
                    try buf.appendSlice(a, "E:");
                    var tmp: [20]u8 = undefined;
                    const ls = std.fmt.bufPrint(&tmp, "{d}", .{total_len}) catch return;
                    try buf.appendSlice(a, ls);
                    try buf.appendSlice(a, ":\"");
                    try buf.appendSlice(a, obj.class_name);
                    try buf.append(a, ':');
                    try buf.appendSlice(a, case_name);
                    try buf.appendSlice(a, "\";");
                    return;
                }
            }

            // SplFixedArray: emit fixed-length object with int-keyed entries from __data
            if (std.mem.eql(u8, obj.class_name, "SplFixedArray")) {
                const data = obj.get("__data");
                if (data == .array) {
                    const arr_v = data.array;
                    try buf.appendSlice(a, "O:13:\"SplFixedArray\":");
                    var tmp: [20]u8 = undefined;
                    const cl = std.fmt.bufPrint(&tmp, "{d}", .{arr_v.entries.items.len}) catch return;
                    try buf.appendSlice(a, cl);
                    try buf.appendSlice(a, ":{");
                    for (arr_v.entries.items, 0..) |entry, i| {
                        try buf.appendSlice(a, "i:");
                        const ki = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return;
                        try buf.appendSlice(a, ki);
                        try buf.append(a, ';');
                        try serializeValue(ctx, buf, sctx, entry.value);
                    }
                    try buf.append(a, '}');
                    return;
                }
            }

            // legacy Serializable interface: serialize() returns a string and
            // the wire format is C:<class_name_len>:"<class_name>":<data_len>:{<data>}
            // PHP prefers __serialize/__unserialize when both are present so
            // this check sits BELOW the __serialize path is wrong - actually PHP
            // checks Serializable first only if __serialize is absent. handle
            // the Serializable path here so it precedes the regular property
            // serialization but does not override __serialize/__sleep below
            if (!ctx.vm.hasMethod(obj.class_name, "__serialize") and ctx.vm.isInstanceOf(obj.class_name, "Serializable") and ctx.vm.hasMethod(obj.class_name, "serialize")) {
                const ser_result = try ctx.vm.callMethod(obj, "serialize", &.{});
                const payload: []const u8 = if (ser_result == .string) ser_result.string.bytes() else "";
                try buf.appendSlice(a, "C:");
                var tmp: [20]u8 = undefined;
                const nl = std.fmt.bufPrint(&tmp, "{d}", .{obj.class_name.len}) catch return;
                try buf.appendSlice(a, nl);
                try buf.appendSlice(a, ":\"");
                try buf.appendSlice(a, obj.class_name);
                try buf.appendSlice(a, "\":");
                const dl = std.fmt.bufPrint(&tmp, "{d}", .{payload.len}) catch return;
                try buf.appendSlice(a, dl);
                try buf.appendSlice(a, ":{");
                try buf.appendSlice(a, payload);
                try buf.append(a, '}');
                return;
            }

            // PHP 7.4+ __serialize: returns the array used as the object's serialized payload
            if (ctx.vm.hasMethod(obj.class_name, "__serialize")) {
                serialize_lock += 1;
                const ser_result = ctx.vm.callMethod(obj, "__serialize", &.{}) catch |err| {
                    serialize_lock -= 1;
                    return err;
                };
                serialize_lock -= 1;
                @import("../runtime/vm.zig").VM.retainValue(ser_result);
                defer ctx.vm.releaseValue(ser_result);
                if (ser_result == .array) {
                    try buf.appendSlice(a, "O:");
                    var tmp: [20]u8 = undefined;
                    const nl = std.fmt.bufPrint(&tmp, "{d}", .{obj.class_name.len}) catch return;
                    try buf.appendSlice(a, nl);
                    try buf.appendSlice(a, ":\"");
                    try buf.appendSlice(a, obj.class_name);
                    try buf.appendSlice(a, "\":");
                    const cl = std.fmt.bufPrint(&tmp, "{d}", .{ser_result.array.entries.items.len}) catch return;
                    try buf.appendSlice(a, cl);
                    try buf.appendSlice(a, ":{");
                    for (ser_result.array.entries.items) |entry| {
                        switch (entry.key) {
                            .int => |i| {
                                try buf.appendSlice(a, "i:");
                                const ki = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return;
                                try buf.appendSlice(a, ki);
                                try buf.append(a, ';');
                            },
                            .string => |s| try emitLenString(buf, a, s.bytes()),
                        }
                        try serializeValue(ctx, buf, sctx, entry.value);
                    }
                    try buf.append(a, '}');
                    return;
                }
            }

            // older __sleep: returns string[] of property names to include
            var sleep_props: ?*PhpArray = null;
            defer if (sleep_props) |props| ctx.vm.releaseValue(.{ .array = props });
            if (ctx.vm.hasMethod(obj.class_name, "__sleep")) {
                serialize_lock += 1;
                const sleep_result = ctx.vm.callMethod(obj, "__sleep", &.{}) catch |err| {
                    serialize_lock -= 1;
                    return err;
                };
                serialize_lock -= 1;
                if (sleep_result == .array) {
                    @import("../runtime/vm.zig").VM.retainValue(sleep_result);
                    sleep_props = sleep_result.array;
                }
            }

            try buf.appendSlice(a, "O:");
            var tmp: [20]u8 = undefined;
            const nl = std.fmt.bufPrint(&tmp, "{d}", .{obj.class_name.len}) catch return;
            try buf.appendSlice(a, nl);
            try buf.appendSlice(a, ":\"");
            try buf.appendSlice(a, obj.class_name);
            try buf.appendSlice(a, "\":");
            var listing: object_properties.Listing = .{};
            defer listing.deinit(a);
            if (sleep_props == null) listing = try object_properties.list(ctx.vm, obj, .serialize, a);
            // php_var_serialize_get_sleep_props: a typed property __sleep
            // names that is uninitialized (a lazy object's included) is left out
            var sleep_count: usize = 0;
            if (sleep_props) |sp| for (sp.entries.items) |entry| {
                if (entry.value != .string or sleepSkips(ctx.vm, obj, entry.value.string.bytes())) continue;
                sleep_count += 1;
            };
            const total_count: usize = if (sleep_props != null) sleep_count else listing.items.items.len;
            const cl = std.fmt.bufPrint(&tmp, "{d}", .{total_count}) catch return;
            try buf.appendSlice(a, cl);
            try buf.appendSlice(a, ":{");

            const class_def = ctx.vm.classes.get(obj.class_name);
            if (sleep_props) |sp| {
                for (sp.entries.items) |entry| {
                    if (entry.value != .string) continue;
                    const name = entry.value.string.bytes();
                    if (sleepSkips(ctx.vm, obj, name)) continue;
                    const vis: ClassDef.Visibility = if (class_def) |c| findPropertyVisibility(c, name) else .public;
                    try emitObjectPropertyKey(buf, a, obj.class_name, name, vis);
                    const v = obj.get(name);
                    try serializeValue(ctx, buf, sctx, v);
                }
                try buf.append(a, '}');
                return;
            }
            for (listing.items.items) |prop| {
                switch (prop.key) {
                    .int => |i| try buf.print(a, "i:{d};", .{i}),
                    .name => |name| try emitObjectPropertyKey(buf, a, if (prop.declaring.len > 0) prop.declaring else obj.class_name, name, prop.visibility),
                }
                try serializeValue(ctx, buf, sctx, prop.value);
            }
            try buf.append(a, '}');
        },
        else => try buf.appendSlice(a, "N;"),
    }
}

fn sleepSkips(vm: *VM, obj: *PhpObject, name: []const u8) bool {
    const decl = vm.propertyDeclaration(obj.class_name, name);
    if (decl.type_str.len == 0) return false;
    if (obj.isLazySlot(name, decl.defining_class)) return true;
    return obj.rawForScope(name, decl.defining_class) == .undef;
}

fn native_unserialize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const s = args[0].string.bytes();
    // PHP returns false silently for empty input - no warning
    if (s.len == 0) return NativeResult.scalar(.{ .bool = false });
    // nested in a Serializable::unserialize() method, the call shares the
    // outer call's back-reference table (php's BG(unserialize)) with its own
    // options and error state
    var own = UnserCtx{};
    defer own.deinit(ctx.allocator);
    const outer = if (serialize_lock == 0) shared_uctx else null;
    const uctx: *UnserCtx = outer orelse &own;
    const saved = uctx.*;
    if (outer != null) {
        uctx.allowed = .all;
        uctx.threw = false;
        uctx.depth_exceeded = false;
        uctx.err_pos = 0;
    }
    defer if (outer != null) {
        uctx.allowed = saved.allowed;
        uctx.threw = saved.threw;
        uctx.max_depth = saved.max_depth;
        uctx.depth = saved.depth;
        uctx.depth_exceeded = saved.depth_exceeded;
        uctx.err_pos = saved.err_pos;
    };
    const owner = outer == null and serialize_lock == 0;
    if (owner) shared_uctx = &own;
    defer if (owner) {
        shared_uctx = null;
    };
    var name_storage: std.ArrayListUnmanaged([]const u8) = .empty;
    defer name_storage.deinit(ctx.allocator);
    if (args.len >= 2 and args[1] == .array) {
        const opts = args[1].array;
        const ac = opts.get(.{ .string = Value.String.borrowed("allowed_classes") });
        switch (ac) {
            .bool => |b| uctx.allowed = if (b) .all else .none,
            .array => |a| {
                for (a.entries.items) |entry| {
                    if (entry.value == .string) try name_storage.append(ctx.allocator, entry.value.string.bytes());
                }
                uctx.allowed = .{ .list = name_storage.items };
            },
            else => {},
        }
        const md = opts.get(.{ .string = Value.String.borrowed("max_depth") });
        // a nested call keeps counting the outer call's depth unless it
        // sets its own limit
        if (md == .int and md.int >= 0) {
            uctx.max_depth = @intCast(md.int);
            uctx.depth = 0;
        }
    }
    const result = unserializeValue(ctx, uctx, s, 0) catch {
        // an exception from __unserialize, __wakeup, or Serializable::unserialize
        // propagates; only a parse failure is a warning
        if (uctx.threw or ctx.vm.pending_exception != null) return error.RuntimeError;
        // emit PHP's parse-failure warning. depth-exceeded gets its own
        // message that names the option + ini setting; generic parse errors
        // get 'Error at offset N of M bytes'
        if (uctx.depth_exceeded) {
            const msg = std.fmt.allocPrint(ctx.allocator, "unserialize(): Maximum depth of {d} exceeded. The depth limit can be changed using the max_depth unserialize() option or the unserialize_max_depth ini setting", .{uctx.max_depth}) catch return NativeResult.scalar(.{ .bool = false });
            defer ctx.allocator.free(msg);
            try ctx.vm.emitWarning(msg);
        }
        const msg2 = std.fmt.allocPrint(ctx.allocator, "unserialize(): Error at offset {d} of {d} bytes", .{ uctx.err_pos, s.len }) catch return NativeResult.scalar(.{ .bool = false });
        defer ctx.allocator.free(msg2);
        try ctx.vm.emitWarning(msg2);
        return NativeResult.scalar(.{ .bool = false });
    };
    return NativeResult.transfer(result.value);
}

// every parsed string result carries one reference for its consumer; the
// consumer drops it once the value is stored (containers retain their own)
fn releaseParsed(v: Value) void {
    if (v == .string) v.string.release();
}

fn strippedKey(str: Value.String) Value.String {
    const full = str.bytes();
    const stripped = stripVisibilityPrefix(full);
    return str.borrowedSlice(full.len - stripped.len, full.len);
}

const ParseResult = struct {
    value: Value,
    pos: usize,
};

fn stripVisibilityPrefix(name: []const u8) []const u8 {
    if (name.len > 2 and name[0] == 0) {
        if (std.mem.lastIndexOfScalar(u8, name[1..], 0)) |last| {
            const second = last + 1;
            return name[second + 1 ..];
        }
    }
    return name;
}

fn unserializeValue(ctx: *NativeContext, uctx: *UnserCtx, s: []const u8, pos: usize) !ParseResult {
    if (pos >= s.len) {
        uctx.err_pos = pos;
        return error.RuntimeError;
    }

    errdefer if (uctx.err_pos == 0) {
        uctx.err_pos = pos;
    };
    switch (s[pos]) {
        'N' => {
            if (pos + 1 < s.len and s[pos + 1] == ';') {
                try uctx.slots.append(ctx.allocator, .null);
                return .{ .value = .null, .pos = pos + 2 };
            }
            return error.RuntimeError;
        },
        'b' => {
            if (pos + 3 < s.len and s[pos + 1] == ':' and s[pos + 3] == ';') {
                const v: Value = .{ .bool = s[pos + 2] == '1' };
                try uctx.slots.append(ctx.allocator, v);
                return .{ .value = v, .pos = pos + 4 };
            }
            return error.RuntimeError;
        },
        'i' => {
            if (pos + 2 >= s.len or s[pos + 1] != ':') return error.RuntimeError;
            const start = pos + 2;
            const end = std.mem.indexOfPos(u8, s, start, ";") orelse return error.RuntimeError;
            const i = std.fmt.parseInt(i64, s[start..end], 10) catch return error.RuntimeError;
            const v: Value = .{ .int = i };
            try uctx.slots.append(ctx.allocator, v);
            return .{ .value = v, .pos = end + 1 };
        },
        'd' => {
            if (pos + 2 >= s.len or s[pos + 1] != ':') return error.RuntimeError;
            const start = pos + 2;
            const end = std.mem.indexOfPos(u8, s, start, ";") orelse return error.RuntimeError;
            const f = std.fmt.parseFloat(f64, s[start..end]) catch return error.RuntimeError;
            const v: Value = .{ .float = f };
            try uctx.slots.append(ctx.allocator, v);
            return .{ .value = v, .pos = end + 1 };
        },
        's' => {
            const r = try parseString(s, pos);
            const v: Value = .{ .string = try Value.String.create(ctx.allocator, r.str) };
            try uctx.slots.append(ctx.allocator, v);
            return .{ .value = v, .pos = r.pos };
        },
        'a' => {
            if (pos + 2 >= s.len or s[pos + 1] != ':') return error.RuntimeError;
            const count_start = pos + 2;
            const colon = std.mem.indexOfPos(u8, s, count_start, ":") orelse return error.RuntimeError;
            const count = std.fmt.parseInt(usize, s[count_start..colon], 10) catch return error.RuntimeError;
            if (colon + 1 >= s.len or s[colon + 1] != '{') return error.RuntimeError;
            var p = colon + 2;
            // PHP counts arrays/objects toward depth; check after consuming
            // 'a:N:{' so the err_pos points at the inner content start
            uctx.depth += 1;
            defer uctx.depth -= 1;
            if (uctx.depth > uctx.max_depth) {
                uctx.depth_exceeded = true;
                uctx.err_pos = p;
                return error.RuntimeError;
            }
            var arr = try ctx.createArray();
            const slot_idx = try uctx.reserve(ctx.allocator);
            uctx.store(slot_idx, .{ .array = arr });
            for (0..count) |_| {
                // PHP array keys are NOT counted as reference slots; use a throwaway
                // UnserCtx stack position that we roll back after each key parse.
                const key_slots_before = uctx.slots.items.len;
                const key_result = try unserializeValue(ctx, uctx, s, p);
                defer releaseParsed(key_result.value);
                p = key_result.pos;
                uctx.slots.items.len = key_slots_before;

                const value_pos = p;
                const value_slot = uctx.slots.items.len;
                const val_result = try unserializeValue(ctx, uctx, s, p);
                defer releaseParsed(val_result.value);
                p = val_result.pos;
                const key: PhpArray.Key = switch (key_result.value) {
                    .int => |i| .{ .int = i },
                    .string => |str| .{ .string = str },
                    else => return error.RuntimeError,
                };
                try arr.set(ctx.allocator, key, val_result.value);
                if (s[value_pos] == 'R') {
                    const id = try std.fmt.parseInt(usize, s[value_pos + 2 .. p - 1], 10);
                    if (uctx.array_targets.get(id - 1)) |target| {
                        try bindDecodedArrayReference(ctx, target.array, target.key, arr, key);
                    }
                } else {
                    try uctx.array_targets.put(ctx.allocator, value_slot, .{ .array = arr, .key = key });
                }
            }
            if (p >= s.len or s[p] != '}') {
                uctx.err_pos = p;
                return error.RuntimeError;
            }
            p += 1;
            return .{ .value = .{ .array = arr }, .pos = p };
        },
        'E' => {
            if (pos + 2 >= s.len or s[pos + 1] != ':') return error.RuntimeError;
            const colon1 = std.mem.indexOfPos(u8, s, pos + 2, ":") orelse return error.RuntimeError;
            const name_len = std.fmt.parseInt(usize, s[pos + 2 .. colon1], 10) catch return error.RuntimeError;
            if (colon1 + 2 + name_len + 2 > s.len) return error.RuntimeError;
            const payload = s[colon1 + 2 .. colon1 + 2 + name_len];
            const sep = std.mem.indexOfScalar(u8, payload, ':') orelse return error.RuntimeError;
            const cls_name = payload[0..sep];
            const case_name = payload[sep + 1 ..];
            const def = ctx.vm.classes.get(cls_name) orelse return error.RuntimeError;
            const v = ctx.vm.enumCase(def.constants.get(case_name) orelse return error.RuntimeError);
            if (v == .string) v.string.retain();
            try uctx.slots.append(ctx.allocator, v);
            var p = colon1 + 2 + name_len + 1;
            if (p < s.len and s[p] == ';') p += 1;
            return .{ .value = v, .pos = p };
        },
        'O' => {
            if (pos + 2 >= s.len or s[pos + 1] != ':') return error.RuntimeError;
            const colon1 = std.mem.indexOfPos(u8, s, pos + 2, ":") orelse return error.RuntimeError;
            const name_len = std.fmt.parseInt(usize, s[pos + 2 .. colon1], 10) catch return error.RuntimeError;
            if (colon1 + 2 + name_len + 1 >= s.len) return error.RuntimeError;
            const orig_class = s[colon1 + 2 .. colon1 + 2 + name_len];
            const class_allowed = uctx.classAllowed(orig_class) and ctx.vm.classes.contains(orig_class) and !value_mod.isResourceClass(orig_class);
            if (class_allowed) try refuseNotSerializable(ctx, orig_class, .unserialize);
            const class_name = try keptClassName(ctx, class_allowed, orig_class);
            var p = colon1 + 2 + name_len + 2;
            const count_end = std.mem.indexOfPos(u8, s, p, ":") orelse return error.RuntimeError;
            const prop_count = std.fmt.parseInt(usize, s[p..count_end], 10) catch return error.RuntimeError;
            if (count_end + 1 >= s.len or s[count_end + 1] != '{') return error.RuntimeError;
            p = count_end + 2;
            uctx.depth += 1;
            defer uctx.depth -= 1;
            if (uctx.depth > uctx.max_depth) {
                uctx.depth_exceeded = true;
                uctx.err_pos = p;
                return error.RuntimeError;
            }

            // ensure __PHP_Incomplete_Class exists in the class table
            if (!class_allowed and !ctx.vm.classes.contains("__PHP_Incomplete_Class")) {
                var def = ClassDef{ .name = "__PHP_Incomplete_Class" };
                try ctx.vm.classes.put(ctx.allocator, "__PHP_Incomplete_Class", def);
                _ = &def;
            }
            const obj = try ctx.createObject(class_name);
            if (!class_allowed) {
                try obj.setCopiedString(ctx.allocator, "__PHP_Incomplete_Class_Name", orig_class);
            }
            if (obj.slots == null) {
                if (ctx.vm.classes.get(class_name)) |cls| {
                    if (cls.slot_layout) |layout| {
                        obj.slots = try ctx.allocator.alloc(Value, layout.names.len);
                        for (layout.defaults, 0..) |def, i| obj.slots.?[i] = def;
                        obj.slot_layout = layout;
                    }
                }
            }

            // register slot before parsing contents so self-refs resolve
            const slot_idx = try uctx.reserve(ctx.allocator);
            uctx.store(slot_idx, .{ .object = obj });

            // collect props into a temp array first so __unserialize can receive them
            const has_unserialize = ctx.vm.hasMethod(class_name, "__unserialize");
            var collected: ?*PhpArray = null;
            if (has_unserialize) {
                const arr = try ctx.vm.allocArray();
                collected = arr;
            }

            const is_fixed_array = std.mem.eql(u8, class_name, "SplFixedArray");
            var fixed_data: ?*PhpArray = null;
            if (is_fixed_array) {
                const arr = try ctx.vm.allocArray();
                fixed_data = arr;
            }
            for (0..prop_count) |_| {
                const key_slots_before = uctx.slots.items.len;
                const key_result = try unserializeValue(ctx, uctx, s, p);
                defer releaseParsed(key_result.value);
                p = key_result.pos;
                uctx.slots.items.len = key_slots_before;

                const val_result = try unserializeValue(ctx, uctx, s, p);
                defer releaseParsed(val_result.value);
                p = val_result.pos;
                if (collected) |arr| {
                    const k: PhpArray.Key = switch (key_result.value) {
                        .string => |str| .{ .string = strippedKey(str) },
                        .int => |n| .{ .int = n },
                        else => continue,
                    };
                    try arr.set(ctx.allocator, k, val_result.value);
                } else if (fixed_data) |arr| {
                    if (key_result.value == .int) try arr.set(ctx.allocator, .{ .int = key_result.value.int }, val_result.value);
                } else if (key_result.value == .string) {
                    const stripped = stripVisibilityPrefix(key_result.value.string.bytes());
                    // when restoring into a kept class, assigning an
                    // __PHP_Incomplete_Class value to a typed property whose
                    // declared type isn't compatible is a TypeError in PHP
                    if (class_allowed and val_result.value == .object and std.mem.eql(u8, val_result.value.object.class_name, "__PHP_Incomplete_Class")) {
                        const ptype = findPropertyType(ctx.vm, class_name, stripped);
                        if (ptype.len > 0 and !ctx.vm.checkTypeMatch(val_result.value, ptype)) {
                            const msg = try std.fmt.allocPrint(ctx.allocator, "Cannot assign __PHP_Incomplete_Class to property {s}::${s} of type {s}", .{ class_name, stripped, ptype });
                            defer ctx.allocator.free(msg);
                            uctx.threw = true;
                            _ = try ctx.vm.throwBuiltinException("TypeError", msg);
                            return error.RuntimeError;
                        }
                    }
                    try obj.set(ctx.allocator, stripped, val_result.value);
                }
            }
            if (is_fixed_array) {
                try obj.set(ctx.allocator, "__data", .{ .array = fixed_data.? });
                try obj.set(ctx.allocator, "__size", .{ .int = @intCast(prop_count) });
                try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
            }
            if (p >= s.len or s[p] != '}') {
                uctx.err_pos = p;
                return error.RuntimeError;
            }
            p += 1;

            if (has_unserialize) {
                if (collected) |arr| {
                    serialize_lock += 1;
                    defer serialize_lock -= 1;
                    _ = try ctx.vm.callMethod(obj, "__unserialize", &.{.{ .array = arr }});
                }
            } else if (ctx.vm.hasMethod(class_name, "__wakeup")) {
                serialize_lock += 1;
                defer serialize_lock -= 1;
                _ = try ctx.vm.callMethod(obj, "__wakeup", &.{});
            }

            return .{ .value = .{ .object = obj }, .pos = p };
        },
        'C' => {
            // Serializable interface payload: C:<nlen>:"<name>":<dlen>:{<raw>}
            if (pos + 2 >= s.len or s[pos + 1] != ':') return error.RuntimeError;
            const colon1 = std.mem.indexOfPos(u8, s, pos + 2, ":") orelse return error.RuntimeError;
            const name_len = std.fmt.parseInt(usize, s[pos + 2 .. colon1], 10) catch return error.RuntimeError;
            if (colon1 + 2 + name_len + 1 >= s.len) return error.RuntimeError;
            const orig_class = s[colon1 + 2 .. colon1 + 2 + name_len];
            const class_allowed = uctx.classAllowed(orig_class) and ctx.vm.classes.contains(orig_class) and !value_mod.isResourceClass(orig_class);
            if (class_allowed) try refuseNotSerializable(ctx, orig_class, .unserialize);
            const class_name = try keptClassName(ctx, class_allowed, orig_class);
            var p = colon1 + 2 + name_len + 2;
            const len_end = std.mem.indexOfPos(u8, s, p, ":") orelse return error.RuntimeError;
            const data_len = std.fmt.parseInt(usize, s[p..len_end], 10) catch return error.RuntimeError;
            if (len_end + 1 >= s.len or s[len_end + 1] != '{') return error.RuntimeError;
            const data_start = len_end + 2;
            if (data_start + data_len > s.len) return error.RuntimeError;
            const payload = s[data_start .. data_start + data_len];
            p = data_start + data_len;
            if (p >= s.len or s[p] != '}') {
                uctx.err_pos = p;
                return error.RuntimeError;
            }
            p += 1;

            const obj = try ctx.createObject(class_name);
            const slot_idx = try uctx.reserve(ctx.allocator);
            uctx.store(slot_idx, .{ .object = obj });

            if (class_allowed and ctx.vm.hasMethod(class_name, "unserialize")) {
                _ = try ctx.vm.callMethod(obj, "unserialize", &.{.{ .string = Value.String.borrowed(payload) }});
            } else if (!class_allowed) {
                try obj.setCopiedString(ctx.allocator, "__PHP_Incomplete_Class_Name", orig_class);
                try obj.setCopiedString(ctx.allocator, "__serialized_data", payload);
            }
            return .{ .value = .{ .object = obj }, .pos = p };
        },
        'r', 'R' => {
            if (pos + 2 >= s.len or s[pos + 1] != ':') return error.RuntimeError;
            const start = pos + 2;
            const end = std.mem.indexOfPos(u8, s, start, ";") orelse return error.RuntimeError;
            const idx = std.fmt.parseInt(usize, s[start..end], 10) catch return error.RuntimeError;
            if (idx == 0 or idx > uctx.slots.items.len) return error.RuntimeError;
            const v = uctx.slots.items[idx - 1];
            if (s[pos] == 'r' and v != .object) return error.RuntimeError;
            if (s[pos] == 'r') try uctx.slots.append(ctx.allocator, v);
            if (v == .string) v.string.retain();
            return .{ .value = v, .pos = end + 1 };
        },
        else => return error.RuntimeError,
    }
}

const StringResult = struct { str: []const u8, pos: usize };

fn parseString(s: []const u8, pos: usize) !StringResult {
    // s:LEN:"...";
    if (pos + 2 >= s.len or s[pos + 1] != ':') return error.RuntimeError;
    const len_start = pos + 2;
    const colon = std.mem.indexOfPos(u8, s, len_start, ":") orelse return error.RuntimeError;
    const str_len = std.fmt.parseInt(usize, s[len_start..colon], 10) catch return error.RuntimeError;
    if (colon + 1 >= s.len or s[colon + 1] != '"') return error.RuntimeError;
    const str_start = colon + 2;
    if (str_start + str_len > s.len) return error.RuntimeError;
    const str = s[str_start .. str_start + str_len];
    const end = str_start + str_len;
    if (end + 1 >= s.len or s[end] != '"' or s[end + 1] != ';') return error.RuntimeError;
    return .{ .str = str, .pos = end + 2 };
}

// SPL's legacy Serializable stream has one reference table spanning flags,
// storage, and members (the separators themselves consume no reference IDs).
pub fn serializeSplArray(ctx: *NativeContext, obj: *PhpObject) RuntimeError!NativeResult {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(ctx.allocator);
    var refs: SerCtx = .{};
    defer refs.deinit(ctx);
    try buf.appendSlice(ctx.allocator, "x:");
    const flags = @import("spl.zig").serializedFlags(obj);
    try serializeValue(ctx, &buf, &refs, .{ .int = flags });
    if ((flags & @import("spl.zig").IS_SELF) == 0) {
        try serializeValue(ctx, &buf, &refs, obj.get("__data"));
        try buf.appendSlice(ctx.allocator, ";");
    }
    try buf.appendSlice(ctx.allocator, "m:");
    const members = try splMembers(ctx, obj);
    try serializeValue(ctx, &buf, &refs, .{ .array = members });
    const result = try buf.toOwnedSlice(ctx.allocator);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result));
}

fn splInternal(name: []const u8) bool {
    return std.mem.eql(u8, name, "__data") or std.mem.eql(u8, name, "__flags") or
        std.mem.eql(u8, name, "__cursor") or std.mem.eql(u8, name, "__iter_class");
}

fn splMember(ctx: *NativeContext, obj: *PhpObject, members: *PhpArray, name: []const u8, val: Value) !void {
    if (splInternal(name) or obj.isUnset(name)) return;
    const cls = ctx.vm.classes.get(obj.class_name);
    const vis = if (cls) |c| findPropertyVisibility(c, name) else .public;
    const key = switch (vis) {
        .public => name,
        .protected => try std.fmt.allocPrint(ctx.allocator, "\x00*\x00{s}", .{name}),
        .private => try std.fmt.allocPrint(ctx.allocator, "\x00{s}\x00{s}", .{ obj.class_name, name }),
    };
    defer if (vis != .public) ctx.allocator.free(key);
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
    if (s.len == 0) return NativeResult.scalar(.null); // PHP treats an empty payload as a no-op.
    var refs: UnserCtx = .{};
    defer refs.deinit(ctx.allocator);
    var pos: usize = 0;
    parseSplArray(ctx, obj, &refs, s, &pos) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        if (refs.threw or ctx.vm.pending_exception != null) return error.RuntimeError;
        const msg = try std.fmt.allocPrint(ctx.allocator, "Error at offset {d} of {d} bytes", .{ @max(pos, refs.err_pos), s.len });
        defer ctx.allocator.free(msg);
        try ctx.vm.setPendingException("UnexpectedValueException", msg);
        return error.RuntimeError;
    };
    return NativeResult.scalar(.null);
}

fn parseSplArray(ctx: *NativeContext, obj: *PhpObject, refs: *UnserCtx, s: []const u8, pos: *usize) !void {
    if (!std.mem.startsWith(u8, s, "x:")) return error.RuntimeError;
    pos.* = 2;
    const flags = try unserializeValue(ctx, refs, s, pos.*);
    pos.* = flags.pos;
    if (flags.value != .int) return error.RuntimeError;
    const spl = @import("spl.zig");
    // the storage takes effect before the members are read; an object php
    // refuses as storage throws once the members are loaded
    var refused = false;
    if ((flags.value.int & spl.IS_SELF) != 0) {
        try spl.splSetSelf(ctx, obj, flags.value.int);
    } else {
        if (pos.* >= s.len or (s[pos.*] != 'a' and s[pos.*] != 'O' and s[pos.*] != 'C' and s[pos.*] != 'r')) return error.RuntimeError;
        const parsed = try unserializeValue(ctx, refs, s, pos.*);
        pos.* = parsed.pos;
        const storage = parsed.value;
        if (storage != .array and storage != .object) return error.RuntimeError;
        if (storage == .array) {
            try obj.set(ctx.allocator, "__data", storage);
            try obj.set(ctx.allocator, "__flags", .{ .int = flags.value.int & spl.FLAGS_MASK });
            try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
        } else {
            spl.splSetStorage(ctx, obj, storage, flags.value.int | spl.otherFlags(ctx.vm, storage), "unserialize") catch |err| {
                if (err != error.RuntimeError or ctx.vm.pending_exception == null) return err;
                refused = true;
            };
        }
        if (pos.* >= s.len or s[pos.*] != ';') return error.RuntimeError;
        pos.* += 1;
    }
    if (!std.mem.startsWith(u8, s[pos.*..], "m:")) return error.RuntimeError;
    pos.* += 2;
    const members = try unserializeValue(ctx, refs, s, pos.*);
    pos.* = members.pos;
    if (members.value != .array) return error.RuntimeError;
    if (refused) {
        const pending = ctx.vm.takePending();
        defer if (pending) |p| ctx.vm.stackRelease(p);
        try spl.loadProperties(ctx, obj, members.value.array);
        if (pending) |p| {
            ctx.vm.pending_exception = p;
            @import("../runtime/vm.zig").VM.retainValue(p);
        }
        return error.RuntimeError;
    }
    try spl.loadProperties(ctx, obj, members.value.array);
    // Trailing bytes are intentionally ignored, as in PHP 8.5.
}

pub fn splArrayState(ctx: *NativeContext, obj: *PhpObject) RuntimeError!NativeResult {
    const state = try ctx.createArray();
    const flags = @import("spl.zig").serializedFlags(obj);
    try state.append(ctx.allocator, .{ .int = flags });
    const data = obj.get("__data");
    // __serialize exposes a value snapshot, not the mutable internal table.
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
