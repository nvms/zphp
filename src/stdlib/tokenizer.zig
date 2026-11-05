// php's tokenizer extension: token_get_all, token_name and PhpToken. the
// lexer follows zend_language_scanner.l state for state, since tools such as
// php-parser, php-cs-fixer and nette read php source through it and depend on
// its exact token boundaries, ids and line numbers
const std = @import("std");
const t = @import("tokens_generated.zig");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const ClassDef = vm_mod.ClassDef;
const NativeContext = vm_mod.NativeContext;
const RuntimeError = vm_mod.RuntimeError;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const Allocator = std.mem.Allocator;

pub const TOKEN_PARSE: i64 = 1;

// a single-character token carries its byte as the id, like php
pub const Token = struct {
    id: i64,
    text: []const u8,
    line: u32,
    pos: u32,

    pub fn isChar(self: Token) bool {
        return self.id < 256;
    }
};

const State = union(enum) {
    initial,
    scripting,
    looking_for_property,
    double_quotes,
    backquote,
    heredoc: Heredoc,
    end_heredoc: Heredoc,
    looking_for_varname,
    var_offset,
};

const Heredoc = struct { label: []const u8, nowdoc: bool };

const Lexer = struct {
    src: []const u8,
    pos: usize = 0,
    line: u32 = 1,
    allocator: Allocator,
    tokens: std.ArrayListUnmanaged(Token) = .empty,
    states: std.ArrayListUnmanaged(State) = .empty,
    short_open_tag: bool,

    fn state(self: *Lexer) State {
        return self.states.items[self.states.items.len - 1];
    }

    fn begin(self: *Lexer, s: State) void {
        self.states.items[self.states.items.len - 1] = s;
    }

    fn push(self: *Lexer, s: State) !void {
        try self.states.append(self.allocator, s);
    }

    fn pop(self: *Lexer) void {
        if (self.states.items.len > 1) _ = self.states.pop();
    }

    fn emit(self: *Lexer, id: i64, len: usize) !void {
        const text = self.src[self.pos .. self.pos + len];
        try self.tokens.append(self.allocator, .{ .id = id, .text = text, .line = self.line, .pos = @intCast(self.pos) });
        self.line += @intCast(std.mem.count(u8, text, "\n") + countLoneCr(text));
        self.pos += len;
    }

    fn rest(self: *Lexer) []const u8 {
        return self.src[self.pos..];
    }

    fn at(self: *Lexer, offset: usize) u8 {
        const i = self.pos + offset;
        return if (i < self.src.len) self.src[i] else 0;
    }

    fn run(self: *Lexer) !void {
        try self.push(.initial);
        while (self.pos < self.src.len) {
            switch (self.state()) {
                .initial => try self.initial(),
                .scripting => try self.scripting(),
                .looking_for_property => try self.lookingForProperty(),
                .double_quotes => try self.interpolated('"'),
                .backquote => try self.interpolated('`'),
                .heredoc => |h| try self.heredocBody(h),
                .end_heredoc => |h| try self.endHeredoc(h),
                .looking_for_varname => try self.lookingForVarname(),
                .var_offset => try self.varOffset(),
            }
        }
    }

    fn initial(self: *Lexer) !void {
        const r = self.rest();
        if (std.mem.startsWith(u8, r, "<?=")) {
            try self.emit(t.T_OPEN_TAG_WITH_ECHO, 3);
            self.begin(.scripting);
            return;
        }
        if (r.len >= 5 and std.ascii.eqlIgnoreCase(r[0..5], "<?php")) {
            if (r.len == 5) {
                try self.emit(t.T_OPEN_TAG, 5);
                self.begin(.scripting);
                return;
            }
            const ws = newlineOrBlankLen(r[5..]);
            if (ws > 0) {
                try self.emit(t.T_OPEN_TAG, 5 + ws);
                self.begin(.scripting);
                return;
            }
        }
        if (self.short_open_tag and std.mem.startsWith(u8, r, "<?")) {
            try self.emit(t.T_OPEN_TAG, 2);
            self.begin(.scripting);
            return;
        }
        var len: usize = 1;
        while (len < r.len) : (len += 1) {
            if (r[len] == '<' and len + 1 < r.len and r[len + 1] == '?' and self.opensTag(r[len..])) break;
        }
        try self.emit(t.T_INLINE_HTML, len);
    }

    fn opensTag(self: *Lexer, r: []const u8) bool {
        if (std.mem.startsWith(u8, r, "<?=")) return true;
        if (r.len >= 5 and std.ascii.eqlIgnoreCase(r[0..5], "<?php") and (r.len == 5 or newlineOrBlankLen(r[5..]) > 0)) return true;
        return self.short_open_tag;
    }

    fn scripting(self: *Lexer) !void {
        const r = self.rest();
        const c = r[0];

        if (isWhitespace(c)) return self.emit(t.T_WHITESPACE, spanWhile(r, isWhitespace));
        if (c == '?' and r.len > 1 and r[1] == '>') {
            const nl = newlineLen(r[2..]);
            try self.emit(t.T_CLOSE_TAG, 2 + nl);
            self.begin(.initial);
            return;
        }
        if (c == '#' and r.len > 1 and r[1] == '[') return self.emit(t.T_ATTRIBUTE, 2);
        if (c == '#' or (c == '/' and r.len > 1 and r[1] == '/')) return self.emit(t.T_COMMENT, lineCommentLen(r));
        if (c == '/' and r.len > 1 and r[1] == '*') {
            const doc = r.len > 3 and r[2] == '*' and isWhitespace(r[3]);
            const end = if (std.mem.indexOf(u8, r[2..], "*/")) |i| i + 4 else r.len;
            return self.emit(if (doc) t.T_DOC_COMMENT else t.T_COMMENT, end);
        }
        if (c == '$' and r.len > 1 and isLabelStart(r[1])) return self.emit(t.T_VARIABLE, 1 + labelLen(r[1..]));
        if (c == '\'' or ((c == 'b' or c == 'B') and r.len > 1 and r[1] == '\'')) return self.singleQuoted();
        if (c == '"' or ((c == 'b' or c == 'B') and r.len > 1 and r[1] == '"')) return self.doubleQuoted();
        if (c == '`') {
            try self.emit('`', 1);
            self.begin(.backquote);
            return;
        }
        if (try self.heredocStart()) return;
        if (isDigit(c) or (c == '.' and r.len > 1 and isDigit(r[1]))) return self.number();
        if (c == '\\' and r.len > 1 and isLabelStart(r[1])) return self.emit(t.T_NAME_FULLY_QUALIFIED, 1 + qualifiedLen(r[1..]));
        if (c == '\\') return self.emit(t.T_NS_SEPARATOR, 1);
        if (isLabelStart(c)) return self.word();
        if (c == '(') if (castAt(r)) |cast| return self.emit(cast.id, cast.len);
        if (c == '{') {
            try self.push(.scripting);
            return self.emit('{', 1);
        }
        if (c == '}') {
            try self.emit('}', 1);
            self.pop();
            return;
        }
        if (operatorAt(r)) |op| {
            try self.emit(op.id, op.len);
            if (op.id == t.T_OBJECT_OPERATOR or op.id == t.T_NULLSAFE_OBJECT_OPERATOR) try self.push(.looking_for_property);
            return;
        }
        if (c == '&') return self.emit(if (ampersandFollowedByVar(r[1..])) t.T_AMPERSAND_FOLLOWED_BY_VAR_OR_VARARG else t.T_AMPERSAND_NOT_FOLLOWED_BY_VAR_OR_VARARG, 1);
        if (std.mem.indexOfScalar(u8, ";:,.[]()|^+-/*=%!~$<>?@", c) != null) return self.emit(c, 1);
        try self.emit(t.T_BAD_CHARACTER, 1);
    }

    fn word(self: *Lexer) !void {
        const r = self.rest();
        const len = labelLen(r);
        const lbl = r[0..len];
        if (len < r.len and r[len] == '\\' and len + 1 < r.len and isLabelStart(r[len + 1])) {
            const qlen = qualifiedLen(r);
            return self.emit(if (std.ascii.eqlIgnoreCase(lbl, "namespace")) t.T_NAME_RELATIVE else t.T_NAME_QUALIFIED, qlen);
        }
        if (std.ascii.eqlIgnoreCase(lbl, "yield")) {
            const gap = whitespaceOrCommentsLen(r[len..]);
            if (gap > 0 and r.len >= len + gap + 4 and std.ascii.eqlIgnoreCase(r[len + gap .. len + gap + 4], "from") and !(len + gap + 4 < r.len and isLabelChar(r[len + gap + 4]))) {
                return self.emit(t.T_YIELD_FROM, len + gap + 4);
            }
        }
        if (std.ascii.eqlIgnoreCase(lbl, "enum")) {
            const gap = whitespaceOrCommentsLen(r[len..]);
            if (gap > 0 and len + gap < r.len and isLabelStart(r[len + gap])) {
                const next = r[len + gap .. len + gap + labelLen(r[len + gap ..])];
                const inheritance = std.ascii.eqlIgnoreCase(next, "extends") or std.ascii.eqlIgnoreCase(next, "implements");
                return self.emit(if (inheritance) t.T_STRING else t.T_ENUM, len);
            }
            return self.emit(t.T_STRING, len);
        }
        if (len + 5 <= r.len and std.ascii.eqlIgnoreCase(r[len .. len + 5], "(set)")) {
            if (std.ascii.eqlIgnoreCase(lbl, "public")) return self.emit(t.T_PUBLIC_SET, len + 5);
            if (std.ascii.eqlIgnoreCase(lbl, "protected")) return self.emit(t.T_PROTECTED_SET, len + 5);
            if (std.ascii.eqlIgnoreCase(lbl, "private")) return self.emit(t.T_PRIVATE_SET, len + 5);
        }
        try self.emit(keywordId(lbl) orelse t.T_STRING, len);
    }

    fn singleQuoted(self: *Lexer) !void {
        const r = self.rest();
        var i: usize = if (r[0] == '\'') 1 else 2;
        while (i < r.len) : (i += 1) {
            if (r[i] == '\\' and i + 1 < r.len) {
                i += 1;
                continue;
            }
            if (r[i] == '\'') return self.emit(t.T_CONSTANT_ENCAPSED_STRING, i + 1);
        }
        try self.emit(t.T_ENCAPSED_AND_WHITESPACE, r.len);
    }

    fn doubleQuoted(self: *Lexer) !void {
        const r = self.rest();
        const open: usize = if (r[0] == '"') 1 else 2;
        const scan = interpolationScan(r[open..], '"');
        if (scan.closed) return self.emit(t.T_CONSTANT_ENCAPSED_STRING, open + scan.len + 1);
        try self.emit('"', open);
        self.begin(.double_quotes);
    }

    fn heredocStart(self: *Lexer) !bool {
        const r = self.rest();
        var i: usize = 0;
        if (r.len > 0 and (r[0] == 'b' or r[0] == 'B')) i = 1;
        if (!std.mem.startsWith(u8, r[i..], "<<<")) return false;
        i += 3;
        while (i < r.len and (r[i] == ' ' or r[i] == '\t')) i += 1;
        var quote: u8 = 0;
        if (i < r.len and (r[i] == '\'' or r[i] == '"')) {
            quote = r[i];
            i += 1;
        }
        if (i >= r.len or !isLabelStart(r[i])) return false;
        const label_start = i;
        i += labelLen(r[i..]);
        const label = r[label_start..i];
        if (quote != 0) {
            if (i >= r.len or r[i] != quote) return false;
            i += 1;
        }
        const nl = newlineLen(r[i..]);
        if (nl == 0) return false;
        const doc: Heredoc = .{ .label = label, .nowdoc = quote == '\'' };
        try self.emit(t.T_START_HEREDOC, i + nl);
        self.begin(if (endMarkerLen(self.rest(), label) != null) .{ .end_heredoc = doc } else .{ .heredoc = doc });
        return true;
    }

    fn heredocBody(self: *Lexer, doc: Heredoc) !void {
        const r = self.rest();
        if (!doc.nowdoc) {
            if (try self.interpolationStart(r)) return;
        }
        var i: usize = 0;
        while (i < r.len) {
            const c = r[i];
            if (!doc.nowdoc) {
                if (c == '\\' and i + 1 < r.len) {
                    i += 2;
                    continue;
                }
                if (i > 0 and startsInterpolation(r[i..])) break;
            }
            i += 1;
            if (c == '\n' or (c == '\r' and (i >= r.len or r[i] != '\n'))) {
                if (endMarkerLen(r[i..], doc.label) != null) {
                    try self.emit(t.T_ENCAPSED_AND_WHITESPACE, i);
                    self.begin(.{ .end_heredoc = doc });
                    return;
                }
            }
        }
        try self.emit(t.T_ENCAPSED_AND_WHITESPACE, i);
    }

    fn endHeredoc(self: *Lexer, doc: Heredoc) !void {
        const len = endMarkerLen(self.rest(), doc.label) orelse self.rest().len;
        try self.emit(t.T_END_HEREDOC, len);
        self.begin(.scripting);
    }

    // $var, $var[, $var->prop, {$ and ${ inside an interpolated string
    fn interpolationStart(self: *Lexer, r: []const u8) !bool {
        if (std.mem.startsWith(u8, r, "{$")) {
            try self.emit(t.T_CURLY_OPEN, 1);
            try self.push(.scripting);
            return true;
        }
        if (std.mem.startsWith(u8, r, "${")) {
            try self.emit(t.T_DOLLAR_OPEN_CURLY_BRACES, 2);
            try self.push(.looking_for_varname);
            return true;
        }
        if (r.len > 1 and r[0] == '$' and isLabelStart(r[1])) {
            const len = 1 + labelLen(r[1..]);
            const after = r[len..];
            try self.emit(t.T_VARIABLE, len);
            if (after.len > 0 and after[0] == '[') {
                try self.push(.var_offset);
            } else if ((std.mem.startsWith(u8, after, "->") and after.len > 2 and isLabelStart(after[2])) or
                (std.mem.startsWith(u8, after, "?->") and after.len > 3 and isLabelStart(after[3])))
            {
                try self.push(.looking_for_property);
            }
            return true;
        }
        return false;
    }

    fn interpolated(self: *Lexer, close: u8) !void {
        const r = self.rest();
        if (r[0] == close) {
            try self.emit(close, 1);
            self.begin(.scripting);
            return;
        }
        if (try self.interpolationStart(r)) return;
        const scan = interpolationScan(r, close);
        try self.emit(t.T_ENCAPSED_AND_WHITESPACE, @max(scan.len, 1));
    }

    fn lookingForProperty(self: *Lexer) !void {
        const r = self.rest();
        if (isWhitespace(r[0])) return self.emit(t.T_WHITESPACE, spanWhile(r, isWhitespace));
        if (std.mem.startsWith(u8, r, "->")) return self.emit(t.T_OBJECT_OPERATOR, 2);
        if (std.mem.startsWith(u8, r, "?->")) return self.emit(t.T_NULLSAFE_OBJECT_OPERATOR, 3);
        if (isLabelStart(r[0])) {
            try self.emit(t.T_STRING, labelLen(r));
            self.pop();
            return;
        }
        self.pop();
    }

    fn lookingForVarname(self: *Lexer) !void {
        const r = self.rest();
        self.pop();
        try self.push(.scripting);
        if (isLabelStart(r[0])) {
            const len = labelLen(r);
            if (len < r.len and (r[len] == '[' or r[len] == '}')) try self.emit(t.T_STRING_VARNAME, len);
        }
    }

    fn varOffset(self: *Lexer) !void {
        const r = self.rest();
        const c = r[0];
        if (c == ']') {
            try self.emit(']', 1);
            self.pop();
            return;
        }
        if (isDigit(c)) return self.emit(t.T_NUM_STRING, numberSpan(r).len);
        if (c == '$' and r.len > 1 and isLabelStart(r[1])) return self.emit(t.T_VARIABLE, 1 + labelLen(r[1..]));
        if (isLabelStart(c)) return self.emit(t.T_STRING, labelLen(r));
        if (std.mem.indexOfScalar(u8, " \n\r\t\\'#", c) != null) {
            self.pop();
            return self.emit(t.T_ENCAPSED_AND_WHITESPACE, 1);
        }
        if (std.mem.indexOfScalar(u8, ";:,.|^&+-/*=%!~$<>?@[(){}\"`", c) != null) return self.emit(c, 1);
        try self.emit(t.T_BAD_CHARACTER, 1);
    }

    fn number(self: *Lexer) !void {
        const span = numberSpan(self.rest());
        try self.emit(if (span.float) t.T_DNUMBER else t.T_LNUMBER, span.len);
    }
};

