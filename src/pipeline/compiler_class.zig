const std = @import("std");
const php_types = @import("php_types.zig");
const compiler = @import("compiler.zig");
const class_names = @import("../runtime/class_names.zig");
const Compiler = @import("compiler.zig").Compiler;
const TypeHint = @import("compiler.zig").TypeHint;
const FunctionAttrEntry = @import("compiler.zig").FunctionAttrEntry;
const AttributeDef = @import("../runtime/vm.zig").AttributeDef;
const Ast = @import("ast.zig").Ast;
const Token = @import("token.zig").Token;
const Chunk = @import("bytecode.zig").Chunk;
const OpCode = @import("bytecode.zig").OpCode;
const ObjFunction = @import("bytecode.zig").ObjFunction;
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const Allocator = std.mem.Allocator;
const Error = Allocator.Error || error{CompileError};
// Declaration dependencies must use the same alias/absolute/namespace-relative
// resolution as expressions, including the early-binding eligibility pass.
const resolveNodeClassName = @import("compiler_expr.zig").resolveNodeClassName;
const compiler_stmt = @import("compiler_stmt.zig");

const ParsedAttr = struct {
    name: []const u8,
    args: []const Value,
    arg_names: []const ?[]const u8 = &.{},
};

fn isModifierToken(tag: Token.Tag) bool {
    return switch (tag) {
        .kw_public,
        .kw_protected,
        .kw_private,
        .kw_static,
        .kw_abstract,
        .kw_readonly,
        .kw_final,
        .kw_function,
        .kw_class,
        .kw_var,
        .kw_enum,
        .kw_interface,
        .kw_trait,
        .kw_const,
        .kw_case,
        => true,
        else => false,
    };
}

fn isTypeToken(tag: Token.Tag) bool {
    return switch (tag) {
        .identifier,
        .question,
        .pipe,
        .backslash,
        .amp,
        .kw_array,
        .kw_callable,
        .kw_self,
        .kw_parent,
        .kw_null,
        .kw_true,
        .kw_false,
        .kw_static,
        => true,
        else => false,
    };
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

// what a function's attributes ask of its calls. no_discard: the message
// of #[\NoDiscard] ("" without one). deprecated: the text #[\Deprecated]
// adds after "is deprecated" (" since 2.0, use x()", "" with neither part).
// null without the attribute. a void or never function can't be NoDiscard:
// php refuses at compile time
const CallAttrs = struct { no_discard: ?[]const u8 = null, deprecated: ?[]const u8 = null };

fn callAttributes(self: *Compiler, main_token: u32, return_type: []const u8, comptime kind: []const u8) Error!CallAttrs {
    var out: CallAttrs = .{};
    if (self.ast.attr_ranges.len == 0) return out;
    const attrs = try extractAttributes(self, main_token, .unchecked);
    defer freeParsedAttrs(self.allocator, attrs);
    for (attrs) |pa| {
        const name = if (pa.name.len > 0 and pa.name[0] == '\\') pa.name[1..] else pa.name;
        if (std.ascii.eqlIgnoreCase(name, "NoDiscard")) {
            if (std.ascii.eqlIgnoreCase(return_type, "void")) {
                return self.fail(main_token, "A void " ++ kind ++ " does not return a value, but #[\\NoDiscard] requires a return value");
            }
            if (std.ascii.eqlIgnoreCase(return_type, "never")) {
                return self.fail(main_token, "A never returning " ++ kind ++ " does not return a value, but #[\\NoDiscard] requires a return value");
            }
            // the texts outlive the attribute list
            out.no_discard = try keepString(self, try self.allocator.dupe(u8, attrArg(pa, 0, "message") orelse ""));
        } else if (std.ascii.eqlIgnoreCase(name, "Deprecated")) {
            for (pa.args) |arg| {
                const plain = arg == .null or (arg == .string and (arg.string.len == 0 or arg.string.bytes()[0] != 0));
                if (!plain) out.deprecated = @import("bytecode.zig").deferred_deprecation;
            }
            if (out.deprecated != null) continue;
            const message = attrArg(pa, 0, "message") orelse "";
            const since = attrArg(pa, 1, "since") orelse "";
            out.deprecated = try keepString(self, try std.fmt.allocPrint(self.allocator, "{s}{s}{s}{s}", .{
                if (since.len > 0) " since " else "", since,
                if (message.len > 0) ", " else "",    message,
            }));
        }
    }
    return out;
}

// a function's parameter attributes, filed with its own under
// paramAttributesName
fn appendParamAttributes(self: *Compiler, func_name: []const u8, param_nodes: []const u32) Error!void {
    for (param_nodes) |p| {
        const attrs = try extractAttributes(self, self.ast.nodes[p].main_token, AttrTarget.parameter);
        if (attrs.len == 0) continue;
        defer self.allocator.free(attrs);
        const defs = try self.allocator.alloc(AttributeDef, attrs.len);
        for (attrs, 0..) |pa, i| defs[i] = .{ .name = pa.name, .args = pa.args, .arg_names = pa.arg_names };
        const key = try @import("bytecode.zig").paramAttributesName(self.allocator, func_name, paramName(self, p));
        try self.string_allocs.append(self.allocator, key);
        try self.function_attrs.append(self.allocator, .{ .name = key, .attrs = defs });
    }
}

fn keepString(self: *Compiler, owned: []u8) Error![]const u8 {
    errdefer self.allocator.free(owned);
    try self.string_allocs.append(self.allocator, owned);
    return owned;
}

// a global constant's attributes, filed with the functions' under
// constantAttributesName and bound to the constant when its definition
// (the define_const just emitted) succeeds
pub fn emitConstantAttributes(self: *Compiler, main_token: u32, name_idx: u16) Error!void {
    const attrs = try extractAttributes(self, main_token, AttrTarget.constant);
    if (attrs.len == 0) return;
    defer self.allocator.free(attrs);
    const defs = try self.allocator.alloc(AttributeDef, attrs.len);
    for (attrs, 0..) |pa, i| defs[i] = .{ .name = pa.name, .args = pa.args, .arg_names = pa.arg_names };
    const key = try @import("bytecode.zig").constantAttributesName(self.allocator, self.file_path, main_token);
    try self.string_allocs.append(self.allocator, key);
    try self.function_attrs.append(self.allocator, .{ .name = key, .attrs = defs });
    try self.emitOp(.bind_const_attributes);
    try self.emitU16(name_idx);
    try self.emitU16(try self.addConstant(.{ .string = Value.String.borrowed(key) }));
}

// what a #[\Deprecated] on the declaration at main_token adds after "is
// deprecated" (" since 2.0, use X", or ""), null without the attribute
pub fn deprecationOfDecl(self: *Compiler, main_token: u32) Error!?[]const u8 {
    return (try callAttributes(self, main_token, "", "constant")).deprecated;
}

// a string attribute argument by position or name
fn attrArg(pa: ParsedAttr, position: usize, name: []const u8) ?[]const u8 {
    for (pa.args, 0..) |arg, i| {
        const arg_name: ?[]const u8 = if (i < pa.arg_names.len) pa.arg_names[i] else null;
        const matches = if (arg_name) |n| std.mem.eql(u8, n, name) else i == position;
        if (!matches or arg != .string) continue;
        // an argument evaluated at run time has no text here
        if (@import("bytecode.zig").attrArgumentInitializerName(arg.string.bytes()) != null) return null;
        return arg.string.bytes();
    }
    return null;
}

fn freeParsedAttrs(allocator: Allocator, attrs: []const ParsedAttr) void {
    if (attrs.len == 0) return;
    for (attrs) |a| {
        for (a.args) |v| freeParsedAttrValue(allocator, v);
        if (a.args.len > 0) allocator.free(a.args);
        if (a.arg_names.len > 0) allocator.free(a.arg_names);
    }
    allocator.free(attrs);
}

fn freeParsedAttrValue(allocator: Allocator, value: Value) void {
    if (value != .array or Value.isEmptyArrayDefault(value)) return;
    for (value.array.entries.items) |entry| freeParsedAttrValue(allocator, if (entry.ref) |ref| ref.* else entry.value);
    value.array.deinit(allocator);
    allocator.destroy(value.array);
}

// what an attribute list is written on, for php's checks of its internal
// attributes (zend_compile_attributes): a target's Attribute::TARGET_* bit,
// or a class declaration, which its validators also look at
pub const AttrTarget = union(enum) {
    // read again for something other than declaring it
    unchecked,
    flags: u8,
    class: struct { kind: ClassKind, name: []const u8, modifiers: u8 = 0 },

    pub const ClassKind = enum { class, interface, trait, @"enum" };
    pub const function: AttrTarget = .{ .flags = 2 };
    pub const method: AttrTarget = .{ .flags = 4 };
    pub const property: AttrTarget = .{ .flags = 8 };
    pub const class_constant: AttrTarget = .{ .flags = 16 };
    pub const parameter: AttrTarget = .{ .flags = 32 };
    pub const constant: AttrTarget = .{ .flags = 64 };
    // a promoted constructor parameter is a parameter and a property
    pub const promoted: AttrTarget = .{ .flags = 32 | 8 };
};

// the internal attributes and the targets their #[Attribute] allows
const internal_attributes = [_]struct { name: []const u8, flags: u8, repeatable: bool = false }{
    .{ .name = "Attribute", .flags = 1 },
    .{ .name = "ReturnTypeWillChange", .flags = 4 },
    .{ .name = "AllowDynamicProperties", .flags = 1 },
    .{ .name = "SensitiveParameter", .flags = 32 },
    .{ .name = "Override", .flags = 12 },
    .{ .name = "Deprecated", .flags = 87 },
    .{ .name = "NoDiscard", .flags = 6 },
    .{ .name = "DelayedTargetValidation", .flags = 127 },
};

fn bareAttributeName(name: []const u8) []const u8 {
    return if (name.len > 0 and name[0] == '\\') name[1..] else name;
}

fn targetNames(buf: []u8, flags: u8) []const u8 {
    const names = [_][]const u8{ "class", "function", "method", "property", "class constant", "parameter", "constant" };
    var len: usize = 0;
    for (names, 0..) |n, bit| {
        if (flags & (@as(u8, 1) << @intCast(bit)) == 0) continue;
        const sep: []const u8 = if (len > 0) ", " else "";
        if (len + sep.len + n.len > buf.len) break;
        @memcpy(buf[len..][0..sep.len], sep);
        len += sep.len;
        @memcpy(buf[len..][0..n.len], n);
        len += n.len;
    }
    return buf[0..len];
}

fn checkInternalAttributes(self: *Compiler, attrs: []const ParsedAttr, target: AttrTarget, at: u32) Error!void {
    const target_flags: u8 = switch (target) {
        .unchecked => return,
        .flags => |f| f,
        .class => 1,
    };
    var delayed = false;
    for (attrs) |pa| {
        if (std.ascii.eqlIgnoreCase(bareAttributeName(pa.name), "DelayedTargetValidation")) delayed = true;
    }
    for (attrs, 0..) |pa, i| {
        const name = bareAttributeName(pa.name);
        const config = for (internal_attributes) |ia| {
            if (std.ascii.eqlIgnoreCase(ia.name, name)) break ia;
        } else continue;
        var run_validator = true;
        if (target_flags & config.flags == 0) {
            if (!delayed) {
                var where_buf: [96]u8 = undefined;
                var allowed_buf: [96]u8 = undefined;
                return self.failFmt(at, "Attribute \"{s}\" cannot target {s} (allowed targets: {s})", .{ name, targetNames(&where_buf, target_flags), targetNames(&allowed_buf, config.flags) });
            }
            run_validator = false;
        }
        if (!config.repeatable) {
            for (attrs[i + 1 ..]) |other| {
                if (std.ascii.eqlIgnoreCase(bareAttributeName(other.name), name)) return self.failFmt(at, "Attribute \"{s}\" must not be repeated", .{name});
            }
        }
        if (run_validator and target == .class) try validateClassAttribute(self, config.name, target.class, at);
    }
}

// the validators php runs for an internal attribute on a class
fn validateClassAttribute(self: *Compiler, attribute: []const u8, class: @FieldType(AttrTarget, "class"), at: u32) Error!void {
    const readonly = class.modifiers & 4 != 0;
    const abstract = class.modifiers & 1 != 0;
    const refused: ?[]const u8 = if (std.mem.eql(u8, attribute, "AllowDynamicProperties")) switch (class.kind) {
        .trait => "trait",
        .interface => "interface",
        .@"enum" => "enum",
        .class => if (readonly) "readonly class" else null,
    } else if (std.mem.eql(u8, attribute, "Attribute")) switch (class.kind) {
        .trait => "trait",
        .interface => "interface",
        .@"enum" => "enum",
        .class => if (abstract) "abstract class" else null,
    } else if (std.mem.eql(u8, attribute, "Deprecated")) switch (class.kind) {
        .trait => null,
        .interface => "interface",
        .@"enum" => "enum",
        .class => "class",
    } else null;
    const kind = refused orelse return;
    const shown = class_names.display(class.name);
    return self.failFmt(at, "Cannot apply #[\\{s}] to {s} {s}", .{ attribute, kind, shown });
}

fn extractAttributes(self: *Compiler, main_token: u32, target: AttrTarget) Error![]const ParsedAttr {
    const ar = findAttrRangeForToken(self.ast.attr_ranges, self.ast.tokens, main_token) orelse return &.{};
    const items = self.ast.extraSlice(ar.items);
    var all_attrs = std.ArrayListUnmanaged(ParsedAttr).empty;
    errdefer {
        for (all_attrs.items) |a| {
            for (a.args) |v| freeParsedAttrValue(self.allocator, v);
            self.allocator.free(a.args);
            self.allocator.free(a.arg_names);
        }
        all_attrs.deinit(self.allocator);
    }
    var i: usize = 0;
    while (i + 2 < items.len) : (i += 3) {
        var raw_name = std.ArrayListUnmanaged(u8).empty;
        defer raw_name.deinit(self.allocator);
        for (items[i]..items[i + 1]) |t| try raw_name.appendSlice(self.allocator, self.ast.tokenSlice(@intCast(t)));
        const kept = try self.allocator.dupe(u8, raw_name.items);
        try self.string_allocs.append(self.allocator, kept);
        // apply namespace + use-alias resolution so #[Assert\NotBlank]
        // inside `use ... as Assert` becomes the fully-qualified class name
        const name = self.resolveClassName(kept);

        const arg_nodes: []const u32 = if (items[i + 2] == ast_mod.AttrRange.no_args) &.{} else self.ast.extraSlice(items[i + 2]);
        const args = try self.allocator.alloc(Value, arg_nodes.len);
        @memset(args, .null);
        const arg_names = try self.allocator.alloc(?[]const u8, arg_nodes.len);
        @memset(arg_names, null);
        try all_attrs.append(self.allocator, .{ .name = name, .args = args, .arg_names = arg_names });
        var named = false;
        for (arg_nodes, 0..) |arg_idx, ai| {
            const arg = self.ast.nodes[arg_idx];
            var value_idx = arg_idx;
            switch (arg.tag) {
                .splat_expr => return self.fail(main_token, "Cannot use unpacking in attribute argument list"),
                .named_arg => {
                    const arg_name = self.ast.tokenSlice(arg.main_token);
                    for (arg_names[0..ai]) |earlier| {
                        if (earlier) |e| if (std.mem.eql(u8, e, arg_name)) return self.failFmt(main_token, "Duplicate named parameter ${s}", .{arg_name});
                    }
                    arg_names[ai] = arg_name;
                    named = true;
                    value_idx = arg.data.lhs;
                },
                else => if (named) return self.fail(main_token, "Cannot use positional argument after named argument"),
            }
            args[ai] = try attributeArgument(self, value_idx, main_token);
        }
    }
    try checkInternalAttributes(self, all_attrs.items, target, main_token);
    return all_attrs.toOwnedSlice(self.allocator);
}

// an argument that folds is stored as its value; anything else becomes an
// initializer the vm runs when reflection asks, in the scope of the class
// the attribute is in
fn attributeArgument(self: *Compiler, idx: u32, target: u32) Error!Value {
    if (hasEmptyArrayElement(self.ast, idx)) return self.fail(target, "Cannot use empty array elements in arrays");
    if (hasDynamicClassConstant(self.ast, idx)) return self.fail(target, "Dynamic class names are not allowed in compile-time class constant references");
    if (!allowedInConstExpr(self.ast, idx)) return self.fail(target, "Constant expression contains invalid operations");
    if (findStaticClass(self.ast, idx) != null) return self.fail(target, "static::class cannot be used for compile-time class name resolution");
    if (namedClassName(self, idx)) |name| return .{ .string = Value.String.borrowed(name) };
    if (attrArgFolds(self, idx)) return self.evalConstExpr(idx);
    const name = try @import("bytecode.zig").attrArgumentInitializer(self.allocator, self.file_path, self.ast.nodes[idx].main_token);
    try self.string_allocs.append(self.allocator, name);
    var compiled = false;
    for (self.functions.items) |f| {
        if (std.mem.eql(u8, f.name, name)) compiled = true;
    }
    if (!compiled) try compileInitializer(self, name, .argument, idx, self.ast.nodes[idx].main_token);
    return .{ .string = Value.String.borrowed(name) };
}

// `[,]` anywhere in the expression, which php refuses before anything else
fn hasEmptyArrayElement(ast: *const Ast, idx: u32) bool {
    if (idx == 0) return false;
    const node = ast.nodes[idx];
    return switch (node.tag) {
        .array_literal => for (ast.extraSlice(node.data.lhs)) |el_idx| {
            if (el_idx == 0) break true;
            const el = ast.nodes[el_idx];
            if (hasEmptyArrayElement(ast, el.data.lhs)) break true;
            if (el.tag == .array_element and hasEmptyArrayElement(ast, el.data.rhs)) break true;
        } else false,
        .binary_op, .logical_and, .logical_or, .null_coalesce, .array_access => hasEmptyArrayElement(ast, node.data.lhs) or hasEmptyArrayElement(ast, node.data.rhs),
        .grouped_expr, .cast_expr, .prefix_op, .property_access, .nullsafe_property_access => hasEmptyArrayElement(ast, node.data.lhs),
        else => false,
    };
}

// `expr::CONST` with a class that isn't a name
fn hasDynamicClassConstant(ast: *const Ast, idx: u32) bool {
    if (idx == 0) return false;
    const node = ast.nodes[idx];
    return switch (node.tag) {
        .static_prop_access => switch (ast.nodes[node.data.lhs].tag) {
            .identifier, .qualified_name => false,
            else => !std.mem.startsWith(u8, ast.tokenSlice(node.main_token), "$"),
        },
        .dynamic_class_const => true,
        .array_literal => for (ast.extraSlice(node.data.lhs)) |el_idx| {
            if (el_idx == 0) continue;
            const el = ast.nodes[el_idx];
            if (hasDynamicClassConstant(ast, el.data.lhs)) break true;
            if (el.tag == .array_element and hasDynamicClassConstant(ast, el.data.rhs)) break true;
        } else false,
        .binary_op, .logical_and, .logical_or, .null_coalesce, .array_access => hasDynamicClassConstant(ast, node.data.lhs) or hasDynamicClassConstant(ast, node.data.rhs),
        .grouped_expr, .cast_expr, .prefix_op, .property_access, .nullsafe_property_access => hasDynamicClassConstant(ast, node.data.lhs),
        else => false,
    };
}

// php's zend_is_allowed_in_const_expr over the whole expression: literals,
// constants, class constants, operators, arrays, `new`, property reads,
// casts, closures and first-class callables
fn allowedInConstExpr(ast: *const Ast, idx: u32) bool {
    if (idx == 0) return true;
    const node = ast.nodes[idx];
    return switch (node.tag) {
        .integer_literal, .float_literal, .string_literal, .true_literal, .false_literal, .null_literal => true,
        .identifier, .qualified_name, .closure_expr, .callable_ref => true,
        .binary_op, .logical_and, .logical_or, .null_coalesce, .array_access => allowedInConstExpr(ast, node.data.lhs) and allowedInConstExpr(ast, node.data.rhs),
        .grouped_expr, .cast_expr => allowedInConstExpr(ast, node.data.lhs),
        .prefix_op => switch (ast.tokens[node.main_token].tag) {
            .plus_plus, .minus_minus => false,
            else => allowedInConstExpr(ast, node.data.lhs),
        },
        .ternary => allowedInConstExpr(ast, node.data.lhs) and
            node.data.rhs + 1 < ast.extra_data.len and
            allowedInConstExpr(ast, ast.extra_data[node.data.rhs]) and
            allowedInConstExpr(ast, ast.extra_data[node.data.rhs + 1]),
        .property_access, .nullsafe_property_access => allowedInConstExpr(ast, node.data.lhs) and
            (ast.nodes[node.data.rhs].tag == .identifier or allowedInConstExpr(ast, node.data.rhs)),
        // Class::CONST and Class::class, not Class::$property
        .static_prop_access => !std.mem.startsWith(u8, ast.tokenSlice(node.main_token), "$") and
            allowedInConstExpr(ast, node.data.lhs),
        .array_literal => {
            for (ast.extraSlice(node.data.lhs)) |el_idx| {
                const el = ast.nodes[el_idx];
                switch (el.tag) {
                    .array_element => if (!allowedInConstExpr(ast, el.data.lhs) or !allowedInConstExpr(ast, el.data.rhs)) return false,
                    .array_spread => if (!allowedInConstExpr(ast, el.data.lhs)) return false,
                    else => return false,
                }
            }
            return true;
        },
        .new_expr => {
            for (ast.extraSlice(node.data.lhs)) |arg_idx| {
                const arg = ast.nodes[arg_idx];
                const value = if (arg.tag == .named_arg or arg.tag == .splat_expr) arg.data.lhs else arg_idx;
                if (!allowedInConstExpr(ast, value)) return false;
            }
            return true;
        },
        else => false,
    };
}

// the token of a static::class inside a constant expression
fn findStaticClass(ast: *const Ast, idx: u32) ?u32 {
    const node = ast.nodes[idx];
    switch (node.tag) {
        .static_prop_access => {
            const class_node = ast.nodes[node.data.lhs];
            if (class_node.tag == .identifier and std.ascii.eqlIgnoreCase(ast.tokenSlice(class_node.main_token), "static") and
                std.ascii.eqlIgnoreCase(ast.tokenSlice(node.main_token), "class")) return node.main_token;
            return null;
        },
        .prefix_op, .grouped_expr => return findStaticClass(ast, node.data.lhs),
        .binary_op => return findStaticClass(ast, node.data.lhs) orelse findStaticClass(ast, node.data.rhs),
        .array_literal => {
            for (ast.extraSlice(node.data.lhs)) |el_idx| {
                const el = ast.nodes[el_idx];
                if (el.tag != .array_element) continue;
                if (findStaticClass(ast, el.data.lhs)) |t| return t;
                if (el.data.rhs != 0) if (findStaticClass(ast, el.data.rhs)) |t| return t;
            }
            return null;
        },
        else => return null,
    }
}

// Name::class for a name that isn't self, parent or static
fn namedClassName(self: *Compiler, idx: u32) ?[]const u8 {
    const node = self.ast.nodes[idx];
    if (node.tag != .static_prop_access or !std.mem.eql(u8, self.ast.tokenSlice(node.main_token), "class")) return null;
    const class_node = self.ast.nodes[node.data.lhs];
    if (class_node.tag != .identifier) return null;
    const written = self.ast.tokenSlice(class_node.main_token);
    for ([_][]const u8{ "self", "parent", "static" }) |relative| {
        if (std.ascii.eqlIgnoreCase(written, relative)) return null;
    }
    return self.resolveClassName(written);
}

fn attrArgFolds(self: *Compiler, idx: u32) bool {
    const node = self.ast.nodes[idx];
    return switch (node.tag) {
        .integer_literal, .float_literal, .true_literal, .false_literal, .null_literal => true,
        .string_literal => true,
        .prefix_op, .grouped_expr => attrArgFolds(self, node.data.lhs),
        .binary_op => attrArgFolds(self, node.data.lhs) and attrArgFolds(self, node.data.rhs),
        .array_literal => {
            for (self.ast.extraSlice(node.data.lhs)) |el_idx| {
                const el = self.ast.nodes[el_idx];
                if (el.tag != .array_element) return false;
                if (!attrArgFolds(self, el.data.lhs)) return false;
                if (el.data.rhs != 0 and !attrArgFolds(self, el.data.rhs)) return false;
            }
            return true;
        },
        // Attribute's own target flags, which php folds too
        .static_prop_access => blk: {
            const class_node = self.ast.nodes[node.data.lhs];
            if (class_node.tag != .identifier) break :blk false;
            const class_name = self.ast.tokenSlice(class_node.main_token);
            break :blk std.mem.eql(u8, class_name, "Attribute") or std.mem.eql(u8, class_name, "\\Attribute");
        },
        else => false,
    };
}

fn freeAttrSlice(allocator: Allocator, attrs: []const ParsedAttr) void {
    freeParsedAttrs(allocator, attrs);
}

fn emitAttributeData(self: *Compiler, attrs: []const ParsedAttr) Error!void {
    try self.emitByte(@intCast(attrs.len));
    for (attrs) |attr| {
        const name_idx = try self.addConstant(.{ .string = Value.String.borrowed(attr.name) });
        try self.emitU16(name_idx);
        // an attribute can take any number of arguments
        try self.emitU32(@intCast(attr.args.len));
        for (attr.args, 0..) |arg, i| {
            // emit named arg flag: 0 = positional, 1 = named (followed by name constant index)
            if (i < attr.arg_names.len) {
                if (attr.arg_names[i]) |arg_name| {
                    try self.emitByte(1);
                    const an_idx = try self.addConstant(.{ .string = Value.String.borrowed(arg_name) });
                    try self.emitU16(an_idx);
                } else {
                    try self.emitByte(0);
                }
            } else {
                try self.emitByte(0);
            }
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
            const arr = val.array;
            var has_string_keys = false;
            for (arr.entries.items) |entry| {
                if (entry.key == .string) {
                    has_string_keys = true;
                    break;
                }
            }
            if (has_string_keys) {
                try self.emitByte(0x07); // associative array
                const len: u16 = @intCast(arr.entries.items.len);
                try self.emitU16(len);
                for (arr.entries.items) |entry| {
                    switch (entry.key) {
                        .string => |s| {
                            try self.emitByte(0x01); // string key
                            const kidx = try self.addConstant(.{ .string = s });
                            try self.emitU16(kidx);
                        },
                        .int => |ki| {
                            try self.emitByte(0x00); // int key
                            const bytes: [8]u8 = @bitCast(ki);
                            for (bytes) |b| try self.emitByte(b);
                        },
                    }
                    try emitAttrValue(self, entry.value);
                }
            } else {
                try self.emitByte(0x06); // sequential array
                const len: u16 = @intCast(arr.entries.items.len);
                try self.emitU16(len);
                for (arr.entries.items) |entry| {
                    try emitAttrValue(self, entry.value);
                }
            }
        },
        else => try self.emitByte(0x00),
    }
}

fn buildTypeString(self: *Compiler, start_tok: u32, end_tok: u32) Error![]const u8 {
    if (start_tok == end_tok) return "";
    try checkTypeDeclaration(self, start_tok, end_tok);

    // A type expression is structured as:
    //   ?T   |   T1|T2|T3   |   T1&T2   |   (T1&T2)|T3
    // where each T is either a primitive ("string"), a backslash-prefixed FQN
    // (`\A\B\C`), or a relative name (`A\B\C`) that needs its first segment
    // namespace-resolved exactly once. Process the token stream piecewise so
    // each side of a union/intersection gets resolved independently
    var buf = std.ArrayListUnmanaged(u8).empty;
    var i: u32 = start_tok;
    var at_segment_start: bool = true; // true between separators/parens/`?`
    var segment_first_ident_done: bool = false;
    var segment_is_fqn: bool = false;

    while (i < end_tok) : (i += 1) {
        const tag = self.ast.tokens[i].tag;
        const lexeme = self.ast.tokens[i].lexeme(self.ast.source);

        // separators reset the per-segment state
        const is_separator = std.mem.eql(u8, lexeme, "|") or std.mem.eql(u8, lexeme, "&") or
            std.mem.eql(u8, lexeme, "(") or std.mem.eql(u8, lexeme, ")");

        if (is_separator) {
            try buf.appendSlice(self.allocator, lexeme);
            at_segment_start = true;
            segment_first_ident_done = false;
            segment_is_fqn = false;
            continue;
        }

        // nullable marker is allowed at segment start; emit and stay at start
        if (at_segment_start and std.mem.eql(u8, lexeme, "?")) {
            try buf.appendSlice(self.allocator, lexeme);
            continue;
        }

        // leading backslash means FQN for this segment - emit it but mark so
        // we don't apply namespace resolution to the first identifier
        if (at_segment_start and std.mem.eql(u8, lexeme, "\\")) {
            segment_is_fqn = true;
            // we drop the leading backslash; resolveClassName outputs without it
            // and the rest of the runtime treats FQN and resolved equivalently
            at_segment_start = false;
            continue;
        }

        if (tag == .identifier and !isPrimitiveType(lexeme) and !segment_is_fqn and !segment_first_ident_done) {
            try buf.appendSlice(self.allocator, self.resolveClassName(lexeme));
            segment_first_ident_done = true;
            at_segment_start = false;
            continue;
        }

        try buf.appendSlice(self.allocator, lexeme);
        at_segment_start = false;
        if (tag == .identifier) segment_first_ident_done = true;
    }

    const s = try buf.toOwnedSlice(self.allocator);
    try self.string_allocs.append(self.allocator, s);
    return s;
}

// one name of a written type: a built-in type or a class
const TypeName = struct {
    written: []const u8,
    // the built-in type's bits, 0 for a class
    mask: u32 = 0,
    iterable: bool = false,
    // the class php compiles it to: resolved, self and parent substituted
    // where the scope is known
    class: []const u8 = "",

    fn isClass(n: TypeName) bool {
        return n.mask == 0 and !n.iterable;
    }
};

// how zend_type_to_string prints one name
fn typeNameString(self: *Compiler, n: TypeName) Error![]const u8 {
    if (n.iterable) return "Traversable|array";
    if (n.isClass()) return n.class;
    const text = php_types.format(self.allocator, .{ .mask = n.mask }) catch return error.OutOfMemory;
    try self.string_allocs.append(self.allocator, text);
    return text;
}

fn readTypeName(self: *Compiler, tok: *u32, end_tok: u32) Error!TypeName {
    const start = tok.*;
    var qualified = false;
    while (tok.* < end_tok) : (tok.* += 1) {
        const lexeme = self.ast.tokens[tok.*].lexeme(self.ast.source);
        if (std.mem.eql(u8, lexeme, "|") or std.mem.eql(u8, lexeme, "&") or std.mem.eql(u8, lexeme, ")") or std.mem.eql(u8, lexeme, "(")) break;
        if (std.mem.indexOfScalar(u8, lexeme, '\\') != null) qualified = true;
    }
    if (tok.* == start) return self.fail(start, "syntax error, unexpected type");
    const first = self.ast.tokens[start].start;
    const last = self.ast.tokens[tok.* - 1];
    const written = self.ast.source[first .. last.start + last.lexeme(self.ast.source).len];
    var lower_buf: [16]u8 = undefined;
    const lower = if (written.len <= lower_buf.len) std.ascii.lowerString(&lower_buf, written) else "";
    if (qualified) try checkQualifiedTypeName(self, start, written);
    if (!qualified and std.mem.eql(u8, lower, "static") and self.current_class.len == 0 and !self.closure_signature and !std.mem.startsWith(u8, self.current_function, "{closure:")) {
        return self.fail(start, "Cannot use \"static\" when no class scope is active");
    }
    // zend_ensure_valid_class_fetch_type, where the scope is known
    if (!qualified and (std.mem.eql(u8, lower, "self") or std.mem.eql(u8, lower, "parent")) and typeScopeKnown(self)) {
        if (self.current_class.len == 0) return self.failFmt(start, "Cannot use \"{s}\" when no class scope is active", .{lower});
        if (std.mem.eql(u8, lower, "parent") and self.current_parent.len == 0) return self.fail(start, "Cannot use \"parent\" when current class scope has no parent");
    }
    if (!qualified) {
        if (std.mem.eql(u8, lower, "iterable")) return .{ .written = written, .iterable = true, .mask = php_types.ARRAY };
        const builtin = std.StaticStringMap(u32).initComptime(.{
            .{ "null", php_types.NULL },       .{ "false", php_types.FALSE }, .{ "true", php_types.TRUE },
            .{ "bool", php_types.BOOL },       .{ "int", php_types.LONG },    .{ "float", php_types.DOUBLE },
            .{ "string", php_types.STRING },   .{ "array", php_types.ARRAY }, .{ "object", php_types.OBJECT },
            .{ "callable", php_types.CALLABLE }, .{ "void", php_types.VOID }, .{ "never", php_types.NEVER },
            .{ "static", php_types.STATIC },   .{ "mixed", php_types.ANY },
        });
        if (builtin.get(lower)) |mask| return .{ .written = written, .mask = mask };
    }
    const scope_known = self.current_class.len > 0 and !self.in_trait and !class_names.isAnonymous(self.current_class);
    if (!qualified and scope_known and std.mem.eql(u8, lower, "self")) return .{ .written = written, .class = self.current_class };
    if (!qualified and scope_known and std.mem.eql(u8, lower, "parent") and self.current_parent.len > 0) return .{ .written = written, .class = self.current_parent };
    if (!qualified and (std.mem.eql(u8, lower, "self") or std.mem.eql(u8, lower, "parent"))) return .{ .written = written, .class = written };
    const class = if (written[0] == '\\') written[1..] else self.resolveClassName(written);
    return .{ .written = written, .class = class };
}

// zend_is_scope_known while compiling a type: not in a closure or a
// trait, and in a class or a function
fn typeScopeKnown(self: *Compiler) bool {
    if (self.closure_signature or std.mem.startsWith(u8, self.current_function, "{closure:")) return false;
    if (self.current_class.len == 0) return self.current_function.len > 0 or self.named_signature;
    return !self.in_trait;
}

// a qualified type name (`\Foo`, `namespace\Foo`, `Foo\Bar`): a built-in
// type can't be written qualified, `\self` names no class, and a name
// ending in a reserved word is refused (zend_compile_single_typename)
fn checkQualifiedTypeName(self: *Compiler, at: u32, written: []const u8) Error!void {
    const bare = if (written[0] == '\\') written[1..] else if (std.ascii.startsWithIgnoreCase(written, "namespace\\")) written["namespace\\".len..] else written;
    if (std.mem.indexOfScalar(u8, bare, '\\') == null) {
        var buf: [16]u8 = undefined;
        if (bare.len <= buf.len) {
            const lower = std.ascii.lowerString(&buf, bare);
            const builtin = std.StaticStringMap(void).initComptime(.{
                .{"null"},   .{"false"},    .{"true"},  .{"bool"},  .{"int"},    .{"float"},  .{"string"},
                .{"array"},  .{"object"},   .{"callable"}, .{"void"}, .{"never"}, .{"static"}, .{"mixed"}, .{"iterable"},
            });
            if (builtin.has(lower)) return self.failFmt(at, "Type declaration '{s}' must be unqualified", .{lower});
            if (written[0] == '\\' and (std.mem.eql(u8, lower, "self") or std.mem.eql(u8, lower, "parent"))) return self.failFmt(at, "'\\{s}' is an invalid class name", .{bare});
        }
    }
    const resolved = if (written[0] == '\\') written[1..] else self.resolveClassName(written);
    if (isReservedClassName(resolved)) return self.failFmt(at, "Cannot use \"{s}\" as a type name as it is reserved", .{resolved});
}

// zend_is_reserved_class_name: the last segment of the name
pub fn isReservedClassName(name: []const u8) bool {
    const last = if (std.mem.lastIndexOfScalar(u8, name, '\\')) |i| name[i + 1 ..] else name;
    const reserved = [_][]const u8{ "bool", "false", "float", "int", "null", "parent", "self", "static", "string", "true", "void", "never", "iterable", "object", "mixed" };
    for (reserved) |r| if (std.ascii.eqlIgnoreCase(last, r)) return true;
    return false;
}

// the members of an intersection, checked as php's compiler checks them
fn readIntersection(self: *Compiler, arena: std.mem.Allocator, tok: *u32, end_tok: u32, list: *std.ArrayListUnmanaged(TypeName)) Error!void {
    while (true) {
        const at = tok.*;
        const n = try readTypeName(self, tok, end_tok);
        if (!n.isClass()) return self.failFmt(at, "Type {s} cannot be part of an intersection type", .{try typeNameString(self, n)});
        if (std.ascii.eqlIgnoreCase(n.class, "self") or std.ascii.eqlIgnoreCase(n.class, "parent")) {
            return self.failFmt(at, "Type {s} cannot be part of an intersection type", .{n.class});
        }
        for (list.items) |prev| {
            if (std.ascii.eqlIgnoreCase(prev.class, n.class)) return self.failFmt(at, "Duplicate type {s} is redundant", .{n.class});
        }
        try list.append(arena, n);
        if (tok.* < end_tok and std.mem.eql(u8, self.ast.tokens[tok.*].lexeme(self.ast.source), "&")) {
            tok.* += 1;
            continue;
        }
        return;
    }
}

fn intersectionString(self: *Compiler, names: []const TypeName) Error![]const u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    for (names, 0..) |n, i| {
        if (i > 0) try out.append(self.allocator, '&');
        try out.appendSlice(self.allocator, n.class);
    }
    const text = try out.toOwnedSlice(self.allocator);
    try self.string_allocs.append(self.allocator, text);
    return text;
}

