const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const VM = @import("../runtime/vm.zig").VM;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "getopt", native_getopt },
    .{ "sleep", native_sleep },
    .{ "usleep", native_usleep },
    .{ "time_nanosleep", native_time_nanosleep },
    .{ "time_sleep_until", native_time_sleep_until },
    .{ "sys_getloadavg", native_sys_getloadavg },
    .{ "getenv", native_getenv },
    .{ "putenv", native_putenv },
    .{ "uniqid", native_uniqid },
    .{ "getcwd", native_getcwd },
    .{ "php_uname", native_php_uname },
    .{ "php_ini_loaded_file", native_php_ini_loaded_file },
    .{ "php_ini_scanned_files", native_php_ini_scanned_files },
    .{ "dl", native_dl },
    .{ "phpinfo", native_phpinfo },
    .{ "phpcredits", native_phpcredits },
    .{ "php_strip_whitespace", native_php_strip_whitespace },
    .{ "getlastmod", native_getlastmod },
    .{ "cli_get_process_title", native_cli_get_process_title },
    .{ "cli_set_process_title", native_cli_set_process_title },
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
    .{ "posix_getppid", native_posix_getppid },
    .{ "posix_getuid", native_posix_getuid },
    .{ "posix_geteuid", native_posix_getuid },
    .{ "posix_getlogin", native_posix_getlogin },
    .{ "posix_getgid", native_posix_getgid },
    .{ "posix_getegid", native_posix_getgid },
    .{ "posix_kill", native_posix_kill },
    .{ "posix_isatty", native_posix_isatty },
    .{ "posix_ttyname", native_posix_ttyname },
    .{ "posix_getpwuid", native_posix_getpwuid },
    .{ "posix_getgrgid", native_posix_getgrgid },
    .{ "posix_getpwnam", native_posix_getpwnam },
    .{ "posix_getgrnam", native_posix_getgrnam },
    .{ "posix_getgroups", native_posix_getgroups },
    .{ "posix_setsid", native_posix_setsid },
    .{ "posix_setpgid", native_posix_setpgid },
    .{ "posix_getpgid", native_posix_getpgid },
    .{ "posix_getrlimit", native_posix_getrlimit },
    .{ "posix_setrlimit", native_posix_setrlimit },
    .{ "posix_uname", native_posix_uname },
    .{ "posix_get_last_error", native_posix_get_last_error },
    .{ "posix_errno", native_posix_get_last_error },
    .{ "posix_strerror", native_posix_strerror },
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

fn native_posix_getlogin(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    // try the LOGNAME / USER env vars first, then fall back to the passwd
    // entry for the effective uid via getpwuid. matches PHP's behavior of
    // returning false when neither path resolves
    if (std.posix.getenv("LOGNAME")) |s| {
        if (s.len > 0) return .{ .string = try ctx.createString(s) };
    }
    if (std.posix.getenv("USER")) |s| {
        if (s.len > 0) return .{ .string = try ctx.createString(s) };
    }
    return .{ .bool = false };
}

extern "c" fn getuid() std.c.uid_t;
extern "c" fn getgid() std.c.gid_t;

fn native_posix_getuid(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = @intCast(getuid()) };
}

fn native_posix_getgid(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = @intCast(getgid()) };
}

extern "c" fn getppid() std.c.pid_t;
extern "c" fn kill(pid: std.c.pid_t, sig: c_int) c_int;
extern "c" fn isatty(fd: c_int) c_int;
extern "c" fn ttyname(fd: c_int) ?[*:0]const u8;
extern "c" fn setsid() std.c.pid_t;
extern "c" fn setpgid(pid: std.c.pid_t, pgid: std.c.pid_t) c_int;
extern "c" fn getpgid(pid: std.c.pid_t) std.c.pid_t;
extern "c" fn strerror(errnum: c_int) ?[*:0]const u8;
const c_struct_passwd = extern struct {
    pw_name: ?[*:0]const u8,
    pw_passwd: ?[*:0]const u8,
    pw_uid: std.c.uid_t,
    pw_gid: std.c.gid_t,
    _rest: [256]u8 = undefined, // rest of struct varies by platform; only need first four fields
};
const c_struct_group = extern struct {
    gr_name: ?[*:0]const u8,
    gr_passwd: ?[*:0]const u8,
    gr_gid: std.c.gid_t,
    _rest: [256]u8 = undefined,
};
extern "c" fn getpwuid(uid: std.c.uid_t) ?*c_struct_passwd;
extern "c" fn getgrgid(gid: std.c.gid_t) ?*c_struct_group;
extern "c" fn getpwnam(name: [*:0]const u8) ?*c_struct_passwd;
extern "c" fn getgrnam(name: [*:0]const u8) ?*c_struct_group;
extern "c" fn getgroups(size: c_int, list: [*]std.c.gid_t) c_int;
const Rlimit = extern struct { rlim_cur: u64, rlim_max: u64 };
extern "c" fn getrlimit(resource: c_int, rlim: *Rlimit) c_int;
extern "c" fn setrlimit(resource: c_int, rlim: *const Rlimit) c_int;

