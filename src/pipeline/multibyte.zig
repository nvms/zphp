// zend.multibyte's script filter (zend_language_scanner.l with mbstring's
// encodings): a script's encoding is found from its byte order mark or its
// NUL bytes (zend.detect_unicode) or zend.script_encoding, and the script is
// converted to the internal encoding before it is lexed. only the unicode
// encodings and the single-byte ones the lexer reads as they are are
// converted; a script in another encoding is lexed as it is
const std = @import("std");
const mb_encodings = @import("../stdlib/mb_encodings_generated.zig");

pub const Encoding = enum {
    utf8,
    utf16be,
    utf16le,
    utf32be,
    utf32le,
    latin1,
    ascii,
    // an encoding zphp doesn't convert (SJIS, EUC-JP, ...)
    other,

    // zend_multibyte_check_lexer_compatibility: an ascii-compatible
    // encoding whose multibyte characters never contain ascii bytes
    fn lexerCompatible(self: Encoding) bool {
        return switch (self) {
            .utf8, .latin1, .ascii => true,
            else => false,
        };
    }
};

// set at startup from the ini, like CG(script_encoding_list) and
// CG(detect_unicode)
pub var script_encoding: ?Encoding = null;
pub var detect_unicode: bool = true;
pub var internal_encoding: Encoding = .utf8;

// a name in zend.script_encoding mbstring doesn't know, which php warns
// about at startup
pub var invalid_script_encoding: ?[]const u8 = null;

// the ini settings the filter reads: zend.script_encoding (a list, as
// php_mb_parse_encoding_list reads it; the first entry is used),
// zend.detect_unicode, and the internal encoding (internal_encoding, else
// default_charset)
pub fn configure(get: *const fn ([]const u8) ?[]const u8) void {
    if (get("zend.detect_unicode")) |v| detect_unicode = iniTrue(v);
    const internal = blk: {
        for ([_][]const u8{ "internal_encoding", "mbstring.internal_encoding", "default_charset" }) |name| {
            if (get(name)) |v| if (v.len > 0) break :blk v;
        }
        break :blk "UTF-8";
    };
    internal_encoding = classify(internal);
    script_encoding = null;
    invalid_script_encoding = null;
    const raw = get("zend.script_encoding") orelse return;
    var list = raw;
    if (list.len > 2 and list[0] == '"' and list[list.len - 1] == '"') list = list[1 .. list.len - 1];
    var names = std.mem.splitScalar(u8, list, ',');
    var first: ?Encoding = null;
    while (names.next()) |entry| {
        const name = std.mem.trim(u8, entry, " \t");
        if (name.len == 0 and list.len == 0) break;
        if (std.ascii.eqlIgnoreCase(name, "auto")) continue;
        if (!knownEncoding(name)) {
            invalid_script_encoding = name;
            return;
        }
        if (first == null) first = classify(name);
    }
    script_encoding = first;
}

fn iniTrue(v: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(v, "true") or std.ascii.eqlIgnoreCase(v, "yes") or std.ascii.eqlIgnoreCase(v, "on")) return true;
    return (std.fmt.parseInt(i64, std.mem.trim(u8, v, " "), 10) catch 0) != 0;
}

// mbstring's name lookup: the canonical names, mime names and aliases, in
// any case
pub fn knownEncoding(name: []const u8) bool {
    for (mb_encodings.encodings) |e| {
        if (std.ascii.eqlIgnoreCase(name, e.name) or (e.mime.len > 0 and std.ascii.eqlIgnoreCase(name, e.mime))) return true;
        for (e.aliases) |alias| if (std.ascii.eqlIgnoreCase(name, alias)) return true;
    }
    return false;
}

pub fn classify(name: []const u8) Encoding {
    const table = [_]struct { []const u8, Encoding }{
        .{ "UTF-8", .utf8 },        .{ "utf8", .utf8 },
        .{ "UTF-16BE", .utf16be },  .{ "UTF-16LE", .utf16le },
        .{ "UTF-16", .utf16be },    .{ "utf16", .utf16be },
        .{ "UTF-32BE", .utf32be },  .{ "UTF-32LE", .utf32le },
        .{ "UTF-32", .utf32be },    .{ "utf32", .utf32be },
        .{ "ISO-8859-1", .latin1 }, .{ "ISO8859-1", .latin1 },
        .{ "latin1", .latin1 },     .{ "ASCII", .ascii },
        .{ "US-ASCII", .ascii },
    };
    for (table) |t| if (std.ascii.eqlIgnoreCase(name, t[0])) return t[1];
    return .other;
}

