// the ftp:// and ftps:// stream wrapper (ext/standard/ftp_fopen_wrapper.c):
// a control connection per operation, AUTH TLS for ftps, a passive data
// connection for file transfers and listings, and the one-command
// operations (SIZE, MDTM, CWD, DELE, RNFR/RNTO, MKD, RMD)
const std = @import("std");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const PhpObject = value_mod.PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const platform = @import("../platform.zig");
const streams = @import("streams.zig");
const user_streams = @import("user_streams.zig");
const network = @import("network.zig");
const fs = @import("filesystem.zig");
const se = @import("stream_errors.zig");
const http = @import("http_wrapper.zig");
const xp_ssl = @import("xp_ssl.zig");
const url_mod = @import("url.zig");
const uri = @import("uri.zig");

const RuntimeError = error{ RuntimeError, OutOfMemory };

const wrapper_label = "ftp";

// whether the url is one the ftp wrapper opens (ftp:// or ftps://, in any case)
pub fn isFtpUrl(path: []const u8) bool {
    const colon = std.mem.indexOf(u8, path, "://") orelse return false;
    const scheme = path[0..colon];
    return std.ascii.eqlIgnoreCase(scheme, "ftp") or std.ascii.eqlIgnoreCase(scheme, "ftps");
}

// the reply line get_ftp_result reads into php's char tmp_line[512]
const Line = struct {
    buf: [512]u8 = undefined,
    len: usize = 0,

    fn text(self: *const Line) []const u8 {
        return self.buf[0..self.len];
    }

    // the reply text after the code ("tmp_line + 4"), empty when shorter
    fn after(self: *const Line, n: usize) []const u8 {
        return if (self.len > n) self.buf[n..self.len] else "";
    }

    fn set(self: *Line, bytes: []const u8) void {
        const n = @min(bytes.len, self.buf.len - 1);
        @memcpy(self.buf[0..n], bytes[0..n]);
        self.len = n;
    }

    fn clear(self: *Line) void {
        self.len = 0;
    }
};

// get_ftp_result: reply lines up to a complete status line ("ddd "), its
// code; 0 when the stream ends first
fn getResult(ctx: *NativeContext, stream: *PhpObject, line: *Line) RuntimeError!i64 {
    line.clear();
    while (try streams.getLine(ctx, stream, line.buf.len - 1)) |l| {
        defer ctx.allocator.free(l);
        line.set(l);
        const t = line.text();
        if (t.len >= 4 and std.ascii.isDigit(t[0]) and std.ascii.isDigit(t[1]) and std.ascii.isDigit(t[2]) and t[3] == ' ') {
            // strtol stops at the space: the code is the three digits
            return @as(i64, t[0] - '0') * 100 + @as(i64, t[1] - '0') * 10 + (t[2] - '0');
        }
    }
    return 0;
}

fn send(ctx: *NativeContext, stream: *PhpObject, data: []const u8) RuntimeError!void {
    _ = try streams.write(ctx, stream, data);
}

fn sendf(ctx: *NativeContext, stream: *PhpObject, comptime fmt: []const u8, args: anytype) RuntimeError!void {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    try send(ctx, stream, msg);
}

// php_raw_url_decode: "%xx" a byte, "+" left alone
fn rawUrlDecode(a: std.mem.Allocator, s: []const u8) RuntimeError![]u8 {
    var out = try a.alloc(u8, s.len);
    var n: usize = 0;
    var i: usize = 0;
    while (i < s.len) : (n += 1) {
        if (s[i] == '%' and i + 2 < s.len and std.ascii.isHex(s[i + 1]) and std.ascii.isHex(s[i + 2])) {
            out[n] = std.fmt.parseInt(u8, s[i + 1 .. i + 3], 16) catch unreachable;
            i += 3;
        } else {
            out[n] = s[i];
            i += 1;
        }
    }
    return a.realloc(out, n) catch out[0..n];
}

// a url's parts as php_uri_parse_to_struct gives them: php_url_parse's,
// control characters replaced, owned
const Resource = struct {
    scheme: ?[]u8 = null,
    user: ?[]u8 = null,
    pass: ?[]u8 = null,
    host: []u8 = &.{},
    port: i64 = 0,
    path: ?[]u8 = null,

    fn deinit(self: *Resource, a: std.mem.Allocator) void {
        inline for (.{ "scheme", "user", "pass", "path" }) |f| if (@field(self, f)) |v| a.free(v);
        a.free(self.host);
    }
};

