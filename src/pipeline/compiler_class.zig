const std = @import("std");
const Compiler = @import("compiler.zig").Compiler;
const TypeHint = @import("compiler.zig").TypeHint;
const Ast = @import("ast.zig").Ast;
const Token = @import("token.zig").Token;
const Chunk = @import("bytecode.zig").Chunk;
const OpCode = @import("bytecode.zig").OpCode;
const ObjFunction = @import("bytecode.zig").ObjFunction;
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const Allocator = std.mem.Allocator;
const Error = Allocator.Error || error{CompileError};

const ParsedAttr = struct {
    name: []const u8,
    args: []const Value,
};

fn isModifierToken(tag: Token.Tag) bool {
    return switch (tag) {
        .kw_public, .kw_protected, .kw_private, .kw_static,
        .kw_abstract, .kw_readonly, .kw_final, .kw_function,
        .kw_class, .kw_var,
        => true,
        else => false,
    };
}

fn isTypeToken(tag: Token.Tag) bool {
    return switch (tag) {
        .identifier, .question, .pipe, .backslash, .amp,
        .kw_array, .kw_callable, .kw_self, .kw_parent, .kw_null,
        .kw_true, .kw_false, .kw_static,
        => true,
        else => false,
    };
}

fn parseAttrArgValue(tokens: []const Token, source: []const u8, pos: *usize, allocator: Allocator) Value {
    if (pos.* >= tokens.len) return .null;
    const tag = tokens[pos.*].tag;
    switch (tag) {
        .string => {
            const raw = tokens[pos.*].lexeme(source);
            pos.* += 1;
            if (raw.len >= 2) return .{ .string = raw[1 .. raw.len - 1] };
            return .{ .string = raw };
        },
        .integer => {
            const text = tokens[pos.*].lexeme(source);
            pos.* += 1;
            return .{ .int = std.fmt.parseInt(i64, text, 0) catch 0 };
        },
        .float => {
            const text = tokens[pos.*].lexeme(source);
            pos.* += 1;
            return .{ .float = std.fmt.parseFloat(f64, text) catch 0.0 };
        },
        .kw_true => {
            pos.* += 1;
            return .{ .bool = true };
        },
        .kw_false => {
            pos.* += 1;
            return .{ .bool = false };
        },
        .kw_null => {
            pos.* += 1;
            return .null;
        },
        .identifier => {
            const text = tokens[pos.*].lexeme(source);
            if (std.mem.eql(u8, text, "true") or std.mem.eql(u8, text, "TRUE")) {
                pos.* += 1;
                return .{ .bool = true };
            }
            if (std.mem.eql(u8, text, "false") or std.mem.eql(u8, text, "FALSE")) {
                pos.* += 1;
                return .{ .bool = false };
            }
            if (std.mem.eql(u8, text, "null") or std.mem.eql(u8, text, "NULL")) {
                pos.* += 1;
                return .null;
            }
            pos.* += 1;
            return .{ .string = text };
        },
        .minus => {
            pos.* += 1;
            const inner = parseAttrArgValue(tokens, source, pos, allocator);
            return switch (inner) {
                .int => |v| .{ .int = -v },
                .float => |v| .{ .float = -v },
                else => .null,
            };
        },
        .l_bracket => {
            pos.* += 1;
            const arr = allocator.create(PhpArray) catch return .null;
            arr.* = .{};
            while (pos.* < tokens.len and tokens[pos.*].tag != .r_bracket) {
                const val = parseAttrArgValue(tokens, source, pos, allocator);
                arr.append(allocator, val) catch break;
                if (pos.* < tokens.len and tokens[pos.*].tag == .comma) pos.* += 1;
            }
            if (pos.* < tokens.len and tokens[pos.*].tag == .r_bracket) pos.* += 1;
            return .{ .array = arr };
        },
        else => {
            pos.* += 1;
            return .null;
        },
    }
}

const ast_mod = @import("ast.zig");

fn findAttrRangeForToken(attr_ranges: []const ast_mod.AttrRange, tokens: []const Token, main_token: u32) ?ast_mod.AttrRange {
    for (attr_ranges) |ar| {
        if (ar.target_tok > main_token) continue;
        var pos = ar.target_tok;
        while (pos <= main_token) {
            if (pos == main_token) return ar;
            const tag = tokens[pos].tag;
            if (isModifierToken(tag) or isTypeToken(tag)) {
                pos += 1;
                continue;
            }
            break;
        }
    }
    return null;
}


fn extractAttributes(self: *Compiler, main_token: u32) []const ParsedAttr {
    const ar = findAttrRangeForToken(self.ast.attr_ranges, self.ast.tokens, main_token) orelse return &.{};

    var all_attrs = std.ArrayListUnmanaged(ParsedAttr){};
    var pos: usize = ar.start;
    const end: usize = ar.end;
    while (pos < end) {
        if (self.ast.tokens[pos].tag != .hash_bracket) {
            pos += 1;
            continue;
        }
        pos += 1;
        var rb_pos: usize = pos;
        var depth: u32 = 1;
        while (rb_pos < end and depth > 0) {
            if (self.ast.tokens[rb_pos].tag == .l_bracket) depth += 1
            else if (self.ast.tokens[rb_pos].tag == .r_bracket) depth -= 1;
            if (depth > 0) rb_pos += 1;
        }

        var inner: usize = pos;
        while (inner < rb_pos) {
            var name_parts = std.ArrayListUnmanaged(u8){};
            while (inner < rb_pos and (self.ast.tokens[inner].tag == .identifier or self.ast.tokens[inner].tag == .backslash)) {
                if (name_parts.items.len > 0 and self.ast.tokens[inner].tag == .identifier) {
                    name_parts.appendSlice(self.allocator, "\\") catch break;
                } else if (self.ast.tokens[inner].tag == .backslash) {
                    if (name_parts.items.len == 0) {
                        name_parts.appendSlice(self.allocator, "\\") catch break;
                    }
                    inner += 1;
                    continue;
                }
                name_parts.appendSlice(self.allocator, self.ast.tokens[inner].lexeme(self.ast.source)) catch break;
                inner += 1;
            }
            if (name_parts.items.len == 0) {
                inner += 1;
                continue;
            }

            const owned_name = name_parts.toOwnedSlice(self.allocator) catch "";
            self.string_allocs.append(self.allocator, @constCast(owned_name)) catch {};

            var args = std.ArrayListUnmanaged(Value){};
            if (inner < rb_pos and self.ast.tokens[inner].tag == .l_paren) {
                inner += 1;
                while (inner < rb_pos and self.ast.tokens[inner].tag != .r_paren) {
                    if (inner + 1 < rb_pos and self.ast.tokens[inner].tag == .identifier and self.ast.tokens[inner + 1].tag == .colon) {
                        inner += 2;
                    }
                    const val = parseAttrArgValue(self.ast.tokens, self.ast.source, &inner, self.allocator);
                    args.append(self.allocator, val) catch break;
                    if (inner < rb_pos and self.ast.tokens[inner].tag == .comma) inner += 1;
                }
                if (inner < rb_pos and self.ast.tokens[inner].tag == .r_paren) inner += 1;
            }

            all_attrs.append(self.allocator, .{
                .name = owned_name,
                .args = args.toOwnedSlice(self.allocator) catch &.{},
            }) catch break;

            if (inner < rb_pos and self.ast.tokens[inner].tag == .comma) inner += 1;
        }

        pos = rb_pos + 1;
    }
    return all_attrs.toOwnedSlice(self.allocator) catch &.{};
}

fn freeAttrSlice(allocator: Allocator, attrs: []const ParsedAttr) void {
    for (attrs) |attr| {
        if (attr.args.len > 0) allocator.free(attr.args);
    }
    if (attrs.len > 0) allocator.free(attrs);
}

fn emitAttributeData(self: *Compiler, attrs: []const ParsedAttr) Error!void {
    try self.emitByte(@intCast(attrs.len));
    for (attrs) |attr| {
        const name_idx = try self.addConstant(.{ .string = attr.name });
        try self.emitU16(name_idx);
        try self.emitByte(@intCast(attr.args.len));
        for (attr.args) |arg| {
            try emitAttrValue(self, arg);
        }
    }
}

