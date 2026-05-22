const std = @import("std");
const Ast = @import("ast.zig").Ast;
const Token = @import("token.zig").Token;
const bytecode = @import("bytecode.zig");
const Chunk = bytecode.Chunk;
const OpCode = bytecode.OpCode;
const ObjFunction = bytecode.ObjFunction;
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const vm_mod = @import("../runtime/vm.zig");

const compiler_strings = @import("compiler_strings.zig");
const compiler_expr = @import("compiler_expr.zig");
const compiler_stmt = @import("compiler_stmt.zig");
const compiler_class = @import("compiler_class.zig");

const Allocator = std.mem.Allocator;
const Error = Allocator.Error || error{CompileError};

var global_closure_counter: u32 = 0;

pub const TypeHint = struct {
    name: []const u8,
    param_types: []const []const u8 = &.{},
    return_type: []const u8 = "",
};

pub const FunctionAttrEntry = struct {
    name: []const u8,
    attrs: []const vm_mod.AttributeDef,
};

pub const CompileResult = struct {
    chunk: Chunk,
    functions: std.ArrayListUnmanaged(ObjFunction),
    string_allocs: std.ArrayListUnmanaged([]const u8),
    allocator: Allocator,
    local_count: u16 = 0,
    slot_names: []const []const u8 = &.{},
    type_hints: std.ArrayListUnmanaged(TypeHint) = .{},
    function_attrs: std.ArrayListUnmanaged(FunctionAttrEntry) = .{},
    new_defaults: std.ArrayListUnmanaged(*bytecode.NewDefault) = .{},
    deferred_exprs: std.ArrayListUnmanaged(*bytecode.DeferredExpr) = .{},
    source: []const u8 = "",
    file_path: []const u8 = "",
    strict_types: bool = false,

    pub fn deinit(self: *CompileResult) void {
        self.chunk.deinit(self.allocator);
        for (self.functions.items) |*f| {
            f.chunk.deinit(self.allocator);
            self.allocator.free(f.params);
            if (f.defaults.len > 0) {
                for (f.defaults) |d| freeDefaultValue(self.allocator, d);
                self.allocator.free(f.defaults);
            }
            if (f.ref_params.len > 0) self.allocator.free(f.ref_params);
            if (f.slot_names.len > 0) self.allocator.free(f.slot_names);
        }
        self.functions.deinit(self.allocator);
        for (self.string_allocs.items) |s| self.allocator.free(s);
        self.string_allocs.deinit(self.allocator);
        for (self.type_hints.items) |th| {
            if (th.param_types.len > 0) self.allocator.free(th.param_types);
        }
        self.type_hints.deinit(self.allocator);
        self.function_attrs.deinit(self.allocator);
        for (self.new_defaults.items) |nd| {
            for (nd.args) |a| freeDefaultValue(self.allocator, a);
            self.allocator.free(nd.args);
            self.allocator.destroy(nd);
        }
        self.new_defaults.deinit(self.allocator);
        // operands are tracked elsewhere (string_allocs / nested in this same
        // list), so only the structs themselves need freeing
        for (self.deferred_exprs.items) |de| self.allocator.destroy(de);
        self.deferred_exprs.deinit(self.allocator);
        if (self.slot_names.len > 0) self.allocator.free(self.slot_names);
    }
};

fn freeDefaultValue(allocator: Allocator, v: Value) void {
    if (v == .array and !Value.isEmptyArrayDefault(v)) {
        const arr = v.array;
        for (arr.entries.items) |entry| freeDefaultValue(allocator, entry.value);
        arr.deinit(allocator);
        allocator.destroy(arr);
    }
}

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
        .closure_count = global_closure_counter,
    };
    errdefer {
        c.chunk.deinit(allocator);
        for (c.functions.items) |*f| f.chunk.deinit(allocator);
        c.functions.deinit(allocator);
        for (c.string_allocs.items) |s| allocator.free(s);
        c.string_allocs.deinit(allocator);
        c.break_jumps.deinit(allocator);
        c.continue_jumps.deinit(allocator);
        c.use_aliases.deinit(allocator);
        c.use_fn_aliases.deinit(allocator);
        c.use_const_aliases.deinit(allocator);
        c.pending_gotos.deinit(allocator);
        c.labels.deinit(allocator);
    }

    const root = ast.nodes[0];
    for (ast.extraSlice(root.data.lhs)) |stmt| {
        try c.compileNode(stmt);
    }
    for (c.pending_gotos.items) |pg| {
        if (c.labels.get(pg.label)) |target| {
            c.patchJumpTo(pg.offset, target);
        }
    }
    c.pending_gotos.deinit(allocator);
    c.labels.deinit(allocator);
    try c.emitOp(.halt);

    c.break_jumps.deinit(allocator);
    c.continue_jumps.deinit(allocator);
    var tp_iter = c.trait_properties.valueIterator();
    while (tp_iter.next()) |v| allocator.free(v.*);
    c.trait_properties.deinit(allocator);
    c.use_aliases.deinit(allocator);
    c.use_fn_aliases.deinit(allocator);
    c.use_const_aliases.deinit(allocator);
    const slot_names = try c.buildSlotNames();
    const local_count = c.next_slot;
    c.local_slots.deinit(allocator);
    global_closure_counter = c.closure_count;
    const strict = detectStrictTypes(ast.source);
    for (c.functions.items) |*f| f.strict_types = strict;
    return .{ .chunk = c.chunk, .functions = c.functions, .string_allocs = c.string_allocs, .allocator = allocator, .local_count = local_count, .slot_names = slot_names, .type_hints = c.type_hints, .function_attrs = c.function_attrs, .new_defaults = c.new_defaults, .deferred_exprs = c.deferred_exprs, .source = ast.source, .file_path = file_path, .strict_types = strict };
}

