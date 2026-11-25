const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const std = @import("std");
const platform = @import("../platform.zig");
const paths = @import("../paths.zig");
const bundle = @import("../bundle.zig");
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
    if (args.len >= 1) try refuseWhileUploadProgress(ctx);
    // legacy 6-callable form: session_set_save_handler(open, close, read, write, destroy, gc, ...)
    if (args.len >= 6 and args[0] != .object) {
        try @import("filesystem.zig").deprecatedDocref(ctx, "Providing individual callbacks instead of an object implementing SessionHandlerInterface is deprecated", .{});
        return NativeResult.scalar(.{ .bool = true });
    }
    // OO form: session_set_save_handler($handler [, $register_shutdown = true])
    if (args.len >= 1 and args[0] == .object) {
        // php 8.6 deprecates a handler that can't create or validate ids
        const class = args[0].object.class_name;
        if (!ctx.vm.isInstanceOf(class, "SessionIdInterface") and !ctx.vm.hasMethod(class, "create_sid")) {
            try @import("filesystem.zig").deprecatedDocref(ctx, "Providing an object to argument #1 ($sessionhandler) which does not have the create_sid() method defined is deprecated", .{});
            if (ctx.vm.pending_exception != null) return error.RuntimeError;
        }
        if (!ctx.vm.isInstanceOf(class, "SessionUpdateTimestampHandlerInterface") and !ctx.vm.hasMethod(class, "validateId")) {
            try @import("filesystem.zig").deprecatedDocref(ctx, "Providing an object to argument #1 ($sessionhandler) which does not have the validateId() method defined is deprecated", .{});
            if (ctx.vm.pending_exception != null) return error.RuntimeError;
        }
        try setSessionVar(ctx, "__session_handler", args[0]);
        return NativeResult.scalar(.{ .bool = true });
    }
    return NativeResult.scalar(.{ .bool = false });
}

const default_name = "PHPSESSID";