fn emitAttrValue(self: *Compiler, val: Value) Error!void {
    switch (val) {
        .null => try self.emitByte(0x00),
        .int => |v| {
            try self.emitByte(0x01);
            const bytes: [8]u8 = @bitCast(v);
            for (bytes) |b| try self.emitByte(b);
        },
        .float => |v| {
            try self.emitByte(0x02);
            const bytes: [8]u8 = @bitCast(v);
            for (bytes) |b| try self.emitByte(b);
        },
        .bool => |v| try self.emitByte(if (v) 0x03 else 0x04),
        .string => |s| {
            try self.emitByte(0x05);
            const idx = try self.addConstant(.{ .string = s });
            try self.emitU16(idx);
        },
        .array => {
            try self.emitByte(0x06);
            const arr = val.array;
            const len: u16 = @intCast(arr.entries.items.len);
            try self.emitU16(len);
            for (arr.entries.items) |entry| {
                try emitAttrValue(self, entry.value);
            }
        },
        else => try self.emitByte(0x00),
    }
}

fn buildTypeString(self: *Compiler, start_tok: u32, end_tok: u32) Error![]const u8 {
    if (start_tok == end_tok) return "";
    if (start_tok + 1 == end_tok) {
        const lexeme = self.ast.tokens[start_tok].lexeme(self.ast.source);
        if (self.ast.tokens[start_tok].tag == .identifier and !isPrimitiveType(lexeme)) {
            return self.resolveClassName(lexeme);
        }
        return lexeme;
    }

    // check if leading backslash means fully qualified
    var is_fqn = false;
    if (start_tok < end_tok) {
        const first_lex = self.ast.tokens[start_tok].lexeme(self.ast.source);
        if (std.mem.eql(u8, first_lex, "\\")) is_fqn = true;
    }

    var buf = std.ArrayListUnmanaged(u8){};
    for (start_tok..end_tok) |t| {
        const tag = self.ast.tokens[t].tag;
        const lexeme = self.ast.tokens[t].lexeme(self.ast.source);
        // skip leading backslash in FQN types (it just means "absolute")
        if (is_fqn and std.mem.eql(u8, lexeme, "\\") and buf.items.len == 0) continue;
        if (tag == .identifier and !isPrimitiveType(lexeme) and !is_fqn) {
            try buf.appendSlice(self.allocator, self.resolveClassName(lexeme));
        } else {
            try buf.appendSlice(self.allocator, lexeme);
        }
    }
    const s = try buf.toOwnedSlice(self.allocator);
    try self.string_allocs.append(self.allocator, s);
    return s;
}

fn isPrimitiveType(name: []const u8) bool {
    const primitives = [_][]const u8{
        "int", "integer", "float", "double", "bool", "boolean",
        "string", "array", "object", "callable", "void", "null",
        "false", "true", "mixed", "never", "iterable", "self",
        "static", "parent", "Generator", "Fiber", "Closure",
    };
    for (primitives) |p| {
        if (std.mem.eql(u8, name, p)) return true;
    }
    return false;
}

fn extractParamTypes(self: *Compiler, param_nodes: []const u32) Error![]const []const u8 {
    var has_any = false;
    for (param_nodes) |p| {
        const rhs = self.ast.nodes[p].data.rhs;
        if ((rhs >> 5) != 0) { has_any = true; break; }
    }
    if (!has_any) return &.{};

    const types = try self.allocator.alloc([]const u8, param_nodes.len);
    for (param_nodes, 0..) |p, i| {
        const rhs = self.ast.nodes[p].data.rhs;
        const type_extra_idx = rhs >> 5;
        if (type_extra_idx == 0) {
            types[i] = "";
        } else {
            const idx = type_extra_idx - 1;
            const start_tok = self.ast.extra_data[idx];
            const end_tok = self.ast.extra_data[idx + 1];
            types[i] = try buildTypeString(self, start_tok, end_tok);
        }
    }
    return types;
}

fn extractReturnType(self: *Compiler, extra_base: u32, param_count: u32) Error![]const u8 {
    const ret_start = self.ast.extra_data[extra_base + 1 + param_count];
    const ret_end = self.ast.extra_data[extra_base + 1 + param_count + 1];
    return buildTypeString(self, ret_start, ret_end);
}

