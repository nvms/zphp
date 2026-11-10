// the string forms of the reflectors (__toString), ported from php's
// ext/reflection/php_reflection.c: _class_string, _function_string,
// _parameter_string, _property_string, _class_const_string,
// _enum_case_string and the attribute's. they read the runtime's tables
// directly and create no objects, so printing a reflector moves no object
// handle a later var_dump shows

const std = @import("std");
const class_names = @import("../runtime/class_names.zig");
const reflection = @import("reflection.zig");
const extensions = @import("extensions_generated.zig");
const native_params = @import("native_params.zig");
const interface_signatures = @import("interface_signatures_generated.zig");
const object_properties = @import("../runtime/object_properties.zig");
const bytecode = @import("../pipeline/bytecode.zig");
const vm_mod = @import("../runtime/vm.zig");
const value_mod = @import("../runtime/value.zig");
const gcvt = @import("formatted_print.zig").gcvt;
const Value = value_mod.Value;
const PhpObject = value_mod.PhpObject;
const PhpArray = value_mod.PhpArray;
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const ObjFunction = bytecode.ObjFunction;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const Allocator = std.mem.Allocator;

const RuntimeError = error{ RuntimeError, OutOfMemory };

pub fn register(vm: *VM, a: Allocator) !void {
    const natives = .{
        .{ "ReflectionClass", classToString },
        .{ "ReflectionFunction", functionToString },
        .{ "ReflectionMethod", methodToString },
        .{ "ReflectionParameter", parameterToString },
        .{ "ReflectionProperty", propertyToString },
        .{ "ReflectionClassConstant", classConstantToString },
        .{ "ReflectionAttribute", attributeToString },
    };
    inline for (natives) |n| {
        if (vm.classes.getPtr(n[0])) |def| try def.methods.put(a, "__toString", .{ .name = "__toString", .arity = 0 });
        try vm.native_fns.put(a, n[0] ++ "::__toString", n[1]);
    }
}

const Writer = struct {
    ctx: *NativeContext,
    buf: std.ArrayListUnmanaged(u8) = .empty,
    // the class whose defaults are printed, which `self::` names
    self_class: ?[]const u8 = null,

    fn str(w: *Writer, s: []const u8) !void {
        try w.buf.appendSlice(w.ctx.allocator, s);
    }

    fn fmt(w: *Writer, comptime f: []const u8, args: anytype) !void {
        try w.buf.print(w.ctx.allocator, f, args);
    }

    fn deinit(w: *Writer) void {
        w.buf.deinit(w.ctx.allocator);
    }

    fn result(w: *Writer) !NativeResult {
        return NativeResult.copyString(w.ctx.allocator, w.buf.items);
    }
};

fn stringProp(obj: *PhpObject, name: []const u8) ?[]const u8 {
    const v = obj.get(name);
    return if (v == .string) v.string.bytes() else null;
}

fn boolProp(obj: *PhpObject, name: []const u8) bool {
    const v = obj.get(name);
    return v == .bool and v.bool;
}

// ---------------------------------------------------------------- values

// smart_str_append_double: zend_gcvt at the precision ini, ".0" added to a
// finite whole number when asked
fn appendDouble(w: *Writer, f: f64, zero_fraction: bool) !void {
    var tmp: [64]u8 = undefined;
    const text = gcvt(f, 14, '.', 'E', &tmp);
    try w.str(text);
    if (zero_fraction and std.math.isFinite(f) and std.mem.indexOfScalar(u8, text, '.') == null) try w.str(".0");
}

// smart_str_append_escaped
fn appendEscaped(w: *Writer, s: []const u8) !void {
    for (s) |c| {
        if (c < 32 or c == '\\' or c > 126) {
            try w.str("\\");
            switch (c) {
                '\n' => try w.str("n"),
                '\r' => try w.str("r"),
                '\t' => try w.str("t"),
                0x0c => try w.str("f"),
                0x0b => try w.str("v"),
                '\\' => try w.str("\\"),
                0x1b => try w.str("e"),
                else => try w.fmt("x{X:0>2}", .{c}),
            }
        } else try w.buf.append(w.ctx.allocator, c);
    }
}

fn constSentinel(s: []const u8) ?struct { class: []const u8, name: []const u8 } {
    if (s.len <= 4 or s[0] != 0 or s[1] != 'C' or s[2] != 'C' or s[3] != 0) return null;
    const rest = s[4..];
    const sep = std.mem.lastIndexOfScalar(u8, rest, 0) orelse return null;
    return .{ .class = rest[0..sep], .name = rest[sep + 1 ..] };
}

fn isLiteral(v: Value) bool {
    return switch (v) {
        .null, .bool, .int, .float => true,
        .string => |s| s.bytes().len == 0 or s.bytes()[0] != 0,
        else => false,
    };
}

fn isListArray(arr: *const PhpArray) bool {
    for (arr.entries.items, 0..) |entry, i| {
        if (entry.key != .int or entry.key.int != @as(i64, @intCast(i))) return false;
    }
    return true;
}

// format_default_value, with the constant expressions zphp keeps unevaluated
// written back the way zend_ast_export prints them
fn appendDefault(w: *Writer, v: Value) RuntimeError!void {
    if (v.isEmptyArrayDefault()) return w.str("[]");
    switch (v) {
        .null, .undef => try w.str("NULL"),
        .bool => |b| try w.str(if (b) "true" else "false"),
        .int => |i| try w.fmt("{d}", .{i}),
        .float => |f| try appendDouble(w, f, true),
        .string => |s| {
            const bytes = s.bytes();
            if (constSentinel(bytes)) |c| {
                // Foo::class is folded to the name when compiled
                if (c.class.len > 0 and std.ascii.eqlIgnoreCase(c.name, "class")) {
                    try w.str("'");
                    try appendEscaped(w, c.class);
                    return w.str("'");
                }
                if (c.class.len > 0) {
                    // the class it names is resolved when compiled, except
                    // self and parent, which it most likely was when it names
                    // the class or its parent
                    var written = c.class;
                    if (w.self_class) |sc| {
                        if (std.mem.eql(u8, sc, c.class)) {
                            written = "self";
                        } else if (w.ctx.vm.classes.get(sc)) |cls| if (cls.parent) |p| if (std.ascii.eqlIgnoreCase(p, c.class)) {
                            written = "parent";
                        };
                    }
                    try w.fmt("{s}::", .{written});
                }
                return w.str(c.name);
            }
            if (bytecode.newDefaultPtr(bytes)) |nd| {
                try w.fmt("new \\{s}(", .{nd.class_name});
                for (nd.args, 0..) |arg, i| {
                    if (i > 0) try w.str(", ");
                    try appendDefault(w, arg);
                }
                return w.str(")");
            }
            if (bytecode.deferredExprPtr(bytes)) |de| {
                // php folds an expression over literals when it compiles it
                if (isLiteral(de.lhs) and (de.op.isUnary() or isLiteral(de.rhs))) {
                    if (w.ctx.vm.resolveDefault(v)) |folded| {
                        if (isLiteral(folded)) return appendDefault(w, folded);
                    } else |_| {}
                }
                if (de.op.isUnary()) {
                    try w.str(switch (de.op) {
                        .neg => "-",
                        .bnot => "~",
                        else => "!",
                    });
                    return appendDefault(w, de.lhs);
                }
                try appendDefault(w, de.lhs);
                try w.str(switch (de.op) {
                    .bor => " | ",
                    .band => " & ",
                    .bxor => " ^ ",
                    .add => " + ",
                    .sub => " - ",
                    .mul => " * ",
                    .div => " / ",
                    .mod => " % ",
                    .shl => " << ",
                    .shr => " >> ",
                    .pow => " ** ",
                    .concat => " . ",
                    .neg, .bnot, .not => unreachable,
                });
                return appendDefault(w, de.rhs);
            }
            try w.str("'");
            try appendEscaped(w, bytes);
            try w.str("'");
        },
        .array => |arr| {
            const list = isListArray(arr);
            try w.str("[");
            for (arr.entries.items, 0..) |entry, i| {
                if (i > 0) try w.str(", ");
                if (!list) {
                    switch (entry.key) {
                        .int => |k| try w.fmt("{d}", .{k}),
                        .string => |k| {
                            if (constSentinel(k.bytes()) != null) {
                                try appendDefault(w, .{ .string = k });
                            } else {
                                try w.str("'");
                                try appendEscaped(w, k.bytes());
                                try w.str("'");
                            }
                        },
                    }
                    try w.str(" => ");
                }
                try appendDefault(w, if (entry.ref) |ref| ref.* else entry.value);
            }
            try w.str("]");
        },
        .object => |obj| {
            const cls = w.ctx.vm.classes.get(obj.class_name);
            if (cls != null and cls.?.is_enum) {
                try w.fmt("{s}::", .{obj.class_name});
                if (stringProp(obj, "name")) |n| try w.str(n);
                return;
            }
            try w.fmt("object({s})", .{obj.class_name});
        },
        else => try w.str("NULL"),
    }
}

