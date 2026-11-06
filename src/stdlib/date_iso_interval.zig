//! timelib_strtointerval, ported from php's copy of timelib
//! (ext/date/lib/parse_iso_intervals.re): the ISO 8601 interval strings
//! DatePeriod accepts ("R4/2012-07-01T00:00:00Z/P7D"). the scanner tries every
//! rule at each position and takes the longest match, the earlier rule on a
//! tie, as re2c does; separators are skipped and anything else is an error

const std = @import("std");

pub const unset: i64 = -9999999;

pub const Date = struct {
    y: i64 = unset,
    m: i64 = unset,
    d: i64 = unset,
    h: i64 = unset,
    i: i64 = unset,
    s: i64 = unset,
};

pub const Period = struct {
    y: i64 = 0,
    m: i64 = 0,
    d: i64 = 0,
    h: i64 = 0,
    i: i64 = 0,
    s: i64 = 0,
};

pub const Interval = struct {
    begin: ?Date = null,
    end: ?Date = null,
    period: ?Period = null,
    // 0 unless the string has an R part
    recurrences: i64 = 0,
    errors: usize = 0,
};

const Rule = enum { recurrences, datetime, period, combinedrep, separator, end_of_line, any };

pub fn parse(input: []const u8) Interval {
    var out: Interval = .{};
    const s = std.mem.trim(u8, input, " \t\n\r\x0b\x0c");
    if (s.len == 0) {
        out.errors += 1;
        return out;
    }
    var have_date = false;
    var have_period = false;
    var begin: Date = .{};
    var end: Date = .{};
    var period: Period = .{};
    var pos: usize = 0;
    while (pos < s.len) {
        const rest = s[pos..];
        const hit = longestMatch(rest);
        const token = rest[0..hit.len];
        switch (hit.rule) {
            .recurrences => {
                var p: usize = 1;
                out.recurrences = unsignedNumber(token, &p, 9);
            },
            .datetime => {
                const current = if (have_date or have_period) &end else &begin;
                if (have_date or have_period) out.end = .{} else out.begin = .{};
                var p: usize = 0;
                current.y = number(token, &p, 4);
                current.m = number(token, &p, 2);
                current.d = number(token, &p, 2);
                current.h = number(token, &p, 2);
                current.i = number(token, &p, 2);
                current.s = number(token, &p, 2);
                have_date = true;
            },
            .period => {
                var p: usize = 1;
                var in_time = false;
                while (true) {
                    if (p < token.len and token[p] == 'T') {
                        in_time = true;
                        p += 1;
                    }
                    if (p >= token.len) {
                        out.errors += 1;
                        break;
                    }
                    const nr = unsignedNumber(token, &p, 12);
                    switch (if (p < token.len) token[p] else 0) {
                        'Y' => period.y = nr,
                        'W' => period.d += nr * 7,
                        'D' => period.d += nr,
                        'H' => period.h = nr,
                        'S' => period.s = nr,
                        'M' => if (in_time) {
                            period.i = nr;
                        } else {
                            period.m = nr;
                        },
                        else => out.errors += 1,
                    }
                    p += 1;
                    if (out.errors > 0 or p >= token.len) break;
                }
                have_period = true;
            },
            .combinedrep => {
                var p: usize = 0;
                period.y = unsignedNumber(token, &p, 4);
                p += 1;
                period.m = unsignedNumber(token, &p, 2);
                p += 1;
                period.d = unsignedNumber(token, &p, 2);
                p += 1;
                period.h = unsignedNumber(token, &p, 2);
                p += 1;
                period.i = unsignedNumber(token, &p, 2);
                p += 1;
                period.s = unsignedNumber(token, &p, 2);
                have_period = true;
            },
            .separator, .end_of_line => {},
            .any => out.errors += 1,
        }
        pos += hit.len;
    }
    if (out.begin != null) out.begin = begin;
    if (out.end != null) out.end = end;
    if (have_period) out.period = period;
    return out;
}

const Hit = struct { rule: Rule, len: usize };

fn longestMatch(rest: []const u8) Hit {
    var best: Hit = .{ .rule = .any, .len = 1 };
    const candidates = [_]struct { rule: Rule, len: ?usize }{
        .{ .rule = .recurrences, .len = matchRecurrences(rest) },
        .{ .rule = .datetime, .len = matchDatetime(rest) },
        .{ .rule = .period, .len = matchPeriod(rest) },
        .{ .rule = .combinedrep, .len = matchCombined(rest) },
        .{ .rule = .separator, .len = if (std.mem.indexOfScalar(u8, " .,\t/", rest[0]) != null) 1 else null },
        .{ .rule = .end_of_line, .len = if (rest[0] == 0 or rest[0] == '\n') 1 else null },
    };
    var found = false;
    for (candidates) |c| {
        const len = c.len orelse continue;
        if (!found or len > best.len) {
            best = .{ .rule = c.rule, .len = len };
            found = true;
        }
    }
    return best;
}

fn digits(s: []const u8, at: usize) usize {
    var n: usize = 0;
    while (at + n < s.len and std.ascii.isDigit(s[at + n])) n += 1;
    return n;
}

// "R" number
fn matchRecurrences(s: []const u8) ?usize {
    if (s[0] != 'R') return null;
    const n = digits(s, 1);
    return if (n > 0) 1 + n else null;
}

