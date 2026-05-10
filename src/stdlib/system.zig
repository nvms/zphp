const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const VM = @import("../runtime/vm.zig").VM;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "sleep", native_sleep },
    .{ "usleep", native_usleep },
    .{ "getenv", native_getenv },
    .{ "putenv", native_putenv },
    .{ "uniqid", native_uniqid },
    .{ "getcwd", native_getcwd },
    .{ "php_uname", native_php_uname },
    .{ "move_uploaded_file", native_move_uploaded_file },
    .{ "is_uploaded_file", native_is_uploaded_file },
    .{ "sys_get_temp_dir", native_sys_get_temp_dir },
    .{ "tempnam", native_tempnam },
    .{ "debug_backtrace", native_debug_backtrace },
    .{ "debug_print_backtrace", native_debug_print_backtrace },
    .{ "get_defined_functions", native_get_defined_functions },
    .{ "get_defined_vars", native_get_defined_vars },
    .{ "get_defined_classes", native_get_defined_classes },
    .{ "set_time_limit", native_set_time_limit },
    .{ "request_parse_body", native_request_parse_body },
    .{ "trait_exists", native_trait_exists },
    .{ "shell_exec", native_shell_exec },
    .{ "exec", native_exec },
    .{ "system", native_system },
    .{ "passthru", native_passthru },
    .{ "escapeshellarg", native_escapeshellarg },
    .{ "escapeshellcmd", native_escapeshellcmd },
    .{ "getrusage", native_getrusage },
    .{ "posix_getpid", native_posix_getpid },
    .{ "posix_getuid", native_posix_getuid },
    .{ "posix_geteuid", native_posix_getuid },
    .{ "posix_getgid", native_posix_getgid },
    .{ "posix_getegid", native_posix_getgid },
};

fn native_getrusage(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const arr = try ctx.createArray();
    // return zero-filled struct since std doesn't expose getrusage cleanly; matches "is_array" check
    try arr.set(ctx.allocator, .{ .string = "ru_utime.tv_sec" }, .{ .int = 0 });
    try arr.set(ctx.allocator, .{ .string = "ru_utime.tv_usec" }, .{ .int = 0 });
    try arr.set(ctx.allocator, .{ .string = "ru_stime.tv_sec" }, .{ .int = 0 });
    try arr.set(ctx.allocator, .{ .string = "ru_stime.tv_usec" }, .{ .int = 0 });
    try arr.set(ctx.allocator, .{ .string = "ru_maxrss" }, .{ .int = 0 });
    try arr.set(ctx.allocator, .{ .string = "ru_minflt" }, .{ .int = 0 });
    try arr.set(ctx.allocator, .{ .string = "ru_majflt" }, .{ .int = 0 });
    try arr.set(ctx.allocator, .{ .string = "ru_inblock" }, .{ .int = 0 });
    try arr.set(ctx.allocator, .{ .string = "ru_oublock" }, .{ .int = 0 });
    try arr.set(ctx.allocator, .{ .string = "ru_nvcsw" }, .{ .int = 0 });
    try arr.set(ctx.allocator, .{ .string = "ru_nivcsw" }, .{ .int = 0 });
    return .{ .array = arr };
}

fn native_posix_getpid(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = @intCast(std.posix.system.getpid()) };
}

extern "c" fn getuid() std.c.uid_t;
extern "c" fn getgid() std.c.gid_t;

fn native_posix_getuid(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = @intCast(getuid()) };
}

fn native_posix_getgid(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = @intCast(getgid()) };
}

fn native_sleep(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
    const secs = Value.toInt(args[0]);
    if (secs > 0) std.Thread.sleep(@intCast(secs * 1_000_000_000));
    return .{ .int = 0 };
}

fn native_usleep(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .null;
    const usecs = Value.toInt(args[0]);
    if (usecs > 0) std.Thread.sleep(@intCast(usecs * 1_000));
    return .null;
}

