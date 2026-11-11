// php's ext/spl/spl_dllist.c: SplDoublyLinkedList, SplQueue and SplStack.
//
// the list lives in hidden properties: its values in order (a packed array
// whose first `head` slots are spent, so shift is cheap) beside a parallel
// array of element ids. php's traverse pointer holds a reference to its
// element, which outlives the element's removal; zphp keeps the element's
// id, and an id no longer in the list is that detached element: valid, with
// no data and no neighbours. foreach walks the list with an iterator of its
// own (spl_dllist_it), kept on the loop's iterator marker
const std = @import("std");
const object_properties = @import("../runtime/object_properties.zig");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const PhpArray = value_mod.PhpArray;
const PhpObject = value_mod.PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeResult = vm_mod.NativeResult;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const sic = @import("spl_iterator_classes.zig");
const serialize = @import("serialize.zig");

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const IT_KEEP: i64 = 0;
pub const IT_FIFO: i64 = 0;
pub const IT_DELETE: i64 = 1;
pub const IT_LIFO: i64 = 2;
pub const IT_MASK: i64 = 3;
pub const IT_FIX: i64 = 4;

const P = struct {
    const values = "__dll_values";
    const ids = "__dll_ids";
    const head = "__dll_head";
    const next_id = "__dll_next_id";
    const flags = "__dll_flags";
    // the traverse pointer: an element id (0 for none), where it was last
    // found, and the traverse position
    const ptr = "__dll_ptr";
    const hint = "__dll_hint";
    const pos = "__dll_pos";
};

const MethodSpec = struct { []const u8, vm_mod.NativeFn };

fn registerClass(vm: *VM, a: Allocator, def: ClassDef, comptime name: []const u8, comptime methods: []const MethodSpec) !void {
    var d = def;
    inline for (methods) |m| {
        try d.methods.put(a, m[0], .{ .name = m[0], .arity = 0 });
        try vm.native_fns.put(a, name ++ "::" ++ m[0], m[1]);
    }
    try vm.classes.put(a, name, d);
}

pub fn register(vm: *VM, a: Allocator) !void {
    var dll = ClassDef{ .name = "SplDoublyLinkedList", .native_properties = debugProperties, .native_clone = cloneList };
    inline for (.{ "Iterator", "Countable", "ArrayAccess", "Serializable" }) |i| try dll.interfaces.append(a, i);
    inline for (.{ .{ "IT_MODE_LIFO", IT_LIFO }, .{ "IT_MODE_FIFO", IT_FIFO }, .{ "IT_MODE_DELETE", IT_DELETE }, .{ "IT_MODE_KEEP", IT_KEEP } }) |c| {
        try dll.constants.put(a, c[0], .{ .int = c[1] });
        try dll.constant_order.append(a, c[0]);
    }
    try registerClass(vm, a, dll, "SplDoublyLinkedList", &.{
        .{ "add", add },                    .{ "pop", pop },
        .{ "shift", shift },                .{ "push", push },
        .{ "unshift", unshift },            .{ "top", top },
        .{ "bottom", bottom },              .{ "__debugInfo", debugInfo },
        .{ "count", count },                .{ "isEmpty", isEmpty },
        .{ "setIteratorMode", setMode },    .{ "getIteratorMode", getMode },
        .{ "offsetExists", offsetExists },  .{ "offsetGet", offsetGet },
        .{ "offsetSet", offsetSet },        .{ "offsetUnset", offsetUnset },
        .{ "rewind", rewind },              .{ "current", current },
        .{ "key", key },                    .{ "prev", prev },
        .{ "next", next },                  .{ "valid", valid },
        .{ "unserialize", unserializeM },   .{ "serialize", serializeM },
        .{ "__serialize", serializeState }, .{ "__unserialize", unserializeState },
    });
    try registerClass(vm, a, .{ .name = "SplQueue", .parent = "SplDoublyLinkedList", .native_clone = cloneList }, "SplQueue", &.{
        .{ "enqueue", enqueue }, .{ "dequeue", dequeue },
    });
    try registerClass(vm, a, .{ .name = "SplStack", .parent = "SplDoublyLinkedList", .native_clone = cloneList }, "SplStack", &.{});
}

