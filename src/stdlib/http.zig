const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const OutputBufferLevel = @import("../runtime/vm.zig").OutputBufferLevel;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "ob_start", native_ob_start },
    .{ "ob_get_clean", native_ob_get_clean },
    .{ "ob_end_clean", native_ob_end_clean },
    .{ "ob_get_contents", native_ob_get_contents },
    .{ "ob_get_level", native_ob_get_level },
    .{ "ob_end_flush", native_ob_end_flush },
    .{ "ob_get_flush", native_ob_get_flush },
    .{ "ob_flush", native_ob_flush },
    .{ "ob_clean", native_ob_clean },
    .{ "ob_get_length", native_ob_get_length },
    .{ "ob_implicit_flush", native_ob_implicit_flush },
    .{ "ob_list_handlers", native_ob_list_handlers },
    .{ "ob_get_status", native_ob_get_status },
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

fn isCallable(v: Value) bool {
    return switch (v) {
        .object => true,
        .string => |s| s.bytes().len > 0,
        .array => |a| a.entries.items.len == 2,
        else => false,
    };
}

fn native_ob_start(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    var level: OutputBufferLevel = .{ .start = ctx.vm.output.items.len };
    if (args.len >= 1 and args[0] != .null) {
        // verify the handler resolves to a real callable; PHP returns false
        // and does not start a buffer when the handler can't be found
        if (args[0] == .string) {
            const name = args[0].string.bytes();
            if (!ctx.vm.functions.contains(name) and !ctx.vm.native_fns.contains(name)) return NativeResult.scalar(.{ .bool = false });
        } else if (!isCallable(args[0])) {
            return NativeResult.scalar(.{ .bool = false });
        }
        level.callback = args[0];
    }
    try ctx.vm.ob_stack.append(ctx.allocator, level);
    if (level.callback) |cb| @import("../runtime/vm.zig").VM.retainValue(cb);
    return NativeResult.scalar(.{ .bool = true });
}

// Keep the handler on the stack during invocation (ob_get_level/contents can
// observe it). Counted input allows callbacks to retain their argument.
fn processBuffer(ctx: *NativeContext, clean: bool, final: bool, get: bool) RuntimeError!NativeResult {
    const len = ctx.vm.ob_stack.items.len;
    if (len == 0) return NativeResult.scalar(.{ .bool = false });
    const index = len - 1;
    var level = ctx.vm.ob_stack.items[index];
    if (level.disabled) level.start = ctx.vm.output.items.len;
    const raw_owned = try Value.String.create(ctx.allocator, ctx.vm.output.items[level.start..]);
    defer raw_owned.release();
    const raw = raw_owned.bytes();
    var transformed: []const u8 = raw;
    const discard = clean and !level.disabled;
    if (if (level.disabled) null else level.callback) |cb| {
        const phase: i64 = (if (level.started) @as(i64, 0) else 1) |
            (if (clean) @as(i64, 2) else 0) |
            (if (final) @as(i64, 8) else if (!clean) @as(i64, 4) else 0);
        ctx.vm.ob_stack.items[index].started = true;
        const result = ctx.invokeCallable(cb, &.{
            .{ .string = raw_owned }, .{ .int = phase },
        }) catch |err| {
            // PHP disables a throwing handler. Clean discards input; flush
            // forwards it unchanged. Final operations still remove the level.
            ctx.vm.ob_stack.items[index].callback = null;
            ctx.vm.ob_stack.items[index].disabled = true;
            ctx.vm.releaseValue(cb);
            ctx.vm.output.shrinkRetainingCapacity(level.start);
            if (!clean) try ctx.vm.output.appendSlice(ctx.allocator, raw);
            if (final) {
                _ = ctx.vm.ob_stack.pop();
            } else {
                ctx.vm.ob_stack.items[index].start = ctx.vm.output.items.len;
            }
            return err;
        };
        // A false return disables future handler processing, including clean.
        if (result == .bool and !result.bool) {
            ctx.vm.ob_stack.items[index].disabled = true;
        } else if (result == .bool or result == .null) {
            transformed = "";
        } else {
            transformed = try @import("strings.zig").coerceToString(ctx, result);
        }
    }
    // Output produced inside a handler is not forwarded.
    ctx.vm.output.shrinkRetainingCapacity(level.start);
    if (!discard) try ctx.vm.output.appendSlice(ctx.allocator, transformed);
    if (final) {
        _ = ctx.vm.ob_stack.pop();
        if (level.callback) |cb| ctx.vm.releaseValue(cb);
    } else {
        ctx.vm.ob_stack.items[index].start = ctx.vm.output.items.len;
    }
    return if (get) NativeResult.shareString(raw_owned) else NativeResult.scalar(.{ .bool = true });
}

