// htmlspecialchars, htmlentities, html_entity_decode, htmlspecialchars_decode
// and get_html_translation_table, ported from php's ext/standard/html.c. the
// tables come from html_tables_generated.zig (scripts/gen-html-tables)
const std = @import("std");
const tables = @import("html_tables_generated.zig");
const Value = @import("../runtime/value.zig").Value;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const coerceToString = @import("strings.zig").coerceToString;
const phpTypeName = @import("types.zig").phpTypeName;
const formatFloat = @import("output.zig").formatFloat;
const RuntimeError = error{ RuntimeError, OutOfMemory };

const Charset = tables.Charset;
const CodePointEntity = tables.CodePointEntity;
const NamedEntity = tables.NamedEntity;

pub const entries = .{
    .{ "htmlspecialchars", native_htmlspecialchars },
    .{ "htmlspecialchars_decode", native_htmlspecialchars_decode },
    .{ "html_entity_decode", native_html_entity_decode },
    .{ "htmlentities", native_htmlentities },
    .{ "get_html_translation_table", native_get_html_translation_table },
};

const quote_single = 1;
const quote_double = 2;
const ignore_errors = 4;
const substitute_errors = 8;
const doc_type_mask = 16 | 32;
const doc_html401 = 0;
const doc_xml1 = 16;
const doc_xhtml = 32;
const doc_html5 = 16 | 32;
const substitute_disallowed = 128;
const default_flags = quote_single | quote_double | substitute_errors;
const e_notice = 8;
const e_deprecated = 8192;

fn unicodeCompat(charset: Charset) bool {
    return @backingInt(charset) <= @backingInt(Charset.iso_8859_1);
}

fn singleByte(charset: Charset) bool {
    return charset != .utf_8 and @backingInt(charset) < @backingInt(Charset.big5);
}

fn partialSupport(charset: Charset) bool {
    return @backingInt(charset) >= @backingInt(Charset.big5);
}

// the byte at i, or the terminating nul php's strings have past their end
fn at(s: []const u8, i: usize) u8 {
    return if (i < s.len) s[i] else 0;
}

fn utf8Lead(c: u8) bool {
    return c < 0x80 or (c >= 0xC2 and c <= 0xF4);
}

fn utf8Trail(c: u8) bool {
    return c >= 0x80 and c <= 0xBF;
}

fn gb2312Lead(c: u8) bool {
    return c != 0x8E and c != 0x8F and c != 0xA0 and c != 0xFF;
}

fn gb2312Trail(c: u8) bool {
    return c >= 0xA1 and c <= 0xFE;
}

fn sjisLead(c: u8) bool {
    return c != 0x80 and c != 0xA0 and c < 0xFD;
}

fn sjisTrail(c: u8) bool {
    return c >= 0x40 and c != 0x7F and c < 0xFD;
}

