// php's own parser, run without semantic actions over php's token stream, to
// word a syntax error exactly as php does: which token it stops at, how that
// token is named, and the expected tokens bison lists. the tables are php's
// (php_grammar_generated.zig); the token stream is the tokenizer that also
// serves token_get_all, so both see the source the way php's scanner does

const std = @import("std");
const g = @import("php_grammar_generated.zig");
const tokenizer = @import("../stdlib/tokenizer.zig");
const t = @import("../stdlib/tokens_generated.zig");

pub const SyntaxError = struct {
    message: []u8,
    line: u32,
};

const symbol_error = 1;
const max_expected = 4;

// the error php's parser raises for the source, or null when php's grammar
// accepts it. the caller owns the message
pub fn diagnose(allocator: std.mem.Allocator, source: []const u8) !?SyntaxError {
    const tokens = try tokenizer.tokenize(allocator, source, true);
    defer allocator.free(tokens);
    var scanner: Scanner = .{ .tokens = tokens, .source = source };
    defer scanner.nesting.deinit(allocator);

    var states: std.ArrayListUnmanaged(i32) = .empty;
    defer states.deinit(allocator);
    try states.append(allocator, 0);
    var lookahead: ?Lookahead = null;

    while (true) {
        const state = states.items[states.items.len - 1];
        if (state == g.final) return null;
        var rule: i32 = undefined;
        decide: {
            var n: i32 = g.pact[@intCast(state)];
            if (n == g.pact_ninf) break :decide;
            if (lookahead == null) {
                lookahead = switch (try scanner.next(allocator)) {
                    .token => |tok| tok,
                    .failed => |failure| return failure,
                };
            }
            n += lookahead.?.symbol;
            if (n < 0 or n > g.last or g.check[@intCast(n)] != lookahead.?.symbol) break :decide;
            n = g.table[@intCast(n)];
            if (n <= 0) {
                if (n == g.table_ninf) return try report(allocator, &scanner, state, lookahead);
                rule = -n;
            } else {
                try states.append(allocator, n);
                lookahead = null;
                continue;
            }
            try reduce(allocator, &states, rule);
            continue;
        }
        rule = g.defact[@intCast(state)];
        if (rule == 0) return try report(allocator, &scanner, state, lookahead);
        try reduce(allocator, &states, rule);
    }
}

fn reduce(allocator: std.mem.Allocator, states: *std.ArrayListUnmanaged(i32), rule: i32) !void {
    states.shrinkRetainingCapacity(states.items.len - g.r2[@intCast(rule)]);
    const top = states.items[states.items.len - 1];
    const lhs: usize = @intCast(g.r1[@intCast(rule)] - g.ntokens);
    const i = g.pgoto[lhs] + top;
    const next: i32 = if (i >= 0 and i <= g.last and g.check[@intCast(i)] == top) g.table[@intCast(i)] else g.defgoto[lhs];
    try states.append(allocator, next);
}

const Lookahead = struct {
    symbol: i32,
    text: []const u8,
    end_of_file: bool,
};

const Next = union(enum) {
    token: Lookahead,
    failed: SyntaxError,
};

const Opening = struct { char: u8, line: u32 };

