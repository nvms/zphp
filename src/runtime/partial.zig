// php 8.6's partial function application (Zend/zend_partial.c): `f(1, ?, x:
// 2, ...)` makes a Closure. php generates the closure's AST and compiles it;
// zphp does the same with source: the closure takes the placeholders as its
// parameters (the callee's names, types, defaults, by-reference flags and
// #[\SensitiveParameter]s), binds the given arguments as its `use` variables
// and forwards everything to the callee:
//
//   function f($a, $b, $c = 3) {}
//   f(1, ?, ...)  =>  static function ($b, $c = 3) use ($a) { return \f($a, $b, $c); }
//
// the callee is a function (`\f`), a method (`$this->m` or `static::m`, the
// closure running in the method's class), or a Closure (`$fn`, bound as the
// first `use` variable). the compiled closure is kept per call site and
// callee for the request; each application makes a closure instance of it
// with the bound values as captures

const std = @import("std");
const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const RuntimeError = vm_mod.RuntimeError;
const RefSource = vm_mod.RefSource;
const value_mod = @import("value.zig");
const Value = value_mod.Value;
const PhpArray = value_mod.PhpArray;
const PhpObject = value_mod.PhpObject;
const callables = @import("callables.zig");
const bytecode = @import("../pipeline/bytecode.zig");
const ObjFunction = bytecode.ObjFunction;
const native_params = @import("../stdlib/native_params.zig");
const deprecations = @import("../stdlib/deprecations_generated.zig");
const parser_mod = @import("../pipeline/parser.zig");
const compiler_mod = @import("../pipeline/compiler.zig");
const compiler_class = @import("../pipeline/compiler_class.zig");
const CompileResult = compiler_mod.CompileResult;

const Default = union(enum) {
    // a required parameter
    none,
    // a user function's default, as its ObjFunction keeps it
    raw: Value,
    // an internal function's default, as a constant expression
    source: []const u8,
    // an internal function's optional parameter whose default php doesn't know
    unknown,
};

const Param = struct {
    // without the $
    name: []const u8,
    by_ref: bool = false,
    type: []const u8 = "",
    default: Default = .none,
    // an internal default php evaluates by compiling it (get_default_via_ast),
    // which leaves the compiler on line 1
    via_ast: bool = false,
    sensitive: bool = false,
};

const Kind = enum { function, method, static_method, closure, magic };

// the function a partial application calls (php's call->func with its This)
const Target = struct {
    kind: Kind,
    // the name messages give it: "f" or "C::m"
    display: []const u8,
    // the function or method name the forwarding call names
    call_name: []const u8,
    object: ?*PhpObject = null,
    called_class: ?[]const u8 = null,
    // the function's class (func->common.scope), null for a function
    scope: ?[]const u8 = null,
    closure: ?*PhpObject = null,
    // the parameters before a variadic one (num_args)
    params: []Param = &.{},
    variadic: ?Param = null,
    required: usize = 0,
    return_type: []const u8 = "",
    returns_ref: bool = false,
    no_discard: ?[]const u8 = null,
    // a static method or static closure
    is_static: bool = false,
    // a closure that isn't static (zp_is_non_static_closure)
    non_static_closure: bool = false,
    // the user function whose defaults initializers evaluate, for their scope
    user: ?*const ObjFunction = null,
    is_assert: bool = false,
    forbid_dynamic: bool = false,
    // what the compiled closure is kept by, with the call site
    identity: usize = 0,
    identity_name: []const u8 = "",
    // the name the vm registered the function under
    registered: []const u8 = "",
};

const Slot = union(enum) {
    undef,
    placeholder,
    bound: struct { value: Value, source: RefSource },
};

fn stripDollar(name: []const u8) []const u8 {
    return if (name.len > 0 and name[0] == '$') name[1..] else name;
}

fn throwFmt(vm: *VM, class: []const u8, comptime fmt: []const u8, args: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(vm.allocator, fmt, args);
    defer vm.allocator.free(msg);
    try vm.setPendingException(class, msg);
    return error.RuntimeError;
}

// a user function's parameters as a partial application sees them
fn fromUser(vm: *VM, t: *Target, func: *const ObjFunction, a: std.mem.Allocator) !void {
    t.user = func;
    t.registered = func.name;
    t.identity = @intFromPtr(func);
    const ti = vm.typeInfoFor(func.name);
    const sensitive = try vm.sensitiveParamMask(func);
    const total = func.params.len;
    const num_args = if (func.is_variadic and total > 0) total - 1 else total;
    var params = try a.alloc(Param, num_args);
    for (0..total) |i| {
        const p: Param = .{
            .name = stripDollar(func.params[i]),
            .by_ref = i < func.ref_params.len and func.ref_params[i],
            .type = if (ti) |info| (if (i < info.param_types.len) info.param_types[i] else "") else "",
            .default = if (i < num_args and i >= func.required_params) .{ .raw = if (i < func.defaults.len) func.defaults[i] else .null } else .none,
            .sensitive = i < 64 and sensitive & (@as(u64, 1) << @intCast(i)) != 0,
        };
        if (i < num_args) params[i] = p else t.variadic = p;
    }
    t.params = params;
    t.required = @min(func.required_params, num_args);
    if (ti) |info| t.return_type = info.return_type;
    t.returns_ref = func.returns_ref;
    t.no_discard = func.no_discard;
}

