const std = @import("std");

pub const PhpArray = struct {
    entries: std.ArrayListUnmanaged(Entry) = .{},
    next_int_key: i64 = 0,

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
        for (self.entries.items) |entry| {
            if (entry.key.eql(key)) return entry.value;
        }
        return .null;
    }

    pub fn length(self: *const PhpArray) i64 {
        return @intCast(self.entries.items.len);
    }
};

pub const Value = union(enum) {
    null,
    bool: bool,
    int: i64,
    float: f64,
    string: []const u8,
    array: *PhpArray,

    pub fn isTruthy(self: Value) bool {
        return switch (self) {
            .null => false,
            .bool => |b| b,
            .int => |i| i != 0,
            .float => |f| f != 0.0,
            .string => |s| s.len > 0 and !std.mem.eql(u8, s, "0"),
            .array => |a| a.entries.items.len > 0,
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
        return .{ .int = @mod(toInt(a), bi) };
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

    pub fn equal(a: Value, b: Value) bool {
        if (a == .array or b == .array) return false;
        return toFloat(a) == toFloat(b);
    }

    pub fn identical(a: Value, b: Value) bool {
        if (@intFromEnum(a) != @intFromEnum(b)) return false;
        return switch (a) {
            .null => true,
            .bool => |ab| ab == b.bool,
            .int => |ai| ai == b.int,
            .float => |af| af == b.float,
            .string => |as_| std.mem.eql(u8, as_, b.string),
            .array => |ap| ap == b.array,
        };
    }

    pub fn lessThan(a: Value, b: Value) bool {
        if (a == .string and b == .string) {
            return std.mem.order(u8, a.string, b.string) == .lt;
        }
        return toFloat(a) < toFloat(b);
    }

    pub fn compare(a: Value, b: Value) i64 {
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
            .string => |s| std.fmt.parseInt(i64, s, 10) catch 0,
            .array => 0,
        };
    }

    pub fn toFloat(v: Value) f64 {
        return switch (v) {
            .null => 0.0,
            .bool => |b| if (b) 1.0 else 0.0,
            .int => |i| @floatFromInt(i),
            .float => |f| f,
            .string => |s| std.fmt.parseFloat(f64, s) catch 0.0,
            .array => 0.0,
        };
    }

    pub fn toArrayKey(v: Value) PhpArray.Key {
        return switch (v) {
            .int => |i| .{ .int = i },
            .string => |s| .{ .string = s },
            .bool => |b| .{ .int = if (b) 1 else 0 },
            .float => |f| .{ .int = @intFromFloat(f) },
            .null => .{ .int = 0 },
            .array => .{ .int = 0 },
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
                } else {
                    var tmp: [64]u8 = undefined;
                    const s = std.fmt.bufPrint(&tmp, "{d}", .{f}) catch return;
                    try buf.appendSlice(allocator, s);
                }
            },
            .string => |s| try buf.appendSlice(allocator, s),
            .array => try buf.appendSlice(allocator, "Array"),
        }
    }

    const BinOp = enum { add, sub, mul };

    fn numericBinOp(a: Value, b: Value, op: BinOp) Value {
        if (a == .int and b == .int) {
            const ai = a.int;
            const bi = b.int;
            return .{ .int = switch (op) {
                .add => ai +% bi,
                .sub => ai -% bi,
                .mul => ai *% bi,
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
