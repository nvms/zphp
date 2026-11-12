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
    const ident = try p.str(0, "prefix");
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

fn native_closelog(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = ctx;
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
    try logStr(ctx, priority, message);
    return NativeResult.scalar(.{ .bool = true });
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
    if (!have_called_openlog) {
        openlog("php", 0, 8);
        have_called_openlog = true;
    }
    try logStr(ctx, priority, message);
}