const NumberSpan = struct { len: usize, float: bool };

// LNUM, DNUM, EXPONENT_DNUM, HNUM, BNUM and ONUM with php's `_` separators; an
// integer literal too large for int is a float token
fn numberSpan(r: []const u8) NumberSpan {
    if (r.len > 2 and r[0] == '0') {
        const radix: ?u8 = switch (r[1]) {
            'x', 'X' => 16,
            'b', 'B' => 2,
            'o', 'O' => 8,
            else => null,
        };
        if (radix) |base| {
            const digits = digitRun(r[2..], base);
            if (digits > 0) return .{ .len = 2 + digits, .float = !fitsInt(r[2 .. 2 + digits], base) };
        }
    }
    var i = digitRun(r, 10);
    var float = false;
    if (i < r.len and r[i] == '.' and (i > 0 or (i + 1 < r.len and isDigit(r[i + 1])))) {
        float = true;
        i += 1;
        i += digitRun(r[i..], 10);
    }
    if (i < r.len and (r[i] == 'e' or r[i] == 'E')) {
        var j = i + 1;
        if (j < r.len and (r[j] == '+' or r[j] == '-')) j += 1;
        const exp = digitRun(r[j..], 10);
        if (exp > 0) return .{ .len = j + exp, .float = true };
    }
    if (float) return .{ .len = i, .float = true };
    const octal = i > 1 and r[0] == '0';
    return .{ .len = i, .float = !fitsInt(r[0..i], if (octal) 8 else 10) };
}