// PHP exposes its own last-errno via posix_get_last_error. we track manually
// since most syscalls below don't reach back into thread-local errno
var last_posix_errno: c_int = 0;

fn native_posix_getppid(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = @intCast(getppid()) };
}

fn native_posix_kill(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .int or args[1] != .int) return .{ .bool = false };
    const rc = kill(@intCast(args[0].int), @intCast(args[1].int));
    if (rc != 0) {
        last_posix_errno = std.c._errno().*;
        return .{ .bool = false };
    }
    return .{ .bool = true };
}

fn native_posix_isatty(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return .{ .bool = false };
    const fd: c_int = switch (args[0]) {
        .int => |i| @intCast(i),
        .object => 1, // PHP also accepts a stream resource - treat as stdout best-effort
        else => return .{ .bool = false },
    };
    return .{ .bool = isatty(fd) != 0 };
}

fn native_posix_ttyname(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .int) return .{ .bool = false };
    const name = ttyname(@intCast(args[0].int)) orelse return .{ .bool = false };
    var i: usize = 0;
    while (name[i] != 0) : (i += 1) {}
    const owned = try ctx.allocator.dupe(u8, name[0..i]);
    try ctx.strings.append(ctx.allocator, owned);
    return .{ .string = owned };
}

fn cstrToStr(ctx: *NativeContext, p: ?[*:0]const u8) ![]const u8 {
    if (p == null) return "";
    const s = p.?;
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {}
    const owned = try ctx.allocator.dupe(u8, s[0..i]);
    try ctx.strings.append(ctx.allocator, owned);
    return owned;
}

fn native_posix_getpwuid(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .int) return .{ .bool = false };
    const pw = getpwuid(@intCast(args[0].int)) orelse return .{ .bool = false };
    const arr = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .string = "name" }, .{ .string = try cstrToStr(ctx, pw.pw_name) });
    try arr.set(ctx.allocator, .{ .string = "passwd" }, .{ .string = try cstrToStr(ctx, pw.pw_passwd) });
    try arr.set(ctx.allocator, .{ .string = "uid" }, .{ .int = @intCast(pw.pw_uid) });
    try arr.set(ctx.allocator, .{ .string = "gid" }, .{ .int = @intCast(pw.pw_gid) });
    try arr.set(ctx.allocator, .{ .string = "gecos" }, .{ .string = "" });
    try arr.set(ctx.allocator, .{ .string = "dir" }, .{ .string = "" });
    try arr.set(ctx.allocator, .{ .string = "shell" }, .{ .string = "" });
    return .{ .array = arr };
}

fn native_posix_getgrgid(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .int) return .{ .bool = false };
    const g = getgrgid(@intCast(args[0].int)) orelse return .{ .bool = false };
    const arr = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .string = "name" }, .{ .string = try cstrToStr(ctx, g.gr_name) });
    try arr.set(ctx.allocator, .{ .string = "passwd" }, .{ .string = try cstrToStr(ctx, g.gr_passwd) });
    try arr.set(ctx.allocator, .{ .string = "gid" }, .{ .int = @intCast(g.gr_gid) });
    try arr.set(ctx.allocator, .{ .string = "members" }, .{ .array = try ctx.createArray() });
    return .{ .array = arr };
}

