const std = @import("std");

// the VM installs this so container stores can release the value they
// replace without knowing the VM: overwrite-release at the store choke point
pub const ReleaseHook = struct { ctx: *anyopaque, call: *const fn (*anyopaque, Value) void };
pub const RefCell = struct {
    value: Value = .null,
    binders: u32 = 0,
    scratch: i32 = 0,
    dead: bool = false,
    visited: bool = false,
};
pub fn cellOf(value: *Value) *RefCell {
    return @fieldParentPtr("value", value);
}
pub const CellUnbindHook = struct { ctx: *anyopaque, call: *const fn (*anyopaque, *Value) void };
pub threadlocal var cell_unbind_hook: ?CellUnbindHook = null;
fn unbindCell(value: *Value) void {
    if (cell_unbind_hook) |hook| hook.call(hook.ctx, value);
}

pub threadlocal var release_hook: ?ReleaseHook = null;

pub threadlocal var trace_obj: ?*PhpObject = null;
pub threadlocal var trace_rc_verbose: bool = false;

// ZPHP_TRACE_OBJ_CLASS: stack trace at every retain/release of one object
pub fn traceObjRc(obj: *PhpObject, what: []const u8) void {
    if (@import("builtin").mode != .Debug) return;
    if (trace_obj != obj or !trace_rc_verbose) return;
    std.debug.print("== trace {s} {s}#{d} refcount now {d}\n", .{ what, obj.class_name, obj.id, obj.refcount });
    std.debug.dumpCurrentStackTrace(null);
}

fn releaseReplaced(old: Value) void {
    if (release_hook) |hook| hook.call(hook.ctx, old);
}

fn retainStored(value: Value) void {
    switch (value) {
        .string => |str| str.retain(),
        .object => |o| o.retain(),
        .array => |a| a.retain(),
        .generator => |g| g.retain(),
        .fiber => |f| f.retain(),
        else => {},
    }
}

pub const PhpArray = struct {
    entries: std.ArrayListUnmanaged(Entry) = .{},
    string_index: std.StringHashMapUnmanaged(usize) = .{},
    next_int_key: i64 = 0,
    has_int_keys: bool = false,
    cursor: usize = 0,
    // refcounting Stage 2 (array-element release): counts every live
    // reference to this array. born at 0. at 0 the array is unreachable and
    // its object elements are released so their __destruct fires promptly.
    // transient scratch field for the cycle collector's trial-decrement
    // pass. only valid while the collector holds the GC lock; otherwise its
    // value is meaningless. signed so the trial decrement can go negative
    // briefly without underflowing
    scratch_rc: i32 = 0,
    // elements_released guards against double-release / cyclic arrays
    refcount: u32 = 0,
    elements_released: bool = false,
    pooled: bool = false,
    cycle_queued: bool = false,
    release_queued: bool = false,
    // a weak container (WeakMap key list): its entries hold no reference to
    // the objects they name, so freeing it releases nothing and the cycle
    // collector ignores its edges
    weak: bool = false,
    // liveness pins taken by natives that hold this array by reference
    // (array_walk, sort): counted in refcount but not a value copy, so a
    // write through the reference set must not separate because of them
    byref_pins: u8 = 0,

    pub const Entry = struct {
        key: Key,
        value: Value,
        // when non-null this element IS a php reference: ref points at the
        // shared *Value cell and `value` is ignored (held .null). readers
        // deref through ref, writers write the cell. defaulted so the ~645
        // existing `.{ .key, .value }` initializers stay non-breaking
        ref: ?*Value = null,
    };

    pub const Key = union(enum) {
        int: i64,
        string: PhpString,

        pub fn eql(a: Key, b: Key) bool {
            if (@intFromEnum(a) != @intFromEnum(b)) return false;
            return switch (a) {
                .int => |ai| ai == b.int,
                .string => |as_| std.mem.eql(u8, as_.bytes(), b.string.bytes()),
            };
        }
    };

    // PHP coerces array string keys that look like canonical decimal integers
    // (no leading zeros, no plus, no whitespace, fits in i64) to int keys at
    // both write and read time. This matches PHP's behavior so $arr['3'] and
    // $arr[3] address the same slot.
    pub fn normalizeKey(key: Key) Key {
        if (key != .string) return key;
        const s = key.string.bytes();
        if (s.len == 0) return key;
        var i: usize = 0;
        if (s[0] == '-') {
            if (s.len == 1) return key;
            i = 1;
        }
        if (i >= s.len) return key;
        if (s[i] == '0') {
            if (s.len - i != 1) return key;
        } else if (s[i] < '1' or s[i] > '9') {
            return key;
        }
        var j: usize = i + 1;
        while (j < s.len) : (j += 1) {
            if (s[j] < '0' or s[j] > '9') return key;
        }
        const v = std.fmt.parseInt(i64, s, 10) catch return key;
        return .{ .int = v };
    }

    pub fn deinit(self: *PhpArray, allocator: std.mem.Allocator) void {
        for (self.entries.items) |entry| {
            if (entry.key == .string) entry.key.string.release();
        }
        self.entries.deinit(allocator);
        self.string_index.deinit(allocator);
    }

    // increment the refcount (Stage 2). a method on PhpArray so value.zig
    // can refcount array elements without importing the VM
    pub fn retain(self: *PhpArray) void {
        self.refcount +%= 1;
    }

    pub fn append(self: *PhpArray, allocator: std.mem.Allocator, value: Value) !void {
        // a store choke point: the new element takes a reference (callers
        // pass raw values, never copyValue'd ones); weak containers count nothing
        const k = if (self.has_int_keys) self.next_int_key else 0;
        if (self.has_int_keys and k == std.math.maxInt(i64)) {
            for (self.entries.items) |entry| {
                if (entry.key == .int and entry.key.int == k) return;
            }
        }
        try self.entries.ensureUnusedCapacity(allocator, 1);
        if (!self.weak) retainStored(value);
        self.entries.appendAssumeCapacity(.{ .key = .{ .int = k }, .value = value });
        self.next_int_key = if (k == std.math.maxInt(i64)) k else k + 1;
        self.has_int_keys = true;
    }

    pub fn set(self: *PhpArray, allocator: std.mem.Allocator, raw_key: Key, value: Value) !void {
        // a store choke point: the element takes a new reference to the
        // value (callers pass raw values, never copyValue'd ones) and the
        // element it replaces is released through the VM's release hook.
        // weak containers ($GLOBALS view, WeakMap keys) count nothing
        const key = normalizeKey(raw_key);
        if (key == .int) {
            const idx = key.int;
            if (idx >= 0) {
                const uidx: usize = @intCast(idx);
                if (uidx < self.entries.items.len) {
                    const entry = &self.entries.items[uidx];
                    if (entry.key == .int and entry.key.int == idx) {
                        if (!self.weak) retainStored(value);
                        const old = entry.value;
                        entry.value = value;
                        const next = if (idx == std.math.maxInt(i64)) idx else idx + 1;
                        self.next_int_key = if (self.has_int_keys) @max(self.next_int_key, next) else next;
                        self.has_int_keys = true;
                        if (!self.weak) releaseReplaced(old);
                        return;
                    }
                }
            }
        }
        if (key == .string) {
            if (self.string_index.get(key.string.bytes())) |idx| {
                if (!self.weak) retainStored(value);
                const old = self.entries.items[idx].value;
                self.entries.items[idx].value = value;
                if (!self.weak) releaseReplaced(old);
                return;
            }
        } else {
            for (self.entries.items) |*entry| {
                if (entry.key.eql(key)) {
                    if (!self.weak) retainStored(value);
                    const old = entry.value;
                    entry.value = value;
                    if (!self.weak) releaseReplaced(old);
                    return;
                }
            }
        }
        const new_idx = self.entries.items.len;
        // Capacity may grow on failure, but entries, index contents, key
        // progression and ownership remain unchanged until both reserves succeed.
        try self.entries.ensureUnusedCapacity(allocator, 1);
        if (key == .string) try self.string_index.ensureUnusedCapacity(allocator, 1);
        if (!self.weak) retainStored(value);
        if (key == .string) key.string.retain();
        self.entries.appendAssumeCapacity(.{ .key = key, .value = value });
        if (key == .int) {
            const next = if (key.int == std.math.maxInt(i64)) key.int else key.int + 1;
            self.next_int_key = if (self.has_int_keys) @max(self.next_int_key, next) else next;
            self.has_int_keys = true;
        } else if (key == .string) {
            self.string_index.putAssumeCapacity(key.string.bytes(), new_idx);
        }
    }

    pub fn contains(self: *const PhpArray, raw_key: Key) bool {
        const key = normalizeKey(raw_key);
        if (key == .string) return self.string_index.contains(key.string.bytes());
        if (key == .int) {
            // mirror get()'s O(1) fast path for sequential dense int keys
            const idx = key.int;
            if (idx >= 0) {
                const uidx: usize = @intCast(idx);
                if (uidx < self.entries.items.len) {
                    const entry = &self.entries.items[uidx];
                    if (entry.key == .int and entry.key.int == idx) return true;
                }
            }
        }
        for (self.entries.items) |e| if (e.key.eql(key)) return true;
        return false;
    }

    pub fn get(self: *const PhpArray, raw_key: Key) Value {
        const key = normalizeKey(raw_key);
        if (key == .int) {
            const idx = key.int;
            if (idx >= 0) {
                const uidx: usize = @intCast(idx);
                if (uidx < self.entries.items.len) {
                    const entry = &self.entries.items[uidx];
                    if (entry.key == .int and entry.key.int == idx) return entry.value;
                }
            }
        }
        if (key == .string) {
            if (self.string_index.get(key.string.bytes())) |idx| {
                return self.entries.items[idx].value;
            }
            return .null;
        }
        for (self.entries.items) |entry| {
            if (entry.key.eql(key)) return entry.value;
        }
        return .null;
    }

    // like get() but returns a mutable pointer to the entry, or null if the
    // key is absent. used to mark an element as a reference (entry.ref)
    pub fn getPtr(self: *PhpArray, raw_key: Key) ?*Entry {
        const key = normalizeKey(raw_key);
        if (key == .int) {
            const idx = key.int;
            if (idx >= 0) {
                const uidx: usize = @intCast(idx);
                if (uidx < self.entries.items.len) {
                    const entry = &self.entries.items[uidx];
                    if (entry.key == .int and entry.key.int == idx) return entry;
                }
            }
        }
        if (key == .string) {
            if (self.string_index.get(key.string.bytes())) |idx| return &self.entries.items[idx];
            return null;
        }
        for (self.entries.items) |*entry| {
            if (entry.key.eql(key)) return entry;
        }
        return null;
    }

    pub fn length(self: *const PhpArray) i64 {
        return @intCast(self.entries.items.len);
    }

    // Build off to the side: a failed rebuild leaves the old index intact.
    // Callers that mutate entries first must instead preflight capacity before
    // mutation and use rebuildStringIndexAssumeCapacity for their commit.
    pub fn rebuildStringIndex(self: *PhpArray, allocator: std.mem.Allocator) !void {
        var index: std.StringHashMapUnmanaged(usize) = .{};
        errdefer index.deinit(allocator);
        for (self.entries.items, 0..) |entry, i| {
            if (entry.key == .string) try index.put(allocator, entry.key.string.bytes(), i);
        }
        self.string_index.deinit(allocator);
        self.string_index = index;
    }

    // Reserve an upper bound on the number of string-keyed entries AFTER the
    // caller's mutation. No entries or index contents change if this fails.
    pub fn reserveStringIndex(self: *PhpArray, allocator: std.mem.Allocator, string_count: usize) !void {
        const count = std.math.cast(u32, string_count) orelse return error.OutOfMemory;
        try self.string_index.ensureTotalCapacity(allocator, count);
    }

    pub fn rebuildStringIndexAssumeCapacity(self: *PhpArray) void {
        self.string_index.clearRetainingCapacity();
        for (self.entries.items, 0..) |entry, i| {
            if (entry.key == .string) self.string_index.putAssumeCapacity(entry.key.string.bytes(), i);
        }
    }

    pub fn remove(self: *PhpArray, key: Key) void {
        var remove_idx: ?usize = null;
        if (key == .string) {
            if (self.string_index.fetchRemove(key.string.bytes())) |kv| {
                remove_idx = kv.value;
            }
        }
        if (remove_idx == null) {
            var i: usize = 0;
            while (i < self.entries.items.len) {
                if (self.entries.items[i].key.eql(key)) {
                    remove_idx = i;
                    break;
                }
                i += 1;
            }
        }
        if (remove_idx) |idx| {
            const removed = self.entries.orderedRemove(idx);
            if (removed.ref) |cell| unbindCell(cell);
            if (removed.key == .string) removed.key.string.release();
            // rebuild string index for shifted entries
            var it = self.string_index.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.* > idx) {
                    entry.value_ptr.* -= 1;
                }
            }
        }
    }
};

