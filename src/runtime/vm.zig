const std = @import("std");
const Value = @import("value.zig").Value;
const PhpArray = @import("value.zig").PhpArray;
const PhpObject = @import("value.zig").PhpObject;
const Generator = @import("value.zig").Generator;
const Fiber = @import("value.zig").Fiber;
const Chunk = @import("../pipeline/bytecode.zig").Chunk;
const OpCode = @import("../pipeline/bytecode.zig").OpCode;
const ObjFunction = @import("../pipeline/bytecode.zig").ObjFunction;
const CompileResult = @import("../pipeline/compiler.zig").CompileResult;
const enums = @import("../stdlib/enums.zig");

const Allocator = std.mem.Allocator;
pub const RuntimeError = error{ RuntimeError, OutOfMemory };

const TypeInfo = struct {
    param_types: []const []const u8 = &.{},
    return_type: []const u8 = "",
};
var g_type_info: std.StringHashMapUnmanaged(TypeInfo) = .{};
var g_type_info_allocator: ?Allocator = null;

pub const FileLoader = fn (path: []const u8, allocator: Allocator) ?*CompileResult;
pub const NativeContext = struct {
    allocator: Allocator,
    arrays: *std.ArrayListUnmanaged(*PhpArray),
    strings: *std.ArrayListUnmanaged([]const u8),
    vm: *VM,
    call_name: ?[]const u8 = null,

    pub fn createArray(self: *NativeContext) !*PhpArray {
        const arr = try self.allocator.create(PhpArray);
        arr.* = .{};
        try self.arrays.append(self.allocator, arr);
        return arr;
    }

    pub fn createString(self: *NativeContext, data: []const u8) ![]const u8 {
        const owned = try self.allocator.dupe(u8, data);
        try self.strings.append(self.allocator, owned);
        return owned;
    }

    pub fn createObject(self: *NativeContext, class_name: []const u8) !*PhpObject {
        const obj = try self.allocator.create(PhpObject);
        obj.* = .{ .class_name = class_name };
        try self.vm.objects.append(self.allocator, obj);
        return obj;
    }

    pub fn callFunction(self: *NativeContext, name: []const u8, args: []const Value) RuntimeError!Value {
        return self.vm.callByName(name, args);
    }

    pub fn callMethod(self: *NativeContext, obj: *PhpObject, method: []const u8, args: []const Value) RuntimeError!Value {
        return self.vm.callMethod(obj, method, args);
    }

    // write a value back to the caller's variable at the given argument position.
    // uses bytecode scan to find the variable name (best-effort, works for simple variable args)
    pub fn setCallerVar(self: *NativeContext, arg_index: usize, arg_count: usize, value: Value) void {
        const vm = self.vm;
        if (vm.frame_count == 0) return;
        const caller = &vm.frames[vm.frame_count - 1];
        const chunk = caller.chunk;
        // ip points past the call instruction (opcode + u16 name + u8 argc = 4 bytes)
        if (caller.ip < 4) return;
        var scan_pos = caller.ip - 4;
        var arg_vars: [16]?[]const u8 = .{null} ** 16;
        var scan_idx: usize = arg_count;
        while (scan_idx > 0 and scan_pos >= 3) {
            scan_idx -= 1;
            if (chunk.code.items[scan_pos - 3] == @intFromEnum(OpCode.get_var)) {
                const hi = chunk.code.items[scan_pos - 2];
                const lo = chunk.code.items[scan_pos - 1];
                const const_idx = (@as(u16, hi) << 8) | lo;
                if (const_idx < chunk.constants.items.len) {
                    arg_vars[scan_idx] = chunk.constants.items[const_idx].string;
                }
                scan_pos -= 3;
            } else if (chunk.code.items[scan_pos - 3] == @intFromEnum(OpCode.get_local)) {
                const hi = chunk.code.items[scan_pos - 2];
                const lo = chunk.code.items[scan_pos - 1];
                const slot = (@as(u16, hi) << 8) | lo;
                const sn = if (caller.func) |func| func.slot_names else vm.global_slot_names;
                if (slot < sn.len) {
                    arg_vars[scan_idx] = sn[slot];
                }
                scan_pos -= 3;
            } else {
                break;
            }
        }
        if (arg_vars[arg_index]) |var_name| {
            caller.vars.put(vm.allocator, var_name, value) catch return;
            const sn2 = if (caller.func) |func| func.slot_names else vm.global_slot_names;
            for (sn2, 0..) |sn_name, si| {
                if (std.mem.eql(u8, sn_name, var_name)) {
                    if (si < caller.locals.len) caller.locals[si] = value;
                    break;
                }
            }
        }
    }

    pub fn invokeCallable(self: *NativeContext, callable: Value, args: []const Value) RuntimeError!Value {
        if (callable == .string) return self.vm.callByName(callable.string, args);
        if (callable != .array) return error.RuntimeError;
        const arr = callable.array;
        if (arr.entries.items.len != 2) return error.RuntimeError;
        const target = arr.entries.items[0].value;
        const method_val = arr.entries.items[1].value;
        if (method_val != .string) return error.RuntimeError;
        const method = method_val.string;
        if (target == .object) return self.vm.callMethod(target.object, method, args);
        if (target == .string) {
            var buf: [256]u8 = undefined;
            const full = std.fmt.bufPrint(&buf, "{s}::{s}", .{ target.string, method }) catch return error.RuntimeError;
            return self.vm.callByName(full, args);
        }
        return error.RuntimeError;
    }

    pub fn invokeCallableRef(self: *NativeContext, callable: Value, args: []Value) RuntimeError!Value {
        if (callable == .string) return self.vm.callByNameRef(callable.string, args);
        return self.invokeCallable(callable, args);
    }
};

const NativeFn = *const fn (*NativeContext, []const Value) RuntimeError!Value;

const CaptureEntry = struct {
    closure_name: []const u8,
    var_name: []const u8,
    value: Value,
    ref_cell: ?*Value = null,
};

const CaptureRange = struct {
    start: u32,
    len: u16,
    has_refs: bool,
};

pub const ClassDef = struct {
    name: []const u8,
    methods: std.StringHashMapUnmanaged(MethodInfo) = .{},
    properties: std.ArrayListUnmanaged(PropertyDef) = .{},
    static_props: std.StringHashMapUnmanaged(Value) = .{},
    parent: ?[]const u8 = null,
    interfaces: std.ArrayListUnmanaged([]const u8) = .{},
    is_enum: bool = false,
    backed_type: enum(u8) { none = 0, int_type = 1, string_type = 2 } = .none,
    case_order: std.ArrayListUnmanaged([]const u8) = .{},
    slot_layout: ?*PhpObject.SlotLayout = null,

    pub const Visibility = enum(u8) { public = 0, protected = 1, private = 2 };

    const MethodInfo = struct {
        name: []const u8,
        arity: u8,
        is_static: bool = false,
        visibility: Visibility = .public,
    };

    const PropertyDef = struct {
        name: []const u8,
        default: Value,
        visibility: Visibility = .public,
        is_readonly: bool = false,
    };

    fn deinit(self: *ClassDef, allocator: Allocator) void {
        self.methods.deinit(allocator);
        self.properties.deinit(allocator);
        self.static_props.deinit(allocator);
        self.interfaces.deinit(allocator);
        self.case_order.deinit(allocator);
        if (self.slot_layout) |layout| {
            allocator.free(layout.names);
            allocator.free(layout.defaults);
            allocator.destroy(layout);
        }
    }
};

pub const InterfaceDef = struct {
    name: []const u8,
    methods: std.ArrayListUnmanaged([]const u8) = .{},
    parent: ?[]const u8 = null,

    fn deinit(self: *InterfaceDef, allocator: Allocator) void {
        self.methods.deinit(allocator);
    }
};

