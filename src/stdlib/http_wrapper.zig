// the http:// stream wrapper (ext/standard/http_fopen_wrapper.c): one
// request over a socket stream, the response headers read off it into the
// wrapper data and $http_response_header, redirects followed, a chunked
// body decoded by the dechunk filter. what is left on the socket is the
// body, read through the stream
const std = @import("std");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const PhpObject = value_mod.PhpObject;
const PhpArray = value_mod.PhpArray;
const vm_mod = @import("../runtime/vm.zig");
const NativeContext = vm_mod.NativeContext;
const streams = @import("streams.zig");
const stream_filters = @import("stream_filters.zig");
const user_streams = @import("user_streams.zig");
const network = @import("network.zig");
const fs = @import("filesystem.zig");

const RuntimeError = error{ RuntimeError, OutOfMemory };

const HEADER_MAX_LOCATION_SIZE = 8182;

// the response headers array exists once a request was sent
threadlocal var headers_started: bool = false;
const REDIRECT_MAX = 20;

const FLAG_HEADER_INIT: u8 = 1;
const FLAG_REDIRECTED: u8 = 2;
const FLAG_KEEP_METHOD: u8 = 4;
const FLAG_STRIP_AUTH: u8 = 8;

const HAVE_USER_AGENT: u8 = 1;
const HAVE_HOST: u8 = 2;
const HAVE_AUTH: u8 = 4;
const HAVE_FROM: u8 = 8;
const HAVE_CONTENT_LENGTH: u8 = 16;
const HAVE_TYPE: u8 = 32;
const HAVE_CONNECTION: u8 = 64;

// STREAM_NOTIFY_* codes and severities
pub const NOTIFY_CONNECT = 2;
pub const NOTIFY_AUTH_REQUIRED = 3;
pub const NOTIFY_MIME_TYPE_IS = 4;
pub const NOTIFY_FILE_SIZE_IS = 5;
pub const NOTIFY_REDIRECTED = 6;
pub const NOTIFY_PROGRESS = 7;
pub const NOTIFY_COMPLETED = 8;
pub const NOTIFY_FAILURE = 9;
pub const NOTIFY_AUTH_RESULT = 10;

const Url = struct {
    scheme: []const u8,
    user: ?[]const u8 = null,
    pass: ?[]const u8 = null,
    host: []const u8 = "",
    port: u16 = 0,
    path: ?[]const u8 = null,
    query: ?[]const u8 = null,
};

// php_url_parse for the parts the wrapper uses
fn parseUrl(url: []const u8) ?Url {
    const colon = std.mem.indexOf(u8, url, "://") orelse return null;
    var u = Url{ .scheme = url[0..colon] };
    var rest = url[colon + 3 ..];
    const auth_end = std.mem.indexOfAny(u8, rest, "/?#") orelse rest.len;
    var authority = rest[0..auth_end];
    rest = rest[auth_end..];
    if (std.mem.lastIndexOfScalar(u8, authority, '@')) |at| {
        const userinfo = authority[0..at];
        authority = authority[at + 1 ..];
        if (std.mem.indexOfScalar(u8, userinfo, ':')) |c| {
            u.user = userinfo[0..c];
            u.pass = userinfo[c + 1 ..];
        } else u.user = userinfo;
    }
    if (authority.len > 0 and authority[0] == '[') {
        const close = std.mem.indexOfScalar(u8, authority, ']') orelse return null;
        u.host = authority[0 .. close + 1];
        const after = authority[close + 1 ..];
        if (after.len > 1 and after[0] == ':') u.port = std.fmt.parseUnsigned(u16, after[1..], 10) catch return null;
    } else if (std.mem.lastIndexOfScalar(u8, authority, ':')) |c| {
        u.host = authority[0..c];
        if (c + 1 < authority.len) u.port = std.fmt.parseUnsigned(u16, authority[c + 1 ..], 10) catch return null;
    } else u.host = authority;
    if (u.host.len == 0) return null;
    const frag = std.mem.indexOfScalar(u8, rest, '#') orelse rest.len;
    rest = rest[0..frag];
    if (std.mem.indexOfScalar(u8, rest, '?')) |q| {
        u.query = rest[q + 1 ..];
        rest = rest[0..q];
    }
    if (rest.len > 0) u.path = rest;
    return u;
}

