// the hash algorithms of php's ext/hash, ported with php's context layouts:
// HashContext serializes a context field by field (php_hash_serialize_spec),
// so every context here is an extern struct shaped as php's C struct, and
// update and final keep php's bookkeeping (which bytes of a buffer are
// rewritten, what a final leaves behind)
const std = @import("std");
const tables = @import("hash_tables_generated.zig");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const PhpArray = value_mod.PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

const rotl = std.math.rotl;
const rotr = std.math.rotr;

// what an algorithm's init gets: the $options array hash(), hash_file(),
// hash_init() and hash_pbkdf2() were given (null when the call passed
// none), and the call, for the deprecations and errors seeds and secrets
// raise
pub const InitArgs = struct {
    ctx: ?*NativeContext = null,
    options: ?*PhpArray = null,
    // the function name php_error_docref puts before a message
    func: []const u8 = "",
};

pub const Ops = struct {
    name: []const u8,
    digest_size: usize,
    block_size: usize,
    context_size: usize,
    is_crypto: bool,
    // php_hash_serialize_spec's layout; null when the context can't be
    // serialized
    spec: ?[]const u8,
    magic: i64 = spec_magic,
    init: *const fn (*anyopaque, InitArgs) RuntimeError!void,
    update: *const fn (*anyopaque, []const u8) void,
    final: *const fn ([]u8, *anyopaque) void,
    // checks an unserialized context can be used safely
    valid: ?*const fn (*anyopaque) bool = null,
    // completes a copied context (memcpy'd from src)
    fixup_copy: ?*const fn (dst: *anyopaque, src: *const anyopaque) void = null,
};

pub const spec_magic: i64 = 2;
pub const keccak_magic: i64 = 100;

// the largest context (xxh3 with its secret) and php's widest alignment
pub const max_context_size = 832;
pub const max_digest_size = 64;
pub const max_block_size = 144;
pub const context_align = 64;

fn opsFor(comptime A: type, comptime meta: struct {
    name: []const u8,
    digest: usize,
    block: usize,
    crypto: bool,
    spec: ?[]const u8,
    magic: i64 = spec_magic,
}) Ops {
    const W = struct {
        fn init(p: *anyopaque, a: InitArgs) RuntimeError!void {
            return A.init(@ptrCast(@alignCast(p)), a);
        }
        fn update(p: *anyopaque, data: []const u8) void {
            A.update(@ptrCast(@alignCast(p)), data);
        }
        fn final(out: []u8, p: *anyopaque) void {
            A.final(out, @ptrCast(@alignCast(p)));
        }
        fn valid(p: *anyopaque) bool {
            return A.valid(@ptrCast(@alignCast(p)));
        }
        fn fixup(dst: *anyopaque, src: *const anyopaque) void {
            A.fixupCopy(@ptrCast(@alignCast(dst)), @ptrCast(@alignCast(src)));
        }
    };
    comptime std.debug.assert(@sizeOf(A.Ctx) <= max_context_size);
    comptime std.debug.assert(@alignOf(A.Ctx) <= context_align);
    return .{
        .name = meta.name,
        .digest_size = meta.digest,
        .block_size = meta.block,
        .context_size = @sizeOf(A.Ctx),
        .is_crypto = meta.crypto,
        .spec = meta.spec,
        .magic = meta.magic,
        .init = W.init,
        .update = W.update,
        .final = W.final,
        .valid = if (@hasDecl(A, "valid")) W.valid else null,
        .fixup_copy = if (@hasDecl(A, "fixupCopy")) W.fixup else null,
    };
}

// php's algorithm table, in php's registration order (hash_algos() lists
// it so); "snefru256" is another name for snefru's ops
pub const registry = [_]struct { []const u8, *const Ops }{
    .{ "md2", &md2_ops },
    .{ "md4", &md4_ops },
    .{ "md5", &md5_ops },
    .{ "sha1", &sha1_ops },
    .{ "sha224", &sha224_ops },
    .{ "sha256", &sha256_ops },
    .{ "sha384", &sha384_ops },
    .{ "sha512/224", &sha512_224_ops },
    .{ "sha512/256", &sha512_256_ops },
    .{ "sha512", &sha512_ops },
    .{ "sha3-224", &sha3_224_ops },
    .{ "sha3-256", &sha3_256_ops },
    .{ "sha3-384", &sha3_384_ops },
    .{ "sha3-512", &sha3_512_ops },
    .{ "ripemd128", &ripemd128_ops },
    .{ "ripemd160", &ripemd160_ops },
    .{ "ripemd256", &ripemd256_ops },
    .{ "ripemd320", &ripemd320_ops },
    .{ "whirlpool", &whirlpool_ops },
    .{ "tiger128,3", &tiger3_128_ops },
    .{ "tiger160,3", &tiger3_160_ops },
    .{ "tiger192,3", &tiger3_192_ops },
    .{ "tiger128,4", &tiger4_128_ops },
    .{ "tiger160,4", &tiger4_160_ops },
    .{ "tiger192,4", &tiger4_192_ops },
    .{ "snefru", &snefru_ops },
    .{ "snefru256", &snefru_ops },
    .{ "gost", &gost_ops },
    .{ "gost-crypto", &gost_crypto_ops },
    .{ "adler32", &adler32_ops },
    .{ "crc32", &crc32_ops },
    .{ "crc32b", &crc32b_ops },
    .{ "crc32c", &crc32c_ops },
    .{ "fnv132", &fnv132_ops },
    .{ "fnv1a32", &fnv1a32_ops },
    .{ "fnv164", &fnv164_ops },
    .{ "fnv1a64", &fnv1a64_ops },
    .{ "joaat", &joaat_ops },
    .{ "murmur3a", &murmur3a_ops },
    .{ "murmur3c", &murmur3c_ops },
    .{ "murmur3f", &murmur3f_ops },
    .{ "xxh32", &xxh32_ops },
    .{ "xxh64", &xxh64_ops },
    .{ "xxh3", &xxh3_ops },
    .{ "xxh128", &xxh128_ops },
    .{ "haval128,3", &haval_ops[0] },
    .{ "haval160,3", &haval_ops[1] },
    .{ "haval192,3", &haval_ops[2] },
    .{ "haval224,3", &haval_ops[3] },
    .{ "haval256,3", &haval_ops[4] },
    .{ "haval128,4", &haval_ops[5] },
    .{ "haval160,4", &haval_ops[6] },
    .{ "haval192,4", &haval_ops[7] },
    .{ "haval224,4", &haval_ops[8] },
    .{ "haval256,4", &haval_ops[9] },
    .{ "haval128,5", &haval_ops[10] },
    .{ "haval160,5", &haval_ops[11] },
    .{ "haval192,5", &haval_ops[12] },
    .{ "haval224,5", &haval_ops[13] },
    .{ "haval256,5", &haval_ops[14] },
};

const lookup = std.StaticStringMap(*const Ops).initComptime(registry);

// php_hash_fetch_ops: names are matched in lowercase
pub fn fetch(name: []const u8) ?*const Ops {
    if (name.len > 16) return null;
    var buf: [16]u8 = undefined;
    return lookup.get(std.ascii.lowerString(&buf, name));
}

// ---------------------------------------------------------------------------
// helpers shared by the md-style hashes

const padding = [_]u8{0x80} ++ @as([127]u8, @splat(0));

// php's bit-count bookkeeping for a 64- or 128-byte block hash: count[0..1]
// is the message length in bits, the buffer keeps the bytes of a partial
// block and only those bytes are rewritten
fn mdUpdate(comptime W: type, comptime block: usize, c: anytype, input: []const u8, comptime transform: anytype) void {
    var index: usize = undefined;
    if (W == u32) {
        index = (c.count[0] >> 3) & (block - 1);
        const add: u32 = @as(u32, @truncate(input.len)) << 3;
        c.count[0] +%= add;
        if (c.count[0] < add) c.count[1] +%= 1;
        c.count[1] +%= @truncate(input.len >> 29);
    } else {
        index = @intCast((c.count[0] >> 3) & (block - 1));
        const add: u64 = @as(u64, input.len) << 3;
        c.count[0] +%= add;
        if (c.count[0] < add) c.count[1] +%= 1;
        c.count[1] +%= @as(u64, input.len) >> 61;
    }
    const part = block - index;
    var i: usize = 0;
    if (input.len >= part) {
        @memcpy(c.buffer[index..][0..part], input[0..part]);
        transform(c, &c.buffer);
        i = part;
        while (i + block - 1 < input.len) : (i += block) transform(c, input[i..][0..block]);
        index = 0;
    }
    @memcpy(c.buffer[index..][0 .. input.len - i], input[i..]);
}

fn decodeLe(comptime n: usize, block: *const [n * 4]u8) [n]u32 {
    var x: [n]u32 = undefined;
    for (0..n) |k| x[k] = std.mem.readInt(u32, block[k * 4 ..][0..4], .little);
    return x;
}

fn encodeLe(out: []u8, words: []const u32) void {
    for (0..out.len / 4) |k| std.mem.writeInt(u32, out[k * 4 ..][0..4], words[k], .little);
}

fn encodeBe(out: []u8, words: []const u32) void {
    for (0..out.len / 4) |k| std.mem.writeInt(u32, out[k * 4 ..][0..4], words[k], .big);
}

fn countLe(count: [2]u32) [8]u8 {
    var bits: [8]u8 = undefined;
    std.mem.writeInt(u32, bits[0..4], count[0], .little);
    std.mem.writeInt(u32, bits[4..8], count[1], .little);
    return bits;
}

fn countBe(count: [2]u32) [8]u8 {
    var bits: [8]u8 = undefined;
    std.mem.writeInt(u32, bits[0..4], count[1], .big);
    std.mem.writeInt(u32, bits[4..8], count[0], .big);
    return bits;
}

fn padLen(count0: anytype, comptime block: usize, comptime tail: usize) usize {
    const index: usize = @intCast((count0 >> 3) & (block - 1));
    return if (index < block - tail) block - tail - index else 2 * block - tail - index;
}

fn wipe(c: anytype) void {
    std.crypto.secureZero(u8, std.mem.asBytes(c));
}

// ---------------------------------------------------------------------------
// md2, md4, md5 (ext/hash/hash_md.c, ext/standard/md5.c)

const Md2 = struct {
    const Ctx = extern struct { state: [48]u8, checksum: [16]u8, buffer: [16]u8, in_buffer: u8 };

    fn init(c: *Ctx, _: InitArgs) RuntimeError!void {
        c.* = std.mem.zeroes(Ctx);
    }

    fn transform(c: *Ctx, block: *const [16]u8) void {
        for (0..16) |i| {
            c.state[16 + i] = block[i];
            c.state[32 + i] = c.state[16 + i] ^ c.state[i];
        }
        var t: u8 = 0;
        for (0..18) |i| {
            for (0..48) |j| {
                c.state[j] ^= tables.md2_s[t];
                t = c.state[j];
            }
            t +%= @intCast(i);
        }
        t = c.checksum[15];
        for (0..16) |i| {
            c.checksum[i] ^= tables.md2_s[block[i] ^ t];
            t = c.checksum[i];
        }
    }

    fn update(c: *Ctx, buf: []const u8) void {
        var p: usize = 0;
        if (c.in_buffer != 0) {
            const have: usize = c.in_buffer;
            if (have + buf.len < 16) {
                @memcpy(c.buffer[have..][0..buf.len], buf);
                c.in_buffer +%= @truncate(buf.len);
                return;
            }
            @memcpy(c.buffer[have..16], buf[0 .. 16 - have]);
            transform(c, &c.buffer);
            p = 16 - have;
            c.in_buffer = 0;
        }
        while (p + 16 <= buf.len) : (p += 16) transform(c, buf[p..][0..16]);
        if (p < buf.len) {
            @memcpy(c.buffer[0 .. buf.len - p], buf[p..]);
            c.in_buffer = @truncate(buf.len - p);
        }
    }

    fn final(out: []u8, c: *Ctx) void {
        const have: usize = c.in_buffer;
        @memset(c.buffer[have..], @intCast(16 - have));
        transform(c, &c.buffer);
        const sum = c.checksum;
        transform(c, &sum);
        @memcpy(out[0..16], c.state[0..16]);
    }

    pub fn valid(c: *Ctx) bool {
        return c.in_buffer < 16;
    }
};

