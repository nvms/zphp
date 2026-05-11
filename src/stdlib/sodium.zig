const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

const c = @cImport({
    @cInclude("sodium.h");
});

pub const entries = .{
    .{ "sodium_bin2hex", native_bin2hex },
    .{ "sodium_hex2bin", native_hex2bin },
    .{ "sodium_bin2base64", native_bin2base64 },
    .{ "sodium_base642bin", native_base642bin },
    .{ "sodium_memzero", native_memzero },
    .{ "sodium_memcmp", native_memcmp },
    .{ "sodium_compare", native_compare },
    .{ "sodium_increment", native_increment },
    .{ "sodium_add", native_add },
    .{ "sodium_pad", native_pad },
    .{ "sodium_unpad", native_unpad },
    .{ "sodium_crypto_secretbox", native_secretbox },
    .{ "sodium_crypto_secretbox_open", native_secretbox_open },
    .{ "sodium_crypto_secretbox_keygen", native_secretbox_keygen },
    .{ "sodium_crypto_box_keypair", native_box_keypair },
    .{ "sodium_crypto_box_keypair_from_secretkey_and_publickey", native_box_keypair_from_skpk },
    .{ "sodium_crypto_box_publickey", native_box_publickey },
    .{ "sodium_crypto_box_secretkey", native_box_secretkey },
    .{ "sodium_crypto_box_publickey_from_secretkey", native_box_pk_from_sk },
    .{ "sodium_crypto_box", native_box },
    .{ "sodium_crypto_box_open", native_box_open },
    .{ "sodium_crypto_box_seal", native_box_seal },
    .{ "sodium_crypto_box_seal_open", native_box_seal_open },
    .{ "sodium_crypto_sign_keypair", native_sign_keypair },
    .{ "sodium_crypto_sign_publickey", native_sign_publickey },
    .{ "sodium_crypto_sign_secretkey", native_sign_secretkey },
    .{ "sodium_crypto_sign_publickey_from_secretkey", native_sign_pk_from_sk },
    .{ "sodium_crypto_sign", native_sign },
    .{ "sodium_crypto_sign_open", native_sign_open },
    .{ "sodium_crypto_sign_detached", native_sign_detached },
    .{ "sodium_crypto_sign_verify_detached", native_sign_verify_detached },
    .{ "sodium_crypto_generichash", native_generichash },
    .{ "sodium_crypto_shorthash", native_shorthash },
    .{ "sodium_crypto_shorthash_keygen", native_shorthash_keygen },
    .{ "sodium_crypto_generichash_keygen", native_generichash_keygen },
    .{ "sodium_crypto_pwhash", native_pwhash },
    .{ "sodium_crypto_pwhash_str", native_pwhash_str },
    .{ "sodium_crypto_pwhash_str_verify", native_pwhash_str_verify },
    .{ "sodium_crypto_pwhash_str_needs_rehash", native_pwhash_str_needs_rehash },
    .{ "sodium_crypto_aead_chacha20poly1305_ietf_encrypt", native_aead_chacha_ietf_enc },
    .{ "sodium_crypto_aead_chacha20poly1305_ietf_decrypt", native_aead_chacha_ietf_dec },
    .{ "sodium_crypto_aead_chacha20poly1305_ietf_keygen", native_aead_chacha_ietf_keygen },
    .{ "sodium_crypto_aead_xchacha20poly1305_ietf_encrypt", native_aead_xchacha_ietf_enc },
    .{ "sodium_crypto_aead_xchacha20poly1305_ietf_decrypt", native_aead_xchacha_ietf_dec },
    .{ "sodium_crypto_aead_xchacha20poly1305_ietf_keygen", native_aead_xchacha_ietf_keygen },
    .{ "sodium_crypto_aead_aes256gcm_is_available", native_aes256gcm_avail },
    .{ "sodium_crypto_aead_aes256gcm_encrypt", native_aes256gcm_enc },
    .{ "sodium_crypto_aead_aes256gcm_decrypt", native_aes256gcm_dec },
    .{ "sodium_crypto_aead_aes256gcm_keygen", native_aes256gcm_keygen },
    .{ "sodium_crypto_auth", native_auth },
    .{ "sodium_crypto_auth_verify", native_auth_verify },
    .{ "sodium_crypto_auth_keygen", native_auth_keygen },
    .{ "sodium_crypto_kx_keypair", native_kx_keypair },
    .{ "sodium_crypto_kx_publickey", native_kx_publickey },
    .{ "sodium_crypto_kx_secretkey", native_kx_secretkey },
    .{ "sodium_crypto_kx_client_session_keys", native_kx_client_session_keys },
    .{ "sodium_crypto_kx_server_session_keys", native_kx_server_session_keys },
    .{ "sodium_crypto_scalarmult", native_scalarmult },
    .{ "sodium_crypto_scalarmult_base", native_scalarmult_base },
    .{ "sodium_crypto_kdf_keygen", native_kdf_keygen },
    .{ "sodium_crypto_kdf_derive_from_key", native_kdf_derive },
    .{ "sodium_randombytes_buf", native_randombytes_buf },
    .{ "sodium_randombytes_random16", native_randombytes_random16 },
    .{ "sodium_randombytes_uniform", native_randombytes_uniform },
};