fn contextOption(context: ?*PhpObject, wrapper: []const u8, name: []const u8) ?Value {
    const c = context orelse return null;
    const options = c.get("options");
    if (options != .array) return null;
    const w = options.array.get(.{ .string = Value.String.borrowed(wrapper) });
    if (w != .array) return null;
    const k: PhpArray.Key = .{ .string = Value.String.borrowed(name) };
    if (!w.array.contains(k)) return null;
    return w.array.get(k);
}

// php_stream_notification_notify: the context's notification callback
pub fn notify(ctx: *NativeContext, context: ?*PhpObject, code: i64, severity: i64, msg: ?[]const u8, xcode: i64, sofar: i64, max: i64) RuntimeError!void {
    const c = context orelse return;
    const callback = c.get("notification");
    if (callback == .null) return;
    const msg_v: Value = if (msg) |m| .{ .string = try Value.String.adopt(ctx.allocator, try ctx.allocator.dupe(u8, m)) } else .null;
    defer ctx.vm.releaseValue(msg_v);
    const args = [_]Value{ .{ .int = code }, .{ .int = severity }, msg_v, .{ .int = xcode }, .{ .int = sofar }, .{ .int = max } };
    _ = ctx.vm.callValueCallable(callback, &args) catch |err| {
        if (ctx.vm.pending_exception != null) return err;
        try fs.warnDocref(ctx, "Failed to call user notifier", .{});
    };
}

fn lower(a: std.mem.Allocator, s: []const u8) ![]u8 {
    const out = try a.dupe(u8, s);
    for (out) |*c| c.* = std.ascii.toLower(c.*);
    return out;
}

fn nextHeaderLine(s: []const u8, i: usize) usize {
    var p = i;
    while (p < s.len and s[p] != '\r' and s[p] != '\n') p += 1;
    if (p < s.len and s[p] == '\r') p += 1;
    if (p < s.len and s[p] == '\n') p += 1;
    return p;
}

// strip_header: drops a header (and its folded lines) from both bags
fn stripHeader(bag: *std.ArrayListUnmanaged(u8), lc_bag: *std.ArrayListUnmanaged(u8), name: []const u8) void {
    var i: usize = 0;
    while (i < lc_bag.items.len) {
        const lc = lc_bag.items;
        if (!std.mem.startsWith(u8, lc[i..], name)) {
            i = nextHeaderLine(lc, i);
            continue;
        }
        var colon = i + name.len;
        while (colon < lc.len and (lc[colon] == ' ' or lc[colon] == '\t')) colon += 1;
        if (colon >= lc.len or lc[colon] != ':') {
            i = nextHeaderLine(lc, i);
            continue;
        }
        var next = nextHeaderLine(lc, i);
        while (next < lc.len and (lc[next] == ' ' or lc[next] == '\t')) next = nextHeaderLine(lc, next);
        var start = i;
        if (next >= lc.len) {
            while (start > 0 and (lc[start - 1] == '\r' or lc[start - 1] == '\n')) start -= 1;
        }
        bag.replaceRangeAssumeCapacity(start, next - start, &.{});
        lc_bag.replaceRangeAssumeCapacity(start, next - start, &.{});
        i = start;
    }
}

fn checkHasHeader(headers: []const u8, header: []const u8) bool {
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, headers, from, header)) |s| {
        if (s == 0 or (s >= 2 and headers[s - 1] == '\n' and headers[s - 2] == '\r')) return true;
        from = s + 1;
    }
    return false;
}

