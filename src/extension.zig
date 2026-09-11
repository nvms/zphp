// third-party extensions: a C ABI (include/zphp_extension.h) over the native
// function table. an extension registers functions, classes, constants, ini
// defaults, and resource types once per process in module_init; every VM
// applies that registry when it starts, and each PHP call reaches the
// extension through a comptime trampoline that carries its slot index
const std = @import("std");
const builtin = @import("builtin");
const vm_mod = @import("runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const NativeFn = vm_mod.NativeFn;
const RuntimeError = vm_mod.RuntimeError;
const NativeResult = vm_mod.NativeResult;
const ClassDef = vm_mod.ClassDef;
const InterfaceDef = vm_mod.InterfaceDef;
const value_mod = @import("runtime/value.zig");
const Value = value_mod.Value;
const PhpArray = value_mod.PhpArray;
const NativeHandle = value_mod.NativeHandle;
const PhpObject = value_mod.PhpObject;
const static_extensions = @import("static_extensions");

pub const abi_version: u32 = 1;
const max_functions = 2048;

pub const Descriptor = extern struct {
    abi: u32,
    name: ?[*:0]const u8,
    version: ?[*:0]const u8,
    module_init: ?*const fn (*Extension) callconv(.c) c_int,
    module_shutdown: ?*const fn () callconv(.c) void,
    worker_init: ?*const fn (*Call) callconv(.c) c_int,
    worker_shutdown: ?*const fn (*Call) callconv(.c) void,
    request_init: ?*const fn (*Call) callconv(.c) c_int,
    request_shutdown: ?*const fn (*Call) callconv(.c) void,
};

pub const ExtFn = *const fn (*Call) callconv(.c) void;
pub const ResourceDtor = *const fn (?*anyopaque) callconv(.c) void;
pub const EntryFn = *const fn (*const Api) callconv(.c) ?*const Descriptor;

const CStr = ?[*:0]const u8;

const FunctionReg = struct { name: []const u8, slot: u32 };
const MethodReg = struct { name: []const u8, slot: u32, arity: u8, is_static: bool };
const ConstantReg = struct { name: []const u8, value: Value };
const PropertyReg = struct { name: []const u8, default: Value };
const IniReg = struct { name: []const u8, default: []const u8 };
const ResourceReg = struct { class_name: []const u8, dtor: ResourceDtor };

pub const ClassReg = struct {
    ext: *Extension,
    name: []const u8,
    parent: ?[]const u8,
    interfaces: std.ArrayListUnmanaged([]const u8) = .{},
    methods: std.ArrayListUnmanaged(MethodReg) = .{},
    constants: std.ArrayListUnmanaged(ConstantReg) = .{},
    properties: std.ArrayListUnmanaged(PropertyReg) = .{},
    resource_type: ?u32 = null,
};

const InterfaceReg = struct { name: []const u8, methods: std.ArrayListUnmanaged([]const u8) = .{} };

// the zphp_module handle: one loaded extension and everything it registered
pub const Extension = struct {
    index: u32,
    desc: *const Descriptor,
    name: []const u8,
    version: []const u8,
    lib: ?std.DynLib = null,
    registering: bool = false,
    functions: std.ArrayListUnmanaged(FunctionReg) = .{},
    classes: std.ArrayListUnmanaged(*ClassReg) = .{},
    interfaces: std.ArrayListUnmanaged(InterfaceReg) = .{},
    constants: std.ArrayListUnmanaged(ConstantReg) = .{},
    inis: std.ArrayListUnmanaged(IniReg) = .{},
    resources: std.ArrayListUnmanaged(ResourceReg) = .{},
};

// the zphp_ctx handle: one native call or lifecycle hook on one VM
pub const Call = struct {
    ctx: *NativeContext,
    ext: *Extension,
    args: []const Value,
    result: NativeResult = NativeResult.scalar(.null),
    threw: bool = false,
};

// per-VM state slots, one per extension
pub const VmSlot = struct { request: ?*anyopaque = null, worker: ?*anyopaque = null };

const Slot = struct { ext: *Extension, func: ExtFn };

var registry_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var extensions: std.ArrayListUnmanaged(*Extension) = .{};
var slots: [max_functions]Slot = undefined;
var slot_count: u32 = 0;
var resource_types: std.ArrayListUnmanaged(ResourceReg) = .{};
var shutdown_registered = false;

fn trampoline(comptime i: usize) NativeFn {
    return &struct {
        fn call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
            return invoke(&slots[i], ctx, args);
        }
    }.call;
}

const trampolines: [max_functions]NativeFn = blk: {
    @setEvalBranchQuota(max_functions * 4);
    var table: [max_functions]NativeFn = undefined;
    for (&table, 0..) |*entry, i| entry.* = trampoline(i);
    break :blk table;
};

fn invoke(slot: *const Slot, ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    var call = Call{ .ctx = ctx, .ext = slot.ext, .args = args };
    slot.func(&call);
    if (call.threw) return error.RuntimeError;
    return call.result;
}

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("zphp: " ++ fmt ++ "\n", args);
    std.process.exit(1);
}

fn persistent() std.mem.Allocator {
    return registry_arena.allocator();
}

fn dupe(s: []const u8) []const u8 {
    return persistent().dupe(u8, s) catch fail("extension registry out of memory", .{});
}

fn cstr(s: CStr) ?[]const u8 {
    return if (s) |p| std.mem.span(p) else null;
}

pub fn loaded() []const *Extension {
    return extensions.items;
}

