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
const phpTypeName = @import("types.zig").phpTypeName;

fn retainReturned(value: Value) Value {
    if (value == .string) value.string.retain();
    return value;
}

// PHP's SplObjectStorage offset* methods strictly require an object key
// and throw TypeError on any other type. centralized helper so all four
// offsetExists/Get/Set/Unset emit the same PHP-format message
fn sosRequireObjectKey(ctx: *NativeContext, fn_name: []const u8, key: Value) !bool {
    if (key == .object) return true;
    const msg = try std.fmt.allocPrint(ctx.allocator, "SplObjectStorage::{s}(): Argument #1 ($object) must be of type object, {s} given", .{ fn_name, phpTypeName(key) });
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("TypeError", msg);
    return false;
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

    var observer = vm_mod.InterfaceDef{ .name = "SplObserver" };
    try observer.methods.append(a, "update");
    try vm.interfaces.put(a, "SplObserver", observer);

    var subject = vm_mod.InterfaceDef{ .name = "SplSubject" };
    try subject.methods.append(a, "attach");
    try subject.methods.append(a, "detach");
    try subject.methods.append(a, "notify");
    try vm.interfaces.put(a, "SplSubject", subject);

    // SplStack
    var stack_def = ClassDef{ .name = "SplStack", .parent = "SplDoublyLinkedList" };
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
    try stack_def.methods.put(a, "offsetGet", .{ .name = "offsetGet", .arity = 1 });
    try stack_def.methods.put(a, "offsetSet", .{ .name = "offsetSet", .arity = 2 });
    try stack_def.methods.put(a, "offsetExists", .{ .name = "offsetExists", .arity = 1 });
    try stack_def.methods.put(a, "offsetUnset", .{ .name = "offsetUnset", .arity = 1 });
    try vm.classes.put(a, "SplStack", stack_def);

    try vm.native_fns.put(a, "SplStack::offsetGet", stackOffsetGet);
    try vm.native_fns.put(a, "SplStack::offsetSet", stackOffsetSet);
    try vm.native_fns.put(a, "SplStack::offsetExists", stackOffsetExists);
    try vm.native_fns.put(a, "SplStack::offsetUnset", stackOffsetUnset);

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
    try ao_def.constants.put(a, "ARRAY_AS_PROPS", .{ .int = 2 });
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
    var wm_def = ClassDef{ .name = "WeakMap" };
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

    // SplPriorityQueue
    var pq_def = ClassDef{ .name = "SplPriorityQueue", .native_properties = priorityQueueProperties };
    try pq_def.interfaces.append(a, "Countable");
    try pq_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 0 });
    try pq_def.methods.put(a, "insert", .{ .name = "insert", .arity = 2 });
    try pq_def.methods.put(a, "extract", .{ .name = "extract", .arity = 0 });
    try pq_def.methods.put(a, "top", .{ .name = "top", .arity = 0 });
    try pq_def.methods.put(a, "count", .{ .name = "count", .arity = 0 });
    try pq_def.methods.put(a, "isEmpty", .{ .name = "isEmpty", .arity = 0 });
    try pq_def.methods.put(a, "setExtractFlags", .{ .name = "setExtractFlags", .arity = 1 });
    try pq_def.methods.put(a, "current", .{ .name = "current", .arity = 0 });
    try pq_def.methods.put(a, "key", .{ .name = "key", .arity = 0 });
    try pq_def.methods.put(a, "next", .{ .name = "next", .arity = 0 });
    try pq_def.methods.put(a, "rewind", .{ .name = "rewind", .arity = 0 });
    try pq_def.methods.put(a, "valid", .{ .name = "valid", .arity = 0 });
    try pq_def.constants.put(a, "EXTR_DATA", .{ .int = EXTR_DATA });
    try pq_def.constants.put(a, "EXTR_PRIORITY", .{ .int = EXTR_PRIORITY });
    try pq_def.constants.put(a, "EXTR_BOTH", .{ .int = EXTR_BOTH });
    try pq_def.methods.put(a, "__serialize", .{ .name = "__serialize", .arity = 0 });
    try pq_def.methods.put(a, "__unserialize", .{ .name = "__unserialize", .arity = 1 });
    try vm.classes.put(a, "SplPriorityQueue", pq_def);

    try vm.native_fns.put(a, "SplPriorityQueue::__construct", pqConstruct);
    try vm.native_fns.put(a, "SplPriorityQueue::__serialize", heapSerialize);
    try vm.native_fns.put(a, "SplPriorityQueue::__unserialize", heapUnserialize);
    try vm.native_fns.put(a, "SplPriorityQueue::insert", pqInsert);
    try vm.native_fns.put(a, "SplPriorityQueue::extract", pqExtract);
    try vm.native_fns.put(a, "SplPriorityQueue::top", pqTop);
    try vm.native_fns.put(a, "SplPriorityQueue::count", pqCount);
    try vm.native_fns.put(a, "SplPriorityQueue::isEmpty", pqIsEmpty);
    try vm.native_fns.put(a, "SplPriorityQueue::setExtractFlags", pqSetExtractFlags);
    try vm.native_fns.put(a, "SplPriorityQueue::current", pqCurrent);
    try vm.native_fns.put(a, "SplPriorityQueue::key", pqKey);
    try vm.native_fns.put(a, "SplPriorityQueue::next", pqNext);
    try vm.native_fns.put(a, "SplPriorityQueue::rewind", pqRewind);
    try vm.native_fns.put(a, "SplPriorityQueue::valid", pqValid);

    // SplHeap (abstract: subclasses define compare), SplMinHeap, SplMaxHeap
    const heap_methods = .{
        .{ "__construct", 0, heapConstruct },
        .{ "insert", 1, heapInsert },
        .{ "extract", 0, heapExtract },
        .{ "top", 0, heapTop },
        .{ "count", 0, heapCount },
        .{ "isEmpty", 0, heapIsEmpty },
        .{ "current", 0, heapCurrent },
        .{ "key", 0, heapKey },
        .{ "next", 0, heapNext },
        .{ "rewind", 0, heapRewind },
        .{ "valid", 0, heapValid },
        .{ "isCorrupted", 0, heapIsCorrupted },
        .{ "recoverFromCorruption", 0, heapRecoverFromCorruption },
    };
    const heap_classes = .{
        .{ "SplHeap", @as(?[]const u8, null), @as(?vm_mod.NativeFn, null) },
        .{ "SplMinHeap", @as(?[]const u8, "SplHeap"), @as(?vm_mod.NativeFn, minHeapCompare) },
        .{ "SplMaxHeap", @as(?[]const u8, "SplHeap"), @as(?vm_mod.NativeFn, maxHeapCompare) },
    };
    inline for (heap_classes) |hc| {
        var def = ClassDef{ .name = hc[0], .parent = hc[1], .native_properties = heapProperties };
        try def.interfaces.append(a, "Iterator");
        try def.interfaces.append(a, "Countable");
        inline for (heap_methods) |m| {
            try def.methods.put(a, m[0], .{ .name = m[0], .arity = m[1] });
            try vm.native_fns.put(a, hc[0] ++ "::" ++ m[0], m[2]);
        }
        if (hc[2]) |compare| {
            try def.methods.put(a, "compare", .{ .name = "compare", .arity = 2, .visibility = .protected });
            try vm.native_fns.put(a, hc[0] ++ "::compare", compare);
        }
        try def.methods.put(a, "__serialize", .{ .name = "__serialize", .arity = 0 });
        try def.methods.put(a, "__unserialize", .{ .name = "__unserialize", .arity = 1 });
        try vm.native_fns.put(a, hc[0] ++ "::__serialize", heapSerialize);
        try vm.native_fns.put(a, hc[0] ++ "::__unserialize", heapUnserialize);
        try vm.classes.put(a, hc[0], def);
    }

    // SplFixedArray
    var fa_def = ClassDef{ .name = "SplFixedArray", .native_properties = fixedArrayProperties };
    try fa_def.interfaces.append(a, "Traversable");
    try fa_def.interfaces.append(a, "Countable");
    try fa_def.interfaces.append(a, "ArrayAccess");
    try fa_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try fa_def.methods.put(a, "getSize", .{ .name = "getSize", .arity = 0 });
    try fa_def.methods.put(a, "setSize", .{ .name = "setSize", .arity = 1 });
    try fa_def.methods.put(a, "count", .{ .name = "count", .arity = 0 });
    try fa_def.methods.put(a, "toArray", .{ .name = "toArray", .arity = 0 });
    try fa_def.methods.put(a, "fromArray", .{ .name = "fromArray", .arity = 1, .is_static = true });
    try fa_def.methods.put(a, "offsetGet", .{ .name = "offsetGet", .arity = 1 });
    try fa_def.methods.put(a, "offsetSet", .{ .name = "offsetSet", .arity = 2 });
    try fa_def.methods.put(a, "offsetExists", .{ .name = "offsetExists", .arity = 1 });
    try fa_def.methods.put(a, "offsetUnset", .{ .name = "offsetUnset", .arity = 1 });
    try fa_def.methods.put(a, "current", .{ .name = "current", .arity = 0 });
    try fa_def.methods.put(a, "key", .{ .name = "key", .arity = 0 });
    try fa_def.methods.put(a, "next", .{ .name = "next", .arity = 0 });
    try fa_def.methods.put(a, "rewind", .{ .name = "rewind", .arity = 0 });
    try fa_def.methods.put(a, "valid", .{ .name = "valid", .arity = 0 });
    try fa_def.methods.put(a, "__serialize", .{ .name = "__serialize", .arity = 0 });
    try fa_def.methods.put(a, "__unserialize", .{ .name = "__unserialize", .arity = 1 });
    try vm.classes.put(a, "SplFixedArray", fa_def);

    try vm.native_fns.put(a, "SplFixedArray::__construct", faConstruct);
    try vm.native_fns.put(a, "SplFixedArray::__serialize", fixedArraySerialize);
    try vm.native_fns.put(a, "SplFixedArray::__unserialize", fixedArrayUnserialize);
    try vm.native_fns.put(a, "SplFixedArray::getSize", faGetSize);
    try vm.native_fns.put(a, "SplFixedArray::setSize", faSetSize);
    try vm.native_fns.put(a, "SplFixedArray::count", faCount);
    try vm.native_fns.put(a, "SplFixedArray::toArray", faToArray);
    try vm.native_fns.put(a, "SplFixedArray::fromArray", faFromArray);
    try vm.native_fns.put(a, "SplFixedArray::offsetGet", faOffsetGet);
    try vm.native_fns.put(a, "SplFixedArray::offsetSet", faOffsetSet);
    try vm.native_fns.put(a, "SplFixedArray::offsetExists", faOffsetExists);
    try vm.native_fns.put(a, "SplFixedArray::offsetUnset", faOffsetUnset);
    try vm.native_fns.put(a, "SplFixedArray::current", faCurrent);
    try vm.native_fns.put(a, "SplFixedArray::key", faKey);
    try vm.native_fns.put(a, "SplFixedArray::next", faNext);
    try vm.native_fns.put(a, "SplFixedArray::rewind", faRewind);
    try vm.native_fns.put(a, "SplFixedArray::valid", faValid);

    // SplQueue
    var sq_def = ClassDef{ .name = "SplQueue", .parent = "SplDoublyLinkedList" };
    try sq_def.interfaces.append(a, "Countable");
    try sq_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 0 });
    try sq_def.methods.put(a, "enqueue", .{ .name = "enqueue", .arity = 1 });
    try sq_def.methods.put(a, "dequeue", .{ .name = "dequeue", .arity = 0 });
    try sq_def.methods.put(a, "bottom", .{ .name = "bottom", .arity = 0 });
    try sq_def.methods.put(a, "top", .{ .name = "top", .arity = 0 });
    try sq_def.methods.put(a, "count", .{ .name = "count", .arity = 0 });
    try sq_def.methods.put(a, "isEmpty", .{ .name = "isEmpty", .arity = 0 });
    try sq_def.methods.put(a, "current", .{ .name = "current", .arity = 0 });
    try sq_def.methods.put(a, "key", .{ .name = "key", .arity = 0 });
    try sq_def.methods.put(a, "next", .{ .name = "next", .arity = 0 });
    try sq_def.methods.put(a, "rewind", .{ .name = "rewind", .arity = 0 });
    try sq_def.methods.put(a, "valid", .{ .name = "valid", .arity = 0 });
    try vm.classes.put(a, "SplQueue", sq_def);

    try vm.native_fns.put(a, "SplQueue::__construct", sqConstruct);
    try vm.native_fns.put(a, "SplQueue::enqueue", sqEnqueue);
    try vm.native_fns.put(a, "SplQueue::dequeue", sqDequeue);
    try vm.native_fns.put(a, "SplQueue::bottom", sqBottom);
    try vm.native_fns.put(a, "SplQueue::top", sqTop);
    try vm.native_fns.put(a, "SplQueue::count", sqCount);
    try vm.native_fns.put(a, "SplQueue::isEmpty", sqIsEmpty);
    try vm.native_fns.put(a, "SplQueue::current", sqCurrent);
    try vm.native_fns.put(a, "SplQueue::key", sqKey);
    try vm.native_fns.put(a, "SplQueue::next", sqNext);
    try vm.native_fns.put(a, "SplQueue::rewind", sqRewind);
    try vm.native_fns.put(a, "SplQueue::valid", sqValid);

    // SplDoublyLinkedList
    var dll_def = ClassDef{ .name = "SplDoublyLinkedList", .native_properties = listProperties };
    try dll_def.interfaces.append(a, "Iterator");
    try dll_def.interfaces.append(a, "Countable");
    try dll_def.interfaces.append(a, "ArrayAccess");
    try dll_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 0 });
    try dll_def.methods.put(a, "push", .{ .name = "push", .arity = 1 });
    try dll_def.methods.put(a, "pop", .{ .name = "pop", .arity = 0 });
    try dll_def.methods.put(a, "unshift", .{ .name = "unshift", .arity = 1 });
    try dll_def.methods.put(a, "shift", .{ .name = "shift", .arity = 0 });
    try dll_def.methods.put(a, "top", .{ .name = "top", .arity = 0 });
    try dll_def.methods.put(a, "bottom", .{ .name = "bottom", .arity = 0 });
    try dll_def.methods.put(a, "count", .{ .name = "count", .arity = 0 });
    try dll_def.methods.put(a, "isEmpty", .{ .name = "isEmpty", .arity = 0 });
    try dll_def.methods.put(a, "setIteratorMode", .{ .name = "setIteratorMode", .arity = 1 });
    try dll_def.methods.put(a, "getIteratorMode", .{ .name = "getIteratorMode", .arity = 0 });
    try dll_def.methods.put(a, "rewind", .{ .name = "rewind", .arity = 0 });
    try dll_def.methods.put(a, "current", .{ .name = "current", .arity = 0 });
    try dll_def.methods.put(a, "key", .{ .name = "key", .arity = 0 });
    try dll_def.methods.put(a, "next", .{ .name = "next", .arity = 0 });
    try dll_def.methods.put(a, "prev", .{ .name = "prev", .arity = 0 });
    try dll_def.methods.put(a, "valid", .{ .name = "valid", .arity = 0 });
    try dll_def.methods.put(a, "offsetGet", .{ .name = "offsetGet", .arity = 1 });
    try dll_def.methods.put(a, "offsetSet", .{ .name = "offsetSet", .arity = 2 });
    try dll_def.methods.put(a, "offsetExists", .{ .name = "offsetExists", .arity = 1 });
    try dll_def.methods.put(a, "offsetUnset", .{ .name = "offsetUnset", .arity = 1 });
    try dll_def.methods.put(a, "add", .{ .name = "add", .arity = 2 });
    try dll_def.methods.put(a, "toArray", .{ .name = "toArray", .arity = 0 });
    try dll_def.constants.put(a, "IT_MODE_LIFO", .{ .int = DLL_IT_MODE_LIFO });
    try dll_def.constants.put(a, "IT_MODE_FIFO", .{ .int = DLL_IT_MODE_FIFO });
    try dll_def.constants.put(a, "IT_MODE_DELETE", .{ .int = DLL_IT_MODE_DELETE });
    try dll_def.constants.put(a, "IT_MODE_KEEP", .{ .int = DLL_IT_MODE_KEEP });
    try dll_def.methods.put(a, "__serialize", .{ .name = "__serialize", .arity = 0 });
    try dll_def.methods.put(a, "__unserialize", .{ .name = "__unserialize", .arity = 1 });
    try vm.classes.put(a, "SplDoublyLinkedList", dll_def);

    try vm.native_fns.put(a, "SplDoublyLinkedList::__construct", dllConstruct);
    try vm.native_fns.put(a, "SplDoublyLinkedList::__serialize", listSerialize);
    try vm.native_fns.put(a, "SplDoublyLinkedList::__unserialize", listUnserialize);
    try vm.native_fns.put(a, "SplDoublyLinkedList::push", dllPush);
    try vm.native_fns.put(a, "SplDoublyLinkedList::pop", dllPop);
    try vm.native_fns.put(a, "SplDoublyLinkedList::unshift", dllUnshift);
    try vm.native_fns.put(a, "SplDoublyLinkedList::shift", dllShift);
    try vm.native_fns.put(a, "SplDoublyLinkedList::top", dllTop);
    try vm.native_fns.put(a, "SplDoublyLinkedList::bottom", dllBottom);
    try vm.native_fns.put(a, "SplDoublyLinkedList::count", dllCount);
    try vm.native_fns.put(a, "SplDoublyLinkedList::isEmpty", dllIsEmpty);
    try vm.native_fns.put(a, "SplDoublyLinkedList::setIteratorMode", dllSetIteratorMode);
    try vm.native_fns.put(a, "SplDoublyLinkedList::getIteratorMode", dllGetIteratorMode);
    try vm.native_fns.put(a, "SplDoublyLinkedList::rewind", dllRewind);
    try vm.native_fns.put(a, "SplDoublyLinkedList::current", dllCurrent);
    try vm.native_fns.put(a, "SplDoublyLinkedList::key", dllKey);
    try vm.native_fns.put(a, "SplDoublyLinkedList::next", dllNext);
    try vm.native_fns.put(a, "SplDoublyLinkedList::prev", dllPrev);
    try vm.native_fns.put(a, "SplDoublyLinkedList::valid", dllValid);
    try vm.native_fns.put(a, "SplDoublyLinkedList::offsetGet", dllOffsetGet);
    try vm.native_fns.put(a, "SplDoublyLinkedList::offsetSet", dllOffsetSet);
    try vm.native_fns.put(a, "SplDoublyLinkedList::offsetExists", dllOffsetExists);
    try vm.native_fns.put(a, "SplDoublyLinkedList::offsetUnset", dllOffsetUnset);
    try vm.native_fns.put(a, "SplDoublyLinkedList::add", dllAdd);
    try vm.native_fns.put(a, "SplDoublyLinkedList::toArray", dllToArray);

    // SplObjectStorage
    var sos_def = ClassDef{ .name = "SplObjectStorage", .native_properties = objectStorageProperties };
    try sos_def.interfaces.append(a, "Countable");
    try sos_def.interfaces.append(a, "SeekableIterator");
    try sos_def.interfaces.append(a, "Traversable");
    try sos_def.interfaces.append(a, "ArrayAccess");
    try sos_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 0 });
    try sos_def.methods.put(a, "attach", .{ .name = "attach", .arity = 2 });
    try sos_def.methods.put(a, "detach", .{ .name = "detach", .arity = 1 });
    try sos_def.methods.put(a, "contains", .{ .name = "contains", .arity = 1 });
    try sos_def.methods.put(a, "count", .{ .name = "count", .arity = 0 });
    try sos_def.methods.put(a, "getInfo", .{ .name = "getInfo", .arity = 0 });
    try sos_def.methods.put(a, "setInfo", .{ .name = "setInfo", .arity = 1 });
    try sos_def.methods.put(a, "getHash", .{ .name = "getHash", .arity = 1 });
    try sos_def.methods.put(a, "rewind", .{ .name = "rewind", .arity = 0 });
    try sos_def.methods.put(a, "current", .{ .name = "current", .arity = 0 });
    try sos_def.methods.put(a, "key", .{ .name = "key", .arity = 0 });
    try sos_def.methods.put(a, "next", .{ .name = "next", .arity = 0 });
    try sos_def.methods.put(a, "valid", .{ .name = "valid", .arity = 0 });
    try sos_def.methods.put(a, "removeAll", .{ .name = "removeAll", .arity = 1 });
    try sos_def.methods.put(a, "removeAllExcept", .{ .name = "removeAllExcept", .arity = 1 });
    try sos_def.methods.put(a, "addAll", .{ .name = "addAll", .arity = 1 });
    try sos_def.methods.put(a, "offsetGet", .{ .name = "offsetGet", .arity = 1 });
    try sos_def.methods.put(a, "offsetSet", .{ .name = "offsetSet", .arity = 2 });
    try sos_def.methods.put(a, "offsetExists", .{ .name = "offsetExists", .arity = 1 });
    try sos_def.methods.put(a, "offsetUnset", .{ .name = "offsetUnset", .arity = 1 });
    try sos_def.methods.put(a, "__serialize", .{ .name = "__serialize", .arity = 0 });
    try sos_def.methods.put(a, "__unserialize", .{ .name = "__unserialize", .arity = 1 });
    try vm.classes.put(a, "SplObjectStorage", sos_def);

    try vm.native_fns.put(a, "SplObjectStorage::__construct", sosConstruct);
    try vm.native_fns.put(a, "SplObjectStorage::__serialize", objectStorageSerialize);
    try vm.native_fns.put(a, "SplObjectStorage::__unserialize", objectStorageUnserialize);
    try vm.native_fns.put(a, "SplObjectStorage::attach", sosAttach);
    try vm.native_fns.put(a, "SplObjectStorage::detach", sosDetach);
    try vm.native_fns.put(a, "SplObjectStorage::contains", sosContains);
    try vm.native_fns.put(a, "SplObjectStorage::count", sosCount);
    try vm.native_fns.put(a, "SplObjectStorage::getInfo", sosGetInfoMethod);
    try vm.native_fns.put(a, "SplObjectStorage::setInfo", sosSetInfoMethod);
    try vm.native_fns.put(a, "SplObjectStorage::getHash", sosGetHash);
    try vm.native_fns.put(a, "SplObjectStorage::rewind", sosRewind);
    try vm.native_fns.put(a, "SplObjectStorage::current", sosCurrent);
    try vm.native_fns.put(a, "SplObjectStorage::key", sosKey);
    try vm.native_fns.put(a, "SplObjectStorage::next", sosNext);
    try vm.native_fns.put(a, "SplObjectStorage::valid", sosValid);
    try vm.native_fns.put(a, "SplObjectStorage::removeAll", sosRemoveAll);
    try vm.native_fns.put(a, "SplObjectStorage::removeAllExcept", sosRemoveAllExcept);
    try vm.native_fns.put(a, "SplObjectStorage::addAll", sosAddAll);
    try vm.native_fns.put(a, "SplObjectStorage::offsetGet", sosOffsetGet);
    try vm.native_fns.put(a, "SplObjectStorage::offsetSet", sosOffsetSet);
    try vm.native_fns.put(a, "SplObjectStorage::offsetExists", sosOffsetExists);
    try vm.native_fns.put(a, "SplObjectStorage::offsetUnset", sosOffsetUnset);

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
    return NativeResult.share(info_v.array.get(.{ .int = sosObjKey(target) }));
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
    try ctx.vm.setPendingException("Error", "Cannot directly construct WeakReference, use WeakReference::create() instead");
    return error.RuntimeError;
}

