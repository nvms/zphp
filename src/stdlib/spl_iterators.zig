const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const spl = @import("spl.zig");
const VM = vm_mod.VM;
const NativeResult = vm_mod.NativeResult;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub fn register(vm: *VM, a: Allocator) !void {
    // RecursiveIterator interface
    var rec_iter = vm_mod.InterfaceDef{ .name = "RecursiveIterator" };
    rec_iter.parent = "Iterator";
    try rec_iter.methods.append(a, "hasChildren");
    try rec_iter.methods.append(a, "getChildren");
    try vm.interfaces.put(a, "RecursiveIterator", rec_iter);

    var outer_iter = vm_mod.InterfaceDef{ .name = "OuterIterator" };
    outer_iter.parent = "Iterator";
    try outer_iter.methods.append(a, "getInnerIterator");
    try vm.interfaces.put(a, "OuterIterator", outer_iter);

    var seekable_iter = vm_mod.InterfaceDef{ .name = "SeekableIterator" };
    seekable_iter.parent = "Iterator";
    try seekable_iter.methods.append(a, "seek");
    try vm.interfaces.put(a, "SeekableIterator", seekable_iter);

    // MultipleIterator
    var mi_def = ClassDef{ .name = "MultipleIterator" };
    try mi_def.interfaces.append(a, "Iterator");
    for ([_][]const u8{ "__construct", "attachIterator", "detachIterator", "containsIterator", "countIterators", "rewind", "valid", "current", "key", "next", "getFlags", "setFlags" }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "attachIterator")) 2 else if (std.mem.eql(u8, m, "detachIterator") or std.mem.eql(u8, m, "containsIterator") or std.mem.eql(u8, m, "setFlags")) 1 else 0;
        try mi_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try mi_def.constants.put(a, "MIT_NEED_ANY", .{ .int = 0 });
    try mi_def.constants.put(a, "MIT_NEED_ALL", .{ .int = 1 });
    try mi_def.constants.put(a, "MIT_KEYS_NUMERIC", .{ .int = 0 });
    try mi_def.constants.put(a, "MIT_KEYS_ASSOC", .{ .int = 2 });
    try vm.classes.put(a, "MultipleIterator", mi_def);
    try vm.native_fns.put(a, "MultipleIterator::__construct", miConstruct);
    try vm.native_fns.put(a, "MultipleIterator::attachIterator", miAttach);
    try vm.native_fns.put(a, "MultipleIterator::detachIterator", miDetach);
    try vm.native_fns.put(a, "MultipleIterator::containsIterator", miContains);
    try vm.native_fns.put(a, "MultipleIterator::countIterators", miCountIterators);
    try vm.native_fns.put(a, "MultipleIterator::rewind", miRewind);
    try vm.native_fns.put(a, "MultipleIterator::valid", miValid);
    try vm.native_fns.put(a, "MultipleIterator::current", miCurrent);
    try vm.native_fns.put(a, "MultipleIterator::key", miKey);
    try vm.native_fns.put(a, "MultipleIterator::next", miNext);
    try vm.native_fns.put(a, "MultipleIterator::getFlags", miGetFlags);
    try vm.native_fns.put(a, "MultipleIterator::setFlags", miSetFlags);

    // RecursiveArrayIterator (extends ArrayIterator, adds hasChildren/getChildren)
    var rai_def = ClassDef{ .name = "RecursiveArrayIterator" };
    rai_def.parent = "ArrayIterator";
    try rai_def.interfaces.append(a, "RecursiveIterator");
    try rai_def.methods.put(a, "hasChildren", .{ .name = "hasChildren", .arity = 0 });
    try rai_def.methods.put(a, "getChildren", .{ .name = "getChildren", .arity = 0 });
    try rai_def.constants.put(a, "CHILD_ARRAYS_ONLY", .{ .int = CHILD_ARRAYS_ONLY });
    try vm.classes.put(a, "RecursiveArrayIterator", rai_def);
    try vm.native_fns.put(a, "RecursiveArrayIterator::hasChildren", raiHasChildren);
    try vm.native_fns.put(a, "RecursiveArrayIterator::getChildren", raiGetChildren);

    try @import("spl_iterator_classes.zig").register(vm, a);
}

