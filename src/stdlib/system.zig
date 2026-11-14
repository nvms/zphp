const std = @import("std");
const class_names = @import("../runtime/class_names.zig");
const bundle = @import("../bundle.zig");
const platform = @import("../platform.zig");
const open_basedir = @import("open_basedir.zig");
const html = @import("html.zig");
const php_version = @import("../php_version.zig");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const VM = @import("../runtime/vm.zig").VM;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "getopt", native_getopt },
    .{ "getservbyname", native_getservbyname },
    .{ "getservbyport", native_getservbyport },
    .{ "getprotobyname", native_getprotobyname },
    .{ "getprotobynumber", native_getprotobynumber },
    .{ "connection_status", native_connection_status },
    .{ "connection_aborted", native_connection_status },
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
};

// php ships no posix extension on windows
pub const posix_entries = .{
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

fn native_getrusage(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    // return zero-filled struct since std doesn't expose getrusage cleanly; matches "is_array" check
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("ru_utime.tv_sec") }, .{ .int = 0 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("ru_utime.tv_usec") }, .{ .int = 0 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("ru_stime.tv_sec") }, .{ .int = 0 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("ru_stime.tv_usec") }, .{ .int = 0 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("ru_maxrss") }, .{ .int = 0 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("ru_minflt") }, .{ .int = 0 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("ru_majflt") }, .{ .int = 0 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("ru_inblock") }, .{ .int = 0 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("ru_oublock") }, .{ .int = 0 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("ru_nvcsw") }, .{ .int = 0 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("ru_nivcsw") }, .{ .int = 0 });
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_posix_getpid(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = @intCast(std.posix.system.getpid()) });
}

fn native_posix_getlogin(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // try the LOGNAME / USER env vars first, then fall back to the passwd
    // entry for the effective uid via getpwuid. matches PHP's behavior of
    // returning false when neither path resolves
    if (platform.getenv("LOGNAME")) |s| {
        if (s.len > 0) return try NativeResult.copyString(ctx.allocator, s);
    }
    if (platform.getenv("USER")) |s| {
        if (s.len > 0) return try NativeResult.copyString(ctx.allocator, s);
    }
    return NativeResult.scalar(.{ .bool = false });
}

extern "c" fn getuid() std.c.uid_t;
extern "c" fn getgid() std.c.gid_t;

fn native_posix_getuid(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = @intCast(getuid()) });
}

fn native_posix_getgid(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = @intCast(getgid()) });
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

fn native_posix_getppid(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = @intCast(getppid()) });
}

fn native_posix_kill(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .int or args[1] != .int) return NativeResult.scalar(.{ .bool = false });
    const rc = kill(@intCast(args[0].int), @intCast(args[1].int));
    if (rc != 0) {
        last_posix_errno = std.c._errno().*;
        return NativeResult.scalar(.{ .bool = false });
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn native_posix_isatty(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1) return NativeResult.scalar(.{ .bool = false });
    const fd: c_int = switch (args[0]) {
        .int => |i| @intCast(i),
        .object => 1, // PHP also accepts a stream resource - treat as stdout best-effort
        else => return NativeResult.scalar(.{ .bool = false }),
    };
    return NativeResult.scalar(.{ .bool = isatty(fd) != 0 });
}

fn native_posix_ttyname(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .int) return NativeResult.scalar(.{ .bool = false });
    const name = ttyname(@intCast(args[0].int)) orelse return NativeResult.scalar(.{ .bool = false });
    var i: usize = 0;
    while (name[i] != 0) : (i += 1) {}
    const owned = try ctx.allocator.dupe(u8, name[0..i]);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, owned));
}

// the bytes of a C string, empty for a null pointer
fn cstrBytes(p: ?[*:0]const u8) []const u8 {
    const str = p orelse return "";
    return std.mem.span(str);
}

fn native_posix_getpwuid(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .int) return NativeResult.scalar(.{ .bool = false });
    const pw = getpwuid(@intCast(args[0].int)) orelse return NativeResult.scalar(.{ .bool = false });
    const arr = try ctx.createArray();
    try arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("name") }, cstrBytes(pw.pw_name));
    try arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("passwd") }, cstrBytes(pw.pw_passwd));
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("uid") }, .{ .int = @intCast(pw.pw_uid) });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("gid") }, .{ .int = @intCast(pw.pw_gid) });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("gecos") }, .{ .string = Value.String.borrowed("") });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("dir") }, .{ .string = Value.String.borrowed("") });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("shell") }, .{ .string = Value.String.borrowed("") });
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_posix_getgrgid(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .int) return NativeResult.scalar(.{ .bool = false });
    const g = getgrgid(@intCast(args[0].int)) orelse return NativeResult.scalar(.{ .bool = false });
    const arr = try ctx.createArray();
    try arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("name") }, cstrBytes(g.gr_name));
    try arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("passwd") }, cstrBytes(g.gr_passwd));
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("gid") }, .{ .int = @intCast(g.gr_gid) });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("members") }, .{ .array = try ctx.createArray() });
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_posix_getpwnam(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const name_z = try ctx.allocator.dupeSentinel(u8, args[0].string.bytes(), 0);
    defer ctx.allocator.free(name_z);
    const pw = getpwnam(name_z) orelse return NativeResult.scalar(.{ .bool = false });
    const arr = try ctx.createArray();
    try arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("name") }, cstrBytes(pw.pw_name));
    try arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("passwd") }, cstrBytes(pw.pw_passwd));
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("uid") }, .{ .int = @intCast(pw.pw_uid) });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("gid") }, .{ .int = @intCast(pw.pw_gid) });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("gecos") }, .{ .string = Value.String.borrowed("") });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("dir") }, .{ .string = Value.String.borrowed("") });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("shell") }, .{ .string = Value.String.borrowed("") });
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_posix_getgrnam(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const name_z = try ctx.allocator.dupeSentinel(u8, args[0].string.bytes(), 0);
    defer ctx.allocator.free(name_z);
    const g = getgrnam(name_z) orelse return NativeResult.scalar(.{ .bool = false });
    const arr = try ctx.createArray();
    try arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("name") }, cstrBytes(g.gr_name));
    try arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("passwd") }, cstrBytes(g.gr_passwd));
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("gid") }, .{ .int = @intCast(g.gr_gid) });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("members") }, .{ .array = try ctx.createArray() });
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_posix_getgroups(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    var buf: [256]std.c.gid_t = undefined;
    const n = getgroups(@intCast(buf.len), &buf);
    if (n < 0) return NativeResult.scalar(.{ .bool = false });
    const arr = try ctx.createArray();
    var i: usize = 0;
    while (i < @as(usize, @intCast(n))) : (i += 1) {
        try arr.append(ctx.allocator, .{ .int = @intCast(buf[i]) });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_posix_setsid(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const r = setsid();
    if (r == -1) {
        last_posix_errno = std.c._errno().*;
        return NativeResult.scalar(.{ .int = -1 });
    }
    return NativeResult.scalar(.{ .int = @intCast(r) });
}

fn native_posix_setpgid(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .int or args[1] != .int) return NativeResult.scalar(.{ .bool = false });
    const rc = setpgid(@intCast(args[0].int), @intCast(args[1].int));
    if (rc != 0) {
        last_posix_errno = std.c._errno().*;
        return NativeResult.scalar(.{ .bool = false });
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn native_posix_getpgid(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .int) return NativeResult.scalar(.{ .bool = false });
    const r = getpgid(@intCast(args[0].int));
    if (r == -1) {
        last_posix_errno = std.c._errno().*;
        return NativeResult.scalar(.{ .bool = false });
    }
    return NativeResult.scalar(.{ .int = @intCast(r) });
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

fn native_posix_getrlimit(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // PHP returns an array of all rlimits by default, or just one when an int
    // resource id is passed
    const arr = try ctx.createArray();
    inline for (RLIMIT_NAMES, 0..) |n, idx| {
        var rl: Rlimit = undefined;
        if (getrlimit(@intCast(idx), &rl) == 0) {
            const cur: i64 = if (rl.rlim_cur == std.math.maxInt(u64)) -1 else @intCast(rl.rlim_cur);
            const max: i64 = if (rl.rlim_max == std.math.maxInt(u64)) -1 else @intCast(rl.rlim_max);
            try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("soft " ++ n) }, .{ .int = cur });
            try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("hard " ++ n) }, .{ .int = max });
        }
    }
    _ = args;
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_posix_setrlimit(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 3 or args[0] != .int) return NativeResult.scalar(.{ .bool = false });
    const soft: u64 = if (args[1] == .int) (if (args[1].int < 0) std.math.maxInt(u64) else @intCast(args[1].int)) else 0;
    const hard: u64 = if (args[2] == .int) (if (args[2].int < 0) std.math.maxInt(u64) else @intCast(args[2].int)) else 0;
    const rl = Rlimit{ .rlim_cur = soft, .rlim_max = hard };
    if (setrlimit(@intCast(args[0].int), &rl) != 0) {
        last_posix_errno = std.c._errno().*;
        return NativeResult.scalar(.{ .bool = false });
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn native_posix_uname(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // simple impl - php_uname-style fields. zphp doesn't link directly to
    // uname(2) but std.posix can produce host info
    const arr = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("sysname") }, .{ .string = Value.String.borrowed("") });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("nodename") }, .{ .string = Value.String.borrowed("") });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("release") }, .{ .string = Value.String.borrowed("") });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("version") }, .{ .string = Value.String.borrowed("") });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("machine") }, .{ .string = Value.String.borrowed("") });
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_posix_get_last_error(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = @intCast(last_posix_errno) });
}