// an internal function's parameters, from its signature
fn fromNative(vm: *VM, t: *Target, name: []const u8, a: std.mem.Allocator) !void {
    _ = vm;
    t.identity_name = name;
    t.registered = name;
    const sig = native_params.get(name) orelse {
        // no published signature: variadic, as php's would be unknown
        t.variadic = .{ .name = "args" };
        return;
    };
    const sensitive = deprecations.sensitive_parameters.get(name) orelse 0;
    var count: usize = 0;
    for (sig.params) |p| {
        if (!p.variadic) count += 1;
    }
    var params = try a.alloc(Param, count);
    var n: usize = 0;
    var required: usize = 0;
    var seen_optional = false;
    for (sig.params, 0..) |p, i| {
        const default: Default = switch (p.default) {
            .required => .none,
            .unknown => .unknown,
            .null => .{ .source = "null" },
            .bool => |b| .{ .source = if (b) "true" else "false" },
            .empty_array => .{ .source = "[]" },
            .int => |v| .{ .source = try std.fmt.allocPrint(a, "{d}", .{v}) },
            .float => |v| .{ .source = try floatSource(a, v) },
            .string => |s| .{ .source = try quoteString(a, s) },
            .class_constant => |cc| .{ .source = try std.fmt.allocPrint(a, "\\{s}::{s}", .{ cc.class, cc.name }) },
        };
        // a stub default written as an expression (a constant) is php's
        // via the AST, compiled where the closure is: `= STR_PAD_RIGHT`
        const expression = native_params.defaultExpression(name, p.name) orelse if (p.default_constant.len > 0) p.default_constant else null;
        const param: Param = .{
            .name = p.name,
            .by_ref = p.by_ref,
            .type = p.type,
            .default = if (p.default == .required) .none else if (expression) |text| .{ .source = text } else default,
            .via_ast = expression != null or p.default == .float or p.default == .class_constant,
            .sensitive = i < 64 and sensitive & (@as(u64, 1) << @intCast(i)) != 0,
        };
        if (p.variadic) {
            t.variadic = param;
            continue;
        }
        if (p.default != .required) seen_optional = true;
        if (!seen_optional) required = n + 1;
        params[n] = param;
        n += 1;
    }
    t.params = params;
    t.required = required;
    t.return_type = sig.returns;
    t.is_static = sig.is_static;
}

fn floatSource(a: std.mem.Allocator, v: f64) ![]const u8 {
    if (std.math.isNan(v)) return a.dupe(u8, "\\NAN");
    if (std.math.isInf(v)) return a.dupe(u8, if (v > 0) "\\INF" else "-\\INF");
    const text = try std.fmt.allocPrint(a, "{e}", .{v});
    return text;
}

// a php single-quoted literal of the bytes
fn quoteString(a: std.mem.Allocator, s: []const u8) ![]const u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    try out.append(a, '\'');
    for (s) |c| {
        if (c == '\'' or c == '\\') try out.append(a, '\\');
        try out.append(a, c);
    }
    try out.append(a, '\'');
    return out.toOwnedSlice(a);
}

// a declared type with self and parent named by the class they mean in
// scope (as php's compile of a class's code leaves them), or as written
// without one
fn resolveRelativeTypes(vm: *VM, text: []const u8, scope: ?[]const u8) ![]const u8 {
    const sc = scope orelse return text;
    if (std.ascii.findIgnoreCase(text, "self") == null and std.ascii.findIgnoreCase(text, "parent") == null) return text;
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(vm.allocator);
    var i: usize = 0;
    while (i < text.len) {
        const c = text[i];
        if (!(std.ascii.isAlphanumeric(c) or c == '_' or c == '\\' or c >= 0x80)) {
            try out.append(vm.allocator, c);
            i += 1;
            continue;
        }
        var j = i;
        while (j < text.len and (std.ascii.isAlphanumeric(text[j]) or text[j] == '_' or text[j] == '\\' or text[j] >= 0x80)) j += 1;
        const word = text[i..j];
        const parent: ?[]const u8 = if (vm.classes.get(sc)) |cd| cd.parent else null;
        if (std.ascii.eqlIgnoreCase(word, "self")) {
            try out.appendSlice(vm.allocator, vm.declaredClassName(sc));
        } else if (std.ascii.eqlIgnoreCase(word, "parent") and parent != null) {
            try out.appendSlice(vm.allocator, vm.declaredClassName(parent.?));
        } else try out.appendSlice(vm.allocator, word);
        i = j;
    }
    return vm.internName(out.items);
}

// a method registered as "Class::method": a user method or an internal one
fn fromMethod(vm: *VM, t: *Target, registered: []const u8, a: std.mem.Allocator) !void {
    const sep = std.mem.indexOf(u8, registered, "::").?;
    t.scope = registered[0..sep];
    if (vm.functions.get(registered)) |func| {
        try fromUser(vm, t, func, a);
        t.is_static = func.is_static;
        t.display = try vm.funcDisplayName(func);
        t.call_name = func.name[std.mem.indexOf(u8, func.name, "::").? + 2 ..];
        if (func.trait_origin.len == 0) {
            const declared = vm.declaredClassName(t.scope.?);
            t.display = try std.fmt.allocPrint(a, "{s}::{s}", .{ declared, try vm.phpMethodName(t.call_name) });
        }
        return;
    }
    try fromNative(vm, t, registered, a);
    t.display = registered;
    t.call_name = registered[sep + 2 ..];
}

