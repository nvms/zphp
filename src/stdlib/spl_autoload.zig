// php's ext/spl/php_spl.c: the autoloader stack (spl_autoload_register,
// spl_autoload_unregister, spl_autoload_functions, spl_autoload_call), the
// default spl_autoload() with spl_autoload_extensions(), and class_parents,
// class_implements and class_uses.
//
// the stack is vm.autoload_callbacks: each entry is the callable as
// registered. php compares entries by what they resolve to (the function,
// its object, its class, a closure), which `identity` computes the same
// way, and lists them in spl_autoload_functions() by that resolution
const std = @import("std");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const PhpArray = value_mod.PhpArray;
const PhpObject = value_mod.PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeResult = vm_mod.NativeResult;
const NativeContext = vm_mod.NativeContext;
const callables = @import("../runtime/callables.zig");
const includes = @import("../runtime/includes.zig");
const class_names = @import("../runtime/class_names.zig");
const sic = @import("spl_iterator_classes.zig");

const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "spl_autoload_register", register },
    .{ "spl_autoload_unregister", unregister },
    .{ "spl_autoload_functions", functions },
    .{ "spl_autoload_call", call },
    .{ "spl_autoload", splAutoload },
    .{ "spl_autoload_extensions", extensions },
    .{ "class_parents", classParents },
    .{ "class_implements", classImplements },
    .{ "class_uses", classUses },
};

const default_extensions = ".inc,.php";

// ==========================================
// the stack
// ==========================================

// what php's autoload_func_info holds, enough to compare two entries and to
// list one
const Identity = struct {
    kind: enum { function, method, closure } = .function,
    // the function or method as declared
    name: []const u8 = "",
    // the lowercase key two entries compare by
    key: []const u8 = "",
    object: ?*PhpObject = null,
    // the calling scope a static method is listed under
    class: []const u8 = "",
    closure: ?*PhpObject = null,
};

// the entry's resolution, or null when it no longer resolves. key and
// name live in ctx allocations
fn identity(ctx: *NativeContext, callable: Value) RuntimeError!?Identity {
    const vm = ctx.vm;
    if (callable == .string and std.mem.eql(u8, callable.string.bytes(), "spl_autoload")) {
        return .{ .name = "spl_autoload", .key = "spl_autoload" };
    }
    const res = callables.resolveCallback(vm, callable, .{ .deprecations = false }) catch |err| {
        if (vm.pending_exception != null) return null;
        return err;
    };
    const callee = switch (res) {
        .callee => |c| c,
        .failure => return null,
    };
    switch (callee) {
        .closure => |c| return .{ .kind = .closure, .closure = c, .key = "{closure}" },
        .function => |name| {
            const declared = vm.functions.getKey(name) orelse vm.native_fns.getKey(name) orelse name;
            return .{ .name = declared, .key = try lower(ctx, declared) };
        },
        // php keeps any object it was given as the callable, as it keeps a
        // Closure, and lists it that way
        .invoke => |o| return .{ .kind = .closure, .closure = o, .key = "{closure}" },
        .method => |m| {
            const full = m.registered orelse (vm.resolveMethod(m.object.class_name, m.name) catch m.name);
            return .{ .kind = .method, .object = m.object, .name = methodPart(full), .key = try lower(ctx, full) };
        },
        .static_method => |sm| {
            return .{ .kind = .method, .name = methodPart(sm.registered), .class = sm.called_class, .key = try lower(ctx, sm.registered) };
        },
        .magic => |mg| {
            const key = try std.fmt.allocPrint(ctx.allocator, "{s}::{s}", .{ mg.class, mg.name });
            defer ctx.allocator.free(key);
            return .{ .kind = .method, .object = mg.object, .name = mg.name, .class = mg.class, .key = try lower(ctx, key) };
        },
    }
}

fn methodPart(full: []const u8) []const u8 {
    const sep = std.mem.indexOf(u8, full, "::") orelse return full;
    return full[sep + 2 ..];
}

fn lower(ctx: *NativeContext, s: []const u8) RuntimeError![]const u8 {
    const out = try ctx.allocator.alloc(u8, s.len);
    defer ctx.allocator.free(out);
    for (s, 0..) |c, i| out[i] = std.ascii.toLower(c);
    return ctx.createString(out);
}