// ==========================================
// the list
// ==========================================

fn this(ctx: *NativeContext) RuntimeError!*PhpObject {
    return sic.thisObj(ctx) orelse {
        try sic.raise(ctx, "Error", "Object not initialized", .{});
        return error.RuntimeError;
    };
}

fn int(obj: *PhpObject, comptime name: []const u8) i64 {
    const v = obj.get(name);
    return if (v == .int) v.int else 0;
}

fn setInt(ctx: *NativeContext, obj: *PhpObject, comptime name: []const u8, n: i64) RuntimeError!void {
    try obj.set(ctx.allocator, name, .{ .int = n });
}

// the iterator flags a new object starts with: SplStack and SplQueue fix
// their direction
fn initialFlags(vm: *VM, class_name: []const u8) i64 {
    if (vm.isInstanceOf(class_name, "SplStack")) return IT_FIX | IT_LIFO;
    if (vm.isInstanceOf(class_name, "SplQueue")) return IT_FIX;
    return 0;
}

pub fn flagsOf(vm: *VM, obj: *PhpObject) i64 {
    const v = obj.get(P.flags);
    return if (v == .int) v.int else initialFlags(vm, obj.class_name);
}

const List = struct {
    values: *PhpArray,
    ids: *PhpArray,
    head: usize,

    fn len(self: List) usize {
        return self.values.entries.items.len - self.head;
    }

    fn at(self: List, i: usize) Value {
        const e = self.values.entries.items[self.head + i];
        return if (e.ref) |r| r.* else e.value;
    }

    fn idAt(self: List, i: usize) i64 {
        return self.ids.entries.items[self.head + i].value.int;
    }

    fn indexOf(self: List, id: i64, hint: i64) ?usize {
        if (id == 0) return null;
        if (hint >= 0 and hint < self.len() and self.idAt(@intCast(hint)) == id) return @intCast(hint);
        for (0..self.len()) |i| if (self.idAt(i) == id) return i;
        return null;
    }
};

fn emptyList(ctx: *NativeContext, obj: *PhpObject) RuntimeError!List {
    const values = try ctx.createArray();
    const ids = try ctx.createArray();
    try obj.set(ctx.allocator, P.values, .{ .array = values });
    try obj.set(ctx.allocator, P.ids, .{ .array = ids });
    try setInt(ctx, obj, P.head, 0);
    return .{ .values = values, .ids = ids, .head = 0 };
}

// the list to read
fn listOf(ctx: *NativeContext, obj: *PhpObject) RuntimeError!List {
    const v = obj.get(P.values);
    const i = obj.get(P.ids);
    if (v != .array or i != .array) return emptyList(ctx, obj);
    return .{ .values = v.array, .ids = i.array, .head = @intCast(int(obj, P.head)) };
}

// the list to change: separated from a clone that still shares it
fn writable(ctx: *NativeContext, obj: *PhpObject) RuntimeError!List {
    const l = try listOf(ctx, obj);
    if (l.values.refcount <= 1 and l.ids.refcount <= 1) return l;
    return rebuild(ctx, obj, l, null, null);
}

// a fresh copy of the list, with `insert` placed before index `at` (at the
// end when `at` is the length) and the element at `drop` left out
fn rebuild(ctx: *NativeContext, obj: *PhpObject, l: List, insert: ?struct { at: usize, value: Value, id: i64 }, drop: ?usize) RuntimeError!List {
    const values = try ctx.createArray();
    const ids = try ctx.createArray();
    for (0..l.len() + 1) |i| {
        if (insert) |ins| if (ins.at == i) {
            try values.append(ctx.allocator, ins.value);
            try ids.append(ctx.allocator, .{ .int = ins.id });
        };
        if (i == l.len()) break;
        if (drop) |d| if (d == i) continue;
        try values.append(ctx.allocator, l.at(i));
        try ids.append(ctx.allocator, .{ .int = l.idAt(i) });
    }
    try obj.set(ctx.allocator, P.values, .{ .array = values });
    try obj.set(ctx.allocator, P.ids, .{ .array = ids });
    try setInt(ctx, obj, P.head, 0);
    return .{ .values = values, .ids = ids, .head = 0 };
}