fn digitRun(r: []const u8, base: u8) usize {
    var i: usize = 0;
    while (i < r.len and digitValue(r[i]) < base) {
        i += 1;
        if (i + 1 < r.len and r[i] == '_' and digitValue(r[i + 1]) < base) i += 1;
    }
    return i;
}

fn digitValue(c: u8) u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => 255,
    };
}

fn fitsInt(digits: []const u8, base: u8) bool {
    var v: u64 = 0;
    for (digits) |c| {
        if (c == '_') continue;
        const d = digitValue(c);
        if (d >= base) continue;
        const mul = @mulWithOverflow(v, base);
        if (mul[1] != 0) return false;
        const add = @addWithOverflow(mul[0], d);
        if (add[1] != 0) return false;
        v = add[0];
    }
    return v <= std.math.maxInt(i64);
}

const Scan = struct { len: usize, closed: bool };

// the literal run of an interpolated string, stopping at the closing quote or
// where a variable, {$ or ${ begins
fn interpolationScan(r: []const u8, close: u8) Scan {
    var i: usize = 0;
    while (i < r.len) {
        const c = r[i];
        if (c == close) return .{ .len = i, .closed = true };
        if (c == '\\' and i + 1 < r.len) {
            i += 2;
            continue;
        }
        if (startsInterpolation(r[i..])) return .{ .len = i, .closed = false };
        i += 1;
    }
    return .{ .len = i, .closed = false };
}