var initialized: bool = false;

fn ensureInit() void {
    if (initialized) return;
    _ = c.sodium_init();
    initialized = true;
}

fn strBytes(v: Value) ?[]const u8 {
    return if (v == .string) v.string else null;
}

fn allocStr(ctx: *NativeContext, src: []const u8) RuntimeError!Value {
    const owned = try ctx.allocator.dupe(u8, src);
    try ctx.strings.append(ctx.allocator, owned);
    return .{ .string = owned };
}

fn native_bin2hex(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 1 or args[0] != .string) return .{ .string = "" };
    const bin = args[0].string;
    const out = try ctx.allocator.alloc(u8, bin.len * 2 + 1);
    defer ctx.allocator.free(out);
    _ = c.sodium_bin2hex(out.ptr, out.len, bin.ptr, bin.len);
    return try allocStr(ctx, out[0 .. bin.len * 2]);
}

fn native_hex2bin(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const hex = args[0].string;
    const ignore: ?[*:0]const u8 = if (args.len > 1 and args[1] == .string)
        (try ctx.allocator.dupeZ(u8, args[1].string)).ptr
    else
        null;
    const out = try ctx.allocator.alloc(u8, hex.len / 2 + 1);
    defer ctx.allocator.free(out);
    var out_len: usize = 0;
    const rc = c.sodium_hex2bin(out.ptr, out.len, hex.ptr, hex.len, ignore, &out_len, null);
    if (rc != 0) return .{ .bool = false };
    return try allocStr(ctx, out[0..out_len]);
}

fn native_bin2base64(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 1 or args[0] != .string) return .{ .string = "" };
    const variant: c_int = if (args.len > 1 and args[1] == .int) @intCast(args[1].int) else 1;
    const bin = args[0].string;
    const out_max = c.sodium_base64_encoded_len(bin.len, variant);
    const out = try ctx.allocator.alloc(u8, out_max);
    defer ctx.allocator.free(out);
    _ = c.sodium_bin2base64(out.ptr, out.len, bin.ptr, bin.len, variant);
    // result is NUL-terminated; trim
    var end = out.len;
    while (end > 0 and out[end - 1] == 0) end -= 1;
    return try allocStr(ctx, out[0..end]);
}

fn native_base642bin(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const variant: c_int = if (args.len > 1 and args[1] == .int) @intCast(args[1].int) else 1;
    const ignore: ?[*:0]const u8 = if (args.len > 2 and args[2] == .string)
        (try ctx.allocator.dupeZ(u8, args[2].string)).ptr
    else
        null;
    const src = args[0].string;
    const out = try ctx.allocator.alloc(u8, src.len + 1);
    defer ctx.allocator.free(out);
    var out_len: usize = 0;
    const rc = c.sodium_base642bin(out.ptr, out.len, src.ptr, src.len, ignore, &out_len, null, variant);
    if (rc != 0) return .{ .bool = false };
    return try allocStr(ctx, out[0..out_len]);
}

fn native_memzero(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .null;
}

fn native_memcmp(_: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .int = -1 };
    const a = args[0].string;
    const b = args[1].string;
    if (a.len != b.len) return .{ .int = -1 };
    return .{ .int = @intCast(c.sodium_memcmp(a.ptr, b.ptr, a.len)) };
}

fn native_compare(_: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .int = 0 };
    const a = args[0].string;
    const b = args[1].string;
    if (a.len != b.len) return .{ .int = if (a.len < b.len) -1 else 1 };
    return .{ .int = @intCast(c.sodium_compare(a.ptr, b.ptr, a.len)) };
}

fn native_increment(_: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 1 or args[0] != .string) return .null;
    const s = args[0].string;
    const mut: [*]u8 = @ptrCast(@constCast(s.ptr));
    c.sodium_increment(mut, s.len);
    return .null;
}

fn native_add(_: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .null;
    const a = args[0].string;
    const b = args[1].string;
    if (a.len != b.len) return .null;
    c.sodium_add(@ptrCast(@constCast(a.ptr)), b.ptr, a.len);
    return .null;
}

