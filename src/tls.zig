const std = @import("std");
const posix = std.posix;

const c = @cImport({
    @cInclude("openssl/ssl.h");
    @cInclude("openssl/err.h");
});

pub const SSL = c.SSL;
pub const SSL_CTX = c.SSL_CTX;
pub const AlpnProtocol = enum { h2, http11 };

fn alpnSelectCb(
    _: ?*c.SSL,
    out: [*c][*c]const u8,
    outlen: [*c]u8,
    in: [*c]const u8,
    inlen: c_uint,
    _: ?*anyopaque,
) callconv(.c) c_int {
    // server prefers h2, falls back to http/1.1
    const server_protos = "\x02h2\x08http/1.1";
    const ret = c.SSL_select_next_proto(
        @ptrCast(out),
        outlen,
        server_protos,
        server_protos.len,
        in,
        inlen,
    );
    if (ret == c.OPENSSL_NPN_NEGOTIATED) return c.SSL_TLSEXT_ERR_OK;
    return c.SSL_TLSEXT_ERR_NOACK;
}

pub fn initContext(cert_path: [*:0]const u8, key_path: [*:0]const u8) ?*SSL_CTX {
    const method = c.TLS_server_method() orelse return null;
    const ctx = c.SSL_CTX_new(method) orelse return null;

    // reject deprecated TLS 1.0/1.1 - require 1.2+
    _ = c.SSL_CTX_set_min_proto_version(ctx, c.TLS1_2_VERSION);

    if (c.SSL_CTX_use_certificate_chain_file(ctx, cert_path) != 1) {
        c.SSL_CTX_free(ctx);
        return null;
    }

    if (c.SSL_CTX_use_PrivateKey_file(ctx, key_path, c.SSL_FILETYPE_PEM) != 1) {
        c.SSL_CTX_free(ctx);
        return null;
    }

    if (c.SSL_CTX_check_private_key(ctx) != 1) {
        c.SSL_CTX_free(ctx);
        return null;
    }

    // server-side ALPN: prefer h2, fall back to http/1.1
    c.SSL_CTX_set_alpn_select_cb(ctx, alpnSelectCb, null);

    return ctx;
}

pub fn getAlpnProtocol(ssl: *SSL) AlpnProtocol {
    var proto: [*c]const u8 = null;
    var len: c_uint = 0;
    c.SSL_get0_alpn_selected(ssl, &proto, &len);
    if (len == 2 and proto != null and proto[0] == 'h' and proto[1] == '2') return .h2;
    return .http11;
}

pub fn freeContext(ctx: *SSL_CTX) void {
    c.SSL_CTX_free(ctx);
}

pub const HandshakeResult = enum { complete, want_read, want_write, failed };

pub fn beginAccept(ctx: *SSL_CTX, fd: posix.fd_t) ?*SSL {
    const ssl = c.SSL_new(ctx) orelse return null;
    if (c.SSL_set_fd(ssl, fd) != 1) {
        c.SSL_free(ssl);
        return null;
    }
    return ssl;
}

pub fn continueAccept(ssl: *SSL) HandshakeResult {
    const ret = c.SSL_accept(ssl);
    if (ret == 1) return .complete;
    const err = c.SSL_get_error(ssl, ret);
    if (err == c.SSL_ERROR_WANT_READ) return .want_read;
    if (err == c.SSL_ERROR_WANT_WRITE) return .want_write;
    c.ERR_clear_error();
    return .failed;
}

pub fn read(ssl: *SSL, buf: []u8) !usize {
    const n = c.SSL_read(ssl, buf.ptr, @intCast(buf.len));
    if (n <= 0) {
        const err = c.SSL_get_error(ssl, n);
        // SSL_read can return WANT_WRITE during a renegotiation handshake; both
        // directions translate to "try again later" so the caller's event loop
        // can re-poll the socket without dropping the connection.
        if (err == c.SSL_ERROR_WANT_READ or err == c.SSL_ERROR_WANT_WRITE) return error.WouldBlock;
        if (err == c.SSL_ERROR_ZERO_RETURN) return 0;
        c.ERR_clear_error();
        return error.ConnectionResetByPeer;
    }
    return @intCast(n);
}

pub fn write(ssl: *SSL, data: []const u8) !usize {
    const n = c.SSL_write(ssl, data.ptr, @intCast(data.len));
    if (n <= 0) {
        const err = c.SSL_get_error(ssl, n);
        if (err == c.SSL_ERROR_WANT_WRITE or err == c.SSL_ERROR_WANT_READ) return error.WouldBlock;
        c.ERR_clear_error();
        return error.BrokenPipe;
    }
    return @intCast(n);
}

pub fn shutdown(ssl: *SSL) void {
    _ = c.SSL_shutdown(ssl);
    c.SSL_free(ssl);
}
