// php's ext/spl/spl_observer.c: SplObjectStorage and MultipleIterator,
// which share php's storage structure.
//
// the storage is a hash keyed by the object's handle, or by what a
// subclass's getHash() returns, in insertion order. zphp keeps it in two
// hidden arrays under the same keys (the objects and their data), the
// handle written "#<handle>" so the key stays a string, and php's internal
// position as an index into them, kept on the same element as entries
// before it are removed
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

const MIT_NEED_ANY: i64 = 0;
const MIT_NEED_ALL: i64 = 1;
const MIT_KEYS_NUMERIC: i64 = 0;
const MIT_KEYS_ASSOC: i64 = 2;

const P = struct {
    const objs = "__sos_objs";
    const infs = "__sos_infs";
    const pos = "__sos_pos";
    const index = "__sos_index";
    const flags = "__sos_flags";
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
    var observer = vm_mod.InterfaceDef{ .name = "SplObserver" };
    try observer.methods.append(a, "update");
    try vm.interfaces.put(a, "SplObserver", observer);
    var subject = vm_mod.InterfaceDef{ .name = "SplSubject" };
    try subject.methods.append(a, "attach");
    try subject.methods.append(a, "detach");
    try subject.methods.append(a, "notify");
    try vm.interfaces.put(a, "SplSubject", subject);

    var sos = ClassDef{ .name = "SplObjectStorage", .native_properties = debugProperties, .native_unset_dimension = unsetDimension };
    inline for (.{ "Countable", "SeekableIterator", "Serializable", "ArrayAccess" }) |i| try sos.interfaces.append(a, i);
    try registerClass(vm, a, sos, "SplObjectStorage", &.{
        .{ "attach", attach },              .{ "detach", detach },
        .{ "contains", contains },          .{ "addAll", addAll },
        .{ "removeAll", removeAll },        .{ "removeAllExcept", removeAllExcept },
        .{ "getInfo", getInfo },            .{ "setInfo", setInfo },
        .{ "count", count },                .{ "rewind", rewind },
        .{ "valid", valid },                .{ "key", key },
        .{ "current", current },            .{ "next", next },
        .{ "seek", seek },                  .{ "unserialize", unserializeM },
        .{ "serialize", serializeM },       .{ "offsetExists", offsetExists },
        .{ "offsetGet", offsetGet },        .{ "offsetSet", offsetSet },
        .{ "offsetUnset", offsetUnset },    .{ "getHash", getHash },
        .{ "__serialize", serializeState }, .{ "__unserialize", unserializeState },
        .{ "__debugInfo", debugInfo },
    });

    var mi = ClassDef{ .name = "MultipleIterator", .native_properties = debugProperties };
    try mi.interfaces.append(a, "Iterator");
    inline for (.{ .{ "MIT_NEED_ANY", MIT_NEED_ANY }, .{ "MIT_NEED_ALL", MIT_NEED_ALL }, .{ "MIT_KEYS_NUMERIC", MIT_KEYS_NUMERIC }, .{ "MIT_KEYS_ASSOC", MIT_KEYS_ASSOC } }) |c| {
        try mi.constants.put(a, c[0], .{ .int = c[1] });
        try mi.constant_order.append(a, c[0]);
    }
    try registerClass(vm, a, mi, "MultipleIterator", &.{
        .{ "__construct", miConstruct }, .{ "getFlags", miGetFlags },
        .{ "setFlags", miSetFlags },     .{ "attachIterator", miAttach },
        .{ "detachIterator", miDetach }, .{ "containsIterator", miContains },
        .{ "countIterators", miCount },  .{ "rewind", miRewind },
        .{ "valid", miValid },           .{ "key", miKey },
        .{ "current", miCurrent },       .{ "next", miNext },
        .{ "__debugInfo", debugInfo },
    });
}

// ==========================================
// the storage
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

const Storage = struct {
    objs: *PhpArray,
    infs: *PhpArray,

    fn len(self: Storage) usize {
        return self.objs.entries.items.len;
    }

    // an object, or a generator (zphp's generators aren't PhpObjects)
    fn objAt(self: Storage, i: usize) Value {
        return self.objs.entries.items[i].value;
    }

    fn infAt(self: Storage, i: usize) Value {
        const e = self.infs.entries.items[i];
        return if (e.ref) |r| r.* else e.value;
    }

    fn keyAt(self: Storage, i: usize) PhpArray.Key {
        return self.objs.entries.items[i].key;
    }

    fn find(self: Storage, k: PhpArray.Key) ?usize {
        switch (k) {
            .string => |s| return self.objs.string_index.get(s.bytes()),
            .int => {
                for (self.objs.entries.items, 0..) |e, i| if (e.key.eql(k)) return i;
                return null;
            },
        }
    }
};