fn detectStrictTypes(src: []const u8) bool {
    // declare(strict_types=1) appears at file scope, before any namespace.
    // tolerate whitespace around tokens. we just need a yes/no answer; we
    // don't bother re-parsing the directive
    var i: usize = 0;
    while (i < src.len) {
        const idx = std.mem.indexOfScalarPos(u8, src, i, 'd') orelse return false;
        if (idx + 7 <= src.len and std.mem.eql(u8, src[idx .. idx + 7], "declare")) {
            var j = idx + 7;
            while (j < src.len and (src[j] == ' ' or src[j] == '\t')) j += 1;
            if (j < src.len and src[j] == '(') {
                const end = std.mem.indexOfScalarPos(u8, src, j, ')') orelse return false;
                const inner = src[j + 1 .. end];
                if (std.mem.indexOf(u8, inner, "strict_types") != null and std.mem.indexOf(u8, inner, "1") != null) return true;
                return false;
            }
        }
        i = idx + 1;
    }
    return false;
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
    // when set, nullsafe operators inside the current chain forward their
    // short-circuit jumps here instead of patching them locally. lets a
    // `$x?->y()->z()` chain short-circuit ALL of `z()` (and further links)
    // when $x is null, matching PHP's nullsafe semantics
    nullsafe_chain_jumps: ?*std.ArrayListUnmanaged(usize) = null,
    loop_depth: u32 = 0,
    foreach_depth: u32 = 0,
    loop_is_foreach: [32]bool = [_]bool{false} ** 32,
    // per-foreach: true when the iterable is anonymous (e.g. `gen()`) and
    // therefore should be closed when the loop exits. `break` uses this to
    // pick iter_end_close vs iter_end
    loop_foreach_close: [32]bool = [_]bool{false} ** 32,
    closure_count: u32 = 0,
    is_generator: bool = false,
    namespace: []const u8 = "",
    use_aliases: std.StringHashMapUnmanaged([]const u8) = .{},
    use_fn_aliases: std.StringHashMapUnmanaged([]const u8) = .{},
    use_const_aliases: std.StringHashMapUnmanaged([]const u8) = .{},
    labels: std.StringHashMapUnmanaged(usize) = .{},
    pending_gotos: std.ArrayListUnmanaged(PendingGoto) = .{},
    file_path: []const u8 = "",
    trait_properties: std.StringHashMapUnmanaged([]const u32) = .{},
    local_slots: std.StringHashMapUnmanaged(u16) = .{},
    next_slot: u16 = 0,
    // set on an arrow-function sub-compiler: points at the enclosing
    // compiler. an arrow captures a parent variable lazily - the first time
    // its body references one - so only the variables the body actually uses
    // are captured (PHP semantics), not the whole enclosing scope
    arrow_parent: ?*Compiler = null,
    type_hints: std.ArrayListUnmanaged(TypeHint) = .{},
    function_attrs: std.ArrayListUnmanaged(FunctionAttrEntry) = .{},
    new_defaults: std.ArrayListUnmanaged(*bytecode.NewDefault) = .{},
    deferred_exprs: std.ArrayListUnmanaged(*bytecode.DeferredExpr) = .{},
    current_source_offset: u32 = 0,
    current_class: []const u8 = "",
    current_parent: []const u8 = "",
    current_function: []const u8 = "",
    in_trait: bool = false,
    finally_nodes: [8]u32 = [_]u32{0} ** 8,
    finally_loop_depth: [8]u32 = [_]u32{0} ** 8,
    finally_depth: u32 = 0,

    pub const LoopJump = struct {
        offset: usize,
        depth: u32,
    };

    pub const PendingGoto = struct {
        offset: usize,
        label: []const u8,
        source_offset: usize,
    };

    // ==================================================================
    // node dispatch
    // ==================================================================

    pub fn compileNode(self: *Compiler, idx: u32) Error!void {
        const node = self.ast.nodes[idx];
        self.current_source_offset = self.ast.tokens[node.main_token].start;
        switch (node.tag) {
            .expression_stmt => {
                if (self.tryCompileLocalAssignSuper(node.data.lhs)) |emitted| {
                    if (!emitted) {
                        try self.compileNode(node.data.lhs);
                        try self.emitOp(.pop);
                    }
                } else |_| {
                    try self.compileNode(node.data.lhs);
                    try self.emitOp(.pop);
                }
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
                    // emit finally blocks (innermost first) before generator_return,
                    // matching the non-generator return path. PHP's finally fires
                    // on every exit including generator completion via return
                    const saved_fd = self.finally_depth;
                    var fd = self.finally_depth;
                    while (fd > 0) {
                        fd -= 1;
                        self.finally_depth = fd;
                        try self.emitOp(.pop_handler);
                        try self.compileNode(self.finally_nodes[fd]);
                    }
                    self.finally_depth = saved_fd;
                    try self.emitOp(.generator_return);
                } else {
                    // close suspended generators in active foreach scopes; the
                    // function is returning so the iterables go out of scope
                    var fei: usize = self.loop_depth;
                    while (fei > 0) {
                        fei -= 1;
                        if (fei < 32 and self.loop_is_foreach[fei]) {
                            try self.emitOp(if (self.loop_foreach_close[fei]) .iter_end_close else .iter_end);
                        }
                    }
                    if (node.data.lhs != 0) {
                        try self.compileNode(node.data.lhs);
                    }
                    // emit finally blocks (innermost first) before returning;
                    // temporarily lower finally_depth around each inline emit so
                    // that a return inside the finally itself does not re-enter
                    // its own finally block (would cause infinite recursion)
                    const saved_fd = self.finally_depth;
                    var fd = self.finally_depth;
                    while (fd > 0) {
                        fd -= 1;
                        self.finally_depth = fd;
                        try self.emitOp(.pop_handler);
                        try self.compileNode(self.finally_nodes[fd]);
                    }
                    self.finally_depth = saved_fd;
                    if (node.data.lhs != 0) {
                        try self.emitOp(.return_val);
                    } else {
                        try self.emitOp(.return_void);
                    }
                }
            },
            .break_stmt => {
                const level = if (node.data.lhs > 0) node.data.lhs else 1;
                const target_depth = self.loop_depth -| level;
                // emit any finally blocks declared inside loops being broken
                const saved_fd = self.finally_depth;
                var fd = self.finally_depth;
                while (fd > 0) {
                    fd -= 1;
                    if (self.finally_loop_depth[fd] <= target_depth) break;
                    self.finally_depth = fd;
                    try self.emitOp(.pop_handler);
                    try self.compileNode(self.finally_nodes[fd]);
                }
                self.finally_depth = saved_fd;
                for (target_depth..self.loop_depth) |d| {
                    if (d < 32 and self.loop_is_foreach[d]) {
                        try self.emitOp(if (self.loop_foreach_close[d]) .iter_end_close else .iter_end);
                    }
                }
                const j = try self.emitJump(.jump);
                try self.break_jumps.append(self.allocator, .{
                    .offset = j,
                    .depth = self.loop_depth -| (level - 1),
                });
            },
            .continue_stmt => {
                if (self.loop_start) |start| {
                    const level = if (node.data.lhs > 0) node.data.lhs else 1;
                    // run any finally inside the loop(s) being continued/skipped
                    const target_depth = self.loop_depth -| level;
                    const saved_fd = self.finally_depth;
                    var fd = self.finally_depth;
                    while (fd > 0) {
                        fd -= 1;
                        if (self.finally_loop_depth[fd] <= target_depth) break;
                        self.finally_depth = fd;
                        try self.emitOp(.pop_handler);
                        try self.compileNode(self.finally_nodes[fd]);
                    }
                    self.finally_depth = saved_fd;
                    if (level > 1) {
                        // emit iter_end for inner foreach loops being skipped
                        const skip_target = self.loop_depth -| (level - 1);
                        for (skip_target..self.loop_depth) |d| {
                            if (d < 32 and self.loop_is_foreach[d]) {
                                try self.emitOp(if (self.loop_foreach_close[d]) .iter_end_close else .iter_end);
                            }
                        }
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
                const raw = self.ast.tokenSlice(node.main_token);
                const name = if (self.namespace.len > 0)
                    try std.fmt.allocPrint(self.allocator, "{s}\\{s}", .{ self.namespace, raw })
                else
                    raw;
                if (self.namespace.len > 0) try self.string_allocs.append(self.allocator, name);
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
            .empty_stmt => {},
            .integer_literal => try self.compileInteger(node),
            .float_literal => try self.compileFloat(node),
            .string_literal => try compiler_strings.compileString(self, node),
            .true_literal => try self.emitOp(.op_true),
            .false_literal => try self.emitOp(.op_false),
            .null_literal => try self.emitOp(.op_null),
            .variable => try self.compileGetVar(node),
            .variable_variable => try self.compileVariableVariable(node),
            .identifier => try self.compileGetVar(node),
            .binary_op => try compiler_expr.compileBinaryOp(self, node),
            .pipe_expr => try compiler_expr.compilePipeExpr(self, node),
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
            .ref_target => try self.compileNode(node.data.lhs),
            .named_arg => try self.compileNode(node.data.lhs),
            .property_access => try compiler_expr.compilePropertyAccess(self, node),
            .nullsafe_property_access => try compiler_expr.compileNullsafePropertyAccess(self, node),
            .nullsafe_method_call => try compiler_expr.compileNullsafeMethodCall(self, node),
            .throw_expr => try compiler_stmt.compileThrow(self, node),
            .print_expr => {
                try self.compileNode(node.data.lhs);
                try self.emitOp(.echo);
                const one_idx = try self.addConstant(.{ .int = 1 });
                try self.emitOp(.constant);
                try self.emitU16(one_idx);
            },
            .try_catch => try compiler_stmt.compileTryCatch(self, node),
            .catch_clause => {},
            .class_decl => try compiler_class.compileClassDecl(self, node),
            .class_method, .class_property, .class_property_hooks, .static_class_method, .static_class_property => {},
            .interface_decl => try compiler_class.compileInterfaceDecl(self, node),
            .interface_method => {},
            .trait_decl => try compiler_class.compileTraitDecl(self, node),
            .trait_use, .trait_insteadof, .trait_as => {},
            .enum_decl => try compiler_class.compileEnumDecl(self, node),
            .enum_case => {},
            .new_expr => try compiler_expr.compileNewExpr(self, node),
            .new_expr_dynamic => try compiler_expr.compileNewExprDynamic(self, node),
            .anonymous_class => try compiler_class.compileAnonymousClass(self, node),
            .method_call => try compiler_expr.compileMethodCall(self, node),
            .static_call => try compiler_expr.compileStaticCall(self, node),
            .dynamic_static_call => try compiler_expr.compileDynamicStaticCall(self, node),
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
            .use_fn_stmt => try compiler_stmt.compileUseFn(self, node),
            .use_const_stmt => try compiler_stmt.compileUseConst(self, node),
            .label_stmt => {
                try self.labels.put(self.allocator, self.ast.tokenSlice(node.main_token), self.chunk.offset());
            },
            .goto_stmt => {
                const label = self.ast.tokenSlice(node.main_token);
                if (self.labels.get(label)) |target| {
                    try self.emitLoop(target);
                } else {
                    const j = try self.emitJump(.jump);
                    try self.pending_gotos.append(self.allocator, .{ .offset = j, .label = label, .source_offset = self.current_source_offset });
                }
            },
            .qualified_name => {
                const parts = self.ast.extraSlice(node.data.lhs);
                const fqn = try self.buildQualifiedString(parts);
                // strip leading backslash for root-namespace constant lookup
                const stripped = if (fqn.len > 0 and fqn[0] == '\\') fqn[1..] else fqn;
                // `namespace\CONST` resolves relative to the current namespace
                const name = if (node.data.rhs == 2 and self.namespace.len > 0) blk: {
                    const q = std.fmt.allocPrint(self.allocator, "{s}\\{s}", .{ self.namespace, stripped }) catch return error.CompileError;
                    self.string_allocs.append(self.allocator, q) catch return error.CompileError;
                    break :blk q;
                } else stripped;
                try self.emitGetVar(name);
            },
            .root => {},
        }
    }

    // ==================================================================
    // literals
    // ==================================================================

    fn compileInteger(self: *Compiler, node: Ast.Node) Error!void {
        const lexeme = self.ast.tokenSlice(node.main_token);
        // an integer literal that overflows i64 becomes a float (PHP semantics)
        const idx = try self.addConstant(parsePhpIntLiteral(lexeme));
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
        if (std.mem.eql(u8, name, "__FUNCTION__")) {
            const idx = try self.addConstant(.{ .string = self.current_function });
            try self.emitConstant(idx);
            return;
        }
        if (std.mem.eql(u8, name, "__CLASS__")) {
            // inside a trait the compile-time class is the trait name, but PHP
            // resolves __CLASS__ to the using class - defer to runtime self::class
            if (self.in_trait) {
                const class_idx = try self.addConstant(.{ .string = "self" });
                const prop_idx = try self.addConstant(.{ .string = "class" });
                try self.emitOp(.get_static_prop);
                try self.emitU16(class_idx);
                try self.emitU16(prop_idx);
                return;
            }
            const idx = try self.addConstant(.{ .string = self.current_class });
            try self.emitConstant(idx);
            return;
        }
        if (std.mem.eql(u8, name, "__METHOD__")) {
            const val = if (self.current_class.len > 0 and self.current_function.len > 0) blk: {
                const full = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ self.current_class, self.current_function });
                try self.string_allocs.append(self.allocator, full);
                break :blk full;
            } else if (self.current_function.len > 0)
                self.current_function
            else
                @as([]const u8, "");
            const idx = try self.addConstant(.{ .string = val });
            try self.emitConstant(idx);
            return;
        }
        if (std.mem.eql(u8, name, "__NAMESPACE__")) {
            const ns = if (self.namespace.len > 0) self.namespace else "";
            const idx = try self.addConstant(.{ .string = ns });
            try self.emitConstant(idx);
            return;
        }
        if (std.mem.eql(u8, name, "__TRAIT__")) {
            const val = if (self.in_trait) self.current_class else "";
            const idx = try self.addConstant(.{ .string = val });
            try self.emitConstant(idx);
            return;
        }
        if (std.mem.eql(u8, name, "__LINE__")) {
            const line = self.getLineNumber();
            const idx = try self.addConstant(.{ .int = @intCast(line) });
            try self.emitConstant(idx);
            return;
        }

        // bare identifier (no $) - PHP constant resolution:
        //   1. if `use const X\Y as Z` aliases this name, use that FQN
        //   2. if in a namespace block, prefer `<namespace>\<name>` (runtime
        //      falls back to global by stripping the namespace prefix)
        if (name.len > 0 and name[0] != '$') {
            if (self.use_const_aliases.get(name)) |fqn| {
                try self.emitGetVar(fqn);
                return;
            }
            if (self.namespace.len > 0) {
                const ns_name = try std.fmt.allocPrint(self.allocator, "{s}\\{s}", .{ self.namespace, name });
                try self.string_allocs.append(self.allocator, ns_name);
                try self.emitGetVar(ns_name);
                return;
            }
        }

        try self.emitGetVar(name);
    }

    pub fn compileVariableVariable(self: *Compiler, node: Ast.Node) Error!void {
        const inner = self.ast.nodes[node.data.lhs];
        try self.compileNode(node.data.lhs);
        if (inner.tag == .variable) {
            // $$var - the inner variable's value is a string with the $ prefix, strip it
            // get_var_var expects the name with $ prefix (matching PHP convention)
        }
        try self.emitOp(.get_var_var);
    }

    fn getLineNumber(self: *Compiler) u32 {
        var line: u32 = 1;
        const clamped = @min(self.current_source_offset, self.ast.source.len);
        for (self.ast.source[0..clamped]) |c| {
            if (c == '\n') line += 1;
        }
        return line;
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
                // keyed slot: list('k' => $var) - data.lhs is the target,
                // data.rhs is the key expression
                if (slot_node.tag == .array_element) {
                    const inner_target = self.ast.nodes[slot_node.data.lhs];
                    if (inner_target.tag == .ref_target) {
                        try self.compileDestructureRefSlot(inner_target, .{ .key_node = slot_node.data.rhs });
                        continue;
                    }
                    try self.emitOp(.dup);
                    try self.compileNode(slot_node.data.rhs);
                    try self.emitOp(.array_get);
                    if (inner_target.tag == .list_destructure or inner_target.tag == .array_literal) {
                        try self.compileDestructure(inner_target);
                        try self.emitOp(.pop);
                    } else if (inner_target.tag == .property_access) {
                        try self.compileNode(inner_target.data.lhs);
                        try self.emitOp(.swap);
                        const prop_name = self.propName(inner_target);
                        const prop_idx = try self.addConstant(.{ .string = prop_name });
                        try self.emitOp(.set_prop);
                        try self.emitU16(prop_idx);
                        try self.emitOp(.pop);
                    } else if (inner_target.tag == .array_access or inner_target.tag == .array_push_target) {
                        try self.compileDestructureArraySlot(inner_target);
                    } else {
                        const name = self.ast.tokenSlice(inner_target.main_token);
                        try self.emitSetVar(name);
                        try self.emitOp(.pop);
                    }
                    continue;
                }
                if (slot_node.tag == .ref_target) {
                    try self.compileDestructureRefSlot(slot_node, .{ .index = @intCast(i) });
                    continue;
                }
                try self.emitOp(.dup);
                const key_idx = try self.addConstant(.{ .int = @intCast(i) });
                try self.emitOp(.constant);
                try self.emitU16(key_idx);
                try self.emitOp(.array_get);
                if (slot_node.tag == .list_destructure) {
                    try self.compileDestructure(slot_node);
                    try self.emitOp(.pop);
                } else if (slot_node.tag == .property_access) {
                    try self.compileNode(slot_node.data.lhs);
                    try self.emitOp(.swap);
                    const prop_name = self.propName(slot_node);
                    const prop_idx = try self.addConstant(.{ .string = prop_name });
                    try self.emitOp(.set_prop);
                    try self.emitU16(prop_idx);
                    try self.emitOp(.pop);
                } else if (slot_node.tag == .array_access or slot_node.tag == .array_push_target) {
                    try self.compileDestructureArraySlot(slot_node);
                } else {
                    const name = self.ast.tokenSlice(slot_node.main_token);
                    try self.emitSetVar(name);
                    try self.emitOp(.pop);
                }
            }
        } else if (target.tag == .array_literal) {
            const elements = self.ast.extraSlice(target.data.lhs);
            for (elements, 0..) |elem_idx, i| {
                if (elem_idx == 0) continue;
                const elem = self.ast.nodes[elem_idx];
                if (elem.tag != .array_element) continue;
                const val_node = self.ast.nodes[elem.data.lhs];
                if (val_node.tag == .ref_target) {
                    if (elem.data.rhs != 0) {
                        try self.compileDestructureRefSlot(val_node, .{ .key_node = elem.data.rhs });
                    } else {
                        try self.compileDestructureRefSlot(val_node, .{ .index = @intCast(i) });
                    }
                    continue;
                }
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
                } else if (val_node.tag == .property_access) {
                    try self.compileNode(val_node.data.lhs);
                    try self.emitOp(.swap);
                    const prop_name = self.propName(val_node);
                    const prop_idx = try self.addConstant(.{ .string = prop_name });
                    try self.emitOp(.set_prop);
                    try self.emitU16(prop_idx);
                    try self.emitOp(.pop);
                } else if (val_node.tag == .array_access or val_node.tag == .array_push_target) {
                    try self.compileDestructureArraySlot(val_node);
                } else {
                    const name = self.ast.tokenSlice(val_node.main_token);
                    try self.emitSetVar(name);
                    try self.emitOp(.pop);
                }
            }
        }
    }

    // writes the value on top of the stack into an array-access destructure
    // target ($arr[$key]). stack: [source, value] -> [source]
    fn compileDestructureArraySlot(self: *Compiler, slot_node: Ast.Node) Error!void {
        try compiler_expr.compileVivifyChain(self, slot_node.data.lhs);
        try self.emitOp(.swap);
        if (slot_node.tag == .array_push_target) {
            try self.emitOp(.array_push);
            try self.emitOp(.pop);
            return;
        }
        try self.compileNode(slot_node.data.rhs);
        try self.emitOp(.swap);
        try self.emitOp(.array_set);
        try self.emitOp(.pop);
    }

    const RefSlotKey = union(enum) { index: i64, key_node: u32 };

    fn compileDestructureRefSlot(self: *Compiler, ref_node: Ast.Node, key: RefSlotKey) Error!void {
        const inner = self.ast.nodes[ref_node.data.lhs];
        if (inner.tag != .variable) return;
        const name = self.ast.tokenSlice(inner.main_token);
        const name_idx = try self.addConstant(.{ .string = name });
        try self.emitOp(.dup);
        switch (key) {
            .index => |i| {
                const ki = try self.addConstant(.{ .int = i });
                try self.emitOp(.constant);
                try self.emitU16(ki);
            },
            .key_node => |kn| try self.compileNode(kn),
        }
        try self.emitOp(.bind_array_ref);
        try self.emitU16(name_idx);
    }

    // ==================================================================
    // const expression evaluation
    // ==================================================================

    // stringify a folded constant scalar for compile-time concat. returns null
    // for values that can't be folded here (arrays, deferred-constant /
    // deferred-new sentinel strings, float - whose display format is resolved
    // at runtime)
    fn constScalarToStr(self: *Compiler, v: Value) ?[]const u8 {
        return switch (v) {
            .string => |s| blk: {
                // reject sentinel-encoded deferred values (\x00CC.. / \x00NW..)
                if (s.len >= 3 and s[0] == 0) break :blk null;
                break :blk s;
            },
            .int => |i| blk: {
                const buf = std.fmt.allocPrint(self.allocator, "{d}", .{i}) catch break :blk null;
                self.string_allocs.append(self.allocator, buf) catch break :blk null;
                break :blk buf;
            },
            .bool => |b| if (b) "1" else "",
            .null => "",
            else => null,
        };
    }

    // a compound const-expression default that can't be folded now (an operand
    // is a deferred constant sentinel) - heap a DeferredExpr and return its
    // sentinel; resolveDefault applies the op at call time
    fn makeDeferredExpr(self: *Compiler, op: bytecode.DeferredExpr.Op, lhs: Value, rhs: Value) Value {
        const de = self.allocator.create(bytecode.DeferredExpr) catch return Value.null;
        de.* = .{ .op = op, .lhs = lhs, .rhs = rhs };
        self.deferred_exprs.append(self.allocator, de) catch {
            self.allocator.destroy(de);
            return Value.null;
        };
        const sentinel = bytecode.encodeDeferredExprSentinel(self.allocator, de) catch return Value.null;
        self.string_allocs.append(self.allocator, sentinel) catch return Value.null;
        return .{ .string = sentinel };
    }

    pub fn evalConstExpr(self: *Compiler, idx: u32) Value {
        const n = self.ast.nodes[idx];
        return switch (n.tag) {
            .integer_literal => parsePhpIntLiteral(self.ast.tokenSlice(n.main_token)),
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
                if (raw.len < 2) break :blk .{ .string = raw };
                const quote = raw[0];
                const inner = raw[1 .. raw.len - 1];
                // process escape sequences the same way the regular string
                // compile path does - a bare quote-strip leaves '\\' / '\n'
                // literal, which is wrong (surfaces in constant-expression
                // defaults like `self::NS . '\\Default'`)
                if (quote == '\'') {
                    if (compiler_strings.processSingleQuoteEscapes(self.allocator, inner) catch null) |p| {
                        self.string_allocs.append(self.allocator, p) catch break :blk .{ .string = inner };
                        break :blk .{ .string = p };
                    }
                    break :blk .{ .string = inner };
                }
                if (std.mem.indexOfScalar(u8, inner, '\\') != null) {
                    const p = compiler_strings.processEscapes(self.allocator, inner) catch break :blk .{ .string = inner };
                    self.string_allocs.append(self.allocator, p) catch break :blk .{ .string = inner };
                    break :blk .{ .string = p };
                }
                break :blk .{ .string = inner };
            },
            .true_literal => .{ .bool = true },
            .false_literal => .{ .bool = false },
            .null_literal => .null,
            .grouped_expr => self.evalConstExpr(n.data.lhs),
            .prefix_op => blk: {
                const tok = self.ast.tokens[n.main_token];
                if (tok.tag == .minus) {
                    const inner = self.evalConstExpr(n.data.lhs);
                    switch (inner) {
                        .int => |v| break :blk Value{ .int = -v },
                        .float => |v| break :blk Value{ .float = -v },
                        // -CONST where CONST is a deferred constant sentinel
                        .string => break :blk self.makeDeferredExpr(.neg, inner, Value.null),
                        else => {},
                    }
                }
                if (tok.tag == .plus) {
                    const inner = self.evalConstExpr(n.data.lhs);
                    switch (inner) {
                        .int, .float => break :blk inner,
                        // +CONST is numeric identity for an already-numeric
                        // constant - resolve to the constant value itself
                        .string => break :blk inner,
                        else => {},
                    }
                }
                break :blk .null;
            },
            .binary_op => blk: {
                const tok = self.ast.tokens[n.main_token];
                const lhs = self.evalConstExpr(n.data.lhs);
                const rhs = self.evalConstExpr(n.data.rhs);
                if (lhs == .int and rhs == .int) {
                    break :blk switch (tok.tag) {
                        .pipe => Value{ .int = lhs.int | rhs.int },
                        .amp => Value{ .int = lhs.int & rhs.int },
                        .caret => Value{ .int = lhs.int ^ rhs.int },
                        .plus => Value{ .int = lhs.int +% rhs.int },
                        .minus => Value{ .int = lhs.int -% rhs.int },
                        .star => Value{ .int = lhs.int *% rhs.int },
                        .lt_lt => if (rhs.int >= 0 and rhs.int < 64) Value{ .int = lhs.int << @intCast(rhs.int) } else Value.null,
                        .gt_gt => if (rhs.int >= 0 and rhs.int < 64) Value{ .int = lhs.int >> @intCast(rhs.int) } else Value.null,
                        .percent => if (rhs.int != 0) Value{ .int = @rem(lhs.int, rhs.int) } else Value.null,
                        .star_star => blk2: {
                            if (rhs.int < 0) break :blk2 Value.null;
                            var acc: i64 = 1;
                            var e: i64 = 0;
                            while (e < rhs.int) : (e += 1) acc *%= lhs.int;
                            break :blk2 Value{ .int = acc };
                        },
                        .lt => Value{ .bool = lhs.int < rhs.int },
                        .gt => Value{ .bool = lhs.int > rhs.int },
                        .lt_equal => Value{ .bool = lhs.int <= rhs.int },
                        .gt_equal => Value{ .bool = lhs.int >= rhs.int },
                        .equal_equal => Value{ .bool = lhs.int == rhs.int },
                        .equal_equal_equal => Value{ .bool = lhs.int == rhs.int },
                        .bang_equal, .lt_gt => Value{ .bool = lhs.int != rhs.int },
                        .bang_equal_equal => Value{ .bool = lhs.int != rhs.int },
                        .spaceship => Value{ .int = if (lhs.int < rhs.int) @as(i64, -1) else if (lhs.int > rhs.int) @as(i64, 1) else @as(i64, 0) },
                        else => Value.null,
                    };
                }
                // string concat in a constant default: 'a' . 'b', and chains.
                // fold when both operands are concrete scalars; otherwise defer
                // (an operand is a constant sentinel resolved at call time)
                if (tok.tag == .dot) {
                    if (constScalarToStr(self, lhs)) |ls| {
                        if (constScalarToStr(self, rhs)) |rs| {
                            const joined = std.fmt.allocPrint(self.allocator, "{s}{s}", .{ ls, rs }) catch break :blk .null;
                            self.string_allocs.append(self.allocator, joined) catch break :blk .null;
                            break :blk .{ .string = joined };
                        }
                    }
                    break :blk self.makeDeferredExpr(.concat, lhs, rhs);
                }
                // a compound arithmetic/bitwise expression that didn't fold -
                // an operand is a deferred constant. defer the whole op
                const dop: ?bytecode.DeferredExpr.Op = switch (tok.tag) {
                    .pipe => .bor,
                    .amp => .band,
                    .caret => .bxor,
                    .plus => .add,
                    .minus => .sub,
                    .star => .mul,
                    .slash => .div,
                    .percent => .mod,
                    .lt_lt => .shl,
                    .gt_gt => .shr,
                    .star_star => .pow,
                    else => null,
                };
                if (dop) |o| break :blk self.makeDeferredExpr(o, lhs, rhs);
                break :blk .null;
            },
            .ternary => blk: {
                // constant-expression ternary default: cond ? then : else.
                // node layout: lhs = condition, extra_data[rhs] = then node
                // (0 for short ternary $a ?: $b), extra_data[rhs+1] = else node
                const cond = self.evalConstExpr(n.data.lhs);
                if (n.data.rhs + 1 >= self.ast.extra_data.len) break :blk .null;
                const then_node = self.ast.extra_data[n.data.rhs];
                const else_node = self.ast.extra_data[n.data.rhs + 1];
                const truthy = switch (cond) {
                    .bool => |b| b,
                    .int => |i| i != 0,
                    .float => |f| f != 0,
                    .string => |s| s.len != 0 and !std.mem.eql(u8, s, "0"),
                    .null => false,
                    else => break :blk .null,
                };
                if (truthy) {
                    if (then_node == 0) break :blk cond;
                    break :blk self.evalConstExpr(then_node);
                }
                break :blk self.evalConstExpr(else_node);
            },
            .array_literal => blk: {
                const elems = self.ast.extraSlice(n.data.lhs);
                if (elems.len == 0) break :blk Value.empty_array_default;
                const arr = self.allocator.create(PhpArray) catch break :blk Value.empty_array_default;
                arr.* = .{};
                var ok = true;
                for (elems) |elem_idx| {
                    const elem = self.ast.nodes[elem_idx];
                    if (elem.tag != .array_element) continue;
                    const val = self.evalConstExpr(elem.data.lhs);
                    if (val == .null and elem.data.lhs != 0 and self.ast.nodes[elem.data.lhs].tag != .null_literal) {
                        ok = false;
                        break;
                    }
                    if (elem.data.rhs != 0) {
                        const key = self.evalConstExpr(elem.data.rhs);
                        const set_key: PhpArray.Key = if (key == .string) .{ .string = key.string } else .{ .int = Value.toInt(key) };
                        arr.set(self.allocator, set_key, val) catch {
                            ok = false;
                            break;
                        };
                    } else {
                        arr.append(self.allocator, val) catch {
                            ok = false;
                            break;
                        };
                    }
                }
                if (!ok) {
                    freeDefaultValue(self.allocator, .{ .array = arr });
                    break :blk Value.empty_array_default;
                }
                break :blk .{ .array = arr };
            },
            .static_prop_access => blk: {
                const class_node = self.ast.nodes[n.data.lhs];
                const class_name = @import("compiler_expr.zig").resolveNodeClassName(self, class_node) catch break :blk Value.null;
                var prop_name = self.ast.tokenSlice(n.main_token);
                if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
                // resolve well-known builtin class constants eagerly so attribute
                // arg expressions like `Attribute::TARGET_CLASS | Attribute::IS_REPEATABLE`
                // can fold to a single int at compile time
                if (std.mem.eql(u8, class_name, "Attribute")) {
                    const known = [_]struct { n: []const u8, v: i64 }{
                        .{ .n = "TARGET_CLASS", .v = 1 },
                        .{ .n = "TARGET_FUNCTION", .v = 2 },
                        .{ .n = "TARGET_METHOD", .v = 4 },
                        .{ .n = "TARGET_PROPERTY", .v = 8 },
                        .{ .n = "TARGET_CLASS_CONSTANT", .v = 16 },
                        .{ .n = "TARGET_PARAMETER", .v = 32 },
                        .{ .n = "TARGET_ALL", .v = 127 },
                        .{ .n = "IS_REPEATABLE", .v = 128 },
                    };
                    for (known) |k| if (std.mem.eql(u8, k.n, prop_name)) break :blk Value{ .int = k.v };
                }
                // encode as deferred sentinel: "\x00CC\x00ClassName\x00CONST_NAME"
                const sentinel = std.fmt.allocPrint(self.allocator, "\x00CC\x00{s}\x00{s}", .{ class_name, prop_name }) catch break :blk Value.null;
                self.string_allocs.append(self.allocator, sentinel) catch break :blk Value.null;
                break :blk .{ .string = sentinel };
            },
            .identifier => blk: {
                const name = self.ast.tokenSlice(n.main_token);
                // handle built-in constants used as defaults
                if (std.mem.eql(u8, name, "true") or std.mem.eql(u8, name, "TRUE")) break :blk Value{ .bool = true };
                if (std.mem.eql(u8, name, "false") or std.mem.eql(u8, name, "FALSE")) break :blk Value{ .bool = false };
                if (std.mem.eql(u8, name, "null") or std.mem.eql(u8, name, "NULL")) break :blk Value.null;
                // treat as a constant name (sentinel for runtime resolution)
                const resolved = self.resolveClassName(name);
                const sentinel = std.fmt.allocPrint(self.allocator, "\x00CC\x00\x00{s}", .{resolved}) catch break :blk Value.null;
                self.string_allocs.append(self.allocator, sentinel) catch break :blk Value.null;
                break :blk .{ .string = sentinel };
            },
            .new_expr => blk: {
                const resolved = @import("compiler_expr.zig").resolveQualifiedNewName(self, n) catch break :blk Value.null;
                const raw_name = resolved.name;
                const class_name = if (resolved.is_absolute) raw_name else self.resolveClassName(raw_name);
                const arg_indices = self.ast.extraSlice(n.data.lhs);
                // bail on splat/named args - keep the simple positional case
                for (arg_indices) |arg_idx| {
                    const an = self.ast.nodes[arg_idx];
                    if (an.tag == .splat_expr or an.tag == .named_arg) break :blk Value.null;
                }
                const args = self.allocator.alloc(Value, arg_indices.len) catch break :blk Value.null;
                for (arg_indices, 0..) |arg_idx, i| args[i] = self.evalConstExpr(arg_idx);
                const nd = self.allocator.create(bytecode.NewDefault) catch {
                    self.allocator.free(args);
                    break :blk Value.null;
                };
                nd.* = .{ .class_name = class_name, .args = args };
                self.new_defaults.append(self.allocator, nd) catch {
                    self.allocator.free(args);
                    self.allocator.destroy(nd);
                    break :blk Value.null;
                };
                const sentinel = bytecode.encodeNewDefaultSentinel(self.allocator, nd) catch break :blk Value.null;
                self.string_allocs.append(self.allocator, sentinel) catch break :blk Value.null;
                break :blk .{ .string = sentinel };
            },
            else => .null,
        };
    }

    // ==================================================================
    // name resolution
    // ==================================================================

    pub fn resolveClassName(self: *Compiler, name: []const u8) []const u8 {
        if (name.len > 0 and name[0] == '\\') return name[1..];
        if (std.mem.eql(u8, name, "self")) {
            if (self.current_class.len > 0 and !self.in_trait) return self.current_class;
            return name;
        }
        if (std.mem.eql(u8, name, "parent")) {
            if (self.current_parent.len > 0 and !self.in_trait) return self.current_parent;
            return name;
        }
        if (std.mem.eql(u8, name, "static")) return name;
        if (self.use_aliases.get(name)) |fqn| return fqn;
        // for multi-segment names like `Assert\NotBlank` look up just the first
        // segment in use_aliases. PHP applies the alias to that prefix then
        // appends the remainder verbatim
        if (std.mem.indexOfScalar(u8, name, '\\')) |slash_pos| {
            const head = name[0..slash_pos];
            const tail = name[slash_pos..]; // includes leading `\`
            if (self.use_aliases.get(head)) |fqn| {
                const qualified = std.fmt.allocPrint(self.allocator, "{s}{s}", .{ fqn, tail }) catch return name;
                self.string_allocs.append(self.allocator, qualified) catch return name;
                return qualified;
            }
        }
        if (self.namespace.len == 0) return name;
        const qualified = std.fmt.allocPrint(self.allocator, "{s}\\{s}", .{ self.namespace, name }) catch return name;
        self.string_allocs.append(self.allocator, qualified) catch return name;
        return qualified;
    }

    pub fn resolveFunctionName(self: *Compiler, name: []const u8) []const u8 {
        if (name.len > 0 and name[0] == '\\') return name[1..];
        if (self.use_fn_aliases.get(name)) |fqn| return fqn;
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

    pub fn isDynamicProp(self: *Compiler, node: Ast.Node) bool {
        if (node.main_token == 0) return true;
        const prop_node = self.ast.nodes[node.data.rhs];
        return self.ast.tokens[prop_node.main_token].tag == .variable;
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

    pub fn patchBreaksTo(self: *Compiler, prev_breaks: *std.ArrayListUnmanaged(LoopJump), target: usize) Error!void {
        for (self.break_jumps.items) |bj| {
            if (bj.depth < self.loop_depth) {
                try prev_breaks.append(self.allocator, bj);
            } else {
                self.patchJumpTo(bj.offset, target);
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

    pub fn inFunctionScope(self: *Compiler) bool {
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

    // for an arrow sub-compiler: is `name` bound in some enclosing scope, so
    // the arrow may capture it? walks the arrow_parent chain and forces every
    // intermediate arrow to register a slot so the capture chains through
    // (handles `fn() => fn() => $x`)
    fn resolveArrowCapture(self: *Compiler, name: []const u8) bool {
        const parent = self.arrow_parent orelse return false;
        if (parent.local_slots.contains(name)) return true;
        if (parent.arrow_parent != null and resolveArrowCapture(parent, name)) {
            _ = parent.getOrCreateSlot(name);
            return true;
        }
        return false;
    }

    // resolve `name` to a local slot, lazily capturing it into an arrow
    // function when it is a variable used from the enclosing scope. returns
    // null when the name is not (and cannot become) a captured local
    pub fn arrowCaptureSlot(self: *Compiler, name: []const u8) ?u16 {
        if (self.arrow_parent == null) return null;
        if (name.len == 0 or name[0] != '$') return null;
        if (!self.resolveArrowCapture(name)) return null;
        return self.getOrCreateSlot(name);
    }

    pub fn emitGetVar(self: *Compiler, name: []const u8) Error!void {
        if (self.local_slots.get(name)) |slot| {
            try self.emitOp(.get_local);
            try self.emitU16(slot);
            return;
        }
        if (self.arrowCaptureSlot(name)) |slot| {
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
        // non-$ name: may be a namespaced constant aliased by `use const`
        const resolved = if (name.len == 0 or name[0] != '$') (self.use_const_aliases.get(name) orelse name) else name;
        const idx = try self.addConstant(.{ .string = resolved });
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

    // superinstruction: $local_dst op= $local_src as a statement (no stack effect)
    pub fn tryCompileLocalAssignSuper(self: *Compiler, expr_idx: u32) Error!bool {
        const expr = self.ast.nodes[expr_idx];
        if (expr.tag != .assign) return false;
        const op_tag = self.ast.tokens[expr.main_token].tag;
        const super_op: OpCode = switch (op_tag) {
            .plus_equal => .add_local_to_local,
            .minus_equal => .sub_local_to_local,
            .star_equal => .mul_local_to_local,
            else => return false,
        };
        const target = self.ast.nodes[expr.data.lhs];
        if (target.tag != .variable and target.tag != .identifier) return false;
        const rhs = self.ast.nodes[expr.data.rhs];
        if (rhs.tag != .variable and rhs.tag != .identifier) return false;
        const dst_name = self.ast.tokenSlice(target.main_token);
        const src_name = self.ast.tokenSlice(rhs.main_token);
        const dst_slot = self.local_slots.get(dst_name) orelse return false;
        const src_slot = self.local_slots.get(src_name) orelse return false;
        try self.emitOp(super_op);
        try self.emitU16(src_slot);
        try self.emitU16(dst_slot);
        return true;
    }

    // ==================================================================
    // bytecode emit helpers
    // ==================================================================

    pub fn emitOp(self: *Compiler, op: OpCode) Error!void {
        try self.chunk.write(self.allocator, @intFromEnum(op), self.current_source_offset);
    }

    pub fn emitByte(self: *Compiler, byte: u8) Error!void {
        try self.chunk.write(self.allocator, byte, self.current_source_offset);
    }

    pub fn emitU16(self: *Compiler, val: u16) Error!void {
        try self.emitByte(@intCast(val >> 8));
        try self.emitByte(@intCast(val & 0xff));
    }

    pub fn emitU32(self: *Compiler, val: u32) Error!void {
        try self.emitByte(@intCast((val >> 24) & 0xff));
        try self.emitByte(@intCast((val >> 16) & 0xff));
        try self.emitByte(@intCast((val >> 8) & 0xff));
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

    pub fn patchJumpTo(self: *Compiler, offset: usize, target: usize) void {
        const dist = target -| offset -| 2;
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
        return switch (parsePhpIntLiteral(s)) {
            .int => |i| i,
            .float => |f| @intFromFloat(f),
            else => 0,
        };
    }

    // parse an integer literal, promoting to float when it overflows i64 -
    // PHP's behavior for 9223372036854775808, 0xFFFFFFFFFFFFFFFFF, etc.
    pub fn parsePhpIntLiteral(s: []const u8) Value {
        if (s.len == 0) return .{ .int = 0 };
        var buf: [128]u8 = undefined;
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
                'x', 'X' => return parseRadixLiteral(clean[2..], 16),
                'b', 'B' => return parseRadixLiteral(clean[2..], 2),
                'o', 'O' => return parseRadixLiteral(clean[2..], 8),
                '0'...'7' => return parseRadixLiteral(clean[1..], 8),
                else => {},
            }
        }
        if (std.fmt.parseInt(i64, clean, 10)) |v| {
            return .{ .int = v };
        } else |_| {
            // decimal literal too large for i64 -> float
            return .{ .float = std.fmt.parseFloat(f64, clean) catch 0.0 };
        }
    }

    fn parseRadixLiteral(digits: []const u8, radix: u8) Value {
        if (std.fmt.parseInt(i64, digits, radix)) |v| {
            return .{ .int = v };
        } else |_| {}
        // overflowing non-decimal literal -> float. accumulate in u128 (exact
        // for everything up to ~3.4e38) then convert to f64 once, so the
        // rounding matches PHP's parse-then-cast instead of accumulating
        // error digit by digit in f64
        var acc: u128 = 0;
        const r: u128 = radix;
        for (digits) |d| {
            const dv: ?u128 = switch (d) {
                '0'...'9' => d - '0',
                'a'...'f' => d - 'a' + 10,
                'A'...'F' => d - 'A' + 10,
                else => null,
            };
            if (dv) |v| {
                const m = @mulWithOverflow(acc, r);
                if (m[1] != 0) return .{ .float = std.fmt.parseFloat(f64, digits) catch 0.0 };
                const a = @addWithOverflow(m[0], v);
                if (a[1] != 0) return .{ .float = std.fmt.parseFloat(f64, digits) catch 0.0 };
                acc = a[0];
            } else return .{ .int = 0 };
        }
        return .{ .float = @floatFromInt(acc) };
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
