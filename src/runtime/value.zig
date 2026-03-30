const std = @import("std");

pub const PhpArray = struct {
    entries: std.ArrayListUnmanaged(Entry) = .{},
    next_int_key: i64 = 0,
    cursor: usize = 0,

    pub const Entry = struct {
        key: Key,
        value: Value,
    };

    pub const Key = union(enum) {
        int: i64,
        string: []const u8,

        pub fn eql(a: Key, b: Key) bool {
            if (@intFromEnum(a) != @intFromEnum(b)) return false;
            return switch (a) {
                .int => |ai| ai == b.int,
                .string => |as_| std.mem.eql(u8, as_, b.string),
            };
        }
    };

    pub fn deinit(self: *PhpArray, allocator: std.mem.Allocator) void {
        self.entries.deinit(allocator);
    }

    pub fn append(self: *PhpArray, allocator: std.mem.Allocator, value: Value) !void {
        try self.entries.append(allocator, .{ .key = .{ .int = self.next_int_key }, .value = value });
        self.next_int_key += 1;
    }

    pub fn set(self: *PhpArray, allocator: std.mem.Allocator, key: Key, value: Value) !void {
        if (key == .int) {
            const idx = key.int;
            if (idx >= 0) {
                const uidx: usize = @intCast(idx);
                if (uidx < self.entries.items.len) {
                    const entry = &self.entries.items[uidx];
                    if (entry.key == .int and entry.key.int == idx) {
                        entry.value = value;
                        if (idx >= self.next_int_key) self.next_int_key = idx + 1;
                        return;
                    }
                }
            }
        }
        for (self.entries.items) |*entry| {
            if (entry.key.eql(key)) {
                entry.value = value;
                return;
            }
        }
        try self.entries.append(allocator, .{ .key = key, .value = value });
        if (key == .int and key.int >= self.next_int_key) {
            self.next_int_key = key.int + 1;
        }
    }

    pub fn get(self: *const PhpArray, key: Key) Value {
        if (key == .int) {
            const idx = key.int;
            if (idx >= 0) {
                const uidx: usize = @intCast(idx);
                if (uidx < self.entries.items.len) {
                    const entry = &self.entries.items[uidx];
                    if (entry.key == .int and entry.key.int == idx) return entry.value;
                }
            }
        }
        for (self.entries.items) |entry| {
            if (entry.key.eql(key)) return entry.value;
        }
        return .null;
    }

    pub fn length(self: *const PhpArray) i64 {
        return @intCast(self.entries.items.len);
    }

    pub fn remove(self: *PhpArray, key: Key) void {
        var i: usize = 0;
        while (i < self.entries.items.len) {
            if (self.entries.items[i].key.eql(key)) {
                _ = self.entries.orderedRemove(i);
                return;
            }
            i += 1;
        }
    }
};

const Chunk = @import("../pipeline/bytecode.zig").Chunk;
const ObjFunction = @import("../pipeline/bytecode.zig").ObjFunction;

pub const Generator = struct {
    state: State = .created,
    func: *const ObjFunction,
    ip: usize = 0,
    vars: std.StringHashMapUnmanaged(Value) = .{},
    locals: std.ArrayListUnmanaged(Value) = .{},
    stack: std.ArrayListUnmanaged(Value) = .{},
    base_sp: usize = 0,
    current_value: Value = .null,
    current_key: Value = .null,
    return_value: Value = .null,
    implicit_key: i64 = 0,
    handler_count: usize = 0,
    saved_handlers: [8]SavedHandler = undefined,
    delegate: ?DelegateState = null,

    pub const SavedHandler = struct {
        catch_ip: usize,
        sp_offset: usize,
        chunk: *const Chunk,
    };

    pub const DelegateState = union(enum) {
        gen: *Generator,
        array: struct { arr: *PhpArray, index: usize },
    };

    pub const State = enum { created, suspended, running, completed };

    pub fn deinit(self: *Generator, allocator: std.mem.Allocator) void {
        self.vars.deinit(allocator);
        self.locals.deinit(allocator);
        self.stack.deinit(allocator);
    }
};