fn parseResource(a: std.mem.Allocator, parser: uri.ParserKind, path: []const u8) RuntimeError!?Resource {
    var parts = (try uri.parseToParts(a, parser, path)) orelse return null;
    defer parts.deinit(a);
    var r = Resource{ .port = parts.port orelse 0 };
    errdefer r.deinit(a);
    r.scheme = parts.scheme;
    parts.scheme = null;
    r.user = parts.user;
    parts.user = null;
    r.pass = parts.password;
    parts.password = null;
    r.host = parts.host orelse try a.dupe(u8, "");
    parts.host = null;
    r.path = parts.path;
    parts.path = null;
    return r;
}

const Conn = struct {
    stream: *PhpObject,
    resource: Resource,
    use_ssl: bool,
    use_ssl_on_data: bool,
    reuseid: bool,
};

fn notifyInfo(ctx: *NativeContext, context: ?*PhpObject, code: i64, msg: ?[]const u8, xcode: i64) RuntimeError!void {
    try http.notify(ctx, context, code, 0, msg, xcode, 0, 0);
}

fn notifyError(ctx: *NativeContext, context: ?*PhpObject, code: i64, msg: ?[]const u8, xcode: i64) RuntimeError!void {
    try http.notify(ctx, context, code, 2, msg, xcode, 0, 0);
}

fn logWarn(ctx: *NativeContext, options: i64, code: se.Code, comptime fmt: []const u8, args: anytype) RuntimeError!void {
    try user_streams.logErrorAt(ctx, options, .{ .code = code, .wrapper = wrapper_label }, fmt, args);
}

fn closeQuietly(ctx: *NativeContext, stream: *PhpObject) void {
    _ = fs.closeStream(ctx, stream) catch {};
}

// php_ftp_fopen_connect: the logged-in control connection, or null (the
// resource comes back for the caller to free either way)
fn connect(ctx: *NativeContext, path: []const u8, options: i64, context: ?*PhpObject, resource_out: *?Resource) RuntimeError!?Conn {
    const a = ctx.allocator;
    const uri_parser = try uri.contextParser(ctx, context, "ftp");
    var resource = (try parseResource(a, uri_parser, path)) orelse return null;
    if (resource.path == null) {
        resource_out.* = resource;
        return null;
    }
    var keep_resource = false;
    defer if (!keep_resource) resource.deinit(a);
    const use_ssl = if (resource.scheme) |s| std.ascii.eqlIgnoreCase(s, "ftps") else false;
    if (resource.port == 0) resource.port = 21;
    const transport = try std.fmt.allocPrint(a, "tcp://{s}:{d}", .{ resource.host, resource.port });
    defer a.free(transport);
    const stream = (try network.connectXport(ctx, transport, context, null)) orelse return null;
    var ok = false;
    defer if (!ok) closeQuietly(ctx, stream);
    if (context) |c| if (stream.get("__context") != .resource) try stream.set(a, "__context", .{ .resource = c });
    try notifyInfo(ctx, context, http.NOTIFY_CONNECT, null, 0);

    var line = Line{};
    var result = try getResult(ctx, stream, &line);
    if (result > 299 or result < 200) {
        try notifyError(ctx, context, http.NOTIFY_FAILURE, line.text(), result);
        return null;
    }
    var reuseid = false;
    var use_ssl_on_data = false;
    if (use_ssl) {
        try send(ctx, stream, "AUTH TLS\r\n");
        result = try getResult(ctx, stream, &line);
        if (result != 234) {
            // no AUTH TLS: try AUTH SSL
            try send(ctx, stream, "AUTH SSL\r\n");
            result = try getResult(ctx, stream, &line);
            if (result != 334) {
                try logWarn(ctx, options, .SslNotSupported, "Server doesn't support FTPS.", .{});
                return null;
            }
            // an old ftpd-ssl wants the old SSL session id reused
            reuseid = true;
        }
        if (try xp_ssl.cryptoSetup(ctx, stream, xp_ssl.SSLv23_CLIENT, null) < 0 or try xp_ssl.cryptoEnable(ctx, stream, true) < 0) {
            try logWarn(ctx, options, .SslNotSupported, "Unable to activate SSL mode", .{});
            return null;
        }
        // PBSZ 0, whatever the answer
        try send(ctx, stream, "PBSZ 0\r\n");
        _ = try getResult(ctx, stream, &line);
        // data connections are protected too
        try send(ctx, stream, "PROT P\r\n");
        result = try getResult(ctx, stream, &line);
        use_ssl_on_data = (result >= 200 and result <= 299) or reuseid;
    }

    if (resource.user) |raw_user| {
        const user = try rawUrlDecode(a, raw_user);
        a.free(raw_user);
        resource.user = user;
        if (hasControl(user)) {
            try logWarn(ctx, options, .AuthFailed, "Invalid login {s}", .{user});
            return null;
        }
        try sendf(ctx, stream, "USER {s}\r\n", .{user});
    } else try send(ctx, stream, "USER anonymous\r\n");
    result = try getResult(ctx, stream, &line);

    // a password, when asked for one
    if (result >= 300 and result <= 399) {
        try notifyInfo(ctx, context, http.NOTIFY_AUTH_REQUIRED, line.text(), 0);
        if (resource.pass) |raw_pass| {
            const pass = try rawUrlDecode(a, raw_pass);
            a.free(raw_pass);
            resource.pass = pass;
            if (hasControl(pass)) {
                try logWarn(ctx, options, .AuthFailed, "Invalid password {s}", .{pass});
                return null;
            }
            try sendf(ctx, stream, "PASS {s}\r\n", .{pass});
        } else if (ctx.vm.ini_settings.get("from")) |from| {
            if (from.len > 0) try sendf(ctx, stream, "PASS {s}\r\n", .{from}) else try send(ctx, stream, "PASS anonymous\r\n");
        } else try send(ctx, stream, "PASS anonymous\r\n");
        result = try getResult(ctx, stream, &line);
        if (result > 299 or result < 200) {
            try notifyError(ctx, context, http.NOTIFY_AUTH_RESULT, line.text(), result);
        } else try notifyInfo(ctx, context, http.NOTIFY_AUTH_RESULT, line.text(), result);
    }
    if (result > 299 or result < 200) return null;
    ok = true;
    keep_resource = true;
    resource_out.* = resource;
    return .{ .stream = stream, .resource = resource, .use_ssl = use_ssl, .use_ssl_on_data = use_ssl_on_data, .reuseid = reuseid };
}