fn trimLine(line: []const u8) struct { text: []const u8, space_trimmed: bool } {
    var end = line.len;
    while (end > 0 and (line[end - 1] == '\n' or line[end - 1] == '\r')) end -= 1;
    var trimmed = false;
    if (end > 0 and (line[end - 1] == ' ' or line[end - 1] == '\t')) {
        trimmed = true;
        while (end > 0 and (line[end - 1] == ' ' or line[end - 1] == '\t')) end -= 1;
    }
    return .{ .text = line[0..end], .space_trimmed = trimmed };
}

const HeaderInfo = struct {
    dechunk: bool = false,
    file_size: i64 = 0,
    err: bool = false,
    follow_location: bool = true,
    location: ?[]u8 = null,
};

// the stream for an http:// url, or null with why in the wrapper error log
pub fn open(ctx: *NativeContext, path: []const u8, mode: []const u8, options: i64, context: ?*PhpObject) RuntimeError!?*PhpObject {
    const headers = try ctx.createArray();
    headers.retain();
    defer ctx.vm.arrayRelease(headers);
    if (ctx.vm.last_http_response_headers) |previous| ctx.vm.arrayRelease(previous);
    ctx.vm.last_http_response_headers = null;
    headers_started = false;
    const stream = try openEx(ctx, path, mode, options, context, REDIRECT_MAX, FLAG_HEADER_INIT, headers);
    if (stream) |st| {
        const s = try streams.of(ctx, st);
        headers.retain();
        s.wrapperdata = .{ .array = headers };
    }
    // a request that never went out leaves no headers behind
    if (!headers_started) return stream;
    headers.retain();
    ctx.vm.last_http_response_headers = headers;
    const copy = try ctx.vm.copyValue(.{ .array = headers });
    try ctx.vm.setVariableByName(ctx.vm.currentFrame(), "$http_response_header", copy);
    return stream;
}

