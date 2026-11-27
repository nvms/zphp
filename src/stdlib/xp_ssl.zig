// php's openssl socket transport (ext/openssl/xp_ssl.c): tcp sockets that
// can switch to TLS. ssl://, tls:// and tlsv1.x:// clients and servers
// enable it when they connect or accept; stream_socket_enable_crypto()
// turns it on for any tcp socket. the state lives on the stream's Stream
// (Stream.tls); reads and writes of an active stream go through SSL_read and
// SSL_write with php's blocking, timeout and error rules
const std = @import("std");
const c = @import("c_tls");
const platform = @import("../platform.zig");
const sys = @import("../sys.zig");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const PhpObject = value_mod.PhpObject;
const PhpArray = value_mod.PhpArray;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const se = @import("stream_errors.zig");
const streams = @import("streams.zig");
const fs = @import("filesystem.zig");
const network = @import("network.zig");
const open_basedir = @import("open_basedir.zig");

const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "stream_socket_enable_crypto", native_stream_socket_enable_crypto },
    .{ "stream_socket_get_crypto_status", native_stream_socket_get_crypto_status },
};

// STREAM_CRYPTO_METHOD_* (php_stream_transport.h)
pub const IS_CLIENT: i64 = 1;
const SSLv2: i64 = 1 << 1;
const SSLv3: i64 = 1 << 2;
const TLSv1_0: i64 = 1 << 3;
const TLSv1_1: i64 = 1 << 4;
const TLSv1_2: i64 = 1 << 5;
const TLSv1_3: i64 = 1 << 6;
pub const TLS_ANY_CLIENT: i64 = TLSv1_0 | TLSv1_1 | TLSv1_2 | TLSv1_3 | IS_CLIENT;
pub const SSLv23_CLIENT: i64 = TLSv1_0 | TLSv1_1 | TLSv1_2 | IS_CLIENT;

pub const STATUS_NONE: i64 = 0;
pub const STATUS_WANT_READ: i64 = 1;
pub const STATUS_WANT_WRITE: i64 = 2;

// openssl built without SSLv3 (as distributions build it) makes TLSv1.0 the
// lowest version php knows
const have_ssl3 = !@hasDecl(c, "OPENSSL_NO_SSL3");
const min_proto_flag: i64 = if (have_ssl3) SSLv3 else TLSv1_0;
const max_proto_flag: i64 = TLSv1_3;

// php_openssl.h
const default_verify_depth: i64 = 9;
const default_reneg_limit: i64 = 2;
const default_reneg_window: i64 = 300;

// ssl.h's SSL_OP_* (SSL_OP_BIT(n)), which translate-c can't take
const SSL_OP_TLSEXT_PADDING: u64 = 1 << 4;
const SSL_OP_SAFARI_ECDHE_ECDSA_BUG: u64 = 1 << 6;
const SSL_OP_IGNORE_UNEXPECTED_EOF: u64 = 1 << 7;
const SSL_OP_DONT_INSERT_EMPTY_FRAGMENTS: u64 = 1 << 11;
const SSL_OP_NO_TICKET: u64 = 1 << 14;
const SSL_OP_NO_COMPRESSION: u64 = 1 << 17;
const SSL_OP_CIPHER_SERVER_PREFERENCE: u64 = 1 << 22;
const SSL_OP_CRYPTOPRO_TLSEXT_BUG: u64 = 1 << 31;
const SSL_OP_ALL: u64 = SSL_OP_CRYPTOPRO_TLSEXT_BUG | SSL_OP_DONT_INSERT_EMPTY_FRAGMENTS | SSL_OP_TLSEXT_PADDING | SSL_OP_SAFARI_ECDHE_ECDSA_BUG;
const SSL_OP_SINGLE_DH_USE: u64 = 0;
pub const default_ciphers = "ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:" ++
    "ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:" ++
    "DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:" ++
    "ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:" ++
    "ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:" ++
    "DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:AES128-GCM-SHA256:" ++
    "AES256-GCM-SHA384:AES128:AES256:HIGH:!SSLv2:!aNULL:!eNULL:!EXPORT:!DES:!MD5:!RC4:!ADH";

const SniCert = struct { name: [:0]u8, ctx: *c.SSL_CTX };

const Reneg = struct {
    prev_handshake: i64 = 0,
    limit: i64,
    window: i64,
    tokens: f32 = 0,
    should_close: bool = false,
};

// php_openssl_netstream_data_t, less the socket fields the stream object
// itself keeps (__fd, __blocking, __timeout_us, __timed_out)
pub const Tls = struct {
    ssl: ?*c.SSL = null,
    ctx: ?*c.SSL_CTX = null,
    // the timeout a client's handshake runs under (the connect timeout), in
    // microseconds; 0 waits as long as it takes
    connect_timeout_us: i64 = 0,
    enable_on_connect: bool = false,
    is_client: bool = false,
    active: bool = false,
    last_status: i64 = STATUS_NONE,
    method: i64 = 0,
    reneg: ?Reneg = null,
    sni_certs: std.ArrayListUnmanaged(SniCert) = .empty,
    alpn: ?[]u8 = null,
    url_name: ?[:0]u8 = null,
    state_set: bool = false,
    // the stream and the call running an openssl operation, for the
    // callbacks openssl makes during it
    stream: ?*PhpObject = null,
    op: ?*NativeContext = null,
    // an error a callback raised, rethrown once openssl returns
    cb_error: ?RuntimeError = null,
};

const allocator = std.heap.c_allocator;

pub fn of(obj: *PhpObject) ?*Tls {
    const s = streams.get(obj) orelse return null;
    return s.tls;
}

fn ensure(ctx: *NativeContext, obj: *PhpObject) RuntimeError!*Tls {
    const s = try streams.of(ctx, obj);
    if (s.tls) |t| return t;
    const t = try allocator.create(Tls);
    t.* = .{};
    s.tls = t;
    return t;
}

// the openssl factory's stream type: every tcp socket (php registers it
// for tcp:// too) can take crypto; unix, udp and udg sockets cannot
pub fn capable(obj: *PhpObject) bool {
    if (!fs.isNetStream(obj)) return false;
    const t = obj.get("__sock_type");
    return t == .string and std.mem.eql(u8, t.string.bytes(), "tcp_socket/ssl");
}

// the transports php_openssl_ssl_socket_factory makes with crypto turned
// on at connect: their method, or null for one that isn't such a transport.
// names are matched as php's transport table does, case and all
pub fn transportMethod(scheme: []const u8, context: ?*PhpObject) ?i64 {
    if (std.mem.eql(u8, scheme, "ssl") or std.mem.eql(u8, scheme, "tls")) return cryptoMethodOption(context, TLS_ANY_CLIENT);
    if (std.mem.eql(u8, scheme, "tlsv1.0")) return TLSv1_0 | IS_CLIENT;
    if (std.mem.eql(u8, scheme, "tlsv1.1")) return TLSv1_1 | IS_CLIENT;
    if (std.mem.eql(u8, scheme, "tlsv1.2")) return TLSv1_2 | IS_CLIENT;
    if (std.mem.eql(u8, scheme, "tlsv1.3")) return TLSv1_3 | IS_CLIENT;
    return null;
}

// php_openssl_get_crypto_method
fn cryptoMethodOption(context: ?*PhpObject, default: i64) i64 {
    const v = option(context, "crypto_method") orelse return default;
    return Value.toInt(v) | IS_CLIENT;
}

// what php_openssl_ssl_socket_factory records about a new tcp socket: the
// handshake method for the crypto transports, the client's connect timeout,
// and the host name the url names, used for SNI and peer name checks
pub fn initSocket(ctx: *NativeContext, obj: *PhpObject, method: ?i64, resource: []const u8, connect_timeout_us: i64) RuntimeError!void {
    const t = try ensure(ctx, obj);
    if (method) |m| {
        t.enable_on_connect = true;
        t.method = m;
    }
    t.connect_timeout_us = connect_timeout_us;
    if (t.url_name) |old| allocator.free(old);
    t.url_name = try urlName(resource);
}

// php_openssl_get_url_name: the host php_url_parse finds in the address,
// trailing dots dropped
fn urlName(resource: []const u8) RuntimeError!?[:0]u8 {
    const u = @import("url.zig").parse(resource) orelse return null;
    var host = u.host orelse return null;
    while (host.len > 0 and host[host.len - 1] == '.') host = host[0 .. host.len - 1];
    if (host.len == 0) return null;
    return try allocator.dupeSentinel(u8, host, 0);
}

// the accepted connection's state: a fresh one, with the listener's method
// when the listener enables crypto on accept (php_openssl_tcp_sockop_accept)
pub fn acceptedFrom(listener: *PhpObject) ?i64 {
    const t = of(listener) orelse return null;
    if (!t.enable_on_connect) return null;
    // the client bit goes
    t.method &= ~IS_CLIENT;
    return t.method;
}

// --- context options -------------------------------------------------------------

// the stream's context (PHP_STREAM_CONTEXT): the one it was made with, or
// php's default one; none for fsockopen's sockets (__context false)
fn streamContext(ctx: *NativeContext, obj: *PhpObject) RuntimeError!?*PhpObject {
    const own = obj.get("__context");
    if (own == .bool) return null;
    if (own == .resource and std.mem.eql(u8, own.resource.class_name, "StreamContext")) return own.resource;
    return try network.defaultContext(ctx);
}

fn contextOfStream(vm: *VM, obj: *PhpObject) ?*PhpObject {
    const own = obj.get("__context");
    if (own == .bool) return null;
    if (own == .resource and std.mem.eql(u8, own.resource.class_name, "StreamContext")) return own.resource;
    return vm.default_stream_context;
}

fn option(context: ?*PhpObject, name: []const u8) ?Value {
    const v = @import("http_wrapper.zig").contextOption(context, "ssl", name) orelse return null;
    return v;
}

fn optionTrue(context: ?*PhpObject, name: []const u8) bool {
    const v = option(context, name) orelse return false;
    return v.isTruthy();
}

// GET_VER_OPT_STRING: the option as a nul-terminated string (try_convert_to_string)
fn optionString(ctx: *NativeContext, context: ?*PhpObject, name: []const u8) RuntimeError!?[:0]u8 {
    const v = option(context, name) orelse return null;
    if (v == .array) {
        try ctx.vm.emitWarning("Array to string conversion");
        return try ctx.allocator.dupeSentinel(u8, "Array", 0);
    }
    const bytes = try ctx.vm.valueToString(v);
    if (ctx.vm.pending_exception != null) return error.RuntimeError;
    return try ctx.allocator.dupeSentinel(u8, bytes, 0);
}

