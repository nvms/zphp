const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "assert_eq", assertEq },
    .{ "assert_true", assertTrue },
    .{ "assert_false", assertFalse },
    .{ "assert_null", assertNull },
    .{ "assert_not_null", assertNotNull },
    .{ "assert_contains", assertContains },
};

fn failAssertion(ctx: *NativeContext, msg: []const u8) RuntimeError!Value {
    if (try ctx.vm.throwBuiltinException("AssertionError", msg)) return .null;
    ctx.vm.error_msg = msg;
    return error.RuntimeError;
}

fn assertEq(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return failAssertion(ctx, "assert_eq requires 2 arguments");
    if (Value.identical(args[0], args[1])) return .null;

    // build error message
    var buf1 = std.ArrayListUnmanaged(u8){};
    try args[0].format(&buf1, ctx.allocator);
    const s1 = try buf1.toOwnedSlice(ctx.allocator);
    defer ctx.allocator.free(s1);

    var buf2 = std.ArrayListUnmanaged(u8){};
    try args[1].format(&buf2, ctx.allocator);
    const s2 = try buf2.toOwnedSlice(ctx.allocator);
    defer ctx.allocator.free(s2);

    const msg = if (args.len >= 3 and args[2] == .string)
        args[2].string
    else blk: {
        const m = try std.fmt.allocPrint(ctx.allocator, "expected {s}, got {s}", .{ s1, s2 });
        try ctx.strings.append(ctx.allocator, m);
        break :blk m;
    };

    return failAssertion(ctx, msg);
}

fn assertTrue(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return failAssertion(ctx, "assert_true requires 1 argument");
    if (args[0].isTruthy()) return .null;
    const msg = if (args.len >= 2 and args[1] == .string) args[1].string else "expected true, got false";
    return failAssertion(ctx, msg);
}

fn assertFalse(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return failAssertion(ctx, "assert_false requires 1 argument");
    if (!args[0].isTruthy()) return .null;
    const msg = if (args.len >= 2 and args[1] == .string) args[1].string else "expected false, got true";
    return failAssertion(ctx, msg);
}

fn assertNull(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return failAssertion(ctx, "assert_null requires 1 argument");
    if (args[0] == .null) return .null;
    const msg = if (args.len >= 2 and args[1] == .string) args[1].string else "expected null";
    return failAssertion(ctx, msg);
}

fn assertNotNull(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return failAssertion(ctx, "assert_not_null requires 1 argument");
    if (args[0] != .null) return .null;
    const msg = if (args.len >= 2 and args[1] == .string) args[1].string else "expected non-null";
    return failAssertion(ctx, msg);
}

fn assertContains(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return failAssertion(ctx, "assert_contains requires 2 arguments");
    if (args[0] == .string and args[1] == .string) {
        if (std.mem.indexOf(u8, args[0].string, args[1].string) != null) return .null;
    }
    if (args[0] == .array and args.len >= 2) {
        for (args[0].array.entries.items) |entry| {
            if (Value.identical(entry.value, args[1])) return .null;
        }
    }
    const msg = if (args.len >= 3 and args[2] == .string) args[2].string else "value not found in haystack";
    return failAssertion(ctx, msg);
}
