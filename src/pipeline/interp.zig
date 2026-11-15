// the parts of an interpolating string (a double-quoted string, a heredoc
// or a backtick command) as php's scanner splits them in ST_DOUBLE_QUOTES,
// ST_HEREDOC and ST_BACKQUOTE: literal text, a simple variable ("$a",
// "$a[k]", "$a->p", "$a?->p"), "{$...}" and "${...}". the parts are byte
// ranges of the source, so the code inside a string is lexed and parsed
// where it stands
const std = @import("std");
const Token = @import("token.zig").Token;
const Lexer = @import("lexer.zig").Lexer;

pub const Kind = enum { literal, simple, curly, dollar_brace };

pub const Part = struct {
    kind: Kind,
    // literal and simple: the text. curly: from the `$` after `{` to the
    // closing brace. dollar_brace: from after `${` to the closing brace
    start: u32,
    end: u32,
    // where the next part starts
    next: u32,
};

pub const Body = struct {
    start: u32,
    end: u32,
    heredoc: bool,
    // a heredoc's closing marker indentation, stripped from each line of
    // its literal text
    indent: u32 = 0,
};

pub fn isLabelStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_' or c >= 0x80;
}

pub fn isLabelChar(c: u8) bool {
    return isLabelStart(c) or std.ascii.isDigit(c);
}

// the interpolating body of a string token, null for one that can't
// interpolate (single-quoted, nowdoc)
pub fn body(source: []const u8, tok: Token) ?Body {
    const text = source[tok.start..tok.end];
    if (tok.tag == .heredoc) {
        const h = heredoc(source, tok) orelse return null;
        return .{ .start = h.body_start, .end = h.body_end, .heredoc = true, .indent = h.indent };
    }
    if (tok.tag != .string or text.len < 2) return null;
    if (text[0] != '"' and text[0] != '`') return null;
    return .{ .start = tok.start + 1, .end = tok.end - 1, .heredoc = false };
}

pub const Heredoc = struct {
    body_start: u32,
    body_end: u32,
    indent: u32,
};

pub fn isNewline(c: u8) bool {
    return c == '\n' or c == '\r';
}

// a heredoc or nowdoc token's body: the lines between the opener and the
// closing marker's line, without the newline before the marker
pub fn heredoc(source: []const u8, tok: Token) ?Heredoc {
    const text = source[tok.start..tok.end];
    var pos: usize = 3;
    while (pos < text.len and (text[pos] == ' ' or text[pos] == '\t')) pos += 1;
    if (pos < text.len and (text[pos] == '\'' or text[pos] == '"')) pos += 1;
    const label_start = pos;
    while (pos < text.len and isLabelChar(text[pos])) pos += 1;
    const label = text[label_start..pos];
    if (label.len == 0) return null;
    while (pos < text.len and !isNewline(text[pos])) pos += 1;
    if (pos < text.len and text[pos] == '\r') pos += 1;
    if (pos < text.len and text[pos] == '\n') pos += 1;
    const body_start = pos;
    if (text.len < label.len or !std.mem.eql(u8, text[text.len - label.len ..], label)) return null;
    const marker = text.len - label.len;
    var line_start = marker;
    while (line_start > body_start and (text[line_start - 1] == ' ' or text[line_start - 1] == '\t')) line_start -= 1;
    const indent = marker - line_start;
    var body_end = line_start;
    if (body_end > body_start and text[body_end - 1] == '\n') body_end -= 1;
    if (body_end > body_start and text[body_end - 1] == '\r') body_end -= 1;
    if (line_start <= body_start) body_end = body_start;
    return .{
        .body_start = tok.start + @as(u32, @intCast(body_start)),
        .body_end = tok.start + @as(u32, @intCast(@max(body_end, body_start))),
        .indent = @intCast(indent),
    };
}

