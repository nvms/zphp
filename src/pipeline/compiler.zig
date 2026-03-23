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
    allocator: Allocator,

    pub fn deinit(self: *CompileResult) void {
        self.chunk.deinit(self.allocator);
        for (self.functions.items) |*f| {
            f.chunk.deinit(self.allocator);
            self.allocator.free(f.params);
        }
        self.functions.deinit(self.allocator);
    }
};

pub fn compile(ast: *const Ast, allocator: Allocator) Error!CompileResult {
    var c = Compiler{
        .ast = ast,
        .chunk = .{},
        .functions = .{},
        .allocator = allocator,
        .scope_depth = 0,
        .loop_start = null,
        .break_jumps = .{},
    };
    errdefer {
        c.chunk.deinit(allocator);
        for (c.functions.items) |*f| f.chunk.deinit(allocator);
        c.functions.deinit(allocator);
        c.break_jumps.deinit(allocator);
    }

    const root = ast.nodes[0];
    for (ast.extraSlice(root.data.lhs)) |stmt| {
        try c.compileNode(stmt);
    }
    try c.emitOp(.halt);

    c.break_jumps.deinit(allocator);
    return .{ .chunk = c.chunk, .functions = c.functions, .allocator = allocator };
}

const Compiler = struct {
    ast: *const Ast,
    chunk: Chunk,
    functions: std.ArrayListUnmanaged(ObjFunction),
    allocator: Allocator,
    scope_depth: u32,
    loop_start: ?usize,
    break_jumps: std.ArrayListUnmanaged(usize),

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
                const j = try self.emitJump(.jump);
                try self.break_jumps.append(self.allocator, j);
            },
            .continue_stmt => {
                if (self.loop_start) |start| {
                    try self.emitLoop(start);
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
            .foreach_stmt => {},
            .function_decl => try self.compileFunction(node),
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
            .array_access => {},
            .property_access => {},
            .array_literal => {},
            .array_element => {},
            .grouped_expr => try self.compileNode(node.data.lhs),
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
        const str = if (lexeme.len >= 2) lexeme[1 .. lexeme.len - 1] else lexeme;
        const idx = try self.addConstant(.{ .string = str });
        try self.emitConstant(idx);
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

    fn compileWhile(self: *Compiler, node: Ast.Node) Error!void {
        const prev_start = self.loop_start;
        const prev_breaks = self.break_jumps;
        self.break_jumps = .{};

        const loop_top = self.chunk.offset();
        self.loop_start = loop_top;

        try self.compileNode(node.data.lhs);
        const exit_jump = try self.emitJump(.jump_if_false);
        try self.emitOp(.pop);
        try self.compileNode(node.data.rhs);
        try self.emitLoop(loop_top);
        self.patchJump(exit_jump);
        try self.emitOp(.pop);

        for (self.break_jumps.items) |bj| self.patchJump(bj);
        self.break_jumps.deinit(self.allocator);
        self.break_jumps = prev_breaks;
        self.loop_start = prev_start;
    }

    fn compileDoWhile(self: *Compiler, node: Ast.Node) Error!void {
        const prev_start = self.loop_start;
        const prev_breaks = self.break_jumps;
        self.break_jumps = .{};

        const loop_top = self.chunk.offset();
        self.loop_start = loop_top;

        try self.compileNode(node.data.lhs);
        try self.compileNode(node.data.rhs);
        const exit_jump = try self.emitJump(.jump_if_false);
        try self.emitOp(.pop);
        try self.emitLoop(loop_top);
        self.patchJump(exit_jump);
        try self.emitOp(.pop);

        for (self.break_jumps.items) |bj| self.patchJump(bj);
        self.break_jumps.deinit(self.allocator);
        self.break_jumps = prev_breaks;
        self.loop_start = prev_start;
    }

    fn compileFor(self: *Compiler, node: Ast.Node) Error!void {
        const init_n = self.ast.extra_data[node.data.lhs];
        const cond_n = self.ast.extra_data[node.data.lhs + 1];
        const update_n = self.ast.extra_data[node.data.lhs + 2];

        const prev_start = self.loop_start;
        const prev_breaks = self.break_jumps;
        self.break_jumps = .{};

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

        if (update_n != 0) {
            try self.compileNode(update_n);
            try self.emitOp(.pop);
        }

        try self.emitLoop(loop_top);

        if (exit_jump) |ej| {
            self.patchJump(ej);
            try self.emitOp(.pop);
        }

        for (self.break_jumps.items) |bj| self.patchJump(bj);
        self.break_jumps.deinit(self.allocator);
        self.break_jumps = prev_breaks;
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
        for (param_nodes, 0..) |p, i| {
            param_names[i] = self.ast.tokenSlice(self.ast.nodes[p].main_token);
        }

        var sub = Compiler{
            .ast = self.ast,
            .chunk = .{},
            .functions = .{},
            .allocator = self.allocator,
            .scope_depth = self.scope_depth + 1,
            .loop_start = null,
            .break_jumps = .{},
        };
        errdefer {
            sub.chunk.deinit(self.allocator);
            sub.break_jumps.deinit(self.allocator);
        }

        try sub.compileNode(node.data.rhs);
        try sub.emitOp(.op_null);
        try sub.emitOp(.return_val);
        sub.break_jumps.deinit(self.allocator);

        try self.functions.append(self.allocator, .{
            .name = name,
            .arity = @intCast(param_nodes.len),
            .params = param_names[0..param_nodes.len],
            .chunk = sub.chunk,
        });

        for (sub.functions.items) |f| try self.functions.append(self.allocator, f);
        sub.functions.deinit(self.allocator);
    }

    // ==================================================================
    // calls
    // ==================================================================

    fn compileCall(self: *Compiler, node: Ast.Node) Error!void {
        const callee = self.ast.nodes[node.data.lhs];

        const args = self.ast.extraSlice(node.data.rhs);
        for (args) |arg| try self.compileNode(arg);

        if (callee.tag == .identifier) {
            const name = self.ast.tokenSlice(callee.main_token);
            const idx = try self.addConstant(.{ .string = name });
            try self.emitOp(.call);
            try self.emitU16(idx);
            try self.emitByte(@intCast(args.len));
        }
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
