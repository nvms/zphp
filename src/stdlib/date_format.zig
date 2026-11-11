// php's date_format() (ext/date/php_date.c): the format characters of
// date(), gmdate() and DateTimeInterface::format(), over a broken-down time
const std = @import("std");
const dp = @import("date_parse.zig");
const Allocator = std.mem.Allocator;

// a time as date_format reads it: wall-clock fields, the instant, and (for a
// local time) the offset in effect with its dst flag and abbreviation
pub const Local = struct {
    y: i64,
    m: i64,
    d: i64,
    h: i64,
    i: i64,
    s: i64,
    us: i64 = 0,
    sse: i64,
    // false for gmdate(): the zone characters print utc's
    localtime: bool = true,
    zone_type: u8 = dp.ZONETYPE_ID,
    offset: i64 = 0,
    is_dst: bool = false,
    // the zone's abbreviation, or "GMT+hhmm" for an offset zone
    abbr: []const u8 = "UTC",
    // the zone id, for 'e'
    tz_name: []const u8 = "UTC",
};

// the wall-clock fields of an instant at an offset (timelib_unixtime2gmt
// after adding the offset)
pub fn fieldsAt(sse: i64, offset: i64, out: *Local) void {
    const local = sse +% offset;
    const days = @divFloor(local, 86400);
    const secs = @mod(local, 86400);
    dp.dateFromEpochDays(days, &out.y, &out.m, &out.d);
    out.h = @divTrunc(secs, 3600);
    out.i = @divTrunc(@rem(secs, 3600), 60);
    out.s = @rem(secs, 60);
    out.sse = sse;
}

const day_full = [_][]const u8{ "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" };
const day_short = [_][]const u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
const mon_full = [_][]const u8{ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };
const mon_short = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

fn englishSuffix(n: i64) []const u8 {
    if (n >= 10 and n <= 19) return "th";
    return switch (@rem(n, 10)) {
        1 => "st",
        2 => "nd",
        3 => "rd",
        else => "th",
    };
}

fn monthIndex(m: i64) usize {
    return @intCast(std.math.clamp(m, 1, 12) - 1);
}

// printf's "%0<w>d": the sign goes before the zero padding
fn padded(out: *std.ArrayListUnmanaged(u8), a: Allocator, v: i64, width: usize) !void {
    var buf: [24]u8 = undefined;
    const digits = std.fmt.bufPrint(&buf, "{d}", .{@abs(v)}) catch unreachable;
    if (v < 0) try out.append(a, '-');
    const used = digits.len + @intFromBool(v < 0);
    if (used < width) try out.appendNTimes(a, '0', width - used);
    try out.appendSlice(a, digits);
}

// "%c%02d%s%02d": the offset as php's 'O' and 'P' print it, with c's
// truncating division for the hours and minutes
fn offsetText(out: *std.ArrayListUnmanaged(u8), a: Allocator, t: *const Local, colon: bool) !void {
    const off: i64 = if (t.localtime) t.offset else 0;
    try out.append(a, if (off < 0) '-' else '+');
    try padded(out, a, @intCast(@abs(@divTrunc(off, 3600))), 2);
    if (colon) try out.append(a, ':');
    try padded(out, a, @intCast(@abs(@divTrunc(@rem(off, 3600), 60))), 2);
}

