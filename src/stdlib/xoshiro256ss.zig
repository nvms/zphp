// Xoshiro256** (StarStar) - PHP-compatible. uses the same internal update step
// as Zig's Xoshiro256 but with the **-scrambler PHP picks (rotl(s[1] * 5, 7) * 9)
// instead of the ++-scrambler Zig stdlib defaults to. seeding from a single
// 64-bit integer follows PHP's path: feed through SplitMix64 to fill the four
// state words

const std = @import("std");

pub const Xoshiro256ss = struct {
    s: [4]u64 = .{ 0, 0, 0, 0 },

    pub fn seedInt(self: *Xoshiro256ss, init_s: u64) void {
        var gen = std.Random.SplitMix64.init(init_s);
        self.s[0] = gen.next();
        self.s[1] = gen.next();
        self.s[2] = gen.next();
        self.s[3] = gen.next();
    }

    // PHP also accepts a 32-byte string seed which fills the state directly.
    // accept >=32 bytes; bytes are interpreted little-endian per u64
    pub fn seedBytes(self: *Xoshiro256ss, seed: []const u8) bool {
        if (seed.len < 32) return false;
        self.s[0] = std.mem.readInt(u64, seed[0..8], .little);
        self.s[1] = std.mem.readInt(u64, seed[8..16], .little);
        self.s[2] = std.mem.readInt(u64, seed[16..24], .little);
        self.s[3] = std.mem.readInt(u64, seed[24..32], .little);
        return true;
    }

    pub fn next(self: *Xoshiro256ss) u64 {
        const result = std.math.rotl(u64, self.s[1] *% 5, 7) *% 9;
        const t = self.s[1] << 17;
        self.s[2] ^= self.s[0];
        self.s[3] ^= self.s[1];
        self.s[1] ^= self.s[2];
        self.s[0] ^= self.s[3];
        self.s[2] ^= t;
        self.s[3] = std.math.rotl(u64, self.s[3], 45);
        return result;
    }
};