pub fn isLoaded(name: []const u8) bool {
    for (extensions.items) |ext| if (std.ascii.eqlIgnoreCase(ext.name, name)) return true;
    return false;
}

// ---------------------------------------------------------------------------
// loading

pub fn loadStatic() void {
    inline for (static_extensions.entries) |entry| {
        const desc: ?*const Descriptor = @ptrCast(@alignCast(entry.entry(&api_v1)));
        adopt(entry.name, desc, null);
    }
}

pub fn loadDynamic(path: []const u8) void {
    if (builtin.abi.isMusl() and builtin.link_mode == .static) {
        fail("extension '{s}': this zphp binary is static and cannot load dynamic extensions; compile it in with -Dextension", .{path});
    }
    var lib = std.DynLib.open(path) catch |err| fail("extension '{s}': cannot load ({s})", .{ path, @errorName(err) });
    const entry = lib.lookup(EntryFn, "zphp_extension_entry") orelse fail("extension '{s}': no zphp_extension_entry symbol; is ZPHP_EXTENSION() used?", .{path});
    adopt(path, entry(&api_v1), lib);
}

pub fn loadDirectory(dir_path: []const u8) void {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| fail("extension directory '{s}': {s}", .{ dir_path, @errorName(err) });
    defer dir.close();
    var names: std.ArrayListUnmanaged([]const u8) = .{};
    defer names.deinit(persistent());
    var it = dir.iterate();
    while (it.next() catch null) |entry| {
        if (entry.kind != .file and entry.kind != .sym_link) continue;
        if (!isLibraryName(entry.name)) continue;
        names.append(persistent(), dupe(entry.name)) catch fail("extension registry out of memory", .{});
    }
    std.mem.sort([]const u8, names.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);
    for (names.items) |name| {
        const full = std.fs.path.join(persistent(), &.{ dir_path, name }) catch fail("extension registry out of memory", .{});
        loadDynamic(full);
    }
}

fn isLibraryName(name: []const u8) bool {
    const suffix: []const u8 = switch (builtin.os.tag) {
        .macos, .ios => ".dylib",
        .windows => ".dll",
        else => ".so",
    };
    return std.mem.endsWith(u8, name, suffix);
}

fn adopt(origin: []const u8, desc_ptr: ?*const Descriptor, lib: ?std.DynLib) void {
    const desc = desc_ptr orelse fail("extension '{s}': entry point returned no descriptor", .{origin});
    if (desc.abi != abi_version) fail("extension '{s}': built for ABI {d}, this zphp provides ABI {d}", .{ origin, desc.abi, abi_version });
    const name = cstr(desc.name) orelse fail("extension '{s}': descriptor has no name", .{origin});
    if (name.len == 0) fail("extension '{s}': descriptor has an empty name", .{origin});
    if (isLoaded(name)) fail("extension '{s}': an extension named '{s}' is already loaded", .{ origin, name });
    const ext = persistent().create(Extension) catch fail("extension registry out of memory", .{});
    ext.* = .{
        .index = @intCast(extensions.items.len),
        .desc = desc,
        .name = dupe(name),
        .version = dupe(cstr(desc.version) orelse "0"),
        .lib = lib,
    };
    extensions.append(persistent(), ext) catch fail("extension registry out of memory", .{});
    if (desc.module_init) |init| {
        ext.registering = true;
        const rc = init(ext);
        ext.registering = false;
        if (rc != 0) fail("extension '{s}': module_init failed with status {d}", .{ name, rc });
    }
    if (!shutdown_registered) {
        shutdown_registered = true;
        _ = atexit(shutdownAll);
    }
}

extern "c" fn atexit(?*const fn () callconv(.c) void) c_int;

fn shutdownAll() callconv(.c) void {
    var i = extensions.items.len;
    while (i > 0) {
        i -= 1;
        if (extensions.items[i].desc.module_shutdown) |shutdown| shutdown();
    }
}

// ---------------------------------------------------------------------------
// applying the registry to a VM

pub fn vmInit(vm: *VM) RuntimeError!void {
    if (extensions.items.len == 0) return;
    vm.ic.?.ext_slots = try vm.allocator.alloc(VmSlot, extensions.items.len);
    @memset(vm.ic.?.ext_slots, .{});
    for (extensions.items) |ext| {
        for (ext.functions.items) |f| try registerNative(vm, f.name, f.slot);
        for (ext.interfaces.items) |iface| {
            if (vm.interfaces.contains(iface.name) or vm.classes.contains(iface.name)) fail("extension '{s}': interface '{s}' is already defined", .{ ext.name, iface.name });
            var def = InterfaceDef{ .name = iface.name };
            for (iface.methods.items) |m| try def.methods.append(vm.allocator, m);
            try vm.interfaces.put(vm.allocator, iface.name, def);
        }
        for (ext.classes.items) |cls| try registerClass(vm, cls);
    }
    checkConstantConflicts(vm);
    try applyConstants(vm);
    for (extensions.items) |ext| {
        const init = ext.desc.worker_init orelse continue;
        var ctx = vm.makeContext(null);
        var call = Call{ .ctx = &ctx, .ext = ext, .args = &.{} };
        if (init(&call) != 0) fail("extension '{s}': worker_init failed", .{ext.name});
    }
}

fn registerNative(vm: *VM, name: []const u8, slot: u32) RuntimeError!void {
    if (vm.native_fns.contains(name)) fail("extension '{s}': function '{s}' is already defined", .{ slots[slot].ext.name, name });
    try vm.native_fns.put(vm.allocator, name, trampolines[slot]);
}

