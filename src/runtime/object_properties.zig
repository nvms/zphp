// the properties an object shows, per purpose, as php's get_properties_for
// gives them. a built-in class may build its own table for a purpose
// (ArrayObject's debug view has its storage, DateTime shows date, timezone_type
// and timezone everywhere); every other object shows its declared and dynamic
// properties. built-in classes keep their own state in properties named "__x",
// which no listing ever shows

const std = @import("std");
const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const ClassDef = vm_mod.ClassDef;
const RuntimeError = vm_mod.RuntimeError;
const value_mod = @import("value.zig");
const Value = value_mod.Value;
const PhpArray = value_mod.PhpArray;
const PhpObject = value_mod.PhpObject;

// php's ZEND_PROP_PURPOSE_*
pub const Purpose = enum {
    // var_dump, print_r, debug_zval_dump
    debug,
    // (array)
    array_cast,
    serialize,
    var_export,
    json,
};

pub const Key = union(enum) {
    int: i64,
    name: []const u8,
};

pub const Property = struct {
    key: Key,
    value: Value,
    visibility: ClassDef.Visibility = .public,
    // the class a private property belongs to
    declaring: []const u8 = "",
    // the name is class metadata, which outlives the object
    declared: bool = false,
    // the declared type of a typed property never initialized, which only
    // the debug view lists
    uninitialized: ?[]const u8 = null,
    // a hook's table entry that is a reference another holder shares
    shared: bool = false,
};

pub const Listing = struct {
    items: std.ArrayListUnmanaged(Property) = .empty,
    // the values get hooks returned, which the listing's items borrow:
    // release it (releaseHolder) once they are no longer read
    holder: ?*PhpArray = null,

    pub fn deinit(self: *Listing, allocator: std.mem.Allocator) void {
        self.items.deinit(allocator);
    }

    pub fn takeHolder(self: *Listing) ?*PhpArray {
        defer self.holder = null;
        return self.holder;
    }
};

pub fn releaseHolder(vm: *VM, holder: ?*PhpArray) void {
    if (holder) |h| vm.releaseUnheldArray(h);
}

fn classHasHooks(vm: *VM, class_name: []const u8) bool {
    if (!vm.any_prop_hooks) return false;
    var current: ?[]const u8 = class_name;
    while (current) |cn| {
        const def = vm.classes.get(cn) orelse return false;
        if (def.has_prop_hooks) return true;
        current = def.parent;
    }
    return false;
}

