const std = @import("std");
const platform = @import("platform.zig");
const parser = @import("pipeline/parser.zig");
const compiler = @import("pipeline/compiler.zig");
const runtime_value = @import("runtime/value.zig");
const VM = @import("runtime/vm.zig").VM;
const Value = runtime_value.Value;
const CompileResult = @import("pipeline/compiler.zig").CompileResult;
const extension = @import("extension.zig");
const ini_config = @import("ini_config.zig");

comptime {
    if (platform.is_windows) @export(&platform.fcntlStub, .{ .name = "fcntl" });
}
const bytecode_format = @import("bytecode_format.zig");
const error_format = @import("error_format.zig");

const max_source_size = 1024 * 1024 * 64;

// debug builds keep the checked allocator so the test suites report leaks
// and double frees; release builds use the retaining allocator, because the
// checked one hands every freed bucket back to the kernel and string churn
// turns into mmap/munmap
const release_allocator = @import("builtin").mode != .Debug;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (!release_allocator) {
        _ = gpa.deinit();
    };
    const allocator = if (release_allocator) std.heap.smp_allocator else gpa.allocator();

    const raw_args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, raw_args);

    extension.loadStatic();

    if (bytecode_format.detectEmbeddedBytecode(allocator)) |bc| {
        defer allocator.free(bc);
        try runBytecode(allocator, bc, raw_args[0], if (raw_args.len > 1) raw_args[1..] else &.{});
        return;
    }

    const args = try loadStartupFlags(allocator, raw_args);
    defer allocator.free(args);

    if (args.len < 2) {
        try writeStdout("zphp 0.9.0\n");
        return;
    }

    try dispatch(allocator, args);
}

// `zphp [--extension=PATH]... [--ini=PATH] [-d name=value]... <command> ...`
// loads dynamic extensions and the ini file before any VM exists. the ini
// file comes from --ini, ZPHP_INI, or php.ini in the working directory; its
// extension= lines load after the flags, -d definitions apply last, then
// ZPHP_EXTENSION_DIR adds every library in that directory. returns the args
// with the flags removed
fn loadStartupFlags(allocator: std.mem.Allocator, raw_args: []const []const u8) ![]const []const u8 {
    var args = std.ArrayListUnmanaged([]const u8){};
    errdefer args.deinit(allocator);
    var defines = std.ArrayListUnmanaged([]const u8){};
    defer defines.deinit(allocator);
    var ini_path: ?[]const u8 = null;
    try args.append(allocator, raw_args[0]);
    var i: usize = 1;
    while (i < raw_args.len) : (i += 1) {
        const arg = raw_args[i];
        if (std.mem.startsWith(u8, arg, "--extension=")) {
            extension.loadDynamic(arg["--extension=".len..]);
        } else if (std.mem.eql(u8, arg, "--extension")) {
            i += 1;
            extension.loadDynamic(try flagValue(raw_args, i, "usage: zphp --extension=PATH <command>\n"));
        } else if (std.mem.startsWith(u8, arg, "--ini=")) {
            ini_path = arg["--ini=".len..];
        } else if (std.mem.eql(u8, arg, "--ini")) {
            i += 1;
            ini_path = try flagValue(raw_args, i, "usage: zphp --ini=PATH <command>\n");
        } else if (std.mem.startsWith(u8, arg, "-d") and arg.len > 2) {
            try defines.append(allocator, arg[2..]);
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--define")) {
            i += 1;
            try defines.append(allocator, try flagValue(raw_args, i, "usage: zphp -d name=value <command>\n"));
        } else {
            try args.appendSlice(allocator, raw_args[i..]);
            break;
        }
    }
    ini_config.discover(ini_path);
    for (defines.items) |d| ini_config.define(d);
    if (platform.getenv("ZPHP_EXTENSION_DIR")) |dir| extension.loadDirectory(dir);
    return args.toOwnedSlice(allocator);
}

fn flagValue(raw_args: []const []const u8, i: usize, usage: []const u8) ![]const u8 {
    if (i >= raw_args.len) {
        try writeStderr(usage);
        std.process.exit(1);
    }
    return raw_args[i];
}