fn native_pad(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 2 or args[0] != .string or args[1] != .int) return .{ .bool = false };
    const block: usize = @intCast(args[1].int);
    if (block == 0) return .{ .bool = false };
    const src = args[0].string;
    const padded_len = src.len + (block - (src.len % block));
    const out = try ctx.allocator.alloc(u8, padded_len);
    defer ctx.allocator.free(out);
    @memcpy(out[0..src.len], src);
    var actual_len: usize = 0;
    const rc = c.sodium_pad(&actual_len, out.ptr, src.len, block, padded_len);
    if (rc != 0) return .{ .bool = false };
    return try allocStr(ctx, out[0..actual_len]);
}

fn native_unpad(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 2 or args[0] != .string or args[1] != .int) return .{ .bool = false };
    const block: usize = @intCast(args[1].int);
    if (block == 0) return .{ .bool = false };
    const src = args[0].string;
    var unpadded_len: usize = 0;
    const rc = c.sodium_unpad(&unpadded_len, src.ptr, src.len, block);
    if (rc != 0) return .{ .bool = false };
    return try allocStr(ctx, src[0..unpadded_len]);
}

fn native_secretbox(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 3 or args[0] != .string or args[1] != .string or args[2] != .string) return .{ .bool = false };
    const msg = args[0].string;
    const nonce = args[1].string;
    const key = args[2].string;
    if (nonce.len != c.crypto_secretbox_NONCEBYTES or key.len != c.crypto_secretbox_KEYBYTES) return .{ .bool = false };
    const out = try ctx.allocator.alloc(u8, msg.len + c.crypto_secretbox_MACBYTES);
    defer ctx.allocator.free(out);
    if (c.crypto_secretbox_easy(out.ptr, msg.ptr, msg.len, nonce.ptr, key.ptr) != 0) return .{ .bool = false };
    return try allocStr(ctx, out);
}

fn native_secretbox_open(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 3 or args[0] != .string or args[1] != .string or args[2] != .string) return .{ .bool = false };
    const ct = args[0].string;
    const nonce = args[1].string;
    const key = args[2].string;
    if (ct.len < c.crypto_secretbox_MACBYTES) return .{ .bool = false };
    if (nonce.len != c.crypto_secretbox_NONCEBYTES or key.len != c.crypto_secretbox_KEYBYTES) return .{ .bool = false };
    const out = try ctx.allocator.alloc(u8, ct.len - c.crypto_secretbox_MACBYTES);
    defer ctx.allocator.free(out);
    if (c.crypto_secretbox_open_easy(out.ptr, ct.ptr, ct.len, nonce.ptr, key.ptr) != 0) return .{ .bool = false };
    return try allocStr(ctx, out);
}

fn keygen(ctx: *NativeContext, len: usize) RuntimeError!Value {
    ensureInit();
    const buf = try ctx.allocator.alloc(u8, len);
    defer ctx.allocator.free(buf);
    c.randombytes_buf(buf.ptr, buf.len);
    return try allocStr(ctx, buf);
}

fn native_secretbox_keygen(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    return try keygen(ctx, c.crypto_secretbox_KEYBYTES);
}

fn native_box_keypair(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    ensureInit();
    var pk: [c.crypto_box_PUBLICKEYBYTES]u8 = undefined;
    var sk: [c.crypto_box_SECRETKEYBYTES]u8 = undefined;
    _ = c.crypto_box_keypair(&pk, &sk);
    var kp: [c.crypto_box_SECRETKEYBYTES + c.crypto_box_PUBLICKEYBYTES]u8 = undefined;
    @memcpy(kp[0..c.crypto_box_SECRETKEYBYTES], &sk);
    @memcpy(kp[c.crypto_box_SECRETKEYBYTES..], &pk);
    return try allocStr(ctx, &kp);
}

fn native_box_keypair_from_skpk(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const sk = args[0].string;
    const pk = args[1].string;
    if (sk.len != c.crypto_box_SECRETKEYBYTES or pk.len != c.crypto_box_PUBLICKEYBYTES) return .{ .bool = false };
    const out = try ctx.allocator.alloc(u8, sk.len + pk.len);
    defer ctx.allocator.free(out);
    @memcpy(out[0..sk.len], sk);
    @memcpy(out[sk.len..], pk);
    return try allocStr(ctx, out);
}

fn native_box_secretkey(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const kp = args[0].string;
    if (kp.len < c.crypto_box_SECRETKEYBYTES) return .{ .bool = false };
    return try allocStr(ctx, kp[0..c.crypto_box_SECRETKEYBYTES]);
}