// what a partial application of `callable` calls, resolved as a first-class
// callable is where the application is made
fn resolveTarget(vm: *VM, callable: Value, a: std.mem.Allocator) RuntimeError!Target {
    var t: Target = .{ .kind = .function, .display = "", .call_name = "" };
    if (callable == .object and std.mem.eql(u8, callable.object.class_name, "Closure")) {
        try closureTarget(vm, &t, callable.object, a);
        return t;
    }
    // $closure->__invoke(...): zend_get_closure_invoke_method, a method of
    // Closure taking the closure's parameters, whose defaults it doesn't know
    if (callable == .array and callable.array.entries.items.len == 2) {
        const first = callable.array.entries.items[0].value;
        const second = callable.array.entries.items[1].value;
        if (first == .object and std.mem.eql(u8, first.object.class_name, "Closure") and second == .string and std.ascii.eqlIgnoreCase(second.string.bytes(), "__invoke")) {
            try closureTarget(vm, &t, first.object, a);
            const params = try a.dupe(Param, t.params);
            for (params) |*p| if (p.default != .none) {
                p.default = .unknown;
            };
            t.params = params;
            t.kind = .method;
            t.object = first.object;
            t.closure = null;
            t.call_name = "__invoke";
            t.display = "Closure::__invoke";
            t.scope = "Closure";
            t.called_class = "Closure";
            t.is_static = false;
            t.non_static_closure = false;
            t.user = null;
            t.identity_name = "Closure::__invoke";
            return t;
        }
    }
    var held_pair: ?*PhpArray = null;
    var function: ?[]const u8 = null;
    var forwarded: ?[]const u8 = null;
    switch (try vm.callableClosureCheck(callable, &held_pair, &function, &forwarded)) {
        .ok => {},
        .failed => |failure| {
            try callables.setDynamicFailure(vm, failure);
            return error.RuntimeError;
        },
    }
    var resolved = callable;
    if (held_pair) |pair| resolved = .{ .array = pair };
    if (function) |registered| resolved = .{ .string = Value.String.borrowed(registered) };
    const callee = switch (try callables.resolveDynamic(vm, resolved)) {
        .callee => |c| c,
        .failure => |failure| {
            try callables.setDynamicFailure(vm, failure);
            return error.RuntimeError;
        },
    };
    switch (callee) {
        .function => |name| {
            if (vm.functions.get(name)) |func| {
                try fromUser(vm, &t, func, a);
                t.display = try vm.funcDisplayName(func);
                t.call_name = func.name;
            } else {
                try fromNative(vm, &t, name, a);
                t.display = name;
                t.call_name = name;
                t.forbid_dynamic = VM.forbidsDynamicCall(name);
                t.is_assert = std.ascii.eqlIgnoreCase(name, "assert");
            }
        },
        .closure => |obj| try closureTarget(vm, &t, obj, a),
        .invoke => |obj| {
            t.kind = .method;
            t.object = obj;
            t.called_class = obj.class_name;
            try fromMethod(vm, &t, try vm.resolveMethod(obj.class_name, "__invoke"), a);
        },
        .method => |m| {
            t.kind = .method;
            t.object = m.object;
            t.called_class = m.object.class_name;
            try fromMethod(vm, &t, m.registered orelse try vm.resolveMethod(m.object.class_name, m.name), a);
        },
        .static_method => |m| {
            t.kind = .static_method;
            t.called_class = forwarded orelse m.called_class;
            try fromMethod(vm, &t, m.registered, a);
            t.is_static = true;
        },
        .magic => |m| {
            // zend_get_call_trampoline_func: a variadic $arguments, run in the
            // scope the application is made in
            t.kind = .magic;
            t.object = m.object;
            t.called_class = m.called orelse (if (m.object) |o| o.class_name else m.class);
            t.call_name = m.name;
            t.display = try std.fmt.allocPrint(a, "{s}::{s}", .{ vm.declaredClassName(if (m.object) |o| o.class_name else m.class), m.name });
            t.variadic = .{ .name = "arguments", .type = "mixed" };
            t.scope = vm.currentDefiningClass();
            t.is_static = m.object == null;
            t.identity_name = try std.fmt.allocPrint(a, "magic:{s}:{s}", .{ m.class, m.name });
        },
        .engine => |e| return throwFmt(vm, "Error", "Cannot create partial application of {s}()", .{e.name}),
    }
    return t;
}

// a Closure called through `$fn`: a closure instance or one made from a
// callable, with the parameters of the function it runs
fn closureTarget(vm: *VM, t: *Target, obj: *PhpObject, a: std.mem.Allocator) RuntimeError!void {
    t.kind = .closure;
    t.closure = obj;
    t.call_name = "";
    if (obj.closureName()) |instance| {
        const func = vm.functions.get(instance) orelse return throwFmt(vm, "Error", "Closure has no function", .{});
        try fromUser(vm, t, func, a);
        t.display = try vm.funcDisplayName(func);
        t.is_static = func.is_static;
        t.non_static_closure = !func.is_static;
        t.scope = vm.closureDefClassByName(instance);
        const this = vm.closureThisByName(instance);
        if (this == .object) t.object = this.object;
        t.called_class = if (t.object) |o| o.class_name else t.scope;
        return;
    }
    // a closure made from a callable runs its function, which tells the
    // parameters
    const callable = obj.fakeCallable();
    var inner = try resolveTarget(vm, callable, a);
    inner.kind = .closure;
    inner.closure = obj;
    inner.non_static_closure = !inner.is_static;
    inner.forbid_dynamic = false;
    if (inner.kind == .closure and inner.object == null and callable == .array) {
        const first = callable.array.entries.items[0].value;
        if (first == .object) inner.object = first.object;
    }
    t.* = inner;
}

// zend_get_arg_offset_by_name: the parameter a name passes, null for one the
// function doesn't declare (or its variadic)
fn paramOffset(t: *const Target, name: []const u8) ?usize {
    for (t.params, 0..) |p, i| if (std.mem.eql(u8, p.name, name)) return i;
    return null;
}

fn paramAt(t: *const Target, offset: usize) Param {
    if (offset < t.params.len) return t.params[offset];
    return t.variadic.?;
}

fn mustBeByRef(t: *const Target, offset: usize) bool {
    if (offset < t.params.len) return t.params[offset].by_ref;
    if (t.variadic) |v| return v.by_ref;
    return false;
}

