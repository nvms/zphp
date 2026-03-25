const std = @import("std");
const Ast = @import("ast.zig").Ast;
const Token = @import("token.zig").Token;
const Chunk = @import("bytecode.zig").Chunk;
const OpCode = @import("bytecode.zig").OpCode;
const ObjFunction = @import("bytecode.zig").ObjFunction;
const Value = @import("../runtime/value.zig").Value;

const Allocator = std.mem.Allocator;
const Error = Allocator.Error || error{CompileError};

pub const CompileResult = struct {
    chunk: Chunk,
    functions: std.ArrayListUnmanaged(ObjFunction),
    string_allocs: std.ArrayListUnmanaged([]const u8),
    allocator: Allocator,

    pub fn deinit(self: *CompileResult) void {
        self.chunk.deinit(self.allocator);
        for (self.functions.items) |*f| {
            f.chunk.deinit(self.allocator);
            self.allocator.free(f.params);
            if (f.defaults.len > 0) self.allocator.free(f.defaults);
            if (f.ref_params.len > 0) self.allocator.free(f.ref_params);
        }
        self.functions.deinit(self.allocator);
        for (self.string_allocs.items) |s| self.allocator.free(s);
        self.string_allocs.deinit(self.allocator);
    }
};

pub fn compile(ast: *const Ast, allocator: Allocator) Error!CompileResult {
    return compileWithPath(ast, allocator, "");
}

pub fn compileWithPath(ast: *const Ast, allocator: Allocator, file_path: []const u8) Error!CompileResult {
    var c = Compiler{
        .ast = ast,
        .chunk = .{},
        .functions = .{},
        .string_allocs = .{},
        .allocator = allocator,
        .scope_depth = 0,
        .loop_start = null,
        .break_jumps = .{},
        .continue_jumps = .{},
        .file_path = file_path,
    };
    errdefer {
        c.chunk.deinit(allocator);
        for (c.functions.items) |*f| f.chunk.deinit(allocator);
        c.functions.deinit(allocator);
        for (c.string_allocs.items) |s| allocator.free(s);
        c.string_allocs.deinit(allocator);
        c.break_jumps.deinit(allocator);
        c.continue_jumps.deinit(allocator);
    }

    const root = ast.nodes[0];
    for (ast.extraSlice(root.data.lhs)) |stmt| {
        try c.compileNode(stmt);
    }
    try c.emitOp(.halt);

    c.break_jumps.deinit(allocator);
    c.continue_jumps.deinit(allocator);
    var tp_iter = c.trait_properties.valueIterator();
    while (tp_iter.next()) |v| allocator.free(v.*);
    c.trait_properties.deinit(allocator);
    return .{ .chunk = c.chunk, .functions = c.functions, .string_allocs = c.string_allocs, .allocator = allocator };
}