fn native_box_publickey(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const kp = args[0].string;
    if (kp.len < c.crypto_box_SECRETKEYBYTES + c.crypto_box_PUBLICKEYBYTES) return .{ .bool = false };
    return try allocStr(ctx, kp[c.crypto_box_SECRETKEYBYTES..]);
}

fn native_box_pk_from_sk(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const sk = args[0].string;
    if (sk.len != c.crypto_box_SECRETKEYBYTES) return .{ .bool = false };
    var pk: [c.crypto_box_PUBLICKEYBYTES]u8 = undefined;
    _ = c.crypto_scalarmult_base(&pk, sk.ptr);
    return try allocStr(ctx, &pk);
}

fn native_box(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 3 or args[0] != .string or args[1] != .string or args[2] != .string) return .{ .bool = false };
    const msg = args[0].string;
    const nonce = args[1].string;
    const kp = args[2].string;
    if (kp.len != c.crypto_box_SECRETKEYBYTES + c.crypto_box_PUBLICKEYBYTES) return .{ .bool = false };
    if (nonce.len != c.crypto_box_NONCEBYTES) return .{ .bool = false };
    const sk = kp[0..c.crypto_box_SECRETKEYBYTES];
    const pk = kp[c.crypto_box_SECRETKEYBYTES..];
    const out = try ctx.allocator.alloc(u8, msg.len + c.crypto_box_MACBYTES);
    defer ctx.allocator.free(out);
    if (c.crypto_box_easy(out.ptr, msg.ptr, msg.len, nonce.ptr, pk.ptr, sk.ptr) != 0) return .{ .bool = false };
    return try allocStr(ctx, out);
}

fn native_box_open(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 3 or args[0] != .string or args[1] != .string or args[2] != .string) return .{ .bool = false };
    const ct = args[0].string;
    const nonce = args[1].string;
    const kp = args[2].string;
    if (kp.len != c.crypto_box_SECRETKEYBYTES + c.crypto_box_PUBLICKEYBYTES) return .{ .bool = false };
    if (nonce.len != c.crypto_box_NONCEBYTES) return .{ .bool = false };
    if (ct.len < c.crypto_box_MACBYTES) return .{ .bool = false };
    const sk = kp[0..c.crypto_box_SECRETKEYBYTES];
    const pk = kp[c.crypto_box_SECRETKEYBYTES..];
    const out = try ctx.allocator.alloc(u8, ct.len - c.crypto_box_MACBYTES);
    defer ctx.allocator.free(out);
    if (c.crypto_box_open_easy(out.ptr, ct.ptr, ct.len, nonce.ptr, pk.ptr, sk.ptr) != 0) return .{ .bool = false };
    return try allocStr(ctx, out);
}

fn native_box_seal(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const msg = args[0].string;
    const pk = args[1].string;
    if (pk.len != c.crypto_box_PUBLICKEYBYTES) return .{ .bool = false };
    const out = try ctx.allocator.alloc(u8, msg.len + c.crypto_box_SEALBYTES);
    defer ctx.allocator.free(out);
    if (c.crypto_box_seal(out.ptr, msg.ptr, msg.len, pk.ptr) != 0) return .{ .bool = false };
    return try allocStr(ctx, out);
}

fn native_box_seal_open(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const ct = args[0].string;
    const kp = args[1].string;
    if (kp.len != c.crypto_box_SECRETKEYBYTES + c.crypto_box_PUBLICKEYBYTES) return .{ .bool = false };
    if (ct.len < c.crypto_box_SEALBYTES) return .{ .bool = false };
    const sk = kp[0..c.crypto_box_SECRETKEYBYTES];
    const pk = kp[c.crypto_box_SECRETKEYBYTES..];
    const out = try ctx.allocator.alloc(u8, ct.len - c.crypto_box_SEALBYTES);
    defer ctx.allocator.free(out);
    if (c.crypto_box_seal_open(out.ptr, ct.ptr, ct.len, pk.ptr, sk.ptr) != 0) return .{ .bool = false };
    return try allocStr(ctx, out);
}

fn native_sign_keypair(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    ensureInit();
    var pk: [c.crypto_sign_PUBLICKEYBYTES]u8 = undefined;
    var sk: [c.crypto_sign_SECRETKEYBYTES]u8 = undefined;
    _ = c.crypto_sign_keypair(&pk, &sk);
    var out: [c.crypto_sign_SECRETKEYBYTES + c.crypto_sign_PUBLICKEYBYTES]u8 = undefined;
    @memcpy(out[0..c.crypto_sign_SECRETKEYBYTES], &sk);
    @memcpy(out[c.crypto_sign_SECRETKEYBYTES..], &pk);
    return try allocStr(ctx, &out);
}

