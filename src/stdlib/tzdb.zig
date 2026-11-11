// php's bundled timezone database and timelib's reading of it (parse_tz.c,
// parse_posix.c). the data is php's own timezonedb.h for the targeted
// version (scripts/gen-tzdata), so zones behave as php's do on any host and
// the system's zoneinfo is never read
const std = @import("std");
const sync = @import("../sync.zig");
const zlib = @import("c_zlib");

const tzdata_gz = @embedFile("tzdata.bin.gz");

const Db = struct {
    version: []const u8,
    names: [][]const u8,
    pos: []u32,
    data: []const u8,
    infos: []?*Info,
};

var db_mutex: sync.Mutex = .{};
var db: ?Db = null;
var db_failed = false;

fn inflateGzip(input: []const u8) ?[]u8 {
    var stream: zlib.z_stream = std.mem.zeroes(zlib.z_stream);
    // 15 window bits + 16 selects gzip framing
    if (zlib.inflateInit2_(&stream, 15 + 16, zlib.zlibVersion(), @sizeOf(zlib.z_stream)) != zlib.Z_OK) return null;
    defer _ = zlib.inflateEnd(&stream);
    const a = std.heap.page_allocator;
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(a);
    stream.next_in = @constCast(input.ptr);
    stream.avail_in = @intCast(input.len);
    var chunk: [32 * 1024]u8 = undefined;
    while (true) {
        stream.next_out = &chunk;
        stream.avail_out = chunk.len;
        const rc = zlib.inflate(&stream, zlib.Z_NO_FLUSH);
        const produced = chunk.len - stream.avail_out;
        if (produced > 0) out.appendSlice(a, chunk[0..produced]) catch return null;
        if (rc == zlib.Z_STREAM_END) break;
        if (rc != zlib.Z_OK) return null;
        if (stream.avail_in == 0 and produced == 0) break;
    }
    return out.toOwnedSlice(a) catch null;
}

// the database is decompressed on first use and kept for the process, as
// php keeps its compiled-in one; serve workers share it
fn load() ?*const Db {
    db_mutex.lock();
    defer db_mutex.unlock();
    if (db) |*d| return d;
    if (db_failed) return null;
    db = decode() orelse {
        db_failed = true;
        return null;
    };
    return &db.?;
}

fn decode() ?Db {
    const a = std.heap.page_allocator;
    const blob = inflateGzip(tzdata_gz) orelse return null;
    if (blob.len < 9 or !std.mem.eql(u8, blob[0..4], "ZTZ2")) return null;
    var off: usize = 4;
    const vlen = blob[off];
    off += 1;
    const ver = blob[off .. off + vlen];
    off += vlen;
    const count = std.mem.readInt(u32, blob[off..][0..4], .little);
    off += 4;
    const names = a.alloc([]const u8, count) catch return null;
    const pos = a.alloc(u32, count) catch return null;
    const infos = a.alloc(?*Info, count) catch return null;
    @memset(infos, null);
    for (0..count) |i| {
        const nl = blob[off];
        off += 1;
        names[i] = blob[off .. off + nl];
        off += nl;
        pos[i] = std.mem.readInt(u32, blob[off..][0..4], .little);
        off += 4;
    }
    const dlen = std.mem.readInt(u32, blob[off..][0..4], .little);
    off += 4;
    return .{ .version = ver, .names = names, .pos = pos, .data = blob[off .. off + dlen], .infos = infos };
}

// timelib_strcasecmp
fn caseCompare(a: []const u8, b: []const u8) std.math.Order {
    const n = @min(a.len, b.len);
    for (a[0..n], b[0..n]) |x, y| {
        const lx = std.ascii.toLower(x);
        const ly = std.ascii.toLower(y);
        if (lx != ly) return std.math.order(lx, ly);
    }
    return std.math.order(a.len, b.len);
}