fn currentSessionDir(ctx: *NativeContext) []const u8 {
    const v = getSessionVar(ctx, "__session_save_path");
    if (v != null and v.? == .string and v.?.string.bytes().len > 0) return v.?.string.bytes();
    return @import("../platform.zig").tempDir();
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
    platform.random.bytes(&raw);
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

// php_session_initialize: the stored data is decoded into a fresh $_SESSION
// with the configured serializer; data it can't decode destroys the session
fn loadSessionData(ctx: *NativeContext, sid: []const u8) RuntimeError!void {
    try ctx.vm.putRequestVar("$_SESSION", .{ .array = try ctx.createArray() });
    const path = try sessionPath(ctx, sid);
    defer ctx.allocator.free(path);
    const data = bundle.readFileAlloc(ctx.allocator, path, 1024 * 1024) catch return;
    defer ctx.allocator.free(data);
    _ = try decodeSession(ctx, data);
}

fn saveSessionData(ctx: *NativeContext, sid: []const u8) !void {
    const encoded = (try encodeSession(ctx)) orelse return;
    defer encoded.release();

    const path = try sessionPath(ctx, sid);
    defer ctx.allocator.free(path);
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const target = paths.streamPath(&path_buf, path);
    bundle.prepareWrite(target, .create);
    std.Io.Dir.cwd().writeFile(platform.io, .{ .sub_path = target, .data = encoded.bytes() }) catch return;
}

const Serializer = enum { php, php_serialize, php_binary };

fn serializer(ctx: *NativeContext) ?Serializer {
    return std.meta.stringToEnum(Serializer, iniValue(ctx, "session.serialize_handler", "php"));
}

// php's session serializers (ext/session/session.c PS_SERIALIZER_ENCODE_FUNC):
// the encoded $_SESSION, or null when a key can't be written
fn encodeSession(ctx: *NativeContext) RuntimeError!?Value.String {
    const session_val = ctx.vm.request_vars.get("$_SESSION") orelse return null;
    const handler = serializer(ctx) orelse return null;
    if (handler == .php_serialize) {
        const out = (try serialize_mod.serializeToString(ctx, session_val)).value;
        return if (out == .string) out.string else null;
    }
    if (session_val != .array) return try Value.String.create(ctx.allocator, "");
    var w = serialize_mod.Writer{ .ctx = ctx };
    w.begin();
    defer w.deinit();
    for (session_val.array.entries.items) |entry| {
        const key = switch (entry.key) {
            .string => |k| k.bytes(),
            .int => |n| {
                try serialize_mod.docref(ctx, 2, "Skipping numeric key {d}", .{n});
                continue;
            },
        };
        switch (handler) {
            .php => {
                if (std.mem.indexOfScalar(u8, key, '|') != null) {
                    try serialize_mod.docref(ctx, 2, "Failed to write session data. Data contains invalid key \"{s}\"", .{key});
                    return null;
                }
                try w.raw(key);
                try w.raw("|");
            },
            .php_binary => {
                if (key.len > 127) continue;
                try w.raw(&.{@intCast(key.len)});
                try w.raw(key);
            },
            .php_serialize => unreachable,
        }
        try w.value(entry.value);
    }
    return try Value.String.create(ctx.allocator, w.buf.items);
}

// PS_SERIALIZER_DECODE_FUNC: fills $_SESSION from data; false when it is
// malformed, after php_session_cancel_decode destroyed the session
fn decodeSession(ctx: *NativeContext, data: []const u8) RuntimeError!bool {
    const handler = serializer(ctx) orelse return false;
    const ok = switch (handler) {
        .php_serialize => blk: {
            var r = serialize_mod.Reader{ .ctx = ctx, .s = data };
            r.begin();
            defer r.deinit();
            const v = try r.value();
            const vars: Value = if (v) |val| (if (val == .null) .{ .array = try ctx.createArray() } else val) else .{ .array = try ctx.createArray() };
            try ctx.vm.putRequestVar("$_SESSION", vars);
            if (v) |val| if (val == .string) val.string.release();
            break :blk v != null or data.len == 0;
        },
        .php, .php_binary => blk: {
            const target = try ctx.createArray();
            const current = ctx.vm.request_vars.get("$_SESSION");
            if (current) |cur| if (cur == .array) {
                for (cur.array.entries.items) |entry| try ctx.vm.arrayAddCarried(target, entry.key, entry, cur.array);
            };
            var r = serialize_mod.Reader{ .ctx = ctx, .s = data };
            r.begin();
            defer r.deinit();
            var good = true;
            while (r.pos < data.len) {
                var name: []const u8 = undefined;
                if (handler == .php) {
                    const bar = std.mem.indexOfScalarPos(u8, data, r.pos, '|') orelse {
                        good = false;
                        break;
                    };
                    name = data[r.pos..bar];
                    r.pos = bar + 1;
                } else {
                    const len = data[r.pos] & 0x7f;
                    if (r.pos + len >= data.len) {
                        good = false;
                        break;
                    }
                    name = data[r.pos + 1 ..][0..len];
                    r.pos += len + 1;
                }
                const v = (try r.value()) orelse {
                    good = false;
                    break;
                };
                const key = try Value.String.create(ctx.allocator, name);
                defer key.release();
                try target.set(ctx.allocator, .{ .string = key }, v);
                if (v == .string) v.string.release();
            }
            try ctx.vm.putRequestVar("$_SESSION", .{ .array = target });
            break :blk good;
        },
    };
    if (ok) return true;
    // php_session_cancel_decode
    if (getSessionVar(ctx, "__session_id")) |sid| if (sid == .string) {
        const path = try sessionPath(ctx, sid.string.bytes());
        defer ctx.allocator.free(path);
        std.Io.Dir.cwd().deleteFile(platform.io, path) catch {};
    };
    try setSessionVar(ctx, "__session_active", .{ .bool = false });
    try ctx.vm.putRequestVar("$_SESSION", .{ .array = try ctx.createArray() });
    try serialize_mod.docref(ctx, 2, "Failed to decode session object. Session has been destroyed", .{});
    return false;
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

// where the running session started, as php's messages name it
pub fn startedAt(ctx: *NativeContext) []const u8 {
    const at = getSessionVar(ctx, "__session_started_at") orelse return "";
    return if (at == .string) at.string.bytes() else "";
}

pub fn isActive(ctx: *NativeContext) bool {
    const active = getSessionVar(ctx, "__session_active") orelse return false;
    return active == .bool and active.bool;
}

// the directives the session module registers (the trans sid tags and hosts
// are the url rewriter's)
// the settings whose handlers refuse changes while a session runs or
// upload progress is on (SESSION_CHECK_*_STATE)
pub fn isSessionIni(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, "session.")) return false;
    for ([_][]const u8{ "session.trans_sid_tags", "session.trans_sid_hosts", "session.encode_sources" }) |other| {
        if (std.mem.eql(u8, name, other)) return false;
    }
    return !isPerDirIni(name);
}