const Chunk = @import("../pipeline/bytecode.zig").Chunk;
const ObjFunction = @import("../pipeline/bytecode.zig").ObjFunction;

pub const ArrayRefBinding = struct {
    cell: *Value,
    array: *PhpArray,
    key: PhpArray.Key,
};

pub const ObjectRefBinding = struct {
    cell: *Value,
    object: *PhpObject,
    prop_name: []const u8,
};

pub const StaticPropRefBinding = struct {
    cell: *Value,
    class_name: []const u8,
    prop_name: []const u8,
};

// a destination an lvalue-reference cell mirrors into. the cell pointer is the
// KEY in RefIndex.fwd, so it's not repeated here. propagateCellWrite(cell) looks
// the cell up and writes every target in its list (a cell can mirror several -
// e.g. a referenced array element that survived a `$d = $c` clone binds the
// entry in BOTH arrays)
pub const BindingTarget = union(enum) {
    array: struct { array: *PhpArray, key: PhpArray.Key },
    object: struct { object: *PhpObject, prop_name: []const u8 },
    static: struct { class_name: []const u8, prop_name: []const u8 },
    // a closure's by-reference capture: the capture entry mirrors (and owns
    // a reference to) the cell's value for the closure instance's lifetime
    capture: struct { closure: *PhpString.Owner, var_name: []const u8 },
};

// reverse index key for the prop/static sync direction (a DIRECT write to
// $obj->prop / Class::$s must update any cell bound to it). keyed by the
// storage location, value is the list of cells mirroring it
pub const PropRefKey = struct {
    object: ?*PhpObject, // null for a static prop
    class_name: []const u8, // "" for an instance prop
    prop_name: []const u8,

    pub fn eql(a: PropRefKey, b: PropRefKey) bool {
        return a.object == b.object and
            std.mem.eql(u8, a.class_name, b.class_name) and
            std.mem.eql(u8, a.prop_name, b.prop_name);
    }
    pub fn hash(self: PropRefKey) u64 {
        var h = std.hash.Wyhash.init(0);
        h.update(std.mem.asBytes(&self.object));
        h.update(self.class_name);
        h.update(self.prop_name);
        return h.final();
    }
};

const PropRefKeyContext = struct {
    pub fn hash(_: PropRefKeyContext, k: PropRefKey) u64 {
        return k.hash();
    }
    pub fn eql(_: PropRefKeyContext, a: PropRefKey, b: PropRefKey) bool {
        return a.eql(b);
    }
};

// cell-keyed binding registry. fwd: cell -> targets it mirrors (the O(1)
// propagateCellWrite source). prop_rev: storage location -> cells mirroring it
// (the O(1) syncObjPropRefs/syncStaticPropRefs source). lives behind a pointer
// on the VM so the hot interpreter struct stays a single nullable pointer wider
pub const RefIndex = struct {
    pub const OwnerId = u64;
    pub const OwnedBinding = struct { cell: *Value, target: BindingTarget };

    fwd: std.AutoHashMapUnmanaged(*Value, std.ArrayListUnmanaged(BindingTarget)) = .{},
    prop_rev: std.HashMapUnmanaged(PropRefKey, std.ArrayListUnmanaged(*Value), PropRefKeyContext, 80) = .{},
    by_owner: std.AutoHashMapUnmanaged(OwnerId, std.ArrayListUnmanaged(OwnedBinding)) = .{},
    next_owner: OwnerId = 1,

    pub fn createOwner(self: *RefIndex) OwnerId {
        const owner = self.next_owner;
        self.next_owner += 1;
        return owner;
    }

    pub fn addOwned(self: *RefIndex, a: std.mem.Allocator, owner: OwnerId, cell: *Value, target: BindingTarget) !void {
        std.debug.assert(owner != 0);
        const gop = try self.by_owner.getOrPut(a, owner);
        if (!gop.found_existing) gop.value_ptr.* = .{};
        for (gop.value_ptr.items) |existing| {
            if (existing.cell == cell and targetEql(existing.target, target)) return;
        }
        try gop.value_ptr.append(a, .{ .cell = cell, .target = target });
        try self.addForward(a, cell, target);
        switch (target) {
            .object => |o| try self.addPropRev(a, .{ .object = o.object, .class_name = "", .prop_name = o.prop_name }, cell),
            .static => |s| try self.addPropRev(a, .{ .object = null, .class_name = s.class_name, .prop_name = s.prop_name }, cell),
            .array, .capture => {},
        }
    }

    pub fn releaseOwner(self: *RefIndex, a: std.mem.Allocator, owner: OwnerId) void {
        const removed = self.by_owner.fetchRemove(owner) orelse return;
        var bindings = removed.value;
        for (bindings.items) |binding| {
            if (!self.edgeHasOwner(binding.cell, binding.target)) self.removeTarget(a, binding.cell, binding.target);
        }
        bindings.deinit(a);
    }

    pub fn transferCell(self: *RefIndex, a: std.mem.Allocator, from: OwnerId, to: OwnerId, cell: *Value) !void {
        const source = self.by_owner.getPtr(from) orelse return;
        var moving: std.ArrayListUnmanaged(BindingTarget) = .{};
        defer moving.deinit(a);
        for (source.items) |binding| if (binding.cell == cell) try moving.append(a, binding.target);
        for (moving.items) |target| try self.addOwned(a, to, cell, target);
        const current = self.by_owner.getPtr(from) orelse return;
        var i: usize = 0;
        while (i < current.items.len) {
            if (current.items[i].cell == cell) _ = current.swapRemove(i) else i += 1;
        }
        if (current.items.len == 0) {
            current.deinit(a);
            _ = self.by_owner.remove(from);
        }
    }

    pub fn removeOwnedTarget(self: *RefIndex, a: std.mem.Allocator, owner: OwnerId, cell: *Value, target: BindingTarget) void {
        if (self.by_owner.getPtr(owner)) |list| {
            var i: usize = 0;
            while (i < list.items.len) {
                const binding = list.items[i];
                if (binding.cell == cell and targetEql(binding.target, target)) _ = list.swapRemove(i) else i += 1;
            }
            if (list.items.len == 0) {
                list.deinit(a);
                _ = self.by_owner.remove(owner);
            }
        }
        if (!self.edgeHasOwner(cell, target)) self.removeTarget(a, cell, target);
    }

    pub fn removeTargetAllOwners(self: *RefIndex, a: std.mem.Allocator, cell: *Value, target: BindingTarget) void {
        var empty_owners: std.ArrayListUnmanaged(OwnerId) = .{};
        defer empty_owners.deinit(a);
        var owner_it = self.by_owner.iterator();
        while (owner_it.next()) |entry| {
            var i: usize = 0;
            while (i < entry.value_ptr.items.len) {
                const binding = entry.value_ptr.items[i];
                if (binding.cell == cell and targetEql(binding.target, target)) _ = entry.value_ptr.swapRemove(i) else i += 1;
            }
            if (entry.value_ptr.items.len == 0) empty_owners.append(a, entry.key_ptr.*) catch {};
        }
        for (empty_owners.items) |owner| {
            if (self.by_owner.fetchRemove(owner)) |removed| {
                var list = removed.value;
                list.deinit(a);
            }
        }
        self.removeTarget(a, cell, target);
    }

    pub fn ownerBindings(self: *RefIndex, owner: OwnerId) ?[]const OwnedBinding {
        const list = self.by_owner.getPtr(owner) orelse return null;
        return list.items;
    }

    fn edgeHasOwner(self: *RefIndex, cell: *Value, target: BindingTarget) bool {
        var it = self.by_owner.valueIterator();
        while (it.next()) |list| for (list.items) |binding| {
            if (binding.cell == cell and targetEql(binding.target, target)) return true;
        };
        return false;
    }

    pub fn addForward(self: *RefIndex, a: std.mem.Allocator, cell: *Value, target: BindingTarget) !void {
        const gop = try self.fwd.getOrPut(a, cell);
        if (!gop.found_existing) gop.value_ptr.* = .{};
        for (gop.value_ptr.items) |existing| {
            if (targetEql(existing, target)) return;
        }
        try gop.value_ptr.append(a, target);
        if (target == .object or target == .static) cellOf(cell).binders += 1;
    }

    pub fn addPropRev(self: *RefIndex, a: std.mem.Allocator, key: PropRefKey, cell: *Value) !void {
        const gop = try self.prop_rev.getOrPut(a, key);
        if (!gop.found_existing) gop.value_ptr.* = .{};
        for (gop.value_ptr.items) |existing| {
            if (existing == cell) return;
        }
        try gop.value_ptr.append(a, cell);
    }

    fn targetEql(a: BindingTarget, b: BindingTarget) bool {
        if (@intFromEnum(a) != @intFromEnum(b)) return false;
        return switch (a) {
            .array => |x| x.array == b.array.array and x.key.eql(b.array.key),
            .object => |x| x.object == b.object.object and std.mem.eql(u8, x.prop_name, b.object.prop_name),
            .static => |x| std.mem.eql(u8, x.class_name, b.static.class_name) and std.mem.eql(u8, x.prop_name, b.static.prop_name),
            .capture => |x| x.closure == b.capture.closure and std.mem.eql(u8, x.var_name, b.capture.var_name),
        };
    }

    // remove ONE specific target from a cell's forward list (frame teardown of a
    // single binding, unset of one element). a cell can have several targets - a
    // referenced element that survived `$d = $c` binds the entry in BOTH arrays -
    // so this removes only the matching one, leaving the others (e.g. the clone's
    // array-lifetime binding survives the binding frame). also scrubs prop_rev
    pub fn removeTarget(self: *RefIndex, a: std.mem.Allocator, cell: *Value, target: BindingTarget) void {
        var removed = false;
        if (self.fwd.getPtr(cell)) |list| {
            var i: usize = 0;
            while (i < list.items.len) {
                if (targetEql(list.items[i], target)) {
                    _ = list.swapRemove(i);
                    removed = true;
                } else i += 1;
            }
            if (list.items.len == 0) {
                list.deinit(a);
                _ = self.fwd.remove(cell);
            }
        }
        switch (target) {
            .object => |o| self.removePropRevCell(a, .{ .object = o.object, .class_name = "", .prop_name = o.prop_name }, cell),
            .static => |s| self.removePropRevCell(a, .{ .object = null, .class_name = s.class_name, .prop_name = s.prop_name }, cell),
            .array, .capture => {},
        }
        if (removed and (target == .object or target == .static)) unbindCell(cell);
    }

    // drop every target/cell associated with this cell (frame teardown, unset,
    // generator suspend). O(targets-for-this-cell), never a global scan
    pub fn removeCell(self: *RefIndex, a: std.mem.Allocator, cell: *Value) void {
        var owners = self.by_owner.iterator();
        var empty_owners: std.ArrayListUnmanaged(OwnerId) = .{};
        defer empty_owners.deinit(a);
        while (owners.next()) |entry| {
            var i: usize = 0;
            while (i < entry.value_ptr.items.len) {
                if (entry.value_ptr.items[i].cell == cell) {
                    _ = entry.value_ptr.swapRemove(i);
                } else {
                    i += 1;
                }
            }
            if (entry.value_ptr.items.len == 0) empty_owners.append(a, entry.key_ptr.*) catch {};
        }
        for (empty_owners.items) |owner| {
            if (self.by_owner.fetchRemove(owner)) |removed| {
                var list = removed.value;
                list.deinit(a);
            }
        }
        if (self.fwd.fetchRemove(cell)) |kv| {
            var list = kv.value;
            // also scrub this cell from any prop_rev lists it appears in
            for (list.items) |t| {
                switch (t) {
                    .object => |o| self.removePropRevCell(a, .{ .object = o.object, .class_name = "", .prop_name = o.prop_name }, cell),
                    .static => |s| self.removePropRevCell(a, .{ .object = null, .class_name = s.class_name, .prop_name = s.prop_name }, cell),
                    .array, .capture => {},
                }
            }
            list.deinit(a);
        }
    }

    fn removePropRevCell(self: *RefIndex, a: std.mem.Allocator, key: PropRefKey, cell: *Value) void {
        if (self.prop_rev.getPtr(key)) |list| {
            var i: usize = 0;
            while (i < list.items.len) {
                if (list.items[i] == cell) {
                    _ = list.swapRemove(i);
                } else i += 1;
            }
            if (list.items.len == 0) {
                list.deinit(a);
                _ = self.prop_rev.remove(key);
            }
        }
    }

    pub fn clear(self: *RefIndex, a: std.mem.Allocator) void {
        var owners = self.by_owner.valueIterator();
        while (owners.next()) |list| list.deinit(a);
        self.by_owner.clearRetainingCapacity();
        var it = self.fwd.valueIterator();
        while (it.next()) |list| list.deinit(a);
        self.fwd.clearRetainingCapacity();
        var it2 = self.prop_rev.valueIterator();
        while (it2.next()) |list| list.deinit(a);
        self.prop_rev.clearRetainingCapacity();
    }

    pub fn deinit(self: *RefIndex, a: std.mem.Allocator) void {
        self.clear(a);
        self.fwd.deinit(a);
        self.prop_rev.deinit(a);
        self.by_owner.deinit(a);
    }
};