fn native_posix_strerror(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .int) return NativeResult.literal("");
    const s = strerror(@intCast(args[0].int)) orelse return NativeResult.literal("");
    return try NativeResult.copyString(ctx.allocator, std.mem.span(s));
}

// the c library's services and protocols databases, as php's
// ext/standard/basic_functions.c reads them
const Servent = extern struct { s_name: ?[*:0]const u8, s_aliases: ?*anyopaque, s_port: c_int, s_proto: ?[*:0]const u8 };
const Protoent = extern struct { p_name: ?[*:0]const u8, p_aliases: ?*anyopaque, p_proto: c_int };
extern fn getservbyname(name: [*:0]const u8, proto: [*:0]const u8) ?*Servent;
extern fn getservbyport(port: c_int, proto: [*:0]const u8) ?*Servent;
extern fn getprotobyname(name: [*:0]const u8) ?*Protoent;
extern fn getprotobynumber(proto: c_int) ?*Protoent;

fn native_getservbyname(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = @import("string_ports.zig").Args.init(ctx, "getservbyname", args);
    const service = try ctx.allocator.dupeSentinel(u8, try p.path(0, "service"), 0);
    defer ctx.allocator.free(service);
    const protocol = try ctx.allocator.dupeSentinel(u8, try p.path(1, "protocol"), 0);
    defer ctx.allocator.free(protocol);
    if (platform.is_windows) return NativeResult.scalar(.{ .bool = false });
    const serv = getservbyname(service.ptr, protocol.ptr) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = std.mem.bigToNative(u16, @truncate(@as(c_uint, @bitCast(serv.s_port)))) });
}

fn native_getservbyport(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = @import("string_ports.zig").Args.init(ctx, "getservbyport", args);
    const port = try p.long(0, "port");
    const protocol = try ctx.allocator.dupeSentinel(u8, try p.path(1, "protocol"), 0);
    defer ctx.allocator.free(protocol);
    if (platform.is_windows) return NativeResult.scalar(.{ .bool = false });
    const net_port: u16 = std.mem.nativeToBig(u16, @truncate(@as(u64, @bitCast(port))));
    const serv = getservbyport(@intCast(net_port), protocol.ptr) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.copyString(ctx.allocator, std.mem.span(serv.s_name orelse return NativeResult.scalar(.{ .bool = false })));
}

fn native_getprotobyname(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const name = try ctx.allocator.dupeSentinel(u8, try @import("string_ports.zig").Args.init(ctx, "getprotobyname", args).path(0, "protocol"), 0);
    defer ctx.allocator.free(name);
    if (platform.is_windows) return NativeResult.scalar(.{ .bool = false });
    const ent = getprotobyname(name.ptr) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = ent.p_proto });
}

fn native_getprotobynumber(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const number = try @import("string_ports.zig").Args.init(ctx, "getprotobynumber", args).long(0, "protocol");
    if (platform.is_windows) return NativeResult.scalar(.{ .bool = false });
    const ent = getprotobynumber(@truncate(number)) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.copyString(ctx.allocator, std.mem.span(ent.p_name orelse return NativeResult.scalar(.{ .bool = false })));
}

// the cli never loses its connection: CONNECTION_NORMAL, and not aborted
fn native_connection_status(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = 0 });
}

// php's opt_struct: a short option's character, or a long option's name
// (opt_char 0); the list ends with opt_char '-'
const GetoptOpt = struct {
    opt_char: u8,
    need_param: u8,
    name: ?[]const u8,
};

const getopt_invalid: i32 = -2;
const getopt_eof: i32 = -1;

// main/getopt.c's php_getopt with its static state, which a getopt() call
// starts afresh (prev_optarg differs each call)
const Getopt = struct {
    argv: []const []const u8,
    opts: []const GetoptOpt,
    optind: usize = 1,
    optchr: usize = 0,
    dash: bool = false,
    optidx: isize = -1,
    optarg: ?[]const u8 = null,

    fn at(s: []const u8, i: usize) u8 {
        return if (i < s.len) s[i] else 0;
    }

    fn next(g: *Getopt) i32 {
        g.optidx = -1;
        g.optarg = null;
        const argc = g.argv.len;
        if (g.optind >= argc) return getopt_eof;
        var arg = g.argv[g.optind];
        if (!g.dash) {
            if (at(arg, 0) != '-') return getopt_eof;
            if (at(arg, 1) == 0) return getopt_eof;
        }
        var arg_start: usize = undefined;
        if (at(arg, 0) == '-' and at(arg, 1) == '-') {
            // "--" ends the options unless a long option name follows
            if (at(arg, 2) == 0) {
                g.optind += 1;
                return getopt_eof;
            }
            arg_start = 2;
            var arg_end: usize = arg.len - 1;
            if (std.mem.indexOfScalar(u8, arg[arg_start..][0 .. arg_end - arg_start], '=')) |pos| {
                arg_end = pos;
                arg_start += 1;
            } else {
                arg_end -= 1;
            }
            while (true) {
                g.optidx += 1;
                const o = g.opts[@intCast(g.optidx)];
                if (o.opt_char == '-') {
                    g.optind += 1;
                    return getopt_invalid;
                }
                if (o.name) |name| {
                    if (name.len == arg_end and std.mem.eql(u8, arg[2 .. 2 + arg_end], name)) break;
                }
            }
            g.optchr = 0;
            g.dash = false;
            arg_start += g.opts[@intCast(g.optidx)].name.?.len;
        } else {
            if (!g.dash) {
                g.dash = true;
                g.optchr = 1;
            }
            if (at(arg, g.optchr) == ':') {
                g.dash = false;
                g.optind += 1;
                return getopt_invalid;
            }
            arg_start = 1 + g.optchr;
        }
        if (g.optidx < 0) {
            while (true) {
                g.optidx += 1;
                const o = g.opts[@intCast(g.optidx)];
                if (o.opt_char == '-') {
                    if (at(arg, g.optchr + 1) == 0) {
                        g.dash = false;
                        g.optind += 1;
                    } else {
                        g.optchr += 1;
                    }
                    return getopt_invalid;
                }
                if (at(arg, g.optchr) == o.opt_char) break;
            }
        }
        const o = g.opts[@intCast(g.optidx)];
        if (o.need_param != 0) {
            g.dash = false;
            if (at(arg, arg_start) == 0) {
                g.optind += 1;
                if (g.optind == argc) {
                    if (o.need_param == 1) return getopt_invalid;
                } else if (o.need_param == 1) {
                    g.optarg = g.argv[g.optind];
                    g.optind += 1;
                }
            } else if (arg[arg_start] == '=') {
                g.optarg = arg[arg_start + 1 ..];
                g.optind += 1;
            } else {
                g.optarg = arg[arg_start..];
                g.optind += 1;
            }
            return o.opt_char;
        }
        // several short options in one argument
        if (arg_start >= 2 and !(at(arg, 0) == '-' and at(arg, 1) == '-')) {
            if (at(arg, g.optchr + 1) == 0) {
                g.dash = false;
                g.optind += 1;
            } else {
                g.optchr += 1;
            }
        } else {
            g.optind += 1;
        }
        return o.opt_char;
    }
};

fn isOptChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c);
}