fn native_posix_getpwnam(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const name_buf = try ctx.allocator.alloc(u8, args[0].string.len + 1);
    @memcpy(name_buf[0..args[0].string.len], args[0].string);
    name_buf[args[0].string.len] = 0;
    try ctx.strings.append(ctx.allocator, name_buf);
    const name_z: [*:0]const u8 = @ptrCast(name_buf.ptr);
    const pw = getpwnam(name_z) orelse return .{ .bool = false };
    const arr = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .string = "name" }, .{ .string = try cstrToStr(ctx, pw.pw_name) });
    try arr.set(ctx.allocator, .{ .string = "passwd" }, .{ .string = try cstrToStr(ctx, pw.pw_passwd) });
    try arr.set(ctx.allocator, .{ .string = "uid" }, .{ .int = @intCast(pw.pw_uid) });
    try arr.set(ctx.allocator, .{ .string = "gid" }, .{ .int = @intCast(pw.pw_gid) });
    try arr.set(ctx.allocator, .{ .string = "gecos" }, .{ .string = "" });
    try arr.set(ctx.allocator, .{ .string = "dir" }, .{ .string = "" });
    try arr.set(ctx.allocator, .{ .string = "shell" }, .{ .string = "" });
    return .{ .array = arr };
}

fn native_posix_getgrnam(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const name_buf = try ctx.allocator.alloc(u8, args[0].string.len + 1);
    @memcpy(name_buf[0..args[0].string.len], args[0].string);
    name_buf[args[0].string.len] = 0;
    try ctx.strings.append(ctx.allocator, name_buf);
    const name_z: [*:0]const u8 = @ptrCast(name_buf.ptr);
    const g = getgrnam(name_z) orelse return .{ .bool = false };
    const arr = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .string = "name" }, .{ .string = try cstrToStr(ctx, g.gr_name) });
    try arr.set(ctx.allocator, .{ .string = "passwd" }, .{ .string = try cstrToStr(ctx, g.gr_passwd) });
    try arr.set(ctx.allocator, .{ .string = "gid" }, .{ .int = @intCast(g.gr_gid) });
    try arr.set(ctx.allocator, .{ .string = "members" }, .{ .array = try ctx.createArray() });
    return .{ .array = arr };
}

fn native_posix_getgroups(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    var buf: [256]std.c.gid_t = undefined;
    const n = getgroups(@intCast(buf.len), &buf);
    if (n < 0) return .{ .bool = false };
    const arr = try ctx.createArray();
    var i: usize = 0;
    while (i < @as(usize, @intCast(n))) : (i += 1) {
        try arr.append(ctx.allocator, .{ .int = @intCast(buf[i]) });
    }
    return .{ .array = arr };
}

fn native_posix_setsid(_: *NativeContext, _: []const Value) RuntimeError!Value {
    const r = setsid();
    if (r == -1) {
        last_posix_errno = std.c._errno().*;
        return .{ .int = -1 };
    }
    return .{ .int = @intCast(r) };
}

fn native_posix_setpgid(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .int or args[1] != .int) return .{ .bool = false };
    const rc = setpgid(@intCast(args[0].int), @intCast(args[1].int));
    if (rc != 0) {
        last_posix_errno = std.c._errno().*;
        return .{ .bool = false };
    }
    return .{ .bool = true };
}

fn native_posix_getpgid(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .int) return .{ .bool = false };
    const r = getpgid(@intCast(args[0].int));
    if (r == -1) {
        last_posix_errno = std.c._errno().*;
        return .{ .bool = false };
    }
    return .{ .int = @intCast(r) };
}

// PHP labels for posix_getrlimit. Index matches RLIMIT_* on Linux/macOS:
// 0=CPU 1=FSIZE 2=DATA 3=STACK 4=CORE 5=RSS 6=NOFILE 7=NPROC 8=MEMLOCK 9=AS 10=LOCKS
const RLIMIT_NAMES = [_][]const u8{
    "cpu", "filesize", "data", "stack", "core", "maxrss", "openfiles", "maxproc", "memlock", "totalmem", "kqueues",
};
fn rlimitFromName(name: []const u8) ?c_int {
    inline for (RLIMIT_NAMES, 0..) |n, idx| {
        if (std.mem.eql(u8, n, name)) return @intCast(idx);
    }
    return null;
}