// =========================================================
// WeakMap
// =========================================================

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

// the debug view of SplDoublyLinkedList, SplQueue and SplStack: the
// iteration flags and the list
fn listProperties(ctx: *NativeContext, obj: *PhpObject, purpose: object_properties.Purpose) RuntimeError!?*PhpArray {
    if (purpose != .debug) return null;
    const table = try object_properties.ownTable(ctx.vm, obj);
    const mode = obj.get("__it_mode");
    try object_properties.setMangled(ctx.vm, table, "flags", .private, "SplDoublyLinkedList", if (mode == .int) mode else .{ .int = 0 });
    try object_properties.setMangled(ctx.vm, table, "dllist", .private, "SplDoublyLinkedList", try dataOrEmpty(ctx, obj));
    return table;
}

// the debug view of a heap: its flags, whether it is corrupted, and the heap
// array in heap order
fn heapProperties(ctx: *NativeContext, obj: *PhpObject, purpose: object_properties.Purpose) RuntimeError!?*PhpArray {
    if (purpose != .debug) return null;
    const table = try object_properties.ownTable(ctx.vm, obj);
    try object_properties.setMangled(ctx.vm, table, "flags", .private, "SplHeap", .{ .int = 0 });
    try object_properties.setMangled(ctx.vm, table, "isCorrupted", .private, "SplHeap", .{ .bool = obj.get("__corrupted") == .bool and obj.get("__corrupted").bool });
    try object_properties.setMangled(ctx.vm, table, "heap", .private, "SplHeap", try dataOrEmpty(ctx, obj));
    return table;
}

