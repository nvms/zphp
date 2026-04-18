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

    // Traversable interface (base for Iterator and IteratorAggregate)
    const traversable = vm_mod.InterfaceDef{ .name = "Traversable" };
    try vm.interfaces.put(a, "Traversable", traversable);

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

    // ArrayIterator
    var ai_def = ClassDef{ .name = "ArrayIterator" };
    try ai_def.interfaces.append(a, "Iterator");
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
    try vm.classes.put(a, "ArrayIterator", ai_def);

    try vm.native_fns.put(a, "ArrayIterator::__construct", aiConstruct);
    try vm.native_fns.put(a, "ArrayIterator::rewind", aiRewind);
    try vm.native_fns.put(a, "ArrayIterator::current", aiCurrent);
    try vm.native_fns.put(a, "ArrayIterator::key", aiKey);
    try vm.native_fns.put(a, "ArrayIterator::next", aiNext);
    try vm.native_fns.put(a, "ArrayIterator::valid", aiValid);
    try vm.native_fns.put(a, "ArrayIterator::count", aiCount);
    try vm.native_fns.put(a, "ArrayIterator::offsetGet", aiOffsetGet);
    try vm.native_fns.put(a, "ArrayIterator::offsetSet", aiOffsetSet);
    try vm.native_fns.put(a, "ArrayIterator::offsetExists", aiOffsetExists);
    try vm.native_fns.put(a, "ArrayIterator::offsetUnset", aiOffsetUnset);
    try vm.native_fns.put(a, "ArrayIterator::getArrayCopy", aiGetArrayCopy);
    try vm.native_fns.put(a, "ArrayIterator::append", aiAppend);
    try vm.native_fns.put(a, "ArrayIterator::getFlags", aiGetFlags);
    try vm.native_fns.put(a, "ArrayIterator::setFlags", aiSetFlags);

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
    var pq_def = ClassDef{ .name = "SplPriorityQueue" };
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
    try pq_def.static_props.put(a, "EXTR_DATA", .{ .int = EXTR_DATA });
    try pq_def.static_props.put(a, "EXTR_PRIORITY", .{ .int = EXTR_PRIORITY });
    try pq_def.static_props.put(a, "EXTR_BOTH", .{ .int = EXTR_BOTH });
    try vm.classes.put(a, "SplPriorityQueue", pq_def);

    try vm.native_fns.put(a, "SplPriorityQueue::__construct", pqConstruct);
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

    // SplMinHeap
    var minh_def = ClassDef{ .name = "SplMinHeap" };
    try minh_def.interfaces.append(a, "Countable");
    try minh_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 0 });
    try minh_def.methods.put(a, "insert", .{ .name = "insert", .arity = 1 });
    try minh_def.methods.put(a, "extract", .{ .name = "extract", .arity = 0 });
    try minh_def.methods.put(a, "top", .{ .name = "top", .arity = 0 });
    try minh_def.methods.put(a, "count", .{ .name = "count", .arity = 0 });
    try minh_def.methods.put(a, "isEmpty", .{ .name = "isEmpty", .arity = 0 });
    try minh_def.methods.put(a, "current", .{ .name = "current", .arity = 0 });
    try minh_def.methods.put(a, "key", .{ .name = "key", .arity = 0 });
    try minh_def.methods.put(a, "next", .{ .name = "next", .arity = 0 });
    try minh_def.methods.put(a, "rewind", .{ .name = "rewind", .arity = 0 });
    try minh_def.methods.put(a, "valid", .{ .name = "valid", .arity = 0 });
    try vm.classes.put(a, "SplMinHeap", minh_def);

    try vm.native_fns.put(a, "SplMinHeap::__construct", heapConstruct);
    try vm.native_fns.put(a, "SplMinHeap::insert", heapInsert);
    try vm.native_fns.put(a, "SplMinHeap::extract", minHeapExtract);
    try vm.native_fns.put(a, "SplMinHeap::top", minHeapTop);
    try vm.native_fns.put(a, "SplMinHeap::count", heapCount);
    try vm.native_fns.put(a, "SplMinHeap::isEmpty", heapIsEmpty);
    try vm.native_fns.put(a, "SplMinHeap::current", minHeapTop);
    try vm.native_fns.put(a, "SplMinHeap::key", heapKey);
    try vm.native_fns.put(a, "SplMinHeap::next", minHeapExtract);
    try vm.native_fns.put(a, "SplMinHeap::rewind", heapRewind);
    try vm.native_fns.put(a, "SplMinHeap::valid", heapValid);

    // SplMaxHeap
    var maxh_def = ClassDef{ .name = "SplMaxHeap" };
    try maxh_def.interfaces.append(a, "Countable");
    try maxh_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 0 });
    try maxh_def.methods.put(a, "insert", .{ .name = "insert", .arity = 1 });
    try maxh_def.methods.put(a, "extract", .{ .name = "extract", .arity = 0 });
    try maxh_def.methods.put(a, "top", .{ .name = "top", .arity = 0 });
    try maxh_def.methods.put(a, "count", .{ .name = "count", .arity = 0 });
    try maxh_def.methods.put(a, "isEmpty", .{ .name = "isEmpty", .arity = 0 });
    try maxh_def.methods.put(a, "current", .{ .name = "current", .arity = 0 });
    try maxh_def.methods.put(a, "key", .{ .name = "key", .arity = 0 });
    try maxh_def.methods.put(a, "next", .{ .name = "next", .arity = 0 });
    try maxh_def.methods.put(a, "rewind", .{ .name = "rewind", .arity = 0 });
    try maxh_def.methods.put(a, "valid", .{ .name = "valid", .arity = 0 });
    try vm.classes.put(a, "SplMaxHeap", maxh_def);

    try vm.native_fns.put(a, "SplMaxHeap::__construct", heapConstruct);
    try vm.native_fns.put(a, "SplMaxHeap::insert", heapInsert);
    try vm.native_fns.put(a, "SplMaxHeap::extract", maxHeapExtract);
    try vm.native_fns.put(a, "SplMaxHeap::top", maxHeapTop);
    try vm.native_fns.put(a, "SplMaxHeap::count", heapCount);
    try vm.native_fns.put(a, "SplMaxHeap::isEmpty", heapIsEmpty);
    try vm.native_fns.put(a, "SplMaxHeap::current", maxHeapTop);
    try vm.native_fns.put(a, "SplMaxHeap::key", heapKey);
    try vm.native_fns.put(a, "SplMaxHeap::next", maxHeapExtract);
    try vm.native_fns.put(a, "SplMaxHeap::rewind", heapRewind);
    try vm.native_fns.put(a, "SplMaxHeap::valid", heapValid);

    // SplFixedArray
    var fa_def = ClassDef{ .name = "SplFixedArray" };
    try fa_def.interfaces.append(a, "Countable");
    try fa_def.interfaces.append(a, "ArrayAccess");
    try fa_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try fa_def.methods.put(a, "getSize", .{ .name = "getSize", .arity = 0 });
    try fa_def.methods.put(a, "setSize", .{ .name = "setSize", .arity = 1 });
    try fa_def.methods.put(a, "count", .{ .name = "count", .arity = 0 });
    try fa_def.methods.put(a, "toArray", .{ .name = "toArray", .arity = 0 });
    try fa_def.methods.put(a, "offsetGet", .{ .name = "offsetGet", .arity = 1 });
    try fa_def.methods.put(a, "offsetSet", .{ .name = "offsetSet", .arity = 2 });
    try fa_def.methods.put(a, "offsetExists", .{ .name = "offsetExists", .arity = 1 });
    try fa_def.methods.put(a, "offsetUnset", .{ .name = "offsetUnset", .arity = 1 });
    try fa_def.methods.put(a, "current", .{ .name = "current", .arity = 0 });
    try fa_def.methods.put(a, "key", .{ .name = "key", .arity = 0 });
    try fa_def.methods.put(a, "next", .{ .name = "next", .arity = 0 });
    try fa_def.methods.put(a, "rewind", .{ .name = "rewind", .arity = 0 });
    try fa_def.methods.put(a, "valid", .{ .name = "valid", .arity = 0 });
    try vm.classes.put(a, "SplFixedArray", fa_def);

    try vm.native_fns.put(a, "SplFixedArray::__construct", faConstruct);
    try vm.native_fns.put(a, "SplFixedArray::getSize", faGetSize);
    try vm.native_fns.put(a, "SplFixedArray::setSize", faSetSize);
    try vm.native_fns.put(a, "SplFixedArray::count", faCount);
    try vm.native_fns.put(a, "SplFixedArray::toArray", faToArray);
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
    var sq_def = ClassDef{ .name = "SplQueue" };
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
    var dll_def = ClassDef{ .name = "SplDoublyLinkedList" };
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
    try dll_def.static_props.put(a, "IT_MODE_LIFO", .{ .int = DLL_IT_MODE_LIFO });
    try dll_def.static_props.put(a, "IT_MODE_FIFO", .{ .int = DLL_IT_MODE_FIFO });
    try dll_def.static_props.put(a, "IT_MODE_DELETE", .{ .int = DLL_IT_MODE_DELETE });
    try dll_def.static_props.put(a, "IT_MODE_KEEP", .{ .int = DLL_IT_MODE_KEEP });
    try vm.classes.put(a, "SplDoublyLinkedList", dll_def);

    try vm.native_fns.put(a, "SplDoublyLinkedList::__construct", dllConstruct);
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
    var sos_def = ClassDef{ .name = "SplObjectStorage" };
    try sos_def.interfaces.append(a, "Countable");
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
    try vm.classes.put(a, "SplObjectStorage", sos_def);

    try vm.native_fns.put(a, "SplObjectStorage::__construct", sosConstruct);
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
            arr.rebuildStringIndex(ctx.allocator) catch {};
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