fn hasControl(s: []const u8) bool {
    for (s) |ch| if (std.ascii.isControl(ch)) return true;
    return false;
}

// strtoul: the value and where the digits stopped (at s when there are none)
fn strtoul(s: []const u8) struct { value: u64, end: usize } {
    var i: usize = 0;
    while (i < s.len and (s[i] == ' ' or (s[i] >= '\t' and s[i] <= '\r'))) i += 1;
    var neg = false;
    if (i < s.len and (s[i] == '+' or s[i] == '-')) {
        neg = s[i] == '-';
        i += 1;
    }
    const start = i;
    var v: u64 = 0;
    var overflow = false;
    while (i < s.len and std.ascii.isDigit(s[i])) : (i += 1) {
        v = std.math.mul(u64, v, 10) catch blk: {
            overflow = true;
            break :blk v;
        };
        v = std.math.add(u64, v, s[i] - '0') catch blk: {
            overflow = true;
            break :blk v;
        };
    }
    if (i == start) return .{ .value = 0, .end = 0 };
    if (overflow) return .{ .value = std.math.maxInt(u64), .end = i };
    return .{ .value = if (neg) 0 -% v else v, .end = i };
}

const Pasv = struct { port: u16, host: ?[]const u8 };

// php_fopen_do_pasv: EPSV, else PASV, for the data connection's port (and
// PASV's address); null when the server gives neither
fn doPasv(ctx: *NativeContext, stream: *PhpObject, ip: *[16]u8) RuntimeError!?Pasv {
    var line = Line{};
    try send(ctx, stream, "EPSV\r\n");
    var result = try getResult(ctx, stream, &line);
    if (result != 229) {
        try send(ctx, stream, "PASV\r\n");
        result = try getResult(ctx, stream, &line);
        if (result != 227) return null;
        // "227 Entering Passive Mode (129,80,95,25,13,221)"
        const t = line.buf[0..line.len];
        var p: usize = @min(4, t.len);
        while (p < t.len and !std.ascii.isDigit(t[p])) p += 1;
        if (p >= t.len) return null;
        const hoststart = p;
        var i: usize = 0;
        while (i < 4) : (i += 1) {
            while (p < t.len and std.ascii.isDigit(t[p])) p += 1;
            if (p >= t.len or t[p] != ',') return null;
            t[p] = '.';
            p += 1;
        }
        // the dots and digits, and php's nul over the last dot, must fit
        if (p - hoststart > ip.len) return null;
        const host_len = p - 1 - hoststart;
        @memcpy(ip[0..host_len], t[hoststart .. p - 1]);
        const msb = strtoul(t[p..]);
        var port: u16 = @truncate(@as(u32, @as(u16, @truncate(msb.value))) * 256);
        p += msb.end;
        if (p >= t.len or t[p] != ',') return null;
        p += 1;
        const lsb = strtoul(t[p..]);
        port +%= @as(u16, @truncate(lsb.value));
        if (port == 0) return null;
        return .{ .port = port, .host = ip[0..host_len] };
    }
    // "229 Entering Extended Passive Mode (|||6446|)"
    const t = line.text();
    var p: usize = @min(4, t.len);
    var bars: usize = 0;
    while (p < t.len) : (p += 1) {
        if (t[p] == '|') {
            bars += 1;
            if (bars == 3) break;
        }
    }
    if (bars < 3) return null;
    const port: u16 = @truncate(strtoul(t[p + 1 ..]).value);
    if (port == 0) return null;
    return .{ .port = port, .host = null };
}