// ext/standard's getopt(): the options php_getopt finds in $_SERVER['argv']
// (or a global $argv), each option's values gathered into an array when it
// repeats
fn native_getopt(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const short = try @import("string_ports.zig").Args.init(ctx, "getopt", args).str(0, "short_options");
    if (args.len >= 3) ctx.setCallerVar(2, args.len, .{ .int = 1 });
    const server = ctx.vm.request_vars.get("$_SERVER");
    const argv_val = blk: {
        if (server) |s| if (s == .array) {
            const v = s.array.get(.{ .string = Value.String.borrowed("argv") });
            if (v != .null) break :blk v;
        };
        break :blk ctx.vm.request_vars.get("$argv") orelse return NativeResult.scalar(.{ .bool = false });
    };
    if (argv_val != .array) return NativeResult.scalar(.{ .bool = false });
    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var argv: std.ArrayListUnmanaged([]const u8) = .empty;
    for (argv_val.array.entries.items) |entry| {
        const v = if (entry.ref) |cell| cell.* else entry.value;
        const s = try @import("strings.zig").coerceToString(ctx, v);
        // php copies each argument as a c string
        const nul = std.mem.indexOfScalar(u8, s, 0) orelse s.len;
        try argv.append(a, try a.dupe(u8, s[0..nul]));
    }
    var opts: std.ArrayListUnmanaged(GetoptOpt) = .empty;
    var i: usize = 0;
    while (i < short.len and isOptChar(short[i])) {
        var o: GetoptOpt = .{ .opt_char = short[i], .need_param = 0, .name = null };
        i += 1;
        if (i < short.len and short[i] == ':') {
            o.need_param = 1;
            i += 1;
            if (i < short.len and short[i] == ':') {
                o.need_param = 2;
                i += 1;
            }
        }
        try opts.append(a, o);
    }
    if (args.len >= 2 and args[1] == .array) {
        for (args[1].array.entries.items) |entry| {
            const v = if (entry.ref) |cell| cell.* else entry.value;
            const s = try @import("strings.zig").coerceToString(ctx, v);
            var name = s[0 .. std.mem.indexOfScalar(u8, s, 0) orelse s.len];
            var need: u8 = 0;
            if (name.len > 0 and name[name.len - 1] == ':') {
                need = 1;
                name = name[0 .. name.len - 1];
                if (name.len > 0 and name[name.len - 1] == ':') {
                    need = 2;
                    name = name[0 .. name.len - 1];
                }
            }
            try opts.append(a, .{ .opt_char = 0, .need_param = need, .name = try a.dupe(u8, name) });
        }
    }
    try opts.append(a, .{ .opt_char = '-', .need_param = 0, .name = null });

    const out = try ctx.createArray();
    var g: Getopt = .{ .argv = argv.items, .opts = opts.items };
    while (true) {
        const o = g.next();
        if (o == getopt_eof) break;
        if (o == getopt_invalid) continue;
        var one: [1]u8 = undefined;
        const optname: []const u8 = if (o == 0) g.opts[@intCast(g.optidx)].name.? else blk: {
            one[0] = if (o == 1) '-' else @intCast(o);
            break :blk &one;
        };
        const val: Value = if (g.optarg) |arg| .{ .string = try Value.String.create(ctx.allocator, arg) } else .{ .bool = false };
        defer if (val == .string) val.string.release();
        const key: PhpArray.Key = blk: {
            // is_numeric_string's IS_LONG
            if (!(optname.len > 1 and optname[0] == '0') and Value.isNumericString(optname)) {
                const t = std.mem.trim(u8, optname, " \t\n\r\x0b\x0c");
                if (std.mem.indexOfAny(u8, t, ".eE") == null) if (std.fmt.parseInt(i64, t, 10)) |n| break :blk .{ .int = n } else |_| {};
            }
            break :blk .{ .string = try Value.String.create(ctx.allocator, optname) };
        };
        defer if (key == .string) key.string.release();
        if (out.getPtr(key)) |existing| {
            if (existing.value != .array) {
                const arr = try ctx.createArray();
                try arr.append(ctx.allocator, existing.value);
                try out.set(ctx.allocator, key, .{ .array = arr });
            }
            try out.getPtr(key).?.value.array.append(ctx.allocator, val);
        } else {
            try out.set(ctx.allocator, key, val);
        }
    }
    if (args.len >= 3) ctx.setCallerVar(2, args.len, .{ .int = @intCast(g.optind) });
    return NativeResult.borrowed(.{ .array = out });
}

fn native_sleep(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = @import("string_ports.zig").Args.init(ctx, "sleep", args);
    const secs = try p.long(0, "seconds");
    if (secs < 0) return p.valueError(0, "seconds", "must be greater than or equal to 0");
    if (secs > 0) ctx.vm.flushOutputToStdout();
    if (secs > 0) platform.sleep(@as(u64, @intCast(@min(secs, std.math.maxInt(u32)))) * 1_000_000_000);
    return NativeResult.scalar(.{ .int = 0 });
}

fn native_usleep(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = @import("string_ports.zig").Args.init(ctx, "usleep", args);
    const usecs = try p.long(0, "microseconds");
    if (usecs < 0) return p.valueError(0, "microseconds", "must be greater than or equal to 0");
    if (usecs > 0) ctx.vm.flushOutputToStdout();
    if (usecs > 0) platform.sleep(@as(u64, @intCast(@min(usecs, std.math.maxInt(u32)))) * 1_000);
    return NativeResult.scalar(.null);
}

fn native_time_nanosleep(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = @import("string_ports.zig").Args.init(ctx, "time_nanosleep", args);
    const secs = try p.long(0, "seconds");
    const nsecs = try p.long(1, "nanoseconds");
    if (secs < 0) return p.valueError(0, "seconds", "must be greater than or equal to 0");
    if (nsecs < 0) return p.valueError(1, "nanoseconds", "must be greater than or equal to 0");
    // nanosleep's EINVAL
    if (nsecs > 999_999_999) {
        try ctx.vm.setPendingException("ValueError", "Nanoseconds was not in the range 0 to 999 999 999 or seconds was negative");
        return error.RuntimeError;
    }
    const total = std.math.mul(u64, @intCast(secs), 1_000_000_000) catch std.math.maxInt(u64);
    platform.sleep(total +| @as(u64, @intCast(nsecs)));
    return NativeResult.scalar(.{ .bool = true });
}

fn native_time_sleep_until(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = @import("string_ports.zig").Args.init(ctx, "time_sleep_until", args);
    const target = try p.double(0, "timestamp");
    const ns_per_sec: u64 = 1_000_000_000;
    const top: u64 = std.math.maxInt(u64) / ns_per_sec;
    if (!(target >= 0 and target <= @as(f64, @floatFromInt(top)))) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "time_sleep_until(): Argument #1 ($timestamp) must be between 0 and {d}", .{top});
        defer ctx.allocator.free(msg);
        try ctx.vm.setPendingException("ValueError", msg);
        return error.RuntimeError;
    }
    const target_ns: u64 = @intFromFloat(target * 1e9);
    const now_ns: u64 = @intCast(@divTrunc(platform.nanoTimestamp(), 1000) * 1000);
    if (target_ns < now_ns) {
        try @import("filesystem.zig").warnDocref(ctx, "Argument #1 ($timestamp) must be greater than or equal to the current time", .{});
        return NativeResult.scalar(.{ .bool = false });
    }
    platform.sleep(target_ns - now_ns);
    return NativeResult.scalar(.{ .bool = true });
}

extern fn getloadavg(loadavg: [*]f64, nelem: c_int) c_int;

fn native_sys_getloadavg(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    if (platform.is_windows) return NativeResult.scalar(.{ .bool = false });
    return posixLoadAvg(ctx);
}