fn newId(ctx: *NativeContext, obj: *PhpObject) RuntimeError!i64 {
    const id = int(obj, P.next_id) + 1;
    try setInt(ctx, obj, P.next_id, id);
    return id;
}

fn listPush(ctx: *NativeContext, obj: *PhpObject, v: Value) RuntimeError!void {
    const l = try writable(ctx, obj);
    const id = try newId(ctx, obj);
    try l.values.append(ctx.allocator, v);
    try l.ids.append(ctx.allocator, .{ .int = id });
}

fn listUnshift(ctx: *NativeContext, obj: *PhpObject, v: Value) RuntimeError!void {
    var l = try writable(ctx, obj);
    const id = try newId(ctx, obj);
    if (l.head == 0) l = try rebuild(ctx, obj, l, .{ .at = 0, .value = v, .id = id }, null) else {
        l.head -= 1;
        VM.retainValue(v);
        l.values.entries.items[l.head].value = v;
        l.ids.entries.items[l.head].value = .{ .int = id };
        try setInt(ctx, obj, P.head, @intCast(l.head));
    }
}

// the removed value, with the reference the list held, for the caller to
// return or release; .undef when the list is empty
fn listPop(ctx: *NativeContext, obj: *PhpObject) RuntimeError!Value {
    const l = try writable(ctx, obj);
    if (l.len() == 0) return .undef;
    // a reference element (from __unserialize data) unbinds through a copy
    if (l.values.entries.items[l.values.entries.items.len - 1].ref != null) {
        const v = l.at(l.len() - 1);
        VM.retainValue(v);
        _ = try rebuild(ctx, obj, l, null, l.len() - 1);
        return v;
    }
    const e = l.values.entries.pop().?;
    _ = l.ids.entries.pop();
    l.values.next_int_key = @intCast(l.values.entries.items.len);
    l.ids.next_int_key = @intCast(l.ids.entries.items.len);
    if (l.len() == 0) _ = try emptyList(ctx, obj);
    return e.value;
}

fn listShift(ctx: *NativeContext, obj: *PhpObject) RuntimeError!Value {
    var l = try writable(ctx, obj);
    if (l.len() == 0) return .undef;
    if (l.values.entries.items[l.head].ref != null) {
        const v = l.at(0);
        VM.retainValue(v);
        _ = try rebuild(ctx, obj, l, null, 0);
        return v;
    }
    const v = l.values.entries.items[l.head].value;
    l.values.entries.items[l.head].value = .null;
    l.ids.entries.items[l.head].value = .{ .int = 0 };
    l.head += 1;
    try setInt(ctx, obj, P.head, @intCast(l.head));
    if (l.len() == 0) {
        _ = try emptyList(ctx, obj);
    } else if (l.head >= 16 and l.head * 2 >= l.values.entries.items.len) {
        l = try rebuild(ctx, obj, l, null, null);
    }
    return v;
}

// the returned value of pop/shift as the method's result
fn handOver(ctx: *NativeContext, v: Value) RuntimeError!NativeResult {
    if (v == .string) {
        if (v.string.owner != null) return NativeResult.takeString(v.string);
        return NativeResult.share(v);
    }
    // the list's reference is dropped as the call returns its result, as
    // array_pop does
    ctx.vm.releaseValue(v);
    return NativeResult.borrowed(v);
}

// ==========================================
// methods
// ==========================================

fn noArgs(ctx: *NativeContext, label: []const u8, args: []const Value) RuntimeError!void {
    if (!try sic.argCount(ctx, label, args.len, 0, 0)) return error.RuntimeError;
}

