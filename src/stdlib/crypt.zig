// php_crypt (ext/standard/crypt.c) and the hashes it dispatches to, ported
// from php's own copies so results match php on every platform: md5-crypt
// (php_crypt_r.c), sha256/sha512-crypt (crypt_sha256.c, crypt_sha512.c),
// bcrypt with the $2a$/$2b$/$2x$/$2y$ variants (crypt_blowfish.c) and
// traditional and extended DES (crypt_freesec.c).
//
// php hands these functions C strings: the password and the salt both end at
// their first nul byte, and reads past the end see a nul

const std = @import("std");
const bf_tables = @import("crypt_blowfish_tables.zig");

pub const max_salt_len = 123;

// a C string view: reads past the end give the terminating nul
const CStr = struct {
    s: []const u8,

    fn of(bytes: []const u8) CStr {
        const end = std.mem.indexOfScalar(u8, bytes, 0) orelse bytes.len;
        return .{ .s = bytes[0..end] };
    }

    fn at(self: CStr, i: usize) u8 {
        return if (i < self.s.len) self.s[i] else 0;
    }

    fn from(self: CStr, i: usize) CStr {
        return .{ .s = if (i < self.s.len) self.s[i..] else "" };
    }
};

fn isValidSaltChar(c: u8) bool {
    return (c >= '.' and c <= '9') or (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z');
}

/// php_crypt: the hash of `password` for `salt`, or null where php returns
/// NULL (crypt() then answers "*0", or "*1" for a salt starting "*0")
pub fn phpCrypt(allocator: std.mem.Allocator, password_bytes: []const u8, salt_bytes: []const u8) !?[]u8 {
    const pw = CStr.of(password_bytes);
    const salt = CStr.of(salt_bytes);
    if (salt.at(0) == '*' and (salt.at(1) == '0' or salt.at(1) == '1')) return null;

    var out: [max_salt_len + 1]u8 = undefined;
    const result: ?[]const u8 = if (salt.at(0) == '$' and salt.at(1) == '1' and salt.at(2) == '$')
        md5Crypt(pw, salt, &out)
    else if (salt.at(0) == '$' and salt.at(1) == '6' and salt.at(2) == '$')
        shaCrypt(std.crypto.hash.sha2.Sha512, pw, salt, &out)
    else if (salt.at(0) == '$' and salt.at(1) == '5' and salt.at(2) == '$')
        shaCrypt(std.crypto.hash.sha2.Sha256, pw, salt, &out)
    else if (salt.at(0) == '$' and salt.at(1) == '2' and salt.at(2) != 0 and salt.at(3) == '$')
        bfCrypt(pw, salt, &out)
    else if (salt.at(0) == '_' or (isValidSaltChar(salt.at(0)) and isValidSaltChar(salt.at(1))))
        desCrypt(pw, salt, &out)
    else
        null;
    const r = result orelse return null;
    const copy = try allocator.dupe(u8, r);
    std.crypto.secureZero(u8, &out);
    return copy;
}

// ---------------------------------------------------------------- md5-crypt

const itoa64 = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

fn to64(out: []u8, pos: *usize, value: u32, n: usize) void {
    var v = value;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        out[pos.*] = itoa64[v & 0x3f];
        pos.* += 1;
        v >>= 6;
    }
}

fn md5Crypt(pw: CStr, salt: CStr, out: []u8) []const u8 {
    const Md5 = std.crypto.hash.Md5;
    const magic = "$1$";
    var sp = salt;
    if (std.mem.startsWith(u8, sp.s, magic)) sp = sp.from(magic.len);
    var sl: usize = 0;
    while (sl < 8 and sp.at(sl) != 0 and sp.at(sl) != '$') sl += 1;
    const s = sp.s[0..sl];
    const p = pw.s;

    var ctx = Md5.init(.{});
    ctx.update(p);
    ctx.update(magic);
    ctx.update(s);

    var final: [16]u8 = undefined;
    var ctx1 = Md5.init(.{});
    ctx1.update(p);
    ctx1.update(s);
    ctx1.update(p);
    ctx1.final(&final);

    var pl: isize = @intCast(p.len);
    while (pl > 0) : (pl -= 16) ctx.update(final[0..@intCast(@min(pl, 16))]);
    @memset(&final, 0);

    // "then something really weird": a zeroed byte of final or the first
    // byte of the password for each bit of the length
    var i: usize = p.len;
    while (i != 0) : (i >>= 1) {
        if (i & 1 != 0) ctx.update(final[0..1]) else ctx.update(p[0..@min(1, p.len)]);
    }
    ctx.final(&final);

    var round: usize = 0;
    while (round < 1000) : (round += 1) {
        ctx1 = Md5.init(.{});
        if (round & 1 != 0) ctx1.update(p) else ctx1.update(&final);
        if (round % 3 != 0) ctx1.update(s);
        if (round % 7 != 0) ctx1.update(p);
        if (round & 1 != 0) ctx1.update(&final) else ctx1.update(p);
        ctx1.final(&final);
    }

    var pos: usize = 0;
    @memcpy(out[0..magic.len], magic);
    pos += magic.len;
    @memcpy(out[pos .. pos + sl], s);
    pos += sl;
    out[pos] = '$';
    pos += 1;
    const f = final;
    to64(out, &pos, (@as(u32, f[0]) << 16) | (@as(u32, f[6]) << 8) | f[12], 4);
    to64(out, &pos, (@as(u32, f[1]) << 16) | (@as(u32, f[7]) << 8) | f[13], 4);
    to64(out, &pos, (@as(u32, f[2]) << 16) | (@as(u32, f[8]) << 8) | f[14], 4);
    to64(out, &pos, (@as(u32, f[3]) << 16) | (@as(u32, f[9]) << 8) | f[15], 4);
    to64(out, &pos, (@as(u32, f[4]) << 16) | (@as(u32, f[10]) << 8) | f[5], 4);
    to64(out, &pos, f[11], 2);
    return out[0..pos];
}