fn storageOf(ctx: *NativeContext, obj: *PhpObject) RuntimeError!Storage {
    const o = obj.get(P.objs);
    const i = obj.get(P.infs);
    if (o == .array and i == .array) return .{ .objs = o.array, .infs = i.array };
    const objs = try ctx.createArray();
    const infs = try ctx.createArray();
    objs.uncounted = true;
    infs.uncounted = true;
    try obj.set(ctx.allocator, P.objs, .{ .array = objs });
    try obj.set(ctx.allocator, P.infs, .{ .array = infs });
    return .{ .objs = objs, .infs = infs };
}

// the storage to change, separated from a clone sharing it
fn writable(ctx: *NativeContext, obj: *PhpObject) RuntimeError!Storage {
    const st = try storageOf(ctx, obj);
    return .{ .objs = try separate(ctx, obj, P.objs, st.objs), .infs = try separate(ctx, obj, P.infs, st.infs) };
}

fn separate(ctx: *NativeContext, obj: *PhpObject, comptime name: []const u8, arr: *PhpArray) RuntimeError!*PhpArray {
    const sep = try ctx.vm.cowSeparate(arr);
    if (sep != arr) {
        sep.uncounted = true;
        try obj.set(ctx.allocator, name, .{ .array = sep });
        sep.refcount -= 1;
    }
    return sep;
}

// an entry under the key, which the array keeps its own copy of
fn put(ctx: *NativeContext, arr: *PhpArray, k: PhpArray.Key, v: Value) RuntimeError!void {
    switch (k) {
        .string => |str| try arr.setCopiedKey(ctx.allocator, str.bytes(), v),
        .int => try arr.set(ctx.allocator, k, v),
    }
}

fn isStorage(vm: *VM, obj: *PhpObject) bool {
    return vm.isInstanceOf(obj.class_name, "SplObjectStorage");
}

// fptr_get_hash: a subclass's own getHash()
fn userHash(vm: *VM, obj: *PhpObject) bool {
    return isStorage(vm, obj) and sic.userMethod(vm, obj.class_name, "getHash");
}

// spl_object_storage_get_hash: the element's key, or null with an
// exception pending
fn hashKey(ctx: *NativeContext, obj: *PhpObject, target: Value) RuntimeError!?PhpArray.Key {
    if (userHash(ctx.vm, obj)) {
        const r = try sic.callOn(ctx, obj, "getHash", &.{target});
        if (r == .undef or sic.pending(ctx)) return null;
        if (r != .string) {
            try sic.raise(ctx, "TypeError", "{s}::getHash(): Return value must be of type string, {s} returned", .{ obj.class_name, r.valueName() });
            return null;
        }
        return PhpArray.normalizeKey(.{ .string = Value.String.borrowed(try ctx.createString(r.string.bytes())) });
    }
    return .{ .string = Value.String.borrowed(try std.fmt.allocPrint(ctx.allocator, "#{d}", .{handleOf(target)})) };
}

fn handleOf(target: Value) u32 {
    return if (target == .generator) target.generator.handle else target.object.id;
}

fn freeKey(ctx: *NativeContext, obj: *PhpObject, k: PhpArray.Key) void {
    if (!userHash(ctx.vm, obj) and k == .string) ctx.allocator.free(k.string.bytes());
}

// spl_object_storage_attach: the element's index
fn storageAttach(ctx: *NativeContext, obj: *PhpObject, target: Value, inf: Value) RuntimeError!?usize {
    const k = (try hashKey(ctx, obj, target)) orelse return null;
    defer freeKey(ctx, obj, k);
    const st = try writable(ctx, obj);
    if (st.find(k)) |i| {
        // the old data's destructor runs last, in case it moves the entry
        const old = st.infAt(i);
        VM.retainValue(old);
        try put(ctx, st.infs, k, inf);
        ctx.vm.releaseValue(old);
        return i;
    }
    try put(ctx, st.objs, k, target);
    try put(ctx, st.infs, k, inf);
    return st.len() - 1;
}

