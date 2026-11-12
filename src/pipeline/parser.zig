const std = @import("std");

// a const_decl flag: this name continues the declaration before it
pub const const_continuation: u32 = 1 << 5;
const ast_mod = @import("ast.zig");
const Ast = ast_mod.Ast;
const AttrRange = ast_mod.AttrRange;
const PropertyHooks = ast_mod.PropertyHooks;
const Token = @import("token.zig").Token;
const Lexer = @import("lexer.zig").Lexer;

const Tag = Token.Tag;
const NodeTag = Ast.Node.Tag;
const Allocator = std.mem.Allocator;
const Error = Allocator.Error || error{ParseError};

pub fn parse(allocator: Allocator, source: []const u8) Allocator.Error!Ast {
    var tok_buf = std.ArrayListUnmanaged(Token).empty;
    errdefer tok_buf.deinit(allocator);

    var lexer = Lexer.init(source);
    while (true) {
        const tok = lexer.next();
        try tok_buf.append(allocator, tok);
        if (tok.tag == .eof) break;
    }

    var p = Parser{
        .source = source,
        .tokens = tok_buf.items,
        .pos = 0,
        .nodes = .empty,
        .extra_data = .empty,
        .errors = .empty,
        .attr_ranges = .empty,
        .allocator = allocator,
    };
    errdefer {
        p.nodes.deinit(allocator);
        p.extra_data.deinit(allocator);
        p.errors.deinit(allocator);
        p.attr_ranges.deinit(allocator);
    }

    p.parseRoot() catch |err| switch (err) {
        error.ParseError => {},
        error.OutOfMemory => return error.OutOfMemory,
    };

    const tok_slice = try tok_buf.toOwnedSlice(allocator);
    errdefer allocator.free(tok_slice);
    const nodes_slice = try p.nodes.toOwnedSlice(allocator);
    errdefer allocator.free(nodes_slice);
    const extra_slice = try p.extra_data.toOwnedSlice(allocator);
    errdefer allocator.free(extra_slice);
    const errors_slice = try p.errors.toOwnedSlice(allocator);
    errdefer allocator.free(errors_slice);
    const attr_slice = try p.attr_ranges.toOwnedSlice(allocator);

    return .{
        .halt_offset = if (lexer.halt_offset) |o| @intCast(o) else null,
        .source = source,
        .tokens = tok_slice,
        .nodes = nodes_slice,
        .extra_data = extra_slice,
        .errors = errors_slice,
        .attr_ranges = attr_slice,
        .allocator = allocator,
        .compile_error = p.compile_error,
    };
}

