//! php's date string parser: a port of timelib's parse_date.re scanner and the
//! tm2unixtime.c resolution steps, as bundled with php 8.5.4. the scanner rules
//! are timelib's own re2c definitions, compiled on first use into an nfa that
//! keeps re2c's semantics: at each position every rule is tried, the longest
//! match wins, and the earlier rule wins a tie

const std = @import("std");
const sync = @import("../sync.zig");
const Allocator = std.mem.Allocator;
const abbr_table = @import("tz_abbr_table.zig");

pub const UNSET: i64 = -9999999;

pub const ZONETYPE_NONE: u8 = 0;
pub const ZONETYPE_OFFSET: u8 = 1;
pub const ZONETYPE_ABBR: u8 = 2;
pub const ZONETYPE_ID: u8 = 3;

pub const SPECIAL_WEEKDAY: u32 = 1;
const SPECIAL_DAY_OF_WEEK_IN_MONTH: u32 = 2;
const SPECIAL_LAST_DAY_OF_WEEK_IN_MONTH: u32 = 3;
pub const FIRST_DAY_OF_MONTH: u8 = 1;
pub const LAST_DAY_OF_MONTH: u8 = 2;

// timelib's re2c definitions, verbatim from parse_date.re
const defs_src =
    \\any = [\000-\377];
    \\
    \\nbsp = [\302][\240];
    \\nnbsp = [\342][\200][\257];
    \\space = [ \t]+ | nbsp+ | nnbsp+;
    \\frac = "."[0-9]+;
    \\
    \\ago = 'ago';
    \\
    \\hour24 = [01]?[0-9] | "2"[0-4];
    \\hour24lz = [01][0-9] | "2"[0-4];
    \\hour12 = "0"?[1-9] | "1"[0-2];
    \\minute = [0-5]?[0-9];
    \\minutelz = [0-5][0-9];
    \\second = minute | "60";
    \\secondlz = minutelz | "60";
    \\meridian = ([AaPp] "."? [Mm] "."?) [\000\t ];
    \\tz = "("? [A-Za-z]{1,6} ")"? | [A-Z][a-z]+([_/-][A-Za-z]+)+;
    \\tzcorrection = "GMT"? [+-] ((hour24 (":"? minute)?) | (hour24lz minutelz secondlz) | (hour24lz ":" minutelz ":" secondlz));
    \\
    \\daysuf = "st" | "nd" | "rd" | "th";
    \\
    \\month = "0"? [0-9] | "1"[0-2];
    \\day   = (([0-2]?[0-9]) | ("3"[01])) daysuf?;
    \\year  = [0-9]{1,4};
    \\year2 = [0-9]{2};
    \\year4 = [0-9]{4};
    \\year4withsign = [+-]? [0-9]{4};
    \\yearx = [+-] [0-9]{5,19};
    \\
    \\dayofyear = "00"[1-9] | "0"[1-9][0-9] | [1-2][0-9][0-9] | "3"[0-5][0-9] | "36"[0-6];
    \\weekofyear = "0"[1-9] | [1-4][0-9] | "5"[0-3];
    \\
    \\monthlz = "0" [0-9] | "1" [0-2];
    \\daylz   = "0" [0-9] | [1-2][0-9] | "3" [01];
    \\
    \\dayfulls = 'sundays' | 'mondays' | 'tuesdays' | 'wednesdays' | 'thursdays' | 'fridays' | 'saturdays';
    \\dayfull = 'sunday' | 'monday' | 'tuesday' | 'wednesday' | 'thursday' | 'friday' | 'saturday';
    \\dayabbr = 'sun' | 'mon' | 'tue' | 'wed' | 'thu' | 'fri' | 'sat' | 'sun';
    \\dayspecial = 'weekday' | 'weekdays';
    \\daytext = dayfulls | dayfull | dayabbr | dayspecial;
    \\
    \\monthfull = 'january' | 'february' | 'march' | 'april' | 'may' | 'june' | 'july' | 'august' | 'september' | 'october' | 'november' | 'december';
    \\monthabbr = 'jan' | 'feb' | 'mar' | 'apr' | 'may' | 'jun' | 'jul' | 'aug' | 'sep' | 'sept' | 'oct' | 'nov' | 'dec';
    \\monthroman = "I" | "II" | "III" | "IV" | "V" | "VI" | "VII" | "VIII" | "IX" | "X" | "XI" | "XII";
    \\monthtext = monthfull | monthabbr | monthroman;
    \\
    \\/* Time formats */
    \\timetiny12 = hour12 space? meridian;
    \\timeshort12 = hour12[:.]minutelz space? meridian;
    \\timelong12 = hour12[:.]minute[:.]secondlz space? meridian;
    \\
    \\timetiny24 = 't' hour24;
    \\timeshort24 = 't'? hour24[:.]minute;
    \\timelong24 =  't'? hour24[:.]minute[:.]second;
    \\iso8601long =  't'? hour24 [:.] minute [:.] second frac;
    \\
    \\/* iso8601shorttz = hour24 [:] minutelz space? (tzcorrection | tz); */
    \\iso8601normtz =  't'? hour24 [:.] minute [:.] secondlz space? (tzcorrection | tz);
    \\/* iso8601longtz =  hour24 [:] minute [:] secondlz frac space? (tzcorrection | tz); */
    \\
    \\gnunocolon       = 't'? hour24lz minutelz;
    \\/* gnunocolontz     = hour24lz minutelz space? (tzcorrection | tz); */
    \\iso8601nocolon   = 't'? hour24lz minutelz secondlz;
    \\/* iso8601nocolontz = hour24lz minutelz secondlz space? (tzcorrection | tz); */
    \\
    \\/* Date formats */
    \\americanshort    = month "/" day;
    \\american         = month "/" day "/" year;
    \\iso8601dateslash = year4 "/" monthlz "/" daylz "/"?;
    \\dateslash        = year4 "/" month "/" day;
    \\iso8601date4     = year4withsign "-" monthlz "-" daylz;
    \\iso8601date2     = year2 "-" monthlz "-" daylz;
    \\iso8601datex     = yearx "-" monthlz "-" daylz;
    \\gnudateshorter   = year4 "-" month;
    \\gnudateshort     = year "-" month "-" day;
    \\pointeddate4     = day [.\t-] month [.-] year4;
    \\pointeddate2     = day [.\t] month "." year2;
    \\datefull         = day ([ \t.-])* monthtext ([ \t.-])* year;
    \\datenoday        = monthtext ([ .\t-])* year4;
    \\datenodayrev     = year4 ([ .\t-])* monthtext;
    \\datetextual      = monthtext ([ .\t-])* day [,.stndrh\t ]+ year;
    \\datenoyear       = monthtext ([ .\t-])* day ([,.stndrh\t ]+|[\000]);
    \\datenoyearrev    = day ([ .\t-])* monthtext;
    \\datenocolon      = year4 monthlz daylz;
    \\
    \\/* Special formats */
    \\soap             = year4 "-" monthlz "-" daylz "T" hour24lz ":" minutelz ":" secondlz frac tzcorrection?;
    \\xmlrpc           = year4 monthlz daylz "T" hour24 ":" minutelz ":" secondlz;
    \\xmlrpcnocolon    = year4 monthlz daylz 't' hour24 minutelz secondlz;
    \\wddx             = year4 "-" month "-" day "T" hour24 ":" minute ":" second;
    \\pgydotd          = year4 [.-]? dayofyear;
    \\pgtextshort      = monthabbr "-" daylz "-" year;
    \\pgtextreverse    = year "-" monthabbr "-" daylz;
    \\mssqltime        = hour12 ":" minutelz ":" secondlz [:.] [0-9]+ meridian;
    \\isoweekday       = year4 "-"? "W" weekofyear "-"? [0-7];
    \\isoweek          = year4 "-"? "W" weekofyear;
    \\exif             = year4 ":" monthlz ":" daylz " " hour24lz ":" minutelz ":" secondlz;
    \\firstdayof       = 'first day of';
    \\lastdayof        = 'last day of';
    \\backof           = 'back of ' hour24 (space? meridian)?;
    \\frontof          = 'front of ' hour24 (space? meridian)?;
    \\
    \\/* Common Log Format: 10/Oct/2000:13:55:36 -0700 */
    \\clf              = day "/" monthabbr "/" year4 ":" hour24lz ":" minutelz ":" secondlz space tzcorrection;
    \\
    \\/* Timestamp format: @1126396800 */
    \\timestamp        = "@" "-"? [0-9]+;
    \\timestampms      = "@" "-"? [0-9]+ "." [0-9]{0,6};
    \\
    \\/* To fix some ambiguities */
    \\dateshortwithtimeshort12  = datenoyear timeshort12;
    \\dateshortwithtimelong12   = datenoyear timelong12;
    \\dateshortwithtimeshort  = datenoyear timeshort24;
    \\dateshortwithtimelong   = datenoyear timelong24;
    \\dateshortwithtimelongtz = datenoyear iso8601normtz;
    \\
    \\/*
    \\ * Relative regexps
    \\ */
    \\reltextnumber = 'first'|'second'|'third'|'fourth'|'fifth'|'sixth'|'seventh'|'eight'|'eighth'|'ninth'|'tenth'|'eleventh'|'twelfth';
    \\reltexttext = 'next'|'last'|'previous'|'this';
    \\reltextunit = 'ms' | 'µs' | (('msec'|'millisecond'|'µsec'|'microsecond'|'usec'|'sec'|'second'|'min'|'minute'|'hour'|'day'|'fortnight'|'forthnight'|'month'|'year') 's'?) | 'weeks' | daytext;
    \\
    \\relnumber = ([+-]*[ \t]*[0-9]{1,13});
    \\relative = relnumber space? (reltextunit | 'week' );
    \\relativetext = (reltextnumber|reltexttext) space reltextunit;
    \\relativetextweek = reltexttext space 'week';
    \\
    \\weekdayof        = (reltextnumber|reltexttext) space (dayfulls|dayfull|dayabbr) space 'of';
;

const Act = enum {
    yesterday,
    now,
    noon,
    midnight_today,
    tomorrow,
    timestamp,
    timestampms,
    firstlastdayof,
    backfrontof,
    weekdayof,
    time12,
    mssqltime,
    time24,
    gnunocolon,
    iso8601nocolon,
    american,
    iso8601date4,
    iso8601date2,
    iso8601datex,
    gnudateshorter,
    gnudateshort,
    datefull,
    pointeddate4,
    pointeddate2,
    datenoday,
    datenodayrev,
    datetextual,
    datenoyearrev,
    datenocolon,
    xmlrpc,
    pgydotd,
    isoweekday,
    isoweek,
    pgtextshort,
    pgtextreverse,
    clf,
    year4,
    ago,
    daytext,
    relativetextweek,
    relativetext,
    monthtext,
    tz,
    dateshortwithtime12,
    dateshortwithtime24,
    relative,
    skip,
    unexpected,
};

// the scanner rules in parse_date.re order, which breaks ties
const Rule = struct { expr: []const u8, act: Act };
const rules = [_]Rule{
    .{ .expr = "'yesterday'", .act = .yesterday },
    .{ .expr = "'now'", .act = .now },
    .{ .expr = "'noon'", .act = .noon },
    .{ .expr = "'midnight' | 'today'", .act = .midnight_today },
    .{ .expr = "'tomorrow'", .act = .tomorrow },
    .{ .expr = "timestamp", .act = .timestamp },
    .{ .expr = "timestampms", .act = .timestampms },
    .{ .expr = "firstdayof | lastdayof", .act = .firstlastdayof },
    .{ .expr = "backof | frontof", .act = .backfrontof },
    .{ .expr = "weekdayof", .act = .weekdayof },
    .{ .expr = "timetiny12 | timeshort12 | timelong12", .act = .time12 },
    .{ .expr = "mssqltime", .act = .mssqltime },
    .{ .expr = "timetiny24 | timeshort24 | timelong24 | iso8601long", .act = .time24 },
    .{ .expr = "gnunocolon", .act = .gnunocolon },
    .{ .expr = "iso8601nocolon", .act = .iso8601nocolon },
    .{ .expr = "americanshort | american", .act = .american },
    .{ .expr = "iso8601date4 | iso8601dateslash | dateslash", .act = .iso8601date4 },
    .{ .expr = "iso8601date2", .act = .iso8601date2 },
    .{ .expr = "iso8601datex", .act = .iso8601datex },
    .{ .expr = "gnudateshorter", .act = .gnudateshorter },
    .{ .expr = "gnudateshort", .act = .gnudateshort },
    .{ .expr = "datefull", .act = .datefull },
    .{ .expr = "pointeddate4", .act = .pointeddate4 },
    .{ .expr = "pointeddate2", .act = .pointeddate2 },
    .{ .expr = "datenoday", .act = .datenoday },
    .{ .expr = "datenodayrev", .act = .datenodayrev },
    .{ .expr = "datetextual | datenoyear", .act = .datetextual },
    .{ .expr = "datenoyearrev", .act = .datenoyearrev },
    .{ .expr = "datenocolon", .act = .datenocolon },
    .{ .expr = "xmlrpc | xmlrpcnocolon | soap | wddx | exif", .act = .xmlrpc },
    .{ .expr = "pgydotd", .act = .pgydotd },
    .{ .expr = "isoweekday", .act = .isoweekday },
    .{ .expr = "isoweek", .act = .isoweek },
    .{ .expr = "pgtextshort", .act = .pgtextshort },
    .{ .expr = "pgtextreverse", .act = .pgtextreverse },
    .{ .expr = "clf", .act = .clf },
    .{ .expr = "year4", .act = .year4 },
    .{ .expr = "ago", .act = .ago },
    .{ .expr = "daytext", .act = .daytext },
    .{ .expr = "relativetextweek", .act = .relativetextweek },
    .{ .expr = "relativetext", .act = .relativetext },
    .{ .expr = "monthfull | monthabbr", .act = .monthtext },
    .{ .expr = "tzcorrection | tz", .act = .tz },
    .{ .expr = "dateshortwithtimeshort12 | dateshortwithtimelong12", .act = .dateshortwithtime12 },
    .{ .expr = "dateshortwithtimeshort | dateshortwithtimelong | dateshortwithtimelongtz", .act = .dateshortwithtime24 },
    .{ .expr = "relative", .act = .relative },
    .{ .expr = "[.,]", .act = .skip },
    .{ .expr = "space", .act = .skip },
    .{ .expr = "\"\\000\"|\"\\n\"", .act = .skip },
    .{ .expr = "any", .act = .unexpected },
};

// ---- the regex engine ----

const ByteSet = std.StaticBitSet(256);
const INF: u16 = 0xffff;

const Node = struct {
    tag: enum { set, cat, alt, rep },
    set: u16 = 0,
    kids: []const u32 = &.{},
    min: u16 = 0,
    max: u16 = 0,
};

const State = struct {
    kind: enum(u8) { set, split, match },
    set: u16 = 0,
    out1: u32 = 0,
    out2: u32 = 0,
    rule: u16 = 0,
};

const Machine = struct {
    states: []const State,
    sets: []const ByteSet,
    start: u32,
};