// the text php's stub gave an internal parameter's default
fn appendNativeDefault(w: *Writer, p: native_params.Param) !void {
    if (p.default_constant.len > 0) return w.str(p.default_constant);
    switch (p.default) {
        .required, .unknown => try w.str("<default>"),
        .null => try w.str("null"),
        .bool => |b| try w.str(if (b) "true" else "false"),
        .int => |i| try w.fmt("{d}", .{i}),
        .float => |f| {
            if (f == @trunc(f) and @abs(f) < 1e15) try w.fmt("{d}.0", .{f}) else try w.fmt("{d}", .{f});
        },
        .string => |s| {
            try w.str("\"");
            for (s) |c| switch (c) {
                '"' => try w.str("\\\""),
                '\\' => try w.str("\\\\"),
                '\n' => try w.str("\\n"),
                '\r' => try w.str("\\r"),
                '\t' => try w.str("\\t"),
                0x0b => try w.str("\\v"),
                0x0c => try w.str("\\f"),
                '$' => try w.str("\\$"),
                else => if (c < 32 or c > 126) try w.fmt("\\x{x:0>2}", .{c}) else try w.buf.append(w.ctx.allocator, c),
            };
            try w.str("\"");
        },
        .empty_array => try w.str("[]"),
        .class_constant => |c| try w.fmt("{s}::{s}", .{ c.class, c.name }),
    }
}

// zend_type_to_string of a declared type as zphp stores it, the way the
// type reflectors print it: self resolved, `T|null` as ?T
fn appendType(w: *Writer, raw: []const u8, nullable_in: bool, self_class: ?[]const u8) !void {
    var clean = raw;
    var nullable = nullable_in;
    if (clean.len > 0 and clean[0] == '?') {
        clean = clean[1..];
        nullable = true;
    }
    if (self_class) |sc| if (std.mem.eql(u8, clean, "self")) {
        clean = sc;
    };
    if (std.mem.indexOfScalar(u8, clean, '|') != null) {
        var has_null = false;
        var non_null: usize = 0;
        var only: []const u8 = "";
        var it = std.mem.splitScalar(u8, clean, '|');
        while (it.next()) |part| {
            const t = std.mem.trim(u8, part, " ");
            if (std.ascii.eqlIgnoreCase(t, "null")) has_null = true else {
                non_null += 1;
                only = t;
            }
        }
        const intersection = std.mem.indexOfScalar(u8, only, '&') != null or (only.len > 0 and only[0] == '(');
        if (has_null and non_null == 1 and !intersection) {
            const name = if (self_class != null and std.mem.eql(u8, only, "self")) self_class.? else only;
            return w.fmt("?{s}", .{name});
        }
        return w.str(try reflection.canonicalUnion(w.ctx, clean, self_class));
    }
    if (std.mem.indexOfScalar(u8, clean, '&') != null) return w.str(clean);
    if (nullable and !std.mem.eql(u8, clean, "mixed") and !std.mem.eql(u8, clean, "null")) try w.str("?");
    try w.str(clean);
}

// zend_zval_type_name
fn zvalTypeName(v: Value) []const u8 {
    return switch (v) {
        .null, .undef => "null",
        .bool => "bool",
        .int => "int",
        .float => "float",
        .string => "string",
        .array => "array",
        .object => |o| o.class_name,
        else => "mixed",
    };
}

// ---------------------------------------------------------------- functions

const MethodInfo = ClassDef.MethodInfo;

const FnView = struct {
    // as printed
    name: []const u8,
    user: ?*const ObjFunction = null,
    sig: ?native_params.Signature = null,
    types: ?vm_mod.TypeInfo = null,
    is_closure: bool = false,
    // the class a method (or a closure declared in one) belongs to
    scope: ?[]const u8 = null,
    info: MethodInfo = .{ .name = "", .arity = 0 },
    deprecated: bool = false,
    // the extension an internal function belongs to
    module: ?[]const u8 = null,
    // the closure instance whose bound variables are listed
    closure_instance: ?[]const u8 = null,
};

fn nativeSignature(key: []const u8) ?native_params.Signature {
    return native_params.get(key) orelse interface_signatures.map.get(key);
}

fn methodDeprecated(key: []const u8, user: ?*const ObjFunction) bool {
    if (user) |f| return f.deprecated != null;
    return @import("deprecations_generated.zig").functions.has(key);
}

fn classModule(vm: *VM, class_name: []const u8) ?[]const u8 {
    if (extensions.classes.get(class_name)) |m| return m;
    // php's own classes all belong to an extension; one zphp adds as built
    // in without php knowing it gets none
    _ = vm;
    return null;
}

fn methodView(ctx: *NativeContext, class_name: []const u8, declaring: []const u8, name: []const u8) !FnView {
    const vm = ctx.vm;
    var key_buf: [1024]u8 = undefined;
    const key = class_names.memberKey(&key_buf, declaring, name);
    _ = class_name;
    var view = FnView{ .name = name, .scope = declaring };
    view.user = vm.functions.get(key);
    if (view.user == null) view.sig = nativeSignature(key);
    view.types = reflection.methodTypeInfo(vm, key);
    if (vm.classes.get(declaring)) |cls| {
        view.info = cls.methods.get(name) orelse .{ .name = name, .arity = 0 };
        if (cls.is_internal and view.user == null) view.module = classModule(vm, declaring);
    } else if (vm.interfaces.contains(declaring)) {
        view.info = .{ .name = name, .arity = 0, .is_abstract = true };
        if (reflection.isInternalClassName(vm, declaring)) view.module = classModule(vm, declaring);
    }
    if (vm.interfaces.contains(declaring)) view.info.is_abstract = true;
    if (vm.classes.get(declaring) == null) if (view.user) |f| {
        // a trait's method, which only its compiled function describes
        view.info.visibility = @fromBackingInt(@intCast(f.method_visibility));
        view.info.is_final = f.is_final;
    };
    if (view.user == null and view.sig == null) if (enumMethodSignature(vm, declaring, name)) |sig| {
        view.sig = sig;
    };
    if (view.user) |f| {
        if (f.is_static) view.info.is_static = true;
    } else if (view.sig) |s| {
        if (s.is_static) view.info.is_static = true;
    }
    view.deprecated = methodDeprecated(key, view.user);
    return view;
}

