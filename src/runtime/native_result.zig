const std = @import("std");
const Value = @import("value.zig").Value;

pub const NativeResult = struct {
    value: Value,

    pub fn scalar(value: Value) NativeResult {
        std.debug.assert(value != .string and value != .array and value != .object and value != .generator and value != .fiber);
        return .{ .value = value };
    }

    pub fn borrowed(value: Value) NativeResult {
        std.debug.assert(value != .string);
        return .{ .value = value };
    }

    pub fn share(value: Value) NativeResult {
        if (value == .string) return shareString(value.string);
        return borrowed(value);
    }

    pub fn shareString(value: Value.String) NativeResult {
        value.retain();
        return .{ .value = .{ .string = value } };
    }

    pub fn takeString(value: Value.String) NativeResult {
        std.debug.assert(value.owner != null);
        std.debug.assert(value.owner.?.refcount > 0);
        return .{ .value = .{ .string = value } };
    }

    pub fn copyString(allocator: std.mem.Allocator, bytes: []const u8) !NativeResult {
        return takeString(try Value.String.create(allocator, bytes));
    }

    pub fn literal(comptime bytes: []const u8) NativeResult {
        return .{ .value = .{ .string = Value.String.borrowed(bytes) } };
    }

    // a value the VM handed over with its reference: a result popped off the
    // operand stack (eval) or a freshly minted closure instance. strings keep
    // the reference they arrived with, everything else stays borrowed
    pub fn transfer(value: Value) NativeResult {
        if (value == .string and value.string.owner != null) return takeString(value.string);
        return .{ .value = value };
    }
};

test "shared native strings survive release of their original owner" {
    const source = try Value.String.create(std.testing.allocator, "kept");
    const result = NativeResult.shareString(source);
    source.release();
    defer result.value.string.release();
    try std.testing.expectEqualStrings("kept", result.value.string.bytes());
    try std.testing.expectEqual(@as(usize, 1), result.value.string.owner.?.refcount);
}

test "transferred native strings do not gain another reference" {
    const source = try Value.String.create(std.testing.allocator, "owned");
    const result = NativeResult.takeString(source);
    defer result.value.string.release();
    try std.testing.expectEqual(@as(usize, 1), result.value.string.owner.?.refcount);
}

test "copied native results do not borrow temporary bytes" {
    var bytes = [_]u8{ 'a', 'b' };
    const result = try NativeResult.copyString(std.testing.allocator, &bytes);
    defer result.value.string.release();
    bytes[0] = 'z';
    try std.testing.expectEqualStrings("ab", result.value.string.bytes());
}
