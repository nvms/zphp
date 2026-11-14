// parse_ini_string() and parse_ini_file(): a port of php's ini scanner
// (Zend/zend_ini_scanner.l) and parser (Zend/zend_ini_parser.y), the parser
// run on php's own LALR tables (ini_grammar_generated.zig) so syntax errors
// read as php's, and the callbacks of ext/standard that build the array
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const std = @import("std");
const filesystem = @import("filesystem.zig");
const platform = @import("../platform.zig");
const g = @import("ini_grammar_generated.zig");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "parse_ini_string", native_parse_ini_string },
    .{ "parse_ini_file", native_parse_ini_file },
};

const Mode = enum { normal, raw, typed };

fn modeOf(ctx: *NativeContext, n: i64) RuntimeError!?Mode {
    return switch (n) {
        0 => .normal,
        1 => .raw,
        2 => .typed,
        else => {
            try ctx.vm.emitWarning("Invalid scanner mode");
            return null;
        },
    };
}

fn native_parse_ini_string(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = @import("string_ports.zig").Args.init(ctx, "parse_ini_string", args);
    const input = try p.str(0, "ini_string");
    const sections = try p.boolean(1, "process_sections", false);
    const mode = (try modeOf(ctx, if (p.has(2)) try p.long(2, "scanner_mode") else 0)) orelse return NativeResult.scalar(.{ .bool = false });
    // php copies the string and scans it up to its first nul
    const text = input[0 .. std.mem.indexOfScalar(u8, input, 0) orelse input.len];
    return parse(ctx, text, null, sections, mode);
}

fn native_parse_ini_file(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = @import("string_ports.zig").Args.init(ctx, "parse_ini_file", args);
    const filename = try p.str(0, "filename");
    if (std.mem.indexOfScalar(u8, filename, 0) != null) return p.valueError(0, "filename", "must not contain any null bytes");
    if (filename.len == 0) return p.valueError(0, "filename", "must not be empty");
    const sections = try p.boolean(1, "process_sections", false);
    const mode_n = if (p.has(2)) try p.long(2, "scanner_mode") else 0;
    // opened the way include opens a file: through the include path, with
    // php's warning when it cannot be
    const path = try filesystem.includePathLookup(ctx, filename, true);
    const content = (try filesystem.readPathAs(ctx, path, "parse_ini_file")) orelse return NativeResult.scalar(Value{ .bool = false });
    defer content.release();
    const mode = (try modeOf(ctx, mode_n)) orelse return NativeResult.scalar(.{ .bool = false });
    return parse(ctx, content.bytes(), filename, sections, mode);
}

// the scanner's tokens: a character for the single-character ones, else
// php's token codes
const Tok = struct {
    pub const end: u16 = 0;
    pub const section: u16 = 258;
    pub const raw: u16 = 259;
    pub const constant: u16 = 260;
    pub const number: u16 = 261;
    pub const string: u16 = 262;
    pub const whitespace: u16 = 263;
    pub const label: u16 = 264;
    pub const offset: u16 = 265;
    pub const dollar_curly: u16 = 266;
    pub const varname: u16 = 267;
    pub const quoted_string: u16 = 268;
    pub const fallback: u16 = 269;
    pub const bool_true: u16 = 270;
    pub const bool_false: u16 = 271;
    pub const null_null: u16 = 272;
    pub const end_of_line: u16 = 273;
};

// a semantic value: a string, or in typed mode a bool, null or int; `number`
// marks a string a TC_NUMBER started (INI_ZVAL_IS_NUMBER)
const Val = struct {
    kind: enum { string, boolean, null, long, double } = .string,
    s: []const u8 = "",
    b: bool = false,
    l: i64 = 0,
    d: f64 = 0,
    number: bool = false,
};

const State = enum { initial, offset, section_value, value, section_raw, double_quotes, varname, var_fallback, raw };

