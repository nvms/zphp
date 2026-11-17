// mbstring's Shift_JIS (libmbfl's mb_sjis_to_wchar and mb_wchar_to_sjis):
// JIS X 0208 in two bytes, ascii and half-width katakana in one
const std = @import("std");
const t = @import("jis_tables_generated.zig");

// the next code point of `bytes` from `at`, and how many bytes it took;
// null for a sequence php reads as bad input
pub const Decoded = struct { cp: ?u21, len: usize };

pub fn decode(bytes: []const u8, at: usize) Decoded {
    const c = bytes[at];
    if (c <= 0x7f) return .{ .cp = c, .len = 1 };
    if (c >= 0xa1 and c <= 0xdf) return .{ .cp = 0xfec0 + @as(u21, c), .len = 1 };
    if (at + 1 >= bytes.len) return .{ .cp = null, .len = 1 };
    const c2 = bytes[at + 1];
    // the tables give an out of range index for a bad lead or trail byte
    const w: u32 = @as(u32, t.sjis_decode1[c]) + @as(u32, t.sjis_decode2[c2]);
    if (w < t.jisx0208_ucs.len) {
        const u = t.jisx0208_ucs[w];
        return .{ .cp = if (u == 0) null else u, .len = 2 };
    }
    // a lead byte that can't start a character leaves its next byte to be
    // read again
    if (c == 0x80 or c == 0xa0 or c > 0xef) return .{ .cp = null, .len = 1 };
    return .{ .cp = null, .len = 2 };
}

// appends the Shift_JIS bytes for cp; false when it has none
pub fn encode(out: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, cp: u21) !bool {
    var s: u32 = 0;
    if (cp >= t.ucs_a1_jis_min and cp < t.ucs_a1_jis_min + t.ucs_a1_jis.len) {
        s = t.ucs_a1_jis[cp - t.ucs_a1_jis_min];
    } else if (cp >= t.ucs_a2_jis_min and cp < t.ucs_a2_jis_min + t.ucs_a2_jis.len) {
        s = t.ucs_a2_jis[cp - t.ucs_a2_jis_min];
    } else if (cp >= t.ucs_i_jis_min and cp < t.ucs_i_jis_min + t.ucs_i_jis.len) {
        s = t.ucs_i_jis[cp - t.ucs_i_jis_min];
    } else if (cp >= t.ucs_r_jis_min and cp < t.ucs_r_jis_min + t.ucs_r_jis.len) {
        s = t.ucs_r_jis[cp - t.ucs_r_jis_min];
    }
    if (s == 0) {
        s = switch (cp) {
            0xa5 => 0x216f, // yen sign as the fullwidth one
            0xaf, 0x203e => 0x2131,
            0xff3c => 0x2140,
            0x2225 => 0x2142,
            0xff0d => 0x215d,
            0xffe0 => 0x2171,
            0xffe1 => 0x2172,
            0xffe2 => 0x224c,
            0 => 0,
            else => return false,
        };
    } else if (s >= 0x8080) return false; // JIS X 0212 has no Shift_JIS form
    if (s <= 0xff) {
        try out.append(allocator, @intCast(s));
        return true;
    }
    // SJIS_ENCODE
    const c1 = (s >> 8) & 0xff;
    const c2 = s & 0xff;
    const s1 = ((c1 - 1) >> 1) + @as(u32, if (c1 < 0x5f) 0x71 else 0xb1);
    var s2 = c2;
    if (c1 & 1 != 0) {
        if (c2 < 0x60) s2 -= 1;
        s2 += 0x20;
    } else s2 += 0x7e;
    try out.appendSlice(allocator, &.{ @intCast(s1), @intCast(s2) });
    return true;
}

test "Shift_JIS round trips kanji, kana and ascii" {
    const a = std.testing.allocator;
    const text = "\x95\x5c\x8e\x9a\xb1A";
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(a);
    var i: usize = 0;
    var cps: [8]u21 = undefined;
    var n: usize = 0;
    while (i < text.len) {
        const d = decode(text, i);
        cps[n] = d.cp.?;
        n += 1;
        i += d.len;
    }
    try std.testing.expectEqual(@as(u21, 0x8868), cps[0]); // 表
    try std.testing.expectEqual(@as(u21, 0x5b57), cps[1]); // 字
    try std.testing.expectEqual(@as(u21, 0xff71), cps[2]);
    for (cps[0..n]) |cp| try std.testing.expect(try encode(&out, a, cp));
    try std.testing.expectEqualStrings(text, out.items);
}
