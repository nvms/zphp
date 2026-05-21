const std = @import("std");
const Compiler = @import("compiler.zig").Compiler;
const Ast = @import("ast.zig").Ast;
const Allocator = std.mem.Allocator;

pub fn compileString(self: *Compiler, node: Ast.Node) (Allocator.Error || error{CompileError})!void {
    const tok_tag = self.ast.tokens[node.main_token].tag;

    if (tok_tag == .heredoc or tok_tag == .nowdoc) {
        const body = try extractHeredocBody(self, node.main_token);
        if (tok_tag == .nowdoc) {
            const idx = try self.addConstant(.{ .string = body });
            try self.emitConstant(idx);
            return;
        }
        if (std.mem.indexOf(u8, body, "$") == null) {
            if (std.mem.indexOf(u8, body, "\\") == null) {
                const idx = try self.addConstant(.{ .string = body });
                try self.emitConstant(idx);
            } else {
                const processed = try processEscapes(self.allocator, body);
                try self.string_allocs.append(self.allocator, processed);
                const idx = try self.addConstant(.{ .string = processed });
                try self.emitConstant(idx);
            }
        } else {
            try compileInterpolatedString(self, body);
        }
        return;
    }

    const lexeme = self.ast.tokenSlice(node.main_token);
    if (lexeme.len < 2) {
        const idx = try self.addConstant(.{ .string = lexeme });
        try self.emitConstant(idx);
        return;
    }
    const quote = lexeme[0];
    const inner = lexeme[1 .. lexeme.len - 1];

    if (quote == '\'') {
        const processed = try processSingleQuoteEscapes(self.allocator, inner);
        if (processed) |p| {
            try self.string_allocs.append(self.allocator, p);
            const idx = try self.addConstant(.{ .string = p });
            try self.emitConstant(idx);
        } else {
            const idx = try self.addConstant(.{ .string = inner });
            try self.emitConstant(idx);
        }
        return;
    }

    if (std.mem.indexOf(u8, inner, "$") == null) {
        if (std.mem.indexOf(u8, inner, "\\") == null) {
            const idx = try self.addConstant(.{ .string = inner });
            try self.emitConstant(idx);
        } else {
            const processed = try processEscapes(self.allocator, inner);
            try self.string_allocs.append(self.allocator, processed);
            const idx = try self.addConstant(.{ .string = processed });
            try self.emitConstant(idx);
        }
        return;
    }

    try compileInterpolatedString(self, inner);
}

pub fn extractHeredocBody(self: *Compiler, token_idx: u32) (Allocator.Error || error{CompileError})![]const u8 {
    const lexeme = self.ast.tokenSlice(token_idx);
    var pos: usize = 3;
    if (pos < lexeme.len and lexeme[pos] == '\'') {
        pos += 1;
    }
    const label_start = pos;
    while (pos < lexeme.len and (std.ascii.isAlphanumeric(lexeme[pos]) or lexeme[pos] == '_')) pos += 1;
    const label = lexeme[label_start..pos];
    if (pos < lexeme.len and lexeme[pos] == '\'') pos += 1;

    while (pos < lexeme.len and lexeme[pos] != '\n') pos += 1;
    if (pos < lexeme.len) pos += 1;
    const body_start = pos;

    var end = lexeme.len;
    if (end > 0 and lexeme[end - 1] == '\n') end -= 1;
    if (end > 0 and lexeme[end - 1] == '\r') end -= 1;
    if (end > 0 and lexeme[end - 1] == ';') end -= 1;
    const label_end = end;
    if (label_end >= label.len and std.mem.eql(u8, lexeme[label_end - label.len .. label_end], label)) {
        end = label_end - label.len;
    }

    var closing_line_start = end;
    while (closing_line_start > body_start and lexeme[closing_line_start - 1] != '\n') {
        closing_line_start -= 1;
    }
    const indent = end - closing_line_start;

    var body_end = closing_line_start;
    if (body_end > body_start and lexeme[body_end - 1] == '\n') body_end -= 1;
    if (body_end > body_start and lexeme[body_end - 1] == '\r') body_end -= 1;

    if (body_end <= body_start) {
        const idx = try self.addConstant(.{ .string = "" });
        _ = idx;
        return "";
    }

    const raw_body = lexeme[body_start..body_end];

    if (indent == 0) return raw_body;

    var result = std.ArrayListUnmanaged(u8){};
    var line_begin: usize = 0;
    var line_idx: usize = 0;
    while (line_begin <= raw_body.len) {
        const line_end = std.mem.indexOfScalarPos(u8, raw_body, line_begin, '\n') orelse raw_body.len;
        const line = raw_body[line_begin..line_end];

        if (line_idx > 0) try result.append(self.allocator, '\n');

        var stripped: usize = 0;
        while (stripped < indent and stripped < line.len and (line[stripped] == ' ' or line[stripped] == '\t')) {
            stripped += 1;
        }
        try result.appendSlice(self.allocator, line[stripped..]);

        line_begin = line_end + 1;
        line_idx += 1;
    }

    const owned = try result.toOwnedSlice(self.allocator);
    try self.string_allocs.append(self.allocator, owned);
    return owned;
}