// the methods php gives every enum, which zphp dispatches without declaring
fn enumMethodSignature(vm: *VM, class_name: []const u8, name: []const u8) ?native_params.Signature {
    const cls = vm.classes.get(class_name) orelse return null;
    if (!cls.is_enum) return null;
    if (std.mem.eql(u8, name, "cases")) return interface_signatures.map.get("UnitEnum::cases");
    if (cls.backed_type == .none) return null;
    if (std.mem.eql(u8, name, "from")) return interface_signatures.map.get("BackedEnum::from");
    if (std.mem.eql(u8, name, "tryFrom")) return interface_signatures.map.get("BackedEnum::tryFrom");
    return null;
}

fn functionView(ctx: *NativeContext, this: *PhpObject) FnView {
    const vm = ctx.vm;
    const key_v = reflection.functionKey(this);
    const key = if (key_v == .string) key_v.string.bytes() else "";
    var view = FnView{ .name = stringProp(this, "name") orelse key };
    view.user = vm.functions.get(key);
    if (view.user == null) {
        view.sig = native_params.get(key);
        view.module = extensions.functions.get(key);
        if (vm.native_fns.get(key)) |native| view.deprecated = native.deprecated != null;
    } else {
        view.types = reflection.closureAwareTypeInfo(key);
        view.deprecated = view.user.?.deprecated != null;
    }
    const instance = this.get("__closure").closureName();
    view.is_closure = instance != null or boolProp(this, "__from_closure");
    if (instance) |name| {
        view.closure_instance = name;
        view.scope = stringProp(this, "__scope_class") orelse vm.closureScopeByName(name);
        if (view.user) |f| view.info.is_static = f.is_static;
    }
    return view;
}

// the class whose method a class's method overrides or implements first:
// what php's zend_function.prototype names
fn prototypeOf(vm: *VM, class_name: []const u8, method: []const u8, depth: usize) ?[]const u8 {
    if (depth > 64) return null;
    var proto: ?[]const u8 = null;
    const is_ctor = std.ascii.eqlIgnoreCase(method, "__construct");
    if (vm.classes.get(class_name)) |cls| {
        if (cls.parent) |parent| {
            if (methodDeclarer(vm, parent, method)) |found| {
                if (found.info.visibility != .private) {
                    const p = prototypeOf(vm, found.class, method, depth + 1) orelse found.class;
                    if (!is_ctor or isAbstractMethod(vm, p, method)) proto = p;
                }
            }
        }
        for (cls.interfaces.items) |iface| {
            if (interfaceDeclarer(vm, iface, method, 0)) |decl| proto = prototypeOf(vm, decl, method, depth + 1) orelse decl;
        }
    }
    if (vm.interfaces.get(class_name)) |iface| {
        var parents: [16][]const u8 = undefined;
        var n: usize = 0;
        if (iface.parent) |p| {
            parents[n] = p;
            n += 1;
        }
        for (iface.parents.items) |p| {
            if (n < parents.len and !containsName(parents[0..n], p)) {
                parents[n] = p;
                n += 1;
            }
        }
        for (parents[0..n]) |p| {
            if (interfaceDeclarer(vm, p, method, 0)) |decl| proto = prototypeOf(vm, decl, method, depth + 1) orelse decl;
        }
    }
    return proto;
}

fn containsName(list: []const []const u8, name: []const u8) bool {
    for (list) |n| if (std.mem.eql(u8, n, name)) return true;
    return false;
}

fn isAbstractMethod(vm: *VM, class_name: []const u8, method: []const u8) bool {
    if (vm.interfaces.contains(class_name)) return true;
    const cls = vm.classes.get(class_name) orelse return false;
    const info = cls.methods.get(method) orelse return false;
    return info.is_abstract;
}

const Declarer = struct { class: []const u8, info: MethodInfo };

// the nearest class from class_name up that declares the method
fn methodDeclarer(vm: *VM, class_name: []const u8, method: []const u8) ?Declarer {
    var current: ?[]const u8 = class_name;
    var depth: usize = 0;
    while (current) |name| : (depth += 1) {
        if (depth > 256) return null;
        const cls = vm.classes.get(name) orelse return null;
        if (cls.methods.getKey(method)) |declared| {
            var buf: [512]u8 = undefined;
            const key = class_names.memberKey(&buf, name, declared);
            if (vm.functions.contains(key) or vm.native_fns.contains(key) or cls.is_internal) {
                return .{ .class = name, .info = cls.methods.get(method).? };
            }
        }
        current = cls.parent;
    }
    return null;
}

// the interface (iface or one it extends) that declares the method
fn interfaceDeclarer(vm: *VM, iface: []const u8, method: []const u8, depth: usize) ?[]const u8 {
    if (depth > 64) return null;
    if (vm.interfaces.get(iface)) |def| {
        for (def.methods.items) |m| if (std.ascii.eqlIgnoreCase(m, method)) return iface;
        if (def.parent) |p| if (interfaceDeclarer(vm, p, method, depth + 1)) |d| return d;
        for (def.parents.items) |p| if (interfaceDeclarer(vm, p, method, depth + 1)) |d| return d;
    }
    if (vm.classes.get(iface)) |cls| {
        if (vm.interfaces.contains(iface)) for (cls.interfaces.items) |p| if (interfaceDeclarer(vm, p, method, depth + 1)) |d| return d;
    }
    return null;
}

// the method a class's parent would dispatch to, unless it is private:
// what `, overwrites X` names
fn overwrites(vm: *VM, declaring: []const u8, method: []const u8) ?[]const u8 {
    const cls = vm.classes.get(declaring) orelse return null;
    const parent = cls.parent orelse return null;
    const found = methodDeclarer(vm, parent, method) orelse return null;
    if (found.info.visibility == .private) return null;
    return found.class;
}

fn paramCount(view: FnView) usize {
    if (view.user) |f| return f.params.len;
    if (view.sig) |s| return s.params.len;
    return 0;
}

fn returnType(view: FnView) struct { text: []const u8, tentative: bool } {
    if (view.user != null) return .{ .text = if (view.types) |t| t.return_type else "", .tentative = false };
    if (view.sig) |s| {
        if (s.returns.len > 0) return .{ .text = s.returns, .tentative = false };
        return .{ .text = s.tentative_returns, .tentative = true };
    }
    return .{ .text = "", .tentative = false };
}

const ParamView = struct {
    position: usize,
    name: []const u8,
    type_raw: []const u8 = "",
    nullable: bool = false,
    by_ref: bool = false,
    variadic: bool = false,
    required: bool = true,
    user_default: ?Value = null,
    native: ?native_params.Param = null,
    self_class: ?[]const u8 = null,
};