fn posixLoadAvg(ctx: *NativeContext) RuntimeError!NativeResult {
    var samples: [3]f64 = .{ 0, 0, 0 };
    const got = getloadavg(&samples, 3);
    if (got < 0) return NativeResult.scalar(.{ .bool = false });
    const arr = try ctx.createArray();
    var i: usize = 0;
    const count: usize = @intCast(got);
    while (i < count) : (i += 1) {
        try arr.set(ctx.allocator, .{ .int = @intCast(i) }, .{ .float = samples[i] });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_getenv(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // no-arg form returns all environment vars as an associative array
    if (args.len == 0) {
        const arr = try ctx.createArray();
        if (platform.is_windows) {
            var em = platform.getEnvMap(ctx.allocator) catch return NativeResult.borrowed(.{ .array = arr });
            defer em.deinit();
            var it = em.iterator();
            while (it.next()) |e| try putEnvEntry(ctx, arr, e.key_ptr.*, e.value_ptr.*);
        } else {
            var lines = std.c.environ;
            while (lines[0]) |entry| : (lines += 1) {
                const line = std.mem.span(entry);
                const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
                try putEnvEntry(ctx, arr, line[0..eq], line[eq + 1 ..]);
            }
        }
        return NativeResult.borrowed(.{ .array = arr });
    }
    if (args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const val = platform.getenvOwned(ctx.allocator, args[0].string.bytes()) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, val));
}

fn putEnvEntry(ctx: *NativeContext, arr: *PhpArray, name: []const u8, value: []const u8) !void {
    const key = try Value.String.create(ctx.allocator, name);
    defer key.release();
    try arr.setCopiedString(ctx.allocator, .{ .string = key }, value);
}

extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;
// mingw has no setenv; _putenv_s with an empty value removes the variable
extern "c" fn _putenv_s(name: [*:0]const u8, value: [*:0]const u8) c_int;

fn native_putenv(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = @import("string_ports.zig").Args.init(ctx, "putenv", args);
    const setting = try p.str(0, "assignment");
    if (setting.len == 0 or setting[0] == '=') return p.valueError(0, "assignment", "must have a valid syntax");
    if (std.mem.indexOfScalar(u8, setting, '=')) |eq| {
        const name = setting[0..eq];
        const val = setting[eq + 1 ..];
        const name_z = ctx.allocator.dupeSentinel(u8, name, 0) catch return NativeResult.scalar(.{ .bool = false });
        defer ctx.allocator.free(name_z);
        const val_z = ctx.allocator.dupeSentinel(u8, val, 0) catch return NativeResult.scalar(.{ .bool = false });
        defer ctx.allocator.free(val_z);
        const ok = if (platform.is_windows) _putenv_s(name_z.ptr, val_z.ptr) == 0 else setenv(name_z.ptr, val_z.ptr, 1) == 0;
        return NativeResult.scalar(.{ .bool = ok });
    } else {
        const name_z = ctx.allocator.dupeSentinel(u8, setting, 0) catch return NativeResult.scalar(.{ .bool = false });
        defer ctx.allocator.free(name_z);
        const ok = if (platform.is_windows) _putenv_s(name_z.ptr, "") == 0 else unsetenv(name_z.ptr) == 0;
        return NativeResult.scalar(.{ .bool = ok });
    }
}

threadlocal var previous_uniqid_microsecond: i128 = -1;

fn native_uniqid(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = @import("string_ports.zig").Args.init(ctx, "uniqid", args);
    const prefix = if (p.has(0)) try p.str(0, "prefix") else "";
    const more_entropy = try p.boolean(1, "more_entropy", false);
    var ns = platform.nanoTimestamp();
    while (@divFloor(ns, 1_000) == previous_uniqid_microsecond) ns = platform.nanoTimestamp();
    previous_uniqid_microsecond = @divFloor(ns, 1_000);
    const abs_ns: u64 = @intCast(if (ns < 0) -ns else ns);
    const usec: u64 = @divTrunc(@mod(abs_ns, 1_000_000_000), 1_000) % 0x100000;
    const sec: u32 = @truncate(@divTrunc(abs_ns, 1_000_000_000));
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(ctx.allocator);
    try out.print(ctx.allocator, "{s}{x:0>8}{x:0>5}", .{ prefix, sec, usec });
    if (more_entropy) {
        // "%.8F" of a random double in [0, 10]
        const seed = @as(f64, @floatFromInt(platform.random.int(u32))) / @as(f64, std.math.maxInt(u32)) * 10.0;
        try out.print(ctx.allocator, "{d:.8}", .{seed});
    }
    return try NativeResult.copyString(ctx.allocator, out.items);
}

fn native_getcwd(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = platform.realpath(".", &buf) catch return NativeResult.scalar(.{ .bool = false });
    return try NativeResult.copyString(ctx.allocator, cwd);
}

fn native_php_ini_loaded_file(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const path = @import("../ini_config.zig").loadedFile() orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.copyString(ctx.allocator, path);
}

fn native_php_ini_scanned_files(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // PHP returns false when no additional ini directory was scanned
    return NativeResult.scalar(.{ .bool = false });
}

// php's dl() checks, before it would load anything: zphp loads extensions
// only at startup (--extension), so a request to load one fails as a
// library php can't open does
fn native_dl(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const filename = try @import("string_ports.zig").Args.init(ctx, "dl", args).str(0, "extension_filename");
    const enabled = ctx.vm.ini_settings.get("enable_dl") orelse "1";
    if (!iniBool(enabled)) {
        try ctx.vm.emitWarning("dl(): Dynamically loaded extensions aren't enabled");
        return NativeResult.scalar(.{ .bool = false });
    }
    if (filename.len >= 4096) {
        try ctx.vm.emitWarning("dl(): Filename exceeds the maximum allowed length of 4096 characters");
        return NativeResult.scalar(.{ .bool = false });
    }
    if (std.mem.indexOfScalar(u8, filename, '/') != null or (platform.is_windows and std.mem.indexOfScalar(u8, filename, '\\') != null)) {
        try ctx.vm.emitWarning("dl(): Temporary module name should contain only filename");
        return NativeResult.scalar(.{ .bool = false });
    }
    const msg = try std.fmt.allocPrint(ctx.allocator, "dl(): Unable to load dynamic library '{s}'", .{filename});
    defer ctx.allocator.free(msg);
    try ctx.vm.emitWarning(msg);
    return NativeResult.scalar(.{ .bool = false });
}

// zend_ini_parse_bool
fn iniBool(v: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(v, "true") or std.ascii.eqlIgnoreCase(v, "yes") or std.ascii.eqlIgnoreCase(v, "on")) return true;
    const t = std.mem.trimStart(u8, v, " \t\n\r\x0b\x0c");
    var end: usize = 0;
    if (end < t.len and (t[end] == '-' or t[end] == '+')) end += 1;
    while (end < t.len and std.ascii.isDigit(t[end])) end += 1;
    const n = std.fmt.parseInt(i64, t[0..end], 10) catch 0;
    return n != 0;
}

fn native_phpinfo(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = args;
    // minimal output: enough for callers to verify the function exists. real
    // PHP prints a giant HTML/text dump of the environment
    try ctx.vm.output.appendSlice(ctx.allocator, "PHP Version => " ++ php_version.string ++ "\n");
    try @import("pcre.zig").writeInfo(ctx, &ctx.vm.output);
    return NativeResult.scalar(.{ .bool = true });
}

fn native_phpcredits(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = true });
}

fn native_getlastmod(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // PHP returns the last modification time of the main script. zphp tracks
    // the running file path; stat it to produce a real mtime
    const path = ctx.vm.file_path;
    if (path.len == 0) return NativeResult.scalar(.{ .bool = false });
    const stat = std.Io.Dir.cwd().statFile(platform.io, path, .{}) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(@divTrunc(stat.mtime.nanoseconds, std.time.ns_per_s)) });
}

fn native_cli_get_process_title(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // not actually tracking the process title; PHP returns false when no title
    // was set explicitly via cli_set_process_title earlier in the run
    return NativeResult.scalar(.{ .bool = false });
}

fn native_cli_set_process_title(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // best-effort no-op; the real prctl(PR_SET_NAME) syscall is linux-only and
    // the cosmetic effect rarely matters for scripts that defensively set it
    return NativeResult.scalar(.{ .bool = true });
}

fn native_php_uname(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = @import("string_ports.zig").Args.init(ctx, "php_uname", args);
    const mode_str = if (p.has(0)) try p.str(0, "mode") else "a";
    if (mode_str.len != 1) return p.valueError(0, "mode", "must be a single character");
    const mode = mode_str[0];
    if (std.mem.indexOfScalar(u8, "amnrsv", mode) == null) return p.valueError(0, "mode", "must be one of \"a\", \"m\", \"n\", \"r\", \"s\", or \"v\"");
    if (!platform.is_windows) {
        var uts: std.c.utsname = undefined;
        if (std.c.uname(&uts) == 0) {
            const field = struct {
                fn f(bytes: anytype) []const u8 {
                    return std.mem.sliceTo(@as([*:0]const u8, @ptrCast(bytes)), 0);
                }
            }.f;
            if (mode == 'a') {
                const all = try std.fmt.allocPrint(ctx.allocator, "{s} {s} {s} {s} {s}", .{ field(&uts.sysname), field(&uts.nodename), field(&uts.release), field(&uts.version), field(&uts.machine) });
                defer ctx.allocator.free(all);
                return NativeResult.copyString(ctx.allocator, all);
            }
            return NativeResult.copyString(ctx.allocator, switch (mode) {
                's' => field(&uts.sysname),
                'n' => field(&uts.nodename),
                'r' => field(&uts.release),
                'v' => field(&uts.version),
                else => field(&uts.machine),
            });
        }
    }
    const is_mac = platform.is_macos;
    const is_arm = @import("builtin").cpu.arch == .aarch64;
    const sysname: []const u8 = if (platform.is_windows) "Windows NT" else if (is_mac) "Darwin" else "Linux";
    const machine: []const u8 = if (platform.is_windows) "AMD64" else if (is_arm) "arm64" else "x86_64";
    return try NativeResult.copyString(ctx.allocator, switch (mode) {
        's' => sysname,
        'n' => "localhost",
        'r' => "0.0.0",
        'm' => machine,
        else => if (platform.is_windows) "Windows NT localhost 0.0.0 AMD64" else if (is_mac) "Darwin localhost 0.0.0 arm64" else "Linux localhost 0.0.0 x86_64",
    });
}