pub const Generator = struct {
    // refcount Stage 2: every live Value handle bumps this. 0 means
    // unreachable; the VM runs closeGenerator + releases gen.vars at that
    // point. starts at 0; new_gen op + push retain to 1
    refcount: u32 = 0,
    state: State = .created,
    func: *const ObjFunction,
    ip: usize = 0,
    vars: std.StringHashMapUnmanaged(Value) = .{},
    locals: std.ArrayListUnmanaged(Value) = .{},
    stack: std.ArrayListUnmanaged(Value) = .{},
    ref_slots: std.StringHashMapUnmanaged(*Value) = .{},
    base_sp: usize = 0,
    current_value: Value = .null,
    current_key: Value = .null,
    return_value: Value = .null,
    implicit_key: i64 = 0,
    handler_count: usize = 0,
    saved_handlers: [8]SavedHandler = undefined,
    delegate: ?DelegateState = null,
    pending_throw: ?Value = null,
    pooled: bool = false,

    pub const SavedHandler = struct {
        catch_ip: usize,
        sp_offset: usize,
        chunk: *const Chunk,
    };

    pub const DelegateState = union(enum) {
        gen: *Generator,
        array: struct { arr: *PhpArray, index: usize },
    };

    pub const State = enum { created, suspended, running, completed };

    pub fn deinit(self: *Generator, allocator: std.mem.Allocator) void {
        self.vars.deinit(allocator);
        self.locals.deinit(allocator);
        self.stack.deinit(allocator);
        var refs = self.ref_slots;
        self.ref_slots = .{};
        var rit = refs.valueIterator();
        while (rit.next()) |cell| unbindCell(cell.*);
        refs.deinit(allocator);
    }

    pub fn retain(self: *Generator) void {
        self.refcount +%= 1;
    }
};

pub const Fiber = struct {
    // refcount Stage 2: every live Value handle bumps this. 0 means
    // unreachable; the VM runs cleanupFiberFrames + drops saved state at
    // that point. starts at 0; new_fiber + push retain to 1
    refcount: u32 = 0,
    state: State = .created,
    callable: Value = .null,

    saved_frames: std.ArrayListUnmanaged(SavedFrame) = .{},
    saved_stack: std.ArrayListUnmanaged(Value) = .{},
    saved_handlers: std.ArrayListUnmanaged(SavedHandler) = .{},

    suspend_value: Value = .null,
    return_value: Value = .null,
    pooled: bool = false,

    pub const State = enum { created, running, suspended, terminated };

    pub const SavedFrame = struct {
        chunk: *const Chunk,
        ip: usize,
        vars: std.StringHashMapUnmanaged(Value),
        locals: []Value = &.{},
        func: ?*const ObjFunction = null,
        called_class: ?[]const u8 = null,
        generator: ?*Generator = null,
        ref_slots: std.StringHashMapUnmanaged(*Value),
        ref_owner: RefIndex.OwnerId = 0,
        call_name: ?[]const u8 = null,
    };

    pub const SavedHandler = struct {
        catch_ip: usize,
        frame_count_offset: usize,
        sp_offset: usize,
        chunk: *const Chunk,
    };

    pub fn deinit(self: *Fiber, allocator: std.mem.Allocator) void {
        for (self.saved_frames.items) |*f| {
            f.vars.deinit(allocator);
            var refs = f.ref_slots;
            f.ref_slots = .{};
            var rit = refs.valueIterator();
            while (rit.next()) |cell| unbindCell(cell.*);
            refs.deinit(allocator);
            if (f.locals.len > 0) allocator.free(f.locals);
        }
        self.saved_frames.deinit(allocator);
        self.saved_stack.deinit(allocator);
        self.saved_handlers.deinit(allocator);
    }

    pub fn retain(self: *Fiber) void {
        self.refcount +%= 1;
    }
};