// a fixed sequence of two-digit fields, each checked by range
fn twoDigits(s: []const u8, at: usize, comptime ok: fn (u8, u8) bool) bool {
    return at + 2 <= s.len and std.ascii.isDigit(s[at]) and std.ascii.isDigit(s[at + 1]) and ok(s[at], s[at + 1]);
}

fn hour24(a: u8, b: u8) bool {
    return a == '0' or a == '1' or (a == '2' and b <= '4');
}

fn minute(a: u8, _: u8) bool {
    return a <= '5';
}

fn monthNonZero(a: u8, b: u8) bool {
    return (a == '0' and b != '0') or (a == '1' and b <= '2');
}

fn monthAny(a: u8, b: u8) bool {
    return a == '0' or (a == '1' and b <= '2');
}

fn dayNonZero(a: u8, b: u8) bool {
    return (a == '0' and b != '0') or a == '1' or a == '2' or (a == '3' and b <= '1');
}

fn dayAny(a: u8, b: u8) bool {
    return a == '0' or a == '1' or a == '2' or (a == '3' and b <= '1');
}

fn year4(s: []const u8, at: usize) bool {
    return digits(s, at) >= 4;
}

// datetimebasic: 20120701T000000Z, datetimeextended: 2012-07-01T00:00:00Z
fn matchDatetime(s: []const u8) ?usize {
    if (!year4(s, 0)) return null;
    if (twoDigits(s, 4, monthNonZero) and twoDigits(s, 6, dayNonZero) and s.len > 8 and s[8] == 'T' and
        twoDigits(s, 9, hour24) and twoDigits(s, 11, minute) and twoDigits(s, 13, minute) and s.len > 15 and s[15] == 'Z') return 16;
    if (s.len > 4 and s[4] == '-' and twoDigits(s, 5, monthNonZero) and s.len > 7 and s[7] == '-' and twoDigits(s, 8, dayNonZero) and
        s.len > 10 and s[10] == 'T' and twoDigits(s, 11, hour24) and s.len > 13 and s[13] == ':' and twoDigits(s, 14, minute) and
        s.len > 16 and s[16] == ':' and twoDigits(s, 17, minute) and s.len > 19 and s[19] == 'Z') return 20;
    return null;
}

// "P" (number "Y")? (number "M")? (number "W")? (number "D")?
// ("T" (number "H")? (number "M")? (number "S")?)?
fn matchPeriod(s: []const u8) ?usize {
    if (s[0] != 'P') return null;
    var p: usize = 1;
    for ("YMWD") |unit| p = optionalUnit(s, p, unit);
    if (p < s.len and s[p] == 'T') {
        p += 1;
        for ("HMS") |unit| p = optionalUnit(s, p, unit);
    }
    return p;
}

fn optionalUnit(s: []const u8, p: usize, unit: u8) usize {
    const n = digits(s, p);
    if (n > 0 and p + n < s.len and s[p + n] == unit) return p + n + 1;
    return p;
}

// "P" year4 "-" monthlzz "-" daylzz "T" hour24lz ":" minutelz ":" secondlz
fn matchCombined(s: []const u8) ?usize {
    if (s[0] != 'P' or !year4(s, 1)) return null;
    if (s.len > 5 and s[5] == '-' and twoDigits(s, 6, monthAny) and s.len > 8 and s[8] == '-' and twoDigits(s, 9, dayAny) and
        s.len > 11 and s[11] == 'T' and twoDigits(s, 12, hour24) and s.len > 14 and s[14] == ':' and twoDigits(s, 15, minute) and
        s.len > 17 and s[17] == ':' and twoDigits(s, 18, minute)) return 20;
    return null;
}

// timelib_get_nr: skip to the next digits and read at most max_length of them
fn number(s: []const u8, p: *usize, max_length: usize) i64 {
    while (p.* < s.len and !std.ascii.isDigit(s[p.*])) p.* += 1;
    if (p.* >= s.len) return unset;
    const begin = p.*;
    while (p.* < s.len and std.ascii.isDigit(s[p.*]) and p.* - begin < max_length) p.* += 1;
    return std.fmt.parseInt(i64, s[begin..p.*], 10) catch 0;
}

// timelib_get_unsigned_nr: a number with any leading signs applied
fn unsignedNumber(s: []const u8, p: *usize, max_length: usize) i64 {
    while (p.* < s.len and !std.ascii.isDigit(s[p.*]) and s[p.*] != '+' and s[p.*] != '-') p.* += 1;
    if (p.* >= s.len) return unset;
    var dir: i64 = 1;
    while (p.* < s.len and (s[p.*] == '+' or s[p.*] == '-')) : (p.* += 1) {
        if (s[p.*] == '-') dir = -dir;
    }
    return dir * number(s, p, max_length);
}

test "iso intervals" {
    const a = parse("R4/2012-07-01T00:00:00Z/P7D");
    try std.testing.expectEqual(@as(usize, 0), a.errors);
    try std.testing.expectEqual(@as(i64, 4), a.recurrences);
    try std.testing.expectEqual(@as(i64, 2012), a.begin.?.y);
    try std.testing.expectEqual(@as(i64, 7), a.period.?.d);
    const b = parse("2008-03-01T13:00:00Z/P1Y2M10DT2H30M/2009-01-01T00:00:00Z");
    try std.testing.expectEqual(@as(i64, 2009), b.end.?.y);
    try std.testing.expectEqual(@as(i64, 30), b.period.?.i);
    try std.testing.expect(parse("R2/x").errors > 0);
    try std.testing.expect(parse("P").errors > 0);
}