// a priority queue's debug view shows each element as data and priority
fn priorityQueueProperties(ctx: *NativeContext, obj: *PhpObject, purpose: object_properties.Purpose) RuntimeError!?*PhpArray {
    if (purpose != .debug) return null;
    const table = try object_properties.ownTable(ctx.vm, obj);
    const flags = obj.get("__flags");
    try object_properties.setMangled(ctx.vm, table, "flags", .private, "SplPriorityQueue", if (flags == .int) flags else .{ .int = EXTR_DATA });
    try object_properties.setMangled(ctx.vm, table, "isCorrupted", .private, "SplPriorityQueue", .{ .bool = obj.get("__corrupted") == .bool and obj.get("__corrupted").bool });
    const heap = try ctx.vm.allocArray();
    if (getData(obj)) |arr| for (arr.entries.items) |entry| {
        if (entry.value != .array) continue;
        const pair = try ctx.vm.allocArray();
        try pair.set(ctx.allocator, .{ .string = Value.String.borrowed("data") }, entry.value.array.get(.{ .int = 0 }));
        try pair.set(ctx.allocator, .{ .string = Value.String.borrowed("priority") }, entry.value.array.get(.{ .int = 1 }));
        try heap.append(ctx.allocator, .{ .array = pair });
    };
    try object_properties.setMangled(ctx.vm, table, "heap", .private, "SplPriorityQueue", .{ .array = heap });
    return table;
}

// SplFixedArray lists its elements, then its own properties, for every
// purpose (json_encode goes through jsonSerialize)
fn fixedArrayProperties(ctx: *NativeContext, obj: *PhpObject, purpose: object_properties.Purpose) RuntimeError!?*PhpArray {
    if (purpose == .serialize) return null;
    const table = try ctx.vm.allocArray();
    if (getData(obj)) |arr| for (arr.entries.items) |entry| try table.append(ctx.allocator, entry.value);
    const own = try object_properties.ownTable(ctx.vm, obj);
    for (own.entries.items) |entry| try table.set(ctx.allocator, entry.key, entry.value);
    return table;
}

// the debug view of SplObjectStorage: each object with its data
fn objectStorageProperties(ctx: *NativeContext, obj: *PhpObject, purpose: object_properties.Purpose) RuntimeError!?*PhpArray {
    if (purpose != .debug) return null;
    const table = try object_properties.ownTable(ctx.vm, obj);
    const storage = try ctx.vm.allocArray();
    if (sosGetObjs(obj)) |objs| {
        const info = sosGetInfo(obj);
        for (objs.entries.items) |entry| {
            const pair = try ctx.vm.allocArray();
            try pair.set(ctx.allocator, .{ .string = Value.String.borrowed("obj") }, entry.value);
            try pair.set(ctx.allocator, .{ .string = Value.String.borrowed("inf") }, if (info) |i| i.get(entry.key) else .null);
            try storage.append(ctx.allocator, .{ .array = pair });
        }
    }
    try object_properties.setMangled(ctx.vm, table, "storage", .private, "SplObjectStorage", .{ .array = storage });
    return table;
}

fn dataOrEmpty(ctx: *NativeContext, obj: *PhpObject) RuntimeError!Value {
    if (getData(obj)) |arr| return .{ .array = arr };
    return .{ .array = try ctx.vm.allocArray() };
}

// php's serialized forms of the SPL containers, each with the object's own
// properties alongside its contents

// SplDoublyLinkedList, SplQueue, SplStack: [flags, elements, properties]
fn listSerialize(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const out = try ctx.createArray();
    const mode = obj.get("__it_mode");
    try out.append(ctx.allocator, if (mode == .int) mode else .{ .int = 0 });
    const elements = try ctx.vm.allocArray();
    if (getData(obj)) |arr| for (arr.entries.items) |entry| try elements.append(ctx.allocator, entry.value);
    try out.append(ctx.allocator, .{ .array = elements });
    try out.append(ctx.allocator, .{ .array = try object_properties.ownTable(ctx.vm, obj) });
    return NativeResult.borrowed(.{ .array = out });
}

fn listUnserialize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const data = if (args.len > 0 and args[0] == .array) args[0].array else return illTyped(ctx);
    const flags = data.get(.{ .int = 0 });
    const elements = data.get(.{ .int = 1 });
    const members = data.get(.{ .int = 2 });
    if (flags != .int or elements != .array or members != .array) return illTyped(ctx);
    try obj.set(ctx.allocator, "__it_mode", flags);
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    const arr = try ctx.vm.allocArray();
    for (elements.array.entries.items) |entry| try arr.append(ctx.allocator, entry.value);
    try obj.set(ctx.allocator, "__data", .{ .array = arr });
    try loadProperties(ctx, obj, members.array);
    return NativeResult.scalar(.null);
}

// SplObjectStorage: [obj, inf, obj, inf, ..., properties]
fn objectStorageSerialize(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const out = try ctx.createArray();
    const flat = try ctx.vm.allocArray();
    if (sosGetObjs(obj)) |objs| {
        const info = sosGetInfo(obj);
        for (objs.entries.items) |entry| {
            try flat.append(ctx.allocator, entry.value);
            try flat.append(ctx.allocator, if (info) |i| i.get(entry.key) else .null);
        }
    }
    try out.append(ctx.allocator, .{ .array = flat });
    try out.append(ctx.allocator, .{ .array = try object_properties.ownTable(ctx.vm, obj) });
    return NativeResult.borrowed(.{ .array = out });
}

fn objectStorageUnserialize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const data = if (args.len > 0 and args[0] == .array) args[0].array else return illTyped(ctx);
    const flat = data.get(.{ .int = 0 });
    const members = data.get(.{ .int = 1 });
    if (flat != .array or members != .array) return illTyped(ctx);
    if (flat.array.entries.items.len % 2 != 0) return unexpected(ctx, "Odd number of elements");
    _ = try sosConstruct(ctx, &.{});
    const objs = sosGetObjs(obj).?;
    const info = sosGetInfo(obj).?;
    var i: usize = 0;
    while (i < flat.array.entries.items.len) : (i += 2) {
        const target = flat.array.entries.items[i].value;
        if (target != .object) return unexpected(ctx, "Non-object key");
        const key = try sosHashKey(ctx, obj, target.object);
        defer if (key == .string) key.string.release();
        try ctx.vm.arraySetOwned(objs, key, target);
        try ctx.vm.arraySetOwned(info, key, flat.array.entries.items[i + 1].value);
    }
    try loadProperties(ctx, obj, members.array);
    return NativeResult.scalar(.null);
}

// SplFixedArray: its elements, then its own properties by name
fn fixedArraySerialize(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const out = try ctx.createArray();
    if (getData(obj)) |arr| for (arr.entries.items) |entry| try out.append(ctx.allocator, entry.value);
    const own = try object_properties.ownTable(ctx.vm, obj);
    for (own.entries.items) |entry| try out.set(ctx.allocator, entry.key, entry.value);
    return NativeResult.borrowed(.{ .array = out });
}

fn fixedArrayUnserialize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const data = if (args.len > 0 and args[0] == .array) args[0].array else return NativeResult.scalar(.null);
    const arr = try ctx.vm.allocArray();
    for (data.entries.items) |entry| {
        if (entry.key == .string) {
            try obj.set(ctx.allocator, entry.key.string.bytes(), entry.value);
        } else {
            try arr.append(ctx.allocator, entry.value);
        }
    }
    try obj.set(ctx.allocator, "__data", .{ .array = arr });
    try obj.set(ctx.allocator, "__size", .{ .int = @intCast(arr.entries.items.len) });
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    return NativeResult.scalar(.null);
}

// the heaps: [properties, [flags, heap_elements]], the elements in heap
// order; a priority queue's as data and priority
fn heapSerialize(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const pqueue = ctx.vm.isInstanceOf(obj.class_name, "SplPriorityQueue");
    const out = try ctx.createArray();
    try out.append(ctx.allocator, .{ .array = try object_properties.ownTable(ctx.vm, obj) });
    const state = try ctx.vm.allocArray();
    const flags = obj.get("__flags");
    try state.set(ctx.allocator, .{ .string = Value.String.borrowed("flags") }, if (pqueue) (if (flags == .int) flags else Value{ .int = EXTR_DATA }) else .{ .int = 0 });
    const elements = try ctx.vm.allocArray();
    if (getData(obj)) |arr| for (arr.entries.items) |entry| {
        if (pqueue and entry.value == .array) {
            const pair = try ctx.vm.allocArray();
            try pair.set(ctx.allocator, .{ .string = Value.String.borrowed("data") }, entry.value.array.get(.{ .int = 0 }));
            try pair.set(ctx.allocator, .{ .string = Value.String.borrowed("priority") }, entry.value.array.get(.{ .int = 1 }));
            try elements.append(ctx.allocator, .{ .array = pair });
        } else try elements.append(ctx.allocator, entry.value);
    };
    try state.set(ctx.allocator, .{ .string = Value.String.borrowed("heap_elements") }, .{ .array = elements });
    try out.append(ctx.allocator, .{ .array = state });
    return NativeResult.borrowed(.{ .array = out });
}