// --- errors -------------------------------------------------------------------------

// php_stream_warn(stream, code, ...): the stream's wrapper (none for a
// socket the http wrapper hasn't claimed yet) and its context
fn warn(ctx: *NativeContext, obj: *PhpObject, code: se.Code, comptime fmt: []const u8, args: anytype) RuntimeError!void {
    return se.raise(ctx, .{ .code = code, .wrapper = wrapperLabel(obj), .context = contextOfStream(ctx.vm, obj) }, fmt, args);
}

fn wrapperLabel(obj: *PhpObject) []const u8 {
    return if (isHttpStream(obj)) "http" else "stream";
}

// a stream the http wrapper opened (and handed over: its __path is the url)
fn isHttpStream(obj: *PhpObject) bool {
    const path = obj.get("__path");
    if (path != .string) return false;
    const p = path.string.bytes();
    return std.ascii.startsWithIgnoreCase(p, "http://") or std.ascii.startsWithIgnoreCase(p, "https://");
}

fn socketErrorText(buf: []u8) []const u8 {
    if (platform.is_windows) {
        const code = sys.ws2.WSAGetLastError();
        return @import("filesystem_win.zig").systemMessage(buf, @intCast(code));
    } else return sys.errnoText();
}

// php_openssl_is_http_stream_talking_to_iis
fn talkingToIis(obj: *PhpObject) bool {
    if (!isHttpStream(obj)) return false;
    const s = streams.get(obj) orelse return false;
    if (s.wrapperdata != .array) return false;
    for (s.wrapperdata.array.entries.items) |e| {
        const v = if (e.ref) |r| r.* else e.value;
        if (v != .string) continue;
        if (std.ascii.eqlIgnoreCase(v.string.bytes(), "Server: Microsoft-IIS")) return true;
        if (std.ascii.eqlIgnoreCase(v.string.bytes(), "Server: GFE/")) return true;
    }
    return false;
}

const SslError = struct {
    retry: bool,
    // errno was EAGAIN: openssl wants the socket again
    again: bool,
};

// php_openssl_handle_ssl_error: whether to retry, and php's warning for a
// real failure
fn handleSslError(ctx: *NativeContext, obj: *PhpObject, t: *Tls, nr_bytes: c_int, is_init: bool, blocked: bool) RuntimeError!SslError {
    const ssl = t.ssl.?;
    const err = c.SSL_get_error(ssl, nr_bytes);
    switch (err) {
        c.SSL_ERROR_ZERO_RETURN => return .{ .retry = false, .again = false },
        c.SSL_ERROR_WANT_READ, c.SSL_ERROR_WANT_WRITE => {
            const retry = if (is_init) true else blocked;
            if (!retry) t.last_status = if (err == c.SSL_ERROR_WANT_READ) STATUS_WANT_READ else STATUS_WANT_WRITE;
            return .{ .retry = retry, .again = true };
        },
        c.SSL_ERROR_SYSCALL => if (c.ERR_peek_error() == 0) {
            if (nr_bytes == 0) {
                if (!talkingToIis(obj) and c.ERR_get_error() != 0) try warn(ctx, obj, .ProtocolError, "SSL: fatal protocol error", .{});
                c.SSL_set_shutdown(ssl, c.SSL_SENT_SHUTDOWN | c.SSL_RECEIVED_SHUTDOWN);
                if (streams.get(obj)) |s| s.eof = true;
            } else {
                var buf: [512]u8 = undefined;
                try warn(ctx, obj, .ProtocolError, "SSL: {s}", .{socketErrorText(&buf)});
            }
            return .{ .retry = false, .again = false };
        },
        else => {},
    }
    var ecode = c.ERR_get_error();
    if (errReason(ecode) == c.SSL_R_NO_SHARED_CIPHER) {
        try warn(ctx, obj, .ProtocolError, "SSL_R_NO_SHARED_CIPHER: no suitable shared cipher could be used.  This could be because the server is missing an SSL certificate (local_cert context option)", .{});
        return .{ .retry = false, .again = false };
    }
    var ebuf: std.ArrayListUnmanaged(u8) = .empty;
    defer ebuf.deinit(ctx.allocator);
    while (ecode != 0) : (ecode = c.ERR_get_error()) {
        var esbuf: [512]u8 = undefined;
        c.ERR_error_string_n(ecode, &esbuf, esbuf.len);
        if (ebuf.items.len > 0) try ebuf.append(ctx.allocator, '\n');
        try ebuf.appendSlice(ctx.allocator, std.mem.sliceTo(&esbuf, 0));
    }
    try warn(ctx, obj, .ProtocolError, "SSL operation failed with code {d}. {s}{s}", .{ err, if (ebuf.items.len > 0) "OpenSSL Error messages:\n" else "", ebuf.items });
    return .{ .retry = false, .again = false };
}

// ERR_GET_REASON
fn errReason(code: c_ulong) c_int {
    return @intCast(code & 0x7FFFFF);
}

// --- callbacks ------------------------------------------------------------------

fn tlsOfSsl(ssl: ?*const c.SSL) ?*Tls {
    const p = c.SSL_get_ex_data(ssl, 0) orelse return null;
    return @ptrCast(@alignCast(p));
}

fn verifyCallback(preverify_ok: c_int, store: ?*c.X509_STORE_CTX) callconv(.c) c_int {
    var ret = preverify_ok;
    const err = c.X509_STORE_CTX_get_error(store);
    const depth = c.X509_STORE_CTX_get_error_depth(store);
    const ssl: ?*c.SSL = @ptrCast(c.X509_STORE_CTX_get_ex_data(store, c.SSL_get_ex_data_X509_STORE_CTX_idx()));
    const t = tlsOfSsl(ssl) orelse return ret;
    const op = t.op orelse return ret;
    const context = contextOfStream(op.vm, t.stream.?);
    // allow_self_signed lets a self-signed peer through
    if (err == c.X509_V_ERR_DEPTH_ZERO_SELF_SIGNED_CERT and optionTrue(context, "allow_self_signed")) ret = 1;
    const allowed: i64 = if (option(context, "verify_depth")) |v| Value.toInt(v) else default_verify_depth;
    if (@as(u64, @bitCast(@as(i64, depth))) > @as(u64, @bitCast(allowed))) {
        ret = 0;
        c.X509_STORE_CTX_set_error(store, c.X509_V_ERR_CERT_CHAIN_TOO_LONG);
    }
    return ret;
}

fn passwdCallback(buf: [*c]u8, num: c_int, _: c_int, data: ?*anyopaque) callconv(.c) c_int {
    const t: *Tls = @ptrCast(@alignCast(data orelse return 0));
    const op = t.op orelse return 0;
    const v = option(contextOfStream(op.vm, t.stream.?), "passphrase") orelse return 0;
    const pass = if (v == .string) v.string.bytes() else (op.vm.valueToString(v) catch return 0);
    if (pass.len < @as(usize, @intCast(num)) - 1) {
        @memcpy(buf[0..pass.len], pass);
        buf[pass.len] = 0;
        return @intCast(pass.len);
    }
    return 0;
}

fn sniCallback(ssl: ?*c.SSL, _: [*c]c_int, _: ?*anyopaque) callconv(.c) c_int {
    const server_name = c.SSL_get_servername(ssl, c.TLSEXT_NAMETYPE_host_name) orelse return c.SSL_TLSEXT_ERR_NOACK;
    const t = tlsOfSsl(ssl) orelse return c.SSL_TLSEXT_ERR_NOACK;
    if (t.sni_certs.items.len == 0) return c.SSL_TLSEXT_ERR_NOACK;
    for (t.sni_certs.items) |cert| {
        if (matchesWildcardName(std.mem.span(server_name), cert.name)) {
            _ = c.SSL_set_SSL_CTX(ssl, cert.ctx);
            return c.SSL_TLSEXT_ERR_OK;
        }
    }
    return c.SSL_TLSEXT_ERR_NOACK;
}

fn alpnCallback(ssl: ?*c.SSL, out: [*c][*c]const u8, outlen: [*c]u8, in: [*c]const u8, inlen: c_uint, _: ?*anyopaque) callconv(.c) c_int {
    const t = tlsOfSsl(ssl) orelse return c.SSL_TLSEXT_ERR_NOACK;
    const protos = t.alpn orelse return c.SSL_TLSEXT_ERR_NOACK;
    if (c.SSL_select_next_proto(@ptrCast(out), outlen, protos.ptr, @intCast(protos.len), in, inlen) != c.OPENSSL_NPN_NEGOTIATED) return c.SSL_TLSEXT_ERR_NOACK;
    return c.SSL_TLSEXT_ERR_OK;
}

fn infoCallback(ssl: ?*const c.SSL, where: c_int, _: c_int) callconv(.c) void {
    if (where & c.SSL_CB_HANDSHAKE_START != 0) limitHandshakeReneg(ssl);
}

// php_openssl_limit_handshake_reneg: a leaky bucket of client-initiated
// renegotiations; past the limit the connection closes unless the
// reneg_limit_callback answers true
fn limitHandshakeReneg(ssl: ?*const c.SSL) void {
    const t = tlsOfSsl(ssl) orelse return;
    const r = &(t.reneg orelse return);
    const now: i64 = @intCast(@divTrunc(platform.nanoTimestamp(), std.time.ns_per_s));
    // the initial handshake is never rate-limited
    if (r.prev_handshake == 0) {
        r.prev_handshake = now;
        return;
    }
    const elapsed = now - r.prev_handshake;
    r.prev_handshake = now;
    // php divides the zend_longs before scaling
    r.tokens -= @floatFromInt(elapsed * (if (r.window != 0) @divTrunc(r.limit, r.window) else 0));
    if (r.tokens < 0) r.tokens = 0;
    r.tokens += 1;
    if (r.tokens <= @as(f32, @floatFromInt(r.limit))) return;
    r.should_close = true;
    const op = t.op orelse return;
    const obj = t.stream.?;
    const context = contextOfStream(op.vm, obj);
    if (option(context, "reneg_limit_callback")) |cb| {
        const args = [_]Value{.{ .resource = obj }};
        const was = obj.get("__no_fclose");
        obj.set(op.allocator, "__no_fclose", .{ .bool = true }) catch {};
        const result = op.vm.callValueCallable(cb, &args) catch |err| blk: {
            if (op.vm.pending_exception == null) warn(op, obj, .UserspaceCallFailed, "SSL: failed invoking reneg limit notification callback", .{}) catch |e| {
                t.cb_error = e;
            } else t.cb_error = err;
            break :blk Value.null;
        };
        obj.set(op.allocator, "__no_fclose", was) catch {};
        if (result == .bool and result.bool) r.should_close = false;
        op.vm.releaseValue(result);
    } else {
        warn(op, obj, .ProtocolError, "SSL: client-initiated handshake rate limit exceeded by peer", .{}) catch |e| {
            t.cb_error = e;
        };
    }
}