// php's scanner in parser mode: trivia skipped, `<?=` read as echo and `?>`
// as a semicolon, and brackets checked for nesting as they are scanned
const Scanner = struct {
    tokens: []const tokenizer.Token,
    source: []const u8,
    index: usize = 0,
    // the line php's scanner is on, the one an error reports
    line: u32 = 1,
    nesting: std.ArrayListUnmanaged(Opening) = .empty,

    fn next(self: *Scanner, allocator: std.mem.Allocator) !Next {
        while (self.index < self.tokens.len) {
            const tok = self.tokens[self.index];
            self.index += 1;
            self.line = tok.line;
            const id: i64 = switch (tok.id) {
                t.T_WHITESPACE, t.T_COMMENT, t.T_DOC_COMMENT, t.T_OPEN_TAG => continue,
                t.T_OPEN_TAG_WITH_ECHO => t.T_ECHO,
                t.T_CLOSE_TAG => ';',
                else => tok.id,
            };
            // a token's newlines are behind the scanner once it is read; the
            // one ending `?>` counts toward the next token
            if (tok.id != t.T_CLOSE_TAG) self.line += lineBreaks(tok.text);
            switch (id) {
                '(', '[', '{', t.T_CURLY_OPEN, t.T_DOLLAR_OPEN_CURLY_BRACES, t.T_ATTRIBUTE => {
                    const char: u8 = switch (id) {
                        '(' => '(',
                        '[', t.T_ATTRIBUTE => '[',
                        else => '{',
                    };
                    try self.nesting.append(allocator, .{ .char = char, .line = tok.line });
                },
                ')', ']', '}' => if (try self.exitNesting(allocator, @intCast(id))) |failure| return .{ .failed = failure },
                else => {},
            }
            return .{ .token = .{ .symbol = g.translate[@intCast(id)], .text = tok.text, .end_of_file = false } };
        }
        self.line = 1 + lineBreaks(self.source);
        if (self.nesting.items.len > 0) {
            return .{ .failed = try self.badNesting(allocator, self.nesting.items[self.nesting.items.len - 1], 0) };
        }
        return .{ .token = .{ .symbol = 0, .text = "", .end_of_file = true } };
    }

    fn exitNesting(self: *Scanner, allocator: std.mem.Allocator, closing: u8) !?SyntaxError {
        const top = self.nesting.pop() orelse return .{
            .message = try std.fmt.allocPrint(allocator, "Unmatched '{c}'", .{closing}),
            .line = self.line,
        };
        const expected: u8 = switch (top.char) {
            '(' => ')',
            '[' => ']',
            else => '}',
        };
        if (closing != expected) return try self.badNesting(allocator, top, closing);
        return null;
    }

    fn badNesting(self: *Scanner, allocator: std.mem.Allocator, opening: Opening, closing: u8) !SyntaxError {
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        errdefer buf.deinit(allocator);
        try buf.print(allocator, "Unclosed '{c}'", .{opening.char});
        if (opening.line != self.line) try buf.print(allocator, " on line {d}", .{opening.line});
        if (closing != 0) try buf.print(allocator, " does not match '{c}'", .{closing});
        return .{ .message = try buf.toOwnedSlice(allocator), .line = self.line };
    }
};

fn lineBreaks(text: []const u8) u32 {
    var count: u32 = 0;
    for (text, 0..) |c, i| {
        if (c == '\n' or (c == '\r' and (i + 1 == text.len or text[i + 1] != '\n'))) count += 1;
    }
    return count;
}

// bison's verbose message: the unexpected token, then up to four expected
// ones when the state has no more than that
fn report(allocator: std.mem.Allocator, scanner: *const Scanner, state: i32, lookahead: ?Lookahead) !SyntaxError {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(allocator);
    const tok = lookahead orelse {
        try buf.appendSlice(allocator, "syntax error");
        return .{ .message = try buf.toOwnedSlice(allocator), .line = scanner.line };
    };
    try buf.appendSlice(allocator, "syntax error, unexpected ");
    try describeUnexpected(&buf, allocator, tok);
    var expected: [max_expected]usize = undefined;
    const count = expectedTokens(state, &expected);
    for (expected[0..count], 0..) |symbol, i| {
        try buf.appendSlice(allocator, if (i == 0) ", expecting " else " or ");
        try describeExpected(&buf, allocator, g.tname[symbol]);
    }
    return .{ .message = try buf.toOwnedSlice(allocator), .line = scanner.line };
}

// the tokens the state can shift, or none when there are more than four
fn expectedTokens(state: i32, out: *[max_expected]usize) usize {
    const n: i32 = g.pact[@intCast(state)];
    if (n == g.pact_ninf) return 0;
    const begin: i32 = if (n < 0) -n else 0;
    const end: i32 = @min(g.last - n + 1, g.ntokens);
    var count: usize = 0;
    var x = begin;
    while (x < end) : (x += 1) {
        const i: usize = @intCast(x + n);
        if (g.check[i] != x or x == symbol_error or g.table[i] == g.table_ninf) continue;
        if (count == max_expected) return 0;
        out[count] = @intCast(x);
        count += 1;
    }
    return count;
}

// "syntax error, unexpected ..." naming the php token at a source offset,
// for an error php's grammar doesn't see. the caller owns the message
pub fn unexpectedAt(allocator: std.mem.Allocator, source: []const u8, offset: usize) ![]u8 {
    const tokens = try tokenizer.tokenize(allocator, source, true);
    defer allocator.free(tokens);
    var lookahead: Lookahead = .{ .symbol = 0, .text = "", .end_of_file = true };
    for (tokens) |tok| {
        if (tok.pos + tok.text.len <= offset) continue;
        switch (tok.id) {
            t.T_WHITESPACE, t.T_COMMENT, t.T_DOC_COMMENT, t.T_OPEN_TAG => continue,
            else => {},
        }
        const id: i64 = switch (tok.id) {
            t.T_OPEN_TAG_WITH_ECHO => t.T_ECHO,
            t.T_CLOSE_TAG => ';',
            else => tok.id,
        };
        lookahead = .{ .symbol = g.translate[@intCast(id)], .text = tok.text, .end_of_file = false };
        break;
    }
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(allocator);
    try buf.appendSlice(allocator, "syntax error, unexpected ");
    try describeUnexpected(&buf, allocator, lookahead);
    return buf.toOwnedSlice(allocator);
}