const Names = struct {
    params: []?[]const u8,
    variadic: ?[]const u8 = null,
    extra: ?[]const u8 = null,
    inner: ?[]const u8 = null,

    fn exists(self: *const Names, name: []const u8) bool {
        for (self.params) |p| if (p) |n| if (std.mem.eql(u8, n, name)) return true;
        if (self.variadic) |n| if (std.mem.eql(u8, n, name)) return true;
        if (self.extra) |n| if (std.mem.eql(u8, n, name)) return true;
        if (self.inner) |n| if (std.mem.eql(u8, n, name)) return true;
        return false;
    }
};

// zp_assign_names: every variable the closure uses gets a name, the
// placeholders the callee's own and the rest made unique
fn assignNames(a: std.mem.Allocator, t: *const Target, slots: []const Slot, variadic_partial: bool, has_extra: bool) !Names {
    var names: Names = .{ .params = try a.alloc(?[]const u8, slots.len) };
    @memset(names.params, null);
    const num_args = t.params.len;
    for (0..@min(slots.len, num_args)) |i| {
        if (slots[i] == .placeholder) names.params[i] = t.params[i].name;
    }
    if (variadic_partial) if (t.variadic) |v| {
        names.variadic = v.name;
    };
    var off = num_args;
    while (off < slots.len) : (off += 1) {
        if (slots[off] != .placeholder) continue;
        const orig = t.variadic.?.name;
        var n: u32 = 0;
        while (true) : (n += 1) {
            const candidate = try std.fmt.allocPrint(a, "{s}{d}", .{ orig, n });
            if (!names.exists(candidate)) {
                names.params[off] = candidate;
                break;
            }
        }
    }
    for (slots, 0..) |slot, i| {
        if (slot != .bound) continue;
        const orig = paramAt(t, @min(i, num_args)).name;
        var candidate = orig;
        var n: u32 = 2;
        while (names.exists(candidate)) : (n += 1) candidate = try std.fmt.allocPrint(a, "{s}{d}", .{ orig, n });
        names.params[i] = candidate;
    }
    if (has_extra) {
        var candidate: []const u8 = "extra_named_params";
        var n: u32 = 2;
        while (names.exists(candidate)) : (n += 1) candidate = try std.fmt.allocPrint(a, "extra_named_params{d}", .{n});
        names.extra = candidate;
    }
    if (t.kind == .closure) {
        var candidate: []const u8 = "fn";
        var n: u32 = 2;
        while (names.exists(candidate)) : (n += 1) candidate = try std.fmt.allocPrint(a, "fn{d}", .{n});
        names.inner = candidate;
    }
    return names;
}

fn validIdentifier(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name, 0..) |c, i| {
        const ok = c == '_' or c >= 0x80 or std.ascii.isAlphabetic(c) or (i > 0 and std.ascii.isDigit(c));
        if (!ok) return false;
    }
    return true;
}

// a literal for an array default, which the closure's own default then is
fn arraySource(a: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8), v: Value) !bool {
    switch (v) {
        .null => try out.appendSlice(a, "null"),
        .bool => |b| try out.appendSlice(a, if (b) "true" else "false"),
        .int => |i| try out.print(a, "{d}", .{i}),
        .float => |f| try out.appendSlice(a, try floatSource(a, f)),
        .string => |s| try out.appendSlice(a, try quoteString(a, s.bytes())),
        .array => |arr| {
            if (v.isEmptyArrayDefault()) {
                try out.appendSlice(a, "[]");
                return true;
            }
            try out.append(a, '[');
            for (arr.entries.items, 0..) |entry, i| {
                if (i > 0) try out.appendSlice(a, ", ");
                switch (entry.key) {
                    .int => |k| try out.print(a, "{d} => ", .{k}),
                    .string => |k| try out.print(a, "{s} => ", .{try quoteString(a, k.bytes())}),
                }
                if (!try arraySource(a, out, entry.value)) return false;
            }
            try out.append(a, ']');
        },
        else => return false,
    }
    return true;
}

const Layout = struct {
    slots: []Slot,
    // the closure's parameter each placeholder slot is
    param_of: []usize,
    num_params: usize,
    num_required: usize,
    names: Names,
};