// spl_object_storage_detach: whether the object was there
fn storageDetach(ctx: *NativeContext, obj: *PhpObject, target: Value) RuntimeError!bool {
    const k = (try hashKey(ctx, obj, target)) orelse return false;
    defer freeKey(ctx, obj, k);
    return removeKey(ctx, obj, k);
}

fn removeKey(ctx: *NativeContext, obj: *PhpObject, k: PhpArray.Key) RuntimeError!bool {
    const st = try writable(ctx, obj);
    const i = st.find(k) orelse return false;
    const o: Value = st.objs.entries.items[i].value;
    const inf = st.infAt(i);
    VM.retainValue(o);
    VM.retainValue(inf);
    ctx.vm.arrayRemoveOwned(st.objs, k);
    ctx.vm.arrayRemoveOwned(st.infs, k);
    // the position stays on the element it was on
    const pos = int(obj, P.pos);
    if (pos > i) try setInt(ctx, obj, P.pos, pos - 1);
    ctx.vm.releaseValue(inf);
    ctx.vm.releaseValue(o);
    return true;
}

fn storageContains(ctx: *NativeContext, obj: *PhpObject, target: Value) RuntimeError!bool {
    const k = (try hashKey(ctx, obj, target)) orelse return true;
    defer freeKey(ctx, obj, k);
    return (try storageOf(ctx, obj)).find(k) != null;
}

fn resetPos(ctx: *NativeContext, obj: *PhpObject) RuntimeError!void {
    try setInt(ctx, obj, P.pos, 0);
    try setInt(ctx, obj, P.index, 0);
}

// spl_object_storage_addall
fn storageAddAll(ctx: *NativeContext, obj: *PhpObject, other: *PhpObject) RuntimeError!void {
    const st = try storageOf(ctx, other);
    // the other storage may change under its elements' destructors
    var i: usize = 0;
    while (i < st.len()) : (i += 1) {
        const target = st.objAt(i);
        const inf = st.infAt(i);
        VM.retainValue(target);
        VM.retainValue(inf);
        defer {
            ctx.vm.releaseValue(inf);
            ctx.vm.releaseValue(target);
        }
        _ = try storageAttach(ctx, obj, target, inf);
        if (sic.pending(ctx)) return;
    }
    try setInt(ctx, obj, P.index, 0);
}

// ==========================================
// SplObjectStorage
// ==========================================

fn argObj(ctx: *NativeContext, label: []const u8, args: []const Value, i: usize, pname: []const u8) RuntimeError!Value {
    if (i < args.len and (args[i] == .object or args[i] == .generator)) return args[i];
    try sic.typeError(ctx, label, i + 1, pname, "object", if (i < args.len) args[i] else .null);
    return error.RuntimeError;
}

fn argStorage(ctx: *NativeContext, label: []const u8, args: []const Value) RuntimeError!*PhpObject {
    if (!try sic.argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const v = (try sic.argObject(ctx, label, args, 0, "storage", "SplObjectStorage")) orelse return error.RuntimeError;
    return v.object;
}

fn noArgs(ctx: *NativeContext, label: []const u8, args: []const Value) RuntimeError!void {
    if (!try sic.argCount(ctx, label, args.len, 0, 0)) return error.RuntimeError;
}

fn attachAs(ctx: *NativeContext, args: []const Value, label: []const u8) RuntimeError!NativeResult {
    const obj = try this(ctx);
    if (!try sic.argCount(ctx, label, args.len, 1, 2)) return error.RuntimeError;
    const target = try argObj(ctx, label, args, 0, "object");
    _ = try storageAttach(ctx, obj, target, if (args.len > 1) args[1] else .null);
    return sic.finishNull(ctx);
}

fn attach(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return attachAs(ctx, args, "SplObjectStorage::attach");
}

fn offsetSet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return attachAs(ctx, args, "SplObjectStorage::offsetSet");
}