fn compileInterpolatedString(self: *Compiler, s: []const u8) (Allocator.Error || error{CompileError})!void {
    var segment_count: u32 = 0;
    var i: usize = 0;

    while (i < s.len) {
        if (s[i] == '\\' and i + 1 < s.len) {
            if (s[i + 1] == '\\') {
                i += 2;
                continue;
            }
            if (s[i + 1] == '$') {
                i += 2;
                continue;
            }
        }
        if (s[i] == '{' and i + 1 < s.len and s[i + 1] == '$') {
            break;
        }
        if (s[i] == '$' and i + 1 < s.len and (isVarStart(s[i + 1]))) {
            break;
        }
        i += 1;
    }

    i = 0;
    var lit_start: usize = 0;

    while (i < s.len) {
        if (s[i] == '\\' and i + 1 < s.len) {
            if (s[i + 1] == '\\') {
                i += 2;
                continue;
            }
            if (s[i + 1] == '$') {
                i += 2;
                continue;
            }
        }

        if (s[i] == '{' and i + 1 < s.len and s[i + 1] == '$') {
            if (i > lit_start) {
                try emitLiteralSegment(self, s[lit_start..i]);
                if (segment_count > 0) try self.emitOp(.concat);
                segment_count += 1;
            }

            const end = std.mem.indexOfScalarPos(u8, s, i, '}') orelse s.len;
            const expr_inner = s[i + 1 .. end];
            try emitInterpolationExpr(self, expr_inner);
            if (segment_count > 0) try self.emitOp(.concat);
            segment_count += 1;

            i = if (end < s.len) end + 1 else end;
            lit_start = i;
            continue;
        }

        if (s[i] == '$' and i + 1 < s.len and s[i + 1] == '{') {
            if (i > lit_start) {
                try emitLiteralSegment(self, s[lit_start..i]);
                if (segment_count > 0) try self.emitOp(.concat);
                segment_count += 1;
            }
            const end = std.mem.indexOfScalarPos(u8, s, i + 2, '}') orelse s.len;
            const var_name_raw = s[i + 2 .. end];
            var name_buf: [256]u8 = undefined;
            name_buf[0] = '$';
            @memcpy(name_buf[1 .. 1 + var_name_raw.len], var_name_raw);
            const full_name = name_buf[0 .. 1 + var_name_raw.len];
            const owned = try self.allocator.dupe(u8, full_name);
            try self.string_allocs.append(self.allocator, owned);
            try self.emitGetVar(owned);
            if (segment_count > 0) try self.emitOp(.concat);
            segment_count += 1;
            i = if (end < s.len) end + 1 else end;
            lit_start = i;
            continue;
        }

        if (s[i] == '$' and i + 1 < s.len and isVarStart(s[i + 1])) {
            if (i > lit_start) {
                try emitLiteralSegment(self, s[lit_start..i]);
                if (segment_count > 0) try self.emitOp(.concat);
                segment_count += 1;
            }

            var j = i + 1;
            while (j < s.len and isVarChar(s[j])) j += 1;

            const var_name = s[i..j];
            try self.emitGetVar(var_name);

            if (j < s.len and s[j] == '[') {
                const bracket_end = std.mem.indexOfScalarPos(u8, s, j, ']') orelse s.len;
                const key_str = s[j + 1 .. bracket_end];
                try emitArrayKeyAccess(self, key_str);
                j = if (bracket_end < s.len) bracket_end + 1 else bracket_end;
            } else if (j + 1 < s.len and s[j] == '-' and s[j + 1] == '>') {
                j += 2;
                var k = j;
                while (k < s.len and isVarChar(s[k])) k += 1;
                if (k > j) {
                    const prop_name = s[j..k];
                    const name_idx = try self.addConstant(.{ .string = prop_name });
                    try self.emitOp(.get_prop);
                    try self.emitU16(name_idx);
                    j = k;
                }
            }

            if (segment_count > 0) try self.emitOp(.concat);
            segment_count += 1;
            i = j;

            lit_start = i;
            continue;
        }

        i += 1;
    }

    if (lit_start < s.len) {
        try emitLiteralSegment(self, s[lit_start..]);
        if (segment_count > 0) try self.emitOp(.concat);
        segment_count += 1;
    }

    if (segment_count == 0) {
        const idx = try self.addConstant(.{ .string = "" });
        try self.emitConstant(idx);
    }
}