const Scanner = struct {
    a: std.mem.Allocator,
    src: []const u8,
    pos: usize = 0,
    state: State = .initial,
    stack: std.ArrayListUnmanaged(State) = .empty,
    lineno: u32 = 1,
    mode: Mode,

    fn at(self: *const Scanner, i: usize) u8 {
        return if (i < self.src.len) self.src[i] else 0;
    }

    fn push(self: *Scanner, s: State) !void {
        try self.stack.append(self.a, self.state);
        self.state = s;
    }

    fn pop(self: *Scanner) void {
        self.state = self.stack.pop() orelse .initial;
    }

    fn token(self: *Scanner, kind: u16, text: []const u8, out: *Val) !u16 {
        out.* = .{};
        if (self.mode == .typed and (self.state == .value or self.state == .raw)) {
            switch (kind) {
                Tok.bool_true, Tok.bool_false => {
                    out.kind = .boolean;
                    out.b = kind == Tok.bool_true;
                    return kind;
                },
                Tok.null_null => {
                    out.kind = .null;
                    return kind;
                },
                else => {},
            }
        }
        out.s = try self.a.dupe(u8, text);
        return kind;
    }

    // ini_lex
    fn next(self: *Scanner, out: *Val) !u16 {
        while (true) {
            out.* = .{};
            const start = self.pos;
            if (start >= self.src.len) {
                if (self.state == .value or self.state == .raw) {
                    self.state = .initial;
                    return Tok.end_of_line;
                }
                return Tok.end;
            }
            if (start == 0 and self.src.len > 3 and std.mem.startsWith(u8, self.src, "\xef\xbb\xbf")) {
                self.pos = 3;
                continue;
            }
            const r = try self.rule(out);
            if (r) |kind| return kind;
        }
    }

    fn isLabelChar(c: u8) bool {
        return switch (c) {
            '=', '\n', '\r', '\t', ';', '&', '|', '^', '$', '~', '(', ')', '{', '}', '!', '"', '[', ']', 0 => false,
            else => true,
        };
    }

    fn spaces(self: *const Scanner, i: usize) usize {
        var j = i;
        while (self.at(j) == ' ' or self.at(j) == '\t') j += 1;
        return j;
    }

    // a NEWLINE at i: its length, or 0
    fn newline(self: *const Scanner, i: usize) usize {
        if (self.at(i) == '\r') return if (self.at(i + 1) == '\n') 2 else 1;
        if (self.at(i) == '\n') return 1;
        return 0;
    }

    fn inRange(self: *const Scanner, i: usize) bool {
        return i < self.src.len;
    }

    // LITERAL_DOLLAR at i: "$" then a byte that is not "{" or nul, or "\" and any byte
    fn literalDollar(self: *const Scanner, i: usize) usize {
        if (self.at(i) != '$' or !self.inRange(i + 1)) return 0;
        const c = self.src[i + 1];
        if (c == '\\' and self.inRange(i + 2)) return 3;
        if (c == '{' or c == 0) return 0;
        return 2;
    }

    fn valueChars(self: *const Scanner, i: usize) usize {
        var j = i;
        while (self.inRange(j)) {
            const c = self.src[j];
            switch (c) {
                '$' => {
                    const n = self.literalDollar(j);
                    if (n == 0) break;
                    j += n;
                },
                '=', ' ', '\t', '\n', '\r', ';', '&', '|', '^', '~', '(', ')', '!', '"', '\'', 0 => break,
                else => j += 1,
            }
        }
        return j - i;
    }

    // FALLBACK_CHARS+ (excluding is "}") or SECTION_VALUE_CHARS+ (excluding is "]")
    fn escapedChars(self: *const Scanner, i: usize, excluded: u8) usize {
        var j = i;
        while (self.inRange(j)) {
            const c = self.src[j];
            if (c == '$') {
                const n = self.literalDollar(j);
                if (n == 0) break;
                j += n;
            } else if (c == '\\') {
                if (!self.inRange(j + 1)) break;
                j += 2;
            } else if (c == '\n' or c == '\r' or c == ';' or c == '"' or c == '\'' or c == excluded) {
                break;
            } else {
                j += 1;
            }
        }
        return j - i;
    }

    fn constantLen(self: *const Scanner, i: usize) usize {
        const c = self.at(i);
        if (!(std.ascii.isAlphabetic(c) or c == '_')) return 0;
        var j = i + 1;
        while (std.ascii.isAlphanumeric(self.at(j)) or self.at(j) == '_') j += 1;
        return j - i;
    }

    fn digits(self: *const Scanner, i: usize) usize {
        var j = i;
        while (std.ascii.isDigit(self.at(j))) j += 1;
        return j - i;
    }

    // NUMBER: [-]?[0-9]+ | [0-9]*[.][0-9]+ | [0-9]+[.][0-9]*
    fn numberLen(self: *const Scanner, i: usize) usize {
        var best: usize = 0;
        const neg: usize = if (self.at(i) == '-') 1 else 0;
        const d1 = self.digits(i + neg);
        if (d1 > 0) best = neg + d1;
        const d0 = self.digits(i);
        if (self.at(i + d0) == '.') {
            const frac = self.digits(i + d0 + 1);
            if (frac > 0 or d0 > 0) best = @max(best, d0 + 1 + frac);
        }
        return best;
    }

    fn keyword(self: *const Scanner, i: usize, comptime words: []const []const u8) usize {
        var best: usize = 0;
        inline for (words) |w| {
            if (std.ascii.startsWithIgnoreCase(self.src[i..], w)) best = @max(best, w.len);
        }
        if (best == 0) return 0;
        return self.spaces(i + best) - i;
    }

    // the rules that apply in the current state, longest match first, the
    // earlier rule on a tie (re2c)
    fn rule(self: *Scanner, out: *Val) !?u16 {
        const i = self.pos;
        const c = self.src[i];
        const st = self.state;
        var best_len: usize = 0;
        var best: u8 = 0;
        const Cand = struct {
            fn take(bl: *usize, b: *u8, id: u8, len: usize) void {
                if (len > bl.*) {
                    bl.* = len;
                    b.* = id;
                }
            }
        };
        const value_like = st == .value or st == .section_value or st == .offset or st == .var_fallback;
        // 1: "[" in INITIAL
        if (st == .initial and c == '[') Cand.take(&best_len, &best, 1, 1);
        // 2: '...' raw string
        if (st == .value or st == .section_value or st == .offset) if (c == '\'') {
            if (std.mem.indexOfScalarPos(u8, self.src, i + 1, '\'')) |close| if (close > i + 1) Cand.take(&best_len, &best, 2, close + 1 - i);
        };
        // 3: "]" [ \t]* NEWLINE? ending a section
        if ((st == .section_raw or st == .section_value) and c == ']') {
            const e = self.spaces(i + 1);
            Cand.take(&best_len, &best, 3, e + self.newline(e) - i);
        }
        // 4: LABEL "[" [ \t]* starting an offset
        if (st == .initial and isLabelChar(c)) {
            var j = i;
            while (isLabelChar(self.at(j))) j += 1;
            if (self.at(j) == '[') Cand.take(&best_len, &best, 4, self.spaces(j + 1) - i);
        }
        // 5: [ \t]* "]" ending an offset
        if (st == .offset) {
            const e = self.spaces(i);
            if (self.at(e) == ']') Cand.take(&best_len, &best, 5, e + 1 - i);
        }
        // 6: "${"
        if ((st == .double_quotes or value_like) and c == '$' and self.at(i + 1) == '{') Cand.take(&best_len, &best, 6, 2);
        // 7: ":-" and 8: a variable name
        if (st == .varname) {
            if (c == ':' and self.at(i + 1) == '-') Cand.take(&best_len, &best, 7, 2);
            if (isLabelChar(c)) Cand.take(&best_len, &best, 8, 1);
        }
        // 9: "}"
        if ((st == .varname or st == .var_fallback) and c == '}') Cand.take(&best_len, &best, 9, 1);
        if (st == .initial or st == .value) {
            Cand.take(&best_len, &best, 10, self.keyword(i, &.{ "true", "on", "yes" }));
            Cand.take(&best_len, &best, 11, self.keyword(i, &.{ "false", "off", "no", "none" }));
            Cand.take(&best_len, &best, 12, self.keyword(i, &.{"null"}));
        }
        if (st == .initial) {
            // 13: LABEL
            var j = i;
            while (isLabelChar(self.at(j))) j += 1;
            Cand.take(&best_len, &best, 13, j - i);
            // 14: [ \t]* "=" [ \t]*
            const e = self.spaces(i);
            if (self.at(e) == '=') Cand.take(&best_len, &best, 14, self.spaces(e + 1) - i);
        }
        // 15: a raw value
        if (st == .raw and c != '\n' and c != '\r' and c != ';' and c != 0) Cand.take(&best_len, &best, 15, 1);
        // 16: a raw section name
        if (st == .section_raw) {
            var j = i;
            while (self.inRange(j) and self.src[j] != ']' and self.src[j] != '\n' and self.src[j] != '\r') j += 1;
            Cand.take(&best_len, &best, 16, j - i);
        }
        // 17: [ \t]* NEWLINE ending a value
        if (st == .value or st == .raw) {
            const e = self.spaces(i);
            const nl = self.newline(e);
            if (nl > 0) Cand.take(&best_len, &best, 17, e + nl - i);
        }
        if (value_like) {
            Cand.take(&best_len, &best, 18, self.constantLen(i));
            Cand.take(&best_len, &best, 19, self.numberLen(i));
        }
        // 20: a character outside values
        if (st == .initial and std.mem.indexOfScalar(u8, ":,.[]\"'()&|^+,-./*=%$!~<>?@{}", c) != null) Cand.take(&best_len, &best, 20, 1);
        if (st == .value) {
            // 21: an operator, 22: "=" in a value, 23: other value characters
            if (std.mem.indexOfScalar(u8, "&|^~()!", c) != null) Cand.take(&best_len, &best, 21, self.spaces(i + 1) - i);
            if (c == '=') Cand.take(&best_len, &best, 22, 1);
            Cand.take(&best_len, &best, 23, self.valueChars(i));
        }
        if (st == .var_fallback) Cand.take(&best_len, &best, 24, self.escapedChars(i, '}'));
        if (st == .section_value or st == .offset) Cand.take(&best_len, &best, 25, self.escapedChars(i, ']'));
        // 26: [ \t]* '"' opening a quoted string
        if (value_like) {
            const e = self.spaces(i);
            if (self.at(e) == '"') Cand.take(&best_len, &best, 26, e + 1 - i);
        }
        if (st == .double_quotes) {
            if (c == '"') Cand.take(&best_len, &best, 27, self.spaces(i + 1) - i);
            Cand.take(&best_len, &best, 28, 1);
        }
        // 29: whitespace inside a value
        if (st == .section_value or st == .value or st == .offset or st == .var_fallback) {
            const e = self.spaces(i);
            if (e > i) Cand.take(&best_len, &best, 29, e - i);
        }
        // 30: whitespace skipped
        if (st == .initial or st == .raw) {
            const e = self.spaces(i);
            if (e > i) Cand.take(&best_len, &best, 30, e - i);
        }
        // 31: an empty line
        if (st == .initial) {
            const e = self.spaces(i);
            const nl = self.newline(e);
            if (nl > 0) Cand.take(&best_len, &best, 31, e + nl - i);
        }
        // 32: a comment to the end of the line
        if (st == .initial or st == .value or st == .raw) {
            const e = self.spaces(i);
            if (self.at(e) == ';') {
                var j = e + 1;
                while (self.inRange(j) and self.src[j] != '\r' and self.src[j] != '\n') j += 1;
                const nl = self.newline(j);
                if (nl > 0) Cand.take(&best_len, &best, 32, j + nl - i);
            }
        }
        // 33: anything else ends a value
        if (st == .value or st == .raw) Cand.take(&best_len, &best, 33, 1);
        // 34: anything else
        Cand.take(&best_len, &best, 34, 1);

        const text = self.src[i .. i + best_len];
        self.pos = i + best_len;
        switch (best) {
            1 => {
                self.state = if (self.mode == .raw) .section_raw else .section_value;
                return Tok.section;
            },
            2 => return try self.token(Tok.raw, text[1 .. text.len - 1], out),
            3 => {
                self.state = .initial;
                self.lineno += 1;
                return ']';
            },
            4 => {
                var t = trimLeading(text);
                while (t.len > 0 and (t[t.len - 1] == '[' or t[t.len - 1] == '\n' or t[t.len - 1] == '\r' or t[t.len - 1] == '\t' or t[t.len - 1] == ' ')) t = t[0 .. t.len - 1];
                self.state = .offset;
                return try self.token(Tok.offset, t, out);
            },
            5 => {
                self.state = .initial;
                return ']';
            },
            6 => {
                try self.push(.varname);
                return Tok.dollar_curly;
            },
            7 => {
                self.pop();
                try self.push(.var_fallback);
                return Tok.fallback;
            },
            8 => {
                // a name followed at once by ":-" is lost: the fallback is
                // what php returns
                if (self.at(self.pos) == ':' and self.at(self.pos + 1) == '-') {
                    self.pos += 1;
                    self.pop();
                    try self.push(.var_fallback);
                    return Tok.fallback;
                }
                while (self.pos < self.src.len) {
                    const ch = self.src[self.pos];
                    self.pos += 1;
                    const stop = switch (ch) {
                        '=', '\n', '\r', '\t', ';', '&', '|', '^', '$', '~', '(', ')', '{', '}', '!', '"', '[', ']' => true,
                        ':' => self.at(self.pos) == '-',
                        else => false,
                    };
                    if (stop) {
                        self.pos -= 1;
                        break;
                    }
                }
                return try self.token(Tok.varname, trimTrailing(trimLeading(self.src[i..self.pos])), out);
            },
            9 => {
                self.pop();
                return '}';
            },
            10 => return try self.token(Tok.bool_true, "1", out),
            11 => return try self.token(Tok.bool_false, "", out),
            12 => return try self.token(Tok.null_null, "", out),
            13 => return try self.token(Tok.label, trimTrailing(trimLeading(text)), out),
            14 => {
                self.state = if (self.mode == .raw) .raw else .value;
                return '=';
            },
            15 => {
                // a raw value: to the end of the line, a ";" outside quotes
                // starting a comment
                const lead = trimLeading(text);
                const begin = i + (text.len - lead.len);
                var sc: ?usize = null;
                while (self.pos < self.src.len) {
                    switch (self.src[self.pos]) {
                        '\n', '\r' => break,
                        ';' => {
                            if (sc == null) sc = self.pos;
                            self.pos += 1;
                        },
                        '"' => {
                            if (self.src[begin] == '"') sc = null;
                            self.pos += 1;
                        },
                        else => self.pos += 1,
                    }
                }
                var v = self.src[begin .. sc orelse self.pos];
                v = trimTrailing(v);
                if (v.len > 1 and v[0] == '"' and v[v.len - 1] == '"') v = v[1 .. v.len - 1];
                return try self.token(Tok.raw, v, out);
            },
            16 => return try self.token(Tok.raw, text, out),
            17 => {
                self.state = .initial;
                self.lineno += 1;
                return Tok.end_of_line;
            },
            18 => return try self.token(Tok.constant, text, out),
            19 => return try self.token(Tok.number, text, out),
            20 => return c,
            21 => return c,
            22 => {
                // yyless(0): the "=" is read again in INITIAL
                self.pos = i;
                self.state = .initial;
                return Tok.end_of_line;
            },
            23, 24, 25 => return try self.token(Tok.string, text, out),
            26 => {
                try self.push(.double_quotes);
                return '"';
            },
            27 => {
                self.pop();
                return '"';
            },
            28 => {
                var s = i;
                while (s < self.src.len) {
                    const ch = self.src[s];
                    s += 1;
                    switch (ch) {
                        '"' => {},
                        '$' => if (s < self.src.len and self.src[s] == '{') {} else continue,
                        '\\' => {
                            if (s < self.src.len) {
                                const escaped = self.src[s];
                                s += 1;
                                // a windows path like key="C:\path\"
                                if (escaped == '"' and (s >= self.src.len or self.src[s] == '\n' or self.src[s] == '\r')) {} else continue;
                            } else continue;
                        },
                        else => continue,
                    }
                    s -= 1;
                    break;
                }
                self.pos = s;
                out.* = .{ .s = try self.escape(self.src[i..s]) };
                return Tok.quoted_string;
            },
            29 => return try self.token(Tok.whitespace, text, out),
            30 => return null,
            31 => {
                self.lineno += 1;
                return Tok.end_of_line;
            },
            32 => {
                self.state = .initial;
                self.lineno += 1;
                return Tok.end_of_line;
            },
            33 => {
                self.state = .initial;
                return Tok.end_of_line;
            },
            else => return Tok.end,
        }
    }

    // zend_ini_escape_string for a double-quoted string
    fn escape(self: *Scanner, str: []const u8) ![]u8 {
        var out: std.ArrayListUnmanaged(u8) = .empty;
        var s: usize = 0;
        while (s < str.len) {
            if (str[s] == '\\') {
                s += 1;
                if (s >= str.len) {
                    try out.append(self.a, '\\');
                    continue;
                }
                switch (str[s]) {
                    '"', '\\', '$' => try out.append(self.a, str[s]),
                    else => {
                        try out.append(self.a, '\\');
                        try out.append(self.a, str[s]);
                    },
                }
            } else {
                try out.append(self.a, str[s]);
            }
            if (str[s] == '\n' or (str[s] == '\r' and (s + 1 >= str.len or str[s + 1] != '\n'))) self.lineno += 1;
            s += 1;
        }
        return out.toOwnedSlice(self.a);
    }
};