// the next character of s at cursor (get_next_char). an ill-formed sequence
// returns null with the cursor moved past the bytes php counts as its part
fn nextChar(charset: Charset, s: []const u8, cursor: *usize) ?u32 {
    const pos = cursor.*;
    const avail = s.len - pos;
    const fail = struct {
        fn f(c: *usize, from: usize, advance: usize) ?u32 {
            c.* = from + advance;
            return null;
        }
    }.f;
    if (avail < 1) return fail(cursor, pos, 1);
    const c = s[pos];
    switch (charset) {
        .utf_8 => {
            if (c < 0x80) {
                cursor.* = pos + 1;
                return c;
            }
            if (c < 0xC2) return fail(cursor, pos, 1);
            if (c < 0xE0) {
                if (avail < 2) return fail(cursor, pos, 1);
                if (!utf8Trail(s[pos + 1])) return fail(cursor, pos, if (utf8Lead(s[pos + 1])) 1 else 2);
                const cp = (@as(u32, c & 0x1F) << 6) | (s[pos + 1] & 0x3F);
                if (cp < 0x80) return fail(cursor, pos, 2);
                cursor.* = pos + 2;
                return cp;
            }
            if (c < 0xF0) {
                if (avail < 3 or !utf8Trail(s[pos + 1]) or !utf8Trail(s[pos + 2])) {
                    if (avail < 2 or utf8Lead(s[pos + 1])) return fail(cursor, pos, 1);
                    if (avail < 3 or utf8Lead(s[pos + 2])) return fail(cursor, pos, 2);
                    return fail(cursor, pos, 3);
                }
                const cp = (@as(u32, c & 0x0F) << 12) | (@as(u32, s[pos + 1] & 0x3F) << 6) | (s[pos + 2] & 0x3F);
                if (cp < 0x800 or (cp >= 0xD800 and cp <= 0xDFFF)) return fail(cursor, pos, 3);
                cursor.* = pos + 3;
                return cp;
            }
            if (c < 0xF5) {
                if (avail < 4 or !utf8Trail(s[pos + 1]) or !utf8Trail(s[pos + 2]) or !utf8Trail(s[pos + 3])) {
                    if (avail < 2 or utf8Lead(s[pos + 1])) return fail(cursor, pos, 1);
                    if (avail < 3 or utf8Lead(s[pos + 2])) return fail(cursor, pos, 2);
                    if (avail < 4 or utf8Lead(s[pos + 3])) return fail(cursor, pos, 3);
                    return fail(cursor, pos, 4);
                }
                const cp = (@as(u32, c & 0x07) << 18) | (@as(u32, s[pos + 1] & 0x3F) << 12) | (@as(u32, s[pos + 2] & 0x3F) << 6) | (s[pos + 3] & 0x3F);
                if (cp < 0x10000 or cp > 0x10FFFF) return fail(cursor, pos, 4);
                cursor.* = pos + 4;
                return cp;
            }
            return fail(cursor, pos, 1);
        },
        .big5, .big5hkscs => {
            if (c >= 0x81 and c <= 0xFE) {
                if (avail < 2) return fail(cursor, pos, 1);
                const next = s[pos + 1];
                if ((next >= 0x40 and next <= 0x7E) or (next >= 0xA1 and next <= 0xFE)) {
                    cursor.* = pos + 2;
                    return (@as(u32, c) << 8) | next;
                }
                if (charset == .big5hkscs and (next == 0x80 or next == 0xFF)) return fail(cursor, pos, 2);
                return fail(cursor, pos, 1);
            }
            cursor.* = pos + 1;
            return c;
        },
        .gb2312 => {
            if (c >= 0xA1 and c <= 0xFE) {
                if (avail < 2) return fail(cursor, pos, 1);
                const next = s[pos + 1];
                if (gb2312Trail(next)) {
                    cursor.* = pos + 2;
                    return (@as(u32, c) << 8) | next;
                }
                return fail(cursor, pos, if (gb2312Lead(next)) 1 else 2);
            }
            if (gb2312Lead(c)) {
                cursor.* = pos + 1;
                return c;
            }
            return fail(cursor, pos, 1);
        },
        .sjis => {
            if ((c >= 0x81 and c <= 0x9F) or (c >= 0xE0 and c <= 0xFC)) {
                if (avail < 2) return fail(cursor, pos, 1);
                const next = s[pos + 1];
                if (sjisTrail(next)) {
                    cursor.* = pos + 2;
                    return (@as(u32, c) << 8) | next;
                }
                return fail(cursor, pos, if (sjisLead(next)) 1 else 2);
            }
            if (c < 0x80 or (c >= 0xA1 and c <= 0xDF)) {
                cursor.* = pos + 1;
                return c;
            }
            return fail(cursor, pos, 1);
        },
        .eucjp => {
            if ((c >= 0xA1 and c <= 0xFE) or c == 0x8E) {
                if (avail < 2) return fail(cursor, pos, 1);
                const next = s[pos + 1];
                const high: u8 = if (c == 0x8E) 0xDF else 0xFE;
                if (next >= 0xA1 and next <= high) {
                    cursor.* = pos + 2;
                    return (@as(u32, c) << 8) | next;
                }
                return fail(cursor, pos, if (next != 0xA0 and next != 0xFF) 1 else 2);
            }
            if (c == 0x8F) {
                const kanji = struct {
                    fn f(b: u8) bool {
                        return b >= 0xA1 and b <= 0xFE;
                    }
                }.f;
                if (avail < 3 or !kanji(s[pos + 1]) or !kanji(s[pos + 2])) {
                    if (avail < 2 or (s[pos + 1] != 0xA0 and s[pos + 1] != 0xFF)) return fail(cursor, pos, 1);
                    if (avail < 3 or (s[pos + 2] != 0xA0 and s[pos + 2] != 0xFF)) return fail(cursor, pos, 2);
                    return fail(cursor, pos, 3);
                }
                cursor.* = pos + 3;
                return (@as(u32, c) << 16) | (@as(u32, s[pos + 1]) << 8) | s[pos + 2];
            }
            if (c != 0xA0 and c != 0xFF) {
                cursor.* = pos + 1;
                return c;
            }
            return fail(cursor, pos, 1);
        },
        else => {
            cursor.* = pos + 1;
            return c;
        },
    }
}

fn iniValue(ctx: *NativeContext, name: []const u8) ?[]const u8 {
    return ctx.vm.ini_settings.get(name) orelse @import("../ini_config.zig").get(name);
}