fn startsInterpolation(r: []const u8) bool {
    if (r.len < 2) return false;
    if (r[0] == '$') return isLabelStart(r[1]) or r[1] == '{';
    return r[0] == '{' and r[1] == '$';
}

// the closing line of a heredoc: indentation, the label, and no label char after
fn endMarkerLen(r: []const u8, label: []const u8) ?usize {
    var i: usize = 0;
    while (i < r.len and (r[i] == ' ' or r[i] == '\t')) i += 1;
    if (!std.mem.startsWith(u8, r[i..], label)) return null;
    const end = i + label.len;
    if (end < r.len and isLabelChar(r[end])) return null;
    return end;
}

const Operator = struct { text: []const u8, id: i64 };

const operators = [_]Operator{
    .{ .text = "<<=", .id = t.T_SL_EQUAL },
    .{ .text = ">>=", .id = t.T_SR_EQUAL },
    .{ .text = "**=", .id = t.T_POW_EQUAL },
    .{ .text = "...", .id = t.T_ELLIPSIS },
    .{ .text = "??=", .id = t.T_COALESCE_EQUAL },
    .{ .text = "===", .id = t.T_IS_IDENTICAL },
    .{ .text = "!==", .id = t.T_IS_NOT_IDENTICAL },
    .{ .text = "<=>", .id = t.T_SPACESHIP },
    .{ .text = "?->", .id = t.T_NULLSAFE_OBJECT_OPERATOR },
    .{ .text = "==", .id = t.T_IS_EQUAL },
    .{ .text = "!=", .id = t.T_IS_NOT_EQUAL },
    .{ .text = "<>", .id = t.T_IS_NOT_EQUAL },
    .{ .text = "<=", .id = t.T_IS_SMALLER_OR_EQUAL },
    .{ .text = ">=", .id = t.T_IS_GREATER_OR_EQUAL },
    .{ .text = "+=", .id = t.T_PLUS_EQUAL },
    .{ .text = "-=", .id = t.T_MINUS_EQUAL },
    .{ .text = "*=", .id = t.T_MUL_EQUAL },
    .{ .text = "/=", .id = t.T_DIV_EQUAL },
    .{ .text = ".=", .id = t.T_CONCAT_EQUAL },
    .{ .text = "%=", .id = t.T_MOD_EQUAL },
    .{ .text = "&=", .id = t.T_AND_EQUAL },
    .{ .text = "|=", .id = t.T_OR_EQUAL },
    .{ .text = "^=", .id = t.T_XOR_EQUAL },
    .{ .text = "||", .id = t.T_BOOLEAN_OR },
    .{ .text = "&&", .id = t.T_BOOLEAN_AND },
    .{ .text = "<<", .id = t.T_SL },
    .{ .text = ">>", .id = t.T_SR },
    .{ .text = "**", .id = t.T_POW },
    .{ .text = "++", .id = t.T_INC },
    .{ .text = "--", .id = t.T_DEC },
    .{ .text = "->", .id = t.T_OBJECT_OPERATOR },
    .{ .text = "=>", .id = t.T_DOUBLE_ARROW },
    .{ .text = "::", .id = t.T_DOUBLE_COLON },
    .{ .text = "??", .id = t.T_COALESCE },
    .{ .text = "|>", .id = t.T_PIPE },
};