pub const Fiber = struct {
    state: State = .created,
    callable: Value = .null,

    saved_frames: std.ArrayListUnmanaged(SavedFrame) = .{},
    saved_stack: std.ArrayListUnmanaged(Value) = .{},
    saved_handlers: std.ArrayListUnmanaged(SavedHandler) = .{},

    suspend_value: Value = .null,
    return_value: Value = .null,

    pub const State = enum { created, running, suspended, terminated };

    pub const SavedFrame = struct {
        chunk: *const Chunk,
        ip: usize,
        vars: std.StringHashMapUnmanaged(Value),
        locals: []Value = &.{},
        generator: ?*Generator = null,
        ref_slots: std.StringHashMapUnmanaged(*Value),
    };

    pub const SavedHandler = struct {
        catch_ip: usize,
        frame_count_offset: usize,
        sp_offset: usize,
        chunk: *const Chunk,
    };

    pub fn deinit(self: *Fiber, allocator: std.mem.Allocator) void {
        for (self.saved_frames.items) |*f| {
            f.vars.deinit(allocator);
            f.ref_slots.deinit(allocator);
            if (f.locals.len > 0) allocator.free(f.locals);
        }
        self.saved_frames.deinit(allocator);
        self.saved_stack.deinit(allocator);
        self.saved_handlers.deinit(allocator);
    }
};

pub const PhpObject = struct {
    class_name: []const u8,
    properties: std.StringHashMapUnmanaged(Value) = .{},
    slots: ?[]Value = null,
    slot_layout: ?*const SlotLayout = null,

    pub const SlotLayout = struct {
        names: []const []const u8,
        defaults: []const Value,
    };

    pub fn deinit(self: *PhpObject, allocator: std.mem.Allocator) void {
        self.properties.deinit(allocator);
        if (self.slots) |s| allocator.free(s);
    }

    pub fn getSlotIndex(self: *const PhpObject, name: []const u8) ?u16 {
        const layout = self.slot_layout orelse return null;
        for (layout.names, 0..) |n, i| {
            if (n.ptr == name.ptr or std.mem.eql(u8, n, name)) return @intCast(i);
        }
        return null;
    }

    pub fn get(self: *const PhpObject, name: []const u8) Value {
        if (self.slots) |s| {
            if (self.getSlotIndex(name)) |idx| return s[idx];
        }
        return self.properties.get(name) orelse .null;
    }

    pub fn set(self: *PhpObject, allocator: std.mem.Allocator, name: []const u8, value: Value) !void {
        if (self.slots) |s| {
            if (self.getSlotIndex(name)) |idx| {
                s[idx] = value;
                return;
            }
        }
        try self.properties.put(allocator, name, value);
    }
};