const Builder = struct {
    a: Allocator,
    nodes: std.ArrayListUnmanaged(Node) = .empty,
    sets: std.ArrayListUnmanaged(ByteSet) = .empty,
    names: std.ArrayListUnmanaged([]const u8) = .empty,
    defs: std.ArrayListUnmanaged(u32) = .empty,
    states: std.ArrayListUnmanaged(State) = .empty,
    src: []const u8 = "",
    pos: usize = 0,

    const Error = error{ OutOfMemory, BadPattern };

    fn peek(b: *Builder) u8 {
        return if (b.pos < b.src.len) b.src[b.pos] else 0;
    }

    fn skip(b: *Builder) void {
        while (b.pos < b.src.len) {
            const c = b.src[b.pos];
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                b.pos += 1;
            } else if (c == '/' and b.pos + 1 < b.src.len and b.src[b.pos + 1] == '*') {
                const end = std.mem.indexOfPos(u8, b.src, b.pos + 2, "*/") orelse b.src.len;
                b.pos = @min(end + 2, b.src.len);
            } else break;
        }
    }

    fn node(b: *Builder, n: Node) Error!u32 {
        try b.nodes.append(b.a, n);
        return @intCast(b.nodes.items.len - 1);
    }

    fn setNode(b: *Builder, s: ByteSet) Error!u32 {
        try b.sets.append(b.a, s);
        return b.node(.{ .tag = .set, .set = @intCast(b.sets.items.len - 1) });
    }

    fn isIdent(c: u8) bool {
        return std.ascii.isAlphanumeric(c) or c == '_';
    }

    fn escape(b: *Builder) u8 {
        // at the byte after a backslash: octal \ooo, \t, \n, or the byte itself
        const c = b.peek();
        b.pos += 1;
        if (c >= '0' and c <= '7') {
            var v: u32 = c - '0';
            var n: usize = 1;
            while (n < 3 and b.peek() >= '0' and b.peek() <= '7') : (n += 1) {
                v = v * 8 + (b.peek() - '0');
                b.pos += 1;
            }
            return @intCast(v & 0xff);
        }
        return switch (c) {
            't' => '\t',
            'n' => '\n',
            'r' => '\r',
            else => c,
        };
    }

    fn parseDefs(b: *Builder, text: []const u8) Error!void {
        b.src = text;
        b.pos = 0;
        while (true) {
            b.skip();
            if (b.pos >= b.src.len) break;
            const start = b.pos;
            while (isIdent(b.peek())) b.pos += 1;
            const name = b.src[start..b.pos];
            if (name.len == 0) return error.BadPattern;
            b.skip();
            if (b.peek() != '=') return error.BadPattern;
            b.pos += 1;
            const n = try b.parseAlt();
            b.skip();
            if (b.peek() != ';') return error.BadPattern;
            b.pos += 1;
            try b.names.append(b.a, name);
            try b.defs.append(b.a, n);
        }
    }

    fn parseExpr(b: *Builder, text: []const u8) Error!u32 {
        b.src = text;
        b.pos = 0;
        const n = try b.parseAlt();
        b.skip();
        if (b.pos != b.src.len) return error.BadPattern;
        return n;
    }

    fn parseAlt(b: *Builder) Error!u32 {
        var kids: std.ArrayListUnmanaged(u32) = .empty;
        try kids.append(b.a, try b.parseCat());
        while (true) {
            b.skip();
            if (b.peek() != '|') break;
            b.pos += 1;
            try kids.append(b.a, try b.parseCat());
        }
        if (kids.items.len == 1) return kids.items[0];
        return b.node(.{ .tag = .alt, .kids = kids.items });
    }

    fn parseCat(b: *Builder) Error!u32 {
        var kids: std.ArrayListUnmanaged(u32) = .empty;
        while (true) {
            b.skip();
            const c = b.peek();
            if (c == 0 or c == '|' or c == ')' or c == ';') break;
            try kids.append(b.a, try b.parsePostfix());
        }
        if (kids.items.len == 0) return error.BadPattern;
        if (kids.items.len == 1) return kids.items[0];
        return b.node(.{ .tag = .cat, .kids = kids.items });
    }

    fn readNum(b: *Builder) Error!u16 {
        const start = b.pos;
        while (std.ascii.isDigit(b.peek())) b.pos += 1;
        return std.fmt.parseInt(u16, b.src[start..b.pos], 10) catch error.BadPattern;
    }

    fn parsePostfix(b: *Builder) Error!u32 {
        var n = try b.parsePrimary();
        while (true) {
            const kid = try b.a.dupe(u32, &.{n});
            switch (b.peek()) {
                '?' => {
                    b.pos += 1;
                    n = try b.node(.{ .tag = .rep, .kids = kid, .min = 0, .max = 1 });
                },
                '*' => {
                    b.pos += 1;
                    n = try b.node(.{ .tag = .rep, .kids = kid, .min = 0, .max = INF });
                },
                '+' => {
                    b.pos += 1;
                    n = try b.node(.{ .tag = .rep, .kids = kid, .min = 1, .max = INF });
                },
                '{' => {
                    b.pos += 1;
                    const lo = try b.readNum();
                    var hi = lo;
                    if (b.peek() == ',') {
                        b.pos += 1;
                        hi = try b.readNum();
                    }
                    if (b.peek() != '}') return error.BadPattern;
                    b.pos += 1;
                    n = try b.node(.{ .tag = .rep, .kids = kid, .min = lo, .max = hi });
                },
                else => return n,
            }
        }
    }

    fn parsePrimary(b: *Builder) Error!u32 {
        const c = b.peek();
        switch (c) {
            '(' => {
                b.pos += 1;
                const n = try b.parseAlt();
                b.skip();
                if (b.peek() != ')') return error.BadPattern;
                b.pos += 1;
                return n;
            },
            '[' => {
                b.pos += 1;
                var set: ByteSet = .empty;
                var first = true;
                while (b.peek() != ']' or first) {
                    if (b.pos >= b.src.len) return error.BadPattern;
                    first = false;
                    var lo = b.peek();
                    b.pos += 1;
                    if (lo == '\\') lo = b.escape();
                    var hi = lo;
                    if (b.peek() == '-' and b.pos + 1 < b.src.len and b.src[b.pos + 1] != ']') {
                        b.pos += 1;
                        hi = b.peek();
                        b.pos += 1;
                        if (hi == '\\') hi = b.escape();
                    }
                    var v: usize = lo;
                    while (v <= hi) : (v += 1) set.set(v);
                }
                b.pos += 1;
                return b.setNode(set);
            },
            '"', '\'' => {
                b.pos += 1;
                var kids: std.ArrayListUnmanaged(u32) = .empty;
                while (b.peek() != c) {
                    if (b.pos >= b.src.len) return error.BadPattern;
                    var ch = b.peek();
                    b.pos += 1;
                    if (ch == '\\') ch = b.escape();
                    var set: ByteSet = .empty;
                    set.set(ch);
                    // single quotes match ascii letters in either case
                    if (c == '\'' and std.ascii.isAlphabetic(ch)) {
                        set.set(std.ascii.toLower(ch));
                        set.set(std.ascii.toUpper(ch));
                    }
                    try kids.append(b.a, try b.setNode(set));
                }
                b.pos += 1;
                if (kids.items.len == 1) return kids.items[0];
                return b.node(.{ .tag = .cat, .kids = kids.items });
            },
            else => {
                const start = b.pos;
                while (isIdent(b.peek())) b.pos += 1;
                const name = b.src[start..b.pos];
                for (b.names.items, 0..) |n, i| {
                    if (std.mem.eql(u8, n, name)) return b.defs.items[i];
                }
                return error.BadPattern;
            },
        }
    }

    fn state(b: *Builder, s: State) Error!u32 {
        try b.states.append(b.a, s);
        return @intCast(b.states.items.len - 1);
    }

    // thompson construction, built back to front: returns the entry state of
    // `n` followed by `next`
    fn compile(b: *Builder, n: u32, next: u32) Error!u32 {
        const nd = b.nodes.items[n];
        switch (nd.tag) {
            .set => return b.state(.{ .kind = .set, .set = nd.set, .out1 = next }),
            .cat => {
                var nx = next;
                var i = nd.kids.len;
                while (i > 0) {
                    i -= 1;
                    nx = try b.compile(nd.kids[i], nx);
                }
                return nx;
            },
            .alt => {
                var nx = try b.compile(nd.kids[nd.kids.len - 1], next);
                var i = nd.kids.len - 1;
                while (i > 0) {
                    i -= 1;
                    const s = try b.compile(nd.kids[i], next);
                    nx = try b.state(.{ .kind = .split, .out1 = s, .out2 = nx });
                }
                return nx;
            },
            .rep => {
                var nx = next;
                if (nd.max == INF) {
                    const loop = try b.state(.{ .kind = .split, .out2 = next });
                    const body = try b.compile(nd.kids[0], loop);
                    b.states.items[loop].out1 = body;
                    nx = loop;
                } else {
                    var k = nd.max - nd.min;
                    while (k > 0) : (k -= 1) {
                        const body = try b.compile(nd.kids[0], nx);
                        nx = try b.state(.{ .kind = .split, .out1 = body, .out2 = nx });
                    }
                }
                var k = nd.min;
                while (k > 0) : (k -= 1) nx = try b.compile(nd.kids[0], nx);
                return nx;
            },
        }
    }
};

fn buildMachine() Builder.Error!Machine {
    // lives for the whole process, like the compiled re2c tables in php
    const arena = try std.heap.page_allocator.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var b = Builder{ .a = arena.allocator() };
    try b.parseDefs(defs_src);
    var starts: [rules.len]u32 = undefined;
    for (rules, 0..) |r, i| {
        const n = try b.parseExpr(r.expr);
        const m = try b.state(.{ .kind = .match, .rule = @intCast(i) });
        starts[i] = try b.compile(n, m);
    }
    var start = starts[rules.len - 1];
    var i: usize = rules.len - 1;
    while (i > 0) {
        i -= 1;
        start = try b.state(.{ .kind = .split, .out1 = starts[i], .out2 = start });
    }
    return .{ .states = b.states.items, .sets = b.sets.items, .start = start };
}

var machine: Machine = undefined;
var machine_once = sync.once(initMachine);

fn initMachine() void {
    machine = buildMachine() catch @panic("date parser rules failed to compile");
}

fn getMachine() *const Machine {
    machine_once.call();
    return &machine;
}

// the nfa is turned into a dfa lazily, the way re2c would have built it ahead
// of time: a dfa state is the set of nfa byte-consuming states reachable after
// some input, plus the best rule that has matched there. states and their
// transitions are added the first time some input needs them and are shared by
// every thread under one lock. the dfa only ever grows, and stays small for
// this grammar; past `max_dfa_states` matching runs on the nfa directly
const max_dfa_states = 20000;
const NONE_RULE: u16 = std.math.maxInt(u16);
const UNKNOWN: u32 = std.math.maxInt(u32);
const DEAD: u32 = std.math.maxInt(u32) - 1;

const DState = struct {
    nfa: []const u32,
    accept: u16,
    trans: []u32,
};

const Dfa = struct {
    a: Allocator,
    classes: [256]u8 = undefined,
    nclasses: usize = 0,
    reps: [256]u8 = undefined,
    states: std.ArrayListUnmanaged(DState) = .empty,
    index: std.HashMapUnmanaged([]const u32, u32, SetContext, 80) = .empty,
    marks: []u32 = &.{},
    gen: u32 = 0,
    list: std.ArrayListUnmanaged(u32) = .empty,
    stack: std.ArrayListUnmanaged(u32) = .empty,
};

const SetContext = struct {
    pub fn hash(_: SetContext, k: []const u32) u64 {
        return std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(k));
    }
    pub fn eql(_: SetContext, a: []const u32, b: []const u32) bool {
        return std.mem.eql(u32, a, b);
    }
};

var dfa: Dfa = undefined;
var dfa_ready = false;
var dfa_mutex: sync.Mutex = .{};

const Match = struct { len: usize, rule: u16 };

fn initDfa(m: *const Machine) !void {
    const arena = try std.heap.page_allocator.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    dfa = .{ .a = arena.allocator() };
    // bytes that every byte set treats alike share a class
    var class_of = @as([256]u16, @splat(0));
    var count: u16 = 1;
    for (m.sets) |set| {
        var remap: [512]u16 = @as([512]u16, @splat(0xffff));
        var next: u16 = 0;
        for (0..256) |b| {
            const key = @as(usize, class_of[b]) * 2 + @intFromBool(set.isSet(b));
            if (remap[key] == 0xffff) {
                remap[key] = next;
                next += 1;
            }
            class_of[b] = remap[key];
        }
        count = next;
    }
    dfa.nclasses = count;
    for (0..256) |b| {
        dfa.classes[b] = @intCast(class_of[b]);
        dfa.reps[class_of[b]] = @intCast(b);
    }
    dfa.marks = try dfa.a.alloc(u32, m.states.len);
    @memset(dfa.marks, 0);
    // state 0 is the start: the closure of the nfa entry
    dfa.gen = 1;
    dfa.list.clearRetainingCapacity();
    var accept: u16 = NONE_RULE;
    try closureInto(m, m.start, &accept);
    _ = try internState(accept);
    dfa_ready = true;
}

fn closureInto(m: *const Machine, from: u32, accept: *u16) !void {
    try dfa.stack.append(dfa.a, from);
    while (dfa.stack.pop()) |st| {
        if (dfa.marks[st] == dfa.gen) continue;
        dfa.marks[st] = dfa.gen;
        const s = m.states[st];
        switch (s.kind) {
            .set => try dfa.list.append(dfa.a, st),
            .split => {
                try dfa.stack.append(dfa.a, s.out2);
                try dfa.stack.append(dfa.a, s.out1);
            },
            .match => if (s.rule < accept.*) {
                accept.* = s.rule;
            },
        }
    }
}

// the key of the nfa set in dfa.list: its sorted states, then the rule that
// matched, since equal sets can follow different matches
fn stateKey(accept: u16) ![]const u32 {
    std.mem.sort(u32, dfa.list.items, {}, std.sort.asc(u32));
    try dfa.list.append(dfa.a, accept);
    return dfa.list.items;
}

// the dfa state for the nfa set in dfa.list, added if new
fn internState(accept: u16) !u32 {
    const key = try stateKey(accept);
    if (dfa.index.get(key)) |i| return i;
    const owned = try dfa.a.dupe(u32, key);
    const trans = try dfa.a.alloc(u32, dfa.nclasses);
    @memset(trans, UNKNOWN);
    try dfa.states.append(dfa.a, .{ .nfa = owned[0 .. owned.len - 1], .accept = accept, .trans = trans });
    const idx: u32 = @intCast(dfa.states.items.len - 1);
    try dfa.index.put(dfa.a, owned, idx);
    return idx;
}

fn bumpGen() void {
    dfa.gen +%= 1;
    if (dfa.gen == 0) {
        @memset(dfa.marks, 0);
        dfa.gen = 1;
    }
}