fn registerClass(vm: *VM, cls: *ClassReg) RuntimeError!void {
    const a = vm.allocator;
    if (vm.classes.contains(cls.name) or vm.interfaces.contains(cls.name)) fail("extension '{s}': class '{s}' is already defined", .{ cls.ext.name, cls.name });
    var def = ClassDef{ .name = cls.name, .parent = cls.parent };
    if (cls.resource_type != null) def.native_cleanup = resourceCleanup;
    for (cls.interfaces.items) |iface| try def.interfaces.append(a, iface);
    for (cls.properties.items) |p| try def.properties.append(a, .{ .name = p.name, .default = p.default, .has_default = true });
    for (cls.constants.items) |c| {
        try def.static_props.put(a, c.name, c.value);
        try def.constant_names.put(a, c.name, {});
        try def.constant_order.append(a, c.name);
    }
    for (cls.methods.items) |m| {
        try def.addMethod(a, .{ .name = m.name, .arity = m.arity, .is_static = m.is_static });
        const full = try std.fmt.allocPrint(a, "{s}::{s}", .{ cls.name, m.name });
        try vm.persistent_strings.append(a, full);
        try registerNative(vm, full, m.slot);
    }
    try vm.classes.put(a, cls.name, def);
}

// constants are cleared and re-seeded on every serve reset, so this runs
// after initConstants both at init and at reset
pub fn applyConstants(vm: *VM) RuntimeError!void {
    for (extensions.items) |ext| {
        for (ext.constants.items) |c| {
            try vm.php_constants.put(vm.allocator, c.name, c.value);
        }
    }
}

pub fn checkConstantConflicts(vm: *VM) void {
    for (extensions.items) |ext| {
        for (ext.constants.items) |c| {
            if (vm.php_constants.contains(c.name)) fail("extension '{s}': constant '{s}' is already defined", .{ ext.name, c.name });
        }
    }
}

pub fn beginRequest(vm: *VM) RuntimeError!void {
    if (extensions.items.len == 0 or vm.ic.?.ext_request_active) return;
    vm.ic.?.ext_request_active = true;
    for (extensions.items) |ext| {
        for (ext.inis.items) |ini| {
            if (!vm.ini_settings.contains(ini.name)) try vm.ini_settings.put(vm.allocator, ini.name, ini.default);
        }
        const init = ext.desc.request_init orelse continue;
        var ctx = vm.makeContext(null);
        var call = Call{ .ctx = &ctx, .ext = ext, .args = &.{} };
        if (init(&call) != 0) {
            vm.error_msg = "extension request_init failed";
            return error.RuntimeError;
        }
    }
}

pub fn endRequest(vm: *VM) void {
    if (!vm.ic.?.ext_request_active) return;
    vm.ic.?.ext_request_active = false;
    var i = extensions.items.len;
    while (i > 0) {
        i -= 1;
        const ext = extensions.items[i];
        if (ext.desc.request_shutdown) |shutdown| {
            var ctx = vm.makeContext(null);
            var call = Call{ .ctx = &ctx, .ext = ext, .args = &.{} };
            shutdown(&call);
        }
        vm.ic.?.ext_slots[ext.index].request = null;
    }
    _ = vm.ic.?.ext_arena.reset(.retain_capacity);
}

pub fn vmDeinit(vm: *VM) void {
    const ic = vm.ic orelse return;
    if (ic.ext_slots.len == 0) return;
    endRequest(vm);
    var i = extensions.items.len;
    while (i > 0) {
        i -= 1;
        const ext = extensions.items[i];
        const shutdown = ext.desc.worker_shutdown orelse continue;
        var ctx = vm.makeContext(null);
        var call = Call{ .ctx = &ctx, .ext = ext, .args = &.{} };
        shutdown(&call);
        vm.ic.?.ext_slots[ext.index].worker = null;
    }
    vm.ic.?.ext_arena.deinit();
    vm.allocator.free(vm.ic.?.ext_slots);
    vm.ic.?.ext_slots = &.{};
}

// the destructor runs once, then the pointer is zeroed
fn resourceCleanup(obj: *PhpObject) bool {
    const id = obj.native.extensionId() orelse return true;
    if (obj.native.ptr == 0 or id == 0) return true;
    const index: usize = id - 1;
    if (index < resource_types.items.len) resource_types.items[index].dtor(@ptrFromInt(obj.native.ptr));
    obj.native.ptr = 0;
    return true;
}

pub fn cleanupResources(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    if (resource_types.items.len == 0) return;
    for (objects.items) |obj| {
        if (obj.pooled or obj.native.extensionId() == null) continue;
        _ = resourceCleanup(obj);
    }
}

// ---------------------------------------------------------------------------
// the C API table

fn regOnly(ext: *Extension) bool {
    if (!ext.registering) {
        std.debug.print("zphp: extension '{s}': registration is only allowed during module_init\n", .{ext.name});
        return false;
    }
    return true;
}

fn apiRegisterFunction(ext: *Extension, name: CStr, func: ?ExtFn) callconv(.c) c_int {
    if (!regOnly(ext)) return -1;
    const n = cstr(name) orelse return -1;
    const f = func orelse return -1;
    if (n.len == 0) return -1;
    const slot = newSlot(ext, f) orelse return -1;
    for (extensions.items) |other| for (other.functions.items) |existing| if (std.ascii.eqlIgnoreCase(existing.name, n)) {
        fail("extension '{s}': function '{s}' is already registered by extension '{s}'", .{ ext.name, n, other.name });
    };
    ext.functions.append(persistent(), .{ .name = dupe(n), .slot = slot }) catch return -1;
    return 0;
}