// the charset a function's encoding argument names, or internal_encoding and
// default_charset when it names none (determine_charset)
fn determineCharset(ctx: *NativeContext, func: []const u8, given: ?[]const u8, quiet: bool) RuntimeError!Charset {
    // php reads the name as a c string
    var hint: []const u8 = if (given) |g| g[0 .. std.mem.indexOfScalar(u8, g, 0) orelse g.len] else "";
    if (hint.len == 0) {
        const internal = iniValue(ctx, "internal_encoding") orelse "";
        const default = iniValue(ctx, "default_charset") orelse "UTF-8";
        hint = if (internal.len > 0) internal else default;
        hint = hint[0 .. std.mem.indexOfScalar(u8, hint, 0) orelse hint.len];
    }
    if (hint.len == 0) return .utf_8;
    for (tables.charset_names) |entry| {
        if (std.ascii.eqlIgnoreCase(hint, entry.name)) return entry.charset;
    }
    if (!quiet) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): Charset \"{s}\" is not supported, assuming UTF-8", .{ func, hint });
        defer ctx.allocator.free(msg);
        try ctx.vm.emitWarning(msg);
    }
    return .utf_8;
}

fn appendUtf8(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, k: u32) !void {
    if (k < 0x80) {
        try buf.append(allocator, @intCast(k));
    } else if (k < 0x800) {
        try buf.appendSlice(allocator, &.{ @intCast(0xC0 | (k >> 6)), @intCast(0x80 | (k & 0x3F)) });
    } else if (k < 0x10000) {
        try buf.appendSlice(allocator, &.{ @intCast(0xE0 | (k >> 12)), @intCast(0x80 | ((k >> 6) & 0x3F)), @intCast(0x80 | (k & 0x3F)) });
    } else {
        try buf.appendSlice(allocator, &.{ @truncate(0xF0 | (k >> 18)), @intCast(0x80 | ((k >> 12) & 0x3F)), @intCast(0x80 | ((k >> 6) & 0x3F)), @intCast(0x80 | (k & 0x3F)) });
    }
}

// code is not necessarily a unicode code point (write_octet_sequence)
fn writeOctets(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, charset: Charset, code: u32) !void {
    if (charset == .utf_8) return appendUtf8(buf, allocator, code);
    try buf.append(allocator, @truncate(code));
}

fn unimapSearch(table: []const tables.FromUnicode, code: u32) ?u32 {
    // the maps have nothing outside the bmp
    if (code > 0xFFFF) return null;
    var lo: usize = 0;
    var hi: usize = table.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const key = table[mid].code_point;
        if (code < key) hi = mid else if (code > key) lo = mid + 1 else return if (table[mid].byte == 0) null else table[mid].byte;
    }
    return null;
}

// a unicode code point as the charset's own code (map_from_unicode)
fn mapFromUnicode(code: u32, charset: Charset) ?u32 {
    switch (charset) {
        .iso_8859_1 => return if (code > 0xFF) null else code,
        .iso_8859_5 => {
            if (code <= 0xA0 or code == 0xAD) return code;
            if (code == 0x2116) return 0xF0;
            if (code == 0xA7) return 0xFD;
            if (code >= 0x0401 and code <= 0x045F) {
                if (code == 0x040D or code == 0x0450 or code == 0x045D) return null;
                return code - 0x360;
            }
            return null;
        },
        .iso_8859_15 => {
            if (code < 0xA4 or (code > 0xBE and code <= 0xFF)) return code;
            return unimapSearch(&tables.from_unicode_iso_8859_15, code);
        },
        .cp1252 => {
            if (code <= 0x7F or (code >= 0xA0 and code <= 0xFF)) return code;
            return unimapSearch(&tables.from_unicode_cp1252, code);
        },
        .macroman, .cp1251, .koi8r, .cp866 => {
            if (charset == .macroman and code == 0x7F) return null;
            if (code <= 0x7F) return code;
            const table: []const tables.FromUnicode = switch (charset) {
                .macroman => &tables.from_unicode_macroman,
                .cp1251 => &tables.from_unicode_cp1251,
                .koi8r => &tables.from_unicode_koi8r,
                else => &tables.from_unicode_cp866,
            };
            return unimapSearch(table, code);
        },
        // only the ascii range maps; 0x5C is the yen sign in japanese text
        .sjis, .eucjp => return if (code >= 0x20 and code <= 0x7D and code != 0x5C) code else null,
        .big5, .big5hkscs, .gb2312 => return if (code >= 0x20 and code <= 0x7D) code else null,
        .utf_8 => return null,
    }
}