// the state after `from` reads a byte of class `cls`, computed on first use
fn step(m: *const Machine, from: u32, cls: usize) !u32 {
    const known = dfa.states.items[from].trans[cls];
    if (known != UNKNOWN) return known;
    bumpGen();
    dfa.list.clearRetainingCapacity();
    var accept: u16 = NONE_RULE;
    const byte = dfa.reps[cls];
    for (dfa.states.items[from].nfa) |st| {
        const s = m.states[st];
        if (m.sets[s.set].isSet(byte)) try closureInto(m, s.out1, &accept);
    }
    var to: u32 = DEAD;
    if (dfa.list.items.len > 0 or accept != NONE_RULE) {
        if (dfa.states.items.len >= max_dfa_states) {
            const key = try stateKey(accept);
            to = dfa.index.get(key) orelse return error.DfaFull;
        } else {
            to = try internState(accept);
        }
    }
    dfa.states.items[from].trans[cls] = to;
    return to;
}

// callers hold dfa_mutex
fn longestMatch(buf: []const u8, start: usize) !Match {
    const m = getMachine();
    if (!dfa_ready) try initDfa(m);
    return dfaMatch(m, buf, start) catch |err| switch (err) {
        error.DfaFull => nfaMatch(m, buf, start),
        else => err,
    };
}

fn dfaMatch(m: *const Machine, buf: []const u8, start: usize) !Match {
    var best_len: usize = 0;
    var best_rule: u16 = NONE_RULE;
    var st: u32 = 0;
    var p: usize = 0;
    while (start + p < buf.len) {
        st = try step(m, st, dfa.classes[buf[start + p]]);
        if (st == DEAD) break;
        p += 1;
        const acc = dfa.states.items[st].accept;
        if (acc != NONE_RULE) {
            best_len = p;
            best_rule = acc;
        }
    }
    // the `any` rule matches every byte, so there is always a match
    if (best_rule == NONE_RULE) return .{ .len = 1, .rule = rules.len - 1 };
    return .{ .len = best_len, .rule = best_rule };
}

// the same longest match straight on the nfa, for when the dfa is full
fn nfaMatch(m: *const Machine, buf: []const u8, start: usize) !Match {
    var best_len: usize = 0;
    var best_rule: u16 = NONE_RULE;
    var cur: std.ArrayListUnmanaged(u32) = .empty;
    defer cur.deinit(std.heap.page_allocator);
    bumpGen();
    dfa.list.clearRetainingCapacity();
    var accept: u16 = NONE_RULE;
    try closureInto(m, m.start, &accept);
    try cur.appendSlice(std.heap.page_allocator, dfa.list.items);
    var p: usize = 0;
    while (cur.items.len > 0 and start + p < buf.len) {
        const c = buf[start + p];
        bumpGen();
        dfa.list.clearRetainingCapacity();
        accept = NONE_RULE;
        for (cur.items) |st| {
            const s = m.states[st];
            if (m.sets[s.set].isSet(c)) try closureInto(m, s.out1, &accept);
        }
        p += 1;
        if (accept != NONE_RULE) {
            best_len = p;
            best_rule = accept;
        }
        cur.clearRetainingCapacity();
        try cur.appendSlice(std.heap.page_allocator, dfa.list.items);
    }
    if (best_rule == NONE_RULE) return .{ .len = 1, .rule = rules.len - 1 };
    return .{ .len = best_len, .rule = best_rule };
}

// ---- parsed time ----

pub const Msg = struct { pos: usize, char: u8, msg: []const u8 };

pub const Rel = struct {
    y: i64 = 0,
    m: i64 = 0,
    d: i64 = 0,
    h: i64 = 0,
    i: i64 = 0,
    s: i64 = 0,
    us: i64 = 0,
    weekday: i64 = 0,
    weekday_behavior: i64 = 0,
    first_last_day_of: u8 = 0,
    special_type: u32 = 0,
    special_amount: i64 = 0,
    have_weekday_relative: bool = false,
    have_special_relative: bool = false,
};

pub const Time = struct {
    y: i64 = UNSET,
    m: i64 = UNSET,
    d: i64 = UNSET,
    h: i64 = UNSET,
    i: i64 = UNSET,
    s: i64 = UNSET,
    us: i64 = UNSET,
    z: i64 = UNSET,
    dst: i64 = UNSET,
    abbr_buf: [16]u8 = undefined,
    abbr_len: u8 = 0,
    has_abbr: bool = false,
    id_buf: [64]u8 = undefined,
    id_len: u8 = 0,
    has_id: bool = false,
    relative: Rel = .{},
    have_time: u32 = 0,
    have_date: u32 = 0,
    have_zone: u32 = 0,
    have_relative: bool = false,
    is_localtime: bool = false,
    zone_type: u8 = ZONETYPE_NONE,
    sse: i64 = 0,

    pub fn abbr(t: *const Time) ?[]const u8 {
        return if (t.has_abbr) t.abbr_buf[0..t.abbr_len] else null;
    }

    // abbreviations are kept upper-cased, as timelib_time_tz_abbr_update does
    pub fn setAbbr(t: *Time, s: []const u8) void {
        const n = @min(s.len, t.abbr_buf.len);
        for (s[0..n], 0..) |c, k| t.abbr_buf[k] = std.ascii.toUpper(c);
        t.abbr_len = @intCast(n);
        t.has_abbr = true;
    }

    pub fn id(t: *const Time) ?[]const u8 {
        return if (t.has_id) t.id_buf[0..t.id_len] else null;
    }

    pub fn setId(t: *Time, s: []const u8) void {
        const n = @min(s.len, t.id_buf.len);
        @memcpy(t.id_buf[0..n], s[0..n]);
        t.id_len = @intCast(n);
        t.has_id = true;
    }
};

pub const OffsetInfo = struct { offset: i64 = 0, transition_time: i64 = 0, is_dst: bool = false };

// the zone database the parser and the resolver consult
pub const TzDb = struct {
    // a known zone id, matched case-insensitively, in the spelling the caller
    // keeps (php keeps the one it was given), or null
    lookupId: *const fn (name: []const u8, out: *[64]u8) ?[]const u8,
    // the utc offset, its start, and dst flag in effect at a utc instant
    offsetInfo: *const fn (id: []const u8, ts: i64) ?OffsetInfo,
};

pub const Parsed = struct {
    time: Time = .{},
    errors: std.ArrayListUnmanaged(Msg) = .empty,
    warnings: std.ArrayListUnmanaged(Msg) = .empty,

    pub fn deinit(p: *Parsed, a: Allocator) void {
        p.errors.deinit(a);
        p.warnings.deinit(a);
    }
};

// ---- lookup tables ----

const Unit = enum { microsec, second, minute, hour, day, month, year, weekday, special };
const RelUnit = struct { name: []const u8, unit: Unit, mult: i64 };
const relunits = [_]RelUnit{
    .{ .name = "ms", .unit = .microsec, .mult = 1000 },
    .{ .name = "msec", .unit = .microsec, .mult = 1000 },
    .{ .name = "msecs", .unit = .microsec, .mult = 1000 },
    .{ .name = "millisecond", .unit = .microsec, .mult = 1000 },
    .{ .name = "milliseconds", .unit = .microsec, .mult = 1000 },
    .{ .name = "\xc2\xb5s", .unit = .microsec, .mult = 1 },
    .{ .name = "usec", .unit = .microsec, .mult = 1 },
    .{ .name = "usecs", .unit = .microsec, .mult = 1 },
    .{ .name = "\xc2\xb5sec", .unit = .microsec, .mult = 1 },
    .{ .name = "\xc2\xb5secs", .unit = .microsec, .mult = 1 },
    .{ .name = "microsecond", .unit = .microsec, .mult = 1 },
    .{ .name = "microseconds", .unit = .microsec, .mult = 1 },
    .{ .name = "sec", .unit = .second, .mult = 1 },
    .{ .name = "secs", .unit = .second, .mult = 1 },
    .{ .name = "second", .unit = .second, .mult = 1 },
    .{ .name = "seconds", .unit = .second, .mult = 1 },
    .{ .name = "min", .unit = .minute, .mult = 1 },
    .{ .name = "mins", .unit = .minute, .mult = 1 },
    .{ .name = "minute", .unit = .minute, .mult = 1 },
    .{ .name = "minutes", .unit = .minute, .mult = 1 },
    .{ .name = "hour", .unit = .hour, .mult = 1 },
    .{ .name = "hours", .unit = .hour, .mult = 1 },
    .{ .name = "day", .unit = .day, .mult = 1 },
    .{ .name = "days", .unit = .day, .mult = 1 },
    .{ .name = "week", .unit = .day, .mult = 7 },
    .{ .name = "weeks", .unit = .day, .mult = 7 },
    .{ .name = "fortnight", .unit = .day, .mult = 14 },
    .{ .name = "fortnights", .unit = .day, .mult = 14 },
    .{ .name = "forthnight", .unit = .day, .mult = 14 },
    .{ .name = "forthnights", .unit = .day, .mult = 14 },
    .{ .name = "month", .unit = .month, .mult = 1 },
    .{ .name = "months", .unit = .month, .mult = 1 },
    .{ .name = "year", .unit = .year, .mult = 1 },
    .{ .name = "years", .unit = .year, .mult = 1 },
    .{ .name = "mondays", .unit = .weekday, .mult = 1 },
    .{ .name = "monday", .unit = .weekday, .mult = 1 },
    .{ .name = "mon", .unit = .weekday, .mult = 1 },
    .{ .name = "tuesdays", .unit = .weekday, .mult = 2 },
    .{ .name = "tuesday", .unit = .weekday, .mult = 2 },
    .{ .name = "tue", .unit = .weekday, .mult = 2 },
    .{ .name = "wednesdays", .unit = .weekday, .mult = 3 },
    .{ .name = "wednesday", .unit = .weekday, .mult = 3 },
    .{ .name = "wed", .unit = .weekday, .mult = 3 },
    .{ .name = "thursdays", .unit = .weekday, .mult = 4 },
    .{ .name = "thursday", .unit = .weekday, .mult = 4 },
    .{ .name = "thu", .unit = .weekday, .mult = 4 },
    .{ .name = "fridays", .unit = .weekday, .mult = 5 },
    .{ .name = "friday", .unit = .weekday, .mult = 5 },
    .{ .name = "fri", .unit = .weekday, .mult = 5 },
    .{ .name = "saturdays", .unit = .weekday, .mult = 6 },
    .{ .name = "saturday", .unit = .weekday, .mult = 6 },
    .{ .name = "sat", .unit = .weekday, .mult = 6 },
    .{ .name = "sundays", .unit = .weekday, .mult = 0 },
    .{ .name = "sunday", .unit = .weekday, .mult = 0 },
    .{ .name = "sun", .unit = .weekday, .mult = 0 },
    .{ .name = "weekday", .unit = .special, .mult = SPECIAL_WEEKDAY },
    .{ .name = "weekdays", .unit = .special, .mult = SPECIAL_WEEKDAY },
};

const RelText = struct { name: []const u8, behavior: i64, value: i64 };
const reltexts = [_]RelText{
    .{ .name = "first", .behavior = 0, .value = 1 },
    .{ .name = "next", .behavior = 0, .value = 1 },
    .{ .name = "second", .behavior = 0, .value = 2 },
    .{ .name = "third", .behavior = 0, .value = 3 },
    .{ .name = "fourth", .behavior = 0, .value = 4 },
    .{ .name = "fifth", .behavior = 0, .value = 5 },
    .{ .name = "sixth", .behavior = 0, .value = 6 },
    .{ .name = "seventh", .behavior = 0, .value = 7 },
    .{ .name = "eight", .behavior = 0, .value = 8 },
    .{ .name = "eighth", .behavior = 0, .value = 8 },
    .{ .name = "ninth", .behavior = 0, .value = 9 },
    .{ .name = "tenth", .behavior = 0, .value = 10 },
    .{ .name = "eleventh", .behavior = 0, .value = 11 },
    .{ .name = "twelfth", .behavior = 0, .value = 12 },
    .{ .name = "last", .behavior = 0, .value = -1 },
    .{ .name = "previous", .behavior = 0, .value = -1 },
    .{ .name = "this", .behavior = 1, .value = 0 },
};

const MonthName = struct { name: []const u8, value: i64 };
const months = [_]MonthName{
    .{ .name = "jan", .value = 1 },       .{ .name = "feb", .value = 2 },      .{ .name = "mar", .value = 3 },
    .{ .name = "apr", .value = 4 },       .{ .name = "may", .value = 5 },      .{ .name = "jun", .value = 6 },
    .{ .name = "jul", .value = 7 },       .{ .name = "aug", .value = 8 },      .{ .name = "sep", .value = 9 },
    .{ .name = "sept", .value = 9 },      .{ .name = "oct", .value = 10 },     .{ .name = "nov", .value = 11 },
    .{ .name = "dec", .value = 12 },      .{ .name = "i", .value = 1 },        .{ .name = "ii", .value = 2 },
    .{ .name = "iii", .value = 3 },       .{ .name = "iv", .value = 4 },       .{ .name = "v", .value = 5 },
    .{ .name = "vi", .value = 6 },        .{ .name = "vii", .value = 7 },      .{ .name = "viii", .value = 8 },
    .{ .name = "ix", .value = 9 },        .{ .name = "x", .value = 10 },       .{ .name = "xi", .value = 11 },
    .{ .name = "xii", .value = 12 },      .{ .name = "january", .value = 1 },  .{ .name = "february", .value = 2 },
    .{ .name = "march", .value = 3 },     .{ .name = "april", .value = 4 },    .{ .name = "may", .value = 5 },
    .{ .name = "june", .value = 6 },      .{ .name = "july", .value = 7 },     .{ .name = "august", .value = 8 },
    .{ .name = "september", .value = 9 }, .{ .name = "october", .value = 10 }, .{ .name = "november", .value = 11 },
    .{ .name = "december", .value = 12 },
};

pub const AbbrHit = struct { offset: i64, dst: bool, id: ?[]const u8 };

// timelib's abbr_search with no offset hint: utc and gmt first, then the first
// table entry with that name
pub fn abbrSearch(word: []const u8) ?AbbrHit {
    if (std.ascii.eqlIgnoreCase(word, "utc") or std.ascii.eqlIgnoreCase(word, "gmt")) {
        return .{ .offset = 0, .dst = false, .id = "UTC" };
    }
    for (abbr_table.entries) |e| {
        if (std.ascii.eqlIgnoreCase(word, e.abbr)) return .{ .offset = e.offset, .dst = e.dst, .id = e.id };
    }
    return null;
}

// timelib's abbr_search with an offset and dst hint, as
// timezone_name_from_abbr() asks it: the zone id it finds, if any
pub fn abbrSearchFull(word: []const u8, gmtoffset: i64, isdst: i64) ?[]const u8 {
    if (std.ascii.eqlIgnoreCase(word, "utc") or std.ascii.eqlIgnoreCase(word, "gmt")) return "UTC";
    var first: ?abbr_table.Entry = null;
    for (abbr_table.entries) |e| {
        if (!std.ascii.eqlIgnoreCase(word, e.abbr)) continue;
        if (first == null) {
            first = e;
            if (gmtoffset == -1) return e.id;
        }
        if (e.offset == gmtoffset) return e.id;
    }
    if (first) |e| return e.id;
    for (abbr_table.fallback) |e| {
        if (e.offset == gmtoffset and @intFromBool(e.dst) == isdst) return e.id;
    }
    return null;
}

