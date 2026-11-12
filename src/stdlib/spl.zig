const std = @import("std");
const object_properties = @import("../runtime/object_properties.zig");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeResult = vm_mod.NativeResult;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };
const arrays_mod = @import("arrays.zig");
const sic = @import("spl_iterator_classes.zig");
const phpTypeName = @import("types.zig").phpTypeName;

fn retainReturned(value: Value) Value {
    if (value == .string) value.string.retain();
    return value;
}

pub fn register(vm: *VM, a: Allocator) !void {
    // stdClass - the default empty class for casting and json/pdo decoding
    const std_def = ClassDef{ .name = "stdClass" };
    try vm.classes.put(a, "stdClass", std_def);

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

    // Traversable interface (base for Iterator and IteratorAggregate)
    const traversable = vm_mod.InterfaceDef{ .name = "Traversable" };
    try vm.interfaces.put(a, "Traversable", traversable);

    // UnitEnum / BackedEnum (implemented automatically by every enum decl)
    var unit_enum = vm_mod.InterfaceDef{ .name = "UnitEnum" };
    try unit_enum.methods.append(a, "cases");
    try vm.interfaces.put(a, "UnitEnum", unit_enum);

    var backed_enum = vm_mod.InterfaceDef{ .name = "BackedEnum", .parent = "UnitEnum" };
    try backed_enum.methods.append(a, "from");
    try backed_enum.methods.append(a, "tryFrom");
    try vm.interfaces.put(a, "BackedEnum", backed_enum);

    // Iterator interface
    var iterator = vm_mod.InterfaceDef{ .name = "Iterator" };
    iterator.parent = "Traversable";
    try iterator.methods.append(a, "current");
    try iterator.methods.append(a, "key");
    try iterator.methods.append(a, "next");
    try iterator.methods.append(a, "rewind");
    try iterator.methods.append(a, "valid");
    try vm.interfaces.put(a, "Iterator", iterator);

    // IteratorAggregate interface
    var iter_agg = vm_mod.InterfaceDef{ .name = "IteratorAggregate" };
    iter_agg.parent = "Traversable";
    try iter_agg.methods.append(a, "getIterator");
    try vm.interfaces.put(a, "IteratorAggregate", iter_agg);

    // JsonSerializable interface
    var json_ser = vm_mod.InterfaceDef{ .name = "JsonSerializable" };
    try json_ser.methods.append(a, "jsonSerialize");
    try vm.interfaces.put(a, "JsonSerializable", json_ser);

    // Stringable interface
    var stringable = vm_mod.InterfaceDef{ .name = "Stringable" };
    try stringable.methods.append(a, "__toString");
    try vm.interfaces.put(a, "Stringable", stringable);

    // SessionHandlerInterface / SessionIdInterface / SessionUpdateTimestampHandlerInterface
    // PHP session module exposes these so userland save handlers can implement them
    var sess = vm_mod.InterfaceDef{ .name = "SessionHandlerInterface" };
    try sess.methods.append(a, "open");
    try sess.methods.append(a, "close");
    try sess.methods.append(a, "read");
    try sess.methods.append(a, "write");
    try sess.methods.append(a, "destroy");
    try sess.methods.append(a, "gc");
    try vm.interfaces.put(a, "SessionHandlerInterface", sess);

    var sess_id = vm_mod.InterfaceDef{ .name = "SessionIdInterface" };
    try sess_id.methods.append(a, "create_sid");
    try vm.interfaces.put(a, "SessionIdInterface", sess_id);

    var sess_ts = vm_mod.InterfaceDef{ .name = "SessionUpdateTimestampHandlerInterface" };
    try sess_ts.methods.append(a, "validateId");
    try sess_ts.methods.append(a, "updateTimestamp");
    try vm.interfaces.put(a, "SessionUpdateTimestampHandlerInterface", sess_ts);

    // Serializable - deprecated marker interface still present for code that
    // checks for it. PHP 8 implemented as a soft-marker that types implementing
    // it via __serialize / __unserialize still satisfy
    var serializable = vm_mod.InterfaceDef{ .name = "Serializable" };
    try serializable.methods.append(a, "serialize");
    try serializable.methods.append(a, "unserialize");
    try vm.interfaces.put(a, "Serializable", serializable);

    // ArrayObject
    var ao_def = ClassDef{ .name = "ArrayObject", .native_properties = arrayStorageProperties, .native_clone = splArrayClone };
    // matches PHP's interface order on ArrayObject so getInterfaceNames() lists
    // them the way callers expect
    try ao_def.interfaces.append(a, "IteratorAggregate");
    try ao_def.interfaces.append(a, "ArrayAccess");
    try ao_def.interfaces.append(a, "Serializable");
    try ao_def.interfaces.append(a, "Countable");
    try ao_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 3 });
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
    try ao_def.methods.put(a, "ksort", .{ .name = "ksort", .arity = 1 });
    try ao_def.methods.put(a, "asort", .{ .name = "asort", .arity = 1 });
    try ao_def.methods.put(a, "uksort", .{ .name = "uksort", .arity = 1 });
    try ao_def.methods.put(a, "uasort", .{ .name = "uasort", .arity = 1 });
    try ao_def.methods.put(a, "natsort", .{ .name = "natsort", .arity = 0 });
    try ao_def.methods.put(a, "natcasesort", .{ .name = "natcasesort", .arity = 0 });
    try ao_def.methods.put(a, "exchangeArray", .{ .name = "exchangeArray", .arity = 1 });
    try ao_def.methods.put(a, "setIteratorClass", .{ .name = "setIteratorClass", .arity = 1 });
    try ao_def.methods.put(a, "getIteratorClass", .{ .name = "getIteratorClass", .arity = 0 });
    try ao_def.methods.put(a, "__get", .{ .name = "__get", .arity = 1 });
    try ao_def.methods.put(a, "__set", .{ .name = "__set", .arity = 2 });
    try ao_def.methods.put(a, "__isset", .{ .name = "__isset", .arity = 1 });
    try ao_def.methods.put(a, "__unset", .{ .name = "__unset", .arity = 1 });
    try ao_def.constants.put(a, "STD_PROP_LIST", .{ .int = 1 });
    try ao_def.constant_order.append(a, "STD_PROP_LIST");
    try ao_def.constants.put(a, "ARRAY_AS_PROPS", .{ .int = 2 });
    try ao_def.constant_order.append(a, "ARRAY_AS_PROPS");
    try ao_def.methods.put(a, "__serialize", .{ .name = "__serialize", .arity = 0 });
    try ao_def.methods.put(a, "__unserialize", .{ .name = "__unserialize", .arity = 1 });
    try ao_def.methods.put(a, "serialize", .{ .name = "serialize", .arity = 0 });
    try ao_def.methods.put(a, "unserialize", .{ .name = "unserialize", .arity = 1 });
    try vm.classes.put(a, "ArrayObject", ao_def);

    try vm.native_fns.put(a, "ArrayObject::__serialize", aoSerializeState);
    try vm.native_fns.put(a, "ArrayObject::__unserialize", aoUnserializeState);
    try vm.native_fns.put(a, "ArrayObject::serialize", aoSerialize);
    try vm.native_fns.put(a, "ArrayObject::unserialize", aoUnserialize);
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
    try vm.native_fns.put(a, "ArrayObject::ksort", aoKsort);
    try vm.native_fns.put(a, "ArrayObject::asort", aoAsort);
    try vm.native_fns.put(a, "ArrayObject::uksort", aoUksort);
    try vm.native_fns.put(a, "ArrayObject::uasort", aoUasort);
    try vm.native_fns.put(a, "ArrayObject::natsort", aoNatsort);
    try vm.native_fns.put(a, "ArrayObject::natcasesort", aoNatcasesort);
    try vm.native_fns.put(a, "ArrayObject::exchangeArray", aoExchangeArray);
    try vm.native_fns.put(a, "ArrayObject::setIteratorClass", aoSetIteratorClass);
    try vm.native_fns.put(a, "ArrayObject::getIteratorClass", aoGetIteratorClass);
    try vm.native_fns.put(a, "ArrayObject::__get", aoMagicGet);
    try vm.native_fns.put(a, "ArrayObject::__set", aoMagicSet);
    try vm.native_fns.put(a, "ArrayObject::__isset", aoMagicIsset);
    try vm.native_fns.put(a, "ArrayObject::__unset", aoMagicUnset);

    // ArrayIterator
    var ai_def = ClassDef{ .name = "ArrayIterator", .native_properties = arrayStorageProperties, .native_clone = splArrayClone };
    try ai_def.interfaces.append(a, "Serializable");
    try ai_def.interfaces.append(a, "SeekableIterator");
    try ai_def.interfaces.append(a, "Countable");
    try ai_def.interfaces.append(a, "ArrayAccess");
    try ai_def.constants.put(a, "STD_PROP_LIST", .{ .int = 1 });
    try ai_def.constant_order.append(a, "STD_PROP_LIST");
    try ai_def.constants.put(a, "ARRAY_AS_PROPS", .{ .int = 2 });
    try ai_def.constant_order.append(a, "ARRAY_AS_PROPS");
    try ai_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try ai_def.methods.put(a, "rewind", .{ .name = "rewind", .arity = 0 });
    try ai_def.methods.put(a, "current", .{ .name = "current", .arity = 0 });
    try ai_def.methods.put(a, "key", .{ .name = "key", .arity = 0 });
    try ai_def.methods.put(a, "next", .{ .name = "next", .arity = 0 });
    try ai_def.methods.put(a, "valid", .{ .name = "valid", .arity = 0 });
    try ai_def.methods.put(a, "count", .{ .name = "count", .arity = 0 });
    try ai_def.methods.put(a, "offsetGet", .{ .name = "offsetGet", .arity = 1 });
    try ai_def.methods.put(a, "offsetSet", .{ .name = "offsetSet", .arity = 2 });
    try ai_def.methods.put(a, "offsetExists", .{ .name = "offsetExists", .arity = 1 });
    try ai_def.methods.put(a, "offsetUnset", .{ .name = "offsetUnset", .arity = 1 });
    try ai_def.methods.put(a, "getArrayCopy", .{ .name = "getArrayCopy", .arity = 0 });
    try ai_def.methods.put(a, "append", .{ .name = "append", .arity = 1 });
    try ai_def.methods.put(a, "getFlags", .{ .name = "getFlags", .arity = 0 });
    try ai_def.methods.put(a, "setFlags", .{ .name = "setFlags", .arity = 1 });
    try ai_def.methods.put(a, "ksort", .{ .name = "ksort", .arity = 1 });
    try ai_def.methods.put(a, "asort", .{ .name = "asort", .arity = 1 });
    try ai_def.methods.put(a, "uksort", .{ .name = "uksort", .arity = 1 });
    try ai_def.methods.put(a, "uasort", .{ .name = "uasort", .arity = 1 });
    try ai_def.methods.put(a, "natsort", .{ .name = "natsort", .arity = 0 });
    try ai_def.methods.put(a, "natcasesort", .{ .name = "natcasesort", .arity = 0 });
    try ai_def.methods.put(a, "seek", .{ .name = "seek", .arity = 1 });
    try ai_def.methods.put(a, "__get", .{ .name = "__get", .arity = 1 });
    try ai_def.methods.put(a, "__set", .{ .name = "__set", .arity = 2 });
    try ai_def.methods.put(a, "__isset", .{ .name = "__isset", .arity = 1 });
    try ai_def.methods.put(a, "__unset", .{ .name = "__unset", .arity = 1 });
    try ai_def.methods.put(a, "__serialize", .{ .name = "__serialize", .arity = 0 });
    try ai_def.methods.put(a, "__unserialize", .{ .name = "__unserialize", .arity = 1 });
    try ai_def.methods.put(a, "serialize", .{ .name = "serialize", .arity = 0 });
    try ai_def.methods.put(a, "unserialize", .{ .name = "unserialize", .arity = 1 });
    try vm.classes.put(a, "ArrayIterator", ai_def);

    try vm.native_fns.put(a, "ArrayIterator::__serialize", aoSerializeState);
    try vm.native_fns.put(a, "ArrayIterator::__unserialize", aoUnserializeState);
    try vm.native_fns.put(a, "ArrayIterator::serialize", aoSerialize);
    try vm.native_fns.put(a, "ArrayIterator::unserialize", aoUnserialize);
    try vm.native_fns.put(a, "ArrayIterator::__construct", aiConstruct);
    try vm.native_fns.put(a, "ArrayIterator::rewind", aiRewind);
    try vm.native_fns.put(a, "ArrayIterator::current", aiCurrent);
    try vm.native_fns.put(a, "ArrayIterator::key", aiKey);
    try vm.native_fns.put(a, "ArrayIterator::next", aiNext);
    try vm.native_fns.put(a, "ArrayIterator::valid", aiValid);
    try vm.native_fns.put(a, "ArrayIterator::count", aoCount);
    try vm.native_fns.put(a, "ArrayIterator::offsetGet", aoOffsetGet);
    try vm.native_fns.put(a, "ArrayIterator::offsetSet", aoOffsetSet);
    try vm.native_fns.put(a, "ArrayIterator::offsetExists", aoOffsetExists);
    try vm.native_fns.put(a, "ArrayIterator::offsetUnset", aoOffsetUnset);
    try vm.native_fns.put(a, "ArrayIterator::getArrayCopy", aoGetArrayCopy);
    try vm.native_fns.put(a, "ArrayIterator::append", aoAppend);
    try vm.native_fns.put(a, "ArrayIterator::getFlags", aoGetFlags);
    try vm.native_fns.put(a, "ArrayIterator::setFlags", aoSetFlags);
    try vm.native_fns.put(a, "ArrayIterator::ksort", aoKsort);
    try vm.native_fns.put(a, "ArrayIterator::asort", aoAsort);
    try vm.native_fns.put(a, "ArrayIterator::uksort", aoUksort);
    try vm.native_fns.put(a, "ArrayIterator::uasort", aoUasort);
    try vm.native_fns.put(a, "ArrayIterator::natsort", aoNatsort);
    try vm.native_fns.put(a, "ArrayIterator::natcasesort", aoNatcasesort);
    try vm.native_fns.put(a, "ArrayIterator::seek", aiSeek);
    try vm.native_fns.put(a, "ArrayIterator::__get", aoMagicGet);
    try vm.native_fns.put(a, "ArrayIterator::__set", aoMagicSet);
    try vm.native_fns.put(a, "ArrayIterator::__isset", aoMagicIsset);
    try vm.native_fns.put(a, "ArrayIterator::__unset", aoMagicUnset);

    // WeakMap (simplified - uses spl_object_id as key, no weak reference semantics)
    var wm_def = ClassDef{ .name = "WeakMap", .native_properties = weakMapProperties };
    try wm_def.interfaces.append(a, "ArrayAccess");
    try wm_def.interfaces.append(a, "Countable");
    try wm_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 0 });
    try wm_def.methods.put(a, "offsetExists", .{ .name = "offsetExists", .arity = 1 });
    try wm_def.methods.put(a, "offsetGet", .{ .name = "offsetGet", .arity = 1 });
    try wm_def.methods.put(a, "offsetSet", .{ .name = "offsetSet", .arity = 2 });
    try wm_def.methods.put(a, "offsetUnset", .{ .name = "offsetUnset", .arity = 1 });
    try wm_def.methods.put(a, "count", .{ .name = "count", .arity = 0 });
    try vm.classes.put(a, "WeakMap", wm_def);

    try vm.native_fns.put(a, "WeakMap::__construct", wmConstruct);
    try vm.native_fns.put(a, "WeakMap::offsetExists", wmOffsetExists);
    try vm.native_fns.put(a, "WeakMap::offsetGet", wmOffsetGet);
    try vm.native_fns.put(a, "WeakMap::offsetSet", wmOffsetSet);
    try vm.native_fns.put(a, "WeakMap::offsetUnset", wmOffsetUnset);
    try vm.native_fns.put(a, "WeakMap::count", wmCount);

    var wr_def = ClassDef{ .name = "WeakReference", .is_final = true, .uncloneable = true, .native_properties = weakRefProperties };
    try wr_def.methods.put(a, "create", .{ .name = "create", .arity = 1, .is_static = true });
    try wr_def.methods.put(a, "get", .{ .name = "get", .arity = 0 });
    try wr_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 0 });
    try vm.classes.put(a, "WeakReference", wr_def);
    try vm.native_fns.put(a, "WeakReference::create", weakRefCreate);
    try vm.native_fns.put(a, "WeakReference::get", weakRefGet);
    try vm.native_fns.put(a, "WeakReference::__construct", weakRefConstruct);

    // add iteration support to existing WeakMap
    if (vm.classes.getPtr("WeakMap")) |wm| {
        try wm.interfaces.append(a, "IteratorAggregate");
        try wm.methods.put(a, "getIterator", .{ .name = "getIterator", .arity = 0 });
    }
    try vm.native_fns.put(a, "WeakMap::getIterator", weakMapGetIterator);

    var wmi_def = ClassDef{ .name = "WeakMapIterator" };
    try wmi_def.interfaces.append(a, "Iterator");
    try wmi_def.methods.put(a, "current", .{ .name = "current", .arity = 0 });
    try wmi_def.methods.put(a, "key", .{ .name = "key", .arity = 0 });
    try wmi_def.methods.put(a, "next", .{ .name = "next", .arity = 0 });
    try wmi_def.methods.put(a, "rewind", .{ .name = "rewind", .arity = 0 });
    try wmi_def.methods.put(a, "valid", .{ .name = "valid", .arity = 0 });
    try vm.classes.put(a, "WeakMapIterator", wmi_def);
    try vm.native_fns.put(a, "WeakMapIterator::current", wmiCurrent);
    try vm.native_fns.put(a, "WeakMapIterator::key", wmiKey);
    try vm.native_fns.put(a, "WeakMapIterator::next", wmiNext);
    try vm.native_fns.put(a, "WeakMapIterator::rewind", wmiRewind);
    try vm.native_fns.put(a, "WeakMapIterator::valid", wmiValid);
}