// ------------------------------------------------------- sha256/sha512-crypt

const sha_rounds_default = 5000;
const sha_rounds_min = 1000;
const sha_rounds_max = 999999999;
const sha_salt_len_max = 16;

// strtoul(num, &endp, 10) as far as the caller looks at it: the value (null
// when it overflows or is negative, both out of any accepted range) and where
// the number ended
fn strtoulBase10(s: CStr, start: usize) struct { value: ?u64, end: usize } {
    var i = start;
    while (switch (s.at(i)) {
        ' ', '\t', '\n', '\r', 0x0b, 0x0c => true,
        else => false,
    }) i += 1;
    var negative = false;
    if (s.at(i) == '+' or s.at(i) == '-') {
        negative = s.at(i) == '-';
        i += 1;
    }
    const digits_start = i;
    var value: ?u64 = 0;
    while (s.at(i) >= '0' and s.at(i) <= '9') : (i += 1) {
        if (value) |v| {
            const mul = std.math.mul(u64, v, 10) catch null;
            value = if (mul) |m| std.math.add(u64, m, s.at(i) - '0') catch null else null;
        }
    }
    if (i == digits_start) return .{ .value = 0, .end = start };
    if (negative and value != null and value.? != 0) value = null;
    return .{ .value = value, .end = i };
}

fn shaCrypt(comptime H: type, pw: CStr, salt_in: CStr, buffer: []u8) ?[]const u8 {
    const is512 = H.digest_length == 64;
    const dl = H.digest_length;
    const prefix = if (is512) "$6$" else "$5$";
    var salt = salt_in;
    if (std.mem.startsWith(u8, salt.s, prefix)) salt = salt.from(prefix.len);

    var rounds: u64 = sha_rounds_default;
    var rounds_custom = false;
    const rounds_prefix = "rounds=";
    if (std.mem.startsWith(u8, salt.s, rounds_prefix)) {
        const r = strtoulBase10(salt, rounds_prefix.len);
        if (salt.at(r.end) == '$') {
            salt = salt.from(r.end + 1);
            const v = r.value orelse return null;
            if (v < sha_rounds_min or v > sha_rounds_max) return null;
            rounds = v;
            rounds_custom = true;
        }
    }

    const salt_len = @min(std.mem.indexOfScalar(u8, salt.s, '$') orelse salt.s.len, sha_salt_len_max);
    const s = salt.s[0..salt_len];
    const key = pw.s;

    var ctx = H.init(.{});
    ctx.update(key);
    ctx.update(s);

    var alt_result: [dl]u8 = undefined;
    var temp_result: [dl]u8 = undefined;
    var alt = H.init(.{});
    alt.update(key);
    alt.update(s);
    alt.update(key);
    alt.final(&alt_result);

    var cnt: usize = key.len;
    while (cnt > dl) : (cnt -= dl) ctx.update(&alt_result);
    ctx.update(alt_result[0..cnt]);

    cnt = key.len;
    while (cnt > 0) : (cnt >>= 1) {
        if (cnt & 1 != 0) ctx.update(&alt_result) else ctx.update(key);
    }
    ctx.final(&alt_result);

    // the p and s byte sequences are at most a password's and 16 bytes long;
    // the password can be long, so its sequence is built in place of key
    // repetitions: byte i of P is temp_result[i % dl]
    alt = H.init(.{});
    cnt = 0;
    while (cnt < key.len) : (cnt += 1) alt.update(key);
    alt.final(&temp_result);
    const p_digest = temp_result;

    alt = H.init(.{});
    cnt = 0;
    while (cnt < 16 + @as(usize, alt_result[0])) : (cnt += 1) alt.update(s);
    alt.final(&temp_result);
    var s_bytes: [sha_salt_len_max]u8 = undefined;
    for (0..salt_len) |i| s_bytes[i] = temp_result[i % dl];
    const sb = s_bytes[0..salt_len];

    var r: u64 = 0;
    while (r < rounds) : (r += 1) {
        ctx = H.init(.{});
        if (r & 1 != 0) updateRepeated(H, &ctx, &p_digest, key.len) else ctx.update(&alt_result);
        if (r % 3 != 0) ctx.update(sb);
        if (r % 7 != 0) updateRepeated(H, &ctx, &p_digest, key.len);
        if (r & 1 != 0) ctx.update(&alt_result) else updateRepeated(H, &ctx, &p_digest, key.len);
        ctx.final(&alt_result);
    }

    // the result string, with crypt_sha*.c's accounting of the 123-byte
    // buffer: a result that would fill it is a failure
    var buflen: isize = max_salt_len;
    var pos: usize = 0;
    @memcpy(buffer[0..3], prefix);
    pos = 3;
    buflen -= 3;
    if (rounds_custom) {
        const written = std.fmt.bufPrint(buffer[pos..], "rounds={d}$", .{rounds}) catch unreachable;
        pos += written.len;
        buflen -= @intCast(written.len);
    }
    const take: usize = @intCast(@min(@max(0, buflen), @as(isize, @intCast(salt_len))));
    @memcpy(buffer[pos .. pos + take], s[0..take]);
    pos += take;
    buflen -= @intCast(take);
    if (buflen > 0) {
        buffer[pos] = '$';
        pos += 1;
        buflen -= 1;
    }
    const a = alt_result;
    const W = struct {
        fn put(out: []u8, p: *usize, bl: *isize, b2: u8, b1: u8, b0: u8, n: usize) void {
            var w: u32 = (@as(u32, b2) << 16) | (@as(u32, b1) << 8) | b0;
            var k = n;
            while (k > 0 and bl.* > 0) : (k -= 1) {
                out[p.*] = itoa64[w & 0x3f];
                p.* += 1;
                bl.* -= 1;
                w >>= 6;
            }
        }
    };
    if (is512) {
        const order = [_][3]u8{
            .{ 0, 21, 42 },  .{ 22, 43, 1 },  .{ 44, 2, 23 },  .{ 3, 24, 45 },
            .{ 25, 46, 4 },  .{ 47, 5, 26 },  .{ 6, 27, 48 },  .{ 28, 49, 7 },
            .{ 50, 8, 29 },  .{ 9, 30, 51 },  .{ 31, 52, 10 }, .{ 53, 11, 32 },
            .{ 12, 33, 54 }, .{ 34, 55, 13 }, .{ 56, 14, 35 }, .{ 15, 36, 57 },
            .{ 37, 58, 16 }, .{ 59, 17, 38 }, .{ 18, 39, 60 }, .{ 40, 61, 19 },
            .{ 62, 20, 41 },
        };
        for (order) |o| W.put(buffer, &pos, &buflen, a[o[0]], a[o[1]], a[o[2]], 4);
        W.put(buffer, &pos, &buflen, 0, 0, a[63], 2);
    } else {
        const order = [_][3]u8{
            .{ 0, 10, 20 }, .{ 21, 1, 11 }, .{ 12, 22, 2 }, .{ 3, 13, 23 }, .{ 24, 4, 14 },
            .{ 15, 25, 5 }, .{ 6, 16, 26 }, .{ 27, 7, 17 }, .{ 18, 28, 8 }, .{ 9, 19, 29 },
        };
        for (order) |o| W.put(buffer, &pos, &buflen, a[o[0]], a[o[1]], a[o[2]], 4);
        W.put(buffer, &pos, &buflen, 0, a[31], a[30], 3);
    }
    if (buflen <= 0) return null;
    return buffer[0..pos];
}