// PHP_INI_PERDIR: ini_set() can't change these at all
pub fn isPerDirIni(name: []const u8) bool {
    return std.mem.eql(u8, name, "session.auto_start") or std.mem.startsWith(u8, name, "session.upload_progress.");
}

pub const upload_progress_refusal = "Session ini settings cannot be changed at runtime when session.upload_progress.enabled is On";

// PS(rfc1867_enabled): off by default since php 8.5.13
pub fn uploadProgressEnabled(ctx: *NativeContext) bool {
    return iniBool(iniValue(ctx, "session.upload_progress.enabled", "0"));
}

// the session functions that set a setting go through its ini handler,
// which refuses while upload progress is on (SESSION_CHECK_UPLOAD_PROGRESS_STATE)
fn refuseWhileUploadProgress(ctx: *NativeContext) RuntimeError!void {
    if (!uploadProgressEnabled(ctx)) return;
    try ctx.vm.setPendingException("Error", upload_progress_refusal);
    return error.RuntimeError;
}

fn iniBool(v: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(v, "true") or std.ascii.eqlIgnoreCase(v, "yes") or std.ascii.eqlIgnoreCase(v, "on")) return true;
    return (std.fmt.parseInt(i64, std.mem.trim(u8, v, " "), 10) catch 0) != 0;
}

// what php's handlers say is deprecated about a session setting's value:
// "Disabling session.use_only_cookies" and the like, or null
pub fn iniDeprecation(name: []const u8, value: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "session.use_only_cookies") and !iniBool(value)) return "Disabling session.use_only_cookies";
    if (std.mem.eql(u8, name, "session.use_trans_sid") and iniBool(value)) return "Enabling session.use_trans_sid";
    if (std.mem.eql(u8, name, "session.referer_check") and value.len > 0) return "Usage of session.referer_check";
    if (std.mem.eql(u8, name, "session.trans_sid_tags") and !std.mem.startsWith(u8, value, "a=href,area=href,frame=src,form=")) return "Usage of session.trans_sid_tags";
    if (std.mem.eql(u8, name, "session.trans_sid_hosts") and value.len > 0) return "Usage of session.trans_sid_hosts";
    return null;
}

fn iniValue(ctx: *NativeContext, name: []const u8, default: []const u8) []const u8 {
    return ctx.vm.ini_settings.get(name) orelse @import("../ini_config.zig").get(name) orelse default;
}

fn sessionName(ctx: *NativeContext) []const u8 {
    return iniValue(ctx, "session.name", default_name);
}

// php_session_reset_id's transparent session id: with use_trans_sid on and
// use_only_cookies off, urls in the output carry the id, unless the
// request's cookie already does
fn applyTransSid(ctx: *NativeContext, sid: []const u8) !void {
    if (!iniBool(iniValue(ctx, "session.use_trans_sid", "0")) or iniBool(iniValue(ctx, "session.use_only_cookies", "1"))) return;
    const name = sessionName(ctx);
    if (iniBool(iniValue(ctx, "session.use_cookies", "1"))) {
        if (ctx.vm.request_vars.get("$_COOKIE")) |cookies| if (cookies == .array and cookies.array.get(.{ .string = Value.String.borrowed(name) }) != .null) return;
    }
    const scanner = @import("url_scanner.zig");
    try scanner.resetVar(ctx, .session, name);
    try scanner.addVar(ctx, .session, name, sid, true);
}