fn unicodeCpIsAllowed(cp: u32, doctype: i32) bool {
    return switch (doctype) {
        doc_html401 => (cp >= 0x20 and cp <= 0x7E) or cp == 0x0A or cp == 0x09 or cp == 0x0D or
            (cp >= 0xA0 and cp <= 0xD7FF) or (cp >= 0xE000 and cp <= 0x10FFFF),
        doc_html5 => (cp >= 0x20 and cp <= 0x7E) or (cp >= 0x09 and cp <= 0x0D and cp != 0x0B) or
            (cp >= 0xA0 and cp <= 0xD7FF) or
            (cp >= 0xE000 and cp <= 0x10FFFF and (cp & 0xFFFF) < 0xFFFE and (cp < 0xFDD0 or cp > 0xFDEF)),
        doc_xhtml, doc_xml1 => (cp >= 0x20 and cp <= 0xD7FF) or cp == 0x0A or cp == 0x09 or cp == 0x0D or
            (cp >= 0xE000 and cp <= 0x10FFFF and cp != 0xFFFE and cp != 0xFFFF),
        else => true,
    };
}

fn numericEntityIsAllowed(cp: u32, doctype: i32) bool {
    return switch (doctype) {
        doc_html401 => cp <= 0x10FFFF,
        doc_html5 => (cp >= 0x20 and cp <= 0x7E) or (cp >= 0x09 and cp <= 0x0C and cp != 0x0B) or
            (cp >= 0xA0 and cp <= 0x10FFFF and (cp & 0xFFFF) < 0xFFFE and (cp < 0xFDD0 or cp > 0xFDEF)),
        doc_xhtml, doc_xml1 => unicodeCpIsAllowed(cp, doctype),
        else => true,
    };
}

fn digitValue(c: u8, hex: bool) ?u32 {
    if (c >= '0' and c <= '9') return c - '0';
    if (!hex) return null;
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    return null;
}

const NumericEntity = struct { code: u32, end: usize };

// the entity after "&#" at start, ending on the ';' at .end
// (process_numeric_entity). php parses the digits with strtol, so a hex
// entity may repeat its 0x prefix and a run of digits too large for a long
// still ends where the digits do
fn processNumericEntity(s: []const u8, start: usize) ?NumericEntity {
    var pos = start;
    const hex = at(s, pos) == 'x' or at(s, pos) == 'X';
    if (hex) pos += 1;
    if (digitValue(at(s, pos), hex) == null) return null;
    if (hex and at(s, pos) == '0' and (at(s, pos + 1) == 'x' or at(s, pos + 1) == 'X') and digitValue(at(s, pos + 2), true) != null) pos += 2;
    var value: u64 = 0;
    var overflow = false;
    while (digitValue(at(s, pos), hex)) |d| : (pos += 1) {
        if (value > 0x10FFFF) overflow = true else value = value * (if (hex) @as(u64, 16) else 10) + d;
    }
    if (at(s, pos) != ';') return null;
    if (overflow or value > 0x10FFFF) return null;
    return .{ .code = @intCast(value), .end = pos };
}

// the length of the alphanumeric name at start when a ';' ends it
// (process_named_entity_html)
fn processNamedEntity(s: []const u8, start: usize) ?usize {
    var pos = start;
    while (std.ascii.isAlphanumeric(at(s, pos))) pos += 1;
    if (at(s, pos) != ';') return null;
    if (pos == start) return null;
    return pos - start;
}

fn resolveNamedEntity(name: []const u8, map: []const NamedEntity) ?NamedEntity {
    var lo: usize = 0;
    var hi: usize = map.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        switch (std.mem.order(u8, name, map[mid].name)) {
            .lt => hi = mid,
            .gt => lo = mid + 1,
            .eq => return map[mid],
        }
    }
    return null;
}

fn findCodePoint(table: []const CodePointEntity, cp: u32) ?*const CodePointEntity {
    var lo: usize = 0;
    var hi: usize = table.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const key = table[mid].code_point;
        if (cp < key) hi = mid else if (cp > key) lo = mid + 1 else return &table[mid];
    }
    return null;
}

// the decoding map (unescape_inverse_map)
fn inverseMap(all: bool, flags: i32) []const NamedEntity {
    const doctype = flags & doc_type_mask;
    if (all) return switch (doctype) {
        doc_html401, doc_xhtml => &tables.html4_by_name,
        doc_html5 => &tables.html5_by_name,
        else => &tables.be_apos_by_name,
    };
    return if (doctype == doc_html401) &tables.be_noapos_by_name else &tables.be_apos_by_name;
}

// the encoding table (determine_entity_table)
fn entityTable(all: bool, doctype: i32) []const CodePointEntity {
    if (all) return if (doctype == doc_html5) &tables.html5_by_code_point else &tables.html4_by_code_point;
    return if (doctype == doc_html401) &tables.basic_noapos_by_code_point else &tables.basic_apos_by_code_point;
}

fn isApos(name: []const u8) bool {
    return std.mem.eql(u8, name, "apos");
}