// autoload_func_info_equals
fn same(a: Identity, b: Identity) bool {
    if (a.kind != b.kind) return false;
    if (a.closure != b.closure or a.object != b.object) return false;
    if (!std.mem.eql(u8, a.key, b.key)) return false;
    return std.ascii.eqlIgnoreCase(a.class, b.class);
}

fn findRegistered(ctx: *NativeContext, want: Identity) RuntimeError!?usize {
    var i: usize = 0;
    while (i < ctx.vm.autoload_callbacks.items.len) : (i += 1) {
        const have = (try identity(ctx, ctx.vm.autoload_callbacks.items[i])) orelse continue;
        if (same(have, want)) return i;
    }
    return null;
}

fn isAutoloadCall(id: Identity) bool {
    return id.kind == .function and std.mem.eql(u8, id.key, "spl_autoload_call");
}

fn argBool(ctx: *NativeContext, label: []const u8, args: []const Value, i: usize, pname: []const u8, default: bool) RuntimeError!bool {
    if (i >= args.len) return default;
    return switch (args[i]) {
        .bool => |b| b,
        .int, .float, .string => args[i].isTruthy(),
        .null => blk: {
            const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): Passing null to parameter #{d} (${s}) of type bool is deprecated", .{ label, i + 1, pname });
            defer ctx.allocator.free(msg);
            try ctx.vm.raiseError(VM.E_DEPRECATED, msg);
            break :blk false;
        },
        else => {
            try sic.typeError(ctx, label, i + 1, pname, "bool", args[i]);
            return error.RuntimeError;
        },
    };
}

fn register(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const label = "spl_autoload_register";
    if (!try sic.argCount(ctx, label, args.len, 0, 3)) return error.RuntimeError;
    const do_throw = try argBool(ctx, label, args, 1, "do_throw", true);
    const prepend = try argBool(ctx, label, args, 2, "prepend", false);
    if (!do_throw) {
        try ctx.vm.raiseError(8, "spl_autoload_register(): Argument #2 ($do_throw) has been ignored, spl_autoload_register() will always throw");
        if (sic.pending(ctx)) return error.RuntimeError;
    }
    const callable: Value = if (args.len > 0 and args[0] != .null) args[0] else .{ .string = Value.String.borrowed("spl_autoload") };
    const id = (try identity(ctx, callable)) orelse return sic.finish(ctx, NativeResult.scalar(.{ .bool = false }));
    if (isAutoloadCall(id)) return sic.throwNow(ctx, "ValueError", "spl_autoload_register(): Argument #1 ($callback) must not be the spl_autoload_call() function", .{});
    if (try findRegistered(ctx, id) != null) return NativeResult.scalar(.{ .bool = true });
    const stored = try storedCallable(ctx, callable, id);
    if (prepend) {
        try ctx.vm.autoload_callbacks.insert(ctx.vm.allocator, 0, stored);
    } else {
        try ctx.vm.autoload_callbacks.append(ctx.vm.allocator, stored);
    }
    return NativeResult.scalar(.{ .bool = true });
}

// the value kept on the stack, holding its own reference: a string or
// closure as given, an array as a fresh copy the caller can't change
fn storedCallable(ctx: *NativeContext, callable: Value, id: Identity) RuntimeError!Value {
    // a static method is kept by the class it resolved to where it was
    // registered ('self' names the registering class)
    if (callable == .array and id.kind == .method and id.object == null and id.class.len > 0) {
        const pair = try ctx.vm.allocArray();
        try pair.appendCopiedString(ctx.allocator, ctx.vm.declaredClassName(id.class));
        try pair.appendCopiedString(ctx.allocator, id.name);
        VM.retainValue(.{ .array = pair });
        return .{ .array = pair };
    }
    if (callable == .array) {
        const copy = try ctx.vm.allocArray();
        for (callable.array.entries.items) |e| try copy.append(ctx.allocator, if (e.ref) |r| r.* else e.value);
        VM.retainValue(.{ .array = copy });
        return .{ .array = copy };
    }
    if (callable == .string and callable.string.owner == null) {
        // a new string starts with its one reference
        return .{ .string = try Value.String.create(ctx.allocator, callable.string.bytes()) };
    }
    VM.retainValue(callable);
    return callable;
}

