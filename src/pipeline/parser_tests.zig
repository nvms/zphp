const std = @import("std");
const Ast = @import("ast.zig").Ast;
const parse = @import("parser.zig").parse;

const Allocator = std.mem.Allocator;

const Buf = struct {
    inner: std.ArrayListUnmanaged(u8) = .empty,
    gpa: Allocator,

    fn append(self: *Buf, byte: u8) !void {
        try self.inner.append(self.gpa, byte);
    }

    fn appendSlice(self: *Buf, bytes: []const u8) !void {
        try self.inner.appendSlice(self.gpa, bytes);
    }

    fn print(self: *Buf, comptime fmt: []const u8, args: anytype) !void {
        try self.inner.print(self.gpa, fmt, args);
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
        if (i > 0) try buf.append(' ');
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

// an error php's compiler raises, which the parser notes for it
fn expectCompileError(source: []const u8) !void {
    var ast = try parse(std.testing.allocator, source);
    defer ast.deinit();
    try std.testing.expect(ast.errors.len > 0 or ast.compile_error != null);
}

fn renderNode(ast: *const Ast, idx: u32, buf: *Buf) !void {
    const node = ast.nodes[idx];
    switch (node.tag) {
        .integer_literal, .float_literal, .string_literal, .variable, .identifier => try buf.appendSlice(ast.tokenSlice(node.main_token)),
        .variable_variable => {
            try buf.appendSlice("($$");
            try renderNode(ast, node.data.lhs, buf);
            try buf.append(')');
        },
        .true_literal => try buf.appendSlice("true"),
        .false_literal => try buf.appendSlice("false"),
        .null_literal => try buf.appendSlice("null"),
        .empty_stmt => try buf.appendSlice("(empty)"),
        .expression_stmt => try renderNode(ast, node.data.lhs, buf),
        .echo_stmt => {
            try buf.appendSlice("(echo");
            for (ast.extraSlice(node.data.lhs)) |expr| {
                try buf.append(' ');
                try renderNode(ast, expr, buf);
            }
            try buf.append(')');
        },
        .return_stmt => {
            try buf.appendSlice("(return");
            if (node.data.lhs != 0) {
                try buf.append(' ');
                try renderNode(ast, node.data.lhs, buf);
            }
            try buf.append(')');
        },
        .break_stmt => try buf.appendSlice("(break)"),
        .continue_stmt => try buf.appendSlice("(continue)"),
        .pipe_expr, .binary_op, .logical_and, .logical_or, .null_coalesce => {
            try buf.append('(');
            try buf.appendSlice(ast.tokenSlice(node.main_token));
            try buf.append(' ');
            try renderNode(ast, node.data.lhs, buf);
            try buf.append(' ');
            try renderNode(ast, node.data.rhs, buf);
            try buf.append(')');
        },
        .assign => {
            try buf.append('(');
            try buf.appendSlice(ast.tokenSlice(node.main_token));
            try buf.append(' ');
            try renderNode(ast, node.data.lhs, buf);
            try buf.append(' ');
            try renderNode(ast, node.data.rhs, buf);
            try buf.append(')');
        },
        .prefix_op => {
            try buf.append('(');
            try buf.appendSlice(ast.tokenSlice(node.main_token));
            try renderNode(ast, node.data.lhs, buf);
            try buf.append(')');
        },
        .postfix_op => {
            try buf.append('(');
            try renderNode(ast, node.data.lhs, buf);
            try buf.appendSlice(ast.tokenSlice(node.main_token));
            try buf.append(')');
        },
        .grouped_expr => try renderNode(ast, node.data.lhs, buf),
        .cast_expr => {
            try buf.appendSlice("(cast ");
            try buf.appendSlice(ast.tokenSlice(node.main_token));
            try buf.append(' ');
            try renderNode(ast, node.data.lhs, buf);
            try buf.append(')');
        },
        .closure_expr => {
            try buf.appendSlice("(closure");
            for (ast.extraSlice(node.data.lhs)) |param| {
                try buf.append(' ');
                try renderNode(ast, param, buf);
            }
            try buf.appendSlice(" ...)");
        },
        .call => {
            try buf.appendSlice("(call ");
            try renderNode(ast, node.data.lhs, buf);
            for (ast.extraSlice(node.data.rhs)) |arg| {
                try buf.append(' ');
                try renderNode(ast, arg, buf);
            }
            try buf.append(')');
        },
        .callable_ref => {
            try buf.appendSlice("(callable_ref ");
            try renderNode(ast, node.data.lhs, buf);
            try buf.append(')');
        },
        .array_access => {
            try buf.appendSlice("(idx ");
            try renderNode(ast, node.data.lhs, buf);
            try buf.append(' ');
            try renderNode(ast, node.data.rhs, buf);
            try buf.append(')');
        },
        .array_push_target => {
            try buf.appendSlice("(push ");
            try renderNode(ast, node.data.lhs, buf);
            try buf.append(')');
        },
        .list_destructure => {
            try buf.appendSlice("(list");
            for (ast.extraSlice(node.data.lhs)) |slot| {
                try buf.append(' ');
                if (slot == 0) {
                    try buf.append('_');
                } else {
                    try renderNode(ast, slot, buf);
                }
            }
            try buf.append(')');
        },
        .ref_target => {
            try buf.appendSlice("(ref ");
            try renderNode(ast, node.data.lhs, buf);
            try buf.append(')');
        },
        .named_arg => {
            try buf.appendSlice("(named ");
            try buf.appendSlice(ast.tokenSlice(node.main_token));
            try buf.append(' ');
            try renderNode(ast, node.data.lhs, buf);
            try buf.append(')');
        },
        .property_access, .nullsafe_property_access => {
            try buf.appendSlice(if (node.tag == .nullsafe_property_access) "(?-> " else "(-> ");
            try renderNode(ast, node.data.lhs, buf);
            try buf.append(' ');
            try renderNode(ast, node.data.rhs, buf);
            try buf.append(')');
        },
        .ternary => {
            const then_n = ast.extra_data[node.data.rhs];
            const else_n = ast.extra_data[node.data.rhs + 1];
            try buf.appendSlice("(? ");
            try renderNode(ast, node.data.lhs, buf);
            if (then_n != 0) {
                try buf.append(' ');
                try renderNode(ast, then_n, buf);
            }
            try buf.appendSlice(" : ");
            try renderNode(ast, else_n, buf);
            try buf.append(')');
        },
        .array_literal => {
            try buf.append('[');
            for (ast.extraSlice(node.data.lhs), 0..) |elem, i| {
                if (i > 0) try buf.appendSlice(", ");
                try renderNode(ast, elem, buf);
            }
            try buf.append(']');
        },
        .array_element => {
            if (node.data.rhs != 0) {
                try renderNode(ast, node.data.rhs, buf);
                try buf.appendSlice(" => ");
            }
            try renderNode(ast, node.data.lhs, buf);
        },
        .if_simple => {
            try buf.appendSlice("(if ");
            try renderNode(ast, node.data.lhs, buf);
            try buf.append(' ');
            try renderNode(ast, node.data.rhs, buf);
            try buf.append(')');
        },
        .if_else => {
            try buf.appendSlice("(if ");
            try renderNode(ast, node.data.lhs, buf);
            try buf.append(' ');
            try renderNode(ast, ast.extra_data[node.data.rhs], buf);
            try buf.appendSlice(" else ");
            try renderNode(ast, ast.extra_data[node.data.rhs + 1], buf);
            try buf.append(')');
        },
        .while_stmt => {
            try buf.appendSlice("(while ");
            try renderNode(ast, node.data.lhs, buf);
            try buf.append(' ');
            try renderNode(ast, node.data.rhs, buf);
            try buf.append(')');
        },
        .do_while => {
            try buf.appendSlice("(do ");
            try renderNode(ast, node.data.lhs, buf);
            try buf.appendSlice(" while ");
            try renderNode(ast, node.data.rhs, buf);
            try buf.append(')');
        },
        .for_stmt => try buf.appendSlice("(for)"),
        .foreach_stmt => try buf.appendSlice("(foreach)"),
        .block => {
            try buf.append('{');
            for (ast.extraSlice(node.data.lhs)) |stmt| {
                try buf.append(' ');
                try renderNode(ast, stmt, buf);
            }
            try buf.appendSlice(" }");
        },
        .function_decl => {
            try buf.appendSlice("(fn ");
            try buf.appendSlice(ast.tokenSlice(node.main_token));
            try buf.append('(');
            for (ast.extraSlice(node.data.lhs), 0..) |param, i| {
                if (i > 0) try buf.appendSlice(", ");
                try renderNode(ast, param, buf);
            }
            try buf.appendSlice(") ");
            try renderNode(ast, node.data.rhs, buf);
            try buf.append(')');
        },
        .switch_stmt => {
            try buf.appendSlice("(switch ");
            try renderNode(ast, node.data.lhs, buf);
            for (ast.extraSlice(node.data.rhs)) |c| {
                try buf.append(' ');
                try renderNode(ast, c, buf);
            }
            try buf.append(')');
        },
        .switch_case => {
            try buf.appendSlice("(case");
            for (ast.extraSlice(node.data.lhs)) |v| {
                try buf.append(' ');
                try renderNode(ast, v, buf);
            }
            try buf.appendSlice(": ...");
            try buf.append(')');
        },
        .switch_default => try buf.appendSlice("(default: ...)"),
        .match_expr => {
            try buf.appendSlice("(match ");
            try renderNode(ast, node.data.lhs, buf);
            for (ast.extraSlice(node.data.rhs)) |a| {
                try buf.append(' ');
                try renderNode(ast, a, buf);
            }
            try buf.append(')');
        },
        .match_arm => {
            const vals = ast.extraSlice(node.data.lhs);
            if (vals.len == 0) {
                try buf.appendSlice("(default => ");
            } else {
                try buf.append('(');
                for (vals, 0..) |v, i| {
                    if (i > 0) try buf.appendSlice(", ");
                    try renderNode(ast, v, buf);
                }
                try buf.appendSlice(" => ");
            }
            try renderNode(ast, node.data.rhs, buf);
            try buf.append(')');
        },
        .const_decl => {
            try buf.appendSlice("(const ");
            try buf.appendSlice(ast.tokenSlice(node.main_token));
            try buf.appendSlice(" = ");
            try renderNode(ast, node.data.lhs, buf);
            try buf.append(')');
        },
        .inline_html => try buf.appendSlice("(html)"),
        .throw_expr => {
            try buf.appendSlice("(throw ");
            try renderNode(ast, node.data.lhs, buf);
            try buf.append(')');
        },
        .print_expr => {
            try buf.appendSlice("(print ");
            try renderNode(ast, node.data.lhs, buf);
            try buf.append(')');
        },
        .try_catch => try buf.appendSlice("(try/catch)"),
        .catch_clause => try buf.appendSlice("(catch)"),
        .class_decl => {
            try buf.appendSlice("(class ");
            try buf.appendSlice(ast.tokenSlice(node.main_token));
            try buf.append(')');
        },
        .class_method => {
            try buf.appendSlice("(method ");
            try buf.appendSlice(ast.tokenSlice(node.main_token));
            try buf.append(')');
        },
        .static_class_method => {
            try buf.appendSlice("(static-method ");
            try buf.appendSlice(ast.tokenSlice(node.main_token));
            try buf.append(')');
        },
        .class_property, .class_property_hooks => {
            try buf.appendSlice("(prop ");
            try buf.appendSlice(ast.tokenSlice(node.main_token));
            try buf.append(')');
        },
        .static_class_property => {
            try buf.appendSlice("(static-prop ");
            try buf.appendSlice(ast.tokenSlice(node.main_token));
            try buf.append(')');
        },
        .new_expr => {
            try buf.appendSlice("(new ");
            try buf.appendSlice(ast.tokenSlice(node.main_token));
            for (ast.extraSlice(node.data.lhs)) |arg| {
                try buf.append(' ');
                try renderNode(ast, arg, buf);
            }
            try buf.append(')');
        },
        .new_expr_dynamic => {
            try buf.appendSlice("(new-dynamic ");
            try renderNode(ast, node.data.lhs, buf);
            for (ast.extraSlice(node.data.rhs)) |arg| {
                try buf.append(' ');
                try renderNode(ast, arg, buf);
            }
            try buf.append(')');
        },
        .anonymous_class => try buf.appendSlice("(new-anon-class)"),
        .method_call, .nullsafe_method_call => {
            try buf.appendSlice(if (node.tag == .nullsafe_method_call) "(?-> " else "(-> ");
            try renderNode(ast, node.data.lhs, buf);
            try buf.append(' ');
            try buf.appendSlice(ast.tokenSlice(node.main_token));
            for (ast.extraSlice(node.data.rhs)) |arg| {
                try buf.append(' ');
                try renderNode(ast, arg, buf);
            }
            try buf.append(')');
        },
        .static_call => {
            try buf.appendSlice("(:: ");
            try renderNode(ast, node.data.lhs, buf);
            try buf.append(' ');
            try buf.appendSlice(ast.tokenSlice(node.main_token));
            for (ast.extraSlice(node.data.rhs)) |arg| {
                try buf.append(' ');
                try renderNode(ast, arg, buf);
            }
            try buf.append(')');
        },
        .dynamic_static_call => {
            try buf.appendSlice("(::{} ");
            try renderNode(ast, node.data.lhs, buf);
            const extra = ast.extraSlice(node.data.rhs);
            try buf.append(' ');
            try renderNode(ast, extra[0], buf);
            for (extra[1..]) |arg| {
                try buf.append(' ');
                try renderNode(ast, arg, buf);
            }
            try buf.append(')');
        },
        .clone_with => {
            try buf.appendSlice("(clone-with ");
            try renderNode(ast, node.data.lhs, buf);
            try buf.append(' ');
            try renderNode(ast, node.data.rhs, buf);
            try buf.append(')');
        },
        .dynamic_class_const => {
            try buf.appendSlice("(::{} ");
            try renderNode(ast, node.data.lhs, buf);
            try buf.append(' ');
            try renderNode(ast, node.data.rhs, buf);
            try buf.append(')');
        },
        .static_prop_access => {
            try buf.appendSlice("(::$ ");
            try renderNode(ast, node.data.lhs, buf);
            try buf.append(' ');
            try buf.appendSlice(ast.tokenSlice(node.main_token));
            try buf.append(')');
        },
        .interface_decl => {
            try buf.appendSlice("(interface ");
            try buf.appendSlice(ast.tokenSlice(node.main_token));
            try buf.append(')');
        },
        .interface_method => {
            try buf.appendSlice("(imethod ");
            try buf.appendSlice(ast.tokenSlice(node.main_token));
            try buf.append(')');
        },
        .trait_decl => {
            try buf.appendSlice("(trait ");
            try buf.appendSlice(ast.tokenSlice(node.main_token));
            try buf.append(')');
        },
        .trait_use => try buf.appendSlice("(use-trait)"),
        .trait_insteadof => try buf.appendSlice("(insteadof)"),
        .trait_as => try buf.appendSlice("(as)"),
        .yield_expr => {
            try buf.appendSlice("(yield");
            if (node.data.lhs != 0) {
                try buf.append(' ');
                try renderNode(ast, node.data.lhs, buf);
            }
            try buf.append(')');
        },
        .yield_from_expr => {
            try buf.appendSlice("(yield-from ");
            try renderNode(ast, node.data.lhs, buf);
            try buf.append(')');
        },
        .yield_pair_expr => {
            try buf.appendSlice("(yield ");
            try renderNode(ast, node.data.lhs, buf);
            try buf.appendSlice(" => ");
            try renderNode(ast, node.data.rhs, buf);
            try buf.append(')');
        },
        .expr_list => {
            for (ast.extraSlice(node.data.lhs), 0..) |expr, i| {
                if (i > 0) try buf.appendSlice(", ");
                try renderNode(ast, expr, buf);
            }
        },
        .global_stmt => {
            try buf.appendSlice("(global");
            for (ast.extraSlice(node.data.lhs)) |v| {
                try buf.append(' ');
                try renderNode(ast, v, buf);
            }
            try buf.append(')');
        },
        .static_var => {
            try buf.appendSlice("(static ");
            try buf.appendSlice(ast.tokenSlice(node.main_token));
            if (node.data.lhs != 0) {
                try buf.appendSlice(" = ");
                try renderNode(ast, node.data.lhs, buf);
            }
            try buf.append(')');
        },
        .array_spread, .splat_expr => {
            try buf.appendSlice("(...");
            try renderNode(ast, node.data.lhs, buf);
            try buf.append(')');
        },
        .require_expr => {
            try buf.appendSlice("(");
            try buf.appendSlice(ast.tokenSlice(node.main_token));
            try buf.append(' ');
            try renderNode(ast, node.data.lhs, buf);
            try buf.append(')');
        },
        .namespace_decl => {
            try buf.appendSlice("(namespace ");
            for (ast.extraSlice(node.data.lhs), 0..) |tok_idx, i| {
                if (i > 0) try buf.append('\\');
                try buf.appendSlice(ast.tokenSlice(tok_idx));
            }
            try buf.append(')');
        },
        .use_stmt, .use_fn_stmt, .use_const_stmt => {
            if (node.tag == .use_fn_stmt) try buf.appendSlice("(use function ") else if (node.tag == .use_const_stmt) try buf.appendSlice("(use const ") else try buf.appendSlice("(use ");
            for (ast.extraSlice(node.data.lhs), 0..) |tok_idx, i| {
                if (i > 0) try buf.append('\\');
                try buf.appendSlice(ast.tokenSlice(tok_idx));
            }
            if (node.tag == .use_stmt and node.data.rhs != 0) {
                try buf.appendSlice(" as ");
                try buf.appendSlice(ast.tokenSlice(node.data.rhs));
            }
            try buf.append(')');
        },
        .declare_stmt => {
            try buf.appendSlice("(declare");
            if (node.data.rhs != 0) {
                try buf.append(' ');
                try renderNode(ast, node.data.rhs, buf);
            }
            try buf.append(')');
        },
        .goto_stmt => {
            try buf.appendSlice("(goto ");
            try buf.appendSlice(ast.tokenSlice(node.main_token));
            try buf.append(')');
        },
        .label_stmt => {
            try buf.appendSlice("(label ");
            try buf.appendSlice(ast.tokenSlice(node.main_token));
            try buf.append(')');
        },
        .enum_decl => {
            try buf.appendSlice("(enum ");
            try buf.appendSlice(ast.tokenSlice(node.main_token));
            try buf.append(')');
        },
        .enum_case => {
            try buf.appendSlice("(case ");
            try buf.appendSlice(ast.tokenSlice(node.main_token));
            if (node.data.lhs != 0) {
                try buf.appendSlice(" = ");
                try renderNode(ast, node.data.lhs, buf);
            }
            try buf.append(')');
        },
        .qualified_name => {
            for (ast.extraSlice(node.data.lhs), 0..) |tok_idx, i| {
                if (i > 0) try buf.append('\\');
                try buf.appendSlice(ast.tokenSlice(tok_idx));
            }
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
test "pipe operator" {
    try expectParse("<?php $x |> strlen(...);", "(|> $x (callable_ref strlen))");
}
test "pipe operator chained" {
    try expectParse("<?php $x |> trim(...) |> strtoupper(...);", "(|> (|> $x (callable_ref trim)) (callable_ref strtoupper))");
}
test "pipe precedence vs arithmetic" {
    try expectParse("<?php 5 + 2 |> sqrt(...);", "(|> (+ 5 2) (callable_ref sqrt))");
}
test "pipe precedence vs comparison" {
    try expectParse("<?php $x |> strlen(...) == 4;", "(== (|> $x (callable_ref strlen)) 4)");
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
test "type hint: simple param" {
    try expectParse("<?php function f(int $x) { return $x; }", "(fn f($x) { (return $x) })");
}
test "type hint: keyword type param" {
    try expectParse("<?php function f(array $x) { return $x; }", "(fn f($x) { (return $x) })");
}
test "type hint: nullable param" {
    try expectParse("<?php function f(?string $x) { return $x; }", "(fn f($x) { (return $x) })");
}
test "type hint: union param" {
    try expectParse("<?php function f(int|string $x) { return $x; }", "(fn f($x) { (return $x) })");
}
test "type hint: return type" {
    try expectParse("<?php function f($x): int { return $x; }", "(fn f($x) { (return $x) })");
}
test "type hint: nullable return" {
    try expectParse("<?php function f($x): ?string { return $x; }", "(fn f($x) { (return $x) })");
}
test "type hint: union return" {
    try expectParse("<?php function f($x): int|string { return $x; }", "(fn f($x) { (return $x) })");
}
test "type hint: intersection param" {
    try expectParse("<?php function f(Foo&Bar $x) { return $x; }", "(fn f($x) { (return $x) })");
}
test "type hint: multiple typed params" {
    try expectParse("<?php function f(int $a, string $b) { return $a; }", "(fn f($a, $b) { (return $a) })");
}

// PHP 8.4 asymmetric visibility validation.
test "php84 asymmetric visibility rejects wider set visibility" {
    try expectCompileError("<?php class T { protected public(set) string $x; }");
}

test "php84 asymmetric visibility requires typed property" {
    try expectCompileError("<?php class T { public private(set) $x; }");
}

test "php85 asymmetric visibility on static properties" {
    try expectNoErrors("<?php class T { public private(set) static string $x; protected(set) static ?int $y = null; }");
    try expectNoErrors("<?php trait T { public private(set) static string $x; }");
    // still needs a type, and set visibility no wider than read visibility
    try expectCompileError("<?php class T { public private(set) static $x; }");
    try expectCompileError("<?php class T { protected public(set) static int $x; }");
}

test "php84 trait asymmetric visibility validation" {
    try expectError("<?php trait T { protected public(set) string $x; }");
    try expectError("<?php trait T { public private(set) $x; }");
}

test "php85 final promoted properties" {
    try expectNoErrors("<?php class T { function __construct(final public int $a, final int $b, public final readonly int $c, final private(set) int $d) {} }");
}

test "php84 promoted asymmetric visibility validation" {
    try expectError("<?php class T { function __construct(protected public(set) string $x) {} }");
    try expectError("<?php class T { function __construct(public private(set) $x) {} }");
}

test "php84 abbreviated promoted asymmetric visibility parses" {
    var ast = try parse(std.testing.allocator, "<?php class T { function __construct(private(set) string $x) {} }");
    defer ast.deinit();
    try std.testing.expectEqual(@as(usize, 0), ast.errors.len);
}

test "property hook generator flags are scoped independently" {
    var ast = try parse(std.testing.allocator,
        \\<?php function factory() {
        \\    class Sequence {
        \\        public $block { get { yield 1; } set { echo $value; } }
        \\        public $short { get => yield 2; }
        \\        public $closure { get => function () { yield 3; }; }
        \\    }
        \\    return new Sequence();
        \\}
    );
    defer ast.deinit();
    try std.testing.expectEqual(@as(usize, 0), ast.errors.len);
    var hooks: usize = 0;
    for (ast.nodes) |node| {
        if (node.tag == .function_decl) {
            try std.testing.expectEqual(@as(u32, 0), node.data.rhs & 0x80000000);
        }
        if (node.tag != .class_property_hooks) continue;
        const expected: u32 = switch (hooks) {
            0 => 2, // block generator
            1 => 3, // short generator
            2 => 1, // nested generator does not mark the hook
            else => unreachable,
        };
        try std.testing.expectEqual(expected, ast.extra_data[node.data.lhs + 4]);
        try std.testing.expectEqual(@as(u32, 0), ast.extra_data[node.data.lhs + 5]);
        hooks += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), hooks);
}

test "property hook abstract final reference and setter type metadata" {
    var ast = try parse(std.testing.allocator,
        \\<?php
        \\abstract class HookFlags {
        \\    abstract public string $name { get; set(string $input); }
        \\    public array $items { final &get => $this->items; }
        \\}
    );
    defer ast.deinit();
    try std.testing.expectEqual(@as(usize, 0), ast.errors.len);
    var count: usize = 0;
    for (ast.nodes) |node| {
        if (node.tag != .class_property_hooks) continue;
        const ext = node.data.lhs;
        if (count == 0) {
            try std.testing.expectEqual(@as(u32, 8), ast.extra_data[ext + 4]);
            try std.testing.expectEqual(@as(u32, 8), ast.extra_data[ext + 5]);
            try std.testing.expectEqualStrings("$input", ast.tokenSlice(ast.extra_data[ext + 3]));
            try std.testing.expectEqualStrings("string", ast.tokenSlice(ast.extra_data[ext + 6]));
            try std.testing.expectEqual(ast.extra_data[ext + 6] + 1, ast.extra_data[ext + 7]);
        } else {
            try std.testing.expectEqual(@as(u32, 53), ast.extra_data[ext + 4]);
        }
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
}

test "duplicate read and set visibility modifiers are rejected in all property contexts" {
    try expectCompileError("<?php class T { private(set) protected(set) int $x; }");
    try expectCompileError("<?php trait T { private(set) private(set) int $x; }");
    try expectCompileError("<?php $x = new class { public public int $x; };");
    try expectCompileError("<?php class T { function __construct(public private(set) protected(set) int $x) {} }");
    try expectCompileError("<?php class T { function __construct(public public int $x) {} }");
}

fn expectErrorTag(source: []const u8, tag: Ast.Error.Tag) !void {
    var ast = try parse(std.testing.allocator, source);
    defer ast.deinit();
    try std.testing.expect(ast.errors.len > 0);
    try std.testing.expectEqual(tag, ast.errors[0].tag);
}

fn expectNoErrors(source: []const u8) !void {
    var ast = try parse(std.testing.allocator, source);
    defer ast.deinit();
    try std.testing.expectEqual(@as(usize, 0), ast.errors.len);
}

test "cast names ignore case" {
    try expectNoErrors("<?php $a = (INT) $x . (Bool) $y . ( string ) $z . (BINARY) $w . (Array) $v;");
}

test "real cast is removed" {
    try expectErrorTag("<?php $a = (real) 1;", .real_cast_removed);
    try expectErrorTag("<?php $a = (REAL) 1;", .real_cast_removed);
}

test "void cast only where the value is discarded" {
    try expectNoErrors("<?php (void) f(); (VOID) $o->m(); for ((void) f(), $i = 0; $i < 3; (void) $i++) {}");
    try expectErrorTag("<?php $x = (void) f();", .void_cast_misplaced);
    try expectErrorTag("<?php echo (void) 1;", .void_cast_misplaced);
    try expectErrorTag("<?php f((void) 1);", .void_cast_misplaced);
    try expectErrorTag("<?php for (; (void) f(); ) {}", .void_cast_misplaced);
}

test "switch cases may end with a semicolon" {
    try expectNoErrors("<?php switch ($x) {; case 1; break; case 2: case 3; default; }");
    try expectNoErrors("<?php switch ($x): ; case 1; default: endswitch;");
}

test "php85 clone with an argument list" {
    try expectNoErrors("<?php $a = clone($o); $b = clone($o, ['x' => 1]); $c = clone($o, $props,); $d = clone $o;");
    var ast = try parse(std.testing.allocator, "<?php clone($o, $p);");
    defer ast.deinit();
    var found = false;
    for (ast.nodes) |node| {
        if (node.tag == .clone_with) found = true;
    }
    try std.testing.expect(found);
}