// the elements go back in through insert, so the heap is rebuilt by its
// own comparison
fn heapUnserialize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const pqueue = ctx.vm.isInstanceOf(obj.class_name, "SplPriorityQueue");
    const data = if (args.len > 0 and args[0] == .array) args[0].array else return invalidHeapData(ctx, obj);
    if (data.entries.items.len != 2) return invalidHeapData(ctx, obj);
    const members = data.get(.{ .int = 0 });
    if (members != .array) return invalidHeapData(ctx, obj);
    loadProperties(ctx, obj, members.array) catch return invalidHeapData(ctx, obj);
    const state = data.get(.{ .int = 1 });
    if (state != .array) return invalidHeapData(ctx, obj);
    const flags = state.array.get(.{ .string = Value.String.borrowed("flags") });
    if (flags != .int) return invalidHeapData(ctx, obj);
    if (pqueue) {
        if (flags.int & 3 == 0) return invalidHeapData(ctx, obj);
        try obj.set(ctx.allocator, "__flags", .{ .int = flags.int & 3 });
    } else if (flags.int != 0) return invalidHeapData(ctx, obj);
    const elements = state.array.get(.{ .string = Value.String.borrowed("heap_elements") });
    if (elements != .array) return invalidHeapData(ctx, obj);
    _ = try ensureData(ctx, obj);
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    for (elements.array.entries.items) |entry| {
        if (pqueue) {
            if (entry.value != .array or entry.value.array.entries.items.len != 2) return invalidHeapData(ctx, obj);
            const data_key: PhpArray.Key = .{ .string = Value.String.borrowed("data") };
            const priority_key: PhpArray.Key = .{ .string = Value.String.borrowed("priority") };
            if (!entry.value.array.contains(data_key) or !entry.value.array.contains(priority_key)) return invalidHeapData(ctx, obj);
            _ = pqInsert(ctx, &.{ entry.value.array.get(data_key), entry.value.array.get(priority_key) }) catch return invalidHeapData(ctx, obj);
        } else {
            _ = heapInsert(ctx, &.{entry.value}) catch return invalidHeapData(ctx, obj);
        }
    }
    return NativeResult.scalar(.null);
}

fn invalidHeapData(ctx: *NativeContext, obj: *PhpObject) RuntimeError!NativeResult {
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

// object_properties_load: serialized properties back onto the object, a
// new dynamic one deprecated as any other; zphp's own state is not among them
pub fn loadProperties(ctx: *NativeContext, obj: *PhpObject, members: *PhpArray) RuntimeError!void {
    for (members.entries.items) |entry| {
        var buf: [24]u8 = undefined;
        const key = tableKey(entry.key, &buf);
        const name = if (key.len > 0 and key[0] == 0) if (std.mem.indexOfScalarPos(u8, key, 1, 0)) |end| key[end + 1 ..] else key else key;
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

// --- SplStack ---

fn stackConstruct(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    _ = try ensureData(ctx, obj);
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    try obj.set(ctx.allocator, "__it_mode", .{ .int = DLL_IT_MODE_LIFO | DLL_IT_MODE_KEEP | 4 });
    return NativeResult.scalar(.null);
}

fn stackPush(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = try ensureData(ctx, obj);
    if (args.len >= 1) try arr.append(ctx.allocator, args[0]);
    return NativeResult.scalar(.null);
}

fn stackPop(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    if (arr.entries.items.len == 0) {
        try ctx.vm.setPendingException("RuntimeException", "Can't peek at an empty datastructure");
        return error.RuntimeError;
    }
    const last = arr.entries.items[arr.entries.items.len - 1].value;
    arr.entries.items.len -= 1;
    return if (last == .string and last.string.owner != null) NativeResult.takeString(last.string) else NativeResult.share(last);
}

fn stackTop(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    if (arr.entries.items.len == 0) {
        try ctx.vm.setPendingException("RuntimeException", "Can't peek at an empty datastructure");
        return error.RuntimeError;
    }
    return NativeResult.share(arr.entries.items[arr.entries.items.len - 1].value);
}

fn stackBottom(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    if (arr.entries.items.len == 0) {
        try ctx.vm.setPendingException("RuntimeException", "Can't peek at an empty datastructure");
        return error.RuntimeError;
    }
    return NativeResult.share(arr.entries.items[0].value);
}

fn stackCount(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const arr = getData(obj) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = arr.length() });
}

fn stackIsEmpty(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = true });
    const arr = getData(obj) orelse return NativeResult.scalar(.{ .bool = true });
    return NativeResult.scalar(.{ .bool = arr.entries.items.len == 0 });
}

fn stackShift(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    if (arr.entries.items.len == 0) {
        try ctx.vm.setPendingException("RuntimeException", "Can't peek at an empty datastructure");
        return error.RuntimeError;
    }
    const first = arr.entries.items[0].value;
    std.mem.copyForwards(PhpArray.Entry, arr.entries.items[0 .. arr.entries.items.len - 1], arr.entries.items[1..arr.entries.items.len]);
    arr.entries.items.len -= 1;
    return if (first == .string and first.string.owner != null) NativeResult.takeString(first.string) else NativeResult.share(first);
}

fn stackUnshift(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = try ensureData(ctx, obj);
    if (args.len == 0) return NativeResult.scalar(.null);
    try arr.entries.insert(ctx.allocator, 0, .{ .key = .{ .int = 0 }, .value = args[0] });
    arr.noteIntKey(0);
    VM.retainValue(args[0]);
    return NativeResult.scalar(.null);
}

// iterator: SplStack iterates in LIFO order (top to bottom)
fn stackRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse {
        try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
        return NativeResult.scalar(.null);
    };
    // cursor starts at end (top of stack)
    try obj.set(ctx.allocator, "__cursor", .{ .int = @as(i64, @intCast(arr.entries.items.len)) - 1 });
    return NativeResult.scalar(.null);
}

fn stackCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    const cursor = Value.toInt(obj.get("__cursor"));
    if (cursor < 0 or cursor >= arr.length()) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.share(arr.entries.items[@intCast(cursor)].value);
}

fn stackKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    const cursor = Value.toInt(obj.get("__cursor"));
    const len = arr.length();
    if (cursor < 0 or cursor >= len) return NativeResult.scalar(.null);
    // key is the underlying array index (the cursor itself). PHP's LIFO
    // iteration starts with the top element's original push position (len-1)
    // and counts down to 0 as the cursor decreases
    return NativeResult.scalar(.{ .int = cursor });
}

fn stackNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const cursor = Value.toInt(obj.get("__cursor"));
    try obj.set(ctx.allocator, "__cursor", .{ .int = cursor - 1 });
    return NativeResult.scalar(.null);
}

fn stackValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const arr = getData(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const cursor = Value.toInt(obj.get("__cursor"));
    return NativeResult.scalar(.{ .bool = cursor >= 0 and cursor < arr.length() });
}

fn stackToArray(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse {
        const empty = try ctx.createArray();
        return NativeResult.borrowed(.{ .array = empty });
    };
    // return a copy in LIFO order
    const copy = try ctx.vm.allocArray();
    var i: usize = arr.entries.items.len;
    var key: i64 = 0;
    while (i > 0) {
        i -= 1;
        try copy.set(ctx.allocator, .{ .int = key }, arr.entries.items[i].value);
        key += 1;
    }
    return NativeResult.borrowed(.{ .array = copy });
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
        const uninitialized = value == .null and declared.type_str.len > 0 and vm.typedPropForbidsNull(declared.type_str);
        return .{ .name = name, .value = value, .slot = true, .visibility = declared.visibility, .declaring = declared.defining_class, .hole = uninitialized or o.isUnset(name) };
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

fn splRead(ctx: *NativeContext, obj: *PhpObject, offset: Value) RuntimeError!NativeResult {
    const key = offset.toArrayKey();
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
    switch (try splStorage(ctx, obj)) {
        .array => |s| {
            const arr = try writableArray(ctx, s.holder, s.arr);
            if (offset == .null) return arr.append(ctx.allocator, value);
            detachSplReference(ctx, arr, offset.toArrayKey());
            try arr.set(ctx.allocator, offset.toArrayKey(), value);
        },
        .object => |o| {
            var buf: [24]u8 = undefined;
            if (offset == .null) return tableWrite(ctx, o, tableKey(.{ .int = nextTableIndex(ctx.vm, o) }, &buf), value);
            try tableWrite(ctx, o, tableKey(offset.toArrayKey(), &buf), value);
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
    const key = offset.toArrayKey();
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
    const key = offset.toArrayKey();
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
    const key = offset.toArrayKey();
    switch (try splStorage(ctx, obj)) {
        .array => |s| if (s.arr.getPtr(key)) |entry| return if (entry.ref) |ref| ref.* else entry.value,
        .object => |o| {
            var buf: [24]u8 = undefined;
            if (tableFind(ctx.vm, o, tableKey(key, &buf), false)) |prop| return prop.value;
        },
    }
    return .null;
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
    return @import("serialize.zig").unserializeSplArray(ctx, obj, args[0].string.bytes());
}

fn aoConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len >= 3 and args[2] == .string) try obj.set(ctx.allocator, "__iter_class", args[2]);
    const flags: i64 = if (args.len >= 2) Value.toInt(args[1]) else 0;
    if (args.len >= 1) {
        try requireStorageArg(ctx, obj, "__construct", args[0]);
        try splSetStorage(ctx, obj, args[0], if (args.len == 1) otherFlags(ctx.vm, args[0]) else flags, "__construct");
    } else {
        _ = try ensureData(ctx, obj);
        try obj.set(ctx.allocator, "__flags", .{ .int = flags });
        try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    }
    return NativeResult.scalar(.null);
}

fn aiConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const flags: i64 = if (args.len >= 2) Value.toInt(args[1]) else 0;
    if (args.len >= 1) {
        try requireStorageArg(ctx, obj, "__construct", args[0]);
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

fn splSort(ctx: *NativeContext, how: SplSort) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
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
    switch (how) {
        .values => |flags| arrays_mod.sortWithFlags(arr, flags, false),
        .keys => |flags| arrays_mod.sortKeysWithFlags(arr, flags, false),
        .user_values => |callback| try arrays_mod.mergeSort(PhpArray.Entry, arr.entries.items, ctx, callback, .value),
        .user_keys => |callback| try arrays_mod.mergeSort(PhpArray.Entry, arr.entries.items, ctx, callback, .key),
        // SORT_NATURAL, with SORT_FLAG_CASE
        .natural => |fold_case| arrays_mod.sortWithFlags(arr, if (fold_case) 6 | 8 else 6, false),
    }
    arr.rebuildStringIndexAssumeCapacity();
}

fn aoKsort(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return splSort(ctx, .{ .keys = if (args.len >= 1) Value.toInt(args[0]) else 0 });
}

fn aoAsort(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return splSort(ctx, .{ .values = if (args.len >= 1) Value.toInt(args[0]) else 0 });
}

fn aoUasort(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1) return NativeResult.scalar(.{ .bool = false });
    return splSort(ctx, .{ .user_values = args[0] });
}

fn aoUksort(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1) return NativeResult.scalar(.{ .bool = false });
    return splSort(ctx, .{ .user_keys = args[0] });
}

fn aoNatsort(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return splSort(ctx, .{ .natural = false });
}

fn aoNatcasesort(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return splSort(ctx, .{ .natural = true });
}

fn aoExchangeArray(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 1) return NativeResult.scalar(.{ .bool = false });
    try requireStorageArg(ctx, obj, "exchangeArray", args[0]);
    const old = try splTableCopy(ctx, obj);
    errdefer ctx.vm.releaseValue(.{ .array = old });
    // the new storage's flags join the ones the object has
    try splSetStorage(ctx, obj, args[0], splFlags(obj) | otherFlags(ctx.vm, args[0]), "exchangeArray");
    return NativeResult.borrowed(.{ .array = old });
}

fn aoSetIteratorClass(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len >= 1 and args[0] == .string) {
        try obj.set(ctx.allocator, "__iter_class", .{ .string = args[0].string });
    }
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

fn wmOffsetExists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const arr = getData(obj) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    const key = wmObjKey(args[0]) orelse return NativeResult.scalar(.{ .bool = false });
    const k = PhpArray.Key{ .int = key };
    return NativeResult.scalar(.{ .bool = arr.get(k) != .null });
}