fn oneArg(ctx: *NativeContext, label: []const u8, args: []const Value) RuntimeError!void {
    if (!try sic.argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
}

fn argIndex(ctx: *NativeContext, label: []const u8, args: []const Value, i: usize) RuntimeError!i64 {
    return (try sic.argLong(ctx, label, args, i, "index", 0)) orelse error.RuntimeError;
}

fn outOfRange(ctx: *NativeContext, label: []const u8, comptime what: []const u8) RuntimeError!NativeResult {
    return sic.throwNow(ctx, "OutOfRangeException", "{s}(): Argument #1 ($index) " ++ what, .{label});
}

fn push(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try oneArg(ctx, "SplDoublyLinkedList::push", args);
    try listPush(ctx, obj, args[0]);
    return NativeResult.scalar(.null);
}

fn enqueue(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try oneArg(ctx, "SplQueue::enqueue", args);
    try listPush(ctx, obj, args[0]);
    return NativeResult.scalar(.null);
}

fn unshift(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try oneArg(ctx, "SplDoublyLinkedList::unshift", args);
    try listUnshift(ctx, obj, args[0]);
    return NativeResult.scalar(.null);
}

fn pop(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplDoublyLinkedList::pop", args);
    const v = try listPop(ctx, obj);
    if (v == .undef) return sic.throwNow(ctx, "RuntimeException", "Can't pop from an empty datastructure", .{});
    return handOver(ctx, v);
}

fn shiftAs(ctx: *NativeContext, args: []const Value, label: []const u8) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, label, args);
    const v = try listShift(ctx, obj);
    if (v == .undef) return sic.throwNow(ctx, "RuntimeException", "Can't shift from an empty datastructure", .{});
    return handOver(ctx, v);
}

fn shift(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return shiftAs(ctx, args, "SplDoublyLinkedList::shift");
}

fn dequeue(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return shiftAs(ctx, args, "SplQueue::dequeue");
}

fn top(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplDoublyLinkedList::top", args);
    const l = try listOf(ctx, obj);
    if (l.len() == 0) return sic.throwNow(ctx, "RuntimeException", "Can't peek at an empty datastructure", .{});
    return NativeResult.share(l.at(l.len() - 1));
}

fn bottom(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplDoublyLinkedList::bottom", args);
    const l = try listOf(ctx, obj);
    if (l.len() == 0) return sic.throwNow(ctx, "RuntimeException", "Can't peek at an empty datastructure", .{});
    return NativeResult.share(l.at(0));
}

fn count(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplDoublyLinkedList::count", args);
    return NativeResult.scalar(.{ .int = @intCast((try listOf(ctx, obj)).len()) });
}

// spl_dllist_object_count_elements: a subclass's count() decides
fn isEmpty(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplDoublyLinkedList::isEmpty", args);
    if (sic.userMethod(ctx.vm, obj.class_name, "count")) {
        const r = try sic.callOn(ctx, obj, "count", &.{});
        if (r == .undef) return error.RuntimeError;
        return NativeResult.scalar(.{ .bool = Value.toInt(r) == 0 });
    }
    return NativeResult.scalar(.{ .bool = (try listOf(ctx, obj)).len() == 0 });
}

fn setMode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplDoublyLinkedList::setIteratorMode";
    try oneArg(ctx, label, args);
    const value = (try sic.argLong(ctx, label, args, 0, "mode", 0)) orelse return error.RuntimeError;
    const f = flagsOf(ctx.vm, obj);
    if (f & IT_FIX != 0 and (f & IT_LIFO) != (value & IT_LIFO)) {
        return sic.throwNow(ctx, "RuntimeException", "Iterators' LIFO/FIFO modes for SplStack/SplQueue objects are frozen", .{});
    }
    const nf = (value & IT_MASK) | (f & IT_FIX);
    try setInt(ctx, obj, P.flags, nf);
    return NativeResult.scalar(.{ .int = nf });
}