// ==========================================
// helpers
// ==========================================

fn getThis(ctx: *NativeContext) ?*PhpObject {
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

fn objGetInt(obj: *PhpObject, key: []const u8) i64 {
    const v = obj.get(key);
    if (v == .int) return v.int;
    return 0;
}

// MultipleIterator
// ==========================================

fn miConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const flags: i64 = if (args.len >= 1) Value.toInt(args[0]) else 1;
    try obj.set(ctx.allocator, "__mi_flags", .{ .int = flags });
    const iters = try ctx.createArray();
    const keys = try ctx.createArray();
    try obj.set(ctx.allocator, "__mi_iters", .{ .array = iters });
    try obj.set(ctx.allocator, "__mi_keys", .{ .array = keys });
    return NativeResult.scalar(.null);
}

fn miAttach(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    if (args[0] != .object and args[0] != .generator) return NativeResult.scalar(.null);
    const iters_v = obj.get("__mi_iters");
    const keys_v = obj.get("__mi_keys");
    if (iters_v != .array or keys_v != .array) return NativeResult.scalar(.null);
    try iters_v.array.append(ctx.allocator, args[0]);
    if (args.len >= 2 and (args[1] == .string or args[1] == .int)) {
        try keys_v.array.append(ctx.allocator, args[1]);
    } else {
        try keys_v.array.append(ctx.allocator, .null);
    }
    return NativeResult.scalar(.null);
}

fn miDetach(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.null);
    const iters_v = obj.get("__mi_iters");
    const keys_v = obj.get("__mi_keys");
    if (iters_v != .array or keys_v != .array) return NativeResult.scalar(.null);
    var i: usize = 0;
    while (i < iters_v.array.entries.items.len) : (i += 1) {
        const e = iters_v.array.entries.items[i];
        if (e.value == .object and e.value.object == args[0].object) {
            _ = iters_v.array.entries.orderedRemove(i);
            if (i < keys_v.array.entries.items.len) _ = keys_v.array.entries.orderedRemove(i);
            return NativeResult.scalar(.null);
        }
    }
    return NativeResult.scalar(.null);
}

fn miContains(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const iters_v = obj.get("__mi_iters");
    if (iters_v != .array) return NativeResult.scalar(.{ .bool = false });
    for (iters_v.array.entries.items) |e| {
        if (e.value == .object and e.value.object == args[0].object) return NativeResult.scalar(.{ .bool = true });
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn miCountIterators(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const iters_v = obj.get("__mi_iters");
    if (iters_v != .array) return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = iters_v.array.length() });
}

fn miCallValid(ctx: *NativeContext, v: Value) !bool {
    if (v == .object) {
        const r = try ctx.vm.callMethod(v.object, "valid", &.{});
        return r.isTruthy();
    } else if (v == .generator) {
        return v.generator.state != .completed;
    }
    return false;
}

fn miCallCurrent(ctx: *NativeContext, v: Value) !Value {
    if (v == .object) return try ctx.vm.callMethod(v.object, "current", &.{});
    if (v == .generator) return v.generator.current_value;
    return .null;
}

fn miCallKey(ctx: *NativeContext, v: Value) !Value {
    if (v == .object) return try ctx.vm.callMethod(v.object, "key", &.{});
    if (v == .generator) return v.generator.current_key;
    return .null;
}

fn miCallNext(ctx: *NativeContext, v: Value) !void {
    if (v == .object) {
        _ = try ctx.vm.callMethod(v.object, "next", &.{});
    } else if (v == .generator) {
        try ctx.vm.resumeGenerator(v.generator, .null);
    }
}

fn miCallRewind(ctx: *NativeContext, v: Value) !void {
    if (v == .object) {
        _ = try ctx.vm.callMethod(v.object, "rewind", &.{});
    } else if (v == .generator) {
        // generator auto-starts on first valid()/current() call; if not yet
        // started, kick it off so current/key are populated
        if (v.generator.state == .created) try ctx.vm.resumeGenerator(v.generator, .null);
    }
}

fn miRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const iters_v = obj.get("__mi_iters");
    if (iters_v != .array) return NativeResult.scalar(.null);
    for (iters_v.array.entries.items) |e| try miCallRewind(ctx, e.value);
    return NativeResult.scalar(.null);
}

