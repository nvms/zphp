// php's zend_ast_export (Zend/zend_ast.c): prints an expression back as php
// source, the text assert() reports as its default message. php prints its
// own ast; this walks zphp's, which keeps less (grouping parentheses, the
// spelling of some names), and reads the tokens where the nodes don't say
const std = @import("std");
const AstMod = @import("ast.zig");
const Ast = AstMod.Ast;
const Token = @import("token.zig").Token;
const parser = @import("parser.zig");
const strings = @import("compiler_strings.zig");
const Compiler = @import("compiler.zig").Compiler;
const gcvt = @import("../stdlib/formatted_print.zig").gcvt;

const Allocator = std.mem.Allocator;
const Error = Allocator.Error;
const Node = Ast.Node;
const Tag = Token.Tag;

// "assert(<expr>)", allocated
pub fn assertMessage(allocator: Allocator, ast: *const Ast, node: u32) Error![]u8 {
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(allocator);
    var e = Exporter{ .ast = ast, .out = &out, .allocator = allocator };
    try e.str("assert(");
    try e.expr(node, 0, 0);
    try e.str(")");
    return out.toOwnedSlice(allocator);
}

const Exporter = struct {
    ast: *const Ast,
    out: *std.ArrayListUnmanaged(u8),
    allocator: Allocator,

    fn str(e: *Exporter, s: []const u8) Error!void {
        try e.out.appendSlice(e.allocator, s);
    }

    fn char(e: *Exporter, c: u8) Error!void {
        try e.out.append(e.allocator, c);
    }

    fn tok(e: *Exporter, t: u32) []const u8 {
        return e.ast.tokenSlice(t);
    }

    fn tokTag(e: *Exporter, t: u32) Tag {
        return e.ast.tokens[t].tag;
    }

    fn node(e: *Exporter, i: u32) Node {
        return e.ast.nodes[i];
    }

    fn indentBy(e: *Exporter, indent: u32) Error!void {
        var i: u32 = 0;
        while (i < indent) : (i += 1) try e.str("    ");
    }

    // zend_ast_export_str: inside single quotes
    fn singleQuoted(e: *Exporter, s: []const u8) Error!void {
        for (s) |c| {
            if (c == '\'' or c == '\\') try e.char('\\');
            try e.char(c);
        }
    }

    // zend_ast_export_qstr
    fn qstr(e: *Exporter, quote: u8, s: []const u8) Error!void {
        for (s) |c| {
            if (c < ' ') {
                switch (c) {
                    '\n' => try e.str("\\n"),
                    '\r' => try e.str("\\r"),
                    '\t' => try e.str("\\t"),
                    0x0c => try e.str("\\f"),
                    0x0b => try e.str("\\v"),
                    0x1b => try e.str("\\e"),
                    else => {
                        try e.str("\\0");
                        try e.char('0' + c / 8);
                        try e.char('0' + c % 8);
                    },
                }
            } else {
                if (c == quote or c == '$' or c == '\\') try e.char('\\');
                try e.char(c);
            }
        }
    }

    // zend_ast_export_quoted_str
    fn quotedString(e: *Exporter, s: []const u8) Error!void {
        for (s) |c| {
            if (c < ' ') {
                try e.char('"');
                try e.qstr('"', s);
                try e.char('"');
                return;
            }
        }
        try e.char('\'');
        try e.singleQuoted(s);
        try e.char('\'');
    }

    fn double(e: *Exporter, v: f64) Error!void {
        var buf: [64]u8 = undefined;
        const text = gcvt(v, 14, '.', 'E', &buf);
        try e.str(text);
        if (std.math.isFinite(v) and std.mem.indexOfScalar(u8, text, '.') == null) try e.str(".0");
    }

    fn validVarName(s: []const u8) bool {
        if (s.len == 0) return false;
        const c0 = s[0];
        if (c0 != '_' and c0 < 127 and !std.ascii.isAlphabetic(c0)) return false;
        for (s[1..]) |c| {
            if (c != '_' and c < 127 and !std.ascii.isAlphanumeric(c)) return false;
        }
        return true;
    }

    fn isVarChar(c: u8) bool {
        return c == '_' or c >= 127 or std.ascii.isAlphanumeric(c);
    }

    // the string a literal node holds, when it is a plain one
    fn literalString(e: *Exporter, n: Node) Error!?[]const u8 {
        if (n.tag != .string_literal) return null;
        const t = e.tokTag(n.main_token);
        const lexeme = e.tok(n.main_token);
        if (t == .nowdoc) return try heredocBody(e.allocator, lexeme);
        if (t == .heredoc) {
            const body = try heredocBody(e.allocator, lexeme);
            defer e.allocator.free(body);
            if (hasInterpolation(body)) return null;
            return try strings.processEscapes(e.allocator, body, 0);
        }
        if (lexeme.len < 2) return try e.allocator.dupe(u8, lexeme);
        const inner = lexeme[1 .. lexeme.len - 1];
        switch (lexeme[0]) {
            '\'' => return (try strings.processSingleQuoteEscapes(e.allocator, inner)) orelse try e.allocator.dupe(u8, inner),
            '"' => {
                if (hasInterpolation(inner)) return null;
                return try strings.processEscapes(e.allocator, inner, '"');
            },
            else => return null,
        }
    }

    // zend_ast_export_var: a member or variable name
    fn varName(e: *Exporter, i: u32, indent: u32) Error!void {
        const n = e.node(i);
        switch (n.tag) {
            .identifier => return e.str(e.tok(n.main_token)),
            .variable => return e.expr(i, 0, indent),
            .variable_variable => return e.expr(i, 0, indent),
            .string_literal => if (try e.literalString(n)) |s| {
                defer e.allocator.free(s);
                if (validVarName(s)) return e.str(s);
            },
            else => {},
        }
        try e.char('{');
        try e.name(i, indent);
        try e.char('}');
    }

    // zend_ast_export_name: a string printed bare, anything else as itself
    fn name(e: *Exporter, i: u32, indent: u32) Error!void {
        const n = e.node(i);
        if (n.tag == .string_literal) {
            if (try e.literalString(n)) |s| {
                defer e.allocator.free(s);
                return e.str(s);
            }
        }
        if (n.tag == .grouped_expr) return e.name(n.data.lhs, indent);
        try e.expr(i, 0, indent);
    }

    // zend_ast_export_ns_name
    fn nsName(e: *Exporter, i: u32, indent: u32) Error!void {
        const n = e.node(i);
        switch (n.tag) {
            .identifier => {
                const t = e.tokTag(n.main_token);
                if (t == .kw_exit or t == .kw_die) return e.str("\\exit");
                if (t == .kw_clone) return e.str("\\clone");
                return e.str(e.tok(n.main_token));
            },
            .qualified_name => return e.qualified(n),
            else => return e.expr(i, 0, indent),
        }
    }

    fn qualified(e: *Exporter, n: Node) Error!void {
        if (n.data.rhs == 1) try e.char('\\');
        if (n.data.rhs == 2) try e.str("namespace\\");
        for (e.ast.extraSlice(n.data.lhs), 0..) |part, k| {
            if (k > 0) try e.char('\\');
            try e.str(e.tok(part));
        }
    }

    fn list(e: *Exporter, items: []const u32, priority: u32, indent: u32) Error!void {
        for (items, 0..) |item, k| {
            if (k > 0) try e.str(", ");
            if (item != 0) try e.expr(item, priority, indent);
        }
    }

    fn binary(e: *Exporter, n: Node, op: []const u8, priority: u32, p: u32, pl: u32, pr: u32, indent: u32) Error!void {
        if (priority > p) try e.char('(');
        try e.expr(n.data.lhs, pl, indent);
        try e.str(op);
        try e.expr(n.data.rhs, pr, indent);
        if (priority > p) try e.char(')');
    }

    fn prefix(e: *Exporter, operand: u32, op: []const u8, priority: u32, p: u32, pl: u32, indent: u32) Error!void {
        if (priority > p) try e.char('(');
        try e.str(op);
        try e.expr(operand, pl, indent);
        if (priority > p) try e.char(')');
    }

    fn binaryOp(e: *Exporter, n: Node, priority: u32, indent: u32) Error!void {
        const t = e.tokTag(n.main_token);
        switch (t) {
            .plus => return e.binary(n, " + ", priority, 200, 200, 201, indent),
            .minus => return e.binary(n, " - ", priority, 200, 200, 201, indent),
            .star => return e.binary(n, " * ", priority, 210, 210, 211, indent),
            .slash => return e.binary(n, " / ", priority, 210, 210, 211, indent),
            .percent => return e.binary(n, " % ", priority, 210, 210, 211, indent),
            .lt_lt => return e.binary(n, " << ", priority, 190, 190, 191, indent),
            .gt_gt => return e.binary(n, " >> ", priority, 190, 190, 191, indent),
            .dot => return e.binary(n, " . ", priority, 185, 185, 186, indent),
            .pipe => return e.binary(n, " | ", priority, 140, 140, 141, indent),
            .amp => return e.binary(n, " & ", priority, 160, 160, 161, indent),
            .caret => return e.binary(n, " ^ ", priority, 150, 150, 151, indent),
            .equal_equal_equal => return e.binary(n, " === ", priority, 170, 171, 171, indent),
            .bang_equal_equal => return e.binary(n, " !== ", priority, 170, 171, 171, indent),
            .equal_equal => return e.binary(n, " == ", priority, 170, 171, 171, indent),
            .bang_equal, .lt_gt => return e.binary(n, " != ", priority, 170, 171, 171, indent),
            .lt => return e.binary(n, " < ", priority, 180, 181, 181, indent),
            .lt_equal => return e.binary(n, " <= ", priority, 180, 181, 181, indent),
            .gt => return e.binary(n, " > ", priority, 180, 181, 181, indent),
            .gt_equal => return e.binary(n, " >= ", priority, 180, 181, 181, indent),
            .star_star => return e.binary(n, " ** ", priority, 250, 251, 250, indent),
            .kw_xor => return e.binary(n, " xor ", priority, 40, 40, 41, indent),
            .spaceship => return e.binary(n, " <=> ", priority, 180, 181, 181, indent),
            .kw_instanceof => {
                try e.expr(n.data.lhs, 0, indent);
                try e.str(" instanceof ");
                return e.nsName(n.data.rhs, indent);
            },
            else => return e.binary(n, e.tok(n.main_token), priority, 0, 0, 0, indent),
        }
    }

    fn assign(e: *Exporter, n: Node, priority: u32, indent: u32) Error!void {
        const op: []const u8 = switch (e.tokTag(n.main_token)) {
            .equal => blk: {
                const rhs = e.node(n.data.rhs);
                if (rhs.tag == .ref_target) {
                    if (priority > 90) try e.char('(');
                    try e.expr(n.data.lhs, 91, indent);
                    try e.str(" =& ");
                    try e.expr(rhs.data.lhs, 90, indent);
                    if (priority > 90) try e.char(')');
                    return;
                }
                break :blk " = ";
            },
            .plus_equal => " += ",
            .minus_equal => " -= ",
            .star_equal => " *= ",
            .slash_equal => " /= ",
            .percent_equal => " %= ",
            .lt_lt_equal => " <<= ",
            .gt_gt_equal => " >>= ",
            .dot_equal => " .= ",
            .pipe_equal => " |= ",
            .amp_equal => " &= ",
            .caret_equal => " ^= ",
            .star_star_equal => " **= ",
            .question_question_equal => " ??= ",
            else => " = ",
        };
        return e.binary(n, op, priority, 90, 91, 90, indent);
    }

    fn castName(text: []const u8) ?[]const u8 {
        const map = [_][2][]const u8{
            .{ "int", "(int)" },      .{ "integer", "(int)" },   .{ "bool", "(bool)" },
            .{ "boolean", "(bool)" }, .{ "float", "(float)" },   .{ "double", "(float)" },
            .{ "real", "(float)" },   .{ "string", "(string)" }, .{ "binary", "(string)" },
            .{ "array", "(array)" },  .{ "object", "(object)" }, .{ "unset", "(unset)" },
            .{ "void", "(void)" },
        };
        for (map) |entry| {
            if (std.ascii.eqlIgnoreCase(text, entry[0])) return entry[1];
        }
        return null;
    }

    fn args(e: *Exporter, extra: u32, indent: u32) Error!void {
        try e.list(e.ast.extraSlice(extra), 0, indent);
    }

    fn call(e: *Exporter, n: Node, priority: u32, indent: u32) Error!void {
        const callee = e.node(n.data.lhs);
        const arg_list = e.ast.extraSlice(n.data.rhs);
        if (callee.tag == .identifier) {
            const t = e.tokTag(callee.main_token);
            // isset($a, $b) is isset($a) && isset($b)
            if (t == .kw_isset and arg_list.len > 1) {
                if (priority > 130) try e.char('(');
                for (arg_list, 0..) |a, k| {
                    if (k > 0) try e.str(" && ");
                    try e.str("isset(");
                    try e.expr(a, 0, indent);
                    try e.char(')');
                }
                if (priority > 130) try e.char(')');
                return;
            }
        }
        if (callee.tag == .grouped_expr and e.node(callee.data.lhs).tag == .closure_expr) {
            try e.char('(');
            try e.closure(e.node(callee.data.lhs), callee.data.lhs, indent, false);
            try e.char(')');
        } else if (callee.tag == .closure_expr) {
            try e.char('(');
            try e.closure(callee, n.data.lhs, indent, false);
            try e.char(')');
        } else {
            try e.nsName(n.data.lhs, indent);
        }
        try e.char('(');
        try e.list(arg_list, 0, indent);
        try e.char(')');
    }

    fn propName(e: *Exporter, n: Node, indent: u32) Error!void {
        // main_token 0: `->{expr}` or `->$$x`; otherwise rhs is an identifier
        // or a variable node
        const prop = e.node(n.data.rhs);
        if (n.main_token == 0 or prop.tag != .identifier) return e.varName(n.data.rhs, indent);
        try e.str(e.tok(prop.main_token));
    }

    fn expr(e: *Exporter, i: u32, priority: u32, indent: u32) Error!void {
        if (i == 0) return;
        const n = e.node(i);
        switch (n.tag) {
            .integer_literal => {
                const v = Compiler.parsePhpIntLiteral(e.tok(n.main_token));
                switch (v) {
                    .int => |x| {
                        var buf: [32]u8 = undefined;
                        try e.str(std.fmt.bufPrint(&buf, "{d}", .{x}) catch unreachable);
                    },
                    .float => |x| try e.double(x),
                    else => {},
                }
            },
            .float_literal => try e.double(Compiler.parsePhpFloat(e.tok(n.main_token))),
            .string_literal => try e.stringLiteral(n, indent),
            .true_literal, .false_literal, .null_literal => {
                if (n.main_token > 0 and e.tokTag(n.main_token - 1) == .backslash) try e.char('\\');
                try e.str(e.tok(n.main_token));
            },
            .variable => {
                try e.str(e.tok(n.main_token));
            },
            .variable_variable => {
                try e.char('$');
                try e.varName(n.data.lhs, indent);
            },
            .identifier => try e.nsName(i, indent),
            .qualified_name => try e.qualified(n),
            .binary_op => try e.binaryOp(n, priority, indent),
            .pipe_expr => try e.binary(n, " |> ", priority, 183, 183, 184, indent),
            .logical_and => try e.binary(n, " && ", priority, 130, 130, 131, indent),
            .logical_or => try e.binary(n, " || ", priority, 120, 120, 121, indent),
            .null_coalesce => try e.binary(n, " ?? ", priority, 110, 111, 110, indent),
            .assign => try e.assign(n, priority, indent),
            .prefix_op => switch (e.tokTag(n.main_token)) {
                .bang => try e.prefix(n.data.lhs, "!", priority, 240, 241, indent),
                .minus => try e.prefix(n.data.lhs, "-", priority, 240, 241, indent),
                .plus => try e.prefix(n.data.lhs, "+", priority, 240, 241, indent),
                .tilde => try e.prefix(n.data.lhs, "~", priority, 240, 241, indent),
                .at => try e.prefix(n.data.lhs, "@", priority, 240, 241, indent),
                .plus_plus => try e.prefix(n.data.lhs, "++", priority, 240, 241, indent),
                .minus_minus => try e.prefix(n.data.lhs, "--", priority, 240, 241, indent),
                .kw_clone => {
                    // php 8.5 compiles clone to a call of \clone()
                    try e.str("\\clone(");
                    try e.expr(n.data.lhs, 0, indent);
                    try e.char(')');
                },
                else => try e.prefix(n.data.lhs, e.tok(n.main_token), priority, 240, 241, indent),
            },
            .postfix_op => {
                if (priority > 240) try e.char('(');
                try e.expr(n.data.lhs, 241, indent);
                try e.str(e.tok(n.main_token));
                if (priority > 240) try e.char(')');
            },
            .ternary => {
                const branches = e.ast.extra_data[n.data.rhs .. n.data.rhs + 2];
                if (priority > 100) try e.char('(');
                try e.expr(n.data.lhs, 100, indent);
                if (branches[0] != 0) {
                    try e.str(" ? ");
                    try e.expr(branches[0], 101, indent);
                    try e.str(" : ");
                } else {
                    try e.str(" ?: ");
                }
                try e.expr(branches[1], 101, indent);
                if (priority > 100) try e.char(')');
            },
            .call => try e.call(n, priority, indent),
            .callable_ref => {
                const target = e.node(n.data.lhs);
                switch (target.tag) {
                    .method_call, .nullsafe_method_call => {
                        try e.expr(target.data.lhs, 0, indent);
                        try e.str(if (target.tag == .nullsafe_method_call) "?->" else "->");
                        try e.str(e.tok(target.main_token));
                    },
                    .static_call => {
                        try e.nsName(target.data.lhs, indent);
                        try e.str("::");
                        try e.str(e.tok(target.main_token));
                    },
                    else => try e.nsName(n.data.lhs, indent),
                }
                try e.str("(...)");
            },
            .array_access => {
                try e.expr(n.data.lhs, 260, indent);
                try e.char('[');
                try e.expr(n.data.rhs, 0, indent);
                try e.char(']');
            },
            .array_push_target => {
                try e.expr(n.data.lhs, 260, indent);
                try e.str("[]");
            },
            .property_access, .nullsafe_property_access => {
                try e.expr(n.data.lhs, 0, indent);
                try e.str(if (n.tag == .nullsafe_property_access) "?->" else "->");
                try e.propName(n, indent);
            },
            .method_call, .nullsafe_method_call => {
                try e.expr(n.data.lhs, 0, indent);
                try e.str(if (n.tag == .nullsafe_method_call) "?->" else "->");
                try e.str(e.tok(n.main_token));
                try e.char('(');
                if (n.data.rhs != 0) try e.args(n.data.rhs, indent);
                try e.char(')');
            },
            .static_call => {
                try e.nsName(n.data.lhs, indent);
                try e.str("::");
                try e.str(e.tok(n.main_token));
                try e.char('(');
                if (n.data.rhs != 0) try e.args(n.data.rhs, indent);
                try e.char(')');
            },
            .dynamic_static_call => {
                const items = e.ast.extraSlice(n.data.rhs);
                try e.nsName(n.data.lhs, indent);
                try e.str("::");
                // main_token is the `$` of `A::${expr}()`, 0 for `A::{expr}()`
                if (n.main_token != 0) {
                    try e.char('$');
                    try e.varName(items[0], indent);
                } else {
                    try e.varName(items[0], indent);
                }
                try e.char('(');
                try e.list(items[1..], 0, indent);
                try e.char(')');
            },
            .static_prop_access => {
                try e.nsName(n.data.lhs, indent);
                if (n.main_token == 0) {
                    try e.str("::$");
                    try e.varName(n.data.rhs, indent);
                } else if (e.tokTag(n.main_token) == .variable) {
                    try e.str("::");
                    try e.str(e.tok(n.main_token));
                } else {
                    try e.str("::");
                    try e.str(e.tok(n.main_token));
                }
            },
            .dynamic_class_const => {
                try e.nsName(n.data.lhs, indent);
                try e.str("::");
                try e.name(n.data.rhs, indent);
            },
            .new_expr => {
                try e.str("new ");
                const marker = n.data.rhs;
                if (marker & (1 << 31) != 0) try e.char('\\');
                if (marker & (1 << 30) != 0) try e.str("namespace\\");
                const parts_extra = marker & ~@as(u32, 3 << 30);
                if (parts_extra != 0) {
                    for (e.ast.extraSlice(parts_extra), 0..) |part, k| {
                        if (k > 0) try e.char('\\');
                        try e.str(e.tok(part));
                    }
                } else try e.str(e.tok(n.main_token));
                try e.char('(');
                try e.args(n.data.lhs, indent);
                try e.char(')');
            },
            .new_expr_dynamic => {
                try e.str("new ");
                try e.nsName(n.data.lhs, indent);
                try e.char('(');
                try e.args(n.data.rhs, indent);
                try e.char(')');
            },
            .anonymous_class => try e.anonymousClass(n, indent),
            .array_literal => {
                try e.char('[');
                try e.list(e.ast.extraSlice(n.data.lhs), 20, indent);
                try e.char(']');
            },
            .list_destructure => {
                try e.char('[');
                try e.list(e.ast.extraSlice(n.data.lhs), 20, indent);
                try e.char(']');
            },
            .array_element => {
                if (n.data.rhs != 0) {
                    try e.expr(n.data.rhs, 80, indent);
                    try e.str(" => ");
                }
                try e.expr(n.data.lhs, 80, indent);
            },
            .ref_target => {
                try e.char('&');
                try e.expr(n.data.lhs, priority, indent);
            },
            .array_spread, .splat_expr => {
                try e.str("...");
                try e.expr(n.data.lhs, priority, indent);
            },
            .named_arg => {
                try e.str(e.tok(n.main_token));
                try e.str(": ");
                try e.expr(n.data.lhs, priority, indent);
            },
            .grouped_expr => {
                const inner = e.node(n.data.lhs);
                // ZEND_PARENTHESIZED_ARROW_FUNC
                if (inner.tag == .closure_expr and isArrow(e.ast, inner)) {
                    try e.char('(');
                    try e.closure(inner, n.data.lhs, indent, false);
                    try e.char(')');
                    return;
                }
                try e.expr(n.data.lhs, priority, indent);
            },
            .cast_expr => {
                const op = castName(e.tok(n.main_token)) orelse e.tok(n.main_token);
                try e.prefix(n.data.lhs, op, priority, 240, 241, indent);
            },
            .closure_expr => try e.closure(n, i, indent, false),
            .throw_expr => {
                try e.str("throw ");
                try e.expr(n.data.lhs, 0, indent);
            },
            .print_expr => try e.prefix(n.data.lhs, "print ", priority, 60, 61, indent),
            .yield_expr, .yield_pair_expr => {
                if (priority > 70) try e.char('(');
                try e.str("yield ");
                if (n.tag == .yield_pair_expr) {
                    try e.expr(n.data.lhs, 70, indent);
                    try e.str(" => ");
                    try e.expr(n.data.rhs, 70, indent);
                } else if (n.data.lhs != 0) {
                    try e.expr(n.data.lhs, 70, indent);
                }
                if (priority > 70) try e.char(')');
            },
            .yield_from_expr => try e.prefix(n.data.lhs, "yield from ", priority, 85, 86, indent),
            .require_expr => {
                try e.str(switch (e.tokTag(n.main_token)) {
                    .kw_include => "include",
                    .kw_include_once => "include_once",
                    .kw_require => "require",
                    else => "require_once",
                });
                try e.char('(');
                try e.expr(n.data.lhs, 0, indent);
                try e.char(')');
            },
            .match_expr => {
                try e.str("match (");
                try e.expr(n.data.lhs, 0, indent);
                try e.str(") {\n");
                for (e.ast.extraSlice(n.data.rhs)) |arm_idx| {
                    const arm = e.node(arm_idx);
                    try e.indentBy(indent + 1);
                    const conds = e.ast.extraSlice(arm.data.lhs);
                    if (conds.len == 0) {
                        try e.str("default => ");
                    } else {
                        try e.list(conds, 0, indent + 1);
                        try e.str(" => ");
                    }
                    try e.expr(arm.data.rhs, 0, 0);
                    try e.str(",\n");
                }
                try e.indentBy(indent);
                try e.char('}');
            },
            .clone_with => {
                try e.str("\\clone(");
                try e.expr(n.data.lhs, 0, indent);
                try e.str(", ");
                try e.expr(n.data.rhs, 0, indent);
                try e.char(')');
            },
            .expr_list => try e.list(e.ast.extraSlice(n.data.lhs), 0, indent),
            else => {},
        }
    }

    fn isArrow(ast: *const Ast, n: Node) bool {
        return ast.tokens[n.main_token].tag == .kw_fn;
    }

    // ---- strings

    fn hasInterpolation(s: []const u8) bool {
        var k: usize = 0;
        while (k < s.len) : (k += 1) {
            if (s[k] == '\\') {
                k += 1;
                continue;
            }
            if (s[k] == '$' and k + 1 < s.len and (s[k + 1] == '{' or s[k + 1] == '_' or s[k + 1] >= 127 or std.ascii.isAlphabetic(s[k + 1]))) return true;
            if (s[k] == '{' and k + 1 < s.len and s[k + 1] == '$') return true;
        }
        return false;
    }

    fn stringLiteral(e: *Exporter, n: Node, indent: u32) Error!void {
        const t = e.tokTag(n.main_token);
        const lexeme = e.tok(n.main_token);
        if (t == .string and lexeme.len >= 2 and lexeme[0] == '`') {
            try e.char('`');
            try e.encaps(lexeme[1 .. lexeme.len - 1], '`', '`', indent);
            try e.char('`');
            return;
        }
        if (try e.literalString(n)) |s| {
            defer e.allocator.free(s);
            return e.quotedString(s);
        }
        const heredoc = t == .heredoc;
        const body: []const u8 = if (heredoc) try heredocBody(e.allocator, lexeme) else lexeme[1 .. lexeme.len - 1];
        defer if (heredoc) e.allocator.free(body);
        try e.char('"');
        try e.encaps(body, if (t == .heredoc) 0 else '"', '"', indent);
        try e.char('"');
    }

    const Part = union(enum) {
        text: []const u8, // processed bytes
        simple: []const u8, // $name
        node: struct { ast: *Ast, idx: u32 },
    };

    // zend_ast_export_encaps_list over the parts of an interpolated string.
    // `source_quote` is the quote the lexer escaped against, `quote` the one
    // the output uses
    fn encaps(e: *Exporter, s: []const u8, source_quote: u8, quote: u8, indent: u32) Error!void {
        var parts = std.ArrayListUnmanaged(Part).empty;
        var asts = std.ArrayListUnmanaged(*Ast).empty;
        var texts = std.ArrayListUnmanaged([]const u8).empty;
        defer {
            for (asts.items) |a| {
                a.deinit();
                e.allocator.destroy(a);
            }
            asts.deinit(e.allocator);
            for (texts.items) |x| e.allocator.free(x);
            texts.deinit(e.allocator);
            parts.deinit(e.allocator);
        }
        var k: usize = 0;
        var lit_start: usize = 0;
        while (k < s.len) {
            const c = s[k];
            if (c == '\\' and k + 1 < s.len) {
                k += 2;
                continue;
            }
            const brace_expr = c == '{' and k + 1 < s.len and s[k + 1] == '$';
            const dollar_brace = c == '$' and k + 1 < s.len and s[k + 1] == '{';
            const simple = c == '$' and k + 1 < s.len and (s[k + 1] == '_' or s[k + 1] >= 127 or std.ascii.isAlphabetic(s[k + 1]));
            if (!brace_expr and !dollar_brace and !simple) {
                k += 1;
                continue;
            }
            if (k > lit_start) {
                const text = try strings.processEscapes(e.allocator, s[lit_start..k], source_quote);
                try texts.append(e.allocator, text);
                try parts.append(e.allocator, .{ .text = text });
            }
            if (brace_expr) {
                const close = matchBrace(s, k) orelse s.len;
                try e.parsedPart(&parts, &asts, &texts, s[k + 1 .. close], false);
                k = @min(close + 1, s.len);
            } else if (dollar_brace) {
                const close = matchBrace(s, k + 1) orelse s.len;
                const inner = s[k + 2 .. close];
                var plain = inner.len > 0 and (inner[0] == '_' or inner[0] >= 127 or std.ascii.isAlphabetic(inner[0]));
                var name_end: usize = 0;
                while (name_end < inner.len and isVarChar(inner[name_end])) name_end += 1;
                if (plain and name_end < inner.len and inner[name_end] != '[') plain = false;
                if (plain and name_end == inner.len) {
                    try parts.append(e.allocator, .{ .simple = inner });
                } else if (plain) {
                    // ${name[expr]}: $name indexed
                    const text = try std.fmt.allocPrint(e.allocator, "${s}", .{inner});
                    try texts.append(e.allocator, text);
                    try e.parsedPart(&parts, &asts, &texts, text, false);
                } else {
                    // ${expr}: the variable the expression names
                    try e.parsedPart(&parts, &asts, &texts, inner, true);
                }
                k = @min(close + 1, s.len);
            } else {
                var j = k + 1;
                while (j < s.len and isVarChar(s[j])) j += 1;
                if (j < s.len and s[j] == '[') {
                    const close = std.mem.indexOfScalarPos(u8, s, j, ']') orelse s.len;
                    // simple syntax keys: a bare word is a string, a number
                    // an integer, a variable itself
                    const key = s[j + 1 .. close];
                    const quoted_key = key.len > 0 and key[0] != '$' and !(std.ascii.isDigit(key[0]) or key[0] == '-');
                    const text = if (quoted_key)
                        try std.fmt.allocPrint(e.allocator, "{s}['{s}']", .{ s[k..j], key })
                    else
                        try std.fmt.allocPrint(e.allocator, "{s}", .{s[k..@min(close + 1, s.len)]});
                    try texts.append(e.allocator, text);
                    try e.parsedPart(&parts, &asts, &texts, text, false);
                    k = @min(close + 1, s.len);
                } else if (j + 2 < s.len and s[j] == '-' and s[j + 1] == '>' and (s[j + 2] == '_' or std.ascii.isAlphabetic(s[j + 2]) or s[j + 2] >= 127)) {
                    var m = j + 2;
                    while (m < s.len and isVarChar(s[m])) m += 1;
                    try e.parsedPart(&parts, &asts, &texts, s[k..m], false);
                    k = m;
                } else {
                    try parts.append(e.allocator, .{ .simple = s[k + 1 .. j] });
                    k = j;
                }
            }
            lit_start = k;
        }
        if (lit_start < s.len) {
            const text = try strings.processEscapes(e.allocator, s[lit_start..], source_quote);
            try texts.append(e.allocator, text);
            try parts.append(e.allocator, .{ .text = text });
        }

        for (parts.items, 0..) |part, idx| {
            // a variable named by a literal prints bare unless what follows
            // would read as part of it
            const next_needs_braces = idx + 1 < parts.items.len and switch (parts.items[idx + 1]) {
                .text => |text| text.len > 0 and (text[0] == '[' or isVarChar(text[0])),
                else => false,
            };
            switch (part) {
                .text => |text| try e.qstr(quote, text),
                .simple => |var_name| {
                    if (next_needs_braces) try e.char('{');
                    try e.char('$');
                    try e.str(var_name);
                    if (next_needs_braces) try e.char('}');
                },
                .node => |pn| {
                    var sub = Exporter{ .ast = pn.ast, .out = e.out, .allocator = e.allocator };
                    const n = pn.ast.nodes[pn.idx];
                    const bare = n.tag == .variable_variable and pn.ast.nodes[n.data.lhs].tag == .string_literal and !next_needs_braces;
                    if (!bare) try e.char('{');
                    try sub.expr(pn.idx, 0, indent);
                    if (!bare) try e.char('}');
                },
            }
        }
    }

    // parses one interpolated expression with zphp's parser; `var_var`
    // wraps it as `${expr}`
    fn parsedPart(e: *Exporter, parts: *std.ArrayListUnmanaged(Part), asts: *std.ArrayListUnmanaged(*Ast), texts: *std.ArrayListUnmanaged([]const u8), text: []const u8, var_var: bool) Error!void {
        const src = if (var_var)
            try std.fmt.allocPrint(e.allocator, "<?php ${{{s}}};", .{text})
        else
            try std.fmt.allocPrint(e.allocator, "<?php {s};", .{text});
        try texts.append(e.allocator, src);
        const sub = try e.allocator.create(Ast);
        sub.* = parser.parse(e.allocator, src) catch |err| {
            e.allocator.destroy(sub);
            return err;
        };
        try asts.append(e.allocator, sub);
        const root = sub.nodes[0];
        const top = sub.extraSlice(root.data.lhs);
        if (sub.errors.len > 0 or top.len == 0 or sub.nodes[top[0]].tag != .expression_stmt) {
            try parts.append(e.allocator, .{ .text = text });
            return;
        }
        try parts.append(e.allocator, .{ .node = .{ .ast = sub, .idx = sub.nodes[top[0]].data.lhs } });
    }

    fn matchBrace(s: []const u8, open: usize) ?usize {
        var depth: usize = 0;
        var k = open;
        var quote: u8 = 0;
        while (k < s.len) : (k += 1) {
            const c = s[k];
            if (quote != 0) {
                if (c == '\\') {
                    k += 1;
                } else if (c == quote) quote = 0;
                continue;
            }
            switch (c) {
                '\'', '"' => quote = c,
                '{' => depth += 1,
                '}' => {
                    depth -= 1;
                    if (depth == 0) return k;
                },
                else => {},
            }
        }
        return null;
    }

    // ---- declarations

    // the attribute groups written right before token `at`, the way
    // zend_ast_export_attributes prints them
    fn attributes(e: *Exporter, at: u32, indent: u32, newlines: bool) Error!void {
        for (e.ast.attr_ranges) |range| {
            if (range.target_tok != at) continue;
            const items = e.ast.extraSlice(range.items);
            var k: usize = 0;
            while (k + 2 < items.len + 2 and k < items.len) {
                // one #[...] group: items until the next one starting after a #[
                try e.str("#[");
                var first = true;
                while (k < items.len) {
                    const name_start = items[k];
                    if (!first and e.tokTag(name_start - 1) == .hash_bracket) break;
                    if (!first) try e.str(", ");
                    first = false;
                    var t = name_start;
                    while (t < items[k + 1]) : (t += 1) try e.str(e.tok(t));
                    if (items[k + 2] != AstMod.AttrRange.no_args) {
                        try e.char('(');
                        try e.args(items[k + 2], indent);
                        try e.char(')');
                    }
                    k += 3;
                }
                try e.char(']');
                if (newlines) {
                    try e.char('\n');
                    try e.indentBy(indent);
                } else try e.char(' ');
            }
            return;
        }
    }

    // the first token of a declaration whose name or keyword is `t`: back
    // over the modifiers written before it
    fn declStart(e: *Exporter, t: u32) u32 {
        var k = t;
        while (k > 0) {
            switch (e.tokTag(k - 1)) {
                .kw_public, .kw_protected, .kw_private, .kw_static, .kw_abstract, .kw_final, .kw_readonly, .kw_var => k -= 1,
                .r_paren => {
                    // `private(set)`
                    if (k >= 4 and e.tokTag(k - 3) == .l_paren and e.tokTag(k - 4) != .identifier) {
                        k -= 3;
                    } else break;
                },
                else => break,
            }
        }
        return k;
    }

    fn typeRange(e: *Exporter, start: u32, end: u32) Error!void {
        var t = start;
        while (t < end) : (t += 1) {
            const tag = e.tokTag(t);
            if (tag == .l_paren or tag == .r_paren) continue;
            try e.str(e.tok(t));
        }
    }

    fn typeExtra(e: *Exporter, extra_plus_one: u32) Error!bool {
        if (extra_plus_one == 0) return false;
        const range = e.ast.extra_data[extra_plus_one - 1 .. extra_plus_one + 1];
        if (range[0] == range[1]) return false;
        try e.typeRange(range[0], range[1]);
        return true;
    }

    fn visibility(e: *Exporter, v: u32) Error!void {
        try e.str(switch (v) {
            1 => "protected ",
            2 => "private ",
            else => "public ",
        });
    }

    fn param(e: *Exporter, i: u32, indent: u32) Error!void {
        const n = e.node(i);
        const flags = n.data.rhs;
        // attributes come before the modifiers and the type
        var first = n.main_token;
        const type_extra = flags >> 8;
        if (type_extra != 0) first = e.ast.extra_data[type_extra - 1];
        if (flags & 2 != 0 and type_extra == 0) first -= 1;
        if (flags & 1 != 0 and type_extra == 0) first -= 1;
        try e.attributes(e.declStart(first), indent, false);
        const promotion = (flags >> 2) & 3;
        const set_promotion = (flags >> 5) & 3;
        if (promotion != 0) try e.visibility(promotion - 1);
        if (set_promotion != 0) try e.str(switch (set_promotion) {
            1 => "public(set) ",
            2 => "protected(set) ",
            else => "private(set) ",
        });
        if (flags & (1 << 7) != 0) try e.str("final ");
        if (try e.typeExtra(type_extra)) try e.char(' ');
        if (flags & 2 != 0) try e.char('&');
        if (flags & 1 != 0) try e.str("...");
        try e.str(e.tok(n.main_token));
        if (n.data.lhs != 0) {
            try e.str(" = ");
            try e.expr(n.data.lhs, 0, indent);
        }
    }

    fn params(e: *Exporter, extra: u32, indent: u32) Error!void {
        for (e.ast.extraSlice(extra), 0..) |p, k| {
            if (k > 0) try e.str(", ");
            try e.param(p, indent);
        }
    }

    fn returnType(e: *Exporter, extra: u32) Error!void {
        const count = e.ast.extra_data[extra];
        const range = e.ast.extra_data[extra + 1 + count .. extra + 3 + count];
        if (range[0] == range[1]) return;
        try e.str(": ");
        try e.typeRange(range[0], range[1]);
    }

    fn closure(e: *Exporter, n: Node, _: u32, indent: u32, _: bool) Error!void {
        const rhs = e.ast.extra_data[n.data.rhs .. n.data.rhs + 2];
        const encoded = rhs[0];
        const body = encoded & 0x1fffffff;
        const is_static = encoded & (1 << 30) != 0;
        const by_ref = encoded & (1 << 29) != 0;
        const arrow = isArrow(e.ast, n);
        try e.attributes(if (is_static) n.main_token - 1 else n.main_token, indent, false);
        if (is_static) try e.str("static ");
        try e.str(if (arrow) "fn" else "function ");
        if (by_ref) try e.char('&');
        try e.char('(');
        try e.params(n.data.lhs, indent);
        try e.char(')');
        if (!arrow and rhs[1] > 0) {
            try e.str(" use(");
            const uses = e.ast.extra_data[n.data.rhs + 2 .. n.data.rhs + 2 + rhs[1]];
            for (uses, 0..) |u, k| {
                if (k > 0) try e.str(", ");
                if (e.node(u).data.rhs == 1) try e.char('&');
                try e.str(e.tok(e.node(u).main_token));
            }
            try e.char(')');
        }
        try e.returnType(n.data.lhs);
        if (arrow) {
            try e.str(" => ");
            const block = e.node(body);
            const body_stmts = e.ast.extraSlice(block.data.lhs);
            if (body_stmts.len > 0) try e.expr(e.node(body_stmts[0]).data.lhs, 0, indent);
            return;
        }
        try e.str(" {\n");
        try e.stmts(body, indent + 1);
        try e.indentBy(indent);
        try e.char('}');
    }

    // ---- statements

    fn stmts(e: *Exporter, i: u32, indent: u32) Error!void {
        if (i == 0) return;
        const n = e.node(i);
        if (n.tag == .block) {
            for (e.ast.extraSlice(n.data.lhs)) |s| try e.stmts(s, indent);
            return;
        }
        try e.stmt(i, indent);
    }

    fn line(e: *Exporter, indent: u32) Error!void {
        try e.indentBy(indent);
    }

    // zend_ast_export_stmt for one statement
    fn stmt(e: *Exporter, i: u32, indent: u32) Error!void {
        const n = e.node(i);
        switch (n.tag) {
            .expression_stmt => {
                const inner = e.node(n.data.lhs);
                // unset($a, $b) is a statement per variable
                if (inner.tag == .call and e.node(inner.data.lhs).tag == .identifier and e.tokTag(e.node(inner.data.lhs).main_token) == .kw_unset) {
                    for (e.ast.extraSlice(inner.data.rhs)) |a| {
                        try e.line(indent);
                        try e.str("unset(");
                        try e.expr(a, 0, indent);
                        try e.str(");\n");
                    }
                    return;
                }
                try e.line(indent);
                try e.expr(n.data.lhs, 0, indent);
                try e.str(";\n");
            },
            .echo_stmt => {
                const is_print = e.tokTag(n.main_token) == .kw_print;
                for (e.ast.extraSlice(n.data.lhs)) |x| {
                    try e.line(indent);
                    try e.str(if (is_print) "print " else "echo ");
                    try e.expr(x, 0, indent);
                    try e.str(";\n");
                }
            },
            .inline_html => {
                try e.line(indent);
                try e.str("echo ");
                try e.quotedString(e.tok(n.main_token));
                try e.str(";\n");
            },
            .return_stmt => {
                try e.line(indent);
                try e.str("return");
                if (n.data.lhs != 0) {
                    try e.char(' ');
                    try e.expr(n.data.lhs, 0, indent);
                }
                try e.str(";\n");
            },
            .break_stmt, .continue_stmt => {
                try e.line(indent);
                try e.str(if (n.tag == .break_stmt) "break" else "continue");
                if (n.data.rhs == 1) {
                    var buf: [16]u8 = undefined;
                    try e.char(' ');
                    try e.str(std.fmt.bufPrint(&buf, "{d}", .{n.data.lhs}) catch unreachable);
                } else if (n.data.rhs != 0) {
                    try e.char(' ');
                    try e.str(e.tok(n.main_token + 1));
                }
                try e.str(";\n");
            },
            .throw_expr => {
                try e.line(indent);
                try e.expr(i, 0, indent);
                try e.str(";\n");
            },
            .block => for (e.ast.extraSlice(n.data.lhs)) |s| try e.stmt(s, indent),
            .if_simple, .if_else => {
                try e.line(indent);
                try e.ifStmt(i, indent);
                try e.char('\n');
            },
            .while_stmt => {
                try e.line(indent);
                try e.str("while (");
                try e.expr(n.data.lhs, 0, indent);
                try e.str(") {\n");
                try e.stmts(n.data.rhs, indent + 1);
                try e.line(indent);
                try e.str("}\n");
            },
            .do_while => {
                try e.line(indent);
                try e.str("do {\n");
                try e.stmts(n.data.lhs, indent + 1);
                try e.line(indent);
                try e.str("} while (");
                try e.expr(n.data.rhs, 0, indent);
                try e.str(");\n");
            },
            .for_stmt => {
                const parts = e.ast.extra_data[n.data.lhs .. n.data.lhs + 3];
                try e.line(indent);
                try e.str("for (");
                try e.expr(parts[0], 0, indent);
                try e.char(';');
                if (parts[1] != 0) {
                    try e.char(' ');
                    try e.expr(parts[1], 0, indent);
                }
                try e.char(';');
                if (parts[2] != 0) {
                    try e.char(' ');
                    try e.expr(parts[2], 0, indent);
                }
                try e.str(") {\n");
                try e.stmts(n.data.rhs, indent + 1);
                try e.line(indent);
                try e.str("}\n");
            },
            .foreach_stmt => {
                const parts = e.ast.extra_data[n.data.lhs .. n.data.lhs + 4];
                try e.line(indent);
                try e.str("foreach (");
                try e.expr(parts[0], 0, indent);
                try e.str(" as ");
                if (parts[2] != 0) {
                    try e.expr(parts[2], 0, indent);
                    try e.str(" => ");
                }
                if (parts[3] == 1) try e.char('&');
                try e.expr(parts[1], 0, indent);
                try e.str(") {\n");
                try e.stmts(n.data.rhs, indent + 1);
                try e.line(indent);
                try e.str("}\n");
            },
            .switch_stmt => {
                try e.line(indent);
                try e.str("switch (");
                try e.expr(n.data.lhs, 0, indent);
                try e.str(") {\n");
                for (e.ast.extraSlice(n.data.rhs)) |c| {
                    const case = e.node(c);
                    if (case.tag == .switch_default) {
                        try e.line(indent + 1);
                        try e.str("default:\n");
                        for (e.ast.extraSlice(case.data.lhs)) |s| try e.stmt(s, indent + 2);
                        continue;
                    }
                    const values = e.ast.extraSlice(case.data.lhs);
                    for (values) |v| {
                        try e.line(indent + 1);
                        try e.str("case ");
                        try e.expr(v, 0, indent + 1);
                        try e.str(":\n");
                    }
                    for (e.ast.extraSlice(case.data.rhs)) |s| try e.stmt(s, indent + 2);
                }
                try e.line(indent);
                try e.str("}\n");
            },
            .try_catch => {
                const extra = e.ast.extra_data[n.data.rhs..];
                const count = extra[0];
                try e.line(indent);
                try e.str("try {\n");
                try e.stmts(n.data.lhs, indent + 1);
                try e.line(indent);
                for (extra[1 .. 1 + count]) |c| {
                    const clause = e.node(c);
                    try e.str("} catch (");
                    for (e.ast.extraSlice(clause.data.lhs), 0..) |t, k| {
                        if (k > 0) try e.char('|');
                        try e.nsName(t, indent);
                    }
                    if (clause.main_token != 0) {
                        try e.char(' ');
                        try e.str(e.tok(clause.main_token));
                    }
                    try e.str(") {\n");
                    try e.stmts(clause.data.rhs, indent + 1);
                    try e.line(indent);
                }
                const finally_node = extra[1 + count];
                if (finally_node != 0) {
                    try e.str("} finally {\n");
                    try e.stmts(finally_node, indent + 1);
                    try e.line(indent);
                }
                try e.str("}\n");
            },
            .global_stmt => for (e.ast.extraSlice(n.data.lhs)) |v| {
                try e.line(indent);
                try e.str("global ");
                try e.expr(v, 0, indent);
                try e.str(";\n");
            },
            .static_var => {
                try e.line(indent);
                try e.str("static ");
                try e.str(e.tok(n.main_token));
                if (n.data.lhs != 0) {
                    try e.str(" = ");
                    try e.expr(n.data.lhs, 0, indent);
                }
                try e.str(";\n");
            },
            .label_stmt => {
                try e.line(indent);
                try e.str(e.tok(n.main_token));
                try e.str(":\n");
            },
            .goto_stmt => {
                try e.line(indent);
                try e.str("goto ");
                try e.str(e.tok(n.main_token));
                try e.str(";\n");
            },
            .declare_stmt => {
                try e.line(indent);
                try e.str("declare(");
                // the directives between the parentheses: name = literal
                var t = n.main_token + 2;
                var first = true;
                while (t < n.data.lhs) {
                    if (e.tokTag(t) == .comma) {
                        t += 1;
                        continue;
                    }
                    if (!first) try e.str(", ");
                    first = false;
                    try e.str(e.tok(t));
                    try e.str(" = ");
                    t += 2;
                    var value_end = t;
                    while (value_end < n.data.lhs and e.tokTag(value_end) != .comma) value_end += 1;
                    if (value_end == t + 1 and e.tokTag(t) == .integer) {
                        const v = Compiler.parsePhpIntLiteral(e.tok(t));
                        var buf: [32]u8 = undefined;
                        if (v == .int) try e.str(std.fmt.bufPrint(&buf, "{d}", .{v.int}) catch unreachable);
                    } else {
                        while (t < value_end) : (t += 1) try e.str(e.tok(t));
                    }
                    t = value_end;
                }
                try e.char(')');
                if (n.data.rhs != 0) {
                    try e.str(" {\n");
                    try e.stmts(n.data.rhs, indent + 1);
                    try e.line(indent);
                    try e.str("}\n");
                } else try e.str(";\n");
            },
            .const_decl => {
                try e.line(indent);
                try e.str("const ");
                try e.str(e.tok(n.main_token));
                try e.str(" = ");
                try e.expr(n.data.lhs, 0, indent);
                try e.str(";\n");
            },
            .function_decl => {
                try e.line(indent);
                try e.attributes(n.main_token - 1 - @as(u32, if (n.data.rhs & (1 << 30) != 0) 1 else 0), indent, true);
                try e.str("function ");
                if (n.data.rhs & (1 << 30) != 0) try e.char('&');
                try e.str(e.tok(n.main_token));
                try e.char('(');
                try e.params(n.data.lhs, indent);
                try e.char(')');
                try e.returnType(n.data.lhs);
                try e.str(" {\n");
                try e.stmts(n.data.rhs & 0x3fffffff, indent + 1);
                try e.line(indent);
                try e.str("}\n\n");
            },
            .class_decl, .interface_decl, .trait_decl, .enum_decl => {
                try e.line(indent);
                try e.classDecl(n, indent);
                try e.str("\n\n");
            },
            .empty_stmt => {},
            else => {
                try e.line(indent);
                try e.expr(i, 0, indent);
                try e.str(";\n");
            },
        }
    }

    fn ifStmt(e: *Exporter, first_if: u32, indent: u32) Error!void {
        var i = first_if;
        var keyword: []const u8 = "if (";
        while (true) {
            const n = e.node(i);
            try e.str(keyword);
            try e.expr(n.data.lhs, 0, indent);
            try e.str(") {\n");
            if (n.tag == .if_simple) {
                try e.stmts(n.data.rhs, indent + 1);
                break;
            }
            const branches = e.ast.extra_data[n.data.rhs .. n.data.rhs + 2];
            try e.stmts(branches[0], indent + 1);
            const else_node = e.node(branches[1]);
            if ((else_node.tag == .if_simple or else_node.tag == .if_else)) {
                try e.line(indent);
                if (e.tokTag(else_node.main_token) == .kw_elseif) {
                    keyword = "} elseif (";
                } else {
                    try e.str("} else ");
                    keyword = "if (";
                }
                i = branches[1];
                continue;
            }
            try e.line(indent);
            try e.str("} else {\n");
            try e.stmts(branches[1], indent + 1);
            break;
        }
        try e.line(indent);
        try e.char('}');
    }

    // ---- classes

    fn classDecl(e: *Exporter, n: Node, indent: u32) Error!void {
        switch (n.tag) {
            .class_decl => {
                const extra = e.ast.extra_data[n.data.rhs..];
                const modifiers = extra[0];
                const keyword = n.main_token - 1;
                try e.attributes(e.declStart(keyword), indent, true);
                if (modifiers & 1 != 0) try e.str("abstract ");
                if (modifiers & 2 != 0) try e.str("final ");
                if (modifiers & 4 != 0) try e.str("readonly ");
                try e.str("class ");
                try e.str(e.tok(n.main_token));
                try e.classBody(extra[1], extra[3 .. 3 + extra[2]], n.data.lhs, indent);
            },
            .interface_decl => {
                try e.attributes(n.main_token - 1, indent, true);
                try e.str("interface ");
                try e.str(e.tok(n.main_token));
                const parents: []const u32 = if (n.data.rhs != 0) e.ast.extraSlice(n.data.rhs) else &.{};
                try e.classBody(0, parents, n.data.lhs, indent);
            },
            .trait_decl => {
                try e.attributes(n.main_token - 1, indent, true);
                try e.str("trait ");
                try e.str(e.tok(n.main_token));
                try e.classBody(0, &.{}, n.data.lhs, indent);
            },
            .enum_decl => {
                const extra = e.ast.extra_data[n.data.rhs..];
                try e.attributes(n.main_token - 1, indent, true);
                try e.str("enum ");
                try e.str(e.tok(n.main_token));
                if (extra[0] != 0) {
                    try e.str(": ");
                    try e.str(e.tok(extra[0]));
                }
                try e.classBody(0, extra[2 .. 2 + extra[1]], n.data.lhs, indent);
            },
            else => {},
        }
    }

    fn anonymousClass(e: *Exporter, n: Node, indent: u32) Error!void {
        const extra = e.ast.extra_data[n.data.rhs..];
        const argc = extra[0];
        try e.str("new ");
        var class_tok = n.main_token + 1;
        while (e.tokTag(class_tok) != .kw_class) class_tok += 1;
        try e.attributes(e.declStart(class_tok), indent, false);
        try e.str("class");
        if (argc > 0) {
            try e.char('(');
            try e.list(extra[1 .. 1 + argc], 0, indent);
            try e.char(')');
        }
        const parent = extra[1 + argc];
        const impl_count = extra[2 + argc];
        try e.classBody(parent, extra[3 + argc .. 3 + argc + impl_count], n.data.lhs, indent);
    }

    // zend_ast_export_class_no_header
    fn classBody(e: *Exporter, parent: u32, implements: []const u32, members: u32, indent: u32) Error!void {
        if (parent != 0) {
            try e.str(" extends ");
            try e.nsName(parent, indent);
        }
        if (implements.len > 0) {
            try e.str(" implements ");
            for (implements, 0..) |impl, k| {
                if (k > 0) try e.str(", ");
                try e.nsName(impl, indent);
            }
        }
        try e.str(" {\n");
        const items = e.ast.extraSlice(members);
        var k: usize = 0;
        while (k < items.len) {
            k += try e.member(items, k, indent + 1);
        }
        try e.indentBy(indent);
        try e.char('}');
    }

    fn isContinuation(e: *Exporter, name_tok: u32) bool {
        return name_tok > 0 and e.tokTag(name_tok - 1) == .comma;
    }

    // prints the member at items[k] (and the rest of its group); returns how
    // many members it printed
    fn member(e: *Exporter, items: []const u32, k: usize, indent: u32) Error!usize {
        const n = e.node(items[k]);
        switch (n.tag) {
            .const_decl => {
                const flags = n.data.rhs;
                try e.indentBy(indent);
                try e.attributes(e.declStart(constKeyword(e, n)), indent, true);
                try e.visibility(flags & 3);
                try e.str("const ");
                if (try e.typeExtra(flags >> 16)) try e.char(' ');
                var count: usize = 0;
                while (k + count < items.len) {
                    const c = e.node(items[k + count]);
                    if (c.tag != .const_decl or (count > 0 and !e.isContinuation(c.main_token))) break;
                    if (count > 0) try e.str(", ");
                    try e.str(e.tok(c.main_token));
                    try e.str(" = ");
                    try e.expr(c.data.lhs, 0, indent);
                    count += 1;
                }
                try e.str(";\n");
                return count;
            },
            .class_property, .static_class_property, .class_property_hooks => {
                const flags = n.data.rhs;
                try e.indentBy(indent);
                var first_tok = n.main_token;
                const type_extra = flags >> 16;
                if (type_extra != 0) first_tok = e.ast.extra_data[type_extra - 1];
                try e.attributes(e.declStart(first_tok), indent, true);
                try e.visibility(flags & 3);
                if (flags & (1 << 5) != 0) try e.str(switch ((flags >> 3) & 3) {
                    0 => "public(set) ",
                    1 => "protected(set) ",
                    else => "private(set) ",
                });
                if (n.tag == .static_class_property or flags & AstMod.PropertyHooks.prop_static_hooked != 0) try e.str("static ");
                if (flags & 4 != 0) try e.str("readonly ");
                if (try e.typeExtra(type_extra)) try e.char(' ');
                if (n.tag == .class_property_hooks) {
                    const hx = e.ast.extra_data[n.data.lhs .. n.data.lhs + 9];
                    try e.str(e.tok(n.main_token));
                    if (hx[0] != 0) {
                        try e.str(" = ");
                        try e.expr(hx[0], 0, indent + 1);
                    }
                    try e.hooks(hx, indent);
                    try e.char('\n');
                    return 1;
                }
                var count: usize = 0;
                while (k + count < items.len) {
                    const p = e.node(items[k + count]);
                    if (count > 0 and (p.tag != n.tag or !e.isContinuation(p.main_token))) break;
                    if (count > 0) try e.str(", ");
                    try e.str(e.tok(p.main_token));
                    if (p.data.lhs != 0) {
                        try e.str(" = ");
                        try e.expr(p.data.lhs, 0, indent + 1);
                    }
                    count += 1;
                }
                try e.str(";\n");
                return count;
            },
            .class_method, .static_class_method, .interface_method => {
                try e.indentBy(indent);
                try e.method(n, indent);
                try e.char('\n');
                return 1;
            },
            .trait_use => {
                try e.indentBy(indent);
                try e.str("use ");
                for (e.ast.extraSlice(n.data.lhs), 0..) |t, j| {
                    if (j > 0) try e.str(", ");
                    try e.nsName(t, indent);
                }
                if (n.data.rhs == 0) {
                    try e.str(";\n");
                    return 1;
                }
                try e.str(" {\n");
                for (e.ast.extraSlice(n.data.rhs)) |c| {
                    const a = e.node(c);
                    try e.indentBy(indent + 1);
                    if (a.data.lhs != 0) {
                        try e.nsName(a.data.lhs, indent);
                        try e.str("::");
                    }
                    try e.str(e.tok(a.main_token));
                    if (a.tag == .trait_insteadof) {
                        try e.str(" insteadof ");
                        for (e.ast.extraSlice(a.data.rhs), 0..) |t, j| {
                            if (j > 0) try e.str(", ");
                            try e.nsName(t, indent);
                        }
                    } else {
                        const pair = e.ast.extra_data[a.data.rhs .. a.data.rhs + 2];
                        if (pair[0] != 0) {
                            try e.str(" as ");
                            try e.str(e.tok(pair[0]));
                        } else if (pair[1] != 0) try e.str(" as");
                        if (pair[1] != 0) {
                            try e.char(' ');
                            try e.str(e.tok(pair[1]));
                        }
                    }
                    try e.str(";\n");
                }
                try e.indentBy(indent);
                try e.str("}\n");
                return 1;
            },
            .enum_case => {
                try e.indentBy(indent);
                try e.attributes(n.main_token - 1, indent, true);
                try e.str("case ");
                try e.str(e.tok(n.main_token));
                if (n.data.lhs != 0) {
                    try e.str(" = ");
                    try e.expr(n.data.lhs, 0, indent);
                }
                try e.str(";\n");
                return 1;
            },
            else => return 1,
        }
    }

    fn constKeyword(e: *Exporter, n: Node) u32 {
        var t = n.main_token;
        while (t > 0 and e.tokTag(t) != .kw_const) t -= 1;
        return t;
    }

    fn method(e: *Exporter, n: Node, indent: u32) Error!void {
        var keyword = n.main_token;
        while (keyword > 0 and e.tokTag(keyword) != .kw_function) keyword -= 1;
        try e.attributes(e.declStart(keyword), indent, true);
        var is_static = n.tag == .static_class_method;
        var is_abstract = false;
        var is_final = false;
        var by_ref = false;
        var vis: u32 = 0;
        var body: u32 = 0;
        if (n.tag == .interface_method) {
            is_static = n.data.rhs & (1 << 30) != 0;
            by_ref = n.data.rhs & (1 << 31) != 0;
            vis = (n.data.rhs >> 28) & 3;
            // abstract in a class; an interface's methods are implicitly so
            var t = e.declStart(keyword);
            while (t < keyword) : (t += 1) {
                if (e.tokTag(t) == .kw_abstract) is_abstract = true;
            }
            is_abstract = true;
        } else {
            vis = n.data.rhs >> 30;
            is_final = n.data.rhs & (1 << 28) != 0;
            by_ref = n.data.rhs & (1 << 27) != 0;
            body = n.data.rhs & 0x7ffffff;
        }
        try e.visibility(vis);
        if (is_static) try e.str("static ");
        if (is_abstract) try e.str("abstract ");
        if (is_final) try e.str("final ");
        try e.str("function ");
        if (by_ref) try e.char('&');
        try e.str(e.tok(n.main_token));
        try e.char('(');
        try e.params(n.data.lhs, indent);
        try e.char(')');
        try e.returnType(n.data.lhs);
        if (body == 0) {
            try e.str(";\n");
            return;
        }
        try e.str(" {\n");
        try e.stmts(body, indent + 1);
        try e.indentBy(indent);
        try e.str("}\n");
    }

    // zend_ast_export_hook_list
    fn hooks(e: *Exporter, hx: []const u32, indent: u32) Error!void {
        const written = e.ast.extraSlice(hx[8]);
        try e.str(" {\n");
        try e.indentBy(indent + 1);
        var k: usize = 0;
        while (k + 3 < written.len + 3 and k < written.len) : (k += 4) {
            const hook_tok = written[k];
            const flags = written[k + 1];
            const modifier = written[k + 3];
            if (modifier != 0) switch (e.tokTag(modifier)) {
                .kw_public, .kw_protected, .kw_private => {
                    try e.str(e.tok(modifier));
                    try e.char(' ');
                },
                else => {},
            };
            if (flags & AstMod.PropertyHooks.hook_final != 0) try e.str("final ");
            const hook_name = e.tok(hook_tok);
            try e.str(hook_name);
            const is_get = std.ascii.eqlIgnoreCase(hook_name, "get");
            const body = if (is_get) hx[1] else hx[2];
            const short = if (is_get) hx[4] else hx[5];
            if (flags & AstMod.PropertyHooks.hook_bodyless != 0 or body == 0) {
                try e.char(';');
            } else if (short & 1 != 0) {
                try e.str(" => ");
                try e.expr(body, 0, indent + 1);
                try e.char(';');
            } else {
                try e.str(" {\n");
                try e.stmts(body, indent + 2);
                try e.indentBy(indent + 1);
                try e.char('}');
            }
            if (k + 4 < written.len) {
                try e.char('\n');
                try e.indentBy(indent + 1);
            }
        }
        try e.char('\n');
        try e.indentBy(indent);
        try e.char('}');
    }
};