pub const Value = union(enum) {
    null,
    bool: bool,
    int: i64,
    float: f64,
    string: []const u8,
    array: *PhpArray,
    object: *PhpObject,
    generator: *Generator,
    fiber: *Fiber,

    // sentinel for "default = []" in function params - fillDefaults creates a fresh empty array
    var empty_array_sentinel: PhpArray = .{};
    pub const empty_array_default: Value = .{ .array = &empty_array_sentinel };

    pub fn isEmptyArrayDefault(self: Value) bool {
        return self == .array and self.array == &empty_array_sentinel;
    }

    pub fn isTruthy(self: Value) bool {
        return switch (self) {
            .null => false,
            .bool => |b| b,
            .int => |i| i != 0,
            .float => |f| f != 0.0,
            .string => |s| s.len > 0 and !std.mem.eql(u8, s, "0"),
            .array => |a| a.entries.items.len > 0,
            .object, .generator, .fiber => true,
        };
    }

    pub fn isNull(self: Value) bool {
        return self == .null;
    }

    pub fn add(a: Value, b: Value) Value {
        return numericBinOp(a, b, .add);
    }

    pub fn subtract(a: Value, b: Value) Value {
        return numericBinOp(a, b, .sub);
    }

    pub fn multiply(a: Value, b: Value) Value {
        return numericBinOp(a, b, .mul);
    }

    pub fn divide(a: Value, b: Value) Value {
        const bv = toFloat(b);
        if (bv == 0.0) return .{ .int = 0 };
        const av = toFloat(a);
        const result = av / bv;
        if (result == @trunc(result)) return .{ .int = @intFromFloat(result) };
        return .{ .float = result };
    }

    pub fn modulo(a: Value, b: Value) Value {
        const bi = toInt(b);
        if (bi == 0) return .{ .int = 0 };
        return .{ .int = @rem(toInt(a), bi) };
    }

    pub fn power(a: Value, b: Value) Value {
        return .{ .float = std.math.pow(f64, toFloat(a), toFloat(b)) };
    }

    pub fn negate(self: Value) Value {
        return switch (self) {
            .int => |i| .{ .int = -i },
            .float => |f| .{ .float = -f },
            else => .{ .int = -toInt(self) },
        };
    }

    fn arrayEqual(a: *PhpArray, b: *PhpArray, strict: bool) bool {
        if (a == b) return true;
        if (a.entries.items.len != b.entries.items.len) return false;
        for (a.entries.items, b.entries.items) |ea, eb| {
            if (!ea.key.eql(eb.key)) return false;
            if (strict) {
                if (!identical(ea.value, eb.value)) return false;
            } else {
                if (!equal(ea.value, eb.value)) return false;
            }
        }
        return true;
    }

    pub fn equal(a: Value, b: Value) bool {
        if (a == .object or b == .object or a == .fiber or b == .fiber) return false;
        if (a == .array and b == .array) return arrayEqual(a.array, b.array, false);
        if (a == .array or b == .array) {
            const arr_side = if (a == .array) a else b;
            const other = if (a == .array) b else a;
            if (other == .null) return arr_side.array.length() == 0;
            if (other == .bool) return arr_side.isTruthy() == other.bool;
            return false;
        }
        if (a == .null and b == .null) return true;
        if (a == .null) return !b.isTruthy();
        if (b == .null) return !a.isTruthy();
        if (a == .string and b == .string) return std.mem.eql(u8, a.string, b.string);
        // php 8: int/float vs non-numeric string is always false
        if ((a == .int or a == .float) and b == .string) {
            if (!isNumericString(b.string)) return false;
        }
        if ((b == .int or b == .float) and a == .string) {
            if (!isNumericString(a.string)) return false;
        }
        return toFloat(a) == toFloat(b);
    }

    fn isNumericString(s: []const u8) bool {
        var i: usize = 0;
        while (i < s.len and (s[i] == ' ' or s[i] == '\t' or s[i] == '\n' or s[i] == '\r')) i += 1;
        if (i >= s.len) return false;
        if (s[i] == '-' or s[i] == '+') i += 1;
        if (i >= s.len) return false;
        var has_digit = false;
        while (i < s.len and s[i] >= '0' and s[i] <= '9') { i += 1; has_digit = true; }
        if (i < s.len and s[i] == '.') {
            i += 1;
            while (i < s.len and s[i] >= '0' and s[i] <= '9') { i += 1; has_digit = true; }
        }
        if (i < s.len and (s[i] == 'e' or s[i] == 'E')) {
            i += 1;
            if (i < s.len and (s[i] == '-' or s[i] == '+')) i += 1;
            while (i < s.len and s[i] >= '0' and s[i] <= '9') i += 1;
        }
        while (i < s.len and (s[i] == ' ' or s[i] == '\t' or s[i] == '\n' or s[i] == '\r')) i += 1;
        return has_digit and i == s.len;
    }

    pub fn identical(a: Value, b: Value) bool {
        if (@intFromEnum(a) != @intFromEnum(b)) return false;
        return switch (a) {
            .null => true,
            .bool => |ab| ab == b.bool,
            .int => |ai| ai == b.int,
            .float => |af| af == b.float,
            .string => |as_| std.mem.eql(u8, as_, b.string),
            .array => |ap| arrayEqual(ap, b.array, true),
            .object => |ao| ao == b.object,
            .generator => |ag| ag == b.generator,
            .fiber => |af| af == b.fiber,
        };
    }

    pub fn lessThan(a: Value, b: Value) bool {
        if (a == .object or b == .object or a == .generator or b == .generator or a == .fiber or b == .fiber) return false;
        if (a == .string and b == .string) {
            return std.mem.order(u8, a.string, b.string) == .lt;
        }
        return toFloat(a) < toFloat(b);
    }

    pub fn compare(a: Value, b: Value) i64 {
        if (a == .object or b == .object or a == .generator or b == .generator or a == .fiber or b == .fiber) return 0;
        if (a == .string and b == .string) {
            return switch (std.mem.order(u8, a.string, b.string)) {
                .lt => -1,
                .eq => 0,
                .gt => 1,
            };
        }
        const af = toFloat(a);
        const bf = toFloat(b);
        if (af < bf) return -1;
        if (af > bf) return 1;
        return 0;
    }

    pub fn toInt(v: Value) i64 {
        return switch (v) {
            .null => 0,
            .bool => |b| if (b) @as(i64, 1) else 0,
            .int => |i| i,
            .float => |f| @intFromFloat(f),
            .string => |s| parseLeadingInt(s),
            .array, .object, .generator, .fiber => 0,
        };
    }

    pub fn toFloat(v: Value) f64 {
        return switch (v) {
            .null => 0.0,
            .bool => |b| if (b) 1.0 else 0.0,
            .int => |i| @floatFromInt(i),
            .float => |f| f,
            .string => |s| parseLeadingFloat(s),
            .array, .object, .generator, .fiber => 0.0,
        };
    }

    fn parseLeadingInt(s: []const u8) i64 {
        var i: usize = 0;
        while (i < s.len and (s[i] == ' ' or s[i] == '\t' or s[i] == '\n' or s[i] == '\r')) i += 1;
        if (i >= s.len) return 0;
        var neg = false;
        if (s[i] == '-') { neg = true; i += 1; } else if (s[i] == '+') i += 1;
        if (i >= s.len or s[i] < '0' or s[i] > '9') return 0;
        var result: i64 = 0;
        while (i < s.len and s[i] >= '0' and s[i] <= '9') {
            result = result *% 10 +% @as(i64, s[i] - '0');
            i += 1;
        }
        return if (neg) -result else result;
    }

    fn parseLeadingFloat(s: []const u8) f64 {
        var start: usize = 0;
        while (start < s.len and (s[start] == ' ' or s[start] == '\t' or s[start] == '\n' or s[start] == '\r')) start += 1;
        if (start >= s.len) return 0.0;
        var end = start;
        if (s[end] == '-' or s[end] == '+') end += 1;
        var has_digit = false;
        while (end < s.len and s[end] >= '0' and s[end] <= '9') { end += 1; has_digit = true; }
        if (end < s.len and s[end] == '.') {
            end += 1;
            while (end < s.len and s[end] >= '0' and s[end] <= '9') { end += 1; has_digit = true; }
        }
        if (end < s.len and (s[end] == 'e' or s[end] == 'E')) {
            end += 1;
            if (end < s.len and (s[end] == '-' or s[end] == '+')) end += 1;
            while (end < s.len and s[end] >= '0' and s[end] <= '9') end += 1;
        }
        if (!has_digit) return 0.0;
        return std.fmt.parseFloat(f64, s[start..end]) catch 0.0;
    }

    pub fn toArrayKey(v: Value) PhpArray.Key {
        return switch (v) {
            .int => |i| .{ .int = i },
            .string => |s| .{ .string = s },
            .bool => |b| .{ .int = if (b) 1 else 0 },
            .float => |f| .{ .int = @intFromFloat(f) },
            .null => .{ .int = 0 },
            .array, .object, .generator, .fiber => .{ .int = 0 },
        };
    }

    pub fn format(self: Value, buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator) !void {
        switch (self) {
            .null => {},
            .bool => |b| if (b) try buf.appendSlice(allocator, "1"),
            .int => |i| {
                var tmp: [32]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return;
                try buf.appendSlice(allocator, s);
            },
            .float => |f| {
                if (f == @trunc(f) and @abs(f) < 1e15) {
                    const i: i64 = @intFromFloat(f);
                    var tmp: [32]u8 = undefined;
                    const s = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return;
                    try buf.appendSlice(allocator, s);
                } else if (std.math.isNan(f)) {
                    try buf.appendSlice(allocator, "NAN");
                } else if (std.math.isInf(f)) {
                    if (f < 0) try buf.append(allocator, '-');
                    try buf.appendSlice(allocator, "INF");
                } else {
                    const abs_f = @abs(f);
                    // very small or very large numbers use scientific notation
                    if (abs_f != 0 and (abs_f < 1e-4 or abs_f >= 1e15)) {
                        var tmp: [64]u8 = undefined;
                        const s = formatScientific(&tmp, f);
                        try buf.appendSlice(allocator, s);
                    } else {
                        // PHP uses 14 significant digits
                        const digits_before: usize = if (abs_f >= 1.0)
                            @as(usize, @intFromFloat(@floor(@log10(abs_f)))) + 1
                        else
                            0;
                        const precision: usize = if (digits_before < 14) 14 - digits_before else 0;
                        var tmp: [64]u8 = undefined;
                        const s = formatFloat(&tmp, f, precision);
                        var end: usize = s.len;
                        if (std.mem.indexOf(u8, s, ".")) |_| {
                            while (end > 1 and s[end - 1] == '0') end -= 1;
                            if (end > 0 and s[end - 1] == '.') end -= 1;
                        }
                        try buf.appendSlice(allocator, s[0..end]);
                    }
                }
            },
            .string => |s| try buf.appendSlice(allocator, s),
            .array => try buf.appendSlice(allocator, "Array"),
            .object => try buf.appendSlice(allocator, "Object"),
            .generator => try buf.appendSlice(allocator, ""),
            .fiber => try buf.appendSlice(allocator, ""),
        }
    }

    fn formatFloat(buf: *[64]u8, f: f64, precision: usize) []const u8 {
        const p: u4 = @intCast(@min(precision, 15));
        switch (p) {
            inline 0...15 => |cp| return std.fmt.bufPrint(buf, "{d:." ++ std.fmt.comptimePrint("{d}", .{@min(cp, 14)}) ++ "}", .{f}) catch "0",
        }
    }

    fn formatScientific(buf: *[64]u8, f: f64) []const u8 {
        // PHP format: [-]d.dddE[+-]d+  (uppercase E, 14 significant digits)
        const abs_f = @abs(f);
        const exp: i32 = if (abs_f != 0)
            @intFromFloat(@floor(@log10(abs_f)))
        else
            0;
        const mantissa = f / std.math.pow(f64, 10.0, @floatFromInt(exp));

        // 14 significant digits total, 13 after the decimal in mantissa
        var tmp: [64]u8 = undefined;
        const m = formatFloat(&tmp, @abs(mantissa), 13);

        // strip trailing zeros but keep at least one decimal place
        var end: usize = m.len;
        if (std.mem.indexOf(u8, m, ".")) |dot| {
            while (end > dot + 2 and m[end - 1] == '0') end -= 1;
        }

        const sign: []const u8 = if (f < 0) "-" else "";
        const exp_sign: u8 = if (exp >= 0) '+' else '-';
        const exp_abs: u32 = @intCast(if (exp >= 0) exp else -exp);

        return std.fmt.bufPrint(buf, "{s}{s}E{c}{d}", .{ sign, m[0..end], exp_sign, exp_abs }) catch "0";
    }

    // overflow-safe int arithmetic, promotes to float on overflow
    pub fn intAdd(a: i64, b: i64) Value {
        const r = @addWithOverflow(a, b);
        if (r[1] == 0) return .{ .int = r[0] };
        return .{ .float = @as(f64, @floatFromInt(a)) + @as(f64, @floatFromInt(b)) };
    }
    pub fn intSub(a: i64, b: i64) Value {
        const r = @subWithOverflow(a, b);
        if (r[1] == 0) return .{ .int = r[0] };
        return .{ .float = @as(f64, @floatFromInt(a)) - @as(f64, @floatFromInt(b)) };
    }
    pub fn intMul(a: i64, b: i64) Value {
        const r = @mulWithOverflow(a, b);
        if (r[1] == 0) return .{ .int = r[0] };
        return .{ .float = @as(f64, @floatFromInt(a)) * @as(f64, @floatFromInt(b)) };
    }
    pub fn intInc(a: i64) Value {
        const r = @addWithOverflow(a, @as(i64, 1));
        if (r[1] == 0) return .{ .int = r[0] };
        return .{ .float = @as(f64, @floatFromInt(a)) + 1.0 };
    }
    pub fn intDec(a: i64) Value {
        const r = @subWithOverflow(a, @as(i64, 1));
        if (r[1] == 0) return .{ .int = r[0] };
        return .{ .float = @as(f64, @floatFromInt(a)) - 1.0 };
    }

    const BinOp = enum { add, sub, mul };

    fn numericBinOp(a: Value, b: Value, op: BinOp) Value {
        if (a == .int and b == .int) {
            const ai = a.int;
            const bi = b.int;
            switch (op) {
                .add => {
                    const r = @addWithOverflow(ai, bi);
                    if (r[1] == 0) return .{ .int = r[0] };
                },
                .sub => {
                    const r = @subWithOverflow(ai, bi);
                    if (r[1] == 0) return .{ .int = r[0] };
                },
                .mul => {
                    const r = @mulWithOverflow(ai, bi);
                    if (r[1] == 0) return .{ .int = r[0] };
                },
            }
            // overflow: promote to float
            const af: f64 = @floatFromInt(ai);
            const bf: f64 = @floatFromInt(bi);
            return .{ .float = switch (op) {
                .add => af + bf,
                .sub => af - bf,
                .mul => af * bf,
            } };
        }
        const af = toFloat(a);
        const bf = toFloat(b);
        return .{ .float = switch (op) {
            .add => af + bf,
            .sub => af - bf,
            .mul => af * bf,
        } };
    }
};