fn paramView(view: FnView, i: usize) ParamView {
    if (view.user) |f| {
        const raw_name = f.params[i];
        var p = ParamView{
            .position = i,
            .name = if (raw_name.len > 0 and raw_name[0] == '$') raw_name[1..] else raw_name,
            .variadic = f.is_variadic and i + 1 == f.arity,
            .by_ref = i < f.ref_params.len and f.ref_params[i],
            .self_class = view.scope,
        };
        p.required = i < f.required_params;
        if (view.types) |t| if (i < t.param_types.len) {
            p.type_raw = t.param_types[i];
        };
        if (!p.variadic and !p.required and i < f.defaults.len) {
            p.user_default = f.defaults[i];
            // php makes a type whose default is null nullable
            if (f.defaults[i] == .null) p.nullable = true;
        }
        return p;
    }
    const sp = view.sig.?.params[i];
    return .{
        .position = i,
        .name = sp.name,
        .type_raw = sp.type,
        .variadic = sp.variadic,
        .by_ref = sp.by_ref,
        .required = sp.default == .required and !sp.variadic,
        .native = sp,
        .self_class = view.scope,
    };
}

// _parameter_string
fn appendParameter(w: *Writer, p: ParamView) !void {
    try w.fmt("Parameter #{d} [ ", .{p.position});
    try w.str(if (p.required) "<required> " else "<optional> ");
    if (p.type_raw.len > 0) {
        try appendType(w, p.type_raw, p.nullable, p.self_class);
        try w.str(" ");
    }
    if (p.by_ref) try w.str("&");
    if (p.variadic) try w.str("...");
    try w.fmt("${s}", .{p.name});
    if (!p.required and !p.variadic) {
        if (p.native) |np| {
            try w.str(" = ");
            try appendNativeDefault(w, np);
        } else if (p.user_default) |d| {
            try w.str(" = ");
            const saved = w.self_class;
            defer w.self_class = saved;
            w.self_class = p.self_class;
            try appendDefault(w, d);
        }
    }
    try w.str(" ]");
}

fn appendBoundVariables(w: *Writer, view: FnView, indent: []const u8) !void {
    const f = view.user orelse return;
    const instance = view.closure_instance orelse return;
    var names: std.ArrayListUnmanaged([]const u8) = .empty;
    defer names.deinit(w.ctx.allocator);
    for (w.ctx.vm.captures.items) |cap| {
        if (!std.mem.eql(u8, cap.closure_name, instance)) continue;
        const name = if (cap.var_name.len > 0 and cap.var_name[0] == '$') cap.var_name[1..] else cap.var_name;
        // the closure's own bookkeeping rides along as captures
        if (std.mem.startsWith(u8, name, "__closure_")) continue;
        if (std.mem.eql(u8, name, "this") or containsName(names.items, name)) continue;
        try names.append(w.ctx.allocator, name);
    }
    for (f.static_vars) |sv| {
        const name = if (sv.name.len > 0 and sv.name[0] == '$') sv.name[1..] else sv.name;
        if (!containsName(names.items, name)) try names.append(w.ctx.allocator, name);
    }
    if (names.items.len == 0) return;
    try w.fmt("\n{s}- Bound Variables [{d}] {{\n", .{ indent, names.items.len });
    for (names.items, 0..) |name, i| try w.fmt("{s}    Variable #{d} [ ${s} ]\n", .{ indent, i, name });
    try w.fmt("{s}}}\n", .{indent});
}

// _function_string. scope is the class being printed (or the class a
// ReflectionMethod was taken from), which `inherits`/`overwrites` compare
// against
fn appendFunction(w: *Writer, view: FnView, scope: ?[]const u8, indent: []const u8) RuntimeError!void {
    const vm = w.ctx.vm;
    if (view.user) |f| if (f.doc_comment.len > 0) {
        try w.fmt("{s}{s}\n", .{ indent, f.doc_comment });
    };
    try w.str(indent);
    try w.str(if (view.is_closure) "Closure [ " else if (view.scope != null) "Method [ " else "Function [ ");
    try w.str(if (view.user != null) "<user" else "<internal");
    if (view.deprecated) try w.str(", deprecated");
    if (view.user == null) if (view.module) |m| try w.fmt(":{s}", .{m});
    if (scope != null and view.scope != null and !view.is_closure) {
        const declaring = view.scope.?;
        if (!std.mem.eql(u8, declaring, scope.?)) {
            try w.fmt(", inherits {s}", .{declaring});
        } else if (overwrites(vm, declaring, view.name)) |parent| {
            try w.fmt(", overwrites {s}", .{parent});
        }
    }
    if (view.scope != null and !view.is_closure) {
        if (prototypeOf(vm, view.scope.?, view.name, 0)) |proto| try w.fmt(", prototype {s}", .{proto});
        if (std.ascii.eqlIgnoreCase(view.name, "__construct")) try w.str(", ctor");
    }
    try w.str("> ");
    if (view.info.is_abstract) try w.str("abstract ");
    if (view.info.is_final) try w.str("final ");
    if (view.info.is_static) try w.str("static ");
    if (view.scope != null) {
        try w.str(switch (view.info.visibility) {
            .public => "public ",
            .protected => "protected ",
            .private => "private ",
        });
        try w.str("method ");
    } else try w.str("function ");
    if (view.user) |f| if (f.returns_ref) try w.str("&");
    if (view.is_closure and view.user != null and view.user.?.display_name.len > 0) {
        try w.str(view.user.?.display_name);
    } else try w.str(view.name);
    try w.str(" ] {\n");
    if (view.user) |f| try w.fmt("{s}  @@ {s} {d} - {d}\n", .{ indent, f.file_path, f.start_line, if (f.end_line == 0) f.start_line else f.end_line });

    const param_indent = try std.fmt.allocPrint(w.ctx.allocator, "{s}  ", .{indent});
    defer w.ctx.allocator.free(param_indent);
    if (view.is_closure) try appendBoundVariables(w, view, param_indent);

    const ret = returnType(view);
    const count = paramCount(view);
    // a user function has argument info only with parameters or a return type
    if (view.user == null or count > 0 or ret.text.len > 0) {
        if (view.user != null or view.sig != null) {
            try w.fmt("\n{s}- Parameters [{d}] {{\n", .{ param_indent, count });
            for (0..count) |i| {
                try w.fmt("{s}  ", .{param_indent});
                try appendParameter(w, paramView(view, i));
                try w.str("\n");
            }
            try w.fmt("{s}}}\n", .{param_indent});
        }
    }
    if (ret.text.len > 0) {
        try w.fmt("  {s}- {s} [ ", .{ indent, if (ret.tentative) "Tentative return" else "Return" });
        try appendType(w, ret.text, false, view.scope);
        try w.str(" ]\n");
    }
    try w.fmt("{s}}}\n", .{indent});
}

// ---------------------------------------------------------------- properties

const PropView = struct {
    name: []const u8,
    declaring: []const u8,
    def: ClassDef.PropertyDef,
    is_static: bool,
};