fn getMode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplDoublyLinkedList::getIteratorMode", args);
    return NativeResult.scalar(.{ .int = flagsOf(ctx.vm, obj) });
}

// spl_ptr_llist_offset: the element `offset` steps from the head, or from
// the tail for a LIFO list
fn offsetIndex(l: List, offset: i64, backward: bool) usize {
    const o: usize = @intCast(offset);
    return if (backward) l.len() - 1 - o else o;
}

fn offsetExists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplDoublyLinkedList::offsetExists";
    try oneArg(ctx, label, args);
    const index = try argIndex(ctx, label, args, 0);
    const n: i64 = @intCast((try listOf(ctx, obj)).len());
    return NativeResult.scalar(.{ .bool = index >= 0 and index < n });
}

fn offsetGet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplDoublyLinkedList::offsetGet";
    try oneArg(ctx, label, args);
    const index = try argIndex(ctx, label, args, 0);
    const l = try listOf(ctx, obj);
    if (index < 0 or index >= l.len()) return outOfRange(ctx, label, "is out of range");
    return NativeResult.share(l.at(offsetIndex(l, index, flagsOf(ctx.vm, obj) & IT_LIFO != 0)));
}

fn offsetSet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplDoublyLinkedList::offsetSet";
    if (!try sic.argCount(ctx, label, args.len, 2, 2)) return error.RuntimeError;
    if (args[0] == .null) {
        try listPush(ctx, obj, args[1]);
        return NativeResult.scalar(.null);
    }
    const index = try argIndex(ctx, label, args, 0);
    const l = try writable(ctx, obj);
    if (index < 0 or index >= l.len()) return outOfRange(ctx, label, "is out of range");
    const i = l.head + offsetIndex(l, index, flagsOf(ctx.vm, obj) & IT_LIFO != 0);
    const entry = &l.values.entries.items[i];
    VM.retainValue(args[1]);
    if (entry.ref) |r| {
        const old = r.*;
        r.* = args[1];
        ctx.vm.releaseValue(old);
    } else {
        const old = entry.value;
        entry.value = args[1];
        ctx.vm.releaseValue(old);
    }
    return NativeResult.scalar(.null);
}

fn offsetUnset(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplDoublyLinkedList::offsetUnset";
    try oneArg(ctx, label, args);
    const index = try argIndex(ctx, label, args, 0);
    const l = try writable(ctx, obj);
    if (index < 0 or index >= l.len()) return outOfRange(ctx, label, "is out of range");
    const i = offsetIndex(l, index, flagsOf(ctx.vm, obj) & IT_LIFO != 0);
    // a traverse pointer on the element lets go of it
    if (int(obj, P.ptr) == l.idAt(i)) try setInt(ctx, obj, P.ptr, 0);
    _ = try rebuild(ctx, obj, l, null, i);
    return NativeResult.scalar(.null);
}

fn add(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplDoublyLinkedList::add";
    if (!try sic.argCount(ctx, label, args.len, 2, 2)) return error.RuntimeError;
    const index = try argIndex(ctx, label, args, 0);
    const l = try writable(ctx, obj);
    if (index < 0 or index > l.len()) return outOfRange(ctx, label, "is out of range");
    if (index == l.len()) {
        try listPush(ctx, obj, args[1]);
        return NativeResult.scalar(.null);
    }
    // the new element goes before the one at the offset, in list order
    const lifo = flagsOf(ctx.vm, obj) & IT_LIFO != 0;
    const before = offsetIndex(l, index, lifo);
    const id = try newId(ctx, obj);
    _ = try rebuild(ctx, obj, l, .{ .at = before, .value = args[1], .id = id }, null);
    return NativeResult.scalar(.null);
}

// ==========================================
// traversal
// ==========================================

pub const Cursor = struct { ptr: i64, hint: i64, pos: i64 };

fn cursorOf(obj: *PhpObject) Cursor {
    return .{ .ptr = int(obj, P.ptr), .hint = int(obj, P.hint), .pos = int(obj, P.pos) };
}

