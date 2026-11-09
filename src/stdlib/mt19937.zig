// PHP-compatible MT19937 + range-conversion. matches PHP 8.x byte-for-byte for
// any given seed and mt_rand($min, $max) call so deterministic test fixtures
// reproduce, in both of php's modes: MT_RAND_MT19937 and the deprecated
// MT_RAND_PHP, which reloads with php's old twist and scales mt_rand ranges
// as RAND_RANGE_BADSCALING did

const std = @import("std");

pub const N: usize = 624;
const M: usize = 397;
const MATRIX_A: u32 = 0x9908b0df;
const UPPER_MASK: u32 = 0x80000000;
const LOWER_MASK: u32 = 0x7fffffff;

pub const Mode = enum(u8) { mt19937 = 0, php = 1 };

pub const Mt19937 = struct {
    state: [N]u32 = undefined,
    index: usize = N,
    mode: Mode = .mt19937,

    pub fn seed(self: *Mt19937, s: u32) void {
        self.state[0] = s;
        var i: usize = 1;
        while (i < N) : (i += 1) {
            const prev = self.state[i - 1];
            self.state[i] = @as(u32, @truncate(@as(u64, 1812433253) *% @as(u64, prev ^ (prev >> 30)) +% @as(u64, i)));
        }
        self.index = N;
    }

    // twist(m, u, v): MT19937 takes the low bit of v, php's legacy twist that
    // of u
    fn twist(self: *const Mt19937, m: u32, u: u32, v: u32) u32 {
        const y = (u & UPPER_MASK) | (v & LOWER_MASK);
        const odd = if (self.mode == .php) u & 1 else v & 1;
        return m ^ (y >> 1) ^ (if (odd != 0) MATRIX_A else @as(u32, 0));
    }

    fn generateBlock(self: *Mt19937) void {
        var i: usize = 0;
        while (i < N - M) : (i += 1) {
            self.state[i] = self.twist(self.state[i + M], self.state[i], self.state[i + 1]);
        }
        while (i < N - 1) : (i += 1) {
            self.state[i] = self.twist(self.state[i + M - N], self.state[i], self.state[i + 1]);
        }
        self.state[N - 1] = self.twist(self.state[M - 1], self.state[N - 1], self.state[0]);
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

    // mt_rand($min, $max) and rand($min, $max): php_mt_rand_common, which in
    // MT_RAND_PHP mode scales a 31-bit value into the range
    pub fn nextCommon(self: *Mt19937, min: i64, max: i64) i64 {
        if (self.mode == .mt19937) return self.nextRange(min, max);
        const r: f64 = @floatFromInt(self.nextU32() >> 1);
        const width = @as(f64, @floatFromInt(max)) - @as(f64, @floatFromInt(min)) + 1.0;
        const offset: u64 = @intFromFloat(width * (r / 2147483648.0));
        return @bitCast(offset +% @as(u64, @bitCast(min)));
    }

    // PHP's range conversion for mt_rand($min, $max). uses the full 32-bit
    // mt19937 output (NOT the 31-bit form mt_rand() returns without arguments)
    // and rejection-samples to remove modulo bias. matches php_random_range32
    pub fn nextRange(self: *Mt19937, min: i64, max: i64) i64 {
        // php draws a number even for an empty range
        if (min == max) {
            _ = self.nextU32();
            return min;
        }
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