// php's zend_compile_typename checks: a declared type that repeats a type,
// mixes types that make each other redundant, or puts a standalone type in a
// union or intersection is a compile-time fatal error
fn checkTypeDeclaration(self: *Compiler, start_tok: u32, end_tok: u32) Error!void {
    var arena_state = std.heap.ArenaAllocator.init(self.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var tok = start_tok;
    const nullable = std.mem.eql(u8, self.ast.tokens[tok].lexeme(self.ast.source), "?");
    if (nullable) tok += 1;

    // a union: each member a name or a parenthesized intersection
    const Member = struct { names: []const TypeName, intersection: bool };
    var members: std.ArrayListUnmanaged(Member) = .empty;
    var mask: u32 = 0;
    var has_class = false;
    var has_only_iterable_class = true;
    var pure_intersection = false;
    var first = true;
    while (tok < end_tok) {
        const at = tok;
        const lexeme = self.ast.tokens[tok].lexeme(self.ast.source);
        if (std.mem.eql(u8, lexeme, "(")) {
            tok += 1;
            var group: std.ArrayListUnmanaged(TypeName) = .empty;
            try readIntersection(self, arena, &tok, end_tok, &group);
            tok += 1; // )
            has_only_iterable_class = false;
            has_class = true;
            for (members.items) |prev| {
                if (prev.intersection) {
                    try checkIntersectionsRedundant(self, at, group.items, prev.names);
                } else if (prev.names[0].isClass()) {
                    try checkIntersectionRedundantBySingle(self, at, group.items, prev.names[0]);
                }
            }
            try members.append(arena, .{ .names = group.items, .intersection = true });
        } else {
            const n = try readTypeName(self, &tok, end_tok);
            if (first and tok < end_tok and std.mem.eql(u8, self.ast.tokens[tok].lexeme(self.ast.source), "&")) {
                // a type that is one intersection
                tok += 1;
                var group: std.ArrayListUnmanaged(TypeName) = .empty;
                var single_tok = at;
                try readIntersection(self, arena, &single_tok, end_tok, &group);
                tok = single_tok;
                pure_intersection = true;
                try members.append(arena, .{ .names = group.items, .intersection = true });
                has_class = true;
                break;
            }
            if (n.mask == php_types.ANY and (tok < end_tok or !first)) return self.fail(at, "Type mixed can only be used as a standalone type");
            const bits = if (n.iterable) php_types.ARRAY else n.mask;
            if (mask & bits != 0) {
                const overlap = php_types.format(self.allocator, .{ .mask = mask & bits }) catch return error.OutOfMemory;
                defer self.allocator.free(overlap);
                return self.failFmt(at, "Duplicate type {s} is redundant", .{overlap});
            }
            if ((mask & php_types.TRUE != 0 and bits == php_types.FALSE) or (mask & php_types.FALSE != 0 and bits == php_types.TRUE)) {
                return self.fail(at, "Type contains both true and false, bool must be used instead");
            }
            mask |= bits;
            const class_name: ?[]const u8 = if (n.iterable) "Traversable" else if (n.isClass()) n.class else null;
            if (class_name) |cn| {
                if (!n.iterable) has_only_iterable_class = false;
                has_class = true;
                for (members.items) |prev| {
                    if (prev.intersection) {
                        try checkIntersectionRedundantBySingle(self, at, prev.names, .{ .written = cn, .class = cn });
                        continue;
                    }
                    const prev_class = if (prev.names[0].iterable) "Traversable" else prev.names[0].class;
                    if ((prev.names[0].isClass() or prev.names[0].iterable) and std.ascii.eqlIgnoreCase(prev_class, cn)) {
                        return self.failFmt(at, "Duplicate type {s} is redundant", .{cn});
                    }
                }
                try members.append(arena, .{ .names = try arena.dupe(TypeName, &.{if (n.iterable) TypeName{ .written = n.written, .class = "Traversable", .iterable = true } else n}), .intersection = false });
            }
        }
        first = false;
        if (tok < end_tok and std.mem.eql(u8, self.ast.tokens[tok].lexeme(self.ast.source), "|")) tok += 1;
    }

    if (!pure_intersection and mask & php_types.OBJECT != 0 and ((!has_only_iterable_class and has_class) or mask & php_types.STATIC != 0)) {
        var names: std.ArrayListUnmanaged([]const u8) = .empty;
        for (members.items) |m| {
            if (m.intersection) {
                try names.append(arena, try std.fmt.allocPrint(arena, "({s})", .{try intersectionString(self, m.names)}));
            } else {
                try names.append(arena, m.names[0].class);
            }
        }
        var text: std.ArrayListUnmanaged(u8) = .empty;
        for (names.items, 0..) |name, i| {
            if (i > 0) try text.append(arena, '|');
            try text.appendSlice(arena, name);
        }
        const builtins = php_types.format(arena, .{ .mask = mask & ~(if (has_only_iterable_class) @as(u32, 0) else 0) }) catch return error.OutOfMemory;
        if (builtins.len > 0) {
            if (text.items.len > 0) try text.append(arena, '|');
            try text.appendSlice(arena, builtins);
        }
        return self.failFmt(start_tok, "Type {s} contains both object and a class type, which is redundant", .{text.items});
    }

    if (mask == php_types.ANY and nullable) return self.fail(start_tok, "Type mixed cannot be marked as nullable since mixed already includes null");
    if (mask & php_types.NULL != 0 and nullable) return self.fail(start_tok, "null cannot be marked as nullable");
    const full = if (nullable) mask | php_types.NULL else mask;
    if (full & php_types.VOID != 0 and (has_class or full != php_types.VOID)) return self.fail(start_tok, "Void can only be used as a standalone type");
    if (full & php_types.NEVER != 0 and (has_class or full != php_types.NEVER)) return self.fail(start_tok, "never can only be used as a standalone type");
}

// zend_are_intersection_types_redundant
fn checkIntersectionsRedundant(self: *Compiler, at: u32, left: []const TypeName, right: []const TypeName) Error!void {
    const flipped = right.len < left.len;
    const smaller = if (flipped) right else left;
    const larger = if (flipped) left else right;
    var shared: usize = 0;
    for (smaller) |outer| {
        for (larger) |inner| {
            if (std.ascii.eqlIgnoreCase(inner.class, outer.class)) {
                shared += 1;
                break;
            }
        }
    }
    if (shared != smaller.len) return;
    const smaller_text = try intersectionString(self, if (flipped) right else left);
    const larger_text = try intersectionString(self, if (flipped) left else right);
    if (smaller.len == larger.len) return self.failFmt(at, "Type {s} is redundant with type {s}", .{ smaller_text, larger_text });
    return self.failFmt(at, "Type {s} is redundant as it is more restrictive than type {s}", .{ larger_text, smaller_text });
}

// zend_is_intersection_type_redundant_by_single_type
fn checkIntersectionRedundantBySingle(self: *Compiler, at: u32, intersection: []const TypeName, single: TypeName) Error!void {
    for (intersection) |n| {
        if (std.ascii.eqlIgnoreCase(n.class, single.class)) {
            return self.failFmt(at, "Type {s} is redundant as it is more restrictive than type {s}", .{ try intersectionString(self, intersection), single.class });
        }
    }
}

// the type of a parameter default php folds at compile time (a literal, or
// an array or operation of literals); null for one that names a constant or
// anything php evaluates later
const DefaultKind = enum { null, true, false, int, float, string, array };

fn foldedDefault(self: *Compiler, idx: u32) ?DefaultKind {
    if (idx == 0 or !foldsAtCompileTime(self.ast, idx)) return null;
    const node = self.ast.nodes[idx];
    return switch (node.tag) {
        .null_literal => .null,
        .true_literal => .true,
        .false_literal => .false,
        .integer_literal => .int,
        .float_literal => .float,
        .string_literal => .string,
        .array_literal => .array,
        else => switch (self.evalConstExpr(idx)) {
            .null => .null,
            .bool => |b| if (b) .true else .false,
            .int => .int,
            .float => .float,
            .string => .string,
            else => null,
        },
    };
}

// zend_is_valid_default_value: whether a folded value fits a declared type
// (an int fits a float), and the value's type name for the error
fn defaultFits(kind: DefaultKind, t: php_types.Type) struct { bool, []const u8 } {
    return switch (kind) {
        .null => .{ t.mask & php_types.NULL != 0, "null" },
        .true => .{ t.mask & php_types.TRUE != 0, "bool" },
        .false => .{ t.mask & php_types.FALSE != 0, "bool" },
        .int => .{ t.mask & (php_types.LONG | php_types.DOUBLE) != 0, "int" },
        .float => .{ t.mask & php_types.DOUBLE != 0, "float" },
        .string => .{ t.mask & php_types.STRING != 0, "string" },
        .array => .{ t.mask & php_types.ARRAY != 0, "array" },
    };
}

// php's zend_compile_class_const_decl checks: a private constant can't be
// final, and a typed constant's literal value must fit its type
// zend_compile_prop_decl: the types a property can't have, and a literal
// default its type can't hold
fn checkPropDecls(self: *Compiler, class_name: []const u8, members: []const u32) Error!void {
    for (members) |m_idx| {
        const m = self.ast.nodes[m_idx];
        if (m.tag != .class_property and m.tag != .static_class_property and m.tag != .class_property_hooks) continue;
        const type_extra = m.data.rhs >> 16;
        if (type_extra == 0) continue;
        const raw = self.ast.tokenSlice(m.main_token);
        const name = if (raw.len > 0 and raw[0] == '$') raw[1..] else raw;
        const text = try buildTypeString(self, self.ast.extra_data[type_extra - 1], self.ast.extra_data[type_extra]);
        const t = php_types.parse(self.allocator, text, null, null) catch return error.OutOfMemory;
        defer t.deinit(self.allocator);
        if (t.mask & (php_types.VOID | php_types.NEVER | php_types.CALLABLE) != 0) {
            const shown = php_types.format(self.allocator, t) catch return error.OutOfMemory;
            defer self.allocator.free(shown);
            return self.failFmt(m.main_token, "Property {s}::${s} cannot have type {s}", .{ class_name, name, shown });
        }
        const default_idx = if (m.tag == .class_property_hooks) self.ast.extra_data[m.data.lhs] else m.data.lhs;
        if (default_idx == 0) continue;
        const kind = foldedDefault(self, default_idx) orelse continue;
        const accepted, const kind_name = defaultFits(kind, t);
        if (accepted) continue;
        const shown = php_types.format(self.allocator, t) catch return error.OutOfMemory;
        defer self.allocator.free(shown);
        if (kind == .null and !t.pure_intersection) {
            var nullable = t;
            nullable.mask |= php_types.NULL;
            const nullable_shown = php_types.format(self.allocator, nullable) catch return error.OutOfMemory;
            defer self.allocator.free(nullable_shown);
            return self.failFmt(m.main_token, "Default value for property of type {s} may not be null. Use the nullable type {s} to allow null default value", .{ shown, nullable_shown });
        }
        return self.failFmt(m.main_token, "Cannot use {s} as default value for property {s}::${s} of type {s}", .{ kind_name, class_name, name, shown });
    }
}

fn checkConstDecls(self: *Compiler, class_name: []const u8, members: []const u32) Error!void {
    const outer_class = self.current_class;
    self.current_class = class_name;
    defer self.current_class = outer_class;
    for (members) |m_idx| {
        const m = self.ast.nodes[m_idx];
        if (m.tag != .const_decl) continue;
        const name = self.ast.tokenSlice(m.main_token);
        if (m.data.rhs & 0x3 == 2 and m.data.rhs & 0x10 != 0) {
            return self.failFmt(m.main_token, "Private constant {s}::{s} cannot be final as it is not visible to other classes", .{ class_name, name });
        }
        const type_extra = m.data.rhs >> 16;
        if (type_extra == 0) continue;
        const text = try buildTypeString(self, self.ast.extra_data[type_extra - 1], self.ast.extra_data[type_extra]);
        const t = php_types.parse(self.allocator, text, class_name, null) catch return error.OutOfMemory;
        defer t.deinit(self.allocator);
        if (t.mask & (php_types.CALLABLE | php_types.VOID | php_types.NEVER) != 0) {
            const shown = php_types.format(self.allocator, t) catch return error.OutOfMemory;
            defer self.allocator.free(shown);
            return self.failFmt(m.main_token, "Class constant {s}::{s} cannot have type {s}", .{ class_name, name, shown });
        }
        const kind = foldedDefault(self, m.data.lhs) orelse continue;
        const accepted, const kind_name = defaultFits(kind, t);
        if (accepted) continue;
        const type_text = php_types.format(self.allocator, t) catch return error.OutOfMemory;
        defer self.allocator.free(type_text);
        return self.failFmt(m.main_token, "Cannot use {s} as value for class constant {s}::{s} of type {s}", .{ kind_name, class_name, name, type_text });
    }
}

fn foldsAtCompileTime(ast: *const Ast, idx: u32) bool {
    const node = ast.nodes[idx];
    return switch (node.tag) {
        .integer_literal, .float_literal, .string_literal, .true_literal, .false_literal, .null_literal => true,
        .prefix_op, .grouped_expr => foldsAtCompileTime(ast, node.data.lhs),
        .binary_op => foldsAtCompileTime(ast, node.data.lhs) and foldsAtCompileTime(ast, node.data.rhs),
        .array_literal => {
            for (ast.extraSlice(node.data.lhs)) |el_idx| {
                const el = ast.nodes[el_idx];
                if (el.tag != .array_element) return false;
                if (!foldsAtCompileTime(ast, el.data.lhs)) return false;
                if (el.data.rhs != 0 and !foldsAtCompileTime(ast, el.data.rhs)) return false;
            }
            return true;
        },
        else => false,
    };
}

// php counts every parameter up to the last one without a default as
// required: an optional parameter before a required one becomes required
fn requiredParamCount(ast: *const Ast, param_nodes: []const u32) u8 {
    var count: u8 = 0;
    for (param_nodes, 0..) |p, i| {
        const node = ast.nodes[p];
        if (node.data.lhs == 0 and (node.data.rhs & 1) == 0) count = @intCast(i + 1);
    }
    return count;
}

fn paramName(self: *Compiler, p: u32) []const u8 {
    const raw = self.ast.tokenSlice(self.ast.nodes[p].main_token);
    return if (raw.len > 0 and raw[0] == '$') raw[1..] else raw;
}

// the checks and deprecations php's zend_compile_params makes on a
// function's declared return and parameters
fn checkParams(self: *Compiler, func_name: []const u8, at: u32, param_nodes: []const u32, return_type: []const u8, returns_ref: bool) Error!void {
    const scope: ?[]const u8 = if (self.current_class.len > 0) self.current_class else null;
    const parent: ?[]const u8 = if (self.current_parent.len > 0) self.current_parent else null;
    if (returns_ref and return_type.len > 0) {
        const t = php_types.parse(self.allocator, return_type, scope, parent) catch return error.OutOfMemory;
        defer t.deinit(self.allocator);
        if (t.mask & php_types.VOID != 0) try self.warn(at, 8192, "{s}(): Returning by reference from a void function is deprecated", .{func_name});
    }
    var last_required: ?usize = null;
    for (param_nodes, 0..) |p, i| {
        const node = self.ast.nodes[p];
        if (node.data.lhs == 0 and (node.data.rhs & 1) == 0) last_required = i;
    }
    for (param_nodes, 0..) |p, i| {
        const node = self.ast.nodes[p];
        const promoted = ((node.data.rhs >> 2) & 3) != 0 or (node.data.rhs & 16) != 0 or ((node.data.rhs >> 5) & 3) != 0;
        const default = foldedDefault(self, node.data.lhs);
        const force_nullable = default == .null and !promoted;
        var forced_nullable = false;
        const type_extra = node.data.rhs >> 8;
        if (type_extra != 0) {
            const text = try buildTypeString(self, self.ast.extra_data[type_extra - 1], self.ast.extra_data[type_extra]);
            const t = php_types.parse(self.allocator, text, scope, parent) catch return error.OutOfMemory;
            defer t.deinit(self.allocator);
            if (force_nullable and t.mask & php_types.NULL == 0) {
                forced_nullable = true;
                try self.warn(at, 8192, "{s}(): Implicitly marking parameter ${s} as nullable is deprecated, the explicit nullable type must be used instead", .{ func_name, paramName(self, p) });
            }
            if (t.mask & php_types.VOID != 0) return self.fail(at, "void cannot be used as a parameter type");
            if (t.mask & php_types.NEVER != 0) return self.fail(at, "never cannot be used as a parameter type");
            if (default) |kind_of| if (!force_nullable) {
                const accepted, const kind = defaultFits(kind_of, t);
                if (!accepted) {
                    const type_text = php_types.format(self.allocator, t) catch return error.OutOfMemory;
                    defer self.allocator.free(type_text);
                    return self.failFmt(at, "Cannot use {s} as default value for parameter ${s} of type {s}", .{ kind, paramName(self, p), type_text });
                }
            };
        }
        if (last_required) |required| if (i < required and node.data.lhs != 0 and !forced_nullable) {
            try self.warn(at, 8192, "{s}(): Optional parameter ${s} declared before required parameter ${s} is implicitly treated as a required parameter", .{ func_name, paramName(self, p), paramName(self, param_nodes[required]) });
        };
    }
}

fn isPrimitiveType(name: []const u8) bool {
    const primitives = [_][]const u8{
        "int",    "integer", "float",     "double",   "bool",     "boolean",
        "string", "array",   "object",    "callable", "void",     "null",
        "false",  "true",    "mixed",     "never",    "iterable", "self",
        "static", "parent",  "Generator", "Fiber",    "Closure",
    };
    for (primitives) |p| {
        if (std.mem.eql(u8, name, p)) return true;
    }
    return false;
}

// reads the type-hint token range out of a class_property node's rhs upper
// bits (set by the parser) and returns a constant-pool index for the rendered
// type string, or 0xFFFF when the property had no type declaration
// counts newlines from the start of source up to a byte offset to derive a
// 1-based line number. used to populate ObjFunction.start_line so that
// ReflectionFunction::getStartLine can report PHP-style line numbers
fn lineForToken(self: *Compiler, tok_idx: u32) u32 {
    if (tok_idx >= self.ast.tokens.len) return 0;
    return lineForOffset(self, self.ast.tokens[tok_idx].start);
}

fn lineForOffset(self: *Compiler, off: u32) u32 {
    const src = self.ast.source;
    const clamped = @min(off, src.len);
    var line: u32 = 1;
    for (src[0..clamped]) |c| if (c == '\n') {
        line += 1;
    };
    return line;
}

// scans forward from a token, balancing braces, to find the matching r_brace
// for a class/trait/interface/enum body. returns the line of the closing brace
// scans source backwards from a token's start position through trivia
// (whitespace + line/block comments) looking for the last `/** ... */` doc
// comment that immediately precedes it. returns the full comment text or ""
fn isDeclLeadingTokenTag(tag: Token.Tag) bool {
    return switch (tag) {
        .kw_function,
        .kw_class,
        .kw_interface,
        .kw_trait,
        .kw_const,
        .kw_case,
        .kw_enum,
        .kw_public,
        .kw_protected,
        .kw_private,
        .kw_static,
        .kw_final,
        .kw_abstract,
        .kw_readonly,
        // type hints in front of a parameter / property
        .identifier,
        .kw_array,
        .kw_callable,
        .kw_self,
        .kw_parent,
        .question,
        .pipe,
        .amp,
        .backslash,
        .l_paren,
        .r_paren,
        => true,
        else => false,
    };
}

fn docCommentForToken(self: *Compiler, tok_idx: u32) []const u8 {
    if (tok_idx >= self.ast.tokens.len) return "";
    // walk back through modifier/keyword tokens (function, class, public,
    // static, etc) to find the leading edge of the declaration. the doc
    // comment lives in the trivia that precedes that leading token
    var lead = tok_idx;
    while (lead > 0) {
        const prev_tag = self.ast.tokens[lead - 1].tag;
        if (!isDeclLeadingTokenTag(prev_tag)) break;
        lead -= 1;
    }
    const tok_start = self.ast.tokens[lead].start;
    var trivia_start: usize = 0;
    if (lead > 0) trivia_start = self.ast.tokens[lead - 1].end;
    if (trivia_start >= tok_start) return "";
    const trivia = self.ast.source[trivia_start..tok_start];

    // walk trivia forwards collecting doc comments; keep the LAST one found
    var last_start: ?usize = null;
    var last_end: usize = 0;
    var i: usize = 0;
    while (i < trivia.len) {
        const c = trivia[i];
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
            i += 1;
            continue;
        }
        if (c == '/' and i + 1 < trivia.len and trivia[i + 1] == '/') {
            while (i < trivia.len and trivia[i] != '\n') i += 1;
            continue;
        }
        if (c == '#' and (i + 1 >= trivia.len or trivia[i + 1] != '[')) {
            while (i < trivia.len and trivia[i] != '\n') i += 1;
            continue;
        }
        if (c == '/' and i + 1 < trivia.len and trivia[i + 1] == '*') {
            const block_start = i;
            const is_doc = i + 2 < trivia.len and trivia[i + 2] == '*' and (i + 3 >= trivia.len or trivia[i + 3] != '/');
            i += 2;
            while (i + 1 < trivia.len) : (i += 1) {
                if (trivia[i] == '*' and trivia[i + 1] == '/') {
                    i += 2;
                    break;
                }
            } else {
                i = trivia.len;
            }
            if (is_doc) {
                last_start = block_start;
                last_end = i;
            }
            continue;
        }
        // unrecognized char in trivia - bail
        break;
    }
    if (last_start) |s| return trivia[s..last_end];
    return "";
}

