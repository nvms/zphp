const std = @import("std");
const posix = std.posix;

const c = @cImport({
    @cInclude("openssl/ssl.h");
    @cInclude("openssl/err.h");
});

pub const SSL = c.SSL;
pub const SSL_CTX = c.SSL_CTX;

pub fn initContext(cert_path: [*:0]const u8, key_path: [*:0]const u8) ?*SSL_CTX {
    const method = c.TLS_server_method() orelse return null;
    const ctx = c.SSL_CTX_new(method) orelse return null;

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

    return ctx;
}

pub fn freeContext(ctx: *SSL_CTX) void {
    c.SSL_CTX_free(ctx);
}

pub fn accept(ctx: *SSL_CTX, fd: posix.fd_t) ?*SSL {
    const ssl = c.SSL_new(ctx) orelse return null;
    if (c.SSL_set_fd(ssl, fd) != 1) {
        c.SSL_free(ssl);
        return null;
    }
    const ret = c.SSL_accept(ssl);
    if (ret != 1) {
        c.ERR_clear_error();
        c.SSL_free(ssl);
        return null;
    }
    return ssl;
}

pub fn read(ssl: *SSL, buf: []u8) !usize {
    const n = c.SSL_read(ssl, buf.ptr, @intCast(buf.len));
    if (n <= 0) {
        const err = c.SSL_get_error(ssl, n);
        if (err == c.SSL_ERROR_WANT_READ) return error.WouldBlock;
        if (err == c.SSL_ERROR_ZERO_RETURN) return 0;
        return error.ConnectionResetByPeer;
    }
    return @intCast(n);
}

pub fn write(ssl: *SSL, data: []const u8) !usize {
    const n = c.SSL_write(ssl, data.ptr, @intCast(data.len));
    if (n <= 0) {
        const err = c.SSL_get_error(ssl, n);
        if (err == c.SSL_ERROR_WANT_WRITE) return error.WouldBlock;
        return error.BrokenPipe;
    }
    return @intCast(n);
}

pub fn shutdown(ssl: *SSL) void {
    _ = c.SSL_shutdown(ssl);
    c.SSL_free(ssl);
}
