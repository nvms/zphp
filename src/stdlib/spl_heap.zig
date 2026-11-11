// php's ext/spl/spl_heap.c: SplHeap, SplMinHeap, SplMaxHeap and
// SplPriorityQueue.
//
// the heap's elements live in hidden packed arrays in heap order (a
// priority queue keeps its priorities in a second array beside them). the
// sift loops are php's, moving elements the way its memcpy does, so what a
// user compare() sees of the heap while it runs, and how equal elements end
// up ordered, match php
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

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

const CORRUPTED: i64 = 1;
const WRITE_LOCKED: i64 = 2;

const EXTR_DATA: i64 = 1;
const EXTR_PRIORITY: i64 = 2;
const EXTR_BOTH: i64 = 3;
const EXTR_MASK: i64 = 3;

const P = struct {
    const data = "__heap_data";
    const priority = "__heap_priority";
    // the heap's CORRUPTED and WRITE_LOCKED bits
    const state = "__heap_state";
    // a priority queue's extract flags
    const flags = "__heap_flags";
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
    var heap = ClassDef{ .name = "SplHeap", .is_abstract = true, .native_properties = heapProperties };
    try heap.interfaces.append(a, "Iterator");
    try heap.interfaces.append(a, "Countable");
    try registerClass(vm, a, heap, "SplHeap", &.{
        .{ "extract", heapExtract },           .{ "insert", heapInsert },
        .{ "top", heapTop },                   .{ "count", count },
        .{ "isEmpty", isEmpty },               .{ "rewind", rewind },
        .{ "current", heapCurrent },           .{ "key", key },
        .{ "next", next },                     .{ "valid", valid },
        .{ "recoverFromCorruption", recover }, .{ "isCorrupted", isCorrupted },
        .{ "__debugInfo", heapDebugInfo },     .{ "__serialize", heapSerialize },
        .{ "__unserialize", heapUnserialize },
    });
    // compare is abstract and protected on SplHeap
    if (vm.classes.getPtr("SplHeap")) |def| try def.methods.put(a, "compare", .{ .name = "compare", .arity = 2, .visibility = .protected, .is_abstract = true });
    inline for (.{ .{ "SplMinHeap", minCompare }, .{ "SplMaxHeap", maxCompare } }) |c| {
        var def = ClassDef{ .name = c[0], .parent = "SplHeap" };
        try def.methods.put(a, "compare", .{ .name = "compare", .arity = 2, .visibility = .protected });
        try vm.native_fns.put(a, c[0] ++ "::compare", c[1]);
        try vm.classes.put(a, c[0], def);
    }

    var pq = ClassDef{ .name = "SplPriorityQueue", .native_properties = pqProperties };
    try pq.interfaces.append(a, "Iterator");
    try pq.interfaces.append(a, "Countable");
    inline for (.{ .{ "EXTR_BOTH", EXTR_BOTH }, .{ "EXTR_PRIORITY", EXTR_PRIORITY }, .{ "EXTR_DATA", EXTR_DATA } }) |c| {
        try pq.constants.put(a, c[0], .{ .int = c[1] });
        try pq.constant_order.append(a, c[0]);
    }
    try registerClass(vm, a, pq, "SplPriorityQueue", &.{
        .{ "compare", pqCompare },               .{ "insert", pqInsert },
        .{ "setExtractFlags", setExtractFlags }, .{ "top", pqTop },
        .{ "extract", pqExtract },               .{ "count", count },
        .{ "isEmpty", isEmpty },                 .{ "rewind", rewind },
        .{ "current", pqCurrent },               .{ "key", key },
        .{ "next", next },                       .{ "valid", valid },
        .{ "recoverFromCorruption", recover },   .{ "isCorrupted", isCorrupted },
        .{ "getExtractFlags", getExtractFlags }, .{ "__debugInfo", pqDebugInfo },
        .{ "__serialize", pqSerialize },         .{ "__unserialize", pqUnserialize },
    });
}