// names shorter than this are looked up as abbreviations (_POSIX_TZNAME_MAX)
pub const MAX_ABBR_LEN = 6;

// ---- reading inside a token ----

// a cursor over the matched token; reading past its end gives 0, the way the
// actions read their nul-terminated copy of the token
const Ptr = struct {
    s: []const u8,
    i: usize = 0,

    fn c(p: *const Ptr) u8 {
        return if (p.i < p.s.len) p.s[p.i] else 0;
    }

    fn at(p: *const Ptr, k: usize) u8 {
        return if (p.i + k < p.s.len) p.s[p.i + k] else 0;
    }
};

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isSpaceC(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == 0x0b or c == 0x0c or c == '\r';
}

fn isLetter(c: u8) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z');
}

// leading digits of s as strtol reads them (no sign handling needed here)
fn strtol(s: []const u8, from: usize) i64 {
    var v: i64 = 0;
    var k = from;
    while (k < s.len and isDigit(s[k])) : (k += 1) v = v *% 10 +% (s[k] - '0');
    return v;
}

fn getNrEx(p: *Ptr, max_length: usize, scanned: ?*usize) i64 {
    while (!isDigit(p.c())) {
        if (p.c() == 0) return UNSET;
        p.i += 1;
    }
    const begin = p.i;
    var len: usize = 0;
    while (isDigit(p.c()) and len < max_length) {
        p.i += 1;
        len += 1;
    }
    if (scanned) |sl| sl.* = len;
    return strtol(p.s[0..p.i], begin);
}

fn getNr(p: *Ptr, max_length: usize) i64 {
    return getNrEx(p, max_length, null);
}

fn skipDaySuffix(p: *Ptr) void {
    if (isSpaceC(p.c())) return;
    const a = std.ascii.toLower(p.c());
    const b = std.ascii.toLower(p.at(1));
    if ((a == 'n' and b == 'd') or (a == 'r' and b == 'd') or (a == 's' and b == 't') or (a == 't' and b == 'h')) p.i += 2;
}

const pow10_neg = [_]f64{ 1e0, 1e-1, 1e-2, 1e-3, 1e-4, 1e-5, 1e-6, 1e-7, 1e-8, 1e-9, 1e-10, 1e-11, 1e-12, 1e-13, 1e-14, 1e-15, 1e-16, 1e-17, 1e-18, 1e-19, 1e-20, 1e-21, 1e-22 };
const pow10_pos = [_]f64{ 1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7 };

fn pow10(e: i64) f64 {
    if (e >= 0) return if (e < pow10_pos.len) pow10_pos[@intCast(e)] else std.math.pow(f64, 10, @floatFromInt(e));
    const n = -e;
    return if (n < pow10_neg.len) pow10_neg[@intCast(n)] else std.math.pow(f64, 10, @floatFromInt(e));
}

// strtod over the [.:0-9] run that follows the separator
fn strtodRun(s: []const u8) f64 {
    var end: usize = 0;
    while (end < s.len and isDigit(s[end])) end += 1;
    if (end < s.len and s[end] == '.') {
        end += 1;
        while (end < s.len and isDigit(s[end])) end += 1;
    }
    if (end == 0 or (end == 1 and s[0] == '.')) return 0;
    return std.fmt.parseFloat(f64, s[0..end]) catch 0;
}

fn toInt(v: f64) i64 {
    if (!(v == v)) return 0;
    if (v >= 9.2e18) return std.math.maxInt(i64);
    if (v <= -9.2e18) return std.math.minInt(i64);
    return @intFromFloat(v);
}

fn getFracNr(p: *Ptr) i64 {
    while (p.c() != '.' and p.c() != ':' and !isDigit(p.c())) {
        if (p.c() == 0) return UNSET;
        p.i += 1;
    }
    const begin = p.i;
    while (p.c() == '.' or p.c() == ':' or isDigit(p.c())) p.i += 1;
    const end = p.i;
    const v = strtodRun(p.s[begin + 1 .. end]) * pow10(7 - @as(i64, @intCast(end - begin)));
    return toInt(v);
}

fn lookupRelativeText(p: *Ptr, behavior: *i64) i64 {
    const begin = p.i;
    while (isLetter(p.c())) p.i += 1;
    const word = p.s[begin..p.i];
    var value: i64 = 0;
    for (reltexts) |r| {
        if (std.ascii.eqlIgnoreCase(word, r.name)) {
            value = r.value;
            behavior.* = r.behavior;
        }
    }
    return value;
}

fn getRelativeText(p: *Ptr, behavior: *i64) i64 {
    while (p.c() == ' ' or p.c() == '\t' or p.c() == '-' or p.c() == '/') p.i += 1;
    return lookupRelativeText(p, behavior);
}

fn lookupMonth(p: *Ptr) i64 {
    const begin = p.i;
    while (isLetter(p.c())) p.i += 1;
    const word = p.s[begin..p.i];
    var value: i64 = 0;
    for (months) |mn| {
        if (std.ascii.eqlIgnoreCase(word, mn.name)) value = mn.value;
    }
    return value;
}

fn getMonth(p: *Ptr) i64 {
    while (p.c() == ' ' or p.c() == '\t' or p.c() == '-' or p.c() == '.' or p.c() == '/') p.i += 1;
    return lookupMonth(p);
}

fn eatSpaces(p: *Ptr) void {
    while (true) {
        if (p.c() == ' ' or p.c() == '\t') {
            p.i += 1;
        } else if (p.c() == 0xe2 and p.at(1) == 0x80 and p.at(2) == 0xaf) {
            p.i += 3;
        } else if (p.c() == 0xc2 and p.at(1) == 0xa0) {
            p.i += 2;
        } else break;
    }
}

fn lookupRelunit(p: *Ptr) ?RelUnit {
    const begin = p.i;
    while (true) {
        const c = p.c();
        if (c == 0 or c == ' ' or c == ',' or c == '\t' or c == ';' or c == ':' or c == '/' or c == '.' or c == '-' or c == '(' or c == ')') break;
        p.i += 1;
    }
    const word = p.s[begin..p.i];
    for (relunits) |r| {
        if (std.ascii.eqlIgnoreCase(word, r.name)) return r;
    }
    return null;
}

fn meridian(p: *Ptr, h: i64) i64 {
    var ret: i64 = 0;
    while (true) {
        const c = p.c();
        if (c == 0 or c == 'A' or c == 'a' or c == 'P' or c == 'p') break;
        p.i += 1;
    }
    if (p.c() == 'a' or p.c() == 'A') {
        if (h == 12) ret = -12;
    } else if (h != 12) {
        ret = 12;
    }
    p.i += 1;
    if (p.c() == '.') p.i += 1;
    if (p.c() == 'M' or p.c() == 'm') p.i += 1;
    if (p.c() == '.') p.i += 1;
    return ret;
}

fn processYear(y: *i64, len: usize) void {
    if (y.* == UNSET or len >= 4) return;
    if (y.* < 100) y.* += if (y.* < 70) 2000 else 1900;
}

// ---- the scanner ----

const Scanner = struct {
    a: Allocator,
    buf: []const u8,
    len: usize,
    tok: usize = 0,
    cur: usize = 0,
    t: *Time,
    p: *Parsed,
    db: TzDb,

    fn addError(s: *Scanner, msg: []const u8) !void {
        if (s.p.errors.items.len >= max_errors) return;
        try s.p.errors.append(s.a, .{ .pos = s.tok, .char = s.buf[s.tok], .msg = msg });
    }

    fn addWarning(s: *Scanner, msg: []const u8) !void {
        if (s.p.warnings.items.len >= max_errors) return;
        try s.p.warnings.append(s.a, .{ .pos = s.tok, .char = s.buf[s.tok], .msg = msg });
    }

    fn haveTime(s: *Scanner) !bool {
        if (s.t.have_time != 0) {
            try s.addError("Double time specification");
            return false;
        }
        s.t.have_time = 1;
        s.t.h = 0;
        s.t.i = 0;
        s.t.s = 0;
        s.t.us = 0;
        return true;
    }

    fn unhaveTime(s: *Scanner) void {
        s.t.have_time = 0;
        s.t.h = 0;
        s.t.i = 0;
        s.t.s = 0;
        s.t.us = 0;
    }

    fn haveDate(s: *Scanner) !bool {
        if (s.t.have_date != 0) {
            try s.addError("Double date specification");
            return false;
        }
        s.t.have_date = 1;
        return true;
    }

    fn unhaveDate(s: *Scanner) void {
        s.t.have_date = 0;
        s.t.d = 0;
        s.t.m = 0;
        s.t.y = 0;
    }

    fn haveWeekdayRelative(s: *Scanner) void {
        s.t.have_relative = true;
        s.t.relative.have_weekday_relative = true;
    }

    fn haveSpecialRelative(s: *Scanner) void {
        s.t.have_relative = true;
        s.t.relative.have_special_relative = true;
    }

    fn haveTz(s: *Scanner) !bool {
        if (s.t.have_zone != 0) {
            if (s.t.have_zone > 1) {
                try s.addError("Double timezone specification");
            } else {
                try s.addWarning("Double timezone specification");
            }
            s.t.have_zone += 1;
            return false;
        }
        s.t.have_zone += 1;
        return true;
    }

    fn getSignedNr(s: *Scanner, p: *Ptr, max_length: usize) !i64 {
        while (!isDigit(p.c()) and p.c() != '+' and p.c() != '-') {
            if (p.c() == 0) {
                try s.addError("Found unexpected data");
                return 0;
            }
            p.i += 1;
        }
        var neg = false;
        while (p.c() == '+' or p.c() == '-') {
            if (p.c() == '-') neg = !neg;
            p.i += 1;
        }
        while (!isDigit(p.c())) {
            if (p.c() == 0) {
                try s.addError("Found unexpected data");
                return 0;
            }
            p.i += 1;
        }
        var v: i128 = 0;
        var len: usize = 0;
        while (isDigit(p.c()) and len < max_length) {
            v = v * 10 + (p.c() - '0');
            p.i += 1;
            len += 1;
        }
        if (neg) v = -v;
        if (v > std.math.maxInt(i64) or v < std.math.minInt(i64)) {
            try s.addError("Number out of range");
            return 0;
        }
        return @intCast(v);
    }

    fn addWithOverflow(s: *Scanner, e: *i64, amount: i64, mult: i64) !void {
        const r = @addWithOverflow(e.*, amount *% mult);
        e.* = r[0];
        if (r[1] != 0) try s.addError("Number out of range");
    }

    fn setRelative(s: *Scanner, p: *Ptr, amount: i64, behavior: i64, keep_time: bool) !void {
        const ru = lookupRelunit(p) orelse return;
        const r = &s.t.relative;
        switch (ru.unit) {
            .microsec => try s.addWithOverflow(&r.us, amount, ru.mult),
            .second => try s.addWithOverflow(&r.s, amount, ru.mult),
            .minute => try s.addWithOverflow(&r.i, amount, ru.mult),
            .hour => try s.addWithOverflow(&r.h, amount, ru.mult),
            .day => try s.addWithOverflow(&r.d, amount, ru.mult),
            .month => try s.addWithOverflow(&r.m, amount, ru.mult),
            .year => try s.addWithOverflow(&r.y, amount, ru.mult),
            .weekday => {
                s.haveWeekdayRelative();
                if (!keep_time) s.unhaveTime();
                r.d +%= (if (amount > 0) amount - 1 else amount) *% 7;
                r.weekday = ru.mult;
                r.weekday_behavior = behavior;
            },
            .special => {
                s.haveSpecialRelative();
                if (!keep_time) s.unhaveTime();
                r.special_type = @intCast(ru.mult);
                r.special_amount = amount;
            },
        }
    }

    fn parseTzCor(p: *Ptr, not_found: *bool) i64 {
        const begin = p.i;
        not_found.* = true;
        while (isDigit(p.c()) or p.c() == ':') p.i += 1;
        const s = p.s;
        const at = struct {
            fn f(str: []const u8, k: usize) u8 {
                return if (k < str.len) str[k] else 0;
            }
        }.f;
        switch (p.i - begin) {
            1, 2 => {
                not_found.* = false;
                return strtol(s, begin) *% 3600;
            },
            3, 4 => {
                not_found.* = false;
                if (at(s, begin + 1) == ':') return strtol(s, begin) *% 3600 +% strtol(s, begin + 2) *% 60;
                if (at(s, begin + 2) == ':') return strtol(s, begin) *% 3600 +% strtol(s, begin + 3) *% 60;
                const tmp = strtol(s, begin);
                return @divTrunc(tmp, 100) * 3600 + @rem(tmp, 100) * 60;
            },
            5 => {
                if (at(s, begin + 2) != ':') return 0;
                not_found.* = false;
                return strtol(s, begin) *% 3600 +% strtol(s, begin + 3) *% 60;
            },
            6 => {
                not_found.* = false;
                const tmp = strtol(s, begin);
                return @divTrunc(tmp, 10000) * 3600 + @rem(@divTrunc(tmp, 100), 100) * 60 + @rem(tmp, 100);
            },
            8 => {
                if (at(s, begin + 2) != ':' or at(s, begin + 5) != ':') return 0;
                not_found.* = false;
                return strtol(s, begin) *% 3600 +% strtol(s, begin + 3) *% 60 +% strtol(s, begin + 6);
            },
            else => return 0,
        }
    }

    // timelib_parse_zone: an offset, an abbreviation, or a zone id
    fn parseZone(s: *Scanner, p: *Ptr, not_found: *bool) i64 {
        return parseZoneInto(s.t, p, not_found, s.db);
    }
};

// timelib_parse_zone over a whole string, as DateTimeZone's constructor uses
// it: the zone lands in `time`, and `rest` is whatever followed it
pub const ZoneParse = struct { time: Time, not_found: bool, rest: usize };

pub fn parseZoneString(s: []const u8, db: TzDb) ZoneParse {
    var t = Time{};
    var p = Ptr{ .s = s };
    var not_found = false;
    t.z = parseZoneInto(&t, &p, &not_found, db);
    return .{ .time = t, .not_found = not_found, .rest = s.len - @min(p.i, s.len) };
}

