const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const std = @import("std");
const platform = @import("../platform.zig");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const VM = @import("../runtime/vm.zig").VM;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "flush", native_flush },
    .{ "header", native_header },
    .{ "http_response_code", native_http_response_code },
    .{ "setcookie", native_setcookie },
    .{ "setrawcookie", native_setrawcookie },
    .{ "header_remove", native_header_remove },
    .{ "headers_sent", native_headers_sent },
    .{ "headers_list", native_headers_list },
    .{ "http_get_last_response_headers", native_http_get_last_response_headers },
    .{ "http_clear_last_response_headers", native_http_clear_last_response_headers },
};

fn native_flush(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // CLI: nothing to flush at HTTP level
    return NativeResult.scalar(.null);
}

fn native_header(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.null);
    const hdr = args[0].string.bytes();
    const replace = args.len < 2 or args[1] != .bool or args[1].bool;

    // PHP treats `header("HTTP/1.1 301 ...")` as a status-code set, not a real
    // header. parse the numeric code out and update response_code. the header
    // string stays in response_headers so headers_list() can introspect it
    // (matching PHP's observable behavior), but writeResponse will skip emitting
    // any HTTP/ line on the wire - the wire status comes from response_code
    if (std.mem.startsWith(u8, hdr, "HTTP/")) {
        // expect "HTTP/x.y CODE message"
        var it = std.mem.tokenizeScalar(u8, hdr, ' ');
        _ = it.next(); // HTTP/x.y
        if (it.next()) |code_str| {
            if (std.fmt.parseInt(i64, code_str, 10)) |parsed| {
                ctx.vm.response_code = parsed;
            } else |_| {}
        }
    }

    if (args.len >= 3 and args[2] == .int) {
        ctx.vm.response_code = args[2].int;
    }

    if (replace) {
        if (std.mem.indexOf(u8, hdr, ":")) |colon| {
            removeHeaderByName(ctx, hdr[0..colon]);
        }
    }

    try appendResponseHeader(ctx, hdr);
    return NativeResult.scalar(.null);
}

fn native_http_response_code(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len >= 1 and args[0] == .int) {
        ctx.vm.response_code = args[0].int;
    }
    return NativeResult.scalar(.{ .int = ctx.vm.response_code });
}

// php's head.c: php_setcookie_common and php_setcookie
fn native_setcookie(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return setcookieCommon(ctx, args, "setcookie", false);
}

fn native_setrawcookie(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return setcookieCommon(ctx, args, "setrawcookie", true);
}

fn cookieError(ctx: *NativeContext, class: []const u8, comptime fmt: []const u8, args: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException(class, msg);
    return error.RuntimeError;
}

const illegal_cookie_chars = "\",\", \";\", \" \", \"\\t\", \"\\r\", \"\\n\", \"\\013\", or \"\\014\"";