pub fn compileFunction(self: *Compiler, node: Ast.Node) Error!void {
    const name_tok = node.main_token;
    const raw_name = self.ast.tokenSlice(name_tok);
    const name = if (std.mem.startsWith(u8, raw_name, "__closure_")) raw_name else self.resolveClassName(raw_name);
    const param_nodes = self.ast.extraSlice(node.data.lhs);

    const param_names = try self.allocator.alloc([]const u8, param_nodes.len);
    const ref_flags = try self.allocator.alloc(bool, param_nodes.len);
    var defaults = std.ArrayListUnmanaged(Value){};
    defer defaults.deinit(self.allocator);
    var required: u8 = 0;
    var seen_default = false;
    var is_variadic = false;

    for (param_nodes, 0..) |p, i| {
        const pnode = self.ast.nodes[p];
        param_names[i] = self.ast.tokenSlice(pnode.main_token);
        ref_flags[i] = (pnode.data.rhs & 2) != 0;
        if ((pnode.data.rhs & 1) != 0) {
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

    const gen = (node.data.rhs & (1 << 31)) != 0;

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
        .is_generator = gen,
        .closure_count = self.closure_count,
        .file_path = self.file_path,
        .namespace = self.namespace,
        .use_aliases = self.use_aliases,
        .use_fn_aliases = self.use_fn_aliases,
        .current_function = name,
    };
    errdefer {
        sub.chunk.deinit(self.allocator);
        sub.break_jumps.deinit(self.allocator);
        sub.continue_jumps.deinit(self.allocator);
        sub.string_allocs.deinit(self.allocator);
        sub.local_slots.deinit(self.allocator);
        sub.type_hints.deinit(self.allocator);
        sub.pending_gotos.deinit(self.allocator);
        sub.labels.deinit(self.allocator);
    }

    for (param_nodes, 0..) |_, i| {
        if (i < ref_flags.len and ref_flags[i]) continue;
        _ = sub.getOrCreateSlot(param_names[i]);
    }

    const body_idx = node.data.rhs & 0x7FFFFFFF;
    try sub.compileNode(body_idx);
    for (sub.pending_gotos.items) |pg| {
        if (sub.labels.get(pg.label)) |target| {
            sub.patchJumpTo(pg.offset, target);
        }
    }
    sub.pending_gotos.deinit(self.allocator);
    sub.labels.deinit(self.allocator);
    try sub.emitOp(.op_null);
    try sub.emitOp(if (gen) .generator_return else .return_val);
    sub.break_jumps.deinit(self.allocator);
    sub.continue_jumps.deinit(self.allocator);

    self.closure_count = sub.closure_count;
    const slot_names = try sub.buildSlotNames();
    const local_count = sub.next_slot;
    sub.local_slots.deinit(self.allocator);

    const is_closure = std.mem.startsWith(u8, name, "__closure_");
    const lo = !is_closure and !gen and !is_variadic and !hasRefParams(ref_flags) and !needsVarSync(&sub.chunk) and sub.closure_count == 0;

    try self.functions.append(self.allocator, .{
        .name = name,
        .arity = @intCast(param_nodes.len),
        .required_params = required,
        .is_variadic = is_variadic,
        .is_generator = gen,
        .locals_only = lo,
        .params = param_names[0..param_nodes.len],
        .defaults = defaults_owned,
        .ref_params = ref_flags,
        .chunk = sub.chunk,
        .local_count = local_count,
        .slot_names = slot_names,
    });

    const param_types = try extractParamTypes(self, param_nodes);
    const return_type = try extractReturnType(self, node.data.lhs, @intCast(param_nodes.len));
    if (param_types.len > 0 or return_type.len > 0) {
        try self.type_hints.append(self.allocator, .{ .name = name, .param_types = param_types, .return_type = return_type });
    }

    for (sub.functions.items) |f| try self.functions.append(self.allocator, f);
    sub.functions.deinit(self.allocator);
    for (sub.string_allocs.items) |s| try self.string_allocs.append(self.allocator, s);
    sub.string_allocs.deinit(self.allocator);
    for (sub.type_hints.items) |th| try self.type_hints.append(self.allocator, th);
    sub.type_hints.deinit(self.allocator);
}

pub fn compileClosure(self: *Compiler, node: Ast.Node) Error!void {
    const id = self.closure_count;
    self.closure_count += 1;

    var name_buf: [32]u8 = undefined;
    const name = std.fmt.bufPrint(&name_buf, "__closure_{d}", .{id}) catch "__closure";
    const owned_name = try self.allocator.dupe(u8, name);
    try self.string_allocs.append(self.allocator, owned_name);

    const param_nodes = self.ast.extraSlice(node.data.lhs);
    const param_names = try self.allocator.alloc([]const u8, param_nodes.len);
    var ref_flags_buf: [16]bool = .{false} ** 16;
    var has_any_ref = false;
    var defaults = std.ArrayListUnmanaged(Value){};
    defer defaults.deinit(self.allocator);
    var required: u8 = 0;
    var seen_default = false;
    var is_variadic = false;

    for (param_nodes, 0..) |p, i| {
        const pnode = self.ast.nodes[p];
        param_names[i] = self.ast.tokenSlice(pnode.main_token);
        if (i < 16 and (pnode.data.rhs & 2) != 0) {
            ref_flags_buf[i] = true;
            has_any_ref = true;
        }
        if ((pnode.data.rhs & 1) != 0) {
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

    const defaults_owned = if (seen_default or is_variadic) blk: {
        const d = try self.allocator.alloc(Value, defaults.items.len);
        @memcpy(d, defaults.items);
        break :blk d;
    } else &[_]Value{};

    // rhs = extra -> {body (bit 31 = generator), use_count, use_vars...}
    // use_count 0xFFFFFFFF = arrow fn (implicit capture)
    const raw_body = self.ast.extra_data[node.data.rhs];
    const body_node = raw_body & 0x7FFFFFFF;
    const gen = (raw_body & (1 << 31)) != 0;
    const raw_use_count = self.ast.extra_data[node.data.rhs + 1];
    const is_arrow = raw_use_count == 0xFFFFFFFF;
    const use_count: u32 = if (is_arrow) 0 else raw_use_count;
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
        .is_generator = gen,
        .closure_count = self.closure_count,
        .file_path = self.file_path,
        .namespace = self.namespace,
        .use_aliases = self.use_aliases,
        .use_fn_aliases = self.use_fn_aliases,
        .current_class = self.current_class,
        .current_parent = self.current_parent,
        .current_function = "{closure}",
        .in_trait = self.in_trait,
    };
    errdefer {
        sub.chunk.deinit(self.allocator);
        sub.break_jumps.deinit(self.allocator);
        sub.continue_jumps.deinit(self.allocator);
        sub.string_allocs.deinit(self.allocator);
        sub.local_slots.deinit(self.allocator);
        sub.type_hints.deinit(self.allocator);
        sub.pending_gotos.deinit(self.allocator);
        sub.labels.deinit(self.allocator);
    }

    for (param_nodes, 0..) |_, i| {
        if (i < 16 and ref_flags_buf[i]) continue;
        _ = sub.getOrCreateSlot(param_names[i]);
    }

    for (use_vars) |use_var_node| {
        const use_node = self.ast.nodes[use_var_node];
        const is_ref = use_node.data.rhs != 0;
        if (!is_ref) {
            const var_name = self.ast.tokenSlice(use_node.main_token);
            _ = sub.getOrCreateSlot(var_name);
        }
    }
    _ = sub.getOrCreateSlot("$this");

    // arrow functions: pre-register parent scope variables so they compile as
    // get_local instead of get_var, enabling locals-only execution path
    if (is_arrow) {
        var parent_it = self.local_slots.iterator();
        while (parent_it.next()) |entry| {
            _ = sub.getOrCreateSlot(entry.key_ptr.*);
        }
    }

    try sub.compileNode(body_node);
    for (sub.pending_gotos.items) |pg| {
        if (sub.labels.get(pg.label)) |target| {
            sub.patchJumpTo(pg.offset, target);
        }
    }
    sub.pending_gotos.deinit(self.allocator);
    sub.labels.deinit(self.allocator);
    try sub.emitOp(.op_null);
    try sub.emitOp(if (gen) .generator_return else .return_val);
    sub.break_jumps.deinit(self.allocator);

    self.closure_count = sub.closure_count;

    const ref_params = if (has_any_ref) blk: {
        const rp = try self.allocator.alloc(bool, param_nodes.len);
        for (0..param_nodes.len) |i| rp[i] = if (i < 16) ref_flags_buf[i] else false;
        break :blk rp;
    } else &[_]bool{};

    // check for ref captures
    var has_ref_capture = false;
    for (use_vars) |use_var_node| {
        if (self.ast.nodes[use_var_node].data.rhs != 0) {
            has_ref_capture = true;
            break;
        }
    }

    const slot_names = try sub.buildSlotNames();
    const local_count = sub.next_slot;
    sub.local_slots.deinit(self.allocator);

    const closure_lo = !gen and !has_any_ref and !has_ref_capture and !needsVarSync(&sub.chunk);

    const func = ObjFunction{
        .name = owned_name,
        .arity = @intCast(param_nodes.len),
        .required_params = required,
        .params = param_names[0..param_nodes.len],
        .defaults = defaults_owned,
        .chunk = sub.chunk,
        .is_arrow = is_arrow,
        .is_generator = gen,
        .is_variadic = is_variadic,
        .locals_only = closure_lo,
        .ref_params = ref_params,
        .local_count = local_count,
        .slot_names = slot_names,
    };

    try self.functions.append(self.allocator, func);

    const param_types = try extractParamTypes(self, param_nodes);
    const return_type = try extractReturnType(self, node.data.lhs, @intCast(param_nodes.len));
    if (param_types.len > 0 or return_type.len > 0) {
        try self.type_hints.append(self.allocator, .{ .name = owned_name, .param_types = param_types, .return_type = return_type });
    }

    for (sub.functions.items) |f| try self.functions.append(self.allocator, f);
    sub.functions.deinit(self.allocator);
    for (sub.string_allocs.items) |s| try self.string_allocs.append(self.allocator, s);
    sub.string_allocs.deinit(self.allocator);
    for (sub.type_hints.items) |th| try self.type_hints.append(self.allocator, th);
    sub.type_hints.deinit(self.allocator);

    const idx = try self.addConstant(.{ .string = owned_name });
    try self.emitConstant(idx);

    for (use_vars) |use_var_node| {
        const use_node = self.ast.nodes[use_var_node];
        const var_name = self.ast.tokenSlice(use_node.main_token);
        const var_idx = try self.addConstant(.{ .string = var_name });
        const is_ref = use_node.data.rhs != 0;
        try self.emitOp(if (is_ref) .closure_bind_ref else .closure_bind);
        try self.emitU16(var_idx);
    }

    // arrow functions: emit closure_bind for all captured outer-scope variables
    if (is_arrow) {
        for (slot_names) |sn| {
            var is_param = false;
            for (param_names[0..param_nodes.len]) |pn| {
                if (sn.len == pn.len and std.mem.eql(u8, sn, pn)) { is_param = true; break; }
            }
            if (is_param) continue;
            if (std.mem.eql(u8, sn, "$this")) continue;
            const sn_idx = try self.addConstant(.{ .string = sn });
            try self.emitOp(.closure_bind);
            try self.emitU16(sn_idx);
        }
    }

    // bind $this for closures in method context
    const this_idx = try self.addConstant(.{ .string = "$this" });
    try self.emitOp(.closure_bind);
    try self.emitU16(this_idx);
}

pub fn compileClassDecl(self: *Compiler, node: Ast.Node) Error!void {
    const class_name = self.resolveClassName(self.ast.tokenSlice(node.main_token));
    const members = self.ast.extraSlice(node.data.lhs);

    const prev_class = self.current_class;
    self.current_class = class_name;
    defer self.current_class = prev_class;

    // decode rhs: {parent_node, implements_count, impl_nodes...}
    const rhs_base = node.data.rhs;
    const parent_node = self.ast.extra_data[rhs_base];
    const impl_count = self.ast.extra_data[rhs_base + 1];
    var impl_names: [16][]const u8 = undefined;
    for (0..impl_count) |i| {
        const impl_node = self.ast.nodes[self.ast.extra_data[rhs_base + 2 + i]];
        impl_names[i] = if (impl_node.tag == .qualified_name) (self.buildQualifiedString(self.ast.extraSlice(impl_node.data.lhs)) catch self.ast.tokenSlice(impl_node.main_token)) else self.resolveClassName(self.ast.tokenSlice(impl_node.main_token));
    }

    const prev_parent = self.current_parent;
    self.current_parent = if (parent_node != 0) blk: {
        const pnode = self.ast.nodes[parent_node];
        break :blk if (pnode.tag == .qualified_name) (self.buildQualifiedString(self.ast.extraSlice(pnode.data.lhs)) catch self.ast.tokenSlice(pnode.main_token)) else self.resolveClassName(self.ast.tokenSlice(pnode.main_token));
    } else "";
    defer self.current_parent = prev_parent;

    var method_count: u16 = 0;
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_method or member.tag == .static_class_method) {
            try compileClassMethodBody(self, class_name, member);
            method_count += 1;
        }
    }

    // count promoted constructor params
    var promoted_count: u16 = 0;
    var constructor_params: []const u32 = &.{};
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_method and std.mem.eql(u8, self.ast.tokenSlice(member.main_token), "__construct")) {
            constructor_params = self.ast.extraSlice(member.data.lhs);
            for (constructor_params) |p| {
                const pnode = self.ast.nodes[p];
                if ((pnode.data.rhs >> 2) & 3 > 0) promoted_count += 1;
            }
            break;
        }
    }

    // collect trait property indices for this class
    var trait_prop_members = std.ArrayListUnmanaged(u32){};
    defer trait_prop_members.deinit(self.allocator);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .trait_use) {
            for (self.ast.extraSlice(member.data.lhs)) |tn| {
                const tname = self.ast.tokenSlice(self.ast.nodes[tn].main_token);
                if (self.trait_properties.get(tname)) |props| {
                    for (props) |pi| try trait_prop_members.append(self.allocator, pi);
                }
            }
        }
    }

    // compile instance property defaults (push onto stack)
    var prop_count: u16 = 0;
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_property) prop_count += 1;
    }
    prop_count += @intCast(trait_prop_members.items.len);
    prop_count += promoted_count;
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_property) {
            if (member.data.lhs != 0) {
                try self.compileNode(member.data.lhs);
            }
        }
    }
    // compile trait property defaults
    for (trait_prop_members.items) |tpi| {
        const tmember = self.ast.nodes[tpi];
        if (tmember.data.lhs != 0) {
            try self.compileNode(tmember.data.lhs);
        }
    }
    // promoted params get null defaults (actual values assigned in constructor body)
    for (constructor_params) |p| {
        const pnode = self.ast.nodes[p];
        if ((pnode.data.rhs >> 2) & 3 > 0) {
            try self.emitOp(.op_null);
        }
    }

    // compile static property defaults (push onto stack after instance props)
    // class constants (const_decl) are treated as static props
    var static_prop_count: u16 = 0;
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .static_class_property or member.tag == .const_decl) static_prop_count += 1;
    }
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .static_class_property) {
            if (member.data.lhs != 0) {
                try self.compileNode(member.data.lhs);
            }
        } else if (member.tag == .const_decl) {
            // push null placeholder - real values set after class_decl so self:: resolves
            try self.emitOp(.op_null);
        }
    }

    const name_idx = try self.addConstant(.{ .string = class_name });
    try self.emitOp(.class_decl);
    try self.emitU16(name_idx);
    try self.emitU16(method_count);

    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_method or member.tag == .static_class_method) {
            const method_name_str = self.ast.tokenSlice(member.main_token);
            const mname_idx = try self.addConstant(.{ .string = method_name_str });
            try self.emitU16(mname_idx);
            const param_nodes = self.ast.extraSlice(member.data.lhs);
            try self.emitByte(@intCast(param_nodes.len));
            try self.emitByte(if (member.tag == .static_class_method) @as(u8, 1) else @as(u8, 0));
            const vis: u8 = @intCast(member.data.rhs >> 30);
            try self.emitByte(vis);
        }
    }

    try self.emitU16(prop_count);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_property) {
            var prop_name = self.ast.tokenSlice(member.main_token);
            if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
            const pname_idx = try self.addConstant(.{ .string = prop_name });
            try self.emitU16(pname_idx);
            try self.emitByte(if (member.data.lhs != 0) @as(u8, 1) else @as(u8, 0));
            try self.emitByte(@intCast(member.data.rhs));
        }
    }
    // trait properties
    for (trait_prop_members.items) |tpi| {
        const tmember = self.ast.nodes[tpi];
        var tprop_name = self.ast.tokenSlice(tmember.main_token);
        if (tprop_name.len > 0 and tprop_name[0] == '$') tprop_name = tprop_name[1..];
        const tpname_idx = try self.addConstant(.{ .string = tprop_name });
        try self.emitU16(tpname_idx);
        try self.emitByte(if (tmember.data.lhs != 0) @as(u8, 1) else @as(u8, 0));
        try self.emitByte(@intCast(tmember.data.rhs));
    }
    // promoted constructor params as properties
    for (constructor_params) |p| {
        const pnode = self.ast.nodes[p];
        const promotion = (pnode.data.rhs >> 2) & 3;
        if (promotion > 0) {
            var param_name = self.ast.tokenSlice(pnode.main_token);
            if (param_name.len > 0 and param_name[0] == '$') param_name = param_name[1..];
            const pname_idx = try self.addConstant(.{ .string = param_name });
            try self.emitU16(pname_idx);
            try self.emitByte(1); // has default (null placeholder)
            // bits 0-1: visibility, bit 2: readonly
            const is_ro: u8 = if ((pnode.data.rhs & 16) != 0) 4 else 0;
            try self.emitByte(@as(u8, @intCast(promotion - 1)) | is_ro);
        }
    }

    try self.emitU16(static_prop_count);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .static_class_property) {
            var prop_name = self.ast.tokenSlice(member.main_token);
            if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
            const pname_idx = try self.addConstant(.{ .string = prop_name });
            try self.emitU16(pname_idx);
            try self.emitByte(if (member.data.lhs != 0) @as(u8, 1) else @as(u8, 0));
            try self.emitByte(@intCast(member.data.rhs));
        } else if (member.tag == .const_decl) {
            const cname = self.ast.tokenSlice(member.main_token);
            const cname_idx = try self.addConstant(.{ .string = cname });
            try self.emitU16(cname_idx);
            try self.emitByte(1); // always has a value
            try self.emitByte(0); // public visibility
        }
    }

    if (parent_node != 0) {
        const pnode = self.ast.nodes[parent_node];
        const parent_name = if (pnode.tag == .qualified_name) try self.buildQualifiedString(self.ast.extraSlice(pnode.data.lhs)) else self.resolveClassName(self.ast.tokenSlice(pnode.main_token));
        const parent_idx = try self.addConstant(.{ .string = parent_name });
        try self.emitU16(parent_idx);
    } else {
        try self.emitU16(0xffff);
    }

    // emit implements count and names (already resolved in impl_names)
    try self.emitByte(@intCast(impl_count));
    for (0..impl_count) |i| {
        const iname_idx = try self.addConstant(.{ .string = impl_names[i] });
        try self.emitU16(iname_idx);
    }

    // collect all trait names from trait_use statements
    var all_traits = std.ArrayListUnmanaged([]const u8){};
    defer all_traits.deinit(self.allocator);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .trait_use) {
            for (self.ast.extraSlice(member.data.lhs)) |tn| {
                const tn_node = self.ast.nodes[tn];
                const raw_name = if (tn_node.tag == .qualified_name) blk: {
                    const parts = self.ast.extraSlice(tn_node.data.lhs);
                    break :blk try self.buildQualifiedString(parts);
                } else self.ast.tokenSlice(tn_node.main_token);
                try all_traits.append(self.allocator, self.resolveClassName(raw_name));
            }
        }
    }
    try self.emitByte(@intCast(all_traits.items.len));
    for (all_traits.items) |tname| {
        const tname_idx = try self.addConstant(.{ .string = tname });
        try self.emitU16(tname_idx);
    }

    // collect conflict resolution rules from trait_use statements
    const ConflictRule = struct { node: Ast.Node };
    var all_conflicts = std.ArrayListUnmanaged(ConflictRule){};
    defer all_conflicts.deinit(self.allocator);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .trait_use and member.data.rhs != 0) {
            for (self.ast.extraSlice(member.data.rhs)) |cn| {
                try all_conflicts.append(self.allocator, .{ .node = self.ast.nodes[cn] });
            }
        }
    }
    try self.emitByte(@intCast(all_conflicts.items.len));
    for (all_conflicts.items) |cr| {
        const method_name = self.ast.tokenSlice(cr.node.main_token);
        const trait_name = self.ast.tokenSlice(self.ast.nodes[cr.node.data.lhs].main_token);
        const method_idx = try self.addConstant(.{ .string = method_name });
        const trait_idx = try self.addConstant(.{ .string = trait_name });
        try self.emitU16(method_idx);
        try self.emitU16(trait_idx);
        if (cr.node.tag == .trait_insteadof) {
            try self.emitByte(1);
            const excluded = self.ast.extraSlice(cr.node.data.rhs);
            try self.emitByte(@intCast(excluded.len));
            for (excluded) |en| {
                const ename = self.ast.tokenSlice(self.ast.nodes[en].main_token);
                const eidx = try self.addConstant(.{ .string = ename });
                try self.emitU16(eidx);
            }
        } else {
            try self.emitByte(2);
            const alias = self.ast.tokenSlice(cr.node.data.rhs);
            const aidx = try self.addConstant(.{ .string = alias });
            try self.emitU16(aidx);
        }
    }

    // class-level attributes
    const class_attrs = extractAttributes(self, node.main_token);
    try emitAttributeData(self, class_attrs);
    freeAttrSlice(self.allocator, class_attrs);

    // method attributes: count of methods that have attrs, then for each: name_idx + attr data
    const MemberAttr = struct { name: []const u8, attrs: []const ParsedAttr };
    var methods_with_attrs = std.ArrayListUnmanaged(MemberAttr){};
    defer methods_with_attrs.deinit(self.allocator);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_method or member.tag == .static_class_method) {
            const mattrs = extractAttributes(self, member.main_token);
            if (mattrs.len > 0) {
                try methods_with_attrs.append(self.allocator, .{
                    .name = self.ast.tokenSlice(member.main_token),
                    .attrs = mattrs,
                });
            }
        }
    }
    try self.emitByte(@intCast(methods_with_attrs.items.len));
    for (methods_with_attrs.items) |ma| {
        const mname_idx = try self.addConstant(.{ .string = ma.name });
        try self.emitU16(mname_idx);
        try emitAttributeData(self, ma.attrs);
    }
    for (methods_with_attrs.items) |ma| freeAttrSlice(self.allocator, ma.attrs);

    // property attributes
    var props_with_attrs = std.ArrayListUnmanaged(MemberAttr){};
    defer props_with_attrs.deinit(self.allocator);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_property) {
            const pattrs = extractAttributes(self, member.main_token);
            if (pattrs.len > 0) {
                var prop_name = self.ast.tokenSlice(member.main_token);
                if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
                try props_with_attrs.append(self.allocator, .{
                    .name = prop_name,
                    .attrs = pattrs,
                });
            }
        }
    }
    try self.emitByte(@intCast(props_with_attrs.items.len));
    for (props_with_attrs.items) |pa| {
        const ppname_idx = try self.addConstant(.{ .string = pa.name });
        try self.emitU16(ppname_idx);
        try emitAttributeData(self, pa.attrs);
    }
    for (props_with_attrs.items) |pa| freeAttrSlice(self.allocator, pa.attrs);

    // set class constants after class_decl so self:: references resolve
    const cname_idx = try self.addConstant(.{ .string = class_name });
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .const_decl) {
            try self.compileNode(member.data.lhs);
            const const_name = self.ast.tokenSlice(member.main_token);
            const cprop_idx = try self.addConstant(.{ .string = const_name });
            try self.emitOp(.set_static_prop);
            try self.emitU16(cname_idx);
            try self.emitU16(cprop_idx);
            try self.emitOp(.pop);
        }
    }
}