fn operatorAt(r: []const u8) ?struct { id: i64, len: usize } {
    for (operators) |op| {
        if (std.mem.startsWith(u8, r, op.text)) return .{ .id = op.id, .len = op.text.len };
    }
    return null;
}

const Cast = struct { name: []const u8, id: i64 };

const casts = [_]Cast{
    .{ .name = "int", .id = t.T_INT_CAST },
    .{ .name = "integer", .id = t.T_INT_CAST },
    .{ .name = "bool", .id = t.T_BOOL_CAST },
    .{ .name = "boolean", .id = t.T_BOOL_CAST },
    .{ .name = "float", .id = t.T_DOUBLE_CAST },
    .{ .name = "double", .id = t.T_DOUBLE_CAST },
    .{ .name = "real", .id = t.T_DOUBLE_CAST },
    .{ .name = "string", .id = t.T_STRING_CAST },
    .{ .name = "binary", .id = t.T_STRING_CAST },
    .{ .name = "array", .id = t.T_ARRAY_CAST },
    .{ .name = "object", .id = t.T_OBJECT_CAST },
    .{ .name = "unset", .id = t.T_UNSET_CAST },
    .{ .name = "void", .id = t.T_VOID_CAST },
};

fn castAt(r: []const u8) ?struct { id: i64, len: usize } {
    var i: usize = 1;
    while (i < r.len and (r[i] == ' ' or r[i] == '\t')) i += 1;
    const start = i;
    while (i < r.len and std.ascii.isAlphabetic(r[i])) i += 1;
    const name = r[start..i];
    while (i < r.len and (r[i] == ' ' or r[i] == '\t')) i += 1;
    if (i >= r.len or r[i] != ')') return null;
    for (casts) |cast| {
        if (std.ascii.eqlIgnoreCase(name, cast.name)) return .{ .id = cast.id, .len = i + 1 };
    }
    return null;
}

const Keyword = struct { text: []const u8, id: i64 };

const keywords = [_]Keyword{
    .{ .text = "abstract", .id = t.T_ABSTRACT },         .{ .text = "and", .id = t.T_LOGICAL_AND },
    .{ .text = "array", .id = t.T_ARRAY },               .{ .text = "as", .id = t.T_AS },
    .{ .text = "break", .id = t.T_BREAK },               .{ .text = "callable", .id = t.T_CALLABLE },
    .{ .text = "case", .id = t.T_CASE },                 .{ .text = "catch", .id = t.T_CATCH },
    .{ .text = "class", .id = t.T_CLASS },               .{ .text = "clone", .id = t.T_CLONE },
    .{ .text = "const", .id = t.T_CONST },               .{ .text = "continue", .id = t.T_CONTINUE },
    .{ .text = "declare", .id = t.T_DECLARE },           .{ .text = "default", .id = t.T_DEFAULT },
    .{ .text = "die", .id = t.T_EXIT },                  .{ .text = "do", .id = t.T_DO },
    .{ .text = "echo", .id = t.T_ECHO },                 .{ .text = "else", .id = t.T_ELSE },
    .{ .text = "elseif", .id = t.T_ELSEIF },             .{ .text = "empty", .id = t.T_EMPTY },
    .{ .text = "enddeclare", .id = t.T_ENDDECLARE },     .{ .text = "endfor", .id = t.T_ENDFOR },
    .{ .text = "endforeach", .id = t.T_ENDFOREACH },     .{ .text = "endif", .id = t.T_ENDIF },
    .{ .text = "endswitch", .id = t.T_ENDSWITCH },       .{ .text = "endwhile", .id = t.T_ENDWHILE },
    .{ .text = "eval", .id = t.T_EVAL },                 .{ .text = "exit", .id = t.T_EXIT },
    .{ .text = "extends", .id = t.T_EXTENDS },           .{ .text = "final", .id = t.T_FINAL },
    .{ .text = "finally", .id = t.T_FINALLY },           .{ .text = "fn", .id = t.T_FN },
    .{ .text = "for", .id = t.T_FOR },                   .{ .text = "foreach", .id = t.T_FOREACH },
    .{ .text = "function", .id = t.T_FUNCTION },         .{ .text = "global", .id = t.T_GLOBAL },
    .{ .text = "goto", .id = t.T_GOTO },                 .{ .text = "if", .id = t.T_IF },
    .{ .text = "implements", .id = t.T_IMPLEMENTS },     .{ .text = "include", .id = t.T_INCLUDE },
    .{ .text = "include_once", .id = t.T_INCLUDE_ONCE }, .{ .text = "instanceof", .id = t.T_INSTANCEOF },
    .{ .text = "insteadof", .id = t.T_INSTEADOF },       .{ .text = "interface", .id = t.T_INTERFACE },
    .{ .text = "isset", .id = t.T_ISSET },               .{ .text = "list", .id = t.T_LIST },
    .{ .text = "match", .id = t.T_MATCH },               .{ .text = "namespace", .id = t.T_NAMESPACE },
    .{ .text = "new", .id = t.T_NEW },                   .{ .text = "or", .id = t.T_LOGICAL_OR },
    .{ .text = "print", .id = t.T_PRINT },               .{ .text = "private", .id = t.T_PRIVATE },
    .{ .text = "protected", .id = t.T_PROTECTED },       .{ .text = "public", .id = t.T_PUBLIC },
    .{ .text = "readonly", .id = t.T_READONLY },         .{ .text = "require", .id = t.T_REQUIRE },
    .{ .text = "require_once", .id = t.T_REQUIRE_ONCE }, .{ .text = "return", .id = t.T_RETURN },
    .{ .text = "static", .id = t.T_STATIC },             .{ .text = "switch", .id = t.T_SWITCH },
    .{ .text = "throw", .id = t.T_THROW },               .{ .text = "trait", .id = t.T_TRAIT },
    .{ .text = "try", .id = t.T_TRY },                   .{ .text = "unset", .id = t.T_UNSET },
    .{ .text = "use", .id = t.T_USE },                   .{ .text = "var", .id = t.T_VAR },
    .{ .text = "while", .id = t.T_WHILE },               .{ .text = "xor", .id = t.T_LOGICAL_XOR },
    .{ .text = "yield", .id = t.T_YIELD },               .{ .text = "__halt_compiler", .id = t.T_HALT_COMPILER },
    .{ .text = "__class__", .id = t.T_CLASS_C },         .{ .text = "__trait__", .id = t.T_TRAIT_C },
    .{ .text = "__function__", .id = t.T_FUNC_C },       .{ .text = "__method__", .id = t.T_METHOD_C },
    .{ .text = "__line__", .id = t.T_LINE },             .{ .text = "__file__", .id = t.T_FILE },
    .{ .text = "__dir__", .id = t.T_DIR },               .{ .text = "__namespace__", .id = t.T_NS_C },
    .{ .text = "__property__", .id = t.T_PROPERTY_C },
};