fn wmOffsetGet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    if (args.len == 0) return NativeResult.scalar(.null);
    const key = wmObjKey(args[0]) orelse return NativeResult.scalar(.null);
    return NativeResult.share(arr.get(.{ .int = key }));
}

fn wmOffsetSet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = try ensureData(ctx, obj);
    if (args.len < 2) return NativeResult.scalar(.null);
    if (args[0] != .object) {
        try ctx.vm.setPendingException("TypeError", "WeakMap key must be an object");
        return error.RuntimeError;
    }
    const key = wmObjKey(args[0]) orelse return NativeResult.scalar(.null);
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
    if (args.len == 0) return NativeResult.scalar(.null);
    const key = wmObjKey(args[0]) orelse return NativeResult.scalar(.null);
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

// --- SplPriorityQueue ---
// stores pairs as [value, priority] in __data, sorted by priority descending

const EXTR_DATA: i64 = 1;
const EXTR_PRIORITY: i64 = 2;
const EXTR_BOTH: i64 = 3;

fn pqConstruct(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    _ = try ensureData(ctx, obj);
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    try obj.set(ctx.allocator, "__flags", .{ .int = EXTR_DATA });
    return NativeResult.scalar(.null);
}

// SplPriorityQueue stores pairs as a binary max-heap. element at index i has
// parent (i-1)/2 and children 2i+1, 2i+2. matching PHP's heap means we get the
// same extraction order for equal-priority items as PHP does
fn pqEntryPriority(entry: PhpArray.Entry) Value {
    if (entry.value != .array) return .null;
    return entry.value.array.get(.{ .int = 1 });
}

// dispatches to a subclass-defined compare() when present so user subclasses
// (e.g. inverting to a min-heap by returning $b <=> $a) actually take effect.
// the base SplPriorityQueue has no native compare method so this returns null
// for the unsubclassed case and we fall back to Value.compare
fn pqUserCompare(ctx: *NativeContext, obj: *PhpObject, a: Value, b: Value) RuntimeError!?i64 {
    if (!ctx.vm.hasMethod(obj.class_name, "compare")) return null;
    const r = try ctx.vm.callMethod(obj, "compare", &.{ a, b });
    return Value.toInt(r);
}

fn pqCompareEntries(ctx: *NativeContext, obj: *PhpObject, lhs: PhpArray.Entry, rhs: PhpArray.Entry) RuntimeError!i64 {
    const pa = pqEntryPriority(lhs);
    const pb = pqEntryPriority(rhs);
    if (try pqUserCompare(ctx, obj, pa, pb)) |c| return c;
    return Value.compare(pa, pb);
}

fn pqSiftUp(ctx: *NativeContext, obj: *PhpObject, arr: *PhpArray, start: usize) RuntimeError!void {
    var i = start;
    while (i > 0) {
        const parent = (i - 1) / 2;
        const c = try pqCompareEntries(ctx, obj, arr.entries.items[i], arr.entries.items[parent]);
        if (c <= 0) break;
        const tmp = arr.entries.items[i];
        arr.entries.items[i] = arr.entries.items[parent];
        arr.entries.items[parent] = tmp;
        i = parent;
    }
}

fn pqSiftDown(ctx: *NativeContext, obj: *PhpObject, arr: *PhpArray, start: usize) RuntimeError!void {
    var i = start;
    const n = arr.entries.items.len;
    while (true) {
        const l = 2 * i + 1;
        const r = 2 * i + 2;
        var best = i;
        if (l < n) {
            const c = try pqCompareEntries(ctx, obj, arr.entries.items[l], arr.entries.items[best]);
            if (c > 0) best = l;
        }
        if (r < n) {
            const c = try pqCompareEntries(ctx, obj, arr.entries.items[r], arr.entries.items[best]);
            if (c > 0) best = r;
        }
        if (best == i) break;
        const tmp = arr.entries.items[i];
        arr.entries.items[i] = arr.entries.items[best];
        arr.entries.items[best] = tmp;
        i = best;
    }
}

fn pqInsert(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = try ensureData(ctx, obj);
    if (args.len < 2) return NativeResult.scalar(.null);
    const pair = try ctx.vm.allocArray();
    try pair.set(ctx.allocator, .{ .int = 0 }, args[0]);
    try pair.set(ctx.allocator, .{ .int = 1 }, args[1]);

    const new_idx = arr.entries.items.len;
    try arr.entries.append(ctx.allocator, .{ .key = .{ .int = @intCast(new_idx) }, .value = .{ .array = pair } });
    arr.noteIntKey(@intCast(new_idx));
    try pqSiftUp(ctx, obj, arr, new_idx);
    return NativeResult.scalar(.null);
}

fn pqExtractValue(ctx: *NativeContext, obj: *PhpObject) RuntimeError!NativeResult {
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    if (arr.entries.items.len == 0) {
        try ctx.vm.setPendingException("RuntimeException", "Can't peek at an empty datastructure");
        return error.RuntimeError;
    }
    const top = arr.entries.items[0].value;
    const last = arr.entries.items[arr.entries.items.len - 1];
    arr.entries.items.len -= 1;
    if (arr.entries.items.len > 0) {
        arr.entries.items[0] = last;
        try pqSiftDown(ctx, obj, arr, 0);
    }
    return pqFormatEntry(ctx, obj, top);
}

fn pqFormatEntry(ctx: *NativeContext, obj: *PhpObject, entry: Value) RuntimeError!NativeResult {
    const flags = Value.toInt(obj.get("__flags"));
    if (entry != .array) return NativeResult.share(entry);
    const pair = entry.array;
    if (flags == EXTR_PRIORITY) return NativeResult.share(pair.get(.{ .int = 1 }));
    if (flags == EXTR_BOTH) {
        const result = try ctx.createArray();
        try result.set(ctx.allocator, .{ .string = Value.String.borrowed("data") }, pair.get(.{ .int = 0 }));
        try result.set(ctx.allocator, .{ .string = Value.String.borrowed("priority") }, pair.get(.{ .int = 1 }));
        return NativeResult.borrowed(.{ .array = result });
    }
    return NativeResult.share(pair.get(.{ .int = 0 }));
}

fn pqExtract(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    return pqExtractValue(ctx, obj);
}

fn pqTop(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    if (arr.entries.items.len == 0) {
        try ctx.vm.setPendingException("RuntimeException", "Can't peek at an empty datastructure");
        return error.RuntimeError;
    }
    return pqFormatEntry(ctx, obj, arr.entries.items[0].value);
}

fn pqCount(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const arr = getData(obj) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = @intCast(arr.entries.items.len) });
}

fn pqIsEmpty(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = true });
    const arr = getData(obj) orelse return NativeResult.scalar(.{ .bool = true });
    return NativeResult.scalar(.{ .bool = arr.entries.items.len == 0 });
}

fn pqSetExtractFlags(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len >= 1) try obj.set(ctx.allocator, "__flags", .{ .int = Value.toInt(args[0]) & FLAGS_MASK });
    return NativeResult.scalar(.null);
}

// pq iteration is destructive: current = top, next = extract, key = remaining-1
fn pqCurrent(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return pqTop(ctx, args);
}

fn pqKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    if (arr.entries.items.len == 0) {
        try ctx.vm.setPendingException("RuntimeException", "Can't peek at an empty datastructure");
        return error.RuntimeError;
    }
    return NativeResult.scalar(.{ .int = @intCast(arr.entries.items.len - 1) });
}

fn pqNext(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const discarded = try pqExtract(ctx, args);
    if (discarded.value == .string) discarded.value.string.release();
    return NativeResult.scalar(.null);
}

fn pqRewind(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.null);
}

fn pqValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const arr = getData(obj) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = arr.entries.items.len > 0 });
}

// --- SplHeap / SplMinHeap / SplMaxHeap ---
// php's spl_ptr_heap: a binary heap in __data, sifted up on insert and down
// on extract with php's comparison order, so ties and compare() side effects
// come out as they do in php. an exception from compare() finishes the
// operation with the remaining comparisons as 0 and marks the heap corrupted

const HeapOrder = enum { max, min };

const HeapOp = struct {
    ctx: *NativeContext,
    obj: *PhpObject,
    order: HeapOrder,
    user_compare: bool,
    failed: ?RuntimeError = null,

    fn begin(ctx: *NativeContext, obj: *PhpObject) HeapOp {
        const order: HeapOrder = if (ctx.vm.isInstanceOf(obj.class_name, "SplMinHeap")) .min else .max;
        const resolved = ctx.vm.resolveMethod(obj.class_name, "compare") catch "";
        return .{ .ctx = ctx, .obj = obj, .order = order, .user_compare = ctx.vm.functions.contains(resolved) };
    }

    // positive when a belongs above b
    fn cmp(self: *HeapOp, a: Value, b: Value) i64 {
        if (self.failed != null) return 0;
        const raw: i64 = if (self.user_compare) blk: {
            const r = self.ctx.vm.callMethod(self.obj, "compare", &.{ a, b }) catch |err| {
                self.failed = err;
                return 0;
            };
            break :blk Value.toInt(r);
        } else switch (self.order) {
            .max => Value.compare(a, b),
            .min => Value.compare(b, a),
        };
        return std.math.sign(raw);
    }

    fn finish(self: *HeapOp) RuntimeError!void {
        const err = self.failed orelse return;
        try self.obj.set(self.ctx.allocator, "__corrupted", .{ .bool = true });
        return err;
    }
};

fn heapItems(arr: *PhpArray) []PhpArray.Entry {
    return arr.entries.items;
}

fn heapRejectCorrupted(ctx: *NativeContext, obj: *PhpObject) RuntimeError!void {
    if (obj.get("__corrupted") != .bool or !obj.get("__corrupted").bool) return;
    try ctx.vm.setPendingException("RuntimeException", "Heap is corrupted, heap properties are no longer ensured.");
    return error.RuntimeError;
}

fn heapConstruct(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    _ = try ensureData(ctx, obj);
    return NativeResult.scalar(.null);
}

fn heapInsert(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    try heapRejectCorrupted(ctx, obj);
    const arr = try ensureData(ctx, obj);
    if (args.len == 0) return NativeResult.scalar(.null);
    const elem = args[0];
    var op = HeapOp.begin(ctx, obj);
    try arr.append(ctx.allocator, elem);
    const items = heapItems(arr);
    var i = items.len - 1;
    while (i > 0 and op.cmp(items[(i - 1) / 2].value, elem) < 0) : (i = (i - 1) / 2) {
        items[i].value = items[(i - 1) / 2].value;
    }
    items[i].value = elem;
    try op.finish();
    return NativeResult.scalar(.{ .bool = true });
}

// php's spl_ptr_heap_delete_top; the removed root is returned owned
fn heapDeleteTop(op: *HeapOp, arr: *PhpArray) ?Value {
    const items = heapItems(arr);
    const count = items.len;
    if (count == 0) return null;
    const top = items[0].value;
    const bottom = items[count - 1].value;
    const limit = (count - 1) / 2;
    var i: usize = 0;
    while (i < limit) {
        var j = i * 2 + 1;
        if (j != count and op.cmp(items[j + 1].value, items[j].value) > 0) j += 1;
        if (op.cmp(bottom, items[j].value) < 0) {
            items[i].value = items[j].value;
        } else break;
        i = j;
    }
    items[i].value = bottom;
    arr.entries.items.len -= 1;
    return top;
}

fn heapExtract(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    try heapRejectCorrupted(ctx, obj);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    var op = HeapOp.begin(ctx, obj);
    const top = heapDeleteTop(&op, arr) orelse {
        try ctx.vm.setPendingException("RuntimeException", "Can't extract from an empty heap");
        return error.RuntimeError;
    };
    op.finish() catch |err| {
        ctx.vm.releaseValue(top);
        return err;
    };
    return if (top == .string and top.string.owner != null) NativeResult.takeString(top.string) else NativeResult.share(top);
}

