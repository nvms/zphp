const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub fn register(vm: *VM, a: Allocator) !void {
    // Countable interface
    var countable = vm_mod.InterfaceDef{ .name = "Countable" };
    try countable.methods.append(a, "count");
    try vm.interfaces.put(a, "Countable", countable);

    // ArrayAccess interface
    var array_access = vm_mod.InterfaceDef{ .name = "ArrayAccess" };
    try array_access.methods.append(a, "offsetGet");
    try array_access.methods.append(a, "offsetSet");
    try array_access.methods.append(a, "offsetExists");
    try array_access.methods.append(a, "offsetUnset");
    try vm.interfaces.put(a, "ArrayAccess", array_access);

    // Iterator interface
    var iterator = vm_mod.InterfaceDef{ .name = "Iterator" };
    try iterator.methods.append(a, "current");
    try iterator.methods.append(a, "key");
    try iterator.methods.append(a, "next");
    try iterator.methods.append(a, "rewind");
    try iterator.methods.append(a, "valid");
    try vm.interfaces.put(a, "Iterator", iterator);

    // IteratorAggregate interface
    var iter_agg = vm_mod.InterfaceDef{ .name = "IteratorAggregate" };
    try iter_agg.methods.append(a, "getIterator");
    try vm.interfaces.put(a, "IteratorAggregate", iter_agg);

    // SplStack
    var stack_def = ClassDef{ .name = "SplStack" };
    try stack_def.interfaces.append(a, "Countable");
    try stack_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 0 });
    try stack_def.methods.put(a, "push", .{ .name = "push", .arity = 1 });
    try stack_def.methods.put(a, "pop", .{ .name = "pop", .arity = 0 });
    try stack_def.methods.put(a, "top", .{ .name = "top", .arity = 0 });
    try stack_def.methods.put(a, "bottom", .{ .name = "bottom", .arity = 0 });
    try stack_def.methods.put(a, "count", .{ .name = "count", .arity = 0 });
    try stack_def.methods.put(a, "isEmpty", .{ .name = "isEmpty", .arity = 0 });
    try stack_def.methods.put(a, "shift", .{ .name = "shift", .arity = 0 });
    try stack_def.methods.put(a, "unshift", .{ .name = "unshift", .arity = 1 });
    try stack_def.methods.put(a, "rewind", .{ .name = "rewind", .arity = 0 });
    try stack_def.methods.put(a, "current", .{ .name = "current", .arity = 0 });
    try stack_def.methods.put(a, "key", .{ .name = "key", .arity = 0 });
    try stack_def.methods.put(a, "next", .{ .name = "next", .arity = 0 });
    try stack_def.methods.put(a, "valid", .{ .name = "valid", .arity = 0 });
    try stack_def.methods.put(a, "toArray", .{ .name = "toArray", .arity = 0 });
    try vm.classes.put(a, "SplStack", stack_def);

    try vm.native_fns.put(a, "SplStack::__construct", stackConstruct);
    try vm.native_fns.put(a, "SplStack::push", stackPush);
    try vm.native_fns.put(a, "SplStack::pop", stackPop);
    try vm.native_fns.put(a, "SplStack::top", stackTop);
    try vm.native_fns.put(a, "SplStack::bottom", stackBottom);
    try vm.native_fns.put(a, "SplStack::count", stackCount);
    try vm.native_fns.put(a, "SplStack::isEmpty", stackIsEmpty);
    try vm.native_fns.put(a, "SplStack::shift", stackShift);
    try vm.native_fns.put(a, "SplStack::unshift", stackUnshift);
    try vm.native_fns.put(a, "SplStack::rewind", stackRewind);
    try vm.native_fns.put(a, "SplStack::current", stackCurrent);
    try vm.native_fns.put(a, "SplStack::key", stackKey);
    try vm.native_fns.put(a, "SplStack::next", stackNext);
    try vm.native_fns.put(a, "SplStack::valid", stackValid);
    try vm.native_fns.put(a, "SplStack::toArray", stackToArray);

    // ArrayObject
    var ao_def = ClassDef{ .name = "ArrayObject" };
    try ao_def.interfaces.append(a, "Countable");
    try ao_def.interfaces.append(a, "ArrayAccess");
    try ao_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try ao_def.methods.put(a, "offsetGet", .{ .name = "offsetGet", .arity = 1 });
    try ao_def.methods.put(a, "offsetSet", .{ .name = "offsetSet", .arity = 2 });
    try ao_def.methods.put(a, "offsetExists", .{ .name = "offsetExists", .arity = 1 });
    try ao_def.methods.put(a, "offsetUnset", .{ .name = "offsetUnset", .arity = 1 });
    try ao_def.methods.put(a, "count", .{ .name = "count", .arity = 0 });
    try ao_def.methods.put(a, "append", .{ .name = "append", .arity = 1 });
    try ao_def.methods.put(a, "getArrayCopy", .{ .name = "getArrayCopy", .arity = 0 });
    try ao_def.methods.put(a, "getIterator", .{ .name = "getIterator", .arity = 0 });
    try ao_def.methods.put(a, "setFlags", .{ .name = "setFlags", .arity = 1 });
    try ao_def.methods.put(a, "getFlags", .{ .name = "getFlags", .arity = 0 });
    try vm.classes.put(a, "ArrayObject", ao_def);

    try vm.native_fns.put(a, "ArrayObject::__construct", aoConstruct);
    try vm.native_fns.put(a, "ArrayObject::offsetGet", aoOffsetGet);
    try vm.native_fns.put(a, "ArrayObject::offsetSet", aoOffsetSet);
    try vm.native_fns.put(a, "ArrayObject::offsetExists", aoOffsetExists);
    try vm.native_fns.put(a, "ArrayObject::offsetUnset", aoOffsetUnset);
    try vm.native_fns.put(a, "ArrayObject::count", aoCount);
    try vm.native_fns.put(a, "ArrayObject::append", aoAppend);
    try vm.native_fns.put(a, "ArrayObject::getArrayCopy", aoGetArrayCopy);
    try vm.native_fns.put(a, "ArrayObject::getIterator", aoGetIterator);
    try vm.native_fns.put(a, "ArrayObject::setFlags", aoSetFlags);
    try vm.native_fns.put(a, "ArrayObject::getFlags", aoGetFlags);
}