fn hookOf(vm: *VM, declaring: []const u8, prop: []const u8, kind: []const u8) ?MethodInfo {
    var buf: [512]u8 = undefined;
    const method = std.fmt.bufPrint(&buf, "{s}$hook_{s}", .{ prop, kind }) catch return null;
    const cls = vm.classes.getPtr(declaring) orelse return null;
    const hook = vm.resolvePropertyHook(cls, method) orelse return null;
    return hook.info;
}

// _property_string
fn appendProperty(w: *Writer, p: PropView, indent: []const u8) RuntimeError!void {
    const vm = w.ctx.vm;
    const def = p.def;
    if (def.doc_comment.len > 0) try w.fmt("{s}{s}\n", .{ indent, def.doc_comment });
    try w.fmt("{s}Property [ ", .{indent});
    const get_hook = hookOf(vm, p.declaring, p.name, "get");
    const set_hook = hookOf(vm, p.declaring, p.name, "set");
    const is_abstract = (get_hook != null and get_hook.?.is_abstract) or (set_hook != null and set_hook.?.is_abstract);
    if (is_abstract) try w.str("abstract ");
    const vis = def.visibility;
    const set_vis = if (def.has_set_visibility) def.set_visibility else vis;
    const private_set = def.has_set_visibility and set_vis == .private and vis != .private;
    // readonly implies protected(set) on a public property
    const protected_set = (set_vis == .protected and vis == .public) or
        (def.is_readonly and !def.readonly_undeclared and vis == .public and set_vis == .public);
    if (def.is_final or private_set) try w.str("final ");
    try w.str(switch (vis) {
        .public => "public ",
        .protected => "protected ",
        .private => "private ",
    });
    if (private_set) try w.str("private(set) ") else if (protected_set) try w.str("protected(set) ");
    if (p.is_static) try w.str("static ");
    if (def.is_readonly and !def.readonly_undeclared) try w.str("readonly ");
    if (def.is_virtual) try w.str("virtual ");
    if (def.type_str.len > 0) {
        try appendType(w, def.type_str, false, p.declaring);
        try w.str(" ");
    }
    try w.fmt("${s}", .{p.name});
    const saved = w.self_class;
    defer w.self_class = saved;
    w.self_class = p.declaring;
    if (!def.is_virtual) {
        if (p.is_static) {
            if (def.default != .undef) {
                try w.str(" = ");
                try appendDefault(w, def.default);
            }
        } else if (def.has_default and !def.is_promoted) {
            try w.str(" = ");
            try appendDefault(w, def.default);
        } else if (def.type_str.len == 0) {
            try w.str(" = NULL");
        }
    }
    if (get_hook != null or set_hook != null) {
        try w.str(" {");
        if (get_hook) |h| try w.str(if (h.is_final) " final get;" else " get;");
        if (set_hook) |h| try w.str(if (h.is_final) " final set;" else " set;");
        try w.str(" }");
    }
    try w.str(" ]\n");
}

fn appendDynamicProperty(w: *Writer, name: []const u8, indent: []const u8) !void {
    try w.fmt("{s}Property [ <dynamic> public ${s} ]\n", .{ indent, name });
}

// what a class lists as its properties, own first, then its parents' that
// are not private
fn collectProperties(ctx: *NativeContext, class_name: []const u8, out: *std.ArrayListUnmanaged(PropView)) RuntimeError!void {
    if (ctx.vm.traits.contains(class_name) and ctx.vm.classes.get(class_name) == null) {
        if (ctx.vm.trait_props.get(class_name)) |props| for (props) |prop| {
            try out.append(ctx.allocator, .{ .name = prop.name, .declaring = class_name, .def = prop, .is_static = false });
        };
        if (ctx.vm.trait_static_props.get(class_name)) |props| for (props) |sp| {
            const vis: ClassDef.Visibility = @fromBackingInt(@intCast(sp.flags & 3));
            try out.append(ctx.allocator, .{ .name = sp.name, .declaring = class_name, .is_static = true, .def = .{
                .name = sp.name,
                .default = sp.value,
                .has_default = true,
                .visibility = vis,
                .set_visibility = vis,
                .type_str = sp.type_str,
                .doc_comment = sp.doc_comment,
            } });
        };
        return;
    }
    var is_own = true;
    var current: ?[]const u8 = class_name;
    var depth: usize = 0;
    while (current) |name| : (depth += 1) {
        if (depth > 256) break;
        const cls = ctx.vm.classes.getPtr(name) orelse break;
        for (cls.properties.items) |prop| {
            if (!is_own and prop.visibility == .private) continue;
            if (hasProp(out.items, prop.name)) continue;
            try out.append(ctx.allocator, .{ .name = prop.name, .declaring = name, .def = prop, .is_static = false });
        }
        var it = cls.static_props.iterator();
        while (it.next()) |entry| {
            const sp_name = entry.key_ptr.*;
            const def = reflection.staticPropertyDef(cls, sp_name, entry.value_ptr.*);
            if (!is_own and def.visibility == .private) continue;
            if (hasProp(out.items, sp_name)) continue;
            try out.append(ctx.allocator, .{ .name = sp_name, .declaring = name, .def = def, .is_static = true });
        }
        current = cls.parent;
        is_own = false;
    }
}

fn hasProp(items: []const PropView, name: []const u8) bool {
    for (items) |p| if (std.mem.eql(u8, p.name, name)) return true;
    return false;
}

// ---------------------------------------------------------------- constants

fn constantValue(ctx: *NativeContext, declaring: []const u8, name: []const u8) RuntimeError!?Value {
    const cls = ctx.vm.classes.get(declaring) orelse return null;
    const stored = cls.constants.get(name) orelse return null;
    if (stored == .undef) return try ctx.vm.evaluateClassConstant(declaring, name);
    return ctx.vm.enumCase(stored);
}

fn isEnumCase(vm: *VM, declaring: []const u8, name: []const u8) bool {
    const cls = vm.classes.get(declaring) orelse return false;
    if (!cls.is_enum) return false;
    return containsName(cls.case_order.items, name);
}

// _class_const_string
fn appendClassConstant(w: *Writer, declaring: []const u8, name: []const u8, value: Value, indent: []const u8) RuntimeError!void {
    const ctx = w.ctx;
    const cls = ctx.vm.classes.get(declaring);
    if (reflection.findConstantDoc(ctx, declaring, name, 0)) |doc| if (doc.len > 0) {
        try w.fmt("{s}{s}\n", .{ indent, doc });
    };
    try w.fmt("{s}Constant [ ", .{indent});
    if (cls) |c| if (c.const_final.contains(name)) try w.str("final ");
    const vis = if (cls) |c| c.const_visibility.get(name) orelse .public else .public;
    try w.str(switch (vis) {
        .public => "public ",
        .protected => "protected ",
        .private => "private ",
    });
    const declared_type = if (cls) |c| c.constant_types.get(name) else null;
    if (declared_type) |t| try appendType(w, t, false, declaring) else try w.str(zvalTypeName(value));
    try w.fmt(" {s} ] {{ ", .{name});
    switch (value) {
        .array => try w.str("Array"),
        .object => try w.str("Object"),
        .float => |f| try appendDouble(w, f, false),
        else => try value.format(&w.buf, ctx.allocator),
    }
    try w.str(" }\n");
}