// --- ArrayIterator ---

fn aiConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len >= 1 and args[0] == .array) {
        try obj.set(ctx.allocator, "__data", args[0]);
    } else {
        _ = try ensureData(ctx, obj);
    }
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    try obj.set(ctx.allocator, "__flags", .{ .int = 0 });
    return .null;
}

fn aiRewind(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    return .null;
}

fn aiCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .{ .bool = false };
    const cursor: usize = @intCast(@max(Value.toInt(obj.get("__cursor")), 0));
    if (cursor >= arr.entries.items.len) return .{ .bool = false };
    return arr.entries.items[cursor].value;
}

fn aiKey(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    const cursor: usize = @intCast(@max(Value.toInt(obj.get("__cursor")), 0));
    if (cursor >= arr.entries.items.len) return .null;
    const key = arr.entries.items[cursor].key;
    return switch (key) {
        .int => |i| .{ .int = i },
        .string => |s| .{ .string = s },
    };
}

fn aiNext(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const cursor = Value.toInt(obj.get("__cursor"));
    try obj.set(ctx.allocator, "__cursor", .{ .int = cursor + 1 });
    return .null;
}

fn aiValid(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const arr = getData(obj) orelse return .{ .bool = false };
    const cursor = Value.toInt(obj.get("__cursor"));
    return .{ .bool = cursor >= 0 and cursor < arr.length() };
}