fn getThis(ctx: *NativeContext) ?*PhpObject {
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

fn getData(obj: *PhpObject) ?*PhpArray {
    const v = obj.get("__data");
    if (v != .array) return null;
    return v.array;
}

fn ensureData(ctx: *NativeContext, obj: *PhpObject) !*PhpArray {
    if (getData(obj)) |arr| return arr;
    const arr = try ctx.allocator.create(PhpArray);
    arr.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, arr);
    try obj.set(ctx.allocator, "__data", .{ .array = arr });
    return arr;
}

// --- SplStack ---

fn stackConstruct(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    _ = try ensureData(ctx, obj);
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    return .null;
}

fn stackPush(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = try ensureData(ctx, obj);
    if (args.len >= 1) try arr.append(ctx.allocator, args[0]);
    return .null;
}

fn stackPop(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    if (arr.entries.items.len == 0) return .null;
    const last = arr.entries.items[arr.entries.items.len - 1].value;
    arr.entries.items.len -= 1;
    return last;
}

fn stackTop(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    if (arr.entries.items.len == 0) return .null;
    return arr.entries.items[arr.entries.items.len - 1].value;
}

fn stackBottom(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    if (arr.entries.items.len == 0) return .null;
    return arr.entries.items[0].value;
}

fn stackCount(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    const arr = getData(obj) orelse return .{ .int = 0 };
    return .{ .int = arr.length() };
}

fn stackIsEmpty(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = true };
    const arr = getData(obj) orelse return .{ .bool = true };
    return .{ .bool = arr.entries.items.len == 0 };
}

fn stackShift(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    if (arr.entries.items.len == 0) return .null;
    const first = arr.entries.items[0].value;
    std.mem.copyForwards(PhpArray.Entry, arr.entries.items[0 .. arr.entries.items.len - 1], arr.entries.items[1..arr.entries.items.len]);
    arr.entries.items.len -= 1;
    return first;
}

fn stackUnshift(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = try ensureData(ctx, obj);
    if (args.len == 0) return .null;
    try arr.entries.insert(ctx.allocator, 0, .{ .key = .{ .int = 0 }, .value = args[0] });
    return .null;
}

