const std = @import("std");
const parser = @import("pipeline/parser.zig");
const compiler = @import("pipeline/compiler.zig");
const CompileResult = compiler.CompileResult;
const VM = @import("runtime/vm.zig").VM;
const ObjFunction = @import("pipeline/bytecode.zig").ObjFunction;
const tui = @import("tui.zig");

const Allocator = std.mem.Allocator;

pub fn run(allocator: Allocator, path: ?[]const u8) !void {
    const start = std.time.milliTimestamp();

    var files = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (files.items) |f| allocator.free(f);
        files.deinit(allocator);
    }

    if (path) |p| {
        try files.append(allocator, try allocator.dupe(u8, p));
    } else {
        try discoverTests(allocator, &files);
    }

    if (files.items.len == 0) {
        tui.warn("no test files found");
        return;
    }

    tui.blank();

    var total_passed: usize = 0;
    var total_failed: usize = 0;
    var total_tests: usize = 0;

    for (files.items) |file| {
        const result = runTestFile(allocator, file);
        total_passed += result.passed;
        total_failed += result.failed;
        total_tests += result.passed + result.failed;
    }

    tui.blank();
    const elapsed: u64 = @intCast(std.time.milliTimestamp() - start);

    if (total_failed == 0) {
        var buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "{d} tests passed", .{total_passed}) catch "?";
        tui.success(msg);
    } else {
        var buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "{d} passed, {d} failed", .{ total_passed, total_failed }) catch "?";
        tui.err(msg);
    }
    tui.timing("ran", elapsed);
    tui.blank();

    if (total_failed > 0) std.process.exit(1);
}

const TestResult = struct { passed: usize, failed: usize };

fn runTestFile(allocator: Allocator, path: []const u8) TestResult {
    var result = TestResult{ .passed = 0, .failed = 0 };

    const source = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024 * 10) catch {
        tui.err(path);
        result.failed = 1;
        return result;
    };
    defer allocator.free(source);

    const abs_path = std.fs.cwd().realpathAlloc(allocator, path) catch allocator.dupe(u8, path) catch {
        result.failed = 1;
        return result;
    };
    defer allocator.free(abs_path);

    var ast = parser.parse(allocator, source) catch {
        tui.err(path);
        result.failed = 1;
        return result;
    };
    defer ast.deinit();

    if (ast.errors.len > 0) {
        tui.err(path);
        result.failed = 1;
        return result;
    }

    var compile_result = compiler.compileWithPath(&ast, allocator, abs_path) catch {
        tui.err(path);
        result.failed = 1;
        return result;
    };
    defer compile_result.deinit();

    // find test_ functions
    var test_fns = std.ArrayListUnmanaged(*const ObjFunction){};
    defer test_fns.deinit(allocator);
    for (compile_result.functions.items) |*func| {
        if (func.name.len > 5 and std.mem.startsWith(u8, func.name, "test_")) {
            test_fns.append(allocator, func) catch continue;
        }
    }

    if (test_fns.items.len == 0) {
        // no test_ functions - run the whole file as a single test
        tui.step("run", path);
        var vm = VM.init(allocator) catch {
            result.failed = 1;
            return result;
        };
        defer vm.deinit();

        vm.interpret(&compile_result) catch {
            printFail(path, if (vm.error_msg) |m| m else "runtime error");
            result.failed = 1;
            return result;
        };
        printPass(path);
        result.passed = 1;
        return result;
    }

    // run each test_ function individually
    tui.step("file", path);
    for (test_fns.items) |func| {
        var vm = VM.init(allocator) catch continue;
        defer vm.deinit();

        // register all functions from the compile result (without executing top-level code)
        for (compile_result.functions.items) |*f| {
            vm.registerFunction(f) catch continue;
        }

        // execute the test function
        vm.frames[0] = .{
            .chunk = &func.chunk,
            .ip = 0,
            .vars = .{},
        };
        vm.frame_count = 1;

        vm.run() catch {
            const err_msg = if (vm.error_msg) |m| m else "assertion failed";
            printFail(func.name, err_msg);
            result.failed += 1;
            continue;
        };

        printPass(func.name);
        result.passed += 1;
    }

    return result;
}

fn printPass(name: []const u8) void {
    tui.write("    ");
    tui.writeColor("\x1b[32m", "pass");
    tui.write("  ");
    tui.write(name);
    tui.write("\n");
}

fn printFail(name: []const u8, msg: []const u8) void {
    tui.write("    ");
    tui.writeColor("\x1b[31m", "FAIL");
    tui.write("  ");
    tui.write(name);
    tui.write("  ");
    tui.writeColor("\x1b[2m", msg);
    tui.write("\n");
}

fn discoverTests(allocator: Allocator, files: *std.ArrayListUnmanaged([]const u8)) !void {
    const dirs = [_][]const u8{ "tests", "test" };
    for (dirs) |dir_name| {
        var dir = std.fs.cwd().openDir(dir_name, .{ .iterate = true }) catch continue;
        defer dir.close();
        try walkDir(allocator, files, dir, dir_name);
    }
}

fn walkDir(allocator: Allocator, files: *std.ArrayListUnmanaged([]const u8), dir: std.fs.Dir, prefix: []const u8) !void {
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const full = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ prefix, entry.name });
        if (entry.kind == .directory) {
            var sub = dir.openDir(entry.name, .{ .iterate = true }) catch {
                allocator.free(full);
                continue;
            };
            defer sub.close();
            try walkDir(allocator, files, sub, full);
            allocator.free(full);
        } else if (entry.kind == .file) {
            if (isTestFile(entry.name)) {
                try files.append(allocator, full);
            } else {
                allocator.free(full);
            }
        } else {
            allocator.free(full);
        }
    }
}

fn isTestFile(name: []const u8) bool {
    if (!std.mem.endsWith(u8, name, ".php")) return false;
    if (std.mem.endsWith(u8, name, "Test.php")) return true;
    if (std.mem.endsWith(u8, name, "_test.php")) return true;
    return false;
}