fn native_sign_publickey(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const kp = args[0].string;
    if (kp.len < c.crypto_sign_SECRETKEYBYTES + c.crypto_sign_PUBLICKEYBYTES) return .{ .bool = false };
    return try allocStr(ctx, kp[c.crypto_sign_SECRETKEYBYTES..]);
}

fn native_sign_secretkey(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const kp = args[0].string;
    if (kp.len < c.crypto_sign_SECRETKEYBYTES) return .{ .bool = false };
    return try allocStr(ctx, kp[0..c.crypto_sign_SECRETKEYBYTES]);
}

fn native_sign_pk_from_sk(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const sk = args[0].string;
    if (sk.len != c.crypto_sign_SECRETKEYBYTES) return .{ .bool = false };
    var pk: [c.crypto_sign_PUBLICKEYBYTES]u8 = undefined;
    if (c.crypto_sign_ed25519_sk_to_pk(&pk, sk.ptr) != 0) return .{ .bool = false };
    return try allocStr(ctx, &pk);
}

fn native_sign(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const msg = args[0].string;
    const sk = args[1].string;
    if (sk.len != c.crypto_sign_SECRETKEYBYTES) return .{ .bool = false };
    const out = try ctx.allocator.alloc(u8, msg.len + c.crypto_sign_BYTES);
    defer ctx.allocator.free(out);
    var slen: c_ulonglong = 0;
    if (c.crypto_sign(out.ptr, &slen, msg.ptr, msg.len, sk.ptr) != 0) return .{ .bool = false };
    return try allocStr(ctx, out[0..slen]);
}

fn native_sign_open(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const signed = args[0].string;
    const pk = args[1].string;
    if (pk.len != c.crypto_sign_PUBLICKEYBYTES) return .{ .bool = false };
    const out = try ctx.allocator.alloc(u8, signed.len);
    defer ctx.allocator.free(out);
    var mlen: c_ulonglong = 0;
    if (c.crypto_sign_open(out.ptr, &mlen, signed.ptr, signed.len, pk.ptr) != 0) return .{ .bool = false };
    return try allocStr(ctx, out[0..mlen]);
}

fn native_sign_detached(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const msg = args[0].string;
    const sk = args[1].string;
    if (sk.len != c.crypto_sign_SECRETKEYBYTES) return .{ .bool = false };
    var sig: [c.crypto_sign_BYTES]u8 = undefined;
    var slen: c_ulonglong = 0;
    if (c.crypto_sign_detached(&sig, &slen, msg.ptr, msg.len, sk.ptr) != 0) return .{ .bool = false };
    return try allocStr(ctx, sig[0..slen]);
}

fn native_sign_verify_detached(_: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 3 or args[0] != .string or args[1] != .string or args[2] != .string) return .{ .bool = false };
    const sig = args[0].string;
    const msg = args[1].string;
    const pk = args[2].string;
    if (sig.len != c.crypto_sign_BYTES or pk.len != c.crypto_sign_PUBLICKEYBYTES) return .{ .bool = false };
    return .{ .bool = c.crypto_sign_verify_detached(sig.ptr, msg.ptr, msg.len, pk.ptr) == 0 };
}

fn native_generichash(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const msg = args[0].string;
    const key: ?[*]const u8 = if (args.len > 1 and args[1] == .string and args[1].string.len > 0) args[1].string.ptr else null;
    const klen: usize = if (args.len > 1 and args[1] == .string) args[1].string.len else 0;
    const out_len: usize = if (args.len > 2 and args[2] == .int) @intCast(args[2].int) else c.crypto_generichash_BYTES;
    const out = try ctx.allocator.alloc(u8, out_len);
    defer ctx.allocator.free(out);
    if (c.crypto_generichash(out.ptr, out.len, msg.ptr, msg.len, key, klen) != 0) return .{ .bool = false };
    return try allocStr(ctx, out);
}

fn native_generichash_keygen(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    return try keygen(ctx, c.crypto_generichash_KEYBYTES);
}

fn native_shorthash(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const msg = args[0].string;
    const key = args[1].string;
    if (key.len != c.crypto_shorthash_KEYBYTES) return .{ .bool = false };
    var out: [c.crypto_shorthash_BYTES]u8 = undefined;
    if (c.crypto_shorthash(&out, msg.ptr, msg.len, key.ptr) != 0) return .{ .bool = false };
    return try allocStr(ctx, &out);
}

fn native_shorthash_keygen(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    return try keygen(ctx, c.crypto_shorthash_KEYBYTES);
}