fn dispatch(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "run")) {
        try requireArg(args, 3, "usage: zphp run <file>\n");
        try runFile(allocator, args[2], if (args.len > 3) args[3..] else &.{});
    } else if (std.mem.eql(u8, cmd, "serve")) {
        try serveCommand(allocator, args);
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
        try writeStdout("zphp 0.9.0\n");
    } else {
        try writeStderr("unknown command: ");
        try writeStderr(cmd);
        try writeStderr("\n");
        std.process.exit(1);
    }
}

fn serveCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
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
        } else if (std.mem.eql(u8, args[i], "--idle-timeout") and i + 1 < args.len) {
            config.idle_timeout_seconds = std.fmt.parseInt(u32, args[i + 1], 10) catch 60;
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

fn dumpProfile(vm: *@import("runtime/vm.zig").VM) void {
    const Entry = struct { name: []const u8, count: u64 };
    const a = vm.allocator;
    var list = std.ArrayListUnmanaged(Entry){};
    defer list.deinit(a);
    var it = vm.profile_calls.iterator();
    while (it.next()) |e| {
        list.append(a, .{ .name = e.key_ptr.*, .count = e.value_ptr.* }) catch return;
    }
    std.sort.heap(Entry, list.items, {}, struct {
        fn lt(_: void, x: Entry, y: Entry) bool {
            return x.count > y.count;
        }
    }.lt);
    const sfe = std.fs.File.stderr();
    _ = sfe.write("[profile] top callees:\n") catch {};
    const n = @min(list.items.len, 30);
    for (list.items[0..n]) |e| {
        const m = std.fmt.allocPrint(a, "  {d: >12} {s}\n", .{ e.count, e.name }) catch return;
        _ = sfe.write(m) catch {};
        a.free(m);
    }
}

const compile_cache_dir = std.fmt.comptimePrint("bytecode-v{d}", .{bytecode_format.FORMAT_VERSION});

fn compileCachePath(allocator: std.mem.Allocator, path: []const u8, stat: std.fs.File.Stat, closure_counter: u32) ![]u8 {
    var digest: [32]u8 = undefined;
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(path);
    hasher.update(std.mem.asBytes(&stat.inode));
    hasher.update(std.mem.asBytes(&stat.size));
    hasher.update(std.mem.asBytes(&stat.mtime));
    hasher.update(std.mem.asBytes(&stat.ctime));
    hasher.update(std.mem.asBytes(&closure_counter));
    hasher.final(&digest);
    const hex = std.fmt.bytesToHex(digest, .lower);
    const cache_root = try compileCacheRoot(allocator);
    return std.fmt.allocPrint(allocator, "{s}/{s}/{s}.zphpc", .{ cache_root, compile_cache_dir, hex });
}

// resolved once per process from the page allocator so the Debug allocator
// does not report a deliberate process-lifetime allocation at exit
var compile_cache_root: ?[]const u8 = null;

fn compileCacheRoot(allocator: std.mem.Allocator) ![]const u8 {
    if (compile_cache_root) |root| return root;
    _ = allocator;
    const root = try std.fs.getAppDataDir(std.heap.page_allocator, "zphp");
    compile_cache_root = root;
    return root;
}

const ResolvedSource = struct { abs_path: []const u8, stat: std.fs.File.Stat };

// a file load used to cost a realpath (open + fcntl + close on macOS) plus
// open + fstat before the bytecode cache was even consulted. directories
// are canonicalized once per process and the file itself gets one lstat;
// a file that is itself a symlink takes the full realpath route
fn resolveSource(allocator: std.mem.Allocator, vm: *VM, path: []const u8) ?ResolvedSource {
    const base = std.fs.path.basename(path);
    if (base.len > 0 and !std.mem.eql(u8, base, ".") and !std.mem.eql(u8, base, "..")) {
        if (realDir(vm, std.fs.path.dirname(path) orelse ".")) |real_dir| {
            const sep: []const u8 = if (std.mem.endsWith(u8, real_dir, "/")) "" else "/";
            const abs = std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ real_dir, sep, base }) catch return null;
            if (platform.is_windows) {
                if (std.fs.cwd().statFile(abs)) |st| {
                    if (st.kind == .file) return .{ .abs_path = abs, .stat = st };
                } else |_| {}
            } else if (std.posix.fstatat(std.posix.AT.FDCWD, abs, std.posix.AT.SYMLINK_NOFOLLOW)) |st| {
                const mode: u32 = @intCast(st.mode);
                if (std.posix.S.ISREG(mode)) return .{ .abs_path = abs, .stat = std.fs.File.Stat.fromPosix(st) };
            } else |_| {}
            allocator.free(abs);
        }
    }
    const abs = std.fs.cwd().realpathAlloc(allocator, path) catch allocator.dupe(u8, path) catch return null;
    const stat = std.fs.cwd().statFile(abs) catch {
        allocator.free(abs);
        return null;
    };
    return .{ .abs_path = abs, .stat = stat };
}

