const std = @import("std");
const Token = @import("token.zig").Token;
const Tag = Token.Tag;

pub const Lexer = struct {
    source: []const u8,
    pos: usize,
    state: State,

    const State = enum { html, php };

    pub fn init(source: []const u8) Lexer {
        return .{ .source = source, .pos = 0, .state = .html };
    }

    pub fn next(self: *Lexer) Token {
        return switch (self.state) {
            .html => self.lexHtml(),
            .php => self.lexPhp(),
        };
    }

    // -- html mode ---------------------------------------------------------

    fn lexHtml(self: *Lexer) Token {
        const start = self.pos;

        while (self.pos < self.source.len) {
            if (self.source[self.pos] != '<') {
                self.pos += 1;
                continue;
            }
            if (self.pos + 1 >= self.source.len or self.source[self.pos + 1] != '?') {
                self.pos += 1;
                continue;
            }

            if (self.isOpenTagEcho()) {
                if (self.pos > start) return self.makeToken(.inline_html, start);
                const tag_start = self.pos;
                self.pos += 3;
                self.state = .php;
                return self.makeToken(.open_tag_echo, tag_start);
            }

            if (self.isOpenTagPhp()) {
                if (self.pos > start) return self.makeToken(.inline_html, start);
                const tag_start = self.pos;
                self.pos += 5;
                self.state = .php;
                return self.makeToken(.open_tag, tag_start);
            }

            self.pos += 1;
        }

        if (self.pos > start) return self.makeToken(.inline_html, start);
        return self.makeEof();
    }

    fn isOpenTagEcho(self: *const Lexer) bool {
        return self.pos + 2 < self.source.len and self.source[self.pos + 2] == '=';
    }

    fn isOpenTagPhp(self: *const Lexer) bool {
        if (self.pos + 5 > self.source.len) return false;
        if (!std.mem.eql(u8, self.source[self.pos + 2 .. self.pos + 5], "php")) return false;
        return self.pos + 5 >= self.source.len or isWhitespace(self.source[self.pos + 5]);
    }

    // -- php mode ----------------------------------------------------------

    fn lexPhp(self: *Lexer) Token {
        self.skipTrivia();
        if (self.pos >= self.source.len) return self.makeEof();

        const start = self.pos;
        const c = self.advance();

        return switch (c) {
            'a'...'z', 'A'...'Z', '_', 0x80...0xff => self.lexIdentifier(start),

            '$' => blk: {
                if (self.pos < self.source.len and isIdentStart(self.source[self.pos])) {
                    while (self.pos < self.source.len and isIdentChar(self.source[self.pos])) self.pos += 1;
                    break :blk self.makeToken(.variable, start);
                }
                break :blk self.makeToken(.dollar, start);
            },

            '0'...'9' => self.lexNumber(start),
            '\'' => self.lexStringBody('\'', start),
            '"' => self.lexStringBody('"', start),

            '.' => self.lexDot(start),
            '+' => self.lexPlus(start),
            '-' => self.lexMinus(start),
            '*' => self.lexStar(start),
            '/' => if (self.match('=')) self.makeToken(.slash_equal, start) else self.makeToken(.slash, start),
            '%' => if (self.match('=')) self.makeToken(.percent_equal, start) else self.makeToken(.percent, start),
            '=' => self.lexEqual(start),
            '!' => self.lexBang(start),
            '<' => self.lexLt(start),
            '>' => self.lexGt(start),
            '&' => self.lexAmp(start),
            '|' => self.lexPipe(start),
            '^' => if (self.match('=')) self.makeToken(.caret_equal, start) else self.makeToken(.caret, start),
            '?' => self.lexQuestion(start),
            '#' => if (self.match('[')) self.makeToken(.hash_bracket, start) else self.makeToken(.invalid, start),
            ':' => if (self.match(':')) self.makeToken(.colon_colon, start) else self.makeToken(.colon, start),

            '~' => self.makeToken(.tilde, start),
            '@' => self.makeToken(.at, start),
            '(' => self.makeToken(.l_paren, start),
            ')' => self.makeToken(.r_paren, start),
            '{' => self.makeToken(.l_brace, start),
            '}' => self.makeToken(.r_brace, start),
            '[' => self.makeToken(.l_bracket, start),
            ']' => self.makeToken(.r_bracket, start),
            ';' => self.makeToken(.semicolon, start),
            ',' => self.makeToken(.comma, start),
            '\\' => self.makeToken(.backslash, start),

            else => self.makeToken(.invalid, start),
        };
    }

    // -- operator lexers ---------------------------------------------------

    fn lexDot(self: *Lexer, start: usize) Token {
        if (self.pos < self.source.len and isDigit(self.source[self.pos])) {
            self.skipDecimalDigits();
            _ = self.skipExponent();
            return self.makeToken(.float, start);
        }
        if (self.match('.')) {
            if (self.match('.')) return self.makeToken(.ellipsis, start);
            return self.makeToken(.invalid, start);
        }
        if (self.match('=')) return self.makeToken(.dot_equal, start);
        return self.makeToken(.dot, start);
    }

    fn lexPlus(self: *Lexer, start: usize) Token {
        if (self.match('+')) return self.makeToken(.plus_plus, start);
        if (self.match('=')) return self.makeToken(.plus_equal, start);
        return self.makeToken(.plus, start);
    }

    fn lexMinus(self: *Lexer, start: usize) Token {
        if (self.match('-')) return self.makeToken(.minus_minus, start);
        if (self.match('=')) return self.makeToken(.minus_equal, start);
        if (self.match('>')) return self.makeToken(.arrow, start);
        return self.makeToken(.minus, start);
    }

    fn lexStar(self: *Lexer, start: usize) Token {
        if (self.match('*')) {
            if (self.match('=')) return self.makeToken(.star_star_equal, start);
            return self.makeToken(.star_star, start);
        }
        if (self.match('=')) return self.makeToken(.star_equal, start);
        return self.makeToken(.star, start);
    }

    fn lexEqual(self: *Lexer, start: usize) Token {
        if (self.match('=')) {
            if (self.match('=')) return self.makeToken(.equal_equal_equal, start);
            return self.makeToken(.equal_equal, start);
        }
        if (self.match('>')) return self.makeToken(.fat_arrow, start);
        return self.makeToken(.equal, start);
    }

    fn lexBang(self: *Lexer, start: usize) Token {
        if (self.match('=')) {
            if (self.match('=')) return self.makeToken(.bang_equal_equal, start);
            return self.makeToken(.bang_equal, start);
        }
        return self.makeToken(.bang, start);
    }

    fn lexLt(self: *Lexer, start: usize) Token {
        if (self.match('<')) {
            if (self.match('<')) return self.lexHeredoc(start);
            if (self.match('=')) return self.makeToken(.lt_lt_equal, start);
            return self.makeToken(.lt_lt, start);
        }
        if (self.match('=')) {
            if (self.match('>')) return self.makeToken(.spaceship, start);
            return self.makeToken(.lt_equal, start);
        }
        if (self.match('>')) return self.makeToken(.lt_gt, start);
        return self.makeToken(.lt, start);
    }

    fn lexHeredoc(self: *Lexer, start: usize) Token {
        var is_nowdoc = false;
        if (self.pos < self.source.len and self.source[self.pos] == '\'') {
            is_nowdoc = true;
            self.pos += 1;
        }

        const label_start = self.pos;
        while (self.pos < self.source.len and (std.ascii.isAlphanumeric(self.source[self.pos]) or self.source[self.pos] == '_')) {
            self.pos += 1;
        }
        const label = self.source[label_start..self.pos];
        if (label.len == 0) return self.makeToken(.invalid, start);

        if (is_nowdoc) {
            if (self.pos < self.source.len and self.source[self.pos] == '\'') {
                self.pos += 1;
            } else {
                return self.makeToken(.invalid, start);
            }
        }

        // skip to end of line
        while (self.pos < self.source.len and self.source[self.pos] != '\n') self.pos += 1;
        if (self.pos < self.source.len) self.pos += 1; // skip \n

        // scan for closing label
        while (self.pos < self.source.len) {
            const line_start = self.pos;

            // skip leading whitespace
            while (self.pos < self.source.len and (self.source[self.pos] == ' ' or self.source[self.pos] == '\t')) {
                self.pos += 1;
            }

            // check if this line starts with the label
            if (self.pos + label.len <= self.source.len and std.mem.eql(u8, self.source[self.pos .. self.pos + label.len], label)) {
                const after_label = self.pos + label.len;
                // closing label must be followed by ; or newline or EOF
                const terminates = after_label >= self.source.len or switch (self.source[after_label]) {
                    '\n', '\r', ';', ')', ',', ']' => true,
                    else => false,
                };
                if (terminates) {
                    self.pos = after_label;
                    return self.makeToken(if (is_nowdoc) .nowdoc else .heredoc, start);
                }
            }

            // skip to next line
            _ = line_start;
            while (self.pos < self.source.len and self.source[self.pos] != '\n') self.pos += 1;
            if (self.pos < self.source.len) self.pos += 1;
        }

        return self.makeToken(.invalid, start);
    }

    fn lexGt(self: *Lexer, start: usize) Token {
        if (self.match('>')) {
            if (self.match('=')) return self.makeToken(.gt_gt_equal, start);
            return self.makeToken(.gt_gt, start);
        }
        if (self.match('=')) return self.makeToken(.gt_equal, start);
        return self.makeToken(.gt, start);
    }

    fn lexAmp(self: *Lexer, start: usize) Token {
        if (self.match('&')) return self.makeToken(.amp_amp, start);
        if (self.match('=')) return self.makeToken(.amp_equal, start);
        return self.makeToken(.amp, start);
    }

    fn lexPipe(self: *Lexer, start: usize) Token {
        if (self.match('|')) return self.makeToken(.pipe_pipe, start);
        if (self.match('=')) return self.makeToken(.pipe_equal, start);
        return self.makeToken(.pipe, start);
    }

    fn lexQuestion(self: *Lexer, start: usize) Token {
        if (self.pos < self.source.len and self.source[self.pos] == '-' and
            self.pos + 1 < self.source.len and self.source[self.pos + 1] == '>')
        {
            self.pos += 2;
            return self.makeToken(.question_arrow, start);
        }
        if (self.match('>')) {
            self.state = .html;
            return self.makeToken(.close_tag, start);
        }
        if (self.match('?')) {
            if (self.match('=')) return self.makeToken(.question_question_equal, start);
            return self.makeToken(.question_question, start);
        }
        return self.makeToken(.question, start);
    }

    // -- identifiers and keywords ------------------------------------------

    fn lexIdentifier(self: *Lexer, start: usize) Token {
        while (self.pos < self.source.len and isIdentChar(self.source[self.pos])) self.pos += 1;
        const ident = self.source[start..self.pos];
        if (Tag.keyword(ident)) |kw| return self.makeToken(kw, start);
        return self.makeToken(.identifier, start);
    }

    // -- numbers -----------------------------------------------------------

    fn lexNumber(self: *Lexer, start: usize) Token {
        const first = self.source[start];

        if (first == '0' and self.pos < self.source.len) {
            switch (self.source[self.pos]) {
                'x', 'X' => {
                    self.pos += 1;
                    if (!self.skipHexDigits()) return self.makeToken(.invalid, start);
                    return self.makeToken(.integer, start);
                },
                'b', 'B' => {
                    self.pos += 1;
                    if (!self.skipBinaryDigits()) return self.makeToken(.invalid, start);
                    return self.makeToken(.integer, start);
                },
                'o', 'O' => {
                    self.pos += 1;
                    if (!self.skipOctalDigits()) return self.makeToken(.invalid, start);
                    return self.makeToken(.integer, start);
                },
                else => {},
            }
        }

        self.skipDecimalDigits();

        if (self.pos < self.source.len and self.source[self.pos] == '.') {
            if (self.pos + 1 < self.source.len and isDigit(self.source[self.pos + 1])) {
                self.pos += 1;
                self.skipDecimalDigits();
                _ = self.skipExponent();
                return self.makeToken(.float, start);
            }
        }

        if (self.skipExponent()) return self.makeToken(.float, start);

        return self.makeToken(.integer, start);
    }

    fn skipDecimalDigits(self: *Lexer) void {
        while (self.pos < self.source.len and (isDigit(self.source[self.pos]) or self.source[self.pos] == '_')) {
            self.pos += 1;
        }
    }

    fn skipHexDigits(self: *Lexer) bool {
        const s = self.pos;
        while (self.pos < self.source.len and (isHexDigit(self.source[self.pos]) or self.source[self.pos] == '_')) {
            self.pos += 1;
        }
        return self.pos > s;
    }

    fn skipBinaryDigits(self: *Lexer) bool {
        const s = self.pos;
        while (self.pos < self.source.len and (self.source[self.pos] == '0' or self.source[self.pos] == '1' or self.source[self.pos] == '_')) {
            self.pos += 1;
        }
        return self.pos > s;
    }

    fn skipOctalDigits(self: *Lexer) bool {
        const s = self.pos;
        while (self.pos < self.source.len and ((self.source[self.pos] >= '0' and self.source[self.pos] <= '7') or self.source[self.pos] == '_')) {
            self.pos += 1;
        }
        return self.pos > s;
    }

    fn skipExponent(self: *Lexer) bool {
        if (self.pos >= self.source.len) return false;
        if (self.source[self.pos] != 'e' and self.source[self.pos] != 'E') return false;
        self.pos += 1;
        if (self.pos < self.source.len and (self.source[self.pos] == '+' or self.source[self.pos] == '-')) {
            self.pos += 1;
        }
        self.skipDecimalDigits();
        return true;
    }

    // -- strings -----------------------------------------------------------

    fn lexStringBody(self: *Lexer, quote: u8, start: usize) Token {
        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (ch == '\\') {
                self.pos += 1;
                if (self.pos < self.source.len) self.pos += 1;
            } else if (ch == quote) {
                self.pos += 1;
                return self.makeToken(.string, start);
            } else {
                self.pos += 1;
            }
        }
        return self.makeToken(.invalid, start);
    }

    // -- trivia (whitespace / comments) ------------------------------------

    fn skipTrivia(self: *Lexer) void {
        while (self.pos < self.source.len) {
            switch (self.source[self.pos]) {
                ' ', '\t', '\n', '\r' => self.pos += 1,
                '/' => {
                    if (self.pos + 1 >= self.source.len) return;
                    switch (self.source[self.pos + 1]) {
                        '/' => self.skipLineComment(),
                        '*' => self.skipBlockComment(),
                        else => return,
                    }
                },
                '#' => {
                    if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '[') return;
                    self.skipLineComment();
                },
                else => return,
            }
        }
    }

    fn skipLineComment(self: *Lexer) void {
        while (self.pos < self.source.len and self.source[self.pos] != '\n') {
            // ?> terminates a line comment in PHP
            if (self.source[self.pos] == '?' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '>') return;
            self.pos += 1;
        }
    }

    fn skipBlockComment(self: *Lexer) void {
        self.pos += 2;
        while (self.pos + 1 < self.source.len) {
            if (self.source[self.pos] == '*' and self.source[self.pos + 1] == '/') {
                self.pos += 2;
                return;
            }
            self.pos += 1;
        }
        self.pos = self.source.len;
    }

    // -- primitives --------------------------------------------------------

    fn advance(self: *Lexer) u8 {
        const c = self.source[self.pos];
        self.pos += 1;
        return c;
    }

    fn match(self: *Lexer, expected: u8) bool {
        if (self.pos < self.source.len and self.source[self.pos] == expected) {
            self.pos += 1;
            return true;
        }
        return false;
    }

    fn makeToken(self: *const Lexer, tag: Tag, start: usize) Token {
        return .{ .tag = tag, .start = @intCast(start), .end = @intCast(self.pos) };
    }

    fn makeEof(self: *const Lexer) Token {
        const p: u32 = @intCast(self.pos);
        return .{ .tag = .eof, .start = p, .end = p };
    }

    // -- character classification ------------------------------------------

    fn isWhitespace(c: u8) bool {
        return c == ' ' or c == '\t' or c == '\n' or c == '\r';
    }

    fn isDigit(c: u8) bool {
        return c >= '0' and c <= '9';
    }

    fn isHexDigit(c: u8) bool {
        return (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
    }

    fn isIdentStart(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_' or c >= 0x80;
    }

    fn isIdentChar(c: u8) bool {
        return isIdentStart(c) or isDigit(c);
    }
};