fn storeCursor(ctx: *NativeContext, obj: *PhpObject, c: Cursor) RuntimeError!void {
    try setInt(ctx, obj, P.ptr, c.ptr);
    try setInt(ctx, obj, P.hint, c.hint);
    try setInt(ctx, obj, P.pos, c.pos);
}

// spl_dllist_it_helper_rewind
pub fn cursorRewind(ctx: *NativeContext, obj: *PhpObject, flags: i64) RuntimeError!Cursor {
    const l = try listOf(ctx, obj);
    if (l.len() == 0) return .{ .ptr = 0, .hint = 0, .pos = if (flags & IT_LIFO != 0) -1 else 0 };
    if (flags & IT_LIFO != 0) return .{ .ptr = l.idAt(l.len() - 1), .hint = @intCast(l.len() - 1), .pos = @as(i64, @intCast(l.len())) - 1 };
    return .{ .ptr = l.idAt(0), .hint = 0, .pos = 0 };
}

// the element under the cursor: its index, or null when the cursor is on
// nothing or on a detached element
pub fn cursorIndex(ctx: *NativeContext, obj: *PhpObject, c: Cursor) RuntimeError!?usize {
    const l = try listOf(ctx, obj);
    return l.indexOf(c.ptr, c.hint);
}

pub fn cursorData(ctx: *NativeContext, obj: *PhpObject, c: Cursor) RuntimeError!?Value {
    const l = try listOf(ctx, obj);
    const i = l.indexOf(c.ptr, c.hint) orelse return null;
    return l.at(i);
}

// spl_dllist_it_helper_move_forward
pub fn cursorForward(ctx: *NativeContext, obj: *PhpObject, c: Cursor, flags: i64) RuntimeError!Cursor {
    if (c.ptr == 0) return c;
    var out = c;
    const l = try listOf(ctx, obj);
    const at = l.indexOf(c.ptr, c.hint);
    if (flags & IT_LIFO != 0) {
        if (at) |i| {
            out.ptr = if (i > 0) l.idAt(i - 1) else 0;
            out.hint = @as(i64, @intCast(i)) - 1;
        } else out.ptr = 0;
        out.pos -= 1;
        if (flags & IT_DELETE != 0) {
            const v = try listPop(ctx, obj);
            if (v != .undef) ctx.vm.releaseValue(v);
        }
    } else {
        if (at) |i| {
            out.ptr = if (i + 1 < l.len()) l.idAt(i + 1) else 0;
            out.hint = @intCast(i + 1);
        } else out.ptr = 0;
        if (flags & IT_DELETE != 0) {
            const v = try listShift(ctx, obj);
            if (v != .undef) ctx.vm.releaseValue(v);
            out.hint -= 1;
        } else out.pos += 1;
    }
    return out;
}

fn rewind(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplDoublyLinkedList::rewind", args);
    try storeCursor(ctx, obj, try cursorRewind(ctx, obj, flagsOf(ctx.vm, obj)));
    return NativeResult.scalar(.null);
}

fn valid(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplDoublyLinkedList::valid", args);
    return NativeResult.scalar(.{ .bool = int(obj, P.ptr) != 0 });
}

fn current(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplDoublyLinkedList::current", args);
    const v = (try cursorData(ctx, obj, cursorOf(obj))) orelse return NativeResult.scalar(.null);
    return NativeResult.share(v);
}

fn key(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplDoublyLinkedList::key", args);
    return NativeResult.scalar(.{ .int = int(obj, P.pos) });
}

fn next(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplDoublyLinkedList::next", args);
    try storeCursor(ctx, obj, try cursorForward(ctx, obj, cursorOf(obj), flagsOf(ctx.vm, obj)));
    return NativeResult.scalar(.null);
}

fn prev(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplDoublyLinkedList::prev", args);
    try storeCursor(ctx, obj, try cursorForward(ctx, obj, cursorOf(obj), flagsOf(ctx.vm, obj) ^ IT_LIFO));
    return NativeResult.scalar(.null);
}