fn trimLeading(s: []const u8) []const u8 {
    return std.mem.trimStart(u8, s, " \t");
}

fn trimTrailing(s: []const u8) []const u8 {
    return std.mem.trimEnd(u8, s, " \t\n\r");
}

const Parser = struct {
    ctx: *NativeContext,
    a: std.mem.Allocator,
    mode: Mode,
    result: *PhpArray,
    sections: bool,
    active: ?*PhpArray = null,
    // get_browser's reader (php_browscap_parser_cb) instead of an array
    browscap: ?*@import("browscap.zig").Reader = null,

    fn str(self: *Parser, v: Val) ![]const u8 {
        return switch (v.kind) {
            .string => v.s,
            .boolean => if (v.b) "1" else "",
            .null => "",
            .long => try std.fmt.allocPrint(self.a, "{d}", .{v.l}),
            .double => (try self.ctx.vm.transientFormatted(.{ .float = v.d })).bytes(),
        };
    }

    // zend_ini_add_string: the result keeps the first operand's number mark
    fn concat(self: *Parser, op1: Val, op2: Val) !Val {
        const s1 = try self.str(op1);
        const s2 = try self.str(op2);
        const joined = try self.a.alloc(u8, s1.len + s2.len);
        @memcpy(joined[0..s1.len], s1);
        @memcpy(joined[s1.len..], s2);
        return .{ .s = joined, .number = op1.number };
    }

    fn intOf(v: Val) i32 {
        return switch (v.kind) {
            .long => @truncate(v.l),
            .double => if (std.math.isFinite(v.d) and @abs(v.d) < 2147483648.0) @intFromFloat(v.d) else 0,
            .string => atoi(v.s),
            .boolean => @intFromBool(v.b),
            .null => 0,
        };
    }

    fn atoi(s: []const u8) i32 {
        var i: usize = 0;
        while (i < s.len and (s[i] == ' ' or (s[i] >= '\t' and s[i] <= '\r'))) i += 1;
        var neg = false;
        if (i < s.len and (s[i] == '-' or s[i] == '+')) {
            neg = s[i] == '-';
            i += 1;
        }
        var n: i64 = 0;
        while (i < s.len and std.ascii.isDigit(s[i])) : (i += 1) n = n *% 10 +% (s[i] - '0');
        const r: i32 = @truncate(n);
        return if (neg) -%r else r;
    }

    // zend_ini_do_op
    fn op(self: *Parser, kind: u8, op1: Val, op2: ?Val) !Val {
        const a = intOf(op1);
        const b = if (op2) |o| intOf(o) else 0;
        const r: i32 = switch (kind) {
            '|' => a | b,
            '&' => a & b,
            '^' => a ^ b,
            '~' => ~a,
            '!' => @intFromBool(a == 0),
            else => 0,
        };
        if (self.mode == .typed) return .{ .kind = .long, .l = r, .number = op1.number };
        return .{ .s = try std.fmt.allocPrint(self.a, "{d}", .{r}), .number = op1.number };
    }

    // zend_ini_get_constant
    fn constant(self: *Parser, name: Val) !Val {
        if (std.mem.indexOfScalar(u8, name.s, ':') != null) return name;
        // zend_get_constant knows true, false and null in any case
        if (std.ascii.eqlIgnoreCase(name.s, "true")) return .{ .s = "1" };
        if (std.ascii.eqlIgnoreCase(name.s, "false") or std.ascii.eqlIgnoreCase(name.s, "null")) return .{};
        const c = self.ctx.vm.php_constants.get(name.s) orelse return name;
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        try c.format(&buf, self.a);
        return .{ .s = buf.items };
    }

    // zend_ini_get_var: a configuration directive, the environment, or the fallback
    fn variable(self: *Parser, name: Val, fallback: ?Val) !Val {
        if (@import("../ini_config.zig").get(name.s)) |v| return .{ .s = try self.a.dupe(u8, v) };
        if (platform.getenv(name.s)) |v| return .{ .s = try self.a.dupe(u8, v) };
        if (fallback) |f| return .{ .s = try self.str(f) };
        return .{};
    }

    // normalize_value: a typed value a number started becomes that number
    fn normalize(self: *Parser, v: Val) Val {
        if (self.mode != .typed or !v.number or v.kind != .string) return v;
        if (!Value.isNumericString(v.s)) return v;
        const t = std.mem.trim(u8, v.s, " \t\n\r\x0b\x0c");
        if (std.mem.indexOfAny(u8, t, ".eE") == null) {
            if (std.fmt.parseInt(i64, t, 10)) |n| return .{ .kind = .long, .l = n } else |_| return v;
        }
        const f = Value.toFloat(.{ .string = Value.String.borrowed(t) });
        if (std.math.isInf(f)) return v;
        return .{ .kind = .double, .d = f };
    }

    fn phpValue(self: *Parser, v: Val) !Value {
        return switch (v.kind) {
            .string => .{ .string = try Value.String.create(self.ctx.allocator, v.s) },
            .boolean => .{ .bool = v.b },
            .null => .null,
            .long => .{ .int = v.l },
            .double => .{ .float = v.d },
        };
    }

    fn keyOf(s: []const u8) PhpArray.Key {
        return PhpArray.normalizeKey(.{ .string = Value.String.borrowed(s) });
    }

    fn target(self: *Parser) *PhpArray {
        return self.active orelse self.result;
    }

    fn set(self: *Parser, arr: *PhpArray, key: PhpArray.Key, v: Value) !void {
        if (key == .string) {
            const owned = try Value.String.create(self.ctx.allocator, key.string.bytes());
            defer owned.release();
            try self.ctx.vm.arraySetOwned(arr, .{ .string = owned }, v);
        } else {
            try self.ctx.vm.arraySetOwned(arr, key, v);
        }
        if (v == .string) v.string.release();
    }

    // php_simple_ini_parser_cb and php_ini_parser_cb_with_sections
    fn section(self: *Parser, name: Val) !void {
        if (self.browscap) |reader| return reader.section(try self.str(name));
        if (!self.sections) return;
        const arr = try self.ctx.createArray();
        try self.set(self.result, keyOf(try self.str(name)), .{ .array = arr });
        self.active = arr;
    }

    fn entry(self: *Parser, name: Val, value: ?Val) !void {
        const v = value orelse return;
        if (self.browscap) |reader| return reader.entry(try self.str(name), try self.str(v));
        try self.set(self.target(), keyOf(name.s), try self.phpValue(v));
    }

    fn popEntry(self: *Parser, name: Val, value: ?Val, offset: ?Val) !void {
        const v = value orelse return;
        if (self.browscap != null) return;
        const arr = self.target();
        const key: PhpArray.Key = blk: {
            const s = name.s;
            if (!(s.len > 1 and s[0] == '0') and Value.isNumericString(s)) {
                const t = std.mem.trim(u8, s, " \t\n\r\x0b\x0c");
                if (std.mem.indexOfAny(u8, t, ".eE") == null) {
                    if (std.fmt.parseInt(i64, t, 10)) |n| break :blk .{ .int = n } else |_| {}
                }
            }
            break :blk .{ .string = Value.String.borrowed(s) };
        };
        const existing = arr.get(key);
        const hash = if (existing == .array) existing.array else blk: {
            const fresh = try self.ctx.createArray();
            try self.set(arr, key, .{ .array = fresh });
            break :blk fresh;
        };
        const pv = try self.phpValue(v);
        const off = offset orelse {
            try hash.append(self.ctx.allocator, pv);
            if (pv == .string) pv.string.release();
            return;
        };
        if (off.kind == .string and off.s.len == 0) {
            try hash.append(self.ctx.allocator, pv);
            if (pv == .string) pv.string.release();
            return;
        }
        // array_set_zval_key
        const okey: PhpArray.Key = switch (off.kind) {
            .string => keyOf(off.s),
            .long => .{ .int = off.l },
            .boolean => .{ .int = @intFromBool(off.b) },
            .null => .{ .string = Value.String.borrowed("") },
            .double => .{ .int = Value.toInt(.{ .float = off.d }) },
        };
        try self.set(hash, okey, pv);
    }

    // the semantic action of a rule (numbered as bison numbers them)
    fn action(self: *Parser, rule: usize, vs: []Val) !Val {
        const one = if (vs.len > 0) vs[0] else Val{};
        switch (rule) {
            4 => try self.section(vs[1]),
            5 => try self.entry(vs[0], vs[2]),
            6 => try self.popEntry(vs[0], vs[4], vs[1]),
            7 => try self.entry(vs[0], null),
            10, 15, 17, 20, 43 => return .{},
            11 => return self.normalize(vs[0]),
            23, 29 => return vs[1],
            18, 19, 24, 25, 30, 31 => return self.concat(vs[0], vs[1]),
            26, 32 => return self.concat(vs[0], vs[2]),
            34 => return self.op('|', vs[0], vs[2]),
            35 => return self.op('&', vs[0], vs[2]),
            36 => return self.op('^', vs[0], vs[2]),
            37 => return self.op('~', vs[1], null),
            38 => return self.op('!', vs[1], null),
            39 => return vs[1],
            40 => return self.variable(vs[1], null),
            41 => return self.variable(vs[1], vs[3]),
            49 => return self.constant(vs[0]),
            51 => {
                var v = vs[0];
                v.number = true;
                return v;
            },
            else => {},
        }
        return one;
    }
};