pub const PhpObject = struct {
    class_name: []const u8,
    properties: std.StringArrayHashMapUnmanaged(Value) = .{},
    slots: ?[]Value = null,
    slot_layout: ?*SlotLayout = null,
    // tracks which named properties have been explicitly unset by user code.
    // a slot can hold a default value of `.null` AND be considered "present"
    // (no __get triggered), so we need a side-channel to distinguish "unset"
    // from "null". needed by PHP's lazy-init via `unset($this->x); ... $this->x`
    // pattern that triggers __get
    unset_slots: std.StringHashMapUnmanaged(void) = .{},
    // PHP's __set recursion guard. when __set is invoked for prop X on this
    // object, writes to X from inside __set skip __set and write directly,
    // matching PHP's behavior where the first write inside __set establishes
    // a dynamic property and stops re-entry
    magic_set_active: std.StringHashMapUnmanaged(void) = .{},
    magic_get_active: std.StringHashMapUnmanaged(void) = .{},
    lazy: ?*LazyState = null,

    id: u32 = 0,
    // object refcounting (Stage 1). counts live references to this object,
    // including operand-stack slots. born at 0: the `new` opcode pushes the
    // result and `push` retains it to 1. every push retains, every pop/drop
    // releases, copyValue retains durable copies. when the count reaches 0 the
    // object is unreachable and __destruct runs. memory itself stays
    // arena-owned and is reclaimed in bulk at request end; the refcount only
    // governs destructor timing.
    refcount: u32 = 0,
    // transient scratch field for the cycle collector's trial-decrement pass
    scratch_rc: i32 = 0,
    // set once __destruct has run, so it never runs twice (refcount-zero path
    // and the end-of-request safety sweep must not double-fire it)
    destructed: bool = false,
    pooled: bool = false,
    cycle_queued: bool = false,
    // a reference cell has targeted one of this object's properties; the
    // release path must detach those weak mirrors before the address is reused
    ref_mirrored: bool = false,
    // a native handle owned by an extension resource: the pointer and the
    // registered type id live here, not in properties, so php code cannot
    // read or forge them
    native_ptr: usize = 0,
    native_kind: u32 = 0,

    pub const LazyState = struct {
        initializer: Value,
        proxy: bool = false,
        backing: ?*PhpObject = null,
        pending: []bool,
        skip_serialize: bool = false,
        running: bool = false,
    };

    pub fn backingValue(self: *const PhpObject) Value {
        if (self.lazy) |state| if (state.backing) |obj| return .{ .object = obj };
        return .null;
    }

    pub fn storage(self: *PhpObject) *PhpObject {
        if (self.lazy) |state| if (state.backing) |obj| return obj;
        return self;
    }

    pub fn ownsDestructor(self: *const PhpObject) bool {
        return self.lazyInitializer() == .null and self.backingValue() == .null;
    }

    pub fn lazyInitializer(self: *const PhpObject) Value {
        const state = self.lazy orelse return .null;
        return state.initializer;
    }

    pub fn isLazySlot(self: *const PhpObject, name: []const u8, scope: ?[]const u8) bool {
        const state = self.lazy orelse return false;
        if (state.running or state.initializer == .null) return false;
        const index = self.getSlotIndexForScope(name, scope) orelse return state.proxy;
        return state.pending[index];
    }
    pub const SlotLayout = struct {
        names: []const []const u8,
        // mutable: set_prop_default patches an instance-property default after
        // class_decl (when a `self::CONST` default finally resolves)
        defaults: []Value,
        // PHP keeps each declaring class's private property in its own
        // storage slot - parent's `private $foo` and child's `private $foo`
        // are NOT the same slot. these parallel arrays let getSlotIndex
        // distinguish: for is_private[i]==true entries, match (name AND
        // declaring_classes[i]==scope). public/protected slots ignore scope
        declaring_classes: []const []const u8,
        is_private: []const bool,
    };

    pub fn deinit(self: *PhpObject, allocator: std.mem.Allocator) void {
        if (self.lazy) |state| {
            allocator.free(state.pending);
            allocator.destroy(state);
        }
        self.properties.deinit(allocator);
        self.unset_slots.deinit(allocator);
        self.magic_set_active.deinit(allocator);
        self.magic_get_active.deinit(allocator);
        if (self.slots) |s| allocator.free(s);
    }

    // increment the refcount (Stage 1). a method on PhpObject so value.zig
    // (PhpArray) can refcount object elements without importing the VM
    pub fn retain(self: *PhpObject) void {
        self.refcount +%= 1;
        traceObjRc(self, "retain");
    }

    pub fn isUnset(self: *const PhpObject, name: []const u8) bool {
        if (self.backingValue() == .object) return self.backingValue().object.isUnset(name);
        return self.unset_slots.contains(name);
    }

    pub fn markUnset(self: *PhpObject, allocator: std.mem.Allocator, name: []const u8) !void {
        try self.unset_slots.put(allocator, name, {});
    }

    pub fn clearUnset(self: *PhpObject, name: []const u8) void {
        _ = self.unset_slots.remove(name);
    }

    pub fn getSlotIndex(self: *const PhpObject, name: []const u8) ?u16 {
        return self.getSlotIndexForScope(name, null);
    }

    // private props from different declaring classes are separate slots.
    // pass scope = the class doing the access (e.g. the current method's
    // class) so the right private slot is picked. scope == null falls back
    // to the FIRST matching slot (legacy callers, public access from
    // outside, native code without scope context)
    pub fn getSlotIndexForScope(self: *const PhpObject, name: []const u8, scope: ?[]const u8) ?u16 {
        const layout = self.slot_layout orelse return null;
        // first pass: exact match with scope-restricted privates
        for (layout.names, 0..) |n, i| {
            if (!(n.ptr == name.ptr or std.mem.eql(u8, n, name))) continue;
            if (layout.is_private[i]) {
                if (scope) |sc| {
                    if (std.mem.eql(u8, sc, layout.declaring_classes[i])) return @intCast(i);
                }
                continue; // private slot but scope doesn't match - skip
            }
            return @intCast(i);
        }
        // second pass: scope didn't match any private, fall back to first
        // matching private (e.g. natives, reflection-like access from
        // outside a class hierarchy)
        if (scope == null) {
            for (layout.names, 0..) |n, i| {
                if (n.ptr == name.ptr or std.mem.eql(u8, n, name)) return @intCast(i);
            }
        }
        return null;
    }

    pub fn get(self: *const PhpObject, name: []const u8) Value {
        return self.getForScope(name, null);
    }

    pub fn getForScope(self: *const PhpObject, name: []const u8, scope: ?[]const u8) Value {
        if (self.backingValue() == .object) return self.backingValue().object.getForScope(name, scope);
        if (self.slots) |s| {
            if (self.getSlotIndexForScope(name, scope)) |idx| return s[idx];
        }
        return self.properties.get(name) orelse .null;
    }

    pub fn set(self: *PhpObject, allocator: std.mem.Allocator, name: []const u8, value: Value) !void {
        if (self.storage() != self) return self.storage().set(allocator, name, value);
        // the universal property-store choke point: the property takes a
        // reference to the value (callers pass raw values, never copyValue'd
        // ones) and the value it replaces is released through the VM's hook
        retainStored(value);
        // a write resurrects a previously-unset property
        self.clearUnset(name);
        if (self.slots) |s| {
            if (self.getSlotIndex(name)) |idx| {
                const old = s[idx];
                s[idx] = value;
                releaseReplaced(old);
                return;
            }
        }
        const gop = try self.properties.getOrPut(allocator, name);
        if (gop.found_existing) {
            const old = gop.value_ptr.*;
            gop.value_ptr.* = value;
            releaseReplaced(old);
        } else {
            gop.value_ptr.* = value;
        }
    }

    // scope-aware variant for the set_prop opcode path where we know the
    // declaring class (private slots are picked correctly)
    pub fn setForScope(self: *PhpObject, allocator: std.mem.Allocator, name: []const u8, value: Value, scope: ?[]const u8) !void {
        if (self.storage() != self) return self.storage().setForScope(allocator, name, value, scope);
        retainStored(value);
        self.clearUnset(name);
        if (self.slots) |s| {
            if (self.getSlotIndexForScope(name, scope)) |idx| {
                const old = s[idx];
                s[idx] = value;
                releaseReplaced(old);
                return;
            }
        }
        const gop = try self.properties.getOrPut(allocator, name);
        if (gop.found_existing) {
            const old = gop.value_ptr.*;
            gop.value_ptr.* = value;
            releaseReplaced(old);
        } else {
            gop.value_ptr.* = value;
        }
    }
};

pub const PhpString = struct {
    ptr: [*]const u8,
    len: usize,
    owner: ?*Owner = null,

    pub const Owner = struct {
        bytes: []u8,
        allocator: std.mem.Allocator,
        refcount: u32 = 1,
        release_queued: bool = false,
        // a closure instance name: the bytes live in the VM's recycled name
        // arena and the VM releases the instance's captures when the last
        // reference drops, so the owner struct is the closure's identity
        closure: bool = false,
    };

    pub fn borrowed(value: []const u8) PhpString {
        return .{ .ptr = value.ptr, .len = value.len };
    }

    pub fn create(allocator: std.mem.Allocator, value: []const u8) !PhpString {
        return adopt(allocator, try allocator.dupe(u8, value));
    }

    pub fn adopt(allocator: std.mem.Allocator, value: []u8) !PhpString {
        errdefer allocator.free(value);
        const owner = try allocator.create(Owner);
        owner.* = .{ .bytes = value, .allocator = allocator };
        return .{ .ptr = value.ptr, .len = value.len, .owner = owner };
    }

    pub fn bytes(self: PhpString) []const u8 {
        return self.ptr[0..self.len];
    }

    pub fn format(self: PhpString, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll(self.bytes());
    }

    pub fn borrowedSlice(self: PhpString, start: usize, end: usize) PhpString {
        return .{ .ptr = self.ptr + start, .len = end - start, .owner = self.owner };
    }

    pub fn retainedSlice(self: PhpString, start: usize, end: usize) PhpString {
        self.retain();
        return self.borrowedSlice(start, end);
    }

    pub fn retain(self: PhpString) void {
        if (self.owner) |owner| owner.refcount += 1;
    }

    pub fn release(self: PhpString) void {
        const owner = self.owner orelse return;
        std.debug.assert(owner.refcount > 0);
        owner.refcount -= 1;
        if (owner.refcount == 0 and !owner.release_queued and !owner.closure) destroyOwner(owner);
    }

    pub fn releaseDeferred(self: PhpString) ?*Owner {
        const owner = self.owner orelse return null;
        std.debug.assert(owner.refcount > 0);
        owner.refcount -= 1;
        return if (owner.refcount == 0) owner else null;
    }

    pub fn destroyOwner(owner: *Owner) void {
        const allocator = owner.allocator;
        if (!owner.closure) allocator.free(owner.bytes);
        allocator.destroy(owner);
    }
};