// the forwarding call: the callee, with every slot as its variable, a skipped
// one moving the rest to named arguments, then the extra named arguments and
// the variadic ones
fn writeCall(a: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8), t: *const Target, lay: *const Layout, variadic_partial: bool, forward_superfluous: bool) !void {
    var close_extra = false;
    if (t.is_assert) {
        // assert() is called dynamically, or it would describe the
        // generated code on failure
        try out.appendSlice(a, "\\call_user_func('assert'");
        close_extra = true;
    } else switch (t.kind) {
        .closure => try out.print(a, "${s}(", .{lay.names.inner.?}),
        .function => try out.print(a, "\\{s}(", .{t.call_name}),
        .method, .static_method, .magic => {
            const via_this = t.object != null and t.kind != .static_method and !(t.kind == .magic and t.object == null);
            if (validIdentifier(t.call_name)) {
                try out.print(a, "{s}{s}(", .{ if (via_this) "$this->" else "static::", t.call_name });
            } else if (via_this) {
                try out.print(a, "$this->{{{s}}}(", .{try quoteString(a, t.call_name)});
            } else {
                try out.print(a, "\\call_user_func([static::class, {s}]", .{try quoteString(a, t.call_name)});
                close_extra = true;
            }
        },
    }
    var first = !close_extra;
    // past a skipped argument the rest go by name, which the callee fills
    // the skipped ones' defaults around; with extra named arguments to
    // unpack too they are unpacked with them (a named argument can't come
    // before an unpacking)
    var named = false;
    var merged: std.ArrayListUnmanaged(u8) = .empty;
    for (lay.slots, 0..) |slot, i| {
        // a skipped by-reference parameter gets its default as php passes
        // it, a value, which the call refuses
        if (slot == .undef and mustBeByRef(t, i) and !(named and lay.names.extra != null)) {
            if (!first) try out.appendSlice(a, ", ");
            first = false;
            if (named) try out.print(a, "{s}: ", .{paramAt(t, i).name});
            try out.appendSlice(a, "null");
            continue;
        }
        if (slot == .undef) {
            named = true;
            continue;
        }
        const name = lay.names.params[i].?;
        if (named and lay.names.extra != null) {
            if (merged.items.len > 0) try merged.appendSlice(a, ", ");
            try merged.print(a, "{s} => {s}${s}", .{ try quoteString(a, paramAt(t, i).name), if (mustBeByRef(t, i)) "&" else "", name });
            continue;
        }
        if (!first) try out.appendSlice(a, ", ");
        first = false;
        if (named) try out.print(a, "{s}: ", .{paramAt(t, i).name});
        try out.print(a, "${s}", .{name});
    }
    if (lay.names.extra) |extra| {
        if (!first) try out.appendSlice(a, ", ");
        first = false;
        if (merged.items.len > 0) {
            try out.print(a, "...([{s}] + ${s})", .{ merged.items, extra });
        } else try out.print(a, "...${s}", .{extra});
    }
    if (variadic_partial) {
        if (t.variadic != null) {
            if (!first) try out.appendSlice(a, ", ");
            try out.print(a, "...${s}", .{lay.names.variadic.?});
        } else if (forward_superfluous) {
            if (!first) try out.appendSlice(a, ", ");
            try out.print(a, "...\\array_slice(\\func_get_args(), {d})", .{lay.num_params});
        }
    }
    try out.append(a, ')');
}

fn writeParam(a: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8), p: Param, name: []const u8, variadic: bool, optional: bool, patch: *bool) !void {
    if (p.sensitive) try out.appendSlice(a, "#[\\SensitiveParameter] ");
    if (p.by_ref) try out.append(a, '&');
    if (variadic) try out.appendSlice(a, "...");
    try out.print(a, "${s}", .{name});
    if (!optional) return;
    switch (p.default) {
        .source => |text| try out.print(a, " = {s}", .{text}),
        .raw => |raw| {
            if (raw == .array and !raw.isEmptyArrayDefault()) {
                var lit: std.ArrayListUnmanaged(u8) = .empty;
                if (try arraySource(a, &lit, raw)) {
                    try out.print(a, " = {s}", .{lit.items});
                    return;
                }
            }
            try out.appendSlice(a, " = null");
            patch.* = true;
        },
        else => try out.appendSlice(a, " = null"),
    }
}

pub const Request = struct {
    callable: Value,
    positional: []const Value,
    sources: []const RefSource,
    named: *PhpArray,
    name: []const u8,
    desc: []const u8,
    file: []const u8,
    line: u32,
    site: usize,
};