fn endLineForBlockStartingAt(self: *Compiler, start_tok: u32) u32 {
    var depth: i32 = 0;
    var i: u32 = start_tok;
    while (i < self.ast.tokens.len) : (i += 1) {
        const tag: Token.Tag = self.ast.tokens[i].tag;
        if (tag == .l_brace) {
            depth += 1;
        } else if (tag == .r_brace) {
            depth -= 1;
            if (depth == 0) return lineForToken(self, i);
        }
    }
    return 0;
}

// last source offset recorded in a function's chunk approximates the closing
// brace - the implicit return instruction sits there
fn endLineForChunk(self: *Compiler, chunk: *const Chunk) u32 {
    if (chunk.lines.items.len == 0) return 0;
    const last = chunk.lines.items[chunk.lines.items.len - 1];
    return lineForOffset(self, last);
}

fn docCommentConst(self: *Compiler, tok_idx: u32) Error!u16 {
    const doc = docCommentForToken(self, tok_idx);
    if (doc.len == 0) return 0xffff;
    return @intCast(try self.addConstant(.{ .string = Value.String.borrowed(doc) }));
}

// zend_compile_prop_decl's and zend_compile_property_hooks' checks of a
// hooked or abstract property, before anything is emitted
fn checkPropertyDeclaration(self: *Compiler, class_name: []const u8, member: Ast.Node, in_interface: bool) Error!void {
    const H = ast_mod.PropertyHooks;
    const flags = member.data.rhs;
    const at = member.main_token;
    const raw = self.ast.tokenSlice(at);
    const prop = if (raw.len > 0 and raw[0] == '$') raw[1..] else raw;
    const visibility = flags & 3;
    if (in_interface and member.tag == .class_property_hooks) {
        if (flags & H.prop_abstract != 0) return self.fail(at, "Property in interface cannot be explicitly abstract. All interface members are implicitly abstract");
        if (visibility != 0) return self.fail(at, "Property in interface cannot be protected or private");
        if (flags & (1 << 7) != 0) return self.fail(at, "Property in interface cannot be final");
    }
    if (member.tag != .class_property_hooks) {
        if (member.tag == .class_property and flags & H.prop_abstract != 0) return self.fail(at, "Only hooked properties may be declared abstract");
        return;
    }
    const ext = member.data.lhs;
    const written = self.ast.extraSlice(self.ast.extra_data[ext + 8]);
    const is_abstract = flags & H.prop_abstract != 0;
    if (is_abstract and flags & (1 << 7) != 0) return self.failParse(at, "Cannot use the final modifier on an abstract property", .{});
    if (flags & (1 << 7) != 0 and visibility == 2) return self.fail(at, "Property cannot be both final and private");
    if (flags & H.prop_static_hooked != 0) return self.fail(at, "Cannot declare hooks for static property");
    if (flags & (1 << 2) != 0) return self.fail(at, "Hooked properties cannot be readonly");
    if (written.len == 0) return self.fail(at, "Property hook list must not be empty");

    var seen_get = false;
    var seen_set = false;
    var any_abstract = false;
    var i: usize = 0;
    while (i + 3 < written.len) : (i += 4) {
        const hook_tok = written[i];
        const hook_flags = written[i + 1];
        const params = written[i + 2];
        const other_modifier = written[i + 3];
        const name = self.ast.tokenSlice(hook_tok);
        if (other_modifier != 0) return self.failParse(other_modifier, "Cannot use the {s} modifier on a property hook", .{self.ast.tokenSlice(other_modifier)});
        const is_get = std.ascii.eqlIgnoreCase(name, "get");
        const is_set = std.ascii.eqlIgnoreCase(name, "set");
        if (!is_get and !is_set) return self.failFmt(hook_tok, "Unknown hook \"{s}\" for property {s}::${s}, expected \"get\" or \"set\"", .{ name, class_name, prop });
        if ((is_get and seen_get) or (is_set and seen_set)) return self.failFmt(hook_tok, "Cannot redeclare property hook \"{s}\"", .{name});
        if (is_get) seen_get = true else seen_set = true;
        const hook_abstract = hook_flags & H.hook_abstract != 0 or ((is_abstract or in_interface) and hook_flags & H.hook_bodyless != 0);
        if (hook_abstract) any_abstract = true;
        if (hook_abstract and hook_flags & H.hook_final != 0) return self.fail(hook_tok, "Property hook cannot be both abstract and final");
        if (hook_flags & H.hook_final != 0 and visibility == 2) return self.fail(hook_tok, "Property hook cannot be both final and private");
        if (hook_abstract and visibility == 2) return self.fail(hook_tok, "Property hook cannot be both abstract and private");
        if (params == H.no_hook_params) continue;
        const param_nodes = self.ast.extraSlice(params);
        if (is_get) return self.failFmt(hook_tok, "get hook of property {s}::${s} must not have a parameter list", .{ class_name, prop });
        if (param_nodes.len != 1) return self.failFmt(hook_tok, "set hook of property {s}::${s} must accept exactly one parameters", .{ class_name, prop });
        const param = self.ast.nodes[param_nodes[0]];
        const pname = self.ast.tokenSlice(param.main_token);
        if (param.data.rhs & 1 != 0) return self.failFmt(param.main_token, "Parameter {s} of set hook {s}::${s} must not be variadic", .{ pname, class_name, prop });
        if (param.data.rhs & 2 != 0) return self.failFmt(param.main_token, "Parameter {s} of set hook {s}::${s} must not be pass-by-reference", .{ pname, class_name, prop });
        if (param.data.lhs != 0) return self.failFmt(param.main_token, "Parameter {s} of set hook {s}::${s} must not have a default value", .{ pname, class_name, prop });
        try checkSetHookParamType(self, class_name, prop, flags, param);
    }
    if (is_abstract and !in_interface and !any_abstract) return self.failFmt(at, "Abstract property {s}::${s} must specify at least one abstract hook", .{ class_name, prop });
    // a virtual property (no hook reaches its storage) has no default. a
    // parent's property may give it storage, which only the declaration
    // knows
    const backed = self.ast.extra_data[ext + 4] & 32 != 0;
    if (!backed and self.current_parent.len == 0 and self.ast.extra_data[ext] != 0) return self.failFmt(at, "Cannot specify default value for virtual hooked property {s}::${s}", .{ class_name, prop });
}

// a set hook's parameter takes at least what the property holds; a check
// that needs to know classes is left to the declaration, as php defers it
fn checkSetHookParamType(self: *Compiler, class_name: []const u8, prop: []const u8, prop_flags: u32, param: Ast.Node) Error!void {
    const prop_extra = prop_flags >> 16;
    if (prop_extra == 0) return;
    const prop_type = try buildTypeString(self, self.ast.extra_data[prop_extra - 1], self.ast.extra_data[prop_extra]);
    const param_extra = param.data.rhs >> 8;
    const incompatible = if (param_extra == 0) true else blk: {
        const param_type = try buildTypeString(self, self.ast.extra_data[param_extra - 1], self.ast.extra_data[param_extra]);
        const parent: ?[]const u8 = if (self.current_parent.len > 0) self.current_parent else null;
        const p = php_types.parse(self.allocator, prop_type, class_name, parent) catch return error.OutOfMemory;
        defer p.deinit(self.allocator);
        const q = php_types.parse(self.allocator, param_type, class_name, parent) catch return error.OutOfMemory;
        defer q.deinit(self.allocator);
        break :blk php_types.covariant(no_classes, class_name, p, q) == .failure;
    };
    if (incompatible) return self.failFmt(param.main_token, "Type of parameter {s} of hook {s}::${s}::set must be compatible with property type", .{ self.ast.tokenSlice(param.main_token), class_name, prop });
}

// the compiler knows no classes: a question about one is unresolved
const no_classes: php_types.Classes = .{
    .context = undefined,
    .exists = struct {
        fn f(_: *anyopaque, _: []const u8) bool {
            return false;
        }
    }.f,
    .subtype = struct {
        fn f(_: *anyopaque, _: []const u8, _: []const u8) bool {
            return false;
        }
    }.f,
    .is_final = struct {
        fn f(_: *anyopaque, _: []const u8) bool {
            return false;
        }
    }.f,
};

// the insteadof and as rules of a declaration's `use` statements: a count,
// then per rule the method, the trait (or ""), and 1 with the excluded traits
// or 2 with the alias and its visibility
fn emitTraitRules(self: *Compiler, members: []const u32) Error!void {
    var rules = std.ArrayListUnmanaged(Ast.Node).empty;
    defer rules.deinit(self.allocator);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .trait_use and member.data.rhs != 0) {
            for (self.ast.extraSlice(member.data.rhs)) |cn| try rules.append(self.allocator, self.ast.nodes[cn]);
        }
    }
    try self.emitByte(@intCast(rules.items.len));
    for (rules.items) |rule| {
        const method_name = self.ast.tokenSlice(rule.main_token);
        // trait names resolve like any class name: namespace and imports
        const trait_name = if (rule.data.lhs == 0) "" else try resolveNodeClassName(self, self.ast.nodes[rule.data.lhs]);
        try self.emitU16(try self.addConstant(.{ .string = Value.String.borrowed(method_name) }));
        try self.emitU16(try self.addConstant(.{ .string = Value.String.borrowed(trait_name) }));
        if (rule.tag == .trait_insteadof) {
            try self.emitByte(1);
            const excluded = self.ast.extraSlice(rule.data.rhs);
            try self.emitByte(@intCast(excluded.len));
            for (excluded) |en| {
                const ename = try resolveNodeClassName(self, self.ast.nodes[en]);
                try self.emitU16(try self.addConstant(.{ .string = Value.String.borrowed(ename) }));
            }
        } else {
            try self.emitByte(2);
            const alias_token: u32 = rule.data.rhs & 0x3FFFFFFF;
            try self.emitU16(try self.addConstant(.{ .string = Value.String.borrowed(self.ast.tokenSlice(alias_token)) }));
            try self.emitByte(@intCast(rule.data.rhs >> 30));
        }
    }
}

fn propertyTypeConst(self: *Compiler, prop_rhs: u32) Error!u16 {
    const type_extra = prop_rhs >> 16;
    if (type_extra == 0) return 0xffff;
    const idx = type_extra - 1;
    const start_tok = self.ast.extra_data[idx];
    const end_tok = self.ast.extra_data[idx + 1];
    const type_str = try buildTypeString(self, start_tok, end_tok);
    return @intCast(try self.addConstant(.{ .string = Value.String.borrowed(type_str) }));
}

fn extractParamTypes(self: *Compiler, param_nodes: []const u32) Error![]const []const u8 {
    var has_any = false;
    for (param_nodes) |p| {
        const rhs = self.ast.nodes[p].data.rhs;
        if ((rhs >> 8) != 0) {
            has_any = true;
            break;
        }
    }
    if (!has_any) return &.{};

    const types = try self.allocator.alloc([]const u8, param_nodes.len);
    for (param_nodes, 0..) |p, i| {
        const rhs = self.ast.nodes[p].data.rhs;
        const type_extra_idx = rhs >> 8;
        if (type_extra_idx == 0) {
            types[i] = "";
        } else {
            const idx = type_extra_idx - 1;
            const start_tok = self.ast.extra_data[idx];
            const end_tok = self.ast.extra_data[idx + 1];
            const text = try buildTypeString(self, start_tok, end_tok);
            types[i] = if (implicitlyNullable(self, p) and php_types.shape(text).mask & php_types.NULL == 0) blk: {
                // `T $x = null` declares ?T (deprecated, but still the type)
                const nullable = try std.fmt.allocPrint(self.allocator, "?{s}", .{text});
                try self.string_allocs.append(self.allocator, nullable);
                break :blk nullable;
            } else text;
        }
    }
    return types;
}

// a parameter's folded default; an int default of a float parameter is
// stored as the float (zend_is_valid_default_value converts it)
fn paramDefaultValue(self: *Compiler, pnode: Ast.Node) Error!Value {
    const value = self.evalConstExpr(pnode.data.lhs);
    if (value != .int) return value;
    const type_extra = pnode.data.rhs >> 8;
    if (type_extra == 0) return value;
    const text = try buildTypeString(self, self.ast.extra_data[type_extra - 1], self.ast.extra_data[type_extra]);
    const mask = php_types.shape(text).mask;
    if (mask & php_types.DOUBLE != 0 and mask & php_types.LONG == 0) return .{ .float = @floatFromInt(value.int) };
    return value;
}

// a parameter whose default is null and that isn't promoted takes null
// whatever its declared type says (zend_compile_params' force_nullable)
fn implicitlyNullable(self: *Compiler, p: u32) bool {
    const node = self.ast.nodes[p];
    const promoted = ((node.data.rhs >> 2) & 3) != 0 or (node.data.rhs & 16) != 0 or ((node.data.rhs >> 5) & 3) != 0;
    return !promoted and node.data.lhs != 0 and foldedDefault(self, node.data.lhs) == .null;
}

fn extractReturnType(self: *Compiler, extra_base: u32, param_count: u32) Error![]const u8 {
    const ret_start = self.ast.extra_data[extra_base + 1 + param_count];
    const ret_end = self.ast.extra_data[extra_base + 1 + param_count + 1];
    return buildTypeString(self, ret_start, ret_end);
}

// php gives __toString an implicit string return type
fn extractMethodReturnType(self: *Compiler, member: Ast.Node, param_count: u32) Error![]const u8 {
    const declared = try extractReturnType(self, member.data.lhs, param_count);
    if (declared.len == 0 and std.ascii.eqlIgnoreCase(self.ast.tokenSlice(member.main_token), "__toString")) return "string";
    return declared;
}

// classify a declared return type for fastLoop's return_val fast/slow split
fn returnTypeKind(t: []const u8) @import("bytecode.zig").ReturnTypeKind {
    if (t.len == 0) return .none;
    if (std.mem.eql(u8, t, "int")) return .int;
    if (std.mem.eql(u8, t, "float")) return .float;
    if (std.mem.eql(u8, t, "bool")) return .bool;
    if (std.mem.eql(u8, t, "string")) return .string;
    // nullable / union / intersection / class / void etc. - always bail
    return .other;
}