// php's zend_hooked_object_build_properties, read as json_encode,
// var_export, get_object_vars and foreach read it: declared properties in
// declaration order from the topmost class down, a hooked one's value from
// its get hook (a virtual one without a get hook left out), then dynamic
// properties. access: the scope whose access is checked, when it is
pub fn applyHooks(vm: *VM, obj: *PhpObject, listing: *Listing, allocator: std.mem.Allocator, access: ?struct { scope: ?[]const u8 }) RuntimeError!void {
    if (!classHasHooks(vm, obj.class_name)) return;
    const Entry = struct { name: []const u8, visibility: ClassDef.Visibility, declaring: []const u8 };
    var order: std.ArrayListUnmanaged(Entry) = .empty;
    defer order.deinit(allocator);
    var chain: std.ArrayListUnmanaged([]const u8) = .empty;
    defer chain.deinit(allocator);
    var current: ?[]const u8 = obj.class_name;
    while (current) |cn| {
        const def = vm.classes.get(cn) orelse break;
        try chain.append(allocator, def.name);
        current = def.parent;
    }
    var ci = chain.items.len;
    while (ci > 0) {
        ci -= 1;
        const def = vm.classes.get(chain.items[ci]) orelse continue;
        props: for (def.properties.items) |prop| {
            if (prop.visibility != .private) {
                for (order.items) |*e| if (e.visibility != .private and std.mem.eql(u8, e.name, prop.name)) {
                    e.visibility = prop.visibility;
                    e.declaring = def.name;
                    continue :props;
                };
            }
            try order.append(allocator, .{ .name = prop.name, .visibility = prop.visibility, .declaring = def.name });
        }
    }

    var out: std.ArrayListUnmanaged(Property) = .empty;
    errdefer out.deinit(allocator);
    const holder = listing.holder orelse try vm.allocArray();
    listing.holder = holder;
    for (order.items) |e| {
        if (access) |a| if (!accessible(vm, a.scope, e.visibility, e.declaring)) continue;
        const existing: ?Property = for (listing.items.items) |p| {
            if (!p.declared or p.key != .name or !std.mem.eql(u8, p.key.name, e.name)) continue;
            if (e.visibility == .private and !std.mem.eql(u8, p.declaring, e.declaring)) continue;
            break p;
        } else null;
        if (vm.hasPropHook(obj.class_name, e.name, .get) and !vm.inPropHook(obj, e.name)) {
            // a virtual property with only a set hook has nothing to read
            if (vm.propertyIsVirtual(obj.class_name, e.name) and !vm.hasRealGetHook(obj.class_name, e.name)) continue;
            if (!vm.hasRealGetHook(obj.class_name, e.name)) {
                if (existing) |p| try out.append(allocator, p);
                continue;
            }
            const value = (try vm.callPropHook(obj, e.name, .get, .null)) orelse (if (existing) |p| p.value else continue);
            try holder.append(vm.allocator, value);
            try out.append(allocator, .{ .key = .{ .name = e.name }, .value = value, .visibility = e.visibility, .declaring = e.declaring, .declared = true });
            continue;
        }
        if (existing) |p| try out.append(allocator, p);
    }
    for (listing.items.items) |p| if (!p.declared) try out.append(allocator, p);
    listing.items.deinit(allocator);
    listing.items = out;
}

fn accessible(vm: *VM, scope: ?[]const u8, visibility: ClassDef.Visibility, declaring: []const u8) bool {
    if (visibility == .public) return true;
    const sc = scope orelse return false;
    if (visibility == .private) return std.mem.eql(u8, sc, declaring);
    return vm.isInstanceOf(sc, declaring) or vm.isInstanceOf(declaring, sc);
}

// a built-in class's own table for a purpose, or null for its plain
// properties. keys of private and protected entries are mangled as (array)
// mangles them: "\0Class\0name", "\0*\0name"
pub const Hook = *const fn (*vm_mod.NativeContext, *PhpObject, Purpose) RuntimeError!?*PhpArray;

// php's lazy objects: a ghost until its initializer runs, a proxy for good
pub const Laziness = enum { none, ghost, proxy };

pub fn laziness(obj: *const PhpObject) Laziness {
    const state = obj.lazy orelse return .none;
    if (state.proxy) return if (state.initializer != .null or state.backing != null) .proxy else .none;
    return if (state.initializer != .null) .ghost else .none;
}

// what var_dump and debug_zval_dump write before "object("
pub fn lazyPrefix(obj: *const PhpObject) []const u8 {
    return switch (laziness(obj)) {
        .none => "",
        .ghost => "lazy ghost ",
        .proxy => "lazy proxy ",
    };
}

pub fn list(vm: *VM, obj: *PhpObject, purpose: Purpose, allocator: std.mem.Allocator) RuntimeError!Listing {
    var listing: Listing = .{};
    errdefer listing.deinit(allocator);
    // an initialized proxy shows its instance in the debug view and stands
    // for it everywhere else
    if (obj.lazy) |state| if (state.proxy) if (state.backing) |instance| {
        if (purpose == .debug) {
            try listing.items.append(allocator, .{ .key = .{ .name = "instance" }, .value = .{ .object = instance } });
            return listing;
        }
        return list(vm, instance, purpose, allocator);
    };
    if (try table(vm, obj, purpose)) |arr| {
        defer releaseBuilt(vm, arr);
        for (arr.entries.items) |entry| {
            const value = if (entry.ref) |ref| ref.* else entry.value;
            var prop: Property = switch (entry.key) {
                .int => |i| .{ .key = .{ .int = i }, .value = value },
                .string => |s| unmangle(s.bytes(), value),
            };
            if (entry.ref) |ref| prop.shared = value_mod.cellOf(ref).binders > 1;
            try listing.items.append(allocator, prop);
        }
        return listing;
    }
    try appendOwn(vm, obj, purpose, &listing, allocator);
    switch (purpose) {
        .json => try applyHooks(vm, obj, &listing, allocator, .{ .scope = null }),
        .var_export => try applyHooks(vm, obj, &listing, allocator, null),
        else => {},
    }
    return listing;
}

