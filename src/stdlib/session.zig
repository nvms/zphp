const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const serialize_mod = @import("serialize.zig");
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

const session_id_alphabet = "0123456789abcdefghijklmnopqrstuvwxyz";
const session_id_len = 26;

fn generateId(ctx: *NativeContext) ![]const u8 {
    var raw: [session_id_len]u8 = undefined;
    std.crypto.random.bytes(&raw);
    // map each byte into the alphabet; modulo bias is negligible for this use
    for (&raw) |*b| b.* = session_id_alphabet[b.* % session_id_alphabet.len];
    return ctx.createString(&raw);
}

// PHP restricts session IDs to [a-zA-Z0-9,-] by default. We reject anything else
// to prevent path traversal in sessionPath.
fn isValidSessionId(sid: []const u8) bool {
    if (sid.len == 0 or sid.len > 128) return false;
    for (sid) |c| {
        const ok = (c >= '0' and c <= '9') or
            (c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            c == ',' or c == '-';
        if (!ok) return false;
    }
    return true;
}

fn sessionPath(a: std.mem.Allocator, sid: []const u8) ![]const u8 {
    return std.mem.concat(a, u8, &.{ session_dir, "/sess_", sid });
}

fn loadSessionData(ctx: *NativeContext, sid: []const u8) !*PhpArray {
    const path = try sessionPath(ctx.allocator, sid);
    defer ctx.allocator.free(path);

    const data = std.fs.cwd().readFileAlloc(ctx.allocator, path, 1024 * 1024) catch {
        return try ctx.createArray();
    };
    defer ctx.allocator.free(data);

    // session data is stored as a serialize()'d array (PHP's "php_serialize" format).
    // if the file is empty or the deserialize fails, fall back to an empty array so
    // a corrupt session can never break session_start.
    if (data.len == 0) return try ctx.createArray();
    const parsed = serialize_mod.unserializeFromString(ctx, data) orelse return try ctx.createArray();
    if (parsed != .array) return try ctx.createArray();
    return parsed.array;
}

fn saveSessionData(ctx: *NativeContext, sid: []const u8) !void {
    const session_val = ctx.vm.frames[0].vars.get("$_SESSION") orelse return;
    if (session_val != .array) return;

    const serialized = try serialize_mod.serializeToString(ctx, session_val);
    if (serialized != .string) return;

    const path = try sessionPath(ctx.allocator, sid);
    defer ctx.allocator.free(path);
    std.fs.cwd().writeFile(.{ .sub_path = path, .data = serialized.string }) catch return;
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
    // already active? (do not short-circuit on __session_id alone so that
    // a session reopened after session_write_close correctly re-loads data)
    const active = getSessionVar(ctx, "__session_active");
    if (active != null and active.? == .bool and active.?.bool) return .{ .bool = true };

    var sid: []const u8 = undefined;
    var is_new = false;

    // prefer an existing id cached on this request (e.g. from a prior
    // session_write_close), otherwise honour the cookie if it's well-formed.
    if (getSessionVar(ctx, "__session_id")) |existing_sid| {
        if (existing_sid == .string and isValidSessionId(existing_sid.string)) {
            sid = existing_sid.string;
        } else if (getCookieSessionId(ctx)) |cookie_sid| {
            if (isValidSessionId(cookie_sid)) {
                sid = cookie_sid;
            } else {
                sid = try generateId(ctx);
                is_new = true;
            }
        } else {
            sid = try generateId(ctx);
            is_new = true;
        }
    } else if (getCookieSessionId(ctx)) |cookie_sid| {
        if (isValidSessionId(cookie_sid)) {
            sid = cookie_sid;
        } else {
            sid = try generateId(ctx);
            is_new = true;
        }
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

    const new_sid = try generateId(ctx);

    // migrate current $_SESSION contents to the new ID so session data survives
    // regeneration (this is how every PHP framework uses it post-login).
    try setSessionVar(ctx, "__session_id", .{ .string = new_sid });
    saveSessionData(ctx, new_sid) catch {};

    const delete_old = args.len >= 1 and args[0].isTruthy();
    if (delete_old) {
        const path = try sessionPath(ctx.allocator, old_sid_val.string);
        defer ctx.allocator.free(path);
        std.fs.cwd().deleteFile(path) catch {};
    }

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
