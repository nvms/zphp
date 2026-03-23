const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("zphp 0.1.0\n", .{});
}

test "placeholder" {
    try std.testing.expect(true);
}