fn wmiCursorObj(this: *PhpObject) ?*PhpObject {
    const objs_v = this.get("__objs");
    if (objs_v != .array) return null;
    const cursor = Value.toInt(this.get("__cursor"));
    if (cursor < 0 or cursor >= @as(i64, @intCast(objs_v.array.entries.items.len))) return null;
    const v = objs_v.array.entries.items[@intCast(cursor)].value;
    if (v != .object) return null;
    return v.object;
}

fn wmiCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const target = wmiCursorObj(this) orelse return NativeResult.scalar(.null);
    const info_v = this.get("__info");
    if (info_v != .array) return NativeResult.scalar(.null);
    return NativeResult.share(info_v.array.get(.{ .int = wmObjKey(.{ .object = target }).? }));
}

fn wmiKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const target = wmiCursorObj(this) orelse return NativeResult.scalar(.null);
    return NativeResult.borrowed(.{ .object = target });
}

fn wmiNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const cur = Value.toInt(this.get("__cursor"));
    try this.set(ctx.allocator, "__cursor", .{ .int = cur + 1 });
    return NativeResult.scalar(.null);
}

fn wmiRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    try this.set(ctx.allocator, "__cursor", .{ .int = 0 });
    return NativeResult.scalar(.null);
}

fn wmiValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const objs_v = this.get("__objs");
    if (objs_v != .array) return NativeResult.scalar(.{ .bool = false });
    const cursor = Value.toInt(this.get("__cursor"));
    return NativeResult.scalar(.{ .bool = cursor >= 0 and cursor < @as(i64, @intCast(objs_v.array.entries.items.len)) });
}