fn emitLiteralSegment(self: *Compiler, s: []const u8) (Allocator.Error || error{CompileError})!void {
    if (std.mem.indexOf(u8, s, "\\") != null) {
        const processed = try processEscapes(self.allocator, s);
        try self.string_allocs.append(self.allocator, processed);
        const idx = try self.addConstant(.{ .string = processed });
        try self.emitConstant(idx);
    } else {
        const idx = try self.addConstant(.{ .string = s });
        try self.emitConstant(idx);
    }
}

fn emitInterpolationExpr(self: *Compiler, expr: []const u8) (Allocator.Error || error{CompileError})!void {
    if (expr.len == 0 or expr[0] != '$') return;

    var j: usize = 1;
    while (j < expr.len and isVarChar(expr[j])) j += 1;

    const var_name = expr[0..j];
    try self.emitGetVar(var_name);

    while (j < expr.len) {
        if (expr[j] == '[') {
            const bracket_end = findMatchingBracket(expr, j) orelse break;
            const key_str = expr[j + 1 .. bracket_end];
            try emitArrayKeyAccess(self, key_str);
            j = bracket_end + 1;
        } else if (expr[j] == '(') {
            // variable function call inside interpolation: {$fn('arg')}
            const paren_end = findMatchingParen(expr, j) orelse break;
            const args_str = expr[j + 1 .. paren_end];
            const arg_count = try emitInterpArgs(self, args_str);
            try self.emitOp(.call_indirect);
            try self.emitByte(arg_count);
            j = paren_end + 1;
        } else if (j + 1 < expr.len and expr[j] == '-' and expr[j + 1] == '>') {
            j += 2;
            // dynamic property name: {$obj->$var}
            if (j < expr.len and expr[j] == '$') {
                var k = j + 1;
                while (k < expr.len and isVarChar(expr[k])) k += 1;
                if (k == j + 1) break;
                try self.emitGetVar(expr[j..k]);
                try self.emitOp(.get_prop_dynamic);
                j = k;
                continue;
            }
            var k = j;
            while (k < expr.len and isVarChar(expr[k])) k += 1;
            if (k == j) break;
            const prop_name = expr[j..k];
            if (k < expr.len and expr[k] == '(') {
                const paren_end = findMatchingParen(expr, k) orelse break;
                const args_str = expr[k + 1 .. paren_end];
                const arg_count = try emitInterpArgs(self, args_str);
                const name_idx = try self.addConstant(.{ .string = prop_name });
                try self.emitOp(.method_call);
                try self.emitU16(name_idx);
                try self.emitByte(arg_count);
                j = paren_end + 1;
            } else {
                const name_idx = try self.addConstant(.{ .string = prop_name });
                try self.emitOp(.get_prop);
                try self.emitU16(name_idx);
                j = k;
            }
        } else break;
    }
}

fn findMatchingParen(s: []const u8, start: usize) ?usize {
    var depth: usize = 0;
    var in_quote: ?u8 = null;
    var i = start;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (in_quote) |q| {
            if (c == '\\' and i + 1 < s.len) { i += 1; continue; }
            if (c == q) in_quote = null;
            continue;
        }
        if (c == '\'' or c == '"') { in_quote = c; continue; }
        if (c == '(') depth += 1
        else if (c == ')') {
            depth -= 1;
            if (depth == 0) return i;
        }
    }
    return null;
}

fn splitArgs(s: []const u8, buf: *[16][]const u8) usize {
    var count: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    var depth: usize = 0;
    var in_quote: ?u8 = null;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (in_quote) |q| {
            if (c == '\\' and i + 1 < s.len) { i += 1; continue; }
            if (c == q) in_quote = null;
            continue;
        }
        if (c == '\'' or c == '"') { in_quote = c; continue; }
        if (c == '(' or c == '[') depth += 1
        else if (c == ')' or c == ']') depth -= 1
        else if (c == ',' and depth == 0) {
            if (count < buf.len) {
                buf[count] = std.mem.trim(u8, s[start..i], " \t\n");
                count += 1;
            }
            start = i + 1;
        }
    }
    const tail = std.mem.trim(u8, s[start..], " \t\n");
    if (tail.len > 0 and count < buf.len) {
        buf[count] = tail;
        count += 1;
    }
    return count;
}

fn emitInterpArgs(self: *Compiler, args_str: []const u8) (Allocator.Error || error{CompileError})!u8 {
    const trimmed = std.mem.trim(u8, args_str, " \t\n");
    if (trimmed.len == 0) return 0;
    var args_buf: [16][]const u8 = undefined;
    const n = splitArgs(trimmed, &args_buf);
    for (args_buf[0..n]) |arg| {
        try emitInterpArgValue(self, arg);
    }
    return @intCast(n);
}