// feeds the first `len` bytes of the P sequence (the digest repeated)
fn updateRepeated(comptime H: type, ctx: *H, digest: *const [H.digest_length]u8, len: usize) void {
    var left = len;
    while (left >= H.digest_length) : (left -= H.digest_length) ctx.update(digest);
    ctx.update(digest[0..left]);
}

// -------------------------------------------------------------------- bcrypt

const bf_itoa64 = "./ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
const bf_magic_w = [6]u32{ 0x4F727068, 0x65616E42, 0x65686F6C, 0x64657253, 0x63727944, 0x6F756274 };

fn bfAtoi64(c: u8) ?u6 {
    if (c < 0x20 or c >= 0x80) return null;
    return switch (c) {
        '.' => 0,
        '/' => 1,
        'A'...'Z' => @intCast(c - 'A' + 2),
        'a'...'z' => @intCast(c - 'a' + 28),
        '0'...'9' => @intCast(c - '0' + 54),
        else => null,
    };
}

// a = 2 (safety measure), b = 4, x = 1 (sign extension bug), y = 4
fn bfFlags(subtype: u8) u8 {
    return switch (subtype) {
        'a' => 2,
        'b', 'y' => 4,
        'x' => 1,
        else => 0,
    };
}

const BfCtx = struct {
    s: [4][256]u32,
    p: [18]u32,

    inline fn f(self: *const BfCtx, x: u32) u32 {
        var t = self.s[0][x >> 24] +% self.s[1][(x >> 16) & 0xff];
        t ^= self.s[2][(x >> 8) & 0xff];
        return t +% self.s[3][x & 0xff];
    }

    inline fn encrypt(self: *const BfCtx, l: *u32, r: *u32) void {
        var L = l.*;
        var R = r.*;
        L ^= self.p[0];
        var n: usize = 0;
        while (n < 16) : (n += 2) {
            R ^= self.p[n + 1] ^ self.f(L);
            L ^= self.p[n + 2] ^ self.f(R);
        }
        l.* = R ^ self.p[17];
        r.* = L;
    }

    fn body(self: *BfCtx) void {
        var L: u32 = 0;
        var R: u32 = 0;
        var i: usize = 0;
        while (i < 18) : (i += 2) {
            self.encrypt(&L, &R);
            self.p[i] = L;
            self.p[i + 1] = R;
        }
        const flat: *[1024]u32 = @ptrCast(&self.s);
        i = 0;
        while (i < 1024) : (i += 2) {
            self.encrypt(&L, &R);
            flat[i] = L;
            flat[i + 1] = R;
        }
    }
};

