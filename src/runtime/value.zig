const std = @import("std");

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
        string: []const u8,

        pub fn eql(a: Key, b: Key) bool {
            if (@intFromEnum(a) != @intFromEnum(b)) return false;
            return switch (a) {
                .int => |ai| ai == b.int,
                .string => |as_| std.mem.eql(u8, as_, b.string),
            };
        }
    };

    // PHP coerces array string keys that look like canonical decimal integers
    // (no leading zeros, no plus, no whitespace, fits in i64) to int keys at
    // both write and read time. This matches PHP's behavior so $arr['3'] and
    // $arr[3] address the same slot.
    pub fn normalizeKey(key: Key) Key {
        if (key != .string) return key;
        const s = key.string;
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
        self.entries.deinit(allocator);
        self.string_index.deinit(allocator);
    }

    // increment the refcount (Stage 2). a method on PhpArray so value.zig
    // can refcount array elements without importing the VM
    pub fn retain(self: *PhpArray) void {
        self.refcount +%= 1;
    }

    pub fn append(self: *PhpArray, allocator: std.mem.Allocator, value: Value) !void {
        // an object or array stored as an element is a new reference. this is
        // a store choke point - the value must arrive un-retained (callers
        // pass transferArg'd or raw values, never copyValue'd ones)
        if (value == .object) value.object.retain();
        if (value == .array) value.array.retain();
        if (value == .generator) value.generator.retain();
        if (value == .fiber) value.fiber.retain();
        const k = if (self.has_int_keys) self.next_int_key else 0;
        if (self.has_int_keys and k == std.math.maxInt(i64)) {
            for (self.entries.items) |entry| {
                if (entry.key == .int and entry.key.int == k) return;
            }
        }
        try self.entries.append(allocator, .{ .key = .{ .int = k }, .value = value });
        self.next_int_key = if (k == std.math.maxInt(i64)) k else k + 1;
        self.has_int_keys = true;
    }

    pub fn set(self: *PhpArray, allocator: std.mem.Allocator, raw_key: Key, value: Value) !void {
        // an object or array stored as an element is a new reference. this is
        // a store choke point - the value must arrive un-retained (callers
        // pass transferArg'd or raw values, never copyValue'd ones). the
        // overwritten old element is not released here (no VM access)
        if (value == .object) value.object.retain();
        if (value == .array) value.array.retain();
        if (value == .generator) value.generator.retain();
        if (value == .fiber) value.fiber.retain();
        const key = normalizeKey(raw_key);
        if (key == .int) {
            const idx = key.int;
            if (idx >= 0) {
                const uidx: usize = @intCast(idx);
                if (uidx < self.entries.items.len) {
                    const entry = &self.entries.items[uidx];
                    if (entry.key == .int and entry.key.int == idx) {
                        entry.value = value;
                        self.next_int_key = if (self.has_int_keys) @max(self.next_int_key, idx + 1) else idx + 1;
                        self.has_int_keys = true;
                        return;
                    }
                }
            }
        }
        if (key == .string) {
            if (self.string_index.get(key.string)) |idx| {
                self.entries.items[idx].value = value;
                return;
            }
        } else {
            for (self.entries.items) |*entry| {
                if (entry.key.eql(key)) {
                    entry.value = value;
                    return;
                }
            }
        }
        const new_idx = self.entries.items.len;
        try self.entries.append(allocator, .{ .key = key, .value = value });
        if (key == .int) {
            const next = if (key.int == std.math.maxInt(i64)) key.int else key.int + 1;
            self.next_int_key = if (self.has_int_keys) @max(self.next_int_key, next) else next;
            self.has_int_keys = true;
        } else if (key == .string) {
            try self.string_index.put(allocator, key.string, new_idx);
        }
    }

    pub fn contains(self: *const PhpArray, raw_key: Key) bool {
        const key = normalizeKey(raw_key);
        if (key == .string) return self.string_index.contains(key.string);
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
            if (self.string_index.get(key.string)) |idx| {
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
            if (self.string_index.get(key.string)) |idx| return &self.entries.items[idx];
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

    pub fn rebuildStringIndex(self: *PhpArray, allocator: std.mem.Allocator) !void {
        self.string_index.clearRetainingCapacity();
        for (self.entries.items, 0..) |entry, i| {
            if (entry.key == .string) {
                try self.string_index.put(allocator, entry.key.string, i);
            }
        }
    }

    pub fn remove(self: *PhpArray, key: Key) void {
        var remove_idx: ?usize = null;
        if (key == .string) {
            if (self.string_index.fetchRemove(key.string)) |kv| {
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
            _ = self.entries.orderedRemove(idx);
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
    fwd: std.AutoHashMapUnmanaged(*Value, std.ArrayListUnmanaged(BindingTarget)) = .{},
    prop_rev: std.HashMapUnmanaged(PropRefKey, std.ArrayListUnmanaged(*Value), PropRefKeyContext, 80) = .{},

    pub fn addForward(self: *RefIndex, a: std.mem.Allocator, cell: *Value, target: BindingTarget) !void {
        const gop = try self.fwd.getOrPut(a, cell);
        if (!gop.found_existing) gop.value_ptr.* = .{};
        try gop.value_ptr.append(a, target);
    }

    pub fn addPropRev(self: *RefIndex, a: std.mem.Allocator, key: PropRefKey, cell: *Value) !void {
        const gop = try self.prop_rev.getOrPut(a, key);
        if (!gop.found_existing) gop.value_ptr.* = .{};
        try gop.value_ptr.append(a, cell);
    }

    // drop every target/cell associated with this cell (frame teardown, unset,
    // generator suspend). O(targets-for-this-cell), never a global scan
    pub fn removeCell(self: *RefIndex, a: std.mem.Allocator, cell: *Value) void {
        if (self.fwd.fetchRemove(cell)) |kv| {
            var list = kv.value;
            // also scrub this cell from any prop_rev lists it appears in
            for (list.items) |t| {
                switch (t) {
                    .object => |o| self.removePropRevCell(.{ .object = o.object, .class_name = "", .prop_name = o.prop_name }, cell),
                    .static => |s| self.removePropRevCell(.{ .object = null, .class_name = s.class_name, .prop_name = s.prop_name }, cell),
                    .array => {},
                }
            }
            list.deinit(a);
        }
    }

    fn removePropRevCell(self: *RefIndex, key: PropRefKey, cell: *Value) void {
        if (self.prop_rev.getPtr(key)) |list| {
            var i: usize = 0;
            while (i < list.items.len) {
                if (list.items[i] == cell) {
                    _ = list.swapRemove(i);
                } else i += 1;
            }
        }
    }

    pub fn clear(self: *RefIndex, a: std.mem.Allocator) void {
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
        self.ref_slots.deinit(allocator);
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
        ref_array_bindings: std.ArrayListUnmanaged(ArrayRefBinding) = .{},
        ref_object_bindings: std.ArrayListUnmanaged(ObjectRefBinding) = .{},
        ref_static_bindings: std.ArrayListUnmanaged(StaticPropRefBinding) = .{},
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
            f.ref_slots.deinit(allocator);
            f.ref_array_bindings.deinit(allocator);
            f.ref_object_bindings.deinit(allocator);
            f.ref_static_bindings.deinit(allocator);
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
    lazy_initializer: Value = .null,
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
    }

    pub fn isUnset(self: *const PhpObject, name: []const u8) bool {
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
        if (self.slots) |s| {
            if (self.getSlotIndexForScope(name, scope)) |idx| return s[idx];
        }
        return self.properties.get(name) orelse .null;
    }

    pub fn set(self: *PhpObject, allocator: std.mem.Allocator, name: []const u8, value: Value) !void {
        // an object or array stored as a property is a new reference - this
        // is the universal property-store choke point, so native code calling
        // obj.set retains too. callers pass transferArg'd or raw values (never
        // copyValue'd ones). the overwritten old value is not released here
        // (no VM access); set_prop does overwrite-release, native overwrites
        // leak (rare). object teardown releases all property objects/arrays
        if (value == .object) value.object.retain();
        if (value == .array) value.array.retain();
        if (value == .generator) value.generator.retain();
        if (value == .fiber) value.fiber.retain();
        // a write resurrects a previously-unset property
        self.clearUnset(name);
        if (self.slots) |s| {
            if (self.getSlotIndex(name)) |idx| {
                s[idx] = value;
                return;
            }
        }
        try self.properties.put(allocator, name, value);
    }

    // scope-aware variant for the set_prop opcode path where we know the
    // declaring class (private slots are picked correctly)
    pub fn setForScope(self: *PhpObject, allocator: std.mem.Allocator, name: []const u8, value: Value, scope: ?[]const u8) !void {
        if (value == .object) value.object.retain();
        if (value == .array) value.array.retain();
        if (value == .generator) value.generator.retain();
        if (value == .fiber) value.fiber.retain();
        self.clearUnset(name);
        if (self.slots) |s| {
            if (self.getSlotIndexForScope(name, scope)) |idx| {
                s[idx] = value;
                return;
            }
        }
        try self.properties.put(allocator, name, value);
    }
};

pub const Value = union(enum) {
    null,
    bool: bool,
    int: i64,
    float: f64,
    string: []const u8,
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
            .string => |s| s.len > 0 and !std.mem.eql(u8, s, "0"),
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
        const both_int = (a == .int or (a == .string and isNumericIntString(a.string))) and
            (b == .int or (b == .string and isNumericIntString(b.string)));
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
                    if (r[1] != 0) { overflowed = true; break; }
                    result = r[0];
                }
                if (e > 1) {
                    const r = @mulWithOverflow(base, base);
                    if (r[1] != 0) { overflowed = true; break; }
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
        if (key == .string) return arr.string_index.contains(key.string);
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
            if (isNumericString(a.string) and isNumericString(b.string)) {
                return toFloat(a) == toFloat(b);
            }
            return std.mem.eql(u8, a.string, b.string);
        }
        // php 8: int/float vs non-numeric string is always false
        if ((a == .int or a == .float) and b == .string) {
            if (!isNumericString(b.string)) return false;
        }
        if ((b == .int or b == .float) and a == .string) {
            if (!isNumericString(a.string)) return false;
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
        while (i < s.len and s[i] >= '0' and s[i] <= '9') { i += 1; has_digit = true; }
        if (i < s.len and s[i] == '.') {
            i += 1;
            while (i < s.len and s[i] >= '0' and s[i] <= '9') { i += 1; has_digit = true; }
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
            .string => |as_| std.mem.eql(u8, as_, b.string),
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
            if (isNumericString(a.string) and isNumericString(b.string)) {
                const af = toFloat(a);
                const bf = toFloat(b);
                if (af < bf) return -1;
                if (af > bf) return 1;
                return 0;
            }
            return switch (std.mem.order(u8, a.string, b.string)) {
                .lt => -1,
                .eq => 0,
                .gt => 1,
            };
        }
        // PHP 8: number vs non-numeric string falls back to STRING comparison
        // (the number is stringified). Number vs numeric string still numeric.
        if ((a == .int or a == .float) and b == .string and !isNumericString(b.string)) {
            var buf: [64]u8 = undefined;
            const as: []const u8 = if (a == .int) (std.fmt.bufPrint(&buf, "{d}", .{a.int}) catch "")
                                   else (std.fmt.bufPrint(&buf, "{d}", .{a.float}) catch "");
            return switch (std.mem.order(u8, as, b.string)) {
                .lt => -1, .eq => 0, .gt => 1,
            };
        }
        if ((b == .int or b == .float) and a == .string and !isNumericString(a.string)) {
            var buf: [64]u8 = undefined;
            const bs: []const u8 = if (b == .int) (std.fmt.bufPrint(&buf, "{d}", .{b.int}) catch "")
                                   else (std.fmt.bufPrint(&buf, "{d}", .{b.float}) catch "");
            return switch (std.mem.order(u8, a.string, bs)) {
                .lt => -1, .eq => 0, .gt => 1,
            };
        }
        // PHP: null vs string compares as "" vs string, so `null < 'abc'` is
        // true and `null == ''` is true
        if (a == .null and b == .string) {
            return switch (std.mem.order(u8, "", b.string)) { .lt => -1, .eq => 0, .gt => 1 };
        }
        if (a == .string and b == .null) {
            return switch (std.mem.order(u8, a.string, "")) { .lt => -1, .eq => 0, .gt => 1 };
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
                .string => |s| if (key == .string and std.mem.eql(u8, s, key.string)) return true,
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
            .string => |s| parseLeadingInt(s),
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
            .string => |s| parseLeadingFloat(s),
            .array, .object, .generator, .fiber => 0.0,
        };
    }

    fn parseLeadingInt(s: []const u8) i64 {
        var i: usize = 0;
        while (i < s.len and (s[i] == ' ' or s[i] == '\t' or s[i] == '\n' or s[i] == '\r')) i += 1;
        if (i >= s.len) return 0;
        const start = i;
        var neg = false;
        if (s[i] == '-') { neg = true; i += 1; } else if (s[i] == '+') i += 1;
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
            if (m[1] != 0) { overflow = true; break; }
            const a = @addWithOverflow(m[0], d);
            if (a[1] != 0) { overflow = true; break; }
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
        while (end < s.len and s[end] >= '0' and s[end] <= '9') { end += 1; has_digit = true; }
        if (end < s.len and s[end] == '.') {
            end += 1;
            while (end < s.len and s[end] >= '0' and s[end] <= '9') { end += 1; has_digit = true; }
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
            .null => .{ .string = "" },
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
            .string => |s| try buf.appendSlice(allocator, s),
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
                if (s.len == 0) return .{ .string = "1" };
                if (isNumericString(s)) {
                    if (isNumericIntString(s)) {
                        const parsed = std.fmt.parseInt(i64, s, 10) catch {
                            const f = std.fmt.parseFloat(f64, s) catch 0.0;
                            return .{ .float = f + 1.0 };
                        };
                        return intInc(parsed);
                    }
                    const f = std.fmt.parseFloat(f64, s) catch 0.0;
                    return .{ .float = f + 1.0 };
                }
                return .{ .string = try incrementAlphaString(allocator, s) };
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
                if (isNumericString(s)) {
                    if (isNumericIntString(s)) {
                        const parsed = std.fmt.parseInt(i64, s, 10) catch {
                            const f = std.fmt.parseFloat(f64, s) catch 0.0;
                            return .{ .float = f - 1.0 };
                        };
                        return intDec(parsed);
                    }
                    const f = std.fmt.parseFloat(f64, s) catch 0.0;
                    return .{ .float = f - 1.0 };
                }
                return a;
            },
            else => return a,
        }
    }

    fn incrementAlphaString(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
        var buf = try allocator.alloc(u8, s.len);
        @memcpy(buf, s);
        var i: usize = s.len;
        var carry = true;
        while (carry and i > 0) {
            i -= 1;
            const c = buf[i];
            if (c >= 'a' and c <= 'z') {
                if (c == 'z') { buf[i] = 'a'; } else { buf[i] = c + 1; carry = false; }
            } else if (c >= 'A' and c <= 'Z') {
                if (c == 'Z') { buf[i] = 'A'; } else { buf[i] = c + 1; carry = false; }
            } else if (c >= '0' and c <= '9') {
                if (c == '9') { buf[i] = '0'; } else { buf[i] = c + 1; carry = false; }
            } else {
                // non-alnum stops the carry without modification (PHP returns
                // the original string)
                carry = false;
            }
        }
        if (carry) {
            const first = s[0];
            const prefix: u8 = if (first >= 'a' and first <= 'z') 'a'
                else if (first >= 'A' and first <= 'Z') 'A'
                else '1';
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
            .string => |s| classifyNumericString(s),
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
            if (c == '.' and !has_dot and !has_exp) { has_dot = true; continue; }
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
    try std.testing.expect(!Value.isTruthy(.{ .string = "" }));
    try std.testing.expect(!Value.isTruthy(.{ .string = "0" }));
    try std.testing.expect(Value.isTruthy(.{ .string = "hello" }));
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
    try std.testing.expect(!Value.identical(.{ .int = 2 }, .{ .string = "2" }));
}