fn unregister(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const label = "spl_autoload_unregister";
    if (!try sic.argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const id = (try identity(ctx, args[0])) orelse return sic.finish(ctx, NativeResult.scalar(.{ .bool = false }));
    if (isAutoloadCall(id)) {
        try ctx.vm.raiseError(VM.E_DEPRECATED, "spl_autoload_unregister(): Using spl_autoload_call() as a callback for spl_autoload_unregister() is deprecated, to remove all registered autoloaders, call spl_autoload_unregister() for all values returned from spl_autoload_functions()");
        if (sic.pending(ctx)) return error.RuntimeError;
        for (ctx.vm.autoload_callbacks.items) |cb| ctx.vm.releaseValue(cb);
        ctx.vm.autoload_callbacks.clearRetainingCapacity();
        return NativeResult.scalar(.{ .bool = true });
    }
    const i = (try findRegistered(ctx, id)) orelse return NativeResult.scalar(.{ .bool = false });
    const removed = ctx.vm.autoload_callbacks.orderedRemove(i);
    ctx.vm.releaseValue(removed);
    return NativeResult.scalar(.{ .bool = true });
}

fn functions(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (!try sic.argCount(ctx, "spl_autoload_functions", args.len, 0, 0)) return error.RuntimeError;
    const out = try ctx.createArray();
    for (ctx.vm.autoload_callbacks.items) |cb| {
        const id = (try identity(ctx, cb)) orelse continue;
        switch (id.kind) {
            .closure => try out.append(ctx.allocator, .{ .object = id.closure.? }),
            .method => {
                const pair = try ctx.createArray();
                if (id.object) |o| {
                    try pair.append(ctx.allocator, .{ .object = o });
                } else try pair.appendCopiedString(ctx.allocator, ctx.vm.declaredClassName(id.class));
                try pair.appendCopiedString(ctx.allocator, id.name);
                try out.append(ctx.allocator, .{ .array = pair });
            },
            .function => try out.appendCopiedString(ctx.allocator, id.name),
        }
    }
    return NativeResult.borrowed(.{ .array = out });
}

// spl_perform_autoload: each autoloader in turn until the class exists;
// one added or removed by an autoloader is taken into account
pub fn performAutoload(ctx: *NativeContext, class_name: []const u8) RuntimeError!void {
    const vm = ctx.vm;
    const lookup = if (class_name.len > 0 and class_name[0] == '\\') class_name[1..] else class_name;
    var i: usize = 0;
    while (i < vm.autoload_callbacks.items.len) {
        const cb = vm.autoload_callbacks.items[i];
        VM.retainValue(cb);
        defer vm.releaseValue(cb);
        _ = try sic.callValue(ctx, cb, &.{.{ .string = Value.String.borrowed(class_name) }});
        if (sic.pending(ctx)) return;
        if (vm.classes.contains(lookup) or vm.interfaces.contains(lookup) or vm.traits.contains(lookup)) return;
        // php's hash position moves to the next bucket; one the autoloader
        // removed leaves a hole that the step passes over too
        i += 1;
    }
}

fn call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const label = "spl_autoload_call";
    if (!try sic.argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const name = (try sic.argString(ctx, label, args, 0, "class")) orelse return error.RuntimeError;
    defer name.release();
    try performAutoload(ctx, name.bytes());
    return sic.finishNull(ctx);
}

// ==========================================
// spl_autoload
// ==========================================

fn extensions(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const label = "spl_autoload_extensions";
    if (!try sic.argCount(ctx, label, args.len, 0, 1)) return error.RuntimeError;
    if (args.len > 0 and args[0] != .null) {
        const exts = (try sic.argString(ctx, label, args, 0, "file_extensions")) orelse return error.RuntimeError;
        defer exts.release();
        try setExtensions(ctx, exts.bytes());
    }
    return NativeResult.copyString(ctx.allocator, currentExtensions(ctx.vm));
}

fn currentExtensions(vm: *VM) []const u8 {
    return vm.spl_autoload_extensions orelse default_extensions;
}

fn setExtensions(ctx: *NativeContext, exts: []const u8) RuntimeError!void {
    const vm = ctx.vm;
    const copy = try vm.allocator.dupe(u8, exts);
    if (vm.spl_autoload_extensions) |old| vm.allocator.free(old);
    vm.spl_autoload_extensions = copy;
}

fn splAutoload(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const label = "spl_autoload";
    if (!try sic.argCount(ctx, label, args.len, 1, 2)) return error.RuntimeError;
    const class_s = (try sic.argString(ctx, label, args, 0, "class")) orelse return error.RuntimeError;
    defer class_s.release();
    var exts_s: ?Value.String = null;
    defer if (exts_s) |e| e.release();
    if (args.len > 1 and args[1] != .null) exts_s = (try sic.argString(ctx, label, args, 1, "file_extensions")) orelse return error.RuntimeError;
    const exts = try ctx.createString(if (exts_s) |e| e.bytes() else currentExtensions(ctx.vm));
    var name = class_s.bytes();
    if (name.len > 0 and name[0] == '\\') name = name[1..];
    const lc = try lower(ctx, name);
    var it = std.mem.splitScalar(u8, exts, ',');
    while (it.next()) |ext| {
        if (sic.pending(ctx)) break;
        if (try loadFile(ctx, lc, ext)) break;
    }
    return sic.finishNull(ctx);
}

// spl_autoload(): the file named by the lowercase class (namespace
// separators as directory separators) and the extension, found on the
// include path and required once. true when the class exists after it ran
fn loadFile(ctx: *NativeContext, lc_name: []const u8, ext: []const u8) RuntimeError!bool {
    const vm = ctx.vm;
    const file = try std.fmt.allocPrint(ctx.allocator, "{s}{s}", .{ lc_name, ext });
    defer ctx.allocator.free(file);
    for (file) |*c| if (c.* == '\\') {
        c.* = '/';
    };
    const path = (try includes.resolve(vm, file)) orelse return false;
    if (vm.ic.?.included.contains(path)) return false;
    var src: std.ArrayListUnmanaged(u8) = .empty;
    defer src.deinit(ctx.allocator);
    try src.appendSlice(ctx.allocator, "require_once '");
    for (path) |c| {
        if (c == '\\' or c == '\'') try src.append(ctx.allocator, '\\');
        try src.append(ctx.allocator, c);
    }
    try src.appendSlice(ctx.allocator, "';");
    _ = sic.guarded(ctx, VM.evalSource, .{ vm, src.items }) catch |err| return err;
    if (sic.pending(ctx)) return false;
    return vm.classes.contains(lc_name) or vm.interfaces.contains(lc_name) or vm.traits.contains(lc_name);
}

// ==========================================
// class_parents, class_implements, class_uses
// ==========================================

// spl_find_ce_by_name: the class, interface or trait's declared name, or
// null after the warning
fn findClass(ctx: *NativeContext, label: []const u8, args: []const Value) RuntimeError!?[]const u8 {
    if (!try sic.argCount(ctx, label, args.len, 1, 2)) return error.RuntimeError;
    const v = args[0];
    if (v == .object) return v.object.class_name;
    if (v != .string) {
        try sic.raise(ctx, "TypeError", "{s}(): Argument #1 ($object_or_class) must be of type object|string, {s} given", .{ label, v.valueName() });
        return error.RuntimeError;
    }
    const autoload = try argBool(ctx, label, args, 1, "autoload", true);
    const raw = v.string.bytes();
    const name = if (raw.len > 0 and raw[0] == '\\') raw[1..] else raw;
    const vm = ctx.vm;
    if (!known(vm, name) and autoload) {
        vm.tryAutoload(name) catch |err| if (vm.pending_exception == null) return err;
        if (sic.pending(ctx)) return error.RuntimeError;
    }
    if (vm.classes.getKey(name)) |k| return k;
    if (vm.interfaces.getKey(name)) |k| return k;
    if (vm.traits.getKey(name)) |k| return k;
    const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): Class {s} does not exist{s}", .{ label, raw, if (autoload) " and could not be loaded" else "" });
    defer ctx.allocator.free(msg);
    try vm.raiseError(VM.E_WARNING, msg);
    if (sic.pending(ctx)) return error.RuntimeError;
    return null;
}