// =========================================================
// WeakReference
// =========================================================

fn weakRefCreate(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.null);
    return NativeResult.borrowed(.{ .object = try ctx.vm.weakReferenceFor(args[0].object) });
}

fn weakRefGet(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const target = this.native.get(PhpObject, .weak_reference) orelse return NativeResult.scalar(.null);
    return NativeResult.share(.{ .object = target });
}

// php 8.5's debug view names the target, or null once it is gone
fn weakRefProperties(ctx: *NativeContext, obj: *PhpObject, purpose: object_properties.Purpose) RuntimeError!?*PhpArray {
    if (purpose != .debug) return null;
    const arr = try object_properties.ownTable(ctx.vm, obj);
    const target: Value = if (obj.native.get(PhpObject, .weak_reference)) |t| .{ .object = t } else .null;
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("object") }, target);
    return arr;
}

fn weakRefConstruct(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    try ctx.vm.setPendingException("Error", "Direct instantiation of WeakReference is not allowed, use WeakReference::create instead");
    return error.RuntimeError;
}

// =========================================================
// WeakMap
// =========================================================

// zend_weakmap_get_properties_for: the debug view lists each entry as
// ["key" => object, "value" => value], in the order they were added
fn weakMapProperties(ctx: *NativeContext, obj: *PhpObject, purpose: object_properties.Purpose) RuntimeError!?*PhpArray {
    if (purpose != .debug) return null;
    const table = try ctx.vm.allocArray();
    const keys_v = obj.get("__keys");
    const data = getData(obj) orelse return table;
    if (keys_v != .array) return table;
    for (keys_v.array.entries.items) |entry| {
        const id = wmObjKey(entry.value) orelse continue;
        if (!data.contains(.{ .int = id })) continue;
        const pair = try ctx.vm.allocArray();
        try pair.set(ctx.allocator, .{ .string = Value.String.borrowed("key") }, entry.value);
        try pair.set(ctx.allocator, .{ .string = Value.String.borrowed("value") }, data.get(.{ .int = id }));
        try table.append(ctx.allocator, .{ .array = pair });
    }
    return table;
}

fn weakMapGetIterator(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const keys_v = obj.get("__keys");
    const data_v = obj.get("__data");
    const iter = try ctx.vm.allocObject(.{ .class_name = "WeakMapIterator" });
    if (keys_v == .array) try iter.set(ctx.allocator, "__objs", keys_v);
    if (data_v == .array) try iter.set(ctx.allocator, "__info", data_v);
    try iter.set(ctx.allocator, "__cursor", .{ .int = 0 });
    return NativeResult.borrowed(.{ .object = iter });
}

// ArrayObject and ArrayIterator (spl_array_get_properties_for and
// get_debug_info): the debug view adds the storage as a private property;
// (array), var_export and json_encode show the storage itself unless
// STD_PROP_LIST asks for the object's own properties
fn arrayStorageProperties(ctx: *NativeContext, obj: *PhpObject, purpose: object_properties.Purpose) RuntimeError!?*PhpArray {
    const storage = obj.get("__data");
    const is_self = storage == .object and storage.object == obj;
    switch (purpose) {
        .debug => {
            const table = try object_properties.ownTable(ctx.vm, obj);
            if (is_self) return table;
            const base = if (ctx.vm.isInstanceOf(obj.class_name, "ArrayIterator")) "ArrayIterator" else "ArrayObject";
            const shown: Value = if (storage == .array or storage == .object) storage else .{ .array = try ctx.vm.allocArray() };
            try object_properties.setMangled(ctx.vm, table, "storage", .private, base, shown);
            return table;
        },
        .array_cast, .var_export, .json => {
            if (splFlags(obj) & STD_PROP_LIST != 0) return null;
            return switch (try splStorage(ctx, obj)) {
                .array => |s| s.arr,
                .object => |o| try tableArray(ctx, o),
            };
        },
        .serialize => return null,
    }
}

fn dataOrEmpty(ctx: *NativeContext, obj: *PhpObject) RuntimeError!Value {
    if (getData(obj)) |arr| return .{ .array = arr };
    return .{ .array = try ctx.vm.allocArray() };
}

// php's serialized forms of the SPL containers, each with the object's own
// properties alongside its contents

// object_properties_load: serialized properties back onto the object, a
// new dynamic one deprecated as any other; zphp's own state is not among them
pub fn loadProperties(ctx: *NativeContext, obj: *PhpObject, members: *PhpArray) RuntimeError!void {
    for (members.entries.items) |entry| {
        var buf: [24]u8 = undefined;
        const key = tableKey(entry.key, &buf);
        const name = if (key.len > 0 and key[0] == 0) if (std.mem.lastIndexOfScalar(u8, key[1..], 0)) |end| key[end + 2 ..] else key else key;
        if (object_properties.isInternalState(ctx.vm, obj, name)) continue;
        if (!obj.properties.contains(name) and !ctx.vm.classDeclaresProperty(obj.class_name, name) and ctx.vm.dynamicPropertyRule(obj) == .deprecated) {
            const msg = try std.fmt.allocPrint(ctx.allocator, "Creation of dynamic property {s}::${s} is deprecated", .{ obj.class_name, name });
            defer ctx.allocator.free(msg);
            try ctx.vm.raiseError(VM.E_DEPRECATED, msg);
        }
        try obj.set(ctx.allocator, name, entry.value);
    }
}

fn illTyped(ctx: *NativeContext) RuntimeError!NativeResult {
    return unexpected(ctx, "Incomplete or ill-typed serialization data");
}

fn unexpected(ctx: *NativeContext, msg: []const u8) RuntimeError!NativeResult {
    try ctx.vm.setPendingException("UnexpectedValueException", msg);
    return error.RuntimeError;
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
    const arr = try ctx.vm.allocArray();
    try obj.set(ctx.allocator, "__data", .{ .array = arr });
    return arr;
}

// --- ArrayObject and ArrayIterator ---
//
// php's spl_array. the storage (`__data`) is an array; another ArrayObject or
// ArrayIterator, whose storage is used (php's USE_OTHER); the object itself
// (IS_SELF); or any other object, whose property table is then read and
// written directly, past visibility, types, readonly and hooks

const STD_PROP_LIST = 1;
const ARRAY_AS_PROPS = 2;
// the flags a clone or an iterator takes from its source
const CLONE_MASK = 0x0100FFFF;
// the flags a script sees; IS_SELF only appears in serialized data
pub const FLAGS_MASK = 0xFFFF;
pub const IS_SELF = 0x01000000;

const SplStorage = union(enum) {
    array: struct { holder: *PhpObject, arr: *PhpArray },
    object: *PhpObject,
};

fn isSplArray(vm: *VM, obj: *PhpObject) bool {
    return vm.isInstanceOf(obj.class_name, "ArrayObject") or vm.isInstanceOf(obj.class_name, "ArrayIterator");
}

