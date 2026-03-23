const std = @import("std");
const parser = @import("pipeline/parser.zig");
const compiler = @import("pipeline/compiler.zig");
const VM = @import("runtime/vm.zig").VM;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try writeStdout("zphp 0.1.0\n");
        return;
    }

    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "run")) {
        if (args.len < 3) {
            try writeStderr("usage: zphp run <file>\n");
            std.process.exit(1);
        }
        try runFile(allocator, args[2]);
    } else if (std.mem.eql(u8, cmd, "version") or std.mem.eql(u8, cmd, "--version")) {
        try writeStdout("zphp 0.1.0\n");
    } else {
        try writeStderr("unknown command: ");
        try writeStderr(cmd);
        try writeStderr("\n");
        std.process.exit(1);
    }
}

fn runFile(allocator: std.mem.Allocator, path: []const u8) !void {
    const source = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024 * 10) catch |err| {
        try writeStderr("error: could not read file '");
        try writeStderr(path);
        try writeStderr("'\n");
        return err;
    };
    defer allocator.free(source);

    var ast = try parser.parse(allocator, source);
    defer ast.deinit();

    if (ast.errors.len > 0) {
        try writeStderr("parse error\n");
        std.process.exit(1);
    }

    var result = compiler.compile(&ast, allocator) catch {
        try writeStderr("compile error\n");
        std.process.exit(1);
    };
    defer result.deinit();

    var vm = VM.init(allocator) catch {
        try writeStderr("vm init error\n");
        std.process.exit(1);
    };
    defer vm.deinit();
    vm.interpret(&result) catch {
        try writeStderr("runtime error\n");
        std.process.exit(1);
    };

    if (vm.output.items.len > 0) {
        try writeStdout(vm.output.items);
    }
}

fn writeStdout(msg: []const u8) !void {
    _ = try std.posix.write(std.posix.STDOUT_FILENO, msg);
}

fn writeStderr(msg: []const u8) !void {
    _ = try std.posix.write(std.posix.STDERR_FILENO, msg);
}

test {
    _ = @import("pipeline/token.zig");
    _ = @import("pipeline/lexer.zig");
    _ = @import("pipeline/ast.zig");
    _ = @import("pipeline/parser.zig");
    _ = @import("pipeline/bytecode.zig");
    _ = @import("pipeline/compiler.zig");
    _ = @import("runtime/value.zig");
    _ = @import("runtime/vm.zig");
    _ = @import("runtime/builtins.zig");
    _ = @import("stdlib/registry.zig");
    _ = @import("pipeline/parser_tests.zig");
    _ = @import("integration_tests.zig");
}