fn openEx(ctx: *NativeContext, path: []const u8, mode: []const u8, options: i64, context: ?*PhpObject, redirect_max_arg: i64, flags: u8, headers: *PhpArray) RuntimeError!?*PhpObject {
    var redirect_max = redirect_max_arg;
    if (redirect_max < 1) {
        try user_streams.logError(ctx, options, "Redirection limit reached, aborting", .{});
        return null;
    }
    const a = ctx.allocator;
    var resource = parseUrl(path) orelse return null;
    if (std.mem.indexOfAny(u8, mode, "awx+") != null) {
        try user_streams.logError(ctx, options, "HTTP wrapper does not support writeable connections", .{});
        return null;
    }
    const header_init = flags & FLAG_HEADER_INIT != 0;
    const redirected = flags & FLAG_REDIRECTED != 0;
    const keep_method = flags & FLAG_KEEP_METHOD != 0;
    var request_fulluri = false;
    if (contextOption(context, "http", "request_fulluri")) |v| request_fulluri = v.isTruthy();
    const use_ssl = resource.scheme.len > 4 and (resource.scheme[4] == 's' or resource.scheme[4] == 'S');
    if (resource.port == 0) resource.port = if (use_ssl) 443 else 80;
    var use_proxy = false;
    var transport: []const u8 = undefined;
    var transport_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer transport_buf.deinit(a);
    if (contextOption(context, "http", "proxy")) |p| if (p == .string and p.string.bytes().len > 0) {
        use_proxy = true;
        transport = p.string.bytes();
    };
    if (!use_proxy) {
        try transport_buf.print(a, "{s}://{s}:{d}", .{ if (use_ssl) "ssl" else "tcp", resource.host, resource.port });
        transport = transport_buf.items;
    }
    if (request_fulluri and std.mem.indexOfAny(u8, path, "\r\n") != null) {
        try user_streams.logError(ctx, options, "HTTP wrapper full URI path does not allow CR or LF characters", .{});
        return null;
    }
    var timeout_s: f64 = network.defaultSocketTimeoutSeconds(ctx);
    if (contextOption(context, "http", "timeout")) |t| {
        const d = Value.toFloat(t);
        const timeoutmax: f64 = @as(f64, @floatFromInt(std.math.maxInt(u64))) / 1000000.0;
        if (d > timeoutmax) {
            try user_streams.logError(ctx, options, "timeout must be lower than {d}", .{@as(u64, @intFromFloat(timeoutmax))});
            return null;
        }
        timeout_s = d;
    }
    if (use_ssl) {
        try user_streams.logError(ctx, options, "Unable to find the socket transport \"ssl\" - did you forget to enable it when you configured PHP?", .{});
        return null;
    }
    const stream = (try network.connectTransport(ctx, transport, timeout_s, options)) orelse return null;
    var keep_stream = false;
    defer if (!keep_stream) {
        _ = fs.closeStream(ctx, stream) catch {};
    };
    const s = try streams.of(ctx, stream);
    // the headers are always \r\n
    const eol_detect = s.detect_eol;
    const eol_mac = s.eol_mac;
    s.detect_eol = false;
    s.eol_mac = false;
    if (context) |c| try stream.set(a, "__context", .{ .resource = c });
    try notify(ctx, context, NOTIFY_CONNECT, 0, null, 0, 0, 0);

    if (header_init) if (contextOption(context, "http", "max_redirects")) |v| {
        redirect_max = Value.toInt(v);
    };

    var req: std.ArrayListUnmanaged(u8) = .empty;
    defer req.deinit(a);
    var custom_method = false;
    if (contextOption(context, "http", "method")) |m| if (m == .string and m.string.bytes().len > 0) {
        const method = m.string.bytes();
        if (!redirected or keep_method or std.mem.eql(u8, method, "GET") or std.mem.eql(u8, method, "HEAD")) {
            custom_method = true;
            try req.appendSlice(a, method);
            try req.append(a, ' ');
        }
    };
    if (!custom_method) try req.appendSlice(a, "GET ");
    if (request_fulluri) {
        try req.appendSlice(a, path);
    } else {
        try req.appendSlice(a, resource.path orelse "/");
        if (resource.query) |q| {
            try req.append(a, '?');
            try req.appendSlice(a, q);
        }
    }
    if (contextOption(context, "http", "protocol_version")) |v| {
        try req.print(a, " HTTP/{d:.1}\r\n", .{Value.toFloat(v)});
    } else try req.appendSlice(a, " HTTP/1.1\r\n");

    var have: u8 = 0;
    var user_headers: std.ArrayListUnmanaged(u8) = .empty;
    defer user_headers.deinit(a);
    var has_user_headers = false;
    if (contextOption(context, "http", "header")) |hv| {
        var raw: std.ArrayListUnmanaged(u8) = .empty;
        defer raw.deinit(a);
        if (hv == .array) {
            for (hv.array.entries.items) |e| {
                const v = if (e.ref) |r| r.* else e.value;
                if (v != .string) continue;
                try raw.appendSlice(a, v.string.bytes());
                try raw.appendSlice(a, "\r\n");
            }
        } else if (hv == .string) {
            try raw.appendSlice(a, hv.string.bytes());
        }
        // php_trim with " \t\n\r\0\x0B" from both ends
        const trimmed = std.mem.trim(u8, raw.items, " \t\n\r\x00\x0b");
        if (trimmed.len > 0) {
            try user_headers.appendSlice(a, trimmed);
            var lc: std.ArrayListUnmanaged(u8) = .empty;
            defer lc.deinit(a);
            try lc.appendSlice(a, trimmed);
            for (lc.items) |*c| c.* = std.ascii.toLower(c.*);
            if (!header_init and !keep_method) {
                stripHeader(&user_headers, &lc, "content-length");
                stripHeader(&user_headers, &lc, "content-type");
            }
            if (flags & FLAG_STRIP_AUTH != 0) {
                stripHeader(&user_headers, &lc, "authorization");
                stripHeader(&user_headers, &lc, "cookie");
                if (!use_proxy) stripHeader(&user_headers, &lc, "proxy-authorization");
            }
            has_user_headers = user_headers.items.len > 0;
            if (checkHasHeader(lc.items, "user-agent:")) have |= HAVE_USER_AGENT;
            if (checkHasHeader(lc.items, "host:")) have |= HAVE_HOST;
            if (checkHasHeader(lc.items, "from:")) have |= HAVE_FROM;
            if (checkHasHeader(lc.items, "authorization:")) have |= HAVE_AUTH;
            if (checkHasHeader(lc.items, "content-length:")) have |= HAVE_CONTENT_LENGTH;
            if (checkHasHeader(lc.items, "content-type:")) have |= HAVE_TYPE;
            if (checkHasHeader(lc.items, "connection:")) have |= HAVE_CONNECTION;
        }
    }
    if (have & HAVE_AUTH == 0) if (resource.user) |user| {
        var scratch: std.ArrayListUnmanaged(u8) = .empty;
        defer scratch.deinit(a);
        const du = try fs.urlDecode(a, user);
        defer a.free(du);
        try scratch.appendSlice(a, du);
        try scratch.append(a, ':');
        if (resource.pass) |p| {
            const dp = try fs.urlDecode(a, p);
            defer a.free(dp);
            try scratch.appendSlice(a, dp);
        }
        const enc = std.base64.standard.Encoder;
        const out = try a.alloc(u8, enc.calcSize(scratch.items.len));
        defer a.free(out);
        _ = enc.encode(out, scratch.items);
        try req.print(a, "Authorization: Basic {s}\r\n", .{out});
        try notify(ctx, context, NOTIFY_AUTH_REQUIRED, 0, null, 0, 0, 0);
    };
    if (have & HAVE_FROM == 0) if (ctx.vm.ini_settings.get("from")) |from| if (from.len > 0) {
        try req.print(a, "From: {s}\r\n", .{from});
    };
    if (have & HAVE_HOST == 0) {
        try req.print(a, "Host: {s}", .{resource.host});
        if ((use_ssl and resource.port != 443) or (!use_ssl and resource.port != 80)) try req.print(a, ":{d}", .{resource.port});
        try req.appendSlice(a, "\r\n");
    }
    if (have & HAVE_CONNECTION == 0) try req.appendSlice(a, "Connection: close\r\n");
    var ua: ?[]const u8 = null;
    if (contextOption(context, "http", "user_agent")) |v| {
        if (v == .string) ua = v.string.bytes();
    }
    if (ua == null) ua = ctx.vm.ini_settings.get("user_agent");
    if (have & HAVE_USER_AGENT == 0) if (ua) |u| if (u.len > 0) {
        try req.print(a, "User-Agent: {s}\r\n", .{u});
    };
    const content: ?[]const u8 = if (contextOption(context, "http", "content")) |v| (if (v == .string and v.string.bytes().len > 0) v.string.bytes() else null) else null;
    if (has_user_headers) {
        if ((header_init or keep_method) and have & HAVE_CONTENT_LENGTH == 0) if (content) |body| {
            try req.print(a, "Content-Length: {d}\r\n", .{body.len});
            have |= HAVE_CONTENT_LENGTH;
        };
        try req.appendSlice(a, user_headers.items);
        try req.appendSlice(a, "\r\n");
    }
    if ((header_init or keep_method) and content != null) {
        if (have & HAVE_CONTENT_LENGTH == 0) try req.print(a, "Content-Length: {d}\r\n", .{content.?.len});
        if (have & HAVE_TYPE == 0) {
            try req.appendSlice(a, "Content-Type: application/x-www-form-urlencoded\r\n");
            try fs.noticeDocref(ctx, "Content-type not specified assuming application/x-www-form-urlencoded", .{});
        }
        try req.appendSlice(a, "\r\n");
        try req.appendSlice(a, content.?);
    } else try req.appendSlice(a, "\r\n");

    _ = try streams.write(ctx, stream, req.items);
    headers_started = true;

    // the status line
    var reqok = false;
    var ignore_errors = false;
    var response_code: i64 = 0;
    var status_line: []const u8 = "";
    var status_owned: ?[]u8 = null;
    defer if (status_owned) |l| a.free(l);
    if (!try streams.eof(ctx, stream)) if (try streams.getLine(ctx, stream, 127)) |line| {
        status_owned = line;
        status_line = line;
        response_code = statusCode(line);
        if (contextOption(context, "http", "ignore_errors")) |v| ignore_errors = v.isTruthy();
        if (ignore_errors) reqok = true;
        // 1xx informational responses are skipped up to the real status
        if (response_code >= 100 and response_code < 200 and response_code != 101) {
            while (!try streams.eof(ctx, stream)) {
                const next = (try streams.getLine(ctx, stream, 127)) orelse break;
                a.free(status_owned.?);
                status_owned = next;
                status_line = next;
                if (next.len >= 6 and std.ascii.startsWithIgnoreCase(next, "HTTP/1")) break;
            }
            response_code = statusCode(status_line);
        }
        if (response_code >= 200 and response_code < 400) {
            reqok = true;
        } else {
            try notify(ctx, context, if (response_code == 403) NOTIFY_AUTH_RESULT else NOTIFY_FAILURE, 2, status_line, response_code, 0, 0);
        }
        var shown = status_line;
        if (shown.len >= 1 and shown[shown.len - 1] == '\n') {
            shown = shown[0 .. shown.len - 1];
            if (shown.len >= 1 and shown[shown.len - 1] == '\r') shown = shown[0 .. shown.len - 1];
        } else {
            // the rest of a long status line is read and dropped
            if (try streams.getLine(ctx, stream, null)) |rest| a.free(rest);
        }
        try headers.appendCopiedString(a, shown);
        status_line = shown;
    } else {
        try user_streams.logError(ctx, options, "HTTP request failed!", .{});
        return null;
    } else {
        try user_streams.logError(ctx, options, "HTTP request failed!", .{});
        return null;
    }
    // the full raw status line, newline and all, is what php's failure names
    const raw_status = status_owned.?;

    var info = HeaderInfo{};
    defer if (info.location) |l| a.free(l);
    var last: ?std.ArrayListUnmanaged(u8) = null;
    defer if (last) |*l| l.deinit(a);
    while (!try streams.eof(ctx, stream)) {
        const line = (try streams.getLine(ctx, stream, null)) orelse break;
        defer a.free(line);
        var last_line = false;
        if (line[0] == '\r') {
            if (line.len < 2 or line[1] != '\n') {
                try user_streams.logError(ctx, options, "HTTP invalid header name (cannot start with CR character)!", .{});
                return null;
            }
            last_line = true;
        } else if (line[0] == '\n') last_line = true;
        if (last) |*prev| {
            if (!last_line) {
                const t = trimLine(line);
                if (t.space_trimmed and t.text.len == 0) continue;
                if (t.text[0] == ' ' or t.text[0] == '\t') {
                    // a folded line continues the header before it
                    const folded = std.mem.trimStart(u8, t.text, " \t");
                    try prev.append(a, ' ');
                    try prev.appendSlice(a, folded);
                    continue;
                }
            }
            const ok = try parseHeader(ctx, prev.items, options, context, response_code, headers, &info);
            prev.deinit(a);
            last = null;
            if (!ok) return null;
        } else if (!last_line) {
            if (line[0] == ' ' or line[0] == '\t') {
                try user_streams.logError(ctx, options, "HTTP invalid response format (folding header at the start)!", .{});
                return null;
            }
        }
        if (last_line) break;
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        try buf.appendSlice(a, trimLine(line).text);
        last = buf;
    }
    if (last) |*prev| {
        _ = try parseHeader(ctx, prev.items, options, context, response_code, headers, &info);
        prev.deinit(a);
        last = null;
    }

    if (!reqok or (info.location != null and info.follow_location)) {
        if (!info.follow_location or (ignore_errors and redirect_max <= 1)) {
            return finish(ctx, stream, s, mode, header_init, headers, &info, context, eol_detect, eol_mac, &keep_stream);
        }
        if (info.location) |loc| try notify(ctx, context, NOTIFY_REDIRECTED, 0, loc, 0, 0, 0);
        _ = try fs.closeStream(ctx, stream);
        keep_stream = true; // closed already
        const loc = info.location orelse {
            try user_streams.logError(ctx, options, "HTTP request failed! {s}", .{raw_status});
            return null;
        };
        var new_path: std.ArrayListUnmanaged(u8) = .empty;
        defer new_path.deinit(a);
        const absolute = loc.len >= 8 and (std.ascii.startsWithIgnoreCase(loc, "http://") or std.ascii.startsWithIgnoreCase(loc, "https://") or std.ascii.startsWithIgnoreCase(loc, "ftp://") or std.ascii.startsWithIgnoreCase(loc, "ftps://"));
        if (!absolute) {
            var loc_path: std.ArrayListUnmanaged(u8) = .empty;
            defer loc_path.deinit(a);
            if (loc.len == 0 or loc[0] != '/') {
                if (loc.len > 1 and resource.path != null) {
                    const p = resource.path.?;
                    const dir = if (std.mem.lastIndexOfScalar(u8, p, '/')) |slash| p[0 .. slash + 1] else "/";
                    if (std.mem.eql(u8, dir, "/")) {
                        try loc_path.print(a, "/{s}", .{loc});
                    } else {
                        try loc_path.print(a, "{s}/{s}", .{ dir[0 .. dir.len - 1], loc });
                    }
                } else try loc_path.print(a, "/{s}", .{loc});
            } else try loc_path.appendSlice(a, loc);
            if ((use_ssl and resource.port != 443) or (!use_ssl and resource.port != 80)) {
                try new_path.print(a, "{s}://{s}:{d}{s}", .{ resource.scheme, resource.host, resource.port, loc_path.items });
            } else {
                try new_path.print(a, "{s}://{s}{s}", .{ resource.scheme, resource.host, loc_path.items });
            }
        } else try new_path.appendSlice(a, loc);
        const new_resource = parseUrl(new_path.items) orelse {
            try user_streams.logError(ctx, options, "Invalid redirect URL! {s}", .{new_path.items});
            return null;
        };
        const default_port: u16 = if (use_ssl) 443 else 80;
        const same_origin = std.ascii.eqlIgnoreCase(resource.scheme, new_resource.scheme) and std.ascii.eqlIgnoreCase(resource.host, new_resource.host) and
            (if (resource.port != 0) resource.port else default_port) == (if (new_resource.port != 0) new_resource.port else default_port);
        // control characters in the user, password or path refuse the redirect
        inline for (.{ "user", "pass", "path" }) |field| {
            if (@field(new_resource, field)) |part| {
                const decoded = try fs.urlDecode(a, part);
                defer a.free(decoded);
                for (decoded) |c| if (std.ascii.isControl(c)) {
                    try user_streams.logError(ctx, options, "Invalid redirect URL! {s}", .{new_path.items});
                    return null;
                };
            }
        }
        var new_flags: u8 = FLAG_REDIRECTED | (flags & FLAG_STRIP_AUTH);
        if (!same_origin) new_flags |= FLAG_STRIP_AUTH;
        if (response_code == 307 or response_code == 308) new_flags |= FLAG_KEEP_METHOD;
        const owned_path = try a.dupe(u8, new_path.items);
        defer a.free(owned_path);
        return openEx(ctx, owned_path, mode, options, context, redirect_max - 1, new_flags, headers);
    }
    return finish(ctx, stream, s, mode, header_init, headers, &info, context, eol_detect, eol_mac, &keep_stream);
}