pub fn create(vm: *VM, req: Request) RuntimeError!Value {
    var arena_state = std.heap.ArenaAllocator.init(vm.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    var t = try resolveTarget(vm, req.callable, a);
    const variadic_partial = req.desc[0] & 1 != 0;

    // the slots the arguments fill, as the call frame's argument slots would
    var slots: std.ArrayListUnmanaged(Slot) = .empty;
    var named_positions: std.StringArrayHashMapUnmanaged(usize) = .empty;
    var extra: std.ArrayListUnmanaged(struct { name: []const u8, value: ?Value, source: RefSource = .none }) = .empty;
    var pos_i: usize = 0;
    var i: usize = 1;
    while (i < req.desc.len) {
        const kind = req.desc[i];
        i += 1;
        switch (kind) {
            'v' => {
                try slots.append(a, .{ .bound = .{ .value = req.positional[pos_i], .source = req.sources[pos_i] } });
                pos_i += 1;
            },
            'p' => {
                try slots.append(a, .placeholder);
                pos_i += 1;
            },
            else => {
                const len = req.desc[i];
                const name = req.desc[i + 1 .. i + 1 + len];
                i += 1 + len;
                const placeholder = kind == 'q';
                const offset = paramOffset(&t, name) orelse {
                    if (t.variadic == null) return throwFmt(vm, "Error", "Unknown named parameter ${s}", .{name});
                    for (extra.items) |e| if (std.mem.eql(u8, e.name, name)) return throwFmt(vm, "Error", "Named parameter ${s} overwrites previous argument", .{name});
                    if (placeholder) {
                        try extra.append(a, .{ .name = name, .value = null });
                        continue;
                    }
                    const entry = req.named.getPtr(.{ .string = Value.String.borrowed(name) }).?;
                    const index = (@intFromPtr(entry) - @intFromPtr(req.named.entries.items.ptr)) / @sizeOf(PhpArray.Entry);
                    try extra.append(a, .{ .name = name, .value = entry.value, .source = vm.namedArgSource(req.named, index) });
                    continue;
                };
                while (slots.items.len <= offset) try slots.append(a, .undef);
                switch (slots.items[offset]) {
                    .undef => {},
                    .placeholder => return throwFmt(vm, "Error", "Named parameter ${s} overwrites previous placeholder", .{name}),
                    .bound => return throwFmt(vm, "Error", "Named parameter ${s} overwrites previous argument", .{name}),
                }
                if (placeholder) {
                    slots.items[offset] = .placeholder;
                    try named_positions.put(a, name, named_positions.count());
                } else {
                    const entry = req.named.getPtr(.{ .string = Value.String.borrowed(name) }).?;
                    const index = (@intFromPtr(entry) - @intFromPtr(req.named.entries.items.ptr)) / @sizeOf(PhpArray.Entry);
                    slots.items[offset] = .{ .bound = .{ .value = entry.value, .source = vm.namedArgSource(req.named, index) } };
                }
            },
        }
    }

    if (t.forbid_dynamic) return throwFmt(vm, "Error", "Cannot call {s}() dynamically", .{t.call_name});
    // zp_args_check
    for (extra.items) |e| if (e.value == null) return throwFmt(vm, "Error", "Cannot use named placeholder for unknown or variadic parameter ${s}", .{e.name});
    // a value named for a by-reference variadic
    if (t.variadic) |v| if (v.by_ref) for (extra.items) |e| {
        if (e.source != .none) continue;
        const msg = try vm.cannotPassByReference(t.registered, @intCast(@min(slots.items.len, 0xFD)));
        defer vm.allocator.free(msg);
        try vm.setPendingException("Error", msg);
        return error.RuntimeError;
    };
    const argc = slots.items.len;
    const num_args = t.params.len;
    if (argc < t.required) {
        if (!variadic_partial) {
            const limit: []const u8 = if (num_args <= t.required) "exactly" else "at least";
            return throwFmt(vm, "ArgumentCountError", "Partial application of {s}() expects {s} {d} arguments, {d} given", .{ t.display, limit, t.required, argc });
        }
    } else if (argc > num_args and t.variadic == null) {
        return throwFmt(vm, "ArgumentCountError", "Partial application of {s}() expects at most {d} arguments, {d} given", .{ t.display, num_args, argc });
    }

    // the closure's parameters: the positional placeholders, the named ones
    // in their order, then the ones `...` adds for every slot left
    if (variadic_partial) while (slots.items.len < num_args) try slots.append(a, .undef);
    const all = slots.items;
    const param_of = try a.alloc(usize, all.len);
    var num_params: usize = 0;
    var num_positional: usize = 0;
    for (all[0..argc], 0..) |slot, off| {
        if (slot != .placeholder) continue;
        num_params += 1;
        const pname = paramAt(&t, @min(off, num_args)).name;
        if (named_positions.get(pname)) |np| {
            param_of[off] = num_positional + np;
        } else {
            param_of[off] = num_positional;
            num_positional += 1;
        }
    }
    var num_required = num_params;
    if (variadic_partial) {
        for (all, 0..) |*slot, off| {
            if (off < argc and slot.* != .undef) continue;
            slot.* = .placeholder;
            num_params += 1;
            const param_offset = num_params - 1;
            param_of[off] = param_offset;
            if (off < num_args) {
                if (off < t.required) num_required = @max(num_required, param_offset + 1);
            } else num_required = param_offset + 1;
        }
    }
    const lay: Layout = .{
        .slots = all,
        .param_of = param_of,
        .num_params = num_params,
        .num_required = num_required,
        .names = try assignNames(a, &t, all, variadic_partial, extra.items.len > 0),
    };

    // the closure's source
    var src: std.ArrayListUnmanaged(u8) = .empty;
    try src.appendSlice(a, "<?php");
    // the closure is php's on the line it is made, unless an internal
    // default it took was compiled
    var line = req.line;
    for (all, 0..) |slot, off| {
        if (off >= num_args or !t.params[off].via_ast) continue;
        if (slot == .undef or (slot == .placeholder and param_of[off] >= num_required)) line = 1;
    }
    for (1..@max(line, 1)) |_| try src.append(a, '\n');
    try src.appendSlice(a, " return ");
    // the callee's message and attribute are copied once compiled
    if (t.no_discard != null) try src.appendSlice(a, "#[\\NoDiscard] ");
    const is_static_closure = t.object == null and !t.non_static_closure;
    if (is_static_closure) try src.appendSlice(a, "static ");
    try src.appendSlice(a, "function ");
    if (t.returns_ref) try src.append(a, '&');
    try src.append(a, '(');
    // parameters by position, which ones need their default patched in
    const order = try a.alloc(usize, num_params);
    for (all, 0..) |slot, off| {
        if (slot == .placeholder) order[param_of[off]] = off;
    }
    const patch = try a.alloc(bool, num_params + 1);
    @memset(patch, false);
    for (order, 0..) |off, pi| {
        if (pi > 0) try src.appendSlice(a, ", ");
        const p = paramAt(&t, @min(off, num_args));
        const optional = pi >= num_required;
        if (optional and off < num_args) {
            switch (p.default) {
                .unknown, .none => return throwFmt(vm, "ArgumentCountError", "{s}(): Argument #{d} (${s}) must be passed explicitly, because the default value is not known", .{ t.display, off + 1, p.name }),
                else => {},
            }
        }
        var param = p;
        param.by_ref = mustBeByRef(&t, off);
        try writeParam(a, &src, param, lay.names.params[off].?, false, optional and off < num_args, &patch[pi]);
    }
    if (variadic_partial) if (t.variadic) |v| {
        if (num_params > 0) try src.appendSlice(a, ", ");
        var unused = false;
        try writeParam(a, &src, v, lay.names.variadic.?, true, false, &unused);
    };
    try src.append(a, ')');
    // the bound values, in php's order: the closure, the arguments, the
    // extra named ones
    var uses: std.ArrayListUnmanaged(u8) = .empty;
    if (lay.names.inner) |inner| try uses.print(a, "${s}", .{inner});
    for (all, 0..) |slot, off| {
        if (slot != .bound) continue;
        if (uses.items.len > 0) try uses.appendSlice(a, ", ");
        if (mustBeByRef(&t, off)) try uses.append(a, '&');
        try uses.print(a, "${s}", .{lay.names.params[off].?});
    }
    if (lay.names.extra) |e| {
        if (uses.items.len > 0) try uses.appendSlice(a, ", ");
        try uses.print(a, "${s}", .{e});
    }
    if (uses.items.len > 0) try src.print(a, " use ({s})", .{uses.items});
    // the skipped arguments: a required one is an error now
    for (all, 0..) |slot, off| {
        if (slot != .undef) continue;
        if (off < t.required) return throwFmt(vm, "ArgumentCountError", "{s}(): Argument #{d} (${s}) not passed", .{ t.display, off + 1, t.params[off].name });
        switch (t.params[off].default) {
            .unknown, .none => return throwFmt(vm, "ArgumentCountError", "{s}(): Argument #{d} (${s}) must be passed explicitly, because the default value is not known", .{ t.display, off + 1, t.params[off].name }),
            else => {},
        }
    }
    const is_void = std.mem.eql(u8, t.return_type, "void");
    const ret: []const u8 = if (is_void) "" else "return ";
    try src.appendSlice(a, " { ");
    if (variadic_partial and t.variadic == null) {
        try src.print(a, "if (\\func_num_args() <= {d}) {{ {s}", .{ num_params, ret });
        try writeCall(a, &src, &t, &lay, variadic_partial, false);
        try src.print(a, "; }} else {{ {s}", .{ret});
        try writeCall(a, &src, &t, &lay, variadic_partial, true);
        try src.appendSlice(a, "; }");
    } else {
        try src.appendSlice(a, ret);
        try writeCall(a, &src, &t, &lay, variadic_partial, false);
        try src.append(a, ';');
    }
    try src.appendSlice(a, " };");

    // the compiled closure, kept per call site and callee
    var key: std.ArrayListUnmanaged(u8) = .empty;
    try key.print(a, "{x}:{x}:{s}:{s}\x00", .{ req.site, t.identity, t.identity_name, req.name });
    try key.appendSlice(a, src.items);
    const compile_name = if (vm.pfa_cache.get(key.items)) |cached| cached else blk: {
        // php compiles `return f(...)` for a never-returning callee too,
        // which its compiler refuses
        if (std.mem.eql(u8, t.return_type, "never")) {
            const at = vm.currentSourcePosition();
            return vm.raiseCompileFatal("A never-returning function must not return", at);
        }
        const made = try compileClosure(vm, &t, req, src.items, order, patch, num_args, variadic_partial);
        try vm.pfa_cache.put(vm.allocator, try vm.internName(key.items), made);
        break :blk made;
    };
    // zp_bind: the bound arguments, checked against their parameters' types
    // as the scope making the application would pass them
    var caps: std.ArrayListUnmanaged(VM.PartialCapture) = .empty;
    if (lay.names.inner) |inner| try caps.append(a, .{ .name = try vm.internName(try std.fmt.allocPrint(a, "${s}", .{inner})), .value = .{ .object = t.closure.? } });
    const strict = vm.currentStrictTypes();
    for (all, 0..) |slot, off| {
        if (slot != .bound) continue;
        const param = if (off < num_args) t.params[off] else t.variadic;
        var value = slot.bound.value;
        var cell: ?*Value = null;
        if (mustBeByRef(&t, off)) {
            cell = try vm.argSourceCell(slot.bound.source);
            if (cell) |c| value = c.* else {
                const msg = try vm.cannotPassByReference(t.registered, @intCast(@min(off, 0xFD)));
                defer vm.allocator.free(msg);
                try vm.setPendingException("Error", msg);
                return error.RuntimeError;
            }
        }
        if (param) |p| if (p.type.len > 0) {
            const scope = t.scope;
            if (try vm.verifyDeclaredType(value, p.type, scope, strict)) |accepted| {
                value = accepted;
                if (cell) |c| if (!std.meta.eql(c.*, accepted)) vm.setCell(c, accepted);
            } else {
                const shown = try vm.resolvedTypeText(p.type, scope);
                if (off < num_args)
                    return throwFmt(vm, "TypeError", "{s}(): Argument #{d} (${s}) must be of type {s}, {s} given", .{ t.display, off + 1, p.name, shown, VM.valueTypeName(value) });
                return throwFmt(vm, "TypeError", "{s}(): Argument #{d} must be of type {s}, {s} given", .{ t.display, off + 1, shown, VM.valueTypeName(value) });
            }
        };
        try caps.append(a, .{ .name = try vm.internName(try std.fmt.allocPrint(a, "${s}", .{lay.names.params[off].?})), .value = value, .cell = cell });
    }
    if (lay.names.extra) |e| {
        const arr = try vm.allocArray();
        for (extra.items) |entry| {
            const v = entry.value.?;
            try arr.set(vm.allocator, .{ .string = Value.String.borrowed(try vm.internName(entry.name)) }, v);
        }
        try caps.append(a, .{ .name = try vm.internName(try std.fmt.allocPrint(a, "${s}", .{e})), .value = .{ .array = arr } });
    }

    // the closure runs in the function's class (or, for __call, where the
    // application is made), with php's dummy scope for an object and none
    var scope = t.scope;
    if (scope == null and t.object != null) scope = "Closure";
    const this: Value = if (t.object != null and !(t.kind == .closure and t.is_static)) .{ .object = t.object.? } else .null;
    return vm.newPartialInstance(compile_name, caps.items, this, scope, t.called_class);
}

fn warnDeprecatedTypeNames(vm: *VM, ty: []const u8) RuntimeError!void {
    var parts = std.mem.tokenizeAny(u8, ty, "|&()? ");
    while (parts.next()) |part| {
        const word = compiler_class.deprecatedClassNameWord(part) orelse continue;
        const msg = try std.fmt.allocPrint(vm.allocator, "Using \"{s}\" as a type name is deprecated since {s}", .{ word, if (std.mem.eql(u8, word, "_")) "8.4" else "8.6" });
        defer vm.allocator.free(msg);
        try vm.raiseError(VM.E_DEPRECATED, msg);
        if (vm.pending_exception != null) return error.RuntimeError;
    }
}

// compiles the closure's source as php compiles the generated AST, and
// fixes up what source can't say: the defaults the callee keeps compiled,
// the declared types, php's name for it and where it was made
fn compileClosure(vm: *VM, t: *const Target, req: Request, source: []const u8, order: []const usize, patch: []const bool, num_args: usize, variadic_partial: bool) RuntimeError![]const u8 {
    const owned = try vm.allocator.dupe(u8, source);
    var ast = parser_mod.parse(vm.allocator, owned) catch {
        vm.allocator.free(owned);
        return error.OutOfMemory;
    };
    defer ast.deinit();
    const file = try vm.internName(req.file);
    var diag: ?compiler_mod.Diagnostic = null;
    if (ast.errors.len > 0) {
        vm.allocator.free(owned);
        return throwFmt(vm, "Error", "Cannot compile partial application", .{});
    }
    var result = compiler_mod.compileWithOrigin(&ast, vm.allocator, .{ .file_path = file, .diagnostic = &diag }) catch {
        vm.allocator.free(owned);
        if (diag) |d| return throwFmt(vm, "Error", "Cannot compile partial application: {s}", .{d.message()});
        return throwFmt(vm, "Error", "Cannot compile partial application", .{});
    };
    const heap_result = vm.allocator.create(CompileResult) catch {
        result.deinit();
        vm.allocator.free(owned);
        return error.OutOfMemory;
    };
    heap_result.* = result;
    try heap_result.string_allocs.append(vm.allocator, owned);
    try vm.compile_results.append(vm.allocator, heap_result);

    var func: ?*ObjFunction = null;
    for (heap_result.functions.items) |*f| {
        if (std.mem.startsWith(u8, f.name, "__closure")) func = f;
    }
    const f = func orelse return throwFmt(vm, "Error", "Cannot compile partial application", .{});
    f.display_name = try vm.internName(req.name);
    f.partial = if (t.kind == .closure) 2 else 1;
    f.default_scope = if (t.user) |u| vm.functionScopeOf(u) else null;
    // the defaults compiled as the callee compiled them
    const defaults: []Value = @constCast(f.defaults);
    for (order, 0..) |off, pi| {
        if (!patch[pi] or off >= num_args or pi >= defaults.len) continue;
        defaults[pi] = t.params[off].default.raw;
    }
    // the parameters' declared types and the return type
    var count = order.len;
    if (variadic_partial and t.variadic != null) count += 1;
    const types = try vm.allocator.alloc([]const u8, count);
    var typed = false;
    // a class's code names its class in self and parent, a trait's keeps
    // them as written
    const relative_scope: ?[]const u8 = if (t.scope) |sc| blk: {
        if (vm.traits.contains(sc)) break :blk null;
        if (t.user) |u| if (u.trait_origin.len > 0) break :blk null;
        break :blk sc;
    } else null;
    for (order, 0..) |off, pi| {
        types[pi] = try resolveRelativeTypes(vm, paramAt(t, @min(off, num_args)).type, relative_scope);
        if (types[pi].len > 0) typed = true;
    }
    if (count > order.len) {
        types[order.len] = try resolveRelativeTypes(vm, t.variadic.?.type, relative_scope);
        if (types[order.len].len > 0) typed = true;
    }
    const return_type = try resolveRelativeTypes(vm, t.return_type, relative_scope);
    f.has_param_types = typed;
    if (return_type.len > 0) f.return_type_kind = compiler_class.returnTypeKind(return_type);
    var replaced = false;
    for (heap_result.type_hints.items) |*th| {
        if (!std.mem.eql(u8, th.name, f.name)) continue;
        if (th.param_types.len > 0) vm.allocator.free(th.param_types);
        th.param_types = types;
        th.return_type = return_type;
        replaced = true;
    }
    if (!replaced) try heap_result.type_hints.append(vm.allocator, .{ .name = f.name, .param_types = types, .return_type = return_type });
    try vm.registerResultFunctions(heap_result);
    // what compiling the generated closure raised, once per call site. the
    // types aren't in the source: php's compile of them deprecates `_`, `let`
    // and `is` as type names again
    try vm.raiseCompileWarnings(heap_result);
    for (types) |ty| try warnDeprecatedTypeNames(vm, ty);
    try warnDeprecatedTypeNames(vm, t.return_type);
    // #[\NoDiscard] is inherited with its arguments as the callee has them
    f.no_discard = t.no_discard;
    if (t.no_discard != null) if (t.user) |u| if (vm.functionAttributesOf(u).attrs) |attrs| {
        var kept: std.ArrayListUnmanaged(vm_mod.AttributeDef) = .empty;
        errdefer kept.deinit(vm.allocator);
        for (attrs) |attr| {
            const name = if (attr.name.len > 0 and attr.name[0] == '\\') attr.name[1..] else attr.name;
            if (std.ascii.eqlIgnoreCase(name, "NoDiscard")) try kept.append(vm.allocator, attr);
        }
        const list = try kept.toOwnedSlice(vm.allocator);
        try vm.partial_attrs.append(vm.allocator, .{ .name = f.name, .list = list });
        try vm.function_attributes.put(vm.allocator, f.name, list);
    };
    for (heap_result.type_hints.items) |th| {
        if (th.cond_id != 0) continue;
        try vm_mod.g_type_info.put(vm.allocator, th.name, .{ .param_types = th.param_types, .return_type = th.return_type });
    }
    return f.name;
}