const Compiler = struct {
    ast: *const Ast,
    chunk: Chunk,
    functions: std.ArrayListUnmanaged(ObjFunction),
    string_allocs: std.ArrayListUnmanaged([]const u8),
    allocator: Allocator,
    scope_depth: u32,
    loop_start: ?usize,
    break_jumps: std.ArrayListUnmanaged(LoopJump),
    continue_jumps: std.ArrayListUnmanaged(LoopJump),
    use_continue_jumps: bool = false,
    loop_depth: u32 = 0,
    closure_count: u32 = 0,
    is_generator: bool = false,
    namespace: []const u8 = "",
    use_aliases: std.StringHashMapUnmanaged([]const u8) = .{},
    file_path: []const u8 = "",
    trait_properties: std.StringHashMapUnmanaged([]const u32) = .{},

    const LoopJump = struct {
        offset: usize,
        depth: u32,
    };

    // ==================================================================
    // node dispatch
    // ==================================================================

    fn compileNode(self: *Compiler, idx: u32) Error!void {
        const node = self.ast.nodes[idx];
        switch (node.tag) {
            .expression_stmt => {
                try self.compileNode(node.data.lhs);
                try self.emitOp(.pop);
            },
            .echo_stmt => {
                for (self.ast.extraSlice(node.data.lhs)) |expr| {
                    try self.compileNode(expr);
                    try self.emitOp(.echo);
                }
            },
            .return_stmt => {
                if (self.is_generator) {
                    if (node.data.lhs != 0) {
                        try self.compileNode(node.data.lhs);
                    } else {
                        try self.emitOp(.op_null);
                    }
                    try self.emitOp(.generator_return);
                } else {
                    if (node.data.lhs != 0) {
                        try self.compileNode(node.data.lhs);
                        try self.emitOp(.return_val);
                    } else {
                        try self.emitOp(.return_void);
                    }
                }
            },
            .break_stmt => {
                const level = if (node.data.lhs > 0) node.data.lhs else 1;
                const j = try self.emitJump(.jump);
                try self.break_jumps.append(self.allocator, .{
                    .offset = j,
                    .depth = self.loop_depth -| (level - 1),
                });
            },
            .continue_stmt => {
                if (self.loop_start) |start| {
                    const level = if (node.data.lhs > 0) node.data.lhs else 1;
                    if (level > 1) {
                        // multi-level continue: emit as forward jump, parent loop handles it
                        const j = try self.emitJump(.jump);
                        try self.continue_jumps.append(self.allocator, .{
                            .offset = j,
                            .depth = self.loop_depth -| (level - 1),
                        });
                    } else if (self.use_continue_jumps) {
                        const j = try self.emitJump(.jump);
                        try self.continue_jumps.append(self.allocator, .{
                            .offset = j,
                            .depth = self.loop_depth,
                        });
                    } else {
                        try self.emitLoop(start);
                    }
                }
            },
            .block => {
                for (self.ast.extraSlice(node.data.lhs)) |stmt| {
                    try self.compileNode(stmt);
                }
            },
            .if_simple => try self.compileIfSimple(node),
            .if_else => try self.compileIfElse(node),
            .while_stmt => try self.compileWhile(node),
            .do_while => try self.compileDoWhile(node),
            .for_stmt => try self.compileFor(node),
            .foreach_stmt => try self.compileForeach(node),
            .function_decl => try self.compileFunction(node),
            .const_decl => {
                try self.compileNode(node.data.lhs);
                const name = self.ast.tokenSlice(node.main_token);
                const name_idx = try self.addConstant(.{ .string = name });
                try self.emitOp(.define_const);
                try self.emitU16(name_idx);
            },
            .switch_stmt => try self.compileSwitch(node),
            .switch_case, .switch_default => {},
            .match_expr => try self.compileMatch(node),
            .match_arm => {},
            .closure_expr => try self.compileClosure(node),
            .cast_expr => try self.compileCast(node),
            .inline_html => {
                const text = self.ast.tokenSlice(node.main_token);
                const idx2 = try self.addConstant(.{ .string = text });
                try self.emitConstant(idx2);
                try self.emitOp(.echo);
            },
            .integer_literal => try self.compileInteger(node),
            .float_literal => try self.compileFloat(node),
            .string_literal => try self.compileString(node),
            .true_literal => try self.emitOp(.op_true),
            .false_literal => try self.emitOp(.op_false),
            .null_literal => try self.emitOp(.op_null),
            .variable => try self.compileGetVar(node),
            .identifier => try self.compileGetVar(node),
            .binary_op => try self.compileBinaryOp(node),
            .assign => try self.compileAssign(node),
            .prefix_op => try self.compilePrefixOp(node),
            .postfix_op => try self.compilePostfixOp(node),
            .logical_and => try self.compileLogicalAnd(node),
            .logical_or => try self.compileLogicalOr(node),
            .null_coalesce => try self.compileNullCoalesce(node),
            .ternary => try self.compileTernary(node),
            .call => try self.compileCall(node),
            .callable_ref => try self.compileCallableRef(node),
            .array_access => try self.compileArrayAccess(node),
            .array_push_target => {},
            .list_destructure => {},
            .named_arg => try self.compileNode(node.data.lhs),
            .property_access => try self.compilePropertyAccess(node),
            .nullsafe_property_access => try self.compileNullsafePropertyAccess(node),
            .nullsafe_method_call => try self.compileNullsafeMethodCall(node),
            .throw_expr => try self.compileThrow(node),
            .try_catch => try self.compileTryCatch(node),
            .catch_clause => {},
            .class_decl => try self.compileClassDecl(node),
            .class_method, .class_property, .static_class_method, .static_class_property => {},
            .interface_decl => try self.compileInterfaceDecl(node),
            .interface_method => {},
            .trait_decl => try self.compileTraitDecl(node),
            .trait_use, .trait_insteadof, .trait_as => {},
            .enum_decl => try self.compileEnumDecl(node),
            .enum_case => {},
            .new_expr => try self.compileNewExpr(node),
            .method_call => try self.compileMethodCall(node),
            .static_call => try self.compileStaticCall(node),
            .static_prop_access => try self.compileStaticPropAccess(node),
            .yield_expr => try self.compileYield(node),
            .yield_pair_expr => try self.compileYieldPair(node),
            .yield_from_expr => try self.compileYieldFrom(node),
            .expr_list => {
                const exprs = self.ast.extraSlice(node.data.lhs);
                for (exprs, 0..) |expr, i| {
                    if (i > 0) try self.emitOp(.pop);
                    try self.compileNode(expr);
                }
            },
            .array_literal => try self.compileArrayLiteral(node),
            .array_element => {},
            .array_spread => {},
            .grouped_expr => try self.compileNode(node.data.lhs),
            .global_stmt => try self.compileGlobal(node),
            .static_var => try self.compileStaticVar(node),
            .splat_expr => {},
            .require_expr => try self.compileRequire(node),
            .namespace_decl => try self.compileNamespace(node),
            .use_stmt => try self.compileUse(node),
            .qualified_name => {
                const parts = self.ast.extraSlice(node.data.lhs);
                const fqn = try self.buildQualifiedString(parts);
                const ci = try self.addConstant(.{ .string = fqn });
                try self.emitConstant(ci);
            },
            .root => {},
        }
    }

    // ==================================================================
    // literals
    // ==================================================================

    fn compileInteger(self: *Compiler, node: Ast.Node) Error!void {
        const lexeme = self.ast.tokenSlice(node.main_token);
        const val = parsePhpInt(lexeme);
        const idx = try self.addConstant(.{ .int = val });
        try self.emitConstant(idx);
    }

    fn compileFloat(self: *Compiler, node: Ast.Node) Error!void {
        const lexeme = self.ast.tokenSlice(node.main_token);
        const val = parsePhpFloat(lexeme);
        const idx = try self.addConstant(.{ .float = val });
        try self.emitConstant(idx);
    }

    fn compileString(self: *Compiler, node: Ast.Node) Error!void {
        const tok_tag = self.ast.tokens[node.main_token].tag;

        if (tok_tag == .heredoc or tok_tag == .nowdoc) {
            const body = try self.extractHeredocBody(node.main_token);
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
                try self.compileInterpolatedString(body);
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

        try self.compileInterpolatedString(inner);
    }

    fn extractHeredocBody(self: *Compiler, token_idx: u32) Error![]const u8 {
        const lexeme = self.ast.tokenSlice(token_idx);
        // lexeme is <<<LABEL\n...\n  LABEL or <<<'LABEL'\n...\n  LABEL
        var pos: usize = 3; // skip <<<
        var is_nowdoc = false;
        if (pos < lexeme.len and lexeme[pos] == '\'') {
            is_nowdoc = true;
            pos += 1;
        }
        const label_start = pos;
        while (pos < lexeme.len and (std.ascii.isAlphanumeric(lexeme[pos]) or lexeme[pos] == '_')) pos += 1;
        const label = lexeme[label_start..pos];
        if (is_nowdoc and pos < lexeme.len and lexeme[pos] == '\'') pos += 1;

        // skip to end of first line
        while (pos < lexeme.len and lexeme[pos] != '\n') pos += 1;
        if (pos < lexeme.len) pos += 1; // skip \n
        const body_start = pos;

        // find closing label from the end - scan backwards to find it
        // the lexeme ends at or after the closing label
        var end = lexeme.len;
        // strip trailing newline/semicolon after label
        if (end > 0 and lexeme[end - 1] == '\n') end -= 1;
        if (end > 0 and lexeme[end - 1] == '\r') end -= 1;
        if (end > 0 and lexeme[end - 1] == ';') end -= 1;
        // end should now point past the label
        const label_end = end;
        if (label_end >= label.len and std.mem.eql(u8, lexeme[label_end - label.len .. label_end], label)) {
            end = label_end - label.len;
        }

        // determine closing line indentation
        var indent: usize = 0;
        var scan = end;
        while (scan > body_start and scan > 0 and lexeme[scan - 1] == ' ' or (scan > body_start and scan > 0 and lexeme[scan - 1] == '\t')) {
            scan -= 1;
            indent += 1;
        }
        // actually we need to find indent from the start of the closing line
        // the closing label line starts right after the last \n before end
        var closing_line_start = end;
        while (closing_line_start > body_start and lexeme[closing_line_start - 1] != '\n') {
            closing_line_start -= 1;
        }
        indent = end - closing_line_start;

        // strip trailing \n before closing label line
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

        // strip indentation from each line
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

    fn compileInterpolatedString(self: *Compiler, s: []const u8) Error!void {
        var segment_count: u32 = 0;
        var i: usize = 0;

        while (i < s.len) {
            if (s[i] == '\\' and i + 1 < s.len) {
                if (s[i + 1] == '$') {
                    i += 2;
                    continue;
                }
            }
            if (s[i] == '{' and i + 1 < s.len and s[i + 1] == '$') {
                // emit literal segment before this
                const lit = s[0..0]; // placeholder
                _ = lit;
                break;
            }
            if (s[i] == '$' and i + 1 < s.len and (isVarStart(s[i + 1]))) {
                break;
            }
            i += 1;
        }

        // full scan approach: walk through and emit segments
        i = 0;
        var lit_start: usize = 0;

        while (i < s.len) {
            if (s[i] == '\\' and i + 1 < s.len and s[i + 1] == '$') {
                i += 2;
                continue;
            }

            if (s[i] == '{' and i + 1 < s.len and s[i + 1] == '$') {
                if (i > lit_start) {
                    try self.emitLiteralSegment(s[lit_start..i]);
                    if (segment_count > 0) try self.emitOp(.concat);
                    segment_count += 1;
                }

                const end = std.mem.indexOfScalarPos(u8, s, i, '}') orelse s.len;
                const expr_inner = s[i + 1 .. end];
                try self.emitInterpolationExpr(expr_inner);
                if (segment_count > 0) try self.emitOp(.concat);
                segment_count += 1;

                i = if (end < s.len) end + 1 else end;
                lit_start = i;
                continue;
            }

            if (s[i] == '$' and i + 1 < s.len and isVarStart(s[i + 1])) {
                if (i > lit_start) {
                    try self.emitLiteralSegment(s[lit_start..i]);
                    if (segment_count > 0) try self.emitOp(.concat);
                    segment_count += 1;
                }

                var j = i + 1;
                while (j < s.len and isVarChar(s[j])) j += 1;

                // check for simple array access: $var[...]
                if (j < s.len and s[j] == '[') {
                    const var_name = s[i..j];
                    const var_idx = try self.addConstant(.{ .string = var_name });
                    try self.emitOp(.get_var);
                    try self.emitU16(var_idx);

                    const bracket_end = std.mem.indexOfScalarPos(u8, s, j, ']') orelse s.len;
                    const key_str = s[j + 1 .. bracket_end];
                    try self.emitArrayKeyAccess(key_str);
                    if (segment_count > 0) try self.emitOp(.concat);
                    segment_count += 1;
                    i = if (bracket_end < s.len) bracket_end + 1 else bracket_end;
                } else {
                    const var_name = s[i..j];
                    const var_idx = try self.addConstant(.{ .string = var_name });
                    try self.emitOp(.get_var);
                    try self.emitU16(var_idx);
                    if (segment_count > 0) try self.emitOp(.concat);
                    segment_count += 1;
                    i = j;
                }

                lit_start = i;
                continue;
            }

            i += 1;
        }

        if (lit_start < s.len) {
            try self.emitLiteralSegment(s[lit_start..]);
            if (segment_count > 0) try self.emitOp(.concat);
            segment_count += 1;
        }

        if (segment_count == 0) {
            const idx = try self.addConstant(.{ .string = "" });
            try self.emitConstant(idx);
        }
    }

    fn emitLiteralSegment(self: *Compiler, s: []const u8) Error!void {
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

    fn emitInterpolationExpr(self: *Compiler, expr: []const u8) Error!void {
        if (expr.len == 0 or expr[0] != '$') return;

        var j: usize = 1;
        while (j < expr.len and isVarChar(expr[j])) j += 1;

        const var_name = expr[0..j];
        const var_idx = try self.addConstant(.{ .string = var_name });
        try self.emitOp(.get_var);
        try self.emitU16(var_idx);

        while (j < expr.len) {
            if (expr[j] == '[') {
                const bracket_end = findMatchingBracket(expr, j) orelse break;
                const key_str = expr[j + 1 .. bracket_end];
                try self.emitArrayKeyAccess(key_str);
                j = bracket_end + 1;
            } else if (j + 1 < expr.len and expr[j] == '-' and expr[j + 1] == '>') {
                j += 2;
                var k = j;
                while (k < expr.len and isVarChar(expr[k])) k += 1;
                if (k == j) break;
                const prop_name = expr[j..k];
                if (k < expr.len and expr[k] == '(') {
                    const paren_end = std.mem.indexOfScalarPos(u8, expr, k, ')') orelse break;
                    const name_idx = try self.addConstant(.{ .string = prop_name });
                    try self.emitOp(.method_call);
                    try self.emitU16(name_idx);
                    try self.emitByte(0);
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

    fn emitArrayKeyAccess(self: *Compiler, key: []const u8) Error!void {
        if (key.len > 0 and key[0] == '$') {
            const key_idx = try self.addConstant(.{ .string = key });
            try self.emitOp(.get_var);
            try self.emitU16(key_idx);
        } else if (key.len > 0 and (key[0] >= '0' and key[0] <= '9')) {
            const int_val = parsePhpInt(key);
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

    fn processSingleQuoteEscapes(allocator: Allocator, s: []const u8) Allocator.Error!?[]const u8 {
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

    fn processEscapes(allocator: Allocator, s: []const u8) ![]const u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        var i: usize = 0;
        while (i < s.len) {
            if (s[i] == '\\' and i + 1 < s.len) {
                switch (s[i + 1]) {
                    'n' => try buf.append(allocator, '\n'),
                    'r' => try buf.append(allocator, '\r'),
                    't' => try buf.append(allocator, '\t'),
                    'v' => try buf.append(allocator, 0x0b),
                    'e' => try buf.append(allocator, 0x1b),
                    'f' => try buf.append(allocator, 0x0c),
                    '\\' => try buf.append(allocator, '\\'),
                    '$' => try buf.append(allocator, '$'),
                    '"' => try buf.append(allocator, '"'),
                    else => {
                        try buf.append(allocator, '\\');
                        try buf.append(allocator, s[i + 1]);
                    },
                }
                i += 2;
            } else {
                try buf.append(allocator, s[i]);
                i += 1;
            }
        }
        return buf.toOwnedSlice(allocator);
    }

    // ==================================================================
    // variables
    // ==================================================================

    fn compileGetVar(self: *Compiler, node: Ast.Node) Error!void {
        const name = self.ast.tokenSlice(node.main_token);

        // magic compile-time constants
        if (std.mem.eql(u8, name, "__DIR__")) {
            const dir = self.getFileDir();
            const idx = try self.addConstant(.{ .string = dir });
            try self.emitConstant(idx);
            return;
        }
        if (std.mem.eql(u8, name, "__FILE__")) {
            const path = if (self.file_path.len > 0) self.file_path else "";
            const idx = try self.addConstant(.{ .string = path });
            try self.emitConstant(idx);
            return;
        }

        const idx = try self.addConstant(.{ .string = name });
        try self.emitOp(.get_var);
        try self.emitU16(idx);
    }

    fn getFileDir(self: *Compiler) []const u8 {
        if (self.file_path.len == 0) return ".";
        // find last / or \ separator
        var i: usize = self.file_path.len;
        while (i > 0) {
            i -= 1;
            if (self.file_path[i] == '/' or self.file_path[i] == '\\') {
                return if (i == 0) "/" else self.file_path[0..i];
            }
        }
        return ".";
    }

    fn compileAssign(self: *Compiler, node: Ast.Node) Error!void {
        const target = self.ast.nodes[node.data.lhs];
        const op_tag = self.ast.tokens[node.main_token].tag;

        if (target.tag == .list_destructure or (target.tag == .array_literal and op_tag == .equal)) {
            try self.compileNode(node.data.rhs);
            try self.compileDestructure(target);
            return;
        }

        if (target.tag == .array_push_target) {
            try self.compileNode(target.data.lhs);
            try self.compileNode(node.data.rhs);
            try self.emitOp(.array_push);
            return;
        }

        if (target.tag == .array_access) {
            if (op_tag == .question_question_equal) {
                try self.compileNode(node.data.lhs);
                const skip_jump = try self.emitJump(.jump_if_not_null);
                try self.emitOp(.pop);
                try self.compileNode(target.data.lhs);
                try self.compileNode(target.data.rhs);
                try self.compileNode(node.data.rhs);
                try self.emitOp(.array_set);
                self.patchJump(skip_jump);
                return;
            }
            try self.compileNode(target.data.lhs);
            try self.compileNode(target.data.rhs);
            try self.compileNode(node.data.rhs);
            try self.emitOp(.array_set);
            return;
        }

        if (target.tag == .property_access) {
            try self.compileNode(target.data.lhs);
            try self.compileNode(node.data.rhs);
            const prop_node = self.ast.nodes[target.data.rhs];
            var prop_name = self.ast.tokenSlice(prop_node.main_token);
            if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
            const name_idx = try self.addConstant(.{ .string = prop_name });
            try self.emitOp(.set_prop);
            try self.emitU16(name_idx);
            return;
        }

        if (target.tag == .static_prop_access) {
            const class_node = self.ast.nodes[target.data.lhs];
            const class_name = self.ast.tokenSlice(class_node.main_token);
            var prop_name = self.ast.tokenSlice(target.main_token);
            if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
            const class_idx = try self.addConstant(.{ .string = class_name });
            const prop_idx = try self.addConstant(.{ .string = prop_name });
            if (op_tag != .equal) {
                try self.emitOp(.get_static_prop);
                try self.emitU16(class_idx);
                try self.emitU16(prop_idx);
            }
            try self.compileNode(node.data.rhs);
            if (op_tag != .equal) {
                try self.emitCompoundOp(op_tag);
            }
            try self.emitOp(.set_static_prop);
            try self.emitU16(class_idx);
            try self.emitU16(prop_idx);
            return;
        }

        if (op_tag == .question_question_equal) {
            {
                try self.compileGetVar(target);
                const skip_jump = try self.emitJump(.jump_if_not_null);
                try self.emitOp(.pop);
                try self.compileNode(node.data.rhs);
                if (target.tag == .variable or target.tag == .identifier) {
                    const name = self.ast.tokenSlice(target.main_token);
                    const idx = try self.addConstant(.{ .string = name });
                    try self.emitOp(.set_var);
                    try self.emitU16(idx);
                }
                self.patchJump(skip_jump);
            }
            return;
        }

        if (op_tag != .equal) {
            try self.compileGetVar(target);
        }

        try self.compileNode(node.data.rhs);

        if (op_tag != .equal) {
            try self.emitCompoundOp(op_tag);
        }

        if (target.tag == .variable or target.tag == .identifier) {
            const name = self.ast.tokenSlice(target.main_token);
            const idx = try self.addConstant(.{ .string = name });
            try self.emitOp(.set_var);
            try self.emitU16(idx);
        }
    }

    fn compileDestructure(self: *Compiler, target: Ast.Node) Error!void {
        // array is on top of stack, we dup it for each slot then pop the extracted value after set_var
        if (target.tag == .list_destructure) {
            const slots = self.ast.extraSlice(target.data.lhs);
            for (slots, 0..) |slot, i| {
                if (slot == 0) continue;
                const slot_node = self.ast.nodes[slot];
                try self.emitOp(.dup);
                const key_idx = try self.addConstant(.{ .int = @intCast(i) });
                try self.emitOp(.constant);
                try self.emitU16(key_idx);
                try self.emitOp(.array_get);
                if (slot_node.tag == .list_destructure) {
                    try self.compileDestructure(slot_node);
                    try self.emitOp(.pop);
                } else {
                    const name = self.ast.tokenSlice(slot_node.main_token);
                    const name_idx = try self.addConstant(.{ .string = name });
                    try self.emitOp(.set_var);
                    try self.emitU16(name_idx);
                    try self.emitOp(.pop);
                }
            }
        } else if (target.tag == .array_literal) {
            const elements = self.ast.extraSlice(target.data.lhs);
            for (elements, 0..) |elem_idx, i| {
                const elem = self.ast.nodes[elem_idx];
                if (elem.tag != .array_element) continue;
                const val_node = self.ast.nodes[elem.data.lhs];
                try self.emitOp(.dup);
                if (elem.data.rhs != 0) {
                    try self.compileNode(elem.data.rhs);
                } else {
                    const key_idx = try self.addConstant(.{ .int = @intCast(i) });
                    try self.emitOp(.constant);
                    try self.emitU16(key_idx);
                }
                try self.emitOp(.array_get);
                if (val_node.tag == .list_destructure or val_node.tag == .array_literal) {
                    try self.compileDestructure(val_node);
                    try self.emitOp(.pop);
                } else {
                    const name = self.ast.tokenSlice(val_node.main_token);
                    const name_idx = try self.addConstant(.{ .string = name });
                    try self.emitOp(.set_var);
                    try self.emitU16(name_idx);
                    try self.emitOp(.pop);
                }
            }
        }
    }

    fn emitCompoundOp(self: *Compiler, tag: Token.Tag) Error!void {
        try self.emitOp(switch (tag) {
            .plus_equal => .add,
            .minus_equal => .subtract,
            .star_equal => .multiply,
            .slash_equal => .divide,
            .percent_equal => .modulo,
            .star_star_equal => .power,
            .dot_equal => .concat,
            .amp_equal => .bit_and,
            .pipe_equal => .bit_or,
            .caret_equal => .bit_xor,
            .lt_lt_equal => .shift_left,
            .gt_gt_equal => .shift_right,
            else => unreachable,
        });
    }

    // ==================================================================
    // operators
    // ==================================================================

    fn compileBinaryOp(self: *Compiler, node: Ast.Node) Error!void {
        const op_tag = self.ast.tokens[node.main_token].tag;

        if (op_tag == .kw_instanceof) {
            try self.compileNode(node.data.lhs);
            const rhs = self.ast.nodes[node.data.rhs];
            const class_name = self.ast.tokenSlice(rhs.main_token);
            const idx = try self.addConstant(.{ .string = class_name });
            try self.emitOp(.constant);
            try self.emitU16(idx);
            try self.emitOp(.instance_check);
            return;
        }

        try self.compileNode(node.data.lhs);
        try self.compileNode(node.data.rhs);
        try self.emitOp(switch (op_tag) {
            .plus => .add,
            .minus => .subtract,
            .star => .multiply,
            .slash => .divide,
            .percent => .modulo,
            .star_star => .power,
            .dot => .concat,
            .equal_equal => .equal,
            .bang_equal => .not_equal,
            .equal_equal_equal => .identical,
            .bang_equal_equal => .not_identical,
            .lt => .less,
            .lt_equal => .less_equal,
            .gt => .greater,
            .gt_equal => .greater_equal,
            .spaceship => .spaceship,
            .amp => .bit_and,
            .pipe => .bit_or,
            .caret => .bit_xor,
            .lt_lt => .shift_left,
            .gt_gt => .shift_right,
            .lt_gt => .not_equal,
            .kw_xor => .bit_xor,
            else => unreachable,
        });
    }

    fn compilePrefixOp(self: *Compiler, node: Ast.Node) Error!void {
        const op_tag = self.ast.tokens[node.main_token].tag;

        if (op_tag == .plus_plus or op_tag == .minus_minus) {
            const target = self.ast.nodes[node.data.lhs];
            if (target.tag == .property_access) {
                // stack: [obj] -> dup -> [obj, obj] -> get_prop -> [obj, val] -> +1 -> [obj, new_val] -> set_prop
                try self.compileNode(target.data.lhs);
                try self.emitOp(.dup);
                const prop_idx = try self.addConstant(.{ .string = self.propName(target) });
                try self.emitOp(.get_prop);
                try self.emitU16(prop_idx);
                try self.emitConstant(try self.addConstant(.{ .int = 1 }));
                try self.emitOp(if (op_tag == .plus_plus) .add else .subtract);
                try self.emitOp(.set_prop);
                try self.emitU16(prop_idx);
                return;
            }
            if (target.tag == .static_prop_access) {
                const class_node = self.ast.nodes[target.data.lhs];
                const class_name = self.ast.tokenSlice(class_node.main_token);
                var prop_name = self.ast.tokenSlice(target.main_token);
                if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
                const class_idx = try self.addConstant(.{ .string = class_name });
                const sprop_idx = try self.addConstant(.{ .string = prop_name });
                try self.emitOp(.get_static_prop);
                try self.emitU16(class_idx);
                try self.emitU16(sprop_idx);
                try self.emitConstant(try self.addConstant(.{ .int = 1 }));
                try self.emitOp(if (op_tag == .plus_plus) .add else .subtract);
                try self.emitOp(.set_static_prop);
                try self.emitU16(class_idx);
                try self.emitU16(sprop_idx);
                return;
            }
            try self.compileNode(node.data.lhs);
            try self.emitConstant(try self.addConstant(.{ .int = 1 }));
            try self.emitOp(if (op_tag == .plus_plus) .add else .subtract);
            if (target.tag == .variable) {
                const name = self.ast.tokenSlice(target.main_token);
                const idx = try self.addConstant(.{ .string = name });
                try self.emitOp(.set_var);
                try self.emitU16(idx);
            }
            return;
        }

        if (op_tag == .at) {
            try self.compileNode(node.data.lhs);
            return;
        }
        if (op_tag == .kw_clone) {
            try self.compileNode(node.data.lhs);
            try self.emitOp(.clone_obj);
            return;
        }
        try self.compileNode(node.data.lhs);
        try self.emitOp(switch (op_tag) {
            .minus => .negate,
            .bang => .not,
            .tilde => .bit_not,
            else => unreachable,
        });
    }

    fn compilePostfixOp(self: *Compiler, node: Ast.Node) Error!void {
        const target = self.ast.nodes[node.data.lhs];
        const op_tag = self.ast.tokens[node.main_token].tag;

        if (target.tag == .property_access) {
            const prop_idx = try self.addConstant(.{ .string = self.propName(target) });
            // get old value (the postfix return value)
            try self.compileNode(target.data.lhs);
            try self.emitOp(.get_prop);
            try self.emitU16(prop_idx);
            // stack: [old_val]
            // now set obj.prop = old_val +/- 1
            try self.compileNode(target.data.lhs);
            try self.compileNode(target.data.lhs);
            try self.emitOp(.get_prop);
            try self.emitU16(prop_idx);
            try self.emitConstant(try self.addConstant(.{ .int = 1 }));
            try self.emitOp(if (op_tag == .plus_plus) .add else .subtract);
            try self.emitOp(.set_prop);
            try self.emitU16(prop_idx);
            try self.emitOp(.pop);
            return;
        }

        if (target.tag == .static_prop_access) {
            const class_node = self.ast.nodes[target.data.lhs];
            var class_name = self.ast.tokenSlice(class_node.main_token);
            if (std.mem.eql(u8, class_name, "self") or std.mem.eql(u8, class_name, "static") or std.mem.eql(u8, class_name, "parent")) {} else {
                class_name = self.ast.tokenSlice(class_node.main_token);
            }
            var prop_name = self.ast.tokenSlice(target.main_token);
            if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
            const class_idx = try self.addConstant(.{ .string = class_name });
            const sprop_idx = try self.addConstant(.{ .string = prop_name });
            try self.emitOp(.get_static_prop);
            try self.emitU16(class_idx);
            try self.emitU16(sprop_idx);
            try self.emitOp(.get_static_prop);
            try self.emitU16(class_idx);
            try self.emitU16(sprop_idx);
            try self.emitConstant(try self.addConstant(.{ .int = 1 }));
            try self.emitOp(if (op_tag == .plus_plus) .add else .subtract);
            try self.emitOp(.set_static_prop);
            try self.emitU16(class_idx);
            try self.emitU16(sprop_idx);
            try self.emitOp(.pop);
            return;
        }

        try self.compileNode(node.data.lhs);
        try self.compileNode(node.data.lhs);
        try self.emitConstant(try self.addConstant(.{ .int = 1 }));
        try self.emitOp(if (op_tag == .plus_plus) .add else .subtract);

        if (target.tag == .variable) {
            const name = self.ast.tokenSlice(target.main_token);
            const idx = try self.addConstant(.{ .string = name });
            try self.emitOp(.set_var);
            try self.emitU16(idx);
            try self.emitOp(.pop);
        }
    }

    // ==================================================================
    // short-circuit
    // ==================================================================

    fn compileLogicalAnd(self: *Compiler, node: Ast.Node) Error!void {
        try self.compileNode(node.data.lhs);
        const end_jump = try self.emitJump(.jump_if_false);
        try self.emitOp(.pop);
        try self.compileNode(node.data.rhs);
        self.patchJump(end_jump);
    }

    fn compileLogicalOr(self: *Compiler, node: Ast.Node) Error!void {
        try self.compileNode(node.data.lhs);
        const end_jump = try self.emitJump(.jump_if_true);
        try self.emitOp(.pop);
        try self.compileNode(node.data.rhs);
        self.patchJump(end_jump);
    }

    fn compileNullCoalesce(self: *Compiler, node: Ast.Node) Error!void {
        try self.compileNode(node.data.lhs);
        const end_jump = try self.emitJump(.jump_if_not_null);
        try self.emitOp(.pop);
        try self.compileNode(node.data.rhs);
        self.patchJump(end_jump);
    }

    fn compileTernary(self: *Compiler, node: Ast.Node) Error!void {
        const then_node = self.ast.extra_data[node.data.rhs];
        const else_node = self.ast.extra_data[node.data.rhs + 1];

        try self.compileNode(node.data.lhs);
        const else_jump = try self.emitJump(.jump_if_false);
        try self.emitOp(.pop);

        if (then_node != 0) {
            try self.compileNode(then_node);
        } else {
            try self.compileNode(node.data.lhs);
        }

        const end_jump = try self.emitJump(.jump);
        self.patchJump(else_jump);
        try self.emitOp(.pop);
        try self.compileNode(else_node);
        self.patchJump(end_jump);
    }

    // ==================================================================
    // control flow
    // ==================================================================

    fn compileIfSimple(self: *Compiler, node: Ast.Node) Error!void {
        try self.compileNode(node.data.lhs);
        const then_jump = try self.emitJump(.jump_if_false);
        try self.emitOp(.pop);
        try self.compileNode(node.data.rhs);
        const end_jump = try self.emitJump(.jump);
        self.patchJump(then_jump);
        try self.emitOp(.pop);
        self.patchJump(end_jump);
    }

    fn compileIfElse(self: *Compiler, node: Ast.Node) Error!void {
        const then_node = self.ast.extra_data[node.data.rhs];
        const else_node = self.ast.extra_data[node.data.rhs + 1];

        try self.compileNode(node.data.lhs);
        const then_jump = try self.emitJump(.jump_if_false);
        try self.emitOp(.pop);
        try self.compileNode(then_node);
        const else_jump = try self.emitJump(.jump);
        self.patchJump(then_jump);
        try self.emitOp(.pop);
        try self.compileNode(else_node);
        self.patchJump(else_jump);
    }

    fn patchBreaks(self: *Compiler, prev_breaks: *std.ArrayListUnmanaged(LoopJump)) Error!void {
        for (self.break_jumps.items) |bj| {
            if (bj.depth < self.loop_depth) {
                // target is an outer loop - propagate up
                try prev_breaks.append(self.allocator, bj);
            } else {
                self.patchJump(bj.offset);
            }
        }
        self.break_jumps.deinit(self.allocator);
    }

    fn patchContinues(self: *Compiler, prev_continues: *std.ArrayListUnmanaged(LoopJump)) Error!void {
        for (self.continue_jumps.items) |cj| {
            if (cj.depth < self.loop_depth) {
                try prev_continues.append(self.allocator, cj);
            } else {
                self.patchJump(cj.offset);
            }
        }
        self.continue_jumps.deinit(self.allocator);
    }

    fn compileWhile(self: *Compiler, node: Ast.Node) Error!void {
        const prev_start = self.loop_start;
        var prev_breaks = self.break_jumps;
        var prev_continues = self.continue_jumps;
        self.break_jumps = .{};
        self.continue_jumps = .{};
        self.loop_depth += 1;

        const loop_top = self.chunk.offset();
        self.loop_start = loop_top;

        try self.compileNode(node.data.lhs);
        const exit_jump = try self.emitJump(.jump_if_false);
        try self.emitOp(.pop);
        try self.compileNode(node.data.rhs);
        try self.emitLoop(loop_top);
        self.patchJump(exit_jump);
        try self.emitOp(.pop);

        try self.patchBreaks(&prev_breaks);
        try self.patchContinues(&prev_continues);
        self.break_jumps = prev_breaks;
        self.continue_jumps = prev_continues;
        self.loop_depth -= 1;
        self.loop_start = prev_start;
    }

    fn compileDoWhile(self: *Compiler, node: Ast.Node) Error!void {
        const prev_start = self.loop_start;
        var prev_breaks = self.break_jumps;
        var prev_continues = self.continue_jumps;
        self.break_jumps = .{};
        self.continue_jumps = .{};
        self.loop_depth += 1;

        const loop_top = self.chunk.offset();
        self.loop_start = loop_top;

        try self.compileNode(node.data.lhs);
        try self.compileNode(node.data.rhs);
        const exit_jump = try self.emitJump(.jump_if_false);
        try self.emitOp(.pop);
        try self.emitLoop(loop_top);
        self.patchJump(exit_jump);
        try self.emitOp(.pop);

        try self.patchBreaks(&prev_breaks);
        try self.patchContinues(&prev_continues);
        self.break_jumps = prev_breaks;
        self.continue_jumps = prev_continues;
        self.loop_depth -= 1;
        self.loop_start = prev_start;
    }

    fn compileFor(self: *Compiler, node: Ast.Node) Error!void {
        const init_n = self.ast.extra_data[node.data.lhs];
        const cond_n = self.ast.extra_data[node.data.lhs + 1];
        const update_n = self.ast.extra_data[node.data.lhs + 2];

        const prev_start = self.loop_start;
        var prev_breaks = self.break_jumps;
        var prev_continues = self.continue_jumps;
        const prev_use_cj = self.use_continue_jumps;
        self.break_jumps = .{};
        self.continue_jumps = .{};
        self.use_continue_jumps = (update_n != 0);
        self.loop_depth += 1;

        if (init_n != 0) {
            try self.compileNode(init_n);
            try self.emitOp(.pop);
        }

        const loop_top = self.chunk.offset();
        self.loop_start = loop_top;

        var exit_jump: ?usize = null;
        if (cond_n != 0) {
            try self.compileNode(cond_n);
            exit_jump = try self.emitJump(.jump_if_false);
            try self.emitOp(.pop);
        }

        try self.compileNode(node.data.rhs);

        // continue lands here - patch continue forward jumps for this depth
        try self.patchContinues(&prev_continues);

        if (update_n != 0) {
            try self.compileNode(update_n);
            try self.emitOp(.pop);
        }

        try self.emitLoop(loop_top);

        if (exit_jump) |ej| {
            self.patchJump(ej);
            try self.emitOp(.pop);
        }

        try self.patchBreaks(&prev_breaks);
        self.break_jumps = prev_breaks;
        self.continue_jumps = prev_continues;
        self.use_continue_jumps = prev_use_cj;
        self.loop_depth -= 1;
        self.loop_start = prev_start;
    }

    // ==================================================================
    // functions
    // ==================================================================

    fn compileFunction(self: *Compiler, node: Ast.Node) Error!void {
        const name_tok = node.main_token;
        const name = self.ast.tokenSlice(name_tok);
        const param_nodes = self.ast.extraSlice(node.data.lhs);

        const param_names = try self.allocator.alloc([]const u8, param_nodes.len);
        const ref_flags = try self.allocator.alloc(bool, param_nodes.len);
        var defaults = std.ArrayListUnmanaged(Value){};
        defer defaults.deinit(self.allocator);
        var required: u8 = 0;
        var seen_default = false;
        var is_variadic = false;

        for (param_nodes, 0..) |p, i| {
            const pnode = self.ast.nodes[p];
            param_names[i] = self.ast.tokenSlice(pnode.main_token);
            ref_flags[i] = (pnode.data.rhs & 2) != 0;
            if ((pnode.data.rhs & 1) != 0) {
                // variadic param - always last
                is_variadic = true;
                try defaults.append(self.allocator, .null);
            } else if (pnode.data.lhs != 0) {
                seen_default = true;
                try defaults.append(self.allocator, self.evalConstExpr(pnode.data.lhs));
            } else {
                if (!seen_default) required += 1;
                try defaults.append(self.allocator, .null);
            }
        }
        if (!seen_default and !is_variadic) required = @intCast(param_nodes.len);

        const defaults_owned = try self.allocator.alloc(Value, defaults.items.len);
        @memcpy(defaults_owned, defaults.items);

        const gen = self.containsYield(node.data.rhs);

        var sub = Compiler{
            .ast = self.ast,
            .chunk = .{},
            .functions = .{},
            .string_allocs = .{},
            .allocator = self.allocator,
            .scope_depth = self.scope_depth + 1,
            .loop_start = null,
            .break_jumps = .{},
            .continue_jumps = .{},
            .is_generator = gen,
            .closure_count = self.closure_count,
            .file_path = self.file_path,
        };
        errdefer {
            sub.chunk.deinit(self.allocator);
            sub.break_jumps.deinit(self.allocator);
            sub.continue_jumps.deinit(self.allocator);
            sub.string_allocs.deinit(self.allocator);
        }

        try sub.compileNode(node.data.rhs);
        try sub.emitOp(.op_null);
        try sub.emitOp(if (gen) .generator_return else .return_val);
        sub.break_jumps.deinit(self.allocator);
        sub.continue_jumps.deinit(self.allocator);

        self.closure_count = sub.closure_count;

        try self.functions.append(self.allocator, .{
            .name = name,
            .arity = @intCast(param_nodes.len),
            .required_params = required,
            .is_variadic = is_variadic,
            .is_generator = gen,
            .params = param_names[0..param_nodes.len],
            .defaults = defaults_owned,
            .ref_params = ref_flags,
            .chunk = sub.chunk,
        });

        for (sub.functions.items) |f| try self.functions.append(self.allocator, f);
        sub.functions.deinit(self.allocator);
        for (sub.string_allocs.items) |s| try self.string_allocs.append(self.allocator, s);
        sub.string_allocs.deinit(self.allocator);
    }

    fn evalConstExpr(self: *Compiler, idx: u32) Value {
        const n = self.ast.nodes[idx];
        return switch (n.tag) {
            .integer_literal => blk: {
                const text = self.ast.tokenSlice(n.main_token);
                break :blk .{ .int = std.fmt.parseInt(i64, text, 10) catch 0 };
            },
            .float_literal => blk: {
                const text = self.ast.tokenSlice(n.main_token);
                break :blk .{ .float = std.fmt.parseFloat(f64, text) catch 0.0 };
            },
            .string_literal => blk: {
                const tok_tag = self.ast.tokens[n.main_token].tag;
                if (tok_tag == .heredoc or tok_tag == .nowdoc) {
                    const body = self.extractHeredocBody(n.main_token) catch "";
                    break :blk .{ .string = body };
                }
                const raw = self.ast.tokenSlice(n.main_token);
                if (raw.len >= 2) {
                    break :blk .{ .string = raw[1 .. raw.len - 1] };
                }
                break :blk .{ .string = raw };
            },
            .true_literal => .{ .bool = true },
            .false_literal => .{ .bool = false },
            .null_literal => .null,
            .prefix_op => blk: {
                const tok = self.ast.tokens[n.main_token];
                if (tok.tag == .minus) {
                    const inner = self.evalConstExpr(n.data.lhs);
                    switch (inner) {
                        .int => |v| break :blk Value{ .int = -v },
                        .float => |v| break :blk Value{ .float = -v },
                        else => {},
                    }
                }
                break :blk .null;
            },
            .array_literal => .null,
            else => .null,
        };
    }

    fn compileThrow(self: *Compiler, node: Ast.Node) Error!void {
        try self.compileNode(node.data.lhs);
        try self.emitOp(.throw);
    }

    fn compileTryCatch(self: *Compiler, node: Ast.Node) Error!void {
        const catch_count = self.ast.extra_data[node.data.rhs];
        const catch_nodes = self.ast.extra_data[node.data.rhs + 1 .. node.data.rhs + 1 + catch_count];
        const finally_node = self.ast.extra_data[node.data.rhs + 1 + catch_count];

        // emit push_handler with placeholder catch offset
        try self.emitOp(.push_handler);
        const handler_offset_pos = self.chunk.offset();
        try self.emitU16(0xffff);

        // compile try body
        try self.compileNode(node.data.lhs);

        // normal exit: pop handler and jump past catches
        try self.emitOp(.pop_handler);
        const skip_catches = try self.emitJump(.jump);

        // patch catch offset to here
        self.patchJump(handler_offset_pos);

        // exception is on the stack when we arrive here
        var end_jumps = std.ArrayListUnmanaged(usize){};
        defer end_jumps.deinit(self.allocator);

        for (catch_nodes, 0..) |catch_idx, ci| {
            const catch_node = self.ast.nodes[catch_idx];
            const types_extra = catch_node.data.lhs;
            const body_idx = catch_node.data.rhs;
            _ = ci;

            const type_count = self.ast.extra_data[types_extra];

            if (type_count > 0) {
                const type_nodes = self.ast.extra_data[types_extra + 1 .. types_extra + 1 + type_count];

                // for each type: dup exc, check instanceof, if true jump to match
                var match_jumps = std.ArrayListUnmanaged(usize){};
                defer match_jumps.deinit(self.allocator);

                for (type_nodes) |tn| {
                    try self.emitOp(.dup); // [exc, exc]
                    const type_name = self.ast.tokenSlice(self.ast.nodes[tn].main_token);
                    const tidx = try self.addConstant(.{ .string = type_name });
                    try self.emitConstant(tidx); // [exc, exc, type]
                    try self.emitOp(.instance_check); // [exc, bool]
                    const mj = try self.emitJump(.jump_if_true); // peek bool
                    try match_jumps.append(self.allocator, mj);
                    try self.emitOp(.pop); // [exc] (remove false bool)
                }

                // none matched, stack: [exc] - skip to next catch
                const skip = try self.emitJump(.jump);

                // match: stack: [exc, bool(true)]
                for (match_jumps.items) |mj| self.patchJump(mj);
                try self.emitOp(.pop); // remove bool -> [exc]

                if (catch_node.main_token != 0) {
                    const var_name = self.ast.tokenSlice(catch_node.main_token);
                    const var_idx = try self.addConstant(.{ .string = var_name });
                    try self.emitOp(.set_var);
                    try self.emitU16(var_idx);
                }
                try self.emitOp(.pop); // remove exc

                try self.compileNode(body_idx);
                const ej = try self.emitJump(.jump);
                try end_jumps.append(self.allocator, ej);

                // skip lands here, stack: [exc] (preserved for next catch)
                self.patchJump(skip);
            } else {
                // untyped catch-all
                if (catch_node.main_token != 0) {
                    const var_name = self.ast.tokenSlice(catch_node.main_token);
                    const var_idx = try self.addConstant(.{ .string = var_name });
                    try self.emitOp(.set_var);
                    try self.emitU16(var_idx);
                }
                try self.emitOp(.pop);

                try self.compileNode(body_idx);
                const ej = try self.emitJump(.jump);
                try end_jumps.append(self.allocator, ej);
            }
        }

        // if no catch matched, re-throw
        try self.emitOp(.throw);

        self.patchJump(skip_catches);
        for (end_jumps.items) |ej| self.patchJump(ej);

        // finally block runs on both paths
        if (finally_node != 0) {
            try self.compileNode(finally_node);
        }
    }

    fn compileClassDecl(self: *Compiler, node: Ast.Node) Error!void {
        const class_name = self.resolveClassName(self.ast.tokenSlice(node.main_token));
        const members = self.ast.extraSlice(node.data.lhs);

        // decode rhs: {parent_node, implements_count, impl_nodes...}
        const rhs_base = node.data.rhs;
        const parent_node = self.ast.extra_data[rhs_base];
        const impl_count = self.ast.extra_data[rhs_base + 1];
        var impl_names: [16][]const u8 = undefined;
        for (0..impl_count) |i| {
            const impl_node = self.ast.nodes[self.ast.extra_data[rhs_base + 2 + i]];
            impl_names[i] = self.ast.tokenSlice(impl_node.main_token);
        }

        var method_count: u8 = 0;
        for (members) |member_idx| {
            const member = self.ast.nodes[member_idx];
            if (member.tag == .class_method or member.tag == .static_class_method) {
                try self.compileClassMethodBody(class_name, member);
                method_count += 1;
            }
        }

        // count promoted constructor params
        var promoted_count: u8 = 0;
        var constructor_params: []const u32 = &.{};
        for (members) |member_idx| {
            const member = self.ast.nodes[member_idx];
            if (member.tag == .class_method and std.mem.eql(u8, self.ast.tokenSlice(member.main_token), "__construct")) {
                constructor_params = self.ast.extraSlice(member.data.lhs);
                for (constructor_params) |p| {
                    const pnode = self.ast.nodes[p];
                    if ((pnode.data.rhs >> 2) & 3 > 0) promoted_count += 1;
                }
                break;
            }
        }

        // collect trait property indices for this class
        var trait_prop_members = std.ArrayListUnmanaged(u32){};
        defer trait_prop_members.deinit(self.allocator);
        for (members) |member_idx| {
            const member = self.ast.nodes[member_idx];
            if (member.tag == .trait_use) {
                for (self.ast.extraSlice(member.data.lhs)) |tn| {
                    const tname = self.ast.tokenSlice(self.ast.nodes[tn].main_token);
                    if (self.trait_properties.get(tname)) |props| {
                        for (props) |pi| try trait_prop_members.append(self.allocator, pi);
                    }
                }
            }
        }

        // compile instance property defaults (push onto stack)
        var prop_count: u8 = 0;
        for (members) |member_idx| {
            const member = self.ast.nodes[member_idx];
            if (member.tag == .class_property) prop_count += 1;
        }
        prop_count += @intCast(trait_prop_members.items.len);
        prop_count += promoted_count;
        for (members) |member_idx| {
            const member = self.ast.nodes[member_idx];
            if (member.tag == .class_property) {
                if (member.data.lhs != 0) {
                    try self.compileNode(member.data.lhs);
                }
            }
        }
        // compile trait property defaults
        for (trait_prop_members.items) |tpi| {
            const tmember = self.ast.nodes[tpi];
            if (tmember.data.lhs != 0) {
                try self.compileNode(tmember.data.lhs);
            }
        }
        // promoted params get null defaults (actual values assigned in constructor body)
        for (constructor_params) |p| {
            const pnode = self.ast.nodes[p];
            if ((pnode.data.rhs >> 2) & 3 > 0) {
                try self.emitOp(.op_null);
            }
        }

        // compile static property defaults (push onto stack after instance props)
        // class constants (const_decl) are treated as static props
        var static_prop_count: u8 = 0;
        for (members) |member_idx| {
            const member = self.ast.nodes[member_idx];
            if (member.tag == .static_class_property or member.tag == .const_decl) static_prop_count += 1;
        }
        for (members) |member_idx| {
            const member = self.ast.nodes[member_idx];
            if (member.tag == .static_class_property) {
                if (member.data.lhs != 0) {
                    try self.compileNode(member.data.lhs);
                }
            } else if (member.tag == .const_decl) {
                try self.compileNode(member.data.lhs);
            }
        }

        const name_idx = try self.addConstant(.{ .string = class_name });
        try self.emitOp(.class_decl);
        try self.emitU16(name_idx);
        try self.emitByte(method_count);

        for (members) |member_idx| {
            const member = self.ast.nodes[member_idx];
            if (member.tag == .class_method or member.tag == .static_class_method) {
                const method_name_str = self.ast.tokenSlice(member.main_token);
                const mname_idx = try self.addConstant(.{ .string = method_name_str });
                try self.emitU16(mname_idx);
                const param_nodes = self.ast.extraSlice(member.data.lhs);
                try self.emitByte(@intCast(param_nodes.len));
                try self.emitByte(if (member.tag == .static_class_method) @as(u8, 1) else @as(u8, 0));
                const vis: u8 = @intCast(member.data.rhs >> 30);
                try self.emitByte(vis);
            }
        }

        try self.emitByte(prop_count);
        for (members) |member_idx| {
            const member = self.ast.nodes[member_idx];
            if (member.tag == .class_property) {
                var prop_name = self.ast.tokenSlice(member.main_token);
                if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
                const pname_idx = try self.addConstant(.{ .string = prop_name });
                try self.emitU16(pname_idx);
                try self.emitByte(if (member.data.lhs != 0) @as(u8, 1) else @as(u8, 0));
                try self.emitByte(@intCast(member.data.rhs));
            }
        }
        // trait properties
        for (trait_prop_members.items) |tpi| {
            const tmember = self.ast.nodes[tpi];
            var tprop_name = self.ast.tokenSlice(tmember.main_token);
            if (tprop_name.len > 0 and tprop_name[0] == '$') tprop_name = tprop_name[1..];
            const tpname_idx = try self.addConstant(.{ .string = tprop_name });
            try self.emitU16(tpname_idx);
            try self.emitByte(if (tmember.data.lhs != 0) @as(u8, 1) else @as(u8, 0));
            try self.emitByte(@intCast(tmember.data.rhs));
        }
        // promoted constructor params as properties
        for (constructor_params) |p| {
            const pnode = self.ast.nodes[p];
            const promotion = (pnode.data.rhs >> 2) & 3;
            if (promotion > 0) {
                var param_name = self.ast.tokenSlice(pnode.main_token);
                if (param_name.len > 0 and param_name[0] == '$') param_name = param_name[1..];
                const pname_idx = try self.addConstant(.{ .string = param_name });
                try self.emitU16(pname_idx);
                try self.emitByte(1); // has default (null placeholder)
                // bits 0-1: visibility, bit 2: readonly
                const is_ro: u8 = if ((pnode.data.rhs & 16) != 0) 4 else 0;
                try self.emitByte(@as(u8, @intCast(promotion - 1)) | is_ro);
            }
        }

        try self.emitByte(static_prop_count);
        for (members) |member_idx| {
            const member = self.ast.nodes[member_idx];
            if (member.tag == .static_class_property) {
                var prop_name = self.ast.tokenSlice(member.main_token);
                if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
                const pname_idx = try self.addConstant(.{ .string = prop_name });
                try self.emitU16(pname_idx);
                try self.emitByte(if (member.data.lhs != 0) @as(u8, 1) else @as(u8, 0));
                try self.emitByte(@intCast(member.data.rhs));
            } else if (member.tag == .const_decl) {
                const cname = self.ast.tokenSlice(member.main_token);
                const cname_idx = try self.addConstant(.{ .string = cname });
                try self.emitU16(cname_idx);
                try self.emitByte(1); // always has a value
                try self.emitByte(0); // public visibility
            }
        }

        if (parent_node != 0) {
            const parent_name = self.ast.tokenSlice(self.ast.nodes[parent_node].main_token);
            const parent_idx = try self.addConstant(.{ .string = parent_name });
            try self.emitU16(parent_idx);
        } else {
            try self.emitU16(0xffff);
        }

        // emit implements count and names
        try self.emitByte(@intCast(impl_count));
        for (0..impl_count) |i| {
            const iname_idx = try self.addConstant(.{ .string = impl_names[i] });
            try self.emitU16(iname_idx);
        }

        // collect all trait names from trait_use statements
        var all_traits = std.ArrayListUnmanaged([]const u8){};
        defer all_traits.deinit(self.allocator);
        for (members) |member_idx| {
            const member = self.ast.nodes[member_idx];
            if (member.tag == .trait_use) {
                for (self.ast.extraSlice(member.data.lhs)) |tn| {
                    try all_traits.append(self.allocator, self.ast.tokenSlice(self.ast.nodes[tn].main_token));
                }
            }
        }
        try self.emitByte(@intCast(all_traits.items.len));
        for (all_traits.items) |tname| {
            const tname_idx = try self.addConstant(.{ .string = tname });
            try self.emitU16(tname_idx);
        }

        // collect conflict resolution rules from trait_use statements
        const ConflictRule = struct { node: Ast.Node };
        var all_conflicts = std.ArrayListUnmanaged(ConflictRule){};
        defer all_conflicts.deinit(self.allocator);
        for (members) |member_idx| {
            const member = self.ast.nodes[member_idx];
            if (member.tag == .trait_use and member.data.rhs != 0) {
                for (self.ast.extraSlice(member.data.rhs)) |cn| {
                    try all_conflicts.append(self.allocator, .{ .node = self.ast.nodes[cn] });
                }
            }
        }
        try self.emitByte(@intCast(all_conflicts.items.len));
        for (all_conflicts.items) |cr| {
            const method_name = self.ast.tokenSlice(cr.node.main_token);
            const trait_name = self.ast.tokenSlice(self.ast.nodes[cr.node.data.lhs].main_token);
            const method_idx = try self.addConstant(.{ .string = method_name });
            const trait_idx = try self.addConstant(.{ .string = trait_name });
            try self.emitU16(method_idx);
            try self.emitU16(trait_idx);
            if (cr.node.tag == .trait_insteadof) {
                try self.emitByte(1);
                const excluded = self.ast.extraSlice(cr.node.data.rhs);
                try self.emitByte(@intCast(excluded.len));
                for (excluded) |en| {
                    const ename = self.ast.tokenSlice(self.ast.nodes[en].main_token);
                    const eidx = try self.addConstant(.{ .string = ename });
                    try self.emitU16(eidx);
                }
            } else {
                try self.emitByte(2);
                const alias = self.ast.tokenSlice(cr.node.data.rhs);
                const aidx = try self.addConstant(.{ .string = alias });
                try self.emitU16(aidx);
            }
        }
    }

    fn compileInterfaceDecl(self: *Compiler, node: Ast.Node) Error!void {
        const iface_name = self.ast.tokenSlice(node.main_token);
        const members = self.ast.extraSlice(node.data.lhs);

        var method_count: u8 = 0;
        for (members) |m| {
            if (self.ast.nodes[m].tag == .interface_method) method_count += 1;
        }

        const name_idx = try self.addConstant(.{ .string = iface_name });
        try self.emitOp(.interface_decl);
        try self.emitU16(name_idx);
        try self.emitByte(method_count);

        for (members) |m| {
            const member = self.ast.nodes[m];
            if (member.tag == .interface_method) {
                const mname = self.ast.tokenSlice(member.main_token);
                const mname_idx = try self.addConstant(.{ .string = mname });
                try self.emitU16(mname_idx);
            }
        }

        if (node.data.rhs != 0) {
            const parent_name = self.ast.tokenSlice(self.ast.nodes[node.data.rhs].main_token);
            const pidx = try self.addConstant(.{ .string = parent_name });
            try self.emitU16(pidx);
        } else {
            try self.emitU16(0xffff);
        }
    }

    fn compileTraitDecl(self: *Compiler, node: Ast.Node) Error!void {
        const trait_name = self.ast.tokenSlice(node.main_token);
        const members = self.ast.extraSlice(node.data.lhs);

        // compile trait methods as TraitName::methodName functions
        for (members) |member_idx| {
            const member = self.ast.nodes[member_idx];
            if (member.tag == .class_method or member.tag == .static_class_method) {
                try self.compileClassMethodBody(trait_name, member);
            }
        }

        // store property member indices for classes that use this trait
        var prop_indices = std.ArrayListUnmanaged(u32){};
        for (members) |member_idx| {
            const member = self.ast.nodes[member_idx];
            if (member.tag == .class_property) {
                try prop_indices.append(self.allocator, member_idx);
            }
        }
        if (prop_indices.items.len > 0) {
            const owned = try prop_indices.toOwnedSlice(self.allocator);
            try self.trait_properties.put(self.allocator, trait_name, owned);
        } else {
            prop_indices.deinit(self.allocator);
        }

        const name_idx = try self.addConstant(.{ .string = trait_name });
        try self.emitOp(.trait_decl);
        try self.emitU16(name_idx);
    }

    fn compileEnumDecl(self: *Compiler, node: Ast.Node) Error!void {
        const enum_name = self.ast.tokenSlice(node.main_token);
        const members = self.ast.extraSlice(node.data.lhs);

        const rhs_base = node.data.rhs;
        const backed_type_token = self.ast.extra_data[rhs_base];
        const impl_count = self.ast.extra_data[rhs_base + 1];

        var backed_type: u8 = 0; // 0=none, 1=int, 2=string
        if (backed_type_token != 0) {
            const type_str = self.ast.tokenSlice(backed_type_token);
            if (std.mem.eql(u8, type_str, "int")) {
                backed_type = 1;
            } else if (std.mem.eql(u8, type_str, "string")) {
                backed_type = 2;
            }
        }

        var method_count: u8 = 0;
        for (members) |member_idx| {
            const member = self.ast.nodes[member_idx];
            if (member.tag == .class_method or member.tag == .static_class_method) {
                try self.compileClassMethodBody(enum_name, member);
                method_count += 1;
            }
        }

        var case_count: u8 = 0;
        for (members) |member_idx| {
            const member = self.ast.nodes[member_idx];
            if (member.tag == .enum_case) {
                if (member.data.lhs != 0) {
                    try self.compileNode(member.data.lhs);
                }
                case_count += 1;
            }
        }

        const name_idx = try self.addConstant(.{ .string = enum_name });
        try self.emitOp(.enum_decl);
        try self.emitU16(name_idx);
        try self.emitByte(backed_type);
        try self.emitByte(case_count);

        for (members) |member_idx| {
            const member = self.ast.nodes[member_idx];
            if (member.tag == .enum_case) {
                const case_name = self.ast.tokenSlice(member.main_token);
                const cname_idx = try self.addConstant(.{ .string = case_name });
                try self.emitU16(cname_idx);
                try self.emitByte(if (member.data.lhs != 0) @as(u8, 1) else @as(u8, 0));
            }
        }

        try self.emitByte(method_count);
        for (members) |member_idx| {
            const member = self.ast.nodes[member_idx];
            if (member.tag == .class_method or member.tag == .static_class_method) {
                const method_name_str = self.ast.tokenSlice(member.main_token);
                const mname_idx = try self.addConstant(.{ .string = method_name_str });
                try self.emitU16(mname_idx);
                const param_nodes = self.ast.extraSlice(member.data.lhs);
                try self.emitByte(@intCast(param_nodes.len));
                try self.emitByte(if (member.tag == .static_class_method) @as(u8, 1) else @as(u8, 0));
                const vis: u8 = @intCast(member.data.rhs >> 30);
                try self.emitByte(vis);
            }
        }

        try self.emitByte(@intCast(impl_count));
        for (0..impl_count) |i| {
            const impl_node = self.ast.nodes[self.ast.extra_data[rhs_base + 2 + i]];
            const iname_idx = try self.addConstant(.{ .string = self.ast.tokenSlice(impl_node.main_token) });
            try self.emitU16(iname_idx);
        }
    }

    fn compileClassMethodBody(self: *Compiler, class_name: []const u8, member: Ast.Node) Error!void {
        const method_name = self.ast.tokenSlice(member.main_token);
        const full_name = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ class_name, method_name });
        try self.string_allocs.append(self.allocator, full_name);

        const param_nodes = self.ast.extraSlice(member.data.lhs);
        const param_names = try self.allocator.alloc([]const u8, param_nodes.len);
        const ref_flags = try self.allocator.alloc(bool, param_nodes.len);
        for (param_nodes, 0..) |p, i| {
            const pnode = self.ast.nodes[p];
            param_names[i] = self.ast.tokenSlice(pnode.main_token);
            ref_flags[i] = (pnode.data.rhs & 2) != 0;
        }

        var defaults = std.ArrayListUnmanaged(Value){};
        defer defaults.deinit(self.allocator);
        var required: u8 = 0;
        var seen_default = false;
        var is_variadic = false;
        for (param_nodes) |p| {
            const pnode = self.ast.nodes[p];
            if ((pnode.data.rhs & 1) != 0) {
                is_variadic = true;
                try defaults.append(self.allocator, .null);
            } else if (pnode.data.lhs != 0) {
                seen_default = true;
                try defaults.append(self.allocator, self.evalConstExpr(pnode.data.lhs));
            } else {
                if (!seen_default) required += 1;
                try defaults.append(self.allocator, .null);
            }
        }
        if (!seen_default and !is_variadic) required = @intCast(param_nodes.len);
        const defaults_owned = try self.allocator.alloc(Value, defaults.items.len);
        @memcpy(defaults_owned, defaults.items);

        var sub = Compiler{
            .ast = self.ast,
            .chunk = .{},
            .functions = .{},
            .string_allocs = .{},
            .allocator = self.allocator,
            .scope_depth = self.scope_depth + 1,
            .loop_start = null,
            .break_jumps = .{},
            .continue_jumps = .{},
            .closure_count = self.closure_count,
            .file_path = self.file_path,
        };
        errdefer {
            sub.chunk.deinit(self.allocator);
            sub.break_jumps.deinit(self.allocator);
            sub.continue_jumps.deinit(self.allocator);
            sub.string_allocs.deinit(self.allocator);
        }

        // constructor property promotion: emit $this->prop = $prop for each promoted param
        if (std.mem.eql(u8, method_name, "__construct")) {
            for (param_nodes) |p| {
                const pnode = self.ast.nodes[p];
                const promotion = (pnode.data.rhs >> 2) & 3;
                if (promotion > 0) {
                    var param_name = self.ast.tokenSlice(pnode.main_token);
                    const this_idx = try sub.addConstant(.{ .string = "$this" });
                    const var_idx = try sub.addConstant(.{ .string = param_name });
                    try sub.emitOp(.get_var);
                    try sub.emitU16(this_idx);
                    try sub.emitOp(.get_var);
                    try sub.emitU16(var_idx);
                    if (param_name.len > 0 and param_name[0] == '$') param_name = param_name[1..];
                    const prop_idx = try sub.addConstant(.{ .string = param_name });
                    try sub.emitOp(.set_prop);
                    try sub.emitU16(prop_idx);
                    try sub.emitOp(.pop);
                }
            }
        }

        const body_idx = member.data.rhs & 0x3FFFFFFF;
        try sub.compileNode(body_idx);
        try sub.emitOp(.op_null);
        try sub.emitOp(.return_val);
        sub.break_jumps.deinit(self.allocator);

        self.closure_count = sub.closure_count;

        try self.functions.append(self.allocator, .{
            .name = full_name,
            .arity = @intCast(param_nodes.len),
            .required_params = required,
            .is_variadic = is_variadic,
            .params = param_names[0..param_nodes.len],
            .defaults = defaults_owned,
            .ref_params = ref_flags,
            .chunk = sub.chunk,
        });

        for (sub.functions.items) |f| try self.functions.append(self.allocator, f);
        sub.functions.deinit(self.allocator);
        for (sub.string_allocs.items) |s| try self.string_allocs.append(self.allocator, s);
        sub.string_allocs.deinit(self.allocator);
    }

    fn compileNewExpr(self: *Compiler, node: Ast.Node) Error!void {
        const raw_name = try self.resolveQualifiedNewName(node);
        const class_name = if (std.mem.indexOf(u8, raw_name, "\\") != null) raw_name else self.resolveClassName(raw_name);
        const args = self.ast.extraSlice(node.data.lhs);
        for (args) |arg| try self.compileNode(arg);
        const name_idx = try self.addConstant(.{ .string = class_name });
        try self.emitOp(.new_obj);
        try self.emitU16(name_idx);
        try self.emitByte(@intCast(args.len));
    }

    fn resolveQualifiedNewName(self: *Compiler, node: Ast.Node) ![]const u8 {
        const first = self.ast.tokenSlice(node.main_token);
        if (node.data.rhs == 0) return first;
        const parts = self.ast.extraSlice(node.data.rhs);
        var buf = std.ArrayListUnmanaged(u8){};
        try buf.appendSlice(self.allocator, first);
        for (parts[1..]) |part_tok| {
            try buf.append(self.allocator, '\\');
            try buf.appendSlice(self.allocator, self.ast.tokenSlice(part_tok));
        }
        const owned = try buf.toOwnedSlice(self.allocator);
        try self.string_allocs.append(self.allocator, owned);
        return owned;
    }

    fn propName(self: *Compiler, node: Ast.Node) []const u8 {
        const prop_node = self.ast.nodes[node.data.rhs];
        var name = self.ast.tokenSlice(prop_node.main_token);
        if (name.len > 0 and name[0] == '$') name = name[1..];
        return name;
    }

    fn compilePropertyAccess(self: *Compiler, node: Ast.Node) Error!void {
        try self.compileNode(node.data.lhs);
        const name_idx = try self.addConstant(.{ .string = self.propName(node) });
        try self.emitOp(.get_prop);
        try self.emitU16(name_idx);
    }

    fn compileMethodCall(self: *Compiler, node: Ast.Node) Error!void {
        try self.compileNode(node.data.lhs);
        const args = self.ast.extraSlice(node.data.rhs);
        const method_name = self.ast.tokenSlice(node.main_token);
        const name_idx = try self.addConstant(.{ .string = method_name });

        if (hasSplatOrNamed(self.ast, args)) {
            try self.emitSpreadArgs(args);
            try self.emitOp(.method_call_spread);
            try self.emitU16(name_idx);
        } else {
            for (args) |arg| try self.compileNode(arg);
            try self.emitOp(.method_call);
            try self.emitU16(name_idx);
            try self.emitByte(@intCast(args.len));
        }
    }

    fn compileNullsafePropertyAccess(self: *Compiler, node: Ast.Node) Error!void {
        try self.compileNode(node.data.lhs);
        const skip_jump = try self.emitJump(.jump_if_not_null);
        const end_jump = try self.emitJump(.jump);
        self.patchJump(skip_jump);
        const name_idx = try self.addConstant(.{ .string = self.propName(node) });
        try self.emitOp(.get_prop);
        try self.emitU16(name_idx);
        self.patchJump(end_jump);
    }

    fn compileNullsafeMethodCall(self: *Compiler, node: Ast.Node) Error!void {
        try self.compileNode(node.data.lhs);
        const skip_jump = try self.emitJump(.jump_if_not_null);
        const end_jump = try self.emitJump(.jump);
        self.patchJump(skip_jump);
        const args = self.ast.extraSlice(node.data.rhs);
        const method_name = self.ast.tokenSlice(node.main_token);
        const name_idx = try self.addConstant(.{ .string = method_name });

        if (hasSplatOrNamed(self.ast, args)) {
            try self.emitSpreadArgs(args);
            try self.emitOp(.method_call_spread);
            try self.emitU16(name_idx);
        } else {
            for (args) |arg| try self.compileNode(arg);
            try self.emitOp(.method_call);
            try self.emitU16(name_idx);
            try self.emitByte(@intCast(args.len));
        }
        self.patchJump(end_jump);
    }

    fn resolveNodeClassName(self: *Compiler, class_node: Ast.Node) ![]const u8 {
        if (class_node.tag == .qualified_name) {
            const parts = self.ast.extraSlice(class_node.data.lhs);
            return try self.buildQualifiedString(parts);
        }
        return self.resolveClassName(self.ast.tokenSlice(class_node.main_token));
    }

    fn compileStaticCall(self: *Compiler, node: Ast.Node) Error!void {
        const class_node = self.ast.nodes[node.data.lhs];
        const class_name = try self.resolveNodeClassName(class_node);
        const method_name = self.ast.tokenSlice(node.main_token);
        const args = self.ast.extraSlice(node.data.rhs);
        const class_idx = try self.addConstant(.{ .string = class_name });
        const method_idx = try self.addConstant(.{ .string = method_name });

        if (hasSplatOrNamed(self.ast, args)) {
            try self.emitSpreadArgs(args);
            try self.emitOp(.static_call_spread);
            try self.emitU16(class_idx);
            try self.emitU16(method_idx);
        } else {
            for (args) |arg| try self.compileNode(arg);
            try self.emitOp(.static_call);
            try self.emitU16(class_idx);
            try self.emitU16(method_idx);
            try self.emitByte(@intCast(args.len));
        }
    }

    fn compileStaticPropAccess(self: *Compiler, node: Ast.Node) Error!void {
        const class_node = self.ast.nodes[node.data.lhs];
        const class_name = try self.resolveNodeClassName(class_node);
        var prop_name = self.ast.tokenSlice(node.main_token);
        if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
        const class_idx = try self.addConstant(.{ .string = class_name });
        const prop_idx = try self.addConstant(.{ .string = prop_name });
        try self.emitOp(.get_static_prop);
        try self.emitU16(class_idx);
        try self.emitU16(prop_idx);
    }

    fn compileYield(self: *Compiler, node: Ast.Node) Error!void {
        if (node.data.lhs != 0) {
            try self.compileNode(node.data.lhs);
        } else {
            try self.emitOp(.op_null);
        }
        try self.emitOp(.yield_value);
    }

    fn compileYieldFrom(self: *Compiler, node: Ast.Node) Error!void {
        try self.compileNode(node.data.lhs);
        try self.emitOp(.yield_from);
    }

    fn compileYieldPair(self: *Compiler, node: Ast.Node) Error!void {
        try self.compileNode(node.data.lhs);
        try self.compileNode(node.data.rhs);
        try self.emitOp(.yield_pair);
    }

    fn containsYield(self: *Compiler, idx: u32) bool {
        if (idx == 0 or idx >= self.ast.nodes.len) return false;
        const n = self.ast.nodes[idx];
        if (n.tag == .yield_expr or n.tag == .yield_pair_expr or n.tag == .yield_from_expr) return true;

        // boundaries: don't descend into nested functions/classes
        if (n.tag == .function_decl or n.tag == .closure_expr) return false;
        if (n.tag == .class_decl or n.tag == .interface_decl or n.tag == .trait_decl) return false;
        if (n.tag == .enum_decl) return false;

        // lhs = extra_data list of children
        if (n.tag == .block or n.tag == .root or n.tag == .echo_stmt or
            n.tag == .array_literal or n.tag == .global_stmt or
            n.tag == .list_destructure or n.tag == .expr_list)
        {
            for (self.ast.extraSlice(n.data.lhs)) |child| {
                if (self.containsYield(child)) return true;
            }
            return false;
        }

        // lhs = extra_data list of children, rhs = extra_data list of children
        if (n.tag == .switch_case) {
            for (self.ast.extraSlice(n.data.lhs)) |child| {
                if (self.containsYield(child)) return true;
            }
            for (self.ast.extraSlice(n.data.rhs)) |child| {
                if (self.containsYield(child)) return true;
            }
            return false;
        }
        if (n.tag == .switch_default) {
            for (self.ast.extraSlice(n.data.lhs)) |child| {
                if (self.containsYield(child)) return true;
            }
            return false;
        }

        // lhs = condition (node), rhs = extra {then, else}
        if (n.tag == .if_else) {
            if (self.containsYield(n.data.lhs)) return true;
            const extra = self.ast.extra_data[n.data.rhs .. n.data.rhs + 2];
            return self.containsYield(extra[0]) or self.containsYield(extra[1]);
        }
        // lhs = condition (node), rhs = extra {then, else} (or 0)
        if (n.tag == .ternary) {
            if (self.containsYield(n.data.lhs)) return true;
            const extra = self.ast.extra_data[n.data.rhs .. n.data.rhs + 2];
            if (self.containsYield(extra[0])) return true;
            return self.containsYield(extra[1]);
        }

        // lhs = extra {init, cond, update}, rhs = body (node)
        if (n.tag == .for_stmt) {
            const parts = self.ast.extra_data[n.data.lhs .. n.data.lhs + 3];
            for (parts) |child| {
                if (self.containsYield(child)) return true;
            }
            return self.containsYield(n.data.rhs);
        }
        // lhs = extra {iter, val, key}, rhs = body (node)
        if (n.tag == .foreach_stmt) {
            const iter_n = self.ast.extra_data[n.data.lhs];
            if (self.containsYield(iter_n)) return true;
            return self.containsYield(n.data.rhs);
        }

        // lhs = callee (node), rhs = extra args
        if (n.tag == .call or n.tag == .method_call or n.tag == .static_call or n.tag == .nullsafe_method_call) {
            if (self.containsYield(n.data.lhs)) return true;
            for (self.ast.extraSlice(n.data.rhs)) |child| {
                if (self.containsYield(child)) return true;
            }
            return false;
        }
        // lhs = extra args
        if (n.tag == .new_expr) {
            for (self.ast.extraSlice(n.data.lhs)) |child| {
                if (self.containsYield(child)) return true;
            }
            return false;
        }

        // lhs = condition (node), rhs = extra cases
        if (n.tag == .switch_stmt or n.tag == .match_expr) {
            if (self.containsYield(n.data.lhs)) return true;
            for (self.ast.extraSlice(n.data.rhs)) |child| {
                if (self.containsYield(child)) return true;
            }
            return false;
        }
        // match_arm: lhs = extra values, rhs = result (node)
        if (n.tag == .match_arm) {
            for (self.ast.extraSlice(n.data.lhs)) |child| {
                if (self.containsYield(child)) return true;
            }
            return self.containsYield(n.data.rhs);
        }

        // lhs = try body (node), rhs = extra {catch_count, catches..., finally_or_0}
        if (n.tag == .try_catch) {
            if (self.containsYield(n.data.lhs)) return true;
            for (self.ast.extraSlice(n.data.rhs)) |child| {
                if (self.containsYield(child)) return true;
            }
            return false;
        }

        // tags where both lhs and rhs are node indices (safe to recurse)
        switch (n.tag) {
            .expression_stmt, .return_stmt, .assign, .binary_op,
            .prefix_op, .postfix_op, .logical_and, .logical_or,
            .null_coalesce, .if_simple, .while_stmt, .do_while,
            .array_access, .array_push_target, .array_element,
            .array_spread, .grouped_expr, .throw_expr, .catch_clause,
            .cast_expr, .property_access, .nullsafe_property_access,
            .static_prop_access, .splat_expr, .require_expr,
            .yield_expr, .yield_pair_expr, .yield_from_expr,
            .callable_ref, .named_arg,
            => {
                if (n.data.lhs != 0 and n.data.lhs < self.ast.nodes.len and self.containsYield(n.data.lhs)) return true;
                if (n.data.rhs != 0 and n.data.rhs < self.ast.nodes.len and self.containsYield(n.data.rhs)) return true;
                return false;
            },
            else => return false,
        }
    }

    fn compileSwitch(self: *Compiler, node: Ast.Node) Error!void {
        const prev_start = self.loop_start;
        const prev_breaks = self.break_jumps;
        self.break_jumps = .{};
        self.loop_start = null;

        try self.compileNode(node.data.lhs);
        const temp_name = try std.fmt.allocPrint(self.allocator, "__switch_{d}", .{self.closure_count});
        try self.string_allocs.append(self.allocator, temp_name);
        self.closure_count += 1;
        const temp_idx = try self.addConstant(.{ .string = temp_name });
        try self.emitOp(.set_var);
        try self.emitU16(temp_idx);
        try self.emitOp(.pop);

        const case_nodes = self.ast.extraSlice(node.data.rhs);

        // phase 1: emit comparison chain, collect jumps to bodies
        var body_jumps = std.ArrayListUnmanaged(usize){};
        defer body_jumps.deinit(self.allocator);
        var default_jump: ?usize = null;

        for (case_nodes) |case_idx| {
            const case_node = self.ast.nodes[case_idx];
            if (case_node.tag == .switch_default) {
                try body_jumps.append(self.allocator, 0);
                continue;
            }

            const values = self.ast.extraSlice(case_node.data.lhs);
            var hit_jumps = std.ArrayListUnmanaged(usize){};
            defer hit_jumps.deinit(self.allocator);

            for (values, 0..) |val, vi| {
                try self.emitOp(.get_var);
                try self.emitU16(temp_idx);
                try self.compileNode(val);
                try self.emitOp(.equal);
                if (vi < values.len - 1) {
                    const hit = try self.emitJump(.jump_if_true);
                    try hit_jumps.append(self.allocator, hit);
                    try self.emitOp(.pop);
                } else {
                    const skip = try self.emitJump(.jump_if_false);
                    // matched: patch all hit_jumps to here
                    for (hit_jumps.items) |hj| self.patchJump(hj);
                    try self.emitOp(.pop);
                    const body_jmp = try self.emitJump(.jump);
                    try body_jumps.append(self.allocator, body_jmp);
                    self.patchJump(skip);
                    try self.emitOp(.pop);
                }
            }
        }

        // jump to default or past all bodies
        for (case_nodes, 0..) |case_idx, i| {
            if (self.ast.nodes[case_idx].tag == .switch_default) {
                default_jump = try self.emitJump(.jump);
                body_jumps.items[i] = default_jump.?;
                break;
            }
        }
        const end_no_match = if (default_jump == null) try self.emitJump(.jump) else null;

        // phase 2: emit bodies sequentially (enables fallthrough)
        for (case_nodes, 0..) |case_idx, i| {
            const case_node = self.ast.nodes[case_idx];
            self.patchJump(body_jumps.items[i]);

            const stmts = if (case_node.tag == .switch_default)
                self.ast.extraSlice(case_node.data.lhs)
            else
                self.ast.extraSlice(case_node.data.rhs);

            for (stmts) |stmt| try self.compileNode(stmt);
        }

        if (end_no_match) |j| self.patchJump(j);
        for (self.break_jumps.items) |bj| self.patchJump(bj.offset);
        self.break_jumps.deinit(self.allocator);
        self.break_jumps = prev_breaks;
        self.loop_start = prev_start;
    }

    fn compileMatch(self: *Compiler, node: Ast.Node) Error!void {
        try self.compileNode(node.data.lhs);
        const temp_name = try std.fmt.allocPrint(self.allocator, "__match_{d}", .{self.closure_count});
        try self.string_allocs.append(self.allocator, temp_name);
        self.closure_count += 1;
        const temp_idx = try self.addConstant(.{ .string = temp_name });
        try self.emitOp(.set_var);
        try self.emitU16(temp_idx);
        try self.emitOp(.pop);

        const arm_nodes = self.ast.extraSlice(node.data.rhs);
        var end_jumps = std.ArrayListUnmanaged(usize){};
        defer end_jumps.deinit(self.allocator);
        var default_arm: ?u32 = null;

        for (arm_nodes) |arm_idx| {
            const arm = self.ast.nodes[arm_idx];
            const values = self.ast.extraSlice(arm.data.lhs);

            if (values.len == 0) {
                default_arm = arm_idx;
                continue;
            }

            var hit_jumps = std.ArrayListUnmanaged(usize){};
            defer hit_jumps.deinit(self.allocator);

            for (values, 0..) |val, vi| {
                try self.emitOp(.get_var);
                try self.emitU16(temp_idx);
                try self.compileNode(val);
                try self.emitOp(.identical);
                if (vi < values.len - 1) {
                    const hit = try self.emitJump(.jump_if_true);
                    try hit_jumps.append(self.allocator, hit);
                    try self.emitOp(.pop);
                } else {
                    const skip = try self.emitJump(.jump_if_false);
                    for (hit_jumps.items) |hj| self.patchJump(hj);
                    try self.emitOp(.pop);
                    try self.compileNode(arm.data.rhs);
                    const end_j = try self.emitJump(.jump);
                    try end_jumps.append(self.allocator, end_j);
                    self.patchJump(skip);
                    try self.emitOp(.pop);
                }
            }
        }

        if (default_arm) |da| {
            try self.compileNode(self.ast.nodes[da].data.rhs);
        } else {
            // no default: throw UnhandledMatchError
            const cls_idx = try self.addConstant(.{ .string = "UnhandledMatchError" });
            const msg_idx = try self.addConstant(.{ .string = "Unhandled match case" });
            try self.emitConstant(msg_idx);
            try self.emitOp(.new_obj);
            try self.emitU16(cls_idx);
            try self.emitByte(1);
            try self.emitOp(.throw);
        }

        for (end_jumps.items) |ej| self.patchJump(ej);
    }

    fn compileCast(self: *Compiler, node: Ast.Node) Error!void {
        try self.compileNode(node.data.lhs);
        const type_name = self.ast.tokenSlice(node.main_token);
        if (std.mem.eql(u8, type_name, "int") or std.mem.eql(u8, type_name, "integer")) {
            try self.emitOp(.cast_int);
        } else if (std.mem.eql(u8, type_name, "float") or std.mem.eql(u8, type_name, "double") or std.mem.eql(u8, type_name, "real")) {
            try self.emitOp(.cast_float);
        } else if (std.mem.eql(u8, type_name, "string")) {
            try self.emitOp(.cast_string);
        } else if (std.mem.eql(u8, type_name, "bool") or std.mem.eql(u8, type_name, "boolean")) {
            try self.emitOp(.cast_bool);
        } else if (std.mem.eql(u8, type_name, "array")) {
            try self.emitOp(.cast_array);
        }
    }

    fn compileCallableRef(self: *Compiler, node: Ast.Node) Error!void {
        const callee = self.ast.nodes[node.data.lhs];
        if (callee.tag == .identifier) {
            const name = self.ast.tokenSlice(callee.main_token);
            const idx = try self.addConstant(.{ .string = name });
            try self.emitOp(.constant);
            try self.emitU16(idx);
        } else {
            // fallback: compile the expression directly
            try self.compileNode(node.data.lhs);
        }
    }

    fn compileClosure(self: *Compiler, node: Ast.Node) Error!void {
        const id = self.closure_count;
        self.closure_count += 1;

        var name_buf: [32]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "__closure_{d}", .{id}) catch "__closure";
        const owned_name = try self.allocator.dupe(u8, name);
        try self.string_allocs.append(self.allocator, owned_name);

        const param_nodes = self.ast.extraSlice(node.data.lhs);
        const param_names = try self.allocator.alloc([]const u8, param_nodes.len);
        var ref_flags_buf: [16]bool = .{false} ** 16;
        var has_any_ref = false;
        for (param_nodes, 0..) |p, i| {
            param_names[i] = self.ast.tokenSlice(self.ast.nodes[p].main_token);
            if (i < 16 and (self.ast.nodes[p].data.rhs & 2) != 0) {
                ref_flags_buf[i] = true;
                has_any_ref = true;
            }
        }

        // rhs = extra -> {body, use_count, use_vars...}
        // use_count 0xFFFFFFFF = arrow fn (implicit capture)
        const body_node = self.ast.extra_data[node.data.rhs];
        const raw_use_count = self.ast.extra_data[node.data.rhs + 1];
        const is_arrow = raw_use_count == 0xFFFFFFFF;
        const use_count: u32 = if (is_arrow) 0 else raw_use_count;
        const use_vars = self.ast.extra_data[node.data.rhs + 2 .. node.data.rhs + 2 + use_count];

        var sub = Compiler{
            .ast = self.ast,
            .chunk = .{},
            .functions = .{},
            .string_allocs = .{},
            .allocator = self.allocator,
            .scope_depth = self.scope_depth + 1,
            .loop_start = null,
            .break_jumps = .{},
            .continue_jumps = .{},
            .closure_count = self.closure_count,
            .file_path = self.file_path,
        };
        errdefer {
            sub.chunk.deinit(self.allocator);
            sub.break_jumps.deinit(self.allocator);
            sub.continue_jumps.deinit(self.allocator);
            sub.string_allocs.deinit(self.allocator);
        }

        try sub.compileNode(body_node);
        try sub.emitOp(.op_null);
        try sub.emitOp(.return_val);
        sub.break_jumps.deinit(self.allocator);

        self.closure_count = sub.closure_count;

        const ref_params = if (has_any_ref) blk: {
            const rp = try self.allocator.alloc(bool, param_nodes.len);
            for (0..param_nodes.len) |i| rp[i] = if (i < 16) ref_flags_buf[i] else false;
            break :blk rp;
        } else &[_]bool{};

        const func = ObjFunction{
            .name = owned_name,
            .arity = @intCast(param_nodes.len),
            .params = param_names[0..param_nodes.len],
            .chunk = sub.chunk,
            .is_arrow = is_arrow,
            .ref_params = ref_params,
        };

        try self.functions.append(self.allocator, func);

        for (sub.functions.items) |f| try self.functions.append(self.allocator, f);
        sub.functions.deinit(self.allocator);
        for (sub.string_allocs.items) |s| try self.string_allocs.append(self.allocator, s);
        sub.string_allocs.deinit(self.allocator);

        const idx = try self.addConstant(.{ .string = owned_name });
        try self.emitConstant(idx);

        for (use_vars) |use_var_node| {
            const use_node = self.ast.nodes[use_var_node];
            const var_name = self.ast.tokenSlice(use_node.main_token);
            const var_idx = try self.addConstant(.{ .string = var_name });
            const is_ref = use_node.data.rhs != 0;
            try self.emitOp(if (is_ref) .closure_bind_ref else .closure_bind);
            try self.emitU16(var_idx);
        }

        // bind $this for closures in method context
        const this_idx = try self.addConstant(.{ .string = "$this" });
        try self.emitOp(.closure_bind);
        try self.emitU16(this_idx);
    }

    // ==================================================================
    // calls
    // ==================================================================

    fn hasSplatOrNamed(ast: *const Ast, args: []const u32) bool {
        for (args) |arg_idx| {
            const tag = ast.nodes[arg_idx].tag;
            if (tag == .splat_expr or tag == .named_arg) return true;
        }
        return false;
    }

    fn emitSpreadArgs(self: *Compiler, args: []const u32) Error!void {
        try self.emitOp(.array_new);
        for (args) |arg_idx| {
            const arg_node = self.ast.nodes[arg_idx];
            if (arg_node.tag == .splat_expr) {
                try self.compileNode(arg_node.data.lhs);
                try self.emitOp(.array_spread);
            } else if (arg_node.tag == .named_arg) {
                const name = self.ast.tokenSlice(arg_node.main_token);
                const name_const = try self.addConstant(.{ .string = name });
                try self.emitOp(.constant);
                try self.emitU16(name_const);
                try self.compileNode(arg_node.data.lhs);
                try self.emitOp(.array_set_elem);
            } else {
                try self.compileNode(arg_idx);
                try self.emitOp(.array_push);
            }
        }
    }

    fn compileUnset(self: *Compiler, args: []const u32) Error!void {
        for (args) |arg_idx| {
            const arg = self.ast.nodes[arg_idx];
            if (arg.tag == .variable) {
                const name = self.ast.tokenSlice(arg.main_token);
                const idx = try self.addConstant(.{ .string = name });
                try self.emitOp(.unset_var);
                try self.emitU16(idx);
            } else if (arg.tag == .property_access) {
                try self.compileNode(arg.data.lhs);
                const prop_node = self.ast.nodes[arg.data.rhs];
                var prop_name = self.ast.tokenSlice(prop_node.main_token);
                if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
                const prop_idx = try self.addConstant(.{ .string = prop_name });
                try self.emitOp(.unset_prop);
                try self.emitU16(prop_idx);
            } else if (arg.tag == .array_access) {
                try self.compileNode(arg.data.lhs);
                try self.compileNode(arg.data.rhs);
                try self.emitOp(.unset_array_elem);
            }
        }
        try self.emitOp(.op_null);
    }

    fn compileCall(self: *Compiler, node: Ast.Node) Error!void {
        const callee = self.ast.nodes[node.data.lhs];
        const args = self.ast.extraSlice(node.data.rhs);

        if (callee.tag == .identifier and std.mem.eql(u8, self.ast.tokenSlice(callee.main_token), "unset")) {
            try self.compileUnset(args);
            return;
        }

        if (hasSplatOrNamed(self.ast, args)) {
            try self.emitSpreadArgs(args);
            if (callee.tag == .identifier) {
                const name = self.ast.tokenSlice(callee.main_token);
                const idx = try self.addConstant(.{ .string = name });
                try self.emitOp(.call_spread);
                try self.emitU16(idx);
            } else {
                try self.compileNode(node.data.lhs);
                // swap so function name is below args array
                try self.emitOp(.call_indirect_spread);
            }
        } else if (callee.tag == .identifier) {
            for (args) |arg| try self.compileNode(arg);
            const name = self.ast.tokenSlice(callee.main_token);
            const idx = try self.addConstant(.{ .string = name });
            try self.emitOp(.call);
            try self.emitU16(idx);
            try self.emitByte(@intCast(args.len));
        } else {
            try self.compileNode(node.data.lhs);
            for (args) |arg| try self.compileNode(arg);
            try self.emitOp(.call_indirect);
            try self.emitByte(@intCast(args.len));
        }
    }

    // ==================================================================
    // arrays
    // ==================================================================

    fn compileArrayLiteral(self: *Compiler, node: Ast.Node) Error!void {
        try self.emitOp(.array_new);
        for (self.ast.extraSlice(node.data.lhs)) |elem_idx| {
            const elem = self.ast.nodes[elem_idx];
            if (elem.tag == .array_spread) {
                try self.compileNode(elem.data.lhs);
                try self.emitOp(.array_spread);
            } else if (elem.data.rhs != 0) {
                try self.compileNode(elem.data.rhs);
                try self.compileNode(elem.data.lhs);
                try self.emitOp(.array_set_elem);
            } else {
                try self.compileNode(elem.data.lhs);
                try self.emitOp(.array_push);
            }
        }
    }

    fn compileGlobal(self: *Compiler, node: Ast.Node) Error!void {
        for (self.ast.extraSlice(node.data.lhs)) |var_idx| {
            const var_node = self.ast.nodes[var_idx];
            const name = self.ast.tokenSlice(var_node.main_token);
            const name_idx = try self.addConstant(.{ .string = name });
            try self.emitOp(.get_global);
            try self.emitU16(name_idx);
        }
    }

    fn compileStaticVar(self: *Compiler, node: Ast.Node) Error!void {
        const var_name = self.ast.tokenSlice(node.main_token);
        const var_idx = try self.addConstant(.{ .string = var_name });

        // get_static pushes the current value (or null if uninitialized)
        // VM derives the storage key from current function name + var name
        try self.emitOp(.get_static);
        try self.emitU16(var_idx);

        // if null (first call), initialize with default
        if (node.data.lhs != 0) {
            const skip = try self.emitJump(.jump_if_not_null);
            try self.emitOp(.pop);
            try self.compileNode(node.data.lhs);
            self.patchJump(skip);
        }

        try self.emitOp(.set_var);
        try self.emitU16(var_idx);
    }

    // ==================================================================
    // namespaces and file inclusion
    // ==================================================================

    fn compileNamespace(self: *Compiler, node: Ast.Node) Error!void {
        // reconstruct namespace name from token indices
        const parts = self.ast.extraSlice(node.data.lhs);
        self.namespace = try self.buildQualifiedString(parts);
    }

    fn compileUse(self: *Compiler, node: Ast.Node) Error!void {
        const parts = self.ast.extraSlice(node.data.lhs);
        const fqn = try self.buildQualifiedString(parts);

        // alias is either explicit (use Foo\Bar as Baz;) or last part of the name
        const alias = if (node.data.rhs != 0)
            self.ast.tokenSlice(node.data.rhs)
        else
            self.ast.tokenSlice(parts[parts.len - 1]);

        try self.use_aliases.put(self.allocator, alias, fqn);
    }

    fn compileRequire(self: *Compiler, node: Ast.Node) Error!void {
        try self.compileNode(node.data.lhs);
        const tok_tag = self.ast.tokens[node.main_token].tag;
        const variant: u8 = switch (tok_tag) {
            .kw_require => 0,
            .kw_require_once => 1,
            .kw_include => 2,
            .kw_include_once => 3,
            else => 0,
        };
        try self.emitOp(.require);
        try self.emitByte(variant);
    }

    // joins token indices with backslash to form "App\Models\User"
    fn buildQualifiedString(self: *Compiler, parts: []const u32) Error![]const u8 {
        if (parts.len == 1) return self.ast.tokenSlice(parts[0]);
        var buf = std.ArrayListUnmanaged(u8){};
        defer buf.deinit(self.allocator);
        for (parts, 0..) |tok_idx, i| {
            if (i > 0) try buf.append(self.allocator, '\\');
            try buf.appendSlice(self.allocator, self.ast.tokenSlice(tok_idx));
        }
        const owned = try self.allocator.dupe(u8, buf.items);
        try self.string_allocs.append(self.allocator, owned);
        return owned;
    }

    // resolves a class name through use aliases and current namespace
    fn resolveClassName(self: *Compiler, name: []const u8) []const u8 {
        // fully-qualified names (starting with \) bypass resolution
        if (name.len > 0 and name[0] == '\\') return name[1..];
        // check use aliases
        if (self.use_aliases.get(name)) |fqn| return fqn;
        // prepend current namespace
        if (self.namespace.len == 0) return name;
        // need to allocate the qualified name
        const qualified = std.fmt.allocPrint(self.allocator, "{s}\\{s}", .{ self.namespace, name }) catch return name;
        self.string_allocs.append(self.allocator, qualified) catch return name;
        return qualified;
    }

    fn compileArrayAccess(self: *Compiler, node: Ast.Node) Error!void {
        try self.compileNode(node.data.lhs);
        try self.compileNode(node.data.rhs);
        try self.emitOp(.array_get);
    }

    fn compileForeach(self: *Compiler, node: Ast.Node) Error!void {
        const iter_n = self.ast.extra_data[node.data.lhs];
        const val_n = self.ast.extra_data[node.data.lhs + 1];
        const key_n = self.ast.extra_data[node.data.lhs + 2];
        const val_by_ref = self.ast.extra_data[node.data.lhs + 3] != 0;

        const prev_start = self.loop_start;
        var prev_breaks = self.break_jumps;
        var prev_continues = self.continue_jumps;
        const prev_use_cj = self.use_continue_jumps;
        self.break_jumps = .{};
        self.continue_jumps = .{};
        self.use_continue_jumps = true;
        self.loop_depth += 1;

        try self.compileNode(iter_n);
        try self.emitOp(.iter_begin);

        const loop_top = self.chunk.offset();
        self.loop_start = loop_top;

        const exit_jump = try self.emitJump(.iter_check);

        // iter_check pushed: key, value (value on top)
        // for by-ref, also store the key for writeback
        var ref_key_idx: ?u16 = null;
        var ref_val_idx: ?u16 = null;

        const val_node = self.ast.nodes[val_n];
        if (val_node.tag == .array_literal or val_node.tag == .list_destructure) {
            try self.compileDestructure(val_node);
            try self.emitOp(.pop);
        } else {
            const val_name = self.ast.tokenSlice(val_node.main_token);
            const val_idx = try self.addConstant(.{ .string = val_name });
            try self.emitOp(.set_var);
            try self.emitU16(val_idx);
            try self.emitOp(.pop);
            if (val_by_ref) ref_val_idx = val_idx;
        }

        if (key_n != 0) {
            const key_name = self.ast.tokenSlice(self.ast.nodes[key_n].main_token);
            const key_idx = try self.addConstant(.{ .string = key_name });
            try self.emitOp(.set_var);
            try self.emitU16(key_idx);
            try self.emitOp(.pop);
            if (val_by_ref) ref_key_idx = key_idx;
        } else {
            if (val_by_ref) {
                // need a synthetic key variable for writeback
                const synth = try self.addConstant(.{ .string = "__foreach_key" });
                try self.emitOp(.set_var);
                try self.emitU16(synth);
                try self.emitOp(.pop);
                ref_key_idx = synth;
            } else {
                try self.emitOp(.pop);
            }
        }

        try self.compileNode(node.data.rhs);

        // continue lands here, before iter_advance (same pattern as for loop update)
        try self.patchContinues(&prev_continues);

        // by-ref writeback: $arr[$key] = $val
        if (val_by_ref) {
            if (ref_val_idx) |vi| {
                if (ref_key_idx) |ki| {
                    try self.compileNode(iter_n);
                    try self.emitOp(.get_var);
                    try self.emitU16(ki);
                    try self.emitOp(.get_var);
                    try self.emitU16(vi);
                    try self.emitOp(.array_set);
                    try self.emitOp(.pop);
                }
            }
        }

        try self.emitOp(.iter_advance);
        try self.emitLoop(loop_top);

        self.patchJump(exit_jump);
        try self.emitOp(.iter_end);

        try self.patchBreaks(&prev_breaks);
        self.break_jumps = prev_breaks;
        self.continue_jumps = prev_continues;
        self.use_continue_jumps = prev_use_cj;
        self.loop_depth -= 1;
        self.loop_start = prev_start;
    }

    // ==================================================================
    // emit helpers
    // ==================================================================

    fn emitOp(self: *Compiler, op: OpCode) Error!void {
        try self.chunk.write(self.allocator, @intFromEnum(op), 0);
    }

    fn emitByte(self: *Compiler, byte: u8) Error!void {
        try self.chunk.write(self.allocator, byte, 0);
    }

    fn emitU16(self: *Compiler, val: u16) Error!void {
        try self.emitByte(@intCast(val >> 8));
        try self.emitByte(@intCast(val & 0xff));
    }

    fn emitConstant(self: *Compiler, idx: u16) Error!void {
        try self.emitOp(.constant);
        try self.emitU16(idx);
    }

    fn emitJump(self: *Compiler, op: OpCode) Error!usize {
        try self.emitOp(op);
        try self.emitU16(0xffff);
        return self.chunk.offset() - 2;
    }

    fn patchJump(self: *Compiler, offset: usize) void {
        const dist = self.chunk.offset() - offset - 2;
        self.chunk.code.items[offset] = @intCast(dist >> 8);
        self.chunk.code.items[offset + 1] = @intCast(dist & 0xff);
    }

    fn emitLoop(self: *Compiler, loop_start: usize) Error!void {
        try self.emitOp(.jump_back);
        const dist = self.chunk.offset() - loop_start + 2;
        try self.emitU16(@intCast(dist));
    }

    fn addConstant(self: *Compiler, value: Value) Error!u16 {
        return self.chunk.addConstant(self.allocator, value);
    }

    // ==================================================================
    // number parsing
    // ==================================================================

    fn parsePhpInt(s: []const u8) i64 {
        if (s.len == 0) return 0;
        var buf: [64]u8 = undefined;
        var len: usize = 0;
        for (s) |c| {
            if (c != '_' and len < buf.len) {
                buf[len] = c;
                len += 1;
            }
        }
        const clean = buf[0..len];
        if (clean.len > 2 and clean[0] == '0') {
            switch (clean[1]) {
                'x', 'X' => return std.fmt.parseInt(i64, clean[2..], 16) catch 0,
                'b', 'B' => return std.fmt.parseInt(i64, clean[2..], 2) catch 0,
                'o', 'O' => return std.fmt.parseInt(i64, clean[2..], 8) catch 0,
                else => {},
            }
        }
        return std.fmt.parseInt(i64, clean, 10) catch 0;
    }

    fn parsePhpFloat(s: []const u8) f64 {
        var buf: [64]u8 = undefined;
        var len: usize = 0;
        for (s) |c| {
            if (c != '_' and len < buf.len) {
                buf[len] = c;
                len += 1;
            }
        }
        return std.fmt.parseFloat(f64, buf[0..len]) catch 0.0;
    }
};
