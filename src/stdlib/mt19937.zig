// PHP-compatible MT19937 + range-conversion. matches PHP 8.x byte-for-byte for
// any given seed and mt_rand($min, $max) call so deterministic test fixtures
// reproduce. PHP's RAND_RANGE_BADSCALING legacy path isn't implemented; default
// PHP 7.1+ mode is the standard rejection-sampled mode this file implements.

const std = @import("std");

pub const N: usize = 624;
const M: usize = 397;
const MATRIX_A: u32 = 0x9908b0df;
const UPPER_MASK: u32 = 0x80000000;
const LOWER_MASK: u32 = 0x7fffffff;

pub const Mt19937 = struct {
    state: [N]u32 = undefined,
    index: usize = N,

    pub fn seed(self: *Mt19937, s: u32) void {
        self.state[0] = s;
        var i: usize = 1;
        while (i < N) : (i += 1) {
            const prev = self.state[i - 1];
            self.state[i] = @as(u32, @truncate(@as(u64, 1812433253) *% @as(u64, prev ^ (prev >> 30)) +% @as(u64, i)));
        }
        self.index = N;
    }

    fn generateBlock(self: *Mt19937) void {
        var i: usize = 0;
        while (i < N - M) : (i += 1) {
            const y = (self.state[i] & UPPER_MASK) | (self.state[i + 1] & LOWER_MASK);
            self.state[i] = self.state[i + M] ^ (y >> 1) ^ (if ((y & 1) != 0) MATRIX_A else @as(u32, 0));
        }
        while (i < N - 1) : (i += 1) {
            const y = (self.state[i] & UPPER_MASK) | (self.state[i + 1] & LOWER_MASK);
            self.state[i] = self.state[i + M - N] ^ (y >> 1) ^ (if ((y & 1) != 0) MATRIX_A else @as(u32, 0));
        }
        const y_last = (self.state[N - 1] & UPPER_MASK) | (self.state[0] & LOWER_MASK);
        self.state[N - 1] = self.state[M - 1] ^ (y_last >> 1) ^ (if ((y_last & 1) != 0) MATRIX_A else @as(u32, 0));
        self.index = 0;
    }

    pub fn nextU32(self: *Mt19937) u32 {
        if (self.index >= N) self.generateBlock();
        var y = self.state[self.index];
        self.index += 1;
        y ^= y >> 11;
        y ^= (y << 7) & 0x9d2c5680;
        y ^= (y << 15) & 0xefc60000;
        y ^= y >> 18;
        return y;
    }

    // PHP's mt_rand returns a 31-bit value
    pub fn next31(self: *Mt19937) i64 {
        return @as(i64, self.nextU32() >> 1);
    }

    // PHP's range conversion for mt_rand($min, $max). uses the full 32-bit
    // mt19937 output (NOT the 31-bit form mt_rand() returns without arguments)
    // and rejection-samples to remove modulo bias. matches php_random_range32
    pub fn nextRange(self: *Mt19937, min: i64, max: i64) i64 {
        if (min == max) return min;
        const umax_raw: u64 = @intCast(max - min);
        // mt_rand($min, $max) where max-min == UINT32_MAX returns the raw
        // 32-bit value directly
        if (umax_raw == 0xffffffff) {
            return min + @as(i64, self.nextU32());
        }
        const span: u64 = umax_raw + 1;
        // power-of-two fast path: PHP just masks
        if ((span & (span - 1)) == 0) {
            return min + @as(i64, @intCast(@as(u64, self.nextU32()) & (span - 1)));
        }
        const limit: u32 = @intCast(0xffffffff - (0xffffffff % span) - 1);
        while (true) {
            const r = self.nextU32();
            if (r <= limit) {
                return min + @as(i64, @intCast(@as(u64, r) % span));
            }
        }
    }
};

test "mt19937 vectors" {
    var m = Mt19937{};
    m.seed(42);
    // PHP: mt_srand(42); mt_rand() -> 1608637542 (full 32-bit), but mt_rand
    // without args returns 31-bit. mt_rand(0, 99) with seed 42 -> 42, 67
    try std.testing.expectEqual(@as(i64, 42), m.nextRange(0, 99));
    try std.testing.expectEqual(@as(i64, 67), m.nextRange(0, 99));
}
