const NativeResult = @import("../runtime/native_result.zig").NativeResult;
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
    .{ "session_commit", native_session_write_close },
    .{ "session_abort", native_session_abort },
    .{ "session_reset", native_session_reset },
    .{ "session_unset", native_session_unset },
    .{ "session_save_path", native_session_save_path },
    .{ "session_module_name", native_session_module_name },
    .{ "session_cache_limiter", native_session_cache_limiter },
    .{ "session_cache_expire", native_session_cache_expire },
    .{ "session_create_id", native_session_create_id },
    .{ "session_gc", native_session_gc },
    .{ "session_set_cookie_params", native_session_set_cookie_params },
    .{ "session_get_cookie_params", native_session_get_cookie_params },
    .{ "session_encode", native_session_encode },
    .{ "session_decode", native_session_decode },
    .{ "session_set_save_handler", native_session_set_save_handler },
};

// SessionHandlerInterface implementations: we accept the registration but
// don't actually delegate session storage through them (the built-in file
// backend continues to serve $_SESSION). this lets apps that follow the
// "register a custom handler before starting" pattern run end-to-end without
// hitting an undefined-function fatal
fn native_session_set_save_handler(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // legacy 6-callable form: session_set_save_handler(open, close, read, write, destroy, gc, ...)
    if (args.len >= 6 and args[0] != .object) return NativeResult.scalar(.{ .bool = true });
    // OO form: session_set_save_handler($handler [, $register_shutdown = true])
    if (args.len >= 1 and args[0] == .object) {
        try setSessionVar(ctx, "__session_handler", args[0]);
        return NativeResult.scalar(.{ .bool = true });
    }
    return NativeResult.scalar(.{ .bool = false });
}

const default_session_dir = "/tmp";
const default_name = "PHPSESSID";

fn currentSessionDir(ctx: *NativeContext) []const u8 {
    const v = getSessionVar(ctx, "__session_save_path");
    if (v != null and v.? == .string and v.?.string.bytes().len > 0) return v.?.string.bytes();
    return default_session_dir;
}

fn getSessionVar(ctx: *NativeContext, key: []const u8) ?Value {
    if (ctx.vm.frame_count == 0) return null;
    return ctx.vm.frames[0].vars.get(key);
}

fn setSessionVar(ctx: *NativeContext, key: []const u8, val: Value) !void {
    try ctx.vm.putGlobalVar(key, val);
}

const session_id_alphabet = "0123456789abcdefghijklmnopqrstuvwxyz";
const session_id_len = 26;