// the entity for k (find_entity_for_char). an entity for k followed by the
// next character moves the cursor past that character
fn findEntityForChar(k: u32, charset: Charset, table: []const CodePointEntity, old: []const u8, cursor: *usize) ?[]const u8 {
    if (((k & 0xFFF000) >> 12) > 0x1D) return null;
    const row = findCodePoint(table, k) orelse return null;
    if (!row.ambiguous) return row.entity;
    const before = cursor.*;
    if (cursor.* < old.len) {
        if (nextChar(charset, old, cursor)) |next| {
            for (row.seconds) |second| {
                if (second.code_point == next) return second.entity;
            }
        }
    }
    cursor.* = before;
    return row.entity;
}

fn findEntityForCharBasic(k: u32, table: []const CodePointEntity) ?[]const u8 {
    if (k >= 64) return null;
    const row = findCodePoint(table, k) orelse return null;
    return row.entity;
}

// php_escape_html_entities_ex; null where php returns an empty string for
// ill-formed input
fn escapeHtmlEntities(ctx: *NativeContext, func: []const u8, old: []const u8, all_requested: bool, flags: i32, hint: ?[]const u8, double_encode: bool, out: *std.ArrayListUnmanaged(u8)) RuntimeError!bool {
    const allocator = ctx.allocator;
    const charset = try determineCharset(ctx, func, hint, false);
    const doctype = flags & doc_type_mask;
    var all = all_requested;
    if (all) {
        if (partialSupport(charset)) {
            const msg = try std.fmt.allocPrint(allocator, "{s}(): Only basic entities substitution is supported for multi-byte encodings other than UTF-8; functionality is equivalent to htmlspecialchars", .{func});
            defer allocator.free(msg);
            try ctx.vm.raiseError(e_notice, msg);
        }
        all = !partialSupport(charset) and doctype != doc_xml1;
    }
    const table = entityTable(all, doctype);
    const to_uni: ?*const [256]u16 = if (all and !unicodeCompat(charset)) tables.toUnicode(charset) else null;
    const inv_map = if (!double_encode) inverseMap(true, flags) else &.{};
    const replacement: []const u8 = if (charset == .utf_8) "\xEF\xBF\xBD" else "&#xFFFD;";

    try out.ensureTotalCapacity(allocator, if (old.len < 64) 128 else old.len * 2);
    // htmlspecialchars on utf-8 (templates' hot path) copies runs of plain
    // ascii in one go; only the five special characters and multibyte
    // sequences need the full path
    const ascii_runs = !all and charset == .utf_8 and (flags & substitute_disallowed) == 0;
    var cursor: usize = 0;
    while (cursor < old.len) {
        if (ascii_runs) {
            var end = cursor;
            while (end < old.len) : (end += 1) {
                const c = old[end];
                if (c >= 0x80 or c == '&' or c == '<' or c == '>' or c == '"' or c == '\'') break;
            }
            if (end > cursor) {
                try out.appendSlice(allocator, old[cursor..end]);
                cursor = end;
                continue;
            }
        }
        const before = cursor;
        const decoded = nextChar(charset, old, &cursor);
        var this_char = decoded orelse {
            if ((flags & ignore_errors) != 0) continue;
            if ((flags & substitute_errors) != 0) {
                try out.appendSlice(allocator, replacement);
                continue;
            }
            return false;
        };
        var sequence = old[before..cursor];

        if (this_char != '&') {
            if ((this_char == '\'' and (flags & quote_single) == 0) or (this_char == '"' and (flags & quote_double) == 0)) {
                try out.appendSlice(allocator, sequence);
                continue;
            }
            var rep: ?[]const u8 = null;
            if (all) {
                if (to_uni) |map| {
                    this_char = map[this_char];
                    if (this_char == 0xFFFF) {
                        try out.appendSlice(allocator, sequence);
                        continue;
                    }
                }
                rep = findEntityForChar(this_char, charset, table, old, &cursor);
            } else {
                rep = findEntityForCharBasic(this_char, table);
            }
            if (rep) |entity| {
                try out.append(allocator, '&');
                try out.appendSlice(allocator, entity);
                try out.append(allocator, ';');
                continue;
            }
            if ((flags & substitute_disallowed) != 0) {
                if (unicodeCompat(charset)) {
                    if (!unicodeCpIsAllowed(this_char, doctype)) sequence = replacement;
                } else if (to_uni) |map| {
                    if (!all) this_char = map[this_char];
                    if (!unicodeCpIsAllowed(this_char, doctype)) sequence = replacement;
                } else {
                    // without a table only the ascii range is known; assume
                    // the charset maps 0x00-0x1F to the c0 controls
                    if (this_char <= 0x7D and !unicodeCpIsAllowed(this_char, doctype)) sequence = replacement;
                }
            }
            try out.appendSlice(allocator, sequence);
            continue;
        }

        if (double_encode) {
            try out.appendSlice(allocator, "&amp;");
            continue;
        }
        // keep an entity that is already valid
        var ent_len: usize = undefined;
        if (at(old, cursor) == '#') {
            const numeric = processNumericEntity(old, cursor + 1) orelse {
                try out.appendSlice(allocator, "&amp;");
                continue;
            };
            if ((flags & substitute_disallowed) != 0 and !numericEntityIsAllowed(numeric.code, doctype)) {
                try out.appendSlice(allocator, "&amp;");
                continue;
            }
            ent_len = numeric.end - cursor;
        } else {
            const len = processNamedEntity(old, cursor) orelse {
                try out.appendSlice(allocator, "&amp;");
                continue;
            };
            const name = old[cursor .. cursor + len];
            // xhtml decodes with the html 4.01 map, which lacks &apos;
            if (resolveNamedEntity(name, inv_map) == null and !(doctype == doc_xhtml and isApos(name))) {
                try out.appendSlice(allocator, "&amp;");
                continue;
            }
            ent_len = len;
        }
        try out.append(allocator, '&');
        try out.appendSlice(allocator, old[cursor .. cursor + ent_len]);
        try out.append(allocator, ';');
        cursor += ent_len + 1;
    }
    return true;
}