// ==========================================================================
// tests
// ==========================================================================

fn expectTokens(source: []const u8, expected: []const Tag) !void {
    var lexer = Lexer.init(source);
    for (expected) |tag| {
        const tok = lexer.next();
        errdefer std.debug.print("expected {s}, got {s} at {d}..{d} \"{s}\"\n", .{
            @tagName(tag),
            @tagName(tok.tag),
            tok.start,
            tok.end,
            tok.lexeme(source),
        });
        try std.testing.expectEqual(tag, tok.tag);
    }
    const last = lexer.next();
    try std.testing.expectEqual(Tag.eof, last.tag);
}

fn expectLexeme(source: []const u8, tag: Tag, expected_lexeme: []const u8) !void {
    var lexer = Lexer.init(source);
    const tok = lexer.next();
    try std.testing.expectEqual(tag, tok.tag);
    try std.testing.expectEqualStrings(expected_lexeme, tok.lexeme(source));
}

test "empty source" {
    try expectTokens("", &.{});
}

test "php open tag" {
    try expectTokens("<?php ", &.{.open_tag});
}

test "php open tag echo" {
    try expectTokens("<?=", &.{.open_tag_echo});
}

test "inline html then php" {
    try expectTokens("<h1>Hi</h1><?php ", &.{ .inline_html, .open_tag });
}