// zend_yytnamerr for the unexpected token: fixed tokens by their spelling,
// the rest by their kind and text
fn describeUnexpected(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, tok: Lookahead) !void {
    const name = g.tname[@intCast(tok.symbol)];
    if (tok.end_of_file) return buf.appendSlice(allocator, "end of file");
    if (std.mem.eql(u8, name, "\"'\\\\'\"")) return buf.appendSlice(allocator, "token \"\\\"");
    if (std.mem.eql(u8, name, "\"amp\"")) return buf.appendSlice(allocator, "token \"&\"");
    if (std.mem.eql(u8, name, "'\"'")) return buf.appendSlice(allocator, "double-quote mark");
    var kind = name;
    if (kind.len >= 2 and kind[0] == '"') kind = kind[1 .. kind.len - 1];
    if (kind.len > 0 and kind[0] == '\'') return buf.print(allocator, "token \"{s}\"", .{kind[1 .. kind.len - 1]});

    var content = tok.text;
    if (content.len == 1 and std.mem.eql(u8, name, "\"invalid character\"")) return buf.print(allocator, "character 0x{X:0>2}", .{content[0]});
    if (std.mem.indexOfScalar(u8, content, '\n')) |nl| content = content[0..nl];
    if (content.len > 0 and std.mem.eql(u8, name, "\"quoted string\"")) {
        if (content[0] == '"') kind = "double-quoted string" else if (content[0] == '\'') kind = "single-quoted string";
    }
    if (content.len > 0 and (content[0] == '\'' or content[0] == '"')) content = content[1..];
    if (content.len > 0 and (content[content.len - 1] == '\'' or content[content.len - 1] == '"')) content = content[0 .. content.len - 1];
    if (content.len > 33) return buf.print(allocator, "{s} \"{s}...\"", .{ kind, content[0..30] });
    try buf.print(allocator, "{s} \"{s}\"", .{ kind, content });
}

// zend_yytnamerr for an expected token: its declared name, single quotes
// turned double
fn describeExpected(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, name: []const u8) !void {
    if (std.mem.eql(u8, name, "\"'\\\\'\"")) return buf.appendSlice(allocator, "\"\\\"");
    if (std.mem.eql(u8, name, "\"amp\"")) return buf.appendSlice(allocator, "token \"&\"");
    var kind = name;
    if (kind.len >= 2 and kind[0] == '"') kind = kind[1 .. kind.len - 1];
    for (kind) |c| try buf.append(allocator, if (c == '\'') '"' else c);
}

test "php's wording for a syntax error" {
    const cases = [_]struct { source: []const u8, message: []const u8, line: u32 }{
        .{ .source = "<?php\n$x = 5 6;\n", .message = "syntax error, unexpected integer \"6\"", .line = 2 },
        .{ .source = "<?php\necho Foo\\Bar Baz;\n", .message = "syntax error, unexpected identifier \"Baz\", expecting \",\" or \";\"", .line = 2 },
        .{ .source = "<?php\nfunction f( {\n", .message = "syntax error, unexpected token \"{\", expecting variable", .line = 2 },
        .{ .source = "<?php\nfunction () {}\n", .message = "syntax error, unexpected end of file", .line = 3 },
        .{ .source = "<?php\nif ($x) { echo 1;\n", .message = "Unclosed '{' on line 2", .line = 3 },
        .{ .source = "<?php\n$a = (1];\n", .message = "Unclosed '(' does not match ']'", .line = 2 },
        .{ .source = "<?php\n}\n", .message = "Unmatched '}'", .line = 2 },
    };
    for (cases) |case| {
        const found = (try diagnose(std.testing.allocator, case.source)) orelse return error.TestUnexpectedResult;
        defer std.testing.allocator.free(found.message);
        try std.testing.expectEqualStrings(case.message, found.message);
        try std.testing.expectEqual(case.line, found.line);
    }
    try std.testing.expect((try diagnose(std.testing.allocator, "<?php\nclass A { public function f(int $x): ?int { return $x?->y; } }\n")) == null);
}