// traverse_for_entities
fn traverseForEntities(allocator: std.mem.Allocator, input: []const u8, all: bool, flags: i32, inv_map: []const NamedEntity, charset: Charset, out: *std.ArrayListUnmanaged(u8)) !void {
    const doctype = flags & doc_type_mask;
    try out.ensureTotalCapacity(allocator, input.len);
    var current: usize = 0;
    while (current < input.len) {
        const amp = std.mem.indexOfScalarPos(u8, input, current, '&') orelse {
            try out.appendSlice(allocator, input[current..]);
            break;
        };
        try out.appendSlice(allocator, input[current..amp]);
        current = amp;
        if (input.len - current < 4) {
            try out.appendSlice(allocator, input[current..]);
            break;
        }

        var code: u32 = 0;
        var code2: u32 = 0;
        var entity_end: usize = undefined;
        const complete = parse: {
            if (input[current + 1] == '#') {
                const numeric = processNumericEntity(input, current + 2) orelse break :parse false;
                code = numeric.code;
                entity_end = numeric.end;
                // htmlspecialchars_decode only decodes &, <, >, " and '
                if (!all and (code > 63 or findEntityForCharBasic(code, &tables.basic_apos_by_code_point) == null)) break :parse false;
                // html 5 allows a literal U+000D but not as a numeric entity
                if (!unicodeCpIsAllowed(code, doctype) or (doctype == doc_html5 and code == 0x0D)) break :parse false;
            } else {
                const name_start = current + 1;
                const max_search = @min(tables.longest_entity_length + 1, input.len - name_start);
                const semicolon = std.mem.indexOfScalar(u8, input[name_start .. name_start + max_search], ';') orelse break :parse false;
                if (semicolon == 0) break :parse false;
                const name = input[name_start .. name_start + semicolon];
                if (resolveNamedEntity(name, inv_map)) |found| {
                    code = found.code_point;
                    code2 = found.second;
                } else if (doctype == doc_xhtml and isApos(name)) {
                    code = '\'';
                } else break :parse false;
                entity_end = name_start + semicolon;
            }
            break :parse true;
        };
        if (!complete) {
            try out.append(allocator, '&');
            current += 1;
            continue;
        }

        var decodable = !((code == '\'' and (flags & quote_single) == 0) or (code == '"' and (flags & quote_double) == 0));
        if (decodable and charset != .utf_8) {
            if (mapFromUnicode(code, charset)) |mapped| {
                code = mapped;
                if (code2 != 0) decodable = false;
            } else decodable = false;
        }
        if (!decodable) {
            try out.appendSlice(allocator, input[current..entity_end]);
            current = entity_end;
            continue;
        }
        try writeOctets(out, allocator, charset, code);
        if (code2 != 0) try writeOctets(out, allocator, charset, code2);
        current = entity_end + 1;
    }
}