fn parseZoneInto(t: *Time, p: *Ptr, not_found: *bool, db: TzDb) i64 {
    var retval: i64 = 0;
    var parens: usize = 0;
    not_found.* = false;
    while (p.c() == ' ' or p.c() == '\t' or p.c() == '(') {
        if (p.c() == '(') parens += 1;
        p.i += 1;
    }
    if (p.c() == 'G' and p.at(1) == 'M' and p.at(2) == 'T' and (p.at(3) == '+' or p.at(3) == '-')) p.i += 3;
    if (p.c() == '+') {
        p.i += 1;
        t.is_localtime = true;
        t.zone_type = ZONETYPE_OFFSET;
        t.dst = 0;
        retval = Scanner.parseTzCor(p, not_found);
    } else if (p.c() == '-') {
        p.i += 1;
        t.is_localtime = true;
        t.zone_type = ZONETYPE_OFFSET;
        t.dst = 0;
        retval = -%Scanner.parseTzCor(p, not_found);
    } else {
        var found = false;
        t.is_localtime = true;
        const begin = p.i;
        while (true) {
            const c = p.c();
            if (!(isLetter(c) or isDigit(c) or c == '/' or c == '_' or c == '-' or c == '+')) break;
            p.i += 1;
        }
        const word = p.s[begin..p.i];
        if (word.len < MAX_ABBR_LEN) {
            if (abbrSearch(word)) |hit| {
                const dst: i64 = if (hit.dst) 1 else 0;
                retval = hit.offset - dst * 3600;
                t.zone_type = ZONETYPE_ABBR;
                t.dst = dst;
                t.setAbbr(word);
                found = true;
            }
        }
        if (!found or std.mem.eql(u8, word, "UTC")) {
            var buf: [64]u8 = undefined;
            if (db.lookupId(word, &buf)) |canonical| {
                t.setId(canonical);
                t.zone_type = ZONETYPE_ID;
                found = true;
            }
        }
        not_found.* = !found;
    }
    while (parens > 0 and p.c() == ')') {
        p.i += 1;
        parens -= 1;
    }
    return retval;
}

fn zoneOrError(s: *Scanner, p: *Ptr) !void {
    var not_found = false;
    s.t.z = s.parseZone(p, &not_found);
    if (not_found) try s.addError("The timezone could not be found in the database");
}

fn action(s: *Scanner, act: Act, tok: []const u8) !void {
    const t = s.t;
    var p = Ptr{ .s = tok };
    switch (act) {
        .skip => {},
        .unexpected => try s.addError("Unexpected character"),
        .yesterday, .tomorrow => {
            t.have_relative = true;
            s.unhaveTime();
            t.relative.d = if (act == .yesterday) -1 else 1;
        },
        .now => {},
        .noon => {
            s.unhaveTime();
            if (!try s.haveTime()) return;
            t.h = 12;
        },
        .midnight_today => s.unhaveTime(),
        .timestamp, .timestampms => {
            t.have_relative = true;
            s.unhaveDate();
            s.unhaveTime();
            if (!try s.haveTz()) return;
            const negative = p.at(1) == '-';
            const i = try s.getSignedNr(&p, 24);
            var us: i64 = 0;
            if (act == .timestampms) {
                const before = p.i;
                us = try s.getSignedNr(&p, 6);
                us = toInt(@as(f64, @floatFromInt(us)) * pow10(7 - @as(i64, @intCast(p.i - before))));
                if (negative) us = -us;
            }
            t.y = 1970;
            t.m = 1;
            t.d = 1;
            t.h = 0;
            t.i = 0;
            t.s = 0;
            t.us = 0;
            t.relative.s +%= i;
            if (act == .timestampms) t.relative.us = us;
            t.is_localtime = true;
            t.zone_type = ZONETYPE_OFFSET;
            t.z = 0;
            t.dst = 0;
        },
        .firstlastdayof => {
            t.have_relative = true;
            t.relative.first_last_day_of = if (p.c() == 'l' or p.c() == 'L') LAST_DAY_OF_MONTH else FIRST_DAY_OF_MONTH;
        },
        .backfrontof => {
            s.unhaveTime();
            if (!try s.haveTime()) return;
            if (p.c() == 'b') {
                t.h = getNr(&p, 2);
                t.i = 15;
            } else {
                t.h = getNr(&p, 2) - 1;
                t.i = 45;
            }
            if (p.c() != 0) {
                eatSpaces(&p);
                t.h += meridian(&p, t.h);
            }
        },
        .weekdayof => {
            t.have_relative = true;
            s.haveSpecialRelative();
            var behavior: i64 = 0;
            const i = getRelativeText(&p, &behavior);
            eatSpaces(&p);
            if (i > 0) {
                t.relative.special_type = SPECIAL_DAY_OF_WEEK_IN_MONTH;
                try s.setRelative(&p, i, 1, false);
            } else {
                t.relative.special_type = SPECIAL_LAST_DAY_OF_WEEK_IN_MONTH;
                try s.setRelative(&p, i, behavior, false);
            }
        },
        .time12 => {
            if (!try s.haveTime()) return;
            t.h = getNr(&p, 2);
            if (p.c() == ':' or p.c() == '.') {
                t.i = getNr(&p, 2);
                if (p.c() == ':' or p.c() == '.') t.s = getNr(&p, 2);
            }
            eatSpaces(&p);
            t.h += meridian(&p, t.h);
        },
        .mssqltime => {
            if (!try s.haveTime()) return;
            t.h = getNr(&p, 2);
            t.i = getNr(&p, 2);
            if (p.c() == ':' or p.c() == '.') {
                t.s = getNr(&p, 2);
                if (p.c() == ':' or p.c() == '.') t.us = getFracNr(&p);
            }
            eatSpaces(&p);
            t.h += meridian(&p, t.h);
        },
        .time24 => {
            if (!try s.haveTime()) return;
            t.h = getNr(&p, 2);
            if (p.c() == ':' or p.c() == '.') {
                t.i = getNr(&p, 2);
                if (p.c() == ':' or p.c() == '.') {
                    t.s = getNr(&p, 2);
                    if (p.c() == '.') t.us = getFracNr(&p);
                }
            }
            if (p.c() != 0) try zoneOrError(s, &p);
        },
        .gnunocolon => {
            switch (t.have_time) {
                0 => {
                    t.h = getNr(&p, 2);
                    t.i = getNr(&p, 2);
                    t.s = 0;
                },
                1 => t.y = getNr(&p, 4),
                else => {
                    try s.addError("Double time specification");
                    return;
                },
            }
            t.have_time += 1;
        },
        .iso8601nocolon => {
            if (!try s.haveTime()) return;
            t.h = getNr(&p, 2);
            t.i = getNr(&p, 2);
            t.s = getNr(&p, 2);
            if (p.c() != 0) try zoneOrError(s, &p);
        },
        .american => {
            if (!try s.haveDate()) return;
            t.m = getNr(&p, 2);
            t.d = getNr(&p, 2);
            if (p.c() == '/') {
                var len: usize = 0;
                t.y = getNrEx(&p, 4, &len);
                processYear(&t.y, len);
            }
        },
        .iso8601date4 => {
            if (!try s.haveDate()) return;
            t.y = try s.getSignedNr(&p, 4);
            t.m = getNr(&p, 2);
            t.d = getNr(&p, 2);
        },
        .iso8601date2 => {
            if (!try s.haveDate()) return;
            var len: usize = 0;
            t.y = getNrEx(&p, 4, &len);
            t.m = getNr(&p, 2);
            t.d = getNr(&p, 2);
            processYear(&t.y, len);
        },
        .iso8601datex => {
            if (!try s.haveDate()) return;
            t.y = try s.getSignedNr(&p, 19);
            t.m = getNr(&p, 2);
            t.d = getNr(&p, 2);
        },
        .gnudateshorter => {
            if (!try s.haveDate()) return;
            var len: usize = 0;
            t.y = getNrEx(&p, 4, &len);
            t.m = getNr(&p, 2);
            t.d = 1;
            processYear(&t.y, len);
        },
        .gnudateshort => {
            if (!try s.haveDate()) return;
            var len: usize = 0;
            t.y = getNrEx(&p, 4, &len);
            t.m = getNr(&p, 2);
            t.d = getNr(&p, 2);
            processYear(&t.y, len);
        },
        .datefull => {
            if (!try s.haveDate()) return;
            t.d = getNr(&p, 2);
            skipDaySuffix(&p);
            t.m = getMonth(&p);
            var len: usize = 0;
            t.y = getNrEx(&p, 4, &len);
            processYear(&t.y, len);
        },
        .pointeddate4 => {
            if (!try s.haveDate()) return;
            t.d = getNr(&p, 2);
            t.m = getNr(&p, 2);
            t.y = getNr(&p, 4);
        },
        .pointeddate2 => {
            if (!try s.haveDate()) return;
            t.d = getNr(&p, 2);
            t.m = getNr(&p, 2);
            var len: usize = 0;
            t.y = getNrEx(&p, 2, &len);
            processYear(&t.y, len);
        },
        .datenoday => {
            if (!try s.haveDate()) return;
            t.m = getMonth(&p);
            var len: usize = 0;
            t.y = getNrEx(&p, 4, &len);
            t.d = 1;
            processYear(&t.y, len);
        },
        .datenodayrev => {
            if (!try s.haveDate()) return;
            var len: usize = 0;
            t.y = getNrEx(&p, 4, &len);
            t.m = getMonth(&p);
            t.d = 1;
            processYear(&t.y, len);
        },
        .datetextual => {
            if (!try s.haveDate()) return;
            t.m = getMonth(&p);
            t.d = getNr(&p, 2);
            var len: usize = 0;
            t.y = getNrEx(&p, 4, &len);
            processYear(&t.y, len);
        },
        .datenoyearrev => {
            if (!try s.haveDate()) return;
            t.d = getNr(&p, 2);
            skipDaySuffix(&p);
            t.m = getMonth(&p);
        },
        .datenocolon => {
            if (!try s.haveDate()) return;
            t.y = getNr(&p, 4);
            t.m = getNr(&p, 2);
            t.d = getNr(&p, 2);
        },
        .xmlrpc => {
            if (!try s.haveTime()) return;
            if (!try s.haveDate()) return;
            t.y = getNr(&p, 4);
            t.m = getNr(&p, 2);
            t.d = getNr(&p, 2);
            t.h = getNr(&p, 2);
            t.i = getNr(&p, 2);
            t.s = getNr(&p, 2);
            if (p.c() == '.') {
                t.us = getFracNr(&p);
                if (p.c() != 0) try zoneOrError(s, &p);
            }
        },
        .pgydotd => {
            if (!try s.haveDate()) return;
            var len: usize = 0;
            t.y = getNrEx(&p, 4, &len);
            t.d = getNr(&p, 3);
            t.m = 1;
            processYear(&t.y, len);
        },
        .isoweekday, .isoweek => {
            if (!try s.haveDate()) return;
            t.have_relative = true;
            t.y = getNr(&p, 4);
            const w = getNr(&p, 2);
            const d = if (act == .isoweekday) getNr(&p, 1) else 1;
            t.m = 1;
            t.d = 1;
            t.relative.d = daynrFromWeeknr(t.y, w, d);
        },
        .pgtextshort => {
            if (!try s.haveDate()) return;
            t.m = getMonth(&p);
            t.d = getNr(&p, 2);
            var len: usize = 0;
            t.y = getNrEx(&p, 4, &len);
            processYear(&t.y, len);
        },
        .pgtextreverse => {
            if (!try s.haveDate()) return;
            var len: usize = 0;
            t.y = getNrEx(&p, 4, &len);
            t.m = getMonth(&p);
            t.d = getNr(&p, 2);
            processYear(&t.y, len);
        },
        .clf => {
            if (!try s.haveTime()) return;
            if (!try s.haveDate()) return;
            t.d = getNr(&p, 2);
            t.m = getMonth(&p);
            t.y = getNr(&p, 4);
            t.h = getNr(&p, 2);
            t.i = getNr(&p, 2);
            t.s = getNr(&p, 2);
            eatSpaces(&p);
            try zoneOrError(s, &p);
        },
        .year4 => t.y = getNr(&p, 4),
        .ago => {
            const r = &t.relative;
            r.y = 0 -% r.y;
            r.m = 0 -% r.m;
            r.d = 0 -% r.d;
            r.h = 0 -% r.h;
            r.i = 0 -% r.i;
            r.s = 0 -% r.s;
            r.weekday = 0 -% r.weekday;
            if (r.weekday == 0) r.weekday = -7;
            if (r.have_special_relative and r.special_type == SPECIAL_WEEKDAY) r.special_amount = 0 -% r.special_amount;
        },
        .daytext => {
            t.have_relative = true;
            s.haveWeekdayRelative();
            s.unhaveTime();
            const ru = lookupRelunit(&p) orelse return;
            t.relative.weekday = ru.mult;
            if (t.relative.weekday_behavior != 2) t.relative.weekday_behavior = 1;
        },
        .relativetextweek, .relativetext => {
            t.have_relative = true;
            while (p.c() != 0) {
                const before = p.i;
                var behavior: i64 = 0;
                const i = getRelativeText(&p, &behavior);
                eatSpaces(&p);
                try s.setRelative(&p, i, behavior, false);
                if (act == .relativetextweek) {
                    t.relative.weekday_behavior = 2;
                    // "this week" and friends without a weekday mean monday
                    if (!t.relative.have_weekday_relative) {
                        s.haveWeekdayRelative();
                        t.relative.weekday = 1;
                    }
                }
                if (p.i == before) break;
            }
        },
        .monthtext => {
            if (!try s.haveDate()) return;
            t.m = lookupMonth(&p);
        },
        .tz => {
            if (!try s.haveTz()) return;
            eatSpaces(&p);
            try zoneOrError(s, &p);
        },
        .dateshortwithtime12 => {
            if (!try s.haveDate()) return;
            t.m = getMonth(&p);
            t.d = getNr(&p, 2);
            if (!try s.haveTime()) return;
            t.h = getNr(&p, 2);
            t.i = getNr(&p, 2);
            if (p.c() == ':' or p.c() == '.') {
                t.s = getNr(&p, 2);
                if (p.c() == '.') t.us = getFracNr(&p);
            }
            t.h += meridian(&p, t.h);
        },
        .dateshortwithtime24 => {
            if (!try s.haveDate()) return;
            t.m = getMonth(&p);
            t.d = getNr(&p, 2);
            if (!try s.haveTime()) return;
            t.h = getNr(&p, 2);
            t.i = getNr(&p, 2);
            if (p.c() == ':') {
                t.s = getNr(&p, 2);
                if (p.c() == '.') t.us = getFracNr(&p);
            }
            if (p.c() != 0) try zoneOrError(s, &p);
        },
        .relative => {
            t.have_relative = true;
            while (p.c() != 0) {
                const before = p.i;
                const i = try s.getSignedNr(&p, 24);
                eatSpaces(&p);
                try s.setRelative(&p, i, 1, true);
                if (p.i == before) break;
            }
        },
    }
}

fn isTrimSpace(c: u8) bool {
    return isSpaceC(c);
}

// timelib_strtotime: scan a date string into fields, a zone, and a relative
// part. errors and warnings carry the byte position in the trimmed string
// timelib stops recording errors and warnings past this many of each
const max_errors = 1000;