fn detachAs(ctx: *NativeContext, args: []const Value, label: []const u8) RuntimeError!NativeResult {
    const obj = try this(ctx);
    if (!try sic.argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const target = try argObj(ctx, label, args, 0, "object");
    _ = try storageDetach(ctx, obj, target);
    try resetPos(ctx, obj);
    return sic.finishNull(ctx);
}

fn detach(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return detachAs(ctx, args, "SplObjectStorage::detach");
}

fn offsetUnset(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return detachAs(ctx, args, "SplObjectStorage::offsetUnset");
}

// spl_object_storage_unset_dimension: unset($storage[$object]) on a
// storage whose subclass overrides neither getHash() nor offsetUnset()
// detaches without the rewind offsetUnset() does
fn unsetDimension(ctx: *NativeContext, obj: *PhpObject, offset: Value) RuntimeError!bool {
    if ((offset != .object and offset != .generator) or !isStorage(ctx.vm, obj)) return false;
    if (sic.userMethod(ctx.vm, obj.class_name, "getHash") or sic.userMethod(ctx.vm, obj.class_name, "offsetUnset")) return false;
    _ = try storageDetach(ctx, obj, offset);
    if (sic.pending(ctx)) return error.RuntimeError;
    return true;
}

fn containsAs(ctx: *NativeContext, args: []const Value, label: []const u8) RuntimeError!NativeResult {
    const obj = try this(ctx);
    if (!try sic.argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const target = try argObj(ctx, label, args, 0, "object");
    const found = try storageContains(ctx, obj, target);
    return sic.finish(ctx, NativeResult.scalar(.{ .bool = found }));
}

fn contains(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return containsAs(ctx, args, "SplObjectStorage::contains");
}

fn offsetExists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return containsAs(ctx, args, "SplObjectStorage::offsetExists");
}

fn offsetGet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplObjectStorage::offsetGet";
    if (!try sic.argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const target = try argObj(ctx, label, args, 0, "object");
    const k = (try hashKey(ctx, obj, target)) orelse return sic.finishNull(ctx);
    defer freeKey(ctx, obj, k);
    const st = try storageOf(ctx, obj);
    const i = st.find(k) orelse return sic.throwNow(ctx, "UnexpectedValueException", "Object not found", .{});
    return NativeResult.share(st.infAt(i));
}

fn getHash(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const label = "SplObjectStorage::getHash";
    if (!try sic.argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const target = try argObj(ctx, label, args, 0, "object");
    // php_spl_object_hash: the handle, then sixteen zeros
    var buf: [32]u8 = undefined;
    const hash = std.fmt.bufPrint(&buf, "{x:0>16}0000000000000000", .{handleOf(target)}) catch unreachable;
    return NativeResult.copyString(ctx.allocator, hash);
}

fn addAll(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const other = try argStorage(ctx, "SplObjectStorage::addAll", args);
    try storageAddAll(ctx, obj, other);
    return sic.finish(ctx, NativeResult.scalar(.{ .int = @intCast((try storageOf(ctx, obj)).len()) }));
}

fn removeAll(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const other = try argStorage(ctx, "SplObjectStorage::removeAll", args);
    var i: usize = 0;
    while (true) {
        const st = try storageOf(ctx, other);
        if (i >= st.len()) break;
        const target = st.objAt(i);
        VM.retainValue(target);
        defer ctx.vm.releaseValue(target);
        const removed = try storageDetach(ctx, obj, target);
        if (sic.pending(ctx)) return error.RuntimeError;
        // removing from itself shrinks the list under the walk
        if (!removed or other != obj) i += 1;
    }
    try resetPos(ctx, obj);
    return NativeResult.scalar(.{ .int = @intCast((try storageOf(ctx, obj)).len()) });
}

fn removeAllExcept(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const other = try argStorage(ctx, "SplObjectStorage::removeAllExcept", args);
    const st = try storageOf(ctx, obj);
    // a snapshot of the elements, as php walks its buckets past holes
    var targets: std.ArrayListUnmanaged(Value) = .empty;
    defer targets.deinit(ctx.allocator);
    for (0..st.len()) |i| {
        const t = st.objAt(i);
        VM.retainValue(t);
        try targets.append(ctx.allocator, t);
    }
    defer for (targets.items) |t| ctx.vm.releaseValue(t);
    for (targets.items) |t| {
        if (!try storageContains(ctx, other, t)) _ = try storageDetach(ctx, obj, t);
        if (sic.pending(ctx)) return error.RuntimeError;
    }
    try resetPos(ctx, obj);
    return NativeResult.scalar(.{ .int = @intCast((try storageOf(ctx, obj)).len()) });
}

fn currentIndex(ctx: *NativeContext, obj: *PhpObject) RuntimeError!?usize {
    const st = try storageOf(ctx, obj);
    const pos = int(obj, P.pos);
    if (pos < 0 or pos >= st.len()) return null;
    return @intCast(pos);
}

fn getInfo(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplObjectStorage::getInfo", args);
    const i = (try currentIndex(ctx, obj)) orelse return NativeResult.scalar(.null);
    return NativeResult.share((try storageOf(ctx, obj)).infAt(i));
}

fn setInfo(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    if (!try sic.argCount(ctx, "SplObjectStorage::setInfo", args.len, 1, 1)) return error.RuntimeError;
    const i = (try currentIndex(ctx, obj)) orelse return NativeResult.scalar(.null);
    const st = try writable(ctx, obj);
    const old = st.infAt(i);
    VM.retainValue(old);
    try put(ctx, st.infs, st.keyAt(i), args[0]);
    ctx.vm.releaseValue(old);
    return NativeResult.scalar(.null);
}

fn count(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplObjectStorage::count";
    if (!try sic.argCount(ctx, label, args.len, 0, 1)) return error.RuntimeError;
    _ = (try sic.argLong(ctx, label, args, 0, "mode", 0)) orelse return error.RuntimeError;
    return NativeResult.scalar(.{ .int = @intCast((try storageOf(ctx, obj)).len()) });
}

fn rewind(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplObjectStorage::rewind", args);
    try resetPos(ctx, obj);
    return NativeResult.scalar(.null);
}

fn valid(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplObjectStorage::valid", args);
    return NativeResult.scalar(.{ .bool = (try currentIndex(ctx, obj)) != null });
}

fn key(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplObjectStorage::key", args);
    return NativeResult.scalar(.{ .int = int(obj, P.index) });
}

fn current(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplObjectStorage::current", args);
    const i = (try currentIndex(ctx, obj)) orelse return sic.throwNow(ctx, "RuntimeException", "Called current() on invalid iterator", .{});
    return NativeResult.share((try storageOf(ctx, obj)).objAt(i));
}

fn next(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplObjectStorage::next", args);
    const n: i64 = @intCast((try storageOf(ctx, obj)).len());
    const pos = int(obj, P.pos);
    if (pos < n) try setInt(ctx, obj, P.pos, pos + 1);
    try setInt(ctx, obj, P.index, int(obj, P.index) + 1);
    return NativeResult.scalar(.null);
}

fn seek(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplObjectStorage::seek";
    if (!try sic.argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const position = (try sic.argLong(ctx, label, args, 0, "offset", 0)) orelse return error.RuntimeError;
    const n: i64 = @intCast((try storageOf(ctx, obj)).len());
    if (position < 0 or position >= n) return sic.throwNow(ctx, "OutOfBoundsException", "Seek position {d} is out of range", .{position});
    // php walks its hash position from where it is, so a position already
    // past the end can't step back
    var pos = int(obj, P.pos);
    var index = int(obj, P.index);
    const forward = struct {
        fn f(p: i64, len: i64) i64 {
            return if (p < len) p + 1 else p;
        }
    }.f;
    if (position == 0) {
        pos = 0;
        index = 0;
    } else if (position > index) {
        while (true) {
            pos = forward(pos, n);
            index += 1;
            if (!(position > index)) break;
        }
    } else if (position < index) {
        if (index - position > position) {
            pos = 0;
            index = 0;
            while (true) {
                pos = forward(pos, n);
                index += 1;
                if (!(position > index)) break;
            }
        } else {
            while (true) {
                if (pos < n) pos = if (pos > 0) pos - 1 else n;
                index -= 1;
                if (!(position < index)) break;
            }
        }
    }
    try setInt(ctx, obj, P.pos, pos);
    try setInt(ctx, obj, P.index, index);
    return NativeResult.scalar(.null);
}

// ==========================================
// serialization and debug view
// ==========================================

fn serializeM(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplObjectStorage::serialize", args);
    var w = serialize.Writer{ .ctx = ctx };
    w.begin();
    defer w.deinit();
    try w.raw("x:");
    var st = try storageOf(ctx, obj);
    try w.value(.{ .int = @intCast(st.len()) });
    var i: usize = 0;
    while (i < st.len()) : (i += 1) {
        const target = st.objAt(i);
        const inf = st.infAt(i);
        VM.retainValue(inf);
        defer ctx.vm.releaseValue(inf);
        try w.value(target);
        try w.raw(",");
        try w.value(inf);
        try w.raw(";");
        st = try storageOf(ctx, obj);
    }
    try w.raw("m:");
    const members = try @import("spl_dllist.zig").memberTable(ctx, obj);
    try w.value(.{ .array = members });
    return w.finish();
}

fn unserializeM(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplObjectStorage::unserialize";
    if (!try sic.argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const data_s = (try sic.argString(ctx, label, args, 0, "data")) orelse return error.RuntimeError;
    defer data_s.release();
    const s = data_s.bytes();
    if (s.len == 0) return NativeResult.scalar(.null);
    var r = serialize.Reader{ .ctx = ctx, .s = s };
    r.begin();
    defer r.deinit();
    const ok = blk: {
        if (s.len < 2 or s[0] != 'x' or s[1] != ':') {
            r.pos = if (s[0] == 'x') 1 else 0;
            break :blk false;
        }
        r.pos = 2;
        const cnt = (try r.value()) orelse break :blk false;
        if (cnt != .int) break :blk false;
        // back on the count's ';', which each element starts after
        r.pos -= 1;
        if (cnt.int < 0) break :blk false;
        var left = cnt.int;
        while (left > 0) : (left -= 1) {
            if (r.pos >= s.len or s[r.pos] != ';') break :blk false;
            r.pos += 1;
            if (r.pos >= s.len or (s[r.pos] != 'O' and s[r.pos] != 'C' and s[r.pos] != 'r')) break :blk false;
            const entry = (try r.value()) orelse break :blk false;
            var inf: Value = .null;
            if (r.pos < s.len and s[r.pos] == ',') {
                r.pos += 1;
                inf = (try r.value()) orelse break :blk false;
            }
            defer if (inf == .string) inf.string.release();
            if (entry != .object) break :blk false;
            _ = try storageAttach(ctx, obj, entry, inf);
            if (sic.pending(ctx)) return error.RuntimeError;
        }
        if (r.pos >= s.len or s[r.pos] != ';') break :blk false;
        r.pos += 1;
        if (r.pos + 1 >= s.len or s[r.pos] != 'm' or s[r.pos + 1] != ':') {
            if (r.pos < s.len and s[r.pos] == 'm') r.pos += 1;
            break :blk false;
        }
        r.pos += 2;
        const members = (try r.value()) orelse break :blk false;
        if (members != .array) break :blk false;
        try @import("spl.zig").loadProperties(ctx, obj, members.array);
        break :blk true;
    };
    if (!ok) return sic.throwNow(ctx, "UnexpectedValueException", "Error at offset {d} of {d} bytes", .{ r.pos, s.len });
    return NativeResult.scalar(.null);
}

fn serializeState(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplObjectStorage::__serialize", args);
    const out = try ctx.createArray();
    const pairs = try ctx.createArray();
    const st = try storageOf(ctx, obj);
    for (0..st.len()) |i| {
        try pairs.append(ctx.allocator, st.objAt(i));
        try pairs.append(ctx.allocator, st.infAt(i));
    }
    try out.append(ctx.allocator, .{ .array = pairs });
    try out.append(ctx.allocator, .{ .array = try @import("spl_dllist.zig").memberTable(ctx, obj) });
    return NativeResult.borrowed(.{ .array = out });
}

fn unserializeState(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplObjectStorage::__unserialize";
    if (!try sic.argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    if (args[0] != .array) {
        try sic.typeError(ctx, label, 1, "data", "array", args[0]);
        return error.RuntimeError;
    }
    const data = args[0].array;
    const storage = data.get(.{ .int = 0 });
    const members = data.get(.{ .int = 1 });
    if (!data.contains(.{ .int = 0 }) or !data.contains(.{ .int = 1 }) or storage != .array or members != .array) {
        return sic.throwNow(ctx, "UnexpectedValueException", "Incomplete or ill-typed serialization data", .{});
    }
    if (@mod(storage.array.length(), 2) != 0) return sic.throwNow(ctx, "UnexpectedValueException", "Odd number of elements", .{});
    var held: ?Value = null;
    for (storage.array.entries.items) |e| {
        const v = if (e.ref) |r| r.* else e.value;
        if (held) |k| {
            if (k != .object) return sic.throwNow(ctx, "UnexpectedValueException", "Non-object key", .{});
            _ = try storageAttach(ctx, obj, k, v);
            if (sic.pending(ctx)) return error.RuntimeError;
            held = null;
        } else held = v;
    }
    try @import("spl.zig").loadProperties(ctx, obj, members.array);
    return NativeResult.scalar(.null);
}

fn debugTable(ctx: *NativeContext, obj: *PhpObject) RuntimeError!*PhpArray {
    const t = try object_properties.ownTable(ctx.vm, obj);
    const storage = try ctx.vm.allocArray();
    const st = try storageOf(ctx, obj);
    for (0..st.len()) |i| {
        const pair = try ctx.vm.allocArray();
        try pair.set(ctx.allocator, .{ .string = Value.String.borrowed("obj") }, st.objAt(i));
        try pair.set(ctx.allocator, .{ .string = Value.String.borrowed("inf") }, st.infAt(i));
        try storage.append(ctx.allocator, .{ .array = pair });
    }
    try object_properties.setMangled(ctx.vm, t, "storage", .private, "SplObjectStorage", .{ .array = storage });
    return t;
}

fn debugProperties(ctx: *NativeContext, obj: *PhpObject, purpose: object_properties.Purpose) RuntimeError!?*PhpArray {
    if (purpose != .debug) return null;
    return try debugTable(ctx, obj);
}

fn debugInfo(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplObjectStorage::__debugInfo", args);
    return NativeResult.borrowed(.{ .array = try debugTable(ctx, obj) });
}

// ==========================================
// MultipleIterator
// ==========================================

fn miFlags(obj: *PhpObject) i64 {
    const v = obj.get(P.flags);
    return if (v == .int) v.int else MIT_NEED_ALL | MIT_KEYS_NUMERIC;
}

fn miConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "MultipleIterator::__construct";
    if (!try sic.argCount(ctx, label, args.len, 0, 1)) return error.RuntimeError;
    const f = (try sic.argLong(ctx, label, args, 0, "flags", MIT_NEED_ALL | MIT_KEYS_NUMERIC)) orelse return error.RuntimeError;
    try setInt(ctx, obj, P.flags, f);
    return NativeResult.scalar(.null);
}

fn miGetFlags(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "MultipleIterator::getFlags", args);
    return NativeResult.scalar(.{ .int = miFlags(obj) });
}

fn miSetFlags(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "MultipleIterator::setFlags";
    if (!try sic.argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const f = (try sic.argLong(ctx, label, args, 0, "flags", 0)) orelse return error.RuntimeError;
    try setInt(ctx, obj, P.flags, f);
    return NativeResult.scalar(.null);
}

fn argIterator(ctx: *NativeContext, label: []const u8, args: []const Value) RuntimeError!Value {
    return (try sic.argObject(ctx, label, args, 0, "iterator", "Iterator")) orelse error.RuntimeError;
}

fn miAttach(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "MultipleIterator::attachIterator";
    if (!try sic.argCount(ctx, label, args.len, 1, 2)) return error.RuntimeError;
    const it = try argIterator(ctx, label, args);
    const info: Value = if (args.len > 1) args[1] else .null;
    switch (info) {
        .null, .int, .string => {},
        .float, .bool => {},
        else => {
            try sic.typeError(ctx, label, 2, "info", "string|int|null", info);
            return error.RuntimeError;
        },
    }
    // Z_PARAM_STR_OR_LONG_OR_NULL: a float or bool becomes an int
    const zinfo: Value = switch (info) {
        .float => |f| .{ .int = @intFromFloat(f) },
        .bool => |b| .{ .int = @intFromBool(b) },
        else => info,
    };
    if (zinfo != .null) {
        const st = try storageOf(ctx, obj);
        for (0..st.len()) |i| {
            if (Value.identical(zinfo, st.infAt(i))) return sic.throwNow(ctx, "InvalidArgumentException", "Key duplication error", .{});
        }
        try setInt(ctx, obj, P.pos, @intCast(st.len()));
    }
    _ = try storageAttach(ctx, obj, it, zinfo);
    return NativeResult.scalar(.null);
}

fn miDetach(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "MultipleIterator::detachIterator";
    if (!try sic.argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const it = try argIterator(ctx, label, args);
    _ = try storageDetach(ctx, obj, it);
    try resetPos(ctx, obj);
    return NativeResult.scalar(.null);
}

fn miContains(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "MultipleIterator::containsIterator";
    if (!try sic.argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const it = try argIterator(ctx, label, args);
    return NativeResult.scalar(.{ .bool = try storageContains(ctx, obj, it) });
}

fn miCount(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "MultipleIterator::countIterators", args);
    return NativeResult.scalar(.{ .int = @intCast((try storageOf(ctx, obj)).len()) });
}

// each sub-iterator's method, in order, while no exception is pending
fn miEach(ctx: *NativeContext, obj: *PhpObject, comptime method: []const u8) RuntimeError!void {
    try setInt(ctx, obj, P.pos, 0);
    var i: usize = 0;
    while (!sic.pending(ctx)) : (i += 1) {
        const st = try storageOf(ctx, obj);
        if (i >= st.len()) break;
        try setInt(ctx, obj, P.pos, @intCast(i));
        const it = st.objAt(i);
        VM.retainValue(it);
        defer ctx.vm.releaseValue(it);
        _ = try sic.callAny(ctx, it, method, &.{});
    }
    try setInt(ctx, obj, P.pos, @intCast((try storageOf(ctx, obj)).len()));
}

fn miRewind(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "MultipleIterator::rewind", args);
    try miEach(ctx, obj, "rewind");
    return sic.finishNull(ctx);
}

fn miNext(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "MultipleIterator::next", args);
    try miEach(ctx, obj, "next");
    return sic.finishNull(ctx);
}

fn miValid(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "MultipleIterator::valid", args);
    if ((try storageOf(ctx, obj)).len() == 0) return NativeResult.scalar(.{ .bool = false });
    const expect = miFlags(obj) & MIT_NEED_ALL != 0;
    var i: usize = 0;
    while (!sic.pending(ctx)) : (i += 1) {
        const st = try storageOf(ctx, obj);
        if (i >= st.len()) break;
        try setInt(ctx, obj, P.pos, @intCast(i));
        const it = st.objAt(i);
        VM.retainValue(it);
        const r = try sic.callAny(ctx, it, "valid", &.{});
        ctx.vm.releaseValue(it);
        const v = r == .bool and r.bool;
        if (v != expect) return sic.finish(ctx, NativeResult.scalar(.{ .bool = !expect }));
    }
    return sic.finish(ctx, NativeResult.scalar(.{ .bool = expect }));
}

// spl_multiple_iterator_get_all
fn getAll(ctx: *NativeContext, obj: *PhpObject, comptime what: []const u8) RuntimeError!NativeResult {
    if ((try storageOf(ctx, obj)).len() == 0) return sic.throwNow(ctx, "RuntimeException", "Called " ++ what ++ "() on an invalid iterator", .{});
    const out = try ctx.createArray();
    const flags = miFlags(obj);
    var i: usize = 0;
    while (!sic.pending(ctx)) : (i += 1) {
        const st = try storageOf(ctx, obj);
        if (i >= st.len()) break;
        try setInt(ctx, obj, P.pos, @intCast(i));
        const it = st.objAt(i);
        const inf = st.infAt(i);
        VM.retainValue(it);
        VM.retainValue(inf);
        defer {
            ctx.vm.releaseValue(inf);
            ctx.vm.releaseValue(it);
        }
        const vr = try sic.callAny(ctx, it, "valid", &.{});
        const is_valid = vr == .bool and vr.bool;
        var retval: Value = .null;
        if (is_valid) {
            retval = try sic.callAny(ctx, it, what, &.{});
            if (retval == .undef) {
                if (!sic.pending(ctx)) try sic.raise(ctx, "RuntimeException", "Failed to call sub iterator method", .{});
                return error.RuntimeError;
            }
        } else if (flags & MIT_NEED_ALL != 0) {
            if (sic.pending(ctx)) return error.RuntimeError;
            return sic.throwNow(ctx, "RuntimeException", "Called " ++ what ++ "() with non valid sub iterator", .{});
        }
        if (flags & MIT_KEYS_ASSOC != 0) {
            switch (inf) {
                .int, .string => try out.set(ctx.allocator, Value.toArrayKey(inf), retval),
                else => return sic.throwNow(ctx, "InvalidArgumentException", "Sub-Iterator is associated with NULL", .{}),
            }
        } else try out.append(ctx.allocator, retval);
    }
    try setInt(ctx, obj, P.pos, @intCast((try storageOf(ctx, obj)).len()));
    if (sic.pending(ctx)) return error.RuntimeError;
    return NativeResult.borrowed(.{ .array = out });
}

fn miCurrent(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "MultipleIterator::current", args);
    return getAll(ctx, obj, "current");
}

fn miKey(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "MultipleIterator::key", args);
    return getAll(ctx, obj, "key");
}