fn miValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const iters_v = obj.get("__mi_iters");
    if (iters_v != .array or iters_v.array.length() == 0) return NativeResult.scalar(.{ .bool = false });
    const flags = objGetInt(obj, "__mi_flags");
    const need_all = (flags & 1) != 0;
    var any: bool = false;
    var all: bool = true;
    for (iters_v.array.entries.items) |e| {
        if (try miCallValid(ctx, e.value)) any = true else all = false;
    }
    return NativeResult.scalar(.{ .bool = if (need_all) all else any });
}

fn miCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const iters_v = obj.get("__mi_iters");
    const keys_v = obj.get("__mi_keys");
    if (iters_v != .array) return NativeResult.scalar(.null);
    const flags = objGetInt(obj, "__mi_flags");
    const assoc = (flags & 2) != 0;
    const result = try ctx.createArray();
    var idx: i64 = 0;
    for (iters_v.array.entries.items, 0..) |e, i| {
        var v: Value = .null;
        if (try miCallValid(ctx, e.value)) v = try miCallCurrent(ctx, e.value);
        if (assoc and keys_v == .array and i < keys_v.array.entries.items.len) {
            const k = keys_v.array.entries.items[i].value;
            if (k == .string) try result.set(ctx.allocator, .{ .string = k.string }, v) else try result.append(ctx.allocator, v);
        } else {
            try result.set(ctx.allocator, .{ .int = idx }, v);
            idx += 1;
        }
    }
    return NativeResult.borrowed(.{ .array = result });
}

fn miKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const iters_v = obj.get("__mi_iters");
    const keys_v = obj.get("__mi_keys");
    if (iters_v != .array) return NativeResult.scalar(.null);
    const flags = objGetInt(obj, "__mi_flags");
    const assoc = (flags & 2) != 0;
    const result = try ctx.createArray();
    var idx: i64 = 0;
    for (iters_v.array.entries.items, 0..) |e, i| {
        var v: Value = .null;
        if (try miCallValid(ctx, e.value)) v = try miCallKey(ctx, e.value);
        if (assoc and keys_v == .array and i < keys_v.array.entries.items.len) {
            const k = keys_v.array.entries.items[i].value;
            if (k == .string) try result.set(ctx.allocator, .{ .string = k.string }, v) else try result.append(ctx.allocator, v);
        } else {
            try result.set(ctx.allocator, .{ .int = idx }, v);
            idx += 1;
        }
    }
    return NativeResult.borrowed(.{ .array = result });
}

fn miNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const iters_v = obj.get("__mi_iters");
    if (iters_v != .array) return NativeResult.scalar(.null);
    for (iters_v.array.entries.items) |e| try miCallNext(ctx, e.value);
    return NativeResult.scalar(.null);
}

fn miGetFlags(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = objGetInt(obj, "__mi_flags") });
}

fn miSetFlags(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__mi_flags", .{ .int = Value.toInt(args[0]) });
    return NativeResult.scalar(.null);
}

// ==========================================
// RecursiveArrayIterator
// ==========================================

// RecursiveArrayIterator::CHILD_ARRAYS_ONLY
const CHILD_ARRAYS_ONLY = 4;

fn raiHasChildren(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const cur = try spl.iteratorCurrent(ctx, obj) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = cur == .array or (cur == .object and spl.iteratorFlags(obj) & CHILD_ARRAYS_ONLY == 0) });
}

// an object element that is already one of these iterators is the child
// itself; any other element becomes the storage of a new one
fn raiGetChildren(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const cur = try spl.iteratorCurrent(ctx, obj) orelse return NativeResult.scalar(.null);
    if (cur == .object) {
        if (spl.iteratorFlags(obj) & CHILD_ARRAYS_ONLY != 0) return NativeResult.scalar(.null);
        if (ctx.vm.isInstanceOf(cur.object.class_name, obj.class_name)) return NativeResult.share(cur);
    }
    const child = try ctx.createObject(obj.class_name);
    _ = try ctx.vm.callMethod(child, "__construct", &.{ cur, .{ .int = spl.iteratorFlags(obj) } });
    return NativeResult.borrowed(.{ .object = child });
}
