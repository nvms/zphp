const std = @import("std");

pub fn main() !void {
    _ = try std.posix.write(std.posix.STDOUT_FILENO, "zphp 0.1.0\n");
}

test {
    _ = @import("pipeline/token.zig");
    _ = @import("pipeline/lexer.zig");
    _ = @import("pipeline/ast.zig");
    _ = @import("pipeline/parser.zig");
}