// php_stream_url_wrap_ftp: the data connection a file is read from or
// written to, which keeps its control connection (__ftp_control) until it
// closes; null with the wrapper's errors logged
pub fn open(ctx: *NativeContext, path: []const u8, mode: []const u8, options: i64, context: ?*PhpObject) RuntimeError!?*PhpObject {
    const a = ctx.allocator;
    var read_write: u8 = 0;
    if (std.mem.indexOfAny(u8, mode, "r+") != null) read_write = 1;
    if (std.mem.indexOfAny(u8, mode, "wa+") != null) {
        if (read_write != 0) {
            try logWarn(ctx, options, .ModeNotSupported, "FTP does not support simultaneous read/write connections", .{});
            return null;
        }
        read_write = if (std.mem.indexOfScalar(u8, mode, 'a') != null) 3 else 2;
    }
    if (read_write == 0) {
        try logWarn(ctx, options, .InvalidMode, "Unknown file open mode", .{});
        return null;
    }
    if (http.contextOption(context, "ftp", "proxy") != null) {
        if (read_write == 1) return http.openThroughProxy(ctx, path, mode, options, context);
        try logWarn(ctx, options, .ModeNotSupported, "FTP proxy may only be used in read mode", .{});
        return null;
    }

    var resource: ?Resource = null;
    defer if (resource) |*r| r.deinit(a);
    var line = Line{};
    var result: i64 = 0;
    var error_message: ?[]u8 = null;
    defer if (error_message) |m| a.free(m);
    var control: ?*PhpObject = null;
    fail: {
        const conn = (try connect(ctx, path, options, context, &resource)) orelse break :fail;
        control = conn.stream;
        const stream = conn.stream;
        const res = conn.resource;
        // binary transfers
        try send(ctx, stream, "TYPE I\r\n");
        result = try getResult(ctx, stream, &line);
        if (result > 299 or result < 200) break :fail;
        // the file's size, which says whether it exists
        try sendf(ctx, stream, "SIZE {s}\r\n", .{res.path.?});
        result = try getResult(ctx, stream, &line);
        var file_size: i64 = 0;
        if (read_write == 1) {
            // a file to read must exist
            if (result > 299 or result < 200) break :fail;
            if (std.mem.indexOfScalar(u8, line.text(), ' ')) |sp| {
                file_size = atoi(line.text()[sp + 1 ..]);
                try http.notify(ctx, context, http.NOTIFY_FILE_SIZE_IS, 0, line.text(), result, 0, file_size);
            }
        } else if (read_write == 2) {
            // a new file must not exist, unless the context allows overwriting it
            const allow_overwrite = if (http.contextOption(context, "ftp", "overwrite")) |v| v.isTruthy() else false;
            if (result <= 299 and result >= 200) {
                if (allow_overwrite) {
                    try sendf(ctx, stream, "DELE {s}\r\n", .{res.path.?});
                    result = try getResult(ctx, stream, &line);
                    if (result >= 300 or result <= 199) break :fail;
                } else {
                    try logWarn(ctx, options, .AlreadyExists, "Remote file already exists and overwrite context option not specified", .{});
                    break :fail;
                }
            }
        }
        var ip: [16]u8 = undefined;
        const pasv = (try doPasv(ctx, stream, &ip)) orelse break :fail;
        var command: []const u8 = undefined;
        if (read_write == 1) {
            // a resume position
            if (http.contextOption(context, "ftp", "resume_pos")) |v| if (v == .int and v.int > 0) {
                try sendf(ctx, stream, "REST {d}\r\n", .{v.int});
                result = try getResult(ctx, stream, &line);
                if (result < 300 or result > 399) {
                    try logWarn(ctx, options, .ResumptionFailed, "Unable to resume from offset {d}", .{v.int});
                    break :fail;
                }
            };
            command = "RETR";
        } else command = if (read_write == 2) "STOR" else "APPE";
        // tmp_line holds the command now
        line.set(command);
        try sendf(ctx, stream, "{s} {s}\r\n", .{ command, res.path.? });
        const host = pasv.host orelse res.host;
        const transport = try std.fmt.allocPrint(a, "tcp://{s}:{d}", .{ host, pasv.port });
        defer a.free(transport);
        const datastream = (try network.connectXport(ctx, transport, context, &error_message)) orelse {
            line.clear();
            break :fail;
        };
        result = try getResult(ctx, stream, &line);
        if (result != 150 and result != 125) {
            // the server couldn't send or take the file
            closeQuietly(ctx, datastream);
            break :fail;
        }
        if (context) |c| try datastream.set(a, "__context", .{ .resource = c });
        try streams.progressInit(ctx, context, file_size);
        if (conn.use_ssl_on_data and (try xp_ssl.cryptoSetup(ctx, datastream, xp_ssl.SSLv23_CLIENT, null) < 0 or try xp_ssl.cryptoEnable(ctx, datastream, true) < 0)) {
            try logWarn(ctx, options, .SslNotSupported, "Unable to activate SSL mode", .{});
            closeQuietly(ctx, datastream);
            line.clear();
            break :fail;
        }
        // the data connection keeps its control connection
        try datastream.set(a, "__ftp_control", .{ .resource = stream });
        return datastream;
    }
    if (control) |stream| {
        try notifyError(ctx, context, http.NOTIFY_FAILURE, line.text(), result);
        closeQuietly(ctx, stream);
    }
    if (line.len > 0) try logWarn(ctx, options, .ProtocolError, "FTP server reports {s}", .{line.text()});
    if (error_message) |m| try logWarn(ctx, options, .NetworkSendFailed, "Failed to set up data channel: {s}", .{m});
    return null;
}