pub fn compileAnonymousClass(self: *Compiler, node: Ast.Node) Error!void {
    const anon_name = try std.fmt.allocPrint(self.allocator, "__anon_class_{d}", .{self.closure_count});
    try self.string_allocs.append(self.allocator, anon_name);
    self.closure_count += 1;

    const members = self.ast.extraSlice(node.data.lhs);
    const rhs_base = node.data.rhs;

    // decode rhs: {ctor_arg_count, ctor_args..., parent, impl_count, impls...}
    const ctor_arg_count = self.ast.extra_data[rhs_base];
    const ctor_args_start = rhs_base + 1;
    const parent_node = self.ast.extra_data[ctor_args_start + ctor_arg_count];
    const impl_count = self.ast.extra_data[ctor_args_start + ctor_arg_count + 1];
    var impl_names: [16][]const u8 = undefined;
    for (0..impl_count) |i| {
        const impl_node = self.ast.nodes[self.ast.extra_data[ctor_args_start + ctor_arg_count + 2 + i]];
        impl_names[i] = if (impl_node.tag == .qualified_name) (self.buildQualifiedString(self.ast.extraSlice(impl_node.data.lhs)) catch self.ast.tokenSlice(impl_node.main_token)) else self.resolveClassName(self.ast.tokenSlice(impl_node.main_token));
    }

    var method_count: u16 = 0;
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_method or member.tag == .static_class_method) {
            try compileClassMethodBody(self, anon_name, member);
            method_count += 1;
        }
    }

    var promoted_count: u16 = 0;
    var constructor_params: []const u32 = &.{};
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_method and std.mem.eql(u8, self.ast.tokenSlice(member.main_token), "__construct")) {
            constructor_params = self.ast.extraSlice(member.data.lhs);
            for (constructor_params) |p| {
                const pnode = self.ast.nodes[p];
                if ((pnode.data.rhs >> 2) & 3 > 0) promoted_count += 1;
            }
            break;
        }
    }

    var trait_prop_members = std.ArrayListUnmanaged(u32){};
    defer trait_prop_members.deinit(self.allocator);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .trait_use) {
            for (self.ast.extraSlice(member.data.lhs)) |tn| {
                const tname = self.ast.tokenSlice(self.ast.nodes[tn].main_token);
                if (self.trait_properties.get(tname)) |props| {
                    for (props) |pi| try trait_prop_members.append(self.allocator, pi);
                }
            }
        }
    }

    var prop_count: u16 = 0;
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_property) prop_count += 1;
    }
    prop_count += @intCast(trait_prop_members.items.len);
    prop_count += promoted_count;
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_property) {
            if (member.data.lhs != 0) {
                try self.compileNode(member.data.lhs);
            }
        }
    }
    for (trait_prop_members.items) |tpi| {
        const tmember = self.ast.nodes[tpi];
        if (tmember.data.lhs != 0) {
            try self.compileNode(tmember.data.lhs);
        }
    }
    for (constructor_params) |p| {
        const pnode = self.ast.nodes[p];
        if ((pnode.data.rhs >> 2) & 3 > 0) {
            try self.emitOp(.op_null);
        }
    }

    var static_prop_count: u16 = 0;
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .static_class_property or member.tag == .const_decl) static_prop_count += 1;
    }
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .static_class_property) {
            if (member.data.lhs != 0) {
                try self.compileNode(member.data.lhs);
            }
        } else if (member.tag == .const_decl) {
            try self.compileNode(member.data.lhs);
        }
    }

    const name_idx = try self.addConstant(.{ .string = anon_name });
    try self.emitOp(.class_decl);
    try self.emitU16(name_idx);
    try self.emitU16(method_count);

    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_method or member.tag == .static_class_method) {
            const method_name_str = self.ast.tokenSlice(member.main_token);
            const mname_idx = try self.addConstant(.{ .string = method_name_str });
            try self.emitU16(mname_idx);
            const param_nodes = self.ast.extraSlice(member.data.lhs);
            try self.emitByte(@intCast(param_nodes.len));
            try self.emitByte(if (member.tag == .static_class_method) @as(u8, 1) else @as(u8, 0));
            const vis: u8 = @intCast(member.data.rhs >> 30);
            try self.emitByte(vis);
        }
    }

    try self.emitU16(prop_count);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_property) {
            var prop_name = self.ast.tokenSlice(member.main_token);
            if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
            const pname_idx = try self.addConstant(.{ .string = prop_name });
            try self.emitU16(pname_idx);
            try self.emitByte(if (member.data.lhs != 0) @as(u8, 1) else @as(u8, 0));
            try self.emitByte(@intCast(member.data.rhs));
        }
    }
    for (trait_prop_members.items) |tpi| {
        const tmember = self.ast.nodes[tpi];
        var tprop_name = self.ast.tokenSlice(tmember.main_token);
        if (tprop_name.len > 0 and tprop_name[0] == '$') tprop_name = tprop_name[1..];
        const tpname_idx = try self.addConstant(.{ .string = tprop_name });
        try self.emitU16(tpname_idx);
        try self.emitByte(if (tmember.data.lhs != 0) @as(u8, 1) else @as(u8, 0));
        try self.emitByte(@intCast(tmember.data.rhs));
    }
    for (constructor_params) |p| {
        const pnode = self.ast.nodes[p];
        const promotion = (pnode.data.rhs >> 2) & 3;
        if (promotion > 0) {
            var param_name = self.ast.tokenSlice(pnode.main_token);
            if (param_name.len > 0 and param_name[0] == '$') param_name = param_name[1..];
            const pname_idx = try self.addConstant(.{ .string = param_name });
            try self.emitU16(pname_idx);
            try self.emitByte(1);
            const is_ro: u8 = if ((pnode.data.rhs & 16) != 0) 4 else 0;
            try self.emitByte(@as(u8, @intCast(promotion - 1)) | is_ro);
        }
    }

    try self.emitU16(static_prop_count);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .static_class_property) {
            var prop_name = self.ast.tokenSlice(member.main_token);
            if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
            const pname_idx = try self.addConstant(.{ .string = prop_name });
            try self.emitU16(pname_idx);
            try self.emitByte(if (member.data.lhs != 0) @as(u8, 1) else @as(u8, 0));
            try self.emitByte(@intCast(member.data.rhs));
        } else if (member.tag == .const_decl) {
            const cname = self.ast.tokenSlice(member.main_token);
            const cname_idx = try self.addConstant(.{ .string = cname });
            try self.emitU16(cname_idx);
            try self.emitByte(1);
            try self.emitByte(0);
        }
    }

    if (parent_node != 0) {
        const apnode = self.ast.nodes[parent_node];
        const parent_name = if (apnode.tag == .qualified_name) try self.buildQualifiedString(self.ast.extraSlice(apnode.data.lhs)) else self.resolveClassName(self.ast.tokenSlice(apnode.main_token));
        const parent_idx = try self.addConstant(.{ .string = parent_name });
        try self.emitU16(parent_idx);
    } else {
        try self.emitU16(0xffff);
    }

    try self.emitByte(@intCast(impl_count));
    for (0..impl_count) |i| {
        const iname_idx = try self.addConstant(.{ .string = impl_names[i] });
        try self.emitU16(iname_idx);
    }

    var all_traits = std.ArrayListUnmanaged([]const u8){};
    defer all_traits.deinit(self.allocator);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .trait_use) {
            for (self.ast.extraSlice(member.data.lhs)) |tn| {
                const tn_node = self.ast.nodes[tn];
                const raw_name = if (tn_node.tag == .qualified_name) blk: {
                    const parts = self.ast.extraSlice(tn_node.data.lhs);
                    break :blk try self.buildQualifiedString(parts);
                } else self.ast.tokenSlice(tn_node.main_token);
                try all_traits.append(self.allocator, self.resolveClassName(raw_name));
            }
        }
    }
    try self.emitByte(@intCast(all_traits.items.len));
    for (all_traits.items) |tname| {
        const tname_idx = try self.addConstant(.{ .string = tname });
        try self.emitU16(tname_idx);
    }

    const ConflictRule = struct { cnode: Ast.Node };
    var all_conflicts = std.ArrayListUnmanaged(ConflictRule){};
    defer all_conflicts.deinit(self.allocator);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .trait_use and member.data.rhs != 0) {
            for (self.ast.extraSlice(member.data.rhs)) |cn| {
                try all_conflicts.append(self.allocator, .{ .cnode = self.ast.nodes[cn] });
            }
        }
    }
    try self.emitByte(@intCast(all_conflicts.items.len));
    for (all_conflicts.items) |cr| {
        const method_name = self.ast.tokenSlice(cr.cnode.main_token);
        const trait_name = self.ast.tokenSlice(self.ast.nodes[cr.cnode.data.lhs].main_token);
        const method_idx = try self.addConstant(.{ .string = method_name });
        const trait_idx = try self.addConstant(.{ .string = trait_name });
        try self.emitU16(method_idx);
        try self.emitU16(trait_idx);
        if (cr.cnode.tag == .trait_insteadof) {
            try self.emitByte(1);
            const excluded = self.ast.extraSlice(cr.cnode.data.rhs);
            try self.emitByte(@intCast(excluded.len));
            for (excluded) |en| {
                const ename = self.ast.tokenSlice(self.ast.nodes[en].main_token);
                const eidx = try self.addConstant(.{ .string = ename });
                try self.emitU16(eidx);
            }
        } else {
            try self.emitByte(2);
            const alias = self.ast.tokenSlice(cr.cnode.data.rhs);
            const aidx = try self.addConstant(.{ .string = alias });
            try self.emitU16(aidx);
        }
    }

    // anonymous classes don't support attributes yet, emit empty
    try self.emitByte(0); // class attrs
    try self.emitByte(0); // method attrs
    try self.emitByte(0); // property attrs

    // now instantiate with constructor args
    for (0..ctor_arg_count) |i| {
        try self.compileNode(self.ast.extra_data[ctor_args_start + i]);
    }
    try self.emitOp(.new_obj);
    try self.emitU16(name_idx);
    try self.emitByte(@intCast(ctor_arg_count));
}