// seek_to_tz_position: php's index is searched case-insensitively
fn indexOf(d: *const Db, name: []const u8) ?usize {
    if (std.mem.indexOfScalar(u8, name, 0) != null) return null;
    var left: isize = 0;
    var right: isize = @as(isize, @intCast(d.names.len)) - 1;
    while (left <= right) {
        const mid: usize = @intCast(@divTrunc(left + right, 2));
        switch (caseCompare(name, d.names[mid])) {
            .lt => right = @as(isize, @intCast(mid)) - 1,
            .gt => left = @as(isize, @intCast(mid)) + 1,
            .eq => return mid,
        }
    }
    return null;
}

pub fn version() []const u8 {
    const d = load() orelse return "0.system";
    return d.version;
}

// timelib_timezone_id_is_valid
pub fn isValid(name: []const u8) bool {
    const d = load() orelse return false;
    return indexOf(d, name) != null;
}

// the database's own spelling of a zone id
pub fn canonicalName(name: []const u8) ?[]const u8 {
    const d = load() orelse return null;
    const i = indexOf(d, name) orelse return null;
    return d.names[i];
}

pub const Id = struct {
    name: []const u8,
    // php's bc flag: set for the ids timezone_identifiers_list() lists by default
    canonical: bool,
    country_code: [2]u8,
};

// every id in the database, in php's order
pub fn identifiers() IdIterator {
    return .{ .d = load() };
}

pub const IdIterator = struct {
    d: ?*const Db,
    i: usize = 0,

    pub fn next(it: *IdIterator) ?Id {
        const d = it.d orelse return null;
        if (it.i >= d.names.len) return null;
        defer it.i += 1;
        const p = d.pos[it.i];
        return .{ .name = d.names[it.i], .canonical = d.data[p + 4] == 1, .country_code = .{ d.data[p + 5], d.data[p + 6] } };
    }
};

pub const TType = struct {
    offset: i32,
    isdst: bool,
    abbr_idx: u32,
};

const TransKind = enum { julian_no_feb29, julian_feb29, mwd };

const TransSpec = struct {
    kind: TransKind = .julian_feb29,
    days: i64 = 0,
    month: i64 = 0,
    week: i64 = 0,
    dow: i64 = 0,
    hour: i64 = 2 * 3600,
};

pub const Posix = struct {
    std_offset: i64,
    dst_offset: i64 = 0,
    has_dst: bool = false,
    dst_begin: ?TransSpec = null,
    dst_end: ?TransSpec = null,
    std_type: usize = 0,
    dst_type: usize = 0,
};

pub const Location = struct {
    country_code: [2]u8,
    latitude: f64,
    longitude: f64,
    comments: []const u8,
};