fn generateId(ctx: *NativeContext) !Value.String {
    var raw: [session_id_len]u8 = undefined;
    std.crypto.random.bytes(&raw);
    // map each byte into the alphabet; modulo bias is negligible for this use
    for (&raw) |*b| b.* = session_id_alphabet[b.* % session_id_alphabet.len];
    return Value.String.create(ctx.allocator, &raw);
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

fn sessionPath(ctx: *NativeContext, sid: []const u8) ![]const u8 {
    const dir = currentSessionDir(ctx);
    return std.mem.concat(ctx.allocator, u8, &.{ dir, "/sess_", sid });
}

fn loadSessionData(ctx: *NativeContext, sid: []const u8) !*PhpArray {
    const path = try sessionPath(ctx, sid);
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
    const session_val = ctx.vm.request_vars.get("$_SESSION") orelse return;
    if (session_val != .array) return;

    const serialized = (try serialize_mod.serializeToString(ctx, session_val)).value;
    defer if (serialized == .string) serialized.string.release();
    if (serialized != .string) return;

    const path = try sessionPath(ctx, sid);
    defer ctx.allocator.free(path);
    std.fs.cwd().writeFile(.{ .sub_path = path, .data = serialized.string.bytes() }) catch return;
}

fn getCookieSessionId(ctx: *NativeContext) ?[]const u8 {
    const cookie_val = ctx.vm.request_vars.get("$_COOKIE") orelse return null;
    if (cookie_val != .array) return null;
    const val = cookie_val.array.get(.{ .string = Value.String.borrowed(default_name) });
    if (val == .string) return val.string.bytes();
    return null;
}

fn setSessionCookie(ctx: *NativeContext, sid: []const u8) !void {
    var buf: [256]u8 = undefined;
    const cookie = std.fmt.bufPrint(&buf, "Set-Cookie: {s}={s}; Path=/; HttpOnly; SameSite=Lax", .{ default_name, sid }) catch return;
    try @import("http.zig").appendResponseHeader(ctx, cookie);
}

fn native_session_start(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // already active? (do not short-circuit on __session_id alone so that
    // a session reopened after session_write_close correctly re-loads data)
    const active = getSessionVar(ctx, "__session_active");
    if (active != null and active.? == .bool and active.?.bool) return NativeResult.scalar(.{ .bool = true });

    var sid: []const u8 = undefined;
    var generated: ?Value.String = null;
    defer if (generated) |value| value.release();
    var is_new = false;

    // prefer an existing id cached on this request (e.g. from a prior
    // session_write_close), otherwise honour the cookie if it's well-formed.
    if (getSessionVar(ctx, "__session_id")) |existing_sid| {
        if (existing_sid == .string and isValidSessionId(existing_sid.string.bytes())) {
            sid = existing_sid.string.bytes();
        } else if (getCookieSessionId(ctx)) |cookie_sid| {
            if (isValidSessionId(cookie_sid)) {
                sid = cookie_sid;
            } else {
                generated = try generateId(ctx);
                sid = generated.?.bytes();
                is_new = true;
            }
        } else {
            generated = try generateId(ctx);
            sid = generated.?.bytes();
            is_new = true;
        }
    } else if (getCookieSessionId(ctx)) |cookie_sid| {
        if (isValidSessionId(cookie_sid)) {
            sid = cookie_sid;
        } else {
            generated = try generateId(ctx);
            sid = generated.?.bytes();
            is_new = true;
        }
    } else {
        generated = try generateId(ctx);
        sid = generated.?.bytes();
        is_new = true;
    }

    const stored_sid = try Value.String.create(ctx.allocator, sid);
    defer stored_sid.release();
    sid = stored_sid.bytes();
    try setSessionVar(ctx, "__session_id", .{ .string = stored_sid });
    try setSessionVar(ctx, "__session_active", .{ .bool = true });

    const arr = try loadSessionData(ctx, sid);
    try ctx.vm.putRequestVar("$_SESSION", .{ .array = arr });

    if (is_new) try setSessionCookie(ctx, sid);

    return NativeResult.scalar(.{ .bool = true });
}

fn native_session_id(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len >= 1 and args[0] == .string) {
        try setSessionVar(ctx, "__session_id", args[0]);
        return NativeResult.share(args[0]);
    }
    const v = getSessionVar(ctx, "__session_id") orelse return NativeResult.literal("");
    if (v == .string) return NativeResult.share(v);
    return NativeResult.literal("");
}

