const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "session_start", native_session_start },
    .{ "session_id", native_session_id },
    .{ "session_destroy", native_session_destroy },
    .{ "session_regenerate_id", native_session_regenerate_id },
    .{ "session_name", native_session_name },
    .{ "session_status", native_session_status },
    .{ "session_write_close", native_session_write_close },
    .{ "session_unset", native_session_unset },
};

const session_dir = "/tmp";
const default_name = "PHPSESSID";

fn getSessionVar(ctx: *NativeContext, key: []const u8) ?Value {
    if (ctx.vm.frame_count == 0) return null;
    return ctx.vm.frames[0].vars.get(key);
}

fn setSessionVar(ctx: *NativeContext, key: []const u8, val: Value) !void {
    try ctx.vm.frames[0].vars.put(ctx.allocator, key, val);
}

fn generateId(ctx: *NativeContext) ![]const u8 {
    const ts: u64 = @intCast(std.time.milliTimestamp());
    var buf: [64]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{x}{x}", .{ ts, ts *% 0x517cc1b727220a95 }) catch return error.RuntimeError;
    return ctx.createString(s);
}

fn sessionPath(a: std.mem.Allocator, sid: []const u8) ![]const u8 {
    return std.mem.concat(a, u8, &.{ session_dir, "/sess_", sid });
}

fn loadSessionData(ctx: *NativeContext, sid: []const u8) !*PhpArray {
    const arr = try ctx.createArray();
    const path = try sessionPath(ctx.allocator, sid);
    defer ctx.allocator.free(path);

    const data = std.fs.cwd().readFileAlloc(ctx.allocator, path, 1024 * 1024) catch return arr;
    defer ctx.allocator.free(data);

    // simple format: key\0value\0key\0value\0...
    var pos: usize = 0;
    while (pos < data.len) {
        const key_end = std.mem.indexOfPos(u8, data, pos, "\x00") orelse break;
        const key = try ctx.createString(data[pos..key_end]);
        pos = key_end + 1;
        const val_end = std.mem.indexOfPos(u8, data, pos, "\x00") orelse break;
        const val = try ctx.createString(data[pos..val_end]);
        try arr.set(ctx.allocator, .{ .string = key }, .{ .string = val });
        pos = val_end + 1;
    }
    return arr;
}

fn saveSessionData(ctx: *NativeContext, sid: []const u8) !void {
    const session_val = ctx.vm.frames[0].vars.get("$_SESSION") orelse return;
    if (session_val != .array) return;
    const arr = session_val.array;

    var buf = std.ArrayListUnmanaged(u8){};
    for (arr.entries.items) |entry| {
        const key_str = switch (entry.key) {
            .string => |s| s,
            .int => |n| blk: {
                var tmp: [20]u8 = undefined;
                break :blk std.fmt.bufPrint(&tmp, "{d}", .{n}) catch continue;
            },
        };
        try buf.appendSlice(ctx.allocator, key_str);
        try buf.append(ctx.allocator, 0);

        if (entry.value == .string) {
            try buf.appendSlice(ctx.allocator, entry.value.string);
        } else {
            var val_buf = std.ArrayListUnmanaged(u8){};
            try entry.value.format(&val_buf, ctx.allocator);
            try buf.appendSlice(ctx.allocator, val_buf.items);
            val_buf.deinit(ctx.allocator);
        }
        try buf.append(ctx.allocator, 0);
    }
    defer buf.deinit(ctx.allocator);

    const path = try sessionPath(ctx.allocator, sid);
    defer ctx.allocator.free(path);
    std.fs.cwd().writeFile(.{ .sub_path = path, .data = buf.items }) catch return;
}

fn getCookieSessionId(ctx: *NativeContext) ?[]const u8 {
    const cookie_val = ctx.vm.request_vars.get("$_COOKIE") orelse return null;
    if (cookie_val != .array) return null;
    const val = cookie_val.array.get(.{ .string = default_name });
    if (val == .string) return val.string;
    return null;
}

