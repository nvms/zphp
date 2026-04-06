const std = @import("std");
const parser = @import("pipeline/parser.zig");
const compiler = @import("pipeline/compiler.zig");
const VM = @import("runtime/vm.zig").VM;
const CompileResult = @import("pipeline/compiler.zig").CompileResult;
const bytecode_format = @import("bytecode_format.zig");
const error_format = @import("error_format.zig");

const max_source_size = 1024 * 1024 * 10;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (bytecode_format.detectEmbeddedBytecode(allocator)) |bc| {
        defer allocator.free(bc);
        try runBytecode(allocator, bc, args[0], if (args.len > 1) args[1..] else &.{});
        return;
    }

    if (args.len < 2) {
        try writeStdout("zphp 0.5.3\n");
        return;
    }

    try dispatch(allocator, args);
}

fn dispatch(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "run")) {
        try requireArg(args, 3, "usage: zphp run <file>\n");
        try runFile(allocator, args[2], if (args.len > 3) args[3..] else &.{});
    } else if (std.mem.eql(u8, cmd, "serve")) {
        try requireArg(args, 3, "usage: zphp serve <file> [--port 8080] [--workers N] [--watch] [--tls-cert FILE --tls-key FILE]\n");
        var config = @import("serve.zig").ServeConfig{ .file = args[2] };
        var i: usize = 3;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--port") and i + 1 < args.len) {
                config.port = std.fmt.parseInt(u16, args[i + 1], 10) catch 8080;
                i += 1;
            } else if (std.mem.eql(u8, args[i], "--workers") and i + 1 < args.len) {
                config.workers = std.fmt.parseInt(u16, args[i + 1], 10) catch 0;
                i += 1;
            } else if (std.mem.eql(u8, args[i], "--tls-cert") and i + 1 < args.len) {
                config.tls_cert = args[i + 1];
                i += 1;
            } else if (std.mem.eql(u8, args[i], "--tls-key") and i + 1 < args.len) {
                config.tls_key = args[i + 1];
                i += 1;
            } else if (std.mem.eql(u8, args[i], "--watch")) {
                config.watch = true;
            }
        }
        try @import("serve.zig").serve(allocator, config);
    } else if (std.mem.eql(u8, cmd, "test")) {
        try @import("test_runner.zig").run(allocator, if (args.len >= 3) args[2] else null);
    } else if (std.mem.eql(u8, cmd, "install")) {
        try @import("pkg.zig").install(allocator);
    } else if (std.mem.eql(u8, cmd, "add")) {
        try requireArg(args, 3, "usage: zphp add <package>\n");
        try @import("pkg.zig").add(allocator, args[2]);
    } else if (std.mem.eql(u8, cmd, "remove")) {
        try requireArg(args, 3, "usage: zphp remove <package>\n");
        try @import("pkg.zig").remove(allocator, args[2]);
    } else if (std.mem.eql(u8, cmd, "packages")) {
        try @import("pkg.zig").packages(allocator);
    } else if (std.mem.eql(u8, cmd, "fmt")) {
        try requireArg(args, 3, "usage: zphp fmt [--check] <file>...\n");
        try @import("fmt.zig").run(allocator, args[2..]);
    } else if (std.mem.eql(u8, cmd, "build")) {
        try requireArg(args, 3, "usage: zphp build [--compile] <file>\n");
        try buildFile(allocator, args[2..]);
    } else if (std.mem.eql(u8, cmd, "version") or std.mem.eql(u8, cmd, "--version")) {
        try writeStdout("zphp 0.5.3\n");
    } else {
        try writeStderr("unknown command: ");
        try writeStderr(cmd);
        try writeStderr("\n");
        std.process.exit(1);
    }
}

fn requireArg(args: []const []const u8, min: usize, usage: []const u8) !void {
    if (args.len < min) {
        try writeStderr(usage);
        std.process.exit(1);
    }
}