// ==========================================
// the heap
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

fn isPq(vm: *VM, obj: *PhpObject) bool {
    return vm.isInstanceOf(obj.class_name, "SplPriorityQueue");
}

fn extractFlags(obj: *PhpObject) i64 {
    const v = obj.get(P.flags);
    return if (v == .int) v.int else EXTR_DATA;
}

const Order = enum { max, min, pq };

const Heap = struct {
    data: *PhpArray,
    priority: ?*PhpArray,
    order: Order,
    // the subclass's own compare(), which php calls (fptr_cmp)
    user_compare: bool,

    fn count(self: Heap) usize {
        return self.data.entries.items.len;
    }

    fn slot(arr: *PhpArray, i: usize) *Value {
        return &arr.entries.items[i].value;
    }

    // one element: its data, and its priority in a queue
    const Elem = struct { data: Value, priority: Value = .null };

    fn get(self: Heap, i: usize) Elem {
        return .{ .data = slot(self.data, i).*, .priority = if (self.priority) |p| slot(p, i).* else .null };
    }

    fn put(self: Heap, i: usize, e: Elem) void {
        slot(self.data, i).* = e.data;
        if (self.priority) |p| slot(p, i).* = e.priority;
    }

    fn append(self: Heap, ctx: *NativeContext, e: Elem) RuntimeError!void {
        try appendRaw(ctx, self.data, e.data);
        if (self.priority) |p| try appendRaw(ctx, p, e.priority);
    }

    fn truncate(self: Heap, n: usize) void {
        truncateRaw(self.data, n);
        if (self.priority) |p| truncateRaw(p, n);
    }
};

// an entry taking a value whose reference moves in with it
fn appendRaw(ctx: *NativeContext, arr: *PhpArray, v: Value) RuntimeError!void {
    const n: i64 = @intCast(arr.entries.items.len);
    try arr.entries.append(ctx.allocator, .{ .key = .{ .int = n }, .value = v });
    arr.noteIntKey(n);
}

fn truncateRaw(arr: *PhpArray, n: usize) void {
    arr.entries.items.len = n;
    arr.next_int_key = @intCast(n);
    if (n == 0) arr.has_int_keys = false;
}

fn heapArrays(ctx: *NativeContext, obj: *PhpObject, pq: bool) RuntimeError!struct { *PhpArray, ?*PhpArray } {
    var data = obj.get(P.data);
    if (data != .array or data.array.refcount > 1) {
        const fresh = try copyArray(ctx, if (data == .array) data.array else null);
        try obj.set(ctx.allocator, P.data, .{ .array = fresh });
        data = .{ .array = fresh };
    }
    if (!pq) return .{ data.array, null };
    var pri = obj.get(P.priority);
    if (pri != .array or pri.array.refcount > 1) {
        const fresh = try copyArray(ctx, if (pri == .array) pri.array else null);
        try obj.set(ctx.allocator, P.priority, .{ .array = fresh });
        pri = .{ .array = fresh };
    }
    return .{ data.array, pri.array };
}

fn copyArray(ctx: *NativeContext, from: ?*PhpArray) RuntimeError!*PhpArray {
    const arr = try ctx.createArray();
    arr.uncounted = true;
    if (from) |f| for (f.entries.items) |e| try arr.append(ctx.allocator, e.value);
    return arr;
}

fn heapOf(ctx: *NativeContext, obj: *PhpObject) RuntimeError!Heap {
    const pq = isPq(ctx.vm, obj);
    const arrays = try heapArrays(ctx, obj, pq);
    const order: Order = if (pq) .pq else if (ctx.vm.isInstanceOf(obj.class_name, "SplMinHeap")) .min else .max;
    return .{ .data = arrays[0], .priority = arrays[1], .order = order, .user_compare = sic.userMethod(ctx.vm, obj.class_name, "compare") };
}