pub fn compileFunction(self: *Compiler, node: Ast.Node) Error!void {
    const name_tok = node.main_token;
    const raw_name = self.ast.tokenSlice(name_tok);
    const name = if (std.mem.startsWith(u8, raw_name, "__closure_")) raw_name else self.declaredName(raw_name);
    const param_nodes = self.ast.extraSlice(node.data.lhs);
    const outer_named_signature = self.named_signature;
    self.named_signature = !std.mem.startsWith(u8, raw_name, "__closure_");
    defer self.named_signature = outer_named_signature;
    if (!std.mem.startsWith(u8, raw_name, "__closure_")) {
        try checkImportCollision(self, name_tok, .function, name);
        try checkParams(self, name, name_tok, param_nodes, try extractReturnType(self, node.data.lhs, @intCast(param_nodes.len)), (node.data.rhs & (1 << 30)) != 0);
    }

    var handed_over = false;
    const param_names = try self.allocator.alloc([]const u8, param_nodes.len);
    errdefer if (!handed_over) self.allocator.free(param_names);
    const ref_flags = try self.allocator.alloc(bool, param_nodes.len);
    errdefer if (!handed_over) self.allocator.free(ref_flags);
    var defaults = std.ArrayListUnmanaged(Value).empty;
    defer defaults.deinit(self.allocator);
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
            try defaults.append(self.allocator, try paramDefaultValue(self, pnode));
        } else {
            try defaults.append(self.allocator, .null);
        }
    }
    const required = requiredParamCount(self.ast, param_nodes);

    const defaults_owned = try self.allocator.alloc(Value, defaults.items.len);
    @memcpy(defaults_owned, defaults.items);
    errdefer if (!handed_over) compiler.freeDefaults(self.allocator, defaults_owned);

    const gen = (node.data.rhs & (1 << 31)) != 0;
    const returns_ref = (node.data.rhs & (1 << 30)) != 0;

    var sub = Compiler{
        .ast = self.ast,
        .diagnostic = self.diagnostic,
        .declared_return = try extractReturnType(self, node.data.lhs, @intCast(param_nodes.len)),
        .chunk = .{},
        .functions = .empty,
        .string_allocs = .empty,
        .allocator = self.allocator,
        .scope_depth = self.scope_depth + 1,
        .loop_start = null,
        .break_jumps = .empty,
        .continue_jumps = .empty,
        .is_generator = gen,
        .returns_ref = returns_ref,
        .closure_count = self.closure_count,
        .cond_fn_count = self.cond_fn_count,
        .hoistable = false,
        .file_path = self.file_path,
        .file_dir = self.file_dir,
        .namespace = self.namespace,
        .use_aliases = self.use_aliases,
        .use_fn_aliases = self.use_fn_aliases,
        .use_const_aliases = self.use_const_aliases,
        .current_function = name,
    };
    defer sub.deinitScratch();
    errdefer sub.discardOutput();

    for (param_nodes, 0..) |_, i| {
        if (i < ref_flags.len and ref_flags[i]) continue;
        _ = sub.getOrCreateSlot(param_names[i]);
    }

    // a generator's body only runs once it is iterated, so its call can't be
    // checked from inside it
    const call_attrs = try callAttributes(self, node.main_token, try extractReturnType(self, node.data.lhs, @intCast(param_nodes.len)), "function");
    if (call_attrs.deprecated != null and !gen) try sub.emitOp(.check_deprecated);
    if (call_attrs.no_discard != null and !gen) try sub.emitOp(.check_nodiscard);
    const body_idx = node.data.rhs & 0x3FFFFFFF;
    try sub.compileNode(body_idx);
    try sub.patchGotos();
    try sub.emitOp(.op_null);
    try sub.emitOp(if (gen) .generator_return else .return_val);

    self.closure_count = sub.closure_count;
    self.cond_fn_count = sub.cond_fn_count;
    try self.functions.ensureUnusedCapacity(self.allocator, 1);
    const slot_names = try sub.buildSlotNames();
    const local_count = sub.next_slot;

    const is_closure = std.mem.startsWith(u8, name, "__closure_");
    const lo = !is_closure and !gen and !is_variadic and !hasRefParams(ref_flags) and !needsVarSync(&sub.chunk);

    // closures stay eagerly registered (instantiation opcodes look them up by
    // internal name); a non-hoistable named function binds at runtime via
    // declare_fn at the declaration site, matching PHP
    var cond_id: u16 = 0;
    if (!self.hoistable and !is_closure) {
        self.cond_fn_count += 1;
        cond_id = self.cond_fn_count;
    }

    self.functions.appendAssumeCapacity(.{
        .name = name,
        .cond_id = cond_id,
        .arity = @intCast(param_nodes.len),
        .required_params = required,
        .is_variadic = is_variadic,
        .is_generator = gen,
        .returns_ref = returns_ref,
        .locals_only = lo,
        .params = param_names[0..param_nodes.len],
        .defaults = defaults_owned,
        .ref_params = ref_flags,
        .chunk = sub.takeChunk(),
        .static_vars = try sub.takeStaticVars(),
        .local_count = local_count,
        .slot_names = slot_names,
        .file_path = self.file_path,
        .start_line = lineForToken(self, name_tok),
        .end_line = endLineForBlockStartingAt(self, node.main_token),
        .doc_comment = docCommentForToken(self, node.main_token),
    });
    handed_over = true;

    const param_types = try extractParamTypes(self, param_nodes);
    const return_type = try extractReturnType(self, node.data.lhs, @intCast(param_nodes.len));
    if (param_types.len > 0 or return_type.len > 0) {
        try self.type_hints.append(self.allocator, .{ .name = name, .param_types = param_types, .return_type = return_type });
    }
    if (self.functions.items.len > 0) {
        self.functions.items[self.functions.items.len - 1].has_param_types = param_types.len > 0;
        if (return_type.len > 0) self.functions.items[self.functions.items.len - 1].return_type_kind = returnTypeKind(return_type);
    }
    self.functions.items[self.functions.items.len - 1].no_discard = call_attrs.no_discard;
    self.functions.items[self.functions.items.len - 1].deprecated = call_attrs.deprecated;

    // function-level attributes
    if (!std.mem.startsWith(u8, name, "__closure_")) {
        const func_attrs = try extractAttributes(self, node.main_token, AttrTarget.function);
        if (func_attrs.len > 0) {
            const attr_defs = try self.allocator.alloc(AttributeDef, func_attrs.len);
            for (func_attrs, 0..) |pa, i| {
                attr_defs[i] = .{ .name = pa.name, .args = pa.args, .arg_names = pa.arg_names };
            }
            try self.function_attrs.append(self.allocator, .{ .name = name, .attrs = attr_defs });
            self.allocator.free(func_attrs);
        }
        try appendParamAttributes(self, name, param_nodes);
    }

    try self.adopt(&sub);

    if (cond_id != 0) {
        try self.emitOp(.declare_fn);
        try self.emitU16(cond_id);
    }
}

pub fn compileClosure(self: *Compiler, node: Ast.Node) Error!void {
    const id = compiler.allocClosureId();
    self.closure_count += 1;

    var name_buf: [32]u8 = undefined;
    const name = std.fmt.bufPrint(&name_buf, "__closure_{d}", .{id}) catch "__closure";
    const owned_name = try self.allocator.dupe(u8, name);
    try self.string_allocs.append(self.allocator, owned_name);

    const param_nodes = self.ast.extraSlice(node.data.lhs);
    var handed_over = false;
    const param_names = try self.allocator.alloc([]const u8, param_nodes.len);
    errdefer if (!handed_over) self.allocator.free(param_names);
    var ref_flags_buf: [16]bool = @splat(false);
    var has_any_ref = false;
    var defaults = std.ArrayListUnmanaged(Value).empty;
    defer defaults.deinit(self.allocator);
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
            try defaults.append(self.allocator, try paramDefaultValue(self, pnode));
        } else {
            try defaults.append(self.allocator, .null);
        }
    }
    const required = requiredParamCount(self.ast, param_nodes);

    const defaults_owned = if (required < param_nodes.len) blk: {
        const d = try self.allocator.alloc(Value, defaults.items.len);
        @memcpy(d, defaults.items);
        break :blk d;
    } else &[_]Value{};
    errdefer if (!handed_over) compiler.freeDefaults(self.allocator, defaults_owned);

    // rhs = extra -> {body (bit 31 = generator, bit 30 = static), use_count, use_vars...}
    // use_count 0xFFFFFFFF = arrow fn (implicit capture)
    const raw_body = self.ast.extra_data[node.data.rhs];
    const body_node = raw_body & 0x1FFFFFFF;
    const closure_returns_ref = (raw_body & (1 << 29)) != 0;
    const gen = (raw_body & (1 << 31)) != 0;
    const is_static_closure = (raw_body & (1 << 30)) != 0;
    const raw_use_count = self.ast.extra_data[node.data.rhs + 1];
    const is_arrow = raw_use_count == 0xFFFFFFFF;
    const use_count: u32 = if (is_arrow) 0 else raw_use_count;
    const use_vars = self.ast.extra_data[node.data.rhs + 2 .. node.data.rhs + 2 + use_count];
    const display_name = try closureDisplayName(self, lineForToken(self, node.main_token));
    // a closure's scope is only known once it is bound
    const outer_closure_signature = self.closure_signature;
    self.closure_signature = true;
    defer self.closure_signature = outer_closure_signature;
    try checkParams(self, display_name, node.main_token, param_nodes, try extractReturnType(self, node.data.lhs, @intCast(param_nodes.len)), closure_returns_ref);

    var sub = Compiler{
        .ast = self.ast,
        .diagnostic = self.diagnostic,
        .declared_return = try extractReturnType(self, node.data.lhs, @intCast(param_nodes.len)),
        .chunk = .{},
        .functions = .empty,
        .string_allocs = .empty,
        .allocator = self.allocator,
        .scope_depth = self.scope_depth + 1,
        .loop_start = null,
        .break_jumps = .empty,
        .continue_jumps = .empty,
        .is_generator = gen,
        .returns_ref = closure_returns_ref,
        .closure_count = self.closure_count,
        .cond_fn_count = self.cond_fn_count,
        .hoistable = false,
        .file_path = self.file_path,
        .file_dir = self.file_dir,
        .namespace = self.namespace,
        .use_aliases = self.use_aliases,
        .use_fn_aliases = self.use_fn_aliases,
        .use_const_aliases = self.use_const_aliases,
        .current_class = self.current_class,
        .current_parent = self.current_parent,
        .current_function = display_name,
        .in_trait = self.in_trait,
    };
    defer sub.deinitScratch();
    errdefer sub.discardOutput();

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

    // arrow functions implicitly capture by value - but only the variables
    // the body actually uses. point the sub-compiler at this scope so a
    // parent variable is captured lazily on first reference (see
    // arrowCaptureSlot); capturing the whole scope would extend the lifetime
    // of unused objects and fire their __destruct late
    if (is_arrow) sub.arrow_parent = self;

    const call_attrs = try callAttributes(self, node.main_token, try extractReturnType(self, node.data.lhs, @intCast(param_nodes.len)), "function");
    if (call_attrs.deprecated != null and !gen) try sub.emitOp(.check_deprecated);
    if (call_attrs.no_discard != null and !gen) try sub.emitOp(.check_nodiscard);
    try sub.compileNode(body_node);
    try sub.patchGotos();
    try sub.emitOp(.op_null);
    try sub.emitOp(if (gen) .generator_return else .return_val);

    self.closure_count = sub.closure_count;
    self.cond_fn_count = sub.cond_fn_count;

    const ref_params = if (has_any_ref) blk: {
        const rp = try self.allocator.alloc(bool, param_nodes.len);
        for (0..param_nodes.len) |i| rp[i] = if (i < 16) ref_flags_buf[i] else false;
        break :blk rp;
    } else &[_]bool{};
    errdefer if (!handed_over and ref_params.len > 0) self.allocator.free(ref_params);

    // check for ref captures
    var has_ref_capture = false;
    for (use_vars) |use_var_node| {
        if (self.ast.nodes[use_var_node].data.rhs != 0) {
            has_ref_capture = true;
            break;
        }
    }

    try self.functions.ensureUnusedCapacity(self.allocator, 1);
    const slot_names = try sub.buildSlotNames();
    const local_count = sub.next_slot;

    // a closure's captures live in its frame's variables, so one that captures
    // them again for a closure of its own keeps them there
    const closure_lo = !gen and !is_variadic and !has_any_ref and !has_ref_capture and !needsVarSync(&sub.chunk) and !hasOp(&sub.chunk, .closure_bind);
    // an arrow function has no braces of its own; it ends with its expression
    const arrow_end = if (is_arrow) endLineForChunk(self, &sub.chunk) else 0;

    const func = ObjFunction{
        .name = owned_name,
        .arity = @intCast(param_nodes.len),
        .required_params = required,
        .params = param_names[0..param_nodes.len],
        .defaults = defaults_owned,
        .chunk = sub.takeChunk(),
        .static_vars = try sub.takeStaticVars(),
        .is_arrow = is_arrow,
        .is_generator = gen,
        .returns_ref = closure_returns_ref,
        .is_variadic = is_variadic,
        .is_static = is_static_closure,
        .locals_only = closure_lo,
        .ref_params = ref_params,
        .local_count = local_count,
        .slot_names = slot_names,
        .file_path = self.file_path,
        .start_line = lineForToken(self, node.main_token),
        .end_line = if (is_arrow) arrow_end else endLineForBlockStartingAt(self, node.main_token),
        .doc_comment = docCommentForToken(self, node.main_token),
        .display_name = display_name,
        .no_discard = call_attrs.no_discard,
        .deprecated = call_attrs.deprecated,
    };

    self.functions.appendAssumeCapacity(func);
    handed_over = true;

    const param_types = try extractParamTypes(self, param_nodes);
    const return_type = try extractReturnType(self, node.data.lhs, @intCast(param_nodes.len));
    if (param_types.len > 0 or return_type.len > 0) {
        try self.type_hints.append(self.allocator, .{ .name = owned_name, .param_types = param_types, .return_type = return_type });
        self.functions.items[self.functions.items.len - 1].has_param_types = param_types.len > 0;
    }

    // closure-level attributes
    const closure_attrs = try extractAttributes(self, node.main_token, AttrTarget.function);
    if (closure_attrs.len > 0) {
        const attr_defs = try self.allocator.alloc(AttributeDef, closure_attrs.len);
        for (closure_attrs, 0..) |pa, i| {
            attr_defs[i] = .{ .name = pa.name, .args = pa.args, .arg_names = pa.arg_names };
        }
        try self.function_attrs.append(self.allocator, .{ .name = owned_name, .attrs = attr_defs });
        self.allocator.free(closure_attrs);
    }
    try appendParamAttributes(self, owned_name, param_nodes);

    try self.adopt(&sub);

    const idx = try self.addConstant(.{ .string = Value.String.borrowed(owned_name) });
    try self.emitConstant(idx);

    // Even a capture-free static closure has lexical/late-static scope.
    // A harmless internal capture instantiates it without binding $this.
    if (is_static_closure and self.current_class.len > 0) {
        const scope_idx = try self.addConstant(.{ .string = Value.String.borrowed("$__closure_context") });
        try self.emitOp(.closure_bind);
        try self.emitU16(scope_idx);
    }

    for (use_vars) |use_var_node| {
        const use_node = self.ast.nodes[use_var_node];
        const var_name = self.ast.tokenSlice(use_node.main_token);
        // inside an arrow function, a use of an outer variable captures it
        // into the arrow, as a read in its body would
        if (self.local_slots.get(var_name) == null) _ = self.arrowCaptureSlot(var_name);
        const var_idx = try self.addConstant(.{ .string = Value.String.borrowed(var_name) });
        const is_ref = use_node.data.rhs != 0;
        try self.emitOp(if (is_ref) .closure_bind_ref else .closure_bind);
        try self.emitU16(var_idx);
    }

    // arrow functions: bind the outer-scope variables the body captured. a
    // sub slot is a capture only when the name also exists in this (the
    // enclosing) scope - the arrow's own params and locals are not captures
    if (is_arrow) {
        for (slot_names) |sn| {
            var is_param = false;
            for (param_names[0..param_nodes.len]) |pn| {
                if (sn.len == pn.len and std.mem.eql(u8, sn, pn)) {
                    is_param = true;
                    break;
                }
            }
            if (is_param) continue;
            if (std.mem.eql(u8, sn, "$this")) continue;
            if (self.local_slots.get(sn) == null) continue;
            const sn_idx = try self.addConstant(.{ .string = Value.String.borrowed(sn) });
            try self.emitOp(.closure_bind);
            try self.emitU16(sn_idx);
        }
    }

    // Static closures never bind $this. Dynamic closures still emit the bind:
    // at runtime it also records class scope when no object is present.
    if (!is_static_closure) {
        const this_idx = try self.addConstant(.{ .string = Value.String.borrowed("$this") });
        try self.emitOp(.closure_bind);
        try self.emitU16(this_idx);
    }
}

// a class/interface declaration default is "hoist-safe" only when it folds to
// a compile-time literal with no external name reference. anything that reads a
// constant, another class's const, a variable, self::CONST, or a call is NOT
// safe: PHP evaluates property defaults at instantiation, so relocating a class
// ahead of a `const`/`define` it depends on would evaluate the default too
// early. literals (and literal arrays / unary / binary of literals) are
// order-independent and safe to relocate
fn defaultExprIsLiteral(ast: *const Ast, idx: u32) bool {
    if (idx == 0) return true;
    const node = ast.nodes[idx];
    return switch (node.tag) {
        .integer_literal, .float_literal, .string_literal, .true_literal, .false_literal, .null_literal => true,
        .prefix_op => defaultExprIsLiteral(ast, node.data.lhs),
        .binary_op => defaultExprIsLiteral(ast, node.data.lhs) and defaultExprIsLiteral(ast, node.data.rhs),
        .array_literal => {
            for (ast.extraSlice(node.data.lhs)) |el_idx| {
                const el = ast.nodes[el_idx];
                if (el.tag != .array_element) return false;
                if (!defaultExprIsLiteral(ast, el.data.lhs)) return false;
                if (el.data.rhs != 0 and !defaultExprIsLiteral(ast, el.data.rhs)) return false;
            }
            return true;
        },
        // self::CONST / parent::CONST in a default are order-independent: the
        // compiler bakes them to the concrete class name (current_class /
        // current_parent), the class registers its own constants before its
        // instance-property defaults run, and a hoisted class's parent was
        // emitted earlier in the prelude. static:: (late static binding) and
        // explicit ClassName::CONST stay excluded - their target may not be
        // available at the relocated position
        .static_prop_access => {
            const member = ast.tokenSlice(node.main_token);
            if (member.len == 0 or member[0] == '$' or std.mem.eql(u8, member, "class")) return false;
            const class_node = ast.nodes[node.data.lhs];
            if (class_node.tag != .identifier) return false;
            const cls = ast.tokenSlice(class_node.main_token);
            return std.ascii.eqlIgnoreCase(cls, "self") or std.ascii.eqlIgnoreCase(cls, "parent");
        },
        else => false,
    };
}

// PHP early-binds a top-level class only if it is self-sufficient at its
// declaration point: a parent (if any) already bound, no interfaces, no traits.
// we additionally require literal defaults (see defaultExprIsLiteral) so the
// relocation can never reorder a default ahead of a constant it reads
fn classDeclEarlyBindable(self: *Compiler, node: Ast.Node) bool {
    if (declHasAttributes(self, node)) return false;
    const rhs_base = node.data.rhs;
    if (self.ast.extra_data[rhs_base + 2] != 0) return false; // implements
    const parent_node = self.ast.extra_data[rhs_base + 1];
    if (parent_node != 0) {
        const pnode = self.ast.nodes[parent_node];
        const parent_name = resolveNodeClassName(self, pnode) catch return false;
        if (!self.hoisted_names.contains(parent_name) and
            !@import("../stdlib/builtin_classes.zig").contains(parent_name)) return false;
    }
    // php early-binds a subclass only when its inheritance checks can run
    // with the classes known while compiling; one whose method types name
    // anything else is declared where it stands
    if (parent_node != 0 and !methodTypesKnown(self, node, &self.hoisted_names)) return false;
    for (self.ast.extraSlice(node.data.lhs)) |m_idx| {
        const m = self.ast.nodes[m_idx];
        switch (m.tag) {
            .trait_use => return false,
            .class_property, .static_class_property => {
                if (m.data.lhs != 0 and !defaultExprIsLiteral(self.ast, m.data.lhs)) return false;
            },
            .const_decl => {
                if (!defaultExprIsLiteral(self.ast, m.data.lhs)) return false;
            },
            .class_property_hooks => {
                const default_idx = self.ast.extra_data[m.data.lhs];
                if (default_idx != 0 and !defaultExprIsLiteral(self.ast, default_idx)) return false;
            },
            else => {},
        }
    }
    return true;
}

// whether every class a method of this class names in its parameter and
// return types is built in or already early-bound in this file
fn methodTypesKnown(self: *Compiler, node: Ast.Node, known: *const std.StringHashMapUnmanaged(void)) bool {
    const own = self.declaredName(self.ast.tokenSlice(node.main_token));
    for (self.ast.extraSlice(node.data.lhs)) |m_idx| {
        const m = self.ast.nodes[m_idx];
        // a property's type is checked against the one it redeclares too
        if (m.tag == .class_property or m.tag == .static_class_property or m.tag == .class_property_hooks) {
            const type_extra = m.data.rhs >> 16;
            if (type_extra != 0 and !typeNamesKnown(self, own, self.ast.extra_data[type_extra - 1], self.ast.extra_data[type_extra], known)) return false;
            continue;
        }
        if (m.tag != .class_method and m.tag != .static_class_method and m.tag != .interface_method) continue;
        const params = self.ast.extraSlice(m.data.lhs);
        for (params) |p| {
            const type_extra = self.ast.nodes[p].data.rhs >> 8;
            if (type_extra == 0) continue;
            if (!typeNamesKnown(self, own, self.ast.extra_data[type_extra - 1], self.ast.extra_data[type_extra], known)) return false;
        }
        const ret = m.data.lhs + 1 + @as(u32, @intCast(params.len));
        if (!typeNamesKnown(self, own, self.ast.extra_data[ret], self.ast.extra_data[ret + 1], known)) return false;
    }
    return true;
}

fn typeNamesKnown(self: *Compiler, own: []const u8, start_tok: u32, end_tok: u32, known: *const std.StringHashMapUnmanaged(void)) bool {
    var tok = start_tok;
    while (tok < end_tok) {
        const lexeme = self.ast.tokens[tok].lexeme(self.ast.source);
        if (lexeme.len == 1 and std.mem.indexOfScalar(u8, "|&()?", lexeme[0]) != null) {
            tok += 1;
            continue;
        }
        const first = self.ast.tokens[tok].start;
        while (tok < end_tok) : (tok += 1) {
            const l = self.ast.tokens[tok].lexeme(self.ast.source);
            if (l.len == 1 and std.mem.indexOfScalar(u8, "|&()?", l[0]) != null) break;
        }
        const last = self.ast.tokens[tok - 1];
        const written = self.ast.source[first .. last.start + last.lexeme(self.ast.source).len];
        var lower_buf: [16]u8 = undefined;
        if (written.len <= lower_buf.len) {
            const lower = std.ascii.lowerString(&lower_buf, written);
            const builtin = std.StaticStringMap(void).initComptime(.{
                .{"null"},   .{"false"},  .{"true"},  .{"bool"},     .{"int"},  .{"float"},  .{"string"}, .{"array"},
                .{"object"}, .{"callable"}, .{"void"}, .{"never"}, .{"static"}, .{"mixed"}, .{"iterable"}, .{"self"},
                .{"parent"},
            });
            if (builtin.has(lower)) continue;
        }
        const name = if (written[0] == '\\') written[1..] else self.resolveClassName(written);
        if (std.ascii.eqlIgnoreCase(name, own)) continue;
        if (known.contains(name) or @import("../stdlib/builtin_classes.zig").contains(name)) continue;
        return false;
    }
    return true;
}