fn aiCount(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    const arr = getData(obj) orelse return .{ .int = 0 };
    return .{ .int = arr.length() };
}

fn aiOffsetGet(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    if (args.len == 0) return .null;
    return arr.get(args[0].toArrayKey());
}

fn aiOffsetSet(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
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

fn aiOffsetExists(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const arr = getData(obj) orelse return .{ .bool = false };
    if (args.len == 0) return .{ .bool = false };
    const key = args[0].toArrayKey();
    for (arr.entries.items) |entry| {
        if (entry.key.eql(key)) return .{ .bool = true };
    }
    return .{ .bool = false };
}

fn aiOffsetUnset(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    if (args.len == 0) return .null;
    const key = args[0].toArrayKey();
    for (arr.entries.items, 0..) |entry, i| {
        if (entry.key.eql(key)) {
            _ = arr.entries.orderedRemove(i);
            arr.rebuildStringIndex(ctx.allocator) catch {};
            return .null;
        }
    }
    return .null;
}

fn aiGetArrayCopy(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
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

fn aiAppend(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = try ensureData(ctx, obj);
    if (args.len >= 1) try arr.append(ctx.allocator, args[0]);
    return .null;
}

fn aiGetFlags(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    return .{ .int = Value.toInt(obj.get("__flags")) };
}

fn aiSetFlags(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len >= 1) try obj.set(ctx.allocator, "__flags", .{ .int = Value.toInt(args[0]) });
    return .null;
}

// --- WeakMap ---

fn wmObjKey(arg: Value) ?i64 {
    if (arg == .object) return @intCast(@intFromPtr(arg.object));
    return null;
}

fn wmConstruct(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    _ = try ensureData(ctx, obj);
    return .null;
}

fn wmOffsetExists(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const arr = getData(obj) orelse return .{ .bool = false };
    if (args.len == 0) return .{ .bool = false };
    const key = wmObjKey(args[0]) orelse return .{ .bool = false };
    const k = PhpArray.Key{ .int = key };
    return .{ .bool = arr.get(k) != .null };
}

fn wmOffsetGet(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    if (args.len == 0) return .null;
    const key = wmObjKey(args[0]) orelse return .null;
    return arr.get(.{ .int = key });
}

fn wmOffsetSet(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = try ensureData(ctx, obj);
    if (args.len < 2) return .null;
    const key = wmObjKey(args[0]) orelse return .null;
    try arr.set(ctx.allocator, .{ .int = key }, args[1]);
    return .null;
}

fn wmOffsetUnset(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    if (args.len == 0) return .null;
    const key = wmObjKey(args[0]) orelse return .null;
    arr.remove(.{ .int = key });
    return .null;
}

fn wmCount(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    const arr = getData(obj) orelse return .{ .int = 0 };
    return .{ .int = @intCast(arr.entries.items.len) };
}

// --- SplPriorityQueue ---
// stores pairs as [value, priority] in __data, sorted by priority descending

const EXTR_DATA: i64 = 1;
const EXTR_PRIORITY: i64 = 2;
const EXTR_BOTH: i64 = 3;

fn pqConstruct(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    _ = try ensureData(ctx, obj);
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    try obj.set(ctx.allocator, "__flags", .{ .int = EXTR_DATA });
    return .null;
}

fn pqInsert(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = try ensureData(ctx, obj);
    if (args.len < 2) return .null;
    const pair = try ctx.allocator.create(PhpArray);
    pair.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, pair);
    try pair.set(ctx.allocator, .{ .int = 0 }, args[0]);
    try pair.set(ctx.allocator, .{ .int = 1 }, args[1]);

    var pos: usize = 0;
    for (arr.entries.items) |entry| {
        if (entry.value != .array) break;
        const ep = entry.value.array.get(.{ .int = 1 });
        if (Value.compare(args[1], ep) > 0) break;
        pos += 1;
    }
    try arr.entries.insert(ctx.allocator, pos, .{ .key = .{ .int = @intCast(arr.entries.items.len) }, .value = .{ .array = pair } });
    return .null;
}