const bom_utf32be = "\x00\x00\xfe\xff";
const bom_utf32le = "\xff\xfe\x00\x00";
const bom_utf16be = "\xfe\xff";
const bom_utf16le = "\xff\xfe";
const bom_utf8 = "\xef\xbb\xbf";

const Detected = struct { encoding: Encoding, bom: usize };

// zend_multibyte_detect_unicode
fn detectUnicode(script: []const u8) ?Detected {
    if (script.len < bom_utf32le.len) return null;
    const boms = [_]struct { []const u8, Encoding }{
        .{ bom_utf32be, .utf32be }, .{ bom_utf32le, .utf32le }, .{ bom_utf16be, .utf16be }, .{ bom_utf16le, .utf16le }, .{ bom_utf8, .utf8 },
    };
    for (boms) |b| if (std.mem.startsWith(u8, script, b[0])) return .{ .encoding = b[1], .bom = b[0].len };
    const nul = std.mem.indexOfScalar(u8, script, 0) orelse return null;
    if (haltCompilerBefore(script, nul)) return null;
    return .{ .encoding = detectUtfEncoding(script), .bom = 0 };
}

// a NUL byte after `__HALT_COMPILER();` is the script's data, not a wide
// character
fn haltCompilerBefore(script: []const u8, nul: usize) bool {
    var pos: usize = 0;
    while (nul - pos >= "__HALT_COMPILER();".len) {
        const underscore = std.mem.indexOfScalarPos(u8, script[0..nul], pos, '_') orelse return false;
        pos = underscore + 1;
        if (!std.ascii.startsWithIgnoreCase(script[pos..], "_HALT_COMPILER")) continue;
        var p = pos + "_HALT_COMPILER".len;
        p = skipSpace(script, p);
        if (p >= script.len or script[p] != '(') continue;
        p = skipSpace(script, p + 1);
        if (p >= script.len or script[p] != ')') continue;
        p = skipSpace(script, p + 1);
        if (p < script.len and script[p] == ';') return true;
    }
    return false;
}

fn skipSpace(script: []const u8, from: usize) usize {
    var p = from;
    while (p < script.len and (script[p] == ' ' or script[p] == '\t' or script[p] == '\r' or script[p] == '\n')) p += 1;
    return p;
}

// zend_multibyte_detect_utf_encoding
fn detectUtfEncoding(script: []const u8) Encoding {
    var wchar_size: usize = 2;
    var offset: usize = 0;
    while (offset < script.len and script.len - offset > 2) {
        const at = std.mem.indexOfScalar(u8, script[offset .. script.len - 2], 0) orelse break;
        const p = offset + at;
        if (script[p + 1] == 0 and script[p + 2] == 0) {
            wchar_size = 4;
            break;
        }
        offset = p + 4;
    }
    var le = false;
    offset = 0;
    while (script.len - offset >= wchar_size) {
        const first = script[offset];
        const last = script[offset + wchar_size - 1];
        if (first == 0 and last != 0) {
            le = false;
            break;
        } else if (first != 0 and last == 0) {
            le = true;
            break;
        }
        offset += wchar_size;
    }
    if (wchar_size == 2) return if (le) .utf16le else .utf16be;
    return if (le) .utf32le else .utf32be;
}

// the script as the lexer reads it, or null when it is read as it is.
// error.Unconvertible is php's "Could not convert the script" fatal
pub fn filterScript(allocator: std.mem.Allocator, source: []const u8) !?[]u8 {
    var script = source;
    var encoding: ?Encoding = null;
    if (detect_unicode) if (detectUnicode(script)) |d| {
        encoding = d.encoding;
        script = script[d.bom..];
    };
    if (encoding == null) encoding = script_encoding;
    const from = encoding orelse return null;
    // zend_multibyte_set_filter: the script is converted to the internal
    // encoding when the lexer can read that one
    if (from == internal_encoding or !internal_encoding.lexerCompatible()) {
        if (script.len == source.len) return null;
        return try allocator.dupe(u8, script);
    }
    if (from == .other) {
        if (script.len == source.len) return null;
        return try allocator.dupe(u8, script);
    }
    return try convert(allocator, script, from, internal_encoding);
}

