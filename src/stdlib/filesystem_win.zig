// the windows side of the filesystem natives that are posix calls on other
// platforms. ownership, modes, and links have no windows equivalent (php
// returns false there too); processes go through proc_win.zig
const std = @import("std");
const platform = @import("../platform.zig");
const filesystem = @import("filesystem.zig");
const proc_win = @import("proc_win.zig");
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "chown", unsupported },
    .{ "chgrp", unsupported },
    .{ "lchown", unsupported },
    .{ "lchgrp", unsupported },
    .{ "umask", zero },
    .{ "fileowner", zero },
    .{ "filegroup", zero },
    .{ "is_link", native_is_link },
    .{ "symlink", unsupported },
    .{ "link", unsupported },
    .{ "flock", native_flock },
    .{ "popen", filesystem.native_popen },
    .{ "pclose", filesystem.native_pclose },
    .{ "proc_open", proc_win.native_proc_open },
    .{ "proc_close", proc_win.native_proc_close },
    .{ "proc_get_status", proc_win.native_proc_get_status },
    .{ "proc_terminate", proc_win.native_proc_terminate },
    .{ "stream_set_blocking", native_stream_set_blocking },
};

fn unsupported(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = false });
}

fn zero(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = 0 });
}

fn native_is_link(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const st = std.Io.Dir.cwd().statFile(platform.io, args[0].string.bytes(), .{}) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = st.kind == .sym_link });
}

fn native_flock(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try filesystem.streamArg(ctx, args, .{ .func = "flock" });
    const operation = try filesystem.flockOperation(ctx, args);
    if (try filesystem.userLock(ctx, obj, operation.kind, operation.non_block)) |r| return r;
    const fd = obj.get("__fd");
    if (fd != .int) return NativeResult.scalar(.{ .bool = false });
    const file = @import("../platform.zig").fileFromFd(fd.int) orelse return NativeResult.scalar(.{ .bool = false });
    const op = operation.kind;
    const non_block = operation.non_block;
    switch (op) {
        1, 2 => {
            // std's tryLock does not compile for windows in zig 0.15.1, so a
            // non-blocking request waits like a blocking one
            _ = non_block;
            const lock: std.Io.File.Lock = if (op == 1) .shared else .exclusive;
            file.lock(platform.io, lock) catch return NativeResult.scalar(.{ .bool = false });
            return NativeResult.scalar(.{ .bool = true });
        },
        3 => {
            file.unlock(platform.io);
            return NativeResult.scalar(.{ .bool = true });
        },
        else => return NativeResult.scalar(.{ .bool = false }),
    }
}

// sockets switch modes; php's own memory and temp streams accept the call;
// a plain file refuses it, as php does on windows
fn native_stream_set_blocking(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try filesystem.streamArg(ctx, args, .{ .func = "stream_set_blocking" });
    if (args.len < 2) return NativeResult.scalar(.{ .bool = false });
    if (try filesystem.userSetBlocking(ctx, obj, args[1].isTruthy())) |r| return r;
    const net = obj.get("__net");
    if (net == .bool and net.bool) {
        const fd = obj.get("__fd");
        if (fd != .int) return NativeResult.scalar(.{ .bool = false });
        const sock = platform.socketFromInt(fd.int) orelse return NativeResult.scalar(.{ .bool = false });
        platform.setNonBlocking(sock, !args[1].isTruthy()) catch return NativeResult.scalar(.{ .bool = false });
        try obj.set(ctx.allocator, "__blocking", .{ .bool = args[1].isTruthy() });
        return NativeResult.scalar(.{ .bool = true });
    }
    const path = obj.get("__path");
    return NativeResult.scalar(.{ .bool = path == .string and std.mem.startsWith(u8, path.string.bytes(), "php://") });
}

// php_win32_stream_wrapper_warn_error's text: the system's message for the
// error without its trailing line break and period, then the code
pub fn errorMessage(buf: []u8, code: u32) []const u8 {
    var text_buf: [1024]u8 = undefined;
    return std.fmt.bufPrint(buf, "{s} (code: {d})", .{ systemMessage(&text_buf, code), code }) catch "";
}

// php_win32_error_to_msg: FormatMessage's text without its trailing line
// break and period
pub fn systemMessage(buf: []u8, code: u32) []const u8 {
    const win32 = @import("../win32.zig");
    var wide: [512]u16 = undefined;
    const n = win32.FormatMessageW(win32.FORMAT_MESSAGE_FROM_SYSTEM | win32.FORMAT_MESSAGE_IGNORE_INSERTS, null, code, 0, &wide, wide.len, null);
    var text: []const u16 = wide[0..n];
    while (text.len > 0 and (text[text.len - 1] == '\r' or text[text.len - 1] == '\n' or text[text.len - 1] == '.')) text = text[0 .. text.len - 1];
    const len = std.unicode.utf16LeToUtf8(buf, text) catch 0;
    return buf[0..len];
}

// the GetLastError code behind an error std reported for a file operation
pub fn errorCode(err: anyerror) u32 {
    return switch (err) {
        error.FileNotFound => 2, // ERROR_FILE_NOT_FOUND
        error.AccessDenied, error.PermissionDenied, error.IsDir => 5, // ERROR_ACCESS_DENIED
        error.FileBusy, error.DeviceBusy => 32, // ERROR_SHARING_VIOLATION
        error.NetworkNotFound => 53, // ERROR_BAD_NETPATH
        error.NotSameFileSystem, error.CrossDevice => 17, // ERROR_NOT_SAME_DEVICE
        error.BadPathName, error.InvalidArgument => 123, // ERROR_INVALID_NAME
        error.PathAlreadyExists => 183, // ERROR_ALREADY_EXISTS
        error.NameTooLong => 206, // ERROR_FILENAME_EXCED_RANGE
        error.NotDir => 267, // ERROR_DIRECTORY
        error.DirNotEmpty => 145, // ERROR_DIR_NOT_EMPTY
        error.NoSpaceLeft => 112, // ERROR_DISK_FULL
        else => 31, // ERROR_GEN_FAILURE
    };
}
