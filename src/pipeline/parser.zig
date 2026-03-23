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
            .kw_break => self.parseSimpleStmt(.break_stmt),
            .kw_continue => self.parseSimpleStmt(.continue_stmt),
            .kw_class => self.parseClassDecl(),
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

        const init = if (self.peek() != .semicolon) try self.parseExpression() else @as(u32, 0);
        _ = try self.expect(.semicolon);
        const cond = if (self.peek() != .semicolon) try self.parseExpression() else @as(u32, 0);
        _ = try self.expect(.semicolon);
        const update = if (self.peek() != .r_paren) try self.parseExpression() else @as(u32, 0);
        _ = try self.expect(.r_paren);

        const body = try self.parseStatementOrBlock();
        const extra = try self.addExtra(&.{ init, cond, update });
        return self.addNode(.{ .tag = .for_stmt, .main_token = tok, .data = .{ .lhs = extra, .rhs = body } });
    }

    fn parseForeachStmt(self: *Parser) Error!u32 {
        const tok = self.advance();
        _ = try self.expect(.l_paren);
        const iterable = try self.parseExpression();
        _ = try self.expect(.kw_as);

        const first = try self.parseExpression();
        var value: u32 = first;
        var key: u32 = 0;

        if (self.peek() == .fat_arrow) {
            _ = self.advance();
            key = first;
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
        const name_tok = try self.expect(.identifier);
        _ = try self.expect(.l_paren);

        var params = std.ArrayListUnmanaged(u32){};
        defer params.deinit(self.allocator);

        if (self.peek() != .r_paren) {
            try params.append(self.allocator, try self.parseParam());
            while (self.peek() == .comma) {
                _ = self.advance();
                try params.append(self.allocator, try self.parseParam());
            }
        }
        _ = try self.expect(.r_paren);

        // skip optional return type hint (: type)
        if (self.peek() == .colon) {
            _ = self.advance();
            _ = self.advance(); // consume type name
        }

        const body = try self.parseBlock();
        const extra = try self.addExtraList(params.items);
        return self.addNode(.{ .tag = .function_decl, .main_token = name_tok, .data = .{ .lhs = extra, .rhs = body } });
    }

    fn parseNewExpr(self: *Parser) Error!u32 {
        _ = self.advance(); // new
        const name_tok = try self.expect(.identifier);

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
        return self.addNode(.{ .tag = .new_expr, .main_token = name_tok, .data = .{ .lhs = extra } });
    }

    fn parseClassDecl(self: *Parser) Error!u32 {
        _ = self.advance(); // class
        const name_tok = try self.expect(.identifier);

        var parent: u32 = 0;
        if (self.peek() == .kw_extends) {
            _ = self.advance();
            parent = try self.addLiteral(.identifier);
        }

        _ = try self.expect(.l_brace);

        var members = std.ArrayListUnmanaged(u32){};
        defer members.deinit(self.allocator);

        while (self.peek() != .r_brace and self.peek() != .eof) {
            // skip visibility modifiers
            while (self.peek() == .kw_public or self.peek() == .kw_protected or
                self.peek() == .kw_private or self.peek() == .kw_static or
                self.peek() == .kw_abstract or self.peek() == .kw_readonly)
            {
                _ = self.advance();
            }

            if (self.peek() == .kw_function) {
                try members.append(self.allocator, try self.parseClassMethod());
            } else if (self.peek() == .variable) {
                try members.append(self.allocator, try self.parseClassProperty());
            } else if (self.peek() == .kw_const) {
                try members.append(self.allocator, try self.parseConstDecl());
            } else {
                _ = self.advance();
            }
        }
        _ = try self.expect(.r_brace);

        const extra = try self.addExtraList(members.items);
        return self.addNode(.{ .tag = .class_decl, .main_token = name_tok, .data = .{ .lhs = extra, .rhs = parent } });
    }

    fn parseClassMethod(self: *Parser) Error!u32 {
        _ = self.advance(); // function
        const name_tok = try self.expect(.identifier);
        _ = try self.expect(.l_paren);

        var params = std.ArrayListUnmanaged(u32){};
        defer params.deinit(self.allocator);

        if (self.peek() != .r_paren) {
            try params.append(self.allocator, try self.parseParam());
            while (self.peek() == .comma) {
                _ = self.advance();
                try params.append(self.allocator, try self.parseParam());
            }
        }
        _ = try self.expect(.r_paren);

        // skip optional return type hint
        if (self.peek() == .colon) {
            _ = self.advance();
            if (self.peek() == .question) _ = self.advance();
            _ = self.advance();
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
                const tok = try self.expect(.variable);
                try use_vars.append(self.allocator, try self.addNode(.{ .tag = .variable, .main_token = tok, .data = .{} }));
                while (self.peek() == .comma) {
                    _ = self.advance();
                    if (self.peek() == .r_paren) break;
                    const vtok = try self.expect(.variable);
                    try use_vars.append(self.allocator, try self.addNode(.{ .tag = .variable, .main_token = vtok, .data = .{} }));
                }
            }
            _ = try self.expect(.r_paren);
        }

        if (self.peek() == .colon) {
            _ = self.advance();
            _ = self.advance();
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
            _ = self.advance();
        }

        _ = try self.expect(.fat_arrow);
        const expr = try self.parseExpression();

        const ret = try self.addNode(.{ .tag = .return_stmt, .main_token = fn_tok, .data = .{ .lhs = expr } });
        const block_extra = try self.addExtraList(&.{ret});
        const body = try self.addNode(.{ .tag = .block, .main_token = fn_tok, .data = .{ .lhs = block_extra } });

        const param_extra = try self.addExtraList(params.items);
        // rhs = extra -> {body, 0} (no use vars for arrow functions)
        const rhs_extra = try self.addExtra(&.{ body, 0 });

        return self.addNode(.{ .tag = .closure_expr, .main_token = fn_tok, .data = .{ .lhs = param_extra, .rhs = rhs_extra } });
    }

    fn parseParam(self: *Parser) Error!u32 {
        // skip optional type hint
        if (self.peek() == .identifier or self.peek() == .question) {
            if (self.peek() == .question) _ = self.advance();
            if (self.peek() == .identifier) _ = self.advance();
        }
        const tok = try self.expect(.variable);
        return self.addNode(.{ .tag = .variable, .main_token = tok, .data = .{} });
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
                    left = try self.parsePropExpr(left);
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
            else => return self.parsePrimaryExpr(),
        }
    }

    fn parsePrimaryExpr(self: *Parser) Error!u32 {
        return switch (self.peek()) {
            .integer => self.addLiteral(.integer_literal),
            .float => self.addLiteral(.float_literal),
            .string => self.addLiteral(.string_literal),
            .kw_true => self.addLiteral(.true_literal),
            .kw_false => self.addLiteral(.false_literal),
            .kw_null => self.addLiteral(.null_literal),
            .variable => self.addLiteral(.variable),
            .identifier => self.addLiteral(.identifier),
            .kw_isset, .kw_empty, .kw_unset, .kw_eval, .kw_exit, .kw_die => self.addLiteral(.identifier),
            .kw_match => self.parseMatchExpr(),
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
        return self.addNode(.{ .tag = .call, .main_token = paren_tok, .data = .{ .lhs = callee, .rhs = extra } });
    }

    fn parseIndexExpr(self: *Parser, array: u32) Error!u32 {
        const bracket_tok = self.advance(); // [
        const index = try self.parseExpression();
        _ = try self.expect(.r_bracket);
        return self.addNode(.{ .tag = .array_access, .main_token = bracket_tok, .data = .{ .lhs = array, .rhs = index } });
    }

    fn parsePropExpr(self: *Parser, object: u32) Error!u32 {
        _ = self.advance(); // ->
        if (self.peek() != .identifier and self.peek() != .variable) {
            try self.addError(.expected_identifier);
            return error.ParseError;
        }
        const name_tok = self.advance();

        // method call: $obj->method(...)
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
            return self.addNode(.{ .tag = .method_call, .main_token = name_tok, .data = .{ .lhs = object, .rhs = extra } });
        }

        // property access: $obj->prop
        const prop = try self.addNode(.{ .tag = .identifier, .main_token = name_tok, .data = .{} });
        return self.addNode(.{ .tag = .property_access, .main_token = name_tok, .data = .{ .lhs = object, .rhs = prop } });
    }

    fn parseStaticAccess(self: *Parser, class_node: u32) Error!u32 {
        _ = self.advance(); // ::
        const name_tok = try self.expect(.identifier);

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

        // static property access could go here, but for now just treat as property
        const prop = try self.addNode(.{ .tag = .identifier, .main_token = name_tok, .data = .{} });
        return self.addNode(.{ .tag = .property_access, .main_token = name_tok, .data = .{ .lhs = class_node, .rhs = prop } });
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
        while (self.peek() != .eof) {
            switch (self.peek()) {
                .semicolon => {
                    _ = self.advance();
                    return;
                },
                .r_brace => return,
                .kw_if, .kw_while, .kw_for, .kw_foreach, .kw_function, .kw_return, .kw_echo, .kw_class => return,
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

// ==========================================================================
// test helpers
// ==========================================================================

const Buf = struct {
    inner: std.ArrayListUnmanaged(u8) = .{},
    gpa: Allocator,

    fn writer(self: *Buf) std.ArrayListUnmanaged(u8).Writer {
        return self.inner.writer(self.gpa);
    }

    fn deinit(self: *Buf) void {
        self.inner.deinit(self.gpa);
    }
};

fn expectParse(source: []const u8, expected: []const u8) !void {
    var ast = try parse(std.testing.allocator, source);
    defer ast.deinit();

    const stmts = ast.extraSlice(ast.nodes[0].data.lhs);
    var buf = Buf{ .gpa = std.testing.allocator };
    defer buf.deinit();

    for (stmts, 0..) |stmt, i| {
        if (i > 0) try buf.writer().writeByte(' ');
        try renderNode(&ast, stmt, &buf);
    }

    errdefer std.debug.print("\nexpected: {s}\n  actual: {s}\n", .{ expected, buf.inner.items });
    try std.testing.expectEqualStrings(expected, buf.inner.items);
}

fn expectError(source: []const u8) !void {
    var ast = try parse(std.testing.allocator, source);
    defer ast.deinit();
    try std.testing.expect(ast.errors.len > 0);
}

fn renderNode(ast: *const Ast, idx: u32, buf: *Buf) !void {
    const node = ast.nodes[idx];
    const w = buf.writer();
    switch (node.tag) {
        .integer_literal, .float_literal, .string_literal, .variable, .identifier => try w.writeAll(ast.tokenSlice(node.main_token)),
        .true_literal => try w.writeAll("true"),
        .false_literal => try w.writeAll("false"),
        .null_literal => try w.writeAll("null"),
        .expression_stmt => try renderNode(ast, node.data.lhs, buf),
        .echo_stmt => {
            try w.writeAll("(echo");
            for (ast.extraSlice(node.data.lhs)) |expr| {
                try w.writeByte(' ');
                try renderNode(ast, expr, buf);
            }
            try w.writeByte(')');
        },
        .return_stmt => {
            try w.writeAll("(return");
            if (node.data.lhs != 0) {
                try w.writeByte(' ');
                try renderNode(ast, node.data.lhs, buf);
            }
            try w.writeByte(')');
        },
        .break_stmt => try w.writeAll("(break)"),
        .continue_stmt => try w.writeAll("(continue)"),
        .binary_op, .logical_and, .logical_or, .null_coalesce => {
            try w.writeByte('(');
            try w.writeAll(ast.tokenSlice(node.main_token));
            try w.writeByte(' ');
            try renderNode(ast, node.data.lhs, buf);
            try w.writeByte(' ');
            try renderNode(ast, node.data.rhs, buf);
            try w.writeByte(')');
        },
        .assign => {
            try w.writeByte('(');
            try w.writeAll(ast.tokenSlice(node.main_token));
            try w.writeByte(' ');
            try renderNode(ast, node.data.lhs, buf);
            try w.writeByte(' ');
            try renderNode(ast, node.data.rhs, buf);
            try w.writeByte(')');
        },
        .prefix_op => {
            try w.writeByte('(');
            try w.writeAll(ast.tokenSlice(node.main_token));
            try renderNode(ast, node.data.lhs, buf);
            try w.writeByte(')');
        },
        .postfix_op => {
            try w.writeByte('(');
            try renderNode(ast, node.data.lhs, buf);
            try w.writeAll(ast.tokenSlice(node.main_token));
            try w.writeByte(')');
        },
        .grouped_expr => try renderNode(ast, node.data.lhs, buf),
        .cast_expr => {
            try w.writeAll("(cast ");
            try w.writeAll(ast.tokenSlice(node.main_token));
            try w.writeByte(' ');
            try renderNode(ast, node.data.lhs, buf);
            try w.writeByte(')');
        },
        .closure_expr => {
            try w.writeAll("(closure");
            for (ast.extraSlice(node.data.lhs)) |param| {
                try w.writeByte(' ');
                try renderNode(ast, param, buf);
            }
            try w.writeAll(" ...)");
        },
        .call => {
            try w.writeAll("(call ");
            try renderNode(ast, node.data.lhs, buf);
            for (ast.extraSlice(node.data.rhs)) |arg| {
                try w.writeByte(' ');
                try renderNode(ast, arg, buf);
            }
            try w.writeByte(')');
        },
        .array_access => {
            try w.writeAll("(idx ");
            try renderNode(ast, node.data.lhs, buf);
            try w.writeByte(' ');
            try renderNode(ast, node.data.rhs, buf);
            try w.writeByte(')');
        },
        .property_access => {
            try w.writeAll("(-> ");
            try renderNode(ast, node.data.lhs, buf);
            try w.writeByte(' ');
            try renderNode(ast, node.data.rhs, buf);
            try w.writeByte(')');
        },
        .ternary => {
            const then_n = ast.extra_data[node.data.rhs];
            const else_n = ast.extra_data[node.data.rhs + 1];
            try w.writeAll("(? ");
            try renderNode(ast, node.data.lhs, buf);
            if (then_n != 0) {
                try w.writeByte(' ');
                try renderNode(ast, then_n, buf);
            }
            try w.writeAll(" : ");
            try renderNode(ast, else_n, buf);
            try w.writeByte(')');
        },
        .array_literal => {
            try w.writeByte('[');
            for (ast.extraSlice(node.data.lhs), 0..) |elem, i| {
                if (i > 0) try w.writeAll(", ");
                try renderNode(ast, elem, buf);
            }
            try w.writeByte(']');
        },
        .array_element => {
            if (node.data.rhs != 0) {
                try renderNode(ast, node.data.rhs, buf);
                try w.writeAll(" => ");
            }
            try renderNode(ast, node.data.lhs, buf);
        },
        .if_simple => {
            try w.writeAll("(if ");
            try renderNode(ast, node.data.lhs, buf);
            try w.writeByte(' ');
            try renderNode(ast, node.data.rhs, buf);
            try w.writeByte(')');
        },
        .if_else => {
            try w.writeAll("(if ");
            try renderNode(ast, node.data.lhs, buf);
            try w.writeByte(' ');
            try renderNode(ast, ast.extra_data[node.data.rhs], buf);
            try w.writeAll(" else ");
            try renderNode(ast, ast.extra_data[node.data.rhs + 1], buf);
            try w.writeByte(')');
        },
        .while_stmt => {
            try w.writeAll("(while ");
            try renderNode(ast, node.data.lhs, buf);
            try w.writeByte(' ');
            try renderNode(ast, node.data.rhs, buf);
            try w.writeByte(')');
        },
        .do_while => {
            try w.writeAll("(do ");
            try renderNode(ast, node.data.lhs, buf);
            try w.writeAll(" while ");
            try renderNode(ast, node.data.rhs, buf);
            try w.writeByte(')');
        },
        .for_stmt => {
            try w.writeAll("(for)");
        },
        .foreach_stmt => {
            try w.writeAll("(foreach)");
        },
        .block => {
            try w.writeByte('{');
            for (ast.extraSlice(node.data.lhs)) |stmt| {
                try w.writeByte(' ');
                try renderNode(ast, stmt, buf);
            }
            try w.writeAll(" }");
        },
        .function_decl => {
            try w.writeAll("(fn ");
            try w.writeAll(ast.tokenSlice(node.main_token));
            try w.writeByte('(');
            for (ast.extraSlice(node.data.lhs), 0..) |param, i| {
                if (i > 0) try w.writeAll(", ");
                try renderNode(ast, param, buf);
            }
            try w.writeAll(") ");
            try renderNode(ast, node.data.rhs, buf);
            try w.writeByte(')');
        },
        .switch_stmt => {
            try w.writeAll("(switch ");
            try renderNode(ast, node.data.lhs, buf);
            for (ast.extraSlice(node.data.rhs)) |c| {
                try w.writeByte(' ');
                try renderNode(ast, c, buf);
            }
            try w.writeByte(')');
        },
        .switch_case => {
            try w.writeAll("(case");
            for (ast.extraSlice(node.data.lhs)) |v| {
                try w.writeByte(' ');
                try renderNode(ast, v, buf);
            }
            try w.writeAll(": ...");
            try w.writeByte(')');
        },
        .switch_default => try w.writeAll("(default: ...)"),
        .match_expr => {
            try w.writeAll("(match ");
            try renderNode(ast, node.data.lhs, buf);
            for (ast.extraSlice(node.data.rhs)) |a| {
                try w.writeByte(' ');
                try renderNode(ast, a, buf);
            }
            try w.writeByte(')');
        },
        .match_arm => {
            const vals = ast.extraSlice(node.data.lhs);
            if (vals.len == 0) {
                try w.writeAll("(default => ");
            } else {
                try w.writeByte('(');
                for (vals, 0..) |v, i| {
                    if (i > 0) try w.writeAll(", ");
                    try renderNode(ast, v, buf);
                }
                try w.writeAll(" => ");
            }
            try renderNode(ast, node.data.rhs, buf);
            try w.writeByte(')');
        },
        .const_decl => {
            try w.writeAll("(const ");
            try w.writeAll(ast.tokenSlice(node.main_token));
            try w.writeAll(" = ");
            try renderNode(ast, node.data.lhs, buf);
            try w.writeByte(')');
        },
        .inline_html => try w.writeAll("(html)"),
        .class_decl => {
            try w.writeAll("(class ");
            try w.writeAll(ast.tokenSlice(node.main_token));
            try w.writeByte(')');
        },
        .class_method => {
            try w.writeAll("(method ");
            try w.writeAll(ast.tokenSlice(node.main_token));
            try w.writeByte(')');
        },
        .class_property => {
            try w.writeAll("(prop ");
            try w.writeAll(ast.tokenSlice(node.main_token));
            try w.writeByte(')');
        },
        .new_expr => {
            try w.writeAll("(new ");
            try w.writeAll(ast.tokenSlice(node.main_token));
            for (ast.extraSlice(node.data.lhs)) |arg| {
                try w.writeByte(' ');
                try renderNode(ast, arg, buf);
            }
            try w.writeByte(')');
        },
        .method_call => {
            try w.writeAll("(-> ");
            try renderNode(ast, node.data.lhs, buf);
            try w.writeByte(' ');
            try w.writeAll(ast.tokenSlice(node.main_token));
            for (ast.extraSlice(node.data.rhs)) |arg| {
                try w.writeByte(' ');
                try renderNode(ast, arg, buf);
            }
            try w.writeByte(')');
        },
        .static_call => {
            try w.writeAll("(:: ");
            try renderNode(ast, node.data.lhs, buf);
            try w.writeByte(' ');
            try w.writeAll(ast.tokenSlice(node.main_token));
            for (ast.extraSlice(node.data.rhs)) |arg| {
                try w.writeByte(' ');
                try renderNode(ast, arg, buf);
            }
            try w.writeByte(')');
        },
        .root => {},
    }
}

// ==========================================================================
// tests
// ==========================================================================

test "integer literal" {
    try expectParse("<?php 42;", "42");
}

test "float literal" {
    try expectParse("<?php 3.14;", "3.14");
}

test "string literal" {
    try expectParse("<?php \"hello\";", "\"hello\"");
}

test "boolean and null literals" {
    try expectParse("<?php true;", "true");
    try expectParse("<?php false;", "false");
    try expectParse("<?php null;", "null");
}

test "variable" {
    try expectParse("<?php $x;", "$x");
}

test "binary addition" {
    try expectParse("<?php 1 + 2;", "(+ 1 2)");
}

test "binary precedence: add vs mul" {
    try expectParse("<?php 1 + 2 * 3;", "(+ 1 (* 2 3))");
}

test "binary precedence: mul vs add" {
    try expectParse("<?php 1 * 2 + 3;", "(+ (* 1 2) 3)");
}

test "left associativity" {
    try expectParse("<?php 1 + 2 + 3;", "(+ (+ 1 2) 3)");
}

test "right associativity: power" {
    try expectParse("<?php 2 ** 3 ** 4;", "(** 2 (** 3 4))");
}

test "parenthesized expression" {
    try expectParse("<?php (1 + 2) * 3;", "(* (+ 1 2) 3)");
}

test "assignment" {
    try expectParse("<?php $x = 42;", "(= $x 42)");
}

test "compound assignment" {
    try expectParse("<?php $x += 1;", "(+= $x 1)");
}

test "right-associative assignment" {
    try expectParse("<?php $a = $b = $c;", "(= $a (= $b $c))");
}

test "prefix negation" {
    try expectParse("<?php -$x;", "(-$x)");
}

test "prefix not" {
    try expectParse("<?php !$x;", "(!$x)");
}

test "postfix increment" {
    try expectParse("<?php $x++;", "($x++)");
}

test "prefix and postfix" {
    try expectParse("<?php -$x++;", "(-($x++))");
}

test "echo statement" {
    try expectParse("<?php echo \"hello\";", "(echo \"hello\")");
}

test "echo multiple" {
    try expectParse("<?php echo $a, $b;", "(echo $a $b)");
}

test "return statement" {
    try expectParse("<?php return 42;", "(return 42)");
}

test "bare return" {
    try expectParse("<?php return;", "(return)");
}

test "if simple" {
    try expectParse("<?php if ($x) $y;", "(if $x $y)");
}

test "if with block" {
    try expectParse("<?php if ($x) { $y; }", "(if $x { $y })");
}

test "if else" {
    try expectParse("<?php if ($x) { $a; } else { $b; }", "(if $x { $a } else { $b })");
}

test "while loop" {
    try expectParse("<?php while ($x) $y;", "(while $x $y)");
}

test "do while" {
    try expectParse("<?php do { $x; } while ($y);", "(do { $x } while $y)");
}

test "for loop" {
    try expectParse("<?php for ($i = 0; $i < 10; $i++) $x;", "(for)");
}

test "function declaration" {
    try expectParse(
        "<?php function add($a, $b) { return $a + $b; }",
        "(fn add($a, $b) { (return (+ $a $b)) })",
    );
}

test "function call" {
    try expectParse("<?php foo();", "(call foo)");
}

test "function call with args" {
    try expectParse("<?php foo($a, $b);", "(call foo $a $b)");
}

test "nested calls" {
    try expectParse("<?php foo(bar($x));", "(call foo (call bar $x))");
}

test "array access" {
    try expectParse("<?php $a[0];", "(idx $a 0)");
}

test "property access" {
    try expectParse("<?php $a->b;", "(-> $a b)");
}

test "method call" {
    try expectParse("<?php $a->b();", "(-> $a b)");
}

test "chained access" {
    try expectParse("<?php $a->b->c;", "(-> (-> $a b) c)");
}

test "ternary" {
    try expectParse("<?php $a ? $b : $c;", "(? $a $b : $c)");
}

test "short ternary" {
    try expectParse("<?php $a ?: $b;", "(? $a : $b)");
}

test "null coalesce" {
    try expectParse("<?php $a ?? $b;", "(?? $a $b)");
}

test "logical and/or" {
    try expectParse("<?php $a && $b || $c;", "(|| (&& $a $b) $c)");
}

test "comparison" {
    try expectParse("<?php $a == $b;", "(== $a $b)");
    try expectParse("<?php $a === $b;", "(=== $a $b)");
    try expectParse("<?php $a <=> $b;", "(<=> $a $b)");
}

test "string concat" {
    try expectParse("<?php $a . $b . $c;", "(. (. $a $b) $c)");
}

test "array literal" {
    try expectParse("<?php [1, 2, 3];", "[1, 2, 3]");
}

test "array with keys" {
    try expectParse("<?php ['a' => 1, 'b' => 2];", "['a' => 1, 'b' => 2]");
}

test "empty array" {
    try expectParse("<?php [];", "[]");
}

test "break and continue" {
    try expectParse("<?php while(1) { break; continue; }", "(while 1 { (break) (continue) })");
}

test "mixed html and php" {
    try expectParse("<h1>Hi</h1><?php echo $x;", "(html) (echo $x)");
}

test "multiple php blocks" {
    try expectParse("A<?php $a; ?>B<?= $b ?>C", "(html) $a (html) (echo $b) (html)");
}

test "complex precedence" {
    try expectParse("<?php $a = $b + $c * $d;", "(= $a (+ $b (* $c $d)))");
}

test "instanceof" {
    try expectParse("<?php $a instanceof Foo;", "(instanceof $a Foo)");
}

test "parse error recovery" {
    try expectError("<?php $x = ;");
}

test "multiple statements" {
    try expectParse("<?php $a = 1; $b = 2;", "(= $a 1) (= $b 2)");
}