// spl_array_get_hash_table
fn splStorage(ctx: *NativeContext, obj: *PhpObject) RuntimeError!SplStorage {
    var holder = obj;
    var depth: usize = 0;
    while (true) : (depth += 1) {
        switch (holder.get("__data")) {
            .array => |arr| return .{ .array = .{ .holder = holder, .arr = arr } },
            .object => |other| {
                if (other == holder) return .{ .object = holder };
                if (depth < 64 and isSplArray(ctx.vm, other)) {
                    holder = other;
                    continue;
                }
                try ctx.vm.triggerLazyInit(other);
                return .{ .object = other.storage() };
            },
            else => return .{ .array = .{ .holder = holder, .arr = try ensureData(ctx, holder) } },
        }
    }
}

// the storage array separated from the copies sharing it, for a write
fn writableArray(ctx: *NativeContext, holder: *PhpObject, arr: *PhpArray) RuntimeError!*PhpArray {
    const sep = try ctx.vm.cowSeparate(arr);
    if (sep != arr) {
        try holder.set(ctx.allocator, "__data", .{ .array = sep });
        sep.refcount -= 1;
    }
    return sep;
}

fn splFlags(obj: *PhpObject) i64 {
    const flags = obj.get("__flags");
    return if (flags == .int) flags.int else 0;
}

// an entry of an object's property table in php's order: declared properties
// first, where one that is unset or typed and never initialized is a hole
// that keeps its place, then dynamic ones in insertion order
const TableProp = struct {
    name: []const u8,
    value: Value,
    slot: bool,
    visibility: ClassDef.Visibility,
    declaring: []const u8,
    hole: bool,

    // the key php's table holds it under, compared without building it
    fn hasKey(self: TableProp, key: []const u8) bool {
        if (!self.slot or self.visibility == .public) return std.mem.eql(u8, key, self.name);
        const class: []const u8 = if (self.visibility == .protected) "*" else self.declaring;
        return key.len == class.len + self.name.len + 2 and key[0] == 0 and
            std.mem.eql(u8, key[1 .. 1 + class.len], class) and key[1 + class.len] == 0 and
            std.mem.endsWith(u8, key, self.name);
    }

    // iteration and count pass over private and protected entries
    fn mangled(self: TableProp) bool {
        return if (self.slot) self.visibility != .public else self.name.len > 0 and self.name[0] == 0;
    }
};

fn tableSize(o: *PhpObject) usize {
    return (if (o.slots) |s| s.len else 0) + o.properties.count();
}

fn tableAt(vm: *VM, o: *PhpObject, pos: usize) ?TableProp {
    const slot_count = if (o.slots) |s| s.len else 0;
    if (pos < slot_count) {
        const layout = o.slot_layout.?;
        const name = layout.names[pos];
        if (object_properties.isInternalState(vm, o, name)) return null;
        const declared = vm.propertyDeclaration(layout.declaring_classes[pos], name);
        const value = o.slots.?[pos];
        const uninitialized = value == .undef or (value == .null and declared.type_str.len > 0 and vm.typedPropForbidsNull(declared.type_str));
        return .{ .name = name, .value = if (value == .undef) .null else value, .slot = true, .visibility = declared.visibility, .declaring = declared.defining_class, .hole = uninitialized or o.isUnset(name) };
    }
    const index = pos - slot_count;
    if (index >= o.properties.count()) return null;
    const name = o.properties.keys()[index];
    if (object_properties.isInternalState(vm, o, name)) return null;
    // an entry beside a non-private slot of the name is not a property of its own
    if (o.slot_layout) |layout| for (layout.names, 0..) |slot_name, i| {
        if (!layout.is_private[i] and std.mem.eql(u8, slot_name, name)) return null;
    };
    return .{ .name = name, .value = o.properties.values()[index], .slot = false, .visibility = .public, .declaring = "", .hole = false };
}

fn tableFind(vm: *VM, o: *PhpObject, key: []const u8, holes: bool) ?TableProp {
    for (0..tableSize(o)) |pos| {
        const prop = tableAt(vm, o, pos) orelse continue;
        if (prop.hole and !holes) continue;
        if (prop.hasKey(key)) return prop;
    }
    return null;
}

fn tableWrite(ctx: *NativeContext, o: *PhpObject, key: []const u8, value: Value) RuntimeError!void {
    if (tableFind(ctx.vm, o, key, true)) |prop| if (prop.slot) {
        return o.setForScope(ctx.allocator, prop.name, value, prop.declaring);
    };
    try o.setDynamic(ctx.allocator, key, value);
}

fn tableUnset(ctx: *NativeContext, o: *PhpObject, key: []const u8) RuntimeError!void {
    const prop = tableFind(ctx.vm, o, key, false) orelse return;
    if (prop.slot) {
        try o.setForScope(ctx.allocator, prop.name, .null, prop.declaring);
        try o.markUnset(ctx.allocator, prop.name);
    } else if (o.removeProperty(ctx.allocator, prop.name)) |old| ctx.vm.releaseValue(old);
}

// the table as an array, under php's keys for private and protected entries
fn tableArray(ctx: *NativeContext, o: *PhpObject) RuntimeError!*PhpArray {
    const arr = try ctx.vm.allocArray();
    for (0..tableSize(o)) |pos| {
        const prop = tableAt(ctx.vm, o, pos) orelse continue;
        if (prop.hole) continue;
        if (prop.slot) {
            try object_properties.setMangled(ctx.vm, arr, prop.name, prop.visibility, prop.declaring, prop.value);
        } else try arr.setCopiedKey(ctx.allocator, prop.name, prop.value);
    }
    return arr;
}

// an offset as php's property table spells it: integers in decimal
fn tableKey(key: PhpArray.Key, buf: *[24]u8) []const u8 {
    return switch (key) {
        .string => |s| s.bytes(),
        .int => |i| std.fmt.bufPrint(buf, "{d}", .{i}) catch unreachable,
    };
}

// php's nApplyCount: a sort of the object's storage is running
fn sorting(obj: *PhpObject) bool {
    const n = obj.get("__sorting");
    return n == .int and n.int > 0;
}

fn forbidDuringSort(ctx: *NativeContext, obj: *PhpObject) RuntimeError!void {
    if (!sorting(obj)) return;
    try ctx.vm.setPendingException("Error", "Modification of ArrayObject during sorting is prohibited");
    return error.RuntimeError;
}

// the class a method's error messages name
fn methodClass(vm: *VM, obj: *PhpObject) []const u8 {
    return if (vm.isInstanceOf(obj.class_name, "ArrayIterator")) "ArrayIterator" else "ArrayObject";
}

fn label(ctx: *NativeContext, obj: *PhpObject, comptime method: []const u8) RuntimeError![]const u8 {
    return std.fmt.allocPrint(ctx.allocator, "{s}::" ++ method, .{methodClass(ctx.vm, obj)});
}

// what a dimension access is for, which names it in an illegal offset error
const KeyUse = enum { read, write, unset, isset };

// get_hash_key: the storage key an offset stands for, or a TypeError thrown
// for one that can't be a key (zend_illegal_container_offset)
fn splKey(ctx: *NativeContext, obj: *PhpObject, offset: Value, use: KeyUse) RuntimeError!PhpArray.Key {
    switch (offset) {
        .null, .undef => {
            try ctx.vm.raiseError(VM.E_DEPRECATED, "Using null as an array offset is deprecated, use an empty string instead");
            if (ctx.vm.pending_exception != null) return error.RuntimeError;
            return .{ .string = Value.String.borrowed("") };
        },
        .string => |str| return PhpArray.normalizeKey(.{ .string = str }),
        .resource => {
            try ctx.vm.warnResourceOffset(offset);
            if (ctx.vm.pending_exception != null) return error.RuntimeError;
            return .{ .int = offset.resource.id };
        },
        .float => |f| {
            const n = Value.toInt(offset);
            if (Value.floatFitsInt(f) and @as(f64, @floatFromInt(n)) != f) {
                const msg = try std.fmt.allocPrint(ctx.allocator, "Implicit conversion from float {s} to int loses precision", .{try @import("spl_iterator_classes.zig").floatText(ctx, f)});
                defer ctx.allocator.free(msg);
                try ctx.vm.raiseError(VM.E_DEPRECATED, msg);
                if (ctx.vm.pending_exception != null) return error.RuntimeError;
            }
            return .{ .int = n };
        },
        .bool => |b| return .{ .int = @intFromBool(b) },
        .int => |n| return .{ .int = n },
        else => {
            const tn = if (offset == .object) offset.object.class_name else phpTypeName(offset);
            const msg = switch (use) {
                .isset => try std.fmt.allocPrint(ctx.allocator, "Cannot access offset of type {s} in isset or empty", .{tn}),
                .unset => try std.fmt.allocPrint(ctx.allocator, "Cannot unset offset of type {s} on {s}", .{ tn, obj.class_name }),
                .read, .write => try std.fmt.allocPrint(ctx.allocator, "Cannot access offset of type {s} on {s}", .{ tn, obj.class_name }),
            };
            defer ctx.allocator.free(msg);
            try ctx.vm.setPendingException("TypeError", msg);
            return error.RuntimeError;
        },
    }
}