pub const Value = union(enum) {
    pub const String = PhpString;

    null,
    bool: bool,
    int: i64,
    float: f64,
    string: PhpString,
    array: *PhpArray,
    object: *PhpObject,
    generator: *Generator,
    fiber: *Fiber,

    // sentinel for "default = []" in function params - fillDefaults creates a fresh empty array
    var empty_array_sentinel: PhpArray = .{};
    pub const empty_array_default: Value = .{ .array = &empty_array_sentinel };

    pub fn isEmptyArrayDefault(self: Value) bool {
        return self == .array and self.array == &empty_array_sentinel;
    }

    pub fn isTruthy(self: Value) bool {
        return switch (self) {
            .null => false,
            .bool => |b| b,
            .int => |i| i != 0,
            .float => |f| f != 0.0,
            .string => |s| s.len > 0 and !std.mem.eql(u8, s.bytes(), "0"),
            .array => |a| a.entries.items.len > 0,
            .object, .generator, .fiber => true,
        };
    }

    pub fn isNull(self: Value) bool {
        return self == .null;
    }

    pub fn add(a: Value, b: Value) Value {
        return numericBinOp(a, b, .add);
    }

    pub fn subtract(a: Value, b: Value) Value {
        return numericBinOp(a, b, .sub);
    }

    pub fn multiply(a: Value, b: Value) Value {
        return numericBinOp(a, b, .mul);
    }

    pub fn divide(a: Value, b: Value) Value {
        const bv = toFloat(b);
        if (bv == 0.0) {
            const av = toFloat(a);
            if (av == 0.0) return .{ .float = std.math.nan(f64) };
            return .{ .float = if (av > 0.0) std.math.inf(f64) else -std.math.inf(f64) };
        }
        const both_int = (a == .int or (a == .string and isNumericIntString(a.string.bytes()))) and
            (b == .int or (b == .string and isNumericIntString(b.string.bytes())));
        // both-int path: check exact divisibility in integer space so we don't
        // lose precision routing through f64 (PHP_INT_MAX is exactly divisible
        // by 7 but float div rounds the quotient down). PHP_INT_MIN / -1 stays
        // a float since the integer quotient overflows
        if (both_int) {
            const ai = toInt(a);
            const bi = toInt(b);
            if (bi != 0 and !(ai == std.math.minInt(i64) and bi == -1)) {
                if (@rem(ai, bi) == 0) return .{ .int = @divTrunc(ai, bi) };
            }
        }
        return .{ .float = toFloat(a) / bv };
    }

    fn isNumericIntString(s: []const u8) bool {
        if (s.len == 0) return false;
        var i: usize = 0;
        if (s[0] == '+' or s[0] == '-') i = 1;
        if (i >= s.len) return false;
        while (i < s.len) : (i += 1) {
            if (s[i] < '0' or s[i] > '9') return false;
        }
        return true;
    }

    pub fn modulo(a: Value, b: Value) Value {
        const bi = toInt(b);
        if (bi == 0) return .{ .float = std.math.nan(f64) };
        return .{ .int = @rem(toInt(a), bi) };
    }

    pub fn power(a: Value, b: Value) Value {
        // when both operands are int and exponent is non-negative, prefer int
        // result if it fits in i64; matches PHP's behavior
        if (a == .int and b == .int and b.int >= 0) {
            const exp_u: u64 = @intCast(b.int);
            var result: i64 = 1;
            var base: i64 = a.int;
            var e = exp_u;
            var overflowed = false;
            while (e > 0 and !overflowed) : (e >>= 1) {
                if ((e & 1) == 1) {
                    const r = @mulWithOverflow(result, base);
                    if (r[1] != 0) {
                        overflowed = true;
                        break;
                    }
                    result = r[0];
                }
                if (e > 1) {
                    const r = @mulWithOverflow(base, base);
                    if (r[1] != 0) {
                        overflowed = true;
                        break;
                    }
                    base = r[0];
                }
            }
            if (!overflowed) return .{ .int = result };
        }
        return .{ .float = std.math.pow(f64, toFloat(a), toFloat(b)) };
    }

    pub fn negate(self: Value) Value {
        return switch (self) {
            .int => |i| if (i == std.math.minInt(i64))
                .{ .float = -@as(f64, @floatFromInt(i)) }
            else
                .{ .int = -i },
            .float => |f| .{ .float = -f },
            else => .{ .int = -toInt(self) },
        };
    }

    fn arrayEqual(a: *PhpArray, b: *PhpArray, strict: bool) bool {
        if (a == b) return true;
        if (a.entries.items.len != b.entries.items.len) return false;
        if (strict) {
            // strict: same key/value pairs in the same order
            for (a.entries.items, b.entries.items) |ea, eb| {
                if (!ea.key.eql(eb.key)) return false;
                if (!identical(ea.value, eb.value)) return false;
            }
            return true;
        }
        // loose: same key/value pairs regardless of order
        for (a.entries.items) |ea| {
            const bv = b.get(ea.key);
            if (bv == .null and equal(ea.value, .null)) {
                // null may legitimately equal a missing entry; need explicit presence check
                if (!hasKey(b, ea.key)) return false;
            }
            if (!equal(ea.value, bv)) return false;
        }
        return true;
    }

    fn hasKey(arr: *PhpArray, key: PhpArray.Key) bool {
        if (key == .string) return arr.string_index.contains(key.string.bytes());
        for (arr.entries.items) |e| if (e.key.eql(key)) return true;
        return false;
    }

    pub fn equal(a: Value, b: Value) bool {
        if (a == .object and b == .object) {
            if (a.object == b.object) return true;
            if (!std.mem.eql(u8, a.object.class_name, b.object.class_name)) return false;
            return objectsCompare(a.object, b.object) == 0;
        }
        if (a == .object or b == .object or a == .fiber or b == .fiber) return false;
        if (a == .array and b == .array) return arrayEqual(a.array, b.array, false);
        if (a == .array or b == .array) {
            const arr_side = if (a == .array) a else b;
            const other = if (a == .array) b else a;
            if (other == .null) return arr_side.array.length() == 0;
            if (other == .bool) return arr_side.isTruthy() == other.bool;
            return false;
        }
        if (a == .null and b == .null) return true;
        // php 8: null compared to string converts null to "" and does string comparison
        if (a == .null and b == .string) return b.string.len == 0;
        if (b == .null and a == .string) return a.string.len == 0;
        if (a == .null) return !b.isTruthy();
        if (b == .null) return !a.isTruthy();
        // when one side is bool, both are cast to bool (PHP rule)
        if (a == .bool or b == .bool) return a.isTruthy() == b.isTruthy();
        if (a == .string and b == .string) {
            // PHP: when both strings are numeric, compare numerically (so '1' == '01')
            if (isNumericString(a.string.bytes()) and isNumericString(b.string.bytes())) {
                return toFloat(a) == toFloat(b);
            }
            return std.mem.eql(u8, a.string.bytes(), b.string.bytes());
        }
        // php 8: int/float vs non-numeric string is always false
        if ((a == .int or a == .float) and b == .string) {
            if (!isNumericString(b.string.bytes())) return false;
        }
        if ((b == .int or b == .float) and a == .string) {
            if (!isNumericString(a.string.bytes())) return false;
        }
        return toFloat(a) == toFloat(b);
    }

    pub fn isNumericString(s: []const u8) bool {
        var i: usize = 0;
        while (i < s.len and (s[i] == ' ' or s[i] == '\t' or s[i] == '\n' or s[i] == '\r')) i += 1;
        if (i >= s.len) return false;
        if (s[i] == '-' or s[i] == '+') i += 1;
        if (i >= s.len) return false;
        var has_digit = false;
        while (i < s.len and s[i] >= '0' and s[i] <= '9') {
            i += 1;
            has_digit = true;
        }
        if (i < s.len and s[i] == '.') {
            i += 1;
            while (i < s.len and s[i] >= '0' and s[i] <= '9') {
                i += 1;
                has_digit = true;
            }
        }
        if (i < s.len and (s[i] == 'e' or s[i] == 'E')) {
            i += 1;
            if (i < s.len and (s[i] == '-' or s[i] == '+')) i += 1;
            while (i < s.len and s[i] >= '0' and s[i] <= '9') i += 1;
        }
        while (i < s.len and (s[i] == ' ' or s[i] == '\t' or s[i] == '\n' or s[i] == '\r')) i += 1;
        return has_digit and i == s.len;
    }

    pub fn identical(a: Value, b: Value) bool {
        if (@intFromEnum(a) != @intFromEnum(b)) return false;
        return switch (a) {
            .null => true,
            .bool => |ab| ab == b.bool,
            .int => |ai| ai == b.int,
            .float => |af| af == b.float,
            .string => |as_| std.mem.eql(u8, as_.bytes(), b.string.bytes()),
            .array => |ap| arrayEqual(ap, b.array, true),
            .object => |ao| ao == b.object,
            .generator => |ag| ag == b.generator,
            .fiber => |af| af == b.fiber,
        };
    }

    pub fn lessThan(a: Value, b: Value) bool {
        return compare(a, b) < 0;
    }

    pub fn compare(a: Value, b: Value) i64 {
        if (a == .object and b == .object) {
            if (a.object == b.object) return 0;
            if (!std.mem.eql(u8, a.object.class_name, b.object.class_name)) return 1;
            return objectsCompare(a.object, b.object);
        }
        if (a == .object or b == .object or a == .generator or b == .generator or a == .fiber or b == .fiber) return 0;
        if (a == .array and b == .array) {
            const al = a.array.entries.items.len;
            const bl = b.array.entries.items.len;
            if (al != bl) return if (al < bl) -1 else 1;
            for (a.array.entries.items) |entry| {
                const bv = b.array.get(entry.key);
                if (bv == .null and !arrayHasKey(b.array, entry.key)) return 1;
                const c = compare(entry.value, bv);
                if (c != 0) return c;
            }
            return 0;
        }
        if (a == .array or b == .array) return if (a == .array) 1 else -1;
        if (a == .string and b == .string) {
            // PHP: when both strings are numeric, compare numerically
            if (isNumericString(a.string.bytes()) and isNumericString(b.string.bytes())) {
                const af = toFloat(a);
                const bf = toFloat(b);
                if (af < bf) return -1;
                if (af > bf) return 1;
                return 0;
            }
            return switch (std.mem.order(u8, a.string.bytes(), b.string.bytes())) {
                .lt => -1,
                .eq => 0,
                .gt => 1,
            };
        }
        // PHP 8: number vs non-numeric string falls back to STRING comparison
        // (the number is stringified). Number vs numeric string still numeric.
        if ((a == .int or a == .float) and b == .string and !isNumericString(b.string.bytes())) {
            var buf: [64]u8 = undefined;
            const as: []const u8 = if (a == .int) (std.fmt.bufPrint(&buf, "{d}", .{a.int}) catch "") else (std.fmt.bufPrint(&buf, "{d}", .{a.float}) catch "");
            return switch (std.mem.order(u8, as, b.string.bytes())) {
                .lt => -1,
                .eq => 0,
                .gt => 1,
            };
        }
        if ((b == .int or b == .float) and a == .string and !isNumericString(a.string.bytes())) {
            var buf: [64]u8 = undefined;
            const bs: []const u8 = if (b == .int) (std.fmt.bufPrint(&buf, "{d}", .{b.int}) catch "") else (std.fmt.bufPrint(&buf, "{d}", .{b.float}) catch "");
            return switch (std.mem.order(u8, a.string.bytes(), bs)) {
                .lt => -1,
                .eq => 0,
                .gt => 1,
            };
        }
        // PHP: null vs string compares as "" vs string, so `null < 'abc'` is
        // true and `null == ''` is true
        if (a == .null and b == .string) {
            return switch (std.mem.order(u8, "", b.string.bytes())) {
                .lt => -1,
                .eq => 0,
                .gt => 1,
            };
        }
        if (a == .string and b == .null) {
            return switch (std.mem.order(u8, a.string.bytes(), "")) {
                .lt => -1,
                .eq => 0,
                .gt => 1,
            };
        }
        // PHP: when either operand is bool or null (and it isn't the
        // null-vs-string case handled above), convert both to bool and
        // compare - FALSE < TRUE. so `null < -1` is true (false < true)
        if (a == .bool or a == .null or b == .bool or b == .null) {
            const ab: i64 = if (a.isTruthy()) 1 else 0;
            const bb: i64 = if (b.isTruthy()) 1 else 0;
            return if (ab < bb) -1 else if (ab > bb) 1 else 0;
        }
        const af = toFloat(a);
        const bf = toFloat(b);
        if (af < bf) return -1;
        if (af > bf) return 1;
        return 0;
    }

    fn arrayHasKey(arr: *PhpArray, key: PhpArray.Key) bool {
        for (arr.entries.items) |e| {
            switch (e.key) {
                .string => |s| if (key == .string and std.mem.eql(u8, s.bytes(), key.string.bytes())) return true,
                .int => |n| if (key == .int and n == key.int) return true,
            }
        }
        return false;
    }

    fn objectsCompare(a: *PhpObject, b: *PhpObject) i64 {
        // walk a's slots + properties; compare value-by-value
        if (a.slots) |sa| {
            const sb = b.slots orelse return 1;
            if (a.slot_layout) |la| {
                for (la.names, 0..) |name, i| {
                    if (i >= sa.len or i >= sb.len) break;
                    const va = sa[i];
                    const vb = b.get(name);
                    const c = compare(va, vb);
                    if (c != 0) return c;
                }
            }
        }
        var it = a.properties.iterator();
        while (it.next()) |entry| {
            const va = entry.value_ptr.*;
            const vb = b.get(entry.key_ptr.*);
            const c = compare(va, vb);
            if (c != 0) return c;
        }
        var it2 = b.properties.iterator();
        while (it2.next()) |entry| {
            if (a.properties.get(entry.key_ptr.*) == null) {
                // b has prop a doesn't: a < b
                return -1;
            }
        }
        return 0;
    }

    // float -> int the way PHP's zend_dval_to_lval does it: NaN/Inf become 0,
    // in-range finite floats truncate toward zero, and out-of-range floats wrap
    // modulo 2^64 rather than saturating. matches PHP for huge casts like
    // (int)9.5e18 == -8946744073709551616
    pub fn dvalToLval(d: f64) i64 {
        if (std.math.isNan(d) or std.math.isInf(d)) return 0;
        // 2^63 as a double; any |d| below this fits an i64 directly
        if (d >= -9.2233720368547758e18 and d < 9.2233720368547758e18) {
            return @intFromFloat(@trunc(d));
        }
        const two_pow_64: f64 = 18446744073709551616.0;
        var dmod = @rem(d, two_pow_64);
        if (dmod < 0) dmod = @ceil(dmod) + two_pow_64;
        if (dmod >= two_pow_64) dmod -= two_pow_64;
        const u: u64 = @intFromFloat(dmod);
        return @bitCast(u);
    }

    pub fn toInt(v: Value) i64 {
        return switch (v) {
            .null => 0,
            .bool => |b| if (b) @as(i64, 1) else 0,
            .int => |i| i,
            .float => |f| dvalToLval(f),
            .string => |s| parseLeadingInt(s.bytes()),
            .array => |arr| if (arr.entries.items.len > 0) @as(i64, 1) else 0,
            .object, .generator, .fiber => 1,
        };
    }

    pub fn toFloat(v: Value) f64 {
        return switch (v) {
            .null => 0.0,
            .bool => |b| if (b) 1.0 else 0.0,
            .int => |i| @floatFromInt(i),
            .float => |f| f,
            .string => |s| parseLeadingFloat(s.bytes()),
            .array, .object, .generator, .fiber => 0.0,
        };
    }

    fn parseLeadingInt(s: []const u8) i64 {
        var i: usize = 0;
        while (i < s.len and (s[i] == ' ' or s[i] == '\t' or s[i] == '\n' or s[i] == '\r')) i += 1;
        if (i >= s.len) return 0;
        const start = i;
        var neg = false;
        if (s[i] == '-') {
            neg = true;
            i += 1;
        } else if (s[i] == '+') i += 1;
        if (i >= s.len or s[i] < '0' or s[i] > '9') return 0;
        const digits_start = i;
        while (i < s.len and s[i] >= '0' and s[i] <= '9') i += 1;
        var is_float = false;
        if (i < s.len and s[i] == '.') is_float = true;
        if (i < s.len and (s[i] == 'e' or s[i] == 'E')) {
            var j = i + 1;
            if (j < s.len and (s[j] == '-' or s[j] == '+')) j += 1;
            if (j < s.len and s[j] >= '0' and s[j] <= '9') is_float = true;
        }
        if (is_float) {
            const f = parseLeadingFloat(s[start..]);
            if (!std.math.isFinite(f)) return 0;
            const max_f: f64 = 9.2233720368547758e18;
            if (f >= max_f or f < -max_f) return 0;
            return @intFromFloat(f);
        }
        // saturating parse: matches PHP's "(int)<numeric string>" which clamps
        // overflow to PHP_INT_MAX / PHP_INT_MIN rather than wrapping
        var result: i64 = 0;
        var overflow = false;
        var k = digits_start;
        while (k < s.len and s[k] >= '0' and s[k] <= '9') : (k += 1) {
            const d: i64 = s[k] - '0';
            const m = @mulWithOverflow(result, 10);
            if (m[1] != 0) {
                overflow = true;
                break;
            }
            const a = @addWithOverflow(m[0], d);
            if (a[1] != 0) {
                overflow = true;
                break;
            }
            result = a[0];
        }
        if (overflow) return if (neg) std.math.minInt(i64) else std.math.maxInt(i64);
        if (neg) {
            const n = @subWithOverflow(@as(i64, 0), result);
            if (n[1] != 0) return std.math.minInt(i64);
            return n[0];
        }
        return result;
    }

    fn parseLeadingFloat(s: []const u8) f64 {
        var start: usize = 0;
        while (start < s.len and (s[start] == ' ' or s[start] == '\t' or s[start] == '\n' or s[start] == '\r')) start += 1;
        if (start >= s.len) return 0.0;
        var end = start;
        if (s[end] == '-' or s[end] == '+') end += 1;
        var has_digit = false;
        while (end < s.len and s[end] >= '0' and s[end] <= '9') {
            end += 1;
            has_digit = true;
        }
        if (end < s.len and s[end] == '.') {
            end += 1;
            while (end < s.len and s[end] >= '0' and s[end] <= '9') {
                end += 1;
                has_digit = true;
            }
        }
        if (end < s.len and (s[end] == 'e' or s[end] == 'E')) {
            // only consume the exponent when at least one exponent digit
            // follows (with an optional sign). matches PHP, which treats
            // "1e" as 1.0 and "1e+" as 1.0
            var ej = end + 1;
            if (ej < s.len and (s[ej] == '-' or s[ej] == '+')) ej += 1;
            if (ej < s.len and s[ej] >= '0' and s[ej] <= '9') {
                end = ej;
                while (end < s.len and s[end] >= '0' and s[end] <= '9') end += 1;
            }
        }
        if (!has_digit) return 0.0;
        return std.fmt.parseFloat(f64, s[start..end]) catch 0.0;
    }

    pub fn toArrayKey(v: Value) PhpArray.Key {
        return switch (v) {
            .int => |i| .{ .int = i },
            .string => |s| .{ .string = s },
            .bool => |b| .{ .int = if (b) 1 else 0 },
            .float => |f| .{ .int = dvalToLval(f) },
            .null => .{ .string = Value.String.borrowed("") },
            .array, .object, .generator, .fiber => .{ .int = 0 },
        };
    }

    pub fn format(self: Value, buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator) !void {
        switch (self) {
            .null => {},
            .bool => |b| if (b) try buf.appendSlice(allocator, "1"),
            .int => |i| {
                var tmp: [32]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return;
                try buf.appendSlice(allocator, s);
            },
            .float => |f| {
                if (f == @trunc(f) and @abs(f) < 1e14) {
                    const i: i64 = @intFromFloat(f);
                    var tmp: [32]u8 = undefined;
                    const s = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return;
                    if (i == 0 and std.math.signbit(f)) try buf.append(allocator, '-');
                    try buf.appendSlice(allocator, s);
                } else if (std.math.isNan(f)) {
                    try buf.appendSlice(allocator, "NAN");
                } else if (std.math.isInf(f)) {
                    if (f < 0) try buf.append(allocator, '-');
                    try buf.appendSlice(allocator, "INF");
                } else {
                    const abs_f = @abs(f);
                    // very small or very large numbers use scientific notation.
                    // PHP defaults precision=14 so values needing more than 14
                    // significant digits go scientific.
                    if (abs_f != 0 and (abs_f < 1e-4 or abs_f >= 1e14)) {
                        var tmp: [64]u8 = undefined;
                        const s = formatScientific(&tmp, f);
                        try buf.appendSlice(allocator, s);
                    } else {
                        // PHP uses 14 significant digits
                        const digits_before: usize = if (abs_f >= 1.0)
                            @as(usize, @intFromFloat(@floor(@log10(abs_f)))) + 1
                        else
                            0;
                        const precision: usize = if (digits_before < 14) 14 - digits_before else 0;
                        var tmp: [64]u8 = undefined;
                        const s = formatFloat(&tmp, f, precision);
                        var end: usize = s.len;
                        if (std.mem.indexOf(u8, s, ".")) |_| {
                            while (end > 1 and s[end - 1] == '0') end -= 1;
                            if (end > 0 and s[end - 1] == '.') end -= 1;
                        }
                        try buf.appendSlice(allocator, s[0..end]);
                    }
                }
            },
            .string => |s| try buf.appendSlice(allocator, s.bytes()),
            .array => try buf.appendSlice(allocator, "Array"),
            .object => try buf.appendSlice(allocator, "Object"),
            .generator => try buf.appendSlice(allocator, ""),
            .fiber => try buf.appendSlice(allocator, ""),
        }
    }

    fn formatFloat(buf: *[64]u8, f: f64, precision: usize) []const u8 {
        const p: u4 = @intCast(@min(precision, 15));
        switch (p) {
            inline 0...15 => |cp| return std.fmt.bufPrint(buf, "{d:." ++ std.fmt.comptimePrint("{d}", .{@min(cp, 14)}) ++ "}", .{f}) catch "0",
        }
    }

    fn formatScientific(buf: *[64]u8, f: f64) []const u8 {
        // PHP format: [-]d.dddE[+-]d+  (uppercase E, 14 significant digits)
        const abs_f = @abs(f);
        const exp: i32 = if (abs_f != 0)
            @intFromFloat(@floor(@log10(abs_f)))
        else
            0;
        const mantissa = f / std.math.pow(f64, 10.0, @floatFromInt(exp));

        // 14 significant digits total, 13 after the decimal in mantissa
        var tmp: [64]u8 = undefined;
        const m = formatFloat(&tmp, @abs(mantissa), 13);

        // strip trailing zeros but keep at least one decimal place
        var end: usize = m.len;
        if (std.mem.indexOf(u8, m, ".")) |dot| {
            while (end > dot + 2 and m[end - 1] == '0') end -= 1;
        }

        const sign: []const u8 = if (f < 0) "-" else "";
        const exp_sign: u8 = if (exp >= 0) '+' else '-';
        const exp_abs: u32 = @intCast(if (exp >= 0) exp else -exp);

        return std.fmt.bufPrint(buf, "{s}{s}E{c}{d}", .{ sign, m[0..end], exp_sign, exp_abs }) catch "0";
    }

    // overflow-safe int arithmetic, promotes to float on overflow
    pub fn intAdd(a: i64, b: i64) Value {
        const r = @addWithOverflow(a, b);
        if (r[1] == 0) return .{ .int = r[0] };
        return .{ .float = @as(f64, @floatFromInt(a)) + @as(f64, @floatFromInt(b)) };
    }
    pub fn intSub(a: i64, b: i64) Value {
        const r = @subWithOverflow(a, b);
        if (r[1] == 0) return .{ .int = r[0] };
        return .{ .float = @as(f64, @floatFromInt(a)) - @as(f64, @floatFromInt(b)) };
    }
    pub fn intMul(a: i64, b: i64) Value {
        const r = @mulWithOverflow(a, b);
        if (r[1] == 0) return .{ .int = r[0] };
        return .{ .float = @as(f64, @floatFromInt(a)) * @as(f64, @floatFromInt(b)) };
    }
    pub fn intInc(a: i64) Value {
        const r = @addWithOverflow(a, @as(i64, 1));
        if (r[1] == 0) return .{ .int = r[0] };
        return .{ .float = @as(f64, @floatFromInt(a)) + 1.0 };
    }
    pub fn intDec(a: i64) Value {
        const r = @subWithOverflow(a, @as(i64, 1));
        if (r[1] == 0) return .{ .int = r[0] };
        return .{ .float = @as(f64, @floatFromInt(a)) - 1.0 };
    }

    /// PHP `++` semantics. For non-numeric strings, applies Perl-style
    /// alphabetic increment (a->b, z->aa, AZ->BA, Zz->AAa, ''->'1'). Numeric
    /// strings increment numerically. null becomes 1. bool/array/object are
    /// returned unchanged (matches PHP's no-op + deprecation notice path).
    pub fn phpInc(a: Value, allocator: std.mem.Allocator) !Value {
        switch (a) {
            .int => |i| return intInc(i),
            .float => |f| return .{ .float = f + 1.0 },
            .null => return .{ .int = 1 },
            .string => |s| {
                if (s.len == 0) return .{ .string = Value.String.borrowed("1") };
                if (isNumericString(s.bytes())) {
                    if (isNumericIntString(s.bytes())) {
                        const parsed = std.fmt.parseInt(i64, s.bytes(), 10) catch {
                            const f = std.fmt.parseFloat(f64, s.bytes()) catch 0.0;
                            return .{ .float = f + 1.0 };
                        };
                        return intInc(parsed);
                    }
                    const f = std.fmt.parseFloat(f64, s.bytes()) catch 0.0;
                    return .{ .float = f + 1.0 };
                }
                return .{ .string = try Value.String.adopt(allocator, try incrementAlphaString(allocator, s.bytes())) };
            },
            else => return a,
        }
    }

    /// PHP `--` semantics. Non-numeric strings and null are returned unchanged
    /// (PHP 8.3+ emits a deprecation notice but keeps the value).
    pub fn phpDec(a: Value) Value {
        switch (a) {
            .int => |i| return intDec(i),
            .float => |f| return .{ .float = f - 1.0 },
            .null => return .null,
            .string => |s| {
                if (s.len == 0) return a;
                if (isNumericString(s.bytes())) {
                    if (isNumericIntString(s.bytes())) {
                        const parsed = std.fmt.parseInt(i64, s.bytes(), 10) catch {
                            const f = std.fmt.parseFloat(f64, s.bytes()) catch 0.0;
                            return .{ .float = f - 1.0 };
                        };
                        return intDec(parsed);
                    }
                    const f = std.fmt.parseFloat(f64, s.bytes()) catch 0.0;
                    return .{ .float = f - 1.0 };
                }
                return a;
            },
            else => return a,
        }
    }

    fn incrementAlphaString(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
        var buf = try allocator.alloc(u8, s.len);
        @memcpy(buf, s);
        var i: usize = s.len;
        var carry = true;
        while (carry and i > 0) {
            i -= 1;
            const c = buf[i];
            if (c >= 'a' and c <= 'z') {
                if (c == 'z') {
                    buf[i] = 'a';
                } else {
                    buf[i] = c + 1;
                    carry = false;
                }
            } else if (c >= 'A' and c <= 'Z') {
                if (c == 'Z') {
                    buf[i] = 'A';
                } else {
                    buf[i] = c + 1;
                    carry = false;
                }
            } else if (c >= '0' and c <= '9') {
                if (c == '9') {
                    buf[i] = '0';
                } else {
                    buf[i] = c + 1;
                    carry = false;
                }
            } else {
                // non-alnum stops the carry without modification (PHP returns
                // the original string)
                carry = false;
            }
        }
        if (carry) {
            const first = s[0];
            const prefix: u8 = if (first >= 'a' and first <= 'z') 'a' else if (first >= 'A' and first <= 'Z') 'A' else '1';
            const grown = try allocator.alloc(u8, s.len + 1);
            grown[0] = prefix;
            @memcpy(grown[1..], buf);
            allocator.free(buf);
            return grown;
        }
        return buf;
    }

    const BinOp = enum { add, sub, mul };

    fn numericBinOp(a: Value, b: Value, op: BinOp) Value {
        const ar = numericPromote(a);
        const br = numericPromote(b);
        if (ar == .int_kind and br == .int_kind) {
            const ai = ar.int_kind;
            const bi = br.int_kind;
            switch (op) {
                .add => {
                    const r = @addWithOverflow(ai, bi);
                    if (r[1] == 0) return .{ .int = r[0] };
                },
                .sub => {
                    const r = @subWithOverflow(ai, bi);
                    if (r[1] == 0) return .{ .int = r[0] };
                },
                .mul => {
                    const r = @mulWithOverflow(ai, bi);
                    if (r[1] == 0) return .{ .int = r[0] };
                },
            }
            // overflow: promote to float
            const af: f64 = @floatFromInt(ai);
            const bf: f64 = @floatFromInt(bi);
            return .{ .float = switch (op) {
                .add => af + bf,
                .sub => af - bf,
                .mul => af * bf,
            } };
        }
        const af: f64 = switch (ar) {
            .int_kind => |i| @floatFromInt(i),
            .float_kind => |f| f,
        };
        const bf: f64 = switch (br) {
            .int_kind => |i| @floatFromInt(i),
            .float_kind => |f| f,
        };
        return .{ .float = switch (op) {
            .add => af + bf,
            .sub => af - bf,
            .mul => af * bf,
        } };
    }

    const NumericValue = union(enum) {
        int_kind: i64,
        float_kind: f64,
    };

    fn numericPromote(v: Value) NumericValue {
        return switch (v) {
            .int => |i| .{ .int_kind = i },
            .float => |f| .{ .float_kind = f },
            .bool => |b| .{ .int_kind = if (b) @as(i64, 1) else 0 },
            .null => .{ .int_kind = 0 },
            .string => |s| classifyNumericString(s.bytes()),
            else => .{ .int_kind = 0 },
        };
    }

    fn classifyNumericString(s: []const u8) NumericValue {
        var start: usize = 0;
        while (start < s.len and (s[start] == ' ' or s[start] == '\t' or s[start] == '\n' or s[start] == '\r')) start += 1;
        var i = start;
        var has_dot = false;
        var has_exp = false;
        if (i < s.len and (s[i] == '+' or s[i] == '-')) i += 1;
        while (i < s.len) : (i += 1) {
            const c = s[i];
            if (c >= '0' and c <= '9') continue;
            if (c == '.' and !has_dot and !has_exp) {
                has_dot = true;
                continue;
            }
            if ((c == 'e' or c == 'E') and !has_exp and i > start) {
                has_exp = true;
                if (i + 1 < s.len and (s[i + 1] == '+' or s[i + 1] == '-')) i += 1;
                continue;
            }
            break;
        }
        const num_str = s[start..i];
        if (num_str.len == 0 or std.mem.eql(u8, num_str, "+") or std.mem.eql(u8, num_str, "-")) {
            return .{ .int_kind = 0 };
        }
        if (has_dot or has_exp) {
            const f = std.fmt.parseFloat(f64, num_str) catch 0.0;
            return .{ .float_kind = f };
        }
        const n = std.fmt.parseInt(i64, num_str, 10) catch {
            const f = std.fmt.parseFloat(f64, num_str) catch 0.0;
            return .{ .float_kind = f };
        };
        return .{ .int_kind = n };
    }
};