// attribute arguments are another decl-time construct that can reference
// external names (another class's constant, an enum case), so relocating a
// class with attributes can reorder it ahead of what its attributes read.
// conservatively refuse to hoist any declaration carrying attributes anywhere
fn declHasAttributes(self: *Compiler, node: Ast.Node) bool {
    if (self.ast.attr_ranges.len == 0) return false;
    if (findAttrRangeForToken(self.ast.attr_ranges, self.ast.tokens, node.main_token) != null) return true;
    for (self.ast.extraSlice(node.data.lhs)) |m_idx| {
        const m = self.ast.nodes[m_idx];
        if (findAttrRangeForToken(self.ast.attr_ranges, self.ast.tokens, m.main_token) != null) return true;
        if (m.tag == .class_method or m.tag == .static_class_method) {
            for (self.ast.extraSlice(m.data.lhs)) |pn| {
                if (findAttrRangeForToken(self.ast.attr_ranges, self.ast.tokens, self.ast.nodes[pn].main_token) != null) return true;
            }
        }
    }
    return false;
}

fn interfaceDeclEarlyBindable(self: *Compiler, node: Ast.Node) bool {
    if (declHasAttributes(self, node)) return false;
    if (node.data.rhs != 0) {
        const parent_count = self.ast.extra_data[node.data.rhs];
        for (0..parent_count) |i| {
            const pnode = self.ast.nodes[self.ast.extra_data[node.data.rhs + 1 + i]];
            const pname = resolveNodeClassName(self, pnode) catch return false;
            if (!self.hoisted_names.contains(pname)) return false;
        }
    }
    for (self.ast.extraSlice(node.data.lhs)) |m_idx| {
        const m = self.ast.nodes[m_idx];
        if (m.tag == .const_decl and !defaultExprIsLiteral(self.ast, m.data.lhs)) return false;
    }
    return true;
}

// emit early-bindable top-level class/interface declarations into a prelude.
// namespace/use statements are replayed as compiler state (they emit nothing)
// so names resolve correctly; bare blocks are descended like PHP's binding pass.
// hoisted_names accumulates in source order so a class extending an
// already-hoisted class is itself recognized as bindable
fn traitDefaultsFold(self: *Compiler, node: Ast.Node) bool {
    for (self.ast.extraSlice(node.data.lhs)) |m| {
        const member = self.ast.nodes[m];
        const default: u32 = switch (member.tag) {
            .class_property, .static_class_property, .const_decl => member.data.lhs,
            .class_property_hooks => self.ast.extra_data[member.data.lhs],
            else => 0,
        };
        if (default != 0 and !foldsAtCompileTime(self.ast, default)) return false;
    }
    return true;
}

fn usesTraits(self: *Compiler, node: Ast.Node) bool {
    for (self.ast.extraSlice(node.data.lhs)) |m| {
        if (self.ast.nodes[m].tag == .trait_use) return true;
    }
    return false;
}

pub fn hoistEarlyClasses(self: *Compiler, stmts: []const u32) Error!void {
    for (stmts) |idx| {
        const node = self.ast.nodes[idx];
        switch (node.tag) {
            .namespace_decl => try compiler_stmt.compileNamespace(self, node),
            .use_stmt => try compiler_stmt.compileUse(self, node),
            .use_fn_stmt => try compiler_stmt.compileUseFn(self, node),
            .use_const_stmt => try compiler_stmt.compileUseConst(self, node),
            .block => try hoistEarlyClasses(self, self.ast.extraSlice(node.data.lhs)),
            .class_decl => if (classDeclEarlyBindable(self, node)) {
                self.current_source_offset = self.ast.tokens[node.main_token].start;
                const name = self.declaredName(self.ast.tokenSlice(node.main_token));
                try compileClassDecl(self, node);
                try self.hoisted_nodes.put(self.allocator, idx, {});
                try self.hoisted_names.put(self.allocator, name, {});
            },
            // php binds a trait that uses no other trait at compile time.
            // zphp evaluates a trait's defaults where it is declared, so only
            // a trait whose defaults fold moves
            .trait_decl => if (!usesTraits(self, node) and traitDefaultsFold(self, node)) {
                self.current_source_offset = self.ast.tokens[node.main_token].start;
                const name = self.declaredName(self.ast.tokenSlice(node.main_token));
                try compileTraitDecl(self, node);
                try self.hoisted_nodes.put(self.allocator, idx, {});
                try self.hoisted_names.put(self.allocator, name, {});
            },
            .interface_decl => if (interfaceDeclEarlyBindable(self, node)) {
                self.current_source_offset = self.ast.tokens[node.main_token].start;
                const name = self.declaredName(self.ast.tokenSlice(node.main_token));
                try compileInterfaceDecl(self, node);
                try self.hoisted_nodes.put(self.allocator, idx, {});
                try self.hoisted_names.put(self.allocator, name, {});
            },
            else => {},
        }
    }
}

// php numbers, in the order it compiles them, each anonymous class and each
// named class it cannot bind while compiling the file (CG(rtd_key_counter)),
// and an anonymous class's name ends with its number. maps each anonymous
// class's `new` token to its number. the numbers come from the whole file,
// not from what zphp compiles first, so a class zphp hoists keeps php's order
pub fn assignRtdKeys(self: *Compiler, stmts: []const u32, keys: *std.AutoHashMapUnmanaged(u32, u32)) Error!void {
    const a = self.allocator;
    var bound_names: std.StringHashMapUnmanaged(void) = .{};
    defer bound_names.deinit(a);
    var bound: std.AutoHashMapUnmanaged(u32, void) = .{};
    defer bound.deinit(a);
    try collectCompileTimeBound(self, stmts, &bound_names, &bound);

    const none = std.math.maxInt(u32);
    const Event = struct { pos: u32, anon: u32 };
    var events: std.ArrayListUnmanaged(Event) = .empty;
    defer events.deinit(a);
    var seen: std.AutoHashMapUnmanaged(u32, void) = .{};
    defer seen.deinit(a);
    for (self.ast.nodes) |n| {
        // an anonymous class is named before its body compiles, a named class
        // gets its key after
        const event: Event = switch (n.tag) {
            .anonymous_class => .{ .pos = n.main_token, .anon = n.main_token },
            .class_decl, .interface_decl, .trait_decl, .enum_decl => if (bound.contains(n.main_token))
                continue
            else
                .{ .pos = blockEndToken(self, n.main_token), .anon = none },
            else => continue,
        };
        if ((try seen.getOrPut(a, n.main_token)).found_existing) continue;
        try events.append(a, event);
    }
    if (events.items.len == 0) return;
    std.sort.pdq(Event, events.items, {}, struct {
        fn lessThan(_: void, x: Event, y: Event) bool {
            return x.pos < y.pos;
        }
    }.lessThan);
    const base = compiler.reserveRtdKeys(@intCast(events.items.len));
    for (events.items, 0..) |e, i| {
        if (e.anon != none) try keys.put(a, e.anon, base +% @as(u32, @intCast(i)));
    }
}

// the top-level declarations php binds while compiling (zend_compile_class_decl):
// a class with no interfaces (__toString adds Stringable, an enum always has
// some), no traits, and a parent, if any, already bound; an interface
// extending none; a trait using none
fn collectCompileTimeBound(self: *Compiler, stmts: []const u32, names: *std.StringHashMapUnmanaged(void), tokens: *std.AutoHashMapUnmanaged(u32, void)) Error!void {
    for (stmts) |idx| {
        const node = self.ast.nodes[idx];
        const binds = switch (node.tag) {
            .namespace_decl => {
                try compiler_stmt.compileNamespace(self, node);
                continue;
            },
            .use_stmt => {
                try compiler_stmt.compileUse(self, node);
                continue;
            },
            .block => {
                try collectCompileTimeBound(self, self.ast.extraSlice(node.data.lhs), names, tokens);
                continue;
            },
            .class_decl => classBindsAtCompileTime(self, node, names),
            .interface_decl => node.data.rhs == 0 or self.ast.extra_data[node.data.rhs] == 0,
            .trait_decl => !usesTraits(self, node),
            else => continue,
        };
        if (!binds) continue;
        const name = self.declaredName(self.ast.tokenSlice(node.main_token));
        // a second declaration of a name is declared at runtime
        if ((try names.getOrPut(self.allocator, name)).found_existing) continue;
        try tokens.put(self.allocator, node.main_token, {});
    }
}

fn classBindsAtCompileTime(self: *Compiler, node: Ast.Node, bound: *const std.StringHashMapUnmanaged(void)) bool {
    const rhs_base = node.data.rhs;
    if (self.ast.extra_data[rhs_base + 2] != 0) return false;
    for (self.ast.extraSlice(node.data.lhs)) |m_idx| {
        const m = self.ast.nodes[m_idx];
        if (m.tag == .trait_use) return false;
        if (m.tag == .class_method and std.ascii.eqlIgnoreCase(self.ast.tokenSlice(m.main_token), "__toString")) return false;
    }
    const parent_node = self.ast.extra_data[rhs_base + 1];
    if (parent_node == 0) return true;
    const parent_name = resolveNodeClassName(self, self.ast.nodes[parent_node]) catch return false;
    if (!bound.contains(parent_name) and !@import("../stdlib/builtin_classes.zig").contains(parent_name)) return false;
    // zend_try_early_bind gives up on inheritance checks naming unknown classes
    return methodTypesKnown(self, node, bound);
}

// the token closing the body that starts after `start_tok`
fn blockEndToken(self: *Compiler, start_tok: u32) u32 {
    var depth: i32 = 0;
    var i: u32 = start_tok;
    while (i < self.ast.tokens.len) : (i += 1) {
        switch (self.ast.tokens[i].tag) {
            .l_brace => depth += 1,
            .r_brace => {
                depth -= 1;
                if (depth == 0) return i;
            },
            else => {},
        }
    }
    return i;
}

// php refuses to declare a class or function under a name a `use` statement
// already imported as something else
fn checkImportCollision(self: *Compiler, token: u32, comptime kind: enum { class, function }, full_name: []const u8) Error!void {
    const written = self.ast.tokenSlice(token);
    const short = if (std.mem.lastIndexOfScalar(u8, written, '\\')) |i| written[i + 1 ..] else written;
    var it = (if (kind == .class) self.use_aliases else self.use_fn_aliases).iterator();
    while (it.next()) |entry| {
        if (!std.ascii.eqlIgnoreCase(entry.key_ptr.*, short) or std.ascii.eqlIgnoreCase(entry.value_ptr.*, full_name)) continue;
        if (kind == .class) return self.failFmt(token, "Cannot redeclare class {s} (previously declared as local import)", .{full_name});
        return self.failFmt(token, "Cannot redeclare function {s}() (previously declared as local import)", .{full_name});
    }
}