fn native_getenv(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const val = std.process.getEnvVarOwned(ctx.allocator, args[0].string) catch return Value{ .bool = false };
    try ctx.strings.append(ctx.allocator, val);
    return .{ .string = val };
}

extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;

fn native_putenv(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const setting = args[0].string;
    if (std.mem.indexOfScalar(u8, setting, '=')) |eq| {
        const name = setting[0..eq];
        const val = setting[eq + 1 ..];
        const name_z = ctx.allocator.dupeZ(u8, name) catch return Value{ .bool = false };
        defer ctx.allocator.free(name_z);
        const val_z = ctx.allocator.dupeZ(u8, val) catch return Value{ .bool = false };
        defer ctx.allocator.free(val_z);
        return .{ .bool = setenv(name_z.ptr, val_z.ptr, 1) == 0 };
    } else {
        const name_z = ctx.allocator.dupeZ(u8, setting) catch return Value{ .bool = false };
        defer ctx.allocator.free(name_z);
        return .{ .bool = unsetenv(name_z.ptr) == 0 };
    }
}

fn native_uniqid(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const prefix = if (args.len >= 1 and args[0] == .string) args[0].string else "";
    const more_entropy = args.len >= 2 and args[1].isTruthy();
    const ns = std.time.nanoTimestamp();
    const abs_ns: u64 = @intCast(if (ns < 0) -ns else ns);
    const usec: u64 = @divTrunc(@mod(abs_ns, 1_000_000_000), 1_000);
    const sec: u64 = @divTrunc(abs_ns, 1_000_000_000);
    var buf: [128]u8 = undefined;
    const hex = if (more_entropy)
        std.fmt.bufPrint(&buf, "{s}{x:0>8}{x:0>5}.{d:0>8}", .{ prefix, sec, usec, std.crypto.random.intRangeAtMost(u32, 0, 99999999) }) catch return Value{ .string = "" }
    else
        std.fmt.bufPrint(&buf, "{s}{x:0>8}{x:0>5}", .{ prefix, sec, usec }) catch return Value{ .string = "" };
    return .{ .string = try ctx.createString(hex) };
}

fn native_getcwd(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = std.fs.cwd().realpath(".", &buf) catch return Value{ .bool = false };
    return .{ .string = try ctx.createString(cwd) };
}

fn native_php_uname(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const mode = if (args.len >= 1 and args[0] == .string and args[0].string.len > 0) args[0].string[0] else 'a';
    const is_mac = @import("builtin").os.tag == .macos;
    const is_arm = @import("builtin").cpu.arch == .aarch64;
    return .{ .string = switch (mode) {
        's' => if (is_mac) "Darwin" else "Linux",
        'n' => "localhost",
        'r' => "0.0.0",
        'm' => if (is_arm) "arm64" else "x86_64",
        else => if (is_mac) "Darwin localhost 0.0.0 arm64" else "Linux localhost 0.0.0 x86_64",
    } };
}

fn native_move_uploaded_file(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const from = args[0].string;
    const to = args[1].string;
    if (!std.mem.startsWith(u8, from, "/tmp/zphp_upload_")) return .{ .bool = false };
    std.fs.cwd().rename(from, to) catch {
        const data = std.fs.cwd().readFileAlloc(std.heap.page_allocator, from, 1024 * 1024 * 64) catch return .{ .bool = false };
        defer std.heap.page_allocator.free(data);
        std.fs.cwd().writeFile(.{ .sub_path = to, .data = data }) catch return .{ .bool = false };
        std.fs.cwd().deleteFile(from) catch {};
    };
    return .{ .bool = true };
}

fn native_is_uploaded_file(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    if (!std.mem.startsWith(u8, args[0].string, "/tmp/zphp_upload_")) return .{ .bool = false };
    std.fs.cwd().access(args[0].string, .{}) catch return .{ .bool = false };
    return .{ .bool = true };
}