test "truthiness" {
    try std.testing.expect(!Value.isTruthy(.null));
    try std.testing.expect(!Value.isTruthy(.{ .bool = false }));
    try std.testing.expect(Value.isTruthy(.{ .bool = true }));
    try std.testing.expect(!Value.isTruthy(.{ .int = 0 }));
    try std.testing.expect(Value.isTruthy(.{ .int = 1 }));
    try std.testing.expect(!Value.isTruthy(.{ .string = Value.String.borrowed("") }));
    try std.testing.expect(!Value.isTruthy(.{ .string = Value.String.borrowed("0") }));
    try std.testing.expect(Value.isTruthy(.{ .string = Value.String.borrowed("hello") }));
}

test "arithmetic" {
    const a = Value{ .int = 10 };
    const b = Value{ .int = 3 };
    try std.testing.expectEqual(@as(i64, 13), Value.add(a, b).int);
    try std.testing.expectEqual(@as(i64, 7), Value.subtract(a, b).int);
    try std.testing.expectEqual(@as(i64, 30), Value.multiply(a, b).int);
}

test "int float promotion" {
    const a = Value{ .int = 3 };
    const b = Value{ .float = 1.5 };
    try std.testing.expectEqual(@as(f64, 4.5), Value.add(a, b).float);
}

