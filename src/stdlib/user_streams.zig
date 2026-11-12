// user stream wrappers (main/streams/userspace.c): stream_wrapper_register
// binds a scheme to a class whose methods implement the wrapper operations
// (stream_open, url_stat, unlink, rename, mkdir, rmdir, dir_opendir,
// stream_metadata) and, on the object stream_open succeeded on, the stream
// operations (stream_read, stream_write, stream_eof, stream_seek, ...)
const std = @import("std");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const PhpObject = value_mod.PhpObject;
const PhpArray = value_mod.PhpArray;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const streams = @import("streams.zig");
const fs = @import("filesystem.zig");
const filters = @import("stream_filters.zig");

const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const REPORT_ERRORS: i64 = 8;
pub const STREAM_OPEN_FOR_INCLUDE: i64 = 0x80;

const callIfExists = filters.callIfExists;

// --- the wrapper error log (php_stream_wrapper_log_error) ----------------------

threadlocal var error_log: std.ArrayListUnmanaged([]u8) = .empty;
threadlocal var error_log_allocator: ?std.mem.Allocator = null;
threadlocal var current_filename: ?[]const u8 = null;
// PG(in_user_include): a local user wrapper is opening for an include
pub threadlocal var in_user_include: bool = false;

pub fn logError(ctx: *NativeContext, options: i64, comptime fmt: []const u8, args: anytype) RuntimeError!void {
    if (options & REPORT_ERRORS != 0) return fs.warnDocref(ctx, fmt, args);
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    error_log_allocator = ctx.allocator;
    try error_log.append(ctx.allocator, msg);
}

// php_stream_display_wrapper_errors: "func(path): caption: what the wrapper
// logged" (or the given fallback), unless an exception is in flight
pub fn displayErrors(ctx: *NativeContext, path: []const u8, caption: []const u8, fallback: []const u8) RuntimeError!void {
    defer tidyErrors();
    if (ctx.vm.pending_exception != null) return;
    var msg: std.ArrayListUnmanaged(u8) = .empty;
    defer msg.deinit(ctx.allocator);
    if (error_log.items.len == 0) {
        try msg.appendSlice(ctx.allocator, fallback);
    } else for (error_log.items, 0..) |e, i| {
        if (i > 0) try msg.append(ctx.allocator, '\n');
        try msg.appendSlice(ctx.allocator, e);
    }
    try fs.warnDocrefParam(ctx, path, "{s}: {s}", .{ caption, msg.items });
}

pub fn tidyErrors() void {
    const a = error_log_allocator orelse return;
    for (error_log.items) |e| a.free(e);
    error_log.clearRetainingCapacity();
}

pub fn freeErrorLog() void {
    tidyErrors();
    if (error_log_allocator) |a| error_log.deinit(a);
    error_log = .empty;
}

pub fn hasLoggedErrors() bool {
    return error_log.items.len > 0;
}

// --- making the wrapper object ----------------------------------------------------

// user_stream_create_object: an instance with its context property, then
// its constructor. null when the class can't be instantiated
fn createObject(ctx: *NativeContext, class: []const u8, context: ?*PhpObject) RuntimeError!?*PhpObject {
    const def = ctx.vm.classes.get(class) orelse return null;
    if (def.is_abstract or def.is_enum) return null;
    const obj = try ctx.createObject(class);
    obj.retain();
    errdefer ctx.vm.releaseValue(.{ .object = obj });
    if (!try filters.assignTypedProperty(ctx, obj, "context", if (context) |c| .{ .resource = c } else .null)) return error.RuntimeError;
    if (ctx.vm.hasMethod(class, "__construct")) _ = try ctx.vm.callMethod(obj, "__construct", &.{});
    return obj;
}

fn releaseObject(ctx: *NativeContext, obj: *PhpObject) void {
    ctx.vm.releaseValue(.{ .object = obj });
}

fn str(ctx: *NativeContext, bytes: []const u8) RuntimeError!Value {
    return .{ .string = try Value.String.adopt(ctx.allocator, try ctx.allocator.dupe(u8, bytes)) };
}

fn className(ctx: *NativeContext, obj: *PhpObject) []const u8 {
    return ctx.vm.declaredClassName(obj.class_name);
}

// --- wrapper operations -------------------------------------------------------------

pub const Opened = struct { stream: *PhpObject, opened_path: ?[]u8 = null };