fn bfSetKey(key: CStr, expanded: *[18]u32, initial: *[18]u32, flags: u8) void {
    const bug: usize = flags & 1;
    const safety: u32 = @as(u32, flags & 2) << 15;
    var sign: u32 = 0;
    var diff: u32 = 0;
    var ptr: usize = 0;
    for (0..18) |i| {
        var tmp = [2]u32{ 0, 0 };
        for (0..4) |j| {
            const c = key.at(ptr);
            tmp[0] <<= 8;
            tmp[0] |= c;
            tmp[1] <<= 8;
            tmp[1] |= @bitCast(@as(i32, @as(i8, @bitCast(c))));
            if (j != 0) sign |= tmp[1] & 0x80;
            if (c == 0) ptr = 0 else ptr += 1;
        }
        diff |= tmp[0] ^ tmp[1];
        expanded[i] = tmp[bug];
        initial[i] = bf_tables.init_p[i] ^ tmp[bug];
    }
    diff |= diff >> 16;
    diff &= 0xffff;
    diff +%= 0xffff;
    sign <<= 9;
    sign &= ~diff & safety;
    initial[0] ^= sign;
}

fn bfCrypt(key: CStr, setting: CStr, out: []u8) ?[]const u8 {
    const sub = setting.at(2);
    if (setting.at(0) != '$' or setting.at(1) != '2' or sub < 'a' or sub > 'z' or bfFlags(sub) == 0 or
        setting.at(3) != '$' or setting.at(4) < '0' or setting.at(4) > '3' or
        setting.at(5) < '0' or setting.at(5) > '9' or (setting.at(4) == '3' and setting.at(5) > '1') or
        setting.at(6) != '$') return null;
    const log_rounds: u5 = @intCast((setting.at(4) - '0') * 10 + (setting.at(5) - '0'));
    var count: u32 = @as(u32, 1) << log_rounds;
    if (count < 16) return null;

    // BF_decode of 16 bytes from 22 characters
    var raw: [16]u8 = undefined;
    {
        var d: usize = 0;
        var sp: usize = 7;
        while (true) {
            const c1 = bfAtoi64(setting.at(sp)) orelse return null;
            const c2 = bfAtoi64(setting.at(sp + 1)) orelse return null;
            sp += 2;
            raw[d] = (@as(u8, c1) << 2) | ((@as(u8, c2) & 0x30) >> 4);
            d += 1;
            if (d >= 16) break;
            const c3 = bfAtoi64(setting.at(sp)) orelse return null;
            sp += 1;
            raw[d] = ((@as(u8, c2) & 0x0f) << 4) | ((@as(u8, c3) & 0x3c) >> 2);
            d += 1;
            if (d >= 16) break;
            const c4 = bfAtoi64(setting.at(sp)) orelse return null;
            sp += 1;
            raw[d] = ((@as(u8, c3) & 0x03) << 6) | c4;
            d += 1;
        }
    }
    var salt: [4]u32 = undefined;
    for (0..4) |i| salt[i] = std.mem.readInt(u32, raw[i * 4 ..][0..4], .big);

    var ctx: BfCtx = undefined;
    var expanded: [18]u32 = undefined;
    bfSetKey(key, &expanded, &ctx.p, bfFlags(sub));
    ctx.s = bf_tables.init_s;

    var L: u32 = 0;
    var R: u32 = 0;
    var i: usize = 0;
    while (i < 18) : (i += 2) {
        L ^= salt[i & 2];
        R ^= salt[(i & 2) + 1];
        ctx.encrypt(&L, &R);
        ctx.p[i] = L;
        ctx.p[i + 1] = R;
    }
    const flat: *[1024]u32 = @ptrCast(&ctx.s);
    i = 0;
    while (i < 1024) : (i += 4) {
        L ^= salt[2];
        R ^= salt[3];
        ctx.encrypt(&L, &R);
        flat[i] = L;
        flat[i + 1] = R;
        L ^= salt[0];
        R ^= salt[1];
        ctx.encrypt(&L, &R);
        flat[i + 2] = L;
        flat[i + 3] = R;
    }

    while (true) {
        for (0..18) |k| ctx.p[k] ^= expanded[k];
        ctx.body();
        for (0..16) |k| ctx.p[k] ^= salt[k & 3];
        ctx.p[16] ^= salt[0];
        ctx.p[17] ^= salt[1];
        ctx.body();
        count -= 1;
        if (count == 0) break;
    }

    var output: [6]u32 = undefined;
    i = 0;
    while (i < 6) : (i += 2) {
        L = bf_magic_w[i];
        R = bf_magic_w[i + 1];
        for (0..64) |_| ctx.encrypt(&L, &R);
        output[i] = L;
        output[i + 1] = R;
    }

    @memcpy(out[0..28], setting.s[0..28]);
    out[28] = bf_itoa64[@as(usize, bfAtoi64(setting.at(28)).?) & 0x30];
    var bytes: [24]u8 = undefined;
    for (0..6) |k| std.mem.writeInt(u32, bytes[k * 4 ..][0..4], output[k], .big);
    // bug-compatible with the original: only 23 of the 24 bytes are encoded
    var pos: usize = 29;
    var sp: usize = 0;
    while (sp < 23) {
        var c1: u8 = bytes[sp];
        sp += 1;
        out[pos] = bf_itoa64[c1 >> 2];
        pos += 1;
        c1 = (c1 & 0x03) << 4;
        if (sp >= 23) {
            out[pos] = bf_itoa64[c1];
            pos += 1;
            break;
        }
        var c2 = bytes[sp];
        sp += 1;
        c1 |= c2 >> 4;
        out[pos] = bf_itoa64[c1];
        pos += 1;
        c1 = (c2 & 0x0f) << 2;
        if (sp >= 23) {
            out[pos] = bf_itoa64[c1];
            pos += 1;
            break;
        }
        c2 = bytes[sp];
        sp += 1;
        c1 |= c2 >> 6;
        out[pos] = bf_itoa64[c1];
        out[pos + 1] = bf_itoa64[c2 & 0x3f];
        pos += 2;
    }
    std.crypto.secureZero(u32, &ctx.p);
    std.crypto.secureZero(u32, &expanded);
    return out[0..pos];
}