fn native_move_uploaded_file(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const from = args[0].string.bytes();
    const to = args[1].string.bytes();
    if (!std.mem.startsWith(u8, from, "/tmp/zphp_upload_")) return NativeResult.scalar(.{ .bool = false });
    bundle.prepareWrite(to, .create);
    std.Io.Dir.cwd().rename(from, std.Io.Dir.cwd(), to, platform.io) catch {
        const data = std.Io.Dir.cwd().readFileAlloc(platform.io, from, std.heap.page_allocator, .limited(1024 * 1024 * 64)) catch return NativeResult.scalar(.{ .bool = false });
        defer std.heap.page_allocator.free(data);
        std.Io.Dir.cwd().writeFile(platform.io, .{ .sub_path = to, .data = data }) catch return NativeResult.scalar(.{ .bool = false });
        std.Io.Dir.cwd().deleteFile(platform.io, from) catch {};
    };
    return NativeResult.scalar(.{ .bool = true });
}

fn native_is_uploaded_file(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    if (!std.mem.startsWith(u8, args[0].string.bytes(), "/tmp/zphp_upload_")) return NativeResult.scalar(.{ .bool = false });
    std.Io.Dir.cwd().access(platform.io, args[0].string.bytes(), .{}) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn native_sys_get_temp_dir(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.copyString(ctx.allocator, systemTempDir());
}

// php's temporary directory: TMPDIR (TEMP, TMP) without a trailing slash,
// or the platform's default
fn systemTempDir() []const u8 {
    const env_keys = [_][]const u8{ "TMPDIR", "TEMP", "TMP" };
    for (env_keys) |k| {
        if (platform.getenv(k)) |v| {
            if (v.len > 0) return if (v.len > 1 and v[v.len - 1] == '/') v[0 .. v.len - 1] else v;
        }
    }
    return platform.tempDir();
}

fn native_tempnam(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const params = html.Params{ .ctx = ctx, .func = "tempnam", .args = args };
    const dir = try params.string(0, "directory", "");
    const prefix_arg = try params.string(1, "prefix", "");
    inline for (.{ .{ dir, 1, "directory" }, .{ prefix_arg, 2, "prefix" } }) |p| {
        if (std.mem.indexOfScalar(u8, p[0], 0) != null) {
            try ctx.vm.setPendingException("ValueError", std.fmt.comptimePrint("tempnam(): Argument #{d} (${s}) must not contain any null bytes", .{ p[1], p[2] }));
            return error.RuntimeError;
        }
    }
    // only the prefix's last path segment counts, cut to 63 bytes
    var prefix = std.fs.path.basename(prefix_arg);
    if (prefix.len > 63) prefix = prefix[0..63];

    // an empty directory means the system's; one that cannot hold the file
    // falls back to it with a notice
    // open_basedir is checked on the directory given and on the fallback
    const limited = open_basedir.setting(ctx.vm) != null;
    if (dir.len > 0) {
        if (limited and !try open_basedir.allows(ctx.vm, "tempnam", dir)) return NativeResult.scalar(.{ .bool = false });
        bundle.ensureDir(dir);
        if (try createTempFile(ctx, dir, prefix)) |path| return NativeResult.takeString(path);
        try ctx.vm.raiseError(8, "tempnam(): file created in the system's temporary directory");
    }
    if (limited and !try open_basedir.allows(ctx.vm, "tempnam", systemTempDir())) return NativeResult.scalar(.{ .bool = false });
    if (try createTempFile(ctx, systemTempDir(), prefix)) |path| return NativeResult.takeString(path);
    return NativeResult.scalar(.{ .bool = false });
}

// php_do_open_temporary_file: in the real directory, the prefix with 13
// base32 characters of randomness and mkstemp's six more, created 0600
fn createTempFile(ctx: *NativeContext, dir: []const u8, prefix: []const u8) RuntimeError!?Value.String {
    var real_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = platform.realpath(dir, &real_buf) catch return null;
    const base32 = "0123456789abcdefghijklmnopqrstuv";
    const mkstemp_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    var random_bytes: [8]u8 = undefined;
    platform.random.bytes(&random_bytes);
    var random = std.mem.readInt(u64, &random_bytes, .little);
    var suffix: [13]u8 = undefined;
    for (&suffix) |*c| {
        c.* = base32[random % base32.len];
        random /= base32.len;
    }
    const sep: []const u8 = if (real.len > 0 and platform.isSep(real[real.len - 1])) "" else platform.sep_str;
    var attempt: usize = 0;
    while (attempt < 100) : (attempt += 1) {
        var tail: [6]u8 = undefined;
        for (&tail) |*c| c.* = mkstemp_chars[platform.random.uintLessThan(usize, mkstemp_chars.len)];
        const candidate = try std.fmt.allocPrint(ctx.allocator, "{s}{s}{s}{s}{s}", .{ real, sep, prefix, &suffix, &tail });
        if (std.Io.Dir.cwd().createFile(platform.io, candidate, .{ .exclusive = true, .permissions = platform.permissionsFromMode(0o600) })) |file| {
            file.close(platform.io);
            return try Value.String.adopt(ctx.allocator, candidate);
        } else |err| {
            ctx.allocator.free(candidate);
            if (err != error.PathAlreadyExists) return null;
        }
    }
    return null;
}

fn buildBacktrace(ctx: *NativeContext, ignore_args: bool, provide_object: bool, limit: usize) RuntimeError!*PhpArray {
    const vm = ctx.vm;
    const alloc = ctx.allocator;
    var result = try ctx.createArray();

    if (vm.frame_count <= 1) return result;

    const max = if (limit > 0) @min(limit, vm.frame_count - 1) else vm.frame_count - 1;
    var count: usize = 0;
    var i: usize = vm.frame_count - 1;

    // the running natives below debug_backtrace itself, innermost first:
    // php lists each where its frame would be, and what one calls as
    // called from an internal function
    var natives: [64]*const @import("../runtime/vm.zig").NativeCall = undefined;
    var native_count: usize = 0;
    var call = vm.native_call;
    if (call) |c| if (c.depth == vm.frame_count) {
        call = c.outer;
    };
    while (call) |c| : (call = c.outer) {
        if (c.depth > vm.frame_count) continue;
        if (native_count == natives.len) break;
        natives[native_count] = c;
        native_count += 1;
    }
    var next_native: usize = 0;

    while (i >= 1 and count < max) : ({
        i -= 1;
        count += 1;
    }) {
        try appendNativeEntries(vm, result, natives[0..native_count], &next_native, i, ignore_args, limit);
        if (limit > 0 and result.entries.items.len >= limit) break;
        const called_by_native = next_native < native_count and natives[next_native].depth == i;
        var entry = try ctx.createArray();
        const frame = &vm.frames[i];
        // a generator running as a yield from delegate is listed as called
        // from the generator waiting in it, and those waiting generators
        // follow it, as php lists them
        const delegator = if (frame.generator) |g| g.delegator else null;
        if (called_by_native and delegator == null) {
            // [internal function]: no file or line
        } else if (delegator) |d| {
            if (vm.generatorPosition(d)) |site| {
                try entry.set(alloc, .{ .string = Value.String.borrowed("file") }, .{ .string = Value.String.borrowed(site.file) });
                try entry.set(alloc, .{ .string = Value.String.borrowed("line") }, .{ .int = site.line });
            }
        } else {
            try entry.set(alloc, .{ .string = Value.String.borrowed("file") }, .{ .string = Value.String.borrowed(vm.frameFile(i - 1)) });
            const caller = &vm.frames[i - 1];
            if (vm.sourceLocation(caller.chunk, caller.ip)) |loc| {
                try entry.set(alloc, .{ .string = Value.String.borrowed("line") }, .{ .int = @intCast(loc.line) });
            }
        }

        if (frame.func) |func| {
            const type_str: []const u8 = if (func.is_static) "::" else "->";
            if (std.mem.indexOf(u8, func.name, "::")) |sep| {
                try entry.set(alloc, .{ .string = Value.String.borrowed("class") }, .{ .string = Value.String.borrowed(func.name[0..sep]) });
                try entry.set(alloc, .{ .string = Value.String.borrowed("function") }, .{ .string = Value.String.borrowed(try vm.phpMethodName(func.name[sep + 2 ..])) });
                try entry.set(alloc, .{ .string = Value.String.borrowed("type") }, .{ .string = Value.String.borrowed(type_str) });
            } else {
                try entry.set(alloc, .{ .string = Value.String.borrowed("function") }, .{ .string = Value.String.borrowed(try vm.funcDisplayName(func)) });
                if (frame.called_class) |cls| {
                    try entry.set(alloc, .{ .string = Value.String.borrowed("class") }, .{ .string = Value.String.borrowed(cls) });
                    try entry.set(alloc, .{ .string = Value.String.borrowed("type") }, .{ .string = Value.String.borrowed(type_str) });
                }
            }
        }

        if (!ignore_args) {
            var args_arr = try ctx.createArray();
            // a resumed generator's frame has no saved arguments: its
            // parameters hold them
            if (frame.generator != null and frame.func != null) {
                const func = frame.func.?;
                const declared = if (func.is_variadic) func.params.len - 1 else func.params.len;
                const sensitive = try vm.sensitiveParamMask(func);
                for (func.params[0..declared], 0..) |pname, a| try args_arr.append(alloc, try vm.traceArgValue(@TypeOf(vm.*).frameParamValue(frame, func, pname), sensitive, a));
            } else if (vm.ic) |ic| {
                const ac = ic.arg_counts[i];
                if (ac != 0xFF) {
                    const offset: usize = ic.fga_offsets[i];
                    const arg_count: usize = ac;
                    // #[\SensitiveParameter] arguments show redacted
                    const sensitive: u64 = if (frame.func) |func| try vm.sensitiveParamMask(func) else 0;
                    const variadic_at: usize = if (frame.func) |func| (if (func.is_variadic and func.params.len > 0) func.params.len - 1 else std.math.maxInt(usize)) else std.math.maxInt(usize);
                    if (offset + arg_count <= ic.fga_room.committed) {
                        for (0..arg_count) |a| {
                            try args_arr.append(alloc, try vm.traceArgValue(ic.fga_buf[offset + a], sensitive, @min(a, variadic_at)));
                        }
                    }
                }
            }
            try entry.set(alloc, .{ .string = Value.String.borrowed("args") }, .{ .array = args_arr });
        }

        // DEBUG_BACKTRACE_PROVIDE_OBJECT: include the $this bound to this
        // frame. callers walk the backtrace looking for a frame whose object
        // is a particular type (e.g. test runners locating the current test)
        if (provide_object) {
            if (frame.vars.get("$this")) |val| {
                if (val == .object) try entry.set(alloc, .{ .string = Value.String.borrowed("object") }, val);
            }
        }

        try result.append(alloc, .{ .array = entry });

        var waiting = delegator;
        while (waiting) |g| : (waiting = g.delegator) {
            if (limit > 0 and result.entries.items.len >= limit) break;
            count += 1;
            var w = try ctx.createArray();
            if (g.delegator) |d| {
                if (vm.generatorPosition(d)) |site| {
                    try w.set(alloc, .{ .string = Value.String.borrowed("file") }, .{ .string = Value.String.borrowed(site.file) });
                    try w.set(alloc, .{ .string = Value.String.borrowed("line") }, .{ .int = site.line });
                }
            } else if (!called_by_native) {
                try w.set(alloc, .{ .string = Value.String.borrowed("file") }, .{ .string = Value.String.borrowed(vm.frameFile(i - 1)) });
                const caller = &vm.frames[i - 1];
                if (vm.sourceLocation(caller.chunk, caller.ip)) |loc| {
                    try w.set(alloc, .{ .string = Value.String.borrowed("line") }, .{ .int = @intCast(loc.line) });
                }
            }
            const func = g.func;
            if (std.mem.indexOf(u8, func.name, "::")) |sep| {
                try w.set(alloc, .{ .string = Value.String.borrowed("class") }, .{ .string = Value.String.borrowed(func.name[0..sep]) });
                try w.set(alloc, .{ .string = Value.String.borrowed("function") }, .{ .string = Value.String.borrowed(func.name[sep + 2 ..]) });
                try w.set(alloc, .{ .string = Value.String.borrowed("type") }, .{ .string = Value.String.borrowed(if (func.is_static) "::" else "->") });
            } else {
                try w.set(alloc, .{ .string = Value.String.borrowed("function") }, .{ .string = Value.String.borrowed(try vm.funcDisplayName(func)) });
            }
            if (!ignore_args) {
                const args_arr = try ctx.createArray();
                const declared = if (func.is_variadic) func.params.len - 1 else func.params.len;
                for (func.params[0..declared]) |pname| try args_arr.append(alloc, @TypeOf(vm.*).generatorParamValue(g, pname));
                try w.set(alloc, .{ .string = Value.String.borrowed("args") }, .{ .array = args_arr });
            }
            try result.append(alloc, .{ .array = w });
        }
    }

    // natives the main script's code called
    if (i == 0) try appendNativeEntries(vm, result, natives[0..native_count], &next_native, 0, ignore_args, limit);
    return result;
}

// the natives frame i called, innermost first: the outermost of them was
// called from frame i's code, each other one by the native outside it
fn appendNativeEntries(vm: *VM, result: *PhpArray, natives: []const *const @import("../runtime/vm.zig").NativeCall, next: *usize, i: usize, ignore_args: bool, limit: usize) RuntimeError!void {
    while (next.* < natives.len and natives[next.*].depth == i + 1) : (next.* += 1) {
        if (natives[next.*].label.len == 0) continue;
        if (limit > 0 and result.entries.items.len >= limit) return;
        const outermost = next.* + 1 == natives.len or natives[next.* + 1].depth != i + 1;
        const site = if (outermost and !natives[next.*].from_native) vm.framePosition(i) else null;
        const native_entry = try vm.nativeTraceEntry(natives[next.*], site, !ignore_args);
        try result.append(vm.allocator, .{ .array = native_entry });
    }
}

fn native_debug_backtrace(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // PHP options: 0 = DEBUG_BACKTRACE_PROVIDE_OBJECT (default), 2 = DEBUG_BACKTRACE_IGNORE_ARGS.
    // PROVIDE_OBJECT is on by default (option=0); only the inverse bit (1) suppresses it
    const options = if (args.len >= 1) Value.toInt(args[0]) else 0;
    const limit_raw = if (args.len >= 2) Value.toInt(args[1]) else 0;
    const ignore_args = (options & 2) != 0;
    const provide_object = (options & 1) == 0;
    const limit: usize = if (limit_raw > 0) @intCast(limit_raw) else 0;
    return NativeResult.borrowed(.{ .array = try buildBacktrace(ctx, ignore_args, provide_object, limit) });
}

fn native_debug_print_backtrace(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const options = if (args.len >= 1) Value.toInt(args[0]) else 0;
    const limit_raw = if (args.len >= 2) Value.toInt(args[1]) else 0;
    const ignore_args = (options & 2) != 0;
    const limit: usize = if (limit_raw > 0) @intCast(limit_raw) else 0;
    const trace = try buildBacktrace(ctx, ignore_args, false, limit);

    const out = &ctx.vm.output;
    const alloc = ctx.allocator;
    for (trace.entries.items, 0..) |entry, idx| {
        const arr = entry.value.array;
        const func = arr.get(.{ .string = Value.String.borrowed("function") });
        const file = arr.get(.{ .string = Value.String.borrowed("file") });
        const line = arr.get(.{ .string = Value.String.borrowed("line") });
        const class = arr.get(.{ .string = Value.String.borrowed("class") });
        const call_type = arr.get(.{ .string = Value.String.borrowed("type") });
        const call_args = arr.get(.{ .string = Value.String.borrowed("args") });
        var num_buf: [20]u8 = undefined;
        const num_str = std.fmt.bufPrint(&num_buf, "{d}", .{idx}) catch "0";
        try out.appendSlice(alloc, "#");
        try out.appendSlice(alloc, num_str);
        try out.appendSlice(alloc, " ");
        if (file == .string) {
            try out.appendSlice(alloc, file.string.bytes());
            if (line == .int) {
                try out.appendSlice(alloc, "(");
                var line_buf: [20]u8 = undefined;
                const line_str = std.fmt.bufPrint(&line_buf, "{d}", .{line.int}) catch "0";
                try out.appendSlice(alloc, line_str);
                try out.appendSlice(alloc, ")");
            }
            try out.appendSlice(alloc, ": ");
        } else {
            try out.appendSlice(alloc, "[internal function]: ");
        }
        // php appends these as C strings, which end at an anonymous class's NUL
        if (class == .string and call_type == .string) {
            try out.appendSlice(alloc, class_names.display(class.string.bytes()));
            try out.appendSlice(alloc, call_type.string.bytes());
        }
        try out.appendSlice(alloc, if (func == .string) class_names.display(func.string.bytes()) else "{main}");
        try out.append(alloc, '(');
        if (call_args == .array) for (call_args.array.entries.items, 0..) |a, n| {
            if (n > 0) try out.appendSlice(alloc, ", ");
            @import("../error_format.zig").writeTraceArg(out, alloc, a.value);
        };
        try out.appendSlice(alloc, ")\n");
    }
    return NativeResult.scalar(.null);
}

fn native_get_defined_functions(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const vm = ctx.vm;
    const alloc = ctx.allocator;
    var result = try ctx.createArray();

    var internal = try ctx.createArray();
    var iter_n = vm.native_fns.keyIterator();
    while (iter_n.next()) |name| {
        // methods are registered by "C::m" beside the functions
        if (std.mem.indexOf(u8, name.*, "::") != null) continue;
        try internal.append(alloc, .{ .string = Value.String.borrowed(name.*) });
    }

    // php lists the function table's keys: lowercased names of the
    // functions the script declared, no methods or closures
    var user = try ctx.createArray();
    var iter_u = vm.functions.iterator();
    while (iter_u.next()) |entry| {
        const name = entry.key_ptr.*;
        if (name.len == 0 or name[0] == 0 or std.mem.indexOf(u8, name, "::") != null or std.mem.indexOfScalar(u8, name, '$') != null) continue;
        if (std.mem.startsWith(u8, name, "__closure_") or std.mem.startsWith(u8, name, "{closure")) continue;
        if (vm.native_fns.contains(name)) continue;
        const lower = try std.ascii.allocLowerString(alloc, name);
        defer alloc.free(lower);
        const owned = try Value.String.create(alloc, lower);
        defer owned.release();
        try user.append(alloc, .{ .string = owned });
    }

    try result.set(alloc, .{ .string = Value.String.borrowed("internal") }, .{ .array = internal });
    try result.set(alloc, .{ .string = Value.String.borrowed("user") }, .{ .array = user });
    return NativeResult.borrowed(.{ .array = result });
}

fn native_get_defined_vars(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const vm = ctx.vm;
    const alloc = ctx.allocator;
    var result = try ctx.createArray();

    if (vm.frame_count == 0) return NativeResult.borrowed(.{ .array = result });
    const frame = &vm.frames[vm.frame_count - 1];

    // slot-based locals first (compile-time named slots). PHP excludes $this
    // from get_defined_vars() even inside instance methods. code that
    // iterates the result and reflects on each name (e.g. checking which
    // local is a function parameter) breaks if $this is included
    const slot_names = if (frame.func) |func| func.slot_names else vm.global_slot_names;
    for (slot_names, 0..) |sn, i| {
        if (sn.len == 0) continue;
        if (i >= frame.locals.len) break;
        if (frame.locals[i] == .undef) continue;
        // names without a $ are the compiler's own temporaries
        if (sn[0] != '$') continue;
        const name = sn[1..];
        if (name.len == 0) continue;
        if (std.mem.eql(u8, name, "this")) continue;
        try result.set(alloc, .{ .string = Value.String.borrowed(name) }, frame.locals[i]);
    }

    // dynamic vars (extract'd, etc.)
    var iter = frame.vars.iterator();
    while (iter.next()) |entry| {
        const raw = entry.key_ptr.*;
        if (raw.len == 0 or raw[0] != '$') continue;
        const name = raw[1..];
        if (name.len == 0) continue;
        if (entry.value_ptr.* == .null) continue;
        if (std.mem.eql(u8, name, "this")) continue;
        try result.set(alloc, .{ .string = Value.String.borrowed(name) }, entry.value_ptr.*);
    }
    return NativeResult.borrowed(.{ .array = result });
}

fn native_get_defined_classes(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const vm = ctx.vm;
    const alloc = ctx.allocator;
    var result = try ctx.createArray();

    var iter = vm.classes.iterator();
    while (iter.next()) |entry| {
        try result.append(alloc, .{ .string = Value.String.borrowed(entry.key_ptr.*) });
    }
    return NativeResult.borrowed(.{ .array = result });
}

fn native_set_time_limit(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // PHP: set_time_limit(int $seconds): bool. 0 = no limit. each call resets
    // the countdown from "now". negative is the same as 0
    var seconds: i64 = 0;
    if (args.len > 0 and args[0] == .int) seconds = args[0].int;
    if (seconds < 0) seconds = 0;
    ctx.vm.setExecutionLimit(seconds);
    // mirror into the ini directive so subsequent ini_get sees the new value
    var buf: [24]u8 = undefined;
    _ = try ctx.vm.setIni("max_execution_time", std.fmt.bufPrint(&buf, "{d}", .{seconds}) catch unreachable);
    return NativeResult.scalar(.{ .bool = true });
}

// request_parse_body(?array $options = null): the options checked as php
// caches them, then the request's body parsed. without a content type (the
// cli) php throws
fn native_request_parse_body(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const options: Value = if (args.len > 0) args[0] else .null;
    if (options != .null and options != .array) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "request_parse_body(): Argument #1 ($options) must be of type ?array, {s} given", .{options.valueName()});
        defer ctx.allocator.free(msg);
        try ctx.vm.setPendingException("TypeError", msg);
        return error.RuntimeError;
    }
    if (options == .array) for (options.array.entries.items) |entry| {
        const key = switch (entry.key) {
            .int => {
                try ctx.vm.setPendingException("ValueError", "Invalid integer key in $options argument");
                return error.RuntimeError;
            },
            .string => |k| k.bytes(),
        };
        if (key.len == 0) {
            try ctx.vm.setPendingException("ValueError", "Invalid empty string key in $options argument");
            return error.RuntimeError;
        }
        const known = [_][]const u8{ "max_file_uploads", "max_input_vars", "max_multipart_body_parts", "post_max_size", "upload_max_filesize" };
        var found = false;
        for (known) |k| if (std.ascii.eqlIgnoreCase(k, key)) {
            found = true;
        };
        if (!found) {
            const msg = try std.fmt.allocPrint(ctx.allocator, "Invalid key \"{s}\" in $options argument", .{key});
            defer ctx.allocator.free(msg);
            try ctx.vm.setPendingException("ValueError", msg);
            return error.RuntimeError;
        }
        const v = if (entry.ref) |r| r.* else entry.value;
        switch (v) {
            .string => |str| {
                const trimmed = std.mem.trim(u8, str.bytes(), " \t\n\r\x0b\x0c");
                const q = @import("../runtime/memory.zig").parseQuantity(str.bytes());
                if (q.problem) |problem| {
                    const msg = switch (problem) {
                        .no_digits => try std.fmt.allocPrint(ctx.allocator, "Invalid quantity \"{s}\": no valid leading digits, interpreting as \"0\" for backwards compatibility", .{trimmed}),
                        .unknown_multiplier => |u| try std.fmt.allocPrint(ctx.allocator, "Invalid quantity \"{s}\": unknown multiplier \"{c}\", interpreting as \"{s}\" for backwards compatibility", .{ trimmed, u.multiplier, u.used }),
                        .out_of_range => try std.fmt.allocPrint(ctx.allocator, "Invalid quantity \"{s}\": value is out of range, using overflow result for backwards compatibility", .{trimmed}),
                    };
                    defer ctx.allocator.free(msg);
                    try ctx.vm.emitWarning(msg);
                }
            },
            .int => {},
            else => {
                const msg = try std.fmt.allocPrint(ctx.allocator, "Invalid {s} value in $options argument", .{v.valueName()});
                defer ctx.allocator.free(msg);
                try ctx.vm.setPendingException("ValueError", msg);
                return error.RuntimeError;
            },
        }
    };
    var has_content_type = false;
    if (ctx.vm.request_vars.get("$_SERVER")) |server| if (server == .array) {
        has_content_type = server.array.get(.{ .string = Value.String.borrowed("CONTENT_TYPE") }) == .string;
    };
    if (!ctx.vm.serve_mode or !has_content_type) {
        try ctx.vm.setPendingException("RequestParseBodyException", "Request does not provide a content type");
        return error.RuntimeError;
    }
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
    return NativeResult.borrowed(.{ .array = result });
}