const Md4 = struct {
    const Ctx = extern struct { state: [4]u32, count: [2]u32, buffer: [64]u8 };

    fn init(c: *Ctx, _: InitArgs) RuntimeError!void {
        c.count = .{ 0, 0 };
        c.state = .{ 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476 };
    }

    fn transform(c: *Ctx, block: *const [64]u8) void {
        const x = decodeLe(16, block);
        var s = c.state;
        const r1 = [4]u5{ 3, 7, 11, 19 };
        const r2 = [4]u5{ 3, 5, 9, 13 };
        const r3 = [4]u5{ 3, 9, 11, 15 };
        const o3 = [16]u8{ 0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15 };
        inline for (0..16) |i| {
            const a = (4 - i % 4) % 4;
            const f = s[(a + 3) % 4] ^ (s[(a + 1) % 4] & (s[(a + 2) % 4] ^ s[(a + 3) % 4]));
            s[a] = rotl(u32, s[a] +% f +% x[i], r1[i % 4]);
        }
        inline for (0..16) |i| {
            const a = (4 - i % 4) % 4;
            const b = s[(a + 1) % 4];
            const cc = s[(a + 2) % 4];
            const d = s[(a + 3) % 4];
            const g = (b & (cc | d)) | (cc & d);
            s[a] = rotl(u32, s[a] +% g +% x[(i % 4) * 4 + i / 4] +% 0x5A827999, r2[i % 4]);
        }
        inline for (0..16) |i| {
            const a = (4 - i % 4) % 4;
            const h = s[(a + 1) % 4] ^ s[(a + 2) % 4] ^ s[(a + 3) % 4];
            s[a] = rotl(u32, s[a] +% h +% x[o3[i]] +% 0x6ED9EBA1, r3[i % 4]);
        }
        for (0..4) |i| c.state[i] +%= s[i];
    }

    fn update(c: *Ctx, input: []const u8) void {
        mdUpdate(u32, 64, c, input, transform);
    }

    fn final(out: []u8, c: *Ctx) void {
        const bits = countLe(c.count);
        update(c, padding[0..padLen(c.count[0], 64, 8)]);
        update(c, &bits);
        encodeLe(out[0..16], &c.state);
        wipe(c);
    }
};

const Md5 = struct {
    const Ctx = extern struct { lo: u32, hi: u32, a: u32, b: u32, c: u32, d: u32, buffer: [64]u8, block: [16]u32 };

    const k = [64]u32{
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
        0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
        0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
        0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
        0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
        0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
        0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
    };
    const shifts = [16]u5{ 7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21 };

    fn init(c: *Ctx, _: InitArgs) RuntimeError!void {
        c.a = 0x67452301;
        c.b = 0xefcdab89;
        c.c = 0x98badcfe;
        c.d = 0x10325476;
        c.lo = 0;
        c.hi = 0;
    }

    fn body(c: *Ctx, data: []const u8) void {
        var p: usize = 0;
        while (p < data.len) : (p += 64) {
            const x = decodeLe(16, data[p..][0..64]);
            var s = [4]u32{ c.a, c.b, c.c, c.d };
            inline for (0..64) |i| {
                const a = (4 - i % 4) % 4;
                const b = s[(a + 1) % 4];
                const cc = s[(a + 2) % 4];
                const d = s[(a + 3) % 4];
                const f, const g = switch (i / 16) {
                    0 => .{ d ^ (b & (cc ^ d)), i },
                    1 => .{ cc ^ (d & (b ^ cc)), (5 * i + 1) % 16 },
                    2 => .{ b ^ cc ^ d, (3 * i + 5) % 16 },
                    else => .{ cc ^ (b | ~d), (7 * i) % 16 },
                };
                s[a] = rotl(u32, s[a] +% f +% x[g] +% k[i], shifts[(i / 16) * 4 + i % 4]) +% b;
            }
            c.a +%= s[0];
            c.b +%= s[1];
            c.c +%= s[2];
            c.d +%= s[3];
        }
    }

    fn update(c: *Ctx, input: []const u8) void {
        var data = input;
        const saved_lo = c.lo;
        c.lo = (saved_lo +% @as(u32, @truncate(data.len))) & 0x1fffffff;
        if (c.lo < saved_lo) c.hi +%= 1;
        c.hi +%= @truncate(data.len >> 29);
        const used: usize = saved_lo & 0x3f;
        if (used != 0) {
            const free = 64 - used;
            if (data.len < free) {
                @memcpy(c.buffer[used..][0..data.len], data);
                return;
            }
            @memcpy(c.buffer[used..64], data[0..free]);
            data = data[free..];
            body(c, &c.buffer);
        }
        if (data.len >= 64) {
            const whole = data.len & ~@as(usize, 0x3f);
            body(c, data[0..whole]);
            data = data[whole..];
        }
        @memcpy(c.buffer[0..data.len], data);
    }

    fn final(out: []u8, c: *Ctx) void {
        var used: usize = c.lo & 0x3f;
        c.buffer[used] = 0x80;
        used += 1;
        var free = 64 - used;
        if (free < 8) {
            @memset(c.buffer[used..], 0);
            body(c, &c.buffer);
            used = 0;
            free = 64;
        }
        @memset(c.buffer[used..56], 0);
        c.lo <<= 3;
        std.mem.writeInt(u32, c.buffer[56..60], c.lo, .little);
        std.mem.writeInt(u32, c.buffer[60..64], c.hi, .little);
        body(c, &c.buffer);
        encodeLe(out[0..16], &.{ c.a, c.b, c.c, c.d });
        wipe(c);
    }
};

// ---------------------------------------------------------------------------
// sha1, sha-2 (ext/standard/sha1.c, ext/hash/hash_sha.c)