fn emitInterpArgValue(self: *Compiler, arg: []const u8) (Allocator.Error || error{CompileError})!void {
    if (arg.len == 0) {
        const idx = try self.addConstant(.{ .string = "" });
        try self.emitConstant(idx);
        return;
    }
    if (arg.len >= 2 and (arg[0] == '\'' or arg[0] == '"') and arg[arg.len - 1] == arg[0]) {
        const inner = arg[1 .. arg.len - 1];
        const owned = try self.allocator.dupe(u8, inner);
        try self.string_allocs.append(self.allocator, owned);
        const idx = try self.addConstant(.{ .string = owned });
        try self.emitConstant(idx);
        return;
    }
    if (arg[0] == '$') {
        try emitInterpolationExpr(self, arg);
        return;
    }
    if (std.mem.eql(u8, arg, "true")) {
        const idx = try self.addConstant(.{ .bool = true });
        try self.emitConstant(idx);
        return;
    }
    if (std.mem.eql(u8, arg, "false")) {
        const idx = try self.addConstant(.{ .bool = false });
        try self.emitConstant(idx);
        return;
    }
    if (std.mem.eql(u8, arg, "null")) {
        const idx = try self.addConstant(.null);
        try self.emitConstant(idx);
        return;
    }
    if (std.fmt.parseInt(i64, arg, 10) catch null) |int_val| {
        const idx = try self.addConstant(.{ .int = int_val });
        try self.emitConstant(idx);
        return;
    }
    if (std.fmt.parseFloat(f64, arg) catch null) |fv| {
        const idx = try self.addConstant(.{ .float = fv });
        try self.emitConstant(idx);
        return;
    }
    const idx = try self.addConstant(.{ .string = arg });
    try self.emitConstant(idx);
}

fn findMatchingBracket(s: []const u8, start: usize) ?usize {
    var depth: usize = 0;
    var i = start;
    while (i < s.len) : (i += 1) {
        if (s[i] == '[') depth += 1
        else if (s[i] == ']') {
            depth -= 1;
            if (depth == 0) return i;
        }
    }
    return null;
}

fn emitArrayKeyAccess(self: *Compiler, key: []const u8) (Allocator.Error || error{CompileError})!void {
    if (key.len > 0 and key[0] == '$') {
        try self.emitGetVar(key);
    } else if (key.len > 0 and (key[0] >= '0' and key[0] <= '9')) {
        const int_val = Compiler.parsePhpInt(key);
        const idx = try self.addConstant(.{ .int = int_val });
        try self.emitConstant(idx);
    } else if (key.len >= 2 and (key[0] == '\'' or key[0] == '"')) {
        const idx = try self.addConstant(.{ .string = key[1 .. key.len - 1] });
        try self.emitConstant(idx);
    } else {
        const idx = try self.addConstant(.{ .string = key });
        try self.emitConstant(idx);
    }
    try self.emitOp(.array_get);
}

fn isVarStart(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

fn isVarChar(c: u8) bool {
    return isVarStart(c) or (c >= '0' and c <= '9');
}

pub fn processSingleQuoteEscapes(allocator: Allocator, s: []const u8) Allocator.Error!?[]const u8 {
    if (std.mem.indexOf(u8, s, "\\") == null) return null;
    var buf = std.ArrayListUnmanaged(u8){};
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

pub fn processEscapes(allocator: Allocator, s: []const u8) ![]const u8 {
    var buf = std.ArrayListUnmanaged(u8){};
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
                '"' => {
                    try buf.append(allocator, '"');
                    i += 2;
                },
                'x' => {
                    // \xNN hex escape
                    var val: u8 = 0;
                    var consumed: usize = 2;
                    var digits: usize = 0;
                    while (digits < 2 and i + 2 + digits < s.len) : (digits += 1) {
                        const c = s[i + 2 + digits];
                        const d: u8 = if (c >= '0' and c <= '9') c - '0'
                            else if (c >= 'a' and c <= 'f') c - 'a' + 10
                            else if (c >= 'A' and c <= 'F') c - 'A' + 10
                            else break;
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
                    // \NNN octal escape (up to 3 digits)
                    var val: u8 = 0;
                    var consumed: usize = 1;
                    var digits: usize = 0;
                    while (digits < 3 and i + 1 + digits < s.len) : (digits += 1) {
                        const c = s[i + 1 + digits];
                        if (c < '0' or c > '7') break;
                        const new_val = @as(u16, val) * 8 + (c - '0');
                        if (new_val > 255) break;
                        val = @intCast(new_val);
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
                            var utf8_buf: [4]u8 = undefined;
                            const utf8_len = std.unicode.utf8Encode(cp, &utf8_buf) catch {
                                try buf.append(allocator, '\\');
                                try buf.append(allocator, 'u');
                                i += 2;
                                continue;
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