fn newSlot(ext: *Extension, func: ExtFn) ?u32 {
    if (slot_count >= max_functions) {
        std.debug.print("zphp: extension '{s}': too many extension functions (limit {d})\n", .{ ext.name, max_functions });
        return null;
    }
    slots[slot_count] = .{ .ext = ext, .func = func };
    slot_count += 1;
    return slot_count - 1;
}

fn apiRegisterClass(ext: *Extension, name: CStr, parent: CStr) callconv(.c) ?*ClassReg {
    if (!regOnly(ext)) return null;
    const n = cstr(name) orelse return null;
    if (n.len == 0) return null;
    for (extensions.items) |other| for (other.classes.items) |existing| if (std.ascii.eqlIgnoreCase(existing.name, n)) {
        fail("extension '{s}': class '{s}' is already registered by extension '{s}'", .{ ext.name, n, other.name });
    };
    const cls = persistent().create(ClassReg) catch return null;
    cls.* = .{ .ext = ext, .name = dupe(n), .parent = if (cstr(parent)) |p| dupe(p) else null };
    ext.classes.append(persistent(), cls) catch return null;
    return cls;
}

fn apiClassAddMethod(cls: ?*ClassReg, name: CStr, func: ?ExtFn, arity: u8, flags: u32) callconv(.c) c_int {
    const c = cls orelse return -1;
    if (!regOnly(c.ext)) return -1;
    const n = cstr(name) orelse return -1;
    const f = func orelse return -1;
    const slot = newSlot(c.ext, f) orelse return -1;
    c.methods.append(persistent(), .{ .name = dupe(n), .slot = slot, .arity = arity, .is_static = flags & 1 != 0 }) catch return -1;
    return 0;
}

fn classConstant(cls: ?*ClassReg, name: CStr, value: Value) c_int {
    const c = cls orelse return -1;
    if (!regOnly(c.ext)) return -1;
    const n = cstr(name) orelse return -1;
    c.constants.append(persistent(), .{ .name = dupe(n), .value = value }) catch return -1;
    return 0;
}

fn apiClassAddConstantInt(cls: ?*ClassReg, name: CStr, value: i64) callconv(.c) c_int {
    return classConstant(cls, name, .{ .int = value });
}

fn apiClassAddConstantFloat(cls: ?*ClassReg, name: CStr, value: f64) callconv(.c) c_int {
    return classConstant(cls, name, .{ .float = value });
}

fn apiClassAddConstantBool(cls: ?*ClassReg, name: CStr, value: bool) callconv(.c) c_int {
    return classConstant(cls, name, .{ .bool = value });
}

fn apiClassAddConstantString(cls: ?*ClassReg, name: CStr, value: CStr) callconv(.c) c_int {
    const v = cstr(value) orelse return -1;
    return classConstant(cls, name, .{ .string = Value.String.borrowed(dupe(v)) });
}

fn classProperty(cls: ?*ClassReg, name: CStr, default: Value) c_int {
    const c = cls orelse return -1;
    if (!regOnly(c.ext)) return -1;
    const n = cstr(name) orelse return -1;
    c.properties.append(persistent(), .{ .name = dupe(n), .default = default }) catch return -1;
    return 0;
}

fn apiClassAddProperty(cls: ?*ClassReg, name: CStr) callconv(.c) c_int {
    return classProperty(cls, name, .null);
}

fn apiClassAddPropertyInt(cls: ?*ClassReg, name: CStr, value: i64) callconv(.c) c_int {
    return classProperty(cls, name, .{ .int = value });
}

fn apiClassAddPropertyString(cls: ?*ClassReg, name: CStr, value: CStr) callconv(.c) c_int {
    const v = cstr(value) orelse return -1;
    return classProperty(cls, name, .{ .string = Value.String.borrowed(dupe(v)) });
}

fn apiClassImplements(cls: ?*ClassReg, iface: CStr) callconv(.c) c_int {
    const c = cls orelse return -1;
    if (!regOnly(c.ext)) return -1;
    const n = cstr(iface) orelse return -1;
    c.interfaces.append(persistent(), dupe(n)) catch return -1;
    return 0;
}

fn apiRegisterInterface(ext: *Extension, name: CStr, methods: ?[*]const CStr, count: usize) callconv(.c) c_int {
    if (!regOnly(ext)) return -1;
    const n = cstr(name) orelse return -1;
    var reg = InterfaceReg{ .name = dupe(n) };
    if (methods) |list| for (list[0..count]) |m| {
        const method = cstr(m) orelse return -1;
        reg.methods.append(persistent(), dupe(method)) catch return -1;
    };
    ext.interfaces.append(persistent(), reg) catch return -1;
    return 0;
}

fn constant(ext: *Extension, name: CStr, value: Value) c_int {
    if (!regOnly(ext)) return -1;
    const n = cstr(name) orelse return -1;
    if (n.len == 0) return -1;
    ext.constants.append(persistent(), .{ .name = dupe(n), .value = value }) catch return -1;
    return 0;
}

fn apiRegisterConstantInt(ext: *Extension, name: CStr, value: i64) callconv(.c) c_int {
    return constant(ext, name, .{ .int = value });
}

fn apiRegisterConstantFloat(ext: *Extension, name: CStr, value: f64) callconv(.c) c_int {
    return constant(ext, name, .{ .float = value });
}