test "close tag returns to html" {
    try expectTokens("<?php ?><b>x</b>", &.{ .open_tag, .close_tag, .inline_html });
}

test "hello world" {
    try expectTokens(
        "<?php echo \"hello\";",
        &.{ .open_tag, .kw_echo, .string, .semicolon },
    );
}

test "variable assignment" {
    try expectTokens(
        "<?php $x = 42;",
        &.{ .open_tag, .variable, .equal, .integer, .semicolon },
    );
}

test "variable lexeme includes dollar" {
    try expectLexeme("<?php $foo", .open_tag, "<?php");
    var lexer = Lexer.init("<?php $foo");
    _ = lexer.next();
    const tok = lexer.next();
    try std.testing.expectEqual(Tag.variable, tok.tag);
    try std.testing.expectEqualStrings("$foo", tok.lexeme("<?php $foo"));
}

test "bare dollar" {
    try expectTokens("<?php $", &.{ .open_tag, .dollar });
}

test "all single-char operators" {
    try expectTokens("<?php + - * / % = ! < > & | ^ ~ @ . ? ( ) { } [ ] ; , : \\", &.{
        .open_tag,  .plus,      .minus,     .star,      .slash,
        .percent,   .equal,     .bang,      .lt,        .gt,
        .amp,       .pipe,      .caret,     .tilde,     .at,
        .dot,       .question,  .l_paren,   .r_paren,   .l_brace,
        .r_brace,   .l_bracket, .r_bracket, .semicolon, .comma,
        .colon,     .backslash,
    });
}