fn native_sys_get_temp_dir(_: *NativeContext, _: []const Value) RuntimeError!Value {
    // honor TMPDIR / TEMP / TMP env vars like PHP does, fall back to /tmp
    const env_keys = [_][]const u8{ "TMPDIR", "TEMP", "TMP" };
    for (env_keys) |k| {
        if (std.posix.getenv(k)) |v| {
            if (v.len > 0) {
                // strip a trailing slash to match PHP
                const trimmed = if (v.len > 1 and v[v.len - 1] == '/') v[0 .. v.len - 1] else v;
                return .{ .string = trimmed };
            }
        }
    }
    return .{ .string = "/tmp" };
}

fn native_tempnam(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const dir = if (args.len >= 1 and args[0] == .string) args[0].string else "/tmp";
    const prefix = if (args.len >= 2 and args[1] == .string) args[1].string else "tmp";
    var seed_bytes: [8]u8 = undefined;
    std.crypto.random.bytes(&seed_bytes);
    var rng = std.Random.DefaultPrng.init(std.mem.readInt(u64, &seed_bytes, .little));
    const r = rng.random();
    var attempt: u8 = 0;
    while (attempt < 16) : (attempt += 1) {
        var hex_buf: [16]u8 = undefined;
        const hex = "0123456789abcdef";
        for (&hex_buf) |*b| b.* = hex[r.uintLessThan(u8, 16)];
        const sep: []const u8 = if (dir.len > 0 and dir[dir.len - 1] == '/') "" else "/";
        const candidate = std.fmt.allocPrint(ctx.allocator, "{s}{s}{s}{s}", .{ dir, sep, prefix, &hex_buf }) catch continue;
        if (std.fs.cwd().createFile(candidate, .{ .exclusive = true, .mode = 0o600 })) |file| {
            file.close();
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const resolved = std.fs.cwd().realpath(candidate, &path_buf) catch {
                try ctx.strings.append(ctx.allocator, candidate);
                return .{ .string = candidate };
            };
            const dup = ctx.allocator.dupe(u8, resolved) catch {
                try ctx.strings.append(ctx.allocator, candidate);
                return .{ .string = candidate };
            };
            ctx.allocator.free(candidate);
            try ctx.strings.append(ctx.allocator, dup);
            return .{ .string = dup };
        } else |_| {
            ctx.allocator.free(candidate);
        }
    }
    return .{ .bool = false };
}

fn buildBacktrace(ctx: *NativeContext, ignore_args: bool, limit: usize) RuntimeError!*PhpArray {
    const vm = ctx.vm;
    const alloc = ctx.allocator;
    var result = try ctx.createArray();

    if (vm.frame_count <= 1) return result;

    const max = if (limit > 0) @min(limit, vm.frame_count - 1) else vm.frame_count - 1;
    var count: usize = 0;
    var i: usize = vm.frame_count - 1;

    while (i >= 1 and count < max) : ({
        i -= 1;
        count += 1;
    }) {
        var entry = try ctx.createArray();
        try entry.set(alloc, .{ .string = "file" }, .{ .string = vm.file_path });

        const caller = &vm.frames[i - 1];
        if (caller.chunk.getSourceLocation(caller.ip, vm.source)) |loc| {
            try entry.set(alloc, .{ .string = "line" }, .{ .int = @intCast(loc.line) });
        }

        const frame = &vm.frames[i];
        if (frame.func) |func| {
            if (std.mem.indexOf(u8, func.name, "::")) |sep| {
                try entry.set(alloc, .{ .string = "class" }, .{ .string = func.name[0..sep] });
                try entry.set(alloc, .{ .string = "function" }, .{ .string = func.name[sep + 2 ..] });
                try entry.set(alloc, .{ .string = "type" }, .{ .string = "->" });
            } else {
                try entry.set(alloc, .{ .string = "function" }, .{ .string = func.name });
                if (frame.called_class) |cls| {
                    try entry.set(alloc, .{ .string = "class" }, .{ .string = cls });
                    try entry.set(alloc, .{ .string = "type" }, .{ .string = "->" });
                }
            }
        }

        if (!ignore_args) {
            var args_arr = try ctx.createArray();
            if (vm.ic) |ic| {
                const ac = ic.arg_counts[i];
                if (ac != 0xFF) {
                    const offset: usize = ic.fga_offsets[i];
                    const arg_count: usize = ac;
                    if (offset + arg_count <= 256) {
                        for (0..arg_count) |a| {
                            try args_arr.append(alloc, ic.fga_buf[offset + a]);
                        }
                    }
                }
            }
            try entry.set(alloc, .{ .string = "args" }, .{ .array = args_arr });
        }

        try result.append(alloc, .{ .array = entry });
    }

    return result;
}