fn state(obj: *PhpObject) i64 {
    return int(obj, P.state);
}

fn setState(ctx: *NativeContext, obj: *PhpObject, s: i64) RuntimeError!void {
    try setInt(ctx, obj, P.state, s);
}

// the heap's comparison: the subclass's compare(), or zend_compare. 0 while
// an exception is pending
fn cmp(ctx: *NativeContext, obj: *PhpObject, h: Heap, a: Heap.Elem, b: Heap.Elem) RuntimeError!i64 {
    if (sic.pending(ctx)) return 0;
    const x = if (h.order == .pq) a.priority else a.data;
    const y = if (h.order == .pq) b.priority else b.data;
    if (h.user_compare) {
        const r = try sic.callOn(ctx, obj, "compare", &.{ x, y });
        if (r == .undef or sic.pending(ctx)) return 0;
        const n = Value.toInt(r);
        return if (n > 0) 1 else if (n < 0) -1 else 0;
    }
    return switch (h.order) {
        .max, .pq => try compareValues(ctx, x, y),
        .min => try compareValues(ctx, y, x),
    };
}

fn compareValues(ctx: *NativeContext, a: Value, b: Value) RuntimeError!i64 {
    const r = ctx.vm.compareWithStringable(a, b) catch |err| {
        if (sic.pending(ctx)) return 0;
        return err;
    };
    return if (r > 0) 1 else if (r < 0) -1 else 0;
}

// spl_ptr_heap_insert: elem's references move into the heap
fn insert(ctx: *NativeContext, obj: *PhpObject, h: Heap, elem: Heap.Elem) RuntimeError!void {
    const n = h.count();
    try setState(ctx, obj, state(obj) | WRITE_LOCKED);
    // the slot past the end, which the first move fills, is php's spare
    // capacity: compare() does not see it
    var tail: ?Heap.Elem = null;
    var pos = n;
    while (pos > 0) {
        const parent = (pos - 1) / 2;
        if (try cmp(ctx, obj, h, h.get(parent), elem) >= 0) break;
        if (pos == n) tail = h.get(parent) else h.put(pos, h.get(parent));
        pos = parent;
    }
    try setState(ctx, obj, state(obj) & ~WRITE_LOCKED);
    if (sic.pending(ctx)) try setState(ctx, obj, state(obj) | CORRUPTED);
    if (tail) |t| {
        try h.append(ctx, t);
        h.put(pos, elem);
    } else try h.append(ctx, elem);
}

// spl_ptr_heap_delete_top: the top element, whose references the caller
// takes, or null on an empty heap
fn deleteTop(ctx: *NativeContext, obj: *PhpObject, h: Heap) RuntimeError!?Heap.Elem {
    const n = h.count();
    if (n == 0) return null;
    const limit = (n - 1) / 2;
    try setState(ctx, obj, state(obj) | WRITE_LOCKED);
    const top_elem = h.get(0);
    const bottom = h.get(n - 1);
    const count_after = n - 1;
    if (count_after == 0) {
        h.truncate(0);
        try setState(ctx, obj, state(obj) & ~WRITE_LOCKED);
        return top_elem;
    }
    // compare() sees one element fewer, the bottom still in its slot past
    // the end
    h.truncate(count_after);
    var parent: usize = 0;
    while (parent < limit) {
        var child = parent * 2 + 1;
        if (child != count_after) {
            const right = if (child + 1 == count_after) bottom else h.get(child + 1);
            if (try cmp(ctx, obj, h, right, h.get(child)) > 0) child += 1;
        }
        const c = if (child == count_after) bottom else h.get(child);
        if (try cmp(ctx, obj, h, bottom, c) < 0) {
            h.put(parent, c);
            parent = child;
        } else break;
    }
    try setState(ctx, obj, state(obj) & ~WRITE_LOCKED);
    if (sic.pending(ctx)) try setState(ctx, obj, state(obj) | CORRUPTED);
    if (parent < count_after) h.put(parent, bottom);
    return top_elem;
}