test "truthiness" {
    try std.testing.expect(!Value.isTruthy(.null));
    try std.testing.expect(!Value.isTruthy(.{ .bool = false }));
    try std.testing.expect(Value.isTruthy(.{ .bool = true }));
    try std.testing.expect(!Value.isTruthy(.{ .int = 0 }));
    try std.testing.expect(Value.isTruthy(.{ .int = 1 }));
    try std.testing.expect(!Value.isTruthy(.{ .string = "" }));
    try std.testing.expect(!Value.isTruthy(.{ .string = "0" }));
    try std.testing.expect(Value.isTruthy(.{ .string = "hello" }));
}

test "arithmetic" {
    const a = Value{ .int = 10 };
    const b = Value{ .int = 3 };
    try std.testing.expectEqual(@as(i64, 13), Value.add(a, b).int);
    try std.testing.expectEqual(@as(i64, 7), Value.subtract(a, b).int);
    try std.testing.expectEqual(@as(i64, 30), Value.multiply(a, b).int);
}

test "int float promotion" {
    const a = Value{ .int = 3 };
    const b = Value{ .float = 1.5 };
    try std.testing.expectEqual(@as(f64, 4.5), Value.add(a, b).float);
}

test "identical" {
    try std.testing.expect(Value.identical(.{ .int = 2 }, .{ .int = 2 }));
    try std.testing.expect(!Value.identical(.{ .int = 1 }, .{ .int = 2 }));
    try std.testing.expect(!Value.identical(.{ .int = 2 }, .{ .string = "2" }));
}
