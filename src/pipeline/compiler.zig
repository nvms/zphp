const std = @import("std");
const Ast = @import("ast.zig").Ast;
const Token = @import("token.zig").Token;
const Chunk = @import("bytecode.zig").Chunk;
const OpCode = @import("bytecode.zig").OpCode;
const ObjFunction = @import("bytecode.zig").ObjFunction;
const Value = @import("../runtime/value.zig").Value;

const compiler_strings = @import("compiler_strings.zig");
const compiler_expr = @import("compiler_expr.zig");
const compiler_stmt = @import("compiler_stmt.zig");
const compiler_class = @import("compiler_class.zig");

const Allocator = std.mem.Allocator;
const Error = Allocator.Error || error{CompileError};

pub const CompileResult = struct {
    chunk: Chunk,
    functions: std.ArrayListUnmanaged(ObjFunction),
    string_allocs: std.ArrayListUnmanaged([]const u8),
    allocator: Allocator,
    local_count: u16 = 0,
    slot_names: []const []const u8 = &.{},

    pub fn deinit(self: *CompileResult) void {
        self.chunk.deinit(self.allocator);
        for (self.functions.items) |*f| {
            f.chunk.deinit(self.allocator);
            self.allocator.free(f.params);
            if (f.defaults.len > 0) self.allocator.free(f.defaults);
            if (f.ref_params.len > 0) self.allocator.free(f.ref_params);
            if (f.slot_names.len > 0) self.allocator.free(f.slot_names);
        }
        self.functions.deinit(self.allocator);
        for (self.string_allocs.items) |s| self.allocator.free(s);
        self.string_allocs.deinit(self.allocator);
        if (self.slot_names.len > 0) self.allocator.free(self.slot_names);
    }
};

pub fn compile(ast: *const Ast, allocator: Allocator) Error!CompileResult {
    return compileWithPath(ast, allocator, "");
}

pub fn compileWithPath(ast: *const Ast, allocator: Allocator, file_path: []const u8) Error!CompileResult {
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
        .file_path = file_path,
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
    var tp_iter = c.trait_properties.valueIterator();
    while (tp_iter.next()) |v| allocator.free(v.*);
    c.trait_properties.deinit(allocator);
    const slot_names = try c.buildSlotNames();
    const local_count = c.next_slot;
    c.local_slots.deinit(allocator);
    return .{ .chunk = c.chunk, .functions = c.functions, .string_allocs = c.string_allocs, .allocator = allocator, .local_count = local_count, .slot_names = slot_names };
}