pub const VM = struct {
    frames: [64]CallFrame = undefined,
    frame_count: usize = 0,
    stack: [256]Value = undefined,
    sp: usize = 0,
    functions: std.StringHashMapUnmanaged(*const ObjFunction) = .{},
    native_fns: std.StringHashMapUnmanaged(NativeFn) = .{},
    output: std.ArrayListUnmanaged(u8) = .{},
    strings: std.ArrayListUnmanaged([]const u8) = .{},
    arrays: std.ArrayListUnmanaged(*PhpArray) = .{},
    objects: std.ArrayListUnmanaged(*PhpObject) = .{},
    generators: std.ArrayListUnmanaged(*Generator) = .{},
    fibers: std.ArrayListUnmanaged(*Fiber) = .{},
    ref_cells: std.ArrayListUnmanaged(*Value) = .{},
    current_fiber: ?*Fiber = null,
    fiber_suspend_pending: bool = false,
    fiber_suspend_value: Value = .null,
    captures: std.ArrayListUnmanaged(CaptureEntry) = .{},
    capture_index: std.StringHashMapUnmanaged(CaptureRange) = .{},
    closure_instance_count: u32 = 0,
    php_constants: std.StringHashMapUnmanaged(Value) = .{},
    classes: std.StringHashMapUnmanaged(ClassDef) = .{},
    interfaces: std.StringHashMapUnmanaged(InterfaceDef) = .{},
    traits: std.StringHashMapUnmanaged(void) = .{},
    statics: std.StringHashMapUnmanaged(Value) = .{},
    static_vars: std.ArrayListUnmanaged(StaticEntry) = .{},
    global_vars: std.ArrayListUnmanaged(StaticEntry) = .{},
    file_loader: ?*const FileLoader = null,
    loaded_files: std.StringHashMapUnmanaged(void) = .{},
    compile_results: std.ArrayListUnmanaged(*CompileResult) = .{},
    error_msg: ?[]const u8 = null,
    exit_requested: bool = false,
    source: []const u8 = "",
    file_path: []const u8 = "",
    autoload_callbacks: std.ArrayListUnmanaged(Value) = .{},
    user_error_handler: ?Value = null,
    prev_error_handler: ?Value = null,
    ob_stack: std.ArrayListUnmanaged(usize) = .{},
    request_vars: std.StringHashMapUnmanaged(Value) = .{},
    exception_handlers: [32]ExceptionHandler = undefined,
    handler_count: usize = 0,
    handler_floor: usize = 0,
    pending_exception: ?Value = null,
    allocator: Allocator,
    global_slot_names: []const []const u8 = &.{},
    global_vars_dirty: bool = false,
    method_cache_class: []const u8 = "",
    method_cache_method: []const u8 = "",
    method_cache_result: []const u8 = "",
    ic: ?*InlineCache = null,

    const InlineCache = struct {
        // property access: keyed by (chunk_ptr ^ ip), stores class_ptr for visibility skip
        prop: [128]PropIC = @splat(.{}),
        // method call: keyed by (chunk_ptr ^ ip), stores class_ptr + resolved func
        method: [128]MethodIC = @splat(.{}),
        // stack-allocated locals for callLocalsOnly - avoids heap alloc/free per call
        locals_buf: [*]Value = undefined,
        locals_sp: usize = 0,
        locals_cap: usize = 0,
        // single-entry function lookup cache
        fn_cache_name: []const u8 = "",
        fn_cache_func: ?*const ObjFunction = null,
        // per-frame sp save for inline call/ret in fastLoop
        sp_save: [64]usize = undefined,
        // per-frame actual arg count for func_get_args
        arg_counts: [64]u8 = [_]u8{0xFF} ** 64,
        // set before pushing a frame, consumed by executeFunction et al
        pending_arg_count: u8 = 0xFF,
        // concat_assign string buffer - avoids O(n) realloc per append
        concat_buf: std.ArrayListUnmanaged(u8) = .{},
        concat_slot: u16 = 0xFFFF,
        concat_frame: usize = 0,

        const PropIC = struct {
            key: usize = 0,
            chunk_key: usize = 0,
            class_ptr: usize = 0,
            slot_index: u16 = 0xFFFF,
        };

        const MethodIC = struct {
            key: usize = 0,
            class_ptr: usize = 0,
            func: ?*const ObjFunction = null,
            native: ?NativeFn = null,
            full_name: []const u8 = "",
        };

        fn propIndex(chunk_ptr: usize, ip: usize) u7 {
            return @truncate((chunk_ptr ^ ip) *% 0x517CC1B727220A95);
        }

        fn methodIndex(chunk_ptr: usize, ip: usize) u7 {
            return @truncate((chunk_ptr ^ ip) *% 0x517CC1B727220A95);
        }
    };

    const StaticEntry = struct {
        var_name: []const u8,
        frame_depth: usize,
    };

    const ExceptionHandler = struct {
        catch_ip: usize, // absolute IP to jump to on throw
        frame_count: usize, // frame count when handler was pushed
        sp: usize, // stack pointer when handler was pushed
        chunk: *const Chunk, // chunk the handler belongs to
    };

    const CallFrame = struct {
        chunk: *const Chunk,
        ip: usize,
        vars: std.StringHashMapUnmanaged(Value),
        locals: []Value = &.{},
        func: ?*const ObjFunction = null,
        generator: ?*Generator = null,
        ref_slots: std.StringHashMapUnmanaged(*Value) = .{},
        called_class: ?[]const u8 = null,
    };

    pub fn init(allocator: Allocator) RuntimeError!VM {
        var vm = VM{ .allocator = allocator };
        try @import("../stdlib/registry.zig").register(&vm.native_fns, allocator);
        try initConstants(&vm.php_constants, allocator);
        try @import("../stdlib/exceptions.zig").register(&vm, allocator);
        try @import("../stdlib/datetime.zig").register(&vm, allocator);
        try @import("../stdlib/spl.zig").register(&vm, allocator);
        try @import("../stdlib/pdo.zig").register(&vm, allocator);
        try @import("../stdlib/websocket.zig").register(&vm, allocator);
        try @import("../stdlib/filesystem.zig").register(&vm, allocator);
        vm.ic = try allocator.create(InlineCache);
        vm.ic.?.* = .{};
        const locals_buf = try allocator.alloc(Value, 8192);
        vm.ic.?.locals_buf = locals_buf.ptr;
        vm.ic.?.locals_cap = 8192;
        return vm;
    }

    fn initConstants(c: *std.StringHashMapUnmanaged(Value), a: Allocator) !void {
        try c.put(a, "TRUE", .{ .bool = true });
        try c.put(a, "FALSE", .{ .bool = false });
        try c.put(a, "NULL", .null);
        try c.put(a, "PHP_EOL", .{ .string = "\n" });
        try c.put(a, "PHP_INT_MAX", .{ .int = std.math.maxInt(i64) });
        try c.put(a, "PHP_INT_MIN", .{ .int = std.math.minInt(i64) });
        try c.put(a, "PHP_INT_SIZE", .{ .int = 8 });
        try c.put(a, "PHP_MAJOR_VERSION", .{ .int = 8 });
        try c.put(a, "PHP_MINOR_VERSION", .{ .int = 4 });
        try c.put(a, "PHP_VERSION", .{ .string = "8.4.0" });
        try c.put(a, "PHP_SAPI", .{ .string = "cli" });
        try c.put(a, "PHP_OS", .{ .string = if (@import("builtin").os.tag == .macos) "Darwin" else "Linux" });
        try c.put(a, "DIRECTORY_SEPARATOR", .{ .string = "/" });
        try c.put(a, "PATH_SEPARATOR", .{ .string = ":" });
        try c.put(a, "STR_PAD_RIGHT", .{ .int = 1 });
        try c.put(a, "STR_PAD_LEFT", .{ .int = 0 });
        try c.put(a, "STR_PAD_BOTH", .{ .int = 2 });
        try c.put(a, "SORT_REGULAR", .{ .int = 0 });
        try c.put(a, "SORT_NUMERIC", .{ .int = 1 });
        try c.put(a, "SORT_STRING", .{ .int = 2 });
        try c.put(a, "SORT_ASC", .{ .int = 4 });
        try c.put(a, "SORT_DESC", .{ .int = 3 });
        try c.put(a, "ARRAY_FILTER_USE_BOTH", .{ .int = 1 });
        try c.put(a, "ARRAY_FILTER_USE_KEY", .{ .int = 2 });
        try c.put(a, "JSON_PRETTY_PRINT", .{ .int = 128 });
        try c.put(a, "JSON_UNESCAPED_SLASHES", .{ .int = 64 });
        try c.put(a, "JSON_UNESCAPED_UNICODE", .{ .int = 256 });
        try c.put(a, "E_ERROR", .{ .int = 1 });
        try c.put(a, "E_WARNING", .{ .int = 2 });
        try c.put(a, "E_NOTICE", .{ .int = 8 });
        try c.put(a, "E_ALL", .{ .int = 32767 });
        try c.put(a, "PHP_FLOAT_MAX", .{ .float = std.math.floatMax(f64) });
        try c.put(a, "PHP_FLOAT_MIN", .{ .float = std.math.floatMin(f64) });
        try c.put(a, "PHP_FLOAT_EPSILON", .{ .float = std.math.floatEps(f64) });
        try c.put(a, "PHP_MAXPATHLEN", .{ .int = 4096 });
        try c.put(a, "M_PI", .{ .float = std.math.pi });
        try c.put(a, "M_E", .{ .float = std.math.e });
        try c.put(a, "M_SQRT2", .{ .float = std.math.sqrt2 });
        try c.put(a, "M_LN2", .{ .float = std.math.ln2 });
        try c.put(a, "M_LN10", .{ .float = @log(10.0) });
        try c.put(a, "INF", .{ .float = std.math.inf(f64) });
        try c.put(a, "NAN", .{ .float = std.math.nan(f64) });
        try c.put(a, "PHP_URL_SCHEME", .{ .int = 0 });
        try c.put(a, "PHP_URL_HOST", .{ .int = 1 });
        try c.put(a, "PHP_URL_PORT", .{ .int = 2 });
        try c.put(a, "PHP_URL_USER", .{ .int = 3 });
        try c.put(a, "PHP_URL_PASS", .{ .int = 4 });
        try c.put(a, "PHP_URL_PATH", .{ .int = 5 });
        try c.put(a, "PHP_URL_QUERY", .{ .int = 6 });
        try c.put(a, "PHP_URL_FRAGMENT", .{ .int = 7 });
        try c.put(a, "PASSWORD_DEFAULT", .{ .int = 1 });
        try c.put(a, "PASSWORD_BCRYPT", .{ .int = 1 });
        try c.put(a, "PREG_SPLIT_DELIM_CAPTURE", .{ .int = 2 });
        try c.put(a, "PREG_SPLIT_NO_EMPTY", .{ .int = 1 });
        try c.put(a, "LOCK_SH", .{ .int = 1 });
        try c.put(a, "LOCK_EX", .{ .int = 2 });
        try c.put(a, "LOCK_UN", .{ .int = 8 });
        try c.put(a, "LOCK_NB", .{ .int = 4 });
        try c.put(a, "FILE_APPEND", .{ .int = 8 });
        try c.put(a, "SEEK_SET", .{ .int = 0 });
        try c.put(a, "SEEK_CUR", .{ .int = 1 });
        try c.put(a, "SEEK_END", .{ .int = 2 });
    }

    fn freeHeapItems(self: *VM) void {
        for (self.strings.items) |s| self.allocator.free(s);
        for (self.arrays.items) |a| {
            a.deinit(self.allocator);
            self.allocator.destroy(a);
        }
        @import("../stdlib/pdo.zig").cleanupResources(self.objects);
        @import("../stdlib/filesystem.zig").cleanupHandles(self.objects);
        for (self.objects.items) |o| {
            o.deinit(self.allocator);
            self.allocator.destroy(o);
        }
        for (self.generators.items) |g| {
            g.deinit(self.allocator);
            self.allocator.destroy(g);
        }
        for (self.fibers.items) |f| {
            self.cleanupFiberFrames(f);
            f.deinit(self.allocator);
            self.allocator.destroy(f);
        }
        for (self.ref_cells.items) |c| self.allocator.destroy(c);
        var statics_iter = self.statics.keyIterator();
        while (statics_iter.next()) |k| self.allocator.free(k.*);
        for (self.compile_results.items) |r| {
            var result = r;
            result.deinit();
            self.allocator.destroy(result);
        }
    }

    fn releaseFrames(self: *VM) void {
        for (0..self.frame_count) |i| {
            self.frames[i].ref_slots.deinit(self.allocator);
            self.frames[i].vars.deinit(self.allocator);
            if (self.frames[i].locals.len > 0) {
                self.freeLocals(self.frames[i].locals);
                self.frames[i].locals = &.{};
            }
        }
    }

    pub fn deinit(self: *VM) void {
        self.releaseFrames();
        self.freeHeapItems();
        if (self.ic) |ic_ptr| {
            ic_ptr.concat_buf.deinit(self.allocator);
            if (ic_ptr.locals_cap > 0) self.allocator.free(ic_ptr.locals_buf[0..ic_ptr.locals_cap]);
            self.allocator.destroy(ic_ptr);
        }
        var ti_iter = g_type_info.valueIterator();
        while (ti_iter.next()) |ti| {
            if (ti.param_types.len > 0) self.allocator.free(ti.param_types);
        }
        g_type_info.deinit(self.allocator);
        g_type_info = .{};
        self.functions.deinit(self.allocator);
        self.native_fns.deinit(self.allocator);
        self.output.deinit(self.allocator);
        self.strings.deinit(self.allocator);
        self.captures.deinit(self.allocator);
        self.capture_index.deinit(self.allocator);
        self.php_constants.deinit(self.allocator);
        self.arrays.deinit(self.allocator);
        self.objects.deinit(self.allocator);
        self.generators.deinit(self.allocator);
        self.fibers.deinit(self.allocator);
        self.ref_cells.deinit(self.allocator);
        var class_iter = self.classes.valueIterator();
        while (class_iter.next()) |c| c.deinit(self.allocator);
        self.classes.deinit(self.allocator);
        var iface_iter = self.interfaces.valueIterator();
        while (iface_iter.next()) |i| i.deinit(self.allocator);
        self.interfaces.deinit(self.allocator);
        self.traits.deinit(self.allocator);
        self.statics.deinit(self.allocator);
        self.static_vars.deinit(self.allocator);
        self.global_vars.deinit(self.allocator);
        self.loaded_files.deinit(self.allocator);
        self.compile_results.deinit(self.allocator);
        self.ob_stack.deinit(self.allocator);
        self.request_vars.deinit(self.allocator);
        self.autoload_callbacks.deinit(self.allocator);
    }

    pub fn reset(self: *VM) void {
        self.releaseFrames();
        self.freeHeapItems();
        self.frame_count = 0;
        self.sp = 0;
        self.handler_count = 0;
        self.handler_floor = 0;
        self.current_fiber = null;
        self.fiber_suspend_pending = false;
        self.fiber_suspend_value = .null;
        self.error_msg = null;
        self.output.clearRetainingCapacity();
        self.strings.clearRetainingCapacity();
        self.arrays.clearRetainingCapacity();
        self.objects.clearRetainingCapacity();
        self.generators.clearRetainingCapacity();
        self.fibers.clearRetainingCapacity();
        self.ref_cells.clearRetainingCapacity();
        self.captures.clearRetainingCapacity();
        self.capture_index.clearRetainingCapacity();
        self.ob_stack.clearRetainingCapacity();
        self.request_vars.clearRetainingCapacity();
        self.statics.clearRetainingCapacity();
        self.static_vars.clearRetainingCapacity();
        self.global_vars.clearRetainingCapacity();
        self.loaded_files.clearRetainingCapacity();
        self.compile_results.clearRetainingCapacity();
    }

    pub fn interpret(self: *VM, result: *const CompileResult) RuntimeError!void {
        for (result.functions.items) |*func| {
            try self.registerFunction(func);
        }
        for (result.type_hints.items) |th| {
            try g_type_info.put(self.allocator, th.name, .{ .param_types = th.param_types, .return_type = th.return_type });
        }
        var vars: std.StringHashMapUnmanaged(Value) = .{};
        var it = self.request_vars.iterator();
        while (it.next()) |entry| {
            try vars.put(self.allocator, entry.key_ptr.*, entry.value_ptr.*);
        }
        var locals: []Value = &.{};
        if (result.local_count > 0) {
            locals = try self.allocator.alloc(Value, result.local_count);
            @memset(locals, .null);
            for (result.slot_names, 0..) |sn, i| {
                if (sn.len > 0) {
                    if (vars.get(sn)) |val| locals[i] = val;
                }
            }
        }
        self.global_slot_names = result.slot_names;
        self.source = result.source;
        self.file_path = result.file_path;
        self.frames[0] = .{ .chunk = &result.chunk, .ip = 0, .vars = vars, .locals = locals };
        self.frame_count = 1;
        try self.run();
    }

    pub fn registerFunction(self: *VM, func: *const ObjFunction) RuntimeError!void {
        if (self.functions.contains(func.name)) {
            const msg = std.fmt.allocPrint(self.allocator, "PHP Fatal error:  Cannot redeclare {s}()\n", .{func.name}) catch return error.RuntimeError;
            self.error_msg = msg;
            return error.RuntimeError;
        }
        try self.functions.put(self.allocator, func.name, func);
    }

    fn runUntilFrame(self: *VM, base_frame: usize) RuntimeError!void {
        if (self.frame_count <= base_frame) return;
        return self.runLoop(base_frame);
    }

    pub fn run(self: *VM) RuntimeError!void {
        return self.runLoop(0);
    }

    fn runLoop(self: *VM, base_frame: usize) RuntimeError!void {
        while (true) {
            const op: OpCode = @enumFromInt(self.readByte());
            switch (op) {
                .constant => {
                    const idx = self.readU16();
                    self.push(self.currentChunk().constants.items[idx]);
                },
                .op_null => self.push(.null),
                .op_true => self.push(.{ .bool = true }),
                .op_false => self.push(.{ .bool = false }),
                .pop => _ = self.pop(),
                .dup => self.push(self.stack[self.sp - 1]),

                .get_var => {
                    const idx = self.readU16();
                    const name = self.currentChunk().constants.items[idx].string;
                    if (self.currentFrame().ref_slots.get(name)) |cell| {
                        self.push(cell.*);
                    } else if (self.currentFrame().vars.get(name)) |val| {
                        self.push(val);
                    } else if (self.php_constants.get(name)) |val| {
                        self.push(val);
                    } else {
                        self.push(.null);
                    }
                },
                .set_var => {
                    const idx = self.readU16();
                    const name = self.currentChunk().constants.items[idx].string;
                    const val = try self.copyValue(self.peek());
                    if (self.currentFrame().ref_slots.get(name)) |cell| {
                        cell.* = val;
                    } else {
                        try self.currentFrame().vars.put(self.allocator, name, val);
                    }
                    const sv_sn = if (self.currentFrame().func) |func| func.slot_names else self.global_slot_names;
                    for (sv_sn, 0..) |sn, si| {
                        if (std.mem.eql(u8, sn, name)) {
                            if (si < self.currentFrame().locals.len) self.currentFrame().locals[si] = val;
                            break;
                        }
                    }
                },

                .add => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(Value.add(a, b));
                },
                .subtract => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(Value.subtract(a, b));
                },
                .multiply => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(Value.multiply(a, b));
                },
                .divide => {
                    const b = self.pop();
                    const a = self.pop();
                    const bv = Value.toFloat(b);
                    if (bv == 0.0) {
                        if (try self.throwBuiltinException("DivisionByZeroError", "Division by zero")) continue;
                        return error.RuntimeError;
                    }
                    self.push(Value.divide(a, b));
                },
                .modulo => {
                    const b = self.pop();
                    const a = self.pop();
                    const bi = Value.toInt(b);
                    if (bi == 0) {
                        if (try self.throwBuiltinException("DivisionByZeroError", "Modulo by zero")) continue;
                        return error.RuntimeError;
                    }
                    self.push(Value.modulo(a, b));
                },
                .power => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(Value.power(a, b));
                },
                .negate => {
                    const v = self.pop();
                    self.push(v.negate());
                },
                .concat => {
                    const b = self.pop();
                    const a = self.pop();
                    // fast path: both strings
                    if (a == .string and b == .string) {
                        const as = a.string;
                        const bs = b.string;
                        const owned = try self.allocator.alloc(u8, as.len + bs.len);
                        @memcpy(owned[0..as.len], as);
                        @memcpy(owned[as.len..], bs);
                        try self.strings.append(self.allocator, owned);
                        self.push(.{ .string = owned });
                    } else {
                        var buf = std.ArrayListUnmanaged(u8){};
                        if (a == .object) {
                            try buf.appendSlice(self.allocator, try self.objectToString(a.object));
                        } else try a.format(&buf, self.allocator);
                        if (b == .object) {
                            try buf.appendSlice(self.allocator, try self.objectToString(b.object));
                        } else try b.format(&buf, self.allocator);
                        const owned = try buf.toOwnedSlice(self.allocator);
                        try self.strings.append(self.allocator, owned);
                        self.push(.{ .string = owned });
                    }
                },

                .bit_and => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(.{ .int = Value.toInt(a) & Value.toInt(b) });
                },
                .bit_or => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(.{ .int = Value.toInt(a) | Value.toInt(b) });
                },
                .bit_xor => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(.{ .int = Value.toInt(a) ^ Value.toInt(b) });
                },
                .bit_not => {
                    const v = self.pop();
                    self.push(.{ .int = ~Value.toInt(v) });
                },
                .shift_left => {
                    const b = self.pop();
                    const a = self.pop();
                    const shift: u6 = @intCast(@min(63, @max(0, Value.toInt(b))));
                    self.push(.{ .int = Value.toInt(a) << shift });
                },
                .shift_right => {
                    const b = self.pop();
                    const a = self.pop();
                    const shift: u6 = @intCast(@min(63, @max(0, Value.toInt(b))));
                    self.push(.{ .int = Value.toInt(a) >> shift });
                },

                .equal => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(.{ .bool = Value.equal(a, b) });
                },
                .not_equal => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(.{ .bool = !Value.equal(a, b) });
                },
                .identical => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(.{ .bool = Value.identical(a, b) });
                },
                .not_identical => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(.{ .bool = !Value.identical(a, b) });
                },
                .less => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(.{ .bool = Value.lessThan(a, b) });
                },
                .less_equal => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(.{ .bool = !Value.lessThan(b, a) });
                },
                .greater => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(.{ .bool = Value.lessThan(b, a) });
                },
                .greater_equal => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(.{ .bool = !Value.lessThan(a, b) });
                },
                .spaceship => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(.{ .int = Value.compare(a, b) });
                },

                .not => {
                    const v = self.pop();
                    self.push(.{ .bool = !v.isTruthy() });
                },

                .jump => {
                    const offset = self.readU16();
                    self.currentFrame().ip += offset;
                },
                .jump_back => {
                    const offset = self.readU16();
                    self.currentFrame().ip -= offset;
                    if (self.currentFrame().locals.len > 0) {
                        try self.fastLoop();
                        if (self.frame_count <= base_frame) return;
                    }
                },
                .jump_if_false => {
                    const offset = self.readU16();
                    if (!self.peek().isTruthy()) self.currentFrame().ip += offset;
                },
                .jump_if_true => {
                    const offset = self.readU16();
                    if (self.peek().isTruthy()) self.currentFrame().ip += offset;
                },
                .jump_if_not_null => {
                    const offset = self.readU16();
                    if (!self.peek().isNull()) self.currentFrame().ip += offset;
                },

                .call => {
                    const name_idx = self.readU16();
                    const arg_count = self.readByte();
                    const name = self.currentChunk().constants.items[name_idx].string;
                    if (self.global_vars_dirty) try self.syncGlobalLocalsToVars();
                    try self.callNamedFunction(name, arg_count);
                },
                .call_indirect => {
                    if (self.global_vars_dirty) try self.syncGlobalLocalsToVars();
                    const arg_count = self.readByte();
                    const ac: usize = arg_count;
                    const name_val = self.stack[self.sp - ac - 1];
                    if (name_val == .string) {
                        const name = name_val.string;
                        var i: usize = 0;
                        while (i < ac) : (i += 1) {
                            self.stack[self.sp - ac - 1 + i] = self.stack[self.sp - ac + i];
                        }
                        self.sp -= 1;
                        try self.callNamedFunction(name, arg_count);
                    } else if (name_val == .object) {
                        var args_buf: [16]Value = undefined;
                        for (0..ac) |i| args_buf[i] = self.stack[self.sp - ac + i];
                        self.sp -= ac + 1;
                        const result = try self.callMethod(name_val.object, "__invoke", args_buf[0..ac]);
                        self.push(result);
                    } else if (name_val == .array) {
                        const arr = name_val.array;
                        if (arr.entries.items.len != 2) {
                            self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught TypeError: Array callback must have exactly two elements", .{}) catch null;
                            return error.RuntimeError;
                        }
                        const target = arr.entries.items[0].value;
                        const method_val = arr.entries.items[1].value;
                        if (method_val != .string) {
                            self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught TypeError: Method name must be a string", .{}) catch null;
                            return error.RuntimeError;
                        }
                        const method = method_val.string;
                        var args_buf: [16]Value = undefined;
                        for (0..ac) |i| args_buf[i] = self.stack[self.sp - ac + i];
                        self.sp -= ac + 1;
                        var ctx = self.makeContext(null);
                        const result = if (target == .object)
                            try ctx.vm.callMethod(target.object, method, args_buf[0..ac])
                        else if (target == .string) blk: {
                            var buf: [256]u8 = undefined;
                            const full = std.fmt.bufPrint(&buf, "{s}::{s}", .{ target.string, method }) catch return error.RuntimeError;
                            break :blk try ctx.vm.callByName(full, args_buf[0..ac]);
                        } else {
                            self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught TypeError: Value of type {s} is not callable", .{valueTypeName(target)}) catch null;
                            return error.RuntimeError;
                        };
                        self.push(result);
                    } else {
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught TypeError: Value of type {s} is not callable", .{valueTypeName(name_val)}) catch null;
                        return error.RuntimeError;
                    }
                },
                .call_spread => {
                    if (self.global_vars_dirty) try self.syncGlobalLocalsToVars();
                    const name_idx = self.readU16();
                    const name = self.currentChunk().constants.items[name_idx].string;
                    const args_val = self.pop();
                    if (args_val != .array) {
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught TypeError: Argument unpacking requires an array", .{}) catch null;
                        return error.RuntimeError;
                    }
                    const arr = args_val.array;
                    // check if any args are named (string keys)
                    var has_named = false;
                    for (arr.entries.items) |entry| {
                        if (entry.key == .string) { has_named = true; break; }
                    }
                    if (has_named) {
                        if (self.functions.get(name)) |func| {
                            // resolve named args to positional
                            var resolved: [16]Value = .{.null} ** 16;
                            var pos: usize = 0;
                            for (arr.entries.items) |entry| {
                                if (entry.key == .string) {
                                    for (func.params, 0..) |p, pi| {
                                        if (std.mem.eql(u8, p[1..], entry.key.string) or std.mem.eql(u8, p, entry.key.string)) {
                                            resolved[pi] = entry.value;
                                            if (pi >= pos) pos = pi + 1;
                                            break;
                                        }
                                    }
                                } else {
                                    resolved[pos] = entry.value;
                                    pos += 1;
                                }
                            }
                            // fill defaults
                            const count = @max(pos, func.required_params);
                            for (0..count) |i| {
                                if (resolved[i] == .null and i < func.defaults.len) {
                                    resolved[i] = func.defaults[i];
                                }
                            }
                            for (0..count) |i| self.push(resolved[i]);
                            try self.callNamedFunction(name, @intCast(count));
                        } else if (@import("../stdlib/native_params.zig").map.get(name)) |params| {
                            var resolved: [16]Value = .{.null} ** 16;
                            var pos: usize = 0;
                            for (arr.entries.items) |entry| {
                                if (entry.key == .string) {
                                    for (params, 0..) |p, pi| {
                                        if (std.mem.eql(u8, p[1..], entry.key.string) or std.mem.eql(u8, p, entry.key.string)) {
                                            resolved[pi] = entry.value;
                                            if (pi >= pos) pos = pi + 1;
                                            break;
                                        }
                                    }
                                } else {
                                    resolved[pos] = entry.value;
                                    pos += 1;
                                }
                            }
                            for (0..pos) |i| self.push(resolved[i]);
                            try self.callNamedFunction(name, @intCast(pos));
                        } else {
                            for (arr.entries.items) |entry| self.push(entry.value);
                            try self.callNamedFunction(name, @intCast(arr.entries.items.len));
                        }
                    } else {
                        for (arr.entries.items) |entry| self.push(entry.value);
                        try self.callNamedFunction(name, @intCast(arr.entries.items.len));
                    }
                },
                .call_indirect_spread => {
                    // stack: [... args_array, func_name]
                    const name_val = self.pop();
                    const args_val = self.pop();
                    if (args_val != .array or name_val != .string) {
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught TypeError: Value of type {s} is not callable", .{valueTypeName(name_val)}) catch null;
                        return error.RuntimeError;
                    }
                    const arr = args_val.array;
                    for (arr.entries.items) |entry| {
                        self.push(entry.value);
                    }
                    const ac: u8 = @intCast(arr.entries.items.len);
                    try self.callNamedFunction(name_val.string, ac);
                },
                .return_val => {
                    const result = self.pop();
                    if (g_type_info.count() > 0) {
                        if (try self.checkReturnType(result)) continue;
                    }
                    try self.popFrame();
                    self.push(result);
                    if (self.frame_count <= base_frame) return;
                },
                .return_void => {
                    try self.popFrame();
                    self.push(.null);
                    if (self.frame_count <= base_frame) return;
                },

                .echo => {
                    const v = self.pop();
                    if (v == .object) {
                        const s = try self.objectToString(v.object);
                        try self.output.appendSlice(self.allocator, s);
                    } else {
                        try v.format(&self.output, self.allocator);
                    }
                },
                .halt => return,

                .array_new => {
                    const arr = try self.allocator.create(PhpArray);
                    arr.* = .{};
                    try self.arrays.append(self.allocator, arr);
                    self.push(.{ .array = arr });
                },
                .array_push => {
                    const val = self.pop();
                    const arr_val = self.peek();
                    if (arr_val == .array) {
                        try arr_val.array.append(self.allocator, val);
                    } else if (arr_val == .object and self.hasMethod(arr_val.object.class_name, "offsetSet")) {
                        _ = self.callMethod(arr_val.object, "offsetSet", &.{ .null, val }) catch {};
                    }
                },
                .array_set_elem => {
                    const val = self.pop();
                    const key = self.pop();
                    const arr_val = self.peek();
                    if (arr_val == .array) {
                        try arr_val.array.set(self.allocator, Value.toArrayKey(key), val);
                    } else if (arr_val == .object and self.hasMethod(arr_val.object.class_name, "offsetSet")) {
                        _ = self.callMethod(arr_val.object, "offsetSet", &.{ key, val }) catch {};
                    }
                },
                .array_get => {
                    const key = self.pop();
                    const arr_val = self.pop();
                    if (arr_val == .array) {
                        self.push(arr_val.array.get(Value.toArrayKey(key)));
                    } else if (arr_val == .object and self.hasMethod(arr_val.object.class_name, "offsetGet")) {
                        const result = self.callMethod(arr_val.object, "offsetGet", &.{key}) catch .null;
                        self.push(result);
                    } else if (arr_val == .string) {
                        const s = arr_val.string;
                        const idx = Value.toInt(key);
                        if (idx >= 0 and @as(usize, @intCast(idx)) < s.len) {
                            self.push(.{ .string = s[@intCast(idx)..][0..1] });
                        } else {
                            self.push(.null);
                        }
                    } else {
                        self.push(.null);
                    }
                },
                .array_get_vivify => {
                    const key = self.pop();
                    const arr_val = self.pop();
                    if (arr_val == .array) {
                        const arr_key = Value.toArrayKey(key);
                        const existing = arr_val.array.get(arr_key);
                        if (existing != .null) {
                            if (existing == .array) {
                                self.push(existing);
                            } else {
                                const new_arr = try self.allocator.create(PhpArray);
                                new_arr.* = .{};
                                try self.arrays.append(self.allocator, new_arr);
                                const new_val = Value{ .array = new_arr };
                                try arr_val.array.set(self.allocator, arr_key, new_val);
                                self.push(new_val);
                            }
                        } else {
                            const new_arr = try self.allocator.create(PhpArray);
                            new_arr.* = .{};
                            try self.arrays.append(self.allocator, new_arr);
                            const new_val = Value{ .array = new_arr };
                            try arr_val.array.set(self.allocator, arr_key, new_val);
                            self.push(new_val);
                        }
                    } else {
                        self.push(.null);
                    }
                },
                .array_set => {
                    const val = self.pop();
                    const key = self.pop();
                    const arr_val = self.pop();
                    if (arr_val == .array) {
                        try arr_val.array.set(self.allocator, Value.toArrayKey(key), val);
                    } else if (arr_val == .object and self.hasMethod(arr_val.object.class_name, "offsetSet")) {
                        _ = self.callMethod(arr_val.object, "offsetSet", &.{ key, val }) catch {};
                    }
                    self.push(val);
                },

                .iter_begin => {
                    const iterable = self.stack[self.sp - 1];
                    if (iterable == .generator) {
                        try self.resumeGenerator(iterable.generator, .null);
                        self.push(.{ .int = -1 }); // sentinel: -1 means generator iteration
                    } else {
                        self.push(.{ .int = 0 });
                    }
                },
                .iter_check => {
                    const offset = self.readU16();
                    const idx_val = self.stack[self.sp - 1];
                    const iterable = self.stack[self.sp - 2];

                    if (iterable == .generator) {
                        const gen = iterable.generator;
                        if (gen.state == .completed) {
                            self.currentFrame().ip += offset;
                        } else {
                            self.push(gen.current_key);
                            self.push(gen.current_value);
                        }
                    } else if (iterable == .array) {
                        const idx = Value.toInt(idx_val);
                        if (idx >= iterable.array.length()) {
                            self.currentFrame().ip += offset;
                        } else {
                            const entry = iterable.array.entries.items[@intCast(idx)];
                            const key_val: Value = switch (entry.key) {
                                .int => |i| .{ .int = i },
                                .string => |s| .{ .string = s },
                            };
                            self.push(key_val);
                            self.push(entry.value);
                        }
                    } else {
                        self.currentFrame().ip += offset;
                    }
                },
                .iter_advance => {
                    const iterable = self.stack[self.sp - 2];
                    if (iterable == .generator) {
                        try self.resumeGenerator(iterable.generator, .null);
                    } else {
                        const idx = self.pop();
                        self.push(.{ .int = Value.toInt(idx) + 1 });
                    }
                },
                .iter_end => {
                    _ = self.pop();
                    _ = self.pop();
                },

                .unset_var => {
                    const idx = self.readU16();
                    const name = self.currentChunk().constants.items[idx].string;
                    _ = self.currentFrame().vars.remove(name);
                },
                .unset_prop => {
                    const name_idx = self.readU16();
                    const prop_name = self.currentChunk().constants.items[name_idx].string;
                    const obj_val = self.pop();
                    if (obj_val == .object) {
                        const obj = obj_val.object;
                        if (self.hasMethod(obj.class_name, "__unset")) {
                            _ = self.callMethod(obj, "__unset", &.{.{ .string = prop_name }}) catch {};
                        } else {
                            if (obj.slots) |s| {
                                if (obj.getSlotIndex(prop_name)) |idx| {
                                    s[idx] = .null;
                                } else {
                                    _ = obj.properties.remove(prop_name);
                                }
                            } else {
                                _ = obj.properties.remove(prop_name);
                            }
                        }
                    }
                },
                .unset_array_elem => {
                    const key = self.pop();
                    const arr_val = self.pop();
                    if (arr_val == .array) {
                        arr_val.array.remove(Value.toArrayKey(key));
                    } else if (arr_val == .object) {
                        if (self.hasMethod(arr_val.object.class_name, "offsetUnset")) {
                            _ = self.callMethod(arr_val.object, "offsetUnset", &.{key}) catch {};
                        }
                    }
                },
                .concat_assign => {
                    if (self.global_vars_dirty) try self.syncGlobalLocalsToVars();
                    const name_idx = self.readU16();
                    const name = self.currentChunk().constants.items[name_idx].string;
                    const append_val = self.pop();
                    const is_ref = self.currentFrame().ref_slots.get(name);

                    // find the local slot for this variable
                    const ca_sn = if (self.currentFrame().func) |func| func.slot_names else self.global_slot_names;
                    var ca_slot: u16 = 0xFFFF;
                    for (ca_sn, 0..) |sn, si| {
                        if (std.mem.eql(u8, sn, name)) {
                            ca_slot = @intCast(si);
                            break;
                        }
                    }

                    // try growable buffer path for local variables (no refs)
                    if (ca_slot != 0xFFFF and is_ref == null and self.ic != null) {
                        const ic = self.ic.?;
                        const current = if (ca_slot < self.currentFrame().locals.len) self.currentFrame().locals[ca_slot] else Value.null;

                        // check if we can reuse the existing buffer
                        if (ic.concat_slot == ca_slot and ic.concat_frame == self.frame_count and ic.concat_buf.items.len > 0) {
                            // verify the local still points into our buffer
                            if (current == .string and current.string.len > 0 and
                                ic.concat_buf.items.len >= current.string.len and
                                current.string.ptr == ic.concat_buf.items.ptr)
                            {
                                // append directly to the buffer
                                if (append_val == .string) {
                                    try ic.concat_buf.appendSlice(self.allocator, append_val.string);
                                } else {
                                    try append_val.format(&ic.concat_buf, self.allocator);
                                }
                                const result_val = Value{ .string = ic.concat_buf.items };
                                self.currentFrame().locals[ca_slot] = result_val;
                                try self.currentFrame().vars.put(self.allocator, name, result_val);
                                self.push(result_val);
                                continue;
                            }
                        }

                        // finalize old buffer: copy its contents to a standalone allocation
                        // so the previous variable's string isn't corrupted
                        if (ic.concat_buf.items.len > 0 and ic.concat_slot != 0xFFFF) {
                            const old_str = try self.allocator.alloc(u8, ic.concat_buf.items.len);
                            @memcpy(old_str, ic.concat_buf.items);
                            try self.strings.append(self.allocator, old_str);
                            // update the old variable to point to the standalone copy
                            if (ic.concat_frame == self.frame_count and ic.concat_slot < self.currentFrame().locals.len) {
                                const old_val = self.currentFrame().locals[ic.concat_slot];
                                if (old_val == .string and old_val.string.ptr == ic.concat_buf.items.ptr) {
                                    self.currentFrame().locals[ic.concat_slot] = .{ .string = old_str };
                                }
                            }
                        }
                        ic.concat_buf.clearRetainingCapacity();
                        if (current == .string) {
                            try ic.concat_buf.appendSlice(self.allocator, current.string);
                        } else if (current != .null) {
                            try current.format(&ic.concat_buf, self.allocator);
                        }
                        if (append_val == .string) {
                            try ic.concat_buf.appendSlice(self.allocator, append_val.string);
                        } else {
                            try append_val.format(&ic.concat_buf, self.allocator);
                        }
                        ic.concat_slot = ca_slot;
                        ic.concat_frame = self.frame_count;
                        const result_val = Value{ .string = ic.concat_buf.items };
                        self.currentFrame().locals[ca_slot] = result_val;
                        try self.currentFrame().vars.put(self.allocator, name, result_val);
                        self.push(result_val);
                        continue;
                    }

                    // fallback: allocate new string each time (ref variables, no IC, no slot)
                    const current = if (is_ref) |cell| cell.* else (self.currentFrame().vars.get(name) orelse .null);
                    var result_str: []const u8 = undefined;
                    if (current == .string and append_val == .string) {
                        const cs = current.string;
                        const as = append_val.string;
                        const new_str = try self.allocator.alloc(u8, cs.len + as.len);
                        @memcpy(new_str[0..cs.len], cs);
                        @memcpy(new_str[cs.len..], as);
                        try self.strings.append(self.allocator, new_str);
                        result_str = new_str;
                    } else {
                        var buf = std.ArrayListUnmanaged(u8){};
                        if (current == .string) {
                            try buf.appendSlice(self.allocator, current.string);
                        } else {
                            try current.format(&buf, self.allocator);
                        }
                        if (append_val == .string) {
                            try buf.appendSlice(self.allocator, append_val.string);
                        } else {
                            try append_val.format(&buf, self.allocator);
                        }
                        const owned = try buf.toOwnedSlice(self.allocator);
                        try self.strings.append(self.allocator, owned);
                        result_str = owned;
                    }
                    const result_val = Value{ .string = result_str };
                    if (is_ref) |cell| {
                        cell.* = result_val;
                    }
                    try self.currentFrame().vars.put(self.allocator, name, result_val);
                    if (ca_slot != 0xFFFF and ca_slot < self.currentFrame().locals.len) {
                        self.currentFrame().locals[ca_slot] = result_val;
                    }
                    self.push(result_val);
                },
                .get_local => {
                    const slot = self.readU16();
                    const frame = self.currentFrame();
                    if (frame.func) |func| {
                        if (slot < func.slot_names.len and func.slot_names[slot].len > 0) {
                            if (frame.ref_slots.get(func.slot_names[slot])) |cell| {
                                self.push(cell.*);
                                continue;
                            }
                        }
                        if (slot < frame.locals.len) {
                            self.push(frame.locals[slot]);
                        } else {
                            self.push(.null);
                        }
                    } else {
                        self.push(self.getLocalGlobal(slot, frame));
                    }
                },
                .set_local => {
                    const slot = self.readU16();
                    const frame = self.currentFrame();
                    const peeked = self.peek();
                    const val = if (peeked == .array) try self.copyValue(peeked) else peeked;
                    if (slot < frame.locals.len) {
                        frame.locals[slot] = val;
                    }
                    if (frame.func) |func| {
                        if (slot < func.slot_names.len) {
                            const name = func.slot_names[slot];
                            if (name.len > 0) {
                                if (frame.ref_slots.get(name)) |cell| {
                                    cell.* = val;
                                }
                                try frame.vars.put(self.allocator, name, val);
                            }
                        }
                    } else {
                        self.setLocalGlobal(slot, val, frame);
                    }
                },
                .inc_local => {
                    const slot = self.readU16();
                    const frame_il = self.currentFrame();
                    if (slot < frame_il.locals.len) {
                        const v = frame_il.locals[slot];
                        frame_il.locals[slot] = if (v == .int) .{ .int = v.int +% 1 } else if (v == .float) .{ .float = v.float + 1.0 } else Value.add(v, .{ .int = 1 });
                    }
                },
                .dec_local => {
                    const slot = self.readU16();
                    const frame_dl = self.currentFrame();
                    if (slot < frame_dl.locals.len) {
                        const v = frame_dl.locals[slot];
                        frame_dl.locals[slot] = if (v == .int) .{ .int = v.int -% 1 } else if (v == .float) .{ .float = v.float - 1.0 } else Value.subtract(v, .{ .int = 1 });
                    }
                },
                .add_local_to_local => {
                    const src_slot = self.readU16();
                    const dst_slot = self.readU16();
                    const frame_al = self.currentFrame();
                    if (src_slot < frame_al.locals.len and dst_slot < frame_al.locals.len) {
                        const src = frame_al.locals[src_slot];
                        const dst = frame_al.locals[dst_slot];
                        frame_al.locals[dst_slot] = if (src == .int and dst == .int) .{ .int = dst.int +% src.int } else if (src == .float and dst == .float) .{ .float = dst.float + src.float } else Value.add(dst, src);
                    }
                },
                .sub_local_to_local => {
                    const src_slot = self.readU16();
                    const dst_slot = self.readU16();
                    const frame_sl = self.currentFrame();
                    if (src_slot < frame_sl.locals.len and dst_slot < frame_sl.locals.len) {
                        const src = frame_sl.locals[src_slot];
                        const dst = frame_sl.locals[dst_slot];
                        frame_sl.locals[dst_slot] = if (src == .int and dst == .int) .{ .int = dst.int -% src.int } else if (src == .float and dst == .float) .{ .float = dst.float - src.float } else Value.subtract(dst, src);
                    }
                },
                .mul_local_to_local => {
                    const src_slot = self.readU16();
                    const dst_slot = self.readU16();
                    const frame_ml = self.currentFrame();
                    if (src_slot < frame_ml.locals.len and dst_slot < frame_ml.locals.len) {
                        const src = frame_ml.locals[src_slot];
                        const dst = frame_ml.locals[dst_slot];
                        frame_ml.locals[dst_slot] = if (src == .int and dst == .int) .{ .int = dst.int *% src.int } else if (src == .float and dst == .float) .{ .float = dst.float * src.float } else Value.multiply(dst, src);
                    }
                },
                .less_local_local_jif => {
                    const slot_a = self.readU16();
                    const slot_b = self.readU16();
                    const offset = self.readU16();
                    const frame_lj = self.currentFrame();
                    const a = if (slot_a < frame_lj.locals.len) frame_lj.locals[slot_a] else Value.null;
                    const b = if (slot_b < frame_lj.locals.len) frame_lj.locals[slot_b] else Value.null;
                    const is_less = if (a == .int and b == .int) a.int < b.int else if (a == .float and b == .float) a.float < b.float else Value.lessThan(a, b);
                    if (!is_less) frame_lj.ip += offset;
                },
                .isset_prop => {
                    const name_idx = self.readU16();
                    const prop_name = self.currentChunk().constants.items[name_idx].string;
                    const obj_val = self.pop();
                    if (obj_val == .object) {
                        const obj = obj_val.object;
                        if (obj.properties.contains(prop_name) or (obj.slots != null and obj.getSlotIndex(prop_name) != null)) {
                            self.push(.{ .bool = obj.get(prop_name) != .null });
                        } else if (self.hasMethod(obj.class_name, "__isset")) {
                            const result = self.callMethod(obj, "__isset", &.{.{ .string = prop_name }}) catch Value{ .bool = false };
                            self.push(.{ .bool = result.isTruthy() });
                        } else {
                            self.push(.{ .bool = false });
                        }
                    } else {
                        self.push(.{ .bool = false });
                    }
                },
                .isset_index => {
                    const key = self.pop();
                    const arr_val = self.pop();
                    if (arr_val == .object and self.hasMethod(arr_val.object.class_name, "offsetExists")) {
                        const result = self.callMethod(arr_val.object, "offsetExists", &.{key}) catch Value{ .bool = false };
                        self.push(.{ .bool = result.isTruthy() });
                    } else if (arr_val == .array) {
                        const v = arr_val.array.get(Value.toArrayKey(key));
                        self.push(.{ .bool = v != .null });
                    } else if (arr_val == .string) {
                        const idx = Value.toInt(key);
                        self.push(.{ .bool = idx >= 0 and @as(usize, @intCast(idx)) < arr_val.string.len });
                    } else {
                        self.push(.{ .bool = false });
                    }
                },
                .clone_obj => {
                    const val = self.pop();
                    if (val == .object) {
                        const src = val.object;
                        const copy = try self.allocator.create(PhpObject);
                        copy.* = .{ .class_name = src.class_name };
                        if (src.slots) |src_slots| {
                            const new_slots = try self.allocator.alloc(Value, src_slots.len);
                            for (src_slots, 0..) |sv, i| {
                                new_slots[i] = try self.copyValue(sv);
                            }
                            copy.slots = new_slots;
                            copy.slot_layout = src.slot_layout;
                        }
                        var it = src.properties.iterator();
                        while (it.next()) |entry| {
                            try copy.properties.put(self.allocator, entry.key_ptr.*, try self.copyValue(entry.value_ptr.*));
                        }
                        try self.objects.append(self.allocator, copy);
                        if (self.hasMethod(src.class_name, "__clone")) {
                            _ = self.callMethod(copy, "__clone", &.{}) catch {};
                        }
                        self.push(.{ .object = copy });
                    } else {
                        self.push(val);
                    }
                },

                .cast_int => {
                    const v = self.pop();
                    self.push(.{ .int = Value.toInt(v) });
                },
                .cast_float => {
                    const v = self.pop();
                    self.push(.{ .float = Value.toFloat(v) });
                },
                .cast_string => {
                    const v = self.pop();
                    if (v == .string) {
                        self.push(v);
                    } else if (v == .object) {
                        const s = try self.objectToString(v.object);
                        self.push(.{ .string = s });
                    } else {
                        var buf = std.ArrayListUnmanaged(u8){};
                        try v.format(&buf, self.allocator);
                        const s = try buf.toOwnedSlice(self.allocator);
                        try self.strings.append(self.allocator, s);
                        self.push(.{ .string = s });
                    }
                },
                .cast_bool => {
                    const v = self.pop();
                    self.push(.{ .bool = v.isTruthy() });
                },
                .cast_array => {
                    const v = self.pop();
                    if (v == .array) {
                        self.push(v);
                    } else {
                        const arr = try self.allocator.create(PhpArray);
                        arr.* = .{};
                        try arr.append(self.allocator, v);
                        try self.arrays.append(self.allocator, arr);
                        self.push(.{ .array = arr });
                    }
                },

                .define_const => {
                    const name_idx = self.readU16();
                    const name = self.currentChunk().constants.items[name_idx].string;
                    const val = self.pop();
                    try self.php_constants.put(self.allocator, name, val);
                },

                .closure_bind => {
                    if (self.frame_count == 1) self.global_vars_dirty = true;
                    if (self.global_vars_dirty) try self.syncGlobalLocalsToVars();
                    const var_idx = self.readU16();
                    const var_name = self.currentChunk().constants.items[var_idx].string;
                    try self.ensureClosureInstance();
                    const closure_name = self.peek().string;
                    const val = if (self.currentFrame().ref_slots.get(var_name)) |cell|
                        cell.*
                    else if (self.currentFrame().vars.get(var_name)) |v|
                        v
                    else
                        self.getLocalByName(var_name);
                    const cap_pos: u32 = @intCast(self.captures.items.len);
                    try self.captures.append(self.allocator, .{
                        .closure_name = closure_name,
                        .var_name = var_name,
                        .value = val,
                    });
                    const gop = try self.capture_index.getOrPut(self.allocator, closure_name);
                    if (gop.found_existing) {
                        gop.value_ptr.len += 1;
                    } else {
                        gop.value_ptr.* = .{ .start = cap_pos, .len = 1, .has_refs = false };
                    }
                },

                .closure_bind_ref => {
                    if (self.frame_count == 1) self.global_vars_dirty = true;
                    if (self.global_vars_dirty) try self.syncGlobalLocalsToVars();
                    const var_idx = self.readU16();
                    const var_name = self.currentChunk().constants.items[var_idx].string;
                    try self.ensureClosureInstance();
                    const closure_name = self.peek().string;
                    // get or create a ref cell for this variable
                    const cell = if (self.currentFrame().ref_slots.get(var_name)) |existing|
                        existing
                    else blk: {
                        const c = try self.allocator.create(Value);
                        c.* = self.currentFrame().vars.get(var_name) orelse self.getLocalByName(var_name);
                        try self.ref_cells.append(self.allocator, c);
                        try self.currentFrame().ref_slots.put(self.allocator, var_name, c);
                        break :blk c;
                    };
                    const cap_pos: u32 = @intCast(self.captures.items.len);
                    try self.captures.append(self.allocator, .{
                        .closure_name = closure_name,
                        .var_name = var_name,
                        .value = .null,
                        .ref_cell = cell,
                    });
                    const gop = try self.capture_index.getOrPut(self.allocator, closure_name);
                    if (gop.found_existing) {
                        gop.value_ptr.len += 1;
                        gop.value_ptr.has_refs = true;
                    } else {
                        gop.value_ptr.* = .{ .start = cap_pos, .len = 1, .has_refs = true };
                    }
                },

                .throw => {
                    const exception = self.pop();
                    if (self.handler_count <= self.handler_floor) {
                        self.pending_exception = exception;
                        return error.RuntimeError;
                    }

                    const handler = self.exception_handlers[self.handler_count - 1];
                    self.handler_count -= 1;

                    // unwind frames back to where handler was set
                    while (self.frame_count > handler.frame_count) {
                        self.frame_count -= 1;
                        self.frames[self.frame_count].vars.deinit(self.allocator);
                        if (self.frames[self.frame_count].locals.len > 0) {
                            self.freeLocals(self.frames[self.frame_count].locals);
                            self.frames[self.frame_count].locals = &.{};
                        }
                    }

                    // restore stack and push exception
                    self.sp = handler.sp;
                    self.push(exception);

                    // jump to catch code
                    self.currentFrame().ip = handler.catch_ip;
                },

                .push_handler => {
                    const offset = self.readU16();
                    self.exception_handlers[self.handler_count] = .{
                        .catch_ip = self.currentFrame().ip + offset,
                        .frame_count = self.frame_count,
                        .sp = self.sp,
                        .chunk = self.currentChunk(),
                    };
                    self.handler_count += 1;
                },

                .pop_handler => {
                    if (self.handler_count > 0) self.handler_count -= 1;
                },

                .get_global => {
                    if (self.global_vars_dirty) try self.syncGlobalLocalsToVars();
                    const name_idx = self.readU16();
                    const name = self.currentChunk().constants.items[name_idx].string;
                    const raw_val = if (self.frame_count > 1) blk: {
                        if (self.frames[0].ref_slots.get(name)) |cell| break :blk cell.*;
                        break :blk self.frames[0].vars.get(name) orelse
                            self.php_constants.get(name) orelse .null;
                    } else blk: {
                        if (self.currentFrame().ref_slots.get(name)) |cell| break :blk cell.*;
                        break :blk self.currentFrame().vars.get(name) orelse .null;
                    };
                    const global_val = try self.copyValue(raw_val);
                    try self.currentFrame().vars.put(self.allocator, name, global_val);
                    if (self.frame_count > 1) {
                        try self.global_vars.append(self.allocator, .{
                            .var_name = name,
                            .frame_depth = self.frame_count,
                        });
                    }
                },

                .get_static => {
                    const name_idx = self.readU16();
                    const var_name = self.currentChunk().constants.items[name_idx].string;
                    const val = self.getStaticVar(var_name);
                    self.push(val);
                    // register for writeback on frame exit
                    try self.static_vars.append(self.allocator, .{
                        .var_name = var_name,
                        .frame_depth = self.frame_count,
                    });
                },

                .set_static => {},

                .require => {
                    const variant = self.readByte();
                    const path_val = self.pop();
                    if (path_val != .string) {
                        self.push(.null);
                    } else {
                        const is_once = (variant == 1 or variant == 3);
                        const is_require = (variant == 0 or variant == 1);
                        const path = path_val.string;

                        if (is_once and self.loaded_files.contains(path)) {
                            self.push(.{ .bool = true });
                        } else {
                            if (self.file_loader) |loader| {
                                if (loader(path, self.allocator)) |result| {
                                    try self.loaded_files.put(self.allocator, path, {});
                                    try self.compile_results.append(self.allocator, result);

                                    for (result.functions.items) |*func| {
                                        try self.registerFunction(func);
                                    }
                                    for (result.type_hints.items) |th| {
                                        try g_type_info.put(self.allocator, th.name, .{ .param_types = th.param_types, .return_type = th.return_type });
                                    }

                                    // execute via runUntilFrame so halt pops back here
                                    const return_frame = self.frame_count;
                                    self.frames[self.frame_count] = .{
                                        .chunk = &result.chunk,
                                        .ip = 0,
                                        .vars = .{},
                                    };
                                    self.frame_count += 1;
                                    self.runUntilFrame(return_frame) catch {
                                        if (is_require) {
                                            if (self.error_msg == null and self.pending_exception == null) {
                                                self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: require(): Failed opening required '{s}'", .{path}) catch null;
                                            }
                                            return error.RuntimeError;
                                        }
                                        self.push(.{ .bool = false });
                                        continue;
                                    };
                                    // clean up the included file's frame if halt left it
                                    while (self.frame_count > return_frame) {
                                        self.frame_count -= 1;
                                        self.frames[self.frame_count].vars.deinit(self.allocator);
                                        if (self.frames[self.frame_count].locals.len > 0) {
                                            self.freeLocals(self.frames[self.frame_count].locals);
                                            self.frames[self.frame_count].locals = &.{};
                                        }
                                    }
                                    self.push(.{ .bool = true });
                                } else {
                                    if (is_require) {
                                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: require(): Failed opening required '{s}'", .{path}) catch null;
                                        return error.RuntimeError;
                                    }
                                    self.push(.{ .bool = false });
                                }
                            } else {
                                if (is_require) {
                                    self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: require(): Failed opening required '{s}'", .{path}) catch null;
                                    return error.RuntimeError;
                                }
                                self.push(.{ .bool = false });
                            }
                        }
                    }
                },

                .array_spread => {
                    const src = self.pop();
                    if (src == .array) {
                        const target = self.peek();
                        if (target == .array) {
                            for (src.array.entries.items) |entry| {
                                if (entry.key == .string) {
                                    try target.array.set(self.allocator, entry.key, entry.value);
                                } else {
                                    try target.array.append(self.allocator, entry.value);
                                }
                            }
                        }
                    }
                },
                .splat_call => {},

                .instance_check => {
                    const class_name_val = self.pop();
                    const obj_val = self.pop();
                    if (obj_val == .object and class_name_val == .string) {
                        self.push(.{ .bool = self.isInstanceOf(obj_val.object.class_name, class_name_val.string) });
                    } else {
                        self.push(.{ .bool = false });
                    }
                },

                .class_decl => try self.handleClassDecl(),

                .interface_decl => {
                    const name_idx = self.readU16();
                    const iface_name = self.currentChunk().constants.items[name_idx].string;
                    const method_count = self.readByte();

                    var idef = InterfaceDef{ .name = iface_name };
                    for (0..method_count) |_| {
                        const mname_idx = self.readU16();
                        const method_name = self.currentChunk().constants.items[mname_idx].string;
                        try idef.methods.append(self.allocator, method_name);
                    }

                    const parent_idx = self.readU16();
                    if (parent_idx != 0xffff) {
                        idef.parent = self.currentChunk().constants.items[parent_idx].string;
                    }

                    try self.interfaces.put(self.allocator, iface_name, idef);
                },

                .trait_decl => {
                    const name_idx = self.readU16();
                    const trait_name = self.currentChunk().constants.items[name_idx].string;
                    try self.traits.put(self.allocator, trait_name, {});
                },

                .enum_decl => try self.handleEnumDecl(),

                .new_obj => {
                    const name_idx = self.readU16();
                    const arg_count = self.readByte();
                    var class_name = self.currentChunk().constants.items[name_idx].string;
                    if (std.mem.eql(u8, class_name, "static")) {
                        class_name = self.resolveStaticClassName(class_name);
                    } else if (std.mem.eql(u8, class_name, "self")) {
                        if (self.currentDefiningClass()) |dc| class_name = dc;
                    } else if (std.mem.eql(u8, class_name, "parent")) {
                        if (self.currentDefiningClass()) |dc| {
                            if (self.classes.get(dc)) |cls| {
                                if (cls.parent) |p| class_name = p;
                            }
                        }
                    }

                    if (std.mem.eql(u8, class_name, "Fiber")) {
                        const ac: usize = arg_count;
                        if (ac < 1) {
                            self.sp -= ac;
                            if (try self.throwBuiltinException("Error", "Fiber::__construct() expects a callable")) continue;
                            return error.RuntimeError;
                        }
                        const callable = self.stack[self.sp - ac];
                        self.sp -= ac;
                        const fiber = try self.allocator.create(Fiber);
                        fiber.* = .{ .callable = callable };
                        try self.fibers.append(self.allocator, fiber);
                        self.push(.{ .fiber = fiber });
                        continue;
                    }

                    // autoload if class not registered
                    if (!self.classes.contains(class_name)) {
                        try self.tryAutoload(class_name);
                    }

                    const obj = try self.allocator.create(PhpObject);
                    obj.* = .{ .class_name = class_name };
                    try self.objects.append(self.allocator, obj);

                    // set property defaults from class and parent chain
                    try self.initObjectProperties(obj, class_name);

                    // call constructor if it exists (walks parent chain)
                    const ac: usize = arg_count;
                    const ctor_name = self.resolveMethod(class_name, "__construct") catch null;

                    if (ctor_name) |cn| {
                        if (self.native_fns.get(cn)) |native| {
                            // native constructor
                            var args_buf: [16]Value = undefined;
                            for (0..ac) |i| args_buf[i] = self.stack[self.sp - ac + i];
                            self.sp -= ac;

                            var tmp_vars: std.StringHashMapUnmanaged(Value) = .{};
                            try tmp_vars.put(self.allocator, "$this", .{ .object = obj });
                            self.frames[self.frame_count] = .{ .chunk = self.currentChunk(), .ip = self.currentFrame().ip, .vars = tmp_vars };
                            self.frame_count += 1;

                            var ctx = self.makeContext(null);
                            _ = try native(&ctx, args_buf[0..ac]);

                            self.frame_count -= 1;
                            self.frames[self.frame_count].vars.deinit(self.allocator);
                        } else if (self.functions.get(cn)) |func| {
                            if (func.locals_only and self.ic != null) {
                                const ctor_ic = self.ic.?;
                                const ctor_lc: usize = func.local_count;
                                const ctor_lbase = ctor_ic.locals_sp;
                                const ctor_locals = if (ctor_lbase + ctor_lc <= ctor_ic.locals_cap) blk: {
                                    const s = ctor_ic.locals_buf[ctor_lbase..ctor_lbase + ctor_lc];
                                    @memset(s, .null);
                                    ctor_ic.locals_sp = ctor_lbase + ctor_lc;
                                    break :blk s;
                                } else blk: {
                                    const s = try self.allocator.alloc(Value, ctor_lc);
                                    @memset(s, .null);
                                    break :blk s;
                                };
                                ctor_locals[0] = .{ .object = obj };
                                for (0..@min(ac, func.arity)) |i| {
                                    ctor_locals[i + 1] = self.stack[self.sp - ac + i];
                                }
                                for (@min(ac, func.arity)..func.arity) |i| {
                                    if (i < func.defaults.len) ctor_locals[i + 1] = func.defaults[i];
                                }
                                self.sp -= ac;
                                self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = .{}, .locals = ctor_locals, .func = func };
                                self.frame_count += 1;
                                try self.fastLoop();
                                const ctor_frame = &self.frames[self.frame_count - 1];
                                if (ctor_frame.chunk == &func.chunk) {
                                    // fastLoop bailed, finish in runLoop
                                    const ctor_base = self.frame_count - 1;
                                    try self.runUntilFrame(ctor_base);
                                }
                                _ = self.pop();
                            } else {
                                var new_vars: std.StringHashMapUnmanaged(Value) = .{};
                                try new_vars.put(self.allocator, "$this", .{ .object = obj });
                                for (0..ac) |i| {
                                    try new_vars.put(self.allocator, func.params[i], self.stack[self.sp - ac + i]);
                                }
                                self.sp -= ac;
                                for (ac..func.arity) |i| {
                                    const default = if (i < func.defaults.len) func.defaults[i] else Value.null;
                                    try new_vars.put(self.allocator, func.params[i], default);
                                }
                                self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars, .locals = try self.allocLocals(func, &new_vars), .func = func };
                                self.frame_count += 1;
                                const ctor_base = self.frame_count - 1;
                                try self.runUntilFrame(ctor_base);
                                _ = self.pop();
                            }
                        } else {
                            self.sp -= ac;
                        }
                    } else {
                        self.sp -= ac;
                    }

                    self.push(.{ .object = obj });
                },

                .get_prop => {
                    const gp_ip = self.currentFrame().ip;
                    const name_idx = self.readU16();
                    const prop_name = self.currentChunk().constants.items[name_idx].string;
                    const obj_val = self.pop();
                    if (obj_val == .object) {
                        const obj = obj_val.object;

                        // IC: slot-indexed fast path
                        if (self.ic) |ic| {
                            const gp_idx = InlineCache.propIndex(@intFromPtr(self.currentChunk()), gp_ip);
                            const gp_entry = &ic.prop[gp_idx];
                            const gp_chunk_key = @intFromPtr(self.currentChunk());
                            if (gp_entry.key == gp_ip and gp_entry.chunk_key == gp_chunk_key and gp_entry.class_ptr == @intFromPtr(obj.class_name.ptr)) {
                                if (gp_entry.slot_index != 0xFFFF) {
                                    if (obj.slots) |s| {
                                        self.push(s[gp_entry.slot_index]);
                                        continue;
                                    }
                                }
                                self.push(obj.get(prop_name));
                                continue;
                            }
                        }

                        const val = obj.get(prop_name);
                        if (val != .null or obj.properties.contains(prop_name) or (obj.slots != null and obj.getSlotIndex(prop_name) != null)) {
                            const vr = self.findPropertyVisibility(obj.class_name, prop_name);
                            if (!self.checkVisibility(vr.defining_class, vr.visibility)) {
                                const msg = try std.fmt.allocPrint(self.allocator, "Cannot access {s} property {s}::${s}", .{
                                    @tagName(vr.visibility), vr.defining_class, prop_name,
                                });
                                try self.strings.append(self.allocator, msg);
                                if (try self.throwBuiltinException("Error", msg)) continue;
                                return error.RuntimeError;
                            }
                            if (self.ic) |ic| {
                                if (vr.visibility == .public) {
                                    const gp_idx = InlineCache.propIndex(@intFromPtr(self.currentChunk()), gp_ip);
                                    const si = if (obj.slot_layout != null) obj.getSlotIndex(prop_name) orelse @as(u16, 0xFFFF) else @as(u16, 0xFFFF);
                                    ic.prop[gp_idx] = .{ .key = gp_ip, .chunk_key = @intFromPtr(self.currentChunk()), .class_ptr = @intFromPtr(obj.class_name.ptr), .slot_index = si };
                                }
                            }
                            self.push(val);
                        } else if (self.hasMethod(obj.class_name, "__get")) {
                            const result = self.callMethod(obj, "__get", &.{.{ .string = prop_name }}) catch .null;
                            self.push(result);
                        } else {
                            self.push(.null);
                        }
                    } else {
                        self.push(.null);
                    }
                },

                .set_prop => {
                    const sp_ip = self.currentFrame().ip;
                    const name_idx = self.readU16();
                    const prop_name = self.currentChunk().constants.items[name_idx].string;
                    const val = try self.copyValue(self.pop());
                    const obj_val = self.pop();
                    if (obj_val == .object) {
                        const obj = obj_val.object;

                        // IC: slot-indexed fast path
                        if (self.ic) |ic| {
                            const sp_idx = InlineCache.propIndex(@intFromPtr(self.currentChunk()), sp_ip);
                            const sp_entry = &ic.prop[sp_idx];
                            if (sp_entry.key == sp_ip and sp_entry.chunk_key == @intFromPtr(self.currentChunk()) and sp_entry.class_ptr == @intFromPtr(obj.class_name.ptr) and sp_entry.slot_index != 0xFFFF) {
                                if (obj.slots) |s| {
                                    s[sp_entry.slot_index] = val;
                                    self.push(val);
                                    continue;
                                }
                            }
                        }

                        const has_prop = obj.properties.contains(prop_name) or (obj.slots != null and obj.getSlotIndex(prop_name) != null);
                        if (!has_prop and self.hasMethod(obj.class_name, "__set")) {
                            _ = self.callMethod(obj, "__set", &.{ .{ .string = prop_name }, val }) catch {};
                        } else {
                            const vr = self.findPropertyVisibility(obj.class_name, prop_name);
                            if (!self.checkVisibility(vr.defining_class, vr.visibility)) {
                                const msg = try std.fmt.allocPrint(self.allocator, "Cannot access {s} property {s}::${s}", .{
                                    @tagName(vr.visibility), vr.defining_class, prop_name,
                                });
                                try self.strings.append(self.allocator, msg);
                                if (try self.throwBuiltinException("Error", msg)) continue;
                                return error.RuntimeError;
                            }
                            if (vr.is_readonly) {
                                const existing = obj.get(prop_name);
                                if (existing != .null) {
                                    const msg = try std.fmt.allocPrint(self.allocator, "Cannot modify readonly property {s}::${s}", .{
                                        vr.defining_class, prop_name,
                                    });
                                    try self.strings.append(self.allocator, msg);
                                    if (try self.throwBuiltinException("Error", msg)) continue;
                                    return error.RuntimeError;
                                }
                            }
                            try obj.set(self.allocator, prop_name, val);
                            // populate IC for slot-indexed writes
                            if (self.ic) |ic| {
                                if (vr.visibility == .public) {
                                    const sp_idx = InlineCache.propIndex(@intFromPtr(self.currentChunk()), sp_ip);
                                    const si = if (obj.slot_layout != null) obj.getSlotIndex(prop_name) orelse @as(u16, 0xFFFF) else @as(u16, 0xFFFF);
                                    ic.prop[sp_idx] = .{ .key = sp_ip, .chunk_key = @intFromPtr(self.currentChunk()), .class_ptr = @intFromPtr(obj.class_name.ptr), .slot_index = si };
                                }
                            }
                        }
                    }
                    self.push(val);
                },

                .method_call => {
                    const name_idx = self.readU16();
                    const arg_count = self.readByte();
                    const method_name = self.currentChunk().constants.items[name_idx].string;
                    const ac: usize = arg_count;

                    // object/generator is below args on the stack
                    const obj_val = self.stack[self.sp - ac - 1];

                    // generator method dispatch
                    if (obj_val == .generator) {
                        const gen = obj_val.generator;
                        self.sp -= ac;
                        self.sp -= 1; // pop generator
                        if (std.mem.eql(u8, method_name, "current")) {
                            // auto-start if not yet started
                            if (gen.state == .created) try self.resumeGenerator(gen, .null);
                            self.push(gen.current_value);
                        } else if (std.mem.eql(u8, method_name, "key")) {
                            if (gen.state == .created) try self.resumeGenerator(gen, .null);
                            self.push(gen.current_key);
                        } else if (std.mem.eql(u8, method_name, "valid")) {
                            if (gen.state == .created) try self.resumeGenerator(gen, .null);
                            self.push(.{ .bool = gen.state != .completed });
                        } else if (std.mem.eql(u8, method_name, "next")) {
                            // next() always advances: if not started, start then advance
                            if (gen.state == .created) try self.resumeGenerator(gen, .null);
                            try self.resumeGenerator(gen, .null);
                            self.push(.null);
                        } else if (std.mem.eql(u8, method_name, "send")) {
                            const sent = if (ac > 0) self.stack[self.sp + 1] else Value{ .null = {} };
                            if (gen.state == .created) try self.resumeGenerator(gen, .null);
                            try self.resumeGenerator(gen, sent);
                            self.push(.null);
                        } else if (std.mem.eql(u8, method_name, "rewind")) {
                            self.push(.null);
                        } else if (std.mem.eql(u8, method_name, "getReturn")) {
                            self.push(gen.return_value);
                        } else {
                            self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught Error: Call to undefined method Generator::{s}()", .{method_name}) catch null;
                            return error.RuntimeError;
                        }
                        continue;
                    }

                    if (obj_val == .fiber) {
                        const fiber = obj_val.fiber;
                        // args are at stack[sp-ac..sp], fiber at stack[sp-ac-1]
                        // save args before popping
                        var args_buf: [16]Value = undefined;
                        for (0..ac) |i| args_buf[i] = self.stack[self.sp - ac + i];
                        self.sp -= ac;
                        self.sp -= 1;

                        if (std.mem.eql(u8, method_name, "start")) {
                            if (fiber.state != .created) {
                                if (try self.throwBuiltinException("FiberError", "Cannot start a fiber that is not in the created state")) continue;
                                return error.RuntimeError;
                            }
                            fiber.state = .running;
                            const fb = self.frame_count;
                            const sb = self.sp;
                            const hb = self.handler_count;

                            for (0..ac) |i| self.push(args_buf[i]);
                            if (fiber.callable == .string) {
                                try self.callNamedFunction(fiber.callable.string, @intCast(ac));
                            } else {
                                var ctx = self.makeContext(null);
                                _ = try ctx.invokeCallable(fiber.callable, args_buf[0..ac]);
                                fiber.state = .terminated;
                                self.push(.null);
                                continue;
                            }

                            const result = try self.executeFiber(fiber, fb, sb, hb);
                            self.push(result);
                        } else if (std.mem.eql(u8, method_name, "resume")) {
                            if (fiber.state != .suspended) {
                                if (try self.throwBuiltinException("FiberError", "Cannot resume a fiber that is not suspended")) continue;
                                return error.RuntimeError;
                            }
                            fiber.state = .running;
                            const fb = self.frame_count;
                            const sb = self.sp;
                            const hb = self.handler_count;

                            self.restoreFiberState(fiber, fb, sb);

                            const resume_val = if (ac > 0) args_buf[0] else Value{ .null = {} };
                            self.push(resume_val);

                            const result = try self.executeFiber(fiber, fb, sb, hb);
                            self.push(result);
                        } else if (std.mem.eql(u8, method_name, "getReturn")) {
                            if (fiber.state != .terminated) {
                                if (try self.throwBuiltinException("FiberError", "Cannot get return value of a fiber that hasn't terminated")) continue;
                                return error.RuntimeError;
                            }
                            self.push(fiber.return_value);
                        } else if (std.mem.eql(u8, method_name, "isStarted")) {
                            self.push(.{ .bool = fiber.state != .created });
                        } else if (std.mem.eql(u8, method_name, "isRunning")) {
                            self.push(.{ .bool = fiber.state == .running });
                        } else if (std.mem.eql(u8, method_name, "isSuspended")) {
                            self.push(.{ .bool = fiber.state == .suspended });
                        } else if (std.mem.eql(u8, method_name, "isTerminated")) {
                            self.push(.{ .bool = fiber.state == .terminated });
                        } else {
                            self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught Error: Call to undefined method Fiber::{s}()", .{method_name}) catch null;
                            return error.RuntimeError;
                        }
                        continue;
                    }

                    if (obj_val != .object) {
                        self.sp -= ac + 1;
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught Error: Call to a member function {s}() on {s}", .{ method_name, valueTypeName(obj_val) }) catch null;
                        return error.RuntimeError;
                    }
                    const obj = obj_val.object;

                    // IC: skip visibility + resolve on cache hit
                    if (self.ic) |ic| {
                        const mc_ip = self.currentFrame().ip - 4;
                        const mc_idx = InlineCache.methodIndex(@intFromPtr(self.currentChunk()), mc_ip);
                        const mc_entry = &ic.method[mc_idx];
                        if (mc_entry.key == mc_ip and mc_entry.class_ptr == @intFromPtr(obj.class_name.ptr)) {
                            if (mc_entry.func) |func| {
                                if (func.locals_only and self.captures.items.len == 0) {
                                    const lc: usize = func.local_count;
                                    const lbase = ic.locals_sp;
                                    const mc_locals = if (lbase + lc <= ic.locals_cap) blk: {
                                        const s = ic.locals_buf[lbase..lbase + lc];
                                        @memset(s, .null);
                                        ic.locals_sp = lbase + lc;
                                        break :blk s;
                                    } else blk: {
                                        const s = try self.allocator.alloc(Value, lc);
                                        @memset(s, .null);
                                        break :blk s;
                                    };
                                    mc_locals[0] = .{ .object = obj };
                                    for (0..@min(ac, func.arity)) |i| {
                                        mc_locals[i + 1] = try self.copyValue(self.stack[self.sp - ac + i]);
                                    }
                                    for (@min(ac, func.arity)..func.arity) |i| {
                                        if (i < func.defaults.len) mc_locals[i + 1] = func.defaults[i];
                                    }
                                    self.sp -= ac + 1;
                                    self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = .{}, .locals = mc_locals, .func = func };
                                    self.frame_count += 1;
                                    try self.fastLoop();
                                    continue;
                                }
                            } else if (mc_entry.native) |native| {
                                var args_buf: [16]Value = undefined;
                                for (0..ac) |i| args_buf[i] = self.stack[self.sp - ac + i];
                                self.sp -= ac + 1;
                                var tmp_vars: std.StringHashMapUnmanaged(Value) = .{};
                                try tmp_vars.put(self.allocator, "$this", .{ .object = obj });
                                self.frames[self.frame_count] = .{ .chunk = self.currentChunk(), .ip = self.currentFrame().ip, .vars = tmp_vars };
                                self.frame_count += 1;
                                const saved_fc = self.frame_count;
                                var ctx = self.makeContext(null);
                                const result = try native(&ctx, args_buf[0..ac]);
                                if (self.frame_count >= saved_fc) {
                                    self.frame_count -= 1;
                                    self.frames[self.frame_count].vars.deinit(self.allocator);
                                    self.push(result);
                                } else {
                                    continue;
                                }
                                continue;
                            }
                        }
                    }

                    // check visibility
                    const mvr = self.findMethodVisibility(obj.class_name, method_name);
                    if (!self.checkVisibility(mvr.defining_class, mvr.visibility)) {
                        const msg = try std.fmt.allocPrint(self.allocator, "Call to {s} method {s}::{s}()", .{
                            @tagName(mvr.visibility), mvr.defining_class, method_name,
                        });
                        try self.strings.append(self.allocator, msg);
                        self.sp -= ac + 1;
                        if (try self.throwBuiltinException("Error", msg)) continue;
                        return error.RuntimeError;
                    }

                    // look up method in class hierarchy
                    const full_name = self.resolveMethod(obj.class_name, method_name) catch {
                        if (self.hasMethod(obj.class_name, "__call")) {
                            var args_arr = try self.allocator.create(PhpArray);
                            args_arr.* = .{};
                            try self.arrays.append(self.allocator, args_arr);
                            for (0..ac) |i| try args_arr.append(self.allocator, self.stack[self.sp - ac + i]);
                            self.sp -= ac + 1;
                            const result = try self.callMethod(obj, "__call", &.{ .{ .string = method_name }, .{ .array = args_arr } });
                            self.push(result);
                            continue;
                        }
                        self.sp -= ac + 1;
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught Error: Call to undefined method {s}::{s}()", .{ obj.class_name, method_name }) catch null;
                        return error.RuntimeError;
                    };
                    if (self.native_fns.get(full_name)) |native| {
                        // populate IC
                        if (self.ic) |ic| {
                            const mc_ip2 = self.currentFrame().ip - 4;
                            const mc_idx2 = InlineCache.methodIndex(@intFromPtr(self.currentChunk()), mc_ip2);
                            if (mvr.visibility == .public) {
                                ic.method[mc_idx2] = .{ .key = mc_ip2, .class_ptr = @intFromPtr(obj.class_name.ptr), .native = native, .full_name = full_name };
                            }
                        }
                        var args_buf: [16]Value = undefined;
                        for (0..ac) |i| args_buf[i] = self.stack[self.sp - ac + i];
                        self.sp -= ac;
                        self.sp -= 1;

                        // push a temporary frame so native can read $this
                        var tmp_vars: std.StringHashMapUnmanaged(Value) = .{};
                        try tmp_vars.put(self.allocator, "$this", .{ .object = obj });
                        self.frames[self.frame_count] = .{ .chunk = self.currentChunk(), .ip = self.currentFrame().ip, .vars = tmp_vars };
                        self.frame_count += 1;
                        const saved_fc = self.frame_count;

                        var ctx = self.makeContext(null);
                        const result = try native(&ctx, args_buf[0..ac]);

                        // if throwBuiltinException unwound frames, skip cleanup
                        if (self.frame_count >= saved_fc) {
                            self.frame_count -= 1;
                            self.frames[self.frame_count].vars.deinit(self.allocator);
                            self.push(result);
                        } else {
                            continue;
                        }
                    } else if (self.functions.get(full_name)) |func| {
                        // populate IC
                        if (self.ic) |ic| {
                            const mc_ip2 = self.currentFrame().ip - 4;
                            const mc_idx2 = InlineCache.methodIndex(@intFromPtr(self.currentChunk()), mc_ip2);
                            if (mvr.visibility == .public) {
                                ic.method[mc_idx2] = .{ .key = mc_ip2, .class_ptr = @intFromPtr(obj.class_name.ptr), .func = func, .full_name = full_name };
                            }
                        }
                        var new_vars: std.StringHashMapUnmanaged(Value) = .{};
                        try new_vars.put(self.allocator, "$this", .{ .object = obj });

                        try self.bindClosures(&new_vars, null, full_name);

                        if (func.is_variadic) {
                            const fixed: usize = func.arity - 1;
                            for (0..@min(ac, fixed)) |i| {
                                try new_vars.put(self.allocator, func.params[i], self.stack[self.sp - ac + i]);
                            }
                            const rest_arr = try self.allocator.create(PhpArray);
                            rest_arr.* = .{};
                            try self.arrays.append(self.allocator, rest_arr);
                            for (fixed..ac) |i| try rest_arr.append(self.allocator, self.stack[self.sp - ac + i]);
                            try new_vars.put(self.allocator, func.params[fixed], .{ .array = rest_arr });
                        } else {
                            for (0..@min(ac, func.arity)) |i| {
                                try new_vars.put(self.allocator, func.params[i], self.stack[self.sp - ac + i]);
                            }
                            try self.fillDefaults(&new_vars, func, ac);
                        }
                        // set up ref cells for by-ref params
                        var method_refs: std.StringHashMapUnmanaged(*Value) = .{};
                        if (func.ref_params.len > 0) {
                            // method_call opcode is 4 bytes: opcode(1) + name(2) + argc(1)
                            const arg_vars = self.scanCallerVarNames(ac);
                            for (0..@min(ac, func.ref_params.len)) |ri| {
                                if (func.ref_params[ri]) {
                                    if (arg_vars[ri]) |caller_var| {
                                        if (self.currentFrame().ref_slots.get(caller_var)) |existing_cell| {
                                            existing_cell.* = new_vars.get(func.params[ri]) orelse .null;
                                            try method_refs.put(self.allocator, func.params[ri], existing_cell);
                                        } else {
                                            const cell = try self.allocator.create(Value);
                                            cell.* = new_vars.get(func.params[ri]) orelse .null;
                                            try self.ref_cells.append(self.allocator, cell);
                                            try self.currentFrame().ref_slots.put(self.allocator, caller_var, cell);
                                            try method_refs.put(self.allocator, func.params[ri], cell);
                                        }
                                    }
                                }
                            }
                        }
                        self.sp -= ac;
                        self.sp -= 1;
                        if (func.is_generator) {
                            method_refs.deinit(self.allocator);
                            const gen = try self.allocator.create(Generator);
                            gen.* = .{ .func = func, .vars = new_vars };
                            try self.generators.append(self.allocator, gen);
                            self.push(.{ .generator = gen });
                        } else {
                            self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars, .locals = try self.allocLocals(func, &new_vars), .func = func, .ref_slots = method_refs };
                            self.frame_count += 1;
                        }
                    } else {
                        self.sp -= ac + 1;
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught Error: Call to undefined method {s}::{s}()", .{ obj.class_name, method_name }) catch null;
                        return error.RuntimeError;
                    }
                },

                .method_call_spread => {
                    const name_idx = self.readU16();
                    const method_name = self.currentChunk().constants.items[name_idx].string;
                    const args_val = self.pop();
                    if (args_val != .array) {
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught TypeError: Argument unpacking requires an array", .{}) catch null;
                        return error.RuntimeError;
                    }
                    const arr = args_val.array;
                    const ac = arr.entries.items.len;
                    for (arr.entries.items) |entry| self.push(entry.value);
                    const obj_val = self.stack[self.sp - ac - 1];
                    if (obj_val != .object) {
                        self.sp -= ac + 1;
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught Error: Call to a member function {s}() on {s}", .{ method_name, valueTypeName(obj_val) }) catch null;
                        return error.RuntimeError;
                    }
                    const obj = obj_val.object;
                    const mvr = self.findMethodVisibility(obj.class_name, method_name);
                    if (!self.checkVisibility(mvr.defining_class, mvr.visibility)) {
                        self.sp -= ac + 1;
                        const msg = std.fmt.allocPrint(self.allocator, "Call to {s} method {s}::{s}()", .{ @tagName(mvr.visibility), mvr.defining_class, method_name }) catch null;
                        self.error_msg = msg;
                        return error.RuntimeError;
                    }
                    const full_name = try self.resolveMethod(obj.class_name, method_name);
                    if (self.native_fns.get(full_name)) |native| {
                        var args_buf: [16]Value = undefined;
                        for (0..ac) |i| args_buf[i] = self.stack[self.sp - ac + i];
                        self.sp -= ac;
                        self.sp -= 1;
                        var tmp_vars: std.StringHashMapUnmanaged(Value) = .{};
                        try tmp_vars.put(self.allocator, "$this", .{ .object = obj });
                        self.frames[self.frame_count] = .{ .chunk = self.currentChunk(), .ip = self.currentFrame().ip, .vars = tmp_vars };
                        self.frame_count += 1;
                        const saved_fc = self.frame_count;
                        var ctx = self.makeContext(null);
                        const result = try native(&ctx, args_buf[0..ac]);
                        if (self.frame_count >= saved_fc) {
                            self.frame_count -= 1;
                            self.frames[self.frame_count].vars.deinit(self.allocator);
                            self.push(result);
                        } else continue;
                    } else if (self.functions.get(full_name)) |func| {
                        var new_vars: std.StringHashMapUnmanaged(Value) = .{};
                        try new_vars.put(self.allocator, "$this", .{ .object = obj });
                        try self.bindClosures(&new_vars, null, full_name);
                        if (func.is_variadic) {
                            const fixed: usize = func.arity - 1;
                            for (0..@min(ac, fixed)) |i| {
                                try new_vars.put(self.allocator, func.params[i], self.stack[self.sp - ac + i]);
                            }
                            const rest_arr = try self.allocator.create(PhpArray);
                            rest_arr.* = .{};
                            try self.arrays.append(self.allocator, rest_arr);
                            for (fixed..ac) |i| try rest_arr.append(self.allocator, self.stack[self.sp - ac + i]);
                            try new_vars.put(self.allocator, func.params[fixed], .{ .array = rest_arr });
                        } else {
                            for (0..@min(ac, func.arity)) |i| {
                                try new_vars.put(self.allocator, func.params[i], self.stack[self.sp - ac + i]);
                            }
                            for (ac..func.arity) |i| {
                                if (i < func.defaults.len) try new_vars.put(self.allocator, func.params[i], func.defaults[i]);
                            }
                        }
                        self.sp -= ac;
                        self.sp -= 1;
                        self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars, .locals = try self.allocLocals(func, &new_vars), .func = func };
                        self.frame_count += 1;
                    } else {
                        self.sp -= ac + 1;
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught Error: Call to undefined method {s}::{s}()", .{ obj.class_name, method_name }) catch null;
                        return error.RuntimeError;
                    }
                },

                .static_call => {
                    const class_idx = self.readU16();
                    const method_idx = self.readU16();
                    const arg_count = self.readByte();
                    var class_name = self.currentChunk().constants.items[class_idx].string;
                    const method_name = self.currentChunk().constants.items[method_idx].string;

                    if (std.mem.eql(u8, class_name, "Fiber") and std.mem.eql(u8, method_name, "suspend")) {
                        const ac: usize = arg_count;
                        const suspend_val = if (ac > 0) blk: {
                            const v = self.stack[self.sp - 1];
                            self.sp -= ac;
                            break :blk v;
                        } else .null;

                        if (self.current_fiber == null) {
                            if (try self.throwBuiltinException("FiberError", "Cannot call Fiber::suspend() when not in a Fiber")) continue;
                            return error.RuntimeError;
                        }

                        self.fiber_suspend_pending = true;
                        self.fiber_suspend_value = suspend_val;
                        return error.RuntimeError;
                    }

                    const this_val = self.currentFrame().vars.get("$this") orelse blk: {
                        const f = self.currentFrame();
                        if (f.func) |fn_info| {
                            if (fn_info.locals_only) {
                                for (fn_info.slot_names, 0..) |sn, si| {
                                    if (std.mem.eql(u8, sn, "$this") and si < f.locals.len and f.locals[si] == .object) {
                                        break :blk f.locals[si];
                                    }
                                }
                            }
                        }
                        break :blk null;
                    };
                    if (std.mem.eql(u8, class_name, "static")) {
                        class_name = self.resolveStaticClassName(class_name);
                    } else if (std.mem.eql(u8, class_name, "parent") or std.mem.eql(u8, class_name, "self")) {
                        const defining_class = self.currentDefiningClass();
                        if (std.mem.eql(u8, class_name, "parent")) {
                            if (defining_class) |dc| {
                                if (self.classes.get(dc)) |cls| {
                                    if (cls.parent) |p| class_name = p;
                                }
                            }
                        } else {
                            if (defining_class) |dc| class_name = dc;
                        }
                    }

                    const full_name = try self.resolveMethod(class_name, method_name);

                    // if we have $this, pass it through to the called method
                    if (this_val) |tv| {
                        if (tv == .object) {
                            if (self.functions.get(full_name)) |func| {
                                const ac: usize = arg_count;
                                var new_vars: std.StringHashMapUnmanaged(Value) = .{};
                                try new_vars.put(self.allocator, "$this", tv);
                                for (0..ac) |i| {
                                    try new_vars.put(self.allocator, func.params[i], self.stack[self.sp - ac + i]);
                                }
                                self.sp -= ac;
                                self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars, .locals = try self.allocLocals(func, &new_vars), .func = func, .called_class = class_name };
                                self.frame_count += 1;
                            } else if (self.native_fns.get(full_name)) |native| {
                                const ac: usize = arg_count;
                                var args_buf: [16]Value = undefined;
                                for (0..ac) |i| args_buf[i] = self.stack[self.sp - ac + i];
                                self.sp -= ac;
                                var tmp_vars: std.StringHashMapUnmanaged(Value) = .{};
                                try tmp_vars.put(self.allocator, "$this", tv);
                                self.frames[self.frame_count] = .{ .chunk = self.currentChunk(), .ip = self.currentFrame().ip, .vars = tmp_vars };
                                self.frame_count += 1;
                                var ctx = self.makeContext(null);
                                const result = try native(&ctx, args_buf[0..ac]);
                                self.frame_count -= 1;
                                self.frames[self.frame_count].vars.deinit(self.allocator);
                                self.push(result);
                            } else {
                                self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught Error: Call to undefined method {s}::{s}()", .{ class_name, method_name }) catch null;
                                return error.RuntimeError;
                            }
                        } else {
                            try self.callNamedFunction(full_name, arg_count);
                            self.frames[self.frame_count - 1].called_class = class_name;
                        }
                    } else {
                        try self.callNamedFunction(full_name, arg_count);
                        self.frames[self.frame_count - 1].called_class = class_name;
                    }
                },

                .static_call_spread => {
                    const class_idx = self.readU16();
                    const method_idx = self.readU16();
                    var class_name = self.currentChunk().constants.items[class_idx].string;
                    const method_name = self.currentChunk().constants.items[method_idx].string;
                    const args_val = self.pop();
                    if (args_val != .array) {
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught TypeError: Argument unpacking requires an array", .{}) catch null;
                        return error.RuntimeError;
                    }
                    const arr = args_val.array;
                    const ac = arr.entries.items.len;

                    const this_val = self.currentFrame().vars.get("$this");
                    if (std.mem.eql(u8, class_name, "parent") or std.mem.eql(u8, class_name, "self")) {
                        const defining_class = self.currentDefiningClass();
                        if (std.mem.eql(u8, class_name, "parent")) {
                            if (defining_class) |dc| {
                                if (self.classes.get(dc)) |cls| {
                                    if (cls.parent) |p| class_name = p;
                                }
                            }
                        } else {
                            if (defining_class) |dc| class_name = dc;
                        }
                    }

                    const full_name = try self.resolveMethod(class_name, method_name);
                    for (arr.entries.items) |entry| self.push(entry.value);

                    if (this_val) |tv| {
                        if (tv == .object) {
                            if (self.functions.get(full_name)) |func| {
                                var new_vars: std.StringHashMapUnmanaged(Value) = .{};
                                try new_vars.put(self.allocator, "$this", tv);
                                if (func.is_variadic) {
                                    const fixed: usize = func.arity - 1;
                                    for (0..@min(ac, fixed)) |i| {
                                        try new_vars.put(self.allocator, func.params[i], self.stack[self.sp - ac + i]);
                                    }
                                    const rest_arr = try self.allocator.create(PhpArray);
                                    rest_arr.* = .{};
                                    try self.arrays.append(self.allocator, rest_arr);
                                    for (fixed..ac) |i| try rest_arr.append(self.allocator, self.stack[self.sp - ac + i]);
                                    try new_vars.put(self.allocator, func.params[fixed], .{ .array = rest_arr });
                                } else {
                                    for (0..@min(ac, func.arity)) |i| {
                                        try new_vars.put(self.allocator, func.params[i], self.stack[self.sp - ac + i]);
                                    }
                                    for (ac..func.arity) |i| {
                                        if (i < func.defaults.len) try new_vars.put(self.allocator, func.params[i], func.defaults[i]);
                                    }
                                }
                                self.sp -= ac;
                                self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars, .locals = try self.allocLocals(func, &new_vars), .func = func };
                                self.frame_count += 1;
                            } else {
                                self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught Error: Call to undefined method {s}::{s}()", .{ class_name, method_name }) catch null;
                                return error.RuntimeError;
                            }
                        } else {
                            try self.callNamedFunction(full_name, @intCast(ac));
                        }
                    } else {
                        try self.callNamedFunction(full_name, @intCast(ac));
                    }
                },

                .get_static_prop => {
                    const class_idx = self.readU16();
                    const prop_idx = self.readU16();
                    var class_name = self.currentChunk().constants.items[class_idx].string;
                    const prop_name = self.currentChunk().constants.items[prop_idx].string;

                    class_name = self.resolveStaticClassName(class_name);

                    if (std.mem.eql(u8, prop_name, "class")) {
                        self.push(.{ .string = class_name });
                    } else if (self.getStaticProp(class_name, prop_name)) |val| {
                        self.push(val);
                    } else {
                        self.push(.null);
                    }
                },

                .yield_value => {
                    const val = self.pop();
                    const gen = self.currentFrame().generator orelse {
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Cannot use yield outside of a generator", .{}) catch null;
                        return error.RuntimeError;
                    };
                    gen.current_value = val;
                    gen.current_key = .{ .int = gen.implicit_key };
                    gen.implicit_key += 1;
                    gen.ip = self.currentFrame().ip;
                    gen.vars = self.currentFrame().vars;
                    self.saveFrameLocalsToGenerator(gen);
                    try self.saveGeneratorStack(gen);
                    self.saveGeneratorHandlers(gen);
                    gen.state = .suspended;
                    self.frame_count -= 1;
                    return;
                },

                .yield_pair => {
                    const val = self.pop();
                    const key = self.pop();
                    const gen = self.currentFrame().generator orelse {
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Cannot use yield outside of a generator", .{}) catch null;
                        return error.RuntimeError;
                    };
                    gen.current_value = val;
                    gen.current_key = key;
                    if (key == .int and key.int >= gen.implicit_key) gen.implicit_key = key.int + 1;
                    gen.ip = self.currentFrame().ip;
                    gen.vars = self.currentFrame().vars;
                    self.saveFrameLocalsToGenerator(gen);
                    try self.saveGeneratorStack(gen);
                    self.saveGeneratorHandlers(gen);
                    gen.state = .suspended;
                    self.frame_count -= 1;
                    return;
                },

                .yield_from => {
                    const iterable = self.pop();
                    const outer_gen = self.currentFrame().generator orelse {
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Cannot use yield outside of a generator", .{}) catch null;
                        return error.RuntimeError;
                    };

                    if (iterable == .generator) {
                        const inner = iterable.generator;
                        if (inner.state == .created) try self.resumeGenerator(inner, .null);

                        if (inner.state == .suspended) {
                            outer_gen.delegate = .{ .gen = inner };
                            outer_gen.current_value = inner.current_value;
                            outer_gen.current_key = inner.current_key;
                            // save ip past the yield_from opcode so we resume here
                            outer_gen.ip = self.currentFrame().ip;
                            outer_gen.vars = self.currentFrame().vars;
                            self.saveFrameLocalsToGenerator(outer_gen);
                            self.saveGeneratorHandlers(outer_gen);
                            outer_gen.state = .suspended;
                            self.frame_count -= 1;
                            return;
                        }
                        // inner already completed
                        self.push(inner.return_value);
                    } else if (iterable == .array) {
                        const arr = iterable.array;
                        if (arr.entries.items.len > 0) {
                            const entry = arr.entries.items[0];
                            outer_gen.delegate = .{ .array = .{ .arr = arr, .index = 1 } };
                            outer_gen.current_key = switch (entry.key) {
                                .int => |i| .{ .int = i },
                                .string => |s| .{ .string = s },
                            };
                            outer_gen.current_value = entry.value;
                            outer_gen.ip = self.currentFrame().ip;
                            outer_gen.vars = self.currentFrame().vars;
                            self.saveFrameLocalsToGenerator(outer_gen);
                            self.saveGeneratorHandlers(outer_gen);
                            outer_gen.state = .suspended;
                            self.frame_count -= 1;
                            return;
                        }
                        self.push(.null);
                    } else {
                        self.push(.null);
                    }
                },

                .generator_return => {
                    const val = self.pop();
                    const gen = self.currentFrame().generator orelse {
                        self.push(val);
                        if (self.frame_count > 1) {
                            self.frame_count -= 1;
                            self.frames[self.frame_count].vars.deinit(self.allocator);
                            if (self.frames[self.frame_count].locals.len > 0) {
                                self.freeLocals(self.frames[self.frame_count].locals);
                                self.frames[self.frame_count].locals = &.{};
                            }
                        }
                        continue;
                    };
                    gen.return_value = val;
                    gen.current_value = .null;
                    gen.current_key = .null;
                    gen.state = .completed;
                    gen.vars = self.currentFrame().vars;
                    self.saveFrameLocalsToGenerator(gen);
                    self.frame_count -= 1;
                    return;
                },

                .set_static_prop => {
                    const class_idx = self.readU16();
                    const prop_idx = self.readU16();
                    var class_name = self.currentChunk().constants.items[class_idx].string;
                    const prop_name = self.currentChunk().constants.items[prop_idx].string;

                    class_name = self.resolveStaticClassName(class_name);

                    const val = try self.copyValue(self.peek());
                    if (self.classes.getPtr(class_name)) |cls| {
                        try cls.static_props.put(self.allocator, prop_name, val);
                    }
                },
            }
        }
    }

    fn resolveStaticClassName(self: *VM, name: []const u8) []const u8 {
        if (std.mem.eql(u8, name, "static")) {
            if (self.currentFrame().vars.get("$this")) |this_val| {
                if (this_val == .object) return this_val.object.class_name;
            }
            const f = self.currentFrame();
            if (f.func) |fn_info| {
                if (fn_info.locals_only) {
                    for (fn_info.slot_names, 0..) |sn, si| {
                        if (std.mem.eql(u8, sn, "$this") and si < f.locals.len and f.locals[si] == .object) {
                            return f.locals[si].object.class_name;
                        }
                    }
                }
            }
            if (f.called_class) |cc| return cc;
            if (self.currentDefiningClass()) |dc| return dc;
        } else if (std.mem.eql(u8, name, "self")) {
            if (self.currentDefiningClass()) |dc| return dc;
        } else if (std.mem.eql(u8, name, "parent")) {
            if (self.currentDefiningClass()) |dc| {
                if (self.classes.get(dc)) |cls| {
                    if (cls.parent) |p| return p;
                }
            }
        }
        return name;
    }

    fn getStaticProp(self: *VM, class_name: []const u8, prop_name: []const u8) ?Value {
        var current: ?[]const u8 = class_name;
        while (current) |cn| {
            if (self.classes.getPtr(cn)) |cls| {
                if (cls.static_props.get(prop_name)) |val| return val;
                current = cls.parent;
            } else break;
        }
        return null;
    }

    pub fn throwBuiltinException(self: *VM, class_name: []const u8, message: []const u8) !bool {
        const obj = try self.allocator.create(PhpObject);
        obj.* = .{ .class_name = class_name };
        try obj.set(self.allocator, "message", .{ .string = message });
        try obj.set(self.allocator, "code", .{ .int = 0 });
        try self.objects.append(self.allocator, obj);

        if (self.handler_count <= self.handler_floor) {
            self.pending_exception = .{ .object = obj };
            return false;
        }

        const handler = self.exception_handlers[self.handler_count - 1];
        self.handler_count -= 1;

        while (self.frame_count > handler.frame_count) {
            self.frame_count -= 1;
            self.frames[self.frame_count].vars.deinit(self.allocator);
        }

        self.sp = handler.sp;
        self.push(.{ .object = obj });
        self.currentFrame().ip = handler.catch_ip;
        return true;
    }

    fn resumeGenerator(self: *VM, gen: *Generator, sent_value: Value) RuntimeError!void {
        if (gen.state == .completed) return;

        // if delegating, advance the delegate instead of resuming bytecode
        if (gen.delegate) |*del| {
            switch (del.*) {
                .gen => |inner| {
                    try self.resumeGenerator(inner, sent_value);
                    if (inner.state == .suspended) {
                        gen.current_value = inner.current_value;
                        gen.current_key = inner.current_key;
                        return;
                    }
                    // inner exhausted - clear delegate and resume outer with return value
                    const ret_val = inner.return_value;
                    gen.delegate = null;
                    return self.resumeGeneratorWithValue(gen, ret_val);
                },
                .array => |*arr_state| {
                    if (arr_state.index < arr_state.arr.entries.items.len) {
                        const entry = arr_state.arr.entries.items[arr_state.index];
                        arr_state.index += 1;
                        gen.current_key = switch (entry.key) {
                            .int => |i| .{ .int = i },
                            .string => |s| .{ .string = s },
                        };
                        gen.current_value = entry.value;
                        return;
                    }
                    // array exhausted
                    gen.delegate = null;
                    return self.resumeGeneratorWithValue(gen, .null);
                },
            }
        }

        return self.resumeGeneratorWithValue(gen, sent_value);
    }

    fn resumeGeneratorWithValue(self: *VM, gen: *Generator, sent_value: Value) RuntimeError!void {
        if (gen.state == .completed) return;

        gen.state = .running;
        const saved_sp = self.sp;
        const return_frame = self.frame_count;
        const saved_handler_count = self.handler_count;
        const prev_floor = self.handler_floor;
        self.handler_floor = self.handler_count;

        // restore saved stack from previous suspension
        for (gen.stack.items) |v| self.push(v);
        gen.stack.clearRetainingCapacity();
        gen.base_sp = saved_sp;

        var gen_locals: []Value = &.{};
        if (gen.locals.items.len > 0) {
            gen_locals = try self.allocator.alloc(Value, gen.locals.items.len);
            @memcpy(gen_locals, gen.locals.items);
        } else if (gen.ip == 0) {
            // first resume - allocate locals from initial vars
            gen_locals = try self.allocLocals(gen.func, &gen.vars);
        }
        self.frames[self.frame_count] = .{
            .chunk = &gen.func.chunk,
            .ip = gen.ip,
            .vars = gen.vars,
            .locals = gen_locals,
            .func = gen.func,
            .generator = gen,
        };
        self.frame_count += 1;

        self.restoreGeneratorHandlers(gen);

        if (gen.ip > 0) {
            self.push(sent_value);
        }

        self.runUntilFrame(return_frame) catch |err| {
            self.handler_floor = prev_floor;
            if (gen.state == .suspended) {
                self.sp = saved_sp;
                return;
            }
            if (gen.state == .completed) {
                self.sp = saved_sp;
                return;
            }
            gen.state = .completed;
            self.handler_count = saved_handler_count;
            // unwind any leftover generator frames
            while (self.frame_count > return_frame) {
                self.frame_count -= 1;
                self.frames[self.frame_count].vars.deinit(self.allocator);
            }
            self.sp = saved_sp;
            if (self.pending_exception) |exc| {
                self.pending_exception = null;
                if (self.handler_count > self.handler_floor) {
                    const handler = self.exception_handlers[self.handler_count - 1];
                    self.handler_count -= 1;
                    while (self.frame_count > handler.frame_count) {
                        self.frame_count -= 1;
                        self.frames[self.frame_count].vars.deinit(self.allocator);
                    }
                    self.sp = handler.sp;
                    self.push(exc);
                    self.currentFrame().ip = handler.catch_ip;
                    return;
                }
                return error.RuntimeError;
            }
            return err;
        };
        self.handler_floor = prev_floor;
        if (gen.state == .running) {
            gen.state = .completed;
        }
        self.sp = saved_sp;
    }

    fn saveGeneratorStack(self: *VM, gen: *Generator) !void {
        gen.stack.clearRetainingCapacity();
        if (self.sp > gen.base_sp) {
            try gen.stack.appendSlice(self.allocator, self.stack[gen.base_sp..self.sp]);
        }
    }

    fn getLocalGlobal(self: *VM, slot: u16, frame: *CallFrame) Value {
        if (slot < self.global_slot_names.len and self.global_slot_names[slot].len > 0) {
            if (frame.ref_slots.count() > 0) {
                if (frame.ref_slots.get(self.global_slot_names[slot])) |cell| {
                    return cell.*;
                }
            }
        }
        if (slot < frame.locals.len) {
            const val = frame.locals[slot];
            if (val != .null) return val;
            if (slot < self.global_slot_names.len and self.global_slot_names[slot].len > 0) {
                if (frame.vars.get(self.global_slot_names[slot])) |v| {
                    frame.locals[slot] = v;
                    return v;
                }
            }
        }
        return .null;
    }

    fn setLocalGlobal(self: *VM, slot: u16, val: Value, frame: *CallFrame) void {
        if (slot < self.global_slot_names.len) {
            const name = self.global_slot_names[slot];
            if (name.len > 0 and frame.ref_slots.count() > 0) {
                if (frame.ref_slots.get(name)) |cell| {
                    cell.* = val;
                }
            }
        }
        self.global_vars_dirty = true;
    }

    fn syncGlobalLocalsToVars(self: *VM) !void {
        if (!self.global_vars_dirty) return;
        self.global_vars_dirty = false;
        const frame = &self.frames[0];
        for (self.global_slot_names, 0..) |name, i| {
            if (name.len > 0 and i < frame.locals.len) {
                try frame.vars.put(self.allocator, name, frame.locals[i]);
            }
        }
    }


    fn writebackGlobals(self: *VM) !void {
        var i: usize = 0;
        while (i < self.global_vars.items.len) {
            const entry = self.global_vars.items[i];
            if (entry.frame_depth == self.frame_count) {
                const val = try self.copyValue(self.currentFrame().vars.get(entry.var_name) orelse .null);
                try self.frames[0].vars.put(self.allocator, entry.var_name, val);
                for (self.global_slot_names, 0..) |sn, si| {
                    if (std.mem.eql(u8, sn, entry.var_name)) {
                        if (si < self.frames[0].locals.len) self.frames[0].locals[si] = val;
                        break;
                    }
                }
                _ = self.global_vars.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    fn objectToString(self: *VM, obj: *PhpObject) RuntimeError![]const u8 {
        const method_name = self.resolveMethod(obj.class_name, "__toString") catch return "Object";
        if (self.functions.get(method_name)) |func| {
            var new_vars: std.StringHashMapUnmanaged(Value) = .{};
            try new_vars.put(self.allocator, "$this", .{ .object = obj });
            self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars, .locals = try self.allocLocals(func, &new_vars), .func = func };
            self.frame_count += 1;
            try self.runLoop(self.frame_count - 1);
            const result = self.pop();
            if (result == .string) return result.string;
            var buf = std.ArrayListUnmanaged(u8){};
            try result.format(&buf, self.allocator);
            const s = try buf.toOwnedSlice(self.allocator);
            try self.strings.append(self.allocator, s);
            return s;
        }
        return "Object";
    }

    // ==================================================================
    // opcode handlers (extracted from runLoop for readability)
    // ==================================================================

    fn handleClassDecl(self: *VM) RuntimeError!void {
        const name_idx = self.readU16();
        const class_name = self.currentChunk().constants.items[name_idx].string;
        const method_count = self.readByte();

        var def = ClassDef{ .name = class_name };

        for (0..method_count) |_| {
            const mi = self.readMethodInfo();
            try def.methods.put(self.allocator, mi[0], mi[1]);
        }

        const prop_count = self.readByte();
        var prop_names: [32][]const u8 = undefined;
        var prop_has_default: [32]u8 = undefined;
        var prop_vis: [32]ClassDef.Visibility = undefined;
        var prop_readonly: [32]bool = .{false} ** 32;
        for (0..prop_count) |pi| {
            const pname_idx = self.readU16();
            prop_names[pi] = self.currentChunk().constants.items[pname_idx].string;
            prop_has_default[pi] = self.readByte();
            const vis_byte = self.readByte();
            prop_vis[pi] = @enumFromInt(vis_byte & 0x03);
            prop_readonly[pi] = (vis_byte & 0x04) != 0;
        }

        const static_prop_count = self.readByte();
        var sprop_names: [32][]const u8 = undefined;
        var sprop_has_default: [32]u8 = undefined;
        for (0..static_prop_count) |pi| {
            const pname_idx = self.readU16();
            sprop_names[pi] = self.currentChunk().constants.items[pname_idx].string;
            sprop_has_default[pi] = self.readByte();
            _ = self.readByte();
        }

        const sdefaults = self.popDefaults(32, sprop_has_default[0..static_prop_count]);
        const defaults = self.popDefaults(32, prop_has_default[0..prop_count]);

        var dj: usize = 0;
        for (0..prop_count) |pi| {
            const default_val = if (prop_has_default[pi] == 1) blk: {
                const v = defaults[dj];
                dj += 1;
                break :blk v;
            } else Value{ .null = {} };
            try def.properties.append(self.allocator, .{
                .name = prop_names[pi],
                .default = default_val,
                .visibility = prop_vis[pi],
                .is_readonly = prop_readonly[pi],
            });
        }

        var sj: usize = 0;
        for (0..static_prop_count) |pi| {
            const default_val = if (sprop_has_default[pi] == 1) blk: {
                const v = sdefaults[sj];
                sj += 1;
                break :blk v;
            } else Value{ .null = {} };
            try def.static_props.put(self.allocator, sprop_names[pi], default_val);
        }

        const parent_idx = self.readU16();
        if (parent_idx != 0xffff) {
            def.parent = self.currentChunk().constants.items[parent_idx].string;
        }

        const iface_count = self.readByte();
        for (0..iface_count) |_| {
            const iname_idx = self.readU16();
            try def.interfaces.append(self.allocator, self.currentChunk().constants.items[iname_idx].string);
        }

        const trait_count = self.readByte();
        var trait_names: [16][]const u8 = undefined;
        for (0..trait_count) |ti| {
            trait_names[ti] = self.currentChunk().constants.items[self.readU16()].string;
        }

        var insteadof_rules: [32]InsteadofRule = undefined;
        var insteadof_count: usize = 0;
        var alias_rules: [32]AliasRule = undefined;
        var alias_count: usize = 0;
        const conflict_count = self.readByte();
        for (0..conflict_count) |_| {
            const method_name = self.currentChunk().constants.items[self.readU16()].string;
            const rule_trait = self.currentChunk().constants.items[self.readU16()].string;
            const rule_type = self.readByte();
            if (rule_type == 1) {
                var rule = InsteadofRule{ .method = method_name, .preferred = rule_trait, .excluded = undefined, .excluded_count = self.readByte() };
                for (0..rule.excluded_count) |ei| {
                    rule.excluded[ei] = self.currentChunk().constants.items[self.readU16()].string;
                }
                insteadof_rules[insteadof_count] = rule;
                insteadof_count += 1;
            } else {
                alias_rules[alias_count] = .{ .method = method_name, .trait = rule_trait, .alias = self.currentChunk().constants.items[self.readU16()].string };
                alias_count += 1;
            }
        }

        for (trait_names[0..trait_count]) |trait_name| {
            try self.applyTrait(&def, class_name, trait_name, alias_rules[0..alias_count], insteadof_rules[0..insteadof_count]);
        }

        def.slot_layout = try self.buildSlotLayout(&def);
        try self.classes.put(self.allocator, class_name, def);
    }

    fn handleEnumDecl(self: *VM) RuntimeError!void {
        const name_idx = self.readU16();
        const enum_name = self.currentChunk().constants.items[name_idx].string;
        const backed_type_byte = self.readByte();
        const case_count = self.readByte();

        var def = ClassDef{ .name = enum_name, .is_enum = true };
        def.backed_type = @enumFromInt(backed_type_byte);

        var case_names: [64][]const u8 = undefined;
        var case_has_value: [64]u8 = undefined;
        for (0..case_count) |ci| {
            case_names[ci] = self.currentChunk().constants.items[self.readU16()].string;
            case_has_value[ci] = self.readByte();
        }

        const case_values = self.popDefaults(64, case_has_value[0..case_count]);

        var vj: usize = 0;
        for (0..case_count) |ci| {
            const case_obj = try self.allocator.create(PhpObject);
            case_obj.* = .{ .class_name = enum_name };
            try self.objects.append(self.allocator, case_obj);
            try case_obj.set(self.allocator, "name", .{ .string = case_names[ci] });
            if (case_has_value[ci] == 1) {
                try case_obj.set(self.allocator, "value", case_values[vj]);
                vj += 1;
            }
            try def.static_props.put(self.allocator, case_names[ci], .{ .object = case_obj });
            try def.case_order.append(self.allocator, case_names[ci]);
        }

        const method_count = self.readByte();
        for (0..method_count) |_| {
            const mi = self.readMethodInfo();
            try def.methods.put(self.allocator, mi[0], mi[1]);
        }

        const iface_count = self.readByte();
        for (0..iface_count) |_| {
            try def.interfaces.append(self.allocator, self.currentChunk().constants.items[self.readU16()].string);
        }

        try self.registerEnumMethods(enum_name, backed_type_byte);
        try self.classes.put(self.allocator, enum_name, def);
    }

    fn readMethodInfo(self: *VM) struct { []const u8, ClassDef.MethodInfo } {
        const mname_idx = self.readU16();
        const method_name = self.currentChunk().constants.items[mname_idx].string;
        const arity = self.readByte();
        const is_static = self.readByte() == 1;
        const vis: ClassDef.Visibility = @enumFromInt(self.readByte());
        return .{ method_name, .{ .name = method_name, .arity = arity, .is_static = is_static, .visibility = vis } };
    }

    fn popDefaults(self: *VM, comptime max: usize, has_default: []const u8) [max]Value {
        var values: [max]Value = undefined;
        var count: usize = 0;
        for (has_default) |hd| {
            if (hd == 1) count += 1;
        }
        var i: usize = count;
        while (i > 0) {
            i -= 1;
            values[i] = self.pop();
        }
        return values;
    }

    fn registerEnumMethods(self: *VM, enum_name: []const u8, backed_type_byte: u8) !void {
        const cases_name = try std.fmt.allocPrint(self.allocator, "{s}::cases", .{enum_name});
        try self.strings.append(self.allocator, cases_name);
        try self.native_fns.put(self.allocator, cases_name, enums.enumCases);

        if (backed_type_byte != 0) {
            const from_name = try std.fmt.allocPrint(self.allocator, "{s}::from", .{enum_name});
            try self.strings.append(self.allocator, from_name);
            try self.native_fns.put(self.allocator, from_name, enums.enumFrom);

            const try_from_name = try std.fmt.allocPrint(self.allocator, "{s}::tryFrom", .{enum_name});
            try self.strings.append(self.allocator, try_from_name);
            try self.native_fns.put(self.allocator, try_from_name, enums.enumTryFrom);
        }
    }

    const InsteadofRule = struct { method: []const u8, preferred: []const u8, excluded: [16][]const u8, excluded_count: u8 };
    const AliasRule = struct { method: []const u8, trait: []const u8, alias: []const u8 };

    fn applyTrait(self: *VM, def: *ClassDef, class_name: []const u8, trait_name: []const u8, alias_rules: []const AliasRule, insteadof_rules: []const InsteadofRule) !void {
        const TraitMethod = struct { name: []const u8, func: *const ObjFunction };
        var pending: [64]TraitMethod = undefined;
        var pending_count: usize = 0;
        {
            var fn_iter = self.functions.iterator();
            while (fn_iter.next()) |entry| {
                const fn_name = entry.key_ptr.*;
                if (fn_name.len > trait_name.len + 2 and
                    std.mem.eql(u8, fn_name[0..trait_name.len], trait_name) and
                    std.mem.eql(u8, fn_name[trait_name.len .. trait_name.len + 2], "::"))
                {
                    pending[pending_count] = .{ .name = fn_name[trait_name.len + 2 ..], .func = entry.value_ptr.* };
                    pending_count += 1;
                }
            }
        }

        for (pending[0..pending_count]) |tm| {
            var vis_override: ?ClassDef.Visibility = null;
            for (alias_rules) |rule| {
                if (std.mem.eql(u8, rule.method, tm.name) and std.mem.eql(u8, rule.trait, trait_name)) {
                    if (std.mem.eql(u8, rule.alias, "public")) {
                        vis_override = .public;
                    } else if (std.mem.eql(u8, rule.alias, "protected")) {
                        vis_override = .protected;
                    } else if (std.mem.eql(u8, rule.alias, "private")) {
                        vis_override = .private;
                    } else {
                        const alias_method = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ class_name, rule.alias });
                        try self.strings.append(self.allocator, alias_method);
                        if (!self.functions.contains(alias_method)) {
                            try self.functions.put(self.allocator, alias_method, tm.func);
                            try def.methods.put(self.allocator, rule.alias, .{ .name = rule.alias, .arity = tm.func.arity });
                        }
                    }
                }
            }

            var excluded = false;
            for (insteadof_rules) |rule| {
                if (std.mem.eql(u8, rule.method, tm.name)) {
                    if (std.mem.eql(u8, rule.preferred, trait_name)) break;
                    for (rule.excluded[0..rule.excluded_count]) |ex| {
                        if (std.mem.eql(u8, ex, trait_name)) { excluded = true; break; }
                    }
                    if (excluded) break;
                }
            }
            if (excluded) continue;

            const class_method = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ class_name, tm.name });
            try self.strings.append(self.allocator, class_method);
            if (!self.functions.contains(class_method)) {
                try self.functions.put(self.allocator, class_method, tm.func);
                try def.methods.put(self.allocator, tm.name, .{
                    .name = tm.name,
                    .arity = tm.func.arity,
                    .visibility = vis_override orelse .public,
                });
            }
        }
    }

    // ==================================================================
    // closure and frame helpers
    // ==================================================================

    fn ensureClosureInstance(self: *VM) !void {
        const compile_name = self.peek().string;
        if (std.mem.startsWith(u8, compile_name, "__closure_") and
            !std.mem.containsAtLeast(u8, compile_name["__closure_".len..], 1, "_"))
        {
            const id = self.closure_instance_count;
            self.closure_instance_count += 1;
            const inst_name = try std.fmt.allocPrint(self.allocator, "{s}_{d}", .{ compile_name, id });
            try self.strings.append(self.allocator, inst_name);
            if (self.functions.get(compile_name)) |func| {
                try self.functions.put(self.allocator, inst_name, func);
            }
            self.stack[self.sp - 1] = .{ .string = inst_name };
        }
    }

    fn getLocalByName(self: *VM, name: []const u8) Value {
        const frame = self.currentFrame();
        if (frame.func) |func| {
            for (func.slot_names, 0..) |sn, si| {
                if (std.mem.eql(u8, sn, name)) {
                    if (si < frame.locals.len) return frame.locals[si];
                    break;
                }
            }
        }
        return .null;
    }

    fn saveFrameLocalsToGenerator(self: *VM, gen: *Generator) void {
        const frame = self.currentFrame();
        gen.locals.clearRetainingCapacity();
        if (frame.locals.len > 0) {
            gen.locals.appendSlice(self.allocator, frame.locals) catch {};
            self.allocator.free(frame.locals);
            self.currentFrame().locals = &.{};
        }
    }

    fn saveGeneratorHandlers(self: *VM, gen: *Generator) void {
        const count = self.handler_count - self.handler_floor;
        gen.handler_count = count;
        for (0..count) |i| {
            const h = self.exception_handlers[self.handler_floor + i];
            gen.saved_handlers[i] = .{
                .catch_ip = h.catch_ip,
                .sp_offset = h.sp -| gen.base_sp,
                .chunk = h.chunk,
            };
        }
        self.handler_count = self.handler_floor;
    }

    fn restoreGeneratorHandlers(self: *VM, gen: *Generator) void {
        for (0..gen.handler_count) |i| {
            const h = gen.saved_handlers[i];
            self.exception_handlers[self.handler_count] = .{
                .catch_ip = h.catch_ip,
                .frame_count = self.frame_count,
                .sp = gen.base_sp + h.sp_offset,
                .chunk = h.chunk,
            };
            self.handler_count += 1;
        }
    }

    fn callClosureLocalsOnly(self: *VM, func: *const ObjFunction, name: []const u8, arg_count: u8) RuntimeError!void {
        const ac: usize = arg_count;
        const lc: usize = func.local_count;

        // check if any captures are by-ref - if so, can't use locals-only fast path
        // because fastLoop's set_local doesn't update ref_slots
        for (self.captures.items) |cap| {
            if (cap.ref_cell != null and
                (cap.closure_name.ptr == name.ptr or
                (cap.closure_name.len == name.len and std.mem.eql(u8, cap.closure_name, name))))
            {
                // fall through to non-locals path via callNamedFunction's slow path
                var new_vars: std.StringHashMapUnmanaged(Value) = .{};
                var closure_refs: std.StringHashMapUnmanaged(*Value) = .{};
                try self.bindClosures(&new_vars, &closure_refs, name);
                const bind_count = @min(ac, func.arity);
                for (0..bind_count) |i| {
                    try new_vars.put(self.allocator, func.params[i], try self.copyValue(self.stack[self.sp - ac + i]));
                }
                self.sp -= ac;
                try self.fillDefaults(&new_vars, func, bind_count);
                const inherit_cc = self.currentFrame().called_class;
                self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars, .locals = try self.allocLocals(func, &new_vars), .func = func, .ref_slots = closure_refs, .called_class = inherit_cc };
                self.setFrameArgCount(arg_count);
                self.frame_count += 1;
                return;
            }
        }

        const ic = self.ic.?;
        const base = ic.locals_sp;

        const locals = if (base + lc <= ic.locals_cap) blk: {
            const s = ic.locals_buf[base..base + lc];
            @memset(s, .null);
            ic.locals_sp = base + lc;
            break :blk s;
        } else blk: {
            const s = try self.allocator.alloc(Value, lc);
            @memset(s, .null);
            break :blk s;
        };

        // bind args to param slots
        const bind_count = @min(ac, func.arity);
        for (0..bind_count) |i| {
            locals[i] = try self.copyValue(self.stack[self.sp - ac + i]);
        }
        for (bind_count..func.arity) |i| {
            if (i < func.defaults.len) locals[i] = func.defaults[i];
        }
        self.sp -= ac;

        // bind captures directly to locals using slot_names
        for (self.captures.items) |cap| {
            if (cap.closure_name.ptr == name.ptr or
                (cap.closure_name.len == name.len and std.mem.eql(u8, cap.closure_name, name)))
            {
                for (func.slot_names, 0..) |sn, si| {
                    if (sn.len == cap.var_name.len and std.mem.eql(u8, sn, cap.var_name)) {
                        locals[si] = try self.copyValue(cap.value);
                        break;
                    }
                }
            }
        }

        self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = .{}, .locals = locals, .func = func, .called_class = self.currentFrame().called_class };
        self.setFrameArgCount(arg_count);
        self.frame_count += 1;
        try self.fastLoop();
    }

    fn callLocalsOnly(self: *VM, func: *const ObjFunction, arg_count: u8) RuntimeError!void {
        const ac: usize = arg_count;
        const lc: usize = func.local_count;
        const ic = self.ic.?;
        const base = ic.locals_sp;

        const locals = if (base + lc <= ic.locals_cap) blk: {
            const s = ic.locals_buf[base..base + lc];
            @memset(s, .null);
            ic.locals_sp = base + lc;
            break :blk s;
        } else blk: {
            const s = try self.allocator.alloc(Value, lc);
            @memset(s, .null);
            break :blk s;
        };

        const bind_count = @min(ac, func.arity);
        for (0..bind_count) |i| {
            locals[i] = try self.copyValue(self.stack[self.sp - ac + i]);
        }
        for (bind_count..func.arity) |i| {
            if (i < func.defaults.len) locals[i] = func.defaults[i];
        }
        self.sp -= ac;
        self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = .{}, .locals = locals, .func = func };
        self.setFrameArgCount(arg_count);
        self.frame_count += 1;
        try self.fastLoop();
    }

    // tight inner interpreter with local ip/sp for hot loops in locals-only functions.
    // handles common opcodes plus call/ret for locals-only functions.
    // returns to runLoop for anything complex (native calls, closures, exceptions, property access).
    fn fastLoop(self: *VM) RuntimeError!void {
        const ic = self.ic.?;
        const entry_fc = self.frame_count;

        reenter: while (true) {
            const frame = &self.frames[self.frame_count - 1];
            const code = frame.chunk.code.items;
            var locals = frame.locals;
            const consts = frame.chunk.constants.items;
            var ip = frame.ip;
            var sp = self.sp;

            while (true) {
                const byte: OpCode = @enumFromInt(code[ip]);
                ip += 1;

                dispatch: switch (byte) {
                .get_local => {
                    const slot = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    ip += 2;
                    self.stack[sp] = locals[slot];
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .set_local => {
                    const slot = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    ip += 2;
                    const val = self.stack[sp - 1];
                    if (val == .array) {
                        locals[slot] = try self.copyValue(val);
                    } else {
                        locals[slot] = val;
                    }
                    if (code[ip] == @intFromEnum(OpCode.pop)) {
                        ip += 1;
                        sp -= 1;
                    }
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .add => {
                    const b = self.stack[sp - 1];
                    const a = self.stack[sp - 2];
                    sp -= 2;
                    self.stack[sp] = if (a == .int and b == .int) .{ .int = a.int +% b.int } else if (a == .float and b == .float) .{ .float = a.float + b.float } else Value.add(a, b);
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .subtract => {
                    const b = self.stack[sp - 1];
                    const a = self.stack[sp - 2];
                    sp -= 2;
                    self.stack[sp] = if (a == .int and b == .int) .{ .int = a.int -% b.int } else if (a == .float and b == .float) .{ .float = a.float - b.float } else Value.subtract(a, b);
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .multiply => {
                    const b = self.stack[sp - 1];
                    const a = self.stack[sp - 2];
                    sp -= 2;
                    self.stack[sp] = if (a == .int and b == .int) .{ .int = a.int *% b.int } else if (a == .float and b == .float) .{ .float = a.float * b.float } else Value.multiply(a, b);
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .less => {
                    const b = self.stack[sp - 1];
                    const a = self.stack[sp - 2];
                    sp -= 2;
                    self.stack[sp] = .{ .bool = if (a == .int and b == .int) a.int < b.int else if (a == .float and b == .float) a.float < b.float else Value.lessThan(a, b) };
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .less_equal => {
                    const b = self.stack[sp - 1];
                    const a = self.stack[sp - 2];
                    sp -= 2;
                    self.stack[sp] = .{ .bool = if (a == .int and b == .int) a.int <= b.int else !Value.lessThan(b, a) };
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .greater => {
                    const b = self.stack[sp - 1];
                    const a = self.stack[sp - 2];
                    sp -= 2;
                    self.stack[sp] = .{ .bool = if (a == .int and b == .int) a.int > b.int else Value.lessThan(b, a) };
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .identical => {
                    const b_id = self.stack[sp - 1];
                    const a_id = self.stack[sp - 2];
                    sp -= 2;
                    self.stack[sp] = .{ .bool = Value.identical(a_id, b_id) };
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .not_identical => {
                    const b_ni = self.stack[sp - 1];
                    const a_ni = self.stack[sp - 2];
                    sp -= 2;
                    self.stack[sp] = .{ .bool = !Value.identical(a_ni, b_ni) };
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .modulo => {
                    const b_mod = self.stack[sp - 1];
                    const a_mod = self.stack[sp - 2];
                    sp -= 2;
                    self.stack[sp] = Value.modulo(a_mod, b_mod);
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .negate => {
                    self.stack[sp - 1] = self.stack[sp - 1].negate();
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .not => {
                    self.stack[sp - 1] = .{ .bool = !self.stack[sp - 1].isTruthy() };
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .jump_back => {
                    const offset = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    ip += 2;
                    ip -= offset;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .constant => {
                    const idx = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    ip += 2;
                    self.stack[sp] = consts[idx];
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .jump_if_false => {
                    const offset = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    ip += 2;
                    if (!self.stack[sp - 1].isTruthy()) {
                        ip += offset;
                    } else if (code[ip] == @intFromEnum(OpCode.pop)) {
                        ip += 1;
                        sp -= 1;
                    }
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .jump => {
                    const offset = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    ip += 2;
                    ip += offset;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .pop => {
                    sp -= 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .dup => {
                    self.stack[sp] = self.stack[sp - 1];
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .op_null => {
                    self.stack[sp] = .null;
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .op_true => {
                    self.stack[sp] = .{ .bool = true };
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .op_false => {
                    self.stack[sp] = .{ .bool = false };
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .cast_int => {
                    const v = self.stack[sp - 1];
                    self.stack[sp - 1] = .{ .int = Value.toInt(v) };
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .array_get => {
                    const ag_key = self.stack[sp - 1];
                    const ag_arr = self.stack[sp - 2];
                    sp -= 2;
                    if (ag_arr == .array) {
                        self.stack[sp] = ag_arr.array.get(Value.toArrayKey(ag_key));
                        sp += 1;
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else {
                        frame.ip = ip - 1;
                        self.sp = sp + 2;
                        return;
                    }
                },
                .array_get_vivify => {
                    const agv_key = self.stack[sp - 1];
                    const agv_arr = self.stack[sp - 2];
                    sp -= 2;
                    if (agv_arr == .array) {
                        const agv_arr_key = Value.toArrayKey(agv_key);
                        const agv_existing = agv_arr.array.get(agv_arr_key);
                        if (agv_existing == .array) {
                            self.stack[sp] = agv_existing;
                            sp += 1;
                            const _next = code[ip];
                            ip += 1;
                            continue :dispatch @as(OpCode, @enumFromInt(_next));
                        } else {
                            frame.ip = ip - 1;
                            self.sp = sp + 2;
                            return;
                        }
                    } else {
                        frame.ip = ip - 1;
                        self.sp = sp + 2;
                        return;
                    }
                },
                .call_indirect => {
                    const ci_ac = code[ip];
                    ip += 1;
                    const ci_acn: usize = ci_ac;
                    const ci_name_val = self.stack[sp - ci_acn - 1];
                    if (ci_name_val != .string) {
                        frame.ip = ip - 2;
                        self.sp = sp;
                        return;
                    }
                    const ci_name = ci_name_val.string;
                    const ci_func = self.functions.get(ci_name) orelse {
                        frame.ip = ip - 2;
                        self.sp = sp;
                        return;
                    };
                    // only handle locals-only functions in fastLoop
                    if (!ci_func.locals_only) {
                        frame.ip = ip - 2;
                        self.sp = sp;
                        return;
                    }
                    const ci_cap_range = self.getCaptureRange(ci_name);
                    if (ci_cap_range != null and !std.mem.startsWith(u8, ci_name, "__closure_")) {
                        frame.ip = ip - 2;
                        self.sp = sp;
                        return;
                    }
                    if (ci_cap_range) |cr| {
                        if (cr.has_refs) {
                            frame.ip = ip - 2;
                            self.sp = sp;
                            return;
                        }
                    }
                    const ci_lc: usize = ci_func.local_count;
                    const ci_lbase = ic.locals_sp;
                    if (ci_lbase + ci_lc > ic.locals_cap) {
                        frame.ip = ip - 2;
                        self.sp = sp;
                        return;
                    }
                    // past all bail points - safe to modify stack
                    // shift args down to overwrite the callable
                    for (0..ci_acn) |i| {
                        self.stack[sp - ci_acn - 1 + i] = self.stack[sp - ci_acn + i];
                    }
                    sp -= 1;
                    const ci_locals = ic.locals_buf[ci_lbase .. ci_lbase + ci_lc];
                    @memset(ci_locals, .null);
                    ic.locals_sp = ci_lbase + ci_lc;
                    const ci_bind = @min(ci_acn, ci_func.arity);
                    for (0..ci_bind) |i| ci_locals[i] = self.stack[sp - ci_acn + i];
                    for (ci_bind..ci_func.arity) |i| {
                        if (i < ci_func.defaults.len) ci_locals[i] = ci_func.defaults[i];
                    }
                    sp -= ci_acn;
                    if (ci_cap_range) |cr| {
                        const caps = self.captures.items[cr.start .. cr.start + cr.len];
                        for (caps) |cap| {
                            for (ci_func.slot_names, 0..) |sn, si| {
                                if (sn.len == cap.var_name.len and std.mem.eql(u8, sn, cap.var_name)) {
                                    ci_locals[si] = cap.value;
                                    break;
                                }
                            }
                        }
                    }
                    ic.sp_save[self.frame_count - 1] = sp;
                    self.sp = sp;
                    frame.ip = ip;
                    self.frames[self.frame_count] = .{
                        .chunk = &ci_func.chunk,
                        .ip = 0,
                        .vars = .{},
                        .locals = ci_locals,
                        .func = ci_func,
                    };
                    self.frame_count += 1;
                    continue :reenter;
                },
                .get_prop => {
                    const gp_ip = ip;
                    ip += 2;
                    const gp_obj_val = self.stack[sp - 1];
                    if (gp_obj_val == .object) {
                        const gp_obj = gp_obj_val.object;
                        const gp_idx = InlineCache.propIndex(@intFromPtr(frame.chunk), gp_ip);
                        const gp_entry = &ic.prop[gp_idx];
                        if (gp_entry.key == gp_ip and gp_entry.chunk_key == @intFromPtr(frame.chunk) and gp_entry.class_ptr == @intFromPtr(gp_obj.class_name.ptr) and gp_entry.slot_index != 0xFFFF) {
                            if (gp_obj.slots) |s| {
                                self.stack[sp - 1] = s[gp_entry.slot_index];
                                const _next_gp = code[ip];
                                ip += 1;
                                continue :dispatch @as(OpCode, @enumFromInt(_next_gp));
                            }
                        }
                    }
                    // bail to runLoop for IC miss or non-object
                    frame.ip = ip - 3;
                    self.sp = sp;
                    return;
                },
                .set_prop => {
                    const sp_ip = ip;
                    ip += 2;
                    const sp_val = self.stack[sp - 1];
                    const sp_obj_val = self.stack[sp - 2];
                    if (sp_obj_val == .object) {
                        const sp_obj = sp_obj_val.object;
                        const sp_idx = InlineCache.propIndex(@intFromPtr(frame.chunk), sp_ip);
                        const sp_entry = &ic.prop[sp_idx];
                        if (sp_entry.key == sp_ip and sp_entry.chunk_key == @intFromPtr(frame.chunk) and sp_entry.class_ptr == @intFromPtr(sp_obj.class_name.ptr) and sp_entry.slot_index != 0xFFFF) {
                            if (sp_obj.slots) |s| {
                                const copied = if (sp_val == .array) try self.copyValue(sp_val) else sp_val;
                                s[sp_entry.slot_index] = copied;
                                sp -= 1;
                                self.stack[sp - 1] = copied;
                                const _next_sp = code[ip];
                                ip += 1;
                                continue :dispatch @as(OpCode, @enumFromInt(_next_sp));
                            }
                        }
                    }
                    frame.ip = ip - 3;
                    self.sp = sp;
                    return;
                },
                .method_call => {
                    const mc_arg_count = code[ip + 2];
                    ip += 3;
                    const mc_ac: usize = mc_arg_count;
                    const mc_obj_val = self.stack[sp - mc_ac - 1];
                    if (mc_obj_val != .object) {
                        frame.ip = ip - 4;
                        self.sp = sp;
                        return;
                    }
                    const mc_obj = mc_obj_val.object;
                    const mc_ip = ip - 4;
                    const mc_idx = InlineCache.methodIndex(@intFromPtr(frame.chunk), mc_ip);
                    const mc_entry = &ic.method[mc_idx];
                    if (mc_entry.key == mc_ip and mc_entry.class_ptr == @intFromPtr(mc_obj.class_name.ptr)) {
                        if (mc_entry.func) |mc_func| {
                            if (mc_func.locals_only and self.captures.items.len == 0) {
                                const mc_lc: usize = mc_func.local_count;
                                const mc_lbase = ic.locals_sp;
                                if (mc_lbase + mc_lc > ic.locals_cap) {
                                    frame.ip = ip - 4;
                                    self.sp = sp;
                                    return;
                                }
                                const mc_locals = ic.locals_buf[mc_lbase .. mc_lbase + mc_lc];
                                @memset(mc_locals, .null);
                                ic.locals_sp = mc_lbase + mc_lc;
                                mc_locals[0] = .{ .object = mc_obj };
                                for (0..@min(mc_ac, mc_func.arity)) |i| {
                                    mc_locals[i + 1] = self.stack[sp - mc_ac + i];
                                }
                                for (@min(mc_ac, mc_func.arity)..mc_func.arity) |i| {
                                    if (i < mc_func.defaults.len) mc_locals[i + 1] = mc_func.defaults[i];
                                }
                                sp -= mc_ac + 1;
                                frame.ip = ip;
                                ic.sp_save[self.frame_count - 1] = sp;
                                self.sp = sp;
                                self.frames[self.frame_count] = .{
                                    .chunk = &mc_func.chunk,
                                    .ip = 0,
                                    .vars = .{},
                                    .locals = mc_locals,
                                    .func = mc_func,
                                };
                                self.frame_count += 1;
                                continue :reenter;
                            }
                        }
                    }
                    // bail for IC miss, native method, or non-locals-only
                    frame.ip = ip - 4;
                    self.sp = sp;
                    return;
                },
                .new_obj => {
                    // fast path for new_obj: slot-based initialization
                    const no_name_idx = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    const no_arg_count = code[ip + 2];
                    ip += 3;
                    const no_class_name = consts[no_name_idx].string;
                    const cls = self.classes.get(no_class_name) orelse {
                        frame.ip = ip - 4;
                        self.sp = sp;
                        return;
                    };
                    if (std.mem.eql(u8, no_class_name, "static") or std.mem.eql(u8, no_class_name, "self") or std.mem.eql(u8, no_class_name, "parent") or std.mem.eql(u8, no_class_name, "Fiber")) {
                        frame.ip = ip - 4;
                        self.sp = sp;
                        return;
                    }
                    const no_obj = self.allocator.create(PhpObject) catch {
                        frame.ip = ip - 4;
                        self.sp = sp;
                        return;
                    };
                    no_obj.* = .{ .class_name = no_class_name };
                    self.objects.append(self.allocator, no_obj) catch {
                        frame.ip = ip - 4;
                        self.sp = sp;
                        return;
                    };
                    // slot-based init
                    if (cls.slot_layout) |layout| {
                        const no_slots = self.allocator.alloc(Value, layout.names.len) catch {
                            frame.ip = ip - 4;
                            self.sp = sp;
                            return;
                        };
                        @memcpy(no_slots, layout.defaults);
                        no_obj.slots = no_slots;
                        no_obj.slot_layout = layout;
                    }
                    // constructor
                    const no_ac: usize = no_arg_count;
                    const ctor_name = self.resolveMethod(no_class_name, "__construct") catch null;
                    if (ctor_name) |cn| {
                        if (self.functions.get(cn)) |ctor_func| {
                            if (ctor_func.locals_only and self.captures.items.len == 0) {
                                const ctor_lc: usize = ctor_func.local_count;
                                const ctor_lbase = ic.locals_sp;
                                if (ctor_lbase + ctor_lc <= ic.locals_cap) {
                                    const ctor_locals = ic.locals_buf[ctor_lbase .. ctor_lbase + ctor_lc];
                                    @memset(ctor_locals, .null);
                                    ic.locals_sp = ctor_lbase + ctor_lc;
                                    ctor_locals[0] = .{ .object = no_obj };
                                    for (0..@min(no_ac, ctor_func.arity)) |i| {
                                        ctor_locals[i + 1] = self.stack[sp - no_ac + i];
                                    }
                                    for (@min(no_ac, ctor_func.arity)..ctor_func.arity) |i| {
                                        if (i < ctor_func.defaults.len) ctor_locals[i + 1] = ctor_func.defaults[i];
                                    }
                                    sp -= no_ac;
                                    self.sp = sp;
                                    // run constructor inline
                                    self.frames[self.frame_count] = .{
                                        .chunk = &ctor_func.chunk,
                                        .ip = 0,
                                        .vars = .{},
                                        .locals = ctor_locals,
                                        .func = ctor_func,
                                    };
                                    self.frame_count += 1;
                                    const ctor_base = self.frame_count - 1;
                                    frame.ip = ip;
                                    self.runUntilFrame(ctor_base) catch {
                                        frame.ip = ip;
                                        self.sp = sp;
                                        return;
                                    };
                                    sp = self.sp;
                                    _ = self.stack[sp - 1]; // pop the null from constructor return
                                    sp -= 1;
                                    self.stack[sp] = .{ .object = no_obj };
                                    sp += 1;
                                    const _next2 = code[ip];
                                    ip += 1;
                                    continue :dispatch @as(OpCode, @enumFromInt(_next2));
                                }
                            }
                        }
                    } else {
                        // no constructor
                        sp -= no_ac;
                        self.stack[sp] = .{ .object = no_obj };
                        sp += 1;
                        const _next_no = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next_no));
                    }
                    frame.ip = ip - 4;
                    self.sp = sp;
                    return;
                },
                .call => {
                    const name_idx = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    const arg_count = code[ip + 2];
                    ip += 3;

                    const name = consts[name_idx].string;
                    const func = blk: {
                        if (ic.fn_cache_name.len == name.len and std.mem.eql(u8, ic.fn_cache_name, name))
                            break :blk ic.fn_cache_func.?;
                        if (self.functions.get(name)) |f| {
                            ic.fn_cache_name = name;
                            ic.fn_cache_func = f;
                            break :blk f;
                        }
                        // native or unknown - bail to runLoop
                        frame.ip = ip - 4;
                        self.sp = sp;
                        return;
                    };

                    if (!func.locals_only or self.captures.items.len > 0) {
                        frame.ip = ip - 4;
                        self.sp = sp;
                        return;
                    }

                    const ac: usize = arg_count;
                    const lc: usize = func.local_count;
                    const lbase = ic.locals_sp;

                    if (lbase + lc > ic.locals_cap) {
                        frame.ip = ip - 4;
                        self.sp = sp;
                        return;
                    }

                    const new_locals = ic.locals_buf[lbase .. lbase + lc];
                    @memset(new_locals, .null);
                    ic.locals_sp = lbase + lc;

                    const bind_count = @min(ac, func.arity);
                    for (0..bind_count) |i| {
                        new_locals[i] = self.stack[sp - ac + i];
                    }
                    for (bind_count..func.arity) |i| {
                        if (i < func.defaults.len) new_locals[i] = func.defaults[i];
                    }
                    sp -= ac;

                    frame.ip = ip;
                    ic.sp_save[self.frame_count - 1] = sp;
                    self.sp = sp;

                    self.frames[self.frame_count] = .{
                        .chunk = &func.chunk,
                        .ip = 0,
                        .vars = .{},
                        .locals = new_locals,
                        .func = func,
                    };
                    self.frame_count += 1;
                    continue :reenter;
                },
                .return_val => {
                    const result = self.stack[sp - 1];
                    // if this frame has vars, bail to runLoop for full cleanup
                    if (frame.vars.count() > 0 or frame.ref_slots.count() > 0) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    if (locals.len > 0) self.freeLocals(locals);
                    self.frame_count -= 1;

                    if (self.frame_count < entry_fc) {
                        self.stack[sp - 1] = result;
                        self.sp = sp;
                        return;
                    }

                    // restore caller's sp from saved state and push result
                    sp = ic.sp_save[self.frame_count - 1];
                    self.stack[sp] = result;
                    sp += 1;
                    self.sp = sp;
                    continue :reenter;
                },
                .return_void => {
                    if (frame.vars.count() > 0 or frame.ref_slots.count() > 0) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    if (locals.len > 0) self.freeLocals(locals);
                    self.frame_count -= 1;

                    if (self.frame_count < entry_fc) {
                        self.stack[sp] = .null;
                        self.sp = sp + 1;
                        return;
                    }

                    sp = ic.sp_save[self.frame_count - 1];
                    self.stack[sp] = .null;
                    sp += 1;
                    self.sp = sp;
                    continue :reenter;
                },
                .inc_local => {
                    const slot = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    ip += 2;
                    const v = locals[slot];
                    if (v == .int) {
                        locals[slot] = .{ .int = v.int +% 1 };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else if (v == .float) {
                        locals[slot] = .{ .float = v.float + 1.0 };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else {
                        frame.ip = ip - 3;
                        self.sp = sp;
                        return;
                    }
                },
                .dec_local => {
                    const slot = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    ip += 2;
                    const v = locals[slot];
                    if (v == .int) {
                        locals[slot] = .{ .int = v.int -% 1 };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else if (v == .float) {
                        locals[slot] = .{ .float = v.float - 1.0 };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else {
                        frame.ip = ip - 3;
                        self.sp = sp;
                        return;
                    }
                },
                .add_local_to_local => {
                    const src_slot = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    const dst_slot = (@as(u16, code[ip + 2]) << 8) | code[ip + 3];
                    ip += 4;
                    const src = locals[src_slot];
                    const dst = locals[dst_slot];
                    if (src == .int and dst == .int) {
                        locals[dst_slot] = .{ .int = dst.int +% src.int };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else if (src == .float and dst == .float) {
                        locals[dst_slot] = .{ .float = dst.float + src.float };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else if (src == .int and dst == .float) {
                        locals[dst_slot] = .{ .float = dst.float + @as(f64, @floatFromInt(src.int)) };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else if (src == .float and dst == .int) {
                        locals[dst_slot] = .{ .float = @as(f64, @floatFromInt(dst.int)) + src.float };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else {
                        frame.ip = ip - 5;
                        self.sp = sp;
                        return;
                    }
                },
                .sub_local_to_local => {
                    const src_slot = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    const dst_slot = (@as(u16, code[ip + 2]) << 8) | code[ip + 3];
                    ip += 4;
                    const src = locals[src_slot];
                    const dst = locals[dst_slot];
                    if (src == .int and dst == .int) {
                        locals[dst_slot] = .{ .int = dst.int -% src.int };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else if (src == .float and dst == .float) {
                        locals[dst_slot] = .{ .float = dst.float - src.float };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else {
                        frame.ip = ip - 5;
                        self.sp = sp;
                        return;
                    }
                },
                .mul_local_to_local => {
                    const src_slot = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    const dst_slot = (@as(u16, code[ip + 2]) << 8) | code[ip + 3];
                    ip += 4;
                    const src = locals[src_slot];
                    const dst = locals[dst_slot];
                    if (src == .int and dst == .int) {
                        locals[dst_slot] = .{ .int = dst.int *% src.int };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else if (src == .float and dst == .float) {
                        locals[dst_slot] = .{ .float = dst.float * src.float };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else if (src == .float and dst == .int) {
                        locals[dst_slot] = .{ .float = @as(f64, @floatFromInt(dst.int)) * src.float };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else if (src == .int and dst == .float) {
                        locals[dst_slot] = .{ .float = dst.float * @as(f64, @floatFromInt(src.int)) };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else {
                        frame.ip = ip - 5;
                        self.sp = sp;
                        return;
                    }
                },
                .less_local_local_jif => {
                    const slot_a = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    const slot_b = (@as(u16, code[ip + 2]) << 8) | code[ip + 3];
                    const offset = (@as(u16, code[ip + 4]) << 8) | code[ip + 5];
                    ip += 6;
                    const a = locals[slot_a];
                    const b = locals[slot_b];
                    if (a == .int and b == .int) {
                        if (a.int >= b.int) ip += offset;
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else if (a == .float and b == .float) {
                        if (a.float >= b.float) ip += offset;
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else {
                        frame.ip = ip - 7;
                        self.sp = sp;
                        return;
                    }
                },
                .concat => {
                    const b = self.stack[sp - 1];
                    const a = self.stack[sp - 2];
                    if (a == .string and b == .string) {
                        const as = a.string;
                        const bs = b.string;
                        const owned = try self.allocator.alloc(u8, as.len + bs.len);
                        @memcpy(owned[0..as.len], as);
                        @memcpy(owned[as.len..], bs);
                        try self.strings.append(self.allocator, owned);
                        sp -= 1;
                        self.stack[sp - 1] = .{ .string = owned };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else if (a == .string and b == .int) {
                        var tmp: [20]u8 = undefined;
                        const bs = std.fmt.bufPrint(&tmp, "{d}", .{b.int}) catch {
                            frame.ip = ip - 1;
                            self.sp = sp;
                            return;
                        };
                        const owned = try self.allocator.alloc(u8, a.string.len + bs.len);
                        @memcpy(owned[0..a.string.len], a.string);
                        @memcpy(owned[a.string.len..], bs);
                        try self.strings.append(self.allocator, owned);
                        sp -= 1;
                        self.stack[sp - 1] = .{ .string = owned };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else if (a == .int and b == .string) {
                        var tmp: [20]u8 = undefined;
                        const as = std.fmt.bufPrint(&tmp, "{d}", .{a.int}) catch {
                            frame.ip = ip - 1;
                            self.sp = sp;
                            return;
                        };
                        const owned = try self.allocator.alloc(u8, as.len + b.string.len);
                        @memcpy(owned[0..as.len], as);
                        @memcpy(owned[as.len..], b.string);
                        try self.strings.append(self.allocator, owned);
                        sp -= 1;
                        self.stack[sp - 1] = .{ .string = owned };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                },
                else => {
                    frame.ip = ip - 1;
                    self.sp = sp;
                    return;
                },
                }
            }
        }
    }

    fn executeFunctionLocalsOnly(self: *VM, func: *const ObjFunction, args: []const Value) RuntimeError!Value {
        const base_frame = self.frame_count;
        const lc: usize = func.local_count;
        const ic = self.ic.?;
        const lbase = ic.locals_sp;

        const locals = if (lbase + lc <= ic.locals_cap) blk: {
            const s = ic.locals_buf[lbase..lbase + lc];
            @memset(s, .null);
            ic.locals_sp = lbase + lc;
            break :blk s;
        } else blk: {
            const s = try self.allocator.alloc(Value, lc);
            @memset(s, .null);
            break :blk s;
        };

        const bind_count = @min(args.len, func.arity);
        for (0..bind_count) |i| {
            locals[i] = try self.copyValue(args[i]);
        }
        for (bind_count..func.arity) |i| {
            if (i < func.defaults.len) locals[i] = func.defaults[i];
        }
        self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = .{}, .locals = locals, .func = func };
        self.consumePendingArgCount();
        self.frame_count += 1;
        try self.runUntilFrame(base_frame);
        return self.pop();
    }

    fn allocLocals(self: *VM, func: *const ObjFunction, vars: *const std.StringHashMapUnmanaged(Value)) ![]Value {
        if (func.local_count == 0) return &.{};
        const locals = try self.allocator.alloc(Value, func.local_count);
        @memset(locals, .null);
        for (func.slot_names, 0..) |name, i| {
            if (name.len > 0) {
                if (vars.get(name)) |val| {
                    locals[i] = val;
                }
            }
        }
        return locals;
    }

    fn popFrame(self: *VM) !void {
        try self.writebackStatics();
        try self.writebackGlobals();
        try self.writebackRefs();
        self.frame_count -= 1;
        self.frames[self.frame_count].ref_slots.deinit(self.allocator);
        self.frames[self.frame_count].vars.deinit(self.allocator);
        if (self.frames[self.frame_count].locals.len > 0) {
            self.freeLocals(self.frames[self.frame_count].locals);
            self.frames[self.frame_count].locals = &.{};
        }
    }

    fn freeLocals(self: *VM, locals: []Value) void {
        if (self.ic) |ic| {
            const lptr = @intFromPtr(locals.ptr);
            const sptr = @intFromPtr(ic.locals_buf);
            if (lptr >= sptr and lptr < sptr + ic.locals_cap * @sizeOf(Value)) {
                ic.locals_sp -= locals.len;
                return;
            }
        }
        self.allocator.free(locals);
    }

    fn cleanupFiberFrames(self: *VM, fiber: *Fiber) void {
        for (fiber.saved_frames.items) |*f| {
            f.vars.deinit(self.allocator);
            f.ref_slots.deinit(self.allocator);
            if (f.locals.len > 0) self.freeLocals(f.locals);
        }
        fiber.saved_frames.clearRetainingCapacity();
    }

    fn writebackRefs(self: *VM) !void {
        _ = self;
    }

    fn scanCallerVarNames(self: *VM, ac: usize) [16]?[]const u8 {
        var arg_vars: [16]?[]const u8 = .{null} ** 16;
        const chunk = self.currentChunk();
        const ip = self.currentFrame().ip;
        if (ip < 4) return arg_vars;
        // scan backwards from just before the call instruction
        // each arg is a single value-producing instruction
        var scan_end = ip - 4; // points to call opcode
        var idx: usize = ac;
        while (idx > 0 and scan_end >= 3) {
            idx -= 1;
            const op = chunk.code.items[scan_end - 3];
            if (op == @intFromEnum(OpCode.get_var)) {
                const hi = chunk.code.items[scan_end - 2];
                const lo = chunk.code.items[scan_end - 1];
                const ci = (@as(u16, hi) << 8) | lo;
                if (ci < chunk.constants.items.len) {
                    arg_vars[idx] = chunk.constants.items[ci].string;
                }
                scan_end -= 3;
            } else if (op == @intFromEnum(OpCode.get_local)) {
                const hi = chunk.code.items[scan_end - 2];
                const lo = chunk.code.items[scan_end - 1];
                const slot = (@as(u16, hi) << 8) | lo;
                const sn = if (self.currentFrame().func) |func| func.slot_names else self.global_slot_names;
                if (slot < sn.len) {
                    arg_vars[idx] = sn[slot];
                }
                scan_end -= 3;
            } else if (op == @intFromEnum(OpCode.constant)) {
                scan_end -= 3;
            } else if (scan_end >= 1 and (chunk.code.items[scan_end - 1] == @intFromEnum(OpCode.op_null) or
                chunk.code.items[scan_end - 1] == @intFromEnum(OpCode.op_true) or
                chunk.code.items[scan_end - 1] == @intFromEnum(OpCode.op_false)))
            {
                scan_end -= 1;
            } else {
                break;
            }
        }
        return arg_vars;
    }

    fn writebackStatics(self: *VM) !void {
        var i: usize = 0;
        while (i < self.static_vars.items.len) {
            const entry = self.static_vars.items[i];
            if (entry.frame_depth == self.frame_count) {
                // save current value back to statics table
                const val = self.currentFrame().vars.get(entry.var_name) orelse .null;
                try self.setStaticVar(entry.var_name, val);
                _ = self.static_vars.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    fn getStaticVar(self: *VM, var_name: []const u8) Value {
        // key is the function name we're currently in + "::" + var name
        // find current function name from the chunk pointer
        const func_name = self.currentFuncName() orelse "__main__";
        var key_buf: [256]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "{s}::{s}", .{ func_name, var_name }) catch return .null;
        // need to look up with a runtime key - use the statics table
        return self.statics.get(key) orelse .null;
    }

    fn setStaticVar(self: *VM, var_name: []const u8, val: Value) !void {
        const func_name = self.currentFuncName() orelse "__main__";
        var key_buf: [256]u8 = undefined;
        const lookup = std.fmt.bufPrint(&key_buf, "{s}::{s}", .{ func_name, var_name }) catch return;
        if (self.statics.getEntry(lookup)) |entry| {
            entry.value_ptr.* = val;
        } else {
            const key = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ func_name, var_name });
            try self.statics.put(self.allocator, key, val);
        }
    }

    fn currentFuncName(self: *VM) ?[]const u8 {
        const chunk_ptr = self.currentChunk();
        var it = self.functions.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.*.chunk.code.items.ptr == chunk_ptr.code.items.ptr) {
                return entry.key_ptr.*;
            }
        }
        return null;
    }

    pub fn tryAutoload(self: *VM, class_name: []const u8) RuntimeError!void {
        for (self.autoload_callbacks.items) |callback| {
            if (callback == .string) {
                _ = self.callByName(callback.string, &.{.{ .string = class_name }}) catch continue;
            } else {
                var ctx = self.makeContext(null);
                _ = ctx.invokeCallable(callback, &.{.{ .string = class_name }}) catch continue;
            }
            if (self.classes.contains(class_name)) return;
        }
    }

    pub fn isInstanceOf(self: *VM, obj_class: []const u8, target_class: []const u8) bool {
        var current = obj_class;
        while (true) {
            if (std.mem.eql(u8, current, target_class)) return true;
            // check interfaces implemented by this class
            if (self.classes.get(current)) |cls| {
                for (cls.interfaces.items) |iface| {
                    if (self.implementsInterface(iface, target_class)) return true;
                }
                if (cls.parent) |p| {
                    current = p;
                    continue;
                }
            }
            return false;
        }
    }

    fn checkVisibility(self: *VM, target_class: []const u8, vis: ClassDef.Visibility) bool {
        if (vis == .public) return true;
        const caller_class = self.currentDefiningClass() orelse return false;
        if (vis == .private) return std.mem.eql(u8, caller_class, target_class);
        // protected: caller must be same class or in inheritance chain
        return self.isInstanceOf(caller_class, target_class) or self.isInstanceOf(target_class, caller_class);
    }

    const VisResult = struct { visibility: ClassDef.Visibility, defining_class: []const u8, is_readonly: bool = false };

    fn findPropertyVisibility(self: *VM, class_name: []const u8, prop_name: []const u8) VisResult {
        var current: ?[]const u8 = class_name;
        while (current) |cn| {
            if (self.classes.get(cn)) |cls| {
                for (cls.properties.items) |prop| {
                    if (std.mem.eql(u8, prop.name, prop_name)) return .{ .visibility = prop.visibility, .defining_class = cn, .is_readonly = prop.is_readonly };
                }
                current = cls.parent;
            } else break;
        }
        return .{ .visibility = .public, .defining_class = class_name };
    }

    fn findMethodVisibility(self: *VM, class_name: []const u8, method_name: []const u8) VisResult {
        var current: ?[]const u8 = class_name;
        while (current) |cn| {
            if (self.classes.get(cn)) |cls| {
                if (cls.methods.get(method_name)) |info| return .{ .visibility = info.visibility, .defining_class = cn };
                current = cls.parent;
            } else break;
        }
        return .{ .visibility = .public, .defining_class = class_name };
    }

    fn implementsInterface(self: *VM, iface_name: []const u8, target: []const u8) bool {
        var current: ?[]const u8 = iface_name;
        while (current) |name| {
            if (std.mem.eql(u8, name, target)) return true;
            if (self.interfaces.get(name)) |idef| {
                current = idef.parent;
            } else break;
        }
        return false;
    }

    fn currentDefiningClass(self: *VM) ?[]const u8 {
        // walk the call stack from current frame upward to find enclosing class method
        // closures inside methods need the enclosing method's class for visibility checks
        var fi: usize = self.frame_count;
        while (fi > 0) {
            fi -= 1;
            const frame = &self.frames[fi];
            const frame_chunk_ptr = frame.chunk;
            var best: ?[]const u8 = null;
            // when a trait method chunk is shared by multiple classes, use $this
            // to disambiguate which class is actually executing
            const this_class: ?[]const u8 = blk: {
                if (frame.func != null and frame.locals.len > 0 and frame.locals[0] == .object)
                    break :blk frame.locals[0].object.class_name;
                const this_val = frame.vars.get("$this") orelse break :blk null;
                if (this_val == .object) break :blk this_val.object.class_name;
                break :blk null;
            };
            var iter = self.functions.iterator();
            while (iter.next()) |entry| {
                if (frame_chunk_ptr == &entry.value_ptr.*.chunk) {
                    const name = entry.key_ptr.*;
                    if (std.mem.indexOf(u8, name, "::")) |sep| {
                        const class_part = name[0..sep];
                        if (self.traits.contains(class_part)) {
                            if (best == null) best = class_part;
                            continue;
                        }
                        // if we have $this, prefer the class that matches $this
                        // or is in $this's inheritance chain
                        if (this_class) |tc| {
                            if (std.mem.eql(u8, class_part, tc) or self.isInstanceOf(tc, class_part))
                                return class_part;
                            // non-trait but doesn't match $this - keep looking
                            if (best == null) best = class_part;
                        } else {
                            return class_part;
                        }
                    }
                }
            }
            if (best) |b| return b;
        }
        return null;
    }

    pub fn hasMethod(self: *VM, class_name: []const u8, method_name: []const u8) bool {
        var current = class_name;
        var buf: [256]u8 = undefined;
        while (true) {
            const full = std.fmt.bufPrint(&buf, "{s}::{s}", .{ current, method_name }) catch return false;
            if (self.functions.get(full) != null or self.native_fns.get(full) != null) return true;
            if (self.classes.get(current)) |cls| {
                if (cls.parent) |p| { current = p; continue; }
            }
            return false;
        }
    }

    fn resolveMethod(self: *VM, class_name: []const u8, method_name: []const u8) RuntimeError![]const u8 {
        // single-entry cache: skip string format + hashmap lookup on repeat calls
        if (self.method_cache_class.ptr == class_name.ptr and
            self.method_cache_class.len == class_name.len and
            self.method_cache_method.ptr == method_name.ptr and
            self.method_cache_method.len == method_name.len)
        {
            return self.method_cache_result;
        }
        const result = try self.resolveMethodSlow(class_name, method_name);
        self.method_cache_class = class_name;
        self.method_cache_method = method_name;
        self.method_cache_result = result;
        return result;
    }

    fn resolveMethodSlow(self: *VM, class_name: []const u8, method_name: []const u8) RuntimeError![]const u8 {
        var current = class_name;
        var buf: [256]u8 = undefined;
        while (true) {
            const full = std.fmt.bufPrint(&buf, "{s}::{s}", .{ current, method_name }) catch return error.RuntimeError;
            if (self.functions.getEntry(full)) |entry| return entry.key_ptr.*;
            if (self.native_fns.getEntry(full)) |entry| return entry.key_ptr.*;
            if (self.classes.get(current)) |cls| {
                if (cls.parent) |p| {
                    current = p;
                    continue;
                }
            }
            return error.RuntimeError;
        }
    }

    fn buildSlotLayout(self: *VM, def: *const ClassDef) RuntimeError!?*PhpObject.SlotLayout {
        // collect all properties walking parent chain (parent first)
        var all_names: [64][]const u8 = undefined;
        var all_defaults: [64]Value = undefined;
        var count: usize = 0;

        var walk_name = def.parent;
        while (walk_name) |pname| {
            const pcls = self.classes.get(pname) orelse break;
            // parent's slot layout already has the full parent chain flattened
            if (pcls.slot_layout) |pl| {
                for (0..pl.names.len) |i| {
                    all_names[count] = pl.names[i];
                    all_defaults[count] = pl.defaults[i];
                    count += 1;
                }
                break;
            }
            walk_name = pcls.parent;
        }

        for (def.properties.items) |prop| {
            // check if parent already defined this slot
            var found = false;
            for (all_names[0..count], 0..) |n, i| {
                if (std.mem.eql(u8, n, prop.name)) {
                    all_defaults[i] = prop.default;
                    found = true;
                    break;
                }
            }
            if (!found) {
                all_names[count] = prop.name;
                all_defaults[count] = prop.default;
                count += 1;
            }
        }

        if (count == 0) return null;

        const layout = self.allocator.create(PhpObject.SlotLayout) catch return error.RuntimeError;
        const names = self.allocator.alloc([]const u8, count) catch return error.RuntimeError;
        const defaults = self.allocator.alloc(Value, count) catch return error.RuntimeError;
        @memcpy(names, all_names[0..count]);
        @memcpy(defaults, all_defaults[0..count]);
        layout.* = .{ .names = names, .defaults = defaults };
        return layout;
    }

    pub fn initObjectProperties(self: *VM, obj: *PhpObject, class_name: []const u8) RuntimeError!void {
        if (self.classes.get(class_name)) |cls| {
            if (cls.slot_layout) |layout| {
                const slots = self.allocator.alloc(Value, layout.names.len) catch return error.RuntimeError;
                for (layout.defaults, 0..) |def_val, i| {
                    slots[i] = try self.copyValue(def_val);
                }
                obj.slots = slots;
                obj.slot_layout = layout;
                return;
            }
            // fallback for classes without slot layout
            if (cls.parent) |parent| {
                try self.initObjectProperties(obj, parent);
            }
            for (cls.properties.items) |prop| {
                try obj.set(self.allocator, prop.name, try self.copyValue(prop.default));
            }
        }
    }

    fn cloneArray(self: *VM, src: *PhpArray) RuntimeError!*PhpArray {
        const copy = self.allocator.create(PhpArray) catch return error.RuntimeError;
        copy.* = .{ .next_int_key = src.next_int_key, .cursor = src.cursor };
        copy.entries.ensureTotalCapacity(self.allocator, src.entries.items.len) catch return error.RuntimeError;
        for (src.entries.items) |entry| {
            copy.entries.appendAssumeCapacity(.{
                .key = entry.key,
                .value = if (entry.value == .array)
                    Value{ .array = try self.cloneArray(entry.value.array) }
                else
                    entry.value,
            });
        }
        self.arrays.append(self.allocator, copy) catch return error.RuntimeError;
        return copy;
    }

    fn copyValue(self: *VM, val: Value) RuntimeError!Value {
        if (val != .array) return val;
        return .{ .array = try self.cloneArray(val.array) };
    }

    pub fn makeContext(self: *VM, call_name: ?[]const u8) NativeContext {
        return .{ .allocator = self.allocator, .arrays = &self.arrays, .strings = &self.strings, .vm = self, .call_name = call_name };
    }

    pub fn bindClosures(self: *VM, vars: *std.StringHashMapUnmanaged(Value), ref_slots: ?*std.StringHashMapUnmanaged(*Value), name: []const u8) !void {
        if (self.getCaptureRange(name)) |cr| {
            const caps = self.captures.items[cr.start .. cr.start + cr.len];
            for (caps) |cap| {
                if (cap.ref_cell) |cell| {
                    if (ref_slots) |rs| try rs.put(self.allocator, cap.var_name, cell);
                } else {
                    try vars.put(self.allocator, cap.var_name, try self.copyValue(cap.value));
                }
            }
        }

        // arrow functions inherit parent scope
        if (self.frame_count > 0) {
            const orig_name = self.getOrigClosureName(name);
            if (self.functions.get(orig_name)) |func| {
                if (func.is_arrow) {
                    const parent = &self.frames[self.frame_count - 1];
                    var it = parent.vars.iterator();
                    while (it.next()) |entry| {
                        if (!vars.contains(entry.key_ptr.*)) {
                            try vars.put(self.allocator, entry.key_ptr.*, try self.copyValue(entry.value_ptr.*));
                        }
                    }
                }
            }
        }
    }

    fn getOrigClosureName(self: *VM, name: []const u8) []const u8 {
        _ = self;
        if (!std.mem.startsWith(u8, name, "__closure_")) return name;
        // runtime instance names have format __closure_N_M, compile name is __closure_N
        const after_prefix = name["__closure_".len..];
        if (std.mem.lastIndexOf(u8, after_prefix, "_")) |last_us| {
            return name[0 .. "__closure_".len + last_us];
        }
        return name;
    }

    fn bindArgs(self: *VM, vars: *std.StringHashMapUnmanaged(Value), func: *const ObjFunction, args: []const Value) !void {
        for (0..args.len) |i| {
            try vars.put(self.allocator, func.params[i], try self.copyValue(args[i]));
        }
        try self.fillDefaults(vars, func, args.len);
    }

    fn fillDefaults(self: *VM, vars: *std.StringHashMapUnmanaged(Value), func: *const ObjFunction, arg_count: usize) !void {
        for (arg_count..func.arity) |i| {
            if (i < func.defaults.len) {
                try vars.put(self.allocator, func.params[i], func.defaults[i]);
            } else {
                try vars.put(self.allocator, func.params[i], .null);
            }
        }
    }

    fn executeFunction(self: *VM, func: *const ObjFunction, vars: std.StringHashMapUnmanaged(Value)) RuntimeError!Value {
        const base_frame = self.frame_count;
        self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = vars, .locals = try self.allocLocals(func, &vars), .func = func };
        self.consumePendingArgCount();
        self.frame_count += 1;
        try self.runUntilFrame(base_frame);
        return self.pop();
    }

    pub fn executeFunctionWithRefs(self: *VM, func: *const ObjFunction, vars: std.StringHashMapUnmanaged(Value), ref_slots: std.StringHashMapUnmanaged(*Value)) RuntimeError!Value {
        const base_frame = self.frame_count;
        self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = vars, .locals = try self.allocLocals(func, &vars), .func = func, .ref_slots = ref_slots };
        self.consumePendingArgCount();
        self.frame_count += 1;
        try self.runUntilFrame(base_frame);
        return self.pop();
    }

    noinline fn valueTypeName(val: Value) []const u8 {
        return switch (val) {
            .int => "int",
            .float => "float",
            .bool => "bool",
            .string => "string",
            .array => "array",
            .object => |obj| obj.class_name,
            .null => "null",
            .generator => "Generator",
            .fiber => "Fiber",
        };
    }

    noinline fn checkSingleType(self: *VM, val: Value, type_name: []const u8) bool {
        if (std.mem.eql(u8, type_name, "mixed")) return true;
        if (std.mem.eql(u8, type_name, "void")) return val == .null;
        if (std.mem.eql(u8, type_name, "int") or std.mem.eql(u8, type_name, "integer")) return val == .int;
        if (std.mem.eql(u8, type_name, "float") or std.mem.eql(u8, type_name, "double")) return val == .float or val == .int;
        if (std.mem.eql(u8, type_name, "bool") or std.mem.eql(u8, type_name, "boolean")) return val == .bool;
        if (std.mem.eql(u8, type_name, "string")) return val == .string;
        if (std.mem.eql(u8, type_name, "array")) return val == .array;
        if (std.mem.eql(u8, type_name, "callable")) return val == .string or val == .array or val == .object;
        if (std.mem.eql(u8, type_name, "null")) return val == .null;
        if (std.mem.eql(u8, type_name, "false")) return val == .bool and !val.bool;
        if (std.mem.eql(u8, type_name, "true")) return val == .bool and val.bool;
        if (std.mem.eql(u8, type_name, "object")) return val == .object;
        if (std.mem.eql(u8, type_name, "iterable")) return val == .array or val == .generator;
        if (std.mem.eql(u8, type_name, "self") or std.mem.eql(u8, type_name, "static") or std.mem.eql(u8, type_name, "parent")) return val == .object;
        if (std.mem.eql(u8, type_name, "Generator")) return val == .generator;
        if (std.mem.eql(u8, type_name, "Fiber")) return val == .fiber;
        if (std.mem.eql(u8, type_name, "Closure")) return val == .string and if (val.string.len > 10) std.mem.startsWith(u8, val.string, "__closure_") else false;
        if (val == .object) return self.isInstanceOf(val.object.class_name, type_name);
        return false;
    }

    noinline fn checkTypeMatch(self: *VM, val: Value, type_str: []const u8) bool {
        if (type_str.len == 0) return true;
        if (type_str[0] == '?') {
            if (val == .null) return true;
            return self.checkSingleType(val, type_str[1..]);
        }
        if (std.mem.indexOf(u8, type_str, "|")) |_| {
            var it = std.mem.splitScalar(u8, type_str, '|');
            while (it.next()) |part| {
                if (self.checkSingleType(val, part)) return true;
            }
            return false;
        }
        return self.checkSingleType(val, type_str);
    }

    noinline fn checkParamTypes(self: *VM, name: []const u8, arg_count: u8) RuntimeError!bool {
        if (g_type_info.count() == 0) return false;
        const ti = g_type_info.get(name) orelse return false;
        if (ti.param_types.len == 0) return false;
        const func = self.functions.get(name);
        const ac: usize = arg_count;
        for (0..@min(ac, ti.param_types.len)) |i| {
            const type_str = ti.param_types[i];
            if (type_str.len == 0) continue;
            const val = self.stack[self.sp - ac + i];
            if (!self.checkTypeMatch(val, type_str)) {
                self.sp -= ac;
                const param_name = if (func) |f| (if (i < f.params.len) f.params[i] else "") else "";
                const msg = if (param_name.len > 0)
                    std.fmt.allocPrint(self.allocator, "{s}(): Argument #{d} ({s}) must be of type {s}, {s} given", .{ name, i + 1, param_name, type_str, valueTypeName(val) }) catch return error.RuntimeError
                else
                    std.fmt.allocPrint(self.allocator, "{s}(): Argument #{d} must be of type {s}, {s} given", .{ name, i + 1, type_str, valueTypeName(val) }) catch return error.RuntimeError;
                try self.strings.append(self.allocator, msg);
                self.error_msg = msg;
                if (try self.throwBuiltinException("TypeError", msg)) return true;
                return error.RuntimeError;
            }
        }
        return false;
    }

    noinline fn checkReturnType(self: *VM, val: Value) RuntimeError!bool {
        if (g_type_info.count() == 0) return false;
        const frame = &self.frames[self.frame_count - 1];
        const func_name = if (frame.func) |f| f.name else return false;
        const ti = g_type_info.get(func_name) orelse return false;
        if (ti.return_type.len == 0) return false;
        if (!self.checkTypeMatch(val, ti.return_type)) {
            const msg = std.fmt.allocPrint(self.allocator, "{s}(): Return value must be of type {s}, {s} returned", .{ func_name, ti.return_type, valueTypeName(val) }) catch return error.RuntimeError;
            try self.strings.append(self.allocator, msg);
            self.error_msg = msg;
            try self.popFrame();
            if (try self.throwBuiltinException("TypeError", msg)) return true;
            return error.RuntimeError;
        }
        return false;
    }

    fn callNamedFunction(self: *VM, name: []const u8, arg_count: u8) RuntimeError!void {
        if (self.native_fns.get(name)) |native| {
            var args: [16]Value = undefined;
            const ac: usize = arg_count;
            for (0..ac) |i| args[i] = self.stack[self.sp - ac + i];
            self.sp -= ac;
            var ctx = self.makeContext(name);
            self.push(try native(&ctx, args[0..ac]));
        } else if (self.functions.get(name)) |func| {
            const ac: usize = arg_count;
            if (ac < func.required_params) {
                self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Too few arguments to function {s}(), {d} passed, {d} required\n", .{ name, ac, func.required_params }) catch null;
                return error.RuntimeError;
            }
            if (g_type_info.count() > 0) {
                if (try self.checkParamTypes(name, arg_count)) return;
            }
            if (func.locals_only) {
                if (self.captures.items.len == 0 or !self.hasCaptures(name))
                    return self.callLocalsOnly(func, arg_count);
                if (std.mem.startsWith(u8, name, "__closure_"))
                    return self.callClosureLocalsOnly(func, name, arg_count);
            }
            var new_vars: std.StringHashMapUnmanaged(Value) = .{};
            var closure_refs: std.StringHashMapUnmanaged(*Value) = .{};
            try self.bindClosures(&new_vars, &closure_refs, name);
            if (func.is_variadic) {
                const fixed: usize = func.arity - 1;
                for (0..@min(ac, fixed)) |i| {
                    try new_vars.put(self.allocator, func.params[i], try self.copyValue(self.stack[self.sp - ac + i]));
                }
                const rest_arr = try self.allocator.create(PhpArray);
                rest_arr.* = .{};
                for (fixed..ac) |i| {
                    try rest_arr.append(self.allocator, self.stack[self.sp - ac + i]);
                }
                try self.arrays.append(self.allocator, rest_arr);
                try new_vars.put(self.allocator, func.params[fixed], .{ .array = rest_arr });
            } else {
                const bind_count = @min(ac, func.arity);
                for (0..bind_count) |i| {
                    try new_vars.put(self.allocator, func.params[i], try self.copyValue(self.stack[self.sp - ac + i]));
                }
            }
            self.sp -= ac;
            if (!func.is_variadic) {
                try self.fillDefaults(&new_vars, func, @min(ac, func.arity));
            }
            // set up shared ref cells for by-ref params
            // start with any closure ref captures
            var callee_refs = closure_refs;
            if (func.ref_params.len > 0) {
                const arg_vars = self.scanCallerVarNames(ac);
                for (0..@min(ac, func.ref_params.len)) |ri| {
                    if (func.ref_params[ri]) {
                        if (arg_vars[ri]) |caller_var| {
                            // check if caller already has a ref cell for this var
                            if (self.currentFrame().ref_slots.get(caller_var)) |existing_cell| {
                                existing_cell.* = new_vars.get(func.params[ri]) orelse .null;
                                try callee_refs.put(self.allocator, func.params[ri], existing_cell);
                            } else {
                                const cell = try self.allocator.create(Value);
                                cell.* = new_vars.get(func.params[ri]) orelse .null;
                                try self.ref_cells.append(self.allocator, cell);
                                try self.currentFrame().ref_slots.put(self.allocator, caller_var, cell);
                                try callee_refs.put(self.allocator, func.params[ri], cell);
                            }
                        }
                    }
                }
            }

            if (func.is_generator) {
                callee_refs.deinit(self.allocator);
                const gen = try self.allocator.create(Generator);
                gen.* = .{ .func = func, .vars = new_vars };
                try self.generators.append(self.allocator, gen);
                self.push(.{ .generator = gen });
            } else {
                const inherit_cc = if (std.mem.startsWith(u8, name, "__closure_")) self.currentFrame().called_class else null;
                self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars, .locals = try self.allocLocals(func, &new_vars), .func = func, .ref_slots = callee_refs, .called_class = inherit_cc };
                self.setFrameArgCount(arg_count);
                self.frame_count += 1;
            }
        } else {
            self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught Error: Call to undefined function {s}()\n", .{name}) catch null;
            return error.RuntimeError;
        }
    }

    pub fn callMethod(self: *VM, obj: *PhpObject, method_name: []const u8, args: []const Value) RuntimeError!Value {
        const full_name = self.resolveMethod(obj.class_name, method_name) catch return error.RuntimeError;
        if (self.native_fns.get(full_name)) |native| {
            var tmp_vars: std.StringHashMapUnmanaged(Value) = .{};
            try tmp_vars.put(self.allocator, "$this", .{ .object = obj });
            self.frames[self.frame_count] = .{ .chunk = self.currentChunk(), .ip = self.currentFrame().ip, .vars = tmp_vars };
            self.frame_count += 1;
            var ctx = self.makeContext(null);
            const result = try native(&ctx, args);
            self.frame_count -= 1;
            self.frames[self.frame_count].vars.deinit(self.allocator);
            return result;
        } else if (self.functions.get(full_name)) |func| {
            if (args.len < func.required_params) return error.RuntimeError;
            var new_vars: std.StringHashMapUnmanaged(Value) = .{};
            try new_vars.put(self.allocator, "$this", .{ .object = obj });
            try self.bindClosures(&new_vars, null, full_name);
            try self.bindArgs(&new_vars, func, args[0..@min(args.len, func.arity)]);
            return self.executeFunction(func, new_vars);
        } else return error.RuntimeError;
    }

    pub fn callByName(self: *VM, name: []const u8, args: []const Value) RuntimeError!Value {
        if (self.native_fns.get(name)) |native| {
            var ctx = self.makeContext(null);
            return native(&ctx, args);
        } else if (self.functions.get(name)) |func| {
            if (args.len < func.required_params) return error.RuntimeError;
            if (self.ic) |ic| ic.pending_arg_count = @intCast(@min(args.len, 255));
            if (func.locals_only) {
                if (self.captures.items.len == 0)
                    return self.executeFunctionLocalsOnly(func, args);
                if (std.mem.startsWith(u8, name, "__closure_")) {
                    if (!self.hasCaptures(name))
                        return self.executeFunctionLocalsOnly(func, args);
                    if (!self.closureHasRefCaptures(name))
                        return self.executeClosureLocalsOnly(func, name, args);
                } else {
                    if (!self.hasCaptures(name))
                        return self.executeFunctionLocalsOnly(func, args);
                }
            }
            var new_vars: std.StringHashMapUnmanaged(Value) = .{};
            var closure_refs: std.StringHashMapUnmanaged(*Value) = .{};
            try self.bindClosures(&new_vars, &closure_refs, name);
            try self.bindArgs(&new_vars, func, args[0..@min(args.len, func.arity)]);
            if (closure_refs.count() > 0) {
                return self.executeFunctionWithRefs(func, new_vars, closure_refs);
            }
            return self.executeFunction(func, new_vars);
        } else return error.RuntimeError;
    }

    fn closureHasRefCaptures(self: *VM, name: []const u8) bool {
        if (self.capture_index.get(name)) |range| return range.has_refs;
        return false;
    }

    fn hasCaptures(self: *VM, name: []const u8) bool {
        return self.capture_index.contains(name);
    }

    fn getCaptureRange(self: *VM, name: []const u8) ?CaptureRange {
        return self.capture_index.get(name);
    }

    fn executeClosureLocalsOnly(self: *VM, func: *const ObjFunction, name: []const u8, args: []const Value) RuntimeError!Value {
        const base_frame = self.frame_count;
        const lc: usize = func.local_count;
        const ic = self.ic.?;
        const lbase = ic.locals_sp;

        const locals = if (lbase + lc <= ic.locals_cap) blk: {
            const s = ic.locals_buf[lbase..lbase + lc];
            @memset(s, .null);
            ic.locals_sp = lbase + lc;
            break :blk s;
        } else blk: {
            const s = try self.allocator.alloc(Value, lc);
            @memset(s, .null);
            break :blk s;
        };

        const bind_count = @min(args.len, func.arity);
        for (0..bind_count) |i| {
            locals[i] = try self.copyValue(args[i]);
        }
        for (bind_count..func.arity) |i| {
            if (i < func.defaults.len) locals[i] = func.defaults[i];
        }
        // bind captures (no ref cells here - ref captures take the slow path)
        if (self.getCaptureRange(name)) |cr| {
            const caps = self.captures.items[cr.start .. cr.start + cr.len];
            for (caps) |cap| {
                for (func.slot_names, 0..) |sn, si| {
                    if (sn.len == cap.var_name.len and std.mem.eql(u8, sn, cap.var_name)) {
                        locals[si] = try self.copyValue(cap.value);
                        break;
                    }
                }
            }
        }
        self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = .{}, .locals = locals, .func = func, .called_class = self.currentFrame().called_class };
        self.consumePendingArgCount();
        self.frame_count += 1;
        try self.fastLoop();
        const fl_frame = &self.frames[self.frame_count - 1];
        if (fl_frame.chunk == &func.chunk) {
            try self.runUntilFrame(base_frame);
        }
        return self.pop();
    }

    pub fn callByNameRef(self: *VM, name: []const u8, args: []Value) RuntimeError!Value {
        if (self.functions.get(name)) |func| {
            if (func.ref_params.len == 0) {
                return self.callByName(name, args);
            }
            const bind_count = @min(args.len, func.arity);
            var new_vars: std.StringHashMapUnmanaged(Value) = .{};
            var ref_slots: std.StringHashMapUnmanaged(*Value) = .{};
            try self.bindClosures(&new_vars, &ref_slots, name);

            var cells: [16]?*Value = .{null} ** 16;
            for (0..bind_count) |i| {
                try new_vars.put(self.allocator, func.params[i], try self.copyValue(args[i]));
                if (i < func.ref_params.len and func.ref_params[i] and i < 16) {
                    const cell = try self.allocator.create(Value);
                    cell.* = args[i];
                    try self.ref_cells.append(self.allocator, cell);
                    try ref_slots.put(self.allocator, func.params[i], cell);
                    cells[i] = cell;
                }
            }
            try self.fillDefaults(&new_vars, func, bind_count);

            const result = try self.executeFunctionWithRefs(func, new_vars, ref_slots);

            for (0..bind_count) |i| {
                if (cells[i]) |cell| {
                    args[i] = cell.*;
                }
            }
            return result;
        }
        return self.callByName(name, args);
    }

    // ==================================================================
    // fibers
    // ==================================================================

    fn executeFiber(self: *VM, fiber: *Fiber, base_frame: usize, base_sp: usize, base_handler: usize) RuntimeError!Value {
        const prev_fiber = self.current_fiber;
        const prev_floor = self.handler_floor;
        self.current_fiber = fiber;
        self.handler_floor = base_handler;

        self.runUntilFrame(base_frame) catch |err| {
            self.current_fiber = prev_fiber;
            self.handler_floor = prev_floor;
            if (self.fiber_suspend_pending) {
                self.fiber_suspend_pending = false;
                try self.saveFiberState(fiber, base_frame, base_sp, base_handler);
                fiber.state = .suspended;
                const result = self.fiber_suspend_value;
                self.fiber_suspend_value = .null;
                return result;
            }
            fiber.state = .terminated;
            // clean up any frames left on the stack
            while (self.frame_count > base_frame) {
                self.frame_count -= 1;
                self.frames[self.frame_count].ref_slots.deinit(self.allocator);
                self.frames[self.frame_count].vars.deinit(self.allocator);
                if (self.frames[self.frame_count].locals.len > 0) {
                    self.freeLocals(self.frames[self.frame_count].locals);
                    self.frames[self.frame_count].locals = &.{};
                }
            }
            self.sp = base_sp;
            self.handler_count = base_handler;
            return err;
        };

        self.current_fiber = prev_fiber;
        self.handler_floor = prev_floor;
        fiber.state = .terminated;
        if (self.sp > base_sp) {
            fiber.return_value = self.pop();
        }
        self.sp = base_sp;
        return .null;
    }

    fn saveFiberState(self: *VM, fiber: *Fiber, base_frame: usize, base_sp: usize, base_handler: usize) !void {
        // clear previously saved state
        self.cleanupFiberFrames(fiber);
        fiber.saved_frames.clearRetainingCapacity();
        fiber.saved_stack.clearRetainingCapacity();
        fiber.saved_handlers.clearRetainingCapacity();

        // save frames (move ownership of vars/ref_bindings/locals to fiber)
        for (self.frames[base_frame..self.frame_count]) |frame| {
            try fiber.saved_frames.append(self.allocator, .{
                .chunk = frame.chunk,
                .ip = frame.ip,
                .vars = frame.vars,
                .locals = frame.locals,
                .generator = frame.generator,
                .ref_slots = frame.ref_slots,
            });
        }
        self.frame_count = base_frame;

        // save stack values
        for (self.stack[base_sp..self.sp]) |val| {
            try fiber.saved_stack.append(self.allocator, val);
        }
        self.sp = base_sp;

        // save exception handlers as relative offsets
        for (self.exception_handlers[base_handler..self.handler_count]) |h| {
            try fiber.saved_handlers.append(self.allocator, .{
                .catch_ip = h.catch_ip,
                .frame_count_offset = h.frame_count - base_frame,
                .sp_offset = h.sp - base_sp,
                .chunk = h.chunk,
            });
        }
        self.handler_count = base_handler;
    }

    fn restoreFiberState(self: *VM, fiber: *Fiber, base_frame: usize, base_sp: usize) void {
        // restore frames (move ownership back to VM)
        for (fiber.saved_frames.items, 0..) |frame, i| {
            self.frames[base_frame + i] = .{
                .chunk = frame.chunk,
                .ip = frame.ip,
                .vars = frame.vars,
                .locals = frame.locals,
                .generator = frame.generator,
                .ref_slots = frame.ref_slots,
            };
        }
        self.frame_count = base_frame + fiber.saved_frames.items.len;
        fiber.saved_frames.clearRetainingCapacity();

        // restore stack
        for (fiber.saved_stack.items) |val| {
            self.stack[self.sp] = val;
            self.sp += 1;
        }
        fiber.saved_stack.clearRetainingCapacity();

        // restore exception handlers with absolute values
        for (fiber.saved_handlers.items) |h| {
            self.exception_handlers[self.handler_count] = .{
                .catch_ip = h.catch_ip,
                .frame_count = base_frame + h.frame_count_offset,
                .sp = base_sp + h.sp_offset,
                .chunk = h.chunk,
            };
            self.handler_count += 1;
        }
        fiber.saved_handlers.clearRetainingCapacity();
    }

    // ==================================================================
    // helpers
    // ==================================================================

    fn readByte(self: *VM) u8 {
        const frame = &self.frames[self.frame_count - 1];
        const byte = frame.chunk.code.items[frame.ip];
        frame.ip += 1;
        return byte;
    }

    fn readU16(self: *VM) u16 {
        const hi: u16 = self.readByte();
        const lo: u16 = self.readByte();
        return (hi << 8) | lo;
    }

    fn currentChunk(self: *const VM) *const Chunk {
        return self.frames[self.frame_count - 1].chunk;
    }

    pub fn currentFrame(self: *VM) *CallFrame {
        return &self.frames[self.frame_count - 1];
    }

    fn setFrameArgCount(self: *VM, ac: u8) void {
        if (self.ic) |ic| ic.arg_counts[self.frame_count] = ac;
    }

    fn consumePendingArgCount(self: *VM) void {
        if (self.ic) |ic| {
            ic.arg_counts[self.frame_count] = ic.pending_arg_count;
            ic.pending_arg_count = 0xFF;
        }
    }

    pub fn getFrameArgCount(self: *VM) ?u8 {
        const ic = self.ic orelse return null;
        const ac = ic.arg_counts[self.frame_count - 1];
        if (ac == 0xFF) return null;
        return ac;
    }

    fn binaryOp(self: *VM, op: *const fn (Value, Value) Value) void {
        const b = self.pop();
        const a = self.pop();
        self.push(op(a, b));
    }

    fn push(self: *VM, value: Value) void {
        self.stack[self.sp] = value;
        self.sp += 1;
    }

    fn pop(self: *VM) Value {
        self.sp -= 1;
        return self.stack[self.sp];
    }

    fn peek(self: *const VM) Value {
        return self.stack[self.sp - 1];
    }

};

