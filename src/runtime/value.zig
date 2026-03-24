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

const Chunk = @import("../pipeline/bytecode.zig").Chunk;
const ObjFunction = @import("../pipeline/bytecode.zig").ObjFunction;

pub const Generator = struct {
    state: State = .created,
    func: *const ObjFunction,
    ip: usize = 0,
    vars: std.StringHashMapUnmanaged(Value) = .{},
    stack: std.ArrayListUnmanaged(Value) = .{},
    current_value: Value = .null,
    current_key: Value = .null,
    return_value: Value = .null,
    implicit_key: i64 = 0,
    handler_count: usize = 0,
    delegate: ?DelegateState = null,

    pub const DelegateState = union(enum) {
        gen: *Generator,
        array: struct { arr: *PhpArray, index: usize },
    };

    pub const State = enum { created, suspended, running, completed };

    pub fn deinit(self: *Generator, allocator: std.mem.Allocator) void {
        self.vars.deinit(allocator);
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
        generator: ?*Generator = null,
        ref_bindings: std.ArrayListUnmanaged(RefBinding),
    };

    pub const RefBinding = struct { caller_var: []const u8, param_name: []const u8 };

    pub const SavedHandler = struct {
        catch_ip: usize,
        frame_count_offset: usize,
        sp_offset: usize,
        chunk: *const Chunk,
    };

    pub fn deinit(self: *Fiber, allocator: std.mem.Allocator) void {
        for (self.saved_frames.items) |*f| {
            f.vars.deinit(allocator);
            f.ref_bindings.deinit(allocator);
        }
        self.saved_frames.deinit(allocator);
        self.saved_stack.deinit(allocator);
        self.saved_handlers.deinit(allocator);
    }
};

pub const PhpObject = struct {
    class_name: []const u8,
    properties: std.StringHashMapUnmanaged(Value) = .{},

    pub fn deinit(self: *PhpObject, allocator: std.mem.Allocator) void {
        self.properties.deinit(allocator);
    }

    pub fn get(self: *const PhpObject, name: []const u8) Value {
        return self.properties.get(name) orelse .null;
    }

    pub fn set(self: *PhpObject, allocator: std.mem.Allocator, name: []const u8, value: Value) !void {
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
        if (a == .array or b == .array or a == .object or b == .object or a == .fiber or b == .fiber) return false;
        if (a == .string and b == .string) return std.mem.eql(u8, a.string, b.string);
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
            .string => |s| std.fmt.parseInt(i64, s, 10) catch 0,
            .array, .object, .generator, .fiber => 0,
        };
    }

    pub fn toFloat(v: Value) f64 {
        return switch (v) {
            .null => 0.0,
            .bool => |b| if (b) 1.0 else 0.0,
            .int => |i| @floatFromInt(i),
            .float => |f| f,
            .string => |s| std.fmt.parseFloat(f64, s) catch 0.0,
            .array, .object, .generator, .fiber => 0.0,
        };
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
                } else {
                    // PHP uses 14 significant digits for float display
                    // compute digits before decimal to get correct precision
                    const abs_f = @abs(f);
                    const digits_before: usize = if (abs_f >= 1.0)
                        @as(usize, @intFromFloat(@floor(@log10(abs_f)))) + 1
                    else
                        1;
                    const precision: usize = if (digits_before < 14) 14 - digits_before else 0;
                    var tmp: [64]u8 = undefined;
                    const s = formatFloat(&tmp, f, precision);
                    // strip trailing zeros after decimal point
                    var end: usize = s.len;
                    if (std.mem.indexOf(u8, s, ".")) |_| {
                        while (end > 1 and s[end - 1] == '0') end -= 1;
                        if (end > 0 and s[end - 1] == '.') end -= 1;
                    }
                    try buf.appendSlice(allocator, s[0..end]);
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
        return switch (precision) {
            0 => std.fmt.bufPrint(buf, "{d:.0}", .{f}) catch "0",
            1 => std.fmt.bufPrint(buf, "{d:.1}", .{f}) catch "0",
            2 => std.fmt.bufPrint(buf, "{d:.2}", .{f}) catch "0",
            3 => std.fmt.bufPrint(buf, "{d:.3}", .{f}) catch "0",
            4 => std.fmt.bufPrint(buf, "{d:.4}", .{f}) catch "0",
            5 => std.fmt.bufPrint(buf, "{d:.5}", .{f}) catch "0",
            6 => std.fmt.bufPrint(buf, "{d:.6}", .{f}) catch "0",
            7 => std.fmt.bufPrint(buf, "{d:.7}", .{f}) catch "0",
            8 => std.fmt.bufPrint(buf, "{d:.8}", .{f}) catch "0",
            9 => std.fmt.bufPrint(buf, "{d:.9}", .{f}) catch "0",
            10 => std.fmt.bufPrint(buf, "{d:.10}", .{f}) catch "0",
            11 => std.fmt.bufPrint(buf, "{d:.11}", .{f}) catch "0",
            12 => std.fmt.bufPrint(buf, "{d:.12}", .{f}) catch "0",
            13 => std.fmt.bufPrint(buf, "{d:.13}", .{f}) catch "0",
            else => std.fmt.bufPrint(buf, "{d:.14}", .{f}) catch "0",
        };
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

test "identical" {
    try std.testing.expect(Value.identical(.{ .int = 2 }, .{ .int = 2 }));
    try std.testing.expect(!Value.identical(.{ .int = 1 }, .{ .int = 2 }));
    try std.testing.expect(!Value.identical(.{ .int = 2 }, .{ .string = "2" }));
}