// foreach's own iterator (spl_dllist_get_iterator), kept on the loop's
// marker: it starts where the object's traverse pointer is, with the
// object's direction and delete flags
pub fn iterBegin(ctx: *NativeContext, obj: *PhpObject, marker: *PhpObject) RuntimeError!void {
    const f = flagsOf(ctx.vm, obj) & IT_MASK;
    try marker.set(ctx.allocator, "__dll_it_flags", .{ .int = f });
    const c = try cursorRewind(ctx, obj, f);
    try storeIter(ctx, marker, c);
}

fn iterCursor(marker: *PhpObject) Cursor {
    return .{ .ptr = int(marker, "__dll_it_ptr"), .hint = int(marker, "__dll_it_hint"), .pos = int(marker, "__dll_it_pos") };
}

fn storeIter(ctx: *NativeContext, marker: *PhpObject, c: Cursor) RuntimeError!void {
    try setInt(ctx, marker, "__dll_it_ptr", c.ptr);
    try setInt(ctx, marker, "__dll_it_hint", c.hint);
    try setInt(ctx, marker, "__dll_it_pos", c.pos);
}

pub fn iterValid(marker: *PhpObject) bool {
    return int(marker, "__dll_it_ptr") != 0;
}

pub fn iterCurrent(ctx: *NativeContext, obj: *PhpObject, marker: *PhpObject) RuntimeError!Value {
    return (try cursorData(ctx, obj, iterCursor(marker))) orelse .null;
}

pub fn iterKey(marker: *PhpObject) Value {
    return .{ .int = int(marker, "__dll_it_pos") };
}

pub fn iterNext(ctx: *NativeContext, obj: *PhpObject, marker: *PhpObject) RuntimeError!void {
    const c = try cursorForward(ctx, obj, iterCursor(marker), int(marker, "__dll_it_flags"));
    try storeIter(ctx, marker, c);
}

// ==========================================
// debug view, clone and serialization
// ==========================================

fn listArray(ctx: *NativeContext, obj: *PhpObject) RuntimeError!*PhpArray {
    const l = try listOf(ctx, obj);
    const arr = try ctx.vm.allocArray();
    for (0..l.len()) |i| try arr.append(ctx.allocator, l.at(i));
    return arr;
}

fn debugTable(ctx: *NativeContext, obj: *PhpObject) RuntimeError!*PhpArray {
    const t = try object_properties.ownTable(ctx.vm, obj);
    try object_properties.setMangled(ctx.vm, t, "flags", .private, "SplDoublyLinkedList", .{ .int = flagsOf(ctx.vm, obj) });
    try object_properties.setMangled(ctx.vm, t, "dllist", .private, "SplDoublyLinkedList", .{ .array = try listArray(ctx, obj) });
    return t;
}

fn debugProperties(ctx: *NativeContext, obj: *PhpObject, purpose: object_properties.Purpose) RuntimeError!?*PhpArray {
    if (purpose != .debug) return null;
    return try debugTable(ctx, obj);
}

fn debugInfo(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplDoublyLinkedList::__debugInfo", args);
    return NativeResult.borrowed(.{ .array = try debugTable(ctx, obj) });
}

// clone_obj: a copy of the list (its arrays shared until one side writes),
// with the traverse pointer back at the head
fn cloneList(vm: *VM, src: *PhpObject, copy: *PhpObject) bool {
    _ = src;
    var ctx = vm.makeContext(null);
    const l = listOf(&ctx, copy) catch return true;
    const head_id: i64 = if (l.len() > 0) l.idAt(0) else 0;
    storeCursor(&ctx, copy, .{ .ptr = head_id, .hint = 0, .pos = 0 }) catch {};
    return true;
}