// --- peer verification ------------------------------------------------------------

// php_openssl_matches_wildcard_name
fn matchesWildcardName(subject: []const u8, cert: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(subject, cert)) return true;
    // a wildcard may only be in the left-most component
    const wildcard = std.mem.indexOfScalar(u8, cert, '*') orelse return false;
    if (std.mem.indexOfScalar(u8, cert[0..wildcard], '.') != null) return false;
    const prefix_len = wildcard;
    if (prefix_len > 0 and (subject.len < prefix_len or !std.ascii.eqlIgnoreCase(subject[0..prefix_len], cert[0..prefix_len]))) return false;
    const suffix = cert[wildcard + 1 ..];
    if (suffix.len + prefix_len > subject.len) return false;
    if (!std.ascii.eqlIgnoreCase(suffix, subject[subject.len - suffix.len ..])) return false;
    // no dot between the prefix and the suffix
    return std.mem.indexOfScalar(u8, subject[prefix_len .. subject.len - suffix.len], '.') == null;
}

fn sanCount(names: ?*c.GENERAL_NAMES) usize {
    const n = c.OPENSSL_sk_num(@ptrCast(names));
    return if (n < 0) 0 else @intCast(n);
}

// EXPAND_IPV6_ADDRESS
fn expandIpv6(buf: []u8, b: []const u8) []const u8 {
    return std.fmt.bufPrint(buf, "{X}:{X}:{X}:{X}:{X}:{X}:{X}:{X}", .{
        @as(u16, b[0]) << 8 | b[1],   @as(u16, b[2]) << 8 | b[3],
        @as(u16, b[4]) << 8 | b[5],   @as(u16, b[6]) << 8 | b[7],
        @as(u16, b[8]) << 8 | b[9],   @as(u16, b[10]) << 8 | b[11],
        @as(u16, b[12]) << 8 | b[13], @as(u16, b[14]) << 8 | b[15],
    }) catch "";
}

fn parseIpv6(text: []const u8) ?[16]u8 {
    const addr = @import("../net.zig").Address.parseIp6(text, 0) catch return null;
    return addr.in6.sa.addr;
}

// php_openssl_matches_san_list
fn matchesSanList(peer: *c.X509, subject: [:0]const u8, has_service_id: *bool) bool {
    const names: ?*c.GENERAL_NAMES = @ptrCast(c.X509_get_ext_d2i(peer, c.NID_subject_alt_name, null, null));
    defer if (names != null) c.GENERAL_NAMES_free(names);
    has_service_id.* = false;
    var subject_v6_buf: [64]u8 = undefined;
    const subject_v6: ?[]const u8 = if (parseIpv6(subject)) |b| expandIpv6(&subject_v6_buf, &b) else null;
    for (0..sanCount(names)) |i| {
        const san: *c.GENERAL_NAME = @ptrCast(@alignCast(c.OPENSSL_sk_value(@ptrCast(names), @intCast(i)) orelse continue));
        switch (san.type) {
            c.GEN_DNS => {
                has_service_id.* = true;
                var cert_name: [*c]u8 = null;
                if (c.ASN1_STRING_to_UTF8(&cert_name, san.d.dNSName) < 0) continue;
                defer c.CRYPTO_free(cert_name, "xp_ssl", 0);
                var name: []const u8 = std.mem.span(@as([*:0]u8, @ptrCast(cert_name)));
                // a nul inside the name poisons it
                if (@as(usize, @intCast(c.ASN1_STRING_length(san.d.dNSName))) != name.len) continue;
                // a valid fqdn may end in a dot
                if (name.len > 0 and name[name.len - 1] == '.') name = name[0 .. name.len - 1];
                if (matchesWildcardName(subject, name)) return true;
            },
            c.GEN_IPADD => {
                const len = c.ASN1_STRING_length(san.d.iPAddress);
                const data = c.ASN1_STRING_get0_data(san.d.iPAddress);
                if (len == 4) {
                    var ipbuf: [64]u8 = undefined;
                    const ip = std.fmt.bufPrint(&ipbuf, "{d}.{d}.{d}.{d}", .{ data[0], data[1], data[2], data[3] }) catch continue;
                    if (std.ascii.eqlIgnoreCase(subject, ip)) return true;
                } else if (len == 16 and subject_v6 != null) {
                    var ipbuf: [64]u8 = undefined;
                    const ip = expandIpv6(&ipbuf, data[0..16]);
                    if (std.ascii.eqlIgnoreCase(subject_v6.?, ip)) return true;
                }
            },
            c.GEN_URI => has_service_id.* = true,
            c.GEN_OTHERNAME => {
                // an SRV-ID, matched by its oid
                var oid: [32]u8 = undefined;
                if (c.OBJ_obj2txt(&oid, oid.len, san.d.otherName.*.type_id, 1) > 0 and std.mem.eql(u8, std.mem.sliceTo(&oid, 0), "1.3.6.1.5.5.7.8.7")) has_service_id.* = true;
            },
            else => {},
        }
    }
    return false;
}

// php_openssl_matches_common_name
fn matchesCommonName(ctx: *NativeContext, obj: *PhpObject, peer: *c.X509, subject: []const u8) RuntimeError!bool {
    const name = c.X509_get_subject_name(peer);
    const index = c.X509_NAME_get_index_by_NID(name, c.NID_commonName, -1);
    if (index == -1) {
        try warn(ctx, obj, .NetworkRecvFailed, "Unable to locate peer certificate CN", .{});
        return false;
    }
    const entry = c.X509_NAME_get_entry(name, index) orelse {
        try warn(ctx, obj, .NetworkRecvFailed, "Unable to locate peer certificate CN", .{});
        return false;
    };
    const data = c.X509_NAME_ENTRY_get_data(entry);
    const len: usize = @intCast(c.ASN1_STRING_length(data));
    const bytes = c.ASN1_STRING_get0_data(data)[0..len];
    // OPENSSL_strndup stops at a nul
    const cert_name = bytes[0 .. std.mem.indexOfScalar(u8, bytes, 0) orelse len];
    if (cert_name.len != len) {
        try warn(ctx, obj, .AuthFailed, "Peer certificate CN=`{s}' is malformed", .{cert_name});
        return false;
    }
    if (matchesWildcardName(subject, cert_name)) return true;
    try warn(ctx, obj, .AuthFailed, "Peer certificate CN=`{s}' did not match expected CN=`{s}'", .{ cert_name, subject });
    return false;
}

// php_openssl_x509_fingerprint: the certificate's digest in lowercase hex
pub fn x509Fingerprint(ctx: *NativeContext, peer: *c.X509, method: []const u8) RuntimeError!?[]u8 {
    const name = try ctx.allocator.dupeSentinel(u8, method, 0);
    defer ctx.allocator.free(name);
    const md = c.EVP_get_digestbyname(name) orelse {
        try fs.warnDocref(ctx, "Unknown digest algorithm", .{});
        return null;
    };
    var digest: [c.EVP_MAX_MD_SIZE]u8 = undefined;
    var n: c_uint = 0;
    if (c.X509_digest(peer, md, &digest, &n) == 0) {
        try fs.warnDocref(ctx, "Could not generate signature", .{});
        return null;
    }
    const hex = try ctx.allocator.alloc(u8, n * 2);
    _ = std.fmt.bufPrint(hex, "{x}", .{digest[0..n]}) catch unreachable;
    return hex;
}

fn fingerprintEqual(ctx: *NativeContext, peer: *c.X509, method: []const u8, expected: []const u8) RuntimeError!bool {
    const fp = (try x509Fingerprint(ctx, peer, method)) orelse return false;
    defer ctx.allocator.free(fp);
    return std.ascii.eqlIgnoreCase(fp, expected);
}

// php_openssl_x509_fingerprint_match
fn fingerprintMatch(ctx: *NativeContext, obj: *PhpObject, peer: *c.X509, val: Value) RuntimeError!bool {
    if (val == .string) {
        const expected = val.string.bytes();
        const method: []const u8 = switch (expected.len) {
            32 => "md5",
            40 => "sha1",
            else => {
                try warn(ctx, obj, .AuthFailed, "peer_fingerprint length doesn't match a md5 or sha1 hash", .{});
                return false;
            },
        };
        if (!try fingerprintEqual(ctx, peer, method, expected)) {
            try warn(ctx, obj, .AuthFailed, "peer_fingerprint match failure", .{});
            return false;
        }
        return true;
    }
    if (val == .array) {
        if (val.array.entries.items.len == 0) {
            try warn(ctx, obj, .Generic, "Invalid peer_fingerprint array; [algo => fingerprint] form required", .{});
            return false;
        }
        for (val.array.entries.items) |e| {
            const current = if (e.ref) |r| r.* else e.value;
            if (e.key != .string or current != .string) {
                try warn(ctx, obj, .Generic, "Invalid peer_fingerprint array; [algo => fingerprint] form required", .{});
                return false;
            }
            if (!try fingerprintEqual(ctx, peer, e.key.string.bytes(), current.string.bytes())) {
                try warn(ctx, obj, .AuthFailed, "peer_fingerprint match failure", .{});
                return false;
            }
        }
        return true;
    }
    try warn(ctx, obj, .Generic, "Invalid peer_fingerprint value; fingerprint string or array of the form [algo => fingerprint] required", .{});
    return false;
}