// the offset splKey turned into a key, without its notices, for a nested
// write's store back
pub fn plainKey(offset: Value) Value {
    return switch (offset) {
        .null, .undef => .{ .string = Value.String.borrowed("") },
        .resource => |r| .{ .int = r.id },
        .float, .bool => .{ .int = Value.toInt(offset) },
        else => offset,
    };
}

fn splRead(ctx: *NativeContext, obj: *PhpObject, offset: Value) RuntimeError!NativeResult {
    const key = try splKey(ctx, obj, offset, .read);
    switch (try splStorage(ctx, obj)) {
        .array => |s| if (s.arr.getPtr(key)) |entry| return NativeResult.share(if (entry.ref) |ref| ref.* else entry.value),
        .object => |o| {
            var buf: [24]u8 = undefined;
            const name = tableKey(key, &buf);
            if (tableFind(ctx.vm, o, name, false)) |prop| return NativeResult.share(prop.value);
            try ctx.vm.emitUndefinedKeyWarning(.{ .string = Value.String.borrowed(name) });
            return NativeResult.scalar(.null);
        },
    }
    try ctx.vm.emitUndefinedKeyWarning(key);
    return NativeResult.scalar(.null);
}

fn splWrite(ctx: *NativeContext, obj: *PhpObject, offset: Value, value: Value) RuntimeError!void {
    try forbidDuringSort(ctx, obj);
    switch (try splStorage(ctx, obj)) {
        .array => |s| {
            const arr = try writableArray(ctx, s.holder, s.arr);
            if (offset == .null) return arr.append(ctx.allocator, value);
            const key = try splKey(ctx, obj, offset, .write);
            detachSplReference(ctx, arr, key);
            try arr.set(ctx.allocator, key, value);
        },
        .object => |o| {
            var buf: [24]u8 = undefined;
            if (offset == .null) return tableWrite(ctx, o, tableKey(.{ .int = nextTableIndex(ctx.vm, o) }, &buf), value);
            try tableWrite(ctx, o, tableKey(try splKey(ctx, obj, offset, .write), &buf), value);
        },
    }
}

// php appends to a property table under the next integer its hash hands
// out, which only appends advance (an offset written as a number is stored
// as a string); the smallest unused integer name follows that for every
// table not appended to past a removal
fn nextTableIndex(vm: *VM, o: *PhpObject) i64 {
    var next: i64 = 0;
    var buf: [24]u8 = undefined;
    while (tableFind(vm, o, tableKey(.{ .int = next }, &buf), true) != null) next += 1;
    return next;
}

fn splUnset(ctx: *NativeContext, obj: *PhpObject, offset: Value) RuntimeError!void {
    try forbidDuringSort(ctx, obj);
    const key = try splKey(ctx, obj, offset, .unset);
    switch (try splStorage(ctx, obj)) {
        .array => |s| ctx.vm.arrayRemoveOwned(try writableArray(ctx, s.holder, s.arr), key),
        .object => |o| {
            var buf: [24]u8 = undefined;
            try tableUnset(ctx, o, tableKey(key, &buf));
        },
    }
}

// offsetExists reports a null element; isset and empty() look at its value
const ExistsCheck = enum { exists, isset, empty };

fn splHas(ctx: *NativeContext, obj: *PhpObject, offset: Value, check: ExistsCheck) RuntimeError!bool {
    const key = try splKey(ctx, obj, offset, .isset);
    const value: Value = switch (try splStorage(ctx, obj)) {
        .array => |s| if (s.arr.getPtr(key)) |entry| (if (entry.ref) |ref| ref.* else entry.value) else return false,
        .object => |o| blk: {
            var buf: [24]u8 = undefined;
            const prop = tableFind(ctx.vm, o, tableKey(key, &buf), false) orelse return false;
            break :blk prop.value;
        },
    };
    return switch (check) {
        .exists => true,
        .isset => value != .null,
        .empty => !value.isTruthy(),
    };
}

// $o[$k] fetched for a nested write, quiet about a missing key
pub fn arrayStorageFetch(ctx: *NativeContext, obj: *PhpObject, offset: Value) RuntimeError!Value {
    try forbidDuringSort(ctx, obj);
    const key = try splKey(ctx, obj, offset, .write);
    switch (try splStorage(ctx, obj)) {
        .array => |s| if (s.arr.getPtr(key)) |entry| return if (entry.ref) |ref| ref.* else entry.value,
        .object => |o| {
            var buf: [24]u8 = undefined;
            if (tableFind(ctx.vm, o, tableKey(key, &buf), false)) |prop| return prop.value;
        },
    }
    return .null;
}

// $r = &$o[$k]: the storage array and the key of the element to bind, made
// null when missing; null for a storage that is an object's property table
pub const RefTarget = struct { arr: *PhpArray, key: PhpArray.Key };

pub fn arrayStorageRefTarget(ctx: *NativeContext, obj: *PhpObject, offset: Value) RuntimeError!?RefTarget {
    try forbidDuringSort(ctx, obj);
    switch (try splStorage(ctx, obj)) {
        .array => |s| {
            const key: PhpArray.Key = if (offset == .null) .{ .int = if (s.arr.has_int_keys) s.arr.next_int_key else 0 } else try splKey(ctx, obj, offset, .write);
            const arr = try writableArray(ctx, s.holder, s.arr);
            if (arr.getPtr(key) == null) try arr.set(ctx.allocator, key, .null);
            return .{ .arr = arr, .key = key };
        },
        .object => return null,
    }
}

// $o[$k]++: like a reference's target, but a missing element warns before
// it is made, and null is the key "" (BP_VAR_RW)
pub fn arrayStorageRefTargetRW(ctx: *NativeContext, obj: *PhpObject, offset: Value) RuntimeError!?RefTarget {
    try forbidDuringSort(ctx, obj);
    switch (try splStorage(ctx, obj)) {
        .array => |s| {
            const key = try splKey(ctx, obj, offset, .write);
            const arr = try writableArray(ctx, s.holder, s.arr);
            if (arr.getPtr(key) == null) {
                try ctx.vm.emitUndefinedKeyWarning(key);
                if (ctx.vm.pending_exception != null) return error.RuntimeError;
                // a warning handler may have swapped the storage
                const again = switch (try splStorage(ctx, obj)) {
                    .array => |a| a,
                    .object => return null,
                };
                const now = try writableArray(ctx, again.holder, again.arr);
                if (now.getPtr(key) == null) try now.set(ctx.allocator, key, .null);
                return .{ .arr = now, .key = key };
            }
            return .{ .arr = arr, .key = key };
        },
        .object => return null,
    }
}

// $o[$k] ?? ...: the element, or null without a warning
pub fn arrayStorageQuiet(ctx: *NativeContext, obj: *PhpObject, offset: Value) RuntimeError!Value {
    const key = try splKey(ctx, obj, offset, .isset);
    switch (try splStorage(ctx, obj)) {
        .array => |s| if (s.arr.getPtr(key)) |entry| return if (entry.ref) |ref| ref.* else entry.value,
        .object => |o| {
            var buf: [24]u8 = undefined;
            if (tableFind(ctx.vm, o, tableKey(key, &buf), false)) |prop| return prop.value;
        },
    }
    return .null;
}

// property_exists() on an ArrayObject or ArrayIterator with ARRAY_AS_PROPS:
// whether the storage has the element (has_dimension with check_empty 2);
// null for any other object
pub fn propertyAsElementExists(ctx: *NativeContext, obj: *PhpObject, name: Value) RuntimeError!?bool {
    if (!isSplArray(ctx.vm, obj) or !arrayAsProps(obj)) return null;
    if (sic.userMethod(ctx.vm, obj.class_name, "offsetExists")) {
        const r = try sic.callOn(ctx, obj, "offsetExists", &.{name});
        if (sic.pending(ctx)) return error.RuntimeError;
        return r.isTruthy();
    }
    return try splHas(ctx, obj, name, .exists);
}

// isset($o[$k]) on an ArrayObject or ArrayIterator, which looks at the value
pub fn arrayStorageIsset(ctx: *NativeContext, obj: *PhpObject, offset: Value) RuntimeError!bool {
    return splHas(ctx, obj, offset, .isset);
}

fn splCount(ctx: *NativeContext, obj: *PhpObject) RuntimeError!i64 {
    switch (try splStorage(ctx, obj)) {
        .array => |s| return s.arr.length(),
        .object => |o| {
            var count: i64 = 0;
            for (0..tableSize(o)) |pos| {
                const prop = tableAt(ctx.vm, o, pos) orelse continue;
                if (prop.hole or (prop.slot and prop.mangled())) continue;
                count += 1;
            }
            return count;
        },
    }
}