fn keywordId(word: []const u8) ?i64 {
    for (keywords) |kw| {
        if (std.ascii.eqlIgnoreCase(word, kw.text)) return kw.id;
    }
    return null;
}

fn isKeywordId(id: i64) bool {
    for (keywords) |kw| {
        if (kw.id == id) return true;
    }
    return false;
}

fn isLabelStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_' or c >= 0x80;
}

fn isLabelChar(c: u8) bool {
    return isLabelStart(c) or isDigit(c);
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

fn spanWhile(r: []const u8, comptime pred: fn (u8) bool) usize {
    var i: usize = 0;
    while (i < r.len and pred(r[i])) i += 1;
    return i;
}

fn labelLen(r: []const u8) usize {
    return spanWhile(r, isLabelChar);
}

// LABEL ("\" LABEL)*
fn qualifiedLen(r: []const u8) usize {
    var i = labelLen(r);
    while (i + 1 < r.len and r[i] == '\\' and isLabelStart(r[i + 1])) i += 1 + labelLen(r[i + 1 ..]);
    return i;
}

fn newlineLen(r: []const u8) usize {
    if (std.mem.startsWith(u8, r, "\r\n")) return 2;
    if (r.len > 0 and (r[0] == '\n' or r[0] == '\r')) return 1;
    return 0;
}

fn newlineOrBlankLen(r: []const u8) usize {
    if (r.len > 0 and (r[0] == ' ' or r[0] == '\t')) return 1;
    return newlineLen(r);
}

fn countLoneCr(text: []const u8) usize {
    var n: usize = 0;
    for (text, 0..) |c, i| {
        if (c == '\r' and (i + 1 >= text.len or text[i + 1] != '\n')) n += 1;
    }
    return n;
}

// a # or // comment ends before the newline or a closing tag
fn lineCommentLen(r: []const u8) usize {
    var i: usize = 0;
    while (i < r.len) : (i += 1) {
        if (r[i] == '\n' or r[i] == '\r') break;
        if (r[i] == '?' and i + 1 < r.len and r[i + 1] == '>') break;
    }
    return i;
}

fn whitespaceOrCommentsLen(r: []const u8) usize {
    var i: usize = 0;
    while (i < r.len) {
        if (isWhitespace(r[i])) {
            i += 1;
        } else if (r[i] == '#' and !(i + 1 < r.len and r[i + 1] == '[') or std.mem.startsWith(u8, r[i..], "//")) {
            i += lineCommentLen(r[i..]);
        } else if (std.mem.startsWith(u8, r[i..], "/*")) {
            i += if (std.mem.indexOf(u8, r[i + 2 ..], "*/")) |e| e + 4 else r.len - i;
        } else break;
    }
    return i;
}

fn ampersandFollowedByVar(r: []const u8) bool {
    const gap = whitespaceOrCommentsLen(r);
    const next = r[gap..];
    return (next.len > 1 and next[0] == '$' and isLabelStart(next[1])) or std.mem.startsWith(u8, next, "...");
}

pub fn tokenize(allocator: Allocator, src: []const u8, short_open_tag: bool) ![]Token {
    var lexer = Lexer{ .src = src, .allocator = allocator, .short_open_tag = short_open_tag };
    defer lexer.states.deinit(allocator);
    errdefer lexer.tokens.deinit(allocator);
    try lexer.run();
    try haltCompiler(allocator, &lexer.tokens, src);
    return lexer.tokens.toOwnedSlice(allocator);
}

// after __halt_compiler and its `();` everything is raw data
fn haltCompiler(allocator: Allocator, tokens: *std.ArrayListUnmanaged(Token), src: []const u8) !void {
    for (tokens.items, 0..) |tok, i| {
        if (tok.id != t.T_HALT_COMPILER) continue;
        var needed: usize = 3;
        var j = i + 1;
        while (j < tokens.items.len and needed > 0) : (j += 1) {
            const id = tokens.items[j].id;
            if (id != t.T_WHITESPACE and id != t.T_COMMENT and id != t.T_DOC_COMMENT) needed -= 1;
        }
        if (j >= tokens.items.len) return;
        const start = tokens.items[j].pos;
        const line = tokens.items[j].line;
        tokens.shrinkRetainingCapacity(j);
        try tokens.append(allocator, .{ .id = t.T_INLINE_HTML, .text = src[start..], .line = line, .pos = start });
        return;
    }
}

// TOKEN_PARSE: php's parser turns a reserved word used where the grammar wants
// an identifier into T_STRING
fn reclassifyIdentifiers(tokens: []Token) void {
    for (tokens, 0..) |*tok, i| {
        if (!isKeywordId(tok.id)) continue;
        const prev = significantBefore(tokens, i);
        const next = significantAfter(tokens, i);
        const prev_id: i64 = if (prev) |p| tokens[p].id else 0;
        const next_id: i64 = if (next) |n| tokens[n].id else 0;
        const after_function = prev_id == t.T_FUNCTION or (prev_id == t.T_AMPERSAND_NOT_FOLLOWED_BY_VAR_OR_VARARG and prev != null and blk: {
            const before = significantBefore(tokens, prev.?);
            break :blk before != null and tokens[before.?].id == t.T_FUNCTION;
        });
        const named_argument = next_id == ':' and (prev_id == '(' or prev_id == ',');
        const enum_case = prev_id == t.T_CASE and (next_id == '=' or next_id == ';');
        const const_list_item = prev_id == ',' and next_id == '=' and inConstList(tokens, i);
        if (prev_id == t.T_DOUBLE_COLON or (after_function and next_id == '(') or prev_id == t.T_CONST or named_argument or enum_case or const_list_item) {
            tok.id = t.T_STRING;
        }
    }
}

// `const A = 1, B = 2`: walks back over the list to its `const`
fn inConstList(tokens: []const Token, i: usize) bool {
    var j = i;
    var depth: i32 = 0;
    while (j > 0) {
        j -= 1;
        switch (tokens[j].id) {
            ')', ']', '}' => depth += 1,
            '(', '[', '{' => {
                if (depth == 0) return false;
                depth -= 1;
            },
            ';' => return false,
            else => if (depth == 0 and tokens[j].id == t.T_CONST) return true,
        }
    }
    return false;
}

fn isTrivia(id: i64) bool {
    return id == t.T_WHITESPACE or id == t.T_COMMENT or id == t.T_DOC_COMMENT;
}

fn significantBefore(tokens: []const Token, i: usize) ?usize {
    var j = i;
    while (j > 0) {
        j -= 1;
        if (!isTrivia(tokens[j].id)) return j;
    }
    return null;
}

fn significantAfter(tokens: []const Token, i: usize) ?usize {
    var j = i + 1;
    while (j < tokens.len) : (j += 1) {
        if (!isTrivia(tokens[j].id)) return j;
    }
    return null;
}

pub fn tokenName(id: i64) ?[]const u8 {
    for (t.names) |n| {
        if (n.id == id) return n.name;
    }
    return null;
}

pub fn register(vm: *VM, a: Allocator) !void {
    for (t.constants) |c| try vm.php_constants.put(a, c.name, .{ .int = c.id });
    try vm.php_constants.put(a, "TOKEN_PARSE", .{ .int = TOKEN_PARSE });

    var def = ClassDef{ .name = "PhpToken" };
    try def.interfaces.append(a, "Stringable");
    for ([_][]const u8{ "id", "text", "line", "pos" }) |prop| try def.properties.append(a, .{ .name = prop, .default = .null });
    try def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 4 });
    try def.methods.put(a, "tokenize", .{ .name = "tokenize", .arity = 2, .is_static = true });
    try def.methods.put(a, "is", .{ .name = "is", .arity = 1 });
    try def.methods.put(a, "isIgnorable", .{ .name = "isIgnorable", .arity = 0 });
    try def.methods.put(a, "getTokenName", .{ .name = "getTokenName", .arity = 0 });
    try def.methods.put(a, "__toString", .{ .name = "__toString", .arity = 0 });
    try vm.classes.put(a, "PhpToken", def);
    try vm.native_fns.put(a, "PhpToken::__construct", phpTokenConstruct);
    try vm.native_fns.put(a, "PhpToken::tokenize", phpTokenTokenize);
    try vm.native_fns.put(a, "PhpToken::is", phpTokenIs);
    try vm.native_fns.put(a, "PhpToken::isIgnorable", phpTokenIsIgnorable);
    try vm.native_fns.put(a, "PhpToken::getTokenName", phpTokenGetTokenName);
    try vm.native_fns.put(a, "PhpToken::__toString", phpTokenToString);
    try vm.native_fns.put(a, "token_get_all", tokenGetAll);
    try vm.native_fns.put(a, "token_name", nativeTokenName);
}