// php_openssl_apply_peer_verification_policy
fn applyPeerVerificationPolicy(ctx: *NativeContext, obj: *PhpObject, t: *Tls, peer: ?*c.X509) RuntimeError!bool {
    const context = contextOfStream(ctx.vm, obj);
    const verify_peer = if (option(context, "verify_peer")) |v| v.isTruthy() else t.is_client;
    const verify_peer_name = if (option(context, "verify_peer_name")) |v| v.isTruthy() else t.is_client;
    const fingerprint = option(context, "peer_fingerprint");
    if ((verify_peer or verify_peer_name or fingerprint != null) and peer == null) {
        try warn(ctx, obj, .NetworkRecvFailed, "Could not get peer certificate", .{});
        return false;
    }
    if (verify_peer) {
        const err = c.SSL_get_verify_result(t.ssl.?);
        if (err != c.X509_V_OK and !(err == c.X509_V_ERR_DEPTH_ZERO_SELF_SIGNED_CERT and optionTrue(context, "allow_self_signed"))) {
            try warn(ctx, obj, .AuthFailed, "Could not verify peer: code:{d} {s}", .{ err, std.mem.span(c.X509_verify_cert_error_string(err)) });
            return false;
        }
    }
    // a fingerprint match trumps peer and peer name verification
    if (fingerprint) |fp| {
        if (fp == .string or fp == .array) {
            if (!try fingerprintMatch(ctx, obj, peer.?, fp)) return false;
        } else {
            try warn(ctx, obj, .AuthFailed, "Expected peer fingerprint must be a string or an array", .{});
            return false;
        }
    }
    if (verify_peer_name) {
        const given = try optionString(ctx, context, "peer_name");
        defer if (given) |g| ctx.allocator.free(g);
        const peer_name: ?[:0]const u8 = given orelse (if (t.is_client) t.url_name else null);
        const name = peer_name orelse return false;
        var has_service_id = false;
        if (matchesSanList(peer.?, name, &has_service_id)) return true;
        if (has_service_id) {
            try warn(ctx, obj, .AuthFailed, "Peer certificate subjectAltName did not match expected name `{s}'", .{name});
            return false;
        }
        return matchesCommonName(ctx, obj, peer.?, name);
    }
    return true;
}

// --- the SSL_CTX ------------------------------------------------------------------

// php_openssl_load_stream_cafile: the certificates of a cafile openssl
// couldn't load itself, read through php's streams
fn loadStreamCafile(ctx: *NativeContext, obj: *PhpObject, store: ?*c.X509_STORE, cafile: []const u8) RuntimeError!bool {
    if (fs.usesUrlWrapper(ctx.vm, cafile)) {
        try warn(ctx, obj, .PermissionDenied, "remote cafile streams are disabled for security purposes", .{});
        return false;
    }
    const opened = (try se.quietly(ctx.vm, fs.openStreamValue, .{ ctx, cafile, "rb", null })) orelse {
        const msg = try std.fmt.allocPrint(ctx.allocator, "failed loading cafile stream: `{s}'", .{cafile});
        defer ctx.allocator.free(msg);
        try ctx.vm.emitWarning(msg);
        return false;
    };
    const stream = opened.resource;
    stream.retain();
    defer ctx.vm.releaseValue(opened);
    defer _ = fs.closeStream(ctx, stream) catch {};
    var added: usize = 0;
    var pem: std.ArrayListUnmanaged(u8) = .empty;
    defer pem.deinit(ctx.allocator);
    var in_cert = false;
    while (try streams.getLine(ctx, stream, null)) |line| {
        defer ctx.allocator.free(line);
        if (!in_cert) {
            if (std.mem.eql(u8, line, "-----BEGIN CERTIFICATE-----\n") or std.mem.eql(u8, line, "-----BEGIN CERTIFICATE-----\r\n")) {
                in_cert = true;
                pem.clearRetainingCapacity();
                try pem.appendSlice(ctx.allocator, line);
            }
            continue;
        }
        try pem.appendSlice(ctx.allocator, line);
        if (std.mem.eql(u8, line, "-----END CERTIFICATE-----") or std.mem.eql(u8, line, "-----END CERTIFICATE-----\n") or std.mem.eql(u8, line, "-----END CERTIFICATE-----\r\n")) {
            in_cert = false;
            const bio = c.BIO_new_mem_buf(pem.items.ptr, @intCast(pem.items.len));
            defer _ = c.BIO_free(bio);
            const cert = c.PEM_read_bio_X509(bio, null, null, null);
            if (cert != null and c.X509_STORE_add_cert(store, cert) != 0) added += 1;
            c.X509_free(cert);
        }
    }
    if (added == 0) try warn(ctx, obj, .DecodingFailed, "no valid certs found cafile stream: '{s}'", .{cafile});
    return added > 0;
}

fn iniPath(vm: *VM, name: []const u8) ?[]const u8 {
    const v = vm.ini_settings.get(name) orelse @import("../ini_config.zig").get(name) orelse return null;
    return if (v.len == 0) null else v;
}

// php_openssl_enable_peer_verification
fn enablePeerVerification(ctx: *NativeContext, obj: *PhpObject, t: *Tls, ssl_ctx: *c.SSL_CTX) RuntimeError!bool {
    const context = contextOfStream(ctx.vm, obj);
    var cafile = try optionString(ctx, context, "cafile");
    defer if (cafile) |f| ctx.allocator.free(f);
    var capath = try optionString(ctx, context, "capath");
    defer if (capath) |p| ctx.allocator.free(p);
    if (cafile == null) {
        if (iniPath(ctx.vm, "openssl.cafile")) |f| cafile = try ctx.allocator.dupeSentinel(u8, f, 0);
    } else if (!t.is_client) {
        // a server loads and names the CAs it accepts client certificates from
        const names = c.SSL_load_client_CA_file(cafile.?.ptr) orelse {
            try warn(ctx, obj, .InvalidFormat, "SSL: failed loading CA names from cafile", .{});
            return false;
        };
        c.SSL_CTX_set_client_CA_list(ssl_ctx, names);
    }
    if (capath == null) {
        if (iniPath(ctx.vm, "openssl.capath")) |p| capath = try ctx.allocator.dupeSentinel(u8, p, 0);
    }
    if (cafile != null or capath != null) {
        if (c.SSL_CTX_load_verify_locations(ssl_ctx, if (cafile) |f| f.ptr else null, if (capath) |p| p.ptr else null) == 0) {
            c.ERR_clear_error();
            if (cafile) |f| if (!try loadStreamCafile(ctx, obj, c.SSL_CTX_get_cert_store(ssl_ctx), f)) return false;
        }
    } else if (t.is_client and c.SSL_CTX_set_default_verify_paths(ssl_ctx) == 0) {
        try warn(ctx, obj, .ProtocolError, "Unable to set default verify locations and no CA settings specified", .{});
        return false;
    }
    c.SSL_CTX_set_verify(ssl_ctx, c.SSL_VERIFY_PEER, verifyCallback);
    return true;
}

// php_openssl_check_path_ex for a context option: the path made absolute,
// or null (with php's warning for a bad one)
fn checkPath(ctx: *NativeContext, obj: *PhpObject, path: []const u8, out: []u8, option_title: []const u8, from_array: bool) RuntimeError!?[:0]u8 {
    if (path.len == 0) {
        out[0] = 0;
        return out[0..0 :0];
    }
    var error_msg: ?[]const u8 = null;
    var expanded: []u8 = &.{};
    if (std.mem.indexOfScalar(u8, path, 0) != null) {
        error_msg = "must not contain any null bytes";
    } else if (open_basedir.expand(path, out[0 .. out.len - 1])) |e| {
        expanded = e;
    } else error_msg = "must be a valid file path";
    if (error_msg) |m| {
        try warn(ctx, obj, .InvalidPath, "Path for {s} {s} {s}", .{ option_title, if (from_array) "array item" else "option", m });
        return null;
    }
    out[expanded.len] = 0;
    const result = out[0..expanded.len :0];
    if (!try open_basedir.allows(ctx.vm, ctx.call_name orelse "stream_socket_enable_crypto", result)) return null;
    return result;
}

// php_openssl_set_local_cert
fn setLocalCert(ctx: *NativeContext, obj: *PhpObject, ssl_ctx: *c.SSL_CTX) RuntimeError!bool {
    const context = contextOfStream(ctx.vm, obj);
    const certfile = (try optionString(ctx, context, "local_cert")) orelse return true;
    defer ctx.allocator.free(certfile);
    var resolved_buf: [std.fs.max_path_bytes + 1]u8 = undefined;
    var resolved = (try checkPath(ctx, obj, certfile, &resolved_buf, "local_cert in ssl stream context", false)) orelse {
        try warn(ctx, obj, .NotFound, "Unable to get real path of certificate file `{s}'", .{certfile});
        return false;
    };
    if (c.SSL_CTX_use_certificate_chain_file(ssl_ctx, resolved.ptr) != 1) {
        try warn(ctx, obj, .WriteFailed, "Unable to set local cert chain file `{s}'; Check that your cafile/capath settings include details of your certificate and its issuer", .{certfile});
        return false;
    }
    const private_key = try optionString(ctx, context, "local_pk");
    defer if (private_key) |k| ctx.allocator.free(k);
    if (private_key) |k| {
        resolved = (try checkPath(ctx, obj, k, &resolved_buf, "local_pk in ssl stream context", false)) orelse {
            try warn(ctx, obj, .NotFound, "Unable to get real path of private key file `{s}'", .{k});
            return false;
        };
    }
    if (c.SSL_CTX_use_PrivateKey_file(ssl_ctx, resolved.ptr, c.SSL_FILETYPE_PEM) != 1) {
        try warn(ctx, obj, .WriteFailed, "Unable to set private key file `{s}'", .{resolved});
        return false;
    }
    if (c.SSL_CTX_check_private_key(ssl_ctx) == 0) try warn(ctx, obj, .PermissionDenied, "Private key does not match certificate!", .{});
    return true;
}

fn minProtoFlag(flags: i64) i64 {
    var ver = min_proto_flag;
    while (ver <= max_proto_flag) : (ver <<= 1) if (flags & ver != 0) return ver;
    return max_proto_flag;
}

fn maxProtoFlag(flags: i64) i64 {
    var ver = max_proto_flag;
    while (ver >= min_proto_flag) : (ver >>= 1) if (flags & ver != 0) return ver;
    return TLSv1_3;
}