// _enum_case_string
fn appendEnumCase(w: *Writer, declaring: []const u8, name: []const u8, value: Value, indent: []const u8) RuntimeError!void {
    const ctx = w.ctx;
    if (reflection.findConstantDoc(ctx, declaring, name, 0)) |doc| if (doc.len > 0) {
        try w.fmt("{s}{s}\n", .{ indent, doc });
    };
    try w.fmt("{s}Case {s}", .{ indent, name });
    const cls = ctx.vm.classes.get(declaring);
    if (cls != null and cls.?.backed_type != .none and value == .object) {
        try w.str(" = ");
        try value.object.get("value").format(&w.buf, ctx.allocator);
    }
    try w.str("\n");
}

// ---------------------------------------------------------------- classes

// a class's interfaces in php's order (zend_do_implement_interfaces): its
// parent's, then the ones it declares, then what each of those extends,
// which zend_do_inherit_interfaces appends last first
fn interfaceList(ctx: *NativeContext, class_name: []const u8, out: *std.ArrayListUnmanaged([]const u8)) RuntimeError!void {
    return interfaceListDepth(ctx, class_name, out, 0);
}

fn declaredInterfaces(vm: *VM, class_name: []const u8, out: *std.ArrayListUnmanaged([]const u8), a: Allocator) !void {
    if (vm.interfaces.get(class_name)) |iface| {
        if (iface.parents.items.len > 0) {
            for (iface.parents.items) |p| if (!containsName(out.items, p)) try out.append(a, p);
        } else if (iface.parent) |p| try out.append(a, p);
    }
    if (vm.classes.get(class_name)) |cls| for (cls.interfaces.items) |p| if (!containsName(out.items, p)) try out.append(a, p);
}

fn interfaceListDepth(ctx: *NativeContext, class_name: []const u8, out: *std.ArrayListUnmanaged([]const u8), depth: usize) RuntimeError!void {
    if (depth > 64) return;
    const vm = ctx.vm;
    const a = ctx.allocator;
    if (!vm.interfaces.contains(class_name)) {
        if (vm.classes.get(class_name)) |cls| if (cls.parent) |p| try interfaceListDepth(ctx, p, out, depth + 1);
    }
    const inherited = out.items.len;
    var declared: std.ArrayListUnmanaged([]const u8) = .empty;
    defer declared.deinit(a);
    try declaredInterfaces(vm, class_name, &declared, a);
    for (declared.items) |name| {
        const canonical = vm.declaredClassName(name);
        if (!containsName(out.items, canonical)) try out.append(a, canonical);
    }
    const own_end = out.items.len;
    for (inherited..own_end) |i| {
        var extended: std.ArrayListUnmanaged([]const u8) = .empty;
        defer extended.deinit(a);
        try interfaceListDepth(ctx, out.items[i], &extended, depth + 1);
        var j = extended.items.len;
        while (j > 0) {
            j -= 1;
            if (!containsName(out.items, extended.items[j])) try out.append(a, extended.items[j]);
        }
    }
}

const MethodEntry = struct { declaring: []const u8, name: []const u8, info: MethodInfo };

// what a class lists as its methods, in php's function table order: its
// own, then what it inherits that is not private
fn collectMethods(ctx: *NativeContext, class_name: []const u8, out: *std.ArrayListUnmanaged(MethodEntry)) RuntimeError!void {
    const vm = ctx.vm;
    if (vm.interfaces.contains(class_name)) {
        try collectInterfaceMethods(ctx, class_name, out, 0);
        return;
    }
    if (vm.traits.contains(class_name) and vm.classes.get(class_name) == null) {
        try collectTraitMethods(ctx, class_name, out);
        return;
    }
    defer if (vm.classes.get(class_name)) |cls| if (cls.is_enum) {
        for ([_][]const u8{ "cases", "from", "tryFrom" }) |m| {
            if (hasMethod(out.items, m) or enumMethodSignature(vm, class_name, m) == null) continue;
            out.append(ctx.allocator, .{ .declaring = class_name, .name = m, .info = .{ .name = m, .arity = 0, .is_static = true } }) catch {};
        }
    };
    var current: ?[]const u8 = class_name;
    var depth: usize = 0;
    while (current) |name| : (depth += 1) {
        if (depth > 256) break;
        const cls = vm.classes.get(name) orelse break;
        var order: std.ArrayListUnmanaged([]const u8) = .empty;
        defer order.deinit(ctx.allocator);
        if (cls.method_order.items.len > 0) {
            try order.appendSlice(ctx.allocator, cls.method_order.items);
        }
        var it = cls.methods.iterator();
        while (it.next()) |entry| if (!containsName(order.items, entry.key_ptr.*)) try order.append(ctx.allocator, entry.key_ptr.*);
        for (order.items) |method_name| {
            const info = cls.methods.get(method_name) orelse continue;
            if (std.mem.indexOf(u8, method_name, "$hook_") != null) continue;
            if (depth > 0 and info.visibility == .private) continue;
            if (hasMethod(out.items, method_name)) continue;
            const declaring = reflection.findDeclaringClass(vm, class_name, method_name);
            try out.append(ctx.allocator, .{ .declaring = declaring, .name = method_name, .info = info });
        }
        current = cls.parent;
    }
}

// a trait's methods, in the order it declares them
fn collectTraitMethods(ctx: *NativeContext, trait_name: []const u8, out: *std.ArrayListUnmanaged(MethodEntry)) RuntimeError!void {
    const start = out.items.len;
    var it = ctx.vm.functions.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        if (key.len <= trait_name.len + 2 or !std.mem.startsWith(u8, key, trait_name) or !std.mem.eql(u8, key[trait_name.len .. trait_name.len + 2], "::")) continue;
        const name = key[trait_name.len + 2 ..];
        if (std.mem.indexOf(u8, name, "$hook_") != null or hasMethod(out.items, name)) continue;
        const f = entry.value_ptr.*;
        try out.append(ctx.allocator, .{ .declaring = trait_name, .name = name, .info = .{
            .name = name,
            .arity = f.arity,
            .is_static = f.is_static,
            .is_final = f.is_final,
            .visibility = @fromBackingInt(@intCast(f.method_visibility)),
        } });
    }
    const Order = struct {
        vm: *VM,
        trait: []const u8,
        fn line(self: @This(), m: MethodEntry) u32 {
            var buf: [512]u8 = undefined;
            const key = class_names.memberKey(&buf, self.trait, m.name);
            return if (self.vm.functions.get(key)) |f| f.start_line else 0;
        }
        fn lessThan(self: @This(), a: MethodEntry, b: MethodEntry) bool {
            return self.line(a) < self.line(b);
        }
    };
    std.mem.sort(MethodEntry, out.items[start..], Order{ .vm = ctx.vm, .trait = trait_name }, Order.lessThan);
}

fn collectInterfaceMethods(ctx: *NativeContext, iface_name: []const u8, out: *std.ArrayListUnmanaged(MethodEntry), depth: usize) RuntimeError!void {
    if (depth > 64) return;
    const iface = ctx.vm.interfaces.get(iface_name) orelse return;
    for (iface.methods.items) |m| {
        if (std.mem.indexOf(u8, m, "$hook_") != null or hasMethod(out.items, m)) continue;
        var info = MethodInfo{ .name = m, .arity = 0, .is_abstract = true };
        if (ctx.vm.classes.get(iface_name)) |cls| if (cls.methods.get(m)) |mi| {
            info = mi;
            info.is_abstract = true;
        };
        try out.append(ctx.allocator, .{ .declaring = iface_name, .name = m, .info = info });
    }
    if (iface.parents.items.len > 0) {
        for (iface.parents.items) |p| try collectInterfaceMethods(ctx, p, out, depth + 1);
    } else if (iface.parent) |p| try collectInterfaceMethods(ctx, p, out, depth + 1);
}