// a heredoc's or nowdoc's body as php reads it: the lines between the
// labels, closing indentation removed. allocated
fn heredocBody(allocator: Allocator, lexeme: []const u8) Error![]u8 {
    var pos: usize = 3;
    while (pos < lexeme.len and (lexeme[pos] == ' ' or lexeme[pos] == '\t')) pos += 1;
    if (pos < lexeme.len and (lexeme[pos] == '\'' or lexeme[pos] == '"')) pos += 1;
    const label_start = pos;
    while (pos < lexeme.len and (std.ascii.isAlphanumeric(lexeme[pos]) or lexeme[pos] == '_')) pos += 1;
    const label = lexeme[label_start..pos];
    while (pos < lexeme.len and lexeme[pos] != '\n') pos += 1;
    if (pos < lexeme.len) pos += 1;
    const body_start = pos;
    var end = lexeme.len;
    while (end > body_start and (lexeme[end - 1] == '\n' or lexeme[end - 1] == '\r' or lexeme[end - 1] == ';')) end -= 1;
    if (end >= label.len and std.mem.eql(u8, lexeme[end - label.len .. end], label)) end -= label.len;
    var closing = end;
    while (closing > body_start and lexeme[closing - 1] != '\n') closing -= 1;
    const indent = end - closing;
    var body_end = closing;
    if (body_end > body_start and lexeme[body_end - 1] == '\n') body_end -= 1;
    if (body_end > body_start and lexeme[body_end - 1] == '\r') body_end -= 1;
    if (body_end <= body_start) return allocator.dupe(u8, "");
    const raw = lexeme[body_start..body_end];
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(allocator);
    var it = std.mem.splitScalar(u8, raw, '\n');
    var first = true;
    while (it.next()) |l| {
        if (!first) try out.append(allocator, '\n');
        first = false;
        var strip: usize = 0;
        while (strip < indent and strip < l.len and (l[strip] == ' ' or l[strip] == '\t')) strip += 1;
        try out.appendSlice(allocator, l[strip..]);
    }
    return out.toOwnedSlice(allocator);
}