// ----------------------------------------------------------------------- DES

const des = struct {
    const ip = [64]u8{
        58, 50, 42, 34, 26, 18, 10, 2, 60, 52, 44, 36, 28, 20, 12, 4,
        62, 54, 46, 38, 30, 22, 14, 6, 64, 56, 48, 40, 32, 24, 16, 8,
        57, 49, 41, 33, 25, 17, 9,  1, 59, 51, 43, 35, 27, 19, 11, 3,
        61, 53, 45, 37, 29, 21, 13, 5, 63, 55, 47, 39, 31, 23, 15, 7,
    };
    const key_perm = [56]u8{
        57, 49, 41, 33, 25, 17, 9,  1,  58, 50, 42, 34, 26, 18,
        10, 2,  59, 51, 43, 35, 27, 19, 11, 3,  60, 52, 44, 36,
        63, 55, 47, 39, 31, 23, 15, 7,  62, 54, 46, 38, 30, 22,
        14, 6,  61, 53, 45, 37, 29, 21, 13, 5,  28, 20, 12, 4,
    };
    const key_shifts = [16]u8{ 1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1 };
    const comp_perm = [48]u8{
        14, 17, 11, 24, 1,  5,  3,  28, 15, 6,  21, 10,
        23, 19, 12, 4,  26, 8,  16, 7,  27, 20, 13, 2,
        41, 52, 31, 37, 47, 55, 30, 40, 51, 45, 33, 48,
        44, 49, 39, 56, 34, 53, 46, 42, 50, 36, 29, 32,
    };
    const sbox = [8][64]u8{
        .{ 14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7, 0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8, 4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0, 15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13 },
        .{ 15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10, 3, 13, 4, 7, 15, 2, 8, 14, 12, 0, 1, 10, 6, 9, 11, 5, 0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15, 13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9 },
        .{ 10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8, 13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1, 13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7, 1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12 },
        .{ 7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15, 13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9, 10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4, 3, 15, 0, 6, 10, 1, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14 },
        .{ 2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9, 14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15, 10, 3, 9, 8, 6, 4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14, 11, 8, 12, 7, 1, 14, 2, 13, 6, 15, 0, 9, 10, 4, 5, 3 },
        .{ 12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11, 10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13, 14, 0, 11, 3, 8, 9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6, 4, 3, 2, 12, 9, 5, 15, 10, 11, 14, 1, 7, 6, 0, 8, 13 },
        .{ 4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1, 13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5, 12, 2, 15, 8, 6, 1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2, 6, 11, 13, 8, 1, 4, 10, 7, 9, 5, 0, 15, 14, 2, 3, 12 },
        .{ 13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7, 1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6, 11, 0, 14, 9, 2, 7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8, 2, 1, 14, 7, 4, 10, 8, 13, 15, 12, 9, 0, 3, 5, 6, 11 },
    };
    const pbox = [32]u8{ 16, 7, 20, 21, 29, 12, 28, 17, 1, 15, 23, 26, 5, 18, 31, 10, 2, 8, 24, 14, 32, 27, 3, 9, 19, 13, 30, 6, 22, 11, 4, 25 };
    const ascii64 = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

    fn bits32(i: usize) u32 {
        return @as(u32, 0x80000000) >> @intCast(i);
    }
    fn bits8(i: usize) u8 {
        return @as(u8, 0x80) >> @intCast(i);
    }

    // _crypt_extended_init's lookup tables, built at compile time
    const Tables = struct {
        m_sbox: [4][4096]u8,
        psbox: [4][256]u32,
        ip_maskl: [8][256]u32,
        ip_maskr: [8][256]u32,
        fp_maskl: [8][256]u32,
        fp_maskr: [8][256]u32,
        key_perm_maskl: [8][128]u32,
        key_perm_maskr: [8][128]u32,
        comp_maskl: [8][128]u32,
        comp_maskr: [8][128]u32,
    };

    const tables: Tables = blk: {
        @setEvalBranchQuota(10_000_000);
        var t: Tables = undefined;
        var u_sbox: [8][64]u8 = undefined;
        for (0..8) |i| {
            for (0..64) |j| {
                const b = (j & 0x20) | ((j & 1) << 4) | ((j >> 1) & 0xf);
                u_sbox[i][j] = sbox[i][b];
            }
        }
        for (0..4) |b| {
            for (0..64) |i| {
                for (0..64) |j| {
                    t.m_sbox[b][(i << 6) | j] = (u_sbox[b << 1][i] << 4) | u_sbox[(b << 1) + 1][j];
                }
            }
        }
        var init_perm: [64]u8 = undefined;
        var final_perm: [64]u8 = undefined;
        var inv_key_perm: [64]u8 = undefined;
        var inv_comp_perm: [56]u8 = undefined;
        for (0..64) |i| {
            final_perm[i] = ip[i] - 1;
            init_perm[final_perm[i]] = i;
            inv_key_perm[i] = 255;
        }
        for (0..56) |i| {
            inv_key_perm[key_perm[i] - 1] = i;
            inv_comp_perm[i] = 255;
        }
        for (0..48) |i| inv_comp_perm[comp_perm[i] - 1] = i;
        for (0..8) |k| {
            for (0..256) |i| {
                var il: u32 = 0;
                var ir: u32 = 0;
                var fl: u32 = 0;
                var fr: u32 = 0;
                for (0..8) |j| {
                    const inbit = 8 * k + j;
                    if (i & bits8(j) != 0) {
                        const o1: usize = init_perm[inbit];
                        if (o1 < 32) il |= bits32(o1) else ir |= bits32(o1 - 32);
                        const o2: usize = final_perm[inbit];
                        if (o2 < 32) fl |= bits32(o2) else fr |= bits32(o2 - 32);
                    }
                }
                t.ip_maskl[k][i] = il;
                t.ip_maskr[k][i] = ir;
                t.fp_maskl[k][i] = fl;
                t.fp_maskr[k][i] = fr;
            }
            for (0..128) |i| {
                var il: u32 = 0;
                var ir: u32 = 0;
                for (0..7) |j| {
                    const inbit = 8 * k + j;
                    if (i & bits8(j + 1) != 0) {
                        const obit: usize = inv_key_perm[inbit];
                        if (obit == 255) continue;
                        if (obit < 28) il |= bits32(obit + 4) else ir |= bits32(obit - 28 + 4);
                    }
                }
                t.key_perm_maskl[k][i] = il;
                t.key_perm_maskr[k][i] = ir;
                il = 0;
                ir = 0;
                for (0..7) |j| {
                    const inbit = 7 * k + j;
                    if (i & bits8(j + 1) != 0) {
                        const obit: usize = inv_comp_perm[inbit];
                        if (obit == 255) continue;
                        if (obit < 24) il |= bits32(obit + 8) else ir |= bits32(obit - 24 + 8);
                    }
                }
                t.comp_maskl[k][i] = il;
                t.comp_maskr[k][i] = ir;
            }
        }
        var un_pbox: [32]u8 = undefined;
        for (0..32) |i| un_pbox[pbox[i] - 1] = i;
        for (0..4) |b| {
            for (0..256) |i| {
                var p: u32 = 0;
                for (0..8) |j| {
                    if (i & bits8(j) != 0) p |= bits32(un_pbox[8 * b + j]);
                }
                t.psbox[b][i] = p;
            }
        }
        break :blk t;
    };

    const State = struct {
        saltbits: u32 = 0,
        en_keysl: [16]u32 = undefined,
        en_keysr: [16]u32 = undefined,

        fn setupSalt(self: *State, salt: u32) void {
            var saltbits: u32 = 0;
            var saltbit: u32 = 1;
            var obit: u32 = 0x800000;
            for (0..24) |_| {
                if (salt & saltbit != 0) saltbits |= obit;
                saltbit <<= 1;
                obit >>= 1;
            }
            self.saltbits = saltbits;
        }

        fn setKey(self: *State, key: *const [8]u8) void {
            const T = &tables;
            const rawkey0 = std.mem.readInt(u32, key[0..4], .big);
            const rawkey1 = std.mem.readInt(u32, key[4..8], .big);
            const k0 = T.key_perm_maskl[0][rawkey0 >> 25] | T.key_perm_maskl[1][(rawkey0 >> 17) & 0x7f] |
                T.key_perm_maskl[2][(rawkey0 >> 9) & 0x7f] | T.key_perm_maskl[3][(rawkey0 >> 1) & 0x7f] |
                T.key_perm_maskl[4][rawkey1 >> 25] | T.key_perm_maskl[5][(rawkey1 >> 17) & 0x7f] |
                T.key_perm_maskl[6][(rawkey1 >> 9) & 0x7f] | T.key_perm_maskl[7][(rawkey1 >> 1) & 0x7f];
            const k1 = T.key_perm_maskr[0][rawkey0 >> 25] | T.key_perm_maskr[1][(rawkey0 >> 17) & 0x7f] |
                T.key_perm_maskr[2][(rawkey0 >> 9) & 0x7f] | T.key_perm_maskr[3][(rawkey0 >> 1) & 0x7f] |
                T.key_perm_maskr[4][rawkey1 >> 25] | T.key_perm_maskr[5][(rawkey1 >> 17) & 0x7f] |
                T.key_perm_maskr[6][(rawkey1 >> 9) & 0x7f] | T.key_perm_maskr[7][(rawkey1 >> 1) & 0x7f];
            var shifts: u5 = 0;
            for (0..16) |round| {
                shifts += @intCast(key_shifts[round]);
                const t0 = (k0 << shifts) | (k0 >> @intCast(@as(u6, 28) - shifts));
                const t1 = (k1 << shifts) | (k1 >> @intCast(@as(u6, 28) - shifts));
                self.en_keysl[round] = T.comp_maskl[0][(t0 >> 21) & 0x7f] | T.comp_maskl[1][(t0 >> 14) & 0x7f] |
                    T.comp_maskl[2][(t0 >> 7) & 0x7f] | T.comp_maskl[3][t0 & 0x7f] |
                    T.comp_maskl[4][(t1 >> 21) & 0x7f] | T.comp_maskl[5][(t1 >> 14) & 0x7f] |
                    T.comp_maskl[6][(t1 >> 7) & 0x7f] | T.comp_maskl[7][t1 & 0x7f];
                self.en_keysr[round] = T.comp_maskr[0][(t0 >> 21) & 0x7f] | T.comp_maskr[1][(t0 >> 14) & 0x7f] |
                    T.comp_maskr[2][(t0 >> 7) & 0x7f] | T.comp_maskr[3][t0 & 0x7f] |
                    T.comp_maskr[4][(t1 >> 21) & 0x7f] | T.comp_maskr[5][(t1 >> 14) & 0x7f] |
                    T.comp_maskr[6][(t1 >> 7) & 0x7f] | T.comp_maskr[7][t1 & 0x7f];
            }
        }

        fn doDes(self: *const State, l_in: u32, r_in: u32, count_in: u32) [2]u32 {
            const T = &tables;
            var l = T.ip_maskl[0][l_in >> 24] | T.ip_maskl[1][(l_in >> 16) & 0xff] |
                T.ip_maskl[2][(l_in >> 8) & 0xff] | T.ip_maskl[3][l_in & 0xff] |
                T.ip_maskl[4][r_in >> 24] | T.ip_maskl[5][(r_in >> 16) & 0xff] |
                T.ip_maskl[6][(r_in >> 8) & 0xff] | T.ip_maskl[7][r_in & 0xff];
            var r = T.ip_maskr[0][l_in >> 24] | T.ip_maskr[1][(l_in >> 16) & 0xff] |
                T.ip_maskr[2][(l_in >> 8) & 0xff] | T.ip_maskr[3][l_in & 0xff] |
                T.ip_maskr[4][r_in >> 24] | T.ip_maskr[5][(r_in >> 16) & 0xff] |
                T.ip_maskr[6][(r_in >> 8) & 0xff] | T.ip_maskr[7][r_in & 0xff];
            const saltbits = self.saltbits;
            var f: u32 = 0;
            var count = count_in;
            while (count > 0) : (count -= 1) {
                for (0..16) |k| {
                    var r48l = ((r & 0x00000001) << 23) | ((r & 0xf8000000) >> 9) |
                        ((r & 0x1f800000) >> 11) | ((r & 0x01f80000) >> 13) | ((r & 0x001f8000) >> 15);
                    var r48r = ((r & 0x0001f800) << 7) | ((r & 0x00001f80) << 5) |
                        ((r & 0x000001f8) << 3) | ((r & 0x0000001f) << 1) | ((r & 0x80000000) >> 31);
                    f = (r48l ^ r48r) & saltbits;
                    r48l ^= f ^ self.en_keysl[k];
                    r48r ^= f ^ self.en_keysr[k];
                    f = T.psbox[0][T.m_sbox[0][r48l >> 12]] | T.psbox[1][T.m_sbox[1][r48l & 0xfff]] |
                        T.psbox[2][T.m_sbox[2][r48r >> 12]] | T.psbox[3][T.m_sbox[3][r48r & 0xfff]];
                    f ^= l;
                    l = r;
                    r = f;
                }
                r = l;
                l = f;
            }
            const lo = T.fp_maskl[0][l >> 24] | T.fp_maskl[1][(l >> 16) & 0xff] |
                T.fp_maskl[2][(l >> 8) & 0xff] | T.fp_maskl[3][l & 0xff] |
                T.fp_maskl[4][r >> 24] | T.fp_maskl[5][(r >> 16) & 0xff] |
                T.fp_maskl[6][(r >> 8) & 0xff] | T.fp_maskl[7][r & 0xff];
            const ro = T.fp_maskr[0][l >> 24] | T.fp_maskr[1][(l >> 16) & 0xff] |
                T.fp_maskr[2][(l >> 8) & 0xff] | T.fp_maskr[3][l & 0xff] |
                T.fp_maskr[4][r >> 24] | T.fp_maskr[5][(r >> 16) & 0xff] |
                T.fp_maskr[6][(r >> 8) & 0xff] | T.fp_maskr[7][r & 0xff];
            return .{ lo, ro };
        }
    };

    fn asciiToBin(ch: u8) u32 {
        const sch: i32 = @as(i8, @bitCast(ch));
        var retval: i32 = sch - '.';
        if (sch >= 'A') {
            retval = sch - ('A' - 12);
            if (sch >= 'a') retval = sch - ('a' - 38);
        }
        return @intCast(retval & 0x3f);
    }

    fn asciiIsUnsafe(ch: u8) bool {
        return ch == 0 or ch == '\n' or ch == ':';
    }
};