// the part of the body starting at `pos`, null at its end. code that
// never closes runs to the end of the body
pub fn nextPart(source: []const u8, b: Body, pos: u32) ?Part {
    if (pos >= b.end) return null;
    const s = source[0..b.end];
    var i: usize = pos;
    if (s[i] == '{' and i + 1 < s.len and s[i + 1] == '$') {
        const close = Lexer.skipEmbeddedCode(s, i + 1) orelse s.len;
        return .{ .kind = .curly, .start = @intCast(i + 1), .end = @intCast(close), .next = @intCast(@min(close + 1, s.len)) };
    }
    if (s[i] == '$' and i + 1 < s.len and s[i + 1] == '{') {
        const close = Lexer.skipEmbeddedCode(s, i + 2) orelse s.len;
        return .{ .kind = .dollar_brace, .start = @intCast(i + 2), .end = @intCast(close), .next = @intCast(@min(close + 1, s.len)) };
    }
    if (s[i] == '$' and i + 1 < s.len and isLabelStart(s[i + 1])) {
        var j = i + 2;
        while (j < s.len and isLabelChar(s[j])) j += 1;
        if (j < s.len and s[j] == '[') {
            // ST_VAR_OFFSET: names, numbers, a variable and `-` up to `]`;
            // anything else is the parser's error
            var k = j + 1;
            while (k < s.len and s[k] != ']') : (k += 1) {
                switch (s[k]) {
                    ' ', '\n', '\r', '\t', '\\', '\'', '#', '"', '`', '[', '(', ')', '{', '}' => break,
                    else => {},
                }
            }
            if (k < s.len and s[k] == ']') k += 1;
            j = k;
        } else if (j + 2 < s.len and s[j] == '-' and s[j + 1] == '>' and isLabelStart(s[j + 2])) {
            j += 3;
            while (j < s.len and isLabelChar(s[j])) j += 1;
        } else if (j + 3 < s.len and s[j] == '?' and s[j + 1] == '-' and s[j + 2] == '>' and isLabelStart(s[j + 3])) {
            j += 4;
            while (j < s.len and isLabelChar(s[j])) j += 1;
        }
        return .{ .kind = .simple, .start = @intCast(i), .end = @intCast(j), .next = @intCast(j) };
    }
    // literal text up to the next variable or brace; a backslash keeps the
    // character after it in the text ("\$a", "\{$a}" read `$a` simple)
    while (i < s.len) {
        const c = s[i];
        if (c == '\\' and i + 1 < s.len) {
            i += 2;
            continue;
        }
        if (i > pos and c == '{' and i + 1 < s.len and s[i + 1] == '$') break;
        if (i > pos and c == '$' and i + 1 < s.len and (s[i + 1] == '{' or isLabelStart(s[i + 1]))) break;
        i += 1;
    }
    return .{ .kind = .literal, .start = pos, .end = @intCast(@min(i, s.len)), .next = @intCast(@min(i, s.len)) };
}

// whether the body has any part besides literal text
pub fn interpolates(source: []const u8, b: Body) bool {
    var pos = b.start;
    while (nextPart(source, b, pos)) |part| : (pos = part.next) {
        if (part.kind != .literal) return true;
    }
    return false;
}

// a heredoc literal's text with the closing marker's indentation removed
// from the start of each of its lines (strip_multiline_string_indentation)
pub fn dedent(allocator: std.mem.Allocator, source: []const u8, b: Body, start: u32, end: u32) std.mem.Allocator.Error![]const u8 {
    const text = source[start..end];
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(allocator);
    var at_line_start = start == b.start or isNewline(source[start - 1]);
    var i: usize = 0;
    while (i < text.len) {
        if (at_line_start) {
            var n: usize = 0;
            while (n < b.indent and i < text.len and (text[i] == ' ' or text[i] == '\t')) : (n += 1) i += 1;
            at_line_start = false;
            continue;
        }
        const c = text[i];
        try out.append(allocator, c);
        i += 1;
        if (c == '\n' or (c == '\r' and (i >= text.len or text[i] != '\n'))) at_line_start = true;
    }
    return out.toOwnedSlice(allocator);
}