fn native_ob_get_clean(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return processBuffer(ctx, true, true, true);
}

fn native_ob_end_clean(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return processBuffer(ctx, true, true, false);
}

fn native_ob_get_contents(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    if (ctx.vm.ob_stack.items.len == 0) return NativeResult.scalar(.{ .bool = false });
    const level = ctx.vm.ob_stack.getLast();
    if (level.disabled) return NativeResult.literal("");
    return NativeResult.copyString(ctx.allocator, ctx.vm.output.items[level.start..]);
}

fn native_ob_get_level(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = @intCast(ctx.vm.ob_stack.items.len) });
}

fn native_ob_end_flush(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return processBuffer(ctx, false, true, false);
}

fn native_ob_get_flush(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return processBuffer(ctx, false, true, true);
}

fn native_ob_flush(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return processBuffer(ctx, false, false, false);
}

fn native_ob_clean(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return processBuffer(ctx, true, false, false);
}

fn native_ob_get_length(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    if (ctx.vm.ob_stack.items.len == 0) return NativeResult.scalar(.{ .bool = false });
    const level = ctx.vm.ob_stack.getLast();
    if (level.disabled) return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = @intCast(ctx.vm.output.items.len - level.start) });
}

fn native_ob_implicit_flush(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.null);
}

fn native_flush(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // CLI: nothing to flush at HTTP level
    return NativeResult.scalar(.null);
}

fn native_ob_get_status(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const full_status = args.len >= 1 and args[0].isTruthy();
    const stack_len = ctx.vm.ob_stack.items.len;
    if (stack_len == 0) {
        return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    }
    if (!full_status) {
        const arr = try ctx.createArray();
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("name") }, .{ .string = Value.String.borrowed("default output handler") });
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("type") }, .{ .int = 0 });
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("flags") }, .{ .int = 112 });
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("level") }, .{ .int = @intCast(stack_len - 1) });
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("chunk_size") }, .{ .int = 0 });
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("buffer_size") }, .{ .int = 16384 });
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("buffer_used") }, .{ .int = 0 });
        return NativeResult.borrowed(.{ .array = arr });
    }
    const result = try ctx.createArray();
    var i: usize = 0;
    while (i < stack_len) : (i += 1) {
        const sub = try ctx.createArray();
        try sub.set(ctx.allocator, .{ .string = Value.String.borrowed("name") }, .{ .string = Value.String.borrowed("default output handler") });
        try sub.set(ctx.allocator, .{ .string = Value.String.borrowed("type") }, .{ .int = 0 });
        try sub.set(ctx.allocator, .{ .string = Value.String.borrowed("flags") }, .{ .int = 112 });
        try sub.set(ctx.allocator, .{ .string = Value.String.borrowed("level") }, .{ .int = @intCast(i) });
        try sub.set(ctx.allocator, .{ .string = Value.String.borrowed("chunk_size") }, .{ .int = 0 });
        try sub.set(ctx.allocator, .{ .string = Value.String.borrowed("buffer_size") }, .{ .int = 16384 });
        try sub.set(ctx.allocator, .{ .string = Value.String.borrowed("buffer_used") }, .{ .int = 0 });
        try result.append(ctx.allocator, .{ .array = sub });
    }
    return NativeResult.borrowed(.{ .array = result });
}

fn native_ob_list_handlers(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    for (0..ctx.vm.ob_stack.items.len) |_| {
        try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("default output handler") });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_header(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.null);
    const hdr = args[0].string.bytes();
    const replace = args.len < 2 or args[1] != .bool or args[1].bool;

    if (startsWithIgnoreCase(hdr, "Content-Type:")) {
        if (std.mem.indexOf(u8, hdr, ": ")) |sep| {
            ctx.vm.response_content_type = try ctx.createString(hdr[sep + 2 ..]);
        }
    }

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

    var buf = std.ArrayListUnmanaged(u8){};
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

fn startsWithIgnoreCase(s: []const u8, prefix: []const u8) bool {
    return s.len >= prefix.len and std.ascii.eqlIgnoreCase(s[0..prefix.len], prefix);
}
