const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

const c = @cImport({
    @cInclude("openssl/evp.h");
    @cInclude("openssl/rand.h");
});

pub const entries = .{
    .{ "openssl_cipher_iv_length", cipherIvLength },
    .{ "openssl_encrypt", opensslEncrypt },
    .{ "openssl_decrypt", opensslDecrypt },
    .{ "openssl_cipher_key_length", cipherKeyLength },
    .{ "openssl_get_cipher_methods", getCipherMethods },
};

fn fetchCipher(name: []const u8) ?*const c.EVP_CIPHER {
    var buf: [64]u8 = undefined;
    if (name.len >= buf.len) return null;
    @memcpy(buf[0..name.len], name);
    buf[name.len] = 0;
    return c.EVP_CIPHER_fetch(null, &buf, null);
}

fn freeCipher(cipher: *const c.EVP_CIPHER) void {
    c.EVP_CIPHER_free(@constCast(cipher));
}

fn cipherIvLength(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const cipher = fetchCipher(args[0].string) orelse return .{ .bool = false };
    defer freeCipher(cipher);
    return .{ .int = c.EVP_CIPHER_iv_length(cipher) };
}

fn cipherKeyLength(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const cipher = fetchCipher(args[0].string) orelse return .{ .bool = false };
    defer freeCipher(cipher);
    return .{ .int = c.EVP_CIPHER_key_length(cipher) };
}

fn opensslEncrypt(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[0] != .string or args[1] != .string or args[2] != .string)
        return .{ .bool = false };

    const data = args[0].string;
    const cipher_name = args[1].string;
    const key = args[2].string;
    const options: i64 = if (args.len > 3 and args[3] == .int) args[3].int else 0;
    const iv: []const u8 = if (args.len > 4 and args[4] == .string) args[4].string else "";

    const cipher = fetchCipher(cipher_name) orelse return .{ .bool = false };
    defer freeCipher(cipher);

    const evp_ctx = c.EVP_CIPHER_CTX_new() orelse return .{ .bool = false };
    defer c.EVP_CIPHER_CTX_free(evp_ctx);

    const is_aead = isAeadCipher(cipher);
    const aad: []const u8 = if (args.len > 6 and args[6] == .string) args[6].string else "";

    if (c.EVP_EncryptInit_ex(evp_ctx, cipher, null, null, null) != 1)
        return .{ .bool = false };

    if (is_aead) {
        if (c.EVP_CIPHER_CTX_ctrl(evp_ctx, c.EVP_CTRL_AEAD_SET_IVLEN, @intCast(iv.len), null) != 1)
            return .{ .bool = false };
    }

    if (c.EVP_EncryptInit_ex(evp_ctx, null, null, key.ptr, if (iv.len > 0) iv.ptr else null) != 1)
        return .{ .bool = false };

    var written: c_int = 0;
    if (is_aead and aad.len > 0) {
        if (c.EVP_EncryptUpdate(evp_ctx, null, &written, aad.ptr, @intCast(aad.len)) != 1)
            return .{ .bool = false };
    }

    const block_size: usize = @intCast(c.EVP_CIPHER_block_size(cipher));
    const out_len = data.len + block_size;
    const out_buf = ctx.allocator.alloc(u8, out_len) catch return .{ .bool = false };
    defer ctx.allocator.free(out_buf);

    if (c.EVP_EncryptUpdate(evp_ctx, out_buf.ptr, &written, data.ptr, @intCast(data.len)) != 1)
        return .{ .bool = false };

    var total: usize = @intCast(written);
    if (c.EVP_EncryptFinal_ex(evp_ctx, out_buf.ptr + total, &written) != 1)
        return .{ .bool = false };
    total += @intCast(written);

    if (is_aead and args.len > 5) {
        var tag_buf: [16]u8 = undefined;
        const tag_len: usize = if (args.len > 7 and args[7] == .int and args[7].int > 0) @intCast(@min(args[7].int, 16)) else 16;
        if (c.EVP_CIPHER_CTX_ctrl(evp_ctx, c.EVP_CTRL_AEAD_GET_TAG, @intCast(tag_len), &tag_buf) != 1)
            return .{ .bool = false };
        const tag_str = try ctx.createString(tag_buf[0..tag_len]);
        ctx.setCallerVar(5, args.len, .{ .string = tag_str });
    }

    const raw = out_buf[0..total];
    if (options & 1 != 0) {
        return .{ .string = try ctx.createString(raw) };
    }
    return .{ .string = try base64Encode(ctx, raw) };
}