fn realDir(vm: *VM, dir: []const u8) ?[]const u8 {
    if (vm.realdir_cache.get(dir)) |real| return real;
    const real = std.fs.cwd().realpathAlloc(vm.allocator, dir) catch return null;
    const key = vm.allocator.dupe(u8, dir) catch {
        vm.allocator.free(real);
        return null;
    };
    vm.realdir_cache.put(vm.allocator, key, real) catch {
        vm.allocator.free(key);
        vm.allocator.free(real);
        return null;
    };
    return real;
}

fn loadCompileCache(allocator: std.mem.Allocator, path: []const u8, stat: std.fs.File.Stat, closure_counter: u32) ?*CompileResult {
    const cache_path = compileCachePath(allocator, path, stat, closure_counter) catch return null;
    defer allocator.free(cache_path);
    const data = std.fs.cwd().readFileAlloc(allocator, cache_path, 256 * 1024 * 1024) catch return null;
    defer allocator.free(data);
    const result = bytecode_format.deserialize(allocator, data) catch {
        std.fs.cwd().deleteFile(cache_path) catch {};
        return null;
    };
    const heap_result = allocator.create(CompileResult) catch {
        var owned = result;
        owned.deinit();
        return null;
    };
    heap_result.* = result;
    return heap_result;
}

fn saveCompileCache(allocator: std.mem.Allocator, path: []const u8, stat: std.fs.File.Stat, closure_counter: u32, result: *const CompileResult) void {
    const cache_path = compileCachePath(allocator, path, stat, closure_counter) catch return;
    defer allocator.free(cache_path);
    const data = bytecode_format.serialize(allocator, result) catch return;
    defer allocator.free(data);
    var write_buffer: [64 * 1024]u8 = undefined;
    var atomic = std.fs.cwd().atomicFile(cache_path, .{ .make_path = true, .write_buffer = &write_buffer }) catch return;
    defer atomic.deinit();
    atomic.file_writer.interface.writeAll(data) catch return;
    atomic.finish() catch return;
}