test "multi-char operators" {
    try expectTokens("<?php ++ -- ** == === != !== <= >= <> <=> && || ?? -> => :: ... << >>", &.{
        .open_tag,
        .plus_plus,
        .minus_minus,
        .star_star,
        .equal_equal,
        .equal_equal_equal,
        .bang_equal,
        .bang_equal_equal,
        .lt_equal,
        .gt_equal,
        .lt_gt,
        .spaceship,
        .amp_amp,
        .pipe_pipe,
        .question_question,
        .arrow,
        .fat_arrow,
        .colon_colon,
        .ellipsis,
        .lt_lt,
        .gt_gt,
    });
}

test "compound assignment operators" {
    try expectTokens("<?php += -= *= /= %= **= .= &= |= ^= <<= >>= ??=", &.{
        .open_tag,
        .plus_equal,
        .minus_equal,
        .star_equal,
        .slash_equal,
        .percent_equal,
        .star_star_equal,
        .dot_equal,
        .amp_equal,
        .pipe_equal,
        .caret_equal,
        .lt_lt_equal,
        .gt_gt_equal,
        .question_question_equal,
    });
}

test "keywords" {
    try expectTokens("<?php if else elseif while for foreach function return class new", &.{
        .open_tag,
        .kw_if,
        .kw_else,
        .kw_elseif,
        .kw_while,
        .kw_for,
        .kw_foreach,
        .kw_function,
        .kw_return,
        .kw_class,
        .kw_new,
    });
}