// a table built for one listing holds references to what it lists; once read
// it lets them go. a hook may instead return live storage, which others hold
pub fn releaseBuilt(vm: *VM, arr: *PhpArray) void {
    if (arr.refcount == 0) vm.releaseUnheldArray(arr);
}

// what replaces the object's own properties for a purpose: __debugInfo for
// the debug view, else the table its class builds
pub fn table(vm: *VM, obj: *PhpObject, purpose: Purpose) RuntimeError!?*PhpArray {
    if (purpose == .debug and vm.hasMethod(obj.class_name, "__debugInfo")) {
        const result = try vm.callMethod(obj, "__debugInfo", &.{});
        if (result == .array) return result.array;
        if (result == .null) return try vm.allocArray();
        return vm.raiseFatal("__debuginfo() must return an array");
    }
    var name: ?[]const u8 = obj.class_name;
    while (name) |n| {
        const def = vm.classes.get(n) orelse return null;
        if (def.native_properties) |hook| {
            var ctx = vm.makeContext(null);
            return hook(&ctx, obj, purpose);
        }
        name = def.parent;
    }
    return null;
}

// the object's declared properties in declaration order, then its dynamic
// ones, leaving out unset properties and built-in state. only the debug view
// lists a typed property that was never initialized (one whose type forbids
// null; zphp stores a nullable one unset as null, so it reads as null)
pub fn appendOwn(vm: *VM, obj: *PhpObject, purpose: Purpose, listing: *Listing, allocator: std.mem.Allocator) RuntimeError!void {
    if (obj.slot_layout) |layout| if (obj.slots) |slots| {
        for (layout.names, 0..) |name, i| {
            if (i >= slots.len) break;
            // a lazy object's property not yet initialized: the debug view
            // lists a typed one as uninitialized, as php does
            // so is a typed property that was unset
            if (obj.isLazySlot(name, layout.declaring_classes[i]) or obj.isUnset(name)) {
                if (purpose != .debug or isInternalState(vm, obj, name)) continue;
                const declared = vm.propertyDeclaration(layout.declaring_classes[i], name);
                if (declared.type_str.len == 0) continue;
                try listing.items.append(allocator, .{ .key = .{ .name = name }, .value = .null, .visibility = declared.visibility, .declaring = declared.defining_class, .declared = true, .uninitialized = try vm.propertyTypeText(declared.type_str, declared.defining_class) });
                continue;
            }
            if (obj.isUnset(name) or isInternalState(vm, obj, name)) continue;
            const declared = vm.propertyDeclaration(layout.declaring_classes[i], name);
            const uninitialized = slots[i] == .undef or (slots[i] == .null and declared.type_str.len > 0 and vm.typedPropForbidsNull(declared.type_str));
            if (uninitialized and purpose != .debug) continue;
            try listing.items.append(allocator, .{ .key = .{ .name = name }, .value = if (slots[i] == .undef) .null else slots[i], .visibility = declared.visibility, .declaring = declared.defining_class, .declared = true, .uninitialized = if (uninitialized) try vm.propertyTypeText(declared.type_str, declared.defining_class) else null });
        }
    };
    var it = obj.properties.iterator();
    while (it.next()) |entry| {
        const name = entry.key_ptr.*;
        if (isInternalState(vm, obj, name)) continue;
        // beside a slot of the same name (an ancestor's private) the entry is
        // a dynamic property of its own
        if (obj.slot_layout) |layout| if (inSlots(layout, name)) {
            if (!shadowsPrivate(layout, name)) continue;
            try listing.items.append(allocator, .{ .key = .{ .name = name }, .value = entry.value_ptr.*, .declaring = obj.class_name });
            continue;
        };
        // a dynamic property under a mangled name (unserialize keeps the
        // names it reads for properties no class declares) lists as php's
        // table shows it: protected or private to the class it names
        if ((purpose == .debug or purpose == .serialize) and name.len > 0 and name[0] == 0) {
            var prop = unmangle(name, entry.value_ptr.*);
            if (prop.visibility != .public) {
                prop.declared = false;
                try listing.items.append(allocator, prop);
                continue;
            }
        }
        const declared = vm.propertyDeclaration(obj.class_name, name);
        try listing.items.append(allocator, .{ .key = .{ .name = name }, .value = entry.value_ptr.*, .visibility = declared.visibility, .declaring = declared.defining_class });
    }
}

