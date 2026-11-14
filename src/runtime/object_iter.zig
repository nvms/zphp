// foreach over a plain object (not Traversable): php's FE_FETCH over the
// object's property table, read live. each step reads the property as it is
// now, skips one that was unset or can't be seen from the loop's scope, and
// properties added during the loop are reached after the ones it started
// with. a class with property hooks iterates as zend_hooked_object_get_iterator
// does: its declared properties fixed at the start, each read through its
// get hook when the loop reaches it, then the dynamic ones live

const std = @import("std");
const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const ClassDef = vm_mod.ClassDef;
const RuntimeError = vm_mod.RuntimeError;
const value_mod = @import("value.zig");
const Value = value_mod.Value;
const PhpArray = value_mod.PhpArray;
const PhpObject = value_mod.PhpObject;
const object_properties = @import("object_properties.zig");

pub const ObjectIter = struct {
    const Kind = enum { slot, dynamic, hooked };
    const Item = struct {
        kind: Kind,
        // the declared slot of a .slot item
        slot: u32 = 0,
        // a declared name is class metadata; a dynamic one is owned here
        name: Value.String,
        declaring: []const u8 = "",
        private: bool = false,
    };
    items: std.ArrayListUnmanaged(Item) = .empty,
    // the dynamic properties the loop already knows
    seen: std.StringHashMapUnmanaged(void) = .{},
    // the value the last get hook returned, held while the body reads it
    held: ?*PhpArray = null,
    scope: ?[]const u8 = null,
    // a by-reference loop binds each property itself: the fetch only finds
    // the next one, without running its get hook
    by_ref: bool = false,

    pub fn destroy(self: *ObjectIter, vm: *VM) void {
        for (self.items.items) |item| if (item.kind == .dynamic) item.name.release();
        self.items.deinit(vm.allocator);
        self.seen.deinit(vm.allocator);
        if (self.held) |h| vm.releaseUnheldArray(h);
        vm.allocator.destroy(self);
    }
};

// a private property the scope declares hides every other property of the
// name from it (zend_get_property_info resolves the name to it)
fn scopePrivateShadows(vm: *VM, obj: *PhpObject, scope: ?[]const u8, name: []const u8) bool {
    const sc = scope orelse return false;
    if (!vm.isInstanceOf(obj.class_name, sc)) return false;
    const def = vm.classes.get(sc) orelse return false;
    for (def.properties.items) |prop| {
        if (prop.visibility == .private and std.mem.eql(u8, prop.name, name)) return true;
    }
    return false;
}

// zend_check_property_access for a declared property
fn declaredVisible(vm: *VM, obj: *PhpObject, scope: ?[]const u8, name: []const u8, visibility: ClassDef.Visibility, declaring: []const u8) bool {
    return switch (visibility) {
        .private => if (scope) |sc| std.mem.eql(u8, sc, declaring) else false,
        .protected => object_properties.accessible(vm, scope, .protected, declaring) and !scopePrivateShadows(vm, obj, scope, name),
        .public => !scopePrivateShadows(vm, obj, scope, name),
    };
}

pub fn create(vm: *VM, obj: *PhpObject, scope: ?[]const u8, by_ref: bool) RuntimeError!*ObjectIter {
    const it = try vm.allocator.create(ObjectIter);
    it.* = .{ .scope = scope, .by_ref = by_ref };
    errdefer it.destroy(vm);
    if (object_properties.classHasHooks(vm, obj.class_name)) {
        var order: std.ArrayListUnmanaged(object_properties.Declared) = .empty;
        defer order.deinit(vm.allocator);
        try object_properties.declaredOrder(vm, obj.class_name, vm.allocator, &order);
        for (order.items) |e| {
            if (!declaredVisible(vm, obj, scope, e.name, e.visibility, e.declaring)) continue;
            try it.items.append(vm.allocator, .{ .kind = .hooked, .name = Value.String.borrowed(e.name), .declaring = e.declaring, .private = e.visibility == .private });
        }
    } else if (obj.slot_layout) |layout| {
        for (layout.names, 0..) |name, i| {
            if (object_properties.isInternalState(vm, obj, name)) continue;
            const declared = vm.propertyDeclaration(layout.declaring_classes[i], name);
            if (!declaredVisible(vm, obj, scope, name, declared.visibility, declared.defining_class)) continue;
            try it.items.append(vm.allocator, .{ .kind = .slot, .slot = @intCast(i), .name = Value.String.borrowed(name), .declaring = layout.declaring_classes[i] });
        }
    }
    _ = try addDynamic(vm, it, obj);
    return it;
}