test "case insensitive keywords" {
    try expectTokens("<?php IF ELSE WHILE Function CLASS", &.{
        .open_tag,
        .kw_if,
        .kw_else,
        .kw_while,
        .kw_function,
        .kw_class,
    });
}

test "identifiers vs keywords" {
    try expectTokens("<?php ifx classy", &.{ .open_tag, .identifier, .identifier });
}

test "integer literals" {
    try expectTokens("<?php 0 42 1_000", &.{ .open_tag, .integer, .integer, .integer });
}

test "hex literals" {
    try expectTokens("<?php 0xff 0XAB", &.{ .open_tag, .integer, .integer });
}

test "binary literals" {
    try expectTokens("<?php 0b1010 0B11", &.{ .open_tag, .integer, .integer });
}

test "octal literals" {
    try expectTokens("<?php 0o17 0O77", &.{ .open_tag, .integer, .integer });
}

test "float literals" {
    try expectTokens("<?php 1.5 3.14 1.0e10 2.5E-3 1e5", &.{
        .open_tag, .float, .float, .float, .float, .float,
    });
}

test "float starting with dot" {
    try expectTokens("<?php .5 .123e4", &.{ .open_tag, .float, .float });
}

test "single quoted string" {
    try expectLexeme("<?php 'hello'", .open_tag, "<?php");
    var lexer = Lexer.init("<?php 'hello'");
    _ = lexer.next();
    const tok = lexer.next();
    try std.testing.expectEqual(Tag.string, tok.tag);
    try std.testing.expectEqualStrings("'hello'", tok.lexeme("<?php 'hello'"));
}