// php's compile-time refusal of a method or property declared twice in one
// class
fn checkDuplicateMembers(self: *Compiler, class_name: []const u8, members: []const u32) Error!void {
    var arena_state = std.heap.ArenaAllocator.init(self.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var methods: std.StringHashMapUnmanaged(void) = .{};
    var props: std.StringHashMapUnmanaged(void) = .{};
    const class = class_names.display(class_name);
    for (members) |m_idx| {
        const m = self.ast.nodes[m_idx];
        switch (m.tag) {
            .class_method, .static_class_method, .interface_method => {
                const name = self.ast.tokenSlice(m.main_token);
                const gop = try methods.getOrPut(arena, try std.ascii.allocLowerString(arena, name));
                if (gop.found_existing) return self.failFmt(m.main_token, "Cannot redeclare {s}::{s}()", .{ class, name });
                if (!std.ascii.eqlIgnoreCase(name, "__construct")) continue;
                for (self.ast.extraSlice(m.data.lhs)) |p| {
                    const pn = self.ast.nodes[p];
                    const promoted = ((pn.data.rhs >> 2) & 3) != 0 or (pn.data.rhs & 16) != 0 or ((pn.data.rhs >> 5) & 3) != 0;
                    if (!promoted) continue;
                    const pname = paramName(self, p);
                    if ((try props.getOrPut(arena, pname)).found_existing) return self.failFmt(pn.main_token, "Cannot redeclare {s}::${s}", .{ class, pname });
                }
            },
            .class_property, .static_class_property, .class_property_hooks => {
                const raw = self.ast.tokenSlice(m.main_token);
                const name = if (raw.len > 0 and raw[0] == '$') raw[1..] else raw;
                if ((try props.getOrPut(arena, name)).found_existing) return self.failFmt(m.main_token, "Cannot redeclare {s}::${s}", .{ class, name });
            },
            else => {},
        }
    }
}

// a class declaration, named or anonymous, as compileClass reads it
const ClassShape = struct {
    name: []const u8,
    members: []const u32,
    modifiers: u8,
    parent_node: u32,
    impl_nodes: []const u32,
    // the token its line, doc comment and end line are found from
    at: u32,
    // the token its attributes precede
    attributes_at: u32,
};

pub fn compileClassDecl(self: *Compiler, node: Ast.Node) Error!void {
    const unqualified = self.ast.tokenSlice(node.main_token);
    if (isReservedClassName(unqualified)) return self.failFmt(node.main_token, "Cannot use \"{s}\" as a class name as it is reserved", .{unqualified});
    const class_name = self.declaredName(self.ast.tokenSlice(node.main_token));
    try checkImportCollision(self, node.main_token, .class, class_name);
    // rhs: {class_modifiers, parent_node, implements_count, impl_nodes...}
    const rhs_base = node.data.rhs;
    const impl_count = self.ast.extra_data[rhs_base + 2];
    try compileClass(self, .{
        .name = class_name,
        .members = self.ast.extraSlice(node.data.lhs),
        .modifiers = @intCast(self.ast.extra_data[rhs_base] & 0xff),
        .parent_node = self.ast.extra_data[rhs_base + 1],
        .impl_nodes = self.ast.extra_data[rhs_base + 3 .. rhs_base + 3 + impl_count],
        .at = node.main_token,
        .attributes_at = node.main_token,
    });
}

fn compileClass(self: *Compiler, shape: ClassShape) Error!void {
    const class_name = shape.name;
    const members = shape.members;
    try checkDuplicateMembers(self, class_name, members);
    try checkConstDecls(self, class_name, members);
    try checkPropDecls(self, class_name, members);

    const prev_class = self.current_class;
    self.current_class = class_name;
    defer self.current_class = prev_class;

    const class_modifiers = shape.modifiers;
    const parent_node = shape.parent_node;
    const impl_count = shape.impl_nodes.len;
    const impl_names = try self.allocator.alloc([]const u8, impl_count);
    defer self.allocator.free(impl_names);
    for (shape.impl_nodes, 0..) |impl_idx, i| {
        const impl_node = self.ast.nodes[impl_idx];
        try rejectReservedParent(self, impl_node, "interface");
        impl_names[i] = try resolveNodeClassName(self, impl_node);
    }

    const prev_parent = self.current_parent;
    self.current_parent = if (parent_node != 0) blk: {
        const pnode = self.ast.nodes[parent_node];
        try rejectReservedParent(self, pnode, "class");
        break :blk try resolveNodeClassName(self, pnode);
    } else "";
    defer self.current_parent = prev_parent;
    for (members) |m| try checkPropertyDeclaration(self, class_name, self.ast.nodes[m], false);

    var method_count: u16 = 0;
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_method or member.tag == .static_class_method) {
            try compileClassMethodBody(self, class_name, member);
            method_count += 1;
        } else if (member.tag == .interface_method) {
            try compileInterfaceMethodStub(self, class_name, member);
            method_count += 1;
        } else if (member.tag == .class_property_hooks) {
            const ext = member.data.lhs;
            const get_body = self.ast.extra_data[ext + 1];
            const set_body = self.ast.extra_data[ext + 2];
            const set_param_tok = self.ast.extra_data[ext + 3];
            const get_short = self.ast.extra_data[ext + 4];
            const set_short = self.ast.extra_data[ext + 5];
            var prop_name = self.ast.tokenSlice(member.main_token);
            if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
            if (get_body != 0 or (self.ast.extra_data[ext + 4] & 8) != 0) {
                try compilePropertyHook(self, class_name, prop_name, get_body, .get, get_short, 0, member);
                method_count += 1;
            }
            if (set_body != 0 or (self.ast.extra_data[ext + 5] & 8) != 0) {
                try compilePropertyHook(self, class_name, prop_name, set_body, .set, set_short, set_param_tok, member);
                method_count += 1;
            }
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
    var trait_prop_members = std.ArrayListUnmanaged(u32).empty;
    defer trait_prop_members.deinit(self.allocator);
    var trait_hook_members = std.ArrayListUnmanaged(u32).empty;
    defer trait_hook_members.deinit(self.allocator);
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
    // emit hook bodies for trait properties as methods on the using class.
    // mirrors the regular class-property-hook codepath above
    for (trait_prop_members.items) |tpi| {
        const tmember = self.ast.nodes[tpi];
        if (tmember.tag != .class_property_hooks) continue;
        const ext = tmember.data.lhs;
        const get_body = self.ast.extra_data[ext + 1];
        const set_body = self.ast.extra_data[ext + 2];
        const set_param_tok = self.ast.extra_data[ext + 3];
        const get_short = self.ast.extra_data[ext + 4];
        const set_short = self.ast.extra_data[ext + 5];
        var prop_name = self.ast.tokenSlice(tmember.main_token);
        if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
        if (get_body != 0 or (self.ast.extra_data[ext + 4] & 8) != 0) {
            try compilePropertyHook(self, class_name, prop_name, get_body, .get, get_short, 0, tmember);
            method_count += 1;
            try trait_hook_members.append(self.allocator, tpi);
        }
        if (set_body != 0 or (self.ast.extra_data[ext + 5] & 8) != 0) {
            try compilePropertyHook(self, class_name, prop_name, set_body, .set, set_short, set_param_tok, tmember);
            method_count += 1;
            // mark second slot for emitting set-method metadata too
            try trait_hook_members.append(self.allocator, tpi | 0x80000000);
        }
    }

    // compile instance property defaults (push onto stack)
    var prop_count: u16 = 0;
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_property or member.tag == .class_property_hooks) prop_count += 1;
    }
    prop_count += @intCast(trait_prop_members.items.len);
    prop_count += promoted_count;
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_property) {
            if (member.data.lhs != 0) {
                // push a null placeholder - the real default is installed
                // after class_decl via set_prop_default, so a default like
                // `self::CONST` resolves against the now-registered class
                try self.emitOp(.op_null);
            }
        } else if (member.tag == .class_property_hooks) {
            const default_idx = self.ast.extra_data[member.data.lhs];
            if (default_idx != 0) try self.compileNode(default_idx);
        }
    }
    // compile trait property defaults (hook properties keep their default in
    // extra_data[lhs], regular properties keep it directly in lhs)
    for (trait_prop_members.items) |tpi| {
        const tmember = self.ast.nodes[tpi];
        if (tmember.tag == .class_property_hooks) {
            const default_idx = self.ast.extra_data[tmember.data.lhs];
            if (default_idx != 0) try self.compileNode(default_idx);
        } else if (tmember.data.lhs != 0) {
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
            // push null placeholder - the real default is set after class_decl
            // (like constants) so a default referencing self::CONST resolves
            if (member.data.lhs != 0) {
                try self.emitOp(.op_null);
            }
        } else if (member.tag == .const_decl) {
            // push null placeholder - real values set after class_decl so self:: resolves
            try self.emitOp(.op_null);
        }
    }

    const name_idx = try self.addConstant(.{ .string = Value.String.borrowed(class_name) });
    try self.emitOp(.class_decl);
    try self.emitByte(class_modifiers);
    try self.emitU16(name_idx);
    try self.emitU32(lineForToken(self, shape.at));
    try self.emitU32(endLineForBlockStartingAt(self, shape.at));
    try self.emitU16(try docCommentConst(self, shape.at));
    try self.emitU16(method_count);

    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_method or member.tag == .static_class_method) {
            const method_name_str = self.ast.tokenSlice(member.main_token);
            const mname_idx = try self.addConstant(.{ .string = Value.String.borrowed(method_name_str) });
            try self.emitU16(mname_idx);
            const param_nodes = self.ast.extraSlice(member.data.lhs);
            try self.emitByte(@intCast(param_nodes.len));
            try self.emitByte(if (member.tag == .static_class_method) @as(u8, 1) else @as(u8, 0));
            const vis: u8 = @intCast(member.data.rhs >> 30);
            try self.emitByte(vis);
            // method flags: bit 0 = abstract, bit 1 = final
            const m_final: u8 = if ((member.data.rhs >> 28) & 1 == 1) 2 else 0;
            try self.emitByte(m_final);
        } else if (member.tag == .class_property_hooks) {
            const ext = member.data.lhs;
            const get_body = self.ast.extra_data[ext + 1];
            const set_body = self.ast.extra_data[ext + 2];
            var prop_name = self.ast.tokenSlice(member.main_token);
            if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
            if (get_body != 0 or (self.ast.extra_data[ext + 4] & 8) != 0) {
                const hk_name = try std.fmt.allocPrint(self.allocator, "{s}$hook_get", .{prop_name});
                try self.string_allocs.append(self.allocator, hk_name);
                const mname_idx = try self.addConstant(.{ .string = Value.String.borrowed(hk_name) });
                try self.emitU16(mname_idx);
                try self.emitByte(0); // arity
                try self.emitByte(0); // not static
                try self.emitByte(2); // private vis
                try self.emitByte(@intCast((self.ast.extra_data[ext + 4] >> 3) & 3)); // abstract/final
            }
            if (set_body != 0 or (self.ast.extra_data[ext + 5] & 8) != 0) {
                const hk_name = try std.fmt.allocPrint(self.allocator, "{s}$hook_set", .{prop_name});
                try self.string_allocs.append(self.allocator, hk_name);
                const mname_idx = try self.addConstant(.{ .string = Value.String.borrowed(hk_name) });
                try self.emitU16(mname_idx);
                try self.emitByte(1); // arity
                try self.emitByte(0); // not static
                try self.emitByte(2); // private vis
                try self.emitByte(@intCast((self.ast.extra_data[ext + 5] >> 3) & 3)); // abstract/final
            }
        } else if (member.tag == .interface_method) {
            const method_name_str = self.ast.tokenSlice(member.main_token);
            const mname_idx = try self.addConstant(.{ .string = Value.String.borrowed(method_name_str) });
            try self.emitU16(mname_idx);
            const param_nodes = self.ast.extraSlice(member.data.lhs);
            try self.emitByte(@intCast(param_nodes.len));
            try self.emitByte(@intCast((member.data.rhs >> 30) & 1));
            const i_vis: u8 = @intCast((member.data.rhs >> 28) & 0x3);
            try self.emitByte(i_vis);
            try self.emitByte(1); // abstract
        }
    }
    // method metadata for trait property hooks compiled above
    for (trait_hook_members.items) |encoded| {
        const is_set = (encoded & 0x80000000) != 0;
        const tpi: u32 = encoded & 0x7fffffff;
        const tmember = self.ast.nodes[tpi];
        var prop_name = self.ast.tokenSlice(tmember.main_token);
        if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
        const suffix = if (is_set) "$hook_set" else "$hook_get";
        const hk_name = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ prop_name, suffix });
        try self.string_allocs.append(self.allocator, hk_name);
        const mname_idx = try self.addConstant(.{ .string = Value.String.borrowed(hk_name) });
        try self.emitU16(mname_idx);
        try self.emitByte(if (is_set) @as(u8, 1) else @as(u8, 0));
        try self.emitByte(0); // not static
        try self.emitByte(2); // private vis
        try self.emitByte(@intCast((self.ast.extra_data[tmember.data.lhs + @as(u32, if (is_set) 5 else 4)] >> 3) & 3));
    }

    try self.emitU16(prop_count);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_property) {
            var prop_name = self.ast.tokenSlice(member.main_token);
            if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
            const pname_idx = try self.addConstant(.{ .string = Value.String.borrowed(prop_name) });
            try self.emitU16(pname_idx);
            try self.emitByte(if (member.data.lhs != 0) @as(u8, 1) else @as(u8, 0));
            try self.emitByte(@intCast(member.data.rhs & 0xff));
            try self.emitU16(try propertyTypeConst(self, member.data.rhs));
            try self.emitU16(try docCommentConst(self, member.main_token));
        } else if (member.tag == .class_property_hooks) {
            var prop_name = self.ast.tokenSlice(member.main_token);
            if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
            const pname_idx = try self.addConstant(.{ .string = Value.String.borrowed(prop_name) });
            try self.emitU16(pname_idx);
            const default_idx = self.ast.extra_data[member.data.lhs];
            try self.emitByte((if (default_idx != 0) @as(u8, 1) else @as(u8, 0)) | propertyVirtualFlag(self, member));
            try self.emitByte(@intCast(member.data.rhs & 0xff));
            try self.emitU16(try propertyTypeConst(self, member.data.rhs));
            try self.emitU16(try docCommentConst(self, member.main_token));
        }
    }
    // trait properties (own + hook variants)
    for (trait_prop_members.items) |tpi| {
        const tmember = self.ast.nodes[tpi];
        var tprop_name = self.ast.tokenSlice(tmember.main_token);
        if (tprop_name.len > 0 and tprop_name[0] == '$') tprop_name = tprop_name[1..];
        const tpname_idx = try self.addConstant(.{ .string = Value.String.borrowed(tprop_name) });
        try self.emitU16(tpname_idx);
        const has_default: u8 = if (tmember.tag == .class_property_hooks) blk: {
            const default_idx = self.ast.extra_data[tmember.data.lhs];
            break :blk if (default_idx != 0) @as(u8, 1) else @as(u8, 0);
        } else if (tmember.data.lhs != 0) @as(u8, 1) else @as(u8, 0);
        try self.emitByte(has_default | propertyVirtualFlag(self, tmember));
        try self.emitByte(@intCast(tmember.data.rhs & 0xff));
        try self.emitU16(try propertyTypeConst(self, tmember.data.rhs));
        try self.emitU16(try docCommentConst(self, tmember.main_token));
    }
    // promoted constructor params as properties
    for (constructor_params) |p| {
        const pnode = self.ast.nodes[p];
        const promotion = (pnode.data.rhs >> 2) & 3;
        if (promotion > 0) {
            var param_name = self.ast.tokenSlice(pnode.main_token);
            if (param_name.len > 0 and param_name[0] == '$') param_name = param_name[1..];
            const pname_idx = try self.addConstant(.{ .string = Value.String.borrowed(param_name) });
            try self.emitU16(pname_idx);
            try self.emitByte(1);
            const is_ro: u8 = if ((pnode.data.rhs & 16) != 0) 4 else 0;
            const set_promo = (pnode.data.rhs >> 5) & 3;
            const asymm_bits: u8 = if (set_promo > 0) (@as(u8, @intCast(set_promo - 1)) << 3) | 0x20 else 0;
            const is_final: u8 = if ((pnode.data.rhs & 0x80) != 0) 0x80 else 0;
            try self.emitByte(@as(u8, @intCast(promotion - 1)) | is_ro | asymm_bits | 0x40 | is_final);
            const param_type_extra = pnode.data.rhs >> 8;
            if (param_type_extra == 0) {
                try self.emitU16(0xffff);
            } else {
                const start_tok = self.ast.extra_data[param_type_extra - 1];
                const end_tok = self.ast.extra_data[param_type_extra];
                const type_str = try buildTypeString(self, start_tok, end_tok);
                try self.emitU16(try self.addConstant(.{ .string = Value.String.borrowed(type_str) }));
            }
            try self.emitU16(0xffff); // promoted params don't carry their own doc comment
        }
    }

    try self.emitU16(static_prop_count);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .static_class_property) {
            var prop_name = self.ast.tokenSlice(member.main_token);
            if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
            const pname_idx = try self.addConstant(.{ .string = Value.String.borrowed(prop_name) });
            try self.emitU16(pname_idx);
            try self.emitByte(if (member.data.lhs != 0) @as(u8, 1) else @as(u8, 0));
            try self.emitByte(@intCast(member.data.rhs & 0xff));
            try self.emitByte(0); // 0 = static property
            try self.emitU16(try propertyTypeConst(self, member.data.rhs));
            try self.emitU16(try docCommentConst(self, member.main_token));
        } else if (member.tag == .const_decl) {
            const cname = self.ast.tokenSlice(member.main_token);
            const cname_idx = try self.addConstant(.{ .string = Value.String.borrowed(cname) });
            try self.emitU16(cname_idx);
            try self.emitByte(1); // always has a value
            try self.emitByte(@intCast(member.data.rhs & 0x13)); // bits 0-1 visibility, bit 4 final
            try self.emitByte(1); // 1 = constant
            try self.emitU16(try propertyTypeConst(self, member.data.rhs));
            try self.emitU16(try docCommentConst(self, member.main_token));
        }
    }

    if (parent_node != 0) {
        const pnode = self.ast.nodes[parent_node];
        const parent_name = try resolveNodeClassName(self, pnode);
        const parent_idx = try self.addConstant(.{ .string = Value.String.borrowed(parent_name) });
        try self.emitU16(parent_idx);
    } else {
        try self.emitU16(0xffff);
    }

    // emit implements count and names (already resolved in impl_names)
    try self.emitByte(@intCast(impl_count));
    for (0..impl_count) |i| {
        const iname_idx = try self.addConstant(.{ .string = Value.String.borrowed(impl_names[i]) });
        try self.emitU16(iname_idx);
    }

    // collect all trait names from trait_use statements
    var all_traits = std.ArrayListUnmanaged([]const u8).empty;
    defer all_traits.deinit(self.allocator);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .trait_use) {
            for (self.ast.extraSlice(member.data.lhs)) |tn| {
                const tn_node = self.ast.nodes[tn];
                const is_absolute = tn_node.tag == .qualified_name and tn_node.data.rhs == 1;
                const raw_name = if (tn_node.tag == .qualified_name) blk: {
                    const parts = self.ast.extraSlice(tn_node.data.lhs);
                    break :blk try self.buildQualifiedString(parts);
                } else self.ast.tokenSlice(tn_node.main_token);
                // FQN (had leading backslash): skip use-alias + namespace prefix
                const resolved = if (is_absolute) raw_name else self.resolveClassName(raw_name);
                try all_traits.append(self.allocator, resolved);
            }
        }
    }
    try self.emitByte(@intCast(all_traits.items.len));
    for (all_traits.items) |tname| {
        const tname_idx = try self.addConstant(.{ .string = Value.String.borrowed(tname) });
        try self.emitU16(tname_idx);
    }

    try emitTraitRules(self, members);

    // class-level attributes
    const class_attrs = try extractAttributes(self, shape.attributes_at, .{ .class = .{ .kind = .class, .name = class_name, .modifiers = class_modifiers } });
    try emitAttributeData(self, class_attrs);
    freeAttrSlice(self.allocator, class_attrs);

    // method attributes: count of methods that have attrs, then for each: name_idx + attr data
    const MemberAttr = struct { name: []const u8, attrs: []const ParsedAttr };
    var methods_with_attrs = std.ArrayListUnmanaged(MemberAttr).empty;
    defer methods_with_attrs.deinit(self.allocator);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_method or member.tag == .static_class_method or member.tag == .interface_method) {
            const mattrs = try extractAttributes(self, member.main_token, AttrTarget.method);
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
        const mname_idx = try self.addConstant(.{ .string = Value.String.borrowed(ma.name) });
        try self.emitU16(mname_idx);
        try emitAttributeData(self, ma.attrs);
    }
    for (methods_with_attrs.items) |ma| freeAttrSlice(self.allocator, ma.attrs);

    // property attributes (includes promoted constructor params - PHP exposes
    // their attributes via ReflectionProperty as well as ReflectionParameter)
    var props_with_attrs = std.ArrayListUnmanaged(MemberAttr).empty;
    defer props_with_attrs.deinit(self.allocator);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_property) {
            const pattrs = try extractAttributes(self, member.main_token, AttrTarget.property);
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
    for (constructor_params) |p| {
        const pnode = self.ast.nodes[p];
        const promotion = (pnode.data.rhs >> 2) & 3;
        if (promotion == 0) continue;
        const pattrs = try extractAttributes(self, pnode.main_token, AttrTarget.promoted);
        if (pattrs.len == 0) continue;
        var pname = self.ast.tokenSlice(pnode.main_token);
        if (pname.len > 0 and pname[0] == '$') pname = pname[1..];
        try props_with_attrs.append(self.allocator, .{
            .name = pname,
            .attrs = pattrs,
        });
    }
    // a trait's property the class doesn't declare itself keeps the trait's
    // attributes
    trait_props: for (trait_prop_members.items) |tpi| {
        const tmember = self.ast.nodes[tpi];
        var tname = self.ast.tokenSlice(tmember.main_token);
        if (tname.len > 0 and tname[0] == '$') tname = tname[1..];
        for (props_with_attrs.items) |existing| {
            if (std.mem.eql(u8, existing.name, tname)) continue :trait_props;
        }
        for (members) |member_idx| {
            const member = self.ast.nodes[member_idx];
            if (member.tag != .class_property and member.tag != .class_property_hooks) continue;
            const own = self.ast.tokenSlice(member.main_token);
            if (std.mem.eql(u8, if (own.len > 0 and own[0] == '$') own[1..] else own, tname)) continue :trait_props;
        }
        const tattrs = try extractAttributes(self, tmember.main_token, .unchecked);
        if (tattrs.len == 0) continue;
        try props_with_attrs.append(self.allocator, .{ .name = tname, .attrs = tattrs });
    }
    try self.emitByte(@intCast(props_with_attrs.items.len));
    for (props_with_attrs.items) |pa| {
        const ppname_idx = try self.addConstant(.{ .string = Value.String.borrowed(pa.name) });
        try self.emitU16(ppname_idx);
        try emitAttributeData(self, pa.attrs);
    }
    for (props_with_attrs.items) |pa| freeAttrSlice(self.allocator, pa.attrs);

    // constant attributes
    var consts_with_attrs = std.ArrayListUnmanaged(MemberAttr).empty;
    defer consts_with_attrs.deinit(self.allocator);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .const_decl) {
            const cattrs = try extractAttributes(self, member.main_token, AttrTarget.class_constant);
            if (cattrs.len > 0) {
                try consts_with_attrs.append(self.allocator, .{
                    .name = self.ast.tokenSlice(member.main_token),
                    .attrs = cattrs,
                });
            }
        }
    }
    try self.emitByte(@intCast(consts_with_attrs.items.len));
    for (consts_with_attrs.items) |ca| {
        const caname_idx = try self.addConstant(.{ .string = Value.String.borrowed(ca.name) });
        try self.emitU16(caname_idx);
        try emitAttributeData(self, ca.attrs);
    }
    for (consts_with_attrs.items) |ca| freeAttrSlice(self.allocator, ca.attrs);

    // parameter attributes: methods that have params with attrs
    const ParamAttr = struct { name: []const u8, attrs: []const ParsedAttr };
    const MethodParamAttrs = struct { method_name: []const u8, params: []const ParamAttr };
    var methods_with_param_attrs = std.ArrayListUnmanaged(MethodParamAttrs).empty;
    defer methods_with_param_attrs.deinit(self.allocator);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_method or member.tag == .static_class_method) {
            const param_nodes = self.ast.extraSlice(member.data.lhs);
            var params_with_attrs = std.ArrayListUnmanaged(ParamAttr).empty;
            for (param_nodes) |pn| {
                const pnode = self.ast.nodes[pn];
                const pattrs = try extractAttributes(self, pnode.main_token, if ((pnode.data.rhs >> 2) & 3 > 0) AttrTarget.promoted else AttrTarget.parameter);
                if (pattrs.len > 0) {
                    var pname = self.ast.tokenSlice(pnode.main_token);
                    if (pname.len > 0 and pname[0] == '$') pname = pname[1..];
                    try params_with_attrs.append(self.allocator, .{ .name = pname, .attrs = pattrs });
                }
            }
            if (params_with_attrs.items.len > 0) {
                try methods_with_param_attrs.append(self.allocator, .{
                    .method_name = self.ast.tokenSlice(member.main_token),
                    .params = params_with_attrs.toOwnedSlice(self.allocator) catch &.{},
                });
            } else {
                params_with_attrs.deinit(self.allocator);
            }
        }
    }
    try self.emitByte(@intCast(methods_with_param_attrs.items.len));
    for (methods_with_param_attrs.items) |mpa| {
        const mpa_name_idx = try self.addConstant(.{ .string = Value.String.borrowed(mpa.method_name) });
        try self.emitU16(mpa_name_idx);
        try self.emitByte(@intCast(mpa.params.len));
        for (mpa.params) |pa| {
            const pa_name_idx = try self.addConstant(.{ .string = Value.String.borrowed(pa.name) });
            try self.emitU16(pa_name_idx);
            try emitAttributeData(self, pa.attrs);
        }
    }
    for (methods_with_param_attrs.items) |mpa| {
        for (mpa.params) |pa| freeAttrSlice(self.allocator, pa.attrs);
        self.allocator.free(mpa.params);
    }

    // set class constants after class_decl so self:: references resolve
    const cname_idx = try self.addConstant(.{ .string = Value.String.borrowed(class_name) });
    try self.emitOp(.enter_class_scope);
    try self.emitU16(cname_idx);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .const_decl) try emitClassConstant(self, class_name, cname_idx, member);
    }
    // set static-property defaults after the constants block so a default
    // expression like `public static $x = self::CONST` sees the class and
    // its (already-set) constants. the rest wait with the instance defaults
    // below for the class's first use
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .static_class_property and member.data.lhs != 0 and defaultExprIsLiteral(self.ast, member.data.lhs)) {
            try self.compileNode(member.data.lhs);
            var sp_name = self.ast.tokenSlice(member.main_token);
            if (sp_name.len > 0 and sp_name[0] == '$') sp_name = sp_name[1..];
            const sp_idx = try self.addConstant(.{ .string = Value.String.borrowed(sp_name) });
            try self.emitOp(.set_static_prop_default);
            try self.emitU16(cname_idx);
            try self.emitU16(sp_idx);
            try self.emitOp(.pop);
        }
    }
    try self.emitOp(.leave_class_scope);
    // set instance-property defaults after class_decl + constants so a default
    // expression like `public int $x = self::CONST` resolves against the
    // now-registered class (the prelude pushed null placeholders). defaults,
    // static or not, that read another class or a global constant wait for
    // the class's first use, like php: the class they name may itself extend
    // this one
    if (try compileDeferredPropDefaults(self, class_name, members)) {
        try self.emitOp(.defer_prop_defaults);
        try self.emitU16(cname_idx);
    }
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_property and member.data.lhs != 0 and defaultExprIsLiteral(self.ast, member.data.lhs)) {
            try self.compileNode(member.data.lhs);
            var p_name = self.ast.tokenSlice(member.main_token);
            if (p_name.len > 0 and p_name[0] == '$') p_name = p_name[1..];
            const p_idx = try self.addConstant(.{ .string = Value.String.borrowed(p_name) });
            try self.emitOp(.set_prop_default);
            try self.emitU16(cname_idx);
            try self.emitU16(p_idx);
            try self.emitOp(.pop);
        }
    }
}

pub fn compileAnonymousClass(self: *Compiler, node: Ast.Node) Error!void {
    self.closure_count += 1;

    // rhs: {ctor_arg_count, ctor_args..., parent, impl_count, impls...}
    const rhs_base = node.data.rhs;
    const ctor_arg_count = self.ast.extra_data[rhs_base];
    const ctor_args_start = rhs_base + 1;
    const parent_at = ctor_args_start + ctor_arg_count;
    const impl_count = self.ast.extra_data[parent_at + 1];

    // zend_generate_anon_class_name: the parent or first interface, a NUL,
    // then the file, the line of `class` and the runtime definition number,
    // so messages, which stop at the NUL, read `Foo@anonymous`
    const prefix_node = if (self.ast.extra_data[parent_at] != 0) self.ast.extra_data[parent_at] else if (impl_count > 0) self.ast.extra_data[parent_at + 2] else 0;
    const prefix = if (prefix_node != 0) try resolveNodeClassName(self, self.ast.nodes[prefix_node]) else "class";
    var class_tok = node.main_token;
    while (class_tok < self.ast.tokens.len and self.ast.tokens[class_tok].tag != .kw_class) class_tok += 1;
    const key = compiler.anon_class_keys.get(node.main_token) orelse compiler.reserveRtdKeys(1);
    const anon_name = try std.fmt.allocPrint(self.allocator, "{s}@anonymous\x00{s}:{d}${x}", .{ prefix, self.file_path, lineForToken(self, class_tok), key });
    try self.string_allocs.append(self.allocator, anon_name);
    // attributes written after `new` precede the class keyword
    var attributes_at = node.main_token;
    for (self.ast.attr_ranges) |ar| {
        if (ar.start == node.main_token + 1) attributes_at = ar.target_tok;
    }
    const name_idx = try self.addConstant(.{ .string = Value.String.borrowed(anon_name) });
    try self.emitOp(.jump_if_class_declared);
    try self.emitU16(name_idx);
    try self.emitU16(0xffff);
    const declared_jump = self.chunk.offset() - 2;
    // `new readonly class`: the modifier comes before the class keyword
    const first = if (attributes_at != node.main_token) attributes_at else node.main_token + 1;
    const modifiers: u8 = switch (self.ast.tokens[first].tag) {
        .kw_abstract => 1,
        .kw_final => 2,
        .kw_readonly => 4,
        else => 0,
    };
    try compileClass(self, .{
        .name = anon_name,
        .members = self.ast.extraSlice(node.data.lhs),
        .modifiers = modifiers,
        .parent_node = self.ast.extra_data[parent_at],
        .impl_nodes = self.ast.extra_data[parent_at + 2 .. parent_at + 2 + impl_count],
        .at = node.main_token,
        .attributes_at = attributes_at,
    });

    self.patchJump(declared_jump);

    const ctor_args_slice = self.ast.extra_data[ctor_args_start .. ctor_args_start + ctor_arg_count];
    try self.emitOp(.new_reserve);
    defer self.emitOp(.new_end) catch {};
    if (@import("compiler_expr.zig").hasSplatOrNamed(self.ast, ctor_args_slice)) {
        var guards = try @import("compiler_expr.zig").emitSpreadArgs(self, ctor_args_slice);
        try @import("compiler_expr.zig").emitSpreadCallOp(self, &guards, .new_obj, name_idx, 0xFF);
    } else {
        for (ctor_args_slice) |arg| try self.compileNode(arg);
        try self.emitOp(.new_obj);
        try self.emitU16(name_idx);
        try self.emitByte(@intCast(ctor_arg_count));
    }
}

pub fn compileInterfaceDecl(self: *Compiler, node: Ast.Node) Error!void {
    const iface_name = self.declaredName(self.ast.tokenSlice(node.main_token));
    for (self.ast.extraSlice(node.data.lhs)) |m| try checkPropertyDeclaration(self, iface_name, self.ast.nodes[m], true);
    const members = self.ast.extraSlice(node.data.lhs);
    try checkImportCollision(self, node.main_token, .class, iface_name);
    try checkDuplicateMembers(self, iface_name, members);
    try checkConstDecls(self, iface_name, members);

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

    const name_idx = try self.addConstant(.{ .string = Value.String.borrowed(iface_name) });
    try self.emitOp(.interface_decl);
    try self.emitU16(name_idx);
    try self.emitU32(lineForToken(self, node.main_token));
    try self.emitU32(endLineForBlockStartingAt(self, node.main_token));
    try self.emitU16(try docCommentConst(self, node.main_token));
    try self.emitU16(method_count);

    for (members) |m| {
        const member = self.ast.nodes[m];
        if (member.tag == .interface_method) {
            const mname = self.ast.tokenSlice(member.main_token);
            const mname_idx = try self.addConstant(.{ .string = Value.String.borrowed(mname) });
            try self.emitU16(mname_idx);
        }
    }

    if (node.data.rhs != 0) {
        const parent_count = self.ast.extra_data[node.data.rhs];
        try self.emitByte(@intCast(parent_count));
        for (0..parent_count) |i| {
            const pnode = self.ast.nodes[self.ast.extra_data[node.data.rhs + 1 + i]];
            try rejectReservedParent(self, pnode, "interface");
            const parent_name = try resolveNodeClassName(self, pnode);
            const pidx = try self.addConstant(.{ .string = Value.String.borrowed(parent_name) });
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
            const cname_idx = try self.addConstant(.{ .string = Value.String.borrowed(cname) });
            try self.emitU16(cname_idx);
            try self.emitU16(try docCommentConst(self, member.main_token));
            try self.emitByte(@intCast(member.data.rhs & 0x13)); // bits 0-1 visibility, bit 4 final
            try self.emitU16(try propertyTypeConst(self, member.data.rhs));
        }
    }

    // interface-level attributes
    const iface_attrs = try extractAttributes(self, node.main_token, .{ .class = .{ .kind = .interface, .name = iface_name } });
    try emitAttributeData(self, iface_attrs);
    freeAttrSlice(self.allocator, iface_attrs);

    // method attributes
    const MemberAttr = struct { name: []const u8, attrs: []const ParsedAttr };
    var methods_with_attrs = std.ArrayListUnmanaged(MemberAttr).empty;
    defer methods_with_attrs.deinit(self.allocator);
    for (members) |m| {
        const member = self.ast.nodes[m];
        if (member.tag == .interface_method) {
            const mattrs = try extractAttributes(self, member.main_token, AttrTarget.method);
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
        const mname_idx = try self.addConstant(.{ .string = Value.String.borrowed(ma.name) });
        try self.emitU16(mname_idx);
        try emitAttributeData(self, ma.attrs);
    }
    for (methods_with_attrs.items) |ma| freeAttrSlice(self.allocator, ma.attrs);

    // Property contracts carry their own metadata, not callable dummy methods.
    var property_count: u16 = 0;
    for (members) |m| {
        if (self.ast.nodes[m].tag == .class_property_hooks) property_count += 1;
    }
    try self.emitU16(property_count);
    for (members) |m| {
        const member = self.ast.nodes[m];
        if (member.tag != .class_property_hooks) continue;
        const prop_name = self.ast.tokenSlice(member.main_token)[1..];
        try self.emitU16(try self.addConstant(.{ .string = Value.String.borrowed(prop_name) }));
        try self.emitU16(try propertyTypeConst(self, member.data.rhs));
        try self.emitU16(try docCommentConst(self, member.main_token));
        const ext = member.data.lhs;
        const mask: u8 = (if ((self.ast.extra_data[ext + 4] & 8) != 0) @as(u8, 1) else 0) |
            (if ((self.ast.extra_data[ext + 5] & 8) != 0) @as(u8, 2) else 0);
        try self.emitByte(mask);
        for ([_][]const u8{ "$hook_get", "$hook_set" }, 0..) |suffix, i| {
            if (mask & (@as(u8, 1) << @intCast(i)) == 0) continue;
            const hook = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ prop_name, suffix });
            try self.string_allocs.append(self.allocator, hook);
            try self.emitU16(try self.addConstant(.{ .string = Value.String.borrowed(hook) }));
        }
        const attrs = try extractAttributes(self, member.main_token, AttrTarget.property);
        try emitAttributeData(self, attrs);
        freeAttrSlice(self.allocator, attrs);
    }

    // constant attributes
    var consts_with_attrs = std.ArrayListUnmanaged(MemberAttr).empty;
    defer consts_with_attrs.deinit(self.allocator);
    for (members) |m| {
        const member = self.ast.nodes[m];
        if (member.tag != .const_decl) continue;
        const cattrs = try extractAttributes(self, member.main_token, AttrTarget.class_constant);
        if (cattrs.len > 0) try consts_with_attrs.append(self.allocator, .{ .name = self.ast.tokenSlice(member.main_token), .attrs = cattrs });
    }
    try self.emitByte(@intCast(consts_with_attrs.items.len));
    for (consts_with_attrs.items) |ca| {
        try self.emitU16(try self.addConstant(.{ .string = Value.String.borrowed(ca.name) }));
        try emitAttributeData(self, ca.attrs);
    }
    for (consts_with_attrs.items) |ca| freeAttrSlice(self.allocator, ca.attrs);

    // set interface constants after interface_decl so self:: references resolve
    try self.emitOp(.enter_class_scope);
    try self.emitU16(name_idx);
    for (members) |m| {
        const member = self.ast.nodes[m];
        if (member.tag == .const_decl) try emitClassConstant(self, iface_name, name_idx, member);
    }
    try self.emitOp(.leave_class_scope);

    // register stub functions so reflection can introspect interface method signatures
    for (members) |m| {
        const member = self.ast.nodes[m];
        if (member.tag == .interface_method) {
            try compileInterfaceMethodStub(self, iface_name, member);
        } else if (member.tag == .class_property_hooks) {
            const ext = member.data.lhs;
            const prop_name = self.ast.tokenSlice(member.main_token)[1..];
            if ((self.ast.extra_data[ext + 4] & 8) != 0) try compilePropertyHook(self, iface_name, prop_name, 0, .get, self.ast.extra_data[ext + 4], 0, member);
            if ((self.ast.extra_data[ext + 5] & 8) != 0) try compilePropertyHook(self, iface_name, prop_name, 0, .set, self.ast.extra_data[ext + 5], self.ast.extra_data[ext + 3], member);
        }
    }
}