// a copy of the storage as an array
fn splTableCopy(ctx: *NativeContext, obj: *PhpObject) RuntimeError!*PhpArray {
    return switch (try splStorage(ctx, obj)) {
        .array => |s| try ctx.vm.cloneArray(s.arr),
        .object => |o| try tableArray(ctx, o),
    };
}

// zpp's "A": an array or an object, reported as an array
fn requireStorageArg(ctx: *NativeContext, obj: *PhpObject, func: []const u8, arg: Value) RuntimeError!void {
    if (arg == .array or arg == .object) return;
    const class = if (ctx.vm.isInstanceOf(obj.class_name, "ArrayIterator")) "ArrayIterator" else "ArrayObject";
    const msg = try std.fmt.allocPrint(ctx.allocator, "{s}::{s}(): Argument #1 ($array) must be of type array, {s} given", .{ class, func, phpTypeName(arg) });
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("TypeError", msg);
    return error.RuntimeError;
}

// the flags another ArrayObject or ArrayIterator hands on when it becomes
// the storage
pub fn otherFlags(vm: *VM, storage: Value) i64 {
    if (storage == .object and isSplArray(vm, storage.object)) return splFlags(storage.object);
    return 0;
}

// spl_array_set_array: a new storage for the constructor, exchangeArray and
// __unserialize (`func`), with the flags the object ends with
pub fn splSetStorage(ctx: *NativeContext, obj: *PhpObject, storage: Value, flags: i64, func: []const u8) RuntimeError!void {
    try forbidDuringSort(ctx, obj);
    if (storage == .object) {
        const kind = if (ctx.vm.isInstanceOf(obj.class_name, "ArrayIterator")) "ArrayIterator" else "ArrayObject";
        const msg = try std.fmt.allocPrint(ctx.allocator, "{s}::{s}(): Using an object as a backing array for {s} is deprecated, as it allows violating class constraints and invariants", .{ kind, func, kind });
        defer ctx.allocator.free(msg);
        try ctx.vm.raiseError(VM.E_DEPRECATED, msg);
        if (ctx.vm.pending_exception != null) return error.RuntimeError;
        const other = storage.object;
        if (!isSplArray(ctx.vm, other)) {
            if (try overloadedObject(ctx, other)) {
                const msg2 = try std.fmt.allocPrint(ctx.allocator, "Overloaded object of type {s} is not compatible with {s}", .{ other.class_name, obj.class_name });
                defer ctx.allocator.free(msg2);
                try ctx.vm.setPendingException("InvalidArgumentException", msg2);
                return error.RuntimeError;
            }
            if (if (ctx.vm.classes.get(other.class_name)) |def| def.is_enum else false) {
                const msg2 = try std.fmt.allocPrint(ctx.allocator, "Enums are not compatible with {s}", .{obj.class_name});
                defer ctx.allocator.free(msg2);
                try ctx.vm.setPendingException("InvalidArgumentException", msg2);
                return error.RuntimeError;
            }
        }
    }
    try obj.set(ctx.allocator, "__data", storage);
    try obj.set(ctx.allocator, "__flags", .{ .int = flags & FLAGS_MASK });
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
}

// the object as its own storage (IS_SELF), from serialized data
pub fn splSetSelf(ctx: *NativeContext, obj: *PhpObject, flags: i64) RuntimeError!void {
    try obj.set(ctx.allocator, "__data", .{ .object = obj });
    try obj.set(ctx.allocator, "__flags", .{ .int = flags & FLAGS_MASK });
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
}

// the flags serialize writes: IS_SELF when the object is its own storage
pub fn serializedFlags(obj: *PhpObject) i64 {
    const data = obj.get("__data");
    return splFlags(obj) | (if (data == .object and data.object == obj) @as(i64, IS_SELF) else 0);
}

// php's objects whose properties come from a handler rather than a table:
// a built-in class that builds its own table for a purpose past the debug view
fn overloadedObject(ctx: *NativeContext, obj: *PhpObject) RuntimeError!bool {
    var name: ?[]const u8 = obj.class_name;
    while (name) |n| {
        const def = ctx.vm.classes.get(n) orelse return false;
        if (def.native_properties) |hook| return try hook(ctx, obj, .array_cast) != null;
        name = def.parent;
    }
    return false;
}

fn aoSerializeState(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (obj.get("__data") == .null) _ = try ensureData(ctx, obj);
    return @import("serialize.zig").splArrayState(ctx, obj);
}

fn aoUnserializeState(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len == 0 or args[0] != .array) {
        try ctx.vm.setPendingException("TypeError", "__unserialize(): Argument #1 ($data) must be of type array");
        return error.RuntimeError;
    }
    return @import("serialize.zig").restoreSplArrayState(ctx, obj, args[0]);
}

fn aoSerialize(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (obj.get("__data") == .null) _ = try ensureData(ctx, obj);
    return @import("serialize.zig").serializeSplArray(ctx, obj);
}

fn aoUnserialize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len == 0 or args[0] != .string) {
        try ctx.vm.setPendingException("TypeError", "unserialize(): Argument #1 ($data) must be of type string");
        return error.RuntimeError;
    }
    if (args[0].string.bytes().len == 0) return NativeResult.scalar(.null);
    try forbidDuringSort(ctx, obj);
    return @import("serialize.zig").unserializeSplArray(ctx, obj, args[0].string.bytes());
}

// zpp's "C" for an iterator class: the name of ArrayIterator or a subclass
fn argIteratorClass(ctx: *NativeContext, lbl: []const u8, args: []const Value, i: usize) RuntimeError![]const u8 {
    const sv = try sic.toPhpString(ctx, args[i]);
    if (sv == .undef) return error.RuntimeError;
    defer sic.releaseString(sv);
    const raw = sv.string.bytes();
    const name = if (raw.len > 0 and raw[0] == '\\') raw[1..] else raw;
    const vm = ctx.vm;
    if (!vm.classes.contains(name)) {
        vm.tryAutoload(name) catch |err| if (vm.pending_exception == null) return err;
        if (sic.pending(ctx)) return error.RuntimeError;
    }
    if (vm.classes.getKey(name)) |k| {
        if (vm.isInstanceOf(k, "ArrayIterator")) return k;
    }
    try sic.raise(ctx, "TypeError", "{s}(): Argument #{d} ($iteratorClass) must be a class name derived from ArrayIterator, {s} given", .{ lbl, i + 1, raw });
    return error.RuntimeError;
}

fn aoConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len == 0) {
        _ = try ensureData(ctx, obj);
        try obj.set(ctx.allocator, "__flags", .{ .int = 0 });
        try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
        return NativeResult.scalar(.null);
    }
    const lbl = "ArrayObject::__construct";
    if (!try sic.argCount(ctx, lbl, args.len, 0, 3)) return error.RuntimeError;
    try requireStorageArg(ctx, obj, "__construct", args[0]);
    const flags = (try sic.argLong(ctx, lbl, args, 1, "flags", 0)) orelse return error.RuntimeError;
    if (args.len > 2) {
        const class = try argIteratorClass(ctx, lbl, args, 2);
        try obj.set(ctx.allocator, "__iter_class", .{ .string = Value.String.borrowed(class) });
    }
    try splSetStorage(ctx, obj, args[0], if (args.len == 1) otherFlags(ctx.vm, args[0]) else flags, "__construct");
    return NativeResult.scalar(.null);
}

fn aiConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (!try sic.argCount(ctx, "ArrayIterator::__construct", args.len, 0, 2)) return error.RuntimeError;
    if (args.len >= 1) try requireStorageArg(ctx, obj, "__construct", args[0]);
    const flags = (try sic.argLong(ctx, "ArrayIterator::__construct", args, 1, "flags", 0)) orelse return error.RuntimeError;
    if (args.len >= 1) {
        try splSetStorage(ctx, obj, args[0], if (args.len == 1) otherFlags(ctx.vm, args[0]) else flags, "__construct");
    } else {
        _ = try ensureData(ctx, obj);
        try obj.set(ctx.allocator, "__flags", .{ .int = flags });
        try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    }
    return NativeResult.scalar(.null);
}

// ARRAY_AS_PROPS sends a missing property to the storage; without it the
// property is an ordinary one
fn arrayAsProps(obj: *PhpObject) bool {
    return splFlags(obj) & ARRAY_AS_PROPS != 0;
}

fn aoMagicGet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len == 0) return NativeResult.scalar(.null);
    if (arrayAsProps(obj)) return splRead(ctx, obj, args[0]);
    const msg = try std.fmt.allocPrint(ctx.allocator, "Undefined property: {s}::${s}", .{ obj.class_name, args[0].string.bytes() });
    defer ctx.allocator.free(msg);
    try ctx.vm.emitWarning(msg);
    return NativeResult.scalar(.null);
}

