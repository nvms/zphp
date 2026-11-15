const std = @import("std");
const Compiler = @import("compiler.zig").Compiler;
const Ast = @import("ast.zig").Ast;
const Allocator = std.mem.Allocator;
const Value = @import("../runtime/value.zig").Value;
const interp = @import("interp.zig");

pub fn compileString(self: *Compiler, node: Ast.Node) (Allocator.Error || error{CompileError})!void {
    const tok_tag = self.ast.tokens[node.main_token].tag;
    const lexeme = self.ast.tokenSlice(node.main_token);
    const quote: u8 = if (tok_tag == .heredoc) 0 else if (lexeme.len > 0) lexeme[0] else 0;

    if (quote == '`') {
        // `cmd` is shell_exec("cmd"), resolved globally like php does
        try self.warn(node.main_token, 8192, "The backtick (`) operator is deprecated, use shell_exec() instead", .{});
        try compileInterpolating(self, node, quote);
        try self.emitOp(.call);
        try self.emitU16(try self.addConstant(.{ .string = Value.String.borrowed("shell_exec") }));
        try self.emitByte(1);
        return;
    }
    if (tok_tag == .heredoc or quote == '"') return compileInterpolating(self, node, quote);

    if (tok_tag == .nowdoc) {
        const body = try extractHeredocBody(self, node.main_token);
        const idx = try self.addConstant(.{ .string = Value.String.borrowed(body) });
        try self.emitConstant(idx);
        return;
    }

    if (lexeme.len < 2) {
        const idx = try self.addConstant(.{ .string = Value.String.borrowed(lexeme) });
        try self.emitConstant(idx);
        return;
    }
    const inner = lexeme[1 .. lexeme.len - 1];
    const processed = try processSingleQuoteEscapes(self.allocator, inner);
    if (processed) |p| {
        try self.string_allocs.append(self.allocator, p);
        const idx = try self.addConstant(.{ .string = Value.String.borrowed(p) });
        try self.emitConstant(idx);
    } else {
        const idx = try self.addConstant(.{ .string = Value.String.borrowed(inner) });
        try self.emitConstant(idx);
    }
}

pub fn extractHeredocBody(self: *Compiler, token_idx: u32) (Allocator.Error || error{CompileError})![]const u8 {
    const src = self.ast.source;
    const tok = self.ast.tokens[token_idx];
    const h = interp.heredoc(src, tok) orelse return "";
    if (h.indent == 0) return src[h.body_start..h.body_end];
    const b: interp.Body = .{ .start = h.body_start, .end = h.body_end, .heredoc = true, .indent = h.indent };
    const owned = try interp.dedent(self.allocator, src, b, h.body_start, h.body_end);
    try self.string_allocs.append(self.allocator, owned);
    return owned;
}

// a double-quoted string, heredoc or backtick command: its literal text
// and, when the parser found any, its interpolated parts, concatenated in
// order (php's encaps_list and rope)
fn compileInterpolating(self: *Compiler, node: Ast.Node, quote: u8) (Allocator.Error || error{CompileError})!void {
    const src = self.ast.source;
    const b = interp.body(src, self.ast.tokens[node.main_token]) orelse {
        try self.emitConstant(try self.addConstant(.{ .string = Value.String.borrowed("") }));
        return;
    };
    if (node.data.rhs != Ast.interpolated) {
        try emitLiteralSegment(self, node.main_token, b, quote, b.start, b.end);
        return;
    }
    const parts = self.ast.extraSlice(node.data.lhs);
    var literal_count: u32 = 0;
    for (parts, 0..) |part_idx, k| {
        const part = self.ast.nodes[part_idx];
        if (part.tag == .interp_literal) {
            try emitLiteralSegment(self, node.main_token, b, quote, part.data.lhs, part.data.rhs);
            literal_count += 1;
        } else {
            try compileInterpPart(self, part_idx);
            // php's rope turns each part into a string as it is added: a
            // value directly followed by another is converted before the
            // next one runs
            if (k == 0 and parts.len > 1 and self.ast.nodes[parts[1]].tag != .interp_literal) try self.emitOp(.cast_string);
        }
        if (k > 0) try self.emitOp(.concat);
    }
    if (parts.len == 0) {
        try self.emitConstant(try self.addConstant(.{ .string = Value.String.borrowed("") }));
    } else if (parts.len == 1 and literal_count == 0) {
        // "$x" alone is still a string
        try self.emitOp(.cast_string);
    }
}