fn finish(ctx: *NativeContext, stream: *PhpObject, s: *streams.Stream, mode: []const u8, header_init: bool, headers: *PhpArray, info: *HeaderInfo, context: ?*PhpObject, eol_detect: bool, eol_mac: bool, keep: *bool) RuntimeError!?*PhpObject {
    keep.* = true;
    _ = header_init;
    _ = headers;
    try streams.progressInit(ctx, context, info.file_size);
    s.detect_eol = eol_detect;
    s.eol_mac = eol_mac;
    s.position = 0;
    try stream.setCopiedString(ctx.allocator, "__mode", mode);
    if (info.dechunk) {
        if (try stream_filters.create(ctx, "dechunk", null)) |f| {
            if (!try stream_filters.append(ctx, stream, &s.readfilters, f)) try stream_filters.remove(ctx, f);
        }
    }
    // body bytes that came in with the headers count as read
    if (s.writepos > s.readpos) try streams.progressIncrement(ctx, context, @intCast(s.writepos - s.readpos));
    return stream;
}

fn statusCode(line: []const u8) i64 {
    if (line.len <= 9) return 0;
    // atoi
    var i: usize = 9;
    while (i < line.len and std.ascii.isWhitespace(line[i])) i += 1;
    var neg = false;
    if (i < line.len and (line[i] == '-' or line[i] == '+')) {
        neg = line[i] == '-';
        i += 1;
    }
    var n: i64 = 0;
    while (i < line.len and std.ascii.isDigit(line[i])) : (i += 1) n = n *% 10 +% (line[i] - '0');
    return if (neg) -n else n;
}

