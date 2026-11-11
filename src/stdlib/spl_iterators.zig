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