// one interpolated part: an expression, or "${...}" with php's deprecation
pub fn compileInterpPart(self: *Compiler, idx: u32) (Allocator.Error || error{CompileError})!void {
    const node = self.ast.nodes[idx];
    switch (node.tag) {
        .interp_dollar_brace => {
            // php 8.2 deprecates both ${name} and ${expr} interpolation
            const at = node.data.rhs & ~Ast.dollar_brace_expr;
            if (node.data.rhs & Ast.dollar_brace_expr != 0) {
                try self.warnAtOffset(at, 8192, "Using ${{expr}} (variable variables) in strings is deprecated, use {{${{expr}}}} instead", .{});
                // ${expr}: the variable named by the expression's value
                try self.compileNode(node.data.lhs);
                try self.emitOp(.get_var_var);
            } else {
                try self.warnAtOffset(at, 8192, "Using ${{var}} in strings is deprecated, use {{$var}} instead", .{});
                try self.compileNode(node.data.lhs);
            }
        },
        .interp_varname => {
            const name = try std.fmt.allocPrint(self.allocator, "${s}", .{self.ast.tokenSlice(node.main_token)});
            try self.string_allocs.append(self.allocator, name);
            try self.emitGetVar(name);
        },
        .interp_offset => try self.emitConstant(try self.addConstant(try interpOffsetValue(self, node))),
        .interp_literal => try self.emitConstant(try self.addConstant(.{ .string = Value.String.borrowed(self.ast.source[node.data.lhs..node.data.rhs]) })),
        else => try self.compileNode(idx),
    }
}

// the key of "$a[k]": a name is a string, a decimal integer without
// leading zeros that fits is an int, any other number stays the string
// written (php's T_NUM_STRING and zend_negate_num_string)
fn interpOffsetValue(self: *Compiler, node: Ast.Node) Allocator.Error!Value {
    const text = self.ast.tokenSlice(node.main_token);
    const negative = node.data.lhs == 1;
    const canonical = text.len > 0 and std.ascii.isDigit(text[0]) and (text[0] != '0' or text.len == 1) and for (text) |c| {
        if (!std.ascii.isDigit(c)) break false;
    } else true;
    if (canonical) {
        if (std.fmt.parseInt(i64, text, 10) catch null) |n| {
            if (!negative) return .{ .int = n };
            if (n != 0) return .{ .int = -n };
        }
    }
    if (!negative) return .{ .string = Value.String.borrowed(text) };
    const owned = try std.fmt.allocPrint(self.allocator, "-{s}", .{text});
    try self.string_allocs.append(self.allocator, owned);
    return .{ .string = Value.String.borrowed(owned) };
}

// literal text of an interpolating string: a heredoc's lines lose the
// closing marker's indentation, then escapes are read
fn emitLiteralSegment(self: *Compiler, token: u32, b: interp.Body, quote: u8, start: u32, end: u32) (Allocator.Error || error{CompileError})!void {
    const src = self.ast.source;
    try warnOctalOverflow(self, token, src[start..end]);
    var text = src[start..end];
    if (b.heredoc and b.indent > 0) {
        text = try interp.dedent(self.allocator, src, b, start, end);
        try self.string_allocs.append(self.allocator, text);
    }
    if (std.mem.indexOfScalar(u8, text, '\\') != null) {
        const processed = try processEscapes(self.allocator, text, quote);
        try self.string_allocs.append(self.allocator, processed);
        text = processed;
    }
    const idx = try self.addConstant(.{ .string = Value.String.borrowed(text) });
    try self.emitConstant(idx);
}