// tokenizes with php's rules for the flags, raising ParseError under
// TOKEN_PARSE when the code does not parse
fn lex(ctx: *NativeContext, args: []const Value) RuntimeError![]Token {
    const src = if (args.len > 0 and args[0] == .string) args[0].string.bytes() else "";
    const flags: i64 = if (args.len > 1) Value.toInt(args[1]) else 0;
    const short = if (ctx.vm.ini_settings.get("short_open_tag")) |v| !(std.mem.eql(u8, v, "0") or std.ascii.eqlIgnoreCase(v, "off")) else true;
    const tokens = try tokenize(ctx.allocator, src, short);
    errdefer ctx.allocator.free(tokens);
    if ((flags & TOKEN_PARSE) != 0) {
        try ctx.vm.checkSyntax(src);
        reclassifyIdentifiers(tokens);
    }
    return tokens;
}

fn tokenGetAll(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const tokens = try lex(ctx, args);
    defer ctx.allocator.free(tokens);
    const out = try ctx.createArray();
    for (tokens) |tok| {
        const text = try Value.String.create(ctx.allocator, tok.text);
        defer text.release();
        if (tok.isChar()) {
            try out.append(ctx.allocator, .{ .string = text });
            continue;
        }
        const entry = try ctx.createArray();
        try entry.append(ctx.allocator, .{ .int = tok.id });
        try entry.append(ctx.allocator, .{ .string = text });
        try entry.append(ctx.allocator, .{ .int = tok.line });
        try out.append(ctx.allocator, .{ .array = entry });
    }
    return NativeResult.borrowed(.{ .array = out });
}