pub fn compileTraitDecl(self: *Compiler, node: Ast.Node) Error!void {
    const trait_name = self.declaredName(self.ast.tokenSlice(node.main_token));
    const members = self.ast.extraSlice(node.data.lhs);
    try checkImportCollision(self, node.main_token, .class, trait_name);
    try checkDuplicateMembers(self, trait_name, members);
    try checkConstDecls(self, trait_name, members);

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
    var sub_traits = std.ArrayListUnmanaged([]const u8).empty;
    defer sub_traits.deinit(self.allocator);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .trait_use) {
            for (self.ast.extraSlice(member.data.lhs)) |tn| {
                const tn_node = self.ast.nodes[tn];
                try sub_traits.append(self.allocator, try @import("compiler_expr.zig").resolveNodeClassName(self, tn_node));
            }
        }
    }

    // store property member indices (own + sub-trait properties)
    var prop_indices = std.ArrayListUnmanaged(u32).empty;
    for (sub_traits.items) |st| {
        if (self.trait_properties.get(st)) |sub_props| {
            for (sub_props) |pi| try prop_indices.append(self.allocator, pi);
        }
    }
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_property or member.tag == .class_property_hooks) {
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
    var own_props = std.ArrayListUnmanaged(u32).empty;
    defer own_props.deinit(self.allocator);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_property or member.tag == .class_property_hooks) {
            try own_props.append(self.allocator, member_idx);
        }
    }

    // collect static property members
    var static_props = std.ArrayListUnmanaged(u32).empty;
    defer static_props.deinit(self.allocator);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .static_class_property) {
            try static_props.append(self.allocator, member_idx);
        }
    }

    // collect const_decl members (PHP 8.2+ trait constants)
    var const_decls = std.ArrayListUnmanaged(u32).empty;
    defer const_decls.deinit(self.allocator);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .const_decl) try const_decls.append(self.allocator, member_idx);
    }

    // compile defaults for trait constants first (popped third by VM)
    for (const_decls.items) |pi| {
        const pmember = self.ast.nodes[pi];
        if (pmember.data.lhs != 0) try self.compileNode(pmember.data.lhs);
    }

    // compile defaults for static properties (popped second by VM)
    for (static_props.items) |pi| {
        const pmember = self.ast.nodes[pi];
        if (pmember.data.lhs != 0) {
            try self.compileNode(pmember.data.lhs);
        }
    }

    // compile defaults for own properties last (popped first by VM)
    for (own_props.items) |pi| {
        const pmember = self.ast.nodes[pi];
        const default = if (pmember.tag == .class_property_hooks) self.ast.extra_data[pmember.data.lhs] else pmember.data.lhs;
        if (default != 0) try self.compileNode(default);
    }

    const name_idx = try self.addConstant(.{ .string = Value.String.borrowed(trait_name) });
    try self.emitOp(.trait_decl);
    try self.emitU16(name_idx);
    try self.emitU32(lineForToken(self, node.main_token));
    try self.emitU32(endLineForBlockStartingAt(self, node.main_token));
    try self.emitU16(try docCommentConst(self, node.main_token));
    try self.emitByte(@intCast(sub_traits.items.len));
    for (sub_traits.items) |st| {
        const st_idx = try self.addConstant(.{ .string = Value.String.borrowed(st) });
        try self.emitU16(st_idx);
    }
    // a trait's own insteadof and as rules apply when it is composed
    try emitTraitRules(self, members);
    try self.emitByte(@intCast(own_props.items.len));
    for (own_props.items) |pi| {
        const pmember = self.ast.nodes[pi];
        var pname = self.ast.tokenSlice(pmember.main_token);
        if (pname.len > 0 and pname[0] == '$') pname = pname[1..];
        const pname_idx = try self.addConstant(.{ .string = Value.String.borrowed(pname) });
        try self.emitU16(pname_idx);
        const default = if (pmember.tag == .class_property_hooks) self.ast.extra_data[pmember.data.lhs] else pmember.data.lhs;
        try self.emitByte(if (default != 0) @as(u8, 1) else @as(u8, 0));
        try self.emitByte(@intCast(pmember.data.rhs & 0xff));
    }
    try self.emitByte(@intCast(static_props.items.len));
    for (static_props.items) |pi| {
        const pmember = self.ast.nodes[pi];
        var pname = self.ast.tokenSlice(pmember.main_token);
        if (pname.len > 0 and pname[0] == '$') pname = pname[1..];
        const pname_idx = try self.addConstant(.{ .string = Value.String.borrowed(pname) });
        try self.emitU16(pname_idx);
        try self.emitByte(if (pmember.data.lhs != 0) @as(u8, 1) else @as(u8, 0));
        try self.emitByte(@intCast(pmember.data.rhs & 0xff));
    }

    // trait constants (PHP 8.2+)
    try self.emitByte(@intCast(const_decls.items.len));
    for (const_decls.items) |pi| {
        const pmember = self.ast.nodes[pi];
        const pname = self.ast.tokenSlice(pmember.main_token);
        const pname_idx = try self.addConstant(.{ .string = Value.String.borrowed(pname) });
        try self.emitU16(pname_idx);
        try self.emitByte(if (pmember.data.lhs != 0) @as(u8, 1) else @as(u8, 0));
        try self.emitU16(try docCommentConst(self, pmember.main_token));
        try self.emitByte(@intCast(pmember.data.rhs & 0x13)); // bits 0-1 visibility, bit 4 final
        try self.emitU16(try propertyTypeConst(self, pmember.data.rhs));
    }

    // trait-level attributes
    const trait_attrs = try extractAttributes(self, node.main_token, .{ .class = .{ .kind = .trait, .name = trait_name } });
    try emitAttributeData(self, trait_attrs);
    freeAttrSlice(self.allocator, trait_attrs);

    // method attributes
    const MemberAttr = struct { name: []const u8, attrs: []const ParsedAttr };
    var methods_with_attrs = std.ArrayListUnmanaged(MemberAttr).empty;
    defer methods_with_attrs.deinit(self.allocator);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_method or member.tag == .static_class_method or member.tag == .interface_method) {
            // a class using the trait reads its parameters' from here
            const method_key = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ trait_name, self.ast.tokenSlice(member.main_token) });
            try self.string_allocs.append(self.allocator, method_key);
            try appendParamAttributes(self, method_key, self.ast.extraSlice(member.data.lhs));
            const mattrs = try extractAttributes(self, member.main_token, AttrTarget.method);
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
        const mname_idx = try self.addConstant(.{ .string = Value.String.borrowed(ma.name) });
        try self.emitU16(mname_idx);
        try emitAttributeData(self, ma.attrs);
    }
    for (methods_with_attrs.items) |ma| freeAttrSlice(self.allocator, ma.attrs);

    // property attributes
    var props_with_attrs = std.ArrayListUnmanaged(MemberAttr).empty;
    defer props_with_attrs.deinit(self.allocator);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_property) {
            const pattrs = try extractAttributes(self, member.main_token, AttrTarget.property);
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
        const ppname_idx = try self.addConstant(.{ .string = Value.String.borrowed(pa.name) });
        try self.emitU16(ppname_idx);
        try emitAttributeData(self, pa.attrs);
    }
    for (props_with_attrs.items) |pa| freeAttrSlice(self.allocator, pa.attrs);
}

// php's compile-time checks of an enum (zend_compile_enum_type and its
// member compilation): the backing type, then each member in order
fn checkEnumDecl(self: *Compiler, enum_name: []const u8, enum_tok: u32, backed_type_token: u32, members: []const u32) Error!void {
    if (backed_type_token != 0) {
        var end = backed_type_token;
        while (end < self.ast.tokens.len and self.ast.tokens[end].tag != .l_brace and self.ast.tokens[end].tag != .kw_implements) end += 1;
        const written = try buildTypeString(self, backed_type_token, end);
        if (std.mem.eql(u8, written, "int") or std.mem.eql(u8, written, "string")) return checkEnumMembers(self, enum_name, enum_tok, true, members);
        const shown = blk: {
            const t = php_types.parse(self.allocator, written, enum_name, null) catch break :blk written;
            defer t.deinit(self.allocator);
            const text = php_types.format(self.allocator, t) catch break :blk written;
            try self.string_allocs.append(self.allocator, text);
            break :blk text;
        };
        return self.failFmt(backed_type_token, "Enum backing type must be int or string, {s} given", .{shown});
    }
    return checkEnumMembers(self, enum_name, enum_tok, false, members);
}

fn checkEnumMembers(self: *Compiler, enum_name: []const u8, enum_tok: u32, backed: bool, members: []const u32) Error!void {
    for (members) |m| {
        const member = self.ast.nodes[m];
        switch (member.tag) {
            .enum_case => {
                const case = self.ast.tokenSlice(member.main_token);
                if (!backed and member.data.lhs != 0) return self.failFmt(member.main_token, "Case {s} of non-backed enum {s} must not have a value", .{ case, enum_name });
                if (backed and member.data.lhs == 0) return self.failFmt(member.main_token, "Case {s} of backed enum {s} must have a value", .{ case, enum_name });
            },
            .class_property, .static_class_property, .class_property_hooks => return self.failFmt(member.main_token, "Enum {s} cannot include properties", .{enum_name}),
            .interface_method => return self.failFmt(member.main_token, "Enum method {s}::{s}() must not be abstract", .{ enum_name, self.ast.tokenSlice(member.main_token) }),
            else => {},
        }
    }
    _ = enum_tok;
}

pub fn compileEnumDecl(self: *Compiler, node: Ast.Node) Error!void {
    const enum_name = self.declaredName(self.ast.tokenSlice(node.main_token));
    const outer_class = self.current_class;
    self.current_class = enum_name;
    defer self.current_class = outer_class;
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
    try checkImportCollision(self, node.main_token, .class, enum_name);
    try checkEnumDecl(self, enum_name, node.main_token, backed_type_token, members);
    try checkDuplicateMembers(self, enum_name, members);
    try checkConstDecls(self, enum_name, members);

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

    const name_idx = try self.addConstant(.{ .string = Value.String.borrowed(enum_name) });
    try self.emitOp(.enum_decl);
    try self.emitU16(name_idx);
    try self.emitU32(lineForToken(self, node.main_token));
    try self.emitU32(endLineForBlockStartingAt(self, node.main_token));
    try self.emitU16(try docCommentConst(self, node.main_token));
    try self.emitByte(backed_type);
    try self.emitByte(case_count);

    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .enum_case) {
            const case_name = self.ast.tokenSlice(member.main_token);
            const cname_idx = try self.addConstant(.{ .string = Value.String.borrowed(case_name) });
            try self.emitU16(cname_idx);
            try self.emitByte(if (member.data.lhs != 0) @as(u8, 1) else @as(u8, 0));
            try self.emitU16(try docCommentConst(self, member.main_token));
        }
    }

    try self.emitU16(method_count);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_method or member.tag == .static_class_method) {
            const method_name_str = self.ast.tokenSlice(member.main_token);
            const mname_idx = try self.addConstant(.{ .string = Value.String.borrowed(method_name_str) });
            try self.emitU16(mname_idx);
            const param_nodes = self.ast.extraSlice(member.data.lhs);
            try self.emitByte(@intCast(param_nodes.len));
            try self.emitByte(if (member.tag == .static_class_method) @as(u8, 1) else @as(u8, 0));
            const vis: u8 = @intCast(member.data.rhs >> 30);
            try self.emitByte(vis);
            const m_final: u8 = if ((member.data.rhs >> 28) & 1 == 1) 2 else 0;
            try self.emitByte(m_final);
        }
    }

    try self.emitByte(@intCast(impl_count));
    for (0..impl_count) |i| {
        const impl_node = self.ast.nodes[self.ast.extra_data[rhs_base + 2 + i]];
        const iname_idx = try self.addConstant(.{ .string = Value.String.borrowed(self.ast.tokenSlice(impl_node.main_token)) });
        try self.emitU16(iname_idx);
    }

    // trait names
    var enum_traits = std.ArrayListUnmanaged([]const u8).empty;
    defer enum_traits.deinit(self.allocator);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .trait_use) {
            for (self.ast.extraSlice(member.data.lhs)) |tn| {
                const tn_node = self.ast.nodes[tn];
                const raw_name = if (tn_node.tag == .qualified_name) blk: {
                    const parts = self.ast.extraSlice(tn_node.data.lhs);
                    break :blk try self.buildQualifiedString(parts);
                } else self.ast.tokenSlice(tn_node.main_token);
                try enum_traits.append(self.allocator, self.resolveClassName(raw_name));
            }
        }
    }
    try self.emitByte(@intCast(enum_traits.items.len));
    for (enum_traits.items) |tname| {
        const tname_idx = try self.addConstant(.{ .string = Value.String.borrowed(tname) });
        try self.emitU16(tname_idx);
    }

    // enum-level attributes
    const enum_attrs = try extractAttributes(self, node.main_token, .{ .class = .{ .kind = .@"enum", .name = enum_name } });
    try emitAttributeData(self, enum_attrs);
    freeAttrSlice(self.allocator, enum_attrs);

    // method attributes
    const MemberAttr = struct { name: []const u8, attrs: []const ParsedAttr };
    var methods_with_attrs = std.ArrayListUnmanaged(MemberAttr).empty;
    defer methods_with_attrs.deinit(self.allocator);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .class_method or member.tag == .static_class_method or member.tag == .interface_method) {
            const mattrs = try extractAttributes(self, member.main_token, AttrTarget.method);
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
        const mname_idx = try self.addConstant(.{ .string = Value.String.borrowed(ma.name) });
        try self.emitU16(mname_idx);
        try emitAttributeData(self, ma.attrs);
    }
    for (methods_with_attrs.items) |ma| freeAttrSlice(self.allocator, ma.attrs);

    // case attributes - emit attrs for each enum case that has any.
    // these end up as constant_attributes so ReflectionClassConstant of an
    // enum case can find them
    const CaseAttr = struct { name: []const u8, attrs: []const ParsedAttr };
    var cases_with_attrs = std.ArrayListUnmanaged(CaseAttr).empty;
    defer cases_with_attrs.deinit(self.allocator);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .enum_case) {
            const cattrs = try extractAttributes(self, member.main_token, AttrTarget.class_constant);
            if (cattrs.len > 0) {
                try cases_with_attrs.append(self.allocator, .{
                    .name = self.ast.tokenSlice(member.main_token),
                    .attrs = cattrs,
                });
            }
        }
    }
    try self.emitByte(@intCast(cases_with_attrs.items.len));
    for (cases_with_attrs.items) |ca| {
        const cname_idx2 = try self.addConstant(.{ .string = Value.String.borrowed(ca.name) });
        try self.emitU16(cname_idx2);
        try emitAttributeData(self, ca.attrs);
    }
    for (cases_with_attrs.items) |ca| freeAttrSlice(self.allocator, ca.attrs);

    // enum constant names (not cases - actual const decls)
    var enum_const_count: u8 = 0;
    for (members) |member_idx| {
        if (self.ast.nodes[member_idx].tag == .const_decl) enum_const_count += 1;
    }
    try self.emitByte(enum_const_count);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .const_decl) {
            const ec_name = self.ast.tokenSlice(member.main_token);
            const ec_idx = try self.addConstant(.{ .string = Value.String.borrowed(ec_name) });
            try self.emitU16(ec_idx);
            try self.emitU16(try docCommentConst(self, member.main_token));
            try self.emitByte(@intCast(member.data.rhs & 0x13)); // bits 0-1 visibility, bit 4 final
            try self.emitU16(try propertyTypeConst(self, member.data.rhs));
        }
    }

    const cname_idx = try self.addConstant(.{ .string = Value.String.borrowed(enum_name) });
    try self.emitOp(.enter_class_scope);
    try self.emitU16(cname_idx);
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (member.tag == .const_decl) try emitClassConstant(self, enum_name, cname_idx, member);
    }
    try self.emitOp(.leave_class_scope);
}

fn compileClassMethodBody(self: *Compiler, class_name: []const u8, member: Ast.Node) Error!void {
    const prev_class = self.current_class;
    self.current_class = class_name;
    defer self.current_class = prev_class;

    const method_name = self.ast.tokenSlice(member.main_token);
    const full_name = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ class_name, method_name });
    try self.string_allocs.append(self.allocator, full_name);

    const param_nodes = self.ast.extraSlice(member.data.lhs);
    try checkParams(self, full_name, member.main_token, param_nodes, try extractReturnType(self, member.data.lhs, @intCast(param_nodes.len)), (member.data.rhs & (1 << 27)) != 0);
    var handed_over = false;
    const param_names = try self.allocator.alloc([]const u8, param_nodes.len);
    errdefer if (!handed_over) self.allocator.free(param_names);
    const ref_flags = try self.allocator.alloc(bool, param_nodes.len);
    errdefer if (!handed_over) self.allocator.free(ref_flags);
    for (param_nodes, 0..) |p, i| {
        const pnode = self.ast.nodes[p];
        param_names[i] = self.ast.tokenSlice(pnode.main_token);
        ref_flags[i] = (pnode.data.rhs & 2) != 0;
    }

    var defaults = std.ArrayListUnmanaged(Value).empty;
    defer defaults.deinit(self.allocator);
    var is_variadic = false;
    for (param_nodes) |p| {
        const pnode = self.ast.nodes[p];
        if ((pnode.data.rhs & 1) != 0) {
            is_variadic = true;
            try defaults.append(self.allocator, .null);
        } else if (pnode.data.lhs != 0) {
            try defaults.append(self.allocator, try paramDefaultValue(self, pnode));
        } else {
            try defaults.append(self.allocator, .null);
        }
    }
    const required = requiredParamCount(self.ast, param_nodes);
    const defaults_owned = try self.allocator.alloc(Value, defaults.items.len);
    @memcpy(defaults_owned, defaults.items);
    errdefer if (!handed_over) compiler.freeDefaults(self.allocator, defaults_owned);

    // bit 29 = generator, bit 28 = is_final, bit 27 = returns_ref
    const method_gen = (member.data.rhs & (1 << 29)) != 0;
    const method_returns_ref = (member.data.rhs & (1 << 27)) != 0;

    var sub = Compiler{
        .ast = self.ast,
        .diagnostic = self.diagnostic,
        .declared_return = try extractReturnType(self, member.data.lhs, @intCast(param_nodes.len)),
        .chunk = .{},
        .functions = .empty,
        .string_allocs = .empty,
        .allocator = self.allocator,
        .scope_depth = self.scope_depth + 1,
        .loop_start = null,
        .break_jumps = .empty,
        .continue_jumps = .empty,
        .is_generator = method_gen,
        .returns_ref = method_returns_ref,
        .closure_count = self.closure_count,
        .cond_fn_count = self.cond_fn_count,
        .hoistable = false,
        .file_path = self.file_path,
        .file_dir = self.file_dir,
        .namespace = self.namespace,
        .use_aliases = self.use_aliases,
        .use_fn_aliases = self.use_fn_aliases,
        .use_const_aliases = self.use_const_aliases,
        .current_class = class_name,
        .current_function = method_name,
        .in_trait = self.in_trait,
    };
    defer sub.deinitScratch();
    errdefer sub.discardOutput();

    // slot 0 = $this for instance methods
    if (member.tag != .static_class_method) {
        _ = sub.getOrCreateSlot("$this");
    }
    for (param_nodes, 0..) |_, i| {
        if (ref_flags[i]) continue;
        _ = sub.getOrCreateSlot(param_names[i]);
    }
    const call_attrs = try callAttributes(self, member.main_token, try extractReturnType(self, member.data.lhs, @intCast(param_nodes.len)), "method");
    if (call_attrs.deprecated != null and !method_gen) try sub.emitOp(.check_deprecated);
    if (call_attrs.no_discard != null and !method_gen) try sub.emitOp(.check_nodiscard);

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
                const prop_idx = try sub.addConstant(.{ .string = Value.String.borrowed(param_name) });
                try sub.emitOp(.set_prop);
                try sub.emitU16(prop_idx);
                try sub.emitOp(.pop);
            }
        }
    }

    // mask out visibility (bits 30-31), generator (bit 29), is_final (bit 28),
    // returns_ref (bit 27)
    const body_idx = member.data.rhs & 0x07FFFFFF;
    try sub.compileNode(body_idx);
    try sub.patchGotos();
    try sub.emitOp(.op_null);
    try sub.emitOp(if (method_gen) .generator_return else .return_val);

    self.closure_count = sub.closure_count;
    self.cond_fn_count = sub.cond_fn_count;
    try self.functions.ensureUnusedCapacity(self.allocator, 1);
    const slot_names = try sub.buildSlotNames();
    const local_count = sub.next_slot;

    const method_lo = !method_gen and !is_variadic and !hasRefParams(ref_flags) and !needsVarSync(&sub.chunk);

    self.functions.appendAssumeCapacity(.{
        .name = full_name,
        .arity = @intCast(param_nodes.len),
        .required_params = required,
        .is_variadic = is_variadic,
        .is_generator = method_gen,
        .returns_ref = method_returns_ref,
        .is_static = member.tag == .static_class_method,
        .method_visibility = @intCast((member.data.rhs >> 30) & 0x3),
        .is_final = ((member.data.rhs >> 28) & 1) != 0,
        .no_discard = call_attrs.no_discard,
        .deprecated = call_attrs.deprecated,
        .locals_only = method_lo,
        .params = param_names[0..param_nodes.len],
        .defaults = defaults_owned,
        .ref_params = ref_flags,
        .chunk = sub.takeChunk(),
        .static_vars = try sub.takeStaticVars(),
        .local_count = local_count,
        .slot_names = slot_names,
        .file_path = self.file_path,
        .start_line = lineForToken(self, member.main_token),
        .end_line = endLineForBlockStartingAt(self, member.main_token),
        .doc_comment = docCommentForToken(self, member.main_token),
    });
    handed_over = true;

    const param_types = try extractParamTypes(self, param_nodes);
    const return_type = try extractMethodReturnType(self, member, @intCast(param_nodes.len));
    if (param_types.len > 0 or return_type.len > 0) {
        try self.type_hints.append(self.allocator, .{ .name = full_name, .param_types = param_types, .return_type = return_type });
    }
    if (self.functions.items.len > 0) {
        self.functions.items[self.functions.items.len - 1].has_param_types = param_types.len > 0;
        if (return_type.len > 0) self.functions.items[self.functions.items.len - 1].return_type_kind = returnTypeKind(return_type);
    }

    try self.adopt(&sub);
    try checkMagicMethod(self, class_name, member, .{
        .params = param_nodes,
        .param_types = param_types,
        .return_type = try extractReturnType(self, member.data.lhs, @intCast(param_nodes.len)),
        .is_static = member.tag == .static_class_method,
        .visibility = @intCast((member.data.rhs >> 30) & 0x3),
    });
}

const MagicMethod = struct {
    params: []const u32,
    param_types: []const []const u8,
    // as declared: __toString's implicit string is not part of it
    return_type: []const u8,
    is_static: bool,
    visibility: u8,
};