fn desCrypt(key: CStr, setting: CStr, out: []u8) ?[]const u8 {
    var st: des.State = .{};
    var keybuf: [8]u8 = undefined;
    var kp: usize = 0;
    for (0..8) |q| {
        keybuf[q] = key.at(kp) << 1;
        if (key.at(kp) != 0) kp += 1;
    }
    st.setKey(&keybuf);

    var count: u32 = undefined;
    var salt: u32 = 0;
    var pos: usize = undefined;
    if (setting.at(0) == '_') {
        count = 0;
        for (1..5) |i| {
            const value = des.asciiToBin(setting.at(i));
            if (des.ascii64[value] != setting.at(i)) return null;
            count |= value << @intCast((i - 1) * 6);
        }
        if (count == 0) return null;
        for (5..9) |i| {
            const value = des.asciiToBin(setting.at(i));
            if (des.ascii64[value] != setting.at(i)) return null;
            salt |= value << @intCast((i - 5) * 6);
        }
        while (key.at(kp) != 0) {
            // encrypt the key with itself, then xor in the next 8 characters
            st.setupSalt(0);
            const r = st.doDes(std.mem.readInt(u32, keybuf[0..4], .big), std.mem.readInt(u32, keybuf[4..8], .big), 1);
            std.mem.writeInt(u32, keybuf[0..4], r[0], .big);
            std.mem.writeInt(u32, keybuf[4..8], r[1], .big);
            var q: usize = 0;
            while (q < 8 and key.at(kp) != 0) : (q += 1) {
                keybuf[q] ^= key.at(kp) << 1;
                kp += 1;
            }
            st.setKey(&keybuf);
        }
        @memcpy(out[0..9], setting.s[0..9]);
        pos = 9;
    } else {
        count = 25;
        if (des.asciiIsUnsafe(setting.at(0)) or des.asciiIsUnsafe(setting.at(1))) return null;
        salt = (des.asciiToBin(setting.at(1)) << 6) | des.asciiToBin(setting.at(0));
        out[0] = setting.at(0);
        out[1] = setting.at(1);
        pos = 2;
    }
    st.setupSalt(salt);
    const res = st.doDes(0, 0, count);
    const r0 = res[0];
    const r1 = res[1];
    var l: u32 = r0 >> 8;
    const a = des.ascii64;
    out[pos + 0] = a[(l >> 18) & 0x3f];
    out[pos + 1] = a[(l >> 12) & 0x3f];
    out[pos + 2] = a[(l >> 6) & 0x3f];
    out[pos + 3] = a[l & 0x3f];
    l = (r0 << 16) | ((r1 >> 16) & 0xffff);
    out[pos + 4] = a[(l >> 18) & 0x3f];
    out[pos + 5] = a[(l >> 12) & 0x3f];
    out[pos + 6] = a[(l >> 6) & 0x3f];
    out[pos + 7] = a[l & 0x3f];
    l = r1 << 2;
    out[pos + 8] = a[(l >> 12) & 0x3f];
    out[pos + 9] = a[(l >> 6) & 0x3f];
    out[pos + 10] = a[l & 0x3f];
    std.crypto.secureZero(u32, &st.en_keysl);
    std.crypto.secureZero(u32, &st.en_keysr);
    return out[0 .. pos + 11];
}