fn aoMagicSet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 2) return NativeResult.scalar(.null);
    if (arrayAsProps(obj)) {
        try splWrite(ctx, obj, args[0], args[1]);
        return NativeResult.scalar(.null);
    }
    const name = args[0].string.bytes();
    // an ordinary property write, so creating one is deprecated as anywhere
    if (!obj.properties.contains(name) and !ctx.vm.classDeclaresProperty(obj.class_name, name) and ctx.vm.dynamicPropertyRule(obj) == .deprecated) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "Creation of dynamic property {s}::${s} is deprecated", .{ obj.class_name, name });
        defer ctx.allocator.free(msg);
        try ctx.vm.raiseError(VM.E_DEPRECATED, msg);
    }
    try obj.set(ctx.allocator, name, args[1]);
    return NativeResult.scalar(.null);
}

fn aoMagicIsset(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len == 0 or !arrayAsProps(obj)) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = try splHas(ctx, obj, args[0], .isset) });
}

fn aoMagicUnset(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len == 0 or !arrayAsProps(obj)) return NativeResult.scalar(.null);
    try splUnset(ctx, obj, args[0]);
    return NativeResult.scalar(.null);
}

fn aoOffsetGet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len == 0) return NativeResult.scalar(.null);
    return splRead(ctx, obj, args[0]);
}

fn aoOffsetSet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 2) return NativeResult.scalar(.null);
    try splWrite(ctx, obj, args[0], args[1]);
    return NativeResult.scalar(.null);
}

fn aoOffsetExists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = try splHas(ctx, obj, args[0], .exists) });
}

fn aoOffsetUnset(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len == 0) return NativeResult.scalar(.null);
    try splUnset(ctx, obj, args[0]);
    return NativeResult.scalar(.null);
}

fn aoCount(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = try splCount(ctx, obj) });
}

fn aoAppend(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len == 0) return NativeResult.scalar(.null);
    if (try splStorage(ctx, obj) == .object) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "Cannot append properties to objects, use {s}::offsetSet() instead", .{obj.class_name});
        defer ctx.allocator.free(msg);
        try ctx.vm.setPendingException("Error", msg);
        return error.RuntimeError;
    }
    try splWrite(ctx, obj, .null, args[0]);
    return NativeResult.scalar(.null);
}

fn aoGetArrayCopy(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.borrowed(.{ .array = try splTableCopy(ctx, obj) });
}

const SplSort = union(enum) {
    values: i64,
    keys: i64,
    user_values: Value,
    user_keys: Value,
    natural: bool,
};

// spl_array_method: the sort function run on the storage, which nothing
// may change while it runs
fn splSort(ctx: *NativeContext, how: SplSort) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const before = obj.get("__sorting");
    const depth: i64 = if (before == .int) before.int else 0;
    try obj.set(ctx.allocator, "__sorting", .{ .int = depth + 1 });
    defer obj.set(ctx.allocator, "__sorting", .{ .int = depth }) catch {};
    switch (try splStorage(ctx, obj)) {
        .array => |s| try sortEntries(ctx, try writableArray(ctx, s.holder, s.arr), how),
        .object => |o| {
            // zphp keeps declared properties in declaration order, so only a
            // table of dynamic properties can take the sorted order
            const table = try tableArray(ctx, o);
            defer ctx.vm.releaseValue(.{ .array = table });
            table.refcount += 1;
            try sortEntries(ctx, table, how);
            for (0..tableSize(o)) |pos| {
                const prop = tableAt(ctx.vm, o, pos) orelse continue;
                if (prop.slot and !prop.hole) return NativeResult.scalar(.{ .bool = true });
            }
            const SortByTable = struct {
                keys: []const []const u8,
                table: *PhpArray,
                fn rank(self: @This(), index: usize) usize {
                    var buf: [24]u8 = undefined;
                    for (self.table.entries.items, 0..) |entry, i| {
                        if (std.mem.eql(u8, tableKey(entry.key, &buf), self.keys[index])) return i;
                    }
                    return std.math.maxInt(usize);
                }
                pub fn lessThan(self: @This(), a: usize, b: usize) bool {
                    return self.rank(a) < self.rank(b);
                }
            };
            o.properties.sort(SortByTable{ .keys = o.properties.keys(), .table = table });
        },
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn sortEntries(ctx: *NativeContext, arr: *PhpArray, how: SplSort) RuntimeError!void {
    try @import("array_sort.zig").sortStorage(ctx, arr, switch (how) {
        .values => |flags| .{ .values = flags },
        .keys => |flags| .{ .keys = flags },
        .user_values => |callback| .{ .user_values = callback },
        .user_keys => |callback| .{ .user_keys = callback },
        .natural => |fold_case| .{ .natural = fold_case },
    });
}

// "|l": the sort flags
fn sortFlags(ctx: *NativeContext, args: []const Value, comptime method: []const u8) RuntimeError!i64 {
    const obj = getThis(ctx) orelse return 0;
    const lbl = try label(ctx, obj, method);
    defer ctx.allocator.free(lbl);
    if (!try sic.argCount(ctx, lbl, args.len, 0, 1)) return error.RuntimeError;
    return (try sic.argLong(ctx, lbl, args, 0, "flags", 0)) orelse error.RuntimeError;
}

// "z": the comparison callback, checked by the sort function it goes to
fn sortCallback(ctx: *NativeContext, args: []const Value, comptime method: []const u8) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const lbl = try label(ctx, obj, method);
    defer ctx.allocator.free(lbl);
    if (!try sic.argCount(ctx, lbl, args.len, 1, 1)) return error.RuntimeError;
    return args[0];
}

fn noSortArgs(ctx: *NativeContext, args: []const Value, comptime method: []const u8) RuntimeError!void {
    const obj = getThis(ctx) orelse return;
    const lbl = try label(ctx, obj, method);
    defer ctx.allocator.free(lbl);
    if (!try sic.argCount(ctx, lbl, args.len, 0, 0)) return error.RuntimeError;
}

fn aoKsort(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return splSort(ctx, .{ .keys = try sortFlags(ctx, args, "ksort") });
}

fn aoAsort(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return splSort(ctx, .{ .values = try sortFlags(ctx, args, "asort") });
}

fn aoUasort(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return splSort(ctx, .{ .user_values = try sortCallback(ctx, args, "uasort") });
}

fn aoUksort(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return splSort(ctx, .{ .user_keys = try sortCallback(ctx, args, "uksort") });
}

fn aoNatsort(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    try noSortArgs(ctx, args, "natsort");
    return splSort(ctx, .{ .natural = false });
}

fn aoNatcasesort(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    try noSortArgs(ctx, args, "natcasesort");
    return splSort(ctx, .{ .natural = true });
}

fn aoExchangeArray(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (!try sic.argCount(ctx, "ArrayObject::exchangeArray", args.len, 1, 1)) return error.RuntimeError;
    try requireStorageArg(ctx, obj, "exchangeArray", args[0]);
    try forbidDuringSort(ctx, obj);
    const old = try splTableCopy(ctx, obj);
    errdefer ctx.vm.releaseValue(.{ .array = old });
    // the new storage's flags join the ones the object has
    try splSetStorage(ctx, obj, args[0], splFlags(obj) | otherFlags(ctx.vm, args[0]), "exchangeArray");
    return NativeResult.borrowed(.{ .array = old });
}

fn aoSetIteratorClass(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const lbl = "ArrayObject::setIteratorClass";
    if (!try sic.argCount(ctx, lbl, args.len, 1, 1)) return error.RuntimeError;
    const class = try argIteratorClass(ctx, lbl, args, 0);
    try obj.set(ctx.allocator, "__iter_class", .{ .string = Value.String.borrowed(class) });
    return NativeResult.scalar(.null);
}

// the iterator works on this object's storage, with its own position
fn aoGetIterator(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const ic = obj.get("__iter_class");
    const cls_name = if (ic == .string and ic.string.bytes().len > 0) ic.string.bytes() else "ArrayIterator";
    const it = try ctx.createObject(cls_name);
    try it.set(ctx.allocator, "__data", .{ .object = obj });
    try it.set(ctx.allocator, "__cursor", .{ .int = 0 });
    try it.set(ctx.allocator, "__flags", .{ .int = splFlags(obj) & CLONE_MASK });
    return NativeResult.borrowed(.{ .object = it });
}

fn aoGetIteratorClass(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.literal("ArrayIterator");
    const ic = obj.get("__iter_class");
    if (ic == .string and ic.string.bytes().len > 0) return NativeResult.shareString(ic.string);
    return NativeResult.literal("ArrayIterator");
}

fn aoSetFlags(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len >= 1) try obj.set(ctx.allocator, "__flags", .{ .int = Value.toInt(args[0]) & FLAGS_MASK });
    return NativeResult.scalar(.null);
}

fn aoGetFlags(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = splFlags(obj) });
}

