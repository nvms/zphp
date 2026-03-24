const std = @import("std");
const Ast = @import("ast.zig").Ast;
const parse = @import("parser.zig").parse;

const Allocator = std.mem.Allocator;

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
        .array_push_target => {
            try w.writeAll("(push ");
            try renderNode(ast, node.data.lhs, buf);
            try w.writeByte(')');
        },
        .list_destructure => {
            try w.writeAll("(list");
            for (ast.extraSlice(node.data.lhs)) |slot| {
                try w.writeByte(' ');
                if (slot == 0) {
                    try w.writeByte('_');
                } else {
                    try renderNode(ast, slot, buf);
                }
            }
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
        .for_stmt => try w.writeAll("(for)"),
        .foreach_stmt => try w.writeAll("(foreach)"),
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
        .throw_expr => {
            try w.writeAll("(throw ");
            try renderNode(ast, node.data.lhs, buf);
            try w.writeByte(')');
        },
        .try_catch => try w.writeAll("(try/catch)"),
        .catch_clause => try w.writeAll("(catch)"),
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
        .static_class_method => {
            try w.writeAll("(static-method ");
            try w.writeAll(ast.tokenSlice(node.main_token));
            try w.writeByte(')');
        },
        .class_property => {
            try w.writeAll("(prop ");
            try w.writeAll(ast.tokenSlice(node.main_token));
            try w.writeByte(')');
        },
        .static_class_property => {
            try w.writeAll("(static-prop ");
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
        .static_prop_access => {
            try w.writeAll("(::$ ");
            try renderNode(ast, node.data.lhs, buf);
            try w.writeByte(' ');
            try w.writeAll(ast.tokenSlice(node.main_token));
            try w.writeByte(')');
        },
        .interface_decl => {
            try w.writeAll("(interface ");
            try w.writeAll(ast.tokenSlice(node.main_token));
            try w.writeByte(')');
        },
        .interface_method => {
            try w.writeAll("(imethod ");
            try w.writeAll(ast.tokenSlice(node.main_token));
            try w.writeByte(')');
        },
        .trait_decl => {
            try w.writeAll("(trait ");
            try w.writeAll(ast.tokenSlice(node.main_token));
            try w.writeByte(')');
        },
        .trait_use => try w.writeAll("(use-trait)"),
        .yield_expr => {
            try w.writeAll("(yield");
            if (node.data.lhs != 0) {
                try w.writeByte(' ');
                try renderNode(ast, node.data.lhs, buf);
            }
            try w.writeByte(')');
        },
        .yield_from_expr => {
            try w.writeAll("(yield-from ");
            try renderNode(ast, node.data.lhs, buf);
            try w.writeByte(')');
        },
        .yield_pair_expr => {
            try w.writeAll("(yield ");
            try renderNode(ast, node.data.lhs, buf);
            try w.writeAll(" => ");
            try renderNode(ast, node.data.rhs, buf);
            try w.writeByte(')');
        },
        .expr_list => {
            for (ast.extraSlice(node.data.lhs), 0..) |expr, i| {
                if (i > 0) try w.writeAll(", ");
                try renderNode(ast, expr, buf);
            }
        },
        .global_stmt => {
            try w.writeAll("(global");
            for (ast.extraSlice(node.data.lhs)) |v| {
                try w.writeByte(' ');
                try renderNode(ast, v, buf);
            }
            try w.writeByte(')');
        },
        .static_var => {
            try w.writeAll("(static ");
            try w.writeAll(ast.tokenSlice(node.main_token));
            if (node.data.lhs != 0) {
                try w.writeAll(" = ");
                try renderNode(ast, node.data.lhs, buf);
            }
            try w.writeByte(')');
        },
        .array_spread, .splat_expr => {
            try w.writeAll("(...");
            try renderNode(ast, node.data.lhs, buf);
            try w.writeByte(')');
        },
        .require_expr => {
            try w.writeAll("(");
            try w.writeAll(ast.tokenSlice(node.main_token));
            try w.writeByte(' ');
            try renderNode(ast, node.data.lhs, buf);
            try w.writeByte(')');
        },
        .namespace_decl => {
            try w.writeAll("(namespace ");
            for (ast.extraSlice(node.data.lhs), 0..) |tok_idx, i| {
                if (i > 0) try w.writeByte('\\');
                try w.writeAll(ast.tokenSlice(tok_idx));
            }
            try w.writeByte(')');
        },
        .use_stmt => {
            try w.writeAll("(use ");
            for (ast.extraSlice(node.data.lhs), 0..) |tok_idx, i| {
                if (i > 0) try w.writeByte('\\');
                try w.writeAll(ast.tokenSlice(tok_idx));
            }
            if (node.data.rhs != 0) {
                try w.writeAll(" as ");
                try w.writeAll(ast.tokenSlice(node.data.rhs));
            }
            try w.writeByte(')');
        },
        .enum_decl => {
            try w.writeAll("(enum ");
            try w.writeAll(ast.tokenSlice(node.main_token));
            try w.writeByte(')');
        },
        .enum_case => {
            try w.writeAll("(case ");
            try w.writeAll(ast.tokenSlice(node.main_token));
            if (node.data.lhs != 0) {
                try w.writeAll(" = ");
                try renderNode(ast, node.data.lhs, buf);
            }
            try w.writeByte(')');
        },
        .qualified_name => {
            for (ast.extraSlice(node.data.lhs), 0..) |tok_idx, i| {
                if (i > 0) try w.writeByte('\\');
                try w.writeAll(ast.tokenSlice(tok_idx));
            }
        },
        .root => {},
    }
}