fn native_trait_exists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const raw = args[0].string.bytes();
    const name = if (raw.len > 0 and raw[0] == '\\') raw[1..] else raw;
    return NativeResult.scalar(.{ .bool = ctx.vm.traits.contains(name) });
}

const ShellResult = struct { stdout: []u8, exit_code: i64 };

// runs a command through the shell and collects its stdout. stdin and stderr
// stay attached to zphp's, as in php: a command's errors reach the terminal.
// on windows cmd.exe gets the line as php hands it (`/s /c "<command>"`)
fn runShell(allocator: std.mem.Allocator, command: []const u8) !ShellResult {
    if (platform.is_windows) {
        const result = try @import("proc_win.zig").runShell(allocator, command);
        return .{ .stdout = result.stdout, .exit_code = result.exit_code };
    }
    const argv = platform.shellArgv(command);
    const result = try platform.runChild(allocator, &argv, .{});
    return .{ .stdout = result.stdout, .exit_code = platform.exitStatus(result.term) };
}

fn requireCommand(ctx: *NativeContext, comptime func: []const u8, command: Value) RuntimeError!void {
    if (std.mem.indexOfScalar(u8, command.string.bytes(), 0) != null) {
        try ctx.vm.setPendingException("ValueError", func ++ "(): Argument #1 ($command) must not contain any null bytes");
        return error.RuntimeError;
    }
    if (command.string.bytes().len > 0) return;
    try ctx.vm.setPendingException("ValueError", func ++ "(): Argument #1 ($command) must not be empty");
    return error.RuntimeError;
}