fn hasMethod(items: []const MethodEntry, name: []const u8) bool {
    for (items) |m| if (std.ascii.eqlIgnoreCase(m.name, name)) return true;
    return false;
}

fn entryView(ctx: *NativeContext, class_name: []const u8, m: MethodEntry) !FnView {
    var view = try methodView(ctx, class_name, m.declaring, m.name);
    view.info.visibility = m.info.visibility;
    view.info.is_final = m.info.is_final;
    view.info.is_abstract = view.info.is_abstract or m.info.is_abstract;
    if (m.info.is_static) view.info.is_static = true;
    return view;
}

// php iterates an object with a hooked property through its hooks, which
// gives the class an iterator
fn hasHookedProperty(vm: *VM, class_name: []const u8) bool {
    var current: ?[]const u8 = class_name;
    var depth: usize = 0;
    while (current) |name| : (depth += 1) {
        if (depth > 256) return false;
        const cls = vm.classes.get(name) orelse return false;
        if (cls.has_prop_hooks) return true;
        current = cls.parent;
    }
    return false;
}

// _class_string
fn appendClass(w: *Writer, class_name: []const u8, obj: ?*PhpObject, indent: []const u8) RuntimeError!void {
    const ctx = w.ctx;
    const vm = ctx.vm;
    const allocator = ctx.allocator;
    const sub_indent = try std.fmt.allocPrint(allocator, "{s}    ", .{indent});
    defer allocator.free(sub_indent);

    const is_interface = vm.interfaces.contains(class_name);
    const is_trait = vm.traits.contains(class_name);
    const cls = vm.classes.get(class_name);
    const is_enum = cls != null and cls.?.is_enum;
    const internal = reflection.isInternalClassName(vm, class_name);

    const site = vm.declSite(class_name);
    if (site) |s| if (s.doc_comment.len > 0) {
        try w.fmt("{s}{s}\n", .{ indent, s.doc_comment });
    };
    if (obj != null) {
        try w.fmt("{s}Object of class [ ", .{indent});
    } else {
        const kind = if (is_interface) "Interface" else if (is_trait) "Trait" else if (is_enum) "Enum" else "Class";
        try w.fmt("{s}{s} [ ", .{ indent, kind });
    }
    try w.str(if (internal) "<internal" else "<user");
    if (internal) if (classModule(vm, class_name)) |m| try w.fmt(":{s}", .{m});
    try w.str("> ");
    if ((!is_interface and !is_trait and vm.isInstanceOf(class_name, "Traversable")) or hasHookedProperty(vm, class_name)) try w.str("<iterateable> ");
    if (is_interface) {
        try w.str("interface ");
    } else if (is_trait) {
        try w.str("trait ");
    } else if (is_enum) {
        try w.str("enum ");
    } else {
        if (cls) |c| {
            if (c.is_abstract) try w.str("abstract ");
            if (c.is_final) try w.str("final ");
            if (c.is_readonly) try w.str("readonly ");
        }
        try w.str("class ");
    }
    try w.str(vm.declaredClassName(class_name));
    if (!is_interface) if (cls) |c| if (c.parent) |p| try w.fmt(" extends {s}", .{vm.declaredClassName(p)});
    if (is_enum and cls.?.backed_type != .none) try w.str(if (cls.?.backed_type == .string_type) ": string" else ": int");
    var ifaces: std.ArrayListUnmanaged([]const u8) = .empty;
    defer ifaces.deinit(allocator);
    try interfaceList(ctx, class_name, &ifaces);
    for (ifaces.items, 0..) |iface, i| {
        if (i == 0) {
            try w.fmt(" {s} {s}", .{ if (is_interface) "extends" else "implements", iface });
        } else try w.fmt(", {s}", .{iface});
    }
    try w.str(" ] {\n");
    if (!internal) if (site) |s| try w.fmt("{s}  @@ {s} {d}-{d}\n", .{ indent, s.file, s.start_line, s.end_line });

    // constants and enum cases
    var constant_w = Writer{ .ctx = ctx };
    defer constant_w.deinit();
    var case_w = Writer{ .ctx = ctx };
    defer case_w.deinit();
    var constant_count: usize = 0;
    var case_count: usize = 0;
    if (cls != null) {
        try vm.updateClassConstants(class_name);
        var constants: std.ArrayListUnmanaged(reflection.VisibleConstant) = .empty;
        defer constants.deinit(allocator);
        try reflection.visibleConstants(ctx, class_name, &constants);
        for (constants.items) |c| {
            if (isEnumCase(vm, c.declaring, c.name)) {
                try appendEnumCase(&case_w, c.declaring, c.name, c.value, sub_indent);
                case_count += 1;
            } else {
                try appendClassConstant(&constant_w, c.declaring, c.name, c.value, sub_indent);
                constant_count += 1;
            }
        }
    }
    if (case_count > 0) {
        try w.fmt("\n{s}  - Enum cases [{d}] {{\n", .{ indent, case_count });
        try w.str(case_w.buf.items);
        try w.fmt("{s}  }}\n", .{indent});
    }
    try w.fmt("\n{s}  - Constants [{d}] {{\n", .{ indent, constant_count });
    try w.str(constant_w.buf.items);
    try w.fmt("{s}  }}\n", .{indent});

    // properties
    if (cls != null) try vm.resolveClassDefaults(class_name);
    var props: std.ArrayListUnmanaged(PropView) = .empty;
    defer props.deinit(allocator);
    try collectProperties(ctx, class_name, &props);
    var static_props: usize = 0;
    for (props.items) |p| {
        if (p.is_static) static_props += 1;
    }
    try w.fmt("\n{s}  - Static properties [{d}] {{\n", .{ indent, static_props });
    for (props.items) |p| if (p.is_static) try appendProperty(w, p, sub_indent);
    try w.fmt("{s}  }}\n", .{indent});

    // methods
    var methods: std.ArrayListUnmanaged(MethodEntry) = .empty;
    defer methods.deinit(allocator);
    try collectMethods(ctx, class_name, &methods);
    var static_methods: usize = 0;
    for (methods.items) |m| {
        const view = try entryView(ctx, class_name, m);
        if (view.info.is_static) static_methods += 1;
    }
    try w.fmt("\n{s}  - Static methods [{d}] {{", .{ indent, static_methods });
    if (static_methods > 0) {
        for (methods.items) |m| {
            const view = try entryView(ctx, class_name, m);
            if (!view.info.is_static) continue;
            try w.str("\n");
            try appendFunction(w, view, class_name, sub_indent);
        }
    } else try w.str("\n");
    try w.fmt("{s}  }}\n", .{indent});

    try w.fmt("\n{s}  - Properties [{d}] {{\n", .{ indent, props.items.len - static_props });
    for (props.items) |p| if (!p.is_static) try appendProperty(w, p, sub_indent);
    try w.fmt("{s}  }}\n", .{indent});

    if (obj) |o| {
        var dyn_w = Writer{ .ctx = ctx };
        defer dyn_w.deinit();
        var count: usize = 0;
        var it = o.properties.iterator();
        while (it.next()) |entry| {
            const name = entry.key_ptr.*;
            if (name.len == 0 or name[0] == 0) continue;
            if (o.isUnset(name) or object_properties.isInternalState(vm, o, name)) continue;
            if (hasProp(props.items, name) or reflection.findPropertyDef(vm, class_name, name) != null) continue;
            try appendDynamicProperty(&dyn_w, name, sub_indent);
            count += 1;
        }
        try w.fmt("\n{s}  - Dynamic properties [{d}] {{\n", .{ indent, count });
        try w.str(dyn_w.buf.items);
        try w.fmt("{s}  }}\n", .{indent});
    }

    const instance_methods = methods.items.len - static_methods;
    try w.fmt("\n{s}  - Methods [{d}] {{", .{ indent, instance_methods });
    if (instance_methods > 0) {
        for (methods.items) |m| {
            const view = try entryView(ctx, class_name, m);
            if (view.info.is_static) continue;
            try w.str("\n");
            try appendFunction(w, view, class_name, sub_indent);
        }
    } else try w.str("\n");
    try w.fmt("{s}  }}\n", .{indent});
    try w.fmt("{s}}}\n", .{indent});
}