// the object's own properties as an array with (array)'s mangled keys, for a
// class hook to extend
pub fn ownTable(vm: *VM, obj: *PhpObject) RuntimeError!*PhpArray {
    const arr = try vm.allocArray();
    var listing: Listing = .{};
    defer listing.deinit(vm.allocator);
    try appendOwn(vm, obj, .debug, &listing, vm.allocator);
    for (listing.items.items) |p| try setMangled(vm, arr, p.key.name, p.visibility, p.declaring, p.value);
    return arr;
}

// a property in a hook's table under its mangled name
pub fn setMangled(vm: *VM, arr: *PhpArray, name: []const u8, visibility: ClassDef.Visibility, declaring: []const u8, value: Value) RuntimeError!void {
    const key = switch (visibility) {
        .public => try vm.allocator.dupe(u8, name),
        .protected => try std.fmt.allocPrint(vm.allocator, "\x00*\x00{s}", .{name}),
        .private => try std.fmt.allocPrint(vm.allocator, "\x00{s}\x00{s}", .{ declaring, name }),
    };
    defer vm.allocator.free(key);
    try arr.setCopiedKey(vm.allocator, key, value);
}

fn unmangle(key: []const u8, value: Value) Property {
    if (key.len > 0 and key[0] == 0) {
        // an anonymous class's name holds a NUL of its own; the name follows the last
        if (std.mem.lastIndexOfScalar(u8, key[1..], 0)) |last| {
            const end = last + 1;
            const class = key[1..end];
            const name = key[end + 1 ..];
            if (std.mem.eql(u8, class, "*")) return .{ .key = .{ .name = name }, .value = value, .visibility = .protected };
            return .{ .key = .{ .name = name }, .value = value, .visibility = .private, .declaring = class };
        }
    }
    return .{ .key = .{ .name = key }, .value = value };
}

// every slot of the name is some class's private, so a property stored by
// name beside them is a separate one
fn shadowsPrivate(layout: *const PhpObject.SlotLayout, name: []const u8) bool {
    for (layout.names, 0..) |slot_name, i| {
        if (std.mem.eql(u8, slot_name, name) and !layout.is_private[i]) return false;
    }
    return true;
}

fn inSlots(layout: *const PhpObject.SlotLayout, name: []const u8) bool {
    for (layout.names) |slot_name| if (std.mem.eql(u8, slot_name, name)) return true;
    return false;
}

// a property zphp keeps a built-in class's state in: named "__x", on an
// object of a built-in class, and declared by no user class
pub fn isInternalState(vm: *VM, obj: *const PhpObject, name: []const u8) bool {
    if (name.len < 2 or name[0] != '_' or name[1] != '_') return false;
    var built_in = false;
    var current: ?[]const u8 = obj.class_name;
    while (current) |cn| {
        const def = vm.classes.get(cn) orelse break;
        if (def.is_internal) {
            built_in = true;
        } else {
            for (def.properties.items) |prop| if (std.mem.eql(u8, prop.name, name)) return false;
        }
        current = def.parent;
    }
    // stdClass and the incomplete class hold only what the script put there
    return built_in and !std.mem.eql(u8, obj.class_name, "stdClass") and !std.mem.eql(u8, obj.class_name, "__PHP_Incomplete_Class");
}