// php's zend_check_magic_method_implementation: the arity, static-ness,
// visibility and types php requires of each magic method, checked as the
// method compiles. only visibility is a warning, the rest end compilation
fn checkMagicMethod(self: *Compiler, class_name: []const u8, member: Ast.Node, m: MagicMethod) Error!void {
    const name = self.ast.tokenSlice(member.main_token);
    if (name.len < 2 or name[0] != '_' or name[1] != '_') return;
    const Rule = struct {
        args: ?u32 = null,
        static: ?bool = false,
        public: bool = true,
        no_return_type: bool = false,
        // the type php requires of each parameter and of the return, when declared
        arg_types: []const u32 = &.{},
        returns: u32 = 0,
    };
    const S = php_types.STRING;
    const A = php_types.ARRAY;
    const rules = std.StaticStringMap(Rule).initComptime(.{
        .{ "__construct", Rule{ .public = false, .no_return_type = true } },
        .{ "__destruct", Rule{ .args = 0, .public = false, .no_return_type = true } },
        .{ "__clone", Rule{ .args = 0, .public = false, .returns = php_types.VOID } },
        .{ "__get", Rule{ .args = 1, .arg_types = &.{S} } },
        .{ "__set", Rule{ .args = 2, .arg_types = &.{S}, .returns = php_types.VOID } },
        .{ "__unset", Rule{ .args = 1, .arg_types = &.{S}, .returns = php_types.VOID } },
        .{ "__isset", Rule{ .args = 1, .arg_types = &.{S}, .returns = php_types.BOOL } },
        .{ "__call", Rule{ .args = 2, .arg_types = &.{ S, A } } },
        .{ "__callstatic", Rule{ .args = 2, .static = true, .arg_types = &.{ S, A } } },
        .{ "__tostring", Rule{ .args = 0, .returns = S } },
        .{ "__debuginfo", Rule{ .args = 0, .returns = A | php_types.NULL } },
        .{ "__serialize", Rule{ .args = 0, .returns = A } },
        .{ "__unserialize", Rule{ .args = 1, .arg_types = &.{A}, .returns = php_types.VOID } },
        .{ "__set_state", Rule{ .args = 1, .static = true, .arg_types = &.{A}, .returns = php_types.OBJECT } },
        .{ "__invoke", Rule{ .static = false } },
        .{ "__sleep", Rule{ .args = 0, .returns = A } },
        .{ "__wakeup", Rule{ .args = 0, .returns = php_types.VOID } },
    });
    var lower_buf: [16]u8 = undefined;
    if (name.len > lower_buf.len) return;
    const rule = rules.get(std.ascii.lowerString(&lower_buf, name)) orelse return;
    const class = class_names.display(class_name);
    const token = member.main_token;

    var arg_count: u32 = 0;
    for (m.params) |p| {
        if ((self.ast.nodes[p].data.rhs & 1) == 0) arg_count += 1;
    }
    if (rule.args) |want| {
        if (arg_count != want) {
            if (want == 0) return self.failFmt(token, "Method {s}::{s}() cannot take arguments", .{ class, name });
            if (want == 1) return self.failFmt(token, "Method {s}::{s}() must take exactly 1 argument", .{ class, name });
            return self.failFmt(token, "Method {s}::{s}() must take exactly {d} arguments", .{ class, name, want });
        }
        for (m.params[0..want]) |p| {
            if ((self.ast.nodes[p].data.rhs & 2) != 0) return self.failFmt(token, "Method {s}::{s}() cannot take arguments by reference", .{ class, name });
        }
    }
    if (rule.static) |must_be_static| {
        if (must_be_static and !m.is_static) return self.failFmt(token, "Method {s}::{s}() must be static", .{ class, name });
        if (!must_be_static and m.is_static) return self.failFmt(token, "Method {s}::{s}() cannot be static", .{ class, name });
    }
    if (rule.public and m.visibility != 0) {
        try self.warn(token, 2, "The magic method {s}::{s}() must have public visibility", .{ class, name });
    }
    for (rule.arg_types, 0..) |want, i| {
        if (i >= m.param_types.len or m.param_types[i].len == 0) continue;
        const declared = php_types.parse(self.allocator, m.param_types[i], class_name, null) catch return error.OutOfMemory;
        defer declared.deinit(self.allocator);
        if (declared.mask & want != 0) continue;
        const pname = self.ast.tokenSlice(self.ast.nodes[m.params[i]].main_token);
        const required = php_types.format(self.allocator, .{ .mask = want }) catch return error.OutOfMemory;
        defer self.allocator.free(required);
        return self.failFmt(token, "{s}::{s}(): Parameter #{d} (${s}) must be of type {s} when declared", .{ class, name, i + 1, if (pname.len > 0 and pname[0] == '$') pname[1..] else pname, required });
    }
    if (rule.no_return_type and m.return_type.len > 0) {
        return self.failFmt(token, "Method {s}::{s}() cannot declare a return type", .{ class, name });
    }
    if (rule.returns != 0 and m.return_type.len > 0) {
        const declared = php_types.parse(self.allocator, m.return_type, class_name, null) catch return error.OutOfMemory;
        defer declared.deinit(self.allocator);
        if (declared.mask & php_types.NEVER != 0) return;
        var complex = declared.names.len > 0 or declared.intersections.len > 0;
        var extra = declared.mask & ~rule.returns;
        if (extra & php_types.STATIC != 0) {
            extra &= ~php_types.STATIC;
            complex = true;
        }
        if (extra != 0 or (complex and rule.returns != php_types.OBJECT)) {
            const required = php_types.format(self.allocator, .{ .mask = rule.returns }) catch return error.OutOfMemory;
            defer self.allocator.free(required);
            return self.failFmt(token, "{s}::{s}(): Return type must be {s} when declared", .{ class, name, required });
        }
    }
}

// compiles the non-literal instance defaults into the class's hidden
// initializer; returns whether there were any
fn isDeferredDefault(ast: *const Ast, member: Ast.Node) bool {
    if (member.tag != .class_property and member.tag != .static_class_property) return false;
    return member.data.lhs != 0 and !defaultExprIsLiteral(ast, member.data.lhs);
}

// a class constant's value: a constant expression folded while compiling
// is set now; any other waits for the constant's first access, as php
// evaluates it, through its own initializer function
fn emitClassConstant(self: *Compiler, class_name: []const u8, class_idx: u16, member: Ast.Node) Error!void {
    const const_name = self.ast.tokenSlice(member.main_token);
    const cprop_idx = try self.addConstant(.{ .string = Value.String.borrowed(const_name) });
    if (foldsAtCompileTime(self.ast, member.data.lhs)) {
        try self.compileNode(member.data.lhs);
        // an int for a constant typed float without int is a float, as php
        // converts it while compiling
        const type_extra = member.data.rhs >> 16;
        if (type_extra != 0 and foldedDefault(self, member.data.lhs) == .int) {
            const text = try buildTypeString(self, self.ast.extra_data[type_extra - 1], self.ast.extra_data[type_extra]);
            const t = php_types.parse(self.allocator, text, class_name, null) catch return error.OutOfMemory;
            defer t.deinit(self.allocator);
            if (t.mask & php_types.DOUBLE != 0 and t.mask & php_types.LONG == 0) try self.emitOp(.cast_float);
        }
        try self.emitOp(.set_class_const);
        try self.emitU16(class_idx);
        try self.emitU16(cprop_idx);
        try self.emitOp(.pop);
        return;
    }
    try compileConstInitializer(self, class_name, member);
    try self.emitOp(.defer_class_const);
    try self.emitU16(class_idx);
    try self.emitU16(cprop_idx);
}

fn compileConstInitializer(self: *Compiler, class_name: []const u8, member: Ast.Node) Error!void {
    const name = try @import("bytecode.zig").constInitializerName(self.allocator, class_name, self.ast.tokenSlice(member.main_token));
    try self.string_allocs.append(self.allocator, name);
    try compileInitializer(self, name, .{ .class = class_name }, member.data.lhs, member.main_token);
}

// a static function named `name` returning the expression's value, run in
// the class's scope (none for "") with self and parent resolved then, the
// way php evaluates a constant expression it couldn't fold
const scope_param = "\x00scope";

const InitializerScope = union(enum) {
    // a class known where the expression is written
    class: []const u8,
    // the class passed as the initializer's argument when it runs (none
    // for ""), for an expression whose scope depends on where it is read
    argument,
};

fn compileInitializer(self: *Compiler, name: []const u8, scope: InitializerScope, expr: u32, at: u32) Error!void {
    const class_name = switch (scope) {
        .class => |c| c,
        .argument => self.current_class,
    };
    var sub = Compiler{
        .ast = self.ast,
        .diagnostic = self.diagnostic,
        .chunk = .{},
        .functions = .empty,
        .string_allocs = .empty,
        .allocator = self.allocator,
        .scope_depth = self.scope_depth + 1,
        .loop_start = null,
        .break_jumps = .empty,
        .continue_jumps = .empty,
        .closure_count = self.closure_count,
        .cond_fn_count = self.cond_fn_count,
        .hoistable = false,
        .file_path = self.file_path,
        .file_dir = self.file_dir,
        .namespace = self.namespace,
        .use_aliases = self.use_aliases,
        .use_fn_aliases = self.use_fn_aliases,
        .use_const_aliases = self.use_const_aliases,
        .current_class = class_name,
        .current_parent = self.current_parent,
        .current_function = self.current_function,
        .in_trait = self.in_trait,
        .relative_const_classes = true,
    };
    defer sub.deinitScratch();
    errdefer sub.discardOutput();
    const scoped = scope == .argument or class_name.len > 0;
    switch (scope) {
        .argument => {
            _ = sub.getOrCreateSlot(scope_param);
            try sub.emitOp(.enter_class_scope_arg);
        },
        .class => if (scoped) {
            const cname_idx = try sub.addConstant(.{ .string = Value.String.borrowed(class_name) });
            try sub.emitOp(.enter_class_scope);
            try sub.emitU16(cname_idx);
        },
    }
    try sub.compileNode(expr);
    if (scoped) try sub.emitOp(.leave_class_scope);
    try sub.emitOp(.return_val);
    self.closure_count = sub.closure_count;
    self.cond_fn_count = sub.cond_fn_count;
    try self.functions.ensureUnusedCapacity(self.allocator, 1);
    const slot_names = try sub.buildSlotNames();
    const local_count = sub.next_slot;
    self.functions.appendAssumeCapacity(.{
        .name = name,
        .arity = if (scope == .argument) 1 else 0,
        .required_params = if (scope == .argument) 1 else 0,
        .is_static = true,
        .params = if (scope == .argument) try self.allocator.dupe([]const u8, &.{scope_param}) else &.{},
        .defaults = &.{},
        .ref_params = &.{},
        .chunk = sub.takeChunk(),
        .static_vars = try sub.takeStaticVars(),
        .local_count = local_count,
        .slot_names = slot_names,
        .file_path = self.file_path,
        .start_line = lineForToken(self, at),
        .end_line = lineForToken(self, at),
    });
    try self.adopt(&sub);
}

fn compileDeferredPropDefaults(self: *Compiler, class_name: []const u8, members: []const u32) Error!bool {
    var any = false;
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (isDeferredDefault(self.ast, member)) any = true;
    }
    if (!any) return false;

    const name = try @import("bytecode.zig").propDefaultsInitializerName(self.allocator, class_name);
    try self.string_allocs.append(self.allocator, name);

    var sub = Compiler{
        .ast = self.ast,
        .diagnostic = self.diagnostic,
        .chunk = .{},
        .functions = .empty,
        .string_allocs = .empty,
        .allocator = self.allocator,
        .scope_depth = self.scope_depth + 1,
        .loop_start = null,
        .break_jumps = .empty,
        .continue_jumps = .empty,
        .closure_count = self.closure_count,
        .cond_fn_count = self.cond_fn_count,
        .hoistable = false,
        .file_path = self.file_path,
        .file_dir = self.file_dir,
        .namespace = self.namespace,
        .use_aliases = self.use_aliases,
        .use_fn_aliases = self.use_fn_aliases,
        .use_const_aliases = self.use_const_aliases,
        .current_class = class_name,
        .current_parent = self.current_parent,
        .current_function = name,
        .in_trait = self.in_trait,
    };
    defer sub.deinitScratch();
    errdefer sub.discardOutput();

    const cname_idx = try sub.addConstant(.{ .string = Value.String.borrowed(class_name) });
    var first_tok: u32 = 0;
    for (members) |member_idx| {
        const member = self.ast.nodes[member_idx];
        if (!isDeferredDefault(self.ast, member)) continue;
        if (first_tok == 0) first_tok = member.main_token;
        try sub.compileNode(member.data.lhs);
        var p_name = self.ast.tokenSlice(member.main_token);
        if (p_name.len > 0 and p_name[0] == '$') p_name = p_name[1..];
        const p_idx = try sub.addConstant(.{ .string = Value.String.borrowed(p_name) });
        try sub.emitOp(if (member.tag == .static_class_property) .set_static_prop_default else .set_prop_default);
        try sub.emitU16(cname_idx);
        try sub.emitU16(p_idx);
        try sub.emitOp(.pop);
    }
    try sub.emitOp(.op_null);
    try sub.emitOp(.return_val);

    self.closure_count = sub.closure_count;
    self.cond_fn_count = sub.cond_fn_count;
    try self.functions.ensureUnusedCapacity(self.allocator, 1);
    const slot_names = try sub.buildSlotNames();
    const local_count = sub.next_slot;

    self.functions.appendAssumeCapacity(.{
        .name = name,
        .arity = 0,
        .required_params = 0,
        .is_static = true,
        .params = &.{},
        .defaults = &.{},
        .ref_params = &.{},
        .chunk = sub.takeChunk(),
        .static_vars = try sub.takeStaticVars(),
        .local_count = local_count,
        .slot_names = slot_names,
        .file_path = self.file_path,
        .start_line = lineForToken(self, first_tok),
        .end_line = lineForToken(self, first_tok),
    });

    try self.adopt(&sub);
    return true;
}

fn propertyVirtualFlag(self: *Compiler, member: Ast.Node) u8 {
    return if (member.tag == .class_property_hooks and (self.ast.extra_data[member.data.lhs + 4] & 32) == 0) 2 else 0;
}

const HookKind = enum { get, set };

fn compilePropertyHook(self: *Compiler, class_name: []const u8, prop_name: []const u8, body_idx: u32, kind: HookKind, hook_flags: u32, set_param_tok: u32, member: Ast.Node) Error!void {
    const is_short = (hook_flags & 1) != 0;
    const is_generator = (hook_flags & 2) != 0;
    const suffix = if (kind == .get) "$hook_get" else "$hook_set";
    const full_name = try std.fmt.allocPrint(self.allocator, "{s}::{s}{s}", .{ class_name, prop_name, suffix });
    try self.string_allocs.append(self.allocator, full_name);
    // what php calls the hook: "$prop::get", shown as "Class::$prop::get"
    const php_name = try std.fmt.allocPrint(self.allocator, "${s}::{s}", .{ prop_name, if (kind == .get) "get" else "set" });
    try self.string_allocs.append(self.allocator, php_name);
    const shown_name = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ class_name, php_name });
    try self.string_allocs.append(self.allocator, shown_name);

    const type_extra = member.data.rhs >> 16;
    const prop_type = if (type_extra != 0)
        try buildTypeString(self, self.ast.extra_data[type_extra - 1], self.ast.extra_data[type_extra])
    else
        "";
    const ext = member.data.lhs;
    const param_types = try self.allocator.alloc([]const u8, if (kind == .set) 1 else 0);
    if (kind == .set) {
        const start = self.ast.extra_data[ext + 6];
        const end = self.ast.extra_data[ext + 7];
        param_types[0] = if (end > start) try buildTypeString(self, start, end) else prop_type;
    }
    try self.type_hints.append(self.allocator, .{ .name = full_name, .param_types = param_types, .return_type = if (kind == .get) prop_type else "void" });

    var param_names_list = std.ArrayListUnmanaged([]const u8).empty;
    defer param_names_list.deinit(self.allocator);
    if (kind == .set) {
        const pname = if (set_param_tok != 0) self.ast.tokenSlice(set_param_tok) else "$value";
        try param_names_list.append(self.allocator, pname);
    }
    var handed_over = false;
    const param_names = try self.allocator.alloc([]const u8, param_names_list.items.len);
    errdefer if (!handed_over) self.allocator.free(param_names);
    @memcpy(param_names, param_names_list.items);
    const ref_flags = try self.allocator.alloc(bool, param_names.len);
    errdefer if (!handed_over and ref_flags.len > 0) self.allocator.free(ref_flags);
    @memset(ref_flags, false);

    const defaults = try self.allocator.alloc(Value, param_names.len);
    errdefer if (!handed_over) compiler.freeDefaults(self.allocator, defaults);
    @memset(defaults, .null);

    var sub = Compiler{
        .ast = self.ast,
        .diagnostic = self.diagnostic,
        .chunk = .{},
        .functions = .empty,
        .string_allocs = .empty,
        .allocator = self.allocator,
        .scope_depth = self.scope_depth + 1,
        .loop_start = null,
        .break_jumps = .empty,
        .continue_jumps = .empty,
        .closure_count = self.closure_count,
        .cond_fn_count = self.cond_fn_count,
        .hoistable = false,
        .file_path = self.file_path,
        .file_dir = self.file_dir,
        .namespace = self.namespace,
        .use_aliases = self.use_aliases,
        .use_fn_aliases = self.use_fn_aliases,
        .use_const_aliases = self.use_const_aliases,
        .is_generator = is_generator,
        .returns_ref = (hook_flags & 4) != 0,
        .current_class = class_name,
        .current_function = php_name,
        .hook_property = prop_name,
        .hook_is_set = kind == .set,
    };
    defer sub.deinitScratch();
    errdefer sub.discardOutput();

    _ = sub.getOrCreateSlot("$this");
    for (param_names) |pn| _ = sub.getOrCreateSlot(pn);

    if (is_short) {
        if (kind == .get) {
            if (!(sub.returns_ref and !is_generator and try sub.tryCompileRefReturn(body_idx))) {
                try sub.compileNode(body_idx);
                try sub.emitOp(if (is_generator) .generator_return else .return_val);
            }
        } else {
            // set short form: $this->prop = expr (raw write since hook guard is active)
            const this_slot = sub.local_slots.get("$this") orelse 0;
            try sub.emitOp(.get_local);
            try sub.emitU16(this_slot);
            try sub.compileNode(body_idx);
            const prop_idx = try sub.addConstant(.{ .string = Value.String.borrowed(prop_name) });
            try sub.emitOp(.set_prop);
            try sub.emitU16(prop_idx);
            try sub.emitOp(.pop);
        }
    } else if (body_idx != 0) {
        try sub.compileNode(body_idx);
    }
    try sub.patchGotos();
    try sub.emitOp(.op_null);
    try sub.emitOp(if (is_generator) .generator_return else .return_val);

    self.closure_count = sub.closure_count;
    self.cond_fn_count = sub.cond_fn_count;
    try self.functions.ensureUnusedCapacity(self.allocator, 1);
    const slot_names = try sub.buildSlotNames();
    const local_count = sub.next_slot;

    const method_lo = !is_generator and !needsVarSync(&sub.chunk);

    self.functions.appendAssumeCapacity(.{
        .name = full_name,
        .display_name = shown_name,
        .arity = @intCast(param_names.len),
        .required_params = @intCast(param_names.len),
        .params = param_names,
        .defaults = defaults,
        .ref_params = ref_flags,
        .chunk = sub.takeChunk(),
        .static_vars = try sub.takeStaticVars(),
        .is_generator = is_generator,
        .locals_only = method_lo,
        .local_count = local_count,
        .slot_names = slot_names,
        .file_path = self.file_path,
        .start_line = if (body_idx != 0) lineForToken(self, self.ast.nodes[body_idx].main_token) else 0,
        .returns_ref = (hook_flags & 4) != 0,
        .has_param_types = param_types.len > 0 and param_types[0].len > 0,
    });
    handed_over = true;

    try self.adopt(&sub);
}

fn compileInterfaceMethodStub(self: *Compiler, owner_name: []const u8, member: Ast.Node) Error!void {
    const method_name = self.ast.tokenSlice(member.main_token);
    const full_name = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ owner_name, method_name });
    try self.string_allocs.append(self.allocator, full_name);

    const param_nodes = self.ast.extraSlice(member.data.lhs);
    try checkParams(self, full_name, member.main_token, param_nodes, try extractReturnType(self, member.data.lhs, @intCast(param_nodes.len)), (member.data.rhs >> 31) & 1 != 0);
    const param_names = try self.allocator.alloc([]const u8, param_nodes.len);
    const ref_flags = try self.allocator.alloc(bool, param_nodes.len);
    for (param_nodes, 0..) |p, i| {
        const pnode = self.ast.nodes[p];
        param_names[i] = self.ast.tokenSlice(pnode.main_token);
        ref_flags[i] = (pnode.data.rhs & 2) != 0;
    }

    var defaults = std.ArrayListUnmanaged(Value).empty;
    defer defaults.deinit(self.allocator);
    var is_variadic = false;
    for (param_nodes) |p| {
        const pnode = self.ast.nodes[p];
        if ((pnode.data.rhs & 1) != 0) {
            is_variadic = true;
            try defaults.append(self.allocator, .null);
        } else if (pnode.data.lhs != 0) {
            try defaults.append(self.allocator, try paramDefaultValue(self, pnode));
        } else {
            try defaults.append(self.allocator, .null);
        }
    }
    const required = requiredParamCount(self.ast, param_nodes);
    const defaults_owned = try self.allocator.alloc(Value, defaults.items.len);
    @memcpy(defaults_owned, defaults.items);

    try self.functions.append(self.allocator, .{
        .name = full_name,
        .arity = @intCast(param_nodes.len),
        .required_params = required,
        .is_variadic = is_variadic,
        .is_static = (member.data.rhs >> 30) & 1 != 0,
        .returns_ref = (member.data.rhs >> 31) & 1 != 0,
        .params = param_names[0..param_nodes.len],
        .defaults = defaults_owned,
        .ref_params = ref_flags,
        .file_path = self.file_path,
        .start_line = lineForToken(self, member.main_token),
    });

    const param_types = try extractParamTypes(self, param_nodes);
    const return_type = try extractMethodReturnType(self, member, @intCast(param_nodes.len));
    if (param_types.len > 0 or return_type.len > 0) {
        try self.type_hints.append(self.allocator, .{ .name = full_name, .param_types = param_types, .return_type = return_type });
    }
    if (self.functions.items.len > 0) {
        self.functions.items[self.functions.items.len - 1].has_param_types = param_types.len > 0;
        if (return_type.len > 0) self.functions.items[self.functions.items.len - 1].return_type_kind = returnTypeKind(return_type);
    }
    try checkMagicMethod(self, owner_name, member, .{
        .params = param_nodes,
        .param_types = param_types,
        .return_type = try extractReturnType(self, member.data.lhs, @intCast(param_nodes.len)),
        .is_static = (member.data.rhs >> 30) & 1 != 0,
        .visibility = @intCast((member.data.rhs >> 28) & 0x3),
    });
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
        if (b == @intFromEnum(OpCode.concat_assign) or b == @intFromEnum(OpCode.get_global) or b == @intFromEnum(OpCode.get_static) or b == @intFromEnum(OpCode.closure_bind_ref))
            return true;
        i += opcodeWidth(b);
    }
    return false;
}

fn hasOp(chunk: *const Chunk, op: OpCode) bool {
    var i: usize = 0;
    const code = chunk.code.items;
    while (i < code.len) {
        if (code[i] == @intFromEnum(op)) return true;
        i += opcodeWidth(code[i]);
    }
    return false;
}

fn opcodeWidth(b: u8) usize {
    return OpCode.widthFromByte(b);
}

// php names a closure after where it is written: `{closure:<scope>:<line>}`,
// the scope being the enclosing closure's name, `Class::method()`, `func()`,
// or the file at the top level
fn closureDisplayName(self: *Compiler, line: u32) ![]const u8 {
    const f = self.current_function;
    const name = if (std.mem.startsWith(u8, f, "{closure:"))
        try std.fmt.allocPrint(self.allocator, "{{closure:{s}:{d}}}", .{ f, line })
    else if (f.len > 0 and self.current_class.len > 0)
        try std.fmt.allocPrint(self.allocator, "{{closure:{s}::{s}():{d}}}", .{ self.current_class, f, line })
    else if (f.len > 0)
        try std.fmt.allocPrint(self.allocator, "{{closure:{s}():{d}}}", .{ f, line })
    else
        try std.fmt.allocPrint(self.allocator, "{{closure:{s}:{d}}}", .{ self.file_path, line });
    try self.string_allocs.append(self.allocator, name);
    return name;
}

// self, parent, and static name the class being compiled, never one to
// extend or implement; php rejects them before anything runs
fn rejectReservedParent(self: *Compiler, n: Ast.Node, comptime kind: []const u8) !void {
    var token = n.main_token;
    if (n.tag == .qualified_name) {
        const parts = self.ast.extraSlice(n.data.lhs);
        if (parts.len != 1 or n.data.rhs != 0) return;
        token = parts[0];
    }
    const name = self.ast.tokenSlice(token);
    for ([_][]const u8{ "self", "parent", "static" }) |reserved| {
        if (std.ascii.eqlIgnoreCase(name, reserved)) return self.failFmt(token, "Cannot use \"{s}\" as " ++ kind ++ " name, as it is reserved", .{name});
    }
}