// php_stream_http_response_headers_parse for one complete header line:
// false (after logging why) for a malformed one
fn parseHeader(ctx: *NativeContext, line: []const u8, options: i64, context: ?*PhpObject, response_code: i64, headers: *PhpArray, info: *HeaderInfo) RuntimeError!bool {
    const colon = std.mem.indexOfScalar(u8, line, ':') orelse {
        info.err = true;
        try user_streams.logError(ctx, options, "HTTP invalid response format (no colon in header line)!", .{});
        return false;
    };
    for (line[@min(1, line.len)..colon]) |c| if (c == ' ' or c == '\t') {
        info.err = true;
        try user_streams.logError(ctx, options, "HTTP invalid response format (space in header name)!", .{});
        return false;
    };
    var value = line[colon + 1 ..];
    while (value.len > 1 and (value[0] == ' ' or value[0] == '\t')) value = value[1..];
    if (value.len == 1 and (value[0] == ' ' or value[0] == '\t')) value = value[1..];
    var store = true;
    if (std.ascii.startsWithIgnoreCase(line, "Location:")) {
        if (contextOption(context, "http", "follow_location")) |v| {
            info.follow_location = v.isTruthy();
        } else if (!((response_code >= 300 and response_code < 304) or response_code == 307 or response_code == 308)) {
            info.follow_location = false;
        }
        if (value.len > HEADER_MAX_LOCATION_SIZE) {
            info.err = true;
            try user_streams.logError(ctx, options, "HTTP Location header size is over the limit of {d} bytes", .{HEADER_MAX_LOCATION_SIZE});
            return false;
        }
        if (info.location) |l| ctx.allocator.free(l);
        info.location = try ctx.allocator.dupe(u8, value);
    } else if (std.ascii.startsWithIgnoreCase(line, "Content-Type:")) {
        try notify(ctx, context, NOTIFY_MIME_TYPE_IS, 0, value, 0, 0, 0);
    } else if (std.ascii.startsWithIgnoreCase(line, "Content-Length:")) {
        if (value.len > 0 and std.ascii.isDigit(value[0])) {
            if (std.fmt.parseUnsigned(u64, value, 10)) |n| {
                info.file_size = @intCast(@min(n, std.math.maxInt(i64)));
                try notify(ctx, context, NOTIFY_FILE_SIZE_IS, 0, line, 0, 0, info.file_size);
            } else |_| {}
        }
    } else if (std.ascii.startsWithIgnoreCase(line, "Transfer-Encoding:") and std.ascii.startsWithIgnoreCase(value, "Chunked")) {
        var decode = true;
        if (contextOption(context, "http", "auto_decode")) |v| decode = v.isTruthy();
        if (decode) {
            info.dechunk = true;
            store = false;
        }
    }
    if (store) try headers.appendCopiedString(ctx.allocator, line);
    return true;
}