fn native_pwhash(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 5) return .{ .bool = false };
    if (args[0] != .int or args[1] != .string or args[2] != .string or args[3] != .int or args[4] != .int) return .{ .bool = false };
    const out_len: usize = @intCast(args[0].int);
    const pass = args[1].string;
    const salt = args[2].string;
    if (salt.len != c.crypto_pwhash_SALTBYTES) return .{ .bool = false };
    const ops: c_ulonglong = @intCast(args[3].int);
    const mem: usize = @intCast(args[4].int);
    const alg: c_int = if (args.len > 5 and args[5] == .int) @intCast(args[5].int) else c.crypto_pwhash_ALG_DEFAULT;
    const out = try ctx.allocator.alloc(u8, out_len);
    defer ctx.allocator.free(out);
    if (c.crypto_pwhash(out.ptr, out_len, pass.ptr, pass.len, salt.ptr, ops, mem, alg) != 0) return .{ .bool = false };
    return try allocStr(ctx, out);
}

fn native_pwhash_str(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 3 or args[0] != .string or args[1] != .int or args[2] != .int) return .{ .bool = false };
    const pass = args[0].string;
    const ops: c_ulonglong = @intCast(args[1].int);
    const mem: usize = @intCast(args[2].int);
    var out: [c.crypto_pwhash_STRBYTES]u8 = undefined;
    if (c.crypto_pwhash_str(&out, pass.ptr, pass.len, ops, mem) != 0) return .{ .bool = false };
    const slen = std.mem.indexOfScalar(u8, &out, 0) orelse out.len;
    return try allocStr(ctx, out[0..slen]);
}

fn native_pwhash_str_verify(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const hash_z = try ctx.allocator.dupeZ(u8, args[0].string);
    defer ctx.allocator.free(hash_z);
    const pass = args[1].string;
    return .{ .bool = c.crypto_pwhash_str_verify(hash_z.ptr, pass.ptr, pass.len) == 0 };
}

fn native_pwhash_str_needs_rehash(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 3 or args[0] != .string or args[1] != .int or args[2] != .int) return .{ .bool = true };
    const hash_z = try ctx.allocator.dupeZ(u8, args[0].string);
    defer ctx.allocator.free(hash_z);
    const ops: c_ulonglong = @intCast(args[1].int);
    const mem: usize = @intCast(args[2].int);
    return .{ .bool = c.crypto_pwhash_str_needs_rehash(hash_z.ptr, ops, mem) != 0 };
}

fn aeadEncrypt(comptime klen: usize, comptime nlen: usize, comptime alen: usize, comptime enc: anytype, ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 4 or args[0] != .string or args[1] != .string or args[2] != .string or args[3] != .string) return .{ .bool = false };
    const msg = args[0].string;
    const ad = args[1].string;
    const nonce = args[2].string;
    const key = args[3].string;
    if (nonce.len != nlen or key.len != klen) return .{ .bool = false };
    const out = try ctx.allocator.alloc(u8, msg.len + alen);
    defer ctx.allocator.free(out);
    var clen: c_ulonglong = 0;
    if (enc(out.ptr, &clen, msg.ptr, msg.len, ad.ptr, ad.len, null, nonce.ptr, key.ptr) != 0) return .{ .bool = false };
    return try allocStr(ctx, out[0..clen]);
}

fn aeadDecrypt(comptime klen: usize, comptime nlen: usize, comptime alen: usize, comptime dec: anytype, ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 4 or args[0] != .string or args[1] != .string or args[2] != .string or args[3] != .string) return .{ .bool = false };
    const ct = args[0].string;
    const ad = args[1].string;
    const nonce = args[2].string;
    const key = args[3].string;
    if (nonce.len != nlen or key.len != klen) return .{ .bool = false };
    if (ct.len < alen) return .{ .bool = false };
    const out = try ctx.allocator.alloc(u8, ct.len - alen);
    defer ctx.allocator.free(out);
    var mlen: c_ulonglong = 0;
    if (dec(out.ptr, &mlen, null, ct.ptr, ct.len, ad.ptr, ad.len, nonce.ptr, key.ptr) != 0) return .{ .bool = false };
    return try allocStr(ctx, out[0..mlen]);
}

fn native_aead_chacha_ietf_enc(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return aeadEncrypt(
        c.crypto_aead_chacha20poly1305_IETF_KEYBYTES,
        c.crypto_aead_chacha20poly1305_IETF_NPUBBYTES,
        c.crypto_aead_chacha20poly1305_IETF_ABYTES,
        c.crypto_aead_chacha20poly1305_ietf_encrypt,
        ctx,
        args,
    );
}
fn native_aead_chacha_ietf_dec(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return aeadDecrypt(
        c.crypto_aead_chacha20poly1305_IETF_KEYBYTES,
        c.crypto_aead_chacha20poly1305_IETF_NPUBBYTES,
        c.crypto_aead_chacha20poly1305_IETF_ABYTES,
        c.crypto_aead_chacha20poly1305_ietf_decrypt,
        ctx,
        args,
    );
}
fn native_aead_chacha_ietf_keygen(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    return try keygen(ctx, c.crypto_aead_chacha20poly1305_IETF_KEYBYTES);
}