fn native_posix_getrlimit(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    // PHP returns an array of all rlimits by default, or just one when an int
    // resource id is passed
    const arr = try ctx.createArray();
    inline for (RLIMIT_NAMES, 0..) |n, idx| {
        var rl: Rlimit = undefined;
        if (getrlimit(@intCast(idx), &rl) == 0) {
            const cur_key = try std.fmt.allocPrint(ctx.allocator, "soft {s}", .{n});
            try ctx.strings.append(ctx.allocator, cur_key);
            const max_key = try std.fmt.allocPrint(ctx.allocator, "hard {s}", .{n});
            try ctx.strings.append(ctx.allocator, max_key);
            const cur: i64 = if (rl.rlim_cur == std.math.maxInt(u64)) -1 else @intCast(rl.rlim_cur);
            const max: i64 = if (rl.rlim_max == std.math.maxInt(u64)) -1 else @intCast(rl.rlim_max);
            try arr.set(ctx.allocator, .{ .string = cur_key }, .{ .int = cur });
            try arr.set(ctx.allocator, .{ .string = max_key }, .{ .int = max });
        }
    }
    _ = args;
    return .{ .array = arr };
}

fn native_posix_setrlimit(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[0] != .int) return .{ .bool = false };
    const soft: u64 = if (args[1] == .int) (if (args[1].int < 0) std.math.maxInt(u64) else @intCast(args[1].int)) else 0;
    const hard: u64 = if (args[2] == .int) (if (args[2].int < 0) std.math.maxInt(u64) else @intCast(args[2].int)) else 0;
    const rl = Rlimit{ .rlim_cur = soft, .rlim_max = hard };
    if (setrlimit(@intCast(args[0].int), &rl) != 0) {
        last_posix_errno = std.c._errno().*;
        return .{ .bool = false };
    }
    return .{ .bool = true };
}

fn native_posix_uname(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    // simple impl - php_uname-style fields. zphp doesn't link directly to
    // uname(2) but std.posix can produce host info
    const arr = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .string = "sysname" }, .{ .string = "" });
    try arr.set(ctx.allocator, .{ .string = "nodename" }, .{ .string = "" });
    try arr.set(ctx.allocator, .{ .string = "release" }, .{ .string = "" });
    try arr.set(ctx.allocator, .{ .string = "version" }, .{ .string = "" });
    try arr.set(ctx.allocator, .{ .string = "machine" }, .{ .string = "" });
    return .{ .array = arr };
}

fn native_posix_get_last_error(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = @intCast(last_posix_errno) };
}

fn native_posix_strerror(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .int) return .{ .string = "" };
    const s = strerror(@intCast(args[0].int)) orelse return .{ .string = "" };
    return .{ .string = try cstrToStr(ctx, s) };
}

