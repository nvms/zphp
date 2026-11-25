// php's ext/standard/syslog.c and main/php_syslog.c over the c library's
// syslog(3). windows has no syslog(3); there the functions only succeed
const std = @import("std");
const builtin = @import("builtin");
const Value = @import("../runtime/value.zig").Value;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const Args = @import("string_ports.zig").Args;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "openlog", native_openlog },
    .{ "syslog", native_syslog },
    .{ "closelog", native_closelog },
};

const has_syslog = builtin.os.tag != .windows;

extern "c" fn openlog(ident: ?[*:0]const u8, option: c_int, facility: c_int) void;
extern "c" fn syslog(priority: c_int, format: [*:0]const u8, ...) void;
extern "c" fn closelog() void;

// openlog keeps the ident pointer, so it lives until the next openlog or
// closelog (php's BG(syslog_device))
threadlocal var ident_buf: ?[:0]u8 = null;
threadlocal var have_called_openlog = false;

fn dropIdent() void {
    if (ident_buf) |b| std.heap.c_allocator.free(b);
    ident_buf = null;
}

fn native_openlog(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "openlog", args);
    const ident = try p.path(0, "prefix");
    const option = try p.longAs(1, "flags", "int");
    const facility = try p.longAs(2, "facility", "int");
    if (has_syslog) {
        const z = try std.heap.c_allocator.dupeSentinel(u8, ident[0 .. std.mem.indexOfScalar(u8, ident, 0) orelse ident.len], 0);
        openlog(z.ptr, @truncate(option), @truncate(facility));
        dropIdent();
        ident_buf = z;
        have_called_openlog = true;
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn native_closelog(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = args;
    if (has_syslog) {
        closelog();
        have_called_openlog = false;
        dropIdent();
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn native_syslog(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "syslog", args);
    const priority = try p.longAs(0, "priority", "int");
    const message = try p.str(1, "message");
    // a log openlog() didn't open is opened with syslog.ident and
    // syslog.facility, and so closed at the request's end (php 8.5.13)
    openDefault();
    try logStr(ctx, priority, message);
    return NativeResult.scalar(.{ .bool = true });
}

// php_openlog(PG(syslog_ident), 0, PG(syslog_facility)) unless the log is
// open already
fn openDefault() void {
    if (!has_syslog or have_called_openlog) return;
    const ini = @import("../ini_config.zig");
    const ident = ini.get("syslog.ident") orelse "php";
    const z = std.heap.c_allocator.dupeSentinel(u8, ident[0 .. std.mem.indexOfScalar(u8, ident, 0) orelse ident.len], 0) catch return;
    openlog(z.ptr, 0, facilityCode(ini.get("syslog.facility") orelse "LOG_USER"));
    dropIdent();
    ident_buf = z;
    have_called_openlog = true;
}

// OnSetFacility's names; LOG_USER for anything else
fn facilityCode(name: []const u8) c_int {
    const table = [_]struct { []const u8, []const u8, c_int }{
        .{ "LOG_AUTH", "auth", 4 << 3 },      .{ "LOG_AUTHPRIV", "authpriv", 10 << 3 },
        .{ "LOG_CRON", "cron", 9 << 3 },      .{ "LOG_DAEMON", "daemon", 3 << 3 },
        .{ "LOG_FTP", "ftp", 11 << 3 },       .{ "LOG_KERN", "kern", 0 },
        .{ "LOG_LPR", "lpr", 6 << 3 },        .{ "LOG_MAIL", "mail", 2 << 3 },
        .{ "LOG_NEWS", "news", 7 << 3 },      .{ "LOG_SYSLOG", "syslog", 5 << 3 },
        .{ "LOG_USER", "user", 1 << 3 },      .{ "LOG_UUCP", "uucp", 8 << 3 },
        .{ "LOG_LOCAL0", "local0", 16 << 3 }, .{ "LOG_LOCAL1", "local1", 17 << 3 },
        .{ "LOG_LOCAL2", "local2", 18 << 3 }, .{ "LOG_LOCAL3", "local3", 19 << 3 },
        .{ "LOG_LOCAL4", "local4", 20 << 3 }, .{ "LOG_LOCAL5", "local5", 21 << 3 },
        .{ "LOG_LOCAL6", "local6", 22 << 3 }, .{ "LOG_LOCAL7", "local7", 23 << 3 },
    };
    if (std.mem.eql(u8, name, "security")) return 4 << 3;
    for (table) |e| if (std.mem.eql(u8, name, e[0]) or std.mem.eql(u8, name, e[1])) return e[2];
    return 1 << 3;
}

// PHP_RSHUTDOWN_FUNCTION(syslog): a log php opened is closed with the
// request; one it never opened is left alone
pub fn endRequest() void {
    if (!has_syslog or !have_called_openlog) return;
    closelog();
    have_called_openlog = false;
    dropIdent();
}

const Filter = enum { all, no_ctrl, ascii, raw };

fn filterSetting(ctx: *NativeContext) Filter {
    const v = ctx.vm.ini_settings.get("syslog.filter") orelse return .no_ctrl;
    if (std.mem.eql(u8, v, "all")) return .all;
    if (std.mem.eql(u8, v, "ascii")) return .ascii;
    if (std.mem.eql(u8, v, "raw")) return .raw;
    return .no_ctrl;
}

fn emit(priority: i64, line: []const u8) void {
    const z = std.heap.c_allocator.dupeSentinel(u8, line, 0) catch return;
    defer std.heap.c_allocator.free(z);
    syslog(@truncate(priority), "%s", z.ptr);
}

// php_syslog_str: each line separately, unprintable bytes as \xNN
pub fn logStr(ctx: *NativeContext, priority: i64, message: []const u8) RuntimeError!void {
    if (!has_syslog) return;
    // LOG_PERROR writes to stderr, after what the script printed so far
    ctx.vm.flushOutputToStdout();
    const filter = filterSetting(ctx);
    if (filter == .raw) {
        emit(priority, message[0 .. std.mem.indexOfScalar(u8, message, 0) orelse message.len]);
        return;
    }
    var line = std.ArrayListUnmanaged(u8).empty;
    defer line.deinit(ctx.allocator);
    const xdigits = "0123456789abcdef";
    for (message) |c| {
        if (c >= 0x20 and c <= 0x7e) {
            try line.append(ctx.allocator, c);
        } else if (c >= 0x80 and filter != .ascii) {
            try line.append(ctx.allocator, c);
        } else if (c == '\n') {
            emit(priority, line.items);
            line.clearRetainingCapacity();
        } else if (c < 0x20 and filter == .all) {
            try line.append(ctx.allocator, c);
        } else {
            try line.appendSlice(ctx.allocator, &.{ '\\', 'x', xdigits[c >> 4], xdigits[c & 0xf] });
        }
    }
    emit(priority, line.items);
}

// php_syslog: opens the log with syslog.ident and syslog.facility first
pub fn log(ctx: *NativeContext, priority: i64, message: []const u8) RuntimeError!void {
    if (!has_syslog) return;
    openDefault();
    try logStr(ctx, priority, message);
}