const Parser = struct {
    source: []const u8,
    tokens: []const Token,
    pos: u32,
    compile_error: ?Ast.CompileErrorNote = null,
    // the class whose members are being parsed, for compile error messages
    current_class_name: []const u8 = "",
    // whether the abstract or interface method just parsed had a body
    method_had_body: bool = false,

    nodes: std.ArrayListUnmanaged(Ast.Node),
    extra_data: std.ArrayListUnmanaged(u32),
    errors: std.ArrayListUnmanaged(Ast.Error),
    attr_ranges: std.ArrayListUnmanaged(AttrRange) = .empty,
    allocator: Allocator,
    found_yield: bool = false,
    // a property declaration ended in a comma: another property follows
    property_list_continues: bool = false,
    in_property_list: bool = false,
    // the token where a list() may stand without an `=` after it: the start
    // of an array element or a foreach target. anywhere else php's grammar
    // has list() only as the left side of an assignment
    bare_list_at: u32 = std.math.maxInt(u32),
    pending_top_stmts: std.ArrayListUnmanaged(u32) = .empty,
    // inside a bracketed namespace's body
    in_namespace_block: bool = false,

    // root

    fn parseRoot(self: *Parser) Error!void {
        _ = try self.addNode(.{ .tag = .root, .main_token = 0, .data = .{} });

        var stmts = std.ArrayListUnmanaged(u32).empty;
        defer stmts.deinit(self.allocator);

        while (self.peek() != .eof or self.pending_top_stmts.items.len > 0) {
            if (self.pending_top_stmts.items.len > 0) {
                const drained = self.pending_top_stmts.orderedRemove(0);
                try stmts.append(self.allocator, drained);
                continue;
            }
            const node = self.parseTopLevel() catch |err| switch (err) {
                error.ParseError => {
                    self.synchronize();
                    continue;
                },
                error.OutOfMemory => return error.OutOfMemory,
            };
            try stmts.append(self.allocator, node);
        }
        self.pending_top_stmts.deinit(self.allocator);

        const extra = try self.addExtraList(stmts.items);
        self.nodes.items[0].data.lhs = extra;
    }

    fn parseTopLevel(self: *Parser) Error!u32 {
        while (true) {
            switch (self.peek()) {
                .open_tag, .close_tag => {
                    _ = self.advance();
                    continue;
                },
                .open_tag_echo => return self.parseOpenTagEcho(),
                .inline_html => {
                    const tok = self.advance();
                    return self.addNode(.{ .tag = .inline_html, .main_token = tok, .data = .{} });
                },
                .eof => return error.ParseError,
                else => return self.parseStatement(),
            }
        }
    }

    fn parseOpenTagEcho(self: *Parser) Error!u32 {
        const echo_tok = self.advance();
        const expr = try self.parseExpression();
        if (self.peek() == .semicolon) _ = self.advance();
        const extra = try self.addExtraList(&.{expr});
        return self.addNode(.{ .tag = .echo_stmt, .main_token = echo_tok, .data = .{ .lhs = extra } });
    }

    fn parseStatement(self: *Parser) Error!u32 {
        if (self.peek() == .hash_bracket) {
            try self.parseAttributes();
            return self.parseStatement();
        }
        // handle inline HTML tokens anywhere in statement context
        while (self.peek() == .open_tag or self.peek() == .close_tag) _ = self.advance();
        if (self.peek() == .inline_html) {
            const tok = self.advance();
            return self.addNode(.{ .tag = .inline_html, .main_token = tok, .data = .{} });
        }
        if (self.peek() == .open_tag_echo) return self.parseOpenTagEcho();
        // __HALT_COMPILER(); — stops compilation. PHAR files use it to mark
        // the boundary between the loader stub and the embedded archive.
        // consume the syntactic form and skip everything else to EOF
        if (self.peek() == .identifier and std.mem.eql(u8, self.lexemeAt(0), "__HALT_COMPILER")) {
            const tok = self.advance();
            if (self.peek() == .l_paren) _ = self.advance();
            if (self.peek() == .r_paren) _ = self.advance();
            if (self.peek() == .semicolon) _ = self.advance();
            while (self.peek() != .eof) _ = self.advance();
            return self.addNode(.{ .tag = .empty_stmt, .main_token = tok, .data = .{} });
        }
        return switch (self.peek()) {
            .kw_echo => self.parseEchoStmt(),
            .kw_print => self.parsePrintStmt(),
            .kw_if => self.parseIfStmt(),
            .kw_while => self.parseWhileStmt(),
            .kw_do => self.parseDoWhileStmt(),
            .kw_for => self.parseForStmt(),
            .kw_foreach => self.parseForeachStmt(),
            .kw_function => self.parseFunctionDecl(),
            .kw_const => self.parseConstDecl(),
            .kw_switch => self.parseSwitchStmt(),
            .kw_return => self.parseReturnStmt(),
            .kw_break => self.parseBreakContinue(.break_stmt),
            .kw_continue => self.parseBreakContinue(.continue_stmt),
            // `readonly(...)` calls a function named readonly
            .kw_readonly => if (self.peekAt(1) == .l_paren) self.parseExpressionStmt() else self.parseClassDecl(),
            .kw_class, .kw_abstract, .kw_final => self.parseClassDecl(),
            .kw_interface => self.parseInterfaceDecl(),
            .kw_trait => self.parseTraitDecl(),
            .kw_enum => self.parseEnumDecl(),
            .kw_throw => self.parseThrowStmt(),
            .kw_try => self.parseTryCatch(),
            .kw_declare => self.parseDeclare(),
            .kw_global => self.parseGlobalStmt(),
            .kw_static => self.parseStaticVarStmt(),
            .kw_namespace => self.parseNamespaceDecl(),
            .kw_use => self.parseUseStmt(),
            .kw_goto => self.parseGotoStmt(),
            .kw_require, .kw_require_once, .kw_include, .kw_include_once => self.parseRequireStmt(),
            .l_brace => self.parseBlock(),
            .semicolon => {
                const tok = self.advance();
                // empty statement: emit an empty block so callers (block, if-body, etc.)
                // don't have to recurse past the next non-semicolon token
                const extra = try self.addExtraList(&.{});
                return self.addNode(.{ .tag = .block, .main_token = tok, .data = .{ .lhs = extra } });
            },
            .identifier => {
                if (self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].tag == .colon) {
                    return self.parseLabelStmt();
                }
                return self.parseExpressionStmt();
            },
            else => self.parseExpressionStmt(),
        };
    }

    fn parseStatementOrBlock(self: *Parser) Error!u32 {
        if (self.peek() == .l_brace) return self.parseBlock();
        return self.parseStatement();
    }

    fn parseAltBlock(self: *Parser, terminators: []const Tag) Error!u32 {
        const colon_tok = try self.expect(.colon);
        var stmts = std.ArrayListUnmanaged(u32).empty;
        defer stmts.deinit(self.allocator);

        while (!self.isTerminator(terminators) and self.peek() != .eof) {
            switch (self.peek()) {
                .open_tag, .close_tag => {
                    _ = self.advance();
                    continue;
                },
                .open_tag_echo => {
                    const node = self.parseOpenTagEcho() catch |err| switch (err) {
                        error.ParseError => {
                            self.synchronize();
                            continue;
                        },
                        error.OutOfMemory => return error.OutOfMemory,
                    };
                    try stmts.append(self.allocator, node);
                },
                .inline_html => {
                    const tok = self.advance();
                    const node = try self.addNode(.{ .tag = .inline_html, .main_token = tok, .data = .{} });
                    try stmts.append(self.allocator, node);
                },
                else => {
                    const stmt = self.parseStatement() catch |err| switch (err) {
                        error.ParseError => {
                            self.synchronize();
                            continue;
                        },
                        error.OutOfMemory => return error.OutOfMemory,
                    };
                    try stmts.append(self.allocator, stmt);
                },
            }
        }

        const extra = try self.addExtraList(stmts.items);
        return self.addNode(.{ .tag = .block, .main_token = colon_tok, .data = .{ .lhs = extra } });
    }

    fn isTerminator(self: *Parser, terminators: []const Tag) bool {
        const current = self.peek();
        for (terminators) |t| {
            if (current == t) return true;
        }
        return false;
    }

    fn parseDeclare(self: *Parser) Error!u32 {
        const tok = self.advance(); // declare
        _ = try self.expect(.l_paren);
        while (self.peek() != .r_paren and self.peek() != .eof) _ = self.advance();
        const close = try self.expect(.r_paren);
        var body: u32 = 0;
        if (self.peek() == .semicolon) {
            _ = self.advance();
        } else if (self.peek() == .colon) {
            body = try self.parseAltBlock(&.{.kw_enddeclare});
            _ = try self.expect(.kw_enddeclare);
            _ = try self.expect(.semicolon);
        } else {
            body = try self.parseStatement();
        }
        return self.addNode(.{ .tag = .declare_stmt, .main_token = tok, .data = .{ .lhs = close, .rhs = body } });
    }

    fn parseGotoStmt(self: *Parser) Error!u32 {
        _ = self.advance(); // goto
        const label_tok = try self.expect(.identifier);
        _ = try self.expect(.semicolon);
        return self.addNode(.{ .tag = .goto_stmt, .main_token = label_tok, .data = .{} });
    }

    fn parseLabelStmt(self: *Parser) Error!u32 {
        const label_tok = self.advance(); // identifier
        _ = self.advance(); // colon
        return self.addNode(.{ .tag = .label_stmt, .main_token = label_tok, .data = .{} });
    }

    fn parseGlobalStmt(self: *Parser) Error!u32 {
        const tok = self.advance(); // global
        var vars = std.ArrayListUnmanaged(u32).empty;
        defer vars.deinit(self.allocator);
        while (true) {
            // `global $$name` and `global ${expr}` name the variable at run time
            if (self.peek() == .dollar) {
                try vars.append(self.allocator, try self.parseVariableVariable());
            } else {
                try vars.append(self.allocator, try self.addNode(.{
                    .tag = .variable,
                    .main_token = try self.expect(.variable),
                    .data = .{},
                }));
            }
            if (self.peek() != .comma) break;
            _ = self.advance();
        }
        _ = try self.expect(.semicolon);
        const extra = try self.addExtraList(vars.items);
        return self.addNode(.{ .tag = .global_stmt, .main_token = tok, .data = .{ .lhs = extra } });
    }

    fn parseStaticVarStmt(self: *Parser) Error!u32 {
        if (self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].tag == .colon_colon) return self.parseExpressionStmt();
        const static_tok = self.advance(); // static
        const var_tok = try self.expect(.variable);
        var default: u32 = 0;
        if (self.peek() == .equal) {
            _ = self.advance();
            default = try self.parseExpression();
        }
        if (self.peek() != .comma) {
            _ = try self.expect(.semicolon);
            return self.addNode(.{ .tag = .static_var, .main_token = var_tok, .data = .{ .lhs = default } });
        }
        // multi-variable: static $a = x, $b = y;
        var stmts = std.ArrayListUnmanaged(u32).empty;
        defer stmts.deinit(self.allocator);
        try stmts.append(self.allocator, try self.addNode(.{ .tag = .static_var, .main_token = var_tok, .data = .{ .lhs = default } }));
        while (self.peek() == .comma) {
            _ = self.advance(); // comma
            const next_var = try self.expect(.variable);
            var next_default: u32 = 0;
            if (self.peek() == .equal) {
                _ = self.advance();
                next_default = try self.parseExpression();
            }
            try stmts.append(self.allocator, try self.addNode(.{ .tag = .static_var, .main_token = next_var, .data = .{ .lhs = next_default } }));
        }
        _ = try self.expect(.semicolon);
        const extra = try self.addExtraList(stmts.items);
        return self.addNode(.{ .tag = .block, .main_token = static_tok, .data = .{ .lhs = extra } });
    }

    fn parseNamespaceDecl(self: *Parser) Error!u32 {
        const tok = self.advance(); // namespace
        var parts = std.ArrayListUnmanaged(u32).empty;
        defer parts.deinit(self.allocator);

        // namespace App\Models\User;  or  namespace App\Models { ... }
        // or unnamed:  namespace { ... }
        if (self.peek() == .identifier or isSemiReserved(self.peek())) {
            try parts.append(self.allocator, self.pos);
            _ = self.advance();
            while (self.peek() == .backslash) {
                _ = self.advance();
                // PHP allows reserved words (Default, Use, Catch, etc.) as
                // namespace segments
                try parts.append(self.allocator, self.pos);
                if (self.peek() == .identifier or isSemiReserved(self.peek())) {
                    _ = self.advance();
                } else {
                    _ = try self.expect(.identifier);
                }
            }
        }

        // namespace_decl rhs: 0 `namespace X;`, 1 a bracketed namespace's
        // start, 2 its end, 3 one nested in another (php's compiler refuses
        // it, so its body is parsed and dropped)
        if (self.peek() == .l_brace and self.in_namespace_block) {
            _ = self.advance();
            while (self.peek() != .r_brace and self.peek() != .eof) {
                _ = self.parseStatement() catch |err| switch (err) {
                    error.ParseError => {
                        self.synchronize();
                        continue;
                    },
                    error.OutOfMemory => return error.OutOfMemory,
                };
            }
            _ = try self.expect(.r_brace);
            const nested_extra = try self.addExtraList(parts.items);
            return self.addNode(.{ .tag = .namespace_decl, .main_token = tok, .data = .{ .lhs = nested_extra, .rhs = 3 } });
        }
        if (self.peek() == .l_brace) {
            _ = self.advance(); // {
            self.in_namespace_block = true;
            defer self.in_namespace_block = false;
            const extra = try self.addExtraList(parts.items);
            // queue the namespace_decl as the next statement; remember to emit
            // a closing reset when we hit `}`
            const ns_node = try self.addNode(.{ .tag = .namespace_decl, .main_token = tok, .data = .{ .lhs = extra, .rhs = 1 } });
            try self.pending_top_stmts.append(self.allocator, ns_node);
            // body statements: drain pending then loop
            while (self.peek() != .r_brace and self.peek() != .eof) {
                const node = self.parseStatement() catch |err| switch (err) {
                    error.ParseError => {
                        self.synchronize();
                        continue;
                    },
                    error.OutOfMemory => return error.OutOfMemory,
                };
                try self.pending_top_stmts.append(self.allocator, node);
            }
            _ = try self.expect(.r_brace);
            // emit a reset namespace_decl (to global namespace) so subsequent
            // top-level code parses outside this namespace
            const empty_extra = try self.addExtraList(&.{});
            const reset_node = try self.addNode(.{ .tag = .namespace_decl, .main_token = tok, .data = .{ .lhs = empty_extra, .rhs = 2 } });
            try self.pending_top_stmts.append(self.allocator, reset_node);
            // return the first pending entry; the rest get drained from caller
            const first = self.pending_top_stmts.orderedRemove(0);
            return first;
        }

        _ = try self.expect(.semicolon);
        const extra = try self.addExtraList(parts.items);
        return self.addNode(.{ .tag = .namespace_decl, .main_token = tok, .data = .{ .lhs = extra } });
    }

    fn parseUseStmt(self: *Parser) Error!u32 {
        const tok = self.advance(); // use

        const outer_is_fn = self.peek() == .kw_function;
        const outer_is_const = self.peek() == .kw_const;
        if (outer_is_fn or outer_is_const) _ = self.advance();

        var prefix = std.ArrayListUnmanaged(u32).empty;
        defer prefix.deinit(self.allocator);

        // an imported name is always fully qualified, so a leading `\` changes nothing
        if (self.peek() == .backslash) _ = self.advance();
        try prefix.append(self.allocator, self.pos);
        if (self.peek() == .identifier or isSemiReserved(self.peek())) {
            _ = self.advance();
        } else {
            _ = try self.expect(.identifier);
        }
        while (self.peek() == .backslash) {
            _ = self.advance();
            if (self.peek() == .l_brace) break;
            try prefix.append(self.allocator, self.pos);
            if (self.peek() == .identifier or isSemiReserved(self.peek())) {
                _ = self.advance();
            } else {
                _ = try self.expect(.identifier);
            }
        }

        // group use: use Prefix\{Name [as Alias], ...};
        if (self.peek() == .l_brace) {
            _ = self.advance();
            var stmts = std.ArrayListUnmanaged(u32).empty;
            defer stmts.deinit(self.allocator);

            while (self.peek() != .r_brace and self.peek() != .eof) {
                var item_is_fn = outer_is_fn;
                var item_is_const = outer_is_const;
                if (self.peek() == .kw_function) {
                    _ = self.advance();
                    item_is_fn = true;
                    item_is_const = false;
                } else if (self.peek() == .kw_const) {
                    _ = self.advance();
                    item_is_const = true;
                    item_is_fn = false;
                }
                var item_parts = std.ArrayListUnmanaged(u32).empty;
                defer item_parts.deinit(self.allocator);
                try item_parts.appendSlice(self.allocator, prefix.items);
                try item_parts.append(self.allocator, self.pos);
                if (self.peek() == .identifier or isSemiReserved(self.peek())) {
                    _ = self.advance();
                } else {
                    _ = try self.expect(.identifier);
                }
                while (self.peek() == .backslash) {
                    _ = self.advance();
                    try item_parts.append(self.allocator, self.pos);
                    if (self.peek() == .identifier or isSemiReserved(self.peek())) {
                        _ = self.advance();
                    } else {
                        _ = try self.expect(.identifier);
                    }
                }
                var alias: u32 = 0;
                if (self.peek() == .kw_as) {
                    _ = self.advance();
                    alias = self.pos;
                    _ = try self.expect(.identifier);
                }
                const ex = try self.addExtraList(item_parts.items);
                const t: Ast.Node.Tag = if (item_is_fn) .use_fn_stmt else if (item_is_const) .use_const_stmt else .use_stmt;
                try stmts.append(self.allocator, try self.addNode(.{ .tag = t, .main_token = tok, .data = .{ .lhs = ex, .rhs = alias } }));
                if (self.peek() == .comma) _ = self.advance() else break;
            }
            _ = try self.expect(.r_brace);
            _ = try self.expect(.semicolon);
            const block_extra = try self.addExtraList(stmts.items);
            return self.addNode(.{ .tag = .block, .main_token = tok, .data = .{ .lhs = block_extra } });
        }

        // the first name of a list may have its own alias
        var first_alias: u32 = 0;
        if (self.peek() == .kw_as and self.peekAt(2) == .comma) {
            _ = self.advance();
            first_alias = self.pos;
            _ = try self.expect(.identifier);
        }
        if (self.peek() == .comma) {
            var stmts = std.ArrayListUnmanaged(u32).empty;
            defer stmts.deinit(self.allocator);
            const first_extra = try self.addExtraList(prefix.items);
            const tag: Ast.Node.Tag = if (outer_is_fn) .use_fn_stmt else if (outer_is_const) .use_const_stmt else .use_stmt;
            try stmts.append(self.allocator, try self.addNode(.{ .tag = tag, .main_token = tok, .data = .{ .lhs = first_extra, .rhs = first_alias } }));
            while (self.peek() == .comma) {
                _ = self.advance();
                var parts = std.ArrayListUnmanaged(u32).empty;
                defer parts.deinit(self.allocator);
                if (self.peek() == .backslash) _ = self.advance();
                try parts.append(self.allocator, self.pos);
                if (self.peek() == .identifier or isSemiReserved(self.peek())) _ = self.advance() else _ = try self.expect(.identifier);
                while (self.peek() == .backslash) {
                    _ = self.advance();
                    try parts.append(self.allocator, self.pos);
                    if (self.peek() == .identifier or isSemiReserved(self.peek())) _ = self.advance() else _ = try self.expect(.identifier);
                }
                var item_alias: u32 = 0;
                if (self.peek() == .kw_as) {
                    _ = self.advance();
                    item_alias = self.pos;
                    _ = try self.expect(.identifier);
                }
                const item_extra = try self.addExtraList(parts.items);
                try stmts.append(self.allocator, try self.addNode(.{ .tag = tag, .main_token = tok, .data = .{ .lhs = item_extra, .rhs = item_alias } }));
            }
            _ = try self.expect(.semicolon);
            const block_extra = try self.addExtraList(stmts.items);
            return self.addNode(.{ .tag = .block, .main_token = tok, .data = .{ .lhs = block_extra } });
        }

        var alias: u32 = 0;
        if (self.peek() == .kw_as) {
            _ = self.advance();
            alias = self.pos;
            _ = try self.expect(.identifier);
        }
        _ = try self.expect(.semicolon);

        const extra = try self.addExtraList(prefix.items);
        const tag: Ast.Node.Tag = if (outer_is_fn) .use_fn_stmt else if (outer_is_const) .use_const_stmt else .use_stmt;
        return self.addNode(.{ .tag = tag, .main_token = tok, .data = .{ .lhs = extra, .rhs = alias } });
    }

    fn parseRequireStmt(self: *Parser) Error!u32 {
        const tok = self.advance(); // require/require_once/include/include_once
        const path_expr = try self.parseExpression();
        _ = try self.expect(.semicolon);
        const req = try self.addNode(.{ .tag = .require_expr, .main_token = tok, .data = .{ .lhs = path_expr } });
        return self.addNode(.{ .tag = .expression_stmt, .main_token = 0, .data = .{ .lhs = req } });
    }

    fn parseExpressionStmt(self: *Parser) Error!u32 {
        const expr = try self.parseVoidableExpression();
        _ = try self.expect(.semicolon);
        return self.addNode(.{ .tag = .expression_stmt, .main_token = 0, .data = .{ .lhs = expr } });
    }

    // (void) discards a whole expression. php 8.5 allows it only where a value
    // is thrown away anyway: an expression statement and the expressions of a
    // for header
    fn parseVoidableExpression(self: *Parser) Error!u32 {
        if (self.peek() != .l_paren or !self.isCastExpr() or !std.ascii.eqlIgnoreCase(self.lexemeAt(1), "void")) return self.parseExpression();
        _ = self.advance(); // (
        const void_tok = self.advance();
        _ = self.advance(); // )
        const operand = try self.parseExpression();
        return self.addNode(.{ .tag = .cast_expr, .main_token = void_tok, .data = .{ .lhs = operand } });
    }

    fn parseEchoStmt(self: *Parser) Error!u32 {
        const echo_tok = self.advance();
        var exprs = std.ArrayListUnmanaged(u32).empty;
        defer exprs.deinit(self.allocator);

        try exprs.append(self.allocator, try self.parseExpression());
        while (self.peek() == .comma) {
            _ = self.advance();
            try exprs.append(self.allocator, try self.parseExpression());
        }
        _ = try self.expect(.semicolon);

        const extra = try self.addExtraList(exprs.items);
        return self.addNode(.{ .tag = .echo_stmt, .main_token = echo_tok, .data = .{ .lhs = extra } });
    }

    fn parsePrintStmt(self: *Parser) Error!u32 {
        const tok = self.advance();
        const expr = try self.parseExpression();
        _ = try self.expect(.semicolon);
        const extra = try self.addExtraList(&.{expr});
        return self.addNode(.{ .tag = .echo_stmt, .main_token = tok, .data = .{ .lhs = extra } });
    }

    fn parseReturnStmt(self: *Parser) Error!u32 {
        const tok = self.advance();
        var expr: u32 = 0;
        if (self.peek() != .semicolon and self.peek() != .eof) {
            expr = try self.parseExpression();
        }
        _ = try self.expect(.semicolon);
        return self.addNode(.{ .tag = .return_stmt, .main_token = tok, .data = .{ .lhs = expr } });
    }

    // php takes any expression after break and continue (optional_expr);
    // the compiler refuses all but a positive integer literal. rhs: 0 no
    // operand, 1 an integer literal (the token after the keyword), 2 another
    // literal, 3 any other expression
    fn parseBreakContinue(self: *Parser, tag: NodeTag) Error!u32 {
        const tok = self.advance();
        var level: u32 = 0;
        var kind: u32 = 0;
        if (self.peek() != .semicolon) {
            const next = self.peekAt(1);
            const alone = next == .semicolon;
            if (self.peek() == .integer and alone) {
                const lit = self.tokens[self.pos].lexeme(self.source);
                level = std.fmt.parseInt(u32, lit, 10) catch std.math.maxInt(u32);
                kind = 1;
                _ = self.advance();
            } else if ((self.peek() == .float or self.peek() == .string) and alone) {
                kind = 2;
                _ = self.advance();
            } else {
                _ = try self.parseExpression();
                kind = 3;
            }
        }
        _ = try self.expect(.semicolon);
        return self.addNode(.{ .tag = tag, .main_token = tok, .data = .{ .lhs = level, .rhs = kind } });
    }

    fn parseSimpleStmt(self: *Parser, tag: NodeTag) Error!u32 {
        const tok = self.advance();
        _ = try self.expect(.semicolon);
        return self.addNode(.{ .tag = tag, .main_token = tok, .data = .{} });
    }

    fn parseBlock(self: *Parser) Error!u32 {
        const brace_tok = try self.expect(.l_brace);
        var stmts = std.ArrayListUnmanaged(u32).empty;
        defer stmts.deinit(self.allocator);

        while (self.peek() != .r_brace and self.peek() != .eof) {
            switch (self.peek()) {
                .open_tag, .close_tag => {
                    _ = self.advance();
                    continue;
                },
                .open_tag_echo => {
                    const node = self.parseOpenTagEcho() catch |err| switch (err) {
                        error.ParseError => {
                            self.synchronize();
                            continue;
                        },
                        error.OutOfMemory => return error.OutOfMemory,
                    };
                    try stmts.append(self.allocator, node);
                },
                .inline_html => {
                    const tok = self.advance();
                    const node = try self.addNode(.{ .tag = .inline_html, .main_token = tok, .data = .{} });
                    try stmts.append(self.allocator, node);
                },
                else => {
                    const stmt = self.parseStatement() catch |err| switch (err) {
                        error.ParseError => {
                            self.synchronize();
                            continue;
                        },
                        error.OutOfMemory => return error.OutOfMemory,
                    };
                    try stmts.append(self.allocator, stmt);
                },
            }
        }
        _ = try self.expect(.r_brace);

        const extra = try self.addExtraList(stmts.items);
        return self.addNode(.{ .tag = .block, .main_token = brace_tok, .data = .{ .lhs = extra } });
    }

    // control flow

    fn parseIfStmt(self: *Parser) Error!u32 {
        return self.parseIfStmtInner(false);
    }

    fn parseIfStmtInner(self: *Parser, alt_mode: bool) Error!u32 {
        const if_tok = self.advance();
        _ = try self.expect(.l_paren);
        const cond = try self.parseExpression();
        _ = try self.expect(.r_paren);

        const is_alt = alt_mode or self.peek() == .colon;

        if (is_alt) {
            const then_body = try self.parseAltBlock(&.{ .kw_elseif, .kw_else, .kw_endif });

            if (self.peek() == .kw_elseif) {
                const else_body = try self.parseIfStmtInner(true);
                const extra = try self.addExtra(&.{ then_body, else_body });
                return self.addNode(.{ .tag = .if_else, .main_token = if_tok, .data = .{ .lhs = cond, .rhs = extra } });
            }

            if (self.peek() == .kw_else) {
                _ = self.advance();
                const else_body = try self.parseAltBlock(&.{.kw_endif});
                _ = try self.expect(.kw_endif);
                _ = try self.expect(.semicolon);
                const extra = try self.addExtra(&.{ then_body, else_body });
                return self.addNode(.{ .tag = .if_else, .main_token = if_tok, .data = .{ .lhs = cond, .rhs = extra } });
            }

            _ = try self.expect(.kw_endif);
            _ = try self.expect(.semicolon);
            return self.addNode(.{ .tag = .if_simple, .main_token = if_tok, .data = .{ .lhs = cond, .rhs = then_body } });
        }

        const then_body = try self.parseStatementOrBlock();

        if (self.peek() == .kw_elseif) {
            const else_body = try self.parseIfStmt();
            const extra = try self.addExtra(&.{ then_body, else_body });
            return self.addNode(.{ .tag = .if_else, .main_token = if_tok, .data = .{ .lhs = cond, .rhs = extra } });
        }

        if (self.peek() == .kw_else) {
            _ = self.advance();
            const else_body = try self.parseStatementOrBlock();
            const extra = try self.addExtra(&.{ then_body, else_body });
            return self.addNode(.{ .tag = .if_else, .main_token = if_tok, .data = .{ .lhs = cond, .rhs = extra } });
        }

        return self.addNode(.{ .tag = .if_simple, .main_token = if_tok, .data = .{ .lhs = cond, .rhs = then_body } });
    }

    fn parseWhileStmt(self: *Parser) Error!u32 {
        const tok = self.advance();
        _ = try self.expect(.l_paren);
        const cond = try self.parseExpression();
        _ = try self.expect(.r_paren);

        if (self.peek() == .colon) {
            const body = try self.parseAltBlock(&.{.kw_endwhile});
            _ = try self.expect(.kw_endwhile);
            _ = try self.expect(.semicolon);
            return self.addNode(.{ .tag = .while_stmt, .main_token = tok, .data = .{ .lhs = cond, .rhs = body } });
        }

        const body = try self.parseStatementOrBlock();
        return self.addNode(.{ .tag = .while_stmt, .main_token = tok, .data = .{ .lhs = cond, .rhs = body } });
    }

    fn parseDoWhileStmt(self: *Parser) Error!u32 {
        const tok = self.advance();
        const body = try self.parseStatementOrBlock();
        _ = try self.expect(.kw_while);
        _ = try self.expect(.l_paren);
        const cond = try self.parseExpression();
        _ = try self.expect(.r_paren);
        _ = try self.expect(.semicolon);
        return self.addNode(.{ .tag = .do_while, .main_token = tok, .data = .{ .lhs = body, .rhs = cond } });
    }

    fn parseForStmt(self: *Parser) Error!u32 {
        const tok = self.advance();
        _ = try self.expect(.l_paren);

        const init = if (self.peek() != .semicolon) try self.parseForExprList() else @as(u32, 0);
        _ = try self.expect(.semicolon);
        const cond = if (self.peek() != .semicolon) try self.parseExpression() else @as(u32, 0);
        _ = try self.expect(.semicolon);
        const update = if (self.peek() != .r_paren) try self.parseForExprList() else @as(u32, 0);
        _ = try self.expect(.r_paren);

        if (self.peek() == .colon) {
            const body = try self.parseAltBlock(&.{.kw_endfor});
            _ = try self.expect(.kw_endfor);
            _ = try self.expect(.semicolon);
            const extra = try self.addExtra(&.{ init, cond, update });
            return self.addNode(.{ .tag = .for_stmt, .main_token = tok, .data = .{ .lhs = extra, .rhs = body } });
        }

        const body = try self.parseStatementOrBlock();
        const extra = try self.addExtra(&.{ init, cond, update });
        return self.addNode(.{ .tag = .for_stmt, .main_token = tok, .data = .{ .lhs = extra, .rhs = body } });
    }

    // parse comma-separated expressions for for-loop init/update
    // returns a single expression node if only one, or an expr_list node
    fn parseForExprList(self: *Parser) Error!u32 {
        const first = try self.parseVoidableExpression();
        if (self.peek() != .comma) return first;
        var exprs = std.ArrayListUnmanaged(u32).empty;
        defer exprs.deinit(self.allocator);
        try exprs.append(self.allocator, first);
        while (self.peek() == .comma) {
            _ = self.advance();
            try exprs.append(self.allocator, try self.parseVoidableExpression());
        }
        const extra = try self.addExtraList(exprs.items);
        return self.addNode(.{ .tag = .expr_list, .main_token = 0, .data = .{ .lhs = extra } });
    }

    fn parseForeachStmt(self: *Parser) Error!u32 {
        const tok = self.advance();
        _ = try self.expect(.l_paren);
        const iterable = try self.parseExpression();
        _ = try self.expect(.kw_as);

        var val_by_ref: u32 = 0;
        if (self.peek() == .amp) {
            _ = self.advance();
            val_by_ref = 1;
        }
        self.bare_list_at = self.pos;
        const first = try self.parseExpression();
        var value: u32 = first;
        var key: u32 = 0;

        if (self.peek() == .fat_arrow) {
            // zend_compile_foreach: a key can't be taken by reference
            if (val_by_ref == 1) self.deferCompileError(tok, "Key element cannot be a reference", .{});
            _ = self.advance();
            key = first;
            val_by_ref = 0;
            if (self.peek() == .amp) {
                _ = self.advance();
                val_by_ref = 1;
            }
            self.bare_list_at = self.pos;
            value = try self.parseExpression();
        }

        _ = try self.expect(.r_paren);

        if (self.peek() == .colon) {
            const body = try self.parseAltBlock(&.{.kw_endforeach});
            _ = try self.expect(.kw_endforeach);
            _ = try self.expect(.semicolon);
            const extra = try self.addExtra(&.{ iterable, value, key, val_by_ref });
            return self.addNode(.{ .tag = .foreach_stmt, .main_token = tok, .data = .{ .lhs = extra, .rhs = body } });
        }

        const body = try self.parseStatementOrBlock();
        const extra = try self.addExtra(&.{ iterable, value, key, val_by_ref });
        return self.addNode(.{ .tag = .foreach_stmt, .main_token = tok, .data = .{ .lhs = extra, .rhs = body } });
    }

    // `const A = 1, B = 2;` as a statement: one declaration, or a block of them
    fn parseConstDecl(self: *Parser) Error!u32 {
        const const_tok = self.pos;
        var decls = std.ArrayListUnmanaged(u32).empty;
        defer decls.deinit(self.allocator);
        try self.parseConstList(&decls);
        if (decls.items.len == 1) return decls.items[0];
        const extra = try self.addExtraList(decls.items);
        return self.addNode(.{ .tag = .block, .main_token = const_tok, .data = .{ .lhs = extra } });
    }

    // `const [type] A = expr, B = expr;`: one const_decl node per name, all
    // carrying the declared type
    fn parseConstList(self: *Parser, out: *std.ArrayListUnmanaged(u32)) Error!void {
        _ = self.advance(); // const
        // php 8.3 typed class constants (`const int|string NAME = 1;`): a
        // name followed by `=` is an untyped constant, anything else a type
        const at0 = self.peek();
        var type_range: [2]u32 = .{ 0, 0 };
        if (!((at0 == .identifier or isSemiReserved(at0)) and self.peekAt(1) == .equal)) {
            type_range = self.collectTypeHint();
        }
        var rhs: u32 = 0;
        if (type_range[0] != type_range[1]) {
            const ext = try self.addExtra(&type_range);
            rhs = (ext + 1) << 16;
        }
        // bit 5 marks the names after the first, so the formatter can print
        // the declaration back as one statement
        var continuation: u32 = 0;
        while (true) {
            const name_tok = try self.expectFunctionName();
            _ = try self.expect(.equal);
            const value = try self.parseExpression();
            try out.append(self.allocator, try self.addNode(.{ .tag = .const_decl, .main_token = name_tok, .data = .{ .lhs = value, .rhs = rhs | continuation } }));
            if (self.peek() != .comma) break;
            _ = self.advance();
            continuation = const_continuation;
        }
        _ = try self.expect(.semicolon);
    }

    // class-body constants: each declared name takes the member's visibility
    // and final flag (bits 0-1 visibility, bit 4 final, bit 5 continuation,
    // bits 16+ type extra)
    fn parseConstMembers(self: *Parser, members: *std.ArrayListUnmanaged(u32), flags: u32) Error!void {
        const first = members.items.len;
        try self.parseConstList(members);
        for (members.items[first..]) |cd| {
            const kept = self.nodes.items[cd].data.rhs & (~@as(u32, 0xffff) | const_continuation);
            self.nodes.items[cd].data.rhs = flags | kept;
        }
    }

    fn parseSwitchStmt(self: *Parser) Error!u32 {
        const switch_tok = self.advance(); // switch
        _ = try self.expect(.l_paren);
        const cond = try self.parseExpression();
        _ = try self.expect(.r_paren);

        const is_alt = self.peek() == .colon;
        if (is_alt) {
            _ = self.advance();
        } else {
            _ = try self.expect(.l_brace);
        }

        const end_tag: Tag = if (is_alt) .kw_endswitch else .r_brace;
        // php's grammar allows one stray `;` before the first case
        if (self.peek() == .semicolon) _ = self.advance();

        var cases = std.ArrayListUnmanaged(u32).empty;
        defer cases.deinit(self.allocator);

        while (self.peek() != end_tag and self.peek() != .eof) {
            if (self.peek() == .kw_case) {
                try cases.append(self.allocator, try self.parseSwitchCase(is_alt));
            } else if (self.peek() == .kw_default) {
                try cases.append(self.allocator, try self.parseSwitchDefault(is_alt));
            } else if (self.peek() == .open_tag or self.peek() == .close_tag) {
                _ = self.advance();
            } else if (self.peek() == .inline_html) {
                _ = self.advance();
            } else {
                self.synchronize();
            }
        }

        if (is_alt) {
            _ = try self.expect(.kw_endswitch);
            _ = try self.expect(.semicolon);
        } else {
            _ = try self.expect(.r_brace);
        }

        const extra = try self.addExtraList(cases.items);
        return self.addNode(.{ .tag = .switch_stmt, .main_token = switch_tok, .data = .{ .lhs = cond, .rhs = extra } });
    }

    // php accepts `case 1;` and `default;` as well as the colon (deprecated in 8.5)
    fn expectCaseSeparator(self: *Parser) Error!void {
        if (self.peek() == .semicolon) {
            _ = self.advance();
            return;
        }
        _ = try self.expect(.colon);
    }

    fn parseSwitchCase(self: *Parser, is_alt: bool) Error!u32 {
        const case_tok = self.advance(); // case

        var values = std.ArrayListUnmanaged(u32).empty;
        defer values.deinit(self.allocator);

        try values.append(self.allocator, try self.parseExpression());
        try self.expectCaseSeparator();

        // collect fallthrough cases: case 1: case 2: case 3: body
        while (self.peek() == .kw_case) {
            _ = self.advance();
            try values.append(self.allocator, try self.parseExpression());
            try self.expectCaseSeparator();
        }

        var stmts = std.ArrayListUnmanaged(u32).empty;
        defer stmts.deinit(self.allocator);

        const end_tag: Tag = if (is_alt) .kw_endswitch else .r_brace;
        while (self.peek() != .kw_case and self.peek() != .kw_default and self.peek() != end_tag and self.peek() != .eof) {
            // case body can contain bare ?>HTML<?php fragments terminated by a
            // case/default/`}`. swallow lone PHP tag tokens here so parseStatement
            // isn't called on a r_brace or kw_case after the tag consumes
            if (self.peek() == .open_tag or self.peek() == .close_tag) {
                _ = self.advance();
                continue;
            }
            const stmt = self.parseStatement() catch |err| switch (err) {
                error.ParseError => {
                    self.synchronize();
                    continue;
                },
                error.OutOfMemory => return error.OutOfMemory,
            };
            try stmts.append(self.allocator, stmt);
        }

        const vals_extra = try self.addExtraList(values.items);
        const body_extra = try self.addExtraList(stmts.items);
        return self.addNode(.{ .tag = .switch_case, .main_token = case_tok, .data = .{ .lhs = vals_extra, .rhs = body_extra } });
    }

    fn parseSwitchDefault(self: *Parser, is_alt: bool) Error!u32 {
        const def_tok = self.advance(); // default
        try self.expectCaseSeparator();

        var stmts = std.ArrayListUnmanaged(u32).empty;
        defer stmts.deinit(self.allocator);

        const end_tag: Tag = if (is_alt) .kw_endswitch else .r_brace;
        while (self.peek() != .kw_case and self.peek() != .kw_default and self.peek() != end_tag and self.peek() != .eof) {
            if (self.peek() == .open_tag or self.peek() == .close_tag) {
                _ = self.advance();
                continue;
            }
            const stmt = self.parseStatement() catch |err| switch (err) {
                error.ParseError => {
                    self.synchronize();
                    continue;
                },
                error.OutOfMemory => return error.OutOfMemory,
            };
            try stmts.append(self.allocator, stmt);
        }

        const body_extra = try self.addExtraList(stmts.items);
        return self.addNode(.{ .tag = .switch_default, .main_token = def_tok, .data = .{ .lhs = body_extra } });
    }

    fn parseMatchExpr(self: *Parser) Error!u32 {
        const match_tok = self.advance(); // match
        _ = try self.expect(.l_paren);
        const cond = try self.parseExpression();
        _ = try self.expect(.r_paren);
        _ = try self.expect(.l_brace);

        var arms = std.ArrayListUnmanaged(u32).empty;
        defer arms.deinit(self.allocator);

        while (self.peek() != .r_brace and self.peek() != .eof) {
            try arms.append(self.allocator, try self.parseMatchArm());
            if (self.peek() == .comma) _ = self.advance();
        }
        _ = try self.expect(.r_brace);

        const extra = try self.addExtraList(arms.items);
        return self.addNode(.{ .tag = .match_expr, .main_token = match_tok, .data = .{ .lhs = cond, .rhs = extra } });
    }

    fn parseMatchArm(self: *Parser) Error!u32 {
        if (self.peek() == .kw_default) {
            _ = self.advance();
            _ = try self.expect(.fat_arrow);
            const result = try self.parseExpression();
            const vals_extra = try self.addExtraList(&.{});
            return self.addNode(.{ .tag = .match_arm, .main_token = 0, .data = .{ .lhs = vals_extra, .rhs = result } });
        }

        var values = std.ArrayListUnmanaged(u32).empty;
        defer values.deinit(self.allocator);

        try values.append(self.allocator, try self.parseExpression());
        while (self.peek() == .comma) {
            _ = self.advance();
            if (self.peek() == .fat_arrow) break;
            try values.append(self.allocator, try self.parseExpression());
        }
        if (self.peek() != .fat_arrow) {
            _ = try self.expect(.fat_arrow);
        }
        _ = self.advance(); // consume =>
        const result = try self.parseExpression();
        const vals_extra = try self.addExtraList(values.items);
        return self.addNode(.{ .tag = .match_arm, .main_token = 0, .data = .{ .lhs = vals_extra, .rhs = result } });
    }

    fn parseFunctionDecl(self: *Parser) Error!u32 {
        _ = self.advance();
        const returns_ref = self.peek() == .amp;
        if (returns_ref) _ = self.advance();
        const name_tok = try self.expectFunctionName();
        _ = try self.expect(.l_paren);

        var params = std.ArrayListUnmanaged(u32).empty;
        defer params.deinit(self.allocator);

        if (self.peek() != .r_paren) {
            try params.append(self.allocator, try self.parseParam());
            while (self.peek() == .comma) {
                _ = self.advance();
                if (self.peek() == .r_paren) break;
                try params.append(self.allocator, try self.parseParam());
            }
        }
        _ = try self.expect(.r_paren);

        var ret_range = [2]u32{ 0, 0 };
        if (self.peek() == .colon) {
            _ = self.advance();
            ret_range = self.collectTypeHint();
        }

        const prev_yield = self.found_yield;
        self.found_yield = false;
        const body = try self.parseBlock();
        const is_gen = self.found_yield;
        self.found_yield = prev_yield;

        const extra = try self.addExtraListWithReturnType(params.items, ret_range);
        // body fits in low bits; high bits encode flags: bit 31 = is_generator,
        // bit 30 = returns_ref. body indices are well below 2^30 in practice
        const rhs = body |
            (if (is_gen) @as(u32, 1) << 31 else 0) |
            (if (returns_ref) @as(u32, 1) << 30 else 0);
        return self.addNode(.{ .tag = .function_decl, .main_token = name_tok, .data = .{ .lhs = extra, .rhs = rhs } });
    }

    fn parseThrowStmt(self: *Parser) Error!u32 {
        const tok = self.advance(); // throw
        const expr = try self.parseExpression();
        _ = try self.expect(.semicolon);
        return self.addNode(.{ .tag = .throw_expr, .main_token = tok, .data = .{ .lhs = expr } });
    }

    fn parseTryCatch(self: *Parser) Error!u32 {
        const try_tok = self.advance(); // try
        const try_body = try self.parseBlock();

        var catches = std.ArrayListUnmanaged(u32).empty;
        defer catches.deinit(self.allocator);

        while (self.peek() == .kw_catch) {
            try catches.append(self.allocator, try self.parseCatchClause());
        }

        var finally_node: u32 = 0;
        if (self.peek() == .kw_finally) {
            _ = self.advance();
            finally_node = try self.parseBlock();
        }

        // rhs = extra -> {catch_count, catch_nodes..., finally_node}
        var extra_data = std.ArrayListUnmanaged(u32).empty;
        defer extra_data.deinit(self.allocator);
        try extra_data.append(self.allocator, @intCast(catches.items.len));
        try extra_data.appendSlice(self.allocator, catches.items);
        try extra_data.append(self.allocator, finally_node);
        const rhs_extra = try self.addExtra(extra_data.items);

        return self.addNode(.{ .tag = .try_catch, .main_token = try_tok, .data = .{ .lhs = try_body, .rhs = rhs_extra } });
    }

    fn parseCatchClause(self: *Parser) Error!u32 {
        _ = self.advance(); // catch
        _ = try self.expect(.l_paren);

        var types = std.ArrayListUnmanaged(u32).empty;
        defer types.deinit(self.allocator);

        if (self.peek() == .identifier or self.peek() == .backslash or (self.peek() == .kw_namespace and self.peekAt(1) == .backslash)) {
            try types.append(self.allocator, try self.parseQualifiedName());

            while (self.peek() == .pipe) {
                _ = self.advance();
                try types.append(self.allocator, try self.parseQualifiedName());
            }
        }

        var var_tok: u32 = 0;
        if (self.peek() == .variable) {
            var_tok = self.advance();
        }

        _ = try self.expect(.r_paren);
        const body = try self.parseBlock();

        // lhs = extra -> {type_count, type_nodes...}
        var extra = std.ArrayListUnmanaged(u32).empty;
        defer extra.deinit(self.allocator);
        try extra.append(self.allocator, @intCast(types.items.len));
        try extra.appendSlice(self.allocator, types.items);
        const lhs = try self.addExtra(extra.items);

        return self.addNode(.{ .tag = .catch_clause, .main_token = var_tok, .data = .{ .lhs = lhs, .rhs = body } });
    }

    fn parseNewExpr(self: *Parser) Error!u32 {
        const new_tok = self.advance(); // new

        // attributes preceding an anonymous class: `new #[Attr] class { ... }`
        // skip the attributes (parseAnonymousClass picks them up via the
        // shared attr_ranges target_tok mechanism)
        if (self.peek() == .hash_bracket) {
            try self.parseAttributes();
        }

        // anonymous class: new class (...) { ... }, or new readonly|abstract|final class ...
        if (self.peek() == .kw_class) {
            return self.parseAnonymousClass(new_tok);
        }
        if ((self.peek() == .kw_readonly or self.peek() == .kw_abstract or self.peek() == .kw_final) and self.peekAt(1) == .kw_class) {
            _ = self.advance(); // readonly/abstract/final modifier
            return self.parseAnonymousClass(new_tok);
        }

        // dynamic class name: new $var(...), new $var['key'](...), or php 8's
        // new (expression)(...)
        if (self.peek() == .dollar or self.peek() == .variable or self.peek() == .l_paren) {
            var class_expr: u32 = undefined;
            if (self.peek() == .l_paren) {
                _ = self.advance();
                class_expr = try self.parseExpression();
                _ = try self.expect(.r_paren);
            } else {
                class_expr = try self.parsePrimaryExpr();
            }
            // Class-name expressions support the same dereference chain as
            // ordinary expressions, including `$object->classes[$name]`.
            while (true) {
                if (self.peek() == .l_bracket) {
                    _ = self.advance();
                    const idx = try self.parseExpression();
                    _ = try self.expect(.r_bracket);
                    class_expr = try self.addNode(.{ .tag = .array_access, .main_token = 0, .data = .{ .lhs = class_expr, .rhs = idx } });
                    continue;
                }
                if (self.peek() == .arrow) {
                    _ = self.advance();
                    const prop = if (self.peek() == .variable) blk: {
                        const tok = self.advance();
                        break :blk try self.addNode(.{ .tag = .variable, .main_token = tok, .data = .{} });
                    } else blk: {
                        const tok = try self.expect(.identifier);
                        break :blk try self.addNode(.{ .tag = .identifier, .main_token = tok, .data = .{} });
                    };
                    class_expr = try self.addNode(.{ .tag = .property_access, .main_token = new_tok, .data = .{ .lhs = class_expr, .rhs = prop } });
                    continue;
                }
                break;
            }

            var args = std.ArrayListUnmanaged(u32).empty;
            defer args.deinit(self.allocator);
            if (self.peek() == .l_paren) {
                _ = self.advance();
                if (self.peek() != .r_paren) {
                    try args.append(self.allocator, try self.parseCallArg());
                    while (self.peek() == .comma) {
                        _ = self.advance();
                        if (self.peek() == .r_paren) break;
                        try args.append(self.allocator, try self.parseCallArg());
                    }
                }
                _ = try self.expect(.r_paren);
            }

            const extra = try self.addExtraList(args.items);
            return self.addNode(.{ .tag = .new_expr_dynamic, .main_token = new_tok, .data = .{ .lhs = class_expr, .rhs = extra } });
        }

        // `new namespace\Cls` - class name relative to the current namespace
        var ns_relative = false;
        if (self.peek() == .kw_namespace and self.peekAt(1) == .backslash) {
            _ = self.advance(); // namespace
            _ = self.advance(); // backslash
            ns_relative = true;
        }
        const is_absolute = !ns_relative and self.peek() == .backslash;
        if (is_absolute) _ = self.advance();
        const name_tok = if (self.peek() == .kw_self or self.peek() == .kw_static or self.peek() == .kw_parent)
            self.advance()
        else
            try self.expect(.identifier);

        // new static::$prop() or new self::$prop() - dynamic class from static property
        if (self.peek() == .colon_colon and self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].tag == .variable) {
            var class_expr = try self.addNode(.{ .tag = .identifier, .main_token = name_tok, .data = .{} });
            class_expr = try self.parseStaticAccess(class_expr);
            while (self.peek() == .colon_colon) {
                class_expr = try self.parseStaticAccess(class_expr);
            }
            while (self.peek() == .l_bracket) {
                _ = self.advance();
                const idx = try self.parseExpression();
                _ = try self.expect(.r_bracket);
                class_expr = try self.addNode(.{ .tag = .array_access, .main_token = 0, .data = .{ .lhs = class_expr, .rhs = idx } });
            }
            var dyn_args = std.ArrayListUnmanaged(u32).empty;
            defer dyn_args.deinit(self.allocator);
            if (self.peek() == .l_paren) {
                _ = self.advance();
                if (self.peek() != .r_paren) {
                    try dyn_args.append(self.allocator, try self.parseCallArg());
                    while (self.peek() == .comma) {
                        _ = self.advance();
                        if (self.peek() == .r_paren) break;
                        try dyn_args.append(self.allocator, try self.parseCallArg());
                    }
                }
                _ = try self.expect(.r_paren);
            }
            const dyn_extra = try self.addExtraList(dyn_args.items);
            return self.addNode(.{ .tag = .new_expr_dynamic, .main_token = new_tok, .data = .{ .lhs = class_expr, .rhs = dyn_extra } });
        }

        // consume qualified name parts: \Identifier\Identifier...
        // PHP allows reserved words as namespace segments (Default, Use, Catch, ...)
        var name_parts = std.ArrayListUnmanaged(u32).empty;
        defer name_parts.deinit(self.allocator);
        try name_parts.append(self.allocator, name_tok);
        while (self.peek() == .backslash) {
            _ = self.advance();
            const seg = if (self.peek() == .identifier or isSemiReserved(self.peek()))
                self.advance()
            else
                try self.expect(.identifier);
            try name_parts.append(self.allocator, seg);
        }

        var args = std.ArrayListUnmanaged(u32).empty;
        defer args.deinit(self.allocator);

        if (self.peek() == .l_paren) {
            _ = self.advance();
            if (self.peek() != .r_paren) {
                try args.append(self.allocator, try self.parseCallArg());
                while (self.peek() == .comma) {
                    _ = self.advance();
                    if (self.peek() == .r_paren) break;
                    try args.append(self.allocator, try self.parseCallArg());
                }
            }
            _ = try self.expect(.r_paren);
        }

        const extra = try self.addExtraList(args.items);
        var name_extra: u32 = if (name_parts.items.len > 1)
            try self.addExtraList(name_parts.items)
        else
            @as(u32, 0);
        if (is_absolute) name_extra |= (1 << 31);
        if (ns_relative) name_extra |= (1 << 30);
        return self.addNode(.{ .tag = .new_expr, .main_token = name_tok, .data = .{ .lhs = extra, .rhs = name_extra } });
    }

    // Property metadata stored in the low byte of class_property rhs.
    // bits 0-1: read visibility, bit 2: readonly, bits 3-4: set visibility,
    // bit 5: explicit asymmetric set visibility, bit 7: final.
    inline fn encodePropertyFlags(
        visibility: u32,
        set_visibility: u32,
        has_set_visibility: bool,
        is_readonly: bool,
        is_final: bool,
    ) u32 {
        return visibility |
            (if (is_readonly) @as(u32, 1) << 2 else 0) |
            (set_visibility << 3) |
            (if (has_set_visibility) @as(u32, 1) << 5 else 0) |
            (if (is_final) @as(u32, 1) << 7 else 0);
    }

    fn parseAnonymousClass(self: *Parser, new_tok: u32) Error!u32 {
        _ = self.advance(); // class

        var ctor_args = std.ArrayListUnmanaged(u32).empty;
        defer ctor_args.deinit(self.allocator);
        if (self.peek() == .l_paren) {
            _ = self.advance();
            if (self.peek() != .r_paren) {
                try ctor_args.append(self.allocator, try self.parseCallArg());
                while (self.peek() == .comma) {
                    _ = self.advance();
                    if (self.peek() == .r_paren) break;
                    try ctor_args.append(self.allocator, try self.parseCallArg());
                }
            }
            _ = try self.expect(.r_paren);
        }

        var parent: u32 = 0;
        if (self.peek() == .kw_extends) {
            _ = self.advance();
            parent = try self.parseQualifiedName();
        }

        var implements = std.ArrayListUnmanaged(u32).empty;
        defer implements.deinit(self.allocator);
        if (self.peek() == .kw_implements) {
            _ = self.advance();
            try implements.append(self.allocator, try self.parseQualifiedName());
            while (self.peek() == .comma) {
                _ = self.advance();
                try implements.append(self.allocator, try self.parseQualifiedName());
            }
        }

        _ = try self.expect(.l_brace);

        var members = std.ArrayListUnmanaged(u32).empty;
        defer members.deinit(self.allocator);
        const outer_class = self.current_class_name;
        self.current_class_name = "class@anonymous";
        try self.parseClassMembers(&members);
        self.current_class_name = outer_class;
        _ = try self.expect(.r_brace);

        const members_extra = try self.addExtraList(members.items);

        // rhs: {ctor_arg_count, ctor_args..., parent, impl_count, impls...}
        var rhs_data = std.ArrayListUnmanaged(u32).empty;
        defer rhs_data.deinit(self.allocator);
        try rhs_data.append(self.allocator, @intCast(ctor_args.items.len));
        for (ctor_args.items) |a| try rhs_data.append(self.allocator, a);
        try rhs_data.append(self.allocator, parent);
        try rhs_data.append(self.allocator, @intCast(implements.items.len));
        for (implements.items) |impl| try rhs_data.append(self.allocator, impl);
        const rhs_idx: u32 = @intCast(self.extra_data.items.len);
        try self.extra_data.appendSlice(self.allocator, rhs_data.items);

        return self.addNode(.{ .tag = .anonymous_class, .main_token = new_tok, .data = .{ .lhs = members_extra, .rhs = rhs_idx } });
    }

    fn parseYieldExpr(self: *Parser) Error!u32 {
        self.found_yield = true;
        const tok = self.advance(); // yield

        if (self.peek() == .identifier) {
            const next_tok = self.tokens[self.pos].lexeme(self.source);
            if (std.mem.eql(u8, next_tok, "from")) {
                _ = self.advance(); // consume "from"
                const iterable = try self.parseExprPrec(1);
                return self.addNode(.{ .tag = .yield_from_expr, .main_token = tok, .data = .{ .lhs = iterable } });
            }
        }

        // a token no expression starts with follows a bare yield, as in
        // php's grammar: `yield * -1` multiplies what the yield receives
        switch (self.peek()) {
            .semicolon, .r_paren, .r_bracket, .r_brace, .comma, .eof, .colon, .question, .question_question, .star, .slash, .percent, .dot, .star_star, .equal_equal, .equal_equal_equal, .bang_equal, .bang_equal_equal, .lt, .gt, .lt_equal, .gt_equal, .lt_gt, .spaceship, .amp_amp, .pipe_pipe, .pipe, .caret, .lt_lt, .gt_gt, .kw_and, .kw_or, .kw_xor, .kw_instanceof, .pipe_gt, .close_tag => {
                return self.addNode(.{ .tag = .yield_expr, .main_token = tok, .data = .{} });
            },
            else => {},
        }

        const expr = try self.parseExprPrec(1);

        if (self.peek() == .fat_arrow) {
            _ = self.advance();
            const value = try self.parseExprPrec(1);
            return self.addNode(.{ .tag = .yield_pair_expr, .main_token = tok, .data = .{ .lhs = expr, .rhs = value } });
        }

        return self.addNode(.{ .tag = .yield_expr, .main_token = tok, .data = .{ .lhs = expr } });
    }

    // attributes written before a group (`const A = 1, B = 2;`, `public $a,
    // $b;`) belong to every member, not only the first
    fn shareGroupAttributes(self: *Parser, ranges_before: usize, rest: []const u32) Error!void {
        if (self.attr_ranges.items.len != ranges_before + 1) return;
        const range = self.attr_ranges.items[ranges_before];
        for (rest) |member| {
            var copy = range;
            copy.target_tok = self.nodes.items[member].main_token;
            try self.attr_ranges.append(self.allocator, copy);
        }
    }

    // the members of a class body up to its closing brace, named or anonymous
    fn parseClassMembers(self: *Parser, members: *std.ArrayListUnmanaged(u32)) Error!void {
        while (self.peek() != .r_brace and self.peek() != .eof) {
            const ranges_before = self.attr_ranges.items.len;
            const members_before = members.items.len;
            defer self.shareGroupAttributes(ranges_before, members.items[@min(members_before + 1, members.items.len)..]) catch {};
            try self.parseAttributes();
            var is_static = false;
            var is_abstract = false;
            var is_final = false;
            var is_readonly = false;
            var visibility: u32 = 0; // 0=public, 1=protected, 2=private
            var set_visibility: u32 = 0;
            var has_set_vis = false;
            var has_read_vis = false;
            // `var` declares a public property and takes no other modifier
            const is_var = self.peek() == .kw_var;
            if (is_var) _ = self.advance();
            if (is_var and (self.peek() == .kw_static or !(self.peek() == .variable or self.isTypeName() or self.peek() == .question or self.peek() == .l_paren))) {
                try self.addError(.unexpected_token);
                return error.ParseError;
            }
            while (!is_var and (self.peek() == .kw_public or self.peek() == .kw_protected or
                self.peek() == .kw_private or self.peek() == .kw_static or
                self.peek() == .kw_abstract or self.peek() == .kw_final or self.peek() == .kw_readonly))
            {
                if (self.peek() == .kw_static) {
                    is_static = true;
                    _ = self.advance();
                    continue;
                }
                if (self.peek() == .kw_abstract) {
                    is_abstract = true;
                    _ = self.advance();
                    continue;
                }
                if (self.peek() == .kw_final) {
                    is_final = true;
                    _ = self.advance();
                    continue;
                }
                if (self.peek() == .kw_readonly) {
                    is_readonly = true;
                    _ = self.advance();
                    continue;
                }
                const vis_val: u32 = if (self.peek() == .kw_protected) 1 else if (self.peek() == .kw_private) 2 else 0;
                _ = self.advance();
                if (self.peek() == .l_paren and self.peekAt(1) == .identifier and std.mem.eql(u8, self.lexemeAt(1), "set") and self.peekAt(2) == .r_paren) {
                    _ = self.advance();
                    _ = self.advance();
                    _ = self.advance();
                    if (has_set_vis) {
                        try self.addError(.unexpected_token);
                        return error.ParseError;
                    }
                    set_visibility = vis_val;
                    has_set_vis = true;
                } else {
                    if (has_read_vis) {
                        try self.addError(.unexpected_token);
                        return error.ParseError;
                    }
                    has_read_vis = true;
                    visibility = vis_val;
                }
            }
            if (!has_set_vis) set_visibility = visibility;

            // asymmetric visibility needs a property (static ones too, since
            // php 8.5), and set visibility may not be wider than read visibility
            const starts_property = self.peek() == .variable or self.isTypeName() or
                self.peek() == .question or self.peek() == .l_paren;
            if (has_set_vis and (!starts_property or set_visibility < visibility)) {
                try self.addError(.unexpected_token);
                return error.ParseError;
            }

            if (self.peek() == .kw_use) {
                try members.append(self.allocator, try self.parseTraitUse());
            } else if (self.peek() == .kw_function) {
                if (is_abstract and is_final) self.deferModifierError(self.pos, "Cannot use the final modifier on an abstract method", .{});
                if (is_abstract) {
                    const method = try self.parseInterfaceMethod(is_static);
                    if (visibility == 2) self.deferCompileError(self.nodes.items[method].main_token, "Abstract function {s}::{s}() cannot be declared private", .{ self.current_class_name, self.tokenText(self.nodes.items[method].main_token) });
                    if (self.method_had_body) self.deferCompileError(self.nodes.items[method].main_token, "Abstract function {s}::{s}() cannot contain body", .{ self.current_class_name, self.tokenText(self.nodes.items[method].main_token) });
                    // encode visibility in rhs bits 28-29; abstract is implicit for interface_method tag
                    self.nodes.items[method].data.rhs = self.nodes.items[method].data.rhs | (visibility << 28);
                    try members.append(self.allocator, method);
                } else {
                    const method = try self.parseClassMethod();
                    if (is_static) {
                        self.nodes.items[method].tag = .static_class_method;
                    }
                    // bits 0-27: body index, bit 28: is_final, bits 30-31: visibility
                    self.nodes.items[method].data.rhs = self.nodes.items[method].data.rhs | (visibility << 30) | (if (is_final) @as(u32, 1) << 28 else 0);
                    try members.append(self.allocator, method);
                }
            } else if (self.peek() == .variable) {
                // Asymmetric set visibility requires an explicit property type.
                if (has_set_vis) {
                    try self.addError(.unexpected_token);
                    return error.ParseError;
                }
                const prop = try self.parseClassProperty();
                const hooked = self.nodes.items[prop].tag == .class_property_hooks;
                if (is_static and !hooked) {
                    self.nodes.items[prop].tag = .static_class_property;
                }
                // Property flags are encoded by encodePropertyFlags(); type metadata remains in bits 16+.
                self.nodes.items[prop].data.rhs = encodePropertyFlags(visibility, set_visibility, has_set_vis, is_readonly, is_final) |
                    (if (is_abstract) PropertyHooks.prop_abstract else 0) | (if (is_static and hooked) PropertyHooks.prop_static_hooked else 0);
                try members.append(self.allocator, prop);
                try self.continuePropertyList(members, prop);
            } else if (self.peek() == .kw_const) {
                if (is_static) self.deferModifierError(self.pos, "Cannot use the static modifier on a class constant", .{});
                if (is_abstract) self.deferModifierError(self.pos, "Cannot use the abstract modifier on a class constant", .{});
                if (is_readonly) self.deferModifierError(self.pos, "Cannot use the readonly modifier on a class constant", .{});
                try self.parseConstMembers(members, visibility | (if (is_final) @as(u32, 1) << 4 else 0));
            } else if (self.isTypeName() or self.peek() == .question or self.peek() == .l_paren) {
                const tr = self.collectTypeHint();
                if (self.peek() == .variable) {
                    const prop = try self.parseClassProperty();
                    const hooked = self.nodes.items[prop].tag == .class_property_hooks;
                    if (is_static and !hooked) {
                        self.nodes.items[prop].tag = .static_class_property;
                    }
                    var rhs: u32 = encodePropertyFlags(visibility, set_visibility, has_set_vis, is_readonly, is_final) |
                        (if (is_abstract) PropertyHooks.prop_abstract else 0) | (if (is_static and hooked) PropertyHooks.prop_static_hooked else 0);
                    if (tr[0] != tr[1]) {
                        const ext = try self.addExtra(&tr);
                        rhs |= (ext + 1) << 16;
                    }
                    self.nodes.items[prop].data.rhs = rhs;
                    try members.append(self.allocator, prop);
                    try self.continuePropertyList(members, prop);
                } else {
                    try self.addError(.unexpected_token);
                    return error.ParseError;
                }
            } else {
                try self.addError(.unexpected_token);
                return error.ParseError;
            }
        }
    }

    fn parseClassDecl(self: *Parser) Error!u32 {
        var class_modifiers: u32 = 0;
        while (self.peek() == .kw_abstract or self.peek() == .kw_final or self.peek() == .kw_readonly) {
            if (self.peek() == .kw_abstract) class_modifiers |= 1;
            if (self.peek() == .kw_final) class_modifiers |= 2;
            if (self.peek() == .kw_readonly) class_modifiers |= 4;
            _ = self.advance();
        }
        _ = self.advance(); // class
        const name_tok = if (self.peek() == .kw_enum) self.advance() else try self.expect(.identifier);

        var parent: u32 = 0;
        if (self.peek() == .kw_extends) {
            _ = self.advance();
            parent = try self.parseQualifiedName();
        }

        var implements = std.ArrayListUnmanaged(u32).empty;
        defer implements.deinit(self.allocator);
        if (self.peek() == .kw_implements) {
            _ = self.advance();
            try implements.append(self.allocator, try self.parseQualifiedName());
            while (self.peek() == .comma) {
                _ = self.advance();
                try implements.append(self.allocator, try self.parseQualifiedName());
            }
        }

        _ = try self.expect(.l_brace);

        var members = std.ArrayListUnmanaged(u32).empty;
        defer members.deinit(self.allocator);

        const outer_class = self.current_class_name;
        self.current_class_name = self.tokenText(name_tok);
        try self.parseClassMembers(&members);
        self.current_class_name = outer_class;
        _ = try self.expect(.r_brace);

        const extra = try self.addExtraList(members.items);

        // rhs encodes flags + parent + implements: {class_modifiers, parent_node, implements_count, impl_nodes...}
        var rhs_data = std.ArrayListUnmanaged(u32).empty;
        defer rhs_data.deinit(self.allocator);
        try rhs_data.append(self.allocator, class_modifiers);
        try rhs_data.append(self.allocator, parent);
        try rhs_data.append(self.allocator, @intCast(implements.items.len));
        for (implements.items) |impl| try rhs_data.append(self.allocator, impl);
        const rhs_idx: u32 = @intCast(self.extra_data.items.len);
        try self.extra_data.appendSlice(self.allocator, rhs_data.items);

        return self.addNode(.{ .tag = .class_decl, .main_token = name_tok, .data = .{ .lhs = extra, .rhs = rhs_idx } });
    }

    fn parseInterfaceDecl(self: *Parser) Error!u32 {
        _ = self.advance(); // interface
        const name_tok = try self.expect(.identifier);

        var parents = std.ArrayListUnmanaged(u32).empty;
        defer parents.deinit(self.allocator);
        if (self.peek() == .kw_extends) {
            _ = self.advance();
            try parents.append(self.allocator, try self.parseQualifiedName());
            while (self.peek() == .comma) {
                _ = self.advance();
                try parents.append(self.allocator, try self.parseQualifiedName());
            }
        }

        _ = try self.expect(.l_brace);

        var methods = std.ArrayListUnmanaged(u32).empty;
        defer methods.deinit(self.allocator);

        while (self.peek() != .r_brace and self.peek() != .eof) {
            try self.parseAttributes();
            // the compiler refuses it, as php's does
            if (self.peek() == .kw_use) {
                try methods.append(self.allocator, try self.parseTraitUse());
                continue;
            }
            var is_static = false;
            var is_final = false;
            var is_abstract = false;
            var visibility: u32 = 0;
            while (self.peek() == .kw_public or self.peek() == .kw_protected or
                self.peek() == .kw_private or self.peek() == .kw_static or
                self.peek() == .kw_abstract or self.peek() == .kw_final)
            {
                switch (self.peek()) {
                    .kw_static => is_static = true,
                    .kw_final => is_final = true,
                    .kw_abstract => is_abstract = true,
                    .kw_protected => visibility = 1,
                    .kw_private => visibility = 2,
                    else => {},
                }
                _ = self.advance();
            }
            if (self.peek() == .kw_function) {
                const method = try self.parseInterfaceMethod(is_static);
                const method_name = self.tokenText(self.nodes.items[method].main_token);
                const at = self.nodes.items[method].main_token;
                // zend_begin_method_decl's checks for an interface
                if (visibility != 0) self.deferCompileError(at, "Access type for interface method {s}::{s}() must be public", .{ self.tokenText(name_tok), method_name });
                if (is_final) self.deferCompileError(at, "Interface method {s}::{s}() must not be final", .{ self.tokenText(name_tok), method_name });
                if (is_abstract) self.deferCompileError(at, "Interface method {s}::{s}() must not be abstract", .{ self.tokenText(name_tok), method_name });
                if (self.method_had_body) self.deferCompileError(at, "Interface function {s}::{s}() cannot contain body", .{ self.tokenText(name_tok), method_name });
                try methods.append(self.allocator, method);
            } else if (self.peek() == .kw_const) {
                const first_const = methods.items.len;
                try self.parseConstMembers(&methods, if (is_final) @as(u32, 1) << 4 else 0);
                if (visibility != 0 and methods.items.len > first_const) {
                    const const_name = self.nodes.items[methods.items[first_const]].main_token;
                    self.deferCompileError(const_name, "Access type for interface constant {s}::{s} must be public", .{ self.tokenText(name_tok), self.tokenText(const_name) });
                }
            } else {
                const tr = self.collectTypeHint();
                if (self.peek() != .variable) {
                    try self.addError(.unexpected_token);
                    return error.ParseError;
                }
                const prop_token = self.pos;
                const prop = try self.parseClassProperty();
                if (self.nodes.items[prop].tag != .class_property_hooks) self.deferCompileError(prop_token, "Interfaces may only include hooked properties", .{});
                // the modifiers stay for the compiler to refuse
                var rhs: u32 = encodePropertyFlags(visibility, visibility, false, false, is_final) |
                    (if (is_abstract) PropertyHooks.prop_abstract else 0) | (if (is_static) PropertyHooks.prop_static_hooked else 0);
                if (tr[0] != tr[1]) {
                    const ext = try self.addExtra(&tr);
                    rhs |= (ext + 1) << 16;
                }
                self.nodes.items[prop].data.rhs = rhs;
                try methods.append(self.allocator, prop);
            }
        }
        _ = try self.expect(.r_brace);

        const extra = try self.addExtraList(methods.items);
        var parent_extra: u32 = 0;
        if (parents.items.len > 0) {
            parent_extra = @intCast(self.extra_data.items.len);
            try self.extra_data.append(self.allocator, @intCast(parents.items.len));
            try self.extra_data.appendSlice(self.allocator, parents.items);
        }
        return self.addNode(.{ .tag = .interface_decl, .main_token = name_tok, .data = .{ .lhs = extra, .rhs = parent_extra } });
    }

    // rhs bit 30: static, bit 31: returns by reference; callers put the
    // visibility in bits 28-29
    fn parseInterfaceMethod(self: *Parser, is_static: bool) Error!u32 {
        _ = self.advance(); // function
        const by_ref = self.peek() == .amp;
        if (by_ref) _ = self.advance();
        const name_tok = try self.expectFunctionName();
        _ = try self.expect(.l_paren);

        var params = std.ArrayListUnmanaged(u32).empty;
        defer params.deinit(self.allocator);

        if (self.peek() != .r_paren) {
            try params.append(self.allocator, try self.parseParam());
            while (self.peek() == .comma) {
                _ = self.advance();
                if (self.peek() == .r_paren) break;
                try params.append(self.allocator, try self.parseParam());
            }
        }
        _ = try self.expect(.r_paren);

        var ret_range = [2]u32{ 0, 0 };
        if (self.peek() == .colon) {
            _ = self.advance();
            ret_range = self.collectTypeHint();
        }

        // a body is the compiler's error, not the grammar's
        self.method_had_body = self.peek() == .l_brace;
        if (self.method_had_body) {
            _ = try self.parseBlock();
        } else _ = try self.expect(.semicolon);
        const extra = try self.addExtraListWithReturnType(params.items, ret_range);
        const flags: u32 = (if (is_static) @as(u32, 1) << 30 else 0) | (if (by_ref) @as(u32, 1) << 31 else 0);
        return self.addNode(.{ .tag = .interface_method, .main_token = name_tok, .data = .{ .lhs = extra, .rhs = flags } });
    }

    fn parseTraitDecl(self: *Parser) Error!u32 {
        _ = self.advance(); // trait
        const name_tok = try self.expect(.identifier);
        _ = try self.expect(.l_brace);

        var members = std.ArrayListUnmanaged(u32).empty;
        defer members.deinit(self.allocator);

        while (self.peek() != .r_brace and self.peek() != .eof) {
            try self.parseAttributes();

            var is_static = false;
            var is_abstract = false;
            var is_final = false;
            var is_readonly = false;
            var visibility: u32 = 0; // 0=public, 1=protected, 2=private
            var set_visibility: u32 = 0;
            var has_set_vis = false;
            var has_read_vis = false;

            // `var` declares a public property and takes no other modifier
            const is_var = self.peek() == .kw_var;
            if (is_var) _ = self.advance();
            if (is_var and (self.peek() == .kw_static or !(self.peek() == .variable or self.isTypeName() or self.peek() == .question or self.peek() == .l_paren))) {
                try self.addError(.unexpected_token);
                return error.ParseError;
            }
            while (!is_var and (self.peek() == .kw_public or self.peek() == .kw_protected or
                self.peek() == .kw_private or self.peek() == .kw_static or
                self.peek() == .kw_abstract or self.peek() == .kw_final or self.peek() == .kw_readonly))
            {
                if (self.peek() == .kw_static) {
                    is_static = true;
                    _ = self.advance();
                    continue;
                }
                if (self.peek() == .kw_abstract) {
                    is_abstract = true;
                    _ = self.advance();
                    continue;
                }
                if (self.peek() == .kw_final) {
                    is_final = true;
                    _ = self.advance();
                    continue;
                }
                if (self.peek() == .kw_readonly) {
                    is_readonly = true;
                    _ = self.advance();
                    continue;
                }

                const vis_val: u32 =
                    if (self.peek() == .kw_protected) 1 else if (self.peek() == .kw_private) 2 else 0;

                _ = self.advance();

                if (self.peek() == .l_paren and
                    self.peekAt(1) == .identifier and
                    std.mem.eql(u8, self.lexemeAt(1), "set") and
                    self.peekAt(2) == .r_paren)
                {
                    _ = self.advance();
                    _ = self.advance();
                    _ = self.advance();
                    if (has_set_vis) {
                        try self.addError(.unexpected_token);
                        return error.ParseError;
                    }
                    set_visibility = vis_val;
                    has_set_vis = true;
                } else {
                    if (has_read_vis) {
                        try self.addError(.unexpected_token);
                        return error.ParseError;
                    }
                    has_read_vis = true;
                    visibility = vis_val;
                }
            }

            if (!has_set_vis) set_visibility = visibility;

            const starts_property = self.peek() == .variable or self.isTypeName() or
                self.peek() == .question or self.peek() == .l_paren;
            if (has_set_vis and (!starts_property or set_visibility < visibility)) {
                try self.addError(.unexpected_token);
                return error.ParseError;
            }

            if (self.peek() == .kw_function) {
                if (is_abstract) {
                    const method = try self.parseInterfaceMethod(is_static);
                    self.nodes.items[method].data.rhs |= visibility << 28;
                    try members.append(self.allocator, method);
                    continue;
                }

                const method = try self.parseClassMethod();
                if (is_static) {
                    self.nodes.items[method].tag = .static_class_method;
                }
                self.nodes.items[method].data.rhs |=
                    (visibility << 30) |
                    (if (is_final) @as(u32, 1) << 28 else 0);
                try members.append(self.allocator, method);
            } else if (self.peek() == .variable) {
                if (has_set_vis) {
                    try self.addError(.unexpected_token);
                    return error.ParseError;
                }

                const prop = try self.parseClassProperty();
                if (is_static) {
                    self.nodes.items[prop].tag = .static_class_property;
                }
                self.nodes.items[prop].data.rhs = encodePropertyFlags(
                    visibility,
                    set_visibility,
                    has_set_vis,
                    is_readonly,
                    is_final,
                );
                try members.append(self.allocator, prop);
                try self.continuePropertyList(&members, prop);
            } else if (self.isTypeName() or self.peek() == .question or self.peek() == .l_paren) {
                const tr = self.collectTypeHint();

                if (self.peek() == .variable) {
                    const prop = try self.parseClassProperty();
                    if (is_static) {
                        self.nodes.items[prop].tag = .static_class_property;
                    }

                    var rhs = encodePropertyFlags(
                        visibility,
                        set_visibility,
                        has_set_vis,
                        is_readonly,
                        is_final,
                    );
                    if (tr[0] != tr[1]) {
                        const ext = try self.addExtra(&tr);
                        rhs |= (ext + 1) << 16;
                    }

                    self.nodes.items[prop].data.rhs = rhs;
                    try members.append(self.allocator, prop);
                    try self.continuePropertyList(&members, prop);
                } else {
                    try self.addError(.unexpected_token);
                    return error.ParseError;
                }
            } else if (self.peek() == .kw_const) {
                try self.parseConstMembers(&members, visibility | (if (is_final) @as(u32, 1) << 4 else 0));
            } else if (self.peek() == .kw_use) {
                try members.append(self.allocator, try self.parseTraitUse());
            } else {
                try self.addError(.unexpected_token);
                return error.ParseError;
            }
        }

        _ = try self.expect(.r_brace);
        const extra = try self.addExtraList(members.items);
        return self.addNode(.{
            .tag = .trait_decl,
            .main_token = name_tok,
            .data = .{ .lhs = extra },
        });
    }

    fn parseEnumDecl(self: *Parser) Error!u32 {
        _ = self.advance(); // enum
        const name_tok = try self.expect(.identifier);

        // the backing type's first token; the compiler reads the whole type
        // to refuse anything but int and string
        var backed_type_token: u32 = 0;
        if (self.peek() == .colon) {
            _ = self.advance();
            backed_type_token = self.pos;
            self.skipTypeHint();
            if (self.pos == backed_type_token) _ = self.advance();
        }

        var implements = std.ArrayListUnmanaged(u32).empty;
        defer implements.deinit(self.allocator);
        if (self.peek() == .kw_implements) {
            _ = self.advance();
            try implements.append(self.allocator, try self.parseQualifiedName());
            while (self.peek() == .comma) {
                _ = self.advance();
                try implements.append(self.allocator, try self.parseQualifiedName());
            }
        }

        _ = try self.expect(.l_brace);

        var members = std.ArrayListUnmanaged(u32).empty;
        defer members.deinit(self.allocator);

        while (self.peek() != .r_brace and self.peek() != .eof) {
            try self.parseAttributes();
            if (self.peek() == .kw_case) {
                _ = self.advance();
                // PHP allows reserved words as enum case names (Array, Bool, Int, etc.)
                const case_name = if (self.peek() == .identifier or isSemiReserved(self.peek()))
                    self.advance()
                else
                    try self.expect(.identifier);
                var value_expr: u32 = 0;
                if (self.peek() == .equal) {
                    _ = self.advance();
                    value_expr = try self.parseExpression();
                }
                _ = try self.expect(.semicolon);
                try members.append(self.allocator, try self.addNode(.{
                    .tag = .enum_case,
                    .main_token = case_name,
                    .data = .{ .lhs = value_expr },
                }));
            } else if (self.peek() == .kw_const) {
                try self.parseConstMembers(&members, 0);
            } else if (self.peek() == .kw_use) {
                try members.append(self.allocator, try self.parseTraitUse());
            } else {
                var is_static = false;
                var is_final = false;
                var is_abstract = false;
                var visibility: u32 = 0;
                while (self.peek() == .kw_public or self.peek() == .kw_protected or
                    self.peek() == .kw_private or self.peek() == .kw_static or self.peek() == .kw_final or
                    self.peek() == .kw_abstract or self.peek() == .kw_readonly or self.peek() == .kw_var)
                {
                    if (self.peek() == .kw_static) is_static = true;
                    if (self.peek() == .kw_final) is_final = true;
                    if (self.peek() == .kw_abstract) is_abstract = true;
                    if (self.peek() == .kw_protected) visibility = 1;
                    if (self.peek() == .kw_private) visibility = 2;
                    _ = self.advance();
                }
                // an abstract method or a property is the compiler's error
                if (self.peek() == .kw_function and is_abstract) {
                    try members.append(self.allocator, try self.parseInterfaceMethod(is_static));
                } else if (self.peek() == .variable or (self.peek() != .kw_function and self.peek() != .kw_const and (self.isTypeName() or self.peek() == .question or self.peek() == .l_paren))) {
                    _ = self.collectTypeHint();
                    if (self.peek() != .variable) {
                        try self.addError(.unexpected_token);
                        return error.ParseError;
                    }
                    try members.append(self.allocator, try self.parseClassProperty());
                } else if (self.peek() == .kw_function) {
                    const method = try self.parseClassMethod();
                    if (is_static) {
                        self.nodes.items[method].tag = .static_class_method;
                    }
                    self.nodes.items[method].data.rhs = self.nodes.items[method].data.rhs | (visibility << 30) | (if (is_final) @as(u32, 1) << 28 else 0);
                    try members.append(self.allocator, method);
                } else if (self.peek() == .kw_const) {
                    try self.parseConstMembers(&members, visibility | (if (is_final) @as(u32, 1) << 4 else 0));
                } else {
                    try self.addError(.unexpected_token);
                    return error.ParseError;
                }
            }
        }
        _ = try self.expect(.r_brace);

        const extra = try self.addExtraList(members.items);

        var rhs_data = std.ArrayListUnmanaged(u32).empty;
        defer rhs_data.deinit(self.allocator);
        try rhs_data.append(self.allocator, backed_type_token);
        try rhs_data.append(self.allocator, @intCast(implements.items.len));
        for (implements.items) |impl| try rhs_data.append(self.allocator, impl);
        const rhs_idx: u32 = @intCast(self.extra_data.items.len);
        try self.extra_data.appendSlice(self.allocator, rhs_data.items);

        return self.addNode(.{ .tag = .enum_decl, .main_token = name_tok, .data = .{ .lhs = extra, .rhs = rhs_idx } });
    }

    fn parseTraitUse(self: *Parser) Error!u32 {
        const use_tok = self.advance(); // use
        var traits = std.ArrayListUnmanaged(u32).empty;
        defer traits.deinit(self.allocator);

        try traits.append(self.allocator, try self.parseQualifiedName());
        while (self.peek() == .comma) {
            _ = self.advance();
            try traits.append(self.allocator, try self.parseQualifiedName());
        }

        var conflicts = std.ArrayListUnmanaged(u32).empty;
        defer conflicts.deinit(self.allocator);

        if (self.peek() == .l_brace) {
            _ = self.advance();
            while (self.peek() != .r_brace and self.peek() != .eof) {
                // TraitName::method insteadof OtherTrait;
                // TraitName::method as alias;
                // TraitName::method as public alias;
                // method as alias;
                // method as public;
                const first_node = try self.parseQualifiedName();
                var trait_node: u32 = 0;
                var method_tok: u32 = 0;

                if (self.peek() == .colon_colon) {
                    _ = self.advance();
                    trait_node = first_node;
                    method_tok = try self.expectFunctionName();
                } else {
                    method_tok = self.nodes.items[first_node].main_token;
                }

                if (self.peek() == .kw_insteadof) {
                    _ = self.advance();
                    var excluded = std.ArrayListUnmanaged(u32).empty;
                    defer excluded.deinit(self.allocator);
                    try excluded.append(self.allocator, try self.parseQualifiedName());
                    while (self.peek() == .comma) {
                        _ = self.advance();
                        try excluded.append(self.allocator, try self.parseQualifiedName());
                    }
                    const excluded_extra = try self.addExtraList(excluded.items);
                    try conflicts.append(self.allocator, try self.addNode(.{
                        .tag = .trait_insteadof,
                        .main_token = method_tok,
                        .data = .{ .lhs = trait_node, .rhs = excluded_extra },
                    }));
                } else if (self.peek() == .kw_as) {
                    _ = self.advance();
                    // php's trait_alias: `as name`, `as modifier`, or
                    // `as modifier name`; a modifier is any member modifier
                    // (the compiler refuses static and abstract)
                    var modifier_tok: u32 = 0;
                    switch (self.peek()) {
                        .kw_public, .kw_protected, .kw_private, .kw_static, .kw_abstract, .kw_final, .kw_readonly => modifier_tok = self.advance(),
                        else => {},
                    }
                    var alias_tok: u32 = 0;
                    // an alias may be any name, a keyword too
                    if (self.peek() == .identifier or isSemiReserved(self.peek())) {
                        alias_tok = self.advance();
                    } else if (modifier_tok == 0) {
                        try self.addError(expectedError(.identifier));
                        return error.ParseError;
                    }
                    try conflicts.append(self.allocator, try self.addNode(.{
                        .tag = .trait_as,
                        .main_token = method_tok,
                        .data = .{ .lhs = trait_node, .rhs = try self.addExtra(&.{ modifier_tok, alias_tok }) },
                    }));
                }
                _ = try self.expect(.semicolon);
            }
            _ = try self.expect(.r_brace);
        } else {
            _ = try self.expect(.semicolon);
        }

        const trait_extra = try self.addExtraList(traits.items);
        const conflict_extra: u32 = if (conflicts.items.len > 0) try self.addExtraList(conflicts.items) else 0;
        return self.addNode(.{ .tag = .trait_use, .main_token = use_tok, .data = .{ .lhs = trait_extra, .rhs = conflict_extra } });
    }

    fn parseClassMethod(self: *Parser) Error!u32 {
        _ = self.advance(); // function
        const returns_ref = self.peek() == .amp;
        if (returns_ref) _ = self.advance();
        const name_tok = try self.expectFunctionName();
        _ = try self.expect(.l_paren);

        var params = std.ArrayListUnmanaged(u32).empty;
        defer params.deinit(self.allocator);

        if (self.peek() != .r_paren) {
            try params.append(self.allocator, try self.parseParam());
            while (self.peek() == .comma) {
                _ = self.advance();
                if (self.peek() == .r_paren) break;
                try params.append(self.allocator, try self.parseParam());
            }
        }
        _ = try self.expect(.r_paren);

        var ret_range = [2]u32{ 0, 0 };
        if (self.peek() == .colon) {
            _ = self.advance();
            ret_range = self.collectTypeHint();
        }

        const prev_yield = self.found_yield;
        self.found_yield = false;
        const body = try self.parseBlock();
        const is_gen = self.found_yield;
        self.found_yield = prev_yield;

        const extra = try self.addExtraListWithReturnType(params.items, ret_range);
        // bits 0-26: body index, bit 27: returns_ref, bit 28: is_final
        // (set by class parser), bit 29: generator, bits 30-31: visibility
        const rhs = body |
            (if (is_gen) @as(u32, 1) << 29 else 0) |
            (if (returns_ref) @as(u32, 1) << 27 else 0);
        return self.addNode(.{ .tag = .class_method, .main_token = name_tok, .data = .{ .lhs = extra, .rhs = rhs } });
    }

    // one property of a declaration; a comma after it (property_list)
    // leaves more for continuePropertyList, which only a property without
    // hooks may have
    fn parseClassProperty(self: *Parser) Error!u32 {
        const tok = try self.expect(.variable);
        var default: u32 = 0;
        if (self.peek() == .equal) {
            _ = self.advance();
            default = try self.parseExpression();
        }
        self.property_list_continues = false;
        if (self.peek() == .l_brace and !self.in_property_list) {
            return self.parsePropertyHooks(tok, default);
        }
        if (self.peek() == .comma) {
            _ = self.advance();
            self.property_list_continues = true;
        } else {
            _ = try self.expect(.semicolon);
        }
        return self.addNode(.{ .tag = .class_property, .main_token = tok, .data = .{ .lhs = default } });
    }

    // the rest of `public int $a = 1, $b;`: each property shares the first
    // one's modifiers and type
    fn continuePropertyList(self: *Parser, members: *std.ArrayListUnmanaged(u32), first: u32) Error!void {
        self.in_property_list = true;
        defer self.in_property_list = false;
        while (self.property_list_continues) {
            const prop = try self.parseClassProperty();
            self.nodes.items[prop].tag = self.nodes.items[first].tag;
            self.nodes.items[prop].data.rhs = self.nodes.items[first].data.rhs;
            try members.append(self.allocator, prop);
        }
    }

    fn parsePropertyHooks(self: *Parser, name_tok: u32, default: u32) Error!u32 {
        _ = self.advance(); // {
        var get_body: u32 = 0;
        var set_body: u32 = 0;
        var set_param_tok: u32 = 0;
        var get_short: u32 = 0;
        var set_short: u32 = 0;
        var set_type_start: u32 = 0;
        var set_type_end: u32 = 0;
        var have_get = false;
        var have_set = false;
        // every hook as written, for the compiler's checks (see
        // ast.PropertyHooks)
        var written = std.ArrayListUnmanaged(u32).empty;
        defer written.deinit(self.allocator);
        const hook_nodes_start = self.nodes.items.len;
        while (self.peek() != .r_brace and self.peek() != .eof) {
            try self.parseAttributes();
            var flags: u32 = 0;
            var other_modifier: u32 = 0;
            while (true) {
                switch (self.peek()) {
                    .kw_final => flags |= PropertyHooks.hook_final,
                    .kw_public, .kw_protected, .kw_private, .kw_static, .kw_readonly, .kw_var, .kw_abstract => {
                        if (other_modifier == 0) other_modifier = self.pos;
                    },
                    else => break,
                }
                _ = self.advance();
            }
            const is_ref = self.peek() == .amp;
            if (is_ref) {
                flags |= PropertyHooks.hook_ref;
                _ = self.advance();
            }
            const hook_tok = try self.expect(.identifier);
            const hook_name = self.tokens[hook_tok].lexeme(self.source);
            // only the first hook of each kind compiles; a repeated one is
            // the compiler's error
            const is_get = std.ascii.eqlIgnoreCase(hook_name, "get") and !have_get;
            const is_set = std.ascii.eqlIgnoreCase(hook_name, "set") and !have_set;
            if (is_get) have_get = true;
            if (is_set) have_set = true;

            var params: u32 = PropertyHooks.no_hook_params;
            if (self.peek() == .l_paren) {
                _ = self.advance();
                var list = std.ArrayListUnmanaged(u32).empty;
                defer list.deinit(self.allocator);
                while (self.peek() != .r_paren) {
                    try list.append(self.allocator, try self.parseParam());
                    if (self.peek() != .comma) break;
                    _ = self.advance();
                }
                _ = try self.expect(.r_paren);
                params = try self.addExtraList(list.items);
                if (is_set and list.items.len > 0) {
                    const pnode = self.nodes.items[list.items[0]];
                    set_param_tok = pnode.main_token;
                    const type_extra = pnode.data.rhs >> 8;
                    if (type_extra != 0) {
                        set_type_start = self.extra_data.items[type_extra - 1];
                        set_type_end = self.extra_data.items[type_extra];
                    }
                }
            }

            const prev_yield = self.found_yield;
            self.found_yield = false;
            defer self.found_yield = prev_yield;

            var body: u32 = 0;
            var short: u32 = 0;
            if (self.peek() == .fat_arrow) {
                _ = self.advance();
                body = try self.parseExpression();
                _ = try self.expect(.semicolon);
                short = 1;
            } else if (self.peek() == .l_brace) {
                body = try self.parseBlock();
            } else {
                _ = try self.expect(.semicolon);
                // Preserve body-less hooks independently from absent hooks.
                short = 8;
                flags |= PropertyHooks.hook_bodyless;
            }
            if (flags & PropertyHooks.hook_final != 0) short |= 16;
            if (is_get and is_ref) short |= 4;
            // Hook flags: bit 0 = short expression, bit 1 = generator, bit 2 = reference.
            if (self.found_yield) short |= 2;
            if (is_get) {
                get_body = body;
                get_short = short;
            } else if (is_set) {
                set_body = body;
                set_short = short;
            }
            try written.appendSlice(self.allocator, &.{ hook_tok, flags, params, other_modifier });
        }
        const written_idx = try self.addExtraList(written.items);
        _ = try self.expect(.r_brace);

        // Backing is a syntactic access to this property's storage in either body.
        // A short setter implicitly writes that storage.
        var backed = (set_short & 1) != 0;
        for (self.nodes.items[hook_nodes_start..]) |n| {
            if (n.tag != .property_access) continue;
            const receiver = self.nodes.items[n.data.lhs];
            if (receiver.tag != .variable or !std.mem.eql(u8, self.tokens[receiver.main_token].lexeme(self.source), "$this")) continue;
            const prop_node = self.nodes.items[n.data.rhs];
            if (n.main_token == 0 or self.tokens[prop_node.main_token].tag == .variable) continue;
            const property = self.tokens[prop_node.main_token].lexeme(self.source);
            if (std.mem.eql(u8, property, self.tokens[name_tok].lexeme(self.source)[1..])) backed = true;
        }
        if (backed) get_short |= 32;

        const extra_idx = try self.addExtra(&[_]u32{ default, get_body, set_body, set_param_tok, get_short, set_short, set_type_start, set_type_end, written_idx });
        return self.addNode(.{ .tag = .class_property_hooks, .main_token = name_tok, .data = .{ .lhs = extra_idx } });
    }

    fn parseClosureExpr(self: *Parser) Error!u32 {
        var is_static = false;
        if (self.peek() == .kw_static) {
            is_static = true;
            _ = self.advance();
        }
        const fn_tok = self.advance(); // function
        const returns_ref = self.peek() == .amp;
        if (returns_ref) _ = self.advance();
        _ = try self.expect(.l_paren);

        var params = std.ArrayListUnmanaged(u32).empty;
        defer params.deinit(self.allocator);

        if (self.peek() != .r_paren) {
            try params.append(self.allocator, try self.parseParam());
            while (self.peek() == .comma) {
                _ = self.advance();
                if (self.peek() == .r_paren) break;
                try params.append(self.allocator, try self.parseParam());
            }
        }
        _ = try self.expect(.r_paren);

        var use_vars = std.ArrayListUnmanaged(u32).empty;
        defer use_vars.deinit(self.allocator);

        if (self.peek() == .kw_use) {
            _ = self.advance();
            _ = try self.expect(.l_paren);
            if (self.peek() != .r_paren) {
                var is_ref: u32 = 0;
                if (self.peek() == .amp) {
                    _ = self.advance();
                    is_ref = 1;
                }
                const tok = try self.expect(.variable);
                try use_vars.append(self.allocator, try self.addNode(.{ .tag = .variable, .main_token = tok, .data = .{ .rhs = is_ref } }));
                while (self.peek() == .comma) {
                    _ = self.advance();
                    if (self.peek() == .r_paren) break;
                    is_ref = 0;
                    if (self.peek() == .amp) {
                        _ = self.advance();
                        is_ref = 1;
                    }
                    const vtok = try self.expect(.variable);
                    try use_vars.append(self.allocator, try self.addNode(.{ .tag = .variable, .main_token = vtok, .data = .{ .rhs = is_ref } }));
                }
            }
            _ = try self.expect(.r_paren);
        }

        var ret_range = [2]u32{ 0, 0 };
        if (self.peek() == .colon) {
            _ = self.advance();
            ret_range = self.collectTypeHint();
        }

        const prev_yield = self.found_yield;
        self.found_yield = false;
        const body = try self.parseBlock();
        const is_gen = self.found_yield;
        self.found_yield = prev_yield;

        const param_extra = try self.addExtraListWithReturnType(params.items, ret_range);

        // rhs = extra -> {body (bit 31 = generator, bit 30 = static, bit 29 =
        // returns by reference), use_count, use_vars...}
        var rhs_data = std.ArrayListUnmanaged(u32).empty;
        defer rhs_data.deinit(self.allocator);
        try rhs_data.append(self.allocator, body | (if (is_gen) @as(u32, 1) << 31 else 0) | (if (is_static) @as(u32, 1) << 30 else 0) | (if (returns_ref) @as(u32, 1) << 29 else 0));
        try rhs_data.append(self.allocator, @intCast(use_vars.items.len));
        try rhs_data.appendSlice(self.allocator, use_vars.items);
        const rhs_extra = try self.addExtra(rhs_data.items);

        return self.addNode(.{ .tag = .closure_expr, .main_token = fn_tok, .data = .{ .lhs = param_extra, .rhs = rhs_extra } });
    }

    fn parseArrowFunc(self: *Parser, is_static: bool) Error!u32 {
        const fn_tok = self.advance(); // fn
        const returns_ref = self.peek() == .amp;
        if (returns_ref) _ = self.advance();
        _ = try self.expect(.l_paren);

        var params = std.ArrayListUnmanaged(u32).empty;
        defer params.deinit(self.allocator);

        if (self.peek() != .r_paren) {
            try params.append(self.allocator, try self.parseParam());
            while (self.peek() == .comma) {
                _ = self.advance();
                if (self.peek() == .r_paren) break;
                try params.append(self.allocator, try self.parseParam());
            }
        }
        _ = try self.expect(.r_paren);

        var ret_range = [2]u32{ 0, 0 };
        if (self.peek() == .colon) {
            _ = self.advance();
            ret_range = self.collectTypeHint();
        }

        _ = try self.expect(.fat_arrow);
        // an arrow function whose expression yields is a generator
        const prev_yield = self.found_yield;
        self.found_yield = false;
        const expr = try self.parseExpression();
        const is_gen = self.found_yield;
        self.found_yield = prev_yield;

        const ret = try self.addNode(.{ .tag = .return_stmt, .main_token = fn_tok, .data = .{ .lhs = expr } });
        const block_extra = try self.addExtraList(&.{ret});
        const body = try self.addNode(.{ .tag = .block, .main_token = fn_tok, .data = .{ .lhs = block_extra } });

        const param_extra = try self.addExtraListWithReturnType(params.items, ret_range);
        // rhs = extra -> {body (bit 30 = static), use_count}.
        // 0xFFFFFFFF signals arrow fn (implicit capture).
        const encoded_body = body | (if (is_gen) @as(u32, 1) << 31 else 0) | (if (is_static) @as(u32, 1) << 30 else 0) | (if (returns_ref) @as(u32, 1) << 29 else 0);
        const rhs_extra = try self.addExtra(&.{ encoded_body, 0xFFFFFFFF });

        return self.addNode(.{ .tag = .closure_expr, .main_token = fn_tok, .data = .{ .lhs = param_extra, .rhs = rhs_extra } });
    }

    fn parseStaticArrowFunc(self: *Parser) Error!u32 {
        _ = self.advance(); // static
        return self.parseArrowFunc(true);
    }

    // parse a qualified name like App\Models\User or just User
    // returns an identifier node for simple names, qualified_name node for multi-part
    // data.rhs = 1 means absolute (had leading \)
    // qualified_name data.rhs: 0 = plain (alias + namespace resolution),
    // 1 = absolute (leading backslash), 2 = `namespace\` relative operator
    fn parseQualifiedName(self: *Parser) Error!u32 {
        // `namespace\X` resolves X relative to the current namespace and skips
        // use-alias lookup (PHP's relative-namespace operator)
        var ns_relative = false;
        if (self.peek() == .kw_namespace and self.peekAt(1) == .backslash) {
            _ = self.advance(); // namespace
            _ = self.advance(); // backslash
            ns_relative = true;
        }
        const has_leading = !ns_relative and self.peek() == .backslash;
        if (has_leading) _ = self.advance();

        const first_tok = if (self.peek() == .identifier or isSemiReserved(self.peek()))
            self.advance()
        else
            try self.expect(.identifier);
        if (self.peek() != .backslash) {
            if (has_leading or ns_relative) {
                var parts = std.ArrayListUnmanaged(u32).empty;
                defer parts.deinit(self.allocator);
                try parts.append(self.allocator, first_tok);
                const extra = try self.addExtraList(parts.items);
                const marker: u32 = if (ns_relative) 2 else 1;
                return self.addNode(.{ .tag = .qualified_name, .main_token = first_tok, .data = .{ .lhs = extra, .rhs = marker } });
            }
            return self.addNode(.{ .tag = .identifier, .main_token = first_tok, .data = .{} });
        }

        var parts = std.ArrayListUnmanaged(u32).empty;
        defer parts.deinit(self.allocator);
        try parts.append(self.allocator, first_tok);
        while (self.peek() == .backslash) {
            _ = self.advance();
            // PHP allows reserved words as namespace segments
            const seg = if (self.peek() == .identifier or isSemiReserved(self.peek()))
                self.advance()
            else
                try self.expect(.identifier);
            try parts.append(self.allocator, seg);
        }
        const extra = try self.addExtraList(parts.items);
        const marker: u32 = if (ns_relative) 2 else if (has_leading) 1 else 0;
        return self.addNode(.{ .tag = .qualified_name, .main_token = first_tok, .data = .{ .lhs = extra, .rhs = marker } });
    }

    fn isTypeName(self: *Parser) bool {
        const tag = self.peek();
        return tag == .identifier or tag == .kw_array or tag == .kw_callable or
            tag == .kw_self or tag == .kw_static or tag == .kw_null or
            tag == .kw_true or tag == .kw_false or tag == .backslash or
            tag == .kw_parent or (tag == .kw_namespace and self.peekAt(1) == .backslash);
    }

    fn skipTypeName(self: *Parser) void {
        // a namespace-relative name, `namespace\Foo`
        if (self.peek() == .kw_namespace and self.peekAt(1) == .backslash) {
            _ = self.advance();
            _ = self.advance();
            if (self.peek() == .identifier or isSemiReserved(self.peek())) _ = self.advance();
            while (self.peek() == .backslash) {
                _ = self.advance();
                if (self.peek() == .identifier or isSemiReserved(self.peek())) _ = self.advance();
            }
            return;
        }
        if (self.peek() == .backslash) _ = self.advance();
        if (self.isTypeName()) _ = self.advance();
        while (self.peek() == .backslash) {
            _ = self.advance();
            if (self.peek() == .identifier or isSemiReserved(self.peek())) _ = self.advance();
        }
    }

    // consumes a full PHP type expression: simple, nullable, union, intersection, DNF
    // e.g. int, ?string, int|string, Foo&Bar, (Foo&Bar)|null, ?\Throwable
    fn skipTypeHint(self: *Parser) void {
        if (self.peek() == .question) {
            _ = self.advance();
            self.skipTypeName();
            return;
        }

        if (self.peek() == .l_paren) {
            _ = self.advance();
            while (self.isTypeName()) {
                self.skipTypeName();
                if (self.peek() == .amp) {
                    _ = self.advance();
                } else break;
            }
            if (self.peek() == .r_paren) _ = self.advance();
            if (self.peek() == .pipe) {
                _ = self.advance();
                self.skipTypeHint();
            }
            return;
        }

        if (!self.isTypeName()) return;
        self.skipTypeName();

        if (self.peek() == .pipe) {
            while (self.peek() == .pipe) {
                _ = self.advance();
                if (self.peek() == .l_paren) {
                    _ = self.advance();
                    while (self.isTypeName()) {
                        self.skipTypeName();
                        if (self.peek() == .amp) {
                            _ = self.advance();
                        } else break;
                    }
                    if (self.peek() == .r_paren) _ = self.advance();
                } else if (self.isTypeName()) {
                    self.skipTypeName();
                }
            }
        } else if (self.peek() == .amp) {
            if (self.peekAt(1) == .variable or self.peekAt(1) == .ellipsis) return;
            while (self.peek() == .amp) {
                _ = self.advance();
                self.skipTypeName();
            }
        }
    }

    fn collectTypeHint(self: *Parser) [2]u32 {
        if (!self.isTypeName() and self.peek() != .question and self.peek() != .l_paren) return .{ 0, 0 };
        const start = self.pos;
        self.skipTypeHint();
        return .{ start, self.pos };
    }

    fn parseAttributes(self: *Parser) Error!void {
        if (self.peek() != .hash_bracket) return;
        const start = self.pos;
        var items = std.ArrayListUnmanaged(u32).empty;
        defer items.deinit(self.allocator);
        while (self.peek() == .hash_bracket) {
            _ = self.advance();
            while (true) {
                const name_start = self.pos;
                if (self.peek() == .backslash) _ = self.advance();
                if (self.peek() != .identifier and !self.isNamedArgKeyword()) _ = try self.expect(.identifier);
                _ = self.advance();
                while (self.peek() == .backslash) {
                    _ = self.advance();
                    if (self.peek() != .identifier and !self.isNamedArgKeyword()) _ = try self.expect(.identifier);
                    _ = self.advance();
                }
                const name_end = self.pos;
                var args: u32 = AttrRange.no_args;
                if (self.peek() == .l_paren) {
                    _ = self.advance();
                    var list = std.ArrayListUnmanaged(u32).empty;
                    defer list.deinit(self.allocator);
                    while (self.peek() != .r_paren) {
                        try list.append(self.allocator, try self.parseCallArg());
                        if (self.peek() != .comma) break;
                        _ = self.advance();
                    }
                    _ = try self.expect(.r_paren);
                    args = try self.addExtraList(list.items);
                }
                try items.appendSlice(self.allocator, &.{ name_start, name_end, args });
                if (self.peek() != .comma) break;
                _ = self.advance();
                if (self.peek() == .r_bracket) break;
            }
            _ = try self.expect(.r_bracket);
        }
        try self.attr_ranges.append(self.allocator, .{
            .target_tok = self.pos,
            .start = start,
            .end = self.pos,
            .items = try self.addExtraList(items.items),
        });
    }

    fn parseParam(self: *Parser) Error!u32 {
        try self.parseAttributes();
        // constructor property promotion: visibility keyword before param
        // read-side promotion: 0 = none, 1 = public, 2 = protected, 3 = private
        // set-side promotion: 0 = no asymmetric override (use read), 1/2/3 same encoding
        var promotion: u32 = 0;
        var set_promotion: u32 = 0;
        var param_readonly = false;
        var param_final = false;
        // handle readonly, final (php 8.5), and visibility keywords (each
        // visibility may have a (set) qualifier)
        var loop_iters: u32 = 0;
        while (loop_iters < 5) : (loop_iters += 1) {
            const tag = self.peek();
            if (tag == .kw_readonly) {
                param_readonly = true;
                _ = self.advance();
                continue;
            }
            if (tag == .kw_final) {
                param_final = true;
                _ = self.advance();
                continue;
            }
            if (tag == .kw_public or tag == .kw_protected or tag == .kw_private) {
                const vis_val: u32 = if (tag == .kw_public) 1 else if (tag == .kw_protected) 2 else 3;
                _ = self.advance();
                if (self.peek() == .l_paren and self.peekAt(1) == .identifier and std.mem.eql(u8, self.lexemeAt(1), "set") and self.peekAt(2) == .r_paren) {
                    _ = self.advance();
                    _ = self.advance();
                    _ = self.advance();
                    if (set_promotion != 0) {
                        try self.addError(.unexpected_token);
                        return error.ParseError;
                    }
                    set_promotion = vis_val;
                } else {
                    if (promotion != 0) {
                        try self.addError(.unexpected_token);
                        return error.ParseError;
                    }
                    promotion = vis_val;
                }
                continue;
            }
            break;
        }
        const type_range = self.collectTypeHint();
        // final alone promotes a public property, as php 8.5 does
        if (param_final and promotion == 0) promotion = 1;

        // PHP 8.4 asymmetric promoted-property validation.
        if (set_promotion > 0) {
            if (promotion == 0) promotion = 1;

            if (set_promotion < promotion or type_range[0] == type_range[1]) {
                try self.addError(.unexpected_token);
                return error.ParseError;
            }
        }
        const is_ref = self.peek() == .amp;
        if (is_ref) _ = self.advance();
        const is_variadic = self.peek() == .ellipsis;
        if (is_variadic) _ = self.advance();

        const tok = try self.expect(.variable);
        var default: u32 = 0;
        if (self.peek() == .equal) {
            _ = self.advance();
            default = try self.parseExpression();
        }
        // rhs encoding: bit 0 = variadic, bit 1 = by-reference, bits 2-3 = read promotion,
        // bit 4 = readonly, bits 5-6 = set promotion (0 = same as read), bit 7 = final,
        // bits 8+ = type_extra
        var flags: u32 = 0;
        if (is_variadic) flags |= 1;
        if (is_ref) flags |= 2;
        flags |= (promotion << 2);
        if (param_readonly) flags |= 16;
        flags |= (set_promotion << 5);
        if (param_final) flags |= 1 << 7;
        if (type_range[0] != type_range[1]) {
            const type_extra = try self.addExtra(&type_range);
            flags |= ((type_extra + 1) << 8);
        }
        return self.addNode(.{ .tag = .variable, .main_token = tok, .data = .{ .lhs = default, .rhs = flags } });
    }

    // expressions

    fn parseExpression(self: *Parser) Error!u32 {
        return self.parseExprPrec(0);
    }

    fn parseExprPrec(self: *Parser, min_prec: u8) Error!u32 {
        var left = try self.parsePrefixExpr();

        while (true) {
            switch (self.peek()) {
                .l_paren => {
                    left = try self.parseCallExpr(left);
                    continue;
                },
                .l_bracket => {
                    left = try self.parseIndexExpr(left);
                    continue;
                },
                .arrow => {
                    left = try self.parsePropExpr(left, false);
                    continue;
                },
                .question_arrow => {
                    left = try self.parsePropExpr(left, true);
                    continue;
                },
                .colon_colon => {
                    left = try self.parseStaticAccess(left);
                    continue;
                },
                .plus_plus, .minus_minus => {
                    if (21 > min_prec and isIncDecOperand(self.nodes.items[left].tag)) {
                        const tok = self.advance();
                        left = try self.addNode(.{ .tag = .postfix_op, .main_token = tok, .data = .{ .lhs = left } });
                        continue;
                    }
                    break;
                },
                else => {},
            }

            if (self.peek() == .question and infixPrec(.question) > min_prec) {
                left = try self.parseTernary(left);
                continue;
            }

            const prec = infixPrec(self.peek());
            if (prec == 0 or prec <= min_prec) {
                // php allows assignment as rhs of any operator: false === $x = expr
                if (prec == 4 and isAssignTarget(self.nodes.items[left].tag)) {
                    // fall through to parse the assignment
                } else break;
            }

            const op_tok = self.advance();
            const op_tag = self.tokens[op_tok].tag;
            const right_min = if (isRightAssoc(op_tag)) prec - 1 else prec;
            const is_ref_assign = op_tag == .equal and self.peek() == .amp;
            var ref_amp_tok: u32 = 0;
            if (is_ref_assign) {
                ref_amp_tok = self.advance();
            }
            const right_inner = try self.parseExprPrec(right_min);
            const right = if (is_ref_assign)
                try self.addNode(.{ .tag = .ref_target, .main_token = ref_amp_tok, .data = .{ .lhs = right_inner } })
            else
                right_inner;
            const node_tag = infixNodeTag(op_tag);

            left = try self.addNode(.{ .tag = node_tag, .main_token = op_tok, .data = .{ .lhs = left, .rhs = right } });
        }

        return left;
    }

    fn parsePrefixExpr(self: *Parser) Error!u32 {
        switch (self.peek()) {
            .bang, .at => {
                const tok = self.advance();
                // ! and @ bind less tightly than instanceof (prec 17)
                const operand = try self.parseExprPrec(16);
                return self.addNode(.{ .tag = .prefix_op, .main_token = tok, .data = .{ .lhs = operand } });
            },
            .plus, .minus, .tilde => {
                const tok = self.advance();
                const operand = try self.parseExprPrec(18);
                return self.addNode(.{ .tag = .prefix_op, .main_token = tok, .data = .{ .lhs = operand } });
            },
            .amp => {
                // reference expression (&$var) - consume & and treat as value
                // zphp has limited reference semantics so &$x degrades to $x
                _ = self.advance();
                return self.parseExprPrec(18);
            },
            .plus_plus, .minus_minus => {
                const tok = self.advance();
                const operand_token = self.pos;
                const operand = try self.parseExprPrec(21);
                if (!isIncDecOperand(self.nodes.items[operand].tag)) try self.addErrorAt(operand_token, .unexpected_token);
                return self.addNode(.{ .tag = .prefix_op, .main_token = tok, .data = .{ .lhs = operand } });
            },
            .kw_clone => {
                const tok = self.advance();
                // php 8.5's clone($object, $withProperties); a single argument
                // is the plain clone of it
                if (self.peek() == .l_paren) {
                    _ = self.advance();
                    const object = try self.parseExpression();
                    var with: u32 = 0;
                    if (self.peek() == .comma) {
                        _ = self.advance();
                        if (self.peek() != .r_paren) {
                            with = try self.parseExpression();
                            if (self.peek() == .comma) _ = self.advance();
                        }
                    }
                    _ = try self.expect(.r_paren);
                    if (with != 0) return self.addNode(.{ .tag = .clone_with, .main_token = tok, .data = .{ .lhs = object, .rhs = with } });
                    const grouped = try self.addNode(.{ .tag = .grouped_expr, .main_token = tok, .data = .{ .lhs = object } });
                    return self.addNode(.{ .tag = .prefix_op, .main_token = tok, .data = .{ .lhs = grouped } });
                }
                const operand = try self.parseExprPrec(18);
                return self.addNode(.{ .tag = .prefix_op, .main_token = tok, .data = .{ .lhs = operand } });
            },
            .kw_throw => {
                const tok = self.advance();
                const operand = try self.parseExprPrec(1);
                return self.addNode(.{ .tag = .throw_expr, .main_token = tok, .data = .{ .lhs = operand } });
            },
            .kw_print => {
                const tok = self.advance();
                const operand = try self.parseExprPrec(2);
                return self.addNode(.{ .tag = .print_expr, .main_token = tok, .data = .{ .lhs = operand } });
            },
            .kw_new => return self.parseNewExpr(),
            .kw_yield => return self.parseYieldExpr(),
            .kw_require, .kw_require_once, .kw_include, .kw_include_once => {
                const tok = self.advance();
                const path_expr = try self.parseExprPrec(1);
                return self.addNode(.{ .tag = .require_expr, .main_token = tok, .data = .{ .lhs = path_expr } });
            },
            else => return self.parsePrimaryExpr(),
        }
    }

    fn parsePrimaryExpr(self: *Parser) Error!u32 {
        return switch (self.peek()) {
            .integer => self.addLiteral(.integer_literal),
            .float => self.addLiteral(.float_literal),
            .string => blk: {
                try self.checkUnicodeEscapes(self.pos);
                break :blk self.addLiteral(.string_literal);
            },
            .heredoc, .nowdoc => blk: {
                try self.checkHeredocIndentation(self.pos);
                break :blk self.addLiteral(.string_literal);
            },
            .kw_true => self.addLiteral(.true_literal),
            .kw_false => self.addLiteral(.false_literal),
            .kw_null => self.addLiteral(.null_literal),
            .variable => self.addLiteral(.variable),
            .dollar => self.parseVariableVariable(),
            .identifier => if (self.peekAt(1) == .backslash) self.parseQualifiedName() else self.addLiteral(.identifier),
            // php's grammar takes `readonly` followed by arguments as a call
            .kw_readonly => if (self.peekAt(1) == .l_paren) self.addLiteral(.identifier) else blk: {
                try self.addError(.unexpected_token);
                break :blk error.ParseError;
            },
            .backslash => blk: {
                // PHP treats `\true`, `\false`, `\null` as the literal values
                // regardless of namespace (they're not namespaceable)
                if (self.peekAt(1) == .kw_true) {
                    _ = self.advance();
                    break :blk self.addLiteral(.true_literal);
                }
                if (self.peekAt(1) == .kw_false) {
                    _ = self.advance();
                    break :blk self.addLiteral(.false_literal);
                }
                if (self.peekAt(1) == .kw_null) {
                    _ = self.advance();
                    break :blk self.addLiteral(.null_literal);
                }
                break :blk self.parseQualifiedName();
            },
            .kw_namespace => if (self.peekAt(1) == .backslash) self.parseQualifiedName() else blk: {
                try self.addError(.expected_expression);
                break :blk error.ParseError;
            },
            .kw_isset, .kw_empty, .kw_unset, .kw_eval => self.addLiteral(.identifier),
            // exit / die are language constructs that work with OR without
            // parens (`exit;`, `exit(0);`, `die("msg");`). emit an identifier
            // node first; if the next token isn't `(`, wrap in a synthetic
            // 0-arg call so the runtime dispatches to native exit/die rather
            // than trying to resolve `exit` as a bare constant
            .kw_exit, .kw_die => blk: {
                const ident = try self.addLiteral(.identifier);
                if (self.peek() == .l_paren) break :blk ident;
                const extra = try self.addExtra(&[_]u32{0});
                const main_tok = self.nodes.items[ident].main_token;
                break :blk self.addNode(.{ .tag = .call, .main_token = main_tok, .data = .{ .lhs = ident, .rhs = extra } });
            },
            .kw_list => blk: {
                const bare_ok = self.bare_list_at == self.pos;
                const list = try self.parseListDestructure();
                if (!bare_ok and self.peek() != .equal) {
                    try self.addError(expectedError(.equal));
                    return error.ParseError;
                }
                break :blk list;
            },
            .kw_match => if (self.isMatchExpr()) self.parseMatchExpr() else self.addLiteral(.identifier),
            .kw_function => self.parseClosureExpr(),
            .kw_fn => self.parseArrowFunc(false),
            .hash_bracket => {
                try self.parseAttributes();
                return self.parsePrimaryExpr();
            },
            .l_paren => if (self.isCastExpr()) self.parseCastExpr() else self.parseGroupedExpr(),
            .l_bracket => self.parseArrayLiteral(),
            .kw_array => self.parseArrayKw(),
            .kw_static => if (self.peekAt(1) == .kw_function) self.parseClosureExpr() else if (self.peekAt(1) == .kw_fn) self.parseStaticArrowFunc() else self.addLiteral(.identifier),
            .kw_self, .kw_parent => self.addLiteral(.identifier),
            else => {
                try self.addError(.expected_expression);
                return error.ParseError;
            },
        };
    }

    fn parseVariableVariable(self: *Parser) Error!u32 {
        const dollar_tok = self.advance(); // $
        if (self.peek() == .l_brace) {
            _ = self.advance(); // {
            const inner = try self.parseExpression();
            _ = try self.expect(.r_brace);
            return self.addNode(.{ .tag = .variable_variable, .main_token = dollar_tok, .data = .{ .lhs = inner } });
        }
        const inner = try self.parsePrimaryExpr();
        return self.addNode(.{ .tag = .variable_variable, .main_token = dollar_tok, .data = .{ .lhs = inner } });
    }

    fn isCastExpr(self: *const Parser) bool {
        if (self.peekAt(2) != .r_paren) return false;
        const next = self.peekAt(1);
        if (next == .kw_array or next == .kw_unset) return true;
        if (next != .identifier) return false;
        // cast names ignore case. real and unset are recognized to report
        // their removal, void to reject it outside a statement
        const lex = self.lexemeAt(1);
        for ([_][]const u8{ "int", "integer", "string", "binary", "bool", "boolean", "float", "double", "object", "void", "real", "unset" }) |name| {
            if (std.ascii.eqlIgnoreCase(lex, name)) return true;
        }
        return false;
    }

    fn parseCastExpr(self: *Parser) Error!u32 {
        const paren_tok = self.advance(); // (
        const type_tok = self.advance(); // type name
        _ = self.advance(); // )
        const type_name = self.tokens[type_tok].lexeme(self.source);
        if (std.ascii.eqlIgnoreCase(type_name, "real")) {
            try self.addErrorAt(type_tok, .real_cast_removed);
            return error.ParseError;
        }
        if (std.ascii.eqlIgnoreCase(type_name, "void")) {
            try self.addErrorAt(paren_tok, .void_cast_misplaced);
            return error.ParseError;
        }
        const operand = try self.parseExprPrec(18);
        return self.addNode(.{ .tag = .cast_expr, .main_token = type_tok, .data = .{ .lhs = operand } });
    }

    fn addLiteral(self: *Parser, tag: NodeTag) Error!u32 {
        const tok = self.advance();
        return self.addNode(.{ .tag = tag, .main_token = tok, .data = .{} });
    }

    fn parseGroupedExpr(self: *Parser) Error!u32 {
        _ = self.advance(); // (
        const inner = try self.parseExpression();
        _ = try self.expect(.r_paren);
        return self.addNode(.{ .tag = .grouped_expr, .main_token = 0, .data = .{ .lhs = inner } });
    }

    fn isNamedArgKeyword(self: *const Parser) bool {
        return switch (self.peek()) {
            .kw_class,
            .kw_match,
            .kw_array,
            .kw_list,
            .kw_static,
            .kw_self,
            .kw_parent,
            .kw_true,
            .kw_false,
            .kw_null,
            .kw_fn,
            .kw_function,
            .kw_return,
            .kw_if,
            .kw_else,
            .kw_for,
            .kw_foreach,
            .kw_while,
            .kw_do,
            .kw_switch,
            .kw_case,
            .kw_default,
            .kw_break,
            .kw_continue,
            .kw_new,
            .kw_echo,
            .kw_throw,
            .kw_try,
            .kw_catch,
            .kw_finally,
            .kw_interface,
            .kw_trait,
            .kw_enum,
            .kw_abstract,
            .kw_final,
            .kw_readonly,
            .kw_global,
            .kw_const,
            .kw_public,
            .kw_private,
            .kw_protected,
            .kw_extends,
            .kw_implements,
            .kw_namespace,
            .kw_use,
            .kw_require,
            .kw_include,
            .kw_isset,
            .kw_empty,
            .kw_unset,
            .kw_eval,
            .kw_exit,
            .kw_die,
            => true,
            else => false,
        };
    }

    fn parseListDestructure(self: *Parser) Error!u32 {
        const list_tok = self.advance(); // list
        _ = try self.expect(.l_paren);
        var targets = std.ArrayListUnmanaged(u32).empty;
        defer targets.deinit(self.allocator);
        while (self.peek() != .r_paren) {
            if (self.peek() == .comma) {
                try targets.append(self.allocator, 0);
            } else {
                var ref_amp_tok: u32 = 0;
                var is_ref = false;
                if (self.peek() == .amp) {
                    ref_amp_tok = self.advance();
                    is_ref = true;
                }
                const inner = if (self.peek() == .kw_list) try self.parseListDestructure() else try self.parseExpression();
                // list('key' => $var) form: the parsed expression was actually
                // the key. wrap the real target in an array_element node so the
                // compiler can look up by key
                if (self.peek() == .fat_arrow) {
                    _ = self.advance();
                    var ref2_tok: u32 = 0;
                    var is_ref2 = false;
                    if (self.peek() == .amp) {
                        ref2_tok = self.advance();
                        is_ref2 = true;
                    }
                    const target_inner = if (self.peek() == .kw_list) try self.parseListDestructure() else try self.parseExpression();
                    const real_target = if (is_ref2)
                        try self.addNode(.{ .tag = .ref_target, .main_token = ref2_tok, .data = .{ .lhs = target_inner } })
                    else
                        target_inner;
                    const elem = try self.addNode(.{ .tag = .array_element, .main_token = 0, .data = .{ .lhs = real_target, .rhs = inner } });
                    try targets.append(self.allocator, elem);
                } else {
                    const target_node = if (is_ref)
                        try self.addNode(.{ .tag = .ref_target, .main_token = ref_amp_tok, .data = .{ .lhs = inner } })
                    else
                        inner;
                    try targets.append(self.allocator, target_node);
                }
            }
            if (self.peek() == .comma) {
                _ = self.advance();
            } else break;
        }
        _ = try self.expect(.r_paren);
        const extra = try self.addExtraList(targets.items);
        return self.addNode(.{ .tag = .list_destructure, .main_token = list_tok, .data = .{ .lhs = extra } });
    }

    fn parseArrayLiteral(self: *Parser) Error!u32 {
        const bracket_tok = self.advance(); // [
        return self.parseArrayElements(bracket_tok, .r_bracket);
    }

    fn parseArrayKw(self: *Parser) Error!u32 {
        const arr_tok = self.advance(); // array
        _ = try self.expect(.l_paren);
        return self.parseArrayElements(arr_tok, .r_paren);
    }

    fn parseArrayElements(self: *Parser, start_tok: u32, end: Tag) Error!u32 {
        var elements = std.ArrayListUnmanaged(u32).empty;
        defer elements.deinit(self.allocator);

        if (self.peek() != end) {
            if (self.peek() == .comma) {
                try elements.append(self.allocator, 0);
            } else {
                try elements.append(self.allocator, try self.parseArrayElement());
            }
            while (self.peek() == .comma) {
                _ = self.advance();
                if (self.peek() == end) break;
                if (self.peek() == .comma) {
                    try elements.append(self.allocator, 0);
                } else {
                    try elements.append(self.allocator, try self.parseArrayElement());
                }
            }
        }
        _ = try self.expectTag(end);

        const extra = try self.addExtraList(elements.items);
        return self.addNode(.{ .tag = .array_literal, .main_token = start_tok, .data = .{ .lhs = extra } });
    }

    fn parseArrayElement(self: *Parser) Error!u32 {
        if (self.peek() == .ellipsis) {
            _ = self.advance();
            const expr = try self.parseExpression();
            return self.addNode(.{ .tag = .array_spread, .main_token = 0, .data = .{ .lhs = expr } });
        }
        // detect leading `&` for ref destructuring (e.g. `[, &$b] = $arr`)
        var ref_tok: u32 = 0;
        var is_ref = false;
        if (self.peek() == .amp) {
            ref_tok = self.advance();
            is_ref = true;
        }
        self.bare_list_at = self.pos;
        const expr0 = try self.parseExpression();
        const expr = if (is_ref)
            try self.addNode(.{ .tag = .ref_target, .main_token = ref_tok, .data = .{ .lhs = expr0 } })
        else
            expr0;
        if (self.peek() == .fat_arrow) {
            _ = self.advance();
            // value side may also be `&$b` (e.g. `['k' => &$v] = $arr`)
            var vref: u32 = 0;
            var v_is_ref = false;
            if (self.peek() == .amp) {
                vref = self.advance();
                v_is_ref = true;
            }
            self.bare_list_at = self.pos;
            const value0 = try self.parseExpression();
            const value = if (v_is_ref)
                try self.addNode(.{ .tag = .ref_target, .main_token = vref, .data = .{ .lhs = value0 } })
            else
                value0;
            return self.addNode(.{ .tag = .array_element, .main_token = 0, .data = .{ .lhs = value, .rhs = expr } });
        }
        return self.addNode(.{ .tag = .array_element, .main_token = 0, .data = .{ .lhs = expr } });
    }

    // postfix expressions

    fn parseCallExpr(self: *Parser, callee: u32) Error!u32 {
        const paren_tok = self.advance(); // (

        if (self.peek() == .ellipsis and self.peekAt(1) == .r_paren) {
            _ = self.advance(); // ...
            _ = self.advance(); // )
            return self.addNode(.{ .tag = .callable_ref, .main_token = paren_tok, .data = .{ .lhs = callee } });
        }

        var args = std.ArrayListUnmanaged(u32).empty;
        defer args.deinit(self.allocator);

        if (self.peek() != .r_paren) {
            try args.append(self.allocator, try self.parseCallArg());
            while (self.peek() == .comma) {
                _ = self.advance();
                if (self.peek() == .r_paren) break;
                try args.append(self.allocator, try self.parseCallArg());
            }
        }
        _ = try self.expect(.r_paren);

        const extra = try self.addExtraList(args.items);
        return self.addNode(.{ .tag = .call, .main_token = paren_tok, .data = .{ .lhs = callee, .rhs = extra } });
    }

    fn parseCallArg(self: *Parser) Error!u32 {
        if (self.peek() == .ellipsis) {
            _ = self.advance();
            const expr = try self.parseExpression();
            return self.addNode(.{ .tag = .splat_expr, .main_token = 0, .data = .{ .lhs = expr } });
        }
        // named argument: identifier (or keyword used as name) followed by colon
        if (self.peekAt(1) == .colon and (self.peek() == .identifier or self.isNamedArgKeyword())) {
            const name_tok = self.advance();
            _ = self.advance(); // colon
            const expr = try self.parseExpression();
            return self.addNode(.{ .tag = .named_arg, .main_token = name_tok, .data = .{ .lhs = expr } });
        }
        return self.parseExpression();
    }

    fn parseIndexExpr(self: *Parser, array: u32) Error!u32 {
        const bracket_tok = self.advance(); // [
        if (self.peek() == .r_bracket) {
            _ = self.advance();
            return self.addNode(.{ .tag = .array_push_target, .main_token = bracket_tok, .data = .{ .lhs = array } });
        }
        const index = try self.parseExpression();
        _ = try self.expect(.r_bracket);
        return self.addNode(.{ .tag = .array_access, .main_token = bracket_tok, .data = .{ .lhs = array, .rhs = index } });
    }

    fn parsePropExpr(self: *Parser, object: u32, nullsafe: bool) Error!u32 {
        _ = self.advance(); // -> or ?->

        if (self.peek() == .l_brace) {
            _ = self.advance();
            const expr = try self.parseExpression();
            _ = try self.expect(.r_brace);

            const tag: Ast.Node.Tag = if (nullsafe) .nullsafe_property_access else .property_access;
            return self.addNode(.{ .tag = tag, .main_token = 0, .data = .{ .lhs = object, .rhs = expr } });
        }

        // `->$$name` and `->${expr}`: the member named by a variable variable
        if (self.peek() == .dollar) {
            const expr = try self.parseVariableVariable();
            const tag: Ast.Node.Tag = if (nullsafe) .nullsafe_property_access else .property_access;
            return self.addNode(.{ .tag = tag, .main_token = 0, .data = .{ .lhs = object, .rhs = expr } });
        }

        if (self.peek() != .identifier and self.peek() != .variable and !isSemiReserved(self.peek())) {
            try self.addError(.expected_identifier);
            return error.ParseError;
        }
        const name_tok = self.advance();

        if (self.peek() == .l_paren) {
            _ = self.advance(); // (

            if (self.peek() == .ellipsis and self.peekAt(1) == .r_paren) {
                _ = self.advance(); // ...
                _ = self.advance(); // )
                const method_node = try self.addNode(.{ .tag = .method_call, .main_token = name_tok, .data = .{ .lhs = object, .rhs = 0 } });
                return self.addNode(.{ .tag = .callable_ref, .main_token = name_tok, .data = .{ .lhs = method_node } });
            }

            var args = std.ArrayListUnmanaged(u32).empty;
            defer args.deinit(self.allocator);

            if (self.peek() != .r_paren) {
                try args.append(self.allocator, try self.parseCallArg());
                while (self.peek() == .comma) {
                    _ = self.advance();
                    if (self.peek() == .r_paren) break;
                    try args.append(self.allocator, try self.parseCallArg());
                }
            }
            _ = try self.expect(.r_paren);

            const extra = try self.addExtraList(args.items);
            const tag: Ast.Node.Tag = if (nullsafe) .nullsafe_method_call else .method_call;
            return self.addNode(.{ .tag = tag, .main_token = name_tok, .data = .{ .lhs = object, .rhs = extra } });
        }

        const prop = try self.addNode(.{ .tag = .identifier, .main_token = name_tok, .data = .{} });
        const tag: Ast.Node.Tag = if (nullsafe) .nullsafe_property_access else .property_access;
        return self.addNode(.{ .tag = tag, .main_token = name_tok, .data = .{ .lhs = object, .rhs = prop } });
    }

    fn parseStaticAccess(self: *Parser, class_node: u32) Error!u32 {
        _ = self.advance(); // ::

        if (self.peek() == .variable) {
            const var_tok = self.advance();
            return self.addNode(.{ .tag = .static_prop_access, .main_token = var_tok, .data = .{ .lhs = class_node } });
        }

        // dynamic static property: Class::$$var and Class::${expr} - the
        // property name comes from an inner expression. produces the same
        // node shape as Class::{expr} (main_token 0, rhs = name expression)
        if (self.peek() == .dollar) {
            _ = self.advance(); // $
            const name_expr = if (self.peek() == .l_brace) blk: {
                _ = self.advance(); // {
                const e = try self.parseExpression();
                _ = try self.expect(.r_brace);
                break :blk e;
            } else try self.parsePrimaryExpr();
            if (self.peek() == .l_paren) {
                _ = self.advance(); // (
                var args = std.ArrayListUnmanaged(u32).empty;
                defer args.deinit(self.allocator);
                try args.append(self.allocator, name_expr);
                if (self.peek() != .r_paren) {
                    try args.append(self.allocator, try self.parseCallArg());
                    while (self.peek() == .comma) {
                        _ = self.advance();
                        if (self.peek() == .r_paren) break;
                        try args.append(self.allocator, try self.parseCallArg());
                    }
                }
                _ = try self.expect(.r_paren);
                const extra = try self.addExtraList(args.items);
                return self.addNode(.{ .tag = .dynamic_static_call, .main_token = 0, .data = .{ .lhs = class_node, .rhs = extra } });
            }
            return self.addNode(.{ .tag = .static_prop_access, .main_token = 0, .data = .{ .lhs = class_node, .rhs = name_expr } });
        }

        // ::class is a special class name resolution constant
        if (self.peek() == .kw_class) {
            const class_tok = self.advance();
            return self.addNode(.{ .tag = .static_prop_access, .main_token = class_tok, .data = .{ .lhs = class_node } });
        }

        if (self.peek() == .l_brace) {
            _ = self.advance(); // {
            const method_expr = try self.parseExpression();
            _ = try self.expect(.r_brace);
            if (self.peek() == .l_paren) {
                _ = self.advance(); // (
                var args = std.ArrayListUnmanaged(u32).empty;
                defer args.deinit(self.allocator);
                try args.append(self.allocator, method_expr);
                if (self.peek() != .r_paren) {
                    try args.append(self.allocator, try self.parseCallArg());
                    while (self.peek() == .comma) {
                        _ = self.advance();
                        if (self.peek() == .r_paren) break;
                        try args.append(self.allocator, try self.parseCallArg());
                    }
                }
                _ = try self.expect(.r_paren);
                const extra = try self.addExtraList(args.items);
                return self.addNode(.{ .tag = .dynamic_static_call, .main_token = 0, .data = .{ .lhs = class_node, .rhs = extra } });
            }
            // dynamic class constant: Class::{expr} (no call)
            return self.addNode(.{ .tag = .dynamic_class_const, .main_token = 0, .data = .{ .lhs = class_node, .rhs = method_expr } });
        }

        const name_tok = if (self.peek() == .identifier or isSemiReserved(self.peek()))
            self.advance()
        else
            try self.expect(.identifier);

        if (self.peek() == .l_paren) {
            _ = self.advance();

            if (self.peek() == .ellipsis and self.peekAt(1) == .r_paren) {
                _ = self.advance(); // ...
                _ = self.advance(); // )
                const static_node = try self.addNode(.{ .tag = .static_call, .main_token = name_tok, .data = .{ .lhs = class_node, .rhs = 0 } });
                return self.addNode(.{ .tag = .callable_ref, .main_token = name_tok, .data = .{ .lhs = static_node } });
            }

            var args = std.ArrayListUnmanaged(u32).empty;
            defer args.deinit(self.allocator);

            if (self.peek() != .r_paren) {
                try args.append(self.allocator, try self.parseCallArg());
                while (self.peek() == .comma) {
                    _ = self.advance();
                    if (self.peek() == .r_paren) break;
                    try args.append(self.allocator, try self.parseCallArg());
                }
            }
            _ = try self.expect(.r_paren);

            const extra = try self.addExtraList(args.items);
            return self.addNode(.{ .tag = .static_call, .main_token = name_tok, .data = .{ .lhs = class_node, .rhs = extra } });
        }

        // class constant / enum case access
        return self.addNode(.{ .tag = .static_prop_access, .main_token = name_tok, .data = .{ .lhs = class_node } });
    }

    fn parseTernary(self: *Parser, cond: u32) Error!u32 {
        const q_tok = self.advance(); // ?
        if (self.peek() == .colon) {
            _ = self.advance();
            const else_expr = try self.parseExprPrec(5);
            const extra = try self.addExtra(&.{ 0, else_expr });
            return self.addNode(.{ .tag = .ternary, .main_token = q_tok, .data = .{ .lhs = cond, .rhs = extra } });
        }
        const then_expr = try self.parseExprPrec(0);
        _ = try self.expect(.colon);
        const else_expr = try self.parseExprPrec(5);
        const extra = try self.addExtra(&.{ then_expr, else_expr });
        return self.addNode(.{ .tag = .ternary, .main_token = q_tok, .data = .{ .lhs = cond, .rhs = extra } });
    }

    // precedence

    fn infixPrec(tag: Tag) u8 {
        return switch (tag) {
            .kw_or => 1,
            .kw_xor => 2,
            .kw_and => 3,
            .equal, .plus_equal, .minus_equal, .star_equal, .slash_equal, .percent_equal, .star_star_equal, .dot_equal, .amp_equal, .pipe_equal, .caret_equal, .lt_lt_equal, .gt_gt_equal, .question_question_equal => 4,
            .question => 5,
            .question_question => 6,
            .pipe_pipe => 7,
            .amp_amp => 8,
            .pipe => 9,
            .caret => 10,
            .amp => 11,
            .equal_equal, .bang_equal, .equal_equal_equal, .bang_equal_equal, .lt_gt => 12,
            .lt, .lt_equal, .gt, .gt_equal, .spaceship => 13,
            .pipe_gt => 14,
            .lt_lt, .gt_gt => 15,
            .plus, .minus, .dot => 16,
            .star, .slash, .percent => 17,
            .kw_instanceof => 18,
            .star_star => 20,
            else => 0,
        };
    }

    fn isAssignTarget(tag: NodeTag) bool {
        return switch (tag) {
            .variable, .variable_variable, .array_access, .property_access, .nullsafe_property_access, .static_prop_access => true,
            else => false,
        };
    }

    // php's grammar takes only a variable here; calls parse so the compiler
    // can report them as return values in write context
    fn isIncDecOperand(tag: NodeTag) bool {
        return isAssignTarget(tag) or switch (tag) {
            .call, .method_call, .static_call, .dynamic_static_call, .nullsafe_method_call => true,
            else => false,
        };
    }

    fn isRightAssoc(tag: Tag) bool {
        return switch (tag) {
            .equal, .plus_equal, .minus_equal, .star_equal, .slash_equal, .percent_equal, .star_star_equal, .dot_equal, .amp_equal, .pipe_equal, .caret_equal, .lt_lt_equal, .gt_gt_equal, .question_question_equal => true,
            .question_question => true,
            .star_star => true,
            else => false,
        };
    }

    fn infixNodeTag(tag: Tag) NodeTag {
        return switch (tag) {
            .amp_amp, .kw_and => .logical_and,
            .pipe_pipe, .kw_or => .logical_or,
            .question_question => .null_coalesce,
            .pipe_gt => .pipe_expr,
            .equal, .plus_equal, .minus_equal, .star_equal, .slash_equal, .percent_equal, .star_star_equal, .dot_equal, .amp_equal, .pipe_equal, .caret_equal, .lt_lt_equal, .gt_gt_equal, .question_question_equal => .assign,
            else => .binary_op,
        };
    }

    fn peek(self: *const Parser) Tag {
        if (self.pos >= self.tokens.len) return .eof;
        return self.tokens[self.pos].tag;
    }

    fn peekAt(self: *const Parser, offset: u32) Tag {
        const i = self.pos + offset;
        if (i >= self.tokens.len) return .eof;
        return self.tokens[i].tag;
    }

    // match(expr) { ... } is a match expression. match(args) is a function call
    fn isMatchExpr(self: *const Parser) bool {
        if (self.peekAt(1) != .l_paren) return false;
        var depth: u32 = 0;
        var i: u32 = 1;
        while (true) {
            const t = self.peekAt(i);
            if (t == .eof) return false;
            if (t == .l_paren) depth += 1;
            if (t == .r_paren) {
                depth -= 1;
                if (depth == 0) return self.peekAt(i + 1) == .l_brace;
            }
            i += 1;
        }
    }

    fn lexemeAt(self: *const Parser, offset: u32) []const u8 {
        const i = self.pos + offset;
        if (i >= self.tokens.len) return "";
        return self.tokens[i].lexeme(self.source);
    }

    fn advance(self: *Parser) u32 {
        const p = self.pos;
        if (self.pos < self.tokens.len) self.pos += 1;
        return p;
    }

    fn expect(self: *Parser, tag: Tag) Error!u32 {
        return self.expectTag(tag);
    }

    fn expectTag(self: *Parser, tag: Tag) Error!u32 {
        if (self.peek() == tag) return self.advance();
        // ?> acts as implicit semicolon in PHP
        if (tag == .semicolon and self.peek() == .close_tag) return self.advance();
        try self.addError(expectedError(tag));
        return error.ParseError;
    }

    fn isSemiReserved(tag: Token.Tag) bool {
        // php 7.0+ allows most keywords as method/constant names in classes
        return @intFromEnum(tag) >= @intFromEnum(Token.Tag.kw_abstract) and
            @intFromEnum(tag) <= @intFromEnum(Token.Tag.kw_yield);
    }

    fn expectFunctionName(self: *Parser) Error!u32 {
        if (self.peek() == .identifier or isSemiReserved(self.peek())) return self.advance();
        try self.addError(expectedError(.identifier));
        return error.ParseError;
    }

    fn addNode(self: *Parser, node: Ast.Node) Error!u32 {
        const idx: u32 = @intCast(self.nodes.items.len);
        try self.nodes.append(self.allocator, node);
        return idx;
    }

    fn addExtra(self: *Parser, data: []const u32) Error!u32 {
        const idx: u32 = @intCast(self.extra_data.items.len);
        try self.extra_data.appendSlice(self.allocator, data);
        return idx;
    }

    fn addExtraList(self: *Parser, items: []const u32) Error!u32 {
        const idx: u32 = @intCast(self.extra_data.items.len);
        try self.extra_data.append(self.allocator, @intCast(items.len));
        try self.extra_data.appendSlice(self.allocator, items);
        return idx;
    }

    fn addExtraListWithReturnType(self: *Parser, items: []const u32, ret_range: [2]u32) Error!u32 {
        const idx: u32 = @intCast(self.extra_data.items.len);
        try self.extra_data.append(self.allocator, @intCast(items.len));
        try self.extra_data.appendSlice(self.allocator, items);
        try self.extra_data.appendSlice(self.allocator, &ret_range);
        return idx;
    }

    fn tokenText(self: *const Parser, token: u32) []const u8 {
        return self.tokens[token].lexeme(self.source);
    }

    // php's compiler refuses what the grammar allowed: the first such error
    // is kept for the compiler to raise
    fn deferCompileError(self: *Parser, token: u32, comptime fmt: []const u8, args: anytype) void {
        if (self.compile_error != null) return;
        var note: Ast.CompileErrorNote = .{ .token = @min(token, @as(u32, @intCast(self.tokens.len - 1))) };
        note.len = if (std.fmt.bufPrint(&note.text, fmt, args)) |written| written.len else |_| note.text.len;
        self.compile_error = note;
    }

    // a compile error php's parser throws while it reads modifiers
    fn deferModifierError(self: *Parser, token: u32, comptime fmt: []const u8, args: anytype) void {
        if (self.compile_error != null) return;
        self.deferCompileError(token, fmt, args);
        self.compile_error.?.trace = false;
    }

    // zend_scan_escape_string's \u{...} rules for a double-quoted string:
    // hex digits between the braces, at least one, at most U+10FFFF. a \u
    // without a brace stays as written
    fn checkUnicodeEscapes(self: *Parser, token: u32) Error!void {
        const text = self.tokens[token].lexeme(self.source);
        if (text.len == 0 or text[0] != '"') return;
        var i: usize = 1;
        var newlines: u32 = 0;
        while (i + 1 < text.len) : (i += 1) {
            if (text[i] == '\n') newlines += 1;
            if (text[i] != '\\') continue;
            if (text[i + 1] != 'u' or i + 2 >= text.len or text[i + 2] != '{') {
                i += 1;
                continue;
            }
            var j = i + 3;
            while (j < text.len and std.ascii.isHex(text[j])) j += 1;
            if (j >= text.len or text[j] != '}' or j == i + 3) {
                try self.errors.append(self.allocator, .{ .token = token, .tag = .unicode_escape_invalid, .line_delta = newlines });
                return error.ParseError;
            }
            const digits = std.mem.trimStart(u8, text[i + 3 .. j], "0");
            const too_large = digits.len > 6 or (std.fmt.parseInt(u32, if (digits.len == 0) "0" else digits, 16) catch 0x110000) > 0x10FFFF;
            if (too_large) {
                try self.errors.append(self.allocator, .{ .token = token, .tag = .unicode_escape_too_large, .line_delta = newlines });
                return error.ParseError;
            }
            i = j;
        }
    }

    fn addError(self: *Parser, tag: Ast.Error.Tag) Error!void {
        try self.addErrorAt(self.pos, tag);
    }

    fn addErrorAt(self: *Parser, token: u32, tag: Ast.Error.Tag) Error!void {
        // advance() can step past the eof token; an error there is at eof
        const last: u32 = @intCast(self.tokens.len - 1);
        try self.errors.append(self.allocator, .{ .token = @min(token, last), .tag = tag });
    }

    // strip_multiline_string_indentation's checks: the closing marker's
    // indentation is all spaces or all tabs, and every body line starts with
    // at least that much of the same whitespace (a shorter line that is only
    // whitespace is fine)
    fn checkHeredocIndentation(self: *Parser, token: u32) Error!void {
        const tok = self.tokens[token];
        const lexeme = self.source[tok.start..tok.end];
        const first_nl = std.mem.indexOfScalar(u8, lexeme, '\n') orelse return;
        const body_start = first_nl + 1;
        var end = lexeme.len;
        while (end > body_start and (lexeme[end - 1] == '\n' or lexeme[end - 1] == '\r' or lexeme[end - 1] == ';')) end -= 1;
        while (end > body_start and (std.ascii.isAlphanumeric(lexeme[end - 1]) or lexeme[end - 1] == '_' or lexeme[end - 1] >= 0x80)) end -= 1;
        var closing_line_start = end;
        while (closing_line_start > body_start and lexeme[closing_line_start - 1] != '\n') closing_line_start -= 1;
        const indent = lexeme[closing_line_start..end];
        if (indent.len == 0) return;
        const has_space = std.mem.indexOfScalar(u8, indent, ' ') != null;
        const has_tab = std.mem.indexOfScalar(u8, indent, '\t') != null;
        // php reports a mixed closing marker on the line after the opener
        if (has_space and has_tab) return self.addHeredocError(token, .heredoc_mixed_indentation, 0, 1);
        const using_spaces = has_space;
        if (closing_line_start <= body_start) return;
        const body = lexeme[body_start .. closing_line_start - 1];
        var lines = std.mem.splitScalar(u8, body, '\n');
        var delta: u32 = 1;
        while (lines.next()) |line| : (delta += 1) {
            for (0..indent.len) |k| {
                if (k == line.len or line[k] == '\r') break;
                const c = line[k];
                if (c != ' ' and c != '\t') return self.addHeredocError(token, .heredoc_body_indentation, @intCast(indent.len), delta);
                if ((c == ' ') != using_spaces) return self.addHeredocError(token, .heredoc_mixed_indentation, 0, delta);
            }
        }
    }

    fn addHeredocError(self: *Parser, token: u32, tag: Ast.Error.Tag, detail: u32, line_delta: u32) Error!void {
        try self.errors.append(self.allocator, .{ .token = token, .tag = tag, .detail = detail, .line_delta = line_delta });
    }

    fn synchronize(self: *Parser) void {
        // always skip at least one token to guarantee forward progress
        if (self.peek() != .eof) _ = self.advance();
        while (self.peek() != .eof) {
            switch (self.peek()) {
                .semicolon => {
                    _ = self.advance();
                    return;
                },
                .r_brace => return,
                .kw_if, .kw_while, .kw_for, .kw_foreach, .kw_function, .kw_return, .kw_echo, .kw_class, .kw_try, .kw_throw => return,
                else => _ = self.advance(),
            }
        }
    }

    fn expectedError(tag: Tag) Ast.Error.Tag {
        return switch (tag) {
            .semicolon => .expected_semicolon,
            .r_paren => .expected_r_paren,
            .r_brace => .expected_r_brace,
            .r_bracket => .expected_r_bracket,
            .identifier => .expected_identifier,
            .variable => .expected_variable,
            .colon => .expected_colon,
            .l_paren => .expected_r_paren,
            else => .unexpected_token,
        };
    }
};