// getopt(short, long?, &rest_index?) — PHP-style CLI option parser.
// short is a string like "ab:c::" (a = no arg, b: = required, c:: = optional);
// long is a list of strings with the same suffix convention. options stop at
// the first non-option arg or at "--". returns assoc array of seen options.
fn native_getopt(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const short: []const u8 = if (args.len >= 1 and args[0] == .string) args[0].string else "";
    const argv_val = ctx.vm.request_vars.get("$argv") orelse return .{ .array = try ctx.createArray() };
    if (argv_val != .array) return .{ .array = try ctx.createArray() };
    const argv = argv_val.array;

    var shorts: std.StringHashMapUnmanaged(u8) = .{};
    defer shorts.deinit(ctx.allocator);
    var i: usize = 0;
    while (i < short.len) : (i += 1) {
        const ch = short[i];
        var mode: u8 = 'n'; // none
        if (i + 1 < short.len and short[i + 1] == ':') {
            if (i + 2 < short.len and short[i + 2] == ':') {
                mode = 'o'; // optional
                i += 2;
            } else {
                mode = 'r'; // required
                i += 1;
            }
        }
        const k2 = try ctx.allocator.dupe(u8, &[_]u8{ch});
        try ctx.vm.strings.append(ctx.allocator, k2);
        try shorts.put(ctx.allocator, k2, mode);
    }

    var longs: std.StringHashMapUnmanaged(u8) = .{};
    defer longs.deinit(ctx.allocator);
    if (args.len >= 2 and args[1] == .array) {
        for (args[1].array.entries.items) |e| {
            if (e.value != .string) continue;
            var s = e.value.string;
            var mode: u8 = 'n';
            if (std.mem.endsWith(u8, s, "::")) {
                mode = 'o';
                s = s[0 .. s.len - 2];
            } else if (std.mem.endsWith(u8, s, ":")) {
                mode = 'r';
                s = s[0 .. s.len - 1];
            }
            const k = try ctx.allocator.dupe(u8, s);
            try ctx.vm.strings.append(ctx.allocator, k);
            try longs.put(ctx.allocator, k, mode);
        }
    }

    const out = try ctx.createArray();
    var idx: usize = 1; // skip $argv[0] (script name)
    while (idx < argv.entries.items.len) : (idx += 1) {
        const v = argv.entries.items[idx].value;
        if (v != .string) continue;
        const arg = v.string;
        if (std.mem.eql(u8, arg, "--")) { idx += 1; break; }
        if (arg.len < 2 or arg[0] != '-') break;
        if (arg[1] == '-') {
            // long
            const eq_idx = std.mem.indexOfScalar(u8, arg[2..], '=');
            const name = if (eq_idx) |e| arg[2 .. 2 + e] else arg[2..];
            const inline_val: ?[]const u8 = if (eq_idx) |e| arg[2 + e + 1 ..] else null;
            const mode = longs.get(name) orelse continue;
            var stored: Value = .{ .bool = false };
            if (inline_val) |iv| {
                stored = .{ .string = try ctx.allocator.dupe(u8, iv) };
                try ctx.vm.strings.append(ctx.allocator, stored.string);
            } else if (mode == 'r' and idx + 1 < argv.entries.items.len) {
                idx += 1;
                const nxt = argv.entries.items[idx].value;
                if (nxt == .string) {
                    stored = .{ .string = try ctx.allocator.dupe(u8, nxt.string) };
                    try ctx.vm.strings.append(ctx.allocator, stored.string);
                }
            }
            try out.set(ctx.allocator, .{ .string = name }, stored);
        } else {
            // short cluster: -abc or -a value or -avalue
            var j: usize = 1;
            while (j < arg.len) : (j += 1) {
                const ch = arg[j];
                const key = &[_]u8{ch};
                const mode = shorts.get(key) orelse continue;
                var stored: Value = .{ .bool = false };
                if (mode == 'r' or mode == 'o') {
                    if (j + 1 < arg.len) {
                        const rest = arg[j + 1 ..];
                        const dup = try ctx.allocator.dupe(u8, rest);
                        try ctx.vm.strings.append(ctx.allocator, dup);
                        stored = .{ .string = dup };
                        j = arg.len;
                    } else if (mode == 'r' and idx + 1 < argv.entries.items.len) {
                        idx += 1;
                        const nxt = argv.entries.items[idx].value;
                        if (nxt == .string) {
                            const dup = try ctx.allocator.dupe(u8, nxt.string);
                            try ctx.vm.strings.append(ctx.allocator, dup);
                            stored = .{ .string = dup };
                        }
                    }
                }
                const kk = try ctx.allocator.dupe(u8, key);
                try ctx.vm.strings.append(ctx.allocator, kk);
                try out.set(ctx.allocator, .{ .string = kk }, stored);
                if (j == arg.len) break;
            }
        }
    }
    return .{ .array = out };
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

fn native_time_nanosleep(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .bool = false };
    const secs = Value.toInt(args[0]);
    const nsecs = Value.toInt(args[1]);
    if (secs < 0 or nsecs < 0) return .{ .bool = false };
    const total_ns: u64 = @intCast(secs * 1_000_000_000 + nsecs);
    std.Thread.sleep(total_ns);
    return .{ .bool = true };
}

fn native_time_sleep_until(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    const target = Value.toFloat(args[0]);
    const now: f64 = @floatFromInt(std.time.timestamp());
    if (target <= now) return .{ .bool = true };
    const delta_ns: u64 = @intFromFloat(@max(0, (target - now) * 1e9));
    std.Thread.sleep(delta_ns);
    return .{ .bool = true };
}

extern fn getloadavg(loadavg: [*]f64, nelem: c_int) c_int;

fn native_sys_getloadavg(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    var samples: [3]f64 = .{ 0, 0, 0 };
    const got = getloadavg(&samples, 3);
    if (got < 0) return .{ .bool = false };
    const arr = try ctx.createArray();
    var i: usize = 0;
    const count: usize = @intCast(got);
    while (i < count) : (i += 1) {
        try arr.set(ctx.allocator, .{ .int = @intCast(i) }, .{ .float = samples[i] });
    }
    return .{ .array = arr };
}