// php's parameter parsing for the arguments of these functions, which
// coerces scalars and rejects what a weak-mode call can't convert
const Params = struct {
    ctx: *NativeContext,
    func: []const u8,
    args: []const Value,

    fn typeError(self: Params, index: usize, name: []const u8, expected: []const u8) RuntimeError {
        const msg = try std.fmt.allocPrint(self.ctx.allocator, "{s}(): Argument #{d} (${s}) must be of type {s}, {s} given", .{ self.func, index + 1, name, expected, phpTypeName(self.args[index]) });
        defer self.ctx.allocator.free(msg);
        try self.ctx.vm.setPendingException("TypeError", msg);
        return error.RuntimeError;
    }

    fn nullDeprecated(self: Params, index: usize, name: []const u8, expected: []const u8) RuntimeError!void {
        const msg = try std.fmt.allocPrint(self.ctx.allocator, "{s}(): Passing null to parameter #{d} (${s}) of type {s} is deprecated", .{ self.func, index + 1, name, expected });
        defer self.ctx.allocator.free(msg);
        try self.ctx.vm.raiseError(e_deprecated, msg);
    }

    fn string(self: Params, index: usize, name: []const u8, default: []const u8) RuntimeError![]const u8 {
        if (index >= self.args.len) return default;
        return switch (self.args[index]) {
            .null, .undef => {
                try self.nullDeprecated(index, name, "string");
                return "";
            },
            .array => self.typeError(index, name, "string"),
            .object => |o| if (self.ctx.vm.hasMethod(o.class_name, "__toString")) coerceToString(self.ctx, self.args[index]) else self.typeError(index, name, "string"),
            else => coerceToString(self.ctx, self.args[index]),
        };
    }

    fn optionalString(self: Params, index: usize, name: []const u8) RuntimeError!?[]const u8 {
        if (index >= self.args.len) return null;
        return switch (self.args[index]) {
            .null, .undef => null,
            .array => self.typeError(index, name, "?string"),
            .object => |o| if (self.ctx.vm.hasMethod(o.class_name, "__toString")) try coerceToString(self.ctx, self.args[index]) else self.typeError(index, name, "?string"),
            else => try coerceToString(self.ctx, self.args[index]),
        };
    }

    fn float(self: Params, index: usize, name: []const u8, f: f64, from_string: bool) RuntimeError!i64 {
        if (!Value.floatFitsInt(f)) return self.typeError(index, name, "int");
        if (f != @trunc(f)) {
            var tmp: [64]u8 = undefined;
            const shown = formatFloat(&tmp, f);
            const msg = if (from_string)
                try std.fmt.allocPrint(self.ctx.allocator, "Implicit conversion from float-string \"{s}\" to int loses precision", .{self.args[index].string.bytes()})
            else
                try std.fmt.allocPrint(self.ctx.allocator, "Implicit conversion from float {s} to int loses precision", .{shown});
            defer self.ctx.allocator.free(msg);
            try self.ctx.vm.raiseError(e_deprecated, msg);
        }
        return @intFromFloat(@trunc(f));
    }

    fn int(self: Params, index: usize, name: []const u8, default: i64) RuntimeError!i64 {
        if (index >= self.args.len) return default;
        const v = self.args[index];
        switch (v) {
            .int => |i| return i,
            .bool => |b| return @intFromBool(b),
            .null, .undef => {
                try self.nullDeprecated(index, name, "int");
                return 0;
            },
            .float => |f| return self.float(index, name, f, false),
            .string => |str| {
                const bytes = str.bytes();
                if (!Value.isNumericString(bytes)) return self.typeError(index, name, "int");
                const trimmed = std.mem.trim(u8, bytes, " \t\n\r\x0b\x0c");
                if (std.fmt.parseInt(i64, trimmed, 10)) |i| return i else |_| {}
                return self.float(index, name, Value.toFloat(v), true);
            },
            else => return self.typeError(index, name, "int"),
        }
    }

    fn boolean(self: Params, index: usize, name: []const u8, default: bool) RuntimeError!bool {
        if (index >= self.args.len) return default;
        return switch (self.args[index]) {
            .null, .undef => {
                try self.nullDeprecated(index, name, "bool");
                return false;
            },
            .bool, .int, .float, .string => self.args[index].isTruthy(),
            else => self.typeError(index, name, "bool"),
        };
    }

    // php hands the flags to html.c as a c int
    fn flags(self: Params, index: usize) RuntimeError!i32 {
        return @truncate(try self.int(index, "flags", default_flags));
    }
};

fn htmlEntities(ctx: *NativeContext, func: []const u8, args: []const Value, all: bool) RuntimeError!NativeResult {
    const params = Params{ .ctx = ctx, .func = func, .args = args };
    const str = try params.string(0, "string", "");
    const flags = try params.flags(1);
    const hint = try params.optionalString(2, "encoding");
    const double_encode = try params.boolean(3, "double_encode", true);
    if (str.len == 0) return NativeResult.literal("");
    var out = std.ArrayListUnmanaged(u8).empty;
    defer out.deinit(ctx.allocator);
    if (!try escapeHtmlEntities(ctx, func, str, all, flags, hint, double_encode, &out)) return NativeResult.literal("");
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, try out.toOwnedSlice(ctx.allocator)));
}

fn native_htmlspecialchars(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return htmlEntities(ctx, "htmlspecialchars", args, false);
}