// the dynamic properties the loop hasn't seen, in the order they were added
fn addDynamic(vm: *VM, it: *ObjectIter, obj: *PhpObject) RuntimeError!bool {
    var added = false;
    var props = obj.properties.iterator();
    while (props.next()) |entry| {
        const name = entry.key_ptr.*;
        if (it.seen.contains(name)) continue;
        if (object_properties.isInternalState(vm, obj, name)) continue;
        // beside a slot of the same name (an ancestor's private) the entry is
        // a dynamic property of its own
        if (obj.slot_layout) |layout| if (object_properties.inSlots(layout, name) and !object_properties.shadowsPrivate(layout, name)) continue;
        const owned = try Value.String.create(vm.allocator, name);
        it.items.append(vm.allocator, .{ .kind = .dynamic, .name = owned }) catch |err| {
            owned.release();
            return err;
        };
        try it.seen.put(vm.allocator, owned.bytes(), {});
        added = true;
    }
    return added;
}

// the object a lazy proxy, or a chain of them, stands for
pub fn innermost(obj: *PhpObject) *PhpObject {
    var o = obj;
    while (o.storage() != o) o = o.storage();
    return o;
}

pub const Step = struct { index: usize, key: Value, value: Value };

fn slotValue(vm: *VM, obj: *PhpObject, index: usize, name: []const u8, declaring: []const u8) ?Value {
    const slots = obj.slots orelse return null;
    if (index >= slots.len) return null;
    if (obj.lazy != null and obj.isLazySlot(name, declaring) and !obj.isLazyWrittenSlot(name, declaring)) return null;
    if (obj.isUnset(name)) return null;
    const v = slots[index];
    if (v == .undef) return null;
    if (v == .null) {
        const declared = vm.propertyDeclaration(declaring, name);
        if (declared.type_str.len > 0 and vm.typedPropForbidsNull(declared.type_str)) return null;
    }
    return v;
}

fn slotIndex(obj: *PhpObject, name: []const u8, declaring: []const u8) ?usize {
    const layout = obj.slot_layout orelse return null;
    for (layout.names, 0..) |slot_name, i| {
        if (!std.mem.eql(u8, slot_name, name)) continue;
        if (layout.is_private[i] and !std.mem.eql(u8, layout.declaring_classes[i], declaring)) continue;
        return i;
    }
    return null;
}

// the first element at or after `from` that is still there, or null once
// the loop has passed every property, including those added since it began
pub fn fetch(vm: *VM, it: *ObjectIter, obj: *PhpObject, from: usize) RuntimeError!?Step {
    var i = from;
    while (true) {
        while (i < it.items.items.len) : (i += 1) {
            const item = it.items.items[i];
            const name = item.name.bytes();
            switch (item.kind) {
                .slot => if (slotValue(vm, obj, item.slot, name, item.declaring)) |v| {
                    return .{ .index = i, .key = .{ .string = item.name }, .value = v };
                },
                .dynamic => if (obj.properties.get(name)) |v| {
                    if (name.len > 0 and name[0] == 0) {
                        // a name that looks mangled is a dynamic property's own;
                        // the loop shows the part after the class
                        const prop = object_properties.unmangle(name, v);
                        return .{ .index = i, .key = .{ .string = item.name.borrowedSlice(name.len - prop.key.name.len, name.len) }, .value = v };
                    }
                    if (scopePrivateShadows(vm, obj, it.scope, name)) continue;
                    return .{ .index = i, .key = .{ .string = item.name }, .value = v };
                },
                .hooked => {
                    // a private property's hooks are its declaring class's
                    const cls = if (item.private) item.declaring else obj.class_name;
                    if (vm.hasPropHook(cls, name, .get) and !vm.inPropHook(obj, name)) {
                        if (vm.propertyIsVirtual(cls, name) and !vm.hasRealGetHook(cls, name)) continue;
                        if (it.by_ref) return .{ .index = i, .key = .{ .string = item.name }, .value = .null };
                        if (vm.hasRealGetHook(cls, name)) {
                            const hook = try vm.resolveMethod(cls, try vm.propHookName(name, .get));
                            const v = try vm.callMethodAs(obj, hook, hook, &.{});
                            if (it.held) |h| vm.releaseUnheldArray(h);
                            const holder = try vm.allocArray();
                            it.held = holder;
                            try holder.append(vm.allocator, v);
                            return .{ .index = i, .key = .{ .string = item.name }, .value = v };
                        }
                    }
                    if (vm.propertyIsVirtual(cls, name)) continue;
                    const index = slotIndex(obj, name, item.declaring) orelse continue;
                    if (slotValue(vm, obj, index, name, item.declaring)) |v| {
                        return .{ .index = i, .key = .{ .string = item.name }, .value = v };
                    }
                },
            }
        }
        if (!try addDynamic(vm, it, obj)) return null;
    }
}