fn serializeM(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplDoublyLinkedList::serialize", args);
    var w = serialize.Writer{ .ctx = ctx };
    w.begin();
    defer w.deinit();
    try w.value(.{ .int = flagsOf(ctx.vm, obj) });
    var l = try listOf(ctx, obj);
    var i: usize = 0;
    while (i < l.len()) {
        try w.raw(":");
        // a __serialize that removes the next element ends the walk there
        const next_id: i64 = if (i + 1 < l.len()) l.idAt(i + 1) else 0;
        try w.value(l.at(i));
        if (next_id == 0) break;
        l = try listOf(ctx, obj);
        i = l.indexOf(next_id, @intCast(i + 1)) orelse break;
    }
    return w.finish();
}

fn unserializeM(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplDoublyLinkedList::unserialize";
    try oneArg(ctx, label, args);
    const data_s = (try sic.argString(ctx, label, args, 0, "data")) orelse return error.RuntimeError;
    defer data_s.release();
    const data = data_s.bytes();
    if (data.len == 0) return NativeResult.scalar(.null);
    _ = try emptyList(ctx, obj);
    var r = serialize.Reader{ .ctx = ctx, .s = data };
    r.begin();
    defer r.deinit();
    const ok = blk: {
        const f = (try r.value()) orelse break :blk false;
        if (f != .int) break :blk false;
        try setInt(ctx, obj, P.flags, f.int);
        while (r.pos < data.len and data[r.pos] == ':') {
            r.pos += 1;
            const v = (try r.value()) orelse break :blk false;
            try listPush(ctx, obj, v);
            if (v == .string) v.string.release();
        }
        break :blk r.pos >= data.len;
    };
    if (!ok) return sic.throwNow(ctx, "UnexpectedValueException", "Error at offset {d} of {d} bytes", .{ r.pos, data.len });
    return NativeResult.scalar(.null);
}

fn serializeState(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplDoublyLinkedList::__serialize", args);
    const out = try ctx.createArray();
    try out.append(ctx.allocator, .{ .int = flagsOf(ctx.vm, obj) });
    try out.append(ctx.allocator, .{ .array = try listArray(ctx, obj) });
    try out.append(ctx.allocator, .{ .array = try memberTable(ctx, obj) });
    return NativeResult.borrowed(.{ .array = out });
}

// zend_std_get_properties as a symbol table: the object's own properties
// under (array)'s keys
pub fn memberTable(ctx: *NativeContext, obj: *PhpObject) RuntimeError!*PhpArray {
    var listing = try object_properties.list(ctx.vm, obj, .array_cast, ctx.allocator);
    defer listing.deinit(ctx.allocator);
    defer object_properties.releaseHolder(ctx.vm, listing.takeHolder());
    const arr = try ctx.vm.allocArray();
    for (listing.items.items) |p| switch (p.key) {
        .int => |i| try arr.set(ctx.allocator, .{ .int = i }, p.value),
        .name => |n| try object_properties.setMangled(ctx.vm, arr, n, p.visibility, p.declaring, p.value),
    };
    return arr;
}

fn unserializeState(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplDoublyLinkedList::__unserialize";
    try oneArg(ctx, label, args);
    if (args[0] != .array) {
        try sic.typeError(ctx, label, 1, "data", "array", args[0]);
        return error.RuntimeError;
    }
    const data = args[0].array;
    const f = data.get(.{ .int = 0 });
    const storage = data.get(.{ .int = 1 });
    const members = data.get(.{ .int = 2 });
    if (!data.contains(.{ .int = 0 }) or !data.contains(.{ .int = 1 }) or !data.contains(.{ .int = 2 }) or f != .int or storage != .array or members != .array) {
        return sic.throwNow(ctx, "UnexpectedValueException", "Incomplete or ill-typed serialization data", .{});
    }
    try setInt(ctx, obj, P.flags, f.int);
    for (storage.array.entries.items) |e| try listPush(ctx, obj, if (e.ref) |r| r.* else e.value);
    try @import("spl.zig").loadProperties(ctx, obj, members.array);
    return NativeResult.scalar(.null);
}