fn pqExtractValue(ctx: *NativeContext, obj: *PhpObject) RuntimeError!Value {
    const arr = getData(obj) orelse return .null;
    if (arr.entries.items.len == 0) return .null;
    const entry = arr.entries.items[0].value;
    std.mem.copyForwards(PhpArray.Entry, arr.entries.items[0 .. arr.entries.items.len - 1], arr.entries.items[1..arr.entries.items.len]);
    arr.entries.items.len -= 1;
    return pqFormatEntry(ctx, obj, entry);
}

fn pqFormatEntry(_: *NativeContext, obj: *PhpObject, entry: Value) Value {
    const flags = Value.toInt(obj.get("__flags"));
    if (entry != .array) return entry;
    const pair = entry.array;
    if (flags == EXTR_PRIORITY) return pair.get(.{ .int = 1 });
    if (flags == EXTR_BOTH) return entry;
    return pair.get(.{ .int = 0 });
}

fn pqExtract(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    return pqExtractValue(ctx, obj);
}

fn pqTop(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    if (arr.entries.items.len == 0) return .null;
    return pqFormatEntry(ctx, obj, arr.entries.items[0].value);
}

fn pqCount(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    const arr = getData(obj) orelse return .{ .int = 0 };
    return .{ .int = @intCast(arr.entries.items.len) };
}

fn pqIsEmpty(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = true };
    const arr = getData(obj) orelse return .{ .bool = true };
    return .{ .bool = arr.entries.items.len == 0 };
}

fn pqSetExtractFlags(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len >= 1) try obj.set(ctx.allocator, "__flags", .{ .int = Value.toInt(args[0]) });
    return .null;
}

// pq iteration is destructive: current = top, next = extract, key = remaining-1
fn pqCurrent(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return pqTop(ctx, args);
}

fn pqKey(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    if (arr.entries.items.len == 0) return .null;
    return .{ .int = @intCast(arr.entries.items.len - 1) };
}

fn pqNext(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    _ = try pqExtract(ctx, args);
    return .null;
}

fn pqRewind(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .null;
}

fn pqValid(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const arr = getData(obj) orelse return .{ .bool = false };
    return .{ .bool = arr.entries.items.len > 0 };
}

// --- SplMinHeap / SplMaxHeap ---
// stored as flat array in __data, heap-ordered

fn heapConstruct(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    _ = try ensureData(ctx, obj);
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    return .null;
}

fn heapInsert(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = try ensureData(ctx, obj);
    if (args.len == 0) return .null;
    try arr.append(ctx.allocator, args[0]);
    return .null;
}

fn findMinIdx(arr: *PhpArray) ?usize {
    if (arr.entries.items.len == 0) return null;
    var best: usize = 0;
    for (arr.entries.items[1..], 1..) |entry, i| {
        if (Value.compare(entry.value, arr.entries.items[best].value) < 0) best = i;
    }
    return best;
}

fn findMaxIdx(arr: *PhpArray) ?usize {
    if (arr.entries.items.len == 0) return null;
    var best: usize = 0;
    for (arr.entries.items[1..], 1..) |entry, i| {
        if (Value.compare(entry.value, arr.entries.items[best].value) > 0) best = i;
    }
    return best;
}

fn heapRemoveAt(arr: *PhpArray, idx: usize) Value {
    const val = arr.entries.items[idx].value;
    std.mem.copyForwards(PhpArray.Entry, arr.entries.items[idx .. arr.entries.items.len - 1], arr.entries.items[idx + 1 .. arr.entries.items.len]);
    arr.entries.items.len -= 1;
    return val;
}

fn minHeapExtract(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    const idx = findMinIdx(arr) orelse return .null;
    return heapRemoveAt(arr, idx);
}

fn minHeapTop(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    const idx = findMinIdx(arr) orelse return .null;
    return arr.entries.items[idx].value;
}

fn maxHeapExtract(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    const idx = findMaxIdx(arr) orelse return .null;
    return heapRemoveAt(arr, idx);
}

fn maxHeapTop(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    const idx = findMaxIdx(arr) orelse return .null;
    return arr.entries.items[idx].value;
}

fn heapCount(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    const arr = getData(obj) orelse return .{ .int = 0 };
    return .{ .int = @intCast(arr.entries.items.len) };
}

fn heapIsEmpty(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = true };
    const arr = getData(obj) orelse return .{ .bool = true };
    return .{ .bool = arr.entries.items.len == 0 };
}

fn heapCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .{ .bool = false };
    const cursor: usize = @intCast(@max(Value.toInt(obj.get("__cursor")), 0));
    if (cursor >= arr.entries.items.len) return .{ .bool = false };
    return arr.entries.items[cursor].value;
}

