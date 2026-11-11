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

fn native_setcookie(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const name = args[0].string.bytes();
    const value = if (args.len >= 2 and args[1] == .string) args[1].string.bytes() else "";

    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);
    try buf.appendSlice(ctx.allocator, "Set-Cookie: ");
    try buf.appendSlice(ctx.allocator, name);
    try buf.append(ctx.allocator, '=');
    try appendUrlEncoded(&buf, ctx.allocator, value);

    if (args.len >= 3 and args[2] == .array) {
        try appendCookieOptionsArray(&buf, ctx.allocator, args[2].array);
    } else {
        try appendCookieOptionsPositional(&buf, ctx.allocator, args);
    }

    try appendResponseHeader(ctx, buf.items);
    return NativeResult.scalar(.{ .bool = true });
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

fn appendCookieOptionsArray(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, opts: *PhpArray) !void {
    const expires = opts.get(.{ .string = Value.String.borrowed("expires") });
    if (expires == .int and expires.int > 0) {
        try appendMaxAge(buf, a, expires.int);
    }
    const path = opts.get(.{ .string = Value.String.borrowed("path") });
    if (path == .string) {
        try buf.appendSlice(a, "; Path=");
        try buf.appendSlice(a, path.string.bytes());
    }
    const domain = opts.get(.{ .string = Value.String.borrowed("domain") });
    if (domain == .string) {
        try buf.appendSlice(a, "; Domain=");
        try buf.appendSlice(a, domain.string.bytes());
    }
    const secure = opts.get(.{ .string = Value.String.borrowed("secure") });
    if (secure == .bool and secure.bool) try buf.appendSlice(a, "; Secure");
    const httponly = opts.get(.{ .string = Value.String.borrowed("httponly") });
    if (httponly == .bool and httponly.bool) try buf.appendSlice(a, "; HttpOnly");
    const samesite = opts.get(.{ .string = Value.String.borrowed("samesite") });
    if (samesite == .string) {
        try buf.appendSlice(a, "; SameSite=");
        try buf.appendSlice(a, samesite.string.bytes());
    }
}

fn appendCookieOptionsPositional(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, args: []const Value) !void {
    if (args.len >= 3 and args[2] == .int and args[2].int > 0) {
        try appendMaxAge(buf, a, args[2].int);
    }
    if (args.len >= 4 and args[3] == .string) {
        try buf.appendSlice(a, "; Path=");
        try buf.appendSlice(a, args[3].string.bytes());
    }
    if (args.len >= 5 and args[4] == .string) {
        try buf.appendSlice(a, "; Domain=");
        try buf.appendSlice(a, args[4].string.bytes());
    }
    if (args.len >= 6 and args[5].isTruthy()) try buf.appendSlice(a, "; Secure");
    if (args.len >= 7 and args[6].isTruthy()) try buf.appendSlice(a, "; HttpOnly");
}

fn appendMaxAge(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, expires: i64) !void {
    try buf.appendSlice(a, "; Max-Age=");
    const now: i64 = @intCast(@divFloor(platform.milliTimestamp(), 1000));
    var tmp: [20]u8 = undefined;
    const s = std.fmt.bufPrint(&tmp, "{d}", .{expires - now}) catch "0";
    try buf.appendSlice(a, s);
}

fn appendUrlEncoded(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, s: []const u8) !void {
    const hex = "0123456789ABCDEF";
    for (s) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
            try buf.append(a, c);
        } else if (c == ' ') {
            try buf.append(a, '+');
        } else {
            try buf.append(a, '%');
            try buf.append(a, hex[c >> 4]);
            try buf.append(a, hex[c & 0xf]);
        }
    }
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
