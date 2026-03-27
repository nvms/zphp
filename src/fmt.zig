const std = @import("std");
const parser = @import("pipeline/parser.zig");
const Ast = @import("pipeline/ast.zig").Ast;
const Token = @import("pipeline/token.zig").Token;
const Tag = Token.Tag;
const NodeTag = Ast.Node.Tag;
const tui = @import("tui.zig");

const Allocator = std.mem.Allocator;

pub fn run(allocator: Allocator, args: []const []const u8) !void {
    var check_mode = false;
    var paths = std.ArrayListUnmanaged([]const u8){};
    defer paths.deinit(allocator);

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--check")) {
            check_mode = true;
        } else {
            try paths.append(allocator, arg);
        }
    }

    if (paths.items.len == 0) {
        try writeStderr("usage: zphp fmt [--check] <file>...\n");
        std.process.exit(1);
    }

    var any_changed = false;
    var any_error = false;

    for (paths.items) |path| {
        const source = std.fs.cwd().readFileAlloc(allocator, path, 10 * 1024 * 1024) catch {
            tui.err(path);
            any_error = true;
            continue;
        };
        defer allocator.free(source);

        var ast = parser.parse(allocator, source) catch {
            tui.err(path);
            any_error = true;
            continue;
        };
        defer ast.deinit();

        if (ast.errors.len > 0) {
            tui.err(path);
            any_error = true;
            continue;
        }

        const formatted = formatSource(allocator, &ast, source) catch {
            tui.err(path);
            any_error = true;
            continue;
        };
        defer allocator.free(formatted);

        if (std.mem.eql(u8, source, formatted)) {
            continue;
        }

        any_changed = true;

        if (check_mode) {
            tui.step("would reformat", path);
        } else {
            std.fs.cwd().writeFile(.{ .sub_path = path, .data = formatted }) catch {
                tui.err(path);
                any_error = true;
                continue;
            };
            tui.step("formatted", path);
        }
    }

    if (any_error) std.process.exit(2);
    if (check_mode and any_changed) std.process.exit(1);
}

// trivia between tokens: comments and whitespace from the source that the
// lexer skipped. we extract these so the formatter can re-emit comments
const Trivia = struct {
    comments: []const Comment,

    const Comment = struct {
        text: []const u8,
        is_line: bool,
    };
};

fn extractTrivia(allocator: Allocator, tokens: []const Token, source: []const u8) ![]const Trivia {
    var result = try allocator.alloc(Trivia, tokens.len);
    var comment_buf = std.ArrayListUnmanaged(Trivia.Comment){};
    defer comment_buf.deinit(allocator);

    for (tokens, 0..) |tok, i| {
        comment_buf.clearRetainingCapacity();

        const gap_start = if (i == 0) @as(u32, 0) else tokens[i - 1].end;
        const gap_end = tok.start;

        if (gap_end > gap_start) {
            const gap = source[gap_start..gap_end];
            var pos: usize = 0;
            while (pos < gap.len) {
                if (gap[pos] == ' ' or gap[pos] == '\t' or gap[pos] == '\n' or gap[pos] == '\r') {
                    pos += 1;
                    continue;
                }
                if (pos + 1 < gap.len and gap[pos] == '/' and gap[pos + 1] == '/') {
                    const start = pos;
                    while (pos < gap.len and gap[pos] != '\n') pos += 1;
                    try comment_buf.append(allocator, .{ .text = gap[start..pos], .is_line = true });
                    continue;
                }
                if (pos + 1 < gap.len and gap[pos] == '#' and (pos + 1 >= gap.len or gap[pos + 1] != '[')) {
                    const start = pos;
                    while (pos < gap.len and gap[pos] != '\n') pos += 1;
                    try comment_buf.append(allocator, .{ .text = gap[start..pos], .is_line = true });
                    continue;
                }
                if (pos + 1 < gap.len and gap[pos] == '/' and gap[pos + 1] == '*') {
                    const start = pos;
                    pos += 2;
                    while (pos + 1 < gap.len) {
                        if (gap[pos] == '*' and gap[pos + 1] == '/') {
                            pos += 2;
                            break;
                        }
                        pos += 1;
                    } else {
                        pos = gap.len;
                    }
                    try comment_buf.append(allocator, .{ .text = gap[start..pos], .is_line = false });
                    continue;
                }
                pos += 1;
            }
        }

        if (comment_buf.items.len > 0) {
            result[i] = .{ .comments = try allocator.dupe(Trivia.Comment, comment_buf.items) };
        } else {
            result[i] = .{ .comments = &.{} };
        }
    }

    return result;
}

fn freeTrivia(allocator: Allocator, trivia: []const Trivia) void {
    for (trivia) |t| {
        if (t.comments.len > 0) allocator.free(t.comments);
    }
    allocator.free(trivia);
}