fn testCrypt(pw: []const u8, salt: []const u8) !?[]u8 {
    return phpCrypt(std.testing.allocator, pw, salt);
}

test "crypt_freesec self test vectors" {
    const cases = [_][2][]const u8{
        .{ "_J9..CCCCXBrJUJV154M", "U*U*U*U*" },
        .{ "_J9..CCCCXUhOBTXzaiE", "U*U***U" },
        .{ "_J9..XXXXVL7qJCnku0I", "*U*U*U*U*U*U*U*U" },
        .{ "_J9..SDizxmRI1GjnQuE", "zxyDPWgydbQjgq" },
        .{ "_K9..SaltNrQgIYUAeoY", "726 even" },
        .{ "_J9..SDSD5YGyRCr4W4c", "" },
        .{ "CCNf8Sbh3HDfQ", "U*U*U*U*" },
        .{ "SDbsugeBiC58A", "" },
        .{ "./xZjzHv5vzVE", "password" },
        .{ "zZDDIZ0NOlPzw", "password" },
    };
    for (cases) |c| {
        const r = (try testCrypt(c[1], c[0])).?;
        defer std.testing.allocator.free(r);
        try std.testing.expectEqualStrings(c[0], r);
    }
    try std.testing.expect((try testCrypt("", "_........")) == null);
    try std.testing.expect((try testCrypt("", "_/!......")) == null);
}