fn mapProtoVersion(flag: i64) c_long {
    return switch (flag) {
        TLSv1_3 => c.TLS1_3_VERSION,
        TLSv1_2 => c.TLS1_2_VERSION,
        TLSv1_1 => c.TLS1_1_VERSION,
        TLSv1_0 => c.TLS1_VERSION,
        SSLv3 => if (have_ssl3) c.SSL3_VERSION else c.TLS1_2_VERSION,
        else => c.TLS1_2_VERSION,
    };
}

// php_openssl_get_proto_version_flags: min_proto_version and
// max_proto_version widen or narrow the method's versions
fn protoVersionFlags(flags_in: i64, min_in: i64, max_in: i64) i64 {
    var flags = flags_in;
    const min = if (min_in == 0) minProtoFlag(flags) else min_in;
    const max = if (max_in == 0) maxProtoFlag(flags) else max_in;
    var ver = min_proto_flag;
    while (ver <= max_proto_flag) : (ver <<= 1) {
        if (ver >= min and ver <= max) {
            flags |= ver;
        } else flags &= ~ver;
    }
    return flags;
}

// php_openssl_set_server_dh_param
fn setServerDhParam(ctx: *NativeContext, obj: *PhpObject, ssl_ctx: *c.SSL_CTX) RuntimeError!bool {
    const context = contextOfStream(ctx.vm, obj);
    const path = (try optionString(ctx, context, "dh_param")) orelse return true;
    defer ctx.allocator.free(path);
    const bio = c.BIO_new_file(path.ptr, "r") orelse {
        try warn(ctx, obj, .NotFound, "Invalid dh_param", .{});
        return false;
    };
    const pkey = c.PEM_read_bio_Parameters(bio, null);
    _ = c.BIO_free(bio);
    if (pkey == null) {
        try warn(ctx, obj, .ReadFailed, "Failed reading DH params", .{});
        return false;
    }
    if (c.SSL_CTX_set0_tmp_dh_pkey(ssl_ctx, pkey) == 0) {
        try warn(ctx, obj, .WriteFailed, "Failed assigning DH params", .{});
        c.EVP_PKEY_free(pkey);
        return false;
    }
    return true;
}

// php_openssl_set_server_specific_opts
fn setServerSpecificOpts(ctx: *NativeContext, obj: *PhpObject, ssl_ctx: *c.SSL_CTX) RuntimeError!bool {
    const context = contextOfStream(ctx.vm, obj);
    var opts = c.SSL_CTX_get_options(ssl_ctx);
    if (option(context, "rsa_key_size") != null) try warn(ctx, obj, .Generic, "rsa_key_size context option has been removed", .{});
    if (!try setServerDhParam(ctx, obj, ssl_ctx)) return false;
    if (option(context, "single_dh_use")) |v| {
        if (v.isTruthy()) opts |= SSL_OP_SINGLE_DH_USE;
    } else opts |= SSL_OP_SINGLE_DH_USE;
    if (option(context, "honor_cipher_order")) |v| {
        if (v.isTruthy()) opts |= SSL_OP_CIPHER_SERVER_PREFERENCE;
    } else opts |= SSL_OP_CIPHER_SERVER_PREFERENCE;
    _ = c.SSL_CTX_set_options(ssl_ctx, opts);
    return true;
}

// php_openssl_create_sni_server_ctx
fn createSniServerCtx(ctx: *NativeContext, obj: *PhpObject, cert_path: [:0]const u8, key_path: [:0]const u8) RuntimeError!?*c.SSL_CTX {
    const method = c.TLS_server_method();
    const sni_ctx = c.SSL_CTX_new(method) orelse {
        try warn(ctx, obj, .CreateFailed, "Failed to create the SSL context", .{});
        return null;
    };
    if (c.SSL_CTX_use_certificate_chain_file(sni_ctx, cert_path.ptr) != 1) {
        try warn(ctx, obj, .ReadFailed, "Failed setting local cert chain file `{s}'; check that your cafile/capath settings include details of your certificate and its issuer", .{cert_path});
        c.SSL_CTX_free(sni_ctx);
        return null;
    }
    if (c.SSL_CTX_use_PrivateKey_file(sni_ctx, key_path.ptr, c.SSL_FILETYPE_PEM) != 1) {
        try warn(ctx, obj, .ReadFailed, "Failed setting private key from file `{s}'", .{key_path});
        c.SSL_CTX_free(sni_ctx);
        return null;
    }
    return sni_ctx;
}

fn arrayString(ctx: *NativeContext, v: Value) RuntimeError![:0]u8 {
    const bytes = try ctx.vm.valueToString(v);
    if (ctx.vm.pending_exception != null) return error.RuntimeError;
    return ctx.allocator.dupeSentinel(u8, bytes, 0);
}

// php_openssl_enable_server_sni: SNI_server_certs maps host names to the
// certificate (and key) a server answers them with
fn enableServerSni(ctx: *NativeContext, obj: *PhpObject, t: *Tls, ssl_ctx: *c.SSL_CTX, verify_peer: bool) RuntimeError!bool {
    const context = contextOfStream(ctx.vm, obj);
    if (option(context, "SNI_enabled")) |v| if (!v.isTruthy()) return true;
    const val = option(context, "SNI_server_certs") orelse return true;
    if (val != .array) {
        try warn(ctx, obj, .Generic, "SNI_server_certs requires an array mapping host names to cert paths", .{});
        return false;
    }
    if (val.array.entries.items.len == 0) {
        try warn(ctx, obj, .Generic, "SNI_server_certs host cert array must not be empty", .{});
        return false;
    }
    for (val.array.entries.items) |e| {
        if (e.key != .string) {
            try warn(ctx, obj, .Generic, "SNI_server_certs array requires string host name keys", .{});
            return false;
        }
        const current = if (e.ref) |r| r.* else e.value;
        var sni_ctx: ?*c.SSL_CTX = null;
        if (current == .array) {
            var cert_buf: [std.fs.max_path_bytes + 1]u8 = undefined;
            var pk_buf: [std.fs.max_path_bytes + 1]u8 = undefined;
            const local_cert = current.array.get(.{ .string = Value.String.borrowed("local_cert") });
            if (!current.array.contains(.{ .string = Value.String.borrowed("local_cert") })) {
                try warn(ctx, obj, .Generic, "local_cert not present in the array", .{});
                return false;
            }
            const cert_str = try arrayString(ctx, local_cert);
            defer ctx.allocator.free(cert_str);
            const cert_path = (try checkPath(ctx, obj, cert_str, &cert_buf, "SNI_server_certs local_cert in ssl stream context", false)) orelse {
                try warn(ctx, obj, .OpenFailed, "Failed setting local cert chain file `{s}'; could not open file", .{cert_str});
                return false;
            };
            if (!current.array.contains(.{ .string = Value.String.borrowed("local_pk") })) {
                try warn(ctx, obj, .Generic, "local_pk not present in the array", .{});
                return false;
            }
            const pk_str = try arrayString(ctx, current.array.get(.{ .string = Value.String.borrowed("local_pk") }));
            defer ctx.allocator.free(pk_str);
            const pk_path = (try checkPath(ctx, obj, pk_str, &pk_buf, "SNI_server_certs local_pk in ssl stream context", false)) orelse {
                try warn(ctx, obj, .OpenFailed, "Failed setting local private key file `{s}';  could not open file", .{pk_str});
                return false;
            };
            sni_ctx = try createSniServerCtx(ctx, obj, cert_path, pk_path);
        } else if (current == .string) {
            var buf: [std.fs.max_path_bytes + 1]u8 = undefined;
            if (try checkPath(ctx, obj, current.string.bytes(), &buf, "SNI_server_certs in ssl stream context", false)) |p| {
                sni_ctx = try createSniServerCtx(ctx, obj, p, p);
            } else try warn(ctx, obj, .NotFound, "Failed setting local cert chain file `{s}'; file not found", .{current.string.bytes()});
        } else try warn(ctx, obj, .Generic, "SNI_server_certs options values must be of type array|string", .{});
        const made = sni_ctx orelse return false;
        if (!verify_peer) {
            c.SSL_CTX_set_verify(made, c.SSL_VERIFY_NONE, null);
        } else if (!try enablePeerVerification(ctx, obj, t, made)) {
            c.SSL_CTX_free(made);
            return false;
        }
        const name = try allocator.dupeSentinel(u8, e.key.string.bytes(), 0);
        try t.sni_certs.append(allocator, .{ .name = name, .ctx = made });
    }
    _ = c.SSL_CTX_callback_ctrl(ssl_ctx, c.SSL_CTRL_SET_TLSEXT_SERVERNAME_CB, @ptrCast(&sniCallback));
    return true;
}

// php_openssl_enable_client_sni
fn enableClientSni(ctx: *NativeContext, obj: *PhpObject, t: *Tls) RuntimeError!void {
    const context = contextOfStream(ctx.vm, obj);
    if (option(context, "SNI_enabled")) |v| if (!v.isTruthy()) return;
    const given = try optionString(ctx, context, "peer_name");
    defer if (given) |g| ctx.allocator.free(g);
    const name: ?[:0]const u8 = given orelse t.url_name;
    if (name) |n| _ = c.SSL_ctrl(t.ssl.?, c.SSL_CTRL_SET_TLSEXT_HOSTNAME, c.TLSEXT_NAMETYPE_host_name, @ptrCast(@constCast(n.ptr)));
}

// php_openssl_alpn_protos_parse: "a,b" as the wire form, each name after
// its length
fn alpnProtosParse(a: std.mem.Allocator, in: []const u8) RuntimeError!?[]u8 {
    if (in.len >= 65535) return null;
    const out = try a.alloc(u8, in.len + 1);
    var start: usize = 0;
    var i: usize = 0;
    while (i <= in.len) : (i += 1) {
        if (i == in.len or in[i] == ',') {
            if (i - start > 255) {
                a.free(out);
                return null;
            }
            out[start] = @intCast(i - start);
            start = i + 1;
        } else out[i + 1] = in[i];
    }
    return out;
}