fn atoi(s: []const u8) i64 {
    var i: usize = 0;
    while (i < s.len and (s[i] == ' ' or (s[i] >= '\t' and s[i] <= '\r'))) i += 1;
    var neg = false;
    if (i < s.len and (s[i] == '+' or s[i] == '-')) {
        neg = s[i] == '-';
        i += 1;
    }
    var v: i32 = 0;
    while (i < s.len and std.ascii.isDigit(s[i])) : (i += 1) v = v *% 10 +% @as(i32, s[i] - '0');
    return if (neg) -%v else v;
}

// php_stream_ftp_stream_close, after the data connection closed: a stream
// opened for writing (and php's r+ data socket) waits for the transfer's
// result, then the control connection says QUIT and closes. false when the
// server reported a failure
pub fn streamClose(ctx: *NativeContext, obj: *PhpObject) RuntimeError!bool {
    const control_v = obj.get("__ftp_control");
    if (control_v != .resource) return true;
    const control = control_v.resource;
    control.retain();
    defer ctx.vm.releaseValue(.{ .resource = control });
    try obj.set(ctx.allocator, "__ftp_control", .null);
    var ok = true;
    // the data socket's mode is "r+", which has the '+'
    var line = Line{};
    const result = try getResult(ctx, control, &line);
    if (result != 226 and result != 250) {
        try se.raise(ctx, .{ .code = .ProtocolError, .wrapper = wrapper_label }, "FTP server error {d}:{s}", .{ result, line.text() });
        ok = false;
    }
    try send(ctx, control, "QUIT\r\n");
    _ = try fs.closeStream(ctx, control);
    return ok;
}

