// PCG OneSeq 128 XSL RR 64 - PHP-compatible. 128-bit state, fixed increment.
// reference: https://www.pcg-random.org/. matches PHP's
// Random\Engine\PcgOneseq128XslRr64 byte-for-byte for both int and 16-byte seeds.

const std = @import("std");

pub const PcgOneseq128 = struct {
    state: u128 = 0,

    const MULT: u128 = (@as(u128, 0x2360ed051fc65da4) << 64) | 0x4385df649fccf645;
    const INC: u128 = (@as(u128, 0x5851f42d4c957f2d) << 64) | 0x14057b7ef767814f;

    fn step(self: *PcgOneseq128) void {
        self.state = self.state *% MULT +% INC;
    }

    fn seed128(self: *PcgOneseq128, seed: u128) void {
        // matches php_random_pcgoneseq128xslrr64_seed128: state=0, step, +=seed, step
        self.state = 0;
        self.step();
        self.state +%= seed;
        self.step();
    }

    pub fn seedInt(self: *PcgOneseq128, seed: u64) void {
        // PHP zero-extends the int to u128: u128_constant(0, seed)
        self.seed128(@as(u128, seed));
    }

    // 16-byte seed: each 8-byte half is read little-endian. PHP packs t[0]
    // (from bytes 0-7) as the HIGH qword of the u128 and t[1] (bytes 8-15)
    // as the LOW qword
    pub fn seedBytes(self: *PcgOneseq128, seed: []const u8) bool {
        if (seed.len < 16) return false;
        const hi = std.mem.readInt(u64, seed[0..8], .little);
        const lo = std.mem.readInt(u64, seed[8..16], .little);
        self.seed128((@as(u128, hi) << 64) | @as(u128, lo));
        return true;
    }

    pub fn next(self: *PcgOneseq128) u64 {
        self.step();
        const hi: u64 = @intCast(self.state >> 64);
        const lo: u64 = @truncate(self.state);
        const rot: u6 = @truncate(@as(u64, @intCast(self.state >> 122)));
        const x = hi ^ lo;
        return std.math.rotr(u64, x, rot);
    }
};