fn compileSource(allocator: std.mem.Allocator, source: []const u8, path: []const u8) !CompileResult {
    var ast = try parser.parse(allocator, source);
    defer ast.deinit();

    if (ast.errors.len > 0) {
        const msg = error_format.formatParseErrors(allocator, &ast, path);
        if (msg.len > 0) {
            try writeStderr(msg);
        } else {
            try writeStderr("parse error\n");
        }
        std.process.exit(1);
    }

    return compiler.compileWithPath(&ast, allocator, path) catch {
        try writeStderr("compile error\n");
        std.process.exit(1);
    };
}

fn readSource(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    return std.fs.cwd().readFileAlloc(allocator, path, max_source_size) catch |err| {
        try writeStderr("error: could not read file '");
        try writeStderr(path);
        try writeStderr("'\n");
        return err;
    };
}

fn resolvePath(allocator: std.mem.Allocator, path: []const u8) []const u8 {
    return std.fs.cwd().realpathAlloc(allocator, path) catch path;
}

fn loadFile(path: []const u8, allocator: std.mem.Allocator) ?*CompileResult {
    const abs_path = std.fs.cwd().realpathAlloc(allocator, path) catch allocator.dupe(u8, path) catch return null;
    const source = std.fs.cwd().readFileAlloc(allocator, abs_path, max_source_size) catch return null;

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
    ast.deinit();

    // source and abs_path must stay alive - compiled bytecode references slices into them
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

const PhpArray = @import("runtime/value.zig").PhpArray;

const env = @import("env.zig");

fn initCliServerVars(vm: *VM, a: std.mem.Allocator) !void {
    const arr = try a.create(PhpArray);
    arr.* = .{};
    try vm.arrays.append(a, arr);

    const entries = .{
        .{ "REQUEST_URI", "/" },
        .{ "SERVER_NAME", "localhost" },
        .{ "SERVER_PORT", "80" },
        .{ "HTTP_HOST", "localhost" },
        .{ "REQUEST_METHOD", "GET" },
        .{ "SCRIPT_NAME", "/" },
        .{ "SCRIPT_FILENAME", "" },
        .{ "DOCUMENT_ROOT", "" },
        .{ "SERVER_PROTOCOL", "HTTP/1.1" },
        .{ "GATEWAY_INTERFACE", "CGI/1.1" },
        .{ "SERVER_SOFTWARE", "zphp" },
        .{ "REMOTE_ADDR", "127.0.0.1" },
        .{ "REQUEST_TIME", "" },
        .{ "argv", "" },
        .{ "argc", "" },
        .{ "PHP_SELF", "/" },
    };
    inline for (entries) |e| {
        try arr.set(a, .{ .string = e[0] }, .{ .string = e[1] });
    }
    try vm.request_vars.put(a, "$_SERVER", .{ .array = arr });

    const superglobal_names = [_][]const u8{ "$_GET", "$_POST", "$_REQUEST", "$_COOKIE", "$_FILES" };
    inline for (superglobal_names) |sg_name| {
        const sg_arr = try a.create(PhpArray);
        sg_arr.* = .{};
        try vm.arrays.append(a, sg_arr);
        try vm.request_vars.put(a, sg_name, .{ .array = sg_arr });
    }
    try env.populateEnvSuperglobal(vm, a, null);
}

fn initArgv(vm: *VM, a: std.mem.Allocator, script_path: []const u8, script_args: []const []const u8) !void {
    const argv_arr = try a.create(PhpArray);
    argv_arr.* = .{};
    try vm.arrays.append(a, argv_arr);

    try argv_arr.append(a, .{ .string = script_path });
    for (script_args) |arg| {
        try argv_arr.append(a, .{ .string = arg });
    }

    try vm.request_vars.put(a, "$argv", .{ .array = argv_arr });
    try vm.request_vars.put(a, "$argc", .{ .int = @intCast(1 + script_args.len) });

    // also update $_SERVER['argv'] and $_SERVER['argc']
    if (vm.request_vars.get("$_SERVER")) |sv| {
        if (sv == .array) {
            try sv.array.set(a, .{ .string = "argv" }, .{ .array = argv_arr });
            try sv.array.set(a, .{ .string = "argc" }, .{ .int = @intCast(1 + script_args.len) });
        }
    }
}

fn runFile(allocator: std.mem.Allocator, path: []const u8, script_args: []const []const u8) !void {
    if (std.mem.endsWith(u8, path, ".zphpc")) {
        const bc = std.fs.cwd().readFileAlloc(allocator, path, 256 * 1024 * 1024) catch |err| {
            try writeStderr("error: could not read file '");
            try writeStderr(path);
            try writeStderr("'\n");
            return err;
        };
        defer allocator.free(bc);
        try runBytecode(allocator, bc, path, script_args);
        return;
    }

    const source = try readSource(allocator, path);
    defer allocator.free(source);

    const abs_path = resolvePath(allocator, path);
    defer if (abs_path.ptr != path.ptr) allocator.free(abs_path);

    var result = try compileSource(allocator, source, abs_path);
    defer result.deinit();

    try runWithVM(allocator, &result, path, script_args);
}

fn runBytecode(allocator: std.mem.Allocator, bc: []const u8, path: []const u8, script_args: []const []const u8) !void {
    var result = bytecode_format.deserialize(allocator, bc) catch {
        try writeStderr("error: invalid bytecode file\n");
        std.process.exit(1);
    };
    defer result.deinit();
    try runWithVM(allocator, &result, path, script_args);
}

fn runWithVM(allocator: std.mem.Allocator, result: *CompileResult, script_path: []const u8, script_args: []const []const u8) !void {
    env.loadEnvFile(allocator);
    const vm = VM.initOnHeap(allocator) catch {
        try writeStderr("vm init error\n");
        std.process.exit(1);
    };
    defer {
        vm.deinit();
        allocator.destroy(vm);
    }
    vm.file_loader = &loadFile;
    try initCliServerVars(vm, allocator);
    try initArgv(vm, allocator, script_path, script_args);
    vm.interpret(result) catch {
        if (vm.output.items.len > 0) try writeStdout(vm.output.items);
        if (vm.exit_requested) std.process.exit(0);
        const msg = error_format.formatRuntimeError(allocator, vm);
        if (msg.len > 0) {
            try writeStderr(msg);
        } else {
            try writeStderr(vm.error_msg orelse "runtime error\n");
        }
        std.process.exit(255);
    };
    if (vm.output.items.len > 0) try writeStdout(vm.output.items);
}

fn buildFile(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var compile_exe = false;
    var file_path: ?[]const u8 = null;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--compile")) {
            compile_exe = true;
        } else {
            file_path = arg;
        }
    }

    const path = file_path orelse {
        try writeStderr("usage: zphp build [--compile] <file>\n");
        std.process.exit(1);
    };

    const source = try readSource(allocator, path);
    defer allocator.free(source);

    const abs_path = resolvePath(allocator, path);
    defer if (abs_path.ptr != path.ptr) allocator.free(abs_path);

    var result = try compileSource(allocator, source, abs_path);
    defer result.deinit();

    const bc = bytecode_format.serialize(allocator, &result) catch {
        try writeStderr("serialization error\n");
        std.process.exit(1);
    };
    defer allocator.free(bc);

    if (compile_exe) {
        const exe_path = std.fs.selfExePathAlloc(allocator) catch {
            try writeStderr("error: could not determine self exe path\n");
            std.process.exit(1);
        };
        defer allocator.free(exe_path);
        const base = std.fs.path.stem(path);
        bytecode_format.appendToExecutable(allocator, exe_path, bc, base) catch {
            try writeStderr("error: could not create executable\n");
            std.process.exit(1);
        };
        try writeStdout("created: ");
        try writeStdout(base);
        try writeStdout("\n");
    } else {
        const base_name = if (std.mem.endsWith(u8, path, ".php")) path[0 .. path.len - 4] else path;
        const out_path = std.fmt.allocPrint(allocator, "{s}.zphpc", .{base_name}) catch std.process.exit(1);
        defer allocator.free(out_path);
        std.fs.cwd().writeFile(.{ .sub_path = out_path, .data = bc }) catch {
            try writeStderr("error: could not write bytecode file\n");
            std.process.exit(1);
        };
        try writeStdout("created: ");
        try writeStdout(out_path);
        try writeStdout("\n");
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
    _ = @import("bytecode_format.zig");
}