fn heapTop(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    try heapRejectCorrupted(ctx, obj);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    if (arr.entries.items.len == 0) {
        try ctx.vm.setPendingException("RuntimeException", "Can't peek at an empty heap");
        return error.RuntimeError;
    }
    return NativeResult.share(arr.entries.items[0].value);
}

fn heapCount(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const arr = getData(obj) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = @intCast(arr.entries.items.len) });
}

fn heapIsEmpty(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = true });
    const arr = getData(obj) orelse return NativeResult.scalar(.{ .bool = true });
    return NativeResult.scalar(.{ .bool = arr.entries.items.len == 0 });
}

fn heapCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    if (arr.entries.items.len == 0) return NativeResult.scalar(.null);
    return NativeResult.share(arr.entries.items[0].value);
}

fn heapKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = -1 });
    const arr = getData(obj) orelse return NativeResult.scalar(.{ .int = -1 });
    return NativeResult.scalar(.{ .int = @as(i64, @intCast(arr.entries.items.len)) - 1 });
}

fn heapNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    var op = HeapOp.begin(ctx, obj);
    if (heapDeleteTop(&op, arr)) |top| ctx.vm.releaseValue(top);
    try op.finish();
    return NativeResult.scalar(.null);
}

fn heapRewind(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.null);
}

fn heapValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const arr = getData(obj) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = arr.entries.items.len > 0 });
}

fn heapIsCorrupted(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const flag = obj.get("__corrupted");
    return NativeResult.scalar(.{ .bool = flag == .bool and flag.bool });
}

fn heapRecoverFromCorruption(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = true });
    try obj.set(ctx.allocator, "__corrupted", .{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn minHeapCompare(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = std.math.sign(Value.compare(args[1], args[0])) });
}

fn maxHeapCompare(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = std.math.sign(Value.compare(args[0], args[1])) });
}

// --- SplFixedArray ---

fn faConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = try ensureData(ctx, obj);
    const raw_size: i64 = if (args.len >= 1) Value.toInt(args[0]) else 0;
    if (raw_size < 0) {
        try ctx.vm.setPendingException("ValueError", "SplFixedArray::__construct(): Argument #1 ($size) must be greater than or equal to 0");
        return error.RuntimeError;
    }
    const size: usize = @intCast(raw_size);
    var i: usize = 0;
    while (i < size) : (i += 1) {
        try arr.append(ctx.allocator, .null);
    }
    try obj.set(ctx.allocator, "__size", .{ .int = @intCast(size) });
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    return NativeResult.scalar(.null);
}

fn faGetSize(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = Value.toInt(obj.get("__size")) });
}

fn faSetSize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = try ensureData(ctx, obj);
    if (args.len == 0) return NativeResult.scalar(.null);
    const new_size: usize = @intCast(@max(Value.toInt(args[0]), 0));
    const cur_len = arr.entries.items.len;
    if (new_size > cur_len) {
        // php allocates the whole table of 16-byte zvals at once
        if (new_size > std.math.maxInt(usize) / 16) {
            var buf: [128]u8 = undefined;
            return ctx.vm.raiseFatal(std.fmt.bufPrint(&buf, "Possible integer overflow in memory allocation ({d} * 16 + 0)", .{new_size}) catch unreachable);
        }
        try arr.entries.ensureTotalCapacity(ctx.allocator, new_size);
        var i: usize = cur_len;
        while (i < new_size) : (i += 1) {
            try arr.append(ctx.allocator, .null);
        }
    } else {
        for (arr.entries.items[new_size..]) |entry| ctx.vm.releaseValue(entry.value);
        arr.entries.items.len = new_size;
    }
    try obj.set(ctx.allocator, "__size", .{ .int = @intCast(new_size) });
    return NativeResult.scalar(.null);
}

fn faCount(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = Value.toInt(obj.get("__size")) });
}

fn faToArray(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse {
        const empty = try ctx.createArray();
        return NativeResult.borrowed(.{ .array = empty });
    };
    const copy = try ctx.createArray();
    for (arr.entries.items, 0..) |entry, i| {
        try copy.set(ctx.allocator, .{ .int = @intCast(i) }, entry.value);
    }
    return NativeResult.borrowed(.{ .array = copy });
}

fn faFromArray(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) {
        const obj = try ctx.createObject("SplFixedArray");
        const arr = try ensureData(ctx, obj);
        try obj.set(ctx.allocator, "__size", .{ .int = 0 });
        try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
        _ = arr;
        return NativeResult.borrowed(.{ .object = obj });
    }
    const src = args[0].array;
    // PHP default: preserveKeys = true (sparse keys produce padded array)
    const preserve_keys = if (args.len >= 2) args[1].isTruthy() else true;
    var max_idx: i64 = -1;
    for (src.entries.items) |entry| {
        if (preserve_keys) {
            if (entry.key != .int) {
                try ctx.vm.setPendingException("InvalidArgumentException", "array must contain only positive integer keys");
                return error.RuntimeError;
            }
            if (entry.key.int < 0) {
                try ctx.vm.setPendingException("InvalidArgumentException", "array must contain only positive integer keys");
                return error.RuntimeError;
            }
            if (entry.key.int > max_idx) max_idx = entry.key.int;
        }
    }
    const size: usize = if (preserve_keys and max_idx >= 0)
        @intCast(max_idx + 1)
    else
        src.entries.items.len;
    const obj = try ctx.createObject("SplFixedArray");
    const arr = try ensureData(ctx, obj);
    var i: usize = 0;
    while (i < size) : (i += 1) try arr.append(ctx.allocator, .null);
    if (preserve_keys) {
        for (src.entries.items) |entry| {
            try arr.set(ctx.allocator, entry.key, entry.value);
        }
    } else {
        for (src.entries.items, 0..) |entry, idx| {
            try arr.set(ctx.allocator, .{ .int = @intCast(idx) }, entry.value);
        }
    }
    try obj.set(ctx.allocator, "__size", .{ .int = @intCast(size) });
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    return NativeResult.borrowed(.{ .object = obj });
}

fn faRejectNonIntKey(ctx: *NativeContext, key: Value) !bool {
    // PHP throws TypeError when the offset isn't an int and can't be coerced
    // from a numeric string. silent coercion of "x" -> 0 would otherwise let
    // string-key access return the first element
    if (key == .int) return false;
    if (key == .string) {
        const s = key.string.bytes();
        if (s.len > 0) {
            var i: usize = 0;
            if (s[0] == '+' or s[0] == '-') i = 1;
            var saw_digit = false;
            while (i < s.len) : (i += 1) {
                if (s[i] < '0' or s[i] > '9') break;
                saw_digit = true;
            }
            if (saw_digit and i == s.len) return false;
        }
    }
    try ctx.vm.setPendingException("TypeError", "Illegal offset type");
    return true;
}

fn faOffsetGet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    if (args.len == 0) return NativeResult.scalar(.null);
    if (try faRejectNonIntKey(ctx, args[0])) return error.RuntimeError;
    const raw = Value.toInt(args[0]);
    if (raw < 0 or @as(usize, @intCast(raw)) >= arr.entries.items.len) {
        try ctx.vm.setPendingException("OutOfBoundsException", "Index invalid or out of range");
        return error.RuntimeError;
    }
    return NativeResult.share(arr.entries.items[@intCast(raw)].value);
}

fn faOffsetSet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    if (args.len < 2) return NativeResult.scalar(.null);
    if (try faRejectNonIntKey(ctx, args[0])) return error.RuntimeError;
    const raw = Value.toInt(args[0]);
    if (raw < 0 or @as(usize, @intCast(raw)) >= arr.entries.items.len) {
        try ctx.vm.setPendingException("OutOfBoundsException", "Index invalid or out of range");
        return error.RuntimeError;
    }
    const idx: usize = @intCast(raw);
    const old = arr.entries.items[idx].value;
    VM.retainValue(args[1]);
    arr.entries.items[idx].value = args[1];
    ctx.vm.releaseValue(old);
    return NativeResult.scalar(.null);
}

fn faOffsetExists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const arr = getData(obj) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    const idx: usize = @intCast(@max(Value.toInt(args[0]), 0));
    if (idx >= arr.entries.items.len) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = arr.entries.items[idx].value != .null });
}

fn faOffsetUnset(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    if (args.len == 0) return NativeResult.scalar(.null);
    const idx: usize = @intCast(@max(Value.toInt(args[0]), 0));
    if (idx >= arr.entries.items.len) return NativeResult.scalar(.null);
    const old = arr.entries.items[idx].value;
    arr.entries.items[idx].value = .null;
    ctx.vm.releaseValue(old);
    return NativeResult.scalar(.null);
}

fn faCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const cursor: usize = @intCast(@max(Value.toInt(obj.get("__cursor")), 0));
    if (cursor >= arr.entries.items.len) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.share(arr.entries.items[cursor].value);
}

fn faKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    const cursor = Value.toInt(obj.get("__cursor"));
    if (cursor < 0 or cursor >= @as(i64, @intCast(arr.entries.items.len))) return NativeResult.scalar(.null);
    return NativeResult.scalar(.{ .int = cursor });
}

fn faNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const cursor = Value.toInt(obj.get("__cursor"));
    try obj.set(ctx.allocator, "__cursor", .{ .int = cursor + 1 });
    return NativeResult.scalar(.null);
}

fn faRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    return NativeResult.scalar(.null);
}

fn faValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const arr = getData(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const cursor = Value.toInt(obj.get("__cursor"));
    return NativeResult.scalar(.{ .bool = cursor >= 0 and cursor < @as(i64, @intCast(arr.entries.items.len)) });
}

// --- SplQueue ---

fn sqConstruct(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    _ = try ensureData(ctx, obj);
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    try obj.set(ctx.allocator, "__it_mode", .{ .int = DLL_IT_MODE_FIFO | DLL_IT_MODE_KEEP | 4 });
    return NativeResult.scalar(.null);
}

fn sqEnqueue(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = try ensureData(ctx, obj);
    if (args.len >= 1) try arr.append(ctx.allocator, args[0]);
    return NativeResult.scalar(.null);
}

fn sqDequeue(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    if (arr.entries.items.len == 0) {
        try ctx.vm.setPendingException("RuntimeException", "Can't peek at an empty datastructure");
        return error.RuntimeError;
    }
    const first = arr.entries.items[0].value;
    std.mem.copyForwards(PhpArray.Entry, arr.entries.items[0 .. arr.entries.items.len - 1], arr.entries.items[1..arr.entries.items.len]);
    arr.entries.items.len -= 1;
    return if (first == .string and first.string.owner != null) NativeResult.takeString(first.string) else NativeResult.share(first);
}

fn sqBottom(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    if (arr.entries.items.len == 0) {
        try ctx.vm.setPendingException("RuntimeException", "Can't peek at an empty datastructure");
        return error.RuntimeError;
    }
    return NativeResult.share(arr.entries.items[0].value);
}

fn sqTop(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    if (arr.entries.items.len == 0) {
        try ctx.vm.setPendingException("RuntimeException", "Can't peek at an empty datastructure");
        return error.RuntimeError;
    }
    return NativeResult.share(arr.entries.items[arr.entries.items.len - 1].value);
}

fn sqCount(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const arr = getData(obj) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = @intCast(arr.entries.items.len) });
}

fn sqIsEmpty(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = true });
    const arr = getData(obj) orelse return NativeResult.scalar(.{ .bool = true });
    return NativeResult.scalar(.{ .bool = arr.entries.items.len == 0 });
}