// php_stream_ftp_opendir, read to its end: the names an NLST lists, each
// php_basename'd and trimmed as php_ftp_dirstream_read does; false with
// the wrapper's errors logged
pub fn listDir(ctx: *NativeContext, path: []const u8, options: i64, context: ?*PhpObject, names: *std.ArrayListUnmanaged(Value.String)) RuntimeError!bool {
    const a = ctx.allocator;
    var resource: ?Resource = null;
    defer if (resource) |*r| r.deinit(a);
    var line = Line{};
    var result: i64 = 0;
    var control: ?*PhpObject = null;
    fail: {
        const conn = (try connect(ctx, path, options, context, &resource)) orelse break :fail;
        control = conn.stream;
        const stream = conn.stream;
        // ascii listings
        try send(ctx, stream, "TYPE A\r\n");
        result = try getResult(ctx, stream, &line);
        if (result > 299 or result < 200) break :fail;
        line.clear();
        var ip: [16]u8 = undefined;
        const pasv = (try doPasv(ctx, stream, &ip)) orelse break :fail;
        const host = pasv.host orelse conn.resource.host;
        const transport = try std.fmt.allocPrint(a, "tcp://{s}:{d}", .{ host, pasv.port });
        defer a.free(transport);
        // php_stream_sock_open_host: no context
        const datastream = (try network.connectXport(ctx, transport, null, null)) orelse break :fail;
        var data_open = true;
        defer if (data_open) closeQuietly(ctx, datastream);
        try sendf(ctx, stream, "NLST {s}\r\n", .{conn.resource.path.?});
        result = try getResult(ctx, stream, &line);
        if (result != 150 and result != 125) break :fail;
        if (context) |c| try datastream.set(a, "__context", .{ .resource = c });
        if (conn.use_ssl_on_data and (try xp_ssl.cryptoSetup(ctx, datastream, xp_ssl.SSLv23_CLIENT, null) < 0 or try xp_ssl.cryptoEnable(ctx, datastream, true) < 0)) {
            try logWarn(ctx, options, .SslNotSupported, "Unable to activate SSL mode", .{});
            break :fail;
        }
        while (!try streams.eof(ctx, datastream)) {
            // php_stream_dirent's d_name holds MAXPATHLEN bytes
            const entry = (try streams.getLine(ctx, datastream, std.fs.max_path_bytes)) orelse break;
            defer a.free(entry);
            var name = fs.phpBasename(entry, "");
            while (name.len > 0 and (name[name.len - 1] == '\n' or name[name.len - 1] == '\r' or name[name.len - 1] == '\t' or name[name.len - 1] == ' ')) name = name[0 .. name.len - 1];
            try names.append(a, try Value.String.create(a, name));
        }
        // closing the directory closes both connections, without a QUIT
        data_open = false;
        closeQuietly(ctx, datastream);
        closeQuietly(ctx, stream);
        return true;
    }
    if (control) |stream| {
        try notifyError(ctx, context, http.NOTIFY_FAILURE, line.text(), result);
        closeQuietly(ctx, stream);
    }
    if (line.len > 0) try logWarn(ctx, options, .ProtocolError, "FTP server reports {s}", .{line.text()});
    return false;
}

extern "c" fn mktime(tm: *CTm) isize;
extern "c" fn gmtime_r(t: *const isize, out: *CTm) ?*CTm;
extern "c" fn time(t: ?*isize) isize;

// struct tm, as glibc and the BSDs lay it out
const CTm = extern struct {
    tm_sec: c_int = 0,
    tm_min: c_int = 0,
    tm_hour: c_int = 0,
    tm_mday: c_int = 0,
    tm_mon: c_int = 0,
    tm_year: c_int = 0,
    tm_wday: c_int = 0,
    tm_yday: c_int = 0,
    tm_isdst: c_int = 0,
    tm_gmtoff: c_long = 0,
    tm_zone: ?[*:0]const u8 = null,
};

// sscanf's %Nd: whitespace, a sign, at most n characters in all
fn scanInt(s: []const u8, pos: *usize, width: usize) ?c_int {
    var i = pos.*;
    while (i < s.len and std.ascii.isWhitespace(s[i])) i += 1;
    const start = i;
    var neg = false;
    if (i < s.len and (s[i] == '+' or s[i] == '-') and width > 1) {
        neg = s[i] == '-';
        i += 1;
    }
    const digits_start = i;
    var v: c_int = 0;
    while (i < s.len and i - start < width and std.ascii.isDigit(s[i])) : (i += 1) v = v *% 10 +% @as(c_int, s[i] - '0');
    if (i == digits_start) return null;
    pos.* = i;
    return if (neg) -%v else v;
}

// MDTM's YYYYMMDDhhmmss, read as php does: as local time, shifted by the
// current offset from GMT
fn mdtmTime(text: []const u8) ?i64 {
    var p: usize = 0;
    while (p < text.len and !std.ascii.isDigit(text[p])) p += 1;
    if (p >= text.len) return null;
    var tm = CTm{};
    inline for (.{ .{ "tm_year", 4 }, .{ "tm_mon", 2 }, .{ "tm_mday", 2 }, .{ "tm_hour", 2 }, .{ "tm_min", 2 }, .{ "tm_sec", 2 } }) |f| {
        @field(tm, f[0]) = scanInt(text, &p, f[1]) orelse return null;
    }
    tm.tm_year -= 1900;
    tm.tm_mon -= 1;
    tm.tm_isdst = -1;
    if (platform.is_windows) {
        // no gmtime_r: the stamp as UTC
        return utcStamp(tm);
    }
    var stamp = time(null);
    var gmbuf = CTm{};
    const gmt = gmtime_r(&stamp, &gmbuf) orelse return null;
    gmt.tm_isdst = -1;
    tm.tm_sec +%= @intCast(stamp - mktime(gmt));
    tm.tm_isdst = gmt.tm_isdst;
    return mktime(&tm);
}