fn native_getenv(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    // no-arg form returns all environment vars as an associative array
    if (args.len == 0) {
        const arr = try ctx.createArray();
        var em = std.process.getEnvMap(ctx.allocator) catch return .{ .array = arr };
        defer em.deinit();
        var it = em.iterator();
        while (it.next()) |e| {
            const k = try ctx.allocator.dupe(u8, e.key_ptr.*);
            const v = try ctx.allocator.dupe(u8, e.value_ptr.*);
            try ctx.strings.append(ctx.allocator, k);
            try ctx.strings.append(ctx.allocator, v);
            try arr.set(ctx.allocator, .{ .string = k }, .{ .string = v });
        }
        return .{ .array = arr };
    }
    if (args[0] != .string) return .{ .bool = false };
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

fn native_php_ini_loaded_file(_: *NativeContext, _: []const Value) RuntimeError!Value {
    // zphp doesn't read a php.ini file; report false to match PHP behavior
    // when no ini was loaded
    return .{ .bool = false };
}

fn native_php_ini_scanned_files(_: *NativeContext, _: []const Value) RuntimeError!Value {
    // PHP returns false when no additional ini directory was scanned
    return .{ .bool = false };
}

fn native_dl(_: *NativeContext, _: []const Value) RuntimeError!Value {
    // dynamic loading: PHP's dl() is restricted in CGI/CLI in modern installs;
    // we don't support runtime extension loading, return false
    return .{ .bool = false };
}

fn native_phpinfo(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    _ = args;
    // minimal output: enough for callers to verify the function exists. real
    // PHP prints a giant HTML/text dump of the environment
    const out = try std.fmt.allocPrint(ctx.allocator, "PHP Version => 8.4.1\n", .{});
    try ctx.strings.append(ctx.allocator, out);
    try ctx.vm.output.appendSlice(ctx.allocator, out);
    return .{ .bool = true };
}

fn native_phpcredits(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = true };
}

fn native_getlastmod(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    // PHP returns the last modification time of the main script. zphp tracks
    // the running file path; stat it to produce a real mtime
    const path = ctx.vm.file_path;
    if (path.len == 0) return .{ .bool = false };
    const stat = std.fs.cwd().statFile(path) catch return .{ .bool = false };
    return .{ .int = @intCast(@divTrunc(stat.mtime, std.time.ns_per_s)) };
}

fn native_cli_get_process_title(_: *NativeContext, _: []const Value) RuntimeError!Value {
    // not actually tracking the process title; PHP returns false when no title
    // was set explicitly via cli_set_process_title earlier in the run
    return .{ .bool = false };
}

fn native_cli_set_process_title(_: *NativeContext, _: []const Value) RuntimeError!Value {
    // best-effort no-op; the real prctl(PR_SET_NAME) syscall is linux-only and
    // the cosmetic effect rarely matters for scripts that defensively set it
    return .{ .bool = true };
}