test "double quoted string" {
    try expectTokens("<?php \"world\"", &.{ .open_tag, .string });
}

test "string with escapes" {
    try expectTokens("<?php 'it\\'s' \"line\\n\"", &.{ .open_tag, .string, .string });
}

test "unterminated string" {
    try expectTokens("<?php \"oops", &.{ .open_tag, .invalid });
}

test "line comment //" {
    try expectTokens("<?php // comment\n$x", &.{ .open_tag, .variable });
}

test "line comment #" {
    try expectTokens("<?php # comment\n$x", &.{ .open_tag, .variable });
}

test "block comment" {
    try expectTokens("<?php /* block */ $x", &.{ .open_tag, .variable });
}

test "doc comment" {
    try expectTokens("<?php /** doc */ $x", &.{ .open_tag, .variable });
}

test "attribute #[" {
    try expectTokens("<?php #[Attr]", &.{ .open_tag, .hash_bracket, .identifier, .r_bracket });
}

test "close tag ?>" {
    try expectTokens("<?php $x; ?> html", &.{
        .open_tag, .variable, .semicolon, .close_tag, .inline_html,
    });
}

test "function definition" {
    try expectTokens(
        "<?php function add($a, $b) { return $a + $b; }",
        &.{
            .open_tag,   .kw_function, .identifier, .l_paren,   .variable,
            .comma,      .variable,    .r_paren,    .l_brace,   .kw_return,
            .variable,   .plus,        .variable,   .semicolon, .r_brace,
        },
    );
}

test "class definition" {
    try expectTokens(
        "<?php class Foo extends Bar { public function baz(): void {} }",
        &.{
            .open_tag,     .kw_class,    .identifier, .kw_extends, .identifier,
            .l_brace,      .kw_public,   .kw_function, .identifier, .l_paren,
            .r_paren,      .colon,       .identifier,  .l_brace,   .r_brace,
            .r_brace,
        },
    );
}

test "match expression" {
    try expectTokens("<?php match($x) { 1 => 'a', 2 => 'b' }", &.{
        .open_tag,    .kw_match,  .l_paren,   .variable,  .r_paren,
        .l_brace,     .integer,   .fat_arrow, .string,    .comma,
        .integer,     .fat_arrow, .string,    .r_brace,
    });
}

test "null coalesce chain" {
    try expectTokens("<?php $a ?? $b ?? $c", &.{
        .open_tag,
        .variable,
        .question_question,
        .variable,
        .question_question,
        .variable,
    });
}

test "spaceship operator" {
    try expectTokens("<?php $a <=> $b", &.{
        .open_tag, .variable, .spaceship, .variable,
    });
}

test "spread operator" {
    try expectTokens("<?php foo(...$args)", &.{
        .open_tag, .identifier, .l_paren, .ellipsis, .variable, .r_paren,
    });
}

test "namespace path" {
    try expectTokens("<?php App\\Models\\User", &.{
        .open_tag, .identifier, .backslash, .identifier, .backslash, .identifier,
    });
}

test "mixed html and php" {
    try expectTokens(
        "<html><?php echo $x; ?></html>",
        &.{ .inline_html, .open_tag, .kw_echo, .variable, .semicolon, .close_tag, .inline_html },
    );
}

test "multiple php blocks" {
    try expectTokens(
        "A<?php $a; ?>B<?= $b ?>C",
        &.{
            .inline_html, .open_tag,      .variable, .semicolon,
            .close_tag,   .inline_html,   .open_tag_echo, .variable,
            .close_tag,   .inline_html,
        },
    );
}

test "invalid hex literal" {
    try expectTokens("<?php 0x", &.{ .open_tag, .invalid });
}

test "invalid character" {
    try expectTokens("<?php `cmd`", &.{ .open_tag, .invalid, .identifier, .invalid });
}