fn native_htmlentities(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return htmlEntities(ctx, "htmlentities", args, true);
}

// php_unescape_html_entities
fn unescapeHtmlEntities(ctx: *NativeContext, func: []const u8, args: []const Value, all: bool) RuntimeError!NativeResult {
    const params = Params{ .ctx = ctx, .func = func, .args = args };
    const str = try params.string(0, "string", "");
    const flags = try params.flags(1);
    const hint = if (all) try params.optionalString(2, "encoding") else null;
    if (std.mem.indexOfScalar(u8, str, '&') == null) {
        if (args.len > 0 and args[0] == .string) return NativeResult.shareString(args[0].string);
        return NativeResult.copyString(ctx.allocator, str);
    }
    // the charset does not matter for the basic entities
    const charset: Charset = if (all) try determineCharset(ctx, func, hint, false) else .iso_8859_1;
    var out = std.ArrayListUnmanaged(u8).empty;
    defer out.deinit(ctx.allocator);
    try traverseForEntities(ctx.allocator, str, all, flags, inverseMap(all, flags), charset, &out);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, try out.toOwnedSlice(ctx.allocator)));
}

fn native_htmlspecialchars_decode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return unescapeHtmlEntities(ctx, "htmlspecialchars_decode", args, false);
}

fn native_html_entity_decode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return unescapeHtmlEntities(ctx, "html_entity_decode", args, true);
}

// one row of a translation table, keyed by the character in the charset
// (write_s3row_data)
fn writeRow(ctx: *NativeContext, arr: anytype, row: *const CodePointEntity, orig_cp: u32, charset: Charset) RuntimeError!void {
    const allocator = ctx.allocator;
    var key = std.ArrayListUnmanaged(u8).empty;
    defer key.deinit(allocator);
    var entity = std.ArrayListUnmanaged(u8).empty;
    defer entity.deinit(allocator);
    try writeOctets(&key, allocator, charset, orig_cp);
    const first_len = key.items.len;
    if (row.entity) |name| try putEntity(ctx, arr, key.items, &entity, name);
    if (!row.ambiguous) return;
    for (row.seconds) |second| {
        const code = if (!unicodeCompat(charset)) mapFromUnicode(second.code_point, charset) orelse continue else second.code_point;
        key.shrinkRetainingCapacity(first_len);
        try writeOctets(&key, allocator, charset, code);
        try putEntity(ctx, arr, key.items, &entity, second.entity);
    }
}

fn putEntity(ctx: *NativeContext, arr: anytype, key: []const u8, entity: *std.ArrayListUnmanaged(u8), name: []const u8) RuntimeError!void {
    entity.clearRetainingCapacity();
    try entity.append(ctx.allocator, '&');
    try entity.appendSlice(ctx.allocator, name);
    try entity.append(ctx.allocator, ';');
    const owned_key = try Value.String.create(ctx.allocator, key);
    defer owned_key.release();
    try arr.setCopiedString(ctx.allocator, .{ .string = owned_key }, entity.items);
}

fn native_get_html_translation_table(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const params = Params{ .ctx = ctx, .func = "get_html_translation_table", .args = args };
    const all_arg = try params.int(0, "table", 0);
    const flags = try params.flags(1);
    const hint = try params.string(2, "encoding", "");
    const charset = try determineCharset(ctx, "get_html_translation_table", hint, false);
    const doctype = flags & doc_type_mask;
    const all = all_arg != 0 and !partialSupport(charset) and doctype != doc_xml1;

    const arr = try ctx.createArray();
    const table = entityTable(all, doctype);
    const skipQuote = struct {
        fn f(code: u32, f_flags: i32) bool {
            return (code == '\'' and (f_flags & quote_single) == 0) or (code == '"' and (f_flags & quote_double) == 0);
        }
    }.f;

    if (all and unicodeCompat(charset)) {
        // iso-8859-1 has the first 256 code points, utf-8 all of them
        const limit: u32 = if (singleByte(charset)) 0x100 else 0x1E000;
        for (table) |*row| {
            if (row.code_point >= limit) break;
            if (skipQuote(row.code_point, flags)) continue;
            try writeRow(ctx, arr, row, row.code_point, charset);
        }
    } else if (all) {
        const to_uni = tables.toUnicode(charset).?;
        var i: u32 = 0;
        while (i <= 0xFF) : (i += 1) {
            if (skipQuote(i, flags)) continue;
            const row = findCodePoint(table, to_uni[i]) orelse continue;
            try writeRow(ctx, arr, row, i, charset);
        }
    } else {
        for (table) |*row| {
            if (skipQuote(row.code_point, flags)) continue;
            try writeRow(ctx, arr, row, row.code_point, .iso_8859_1);
        }
    }
    return NativeResult.borrowed(.{ .array = arr });
}