fn parse(ctx: *NativeContext, src: []const u8, filename: ?[]const u8, sections: bool, mode: Mode) RuntimeError!NativeResult {
    return parseInto(ctx, src, filename, sections, mode, null);
}

// zend_parse_ini_file in raw mode with browscap's callback
pub fn parseBrowscap(ctx: *NativeContext, src: []const u8, filename: []const u8, reader: *@import("browscap.zig").Reader) RuntimeError!void {
    const result = try parseInto(ctx, src, filename, true, .raw, reader);
    if (result.value == .array) ctx.vm.releaseUnheldArray(result.value.array);
}

fn parseInto(ctx: *NativeContext, src: []const u8, filename: ?[]const u8, sections: bool, mode: Mode, browscap: ?*@import("browscap.zig").Reader) RuntimeError!NativeResult {
    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var sc: Scanner = .{ .a = a, .src = src, .mode = mode };
    const result = try ctx.createArray();
    var parser: Parser = .{ .ctx = ctx, .a = a, .mode = mode, .result = result, .sections = sections, .browscap = browscap };

    var states: std.ArrayListUnmanaged(i32) = .empty;
    var values: std.ArrayListUnmanaged(Val) = .empty;
    try states.append(a, 0);
    try values.append(a, .{});
    var lookahead: ?i32 = null;
    var lval: Val = .{};
    while (true) {
        const state = states.items[states.items.len - 1];
        if (state == g.final) return NativeResult.borrowed(.{ .array = result });
        var rule: i32 = undefined;
        decide: {
            var n: i32 = g.pact[@intCast(state)];
            if (n == g.pact_ninf) break :decide;
            if (lookahead == null) {
                const tok = try sc.next(&lval);
                lookahead = if (tok <= g.maxutok) g.translate[tok] else 2;
            }
            n += lookahead.?;
            if (n < 0 or n > g.last or g.check[@intCast(n)] != lookahead.?) break :decide;
            n = g.table[@intCast(n)];
            if (n <= 0) {
                if (n == g.table_ninf) return syntaxError(ctx, &sc, filename, state, lookahead.?);
                rule = -n;
            } else {
                try states.append(a, n);
                try values.append(a, lval);
                lookahead = null;
                continue;
            }
            try reduce(&parser, &states, &values, rule);
            continue;
        }
        rule = g.defact[@intCast(state)];
        if (rule == 0) return syntaxError(ctx, &sc, filename, state, lookahead);
        try reduce(&parser, &states, &values, rule);
    }
}