pub fn compileInterfaceDecl(self: *Compiler, node: Ast.Node) Error!void {
    const iface_name = self.resolveClassName(self.ast.tokenSlice(node.main_token));
    const members = self.ast.extraSlice(node.data.lhs);

    const prev_class = self.current_class;
    self.current_class = iface_name;
    defer self.current_class = prev_class;

    var method_count: u16 = 0;
    var const_count: u8 = 0;
    for (members) |m| {
        if (self.ast.nodes[m].tag == .interface_method) method_count += 1;
        if (self.ast.nodes[m].tag == .const_decl) const_count += 1;
    }

    // push null placeholders - real values set after interface_decl so self:: resolves
    for (members) |m| {
        const member = self.ast.nodes[m];
        if (member.tag == .const_decl) {
            try self.emitOp(.op_null);
        }
    }

    const name_idx = try self.addConstant(.{ .string = iface_name });
    try self.emitOp(.interface_decl);
    try self.emitU16(name_idx);
    try self.emitU16(method_count);

    for (members) |m| {
        const member = self.ast.nodes[m];
        if (member.tag == .interface_method) {
            const mname = self.ast.tokenSlice(member.main_token);
            const mname_idx = try self.addConstant(.{ .string = mname });
            try self.emitU16(mname_idx);
        }
    }

    if (node.data.rhs != 0) {
        const parent_count = self.ast.extra_data[node.data.rhs];
        try self.emitByte(@intCast(parent_count));
        for (0..parent_count) |i| {
            const pnode = self.ast.nodes[self.ast.extra_data[node.data.rhs + 1 + i]];
            const parent_name = if (pnode.tag == .qualified_name) try self.buildQualifiedString(self.ast.extraSlice(pnode.data.lhs)) else self.resolveClassName(self.ast.tokenSlice(pnode.main_token));
            const pidx = try self.addConstant(.{ .string = parent_name });
            try self.emitU16(pidx);
        }
    } else {
        try self.emitByte(0);
    }

    try self.emitByte(const_count);
    for (members) |m| {
        const member = self.ast.nodes[m];
        if (member.tag == .const_decl) {
            const cname = self.ast.tokenSlice(member.main_token);
            const cname_idx = try self.addConstant(.{ .string = cname });
            try self.emitU16(cname_idx);
        }
    }

    // set interface constants after interface_decl so self:: references resolve
    for (members) |m| {
        const member = self.ast.nodes[m];
        if (member.tag == .const_decl) {
            try self.compileNode(member.data.lhs);
            const cname = self.ast.tokenSlice(member.main_token);
            const cprop_idx = try self.addConstant(.{ .string = cname });
            try self.emitOp(.set_static_prop);
            try self.emitU16(name_idx);
            try self.emitU16(cprop_idx);
            try self.emitOp(.pop);
        }
    }
}