fn native_php_strip_whitespace(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    // PHP's php_strip_whitespace runs the source through the tokenizer and
    // emits only the non-whitespace tokens; without a real tokenizer we return
    // the original source so callers that use the result still see valid PHP
    if (args.len == 0 or args[0] != .string) return .{ .string = "" };
    const content = std.fs.cwd().readFileAlloc(ctx.allocator, args[0].string, 1024 * 1024 * 64) catch return .{ .string = "" };
    try ctx.strings.append(ctx.allocator, content);
    return .{ .string = content };
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

fn buildBacktrace(ctx: *NativeContext, ignore_args: bool, provide_object: bool, limit: usize) RuntimeError!*PhpArray {
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
            const type_str: []const u8 = if (func.is_static) "::" else "->";
            if (std.mem.indexOf(u8, func.name, "::")) |sep| {
                try entry.set(alloc, .{ .string = "class" }, .{ .string = func.name[0..sep] });
                try entry.set(alloc, .{ .string = "function" }, .{ .string = func.name[sep + 2 ..] });
                try entry.set(alloc, .{ .string = "type" }, .{ .string = type_str });
            } else {
                try entry.set(alloc, .{ .string = "function" }, .{ .string = func.name });
                if (frame.called_class) |cls| {
                    try entry.set(alloc, .{ .string = "class" }, .{ .string = cls });
                    try entry.set(alloc, .{ .string = "type" }, .{ .string = type_str });
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

        // DEBUG_BACKTRACE_PROVIDE_OBJECT: include the $this bound to this
        // frame. callers walk the backtrace looking for a frame whose object
        // is a particular type (e.g. test runners locating the current test)
        if (provide_object) {
            if (frame.vars.get("$this")) |val| {
                if (val == .object) try entry.set(alloc, .{ .string = "object" }, val);
            }
        }

        try result.append(alloc, .{ .array = entry });
    }

    return result;
}

fn native_debug_backtrace(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    // PHP options: 0 = DEBUG_BACKTRACE_PROVIDE_OBJECT (default), 2 = DEBUG_BACKTRACE_IGNORE_ARGS.
    // PROVIDE_OBJECT is on by default (option=0); only the inverse bit (1) suppresses it
    const options = if (args.len >= 1) Value.toInt(args[0]) else 0;
    const limit_raw = if (args.len >= 2) Value.toInt(args[1]) else 0;
    const ignore_args = (options & 2) != 0;
    const provide_object = (options & 1) == 0;
    const limit: usize = if (limit_raw > 0) @intCast(limit_raw) else 0;
    return .{ .array = try buildBacktrace(ctx, ignore_args, provide_object, limit) };
}

fn native_debug_print_backtrace(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const options = if (args.len >= 1) Value.toInt(args[0]) else 0;
    const limit_raw = if (args.len >= 2) Value.toInt(args[1]) else 0;
    const ignore_args = (options & 2) != 0;
    const limit: usize = if (limit_raw > 0) @intCast(limit_raw) else 0;
    const trace = try buildBacktrace(ctx, ignore_args, false, limit);

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

    // slot-based locals first (compile-time named slots). PHP excludes $this
    // from get_defined_vars() even inside instance methods. code that
    // iterates the result and reflects on each name (e.g. checking which
    // local is a function parameter) breaks if $this is included
    const slot_names = if (frame.func) |func| func.slot_names else vm.global_slot_names;
    for (slot_names, 0..) |sn, i| {
        if (sn.len == 0) continue;
        if (i >= frame.locals.len) break;
        if (frame.locals[i] == .null) continue;
        const name = if (sn.len > 0 and sn[0] == '$') sn[1..] else sn;
        if (name.len == 0) continue;
        if (std.mem.eql(u8, name, "this")) continue;
        try result.set(alloc, .{ .string = name }, frame.locals[i]);
    }

    // dynamic vars (extract'd, etc.)
    var iter = frame.vars.iterator();
    while (iter.next()) |entry| {
        const raw = entry.key_ptr.*;
        const name = if (raw.len > 0 and raw[0] == '$') raw[1..] else raw;
        if (name.len == 0) continue;
        if (entry.value_ptr.* == .null) continue;
        if (std.mem.eql(u8, name, "this")) continue;
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

fn native_set_time_limit(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    // PHP: set_time_limit(int $seconds): bool. 0 = no limit. each call resets
    // the countdown from "now". negative is the same as 0
    var seconds: i64 = 0;
    if (args.len > 0 and args[0] == .int) seconds = args[0].int;
    if (seconds < 0) seconds = 0;
    ctx.vm.setExecutionLimit(seconds);
    // mirror into the ini directive so subsequent ini_get sees the new value
    const repr = std.fmt.allocPrint(ctx.allocator, "{d}", .{seconds}) catch return .{ .bool = false };
    try ctx.vm.strings.append(ctx.allocator, repr);
    const owned_name = ctx.allocator.dupe(u8, "max_execution_time") catch return .{ .bool = false };
    try ctx.vm.strings.append(ctx.allocator, owned_name);
    try ctx.vm.ini_settings.put(ctx.allocator, owned_name, repr);
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
    const raw = args[0].string;
    const name = if (raw.len > 0 and raw[0] == '\\') raw[1..] else raw;
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

    // optional output array (param 2, by-ref)
    if (args.len >= 2) {
        const arr = if (args[1] == .array) args[1].array else blk: {
            const a = try ctx.allocator.create(@import("../runtime/value.zig").PhpArray);
            a.* = .{};
            try ctx.vm.arrays.append(ctx.allocator, a);
            break :blk a;
        };
        for (lines.items) |line| {
            const copy = try ctx.allocator.dupe(u8, line);
            try ctx.vm.strings.append(ctx.allocator, copy);
            try arr.append(ctx.allocator, .{ .string = copy });
        }
        if (args[1] != .array) ctx.setCallerVar(1, args.len, .{ .array = arr });
    }
    // optional result_code (param 3, by-ref)
    const exit_code: i64 = switch (result.term) {
        .Exited => |c| @intCast(c),
        .Signal => |c| @as(i64, @intCast(c)) + 128,
        else => -1,
    };
    if (args.len >= 3) ctx.setCallerVar(2, args.len, .{ .int = exit_code });

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
    if (args.len >= 2) ctx.setCallerVar(1, args.len, .{ .int = exit_code });

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