// ---------------------------------------------------------------- natives

fn classToString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = reflection.getThis(ctx) orelse return NativeResult.literal("");
    const name = stringProp(this, "name") orelse return NativeResult.literal("");
    var w = Writer{ .ctx = ctx };
    defer w.deinit();
    const target = this.get("__object");
    try appendClass(&w, name, if (target == .object) target.object else null, "");
    return w.result();
}

fn functionToString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = reflection.getThis(ctx) orelse return NativeResult.literal("");
    const view = functionView(ctx, this);
    var w = Writer{ .ctx = ctx };
    defer w.deinit();
    try appendFunction(&w, view, null, "");
    return w.result();
}

fn methodToString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = reflection.getThis(ctx) orelse return NativeResult.literal("");
    const name = reflection.methodLookupName(this) orelse return NativeResult.literal("");
    const declaring = stringProp(this, "__declaring_class") orelse return NativeResult.literal("");
    const class_name = stringProp(this, "class") orelse declaring;
    var view = try methodView(ctx, class_name, declaring, name);
    const vis = this.get("__visibility");
    if (vis == .int) view.info.visibility = @fromBackingInt(@intCast(@as(u8, @intCast(vis.int))));
    if (boolProp(this, "__is_static")) view.info.is_static = true;
    var w = Writer{ .ctx = ctx };
    defer w.deinit();
    try appendFunction(&w, view, class_name, "");
    return w.result();
}

fn parameterToString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = reflection.getThis(ctx) orelse return NativeResult.literal("");
    const position: usize = if (this.get("__position") == .int) @intCast(this.get("__position").int) else 0;
    const function = stringProp(this, "__function") orelse "";
    var view: FnView = undefined;
    if (stringProp(this, "__declaring_class")) |declaring| {
        const method = stringProp(this, "__method_name") orelse function;
        view = try methodView(ctx, declaring, declaring, method);
    } else {
        view = .{ .name = function };
        view.user = ctx.vm.functions.get(function);
        if (view.user == null) view.sig = native_params.get(function) else view.types = reflection.closureAwareTypeInfo(function);
    }
    if (position >= paramCount(view)) return NativeResult.literal("");
    var w = Writer{ .ctx = ctx };
    defer w.deinit();
    try appendParameter(&w, paramView(view, position));
    return w.result();
}

fn propertyToString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = reflection.getThis(ctx) orelse return NativeResult.literal("");
    const name = stringProp(this, "name") orelse return NativeResult.literal("");
    var w = Writer{ .ctx = ctx };
    defer w.deinit();
    const declaring = stringProp(this, "__declaring_class");
    const class_name = stringProp(this, "class") orelse "";
    if (declaring == null) {
        try appendDynamicProperty(&w, name, "");
        return w.result();
    }
    const found = reflection.findPropertyDef(ctx.vm, declaring.?, name) orelse reflection.findPropertyDef(ctx.vm, class_name, name) orelse {
        try appendDynamicProperty(&w, name, "");
        return w.result();
    };
    try appendProperty(&w, .{ .name = name, .declaring = found.declaring_class, .def = found.prop, .is_static = found.is_static }, "");
    return w.result();
}

fn classConstantToString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = reflection.getThis(ctx) orelse return NativeResult.literal("");
    const name = stringProp(this, "name") orelse {
        try ctx.vm.setPendingException("Error", "Typed property ReflectionClassConstant::$name must not be accessed before initialization");
        return error.RuntimeError;
    };
    const class_name = stringProp(this, "class") orelse return NativeResult.literal("");
    const declaring = reflection.findConstantOwner(ctx, class_name, name, 0) orelse class_name;
    const value = (try constantValue(ctx, declaring, name)) orelse Value.null;
    var w = Writer{ .ctx = ctx };
    defer w.deinit();
    try appendClassConstant(&w, declaring, name, value, "");
    return w.result();
}

fn attributeToString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = reflection.getThis(ctx) orelse return NativeResult.literal("");
    const name = stringProp(this, "name") orelse "";
    var w = Writer{ .ctx = ctx };
    defer w.deinit();
    try w.fmt("Attribute [ {s} ]", .{name});
    const args = this.get("__arguments");
    if (args == .array and args.array.entries.items.len > 0) {
        try w.str(" {\n");
        try w.fmt("  - Arguments [{d}] {{\n", .{args.array.entries.items.len});
        for (args.array.entries.items, 0..) |entry, i| {
            try w.fmt("    Argument #{d} [ ", .{i});
            if (entry.key == .string) try w.fmt("{s} = ", .{entry.key.string.bytes()});
            const arg = if (entry.ref) |ref| ref.* else entry.value;
            // an argument zphp evaluates with a hidden initializer keeps no
            // source text to print, and evaluating it here could throw
            if (arg == .string and bytecode.attrArgumentInitializerName(arg.string.bytes()) != null) {
                try w.str("NULL");
            } else try appendDefault(&w, arg);
            try w.str(" ]\n");
        }
        try w.str("  }\n");
        try w.str("}\n");
    } else try w.str("\n");
    return w.result();
}

// _const_string, for ReflectionConstant
pub fn constantString(ctx: *NativeContext, name: []const u8, value: Value, persistent: bool, deprecated: bool) RuntimeError!NativeResult {
    var w = Writer{ .ctx = ctx };
    defer w.deinit();
    try w.str("Constant [ ");
    if (persistent or deprecated) {
        try w.str("<");
        if (persistent) try w.str("persistent");
        if (deprecated) try w.str(if (persistent) ", deprecated" else "deprecated");
        try w.str("> ");
    }
    try w.fmt("{s} {s} ] {{ ", .{ zvalTypeName(value), name });
    switch (value) {
        .array => try w.str("Array"),
        .float => |f| try appendDouble(&w, f, false),
        .object => try w.str("Object"),
        else => try value.format(&w.buf, ctx.allocator),
    }
    try w.str(" }\n");
    return w.result();
}