fn native_aead_xchacha_ietf_enc(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return aeadEncrypt(
        c.crypto_aead_xchacha20poly1305_IETF_KEYBYTES,
        c.crypto_aead_xchacha20poly1305_IETF_NPUBBYTES,
        c.crypto_aead_xchacha20poly1305_IETF_ABYTES,
        c.crypto_aead_xchacha20poly1305_ietf_encrypt,
        ctx,
        args,
    );
}
fn native_aead_xchacha_ietf_dec(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return aeadDecrypt(
        c.crypto_aead_xchacha20poly1305_IETF_KEYBYTES,
        c.crypto_aead_xchacha20poly1305_IETF_NPUBBYTES,
        c.crypto_aead_xchacha20poly1305_IETF_ABYTES,
        c.crypto_aead_xchacha20poly1305_ietf_decrypt,
        ctx,
        args,
    );
}
fn native_aead_xchacha_ietf_keygen(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    return try keygen(ctx, c.crypto_aead_xchacha20poly1305_IETF_KEYBYTES);
}

fn native_aes256gcm_avail(_: *NativeContext, _: []const Value) RuntimeError!Value {
    ensureInit();
    return .{ .bool = c.crypto_aead_aes256gcm_is_available() == 1 };
}
fn native_aes256gcm_enc(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return aeadEncrypt(
        c.crypto_aead_aes256gcm_KEYBYTES,
        c.crypto_aead_aes256gcm_NPUBBYTES,
        c.crypto_aead_aes256gcm_ABYTES,
        c.crypto_aead_aes256gcm_encrypt,
        ctx,
        args,
    );
}
fn native_aes256gcm_dec(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return aeadDecrypt(
        c.crypto_aead_aes256gcm_KEYBYTES,
        c.crypto_aead_aes256gcm_NPUBBYTES,
        c.crypto_aead_aes256gcm_ABYTES,
        c.crypto_aead_aes256gcm_decrypt,
        ctx,
        args,
    );
}
fn native_aes256gcm_keygen(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    return try keygen(ctx, c.crypto_aead_aes256gcm_KEYBYTES);
}

fn native_auth(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const msg = args[0].string;
    const key = args[1].string;
    if (key.len != c.crypto_auth_KEYBYTES) return .{ .bool = false };
    var out: [c.crypto_auth_BYTES]u8 = undefined;
    if (c.crypto_auth(&out, msg.ptr, msg.len, key.ptr) != 0) return .{ .bool = false };
    return try allocStr(ctx, &out);
}

fn native_auth_verify(_: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 3 or args[0] != .string or args[1] != .string or args[2] != .string) return .{ .bool = false };
    const mac = args[0].string;
    const msg = args[1].string;
    const key = args[2].string;
    if (mac.len != c.crypto_auth_BYTES or key.len != c.crypto_auth_KEYBYTES) return .{ .bool = false };
    return .{ .bool = c.crypto_auth_verify(mac.ptr, msg.ptr, msg.len, key.ptr) == 0 };
}

fn native_auth_keygen(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    return try keygen(ctx, c.crypto_auth_KEYBYTES);
}

fn native_kx_keypair(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    ensureInit();
    var pk: [c.crypto_kx_PUBLICKEYBYTES]u8 = undefined;
    var sk: [c.crypto_kx_SECRETKEYBYTES]u8 = undefined;
    _ = c.crypto_kx_keypair(&pk, &sk);
    var out: [c.crypto_kx_SECRETKEYBYTES + c.crypto_kx_PUBLICKEYBYTES]u8 = undefined;
    @memcpy(out[0..c.crypto_kx_SECRETKEYBYTES], &sk);
    @memcpy(out[c.crypto_kx_SECRETKEYBYTES..], &pk);
    return try allocStr(ctx, &out);
}

fn native_kx_publickey(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const kp = args[0].string;
    if (kp.len < c.crypto_kx_SECRETKEYBYTES + c.crypto_kx_PUBLICKEYBYTES) return .{ .bool = false };
    return try allocStr(ctx, kp[c.crypto_kx_SECRETKEYBYTES..]);
}

fn native_kx_secretkey(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const kp = args[0].string;
    if (kp.len < c.crypto_kx_SECRETKEYBYTES) return .{ .bool = false };
    return try allocStr(ctx, kp[0..c.crypto_kx_SECRETKEYBYTES]);
}