fn utcStamp(tm: CTm) i64 {
    const y: i64 = @as(i64, tm.tm_year) + 1900;
    const m: i64 = @as(i64, tm.tm_mon) + 1;
    const yy = if (m <= 2) y - 1 else y;
    const era = @divFloor(yy, 400);
    const yoe = yy - era * 400;
    const mp = @mod(m + 9, 12);
    const doy = @divFloor(153 * mp + 2, 5) + @as(i64, tm.tm_mday) - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    const days = era * 146097 + doe - 719468;
    return days * 86400 + @as(i64, tm.tm_hour) * 3600 + @as(i64, tm.tm_min) * 60 + tm.tm_sec;
}

// php_stream_ftp_url_stat: what CWD, SIZE and MDTM say about the path;
// null when it can't be stat'ed
pub fn urlStat(ctx: *NativeContext, path: []const u8, context: ?*PhpObject) RuntimeError!?fs.WrapperStat {
    const a = ctx.allocator;
    var resource: ?Resource = null;
    defer if (resource) |*r| r.deinit(a);
    const conn = (try connect(ctx, path, 0, context, &resource)) orelse return null;
    const stream = conn.stream;
    defer closeQuietly(ctx, stream);
    const target = conn.resource.path.?;
    var line = Line{};
    // ftp gives no mode: readable, and a directory if CWD goes there
    var mode: i64 = 0o644;
    try sendf(ctx, stream, "CWD {s}\r\n", .{target});
    var result = try getResult(ctx, stream, &line);
    if (result < 200 or result > 299) {
        mode |= 0o100000;
    } else mode |= 0o040000 | 0o111;
    // some servers refuse SIZE in ascii mode
    try send(ctx, stream, "TYPE I\r\n");
    result = try getResult(ctx, stream, &line);
    if (result < 200 or result > 299) return null;
    var size: i64 = 0;
    try sendf(ctx, stream, "SIZE {s}\r\n", .{target});
    result = try getResult(ctx, stream, &line);
    if (result < 200 or result > 299) {
        // missing, or a directory this server won't size
        if (mode & 0o040000 == 0) return null;
    } else size = atoi(line.after(4));
    try sendf(ctx, stream, "MDTM {s}\r\n", .{target});
    result = try getResult(ctx, stream, &line);
    const mtime: i64 = if (result == 213) mdtmTime(line.after(4)) orelse -1 else -1;
    return .{ .mode = mode, .size = size, .mtime = mtime, .atime = -1, .ctime = -1, .nlink = 1, .rdev = -1, .blksize = 4096, .blocks = @divTrunc(4095 + size, 4096) };
}

// php_stream_ftp_unlink
pub fn unlink(ctx: *NativeContext, url: []const u8, options: i64, context: ?*PhpObject) RuntimeError!bool {
    const a = ctx.allocator;
    var resource: ?Resource = null;
    defer if (resource) |*r| r.deinit(a);
    const conn = (try connect(ctx, url, 0, context, &resource)) orelse {
        try wrapperWarn(ctx, options, .AuthFailed, "Unable to connect to {s}", .{url});
        return false;
    };
    defer closeQuietly(ctx, conn.stream);
    var line = Line{};
    try sendf(ctx, conn.stream, "DELE {s}\r\n", .{conn.resource.path.?});
    const result = try getResult(ctx, conn.stream, &line);
    if (result < 200 or result > 299) {
        try wrapperWarn(ctx, options, .UnlinkFailed, "Error Deleting file: {s}", .{line.text()});
        return false;
    }
    return true;
}

// php_stream_wrapper_warn: at once when the caller reports errors
fn wrapperWarn(ctx: *NativeContext, options: i64, code: se.Code, comptime fmt: []const u8, args: anytype) RuntimeError!void {
    if (options & user_streams.REPORT_ERRORS == 0) return;
    try se.raise(ctx, .{ .code = code, .wrapper = wrapper_label }, fmt, args);
}