test "identical" {
    try std.testing.expect(Value.identical(.{ .int = 2 }, .{ .int = 2 }));
    try std.testing.expect(!Value.identical(.{ .int = 1 }, .{ .int = 2 }));
    try std.testing.expect(!Value.identical(.{ .int = 2 }, .{ .string = Value.String.borrowed("2") }));
}

// These tests deliberately use an owned key/value allocated independently of
// the failing allocator, so every failure in the operation can check ownership.
fn testArrayStoreFailures(allocator: std.mem.Allocator, mode: enum { append, integer, string }, weak: bool) !void {
    const key = try PhpString.create(std.testing.allocator, "owned-key");
    defer key.release();
    const value = try PhpString.create(std.testing.allocator, "owned-value");
    defer value.release();
    var arr: PhpArray = .{ .weak = weak, .cursor = 7 };
    defer arr.deinit(allocator);
    // Deinit releases keys, but the VM normally releases stored values.
    defer if (!weak) {
        for (arr.entries.items) |entry| if (entry.value == .string) {
            entry.value.string.release();
        };
    };
    const result = switch (mode) {
        .append => arr.append(allocator, .{ .string = value }),
        .integer => arr.set(allocator, .{ .int = std.math.maxInt(i64) }, .{ .string = value }),
        .string => arr.set(allocator, .{ .string = key }, .{ .string = value }),
    };
    result catch |err| {
        try std.testing.expectEqual(@as(usize, 0), arr.entries.items.len);
        try std.testing.expectEqual(@as(u32, 0), arr.string_index.count());
        try std.testing.expectEqual(@as(i64, 0), arr.next_int_key);
        try std.testing.expect(!arr.has_int_keys);
        try std.testing.expectEqual(@as(usize, 7), arr.cursor);
        try std.testing.expectEqual(@as(u32, 1), key.owner.?.refcount);
        try std.testing.expectEqual(@as(u32, 1), value.owner.?.refcount);
        return err;
    };
    try std.testing.expectEqual(@as(usize, 1), arr.entries.items.len);
    try std.testing.expectEqual(@as(u32, if (weak) 1 else 2), value.owner.?.refcount);
    try std.testing.expectEqual(@as(u32, if (mode == .string) 2 else 1), key.owner.?.refcount);
    try std.testing.expect(arr.entries.items[0].ref == null);
    if (mode == .string) {
        try std.testing.expectEqual(@as(usize, 0), arr.string_index.get(key.bytes()).?);
    } else {
        try std.testing.expect(arr.has_int_keys);
        try std.testing.expectEqual(@as(i64, if (mode == .append) 1 else std.math.maxInt(i64)), arr.next_int_key);
    }
}