pub fn compileTraitDecl(self: *Compiler, node: Ast.Node) Error!void {
    const trait_name = self.resolveClassName(self.ast.tokenSlice(node.main_token));
    const members = self.ast.extraSlice(node.data.lhs);

    // compile trait methods as TraitName::methodName functions
    const prev_in_trait = self.in_trait;
    self.in_trait = true;
    defer self.in_trait = prev_in_trait;
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_method or member.tag == .static_class_method) {
            try compileClassMethodBody(self, trait_name, member);
        }
    }

    // collect sub-trait names from trait_use members
    var sub_traits = std.ArrayListUnmanaged([]const u8){};
    defer sub_traits.deinit(self.allocator);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .trait_use) {
            for (self.ast.extraSlice(member.data.lhs)) |tn| {
                const tn_node = self.ast.nodes[tn];
                const raw_name = if (tn_node.tag == .qualified_name) blk: {
                    const parts = self.ast.extraSlice(tn_node.data.lhs);
                    break :blk try self.buildQualifiedString(parts);
                } else self.ast.tokenSlice(tn_node.main_token);
                try sub_traits.append(self.allocator, self.resolveClassName(raw_name));
            }
        }
    }

    // store property member indices (own + sub-trait properties)
    var prop_indices = std.ArrayListUnmanaged(u32){};
    for (sub_traits.items) |st| {
        if (self.trait_properties.get(st)) |sub_props| {
            for (sub_props) |pi| try prop_indices.append(self.allocator, pi);
        }
    }
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_property) {
            try prop_indices.append(self.allocator, member_idx);
        }
    }
    if (prop_indices.items.len > 0) {
        const owned = try prop_indices.toOwnedSlice(self.allocator);
        try self.trait_properties.put(self.allocator, trait_name, owned);
    } else {
        prop_indices.deinit(self.allocator);
    }

    // collect own property members (not sub-trait props)
    var own_props = std.ArrayListUnmanaged(u32){};
    defer own_props.deinit(self.allocator);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_property) {
            try own_props.append(self.allocator, member_idx);
        }
    }

    // collect static property members
    var static_props = std.ArrayListUnmanaged(u32){};
    defer static_props.deinit(self.allocator);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .static_class_property) {
            try static_props.append(self.allocator, member_idx);
        }
    }

    // compile defaults for static properties first (popped second by VM)
    for (static_props.items) |pi| {
        const pmember = self.ast.nodes[pi];
        if (pmember.data.lhs != 0) {
            try self.compileNode(pmember.data.lhs);
        }
    }

    // compile defaults for own properties second (popped first by VM)
    for (own_props.items) |pi| {
        const pmember = self.ast.nodes[pi];
        if (pmember.data.lhs != 0) {
            try self.compileNode(pmember.data.lhs);
        }
    }

    const name_idx = try self.addConstant(.{ .string = trait_name });
    try self.emitOp(.trait_decl);
    try self.emitU16(name_idx);
    try self.emitByte(@intCast(sub_traits.items.len));
    for (sub_traits.items) |st| {
        const st_idx = try self.addConstant(.{ .string = st });
        try self.emitU16(st_idx);
    }
    try self.emitByte(@intCast(own_props.items.len));
    for (own_props.items) |pi| {
        const pmember = self.ast.nodes[pi];
        var pname = self.ast.tokenSlice(pmember.main_token);
        if (pname.len > 0 and pname[0] == '$') pname = pname[1..];
        const pname_idx = try self.addConstant(.{ .string = pname });
        try self.emitU16(pname_idx);
        try self.emitByte(if (pmember.data.lhs != 0) @as(u8, 1) else @as(u8, 0));
        try self.emitByte(@intCast(pmember.data.rhs));
    }
    try self.emitByte(@intCast(static_props.items.len));
    for (static_props.items) |pi| {
        const pmember = self.ast.nodes[pi];
        var pname = self.ast.tokenSlice(pmember.main_token);
        if (pname.len > 0 and pname[0] == '$') pname = pname[1..];
        const pname_idx = try self.addConstant(.{ .string = pname });
        try self.emitU16(pname_idx);
        try self.emitByte(if (pmember.data.lhs != 0) @as(u8, 1) else @as(u8, 0));
        try self.emitByte(@intCast(pmember.data.rhs));
    }
}