fn releaseElem(ctx: *NativeContext, h: Heap, e: Heap.Elem) void {
    ctx.vm.releaseValue(e.data);
    if (h.priority != null) ctx.vm.releaseValue(e.priority);
}

// spl_heap_consistency_validations
fn validate(ctx: *NativeContext, obj: *PhpObject, write: bool) RuntimeError!void {
    const s = state(obj);
    if (s & CORRUPTED != 0) {
        try sic.raise(ctx, "RuntimeException", "Heap is corrupted, heap properties are no longer ensured.", .{});
        return error.RuntimeError;
    }
    if (write and s & WRITE_LOCKED != 0) {
        try sic.raise(ctx, "RuntimeException", "Heap cannot be changed when it is already being modified.", .{});
        return error.RuntimeError;
    }
}

// a value the heap hands to the caller with its reference
fn handOver(ctx: *NativeContext, v: Value) NativeResult {
    if (v == .string) {
        if (v.string.owner != null) return NativeResult.takeString(v.string);
        return NativeResult.share(v);
    }
    ctx.vm.releaseValue(v);
    return NativeResult.borrowed(v);
}

// spl_pqueue_extract_helper: a new value for the caller
fn extractValue(ctx: *NativeContext, e: Heap.Elem, flags: i64) RuntimeError!Value {
    if (flags & EXTR_BOTH == EXTR_BOTH) {
        const arr = try ctx.createArray();
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("data") }, e.data);
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("priority") }, e.priority);
        return .{ .array = arr };
    }
    return if (flags & EXTR_DATA != 0) e.data else e.priority;
}

// ==========================================
// methods
// ==========================================

fn noArgs(ctx: *NativeContext, label: []const u8, args: []const Value) RuntimeError!void {
    if (!try sic.argCount(ctx, label, args.len, 0, 0)) return error.RuntimeError;
}

fn count(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplHeap::count", args);
    const d = obj.get(P.data);
    return NativeResult.scalar(.{ .int = if (d == .array) d.array.length() else 0 });
}

fn isEmpty(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplHeap::isEmpty", args);
    const d = obj.get(P.data);
    return NativeResult.scalar(.{ .bool = d != .array or d.array.length() == 0 });
}

fn heapInsert(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    if (!try sic.argCount(ctx, "SplHeap::insert", args.len, 1, 1)) return error.RuntimeError;
    try validate(ctx, obj, true);
    const h = try heapOf(ctx, obj);
    VM.retainValue(args[0]);
    try insert(ctx, obj, h, .{ .data = args[0] });
    return sic.finish(ctx, NativeResult.scalar(.{ .bool = true }));
}

fn heapExtract(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplHeap::extract", args);
    try validate(ctx, obj, true);
    const h = try heapOf(ctx, obj);
    const e = (try deleteTop(ctx, obj, h)) orelse return sic.throwNow(ctx, "RuntimeException", "Can't extract from an empty heap", .{});
    if (sic.pending(ctx)) {
        releaseElem(ctx, h, e);
        return error.RuntimeError;
    }
    return handOver(ctx, e.data);
}

fn heapTop(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplHeap::top", args);
    try validate(ctx, obj, false);
    const d = obj.get(P.data);
    if (d != .array or d.array.length() == 0) return sic.throwNow(ctx, "RuntimeException", "Can't peek at an empty heap", .{});
    return NativeResult.share(d.array.entries.items[0].value);
}

fn heapCurrent(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplHeap::current", args);
    const d = obj.get(P.data);
    if (d != .array or d.array.length() == 0) return NativeResult.scalar(.null);
    return NativeResult.share(d.array.entries.items[0].value);
}

fn key(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplHeap::key", args);
    const d = obj.get(P.data);
    return NativeResult.scalar(.{ .int = (if (d == .array) d.array.length() else 0) - 1 });
}