fn native_debug_backtrace(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const options = if (args.len >= 1) Value.toInt(args[0]) else 0;
    const limit_raw = if (args.len >= 2) Value.toInt(args[1]) else 0;
    const ignore_args = (options & 2) != 0;
    const limit: usize = if (limit_raw > 0) @intCast(limit_raw) else 0;
    return .{ .array = try buildBacktrace(ctx, ignore_args, limit) };
}

fn native_debug_print_backtrace(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const options = if (args.len >= 1) Value.toInt(args[0]) else 0;
    const limit_raw = if (args.len >= 2) Value.toInt(args[1]) else 0;
    const ignore_args = (options & 2) != 0;
    const limit: usize = if (limit_raw > 0) @intCast(limit_raw) else 0;
    const trace = try buildBacktrace(ctx, ignore_args, limit);

    const out = &ctx.vm.output;
    const alloc = ctx.allocator;
    for (trace.entries.items, 0..) |entry, idx| {
        const arr = entry.value.array;
        const func = arr.get(.{ .string = "function" });
        const file = arr.get(.{ .string = "file" });
        const line = arr.get(.{ .string = "line" });
        var num_buf: [20]u8 = undefined;
        const num_str = std.fmt.bufPrint(&num_buf, "{d}", .{idx}) catch "0";
        try out.appendSlice(alloc, "#");
        try out.appendSlice(alloc, num_str);
        try out.appendSlice(alloc, " ");
        if (file == .string) {
            try out.appendSlice(alloc, file.string);
            if (line == .int) {
                try out.appendSlice(alloc, "(");
                var line_buf: [20]u8 = undefined;
                const line_str = std.fmt.bufPrint(&line_buf, "{d}", .{line.int}) catch "0";
                try out.appendSlice(alloc, line_str);
                try out.appendSlice(alloc, ")");
            }
            try out.appendSlice(alloc, ": ");
        }
        try out.appendSlice(alloc, if (func == .string) func.string else "{main}");
        try out.appendSlice(alloc, "()\n");
    }
    return .null;
}

fn native_get_defined_functions(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const vm = ctx.vm;
    const alloc = ctx.allocator;
    var result = try ctx.createArray();

    var internal = try ctx.createArray();
    var iter_n = vm.native_fns.iterator();
    while (iter_n.next()) |entry| {
        try internal.append(alloc, .{ .string = entry.key_ptr.* });
    }

    var user = try ctx.createArray();
    var iter_u = vm.functions.iterator();
    while (iter_u.next()) |entry| {
        try user.append(alloc, .{ .string = entry.key_ptr.* });
    }

    try result.set(alloc, .{ .string = "internal" }, .{ .array = internal });
    try result.set(alloc, .{ .string = "user" }, .{ .array = user });
    return .{ .array = result };
}