fn sqCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const cursor: usize = @intCast(@max(Value.toInt(obj.get("__cursor")), 0));
    if (cursor >= arr.entries.items.len) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.share(arr.entries.items[cursor].value);
}

fn sqKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    const cursor = Value.toInt(obj.get("__cursor"));
    if (cursor < 0 or cursor >= @as(i64, @intCast(arr.entries.items.len))) return NativeResult.scalar(.null);
    return NativeResult.scalar(.{ .int = cursor });
}

fn sqNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const cursor = Value.toInt(obj.get("__cursor"));
    try obj.set(ctx.allocator, "__cursor", .{ .int = cursor + 1 });
    return NativeResult.scalar(.null);
}

fn sqRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    return NativeResult.scalar(.null);
}

fn sqValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const arr = getData(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const cursor = Value.toInt(obj.get("__cursor"));
    return NativeResult.scalar(.{ .bool = cursor >= 0 and cursor < @as(i64, @intCast(arr.entries.items.len)) });
}

// --- SplDoublyLinkedList ---

const DLL_IT_MODE_LIFO: i64 = 2;
const DLL_IT_MODE_FIFO: i64 = 0;
const DLL_IT_MODE_DELETE: i64 = 1;
const DLL_IT_MODE_KEEP: i64 = 0;

fn dllConstruct(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    _ = try ensureData(ctx, obj);
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    try obj.set(ctx.allocator, "__it_mode", .{ .int = DLL_IT_MODE_FIFO | DLL_IT_MODE_KEEP });
    return NativeResult.scalar(.null);
}

fn dllPush(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = try ensureData(ctx, obj);
    if (args.len >= 1) try arr.append(ctx.allocator, args[0]);
    return NativeResult.scalar(.null);
}

fn dllPop(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    if (arr.entries.items.len == 0) {
        try ctx.vm.setPendingException("RuntimeException", "Can't peek at an empty datastructure");
        return error.RuntimeError;
    }
    const last = arr.entries.items[arr.entries.items.len - 1].value;
    arr.entries.items.len -= 1;
    return if (last == .string and last.string.owner != null) NativeResult.takeString(last.string) else NativeResult.share(last);
}

fn dllUnshift(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = try ensureData(ctx, obj);
    if (args.len == 0) return NativeResult.scalar(.null);
    try arr.entries.insert(ctx.allocator, 0, .{ .key = .{ .int = 0 }, .value = args[0] });
    VM.retainValue(args[0]);
    for (arr.entries.items, 0..) |*entry, i| {
        entry.key = .{ .int = @intCast(i) };
    }
    arr.next_int_key = @intCast(arr.entries.items.len);
    arr.has_int_keys = true;
    return NativeResult.scalar(.null);
}

fn dllShift(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    if (arr.entries.items.len == 0) {
        try ctx.vm.setPendingException("RuntimeException", "Can't peek at an empty datastructure");
        return error.RuntimeError;
    }
    const first = arr.entries.items[0].value;
    std.mem.copyForwards(PhpArray.Entry, arr.entries.items[0 .. arr.entries.items.len - 1], arr.entries.items[1..arr.entries.items.len]);
    arr.entries.items.len -= 1;
    return if (first == .string and first.string.owner != null) NativeResult.takeString(first.string) else NativeResult.share(first);
}

fn dllTop(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    if (arr.entries.items.len == 0) {
        try ctx.vm.setPendingException("RuntimeException", "Can't peek at an empty datastructure");
        return error.RuntimeError;
    }
    return NativeResult.share(arr.entries.items[arr.entries.items.len - 1].value);
}

fn dllBottom(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    if (arr.entries.items.len == 0) {
        try ctx.vm.setPendingException("RuntimeException", "Can't peek at an empty datastructure");
        return error.RuntimeError;
    }
    return NativeResult.share(arr.entries.items[0].value);
}

fn dllCount(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const arr = getData(obj) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = arr.length() });
}

fn dllIsEmpty(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = true });
    const arr = getData(obj) orelse return NativeResult.scalar(.{ .bool = true });
    return NativeResult.scalar(.{ .bool = arr.entries.items.len == 0 });
}

fn dllSetIteratorMode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len >= 1 and args[0] == .int) {
        try obj.set(ctx.allocator, "__it_mode", args[0]);
    }
    return NativeResult.scalar(.null);
}

fn dllGetIteratorMode(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.share(obj.get("__it_mode"));
}

fn dllRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const mode = Value.toInt(obj.get("__it_mode"));
    const is_lifo = (mode & DLL_IT_MODE_LIFO) != 0;
    if (is_lifo) {
        const arr = getData(obj) orelse {
            try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
            return NativeResult.scalar(.null);
        };
        try obj.set(ctx.allocator, "__cursor", .{ .int = @as(i64, @intCast(arr.entries.items.len)) - 1 });
    } else {
        try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    }
    return NativeResult.scalar(.null);
}

fn dllCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const arr = getData(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const cursor = Value.toInt(obj.get("__cursor"));
    if (cursor < 0 or cursor >= @as(i64, @intCast(arr.entries.items.len))) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.share(arr.entries.items[@intCast(cursor)].value);
}

fn dllKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.scalar(obj.get("__cursor"));
}

fn dllNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const mode = Value.toInt(obj.get("__it_mode"));
    const is_lifo = (mode & DLL_IT_MODE_LIFO) != 0;
    const is_delete = (mode & DLL_IT_MODE_DELETE) != 0;
    if (is_delete) {
        if (getData(obj)) |arr| {
            if (is_lifo) {
                if (arr.entries.pop()) |removed| {
                    if (removed.key == .string) removed.key.string.release();
                    ctx.vm.releaseValue(removed.value);
                }
                try obj.set(ctx.allocator, "__cursor", .{ .int = @as(i64, @intCast(arr.entries.items.len)) - 1 });
            } else if (arr.entries.items.len > 0) {
                const removed = arr.entries.orderedRemove(0);
                if (removed.key == .string) removed.key.string.release();
                ctx.vm.releaseValue(removed.value);
            }
        }
        return NativeResult.scalar(.null);
    }
    const cursor = Value.toInt(obj.get("__cursor"));
    if (is_lifo) {
        try obj.set(ctx.allocator, "__cursor", .{ .int = cursor - 1 });
    } else {
        try obj.set(ctx.allocator, "__cursor", .{ .int = cursor + 1 });
    }
    return NativeResult.scalar(.null);
}

fn dllPrev(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const mode = Value.toInt(obj.get("__it_mode"));
    const is_lifo = (mode & DLL_IT_MODE_LIFO) != 0;
    const cursor = Value.toInt(obj.get("__cursor"));
    if (is_lifo) {
        try obj.set(ctx.allocator, "__cursor", .{ .int = cursor + 1 });
    } else {
        try obj.set(ctx.allocator, "__cursor", .{ .int = cursor - 1 });
    }
    return NativeResult.scalar(.null);
}

fn dllValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const arr = getData(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const cursor = Value.toInt(obj.get("__cursor"));
    return NativeResult.scalar(.{ .bool = cursor >= 0 and cursor < @as(i64, @intCast(arr.entries.items.len)) });
}

fn stackOffsetGet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    if (args.len == 0) return NativeResult.scalar(.null);
    const n: i64 = @intCast(arr.entries.items.len);
    const idx = Value.toInt(args[0]);
    if (idx < 0 or idx >= n) {
        try ctx.vm.setPendingException("OutOfRangeException", "Offset invalid or out of range");
        return error.RuntimeError;
    }
    return NativeResult.share(arr.entries.items[@intCast(n - 1 - idx)].value);
}

fn stackOffsetSet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = try ensureData(ctx, obj);
    if (args.len < 2) return NativeResult.scalar(.null);
    if (args[0] == .null) {
        try arr.append(ctx.allocator, args[1]);
        return NativeResult.scalar(.null);
    }
    const n: i64 = @intCast(arr.entries.items.len);
    const idx = Value.toInt(args[0]);
    if (idx >= 0 and idx < n) {
        try ctx.vm.arraySetOwned(arr, arr.entries.items[@intCast(n - 1 - idx)].key, args[1]);
    }
    return NativeResult.scalar(.null);
}

fn stackOffsetExists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const arr = getData(obj) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    const idx = Value.toInt(args[0]);
    return NativeResult.scalar(.{ .bool = idx >= 0 and idx < @as(i64, @intCast(arr.entries.items.len)) });
}

fn stackOffsetUnset(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    if (args.len == 0) return NativeResult.scalar(.null);
    const n: i64 = @intCast(arr.entries.items.len);
    const idx = Value.toInt(args[0]);
    if (idx >= 0 and idx < n) {
        const removed = arr.entries.orderedRemove(@intCast(n - 1 - idx));
        if (removed.key == .string) removed.key.string.release();
        ctx.vm.releaseValue(removed.value);
    }
    return NativeResult.scalar(.null);
}

fn dllOffsetGet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    if (args.len == 0) return NativeResult.scalar(.null);
    const idx = Value.toInt(args[0]);
    if (idx < 0 or idx >= @as(i64, @intCast(arr.entries.items.len))) {
        try ctx.vm.setPendingException("OutOfRangeException", "Offset invalid or out of range");
        return error.RuntimeError;
    }
    return NativeResult.share(arr.entries.items[@intCast(idx)].value);
}

fn dllOffsetSet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = try ensureData(ctx, obj);
    if (args.len < 2) return NativeResult.scalar(.null);
    if (args[0] == .null) {
        try arr.append(ctx.allocator, args[1]);
    } else {
        const idx = Value.toInt(args[0]);
        if (idx >= 0 and idx < @as(i64, @intCast(arr.entries.items.len))) {
            try ctx.vm.arraySetOwned(arr, arr.entries.items[@intCast(idx)].key, args[1]);
        }
    }
    return NativeResult.scalar(.null);
}

fn dllOffsetExists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const arr = getData(obj) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    const idx = Value.toInt(args[0]);
    return NativeResult.scalar(.{ .bool = idx >= 0 and idx < @as(i64, @intCast(arr.entries.items.len)) });
}

fn dllOffsetUnset(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse return NativeResult.scalar(.null);
    if (args.len == 0) return NativeResult.scalar(.null);
    const idx = Value.toInt(args[0]);
    if (idx >= 0 and idx < @as(i64, @intCast(arr.entries.items.len))) {
        const removed = arr.entries.orderedRemove(@intCast(idx));
        if (removed.key == .string) removed.key.string.release();
        ctx.vm.releaseValue(removed.value);
    }
    return NativeResult.scalar(.null);
}

fn dllAdd(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = try ensureData(ctx, obj);
    if (args.len < 2) return NativeResult.scalar(.null);
    const idx = Value.toInt(args[0]);
    if (idx < 0) return NativeResult.scalar(.null);
    const uidx: usize = @intCast(idx);
    if (uidx > arr.entries.items.len) return NativeResult.scalar(.null);
    try arr.entries.insert(ctx.allocator, uidx, .{ .key = .{ .int = idx }, .value = args[1] });
    arr.noteIntKey(idx);
    VM.retainValue(args[1]);
    return NativeResult.scalar(.null);
}

fn dllToArray(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = getData(obj) orelse {
        const new_arr = try ctx.createArray();
        return NativeResult.borrowed(.{ .array = new_arr });
    };
    const result = try ctx.createArray();
    for (arr.entries.items, 0..) |entry, i| {
        try result.set(ctx.allocator, .{ .int = @intCast(i) }, entry.value);
    }
    return NativeResult.borrowed(.{ .array = result });
}

// --- SplObjectStorage ---
// stores objects keyed by pointer identity, each with optional associated data