// php_openssl_create_server_ctx: the SSL_CTX the stream's context
// options describe (for clients too, despite the name)
fn createCtx(ctx: *NativeContext, obj: *PhpObject, t: *Tls, method_flags_in: i64) RuntimeError!bool {
    const method = if (t.is_client) c.TLS_client_method() else c.TLS_server_method();
    const ssl_ctx = c.SSL_CTX_new(method) orelse {
        try warn(ctx, obj, .CreateFailed, "SSL context creation failure", .{});
        return false;
    };
    t.ctx = ssl_ctx;
    const context = contextOfStream(ctx.vm, obj);
    const min_version: i64 = if (option(context, "min_proto_version")) |v| Value.toInt(v) else 0;
    const max_version: i64 = if (option(context, "max_proto_version")) |v| Value.toInt(v) else 0;
    const method_flags = protoVersionFlags(method_flags_in, min_version, max_version);
    var opts: u64 = SSL_OP_ALL;
    if (optionTrue(context, "no_ticket")) opts |= SSL_OP_NO_TICKET;
    if (option(context, "num_tickets")) |v| {
        const n = Value.toInt(v);
        if (n >= 0) _ = c.SSL_CTX_set_num_tickets(ssl_ctx, @intCast(n));
    }
    opts &= ~SSL_OP_DONT_INSERT_EMPTY_FRAGMENTS;
    opts |= SSL_OP_IGNORE_UNEXPECTED_EOF;
    if (option(context, "disable_compression")) |v| {
        if (v.isTruthy()) opts |= SSL_OP_NO_COMPRESSION;
    } else opts |= SSL_OP_NO_COMPRESSION;

    var verify_peer = false;
    if (option(context, "verify_peer")) |v| if (!v.isTruthy()) {
        c.SSL_CTX_set_verify(ssl_ctx, c.SSL_VERIFY_NONE, null);
    } else {
        verify_peer = true;
    } else verify_peer = true;
    if (verify_peer and !try enablePeerVerification(ctx, obj, t, ssl_ctx)) return false;

    // the passphrase for the local certificate's key
    if (option(context, "passphrase") != null) {
        c.SSL_CTX_set_default_passwd_cb_userdata(ssl_ctx, t);
        c.SSL_CTX_set_default_passwd_cb(ssl_ctx, passwdCallback);
    }

    const cipherlist = try optionString(ctx, context, "ciphers");
    defer if (cipherlist) |l| ctx.allocator.free(l);
    if (c.SSL_CTX_set_cipher_list(ssl_ctx, if (cipherlist) |l| l.ptr else default_ciphers) != 1) return false;

    if (option(context, "security_level")) |v| {
        const level = Value.toInt(v);
        if (level < 0 or level > 5) try warn(ctx, obj, .Generic, "Security level must be between 0 and 5", .{});
        c.SSL_CTX_set_security_level(ssl_ctx, @truncate(level));
    }

    const alpn_protocols = try optionString(ctx, context, "alpn_protocols");
    defer if (alpn_protocols) |p| ctx.allocator.free(p);
    if (alpn_protocols) |protos| {
        const alpn = (try alpnProtosParse(allocator, protos)) orelse {
            try warn(ctx, obj, .DecodingFailed, "Failed parsing comma-separated TLS ALPN protocol string", .{});
            c.SSL_CTX_free(ssl_ctx);
            t.ctx = null;
            return false;
        };
        if (t.is_client) {
            defer allocator.free(alpn);
            if (c.SSL_CTX_set_alpn_protos(ssl_ctx, alpn.ptr, @intCast(alpn.len)) != 0) {
                try warn(ctx, obj, .DecodingFailed, "Failed setting TLS ALPN protocols, protocol names must not be empty", .{});
                c.SSL_CTX_free(ssl_ctx);
                t.ctx = null;
                return false;
            }
        } else {
            if (t.alpn) |old| allocator.free(old);
            t.alpn = alpn;
            c.SSL_CTX_set_alpn_select_cb(ssl_ctx, alpnCallback, null);
        }
    }

    if (!try setLocalCert(ctx, obj, ssl_ctx)) return false;
    _ = c.SSL_CTX_set_options(ssl_ctx, opts);
    _ = c.SSL_CTX_ctrl(ssl_ctx, c.SSL_CTRL_SET_MIN_PROTO_VERSION, mapProtoVersion(minProtoFlag(method_flags)), null);
    _ = c.SSL_CTX_ctrl(ssl_ctx, c.SSL_CTRL_SET_MAX_PROTO_VERSION, mapProtoVersion(maxProtoFlag(method_flags)), null);

    if (!t.is_client) {
        if (!try setServerSpecificOpts(ctx, obj, ssl_ctx)) return false;
        if (!try enableServerSni(ctx, obj, t, ssl_ctx, verify_peer)) return false;
    }
    return true;
}

fn socketOf(obj: *PhpObject) ?std.posix.socket_t {
    const fd = obj.get("__fd");
    if (fd != .int or fd.int < 0) return null;
    return platform.socketFromInt(fd.int);
}

fn setFd(ssl: *c.SSL, sock: std.posix.socket_t) c_int {
    return c.SSL_set_fd(ssl, @intCast(platform.socketToInt(sock)));
}

// php_openssl_setup_crypto (STREAM_XPORT_CRYPTO_OP_SETUP): 0, or -1
pub fn setup(ctx: *NativeContext, obj: *PhpObject, method_in: i64, session: ?*PhpObject) RuntimeError!i32 {
    const t = try ensure(ctx, obj);
    if (t.ssl != null) {
        if (isBlocked(obj)) {
            try warn(ctx, obj, .Generic, "SSL/TLS already set-up for this stream", .{});
            return -1;
        }
        return 0;
    }
    c.ERR_clear_error();
    t.is_client = method_in & IS_CLIENT != 0;
    const method_flags = method_in & ~IS_CLIENT;
    const sock = socketOf(obj) orelse return -1;

    // the session stream's SSL_CTX is shared, and a client resumes its session
    if (session) |parent_obj| reuse: {
        const parent = if (capable(parent_obj)) of(parent_obj) else null;
        if (parent == null) {
            try warn(ctx, obj, .SslNotSupported, "Supplied session stream must be an SSL enabled stream", .{});
            break :reuse;
        }
        const p = parent.?;
        if (p.ctx == null) {
            try warn(ctx, obj, .SslNotSupported, "Supplied SSL session stream is not set up", .{});
            break :reuse;
        }
        if (t.is_client and p.ssl == null) {
            try warn(ctx, obj, .SslNotSupported, "Supplied SSL session stream is not initialized", .{});
            break :reuse;
        }
        _ = c.SSL_CTX_up_ref(p.ctx);
        t.ctx = p.ctx;
        if (p.alpn) |alpn| {
            if (t.alpn) |old| allocator.free(old);
            t.alpn = try allocator.dupe(u8, alpn);
        }
        t.ssl = c.SSL_new(t.ctx) orelse {
            try warn(ctx, obj, .CreateFailed, "SSL handle creation failure", .{});
            c.SSL_CTX_free(t.ctx);
            t.ctx = null;
            return -1;
        };
        _ = c.SSL_set_ex_data(t.ssl, 0, t);
        t.stream = obj;
        if (setFd(t.ssl.?, sock) == 0) _ = try handleSslError(ctx, obj, t, 0, true, isBlocked(obj));
        if (t.is_client) {
            if (c.SSL_copy_session_id(t.ssl, p.ssl) != 0) {
                _ = c.SSL_CTX_ctrl(t.ctx, c.SSL_CTRL_SET_SESS_CACHE_MODE, c.SSL_SESS_CACHE_CLIENT, null);
            } else try warn(ctx, obj, .CreateFailed, "SSL session copying failed creation failure", .{});
        }
        return 0;
    }

    t.stream = obj;
    t.op = ctx;
    defer t.op = null;
    if (!try createCtx(ctx, obj, t, method_flags)) return -1;
    const ssl = c.SSL_new(t.ctx);
    if (ssl == null or c.SSL_set_ex_data(ssl, 0, t) == 0) {
        if (ssl != null) c.SSL_free(ssl);
        try warn(ctx, obj, .CreateFailed, "SSL handle creation failure", .{});
        c.SSL_CTX_free(t.ctx);
        t.ctx = null;
        if (t.alpn) |a| allocator.free(a);
        t.alpn = null;
        return -1;
    }
    t.ssl = ssl;
    if (setFd(ssl.?, sock) == 0) _ = try handleSslError(ctx, obj, t, 0, true, isBlocked(obj));
    return 0;
}

fn isBlocked(obj: *PhpObject) bool {
    const b = obj.get("__blocking");
    return !(b == .bool and !b.bool);
}

// php_openssl_set_blocking: the socket's mode, as is_blocked tracks it
fn setBlocking(obj: *PhpObject, block: bool) bool {
    const sock = socketOf(obj) orelse return false;
    platform.setNonBlocking(sock, !block) catch return false;
    return true;
}

// the stream's read timeout (sslsock->s.timeout) in microseconds: what
// stream_set_timeout set, default_socket_timeout otherwise; negative waits
// forever
fn readTimeoutUs(ctx: *NativeContext, obj: *PhpObject) i64 {
    const v = obj.get("__timeout_us");
    if (v == .int) return v.int;
    const seconds = network.defaultSocketTimeoutSeconds(ctx);
    if (!(seconds >= 0)) return -1;
    return @intFromFloat(@min(seconds, 1e12) * 1e6);
}

fn nowUs() i64 {
    return @intCast(@divTrunc(platform.monotonicNanos(), std.time.ns_per_us));
}

// php_pollfd_for: wait for the socket, at most left_us (null waits forever)
fn pollFor(obj: *PhpObject, events: i16, left_us: ?i64) void {
    const sock = socketOf(obj) orelse return;
    var fds = [_]sys.pollfd{.{ .fd = sock, .events = events, .revents = 0 }};
    const ms: i32 = if (left_us) |us| @intCast(std.math.clamp(@divTrunc(us + 999, 1000), 0, std.math.maxInt(i32))) else -1;
    _ = sys.poll(&fds, ms) catch {};
}

const POLLIN_PRI = sys.POLL.IN | sys.POLL.PRI;
const POLLOUT_PRI = sys.POLL.OUT | sys.POLL.PRI;