// php_stream_ftp_rename: both urls on the same server
pub fn rename(ctx: *NativeContext, url_from: []const u8, url_to: []const u8, options: i64, context: ?*PhpObject) RuntimeError!bool {
    const a = ctx.allocator;
    const uri_parser = try uri.contextParser(ctx, context, "ftp");
    var from = (try parseResource(a, uri_parser, url_from)) orelse return false;
    defer from.deinit(a);
    var to = (try parseResource(a, uri_parser, url_to)) orelse return false;
    defer to.deinit(a);
    if (from.scheme == null or to.scheme == null or !std.mem.eql(u8, from.scheme.?, to.scheme.?) or
        !std.mem.eql(u8, from.host, to.host) or
        (from.port != to.port and from.port *% to.port != 0 and from.port +% to.port != 21) or
        from.path == null or to.path == null) return false;
    var resource: ?Resource = null;
    defer if (resource) |*r| r.deinit(a);
    const conn = (try connect(ctx, url_from, 0, context, &resource)) orelse {
        try wrapperWarn(ctx, options, .AuthFailed, "Unable to connect to {s}", .{from.host});
        return false;
    };
    defer closeQuietly(ctx, conn.stream);
    var line = Line{};
    try sendf(ctx, conn.stream, "RNFR {s}\r\n", .{from.path.?});
    var result = try getResult(ctx, conn.stream, &line);
    if (result < 300 or result > 399) {
        try wrapperWarn(ctx, options, .RenameFailed, "Error Renaming file: {s}", .{line.text()});
        return false;
    }
    try sendf(ctx, conn.stream, "RNTO {s}\r\n", .{to.path.?});
    result = try getResult(ctx, conn.stream, &line);
    if (result < 200 or result > 299) {
        try wrapperWarn(ctx, options, .RenameFailed, "Error Renaming file: {s}", .{line.text()});
        return false;
    }
    return true;
}

// php_stream_ftp_mkdir: MKD, or for a recursive mkdir CWD up the path to
// the deepest directory that exists and MKD each one below it
pub fn mkdir(ctx: *NativeContext, url: []const u8, recursive: bool, options: i64, context: ?*PhpObject) RuntimeError!bool {
    const a = ctx.allocator;
    var resource: ?Resource = null;
    defer if (resource) |*r| r.deinit(a);
    const conn = (try connect(ctx, url, 0, context, &resource)) orelse {
        try wrapperWarn(ctx, options, .AuthFailed, "Unable to connect to {s}", .{url});
        return false;
    };
    defer closeQuietly(ctx, conn.stream);
    const stream = conn.stream;
    var line = Line{};
    var result: i64 = 0;
    if (!recursive) {
        try sendf(ctx, stream, "MKD {s}\r\n", .{conn.resource.path.?});
        result = try getResult(ctx, stream, &line);
    } else {
        // php cuts the path at its slashes in place: buf holds the parts
        // with nuls where the slashes were
        const buf = try a.dupe(u8, conn.resource.path.?);
        defer a.free(buf);
        const e = buf.len;
        var len = cstrlen(buf);
        // strrchr's last answer: null once the path ran out of slashes
        var p: ?usize = null;
        while (true) {
            const slash = std.mem.lastIndexOfScalar(u8, buf[0..len], '/') orelse {
                p = null;
                break;
            };
            buf[slash] = 0;
            len = slash;
            p = slash;
            try sendf(ctx, stream, "CWD {s}\r\n", .{if (len > 0) buf[0..len] else "/"});
            result = try getResult(ctx, stream, &line);
            if (result >= 200 and result <= 299) {
                buf[slash] = '/';
                break;
            }
        }
        try sendf(ctx, stream, "MKD {s}\r\n", .{if (cstrlen(buf) > 0) buf[0..cstrlen(buf)] else "/"});
        result = try getResult(ctx, stream, &line);
        if (result >= 200 and result <= 299) {
            var q = p orelse 0;
            // each directory below the one just made
            while (q != e) : (q += 1) {
                if (buf[q] == 0 and q + 1 < e and buf[q + 1] != 0) {
                    buf[q] = '/';
                    try sendf(ctx, stream, "MKD {s}\r\n", .{buf[0..cstrlen(buf)]});
                    result = try getResult(ctx, stream, &line);
                    if (result < 200 or result > 299) {
                        try wrapperWarn(ctx, options, .MkdirFailed, "{s}", .{line.text()});
                        break;
                    }
                }
            }
        }
    }
    return result >= 200 and result <= 299;
}

fn cstrlen(s: []const u8) usize {
    return std.mem.indexOfScalar(u8, s, 0) orelse s.len;
}

// php_stream_ftp_rmdir
pub fn rmdir(ctx: *NativeContext, url: []const u8, options: i64, context: ?*PhpObject) RuntimeError!bool {
    const a = ctx.allocator;
    var resource: ?Resource = null;
    defer if (resource) |*r| r.deinit(a);
    const conn = (try connect(ctx, url, 0, context, &resource)) orelse {
        try wrapperWarn(ctx, options, .AuthFailed, "Unable to connect to {s}", .{url});
        return false;
    };
    defer closeQuietly(ctx, conn.stream);
    var line = Line{};
    try sendf(ctx, conn.stream, "RMD {s}\r\n", .{conn.resource.path.?});
    const result = try getResult(ctx, conn.stream, &line);
    if (result < 200 or result > 299) {
        try wrapperWarn(ctx, options, .RmdirFailed, "{s}", .{line.text()});
        return false;
    }
    return true;
}