fn known(vm: *VM, name: []const u8) bool {
    return vm.classes.contains(name) or vm.interfaces.contains(name) or vm.traits.contains(name);
}

fn addName(ctx: *NativeContext, arr: *PhpArray, name: []const u8) RuntimeError!void {
    const shown = ctx.vm.declaredClassName(name);
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(shown) }, .{ .string = Value.String.borrowed(shown) });
}

fn classParents(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const name = (try findClass(ctx, "class_parents", args)) orelse return NativeResult.scalar(.{ .bool = false });
    const out = try ctx.createArray();
    var parent = if (ctx.vm.classes.get(name)) |c| c.parent else null;
    while (parent) |p| {
        try addName(ctx, out, p);
        parent = if (ctx.vm.classes.get(p)) |c| c.parent else null;
    }
    return NativeResult.borrowed(.{ .array = out });
}

fn classImplements(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const name = (try findClass(ctx, "class_implements", args)) orelse return NativeResult.scalar(.{ .bool = false });
    return interfacesOf(ctx, name);
}

fn classUses(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const name = (try findClass(ctx, "class_uses", args)) orelse return NativeResult.scalar(.{ .bool = false });
    const used = if (ctx.vm.classes.get(name)) |cls| cls.used_traits.items else ctx.vm.trait_uses.get(name) orelse &.{};
    const out = try ctx.createArray();
    for (used) |t| try addName(ctx, out, t);
    return NativeResult.borrowed(.{ .array = out });
}

