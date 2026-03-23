const std = @import("std");
const Token = @import("token.zig").Token;

pub const Ast = struct {
    source: []const u8,
    tokens: []const Token,
    nodes: []const Node,
    extra_data: []const u32,
    errors: []const Error,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Ast) void {
        self.allocator.free(self.tokens);
        self.allocator.free(self.nodes);
        self.allocator.free(self.extra_data);
        self.allocator.free(self.errors);
    }

    pub fn tokenSlice(self: *const Ast, index: u32) []const u8 {
        return self.tokens[index].lexeme(self.source);
    }

    pub fn extraSlice(self: *const Ast, index: u32) []const u32 {
        const count = self.extra_data[index];
        return self.extra_data[index + 1 .. index + 1 + count];
    }

    pub const Node = struct {
        tag: Tag,
        main_token: u32,
        data: Data,

        pub const Data = struct {
            lhs: u32 = 0,
            rhs: u32 = 0,
        };

        pub const Tag = enum(u8) {
            // root node: lhs = extra index -> {count, stmt...}
            root,

            // statements
            expression_stmt, // lhs = expression
            echo_stmt, // main_token = echo, lhs = extra index -> {count, expr...}
            return_stmt, // lhs = expression (0 = bare return)
            break_stmt,
            continue_stmt,
            block, // main_token = {, lhs = extra index -> {count, stmt...}
            if_simple, // lhs = condition, rhs = then body
            if_else, // lhs = condition, rhs = extra index -> {then, else}
            while_stmt, // lhs = condition, rhs = body
            do_while, // lhs = body, rhs = condition
            for_stmt, // lhs = extra index -> {init, cond, update}, rhs = body
            foreach_stmt, // lhs = extra index -> {iter, value, key_or_0}, rhs = body
            function_decl, // main_token = name, lhs = extra index -> {count, param...}, rhs = body
            inline_html, // main_token = inline_html token

            // literals
            integer_literal,
            float_literal,
            string_literal,
            true_literal,
            false_literal,
            null_literal,
            variable,
            identifier,

            // binary (non-short-circuit, main_token = operator)
            binary_op, // lhs = left, rhs = right

            // assignment (main_token = assignment operator)
            assign, // lhs = target, rhs = value

            // unary
            prefix_op, // main_token = operator, lhs = operand
            postfix_op, // main_token = operator, lhs = operand

            // short-circuit (main_token = operator)
            logical_and, // lhs, rhs
            logical_or, // lhs, rhs
            null_coalesce, // lhs, rhs
            ternary, // lhs = condition, rhs = extra index -> {then, else}. then=0 means short ternary

            // postfix expressions
            call, // lhs = callee, rhs = extra index -> {count, arg...}
            array_access, // lhs = array, rhs = index expr
            property_access, // main_token = ->, lhs = object, rhs = property node

            // closures
            closure_expr, // main_token = function, lhs = extra index -> {count, param...}, rhs = extra index -> {body, use_count, use_vars...}

            // compound
            array_literal, // main_token = [, lhs = extra index -> {count, element...}
            array_element, // lhs = value, rhs = key (0 = no key)
            grouped_expr, // lhs = inner expression
        };
    };

    pub const Error = struct {
        token: u32,
        tag: Tag,

        pub const Tag = enum {
            expected_expression,
            expected_semicolon,
            expected_r_paren,
            expected_r_brace,
            expected_r_bracket,
            expected_identifier,
            expected_variable,
            expected_colon,
            unexpected_token,
        };
    };
};