// ==========================================================================
// tests
// ==========================================================================

test "integer literal" { try expectParse("<?php 42;", "42"); }
test "float literal" { try expectParse("<?php 3.14;", "3.14"); }
test "string literal" { try expectParse("<?php \"hello\";", "\"hello\""); }
test "boolean and null literals" {
    try expectParse("<?php true;", "true");
    try expectParse("<?php false;", "false");
    try expectParse("<?php null;", "null");
}
test "variable" { try expectParse("<?php $x;", "$x"); }
test "binary addition" { try expectParse("<?php 1 + 2;", "(+ 1 2)"); }
test "binary precedence: add vs mul" { try expectParse("<?php 1 + 2 * 3;", "(+ 1 (* 2 3))"); }
test "binary precedence: mul vs add" { try expectParse("<?php 1 * 2 + 3;", "(+ (* 1 2) 3)"); }
test "left associativity" { try expectParse("<?php 1 + 2 + 3;", "(+ (+ 1 2) 3)"); }
test "right associativity: power" { try expectParse("<?php 2 ** 3 ** 4;", "(** 2 (** 3 4))"); }
test "parenthesized expression" { try expectParse("<?php (1 + 2) * 3;", "(* (+ 1 2) 3)"); }
test "assignment" { try expectParse("<?php $x = 42;", "(= $x 42)"); }
test "compound assignment" { try expectParse("<?php $x += 1;", "(+= $x 1)"); }
test "right-associative assignment" { try expectParse("<?php $a = $b = $c;", "(= $a (= $b $c))"); }
test "prefix negation" { try expectParse("<?php -$x;", "(-$x)"); }
test "prefix not" { try expectParse("<?php !$x;", "(!$x)"); }
test "postfix increment" { try expectParse("<?php $x++;", "($x++)"); }
test "prefix and postfix" { try expectParse("<?php -$x++;", "(-($x++))"); }
test "echo statement" { try expectParse("<?php echo \"hello\";", "(echo \"hello\")"); }
test "echo multiple" { try expectParse("<?php echo $a, $b;", "(echo $a $b)"); }
test "return statement" { try expectParse("<?php return 42;", "(return 42)"); }
test "bare return" { try expectParse("<?php return;", "(return)"); }
test "if simple" { try expectParse("<?php if ($x) $y;", "(if $x $y)"); }
test "if with block" { try expectParse("<?php if ($x) { $y; }", "(if $x { $y })"); }
test "if else" { try expectParse("<?php if ($x) { $a; } else { $b; }", "(if $x { $a } else { $b })"); }
test "while loop" { try expectParse("<?php while ($x) $y;", "(while $x $y)"); }
test "do while" { try expectParse("<?php do { $x; } while ($y);", "(do { $x } while $y)"); }
test "for loop" { try expectParse("<?php for ($i = 0; $i < 10; $i++) $x;", "(for)"); }
test "function declaration" {
    try expectParse(
        "<?php function add($a, $b) { return $a + $b; }",
        "(fn add($a, $b) { (return (+ $a $b)) })",
    );
}
test "function call" { try expectParse("<?php foo();", "(call foo)"); }
test "function call with args" { try expectParse("<?php foo($a, $b);", "(call foo $a $b)"); }
test "nested calls" { try expectParse("<?php foo(bar($x));", "(call foo (call bar $x))"); }
test "array access" { try expectParse("<?php $a[0];", "(idx $a 0)"); }
test "property access" { try expectParse("<?php $a->b;", "(-> $a b)"); }
test "method call" { try expectParse("<?php $a->b();", "(-> $a b)"); }
test "chained access" { try expectParse("<?php $a->b->c;", "(-> (-> $a b) c)"); }
test "ternary" { try expectParse("<?php $a ? $b : $c;", "(? $a $b : $c)"); }
test "short ternary" { try expectParse("<?php $a ?: $b;", "(? $a : $b)"); }
test "null coalesce" { try expectParse("<?php $a ?? $b;", "(?? $a $b)"); }
test "logical and/or" { try expectParse("<?php $a && $b || $c;", "(|| (&& $a $b) $c)"); }
test "comparison" {
    try expectParse("<?php $a == $b;", "(== $a $b)");
    try expectParse("<?php $a === $b;", "(=== $a $b)");
    try expectParse("<?php $a <=> $b;", "(<=> $a $b)");
}
test "string concat" { try expectParse("<?php $a . $b . $c;", "(. (. $a $b) $c)"); }
test "array literal" { try expectParse("<?php [1, 2, 3];", "[1, 2, 3]"); }
test "array with keys" { try expectParse("<?php ['a' => 1, 'b' => 2];", "['a' => 1, 'b' => 2]"); }
test "empty array" { try expectParse("<?php [];", "[]"); }
test "break and continue" { try expectParse("<?php while(1) { break; continue; }", "(while 1 { (break) (continue) })"); }
test "mixed html and php" { try expectParse("<h1>Hi</h1><?php echo $x;", "(html) (echo $x)"); }
test "multiple php blocks" { try expectParse("A<?php $a; ?>B<?= $b ?>C", "(html) $a (html) (echo $b) (html)"); }
test "complex precedence" { try expectParse("<?php $a = $b + $c * $d;", "(= $a (+ $b (* $c $d)))"); }
test "instanceof" { try expectParse("<?php $a instanceof Foo;", "(instanceof $a Foo)"); }
test "parse error recovery" { try expectError("<?php $x = ;"); }
test "multiple statements" { try expectParse("<?php $a = 1; $b = 2;", "(= $a 1) (= $b 2)"); }
test "type hint: simple param" { try expectParse("<?php function f(int $x) { return $x; }", "(fn f($x) { (return $x) })"); }
test "type hint: keyword type param" { try expectParse("<?php function f(array $x) { return $x; }", "(fn f($x) { (return $x) })"); }
test "type hint: nullable param" { try expectParse("<?php function f(?string $x) { return $x; }", "(fn f($x) { (return $x) })"); }
test "type hint: union param" { try expectParse("<?php function f(int|string $x) { return $x; }", "(fn f($x) { (return $x) })"); }
test "type hint: return type" { try expectParse("<?php function f($x): int { return $x; }", "(fn f($x) { (return $x) })"); }
test "type hint: nullable return" { try expectParse("<?php function f($x): ?string { return $x; }", "(fn f($x) { (return $x) })"); }
test "type hint: union return" { try expectParse("<?php function f($x): int|string { return $x; }", "(fn f($x) { (return $x) })"); }
test "type hint: intersection param" { try expectParse("<?php function f(Foo&Bar $x) { return $x; }", "(fn f($x) { (return $x) })"); }
test "type hint: multiple typed params" { try expectParse("<?php function f(int $a, string $b) { return $a; }", "(fn f($a, $b) { (return $a) })"); }