fn loadFile(path: []const u8, allocator: std.mem.Allocator, vm: *@import("runtime/vm.zig").VM) ?*CompileResult {
    var abs_path: []const u8 = undefined;
    var source: []const u8 = undefined;
    var source_stat: ?std.fs.File.Stat = null;
    const closure_counter = compiler.closureCounter();

    if (std.mem.startsWith(u8, path, "phar://")) {
        const phar_path = @import("stdlib/phar_path.zig");
        const resolved_phar = phar_path.resolve(path, &vm.phar_aliases) orelse return null;
        const archive = resolved_phar.archive_path;
        const internal = resolved_phar.internal_path;

        const phar_mod = @import("stdlib/phar.zig");
        const PharCacheEntry = @import("runtime/vm.zig").PharCacheEntry;
        // cache parsed phars on the VM so 350+ require_once calls into the
        // same archive (PHPUnit's stub) don't re-read + re-parse every time
        const cached = vm.phar_cache.get(archive);
        var cache_entry: *PharCacheEntry = undefined;
        if (cached) |c| {
            cache_entry = c;
        } else {
            const archive_bytes_owned = std.fs.cwd().readFileAlloc(allocator, archive, 256 * 1024 * 1024) catch return null;
            const parsed = phar_mod.parse(allocator, archive_bytes_owned) catch {
                allocator.free(archive_bytes_owned);
                return null;
            };
            const e = allocator.create(PharCacheEntry) catch {
                allocator.free(archive_bytes_owned);
                var p = parsed;
                p.deinit(allocator);
                return null;
            };
            e.* = .{ .bytes = archive_bytes_owned, .parsed = parsed };
            const archive_key = allocator.dupe(u8, archive) catch {
                allocator.free(archive_bytes_owned);
                var p = parsed;
                p.deinit(allocator);
                allocator.destroy(e);
                return null;
            };
            vm.phar_cache.put(allocator, archive_key, e) catch {
                allocator.free(archive_key);
                allocator.free(archive_bytes_owned);
                var p = parsed;
                p.deinit(allocator);
                allocator.destroy(e);
                return null;
            };
            cache_entry = e;
        }
        const normalized_internal = phar_path.normalizeInternal(allocator, internal) catch return null;
        defer allocator.free(normalized_internal);
        const entry = cache_entry.parsed.lookup(normalized_internal) orelse return null;
        const payload = phar_mod.extract(allocator, &cache_entry.parsed, entry) catch return null;
        source = payload;
        // synthesize a display path so error messages identify the entry inside the phar
        abs_path = std.fmt.allocPrint(allocator, "phar://{s}/{s}", .{ archive, internal }) catch {
            allocator.free(payload);
            return null;
        };
    } else {
        const resolved = resolveSource(allocator, vm, path) orelse return null;
        abs_path = resolved.abs_path;
        const stat = resolved.stat;
        if (loadCompileCache(allocator, abs_path, stat, closure_counter)) |cached| {
            allocator.free(abs_path);
            return cached;
        }
        const file = std.fs.cwd().openFile(abs_path, .{}) catch {
            allocator.free(abs_path);
            return null;
        };
        defer file.close();
        source = file.readToEndAlloc(allocator, max_source_size) catch {
            allocator.free(abs_path);
            return null;
        };
        const read_stat = file.stat() catch {
            allocator.free(source);
            allocator.free(abs_path);
            return null;
        };
        if (stat.inode != read_stat.inode or stat.size != read_stat.size or stat.mtime != read_stat.mtime or stat.ctime != read_stat.ctime) {
            allocator.free(source);
            allocator.free(abs_path);
            return loadFile(path, allocator, vm);
        }
        source_stat = stat;
    }

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

    if (source_stat) |stat| saveCompileCache(allocator, abs_path, stat, closure_counter, heap_result);

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
        try arr.set(a, .{ .string = Value.String.borrowed(e[0]) }, .{ .string = Value.String.borrowed(e[1]) });
    }
    try vm.putRequestVar("$_SERVER", .{ .array = arr });

    const superglobal_names = [_][]const u8{ "$_GET", "$_POST", "$_REQUEST", "$_COOKIE", "$_FILES" };
    inline for (superglobal_names) |sg_name| {
        const sg_arr = try a.create(PhpArray);
        sg_arr.* = .{};
        try vm.arrays.append(a, sg_arr);
        try vm.putRequestVar(sg_name, .{ .array = sg_arr });
    }
    try env.populateEnvSuperglobal(vm, a, null);
}