pub fn parse(a: Allocator, input: []const u8, db: TzDb) !Parsed {
    var out = Parsed{};
    errdefer out.deinit(a);
    var start: usize = 0;
    var end: usize = input.len; // exclusive
    if (input.len > 0) {
        var e = input.len - 1;
        while (start <= e and isTrimSpace(input[start])) start += 1;
        while (start <= e and e > start and isTrimSpace(input[e])) e -= 1;
        end = e + 1;
    }
    // nothing left once the whitespace is trimmed
    if (start >= end) {
        try out.errors.append(a, .{ .pos = 0, .char = 0, .msg = "Empty string" });
        out.time.is_localtime = false;
        out.time.zone_type = 0;
        return out;
    }
    const len = end - start;
    // the scanner reads a few bytes past the end, so the text is copied with
    // nul padding, on the stack when it is short
    const pad = 16;
    var stack_buf: [256]u8 = undefined;
    const buf = if (len + pad <= stack_buf.len) stack_buf[0 .. len + pad] else try a.alloc(u8, len + pad);
    defer if (buf.ptr != &stack_buf) a.free(buf);
    @memcpy(buf[0..len], input[start..end]);
    @memset(buf[len..], 0);

    var s = Scanner{ .a = a, .buf = buf, .len = len, .t = &out.time, .p = &out, .db = db };
    {
        // zone lookups inside actions take only the zone cache's own lock
        dfa_mutex.lock();
        defer dfa_mutex.unlock();
        while (true) {
            s.tok = s.cur;
            if (s.cur > s.len) break;
            const m = try longestMatch(buf, s.cur);
            s.cur += m.len;
            try action(&s, rules[m.rule].act, buf[s.tok..s.cur]);
        }
    }
    const t = &out.time;
    if (t.have_time != 0 and !validTime(t.h, t.i, t.s)) try s.addWarning("The parsed time was invalid");
    if (t.have_date != 0 and !validDate(t.y, t.m, t.d)) try s.addWarning("The parsed date was invalid");
    return out;
}

// ---- parsing against a format (timelib_parse_from_format) ----

const FormatCode = enum {
    textual_day,
    day,
    day_suffix,
    day_of_year,
    month,
    textual_month,
    year2,
    year4,
    year_expanded,
    hour12,
    hour24,
    meridian,
    minute,
    second,
    microsecond,
    millisecond,
    whitespace,
    epoch_seconds,
    any_separator,
    separator,
    reset_all,
    reset_unset,
    random_char,
    escape,
    skip_to_separator,
    allow_extra,
    timezone,
    literal,
};

// default_format_map; anything else is a literal
fn formatCode(c: u8) FormatCode {
    return switch (c) {
        '+' => .allow_extra,
        '#' => .any_separator,
        'j', 'd' => .day,
        'z' => .day_of_year,
        'S' => .day_suffix,
        'U' => .epoch_seconds,
        '\\' => .escape,
        'h', 'g' => .hour12,
        'H', 'G' => .hour24,
        'a', 'A' => .meridian,
        'u' => .microsecond,
        'v' => .millisecond,
        'i' => .minute,
        'n', 'm' => .month,
        '?' => .random_char,
        '!' => .reset_all,
        '|' => .reset_unset,
        's' => .second,
        ';', ':', '/', '.', ',', '-', '(', ')' => .separator,
        '*' => .skip_to_separator,
        'D', 'l' => .textual_day,
        'M', 'F' => .textual_month,
        'e', 'P', 'p', 'T', 'O' => .timezone,
        ' ' => .whitespace,
        'y' => .year2,
        'Y' => .year4,
        'x', 'X' => .year_expanded,
        else => .literal,
    };
}

// timelib_meridian_with_check: unlike the scanner's meridian, the "m" (and the
// dots around it) must be there
fn meridianWithCheck(p: *Ptr, h: i64) i64 {
    var ret: i64 = 0;
    while (p.c() != 0 and p.c() != 'A' and p.c() != 'a' and p.c() != 'P' and p.c() != 'p') p.i += 1;
    if (p.c() == 0) return UNSET;
    if (p.c() == 'a' or p.c() == 'A') {
        if (h == 12) ret = -12;
    } else if (h != 12) {
        ret = 12;
    }
    p.i += 1;
    if (p.c() == '.') {
        p.i += 1;
        if (p.c() != 'm' and p.c() != 'M') return UNSET;
        p.i += 1;
        if (p.c() != '.') return UNSET;
        p.i += 1;
    } else if (p.c() == 'm' or p.c() == 'M') {
        p.i += 1;
    } else {
        return UNSET;
    }
    return ret;
}

// strchr(set, c) in c also finds the terminating nul
fn inSetOrNul(set: []const u8, c: u8) bool {
    return c == 0 or std.mem.indexOfScalar(u8, set, c) != null;
}

// timelib_unixtime2gmt's fields: the utc wall clock of t.sse
fn fieldsFromSse(t: *Time, ts: i64) void {
    const days = @divFloor(ts, 86400);
    const rem = ts - days *% 86400;
    dateFromEpochDays(days, &t.y, &t.m, &t.d);
    t.h = @divTrunc(rem, 3600);
    t.i = @divTrunc(rem - t.h * 3600, 60);
    t.s = @rem(rem, 60);
}

fn resetFields(t: *Time) void {
    t.y = 1970;
    t.m = 1;
    t.d = 1;
    t.h = 0;
    t.i = 0;
    t.s = 0;
    t.us = 0;
    t.has_id = false;
}

fn resetUnsetFields(t: *Time) void {
    if (t.y == UNSET) t.y = 1970;
    if (t.m == UNSET) t.m = 1;
    if (t.d == UNSET) t.d = 1;
    if (t.h == UNSET) t.h = 0;
    if (t.i == UNSET) t.i = 0;
    if (t.s == UNSET) t.s = 0;
    if (t.us == UNSET) t.us = 0;
}

// timelib_parse_from_format with php's default format map. the input ends at
// its first nul, as the c string does. the iso specifiers of other maps don't
// exist here
pub fn parseFromFormat(a: Allocator, format: []const u8, input: []const u8, db: TzDb) !Parsed {
    var out = Parsed{};
    errdefer out.deinit(a);
    const t = &out.time;
    // errors raised inside the number readers carry no token: position 0, no
    // character
    const no_tok = [_]u8{0};
    var s = Scanner{ .a = a, .buf = &no_tok, .len = 0, .t = t, .p = &out, .db = db };
    var f = Ptr{ .s = format };
    var p = Ptr{ .s = input };
    var allow_extra = false;

    const at = struct {
        fn err(o: *Parsed, al: Allocator, in: *const Ptr, pos: usize, msg: []const u8) !void {
            if (o.errors.items.len >= max_errors) return;
            try o.errors.append(al, .{ .pos = pos, .char = if (pos < in.s.len) in.s[pos] else 0, .msg = msg });
        }
        fn warn(o: *Parsed, al: Allocator, in: *const Ptr, pos: usize, msg: []const u8) !void {
            if (o.warnings.items.len >= max_errors) return;
            try o.warnings.append(al, .{ .pos = pos, .char = if (pos < in.s.len) in.s[pos] else 0, .msg = msg });
        }
    };

    while (f.c() != 0 and p.c() != 0) {
        const begin = p.i;
        switch (formatCode(f.c())) {
            .textual_day => {
                if (lookupRelunit(&p)) |ru| {
                    t.have_relative = true;
                    t.relative.have_weekday_relative = true;
                    t.relative.weekday = ru.mult;
                    t.relative.weekday_behavior = 1;
                } else {
                    try at.err(&out, a, &p, begin, "A textual day could not be found");
                }
            },
            .day => {
                if (!inSetOrNul("0123456789", p.c())) try at.err(&out, a, &p, begin, "Unexpected data found.");
                t.d = getNr(&p, 2);
                if (t.d == UNSET) {
                    try at.err(&out, a, &p, begin, "A two digit day could not be found");
                } else t.have_date = 1;
            },
            .day_suffix => skipDaySuffix(&p),
            .day_of_year => {
                if (!inSetOrNul("0123456789", p.c())) try at.err(&out, a, &p, begin, "Unexpected data found.");
                if (t.y == UNSET) try at.err(&out, a, &p, begin, "A 'day of year' can only come after a year has been found");
                const tmp = getNr(&p, 3);
                if (tmp == UNSET) {
                    try at.err(&out, a, &p, begin, "A three digit day-of-year could not be found");
                } else if (t.y != UNSET) {
                    t.have_date = 1;
                    t.m = 1;
                    t.d = tmp + 1;
                    doNormalize(t);
                }
            },
            .month => {
                if (!inSetOrNul("0123456789", p.c())) try at.err(&out, a, &p, begin, "Unexpected data found.");
                t.m = getNr(&p, 2);
                if (t.m == UNSET) {
                    try at.err(&out, a, &p, begin, "A two digit month could not be found");
                } else t.have_date = 1;
            },
            .textual_month => {
                const tmp = lookupMonth(&p);
                if (tmp == 0) {
                    try at.err(&out, a, &p, begin, "A textual month could not be found");
                } else {
                    t.have_date = 1;
                    t.m = tmp;
                }
            },
            .year2 => {
                if (!inSetOrNul("0123456789", p.c())) try at.err(&out, a, &p, begin, "Unexpected data found.");
                var length: usize = 0;
                t.y = getNrEx(&p, 2, &length);
                if (t.y == UNSET) {
                    try at.err(&out, a, &p, begin, "A two digit year could not be found");
                } else {
                    t.have_date = 1;
                    processYear(&t.y, length);
                }
            },
            .year4 => {
                if (!inSetOrNul("0123456789", p.c())) try at.err(&out, a, &p, begin, "Unexpected data found.");
                t.y = getNr(&p, 4);
                if (t.y == UNSET) {
                    try at.err(&out, a, &p, begin, "A four digit year could not be found");
                } else t.have_date = 1;
            },
            .year_expanded => {
                if (!inSetOrNul("+-0123456789", p.c())) try at.err(&out, a, &p, begin, "Unexpected data found.");
                t.y = try s.getSignedNr(&p, 19);
                if (t.y == UNSET) {
                    try at.err(&out, a, &p, begin, "An expanded digit year could not be found");
                } else t.have_date = 1;
            },
            .hour12 => {
                if (!inSetOrNul("0123456789", p.c())) try at.err(&out, a, &p, begin, "Unexpected data found.");
                t.h = getNr(&p, 2);
                if (t.h == UNSET) {
                    try at.err(&out, a, &p, begin, "A two digit hour could not be found");
                } else if (t.h > 12) {
                    try at.err(&out, a, &p, begin, "Hour cannot be higher than 12");
                } else t.have_time = 1;
            },
            .hour24 => {
                if (!inSetOrNul("0123456789", p.c())) try at.err(&out, a, &p, begin, "Unexpected data found.");
                t.h = getNr(&p, 2);
                if (t.h == UNSET) {
                    try at.err(&out, a, &p, begin, "A two digit hour could not be found");
                } else t.have_time = 1;
            },
            .meridian => {
                if (t.h == UNSET) try at.err(&out, a, &p, begin, "Meridian can only come after an hour has been found");
                const tmp = meridianWithCheck(&p, t.h);
                if (tmp == UNSET) {
                    try at.err(&out, a, &p, begin, "A meridian could not be found");
                } else {
                    t.have_time = 1;
                    if (t.h != UNSET) t.h += tmp;
                }
            },
            .minute, .second => {
                const is_min = formatCode(f.c()) == .minute;
                if (!inSetOrNul("0123456789", p.c())) try at.err(&out, a, &p, begin, "Unexpected data found.");
                var length: usize = 0;
                const v = getNrEx(&p, 2, &length);
                if (v == UNSET or length != 2) {
                    try at.err(&out, a, &p, begin, if (is_min) "A two digit minute could not be found" else "A two digit second could not be found");
                } else {
                    t.have_time = 1;
                    if (is_min) t.i = v else t.s = v;
                }
            },
            .microsecond, .millisecond => {
                const micro = formatCode(f.c()) == .microsecond;
                if (!inSetOrNul("0123456789", p.c())) try at.err(&out, a, &p, begin, "Unexpected data found.");
                const tptr = p.i;
                const v = getNr(&p, if (micro) 6 else 3);
                if (v == UNSET or p.i - tptr < 1) {
                    try at.err(&out, a, &p, begin, if (micro) "A six digit microsecond could not be found" else "A three digit millisecond could not be found");
                } else {
                    // the digit count includes anything skipped before the digits
                    const scale: i64 = (if (micro) @as(i64, 6) else 3) - @as(i64, @intCast(p.i - tptr));
                    const fv = @as(f64, @floatFromInt(v)) * std.math.pow(f64, 10, @floatFromInt(scale));
                    t.us = toInt(if (micro) fv else fv * 1000);
                }
            },
            .whitespace => eatSpaces(&p),
            .epoch_seconds => {
                if (!inSetOrNul("+-0123456789", p.c())) try at.err(&out, a, &p, begin, "Unexpected data found.");
                const tmp = try s.getSignedNr(&p, 24);
                t.have_zone = 1;
                t.sse = tmp;
                t.is_localtime = true;
                t.zone_type = ZONETYPE_OFFSET;
                t.z = 0;
                t.dst = 0;
                fieldsFromSse(t, tmp);
            },
            .any_separator => {
                if (formatCode(p.c()) != .separator) {
                    try at.err(&out, a, &p, begin, "The separation symbol ([;:/.,-]) could not be found");
                } else p.i += 1;
            },
            .separator => {
                if (p.c() != f.c()) {
                    try at.err(&out, a, &p, begin, "The separation symbol could not be found");
                } else p.i += 1;
            },
            .reset_all => resetFields(t),
            .reset_unset => resetUnsetFields(t),
            .random_char => p.i += 1,
            .escape => blk: {
                if (f.at(1) == 0) {
                    try at.err(&out, a, &p, begin, "Escaped character expected");
                    break :blk;
                }
                f.i += 1;
                if (p.c() != f.c()) {
                    try at.err(&out, a, &p, begin, "The escaped character could not be found");
                } else p.i += 1;
            },
            .skip_to_separator => {
                p.i += 1;
                while (!inSetOrNul(" \t.,:;/-0123456789", p.c())) p.i += 1;
            },
            .allow_extra => allow_extra = true,
            .timezone => {
                var not_found = false;
                t.z = parseZoneInto(t, &p, &not_found, db);
                if (not_found) {
                    try at.err(&out, a, &p, begin, "The timezone could not be found in the database");
                } else t.have_zone = 1;
            },
            .literal => {
                if (f.c() != p.c()) try at.err(&out, a, &p, begin, "The format separator does not match");
                p.i += 1;
            },
        }
        f.i += 1;
    }
    if (p.c() != 0) {
        if (allow_extra) {
            try at.warn(&out, a, &p, p.i, "Trailing data");
        } else {
            try at.err(&out, a, &p, p.i, "Trailing data");
        }
    }
    // trailing reset specifiers are valid
    while (f.c() != 0) : (f.i += 1) {
        switch (formatCode(f.c())) {
            .reset_all => resetFields(t),
            .reset_unset => resetUnsetFields(t),
            .allow_extra => {},
            else => {
                try at.err(&out, a, &p, p.i, "Not enough data available to satisfy format");
                break;
            },
        }
    }
    if (t.h != UNSET or t.i != UNSET or t.s != UNSET or t.us != UNSET) {
        if (t.h == UNSET) t.h = 0;
        if (t.i == UNSET) t.i = 0;
        if (t.s == UNSET) t.s = 0;
        if (t.us == UNSET) t.us = 0;
    }
    if (t.h != UNSET and t.i != UNSET and t.s != UNSET and !validTime(t.h, t.i, t.s)) try at.warn(&out, a, &p, p.i, "The parsed time was invalid");
    if (t.y != UNSET and t.m != UNSET and t.d != UNSET and !validDate(t.y, t.m, t.d)) try at.warn(&out, a, &p, p.i, "The parsed date was invalid");
    return out;
}