fn nativeTokenName(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const id: i64 = if (args.len > 0) Value.toInt(args[0]) else 0;
    return NativeResult.copyString(ctx.allocator, tokenName(id) orelse "UNKNOWN");
}

fn thisToken(ctx: *NativeContext) ?*PhpObject {
    const this = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    return if (this == .object) this.object else null;
}

fn phpTokenConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = thisToken(ctx) orelse return NativeResult.scalar(.null);
    try this.set(ctx.allocator, "id", .{ .int = if (args.len > 0) Value.toInt(args[0]) else 0 });
    try this.set(ctx.allocator, "text", if (args.len > 1) args[1] else .{ .string = Value.String.borrowed("") });
    try this.set(ctx.allocator, "line", .{ .int = if (args.len > 2) Value.toInt(args[2]) else -1 });
    try this.set(ctx.allocator, "pos", .{ .int = if (args.len > 3) Value.toInt(args[3]) else -1 });
    return NativeResult.scalar(.null);
}

// instances of the class tokenize was called on, built without running a
// constructor, as php does
fn phpTokenTokenize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const tokens = try lex(ctx, args);
    defer ctx.allocator.free(tokens);
    const class_name = calledClass(ctx);
    const out = try ctx.createArray();
    for (tokens) |tok| {
        const obj = try ctx.createObject(class_name);
        const text = try Value.String.create(ctx.allocator, tok.text);
        defer text.release();
        try obj.set(ctx.allocator, "id", .{ .int = tok.id });
        try obj.set(ctx.allocator, "text", .{ .string = text });
        try obj.set(ctx.allocator, "line", .{ .int = tok.line });
        try obj.set(ctx.allocator, "pos", .{ .int = tok.pos });
        try out.append(ctx.allocator, .{ .object = obj });
    }
    return NativeResult.borrowed(.{ .array = out });
}

fn calledClass(ctx: *NativeContext) []const u8 {
    if (ctx.vm.currentFrame().called_class) |cls| return cls;
    if (ctx.call_name) |name| if (std.mem.indexOf(u8, name, "::")) |sep| return name[0..sep];
    return "PhpToken";
}

fn tokenIdOf(obj: *PhpObject) i64 {
    const id = obj.get("id");
    return if (id == .int) id.int else 0;
}

fn tokenTextOf(obj: *PhpObject) []const u8 {
    const text = obj.get("text");
    return if (text == .string) text.string.bytes() else "";
}

fn matchesKind(obj: *PhpObject, kind: Value) bool {
    return switch (kind) {
        .int => |id| tokenIdOf(obj) == id,
        .string => |s| std.mem.eql(u8, tokenTextOf(obj), s.bytes()),
        .array => |arr| for (arr.entries.items) |e| {
            if (matchesKind(obj, e.value)) break true;
        } else false,
        else => false,
    };
}

fn phpTokenIs(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = thisToken(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    if (args[0] != .int and args[0] != .string and args[0] != .array) {
        try ctx.vm.setPendingException("TypeError", "PhpToken::is(): Argument #1 ($kind) must be of type string|int|array");
        return error.RuntimeError;
    }
    return NativeResult.scalar(.{ .bool = matchesKind(this, args[0]) });
}

fn phpTokenIsIgnorable(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = thisToken(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const id = tokenIdOf(this);
    return NativeResult.scalar(.{ .bool = isTrivia(id) or id == t.T_OPEN_TAG });
}

fn phpTokenGetTokenName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = thisToken(ctx) orelse return NativeResult.scalar(.null);
    const id = tokenIdOf(this);
    if (id >= 0 and id < 256) {
        const byte = [1]u8{@intCast(id)};
        return NativeResult.copyString(ctx.allocator, &byte);
    }
    return if (tokenName(id)) |name| NativeResult.copyString(ctx.allocator, name) else NativeResult.scalar(.null);
}

fn phpTokenToString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = thisToken(ctx) orelse return NativeResult.literal("");
    return NativeResult.share(this.get("text"));
}

test "tokenize names, casts and heredoc" {
    const a = std.testing.allocator;
    const tokens = try tokenize(a, "<?php namespace\\A; \\B\\C; (int ) $x; <<<E\n  a $b\n  E;\n", true);
    defer a.free(tokens);
    try std.testing.expectEqual(t.T_OPEN_TAG, tokens[0].id);
    try std.testing.expectEqual(t.T_NAME_RELATIVE, tokens[1].id);
    try std.testing.expectEqual(t.T_NAME_FULLY_QUALIFIED, tokens[4].id);
    try std.testing.expectEqual(t.T_INT_CAST, tokens[7].id);
    try std.testing.expectEqualStrings("(int )", tokens[7].text);
    var saw_end = false;
    for (tokens) |tok| {
        if (tok.id == t.T_END_HEREDOC) {
            try std.testing.expectEqualStrings("  E", tok.text);
            try std.testing.expectEqual(@as(u32, 3), tok.line);
            saw_end = true;
        }
    }
    try std.testing.expect(saw_end);
}