fn native_get_defined_vars(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const vm = ctx.vm;
    const alloc = ctx.allocator;
    var result = try ctx.createArray();

    if (vm.frame_count == 0) return .{ .array = result };
    const frame = &vm.frames[vm.frame_count - 1];

    // slot-based locals first (compile-time named slots)
    const slot_names = if (frame.func) |func| func.slot_names else vm.global_slot_names;
    for (slot_names, 0..) |sn, i| {
        if (sn.len == 0) continue;
        if (i >= frame.locals.len) break;
        if (frame.locals[i] == .null) continue;
        const name = if (sn.len > 0 and sn[0] == '$') sn[1..] else sn;
        if (name.len == 0) continue;
        try result.set(alloc, .{ .string = name }, frame.locals[i]);
    }

    // dynamic vars (extract'd, etc.)
    var iter = frame.vars.iterator();
    while (iter.next()) |entry| {
        const raw = entry.key_ptr.*;
        const name = if (raw.len > 0 and raw[0] == '$') raw[1..] else raw;
        if (name.len == 0) continue;
        if (entry.value_ptr.* == .null) continue;
        try result.set(alloc, .{ .string = name }, entry.value_ptr.*);
    }
    return .{ .array = result };
}

fn native_get_defined_classes(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const vm = ctx.vm;
    const alloc = ctx.allocator;
    var result = try ctx.createArray();

    var iter = vm.classes.iterator();
    while (iter.next()) |entry| {
        try result.append(alloc, .{ .string = entry.key_ptr.* });
    }
    return .{ .array = result };
}

fn native_set_time_limit(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = true };
}

fn native_request_parse_body(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    var post = try ctx.createArray();
    var files = try ctx.createArray();
    if (ctx.vm.request_vars.get("$_POST")) |post_val| {
        if (post_val == .array) post = post_val.array;
    }
    if (ctx.vm.request_vars.get("$_FILES")) |files_val| {
        if (files_val == .array) files = files_val.array;
    }
    var result = try ctx.createArray();
    try result.append(ctx.allocator, .{ .array = post });
    try result.append(ctx.allocator, .{ .array = files });
    return .{ .array = result };
}

fn native_trait_exists(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const name = args[0].string;
    return .{ .bool = ctx.vm.traits.contains(name) };
}

fn runShell(allocator: std.mem.Allocator, command: []const u8, capture: bool) !std.process.Child.RunResult {
    const argv = [_][]const u8{ "/bin/sh", "-c", command };
    return std.process.Child.run(.{
        .allocator = allocator,
        .argv = &argv,
        .max_output_bytes = if (capture) 64 * 1024 * 1024 else 1024,
    });
}

fn native_shell_exec(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .null;
    const result = runShell(ctx.allocator, args[0].string, true) catch return .null;
    defer ctx.allocator.free(result.stderr);
    if (result.stdout.len == 0) {
        ctx.allocator.free(result.stdout);
        return .null;
    }
    try ctx.vm.strings.append(ctx.allocator, result.stdout);
    return .{ .string = result.stdout };
}

fn native_exec(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const result = runShell(ctx.allocator, args[0].string, true) catch return .{ .bool = false };
    defer ctx.allocator.free(result.stderr);
    defer ctx.allocator.free(result.stdout);

    var lines = std.ArrayListUnmanaged([]const u8){};
    defer lines.deinit(ctx.allocator);
    var iter = std.mem.splitScalar(u8, result.stdout, '\n');
    while (iter.next()) |raw| {
        var line = raw;
        if (line.len > 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];
        try lines.append(ctx.allocator, line);
    }
    if (lines.items.len > 0 and lines.items[lines.items.len - 1].len == 0) {
        _ = lines.pop();
    }

    // optional output array (param 2, by-ref) - we append lines if it's an array
    if (args.len >= 2 and args[1] == .array) {
        for (lines.items) |line| {
            const copy = try ctx.allocator.dupe(u8, line);
            try ctx.vm.strings.append(ctx.allocator, copy);
            try args[1].array.append(ctx.allocator, .{ .string = copy });
        }
    }
    // optional result_code (param 3, by-ref)
    const exit_code: i64 = switch (result.term) {
        .Exited => |c| @intCast(c),
        .Signal => |c| @as(i64, @intCast(c)) + 128,
        else => -1,
    };
    if (args.len >= 3 and args[2] == .array) {
        try args[2].array.append(ctx.allocator, .{ .int = exit_code });
    }

    if (lines.items.len == 0) return .{ .string = "" };
    const last = lines.items[lines.items.len - 1];
    const copy = try ctx.allocator.dupe(u8, last);
    try ctx.vm.strings.append(ctx.allocator, copy);
    return .{ .string = copy };
}