test "array append and set fail atomically at every allocation" {
    inline for (.{ .append, .integer, .string }) |mode| {
        inline for (.{ false, true }) |weak| {
            try std.testing.checkAllAllocationFailures(std.testing.allocator, testArrayStoreFailures, .{ mode, weak });
        }
    }
}

fn testArrayRebuildFailures(allocator: std.mem.Allocator) !void {
    var arr: PhpArray = .{};
    defer arr.deinit(allocator);
    // Use the failing allocator for setup too; the exhaustive runner reaches
    // every growth in both the initial index and the temporary replacement.
    const keys = [_][]const u8{ "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o" };
    for (keys, 0..) |key, i| try arr.set(allocator, .{ .string = PhpString.borrowed(key) }, .{ .int = @intCast(i) });
    var cell: Value = .{ .int = 42 };
    arr.entries.items[0].ref = &cell;
    arr.cursor = 4;
    arr.rebuildStringIndex(allocator) catch |err| {
        try std.testing.expectEqual(@as(u32, keys.len), arr.string_index.count());
        for (keys, 0..) |key, i| try std.testing.expectEqual(i, arr.string_index.get(key).?);
        try std.testing.expect(arr.entries.items[0].ref == &cell);
        try std.testing.expectEqual(@as(usize, 4), arr.cursor);
        return err;
    };
    for (keys, 0..) |key, i| try std.testing.expectEqual(i, arr.string_index.get(key).?);
}

test "array index rebuild preserves old complete index on every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, testArrayRebuildFailures, .{});
}

const ArrayStoreTestRelease = struct {
    calls: usize = 0,
    fn call(ctx: *anyopaque, value: Value) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.calls += 1;
        if (value == .string) value.string.release();
    }
};

test "array allocation-free stores preserve ownership metadata and overflow refusal" {
    const allocator = std.testing.allocator;
    var failing = std.testing.FailingAllocator.init(allocator, .{ .fail_index = 0 });
    const noalloc = failing.allocator();
    const value = try PhpString.create(allocator, "same value");
    defer value.release();
    var releases: ArrayStoreTestRelease = .{};
    const saved = release_hook;
    release_hook = .{ .ctx = &releases, .call = ArrayStoreTestRelease.call };
    defer release_hook = saved;
    var arr: PhpArray = .{};
    defer arr.deinit(allocator);
    defer for (arr.entries.items) |entry| {
        if (entry.value == .string) entry.value.string.release();
    };
    try arr.entries.ensureUnusedCapacity(allocator, 4);
    try arr.reserveStringIndex(allocator, 2);
    try arr.append(noalloc, .{ .string = value });
    try arr.set(noalloc, .{ .string = PhpString.borrowed("0") }, .{ .string = value });
    try arr.set(noalloc, .{ .int = -5 }, .{ .string = value });
    try arr.set(noalloc, .{ .int = -5 }, .{ .string = value });
    try arr.set(noalloc, .{ .string = PhpString.borrowed("name") }, .{ .string = value });
    var cell: Value = .null;
    arr.entries.items[2].ref = &cell;
    try arr.set(noalloc, .{ .string = PhpString.borrowed("name") }, .{ .string = value });
    try std.testing.expect(arr.entries.items[2].ref == &cell);
    try arr.set(noalloc, .{ .string = PhpString.borrowed("9223372036854775807") }, .{ .string = value });
    try arr.set(noalloc, .{ .int = std.math.maxInt(i64) }, .{ .string = value });
    try arr.append(noalloc, .{ .string = value }); // refused, no retain
    try std.testing.expectEqual(@as(usize, 4), arr.entries.items.len);
    try std.testing.expectEqual(@as(u32, 5), value.owner.?.refcount);
    try std.testing.expectEqual(@as(usize, 4), releases.calls);
    try std.testing.expectEqual(std.math.maxInt(i64), arr.next_int_key);
    std.mem.swap(PhpArray.Entry, &arr.entries.items[0], &arr.entries.items[2]);
    arr.rebuildStringIndexAssumeCapacity();
    try std.testing.expectEqual(@as(usize, 0), arr.string_index.get("name").?);
    try std.testing.expect(arr.entries.items[0].ref == &cell);
    try std.testing.expect(!failing.has_induced_failure);
}

test "array failed growth preserves populated entries and reference bindings" {
    const allocator = std.testing.allocator;
    var arr: PhpArray = .{ .cursor = 3 };
    defer arr.deinit(allocator);
    var held: PhpArray = .{};
    var candidate: PhpArray = .{};
    var cell: Value = .{ .int = 99 };
    try arr.set(allocator, .{ .string = PhpString.borrowed("existing") }, .{ .array = &held });
    arr.entries.items[0].ref = &cell;
    // Force entry growth regardless of ArrayList's growth policy.
    while (arr.entries.items.len < arr.entries.capacity) try arr.append(allocator, .null);
    const len = arr.entries.items.len;
    const next = arr.next_int_key;
    var failing = std.testing.FailingAllocator.init(allocator, .{ .fail_index = 0, .resize_fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, arr.append(failing.allocator(), .{ .array = &candidate }));
    try std.testing.expectError(error.OutOfMemory, arr.set(failing.allocator(), .{ .int = -20 }, .{ .array = &candidate }));
    try std.testing.expectError(error.OutOfMemory, arr.set(failing.allocator(), .{ .string = PhpString.borrowed("new") }, .{ .array = &candidate }));
    try std.testing.expectError(error.OutOfMemory, arr.reserveStringIndex(failing.allocator(), 100));
    try std.testing.expectEqual(len, arr.entries.items.len);
    try std.testing.expectEqual(next, arr.next_int_key);
    try std.testing.expectEqual(@as(usize, 3), arr.cursor);
    try std.testing.expectEqual(@as(u32, 1), held.refcount);
    try std.testing.expectEqual(@as(u32, 0), candidate.refcount);
    try std.testing.expect(arr.entries.items[0].ref == &cell);
    try std.testing.expectEqual(@as(usize, 0), arr.string_index.get("existing").?);
    try std.testing.expect(!arr.contains(.{ .string = PhpString.borrowed("new") }));
    // A weak replacement neither retains the candidate nor releases the old.
    arr.weak = true;
    try arr.set(failing.allocator(), .{ .string = PhpString.borrowed("existing") }, .{ .array = &candidate });
    try std.testing.expectEqual(@as(u32, 0), candidate.refcount);
    try std.testing.expectEqual(@as(u32, 1), held.refcount);
    try std.testing.expect(arr.entries.items[0].ref == &cell);
}