// php_openssl_enable_crypto (STREAM_XPORT_CRYPTO_OP_ENABLE): 1 when the
// handshake completed, 0 when a non-blocking one must be called again, -1
// on failure (and always for turning crypto off)
pub fn enable(ctx: *NativeContext, obj: *PhpObject, activate: bool) RuntimeError!i32 {
    const t = try ensure(ctx, obj);
    t.last_status = STATUS_NONE;
    if (activate and !t.active) {
        const ssl = t.ssl orelse return -1;
        t.stream = obj;
        t.op = ctx;
        defer t.op = null;
        if (!t.state_set) {
            if (t.is_client) {
                try enableClientSni(ctx, obj, t);
                c.SSL_set_connect_state(ssl);
            } else {
                initServerRenegLimit(ctx, obj, t);
                c.SSL_set_accept_state(ssl);
            }
            t.state_set = true;
        }
        _ = c.SSL_ctrl(ssl, c.SSL_CTRL_MODE, c.SSL_MODE_RELEASE_BUFFERS, null);
        const blocked = isBlocked(obj);
        var now_blocked = blocked;
        if (setBlocking(obj, false)) {
            now_blocked = false;
            // these modes only go with a socket that could go non-blocking,
            // as reads and writes use it too
            _ = c.SSL_ctrl(ssl, c.SSL_CTRL_MODE, c.SSL_MODE_ENABLE_PARTIAL_WRITE | c.SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER, null);
        }
        const timeout_us: i64 = if (t.is_client) t.connect_timeout_us else readTimeoutUs(ctx, obj);
        const has_timeout = !now_blocked and timeout_us > 0;
        const start = nowUs();
        ctx.vm.flushOutputToStdout();
        var n: c_int = 0;
        var again = false;
        while (true) {
            c.ERR_clear_error();
            n = if (t.is_client) c.SSL_connect(ssl) else c.SSL_accept(ssl);
            if (t.cb_error) |e| {
                t.cb_error = null;
                _ = setBlocking(obj, blocked);
                return e;
            }
            var elapsed: i64 = 0;
            if (has_timeout) {
                elapsed = nowUs() - start;
                if (elapsed > timeout_us) {
                    _ = setBlocking(obj, blocked);
                    try warn(ctx, obj, .TimeOut, "SSL: Handshake timed out", .{});
                    return -1;
                }
            }
            if (n > 0) break;
            // a non-blocking handshake that would block isn't retried
            const r = try handleSslError(ctx, obj, t, n, blocked, now_blocked);
            again = r.again;
            if (!r.retry) break;
            const err = c.SSL_get_error(ssl, n);
            pollFor(obj, if (err == c.SSL_ERROR_WANT_READ) POLLIN_PRI else sys.POLL.OUT, if (has_timeout) timeout_us - elapsed else null);
        }
        if (now_blocked != blocked) _ = setBlocking(obj, blocked);
        const context = try streamContext(ctx, obj);
        if (n == 1) {
            const peer = c.SSL_get1_peer_certificate(ssl);
            var captured = false;
            if (peer != null and context != null) captured = try capturePeerCerts(ctx, t, context.?, peer.?);
            defer if (peer != null and !captured) c.X509_free(peer);
            if (!try applyPeerVerificationPolicy(ctx, obj, t, peer)) {
                _ = c.SSL_shutdown(ssl);
                return -1;
            }
            t.active = true;
            return 1;
        }
        if (again) return 0;
        // the peer's certificate is captured even when verification failed
        const peer = c.SSL_get1_peer_certificate(ssl);
        if (peer != null and (context == null or !try capturePeerCerts(ctx, t, context.?, peer.?))) c.X509_free(peer);
        return -1;
    } else if (!activate and t.active) {
        // deactivate: the same for clients and servers
        if (t.ssl) |ssl| _ = c.SSL_shutdown(ssl);
        t.active = false;
    }
    return -1;
}

// php_openssl_init_server_reneg_limit
fn initServerRenegLimit(ctx: *NativeContext, obj: *PhpObject, t: *Tls) void {
    const ctxobj = contextOfStream(ctx.vm, obj);
    const limit: i64 = if (option(ctxobj, "reneg_limit")) |v| Value.toInt(v) else default_reneg_limit;
    // no renegotiation rate-limiting
    if (limit < 0) return;
    const window: i64 = if (option(ctxobj, "reneg_window")) |v| Value.toInt(v) else default_reneg_window;
    t.reneg = .{ .limit = limit, .window = window };
    c.SSL_set_info_callback(t.ssl, infoCallback);
}

// php_openssl_capture_peer_certs: the peer's certificate and chain, put in
// the context as OpenSSLCertificate objects. true when the certificate
// itself was kept
fn capturePeerCerts(ctx: *NativeContext, t: *Tls, context: *PhpObject, peer: *c.X509) RuntimeError!bool {
    var captured = false;
    if (optionTrue(context, "capture_peer_cert")) {
        const cert = try certificateObject(ctx, peer);
        captured = true;
        defer ctx.vm.releaseValue(.{ .object = cert });
        try network.setContextOption(ctx, context, "ssl", "peer_certificate", .{ .object = cert });
    }
    if (optionTrue(context, "capture_peer_cert_chain")) {
        const chain = c.SSL_get_peer_cert_chain(t.ssl);
        const count = c.OPENSSL_sk_num(@ptrCast(chain));
        if (chain != null and count > 0) {
            const arr = try ctx.createArray();
            defer ctx.vm.arrayRelease(arr);
            arr.retain();
            for (0..@intCast(count)) |i| {
                const x: *c.X509 = @ptrCast(@alignCast(c.OPENSSL_sk_value(@ptrCast(chain), @intCast(i)).?));
                const cert = try certificateObject(ctx, c.X509_dup(x).?);
                try arr.append(ctx.allocator, .{ .object = cert });
            }
            try network.setContextOption(ctx, context, "ssl", "peer_certificate_chain", .{ .array = arr });
        } else try network.setContextOption(ctx, context, "ssl", "peer_certificate_chain", .null);
    }
    return captured;
}

// --- OpenSSLCertificate -------------------------------------------------------------

pub const certificate_class = "OpenSSLCertificate";

// a new OpenSSLCertificate owning x509 (one reference, the caller's)
pub fn certificateObject(ctx: *NativeContext, x509: *c.X509) RuntimeError!*PhpObject {
    const obj = ctx.createObject(certificate_class) catch |err| {
        c.X509_free(x509);
        return err;
    };
    obj.native = .{ .kind = .x509, .ptr = @intFromPtr(x509) };
    return obj;
}

pub fn certificateOf(obj: *PhpObject) ?*c.X509 {
    return obj.native.get(c.X509, .x509);
}

fn cleanupCertificate(obj: *PhpObject) bool {
    if (certificateOf(obj)) |x| c.X509_free(x);
    obj.native = .{};
    return true;
}

pub fn cleanupResources(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    for (objects.items) |obj| {
        if (obj.pooled or obj.native.kind != .x509) continue;
        _ = cleanupCertificate(obj);
    }
}

pub fn register(vm: *VM, a: std.mem.Allocator) !void {
    var def = ClassDef{ .name = certificate_class, .is_final = true, .uncloneable = true, .native_cleanup = cleanupCertificate };
    def.slot_layout = try vm.buildSlotLayout(&def);
    try vm.classes.put(a, certificate_class, def);
}

// --- reads and writes ---------------------------------------------------------------

// php_openssl_sockop_io: one read or write through openssl. a blocking
// stream waits up to its timeout with the socket non-blocking underneath;
// a non-blocking one does what it can now
fn io(ctx: *NativeContext, obj: *PhpObject, s: *streams.Stream, t: *Tls, comptime reading: bool, buf: []u8) RuntimeError!isize {
    const ssl = t.ssl.?;
    t.stream = obj;
    t.op = ctx;
    defer t.op = null;
    // buffered data was already returned: fill more without waiting
    const supplemental = s.has_buffered_data;
    var retry = !supplemental;
    const began_blocked = isBlocked(obj);
    const count: c_int = @intCast(@min(buf.len, std.math.maxInt(c_int)));
    // never a timeout for a non-blocking socket
    const use_timeout = began_blocked and !supplemental;
    const timeout_us: i64 = if (use_timeout) readTimeoutUs(ctx, obj) else 0;
    var now_blocked = began_blocked;
    if (use_timeout or supplemental) {
        if (setBlocking(obj, false)) now_blocked = false;
    }
    const has_timeout = !now_blocked and use_timeout and timeout_us > 0;
    const start = nowUs();
    var nr_bytes: c_int = 0;
    if (reading) try obj.set(ctx.allocator, "__timed_out", .{ .bool = false });
    while (true) {
        var elapsed: i64 = 0;
        if (has_timeout) {
            elapsed = nowUs() - start;
            if (elapsed > timeout_us) {
                if (began_blocked) _ = setBlocking(obj, true);
                try obj.set(ctx.allocator, "__timed_out", .{ .bool = true });
                return -1;
            }
        }
        c.ERR_clear_error();
        t.last_status = STATUS_NONE;
        if (reading) {
            nr_bytes = c.SSL_read(ssl, buf.ptr, count);
            if (t.reneg) |r| if (r.should_close) {
                // renegotiation rate limiting triggered
                if (socketOf(obj)) |sock| sys.shutdown(sock, .both) catch {};
                nr_bytes = 0;
                s.eof = true;
                break;
            };
        } else nr_bytes = c.SSL_write(ssl, buf.ptr, count);
        if (t.cb_error) |e| {
            t.cb_error = null;
            if (began_blocked) _ = setBlocking(obj, true);
            return e;
        }
        const left: ?i64 = if (has_timeout) timeout_us - elapsed else null;
        if (nr_bytes <= 0) {
            const err = c.SSL_get_error(ssl, nr_bytes);
            const r = try handleSslError(ctx, obj, t, nr_bytes, false, now_blocked);
            retry = r.retry;
            if (r.again and err == c.SSL_ERROR_WANT_READ and reading) retry = true;
            if (r.again and err == c.SSL_ERROR_WANT_WRITE and !reading) retry = true;
            // eof unless openssl just needs to wait
            if (reading) s.eof = !retry and err != c.SSL_ERROR_WANT_READ and err != c.SSL_ERROR_WANT_WRITE and c.SSL_pending(ssl) == 0;
            // don't loop forever on a non-blocking stream with nothing to do
            if (!began_blocked or supplemental) break;
            if (retry) {
                if (reading) {
                    pollFor(obj, if (err == c.SSL_ERROR_WANT_WRITE) POLLOUT_PRI else POLLIN_PRI, left);
                } else pollFor(obj, if (err == c.SSL_ERROR_WANT_READ) POLLIN_PRI else POLLOUT_PRI, left);
            }
        } else {
            const err = c.SSL_get_error(ssl, nr_bytes);
            if (err == c.SSL_ERROR_NONE) break;
            if (began_blocked) {
                if (reading) {
                    pollFor(obj, if (err == c.SSL_ERROR_WANT_WRITE) POLLOUT_PRI else POLLIN_PRI, left);
                } else pollFor(obj, if (err == c.SSL_ERROR_WANT_READ) POLLIN_PRI else POLLOUT_PRI, left);
            } else if (err == c.SSL_ERROR_WANT_READ) {
                t.last_status = STATUS_WANT_READ;
            } else if (err == c.SSL_ERROR_WANT_WRITE) {
                t.last_status = STATUS_WANT_WRITE;
            }
        }
        if (!retry) break;
    }
    if (nr_bytes > 0) try streams.progressIncrement(ctx, contextOfStreamCtx(obj), nr_bytes);
    // a supplemental read that found nothing isn't waiting for anything
    if (reading and supplemental and nr_bytes <= 0 and t.last_status == STATUS_WANT_READ) t.last_status = STATUS_NONE;
    if (began_blocked) _ = setBlocking(obj, true);
    return if (nr_bytes < 0) 0 else nr_bytes;
}