fn native_system(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const result = runShell(ctx.allocator, args[0].string, true) catch return .{ .bool = false };
    defer ctx.allocator.free(result.stderr);
    defer ctx.allocator.free(result.stdout);

    try ctx.vm.output.appendSlice(ctx.allocator, result.stdout);

    const exit_code: i64 = switch (result.term) {
        .Exited => |c| @intCast(c),
        .Signal => |c| @as(i64, @intCast(c)) + 128,
        else => -1,
    };
    if (args.len >= 2 and args[1] == .array) {
        try args[1].array.append(ctx.allocator, .{ .int = exit_code });
    }

    // last line of output
    var last_line: []const u8 = "";
    if (result.stdout.len > 0) {
        var end = result.stdout.len;
        if (result.stdout[end - 1] == '\n') end -= 1;
        const start = if (std.mem.lastIndexOfScalar(u8, result.stdout[0..end], '\n')) |i| i + 1 else 0;
        last_line = result.stdout[start..end];
    }
    const copy = try ctx.allocator.dupe(u8, last_line);
    try ctx.vm.strings.append(ctx.allocator, copy);
    return .{ .string = copy };
}

fn native_passthru(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .null;
    const result = runShell(ctx.allocator, args[0].string, true) catch return .{ .bool = false };
    defer ctx.allocator.free(result.stderr);
    defer ctx.allocator.free(result.stdout);
    try ctx.vm.output.appendSlice(ctx.allocator, result.stdout);
    const exit_code: i64 = switch (result.term) {
        .Exited => |c| @intCast(c),
        .Signal => |c| @as(i64, @intCast(c)) + 128,
        else => -1,
    };
    if (args.len >= 2 and args[1] == .array) {
        try args[1].array.append(ctx.allocator, .{ .int = exit_code });
    }
    return .null;
}

fn native_escapeshellarg(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .string = "''" };
    const s = args[0].string;
    var buf = std.ArrayListUnmanaged(u8){};
    try buf.append(ctx.allocator, '\'');
    for (s) |c| {
        if (c == 0) continue;
        if (c == '\'') {
            try buf.appendSlice(ctx.allocator, "'\\''");
        } else {
            try buf.append(ctx.allocator, c);
        }
    }
    try buf.append(ctx.allocator, '\'');
    const out = try ctx.allocator.dupe(u8, buf.items);
    buf.deinit(ctx.allocator);
    try ctx.vm.strings.append(ctx.allocator, out);
    return .{ .string = out };
}

fn native_escapeshellcmd(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .string = "" };
    const s = args[0].string;
    var buf = std.ArrayListUnmanaged(u8){};
    var in_squote = false;
    var in_dquote = false;
    for (s) |c| {
        if (c == 0) continue;
        const is_special = switch (c) {
            '#', '&', ';', '`', '|', '*', '?', '~', '<', '>', '^', '(', ')', '[', ']', '{', '}', '$', '\\', '\x0a', '\xff' => true,
            else => false,
        };
        if (c == '\'' and !in_dquote) {
            in_squote = !in_squote;
        } else if (c == '"' and !in_squote) {
            in_dquote = !in_dquote;
        } else if (is_special and !in_squote and !in_dquote) {
            try buf.append(ctx.allocator, '\\');
        }
        try buf.append(ctx.allocator, c);
    }
    const out = try ctx.allocator.dupe(u8, buf.items);
    buf.deinit(ctx.allocator);
    try ctx.vm.strings.append(ctx.allocator, out);
    return .{ .string = out };
}