// user_wrapper_opener: the FileHandle for a stream the wrapper opened, or
// null with the reason in the error log
pub fn open(ctx: *NativeContext, class: []const u8, path: []const u8, mode: []const u8, options: i64, context: ?*PhpObject) RuntimeError!?Opened {
    if (current_filename) |cur| if (std.mem.eql(u8, cur, path)) {
        try logError(ctx, options, "infinite recursion prevented", .{});
        return null;
    };
    current_filename = path;
    defer current_filename = null;
    const obj = (try createObject(ctx, class, context)) orelse return null;
    defer releaseObject(ctx, obj);
    var args = [_]Value{ try str(ctx, path), try str(ctx, mode), .{ .int = options }, .null };
    const has = ctx.vm.hasMethod(obj.class_name, "stream_open") or ctx.vm.hasMethod(obj.class_name, "__call");
    if (!has) {
        for (args[0..2]) |a| ctx.vm.releaseValue(a);
        try logError(ctx, options, "\"{s}::stream_open\" is not implemented", .{className(ctx, obj)});
        return null;
    }
    const ret = if (ctx.vm.hasMethod(obj.class_name, "stream_open"))
        try ctx.vm.callMethodRef(obj, "stream_open", &args)
    else
        (try callIfExists(ctx, obj, "stream_open", args[0..3])).?;
    defer for (args) |a| ctx.vm.releaseValue(a);
    if (!ret.isTruthy()) {
        try logError(ctx, options, "\"{s}::stream_open\" call failed", .{className(ctx, obj)});
        return null;
    }
    const fh = try ctx.createResource("FileHandle");
    try fh.set(ctx.allocator, "__wrapper_obj", .{ .object = obj });
    try fh.set(ctx.allocator, "__open", .{ .bool = true });
    try fh.setCopiedString(ctx.allocator, "__mode", mode);
    try fh.setCopiedString(ctx.allocator, "__path", path);
    _ = try streams.attach(ctx, fh, .{});
    var opened: Opened = .{ .stream = fh };
    if (args[3] == .string) opened.opened_path = try ctx.allocator.dupe(u8, args[3].string.bytes());
    return opened;
}

pub fn opendir(ctx: *NativeContext, class: []const u8, path: []const u8, options: i64, context: ?*PhpObject) RuntimeError!?*PhpObject {
    if (current_filename) |cur| if (std.mem.eql(u8, cur, path)) {
        try logError(ctx, options, "infinite recursion prevented", .{});
        return null;
    };
    current_filename = path;
    defer current_filename = null;
    const obj = (try createObject(ctx, class, context)) orelse return null;
    defer releaseObject(ctx, obj);
    const p = try str(ctx, path);
    defer ctx.vm.releaseValue(p);
    const ret = (try callIfExists(ctx, obj, "dir_opendir", &.{ p, .{ .int = options } })) orelse {
        try logError(ctx, options, "\"{s}::dir_opendir\" is not implemented", .{className(ctx, obj)});
        return null;
    };
    if (!ret.isTruthy()) {
        try logError(ctx, options, "\"{s}::dir_opendir\" call failed", .{className(ctx, obj)});
        return null;
    }
    const dh = try ctx.createResource("DirectoryHandle");
    try dh.set(ctx.allocator, "__wrapper_obj", .{ .object = obj });
    try dh.set(ctx.allocator, "__open", .{ .bool = true });
    try dh.setCopiedString(ctx.allocator, "__path", path);
    return dh;
}

// the next entry dir_readdir names, owned by the caller; null at the end
pub fn readdir(ctx: *NativeContext, w: *PhpObject) RuntimeError!?Value.String {
    const ret = (try callIfExists(ctx, w, "dir_readdir", &.{})) orelse {
        try fs.warnDocref(ctx, "{s}::dir_readdir is not implemented!", .{className(ctx, w)});
        return null;
    };
    if (ret == .bool) return null;
    return try Value.String.adopt(ctx.allocator, try filters.toOwnedString(ctx, ret));
}

pub fn rewinddir(ctx: *NativeContext, w: *PhpObject) RuntimeError!void {
    _ = try callIfExists(ctx, w, "dir_rewinddir", &.{});
}

pub fn closedir(ctx: *NativeContext, w: *PhpObject) RuntimeError!void {
    _ = try callIfExists(ctx, w, "dir_closedir", &.{});
}

