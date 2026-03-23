const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "abs", native_abs },
    .{ "floor", native_floor },
    .{ "ceil", native_ceil },
    .{ "round", native_round },
    .{ "min", native_min },
    .{ "max", native_max },
    .{ "rand", native_rand },
};

fn native_abs(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
    return switch (args[0]) {
        .int => |i| .{ .int = if (i < 0) -i else i },
        .float => |f| .{ .float = @abs(f) },
        else => .{ .int = @as(i64, if (Value.toInt(args[0]) < 0) -Value.toInt(args[0]) else Value.toInt(args[0])) },
    };
}

fn native_floor(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 0.0 };
    return .{ .float = @floor(Value.toFloat(args[0])) };
}

fn native_ceil(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 0.0 };
    return .{ .float = @ceil(Value.toFloat(args[0])) };
}

fn native_round(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 0.0 };
    const v = Value.toFloat(args[0]);
    return .{ .float = @round(v) };
}

fn native_min(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .null;
    if (args.len == 1 and args[0] == .array) {
        const arr = args[0].array;
        if (arr.entries.items.len == 0) return .null;
        var result = arr.entries.items[0].value;
        for (arr.entries.items[1..]) |e| {
            if (Value.lessThan(e.value, result)) result = e.value;
        }
        return result;
    }
    var result = args[0];
    for (args[1..]) |a| {
        if (Value.lessThan(a, result)) result = a;
    }
    return result;
}

fn native_max(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .null;
    if (args.len == 1 and args[0] == .array) {
        const arr = args[0].array;
        if (arr.entries.items.len == 0) return .null;
        var result = arr.entries.items[0].value;
        for (arr.entries.items[1..]) |e| {
            if (Value.lessThan(result, e.value)) result = e.value;
        }
        return result;
    }
    var result = args[0];
    for (args[1..]) |a| {
        if (Value.lessThan(result, a)) result = a;
    }
    return result;
}

fn native_rand(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const lo: i64 = if (args.len >= 1) Value.toInt(args[0]) else 0;
    const hi: i64 = if (args.len >= 2) Value.toInt(args[1]) else 2147483647;
    if (lo >= hi) return .{ .int = lo };
    const range: u64 = @intCast(hi - lo + 1);
    const r = std.crypto.random.intRangeAtMost(u64, 0, range - 1);
    return .{ .int = lo + @as(i64, @intCast(r)) };
}