fn heapKey(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    if (arr.entries.items.len == 0) return .null;
    return .{ .int = @intCast(arr.entries.items.len - 1) };
}

fn heapNext(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const cursor = Value.toInt(obj.get("__cursor"));
    try obj.set(ctx.allocator, "__cursor", .{ .int = cursor + 1 });
    return .null;
}

fn heapRewind(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    return .null;
}

fn heapValid(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const arr = getData(obj) orelse return .{ .bool = false };
    return .{ .bool = arr.entries.items.len > 0 };
}

// --- SplFixedArray ---

fn faConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = try ensureData(ctx, obj);
    const size: usize = if (args.len >= 1) @intCast(@max(Value.toInt(args[0]), 0)) else 0;
    var i: usize = 0;
    while (i < size) : (i += 1) {
        try arr.append(ctx.allocator, .null);
    }
    try obj.set(ctx.allocator, "__size", .{ .int = @intCast(size) });
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    return .null;
}

fn faGetSize(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    return .{ .int = Value.toInt(obj.get("__size")) };
}

fn faSetSize(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = try ensureData(ctx, obj);
    if (args.len == 0) return .null;
    const new_size: usize = @intCast(@max(Value.toInt(args[0]), 0));
    const cur_len = arr.entries.items.len;
    if (new_size > cur_len) {
        var i: usize = cur_len;
        while (i < new_size) : (i += 1) {
            try arr.append(ctx.allocator, .null);
        }
    } else {
        arr.entries.items.len = new_size;
    }
    try obj.set(ctx.allocator, "__size", .{ .int = @intCast(new_size) });
    return .null;
}

fn faCount(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    return .{ .int = Value.toInt(obj.get("__size")) };
}

fn faToArray(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
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
    for (arr.entries.items, 0..) |entry, i| {
        try copy.set(ctx.allocator, .{ .int = @intCast(i) }, entry.value);
    }
    return .{ .array = copy };
}

fn faOffsetGet(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    if (args.len == 0) return .null;
    const idx: usize = @intCast(@max(Value.toInt(args[0]), 0));
    if (idx >= arr.entries.items.len) return .null;
    return arr.entries.items[idx].value;
}

fn faOffsetSet(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    if (args.len < 2) return .null;
    const idx: usize = @intCast(@max(Value.toInt(args[0]), 0));
    if (idx >= arr.entries.items.len) return .null;
    arr.entries.items[idx].value = args[1];
    return .null;
}

fn faOffsetExists(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const arr = getData(obj) orelse return .{ .bool = false };
    if (args.len == 0) return .{ .bool = false };
    const idx: usize = @intCast(@max(Value.toInt(args[0]), 0));
    if (idx >= arr.entries.items.len) return .{ .bool = false };
    return .{ .bool = arr.entries.items[idx].value != .null };
}

fn faOffsetUnset(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    if (args.len == 0) return .null;
    const idx: usize = @intCast(@max(Value.toInt(args[0]), 0));
    if (idx >= arr.entries.items.len) return .null;
    arr.entries.items[idx].value = .null;
    return .null;
}

fn faCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .{ .bool = false };
    const cursor: usize = @intCast(@max(Value.toInt(obj.get("__cursor")), 0));
    if (cursor >= arr.entries.items.len) return .{ .bool = false };
    return arr.entries.items[cursor].value;
}

fn faKey(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    const cursor = Value.toInt(obj.get("__cursor"));
    if (cursor < 0 or cursor >= @as(i64, @intCast(arr.entries.items.len))) return .null;
    return .{ .int = cursor };
}

fn faNext(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const cursor = Value.toInt(obj.get("__cursor"));
    try obj.set(ctx.allocator, "__cursor", .{ .int = cursor + 1 });
    return .null;
}

fn faRewind(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    return .null;
}

fn faValid(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const arr = getData(obj) orelse return .{ .bool = false };
    const cursor = Value.toInt(obj.get("__cursor"));
    return .{ .bool = cursor >= 0 and cursor < @as(i64, @intCast(arr.entries.items.len)) };
}

// --- SplQueue ---

fn sqConstruct(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    _ = try ensureData(ctx, obj);
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    return .null;
}

fn sqEnqueue(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = try ensureData(ctx, obj);
    if (args.len >= 1) try arr.append(ctx.allocator, args[0]);
    return .null;
}

fn sqDequeue(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    if (arr.entries.items.len == 0) return .null;
    const first = arr.entries.items[0].value;
    std.mem.copyForwards(PhpArray.Entry, arr.entries.items[0 .. arr.entries.items.len - 1], arr.entries.items[1..arr.entries.items.len]);
    arr.entries.items.len -= 1;
    return first;
}

fn sqBottom(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    if (arr.entries.items.len == 0) return .null;
    return arr.entries.items[0].value;
}

fn sqTop(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    if (arr.entries.items.len == 0) return .null;
    return arr.entries.items[arr.entries.items.len - 1].value;
}