const Sha1 = struct {
    const Ctx = extern struct { state: [5]u32, count: [2]u32, buffer: [64]u8 };

    fn init(c: *Ctx, _: InitArgs) RuntimeError!void {
        c.count = .{ 0, 0 };
        c.state = .{ 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0 };
    }

    fn transform(c: *Ctx, block: *const [64]u8) void {
        var w: [80]u32 = undefined;
        for (0..16) |i| w[i] = std.mem.readInt(u32, block[i * 4 ..][0..4], .big);
        for (16..80) |i| w[i] = rotl(u32, w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
        var a = c.state[0];
        var b = c.state[1];
        var cc = c.state[2];
        var d = c.state[3];
        var e = c.state[4];
        inline for (0..80) |i| {
            const f, const kk = switch (i / 20) {
                0 => .{ d ^ (b & (cc ^ d)), 0x5A827999 },
                1 => .{ b ^ cc ^ d, 0x6ED9EBA1 },
                2 => .{ (b & cc) | (d & (b | cc)), 0x8F1BBCDC },
                else => .{ b ^ cc ^ d, 0xCA62C1D6 },
            };
            const t = rotl(u32, a, 5) +% f +% e +% w[i] +% @as(u32, kk);
            e = d;
            d = cc;
            cc = rotl(u32, b, 30);
            b = a;
            a = t;
        }
        c.state[0] +%= a;
        c.state[1] +%= b;
        c.state[2] +%= cc;
        c.state[3] +%= d;
        c.state[4] +%= e;
    }

    fn update(c: *Ctx, input: []const u8) void {
        mdUpdate(u32, 64, c, input, transform);
    }

    fn final(out: []u8, c: *Ctx) void {
        const bits = countBe(c.count);
        update(c, padding[0..padLen(c.count[0], 64, 8)]);
        update(c, &bits);
        encodeBe(out[0..20], &c.state);
        wipe(c);
    }
};

// where sha-2's working variable `r` (0 is a, 7 is h) sits in round i
fn role(comptime r: usize, comptime i: usize) usize {
    return (r + 8 * 80 - i) % 8;
}

fn Sha256(comptime iv: [8]u32, comptime digest: usize) type {
    return struct {
        const Ctx = extern struct { state: [8]u32, count: [2]u32, buffer: [64]u8 };

        fn init(c: *Ctx, _: InitArgs) RuntimeError!void {
            c.count = .{ 0, 0 };
            c.state = iv;
        }

        fn transform(c: *Ctx, block: *const [64]u8) void {
            var w: [64]u32 = undefined;
            for (0..16) |i| w[i] = std.mem.readInt(u32, block[i * 4 ..][0..4], .big);
            for (16..64) |i| {
                const s0 = rotr(u32, w[i - 15], 7) ^ rotr(u32, w[i - 15], 18) ^ (w[i - 15] >> 3);
                const s1 = rotr(u32, w[i - 2], 17) ^ rotr(u32, w[i - 2], 19) ^ (w[i - 2] >> 10);
                w[i] = w[i - 16] +% s0 +% w[i - 7] +% s1;
            }
            var s = c.state;
            // the eight working variables rotate through s instead of moving
            inline for (0..64) |i| {
                const a = role(0, i);
                const e = role(4, i);
                const t1 = s[role(7, i)] +% (rotr(u32, s[e], 6) ^ rotr(u32, s[e], 11) ^ rotr(u32, s[e], 25)) +% (s[role(6, i)] ^ (s[e] & (s[role(5, i)] ^ s[role(6, i)]))) +% tables.sha256_k[i] +% w[i];
                const t2 = (rotr(u32, s[a], 2) ^ rotr(u32, s[a], 13) ^ rotr(u32, s[a], 22)) +% ((s[a] & s[role(1, i)]) | (s[role(2, i)] & (s[a] | s[role(1, i)])));
                s[role(3, i)] +%= t1;
                s[role(7, i)] = t1 +% t2;
            }
            for (0..8) |i| c.state[i] +%= s[i];
        }

        fn update(c: *Ctx, input: []const u8) void {
            mdUpdate(u32, 64, c, input, transform);
        }

        fn final(out: []u8, c: *Ctx) void {
            const bits = countBe(c.count);
            update(c, padding[0..padLen(c.count[0], 64, 8)]);
            update(c, &bits);
            encodeBe(out[0..digest], c.state[0 .. digest / 4]);
            wipe(c);
        }
    };
}

fn Sha512(comptime iv: [8]u64, comptime digest: usize) type {
    return struct {
        const Ctx = extern struct { state: [8]u64, count: [2]u64, buffer: [128]u8 };

        fn init(c: *Ctx, _: InitArgs) RuntimeError!void {
            c.count = .{ 0, 0 };
            c.state = iv;
        }

        fn transform(c: *Ctx, block: *const [128]u8) void {
            var w: [80]u64 = undefined;
            for (0..16) |i| w[i] = std.mem.readInt(u64, block[i * 8 ..][0..8], .big);
            for (16..80) |i| {
                const s0 = rotr(u64, w[i - 15], 1) ^ rotr(u64, w[i - 15], 8) ^ (w[i - 15] >> 7);
                const s1 = rotr(u64, w[i - 2], 19) ^ rotr(u64, w[i - 2], 61) ^ (w[i - 2] >> 6);
                w[i] = w[i - 16] +% s0 +% w[i - 7] +% s1;
            }
            var s = c.state;
            inline for (0..80) |i| {
                const a = role(0, i);
                const e = role(4, i);
                const t1 = s[role(7, i)] +% (rotr(u64, s[e], 14) ^ rotr(u64, s[e], 18) ^ rotr(u64, s[e], 41)) +% (s[role(6, i)] ^ (s[e] & (s[role(5, i)] ^ s[role(6, i)]))) +% tables.sha512_k[i] +% w[i];
                const t2 = (rotr(u64, s[a], 28) ^ rotr(u64, s[a], 34) ^ rotr(u64, s[a], 39)) +% ((s[a] & s[role(1, i)]) | (s[role(2, i)] & (s[a] | s[role(1, i)])));
                s[role(3, i)] +%= t1;
                s[role(7, i)] = t1 +% t2;
            }
            for (0..8) |i| c.state[i] +%= s[i];
        }

        fn update(c: *Ctx, input: []const u8) void {
            mdUpdate(u64, 128, c, input, transform);
        }

        fn final(out: []u8, c: *Ctx) void {
            var bits: [16]u8 = undefined;
            std.mem.writeInt(u64, bits[0..8], c.count[1], .big);
            std.mem.writeInt(u64, bits[8..16], c.count[0], .big);
            update(c, padding[0..padLen(c.count[0], 128, 16)]);
            update(c, &bits);
            var full: [64]u8 = undefined;
            for (0..8) |i| std.mem.writeInt(u64, full[i * 8 ..][0..8], c.state[i], .big);
            @memcpy(out[0..digest], full[0..digest]);
            wipe(c);
        }
    };
}

const Sha224 = Sha256(.{ 0xc1059ed8, 0x367cd507, 0x3070dd17, 0xf70e5939, 0xffc00b31, 0x68581511, 0x64f98fa7, 0xbefa4fa4 }, 28);
const Sha256Full = Sha256(.{ 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }, 32);
const Sha384 = Sha512(.{ 0xcbbb9d5dc1059ed8, 0x629a292a367cd507, 0x9159015a3070dd17, 0x152fecd8f70e5939, 0x67332667ffc00b31, 0x8eb44a8768581511, 0xdb0c2e0d64f98fa7, 0x47b5481dbefa4fa4 }, 48);
const Sha512Full = Sha512(.{ 0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1, 0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179 }, 64);
const Sha512_256 = Sha512(.{ 0x22312194FC2BF72C, 0x9F555FA3C84C64C2, 0x2393B86B6F53B151, 0x963877195940EABD, 0x96283EE2A88EFFE3, 0xBE5E1E2553863992, 0x2B0199FC2C85B8AA, 0x0EB72DDC81C52CA2 }, 32);
const Sha512_224 = Sha512(.{ 0x8C3D37C819544DA2, 0x73E1996689DCD4D6, 0x1DFAB7AE32FF9C82, 0x679DD514582F9FCF, 0x0F6D2B697BD44DA8, 0x77E36F7304C48942, 0x3F9D85A86A1D36C8, 0x1112E6AD91D692A1 }, 28);

// ---------------------------------------------------------------------------
// sha3 (php's bundled keccak: generic64lc, whose state keeps six lanes
// complemented, which is what a serialized context shows)

fn Sha3(comptime bits: usize) type {
    return struct {
        const Ctx = extern struct {
            state: [200]u8 align(8),
            rate: u32,
            byte_io_index: u32,
            squeezing: i32,
            fixed_output_length: u32,
            delimited_suffix: u8,
        };
        const rate_bytes = (1600 - 2 * bits) / 8;
        const complemented = [_]usize{ 1, 2, 8, 12, 17, 20 };

        fn init(c: *Ctx, _: InitArgs) RuntimeError!void {
            @memset(&c.state, 0);
            for (complemented) |lane| @memset(c.state[lane * 8 ..][0..8], 0xff);
            c.rate = rate_bytes * 8;
            c.byte_io_index = 0;
            c.squeezing = 0;
            c.fixed_output_length = bits;
            c.delimited_suffix = 0x06;
        }

        fn permute(c: *Ctx) void {
            var f: std.crypto.core.keccak.KeccakF(1600) = .{};
            for (0..25) |i| f.st[i] = std.mem.readInt(u64, c.state[i * 8 ..][0..8], .little);
            for (complemented) |lane| f.st[lane] = ~f.st[lane];
            f.permute();
            for (complemented) |lane| f.st[lane] = ~f.st[lane];
            for (0..25) |i| std.mem.writeInt(u64, c.state[i * 8 ..][0..8], f.st[i], .little);
        }

        fn update(c: *Ctx, input: []const u8) void {
            if (c.squeezing != 0) return;
            var data = input;
            while (data.len > 0) {
                const at: usize = c.byte_io_index;
                const n = @min(data.len, rate_bytes - at);
                for (0..n) |i| c.state[at + i] ^= data[i];
                data = data[n..];
                c.byte_io_index += @intCast(n);
                if (c.byte_io_index == rate_bytes) {
                    permute(c);
                    c.byte_io_index = 0;
                }
            }
        }

        fn final(out: []u8, c: *Ctx) void {
            const at: usize = c.byte_io_index;
            c.state[at] ^= c.delimited_suffix;
            if (c.delimited_suffix & 0x80 != 0 and at == rate_bytes - 1) permute(c);
            c.state[rate_bytes - 1] ^= 0x80;
            permute(c);
            c.byte_io_index = 0;
            c.squeezing = 1;
            for (0..bits / 8) |i| {
                var byte = c.state[i];
                for (complemented) |lane| {
                    if (i / 8 == lane) byte = ~byte;
                }
                out[i] = byte;
            }
        }

        pub fn valid(c: *Ctx) bool {
            return c.byte_io_index < c.rate / 8;
        }
    };
}

// ---------------------------------------------------------------------------
// ripemd (ext/hash/hash_ripemd.c)

fn ripemdF(comptime j: usize, x: u32, y: u32, z: u32) u32 {
    return switch (j) {
        0 => x ^ y ^ z,
        1 => (x & y) | (~x & z),
        2 => (x | ~y) ^ z,
        3 => (x & z) | (y & ~z),
        else => x ^ (y | ~z),
    };
}

const ripemd_k = [5]u32{ 0x00000000, 0x5A827999, 0x6ED9EBA1, 0x8F1BBCDC, 0xA953FD4E };
const ripemd_kk = [4]u32{ 0x50A28BE6, 0x5C4DD124, 0x6D703EF3, 0x00000000 };
const ripemd_kk160 = [5]u32{ 0x50A28BE6, 0x5C4DD124, 0x6D703EF3, 0x7A6D76E9, 0x00000000 };

fn Ripemd(comptime words: usize) type {
    return struct {
        const Ctx = extern struct { state: [words]u32, count: [2]u32, buffer: [64]u8 };

        fn init(c: *Ctx, _: InitArgs) RuntimeError!void {
            c.count = .{ 0, 0 };
            c.state = switch (words) {
                4 => .{ 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476 },
                5 => .{ 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0 },
                8 => .{ 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0x76543210, 0xFEDCBA98, 0x89ABCDEF, 0x01234567 },
                else => .{ 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0, 0x76543210, 0xFEDCBA98, 0x89ABCDEF, 0x01234567, 0x3C2D1E0F },
            };
        }

        // the 4-word line (128, 256): rounds of 16 with F0..F3 on the left
        // and F3..F0 on the right
        fn line4(comptime j0: usize, a: *u32, b: *u32, c: *u32, d: *u32, aa: *u32, bb: *u32, cc: *u32, dd: *u32, x: [16]u32) void {
            inline for (j0..j0 + 16) |j| {
                const r = j / 16;
                var tmp = rotl(u32, a.* +% ripemdF(r, b.*, c.*, d.*) +% x[tables.ripemd_r[j]] +% ripemd_k[r], tables.ripemd_s[j]);
                a.* = d.*;
                d.* = c.*;
                c.* = b.*;
                b.* = tmp;
                tmp = rotl(u32, aa.* +% ripemdF(3 - r, bb.*, cc.*, dd.*) +% x[tables.ripemd_rr[j]] +% ripemd_kk[r], tables.ripemd_ss[j]);
                aa.* = dd.*;
                dd.* = cc.*;
                cc.* = bb.*;
                bb.* = tmp;
            }
        }

        // the 5-word line (160, 320): F0..F4 on the left, F4..F0 on the right
        fn line5(comptime j0: usize, a: *u32, b: *u32, c: *u32, d: *u32, e: *u32, aa: *u32, bb: *u32, cc: *u32, dd: *u32, ee: *u32, x: [16]u32) void {
            inline for (j0..j0 + 16) |j| {
                const r = j / 16;
                var tmp = rotl(u32, a.* +% ripemdF(r, b.*, c.*, d.*) +% x[tables.ripemd_r[j]] +% ripemd_k[r], tables.ripemd_s[j]) +% e.*;
                a.* = e.*;
                e.* = d.*;
                d.* = rotl(u32, c.*, 10);
                c.* = b.*;
                b.* = tmp;
                tmp = rotl(u32, aa.* +% ripemdF(4 - r, bb.*, cc.*, dd.*) +% x[tables.ripemd_rr[j]] +% ripemd_kk160[r], tables.ripemd_ss[j]) +% ee.*;
                aa.* = ee.*;
                ee.* = dd.*;
                dd.* = rotl(u32, cc.*, 10);
                cc.* = bb.*;
                bb.* = tmp;
            }
        }

        fn transform(ctx: *Ctx, block: *const [64]u8) void {
            const x = decodeLe(16, block);
            const st = &ctx.state;
            switch (words) {
                4 => {
                    var a = st[0];
                    var b = st[1];
                    var c = st[2];
                    var d = st[3];
                    var aa = st[0];
                    var bb = st[1];
                    var cc = st[2];
                    var dd = st[3];
                    inline for (.{ 0, 16, 32, 48 }) |j0| line4(j0, &a, &b, &c, &d, &aa, &bb, &cc, &dd, x);
                    const tmp = st[1] +% c +% dd;
                    st[1] = st[2] +% d +% aa;
                    st[2] = st[3] +% a +% bb;
                    st[3] = st[0] +% b +% cc;
                    st[0] = tmp;
                },
                8 => {
                    var a = st[0];
                    var b = st[1];
                    var c = st[2];
                    var d = st[3];
                    var aa = st[4];
                    var bb = st[5];
                    var cc = st[6];
                    var dd = st[7];
                    line4(0, &a, &b, &c, &d, &aa, &bb, &cc, &dd, x);
                    std.mem.swap(u32, &a, &aa);
                    line4(16, &a, &b, &c, &d, &aa, &bb, &cc, &dd, x);
                    std.mem.swap(u32, &b, &bb);
                    line4(32, &a, &b, &c, &d, &aa, &bb, &cc, &dd, x);
                    std.mem.swap(u32, &c, &cc);
                    line4(48, &a, &b, &c, &d, &aa, &bb, &cc, &dd, x);
                    std.mem.swap(u32, &d, &dd);
                    for ([8]u32{ a, b, c, d, aa, bb, cc, dd }, 0..) |v, i| st[i] +%= v;
                },
                5 => {
                    var a = st[0];
                    var b = st[1];
                    var c = st[2];
                    var d = st[3];
                    var e = st[4];
                    var aa = st[0];
                    var bb = st[1];
                    var cc = st[2];
                    var dd = st[3];
                    var ee = st[4];
                    inline for (.{ 0, 16, 32, 48, 64 }) |j0| line5(j0, &a, &b, &c, &d, &e, &aa, &bb, &cc, &dd, &ee, x);
                    const tmp = st[1] +% c +% dd;
                    st[1] = st[2] +% d +% ee;
                    st[2] = st[3] +% e +% aa;
                    st[3] = st[4] +% a +% bb;
                    st[4] = st[0] +% b +% cc;
                    st[0] = tmp;
                },
                else => {
                    var a = st[0];
                    var b = st[1];
                    var c = st[2];
                    var d = st[3];
                    var e = st[4];
                    var aa = st[5];
                    var bb = st[6];
                    var cc = st[7];
                    var dd = st[8];
                    var ee = st[9];
                    line5(0, &a, &b, &c, &d, &e, &aa, &bb, &cc, &dd, &ee, x);
                    std.mem.swap(u32, &b, &bb);
                    line5(16, &a, &b, &c, &d, &e, &aa, &bb, &cc, &dd, &ee, x);
                    std.mem.swap(u32, &d, &dd);
                    line5(32, &a, &b, &c, &d, &e, &aa, &bb, &cc, &dd, &ee, x);
                    std.mem.swap(u32, &a, &aa);
                    line5(48, &a, &b, &c, &d, &e, &aa, &bb, &cc, &dd, &ee, x);
                    std.mem.swap(u32, &c, &cc);
                    line5(64, &a, &b, &c, &d, &e, &aa, &bb, &cc, &dd, &ee, x);
                    std.mem.swap(u32, &e, &ee);
                    for ([10]u32{ a, b, c, d, e, aa, bb, cc, dd, ee }, 0..) |v, i| st[i] +%= v;
                },
            }
        }

        fn update(c: *Ctx, input: []const u8) void {
            mdUpdate(u32, 64, c, input, transform);
        }

        fn final(out: []u8, c: *Ctx) void {
            const bits = countLe(c.count);
            update(c, padding[0..padLen(c.count[0], 64, 8)]);
            update(c, &bits);
            encodeLe(out[0 .. words * 4], &c.state);
            wipe(c);
        }
    };
}

// ---------------------------------------------------------------------------
// haval (ext/hash/hash_haval.c)

fn havalF(comptime n: usize, x6: u32, x5: u32, x4: u32, x3: u32, x2: u32, x1: u32, x0: u32) u32 {
    return switch (n) {
        1 => (x1 & x4) ^ (x2 & x5) ^ (x3 & x6) ^ (x0 & x1) ^ x0,
        2 => (x1 & x2 & x3) ^ (x2 & x4 & x5) ^ (x1 & x2) ^ (x1 & x4) ^ (x2 & x6) ^ (x3 & x5) ^ (x4 & x5) ^ (x0 & x2) ^ x0,
        3 => (x1 & x2 & x3) ^ (x1 & x4) ^ (x2 & x5) ^ (x3 & x6) ^ (x0 & x3) ^ x0,
        4 => (x1 & x2 & x3) ^ (x2 & x4 & x5) ^ (x3 & x4 & x6) ^ (x1 & x4) ^ (x2 & x6) ^ (x3 & x4) ^ (x3 & x5) ^ (x3 & x6) ^ (x4 & x5) ^ (x4 & x6) ^ (x0 & x4) ^ x0,
        else => (x1 & x4) ^ (x2 & x5) ^ (x3 & x6) ^ (x0 & x1 & x2 & x3) ^ (x0 & x5) ^ x0,
    };
}

const haval_m = [8]*const [32]u8{ &tables.haval_m0, &tables.haval_m1, &tables.haval_m2, &tables.haval_m3, &tables.haval_m4, &tables.haval_m5, &tables.haval_m6, &tables.haval_m7 };
const haval_order_i = [6]?*const [32]u8{ null, null, &tables.haval_i2, &tables.haval_i3, &tables.haval_i4, &tables.haval_i5 };
const haval_k = [6]?*const [32]u32{ null, null, &tables.haval_k2, &tables.haval_k3, &tables.haval_k4, &tables.haval_k5 };

// which M tables feed F's seven arguments, per pass count and round
const haval_args = [3][5][7]u8{
    .{ .{ 1, 0, 3, 5, 6, 2, 4 }, .{ 4, 2, 1, 0, 5, 3, 6 }, .{ 6, 1, 2, 3, 4, 5, 0 }, .{ 0, 0, 0, 0, 0, 0, 0 }, .{ 0, 0, 0, 0, 0, 0, 0 } },
    .{ .{ 2, 6, 1, 4, 5, 3, 0 }, .{ 3, 5, 2, 0, 1, 6, 4 }, .{ 1, 4, 3, 6, 0, 2, 5 }, .{ 6, 4, 0, 5, 2, 1, 3 }, .{ 0, 0, 0, 0, 0, 0, 0 } },
    .{ .{ 3, 4, 1, 0, 5, 2, 6 }, .{ 6, 2, 1, 0, 3, 4, 5 }, .{ 2, 6, 0, 4, 3, 1, 5 }, .{ 1, 5, 3, 2, 0, 4, 6 }, .{ 2, 5, 0, 6, 4, 3, 1 } },
};

fn Haval(comptime passes: u8, comptime output: u16) type {
    return struct {
        const Ctx = extern struct {
            state: [8]u32,
            count: [2]u32,
            buffer: [128]u8,
            passes: i8,
            output: i16,
            // php's transform function pointer, never serialized
            transform_fn: usize,
        };

        fn init(c: *Ctx, _: InitArgs) RuntimeError!void {
            c.count = .{ 0, 0 };
            c.state = tables.haval_d0;
            c.passes = passes;
            c.output = output;
        }

        fn transform(c: *Ctx, block: *const [128]u8) void {
            const x = decodeLe(32, block);
            var e = c.state;
            inline for (0..passes) |round| {
                const args = haval_args[passes - 3][round];
                for (0..32) |i| {
                    const f = havalF(round + 1, e[haval_m[args[0]][i]], e[haval_m[args[1]][i]], e[haval_m[args[2]][i]], e[haval_m[args[3]][i]], e[haval_m[args[4]][i]], e[haval_m[args[5]][i]], e[haval_m[args[6]][i]]);
                    var v = rotr(u32, f, 7) +% rotr(u32, e[haval_m[7][i]], 11);
                    if (round == 0) {
                        v +%= x[i];
                    } else {
                        v +%= x[haval_order_i[round + 1].?[i]] +% haval_k[round + 1].?[i];
                    }
                    e[7 - (i % 8)] = v;
                }
            }
            for (0..8) |i| c.state[i] +%= e[i];
        }

        fn update(c: *Ctx, input: []const u8) void {
            mdUpdate(u32, 128, c, input, transform);
        }

        fn final(out: []u8, c: *Ctx) void {
            var bits: [10]u8 = undefined;
            bits[0] = @truncate(1 | ((@as(u32, @intCast(c.passes)) & 7) << 3) | ((@as(u32, @intCast(c.output)) & 3) << 6));
            bits[1] = @truncate(@as(u32, @intCast(c.output)) >> 2);
            bits[2..10].* = countLe(c.count);
            const index: usize = (c.count[0] >> 3) & 0x7f;
            const pad = if (index < 118) 118 - index else 246 - index;
            var hpad: [128]u8 = @splat(0);
            hpad[0] = 1;
            update(c, hpad[0..pad]);
            update(c, &bits);
            const s = &c.state;
            switch (output) {
                128 => {
                    s[3] +%= (s[7] & 0xFF000000) | (s[6] & 0x00FF0000) | (s[5] & 0x0000FF00) | (s[4] & 0x000000FF);
                    s[2] +%= (((s[7] & 0x00FF0000) | (s[6] & 0x0000FF00) | (s[5] & 0x000000FF)) << 8) | ((s[4] & 0xFF000000) >> 24);
                    s[1] +%= (((s[7] & 0x0000FF00) | (s[6] & 0x000000FF)) << 16) | (((s[5] & 0xFF000000) | (s[4] & 0x00FF0000)) >> 16);
                    s[0] +%= ((s[7] & 0x000000FF) << 24) | (((s[6] & 0xFF000000) | (s[5] & 0x00FF0000) | (s[4] & 0x0000FF00)) >> 8);
                },
                160 => {
                    s[4] +%= ((s[7] & 0xFE000000) | (s[6] & 0x01F80000) | (s[5] & 0x0007F000)) >> 12;
                    s[3] +%= ((s[7] & 0x01F80000) | (s[6] & 0x0007F000) | (s[5] & 0x00000FC0)) >> 6;
                    s[2] +%= (s[7] & 0x0007F000) | (s[6] & 0x00000FC0) | (s[5] & 0x0000003F);
                    s[1] +%= rotr(u32, (s[7] & 0x00000FC0) | (s[6] & 0x0000003F) | (s[5] & 0xFE000000), 25);
                    s[0] +%= rotr(u32, (s[7] & 0x0000003F) | (s[6] & 0xFE000000) | (s[5] & 0x01F80000), 19);
                },
                192 => {
                    s[5] +%= ((s[7] & 0xFC000000) | (s[6] & 0x03E00000)) >> 21;
                    s[4] +%= ((s[7] & 0x03E00000) | (s[6] & 0x001F0000)) >> 16;
                    s[3] +%= ((s[7] & 0x001F0000) | (s[6] & 0x0000FC00)) >> 10;
                    s[2] +%= ((s[7] & 0x0000FC00) | (s[6] & 0x000003E0)) >> 5;
                    s[1] +%= (s[7] & 0x000003E0) | (s[6] & 0x0000001F);
                    s[0] +%= rotr(u32, (s[7] & 0x0000001F) | (s[6] & 0xFC000000), 26);
                },
                224 => {
                    s[6] +%= s[7] & 0x0000000F;
                    s[5] +%= (s[7] >> 4) & 0x0000001F;
                    s[4] +%= (s[7] >> 9) & 0x0000000F;
                    s[3] +%= (s[7] >> 13) & 0x0000001F;
                    s[2] +%= (s[7] >> 18) & 0x0000000F;
                    s[1] +%= (s[7] >> 22) & 0x0000001F;
                    s[0] +%= (s[7] >> 27) & 0x0000001F;
                },
                else => {},
            }
            encodeLe(out[0 .. output / 8], s);
            wipe(c);
        }
    };
}

// ---------------------------------------------------------------------------
// tiger (ext/hash/hash_tiger.c)

fn Tiger(comptime passes: u32, comptime output: usize) type {
    return struct {
        const Ctx = extern struct { state: [3]u64, passed: u64, buffer: [64]u8, length: u32, passes: u32 };

        fn init(c: *Ctx, _: InitArgs) RuntimeError!void {
            c.* = std.mem.zeroes(Ctx);
            c.passes = passes;
            c.state = .{ 0x0123456789ABCDEF, 0xFEDCBA9876543210, 0xF096A5B4C3B2E187 };
        }

        inline fn round(a: *u64, b: *u64, c: *u64, x: u64, comptime mul: u64) void {
            c.* ^= x;
            const cv = c.*;
            const b0: u8 = @truncate(cv);
            const b1: u8 = @truncate(cv >> 8);
            const b2: u8 = @truncate(cv >> 16);
            const b3: u8 = @truncate(cv >> 24);
            const b4: u8 = @truncate(cv >> 32);
            const b5: u8 = @truncate(cv >> 40);
            const b6: u8 = @truncate(cv >> 48);
            const b7: u8 = @truncate(cv >> 56);
            a.* -%= tables.tiger[0][b0] ^ tables.tiger[1][b2] ^ tables.tiger[2][b4] ^ tables.tiger[3][b6];
            b.* +%= tables.tiger[3][b1] ^ tables.tiger[2][b3] ^ tables.tiger[1][b5] ^ tables.tiger[0][b7];
            b.* *%= mul;
        }

        fn pass(a: *u64, b: *u64, c: *u64, x: *const [8]u64, comptime mul: u64) void {
            round(a, b, c, x[0], mul);
            round(b, c, a, x[1], mul);
            round(c, a, b, x[2], mul);
            round(a, b, c, x[3], mul);
            round(b, c, a, x[4], mul);
            round(c, a, b, x[5], mul);
            round(a, b, c, x[6], mul);
            round(b, c, a, x[7], mul);
        }

        fn keySchedule(x: *[8]u64) void {
            x[0] -%= x[7] ^ 0xA5A5A5A5A5A5A5A5;
            x[1] ^= x[0];
            x[2] +%= x[1];
            x[3] -%= x[2] ^ ((~x[1]) << 19);
            x[4] ^= x[3];
            x[5] +%= x[4];
            x[6] -%= x[5] ^ ((~x[4]) >> 23);
            x[7] ^= x[6];
            x[0] +%= x[7];
            x[1] -%= x[0] ^ ((~x[7]) << 19);
            x[2] ^= x[1];
            x[3] +%= x[2];
            x[4] -%= x[3] ^ ((~x[2]) >> 23);
            x[5] ^= x[4];
            x[6] +%= x[5];
            x[7] -%= x[6] ^ 0x0123456789ABCDEF;
        }

        fn compress(c: *Ctx, block: *const [64]u8) void {
            var x: [8]u64 = undefined;
            for (0..8) |i| x[i] = std.mem.readInt(u64, block[i * 8 ..][0..8], .little);
            var a = c.state[0];
            var b = c.state[1];
            var cc = c.state[2];
            const aa = a;
            const bb = b;
            const ccc = cc;
            pass(&a, &b, &cc, &x, 5);
            keySchedule(&x);
            pass(&cc, &a, &b, &x, 7);
            keySchedule(&x);
            pass(&b, &cc, &a, &x, 9);
            var n: u32 = 0;
            while (n < c.passes) : (n += 1) {
                keySchedule(&x);
                pass(&a, &b, &cc, &x, 9);
                const t = a;
                a = cc;
                cc = b;
                b = t;
            }
            a ^= aa;
            b -%= bb;
            cc +%= ccc;
            c.state = .{ a, b, cc };
        }

        fn update(c: *Ctx, input: []const u8) void {
            const len: usize = c.length;
            if (len + input.len < 64) {
                @memcpy(c.buffer[len..][0..input.len], input);
                c.length += @intCast(input.len);
                return;
            }
            var i: usize = 0;
            const r = (len + input.len) % 64;
            if (len != 0) {
                i = 64 - len;
                @memcpy(c.buffer[len..64], input[0..i]);
                compress(c, &c.buffer);
                @memset(&c.buffer, 0);
                c.passed +%= 512;
            }
            while (i + 64 <= input.len) : (i += 64) {
                @memcpy(&c.buffer, input[i..][0..64]);
                compress(c, &c.buffer);
                c.passed +%= 512;
            }
            @memset(c.buffer[r..], 0);
            @memcpy(c.buffer[0..r], input[i..][0..r]);
            c.length = @intCast(r);
        }

        fn final(out: []u8, c: *Ctx) void {
            c.passed +%= @as(u64, c.length) << 3;
            c.buffer[c.length] = 1;
            c.length += 1;
            if (c.length % 8 != 0) {
                const fill = 8 - c.length % 8;
                @memset(c.buffer[c.length..][0..fill], 0);
                c.length += fill;
            }
            if (c.length > 56) {
                @memset(c.buffer[c.length..], 0);
                compress(c, &c.buffer);
                @memset(c.buffer[0..56], 0);
            } else {
                @memset(c.buffer[c.length..56], 0);
            }
            std.mem.writeInt(u64, c.buffer[56..64], c.passed, .little);
            compress(c, &c.buffer);
            for (0..output) |i| out[i] = @truncate(c.state[i / 8] >> @intCast(8 * (i % 8)));
            wipe(c);
        }

        pub fn valid(c: *Ctx) bool {
            return c.length < 64;
        }
    };
}

// ---------------------------------------------------------------------------
// whirlpool (ext/hash/hash_whirlpool.c)

const Whirlpool = struct {
    const Ctx = extern struct {
        state: [8]u64,
        bitlength: [32]u8,
        pos: i32,
        bits: i32,
        data: [64]u8,
    };

    fn init(c: *Ctx, _: InitArgs) RuntimeError!void {
        c.* = std.mem.zeroes(Ctx);
    }

    inline fn mix(s: [8]u64, comptime i: usize) u64 {
        return tables.whirlpool_c0[@intCast(s[i] >> 56)] ^
            tables.whirlpool_c1[@intCast((s[(i + 7) % 8] >> 48) & 0xff)] ^
            tables.whirlpool_c2[@intCast((s[(i + 6) % 8] >> 40) & 0xff)] ^
            tables.whirlpool_c3[@intCast((s[(i + 5) % 8] >> 32) & 0xff)] ^
            tables.whirlpool_c4[@intCast((s[(i + 4) % 8] >> 24) & 0xff)] ^
            tables.whirlpool_c5[@intCast((s[(i + 3) % 8] >> 16) & 0xff)] ^
            tables.whirlpool_c6[@intCast((s[(i + 2) % 8] >> 8) & 0xff)] ^
            tables.whirlpool_c7[@intCast(s[(i + 1) % 8] & 0xff)];
    }

    fn transform(c: *Ctx) void {
        var block: [8]u64 = undefined;
        for (0..8) |i| block[i] = std.mem.readInt(u64, c.data[i * 8 ..][0..8], .big);
        var k = c.state;
        var state: [8]u64 = undefined;
        for (0..8) |i| state[i] = block[i] ^ k[i];
        for (1..11) |r| {
            var l: [8]u64 = undefined;
            inline for (0..8) |i| l[i] = mix(k, i);
            l[0] ^= tables.whirlpool_rc[r];
            k = l;
            inline for (0..8) |i| l[i] = mix(state, i) ^ k[i];
            state = l;
        }
        for (0..8) |i| c.state[i] ^= state[i] ^ block[i];
    }

    fn update(c: *Ctx, input: []const u8) void {
        var source_bits: u64 = @as(u64, input.len) *% 8;
        var source_pos: usize = 0;
        const source_gap: u5 = 0;
        const buffer_rem: u5 = @intCast(c.bits & 7);
        var buffer_bits: i32 = c.bits;
        var buffer_pos: usize = @intCast(c.pos);
        // tally the length of the added data
        var value: u64 = source_bits;
        var carry: u32 = 0;
        var i: isize = 31;
        while (i >= 0 and (carry != 0 or value != 0)) : (i -= 1) {
            const idx: usize = @intCast(i);
            carry += @as(u32, c.bitlength[idx]) + @as(u32, @truncate(value & 0xff));
            c.bitlength[idx] = @truncate(carry);
            carry >>= 8;
            value >>= 8;
        }
        var b: u32 = 0;
        while (source_bits > 8) {
            b = ((@as(u32, input[source_pos]) << source_gap) & 0xff) | ((@as(u32, input[source_pos + 1]) & 0xff) >> (8 - source_gap));
            c.data[buffer_pos] |= @truncate(b >> buffer_rem);
            buffer_pos += 1;
            buffer_bits += 8 - @as(i32, buffer_rem);
            if (buffer_bits == 512) {
                transform(c);
                buffer_bits = 0;
                buffer_pos = 0;
            }
            c.data[buffer_pos] = @truncate(b << (8 - buffer_rem));
            buffer_bits += @as(i32, buffer_rem);
            source_bits -= 8;
            source_pos += 1;
        }
        if (source_bits > 0) {
            b = (@as(u32, input[source_pos]) << source_gap) & 0xff;
            c.data[buffer_pos] |= @truncate(b >> buffer_rem);
        } else {
            b = 0;
        }
        if (@as(u64, buffer_rem) + source_bits < 8) {
            buffer_bits += @intCast(source_bits);
        } else {
            buffer_pos += 1;
            buffer_bits += 8 - @as(i32, buffer_rem);
            source_bits -= 8 - @as(u64, buffer_rem);
            if (buffer_bits == 512) {
                transform(c);
                buffer_bits = 0;
                buffer_pos = 0;
            }
            c.data[buffer_pos] = @truncate(b << (8 - buffer_rem));
            buffer_bits += @intCast(source_bits);
        }
        c.bits = buffer_bits;
        c.pos = @intCast(buffer_pos);
    }

    fn final(out: []u8, c: *Ctx) void {
        var pos: usize = @intCast(c.pos);
        c.data[pos] |= @as(u8, 0x80) >> @intCast(c.bits & 7);
        pos += 1;
        if (pos > 32) {
            if (pos < 64) @memset(c.data[pos..], 0);
            transform(c);
            pos = 0;
        }
        if (pos < 32) @memset(c.data[pos..32], 0);
        @memcpy(c.data[32..64], &c.bitlength);
        transform(c);
        for (0..8) |i| std.mem.writeInt(u64, out[i * 8 ..][0..8], c.state[i], .big);
        wipe(c);
    }

    pub fn valid(c: *Ctx) bool {
        return c.pos >= 0 and c.pos < 64 and c.bits >= c.pos * 8 and c.bits < c.pos * 8 + 8;
    }
};

// ---------------------------------------------------------------------------
// snefru (ext/hash/hash_snefru.c)

const Snefru = struct {
    const Ctx = extern struct { state: [16]u32, count: [2]u32, length: u8, buffer: [32]u8 };

    fn init(c: *Ctx, _: InitArgs) RuntimeError!void {
        c.* = std.mem.zeroes(Ctx);
    }

    fn snefru(input: *[16]u32) void {
        const shifts = [4]u5{ 16, 8, 16, 24 };
        var bv = input.*;
        for (0..8) |index| {
            const t0 = &tables.snefru[2 * index];
            const t1 = &tables.snefru[2 * index + 1];
            for (0..4) |b| {
                inline for (0..16) |j| {
                    const t = if ((j / 2) % 2 == 0) t0 else t1;
                    const sbe = t[bv[j] & 0xff];
                    bv[(j + 15) % 16] ^= sbe;
                    bv[(j + 1) % 16] ^= sbe;
                }
                for (&bv) |*v| v.* = rotr(u32, v.*, shifts[b]);
            }
        }
        for (0..8) |i| input[i] ^= bv[15 - i];
    }

    fn transform(c: *Ctx, input: *const [32]u8) void {
        for (0..8) |j| c.state[8 + j] = std.mem.readInt(u32, input[j * 4 ..][0..4], .big);
        snefru(&c.state);
        @memset(c.state[8..16], 0);
    }

    fn update(c: *Ctx, input: []const u8) void {
        const bits: u64 = @as(u64, input.len) *% 8;
        if (@as(u64, 0xffffffff - c.count[1]) < bits) {
            c.count[0] +%= 1;
            c.count[1] = 0xffffffff - c.count[1];
            c.count[1] = (@as(u32, @truncate(input.len)) *% 8) -% c.count[1];
        } else {
            c.count[1] +%= @as(u32, @truncate(input.len)) *% 8;
        }
        const len: usize = c.length;
        if (len + input.len < 32) {
            @memcpy(c.buffer[len..][0..input.len], input);
            c.length +%= @truncate(input.len);
            return;
        }
        var i: usize = 0;
        const r = (len + input.len) % 32;
        if (len != 0) {
            i = 32 - len;
            @memcpy(c.buffer[len..32], input[0..i]);
            transform(c, &c.buffer);
        }
        while (i + 32 <= input.len) : (i += 32) transform(c, input[i..][0..32]);
        @memcpy(c.buffer[0..r], input[i..][0..r]);
        @memset(c.buffer[r..], 0);
        c.length = @intCast(r);
    }

    fn final(out: []u8, c: *Ctx) void {
        if (c.length != 0) transform(c, &c.buffer);
        c.state[14] = c.count[0];
        c.state[15] = c.count[1];
        snefru(&c.state);
        encodeBe(out[0..32], c.state[0..8]);
        wipe(c);
    }

    pub fn valid(c: *Ctx) bool {
        return c.length < 32;
    }
};

// ---------------------------------------------------------------------------
// gost (ext/hash/hash_gost.c)

fn Gost(comptime crypto: bool) type {
    return struct {
        const Ctx = extern struct {
            state: [16]u32,
            count: [2]u32,
            length: u8,
            buffer: [32]u8,
            // php's sbox table pointer, never serialized
            tables_ptr: usize,
        };
        const t = if (crypto) &tables.gost_crypto else &tables.gost_test;

        fn init(c: *Ctx, _: InitArgs) RuntimeError!void {
            c.* = std.mem.zeroes(Ctx);
        }

        inline fn gostRound(l: *u32, r: *u32, k1: u32, k2: u32) void {
            var x = k1 +% r.*;
            l.* ^= t[0][x & 0xff] ^ t[1][(x >> 8) & 0xff] ^ t[2][(x >> 16) & 0xff] ^ t[3][x >> 24];
            x = k2 +% l.*;
            r.* ^= t[0][x & 0xff] ^ t[1][(x >> 8) & 0xff] ^ t[2][(x >> 16) & 0xff] ^ t[3][x >> 24];
        }

        fn encrypt(key: [8]u32, h0: u32, h1: u32) [2]u32 {
            var r = h0;
            var l = h1;
            inline for (0..3) |_| {
                gostRound(&l, &r, key[0], key[1]);
                gostRound(&l, &r, key[2], key[3]);
                gostRound(&l, &r, key[4], key[5]);
                gostRound(&l, &r, key[6], key[7]);
            }
            gostRound(&l, &r, key[7], key[6]);
            gostRound(&l, &r, key[5], key[4]);
            gostRound(&l, &r, key[3], key[2]);
            gostRound(&l, &r, key[1], key[0]);
            // R ends by swapping l and r, and S stores the swapped r then l
            return .{ l, r };
        }

        fn gost(c: *Ctx, data: *const [8]u32) void {
            const h = c.state[0..8];
            const m = data;
            var u: [8]u32 = h.*;
            var v: [8]u32 = m.*;
            var s: [8]u32 = undefined;
            var i: usize = 0;
            while (i < 8) : (i += 2) {
                var w: [8]u32 = undefined;
                for (0..8) |k| w[k] = u[k] ^ v[k];
                var key: [8]u32 = undefined;
                key[0] = (w[0] & 0x000000ff) | ((w[2] & 0x000000ff) << 8) | ((w[4] & 0x000000ff) << 16) | ((w[6] & 0x000000ff) << 24);
                key[1] = ((w[0] & 0x0000ff00) >> 8) | (w[2] & 0x0000ff00) | ((w[4] & 0x0000ff00) << 8) | ((w[6] & 0x0000ff00) << 16);
                key[2] = ((w[0] & 0x00ff0000) >> 16) | ((w[2] & 0x00ff0000) >> 8) | (w[4] & 0x00ff0000) | ((w[6] & 0x00ff0000) << 8);
                key[3] = ((w[0] & 0xff000000) >> 24) | ((w[2] & 0xff000000) >> 16) | ((w[4] & 0xff000000) >> 8) | (w[6] & 0xff000000);
                key[4] = (w[1] & 0x000000ff) | ((w[3] & 0x000000ff) << 8) | ((w[5] & 0x000000ff) << 16) | ((w[7] & 0x000000ff) << 24);
                key[5] = ((w[1] & 0x0000ff00) >> 8) | (w[3] & 0x0000ff00) | ((w[5] & 0x0000ff00) << 8) | ((w[7] & 0x0000ff00) << 16);
                key[6] = ((w[1] & 0x00ff0000) >> 16) | ((w[3] & 0x00ff0000) >> 8) | (w[5] & 0x00ff0000) | ((w[7] & 0x00ff0000) << 8);
                key[7] = ((w[1] & 0xff000000) >> 24) | ((w[3] & 0xff000000) >> 16) | ((w[5] & 0xff000000) >> 8) | (w[7] & 0xff000000);
                const lr = encrypt(key, h[i], h[i + 1]);
                s[i] = lr[0];
                s[i + 1] = lr[1];
                if (i != 6) {
                    // A(u)
                    var l = u[0] ^ u[2];
                    var r = u[1] ^ u[3];
                    u = .{ u[2], u[3], u[4], u[5], u[6], u[7], l, r };
                    if (i == 2) {
                        u[0] ^= 0xff00ff00;
                        u[1] ^= 0xff00ff00;
                        u[2] ^= 0x00ff00ff;
                        u[3] ^= 0x00ff00ff;
                        u[4] ^= 0x00ffff00;
                        u[5] ^= 0xff0000ff;
                        u[6] ^= 0x000000ff;
                        u[7] ^= 0xff00ffff;
                    }
                    // AA(v)
                    l = v[0];
                    r = v[2];
                    v[0] = v[4];
                    v[2] = v[6];
                    v[4] = l ^ r;
                    v[6] = v[0] ^ r;
                    l = v[1];
                    r = v[3];
                    v[1] = v[5];
                    v[3] = v[7];
                    v[5] = l ^ r;
                    v[7] = v[1] ^ r;
                }
            }
            // SHIFT12(u, m, s)
            u[0] = m[0] ^ s[6];
            u[1] = m[1] ^ s[7];
            u[2] = m[2] ^ (s[0] << 16) ^ (s[0] >> 16) ^ (s[0] & 0xffff) ^ (s[1] & 0xffff) ^ (s[1] >> 16) ^ (s[2] << 16) ^ s[6] ^ (s[6] << 16) ^ (s[7] & 0xffff0000) ^ (s[7] >> 16);
            u[3] = m[3] ^ (s[0] & 0xffff) ^ (s[0] << 16) ^ (s[1] & 0xffff) ^ (s[1] << 16) ^ (s[1] >> 16) ^ (s[2] << 16) ^ (s[2] >> 16) ^ (s[3] << 16) ^ s[6] ^ (s[6] << 16) ^ (s[6] >> 16) ^ (s[7] & 0xffff) ^ (s[7] << 16) ^ (s[7] >> 16);
            u[4] = m[4] ^ (s[0] & 0xffff0000) ^ (s[0] << 16) ^ (s[0] >> 16) ^ (s[1] & 0xffff0000) ^ (s[1] >> 16) ^ (s[2] << 16) ^ (s[2] >> 16) ^ (s[3] << 16) ^ (s[3] >> 16) ^ (s[4] << 16) ^ (s[6] << 16) ^ (s[6] >> 16) ^ (s[7] & 0xffff) ^ (s[7] << 16) ^ (s[7] >> 16);
            u[5] = m[5] ^ (s[0] << 16) ^ (s[0] >> 16) ^ (s[0] & 0xffff0000) ^ (s[1] & 0xffff) ^ s[2] ^ (s[2] >> 16) ^ (s[3] << 16) ^ (s[3] >> 16) ^ (s[4] << 16) ^ (s[4] >> 16) ^ (s[5] << 16) ^ (s[6] << 16) ^ (s[6] >> 16) ^ (s[7] & 0xffff0000) ^ (s[7] << 16) ^ (s[7] >> 16);
            u[6] = m[6] ^ s[0] ^ (s[1] >> 16) ^ (s[2] << 16) ^ s[3] ^ (s[3] >> 16) ^ (s[4] << 16) ^ (s[4] >> 16) ^ (s[5] << 16) ^ (s[5] >> 16) ^ s[6] ^ (s[6] << 16) ^ (s[6] >> 16) ^ (s[7] << 16);
            u[7] = m[7] ^ (s[0] & 0xffff0000) ^ (s[0] << 16) ^ (s[1] & 0xffff) ^ (s[1] << 16) ^ (s[2] >> 16) ^ (s[3] << 16) ^ s[4] ^ (s[4] >> 16) ^ (s[5] << 16) ^ (s[5] >> 16) ^ (s[6] >> 16) ^ (s[7] & 0xffff) ^ (s[7] << 16) ^ (s[7] >> 16);
            // SHIFT16(h, v, u)
            v[0] = h[0] ^ (u[1] << 16) ^ (u[0] >> 16);
            v[1] = h[1] ^ (u[2] << 16) ^ (u[1] >> 16);
            v[2] = h[2] ^ (u[3] << 16) ^ (u[2] >> 16);
            v[3] = h[3] ^ (u[4] << 16) ^ (u[3] >> 16);
            v[4] = h[4] ^ (u[5] << 16) ^ (u[4] >> 16);
            v[5] = h[5] ^ (u[6] << 16) ^ (u[5] >> 16);
            v[6] = h[6] ^ (u[7] << 16) ^ (u[6] >> 16);
            v[7] = h[7] ^ (u[0] & 0xffff0000) ^ (u[0] << 16) ^ (u[7] >> 16) ^ (u[1] & 0xffff0000) ^ (u[1] << 16) ^ (u[6] << 16) ^ (u[7] & 0xffff0000);
            // SHIFT61(h, v)
            h[0] = (v[0] & 0xffff0000) ^ (v[0] << 16) ^ (v[0] >> 16) ^ (v[1] >> 16) ^ (v[1] & 0xffff0000) ^ (v[2] << 16) ^ (v[3] >> 16) ^ (v[4] << 16) ^ (v[5] >> 16) ^ v[5] ^ (v[6] >> 16) ^ (v[7] << 16) ^ (v[7] >> 16) ^ (v[7] & 0xffff);
            h[1] = (v[0] << 16) ^ (v[0] >> 16) ^ (v[0] & 0xffff0000) ^ (v[1] & 0xffff) ^ v[2] ^ (v[2] >> 16) ^ (v[3] << 16) ^ (v[4] >> 16) ^ (v[5] << 16) ^ (v[6] << 16) ^ v[6] ^ (v[7] & 0xffff0000) ^ (v[7] >> 16);
            h[2] = (v[0] & 0xffff) ^ (v[0] << 16) ^ (v[1] << 16) ^ (v[1] >> 16) ^ (v[1] & 0xffff0000) ^ (v[2] << 16) ^ (v[3] >> 16) ^ v[3] ^ (v[4] << 16) ^ (v[5] >> 16) ^ v[6] ^ (v[6] >> 16) ^ (v[7] & 0xffff) ^ (v[7] << 16) ^ (v[7] >> 16);
            h[3] = (v[0] << 16) ^ (v[0] >> 16) ^ (v[0] & 0xffff0000) ^ (v[1] & 0xffff0000) ^ (v[1] >> 16) ^ (v[2] << 16) ^ (v[2] >> 16) ^ v[2] ^ (v[3] << 16) ^ (v[4] >> 16) ^ v[4] ^ (v[5] << 16) ^ (v[6] << 16) ^ (v[7] & 0xffff) ^ (v[7] >> 16);
            h[4] = (v[0] >> 16) ^ (v[1] << 16) ^ v[1] ^ (v[2] >> 16) ^ v[2] ^ (v[3] << 16) ^ (v[3] >> 16) ^ v[3] ^ (v[4] << 16) ^ (v[5] >> 16) ^ v[5] ^ (v[6] << 16) ^ (v[6] >> 16) ^ (v[7] << 16);
            h[5] = (v[0] << 16) ^ (v[0] & 0xffff0000) ^ (v[1] << 16) ^ (v[1] >> 16) ^ (v[1] & 0xffff0000) ^ (v[2] << 16) ^ v[2] ^ (v[3] >> 16) ^ v[3] ^ (v[4] << 16) ^ (v[4] >> 16) ^ v[4] ^ (v[5] << 16) ^ (v[6] << 16) ^ (v[6] >> 16) ^ v[6] ^ (v[7] << 16) ^ (v[7] >> 16) ^ (v[7] & 0xffff0000);
            h[6] = v[0] ^ v[2] ^ (v[2] >> 16) ^ v[3] ^ (v[3] << 16) ^ v[4] ^ (v[4] >> 16) ^ (v[5] << 16) ^ (v[5] >> 16) ^ v[5] ^ (v[6] << 16) ^ (v[6] >> 16) ^ v[6] ^ (v[7] << 16) ^ v[7];
            h[7] = v[0] ^ (v[0] >> 16) ^ (v[1] << 16) ^ (v[1] >> 16) ^ (v[2] << 16) ^ (v[3] >> 16) ^ v[3] ^ (v[4] << 16) ^ v[4] ^ (v[5] >> 16) ^ v[5] ^ (v[6] << 16) ^ (v[6] >> 16) ^ (v[7] << 16) ^ v[7];
        }

        fn transform(c: *Ctx, input: *const [32]u8) void {
            var data: [8]u32 = undefined;
            var temp: u32 = 0;
            for (0..8) |i| {
                data[i] = std.mem.readInt(u32, input[i * 4 ..][0..4], .little);
                c.state[i + 8] +%= data[i] +% temp;
                temp = if (c.state[i + 8] < data[i]) 1 else if (c.state[i + 8] == data[i]) temp else 0;
            }
            gost(c, &data);
        }

        fn update(c: *Ctx, input: []const u8) void {
            const bits: u64 = @as(u64, input.len) *% 8;
            if (@as(u64, 0xffffffff - c.count[0]) < bits) {
                c.count[1] +%= 1;
                c.count[0] = 0xffffffff - c.count[0];
                c.count[0] = @as(u32, @truncate(bits)) -% c.count[0];
            } else {
                c.count[0] +%= @truncate(bits);
            }
            const len: usize = c.length;
            if (len + input.len < 32) {
                @memcpy(c.buffer[len..][0..input.len], input);
                c.length +%= @truncate(input.len);
                return;
            }
            var i: usize = 0;
            const r = (len + input.len) % 32;
            if (len != 0) {
                i = 32 - len;
                @memcpy(c.buffer[len..32], input[0..i]);
                transform(c, &c.buffer);
            }
            while (i + 32 <= input.len) : (i += 32) transform(c, input[i..][0..32]);
            @memcpy(c.buffer[0..r], input[i..][0..r]);
            @memset(c.buffer[r..], 0);
            c.length = @intCast(r);
        }

        fn final(out: []u8, c: *Ctx) void {
            if (c.length != 0) transform(c, &c.buffer);
            var l: [8]u32 = @splat(0);
            l[0] = c.count[0];
            l[1] = c.count[1];
            gost(c, &l);
            l = c.state[8..16].*;
            gost(c, &l);
            encodeLe(out[0..32], c.state[0..8]);
            wipe(c);
        }

        pub fn valid(c: *Ctx) bool {
            return c.length < 32;
        }
    };
}

// ---------------------------------------------------------------------------
// checksums and non-cryptographic hashes

const Adler32 = struct {
    const Ctx = extern struct { state: u32 };

    fn init(c: *Ctx, _: InitArgs) RuntimeError!void {
        c.state = 1;
    }

    fn update(c: *Ctx, input: []const u8) void {
        var s0: u32 = c.state & 0xffff;
        var s1: u32 = (c.state >> 16) & 0xffff;
        for (input) |byte| {
            s0 += byte;
            s1 += s0;
            if (s1 >= 0x7fffffff) {
                s0 %= 65521;
                s1 %= 65521;
            }
        }
        s0 %= 65521;
        s1 %= 65521;
        c.state = s0 + (s1 << 16);
    }

    fn final(out: []u8, c: *Ctx) void {
        std.mem.writeInt(u32, out[0..4], c.state, .big);
        c.state = 0;
    }
};

const crc_tables = blk: {
    @setEvalBranchQuota(20000);
    var t: [3][256]u32 = undefined;
    for (0..256) |i| {
        // crc32 (bzip2): msb first
        var c: u32 = @as(u32, @intCast(i)) << 24;
        for (0..8) |_| c = if (c & 0x80000000 != 0) (c << 1) ^ 0x04C11DB7 else c << 1;
        t[0][i] = c;
        // crc32b (ieee) and crc32c (castagnoli): reflected
        var b: u32 = @intCast(i);
        for (0..8) |_| b = if (b & 1 != 0) (b >> 1) ^ 0xEDB88320 else b >> 1;
        t[1][i] = b;
        var cc: u32 = @intCast(i);
        for (0..8) |_| cc = if (cc & 1 != 0) (cc >> 1) ^ 0x82F63B78 else cc >> 1;
        t[2][i] = cc;
    }
    break :blk t;
};

fn Crc32(comptime variant: enum { bzip2, ieee, castagnoli }) type {
    return struct {
        const Ctx = extern struct { state: u32 };

        fn init(c: *Ctx, _: InitArgs) RuntimeError!void {
            c.state = 0xffffffff;
        }

        fn update(c: *Ctx, input: []const u8) void {
            var s = c.state;
            switch (variant) {
                .bzip2 => for (input) |byte| {
                    s = (s << 8) ^ crc_tables[0][(s >> 24) ^ byte];
                },
                .ieee => for (input) |byte| {
                    s = (s >> 8) ^ crc_tables[1][(s ^ byte) & 0xff];
                },
                .castagnoli => for (input) |byte| {
                    s = (s >> 8) ^ crc_tables[2][(s ^ byte) & 0xff];
                },
            }
            c.state = s;
        }

        fn final(out: []u8, c: *Ctx) void {
            c.state = ~c.state;
            std.mem.writeInt(u32, out[0..4], c.state, if (variant == .bzip2) .little else .big);
            c.state = 0;
        }
    };
}

fn Fnv32(comptime alternate: bool) type {
    return struct {
        const Ctx = extern struct { state: u32 };

        fn init(c: *Ctx, _: InitArgs) RuntimeError!void {
            c.state = 0x811c9dc5;
        }

        fn update(c: *Ctx, input: []const u8) void {
            var h = c.state;
            for (input) |byte| {
                if (alternate) {
                    h ^= byte;
                    h *%= 0x01000193;
                } else {
                    h *%= 0x01000193;
                    h ^= byte;
                }
            }
            c.state = h;
        }

        fn final(out: []u8, c: *Ctx) void {
            std.mem.writeInt(u32, out[0..4], c.state, .big);
        }
    };
}

fn Fnv64(comptime alternate: bool) type {
    return struct {
        const Ctx = extern struct { state: u64 };

        fn init(c: *Ctx, _: InitArgs) RuntimeError!void {
            c.state = 0xcbf29ce484222325;
        }

        fn update(c: *Ctx, input: []const u8) void {
            var h = c.state;
            for (input) |byte| {
                if (alternate) {
                    h ^= byte;
                    h *%= 0x100000001b3;
                } else {
                    h *%= 0x100000001b3;
                    h ^= byte;
                }
            }
            c.state = h;
        }

        fn final(out: []u8, c: *Ctx) void {
            std.mem.writeInt(u64, out[0..8], c.state, .big);
        }
    };
}

const Joaat = struct {
    const Ctx = extern struct { state: u32 };

    fn init(c: *Ctx, _: InitArgs) RuntimeError!void {
        c.state = 0;
    }

    fn update(c: *Ctx, input: []const u8) void {
        var h = c.state;
        for (input) |byte| {
            h +%= byte;
            h +%= h << 10;
            h ^= h >> 6;
        }
        c.state = h;
    }

    fn final(out: []u8, c: *Ctx) void {
        var h = c.state;
        h +%= h << 3;
        h ^= h >> 11;
        h +%= h << 15;
        std.mem.writeInt(u32, out[0..4], h, .big);
        c.state = 0;
    }
};

// the "seed" option murmur and xxh32 read: an int, or a deprecation and 0
fn seedOption(a: InitArgs) RuntimeError!?Value {
    return option(a.options orelse return null, "seed");
}

// zend_hash_str_find_deref
fn option(opts: *PhpArray, name: []const u8) ?Value {
    const entry = opts.getPtr(.{ .string = Value.String.borrowed(name) }) orelse return null;
    return if (entry.ref) |cell| cell.* else entry.value;
}

fn deprecated(a: InitArgs, comptime msg: []const u8) RuntimeError!void {
    const ctx = a.ctx orelse return;
    const text = try std.fmt.allocPrint(ctx.allocator, "{s}(): " ++ msg, .{a.func});
    defer ctx.allocator.free(text);
    try ctx.vm.raiseError(8192, text);
}

fn murmurSeed(a: InitArgs) RuntimeError!u64 {
    const seed = (try seedOption(a)) orelse return 0;
    if (seed == .int) return @bitCast(seed.int);
    try deprecated(a, "Passing a seed of a type other than int is deprecated because it is the same as setting the seed to 0");
    return 0;
}

const murmur_c1: u32 = 0xcc9e2d51;
const murmur_c2: u32 = 0x1b873593;

const Murmur3a = struct {
    const Ctx = extern struct { h: u32, carry: u32, len: u32 };

    fn init(c: *Ctx, a: InitArgs) RuntimeError!void {
        c.h = @truncate(try murmurSeed(a));
        c.carry = 0;
        c.len = 0;
    }

    // php's doblock macros mix the words in place: a carry that went through
    // it keeps the mixed bits, which a serialized context shows
    inline fn block(h1: *u32, k: *u32) void {
        k.* *%= murmur_c1;
        k.* = rotl(u32, k.*, 15) *% murmur_c2;
        h1.* ^= k.*;
        h1.* = rotl(u32, h1.*, 13) *% 5 +% 0xe6546b64;
    }

    fn bytes(cnt: usize, h1: *u32, cr: *u32, n: *u32, data: []const u8, p: *usize) void {
        for (0..cnt) |_| {
            cr.* = cr.* >> 8 | @as(u32, data[p.*]) << 24;
            p.* += 1;
            n.* += 1;
            if (n.* == 4) {
                block(h1, cr);
                n.* = 0;
            }
        }
    }

    fn update(c: *Ctx, data: []const u8) void {
        c.len +%= @truncate(data.len);
        var h1 = c.h;
        var cr = c.carry;
        var n: u32 = cr & 3;
        var p: usize = 0;
        var len = data.len;
        const i = (4 - n) & 3;
        if (i != 0 and i <= len) {
            bytes(i, &h1, &cr, &n, data, &p);
            len -= i;
        }
        const end = p + (len & ~@as(usize, 3));
        while (p < end) : (p += 4) {
            var k1 = std.mem.readInt(u32, data[p..][0..4], .little);
            block(&h1, &k1);
        }
        len -= len & ~@as(usize, 3);
        bytes(len, &h1, &cr, &n, data, &p);
        c.h = h1;
        c.carry = (cr & ~@as(u32, 0xff)) | n;
    }

    fn final(out: []u8, c: *Ctx) void {
        var h = c.h;
        const n = c.carry & 3;
        if (n != 0) {
            var k1 = c.carry >> @intCast((4 - n) * 8);
            k1 *%= murmur_c1;
            k1 = rotl(u32, k1, 15) *% murmur_c2;
            h ^= k1;
        }
        h ^= c.len;
        h = fmix32(h);
        c.h = h;
        std.mem.writeInt(u32, out[0..4], h, .big);
    }
};

fn fmix32(x: u32) u32 {
    var h = x;
    h ^= h >> 16;
    h *%= 0x85ebca6b;
    h ^= h >> 13;
    h *%= 0xc2b2ae35;
    h ^= h >> 16;
    return h;
}

fn fmix64(x: u64) u64 {
    var k = x;
    k ^= k >> 33;
    k *%= 0xff51afd7ed558ccd;
    k ^= k >> 33;
    k *%= 0xc4ceb9fe1a85ec53;
    k ^= k >> 33;
    return k;
}

const Murmur3c = struct {
    const Ctx = extern struct { h: [4]u32, carry: [4]u32, len: u32 };
    const c1: u32 = 0x239b961b;
    const c2: u32 = 0xab0e9789;
    const c3: u32 = 0x38b34ae5;
    const c4: u32 = 0xa1e38b93;

    fn init(c: *Ctx, a: InitArgs) RuntimeError!void {
        const seed: u32 = @truncate(try murmurSeed(a));
        c.h = .{ seed, seed, seed, seed };
        c.carry = .{ 0, 0, 0, 0 };
        c.len = 0;
    }

    fn block(h: *[4]u32, k: *[4]u32) void {
        k[0] *%= c1;
        k[0] = rotl(u32, k[0], 15) *% c2;
        h[0] ^= k[0];
        h[0] = rotl(u32, h[0], 19) +% h[1];
        h[0] = h[0] *% 5 +% 0x561ccd1b;
        k[1] *%= c2;
        k[1] = rotl(u32, k[1], 16) *% c3;
        h[1] ^= k[1];
        h[1] = rotl(u32, h[1], 17) +% h[2];
        h[1] = h[1] *% 5 +% 0x0bcaa747;
        k[2] *%= c3;
        k[2] = rotl(u32, k[2], 17) *% c4;
        h[2] ^= k[2];
        h[2] = rotl(u32, h[2], 15) +% h[3];
        h[2] = h[2] *% 5 +% 0x96cd1c35;
        k[3] *%= c4;
        k[3] = rotl(u32, k[3], 18) *% c1;
        h[3] ^= k[3];
        h[3] = rotl(u32, h[3], 13) +% h[0];
        h[3] = h[3] *% 5 +% 0x32ac3b17;
    }

    fn bytes(cnt: usize, h: *[4]u32, k: *[4]u32, n: *u32, data: []const u8, p: *usize) void {
        for (0..cnt) |_| {
            const byte = @as(u32, data[p.*]) << 24;
            p.* += 1;
            const slot: usize = n.* / 4;
            k[slot] = k[slot] >> 8 | byte;
            if (n.* == 15) {
                block(h, k);
                n.* = 0;
            } else n.* += 1;
        }
    }

    fn update(c: *Ctx, data: []const u8) void {
        c.len +%= @truncate(data.len);
        var h = c.h;
        var k = c.carry;
        var n: u32 = k[3] & 15;
        var p: usize = 0;
        var len = data.len;
        const i = (16 - n) & 15;
        if (i != 0 and i <= len) {
            bytes(i, &h, &k, &n, data, &p);
            len -= i;
        }
        const end = p + (len & ~@as(usize, 15));
        while (p < end) : (p += 16) {
            k = .{
                std.mem.readInt(u32, data[p..][0..4], .little),
                std.mem.readInt(u32, data[p + 4 ..][0..4], .little),
                std.mem.readInt(u32, data[p + 8 ..][0..4], .little),
                std.mem.readInt(u32, data[p + 12 ..][0..4], .little),
            };
            block(&h, &k);
        }
        len -= len & ~@as(usize, 15);
        bytes(len, &h, &k, &n, data, &p);
        c.h = h;
        c.carry = .{ k[0], k[1], k[2], (k[3] & ~@as(u32, 0xff)) | n };
    }

    fn final(out: []u8, c: *Ctx) void {
        var h = c.h;
        const pc = c.carry;
        const n = pc[3] & 15;
        if (n != 0) {
            var k: [4]u32 = .{ 0, 0, 0, 0 };
            if (n >= 13) {
                k[3] = pc[3] >> @intCast((16 - n) * 8);
                k[2] = pc[2];
                k[1] = pc[1];
                k[0] = pc[0];
            } else if (n >= 9) {
                k[2] = pc[2] >> @intCast((12 - n) * 8);
                k[1] = pc[1];
                k[0] = pc[0];
            } else if (n >= 5) {
                k[1] = pc[1] >> @intCast((8 - n) * 8);
                k[0] = pc[0];
            } else {
                k[0] = pc[0] >> @intCast((4 - n) * 8);
            }
            if (n >= 13) {
                k[3] *%= c4;
                k[3] = rotl(u32, k[3], 18) *% c1;
                h[3] ^= k[3];
            }
            if (n >= 9) {
                k[2] *%= c3;
                k[2] = rotl(u32, k[2], 17) *% c4;
                h[2] ^= k[2];
            }
            if (n >= 5) {
                k[1] *%= c2;
                k[1] = rotl(u32, k[1], 16) *% c3;
                h[1] ^= k[1];
            }
            k[0] *%= c1;
            k[0] = rotl(u32, k[0], 15) *% c2;
            h[0] ^= k[0];
        }
        for (&h) |*v| v.* ^= c.len;
        h[0] +%= h[1];
        h[0] +%= h[2];
        h[0] +%= h[3];
        h[1] +%= h[0];
        h[2] +%= h[0];
        h[3] +%= h[0];
        for (&h) |*v| v.* = fmix32(v.*);
        h[0] +%= h[1];
        h[0] +%= h[2];
        h[0] +%= h[3];
        h[1] +%= h[0];
        h[2] +%= h[0];
        h[3] +%= h[0];
        encodeBe(out[0..16], &h);
    }
};

const Murmur3f = struct {
    const Ctx = extern struct { h: [2]u64, carry: [2]u64, len: u32 };
    const c1: u64 = 0x87c37b91114253d5;
    const c2: u64 = 0x4cf5ad432745937f;

    fn init(c: *Ctx, a: InitArgs) RuntimeError!void {
        const seed = try murmurSeed(a);
        c.h = .{ seed, seed };
        c.carry = .{ 0, 0 };
        c.len = 0;
    }

    fn block(h: *[2]u64, k: *[2]u64) void {
        k[0] *%= c1;
        k[0] = rotl(u64, k[0], 31) *% c2;
        h[0] ^= k[0];
        h[0] = rotl(u64, h[0], 27) +% h[1];
        h[0] = h[0] *% 5 +% 0x52dce729;
        k[1] *%= c2;
        k[1] = rotl(u64, k[1], 33) *% c1;
        h[1] ^= k[1];
        h[1] = rotl(u64, h[1], 31) +% h[0];
        h[1] = h[1] *% 5 +% 0x38495ab5;
    }

    fn bytes(cnt: usize, h: *[2]u64, k: *[2]u64, n: *u32, data: []const u8, p: *usize) void {
        for (0..cnt) |_| {
            const byte = @as(u64, data[p.*]) << 56;
            p.* += 1;
            const slot: usize = n.* / 8;
            k[slot] = k[slot] >> 8 | byte;
            if (n.* == 15) {
                block(h, k);
                n.* = 0;
            } else n.* += 1;
        }
    }

    fn update(c: *Ctx, data: []const u8) void {
        c.len +%= @truncate(data.len);
        var h = c.h;
        var k = c.carry;
        var n: u32 = @truncate(k[1] & 15);
        var p: usize = 0;
        var len = data.len;
        const i = (16 - n) & 15;
        if (i != 0 and i <= len) {
            bytes(i, &h, &k, &n, data, &p);
            len -= i;
        }
        const end = p + (len & ~@as(usize, 15));
        while (p < end) : (p += 16) {
            k = .{ std.mem.readInt(u64, data[p..][0..8], .little), std.mem.readInt(u64, data[p + 8 ..][0..8], .little) };
            block(&h, &k);
        }
        len -= len & ~@as(usize, 15);
        bytes(len, &h, &k, &n, data, &p);
        c.h = h;
        c.carry = .{ k[0], (k[1] & ~@as(u64, 0xff)) | n };
    }

    fn final(out: []u8, c: *Ctx) void {
        var h1 = c.h[0];
        var h2 = c.h[1];
        var k2 = c.carry[1];
        const n = k2 & 15;
        if (n != 0) {
            var k1 = c.carry[0];
            if (n > 8) {
                k2 >>= @intCast((16 - n) * 8);
                k2 *%= c2;
                k2 = rotl(u64, k2, 33) *% c1;
                h2 ^= k2;
            } else {
                k1 >>= @intCast((8 - n) * 8);
            }
            k1 *%= c1;
            k1 = rotl(u64, k1, 31) *% c2;
            h1 ^= k1;
        }
        h1 ^= c.len;
        h2 ^= c.len;
        h1 +%= h2;
        h2 +%= h1;
        h1 = fmix64(h1);
        h2 = fmix64(h2);
        h1 +%= h2;
        h2 +%= h1;
        std.mem.writeInt(u64, out[0..8], h1, .big);
        std.mem.writeInt(u64, out[8..16], h2, .big);
    }
};

// ---------------------------------------------------------------------------
// xxhash (the vendored xxhash.h through xxhash_shim.c)

extern fn zphp_xxh32_reset(s: *anyopaque, seed: u32) void;
extern fn zphp_xxh32_update(s: *anyopaque, data: ?[*]const u8, len: usize) void;
extern fn zphp_xxh32_digest(s: *const anyopaque) u32;
extern fn zphp_xxh64_reset(s: *anyopaque, seed: u64) void;
extern fn zphp_xxh64_update(s: *anyopaque, data: ?[*]const u8, len: usize) void;
extern fn zphp_xxh64_digest(s: *const anyopaque) u64;
extern fn zphp_xxh3_64_reset_seed(s: *anyopaque, seed: u64) void;
extern fn zphp_xxh3_64_reset_secret(s: *anyopaque, secret: [*]const u8, len: usize) void;
extern fn zphp_xxh3_64_update(s: *anyopaque, data: ?[*]const u8, len: usize) void;
extern fn zphp_xxh3_64_digest(s: *const anyopaque) u64;
extern fn zphp_xxh3_128_reset_seed(s: *anyopaque, seed: u64) void;
extern fn zphp_xxh3_128_reset_secret(s: *anyopaque, secret: [*]const u8, len: usize) void;
extern fn zphp_xxh3_128_update(s: *anyopaque, data: ?[*]const u8, len: usize) void;
extern fn zphp_xxh3_128_digest(s: *const anyopaque, out: [*]u8) void;
extern fn zphp_xxh3_ext_secret(s: *const anyopaque) ?*const anyopaque;
extern fn zphp_xxh3_set_ext_secret(s: *anyopaque, secret: ?*const anyopaque) void;

fn ptrOf(data: []const u8) ?[*]const u8 {
    return if (data.len == 0) null else data.ptr;
}

const Xxh32 = struct {
    const Ctx = extern struct {
        total_len_32: u32,
        large_len: u32,
        v: [4]u32,
        mem32: [4]u32,
        memsize: u32,
        reserved: u32,
    };

    fn init(c: *Ctx, a: InitArgs) RuntimeError!void {
        c.* = std.mem.zeroes(Ctx);
        if (try seedOption(a)) |seed| {
            if (seed == .int) {
                zphp_xxh32_reset(c, @truncate(@as(u64, @bitCast(seed.int))));
                return;
            }
            try deprecated(a, "Passing a seed of a type other than int is deprecated because it is the same as setting the seed to 0");
        }
        zphp_xxh32_reset(c, 0);
    }

    fn update(c: *Ctx, data: []const u8) void {
        zphp_xxh32_update(c, ptrOf(data), data.len);
    }

    fn final(out: []u8, c: *Ctx) void {
        std.mem.writeInt(u32, out[0..4], zphp_xxh32_digest(c), .big);
    }

    pub fn valid(c: *Ctx) bool {
        return c.memsize < 16;
    }
};

const Xxh64 = struct {
    const Ctx = extern struct {
        total_len: u64,
        v: [4]u64,
        mem64: [4]u64,
        memsize: u32,
        reserved32: u32,
        reserved64: u64,
    };

    fn init(c: *Ctx, a: InitArgs) RuntimeError!void {
        c.* = std.mem.zeroes(Ctx);
        if (a.options) |_| {
            const seed = try seedOption(a);
            if (seed != null and seed.? == .int) {
                zphp_xxh64_reset(c, @bitCast(seed.?.int));
                return;
            }
            try deprecated(a, "Passing a seed of a type other than int is deprecated because it is the same as setting the seed to 0");
        }
        zphp_xxh64_reset(c, 0);
    }

    fn update(c: *Ctx, data: []const u8) void {
        zphp_xxh64_update(c, ptrOf(data), data.len);
    }

    fn final(out: []u8, c: *Ctx) void {
        std.mem.writeInt(u64, out[0..8], zphp_xxh64_digest(c), .big);
    }

    pub fn valid(c: *Ctx) bool {
        return c.memsize < 32;
    }
};

const secret_size_min = 136;

fn Xxh3(comptime wide: bool) type {
    return struct {
        const Ctx = extern struct {
            state: [576]u8 align(64),
            secret: [256]u8,
        };
        const algo = if (wide) "xxh128" else "xxh3";

        fn resetSeed(c: *Ctx, seed: u64) void {
            if (wide) zphp_xxh3_128_reset_seed(&c.state, seed) else zphp_xxh3_64_reset_seed(&c.state, seed);
        }

        fn init(c: *Ctx, a: InitArgs) RuntimeError!void {
            @memset(&c.state, 0);
            if (a.options) |opts| {
                const seed_opt = option(opts, "seed");
                const secret_opt = option(opts, "secret");
                if (seed_opt != null and secret_opt != null) return throwError(a, algo ++ ": Only one of seed or secret is to be passed for initialization", .{});
                if (seed_opt) |seed| if (seed != .int) try deprecated(a, "Passing a seed of a type other than int is deprecated because it is ignored");
                if (seed_opt != null and seed_opt.? == .int) {
                    resetSeed(c, @bitCast(seed_opt.?.int));
                    return;
                } else if (secret_opt) |secret| {
                    if (secret != .string) try deprecated(a, "Passing a secret of a type other than string is deprecated because it implicitly converts to a string, potentially hiding bugs");
                    const ctx = a.ctx orelse return;
                    if (ctx.vm.pending_exception != null) return;
                    const bytes = try secretBytes(ctx, secret);
                    var len = bytes.len;
                    if (len < secret_size_min) return throwError(a, algo ++ ": Secret length must be >= {d} bytes, {d} bytes passed", .{ secret_size_min, len });
                    if (len > c.secret.len) {
                        len = c.secret.len;
                        const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): " ++ algo ++ ": Secret content exceeding {d} bytes discarded", .{ a.func, c.secret.len });
                        defer ctx.allocator.free(msg);
                        try ctx.vm.emitWarning(msg);
                    }
                    @memcpy(c.secret[0..len], bytes[0..len]);
                    if (wide) zphp_xxh3_128_reset_secret(&c.state, &c.secret, len) else zphp_xxh3_64_reset_secret(&c.state, &c.secret, len);
                    return;
                }
            }
            resetSeed(c, 0);
        }

        fn update(c: *Ctx, data: []const u8) void {
            if (wide) zphp_xxh3_128_update(&c.state, ptrOf(data), data.len) else zphp_xxh3_64_update(&c.state, ptrOf(data), data.len);
        }

        fn final(out: []u8, c: *Ctx) void {
            if (wide) {
                zphp_xxh3_128_digest(&c.state, out.ptr);
            } else {
                std.mem.writeInt(u64, out[0..8], zphp_xxh3_64_digest(&c.state), .big);
            }
        }

        // a state made with a secret points at its context's copy of it
        pub fn fixupCopy(dst: *Ctx, src: *const Ctx) void {
            if (zphp_xxh3_ext_secret(&src.state) == @as(*const anyopaque, @ptrCast(&src.secret))) zphp_xxh3_set_ext_secret(&dst.state, &dst.secret);
        }
    };
}