// iterator: SplStack iterates in LIFO order (top to bottom)
fn stackRewind(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse {
        try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
        return .null;
    };
    // cursor starts at end (top of stack)
    try obj.set(ctx.allocator, "__cursor", .{ .int = @as(i64, @intCast(arr.entries.items.len)) - 1 });
    return .null;
}

fn stackCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    const cursor = Value.toInt(obj.get("__cursor"));
    if (cursor < 0 or cursor >= arr.length()) return .{ .bool = false };
    return arr.entries.items[@intCast(cursor)].value;
}

fn stackKey(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    const cursor = Value.toInt(obj.get("__cursor"));
    const len = arr.length();
    if (cursor < 0 or cursor >= len) return .null;
    // key is distance from top
    return .{ .int = len - 1 - cursor };
}

fn stackNext(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const cursor = Value.toInt(obj.get("__cursor"));
    try obj.set(ctx.allocator, "__cursor", .{ .int = cursor - 1 });
    return .null;
}

fn stackValid(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const arr = getData(obj) orelse return .{ .bool = false };
    const cursor = Value.toInt(obj.get("__cursor"));
    return .{ .bool = cursor >= 0 and cursor < arr.length() };
}

fn stackToArray(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse {
        const empty = try ctx.allocator.create(PhpArray);
        empty.* = .{};
        try ctx.vm.arrays.append(ctx.allocator, empty);
        return .{ .array = empty };
    };
    // return a copy in LIFO order
    const copy = try ctx.allocator.create(PhpArray);
    copy.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, copy);
    var i: usize = arr.entries.items.len;
    var key: i64 = 0;
    while (i > 0) {
        i -= 1;
        try copy.set(ctx.allocator, .{ .int = key }, arr.entries.items[i].value);
        key += 1;
    }
    return .{ .array = copy };
}

// --- ArrayObject ---

fn aoConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len >= 1 and args[0] == .array) {
        try obj.set(ctx.allocator, "__data", args[0]);
    } else {
        _ = try ensureData(ctx, obj);
    }
    try obj.set(ctx.allocator, "__flags", .{ .int = 0 });
    return .null;
}

fn aoOffsetGet(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    if (args.len == 0) return .null;
    return arr.get(args[0].toArrayKey());
}

fn aoOffsetSet(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = try ensureData(ctx, obj);
    if (args.len < 2) return .null;
    if (args[0] == .null) {
        try arr.append(ctx.allocator, args[1]);
    } else {
        try arr.set(ctx.allocator, args[0].toArrayKey(), args[1]);
    }
    return .null;
}

fn aoOffsetExists(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const arr = getData(obj) orelse return .{ .bool = false };
    if (args.len == 0) return .{ .bool = false };
    const key = args[0].toArrayKey();
    for (arr.entries.items) |entry| {
        if (entry.key.eql(key)) return .{ .bool = true };
    }
    return .{ .bool = false };
}

fn aoOffsetUnset(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    if (args.len == 0) return .null;
    const key = args[0].toArrayKey();
    for (arr.entries.items, 0..) |entry, i| {
        if (entry.key.eql(key)) {
            _ = arr.entries.orderedRemove(i);
            return .null;
        }
    }
    return .null;
}

fn aoCount(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    const arr = getData(obj) orelse return .{ .int = 0 };
    return .{ .int = arr.length() };
}

fn aoAppend(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = try ensureData(ctx, obj);
    if (args.len >= 1) try arr.append(ctx.allocator, args[0]);
    return .null;
}

fn aoGetArrayCopy(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse {
        const empty = try ctx.allocator.create(PhpArray);
        empty.* = .{};
        try ctx.vm.arrays.append(ctx.allocator, empty);
        return .{ .array = empty };
    };
    const copy = try ctx.allocator.create(PhpArray);
    copy.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, copy);
    for (arr.entries.items) |entry| {
        try copy.set(ctx.allocator, entry.key, entry.value);
    }
    return .{ .array = copy };
}

fn aoGetIterator(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    // return the underlying array for foreach iteration
    return .{ .array = arr };
}

fn aoSetFlags(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len >= 1) try obj.set(ctx.allocator, "__flags", .{ .int = Value.toInt(args[0]) });
    return .null;
}

fn aoGetFlags(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    return .{ .int = Value.toInt(obj.get("__flags")) };
}