fn apiRegisterConstantBool(ext: *Extension, name: CStr, value: bool) callconv(.c) c_int {
    return constant(ext, name, .{ .bool = value });
}

fn apiRegisterConstantString(ext: *Extension, name: CStr, value: CStr) callconv(.c) c_int {
    const v = cstr(value) orelse return -1;
    return constant(ext, name, .{ .string = Value.String.borrowed(dupe(v)) });
}

fn apiRegisterIni(ext: *Extension, name: CStr, default: CStr) callconv(.c) c_int {
    if (!regOnly(ext)) return -1;
    const n = cstr(name) orelse return -1;
    const d = cstr(default) orelse return -1;
    ext.inis.append(persistent(), .{ .name = dupe(n), .default = dupe(d) }) catch return -1;
    return 0;
}

fn apiRegisterResource(ext: *Extension, class_name: CStr, dtor: ?ResourceDtor) callconv(.c) u32 {
    if (!regOnly(ext)) return 0;
    const d = dtor orelse return 0;
    const cls = apiRegisterClass(ext, class_name, null) orelse return 0;
    const reg = ResourceReg{ .class_name = cls.name, .dtor = d };
    resource_types.append(persistent(), reg) catch return 0;
    ext.resources.append(persistent(), reg) catch return 0;
    cls.resource_type = @intCast(resource_types.items.len);
    return cls.resource_type.?;
}

fn cell(call: *Call, v: Value) ?*Value {
    const p = call.ctx.vm.ic.?.ext_arena.allocator().create(Value) catch return null;
    p.* = v;
    return p;
}

fn apiArgCount(call: *Call) callconv(.c) usize {
    return call.args.len;
}

fn apiArg(call: *Call, index: usize) callconv(.c) ?*const Value {
    if (index >= call.args.len) return null;
    return &call.args[index];
}

fn apiThis(call: *Call) callconv(.c) ?*const Value {
    const vm = call.ctx.vm;
    if (vm.frame_count == 0) return null;
    const this = vm.currentFrame().vars.get("$this") orelse return null;
    if (this != .object) return null;
    return cell(call, this);
}

fn apiTypeOf(v: ?*const Value) callconv(.c) c_int {
    const value = v orelse return 0;
    return switch (value.*) {
        .null => 0,
        .bool => 1,
        .int => 2,
        .float => 3,
        .string => 4,
        .array => 5,
        .object => 6,
        else => 7,
    };
}

fn apiGetInt(v: ?*const Value) callconv(.c) i64 {
    return Value.toInt((v orelse return 0).*);
}

fn apiGetFloat(v: ?*const Value) callconv(.c) f64 {
    return Value.toFloat((v orelse return 0).*);
}

fn apiGetBool(v: ?*const Value) callconv(.c) bool {
    return (v orelse return false).isTruthy();
}

fn apiGetString(call: *Call, v: ?*const Value, len: ?*usize) callconv(.c) ?[*]const u8 {
    const value = (v orelse return null).*;
    const bytes: []const u8 = switch (value) {
        .string => |s| s.bytes(),
        .array, .object, .generator, .fiber => return null,
        else => blk: {
            var buf = std.ArrayListUnmanaged(u8){};
            defer buf.deinit(call.ctx.allocator);
            value.format(&buf, call.ctx.allocator) catch return null;
            break :blk call.ctx.createString(buf.items) catch return null;
        },
    };
    if (len) |l| l.* = bytes.len;
    return bytes.ptr;
}

fn apiMakeNull(call: *Call) callconv(.c) ?*Value {
    return cell(call, .null);
}

fn apiMakeBool(call: *Call, value: bool) callconv(.c) ?*Value {
    return cell(call, .{ .bool = value });
}

fn apiMakeInt(call: *Call, value: i64) callconv(.c) ?*Value {
    return cell(call, .{ .int = value });
}

fn apiMakeFloat(call: *Call, value: f64) callconv(.c) ?*Value {
    return cell(call, .{ .float = value });
}

fn apiMakeString(call: *Call, bytes: ?[*]const u8, len: usize) callconv(.c) ?*Value {
    const src: []const u8 = if (bytes) |b| b[0..len] else "";
    const owned = call.ctx.createString(src) catch return null;
    return cell(call, .{ .string = Value.String.borrowed(owned) });
}

fn apiMakeArray(call: *Call) callconv(.c) ?*Value {
    const arr = call.ctx.createArray() catch return null;
    return cell(call, .{ .array = arr });
}

fn apiArrayCount(v: ?*const Value) callconv(.c) usize {
    const value = v orelse return 0;
    if (value.* != .array) return 0;
    return value.array.entries.items.len;
}

fn apiArrayPush(call: *Call, arr: ?*Value, v: ?*const Value) callconv(.c) c_int {
    const target = arr orelse return -1;
    if (target.* != .array) return -1;
    target.array.append(call.ctx.allocator, (v orelse return -1).*) catch return -1;
    return 0;
}

fn apiArraySetInt(call: *Call, arr: ?*Value, key: i64, v: ?*const Value) callconv(.c) c_int {
    const target = arr orelse return -1;
    if (target.* != .array) return -1;
    target.array.set(call.ctx.allocator, .{ .int = key }, (v orelse return -1).*) catch return -1;
    return 0;
}

fn apiArraySetString(call: *Call, arr: ?*Value, key: ?[*]const u8, key_len: usize, v: ?*const Value) callconv(.c) c_int {
    const target = arr orelse return -1;
    if (target.* != .array) return -1;
    const k = call.ctx.createString(if (key) |p| p[0..key_len] else "") catch return -1;
    target.array.set(call.ctx.allocator, .{ .string = Value.String.borrowed(k) }, (v orelse return -1).*) catch return -1;
    return 0;
}