fn setcookieCommon(ctx: *NativeContext, args: []const Value, comptime func: []const u8, raw: bool) RuntimeError!NativeResult {
    const Args = @import("string_ports.zig").Args;
    const a = ctx.allocator;
    const p = Args.init(ctx, func, args);
    const name = try p.str(0, "name");
    const value: ?[]const u8 = if (args.len > 1) try p.str(1, "value") else null;
    var expires: i64 = 0;
    var path: ?[]const u8 = null;
    var domain: ?[]const u8 = null;
    var samesite: ?[]const u8 = null;
    var secure = false;
    var httponly = false;
    var partitioned = false;
    // option strings converted from other types live until the call ends
    var owned = std.ArrayListUnmanaged([]u8).empty;
    defer {
        for (owned.items) |s| a.free(s);
        owned.deinit(a);
    }
    if (args.len > 2 and args[2] == .array) {
        if (args.len > 3) return cookieError(ctx, "ArgumentCountError", func ++ "(): Expects exactly 3 arguments when argument #3 ($expires_or_options) is an array", .{});
        for (args[2].array.entries.items) |entry| {
            if (entry.key != .string) return cookieError(ctx, "ValueError", func ++ "(): option array cannot have numeric keys", .{});
            const key = entry.key.string.bytes();
            const v = entry.value;
            if (std.ascii.eqlIgnoreCase(key, "expires")) {
                expires = Value.toInt(v);
            } else if (std.ascii.eqlIgnoreCase(key, "path") or std.ascii.eqlIgnoreCase(key, "domain") or std.ascii.eqlIgnoreCase(key, "samesite")) {
                var buf = std.ArrayListUnmanaged(u8).empty;
                errdefer buf.deinit(a);
                try v.format(&buf, a);
                const s = try buf.toOwnedSlice(a);
                try owned.append(a, s);
                if (std.ascii.eqlIgnoreCase(key, "path")) path = s else if (std.ascii.eqlIgnoreCase(key, "domain")) domain = s else samesite = s;
            } else if (std.ascii.eqlIgnoreCase(key, "secure")) {
                secure = v.isTruthy();
            } else if (std.ascii.eqlIgnoreCase(key, "httponly")) {
                httponly = v.isTruthy();
            } else if (std.ascii.eqlIgnoreCase(key, "partitioned")) {
                partitioned = v.isTruthy();
            } else {
                return cookieError(ctx, "ValueError", func ++ "(): option \"{s}\" is invalid", .{key[0 .. std.mem.indexOfScalar(u8, key, 0) orelse key.len]});
            }
        }
    } else {
        if (args.len > 2) expires = try p.longAs(2, "expires_or_options", "array|int");
        if (args.len > 3) path = try p.str(3, "path");
        if (args.len > 4) domain = try p.str(4, "domain");
        if (args.len > 5) secure = try p.boolean(5, "secure", false);
        if (args.len > 6) httponly = try p.boolean(6, "httponly", false);
    }

    // the c strings php checks end at a nul byte
    const cs = struct {
        fn f(s: []const u8) []const u8 {
            return s[0 .. std.mem.indexOfScalar(u8, s, 0) orelse s.len];
        }
    }.f;
    if (name.len == 0) return p.valueError(0, "name", "must not be empty");
    if (std.mem.indexOfAny(u8, cs(name), "=,; \t\r\n\x0b\x0c") != null) return p.valueError(0, "name", "cannot contain \"=\", " ++ illegal_cookie_chars);
    if (raw) if (value) |v| if (std.mem.indexOfAny(u8, cs(v), ",; \t\r\n\x0b\x0c") != null) return p.valueError(1, "value", "cannot contain " ++ illegal_cookie_chars);
    if (path) |s| if (std.mem.indexOfAny(u8, cs(s), ",; \t\r\n\x0b\x0c") != null) return cookieError(ctx, "ValueError", func ++ "(): \"path\" option cannot contain " ++ illegal_cookie_chars, .{});
    if (domain) |s| if (std.mem.indexOfAny(u8, cs(s), ",; \t\r\n\x0b\x0c") != null) return cookieError(ctx, "ValueError", func ++ "(): \"domain\" option cannot contain " ++ illegal_cookie_chars, .{});
    if (expires >= 253402300800) return cookieError(ctx, "ValueError", func ++ "(): \"expires\" option cannot have a year greater than 9999", .{});
    if (partitioned and !secure) return cookieError(ctx, "ValueError", func ++ "(): \"partitioned\" option cannot be used without \"secure\" option", .{});

    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(a);
    try buf.appendSlice(a, "Set-Cookie: ");
    try buf.appendSlice(a, name);
    if (value == null or value.?.len == 0) {
        try buf.appendSlice(a, "=deleted; expires=Thu, 01 Jan 1970 00:00:01 GMT; Max-Age=0");
    } else {
        try buf.append(a, '=');
        if (raw) try buf.appendSlice(a, value.?) else try appendRawUrlEncoded(&buf, a, value.?);
        if (expires > 0) {
            try buf.appendSlice(a, "; expires=");
            const dt = try ctx.vm.callByName("gmdate", &.{ .{ .string = Value.String.borrowed("D, d M Y H:i:s \\G\\M\\T") }, .{ .int = expires } });
            if (dt == .string) try buf.appendSlice(a, dt.string.bytes());
            const now: i64 = @intCast(@divFloor(platform.milliTimestamp(), 1000));
            try buf.print(a, "; Max-Age={d}", .{@max(expires - now, 0)});
        }
    }
    if (path) |s| if (s.len > 0) {
        try buf.appendSlice(a, "; path=");
        try buf.appendSlice(a, s);
    };
    if (domain) |s| if (s.len > 0) {
        try buf.appendSlice(a, "; domain=");
        try buf.appendSlice(a, s);
    };
    if (secure) try buf.appendSlice(a, "; secure");
    if (httponly) try buf.appendSlice(a, "; HttpOnly");
    if (samesite) |s| if (s.len > 0) {
        try buf.appendSlice(a, "; SameSite=");
        try buf.appendSlice(a, s);
    };
    if (partitioned) try buf.appendSlice(a, "; Partitioned");

    try appendResponseHeader(ctx, buf.items);
    return NativeResult.scalar(.{ .bool = true });
}

