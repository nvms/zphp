const std = @import("std");
const Ast = @import("ast.zig").Ast;
const Token = @import("token.zig").Token;
const Lexer = @import("lexer.zig").Lexer;

const Tag = Token.Tag;
const NodeTag = Ast.Node.Tag;
const Allocator = std.mem.Allocator;
const Error = Allocator.Error || error{ParseError};

pub fn parse(allocator: Allocator, source: []const u8) Allocator.Error!Ast {
    var tok_buf = std.ArrayListUnmanaged(Token){};
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
        .nodes = .{},
        .extra_data = .{},
        .errors = .{},
        .allocator = allocator,
    };
    errdefer {
        p.nodes.deinit(allocator);
        p.extra_data.deinit(allocator);
        p.errors.deinit(allocator);
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

    return .{
        .source = source,
        .tokens = tok_slice,
        .nodes = nodes_slice,
        .extra_data = extra_slice,
        .errors = errors_slice,
        .allocator = allocator,
    };
}

const Parser = struct {
    source: []const u8,
    tokens: []const Token,
    pos: u32,
    nodes: std.ArrayListUnmanaged(Ast.Node),
    extra_data: std.ArrayListUnmanaged(u32),
    errors: std.ArrayListUnmanaged(Ast.Error),
    allocator: Allocator,

    // ======================================================================
    // root
    // ======================================================================

    fn parseRoot(self: *Parser) Error!void {
        // reserve root at index 0
        _ = try self.addNode(.{ .tag = .root, .main_token = 0, .data = .{} });

        var stmts = std.ArrayListUnmanaged(u32){};
        defer stmts.deinit(self.allocator);

        while (self.peek() != .eof) {
            const node = self.parseTopLevel() catch |err| switch (err) {
                error.ParseError => {
                    self.synchronize();
                    continue;
                },
                error.OutOfMemory => return error.OutOfMemory,
            };
            try stmts.append(self.allocator, node);
        }

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

    // ======================================================================
    // statements
    // ======================================================================

    fn parseStatement(self: *Parser) Error!u32 {
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
            .kw_class, .kw_abstract => self.parseClassDecl(),
            .kw_interface => self.parseInterfaceDecl(),
            .kw_trait => self.parseTraitDecl(),
            .kw_enum => self.parseEnumDecl(),
            .kw_throw => self.parseThrowStmt(),
            .kw_try => self.parseTryCatch(),
            .kw_declare => self.skipDeclare(),
            .kw_global => self.parseGlobalStmt(),
            .kw_static => self.parseStaticVarStmt(),
            .kw_namespace => self.parseNamespaceDecl(),
            .kw_use => self.parseUseStmt(),
            .kw_require, .kw_require_once, .kw_include, .kw_include_once => self.parseRequireStmt(),
            .l_brace => self.parseBlock(),
            .semicolon => {
                _ = self.advance();
                return self.parseStatement();
            },
            else => self.parseExpressionStmt(),
        };
    }

    fn parseStatementOrBlock(self: *Parser) Error!u32 {
        if (self.peek() == .l_brace) return self.parseBlock();
        return self.parseStatement();
    }

    // declare(strict_types=1); - skip the entire directive
    fn skipDeclare(self: *Parser) Error!u32 {
        _ = self.advance(); // declare
        if (self.peek() == .l_paren) {
            _ = self.advance();
            while (self.peek() != .r_paren and self.peek() != .eof) {
                _ = self.advance();
            }
            if (self.peek() == .r_paren) _ = self.advance();
        }
        if (self.peek() == .semicolon) _ = self.advance();
        return self.parseStatement();
    }

    fn parseGlobalStmt(self: *Parser) Error!u32 {
        const tok = self.advance(); // global
        var vars = std.ArrayListUnmanaged(u32){};
        defer vars.deinit(self.allocator);
        try vars.append(self.allocator, try self.addNode(.{
            .tag = .variable,
            .main_token = try self.expect(.variable),
            .data = .{},
        }));
        while (self.peek() == .comma) {
            _ = self.advance();
            try vars.append(self.allocator, try self.addNode(.{
                .tag = .variable,
                .main_token = try self.expect(.variable),
                .data = .{},
            }));
        }
        _ = try self.expect(.semicolon);
        const extra = try self.addExtraList(vars.items);
        return self.addNode(.{ .tag = .global_stmt, .main_token = tok, .data = .{ .lhs = extra } });
    }

    fn parseStaticVarStmt(self: *Parser) Error!u32 {
        _ = self.advance(); // static
        const var_tok = try self.expect(.variable);
        var default: u32 = 0;
        if (self.peek() == .equal) {
            _ = self.advance();
            default = try self.parseExpression();
        }
        _ = try self.expect(.semicolon);
        return self.addNode(.{ .tag = .static_var, .main_token = var_tok, .data = .{ .lhs = default } });
    }

    fn parseNamespaceDecl(self: *Parser) Error!u32 {
        const tok = self.advance(); // namespace
        var parts = std.ArrayListUnmanaged(u32){};
        defer parts.deinit(self.allocator);

        // namespace App\Models\User;
        try parts.append(self.allocator, self.pos);
        _ = try self.expect(.identifier);
        while (self.peek() == .backslash) {
            _ = self.advance();
            try parts.append(self.allocator, self.pos);
            _ = try self.expect(.identifier);
        }
        _ = try self.expect(.semicolon);

        const extra = try self.addExtraList(parts.items);
        return self.addNode(.{ .tag = .namespace_decl, .main_token = tok, .data = .{ .lhs = extra } });
    }

    fn parseUseStmt(self: *Parser) Error!u32 {
        const tok = self.advance(); // use

        // use App\Models\User;
        // use App\Models\User as Alias;
        var parts = std.ArrayListUnmanaged(u32){};
        defer parts.deinit(self.allocator);

        try parts.append(self.allocator, self.pos);
        _ = try self.expect(.identifier);
        while (self.peek() == .backslash) {
            _ = self.advance();
            try parts.append(self.allocator, self.pos);
            _ = try self.expect(.identifier);
        }

        var alias: u32 = 0;
        if (self.peek() == .kw_as) {
            _ = self.advance();
            alias = self.pos;
            _ = try self.expect(.identifier);
        }
        _ = try self.expect(.semicolon);

        const extra = try self.addExtraList(parts.items);
        return self.addNode(.{ .tag = .use_stmt, .main_token = tok, .data = .{ .lhs = extra, .rhs = alias } });
    }

    fn parseRequireStmt(self: *Parser) Error!u32 {
        const tok = self.advance(); // require/require_once/include/include_once
        const path_expr = try self.parseExpression();
        _ = try self.expect(.semicolon);
        const req = try self.addNode(.{ .tag = .require_expr, .main_token = tok, .data = .{ .lhs = path_expr } });
        return self.addNode(.{ .tag = .expression_stmt, .main_token = 0, .data = .{ .lhs = req } });
    }

    fn parseExpressionStmt(self: *Parser) Error!u32 {
        const expr = try self.parseExpression();
        _ = try self.expect(.semicolon);
        return self.addNode(.{ .tag = .expression_stmt, .main_token = 0, .data = .{ .lhs = expr } });
    }

    fn parseEchoStmt(self: *Parser) Error!u32 {
        const echo_tok = self.advance();
        var exprs = std.ArrayListUnmanaged(u32){};
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

    fn parseBreakContinue(self: *Parser, tag: NodeTag) Error!u32 {
        const tok = self.advance();
        var level: u32 = 0;
        if (self.peek() == .integer) {
            const lit = self.tokens[self.pos].lexeme(self.source);
            level = std.fmt.parseInt(u32, lit, 10) catch 1;
            _ = self.advance();
        }
        _ = try self.expect(.semicolon);
        return self.addNode(.{ .tag = tag, .main_token = tok, .data = .{ .lhs = level } });
    }

    fn parseSimpleStmt(self: *Parser, tag: NodeTag) Error!u32 {
        const tok = self.advance();
        _ = try self.expect(.semicolon);
        return self.addNode(.{ .tag = tag, .main_token = tok, .data = .{} });
    }

    fn parseBlock(self: *Parser) Error!u32 {
        const brace_tok = try self.expect(.l_brace);
        var stmts = std.ArrayListUnmanaged(u32){};
        defer stmts.deinit(self.allocator);

        while (self.peek() != .r_brace and self.peek() != .eof) {
            const stmt = self.parseStatement() catch |err| switch (err) {
                error.ParseError => {
                    self.synchronize();
                    continue;
                },
                error.OutOfMemory => return error.OutOfMemory,
            };
            try stmts.append(self.allocator, stmt);
        }
        _ = try self.expect(.r_brace);

        const extra = try self.addExtraList(stmts.items);
        return self.addNode(.{ .tag = .block, .main_token = brace_tok, .data = .{ .lhs = extra } });
    }

    // ======================================================================
    // control flow
    // ======================================================================

    fn parseIfStmt(self: *Parser) Error!u32 {
        const if_tok = self.advance();
        _ = try self.expect(.l_paren);
        const cond = try self.parseExpression();
        _ = try self.expect(.r_paren);
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

        const body = try self.parseStatementOrBlock();
        const extra = try self.addExtra(&.{ init, cond, update });
        return self.addNode(.{ .tag = .for_stmt, .main_token = tok, .data = .{ .lhs = extra, .rhs = body } });
    }

    // parse comma-separated expressions for for-loop init/update
    // returns a single expression node if only one, or an expr_list node
    fn parseForExprList(self: *Parser) Error!u32 {
        const first = try self.parseExpression();
        if (self.peek() != .comma) return first;
        var exprs = std.ArrayListUnmanaged(u32){};
        defer exprs.deinit(self.allocator);
        try exprs.append(self.allocator, first);
        while (self.peek() == .comma) {
            _ = self.advance();
            try exprs.append(self.allocator, try self.parseExpression());
        }
        const extra = try self.addExtraList(exprs.items);
        return self.addNode(.{ .tag = .expr_list, .main_token = 0, .data = .{ .lhs = extra } });
    }

    fn parseForeachStmt(self: *Parser) Error!u32 {
        const tok = self.advance();
        _ = try self.expect(.l_paren);
        const iterable = try self.parseExpression();
        _ = try self.expect(.kw_as);

        // skip & for foreach by-reference (zphp arrays are already reference semantics)
        if (self.peek() == .amp) _ = self.advance();
        const first = try self.parseExpression();
        var value: u32 = first;
        var key: u32 = 0;

        if (self.peek() == .fat_arrow) {
            _ = self.advance();
            key = first;
            if (self.peek() == .amp) _ = self.advance();
            value = try self.parseExpression();
        }

        _ = try self.expect(.r_paren);
        const body = try self.parseStatementOrBlock();
        const extra = try self.addExtra(&.{ iterable, value, key });
        return self.addNode(.{ .tag = .foreach_stmt, .main_token = tok, .data = .{ .lhs = extra, .rhs = body } });
    }

    fn parseConstDecl(self: *Parser) Error!u32 {
        _ = self.advance(); // const
        const name_tok = try self.expect(.identifier);
        _ = try self.expect(.equal);
        const value = try self.parseExpression();
        _ = try self.expect(.semicolon);
        return self.addNode(.{ .tag = .const_decl, .main_token = name_tok, .data = .{ .lhs = value } });
    }

    fn parseSwitchStmt(self: *Parser) Error!u32 {
        const switch_tok = self.advance(); // switch
        _ = try self.expect(.l_paren);
        const cond = try self.parseExpression();
        _ = try self.expect(.r_paren);
        _ = try self.expect(.l_brace);

        var cases = std.ArrayListUnmanaged(u32){};
        defer cases.deinit(self.allocator);

        while (self.peek() != .r_brace and self.peek() != .eof) {
            if (self.peek() == .kw_case) {
                try cases.append(self.allocator, try self.parseSwitchCase());
            } else if (self.peek() == .kw_default) {
                try cases.append(self.allocator, try self.parseSwitchDefault());
            } else {
                self.synchronize();
            }
        }
        _ = try self.expect(.r_brace);

        const extra = try self.addExtraList(cases.items);
        return self.addNode(.{ .tag = .switch_stmt, .main_token = switch_tok, .data = .{ .lhs = cond, .rhs = extra } });
    }

    fn parseSwitchCase(self: *Parser) Error!u32 {
        const case_tok = self.advance(); // case

        var values = std.ArrayListUnmanaged(u32){};
        defer values.deinit(self.allocator);

        try values.append(self.allocator, try self.parseExpression());
        _ = try self.expect(.colon);

        // collect fallthrough cases: case 1: case 2: case 3: body
        while (self.peek() == .kw_case) {
            _ = self.advance();
            try values.append(self.allocator, try self.parseExpression());
            _ = try self.expect(.colon);
        }

        var stmts = std.ArrayListUnmanaged(u32){};
        defer stmts.deinit(self.allocator);

        while (self.peek() != .kw_case and self.peek() != .kw_default and self.peek() != .r_brace and self.peek() != .eof) {
            const stmt = self.parseStatement() catch |err| switch (err) {
                error.ParseError => { self.synchronize(); continue; },
                error.OutOfMemory => return error.OutOfMemory,
            };
            try stmts.append(self.allocator, stmt);
        }

        const vals_extra = try self.addExtraList(values.items);
        const body_extra = try self.addExtraList(stmts.items);
        return self.addNode(.{ .tag = .switch_case, .main_token = case_tok, .data = .{ .lhs = vals_extra, .rhs = body_extra } });
    }

    fn parseSwitchDefault(self: *Parser) Error!u32 {
        const def_tok = self.advance(); // default
        _ = try self.expect(.colon);

        var stmts = std.ArrayListUnmanaged(u32){};
        defer stmts.deinit(self.allocator);

        while (self.peek() != .kw_case and self.peek() != .kw_default and self.peek() != .r_brace and self.peek() != .eof) {
            const stmt = self.parseStatement() catch |err| switch (err) {
                error.ParseError => { self.synchronize(); continue; },
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

        var arms = std.ArrayListUnmanaged(u32){};
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

        var values = std.ArrayListUnmanaged(u32){};
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
        const name_tok = try self.expectFunctionName();
        _ = try self.expect(.l_paren);

        var params = std.ArrayListUnmanaged(u32){};
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

        if (self.peek() == .colon) {
            _ = self.advance();
            self.skipTypeHint();
        }

        const body = try self.parseBlock();
        const extra = try self.addExtraList(params.items);
        return self.addNode(.{ .tag = .function_decl, .main_token = name_tok, .data = .{ .lhs = extra, .rhs = body } });
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

        var catches = std.ArrayListUnmanaged(u32){};
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
        var extra_data = std.ArrayListUnmanaged(u32){};
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

        var types = std.ArrayListUnmanaged(u32){};
        defer types.deinit(self.allocator);

        if (self.peek() == .identifier or self.peek() == .backslash) {
            try types.append(self.allocator, try self.parseQualifiedName());

            while (self.peek() == .pipe) {
                _ = self.advance();
                try types.append(self.allocator, try self.parseQualifiedName());
            }
        }

        // optional variable
        var var_tok: u32 = 0;
        if (self.peek() == .variable) {
            var_tok = self.advance();
        }

        _ = try self.expect(.r_paren);
        const body = try self.parseBlock();

        // lhs = extra -> {type_count, type_nodes...}
        var extra = std.ArrayListUnmanaged(u32){};
        defer extra.deinit(self.allocator);
        try extra.append(self.allocator, @intCast(types.items.len));
        try extra.appendSlice(self.allocator, types.items);
        const lhs = try self.addExtra(extra.items);

        return self.addNode(.{ .tag = .catch_clause, .main_token = var_tok, .data = .{ .lhs = lhs, .rhs = body } });
    }

    fn parseNewExpr(self: *Parser) Error!u32 {
        _ = self.advance(); // new
        if (self.peek() == .backslash) _ = self.advance(); // leading backslash
        const name_tok = try self.expect(.identifier);

        // consume qualified name parts: \Identifier\Identifier...
        var name_parts = std.ArrayListUnmanaged(u32){};
        defer name_parts.deinit(self.allocator);
        try name_parts.append(self.allocator, name_tok);
        while (self.peek() == .backslash) {
            _ = self.advance();
            try name_parts.append(self.allocator, try self.expect(.identifier));
        }

        var args = std.ArrayListUnmanaged(u32){};
        defer args.deinit(self.allocator);

        if (self.peek() == .l_paren) {
            _ = self.advance();
            if (self.peek() != .r_paren) {
                try args.append(self.allocator, try self.parseExpression());
                while (self.peek() == .comma) {
                    _ = self.advance();
                    if (self.peek() == .r_paren) break;
                    try args.append(self.allocator, try self.parseExpression());
                }
            }
            _ = try self.expect(.r_paren);
        }

        const extra = try self.addExtraList(args.items);
        const name_extra = if (name_parts.items.len > 1)
            try self.addExtraList(name_parts.items)
        else
            @as(u32, 0);
        return self.addNode(.{ .tag = .new_expr, .main_token = name_tok, .data = .{ .lhs = extra, .rhs = name_extra } });
    }

    fn parseYieldExpr(self: *Parser) Error!u32 {
        const tok = self.advance(); // yield

        // yield from $expr
        if (self.peek() == .identifier) {
            const next_tok = self.tokens[self.pos].lexeme(self.source);
            if (std.mem.eql(u8, next_tok, "from")) {
                _ = self.advance(); // consume "from"
                const iterable = try self.parseExprPrec(1);
                return self.addNode(.{ .tag = .yield_from_expr, .main_token = tok, .data = .{ .lhs = iterable } });
            }
        }

        // bare yield (no value)
        if (self.peek() == .semicolon or self.peek() == .r_paren or
            self.peek() == .r_bracket or self.peek() == .comma or self.peek() == .eof)
        {
            return self.addNode(.{ .tag = .yield_expr, .main_token = tok, .data = .{} });
        }

        const expr = try self.parseExprPrec(1);

        // yield $key => $value
        if (self.peek() == .fat_arrow) {
            _ = self.advance();
            const value = try self.parseExprPrec(1);
            return self.addNode(.{ .tag = .yield_pair_expr, .main_token = tok, .data = .{ .lhs = expr, .rhs = value } });
        }

        return self.addNode(.{ .tag = .yield_expr, .main_token = tok, .data = .{ .lhs = expr } });
    }

    fn parseClassDecl(self: *Parser) Error!u32 {
        if (self.peek() == .kw_abstract) _ = self.advance();
        _ = self.advance(); // class
        const name_tok = try self.expect(.identifier);

        var parent: u32 = 0;
        if (self.peek() == .kw_extends) {
            _ = self.advance();
            parent = try self.parseQualifiedName();
        }

        var implements = std.ArrayListUnmanaged(u32){};
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

        var members = std.ArrayListUnmanaged(u32){};
        defer members.deinit(self.allocator);

        while (self.peek() != .r_brace and self.peek() != .eof) {
            var is_static = false;
            var is_abstract = false;
            var is_readonly = false;
            var visibility: u32 = 0; // 0=public, 1=protected, 2=private
            while (self.peek() == .kw_public or self.peek() == .kw_protected or
                self.peek() == .kw_private or self.peek() == .kw_static or
                self.peek() == .kw_abstract or self.peek() == .kw_readonly)
            {
                if (self.peek() == .kw_static) is_static = true;
                if (self.peek() == .kw_abstract) is_abstract = true;
                if (self.peek() == .kw_readonly) is_readonly = true;
                if (self.peek() == .kw_protected) visibility = 1;
                if (self.peek() == .kw_private) visibility = 2;
                _ = self.advance();
            }

            if (self.peek() == .kw_use) {
                try members.append(self.allocator, try self.parseTraitUse());
            } else if (self.peek() == .kw_function) {
                if (is_abstract) {
                    try members.append(self.allocator, try self.parseInterfaceMethod());
                } else {
                    const method = try self.parseClassMethod();
                    if (is_static) {
                        self.nodes.items[method].tag = .static_class_method;
                    }
                    // encode visibility in rhs high bits (rhs is body block index)
                    // store visibility separately in extra_data
                    self.nodes.items[method].data.rhs = self.nodes.items[method].data.rhs | (visibility << 30);
                    try members.append(self.allocator, method);
                }
            } else if (self.peek() == .variable) {
                const prop = try self.parseClassProperty();
                if (is_static) {
                    self.nodes.items[prop].tag = .static_class_property;
                }
                // bits 0-1: visibility, bit 2: readonly
                self.nodes.items[prop].data.rhs = visibility | (if (is_readonly) @as(u32, 4) else 0);
                try members.append(self.allocator, prop);
            } else if (self.peek() == .kw_const) {
                try members.append(self.allocator, try self.parseConstDecl());
            } else if (self.isTypeName() or self.peek() == .question or self.peek() == .l_paren) {
                self.skipTypeHint();
                if (self.peek() == .variable) {
                    const prop = try self.parseClassProperty();
                    if (is_static) {
                        self.nodes.items[prop].tag = .static_class_property;
                    }
                    self.nodes.items[prop].data.rhs = visibility | (if (is_readonly) @as(u32, 4) else 0);
                    try members.append(self.allocator, prop);
                } else {
                    _ = self.advance();
                }
            } else {
                _ = self.advance();
            }
        }
        _ = try self.expect(.r_brace);

        const extra = try self.addExtraList(members.items);

        // rhs encodes parent + implements: {parent_node, implements_count, impl_nodes...}
        var rhs_data = std.ArrayListUnmanaged(u32){};
        defer rhs_data.deinit(self.allocator);
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

        var parent: u32 = 0;
        if (self.peek() == .kw_extends) {
            _ = self.advance();
            parent = try self.parseQualifiedName();
        }

        _ = try self.expect(.l_brace);

        var methods = std.ArrayListUnmanaged(u32){};
        defer methods.deinit(self.allocator);

        while (self.peek() != .r_brace and self.peek() != .eof) {
            while (self.peek() == .kw_public or self.peek() == .kw_protected or
                self.peek() == .kw_private or self.peek() == .kw_static or
                self.peek() == .kw_abstract)
            {
                _ = self.advance();
            }
            if (self.peek() == .kw_function) {
                try methods.append(self.allocator, try self.parseInterfaceMethod());
            } else if (self.peek() == .kw_const) {
                try methods.append(self.allocator, try self.parseConstDecl());
            } else {
                _ = self.advance();
            }
        }
        _ = try self.expect(.r_brace);

        const extra = try self.addExtraList(methods.items);
        return self.addNode(.{ .tag = .interface_decl, .main_token = name_tok, .data = .{ .lhs = extra, .rhs = parent } });
    }

    fn parseInterfaceMethod(self: *Parser) Error!u32 {
        _ = self.advance(); // function
        const name_tok = try self.expectFunctionName();
        _ = try self.expect(.l_paren);

        var params = std.ArrayListUnmanaged(u32){};
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

        if (self.peek() == .colon) {
            _ = self.advance();
            self.skipTypeHint();
        }

        _ = try self.expect(.semicolon);
        const extra = try self.addExtraList(params.items);
        return self.addNode(.{ .tag = .interface_method, .main_token = name_tok, .data = .{ .lhs = extra } });
    }

    fn parseTraitDecl(self: *Parser) Error!u32 {
        _ = self.advance(); // trait
        const name_tok = try self.expect(.identifier);
        _ = try self.expect(.l_brace);

        var members = std.ArrayListUnmanaged(u32){};
        defer members.deinit(self.allocator);

        while (self.peek() != .r_brace and self.peek() != .eof) {
            var is_static = false;
            while (self.peek() == .kw_public or self.peek() == .kw_protected or
                self.peek() == .kw_private or self.peek() == .kw_static or
                self.peek() == .kw_abstract or self.peek() == .kw_readonly)
            {
                if (self.peek() == .kw_static) is_static = true;
                _ = self.advance();
            }

            if (self.peek() == .kw_function) {
                const method = try self.parseClassMethod();
                if (is_static) {
                    self.nodes.items[method].tag = .static_class_method;
                }
                try members.append(self.allocator, method);
            } else if (self.peek() == .variable) {
                const prop = try self.parseClassProperty();
                if (is_static) {
                    self.nodes.items[prop].tag = .static_class_property;
                }
                try members.append(self.allocator, prop);
            } else if (self.isTypeName() or self.peek() == .question or self.peek() == .l_paren) {
                self.skipTypeHint();
                if (self.peek() == .variable) {
                    const prop = try self.parseClassProperty();
                    if (is_static) {
                        self.nodes.items[prop].tag = .static_class_property;
                    }
                    try members.append(self.allocator, prop);
                } else {
                    _ = self.advance();
                }
            } else if (self.peek() == .kw_const) {
                try members.append(self.allocator, try self.parseConstDecl());
            } else if (self.peek() == .kw_use) {
                try members.append(self.allocator, try self.parseTraitUse());
            } else {
                _ = self.advance();
            }
        }
        _ = try self.expect(.r_brace);

        const extra = try self.addExtraList(members.items);
        return self.addNode(.{ .tag = .trait_decl, .main_token = name_tok, .data = .{ .lhs = extra } });
    }

    fn parseEnumDecl(self: *Parser) Error!u32 {
        _ = self.advance(); // enum
        const name_tok = try self.expect(.identifier);

        var backed_type_token: u32 = 0;
        if (self.peek() == .colon) {
            _ = self.advance();
            backed_type_token = self.advance();
        }

        var implements = std.ArrayListUnmanaged(u32){};
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

        var members = std.ArrayListUnmanaged(u32){};
        defer members.deinit(self.allocator);

        while (self.peek() != .r_brace and self.peek() != .eof) {
            if (self.peek() == .kw_case) {
                _ = self.advance();
                const case_name = try self.expect(.identifier);
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
                try members.append(self.allocator, try self.parseConstDecl());
            } else {
                var is_static = false;
                var visibility: u32 = 0;
                while (self.peek() == .kw_public or self.peek() == .kw_protected or
                    self.peek() == .kw_private or self.peek() == .kw_static)
                {
                    if (self.peek() == .kw_static) is_static = true;
                    if (self.peek() == .kw_protected) visibility = 1;
                    if (self.peek() == .kw_private) visibility = 2;
                    _ = self.advance();
                }
                if (self.peek() == .kw_function) {
                    const method = try self.parseClassMethod();
                    if (is_static) {
                        self.nodes.items[method].tag = .static_class_method;
                    }
                    self.nodes.items[method].data.rhs = self.nodes.items[method].data.rhs | (visibility << 30);
                    try members.append(self.allocator, method);
                } else {
                    _ = self.advance();
                }
            }
        }
        _ = try self.expect(.r_brace);

        const extra = try self.addExtraList(members.items);

        var rhs_data = std.ArrayListUnmanaged(u32){};
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
        var traits = std.ArrayListUnmanaged(u32){};
        defer traits.deinit(self.allocator);

        try traits.append(self.allocator, try self.parseQualifiedName());
        while (self.peek() == .comma) {
            _ = self.advance();
            try traits.append(self.allocator, try self.parseQualifiedName());
        }

        var conflicts = std.ArrayListUnmanaged(u32){};
        defer conflicts.deinit(self.allocator);

        if (self.peek() == .l_brace) {
            _ = self.advance();
            while (self.peek() != .r_brace and self.peek() != .eof) {
                // TraitName::method insteadof OtherTrait;
                // TraitName::method as alias;
                // TraitName::method as public;
                const trait_node = try self.parseQualifiedName();
                _ = try self.expect(.colon_colon);
                const method_tok = try self.expectFunctionName();

                if (self.peek() == .kw_insteadof) {
                    _ = self.advance();
                    var excluded = std.ArrayListUnmanaged(u32){};
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
                    const alias_tok = self.advance();
                    try conflicts.append(self.allocator, try self.addNode(.{
                        .tag = .trait_as,
                        .main_token = method_tok,
                        .data = .{ .lhs = trait_node, .rhs = alias_tok },
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
        const name_tok = try self.expectFunctionName();
        _ = try self.expect(.l_paren);

        var params = std.ArrayListUnmanaged(u32){};
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

        if (self.peek() == .colon) {
            _ = self.advance();
            self.skipTypeHint();
        }

        const body = try self.parseBlock();
        const extra = try self.addExtraList(params.items);
        return self.addNode(.{ .tag = .class_method, .main_token = name_tok, .data = .{ .lhs = extra, .rhs = body } });
    }

    fn parseClassProperty(self: *Parser) Error!u32 {
        const tok = self.advance(); // $variable
        var default: u32 = 0;
        if (self.peek() == .equal) {
            _ = self.advance();
            default = try self.parseExpression();
        }
        _ = try self.expect(.semicolon);
        return self.addNode(.{ .tag = .class_property, .main_token = tok, .data = .{ .lhs = default } });
    }

    fn parseClosureExpr(self: *Parser) Error!u32 {
        const fn_tok = self.advance(); // function
        _ = try self.expect(.l_paren);

        var params = std.ArrayListUnmanaged(u32){};
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

        var use_vars = std.ArrayListUnmanaged(u32){};
        defer use_vars.deinit(self.allocator);

        if (self.peek() == .kw_use) {
            _ = self.advance();
            _ = try self.expect(.l_paren);
            if (self.peek() != .r_paren) {
                if (self.peek() == .amp) _ = self.advance();
                const tok = try self.expect(.variable);
                try use_vars.append(self.allocator, try self.addNode(.{ .tag = .variable, .main_token = tok, .data = .{} }));
                while (self.peek() == .comma) {
                    _ = self.advance();
                    if (self.peek() == .r_paren) break;
                    if (self.peek() == .amp) _ = self.advance();
                    const vtok = try self.expect(.variable);
                    try use_vars.append(self.allocator, try self.addNode(.{ .tag = .variable, .main_token = vtok, .data = .{} }));
                }
            }
            _ = try self.expect(.r_paren);
        }

        if (self.peek() == .colon) {
            _ = self.advance();
            self.skipTypeHint();
        }

        const body = try self.parseBlock();
        const param_extra = try self.addExtraList(params.items);

        // rhs = extra -> {body, use_count, use_vars...}
        var rhs_data = std.ArrayListUnmanaged(u32){};
        defer rhs_data.deinit(self.allocator);
        try rhs_data.append(self.allocator, body);
        try rhs_data.append(self.allocator, @intCast(use_vars.items.len));
        try rhs_data.appendSlice(self.allocator, use_vars.items);
        const rhs_extra = try self.addExtra(rhs_data.items);

        return self.addNode(.{ .tag = .closure_expr, .main_token = fn_tok, .data = .{ .lhs = param_extra, .rhs = rhs_extra } });
    }

    fn parseArrowFunc(self: *Parser) Error!u32 {
        const fn_tok = self.advance(); // fn
        _ = try self.expect(.l_paren);

        var params = std.ArrayListUnmanaged(u32){};
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

        if (self.peek() == .colon) {
            _ = self.advance();
            self.skipTypeHint();
        }

        _ = try self.expect(.fat_arrow);
        const expr = try self.parseExpression();

        const ret = try self.addNode(.{ .tag = .return_stmt, .main_token = fn_tok, .data = .{ .lhs = expr } });
        const block_extra = try self.addExtraList(&.{ret});
        const body = try self.addNode(.{ .tag = .block, .main_token = fn_tok, .data = .{ .lhs = block_extra } });

        const param_extra = try self.addExtraList(params.items);
        // rhs = extra -> {body, use_count}. 0xFFFFFFFF signals arrow fn (implicit capture)
        const rhs_extra = try self.addExtra(&.{ body, 0xFFFFFFFF });

        return self.addNode(.{ .tag = .closure_expr, .main_token = fn_tok, .data = .{ .lhs = param_extra, .rhs = rhs_extra } });
    }

    // parse a qualified name like App\Models\User or just User
    // returns an identifier node for simple names, qualified_name node for multi-part
    fn parseQualifiedName(self: *Parser) Error!u32 {
        // optional leading backslash for fully-qualified names
        const has_leading = self.peek() == .backslash;
        if (has_leading) _ = self.advance();

        const first_tok = try self.expect(.identifier);
        if (self.peek() != .backslash) {
            // simple name - return as plain identifier
            return self.addNode(.{ .tag = .identifier, .main_token = first_tok, .data = .{} });
        }

        var parts = std.ArrayListUnmanaged(u32){};
        defer parts.deinit(self.allocator);
        try parts.append(self.allocator, first_tok);
        while (self.peek() == .backslash) {
            _ = self.advance();
            try parts.append(self.allocator, try self.expect(.identifier));
        }
        const extra = try self.addExtraList(parts.items);
        return self.addNode(.{ .tag = .qualified_name, .main_token = first_tok, .data = .{ .lhs = extra } });
    }

    fn isTypeName(self: *Parser) bool {
        const tag = self.peek();
        return tag == .identifier or tag == .kw_array or tag == .kw_callable or
            tag == .kw_self or tag == .kw_static or tag == .kw_null or
            tag == .kw_true or tag == .kw_false;
    }

    // consumes a full PHP type expression: simple, nullable, union, intersection, DNF
    // e.g. int, ?string, int|string, Foo&Bar, (Foo&Bar)|null
    fn skipTypeHint(self: *Parser) void {
        if (self.peek() == .question) {
            _ = self.advance();
            if (self.isTypeName()) _ = self.advance();
            return;
        }

        // DNF: (Foo&Bar)|Baz
        if (self.peek() == .l_paren) {
            _ = self.advance();
            while (self.isTypeName()) {
                _ = self.advance();
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
        _ = self.advance();

        // union: int|string|null or intersection: Foo&Bar
        if (self.peek() == .pipe) {
            while (self.peek() == .pipe) {
                _ = self.advance();
                if (self.peek() == .l_paren) {
                    // DNF group mid-union
                    _ = self.advance();
                    while (self.isTypeName()) {
                        _ = self.advance();
                        if (self.peek() == .amp) {
                            _ = self.advance();
                        } else break;
                    }
                    if (self.peek() == .r_paren) _ = self.advance();
                } else if (self.isTypeName()) {
                    _ = self.advance();
                }
            }
        } else if (self.peek() == .amp) {
            while (self.peek() == .amp) {
                _ = self.advance();
                if (self.isTypeName()) _ = self.advance();
            }
        }
    }

    fn parseParam(self: *Parser) Error!u32 {
        // constructor property promotion: visibility keyword before param
        // 0 = none, 1 = public, 2 = protected, 3 = private
        var promotion: u32 = 0;
        var param_readonly = false;
        // handle readonly and visibility in any order
        if (self.peek() == .kw_readonly) { param_readonly = true; _ = self.advance(); }
        if (self.peek() == .kw_public) { promotion = 1; _ = self.advance(); }
        else if (self.peek() == .kw_protected) { promotion = 2; _ = self.advance(); }
        else if (self.peek() == .kw_private) { promotion = 3; _ = self.advance(); }
        if (self.peek() == .kw_readonly) { param_readonly = true; _ = self.advance(); }
        if (self.isTypeName() or self.peek() == .question or self.peek() == .l_paren) {
            self.skipTypeHint();
        }
        // reference: &$param
        const is_ref = self.peek() == .amp;
        if (is_ref) _ = self.advance();
        // variadic: ...$args
        const is_variadic = self.peek() == .ellipsis;
        if (is_variadic) _ = self.advance();

        const tok = try self.expect(.variable);
        var default: u32 = 0;
        if (self.peek() == .equal) {
            _ = self.advance();
            default = try self.parseExpression();
        }
        // rhs encoding: bit 0 = variadic, bit 1 = by-reference, bits 2-3 = promotion visibility, bit 4 = readonly
        var flags: u32 = 0;
        if (is_variadic) flags |= 1;
        if (is_ref) flags |= 2;
        flags |= (promotion << 2);
        if (param_readonly) flags |= 16;
        return self.addNode(.{ .tag = .variable, .main_token = tok, .data = .{ .lhs = default, .rhs = flags } });
    }

    // ======================================================================
    // expressions
    // ======================================================================

    fn parseExpression(self: *Parser) Error!u32 {
        return self.parseExprPrec(0);
    }

    fn parseExprPrec(self: *Parser, min_prec: u8) Error!u32 {
        var left = try self.parsePrefixExpr();

        while (true) {
            // postfix: call, index, property, increment/decrement
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
                    if (20 > min_prec) {
                        const tok = self.advance();
                        left = try self.addNode(.{ .tag = .postfix_op, .main_token = tok, .data = .{ .lhs = left } });
                        continue;
                    }
                    break;
                },
                else => {},
            }

            // ternary
            if (self.peek() == .question and infixPrec(.question) > min_prec) {
                left = try self.parseTernary(left);
                continue;
            }

            // infix
            const prec = infixPrec(self.peek());
            if (prec == 0 or prec <= min_prec) break;

            const op_tok = self.advance();
            const op_tag = self.tokens[op_tok].tag;
            const right_min = if (isRightAssoc(op_tag)) prec - 1 else prec;
            const right = try self.parseExprPrec(right_min);
            const node_tag = infixNodeTag(op_tag);

            left = try self.addNode(.{ .tag = node_tag, .main_token = op_tok, .data = .{ .lhs = left, .rhs = right } });
        }

        return left;
    }

    fn parsePrefixExpr(self: *Parser) Error!u32 {
        switch (self.peek()) {
            .minus, .bang, .tilde, .at => {
                const tok = self.advance();
                const operand = try self.parseExprPrec(18);
                return self.addNode(.{ .tag = .prefix_op, .main_token = tok, .data = .{ .lhs = operand } });
            },
            .plus_plus, .minus_minus => {
                const tok = self.advance();
                const operand = try self.parseExprPrec(18);
                return self.addNode(.{ .tag = .prefix_op, .main_token = tok, .data = .{ .lhs = operand } });
            },
            .kw_clone => {
                const tok = self.advance();
                const operand = try self.parseExprPrec(18);
                return self.addNode(.{ .tag = .prefix_op, .main_token = tok, .data = .{ .lhs = operand } });
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
            .string, .heredoc, .nowdoc => self.addLiteral(.string_literal),
            .kw_true => self.addLiteral(.true_literal),
            .kw_false => self.addLiteral(.false_literal),
            .kw_null => self.addLiteral(.null_literal),
            .variable => self.addLiteral(.variable),
            .identifier => if (self.peekAt(1) == .backslash) self.parseQualifiedName() else self.addLiteral(.identifier),
            .kw_isset, .kw_empty, .kw_unset, .kw_eval, .kw_exit, .kw_die => self.addLiteral(.identifier),
            .kw_list => self.parseListDestructure(),
            .kw_match => if (self.isMatchExpr()) self.parseMatchExpr() else self.addLiteral(.identifier),
            .kw_function => self.parseClosureExpr(),
            .kw_fn => self.parseArrowFunc(),
            .l_paren => if (self.isCastExpr()) self.parseCastExpr() else self.parseGroupedExpr(),
            .l_bracket => self.parseArrayLiteral(),
            .kw_array => self.parseArrayKw(),
            .kw_static, .kw_self, .kw_parent => self.addLiteral(.identifier),
            else => {
                try self.addError(.expected_expression);
                return error.ParseError;
            },
        };
    }

    fn isCastExpr(self: *const Parser) bool {
        if (self.peekAt(2) != .r_paren) return false;
        const next = self.peekAt(1);
        if (next == .kw_array) return true;
        if (next != .identifier) return false;
        const lex = self.lexemeAt(1);
        return std.mem.eql(u8, lex, "int") or std.mem.eql(u8, lex, "integer") or
            std.mem.eql(u8, lex, "string") or std.mem.eql(u8, lex, "bool") or
            std.mem.eql(u8, lex, "boolean") or std.mem.eql(u8, lex, "float") or
            std.mem.eql(u8, lex, "double") or std.mem.eql(u8, lex, "real") or
            std.mem.eql(u8, lex, "object") or std.mem.eql(u8, lex, "unset");
    }

    fn parseCastExpr(self: *Parser) Error!u32 {
        _ = self.advance(); // (
        const type_tok = self.advance(); // type name
        _ = self.advance(); // )
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
            .kw_class, .kw_match, .kw_array, .kw_list, .kw_static, .kw_self, .kw_parent,
            .kw_true, .kw_false, .kw_null, .kw_fn, .kw_function, .kw_return, .kw_if,
            .kw_else, .kw_for, .kw_foreach, .kw_while, .kw_do, .kw_switch, .kw_case,
            .kw_default, .kw_break, .kw_continue, .kw_new, .kw_echo, .kw_throw,
            .kw_try, .kw_catch, .kw_finally, .kw_interface, .kw_trait, .kw_enum,
            .kw_abstract, .kw_final, .kw_readonly, .kw_global, .kw_const,
            .kw_public, .kw_private, .kw_protected, .kw_extends, .kw_implements,
            .kw_namespace, .kw_use, .kw_require, .kw_include, .kw_isset, .kw_empty,
            .kw_unset, .kw_eval, .kw_exit, .kw_die,
            => true,
            else => false,
        };
    }

    fn parseListDestructure(self: *Parser) Error!u32 {
        const list_tok = self.advance(); // list
        _ = try self.expect(.l_paren);
        var targets = std.ArrayListUnmanaged(u32){};
        defer targets.deinit(self.allocator);
        while (self.peek() != .r_paren) {
            if (self.peek() == .comma) {
                // skip slot (list(,$b) = ...)
                try targets.append(self.allocator, 0);
            } else if (self.peek() == .kw_list) {
                try targets.append(self.allocator, try self.parseListDestructure());
            } else {
                try targets.append(self.allocator, try self.parseExpression());
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
        var elements = std.ArrayListUnmanaged(u32){};
        defer elements.deinit(self.allocator);

        if (self.peek() != end) {
            try elements.append(self.allocator, try self.parseArrayElement());
            while (self.peek() == .comma) {
                _ = self.advance();
                if (self.peek() == end) break; // trailing comma
                try elements.append(self.allocator, try self.parseArrayElement());
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
        const expr = try self.parseExpression();
        if (self.peek() == .fat_arrow) {
            _ = self.advance();
            const value = try self.parseExpression();
            return self.addNode(.{ .tag = .array_element, .main_token = 0, .data = .{ .lhs = value, .rhs = expr } });
        }
        return self.addNode(.{ .tag = .array_element, .main_token = 0, .data = .{ .lhs = expr } });
    }

    // ======================================================================
    // postfix expressions
    // ======================================================================

    fn parseCallExpr(self: *Parser, callee: u32) Error!u32 {
        const paren_tok = self.advance(); // (

        // first-class callable: foo(...)
        if (self.peek() == .ellipsis and self.peekAt(1) == .r_paren) {
            _ = self.advance(); // ...
            _ = self.advance(); // )
            return self.addNode(.{ .tag = .callable_ref, .main_token = paren_tok, .data = .{ .lhs = callee } });
        }

        var args = std.ArrayListUnmanaged(u32){};
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
            // $arr[] - array push syntax
            _ = self.advance();
            return self.addNode(.{ .tag = .array_push_target, .main_token = bracket_tok, .data = .{ .lhs = array } });
        }
        const index = try self.parseExpression();
        _ = try self.expect(.r_bracket);
        return self.addNode(.{ .tag = .array_access, .main_token = bracket_tok, .data = .{ .lhs = array, .rhs = index } });
    }

    fn parsePropExpr(self: *Parser, object: u32, nullsafe: bool) Error!u32 {
        _ = self.advance(); // -> or ?->
        if (self.peek() != .identifier and self.peek() != .variable and !isSemiReserved(self.peek())) {
            try self.addError(.expected_identifier);
            return error.ParseError;
        }
        const name_tok = self.advance();

        // method call: $obj->method(...) or $obj?->method(...)
        if (self.peek() == .l_paren) {
            _ = self.advance(); // (
            var args = std.ArrayListUnmanaged(u32){};
            defer args.deinit(self.allocator);

            if (self.peek() != .r_paren) {
                try args.append(self.allocator, try self.parseExpression());
                while (self.peek() == .comma) {
                    _ = self.advance();
                    if (self.peek() == .r_paren) break;
                    try args.append(self.allocator, try self.parseExpression());
                }
            }
            _ = try self.expect(.r_paren);

            const extra = try self.addExtraList(args.items);
            const tag: Ast.Node.Tag = if (nullsafe) .nullsafe_method_call else .method_call;
            return self.addNode(.{ .tag = tag, .main_token = name_tok, .data = .{ .lhs = object, .rhs = extra } });
        }

        // property access: $obj->prop or $obj?->prop
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

        const name_tok = if (self.peek() == .identifier or isSemiReserved(self.peek()))
            self.advance()
        else
            try self.expect(.identifier);

        if (self.peek() == .l_paren) {
            _ = self.advance();
            var args = std.ArrayListUnmanaged(u32){};
            defer args.deinit(self.allocator);

            if (self.peek() != .r_paren) {
                try args.append(self.allocator, try self.parseExpression());
                while (self.peek() == .comma) {
                    _ = self.advance();
                    if (self.peek() == .r_paren) break;
                    try args.append(self.allocator, try self.parseExpression());
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

    // ======================================================================
    // precedence
    // ======================================================================

    fn infixPrec(tag: Tag) u8 {
        return switch (tag) {
            .kw_or => 1,
            .kw_xor => 2,
            .kw_and => 3,
            .equal, .plus_equal, .minus_equal, .star_equal, .slash_equal, .percent_equal, .star_star_equal, .dot_equal, .amp_equal, .pipe_equal, .caret_equal, .lt_lt_equal, .gt_gt_equal, .question_question_equal => 4,
            .question_question => 5,
            .question => 6,
            .pipe_pipe => 7,
            .amp_amp => 8,
            .pipe => 9,
            .caret => 10,
            .amp => 11,
            .equal_equal, .bang_equal, .equal_equal_equal, .bang_equal_equal, .lt_gt => 12,
            .lt, .lt_equal, .gt, .gt_equal, .spaceship => 13,
            .lt_lt, .gt_gt => 14,
            .plus, .minus, .dot => 15,
            .star, .slash, .percent => 16,
            .kw_instanceof => 17,
            .star_star => 19,
            else => 0,
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
            .equal, .plus_equal, .minus_equal, .star_equal, .slash_equal, .percent_equal, .star_star_equal, .dot_equal, .amp_equal, .pipe_equal, .caret_equal, .lt_lt_equal, .gt_gt_equal, .question_question_equal => .assign,
            else => .binary_op,
        };
    }

    // ======================================================================
    // utilities
    // ======================================================================

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
        try self.addError(expectedError(tag));
        return error.ParseError;
    }

    fn isSemiReserved(tag: Token.Tag) bool {
        return switch (tag) {
            .kw_match, .kw_enum, .kw_readonly, .kw_self, .kw_parent,
            .kw_true, .kw_false, .kw_null,
            => true,
            else => false,
        };
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

    fn addError(self: *Parser, tag: Ast.Error.Tag) Error!void {
        try self.errors.append(self.allocator, .{ .token = self.pos, .tag = tag });
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