fn native_kx_client_session_keys(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const kp = args[0].string;
    const server_pk = args[1].string;
    if (kp.len != c.crypto_kx_SECRETKEYBYTES + c.crypto_kx_PUBLICKEYBYTES) return .{ .bool = false };
    if (server_pk.len != c.crypto_kx_PUBLICKEYBYTES) return .{ .bool = false };
    var rx: [c.crypto_kx_SESSIONKEYBYTES]u8 = undefined;
    var tx: [c.crypto_kx_SESSIONKEYBYTES]u8 = undefined;
    if (c.crypto_kx_client_session_keys(&rx, &tx, kp[c.crypto_kx_SECRETKEYBYTES..].ptr, kp[0..c.crypto_kx_SECRETKEYBYTES].ptr, server_pk.ptr) != 0) return .{ .bool = false };
    const arr = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .int = 0 }, try allocStr(ctx, &rx));
    try arr.set(ctx.allocator, .{ .int = 1 }, try allocStr(ctx, &tx));
    return .{ .array = arr };
}

fn native_kx_server_session_keys(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const kp = args[0].string;
    const client_pk = args[1].string;
    if (kp.len != c.crypto_kx_SECRETKEYBYTES + c.crypto_kx_PUBLICKEYBYTES) return .{ .bool = false };
    if (client_pk.len != c.crypto_kx_PUBLICKEYBYTES) return .{ .bool = false };
    var rx: [c.crypto_kx_SESSIONKEYBYTES]u8 = undefined;
    var tx: [c.crypto_kx_SESSIONKEYBYTES]u8 = undefined;
    if (c.crypto_kx_server_session_keys(&rx, &tx, kp[c.crypto_kx_SECRETKEYBYTES..].ptr, kp[0..c.crypto_kx_SECRETKEYBYTES].ptr, client_pk.ptr) != 0) return .{ .bool = false };
    const arr = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .int = 0 }, try allocStr(ctx, &rx));
    try arr.set(ctx.allocator, .{ .int = 1 }, try allocStr(ctx, &tx));
    return .{ .array = arr };
}

fn native_scalarmult(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const sk = args[0].string;
    const pk = args[1].string;
    if (sk.len != c.crypto_scalarmult_SCALARBYTES or pk.len != c.crypto_scalarmult_BYTES) return .{ .bool = false };
    var out: [c.crypto_scalarmult_BYTES]u8 = undefined;
    if (c.crypto_scalarmult(&out, sk.ptr, pk.ptr) != 0) return .{ .bool = false };
    return try allocStr(ctx, &out);
}

fn native_scalarmult_base(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const sk = args[0].string;
    if (sk.len != c.crypto_scalarmult_SCALARBYTES) return .{ .bool = false };
    var out: [c.crypto_scalarmult_BYTES]u8 = undefined;
    if (c.crypto_scalarmult_base(&out, sk.ptr) != 0) return .{ .bool = false };
    return try allocStr(ctx, &out);
}

fn native_kdf_keygen(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    return try keygen(ctx, c.crypto_kdf_KEYBYTES);
}

fn native_kdf_derive(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 4 or args[0] != .int or args[1] != .int or args[2] != .string or args[3] != .string) return .{ .bool = false };
    const out_len: usize = @intCast(args[0].int);
    const subkey_id: u64 = @intCast(args[1].int);
    const context = args[2].string;
    const key = args[3].string;
    if (key.len != c.crypto_kdf_KEYBYTES) return .{ .bool = false };
    if (context.len < c.crypto_kdf_CONTEXTBYTES) return .{ .bool = false };
    var ctx_buf: [c.crypto_kdf_CONTEXTBYTES]u8 = undefined;
    @memcpy(&ctx_buf, context[0..c.crypto_kdf_CONTEXTBYTES]);
    const out = try ctx.allocator.alloc(u8, out_len);
    defer ctx.allocator.free(out);
    if (c.crypto_kdf_derive_from_key(out.ptr, out.len, subkey_id, &ctx_buf, key.ptr) != 0) return .{ .bool = false };
    return try allocStr(ctx, out);
}

fn native_randombytes_buf(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 1 or args[0] != .int) return .{ .string = "" };
    const n: usize = @intCast(args[0].int);
    return try keygen(ctx, n);
}

fn native_randombytes_random16(_: *NativeContext, _: []const Value) RuntimeError!Value {
    ensureInit();
    return .{ .int = @intCast(c.randombytes_random()) };
}

fn native_randombytes_uniform(_: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureInit();
    if (args.len < 1 or args[0] != .int) return .{ .int = 0 };
    return .{ .int = @intCast(c.randombytes_uniform(@intCast(args[0].int))) };
}

test {}