// ---- calendar helpers (dow.c) ----

pub fn isLeap(y: i64) bool {
    return @rem(y, 4) == 0 and (@rem(y, 100) != 0 or @rem(y, 400) == 0);
}

const m_table_common = [13]i64{ -1, 0, 3, 3, 6, 1, 4, 6, 2, 5, 0, 3, 5 };
const m_table_leap = [13]i64{ -1, 6, 2, 3, 6, 1, 4, 6, 2, 5, 0, 3, 5 };
const ml_table_common = [13]i64{ 0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
const ml_table_leap = [13]i64{ 0, 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
// indexed by month with december at 0, as tm2unixtime.c does
const dim_leap = [13]i64{ 31, 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
const dim_common = [13]i64{ 31, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

fn positiveMod(x: i64, y: i64) i64 {
    var tmp = @rem(x, y);
    if (tmp < 0) tmp += y;
    return tmp;
}

fn monthIndex(m: i64) usize {
    return @intCast(std.math.clamp(m, 0, 12));
}

pub fn dayOfWeek(y: i64, m: i64, d: i64) i64 {
    const c1 = 6 - positiveMod(@divTrunc(positiveMod(y, 400), 100), 4) * 2;
    const y1 = positiveMod(y, 100);
    const m1 = if (isLeap(y)) m_table_leap[monthIndex(m)] else m_table_common[monthIndex(m)];
    return positiveMod(c1 +% y1 +% m1 +% @divTrunc(y1, 4) +% d, 7);
}

pub fn daysInMonth(y: i64, m: i64) i64 {
    return if (isLeap(y)) ml_table_leap[monthIndex(m)] else ml_table_common[monthIndex(m)];
}

pub fn validTime(h: i64, i: i64, s: i64) bool {
    return !(h < 0 or h > 23 or i < 0 or i > 59 or s < 0 or s > 59);
}

pub fn validDate(y: i64, m: i64, d: i64) bool {
    return !(m < 1 or m > 12 or d < 1 or d > daysInMonth(y, m));
}

pub fn daynrFromWeeknr(iy: i64, iw: i64, id_: i64) i64 {
    const dow = dayOfWeek(iy, 1, 1);
    const day = 0 - (if (dow > 4) dow - 7 else dow);
    return day +% (iw -% 1) *% 7 +% id_;
}

// civil date from days since 1970-01-01 (timelib_date_from_epoch_days). the
// day-of-era steps are unsigned in c, which only shows when days wrapped
pub fn dateFromEpochDays(epoch_days: i64, y: *i64, m: *i64, d: *i64) void {
    const days = epoch_days +% 719468;
    const era = @divTrunc(if (days >= 0) days else days -% 146096, 146097);
    const doe: u64 = @bitCast(days -% era *% 146097);
    const yoe = (doe -% doe / 1460 +% doe / 36524 -% doe / 146096) / 365;
    const doy = doe -% (365 *% yoe +% yoe / 4 -% yoe / 100);
    const mp = (5 *% doy +% 2) / 153;
    d.* = @bitCast(doy -% (153 *% mp +% 2) / 5 +% 1);
    m.* = @bitCast(if (mp < 10) mp +% 3 else mp -% 9);
    y.* = @as(i64, @bitCast(yoe)) +% era *% 400 +% (if (m.* <= 2) @as(i64, 1) else 0);
}

// ---- resolving a parsed time (tm2unixtime.c) ----

fn rangeLimit(start: i64, end: i64, adj: i64, a: *i64, b: *i64) void {
    if (a.* < start) {
        const a_plus_1 = a.* +% 1;
        b.* -%= @divTrunc(start -% a_plus_1, adj) +% 1;
        a.* +%= adj *% @divTrunc(start -% a_plus_1, adj);
        a.* +%= adj;
    }
    if (a.* >= end) {
        b.* +%= @divTrunc(a.*, adj);
        a.* -%= adj *% @divTrunc(a.*, adj);
    }
}

fn rangeLimitDays(y: *i64, m: *i64, d: *i64) bool {
    const era_days: i64 = 146097;
    if (d.* >= era_days or d.* <= -era_days) {
        y.* +%= 400 *% @divTrunc(d.*, era_days);
        d.* -%= era_days *% @divTrunc(d.*, era_days);
    }
    rangeLimit(1, 13, 12, m, y);
    const table = if (isLeap(y.*)) &dim_leap else &dim_common;
    var ret = false;
    while (d.* <= 0 and m.* > 0) {
        var prev_m = m.* - 1;
        var prev_y = y.*;
        if (prev_m < 1) {
            prev_m += 12;
            prev_y -%= 1;
        }
        d.* +%= if (isLeap(prev_y)) dim_leap[monthIndex(prev_m)] else dim_common[monthIndex(prev_m)];
        m.* -= 1;
        ret = true;
    }
    while (d.* > 0 and m.* <= 12 and d.* > table[monthIndex(m.*)]) {
        d.* -= table[monthIndex(m.*)];
        m.* += 1;
        ret = true;
    }
    return ret;
}

pub fn doNormalize(t: *Time) void {
    if (t.us != UNSET) rangeLimit(0, 1000000, 1000000, &t.us, &t.s);
    if (t.s != UNSET) rangeLimit(0, 60, 60, &t.s, &t.i);
    if (t.s != UNSET) rangeLimit(0, 60, 60, &t.i, &t.h);
    if (t.s != UNSET) rangeLimit(0, 24, 24, &t.h, &t.d);
    rangeLimit(1, 13, 12, &t.m, &t.y);
    // short cut for dates against the epoch
    if (t.y == 1970 and t.m == 1) {
        dateFromEpochDays(t.d -% 1, &t.y, &t.m, &t.d);
        return;
    }
    while (rangeLimitDays(&t.y, &t.m, &t.d)) {}
    rangeLimit(1, 13, 12, &t.m, &t.y);
}

fn adjustForWeekday(t: *Time) void {
    const current_dow = dayOfWeek(t.y, t.m, t.d);
    const r = &t.relative;
    if (r.weekday_behavior == 2) {
        // "this week" from a sunday, and "sunday this week" from another day
        if (current_dow == 0 and r.weekday != 0) r.weekday -= 7;
        if (r.weekday == 0 and current_dow != 0) r.weekday = 7;
        t.d -%= current_dow;
        t.d +%= r.weekday;
        return;
    }
    var difference = r.weekday - current_dow;
    if ((r.d < 0 and difference < 0) or (r.d >= 0 and difference <= -r.weekday_behavior)) difference += 7;
    if (r.weekday >= 0) {
        t.d +%= difference;
    } else {
        const aw: i64 = if (r.weekday < 0) -r.weekday else r.weekday;
        t.d -%= 7 - (aw - current_dow);
    }
    r.have_weekday_relative = false;
}

fn adjustRelative(t: *Time) void {
    if (t.relative.have_weekday_relative) adjustForWeekday(t);
    doNormalize(t);
    if (t.have_relative) {
        t.us +%= t.relative.us;
        t.s +%= t.relative.s;
        t.i +%= t.relative.i;
        t.h +%= t.relative.h;
        t.d +%= t.relative.d;
        t.m +%= t.relative.m;
        t.y +%= t.relative.y;
    }
    switch (t.relative.first_last_day_of) {
        FIRST_DAY_OF_MONTH => t.d = 1,
        LAST_DAY_OF_MONTH => {
            t.d = 0;
            t.m +%= 1;
        },
        else => {},
    }
    doNormalize(t);
}

fn adjustSpecialWeekday(t: *Time) void {
    const count = t.relative.special_amount;
    const dow = dayOfWeek(t.y, t.m, t.d);
    t.d +%= @divTrunc(count, 5) *% 7;
    const rem = @rem(count, 5);
    if (count > 0) {
        if (rem == 0) {
            if (dow == 0) {
                t.d -%= 2;
            } else if (dow == 6) {
                t.d -%= 1;
            }
        } else if (dow == 6) {
            t.d +%= 1;
        } else if (dow + rem > 5) {
            t.d +%= 2;
        }
    } else {
        if (rem == 0) {
            if (dow == 6) {
                t.d +%= 2;
            } else if (dow == 0) {
                t.d +%= 1;
            }
        } else if (dow == 0) {
            t.d -%= 1;
        } else if (dow + rem < 1) {
            t.d -%= 2;
        }
    }
    t.d +%= rem;
}

fn adjustSpecial(t: *Time) void {
    if (t.relative.have_special_relative and t.relative.special_type == SPECIAL_WEEKDAY) adjustSpecialWeekday(t);
    doNormalize(t);
    t.relative.special_type = 0;
    t.relative.special_amount = 0;
}

fn adjustSpecialEarly(t: *Time) void {
    if (t.relative.have_special_relative) {
        switch (t.relative.special_type) {
            SPECIAL_DAY_OF_WEEK_IN_MONTH => {
                t.d = 1;
                t.m +%= t.relative.m;
                t.relative.m = 0;
            },
            SPECIAL_LAST_DAY_OF_WEEK_IN_MONTH => {
                t.d = 1;
                t.m +%= t.relative.m +% 1;
                t.relative.m = 0;
            },
            else => {},
        }
    }
    switch (t.relative.first_last_day_of) {
        FIRST_DAY_OF_MONTH => t.d = 1,
        LAST_DAY_OF_MONTH => {
            t.d = 0;
            t.m +%= 1;
        },
        else => {},
    }
    doNormalize(t);
}

pub fn epochDaysFromTime(t: *const Time) i64 {
    var y = t.y;
    if (t.m <= 2) y -%= 1;
    const era = @divTrunc(if (y >= 0) y else y -% 399, 400);
    const year_of_era = y -% era *% 400;
    const day_of_year = @divTrunc(153 * (t.m + (if (t.m > 2) @as(i64, -3) else 9)) + 2, 5) +% t.d - 1;
    const day_of_era = year_of_era *% 365 +% @divTrunc(year_of_era, 4) -% @divTrunc(year_of_era, 100) +% day_of_year;
    return era *% 146097 +% day_of_era -% 719468;
}

fn info(db: TzDb, id_: []const u8, ts: i64) OffsetInfo {
    return db.offsetInfo(id_, ts) orelse .{};
}

fn adjustTimezone(t: *Time, tzi: ?[]const u8, db: TzDb) void {
    switch (t.zone_type) {
        ZONETYPE_OFFSET => {
            t.is_localtime = true;
            t.sse +%= -%t.z;
            return;
        },
        ZONETYPE_ABBR => {
            t.is_localtime = true;
            t.sse +%= -%t.z -% t.dst *% 3600;
            return;
        },
        else => {},
    }
    const zone = if (t.zone_type == ZONETYPE_ID) t.id() else tzi;
    const name = zone orelse return;
    const current = info(db, name, t.sse);
    const after = info(db, name, t.sse -% current.offset);
    var actual_offset = after.offset;
    var actual_transition_time = after.transition_time;
    if (current.offset == after.offset and t.have_zone != 0) {
        if (current.offset >= 0 and t.dst != 0 and !current.is_dst) {
            const earlier = info(db, name, t.sse -% current.offset -% 7200);
            if (earlier.offset != after.offset and t.sse -% earlier.offset < after.transition_time) {
                actual_offset = earlier.offset;
                actual_transition_time = earlier.transition_time;
            }
        } else if (current.offset <= 0 and current.is_dst and t.dst == 0) {
            const later = info(db, name, t.sse -% current.offset +% 7200);
            if (later.offset != after.offset and t.sse -% later.offset >= later.transition_time) {
                actual_offset = later.offset;
                actual_transition_time = later.transition_time;
            }
        }
    }
    t.is_localtime = true;
    const local = t.sse -% actual_offset;
    const in_transition = actual_transition_time != std.math.minInt(i64) and
        local >= actual_transition_time +% (current.offset - actual_offset) and
        local < actual_transition_time;
    const adjustment = if (current.offset != actual_offset and !in_transition) -actual_offset else -current.offset;
    t.sse +%= adjustment;
    // timelib_set_timezone
    const now_info = info(db, name, t.sse);
    t.z = now_info.offset;
    t.dst = if (now_info.is_dst) 1 else 0;
    if (t.zone_type != ZONETYPE_ID) t.setId(name);
    t.have_zone = 1;
    t.zone_type = ZONETYPE_ID;
}

// the instant a wall-clock time (seconds as if the wall clock were utc) names
// in zone `id`, resolved as a time without a zone of its own is
pub fn utcOfWall(wall: i64, id: []const u8, db: TzDb) i64 {
    var t = Time{};
    t.sse = wall;
    t.dst = 0;
    adjustTimezone(&t, id, db);
    return t.sse;
}

// timelib_update_ts: apply the relative part and the zone, leaving the
// instant in t.sse. tzi is the zone for a time that names none
pub fn updateTs(t: *Time, tzi: ?[]const u8, db: TzDb) void {
    adjustSpecialEarly(t);
    adjustRelative(t);
    adjustSpecial(t);
    const days = epochDaysFromTime(t);
    t.sse = t.h *% 3600 +% t.i *% 60 +% t.s;
    t.sse +%= days *% 43200;
    t.sse +%= days *% 43200;
    adjustTimezone(t, tzi, db);
    t.have_relative = false;
    t.relative.have_weekday_relative = false;
    t.relative.have_special_relative = false;
    t.relative.first_last_day_of = 0;
}

// the moment a parsed time is resolved against
// timelib_update_from_sse: the wall-clock fields of t.sse in t's zone
pub fn updateFromSse(t: *Time, db: TzDb) void {
    const sse = t.sse;
    const z = t.z;
    const dst = t.dst;
    switch (t.zone_type) {
        ZONETYPE_ABBR, ZONETYPE_OFFSET => fieldsFromSse(t, sse +% t.z +% t.dst *% 3600),
        ZONETYPE_ID => fieldsFromSse(t, sse +% (if (t.id()) |id_| info(db, id_, sse).offset else 0)),
        else => fieldsFromSse(t, sse),
    }
    t.sse = sse;
    t.is_localtime = true;
    t.have_zone = 1;
    t.z = z;
    t.dst = dst;
}

fn hmsToSeconds(h: i64, i: i64, s: i64) i64 {
    return h *% 3600 +% i *% 60 +% s;
}

// the y/m/d/h/i/s/us of an interval as a relative time, with the sign applied
fn plainRelative(rel: *const Rel, bias: i64) Rel {
    return .{ .y = rel.y *% bias, .m = rel.m *% bias, .d = rel.d *% bias, .h = rel.h *% bias, .i = rel.i *% bias, .s = rel.s *% bias, .us = rel.us *% bias };
}

// timelib_add: the interval as a relative time on the wall clock. a weekday
// or special interval (from a date string) applies whole and ignores invert
pub fn add(t: *Time, rel: *const Rel, invert: bool, db: TzDb) void {
    t.relative = if (rel.have_weekday_relative or rel.have_special_relative) rel.* else plainRelative(rel, if (invert) -1 else 1);
    t.have_relative = true;
    updateTs(t, null, db);
    updateFromSse(t, db);
    t.have_relative = false;
}

// timelib_sub; the caller refuses weekday and special intervals first
pub fn sub(t: *Time, rel: *const Rel, invert: bool, db: TzDb) void {
    t.relative = plainRelative(rel, if (invert) 1 else -1);
    t.have_relative = true;
    updateTs(t, null, db);
    updateFromSse(t, db);
    t.have_relative = false;
}

// timelib_add_wall and timelib_sub_wall (sign -1): years, months, and days on
// the wall clock, then hours, minutes, and seconds as elapsed time
pub fn addWall(t: *Time, rel: *const Rel, invert: bool, sign: i64, db: TzDb) void {
    t.have_relative = true;
    if (rel.have_weekday_relative or rel.have_special_relative) {
        t.relative = rel.*;
        updateTs(t, null, db);
        updateFromSse(t, db);
    } else {
        const bias: i64 = if (invert) -1 else 1;
        t.relative = .{ .y = sign *% rel.y *% bias, .m = sign *% rel.m *% bias, .d = sign *% rel.d *% bias };
        if (t.relative.y != 0 or t.relative.m != 0 or t.relative.d != 0) updateTs(t, null, db);
        if (rel.us == 0) {
            t.sse +%= sign *% bias *% hmsToSeconds(rel.h, rel.i, rel.s);
            updateFromSse(t, db);
        } else {
            var us = rel.us;
            var secs = rel.s;
            rangeLimit(0, 1000000, 1000000, &us, &secs);
            t.sse +%= sign *% bias *% hmsToSeconds(rel.h, rel.i, secs);
            updateFromSse(t, db);
            t.us +%= sign *% us *% bias;
            doNormalize(t);
            updateTs(t, null, db);
        }
        doNormalize(t);
    }
    t.have_relative = false;
}

// date_period_advance: the whole interval as the relative part, invert unused
pub fn periodAdvance(t: *Time, rel: *const Rel, db: TzDb) void {
    t.have_relative = true;
    t.relative = rel.*;
    updateTs(t, null, db);
    updateFromSse(t, db);
}

pub const Now = struct {
    y: i64,
    m: i64,
    d: i64,
    h: i64,
    i: i64,
    s: i64,
    us: i64,
    z: i64,
    dst: i64,
    zone_type: u8,
    // the zone id for ZONETYPE_ID, the abbreviation for ZONETYPE_ABBR
    name: []const u8,
};

// timelib_fill_holes: unset fields come from now; a date without a time means
// midnight unless override_time (createFromFormat) asks otherwise
pub fn fillHoles(t: *Time, now: *const Now, override_time: bool) void {
    if (!override_time and t.have_date != 0 and t.have_time == 0) {
        t.h = 0;
        t.i = 0;
        t.s = 0;
        t.us = 0;
    }
    if (t.y != UNSET or t.m != UNSET or t.d != UNSET or t.h != UNSET or t.i != UNSET or t.s != UNSET) {
        if (t.us == UNSET) t.us = 0;
    } else {
        if (t.us == UNSET) t.us = if (now.us != UNSET) now.us else 0;
    }
    if (t.y == UNSET) t.y = if (now.y != UNSET) now.y else 0;
    if (t.m == UNSET) t.m = if (now.m != UNSET) now.m else 0;
    if (t.d == UNSET) t.d = if (now.d != UNSET) now.d else 0;
    if (t.h == UNSET) t.h = if (now.h != UNSET) now.h else 0;
    if (t.i == UNSET) t.i = if (now.i != UNSET) now.i else 0;
    if (t.s == UNSET) t.s = if (now.s != UNSET) now.s else 0;
    if (!t.has_id) {
        if (now.zone_type == ZONETYPE_ID) t.setId(now.name);
        if (t.z == UNSET) t.z = if (now.z != UNSET) now.z else 0;
        if (t.dst == UNSET) t.dst = if (now.dst != UNSET) now.dst else 0;
        if (!t.has_abbr and now.zone_type == ZONETYPE_ABBR) t.setAbbr(now.name);
    }
    if (t.zone_type == ZONETYPE_NONE and now.zone_type != ZONETYPE_NONE) {
        t.zone_type = now.zone_type;
        t.is_localtime = true;
    }
}

fn testLookupId(name: []const u8, out: *[64]u8) ?[]const u8 {
    const known = [_][]const u8{ "UTC", "Europe/Paris", "America/New_York" };
    for (known) |k| {
        if (std.ascii.eqlIgnoreCase(k, name)) {
            @memcpy(out[0..k.len], k);
            return out[0..k.len];
        }
    }
    return null;
}

fn testOffsetInfo(_: []const u8, _: i64) ?OffsetInfo {
    return .{ .offset = 0, .transition_time = std.math.minInt(i64), .is_dst = false };
}

test "scanner fields" {
    const db = TzDb{ .lookupId = testLookupId, .offsetInfo = testOffsetInfo };
    const a = std.testing.allocator;
    var p = try parse(a, "2024-02-30 10:20:30.5 Europe/Paris", db);
    defer p.deinit(a);
    try std.testing.expectEqual(@as(i64, 2024), p.time.y);
    try std.testing.expectEqual(@as(i64, 2), p.time.m);
    try std.testing.expectEqual(@as(i64, 30), p.time.d);
    try std.testing.expectEqual(@as(i64, 10), p.time.h);
    try std.testing.expectEqual(@as(i64, 500000), p.time.us);
    try std.testing.expectEqual(ZONETYPE_ID, p.time.zone_type);
    try std.testing.expectEqualStrings("Europe/Paris", p.time.id().?);
    try std.testing.expectEqual(@as(usize, 1), p.warnings.items.len);
    try std.testing.expectEqual(@as(usize, 35), p.warnings.items[0].pos);

    var q = try parse(a, "2024", db);
    defer q.deinit(a);
    try std.testing.expectEqual(@as(i64, 20), q.time.h);
    try std.testing.expectEqual(@as(i64, 24), q.time.i);

    var r = try parse(a, "next monday +2 days 3 hours ago", db);
    defer r.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), r.errors.items.len);
    try std.testing.expectEqual(@as(i64, -2), r.time.relative.d);
    try std.testing.expectEqual(@as(i64, -1), r.time.relative.weekday);

    var e = try parse(a, "foo bar", db);
    defer e.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), e.errors.items.len);
    try std.testing.expectEqual(@as(usize, 1), e.warnings.items.len);
    try std.testing.expectEqual(@as(usize, 4), e.warnings.items[0].pos);
}

