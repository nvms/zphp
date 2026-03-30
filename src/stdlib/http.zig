const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "ob_start", native_ob_start },
    .{ "ob_get_clean", native_ob_get_clean },
    .{ "ob_end_clean", native_ob_end_clean },
    .{ "ob_get_contents", native_ob_get_contents },
    .{ "ob_get_level", native_ob_get_level },
    .{ "header", native_header },
    .{ "http_response_code", native_http_response_code },
    .{ "setcookie", native_setcookie },
    .{ "headers_sent", native_headers_sent },
    .{ "headers_list", native_headers_list },
};

fn native_ob_start(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    try ctx.vm.ob_stack.append(ctx.allocator, ctx.vm.output.items.len);
    return .{ .bool = true };
}

fn native_ob_get_clean(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    if (ctx.vm.ob_stack.items.len == 0) return .{ .bool = false };
    const start = ctx.vm.ob_stack.pop().?;
    const content = try ctx.createString(ctx.vm.output.items[start..]);
    ctx.vm.output.shrinkRetainingCapacity(start);
    return .{ .string = content };
}

fn native_ob_end_clean(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    if (ctx.vm.ob_stack.items.len == 0) return .{ .bool = false };
    const start = ctx.vm.ob_stack.pop().?;
    ctx.vm.output.shrinkRetainingCapacity(start);
    return .{ .bool = true };
}

fn native_ob_get_contents(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    if (ctx.vm.ob_stack.items.len == 0) return .{ .bool = false };
    const start = ctx.vm.ob_stack.getLast();
    return .{ .string = try ctx.createString(ctx.vm.output.items[start..]) };
}

fn native_ob_get_level(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = @intCast(ctx.vm.ob_stack.items.len) };
}

fn native_header(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .null;
    const hdr = args[0].string;

    if (startsWithIgnoreCase(hdr, "Content-Type:")) {
        if (std.mem.indexOf(u8, hdr, ": ")) |sep| {
            try ctx.vm.currentFrame().vars.put(ctx.allocator, "__response_content_type", .{ .string = hdr[sep + 2 ..] });
        }
    }

    const key = "__response_headers";
    const existing = ctx.vm.currentFrame().vars.get(key);
    if (existing != null and existing.? == .array) {
        try existing.?.array.append(ctx.allocator, .{ .string = hdr });
    } else {
        const arr = try ctx.createArray();
        try arr.append(ctx.allocator, .{ .string = hdr });
        try ctx.vm.currentFrame().vars.put(ctx.allocator, key, .{ .array = arr });
    }
    return .null;
}

fn native_http_response_code(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len >= 1 and args[0] == .int) {
        try ctx.vm.currentFrame().vars.put(ctx.allocator, "__response_code", args[0]);
    }
    return ctx.vm.currentFrame().vars.get("__response_code") orelse Value{ .int = 200 };
}

fn native_setcookie(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const name = args[0].string;
    const value = if (args.len >= 2 and args[1] == .string) args[1].string else "";

    var buf = std.ArrayListUnmanaged(u8){};
    try buf.appendSlice(ctx.allocator, "Set-Cookie: ");
    try buf.appendSlice(ctx.allocator, name);
    try buf.append(ctx.allocator, '=');
    try appendUrlEncoded(&buf, ctx.allocator, value);

    if (args.len >= 3 and args[2] == .array) {
        try appendCookieOptionsArray(&buf, ctx.allocator, args[2].array);
    } else {
        try appendCookieOptionsPositional(&buf, ctx.allocator, args);
    }

    const hdr = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, hdr);
    try appendResponseHeader(ctx, hdr);
    return .{ .bool = true };
}

fn native_headers_sent(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = false };
}

fn native_headers_list(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    if (getResponseHeaders(ctx)) |arr| return .{ .array = arr };
    return .{ .array = try ctx.createArray() };
}

fn appendCookieOptionsArray(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, opts: *PhpArray) !void {
    const expires = opts.get(.{ .string = "expires" });
    if (expires == .int and expires.int > 0) {
        try appendMaxAge(buf, a, expires.int);
    }
    const path = opts.get(.{ .string = "path" });
    if (path == .string) {
        try buf.appendSlice(a, "; Path=");
        try buf.appendSlice(a, path.string);
    }
    const domain = opts.get(.{ .string = "domain" });
    if (domain == .string) {
        try buf.appendSlice(a, "; Domain=");
        try buf.appendSlice(a, domain.string);
    }
    const secure = opts.get(.{ .string = "secure" });
    if (secure == .bool and secure.bool) try buf.appendSlice(a, "; Secure");
    const httponly = opts.get(.{ .string = "httponly" });
    if (httponly == .bool and httponly.bool) try buf.appendSlice(a, "; HttpOnly");
    const samesite = opts.get(.{ .string = "samesite" });
    if (samesite == .string) {
        try buf.appendSlice(a, "; SameSite=");
        try buf.appendSlice(a, samesite.string);
    }
}

fn appendCookieOptionsPositional(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, args: []const Value) !void {
    if (args.len >= 3 and args[2] == .int and args[2].int > 0) {
        try appendMaxAge(buf, a, args[2].int);
    }
    if (args.len >= 4 and args[3] == .string) {
        try buf.appendSlice(a, "; Path=");
        try buf.appendSlice(a, args[3].string);
    }
    if (args.len >= 5 and args[4] == .string) {
        try buf.appendSlice(a, "; Domain=");
        try buf.appendSlice(a, args[4].string);
    }
    if (args.len >= 6 and args[5].isTruthy()) try buf.appendSlice(a, "; Secure");
    if (args.len >= 7 and args[6].isTruthy()) try buf.appendSlice(a, "; HttpOnly");
}

fn appendMaxAge(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, expires: i64) !void {
    try buf.appendSlice(a, "; Max-Age=");
    const now: i64 = @intCast(@divFloor(std.time.milliTimestamp(), 1000));
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
    const existing = ctx.vm.frames[0].vars.get("__response_headers");
    if (existing != null and existing.? == .array) return existing.?.array;
    return null;
}

fn appendResponseHeader(ctx: *NativeContext, hdr: []const u8) !void {
    const key = "__response_headers";
    if (getResponseHeaders(ctx)) |arr| {
        try arr.append(ctx.allocator, .{ .string = hdr });
    } else {
        const arr = try ctx.createArray();
        try arr.append(ctx.allocator, .{ .string = hdr });
        try ctx.vm.frames[0].vars.put(ctx.allocator, key, .{ .array = arr });
    }
}

fn startsWithIgnoreCase(s: []const u8, prefix: []const u8) bool {
    return s.len >= prefix.len and std.ascii.eqlIgnoreCase(s[0..prefix.len], prefix);
}