fn throwError(a: InitArgs, comptime fmt: []const u8, args: anytype) RuntimeError!void {
    const ctx = a.ctx orelse return;
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("Error", msg);
}

// zval_try_get_string for the secret option
fn secretBytes(ctx: *NativeContext, v: Value) RuntimeError![]const u8 {
    switch (v) {
        .string => |s| return s.bytes(),
        .object => |o| {
            if (!ctx.vm.hasMethod(o.class_name, "__toString")) {
                const msg = try std.fmt.allocPrint(ctx.allocator, "Object of class {s} could not be converted to string", .{o.class_name});
                defer ctx.allocator.free(msg);
                try ctx.vm.setPendingException("Error", msg);
                return error.RuntimeError;
            }
            return ctx.vm.objectToString(o);
        },
        .array => {
            try ctx.vm.emitWarning("Array to string conversion");
            return "Array";
        },
        else => {
            var buf = std.ArrayListUnmanaged(u8).empty;
            defer buf.deinit(ctx.allocator);
            try v.format(&buf, ctx.allocator);
            return (try ctx.vm.transientBytes(buf.items)).bytes();
        },
    }
}

// ---------------------------------------------------------------------------
// the ops php registers

const md2_ops = opsFor(Md2, .{ .name = "md2", .digest = 16, .block = 16, .crypto = true, .spec = "b48b16b16b." });
const md4_ops = opsFor(Md4, .{ .name = "md4", .digest = 16, .block = 64, .crypto = true, .spec = "l4l2b64." });
pub const md5_ops = opsFor(Md5, .{ .name = "md5", .digest = 16, .block = 64, .crypto = true, .spec = "llllllb64l16." });
pub const sha1_ops = opsFor(Sha1, .{ .name = "sha1", .digest = 20, .block = 64, .crypto = true, .spec = "l5l2b64." });
const sha224_ops = opsFor(Sha224, .{ .name = "sha224", .digest = 28, .block = 64, .crypto = true, .spec = "l8l2b64." });
const sha256_ops = opsFor(Sha256Full, .{ .name = "sha256", .digest = 32, .block = 64, .crypto = true, .spec = "l8l2b64." });
const sha384_ops = opsFor(Sha384, .{ .name = "sha384", .digest = 48, .block = 128, .crypto = true, .spec = "q8q2b128." });
const sha512_ops = opsFor(Sha512Full, .{ .name = "sha512", .digest = 64, .block = 128, .crypto = true, .spec = "q8q2b128." });
const sha512_256_ops = opsFor(Sha512_256, .{ .name = "sha512/256", .digest = 32, .block = 128, .crypto = true, .spec = "q8q2b128." });
const sha512_224_ops = opsFor(Sha512_224, .{ .name = "sha512/224", .digest = 28, .block = 128, .crypto = true, .spec = "q8q2b128." });
const keccak_spec = "b200IiIIB";
const sha3_224_ops = opsFor(Sha3(224), .{ .name = "sha3-224", .digest = 28, .block = 144, .crypto = true, .spec = keccak_spec, .magic = keccak_magic });
const sha3_256_ops = opsFor(Sha3(256), .{ .name = "sha3-256", .digest = 32, .block = 136, .crypto = true, .spec = keccak_spec, .magic = keccak_magic });
const sha3_384_ops = opsFor(Sha3(384), .{ .name = "sha3-384", .digest = 48, .block = 104, .crypto = true, .spec = keccak_spec, .magic = keccak_magic });
const sha3_512_ops = opsFor(Sha3(512), .{ .name = "sha3-512", .digest = 64, .block = 72, .crypto = true, .spec = keccak_spec, .magic = keccak_magic });
const ripemd128_ops = opsFor(Ripemd(4), .{ .name = "ripemd128", .digest = 16, .block = 64, .crypto = true, .spec = "l4l2b64." });
const ripemd160_ops = opsFor(Ripemd(5), .{ .name = "ripemd160", .digest = 20, .block = 64, .crypto = true, .spec = "l5l2b64." });
const ripemd256_ops = opsFor(Ripemd(8), .{ .name = "ripemd256", .digest = 32, .block = 64, .crypto = true, .spec = "l8l2b64." });
const ripemd320_ops = opsFor(Ripemd(10), .{ .name = "ripemd320", .digest = 40, .block = 64, .crypto = true, .spec = "l10l2b64." });
const whirlpool_ops = opsFor(Whirlpool, .{ .name = "whirlpool", .digest = 64, .block = 64, .crypto = true, .spec = "q8b32iib64." });
const tiger_spec = "q3qb64l";
const tiger3_128_ops = opsFor(Tiger(0, 16), .{ .name = "tiger128,3", .digest = 16, .block = 64, .crypto = true, .spec = tiger_spec });
const tiger3_160_ops = opsFor(Tiger(0, 20), .{ .name = "tiger160,3", .digest = 20, .block = 64, .crypto = true, .spec = tiger_spec });
const tiger3_192_ops = opsFor(Tiger(0, 24), .{ .name = "tiger192,3", .digest = 24, .block = 64, .crypto = true, .spec = tiger_spec });
const tiger4_128_ops = opsFor(Tiger(1, 16), .{ .name = "tiger128,4", .digest = 16, .block = 64, .crypto = true, .spec = tiger_spec });
const tiger4_160_ops = opsFor(Tiger(1, 20), .{ .name = "tiger160,4", .digest = 20, .block = 64, .crypto = true, .spec = tiger_spec });
const tiger4_192_ops = opsFor(Tiger(1, 24), .{ .name = "tiger192,4", .digest = 24, .block = 64, .crypto = true, .spec = tiger_spec });
const snefru_ops = opsFor(Snefru, .{ .name = "snefru", .digest = 32, .block = 32, .crypto = true, .spec = "l16l2bb32" });
const gost_ops = opsFor(Gost(false), .{ .name = "gost", .digest = 32, .block = 32, .crypto = true, .spec = "l16l2bb32" });
const gost_crypto_ops = opsFor(Gost(true), .{ .name = "gost-crypto", .digest = 32, .block = 32, .crypto = true, .spec = "l16l2bb32" });
const adler32_ops = opsFor(Adler32, .{ .name = "adler32", .digest = 4, .block = 4, .crypto = false, .spec = "l." });
const crc32_ops = opsFor(Crc32(.bzip2), .{ .name = "crc32", .digest = 4, .block = 4, .crypto = false, .spec = "l." });
const crc32b_ops = opsFor(Crc32(.ieee), .{ .name = "crc32b", .digest = 4, .block = 4, .crypto = false, .spec = "l." });
const crc32c_ops = opsFor(Crc32(.castagnoli), .{ .name = "crc32c", .digest = 4, .block = 4, .crypto = false, .spec = "l." });
const fnv132_ops = opsFor(Fnv32(false), .{ .name = "fnv132", .digest = 4, .block = 4, .crypto = false, .spec = "l." });
const fnv1a32_ops = opsFor(Fnv32(true), .{ .name = "fnv1a32", .digest = 4, .block = 4, .crypto = false, .spec = "l." });
const fnv164_ops = opsFor(Fnv64(false), .{ .name = "fnv164", .digest = 8, .block = 4, .crypto = false, .spec = "q." });
const fnv1a64_ops = opsFor(Fnv64(true), .{ .name = "fnv1a64", .digest = 8, .block = 4, .crypto = false, .spec = "q." });
const joaat_ops = opsFor(Joaat, .{ .name = "joaat", .digest = 4, .block = 4, .crypto = false, .spec = "l." });
const murmur3a_ops = opsFor(Murmur3a, .{ .name = "murmur3a", .digest = 4, .block = 4, .crypto = false, .spec = "lll" });
const murmur3c_ops = opsFor(Murmur3c, .{ .name = "murmur3c", .digest = 16, .block = 4, .crypto = false, .spec = "lllllllll" });
const murmur3f_ops = opsFor(Murmur3f, .{ .name = "murmur3f", .digest = 16, .block = 8, .crypto = false, .spec = "qqqql" });
const xxh32_ops = opsFor(Xxh32, .{ .name = "xxh32", .digest = 4, .block = 4, .crypto = false, .spec = "llllllllllll" });
const xxh64_ops = opsFor(Xxh64, .{ .name = "xxh64", .digest = 8, .block = 8, .crypto = false, .spec = "qqqqqqqqqllq" });
const xxh3_ops = opsFor(Xxh3(false), .{ .name = "xxh3", .digest = 8, .block = 8, .crypto = false, .spec = null });
const xxh128_ops = opsFor(Xxh3(true), .{ .name = "xxh128", .digest = 16, .block = 8, .crypto = false, .spec = null });

const haval_ops = blk: {
    var ops: [15]Ops = undefined;
    for (.{ 3, 4, 5 }, 0..) |p, pi| {
        for (.{ 128, 160, 192, 224, 256 }, 0..) |b, bi| {
            ops[pi * 5 + bi] = opsFor(Haval(p, b), .{ .name = std.fmt.comptimePrint("haval{d},{d}", .{ b, p }), .digest = b / 8, .block = 128, .crypto = true, .spec = "l8l2b128" });
        }
    }
    break :blk ops;
};