// a class's ce->interfaces table, in php's order (zend_inheritance.c).
// a user class or interface naming interfaces copies its parent's table,
// appends the names, then for each name appends that interface's table in
// reverse (zend_do_inherit_interfaces walks it backwards); one naming none
// takes its parent's table reversed. an internal class starts from its
// parent's reversed table and adds each interface followed by its reversed
// table (zend_class_implements)
fn ceInterfaces(vm: *VM, name: []const u8, out: *std.ArrayListUnmanaged([]const u8), a: std.mem.Allocator, depth: usize) RuntimeError!void {
    if (depth > 64) return;
    var parent: ?[]const u8 = null;
    var names: []const []const u8 = &.{};
    var single: [1][]const u8 = undefined;
    var internal = false;
    if (vm.interfaces.get(name)) |def| {
        if (def.parents.items.len > 0) {
            names = def.parents.items;
        } else if (def.parent) |p| {
            single[0] = p;
            names = &single;
        }
    } else if (vm.classes.get(name)) |def| {
        parent = def.parent;
        names = def.interfaces.items;
        internal = def.is_internal;
    } else return;
    var inherited: std.ArrayListUnmanaged([]const u8) = .empty;
    defer inherited.deinit(a);
    if (parent) |p| try ceInterfaces(vm, p, &inherited, a, depth + 1);
    if (internal) {
        try inheritReversed(vm, out, a, inherited.items);
        for (names) |iface| {
            if (contains(vm, out.items, iface)) continue;
            try out.append(a, iface);
            try inheritFrom(vm, out, a, iface, depth);
        }
        return;
    }
    if (names.len == 0) return inheritReversed(vm, out, a, inherited.items);
    try out.appendSlice(a, inherited.items);
    const own_start = out.items.len;
    for (names) |iface| try addUnique(vm, out, a, iface);
    const own_end = out.items.len;
    for (own_start..own_end) |i| try inheritFrom(vm, out, a, out.items[i], depth);
}

fn inheritFrom(vm: *VM, out: *std.ArrayListUnmanaged([]const u8), a: std.mem.Allocator, iface: []const u8, depth: usize) RuntimeError!void {
    var sub: std.ArrayListUnmanaged([]const u8) = .empty;
    defer sub.deinit(a);
    try ceInterfaces(vm, iface, &sub, a, depth + 1);
    try inheritReversed(vm, out, a, sub.items);
}

fn inheritReversed(vm: *VM, out: *std.ArrayListUnmanaged([]const u8), a: std.mem.Allocator, list: []const []const u8) RuntimeError!void {
    var i = list.len;
    while (i > 0) {
        i -= 1;
        try addUnique(vm, out, a, list[i]);
    }
}

fn contains(vm: *VM, list: []const []const u8, name: []const u8) bool {
    const shown = vm.declaredClassName(name);
    for (list) |x| if (std.ascii.eqlIgnoreCase(vm.declaredClassName(x), shown)) return true;
    return false;
}

fn addUnique(vm: *VM, out: *std.ArrayListUnmanaged([]const u8), a: std.mem.Allocator, name: []const u8) RuntimeError!void {
    if (!contains(vm, out.items, name)) try out.append(a, name);
}

fn interfacesOf(ctx: *NativeContext, class_name: []const u8) RuntimeError!NativeResult {
    var list: std.ArrayListUnmanaged([]const u8) = .empty;
    defer list.deinit(ctx.allocator);
    try ceInterfaces(ctx.vm, class_name, &list, ctx.allocator, 0);
    const result = try ctx.createArray();
    for (list.items) |iface| try addName(ctx, result, iface);
    return NativeResult.borrowed(.{ .array = result });
}