fn boolResult(ret: ?Value) bool {
    const v = ret orelse return false;
    return v == .bool and v.bool;
}

pub fn unlink(ctx: *NativeContext, class: []const u8, url: []const u8, context: ?*PhpObject) RuntimeError!bool {
    const obj = (try createObject(ctx, class, context)) orelse return false;
    defer releaseObject(ctx, obj);
    const u = try str(ctx, url);
    defer ctx.vm.releaseValue(u);
    const ret = try callIfExists(ctx, obj, "unlink", &.{u});
    if (ret == null) try fs.warnDocref(ctx, "{s}::unlink is not implemented!", .{className(ctx, obj)});
    return boolResult(ret);
}

pub fn rename(ctx: *NativeContext, class: []const u8, from: []const u8, to: []const u8, context: ?*PhpObject) RuntimeError!bool {
    const obj = (try createObject(ctx, class, context)) orelse return false;
    defer releaseObject(ctx, obj);
    const a = try str(ctx, from);
    defer ctx.vm.releaseValue(a);
    const b = try str(ctx, to);
    defer ctx.vm.releaseValue(b);
    const ret = try callIfExists(ctx, obj, "rename", &.{ a, b });
    if (ret == null) try fs.warnDocref(ctx, "{s}::rename is not implemented!", .{className(ctx, obj)});
    return boolResult(ret);
}

pub fn mkdir(ctx: *NativeContext, class: []const u8, url: []const u8, mode: i64, options: i64, context: ?*PhpObject) RuntimeError!bool {
    const obj = (try createObject(ctx, class, context)) orelse return false;
    defer releaseObject(ctx, obj);
    const u = try str(ctx, url);
    defer ctx.vm.releaseValue(u);
    const ret = try callIfExists(ctx, obj, "mkdir", &.{ u, .{ .int = mode }, .{ .int = options } });
    if (ret == null) try fs.warnDocref(ctx, "{s}::mkdir is not implemented!", .{className(ctx, obj)});
    return boolResult(ret);
}

pub fn rmdir(ctx: *NativeContext, class: []const u8, url: []const u8, options: i64, context: ?*PhpObject) RuntimeError!bool {
    const obj = (try createObject(ctx, class, context)) orelse return false;
    defer releaseObject(ctx, obj);
    const u = try str(ctx, url);
    defer ctx.vm.releaseValue(u);
    const ret = try callIfExists(ctx, obj, "rmdir", &.{ u, .{ .int = options } });
    if (ret == null) try fs.warnDocref(ctx, "{s}::rmdir is not implemented!", .{className(ctx, obj)});
    return boolResult(ret);
}

pub const META_TOUCH: i64 = 1;
pub const META_OWNER_NAME: i64 = 2;
pub const META_OWNER: i64 = 3;
pub const META_GROUP_NAME: i64 = 4;
pub const META_GROUP: i64 = 5;
pub const META_ACCESS: i64 = 6;

// user_wrapper_metadata: value is the touch times (an array), an id, a mode
// or a name, as the option says
pub fn metadata(ctx: *NativeContext, class: []const u8, url: []const u8, option: i64, value: Value) RuntimeError!bool {
    const obj = (try createObject(ctx, class, null)) orelse return false;
    defer releaseObject(ctx, obj);
    const u = try str(ctx, url);
    defer ctx.vm.releaseValue(u);
    const ret = try callIfExists(ctx, obj, "stream_metadata", &.{ u, .{ .int = option }, value });
    if (ret == null) try fs.warnDocref(ctx, "{s}::stream_metadata is not implemented!", .{className(ctx, obj)});
    return boolResult(ret);
}

// user_wrapper_stat_url: the array url_stat returned, or null
pub fn urlStat(ctx: *NativeContext, class: []const u8, url: []const u8, flags: i64) RuntimeError!?*PhpArray {
    const obj = (try createObject(ctx, class, null)) orelse return null;
    defer releaseObject(ctx, obj);
    const u = try str(ctx, url);
    defer ctx.vm.releaseValue(u);
    const ret = (try callIfExists(ctx, obj, "url_stat", &.{ u, .{ .int = flags } })) orelse {
        try fs.warnDocref(ctx, "{s}::url_stat is not implemented!", .{className(ctx, obj)});
        return null;
    };
    if (ret == .array) return ret.array;
    return null;
}

// --- stream operations ----------------------------------------------------------------