pub fn compileEnumDecl(self: *Compiler, node: Ast.Node) Error!void {
    const enum_name = self.resolveClassName(self.ast.tokenSlice(node.main_token));
    const members = self.ast.extraSlice(node.data.lhs);

    const rhs_base = node.data.rhs;
    const backed_type_token = self.ast.extra_data[rhs_base];
    const impl_count = self.ast.extra_data[rhs_base + 1];

    var backed_type: u8 = 0; // 0=none, 1=int, 2=string
    if (backed_type_token != 0) {
        const type_str = self.ast.tokenSlice(backed_type_token);
        if (std.mem.eql(u8, type_str, "int")) {
            backed_type = 1;
        } else if (std.mem.eql(u8, type_str, "string")) {
            backed_type = 2;
        }
    }

    var method_count: u16 = 0;
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_method or member.tag == .static_class_method) {
            try compileClassMethodBody(self, enum_name, member);
            method_count += 1;
        }
    }

    var case_count: u8 = 0;
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .enum_case) {
            if (member.data.lhs != 0) {
                try self.compileNode(member.data.lhs);
            }
            case_count += 1;
        }
    }

    const name_idx = try self.addConstant(.{ .string = enum_name });
    try self.emitOp(.enum_decl);
    try self.emitU16(name_idx);
    try self.emitByte(backed_type);
    try self.emitByte(case_count);

    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .enum_case) {
            const case_name = self.ast.tokenSlice(member.main_token);
            const cname_idx = try self.addConstant(.{ .string = case_name });
            try self.emitU16(cname_idx);
            try self.emitByte(if (member.data.lhs != 0) @as(u8, 1) else @as(u8, 0));
        }
    }

    try self.emitU16(method_count);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_method or member.tag == .static_class_method) {
            const method_name_str = self.ast.tokenSlice(member.main_token);
            const mname_idx = try self.addConstant(.{ .string = method_name_str });
            try self.emitU16(mname_idx);
            const param_nodes = self.ast.extraSlice(member.data.lhs);
            try self.emitByte(@intCast(param_nodes.len));
            try self.emitByte(if (member.tag == .static_class_method) @as(u8, 1) else @as(u8, 0));
            const vis: u8 = @intCast(member.data.rhs >> 30);
            try self.emitByte(vis);
        }
    }

    try self.emitByte(@intCast(impl_count));
    for (0..impl_count) |i| {
        const impl_node = self.ast.nodes[self.ast.extra_data[rhs_base + 2 + i]];
        const iname_idx = try self.addConstant(.{ .string = self.ast.tokenSlice(impl_node.main_token) });
        try self.emitU16(iname_idx);
    }

    const cname_idx = try self.addConstant(.{ .string = enum_name });
    const prev_class = self.current_class;
    self.current_class = enum_name;
    defer self.current_class = prev_class;
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .const_decl) {
            try self.compileNode(member.data.lhs);
            const const_name = self.ast.tokenSlice(member.main_token);
            const cprop_idx = try self.addConstant(.{ .string = const_name });
            try self.emitOp(.set_static_prop);
            try self.emitU16(cname_idx);
            try self.emitU16(cprop_idx);
            try self.emitOp(.pop);
        }
    }
}