fn initArgv(vm: *VM, a: std.mem.Allocator, script_path: []const u8, script_args: []const []const u8) !void {
    const argv_arr = try a.create(PhpArray);
    argv_arr.* = .{};
    try vm.arrays.append(a, argv_arr);

    try argv_arr.append(a, .{ .string = Value.String.borrowed(script_path) });
    for (script_args) |arg| {
        try argv_arr.append(a, .{ .string = Value.String.borrowed(arg) });
    }

    try vm.putRequestVar("$argv", .{ .array = argv_arr });
    try vm.putRequestVar("$argc", .{ .int = @intCast(1 + script_args.len) });

    // also update $_SERVER['argv'] and $_SERVER['argc'], plus the script-
    // path keys that CLI PHP populates for the running file
    if (vm.request_vars.get("$_SERVER")) |sv| {
        if (sv == .array) {
            try sv.array.set(a, .{ .string = Value.String.borrowed("argv") }, .{ .array = argv_arr });
            try sv.array.set(a, .{ .string = Value.String.borrowed("argc") }, .{ .int = @intCast(1 + script_args.len) });
            const dup_path = try a.dupe(u8, script_path);
            try vm.strings.append(a, dup_path);
            try sv.array.set(a, .{ .string = Value.String.borrowed("SCRIPT_FILENAME") }, .{ .string = Value.String.borrowed(dup_path) });
            try sv.array.set(a, .{ .string = Value.String.borrowed("SCRIPT_NAME") }, .{ .string = Value.String.borrowed(dup_path) });
            try sv.array.set(a, .{ .string = Value.String.borrowed("PHP_SELF") }, .{ .string = Value.String.borrowed(dup_path) });
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
        var buf: [std.fs.max_path_bytes + 64]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "error: invalid bytecode file '{s}'\n", .{path}) catch
            "error: invalid bytecode file\n";

        try writeStderr(msg);
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
        if (platform.getenv("ZPHP_DBG_PROFILE") != null) dumpProfile(vm);
        vm.deinit();
        allocator.destroy(vm);
    }
    vm.file_loader = &loadFile;
    try initCliServerVars(vm, allocator);
    try initArgv(vm, allocator, script_path, script_args);
    vm.interpret(result) catch {
        if (vm.exit_requested) {
            vm.runShutdownCallbacks() catch {};
            if (vm.output.items.len > 0) try writeStdout(vm.output.items);
            std.process.exit(vm.exit_code);
        }
        // dispatch to user exception handler if one is installed and we have
        // an uncaught exception. handler runs, then we exit 0 unless it
        // threw or the script set a different exit code
        if (vm.pending_exception) |exc| {
            if (vm.user_exception_handler) |handler| {
                vm.user_exception_handler = null; // prevent recursion
                vm.pending_exception = null;
                var ctx = vm.makeContext(null);
                _ = ctx.invokeCallable(handler, &.{exc}) catch {};
                vm.releaseValue(handler);
                vm.runShutdownCallbacks() catch {};
                if (vm.output.items.len > 0) try writeStdout(vm.output.items);
                if (platform.getenv("ZPHP_DBG_PROFILE") != null) dumpProfile(vm);
                if (vm.exit_requested) std.process.exit(vm.exit_code);
                if (vm.pending_exception != null) {
                    const fallback = error_format.formatRuntimeError(allocator, vm);
                    if (fallback.len > 0 and (vm.error_reporting_level & 1) != 0) try writeStderr(fallback);
                    std.process.exit(255);
                }
                return;
            }
        }
        vm.runShutdownCallbacks() catch {};
        if (vm.output.items.len > 0) try writeStdout(vm.output.items);
        if (platform.getenv("ZPHP_DBG_PROFILE") != null) dumpProfile(vm);
        const msg = error_format.formatRuntimeError(allocator, vm);
        if ((vm.error_reporting_level & 1) != 0) {
            if (msg.len > 0) {
                try writeStderr(msg);
            } else {
                try writeStderr(vm.error_msg orelse "runtime error\n");
            }
        }
        std.process.exit(255);
    };
    vm.runShutdownCallbacks() catch {};
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
    try std.fs.File.stdout().writeAll(msg);
}

fn writeStderr(msg: []const u8) !void {
    try std.fs.File.stderr().writeAll(msg);
}

test {
    _ = @import("ini_config.zig");
    _ = @import("pipeline/token.zig");
    _ = @import("pipeline/lexer.zig");
    _ = @import("pipeline/ast.zig");
    _ = @import("pipeline/parser.zig");
    _ = @import("pipeline/bytecode.zig");
    _ = @import("pipeline/compiler.zig");
    _ = @import("runtime/value.zig");
    _ = @import("runtime/native_result.zig");
    _ = @import("runtime/vm.zig");
    _ = @import("stdlib/exceptions.zig");
    _ = @import("stdlib/registry.zig");
    _ = @import("stdlib/datetime.zig");
    _ = @import("stdlib/phar_path.zig");
    _ = @import("serve.zig");
    _ = @import("stdlib/pcre.zig");
    _ = @import("pipeline/parser_tests.zig");
    _ = @import("integration_tests.zig");
    _ = @import("fmt.zig");
    _ = @import("websocket.zig");
    _ = @import("bytecode_format.zig");
}