// a clone of an ArrayObject owns a copy of the storage; a clone of an
// ArrayIterator works on the original's storage
fn splArrayClone(vm: *VM, src: *PhpObject, copy: *PhpObject) bool {
    var ctx = vm.makeContext(null);
    const data = src.get("__data");
    if (data == .object and data.object == src) {
        copy.set(vm.allocator, "__data", .{ .object = copy }) catch return false;
    } else if (vm.isInstanceOf(src.class_name, "ArrayIterator")) {
        copy.set(vm.allocator, "__data", .{ .object = src }) catch return false;
    } else {
        const table = splTableCopy(&ctx, src) catch return false;
        copy.set(vm.allocator, "__data", .{ .array = table }) catch return false;
    }
    return true;
}

// --- ArrayIterator ---

// a position iteration visits, at or after `from`: an array's next entry, or
// the next public, initialized entry of a property table
fn iterPosition(ctx: *NativeContext, obj: *PhpObject, from: usize) RuntimeError!?usize {
    switch (try splStorage(ctx, obj)) {
        .array => |s| return if (from < s.arr.entries.items.len) from else null,
        .object => |o| {
            var pos = from;
            while (pos < tableSize(o)) : (pos += 1) {
                const prop = tableAt(ctx.vm, o, pos) orelse continue;
                if (!prop.hole and !prop.mangled()) return pos;
            }
            return null;
        },
    }
}

fn storageEnd(storage: SplStorage) usize {
    return switch (storage) {
        .array => |s| s.arr.entries.items.len,
        .object => |o| tableSize(o),
    };
}

fn cursorOf(obj: *PhpObject) usize {
    return @intCast(@max(Value.toInt(obj.get("__cursor")), 0));
}

fn aiRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    return NativeResult.scalar(.null);
}

// the element at an ArrayIterator's position, or null past the end
pub fn iteratorCurrent(ctx: *NativeContext, obj: *PhpObject) RuntimeError!?Value {
    const pos = try iterPosition(ctx, obj, cursorOf(obj)) orelse return null;
    return switch (try splStorage(ctx, obj)) {
        .array => |s| blk: {
            const entry = s.arr.entries.items[pos];
            break :blk if (entry.ref) |ref| ref.* else entry.value;
        },
        .object => |o| tableAt(ctx.vm, o, pos).?.value,
    };
}

pub fn iteratorFlags(obj: *PhpObject) i64 {
    return splFlags(obj);
}

fn aiCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(try iteratorCurrent(ctx, obj) orelse .null);
}

fn aiKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const pos = try iterPosition(ctx, obj, cursorOf(obj)) orelse return NativeResult.scalar(.null);
    return switch (try splStorage(ctx, obj)) {
        .array => |s| switch (s.arr.entries.items[pos].key) {
            .int => |i| NativeResult.scalar(.{ .int = i }),
            .string => |value| NativeResult.shareString(value),
        },
        .object => |o| NativeResult.takeString(try Value.String.create(ctx.allocator, tableAt(ctx.vm, o, pos).?.name)),
    };
}

fn aiNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const pos = try iterPosition(ctx, obj, cursorOf(obj)) orelse return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__cursor", .{ .int = @intCast(pos + 1) });
    return NativeResult.scalar(.null);
}

fn aiValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = try iterPosition(ctx, obj, cursorOf(obj)) != null });
}

fn aiSeek(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const target = if (args.len >= 1) Value.toInt(args[0]) else 0;
    if (target >= 0) {
        var pos = try iterPosition(ctx, obj, 0);
        var steps = target;
        while (steps > 0) : (steps -= 1) {
            const at = pos orelse break;
            pos = try iterPosition(ctx, obj, at + 1);
        }
        if (pos) |at| {
            try obj.set(ctx.allocator, "__cursor", .{ .int = @intCast(at) });
            return NativeResult.scalar(.null);
        }
    }
    if (target >= 0) try obj.set(ctx.allocator, "__cursor", .{ .int = @intCast(storageEnd(try splStorage(ctx, obj))) });
    const msg = try std.fmt.allocPrint(ctx.allocator, "Seek position {d} is out of range", .{target});
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("OutOfBoundsException", msg);
    return error.RuntimeError;
}

// --- WeakMap ---

fn wmObjKey(arg: Value) ?i64 {
    if (arg == .object) return @intCast(@intFromPtr(arg.object));
    return null;
}

fn wmConstruct(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    _ = try ensureData(ctx, obj);
    // __keys parallel-tracks the object references in insertion order so that
    // iteration can yield real object keys (the int-keyed __data only has pointers)
    if (obj.get("__keys") != .array) {
        const keys = try ctx.createArray();
        keys.weak = true;
        try obj.set(ctx.allocator, "__keys", .{ .array = keys });
    }
    // register for weak-key cleanup on object destruct
    try ctx.vm.weakmaps.append(ctx.allocator, obj);
    return NativeResult.scalar(.null);
}

// zend_weakmap's dimension handlers refuse anything but an object key, and a
// missing one (`$map[]`) is an append, which a WeakMap can't do
fn wmKeyOf(ctx: *NativeContext, args: []const Value) RuntimeError!i64 {
    const offset: Value = if (args.len > 0) args[0] else .null;
    if (offset == .null) {
        try ctx.vm.setPendingException("Error", "Cannot append to WeakMap");
        return error.RuntimeError;
    }
    return wmObjKey(offset) orelse {
        try ctx.vm.setPendingException("TypeError", "WeakMap key must be an object");
        return error.RuntimeError;
    };
}

fn wmOffsetExists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len == 0 or args[0] != .object) {
        try ctx.vm.setPendingException("TypeError", "WeakMap key must be an object");
        return error.RuntimeError;
    }
    const key = try wmKeyOf(ctx, args);
    const arr = getData(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const k = PhpArray.Key{ .int = key };
    return NativeResult.scalar(.{ .bool = arr.get(k) != .null });
}

fn wmOffsetGet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const key = try wmKeyOf(ctx, args);
    const arr = getData(obj);
    if (arr == null or !arr.?.contains(.{ .int = key })) {
        const o = args[0].object;
        const msg = try std.fmt.allocPrint(ctx.allocator, "Object {s}#{d} not contained in WeakMap", .{ o.class_name, o.id });
        defer ctx.allocator.free(msg);
        try ctx.vm.setPendingException("Error", msg);
        return error.RuntimeError;
    }
    return NativeResult.share(arr.?.get(.{ .int = key }));
}

fn wmOffsetSet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = try ensureData(ctx, obj);
    if (args.len < 2) return NativeResult.scalar(.null);
    const key = try wmKeyOf(ctx, args);
    const is_new = arr.get(.{ .int = key }) == .null;
    try ctx.vm.arraySetOwned(arr, .{ .int = key }, args[1]);
    if (is_new and args[0] == .object) {
        const keys_v = obj.get("__keys");
        // __keys is a weak array: appending takes no reference, and the
        // weakmapsOnObjectDestruct hook drops the stale __keys / __data entry
        // when the key object becomes unreachable
        if (keys_v == .array) try keys_v.array.append(ctx.allocator, args[0]);
    }
    return NativeResult.scalar(.null);
}

fn wmOffsetUnset(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    if (args.len == 0 or args[0] != .object) {
        try ctx.vm.setPendingException("TypeError", "WeakMap key must be an object");
        return error.RuntimeError;
    }
    const key = wmObjKey(args[0]).?;
    ctx.vm.arrayRemoveOwned(arr, .{ .int = key });
    if (args[0] == .object) {
        const keys_v = obj.get("__keys");
        if (keys_v == .array) {
            const target = args[0].object;
            for (keys_v.array.entries.items, 0..) |e, i| {
                if (e.value == .object and e.value.object == target) {
                    _ = keys_v.array.entries.orderedRemove(i);
                    break;
                }
            }
        }
    }
    return NativeResult.scalar(.null);
}

fn wmCount(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const arr = getData(obj) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = @intCast(arr.entries.items.len) });
}

// SPL offsetSet replaces the bucket, rather than writing through a reference
// in it (unlike a PHP array assignment).
fn detachSplReference(ctx: *NativeContext, arr: *PhpArray, key: PhpArray.Key) void {
    const entry = arr.getPtr(key) orelse return;
    const cell = entry.ref orelse return;
    entry.ref = null;
    if (ctx.vm.ref_index) |index| index.removeTargetAllOwners(ctx.allocator, cell, .{ .array = .{ .array = arr, .key = key } });
    var i: usize = 0;
    while (i < ctx.vm.array_ref_bindings.items.len) {
        const binding = ctx.vm.array_ref_bindings.items[i];
        if (binding.array == arr and binding.key.eql(key)) {
            _ = ctx.vm.array_ref_bindings.swapRemove(i);
        } else i += 1;
    }
    if (@import("../runtime/value.zig").hooks().cell_unbind) |hook| hook.call(hook.ctx, cell);
}