pub fn read(ctx: *NativeContext, stream_obj: *PhpObject, s: *streams.Stream, w: *PhpObject, dest: []u8) RuntimeError!isize {
    _ = stream_obj;
    s.busy += 1;
    defer s.busy -= 1;
    const ret = (try callIfExists(ctx, w, "stream_read", &.{.{ .int = @intCast(dest.len) }})) orelse {
        try fs.warnDocref(ctx, "{s}::stream_read is not implemented!", .{className(ctx, w)});
        return -1;
    };
    if (ret == .bool and !ret.bool) return -1;
    var didread: usize = 0;
    {
        const bytes = try filters.toOwnedString(ctx, ret);
        defer ctx.allocator.free(bytes);
        didread = bytes.len;
        if (didread > 0) {
            if (didread > dest.len) {
                try fs.warnDocref(ctx, "{s}::stream_read - read {d} bytes more data than requested ({d} read, {d} max) - excess data will be lost", .{ className(ctx, w), didread - dest.len, didread, dest.len });
                didread = dest.len;
            }
            @memcpy(dest[0..didread], bytes[0..didread]);
        }
    }
    const eof_ret = (try callIfExists(ctx, w, "stream_eof", &.{})) orelse {
        try fs.warnDocref(ctx, "{s}::stream_eof is not implemented! Assuming EOF", .{className(ctx, w)});
        s.eof = true;
        return -1;
    };
    if (eof_ret.isTruthy()) s.eof = true;
    return @intCast(didread);
}

pub fn write(ctx: *NativeContext, stream_obj: *PhpObject, s: *streams.Stream, w: *PhpObject, data: []const u8) RuntimeError!isize {
    _ = stream_obj;
    s.busy += 1;
    defer s.busy -= 1;
    const arg = try str(ctx, data);
    defer ctx.vm.releaseValue(arg);
    const ret = (try callIfExists(ctx, w, "stream_write", &.{arg})) orelse {
        try fs.warnDocref(ctx, "{s}::stream_write is not implemented!", .{className(ctx, w)});
        return -1;
    };
    if (ret == .bool and !ret.bool) return -1;
    var didwrite = Value.toInt(ret);
    if (didwrite > 0 and didwrite > data.len) {
        try fs.warnDocref(ctx, "{s}::stream_write wrote {d} bytes more data than requested ({d} written, {d} max)", .{ className(ctx, w), didwrite - @as(i64, @intCast(data.len)), didwrite, data.len });
        didwrite = @intCast(data.len);
    }
    return @intCast(didwrite);
}

pub fn seek(ctx: *NativeContext, stream_obj: *PhpObject, s: *streams.Stream, w: *PhpObject, offset: i64, whence: u2) RuntimeError!?i64 {
    _ = stream_obj;
    s.busy += 1;
    defer s.busy -= 1;
    const ret = (try callIfExists(ctx, w, "stream_seek", &.{ .{ .int = offset }, .{ .int = whence } })) orelse {
        s.no_seek = true;
        return null;
    };
    if (!ret.isTruthy()) return null;
    const pos = (try callIfExists(ctx, w, "stream_tell", &.{})) orelse {
        try fs.warnDocref(ctx, "{s}::stream_tell is not implemented!", .{className(ctx, w)});
        return null;
    };
    if (pos != .int) return null;
    return pos.int;
}

pub fn flush(ctx: *NativeContext, w: *PhpObject) RuntimeError!bool {
    const ret = (try callIfExists(ctx, w, "stream_flush", &.{})) orelse return false;
    return ret.isTruthy();
}

pub fn close(ctx: *NativeContext, stream_obj: *PhpObject, w: *PhpObject) RuntimeError!void {
    _ = stream_obj;
    _ = try callIfExists(ctx, w, "stream_close", &.{});
}

// PHP_STREAM_OPTION_CHECK_LIVENESS: true when the stream says it is at eof
pub fn checkLiveness(ctx: *NativeContext, stream_obj: *PhpObject, s: *streams.Stream, w: *PhpObject) RuntimeError!bool {
    _ = stream_obj;
    _ = s;
    const ret = (try callIfExists(ctx, w, "stream_eof", &.{})) orelse {
        try fs.warnDocref(ctx, "{s}::stream_eof is not implemented! Assuming EOF", .{className(ctx, w)});
        return true;
    };
    if (ret == .bool) return ret.bool;
    try fs.warnDocref(ctx, "{s}::stream_eof value must be of type bool, {s} given", .{ className(ctx, w), ret.valueName() });
    return true;
}