pub fn format(a: Allocator, fmt: []const u8, t_in: *const Local) ![]u8 {
    // an offset zone's abbreviation is "GMT+hhmm"
    var local = t_in.*;
    const t = &local;
    var gmt_buf: [24]u8 = undefined;
    if (t.localtime and t.zone_type == dp.ZONETYPE_OFFSET) {
        t.abbr = std.fmt.bufPrint(&gmt_buf, "GMT{c}{d:0>2}{d:0>2}", .{ @as(u8, if (t.offset < 0) '-' else '+'), @abs(@divTrunc(t.offset, 3600)), @abs(@divTrunc(@rem(t.offset, 3600), 60)) }) catch "GMT+0000";
    }
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(a);
    var week_set = false;
    var iso_week: i64 = 0;
    var iso_year: i64 = 0;
    var i: usize = 0;
    while (i < fmt.len) : (i += 1) {
        switch (fmt[i]) {
            'd' => try padded(&out, a, t.d, 2),
            'D' => try out.appendSlice(a, day_short[@intCast(dp.dayOfWeek(t.y, t.m, t.d))]),
            'j' => try out.print(a, "{d}", .{t.d}),
            'l' => try out.appendSlice(a, day_full[@intCast(dp.dayOfWeek(t.y, t.m, t.d))]),
            'S' => try out.appendSlice(a, englishSuffix(t.d)),
            'w' => try out.print(a, "{d}", .{dp.dayOfWeek(t.y, t.m, t.d)}),
            'N' => try out.print(a, "{d}", .{dp.isoDayOfWeek(t.y, t.m, t.d)}),
            'z' => try out.print(a, "{d}", .{dp.dayOfYear(t.y, t.m, t.d)}),
            'W', 'o' => {
                if (!week_set) {
                    dp.isoWeekFromDate(t.y, t.m, t.d, &iso_week, &iso_year);
                    week_set = true;
                }
                if (fmt[i] == 'W') try padded(&out, a, iso_week, 2) else try out.print(a, "{d}", .{iso_year});
            },
            'F' => try out.appendSlice(a, mon_full[monthIndex(t.m)]),
            'm' => try padded(&out, a, t.m, 2),
            'M' => try out.appendSlice(a, mon_short[monthIndex(t.m)]),
            'n' => try out.print(a, "{d}", .{t.m}),
            't' => try out.print(a, "{d}", .{dp.daysInMonth(t.y, t.m)}),
            'L' => try out.append(a, if (dp.isLeap(t.y)) '1' else '0'),
            'y' => try padded(&out, a, @rem(t.y, 100), 2),
            'Y', 'x', 'X' => {
                const sign: []const u8 = if (t.y < 0) "-" else switch (fmt[i]) {
                    'x' => if (t.y >= 10000) "+" else "",
                    'X' => "+",
                    else => "",
                };
                try out.appendSlice(a, sign);
                try padded(&out, a, @intCast(@abs(t.y)), 4);
            },
            'a' => try out.appendSlice(a, if (t.h >= 12) "pm" else "am"),
            'A' => try out.appendSlice(a, if (t.h >= 12) "PM" else "AM"),
            'B' => {
                var beat: i64 = (@rem(t.sse, 86400) + 3600) * 10;
                if (beat < 0) beat += 864000;
                try padded(&out, a, @rem(@divTrunc(beat, 864), 1000), 3);
            },
            'g' => try out.print(a, "{d}", .{if (@rem(t.h, 12) != 0) @rem(t.h, 12) else 12}),
            'G' => try out.print(a, "{d}", .{t.h}),
            'h' => try padded(&out, a, if (@rem(t.h, 12) != 0) @rem(t.h, 12) else 12, 2),
            'H' => try padded(&out, a, t.h, 2),
            'i' => try padded(&out, a, t.i, 2),
            's' => try padded(&out, a, t.s, 2),
            'u' => try padded(&out, a, t.us, 6),
            'v' => try padded(&out, a, @divTrunc(t.us, 1000), 3),
            'I' => try out.append(a, if (t.localtime and t.is_dst) '1' else '0'),
            'p' => {
                if (!t.localtime or std.mem.eql(u8, t.abbr, "UTC") or std.mem.eql(u8, t.abbr, "Z") or std.mem.eql(u8, t.abbr, "GMT+0000")) {
                    try out.append(a, 'Z');
                } else try offsetText(&out, a, t, true);
            },
            'P' => try offsetText(&out, a, t, true),
            'O' => try offsetText(&out, a, t, false),
            'T' => try out.appendSlice(a, if (t.localtime) t.abbr else "GMT"),
            'e' => {
                if (!t.localtime) {
                    try out.appendSlice(a, "UTC");
                } else switch (t.zone_type) {
                    dp.ZONETYPE_ID => try out.appendSlice(a, t.tz_name),
                    dp.ZONETYPE_ABBR => try out.appendSlice(a, t.abbr),
                    else => {
                        try out.append(a, if (t.offset < 0) '-' else '+');
                        try padded(&out, a, @intCast(@abs(@divTrunc(t.offset, 3600))), 2);
                        try out.append(a, ':');
                        try padded(&out, a, @intCast(@abs(@divTrunc(@rem(t.offset, 3600), 60))), 2);
                        if (@rem(t.offset, 60) != 0) {
                            try out.append(a, ':');
                            try padded(&out, a, @intCast(@abs(@rem(t.offset, 60))), 2);
                        }
                    },
                }
            },
            'Z' => try out.print(a, "{d}", .{if (t.localtime) t.offset else 0}),
            'c' => {
                try padded(&out, a, t.y, 4);
                try out.append(a, '-');
                try padded(&out, a, t.m, 2);
                try out.append(a, '-');
                try padded(&out, a, t.d, 2);
                try out.append(a, 'T');
                try padded(&out, a, t.h, 2);
                try out.append(a, ':');
                try padded(&out, a, t.i, 2);
                try out.append(a, ':');
                try padded(&out, a, t.s, 2);
                try offsetText(&out, a, t, true);
            },
            'r' => {
                try out.appendSlice(a, day_short[@intCast(dp.dayOfWeek(t.y, t.m, t.d))]);
                try out.appendSlice(a, ", ");
                try padded(&out, a, t.d, 2);
                try out.append(a, ' ');
                try out.appendSlice(a, mon_short[monthIndex(t.m)]);
                try out.append(a, ' ');
                try padded(&out, a, t.y, 4);
                try out.append(a, ' ');
                try padded(&out, a, t.h, 2);
                try out.append(a, ':');
                try padded(&out, a, t.i, 2);
                try out.append(a, ':');
                try padded(&out, a, t.s, 2);
                try out.append(a, ' ');
                try offsetText(&out, a, t, false);
            },
            'U' => try out.print(a, "{d}", .{t.sse}),
            '\\' => {
                // a trailing backslash prints the string's terminating nul
                i += 1;
                try out.append(a, if (i < fmt.len) fmt[i] else 0);
            },
            else => |c| try out.append(a, c),
        }
    }
    return out.toOwnedSlice(a);
}