pub fn processSingleQuoteEscapes(allocator: Allocator, s: []const u8) Allocator.Error!?[]const u8 {
    if (std.mem.indexOf(u8, s, "\\") == null) return null;
    var buf = std.ArrayListUnmanaged(u8).empty;
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '\\' and i + 1 < s.len) {
            switch (s[i + 1]) {
                '\\' => {
                    try buf.append(allocator, '\\');
                    i += 2;
                },
                '\'' => {
                    try buf.append(allocator, '\'');
                    i += 2;
                },
                else => {
                    try buf.append(allocator, s[i]);
                    i += 1;
                },
            }
        } else {
            try buf.append(allocator, s[i]);
            i += 1;
        }
    }
    const slice: []const u8 = try buf.toOwnedSlice(allocator);
    return slice;
}

// escape sequences of a double-quoted string, heredoc, or backtick command.
// quote is the delimiter (`"` or '`'), or 0 for a heredoc: an escaped quote
// character only loses its backslash inside its own kind of string
// zend_scan_escape_string's warning for a three-digit octal escape past
// \377, whose value is cut to a byte. the scanner counts the string's lines
// as it goes, so the warning names the escape's own line; a heredoc's body
// starts on the line after its opening
fn warnOctalOverflow(self: *Compiler, token: u32, s: []const u8) (Allocator.Error || error{CompileError})!void {
    if (std.mem.indexOfScalar(u8, s, '\\') == null) return;
    const src = self.ast.source;
    const tok_start = @min(self.ast.tokens[token].start, src.len);
    const in_source = @intFromPtr(s.ptr) >= @intFromPtr(src.ptr) and @intFromPtr(s.ptr) + s.len <= @intFromPtr(src.ptr) + src.len;
    const body_start: usize = if (in_source) @intFromPtr(s.ptr) - @intFromPtr(src.ptr) else if (std.mem.indexOfScalarPos(u8, src, tok_start, '\n')) |nl| nl + 1 else tok_start;
    const first_line: u32 = 1 + @as(u32, @intCast(std.mem.count(u8, src[0..body_start], "\n")));
    var i: usize = 0;
    while (i + 1 < s.len) {
        if (s[i] != '\\') {
            i += 1;
            continue;
        }
        var n: usize = 0;
        while (n < 3 and i + 1 + n < s.len and s[i + 1 + n] >= '0' and s[i + 1 + n] <= '7') n += 1;
        if (n == 3 and s[i + 1] > '3') {
            const line = first_line + @as(u32, @intCast(std.mem.count(u8, s[0..i], "\n")));
            try self.warnAtLine(line, 128, "Octal escape sequence overflow \\{s} is greater than \\377", .{s[i + 1 .. i + 4]});
            self.warnings.items[self.warnings.items.len - 1].scanner = true;
        }
        i += if (n > 0) 1 + n else 2;
    }
}