fn entryValue(entry: PhpArray.Entry) Value {
    return if (entry.ref) |r| r.* else entry.value;
}

fn apiArrayGetInt(call: *Call, arr: ?*const Value, key: i64) callconv(.c) ?*const Value {
    const source = arr orelse return null;
    if (source.* != .array) return null;
    if (!source.array.contains(.{ .int = key })) return null;
    return cell(call, source.array.get(.{ .int = key }));
}

fn apiArrayGetString(call: *Call, arr: ?*const Value, key: ?[*]const u8, key_len: usize) callconv(.c) ?*const Value {
    const source = arr orelse return null;
    if (source.* != .array) return null;
    const k = PhpArray.Key{ .string = Value.String.borrowed(if (key) |p| p[0..key_len] else "") };
    if (!source.array.contains(k)) return null;
    return cell(call, source.array.get(k));
}

fn apiArrayAt(call: *Call, arr: ?*const Value, index: usize, key_out: ?*?*const Value, value_out: ?*?*const Value) callconv(.c) c_int {
    const source = arr orelse return -1;
    if (source.* != .array) return -1;
    if (index >= source.array.entries.items.len) return -1;
    const entry = source.array.entries.items[index];
    if (key_out) |k| k.* = cell(call, switch (entry.key) {
        .int => |i| .{ .int = i },
        .string => |s| .{ .string = s },
    });
    if (value_out) |v| v.* = cell(call, entryValue(entry));
    return 0;
}

fn apiMakeObject(call: *Call, class_name: CStr) callconv(.c) ?*Value {
    const name = cstr(class_name) orelse return null;
    const vm = call.ctx.vm;
    if (!vm.classes.contains(name)) return null;
    const stable = vm.classes.getKey(name).?;
    const obj = call.ctx.createObject(stable) catch return null;
    return cell(call, .{ .object = obj });
}

fn apiObjectClass(call: *Call, v: ?*const Value, len: ?*usize) callconv(.c) ?[*]const u8 {
    _ = call;
    const value = v orelse return null;
    if (value.* != .object) return null;
    if (len) |l| l.* = value.object.class_name.len;
    return value.object.class_name.ptr;
}

fn apiInstanceOf(call: *Call, v: ?*const Value, class_name: CStr) callconv(.c) bool {
    const value = v orelse return false;
    const name = cstr(class_name) orelse return false;
    if (value.* != .object) return false;
    return call.ctx.vm.isInstanceOf(value.object.class_name, name);
}

fn apiObjectGet(call: *Call, v: ?*const Value, name: CStr) callconv(.c) ?*const Value {
    const value = v orelse return null;
    const n = cstr(name) orelse return null;
    if (value.* != .object) return null;
    return cell(call, value.object.get(n));
}

fn apiObjectSet(call: *Call, v: ?*Value, name: CStr, new_value: ?*const Value) callconv(.c) c_int {
    const value = v orelse return -1;
    const n = cstr(name) orelse return -1;
    if (value.* != .object) return -1;
    const stable = call.ctx.createString(n) catch return -1;
    value.object.set(call.ctx.allocator, stable, (new_value orelse return -1).*) catch return -1;
    return 0;
}

fn apiMakeResource(call: *Call, kind: u32, ptr: ?*anyopaque) callconv(.c) ?*Value {
    if (kind == 0 or kind > resource_types.items.len) return null;
    const class_name = resource_types.items[kind - 1].class_name;
    const obj = call.ctx.createObject(class_name) catch return null;
    obj.native = .{ .kind = NativeHandle.extensionKind(kind), .ptr = @intFromPtr(ptr) };
    return cell(call, .{ .object = obj });
}

fn apiResourcePtr(call: *Call, v: ?*const Value, kind: u32) callconv(.c) ?*anyopaque {
    _ = call;
    const value = v orelse return null;
    if (value.* != .object) return null;
    return value.object.native.get(anyopaque, NativeHandle.extensionKind(kind));
}

fn collectArgs(buf: []Value, args: ?[*]const ?*const Value, count: usize) ?[]Value {
    if (count > buf.len) return null;
    const list = args orelse return if (count == 0) buf[0..0] else null;
    for (list[0..count], 0..) |arg, i| buf[i] = (arg orelse return null).*;
    return buf[0..count];
}

fn apiCall(call: *Call, name: CStr, args: ?[*]const ?*const Value, count: usize) callconv(.c) ?*Value {
    const n = cstr(name) orelse return null;
    var buf: [64]Value = undefined;
    const list = collectArgs(&buf, args, count) orelse return null;
    const result = call.ctx.callFunction(n, list) catch {
        failedCall(call, "Call to undefined function {s}()", .{n});
        return null;
    };
    return cell(call, result);
}

// a call that failed without raising a PHP exception (no such function or
// method) becomes an Error so the extension's caller sees what happened
fn failedCall(call: *Call, comptime fmt: []const u8, args: anytype) void {
    call.threw = true;
    const vm = call.ctx.vm;
    if (vm.pending_exception != null) return;
    const msg = std.fmt.allocPrint(call.ctx.allocator, fmt, args) catch return;
    call.ctx.strings.append(call.ctx.allocator, msg) catch return;
    _ = vm.throwBuiltinException("Error", vm.error_msg orelse msg) catch {};
}

