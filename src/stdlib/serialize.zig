const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const ClassDef = @import("../runtime/vm.zig").ClassDef;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

const SerCtx = struct {
    objects: std.AutoHashMapUnmanaged(*PhpObject, usize) = .{},
    arrays: std.AutoHashMapUnmanaged(*PhpArray, usize) = .{},
    next_slot: usize = 1,

    fn deinit(self: *SerCtx, a: Allocator) void {
        self.objects.deinit(a);
        self.arrays.deinit(a);
    }
};

const AllowedClasses = union(enum) {
    all,
    none,
    list: []const []const u8,
};

const UnserCtx = struct {
    slots: std.ArrayListUnmanaged(Value) = .{},
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
                    if (buf.items[search - 1] == '.') { has_dot = true; break; }
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

fn native_serialize(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    if (args[0] == .string and std.mem.startsWith(u8, args[0].string, "__closure_")) {
        try ctx.vm.setPendingException("Exception", "Serialization of 'Closure' is not allowed");
        return error.RuntimeError;
    }
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
    return try serializeToString(ctx, args[0]);
}

// Public entrypoint for other stdlib modules that need to serialize PHP values
// (e.g. session storage). Owns allocation via ctx.strings.
pub fn serializeToString(ctx: *NativeContext, val: Value) RuntimeError!Value {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(ctx.allocator);
    var sctx = SerCtx{};
    defer sctx.deinit(ctx.allocator);
    try serializeValue(ctx, &buf, &sctx, val);
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

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
        .string => |str| try emitLenString(buf, a, str),
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
                    .string => |s| try emitLenString(buf, a, s),
                }
                try serializeValue(ctx, buf, sctx, entry.value);
            }
            try buf.append(a, '}');
        },
        .object => |obj| {
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
            try sctx.objects.put(a, obj, sctx.next_slot - 1);

            // enum: emit E:<len>:"Class:Case"; per PHP 8.1
            if (ctx.vm.classes.get(obj.class_name)) |cdef| {
                if (cdef.is_enum) {
                    const name_val = obj.get("name");
                    const case_name: []const u8 = if (name_val == .string) name_val.string else "";
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
            // a class that declares Serializable but provides no serialize()
            // method (e.g. ArrayObject in PHP 8.4 - the interface is listed for
            // BC but actual serialization goes through the default property path)
            // falls through to default object serialization
            if (!ctx.vm.hasMethod(obj.class_name, "__serialize") and ctx.vm.isInstanceOf(obj.class_name, "Serializable") and ctx.vm.hasMethod(obj.class_name, "serialize")) {
                const ser_result = try ctx.vm.callMethod(obj, "serialize", &.{});
                const payload: []const u8 = if (ser_result == .string) ser_result.string else "";
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
                const ser_result = try ctx.vm.callMethod(obj, "__serialize", &.{});
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
                            .string => |s| try emitLenString(buf, a, s),
                        }
                        try serializeValue(ctx, buf, sctx, entry.value);
                    }
                    try buf.append(a, '}');
                    return;
                }
            }

            // older __sleep: returns string[] of property names to include
            var sleep_props: ?*PhpArray = null;
            if (ctx.vm.hasMethod(obj.class_name, "__sleep")) {
                const sleep_result = try ctx.vm.callMethod(obj, "__sleep", &.{});
                if (sleep_result == .array) sleep_props = sleep_result.array;
            }

            try buf.appendSlice(a, "O:");
            var tmp: [20]u8 = undefined;
            const nl = std.fmt.bufPrint(&tmp, "{d}", .{obj.class_name.len}) catch return;
            try buf.appendSlice(a, nl);
            try buf.appendSlice(a, ":\"");
            try buf.appendSlice(a, obj.class_name);
            try buf.appendSlice(a, "\":");
            var total_count: u32 = 0;
            if (sleep_props) |sp| {
                total_count = @intCast(sp.entries.items.len);
            } else {
                const slot_count: u32 = if (obj.slot_layout) |layout| @intCast(layout.names.len) else 0;
                total_count = slot_count + @as(u32, @intCast(obj.properties.count()));
            }
            const cl = std.fmt.bufPrint(&tmp, "{d}", .{total_count}) catch return;
            try buf.appendSlice(a, cl);
            try buf.appendSlice(a, ":{");

            const class_def = ctx.vm.classes.get(obj.class_name);
            if (sleep_props) |sp| {
                for (sp.entries.items) |entry| {
                    if (entry.value != .string) continue;
                    const name = entry.value.string;
                    const vis: ClassDef.Visibility = if (class_def) |c| findPropertyVisibility(c, name) else .public;
                    try emitObjectPropertyKey(buf, a, obj.class_name, name, vis);
                    const v = obj.get(name);
                    try serializeValue(ctx, buf, sctx, v);
                }
                try buf.append(a, '}');
                return;
            }
            if (obj.slot_layout) |layout| {
                if (obj.slots) |slots| {
                    for (layout.names, 0..) |name, i| {
                        const vis: ClassDef.Visibility = if (class_def) |c| findPropertyVisibility(c, name) else .public;
                        try emitObjectPropertyKey(buf, a, obj.class_name, name, vis);
                        try serializeValue(ctx, buf, sctx, slots[i]);
                    }
                }
            }
            var iter = obj.properties.iterator();
            while (iter.next()) |entry| {
                const k = entry.key_ptr.*;
                // properties in the hashmap are keyed by the bare name (visibility stored on ClassDef),
                // so look up visibility the same way as slot properties
                const vis: ClassDef.Visibility = if (class_def) |c| findPropertyVisibility(c, k) else .public;
                try emitObjectPropertyKey(buf, a, obj.class_name, k, vis);
                try serializeValue(ctx, buf, sctx, entry.value_ptr.*);
            }
            try buf.append(a, '}');
        },
        else => try buf.appendSlice(a, "N;"),
    }
}