test "dfa and nfa agree on the longest match" {
    const inputs = [_][]const u8{
        "next monday +2 days 3 hours ago", "2024-03-15T10:11:12.5+01:00", "10/Oct/2000:13:55:36 -0700", "first day of next month",
        "last sat of July 2008",           "@1700000000.25",              "Feb 3 2024 10:30pm",         "2024W11-3",
        "back of 7pm",                     "+1 week 2 days",              "Europe/Paris",               "(UTC)",
        "12.03.24",                        "tomorrow noon",               "20240315T101112",            "3 weekdays ago",
        "\xc2\xa0mon",
    };
    const m = getMachine();
    dfa_mutex.lock();
    defer dfa_mutex.unlock();
    if (!dfa_ready) try initDfa(m);
    for (inputs) |in| {
        const buf = try std.testing.allocator.alloc(u8, in.len + 16);
        defer std.testing.allocator.free(buf);
        @memcpy(buf[0..in.len], in);
        @memset(buf[in.len..], 0);
        var pos: usize = 0;
        while (pos <= in.len) {
            const a = try dfaMatch(m, buf, pos);
            const b = try nfaMatch(m, buf, pos);
            try std.testing.expectEqual(b.len, a.len);
            try std.testing.expectEqual(b.rule, a.rule);
            pos += a.len;
        }
    }
}

// ---- the difference between two times (interval.c) ----

pub const Interval = struct {
    y: i64 = 0,
    m: i64 = 0,
    d: i64 = 0,
    h: i64 = 0,
    i: i64 = 0,
    s: i64 = 0,
    us: i64 = 0,
    days: i64 = 0,
    invert: bool = false,
};

fn sameTimezone(one: *const Time, two: *const Time) bool {
    if (one.zone_type != two.zone_type) return false;
    if (one.zone_type == ZONETYPE_ABBR or one.zone_type == ZONETYPE_OFFSET) return one.z + one.dst * 3600 == two.z + two.dst * 3600;
    if (one.zone_type == ZONETYPE_ID) return std.mem.eql(u8, one.id() orelse "", two.id() orelse "");
    return false;
}

fn timeCompare(a: *const Time, b: *const Time) i32 {
    if (a.sse == b.sse) {
        if (a.us == b.us) return 0;
        return if (a.us < b.us) -1 else 1;
    }
    return if (a.sse < b.sse) -1 else 1;
}

fn decimalHour(h: i64, i: i64, s: i64, us: i64) f64 {
    const fh: f64 = @floatFromInt(h);
    const fi: f64 = @as(f64, @floatFromInt(i)) / 60.0;
    const fs: f64 = @as(f64, @floatFromInt(s)) / 3600.0;
    const fus: f64 = @as(f64, @floatFromInt(us)) / 3600000000.0;
    return if (h >= 0) (fh + fi + fs) + fus else (fh - fi - fs) - fus;
}

fn diffDays(one: *const Time, two: *const Time) i64 {
    if (sameTimezone(one, two)) {
        const one_first = timeCompare(one, two) < 0;
        const earliest = if (one_first) one else two;
        const latest = if (one_first) two else one;
        const earliest_time = decimalHour(earliest.h, earliest.i, earliest.s, earliest.us);
        const latest_time = decimalHour(latest.h, latest.i, latest.s, latest.us);
        var days: i64 = @bitCast(@abs(epochDaysFromTime(one) -% epochDaysFromTime(two)));
        if (latest_time < earliest_time and days > 0) days -= 1;
        return days;
    }
    const delta: f64 = @floatFromInt(one.sse -% two.sse);
    return toInt(@abs(delta / 86400.0));
}

fn rangeLimitDaysRelative(base_y: *i64, base_m: *i64, m: *i64, d: *i64, invert: bool) void {
    rangeLimit(1, 13, 12, base_m, base_y);
    var year = base_y.*;
    var month = base_m.*;
    if (!invert) {
        while (d.* < 0) {
            month -= 1;
            if (month < 1) {
                month += 12;
                year -= 1;
            }
            d.* += if (isLeap(year)) dim_leap[monthIndex(month)] else dim_common[monthIndex(month)];
            m.* -= 1;
        }
    } else {
        while (d.* < 0) {
            d.* += if (isLeap(year)) dim_leap[monthIndex(month)] else dim_common[monthIndex(month)];
            m.* -= 1;
            month += 1;
            if (month > 12) {
                month -= 12;
                year += 1;
            }
        }
    }
}

fn relNormalize(base: *Time, rt: *Interval) void {
    rangeLimit(0, 1000000, 1000000, &rt.us, &rt.s);
    rangeLimit(0, 60, 60, &rt.s, &rt.i);
    rangeLimit(0, 60, 60, &rt.i, &rt.h);
    rangeLimit(0, 24, 24, &rt.h, &rt.d);
    rangeLimit(0, 12, 12, &rt.m, &rt.y);
    rangeLimitDaysRelative(&base.y, &base.m, &rt.m, &rt.d, rt.invert);
    rangeLimit(0, 12, 12, &rt.m, &rt.y);
}

fn fieldsAfter(a: *const Time, b: *const Time) bool {
    const fa = [_]i64{ a.y, a.m, a.d, a.h, a.i, a.s, a.us };
    const fb = [_]i64{ b.y, b.m, b.d, b.h, b.i, b.s, b.us };
    for (fa, fb) |x, y| {
        if (x != y) return x > y;
    }
    return false;
}

// timelib_diff: one and two carry their wall-clock fields, sse, z, dst, and
// zone as unixtime2local leaves them
pub fn diff(one_in: *const Time, two_in: *const Time, db: TzDb) Interval {
    var one = one_in.*;
    var two = two_in.*;
    var rt = Interval{};
    const same_id = one.zone_type == ZONETYPE_ID and two.zone_type == ZONETYPE_ID and std.mem.eql(u8, one.id() orelse "", two.id() orelse "");
    const swap = if (same_id) fieldsAfter(&one, &two) else (one.sse > two.sse or (one.sse == two.sse and one.us > two.us));
    if (swap) {
        std.mem.swap(Time, &one, &two);
        rt.invert = true;
    }
    if (!same_id) {
        rt.y = two.y -% one.y;
        rt.m = two.m -% one.m;
        rt.d = two.d -% one.d;
        rt.h = two.h -% one.h;
        if (one.zone_type != ZONETYPE_ID) rt.h += one.dst;
        if (two.zone_type != ZONETYPE_ID) rt.h -= two.dst;
        rt.i = two.i -% one.i;
        rt.s = two.s -% one.s -% two.z +% one.z;
        rt.us = two.us -% one.us;
        rt.days = diffDays(&one, &two);
        relNormalize(if (rt.invert) &one else &two, &rt);
        return rt;
    }
    var dst_corr = two.z - one.z;
    const dst_h_corr = @divTrunc(dst_corr, 3600);
    const dst_m_corr = @divTrunc(@rem(dst_corr, 3600), 60);
    rt.y = two.y -% one.y;
    rt.m = two.m -% one.m;
    rt.d = two.d -% one.d;
    rt.h = two.h -% one.h;
    rt.i = two.i -% one.i;
    rt.s = two.s -% one.s;
    rt.us = two.us -% one.us;
    rt.days = diffDays(&one, &two);
    // fall back: within the repeated hour the later wall time can be the
    // earlier instant
    if (two.sse < one.sse) {
        const flipped: i64 = @intCast(@abs((rt.i * 60) + rt.s - dst_corr));
        rt.h = @divTrunc(flipped, 3600);
        rt.i = @divTrunc(flipped - rt.h * 3600, 60);
        rt.s = @rem(flipped, 60);
        rt.invert = !rt.invert;
    }
    relNormalize(if (rt.invert) &one else &two, &rt);
    const zone = two.id() orelse "";
    if (one.dst == 1 and two.dst == 0) {
        if ((two.sse -% one.sse +% dst_corr) < 86400) {
            rt.h -= dst_h_corr;
            rt.i -= dst_m_corr;
        }
    } else if (one.dst == 0 and two.dst == 1) {
        if (db.offsetInfo(zone, two.sse)) |inf| {
            const tt = inf.transition_time;
            if (!((one.sse +% 86400 > tt) and (one.sse +% 86400 <= tt +% dst_corr)) and
                two.sse >= tt and
                @rem(two.sse -% one.sse +% dst_corr, 86400) > (two.sse -% tt))
            {
                rt.h -= dst_h_corr;
                rt.i -= dst_m_corr;
            }
        }
    } else if (two.sse -% one.sse >= 86400) {
        if (db.offsetInfo(zone, two.sse -% two.z)) |inf| {
            dst_corr = one.z - inf.offset;
            if (two.sse >= inf.transition_time -% dst_corr and two.sse < inf.transition_time) {
                rt.d -= 1;
                rt.h = 24;
            }
        }
    }
    return rt;
}