// mbstring's conversion: an ill-formed sequence or a character the target
// lacks becomes '?'
fn convert(allocator: std.mem.Allocator, input: []const u8, from: Encoding, to: Encoding) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < input.len) {
        var cp: ?u21 = null;
        switch (from) {
            .utf8 => {
                const len = std.unicode.utf8ByteSequenceLength(input[i]) catch 1;
                if (i + len <= input.len) cp = std.unicode.utf8Decode(input[i .. i + len]) catch null;
                i += if (cp != null) len else 1;
            },
            .latin1 => {
                cp = input[i];
                i += 1;
            },
            .ascii => {
                if (input[i] < 0x80) cp = input[i];
                i += 1;
            },
            .utf16be, .utf16le => {
                if (i + 2 > input.len) {
                    i = input.len;
                } else {
                    const unit = readUnit16(input[i..], from == .utf16le);
                    i += 2;
                    if (unit >= 0xd800 and unit <= 0xdbff) {
                        if (i + 2 <= input.len) {
                            const low = readUnit16(input[i..], from == .utf16le);
                            if (low >= 0xdc00 and low <= 0xdfff) {
                                i += 2;
                                cp = @intCast(0x10000 + ((@as(u32, unit) - 0xd800) << 10) + (low - 0xdc00));
                            }
                        }
                    } else if (unit < 0xdc00 or unit > 0xdfff) cp = @intCast(unit);
                }
            },
            .utf32be, .utf32le => {
                if (i + 4 > input.len) {
                    i = input.len;
                } else {
                    const b = input[i .. i + 4];
                    const v: u32 = if (from == .utf32le)
                        @as(u32, b[0]) | (@as(u32, b[1]) << 8) | (@as(u32, b[2]) << 16) | (@as(u32, b[3]) << 24)
                    else
                        @as(u32, b[3]) | (@as(u32, b[2]) << 8) | (@as(u32, b[1]) << 16) | (@as(u32, b[0]) << 24);
                    i += 4;
                    if (v <= 0x10ffff and (v < 0xd800 or v > 0xdfff)) cp = @intCast(v);
                }
            },
            .other => unreachable,
        }
        const c = cp orelse {
            try out.append(allocator, '?');
            continue;
        };
        switch (to) {
            .utf8 => {
                var buf: [4]u8 = undefined;
                const n = std.unicode.utf8Encode(c, &buf) catch {
                    try out.append(allocator, '?');
                    continue;
                };
                try out.appendSlice(allocator, buf[0..n]);
            },
            .latin1 => try out.append(allocator, if (c <= 0xff) @intCast(c) else '?'),
            .ascii => try out.append(allocator, if (c < 0x80) @intCast(c) else '?'),
            else => unreachable,
        }
    }
    return out.toOwnedSlice(allocator);
}

fn readUnit16(b: []const u8, le: bool) u16 {
    return if (le) @as(u16, b[0]) | (@as(u16, b[1]) << 8) else (@as(u16, b[0]) << 8) | @as(u16, b[1]);
}

test "a byte order mark names the script's encoding and goes" {
    const a = std.testing.allocator;
    script_encoding = null;
    internal_encoding = .latin1;
    defer internal_encoding = .utf8;
    const utf8 = (try filterScript(a, "\xef\xbb\xbf<?php echo 1;")).?;
    defer a.free(utf8);
    try std.testing.expectEqualStrings("<?php echo 1;", utf8);
    const utf16 = (try filterScript(a, "\xff\xfe<\x00?\x00\xe9\x00\n")).?;
    defer a.free(utf16);
    try std.testing.expectEqualStrings("<?\xe9?", utf16);
    try std.testing.expect((try filterScript(a, "<?php echo 1;")) == null);
}