fn setSessionCookie(ctx: *NativeContext, sid: []const u8) !void {
    var buf: [256]u8 = undefined;
    const cookie = std.fmt.bufPrint(&buf, "Set-Cookie: {s}={s}; Path=/; HttpOnly; SameSite=Lax", .{ default_name, sid }) catch return;
    const hdr = try ctx.createString(cookie);

    const key = "__response_headers";
    const existing = ctx.vm.frames[0].vars.get(key);
    if (existing != null and existing.? == .array) {
        try existing.?.array.append(ctx.allocator, .{ .string = hdr });
    } else {
        const arr = try ctx.createArray();
        try arr.append(ctx.allocator, .{ .string = hdr });
        try ctx.vm.frames[0].vars.put(ctx.allocator, key, .{ .array = arr });
    }
}

fn native_session_start(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    // already started?
    if (getSessionVar(ctx, "__session_id") != null) return .{ .bool = true };

    var sid: []const u8 = undefined;
    var is_new = false;

    if (getCookieSessionId(ctx)) |existing| {
        sid = existing;
    } else {
        sid = try generateId(ctx);
        is_new = true;
    }

    try setSessionVar(ctx, "__session_id", .{ .string = sid });
    try setSessionVar(ctx, "__session_active", .{ .bool = true });

    const arr = try loadSessionData(ctx, sid);
    try ctx.vm.request_vars.put(ctx.allocator, "$_SESSION", .{ .array = arr });
    try ctx.vm.frames[0].vars.put(ctx.allocator, "$_SESSION", .{ .array = arr });

    if (is_new) try setSessionCookie(ctx, sid);

    return .{ .bool = true };
}

fn native_session_id(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len >= 1 and args[0] == .string) {
        try setSessionVar(ctx, "__session_id", args[0]);
        return .{ .string = args[0].string };
    }
    const v = getSessionVar(ctx, "__session_id") orelse return .{ .string = "" };
    if (v == .string) return v;
    return .{ .string = "" };
}

fn native_session_destroy(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const sid_val = getSessionVar(ctx, "__session_id") orelse return .{ .bool = false };
    if (sid_val != .string) return .{ .bool = false };

    const path = try sessionPath(ctx.allocator, sid_val.string);
    defer ctx.allocator.free(path);
    std.fs.cwd().deleteFile(path) catch {};

    try setSessionVar(ctx, "__session_active", .{ .bool = false });
    return .{ .bool = true };
}

fn native_session_regenerate_id(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const old_sid_val = getSessionVar(ctx, "__session_id") orelse return .{ .bool = false };
    if (old_sid_val != .string) return .{ .bool = false };

    const delete_old = args.len >= 1 and args[0] == .bool and args[0].bool;
    if (delete_old) {
        const path = try sessionPath(ctx.allocator, old_sid_val.string);
        defer ctx.allocator.free(path);
        std.fs.cwd().deleteFile(path) catch {};
    }

    const new_sid = try generateId(ctx);
    try setSessionVar(ctx, "__session_id", .{ .string = new_sid });
    try setSessionCookie(ctx, new_sid);
    return .{ .bool = true };
}

fn native_session_name(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .string = default_name };
}

fn native_session_status(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const active = getSessionVar(ctx, "__session_active");
    if (active != null and active.? == .bool and active.?.bool) return .{ .int = 2 }; // PHP_SESSION_ACTIVE
    return .{ .int = 1 }; // PHP_SESSION_NONE
}

fn native_session_write_close(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const sid_val = getSessionVar(ctx, "__session_id") orelse return .null;
    if (sid_val != .string) return .null;
    const active = getSessionVar(ctx, "__session_active");
    if (active == null or active.? != .bool or !active.?.bool) return .null;
    try saveSessionData(ctx, sid_val.string);
    try setSessionVar(ctx, "__session_active", .{ .bool = false });
    return .null;
}

fn native_session_unset(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const arr = try ctx.createArray();
    try ctx.vm.request_vars.put(ctx.allocator, "$_SESSION", .{ .array = arr });
    try ctx.vm.frames[0].vars.put(ctx.allocator, "$_SESSION", .{ .array = arr });
    return .null;
}

// called from serve after PHP execution to persist session
pub fn finalizeSession(ctx: *NativeContext) void {
    const active = getSessionVar(ctx, "__session_active");
    if (active == null or active.? != .bool or !active.?.bool) return;
    const sid_val = getSessionVar(ctx, "__session_id") orelse return;
    if (sid_val != .string) return;
    saveSessionData(ctx, sid_val.string) catch {};
}