fn native_unserialize(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return Value{ .bool = false };
    const s = args[0].string;
    // PHP returns false silently for empty input - no warning
    if (s.len == 0) return Value{ .bool = false };
    var uctx = UnserCtx{};
    defer uctx.deinit(ctx.allocator);
    var name_storage: std.ArrayListUnmanaged([]const u8) = .{};
    defer name_storage.deinit(ctx.allocator);
    if (args.len >= 2 and args[1] == .array) {
        const opts = args[1].array;
        const ac = opts.get(.{ .string = "allowed_classes" });
        switch (ac) {
            .bool => |b| uctx.allowed = if (b) .all else .none,
            .array => |a| {
                for (a.entries.items) |entry| {
                    if (entry.value == .string) try name_storage.append(ctx.allocator, entry.value.string);
                }
                uctx.allowed = .{ .list = name_storage.items };
            },
            else => {},
        }
        const md = opts.get(.{ .string = "max_depth" });
        if (md == .int and md.int >= 0) uctx.max_depth = @intCast(md.int);
    }
    const result = unserializeValue(ctx, &uctx, s, 0) catch {
        if (uctx.threw) return error.RuntimeError;
        // emit PHP's parse-failure warning. depth-exceeded gets its own
        // message that names the option + ini setting; generic parse errors
        // get 'Error at offset N of M bytes'
        if (uctx.depth_exceeded) {
            const msg = std.fmt.allocPrint(ctx.allocator, "unserialize(): Maximum depth of {d} exceeded. The depth limit can be changed using the max_depth unserialize() option or the unserialize_max_depth ini setting", .{uctx.max_depth}) catch return Value{ .bool = false };
            ctx.vm.strings.append(ctx.allocator, msg) catch {};
            ctx.vm.emitWarning(msg);
        }
        const msg2 = std.fmt.allocPrint(ctx.allocator, "unserialize(): Error at offset {d} of {d} bytes", .{ uctx.err_pos, s.len }) catch return Value{ .bool = false };
        ctx.vm.strings.append(ctx.allocator, msg2) catch {};
        ctx.vm.emitWarning(msg2);
        return Value{ .bool = false };
    };
    return result.value;
}

const ParseResult = struct {
    value: Value,
    pos: usize,
};

