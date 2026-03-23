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
        }
        self.functions.deinit(self.allocator);
        for (self.string_allocs.items) |s| self.allocator.free(s);
        self.string_allocs.deinit(self.allocator);
    }
};

pub fn compile(ast: *const Ast, allocator: Allocator) Error!CompileResult {
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
                if (node.data.lhs != 0) {
                    try self.compileNode(node.data.lhs);
                    try self.emitOp(.return_val);
                } else {
                    try self.emitOp(.return_void);
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
            .array_access => try self.compileArrayAccess(node),
            .property_access => try self.compilePropertyAccess(node),
            .throw_expr => try self.compileThrow(node),
            .try_catch => try self.compileTryCatch(node),
            .catch_clause => {},
            .class_decl => try self.compileClassDecl(node),
            .class_method, .class_property => {},
            .new_expr => try self.compileNewExpr(node),
            .method_call => try self.compileMethodCall(node),
            .static_call => try self.compileStaticCall(node),
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
        // handles: $var and $var[key]
        if (expr.len == 0 or expr[0] != '$') return;

        var j: usize = 1;
        while (j < expr.len and isVarChar(expr[j])) j += 1;

        const var_name = expr[0..j];
        const var_idx = try self.addConstant(.{ .string = var_name });
        try self.emitOp(.get_var);
        try self.emitU16(var_idx);

        if (j < expr.len and expr[j] == '[') {
            const bracket_end = std.mem.indexOfScalarPos(u8, expr, j, ']') orelse expr.len;
            const key_str = expr[j + 1 .. bracket_end];
            try self.emitArrayKeyAccess(key_str);
        }
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
        const idx = try self.addConstant(.{ .string = name });
        try self.emitOp(.get_var);
        try self.emitU16(idx);
    }

    fn compileAssign(self: *Compiler, node: Ast.Node) Error!void {
        const target = self.ast.nodes[node.data.lhs];
        const op_tag = self.ast.tokens[node.main_token].tag;

        if (target.tag == .array_access) {
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
            else => .add,
        });
    }

    // ==================================================================
    // operators
    // ==================================================================

    fn compileBinaryOp(self: *Compiler, node: Ast.Node) Error!void {
        try self.compileNode(node.data.lhs);
        try self.compileNode(node.data.rhs);
        const op_tag = self.ast.tokens[node.main_token].tag;
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
            .kw_instanceof => .identical,
            else => .add,
        });
    }

    fn compilePrefixOp(self: *Compiler, node: Ast.Node) Error!void {
        const op_tag = self.ast.tokens[node.main_token].tag;

        if (op_tag == .plus_plus or op_tag == .minus_minus) {
            try self.compileNode(node.data.lhs);
            try self.emitConstant(try self.addConstant(.{ .int = 1 }));
            try self.emitOp(if (op_tag == .plus_plus) .add else .subtract);
            const target = self.ast.nodes[node.data.lhs];
            if (target.tag == .variable) {
                const name = self.ast.tokenSlice(target.main_token);
                const idx = try self.addConstant(.{ .string = name });
                try self.emitOp(.set_var);
                try self.emitU16(idx);
            }
            return;
        }

        try self.compileNode(node.data.lhs);
        try self.emitOp(switch (op_tag) {
            .minus => .negate,
            .bang => .not,
            .tilde => .bit_not,
            else => .negate,
        });
    }

    fn compilePostfixOp(self: *Compiler, node: Ast.Node) Error!void {
        const target = self.ast.nodes[node.data.lhs];
        const op_tag = self.ast.tokens[node.main_token].tag;

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
        var defaults = std.ArrayListUnmanaged(Value){};
        defer defaults.deinit(self.allocator);
        var required: u8 = 0;
        var seen_default = false;
        var is_variadic = false;

        for (param_nodes, 0..) |p, i| {
            const pnode = self.ast.nodes[p];
            param_names[i] = self.ast.tokenSlice(pnode.main_token);
            if (pnode.data.rhs == 1) {
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
        };
        errdefer {
            sub.chunk.deinit(self.allocator);
            sub.break_jumps.deinit(self.allocator);
            sub.continue_jumps.deinit(self.allocator);
            sub.string_allocs.deinit(self.allocator);
        }

        try sub.compileNode(node.data.rhs);
        try sub.emitOp(.op_null);
        try sub.emitOp(.return_val);
        sub.break_jumps.deinit(self.allocator);
        sub.continue_jumps.deinit(self.allocator);

        try self.functions.append(self.allocator, .{
            .name = name,
            .arity = @intCast(param_nodes.len),
            .required_params = required,
            .is_variadic = is_variadic,
            .params = param_names[0..param_nodes.len],
            .defaults = defaults_owned,
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
            const type_node_idx = catch_node.data.lhs;
            const body_idx = catch_node.data.rhs;
            _ = ci;

            if (type_node_idx != 0) {
                // typed catch: check instanceof, skip if no match
                try self.emitOp(.dup);
                const type_name = self.ast.tokenSlice(self.ast.nodes[type_node_idx].main_token);
                const type_idx = try self.addConstant(.{ .string = type_name });
                try self.emitConstant(type_idx);
                try self.emitOp(.instance_check);
                const skip = try self.emitJump(.jump_if_false);
                try self.emitOp(.pop);

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

                self.patchJump(skip);
                try self.emitOp(.pop);
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
        const class_name = self.ast.tokenSlice(node.main_token);
        const members = self.ast.extraSlice(node.data.lhs);

        // compile methods as functions named "ClassName::methodName"
        var method_count: u8 = 0;
        for (members) |member_idx| {
            const member = self.ast.nodes[member_idx];
            if (member.tag == .class_method) {
                const method_name = self.ast.tokenSlice(member.main_token);
                const full_name = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ class_name, method_name });
                try self.string_allocs.append(self.allocator, full_name);

                const param_nodes = self.ast.extraSlice(member.data.lhs);
                const param_names = try self.allocator.alloc([]const u8, param_nodes.len);
                for (param_nodes, 0..) |p, i| {
                    param_names[i] = self.ast.tokenSlice(self.ast.nodes[p].main_token);
                }

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
                };
                errdefer {
                    sub.chunk.deinit(self.allocator);
                    sub.break_jumps.deinit(self.allocator);
                    sub.continue_jumps.deinit(self.allocator);
                    sub.string_allocs.deinit(self.allocator);
                }

                try sub.compileNode(member.data.rhs);
                try sub.emitOp(.op_null);
                try sub.emitOp(.return_val);
                sub.break_jumps.deinit(self.allocator);

                self.closure_count = sub.closure_count;

                try self.functions.append(self.allocator, .{
                    .name = full_name,
                    .arity = @intCast(param_nodes.len),
                    .params = param_names[0..param_nodes.len],
                    .chunk = sub.chunk,
                });

                for (sub.functions.items) |f| try self.functions.append(self.allocator, f);
                sub.functions.deinit(self.allocator);
                for (sub.string_allocs.items) |s| try self.string_allocs.append(self.allocator, s);
                sub.string_allocs.deinit(self.allocator);

                method_count += 1;
            }
        }

        // compile property default values first (they push onto the stack)
        // emit them in reverse so the VM can pop them in forward order
        var prop_count: u8 = 0;
        for (members) |member_idx| {
            const member = self.ast.nodes[member_idx];
            if (member.tag == .class_property) prop_count += 1;
        }
        // push defaults in forward order (VM pops in forward order)
        for (members) |member_idx| {
            const member = self.ast.nodes[member_idx];
            if (member.tag == .class_property) {
                if (member.data.lhs != 0) {
                    try self.compileNode(member.data.lhs);
                }
            }
        }

        // emit class_decl opcode (defaults are already on stack)
        const name_idx = try self.addConstant(.{ .string = class_name });
        try self.emitOp(.class_decl);
        try self.emitU16(name_idx);
        try self.emitByte(method_count);

        for (members) |member_idx| {
            const member = self.ast.nodes[member_idx];
            if (member.tag == .class_method) {
                const method_name_str = self.ast.tokenSlice(member.main_token);
                const mname_idx = try self.addConstant(.{ .string = method_name_str });
                try self.emitU16(mname_idx);
                const param_nodes = self.ast.extraSlice(member.data.lhs);
                try self.emitByte(@intCast(param_nodes.len));
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
            }
        }

        if (node.data.rhs != 0) {
            const parent_name = self.ast.tokenSlice(self.ast.nodes[node.data.rhs].main_token);
            const parent_idx = try self.addConstant(.{ .string = parent_name });
            try self.emitU16(parent_idx);
        } else {
            try self.emitU16(0xffff);
        }
    }

    fn compileNewExpr(self: *Compiler, node: Ast.Node) Error!void {
        const class_name = self.ast.tokenSlice(node.main_token);
        const args = self.ast.extraSlice(node.data.lhs);
        for (args) |arg| try self.compileNode(arg);
        const name_idx = try self.addConstant(.{ .string = class_name });
        try self.emitOp(.new_obj);
        try self.emitU16(name_idx);
        try self.emitByte(@intCast(args.len));
    }

    fn compilePropertyAccess(self: *Compiler, node: Ast.Node) Error!void {
        const target = self.ast.nodes[node.data.lhs];

        // check if this is an assignment target (handled by compileAssign)
        // here we just handle reads
        try self.compileNode(node.data.lhs);
        const prop_node = self.ast.nodes[node.data.rhs];
        var prop_name = self.ast.tokenSlice(prop_node.main_token);
        // strip $ if it's a variable token used as property name
        if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
        _ = target;
        const name_idx = try self.addConstant(.{ .string = prop_name });
        try self.emitOp(.get_prop);
        try self.emitU16(name_idx);
    }

    fn compileMethodCall(self: *Compiler, node: Ast.Node) Error!void {
        try self.compileNode(node.data.lhs);
        const args = self.ast.extraSlice(node.data.rhs);
        for (args) |arg| try self.compileNode(arg);
        const method_name = self.ast.tokenSlice(node.main_token);
        const name_idx = try self.addConstant(.{ .string = method_name });
        try self.emitOp(.method_call);
        try self.emitU16(name_idx);
        try self.emitByte(@intCast(args.len));
    }

    fn compileStaticCall(self: *Compiler, node: Ast.Node) Error!void {
        const class_node = self.ast.nodes[node.data.lhs];
        const class_name = self.ast.tokenSlice(class_node.main_token);
        const method_name = self.ast.tokenSlice(node.main_token);
        const args = self.ast.extraSlice(node.data.rhs);
        for (args) |arg| try self.compileNode(arg);
        const class_idx = try self.addConstant(.{ .string = class_name });
        const method_idx = try self.addConstant(.{ .string = method_name });
        try self.emitOp(.static_call);
        try self.emitU16(class_idx);
        try self.emitU16(method_idx);
        try self.emitByte(@intCast(args.len));
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
            try self.emitOp(.op_null);
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

    fn compileClosure(self: *Compiler, node: Ast.Node) Error!void {
        const id = self.closure_count;
        self.closure_count += 1;

        var name_buf: [32]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "__closure_{d}", .{id}) catch "__closure";
        const owned_name = try self.allocator.dupe(u8, name);
        try self.string_allocs.append(self.allocator, owned_name);

        const param_nodes = self.ast.extraSlice(node.data.lhs);
        const param_names = try self.allocator.alloc([]const u8, param_nodes.len);
        for (param_nodes, 0..) |p, i| {
            param_names[i] = self.ast.tokenSlice(self.ast.nodes[p].main_token);
        }

        // rhs = extra -> {body, use_count, use_vars...}
        const body_node = self.ast.extra_data[node.data.rhs];
        const use_count = self.ast.extra_data[node.data.rhs + 1];
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

        try self.functions.append(self.allocator, .{
            .name = owned_name,
            .arity = @intCast(param_nodes.len),
            .params = param_names[0..param_nodes.len],
            .chunk = sub.chunk,
        });

        for (sub.functions.items) |f| try self.functions.append(self.allocator, f);
        sub.functions.deinit(self.allocator);
        for (sub.string_allocs.items) |s| try self.string_allocs.append(self.allocator, s);
        sub.string_allocs.deinit(self.allocator);

        const idx = try self.addConstant(.{ .string = owned_name });
        try self.emitConstant(idx);

        for (use_vars) |use_var_node| {
            const var_name = self.ast.tokenSlice(self.ast.nodes[use_var_node].main_token);
            const var_idx = try self.addConstant(.{ .string = var_name });
            try self.emitOp(.closure_bind);
            try self.emitU16(var_idx);
        }
    }

    // ==================================================================
    // calls
    // ==================================================================

    fn compileCall(self: *Compiler, node: Ast.Node) Error!void {
        const callee = self.ast.nodes[node.data.lhs];
        const args = self.ast.extraSlice(node.data.rhs);

        // check if any arg is a splat expression
        var has_splat = false;
        for (args) |arg_idx| {
            if (self.ast.nodes[arg_idx].tag == .splat_expr) {
                has_splat = true;
                break;
            }
        }

        if (has_splat) {
            // build args array: array_new, then push/spread each arg
            try self.emitOp(.array_new);
            for (args) |arg_idx| {
                const arg_node = self.ast.nodes[arg_idx];
                if (arg_node.tag == .splat_expr) {
                    try self.compileNode(arg_node.data.lhs);
                    try self.emitOp(.array_spread);
                } else {
                    try self.compileNode(arg_idx);
                    try self.emitOp(.array_push);
                }
            }
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

    fn compileArrayAccess(self: *Compiler, node: Ast.Node) Error!void {
        try self.compileNode(node.data.lhs);
        try self.compileNode(node.data.rhs);
        try self.emitOp(.array_get);
    }

    fn compileForeach(self: *Compiler, node: Ast.Node) Error!void {
        const iter_n = self.ast.extra_data[node.data.lhs];
        const val_n = self.ast.extra_data[node.data.lhs + 1];
        const key_n = self.ast.extra_data[node.data.lhs + 2];

        const prev_start = self.loop_start;
        var prev_breaks = self.break_jumps;
        var prev_continues = self.continue_jumps;
        self.break_jumps = .{};
        self.continue_jumps = .{};
        self.loop_depth += 1;

        try self.compileNode(iter_n);
        try self.emitOp(.iter_begin);

        const loop_top = self.chunk.offset();
        self.loop_start = loop_top;

        const exit_jump = try self.emitJump(.iter_check);

        const val_name = self.ast.tokenSlice(self.ast.nodes[val_n].main_token);
        const val_idx = try self.addConstant(.{ .string = val_name });
        try self.emitOp(.set_var);
        try self.emitU16(val_idx);
        try self.emitOp(.pop);

        if (key_n != 0) {
            const key_name = self.ast.tokenSlice(self.ast.nodes[key_n].main_token);
            const key_idx = try self.addConstant(.{ .string = key_name });
            try self.emitOp(.set_var);
            try self.emitU16(key_idx);
            try self.emitOp(.pop);
        } else {
            try self.emitOp(.pop);
        }

        try self.compileNode(node.data.rhs);
        try self.emitOp(.iter_advance);
        try self.emitLoop(loop_top);

        self.patchJump(exit_jump);
        try self.emitOp(.iter_end);

        try self.patchBreaks(&prev_breaks);
        try self.patchContinues(&prev_continues);
        self.break_jumps = prev_breaks;
        self.continue_jumps = prev_continues;
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