fn opensslDecrypt(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[0] != .string or args[1] != .string or args[2] != .string)
        return .{ .bool = false };

    const raw_data = args[0].string;
    const cipher_name = args[1].string;
    const key = args[2].string;
    const options: i64 = if (args.len > 3 and args[3] == .int) args[3].int else 0;
    const iv: []const u8 = if (args.len > 4 and args[4] == .string) args[4].string else "";

    const cipher = fetchCipher(cipher_name) orelse return .{ .bool = false };
    defer freeCipher(cipher);

    var decoded_buf: [8192]u8 = undefined;
    const data = if (options & 1 != 0) raw_data else blk: {
        const len = std.base64.standard.Decoder.calcSizeForSlice(raw_data) catch return .{ .bool = false };
        if (len > decoded_buf.len) return .{ .bool = false };
        std.base64.standard.Decoder.decode(decoded_buf[0..len], raw_data) catch return .{ .bool = false };
        break :blk decoded_buf[0..len];
    };

    const evp_ctx = c.EVP_CIPHER_CTX_new() orelse return .{ .bool = false };
    defer c.EVP_CIPHER_CTX_free(evp_ctx);

    const is_aead = isAeadCipher(cipher);
    const aad: []const u8 = if (args.len > 6 and args[6] == .string) args[6].string else "";

    if (c.EVP_DecryptInit_ex(evp_ctx, cipher, null, null, null) != 1)
        return .{ .bool = false };

    if (is_aead) {
        if (c.EVP_CIPHER_CTX_ctrl(evp_ctx, c.EVP_CTRL_AEAD_SET_IVLEN, @intCast(iv.len), null) != 1)
            return .{ .bool = false };
    }

    if (c.EVP_DecryptInit_ex(evp_ctx, null, null, key.ptr, if (iv.len > 0) iv.ptr else null) != 1)
        return .{ .bool = false };

    if (is_aead and args.len > 5 and args[5] == .string) {
        const tag = args[5].string;
        if (tag.len > 0) {
            if (c.EVP_CIPHER_CTX_ctrl(evp_ctx, c.EVP_CTRL_AEAD_SET_TAG, @intCast(tag.len), @constCast(tag.ptr)) != 1)
                return .{ .bool = false };
        }
    }

    var written: c_int = 0;
    if (is_aead and aad.len > 0) {
        if (c.EVP_DecryptUpdate(evp_ctx, null, &written, aad.ptr, @intCast(aad.len)) != 1)
            return .{ .bool = false };
    }

    const out_buf = ctx.allocator.alloc(u8, data.len + 128) catch return .{ .bool = false };
    defer ctx.allocator.free(out_buf);

    if (c.EVP_DecryptUpdate(evp_ctx, out_buf.ptr, &written, data.ptr, @intCast(data.len)) != 1)
        return .{ .bool = false };

    var total: usize = @intCast(written);
    if (c.EVP_DecryptFinal_ex(evp_ctx, out_buf.ptr + total, &written) != 1)
        return .{ .bool = false };
    total += @intCast(written);

    return .{ .string = try ctx.createString(out_buf[0..total]) };
}

fn isAeadCipher(cipher: *const c.EVP_CIPHER) bool {
    return (c.EVP_CIPHER_flags(cipher) & c.EVP_CIPH_FLAG_AEAD_CIPHER) != 0;
}

fn base64Encode(ctx: *NativeContext, data: []const u8) ![]const u8 {
    const len = std.base64.standard.Encoder.calcSize(data.len);
    const buf = try ctx.allocator.alloc(u8, len);
    const result = std.base64.standard.Encoder.encode(buf, data);
    try ctx.strings.append(ctx.allocator, buf);
    return result;
}

fn getCipherMethods(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const methods = [_][]const u8{
        "aes-128-cbc",   "aes-192-cbc",   "aes-256-cbc",
        "aes-128-gcm",   "aes-192-gcm",   "aes-256-gcm",
        "aes-128-ctr",   "aes-192-ctr",   "aes-256-ctr",
        "aes-128-ecb",   "aes-192-ecb",   "aes-256-ecb",
        "des-ede3-cbc",  "chacha20-poly1305",
    };
    const arr = try ctx.createArray();
    for (methods) |name| {
        try arr.append(ctx.allocator, .{ .string = name });
    }
    return .{ .array = arr };
}