fn contextOfStreamCtx(obj: *PhpObject) ?*PhpObject {
    const own = obj.get("__context");
    return if (own == .resource) own.resource else null;
}

pub fn read(ctx: *NativeContext, obj: *PhpObject, s: *streams.Stream, t: *Tls, dest: []u8) RuntimeError!isize {
    if (s.may_block) ctx.vm.flushOutputToStdout();
    return io(ctx, obj, s, t, true, dest);
}

// a write takes everything a blocking stream can send, as the stream
// layer's write loop does
pub fn write(ctx: *NativeContext, obj: *PhpObject, s: *streams.Stream, t: *Tls, data: []const u8) RuntimeError!isize {
    var written: usize = 0;
    while (written < data.len) {
        const n = try io(ctx, obj, s, t, false, @constCast(data[written..]));
        if (n <= 0) {
            if (written == 0) return n;
            break;
        }
        written += @intCast(n);
    }
    return @intCast(written);
}

// what openssl holds decrypted and unread
pub fn pending(t: *Tls) usize {
    const n = c.SSL_pending(t.ssl orelse return 0);
    return if (n > 0) @intCast(n) else 0;
}

// whether the stream's reads go through openssl
pub fn activeOf(obj: *PhpObject, s: *streams.Stream) ?*Tls {
    _ = obj;
    const t = s.tls orelse return null;
    return if (t.active) t else null;
}

// PHP_STREAM_OPTION_CHECK_LIVENESS with a zero timeout for an active
// stream, as feof() asks: false once the peer closed or a fatal error is
// waiting
pub fn alive(obj: *PhpObject, t: *Tls) bool {
    const sock = socketOf(obj) orelse return false;
    var fds = [_]sys.pollfd{.{ .fd = sock, .events = sys.POLL.IN | sys.POLL.PRI, .revents = 0 }};
    const ready = sys.poll(&fds, 0) catch 0;
    if (ready == 0) return true;
    var b: [1]u8 = undefined;
    const began_blocked = isBlocked(obj);
    if (began_blocked) _ = setBlocking(obj, false);
    defer if (began_blocked) {
        _ = setBlocking(obj, true);
    };
    const n = c.SSL_peek(t.ssl, &b, 1);
    if (n > 0) return true;
    return switch (c.SSL_get_error(t.ssl, n)) {
        c.SSL_ERROR_SYSCALL => if (platform.is_windows)
            sys.ws2.WSAGetLastError() == sys.ws2.WSAEWOULDBLOCK
        else
            std.c._errno().* == @backingInt(std.posix.E.AGAIN),
        c.SSL_ERROR_WANT_READ, c.SSL_ERROR_WANT_WRITE => true,
        else => false,
    };
}

// PHP_STREAM_OPTION_META_DATA_API: the crypto entry an active stream reports
pub fn metaData(ctx: *NativeContext, t: *Tls, result: *PhpArray) RuntimeError!void {
    if (!t.active) return;
    const ssl = t.ssl.?;
    const arr = try ctx.createArray();
    const proto: []const u8 = switch (c.SSL_version(ssl)) {
        c.TLS1_3_VERSION => "TLSv1.3",
        c.TLS1_2_VERSION => "TLSv1.2",
        c.TLS1_1_VERSION => "TLSv1.1",
        c.TLS1_VERSION => "TLSv1",
        else => if (have_ssl3 and c.SSL_version(ssl) == c.SSL3_VERSION) "SSLv3" else "UNKNOWN",
    };
    const cipher = c.SSL_get_current_cipher(ssl);
    const key = struct {
        fn k(name: []const u8) PhpArray.Key {
            return .{ .string = Value.String.borrowed(name) };
        }
    }.k;
    try arr.setCopiedString(ctx.allocator, key("protocol"), proto);
    try arr.setCopiedString(ctx.allocator, key("cipher_name"), std.mem.span(c.SSL_CIPHER_get_name(cipher)));
    try arr.set(ctx.allocator, key("cipher_bits"), .{ .int = c.SSL_CIPHER_get_bits(cipher, null) });
    try arr.setCopiedString(ctx.allocator, key("cipher_version"), std.mem.span(c.SSL_CIPHER_get_version(cipher)));
    try arr.set(ctx.allocator, key("session_reused"), .{ .bool = c.SSL_session_reused(ssl) != 0 });
    var alpn: [*c]const u8 = null;
    var alpn_len: c_uint = 0;
    c.SSL_get0_alpn_selected(ssl, &alpn, &alpn_len);
    if (alpn != null) try arr.setCopiedString(ctx.allocator, key("alpn_protocol"), alpn[0..alpn_len]);
    try result.set(ctx.allocator, key("crypto"), .{ .array = arr });
}

// php_openssl_sockop_close with close_handle: the TLS session ends before
// the socket closes
pub fn shutdown(t: *Tls) void {
    if (t.active) {
        if (t.ssl) |ssl| _ = c.SSL_shutdown(ssl);
        t.active = false;
    }
}

// frees what the transport holds (the stream is going away)
pub fn free(t: *Tls) void {
    shutdown(t);
    if (t.ssl) |ssl| c.SSL_free(ssl);
    if (t.ctx) |x| c.SSL_CTX_free(x);
    for (t.sni_certs.items) |cert| {
        c.SSL_CTX_free(cert.ctx);
        allocator.free(cert.name);
    }
    t.sni_certs.deinit(allocator);
    if (t.alpn) |a| allocator.free(a);
    if (t.url_name) |u| allocator.free(u);
    allocator.destroy(t);
}

// --- the stream functions ----------------------------------------------------------

// php_stream_xport_crypto_setup and _enable on a stream that has no crypto
// to offer: php's warning, and its "not implemented"
const NOTIMPL: i32 = -2;

fn notSupported(ctx: *NativeContext, obj: *PhpObject) RuntimeError!i32 {
    try se.raise(ctx, .{ .code = .SslNotSupported, .wrapper = se.streamLabel(ctx.vm, obj), .context = contextOfStream(ctx.vm, obj) }, "This stream does not support SSL/crypto", .{});
    return NOTIMPL;
}

pub fn cryptoSetup(ctx: *NativeContext, obj: *PhpObject, method: i64, session: ?*PhpObject) RuntimeError!i32 {
    if (!capable(obj)) return notSupported(ctx, obj);
    return setup(ctx, obj, method, session);
}

pub fn cryptoEnable(ctx: *NativeContext, obj: *PhpObject, activate: bool) RuntimeError!i32 {
    if (!capable(obj)) return notSupported(ctx, obj);
    return enable(ctx, obj, activate);
}

// the crypto a crypto transport turns on once it connected (or accepted):
// false, after php's warning, when it failed
pub fn enableOnConnect(ctx: *NativeContext, obj: *PhpObject, session: ?*PhpObject) RuntimeError!bool {
    const t = of(obj) orelse return true;
    if (!t.enable_on_connect) return true;
    if (try setup(ctx, obj, t.method, session) < 0 or try enable(ctx, obj, true) < 0) {
        try warn(ctx, obj, .ProtocolError, "Failed to enable crypto", .{});
        return false;
    }
    return true;
}

// stream_socket_enable_crypto($stream, $enable, $crypto_method = null, $session_stream = null)
fn native_stream_socket_enable_crypto(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try fs.streamArg(ctx, args, .{ .func = "stream_socket_enable_crypto" });
    const on = args.len > 1 and args[1].isTruthy();
    const method_given = args.len > 2 and args[2] != .null;
    var session: ?*PhpObject = null;
    if (args.len > 3 and args[3] != .null) session = try fs.streamArg(ctx, args, .{ .func = "stream_socket_enable_crypto", .index = 3, .param = "session_stream" });
    if (on) {
        var method: i64 = if (method_given) Value.toInt(args[2]) else 0;
        if (!method_given) {
            const v = @import("http_wrapper.zig").contextOption(contextOfStream(ctx.vm, obj), "ssl", "crypto_method") orelse {
                try ctx.vm.setPendingException("ValueError", "stream_socket_enable_crypto(): Argument #3 ($crypto_method) must be specified when enabling encryption");
                return error.RuntimeError;
            };
            method = Value.toInt(v);
        }
        if (try cryptoSetup(ctx, obj, method, session) < 0) return NativeResult.scalar(.{ .bool = false });
    }
    return switch (try cryptoEnable(ctx, obj, on)) {
        -1 => NativeResult.scalar(.{ .bool = false }),
        0 => NativeResult.scalar(.{ .int = 0 }),
        else => NativeResult.scalar(.{ .bool = true }),
    };
}

// stream_socket_get_crypto_status($stream): what the last non-blocking
// handshake, read or write waits for
fn native_stream_socket_get_crypto_status(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try fs.streamArg(ctx, args, .{ .func = "stream_socket_get_crypto_status" });
    if (!capable(obj)) {
        _ = try notSupported(ctx, obj);
        return NativeResult.scalar(.{ .int = STATUS_NONE });
    }
    const t = of(obj) orelse return NativeResult.scalar(.{ .int = STATUS_NONE });
    return NativeResult.scalar(.{ .int = t.last_status });
}