fn next(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplHeap::next", args);
    try validate(ctx, obj, true);
    const h = try heapOf(ctx, obj);
    if (try deleteTop(ctx, obj, h)) |e| releaseElem(ctx, h, e);
    return sic.finishNull(ctx);
}

fn valid(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplHeap::valid", args);
    const d = obj.get(P.data);
    return NativeResult.scalar(.{ .bool = d == .array and d.array.length() != 0 });
}

fn rewind(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = try this(ctx);
    try noArgs(ctx, "SplHeap::rewind", args);
    return NativeResult.scalar(.null);
}

fn recover(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplHeap::recoverFromCorruption", args);
    try setState(ctx, obj, state(obj) & ~CORRUPTED);
    return NativeResult.scalar(.{ .bool = true });
}

fn isCorrupted(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplHeap::isCorrupted", args);
    return NativeResult.scalar(.{ .bool = state(obj) & CORRUPTED != 0 });
}

fn compareArgs(ctx: *NativeContext, label: []const u8, args: []const Value) RuntimeError!void {
    if (!try sic.argCount(ctx, label, args.len, 2, 2)) return error.RuntimeError;
}

fn minCompare(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    try compareArgs(ctx, "SplMinHeap::compare", args);
    return sic.finish(ctx, NativeResult.scalar(.{ .int = try compareValues(ctx, args[1], args[0]) }));
}

fn maxCompare(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    try compareArgs(ctx, "SplMaxHeap::compare", args);
    return sic.finish(ctx, NativeResult.scalar(.{ .int = try compareValues(ctx, args[0], args[1]) }));
}

fn pqCompare(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    try compareArgs(ctx, "SplPriorityQueue::compare", args);
    return sic.finish(ctx, NativeResult.scalar(.{ .int = try compareValues(ctx, args[0], args[1]) }));
}

fn pqInsert(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    if (!try sic.argCount(ctx, "SplPriorityQueue::insert", args.len, 2, 2)) return error.RuntimeError;
    try validate(ctx, obj, true);
    const h = try heapOf(ctx, obj);
    VM.retainValue(args[0]);
    VM.retainValue(args[1]);
    try insert(ctx, obj, h, .{ .data = args[0], .priority = args[1] });
    return sic.finish(ctx, NativeResult.scalar(.{ .bool = true }));
}

fn pqExtract(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplPriorityQueue::extract", args);
    try validate(ctx, obj, true);
    const h = try heapOf(ctx, obj);
    const e = (try deleteTop(ctx, obj, h)) orelse return sic.throwNow(ctx, "RuntimeException", "Can't extract from an empty heap", .{});
    defer releaseElem(ctx, h, e);
    if (sic.pending(ctx)) return error.RuntimeError;
    return NativeResult.share(try extractValue(ctx, e, extractFlags(obj)));
}

fn pqTop(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplPriorityQueue::top", args);
    try validate(ctx, obj, false);
    const h = try heapOf(ctx, obj);
    if (h.count() == 0) return sic.throwNow(ctx, "RuntimeException", "Can't peek at an empty heap", .{});
    return NativeResult.share(try extractValue(ctx, h.get(0), extractFlags(obj)));
}

fn pqCurrent(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplPriorityQueue::current", args);
    const h = try heapOf(ctx, obj);
    if (h.count() == 0) return NativeResult.scalar(.null);
    return NativeResult.share(try extractValue(ctx, h.get(0), extractFlags(obj)));
}