fn sosObjKey(obj: *PhpObject) i64 {
    return @intCast(@intFromPtr(obj));
}

fn sosHashKey(ctx: *NativeContext, sos: *PhpObject, target: *PhpObject) !PhpArray.Key {
    if (!std.mem.eql(u8, sos.class_name, "SplObjectStorage")) {
        const resolved = ctx.vm.resolveMethod(sos.class_name, "getHash") catch null;
        if (resolved) |r| {
            if (!std.mem.eql(u8, r, "SplObjectStorage::getHash")) {
                const result = try ctx.vm.callMethod(sos, "getHash", &.{.{ .object = target }});
                if (result == .string) {
                    return .{ .string = try Value.String.create(ctx.allocator, result.string.bytes()) };
                }
            }
        }
    }
    return .{ .int = sosObjKey(target) };
}

fn sosFindIndexByKey(objs: *PhpArray, key: PhpArray.Key) ?usize {
    for (objs.entries.items, 0..) |entry, i| {
        if (entry.key.eql(key)) return i;
    }
    return null;
}

fn sosFindIndexByObject(objs: *PhpArray, target: *PhpObject) ?usize {
    for (objs.entries.items, 0..) |entry, i| {
        if (entry.value == .object and entry.value.object == target) return i;
    }
    return null;
}

fn sosLookupKey(objs: *PhpArray, key: PhpArray.Key, target: *PhpObject) ?PhpArray.Key {
    if (sosFindIndexByKey(objs, key)) |idx| return objs.entries.items[idx].key;
    if (sosFindIndexByObject(objs, target)) |idx| return objs.entries.items[idx].key;
    return null;
}

fn sosConstruct(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    _ = try ensureData(ctx, obj);
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    // __info stores associated data keyed by object pointer as string
    const info_arr = try ctx.createArray();
    try obj.set(ctx.allocator, "__info", .{ .array = info_arr });
    // __objs stores object references in insertion order for iteration
    const objs_arr = try ctx.createArray();
    try obj.set(ctx.allocator, "__objs", .{ .array = objs_arr });
    return NativeResult.scalar(.null);
}

fn sosGetObjs(obj: *PhpObject) ?*PhpArray {
    const v = obj.get("__objs");
    if (v != .array) return null;
    return v.array;
}

fn sosGetInfo(obj: *PhpObject) ?*PhpArray {
    const v = obj.get("__info");
    if (v != .array) return null;
    return v.array;
}

fn sosFindIndex(ctx: *NativeContext, sos: *PhpObject, objs: *PhpArray, target: *PhpObject) !?usize {
    const key = try sosHashKey(ctx, sos, target);
    defer if (key == .string) key.string.release();
    return sosFindIndexByKey(objs, key);
}

fn sosAttach(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.null);
    const target = args[0].object;
    const data = if (args.len >= 2) args[1] else Value.null;
    const objs = sosGetObjs(obj) orelse return NativeResult.scalar(.null);
    const info = sosGetInfo(obj) orelse return NativeResult.scalar(.null);
    const key = try sosHashKey(ctx, obj, target);
    defer if (key == .string) key.string.release();

    try ctx.vm.arraySetOwned(objs, key, .{ .object = target });
    try ctx.vm.arraySetOwned(info, key, data);
    return NativeResult.scalar(.null);
}

fn sosDetach(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.null);
    const target = args[0].object;
    const objs = sosGetObjs(obj) orelse return NativeResult.scalar(.null);
    const info = sosGetInfo(obj) orelse return NativeResult.scalar(.null);
    const key = try sosHashKey(ctx, obj, target);
    defer if (key == .string) key.string.release();

    const lookup = sosLookupKey(objs, key, target);
    if (lookup) |real_key| {
        const idx = sosFindIndexByKey(objs, real_key).?;
        const removed = objs.entries.orderedRemove(idx);
        defer {
            if (removed.key == .string) removed.key.string.release();
            ctx.vm.releaseValue(removed.value);
        }
        if (real_key == .string) _ = objs.string_index.remove(real_key.string.bytes());
        ctx.vm.arrayRemoveOwned(info, real_key);
        if (real_key == .string) {
            objs.rebuildStringIndexAssumeCapacity();
        }
    }
    return NativeResult.scalar(.null);
}

fn sosContains(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const objs = sosGetObjs(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const key = try sosHashKey(ctx, obj, args[0].object);
    defer if (key == .string) key.string.release();
    return NativeResult.scalar(.{ .bool = sosLookupKey(objs, key, args[0].object) != null });
}

fn sosCount(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const objs = sosGetObjs(obj) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = @intCast(objs.entries.items.len) });
}

fn sosGetInfoMethod(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const objs = sosGetObjs(obj) orelse return NativeResult.scalar(.null);
    const info = sosGetInfo(obj) orelse return NativeResult.scalar(.null);
    const cursor = Value.toInt(obj.get("__cursor"));
    if (cursor < 0 or cursor >= @as(i64, @intCast(objs.entries.items.len))) return NativeResult.scalar(.null);
    return NativeResult.share(info.get(objs.entries.items[@intCast(cursor)].key));
}

fn sosSetInfoMethod(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len == 0) return NativeResult.scalar(.null);
    const objs = sosGetObjs(obj) orelse return NativeResult.scalar(.null);
    const info = sosGetInfo(obj) orelse return NativeResult.scalar(.null);
    const cursor = Value.toInt(obj.get("__cursor"));
    if (cursor < 0 or cursor >= @as(i64, @intCast(objs.entries.items.len))) return NativeResult.scalar(.null);
    try ctx.vm.arraySetOwned(info, objs.entries.items[@intCast(cursor)].key, args[0]);
    return NativeResult.scalar(.null);
}

fn sosGetHash(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.null);
    const ptr: usize = @intFromPtr(args[0].object);
    const hash = try std.fmt.allocPrint(ctx.allocator, "{x:0>32}", .{ptr});
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, hash));
}

fn sosRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    return NativeResult.scalar(.null);
}

fn sosCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const objs = sosGetObjs(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const cursor = Value.toInt(obj.get("__cursor"));
    if (cursor < 0 or cursor >= @as(i64, @intCast(objs.entries.items.len))) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.borrowed(objs.entries.items[@intCast(cursor)].value);
}

fn sosKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.scalar(obj.get("__cursor"));
}

fn sosNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const cursor = Value.toInt(obj.get("__cursor"));
    try obj.set(ctx.allocator, "__cursor", .{ .int = cursor + 1 });
    return NativeResult.scalar(.null);
}

fn sosValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const objs = sosGetObjs(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const cursor = Value.toInt(obj.get("__cursor"));
    return NativeResult.scalar(.{ .bool = cursor >= 0 and cursor < @as(i64, @intCast(objs.entries.items.len)) });
}

fn sosRemoveAll(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.null);
    const other_this = args[0].object;
    const other_objs = sosGetObjs(other_this) orelse return NativeResult.scalar(.null);
    const objs = sosGetObjs(obj) orelse return NativeResult.scalar(.null);
    const info = sosGetInfo(obj) orelse return NativeResult.scalar(.null);

    const snapshot = try ctx.vm.cloneArray(other_objs);
    VM.arrayRetain(snapshot);
    defer ctx.vm.arrayRelease(snapshot);
    for (snapshot.entries.items) |o_entry| {
        if (o_entry.value != .object) continue;
        const key = try sosHashKey(ctx, obj, o_entry.value.object);
        defer if (key == .string) key.string.release();
        if (sosFindIndexByKey(objs, key)) |idx| {
            const removed = objs.entries.orderedRemove(idx);
            defer {
                if (removed.key == .string) removed.key.string.release();
                ctx.vm.releaseValue(removed.value);
            }
            if (key == .string) {
                _ = objs.string_index.remove(key.string.bytes());
                objs.rebuildStringIndexAssumeCapacity();
            }
            ctx.vm.arrayRemoveOwned(info, key);
        }
    }
    return NativeResult.scalar(.null);
}

fn sosRemoveAllExcept(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.null);
    const other_this = args[0].object;
    const other_objs = sosGetObjs(other_this) orelse return NativeResult.scalar(.null);
    const objs = sosGetObjs(obj) orelse return NativeResult.scalar(.null);
    const info = sosGetInfo(obj) orelse return NativeResult.scalar(.null);

    var i: usize = 0;
    while (i < objs.entries.items.len) {
        const entry = objs.entries.items[i];
        if (entry.value != .object) {
            i += 1;
            continue;
        }
        // is this object's hash present in other?
        var found = false;
        for (other_objs.entries.items) |o_entry| {
            if (o_entry.value != .object) continue;
            const other_key = try sosHashKey(ctx, obj, o_entry.value.object);
            defer if (other_key == .string) other_key.string.release();
            if (entry.key.eql(other_key)) {
                found = true;
                break;
            }
        }
        if (!found) {
            const key = entry.key;
            const removed = objs.entries.orderedRemove(i);
            defer {
                if (removed.key == .string) removed.key.string.release();
                ctx.vm.releaseValue(removed.value);
            }
            if (key == .string) {
                _ = objs.string_index.remove(key.string.bytes());
            }
            ctx.vm.arrayRemoveOwned(info, key);
        } else {
            i += 1;
        }
    }
    objs.rebuildStringIndexAssumeCapacity();
    return NativeResult.scalar(.null);
}

fn sosAddAll(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.null);
    const other_this = args[0].object;
    const other_objs = sosGetObjs(other_this) orelse return NativeResult.scalar(.null);
    const other_info = sosGetInfo(other_this) orelse return NativeResult.scalar(.null);
    const objs = sosGetObjs(obj) orelse return NativeResult.scalar(.null);
    const info = sosGetInfo(obj) orelse return NativeResult.scalar(.null);

    for (other_objs.entries.items) |entry| {
        if (entry.value == .object) {
            const target = entry.value.object;
            const self_key = try sosHashKey(ctx, obj, target);
            defer if (self_key == .string) self_key.string.release();
            try ctx.vm.arraySetOwned(objs, self_key, .{ .object = target });
            const data = other_info.get(entry.key);
            try ctx.vm.arraySetOwned(info, self_key, data);
        }
    }
    return NativeResult.scalar(.null);
}

fn sosOffsetGet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len == 0) return NativeResult.scalar(.null);
    if (!try sosRequireObjectKey(ctx, "offsetGet", args[0])) return error.RuntimeError;
    const info = sosGetInfo(obj) orelse {
        try ctx.vm.setPendingException("UnexpectedValueException", "Object not found");
        return error.RuntimeError;
    };
    const objs = sosGetObjs(obj) orelse return NativeResult.scalar(.null);
    const key = try sosHashKey(ctx, obj, args[0].object);
    defer if (key == .string) key.string.release();
    const real_key = sosLookupKey(objs, key, args[0].object) orelse {
        try ctx.vm.setPendingException("UnexpectedValueException", "Object not found");
        return error.RuntimeError;
    };
    return NativeResult.share(info.get(real_key));
}

fn sosOffsetSet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // offsetSet($obj, $data) is equivalent to attach($obj, $data) but the
    // offset* variant uses a TypeError-throwing key check (attach is now
    // deprecated and tolerant of non-objects)
    if (args.len == 0) return NativeResult.scalar(.null);
    if (!try sosRequireObjectKey(ctx, "offsetSet", args[0])) return error.RuntimeError;
    return sosAttach(ctx, args);
}

fn sosOffsetExists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    if (!try sosRequireObjectKey(ctx, "offsetExists", args[0])) return error.RuntimeError;
    return sosContains(ctx, args);
}

fn sosOffsetUnset(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.null);
    if (!try sosRequireObjectKey(ctx, "offsetUnset", args[0])) return error.RuntimeError;
    return sosDetach(ctx, args);
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