fn sqCount(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    const arr = getData(obj) orelse return .{ .int = 0 };
    return .{ .int = @intCast(arr.entries.items.len) };
}

fn sqIsEmpty(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = true };
    const arr = getData(obj) orelse return .{ .bool = true };
    return .{ .bool = arr.entries.items.len == 0 };
}

fn sqCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .{ .bool = false };
    const cursor: usize = @intCast(@max(Value.toInt(obj.get("__cursor")), 0));
    if (cursor >= arr.entries.items.len) return .{ .bool = false };
    return arr.entries.items[cursor].value;
}

fn sqKey(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    const cursor = Value.toInt(obj.get("__cursor"));
    if (cursor < 0 or cursor >= @as(i64, @intCast(arr.entries.items.len))) return .null;
    return .{ .int = cursor };
}

fn sqNext(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const cursor = Value.toInt(obj.get("__cursor"));
    try obj.set(ctx.allocator, "__cursor", .{ .int = cursor + 1 });
    return .null;
}

fn sqRewind(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    return .null;
}

fn sqValid(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const arr = getData(obj) orelse return .{ .bool = false };
    const cursor = Value.toInt(obj.get("__cursor"));
    return .{ .bool = cursor >= 0 and cursor < @as(i64, @intCast(arr.entries.items.len)) };
}

// --- SplDoublyLinkedList ---

const DLL_IT_MODE_LIFO: i64 = 2;
const DLL_IT_MODE_FIFO: i64 = 0;
const DLL_IT_MODE_DELETE: i64 = 1;
const DLL_IT_MODE_KEEP: i64 = 0;

fn dllConstruct(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    _ = try ensureData(ctx, obj);
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    try obj.set(ctx.allocator, "__it_mode", .{ .int = DLL_IT_MODE_FIFO | DLL_IT_MODE_KEEP });
    return .null;
}

fn dllPush(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = try ensureData(ctx, obj);
    if (args.len >= 1) try arr.append(ctx.allocator, args[0]);
    return .null;
}

fn dllPop(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    if (arr.entries.items.len == 0) return .null;
    const last = arr.entries.items[arr.entries.items.len - 1].value;
    arr.entries.items.len -= 1;
    return last;
}

fn dllUnshift(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = try ensureData(ctx, obj);
    if (args.len == 0) return .null;
    try arr.entries.insert(ctx.allocator, 0, .{ .key = .{ .int = 0 }, .value = args[0] });
    return .null;
}

fn dllShift(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    if (arr.entries.items.len == 0) return .null;
    const first = arr.entries.items[0].value;
    std.mem.copyForwards(PhpArray.Entry, arr.entries.items[0 .. arr.entries.items.len - 1], arr.entries.items[1..arr.entries.items.len]);
    arr.entries.items.len -= 1;
    return first;
}

fn dllTop(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    if (arr.entries.items.len == 0) return .null;
    return arr.entries.items[arr.entries.items.len - 1].value;
}

fn dllBottom(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    if (arr.entries.items.len == 0) return .null;
    return arr.entries.items[0].value;
}

fn dllCount(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    const arr = getData(obj) orelse return .{ .int = 0 };
    return .{ .int = arr.length() };
}

fn dllIsEmpty(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = true };
    const arr = getData(obj) orelse return .{ .bool = true };
    return .{ .bool = arr.entries.items.len == 0 };
}

fn dllSetIteratorMode(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len >= 1 and args[0] == .int) {
        try obj.set(ctx.allocator, "__it_mode", args[0]);
    }
    return .null;
}

fn dllGetIteratorMode(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    return obj.get("__it_mode");
}

fn dllRewind(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const mode = Value.toInt(obj.get("__it_mode"));
    const is_lifo = (mode & DLL_IT_MODE_LIFO) != 0;
    if (is_lifo) {
        const arr = getData(obj) orelse {
            try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
            return .null;
        };
        try obj.set(ctx.allocator, "__cursor", .{ .int = @as(i64, @intCast(arr.entries.items.len)) - 1 });
    } else {
        try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    }
    return .null;
}

fn dllCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const arr = getData(obj) orelse return .{ .bool = false };
    const cursor = Value.toInt(obj.get("__cursor"));
    if (cursor < 0 or cursor >= @as(i64, @intCast(arr.entries.items.len))) return .{ .bool = false };
    return arr.entries.items[@intCast(cursor)].value;
}

fn dllKey(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    return obj.get("__cursor");
}

fn dllNext(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const mode = Value.toInt(obj.get("__it_mode"));
    const is_lifo = (mode & DLL_IT_MODE_LIFO) != 0;
    const cursor = Value.toInt(obj.get("__cursor"));
    if (is_lifo) {
        try obj.set(ctx.allocator, "__cursor", .{ .int = cursor - 1 });
    } else {
        try obj.set(ctx.allocator, "__cursor", .{ .int = cursor + 1 });
    }
    return .null;
}