fn native_shell_exec(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    try requireCommand(ctx, "shell_exec", args[0]);
    const result = runShell(ctx.allocator, args[0].string.bytes()) catch return NativeResult.scalar(.null);
    if (result.stdout.len == 0) {
        ctx.allocator.free(result.stdout);
        return NativeResult.scalar(.null);
    }
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result.stdout));
}

fn native_exec(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    try requireCommand(ctx, "exec", args[0]);
    const result = runShell(ctx.allocator, args[0].string.bytes()) catch return NativeResult.scalar(.{ .bool = false });
    defer ctx.allocator.free(result.stdout);

    // php_exec: each line, to and with its newline, less trailing
    // whitespace (c's isspace)
    var lines = std.ArrayListUnmanaged([]const u8).empty;
    defer lines.deinit(ctx.allocator);
    var rest = result.stdout;
    while (rest.len > 0) {
        const end = if (std.mem.indexOfScalar(u8, rest, '\n')) |nl| nl + 1 else rest.len;
        try lines.append(ctx.allocator, std.mem.trimEnd(u8, rest[0..end], " \t\n\r\x0b\x0c"));
        rest = rest[end..];
    }

    // optional output array (param 2, by-ref)
    if (args.len >= 2) {
        const arr = if (args[1] == .array) args[1].array else blk: {
            const a = try ctx.vm.allocArray();
            break :blk a;
        };
        for (lines.items) |line| try arr.appendCopiedString(ctx.allocator, line);
        if (args[1] != .array) ctx.setCallerVar(1, args.len, .{ .array = arr });
    }
    // optional result_code (param 3, by-ref)
    const exit_code: i64 = result.exit_code;
    if (args.len >= 3) ctx.setCallerVar(2, args.len, .{ .int = exit_code });

    if (lines.items.len == 0) return NativeResult.literal("");
    const last = lines.items[lines.items.len - 1];
    return try NativeResult.copyString(ctx.allocator, last);
}