fn native_session_start(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // already active? (do not short-circuit on __session_id alone so that
    // a session reopened after session_write_close correctly re-loads data)
    const active = getSessionVar(ctx, "__session_active");
    if (active != null and active.? == .bool and active.?.bool) {
        try serialize_mod.docref(ctx, 8, "Ignoring session_start() because a session is already active (started from {s})", .{startedAt(ctx)});
        return NativeResult.scalar(.{ .bool = true });
    }

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

    // session.use_strict_mode (on by default since php 8.6): an id the
    // files handler has no data for is not adopted, a new one replaces it
    if (!is_new and iniBool(iniValue(ctx, "session.use_strict_mode", "1"))) {
        const path = try sessionPath(ctx, sid);
        defer ctx.allocator.free(path);
        const known = if (std.Io.Dir.cwd().statFile(platform.io, path, .{})) |_| true else |_| false;
        if (!known) {
            generated = try generateId(ctx);
            sid = generated.?.bytes();
            is_new = true;
        }
    }

    const stored_sid = try Value.String.create(ctx.allocator, sid);
    defer stored_sid.release();
    sid = stored_sid.bytes();
    try setSessionVar(ctx, "__session_id", .{ .string = stored_sid });
    try setSessionVar(ctx, "__session_active", .{ .bool = true });
    const pos = ctx.vm.currentSourcePosition();
    const at = try std.fmt.allocPrint(ctx.allocator, "{s} on line {d}", .{ pos.file, pos.line });
    defer ctx.allocator.free(at);
    const at_str = try Value.String.create(ctx.allocator, at);
    defer at_str.release();
    try setSessionVar(ctx, "__session_started_at", .{ .string = at_str });

    try loadSessionData(ctx, sid);

    if (is_new and iniBool(iniValue(ctx, "session.use_cookies", "1"))) try setSessionCookie(ctx, sid);
    try applyTransSid(ctx, sid);

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
    if (!isActive(ctx)) {
        try serialize_mod.docref(ctx, 2, "Trying to destroy uninitialized session", .{});
        return NativeResult.scalar(.{ .bool = false });
    }
    const sid_val = getSessionVar(ctx, "__session_id") orelse return NativeResult.scalar(.{ .bool = false });
    if (sid_val != .string) return NativeResult.scalar(.{ .bool = false });

    const path = try sessionPath(ctx, sid_val.string.bytes());
    defer ctx.allocator.free(path);
    std.Io.Dir.cwd().deleteFile(platform.io, path) catch {};

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
        std.Io.Dir.cwd().deleteFile(platform.io, path) catch {};
    }

    try setSessionCookie(ctx, new_sid.bytes());
    return NativeResult.scalar(.{ .bool = true });
}

fn native_session_name(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len >= 1 and args[0] != .null) try refuseWhileUploadProgress(ctx);
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
    if (args.len >= 1 and args[0] != .null) try refuseWhileUploadProgress(ctx);
    if (args.len >= 1 and args[0] == .string and args[0].string.bytes().len > 0) {
        try setSessionVar(ctx, "__session_save_path", args[0]);
    }
    return NativeResult.takeString(current);
}

fn native_session_module_name(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len >= 1 and args[0] != .null) try refuseWhileUploadProgress(ctx);
    if (args.len >= 1) {
        // accept and ignore - we only implement the 'files' handler
    }
    return NativeResult.literal("files");
}

fn native_session_cache_limiter(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len >= 1 and args[0] != .null) try refuseWhileUploadProgress(ctx);
    if (args.len >= 1 and args[0] == .string) return NativeResult.share(args[0]);
    return NativeResult.literal("nocache");
}

fn native_session_cache_expire(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len >= 1 and args[0] != .null) try refuseWhileUploadProgress(ctx);
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
    try loadSessionData(ctx, sid_val.string.bytes());
    return NativeResult.scalar(.{ .bool = true });
}

fn native_session_set_cookie_params(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    try refuseWhileUploadProgress(ctx);
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
    if (ctx.vm.request_vars.get("$_SESSION") == null) {
        try serialize_mod.docref(ctx, 2, "Cannot encode non-existent session", .{});
        return NativeResult.scalar(.{ .bool = false });
    }
    const encoded = (try encodeSession(ctx)) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.takeString(encoded);
}

fn native_session_decode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    if (!isActive(ctx)) {
        try serialize_mod.docref(ctx, 2, "Session data cannot be decoded when there is no active session", .{});
        return NativeResult.scalar(.{ .bool = false });
    }
    return NativeResult.scalar(.{ .bool = try decodeSession(ctx, args[0].string.bytes()) });
}

// called from serve after PHP execution to persist session
pub fn finalizeSession(ctx: *NativeContext) void {
    const active = getSessionVar(ctx, "__session_active");
    if (active == null or active.? != .bool or !active.?.bool) return;
    const sid_val = getSessionVar(ctx, "__session_id") orelse return;
    if (sid_val != .string) return;
    saveSessionData(ctx, sid_val.string.bytes()) catch {};
}