fn dllPrev(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const mode = Value.toInt(obj.get("__it_mode"));
    const is_lifo = (mode & DLL_IT_MODE_LIFO) != 0;
    const cursor = Value.toInt(obj.get("__cursor"));
    if (is_lifo) {
        try obj.set(ctx.allocator, "__cursor", .{ .int = cursor + 1 });
    } else {
        try obj.set(ctx.allocator, "__cursor", .{ .int = cursor - 1 });
    }
    return .null;
}

fn dllValid(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const arr = getData(obj) orelse return .{ .bool = false };
    const cursor = Value.toInt(obj.get("__cursor"));
    return .{ .bool = cursor >= 0 and cursor < @as(i64, @intCast(arr.entries.items.len)) };
}

fn dllOffsetGet(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    if (args.len == 0) return .null;
    const idx = Value.toInt(args[0]);
    if (idx < 0 or idx >= @as(i64, @intCast(arr.entries.items.len))) return .null;
    return arr.entries.items[@intCast(idx)].value;
}

fn dllOffsetSet(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = try ensureData(ctx, obj);
    if (args.len < 2) return .null;
    if (args[0] == .null) {
        try arr.append(ctx.allocator, args[1]);
    } else {
        const idx = Value.toInt(args[0]);
        if (idx >= 0 and idx < @as(i64, @intCast(arr.entries.items.len))) {
            arr.entries.items[@intCast(idx)].value = args[1];
        }
    }
    return .null;
}

fn dllOffsetExists(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const arr = getData(obj) orelse return .{ .bool = false };
    if (args.len == 0) return .{ .bool = false };
    const idx = Value.toInt(args[0]);
    return .{ .bool = idx >= 0 and idx < @as(i64, @intCast(arr.entries.items.len)) };
}

fn dllOffsetUnset(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse return .null;
    if (args.len == 0) return .null;
    const idx = Value.toInt(args[0]);
    if (idx >= 0 and idx < @as(i64, @intCast(arr.entries.items.len))) {
        _ = arr.entries.orderedRemove(@intCast(idx));
    }
    return .null;
}

fn dllAdd(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = try ensureData(ctx, obj);
    if (args.len < 2) return .null;
    const idx = Value.toInt(args[0]);
    if (idx < 0) return .null;
    const uidx: usize = @intCast(idx);
    if (uidx > arr.entries.items.len) return .null;
    try arr.entries.insert(ctx.allocator, uidx, .{ .key = .{ .int = idx }, .value = args[1] });
    return .null;
}

fn dllToArray(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = getData(obj) orelse {
        const new_arr = try ctx.createArray();
        return .{ .array = new_arr };
    };
    const result = try ctx.createArray();
    for (arr.entries.items, 0..) |entry, i| {
        try result.set(ctx.allocator, .{ .int = @intCast(i) }, entry.value);
    }
    return .{ .array = result };
}

// --- SplObjectStorage ---
// stores objects keyed by pointer identity, each with optional associated data

fn sosObjKey(obj: *PhpObject) i64 {
    return @intCast(@intFromPtr(obj));
}

fn sosConstruct(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    _ = try ensureData(ctx, obj);
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    // __info stores associated data keyed by object pointer as string
    const info_arr = try ctx.allocator.create(PhpArray);
    info_arr.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, info_arr);
    try obj.set(ctx.allocator, "__info", .{ .array = info_arr });
    // __objs stores object references in insertion order for iteration
    const objs_arr = try ctx.allocator.create(PhpArray);
    objs_arr.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, objs_arr);
    try obj.set(ctx.allocator, "__objs", .{ .array = objs_arr });
    return .null;
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

fn sosFindIndex(objs: *PhpArray, target: *PhpObject) ?usize {
    const target_key = sosObjKey(target);
    for (objs.entries.items, 0..) |entry, i| {
        if (entry.value == .object and sosObjKey(entry.value.object) == target_key) return i;
    }
    return null;
}

fn sosAttach(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len == 0 or args[0] != .object) return .null;
    const target = args[0].object;
    const data = if (args.len >= 2) args[1] else Value.null;
    const objs = sosGetObjs(obj) orelse return .null;
    const info = sosGetInfo(obj) orelse return .null;
    const key: PhpArray.Key = .{ .int = sosObjKey(target) };

    if (sosFindIndex(objs, target)) |_| {
        try info.set(ctx.allocator, key, data);
    } else {
        try objs.append(ctx.allocator, .{ .object = target });
        try info.set(ctx.allocator, key, data);
    }
    return .null;
}

fn sosDetach(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len == 0 or args[0] != .object) return .null;
    const target = args[0].object;
    const objs = sosGetObjs(obj) orelse return .null;
    const info = sosGetInfo(obj) orelse return .null;

    if (sosFindIndex(objs, target)) |idx| {
        _ = objs.entries.orderedRemove(idx);
        info.remove(.{ .int = sosObjKey(target) });
    }
    return .null;
}

fn sosContains(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    if (args.len == 0 or args[0] != .object) return .{ .bool = false };
    const objs = sosGetObjs(obj) orelse return .{ .bool = false };
    return .{ .bool = sosFindIndex(objs, args[0].object) != null };
}