fn reduce(parser: *Parser, states: *std.ArrayListUnmanaged(i32), values: *std.ArrayListUnmanaged(Val), rule: i32) RuntimeError!void {
    const len: usize = g.r2[@intCast(rule)];
    const rhs = values.items[values.items.len - len ..];
    const result = try parser.action(@intCast(rule), rhs);
    states.shrinkRetainingCapacity(states.items.len - len);
    values.shrinkRetainingCapacity(values.items.len - len);
    const top = states.items[states.items.len - 1];
    const lhs: usize = @intCast(g.r1[@intCast(rule)] - g.ntokens);
    const i = g.pgoto[lhs] + top;
    const next: i32 = if (i >= 0 and i <= g.last and g.check[@intCast(i)] == top) g.table[@intCast(i)] else g.defgoto[lhs];
    try states.append(parser.a, next);
    try values.append(parser.a, result);
}

// bison's verbose message through php's ini_error, as an E_WARNING
fn syntaxError(ctx: *NativeContext, sc: *const Scanner, filename: ?[]const u8, state: i32, lookahead: ?i32) RuntimeError!NativeResult {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    try buf.appendSlice(ctx.allocator, "syntax error");
    var expected: [4]usize = undefined;
    var count: usize = 0;
    const n: i32 = g.pact[@intCast(state)];
    if (lookahead) |symbol| {
        try buf.appendSlice(ctx.allocator, ", unexpected ");
        try appendName(&buf, ctx.allocator, g.tname[@intCast(symbol)]);
    }
    if (lookahead != null and n != g.pact_ninf) {
        const begin: i32 = if (n < 0) -n else 0;
        const end: i32 = @min(g.last - n + 1, g.ntokens);
        var x = begin;
        while (x < end) : (x += 1) {
            const i: usize = @intCast(x + n);
            if (g.check[i] != x or x == 1 or g.table[i] == g.table_ninf) continue;
            if (count == 4) {
                count = 0;
                break;
            }
            expected[count] = @intCast(x);
            count += 1;
        }
    }
    for (expected[0..count], 0..) |sym, k| {
        try buf.appendSlice(ctx.allocator, if (k == 0) ", expecting " else " or ");
        try appendName(&buf, ctx.allocator, g.tname[sym]);
    }
    try buf.print(ctx.allocator, " in {s} on line {d}\n", .{ filename orelse "Unknown", sc.lineno });
    try ctx.vm.emitWarning(buf.items);
    return NativeResult.scalar(.{ .bool = false });
}

// yytnamerr: a quoted name without its quotes
fn appendName(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, name: []const u8) !void {
    if (name.len >= 2 and name[0] == '"') return buf.appendSlice(a, name[1 .. name.len - 1]);
    try buf.appendSlice(a, name);
}