test "crypt_blowfish self test" {
    const r = (try testCrypt("8b \xd0\xc1\xd2\xcf\xcc\xd8", "$2a$05$abcdefghijklmnopqrstuu")).?;
    defer std.testing.allocator.free(r);
    try std.testing.expect(r.len == 60);
    const x = (try testCrypt("U*U", "$2a$05$CCCCCCCCCCCCCCCCCCCCC.")).?;
    defer std.testing.allocator.free(x);
    try std.testing.expectEqualStrings("$2a$05$CCCCCCCCCCCCCCCCCCCCC.E5YPO9kmyuRGyh0XouQYb4YMJKvyOeW", x);
}

test "sha and md5 crypt" {
    const a = (try testCrypt("Hello world!", "$5$saltstring")).?;
    defer std.testing.allocator.free(a);
    try std.testing.expectEqualStrings("$5$saltstring$5B8vYYiY.CVt1RlTTf8KbXBH3hsxY/GNooZaBBGWEc5", a);
    const b = (try testCrypt("Hello world!", "$6$saltstring")).?;
    defer std.testing.allocator.free(b);
    try std.testing.expectEqualStrings("$6$saltstring$svn8UoSVapNtMuq1ukKS4tPQd8iKwSMHWjl/O817G3uBnIFNjnQJuesI68u4OTLiBFdcbYEdFCoEOfaS35inz1", b);
    const c = (try testCrypt("rasmuslerdorf", "$1$rasmusle$")).?;
    defer std.testing.allocator.free(c);
    try std.testing.expectEqualStrings("$1$rasmusle$rISCgZzpwk3UhDidwXvin0", c);
}