fn sosCount(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    const objs = sosGetObjs(obj) orelse return .{ .int = 0 };
    return .{ .int = @intCast(objs.entries.items.len) };
}

fn sosGetInfoMethod(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const objs = sosGetObjs(obj) orelse return .null;
    const info = sosGetInfo(obj) orelse return .null;
    const cursor = Value.toInt(obj.get("__cursor"));
    if (cursor < 0 or cursor >= @as(i64, @intCast(objs.entries.items.len))) return .null;
    const cur_obj = objs.entries.items[@intCast(cursor)].value;
    if (cur_obj != .object) return .null;
    return info.get(.{ .int = sosObjKey(cur_obj.object) });
}

fn sosSetInfoMethod(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len == 0) return .null;
    const objs = sosGetObjs(obj) orelse return .null;
    const info = sosGetInfo(obj) orelse return .null;
    const cursor = Value.toInt(obj.get("__cursor"));
    if (cursor < 0 or cursor >= @as(i64, @intCast(objs.entries.items.len))) return .null;
    const cur_obj = objs.entries.items[@intCast(cursor)].value;
    if (cur_obj != .object) return .null;
    try info.set(ctx.allocator, .{ .int = sosObjKey(cur_obj.object) }, args[0]);
    return .null;
}

fn sosGetHash(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .null;
    return .{ .int = sosObjKey(args[0].object) };
}

fn sosRewind(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    return .null;
}

fn sosCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const objs = sosGetObjs(obj) orelse return .{ .bool = false };
    const cursor = Value.toInt(obj.get("__cursor"));
    if (cursor < 0 or cursor >= @as(i64, @intCast(objs.entries.items.len))) return .{ .bool = false };
    return objs.entries.items[@intCast(cursor)].value;
}

fn sosKey(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    return obj.get("__cursor");
}

fn sosNext(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const cursor = Value.toInt(obj.get("__cursor"));
    try obj.set(ctx.allocator, "__cursor", .{ .int = cursor + 1 });
    return .null;
}

fn sosValid(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const objs = sosGetObjs(obj) orelse return .{ .bool = false };
    const cursor = Value.toInt(obj.get("__cursor"));
    return .{ .bool = cursor >= 0 and cursor < @as(i64, @intCast(objs.entries.items.len)) };
}

fn sosRemoveAll(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len == 0 or args[0] != .object) return .null;
    const other_this = args[0].object;
    const other_objs = sosGetObjs(other_this) orelse return .null;
    const objs = sosGetObjs(obj) orelse return .null;
    const info = sosGetInfo(obj) orelse return .null;

    var i: usize = 0;
    while (i < objs.entries.items.len) {
        const entry = objs.entries.items[i];
        if (entry.value == .object and sosFindIndex(other_objs, entry.value.object) != null) {
            info.remove(.{ .int = sosObjKey(entry.value.object) });
            _ = objs.entries.orderedRemove(i);
        } else {
            i += 1;
        }
    }
    return .null;
}

fn sosRemoveAllExcept(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len == 0 or args[0] != .object) return .null;
    const other_this = args[0].object;
    const other_objs = sosGetObjs(other_this) orelse return .null;
    const objs = sosGetObjs(obj) orelse return .null;
    const info = sosGetInfo(obj) orelse return .null;

    var i: usize = 0;
    while (i < objs.entries.items.len) {
        const entry = objs.entries.items[i];
        if (entry.value == .object and sosFindIndex(other_objs, entry.value.object) == null) {
            info.remove(.{ .int = sosObjKey(entry.value.object) });
            _ = objs.entries.orderedRemove(i);
        } else {
            i += 1;
        }
    }
    return .null;
}

fn sosAddAll(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len == 0 or args[0] != .object) return .null;
    const other_this = args[0].object;
    const other_objs = sosGetObjs(other_this) orelse return .null;
    const other_info = sosGetInfo(other_this) orelse return .null;
    const objs = sosGetObjs(obj) orelse return .null;
    const info = sosGetInfo(obj) orelse return .null;

    for (other_objs.entries.items) |entry| {
        if (entry.value == .object) {
            const target = entry.value.object;
            if (sosFindIndex(objs, target) == null) {
                try objs.append(ctx.allocator, .{ .object = target });
            }
            const data = other_info.get(.{ .int = sosObjKey(target) });
            try info.set(ctx.allocator, .{ .int = sosObjKey(target) }, data);
        }
    }
    return .null;
}

fn sosOffsetGet(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len == 0 or args[0] != .object) return .null;
    const info = sosGetInfo(obj) orelse return .null;
    return info.get(.{ .int = sosObjKey(args[0].object) });
}

fn sosOffsetSet(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    // offsetSet($obj, $data) is equivalent to attach($obj, $data)
    return sosAttach(ctx, args);
}

fn sosOffsetExists(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return sosContains(ctx, args);
}

fn sosOffsetUnset(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return sosDetach(ctx, args);
}