fn stripVisibilityPrefix(name: []const u8) []const u8 {
    if (name.len > 2 and name[0] == 0) {
        if (std.mem.indexOfScalarPos(u8, name, 1, 0)) |second| {
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
            const v: Value = .{ .string = try ctx.createString(r.str) };
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
                p = key_result.pos;
                uctx.slots.items.len = key_slots_before;

                const val_result = try unserializeValue(ctx, uctx, s, p);
                p = val_result.pos;
                const key: PhpArray.Key = switch (key_result.value) {
                    .int => |i| .{ .int = i },
                    .string => |str| .{ .string = str },
                    else => .{ .int = 0 },
                };
                try arr.set(ctx.allocator, key, val_result.value);
            }
            if (p < s.len and s[p] == '}') p += 1;
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
            const v = def.static_props.get(case_name) orelse return error.RuntimeError;
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
            const class_allowed = uctx.classAllowed(orig_class) and ctx.vm.classes.contains(orig_class);
            const class_name = try ctx.createString(if (class_allowed) orig_class else "__PHP_Incomplete_Class");
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
                try obj.set(ctx.allocator, "__PHP_Incomplete_Class_Name", .{ .string = try ctx.createString(orig_class) });
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
                const arr = try ctx.allocator.create(PhpArray);
                arr.* = .{};
                try ctx.vm.arrays.append(ctx.allocator, arr);
                collected = arr;
            }

            const is_fixed_array = std.mem.eql(u8, class_name, "SplFixedArray");
            var fixed_data: ?*PhpArray = null;
            if (is_fixed_array) {
                const arr = try ctx.allocator.create(PhpArray);
                arr.* = .{};
                try ctx.vm.arrays.append(ctx.allocator, arr);
                fixed_data = arr;
            }
            for (0..prop_count) |_| {
                const key_slots_before = uctx.slots.items.len;
                const key_result = try unserializeValue(ctx, uctx, s, p);
                p = key_result.pos;
                uctx.slots.items.len = key_slots_before;

                const val_result = try unserializeValue(ctx, uctx, s, p);
                p = val_result.pos;
                if (collected) |arr| {
                    const k: PhpArray.Key = switch (key_result.value) {
                        .string => |str| .{ .string = stripVisibilityPrefix(str) },
                        .int => |n| .{ .int = n },
                        else => continue,
                    };
                    try arr.set(ctx.allocator, k, val_result.value);
                } else if (fixed_data) |arr| {
                    if (key_result.value == .int) try arr.set(ctx.allocator, .{ .int = key_result.value.int }, val_result.value);
                } else if (key_result.value == .string) {
                    const stripped = stripVisibilityPrefix(key_result.value.string);
                    // when restoring into a kept class, assigning an
                    // __PHP_Incomplete_Class value to a typed property whose
                    // declared type isn't compatible is a TypeError in PHP
                    if (class_allowed and val_result.value == .object and std.mem.eql(u8, val_result.value.object.class_name, "__PHP_Incomplete_Class")) {
                        const ptype = findPropertyType(ctx.vm, class_name, stripped);
                        if (ptype.len > 0 and !ctx.vm.checkTypeMatch(val_result.value, ptype)) {
                            const msg = try std.fmt.allocPrint(ctx.allocator, "Cannot assign __PHP_Incomplete_Class to property {s}::${s} of type {s}", .{ class_name, stripped, ptype });
                            try ctx.strings.append(ctx.allocator, msg);
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
            if (p < s.len and s[p] == '}') p += 1;

            if (has_unserialize) {
                if (collected) |arr| {
                    _ = try ctx.vm.callMethod(obj, "__unserialize", &.{.{ .array = arr }});
                }
            } else if (ctx.vm.hasMethod(class_name, "__wakeup")) {
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
            const class_allowed = uctx.classAllowed(orig_class) and ctx.vm.classes.contains(orig_class);
            const class_name = try ctx.createString(if (class_allowed) orig_class else "__PHP_Incomplete_Class");
            var p = colon1 + 2 + name_len + 2;
            const len_end = std.mem.indexOfPos(u8, s, p, ":") orelse return error.RuntimeError;
            const data_len = std.fmt.parseInt(usize, s[p..len_end], 10) catch return error.RuntimeError;
            if (len_end + 1 >= s.len or s[len_end + 1] != '{') return error.RuntimeError;
            const data_start = len_end + 2;
            if (data_start + data_len > s.len) return error.RuntimeError;
            const payload = s[data_start .. data_start + data_len];
            p = data_start + data_len;
            if (p < s.len and s[p] == '}') p += 1;

            const obj = try ctx.createObject(class_name);
            const slot_idx = try uctx.reserve(ctx.allocator);
            uctx.store(slot_idx, .{ .object = obj });

            if (class_allowed and ctx.vm.hasMethod(class_name, "unserialize")) {
                const payload_str = try ctx.createString(payload);
                _ = try ctx.vm.callMethod(obj, "unserialize", &.{.{ .string = payload_str }});
            } else if (!class_allowed) {
                try obj.set(ctx.allocator, "__PHP_Incomplete_Class_Name", .{ .string = try ctx.createString(orig_class) });
                try obj.set(ctx.allocator, "__serialized_data", .{ .string = try ctx.createString(payload) });
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
            try uctx.slots.append(ctx.allocator, v);
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