// timelib_tzinfo for one zone, parsed once and kept for the process
pub const Info = struct {
    // the database's spelling; php names a zone the way it was asked for
    name: []const u8,
    bc: bool,
    trans: []const i64,
    trans_idx: []const u8,
    types: []const TType,
    abbrs: []const u8,
    posix: ?Posix,
    location: Location,

    pub fn abbr(self: *const Info, t: TType) []const u8 {
        if (t.abbr_idx >= self.abbrs.len) return "";
        const rest = self.abbrs[t.abbr_idx..];
        return rest[0 .. std.mem.indexOfScalar(u8, rest, 0) orelse rest.len];
    }

    pub const Fetched = struct { t: TType, transition: i64 };

    // timelib_fetch_timezone_offset
    pub fn fetch(self: *const Info, ts: i64) ?Fetched {
        const min = std.math.minInt(i64);
        if (self.trans.len == 0) {
            if (self.posix != null) {
                const r = self.fetchPosix(ts) orelse return null;
                return .{ .t = r.t, .transition = min };
            }
            if (self.types.len == 1) return .{ .t = self.types[0], .transition = min };
            return null;
        }
        if (ts < self.trans[0]) return .{ .t = self.types[0], .transition = min };
        const last = self.trans.len - 1;
        if (ts >= self.trans[last]) {
            if (self.posix != null) return self.fetchPosix(ts);
            return .{ .t = self.types[self.trans_idx[last]], .transition = self.trans[last] };
        }
        var left: usize = 0;
        var right: usize = last;
        while (right - left > 1) {
            const mid = (left + right) >> 1;
            if (ts < self.trans[mid]) right = mid else left = mid;
        }
        return .{ .t = self.types[self.trans_idx[left]], .transition = self.trans[left] };
    }

    // timelib_fetch_posix_timezone_offset
    fn fetchPosix(self: *const Info, ts: i64) ?Fetched {
        const p = self.posix.?;
        if (p.dst_end == null) {
            const tt: i64 = if (self.trans.len > 0) self.trans[self.trans.len - 1] else std.math.minInt(i64);
            return .{ .t = self.types[p.std_type], .transition = tt };
        }
        const year = yearOf(ts);
        var tr = Transitions{};
        self.transitionsForYear(year - 1, &tr);
        self.transitionsForYear(year, &tr);
        self.transitionsForYear(year + 1, &tr);
        var i: usize = 1;
        while (i < tr.count) : (i += 1) {
            if (ts < tr.times[i]) return .{ .t = self.types[tr.types[i - 1]], .transition = tr.times[i - 1] };
        }
        return null;
    }

    pub const Transitions = struct {
        times: [6]i64 = undefined,
        types: [6]usize = undefined,
        count: usize = 0,
    };

    // timelib_get_transitions_for_year; only for a posix rule with dst
    pub fn transitionsForYear(self: *const Info, year: i64, out: *Transitions) void {
        const p = self.posix.?;
        const year_begin = tsAtStartOfYear(year);
        const begin = year_begin +% calcTransition(p.dst_begin.?, year) +% p.dst_begin.?.hour -% p.std_offset;
        const end = year_begin +% calcTransition(p.dst_end.?, year) +% p.dst_end.?.hour -% p.dst_offset;
        const c = out.count;
        if (begin < end) {
            out.times[c] = begin;
            out.times[c + 1] = end;
            out.types[c] = p.dst_type;
            out.types[c + 1] = p.std_type;
        } else {
            out.times[c + 1] = begin;
            out.times[c] = end;
            out.types[c + 1] = p.dst_type;
            out.types[c] = p.std_type;
        }
        out.count += 2;
    }
};

// the zone's parsed data, or null for an id the database lacks
pub fn info(name: []const u8) ?*const Info {
    const d = load() orelse return null;
    const i = indexOf(d, name) orelse return null;
    db_mutex.lock();
    defer db_mutex.unlock();
    if (d.infos[i]) |inf| return inf;
    const inf = parse(d.names[i], d.data[d.pos[i]..]) orelse return null;
    d.infos[i] = inf;
    return inf;
}

const Reader = struct {
    b: []const u8,
    i: usize = 0,

    fn u32be(r: *Reader) ?u32 {
        if (r.i + 4 > r.b.len) return null;
        defer r.i += 4;
        return std.mem.readInt(u32, r.b[r.i..][0..4], .big);
    }

    fn skip(r: *Reader, n: usize) ?void {
        if (r.i + n > r.b.len) return null;
        r.i += n;
    }

    fn take(r: *Reader, n: usize) ?[]const u8 {
        if (r.i + n > r.b.len) return null;
        defer r.i += n;
        return r.b[r.i .. r.i + n];
    }
};

const Counts = struct { isut: u32, isstd: u32, leap: u32, time: u32, type: u32, char: u32 };

fn readCounts(r: *Reader) ?Counts {
    return .{ .isut = r.u32be() orelse return null, .isstd = r.u32be() orelse return null, .leap = r.u32be() orelse return null, .time = r.u32be() orelse return null, .type = r.u32be() orelse return null, .char = r.u32be() orelse return null };
}