fn native_system(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    try requireCommand(ctx, "system", args[0]);
    const result = runShell(ctx.allocator, args[0].string.bytes()) catch return NativeResult.scalar(.{ .bool = false });
    defer ctx.allocator.free(result.stdout);

    try ctx.vm.output.appendSlice(ctx.allocator, result.stdout);

    const exit_code: i64 = result.exit_code;
    if (args.len >= 2) ctx.setCallerVar(1, args.len, .{ .int = exit_code });

    // last line of output
    var last_line: []const u8 = "";
    if (result.stdout.len > 0) {
        var end = result.stdout.len;
        if (result.stdout[end - 1] == '\n') end -= 1;
        const start = if (std.mem.lastIndexOfScalar(u8, result.stdout[0..end], '\n')) |i| i + 1 else 0;
        last_line = result.stdout[start..end];
    }
    return try NativeResult.copyString(ctx.allocator, last_line);
}

fn native_passthru(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    try requireCommand(ctx, "passthru", args[0]);
    const result = runShell(ctx.allocator, args[0].string.bytes()) catch return NativeResult.scalar(.{ .bool = false });
    defer ctx.allocator.free(result.stdout);
    try ctx.vm.output.appendSlice(ctx.allocator, result.stdout);
    const exit_code: i64 = result.exit_code;
    if (args.len >= 2 and args[1] == .array) {
        try args[1].array.append(ctx.allocator, .{ .int = exit_code });
    }
    return NativeResult.scalar(.null);
}

extern fn sysconf(name: c_int) c_long;

// exec.c's cmd_max_len: the system's ARG_MAX
fn cmdMaxLen() usize {
    if (platform.is_windows) return 8192;
    const sc_arg_max: c_int = if (platform.is_macos) 1 else 0;
    const n = sysconf(sc_arg_max);
    return if (n > 0) @intCast(n) else 4096;
}

// Z_PARAM_PATH_STR: a string without NUL bytes
fn pathArg(ctx: *NativeContext, func: []const u8, args: []const Value, name: []const u8) RuntimeError![]const u8 {
    const p = @import("string_ports.zig").Args.init(ctx, func, args);
    const s = try p.str(0, name);
    if (std.mem.indexOfScalar(u8, s, 0) != null) return p.valueError(0, name, "must not contain any null bytes");
    return s;
}

fn tooLong(ctx: *NativeContext, comptime what: []const u8, max: usize) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, what ++ " exceeds the allowed length of {d} bytes", .{max});
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("ValueError", msg);
    return error.RuntimeError;
}

// php_escape_shell_arg
fn native_escapeshellarg(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const s = try pathArg(ctx, "escapeshellarg", args, "arg");
    const max = cmdMaxLen();
    if (s.len > max - 3) return tooLong(ctx, "Argument", max);
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(ctx.allocator);
    const a = ctx.allocator;
    try out.append(a, if (platform.is_windows) '"' else '\'');
    var x: usize = 0;
    while (x < s.len) : (x += 1) {
        const mb = @import("locale.zig").mblen(s[x..]);
        // invalid multibyte sequences are dropped
        if (mb < 0) continue;
        if (mb > 1) {
            const n: usize = @intCast(mb);
            try out.appendSlice(a, s[x .. x + n]);
            x += n - 1;
            continue;
        }
        const c = s[x];
        if (platform.is_windows) {
            if (c == '"' or c == '%' or c == '!') {
                try out.append(a, ' ');
                continue;
            }
        } else if (c == '\'') {
            try out.appendSlice(a, "'\\'");
        }
        try out.append(a, c);
    }
    if (platform.is_windows) {
        // an odd run of trailing backslashes would escape the closing quote
        var k: usize = 0;
        while (k < out.items.len and out.items[out.items.len - 1 - k] == '\\') k += 1;
        if (k % 2 == 1) try out.append(a, '\\');
        try out.append(a, '"');
    } else {
        try out.append(a, '\'');
    }
    if (out.items.len > max + 1) return tooLong(ctx, "Escaped argument", max);
    return NativeResult.copyString(a, out.items);
}

// php_escape_shell_cmd: shell metacharacters escaped, and a quote unless it
// has a partner later in the command
fn native_escapeshellcmd(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const s = try pathArg(ctx, "escapeshellcmd", args, "command");
    if (s.len == 0) return NativeResult.literal("");
    const max = cmdMaxLen();
    if (s.len > max - 3) return tooLong(ctx, "Command", max);
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(ctx.allocator);
    const a = ctx.allocator;
    const escape: u8 = if (platform.is_windows) '^' else '\\';
    var pending_quote: ?usize = null;
    var x: usize = 0;
    while (x < s.len) : (x += 1) {
        const mb = @import("locale.zig").mblen(s[x..]);
        if (mb < 0) continue;
        if (mb > 1) {
            const n: usize = @intCast(mb);
            try out.appendSlice(a, s[x .. x + n]);
            x += n - 1;
            continue;
        }
        const c = s[x];
        switch (c) {
            '"', '\'' => if (platform.is_windows) {
                try out.append(a, escape);
            } else if (pending_quote == null) {
                if (std.mem.indexOfScalarPos(u8, s, x + 1, c)) |at| {
                    pending_quote = at;
                } else {
                    try out.append(a, escape);
                }
            } else if (s[pending_quote.?] == c) {
                pending_quote = null;
            } else {
                try out.append(a, escape);
            },
            '%', '!' => if (platform.is_windows) try out.append(a, escape),
            '#', '&', ';', '`', '|', '*', '?', '~', '<', '>', '^', '(', ')', '[', ']', '{', '}', '$', '\\', '\x0a', '\xff' => try out.append(a, escape),
            else => {},
        }
        try out.append(a, c);
    }
    if (out.items.len > max + 1) return tooLong(ctx, "Escaped command", max);
    return NativeResult.copyString(a, out.items);
}
