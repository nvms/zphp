const std = @import("std");
const parser = @import("pipeline/parser.zig");
const compiler = @import("pipeline/compiler.zig");
const VM = @import("runtime/vm.zig").VM;
const CompileResult = @import("pipeline/compiler.zig").CompileResult;

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
    } else if (std.mem.eql(u8, cmd, "serve")) {
        if (args.len < 3) {
            try writeStderr("usage: zphp serve <file> [--port 8080] [--workers N]\n");
            std.process.exit(1);
        }
        var config = @import("serve.zig").ServeConfig{ .file = args[2] };
        var i: usize = 3;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--port") and i + 1 < args.len) {
                config.port = std.fmt.parseInt(u16, args[i + 1], 10) catch 8080;
                i += 1;
            } else if (std.mem.eql(u8, args[i], "--workers") and i + 1 < args.len) {
                config.workers = std.fmt.parseInt(u16, args[i + 1], 10) catch 0;
                i += 1;
            }
        }
        try @import("serve.zig").serve(allocator, config);
    } else if (std.mem.eql(u8, cmd, "test")) {
        const test_path = if (args.len >= 3) args[2] else null;
        try @import("test_runner.zig").run(allocator, test_path);
    } else if (std.mem.eql(u8, cmd, "install")) {
        try @import("pkg.zig").install(allocator);
    } else if (std.mem.eql(u8, cmd, "add")) {
        if (args.len < 3) {
            try writeStderr("usage: zphp add <package>\n");
            std.process.exit(1);
        }
        try @import("pkg.zig").add(allocator, args[2]);
    } else if (std.mem.eql(u8, cmd, "remove")) {
        if (args.len < 3) {
            try writeStderr("usage: zphp remove <package>\n");
            std.process.exit(1);
        }
        try @import("pkg.zig").remove(allocator, args[2]);
    } else if (std.mem.eql(u8, cmd, "packages")) {
        try @import("pkg.zig").packages(allocator);
    } else if (std.mem.eql(u8, cmd, "fmt")) {
        if (args.len < 3) {
            try writeStderr("usage: zphp fmt [--check] <file>...\n");
            std.process.exit(1);
        }
        try @import("fmt.zig").run(allocator, args[2..]);
    } else if (std.mem.eql(u8, cmd, "version") or std.mem.eql(u8, cmd, "--version")) {
        try writeStdout("zphp 0.1.0\n");
    } else {
        try writeStderr("unknown command: ");
        try writeStderr(cmd);
        try writeStderr("\n");
        std.process.exit(1);
    }
}

fn loadFile(path: []const u8, allocator: std.mem.Allocator) ?*CompileResult {
    const source = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024 * 10) catch return null;

    // resolve to absolute path for __FILE__ and __DIR__
    const abs_path = std.fs.cwd().realpathAlloc(allocator, path) catch allocator.dupe(u8, path) catch return null;

    var ast = parser.parse(allocator, source) catch {
        allocator.free(source);
        allocator.free(abs_path);
        return null;
    };

    if (ast.errors.len > 0) {
        ast.deinit();
        allocator.free(source);
        allocator.free(abs_path);
        return null;
    }

    var result = compiler.compileWithPath(&ast, allocator, abs_path) catch {
        ast.deinit();
        allocator.free(source);
        allocator.free(abs_path);
        return null;
    };

    const heap_result = allocator.create(CompileResult) catch {
        result.deinit();
        ast.deinit();
        allocator.free(source);
        return null;
    };
    heap_result.* = result;

    // ast can be freed but source must stay alive - function/variable names
    // in the compiled bytecode reference slices into the source buffer
    ast.deinit();
    // source ownership transfers to the CompileResult's string_allocs
    // so it gets freed when the VM cleans up compile_results
    // source and abs_path must stay alive - compiled bytecode references slices
    // into source, and __DIR__/__FILE__ reference abs_path
    heap_result.string_allocs.append(allocator, source) catch {
        allocator.free(source);
        allocator.free(abs_path);
        heap_result.deinit();
        allocator.destroy(heap_result);
        return null;
    };
    heap_result.string_allocs.append(allocator, abs_path) catch {
        allocator.free(abs_path);
        heap_result.deinit();
        allocator.destroy(heap_result);
        return null;
    };

    return heap_result;
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

    const abs_path = std.fs.cwd().realpathAlloc(allocator, path) catch path;
    defer if (abs_path.ptr != path.ptr) allocator.free(abs_path);

    var result = compiler.compileWithPath(&ast, allocator, abs_path) catch {
        try writeStderr("compile error\n");
        std.process.exit(1);
    };
    defer result.deinit();

    var vm = VM.init(allocator) catch {
        try writeStderr("vm init error\n");
        std.process.exit(1);
    };
    defer vm.deinit();
    vm.file_loader = &loadFile;
    vm.interpret(&result) catch {
        if (vm.output.items.len > 0) {
            try writeStdout(vm.output.items);
        }
        if (vm.error_msg) |msg| {
            try writeStderr(msg);
        } else {
            try writeStderr("runtime error\n");
        }
        std.process.exit(255);
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
    _ = @import("stdlib/exceptions.zig");
    _ = @import("stdlib/registry.zig");
    _ = @import("stdlib/datetime.zig");
    _ = @import("pipeline/parser_tests.zig");
    _ = @import("integration_tests.zig");
    _ = @import("fmt.zig");
    _ = @import("websocket.zig");
}