// timelib_parse_tzfile on a php "PHP2" record
fn parse(name: []const u8, rec: []const u8) ?*Info {
    const a = std.heap.page_allocator;
    var r = Reader{ .b = rec };
    if (rec.len < 20 or !std.mem.eql(u8, rec[0..3], "PHP")) return null;
    const bc = rec[4] == 1;
    const cc = [2]u8{ rec[5], rec[6] };
    r.i = 20;
    // the 32-bit data php's files still carry (empty in slim files)
    const c32 = readCounts(&r) orelse return null;
    r.skip(@as(usize, c32.time) * 5 + @as(usize, c32.type) * 6 + c32.char + @as(usize, c32.leap) * 8 + c32.isstd + c32.isut) orelse return null;
    const pre = r.take(20) orelse return null;
    if (!std.mem.eql(u8, pre[0..4], "TZif") or pre[4] < '2' or pre[4] > '4') return null;
    const c = readCounts(&r) orelse return null;

    const trans = a.alloc(i64, c.time) catch return null;
    for (trans, 0..) |*t, i| {
        const raw = r.take(8) orelse return null;
        t.* = std.mem.readInt(i64, raw[0..8], .big);
        if (i > 0 and !(t.* > trans[i - 1])) return null;
    }
    const trans_idx = a.dupe(u8, r.take(c.time) orelse return null) catch return null;

    // room for the two types a posix string may add
    var types = std.ArrayListUnmanaged(TType).initCapacity(a, c.type + 2) catch return null;
    for (0..c.type) |_| {
        const t = r.take(6) orelse return null;
        types.appendAssumeCapacity(.{ .offset = std.mem.readInt(i32, t[0..4], .big), .isdst = t[4] != 0, .abbr_idx = t[5] });
    }
    var abbrs = std.ArrayListUnmanaged(u8).empty;
    abbrs.appendSlice(a, r.take(c.char) orelse return null) catch return null;
    r.skip(@as(usize, c.leap) * 12 + c.isstd + c.isut) orelse return null;
    for (trans_idx) |ti| if (ti >= types.items.len) return null;

    // the posix string between newlines
    if ((r.take(1) orelse return null)[0] != '\n') return null;
    const pstart = r.i;
    const pend = std.mem.indexOfScalarPos(u8, rec, pstart, '\n') orelse return null;
    const posix_string = rec[pstart..pend];
    r.i = pend + 1;
    var posix: ?Posix = null;
    if (posix_string.len > 0) {
        var p = parsePosix(posix_string) orelse return null;
        p.std_type = typeIndex(&types, &abbrs, p.std_offset, false, p.std_name);
        if (p.has_dst) p.dst_type = typeIndex(&types, &abbrs, p.dst_offset, true, p.dst_name);
        posix = p.toPosix();
    }

    // read_location
    const lat = r.u32be() orelse return null;
    const lon = r.u32be() orelse return null;
    const clen = r.u32be() orelse return null;
    const comments = r.take(clen) orelse return null;

    const inf = a.create(Info) catch return null;
    inf.* = .{
        .name = name,
        .bc = bc,
        .trans = trans,
        .trans_idx = trans_idx,
        .types = types.items,
        .abbrs = abbrs.items,
        .posix = posix,
        .location = .{
            .country_code = cc,
            .latitude = @as(f64, @floatFromInt(lat)) / 100000 - 90,
            .longitude = @as(f64, @floatFromInt(lon)) / 100000 - 180,
            .comments = comments,
        },
    };
    return inf;
}

// find_ttinfo_index, else add_new_ttinfo_index
fn typeIndex(types: *std.ArrayListUnmanaged(TType), abbrs: *std.ArrayListUnmanaged(u8), offset: i64, isdst: bool, name: []const u8) usize {
    for (types.items, 0..) |t, i| {
        if (t.offset != offset or t.isdst != isdst) continue;
        const rest = abbrs.items[@min(t.abbr_idx, abbrs.items.len)..];
        const s = rest[0 .. std.mem.indexOfScalar(u8, rest, 0) orelse rest.len];
        if (std.mem.eql(u8, s, name)) return i;
    }
    const a = std.heap.page_allocator;
    const idx: u32 = @intCast(abbrs.items.len);
    abbrs.appendSlice(a, name) catch {};
    abbrs.append(a, 0) catch {};
    types.append(a, .{ .offset = @intCast(offset), .isdst = isdst, .abbr_idx = idx }) catch return 0;
    return types.items.len - 1;
}