pub const Compiler = struct {
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
    is_generator: bool = false,
    namespace: []const u8 = "",
    use_aliases: std.StringHashMapUnmanaged([]const u8) = .{},
    file_path: []const u8 = "",
    trait_properties: std.StringHashMapUnmanaged([]const u32) = .{},
    local_slots: std.StringHashMapUnmanaged(u16) = .{},
    next_slot: u16 = 0,

    pub const LoopJump = struct {
        offset: usize,
        depth: u32,
    };

    // ==================================================================
    // node dispatch
    // ==================================================================

    pub fn compileNode(self: *Compiler, idx: u32) Error!void {
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
                if (self.is_generator) {
                    if (node.data.lhs != 0) {
                        try self.compileNode(node.data.lhs);
                    } else {
                        try self.emitOp(.op_null);
                    }
                    try self.emitOp(.generator_return);
                } else {
                    if (node.data.lhs != 0) {
                        try self.compileNode(node.data.lhs);
                        try self.emitOp(.return_val);
                    } else {
                        try self.emitOp(.return_void);
                    }
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
            .if_simple => try compiler_stmt.compileIfSimple(self, node),
            .if_else => try compiler_stmt.compileIfElse(self, node),
            .while_stmt => try compiler_stmt.compileWhile(self, node),
            .do_while => try compiler_stmt.compileDoWhile(self, node),
            .for_stmt => try compiler_stmt.compileFor(self, node),
            .foreach_stmt => try compiler_stmt.compileForeach(self, node),
            .function_decl => try compiler_class.compileFunction(self, node),
            .const_decl => {
                try self.compileNode(node.data.lhs);
                const name = self.ast.tokenSlice(node.main_token);
                const name_idx = try self.addConstant(.{ .string = name });
                try self.emitOp(.define_const);
                try self.emitU16(name_idx);
            },
            .switch_stmt => try compiler_stmt.compileSwitch(self, node),
            .switch_case, .switch_default => {},
            .match_expr => try compiler_stmt.compileMatch(self, node),
            .match_arm => {},
            .closure_expr => try compiler_class.compileClosure(self, node),
            .cast_expr => try compiler_expr.compileCast(self, node),
            .inline_html => {
                const text = self.ast.tokenSlice(node.main_token);
                const idx2 = try self.addConstant(.{ .string = text });
                try self.emitConstant(idx2);
                try self.emitOp(.echo);
            },
            .integer_literal => try self.compileInteger(node),
            .float_literal => try self.compileFloat(node),
            .string_literal => try compiler_strings.compileString(self, node),
            .true_literal => try self.emitOp(.op_true),
            .false_literal => try self.emitOp(.op_false),
            .null_literal => try self.emitOp(.op_null),
            .variable => try self.compileGetVar(node),
            .identifier => try self.compileGetVar(node),
            .binary_op => try compiler_expr.compileBinaryOp(self, node),
            .assign => try compiler_expr.compileAssign(self, node),
            .prefix_op => try compiler_expr.compilePrefixOp(self, node),
            .postfix_op => try compiler_expr.compilePostfixOp(self, node),
            .logical_and => try compiler_expr.compileLogicalAnd(self, node),
            .logical_or => try compiler_expr.compileLogicalOr(self, node),
            .null_coalesce => try compiler_expr.compileNullCoalesce(self, node),
            .ternary => try compiler_expr.compileTernary(self, node),
            .call => try compiler_expr.compileCall(self, node),
            .callable_ref => try compiler_expr.compileCallableRef(self, node),
            .array_access => try compiler_expr.compileArrayAccess(self, node),
            .array_push_target => {},
            .list_destructure => {},
            .named_arg => try self.compileNode(node.data.lhs),
            .property_access => try compiler_expr.compilePropertyAccess(self, node),
            .nullsafe_property_access => try compiler_expr.compileNullsafePropertyAccess(self, node),
            .nullsafe_method_call => try compiler_expr.compileNullsafeMethodCall(self, node),
            .throw_expr => try compiler_stmt.compileThrow(self, node),
            .try_catch => try compiler_stmt.compileTryCatch(self, node),
            .catch_clause => {},
            .class_decl => try compiler_class.compileClassDecl(self, node),
            .class_method, .class_property, .static_class_method, .static_class_property => {},
            .interface_decl => try compiler_class.compileInterfaceDecl(self, node),
            .interface_method => {},
            .trait_decl => try compiler_class.compileTraitDecl(self, node),
            .trait_use, .trait_insteadof, .trait_as => {},
            .enum_decl => try compiler_class.compileEnumDecl(self, node),
            .enum_case => {},
            .new_expr => try compiler_expr.compileNewExpr(self, node),
            .method_call => try compiler_expr.compileMethodCall(self, node),
            .static_call => try compiler_expr.compileStaticCall(self, node),
            .static_prop_access => try compiler_expr.compileStaticPropAccess(self, node),
            .yield_expr => try compiler_expr.compileYield(self, node),
            .yield_pair_expr => try compiler_expr.compileYieldPair(self, node),
            .yield_from_expr => try compiler_expr.compileYieldFrom(self, node),
            .expr_list => {
                const exprs = self.ast.extraSlice(node.data.lhs);
                for (exprs, 0..) |expr, i| {
                    if (i > 0) try self.emitOp(.pop);
                    try self.compileNode(expr);
                }
            },
            .array_literal => try compiler_expr.compileArrayLiteral(self, node),
            .array_element => {},
            .array_spread => {},
            .grouped_expr => try self.compileNode(node.data.lhs),
            .global_stmt => try compiler_stmt.compileGlobal(self, node),
            .static_var => try compiler_stmt.compileStaticVar(self, node),
            .splat_expr => {},
            .require_expr => try compiler_stmt.compileRequire(self, node),
            .namespace_decl => try compiler_stmt.compileNamespace(self, node),
            .use_stmt => try compiler_stmt.compileUse(self, node),
            .qualified_name => {
                const parts = self.ast.extraSlice(node.data.lhs);
                const fqn = try self.buildQualifiedString(parts);
                const ci = try self.addConstant(.{ .string = fqn });
                try self.emitConstant(ci);
            },
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

    // ==================================================================
    // variables
    // ==================================================================

    pub fn compileGetVar(self: *Compiler, node: Ast.Node) Error!void {
        const name = self.ast.tokenSlice(node.main_token);

        if (std.mem.eql(u8, name, "__DIR__")) {
            const dir = self.getFileDir();
            const idx = try self.addConstant(.{ .string = dir });
            try self.emitConstant(idx);
            return;
        }
        if (std.mem.eql(u8, name, "__FILE__")) {
            const path = if (self.file_path.len > 0) self.file_path else "";
            const idx = try self.addConstant(.{ .string = path });
            try self.emitConstant(idx);
            return;
        }

        try self.emitGetVar(name);
    }

    fn getFileDir(self: *Compiler) []const u8 {
        if (self.file_path.len == 0) return ".";
        var i: usize = self.file_path.len;
        while (i > 0) {
            i -= 1;
            if (self.file_path[i] == '/' or self.file_path[i] == '\\') {
                return if (i == 0) "/" else self.file_path[0..i];
            }
        }
        return ".";
    }

    // ==================================================================
    // destructuring
    // ==================================================================

    pub fn compileDestructure(self: *Compiler, target: Ast.Node) Error!void {
        if (target.tag == .list_destructure) {
            const slots = self.ast.extraSlice(target.data.lhs);
            for (slots, 0..) |slot, i| {
                if (slot == 0) continue;
                const slot_node = self.ast.nodes[slot];
                try self.emitOp(.dup);
                const key_idx = try self.addConstant(.{ .int = @intCast(i) });
                try self.emitOp(.constant);
                try self.emitU16(key_idx);
                try self.emitOp(.array_get);
                if (slot_node.tag == .list_destructure) {
                    try self.compileDestructure(slot_node);
                    try self.emitOp(.pop);
                } else {
                    const name = self.ast.tokenSlice(slot_node.main_token);
                    try self.emitSetVar(name);
                    try self.emitOp(.pop);
                }
            }
        } else if (target.tag == .array_literal) {
            const elements = self.ast.extraSlice(target.data.lhs);
            for (elements, 0..) |elem_idx, i| {
                const elem = self.ast.nodes[elem_idx];
                if (elem.tag != .array_element) continue;
                const val_node = self.ast.nodes[elem.data.lhs];
                try self.emitOp(.dup);
                if (elem.data.rhs != 0) {
                    try self.compileNode(elem.data.rhs);
                } else {
                    const key_idx = try self.addConstant(.{ .int = @intCast(i) });
                    try self.emitOp(.constant);
                    try self.emitU16(key_idx);
                }
                try self.emitOp(.array_get);
                if (val_node.tag == .list_destructure or val_node.tag == .array_literal) {
                    try self.compileDestructure(val_node);
                    try self.emitOp(.pop);
                } else {
                    const name = self.ast.tokenSlice(val_node.main_token);
                    try self.emitSetVar(name);
                    try self.emitOp(.pop);
                }
            }
        }
    }

    // ==================================================================
    // const expression evaluation
    // ==================================================================

    pub fn evalConstExpr(self: *Compiler, idx: u32) Value {
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
                const tok_tag = self.ast.tokens[n.main_token].tag;
                if (tok_tag == .heredoc or tok_tag == .nowdoc) {
                    const body = compiler_strings.extractHeredocBody(self, n.main_token) catch "";
                    break :blk .{ .string = body };
                }
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

    // ==================================================================
    // name resolution
    // ==================================================================

    pub fn resolveClassName(self: *Compiler, name: []const u8) []const u8 {
        if (name.len > 0 and name[0] == '\\') return name[1..];
        if (self.use_aliases.get(name)) |fqn| return fqn;
        if (self.namespace.len == 0) return name;
        const qualified = std.fmt.allocPrint(self.allocator, "{s}\\{s}", .{ self.namespace, name }) catch return name;
        self.string_allocs.append(self.allocator, qualified) catch return name;
        return qualified;
    }

    pub fn buildQualifiedString(self: *Compiler, parts: []const u32) Error![]const u8 {
        if (parts.len == 1) return self.ast.tokenSlice(parts[0]);
        var buf = std.ArrayListUnmanaged(u8){};
        defer buf.deinit(self.allocator);
        for (parts, 0..) |tok_idx, i| {
            if (i > 0) try buf.append(self.allocator, '\\');
            try buf.appendSlice(self.allocator, self.ast.tokenSlice(tok_idx));
        }
        const owned = try self.allocator.dupe(u8, buf.items);
        try self.string_allocs.append(self.allocator, owned);
        return owned;
    }

    pub fn propName(self: *Compiler, node: Ast.Node) []const u8 {
        const prop_node = self.ast.nodes[node.data.rhs];
        var name = self.ast.tokenSlice(prop_node.main_token);
        if (name.len > 0 and name[0] == '$') name = name[1..];
        return name;
    }

    // ==================================================================
    // loop helpers
    // ==================================================================

    pub fn patchBreaks(self: *Compiler, prev_breaks: *std.ArrayListUnmanaged(LoopJump)) Error!void {
        for (self.break_jumps.items) |bj| {
            if (bj.depth < self.loop_depth) {
                try prev_breaks.append(self.allocator, bj);
            } else {
                self.patchJump(bj.offset);
            }
        }
        self.break_jumps.deinit(self.allocator);
    }

    pub fn patchContinues(self: *Compiler, prev_continues: *std.ArrayListUnmanaged(LoopJump)) Error!void {
        for (self.continue_jumps.items) |cj| {
            if (cj.depth < self.loop_depth) {
                try prev_continues.append(self.allocator, cj);
            } else {
                self.patchJump(cj.offset);
            }
        }
        self.continue_jumps.deinit(self.allocator);
    }

    // ==================================================================
    // slot management
    // ==================================================================

    pub fn getOrCreateSlot(self: *Compiler, name: []const u8) u16 {
        if (self.local_slots.get(name)) |slot| return slot;
        const slot = self.next_slot;
        self.local_slots.put(self.allocator, name, slot) catch return slot;
        self.next_slot += 1;
        return slot;
    }

    fn inFunctionScope(self: *Compiler) bool {
        return self.scope_depth > 0;
    }

    pub fn buildSlotNames(self: *Compiler) Error![]const []const u8 {
        if (self.next_slot == 0) return &.{};
        const names = try self.allocator.alloc([]const u8, self.next_slot);
        @memset(names, "");
        var it = self.local_slots.iterator();
        while (it.next()) |entry| {
            names[entry.value_ptr.*] = entry.key_ptr.*;
        }
        return names;
    }

    // ==================================================================
    // variable emit helpers
    // ==================================================================

    pub fn emitGetVar(self: *Compiler, name: []const u8) Error!void {
        if (self.local_slots.get(name)) |slot| {
            try self.emitOp(.get_local);
            try self.emitU16(slot);
            return;
        }
        if (!self.inFunctionScope() and name.len > 0 and name[0] == '$') {
            const slot = self.getOrCreateSlot(name);
            try self.emitOp(.get_local);
            try self.emitU16(slot);
            return;
        }
        const idx = try self.addConstant(.{ .string = name });
        try self.emitOp(.get_var);
        try self.emitU16(idx);
    }

    pub fn emitSetVar(self: *Compiler, name: []const u8) Error!void {
        if (self.inFunctionScope() or (name.len > 0 and name[0] == '$')) {
            const slot = self.getOrCreateSlot(name);
            try self.emitOp(.set_local);
            try self.emitU16(slot);
            return;
        }
        const idx = try self.addConstant(.{ .string = name });
        try self.emitOp(.set_var);
        try self.emitU16(idx);
    }

    // ==================================================================
    // bytecode emit helpers
    // ==================================================================

    pub fn emitOp(self: *Compiler, op: OpCode) Error!void {
        try self.chunk.write(self.allocator, @intFromEnum(op), 0);
    }

    pub fn emitByte(self: *Compiler, byte: u8) Error!void {
        try self.chunk.write(self.allocator, byte, 0);
    }

    pub fn emitU16(self: *Compiler, val: u16) Error!void {
        try self.emitByte(@intCast(val >> 8));
        try self.emitByte(@intCast(val & 0xff));
    }

    pub fn emitConstant(self: *Compiler, idx: u16) Error!void {
        try self.emitOp(.constant);
        try self.emitU16(idx);
    }

    pub fn emitJump(self: *Compiler, op: OpCode) Error!usize {
        try self.emitOp(op);
        try self.emitU16(0xffff);
        return self.chunk.offset() - 2;
    }

    pub fn patchJump(self: *Compiler, offset: usize) void {
        const dist = self.chunk.offset() - offset - 2;
        self.chunk.code.items[offset] = @intCast(dist >> 8);
        self.chunk.code.items[offset + 1] = @intCast(dist & 0xff);
    }

    pub fn emitLoop(self: *Compiler, loop_start_val: usize) Error!void {
        try self.emitOp(.jump_back);
        const dist = self.chunk.offset() - loop_start_val + 2;
        try self.emitU16(@intCast(dist));
    }

    pub fn addConstant(self: *Compiler, value: Value) Error!u16 {
        return self.chunk.addConstant(self.allocator, value);
    }

    // ==================================================================
    // number parsing
    // ==================================================================

    pub fn parsePhpInt(s: []const u8) i64 {
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