const Formatter = struct {
    ast: *const Ast,
    source: []const u8,
    trivia: []const Trivia,
    out: std.ArrayListUnmanaged(u8),
    indent: u32,
    allocator: Allocator,
    last_was_newline: bool,

    fn init(allocator: Allocator, ast: *const Ast, source: []const u8, trivia: []const Trivia) Formatter {
        return .{
            .ast = ast,
            .source = source,
            .trivia = trivia,
            .out = .{},
            .indent = 0,
            .allocator = allocator,
            .last_was_newline = false,
        };
    }

    fn deinit(self: *Formatter) void {
        self.out.deinit(self.allocator);
    }

    fn toOwnedSlice(self: *Formatter) ![]const u8 {
        return self.out.toOwnedSlice(self.allocator);
    }

    fn write(self: *Formatter, s: []const u8) void {
        self.out.appendSlice(self.allocator, s) catch {};
        if (s.len > 0) {
            self.last_was_newline = s[s.len - 1] == '\n';
        }
    }

    fn newline(self: *Formatter) void {
        self.write("\n");
    }

    fn blankLine(self: *Formatter) void {
        if (!self.last_was_newline) self.newline();
        self.newline();
    }

    fn writeIndent(self: *Formatter) void {
        var i: u32 = 0;
        while (i < self.indent) : (i += 1) {
            self.write("    ");
        }
    }

    fn indentedLine(self: *Formatter) void {
        self.newline();
        self.writeIndent();
    }

    fn emitToken(self: *Formatter, tok_idx: u32) void {
        self.emitTriviaFor(tok_idx);
        self.write(self.ast.tokens[tok_idx].lexeme(self.source));
    }

    fn emitTriviaFor(self: *Formatter, tok_idx: u32) void {
        if (tok_idx >= self.trivia.len) return;
        for (self.trivia[tok_idx].comments) |comment| {
            self.write(comment.text);
            self.newline();
        }
    }

    // walk nodes

    fn formatRoot(self: *Formatter) void {
        const root = self.ast.nodes[0];
        const stmts = self.ast.extraSlice(root.data.lhs);

        var prev_tag: ?NodeTag = null;
        for (stmts) |stmt_idx| {
            const node = self.ast.nodes[stmt_idx];

            if (node.tag == .inline_html) {
                self.write(self.ast.tokens[node.main_token].lexeme(self.source));
                prev_tag = .inline_html;
                continue;
            }

            const is_decl = node.tag == .function_decl or node.tag == .class_decl or
                node.tag == .interface_decl or node.tag == .trait_decl or node.tag == .enum_decl;

            if (prev_tag != null and prev_tag != .inline_html) {
                if (is_decl or prev_tag == .function_decl or prev_tag == .class_decl or
                    prev_tag == .interface_decl or prev_tag == .trait_decl or prev_tag == .enum_decl)
                {
                    self.blankLine();
                } else {
                    self.newline();
                }
            }

            self.emitTriviaForNode(stmt_idx);
            self.formatNode(stmt_idx);
            prev_tag = node.tag;
        }

        // trailing newline
        if (self.out.items.len > 0 and self.out.items[self.out.items.len - 1] != '\n') {
            self.newline();
        }
    }

    fn emitTriviaForNode(self: *Formatter, node_idx: u32) void {
        const tok = self.findFirstToken(node_idx);
        if (tok) |t| self.emitTriviaFor(t);
    }

    fn findFirstToken(self: *Formatter, node_idx: u32) ?u32 {
        if (node_idx == 0) return null;
        const node = self.ast.nodes[node_idx];
        return switch (node.tag) {
            .expression_stmt => self.findFirstToken(node.data.lhs),
            .grouped_expr => self.findFirstToken(node.data.lhs),
            .binary_op, .assign, .logical_and, .logical_or, .null_coalesce => self.findFirstToken(node.data.lhs),
            .property_access, .nullsafe_property_access => self.findFirstToken(node.data.lhs),
            .method_call, .nullsafe_method_call => self.findFirstToken(node.data.lhs),
            .call, .callable_ref => self.findFirstToken(node.data.lhs),
            .array_access, .array_push_target => self.findFirstToken(node.data.lhs),
            .list_destructure, .named_arg => node.main_token,
            .postfix_op => self.findFirstToken(node.data.lhs),
            .static_call => self.findFirstToken(node.data.lhs),
            .static_prop_access => self.findFirstToken(node.data.lhs),
            else => node.main_token,
        };
    }

    fn formatNode(self: *Formatter, node_idx: u32) void {
        if (node_idx == 0) return;
        const node = self.ast.nodes[node_idx];
        switch (node.tag) {
            .root => self.formatRoot(),
            .inline_html => self.write(self.ast.tokens[node.main_token].lexeme(self.source)),
            .expression_stmt => {
                self.formatNode(node.data.lhs);
                self.write(";");
            },
            .echo_stmt => self.formatEcho(node),
            .return_stmt => self.formatReturn(node),
            .break_stmt => self.formatBreakContinue(node, "break"),
            .continue_stmt => self.formatBreakContinue(node, "continue"),
            .block => self.formatBlock(node_idx),
            .if_simple => self.formatIfSimple(node),
            .if_else => self.formatIfElse(node),
            .while_stmt => self.formatWhile(node),
            .do_while => self.formatDoWhile(node),
            .for_stmt => self.formatFor(node),
            .foreach_stmt => self.formatForeach(node),
            .function_decl => self.formatFunctionDecl(node),
            .class_decl => self.formatClassDecl(node),
            .interface_decl => self.formatInterfaceDecl(node),
            .trait_decl => self.formatTraitDecl(node),
            .const_decl => self.formatConstDecl(node),
            .switch_stmt => self.formatSwitch(node),
            .match_expr => self.formatMatch(node),
            .try_catch => self.formatTryCatch(node),
            .throw_expr => self.formatThrow(node),
            .namespace_decl => self.formatNamespaceDecl(node),
            .use_stmt => self.formatUseStmt(node),
            .require_expr => self.formatRequire(node),
            .global_stmt => self.formatGlobalStmt(node),
            .static_var => self.formatStaticVar(node),
            .trait_use => self.formatTraitUse(node),
            .trait_insteadof, .trait_as => {},
            .class_method, .static_class_method => self.formatClassMethod(node),
            .class_property, .static_class_property => self.formatClassProperty(node),
            .interface_method => self.formatInterfaceMethod(node),

            .integer_literal, .float_literal, .string_literal => {
                self.write(self.ast.tokens[node.main_token].lexeme(self.source));
            },
            .true_literal => self.write("true"),
            .false_literal => self.write("false"),
            .null_literal => self.write("null"),
            .variable => self.write(self.ast.tokens[node.main_token].lexeme(self.source)),
            .identifier => self.write(self.ast.tokens[node.main_token].lexeme(self.source)),

            .binary_op => self.formatBinaryOp(node),
            .assign => self.formatAssign(node),
            .logical_and => self.formatLogical(node, "&&"),
            .logical_or => self.formatLogical(node, "||"),
            .null_coalesce => self.formatLogical(node, "??"),
            .prefix_op => self.formatPrefixOp(node),
            .postfix_op => self.formatPostfixOp(node),
            .ternary => self.formatTernary(node),

            .call => self.formatCall(node),
            .callable_ref => {
                self.formatNode(node.data.lhs);
                self.write("(...)");
            },
            .array_access => self.formatArrayAccess(node),
            .array_push_target => self.formatArrayPushTarget(node),
            .list_destructure => self.formatListDestructure(node),
            .named_arg => self.formatNamedArg(node),
            .property_access => self.formatPropertyAccess(node, false),
            .nullsafe_property_access => self.formatPropertyAccess(node, true),
            .method_call => self.formatMethodCall(node, false),
            .nullsafe_method_call => self.formatMethodCall(node, true),
            .static_call => self.formatStaticCall(node),
            .static_prop_access => self.formatStaticPropAccess(node),
            .new_expr => self.formatNewExpr(node),
            .new_expr_dynamic => {
                self.write("new ");
                self.formatNode(node.data.lhs);
                self.write("(");
                const args = self.ast.extraSlice(node.data.rhs);
                for (args, 0..) |arg, i| {
                    if (i > 0) self.write(", ");
                    self.formatNode(arg);
                }
                self.write(")");
            },
            .cast_expr => self.formatCastExpr(node),

            .closure_expr => self.formatClosure(node),
            .array_literal => self.formatArrayLiteral(node),
            .array_element => self.formatArrayElement(node),
            .array_spread => {
                self.write("...");
                self.formatNode(node.data.lhs);
            },
            .grouped_expr => {
                self.write("(");
                self.formatNode(node.data.lhs);
                self.write(")");
            },
            .expr_list => self.formatExprList(node),

            .yield_expr => {
                self.write("yield");
                if (node.data.lhs != 0) {
                    self.write(" ");
                    self.formatNode(node.data.lhs);
                }
            },
            .yield_pair_expr => {
                self.write("yield ");
                self.formatNode(node.data.lhs);
                self.write(" => ");
                self.formatNode(node.data.rhs);
            },
            .yield_from_expr => {
                self.write("yield from ");
                self.formatNode(node.data.lhs);
            },
            .splat_expr => {
                self.write("...");
                self.formatNode(node.data.lhs);
            },
            .qualified_name => self.formatQualifiedName(node),
            .enum_decl => self.formatEnumDecl(node),
            .enum_case => self.formatEnumCase(node),

            .switch_case, .switch_default, .match_arm, .catch_clause => {},
        }
    }

    // statements

    fn formatEcho(self: *Formatter, node: Ast.Node) void {
        const tok_lex = self.ast.tokens[node.main_token].lexeme(self.source);
        const is_short = self.ast.tokens[node.main_token].tag == .open_tag_echo;
        if (is_short) {
            self.write("<?= ");
        } else {
            self.write(tok_lex);
            self.write(" ");
        }
        const exprs = self.ast.extraSlice(node.data.lhs);
        for (exprs, 0..) |expr, i| {
            if (i > 0) self.write(", ");
            self.formatNode(expr);
        }
        if (!is_short) self.write(";");
    }

    fn formatReturn(self: *Formatter, node: Ast.Node) void {
        self.write("return");
        if (node.data.lhs != 0) {
            self.write(" ");
            self.formatNode(node.data.lhs);
        }
        self.write(";");
    }

    fn formatBreakContinue(self: *Formatter, node: Ast.Node, keyword: []const u8) void {
        self.write(keyword);
        if (node.data.lhs > 1) {
            self.write(" ");
            var buf: [16]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{node.data.lhs}) catch "?";
            self.write(s);
        }
        self.write(";");
    }

    fn formatBlock(self: *Formatter, node_idx: u32) void {
        const node = self.ast.nodes[node_idx];
        const stmts = self.ast.extraSlice(node.data.lhs);
        self.write("{");
        if (stmts.len > 0) {
            self.indent += 1;
            for (stmts) |stmt_idx| {
                self.newline();
                self.emitTriviaForNode(stmt_idx);
                self.writeIndent();
                self.formatNode(stmt_idx);
            }
            self.indent -|= 1;
            self.newline();
            self.writeIndent();
        }
        self.write("}");
    }

    fn formatBlockInline(self: *Formatter, node_idx: u32) void {
        const node = self.ast.nodes[node_idx];
        if (node.tag != .block) {
            self.indent += 1;
            self.newline();
            self.writeIndent();
            self.formatNode(node_idx);
            self.indent -|= 1;
            return;
        }
        self.write(" ");
        self.formatBlock(node_idx);
    }

    fn formatIfSimple(self: *Formatter, node: Ast.Node) void {
        self.write("if (");
        self.formatNode(node.data.lhs);
        self.write(")");
        self.formatBlockInline(node.data.rhs);
    }

    fn formatIfElse(self: *Formatter, node: Ast.Node) void {
        const extra = self.ast.extra_data[node.data.rhs .. node.data.rhs + 2];
        const then_body = extra[0];
        const else_body = extra[1];

        self.write("if (");
        self.formatNode(node.data.lhs);
        self.write(")");
        self.formatBlockInline(then_body);

        const else_node = self.ast.nodes[else_body];
        if (else_node.tag == .if_simple or else_node.tag == .if_else) {
            self.write(" else");
            // elseif - check if original token was kw_elseif
            if (self.ast.tokens[else_node.main_token].tag == .kw_elseif) {
                self.write("if (");
            } else {
                self.write(" if (");
            }
            self.formatNode(else_node.data.lhs);
            self.write(")");
            if (else_node.tag == .if_simple) {
                self.formatBlockInline(else_node.data.rhs);
            } else {
                const inner_extra = self.ast.extra_data[else_node.data.rhs .. else_node.data.rhs + 2];
                self.formatBlockInline(inner_extra[0]);
                self.formatElseChain(inner_extra[1]);
            }
        } else {
            self.write(" else");
            self.formatBlockInline(else_body);
        }
    }

    fn formatElseChain(self: *Formatter, else_body: u32) void {
        if (else_body == 0) return;
        const else_node = self.ast.nodes[else_body];
        if (else_node.tag == .if_simple or else_node.tag == .if_else) {
            self.write(" elseif (");
            self.formatNode(else_node.data.lhs);
            self.write(")");
            if (else_node.tag == .if_simple) {
                self.formatBlockInline(else_node.data.rhs);
            } else {
                const inner_extra = self.ast.extra_data[else_node.data.rhs .. else_node.data.rhs + 2];
                self.formatBlockInline(inner_extra[0]);
                self.formatElseChain(inner_extra[1]);
            }
        } else {
            self.write(" else");
            self.formatBlockInline(else_body);
        }
    }

    fn formatWhile(self: *Formatter, node: Ast.Node) void {
        self.write("while (");
        self.formatNode(node.data.lhs);
        self.write(")");
        self.formatBlockInline(node.data.rhs);
    }

    fn formatDoWhile(self: *Formatter, node: Ast.Node) void {
        self.write("do");
        self.formatBlockInline(node.data.lhs);
        self.write(" while (");
        self.formatNode(node.data.rhs);
        self.write(");");
    }

    fn formatFor(self: *Formatter, node: Ast.Node) void {
        const parts = self.ast.extra_data[node.data.lhs .. node.data.lhs + 3];
        self.write("for (");
        if (parts[0] != 0) self.formatNode(parts[0]);
        self.write("; ");
        if (parts[1] != 0) self.formatNode(parts[1]);
        self.write("; ");
        if (parts[2] != 0) self.formatNode(parts[2]);
        self.write(")");
        self.formatBlockInline(node.data.rhs);
    }

    fn formatForeach(self: *Formatter, node: Ast.Node) void {
        const parts = self.ast.extra_data[node.data.lhs .. node.data.lhs + 3];
        self.write("foreach (");
        self.formatNode(parts[0]);
        self.write(" as ");
        if (parts[2] != 0) {
            self.formatNode(parts[2]);
            self.write(" => ");
        }
        self.formatNode(parts[1]);
        self.write(")");
        self.formatBlockInline(node.data.rhs);
    }

    fn formatFunctionDecl(self: *Formatter, node: Ast.Node) void {
        self.write("function ");
        self.write(self.ast.tokens[node.main_token].lexeme(self.source));
        self.write("(");
        self.formatParamList(node.data.lhs);
        self.write(")");
        self.formatReturnType(node.main_token);
        self.formatBlockInline(node.data.rhs);
    }

    fn formatReturnType(self: *Formatter, name_tok: u32) void {
        // scan forward from name token to find : before {
        var i = name_tok + 1;
        while (i < self.ast.tokens.len) : (i += 1) {
            const tag = self.ast.tokens[i].tag;
            if (tag == .l_brace or tag == .semicolon or tag == .eof) break;
            if (tag == .r_paren) {
                // check if next non-whitespace is colon
                var j = i + 1;
                while (j < self.ast.tokens.len) : (j += 1) {
                    const jt = self.ast.tokens[j].tag;
                    if (jt == .l_brace or jt == .semicolon or jt == .eof) break;
                    if (jt == .colon) {
                        self.write(": ");
                        // emit type tokens until { or ;
                        var k = j + 1;
                        while (k < self.ast.tokens.len) : (k += 1) {
                            const kt = self.ast.tokens[k].tag;
                            if (kt == .l_brace or kt == .semicolon or kt == .eof or kt == .fat_arrow) break;
                            if (k > j + 1) {
                                const prev_end = self.ast.tokens[k - 1].end;
                                const cur_start = self.ast.tokens[k].start;
                                if (cur_start > prev_end) self.write(" ");
                            }
                            self.write(self.ast.tokens[k].lexeme(self.source));
                        }
                        return;
                    }
                    if (jt != .colon) break;
                }
                break;
            }
        }
    }

    fn formatParamList(self: *Formatter, extra_idx: u32) void {
        const params = self.ast.extraSlice(extra_idx);
        for (params, 0..) |param_idx, i| {
            if (i > 0) self.write(", ");
            self.formatParam(param_idx);
        }
    }

    fn formatParam(self: *Formatter, node_idx: u32) void {
        const node = self.ast.nodes[node_idx];
        // emit type hint tokens before the variable
        const var_tok = node.main_token;
        self.emitTypeTokensBefore(var_tok);
        if (node.data.rhs == 1) self.write("...");
        self.write(self.ast.tokens[var_tok].lexeme(self.source));
        if (node.data.lhs != 0) {
            self.write(" = ");
            self.formatNode(node.data.lhs);
        }
    }

    fn emitTypeTokensBefore(self: *Formatter, var_tok: u32) void {
        if (var_tok == 0) return;
        var start: u32 = var_tok;
        if (start > 0 and self.ast.tokens[start - 1].tag == .ellipsis) start -= 1;
        var scan = start;
        while (scan > 0) {
            const prev = self.ast.tokens[scan - 1].tag;
            // only scan over actual type tokens - not l_paren/r_paren (those are param list delimiters)
            if (prev == .identifier or prev == .kw_array or prev == .kw_callable or
                prev == .kw_self or prev == .kw_static or prev == .kw_null or
                prev == .kw_true or prev == .kw_false or prev == .question or
                prev == .pipe or prev == .amp or prev == .backslash)
            {
                scan -= 1;
            } else break;
        }
        // verify the token before our type sequence is a delimiter (comma or l_paren)
        // if not, we may have grabbed non-type tokens
        if (scan < start and scan > 0) {
            const before = self.ast.tokens[scan - 1].tag;
            if (before != .comma and before != .l_paren and before != .kw_static and before != .kw_readonly) {
                return;
            }
        }
        if (scan < start) {
            var i = scan;
            while (i < start) : (i += 1) {
                self.write(self.ast.tokens[i].lexeme(self.source));
                if (i + 1 < start) {
                    const cur_end = self.ast.tokens[i].end;
                    const next_start = self.ast.tokens[i + 1].start;
                    if (next_start > cur_end) self.write(" ");
                }
            }
            self.write(" ");
        }
    }

    fn formatConstDecl(self: *Formatter, node: Ast.Node) void {
        self.write("const ");
        self.write(self.ast.tokens[node.main_token].lexeme(self.source));
        self.write(" = ");
        self.formatNode(node.data.lhs);
        self.write(";");
    }

    fn formatSwitch(self: *Formatter, node: Ast.Node) void {
        self.write("switch (");
        self.formatNode(node.data.lhs);
        self.write(") {");
        const cases = self.ast.extraSlice(node.data.rhs);
        self.indent += 1;
        for (cases) |case_idx| {
            const case_node = self.ast.nodes[case_idx];
            self.indentedLine();
            if (case_node.tag == .switch_case) {
                const values = self.ast.extraSlice(case_node.data.lhs);
                for (values, 0..) |val, vi| {
                    if (vi > 0) {
                        self.indentedLine();
                    }
                    self.write("case ");
                    self.formatNode(val);
                    self.write(":");
                }
                const stmts = self.ast.extraSlice(case_node.data.rhs);
                self.indent += 1;
                for (stmts) |stmt| {
                    self.indentedLine();
                    self.formatNode(stmt);
                }
                self.indent -|= 1;
            } else if (case_node.tag == .switch_default) {
                self.write("default:");
                const stmts = self.ast.extraSlice(case_node.data.lhs);
                self.indent += 1;
                for (stmts) |stmt| {
                    self.indentedLine();
                    self.formatNode(stmt);
                }
                self.indent -|= 1;
            }
        }
        self.indent -|= 1;
        self.indentedLine();
        self.write("}");
    }

    fn formatMatch(self: *Formatter, node: Ast.Node) void {
        self.write("match (");
        self.formatNode(node.data.lhs);
        self.write(") {");
        const arms = self.ast.extraSlice(node.data.rhs);
        self.indent += 1;
        for (arms, 0..) |arm_idx, ai| {
            const arm = self.ast.nodes[arm_idx];
            self.indentedLine();
            const values = self.ast.extraSlice(arm.data.lhs);
            if (values.len == 0) {
                self.write("default");
            } else {
                for (values, 0..) |val, vi| {
                    if (vi > 0) self.write(", ");
                    self.formatNode(val);
                }
            }
            self.write(" => ");
            self.formatNode(arm.data.rhs);
            if (ai < arms.len - 1) self.write(",");
        }
        self.indent -|= 1;
        self.indentedLine();
        self.write("}");
    }

    fn formatTryCatch(self: *Formatter, node: Ast.Node) void {
        self.write("try");
        self.formatBlockInline(node.data.lhs);

        const catch_count = self.ast.extra_data[node.data.rhs];
        const catches = self.ast.extra_data[node.data.rhs + 1 .. node.data.rhs + 1 + catch_count];
        const finally_node = self.ast.extra_data[node.data.rhs + 1 + catch_count];

        for (catches) |catch_idx| {
            const catch_node = self.ast.nodes[catch_idx];
            self.write(" catch (");
            if (catch_node.data.lhs != 0) {
                self.formatNode(catch_node.data.lhs);
                if (catch_node.main_token != 0) self.write(" ");
            }
            if (catch_node.main_token != 0) {
                self.write(self.ast.tokens[catch_node.main_token].lexeme(self.source));
            }
            self.write(")");
            self.formatBlockInline(catch_node.data.rhs);
        }

        if (finally_node != 0) {
            self.write(" finally");
            self.formatBlockInline(finally_node);
        }
    }

    fn formatThrow(self: *Formatter, node: Ast.Node) void {
        self.write("throw ");
        self.formatNode(node.data.lhs);
        self.write(";");
    }

    fn formatNamespaceDecl(self: *Formatter, node: Ast.Node) void {
        self.write("namespace ");
        const parts = self.ast.extraSlice(node.data.lhs);
        for (parts, 0..) |tok_idx, i| {
            if (i > 0) self.write("\\");
            self.write(self.ast.tokens[tok_idx].lexeme(self.source));
        }
        self.write(";");
    }

    fn formatUseStmt(self: *Formatter, node: Ast.Node) void {
        self.write("use ");
        const parts = self.ast.extraSlice(node.data.lhs);
        for (parts, 0..) |tok_idx, i| {
            if (i > 0) self.write("\\");
            self.write(self.ast.tokens[tok_idx].lexeme(self.source));
        }
        if (node.data.rhs != 0) {
            self.write(" as ");
            self.write(self.ast.tokens[node.data.rhs].lexeme(self.source));
        }
        self.write(";");
    }

    fn formatRequire(self: *Formatter, node: Ast.Node) void {
        self.write(self.ast.tokens[node.main_token].lexeme(self.source));
        self.write(" ");
        self.formatNode(node.data.lhs);
    }

    fn formatGlobalStmt(self: *Formatter, node: Ast.Node) void {
        self.write("global ");
        const vars = self.ast.extraSlice(node.data.lhs);
        for (vars, 0..) |v, i| {
            if (i > 0) self.write(", ");
            self.write(self.ast.tokens[self.ast.nodes[v].main_token].lexeme(self.source));
        }
        self.write(";");
    }

    fn formatStaticVar(self: *Formatter, node: Ast.Node) void {
        self.write("static ");
        self.write(self.ast.tokens[node.main_token].lexeme(self.source));
        if (node.data.lhs != 0) {
            self.write(" = ");
            self.formatNode(node.data.lhs);
        }
        self.write(";");
    }

    // classes

    fn formatClassDecl(self: *Formatter, node: Ast.Node) void {
        const name_tok = node.main_token;
        // token before name is `class`, token before that may be `abstract`
        if (name_tok >= 2 and self.ast.tokens[name_tok - 2].tag == .kw_abstract) {
            self.write("abstract ");
        }
        self.write("class ");
        self.write(self.ast.tokens[name_tok].lexeme(self.source));

        // parent + implements from rhs
        const parent = self.ast.extra_data[node.data.rhs];
        const impl_count = self.ast.extra_data[node.data.rhs + 1];
        if (parent != 0) {
            self.write(" extends ");
            self.formatNode(parent);
        }
        if (impl_count > 0) {
            self.write(" implements ");
            var i: u32 = 0;
            while (i < impl_count) : (i += 1) {
                if (i > 0) self.write(", ");
                self.formatNode(self.ast.extra_data[node.data.rhs + 2 + i]);
            }
        }

        self.write(" {");
        const members = self.ast.extraSlice(node.data.lhs);
        if (members.len > 0) {
            self.indent += 1;
            var prev_member_tag: ?NodeTag = null;
            for (members) |member_idx| {
                const member = self.ast.nodes[member_idx];
                const is_method = member.tag == .class_method or member.tag == .static_class_method;
                if (prev_member_tag != null and (is_method or prev_member_tag == .class_method or prev_member_tag == .static_class_method)) {
                    self.blankLine();
                } else {
                    self.newline();
                }
                self.emitTriviaForNode(member_idx);
                self.writeIndent();
                self.formatNode(member_idx);
                prev_member_tag = member.tag;
            }
            self.indent -|= 1;
            self.indentedLine();
        }
        self.write("}");
    }

    fn formatClassMethod(self: *Formatter, node: Ast.Node) void {
        const visibility = (node.data.rhs >> 30) & 0x3;
        const body_idx = node.data.rhs & 0x3FFFFFFF;
        switch (visibility) {
            0 => self.write("public "),
            1 => self.write("protected "),
            2 => self.write("private "),
            else => self.write("public "),
        }
        if (node.tag == .static_class_method) self.write("static ");
        self.write("function ");
        self.write(self.ast.tokens[node.main_token].lexeme(self.source));
        self.write("(");
        self.formatParamList(node.data.lhs);
        self.write(")");
        self.formatReturnType(node.main_token);
        self.formatBlockInline(body_idx);
    }

    fn formatClassProperty(self: *Formatter, node: Ast.Node) void {
        switch (node.data.rhs) {
            0 => self.write("public "),
            1 => self.write("protected "),
            2 => self.write("private "),
            else => self.write("public "),
        }
        if (node.tag == .static_class_property) self.write("static ");
        // emit type hint if present
        self.emitPropertyTypeHint(node.main_token);
        self.write(self.ast.tokens[node.main_token].lexeme(self.source));
        if (node.data.lhs != 0) {
            self.write(" = ");
            self.formatNode(node.data.lhs);
        }
        self.write(";");
    }

    fn emitPropertyTypeHint(self: *Formatter, var_tok: u32) void {
        if (var_tok == 0) return;
        var scan = var_tok;
        while (scan > 0) {
            const prev = self.ast.tokens[scan - 1].tag;
            // scan over type tokens but NOT kw_static (handled by caller)
            if (prev == .identifier or prev == .kw_array or prev == .kw_callable or
                prev == .kw_self or prev == .kw_null or
                prev == .kw_true or prev == .kw_false or prev == .question or
                prev == .pipe or prev == .amp or prev == .backslash)
            {
                scan -= 1;
            } else break;
        }
        if (scan < var_tok) {
            var i = scan;
            while (i < var_tok) : (i += 1) {
                self.write(self.ast.tokens[i].lexeme(self.source));
                if (i + 1 < var_tok) {
                    const cur_end = self.ast.tokens[i].end;
                    const next_start = self.ast.tokens[i + 1].start;
                    if (next_start > cur_end) self.write(" ");
                }
            }
            self.write(" ");
        }
    }

    fn formatEnumDecl(self: *Formatter, node: Ast.Node) void {
        self.write("enum ");
        self.write(self.ast.tokens[node.main_token].lexeme(self.source));

        const backed_type_token = self.ast.extra_data[node.data.rhs];
        const impl_count = self.ast.extra_data[node.data.rhs + 1];
        if (backed_type_token != 0) {
            self.write(": ");
            self.write(self.ast.tokens[backed_type_token].lexeme(self.source));
        }
        if (impl_count > 0) {
            self.write(" implements ");
            var i: u32 = 0;
            while (i < impl_count) : (i += 1) {
                if (i > 0) self.write(", ");
                self.formatNode(self.ast.extra_data[node.data.rhs + 2 + i]);
            }
        }

        self.write(" {");
        const members = self.ast.extraSlice(node.data.lhs);
        if (members.len > 0) {
            self.indent += 1;
            var prev_member_tag: ?NodeTag = null;
            for (members) |member_idx| {
                const member = self.ast.nodes[member_idx];
                const is_method = member.tag == .class_method or member.tag == .static_class_method;
                if (prev_member_tag != null and (is_method or prev_member_tag == .class_method or prev_member_tag == .static_class_method)) {
                    self.blankLine();
                } else {
                    self.newline();
                }
                self.emitTriviaForNode(member_idx);
                self.writeIndent();
                self.formatNode(member_idx);
                prev_member_tag = member.tag;
            }
            self.indent -|= 1;
            self.indentedLine();
        }
        self.write("}");
    }

    fn formatEnumCase(self: *Formatter, node: Ast.Node) void {
        self.write("case ");
        self.write(self.ast.tokens[node.main_token].lexeme(self.source));
        if (node.data.lhs != 0) {
            self.write(" = ");
            self.formatNode(node.data.lhs);
        }
        self.write(";");
    }

    fn formatInterfaceDecl(self: *Formatter, node: Ast.Node) void {
        self.write("interface ");
        self.write(self.ast.tokens[node.main_token].lexeme(self.source));
        if (node.data.rhs != 0) {
            self.write(" extends ");
            self.formatNode(node.data.rhs);
        }
        self.write(" {");
        const methods = self.ast.extraSlice(node.data.lhs);
        if (methods.len > 0) {
            self.indent += 1;
            for (methods) |m| {
                self.blankLine();
                self.writeIndent();
                self.formatNode(m);
            }
            self.indent -|= 1;
            self.indentedLine();
        }
        self.write("}");
    }

    fn formatInterfaceMethod(self: *Formatter, node: Ast.Node) void {
        const mods = self.scanMethodModifiers(node.main_token);
        if (mods.is_abstract) self.write("abstract ");
        if (mods.visibility) |v| {
            self.write(v);
            self.write(" ");
        } else {
            self.write("public ");
        }
        if (mods.is_static) self.write("static ");
        self.write("function ");
        self.write(self.ast.tokens[node.main_token].lexeme(self.source));
        self.write("(");
        self.formatParamList(node.data.lhs);
        self.write(")");
        self.formatReturnType(node.main_token);
        self.write(";");
    }

    const MethodModifiers = struct {
        visibility: ?[]const u8,
        is_abstract: bool,
        is_static: bool,
    };

    fn scanMethodModifiers(self: *Formatter, name_tok: u32) MethodModifiers {
        var result = MethodModifiers{ .visibility = null, .is_abstract = false, .is_static = false };
        if (name_tok < 2) return result;
        var i = name_tok - 2;
        while (true) {
            const tag = self.ast.tokens[i].tag;
            if (tag == .kw_public) {
                result.visibility = "public";
            } else if (tag == .kw_protected) {
                result.visibility = "protected";
            } else if (tag == .kw_private) {
                result.visibility = "private";
            } else if (tag == .kw_abstract) {
                result.is_abstract = true;
            } else if (tag == .kw_static) {
                result.is_static = true;
            } else break;
            if (i == 0) break;
            i -= 1;
        }
        return result;
    }

    fn formatTraitDecl(self: *Formatter, node: Ast.Node) void {
        self.write("trait ");
        self.write(self.ast.tokens[node.main_token].lexeme(self.source));
        self.write(" {");
        const members = self.ast.extraSlice(node.data.lhs);
        if (members.len > 0) {
            self.indent += 1;
            for (members) |m| {
                self.blankLine();
                self.writeIndent();
                self.formatNode(m);
            }
            self.indent -|= 1;
            self.indentedLine();
        }
        self.write("}");
    }

    fn formatTraitUse(self: *Formatter, node: Ast.Node) void {
        self.write("use ");
        const traits = self.ast.extraSlice(node.data.lhs);
        for (traits, 0..) |t, i| {
            if (i > 0) self.write(", ");
            self.formatNode(t);
        }
        self.write(";");
    }

    // expressions

    fn formatBinaryOp(self: *Formatter, node: Ast.Node) void {
        self.formatNode(node.data.lhs);
        const op = self.ast.tokens[node.main_token].lexeme(self.source);
        // dot concatenation uses tight spacing
        if (self.ast.tokens[node.main_token].tag == .dot) {
            self.write(" . ");
        } else {
            self.write(" ");
            self.write(op);
            self.write(" ");
        }
        self.formatNode(node.data.rhs);
    }

    fn formatAssign(self: *Formatter, node: Ast.Node) void {
        self.formatNode(node.data.lhs);
        self.write(" ");
        self.write(self.ast.tokens[node.main_token].lexeme(self.source));
        self.write(" ");
        self.formatNode(node.data.rhs);
    }

    fn formatLogical(self: *Formatter, node: Ast.Node, op: []const u8) void {
        self.formatNode(node.data.lhs);
        self.write(" ");
        self.write(op);
        self.write(" ");
        self.formatNode(node.data.rhs);
    }

    fn formatPrefixOp(self: *Formatter, node: Ast.Node) void {
        const op = self.ast.tokens[node.main_token].lexeme(self.source);
        self.write(op);
        // space after keyword prefix like clone
        if (self.ast.tokens[node.main_token].tag == .kw_clone) self.write(" ");
        self.formatNode(node.data.lhs);
    }

    fn formatPostfixOp(self: *Formatter, node: Ast.Node) void {
        self.formatNode(node.data.lhs);
        self.write(self.ast.tokens[node.main_token].lexeme(self.source));
    }

    fn formatTernary(self: *Formatter, node: Ast.Node) void {
        const parts = self.ast.extra_data[node.data.rhs .. node.data.rhs + 2];
        self.formatNode(node.data.lhs);
        if (parts[0] == 0) {
            self.write(" ?: ");
        } else {
            self.write(" ? ");
            self.formatNode(parts[0]);
            self.write(" : ");
        }
        self.formatNode(parts[1]);
    }

    fn formatCall(self: *Formatter, node: Ast.Node) void {
        self.formatNode(node.data.lhs);
        self.write("(");
        const args = self.ast.extraSlice(node.data.rhs);
        for (args, 0..) |arg, i| {
            if (i > 0) self.write(", ");
            self.formatNode(arg);
        }
        self.write(")");
    }

    fn formatArrayAccess(self: *Formatter, node: Ast.Node) void {
        self.formatNode(node.data.lhs);
        self.write("[");
        self.formatNode(node.data.rhs);
        self.write("]");
    }

    fn formatNamedArg(self: *Formatter, node: Ast.Node) void {
        self.write(self.ast.tokenSlice(node.main_token));
        self.write(": ");
        self.formatNode(node.data.lhs);
    }

    fn formatArrayPushTarget(self: *Formatter, node: Ast.Node) void {
        self.formatNode(node.data.lhs);
        self.write("[]");
    }

    fn formatListDestructure(self: *Formatter, node: Ast.Node) void {
        self.write("list(");
        const slots = self.ast.extraSlice(node.data.lhs);
        for (slots, 0..) |slot, i| {
            if (i > 0) self.write(", ");
            if (slot == 0) continue;
            self.formatNode(slot);
        }
        self.write(")");
    }

    fn formatPropertyAccess(self: *Formatter, node: Ast.Node, nullsafe: bool) void {
        self.formatNode(node.data.lhs);
        if (self.ast.tokens[node.main_token].tag == .colon_colon) {
            self.write("::");
        } else {
            self.write(if (nullsafe) "?->" else "->");
        }
        self.formatNode(node.data.rhs);
    }

    fn formatMethodCall(self: *Formatter, node: Ast.Node, nullsafe: bool) void {
        self.formatNode(node.data.lhs);
        self.write(if (nullsafe) "?->" else "->");
        self.write(self.ast.tokens[node.main_token].lexeme(self.source));
        self.write("(");
        const args = self.ast.extraSlice(node.data.rhs);
        for (args, 0..) |arg, i| {
            if (i > 0) self.write(", ");
            self.formatNode(arg);
        }
        self.write(")");
    }

    fn formatStaticCall(self: *Formatter, node: Ast.Node) void {
        self.formatNode(node.data.lhs);
        self.write("::");
        self.write(self.ast.tokens[node.main_token].lexeme(self.source));
        self.write("(");
        const args = self.ast.extraSlice(node.data.rhs);
        for (args, 0..) |arg, i| {
            if (i > 0) self.write(", ");
            self.formatNode(arg);
        }
        self.write(")");
    }

    fn formatStaticPropAccess(self: *Formatter, node: Ast.Node) void {
        self.formatNode(node.data.lhs);
        self.write("::");
        self.write(self.ast.tokens[node.main_token].lexeme(self.source));
    }

    fn formatNewExpr(self: *Formatter, node: Ast.Node) void {
        self.write("new ");
        if (node.data.rhs != 0) {
            // qualified name from extra
            const parts = self.ast.extraSlice(node.data.rhs);
            for (parts, 0..) |tok_idx, i| {
                if (i > 0) self.write("\\");
                self.write(self.ast.tokens[tok_idx].lexeme(self.source));
            }
        } else {
            self.write(self.ast.tokens[node.main_token].lexeme(self.source));
        }
        self.write("(");
        const args = self.ast.extraSlice(node.data.lhs);
        for (args, 0..) |arg, i| {
            if (i > 0) self.write(", ");
            self.formatNode(arg);
        }
        self.write(")");
    }

    fn formatCastExpr(self: *Formatter, node: Ast.Node) void {
        self.write("(");
        self.write(self.ast.tokens[node.main_token].lexeme(self.source));
        self.write(")");
        self.formatNode(node.data.lhs);
    }

    fn formatClosure(self: *Formatter, node: Ast.Node) void {
        const is_arrow = self.ast.tokens[node.main_token].tag == .kw_fn;
        if (is_arrow) {
            self.write("fn(");
        } else {
            self.write("function(");
        }
        self.formatParamList(node.data.lhs);
        self.write(")");

        // rhs -> {body, use_count, use_vars...}
        const body = self.ast.extra_data[node.data.rhs];
        const use_count = self.ast.extra_data[node.data.rhs + 1];

        if (!is_arrow and use_count > 0) {
            self.write(" use (");
            var i: u32 = 0;
            while (i < use_count) : (i += 1) {
                if (i > 0) self.write(", ");
                const var_node = self.ast.nodes[self.ast.extra_data[node.data.rhs + 2 + i]];
                self.write(self.ast.tokens[var_node.main_token].lexeme(self.source));
            }
            self.write(")");
        }

        if (is_arrow) {
            // arrow function: fn($x) => expr
            // body is a block containing a single return statement
            const block_node = self.ast.nodes[body];
            if (block_node.tag == .block) {
                const stmts = self.ast.extraSlice(block_node.data.lhs);
                if (stmts.len == 1) {
                    const ret = self.ast.nodes[stmts[0]];
                    if (ret.tag == .return_stmt and ret.data.lhs != 0) {
                        self.write(" => ");
                        self.formatNode(ret.data.lhs);
                        return;
                    }
                }
            }
        }

        self.formatBlockInline(body);
    }

    fn formatArrayLiteral(self: *Formatter, node: Ast.Node) void {
        const elements = self.ast.extraSlice(node.data.lhs);
        if (elements.len == 0) {
            self.write("[]");
            return;
        }
        self.write("[");
        for (elements, 0..) |elem, i| {
            if (i > 0) self.write(", ");
            self.formatNode(elem);
        }
        self.write("]");
    }

    fn formatArrayElement(self: *Formatter, node: Ast.Node) void {
        if (node.data.rhs != 0) {
            self.formatNode(node.data.rhs);
            self.write(" => ");
        }
        self.formatNode(node.data.lhs);
    }

    fn formatExprList(self: *Formatter, node: Ast.Node) void {
        const exprs = self.ast.extraSlice(node.data.lhs);
        for (exprs, 0..) |expr, i| {
            if (i > 0) self.write(", ");
            self.formatNode(expr);
        }
    }

    fn formatQualifiedName(self: *Formatter, node: Ast.Node) void {
        const parts = self.ast.extraSlice(node.data.lhs);
        for (parts, 0..) |tok_idx, i| {
            if (i > 0) self.write("\\");
            self.write(self.ast.tokens[tok_idx].lexeme(self.source));
        }
    }
};