const ParsedPosix = struct {
    std_name: []const u8,
    std_offset: i64,
    dst_name: []const u8 = "",
    dst_offset: i64 = 0,
    has_dst: bool = false,
    dst_begin: ?TransSpec = null,
    dst_end: ?TransSpec = null,
    std_type: usize = 0,
    dst_type: usize = 0,

    fn toPosix(p: ParsedPosix) Posix {
        return .{ .std_offset = p.std_offset, .dst_offset = p.dst_offset, .has_dst = p.has_dst, .dst_begin = p.dst_begin, .dst_end = p.dst_end, .std_type = p.std_type, .dst_type = p.dst_type };
    }
};

const PosixReader = struct {
    s: []const u8,
    i: usize = 0,

    fn c(p: *const PosixReader) u8 {
        return if (p.i < p.s.len) p.s[p.i] else 0;
    }

    // "<" [+-]? .+? ">" | [A-Za-z]+
    fn description(p: *PosixReader) ?[]const u8 {
        if (p.c() == '<') {
            p.i += 1;
            const begin = p.i;
            while (p.c() != 0 and p.c() != '>') p.i += 1;
            if (p.c() == 0) return null;
            const end = p.i;
            p.i += 1;
            if (end - begin < 1) return null;
            return p.s[begin..end];
        }
        const begin = p.i;
        while (std.ascii.isAlphabetic(p.c())) p.i += 1;
        if (p.i == begin) return null;
        return p.s[begin..p.i];
    }

    fn number(p: *PosixReader) ?i64 {
        const begin = p.i;
        var acc: i64 = 0;
        while (p.c() == '0') p.i += 1;
        while (p.c() >= '0' and p.c() <= '9') : (p.i += 1) acc = acc * 10 + (p.c() - '0');
        if (p.i == begin) return null;
        return acc;
    }

    // [+-]? hh(:mm(:ss)?)?, negated: EST5 is utc-5
    fn offset(p: *PosixReader) ?i64 {
        var bias: i64 = 1;
        if (p.c() == '+') {
            p.i += 1;
        } else if (p.c() == '-') {
            bias = -1;
            p.i += 1;
        }
        const h = p.number() orelse return null;
        var m: i64 = 0;
        var s: i64 = 0;
        if (p.c() == ':') {
            p.i += 1;
            m = p.number() orelse return null;
        }
        if (p.c() == ':') {
            p.i += 1;
            s = p.number() orelse return null;
        }
        return -1 * bias * (h * 3600 + m * 60 + s);
    }

    fn spec(p: *PosixReader) ?TransSpec {
        var t = TransSpec{};
        if (p.c() == 'M') {
            t.kind = .mwd;
            p.i += 1;
            t.month = p.number() orelse return null;
            if (p.c() != '.') return null;
            p.i += 1;
            t.week = p.number() orelse return null;
            if (p.c() != '.') return null;
            p.i += 1;
            t.dow = p.number() orelse return null;
        } else {
            if (p.c() == 'J') {
                t.kind = .julian_no_feb29;
                p.i += 1;
            }
            t.days = p.number() orelse return null;
        }
        if (p.c() == '/') {
            p.i += 1;
            t.hour = -(p.offset() orelse return null);
        }
        return t;
    }
};

