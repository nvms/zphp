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
            const_decl, // main_token = identifier, lhs = value expression
            switch_stmt, // main_token = switch, lhs = condition, rhs = extra index -> {count, case/default nodes...}
            switch_case, // main_token = case, lhs = extra index -> {count, value_expr...}, rhs = extra index -> {count, stmt...}
            switch_default, // main_token = default, lhs = extra index -> {count, stmt...}
            match_expr, // main_token = match, lhs = condition, rhs = extra index -> {count, arm_nodes...}
            match_arm, // lhs = extra index -> {count, value_expr...}, rhs = result expr. count=0 means default
            inline_html, // main_token = inline_html token

            // literals
            integer_literal,
            float_literal,
            string_literal,
            true_literal,
            false_literal,
            null_literal,
            variable,
            variable_variable, // lhs = inner expression ($$var, ${expr})
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
            array_push_target, // lhs = array ($arr[] push target)
            list_destructure, // lhs = extra index -> {count, variable_nodes...} (0 = skip)
            named_arg, // main_token = name identifier, lhs = value expression
            property_access, // main_token = ->, lhs = object, rhs = property node
            nullsafe_property_access, // main_token = ?->, lhs = object, rhs = property node
            nullsafe_method_call, // main_token = method name, lhs = object, rhs = extra index -> {count, arg...}

            // casts
            cast_expr, // main_token = type identifier (int/string/etc), lhs = operand

            // closures
            closure_expr, // main_token = function, lhs = extra index -> {count, param...}, rhs = extra index -> {body, use_count, use_vars...}

            // exceptions
            throw_expr, // lhs = expression to throw
            try_catch, // lhs = try body, rhs = extra index -> {catch_count, catch_nodes..., finally_node_or_0}
            catch_clause, // main_token = variable, lhs = type name node (0 = catch all), rhs = body block

            // classes
            class_decl, // main_token = class name, lhs = extra index -> {count, member_nodes...}, rhs = extra index -> {parent_node, implements_count, implements_nodes...}
            class_method, // main_token = method name, lhs = extra index -> {count, param...}, rhs = body block
            class_property, // main_token = property variable, lhs = default value (0 = none)
            static_class_method, // same as class_method but static
            static_class_property, // same as class_property but static
            interface_decl, // main_token = interface name, lhs = extra index -> {count, method_nodes...}, rhs = parent interface node (0 = none)
            interface_method, // main_token = method name, lhs = extra index -> {count, param...}
            trait_decl, // main_token = trait name, lhs = extra index -> {count, member_nodes...}
            trait_use, // main_token = use keyword, lhs = extra index -> {count, trait_name_nodes...}, rhs = extra index -> {count, conflict_nodes...} (0 = none)
            trait_insteadof, // main_token = method name, lhs = trait name node, rhs = extra index -> {count, excluded_trait_nodes...}
            trait_as, // main_token = method name, lhs = trait name node, rhs = alias token index (identifier or visibility keyword)
            new_expr, // main_token = class name, lhs = extra index -> {count, arg...}
            new_expr_dynamic, // lhs = class name expression, rhs = extra index -> {count, arg...}
            anonymous_class, // main_token = new, lhs = extra (members), rhs = extra {ctor_arg_count, ctor_args..., parent, impl_count, impls...}
            method_call, // main_token = method name, lhs = object, rhs = extra index -> {count, arg...}
            static_call, // main_token = method name, lhs = class name node, rhs = extra index -> {count, arg...}
            dynamic_static_call, // main_token = 0, lhs = class name node, rhs = extra index -> {method_expr, count, arg...}
            static_prop_access, // main_token = $variable, lhs = class name node

            // compound
            array_literal, // main_token = [, lhs = extra index -> {count, element...}
            array_element, // lhs = value, rhs = key (0 = no key)
            array_spread, // lhs = expression to spread
            grouped_expr, // lhs = inner expression

            // multi-expression (for loop init/update)
            expr_list, // lhs = extra index -> {count, expr...}

            // scope
            global_stmt, // lhs = extra index -> {count, variable_nodes...}
            static_var, // main_token = variable, lhs = default expression (0 = none)

            // generators
            yield_expr, // lhs = value expression (0 = yield null)
            yield_pair_expr, // lhs = key expression, rhs = value expression
            yield_from_expr, // lhs = iterable expression

            // variadic
            splat_expr, // lhs = expression to spread (used in function call args)

            // first-class callable
            callable_ref, // lhs = callee expression (function name identifier node)

            // file inclusion
            // main_token = require/require_once/include/include_once keyword
            // lhs = path expression
            require_expr,

            // enums
            enum_decl, // main_token = enum name, lhs = extra index -> {count, member_nodes...}, rhs = extra index -> {backed_type_token_or_0, implements_count, impl_nodes...}
            enum_case, // main_token = case name, lhs = backing value expression (0 = none)

            // namespaces
            namespace_decl, // main_token = namespace keyword, lhs = extra index -> {count, name_token_indices...}
            use_stmt, // main_token = use keyword, lhs = extra index -> {count, name_token_indices...}, rhs = alias token (0 = no alias)
            use_fn_stmt, // same layout as use_stmt but for 'use function'
            goto_stmt, // main_token = label identifier
            label_stmt, // main_token = label identifier
            qualified_name, // main_token = first identifier, lhs = extra index -> {count, token_indices...} for multi-part names
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