fn native_session_destroy(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const sid_val = getSessionVar(ctx, "__session_id") orelse return NativeResult.scalar(.{ .bool = false });
    if (sid_val != .string) return NativeResult.scalar(.{ .bool = false });

    const path = try sessionPath(ctx, sid_val.string.bytes());
    defer ctx.allocator.free(path);
    std.fs.cwd().deleteFile(path) catch {};

    try setSessionVar(ctx, "__session_active", .{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn native_session_regenerate_id(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const old_sid_val = getSessionVar(ctx, "__session_id") orelse return NativeResult.scalar(.{ .bool = false });
    if (old_sid_val != .string) return NativeResult.scalar(.{ .bool = false });

    old_sid_val.string.retain();
    defer old_sid_val.string.release();
    const new_sid = try generateId(ctx);
    defer new_sid.release();

    // migrate current $_SESSION contents to the new ID so session data survives
    // regeneration (this is how every PHP framework uses it post-login).
    try setSessionVar(ctx, "__session_id", .{ .string = new_sid });
    saveSessionData(ctx, new_sid.bytes()) catch {};

    const delete_old = args.len >= 1 and args[0].isTruthy();
    if (delete_old) {
        const path = try sessionPath(ctx, old_sid_val.string.bytes());
        defer ctx.allocator.free(path);
        std.fs.cwd().deleteFile(path) catch {};
    }

    try setSessionCookie(ctx, new_sid.bytes());
    return NativeResult.scalar(.{ .bool = true });
}

fn native_session_name(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.literal(default_name);
}

fn native_session_status(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const active = getSessionVar(ctx, "__session_active");
    if (active != null and active.? == .bool and active.?.bool) return NativeResult.scalar(.{ .int = 2 }); // PHP_SESSION_ACTIVE
    return NativeResult.scalar(.{ .int = 1 }); // PHP_SESSION_NONE
}

fn native_session_write_close(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const sid_val = getSessionVar(ctx, "__session_id") orelse return NativeResult.scalar(.null);
    if (sid_val != .string) return NativeResult.scalar(.null);
    const active = getSessionVar(ctx, "__session_active");
    if (active == null or active.? != .bool or !active.?.bool) return NativeResult.scalar(.null);
    try saveSessionData(ctx, sid_val.string.bytes());
    try setSessionVar(ctx, "__session_active", .{ .bool = false });
    return NativeResult.scalar(.null);
}

fn native_session_unset(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    try ctx.vm.putRequestVar("$_SESSION", .{ .array = arr });
    return NativeResult.scalar(.null);
}

fn native_session_save_path(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const current = try Value.String.create(ctx.allocator, currentSessionDir(ctx));
    errdefer current.release();
    if (args.len >= 1 and args[0] == .string and args[0].string.bytes().len > 0) {
        try setSessionVar(ctx, "__session_save_path", args[0]);
    }
    return NativeResult.takeString(current);
}

fn native_session_module_name(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = ctx;
    if (args.len >= 1) {
        // accept and ignore - we only implement the 'files' handler
    }
    return NativeResult.literal("files");
}

fn native_session_cache_limiter(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len >= 1 and args[0] == .string) return NativeResult.share(args[0]);
    return NativeResult.literal("nocache");
}

fn native_session_cache_expire(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len >= 1 and args[0] == .int) return NativeResult.share(args[0]);
    return NativeResult.scalar(.{ .int = 180 });
}

fn native_session_create_id(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const sid = try generateId(ctx);
    defer sid.release();
    if (args.len >= 1 and args[0] == .string and args[0].string.bytes().len > 0) {
        const combined = try std.mem.concat(ctx.allocator, u8, &.{ args[0].string.bytes(), sid.bytes() });
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, combined));
    }
    return NativeResult.shareString(sid);
}

fn native_session_gc(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // PHP returns the number of deleted sessions; without configurable GC, return 0
    return NativeResult.scalar(.{ .int = 0 });
}

fn native_session_abort(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // discard pending changes by clearing active state without saving
    try setSessionVar(ctx, "__session_active", .{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn native_session_reset(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const sid_val = getSessionVar(ctx, "__session_id") orelse return NativeResult.scalar(.{ .bool = false });
    if (sid_val != .string) return NativeResult.scalar(.{ .bool = false });
    const arr = try loadSessionData(ctx, sid_val.string.bytes());
    try ctx.vm.putRequestVar("$_SESSION", .{ .array = arr });
    return NativeResult.scalar(.{ .bool = true });
}

fn native_session_set_cookie_params(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = true });
}

fn native_session_get_cookie_params(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("lifetime") }, .{ .int = 0 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("path") }, .{ .string = Value.String.borrowed("/") });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("domain") }, .{ .string = Value.String.borrowed("") });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("secure") }, .{ .bool = false });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("httponly") }, .{ .bool = true });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("samesite") }, .{ .string = Value.String.borrowed("Lax") });
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_session_encode(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const session_val = ctx.vm.request_vars.get("$_SESSION") orelse return NativeResult.literal("");
    if (session_val != .array) return NativeResult.literal("");
    return try serialize_mod.serializeToString(ctx, session_val);
}

fn native_session_decode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const parsed = serialize_mod.unserializeFromString(ctx, args[0].string.bytes()) orelse return NativeResult.scalar(.{ .bool = false });
    if (parsed != .array) return NativeResult.scalar(.{ .bool = false });
    try ctx.vm.putRequestVar("$_SESSION", parsed);
    return NativeResult.scalar(.{ .bool = true });
}

// called from serve after PHP execution to persist session
pub fn finalizeSession(ctx: *NativeContext) void {
    const active = getSessionVar(ctx, "__session_active");
    if (active == null or active.? != .bool or !active.?.bool) return;
    const sid_val = getSessionVar(ctx, "__session_id") orelse return;
    if (sid_val != .string) return;
    saveSessionData(ctx, sid_val.string.bytes()) catch {};
}