fn apiCallMethod(call: *Call, target: ?*const Value, name: CStr, args: ?[*]const ?*const Value, count: usize) callconv(.c) ?*Value {
    const n = cstr(name) orelse return null;
    const obj = target orelse return null;
    if (obj.* != .object) return null;
    var buf: [64]Value = undefined;
    const list = collectArgs(&buf, args, count) orelse return null;
    const result = call.ctx.callMethod(obj.object, n, list) catch {
        failedCall(call, "Call to undefined method {s}::{s}()", .{ obj.object.class_name, n });
        return null;
    };
    return cell(call, result);
}

fn apiThrow(call: *Call, class_name: CStr, message: CStr) callconv(.c) void {
    const cls = cstr(class_name) orelse "Exception";
    const msg = call.ctx.createString(cstr(message) orelse "") catch "";
    _ = call.ctx.vm.throwBuiltinException(cls, msg) catch {};
    call.threw = true;
}

fn apiReturnNull(call: *Call) callconv(.c) void {
    call.result = NativeResult.scalar(.null);
}

fn apiReturnBool(call: *Call, value: bool) callconv(.c) void {
    call.result = NativeResult.scalar(.{ .bool = value });
}

fn apiReturnInt(call: *Call, value: i64) callconv(.c) void {
    call.result = NativeResult.scalar(.{ .int = value });
}

fn apiReturnFloat(call: *Call, value: f64) callconv(.c) void {
    call.result = NativeResult.scalar(.{ .float = value });
}

fn apiReturnString(call: *Call, bytes: ?[*]const u8, len: usize) callconv(.c) void {
    const src: []const u8 = if (bytes) |b| b[0..len] else "";
    call.result = NativeResult.copyString(call.ctx.allocator, src) catch NativeResult.scalar(.null);
}

fn apiReturnValue(call: *Call, v: ?*const Value) callconv(.c) void {
    const value = (v orelse return apiReturnNull(call)).*;
    call.result = switch (value) {
        .string => |s| if (s.owner != null) NativeResult.shareString(s) else NativeResult.copyString(call.ctx.allocator, s.bytes()) catch NativeResult.scalar(.null),
        else => NativeResult.borrowed(value),
    };
}

fn apiEcho(call: *Call, bytes: ?[*]const u8, len: usize) callconv(.c) void {
    const src = bytes orelse return;
    call.ctx.vm.output.appendSlice(call.ctx.allocator, src[0..len]) catch {};
}

fn apiIniGet(call: *Call, name: CStr, len: ?*usize) callconv(.c) ?[*]const u8 {
    const n = cstr(name) orelse return null;
    const stored = call.ctx.vm.ini_settings.get(n) orelse blk: {
        for (call.ext.inis.items) |ini| if (std.mem.eql(u8, ini.name, n)) break :blk ini.default;
        return null;
    };
    if (len) |l| l.* = stored.len;
    return stored.ptr;
}

fn apiRequestData(call: *Call) callconv(.c) ?*anyopaque {
    return call.ctx.vm.ic.?.ext_slots[call.ext.index].request;
}

fn apiSetRequestData(call: *Call, data: ?*anyopaque) callconv(.c) void {
    call.ctx.vm.ic.?.ext_slots[call.ext.index].request = data;
}

fn apiWorkerData(call: *Call) callconv(.c) ?*anyopaque {
    return call.ctx.vm.ic.?.ext_slots[call.ext.index].worker;
}

fn apiSetWorkerData(call: *Call, data: ?*anyopaque) callconv(.c) void {
    call.ctx.vm.ic.?.ext_slots[call.ext.index].worker = data;
}

