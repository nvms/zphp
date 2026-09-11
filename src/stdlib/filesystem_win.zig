// the windows side of the filesystem natives that are posix calls on other
// platforms. ownership, modes, links, and process pipes either have no
// windows equivalent (php returns false there too) or are on the roadmap
const std = @import("std");
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
    .{ "stat", native_stat },
    .{ "lstat", native_stat },
    .{ "flock", native_flock },
    .{ "popen", unsupported },
    .{ "pclose", unsupported },
    .{ "proc_open", unsupported },
    .{ "proc_close", unsupported },
    .{ "proc_get_status", unsupported },
    .{ "proc_terminate", unsupported },
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
    const st = std.fs.cwd().statFile(args[0].string.bytes()) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = st.kind == .sym_link });
}

// php's stat() shape from what windows reports: no owner, no inode, no
// block accounting
fn native_stat(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const st = @import("../platform.zig").statPath(args[0].string.bytes()) catch return NativeResult.scalar(.{ .bool = false });
    const mode: i64 = @intCast(@import("../platform.zig").modeOf(st));
    const size: i64 = @intCast(st.size);
    const atime: i64 = @intCast(@divTrunc(st.atime, std.time.ns_per_s));
    const mtime: i64 = @intCast(@divTrunc(st.mtime, std.time.ns_per_s));
    const ctime: i64 = @intCast(@divTrunc(st.ctime, std.time.ns_per_s));
    const pairs = [_]struct { name: []const u8, val: i64 }{
        .{ .name = "dev", .val = 0 },       .{ .name = "ino", .val = 0 },
        .{ .name = "mode", .val = mode },   .{ .name = "nlink", .val = 1 },
        .{ .name = "uid", .val = 0 },       .{ .name = "gid", .val = 0 },
        .{ .name = "rdev", .val = 0 },      .{ .name = "size", .val = size },
        .{ .name = "atime", .val = atime }, .{ .name = "mtime", .val = mtime },
        .{ .name = "ctime", .val = ctime }, .{ .name = "blksize", .val = -1 },
        .{ .name = "blocks", .val = -1 },
    };
    var arr = try ctx.createArray();
    for (pairs, 0..) |p, i| {
        try arr.set(ctx.allocator, .{ .int = @intCast(i) }, .{ .int = p.val });
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(p.name) }, .{ .int = p.val });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_flock(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .object or args[1] != .int) return NativeResult.scalar(.{ .bool = false });
    const fd = args[0].object.get("__fd");
    if (fd != .int) return NativeResult.scalar(.{ .bool = false });
    const file = @import("../platform.zig").fileFromFd(fd.int) orelse return NativeResult.scalar(.{ .bool = false });
    const op = args[1].int & 0x3;
    const non_block = (args[1].int & 4) != 0;
    switch (op) {
        1, 2 => {
            // std's tryLock does not compile for windows in zig 0.15.1, so a
            // non-blocking request waits like a blocking one
            _ = non_block;
            const lock: std.fs.File.Lock = if (op == 1) .shared else .exclusive;
            file.lock(lock) catch return NativeResult.scalar(.{ .bool = false });
            return NativeResult.scalar(.{ .bool = true });
        },
        3 => {
            file.unlock();
            return NativeResult.scalar(.{ .bool = true });
        },
        else => return NativeResult.scalar(.{ .bool = false }),
    }
}

// php on windows accepts the call for its own memory and temp streams and
// refuses it for plain files; sockets wait for the serve port
fn native_stream_set_blocking(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const path = args[0].object.get("__path");
    return NativeResult.scalar(.{ .bool = path == .string and std.mem.startsWith(u8, path.string.bytes(), "php://") });
}