// timelib_parse_posix_str
fn parsePosix(s: []const u8) ?ParsedPosix {
    var p = PosixReader{ .s = s };
    var out = ParsedPosix{ .std_name = p.description() orelse return null, .std_offset = 0 };
    out.std_offset = p.offset() orelse return null;
    if (p.c() == 0) return out;
    out.dst_offset = out.std_offset + 3600;
    out.dst_name = p.description() orelse return null;
    out.has_dst = true;
    if (p.c() != ',' and p.c() != 0) out.dst_offset = p.offset() orelse return null;
    if (p.c() != ',') return null;
    p.i += 1;
    out.dst_begin = p.spec() orelse return null;
    if (p.c() != ',') return null;
    p.i += 1;
    out.dst_end = p.spec() orelse return null;
    if (p.i != s.len) return null;
    return out;
}

fn isLeap(y: i64) bool {
    return @rem(y, 4) == 0 and (@rem(y, 100) != 0 or @rem(y, 400) == 0);
}

const month_lengths = [2][12]i64{
    .{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 },
    .{ 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 },
};

// calc_transition: seconds from the start of the year (tzcode's transtime)
fn calcTransition(t: TransSpec, year: i64) i64 {
    const leap: usize = @intFromBool(isLeap(year));
    switch (t.kind) {
        .julian_no_feb29 => {
            var v = t.days - 1;
            if (leap == 1 and t.days >= 60) v += 1;
            return v * 86400;
        },
        .julian_feb29 => return t.days * 86400,
        .mwd => {
            // zeller's congruence, in c's int arithmetic
            const m1: i32 = @intCast(@rem(t.month + 9, 12) + 1);
            const yy0: i32 = @truncate(if (t.month <= 2) year - 1 else year);
            const yy1 = @divTrunc(yy0, 100);
            const yy2 = @rem(yy0, 100);
            var dow = @rem(@divTrunc(26 * m1 - 2, 10) + 1 + yy2 + @divTrunc(yy2, 4) + @divTrunc(yy1, 4) - 2 * yy1, 7);
            if (dow < 0) dow += 7;
            var d: i64 = t.dow - dow;
            if (d < 0) d += 7;
            const month: usize = @intCast(std.math.clamp(t.month, 1, 12));
            var i: i64 = 1;
            while (i < t.week) : (i += 1) {
                if (d + 7 >= month_lengths[leap][month - 1]) break;
                d += 7;
            }
            var v = d * 86400;
            for (0..month - 1) |k| v += month_lengths[leap][k] * 86400;
            return v;
        },
    }
}

fn countLeapYears(y0: i64) i64 {
    const y = y0 - 1;
    return @divTrunc(y, 4) - @divTrunc(y, 100) + @divTrunc(y, 400);
}

// timelib_ts_at_start_of_year
pub fn tsAtStartOfYear(year: i64) i64 {
    return 86400 *% ((year -% 1970) *% 365 +% countLeapYears(year) - countLeapYears(1970));
}

// the utc year of an instant (timelib_unixtime2gmt's y)
pub fn yearOf(ts: i64) i64 {
    const days = @divFloor(ts, 86400);
    // civil-from-days (howard hinnant), which timelib's result matches
    const z = days + 719468;
    const era = @divFloor(z, 146097);
    const doe = z - era * 146097;
    const yoe = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const doy = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp = @divFloor(5 * doy + 2, 153);
    const m = if (mp < 10) mp + 3 else mp - 9;
    return yoe + era * 400 + @as(i64, if (m <= 2) 1 else 0);
}

test "bundled database reads php's zones" {
    const london = info("Europe/London") orelse return error.Missing;
    try std.testing.expectEqualStrings("GB", &london.location.country_code);
    const summer = london.fetch(1751328000) orelse return error.Missing; // 2025-07-01
    try std.testing.expectEqual(@as(i32, 3600), summer.t.offset);
    try std.testing.expectEqualStrings("BST", london.abbr(summer.t));
    try std.testing.expect(isValid("asia/calcutta"));
    try std.testing.expect(!isValid("Not/AZone"));
    try std.testing.expectEqualStrings("America/New_York", canonicalName("america/new_york").?);
}