// field order is the ABI: append only, and bump abi_version for anything else
pub const Api = extern struct {
    abi: u32,
    register_function: *const @TypeOf(apiRegisterFunction),
    register_class: *const @TypeOf(apiRegisterClass),
    class_add_method: *const @TypeOf(apiClassAddMethod),
    class_add_constant_int: *const @TypeOf(apiClassAddConstantInt),
    class_add_constant_float: *const @TypeOf(apiClassAddConstantFloat),
    class_add_constant_bool: *const @TypeOf(apiClassAddConstantBool),
    class_add_constant_string: *const @TypeOf(apiClassAddConstantString),
    class_add_property: *const @TypeOf(apiClassAddProperty),
    class_add_property_int: *const @TypeOf(apiClassAddPropertyInt),
    class_add_property_string: *const @TypeOf(apiClassAddPropertyString),
    class_implements: *const @TypeOf(apiClassImplements),
    register_interface: *const @TypeOf(apiRegisterInterface),
    register_constant_int: *const @TypeOf(apiRegisterConstantInt),
    register_constant_float: *const @TypeOf(apiRegisterConstantFloat),
    register_constant_bool: *const @TypeOf(apiRegisterConstantBool),
    register_constant_string: *const @TypeOf(apiRegisterConstantString),
    register_ini: *const @TypeOf(apiRegisterIni),
    register_resource: *const @TypeOf(apiRegisterResource),
    arg_count: *const @TypeOf(apiArgCount),
    arg: *const @TypeOf(apiArg),
    this_object: *const @TypeOf(apiThis),
    type_of: *const @TypeOf(apiTypeOf),
    get_int: *const @TypeOf(apiGetInt),
    get_float: *const @TypeOf(apiGetFloat),
    get_bool: *const @TypeOf(apiGetBool),
    get_string: *const @TypeOf(apiGetString),
    make_null: *const @TypeOf(apiMakeNull),
    make_bool: *const @TypeOf(apiMakeBool),
    make_int: *const @TypeOf(apiMakeInt),
    make_float: *const @TypeOf(apiMakeFloat),
    make_string: *const @TypeOf(apiMakeString),
    make_array: *const @TypeOf(apiMakeArray),
    array_count: *const @TypeOf(apiArrayCount),
    array_push: *const @TypeOf(apiArrayPush),
    array_set_int: *const @TypeOf(apiArraySetInt),
    array_set_string: *const @TypeOf(apiArraySetString),
    array_get_int: *const @TypeOf(apiArrayGetInt),
    array_get_string: *const @TypeOf(apiArrayGetString),
    array_at: *const @TypeOf(apiArrayAt),
    make_object: *const @TypeOf(apiMakeObject),
    object_class: *const @TypeOf(apiObjectClass),
    instance_of: *const @TypeOf(apiInstanceOf),
    object_get: *const @TypeOf(apiObjectGet),
    object_set: *const @TypeOf(apiObjectSet),
    make_resource: *const @TypeOf(apiMakeResource),
    resource_ptr: *const @TypeOf(apiResourcePtr),
    call: *const @TypeOf(apiCall),
    call_method: *const @TypeOf(apiCallMethod),
    throw_exception: *const @TypeOf(apiThrow),
    return_null: *const @TypeOf(apiReturnNull),
    return_bool: *const @TypeOf(apiReturnBool),
    return_int: *const @TypeOf(apiReturnInt),
    return_float: *const @TypeOf(apiReturnFloat),
    return_string: *const @TypeOf(apiReturnString),
    return_value: *const @TypeOf(apiReturnValue),
    echo: *const @TypeOf(apiEcho),
    ini_get: *const @TypeOf(apiIniGet),
    request_data: *const @TypeOf(apiRequestData),
    set_request_data: *const @TypeOf(apiSetRequestData),
    worker_data: *const @TypeOf(apiWorkerData),
    set_worker_data: *const @TypeOf(apiSetWorkerData),
};

pub const api_v1 = Api{
    .abi = abi_version,
    .register_function = apiRegisterFunction,
    .register_class = apiRegisterClass,
    .class_add_method = apiClassAddMethod,
    .class_add_constant_int = apiClassAddConstantInt,
    .class_add_constant_float = apiClassAddConstantFloat,
    .class_add_constant_bool = apiClassAddConstantBool,
    .class_add_constant_string = apiClassAddConstantString,
    .class_add_property = apiClassAddProperty,
    .class_add_property_int = apiClassAddPropertyInt,
    .class_add_property_string = apiClassAddPropertyString,
    .class_implements = apiClassImplements,
    .register_interface = apiRegisterInterface,
    .register_constant_int = apiRegisterConstantInt,
    .register_constant_float = apiRegisterConstantFloat,
    .register_constant_bool = apiRegisterConstantBool,
    .register_constant_string = apiRegisterConstantString,
    .register_ini = apiRegisterIni,
    .register_resource = apiRegisterResource,
    .arg_count = apiArgCount,
    .arg = apiArg,
    .this_object = apiThis,
    .type_of = apiTypeOf,
    .get_int = apiGetInt,
    .get_float = apiGetFloat,
    .get_bool = apiGetBool,
    .get_string = apiGetString,
    .make_null = apiMakeNull,
    .make_bool = apiMakeBool,
    .make_int = apiMakeInt,
    .make_float = apiMakeFloat,
    .make_string = apiMakeString,
    .make_array = apiMakeArray,
    .array_count = apiArrayCount,
    .array_push = apiArrayPush,
    .array_set_int = apiArraySetInt,
    .array_set_string = apiArraySetString,
    .array_get_int = apiArrayGetInt,
    .array_get_string = apiArrayGetString,
    .array_at = apiArrayAt,
    .make_object = apiMakeObject,
    .object_class = apiObjectClass,
    .instance_of = apiInstanceOf,
    .object_get = apiObjectGet,
    .object_set = apiObjectSet,
    .make_resource = apiMakeResource,
    .resource_ptr = apiResourcePtr,
    .call = apiCall,
    .call_method = apiCallMethod,
    .throw_exception = apiThrow,
    .return_null = apiReturnNull,
    .return_bool = apiReturnBool,
    .return_int = apiReturnInt,
    .return_float = apiReturnFloat,
    .return_string = apiReturnString,
    .return_value = apiReturnValue,
    .echo = apiEcho,
    .ini_get = apiIniGet,
    .request_data = apiRequestData,
    .set_request_data = apiSetRequestData,
    .worker_data = apiWorkerData,
    .set_worker_data = apiSetWorkerData,
};

test "the api table matches the header field by field" {
    const header = std.fs.cwd().readFileAlloc(std.testing.allocator, "include/zphp_extension.h", 1 << 20) catch return error.SkipZigTest;
    defer std.testing.allocator.free(header);
    const fields = @typeInfo(Api).@"struct".fields;
    var pos: usize = std.mem.indexOf(u8, header, "typedef struct zphp_api {").?;
    inline for (fields[1..]) |field| {
        const needle = "(*" ++ field.name ++ ")(";
        const at = std.mem.indexOfPos(u8, header, pos, needle) orelse {
            std.debug.print("api field '{s}' missing from the header, or out of order\n", .{field.name});
            return error.TestUnexpectedResult;
        };
        pos = at + needle.len;
    }
    const end = std.mem.indexOf(u8, header, "} zphp_api;").?;
    try std.testing.expect(pos < end);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, header[pos..end], "(*"));
}