pub fn processEscapes(allocator: Allocator, s: []const u8, quote: u8) ![]const u8 {
    var buf = std.ArrayListUnmanaged(u8).empty;
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '\\' and i + 1 < s.len) {
            switch (s[i + 1]) {
                'n' => {
                    try buf.append(allocator, '\n');
                    i += 2;
                },
                'r' => {
                    try buf.append(allocator, '\r');
                    i += 2;
                },
                't' => {
                    try buf.append(allocator, '\t');
                    i += 2;
                },
                'v' => {
                    try buf.append(allocator, 0x0b);
                    i += 2;
                },
                'e' => {
                    try buf.append(allocator, 0x1b);
                    i += 2;
                },
                'f' => {
                    try buf.append(allocator, 0x0c);
                    i += 2;
                },
                '\\' => {
                    try buf.append(allocator, '\\');
                    i += 2;
                },
                '$' => {
                    try buf.append(allocator, '$');
                    i += 2;
                },
                '"', '`' => {
                    if (s[i + 1] != quote) try buf.append(allocator, '\\');
                    try buf.append(allocator, s[i + 1]);
                    i += 2;
                },
                'x' => {
                    // \xNN hex escape
                    var val: u8 = 0;
                    var consumed: usize = 2;
                    var digits: usize = 0;
                    while (digits < 2 and i + 2 + digits < s.len) : (digits += 1) {
                        const c = s[i + 2 + digits];
                        const d: u8 = if (c >= '0' and c <= '9') c - '0' else if (c >= 'a' and c <= 'f') c - 'a' + 10 else if (c >= 'A' and c <= 'F') c - 'A' + 10 else break;
                        val = val * 16 + d;
                        consumed += 1;
                    }
                    if (digits > 0) {
                        try buf.append(allocator, val);
                        i += consumed;
                    } else {
                        try buf.append(allocator, '\\');
                        try buf.append(allocator, 'x');
                        i += 2;
                    }
                },
                '0'...'7' => {
                    // \NNN octal escape (up to 3 digits); php keeps the
                    // low byte of a value past \377
                    var val: u8 = 0;
                    var consumed: usize = 1;
                    var digits: usize = 0;
                    while (digits < 3 and i + 1 + digits < s.len) : (digits += 1) {
                        const c = s[i + 1 + digits];
                        if (c < '0' or c > '7') break;
                        val = val *% 8 +% (c - '0');
                        consumed += 1;
                    }
                    try buf.append(allocator, val);
                    i += consumed;
                },
                'u' => {
                    // \u{NNNN} unicode escape
                    if (i + 3 < s.len and s[i + 2] == '{') {
                        var end = i + 3;
                        while (end < s.len and s[end] != '}') end += 1;
                        if (end < s.len) {
                            const hex_str = s[i + 3 .. end];
                            const cp = std.fmt.parseInt(u21, hex_str, 16) catch {
                                try buf.append(allocator, '\\');
                                try buf.append(allocator, 'u');
                                i += 2;
                                continue;
                            };
                            // php encodes any code point up to U+10FFFF,
                            // surrogates included
                            var utf8_buf: [4]u8 = undefined;
                            const c: u32 = cp;
                            const utf8_len: usize = if (c < 0x80) blk: {
                                utf8_buf[0] = @intCast(c);
                                break :blk 1;
                            } else if (c < 0x800) blk: {
                                utf8_buf[0] = @intCast(0xC0 | (c >> 6));
                                utf8_buf[1] = @intCast(0x80 | (c & 0x3F));
                                break :blk 2;
                            } else if (c < 0x10000) blk: {
                                utf8_buf[0] = @intCast(0xE0 | (c >> 12));
                                utf8_buf[1] = @intCast(0x80 | ((c >> 6) & 0x3F));
                                utf8_buf[2] = @intCast(0x80 | (c & 0x3F));
                                break :blk 3;
                            } else blk: {
                                utf8_buf[0] = @intCast(0xF0 | (c >> 18));
                                utf8_buf[1] = @intCast(0x80 | ((c >> 12) & 0x3F));
                                utf8_buf[2] = @intCast(0x80 | ((c >> 6) & 0x3F));
                                utf8_buf[3] = @intCast(0x80 | (c & 0x3F));
                                break :blk 4;
                            };
                            try buf.appendSlice(allocator, utf8_buf[0..utf8_len]);
                            i = end + 1;
                        } else {
                            try buf.append(allocator, '\\');
                            try buf.append(allocator, 'u');
                            i += 2;
                        }
                    } else {
                        try buf.append(allocator, '\\');
                        try buf.append(allocator, 'u');
                        i += 2;
                    }
                },
                else => {
                    try buf.append(allocator, '\\');
                    try buf.append(allocator, s[i + 1]);
                    i += 2;
                },
            }
        } else {
            try buf.append(allocator, s[i]);
            i += 1;
        }
    }
    return buf.toOwnedSlice(allocator);
}