fn compileClassMethodBody(self: *Compiler, class_name: []const u8, member: Ast.Node) Error!void {
    const prev_class = self.current_class;
    self.current_class = class_name;
    defer self.current_class = prev_class;

    const method_name = self.ast.tokenSlice(member.main_token);
    const full_name = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ class_name, method_name });
    try self.string_allocs.append(self.allocator, full_name);

    const param_nodes = self.ast.extraSlice(member.data.lhs);
    const param_names = try self.allocator.alloc([]const u8, param_nodes.len);
    const ref_flags = try self.allocator.alloc(bool, param_nodes.len);
    for (param_nodes, 0..) |p, i| {
        const pnode = self.ast.nodes[p];
        param_names[i] = self.ast.tokenSlice(pnode.main_token);
        ref_flags[i] = (pnode.data.rhs & 2) != 0;
    }

    var defaults = std.ArrayListUnmanaged(Value){};
    defer defaults.deinit(self.allocator);
    var required: u8 = 0;
    var seen_default = false;
    var is_variadic = false;
    for (param_nodes) |p| {
        const pnode = self.ast.nodes[p];
        if ((pnode.data.rhs & 1) != 0) {
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

    // bit 29 = generator flag (bits 30-31 = visibility)
    const method_gen = (member.data.rhs & (1 << 29)) != 0;

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
        .is_generator = method_gen,
        .closure_count = self.closure_count,
        .file_path = self.file_path,
        .namespace = self.namespace,
        .use_aliases = self.use_aliases,
        .use_fn_aliases = self.use_fn_aliases,
        .current_class = class_name,
        .current_function = method_name,
        .in_trait = self.in_trait,
    };
    errdefer {
        sub.chunk.deinit(self.allocator);
        sub.break_jumps.deinit(self.allocator);
        sub.continue_jumps.deinit(self.allocator);
        sub.string_allocs.deinit(self.allocator);
        sub.local_slots.deinit(self.allocator);
        sub.type_hints.deinit(self.allocator);
        sub.pending_gotos.deinit(self.allocator);
        sub.labels.deinit(self.allocator);
    }

    // slot 0 = $this for instance methods
    if (member.tag != .static_class_method) {
        _ = sub.getOrCreateSlot("$this");
    }
    for (param_nodes, 0..) |_, i| {
        if (ref_flags[i]) continue;
        _ = sub.getOrCreateSlot(param_names[i]);
    }

    // constructor property promotion: emit $this->prop = $prop for each promoted param
    if (std.mem.eql(u8, method_name, "__construct")) {
        for (param_nodes) |p| {
            const pnode = self.ast.nodes[p];
            const promotion = (pnode.data.rhs >> 2) & 3;
            if (promotion > 0) {
                var param_name = self.ast.tokenSlice(pnode.main_token);
                try sub.emitGetVar("$this");
                try sub.emitGetVar(param_name);
                if (param_name.len > 0 and param_name[0] == '$') param_name = param_name[1..];
                const prop_idx = try sub.addConstant(.{ .string = param_name });
                try sub.emitOp(.set_prop);
                try sub.emitU16(prop_idx);
                try sub.emitOp(.pop);
            }
        }
    }

    // mask out visibility (bits 30-31) and generator flag (bit 29)
    const body_idx = member.data.rhs & 0x1FFFFFFF;
    try sub.compileNode(body_idx);
    for (sub.pending_gotos.items) |pg| {
        if (sub.labels.get(pg.label)) |target| {
            sub.patchJumpTo(pg.offset, target);
        }
    }
    sub.pending_gotos.deinit(self.allocator);
    sub.labels.deinit(self.allocator);
    try sub.emitOp(.op_null);
    try sub.emitOp(if (method_gen) .generator_return else .return_val);
    sub.break_jumps.deinit(self.allocator);

    self.closure_count = sub.closure_count;
    const slot_names = try sub.buildSlotNames();
    const local_count = sub.next_slot;
    sub.local_slots.deinit(self.allocator);

    const method_lo = !method_gen and !is_variadic and !hasRefParams(ref_flags) and !needsVarSync(&sub.chunk) and sub.closure_count == 0;

    try self.functions.append(self.allocator, .{
        .name = full_name,
        .arity = @intCast(param_nodes.len),
        .required_params = required,
        .is_variadic = is_variadic,
        .is_generator = method_gen,
        .locals_only = method_lo,
        .params = param_names[0..param_nodes.len],
        .defaults = defaults_owned,
        .ref_params = ref_flags,
        .chunk = sub.chunk,
        .local_count = local_count,
        .slot_names = slot_names,
    });

    const param_types = try extractParamTypes(self, param_nodes);
    const return_type = try extractReturnType(self, member.data.lhs, @intCast(param_nodes.len));
    if (param_types.len > 0 or return_type.len > 0) {
        try self.type_hints.append(self.allocator, .{ .name = full_name, .param_types = param_types, .return_type = return_type });
    }

    for (sub.functions.items) |f| try self.functions.append(self.allocator, f);
    sub.functions.deinit(self.allocator);
    for (sub.string_allocs.items) |s| try self.string_allocs.append(self.allocator, s);
    sub.string_allocs.deinit(self.allocator);
    for (sub.type_hints.items) |th| try self.type_hints.append(self.allocator, th);
    sub.type_hints.deinit(self.allocator);
}

fn hasRefParams(ref_flags: []const bool) bool {
    for (ref_flags) |r| if (r) return true;
    return false;
}

fn needsVarSync(chunk: *const Chunk) bool {
    var i: usize = 0;
    const code = chunk.code.items;
    while (i < code.len) {
        const b = code[i];
        if (b == @intFromEnum(OpCode.concat_assign) or b == @intFromEnum(OpCode.get_global) or b == @intFromEnum(OpCode.get_static) or b == @intFromEnum(OpCode.closure_bind) or b == @intFromEnum(OpCode.closure_bind_ref))
            return true;
        i += opcodeWidth(b);
    }
    return false;
}

fn opcodeWidth(b: u8) usize {
    const op: OpCode = std.meta.intToEnum(OpCode, b) catch return 1;
    return switch (op) {
        // 1 + u16 = 3 bytes
        .constant, .get_var, .set_var, .jump, .jump_back, .jump_if_false, .jump_if_true,
        .jump_if_not_null, .push_handler, .get_prop, .set_prop, .get_local, .set_local,
        .get_global, .concat_assign, .unset_var, .unset_prop, .isset_prop,
        .closure_bind, .closure_bind_ref, .define_const,
        .iter_check, .inc_local, .dec_local, .trait_decl,
        => 3,
        // 1 + u16 + u8 = 4 bytes
        .call, .call_spread, .new_obj, .method_call, .method_call_spread, .static_call_dyn_method => 4,
        // 1 + u16 + u16 = 5 bytes
        .get_static_prop, .set_static_prop,
        .get_static, .set_static,
        .static_call_spread,
        .add_local_to_local, .sub_local_to_local, .mul_local_to_local,
        => 5,
        // 1 + u16 + u16 + u8 = 6 bytes
        .static_call => 6,
        // 1 + u16 + u16 + u16 = 7 bytes
        .less_local_local_jif => 7,
        // 1 + u8 = 2 bytes
        .require, .call_indirect, .call_indirect_spread, .method_call_dynamic, .static_call_dyn_both => 2,
        // variable-length: scan past inline operands
        .class_decl, .interface_decl, .enum_decl => 1,
        // all other opcodes are 1 byte (no operands)
        else => 1,
    };
}