fn setExtractFlags(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplPriorityQueue::setExtractFlags";
    if (!try sic.argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const value = ((try sic.argLong(ctx, label, args, 0, "flags", 0)) orelse return error.RuntimeError) & EXTR_MASK;
    if (value == 0) return sic.throwNow(ctx, "RuntimeException", "Must specify at least one extract flag", .{});
    try setInt(ctx, obj, P.flags, value);
    return NativeResult.scalar(.{ .int = value });
}

fn getExtractFlags(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplPriorityQueue::getExtractFlags", args);
    return NativeResult.scalar(.{ .int = extractFlags(obj) });
}

// ==========================================
// debug view and serialization
// ==========================================

fn debugTable(ctx: *NativeContext, obj: *PhpObject, comptime ce: []const u8) RuntimeError!*PhpArray {
    const vm = ctx.vm;
    const t = try object_properties.ownTable(vm, obj);
    const pq = isPq(vm, obj);
    try object_properties.setMangled(vm, t, "flags", .private, ce, .{ .int = if (pq) extractFlags(obj) else 0 });
    try object_properties.setMangled(vm, t, "isCorrupted", .private, ce, .{ .bool = state(obj) & CORRUPTED != 0 });
    const heap = try vm.allocArray();
    const d = obj.get(P.data);
    const p = obj.get(P.priority);
    if (d == .array) for (d.array.entries.items, 0..) |e, i| {
        if (pq) {
            const pri: Value = if (p == .array and i < p.array.entries.items.len) p.array.entries.items[i].value else .null;
            try heap.append(ctx.allocator, try extractValue(ctx, .{ .data = e.value, .priority = pri }, EXTR_BOTH));
        } else try heap.append(ctx.allocator, e.value);
    };
    try object_properties.setMangled(vm, t, "heap", .private, ce, .{ .array = heap });
    return t;
}

fn heapProperties(ctx: *NativeContext, obj: *PhpObject, purpose: object_properties.Purpose) RuntimeError!?*PhpArray {
    if (purpose != .debug) return null;
    return try debugTable(ctx, obj, "SplHeap");
}

fn pqProperties(ctx: *NativeContext, obj: *PhpObject, purpose: object_properties.Purpose) RuntimeError!?*PhpArray {
    if (purpose != .debug) return null;
    return try debugTable(ctx, obj, "SplPriorityQueue");
}

fn heapDebugInfo(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplHeap::__debugInfo", args);
    return NativeResult.borrowed(.{ .array = try debugTable(ctx, obj, "SplHeap") });
}

fn pqDebugInfo(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplPriorityQueue::__debugInfo", args);
    return NativeResult.borrowed(.{ .array = try debugTable(ctx, obj, "SplPriorityQueue") });
}

// spl_heap_serialize_internal
fn serializeAs(ctx: *NativeContext, args: []const Value, comptime label: []const u8, pq: bool) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, label, args);
    try validate(ctx, obj, false);
    if (state(obj) & WRITE_LOCKED != 0) return sic.throwNow(ctx, "RuntimeException", "Cannot serialize heap while it is being modified.", .{});
    const out = try ctx.createArray();
    try out.append(ctx.allocator, .{ .array = try @import("spl_dllist.zig").memberTable(ctx, obj) });
    const st = try ctx.createArray();
    try st.set(ctx.allocator, .{ .string = Value.String.borrowed("flags") }, .{ .int = if (pq) extractFlags(obj) else 0 });
    const elements = try ctx.createArray();
    const d = obj.get(P.data);
    const p = obj.get(P.priority);
    if (d == .array) for (d.array.entries.items, 0..) |e, i| {
        if (pq) {
            const pri: Value = if (p == .array and i < p.array.entries.items.len) p.array.entries.items[i].value else .null;
            try elements.append(ctx.allocator, try extractValue(ctx, .{ .data = e.value, .priority = pri }, EXTR_BOTH));
        } else try elements.append(ctx.allocator, e.value);
    };
    try st.set(ctx.allocator, .{ .string = Value.String.borrowed("heap_elements") }, .{ .array = elements });
    try out.append(ctx.allocator, .{ .array = st });
    return NativeResult.borrowed(.{ .array = out });
}

fn heapSerialize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return serializeAs(ctx, args, "SplHeap::__serialize", false);
}