// php_raw_url_encode
fn appendRawUrlEncoded(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, s: []const u8) !void {
    const hex = "0123456789ABCDEF";
    for (s) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
            try buf.append(a, c);
        } else {
            try buf.appendSlice(a, &.{ '%', hex[c >> 4], hex[c & 0xf] });
        }
    }
}

fn native_header_remove(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) {
        if (getResponseHeaders(ctx)) |arr| {
            while (arr.entries.items.len > 0) {
                ctx.vm.arrayRemoveOwned(arr, arr.entries.items[arr.entries.items.len - 1].key);
            }
        }
        return NativeResult.scalar(.null);
    }
    if (args[0] == .string) removeHeaderByName(ctx, args[0].string.bytes());
    return NativeResult.scalar(.null);
}

fn native_headers_sent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = ctx.vm.headers_sent });
}

fn native_headers_list(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    if (getResponseHeaders(ctx)) |arr| return NativeResult.borrowed(.{ .array = arr });
    return NativeResult.borrowed(.{ .array = try ctx.createArray() });
}

fn native_http_get_last_response_headers(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    if (ctx.vm.last_http_response_headers) |arr| {
        return NativeResult.borrowed(.{ .array = try ctx.vm.cloneArray(arr) });
    }
    return NativeResult.scalar(.null);
}

fn native_http_clear_last_response_headers(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    if (ctx.vm.last_http_response_headers) |arr| ctx.vm.arrayRelease(arr);
    ctx.vm.last_http_response_headers = null;
    return NativeResult.scalar(.null);
}

fn getResponseHeaders(ctx: *NativeContext) ?*PhpArray {
    return ctx.vm.response_headers;
}

pub fn appendResponseHeader(ctx: *NativeContext, hdr: []const u8) !void {
    const owned = try Value.String.create(ctx.allocator, hdr);
    defer owned.release();
    if (ctx.vm.response_headers) |arr| {
        try arr.append(ctx.allocator, .{ .string = owned });
    } else {
        const arr = try ctx.createArray();
        try arr.append(ctx.allocator, .{ .string = owned });
        ctx.vm.response_headers = arr;
    }
}

fn removeHeaderByName(ctx: *NativeContext, name: []const u8) void {
    const arr = getResponseHeaders(ctx) orelse return;
    var removed = false;
    var i: usize = 0;
    while (i < arr.entries.items.len) {
        const entry = arr.entries.items[i];
        if (entry.value == .string) {
            const hdr = entry.value.string.bytes();
            if (hdr.len > name.len and hdr[name.len] == ':' and std.ascii.eqlIgnoreCase(hdr[0..name.len], name)) {
                ctx.vm.arrayRemoveOwned(arr, entry.key);
                removed = true;
                continue;
            }
        }
        i += 1;
    }
    if (removed) arr.rebuildStringIndexAssumeCapacity();
}

pub fn isContentTypeHeader(hdr: []const u8) bool {
    return startsWithIgnoreCase(hdr, "Content-Type:");
}

// the last Content-Type header() set, or php's default
pub fn responseContentType(vm: *const VM) []const u8 {
    const arr = vm.response_headers orelse return "text/html";
    var i = arr.entries.items.len;
    while (i > 0) {
        i -= 1;
        const entry = arr.entries.items[i];
        if (entry.value != .string) continue;
        const hdr = entry.value.string.bytes();
        if (isContentTypeHeader(hdr)) return std.mem.trim(u8, hdr["Content-Type:".len..], " \t");
    }
    return "text/html";
}

fn startsWithIgnoreCase(s: []const u8, prefix: []const u8) bool {
    return s.len >= prefix.len and std.ascii.eqlIgnoreCase(s[0..prefix.len], prefix);
}