pub fn formatSource(allocator: Allocator, ast: *const Ast, source: []const u8) ![]const u8 {
    const trivia = try extractTrivia(allocator, ast.tokens, source);
    defer freeTrivia(allocator, trivia);

    var f = Formatter.init(allocator, ast, source, trivia);
    defer f.deinit();

    // emit <?php tag
    if (ast.tokens.len > 0 and (ast.tokens[0].tag == .open_tag or ast.tokens[0].tag == .open_tag_echo)) {
        f.write("<?php");
        f.newline();
    }

    f.formatRoot();

    return f.toOwnedSlice();
}

fn writeStderr(msg: []const u8) !void {
    _ = try std.posix.write(std.posix.STDERR_FILENO, msg);
}

test "format simple echo" {
    const allocator = std.testing.allocator;
    const source = "<?php   echo  \"hello\" ;";
    var ast = try parser.parse(allocator, source);
    defer ast.deinit();
    const result = try formatSource(allocator, &ast, source);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("<?php\necho \"hello\";\n", result);
}

test "format function" {
    const allocator = std.testing.allocator;
    const source = "<?php function   add( $a,  $b ){return $a+$b;}";
    var ast = try parser.parse(allocator, source);
    defer ast.deinit();
    const result = try formatSource(allocator, &ast, source);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("<?php\nfunction add($a, $b) {\n    return $a + $b;\n}\n", result);
}

test "format class" {
    const allocator = std.testing.allocator;
    const source = "<?php class Foo{public $x=1;public function bar(){return $this->x;}}";
    var ast = try parser.parse(allocator, source);
    defer ast.deinit();
    const result = try formatSource(allocator, &ast, source);
    defer allocator.free(result);
    const expected = "<?php\nclass Foo {\n    public $x = 1;\n\n    public function bar() {\n        return $this->x;\n    }\n}\n";
    try std.testing.expectEqualStrings(expected, result);
}

test "format idempotent" {
    const allocator = std.testing.allocator;
    const source = "<?php\necho \"hello\";\n";
    var ast = try parser.parse(allocator, source);
    defer ast.deinit();
    const result = try formatSource(allocator, &ast, source);
    defer allocator.free(result);
    try std.testing.expectEqualStrings(source, result);
}