pub fn stat(ctx: *NativeContext, w: *PhpObject) RuntimeError!?*PhpArray {
    const ret = (try callIfExists(ctx, w, "stream_stat", &.{})) orelse {
        try fs.warnDocref(ctx, "{s}::stream_stat is not implemented!", .{className(ctx, w)});
        return null;
    };
    if (ret == .array) return ret.array;
    return null;
}

pub const OptionResult = enum { ok, err, notimpl };

// stream_lock: php's LOCK_* numbering differs from flock(2)'s
pub fn lock(ctx: *NativeContext, w: *PhpObject, operation: i64) RuntimeError!OptionResult {
    var op: i64 = 0;
    if (operation & 4 != 0) op |= 4;
    switch (operation & ~@as(i64, 4)) {
        1 => op |= 1,
        2 => op |= 2,
        8 => op |= 3,
        else => {},
    }
    const ret = (try callIfExists(ctx, w, "stream_lock", &.{.{ .int = op }})) orelse {
        if (operation == 0) return .ok;
        try fs.warnDocref(ctx, "{s}::stream_lock is not implemented!", .{className(ctx, w)});
        return .err;
    };
    if (ret == .bool) return if (ret.bool) .ok else .err;
    return .notimpl;
}

pub fn truncateSupported(ctx: *NativeContext, w: *PhpObject) bool {
    return ctx.vm.hasMethod(w.class_name, "stream_truncate") or ctx.vm.hasMethod(w.class_name, "__call");
}

pub fn truncate(ctx: *NativeContext, w: *PhpObject, size: i64) RuntimeError!OptionResult {
    const ret = (try callIfExists(ctx, w, "stream_truncate", &.{.{ .int = size }})) orelse {
        try fs.warnDocref(ctx, "{s}::stream_truncate is not implemented!", .{className(ctx, w)});
        return .err;
    };
    if (ret == .bool) return if (ret.bool) .ok else .err;
    try fs.warnDocref(ctx, "{s}::stream_truncate value must be of type bool, {s} given", .{ className(ctx, w), ret.valueName() });
    return .err;
}

pub const OPTION_BLOCKING: i64 = 1;
pub const OPTION_READ_BUFFER: i64 = 2;
pub const OPTION_WRITE_BUFFER: i64 = 3;
pub const OPTION_READ_TIMEOUT: i64 = 4;

pub fn setOption(ctx: *NativeContext, w: *PhpObject, option: i64, value: i64, extra: Value) RuntimeError!OptionResult {
    const ret = (try callIfExists(ctx, w, "stream_set_option", &.{ .{ .int = option }, .{ .int = value }, extra })) orelse {
        try fs.warnDocref(ctx, "{s}::stream_set_option is not implemented!", .{className(ctx, w)});
        return .err;
    };
    return if (ret.isTruthy()) .ok else .err;
}

pub const CAST_FOR_SELECT: i64 = 3;
pub const CAST_AS_STREAM: i64 = 0;

// php_userstreamop_cast: the stream stream_cast hands back, checked; null
// when there is none (with php's warnings when report is set)
pub fn cast(ctx: *NativeContext, stream_obj: *PhpObject, w: *PhpObject, castas: i64, report: bool) RuntimeError!?*PhpObject {
    const s = streams.get(stream_obj);
    if (s) |st| st.busy += 1;
    defer if (s) |st| {
        st.busy -= 1;
    };
    const ret = (try callIfExists(ctx, w, "stream_cast", &.{.{ .int = castas }})) orelse {
        if (report) try fs.warnDocref(ctx, "{s}::stream_cast is not implemented!", .{className(ctx, w)});
        return null;
    };
    if (!ret.isTruthy()) return null;
    if (ret != .resource or !std.mem.eql(u8, ret.resource.class_name, "FileHandle") or value_mod.resourceClosed(ret.resource)) {
        if (report) try fs.warnDocref(ctx, "{s}::stream_cast must return a stream resource", .{className(ctx, w)});
        return null;
    }
    if (ret.resource == stream_obj) {
        if (report) try fs.warnDocref(ctx, "{s}::stream_cast must not return itself", .{className(ctx, w)});
        return null;
    }
    return ret.resource;
}