fn pqSerialize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return serializeAs(ctx, args, "SplPriorityQueue::__serialize", true);
}

fn invalidData(ctx: *NativeContext, obj: *PhpObject) RuntimeError!NativeResult {
    const msg = try std.fmt.allocPrint(ctx.allocator, "Invalid serialization data for {s} object", .{obj.class_name});
    defer ctx.allocator.free(msg);
    // an exception the restore threw becomes the previous of this one, as
    // throwing over a pending exception does in php
    const cause = ctx.vm.takePending();
    defer if (cause) |c| ctx.vm.stackRelease(c);
    try ctx.vm.setPendingException("Exception", msg);
    if (cause) |c| if (c == .object) if (ctx.vm.pending_exception) |exc| if (exc == .object) {
        _ = try ctx.vm.chainPrevious(exc.object, c.object);
    };
    return error.RuntimeError;
}

// spl_heap_unserialize_internal_state: false on bad data
fn unserializeState(ctx: *NativeContext, obj: *PhpObject, st: *PhpArray, pq: bool) RuntimeError!bool {
    const f = st.get(.{ .string = Value.String.borrowed("flags") });
    if (f != .int) return false;
    var flags_value = f.int;
    if (pq) {
        flags_value &= EXTR_MASK;
        if (flags_value == 0) return false;
        try setInt(ctx, obj, P.flags, flags_value);
    } else if (flags_value != 0) return false;
    const elements = st.get(.{ .string = Value.String.borrowed("heap_elements") });
    if (elements != .array) return false;
    for (elements.array.entries.items) |entry| {
        const val = if (entry.ref) |r| r.* else entry.value;
        const h = try heapOf(ctx, obj);
        if (pq) {
            if (val != .array or val.array.length() != 2) return false;
            const data_k: PhpArray.Key = .{ .string = Value.String.borrowed("data") };
            const pri_k: PhpArray.Key = .{ .string = Value.String.borrowed("priority") };
            if (!val.array.contains(data_k) or !val.array.contains(pri_k)) return false;
            const data = val.array.get(data_k);
            const priority = val.array.get(pri_k);
            VM.retainValue(data);
            VM.retainValue(priority);
            try insert(ctx, obj, h, .{ .data = data, .priority = priority });
        } else {
            VM.retainValue(val);
            try insert(ctx, obj, h, .{ .data = val });
        }
        if (sic.pending(ctx)) return false;
    }
    return true;
}

fn unserializeAs(ctx: *NativeContext, args: []const Value, comptime label: []const u8, pq: bool) RuntimeError!NativeResult {
    const obj = try this(ctx);
    if (!try sic.argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    if (args[0] != .array) {
        try sic.typeError(ctx, label, 1, "data", "array", args[0]);
        return error.RuntimeError;
    }
    if (!pq) try validate(ctx, obj, true);
    const data = args[0].array;
    if (data.length() != 2) return invalidData(ctx, obj);
    const props = data.get(.{ .int = 0 });
    if (!data.contains(.{ .int = 0 }) or props != .array) return invalidData(ctx, obj);
    @import("spl.zig").loadProperties(ctx, obj, props.array) catch |err| {
        if (!sic.pending(ctx)) return err;
        return invalidData(ctx, obj);
    };
    if (sic.pending(ctx)) return invalidData(ctx, obj);
    const st = data.get(.{ .int = 1 });
    if (!data.contains(.{ .int = 1 }) or st != .array) return invalidData(ctx, obj);
    if (!try unserializeState(ctx, obj, st.array, pq)) return invalidData(ctx, obj);
    if (sic.pending(ctx)) return error.RuntimeError;
    try validate(ctx, obj, false);
    return NativeResult.scalar(.null);
}

fn heapUnserialize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return unserializeAs(ctx, args, "SplHeap::__unserialize", false);
}

fn pqUnserialize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return unserializeAs(ctx, args, "SplPriorityQueue::__unserialize", true);
}
