const std = @import("std");
const Value = @import("value.zig").Value;
const PhpArray = @import("value.zig").PhpArray;
const PhpObject = @import("value.zig").PhpObject;
const Generator = @import("value.zig").Generator;
const Fiber = @import("value.zig").Fiber;
const ArrayRefBinding = @import("value.zig").ArrayRefBinding;
const ObjectRefBinding = @import("value.zig").ObjectRefBinding;
const bytecode = @import("../pipeline/bytecode.zig");
const Chunk = bytecode.Chunk;
const OpCode = bytecode.OpCode;
const ObjFunction = bytecode.ObjFunction;
const CompileResult = @import("../pipeline/compiler.zig").CompileResult;
const enums = @import("../stdlib/enums.zig");

const Allocator = std.mem.Allocator;
pub const RuntimeError = error{ RuntimeError, OutOfMemory };

extern fn zphp_fast_loop(vm_ptr: *anyopaque) callconv(.c) u8;

pub const TypeInfo = struct {
    param_types: []const []const u8 = &.{},
    return_type: []const u8 = "",
};
pub var g_type_info: std.StringHashMapUnmanaged(TypeInfo) = .{};
var g_type_info_allocator: ?Allocator = null;

pub fn getTypeInfo(key: []const u8) ?TypeInfo {
    return g_type_info.get(key);
}

pub const FileLoader = fn (path: []const u8, allocator: Allocator, vm: *VM) ?*CompileResult;

pub const OutputBufferLevel = struct {
    start: usize,
    callback: ?Value = null,
};

pub const ErrorHandlerEntry = struct { handler: Value, mask: i64 };

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
        self.vm.next_object_id += 1;
        obj.* = .{ .class_name = class_name, .id = self.vm.next_object_id };
        try self.vm.objects.append(self.allocator, obj);
        try self.vm.initObjectProperties(obj, class_name);
        return obj;
    }

    pub fn callFunction(self: *NativeContext, name: []const u8, args: []const Value) RuntimeError!Value {
        return self.vm.callByName(name, args);
    }

    pub fn callMethod(self: *NativeContext, obj: *PhpObject, method: []const u8, args: []const Value) RuntimeError!Value {
        return self.vm.callMethod(obj, method, args);
    }

    pub fn setCallerVar(self: *NativeContext, arg_index: usize, arg_count: usize, value: Value) void {
        const vm = self.vm;
        if (vm.frame_count == 0) return;
        const arg_sources = vm.scanCallerArgSources(arg_count);
        const caller = vm.currentFrame();

        switch (arg_sources[arg_index]) {
            .simple => |var_name| {
                caller.vars.put(vm.allocator, var_name, value) catch return;
                const sn = if (caller.func) |func| func.slot_names else vm.global_slot_names;
                for (sn, 0..) |sn_name, si| {
                    if (std.mem.eql(u8, sn_name, var_name)) {
                        if (si < caller.locals.len) caller.locals[si] = value;
                        break;
                    }
                }
                // if the caller's param itself is a reference (e.g. function
                // wrap(&$r) { parse_str(..., $r); }) propagate the write
                // through the ref binding so the outer scope's variable
                // updates too. without this, native by-ref writes stop at
                // the first wrapping function
                if (caller.ref_slots.get(var_name)) |cell| {
                    cell.* = value;
                    vm.propagateCellWrite(cell, value) catch {};
                }
            },
            .array_elem => |ae| {
                const arr_val = vm.resolveCallerVar(ae.var_name, ae.is_local, ae.slot);
                if (arr_val == .array) {
                    arr_val.array.set(vm.allocator, Value.toArrayKey(ae.key), value) catch return;
                }
            },
            .object_prop => |op| {
                const obj_val = vm.resolveCallerVar(op.var_name, op.is_local, op.slot);
                if (obj_val == .object) {
                    obj_val.object.set(vm.allocator, op.prop_name, value) catch return;
                }
            },
            .chained_prop => |cp| {
                const target = vm.resolveChainedProp(cp);
                if (target) |t| {
                    t.obj.set(vm.allocator, t.prop, value) catch return;
                }
            },
            .prop_array_elem => |pae| {
                const obj_val = vm.resolveCallerVar(pae.var_name, pae.is_local, pae.slot);
                if (obj_val == .object) {
                    const prop_val = obj_val.object.get(pae.prop_name);
                    if (prop_val == .array) {
                        prop_val.array.set(vm.allocator, Value.toArrayKey(pae.key), value) catch return;
                    }
                }
            },
            .none => {},
        }
    }

    pub fn invokeCallable(self: *NativeContext, callable: Value, args: []const Value) RuntimeError!Value {
        if (callable == .string) return self.vm.callByName(callable.string, args);
        if (callable == .object) {
            if (self.vm.hasMethod(callable.object.class_name, "__invoke")) {
                return self.vm.callMethod(callable.object, "__invoke", args);
            }
            return error.RuntimeError;
        }
        if (callable != .array) return error.RuntimeError;
        const arr = callable.array;
        if (arr.entries.items.len != 2) return error.RuntimeError;
        const target = arr.entries.items[0].value;
        const method_val = arr.entries.items[1].value;
        if (method_val != .string) return error.RuntimeError;
        const method = method_val.string;
        if (target == .object) return self.vm.callMethod(target.object, method, args);
        if (target == .string) {
            var buf: [512]u8 = undefined;
            const full = std.fmt.bufPrint(&buf, "{s}::{s}", .{ target.string, method }) catch return error.RuntimeError;
            return self.vm.callByName(full, args) catch |err| {
                if (err == error.RuntimeError and self.vm.autoload_callbacks.items.len > 0) {
                    try self.vm.tryAutoload(target.string);
                    const full2 = std.fmt.bufPrint(&buf, "{s}::{s}", .{ target.string, method }) catch return error.RuntimeError;
                    return self.vm.callByName(full2, args);
                }
                return err;
            };
        }
        return error.RuntimeError;
    }

    pub fn invokeCallableRef(self: *NativeContext, callable: Value, args: []Value) RuntimeError!Value {
        if (callable == .string) return self.vm.callByNameRef(callable.string, args);
        return self.invokeCallable(callable, args);
    }
};

const NativeFn = *const fn (*NativeContext, []const Value) RuntimeError!Value;

pub const CaptureEntry = struct {
    closure_name: []const u8,
    var_name: []const u8,
    value: Value,
    ref_cell: ?*Value = null,
};

const RefSource = union(enum) {
    none,
    simple: []const u8,
    array_elem: struct {
        var_name: []const u8,
        is_local: bool,
        slot: u16,
        key: Value,
    },
    object_prop: struct {
        var_name: []const u8,
        is_local: bool,
        slot: u16,
        prop_name: []const u8,
    },
    chained_prop: struct {
        var_name: []const u8,
        is_local: bool,
        slot: u16,
        // chains deeper than this length silently skip the writeback. real
        // code (linked lists, trees, AST walkers) easily exceeds 4 so the
        // bound is set high enough to cover practical cases without making
        // the RefSource union enormous
        props: [16]?[]const u8,
    },
    prop_array_elem: struct {
        var_name: []const u8,
        is_local: bool,
        slot: u16,
        prop_name: []const u8,
        key: Value,
    },
};

pub const CaptureRange = struct {
    start: u32,
    len: u16,
    has_refs: bool,
};

pub const AttributeDef = struct {
    name: []const u8,
    args: []const Value = &.{},
    arg_names: []const ?[]const u8 = &.{},
};

pub const ClassDef = struct {
    name: []const u8,
    methods: std.StringHashMapUnmanaged(MethodInfo) = .{},
    method_order: std.ArrayListUnmanaged([]const u8) = .{},
    properties: std.ArrayListUnmanaged(PropertyDef) = .{},
    static_props: std.StringHashMapUnmanaged(Value) = .{},
    static_prop_types: std.StringHashMapUnmanaged([]const u8) = .{},
    file_path: []const u8 = "",
    start_line: u32 = 0,
    end_line: u32 = 0,
    doc_comment: []const u8 = "",
    parent: ?[]const u8 = null,
    interfaces: std.ArrayListUnmanaged([]const u8) = .{},
    is_enum: bool = false,
    is_abstract: bool = false,
    is_final: bool = false,
    is_readonly: bool = false,
    backed_type: enum(u8) { none = 0, int_type = 1, string_type = 2 } = .none,
    case_order: std.ArrayListUnmanaged([]const u8) = .{},
    slot_layout: ?*PhpObject.SlotLayout = null,
    used_traits: std.ArrayListUnmanaged([]const u8) = .{},
    attributes: std.ArrayListUnmanaged(AttributeDef) = .{},
    method_attributes: std.StringHashMapUnmanaged([]const AttributeDef) = .{},
    property_attributes: std.StringHashMapUnmanaged([]const AttributeDef) = .{},
    param_attributes: std.StringHashMapUnmanaged([]const AttributeDef) = .{},
    constant_names: std.StringHashMapUnmanaged(void) = .{},
    constant_order: std.ArrayListUnmanaged([]const u8) = .{},
    const_visibility: std.StringHashMapUnmanaged(Visibility) = .{},
    const_final: std.StringHashMapUnmanaged(void) = .{},
    constant_attributes: std.StringHashMapUnmanaged([]const AttributeDef) = .{},

    pub const Visibility = enum(u8) { public = 0, protected = 1, private = 2 };

    pub const MethodInfo = struct {
        name: []const u8,
        arity: u8,
        is_static: bool = false,
        is_abstract: bool = false,
        is_final: bool = false,
        visibility: Visibility = .public,
    };

    pub fn addMethod(self: *ClassDef, allocator: Allocator, info: MethodInfo) !void {
        const existed = self.methods.contains(info.name);
        try self.methods.put(allocator, info.name, info);
        if (!existed) try self.method_order.append(allocator, info.name);
    }

    pub const PropertyDef = struct {
        name: []const u8,
        default: Value,
        has_default: bool = false,
        visibility: Visibility = .public,
        set_visibility: Visibility = .public,
        is_readonly: bool = false,
        is_promoted: bool = false,
        type_str: []const u8 = "",
        doc_comment: []const u8 = "",
    };

    fn freeAttributeDefs(allocator: Allocator, attrs: []const AttributeDef) void {
        for (attrs) |a| {
            if (a.args.len > 0) allocator.free(a.args);
            if (a.arg_names.len > 0) allocator.free(a.arg_names);
        }
        allocator.free(attrs);
    }

    fn deinit(self: *ClassDef, allocator: Allocator) void {
        self.methods.deinit(allocator);
        self.method_order.deinit(allocator);
        self.const_final.deinit(allocator);
        self.properties.deinit(allocator);
        self.static_props.deinit(allocator);
        self.static_prop_types.deinit(allocator);
        self.interfaces.deinit(allocator);
        self.used_traits.deinit(allocator);
        self.case_order.deinit(allocator);
        for (self.attributes.items) |a| {
            if (a.args.len > 0) allocator.free(a.args);
            if (a.arg_names.len > 0) allocator.free(a.arg_names);
        }
        self.attributes.deinit(allocator);
        var ma_iter = self.method_attributes.valueIterator();
        while (ma_iter.next()) |attrs| freeAttributeDefs(allocator, attrs.*);
        self.method_attributes.deinit(allocator);
        var pa_iter = self.property_attributes.valueIterator();
        while (pa_iter.next()) |attrs| freeAttributeDefs(allocator, attrs.*);
        self.property_attributes.deinit(allocator);
        var pra_it = self.param_attributes.iterator();
        while (pra_it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            freeAttributeDefs(allocator, entry.value_ptr.*);
        }
        self.param_attributes.deinit(allocator);
        self.constant_names.deinit(allocator);
        self.constant_order.deinit(allocator);
        self.const_visibility.deinit(allocator);
        var ca_iter = self.constant_attributes.valueIterator();
        while (ca_iter.next()) |attrs| freeAttributeDefs(allocator, attrs.*);
        self.constant_attributes.deinit(allocator);
        if (self.slot_layout) |layout| {
            allocator.free(layout.names);
            allocator.free(layout.defaults);
            allocator.destroy(layout);
        }
    }
};

const TraitStaticProp = struct { name: []const u8, value: Value };

pub const InterfaceDef = struct {
    name: []const u8,
    methods: std.ArrayListUnmanaged([]const u8) = .{},
    parent: ?[]const u8 = null,
    // PHP allows `interface C extends A, B` - all extended interfaces. the
    // single `parent` field is kept for code that walks one parent at a time;
    // new code should iterate `parents` so multi-extension is honored
    parents: std.ArrayListUnmanaged([]const u8) = .{},

    fn deinit(self: *InterfaceDef, allocator: Allocator) void {
        self.methods.deinit(allocator);
        self.parents.deinit(allocator);
    }
};

pub const VM = struct {
    frames: [2048]CallFrame = undefined,
    frame_count: usize = 0,
    frame_high_water: usize = 0,
    stack: [2048]Value = undefined,
    sp: usize = 0,
    functions: std.StringHashMapUnmanaged(*const ObjFunction) = .{},
    function_attributes: std.StringHashMapUnmanaged([]const AttributeDef) = .{},
    native_fns: std.StringHashMapUnmanaged(NativeFn) = .{},
    output: std.ArrayListUnmanaged(u8) = .{},
    strings: std.ArrayListUnmanaged([]const u8) = .{},
    arrays: std.ArrayListUnmanaged(*PhpArray) = .{},
    objects: std.ArrayListUnmanaged(*PhpObject) = .{},
    next_object_id: u32 = 0,
    // pointer to the $GLOBALS PhpArray for the current run, used so writes
    // to $GLOBALS[key] = val also propagate to the top frame's variable
    // table (matching PHP's superglobal semantics)
    globals_array: ?*PhpArray = null,
    rng_seeded: bool = false,
    rng_state: std.Random.DefaultPrng = std.Random.DefaultPrng.init(0),
    mt19937: @import("../stdlib/mt19937.zig").Mt19937 = .{},
    obj_id_base: usize = 0,
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
    user_constants: std.StringHashMapUnmanaged(void) = .{},
    ini_settings: std.StringHashMapUnmanaged([]const u8) = .{},
    ini_callbacks: std.StringHashMapUnmanaged(Value) = .{},
    shutdown_callbacks: std.ArrayListUnmanaged(Value) = .{},
    strtok_state: ?[]const u8 = null,
    strtok_pos: usize = 0,
    classes: std.StringHashMapUnmanaged(ClassDef) = .{},
    interfaces: std.StringHashMapUnmanaged(InterfaceDef) = .{},
    traits: std.StringHashMapUnmanaged(void) = .{},
    trait_uses: std.StringHashMapUnmanaged([]const []const u8) = .{},
    trait_props: std.StringHashMapUnmanaged([]const ClassDef.PropertyDef) = .{},
    trait_static_props: std.StringHashMapUnmanaged([]const TraitStaticProp) = .{},
    trait_constants: std.StringHashMapUnmanaged([]const TraitStaticProp) = .{},
    statics: std.StringHashMapUnmanaged(Value) = .{},
    statics_cells: std.StringHashMapUnmanaged(*Value) = .{},
    // shared heap cell per global variable name. allocated on first `global $x`
    // declaration so every function frame referencing the same global gets a
    // pointer to the same value. lets writes propagate live to recursive calls
    globals_cells: std.StringHashMapUnmanaged(*Value) = .{},
    pending_call_name: ?[]const u8 = null,
    // args slice for invocations driven from native code (callByName-style).
    // executeFunction consumes this to seed fga_buf so func_get_args inside
    // the called function sees the real args, not stale data from whatever
    // last used this frame slot
    pending_invoke_args: ?[]const Value = null,
    static_vars: std.ArrayListUnmanaged(StaticEntry) = .{},
    global_vars: std.ArrayListUnmanaged(StaticEntry) = .{},
    file_loader: ?*const FileLoader = null,
    loaded_files: std.StringHashMapUnmanaged(void) = .{},
    // protocols whose builtin stream wrapper has been disabled via stream_wrapper_unregister
    stream_wrappers_unregistered: std.StringHashMapUnmanaged(void) = .{},
    // protocol -> user class name registered via stream_wrapper_register
    stream_wrappers_user: std.StringHashMapUnmanaged([]const u8) = .{},
    compile_results: std.ArrayListUnmanaged(*CompileResult) = .{},
    error_msg: ?[]const u8 = null,
    exit_requested: bool = false,
    exit_code: u8 = 0,
    source: []const u8 = "",
    file_path: []const u8 = "",
    autoload_callbacks: std.ArrayListUnmanaged(Value) = .{},
    autoload_depth: u8 = 0,
    // when a required script does an early `return X` at top level, the
    // return op pops its frame before the require handler runs the merge.
    // require sets this to the about-to-be-popped frame depth before
    // runUntilFrame; popFrame skips deinit and leaves the slot intact so
    // the require handler can read the include frame's locals/vars
    require_merge_depth: usize = 0,
    magic_get_guard: std.ArrayListUnmanaged(struct { obj_ptr: usize, prop_name: []const u8 }) = .{},
    magic_call_guard: std.ArrayListUnmanaged(struct { obj_ptr: usize, method_name: []const u8 }) = .{},
    prop_hook_guard: std.ArrayListUnmanaged(struct { obj_ptr: usize, prop_name: []const u8 }) = .{},
    user_error_handler: ?Value = null,
    user_error_handler_mask: i64 = -1,
    user_exception_handler: ?Value = null,
    error_handler_stack: std.ArrayListUnmanaged(ErrorHandlerEntry) = .{},
    error_silenced_depth: u32 = 0,
    last_error_type: i64 = 0,
    last_error_message: []const u8 = "",
    last_error_file: []const u8 = "",
    last_error_line: i64 = 0,
    prev_error_handler: ?Value = null,
    error_reporting_level: i64 = 30719,
    ob_stack: std.ArrayListUnmanaged(OutputBufferLevel) = .{},
    request_vars: std.StringHashMapUnmanaged(Value) = .{},
    // maps a phar alias (e.g. "phpunit-11.5.55.phar") to the on-disk archive
    // path. populated by Phar::mapPhar()/Phar::loadPhar() and read by the
    // phar:// stream wrapper to resolve `phar://alias/internal/path`
    phar_aliases: std.StringHashMapUnmanaged([]const u8) = .{},
    exception_handlers: [1024]ExceptionHandler = undefined,
    handler_count: usize = 0,
    handler_floor: usize = 0,
    pending_exception: ?Value = null,
    // when true, the current pending_exception is a fatal that cannot be caught
    // by user try/catch. used for execution-deadline timeouts; PHP's
    // `Maximum execution time exceeded` is an uncatchable fatal there too
    uncatchable_fatal: bool = false,
    exception_dispatched: bool = false,
    run_base_frame: usize = 0,
    allocator: Allocator,
    global_slot_names: []const []const u8 = &.{},
    script_strict_types: bool = false,
    // most recent ICU UErrorCode from any intl native call. reset to 0 on entry
    // to each intl call (except intl_get_error_*/intl_is_failure/intl_error_name)
    // and bumped to the failing status when an op fails
    last_intl_error_code: i32 = 0,
    // the slot_names of the top script frame (frame[0]). global_slot_names
    // is temporarily overridden during require/include to point at the inner
    // file's slot_names; writebacks to frame[0]'s locals must use the top
    // script's layout, not the most-recently-required file's
    top_slot_names: []const []const u8 = &.{},
    global_vars_dirty: bool = false,
    method_cache_class: []const u8 = "",
    method_cache_method: []const u8 = "",
    method_cache_result: []const u8 = "",
    ic: ?*InlineCache = null,
    serve_mode: bool = false,
    // deadline enforcement for set_time_limit / max_execution_time. 0 means
    // unlimited (PHP CLI default). non-zero is a monotonic-clock nanosecond
    // wall (after which any backwards jump or function entry throws a fatal
    // Error). polling is gated by deadline_tick_counter to keep overhead low
    execution_deadline_ns: i64 = 0,
    execution_limit_seconds: i64 = 0,
    deadline_tick_counter: u32 = 0,
    serve_compile_cache: std.StringHashMapUnmanaged(*CompileResult) = .{},
    serve_cache_keys: std.ArrayListUnmanaged([]const u8) = .{},
    response_code: i64 = 200,
    response_content_type: []const u8 = "text/html",
    response_headers: ?*PhpArray = null,
    headers_sent: bool = false,
    default_tz_name: []const u8 = "UTC",
    default_tz_offset: i32 = 0,

    pub const InlineCache = struct {
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
        sp_save: [2048]usize = undefined,
        // per-frame actual arg count for func_get_args
        arg_counts: [2048]u8 = [_]u8{0xFF} ** 2048,
        // per-frame saved arg values for func_get_args (flat buffer indexed by frame)
        fga_buf: [2048]Value = @splat(.null),
        fga_offsets: [2048]u16 = @splat(0),
        fga_sp: u16 = 0,
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
            chunk_key: usize = 0,
            class_ptr: usize = 0,
            func: ?*const ObjFunction = null,
            native: ?NativeFn = null,
            full_name: []const u8 = "",
        };

        pub fn propIndex(chunk_ptr: usize, ip: usize) u7 {
            return @truncate((chunk_ptr ^ ip) *% 0x517CC1B727220A95);
        }

        pub fn methodIndex(chunk_ptr: usize, ip: usize) u7 {
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
        ref_array_bindings: std.ArrayListUnmanaged(ArrayRefBinding) = .{},
        ref_object_bindings: std.ArrayListUnmanaged(ObjectRefBinding) = .{},
        called_class: ?[]const u8 = null,
        // name the function was looked up by - distinguishes closure instances
        // (which all share the same ObjFunction) for per-instance static state.
        call_name: ?[]const u8 = null,
        entry_sp: usize = 0,
        // the script file currently executing in this frame. used by class/
        // function declarations inside required files so ReflectionClass::
        // getFileName reports the *declaring* file rather than vm.file_path
        // (which only tracks the top-level script)
        script_path: []const u8 = "",
    };

    pub fn init(allocator: Allocator) RuntimeError!VM {
        return initInPlace(allocator);
    }

    pub fn initInPlace(allocator: Allocator) RuntimeError!VM {
        var vm = VM{ .allocator = allocator };
        try initVm(&vm, allocator);
        return vm;
    }

    pub fn initOnHeap(allocator: Allocator) RuntimeError!*VM {
        const vm = try allocator.create(VM);
        @memset(std.mem.asBytes(vm), 0);
        vm.allocator = allocator;
        try initVm(vm, allocator);
        return vm;
    }

    fn initVm(vm: *VM, allocator: Allocator) RuntimeError!void {
        vm.default_tz_name = "UTC";
        try @import("../stdlib/registry.zig").register(&vm.native_fns, allocator);
        try initConstants(&vm.php_constants, allocator);
        try registerStdlibClasses(vm, allocator);
        vm.error_reporting_level = 30719;
        vm.ic = try allocator.create(InlineCache);
        vm.ic.?.* = .{};
        const locals_buf = try allocator.alloc(Value, 8192);
        vm.ic.?.locals_buf = locals_buf.ptr;
        vm.ic.?.locals_cap = 8192;
    }

    // stdlib class/interface/trait registration. callable both at VM init time
    // and after a serve-mode reset (which clears the class table to drop the
    // user's request-scoped class definitions). idempotent for each stdlib
    // module since the maps overwrite on duplicate keys
    fn registerStdlibClasses(vm: *VM, allocator: Allocator) RuntimeError!void {
        try @import("../stdlib/exceptions.zig").register(vm, allocator);
        try @import("../stdlib/datetime.zig").register(vm, allocator);
        try @import("../stdlib/spl.zig").register(vm, allocator);
        try @import("../stdlib/spl_iterators.zig").register(vm, allocator);
        try @import("../stdlib/spl_file.zig").register(vm, allocator);
        try @import("../stdlib/pdo.zig").register(vm, allocator);
        try @import("../stdlib/websocket.zig").register(vm, allocator);
        try @import("../stdlib/filesystem.zig").register(vm, allocator);
        try @import("../stdlib/reflection.zig").register(vm, allocator);
        try @import("../stdlib/curl.zig").register(vm, allocator);
        try @import("../stdlib/phar_class.zig").register(vm, allocator);
        try @import("../stdlib/random.zig").register(vm, allocator);
        try @import("../stdlib/dom.zig").register(vm, allocator);
        try @import("../stdlib/simplexml.zig").register(vm, allocator);
        try @import("../stdlib/xmlreader.zig").register(vm, allocator);
        try @import("../stdlib/xmlwriter.zig").register(vm, allocator);
        try @import("../stdlib/xml_parser.zig").register(vm, allocator);
        try @import("../stdlib/intl.zig").register(vm, allocator);
        try @import("../stdlib/gmp.zig").register(vm, allocator);
        try @import("../stdlib/gd.zig").register(vm, allocator);
        try @import("../stdlib/soap.zig").register(vm, allocator);
        try @import("../stdlib/mysqli.zig").register(vm, allocator);

        // HashContext is the type returned by hash_init - register so
        // class_exists('HashContext') and instanceof checks see it
        const hash_ctx_def = ClassDef{ .name = "HashContext" };
        try vm.classes.put(allocator, "HashContext", hash_ctx_def);

        // tidy and tidyNode - stub classes for the deprecated tidy ext. zphp
        // doesn't link libtidy but class_exists checks still need to pass
        const tidy_def = ClassDef{ .name = "tidy" };
        try vm.classes.put(allocator, "tidy", tidy_def);
        const tidynode_def = ClassDef{ .name = "tidyNode" };
        try vm.classes.put(allocator, "tidyNode", tidynode_def);

        // PHP 8.4 RoundingMode enum. registered as a unit (unbacked) enum to
        // match PHP's exposed surface - the cases have a `name` property only,
        // and the internal mapping from case -> mode int happens inside round()
        var rm_def = ClassDef{ .name = "RoundingMode", .is_enum = true };
        const rm_cases = [_][]const u8{
            "HalfAwayFromZero",
            "HalfTowardsZero",
            "HalfEven",
            "HalfOdd",
            "TowardsZero",
            "AwayFromZero",
            "NegativeInfinity",
            "PositiveInfinity",
        };
        for (rm_cases) |name| {
            const case_obj = try allocator.create(PhpObject);
            case_obj.* = .{ .class_name = "RoundingMode" };
            try vm.objects.append(allocator, case_obj);
            try case_obj.set(allocator, "name", .{ .string = name });
            try rm_def.static_props.put(allocator, name, .{ .object = case_obj });
            try rm_def.constant_names.put(allocator, name, {});
            try rm_def.constant_order.append(allocator, name);
            try rm_def.case_order.append(allocator, name);
        }
        try rm_def.interfaces.append(allocator, "UnitEnum");
        try vm.classes.put(allocator, "RoundingMode", rm_def);
        try vm.registerEnumMethods("RoundingMode", 0);
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
        try c.put(a, "PHP_RELEASE_VERSION", .{ .int = 0 });
        try c.put(a, "PHP_SESSION_DISABLED", .{ .int = 0 });
        try c.put(a, "PHP_SESSION_NONE", .{ .int = 1 });
        try c.put(a, "PHP_SESSION_ACTIVE", .{ .int = 2 });
        try c.put(a, "PHP_VERSION", .{ .string = "8.4.0" });
        try c.put(a, "PHP_VERSION_ID", .{ .int = 80400 });
        try c.put(a, "PHP_SAPI", .{ .string = "cli" });
        try c.put(a, "PHP_OS", .{ .string = if (@import("builtin").os.tag == .macos) "Darwin" else "Linux" });
        try c.put(a, "DIRECTORY_SEPARATOR", .{ .string = "/" });
        try c.put(a, "PATH_SEPARATOR", .{ .string = ":" });
        // syslog priority + facility constants (zphp lacks a real syslog
        // backend, but vendor code references these constants at config time)
        try c.put(a, "LOG_EMERG", .{ .int = 0 });
        try c.put(a, "LOG_ALERT", .{ .int = 1 });
        try c.put(a, "LOG_CRIT", .{ .int = 2 });
        try c.put(a, "LOG_ERR", .{ .int = 3 });
        try c.put(a, "LOG_WARNING", .{ .int = 4 });
        try c.put(a, "LOG_NOTICE", .{ .int = 5 });
        try c.put(a, "LOG_INFO", .{ .int = 6 });
        try c.put(a, "LOG_DEBUG", .{ .int = 7 });
        try c.put(a, "LOG_KERN", .{ .int = 0 });
        try c.put(a, "LOG_USER", .{ .int = 8 });
        try c.put(a, "LOG_MAIL", .{ .int = 16 });
        try c.put(a, "LOG_DAEMON", .{ .int = 24 });
        try c.put(a, "LOG_AUTH", .{ .int = 32 });
        try c.put(a, "LOG_SYSLOG", .{ .int = 40 });
        try c.put(a, "LOG_LPR", .{ .int = 48 });
        try c.put(a, "LOG_NEWS", .{ .int = 56 });
        try c.put(a, "LOG_UUCP", .{ .int = 64 });
        try c.put(a, "LOG_CRON", .{ .int = 72 });
        try c.put(a, "LOG_AUTHPRIV", .{ .int = 80 });
        try c.put(a, "LOG_LOCAL0", .{ .int = 128 });
        try c.put(a, "LOG_LOCAL1", .{ .int = 136 });
        try c.put(a, "LOG_LOCAL2", .{ .int = 144 });
        try c.put(a, "LOG_LOCAL3", .{ .int = 152 });
        try c.put(a, "LOG_LOCAL4", .{ .int = 160 });
        try c.put(a, "LOG_LOCAL5", .{ .int = 168 });
        try c.put(a, "LOG_LOCAL6", .{ .int = 176 });
        try c.put(a, "LOG_LOCAL7", .{ .int = 184 });
        try c.put(a, "LOG_PID", .{ .int = 1 });
        try c.put(a, "LOG_CONS", .{ .int = 2 });
        try c.put(a, "LOG_ODELAY", .{ .int = 4 });
        try c.put(a, "LOG_NDELAY", .{ .int = 8 });
        try c.put(a, "LOG_NOWAIT", .{ .int = 16 });
        try c.put(a, "LOG_PERROR", .{ .int = 32 });
        try c.put(a, "ENT_HTML_QUOTE_NONE", .{ .int = 0 });
        try c.put(a, "ENT_HTML_QUOTE_SINGLE", .{ .int = 1 });
        try c.put(a, "ENT_HTML_QUOTE_DOUBLE", .{ .int = 2 });
        try c.put(a, "ENT_COMPAT", .{ .int = 2 });
        try c.put(a, "ENT_QUOTES", .{ .int = 3 });
        try c.put(a, "ENT_NOQUOTES", .{ .int = 0 });
        try c.put(a, "ENT_IGNORE", .{ .int = 4 });
        try c.put(a, "ENT_SUBSTITUTE", .{ .int = 8 });
        try c.put(a, "ENT_HTML401", .{ .int = 0 });
        try c.put(a, "ENT_XML1", .{ .int = 16 });
        try c.put(a, "ENT_XHTML", .{ .int = 32 });
        try c.put(a, "ENT_HTML5", .{ .int = 48 });
        try c.put(a, "HTML_SPECIALCHARS", .{ .int = 0 });
        try c.put(a, "HTML_ENTITIES", .{ .int = 1 });
        try c.put(a, "ENT_DISALLOWED", .{ .int = 128 });
        try c.put(a, "PHP_QUERY_RFC1738", .{ .int = 1 });
        try c.put(a, "PHP_QUERY_RFC3986", .{ .int = 2 });
        try c.put(a, "STR_PAD_RIGHT", .{ .int = 1 });
        try c.put(a, "STR_PAD_LEFT", .{ .int = 0 });
        try c.put(a, "STR_PAD_BOTH", .{ .int = 2 });
        try c.put(a, "EXTR_OVERWRITE", .{ .int = 0 });
        try c.put(a, "EXTR_SKIP", .{ .int = 1 });
        try c.put(a, "EXTR_PREFIX_SAME", .{ .int = 2 });
        try c.put(a, "EXTR_PREFIX_ALL", .{ .int = 3 });
        try c.put(a, "EXTR_PREFIX_INVALID", .{ .int = 4 });
        try c.put(a, "EXTR_IF_EXISTS", .{ .int = 5 });
        try c.put(a, "EXTR_PREFIX_IF_EXISTS", .{ .int = 6 });
        try c.put(a, "EXTR_REFS", .{ .int = 256 });
        try c.put(a, "ASSERT_ACTIVE", .{ .int = 1 });
        try c.put(a, "ASSERT_CALLBACK", .{ .int = 2 });
        try c.put(a, "ASSERT_BAIL", .{ .int = 3 });
        try c.put(a, "ASSERT_WARNING", .{ .int = 4 });
        try c.put(a, "ASSERT_QUIET_EVAL", .{ .int = 5 });
        try c.put(a, "ASSERT_EXCEPTION", .{ .int = 6 });
        try c.put(a, "SORT_REGULAR", .{ .int = 0 });
        try c.put(a, "SORT_NUMERIC", .{ .int = 1 });
        try c.put(a, "SORT_STRING", .{ .int = 2 });
        try c.put(a, "SORT_LOCALE_STRING", .{ .int = 5 });
        try c.put(a, "SORT_NATURAL", .{ .int = 6 });
        try c.put(a, "SORT_FLAG_CASE", .{ .int = 8 });
        try c.put(a, "SORT_ASC", .{ .int = 4 });
        try c.put(a, "SORT_DESC", .{ .int = 3 });
        try c.put(a, "DNS_A", .{ .int = 1 });
        try c.put(a, "DNS_CNAME", .{ .int = 16 });
        try c.put(a, "DNS_HINFO", .{ .int = 4096 });
        try c.put(a, "DNS_CAA", .{ .int = 8192 });
        try c.put(a, "DNS_MX", .{ .int = 16384 });
        try c.put(a, "DNS_NS", .{ .int = 2 });
        try c.put(a, "DNS_PTR", .{ .int = 2048 });
        try c.put(a, "DNS_SOA", .{ .int = 32 });
        try c.put(a, "DNS_TXT", .{ .int = 32768 });
        try c.put(a, "DNS_AAAA", .{ .int = 134217728 });
        try c.put(a, "DNS_SRV", .{ .int = 33554432 });
        try c.put(a, "DNS_NAPTR", .{ .int = 67108864 });
        try c.put(a, "DNS_A6", .{ .int = 16777216 });
        try c.put(a, "DNS_ALL", .{ .int = 251713587 });
        try c.put(a, "DNS_ANY", .{ .int = 268435456 });
        try c.put(a, "ZLIB_ENCODING_RAW", .{ .int = -15 });
        try c.put(a, "ZLIB_ENCODING_GZIP", .{ .int = 31 });
        try c.put(a, "ZLIB_ENCODING_DEFLATE", .{ .int = 15 });
        try c.put(a, "GLOB_MARK", .{ .int = 8 });
        try c.put(a, "GLOB_NOSORT", .{ .int = 32 });
        try c.put(a, "GLOB_NOCHECK", .{ .int = 16 });
        try c.put(a, "GLOB_NOESCAPE", .{ .int = 4096 });
        try c.put(a, "GLOB_BRACE", .{ .int = 128 });
        try c.put(a, "GLOB_ONLYDIR", .{ .int = 1073741824 });
        try c.put(a, "GLOB_ERR", .{ .int = 4 });
        try c.put(a, "GLOB_AVAILABLE_FLAGS", .{ .int = 8 | 32 | 16 | 4096 | 128 | 1073741824 | 4 });
        const posix = std.posix;
        try c.put(a, "SIGHUP", .{ .int = @intCast(posix.SIG.HUP) });
        try c.put(a, "SIGINT", .{ .int = @intCast(posix.SIG.INT) });
        try c.put(a, "SIGQUIT", .{ .int = @intCast(posix.SIG.QUIT) });
        try c.put(a, "SIGILL", .{ .int = @intCast(posix.SIG.ILL) });
        try c.put(a, "SIGTRAP", .{ .int = @intCast(posix.SIG.TRAP) });
        try c.put(a, "SIGABRT", .{ .int = @intCast(posix.SIG.ABRT) });
        try c.put(a, "SIGIOT", .{ .int = @intCast(posix.SIG.ABRT) });
        try c.put(a, "SIGBUS", .{ .int = @intCast(posix.SIG.BUS) });
        try c.put(a, "SIGFPE", .{ .int = @intCast(posix.SIG.FPE) });
        try c.put(a, "SIGKILL", .{ .int = @intCast(posix.SIG.KILL) });
        try c.put(a, "SIGUSR1", .{ .int = @intCast(posix.SIG.USR1) });
        try c.put(a, "SIGSEGV", .{ .int = @intCast(posix.SIG.SEGV) });
        try c.put(a, "SIGUSR2", .{ .int = @intCast(posix.SIG.USR2) });
        try c.put(a, "SIGPIPE", .{ .int = @intCast(posix.SIG.PIPE) });
        try c.put(a, "SIGALRM", .{ .int = @intCast(posix.SIG.ALRM) });
        try c.put(a, "SIGTERM", .{ .int = @intCast(posix.SIG.TERM) });
        try c.put(a, "SIGCHLD", .{ .int = @intCast(posix.SIG.CHLD) });
        try c.put(a, "SIGCLD", .{ .int = @intCast(posix.SIG.CHLD) });
        try c.put(a, "SIGCONT", .{ .int = @intCast(posix.SIG.CONT) });
        try c.put(a, "SIGSTOP", .{ .int = @intCast(posix.SIG.STOP) });
        try c.put(a, "SIGTSTP", .{ .int = @intCast(posix.SIG.TSTP) });
        try c.put(a, "SIGTTIN", .{ .int = @intCast(posix.SIG.TTIN) });
        try c.put(a, "SIGTTOU", .{ .int = @intCast(posix.SIG.TTOU) });
        try c.put(a, "SIGURG", .{ .int = @intCast(posix.SIG.URG) });
        try c.put(a, "SIGXCPU", .{ .int = @intCast(posix.SIG.XCPU) });
        try c.put(a, "SIGXFSZ", .{ .int = @intCast(posix.SIG.XFSZ) });
        try c.put(a, "SIGVTALRM", .{ .int = @intCast(posix.SIG.VTALRM) });
        try c.put(a, "SIGPROF", .{ .int = @intCast(posix.SIG.PROF) });
        try c.put(a, "SIGWINCH", .{ .int = @intCast(posix.SIG.WINCH) });
        try c.put(a, "SIGIO", .{ .int = @intCast(posix.SIG.IO) });
        try c.put(a, "SIGSYS", .{ .int = @intCast(posix.SIG.SYS) });
        try c.put(a, "SIG_DFL", .{ .int = 0 });
        try c.put(a, "SIG_IGN", .{ .int = 1 });
        try c.put(a, "SIG_ERR", .{ .int = -1 });
        try c.put(a, "WNOHANG", .{ .int = 1 });
        try c.put(a, "WUNTRACED", .{ .int = 2 });
        try c.put(a, "SIG_BLOCK", .{ .int = 0 });
        try c.put(a, "SIG_UNBLOCK", .{ .int = 1 });
        try c.put(a, "SIG_SETMASK", .{ .int = 2 });
        try c.put(a, "FTP_ASCII", .{ .int = 1 });
        try c.put(a, "FTP_TEXT", .{ .int = 1 });
        try c.put(a, "FTP_BINARY", .{ .int = 2 });
        try c.put(a, "FTP_IMAGE", .{ .int = 2 });
        try c.put(a, "FTP_AUTORESUME", .{ .int = -1 });
        try c.put(a, "FTP_TIMEOUT_SEC", .{ .int = 0 });
        try c.put(a, "FTP_AUTOSEEK", .{ .int = 1 });
        try c.put(a, "FTP_USEPASVADDRESS", .{ .int = 2 });
        try c.put(a, "FTP_FAILED", .{ .int = 0 });
        try c.put(a, "MYSQLI_REPORT_OFF", .{ .int = 0 });
        try c.put(a, "MYSQLI_REPORT_ERROR", .{ .int = 1 });
        try c.put(a, "MYSQLI_REPORT_STRICT", .{ .int = 2 });
        try c.put(a, "MYSQLI_REPORT_INDEX", .{ .int = 4 });
        try c.put(a, "MYSQLI_REPORT_DATA_TRUNCATION", .{ .int = 8 });
        try c.put(a, "MYSQLI_REPORT_ALL", .{ .int = 255 });
        try c.put(a, "MYSQLI_ASSOC", .{ .int = 1 });
        try c.put(a, "MYSQLI_NUM", .{ .int = 2 });
        try c.put(a, "MYSQLI_BOTH", .{ .int = 3 });
        try c.put(a, "MYSQLI_STORE_RESULT", .{ .int = 0 });
        try c.put(a, "MYSQLI_USE_RESULT", .{ .int = 1 });
        try c.put(a, "MYSQLI_CLIENT_FOUND_ROWS", .{ .int = 2 });
        try c.put(a, "MYSQLI_CLIENT_COMPRESS", .{ .int = 32 });
        try c.put(a, "MYSQLI_CLIENT_SSL", .{ .int = 2048 });
        try c.put(a, "MYSQLI_OPT_CONNECT_TIMEOUT", .{ .int = 0 });
        try c.put(a, "FTP_FINISHED", .{ .int = 1 });
        try c.put(a, "FTP_MOREDATA", .{ .int = 2 });
        try c.put(a, "SODIUM_LIBRARY_MAJOR_VERSION", .{ .int = 26 });
        try c.put(a, "SODIUM_LIBRARY_MINOR_VERSION", .{ .int = 1 });
        try c.put(a, "SODIUM_CRYPTO_SECRETBOX_KEYBYTES", .{ .int = 32 });
        try c.put(a, "SODIUM_CRYPTO_SECRETBOX_NONCEBYTES", .{ .int = 24 });
        try c.put(a, "SODIUM_CRYPTO_SECRETBOX_MACBYTES", .{ .int = 16 });
        try c.put(a, "SODIUM_CRYPTO_BOX_KEYPAIRBYTES", .{ .int = 64 });
        try c.put(a, "SODIUM_CRYPTO_BOX_PUBLICKEYBYTES", .{ .int = 32 });
        try c.put(a, "SODIUM_CRYPTO_BOX_SECRETKEYBYTES", .{ .int = 32 });
        try c.put(a, "SODIUM_CRYPTO_BOX_NONCEBYTES", .{ .int = 24 });
        try c.put(a, "SODIUM_CRYPTO_BOX_MACBYTES", .{ .int = 16 });
        try c.put(a, "SODIUM_CRYPTO_BOX_SEEDBYTES", .{ .int = 32 });
        try c.put(a, "SODIUM_CRYPTO_BOX_SEALBYTES", .{ .int = 48 });
        try c.put(a, "SODIUM_CRYPTO_SIGN_KEYPAIRBYTES", .{ .int = 96 });
        try c.put(a, "SODIUM_CRYPTO_SIGN_PUBLICKEYBYTES", .{ .int = 32 });
        try c.put(a, "SODIUM_CRYPTO_SIGN_SECRETKEYBYTES", .{ .int = 64 });
        try c.put(a, "SODIUM_CRYPTO_SIGN_SEEDBYTES", .{ .int = 32 });
        try c.put(a, "SODIUM_CRYPTO_SIGN_BYTES", .{ .int = 64 });
        try c.put(a, "SODIUM_CRYPTO_GENERICHASH_BYTES", .{ .int = 32 });
        try c.put(a, "SODIUM_CRYPTO_GENERICHASH_BYTES_MIN", .{ .int = 16 });
        try c.put(a, "SODIUM_CRYPTO_GENERICHASH_BYTES_MAX", .{ .int = 64 });
        try c.put(a, "SODIUM_CRYPTO_GENERICHASH_KEYBYTES", .{ .int = 32 });
        try c.put(a, "SODIUM_CRYPTO_GENERICHASH_KEYBYTES_MIN", .{ .int = 16 });
        try c.put(a, "SODIUM_CRYPTO_GENERICHASH_KEYBYTES_MAX", .{ .int = 64 });
        try c.put(a, "SODIUM_CRYPTO_SHORTHASH_KEYBYTES", .{ .int = 16 });
        try c.put(a, "SODIUM_CRYPTO_SHORTHASH_BYTES", .{ .int = 8 });
        try c.put(a, "SODIUM_CRYPTO_AUTH_BYTES", .{ .int = 32 });
        try c.put(a, "SODIUM_CRYPTO_AUTH_KEYBYTES", .{ .int = 32 });
        try c.put(a, "SODIUM_CRYPTO_PWHASH_SALTBYTES", .{ .int = 16 });
        try c.put(a, "SODIUM_CRYPTO_PWHASH_STRPREFIX", .{ .string = "$argon2id$" });
        try c.put(a, "SODIUM_CRYPTO_PWHASH_ALG_ARGON2I13", .{ .int = 1 });
        try c.put(a, "SODIUM_CRYPTO_PWHASH_ALG_ARGON2ID13", .{ .int = 2 });
        try c.put(a, "SODIUM_CRYPTO_PWHASH_ALG_DEFAULT", .{ .int = 2 });
        try c.put(a, "SODIUM_CRYPTO_PWHASH_OPSLIMIT_INTERACTIVE", .{ .int = 2 });
        try c.put(a, "SODIUM_CRYPTO_PWHASH_MEMLIMIT_INTERACTIVE", .{ .int = 67108864 });
        try c.put(a, "SODIUM_CRYPTO_PWHASH_OPSLIMIT_MODERATE", .{ .int = 3 });
        try c.put(a, "SODIUM_CRYPTO_PWHASH_MEMLIMIT_MODERATE", .{ .int = 268435456 });
        try c.put(a, "SODIUM_CRYPTO_PWHASH_OPSLIMIT_SENSITIVE", .{ .int = 4 });
        try c.put(a, "SODIUM_CRYPTO_PWHASH_MEMLIMIT_SENSITIVE", .{ .int = 1073741824 });
        try c.put(a, "SODIUM_BASE64_VARIANT_ORIGINAL", .{ .int = 1 });
        try c.put(a, "SODIUM_BASE64_VARIANT_ORIGINAL_NO_PADDING", .{ .int = 3 });
        try c.put(a, "SODIUM_BASE64_VARIANT_URLSAFE", .{ .int = 5 });
        try c.put(a, "SODIUM_BASE64_VARIANT_URLSAFE_NO_PADDING", .{ .int = 7 });
        try c.put(a, "SODIUM_CRYPTO_AEAD_CHACHA20POLY1305_IETF_KEYBYTES", .{ .int = 32 });
        try c.put(a, "SODIUM_CRYPTO_AEAD_CHACHA20POLY1305_IETF_NPUBBYTES", .{ .int = 12 });
        try c.put(a, "SODIUM_CRYPTO_AEAD_CHACHA20POLY1305_IETF_ABYTES", .{ .int = 16 });
        try c.put(a, "SODIUM_CRYPTO_AEAD_XCHACHA20POLY1305_IETF_KEYBYTES", .{ .int = 32 });
        try c.put(a, "SODIUM_CRYPTO_AEAD_XCHACHA20POLY1305_IETF_NPUBBYTES", .{ .int = 24 });
        try c.put(a, "SODIUM_CRYPTO_AEAD_XCHACHA20POLY1305_IETF_ABYTES", .{ .int = 16 });
        try c.put(a, "SODIUM_CRYPTO_AEAD_AES256GCM_KEYBYTES", .{ .int = 32 });
        try c.put(a, "SODIUM_CRYPTO_AEAD_AES256GCM_NPUBBYTES", .{ .int = 12 });
        try c.put(a, "SODIUM_CRYPTO_AEAD_AES256GCM_ABYTES", .{ .int = 16 });
        try c.put(a, "SODIUM_CRYPTO_KX_KEYPAIRBYTES", .{ .int = 64 });
        try c.put(a, "SODIUM_CRYPTO_KX_PUBLICKEYBYTES", .{ .int = 32 });
        try c.put(a, "SODIUM_CRYPTO_KX_SECRETKEYBYTES", .{ .int = 32 });
        try c.put(a, "SODIUM_CRYPTO_KX_SESSIONKEYBYTES", .{ .int = 32 });
        try c.put(a, "SODIUM_CRYPTO_KDF_KEYBYTES", .{ .int = 32 });
        try c.put(a, "SODIUM_CRYPTO_KDF_CONTEXTBYTES", .{ .int = 8 });
        try c.put(a, "SODIUM_CRYPTO_KDF_BYTES_MIN", .{ .int = 16 });
        try c.put(a, "SODIUM_CRYPTO_KDF_BYTES_MAX", .{ .int = 64 });
        try c.put(a, "SODIUM_CRYPTO_SCALARMULT_BYTES", .{ .int = 32 });
        try c.put(a, "SODIUM_CRYPTO_SCALARMULT_SCALARBYTES", .{ .int = 32 });
        try c.put(a, "LDAP_DEREF_NEVER", .{ .int = 0 });
        try c.put(a, "LDAP_DEREF_SEARCHING", .{ .int = 1 });
        try c.put(a, "LDAP_DEREF_FINDING", .{ .int = 2 });
        try c.put(a, "LDAP_DEREF_ALWAYS", .{ .int = 3 });
        try c.put(a, "LDAP_OPT_DEREF", .{ .int = 0x02 });
        try c.put(a, "LDAP_OPT_SIZELIMIT", .{ .int = 0x03 });
        try c.put(a, "LDAP_OPT_TIMELIMIT", .{ .int = 0x04 });
        try c.put(a, "LDAP_OPT_NETWORK_TIMEOUT", .{ .int = 0x5005 });
        try c.put(a, "LDAP_OPT_TIMEOUT", .{ .int = 0x5002 });
        try c.put(a, "LDAP_OPT_PROTOCOL_VERSION", .{ .int = 0x11 });
        try c.put(a, "LDAP_OPT_ERROR_NUMBER", .{ .int = 0x31 });
        try c.put(a, "LDAP_OPT_REFERRALS", .{ .int = 0x08 });
        try c.put(a, "LDAP_OPT_RESTART", .{ .int = 0x09 });
        try c.put(a, "LDAP_OPT_HOST_NAME", .{ .int = 0x30 });
        try c.put(a, "LDAP_OPT_ERROR_STRING", .{ .int = 0x32 });
        try c.put(a, "LDAP_OPT_MATCHED_DN", .{ .int = 0x33 });
        try c.put(a, "LDAP_OPT_SERVER_CONTROLS", .{ .int = 0x12 });
        try c.put(a, "LDAP_OPT_CLIENT_CONTROLS", .{ .int = 0x13 });
        try c.put(a, "LDAP_OPT_DEBUG_LEVEL", .{ .int = 0x5001 });
        try c.put(a, "LDAP_OPT_X_TLS_REQUIRE_CERT", .{ .int = 0x6006 });
        try c.put(a, "LDAP_OPT_X_TLS_CACERTDIR", .{ .int = 0x6003 });
        try c.put(a, "LDAP_OPT_X_TLS_CACERTFILE", .{ .int = 0x6002 });
        try c.put(a, "LDAP_OPT_X_TLS_CERTFILE", .{ .int = 0x6004 });
        try c.put(a, "LDAP_OPT_X_TLS_KEYFILE", .{ .int = 0x6005 });
        try c.put(a, "LDAP_OPT_X_TLS_CIPHER_SUITE", .{ .int = 0x6008 });
        try c.put(a, "LDAP_OPT_X_TLS_PROTOCOL_MIN", .{ .int = 0x6007 });
        try c.put(a, "LDAP_OPT_X_TLS_RANDOM_FILE", .{ .int = 0x6009 });
        try c.put(a, "LDAP_OPT_X_TLS_CRLCHECK", .{ .int = 0x600b });
        try c.put(a, "LDAP_OPT_X_TLS_CRLFILE", .{ .int = 0x6011 });
        try c.put(a, "LDAP_OPT_X_TLS_DHFILE", .{ .int = 0x6010 });
        try c.put(a, "LDAP_OPT_X_TLS_NEVER", .{ .int = 0 });
        try c.put(a, "LDAP_OPT_X_TLS_HARD", .{ .int = 1 });
        try c.put(a, "LDAP_OPT_X_TLS_DEMAND", .{ .int = 2 });
        try c.put(a, "LDAP_OPT_X_TLS_ALLOW", .{ .int = 3 });
        try c.put(a, "LDAP_OPT_X_TLS_TRY", .{ .int = 4 });
        try c.put(a, "LDAP_OPT_X_KEEPALIVE_IDLE", .{ .int = 0x6300 });
        try c.put(a, "LDAP_OPT_X_KEEPALIVE_PROBES", .{ .int = 0x6301 });
        try c.put(a, "LDAP_OPT_X_KEEPALIVE_INTERVAL", .{ .int = 0x6302 });
        try c.put(a, "LDAP_OPT_X_TLS_CRL_NONE", .{ .int = 0 });
        try c.put(a, "LDAP_OPT_X_TLS_CRL_PEER", .{ .int = 1 });
        try c.put(a, "LDAP_OPT_X_TLS_CRL_ALL", .{ .int = 2 });
        try c.put(a, "LDAP_ESCAPE_FILTER", .{ .int = 1 });
        try c.put(a, "LDAP_ESCAPE_DN", .{ .int = 2 });
        try c.put(a, "LDAP_CONTROL_PAGEDRESULTS", .{ .string = "1.2.840.113556.1.4.319" });
        try c.put(a, "LDAP_CONTROL_SORTREQUEST", .{ .string = "1.2.840.113556.1.4.473" });
        try c.put(a, "LDAP_CONTROL_VLVREQUEST", .{ .string = "2.16.840.1.113730.3.4.9" });
        try c.put(a, "LDAP_MOD_ADD", .{ .int = 0 });
        try c.put(a, "LDAP_MOD_DELETE", .{ .int = 1 });
        try c.put(a, "LDAP_MOD_REPLACE", .{ .int = 2 });
        try c.put(a, "LDAP_MOD_BVALUES", .{ .int = 0x80 });
        try c.put(a, "SOAP_1_1", .{ .int = 1 });
        try c.put(a, "SOAP_1_2", .{ .int = 2 });
        try c.put(a, "SOAP_RPC", .{ .int = 1 });
        try c.put(a, "SOAP_DOCUMENT", .{ .int = 2 });
        try c.put(a, "SOAP_ENCODED", .{ .int = 1 });
        try c.put(a, "SOAP_LITERAL", .{ .int = 2 });
        try c.put(a, "SOAP_PERSISTENCE_SESSION", .{ .int = 1 });
        try c.put(a, "SOAP_PERSISTENCE_REQUEST", .{ .int = 2 });
        try c.put(a, "SOAP_FUNCTIONS_ALL", .{ .int = 999 });
        try c.put(a, "SOAP_ACTOR_NEXT", .{ .int = 1 });
        try c.put(a, "SOAP_ACTOR_NONE", .{ .int = 2 });
        try c.put(a, "SOAP_ACTOR_UNLIMATERECEIVER", .{ .int = 3 });
        try c.put(a, "SOAP_COMPRESSION_ACCEPT", .{ .int = 32 });
        try c.put(a, "SOAP_COMPRESSION_GZIP", .{ .int = 0 });
        try c.put(a, "SOAP_COMPRESSION_DEFLATE", .{ .int = 16 });
        try c.put(a, "SOAP_AUTHENTICATION_BASIC", .{ .int = 0 });
        try c.put(a, "SOAP_AUTHENTICATION_DIGEST", .{ .int = 1 });
        try c.put(a, "SOAP_SINGLE_ELEMENT_ARRAYS", .{ .int = 1 });
        try c.put(a, "SOAP_WAIT_ONE_WAY_CALLS", .{ .int = 2 });
        try c.put(a, "SOAP_USE_XSI_ARRAY_TYPE", .{ .int = 4 });
        try c.put(a, "WSDL_CACHE_NONE", .{ .int = 0 });
        try c.put(a, "WSDL_CACHE_DISK", .{ .int = 1 });
        try c.put(a, "WSDL_CACHE_MEMORY", .{ .int = 2 });
        try c.put(a, "WSDL_CACHE_BOTH", .{ .int = 3 });
        try c.put(a, "XSD_STRING", .{ .int = 101 });
        try c.put(a, "XSD_BOOLEAN", .{ .int = 102 });
        try c.put(a, "XSD_DECIMAL", .{ .int = 103 });
        try c.put(a, "XSD_FLOAT", .{ .int = 104 });
        try c.put(a, "XSD_DOUBLE", .{ .int = 105 });
        try c.put(a, "XSD_INT", .{ .int = 135 });
        try c.put(a, "XSD_LONG", .{ .int = 134 });
        try c.put(a, "XSD_SHORT", .{ .int = 136 });
        try c.put(a, "FNM_NOESCAPE", .{ .int = 1 });
        try c.put(a, "FNM_PATHNAME", .{ .int = 2 });
        try c.put(a, "FNM_PERIOD", .{ .int = 4 });
        try c.put(a, "FNM_CASEFOLD", .{ .int = 16 });
        try c.put(a, "INI_SCANNER_NORMAL", .{ .int = 0 });
        try c.put(a, "INI_SCANNER_RAW", .{ .int = 1 });
        try c.put(a, "INI_SCANNER_TYPED", .{ .int = 2 });
        try c.put(a, "ARRAY_FILTER_USE_BOTH", .{ .int = 1 });
        try c.put(a, "ARRAY_FILTER_USE_KEY", .{ .int = 2 });
        try c.put(a, "COUNT_NORMAL", .{ .int = 0 });
        try c.put(a, "COUNT_RECURSIVE", .{ .int = 1 });
        try c.put(a, "CASE_LOWER", .{ .int = 0 });
        try c.put(a, "CASE_UPPER", .{ .int = 1 });
        try c.put(a, "JSON_PRETTY_PRINT", .{ .int = 128 });
        try c.put(a, "JSON_UNESCAPED_SLASHES", .{ .int = 64 });
        try c.put(a, "JSON_UNESCAPED_UNICODE", .{ .int = 256 });
        try c.put(a, "JSON_THROW_ON_ERROR", .{ .int = 4194304 });
        try c.put(a, "JSON_ERROR_NONE", .{ .int = 0 });
        try c.put(a, "JSON_ERROR_DEPTH", .{ .int = 1 });
        try c.put(a, "JSON_ERROR_STATE_MISMATCH", .{ .int = 2 });
        try c.put(a, "JSON_ERROR_CTRL_CHAR", .{ .int = 3 });
        try c.put(a, "JSON_ERROR_SYNTAX", .{ .int = 4 });
        try c.put(a, "JSON_ERROR_UTF8", .{ .int = 5 });
        try c.put(a, "JSON_FORCE_OBJECT", .{ .int = 16 });
        try c.put(a, "JSON_NUMERIC_CHECK", .{ .int = 32 });
        try c.put(a, "JSON_PRESERVE_ZERO_FRACTION", .{ .int = 1024 });
        try c.put(a, "JSON_UNESCAPED_LINE_TERMINATORS", .{ .int = 2048 });
        try c.put(a, "JSON_INVALID_UTF8_IGNORE", .{ .int = 1048576 });
        try c.put(a, "JSON_INVALID_UTF8_SUBSTITUTE", .{ .int = 2097152 });
        try c.put(a, "JSON_PARTIAL_OUTPUT_ON_ERROR", .{ .int = 512 });
        try c.put(a, "JSON_BIGINT_AS_STRING", .{ .int = 2 });
        try c.put(a, "JSON_OBJECT_AS_ARRAY", .{ .int = 1 });
        try c.put(a, "MB_CASE_UPPER", .{ .int = 0 });
        try c.put(a, "MB_CASE_LOWER", .{ .int = 1 });
        try c.put(a, "MB_CASE_TITLE", .{ .int = 2 });
        try c.put(a, "HASH_HMAC", .{ .int = 1 });
        try c.put(a, "PHP_ROUND_HALF_UP", .{ .int = 1 });
        try c.put(a, "PHP_ROUND_HALF_DOWN", .{ .int = 2 });
        try c.put(a, "PHP_ROUND_HALF_EVEN", .{ .int = 3 });
        try c.put(a, "PHP_ROUND_HALF_ODD", .{ .int = 4 });
        try c.put(a, "JSON_HEX_TAG", .{ .int = 1 });
        try c.put(a, "JSON_HEX_AMP", .{ .int = 2 });
        try c.put(a, "JSON_HEX_APOS", .{ .int = 4 });
        try c.put(a, "JSON_HEX_QUOT", .{ .int = 8 });
        try c.put(a, "JSON_PARTIAL_OUTPUT_ON_ERROR", .{ .int = 512 });
        try c.put(a, "JSON_INVALID_UTF8_IGNORE", .{ .int = 1048576 });
        try c.put(a, "JSON_INVALID_UTF8_SUBSTITUTE", .{ .int = 2097152 });
        try c.put(a, "E_ERROR", .{ .int = 1 });
        try c.put(a, "E_WARNING", .{ .int = 2 });
        try c.put(a, "E_PARSE", .{ .int = 4 });
        try c.put(a, "E_NOTICE", .{ .int = 8 });
        try c.put(a, "E_CORE_ERROR", .{ .int = 16 });
        try c.put(a, "E_CORE_WARNING", .{ .int = 32 });
        try c.put(a, "E_COMPILE_ERROR", .{ .int = 64 });
        try c.put(a, "E_COMPILE_WARNING", .{ .int = 128 });
        try c.put(a, "E_USER_ERROR", .{ .int = 256 });
        try c.put(a, "E_USER_WARNING", .{ .int = 512 });
        try c.put(a, "E_USER_NOTICE", .{ .int = 1024 });
        try c.put(a, "E_STRICT", .{ .int = 2048 });
        try c.put(a, "E_RECOVERABLE_ERROR", .{ .int = 4096 });
        try c.put(a, "E_DEPRECATED", .{ .int = 8192 });
        try c.put(a, "E_USER_DEPRECATED", .{ .int = 16384 });
        try c.put(a, "E_ALL", .{ .int = 30719 });
        try c.put(a, "PHP_FLOAT_MAX", .{ .float = std.math.floatMax(f64) });
        try c.put(a, "PHP_FLOAT_MIN", .{ .float = std.math.floatMin(f64) });
        try c.put(a, "PHP_FLOAT_EPSILON", .{ .float = std.math.floatEps(f64) });
        try c.put(a, "PHP_MAXPATHLEN", .{ .int = 4096 });
        try c.put(a, "M_PI", .{ .float = std.math.pi });
        try c.put(a, "M_E", .{ .float = std.math.e });
        try c.put(a, "M_SQRT2", .{ .float = std.math.sqrt2 });
        try c.put(a, "M_SQRT1_2", .{ .float = 1.0 / std.math.sqrt2 });
        try c.put(a, "M_LN2", .{ .float = std.math.ln2 });
        try c.put(a, "M_LN10", .{ .float = @log(10.0) });
        try c.put(a, "M_LOG2E", .{ .float = std.math.log2e });
        try c.put(a, "M_LOG10E", .{ .float = std.math.log10e });
        try c.put(a, "M_PI_2", .{ .float = std.math.pi / 2.0 });
        try c.put(a, "M_PI_4", .{ .float = std.math.pi / 4.0 });
        try c.put(a, "M_1_PI", .{ .float = 1.0 / std.math.pi });
        try c.put(a, "M_2_PI", .{ .float = 2.0 / std.math.pi });
        try c.put(a, "M_SQRTPI", .{ .float = @sqrt(std.math.pi) });
        try c.put(a, "M_2_SQRTPI", .{ .float = 2.0 / @sqrt(std.math.pi) });
        try c.put(a, "PHP_FLOAT_DIG", .{ .int = 15 });
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
        try c.put(a, "PASSWORD_DEFAULT", .{ .string = "2y" });
        try c.put(a, "PASSWORD_BCRYPT", .{ .string = "2y" });
        try c.put(a, "PASSWORD_ARGON2I", .{ .string = "argon2i" });
        try c.put(a, "PASSWORD_ARGON2ID", .{ .string = "argon2id" });
        try c.put(a, "CRYPT_BLOWFISH", .{ .int = 1 });
        try c.put(a, "CRYPT_SHA256", .{ .int = 1 });
        try c.put(a, "CRYPT_SHA512", .{ .int = 1 });
        try c.put(a, "PATHINFO_DIRNAME", .{ .int = 1 });
        try c.put(a, "PATHINFO_BASENAME", .{ .int = 2 });
        try c.put(a, "PATHINFO_EXTENSION", .{ .int = 4 });
        try c.put(a, "PATHINFO_FILENAME", .{ .int = 8 });
        try c.put(a, "PATHINFO_ALL", .{ .int = 15 });
        try c.put(a, "OPENSSL_ALGO_SHA1", .{ .int = 1 });
        try c.put(a, "OPENSSL_ALGO_MD5", .{ .int = 2 });
        try c.put(a, "OPENSSL_ALGO_SHA224", .{ .int = 6 });
        try c.put(a, "OPENSSL_ALGO_SHA256", .{ .int = 7 });
        try c.put(a, "OPENSSL_ALGO_SHA384", .{ .int = 8 });
        try c.put(a, "OPENSSL_ALGO_SHA512", .{ .int = 9 });
        try c.put(a, "OPENSSL_RAW_DATA", .{ .int = 1 });
        try c.put(a, "OPENSSL_ZERO_PADDING", .{ .int = 2 });
        try c.put(a, "OPENSSL_PKCS1_PADDING", .{ .int = 1 });
        try c.put(a, "OPENSSL_NO_PADDING", .{ .int = 3 });
        try c.put(a, "DATE_ATOM", .{ .string = "Y-m-d\\TH:i:sP" });
        try c.put(a, "DATE_ISO8601", .{ .string = "Y-m-d\\TH:i:sO" });
        try c.put(a, "DATE_RFC2822", .{ .string = "D, d M Y H:i:s O" });
        try c.put(a, "DATE_RFC3339", .{ .string = "Y-m-d\\TH:i:sP" });
        try c.put(a, "DATE_W3C", .{ .string = "Y-m-d\\TH:i:sP" });
        try c.put(a, "DATE_COOKIE", .{ .string = "l, d-M-Y H:i:s T" });
        try c.put(a, "DATE_RFC822", .{ .string = "D, d M y H:i:s O" });
        try c.put(a, "DATE_RFC850", .{ .string = "l, d-M-y H:i:s T" });
        try c.put(a, "DATE_RFC1036", .{ .string = "D, d M y H:i:s O" });
        try c.put(a, "DATE_RFC1123", .{ .string = "D, d M Y H:i:s O" });
        try c.put(a, "DATE_RFC7231", .{ .string = "D, d M Y H:i:s \\G\\M\\T" });
        try c.put(a, "DATE_RSS", .{ .string = "D, d M Y H:i:s O" });
        // signal numbers are registered above via std.posix.SIG.*; do not
        // re-register them here with hardcoded macOS values or they clobber
        // the platform-correct numbers on Linux (SIGUSR1=10 vs macOS=30)
        try c.put(a, "AF_INET", .{ .int = 2 });
        try c.put(a, "AF_INET6", .{ .int = if (@import("builtin").os.tag == .macos) @as(i64, 30) else 10 });
        try c.put(a, "AF_UNIX", .{ .int = 1 });
        try c.put(a, "SOCK_STREAM", .{ .int = 1 });
        try c.put(a, "SOCK_DGRAM", .{ .int = 2 });
        try c.put(a, "SOCK_RAW", .{ .int = 3 });
        try c.put(a, "SOL_SOCKET", .{ .int = if (@import("builtin").os.tag == .macos) @as(i64, 0xffff) else 1 });
        try c.put(a, "STREAM_CLIENT_CONNECT", .{ .int = 4 });
        try c.put(a, "STREAM_CLIENT_PERSISTENT", .{ .int = 1 });
        try c.put(a, "STREAM_CLIENT_ASYNC_CONNECT", .{ .int = 2 });
        try c.put(a, "PHP_OS_FAMILY", .{ .string = switch (@import("builtin").os.tag) {
            .macos => "Darwin",
            .linux => "Linux",
            .windows => "Windows",
            .freebsd, .netbsd, .openbsd, .dragonfly => "BSD",
            else => "Unknown",
        } });
        try c.put(a, "PHP_BINARY", .{ .string = "zphp" });
        try c.put(a, "PREG_PATTERN_ORDER", .{ .int = 1 });
        try c.put(a, "PREG_SET_ORDER", .{ .int = 2 });
        try c.put(a, "PREG_OFFSET_CAPTURE", .{ .int = 256 });
        try c.put(a, "PREG_SPLIT_DELIM_CAPTURE", .{ .int = 2 });
        try c.put(a, "PREG_SPLIT_NO_EMPTY", .{ .int = 1 });
        try c.put(a, "PREG_SPLIT_OFFSET_CAPTURE", .{ .int = 4 });
        try c.put(a, "PREG_GREP_INVERT", .{ .int = 1 });
        try c.put(a, "PREG_UNMATCHED_AS_NULL", .{ .int = 512 });
        try c.put(a, "PREG_NO_ERROR", .{ .int = 0 });
        try c.put(a, "PREG_INTERNAL_ERROR", .{ .int = 1 });
        try c.put(a, "PREG_BACKTRACK_LIMIT_ERROR", .{ .int = 2 });
        try c.put(a, "PREG_RECURSION_LIMIT_ERROR", .{ .int = 3 });
        try c.put(a, "PREG_BAD_UTF8_ERROR", .{ .int = 4 });
        try c.put(a, "PREG_BAD_UTF8_OFFSET_ERROR", .{ .int = 5 });
        try c.put(a, "PREG_JIT_STACKLIMIT_ERROR", .{ .int = 6 });
        try c.put(a, "LOCK_SH", .{ .int = 1 });
        try c.put(a, "LOCK_EX", .{ .int = 2 });
        try c.put(a, "LOCK_UN", .{ .int = 3 });
        try c.put(a, "LOCK_NB", .{ .int = 4 });
        try c.put(a, "FILE_USE_INCLUDE_PATH", .{ .int = 1 });
        try c.put(a, "FILE_IGNORE_NEW_LINES", .{ .int = 2 });
        try c.put(a, "FILE_SKIP_EMPTY_LINES", .{ .int = 4 });
        try c.put(a, "FILE_APPEND", .{ .int = 8 });
        try c.put(a, "FILE_NO_DEFAULT_CONTEXT", .{ .int = 16 });
        try c.put(a, "SCANDIR_SORT_ASCENDING", .{ .int = 0 });
        try c.put(a, "SCANDIR_SORT_DESCENDING", .{ .int = 1 });
        try c.put(a, "SCANDIR_SORT_NONE", .{ .int = 2 });
        try c.put(a, "SEEK_SET", .{ .int = 0 });
        try c.put(a, "SEEK_CUR", .{ .int = 1 });
        try c.put(a, "SEEK_END", .{ .int = 2 });
        try c.put(a, "FILTER_VALIDATE_INT", .{ .int = 257 });
        try c.put(a, "FILTER_VALIDATE_FLOAT", .{ .int = 259 });
        try c.put(a, "FILTER_VALIDATE_IP", .{ .int = 275 });
        try c.put(a, "FILTER_VALIDATE_EMAIL", .{ .int = 274 });
        try c.put(a, "FILTER_VALIDATE_URL", .{ .int = 273 });
        try c.put(a, "FILTER_VALIDATE_BOOLEAN", .{ .int = 258 });
        try c.put(a, "FILTER_SANITIZE_STRING", .{ .int = 513 });
        try c.put(a, "FILTER_SANITIZE_SPECIAL_CHARS", .{ .int = 515 });
        try c.put(a, "FILTER_SANITIZE_FULL_SPECIAL_CHARS", .{ .int = 522 });
        try c.put(a, "FILTER_SANITIZE_EMAIL", .{ .int = 517 });
        try c.put(a, "FILTER_SANITIZE_URL", .{ .int = 518 });
        try c.put(a, "FILTER_SANITIZE_NUMBER_INT", .{ .int = 519 });
        try c.put(a, "FILTER_SANITIZE_NUMBER_FLOAT", .{ .int = 520 });
        try c.put(a, "FILTER_SANITIZE_ENCODED", .{ .int = 514 });
        try c.put(a, "FILTER_FLAG_IPV4", .{ .int = 1048576 });
        try c.put(a, "FILTER_FLAG_IPV6", .{ .int = 2097152 });
        try c.put(a, "FILTER_FLAG_NO_PRIV_RANGE", .{ .int = 8388608 });
        try c.put(a, "FILTER_FLAG_NO_RES_RANGE", .{ .int = 4194304 });
        try c.put(a, "FILTER_FLAG_HOSTNAME", .{ .int = 1048576 });
        try c.put(a, "FILTER_NULL_ON_FAILURE", .{ .int = 134217728 });
        try c.put(a, "FILTER_SANITIZE_FULL_SPECIAL_CHARS", .{ .int = 522 });
        try c.put(a, "FILTER_FLAG_NO_ENCODE_QUOTES", .{ .int = 128 });
        try c.put(a, "FILTER_FLAG_STRIP_LOW", .{ .int = 4 });
        try c.put(a, "FILTER_FLAG_STRIP_HIGH", .{ .int = 8 });
        try c.put(a, "FILTER_DEFAULT", .{ .int = 516 });
        try c.put(a, "FILTER_VALIDATE_REGEXP", .{ .int = 272 });
        try c.put(a, "FILTER_VALIDATE_DOMAIN", .{ .int = 277 });
        try c.put(a, "FILTER_VALIDATE_MAC", .{ .int = 276 });
        try c.put(a, "FILTER_FLAG_ALLOW_FRACTION", .{ .int = 4096 });
        try c.put(a, "FILTER_FLAG_ALLOW_OCTAL", .{ .int = 1 });
        try c.put(a, "FILTER_FLAG_ALLOW_HEX", .{ .int = 2 });
        try c.put(a, "FILTER_FLAG_ALLOW_THOUSAND", .{ .int = 8192 });
        try c.put(a, "FILTER_FLAG_ALLOW_SCIENTIFIC", .{ .int = 16384 });
        try c.put(a, "FILTER_FLAG_ALLOW_THOUSAND", .{ .int = 8192 });
        try c.put(a, "FILTER_FLAG_ALLOW_SCIENTIFIC", .{ .int = 16384 });
        try c.put(a, "FILTER_REQUIRE_SCALAR", .{ .int = 33554432 });
        try c.put(a, "FILTER_REQUIRE_ARRAY", .{ .int = 16777216 });
        try c.put(a, "FILTER_FORCE_ARRAY", .{ .int = 67108864 });
        try c.put(a, "FILTER_FLAG_EMAIL_UNICODE", .{ .int = 1048576 });
        try c.put(a, "FILTER_FLAG_PATH_REQUIRED", .{ .int = 262144 });
        try c.put(a, "FILTER_FLAG_QUERY_REQUIRED", .{ .int = 524288 });
        try c.put(a, "FILTER_UNSAFE_RAW", .{ .int = 516 });
        try c.put(a, "FILTER_CALLBACK", .{ .int = 1024 });
        try c.put(a, "FILTER_SANITIZE_ADD_SLASHES", .{ .int = 523 });
        try c.put(a, "INPUT_POST", .{ .int = 0 });
        try c.put(a, "INPUT_GET", .{ .int = 1 });
        try c.put(a, "INPUT_COOKIE", .{ .int = 2 });
        try c.put(a, "INPUT_ENV", .{ .int = 4 });
        try c.put(a, "INPUT_SERVER", .{ .int = 5 });
        try c.put(a, "INPUT_SESSION", .{ .int = 6 });
        try c.put(a, "INPUT_REQUEST", .{ .int = 99 });
        try c.put(a, "T_OPEN_TAG", .{ .int = 379 });
        try c.put(a, "T_OPEN_TAG_WITH_ECHO", .{ .int = 380 });
        try c.put(a, "T_CLOSE_TAG", .{ .int = 381 });
        try c.put(a, "T_INLINE_HTML", .{ .int = 312 });
        try c.put(a, "T_WHITESPACE", .{ .int = 382 });
        try c.put(a, "T_VARIABLE", .{ .int = 309 });
        try c.put(a, "T_STRING", .{ .int = 310 });
        try c.put(a, "T_LNUMBER", .{ .int = 311 });
        try c.put(a, "T_DNUMBER", .{ .int = 313 });
        try c.put(a, "T_CONSTANT_ENCAPSED_STRING", .{ .int = 314 });
        try c.put(a, "T_ENCAPSED_AND_WHITESPACE", .{ .int = 315 });
        try c.put(a, "T_COMMENT", .{ .int = 393 });
        try c.put(a, "T_DOC_COMMENT", .{ .int = 394 });
        try c.put(a, "TOKEN_PARSE", .{ .int = 1 });
        try c.put(a, "T_ECHO", .{ .int = 400 });
        try c.put(a, "T_FUNCTION", .{ .int = 401 });
        try c.put(a, "T_CLASS", .{ .int = 402 });
        try c.put(a, "T_RETURN", .{ .int = 403 });
        try c.put(a, "T_IF", .{ .int = 404 });
        try c.put(a, "T_ELSE", .{ .int = 405 });
        try c.put(a, "T_ELSEIF", .{ .int = 406 });
        try c.put(a, "T_WHILE", .{ .int = 407 });
        try c.put(a, "T_FOR", .{ .int = 408 });
        try c.put(a, "T_FOREACH", .{ .int = 409 });
        try c.put(a, "T_DO", .{ .int = 410 });
        try c.put(a, "T_SWITCH", .{ .int = 411 });
        try c.put(a, "T_CASE", .{ .int = 412 });
        try c.put(a, "T_BREAK", .{ .int = 413 });
        try c.put(a, "T_CONTINUE", .{ .int = 414 });
        try c.put(a, "T_DEFAULT", .{ .int = 415 });
        try c.put(a, "T_PUBLIC", .{ .int = 416 });
        try c.put(a, "T_PROTECTED", .{ .int = 417 });
        try c.put(a, "T_PRIVATE", .{ .int = 418 });
        try c.put(a, "T_STATIC", .{ .int = 419 });
        try c.put(a, "T_ABSTRACT", .{ .int = 420 });
        try c.put(a, "T_FINAL", .{ .int = 421 });
        try c.put(a, "T_NAMESPACE", .{ .int = 422 });
        try c.put(a, "T_USE", .{ .int = 423 });
        try c.put(a, "T_EXTENDS", .{ .int = 424 });
        try c.put(a, "T_IMPLEMENTS", .{ .int = 425 });
        try c.put(a, "T_NEW", .{ .int = 426 });
        try c.put(a, "T_THROW", .{ .int = 427 });
        try c.put(a, "T_TRY", .{ .int = 428 });
        try c.put(a, "T_CATCH", .{ .int = 429 });
        try c.put(a, "T_FINALLY", .{ .int = 430 });
        try c.put(a, "T_NULL", .{ .int = 431 });
        try c.put(a, "T_TRUE", .{ .int = 432 });
        try c.put(a, "T_FALSE", .{ .int = 433 });
        try c.put(a, "T_CONST", .{ .int = 434 });
        try c.put(a, "T_INTERFACE", .{ .int = 435 });
        try c.put(a, "T_TRAIT", .{ .int = 436 });
        try c.put(a, "T_ENUM", .{ .int = 437 });
        try c.put(a, "T_GLOBAL", .{ .int = 438 });
        try c.put(a, "T_REQUIRE", .{ .int = 439 });
        try c.put(a, "T_REQUIRE_ONCE", .{ .int = 440 });
        try c.put(a, "T_INCLUDE", .{ .int = 441 });
        try c.put(a, "T_INCLUDE_ONCE", .{ .int = 442 });
        try c.put(a, "T_PRINT", .{ .int = 443 });
        try c.put(a, "T_READONLY", .{ .int = 444 });
        try c.put(a, "T_YIELD", .{ .int = 445 });
        try c.put(a, "T_FN", .{ .int = 446 });
        try c.put(a, "T_MATCH", .{ .int = 447 });
        try c.put(a, "T_AS", .{ .int = 448 });
        try c.put(a, "T_INSTANCEOF", .{ .int = 449 });
    }

    fn freeHeapItems(self: *VM) void {
        // cleanup subsystem resources before freeing strings, because cleanup
        // reads class_name from each object and those names may live in self.strings
        // (e.g. when created by unserialize via ctx.createString)
        @import("../stdlib/pdo.zig").cleanupResources(self.objects);
        @import("../stdlib/curl.zig").cleanupResources(self.objects);
        @import("../stdlib/filesystem.zig").cleanupHandles(self.objects);
        @import("../stdlib/dom.zig").cleanupResources(self.objects);
        @import("../stdlib/simplexml.zig").cleanupResources(self.objects);
        @import("../stdlib/xmlreader.zig").cleanupResources(self.objects);
        @import("../stdlib/xmlwriter.zig").cleanupResources(self.objects);
        @import("../stdlib/intl.zig").cleanupResources(self.objects);
        @import("../stdlib/gmp.zig").cleanupResources(self.objects);
        @import("../stdlib/gd.zig").cleanupResources(self.objects);
        @import("../stdlib/ftp.zig").cleanupResources(self.objects);
        @import("../stdlib/ldap.zig").cleanupResources(self.objects);
        @import("../stdlib/mysqli.zig").cleanupConnections(self.objects);
        // clean up fiber frames before strings/arrays/objects since fiber frames
        // may reference values that get freed by those passes
        for (self.fibers.items) |f| self.cleanupFiberFrames(f);
        for (self.strings.items) |s| self.allocator.free(s);
        for (self.arrays.items) |a| {
            a.deinit(self.allocator);
            self.allocator.destroy(a);
        }
        for (self.objects.items) |o| {
            o.deinit(self.allocator);
            self.allocator.destroy(o);
        }
        for (self.generators.items) |g| {
            g.deinit(self.allocator);
            self.allocator.destroy(g);
        }
        for (self.fibers.items) |f| {
            f.deinit(self.allocator);
            self.allocator.destroy(f);
        }
        for (self.ref_cells.items) |c| self.allocator.destroy(c);
        var statics_iter = self.statics.keyIterator();
        while (statics_iter.next()) |k| self.allocator.free(k.*);
        if (!self.serve_mode) {
            for (self.compile_results.items) |r| {
                var result = r;
                result.deinit();
                self.allocator.destroy(result);
            }
        }
    }

    fn freeClassState(self: *VM) void {
        var class_iter = self.classes.valueIterator();
        while (class_iter.next()) |c| c.deinit(self.allocator);
        self.classes.clearRetainingCapacity();
        var iface_iter = self.interfaces.valueIterator();
        while (iface_iter.next()) |i| i.deinit(self.allocator);
        self.interfaces.clearRetainingCapacity();
        self.traits.clearRetainingCapacity();
        var tu_iter = self.trait_uses.valueIterator();
        while (tu_iter.next()) |subs| self.allocator.free(subs.*);
        self.trait_uses.clearRetainingCapacity();
        var tp_iter = self.trait_props.valueIterator();
        while (tp_iter.next()) |props| self.allocator.free(props.*);
        self.trait_props.clearRetainingCapacity();
        var tsp_iter = self.trait_static_props.valueIterator();
        while (tsp_iter.next()) |props| self.allocator.free(props.*);
        self.trait_static_props.clearRetainingCapacity();
        var tc_iter = self.trait_constants.valueIterator();
        while (tc_iter.next()) |props| self.allocator.free(props.*);
        self.trait_constants.clearRetainingCapacity();
    }

    fn releaseFrames(self: *VM) void {
        for (0..self.frame_count) |i| self.deinitFrameSlot(i);
        // sweep any maps left in slots above frame_count from non-popFrame
        // paths (fast pops, exception unwinds, generator suspends).
        // do not touch locals/vars - those are owned by the call path or
        // already freed; only the ref_* maps can persist past pop.
        if (self.frame_high_water > self.frame_count) {
            for (self.frame_count..self.frame_high_water) |i| {
                self.frames[i].ref_slots.deinit(self.allocator);
                self.frames[i].ref_array_bindings.deinit(self.allocator);
                self.frames[i].ref_object_bindings.deinit(self.allocator);
                self.frames[i].ref_slots = .{};
                self.frames[i].ref_array_bindings = .{};
                self.frames[i].ref_object_bindings = .{};
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
        g_type_info.deinit(self.allocator);
        g_type_info = .{};
        self.functions.deinit(self.allocator);
        var fa_iter = self.function_attributes.valueIterator();
        while (fa_iter.next()) |attrs| {
            for (attrs.*) |a| {
                if (a.args.len > 0) self.allocator.free(a.args);
                if (a.arg_names.len > 0) self.allocator.free(a.arg_names);
            }
            self.allocator.free(attrs.*);
        }
        self.function_attributes.deinit(self.allocator);
        self.native_fns.deinit(self.allocator);
        self.output.deinit(self.allocator);
        self.strings.deinit(self.allocator);
        self.captures.deinit(self.allocator);
        self.capture_index.deinit(self.allocator);
        self.php_constants.deinit(self.allocator);
        self.user_constants.deinit(self.allocator);
        self.ini_settings.deinit(self.allocator);
        self.ini_callbacks.deinit(self.allocator);
        self.shutdown_callbacks.deinit(self.allocator);
        self.error_handler_stack.deinit(self.allocator);
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
        var tu_iter = self.trait_uses.valueIterator();
        while (tu_iter.next()) |subs| self.allocator.free(subs.*);
        self.trait_uses.deinit(self.allocator);
        var tp_iter = self.trait_props.valueIterator();
        while (tp_iter.next()) |props| self.allocator.free(props.*);
        self.trait_props.deinit(self.allocator);
        var tsp_iter = self.trait_static_props.valueIterator();
        while (tsp_iter.next()) |props| self.allocator.free(props.*);
        self.trait_static_props.deinit(self.allocator);
        var tc_iter = self.trait_constants.valueIterator();
        while (tc_iter.next()) |props| self.allocator.free(props.*);
        self.trait_constants.deinit(self.allocator);
        self.statics.deinit(self.allocator);
        var sc_iter = self.statics_cells.iterator();
        while (sc_iter.next()) |entry| self.allocator.destroy(entry.value_ptr.*);
        self.statics_cells.deinit(self.allocator);
        var gc_iter = self.globals_cells.iterator();
        while (gc_iter.next()) |entry| self.allocator.destroy(entry.value_ptr.*);
        self.globals_cells.deinit(self.allocator);
        self.static_vars.deinit(self.allocator);
        self.global_vars.deinit(self.allocator);
        self.loaded_files.deinit(self.allocator);
        self.stream_wrappers_unregistered.deinit(self.allocator);
        self.stream_wrappers_user.deinit(self.allocator);
        if (self.serve_mode) {
            for (self.compile_results.items) |r| {
                var result = r;
                result.deinit();
                self.allocator.destroy(result);
            }
        }
        self.compile_results.deinit(self.allocator);
        self.ob_stack.deinit(self.allocator);
        self.request_vars.deinit(self.allocator);
        self.autoload_callbacks.deinit(self.allocator);
        self.magic_get_guard.deinit(self.allocator);
        self.magic_call_guard.deinit(self.allocator);
        self.prop_hook_guard.deinit(self.allocator);
        for (self.serve_cache_keys.items) |k| self.allocator.free(k);
        self.serve_cache_keys.deinit(self.allocator);
        self.serve_compile_cache.deinit(self.allocator);
    }

    pub fn reset(self: *VM) void {
        self.releaseFrames();
        self.frame_high_water = 0;
        self.freeHeapItems();
        if (self.serve_mode) self.freeClassState();
        self.frame_count = 0;
        self.sp = 0;
        self.handler_count = 0;
        self.handler_floor = 0;
        self.current_fiber = null;
        self.fiber_suspend_pending = false;
        self.fiber_suspend_value = .null;
        self.error_msg = null;
        self.exit_requested = false;
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
        self.response_code = 200;
        self.response_content_type = "text/html";
        self.response_headers = null;
        self.headers_sent = false;
        self.default_tz_name = "UTC";
        self.default_tz_offset = 0;
        self.statics.clearRetainingCapacity();
        var sc_it = self.statics_cells.iterator();
        while (sc_it.next()) |entry| self.allocator.destroy(entry.value_ptr.*);
        self.statics_cells.clearRetainingCapacity();
        var gc_it = self.globals_cells.iterator();
        while (gc_it.next()) |entry| self.allocator.destroy(entry.value_ptr.*);
        self.globals_cells.clearRetainingCapacity();
        self.static_vars.clearRetainingCapacity();
        self.global_vars.clearRetainingCapacity();
        self.loaded_files.clearRetainingCapacity();
        self.stream_wrappers_unregistered.clearRetainingCapacity();
        self.stream_wrappers_user.clearRetainingCapacity();
        self.magic_get_guard.clearRetainingCapacity();
        self.magic_call_guard.clearRetainingCapacity();
        if (self.serve_mode) {
            self.functions.clearRetainingCapacity();
            self.php_constants.clearRetainingCapacity();
            initConstants(&self.php_constants, self.allocator) catch {};
            // freeClassState above cleared the class table. re-seed it with
            // the stdlib classes so PDO, DateTime, SPL types etc. are visible
            // to the next request
            registerStdlibClasses(self, self.allocator) catch {};
            self.autoload_callbacks.clearRetainingCapacity();
            self.closure_instance_count = 0;
        } else {
            self.compile_results.clearRetainingCapacity();
        }
    }

    pub fn interpret(self: *VM, result: *const CompileResult) RuntimeError!void {
        for (result.functions.items) |*func| {
            try self.registerFunction(func);
        }
        for (result.type_hints.items) |th| {
            try g_type_info.put(self.allocator, th.name, .{ .param_types = th.param_types, .return_type = th.return_type });
        }
        for (result.function_attrs.items) |fa| {
            try self.function_attributes.put(self.allocator, fa.name, fa.attrs);
        }
        var vars: std.StringHashMapUnmanaged(Value) = .{};
        var it = self.request_vars.iterator();
        while (it.next()) |entry| {
            try vars.put(self.allocator, entry.key_ptr.*, entry.value_ptr.*);
        }
        if (!vars.contains("$GLOBALS")) {
            const globals_arr = try self.allocator.create(PhpArray);
            globals_arr.* = .{};
            try self.arrays.append(self.allocator, globals_arr);
            try vars.put(self.allocator, "$GLOBALS", .{ .array = globals_arr });
            self.globals_array = globals_arr;
        } else {
            const gv = vars.get("$GLOBALS").?;
            if (gv == .array) self.globals_array = gv.array;
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
        self.top_slot_names = result.slot_names;
        self.source = result.source;
        self.file_path = result.file_path;
        self.script_strict_types = result.strict_types;
        self.frames[0] = .{ .chunk = &result.chunk, .ip = 0, .vars = vars, .locals = locals };
        self.frame_count = 1;
        self.obj_id_base = self.objects.items.len;
        try self.run();
    }

    // tracked allocPrint into self.error_msg. the underlying string is
    // appended to self.strings so it gets freed at vm.deinit/reset rather
    // than leaking when the error is recovered (e.g. caught by user code)
    pub fn setErrorMsg(self: *VM, comptime fmt: []const u8, args: anytype) void {
        const msg = std.fmt.allocPrint(self.allocator, fmt, args) catch {
            self.error_msg = null;
            return;
        };
        self.strings.append(self.allocator, msg) catch {
            self.allocator.free(msg);
            self.error_msg = null;
            return;
        };
        self.error_msg = msg;
    }

    pub fn registerFunction(self: *VM, func: *const ObjFunction) RuntimeError!void {
        if (self.functions.contains(func.name)) return;
        try self.functions.put(self.allocator, func.name, func);
    }

    fn runUntilFrame(self: *VM, base_frame: usize) RuntimeError!void {
        if (self.frame_count <= base_frame) return;
        self.runLoop(base_frame) catch |err| {
            if (self.pending_exception != null) {
                if (self.dispatchPendingException(self.run_base_frame)) {
                    self.exception_dispatched = true;
                    return;
                }
            }
            // surface the Zig error in error_msg so callers (e.g. require's
            // catch block) don't replace it with a generic "Failed opening"
            // message. captures the current function name and IP so the user
            // gets a real diagnostic instead of a bare RuntimeError
            if (self.error_msg == null and self.pending_exception == null) {
                const cur_frame = if (self.frame_count > 0) &self.frames[self.frame_count - 1] else null;
                const ip: usize = if (cur_frame) |f| f.ip else 0;
                const func_name: []const u8 = if (cur_frame) |f|
                    if (f.func) |fn_def| fn_def.name else "<top>"
                else
                    "<no frame>";
                self.setErrorMsg("Fatal error: internal {s} in {s} at ip {d}", .{ @errorName(err), func_name, ip });
            }
            return error.RuntimeError;
        };
    }

    pub fn run(self: *VM) RuntimeError!void {
        return self.runLoop(0);
    }

    fn runLoop(self: *VM, base_frame: usize) RuntimeError!void {
        const prev_base_frame = self.run_base_frame;
        self.run_base_frame = base_frame;
        defer self.run_base_frame = prev_base_frame;
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
                .swap => {
                    const tmp = self.stack[self.sp - 1];
                    self.stack[self.sp - 1] = self.stack[self.sp - 2];
                    self.stack[self.sp - 2] = tmp;
                },

                .get_var => {
                    const idx = self.readU16();
                    const name = self.currentChunk().constants.items[idx].string;
                    // $GLOBALS is a true superglobal: always resolve to the
                    // single shared array on the VM, regardless of frame scope
                    if (std.mem.eql(u8, name, "$GLOBALS")) {
                        if (self.globals_array) |ga| {
                            self.push(.{ .array = ga });
                            continue;
                        }
                    }
                    if (self.currentFrame().ref_slots.get(name)) |cell| {
                        self.push(cell.*);
                    } else if (self.currentFrame().vars.get(name)) |val| {
                        // if this variable is backed by the concat buffer,
                        // materialize a stable copy so the buffer can safely
                        // reallocate on future appends
                        if (self.ic) |ic| {
                            if (val == .string and val.string.len > 0 and
                                ic.concat_buf.items.len > 0 and
                                val.string.ptr == ic.concat_buf.items.ptr)
                            {
                                const stable = try self.allocator.alloc(u8, val.string.len);
                                @memcpy(stable, val.string);
                                try self.strings.append(self.allocator, stable);
                                self.push(.{ .string = stable });
                                continue;
                            }
                        }
                        self.push(val);
                    } else if (self.php_constants.get(name)) |val| {
                        self.push(val);
                    } else if (std.mem.lastIndexOfScalar(u8, name, '\\')) |sep| blk: {
                        // PHP fallback: bare constants in a namespace try
                        // <ns>\<name> first, then fall back to the global <name>
                        const bare = name[sep + 1 ..];
                        if (self.php_constants.get(bare)) |val| {
                            self.push(val);
                            break :blk;
                        }
                        self.push(.null);
                    } else if (name.len > 2 and name[0] == '$' and name[1] == '_') {
                        self.push(self.request_vars.get(name) orelse .null);
                    } else if (self.request_vars.get(name)) |rv| {
                        self.push(rv);
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
                        try self.propagateCellWrite(cell, val);
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

                .get_var_var => {
                    const name_val = self.pop();
                    const raw_name = if (name_val == .string) name_val.string else "";
                    if (raw_name.len == 0) {
                        self.push(.null);
                    } else {
                        var buf: [256]u8 = undefined;
                        const dollar_name = varVarName(raw_name, &buf);
                        if (self.currentFrame().ref_slots.get(dollar_name)) |cell| {
                            self.push(cell.*);
                        } else {
                            // check locals first (via slot_names) since vars can have stale entries
                            const sn = if (self.currentFrame().func) |func| func.slot_names else self.global_slot_names;
                            var found = false;
                            for (sn, 0..) |s, si| {
                                if (std.mem.eql(u8, s, dollar_name)) {
                                    if (si < self.currentFrame().locals.len) {
                                        self.push(self.currentFrame().locals[si]);
                                    } else {
                                        self.push(.null);
                                    }
                                    found = true;
                                    break;
                                }
                            }
                            if (!found) {
                                if (self.currentFrame().vars.get(dollar_name)) |val| {
                                    self.push(val);
                                } else if (dollar_name.len > 2 and dollar_name[0] == '$' and dollar_name[1] == '_') {
                                    self.push(self.request_vars.get(dollar_name) orelse .null);
                                } else {
                                    self.push(.null);
                                }
                            }
                        }
                    }
                },
                .set_var_var => {
                    const name_val = self.pop();
                    const raw_name = if (name_val == .string) name_val.string else "";
                    const val = try self.copyValue(self.peek());
                    if (raw_name.len > 0) {
                        var buf: [256]u8 = undefined;
                        const dollar_name = varVarName(raw_name, &buf);
                        if (self.currentFrame().ref_slots.get(dollar_name)) |cell| {
                            cell.* = val;
                        } else {
                            const sn = if (self.currentFrame().func) |func| func.slot_names else self.global_slot_names;
                            var found_slot = false;
                            for (sn, 0..) |s, si| {
                                if (std.mem.eql(u8, s, dollar_name)) {
                                    if (si < self.currentFrame().locals.len) self.currentFrame().locals[si] = val;
                                    found_slot = true;
                                    break;
                                }
                            }
                            if (!found_slot) {
                                const stable_key = try std.fmt.allocPrint(self.allocator, "${s}", .{raw_name});
                                try self.strings.append(self.allocator, stable_key);
                                try self.currentFrame().vars.put(self.allocator, stable_key, val);
                            }
                        }
                    }
                },

                .add => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .array and b == .array) {
                        self.push(.{ .array = try self.arrayUnion(a.array, b.array) });
                    } else {
                        if (try self.checkArithOperands(a, b, "+")) continue;
                        self.push(Value.add(a, b));
                    }
                },
                .subtract => {
                    const b = self.pop();
                    const a = self.pop();
                    if (try self.checkArithOperands(a, b, "-")) continue;
                    self.push(Value.subtract(a, b));
                },
                .multiply => {
                    const b = self.pop();
                    const a = self.pop();
                    if (try self.checkArithOperands(a, b, "*")) continue;
                    self.push(Value.multiply(a, b));
                },
                .inc_value => {
                    const v = self.pop();
                    const incremented = try Value.phpInc(v, self.allocator);
                    // phpInc allocates a new buffer only for the alpha-increment
                    // path (existing non-empty non-numeric string). track those
                    // for cleanup; other paths return scalars or string literals
                    if (incremented == .string and v == .string and v.string.len > 0
                        and !Value.isNumericString(v.string)) {
                        try self.strings.append(self.allocator, @constCast(incremented.string));
                    }
                    self.push(incremented);
                },
                .dec_value => {
                    const v = self.pop();
                    self.push(Value.phpDec(v));
                },
                .divide => {
                    const b = self.pop();
                    const a = self.pop();
                    if (try self.checkArithOperands(a, b, "/")) continue;
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
                    if (try self.checkArithOperands(a, b, "%")) continue;
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
                    if (try self.checkArithOperands(a, b, "**")) continue;
                    self.push(Value.power(a, b));
                },
                .negate => {
                    const v = self.pop();
                    if (!isArithOperand(v)) {
                        const tn = arithTypeName(v);
                        const msg = try std.fmt.allocPrint(self.allocator, "Cannot negate {s}", .{tn});
                        try self.strings.append(self.allocator, msg);
                        if (try self.throwBuiltinException("TypeError", msg)) continue;
                        return error.RuntimeError;
                    }
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
                            const s = self.objectToString(a.object) catch {
                                if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            };
                            try buf.appendSlice(self.allocator, s);
                        } else try a.format(&buf, self.allocator);
                        if (b == .object) {
                            const s = self.objectToString(b.object) catch {
                                if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            };
                            try buf.appendSlice(self.allocator, s);
                        } else try b.format(&buf, self.allocator);
                        const owned = try buf.toOwnedSlice(self.allocator);
                        try self.strings.append(self.allocator, owned);
                        self.push(.{ .string = owned });
                    }
                },

                .bit_and => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .string and b == .string) {
                        const result = try self.bitwiseStrings(a.string, b.string, .and_op);
                        self.push(.{ .string = result });
                    } else {
                        if (try self.checkArithOperands(a, b, "&")) continue;
                        self.push(.{ .int = Value.toInt(a) & Value.toInt(b) });
                    }
                },
                .bit_or => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .string and b == .string) {
                        const result = try self.bitwiseStrings(a.string, b.string, .or_op);
                        self.push(.{ .string = result });
                    } else {
                        if (try self.checkArithOperands(a, b, "|")) continue;
                        self.push(.{ .int = Value.toInt(a) | Value.toInt(b) });
                    }
                },
                .bit_xor => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .string and b == .string) {
                        const result = try self.bitwiseStrings(a.string, b.string, .xor_op);
                        self.push(.{ .string = result });
                    } else {
                        if (try self.checkArithOperands(a, b, "^")) continue;
                        self.push(.{ .int = Value.toInt(a) ^ Value.toInt(b) });
                    }
                },
                .bit_not => {
                    const v = self.pop();
                    self.push(.{ .int = ~Value.toInt(v) });
                },
                .shift_left => {
                    const b = self.pop();
                    const a = self.pop();
                    const sh = Value.toInt(b);
                    if (sh < 0) {
                        self.sp += 2;
                        if (try self.throwBuiltinException("ArithmeticError", "Bit shift by negative number")) continue;
                        return error.RuntimeError;
                    }
                    if (sh >= 64) { self.push(.{ .int = 0 }); } else {
                        const shift: u6 = @intCast(sh);
                        self.push(.{ .int = Value.toInt(a) << shift });
                    }
                },
                .shift_right => {
                    const b = self.pop();
                    const a = self.pop();
                    const sh = Value.toInt(b);
                    if (sh < 0) {
                        self.sp += 2;
                        if (try self.throwBuiltinException("ArithmeticError", "Bit shift by negative number")) continue;
                        return error.RuntimeError;
                    }
                    if (sh >= 64) {
                        // arithmetic shift: -1 stays -1, otherwise 0
                        const v = Value.toInt(a);
                        self.push(.{ .int = if (v < 0) -1 else 0 });
                    } else {
                        const shift: u6 = @intCast(sh);
                        self.push(.{ .int = Value.toInt(a) >> shift });
                    }
                },

                .equal => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(.{ .bool = try self.looseEqualWithStringable(a, b) });
                },
                .not_equal => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(.{ .bool = !try self.looseEqualWithStringable(a, b) });
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
                    self.push(.{ .bool = try self.compareWithStringable(a, b) < 0 });
                },
                .less_equal => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(.{ .bool = try self.compareWithStringable(a, b) <= 0 });
                },
                .greater => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(.{ .bool = try self.compareWithStringable(a, b) > 0 });
                },
                .greater_equal => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(.{ .bool = try self.compareWithStringable(a, b) >= 0 });
                },
                .spaceship => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(.{ .int = try self.compareWithStringable(a, b) });
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
                    try self.pollExecutionDeadline();
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
                            self.setErrorMsg("Fatal error: Uncaught TypeError: Array callback must have exactly two elements", .{});
                            return error.RuntimeError;
                        }
                        const target = arr.entries.items[0].value;
                        const method_val = arr.entries.items[1].value;
                        if (method_val != .string) {
                            self.setErrorMsg("Fatal error: Uncaught TypeError: Method name must be a string", .{});
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
                            var buf: [512]u8 = undefined;
                            const full = std.fmt.bufPrint(&buf, "{s}::{s}", .{ target.string, method }) catch return error.RuntimeError;
                            break :blk ctx.vm.callByName(full, args_buf[0..ac]) catch |err| {
                                if (err == error.RuntimeError and self.autoload_callbacks.items.len > 0) {
                                    try self.tryAutoload(target.string);
                                    const full2 = std.fmt.bufPrint(&buf, "{s}::{s}", .{ target.string, method }) catch return error.RuntimeError;
                                    break :blk try ctx.vm.callByName(full2, args_buf[0..ac]);
                                }
                                return err;
                            };
                        } else {
                            var buf2: [256]u8 = undefined;
                            const msg = std.fmt.bufPrint(&buf2, "Value of type {s} is not callable", .{valueTypeName(target)}) catch "Value is not callable";
                            if (try self.throwBuiltinException("TypeError", msg)) continue;
                            return error.RuntimeError;
                        };
                        self.push(result);
                    } else {
                        var buf2: [256]u8 = undefined;
                        const msg = std.fmt.bufPrint(&buf2, "Value of type {s} is not callable", .{valueTypeName(name_val)}) catch "Value is not callable";
                        if (try self.throwBuiltinException("TypeError", msg)) continue;
                        return error.RuntimeError;
                    }
                },
                .call_spread => {
                    if (self.global_vars_dirty) try self.syncGlobalLocalsToVars();
                    const name_idx = self.readU16();
                    const name = self.currentChunk().constants.items[name_idx].string;
                    const args_val = self.pop();
                    if (args_val != .array) {
                        self.setErrorMsg("Fatal error: Uncaught TypeError: Argument unpacking requires an array", .{});
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
                            var assigned: [16]bool = .{false} ** 16;
                            var pos: usize = 0;
                            var ok = true;
                            for (arr.entries.items) |entry| {
                                if (entry.key == .string) {
                                    var found = false;
                                    for (func.params, 0..) |p, pi| {
                                        if (std.mem.eql(u8, p[1..], entry.key.string) or std.mem.eql(u8, p, entry.key.string)) {
                                            if (assigned[pi]) {
                                                const msg = try std.fmt.allocPrint(self.allocator, "Named argument ${s} overwrites previous argument", .{entry.key.string});
                                                try self.strings.append(self.allocator, msg);
                                                if (try self.throwBuiltinException("Error", msg)) { ok = false; break; }
                                                return error.RuntimeError;
                                            }
                                            resolved[pi] = entry.value;
                                            assigned[pi] = true;
                                            if (pi >= pos) pos = pi + 1;
                                            found = true;
                                            break;
                                        }
                                    }
                                    if (!ok) break;
                                    if (!found) {
                                        const msg = try std.fmt.allocPrint(self.allocator, "Unknown named parameter ${s}", .{entry.key.string});
                                        try self.strings.append(self.allocator, msg);
                                        if (try self.throwBuiltinException("Error", msg)) { ok = false; break; }
                                        return error.RuntimeError;
                                    }
                                } else {
                                    if (assigned[pos]) {
                                        // positional after a named that already filled this slot
                                        ok = true;
                                    }
                                    resolved[pos] = entry.value;
                                    assigned[pos] = true;
                                    pos += 1;
                                }
                            }
                            if (!ok) continue;
                            // fill defaults
                            const count = @max(pos, func.required_params);
                            for (0..count) |i| {
                                if (resolved[i] == .null and i < func.defaults.len) {
                                    resolved[i] = try self.resolveDefault(func.defaults[i]);
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
                    if (args_val != .array) {
                        var buf2: [256]u8 = undefined;
                        const msg = std.fmt.bufPrint(&buf2, "Value of type {s} is not callable", .{valueTypeName(name_val)}) catch "Value is not callable";
                        if (try self.throwBuiltinException("TypeError", msg)) continue;
                        return error.RuntimeError;
                    }
                    const arr = args_val.array;
                    if (name_val == .string) {
                        var has_named_args = false;
                        for (arr.entries.items) |entry| {
                            if (entry.key == .string) { has_named_args = true; break; }
                        }
                        if (has_named_args) {
                            if (self.functions.get(name_val.string)) |func| {
                                var resolved: [16]Value = .{.null} ** 16;
                                var pos: usize = 0;
                                for (arr.entries.items) |entry| {
                                    if (entry.key == .string) {
                                        for (func.params, 0..) |p, pi| {
                                            const pn = if (p.len > 0 and p[0] == '$') p[1..] else p;
                                            if (std.mem.eql(u8, pn, entry.key.string)) {
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
                                try self.callNamedFunction(name_val.string, @intCast(pos));
                            } else {
                                for (arr.entries.items) |entry| self.push(entry.value);
                                const ac2: u8 = @intCast(arr.entries.items.len);
                                try self.callNamedFunction(name_val.string, ac2);
                            }
                        } else {
                            for (arr.entries.items) |entry| self.push(entry.value);
                            const ac: u8 = @intCast(arr.entries.items.len);
                            try self.callNamedFunction(name_val.string, ac);
                        }
                    } else if (name_val == .array) {
                        const cb_arr = name_val.array;
                        if (cb_arr.entries.items.len == 2) {
                            const target = cb_arr.entries.items[0].value;
                            const method_val = cb_arr.entries.items[1].value;
                            if (method_val == .string) {
                                var args_buf: [32]Value = undefined;
                                const ac = arr.entries.items.len;
                                for (0..ac) |i| args_buf[i] = arr.entries.items[i].value;
                                const result = if (target == .object)
                                    try self.callMethod(target.object, method_val.string, args_buf[0..ac])
                                else if (target == .string) blk: {
                                    var buf: [256]u8 = undefined;
                                    const full = std.fmt.bufPrint(&buf, "{s}::{s}", .{ target.string, method_val.string }) catch return error.RuntimeError;
                                    break :blk try self.callByName(full, args_buf[0..ac]);
                                } else {
                                    var buf2: [256]u8 = undefined;
                                    const msg = std.fmt.bufPrint(&buf2, "Value of type {s} is not callable", .{valueTypeName(name_val)}) catch "Value is not callable";
                                    if (try self.throwBuiltinException("TypeError", msg)) continue;
                                    return error.RuntimeError;
                                };
                                self.push(result);
                            } else {
                                if (try self.throwBuiltinException("TypeError", "Method name must be a string")) continue;
                                return error.RuntimeError;
                            }
                        } else {
                            if (try self.throwBuiltinException("TypeError", "Array callback must have exactly two elements")) continue;
                            return error.RuntimeError;
                        }
                    } else if (name_val == .object and self.hasMethod(name_val.object.class_name, "__invoke")) {
                        var args_buf: [32]Value = undefined;
                        const ac = arr.entries.items.len;
                        for (0..ac) |i| args_buf[i] = arr.entries.items[i].value;
                        const result = try self.callMethod(name_val.object, "__invoke", args_buf[0..ac]);
                        self.push(result);
                    } else {
                        var buf2: [256]u8 = undefined;
                        const msg = std.fmt.bufPrint(&buf2, "Value of type {s} is not callable", .{valueTypeName(name_val)}) catch "Value is not callable";
                        if (try self.throwBuiltinException("TypeError", msg)) continue;
                        return error.RuntimeError;
                    }
                },
                .return_val => {
                    var result = self.pop();
                    if (g_type_info.count() > 0) {
                        if (try self.checkReturnType(&result)) continue;
                    }
                    const saved_entry_sp = self.currentFrame().entry_sp;
                    try self.popFrame();
                    if (saved_entry_sp > 0) self.sp = saved_entry_sp;
                    self.push(result);
                    if (self.frame_count <= base_frame) return;
                },
                .return_void => {
                    const saved_entry_sp = self.currentFrame().entry_sp;
                    try self.popFrame();
                    if (saved_entry_sp > 0) self.sp = saved_entry_sp;
                    self.push(.null);
                    if (self.frame_count <= base_frame) return;
                },

                .echo => {
                    const v = self.pop();
                    if (v == .object) {
                        const s = self.objectToString(v.object) catch {
                            if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                            return error.RuntimeError;
                        };
                        try self.output.appendSlice(self.allocator, s);
                    } else {
                        try v.format(&self.output, self.allocator);
                    }
                    if (self.ob_stack.items.len == 0) self.headers_sent = true;
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
                        _ = self.callMethod(arr_val.object, "offsetSet", &.{ .null, val }) catch {
                            if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                            return error.RuntimeError;
                        };
                    }
                },
                .array_set_elem => {
                    const val = self.pop();
                    const key = self.pop();
                    const arr_val = self.peek();
                    if (arr_val == .array) {
                        if (key == .array or key == .object) {
                            if (try self.throwOffsetKeyType(key, .access)) continue;
                            return error.RuntimeError;
                        }
                        try arr_val.array.set(self.allocator, Value.toArrayKey(key), val);
                    } else if (arr_val == .object and self.hasMethod(arr_val.object.class_name, "offsetSet")) {
                        _ = self.callMethod(arr_val.object, "offsetSet", &.{ key, val }) catch {
                            if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                            return error.RuntimeError;
                        };
                    }
                },
                .array_get => {
                    const key = self.pop();
                    const arr_val = self.pop();
                    if (arr_val == .array) {
                        if (key == .array or key == .object) {
                            if (try self.throwOffsetKeyType(key, .access)) continue;
                            return error.RuntimeError;
                        }
                        const ak = Value.toArrayKey(key);
                        if (!arr_val.array.contains(ak)) {
                            self.emitUndefinedKeyWarning(ak);
                        }
                        self.push(arr_val.array.get(ak));
                    } else if (arr_val == .object and self.hasMethod(arr_val.object.class_name, "offsetGet")) {
                        const result = self.callMethod(arr_val.object, "offsetGet", &.{key}) catch {
                            if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                            return error.RuntimeError;
                        };
                        self.push(result);
                    } else if (arr_val == .string) {
                        const s = arr_val.string;
                        const idx = Value.toInt(key);
                        const resolved: ?usize = if (idx >= 0)
                            if (@as(usize, @intCast(idx)) < s.len) @as(usize, @intCast(idx)) else null
                        else if (@as(usize, @intCast(-idx)) <= s.len)
                            s.len - @as(usize, @intCast(-idx))
                        else
                            null;
                        if (resolved) |ri| {
                            self.push(.{ .string = s[ri..][0..1] });
                        } else {
                            self.push(.{ .string = "" });
                        }
                    } else {
                        self.push(.null);
                    }
                },
                .array_get_coalesce => {
                    // like array_get but with isset-style semantics for `??`:
                    // OOB string offsets and missing array keys are null, and we
                    // route object access through offsetExists+offsetGet so user
                    // ArrayAccess types don't synthesize a value when the key is
                    // absent
                    const key = self.pop();
                    const arr_val = self.pop();
                    if (arr_val == .array) {
                        if (key == .array or key == .object) {
                            self.push(.null);
                            continue;
                        }
                        self.push(arr_val.array.get(Value.toArrayKey(key)));
                    } else if (arr_val == .object and self.hasMethod(arr_val.object.class_name, "offsetGet")) {
                        if (self.hasMethod(arr_val.object.class_name, "offsetExists")) {
                            const exists = self.callMethod(arr_val.object, "offsetExists", &.{key}) catch {
                                if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            };
                            if (!exists.isTruthy()) {
                                self.push(.null);
                                continue;
                            }
                        }
                        const result = self.callMethod(arr_val.object, "offsetGet", &.{key}) catch {
                            if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                            return error.RuntimeError;
                        };
                        self.push(result);
                    } else if (arr_val == .string) {
                        const s = arr_val.string;
                        const idx = Value.toInt(key);
                        const resolved: ?usize = if (idx >= 0)
                            if (@as(usize, @intCast(idx)) < s.len) @as(usize, @intCast(idx)) else null
                        else if (@as(usize, @intCast(-idx)) <= s.len)
                            s.len - @as(usize, @intCast(-idx))
                        else
                            null;
                        if (resolved) |ri| {
                            self.push(.{ .string = s[ri..][0..1] });
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
                        if (key == .array or key == .object) {
                            if (try self.throwOffsetKeyType(key, .access)) continue;
                            return error.RuntimeError;
                        }
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
                    } else if (arr_val == .object and self.hasMethod(arr_val.object.class_name, "offsetGet")) {
                        const result = self.callMethod(arr_val.object, "offsetGet", &.{key}) catch {
                            if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                            return error.RuntimeError;
                        };
                        self.push(result);
                    } else {
                        self.push(.null);
                    }
                },
                .prop_set_chain => {
                    // depth-2 write for `$obj->prop[i] = v`. always uses
                    // direct property access on base (never offsetGet/Set)
                    const v = self.pop();
                    const inner_key = self.pop();
                    const prop_key = self.pop();
                    const base = self.pop();
                    if (base != .object or prop_key != .string) {
                        self.push(v);
                        continue;
                    }
                    const obj = base.object;
                    const pname = prop_key.string;
                    const ik = Value.toArrayKey(inner_key);
                    const existing = obj.get(pname);
                    if (existing == .string) {
                        const s = existing.string;
                        var idx: i64 = switch (ik) { .int => |n| n, .string => |str| @intCast(std.fmt.parseInt(i64, str, 10) catch 0) };
                        if (idx < 0) idx = @as(i64, @intCast(s.len)) + idx;
                        if (idx < 0) { self.push(v); continue; }
                        var write_byte: u8 = 0;
                        if (v == .string) {
                            if (v.string.len > 0) write_byte = v.string[0];
                        } else {
                            var tmp: std.ArrayListUnmanaged(u8) = .{};
                            defer tmp.deinit(self.allocator);
                            try v.format(&tmp, self.allocator);
                            if (tmp.items.len > 0) write_byte = tmp.items[0];
                        }
                        const target_idx: usize = @intCast(idx);
                        const new_len: usize = @max(s.len, target_idx + 1);
                        const buf = try self.allocator.alloc(u8, new_len);
                        @memcpy(buf[0..s.len], s);
                        if (new_len > s.len) @memset(buf[s.len..], ' ');
                        buf[target_idx] = write_byte;
                        try self.strings.append(self.allocator, buf);
                        try obj.set(self.allocator, pname, .{ .string = buf });
                        self.push(v);
                        continue;
                    }
                    if (existing == .array) {
                        try existing.array.set(self.allocator, ik, v);
                        self.push(v);
                        continue;
                    }
                    if (existing == .null or (existing == .bool and !existing.bool)) {
                        const new_arr = try self.allocator.create(PhpArray);
                        new_arr.* = .{};
                        try self.arrays.append(self.allocator, new_arr);
                        try new_arr.set(self.allocator, ik, v);
                        try obj.set(self.allocator, pname, .{ .array = new_arr });
                        self.push(v);
                        continue;
                    }
                    if (existing == .object and self.hasMethod(existing.object.class_name, "offsetSet")) {
                        _ = self.callMethod(existing.object, "offsetSet", &.{ inner_key, v }) catch {
                            if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                            return error.RuntimeError;
                        };
                        self.push(v);
                        continue;
                    }
                    self.push(v);
                },

                .array_set_chain => {
                    // depth-2 write: $base[outer][inner] = val, or $obj->prop[inner] = val
                    // pops [val, inner_key, outer_key, base]
                    const v = self.pop();
                    const inner_key = self.pop();
                    const outer_key = self.pop();
                    const base = self.pop();
                    const ik = Value.toArrayKey(inner_key);
                    var existing: Value = .null;
                    var base_is_array_access_obj = false;
                    if (base == .array) {
                        existing = base.array.get(Value.toArrayKey(outer_key));
                    } else if (base == .object and self.hasMethod(base.object.class_name, "offsetGet")) {
                        // ArrayObject / WeakMap / custom ArrayAccess: fetch the
                        // inner element via offsetGet so the write is on the
                        // underlying stored value (or routed back through
                        // offsetSet for scalar inners)
                        existing = self.callMethod(base.object, "offsetGet", &.{outer_key}) catch {
                            if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                            return error.RuntimeError;
                        };
                        base_is_array_access_obj = true;
                    } else if (base == .object and outer_key == .string) {
                        existing = base.object.get(outer_key.string);
                    } else {
                        self.push(v);
                        continue;
                    }
                    const ok = Value.toArrayKey(outer_key);
                    if (existing == .string) {
                        const s = existing.string;
                        var idx: i64 = switch (ik) { .int => |n| n, .string => |str| @intCast(std.fmt.parseInt(i64, str, 10) catch 0) };
                        if (idx < 0) idx = @as(i64, @intCast(s.len)) + idx;
                        if (idx < 0) { self.push(v); continue; }
                        var write_byte: u8 = 0;
                        if (v == .string) {
                            if (v.string.len > 0) write_byte = v.string[0];
                        } else {
                            var tmp: std.ArrayListUnmanaged(u8) = .{};
                            defer tmp.deinit(self.allocator);
                            try v.format(&tmp, self.allocator);
                            if (tmp.items.len > 0) write_byte = tmp.items[0];
                        }
                        const target_idx: usize = @intCast(idx);
                        const new_len: usize = @max(s.len, target_idx + 1);
                        const buf = try self.allocator.alloc(u8, new_len);
                        @memcpy(buf[0..s.len], s);
                        if (new_len > s.len) @memset(buf[s.len..], ' ');
                        buf[target_idx] = write_byte;
                        try self.strings.append(self.allocator, buf);
                        if (base == .array) {
                            try base.array.set(self.allocator, ok, .{ .string = buf });
                        } else if (base_is_array_access_obj) {
                            _ = self.callMethod(base.object, "offsetSet", &.{ outer_key, .{ .string = buf } }) catch {
                                if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            };
                        } else if (outer_key == .string) {
                            try base.object.set(self.allocator, outer_key.string, .{ .string = buf });
                        }
                        self.push(v);
                        continue;
                    }
                    if (existing == .array) {
                        try existing.array.set(self.allocator, ik, v);
                        self.push(v);
                        continue;
                    }
                    if (existing == .null or (existing == .bool and !existing.bool)) {
                        const new_arr = try self.allocator.create(PhpArray);
                        new_arr.* = .{};
                        try self.arrays.append(self.allocator, new_arr);
                        try new_arr.set(self.allocator, ik, v);
                        if (base == .array) {
                            try base.array.set(self.allocator, ok, .{ .array = new_arr });
                        } else if (base_is_array_access_obj) {
                            _ = self.callMethod(base.object, "offsetSet", &.{ outer_key, .{ .array = new_arr } }) catch {
                                if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            };
                        } else if (outer_key == .string) {
                            try base.object.set(self.allocator, outer_key.string, .{ .array = new_arr });
                        }
                        self.push(v);
                        continue;
                    }
                    if (existing == .int or existing == .float or (existing == .bool and existing.bool)) {
                        if (try self.throwBuiltinException("Error", "Cannot use a scalar value as an array")) continue;
                        return error.RuntimeError;
                    }
                    if (existing == .object) {
                        if (self.hasMethod(existing.object.class_name, "offsetSet")) {
                            _ = self.callMethod(existing.object, "offsetSet", &.{ inner_key, v }) catch {
                                if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            };
                            self.push(v);
                            continue;
                        }
                    }
                    self.push(v);
                },

                .array_set => {
                    const val = self.pop();
                    const key = self.pop();
                    const arr_val = self.pop();
                    if (arr_val == .array) {
                        if (key == .array or key == .object) {
                            if (try self.throwOffsetKeyType(key, .access)) continue;
                            return error.RuntimeError;
                        }
                        try arr_val.array.set(self.allocator, Value.toArrayKey(key), val);
                        if (self.globals_array) |ga| {
                            if (arr_val.array == ga and key == .string) {
                                try self.mirrorGlobalsWrite(key.string, val);
                            }
                        }
                    } else if (arr_val == .object and self.hasMethod(arr_val.object.class_name, "offsetSet")) {
                        _ = self.callMethod(arr_val.object, "offsetSet", &.{ key, val }) catch {
                            if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                            return error.RuntimeError;
                        };
                    } else if (arr_val == .int or arr_val == .float or (arr_val == .bool and arr_val.bool)) {
                        if (try self.throwBuiltinException("Error", "Cannot use a scalar value as an array")) continue;
                        return error.RuntimeError;
                    } else if (arr_val == .string and key == .string) {
                        if (try self.throwBuiltinException("TypeError", "Cannot access offset of type string on string")) continue;
                        return error.RuntimeError;
                    }
                    self.push(val);
                },

                .array_set_local => {
                    const slot = self.readU16();
                    const val = self.pop();
                    const key = self.pop();
                    const frame = self.currentFrame();

                    var cur: Value = .null;
                    var ref_cell: ?*Value = null;
                    if (frame.func) |func| {
                        if (slot < func.slot_names.len and func.slot_names[slot].len > 0) {
                            if (frame.ref_slots.get(func.slot_names[slot])) |cell| {
                                cur = cell.*;
                                ref_cell = cell;
                            }
                        }
                        if (ref_cell == null and slot < frame.locals.len) cur = frame.locals[slot];
                    } else {
                        cur = self.getLocalGlobal(slot, frame);
                    }

                    if (cur == .string) {
                        const s = cur.string;
                        var idx: i64 = Value.toInt(key);
                        if (idx < 0) idx = @as(i64, @intCast(s.len)) + idx;
                        if (idx < 0) {
                            self.push(val);
                            continue;
                        }
                        var write_byte: u8 = 0;
                        if (val == .string) {
                            if (val.string.len > 0) write_byte = val.string[0];
                        } else {
                            var tmp: std.ArrayListUnmanaged(u8) = .{};
                            defer tmp.deinit(self.allocator);
                            try val.format(&tmp, self.allocator);
                            if (tmp.items.len > 0) write_byte = tmp.items[0];
                        }
                        const target_idx: usize = @intCast(idx);
                        const new_len: usize = @max(s.len, target_idx + 1);
                        const buf = try self.allocator.alloc(u8, new_len);
                        @memcpy(buf[0..s.len], s);
                        if (new_len > s.len) @memset(buf[s.len..], ' ');
                        buf[target_idx] = write_byte;
                        try self.strings.append(self.allocator, buf);
                        const new_str = Value{ .string = buf };

                        if (ref_cell) |cell| cell.* = new_str;
                        if (frame.func) |func| {
                            if (slot < func.slot_names.len) {
                                const name = func.slot_names[slot];
                                if (name.len > 0) try frame.vars.put(self.allocator, name, new_str);
                            }
                            if (slot < frame.locals.len) frame.locals[slot] = new_str;
                        } else {
                            if (slot < frame.locals.len) frame.locals[slot] = new_str;
                            try self.setLocalGlobal(slot, new_str, frame);
                        }
                        self.push(val);
                        continue;
                    }

                    if (cur == .int or cur == .float or (cur == .bool and cur.bool)) {
                        if (try self.throwBuiltinException("Error", "Cannot use a scalar value as an array")) continue;
                        return error.RuntimeError;
                    }

                    if (cur == .null or (cur == .bool and !cur.bool)) {
                        if (key == .array or key == .object) {
                            if (try self.throwOffsetKeyType(key, .access)) continue;
                            return error.RuntimeError;
                        }
                        const new_arr = try self.allocator.create(PhpArray);
                        new_arr.* = .{};
                        try self.arrays.append(self.allocator, new_arr);
                        const arr_val = Value{ .array = new_arr };
                        if (ref_cell) |cell| cell.* = arr_val;
                        if (frame.func) |func| {
                            if (slot < func.slot_names.len) {
                                const name = func.slot_names[slot];
                                if (name.len > 0) try frame.vars.put(self.allocator, name, arr_val);
                            }
                            if (slot < frame.locals.len) frame.locals[slot] = arr_val;
                        } else {
                            if (slot < frame.locals.len) frame.locals[slot] = arr_val;
                            try self.setLocalGlobal(slot, arr_val, frame);
                        }
                        try new_arr.set(self.allocator, Value.toArrayKey(key), val);
                        self.push(val);
                        continue;
                    }

                    if (cur == .array) {
                        if (key == .array or key == .object) {
                            if (try self.throwOffsetKeyType(key, .access)) continue;
                            return error.RuntimeError;
                        }
                        try cur.array.set(self.allocator, Value.toArrayKey(key), val);
                        if (self.globals_array) |ga| {
                            if (cur.array == ga and key == .string) {
                                try self.mirrorGlobalsWrite(key.string, val);
                            }
                        }
                        self.push(val);
                        continue;
                    }

                    if (cur == .object and self.hasMethod(cur.object.class_name, "offsetSet")) {
                        _ = self.callMethod(cur.object, "offsetSet", &.{ key, val }) catch {
                            if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                            return error.RuntimeError;
                        };
                        self.push(val);
                        continue;
                    }

                    self.push(val);
                },

                .ensure_array_local => {
                    const slot = self.readU16();
                    const frame = self.currentFrame();
                    // $GLOBALS resolves to the VM-wide superglobal array
                    const ea_slot_name = if (frame.func) |func|
                        (if (slot < func.slot_names.len) func.slot_names[slot] else "")
                    else
                        (if (slot < self.global_slot_names.len) self.global_slot_names[slot] else "");
                    if (std.mem.eql(u8, ea_slot_name, "$GLOBALS")) {
                        if (self.globals_array) |ga| {
                            self.push(.{ .array = ga });
                            continue;
                        }
                    }
                    var cur: Value = .null;
                    if (frame.func) |func| {
                        var from_ref = false;
                        if (slot < func.slot_names.len and func.slot_names[slot].len > 0) {
                            if (frame.ref_slots.get(func.slot_names[slot])) |cell| {
                                cur = cell.*;
                                from_ref = true;
                            }
                        }
                        if (!from_ref and slot < frame.locals.len) cur = frame.locals[slot];
                    } else {
                        cur = self.getLocalGlobal(slot, frame);
                    }
                    if (cur == .int or cur == .float or (cur == .bool and cur.bool)) {
                        if (try self.throwBuiltinException("Error", "Cannot use a scalar value as an array")) continue;
                        return error.RuntimeError;
                    }
                    if (cur != .null and !(cur == .bool and !cur.bool)) {
                        self.push(cur);
                        continue;
                    }
                    const new_arr = try self.allocator.create(PhpArray);
                    new_arr.* = .{};
                    try self.arrays.append(self.allocator, new_arr);
                    const new_val = Value{ .array = new_arr };
                    if (frame.func) |func| {
                        if (slot < func.slot_names.len) {
                            const name = func.slot_names[slot];
                            if (name.len > 0) {
                                if (frame.ref_slots.get(name)) |cell| cell.* = new_val;
                                try frame.vars.put(self.allocator, name, new_val);
                            }
                        }
                        if (slot < frame.locals.len) frame.locals[slot] = new_val;
                    } else {
                        if (slot < frame.locals.len) frame.locals[slot] = new_val;
                        try self.setLocalGlobal(slot, new_val, frame);
                    }
                    self.push(new_val);
                },

                .ensure_array_var => {
                    const idx = self.readU16();
                    const name = self.currentChunk().constants.items[idx].string;
                    // $GLOBALS resolves to the VM-wide superglobal array
                    if (std.mem.eql(u8, name, "$GLOBALS")) {
                        if (self.globals_array) |ga| {
                            self.push(.{ .array = ga });
                            continue;
                        }
                    }
                    const frame = self.currentFrame();
                    var cur: Value = .null;
                    var from_request = false;
                    if (frame.ref_slots.get(name)) |cell| {
                        cur = cell.*;
                    } else if (frame.vars.get(name)) |v| {
                        cur = v;
                    } else if (name.len > 2 and name[0] == '$' and name[1] == '_') {
                        if (self.request_vars.get(name)) |rv| {
                            cur = rv;
                            from_request = true;
                        }
                    }
                    if (cur == .int or cur == .float or (cur == .bool and cur.bool)) {
                        if (try self.throwBuiltinException("Error", "Cannot use a scalar value as an array")) continue;
                        return error.RuntimeError;
                    }
                    if (cur != .null and !(cur == .bool and !cur.bool)) {
                        self.push(cur);
                        continue;
                    }
                    const new_arr = try self.allocator.create(PhpArray);
                    new_arr.* = .{};
                    try self.arrays.append(self.allocator, new_arr);
                    const new_val = Value{ .array = new_arr };
                    if (frame.ref_slots.get(name)) |cell| {
                        cell.* = new_val;
                    } else if (from_request) {
                        try self.request_vars.put(self.allocator, name, new_val);
                    } else {
                        try frame.vars.put(self.allocator, name, new_val);
                    }
                    const sn = if (frame.func) |func| func.slot_names else self.global_slot_names;
                    for (sn, 0..) |s, si| {
                        if (std.mem.eql(u8, s, name)) {
                            if (si < frame.locals.len) frame.locals[si] = new_val;
                            break;
                        }
                    }
                    self.push(new_val);
                },

                .array_elem_inc, .array_elem_dec => {
                    const aei_key = self.pop();
                    const aei_arr = self.pop();
                    if (aei_arr == .array) {
                        const ak = Value.toArrayKey(aei_key);
                        const old = aei_arr.array.get(ak);
                        const new_val: Value = blk: {
                            if (op == .array_elem_inc) {
                                const v = try Value.phpInc(old, self.allocator);
                                if (v == .string and old == .string and old.string.len > 0
                                    and !Value.isNumericString(old.string)) {
                                    try self.strings.append(self.allocator, @constCast(v.string));
                                }
                                break :blk v;
                            }
                            break :blk Value.phpDec(old);
                        };
                        try aei_arr.array.set(self.allocator, ak, new_val);
                        if (self.globals_array) |ga| {
                            if (aei_arr.array == ga and ak == .string) {
                                try self.mirrorGlobalsWrite(ak.string, new_val);
                            }
                        }
                        self.push(old);
                    } else {
                        self.push(.null);
                    }
                },

                .iter_begin => {
                    var iterable = self.stack[self.sp - 1];
                    if (iterable == .array) {
                        const src = iterable.array;
                        const copy = try self.allocator.create(PhpArray);
                        copy.* = .{};
                        try self.arrays.append(self.allocator, copy);
                        for (src.entries.items) |entry| {
                            try copy.set(self.allocator, entry.key, entry.value);
                        }
                        self.stack[self.sp - 1] = .{ .array = copy };
                        iterable = .{ .array = copy };
                    }
                    if (iterable == .generator) {
                        if (iterable.generator.state == .completed) {
                            if (try self.throwBuiltinException("Exception", "Cannot traverse an already closed generator")) continue;
                            return error.RuntimeError;
                        }
                        if (iterable.generator.state == .created) {
                            self.resumeGenerator(iterable.generator, .null) catch {
                                if (self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            };
                        }
                        self.push(.{ .int = -1 }); // sentinel: -1 means generator iteration
                    } else if (iterable == .object) {
                        // IteratorAggregate: replace iterable with getIterator() result.
                        // PHP allows getIterator to return another IteratorAggregate;
                        // unwrap up to a fixed depth to avoid infinite cycles.
                        var unwrap_dispatched = false;
                        var unwrap_failed = false;
                        var unwrap_steps: u8 = 0;
                        unwrap: while (iterable == .object and self.hasMethod(iterable.object.class_name, "getIterator") and !self.isInstanceOf(iterable.object.class_name, "Iterator") and unwrap_steps < 8) {
                            const inner = self.callMethod(iterable.object, "getIterator", &.{}) catch {
                                if (self.dispatchPendingException(base_frame)) {
                                    unwrap_dispatched = true;
                                } else {
                                    unwrap_failed = true;
                                }
                                break :unwrap;
                            };
                            self.stack[self.sp - 1] = inner;
                            iterable = inner;
                            unwrap_steps += 1;
                        }
                        if (unwrap_dispatched) continue;
                        if (unwrap_failed) return error.RuntimeError;
                        // getIterator may have returned a generator; iterate it directly
                        if (iterable == .generator) {
                            self.resumeGenerator(iterable.generator, .null) catch {
                                if (self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            };
                            self.push(.{ .int = -1 });
                            continue;
                        }
                        // Iterator protocol
                        if (iterable == .object and self.hasMethod(iterable.object.class_name, "rewind")) {
                            _ = self.callMethod(iterable.object, "rewind", &.{}) catch {};
                            self.push(.{ .int = -2 }); // sentinel: -2 means Iterator
                        } else if (iterable == .array) {
                            self.push(.{ .int = 0 });
                        } else if (iterable == .object) {
                            const obj = iterable.object;
                            const arr = try self.allocator.create(PhpArray);
                            arr.* = .{};
                            try self.arrays.append(self.allocator, arr);
                            // when foreach runs inside a class method whose
                            // scope can see private/protected on this object,
                            // include those too (PHP's foreach($this as ...)
                            // sees the full property set). private requires
                            // exact class match; protected requires inheritance
                            const scope_class: ?[]const u8 = if (self.frame_count > 0)
                                self.frames[self.frame_count - 1].called_class orelse self.currentDefiningClass()
                            else
                                null;
                            const includeProp = struct {
                                fn check(vm: *VM, scope: ?[]const u8, vis: ClassDef.Visibility, declaring: []const u8) bool {
                                    if (vis == .public) return true;
                                    const sc = scope orelse return false;
                                    if (vis == .private) return std.mem.eql(u8, sc, declaring);
                                    return vm.isInstanceOf(sc, declaring) or vm.isInstanceOf(declaring, sc);
                                }
                            }.check;
                            if (obj.slots) |slots| {
                                if (obj.slot_layout) |layout| {
                                    for (layout.names, 0..) |name, i| {
                                        if (i < slots.len) {
                                            const vr = self.findPropertyVisibility(obj.class_name, name);
                                            if (includeProp(self, scope_class, vr.visibility, vr.defining_class)) {
                                                try arr.set(self.allocator, .{ .string = name }, slots[i]);
                                            }
                                        }
                                    }
                                }
                            }
                            var it = obj.properties.iterator();
                            while (it.next()) |entry| {
                                const vr = self.findPropertyVisibility(obj.class_name, entry.key_ptr.*);
                                if (includeProp(self, scope_class, vr.visibility, vr.defining_class)) {
                                    try arr.set(self.allocator, .{ .string = entry.key_ptr.* }, entry.value_ptr.*);
                                }
                            }
                            self.stack[self.sp - 1] = .{ .array = arr };
                            self.push(.{ .int = 0 });
                        } else {
                            self.push(.{ .int = 0 });
                        }
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
                    } else if (Value.toInt(idx_val) == -2 and iterable == .object) {
                        // Iterator protocol
                        const valid = self.callMethod(iterable.object, "valid", &.{}) catch {
                            if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                            return error.RuntimeError;
                        };
                        if (!valid.isTruthy()) {
                            self.currentFrame().ip += offset;
                        } else {
                            const key = self.callMethod(iterable.object, "key", &.{}) catch {
                                if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            };
                            const current = self.callMethod(iterable.object, "current", &.{}) catch {
                                if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            };
                            self.push(key);
                            self.push(current);
                        }
                    } else if (iterable == .array) {
                        const idx = Value.toInt(idx_val);
                        if (idx < 0 or idx >= iterable.array.length()) {
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
                        self.resumeGenerator(iterable.generator, .null) catch {
                            if (self.dispatchPendingException(base_frame)) continue;
                            return error.RuntimeError;
                        };
                    } else if (Value.toInt(self.stack[self.sp - 1]) == -2 and iterable == .object) {
                        _ = self.callMethod(iterable.object, "next", &.{}) catch {};
                    } else {
                        const idx = self.pop();
                        self.push(.{ .int = Value.toInt(idx) + 1 });
                    }
                },
                .iter_end => {
                    _ = self.pop();
                    _ = self.pop();
                },
                .iter_end_close => {
                    const iterable = self.stack[self.sp - 2];
                    if (iterable == .generator and iterable.generator.state == .suspended) {
                        try self.closeGenerator(iterable.generator, base_frame);
                    }
                    _ = self.pop();
                    _ = self.pop();
                },

                .silence_begin => {
                    self.error_silenced_depth += 1;
                },
                .silence_end => {
                    if (self.error_silenced_depth > 0) self.error_silenced_depth -= 1;
                },

                .bind_array_ref => {
                    const idx = self.readU16();
                    const name = self.currentChunk().constants.items[idx].string;
                    const key_val = self.pop();
                    const src_val = self.pop();
                    if (src_val != .array) {
                        self.push(.null);
                    } else {
                        const arr_ptr = src_val.array;
                        const key: PhpArray.Key = switch (key_val) {
                            .int => |i| .{ .int = i },
                            .string => |s| .{ .string = s },
                            else => .{ .int = Value.toInt(key_val) },
                        };
                        const cell = try self.allocator.create(Value);
                        cell.* = arr_ptr.get(key);
                        try self.ref_cells.append(self.allocator, cell);
                        try self.currentFrame().ref_slots.put(self.allocator, name, cell);
                        try self.currentFrame().ref_array_bindings.append(self.allocator, .{ .cell = cell, .array = arr_ptr, .key = key });
                    }
                },

                .break_var_ref => {
                    const idx = self.readU16();
                    const name = self.currentChunk().constants.items[idx].string;
                    _ = self.currentFrame().ref_slots.remove(name);
                },

                .make_var_ref => {
                    const dst_idx = self.readU16();
                    const src_idx = self.readU16();
                    const dst_name = self.currentChunk().constants.items[dst_idx].string;
                    const src_name = self.currentChunk().constants.items[src_idx].string;
                    const frame = self.currentFrame();
                    var cell: *Value = undefined;
                    if (frame.ref_slots.get(src_name)) |existing| {
                        cell = existing;
                    } else {
                        cell = try self.allocator.create(Value);
                        // seed without copyValue so cell shares any array pointer
                        var seed: Value = .null;
                        const sn = if (frame.func) |fn_| fn_.slot_names else self.global_slot_names;
                        var found_slot = false;
                        for (sn, 0..) |s, si| {
                            if (std.mem.eql(u8, s, src_name) and si < frame.locals.len) {
                                seed = frame.locals[si];
                                found_slot = true;
                                break;
                            }
                        }
                        if (!found_slot) {
                            if (frame.vars.get(src_name)) |v| seed = v;
                        }
                        cell.* = seed;
                        try self.ref_cells.append(self.allocator, cell);
                        try frame.ref_slots.put(self.allocator, src_name, cell);
                    }
                    try frame.ref_slots.put(self.allocator, dst_name, cell);
                },

                .make_var_array_elem_ref => {
                    const dst_idx = self.readU16();
                    const dst_name = self.currentChunk().constants.items[dst_idx].string;
                    if (std.posix.getenv("ZPHP_DBG_REF") != null) {
                        const sfe = std.fs.File{ .handle = 2 };
                        const f_dbg = self.currentFrame();
                        const fname = if (f_dbg.func) |fn_| fn_.name else "<g>";
                        const cls = f_dbg.called_class orelse "";
                        const fp = if (f_dbg.func) |fn_| fn_.file_path else "";
                        const ln: i64 = if (f_dbg.ip > 0)
                            if (f_dbg.chunk.getSourceLocation(f_dbg.ip - 1, self.source)) |l| @intCast(l.line) else 0
                        else 0;
                        const m = std.fmt.allocPrint(self.allocator, "[MVAER] dst={s} at {s}::{s} {s}:{d}\n", .{ dst_name, cls, fname, fp, ln }) catch return error.RuntimeError;
                        _ = sfe.write(m) catch {};
                        self.allocator.free(m);
                    }
                    const key_val = self.pop();
                    const arr_val = self.pop();
                    const frame = self.currentFrame();
                    _ = frame.ref_slots.remove(dst_name);
                    if (arr_val != .array) {
                        try frame.ref_slots.put(self.allocator, dst_name, blk: {
                            const c = try self.allocator.create(Value);
                            c.* = .null;
                            try self.ref_cells.append(self.allocator, c);
                            break :blk c;
                        });
                    } else {
                        const arr_ptr = arr_val.array;
                        const key: PhpArray.Key = switch (key_val) {
                            .int => |i| .{ .int = i },
                            .string => |s| .{ .string = s },
                            else => .{ .int = Value.toInt(key_val) },
                        };
                        const cell = try self.allocator.create(Value);
                        // seed without cloning so cell shares any nested array pointer
                        cell.* = arr_ptr.get(key);
                        try self.ref_cells.append(self.allocator, cell);
                        try frame.ref_slots.put(self.allocator, dst_name, cell);
                        try frame.ref_array_bindings.append(self.allocator, .{ .cell = cell, .array = arr_ptr, .key = key });
                    }
                },

                .make_var_prop_ref => {
                    const dst_idx = self.readU16();
                    const prop_idx = self.readU16();
                    const dst_name = self.currentChunk().constants.items[dst_idx].string;
                    const prop_name = self.currentChunk().constants.items[prop_idx].string;
                    const obj_val = self.pop();
                    const frame = self.currentFrame();
                    _ = frame.ref_slots.remove(dst_name);
                    if (obj_val != .object) {
                        const c = try self.allocator.create(Value);
                        c.* = .null;
                        try self.ref_cells.append(self.allocator, c);
                        try frame.ref_slots.put(self.allocator, dst_name, c);
                    } else {
                        const obj_ptr = obj_val.object;
                        const cell = try self.allocator.create(Value);
                        cell.* = obj_ptr.get(prop_name);
                        try self.ref_cells.append(self.allocator, cell);
                        try frame.ref_slots.put(self.allocator, dst_name, cell);
                        try frame.ref_object_bindings.append(self.allocator, .{ .cell = cell, .object = obj_ptr, .prop_name = prop_name });
                    }
                },

                .unset_var => {
                    const idx = self.readU16();
                    const name = self.currentChunk().constants.items[idx].string;
                    if (self.currentFrame().vars.get(name)) |existing| {
                        if (existing == .generator) self.closeGenerator(existing.generator, self.frame_count) catch {};
                    }
                    _ = self.currentFrame().vars.remove(name);
                },
                .unset_prop => {
                    const name_idx = self.readU16();
                    const prop_name = self.currentChunk().constants.items[name_idx].string;
                    const obj_val = self.pop();
                    if (obj_val == .object) {
                        const obj = obj_val.object;
                        {
                            const vr = self.findPropertyVisibility(obj.class_name, prop_name);
                            if (vr.is_readonly and obj.get(prop_name) != .null) {
                                const msg = try std.fmt.allocPrint(self.allocator, "Cannot unset readonly property {s}::${s}", .{ obj.class_name, prop_name });
                                try self.strings.append(self.allocator, msg);
                                if (try self.throwBuiltinException("Error", msg)) continue;
                                return error.RuntimeError;
                            }
                        }
                        if (self.hasMethod(obj.class_name, "__unset")) {
                            _ = self.callMethod(obj, "__unset", &.{.{ .string = prop_name }}) catch {};
                        } else {
                            // mark the property as unset so subsequent reads
                            // fall through to __get (matching PHP's lazy-init
                            // pattern). slot value remains its default; only
                            // the unset_slots set decides "present"
                            try obj.markUnset(self.allocator, prop_name);
                            if (obj.slots) |s| {
                                if (obj.getSlotIndex(prop_name)) |idx| {
                                    s[idx] = .null;
                                }
                            }
                            _ = obj.properties.orderedRemove(prop_name);
                        }
                    }
                },
                .unset_prop_dynamic => {
                    const name_val = self.pop();
                    const obj_val = self.pop();
                    if (obj_val == .object and name_val == .string) {
                        const obj = obj_val.object;
                        const prop_name = name_val.string;
                        const vr = self.findPropertyVisibility(obj.class_name, prop_name);
                        if (vr.is_readonly and obj.get(prop_name) != .null) {
                            const msg = try std.fmt.allocPrint(self.allocator, "Cannot unset readonly property {s}::${s}", .{ obj.class_name, prop_name });
                            try self.strings.append(self.allocator, msg);
                            if (try self.throwBuiltinException("Error", msg)) continue;
                            return error.RuntimeError;
                        }
                        if (self.hasMethod(obj.class_name, "__unset")) {
                            _ = self.callMethod(obj, "__unset", &.{.{ .string = prop_name }}) catch {};
                        } else {
                            try obj.markUnset(self.allocator, prop_name);
                            if (obj.slots) |s| {
                                if (obj.getSlotIndex(prop_name)) |idx| {
                                    s[idx] = .null;
                                }
                            }
                            _ = obj.properties.orderedRemove(prop_name);
                        }
                    }
                },
                .unset_array_elem => {
                    const key = self.pop();
                    const arr_val = self.pop();
                    if (arr_val == .array) {
                        if (key == .array or key == .object) {
                            if (try self.throwOffsetKeyType(key, .unset)) continue;
                            return error.RuntimeError;
                        }
                        arr_val.array.remove(Value.toArrayKey(key));
                    } else if (arr_val == .object) {
                        if (self.hasMethod(arr_val.object.class_name, "offsetUnset")) {
                            _ = self.callMethod(arr_val.object, "offsetUnset", &.{key}) catch {
                                if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            };
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

                        // finalize old buffer: transfer ownership to self.strings so
                        // external references (array entries etc.) remain valid, then
                        // start a fresh buffer
                        if (ic.concat_buf.items.len > 0 and ic.concat_slot != 0xFFFF) {
                            const old_str = try self.allocator.alloc(u8, ic.concat_buf.items.len);
                            @memcpy(old_str, ic.concat_buf.items);
                            try self.strings.append(self.allocator, old_str);
                            if (ic.concat_frame == self.frame_count and ic.concat_slot < self.currentFrame().locals.len) {
                                const old_val = self.currentFrame().locals[ic.concat_slot];
                                if (old_val == .string and old_val.string.ptr == ic.concat_buf.items.ptr) {
                                    self.currentFrame().locals[ic.concat_slot] = .{ .string = old_str };
                                }
                            }
                            // preserve old buffer memory for external references
                            if (ic.concat_buf.capacity > 0) {
                                try self.strings.append(self.allocator, ic.concat_buf.allocatedSlice());
                                ic.concat_buf = .{};
                            }
                        } else {
                            ic.concat_buf.clearRetainingCapacity();
                        }
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
                            // $GLOBALS is a superglobal — always resolve to
                            // the shared VM-level array
                            if (std.mem.eql(u8, func.slot_names[slot], "$GLOBALS")) {
                                if (self.globals_array) |ga| {
                                    self.push(.{ .array = ga });
                                    continue;
                                }
                            }
                        }
                        if (slot < frame.locals.len) {
                            self.push(frame.locals[slot]);
                        } else {
                            self.push(.null);
                        }
                    } else {
                        // top-frame: check $GLOBALS by slot name
                        if (slot < self.global_slot_names.len and std.mem.eql(u8, self.global_slot_names[slot], "$GLOBALS")) {
                            if (self.globals_array) |ga| {
                                self.push(.{ .array = ga });
                                continue;
                            }
                        }
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
                                    try self.propagateCellWrite(cell, val);
                                }
                                try frame.vars.put(self.allocator, name, val);
                            }
                        }
                    } else {
                        try self.setLocalGlobal(slot, val, frame);
                    }
                },
                .inc_local => {
                    const slot = self.readU16();
                    const frame_il = self.currentFrame();
                    if (slot < frame_il.locals.len) {
                        const v = frame_il.locals[slot];
                        if (v == .int) {
                            frame_il.locals[slot] = Value.intInc(v.int);
                        } else if (v == .float) {
                            frame_il.locals[slot] = .{ .float = v.float + 1.0 };
                        } else {
                            const incremented = try Value.phpInc(v, self.allocator);
                            if (incremented == .string and v == .string and v.string.len > 0
                                and !Value.isNumericString(v.string)) {
                                try self.strings.append(self.allocator, @constCast(incremented.string));
                            }
                            frame_il.locals[slot] = incremented;
                        }
                    }
                },
                .dec_local => {
                    const slot = self.readU16();
                    const frame_dl = self.currentFrame();
                    if (slot < frame_dl.locals.len) {
                        const v = frame_dl.locals[slot];
                        frame_dl.locals[slot] = if (v == .int) Value.intDec(v.int) else if (v == .float) .{ .float = v.float - 1.0 } else Value.phpDec(v);
                    }
                },
                .add_local_to_local => {
                    const src_slot = self.readU16();
                    const dst_slot = self.readU16();
                    const frame_al = self.currentFrame();
                    if (src_slot < frame_al.locals.len and dst_slot < frame_al.locals.len) {
                        const src = frame_al.locals[src_slot];
                        const dst = frame_al.locals[dst_slot];
                        frame_al.locals[dst_slot] = if (src == .int and dst == .int) Value.intAdd(dst.int, src.int) else if (src == .float and dst == .float) .{ .float = dst.float + src.float } else if (src == .array and dst == .array) .{ .array = try self.arrayUnion(dst.array, src.array) } else Value.add(dst, src);
                    }
                },
                .sub_local_to_local => {
                    const src_slot = self.readU16();
                    const dst_slot = self.readU16();
                    const frame_sl = self.currentFrame();
                    if (src_slot < frame_sl.locals.len and dst_slot < frame_sl.locals.len) {
                        const src = frame_sl.locals[src_slot];
                        const dst = frame_sl.locals[dst_slot];
                        frame_sl.locals[dst_slot] = if (src == .int and dst == .int) Value.intSub(dst.int, src.int) else if (src == .float and dst == .float) .{ .float = dst.float - src.float } else Value.subtract(dst, src);
                    }
                },
                .mul_local_to_local => {
                    const src_slot = self.readU16();
                    const dst_slot = self.readU16();
                    const frame_ml = self.currentFrame();
                    if (src_slot < frame_ml.locals.len and dst_slot < frame_ml.locals.len) {
                        const src = frame_ml.locals[src_slot];
                        const dst = frame_ml.locals[dst_slot];
                        frame_ml.locals[dst_slot] = if (src == .int and dst == .int) Value.intMul(dst.int, src.int) else if (src == .float and dst == .float) .{ .float = dst.float * src.float } else Value.multiply(dst, src);
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
                .isset_prop_dynamic => {
                    const prop_name_val = self.pop();
                    const obj_val = self.pop();
                    if (obj_val == .object and prop_name_val == .string) {
                        const obj = obj_val.object;
                        const prop_name = prop_name_val.string;
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
                    if ((arr_val == .array or (arr_val == .object and (std.mem.eql(u8, arr_val.object.class_name, "ArrayObject") or std.mem.eql(u8, arr_val.object.class_name, "ArrayIterator")))) and (key == .array or key == .object)) {
                        if (try self.throwOffsetKeyType(key, .isset_or_empty)) continue;
                        return error.RuntimeError;
                    }
                    if (arr_val == .object and (std.mem.eql(u8, arr_val.object.class_name, "ArrayObject") or std.mem.eql(u8, arr_val.object.class_name, "ArrayIterator"))) {
                        // SPL ArrayObject/ArrayIterator: isset() is null-aware (PHP's spl_array_has_dimension semantics)
                        const data = arr_val.object.get("__data");
                        if (data == .array) {
                            const v = data.array.get(Value.toArrayKey(key));
                            self.push(.{ .bool = v != .null });
                        } else {
                            self.push(.{ .bool = false });
                        }
                    } else if (arr_val == .object and self.hasMethod(arr_val.object.class_name, "offsetExists")) {
                        const result = self.callMethod(arr_val.object, "offsetExists", &.{key}) catch {
                            if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                            return error.RuntimeError;
                        };
                        self.push(.{ .bool = result.isTruthy() });
                    } else if (arr_val == .array) {
                        const v = arr_val.array.get(Value.toArrayKey(key));
                        self.push(.{ .bool = v != .null });
                    } else if (arr_val == .string) {
                        const s = arr_val.string;
                        const idx = Value.toInt(key);
                        const valid = if (idx >= 0)
                            @as(usize, @intCast(idx)) < s.len
                        else
                            @as(usize, @intCast(-idx)) <= s.len;
                        self.push(.{ .bool = valid });
                    } else {
                        self.push(.{ .bool = false });
                    }
                },
                .clone_obj => {
                    const val = self.pop();
                    // PHP rejects cloning of generators and fibers with Error
                    if (val == .generator) {
                        if (try self.throwBuiltinException("Error", "Trying to clone an uncloneable object of class Generator")) continue;
                        return error.RuntimeError;
                    }
                    if (val == .fiber) {
                        if (try self.throwBuiltinException("Error", "Trying to clone an uncloneable object of class Fiber")) continue;
                        return error.RuntimeError;
                    }
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

                .get_obj_class => {
                    const v = self.pop();
                    if (v == .object) {
                        self.push(.{ .string = v.object.class_name });
                    } else {
                        self.setErrorMsg("Fatal error: Cannot use \"::class\" on non-object", .{});
                        return error.RuntimeError;
                    }
                },

                .cast_int => {
                    const v = self.pop();
                    if (v == .object and self.hasMethod(v.object.class_name, "__toString")) {
                        const s = self.objectToString(v.object) catch {
                            if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                            return error.RuntimeError;
                        };
                        self.push(.{ .int = Value.toInt(.{ .string = s }) });
                    } else {
                        if (v == .object) {
                            const w = std.fmt.allocPrint(self.allocator, "Object of class {s} could not be converted to int", .{v.object.class_name}) catch null;
                            if (w) |m| {
                                self.strings.append(self.allocator, m) catch {};
                                self.emitWarning(m);
                            }
                        }
                        self.push(.{ .int = Value.toInt(v) });
                    }
                },
                .cast_float => {
                    const v = self.pop();
                    if (v == .object and self.hasMethod(v.object.class_name, "__toString")) {
                        const s = self.objectToString(v.object) catch {
                            if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                            return error.RuntimeError;
                        };
                        self.push(.{ .float = Value.toFloat(.{ .string = s }) });
                    } else {
                        if (v == .object) {
                            const w = std.fmt.allocPrint(self.allocator, "Object of class {s} could not be converted to float", .{v.object.class_name}) catch null;
                            if (w) |m| {
                                self.strings.append(self.allocator, m) catch {};
                                self.emitWarning(m);
                            }
                        }
                        self.push(.{ .float = Value.toFloat(v) });
                    }
                },
                .cast_string => {
                    const v = self.pop();
                    if (v == .string) {
                        self.push(v);
                    } else if (v == .object) {
                        const s = self.objectToString(v.object) catch {
                            if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                            return error.RuntimeError;
                        };
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
                    } else if (v == .object) {
                        const obj = v.object;
                        const arr = try self.allocator.create(PhpArray);
                        arr.* = .{};
                        try self.arrays.append(self.allocator, arr);
                        if (obj.slots) |slots| {
                            if (obj.slot_layout) |layout| {
                                for (layout.names, 0..) |name, i| {
                                    if (i < slots.len) {
                                        const vr = self.findPropertyVisibility(obj.class_name, name);
                                        const key_str: []const u8 = switch (vr.visibility) {
                                            .public => name,
                                            .protected => try std.fmt.allocPrint(self.allocator, "\x00*\x00{s}", .{name}),
                                            .private => try std.fmt.allocPrint(self.allocator, "\x00{s}\x00{s}", .{ vr.defining_class, name }),
                                        };
                                        if (vr.visibility != .public) try self.strings.append(self.allocator, key_str);
                                        try arr.set(self.allocator, .{ .string = key_str }, slots[i]);
                                    }
                                }
                            }
                        }
                        var it = obj.properties.iterator();
                        while (it.next()) |entry| {
                            const vr = self.findPropertyVisibility(obj.class_name, entry.key_ptr.*);
                            const key_str: []const u8 = switch (vr.visibility) {
                                .public => entry.key_ptr.*,
                                .protected => try std.fmt.allocPrint(self.allocator, "\x00*\x00{s}", .{entry.key_ptr.*}),
                                .private => try std.fmt.allocPrint(self.allocator, "\x00{s}\x00{s}", .{ vr.defining_class, entry.key_ptr.* }),
                            };
                            if (vr.visibility != .public) try self.strings.append(self.allocator, key_str);
                            try arr.set(self.allocator, .{ .string = key_str }, entry.value_ptr.*);
                        }
                        self.push(.{ .array = arr });
                    } else if (v == .null) {
                        const arr = try self.allocator.create(PhpArray);
                        arr.* = .{};
                        try self.arrays.append(self.allocator, arr);
                        self.push(.{ .array = arr });
                    } else {
                        const arr = try self.allocator.create(PhpArray);
                        arr.* = .{};
                        try arr.append(self.allocator, v);
                        try self.arrays.append(self.allocator, arr);
                        self.push(.{ .array = arr });
                    }
                },

                .cast_object => {
                    const v = self.pop();
                    if (v == .object) {
                        self.push(v);
                    } else if (v == .array) {
                        const obj = try self.allocator.create(PhpObject);
                        obj.* = .{ .class_name = "stdClass" };
                        try self.objects.append(self.allocator, obj);
                        for (v.array.entries.items) |entry| {
                            const key_str: []const u8 = switch (entry.key) {
                                .string => |s| s,
                                .int => |i| blk: {
                                    const s = try std.fmt.allocPrint(self.allocator, "{d}", .{i});
                                    try self.strings.append(self.allocator, s);
                                    break :blk s;
                                },
                            };
                            try obj.set(self.allocator, key_str, entry.value);
                        }
                        self.push(.{ .object = obj });
                    } else if (v == .null) {
                        const obj = try self.allocator.create(PhpObject);
                        obj.* = .{ .class_name = "stdClass" };
                        try self.objects.append(self.allocator, obj);
                        self.push(.{ .object = obj });
                    } else {
                        const obj = try self.allocator.create(PhpObject);
                        obj.* = .{ .class_name = "stdClass" };
                        try self.objects.append(self.allocator, obj);
                        try obj.set(self.allocator, "scalar", v);
                        self.push(.{ .object = obj });
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
                    const local_val = self.getLocalByName(var_name);
                    const val = if (self.currentFrame().ref_slots.get(var_name)) |cell|
                        cell.*
                    else if (local_val != .null)
                        local_val
                    else if (self.currentFrame().vars.get(var_name)) |v|
                        v
                    else
                        .null;
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
                    // closures defined inside class methods inherit class scope
                    if (std.mem.eql(u8, var_name, "$this") and val == .object) {
                        try self.captures.append(self.allocator, .{
                            .closure_name = closure_name,
                            .var_name = "$__closure_scope",
                            .value = .{ .string = val.object.class_name },
                        });
                        const gop2 = try self.capture_index.getOrPut(self.allocator, closure_name);
                        gop2.value_ptr.len += 1;
                    } else if (!gop.found_existing) {
                        // first capture for this closure - check if we're in a static class method
                        const scope = self.currentFrame().called_class orelse self.currentDefiningClass();
                        if (scope) |class_name| {
                            try self.captures.append(self.allocator, .{
                                .closure_name = closure_name,
                                .var_name = "$__closure_scope",
                                .value = .{ .string = class_name },
                            });
                            const gop2 = try self.capture_index.getOrPut(self.allocator, closure_name);
                            gop2.value_ptr.len += 1;
                        }
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
                    // if finally was triggered by a propagating exception and that
                    // exception is still on the stack below this throw, chain it
                    // as `previous` to match PHP's exception chaining behavior
                    if (exception == .object and self.sp > 0) {
                        const below = self.stack[self.sp - 1];
                        if (below == .object and self.isInstanceOf(below.object.class_name, "Throwable")) {
                            const prev = exception.object.get("previous");
                            if (prev == .null and below.object != exception.object) {
                                try exception.object.set(self.allocator, "previous", below);
                                _ = self.pop();
                            }
                        }
                    }
                    if (self.handler_count <= self.handler_floor) {
                        self.pending_exception = exception;
                        return error.RuntimeError;
                    }

                    const handler = self.exception_handlers[self.handler_count - 1];

                    // handler belongs to an outer runLoop - propagate up
                    if (handler.frame_count <= base_frame and base_frame > 0) {
                        self.pending_exception = exception;
                        return error.RuntimeError;
                    }

                    self.handler_count -= 1;

                    // unwind frames back to where handler was set
                    while (self.frame_count > handler.frame_count) {
                        self.frame_count -= 1;
                        self.deinitFrameSlot(self.frame_count);
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
                    // resolve or allocate the shared cell. picks up the current
                    // value from the top-frame's view (locals + ref_slots + vars
                    // + constants) so this is the first read after a value was
                    // set there
                    var cell = self.globals_cells.get(name);
                    if (cell == null) {
                        const initial: Value = blk: {
                            if (self.frames[0].ref_slots.get(name)) |c| break :blk c.*;
                            for (self.top_slot_names, 0..) |sn, i| {
                                if (std.mem.eql(u8, sn, name) and i < self.frames[0].locals.len) {
                                    const v = self.frames[0].locals[i];
                                    if (v != .null) break :blk v;
                                }
                            }
                            if (self.frames[0].vars.get(name)) |v| break :blk v;
                            if (self.php_constants.get(name)) |v| break :blk v;
                            break :blk .null;
                        };
                        const c = try self.allocator.create(Value);
                        c.* = initial;
                        const owned = try self.allocator.dupe(u8, name);
                        try self.strings.append(self.allocator, owned);
                        try self.globals_cells.put(self.allocator, owned, c);
                        cell = c;
                    }
                    // bind the local name to the cell so set_var/get_var on this
                    // frame routes through ref_slots and stays in sync across
                    // recursive calls. also point the top frame at the cell so
                    // top-level reads of $name pick up writes done by function
                    // frames sharing the cell
                    try self.currentFrame().ref_slots.put(self.allocator, name, cell.?);
                    try self.currentFrame().vars.put(self.allocator, name, cell.?.*);
                    if (self.frame_count > 1) {
                        try self.frames[0].ref_slots.put(self.allocator, name, cell.?);
                    }
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
                    // share a heap cell across all frames running the same function so
                    // recursive calls and across-call state stay in sync (matches PHP's
                    // static variable semantics).
                    const func_name = self.currentFuncName() orelse "__main__";
                    var key_buf: [256]u8 = undefined;
                    const key = std.fmt.bufPrint(&key_buf, "{s}::{s}", .{ func_name, var_name }) catch "";
                    var cell = self.statics_cells.get(key);
                    if (cell == null) {
                        const c = try self.allocator.create(Value);
                        c.* = self.statics.get(key) orelse .null;
                        const owned_key = try self.allocator.dupe(u8, key);
                        try self.strings.append(self.allocator, owned_key);
                        try self.statics_cells.put(self.allocator, owned_key, c);
                        cell = c;
                    }
                    self.push(cell.?.*);
                    // bind var_name as a true reference to the shared cell
                    try self.currentFrame().ref_slots.put(self.allocator, var_name, cell.?);
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
                            const from_cache = self.serve_mode and self.serve_compile_cache.contains(path);
                            const result: ?*CompileResult = if (from_cache)
                                self.serve_compile_cache.get(path).?
                            else if (self.file_loader) |loader|
                                loader(path, self.allocator, self)
                            else
                                null;

                            if (result) |r| {
                                if (self.serve_mode and !from_cache) {
                                    const duped = try self.allocator.dupe(u8, path);
                                    try self.serve_cache_keys.append(self.allocator, duped);
                                    try self.serve_compile_cache.put(self.allocator, duped, r);
                                }
                                try self.loaded_files.put(self.allocator, path, {});
                                if (!from_cache) {
                                    try self.compile_results.append(self.allocator, r);
                                }

                                for (r.functions.items) |*func| {
                                    try self.registerFunction(func);
                                }
                                for (r.type_hints.items) |th| {
                                    try g_type_info.put(self.allocator, th.name, .{ .param_types = th.param_types, .return_type = th.return_type });
                                }

                                const return_frame = self.frame_count;
                                if (self.frame_count >= 2047) {
                                    self.error_msg = "Fatal error: maximum call stack depth exceeded";
                                    return error.RuntimeError;
                                }
                                const sp_before = self.sp;
                                var req_locals: []Value = &.{};
                                if (r.local_count > 0) {
                                    req_locals = try self.allocator.alloc(Value, r.local_count);
                                    @memset(req_locals, .null);
                                }
                                var inherited_vars: @TypeOf(self.frames[0].vars) = .{};
                                const caller = self.currentFrame();
                                if (caller.vars.count() > 0) {
                                    var vit = caller.vars.iterator();
                                    while (vit.next()) |entry| {
                                        try inherited_vars.put(self.allocator, entry.key_ptr.*, entry.value_ptr.*);
                                    }
                                }
                                const caller_sn = if (caller.func) |func| func.slot_names else self.global_slot_names;
                                for (caller_sn, 0..) |csn, ci| {
                                    if (ci < caller.locals.len and csn.len > 0) {
                                        const cval = caller.locals[ci];
                                        if (cval != .null and !inherited_vars.contains(csn)) {
                                            try inherited_vars.put(self.allocator, csn, cval);
                                        }
                                    }
                                }
                                const saved_slot_names = self.global_slot_names;
                                self.global_slot_names = r.slot_names;
                                const saved_strict = self.script_strict_types;
                                self.script_strict_types = r.strict_types;
                                self.frames[self.frame_count] = .{
                                    .chunk = &r.chunk,
                                    .ip = 0,
                                    .vars = inherited_vars,
                                    .locals = req_locals,
                                    .script_path = r.file_path,
                                };
                                self.frames[self.frame_count].entry_sp = self.sp;
                                self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
                                const saved_merge_depth = self.require_merge_depth;
                                self.require_merge_depth = self.frame_count;
                                self.runUntilFrame(return_frame) catch {
                                    self.require_merge_depth = saved_merge_depth;
                                    while (self.frame_count > return_frame) {
                                        self.frame_count -= 1;
                                        self.deinitFrameSlot(self.frame_count);
                                    }
                                    self.global_slot_names = saved_slot_names;
                                self.script_strict_types = saved_strict;

                                    if (self.pending_exception) |exc| {
                                        if (self.handler_count > self.handler_floor) {
                                            const handler = self.exception_handlers[self.handler_count - 1];
                                            if (handler.frame_count > base_frame or base_frame == 0) {
                                                self.pending_exception = null;
                                                self.handler_count -= 1;
                                                while (self.frame_count > handler.frame_count) {
                                                    self.frame_count -= 1;
                                                    self.deinitFrameSlot(self.frame_count);
                                                }
                                                self.sp = handler.sp;
                                                self.push(exc);
                                                self.currentFrame().ip = handler.catch_ip;
                                                continue;
                                            }
                                        }
                                    }

                                    if (is_require) {
                                        if (self.error_msg == null and self.pending_exception == null) {
                                            self.setErrorMsg("Fatal error: require(): Failed opening required '{s}'", .{path});
                                        }
                                        return error.RuntimeError;
                                    }
                                    self.push(.{ .bool = false });
                                    continue;
                                };
                                // merge top-level variable assignments from the
                                // included file back into the caller's scope.
                                // PHP semantics: vars defined at the top level
                                // of an included script become locals/globals
                                // in the requiring scope. without this, files
                                // that rely on `$x = ...; require 'helper.php';`
                                // patterns (WordPress, legacy frameworks) fail
                                // to pick up state set by the include
                                // the include frame lives at return_frame (its slot
                                // when pushed). popFrame leaves it intact when popping
                                // back to require_merge_depth, so we can read its
                                // vars/locals here even after an explicit `return`
                                const include_frame_idx = return_frame;
                                const include_frame = &self.frames[include_frame_idx];
                                const include_slot_names = r.slot_names;
                                // 1) merge slot-backed locals
                                for (include_slot_names, 0..) |name, si| {
                                    if (name.len == 0) continue;
                                    if (si >= include_frame.locals.len) continue;
                                    const v = include_frame.locals[si];
                                    if (v == .null) continue;
                                    // find a matching slot in the caller
                                    var caller_slot: ?usize = null;
                                    for (caller_sn, 0..) |csn, ci| {
                                        if (std.mem.eql(u8, csn, name)) { caller_slot = ci; break; }
                                    }
                                    if (caller_slot) |cs| {
                                        if (cs < caller.locals.len) caller.locals[cs] = v;
                                    } else {
                                        try caller.vars.put(self.allocator, name, v);
                                    }
                                }
                                // 2) merge dynamically-stored vars
                                var iter_vars = include_frame.vars.iterator();
                                while (iter_vars.next()) |entry| {
                                    const name = entry.key_ptr.*;
                                    if (name.len == 0) continue;
                                    // skip framework-internal keys (start with __)
                                    if (name.len >= 3 and name[0] == '$' and name[1] == '_' and name[2] == '_') continue;
                                    var caller_slot: ?usize = null;
                                    for (caller_sn, 0..) |csn, ci| {
                                        if (std.mem.eql(u8, csn, name)) { caller_slot = ci; break; }
                                    }
                                    if (caller_slot) |cs| {
                                        if (cs < caller.locals.len) caller.locals[cs] = entry.value_ptr.*;
                                    } else {
                                        try caller.vars.put(self.allocator, name, entry.value_ptr.*);
                                    }
                                }
                                while (self.frame_count > return_frame) {
                                    self.frame_count -= 1;
                                    self.deinitFrameSlot(self.frame_count);
                                }
                                // popFrame at require_merge_depth left this slot
                                // intact for the merge above; deinit it now
                                self.deinitFrameSlot(return_frame);
                                self.require_merge_depth = saved_merge_depth;
                                self.global_slot_names = saved_slot_names;
                                self.script_strict_types = saved_strict;
                                if (self.sp <= sp_before) self.push(.{ .bool = true });
                            } else {
                                if (is_require) {
                                    self.setErrorMsg("Fatal error: require(): Failed opening required '{s}'", .{path});
                                    return error.RuntimeError;
                                }
                                self.push(.{ .bool = false });
                            }
                        }
                    }
                },

                .array_spread => {
                    var src = self.pop();
                    const target = self.peek();
                    if (target != .array) continue;

                    if (src == .object and self.hasMethod(src.object.class_name, "getIterator")) {
                        src = self.callMethod(src.object, "getIterator", &.{}) catch .null;
                    }

                    if (src == .array) {
                        for (src.array.entries.items) |entry| {
                            if (entry.key == .string) {
                                try target.array.set(self.allocator, entry.key, entry.value);
                            } else {
                                try target.array.append(self.allocator, entry.value);
                            }
                        }
                    } else if (src == .generator) {
                        const gen = src.generator;
                        if (gen.state == .created) {
                            self.resumeGenerator(gen, .null) catch {
                                if (self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            };
                        }
                        while (gen.state != .completed) {
                            if (gen.current_key == .string) {
                                try target.array.set(self.allocator, .{ .string = gen.current_key.string }, gen.current_value);
                            } else {
                                try target.array.append(self.allocator, gen.current_value);
                            }
                            self.resumeGenerator(gen, .null) catch {
                                if (self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            };
                        }
                    } else if (src == .object and self.hasMethod(src.object.class_name, "current")) {
                        if (self.hasMethod(src.object.class_name, "rewind")) {
                            _ = self.callMethod(src.object, "rewind", &.{}) catch {};
                        }
                        while (true) {
                            const valid = self.callMethod(src.object, "valid", &.{}) catch Value{ .bool = false };
                            if (!valid.isTruthy()) break;
                            const key = self.callMethod(src.object, "key", &.{}) catch .null;
                            const val = self.callMethod(src.object, "current", &.{}) catch .null;
                            if (key == .string) {
                                try target.array.set(self.allocator, .{ .string = key.string }, val);
                            } else {
                                try target.array.append(self.allocator, val);
                            }
                            _ = self.callMethod(src.object, "next", &.{}) catch {};
                        }
                    }
                },
                .splat_call => {},

                .instance_check => {
                    const class_name_val = self.pop();
                    const obj_val = self.pop();
                    if (obj_val == .object and class_name_val == .string) {
                        self.push(.{ .bool = self.isInstanceOf(obj_val.object.class_name, class_name_val.string) });
                    } else if (obj_val == .generator and class_name_val == .string) {
                        const t = class_name_val.string;
                        const matches = std.mem.eql(u8, t, "Generator") or
                            std.mem.eql(u8, t, "Iterator") or
                            std.mem.eql(u8, t, "Traversable");
                        self.push(.{ .bool = matches });
                    } else if (obj_val == .fiber and class_name_val == .string) {
                        self.push(.{ .bool = std.mem.eql(u8, class_name_val.string, "Fiber") });
                    } else if (obj_val == .string and class_name_val == .string and
                        std.mem.eql(u8, class_name_val.string, "Closure") and
                        std.mem.startsWith(u8, obj_val.string, "__closure_"))
                    {
                        self.push(.{ .bool = true });
                    } else {
                        self.push(.{ .bool = false });
                    }
                },

                .class_decl => try self.handleClassDecl(),

                .interface_decl => {
                    const name_idx = self.readU16();
                    const iface_name = self.currentChunk().constants.items[name_idx].string;
                    const method_count = self.readU16();

                    var idef = InterfaceDef{ .name = iface_name };
                    for (0..method_count) |_| {
                        const mname_idx = self.readU16();
                        const method_name = self.currentChunk().constants.items[mname_idx].string;
                        try idef.methods.append(self.allocator, method_name);
                    }

                    const parent_count = self.readByte();
                    var parent_names: [16][]const u8 = undefined;
                    for (0..parent_count) |pi| {
                        const pidx = self.readU16();
                        parent_names[pi] = self.currentChunk().constants.items[pidx].string;
                        try idef.parents.append(self.allocator, parent_names[pi]);
                    }
                    if (parent_count > 0) {
                        idef.parent = parent_names[0];
                    }

                    const const_count = self.readByte();
                    var def = ClassDef{ .name = iface_name };
                    if (const_count > 0) {
                        var ci: usize = const_count;
                        while (ci > 0) : (ci -= 1) {
                            const cname_idx = self.readU16();
                            const cname = self.currentChunk().constants.items[cname_idx].string;
                            const cval = self.stack[self.sp - ci];
                            try def.static_props.put(self.allocator, cname, cval);
                            try def.constant_names.put(self.allocator, cname, {});
                        }
                        self.sp -= const_count;
                    } else {
                        // read const names even when 0 (shouldn't have any)
                    }
                    for (0..parent_count) |pi| {
                        try def.interfaces.append(self.allocator, parent_names[pi]);
                    }

                    // interface-level attributes
                    const iface_attrs = try self.readAttributeDefs();
                    for (iface_attrs) |a| try def.attributes.append(self.allocator, a);
                    if (iface_attrs.len > 0) self.allocator.free(iface_attrs);

                    // method attributes
                    const iface_method_attr_count = self.readByte();
                    for (0..iface_method_attr_count) |_| {
                        const ma_name_idx = self.readU16();
                        const ma_name = self.currentChunk().constants.items[ma_name_idx].string;
                        const ma_attrs = try self.readAttributeDefs();
                        try def.method_attributes.put(self.allocator, ma_name, ma_attrs);
                    }

                    if (self.classes.fetchRemove(iface_name)) |old| {
                        var od = old.value;
                        od.deinit(self.allocator);
                    }
                    if (self.interfaces.fetchRemove(iface_name)) |old| {
                        var oi = old.value;
                        oi.deinit(self.allocator);
                    }
                    try self.classes.put(self.allocator, iface_name, def);
                    try self.interfaces.put(self.allocator, iface_name, idef);
                },

                .trait_decl => {
                    const name_idx = self.readU16();
                    const trait_name = self.currentChunk().constants.items[name_idx].string;
                    try self.traits.put(self.allocator, trait_name, {});
                    const sub_count = self.readByte();
                    if (sub_count > 0) {
                        const subs = try self.allocator.alloc([]const u8, sub_count);
                        for (0..sub_count) |i| {
                            const si = self.readU16();
                            subs[i] = self.currentChunk().constants.items[si].string;
                        }
                        try self.trait_uses.put(self.allocator, trait_name, subs);
                    }
                    const tp_count = self.readByte();
                    if (tp_count > 0) {
                        var tp_names: [32][]const u8 = undefined;
                        var tp_has_default: [32]u8 = undefined;
                        var tp_vis: [32]ClassDef.Visibility = undefined;
                        for (0..tp_count) |pi| {
                            tp_names[pi] = self.currentChunk().constants.items[self.readU16()].string;
                            tp_has_default[pi] = self.readByte();
                            const vis_byte = self.readByte();
                            tp_vis[pi] = @enumFromInt(vis_byte & 0x03);
                        }
                        const tp_defaults = self.popDefaults(32, tp_has_default[0..tp_count]);
                        const props = try self.allocator.alloc(ClassDef.PropertyDef, tp_count);
                        var dj: usize = 0;
                        for (0..tp_count) |pi| {
                            const dval = if (tp_has_default[pi] == 1) blk: {
                                const v = tp_defaults[dj];
                                dj += 1;
                                break :blk v;
                            } else Value{ .null = {} };
                            props[pi] = .{ .name = tp_names[pi], .default = dval, .visibility = tp_vis[pi] };
                        }
                        try self.trait_props.put(self.allocator, trait_name, props);
                    }
                    const sp_count = self.readByte();
                    if (sp_count > 0) {
                        var sp_names: [32][]const u8 = undefined;
                        var sp_has_default: [32]u8 = undefined;
                        for (0..sp_count) |pi| {
                            sp_names[pi] = self.currentChunk().constants.items[self.readU16()].string;
                            sp_has_default[pi] = self.readByte();
                            _ = self.readByte(); // visibility
                        }
                        const sp_defaults = self.popDefaults(32, sp_has_default[0..sp_count]);
                        const sprops = try self.allocator.alloc(TraitStaticProp, sp_count);
                        var sj: usize = 0;
                        for (0..sp_count) |pi| {
                            const sval = if (sp_has_default[pi] == 1) blk: {
                                const v = sp_defaults[sj];
                                sj += 1;
                                break :blk v;
                            } else Value{ .null = {} };
                            sprops[pi] = .{ .name = sp_names[pi], .value = sval };
                        }
                        try self.trait_static_props.put(self.allocator, trait_name, sprops);
                    }

                    // trait constants (PHP 8.2+)
                    const tc_count = self.readByte();
                    if (tc_count > 0) {
                        var tc_names: [32][]const u8 = undefined;
                        var tc_has_default: [32]u8 = undefined;
                        for (0..tc_count) |ci| {
                            tc_names[ci] = self.currentChunk().constants.items[self.readU16()].string;
                            tc_has_default[ci] = self.readByte();
                        }
                        const tc_defaults = self.popDefaults(32, tc_has_default[0..tc_count]);
                        const tcs = try self.allocator.alloc(TraitStaticProp, tc_count);
                        var tcj: usize = 0;
                        for (0..tc_count) |ci| {
                            const cval = if (tc_has_default[ci] == 1) blk: {
                                const v = tc_defaults[tcj];
                                tcj += 1;
                                break :blk v;
                            } else Value{ .null = {} };
                            tcs[ci] = .{ .name = tc_names[ci], .value = cval };
                        }
                        try self.trait_constants.put(self.allocator, trait_name, tcs);
                    }

                    // trait-level attributes
                    const trait_attrs = try self.readAttributeDefs();
                    const trait_method_attr_count = self.readByte();
                    var trait_method_attrs: [32]struct { name: []const u8, attrs: []const AttributeDef } = undefined;
                    for (0..trait_method_attr_count) |tmi| {
                        const tma_name_idx = self.readU16();
                        const tma_name = self.currentChunk().constants.items[tma_name_idx].string;
                        const tma_attrs = try self.readAttributeDefs();
                        trait_method_attrs[tmi] = .{ .name = tma_name, .attrs = tma_attrs };
                    }
                    const trait_prop_attr_count = self.readByte();
                    var trait_prop_attrs: [32]struct { name: []const u8, attrs: []const AttributeDef } = undefined;
                    for (0..trait_prop_attr_count) |tpi| {
                        const tpa_name_idx = self.readU16();
                        const tpa_name = self.currentChunk().constants.items[tpa_name_idx].string;
                        const tpa_attrs = try self.readAttributeDefs();
                        trait_prop_attrs[tpi] = .{ .name = tpa_name, .attrs = tpa_attrs };
                    }

                    if (trait_attrs.len > 0 or trait_method_attr_count > 0 or trait_prop_attr_count > 0) {
                        var tdef = ClassDef{ .name = trait_name };
                        for (trait_attrs) |a| try tdef.attributes.append(self.allocator, a);
                        if (trait_attrs.len > 0) self.allocator.free(trait_attrs);
                        for (0..trait_method_attr_count) |tmi| {
                            try tdef.method_attributes.put(self.allocator, trait_method_attrs[tmi].name, trait_method_attrs[tmi].attrs);
                        }
                        for (0..trait_prop_attr_count) |tpi| {
                            try tdef.property_attributes.put(self.allocator, trait_prop_attrs[tpi].name, trait_prop_attrs[tpi].attrs);
                        }
                        try self.classes.put(self.allocator, trait_name, tdef);
                    } else {
                        if (trait_attrs.len > 0) self.allocator.free(trait_attrs);
                    }
                },

                .enum_decl => try self.handleEnumDecl(),

                .new_obj => {
                    const name_idx = self.readU16();
                    var arg_count = self.readByte();
                    // 0xFF signals spread args: top of stack is an array to unpack
                    if (arg_count == 0xFF) {
                        const arr_val = self.pop();
                        if (arr_val == .array) {
                            const entries = arr_val.array.entries.items;
                            var has_named = false;
                            for (entries) |entry| {
                                if (entry.key == .string) { has_named = true; break; }
                            }
                            if (has_named) {
                                // resolve class name early to look up constructor params
                                var cn = self.currentChunk().constants.items[name_idx].string;
                                if (std.mem.eql(u8, cn, "static")) cn = self.resolveStaticClassName(cn)
                                else if (std.mem.eql(u8, cn, "self")) { if (self.currentDefiningClass()) |dc| cn = dc; }
                                else if (std.mem.eql(u8, cn, "parent")) { if (self.parentResolvingClass()) |dc| { if (self.classes.get(dc)) |cls| { if (cls.parent) |p| cn = p; } } }
                                const ctor_name = self.resolveMethod(cn, "__construct") catch null;
                                if (ctor_name) |ctn| {
                                    if (self.functions.get(ctn)) |func| {
                                        var resolved: [16]Value = .{.null} ** 16;
                                        var pos: usize = 0;
                                        for (entries) |entry| {
                                            if (entry.key == .string) {
                                                for (func.params, 0..) |p, pi| {
                                                    const pname = if (p.len > 0 and p[0] == '$') p[1..] else p;
                                                    if (std.mem.eql(u8, pname, entry.key.string) or std.mem.eql(u8, p, entry.key.string)) {
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
                                        const count = @max(pos, func.required_params);
                                        for (0..count) |i| {
                                            if (resolved[i] == .null and i < func.defaults.len) {
                                                resolved[i] = try self.resolveDefault(func.defaults[i]);
                                            }
                                        }
                                        for (0..count) |i| self.push(resolved[i]);
                                        arg_count = @intCast(count);
                                    } else {
                                        for (entries) |entry| self.push(entry.value);
                                        arg_count = @intCast(entries.len);
                                    }
                                } else {
                                    for (entries) |entry| self.push(entry.value);
                                    arg_count = @intCast(entries.len);
                                }
                            } else {
                                for (entries) |entry| self.push(entry.value);
                                arg_count = @intCast(entries.len);
                            }
                        } else {
                            arg_count = 0;
                        }
                    }
                    var class_name = self.currentChunk().constants.items[name_idx].string;
                    if (std.mem.eql(u8, class_name, "static")) {
                        class_name = self.resolveStaticClassName(class_name);
                    } else if (std.mem.eql(u8, class_name, "self")) {
                        if (self.currentDefiningClass()) |dc| class_name = dc;
                    } else if (std.mem.eql(u8, class_name, "parent")) {
                        if (self.parentResolvingClass()) |dc| {
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
                    if (self.interfaces.contains(class_name)) {
                        const ac_drop: usize = arg_count;
                        self.sp -= ac_drop;
                        const msg = try std.fmt.allocPrint(self.allocator, "Cannot instantiate interface {s}", .{class_name});
                        try self.strings.append(self.allocator, msg);
                        if (try self.throwBuiltinException("Error", msg)) continue;
                        return error.RuntimeError;
                    }
                    if (!self.classes.contains(class_name)) {
                        const ac_drop: usize = arg_count;
                        self.sp -= ac_drop;
                        const msg = try std.fmt.allocPrint(self.allocator, "Class \"{s}\" not found", .{class_name});
                        try self.strings.append(self.allocator, msg);
                        if (try self.throwBuiltinException("Error", msg)) continue;
                        return error.RuntimeError;
                    }
                    if (self.classes.get(class_name)) |cls_ref| {
                        if (cls_ref.is_abstract) {
                            const ac_drop: usize = arg_count;
                            self.sp -= ac_drop;
                            const msg = try std.fmt.allocPrint(self.allocator, "Cannot instantiate abstract class {s}", .{class_name});
                            try self.strings.append(self.allocator, msg);
                            if (try self.throwBuiltinException("Error", msg)) continue;
                            return error.RuntimeError;
                        }
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
                            self.frames[self.frame_count].entry_sp = self.sp;
                    self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;

                            const saved_fc = self.frame_count;
                            var ctx = self.makeContext(null);
                            _ = native(&ctx, args_buf[0..ac]) catch {
                                // clean up temp frame if throwBuiltinException didn't already unwind past it
                                if (self.frame_count >= saved_fc) {
                                    self.frame_count -= 1;
                                    self.deinitFrameSlot(self.frame_count);
                                }
                                if (self.pending_exception) |exc| {
                                    self.pending_exception = null;
                                    if (self.handler_count > self.handler_floor) {
                                        const handler = self.exception_handlers[self.handler_count - 1];
                                        self.handler_count -= 1;
                                        while (self.frame_count > handler.frame_count) {
                                            self.frame_count -= 1;
                                            self.deinitFrameSlot(self.frame_count);
                                        }
                                        self.sp = handler.sp;
                                        self.push(exc);
                                        self.currentFrame().ip = handler.catch_ip;
                                        continue;
                                    }
                                    self.pending_exception = exc;
                                } else {
                                    // throwBuiltinException already dispatched to handler
                                    continue;
                                }
                                return error.RuntimeError;
                            };

                            self.frame_count -= 1;
                            self.deinitFrameSlot(self.frame_count);
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
                                if (func.is_variadic) {
                                    const fixed: usize = func.arity - 1;
                                    for (0..@min(ac, fixed)) |i| {
                                        ctor_locals[i + 1] = self.stack[self.sp - ac + i];
                                    }
                                    for (@min(ac, fixed)..fixed) |i| {
                                        if (i < func.defaults.len) ctor_locals[i + 1] = try self.resolveDefault(func.defaults[i]);
                                    }
                                    const rest_arr = try self.allocator.create(PhpArray);
                                    rest_arr.* = .{};
                                    try self.arrays.append(self.allocator, rest_arr);
                                    if (ac > fixed) {
                                        for (fixed..ac) |i| {
                                            try rest_arr.append(self.allocator, self.stack[self.sp - ac + i]);
                                        }
                                    }
                                    ctor_locals[fixed + 1] = .{ .array = rest_arr };
                                } else {
                                    for (0..@min(ac, func.arity)) |i| {
                                        ctor_locals[i + 1] = self.stack[self.sp - ac + i];
                                    }
                                    for (@min(ac, func.arity)..func.arity) |i| {
                                        if (i < func.defaults.len) ctor_locals[i + 1] = try self.resolveDefault(func.defaults[i]);
                                    }
                                }
                                self.sp -= ac;
                                self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = .{}, .locals = ctor_locals, .func = func };
                                self.frames[self.frame_count].entry_sp = self.sp;
                    self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
                                self.exception_dispatched = false;
                                try self.fastLoop();
                                const ctor_frame = &self.frames[self.frame_count - 1];
                                if (ctor_frame.chunk == &func.chunk) {
                                    const ctor_base = self.frame_count - 1;
                                    try self.runUntilFrame(ctor_base);
                                    if (self.exception_dispatched) {
                                        self.exception_dispatched = false;
                                        continue;
                                    }
                                }
                                _ = self.pop();
                            } else {
                                var new_vars: std.StringHashMapUnmanaged(Value) = .{};
                                try new_vars.put(self.allocator, "$this", .{ .object = obj });
                                if (func.is_variadic) {
                                    const fixed: usize = func.arity - 1;
                                    for (0..@min(ac, fixed)) |i| {
                                        try new_vars.put(self.allocator, func.params[i], self.stack[self.sp - ac + i]);
                                    }
                                    for (@min(ac, fixed)..fixed) |i| {
                                        if (i < func.defaults.len) try new_vars.put(self.allocator, func.params[i], try self.resolveDefault(func.defaults[i]));
                                    }
                                    const rest_arr = try self.allocator.create(PhpArray);
                                    rest_arr.* = .{};
                                    try self.arrays.append(self.allocator, rest_arr);
                                    if (ac > fixed) {
                                        for (fixed..ac) |i| {
                                            try rest_arr.append(self.allocator, self.stack[self.sp - ac + i]);
                                        }
                                    }
                                    try new_vars.put(self.allocator, func.params[func.arity - 1], .{ .array = rest_arr });
                                } else {
                                    const copy_count = @min(ac, func.params.len);
                                    for (0..copy_count) |i| {
                                        try new_vars.put(self.allocator, func.params[i], self.stack[self.sp - ac + i]);
                                    }
                                }
                                self.sp -= ac;
                                if (!func.is_variadic and ac < func.arity) for (ac..func.arity) |i| {
                                    const default = if (i < func.defaults.len) try self.resolveDefault(func.defaults[i]) else Value.null;
                                    try new_vars.put(self.allocator, func.params[i], default);
                                };
                                self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars, .locals = try self.allocLocals(func, &new_vars), .func = func };
                                self.frames[self.frame_count].entry_sp = self.sp;
                    self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
                                self.exception_dispatched = false;
                                const ctor_base = self.frame_count - 1;
                                try self.runUntilFrame(ctor_base);
                                if (self.exception_dispatched) {
                                    self.exception_dispatched = false;
                                    continue;
                                }
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

                .new_obj_dynamic => {
                    var arg_count = self.readByte();
                    // 0xFF signals spread args: top of stack is an array to unpack
                    if (arg_count == 0xFF) {
                        const arr_val = self.pop();
                        if (arr_val == .array) {
                            const entries = arr_val.array.entries.items;
                            for (entries) |entry| self.push(entry.value);
                            arg_count = @intCast(entries.len);
                        } else {
                            arg_count = 0;
                        }
                    }
                    const ac: usize = arg_count;
                    const name_val = self.stack[self.sp - ac - 1];
                    const raw_class_name = if (name_val == .string) name_val.string else if (name_val == .object) name_val.object.class_name else {
                        self.setErrorMsg("Fatal error: Class name must be a valid object or a string", .{});
                        return error.RuntimeError;
                    };
                    // strip leading backslash from fully-qualified class names
                    const class_name = if (raw_class_name.len > 0 and raw_class_name[0] == '\\') raw_class_name[1..] else raw_class_name;
                    if (!self.classes.contains(class_name)) try self.tryAutoload(class_name);
                    if (!self.classes.contains(class_name)) {
                        self.sp -= ac + 1;
                        const msg = try std.fmt.allocPrint(self.allocator, "Class \"{s}\" not found", .{class_name});
                        try self.strings.append(self.allocator, msg);
                        if (try self.throwBuiltinException("Error", msg)) continue;
                        return error.RuntimeError;
                    }

                    const obj = try self.allocator.create(PhpObject);
                    obj.* = .{ .class_name = class_name };
                    try self.objects.append(self.allocator, obj);
                    try self.initObjectProperties(obj, class_name);

                    const ctor_name = self.resolveMethod(class_name, "__construct") catch null;
                    if (ctor_name) |cn| {
                        if (self.native_fns.get(cn)) |native| {
                            var args_buf: [16]Value = undefined;
                            for (0..ac) |i| args_buf[i] = self.stack[self.sp - ac + i];
                            self.sp -= ac + 1;
                            var tmp_vars: std.StringHashMapUnmanaged(Value) = .{};
                            try tmp_vars.put(self.allocator, "$this", .{ .object = obj });
                            self.frames[self.frame_count] = .{ .chunk = self.currentChunk(), .ip = self.currentFrame().ip, .vars = tmp_vars };
                            self.frames[self.frame_count].entry_sp = self.sp;
                    self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
                            var ctx = self.makeContext(null);
                            _ = native(&ctx, args_buf[0..ac]) catch {
                                self.frame_count -= 1;
                                self.deinitFrameSlot(self.frame_count);
                                if (self.pending_exception) |exc| {
                                    self.pending_exception = null;
                                    if (self.handler_count > self.handler_floor) {
                                        const handler = self.exception_handlers[self.handler_count - 1];
                                        self.handler_count -= 1;
                                        while (self.frame_count > handler.frame_count) {
                                            self.frame_count -= 1;
                                            self.deinitFrameSlot(self.frame_count);
                                        }
                                        self.sp = handler.sp;
                                        self.push(exc);
                                        self.currentFrame().ip = handler.catch_ip;
                                        continue;
                                    }
                                    self.pending_exception = exc;
                                } else {
                                    continue;
                                }
                                return error.RuntimeError;
                            };
                            self.frame_count -= 1;
                            self.deinitFrameSlot(self.frame_count);
                        } else if (self.functions.get(cn)) |func| {
                            var new_vars: std.StringHashMapUnmanaged(Value) = .{};
                            try new_vars.put(self.allocator, "$this", .{ .object = obj });
                            for (0..@min(ac, func.arity)) |i| {
                                try new_vars.put(self.allocator, func.params[i], self.stack[self.sp - ac + i]);
                            }
                            self.sp -= ac + 1;
                            for (@min(ac, func.arity)..func.arity) |i| {
                                const default = if (i < func.defaults.len) try self.resolveDefault(func.defaults[i]) else Value.null;
                                try new_vars.put(self.allocator, func.params[i], default);
                            }
                            self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars, .locals = try self.allocLocals(func, &new_vars), .func = func };
                            self.frames[self.frame_count].entry_sp = self.sp;
                    self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
                            self.exception_dispatched = false;
                            const ctor_base = self.frame_count - 1;
                            try self.runUntilFrame(ctor_base);
                            if (self.exception_dispatched) {
                                self.exception_dispatched = false;
                                continue;
                            }
                            _ = self.pop();
                        } else {
                            self.sp -= ac + 1;
                        }
                    } else {
                        self.sp -= ac + 1;
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

                        if (obj.lazy_initializer != .null) try self.triggerLazyInit(obj);

                        // property hooks: dispatch to get hook if present (and not recursing).
                        // route exceptions through the local try/catch handler
                        if (self.hasPropHook(obj.class_name, prop_name, .get) and !self.inPropHook(obj, prop_name)) {
                            const hook_result = self.callPropHook(obj, prop_name, .get, .null) catch {
                                if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            };
                            if (hook_result) |hv| {
                                self.push(hv);
                                continue;
                            }
                        }

                        // IC: slot-indexed fast path. skip the cache when the
                        // property was explicitly unset - the slot still holds
                        // a value, but we need to fall through to __get
                        if (self.ic) |ic| {
                            const gp_idx = InlineCache.propIndex(@intFromPtr(self.currentChunk()), gp_ip);
                            const gp_entry = &ic.prop[gp_idx];
                            const gp_chunk_key = @intFromPtr(self.currentChunk());
                            if (gp_entry.key == gp_ip and gp_entry.chunk_key == gp_chunk_key and gp_entry.class_ptr == @intFromPtr(obj.class_name.ptr) and !obj.isUnset(prop_name)) {
                                if (gp_entry.slot_index != 0xFFFF) {
                                    if (obj.slots) |s| {
                                        const ic_val = s[gp_entry.slot_index];
                                        self.push(ic_val);
                                        continue;
                                    }
                                }
                                self.push(obj.get(prop_name));
                                continue;
                            }
                        }

                        const val = obj.get(prop_name);
                        // if the property was explicitly unset, treat it as
                        // absent so __get fires
                        const is_present = !obj.isUnset(prop_name) and
                            (val != .null or obj.properties.contains(prop_name) or
                             (obj.slots != null and obj.getSlotIndex(prop_name) != null));
                        if (is_present) {
                            const vr = self.findPropertyVisibility(obj.class_name, prop_name);
                            if (!self.checkVisibility(vr.defining_class, vr.visibility)) {
                                if (self.hasMethod(obj.class_name, "__get")) {
                                    const result = try self.callMagicGet(obj, prop_name);
                                    self.push(result);
                                    continue;
                                }
                                // private members of a parent class are invisible to subclasses:
                                // PHP treats access as "undefined property" rather than a fatal error.
                                if (vr.visibility == .private) {
                                    const scope = self.currentFrame().called_class orelse self.currentDefiningClass();
                                    if (scope) |sc| {
                                        if (!std.mem.eql(u8, sc, vr.defining_class) and self.isInstanceOf(sc, vr.defining_class)) {
                                            self.push(.null);
                                            continue;
                                        }
                                    }
                                }
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
                            const result = try self.callMagicGet(obj, prop_name);
                            self.push(result);
                        } else {
                            self.push(.null);
                        }
                    } else {
                        self.push(.null);
                    }
                },

                .get_prop_dynamic => {
                    const prop_name_val = self.pop();
                    const obj_val = self.pop();
                    if (obj_val == .object and prop_name_val == .string) {
                        const obj = obj_val.object;
                        const prop_name = prop_name_val.string;
                        const val = obj.get(prop_name);
                        if (val != .null or obj.properties.contains(prop_name) or (obj.slots != null and obj.getSlotIndex(prop_name) != null)) {
                            self.push(val);
                        } else if (self.hasMethod(obj.class_name, "__get")) {
                            const result = try self.callMagicGet(obj, prop_name);
                            self.push(result);
                        } else {
                            self.push(.null);
                        }
                    } else {
                        self.push(.null);
                    }
                },

                .set_prop_dynamic => {
                    const prop_name_val = self.pop();
                    const new_val = try self.copyValue(self.pop());
                    const obj_val = self.pop();
                    if (obj_val == .object and prop_name_val == .string) {
                        const obj = obj_val.object;
                        const prop_name = prop_name_val.string;
                        const has_prop = obj.properties.contains(prop_name) or (obj.slots != null and obj.getSlotIndex(prop_name) != null);
                        if (!has_prop and self.hasMethod(obj.class_name, "__set") and !obj.magic_set_active.contains(prop_name)) {
                            try obj.magic_set_active.put(self.allocator, prop_name, {});
                            _ = self.callMethod(obj, "__set", &.{ .{ .string = prop_name }, new_val }) catch {};
                            _ = obj.magic_set_active.remove(prop_name);
                        } else {
                            try obj.set(self.allocator, prop_name, new_val);
                        }
                    }
                    self.push(new_val);
                },

                .set_prop => {
                    const sp_ip = self.currentFrame().ip;
                    const name_idx = self.readU16();
                    const prop_name = self.currentChunk().constants.items[name_idx].string;
                    const val = try self.copyValue(self.pop());
                    const obj_val = self.pop();
                    if (obj_val == .object) {
                        const obj = obj_val.object;

                        if (obj.lazy_initializer != .null) try self.triggerLazyInit(obj);

                        // property hooks: dispatch to set hook if present (and not recursing).
                        // an exception thrown inside the hook must dispatch back into the
                        // caller's try/catch instead of bubbling out of runLoop
                        if (self.hasPropHook(obj.class_name, prop_name, .set) and !self.inPropHook(obj, prop_name)) {
                            const hook_result = self.callPropHook(obj, prop_name, .set, val) catch {
                                if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            };
                            if (hook_result != null) {
                                self.push(val);
                                continue;
                            }
                        } else if (self.hasPropHook(obj.class_name, prop_name, .get) and !self.inPropHook(obj, prop_name)) {
                            // get hook exists but no set hook. PHP allows the
                            // write when the property is "backed" (a default
                            // was declared, in which case there's storage to
                            // write to). purely virtual properties with no
                            // default are read-only
                            const has_default = blk: {
                                var current: ?[]const u8 = obj.class_name;
                                while (current) |cn| {
                                    if (self.classes.get(cn)) |cls_def| {
                                        for (cls_def.properties.items) |p| {
                                            if (std.mem.eql(u8, p.name, prop_name)) break :blk p.has_default;
                                        }
                                        current = cls_def.parent;
                                    } else break;
                                }
                                break :blk false;
                            };
                            if (!has_default) {
                                const msg = std.fmt.allocPrint(self.allocator, "Property {s}::${s} is read-only", .{ obj.class_name, prop_name }) catch return error.RuntimeError;
                                try self.strings.append(self.allocator, msg);
                                if (try self.throwBuiltinException("Error", msg)) continue;
                                return error.RuntimeError;
                            }
                            // fall through to the regular slot/property write
                        }

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
                        if (!has_prop and self.hasMethod(obj.class_name, "__set") and !obj.magic_set_active.contains(prop_name)) {
                            try obj.magic_set_active.put(self.allocator, prop_name, {});
                            _ = self.callMethod(obj, "__set", &.{ .{ .string = prop_name }, val }) catch {};
                            _ = obj.magic_set_active.remove(prop_name);
                        } else {
                            const vr = self.findPropertyVisibility(obj.class_name, prop_name);
                            if (!self.checkVisibility(vr.defining_class, vr.visibility)) {
                                if (self.hasMethod(obj.class_name, "__set") and !obj.magic_set_active.contains(prop_name)) {
                                    try obj.magic_set_active.put(self.allocator, prop_name, {});
                                    _ = self.callMethod(obj, "__set", &.{ .{ .string = prop_name }, val }) catch {};
                                    _ = obj.magic_set_active.remove(prop_name);
                                    self.push(val);
                                    continue;
                                }
                                const msg = try std.fmt.allocPrint(self.allocator, "Cannot access {s} property {s}::${s}", .{
                                    @tagName(vr.visibility), vr.defining_class, prop_name,
                                });
                                try self.strings.append(self.allocator, msg);
                                if (try self.throwBuiltinException("Error", msg)) continue;
                                return error.RuntimeError;
                            }
                            if (vr.set_visibility != vr.visibility and !self.checkVisibility(vr.defining_class, vr.set_visibility)) {
                                if (self.hasMethod(obj.class_name, "__set") and !obj.magic_set_active.contains(prop_name)) {
                                    try obj.magic_set_active.put(self.allocator, prop_name, {});
                                    _ = self.callMethod(obj, "__set", &.{ .{ .string = prop_name }, val }) catch {};
                                    _ = obj.magic_set_active.remove(prop_name);
                                    self.push(val);
                                    continue;
                                }
                                const scope_name = self.currentDefiningClass();
                                const msg = if (scope_name) |sn|
                                    try std.fmt.allocPrint(self.allocator, "Cannot modify {s}(set) property {s}::${s} from scope {s}", .{
                                        @tagName(vr.set_visibility), vr.defining_class, prop_name, sn,
                                    })
                                else
                                    try std.fmt.allocPrint(self.allocator, "Cannot modify {s}(set) property {s}::${s} from global scope", .{
                                        @tagName(vr.set_visibility), vr.defining_class, prop_name,
                                    });
                                try self.strings.append(self.allocator, msg);
                                if (try self.throwBuiltinException("Error", msg)) continue;
                                return error.RuntimeError;
                            }
                            if (vr.is_readonly) {
                                // PHP readonly: the property can be initialized exactly
                                // once, from within the declaring class's scope. a child
                                // class's methods cannot write the parent's readonly
                                // property (the child must redeclare it to get its own
                                // init slot - which zphp doesn't model separately, so
                                // we enforce the declaring-class rule strictly)
                                const existing = obj.get(prop_name);
                                if (existing != .null) {
                                    const scope_is_decl = blk: {
                                        const scope = self.currentDefiningClass() orelse break :blk false;
                                        break :blk std.mem.eql(u8, scope, vr.defining_class);
                                    };
                                    if (!scope_is_decl) {
                                        const msg = try std.fmt.allocPrint(self.allocator, "Cannot modify readonly property {s}::${s}", .{
                                            vr.defining_class, prop_name,
                                        });
                                        try self.strings.append(self.allocator, msg);
                                        if (try self.throwBuiltinException("Error", msg)) continue;
                                        return error.RuntimeError;
                                    }
                                }
                            }
                            try obj.set(self.allocator, prop_name, val);
                            // populate IC for slot-indexed writes
                            if (self.ic) |ic| {
                                if (vr.visibility == .public and vr.set_visibility == .public) {
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

                    if (obj_val == .object and obj_val.object.lazy_initializer != .null) {
                        try self.triggerLazyInit(obj_val.object);
                    }

                    // generator method dispatch
                    if (obj_val == .generator) {
                        const gen = obj_val.generator;
                        self.sp -= ac;
                        self.sp -= 1; // pop generator
                        if (std.mem.eql(u8, method_name, "current")) {
                            // auto-start if not yet started
                            if (gen.state == .created) {
                                self.resumeGenerator(gen, .null) catch {
                                    if (self.dispatchPendingException(base_frame)) continue;
                                    return error.RuntimeError;
                                };
                            }
                            self.push(gen.current_value);
                        } else if (std.mem.eql(u8, method_name, "key")) {
                            if (gen.state == .created) {
                                self.resumeGenerator(gen, .null) catch {
                                    if (self.dispatchPendingException(base_frame)) continue;
                                    return error.RuntimeError;
                                };
                            }
                            self.push(gen.current_key);
                        } else if (std.mem.eql(u8, method_name, "valid")) {
                            if (gen.state == .created) {
                                self.resumeGenerator(gen, .null) catch {
                                    if (self.dispatchPendingException(base_frame)) continue;
                                    return error.RuntimeError;
                                };
                            }
                            self.push(.{ .bool = gen.state != .completed });
                        } else if (std.mem.eql(u8, method_name, "next")) {
                            // next() always advances: if not started, start then advance
                            if (gen.state == .created) {
                                self.resumeGenerator(gen, .null) catch {
                                    if (self.dispatchPendingException(base_frame)) continue;
                                    return error.RuntimeError;
                                };
                            }
                            self.resumeGenerator(gen, .null) catch {
                                if (self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            };
                            self.push(.null);
                        } else if (std.mem.eql(u8, method_name, "send")) {
                            const sent = if (ac > 0) self.stack[self.sp + 1] else Value{ .null = {} };
                            if (gen.state == .created) {
                                self.resumeGenerator(gen, .null) catch {
                                    if (self.dispatchPendingException(base_frame)) continue;
                                    return error.RuntimeError;
                                };
                            }
                            self.resumeGenerator(gen, sent) catch {
                                if (self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            };
                            self.push(if (gen.state == .completed) .null else gen.current_value);
                        } else if (std.mem.eql(u8, method_name, "rewind")) {
                            if (gen.state == .completed or (gen.state == .suspended and gen.ip > 0)) {
                                try self.setPendingException("Exception", "Cannot rewind a generator that was already run");
                                if (self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            }
                            if (gen.state == .created) {
                                self.resumeGenerator(gen, .null) catch {
                                    if (self.dispatchPendingException(base_frame)) continue;
                                    return error.RuntimeError;
                                };
                            }
                            self.push(.null);
                        } else if (std.mem.eql(u8, method_name, "getReturn")) {
                            if (gen.state != .completed) {
                                try self.setPendingException("Exception", "Cannot get return value of a generator that hasn't returned");
                                if (self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            }
                            self.push(gen.return_value);
                        } else if (std.mem.eql(u8, method_name, "throw")) {
                            const ex = if (ac > 0) self.stack[self.sp + 1] else Value{ .null = {} };
                            if (gen.state == .completed) {
                                self.pending_exception = ex;
                                if (self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            }
                            if (gen.state == .created) {
                                self.resumeGenerator(gen, .null) catch {
                                    if (self.dispatchPendingException(base_frame)) continue;
                                    return error.RuntimeError;
                                };
                            }
                            gen.pending_throw = ex;
                            self.resumeGenerator(gen, .null) catch {
                                if (self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            };
                            self.push(if (gen.state == .completed) .null else gen.current_value);
                        } else {
                            const msg = try std.fmt.allocPrint(self.allocator, "Call to undefined method Generator::{s}()", .{method_name});
                            try self.strings.append(self.allocator, msg);
                            if (try self.throwBuiltinException("Error", msg)) continue;
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
                                if (try self.throwBuiltinException("FiberError", "Cannot start a fiber that has already been started")) continue;
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

                            const result = self.executeFiber(fiber, fb, sb, hb) catch {
                                if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            };
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

                            const result = self.executeFiber(fiber, fb, sb, hb) catch {
                                if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            };
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
                        } else if (std.mem.eql(u8, method_name, "throw")) {
                            if (fiber.state != .suspended) {
                                if (try self.throwBuiltinException("FiberError", "Cannot resume a fiber that is not suspended")) continue;
                                return error.RuntimeError;
                            }
                            const exc_val = if (ac > 0) args_buf[0] else Value.null;
                            if (exc_val != .object) {
                                if (try self.throwBuiltinException("TypeError", "Fiber::throw() expects an object")) continue;
                                return error.RuntimeError;
                            }
                            fiber.state = .running;
                            const fb = self.frame_count;
                            const sb = self.sp;
                            const hb = self.handler_count;

                            self.restoreFiberState(fiber, fb, sb);
                            self.push(.null);
                            const prev_fiber = self.current_fiber;
                            const prev_floor = self.handler_floor;
                            self.current_fiber = fiber;
                            self.handler_floor = hb;
                            self.pending_exception = exc_val;
                            const dispatched = self.dispatchPendingException(fb);
                            self.current_fiber = prev_fiber;
                            self.handler_floor = prev_floor;
                            if (!dispatched) {
                                fiber.state = .terminated;
                                if (self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            }
                            const result = self.executeFiber(fiber, fb, sb, hb) catch {
                                if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            };
                            self.push(result);
                        } else {
                            const msg = try std.fmt.allocPrint(self.allocator, "Call to undefined method Fiber::{s}()", .{method_name});
                            try self.strings.append(self.allocator, msg);
                            if (try self.throwBuiltinException("Error", msg)) continue;
                            return error.RuntimeError;
                        }
                        continue;
                    }

                    if (obj_val == .string and std.mem.startsWith(u8, obj_val.string, "__closure_")) {
                        const closure_name = obj_val.string;
                        // __invoke(...args) on a closure is equivalent to
                        // calling the closure directly. preserves the closure's
                        // existing $this/scope binding
                        if (std.mem.eql(u8, method_name, "__invoke")) {
                            var call_args: [16]Value = undefined;
                            for (0..ac) |i| call_args[i] = self.stack[self.sp - ac + i];
                            self.sp -= ac + 1;
                            const result = try self.callByName(closure_name, call_args[0..ac]);
                            self.push(result);
                            continue;
                        }
                        if (std.mem.eql(u8, method_name, "bindTo")) {
                            const new_this = if (ac >= 1) self.stack[self.sp - ac] else Value.null;
                            const bt_scope: ClosureScope = blk: {
                                if (ac >= 2) {
                                    const sa = self.stack[self.sp - ac + 1];
                                    if (sa == .string) {
                                        if (std.mem.eql(u8, sa.string, "static")) break :blk .preserve;
                                        break :blk .{ .set = sa.string };
                                    }
                                    if (sa == .object) break :blk .{ .set = sa.object.class_name };
                                    if (sa == .null) break :blk .clear;
                                }
                                break :blk .preserve;
                            };
                            self.sp -= ac + 1;
                            const result = try self.cloneClosureWithThis(closure_name, new_this, bt_scope);
                            self.push(result);
                            continue;
                        } else if (std.mem.eql(u8, method_name, "call")) {
                            const new_this = if (ac >= 1) self.stack[self.sp - ac] else Value.null;
                            const call_scope: ClosureScope = if (new_this == .object) .{ .set = new_this.object.class_name } else .preserve;
                            var call_args: [16]Value = undefined;
                            const extra = if (ac > 1) ac - 1 else 0;
                            for (0..extra) |i| call_args[i] = self.stack[self.sp - ac + 1 + i];
                            self.sp -= ac + 1;
                            const bound = try self.cloneClosureWithThis(closure_name, new_this, call_scope);
                            if (bound == .string) {
                                const result = try self.callByName(bound.string, call_args[0..extra]);
                                self.push(result);
                            } else {
                                self.push(.null);
                            }
                            continue;
                        } else {
                            self.sp -= ac + 1;
                            const msg = try std.fmt.allocPrint(self.allocator, "Call to undefined method Closure::{s}()", .{method_name});
                            try self.strings.append(self.allocator, msg);
                            if (try self.throwBuiltinException("Error", msg)) continue;
                            return error.RuntimeError;
                        }
                    }

                    if (obj_val != .object) {
                        self.sp -= ac + 1;
                        const msg = try std.fmt.allocPrint(self.allocator, "Call to a member function {s}() on {s}", .{ method_name, valueTypeName(obj_val) });
                        try self.strings.append(self.allocator, msg);
                        if (try self.throwBuiltinException("Error", msg)) continue;
                        return error.RuntimeError;
                    }
                    const obj = obj_val.object;

                    // IC: skip visibility + resolve on cache hit
                    if (self.ic) |ic| {
                        const mc_ip = self.currentFrame().ip - 4;
                        const mc_chunk_key = @intFromPtr(self.currentChunk());
                        const mc_idx = InlineCache.methodIndex(mc_chunk_key, mc_ip);
                        const mc_entry = &ic.method[mc_idx];
                        if (mc_entry.key == mc_ip and mc_entry.chunk_key == mc_chunk_key and mc_entry.class_ptr == @intFromPtr(obj.class_name.ptr)) {
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
                                        if (i < func.defaults.len) mc_locals[i + 1] = try self.resolveDefault(func.defaults[i]);
                                    }
                                    self.saveFrameArgs(arg_count);
                                    self.sp -= ac + 1;
                                    self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = .{}, .locals = mc_locals, .func = func };
                                    self.setFrameArgCount(arg_count);
                                    self.frames[self.frame_count].entry_sp = self.sp;
                    self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
                                    try self.fastLoop();
                                    continue;
                                }
                            } else if (mc_entry.native) |native| {
                                var args_buf: [16]Value = undefined;
                                for (0..ac) |i| args_buf[i] = self.stack[self.sp - ac + i];
                                self.saveFrameArgs(arg_count);
                                self.sp -= ac + 1;
                                var tmp_vars: std.StringHashMapUnmanaged(Value) = .{};
                                try tmp_vars.put(self.allocator, "$this", .{ .object = obj });
                                self.frames[self.frame_count] = .{ .chunk = self.currentChunk(), .ip = self.currentFrame().ip, .vars = tmp_vars };
                                self.setFrameArgCount(arg_count);
                                self.frames[self.frame_count].entry_sp = self.sp;
                    self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
                                const saved_fc = self.frame_count;
                                var ctx = self.makeContext(null);
                                const result = try native(&ctx, args_buf[0..ac]);
                                if (self.frame_count >= saved_fc) {
                                    self.frame_count -= 1;
                                    self.deinitFrameSlot(self.frame_count);
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
                        const suffix = self.visScopeSuffix();
                        const msg = try std.fmt.allocPrint(self.allocator, "Call to {s} method {s}::{s}(){s}", .{
                            @tagName(mvr.visibility), mvr.defining_class, method_name, suffix,
                        });
                        try self.strings.append(self.allocator, msg);
                        self.sp -= ac + 1;
                        if (try self.throwBuiltinException("Error", msg)) continue;
                        return error.RuntimeError;
                    }

                    // look up method in class hierarchy
                    const full_name = self.resolveMethod(obj.class_name, method_name) catch {
                        if (self.hasMethod(obj.class_name, "__call")) {
                            const obj_id = @intFromPtr(obj);
                            var in_call = false;
                            var call_depth: usize = 0;
                            for (self.magic_call_guard.items) |e| {
                                if (e.obj_ptr == obj_id) {
                                    call_depth += 1;
                                    if (std.mem.eql(u8, e.method_name, method_name)) {
                                        in_call = true;
                                        break;
                                    }
                                }
                            }
                            if (!in_call and call_depth < 16) {
                                try self.magic_call_guard.append(self.allocator, .{ .obj_ptr = obj_id, .method_name = method_name });
                                var args_arr = try self.allocator.create(PhpArray);
                                args_arr.* = .{};
                                try self.arrays.append(self.allocator, args_arr);
                                for (0..ac) |i| try args_arr.append(self.allocator, self.stack[self.sp - ac + i]);
                                self.sp -= ac + 1;
                                const result = self.callMethod(obj, "__call", &.{ .{ .string = method_name }, .{ .array = args_arr } }) catch |err| {
                                    self.removeCallGuard(obj_id, method_name);
                                    if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                                    return err;
                                };
                                self.removeCallGuard(obj_id, method_name);
                                self.push(result);
                                continue;
                            }
                        }
                        self.sp -= ac + 1;
                        const msg = std.fmt.allocPrint(self.allocator, "Call to undefined method {s}::{s}()", .{ obj.class_name, method_name }) catch "Call to undefined method";
                        try self.strings.append(self.allocator, msg);
                        if (try self.throwBuiltinException("Error", msg)) continue;
                        self.setErrorMsg("Fatal error: Uncaught Error: {s}", .{msg});
                        return error.RuntimeError;
                    };
                    if (self.native_fns.get(full_name)) |native| {
                        // populate IC
                        if (self.ic) |ic| {
                            const mc_ip2 = self.currentFrame().ip - 4;
                            const mc_chunk_key2 = @intFromPtr(self.currentChunk());
                            const mc_idx2 = InlineCache.methodIndex(mc_chunk_key2, mc_ip2);
                            if (mvr.visibility == .public) {
                                ic.method[mc_idx2] = .{ .key = mc_ip2, .chunk_key = mc_chunk_key2, .class_ptr = @intFromPtr(obj.class_name.ptr), .native = native, .full_name = full_name };
                            }
                        }
                        var args_buf: [16]Value = undefined;
                        for (0..ac) |i| args_buf[i] = self.stack[self.sp - ac + i];
                        self.saveFrameArgs(arg_count);
                        self.sp -= ac;
                        self.sp -= 1;

                        // push a temporary frame so native can read $this
                        var tmp_vars: std.StringHashMapUnmanaged(Value) = .{};
                        try tmp_vars.put(self.allocator, "$this", .{ .object = obj });
                        self.frames[self.frame_count] = .{ .chunk = self.currentChunk(), .ip = self.currentFrame().ip, .vars = tmp_vars };
                        self.setFrameArgCount(arg_count);
                        self.frames[self.frame_count].entry_sp = self.sp;
                    self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
                        const saved_fc = self.frame_count;

                        var ctx = self.makeContext(null);
                        const result = native(&ctx, args_buf[0..ac]) catch {
                            if (self.frame_count >= saved_fc) {
                                self.frame_count -= 1;
                                self.deinitFrameSlot(self.frame_count);
                            }
                            if (self.pending_exception) |exc| {
                                self.pending_exception = null;
                                if (self.handler_count > self.handler_floor) {
                                    const handler = self.exception_handlers[self.handler_count - 1];
                                    self.handler_count -= 1;
                                    while (self.frame_count > handler.frame_count) {
                                        self.frame_count -= 1;
                                        self.deinitFrameSlot(self.frame_count);
                                    }
                                    self.sp = handler.sp;
                                    self.push(exc);
                                    self.currentFrame().ip = handler.catch_ip;
                                    continue;
                                }
                                self.pending_exception = exc;
                            } else {
                                continue;
                            }
                            return error.RuntimeError;
                        };

                        // if throwBuiltinException unwound frames, skip cleanup
                        if (self.frame_count >= saved_fc) {
                            self.frame_count -= 1;
                            self.deinitFrameSlot(self.frame_count);
                            self.push(result);
                        } else {
                            continue;
                        }
                    } else if (self.functions.get(full_name)) |func| {
                        // populate IC
                        if (self.ic) |ic| {
                            const mc_ip2 = self.currentFrame().ip - 4;
                            const mc_chunk_key2 = @intFromPtr(self.currentChunk());
                            const mc_idx2 = InlineCache.methodIndex(mc_chunk_key2, mc_ip2);
                            if (mvr.visibility == .public) {
                                ic.method[mc_idx2] = .{ .key = mc_ip2, .chunk_key = mc_chunk_key2, .class_ptr = @intFromPtr(obj.class_name.ptr), .func = func, .full_name = full_name };
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
                            for (@min(ac, fixed)..fixed) |i| {
                                if (i < func.defaults.len) try new_vars.put(self.allocator, func.params[i], try self.resolveDefault(func.defaults[i]));
                            }
                            const rest_arr = try self.allocator.create(PhpArray);
                            rest_arr.* = .{};
                            try self.arrays.append(self.allocator, rest_arr);
                            if (ac > fixed) for (fixed..ac) |i| try rest_arr.append(self.allocator, self.stack[self.sp - ac + i]);
                            try new_vars.put(self.allocator, func.params[fixed], .{ .array = rest_arr });
                        } else {
                            for (0..@min(ac, func.arity)) |i| {
                                try new_vars.put(self.allocator, func.params[i], self.stack[self.sp - ac + i]);
                            }
                            try self.fillDefaults(&new_vars, func, ac);
                        }
                        var method_refs: std.StringHashMapUnmanaged(*Value) = .{};
                        var method_array_bindings: std.ArrayListUnmanaged(ArrayRefBinding) = .{};
                        var method_object_bindings: std.ArrayListUnmanaged(ObjectRefBinding) = .{};
                        try self.bindRefParams(ac, func, &new_vars, &method_refs, &method_array_bindings, &method_object_bindings);
                        self.saveFrameArgs(arg_count);
                        self.sp -= ac;
                        self.sp -= 1;
                        if (func.is_generator) {
                            method_refs.deinit(self.allocator);
                            method_array_bindings.deinit(self.allocator);
                            method_object_bindings.deinit(self.allocator);
                            const gen = try self.allocator.create(Generator);
                            gen.* = .{ .func = func, .vars = new_vars };
                            try self.generators.append(self.allocator, gen);
                            self.push(.{ .generator = gen });
                        } else {
                            self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars, .locals = try self.allocLocals(func, &new_vars), .func = func, .ref_slots = method_refs, .ref_array_bindings = method_array_bindings, .ref_object_bindings = method_object_bindings };
                            self.setFrameArgCount(arg_count);
                            self.frames[self.frame_count].entry_sp = self.sp;
                    self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
                        }
                    } else {
                        self.sp -= ac + 1;
                        const msg = std.fmt.allocPrint(self.allocator, "Call to undefined method {s}::{s}()", .{ obj.class_name, method_name }) catch "Call to undefined method";
                        try self.strings.append(self.allocator, msg);
                        if (try self.throwBuiltinException("Error", msg)) continue;
                        self.setErrorMsg("Fatal error: Uncaught Error: {s}", .{msg});
                        return error.RuntimeError;
                    }
                },

                .method_call_spread => {
                    const name_idx = self.readU16();
                    const method_name = self.currentChunk().constants.items[name_idx].string;
                    const args_val = self.pop();
                    if (args_val != .array) {
                        self.setErrorMsg("Fatal error: Uncaught TypeError: Argument unpacking requires an array", .{});
                        return error.RuntimeError;
                    }
                    const arr = args_val.array;

                    // check for named args
                    var has_named = false;
                    for (arr.entries.items) |entry| {
                        if (entry.key == .string) { has_named = true; break; }
                    }

                    var resolved_buf: [16]Value = .{.null} ** 16;
                    var ac = arr.entries.items.len;

                    if (has_named) {
                        const obj_peek = self.stack[self.sp - 1];
                        if (obj_peek == .object) {
                            const full = self.resolveMethod(obj_peek.object.class_name, method_name) catch null;
                            if (full) |fn_name| {
                                if (self.functions.get(fn_name)) |func| {
                                    var pos: usize = 0;
                                    for (arr.entries.items) |entry| {
                                        if (entry.key == .string) {
                                            for (func.params, 0..) |p, pi| {
                                                if (std.mem.eql(u8, p[1..], entry.key.string) or std.mem.eql(u8, p, entry.key.string)) {
                                                    resolved_buf[pi] = entry.value;
                                                    if (pi >= pos) pos = pi + 1;
                                                    break;
                                                }
                                            }
                                        } else {
                                            resolved_buf[pos] = entry.value;
                                            pos += 1;
                                        }
                                    }
                                    // fill defaults
                                    ac = @max(pos, func.required_params);
                                    for (0..ac) |i| {
                                        if (resolved_buf[i] == .null and i < func.defaults.len) {
                                            resolved_buf[i] = try self.resolveDefault(func.defaults[i]);
                                        }
                                    }
                                    for (0..ac) |i| self.push(resolved_buf[i]);
                                } else {
                                    for (arr.entries.items) |entry| self.push(entry.value);
                                }
                            } else {
                                for (arr.entries.items) |entry| self.push(entry.value);
                            }
                        } else {
                            for (arr.entries.items) |entry| self.push(entry.value);
                        }
                    } else {
                        for (arr.entries.items) |entry| self.push(entry.value);
                    }
                    const obj_val = self.stack[self.sp - ac - 1];
                    if (obj_val != .object) {
                        self.sp -= ac + 1;
                        const msg = try std.fmt.allocPrint(self.allocator, "Call to a member function {s}() on {s}", .{ method_name, valueTypeName(obj_val) });
                        try self.strings.append(self.allocator, msg);
                        if (try self.throwBuiltinException("Error", msg)) continue;
                        return error.RuntimeError;
                    }
                    const obj = obj_val.object;
                    const mvr = self.findMethodVisibility(obj.class_name, method_name);
                    if (!self.checkVisibility(mvr.defining_class, mvr.visibility)) {
                        self.sp -= ac + 1;
                        const suffix = self.visScopeSuffix();
                        const msg = std.fmt.allocPrint(self.allocator, "Call to {s} method {s}::{s}(){s}", .{ @tagName(mvr.visibility), mvr.defining_class, method_name, suffix }) catch null;
                        self.error_msg = msg;
                        return error.RuntimeError;
                    }
                    const mcs_ac_u8: u8 = @intCast(@min(ac, 255));
                    const full_name = try self.resolveMethod(obj.class_name, method_name);
                    if (self.native_fns.get(full_name)) |native| {
                        var args_buf: [16]Value = undefined;
                        for (0..ac) |i| args_buf[i] = self.stack[self.sp - ac + i];
                        self.saveFrameArgs(mcs_ac_u8);
                        self.sp -= ac;
                        self.sp -= 1;
                        var tmp_vars: std.StringHashMapUnmanaged(Value) = .{};
                        try tmp_vars.put(self.allocator, "$this", .{ .object = obj });
                        self.frames[self.frame_count] = .{ .chunk = self.currentChunk(), .ip = self.currentFrame().ip, .vars = tmp_vars };
                        self.setFrameArgCount(mcs_ac_u8);
                        self.frames[self.frame_count].entry_sp = self.sp;
                    self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
                        const saved_fc = self.frame_count;
                        var ctx = self.makeContext(null);
                        const result = native(&ctx, args_buf[0..ac]) catch {
                            if (self.frame_count >= saved_fc) {
                                self.frame_count -= 1;
                                self.deinitFrameSlot(self.frame_count);
                            }
                            if (self.pending_exception) |exc| {
                                self.pending_exception = null;
                                if (self.handler_count > self.handler_floor) {
                                    const handler = self.exception_handlers[self.handler_count - 1];
                                    self.handler_count -= 1;
                                    while (self.frame_count > handler.frame_count) {
                                        self.frame_count -= 1;
                                        self.deinitFrameSlot(self.frame_count);
                                    }
                                    self.sp = handler.sp;
                                    self.push(exc);
                                    self.currentFrame().ip = handler.catch_ip;
                                    continue;
                                }
                                self.pending_exception = exc;
                            } else {
                                continue;
                            }
                            return error.RuntimeError;
                        };
                        if (self.frame_count >= saved_fc) {
                            self.frame_count -= 1;
                            self.deinitFrameSlot(self.frame_count);
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
                            for (@min(ac, fixed)..fixed) |i| {
                                if (i < func.defaults.len) try new_vars.put(self.allocator, func.params[i], try self.resolveDefault(func.defaults[i]));
                            }
                            const rest_arr = try self.allocator.create(PhpArray);
                            rest_arr.* = .{};
                            try self.arrays.append(self.allocator, rest_arr);
                            if (ac > fixed) for (fixed..ac) |i| try rest_arr.append(self.allocator, self.stack[self.sp - ac + i]);
                            try new_vars.put(self.allocator, func.params[fixed], .{ .array = rest_arr });
                        } else {
                            for (0..@min(ac, func.arity)) |i| {
                                try new_vars.put(self.allocator, func.params[i], self.stack[self.sp - ac + i]);
                            }
                            for (ac..func.arity) |i| {
                                if (i < func.defaults.len) try new_vars.put(self.allocator, func.params[i], try self.resolveDefault(func.defaults[i]));
                            }
                        }
                        self.saveFrameArgs(mcs_ac_u8);
                        self.sp -= ac;
                        self.sp -= 1;
                        self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars, .locals = try self.allocLocals(func, &new_vars), .func = func };
                        self.setFrameArgCount(mcs_ac_u8);
                        self.frames[self.frame_count].entry_sp = self.sp;
                    self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
                    } else {
                        self.sp -= ac + 1;
                        const msg = std.fmt.allocPrint(self.allocator, "Call to undefined method {s}::{s}()", .{ obj.class_name, method_name }) catch "Call to undefined method";
                        try self.strings.append(self.allocator, msg);
                        if (try self.throwBuiltinException("Error", msg)) continue;
                        self.setErrorMsg("Fatal error: Uncaught Error: {s}", .{msg});
                        return error.RuntimeError;
                    }
                },

                .method_call_dynamic => {
                    const arg_count = self.readByte();
                    const ac: usize = arg_count;
                    // stack: [object, method_name, arg1, ..., argN]
                    const method_name_val = self.stack[self.sp - ac - 1];
                    const obj_val = self.stack[self.sp - ac - 2];
                    if (method_name_val != .string) {
                        self.sp -= ac + 2;
                        const msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught TypeError: Method name must be a string", .{}) catch null;
                        self.error_msg = msg;
                        return error.RuntimeError;
                    }
                    const method_name = method_name_val.string;
                    if (obj_val != .object) {
                        self.sp -= ac + 2;
                        const msg = try std.fmt.allocPrint(self.allocator, "Call to a member function {s}() on {s}", .{ method_name, valueTypeName(obj_val) });
                        try self.strings.append(self.allocator, msg);
                        if (try self.throwBuiltinException("Error", msg)) continue;
                        return error.RuntimeError;
                    }
                    const obj = obj_val.object;
                    // shift args down by 1 to remove method_name from stack, leaving [object, arg1, ..., argN]
                    var i: usize = 0;
                    while (i < ac) : (i += 1) {
                        self.stack[self.sp - ac - 1 + i] = self.stack[self.sp - ac + i];
                    }
                    self.sp -= 1;
                    // now stack is [object, arg1, ..., argN] - same layout as method_call
                    const full_name = self.resolveMethod(obj.class_name, method_name) catch {
                        if (self.hasMethod(obj.class_name, "__call")) {
                            var args_arr = try self.allocator.create(PhpArray);
                            args_arr.* = .{};
                            try self.arrays.append(self.allocator, args_arr);
                            for (0..ac) |ai| try args_arr.append(self.allocator, self.stack[self.sp - ac + ai]);
                            self.sp -= ac;
                            self.sp -= 1;
                            const result = self.callMethod(obj, "__call", &.{ .{ .string = method_name }, .{ .array = args_arr } }) catch {
                                if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            };
                            self.push(result);
                            continue;
                        }
                        self.sp -= ac + 1;
                        const msg = std.fmt.allocPrint(self.allocator, "Call to undefined method {s}::{s}()", .{ obj.class_name, method_name }) catch "Call to undefined method";
                        try self.strings.append(self.allocator, msg);
                        if (try self.throwBuiltinException("Error", msg)) continue;
                        self.setErrorMsg("Fatal error: Uncaught Error: {s}", .{msg});
                        return error.RuntimeError;
                    };
                    if (self.native_fns.get(full_name)) |native| {
                        var args_buf: [16]Value = undefined;
                        for (0..ac) |ai| args_buf[ai] = self.stack[self.sp - ac + ai];
                        self.saveFrameArgs(arg_count);
                        self.sp -= ac;
                        self.sp -= 1;
                        var tmp_vars: std.StringHashMapUnmanaged(Value) = .{};
                        try tmp_vars.put(self.allocator, "$this", .{ .object = obj });
                        self.frames[self.frame_count] = .{ .chunk = self.currentChunk(), .ip = self.currentFrame().ip, .vars = tmp_vars };
                        self.setFrameArgCount(arg_count);
                        self.frames[self.frame_count].entry_sp = self.sp;
                    self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
                        const saved_fc = self.frame_count;
                        var ctx = self.makeContext(null);
                        const result = native(&ctx, args_buf[0..ac]) catch {
                            if (self.frame_count >= saved_fc) {
                                self.frame_count -= 1;
                                self.deinitFrameSlot(self.frame_count);
                            }
                            if (self.pending_exception) |exc| {
                                self.pending_exception = null;
                                if (self.handler_count > self.handler_floor) {
                                    const handler = self.exception_handlers[self.handler_count - 1];
                                    self.handler_count -= 1;
                                    while (self.frame_count > handler.frame_count) {
                                        self.frame_count -= 1;
                                        self.deinitFrameSlot(self.frame_count);
                                    }
                                    self.sp = handler.sp;
                                    self.push(exc);
                                    self.currentFrame().ip = handler.catch_ip;
                                    continue;
                                }
                                self.pending_exception = exc;
                            } else {
                                continue;
                            }
                            return error.RuntimeError;
                        };
                        if (self.frame_count >= saved_fc) {
                            self.frame_count -= 1;
                            self.deinitFrameSlot(self.frame_count);
                            self.push(result);
                        } else continue;
                    } else if (self.functions.get(full_name)) |func| {
                        var new_vars: std.StringHashMapUnmanaged(Value) = .{};
                        try new_vars.put(self.allocator, "$this", .{ .object = obj });
                        try self.bindClosures(&new_vars, null, full_name);
                        if (func.is_variadic) {
                            const fixed: usize = func.arity - 1;
                            for (0..@min(ac, fixed)) |ai| {
                                try new_vars.put(self.allocator, func.params[ai], self.stack[self.sp - ac + ai]);
                            }
                            for (@min(ac, fixed)..fixed) |ai| {
                                if (ai < func.defaults.len) try new_vars.put(self.allocator, func.params[ai], try self.resolveDefault(func.defaults[ai]));
                            }
                            const rest_arr = try self.allocator.create(PhpArray);
                            rest_arr.* = .{};
                            try self.arrays.append(self.allocator, rest_arr);
                            if (ac > fixed) for (fixed..ac) |ai| try rest_arr.append(self.allocator, self.stack[self.sp - ac + ai]);
                            try new_vars.put(self.allocator, func.params[fixed], .{ .array = rest_arr });
                        } else {
                            for (0..@min(ac, func.arity)) |ai| {
                                try new_vars.put(self.allocator, func.params[ai], self.stack[self.sp - ac + ai]);
                            }
                            if (ac < func.arity) {
                                for (ac..func.arity) |ai| {
                                    if (ai < func.defaults.len) try new_vars.put(self.allocator, func.params[ai], try self.resolveDefault(func.defaults[ai]));
                                }
                            }
                        }
                        self.saveFrameArgs(arg_count);
                        self.sp -= ac;
                        self.sp -= 1;
                        self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars, .locals = try self.allocLocals(func, &new_vars), .func = func };
                        self.setFrameArgCount(arg_count);
                        self.frames[self.frame_count].entry_sp = self.sp;
                    self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
                    } else {
                        self.sp -= ac + 1;
                        const msg = std.fmt.allocPrint(self.allocator, "Call to undefined method {s}::{s}()", .{ obj.class_name, method_name }) catch "Call to undefined method";
                        try self.strings.append(self.allocator, msg);
                        if (try self.throwBuiltinException("Error", msg)) continue;
                        self.setErrorMsg("Fatal error: Uncaught Error: {s}", .{msg});
                        return error.RuntimeError;
                    }
                },

                .method_call_dynamic_spread => {
                    // stack: [object, method_name, args_array]
                    const args_val = self.pop();
                    const method_name_val = self.pop();
                    const obj_val = self.pop();
                    if (args_val != .array) {
                        self.setErrorMsg("Fatal error: Uncaught TypeError: Argument unpacking requires an array", .{});
                        return error.RuntimeError;
                    }
                    if (method_name_val != .string) {
                        self.setErrorMsg("Fatal error: Uncaught TypeError: Method name must be a string", .{});
                        return error.RuntimeError;
                    }
                    if (obj_val != .object) {
                        const msg = try std.fmt.allocPrint(self.allocator, "Call to a member function {s}() on {s}", .{ method_name_val.string, valueTypeName(obj_val) });
                        try self.strings.append(self.allocator, msg);
                        if (try self.throwBuiltinException("Error", msg)) continue;
                        return error.RuntimeError;
                    }
                    const method_name = method_name_val.string;
                    const obj = obj_val.object;
                    const arr = args_val.array;
                    const ac = arr.entries.items.len;
                    // push object and args back in method_call layout
                    self.push(obj_val);
                    for (arr.entries.items) |entry| self.push(entry.value);
                    // reuse method_call logic
                    const full_name = self.resolveMethod(obj.class_name, method_name) catch {
                        if (self.hasMethod(obj.class_name, "__call")) {
                            const obj_id = @intFromPtr(obj);
                            var in_call = false;
                            var call_depth: usize = 0;
                            for (self.magic_call_guard.items) |e| {
                                if (e.obj_ptr == obj_id) {
                                    call_depth += 1;
                                    if (std.mem.eql(u8, e.method_name, method_name)) {
                                        in_call = true;
                                        break;
                                    }
                                }
                            }
                            if (!in_call and call_depth < 16) {
                                try self.magic_call_guard.append(self.allocator, .{ .obj_ptr = obj_id, .method_name = method_name });
                                var call_args_arr = try self.allocator.create(PhpArray);
                                call_args_arr.* = .{};
                                try self.arrays.append(self.allocator, call_args_arr);
                                for (0..ac) |ai| try call_args_arr.append(self.allocator, self.stack[self.sp - ac + ai]);
                                self.sp -= ac;
                                self.sp -= 1;
                                const result = self.callMethod(obj, "__call", &.{ .{ .string = method_name }, .{ .array = call_args_arr } }) catch |err| {
                                    self.removeCallGuard(obj_id, method_name);
                                    if (err == error.RuntimeError and self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                                    return err;
                                };
                                self.removeCallGuard(obj_id, method_name);
                                self.push(result);
                                continue;
                            }
                        }
                        self.sp -= ac + 1;
                        const msg = std.fmt.allocPrint(self.allocator, "Call to undefined method {s}::{s}()", .{ obj.class_name, method_name }) catch "Call to undefined method";
                        try self.strings.append(self.allocator, msg);
                        if (try self.throwBuiltinException("Error", msg)) continue;
                        self.setErrorMsg("Fatal error: Uncaught Error: {s}", .{msg});
                        return error.RuntimeError;
                    };
                    const mcds_ac_u8: u8 = @intCast(@min(ac, 255));
                    if (self.native_fns.get(full_name)) |native| {
                        var args_buf: [16]Value = undefined;
                        for (0..ac) |ai| args_buf[ai] = self.stack[self.sp - ac + ai];
                        self.saveFrameArgs(mcds_ac_u8);
                        self.sp -= ac;
                        self.sp -= 1;
                        var tmp_vars: std.StringHashMapUnmanaged(Value) = .{};
                        try tmp_vars.put(self.allocator, "$this", .{ .object = obj });
                        self.frames[self.frame_count] = .{ .chunk = self.currentChunk(), .ip = self.currentFrame().ip, .vars = tmp_vars };
                        self.setFrameArgCount(mcds_ac_u8);
                        self.frames[self.frame_count].entry_sp = self.sp;
                    self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
                        const saved_fc = self.frame_count;
                        var ctx = self.makeContext(null);
                        const result = native(&ctx, args_buf[0..ac]) catch {
                            if (self.frame_count >= saved_fc) {
                                self.frame_count -= 1;
                                self.deinitFrameSlot(self.frame_count);
                            }
                            if (self.pending_exception) |exc| {
                                self.pending_exception = null;
                                if (self.handler_count > self.handler_floor) {
                                    const handler = self.exception_handlers[self.handler_count - 1];
                                    self.handler_count -= 1;
                                    while (self.frame_count > handler.frame_count) {
                                        self.frame_count -= 1;
                                        self.deinitFrameSlot(self.frame_count);
                                    }
                                    self.sp = handler.sp;
                                    self.push(exc);
                                    self.currentFrame().ip = handler.catch_ip;
                                    continue;
                                }
                                self.pending_exception = exc;
                            } else {
                                continue;
                            }
                            return error.RuntimeError;
                        };
                        if (self.frame_count >= saved_fc) {
                            self.frame_count -= 1;
                            self.deinitFrameSlot(self.frame_count);
                            self.push(result);
                        } else continue;
                    } else if (self.functions.get(full_name)) |func| {
                        var new_vars: std.StringHashMapUnmanaged(Value) = .{};
                        try new_vars.put(self.allocator, "$this", .{ .object = obj });
                        try self.bindClosures(&new_vars, null, full_name);
                        if (func.is_variadic) {
                            const fixed: usize = func.arity - 1;
                            for (0..@min(ac, fixed)) |ai| {
                                try new_vars.put(self.allocator, func.params[ai], self.stack[self.sp - ac + ai]);
                            }
                            for (@min(ac, fixed)..fixed) |ai| {
                                if (ai < func.defaults.len) try new_vars.put(self.allocator, func.params[ai], try self.resolveDefault(func.defaults[ai]));
                            }
                            const rest_arr = try self.allocator.create(PhpArray);
                            rest_arr.* = .{};
                            try self.arrays.append(self.allocator, rest_arr);
                            if (ac > fixed) for (fixed..ac) |ai| try rest_arr.append(self.allocator, self.stack[self.sp - ac + ai]);
                            try new_vars.put(self.allocator, func.params[fixed], .{ .array = rest_arr });
                        } else {
                            for (0..@min(ac, func.arity)) |ai| {
                                try new_vars.put(self.allocator, func.params[ai], self.stack[self.sp - ac + ai]);
                            }
                            if (ac < func.arity) {
                                for (ac..func.arity) |ai| {
                                    if (ai < func.defaults.len) try new_vars.put(self.allocator, func.params[ai], try self.resolveDefault(func.defaults[ai]));
                                }
                            }
                        }
                        self.saveFrameArgs(mcds_ac_u8);
                        self.sp -= ac;
                        self.sp -= 1;
                        self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars, .locals = try self.allocLocals(func, &new_vars), .func = func };
                        self.setFrameArgCount(mcds_ac_u8);
                        self.frames[self.frame_count].entry_sp = self.sp;
                    self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
                    } else {
                        self.sp -= ac + 1;
                        const msg = std.fmt.allocPrint(self.allocator, "Call to undefined method {s}::{s}()", .{ obj.class_name, method_name }) catch "Call to undefined method";
                        try self.strings.append(self.allocator, msg);
                        if (try self.throwBuiltinException("Error", msg)) continue;
                        self.setErrorMsg("Fatal error: Uncaught Error: {s}", .{msg});
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

                    if (std.mem.eql(u8, class_name, "Fiber") and std.mem.eql(u8, method_name, "getCurrent")) {
                        self.sp -= @as(usize, arg_count);
                        if (self.current_fiber) |fiber| {
                            self.push(.{ .fiber = fiber });
                        } else {
                            self.push(.null);
                        }
                        continue;
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
                    var lsb_class: ?[]const u8 = null;
                    if (std.mem.eql(u8, class_name, "static")) {
                        class_name = self.resolveStaticClassName(class_name);
                    } else if (std.mem.eql(u8, class_name, "parent") or std.mem.eql(u8, class_name, "self")) {
                        if (std.mem.eql(u8, class_name, "parent")) {
                            const dc = self.parentResolvingClass();
                            if (dc) |defining| {
                                if (self.classes.get(defining)) |cls| {
                                    if (cls.parent) |p| class_name = p;
                                }
                                lsb_class = self.currentFrame().called_class orelse defining;
                            }
                        } else {
                            // self:: resolves to the defining class for method lookup,
                            // but propagates called_class for LSB (new static() etc)
                            lsb_class = self.currentFrame().called_class;
                            if (self.currentDefiningClass()) |dc| class_name = dc;
                        }
                    } else if (self.currentFrame().called_class) |cc| {
                        // compiler resolved self:: to a concrete class at compile time;
                        // propagate called_class if the target is an ancestor of it
                        if (self.isAncestor(class_name, cc)) lsb_class = cc;
                    }

                    const effective_called = lsb_class orelse class_name;

                    const full_name = self.resolveMethod(class_name, method_name) catch {
                        if (self.hasMethod(class_name, "__callStatic")) {
                            const ac: usize = arg_count;
                            var args_arr = try self.allocator.create(PhpArray);
                            args_arr.* = .{};
                            try self.arrays.append(self.allocator, args_arr);
                            for (0..ac) |i| try args_arr.append(self.allocator, self.stack[self.sp - ac + i]);
                            self.sp -= ac;
                            const cs_name = try self.resolveMethod(class_name, "__callStatic");
                            self.push(.{ .string = method_name });
                            self.push(.{ .array = args_arr });
                            try self.callStaticFunction(cs_name, 2, effective_called);
                            continue;
                        }
                        const msg = std.fmt.allocPrint(self.allocator, "Call to undefined method {s}::{s}()", .{ class_name, method_name }) catch "Call to undefined method";
                        try self.strings.append(self.allocator, msg);
                        if (try self.throwBuiltinException("Error", msg)) continue;
                        self.setErrorMsg("Fatal error: Uncaught Error: {s}", .{msg});
                        return error.RuntimeError;
                    };

                    // if we have $this, pass it through to the called method
                    if (this_val) |tv| {
                        if (tv == .object) {
                            if (self.functions.get(full_name)) |func| {
                                if (func.is_generator) {
                                    try self.callStaticFunction(full_name, arg_count, effective_called);
                                } else {
                                const ac: usize = arg_count;
                                var new_vars: std.StringHashMapUnmanaged(Value) = .{};
                                try new_vars.put(self.allocator, "$this", tv);
                                if (func.is_variadic) {
                                    const fixed: usize = func.arity - 1;
                                    for (0..@min(ac, fixed)) |i| {
                                        const is_ref = i < func.ref_params.len and func.ref_params[i];
                                        const sv = self.stack[self.sp - ac + i];
                                        try new_vars.put(self.allocator, func.params[i], if (is_ref) sv else try self.copyValue(sv));
                                    }
                                    const rest_arr = try self.allocator.create(PhpArray);
                                    rest_arr.* = .{};
                                    if (ac > fixed) {
                                        for (fixed..ac) |i| {
                                            try rest_arr.append(self.allocator, try self.copyValue(self.stack[self.sp - ac + i]));
                                        }
                                    }
                                    try self.arrays.append(self.allocator, rest_arr);
                                    try new_vars.put(self.allocator, func.params[fixed], .{ .array = rest_arr });
                                } else {
                                    for (0..@min(ac, func.arity)) |i| {
                                        const is_ref = i < func.ref_params.len and func.ref_params[i];
                                        const sv = self.stack[self.sp - ac + i];
                                        try new_vars.put(self.allocator, func.params[i], if (is_ref) sv else try self.copyValue(sv));
                                    }
                                }
                                if (self.frame_count >= 2047) {
                                    self.sp -= ac;
                                    new_vars.deinit(self.allocator);
                                    const msg = std.fmt.allocPrint(self.allocator, "Fatal error: maximum call stack depth exceeded in {s}::{s}()", .{ class_name, method_name }) catch "Fatal error: maximum call stack depth exceeded";
                                    try self.strings.append(self.allocator, msg);
                                    if (try self.throwBuiltinException("Error", msg)) continue;
                                    self.error_msg = msg;
                                    return error.RuntimeError;
                                }
                                self.saveFrameArgs(arg_count);
                                self.sp -= ac;
                                try self.fillDefaults(&new_vars, func, ac);
                                self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars, .locals = try self.allocLocals(func, &new_vars), .func = func, .called_class = effective_called };
                                self.setFrameArgCount(arg_count);
                                self.frames[self.frame_count].entry_sp = self.sp;
                    self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
                                }
                            } else if (self.native_fns.get(full_name)) |native| {
                                const ac: usize = arg_count;
                                var args_buf: [16]Value = undefined;
                                for (0..ac) |i| args_buf[i] = self.stack[self.sp - ac + i];
                                self.saveFrameArgs(arg_count);
                                self.sp -= ac;
                                var tmp_vars: std.StringHashMapUnmanaged(Value) = .{};
                                try tmp_vars.put(self.allocator, "$this", tv);
                                self.frames[self.frame_count] = .{ .chunk = self.currentChunk(), .ip = self.currentFrame().ip, .vars = tmp_vars, .called_class = effective_called };
                                self.setFrameArgCount(arg_count);
                                const sc_saved_fc = self.frame_count;
                                self.frames[self.frame_count].entry_sp = self.sp;
                    self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
                                var ctx = self.makeContext(full_name);
                                const result = native(&ctx, args_buf[0..ac]) catch {
                                    if (self.frame_count > sc_saved_fc) {
                                        self.frame_count -= 1;
                                        self.deinitFrameSlot(self.frame_count);
                                    }
                                    if (self.pending_exception) |exc| {
                                        self.pending_exception = null;
                                        if (self.handler_count > self.handler_floor) {
                                            const handler = self.exception_handlers[self.handler_count - 1];
                                            self.handler_count -= 1;
                                            while (self.frame_count > handler.frame_count) {
                                                self.frame_count -= 1;
                                                self.deinitFrameSlot(self.frame_count);
                                            }
                                            self.sp = handler.sp;
                                            self.push(exc);
                                            self.currentFrame().ip = handler.catch_ip;
                                            continue;
                                        }
                                        self.pending_exception = exc;
                                    } else {
                                        continue;
                                    }
                                    return error.RuntimeError;
                                };
                                self.frame_count -= 1;
                                self.deinitFrameSlot(self.frame_count);
                                self.push(result);
                            } else {
                                const msg = std.fmt.allocPrint(self.allocator, "Call to undefined method {s}::{s}()", .{ class_name, method_name }) catch "Call to undefined method";
                                try self.strings.append(self.allocator, msg);
                                if (try self.throwBuiltinException("Error", msg)) continue;
                                self.setErrorMsg("Fatal error: Uncaught Error: {s}", .{msg});
                                return error.RuntimeError;
                            }
                        } else {
                            try self.callStaticFunction(full_name, arg_count, effective_called);
                        }
                    } else {
                        try self.callStaticFunction(full_name, arg_count, effective_called);
                    }
                },

                .static_call_spread => {
                    const class_idx = self.readU16();
                    const method_idx = self.readU16();
                    var class_name = self.currentChunk().constants.items[class_idx].string;
                    const method_name = self.currentChunk().constants.items[method_idx].string;
                    const args_val = self.pop();
                    if (args_val != .array) {
                        self.setErrorMsg("Fatal error: Uncaught TypeError: Argument unpacking requires an array", .{});
                        return error.RuntimeError;
                    }
                    const arr = args_val.array;
                    const ac = arr.entries.items.len;

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
                    var lsb_class: ?[]const u8 = null;
                    if (std.mem.eql(u8, class_name, "parent") or std.mem.eql(u8, class_name, "self")) {
                        if (std.mem.eql(u8, class_name, "parent")) {
                            const dc = self.parentResolvingClass();
                            if (dc) |defining| {
                                if (self.classes.get(defining)) |cls| {
                                    if (cls.parent) |p| class_name = p;
                                }
                                lsb_class = self.currentFrame().called_class orelse defining;
                            }
                        } else {
                            // self:: resolves to defining class for method lookup,
                            // but propagates called_class for LSB
                            lsb_class = self.currentFrame().called_class;
                            if (self.currentDefiningClass()) |dc| class_name = dc;
                        }
                    } else if (self.currentFrame().called_class) |cc| {
                        if (self.isAncestor(class_name, cc)) lsb_class = cc;
                    }

                    const effective_called = lsb_class orelse class_name;

                    const full_name = self.resolveMethod(class_name, method_name) catch {
                        if (self.hasMethod(class_name, "__callStatic")) {
                            const cs_name = try self.resolveMethod(class_name, "__callStatic");
                            self.push(.{ .string = method_name });
                            self.push(.{ .array = arr });
                            try self.callStaticFunction(cs_name, 2, effective_called);
                            continue;
                        }
                        const msg = try std.fmt.allocPrint(self.allocator, "Call to undefined method {s}::{s}()", .{ class_name, method_name });
                        try self.strings.append(self.allocator, msg);
                        if (try self.throwBuiltinException("Error", msg)) continue;
                        return error.RuntimeError;
                    };
                    // resolve named args to positional order
                    var has_named_sc = false;
                    for (arr.entries.items) |entry| {
                        if (entry.key == .string) { has_named_sc = true; break; }
                    }
                    var resolved_ac = ac;
                    if (has_named_sc) {
                        if (self.functions.get(full_name)) |func2| {
                            var resolved: [16]Value = .{.null} ** 16;
                            var pos: usize = 0;
                            for (arr.entries.items) |entry| {
                                if (entry.key == .string) {
                                    for (func2.params, 0..) |p, pi| {
                                        const pn = if (p.len > 0 and p[0] == '$') p[1..] else p;
                                        if (std.mem.eql(u8, pn, entry.key.string)) {
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
                            resolved_ac = pos;
                        } else {
                            for (arr.entries.items) |entry| self.push(entry.value);
                        }
                    } else {
                        for (arr.entries.items) |entry| self.push(entry.value);
                    }

                    if (this_val) |tv| {
                        if (tv == .object) {
                            if (self.functions.get(full_name)) |func| {
                                if (func.is_generator) {
                                    try self.callStaticFunction(full_name, @intCast(resolved_ac), effective_called);
                                } else {
                                var new_vars: std.StringHashMapUnmanaged(Value) = .{};
                                try new_vars.put(self.allocator, "$this", tv);
                                if (func.is_variadic) {
                                    const fixed: usize = func.arity - 1;
                                    for (0..@min(resolved_ac, fixed)) |i| {
                                        try new_vars.put(self.allocator, func.params[i], self.stack[self.sp - resolved_ac + i]);
                                    }
                                    const rest_arr = try self.allocator.create(PhpArray);
                                    rest_arr.* = .{};
                                    try self.arrays.append(self.allocator, rest_arr);
                                    for (fixed..resolved_ac) |i| try rest_arr.append(self.allocator, self.stack[self.sp - resolved_ac + i]);
                                    try new_vars.put(self.allocator, func.params[fixed], .{ .array = rest_arr });
                                } else {
                                    for (0..@min(resolved_ac, func.arity)) |i| {
                                        try new_vars.put(self.allocator, func.params[i], self.stack[self.sp - resolved_ac + i]);
                                    }
                                    for (resolved_ac..func.arity) |i| {
                                        if (i < func.defaults.len) try new_vars.put(self.allocator, func.params[i], try self.resolveDefault(func.defaults[i]));
                                    }
                                }
                                const scs_ac: u8 = @intCast(@min(resolved_ac, 255));
                                self.saveFrameArgs(scs_ac);
                                self.sp -= resolved_ac;
                                self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars, .locals = try self.allocLocals(func, &new_vars), .func = func, .called_class = effective_called };
                                self.setFrameArgCount(scs_ac);
                                self.frames[self.frame_count].entry_sp = self.sp;
                    self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
                                }
                            } else {
                                const msg = try std.fmt.allocPrint(self.allocator, "Call to undefined method {s}::{s}()", .{ class_name, method_name });
                                try self.strings.append(self.allocator, msg);
                                if (try self.throwBuiltinException("Error", msg)) continue;
                                return error.RuntimeError;
                            }
                        } else {
                            try self.callNamedFunction(full_name, @intCast(resolved_ac));
                        }
                    } else {
                        try self.callNamedFunction(full_name, @intCast(resolved_ac));
                    }
                },

                .static_call_dynamic => {
                    const method_idx = self.readU16();
                    const arg_count = self.readByte();
                    const method_name = self.currentChunk().constants.items[method_idx].string;
                    const ac: usize = arg_count;
                    const class_val = self.stack[self.sp - ac - 1];
                    const raw_class_name = if (class_val == .string)
                        class_val.string
                    else if (class_val == .object)
                        class_val.object.class_name
                    else {
                        self.sp -= ac + 1;
                        const msg = try std.fmt.allocPrint(self.allocator, "{s}::method() requires a class name string", .{method_name});
                        try self.strings.append(self.allocator, msg);
                        if (try self.throwBuiltinException("Error", msg)) continue;
                        return error.RuntimeError;
                    };
                    // accept FQN with leading backslash
                    const class_name = if (raw_class_name.len > 0 and raw_class_name[0] == '\\') raw_class_name[1..] else raw_class_name;
                    if (!self.classes.contains(class_name)) {
                        try self.tryAutoload(class_name);
                    }
                    const full_name = self.resolveMethod(class_name, method_name) catch {
                        if (self.hasMethod(class_name, "__callStatic")) {
                            var args_arr = try self.allocator.create(PhpArray);
                            args_arr.* = .{};
                            try self.arrays.append(self.allocator, args_arr);
                            for (0..ac) |i| try args_arr.append(self.allocator, self.stack[self.sp - ac + i]);
                            self.sp -= ac + 1; // +1 for class name on stack
                            const cs_name = try self.resolveMethod(class_name, "__callStatic");
                            self.push(.{ .string = method_name });
                            self.push(.{ .array = args_arr });
                            try self.callStaticFunction(cs_name, 2, class_name);
                            continue;
                        }
                        const msg = std.fmt.allocPrint(self.allocator, "Call to undefined method {s}::{s}()", .{ class_name, method_name }) catch "Call to undefined method";
                        try self.strings.append(self.allocator, msg);
                        if (try self.throwBuiltinException("Error", msg)) continue;
                        self.setErrorMsg("Fatal error: Uncaught Error: {s}", .{msg});
                        return error.RuntimeError;
                    };
                    // remove class name from stack (shift args down)
                    var i: usize = 0;
                    while (i < ac) : (i += 1) {
                        self.stack[self.sp - ac - 1 + i] = self.stack[self.sp - ac + i];
                    }
                    self.sp -= 1;
                    try self.callStaticFunction(full_name, arg_count, class_name);
                },

                .static_call_dyn_method => {
                    const class_idx = self.readU16();
                    const arg_count = self.readByte();
                    var class_name = self.currentChunk().constants.items[class_idx].string;
                    var lsb_class: ?[]const u8 = null;
                    if (std.mem.eql(u8, class_name, "static")) {
                        class_name = self.resolveStaticClassName(class_name);
                    } else if (std.mem.eql(u8, class_name, "parent") or std.mem.eql(u8, class_name, "self")) {
                        if (std.mem.eql(u8, class_name, "parent")) {
                            const dc = self.parentResolvingClass();
                            if (dc) |defining| {
                                if (self.classes.get(defining)) |cls| {
                                    if (cls.parent) |p| class_name = p;
                                }
                                lsb_class = self.currentFrame().called_class orelse defining;
                            }
                        } else {
                            // self:: resolves to defining class for method lookup,
                            // but propagates called_class for LSB
                            lsb_class = self.currentFrame().called_class;
                            if (self.currentDefiningClass()) |dc| class_name = dc;
                        }
                    } else if (self.currentFrame().called_class) |cc| {
                        if (self.isAncestor(class_name, cc)) lsb_class = cc;
                    }
                    const effective_called = lsb_class orelse class_name;
                    if (!self.classes.contains(class_name)) {
                        try self.tryAutoload(class_name);
                    }
                    const ac: usize = arg_count;
                    const method_val = self.stack[self.sp - ac - 1];
                    const method_name = if (method_val == .string) method_val.string else {
                        self.setErrorMsg("Fatal error: dynamic method name must be a string", .{});
                        return error.RuntimeError;
                    };
                    const full_name = self.resolveMethod(class_name, method_name) catch {
                        if (self.hasMethod(class_name, "__callStatic")) {
                            var args_arr = try self.allocator.create(PhpArray);
                            args_arr.* = .{};
                            try self.arrays.append(self.allocator, args_arr);
                            for (0..ac) |i| try args_arr.append(self.allocator, self.stack[self.sp - ac + i]);
                            self.sp -= ac + 1;
                            const cs_name = try self.resolveMethod(class_name, "__callStatic");
                            self.push(.{ .string = method_name });
                            self.push(.{ .array = args_arr });
                            try self.callStaticFunction(cs_name, 2, effective_called);
                            continue;
                        }
                        const msg = std.fmt.allocPrint(self.allocator, "Call to undefined method {s}::{s}()", .{ class_name, method_name }) catch "Call to undefined method";
                        try self.strings.append(self.allocator, msg);
                        if (try self.throwBuiltinException("Error", msg)) continue;
                        self.setErrorMsg("Fatal error: Uncaught Error: {s}", .{msg});
                        return error.RuntimeError;
                    };
                    var i: usize = 0;
                    while (i < ac) : (i += 1) {
                        self.stack[self.sp - ac - 1 + i] = self.stack[self.sp - ac + i];
                    }
                    self.sp -= 1;
                    try self.callStaticFunction(full_name, arg_count, effective_called);
                },

                .static_call_dyn_both => {
                    const arg_count = self.readByte();
                    const ac: usize = arg_count;
                    const method_val = self.stack[self.sp - ac - 1];
                    const class_val = self.stack[self.sp - ac - 2];
                    const method_name = if (method_val == .string) method_val.string else {
                        self.setErrorMsg("Fatal error: dynamic method name must be a string", .{});
                        return error.RuntimeError;
                    };
                    var class_name = if (class_val == .string) class_val.string else if (class_val == .object) class_val.object.class_name else {
                        self.setErrorMsg("Fatal error: dynamic class name must be a string", .{});
                        return error.RuntimeError;
                    };
                    var lsb_class: ?[]const u8 = null;
                    if (std.mem.eql(u8, class_name, "static")) {
                        class_name = self.resolveStaticClassName(class_name);
                    } else if (std.mem.eql(u8, class_name, "parent") or std.mem.eql(u8, class_name, "self")) {
                        if (std.mem.eql(u8, class_name, "parent")) {
                            const dc = self.parentResolvingClass();
                            if (dc) |defining| {
                                if (self.classes.get(defining)) |cls| {
                                    if (cls.parent) |p| class_name = p;
                                }
                                lsb_class = self.currentFrame().called_class orelse defining;
                            }
                        } else {
                            // self:: resolves to defining class for method lookup,
                            // but propagates called_class for LSB
                            lsb_class = self.currentFrame().called_class;
                            if (self.currentDefiningClass()) |dc| class_name = dc;
                        }
                    } else if (self.currentFrame().called_class) |cc| {
                        if (self.isAncestor(class_name, cc)) lsb_class = cc;
                    }
                    const effective_called = lsb_class orelse class_name;
                    if (!self.classes.contains(class_name)) {
                        try self.tryAutoload(class_name);
                    }
                    const full_name = self.resolveMethod(class_name, method_name) catch {
                        if (self.hasMethod(class_name, "__callStatic")) {
                            var args_arr = try self.allocator.create(PhpArray);
                            args_arr.* = .{};
                            try self.arrays.append(self.allocator, args_arr);
                            for (0..ac) |i| try args_arr.append(self.allocator, self.stack[self.sp - ac + i]);
                            self.sp -= ac + 2;
                            const cs_name = try self.resolveMethod(class_name, "__callStatic");
                            self.push(.{ .string = method_name });
                            self.push(.{ .array = args_arr });
                            try self.callStaticFunction(cs_name, 2, effective_called);
                            continue;
                        }
                        const msg = std.fmt.allocPrint(self.allocator, "Call to undefined method {s}::{s}()", .{ class_name, method_name }) catch "Call to undefined method";
                        try self.strings.append(self.allocator, msg);
                        if (try self.throwBuiltinException("Error", msg)) continue;
                        self.setErrorMsg("Fatal error: Uncaught Error: {s}", .{msg});
                        return error.RuntimeError;
                    };
                    // remove class name and method name from stack (shift args down by 2)
                    var i: usize = 0;
                    while (i < ac) : (i += 1) {
                        self.stack[self.sp - ac - 2 + i] = self.stack[self.sp - ac + i];
                    }
                    self.sp -= 2;
                    try self.callStaticFunction(full_name, arg_count, effective_called);
                },

                .static_call_dyn_both_spread => {
                    // stack: [class_name, method_name, args_array]
                    const args_val = self.pop();
                    const method_val = self.pop();
                    const class_val = self.pop();
                    if (args_val != .array) {
                        self.error_msg = "Fatal error: argument unpacking requires an array";
                        return error.RuntimeError;
                    }
                    const method_name = if (method_val == .string) method_val.string else {
                        self.error_msg = "Fatal error: dynamic method name must be a string";
                        return error.RuntimeError;
                    };
                    var class_name = if (class_val == .string) class_val.string else if (class_val == .object) class_val.object.class_name else {
                        self.error_msg = "Fatal error: dynamic class name must be a string";
                        return error.RuntimeError;
                    };
                    class_name = self.resolveStaticClassName(class_name);
                    if (!self.classes.contains(class_name)) try self.tryAutoload(class_name);
                    const arr = args_val.array;
                    const full_name = self.resolveMethod(class_name, method_name) catch {
                        if (self.hasMethod(class_name, "__callStatic")) {
                            const cs_name = try self.resolveMethod(class_name, "__callStatic");
                            self.push(.{ .string = method_name });
                            self.push(args_val);
                            try self.callStaticFunction(cs_name, 2, class_name);
                            continue;
                        }
                        const msg = std.fmt.allocPrint(self.allocator, "Call to undefined method {s}::{s}()", .{ class_name, method_name }) catch "Call to undefined method";
                        try self.strings.append(self.allocator, msg);
                        if (try self.throwBuiltinException("Error", msg)) continue;
                        self.setErrorMsg("Fatal error: Uncaught Error: {s}", .{msg});
                        return error.RuntimeError;
                    };
                    for (arr.entries.items) |entry| self.push(entry.value);
                    const ac: u8 = @intCast(arr.entries.items.len);
                    try self.callStaticFunction(full_name, ac, class_name);
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
                        if (!self.classes.contains(class_name) and !self.interfaces.contains(class_name)) {
                            try self.tryAutoload(class_name);
                            if (self.getStaticProp(class_name, prop_name)) |val| {
                                self.push(val);
                            } else {
                                self.push(.null);
                            }
                        } else {
                            self.push(.null);
                        }
                    }
                },

                .get_static_prop_dyn_name => {
                    const class_idx = self.readU16();
                    const class_name = self.currentChunk().constants.items[class_idx].string;
                    const name_val = self.pop();
                    const prop_name: []const u8 = if (name_val == .string) name_val.string else "";
                    if (prop_name.len == 0) {
                        self.push(.null);
                    } else if (std.mem.eql(u8, prop_name, "class")) {
                        // Class::{'class'} resolves to the class name string,
                        // matching the static `Class::class` form
                        self.push(.{ .string = class_name });
                    } else if (self.getStaticProp(class_name, prop_name)) |val| {
                        self.push(val);
                    } else {
                        if (!self.classes.contains(class_name) and !self.interfaces.contains(class_name)) {
                            try self.tryAutoload(class_name);
                        }
                        if (self.getStaticProp(class_name, prop_name)) |val| {
                            self.push(val);
                        } else {
                            self.push(.null);
                        }
                    }
                },

                .get_static_prop_dynamic => {
                    const prop_idx = self.readU16();
                    const prop_name = self.currentChunk().constants.items[prop_idx].string;
                    const class_val = self.pop();
                    const class_name: []const u8 = switch (class_val) {
                        .string => |s| s,
                        .object => |o| o.class_name,
                        else => "",
                    };

                    if (class_name.len == 0) {
                        self.push(.null);
                    } else if (self.getStaticProp(class_name, prop_name)) |val| {
                        self.push(val);
                    } else {
                        if (!self.classes.contains(class_name) and !self.interfaces.contains(class_name)) {
                            try self.tryAutoload(class_name);
                            if (self.getStaticProp(class_name, prop_name)) |val| {
                                self.push(val);
                            } else {
                                self.push(.null);
                            }
                        } else {
                            self.push(.null);
                        }
                    }
                },

                .yield_value => {
                    const val = self.pop();
                    const gen = self.currentFrame().generator orelse {
                        self.setErrorMsg("Fatal error: Cannot use yield outside of a generator", .{});
                        return error.RuntimeError;
                    };
                    gen.current_value = val;
                    gen.current_key = .{ .int = gen.implicit_key };
                    gen.implicit_key += 1;
                    gen.ip = self.currentFrame().ip;
                    gen.vars = self.currentFrame().vars;
                    gen.ref_slots = self.currentFrame().ref_slots;
                    self.currentFrame().ref_slots = .{};
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
                        self.setErrorMsg("Fatal error: Cannot use yield outside of a generator", .{});
                        return error.RuntimeError;
                    };
                    gen.current_value = val;
                    gen.current_key = key;
                    if (key == .int and key.int >= gen.implicit_key) gen.implicit_key = key.int + 1;
                    gen.ip = self.currentFrame().ip;
                    gen.vars = self.currentFrame().vars;
                    gen.ref_slots = self.currentFrame().ref_slots;
                    self.currentFrame().ref_slots = .{};
                    self.saveFrameLocalsToGenerator(gen);
                    try self.saveGeneratorStack(gen);
                    self.saveGeneratorHandlers(gen);
                    gen.state = .suspended;
                    self.frame_count -= 1;
                    return;
                },

                .yield_from => {
                    var iterable = self.pop();
                    const outer_gen = self.currentFrame().generator orelse {
                        self.setErrorMsg("Fatal error: Cannot use yield outside of a generator", .{});
                        return error.RuntimeError;
                    };

                    // unwrap IteratorAggregate by calling getIterator
                    if (iterable == .object and self.hasMethod(iterable.object.class_name, "getIterator")) {
                        iterable = self.callMethod(iterable.object, "getIterator", &.{}) catch {
                            if (self.dispatchPendingException(base_frame)) continue;
                            return error.RuntimeError;
                        };
                    }

                    // drain Iterator-like objects into an array for delegation
                    if (iterable == .object and self.hasMethod(iterable.object.class_name, "rewind") and self.hasMethod(iterable.object.class_name, "valid") and self.hasMethod(iterable.object.class_name, "current") and self.hasMethod(iterable.object.class_name, "next")) {
                        const it = iterable.object;
                        _ = self.callMethod(it, "rewind", &.{}) catch {
                            if (self.dispatchPendingException(base_frame)) continue;
                            return error.RuntimeError;
                        };
                        const arr = try self.allocator.create(@import("value.zig").PhpArray);
                        arr.* = .{};
                        try self.arrays.append(self.allocator, arr);
                        const has_key = self.hasMethod(it.class_name, "key");
                        while (true) {
                            const v = self.callMethod(it, "valid", &.{}) catch {
                                if (self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            };
                            if (!v.isTruthy()) break;
                            const cur = self.callMethod(it, "current", &.{}) catch {
                                if (self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            };
                            if (has_key) {
                                const k = self.callMethod(it, "key", &.{}) catch {
                                    if (self.dispatchPendingException(base_frame)) continue;
                                    return error.RuntimeError;
                                };
                                try arr.set(self.allocator, @import("value.zig").Value.toArrayKey(k), cur);
                            } else {
                                try arr.append(self.allocator, cur);
                            }
                            _ = self.callMethod(it, "next", &.{}) catch {
                                if (self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            };
                        }
                        iterable = .{ .array = arr };
                    }

                    if (iterable == .generator) {
                        const inner = iterable.generator;
                        if (inner.state == .created) {
                            self.resumeGenerator(inner, .null) catch {
                                if (self.dispatchPendingException(base_frame)) continue;
                                return error.RuntimeError;
                            };
                        }

                        if (inner.state == .suspended) {
                            outer_gen.delegate = .{ .gen = inner };
                            outer_gen.current_value = inner.current_value;
                            outer_gen.current_key = inner.current_key;
                            // save ip past the yield_from opcode so we resume here
                            outer_gen.ip = self.currentFrame().ip;
                            outer_gen.vars = self.currentFrame().vars;
                            outer_gen.ref_slots = self.currentFrame().ref_slots;
                            self.currentFrame().ref_slots = .{};
                            self.saveFrameLocalsToGenerator(outer_gen);
                            try self.saveGeneratorStack(outer_gen);
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
                            outer_gen.ref_slots = self.currentFrame().ref_slots;
                            self.currentFrame().ref_slots = .{};
                            self.saveFrameLocalsToGenerator(outer_gen);
                            try self.saveGeneratorStack(outer_gen);
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
                            self.deinitFrameSlot(self.frame_count);
                        }
                        continue;
                    };
                    gen.return_value = val;
                    gen.current_value = .null;
                    gen.current_key = .null;
                    gen.state = .completed;
                    gen.vars = self.currentFrame().vars;
                    gen.ref_slots = self.currentFrame().ref_slots;
                    self.currentFrame().ref_slots = .{};
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
                    var target: ?*ClassDef = null;
                    if (self.classes.getPtr(class_name)) |cls| {
                        if (cls.static_props.contains(prop_name)) {
                            target = cls;
                        } else {
                            var parent: ?[]const u8 = cls.parent;
                            while (parent) |p| {
                                if (self.classes.getPtr(p)) |pcls| {
                                    if (pcls.static_props.contains(prop_name)) {
                                        target = pcls;
                                        break;
                                    }
                                    parent = pcls.parent;
                                } else break;
                            }
                            if (target == null) target = cls;
                        }
                    }
                    if (target) |cls| {
                        try cls.static_props.put(self.allocator, prop_name, val);
                    }
                },
            }
        }
    }

    fn resolveStaticClassName(self: *VM, name: []const u8) []const u8 {
        if (name.len > 0 and name[0] == '$') {
            const local_val = self.getLocalByName(name);
            if (local_val == .string) {
                const s = local_val.string;
                return if (s.len > 0 and s[0] == '\\') s[1..] else s;
            }
            if (self.currentFrame().vars.get(name)) |val| {
                if (val == .string) {
                    const s = val.string;
                    return if (s.len > 0 and s[0] == '\\') s[1..] else s;
                }
            }
            return name;
        }
        // direct FQN with leading backslash
        if (name.len > 0 and name[0] == '\\') return name[1..];
        if (std.mem.eql(u8, name, "static")) {
            const f = self.currentFrame();
            // called_class takes priority - set by explicit static calls like Base::get()
            if (f.called_class) |cc| return cc;
            if (f.vars.get("$this")) |this_val| {
                if (this_val == .object) return this_val.object.class_name;
            }
            if (f.func) |fn_info| {
                if (fn_info.locals_only) {
                    for (fn_info.slot_names, 0..) |sn, si| {
                        if (std.mem.eql(u8, sn, "$this") and si < f.locals.len and f.locals[si] == .object) {
                            return f.locals[si].object.class_name;
                        }
                    }
                }
            }
            if (self.currentDefiningClass()) |dc| return dc;
        } else if (std.mem.eql(u8, name, "self")) {
            // self:: from inside a trait static method needs to know WHICH
            // using-class we were invoked through. called_class on the active
            // frame carries that (set when X::method() is dispatched).
            // currentDefiningClass falls back to chunk identity which is
            // ambiguous when multiple classes share the same trait chunk
            if (self.currentFrame().called_class) |cc| {
                if (self.currentDefiningClass()) |dc| {
                    if (self.traits.contains(dc)) return cc;
                }
                return cc;
            }
            if (self.currentDefiningClass()) |dc| return dc;
        } else if (std.mem.eql(u8, name, "parent")) {
            if (self.parentResolvingClass()) |dc| {
                if (self.classes.get(dc)) |cls| {
                    if (cls.parent) |p| return p;
                }
            }
        }
        return name;
    }

    pub fn getStaticProp(self: *VM, class_name: []const u8, prop_name: []const u8) ?Value {
        var current: ?[]const u8 = class_name;
        while (current) |cn| {
            if (self.classes.getPtr(cn)) |cls| {
                if (cls.static_props.get(prop_name)) |val| return val;
                for (cls.interfaces.items) |iface| {
                    if (self.getStaticProp(iface, prop_name)) |val| return val;
                }
                current = cls.parent;
            } else {
                self.tryAutoload(cn) catch {};
                if (self.classes.getPtr(cn)) |cls| {
                    if (cls.static_props.get(prop_name)) |val| return val;
                    for (cls.interfaces.items) |iface| {
                        if (self.getStaticProp(iface, prop_name)) |val| return val;
                    }
                    current = cls.parent;
                } else break;
            }
        }
        return null;
    }

    // poll the execution deadline. backed by a tick counter so the actual
    // monotonic-clock read only happens once every ~4096 backwards jumps -
    // overhead under a percent of a tight loop but still well under a
    // millisecond of slop on the deadline
    pub inline fn pollExecutionDeadline(self: *VM) !void {
        if (self.execution_deadline_ns == 0) return;
        self.deadline_tick_counter +%= 1;
        if (self.deadline_tick_counter & 0xFFF != 0) return;
        const now_ns = std.time.nanoTimestamp();
        if (now_ns < self.execution_deadline_ns) return;
        const unit: []const u8 = if (self.execution_limit_seconds == 1) "second" else "seconds";
        const msg = try std.fmt.allocPrint(self.allocator, "Maximum execution time of {d} {s} exceeded", .{ self.execution_limit_seconds, unit });
        try self.strings.append(self.allocator, msg);
        try self.setPendingException("Error", msg);
        // PHP makes this fatal uncatchable: even user try/catch around an
        // infinite loop won't keep the script alive past the deadline
        self.uncatchable_fatal = true;
        // disarm so a single overrun isn't reported repeatedly while the
        // stack unwinds toward the run-loop boundary
        self.execution_deadline_ns = 0;
        return error.RuntimeError;
    }

    pub fn setExecutionLimit(self: *VM, seconds: i64) void {
        self.execution_limit_seconds = seconds;
        if (seconds <= 0) {
            self.execution_deadline_ns = 0;
            return;
        }
        const now_ns = std.time.nanoTimestamp();
        self.execution_deadline_ns = @intCast(now_ns + @as(i128, seconds) * std.time.ns_per_s);
        self.deadline_tick_counter = 0;
    }

    pub fn setPendingException(self: *VM, class_name: []const u8, message: []const u8) !void {
        const obj = try self.allocator.create(PhpObject);
        obj.* = .{ .class_name = class_name };
        try obj.set(self.allocator, "message", .{ .string = message });
        try obj.set(self.allocator, "code", .{ .int = 0 });
        try obj.set(self.allocator, "file", .{ .string = self.file_path });
        const ip = if (self.frame_count > 0) self.currentFrame().ip else 0;
        const line: i64 = if (self.frame_count > 0)
            if (self.currentChunk().getSourceLocation(if (ip > 0) ip - 1 else 0, self.source)) |loc| @intCast(loc.line) else 0
        else
            0;
        try obj.set(self.allocator, "line", .{ .int = line });
        try self.objects.append(self.allocator, obj);
        self.pending_exception = .{ .object = obj };
    }

    pub const OffsetOp = enum { access, isset_or_empty, unset };

    pub fn throwOffsetKeyType(self: *VM, key: Value, op: OffsetOp) RuntimeError!bool {
        const tn: []const u8 = if (key == .object) key.object.class_name else "array";
        const msg = switch (op) {
            .access => std.fmt.allocPrint(self.allocator, "Cannot access offset of type {s} on array", .{tn}),
            .isset_or_empty => std.fmt.allocPrint(self.allocator, "Cannot access offset of type {s} in isset or empty", .{tn}),
            .unset => std.fmt.allocPrint(self.allocator, "Cannot unset offset of type {s} on array", .{tn}),
        } catch return error.RuntimeError;
        try self.strings.append(self.allocator, msg);
        return self.throwBuiltinException("TypeError", msg);
    }

    // close a suspended generator: inject a synthetic exception so any open
    // try/finally blocks run during the unwind. swallow the marker if it
    // propagates out (matches PHP's close-on-foreach-break semantics). a
    // different exception raised by finally still propagates to the caller
    pub fn closeGenerator(self: *VM, gen: *Generator, base_frame: usize) RuntimeError!void {
        if (gen.state != .suspended) return;
        const obj = try self.allocator.create(PhpObject);
        obj.* = .{ .class_name = "Exception" };
        try obj.set(self.allocator, "message", .{ .string = "Generator closed" });
        try obj.set(self.allocator, "code", .{ .int = 0 });
        try self.objects.append(self.allocator, obj);
        const marker_ptr = @intFromPtr(obj);

        gen.pending_throw = .{ .object = obj };
        self.resumeGenerator(gen, .null) catch |err| {
            // RuntimeError is expected when the marker (or another exception)
            // exits the generator with no handler. handle the bookkeeping below
            if (err != error.RuntimeError) return err;
        };
        if (self.pending_exception) |ex| {
            if (ex == .object and @intFromPtr(ex.object) == marker_ptr) {
                self.pending_exception = null;
            } else {
                // finally raised something other than our marker - dispatch into
                // the caller's handler chain
                _ = self.dispatchPendingException(base_frame);
            }
        }
    }

    /// PHP 8 rejects non-numeric strings, arrays (except for +), and objects
    /// without __toString as arithmetic operands with TypeError. returns true
    /// when the throw was caught in-frame and the caller should `continue`
    pub fn checkArithOperands(self: *VM, a: Value, b: Value, comptime op: []const u8) RuntimeError!bool {
        if (isArithOperand(a) and isArithOperand(b)) {
            if (a == .string and isPartialNumericString(a.string)) self.emitNonNumericWarning();
            if (b == .string and isPartialNumericString(b.string)) self.emitNonNumericWarning();
            return false;
        }
        const tn_a = arithTypeName(a);
        const tn_b = arithTypeName(b);
        const msg = try std.fmt.allocPrint(self.allocator, "Unsupported operand types: {s} " ++ op ++ " {s}", .{ tn_a, tn_b });
        try self.strings.append(self.allocator, msg);
        if (try self.throwBuiltinException("TypeError", msg)) return true;
        return error.RuntimeError;
    }

    fn bitwiseStrings(self: *VM, a: []const u8, b: []const u8, comptime op: enum { and_op, or_op, xor_op }) ![]const u8 {
        // PHP byte-wise op on two strings: AND truncates to shorter length,
        // OR and XOR pad shorter side with NUL bytes
        const len = switch (op) {
            .and_op => @min(a.len, b.len),
            .or_op, .xor_op => @max(a.len, b.len),
        };
        const out = try self.allocator.alloc(u8, len);
        try self.strings.append(self.allocator, out);
        for (0..len) |i| {
            const ca: u8 = if (i < a.len) a[i] else 0;
            const cb: u8 = if (i < b.len) b[i] else 0;
            out[i] = switch (op) {
                .and_op => ca & cb,
                .or_op => ca | cb,
                .xor_op => ca ^ cb,
            };
        }
        return out;
    }

    fn isArithOperand(v: Value) bool {
        return switch (v) {
            .int, .float, .bool, .null => true,
            // PHP throws TypeError only for strings with no leading-numeric
            // prefix. '5abc' / '  5  ' / '0xFF' all pass (PHP emits a warning
            // and uses the numeric prefix, which is 0 for '0xFF'). truly
            // alphabetic strings like 'abc' do not pass
            .string => |s| stringHasLeadingNumericish(s),
            else => false,
        };
    }

    fn isPartialNumericString(s: []const u8) bool {
        // string with a leading numeric prefix followed by non-numeric garbage
        // (PHP emits "A non-numeric value encountered" when arithmetic uses
        // such a string). pure-numeric and pure-non-numeric strings don't qualify
        var i: usize = 0;
        while (i < s.len and (s[i] == ' ' or s[i] == '\t' or s[i] == '\n' or s[i] == '\r' or s[i] == '\x0b' or s[i] == '\x0c')) i += 1;
        if (i >= s.len) return false;
        if (s[i] == '+' or s[i] == '-') i += 1;
        if (i >= s.len) return false;
        var saw_digit = false;
        while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) saw_digit = true;
        if (i < s.len and s[i] == '.') {
            i += 1;
            while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) saw_digit = true;
        }
        if (!saw_digit) return false;
        if (i < s.len and (s[i] == 'e' or s[i] == 'E')) {
            const save = i;
            i += 1;
            if (i < s.len and (s[i] == '+' or s[i] == '-')) i += 1;
            const exp_start = i;
            while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) {}
            if (i == exp_start) i = save; // no exponent digits, roll back so 'e' is trailing garbage
        }
        // skip trailing whitespace (PHP treats "  5  " as fully numeric)
        while (i < s.len and (s[i] == ' ' or s[i] == '\t' or s[i] == '\n' or s[i] == '\r' or s[i] == '\x0b' or s[i] == '\x0c')) i += 1;
        return i < s.len;
    }

    fn emitNonNumericWarning(self: *VM) void {
        self.emitWarning("A non-numeric value encountered");
    }

    fn emitUndefinedKeyWarning(self: *VM, key: PhpArray.Key) void {
        const msg = switch (key) {
            .int => |n| std.fmt.allocPrint(self.allocator, "Undefined array key {d}", .{n}) catch return,
            .string => |s| std.fmt.allocPrint(self.allocator, "Undefined array key \"{s}\"", .{s}) catch return,
        };
        self.strings.append(self.allocator, msg) catch {};
        self.emitWarning(msg);
    }


    pub fn emitWarning(self: *VM, msg: []const u8) void {
        const ip = if (self.frame_count > 0) self.currentFrame().ip else 0;
        const line: i64 = if (self.frame_count > 0)
            if (self.currentChunk().getSourceLocation(if (ip > 0) ip - 1 else 0, self.source)) |loc| @intCast(loc.line) else 0
        else
            0;
        const file = self.file_path;
        if (self.error_silenced_depth != 0 or (self.error_reporting_level & 2) == 0) return;
        if (self.output.items.len > 0) {
            const stdout_file = std.fs.File{ .handle = 1 };
            _ = stdout_file.write(self.output.items) catch {};
            self.output.clearRetainingCapacity();
        }
        const stderr_text = std.fmt.allocPrint(self.allocator, "PHP Warning:  {s} in {s} on line {d}\n", .{ msg, file, line }) catch return;
        self.strings.append(self.allocator, stderr_text) catch {};
        const stderr_file = std.fs.File{ .handle = 2 };
        _ = stderr_file.write(stderr_text) catch {};
        const stdout_text = std.fmt.allocPrint(self.allocator, "\nWarning: {s} in {s} on line {d}\n", .{ msg, file, line }) catch return;
        self.strings.append(self.allocator, stdout_text) catch {};
        self.output.appendSlice(self.allocator, stdout_text) catch {};
    }

    fn stringHasLeadingNumericish(s: []const u8) bool {
        var i: usize = 0;
        while (i < s.len and (s[i] == ' ' or s[i] == '\t' or s[i] == '\n' or s[i] == '\r')) i += 1;
        if (i >= s.len) return false;
        if (s[i] == '+' or s[i] == '-') i += 1;
        if (i >= s.len) return false;
        return s[i] >= '0' and s[i] <= '9' or s[i] == '.';
    }

    fn arithTypeName(v: Value) []const u8 {
        return switch (v) {
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

    pub fn throwBuiltinException(self: *VM, class_name: []const u8, message: []const u8) !bool {
        const obj = try self.allocator.create(PhpObject);
        obj.* = .{ .class_name = class_name };
        try obj.set(self.allocator, "message", .{ .string = message });
        try obj.set(self.allocator, "code", .{ .int = 0 });
        // file/line should reflect the throwing frame (often a function in a
        // required file), not the top-level script. fall back to self.file_path
        // when the current frame has no associated source
        const frame_file: []const u8 = if (self.frame_count > 0)
            if (self.currentFrame().func) |fn_| fn_.file_path else self.file_path
        else
            self.file_path;
        try obj.set(self.allocator, "file", .{ .string = if (frame_file.len > 0) frame_file else self.file_path });
        const ip = if (self.frame_count > 0) self.currentFrame().ip else 0;
        const line: i64 = if (self.frame_count > 0)
            if (self.currentChunk().getSourceLocation(if (ip > 0) ip - 1 else 0, self.source)) |loc| @intCast(loc.line) else 0
        else
            0;
        try obj.set(self.allocator, "line", .{ .int = line });
        try self.objects.append(self.allocator, obj);

        if (self.handler_count <= self.handler_floor) {
            self.pending_exception = .{ .object = obj };
            return false;
        }

        const handler = self.exception_handlers[self.handler_count - 1];

        // handler belongs to an outer runLoop - propagate up
        if (handler.frame_count <= self.run_base_frame and self.run_base_frame > 0) {
            self.pending_exception = .{ .object = obj };
            return false;
        }

        self.handler_count -= 1;

        while (self.frame_count > handler.frame_count) {
            self.frame_count -= 1;
            self.deinitFrameSlot(self.frame_count);
        }

        self.sp = handler.sp;
        self.push(.{ .object = obj });
        self.currentFrame().ip = handler.catch_ip;
        return true;
    }

    fn dispatchPendingException(self: *VM, base_frame: usize) bool {
        if (self.uncatchable_fatal) return false;
        const exc = self.pending_exception orelse return false;
        if (self.handler_count <= self.handler_floor) return false;
        const handler = self.exception_handlers[self.handler_count - 1];
        if (handler.frame_count <= base_frame and base_frame > 0) return false;
        self.pending_exception = null;
        self.handler_count -= 1;
        while (self.frame_count > handler.frame_count) {
            self.frame_count -= 1;
            self.deinitFrameSlot(self.frame_count);
        }
        self.sp = handler.sp;
        self.push(exc);
        self.currentFrame().ip = handler.catch_ip;
        return true;
    }

    pub fn resumeGenerator(self: *VM, gen: *Generator, sent_value: Value) RuntimeError!void {
        if (gen.state == .completed) return;

        // if delegating, advance the delegate instead of resuming bytecode
        if (gen.delegate) |*del| {
            switch (del.*) {
                .gen => |inner| {
                    // throw() on the outer generator forwards into the inner
                    // delegate so try/catch around `yield from` works PHP-style
                    if (gen.pending_throw) |ex| {
                        gen.pending_throw = null;
                        inner.pending_throw = ex;
                    }
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
            .ref_slots = gen.ref_slots,
        };
        gen.ref_slots = .{};
        self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;

        self.restoreGeneratorHandlers(gen);

        if (gen.ip > 0) {
            self.push(sent_value);
        }

        if (gen.pending_throw) |ex| {
            gen.pending_throw = null;
            self.pending_exception = ex;
            // try to dispatch within the generator's frame; if no handler, the exception
            // will propagate when runUntilFrame catches the eventual error
            if (self.dispatchPendingException(return_frame)) {
                // handler found - runLoop will continue from catch block
            } else {
                // no handler - generator completes with the exception pending
                gen.state = .completed;
                self.handler_count = saved_handler_count;
                while (self.frame_count > return_frame) {
                    self.frame_count -= 1;
                    self.deinitFrameSlot(self.frame_count);
                }
                self.sp = saved_sp;
                self.handler_floor = prev_floor;
                return error.RuntimeError;
            }
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
                self.deinitFrameSlot(self.frame_count);
            }
            self.sp = saved_sp;
            if (self.pending_exception != null) {
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

    fn setLocalGlobal(self: *VM, slot: u16, val: Value, frame: *CallFrame) !void {
        if (slot < self.global_slot_names.len) {
            const name = self.global_slot_names[slot];
            if (name.len > 0) {
                if (frame.ref_slots.count() > 0) {
                    if (frame.ref_slots.get(name)) |cell| {
                        cell.* = val;
                        try self.propagateCellWrite(cell, val);
                    }
                }
                try frame.vars.put(self.allocator, name, val);
                // $GLOBALS is a live view of top-frame variables. mirror writes
                // back so $GLOBALS[$key] picks up the new value
                if (self.globals_array) |ga| {
                    if (name.len > 1 and name[0] == '$') {
                        try ga.set(self.allocator, .{ .string = name[1..] }, val);
                    }
                }
                // keep the shared global-cell (used by `global $name` inside
                // functions) in sync with the top-frame write
                if (self.globals_cells.get(name)) |cell| {
                    cell.* = val;
                }
            }
        }
        self.global_vars_dirty = true;
    }

    // propagate a write to $GLOBALS[$key] into every frame that has `global $key`
    // declared (including the top frame). PHP models $GLOBALS as a live view of
    // the global table, so a write must be visible to every active `global`
    // binding, not just the top-level script frame.
    fn mirrorGlobalsWrite(self: *VM, key: []const u8, val: Value) !void {
        const dollar_name = std.fmt.allocPrint(self.allocator, "${s}", .{key}) catch return;
        try self.strings.append(self.allocator, dollar_name);

        // top frame: vars + locals (slot lookup via top_slot_names — must
        // not use global_slot_names because it's overridden inside require)
        if (self.frame_count > 0) {
            const top = &self.frames[0];
            try top.vars.put(self.allocator, dollar_name, val);
            for (self.top_slot_names, 0..) |sn, i| {
                if (std.mem.eql(u8, sn, dollar_name)) {
                    if (i < top.locals.len) top.locals[i] = val;
                    break;
                }
            }
        }

        // shared global cell - so `global $key` inside any function picks
        // up writes done through $GLOBALS at the top level
        if (self.globals_cells.get(dollar_name)) |cell| {
            cell.* = val;
        }

        // any function frame with an active `global $key` declaration
        for (self.global_vars.items) |entry| {
            if (!std.mem.eql(u8, entry.var_name, dollar_name)) continue;
            if (entry.frame_depth == 0 or entry.frame_depth > self.frame_count) continue;
            const frame = &self.frames[entry.frame_depth - 1];
            try frame.vars.put(self.allocator, dollar_name, val);
            if (frame.func) |func| {
                for (func.slot_names, 0..) |sn, i| {
                    if (std.mem.eql(u8, sn, dollar_name)) {
                        if (i < frame.locals.len) frame.locals[i] = val;
                        break;
                    }
                }
            }
        }
    }

    fn syncGlobalLocalsToVars(self: *VM) !void {
        if (!self.global_vars_dirty) return;
        self.global_vars_dirty = false;
        const frame = &self.frames[0];
        for (self.top_slot_names, 0..) |name, i| {
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
                for (self.top_slot_names, 0..) |sn, si| {
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
        const method_name = self.resolveMethod(obj.class_name, "__toString") catch {
            // PHP: 'Object of class X could not be converted to string'.
            // throw a catchable Error so user code wrapping the access in
            // try/catch can recover; non-catching code falls through to a
            // runtime error like any other uncaught exception
            const msg = try std.fmt.allocPrint(self.allocator, "Object of class {s} could not be converted to string", .{obj.class_name});
            try self.strings.append(self.allocator, msg);
            try self.setPendingException("Error", msg);
            return error.RuntimeError;
        };
        if (self.functions.get(method_name)) |func| {
            var new_vars: std.StringHashMapUnmanaged(Value) = .{};
            try new_vars.put(self.allocator, "$this", .{ .object = obj });
            self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars, .locals = try self.allocLocals(func, &new_vars), .func = func };
            self.frames[self.frame_count].entry_sp = self.sp;
            self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
            try self.runLoop(self.frame_count - 1);
            const result = self.pop();
            if (result == .string) return result.string;
            var buf = std.ArrayListUnmanaged(u8){};
            try result.format(&buf, self.allocator);
            const s = try buf.toOwnedSlice(self.allocator);
            try self.strings.append(self.allocator, s);
            return s;
        }
        if (self.native_fns.get(method_name)) |native| {
            const prev_this = self.currentFrame().vars.get("$this");
            self.currentFrame().vars.put(self.allocator, "$this", .{ .object = obj }) catch return "Object";
            defer {
                if (prev_this) |pt| {
                    self.currentFrame().vars.put(self.allocator, "$this", pt) catch {};
                } else {
                    _ = self.currentFrame().vars.remove("$this");
                }
            }
            var ctx = self.makeContext(null);
            const result = native(&ctx, &.{}) catch return "Object";
            if (result == .string) return result.string;
            var buf = std.ArrayListUnmanaged(u8){};
            result.format(&buf, self.allocator) catch return "Object";
            const s = buf.toOwnedSlice(self.allocator) catch return "Object";
            self.strings.append(self.allocator, s) catch return "Object";
            return s;
        }
        return "Object";
    }

    // ==================================================================
    // opcode handlers (extracted from runLoop for readability)
    // ==================================================================

    fn handleClassDecl(self: *VM) RuntimeError!void {
        const class_modifiers = self.readByte();
        const name_idx = self.readU16();
        const class_name = self.currentChunk().constants.items[name_idx].string;
        const start_line = self.readU32();
        const end_line = self.readU32();
        const doc_idx = self.readU16();
        const method_count = self.readU16();

        var def = ClassDef{ .name = class_name };
        def.is_abstract = (class_modifiers & 1) != 0;
        def.is_final = (class_modifiers & 2) != 0;
        def.is_readonly = (class_modifiers & 4) != 0;
        // prefer the executing frame's script_path so classes declared in
        // required files report the right file via Reflection. fall back to
        // the VM's top-level file_path for the main script
        def.file_path = blk: {
            if (self.frame_count > 0) {
                const sp = self.currentFrame().script_path;
                if (sp.len > 0) break :blk sp;
            }
            break :blk self.file_path;
        };
        def.start_line = start_line;
        def.end_line = end_line;
        if (doc_idx != 0xffff) def.doc_comment = self.currentChunk().constants.items[doc_idx].string;

        for (0..method_count) |_| {
            const mi = self.readMethodInfo();
            try def.addMethod(self.allocator, mi[1]);
        }

        const prop_count = self.readU16();
        var prop_names: [256][]const u8 = undefined;
        var prop_has_default: [256]u8 = undefined;
        var prop_vis: [256]ClassDef.Visibility = undefined;
        var prop_set_vis: [256]ClassDef.Visibility = undefined;
        var prop_readonly: [256]bool = .{false} ** 256;
        var prop_promoted: [256]bool = .{false} ** 256;
        var prop_type: [256][]const u8 = .{""} ** 256;
        var prop_doc: [256][]const u8 = .{""} ** 256;
        for (0..prop_count) |pi| {
            const pname_idx = self.readU16();
            prop_names[pi] = self.currentChunk().constants.items[pname_idx].string;
            prop_has_default[pi] = self.readByte();
            const vis_byte = self.readByte();
            prop_vis[pi] = @enumFromInt(vis_byte & 0x03);
            prop_readonly[pi] = (vis_byte & 0x04) != 0;
            const has_asymm = (vis_byte & 0x20) != 0;
            prop_set_vis[pi] = if (has_asymm) @enumFromInt((vis_byte >> 3) & 0x03) else prop_vis[pi];
            prop_promoted[pi] = (vis_byte & 0x40) != 0;
            const type_idx = self.readU16();
            prop_type[pi] = if (type_idx == 0xffff) "" else self.currentChunk().constants.items[type_idx].string;
            const doc_idx_p = self.readU16();
            prop_doc[pi] = if (doc_idx_p == 0xffff) "" else self.currentChunk().constants.items[doc_idx_p].string;
        }

        const static_prop_count = self.readU16();
        var sprop_names: [256][]const u8 = undefined;
        var sprop_has_default: [256]u8 = undefined;
        var sprop_is_const: [256]u8 = undefined;
        var sprop_visibility: [256]u8 = undefined;
        var sprop_type: [256][]const u8 = .{""} ** 256;
        var sprop_doc: [256][]const u8 = .{""} ** 256;
        for (0..static_prop_count) |pi| {
            const pname_idx = self.readU16();
            sprop_names[pi] = self.currentChunk().constants.items[pname_idx].string;
            sprop_has_default[pi] = self.readByte();
            sprop_visibility[pi] = self.readByte();
            sprop_is_const[pi] = self.readByte();
            const t_idx = self.readU16();
            sprop_type[pi] = if (t_idx == 0xffff) "" else self.currentChunk().constants.items[t_idx].string;
            const sd_idx = self.readU16();
            sprop_doc[pi] = if (sd_idx == 0xffff) "" else self.currentChunk().constants.items[sd_idx].string;
        }

        const sdefaults = self.popDefaults(256, sprop_has_default[0..static_prop_count]);
        const defaults = self.popDefaults(256, prop_has_default[0..prop_count]);

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
                .has_default = prop_has_default[pi] == 1,
                .visibility = prop_vis[pi],
                .set_visibility = prop_set_vis[pi],
                .is_readonly = prop_readonly[pi] or def.is_readonly,
                .is_promoted = prop_promoted[pi],
                .type_str = prop_type[pi],
                .doc_comment = prop_doc[pi],
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
            if (sprop_type[pi].len > 0) try def.static_prop_types.put(self.allocator, sprop_names[pi], sprop_type[pi]);
            const vis_byte = sprop_visibility[pi] & 0x03;
            if (vis_byte != 0) {
                try def.const_visibility.put(self.allocator, sprop_names[pi], @enumFromInt(vis_byte));
            }
            if (sprop_is_const[pi] == 1) {
                if (!def.constant_names.contains(sprop_names[pi])) {
                    try def.constant_order.append(self.allocator, sprop_names[pi]);
                }
                try def.constant_names.put(self.allocator, sprop_names[pi], {});
                if ((sprop_visibility[pi] & 0x10) != 0) {
                    try def.const_final.put(self.allocator, sprop_names[pi], {});
                }
            }
        }

        const parent_idx = self.readU16();
        if (parent_idx != 0xffff) {
            const parent_name = self.currentChunk().constants.items[parent_idx].string;
            def.parent = parent_name;
            if (self.classes.get(parent_name)) |parent_cls| {
                if (parent_cls.is_final) {
                    const msg = try std.fmt.allocPrint(self.allocator, "Class {s} cannot extend final class {s}", .{ class_name, parent_name });
                    try self.strings.append(self.allocator, msg);
                    self.error_msg = msg;
                    return error.RuntimeError;
                }
                if (parent_cls.is_readonly and !def.is_readonly) {
                    const msg = try std.fmt.allocPrint(self.allocator, "Non-readonly class {s} cannot extend readonly class {s}", .{ class_name, parent_name });
                    try self.strings.append(self.allocator, msg);
                    self.error_msg = msg;
                    return error.RuntimeError;
                }
                if (def.is_readonly and !parent_cls.is_readonly) {
                    const msg = try std.fmt.allocPrint(self.allocator, "Readonly class {s} cannot extend non-readonly class {s}", .{ class_name, parent_name });
                    try self.strings.append(self.allocator, msg);
                    self.error_msg = msg;
                    return error.RuntimeError;
                }
                // reject overrides of final methods
                var pcls_iter = parent_cls.methods.iterator();
                while (pcls_iter.next()) |pe| {
                    if (!pe.value_ptr.is_final) continue;
                    if (def.methods.get(pe.key_ptr.*)) |_| {
                        const msg = try std.fmt.allocPrint(self.allocator, "Cannot override final method {s}::{s}()", .{ parent_name, pe.key_ptr.* });
                        try self.strings.append(self.allocator, msg);
                        self.error_msg = msg;
                        return error.RuntimeError;
                    }
                }
            }
        }


        const iface_count = self.readByte();
        for (0..iface_count) |_| {
            const iname_idx = self.readU16();
            try def.interfaces.append(self.allocator, self.currentChunk().constants.items[iname_idx].string);
        }

        const trait_count = self.readByte();
        var trait_names: [64][]const u8 = undefined;
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
                const alias_name = self.currentChunk().constants.items[self.readU16()].string;
                const vis_kind = self.readByte();
                alias_rules[alias_count] = .{ .method = method_name, .trait = rule_trait, .alias = alias_name, .visibility = vis_kind };
                alias_count += 1;
            }
        }

        for (trait_names[0..trait_count]) |trait_name| {
            try self.applyTrait(&def, class_name, trait_name, alias_rules[0..alias_count], insteadof_rules[0..insteadof_count]);
            try def.used_traits.append(self.allocator, trait_name);
        }

        // class-level attributes
        const class_attrs = try self.readAttributeDefs();
        for (class_attrs) |a| try def.attributes.append(self.allocator, a);
        if (class_attrs.len > 0) self.allocator.free(class_attrs);

        // method attributes
        const method_attr_count = self.readByte();
        for (0..method_attr_count) |_| {
            const ma_name_idx = self.readU16();
            const ma_name = self.currentChunk().constants.items[ma_name_idx].string;
            const ma_attrs = try self.readAttributeDefs();
            try def.method_attributes.put(self.allocator, ma_name, ma_attrs);
        }

        // property attributes
        const prop_attr_count = self.readByte();
        for (0..prop_attr_count) |_| {
            const pa_name_idx = self.readU16();
            const pa_name = self.currentChunk().constants.items[pa_name_idx].string;
            const pa_attrs = try self.readAttributeDefs();
            try def.property_attributes.put(self.allocator, pa_name, pa_attrs);
        }

        // constant attributes
        const const_attr_count = self.readByte();
        for (0..const_attr_count) |_| {
            const ca_name_idx = self.readU16();
            const ca_name = self.currentChunk().constants.items[ca_name_idx].string;
            const ca_attrs = try self.readAttributeDefs();
            try def.constant_attributes.put(self.allocator, ca_name, ca_attrs);
        }

        // parameter attributes
        const param_attr_method_count = self.readByte();
        for (0..param_attr_method_count) |_| {
            const pam_name_idx = self.readU16();
            const pam_method = self.currentChunk().constants.items[pam_name_idx].string;
            const pam_param_count = self.readByte();
            for (0..pam_param_count) |_| {
                const pap_name_idx = self.readU16();
                const pap_name = self.currentChunk().constants.items[pap_name_idx].string;
                const pap_attrs = try self.readAttributeDefs();
                var key_buf: [256]u8 = undefined;
                const key = std.fmt.bufPrint(&key_buf, "{s}:{s}", .{ pam_method, pap_name }) catch continue;
                const owned_key = try self.allocator.dupe(u8, key);
                try def.param_attributes.put(self.allocator, owned_key, pap_attrs);
            }
        }

        if (def.parent) |parent_name| {
            if (!self.classes.contains(parent_name)) try self.tryAutoload(parent_name);
        }

        def.slot_layout = try self.buildSlotLayout(&def);
        // composer's autoloader uses `include` (not require_once), so a class
        // file can be re-executed multiple times during a single autoload chain.
        // each re-execution rebuilds slot_layout and the class def. the LAST
        // a non-abstract class cannot declare any abstract methods directly.
        // PHP fatals here: 'Class X declares abstract method Y() and must
        // therefore be declared abstract'
        if (!def.is_abstract) {
            var di = def.methods.iterator();
            while (di.next()) |e| {
                if (e.value_ptr.is_abstract) {
                    const msg = try std.fmt.allocPrint(self.allocator, "Class {s} declares abstract method {s}() and must therefore be declared abstract", .{ class_name, e.key_ptr.* });
                    try self.strings.append(self.allocator, msg);
                    self.error_msg = msg;
                    return error.RuntimeError;
                }
            }
        }

        // unless this class is itself abstract, every abstract method inherited
        // from the parent chain (and required by any implemented interface)
        // must be implemented by a non-abstract method
        if (!def.is_abstract) {
            var seen_abstract = std.StringHashMapUnmanaged([]const u8){};
            defer seen_abstract.deinit(self.allocator);
            var current_parent: ?[]const u8 = def.parent;
            while (current_parent) |pn| {
                if (self.classes.get(pn)) |pc| {
                    var pi = pc.methods.iterator();
                    while (pi.next()) |pe| {
                        if (!pe.value_ptr.is_abstract) continue;
                        if (seen_abstract.contains(pe.key_ptr.*)) continue;
                        try seen_abstract.put(self.allocator, pe.key_ptr.*, pn);
                    }
                    current_parent = pc.parent;
                } else break;
            }
            // walk both the class's direct interfaces AND any interfaces
            // declared by its parent chain (an `abstract class Foo implements Bar`
            // means subclasses of Foo must satisfy Bar even though Foo's subclass
            // doesn't `implements Bar` directly)
            var iface_walk_parent: ?[]const u8 = class_name;
            while (iface_walk_parent) |cn| {
                if (self.classes.get(cn)) |cd| {
                    for (cd.interfaces.items) |iname| {
                        var current_iface: ?[]const u8 = iname;
                        while (current_iface) |in| {
                            if (self.interfaces.get(in)) |idef| {
                                for (idef.methods.items) |mname| {
                                    if (seen_abstract.contains(mname)) continue;
                                    try seen_abstract.put(self.allocator, mname, in);
                                }
                                current_iface = idef.parent;
                            } else break;
                        }
                    }
                    iface_walk_parent = cd.parent;
                } else break;
            }
            var sa_iter = seen_abstract.iterator();
            while (sa_iter.next()) |se| {
                // walk parent chain looking for a non-abstract implementation
                var found_concrete = false;
                if (def.methods.get(se.key_ptr.*)) |m| {
                    if (!m.is_abstract) found_concrete = true;
                }
                if (!found_concrete) {
                    var pp: ?[]const u8 = def.parent;
                    while (pp) |pn2| {
                        if (self.classes.get(pn2)) |pc| {
                            if (pc.methods.get(se.key_ptr.*)) |pm| {
                                if (!pm.is_abstract) { found_concrete = true; break; }
                            }
                            pp = pc.parent;
                        } else break;
                    }
                }
                if (!found_concrete) {
                    const msg = try std.fmt.allocPrint(self.allocator, "Class {s} contains abstract method {s}::{s} and must therefore be declared abstract or implement it", .{ class_name, se.value_ptr.*, se.key_ptr.* });
                    try self.strings.append(self.allocator, msg);
                    self.error_msg = msg;
                    return error.RuntimeError;
                }
            }
        }

        // anonymous classes have a stable structure and are re-executed every
        // time the call site runs. their existing instances point at the old
        // slot_layout, so freeing it (as we do for regular re-registration)
        // would invalidate live objects. keep the first registration.
        if (std.mem.startsWith(u8, class_name, "class@anonymous_") and self.classes.contains(class_name)) {
            def.deinit(self.allocator);
            return;
        }

        // put has the most complete state (e.g. parent slots merged), so we
        // let it win - but we must free the prior def or its slot_layout and
        // owned tables leak
        if (self.classes.fetchRemove(class_name)) |old| {
            var old_def = old.value;
            old_def.deinit(self.allocator);
        }
        try self.classes.put(self.allocator, class_name, def);

        // #[Override] enforcement - runs after class is registered so class
        // loading state stays consistent even if the error is caught
        var override_err: ?[]const u8 = null;
        var oa_it = def.method_attributes.iterator();
        while (oa_it.next()) |entry| {
            const method_name = entry.key_ptr.*;
            for (entry.value_ptr.*) |attr| {
                if (!std.mem.eql(u8, attr.name, "Override")) continue;
                if (self.methodExistsInAncestors(class_name, method_name, &def)) break;
                override_err = method_name;
                break;
            }
            if (override_err != null) break;
        }
        if (override_err) |method_name| {
            var buf2: [512]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf2, "{s}::{s}() has #[\\Override] attribute, but no matching parent method exists", .{ class_name, method_name }) catch "";
            if (try self.throwBuiltinException("Error", msg)) return;
            return error.RuntimeError;
        }
    }

    fn methodExistsInAncestors(self: *VM, class_name: []const u8, method_name: []const u8, def: *const ClassDef) bool {
        var buf: [256]u8 = undefined;

        // check parent class chain (functions, native_fns, and method declarations)
        var current: ?[]const u8 = def.parent;
        while (current) |parent| {
            const full = std.fmt.bufPrint(&buf, "{s}::{s}", .{ parent, method_name }) catch break;
            if (self.functions.contains(full) or self.native_fns.contains(full)) return true;
            const pcls = self.classes.get(parent) orelse break;
            if (pcls.methods.contains(method_name)) return true;
            current = pcls.parent;
        }

        // check interfaces (including parent interfaces)
        for (def.interfaces.items) |iface_name| {
            if (self.interfaceDeclaresMethod(iface_name, method_name)) return true;
        }
        // also check parent's interfaces
        current = def.parent;
        while (current) |parent| {
            const pcls = self.classes.get(parent) orelse break;
            for (pcls.interfaces.items) |iface_name| {
                if (self.interfaceDeclaresMethod(iface_name, method_name)) return true;
            }
            current = pcls.parent;
        }

        _ = class_name;
        return false;
    }

    fn interfaceDeclaresMethod(self: *VM, iface_name: []const u8, method_name: []const u8) bool {
        const idef = self.interfaces.get(iface_name) orelse return false;
        for (idef.methods.items) |m| {
            if (std.mem.eql(u8, m, method_name)) return true;
        }
        if (idef.parent) |parent| {
            return self.interfaceDeclaresMethod(parent, method_name);
        }
        return false;
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
            try def.constant_names.put(self.allocator, case_names[ci], {});
            try def.constant_order.append(self.allocator, case_names[ci]);
            try def.case_order.append(self.allocator, case_names[ci]);
        }

        const method_count = self.readU16();
        for (0..method_count) |_| {
            const mi = self.readMethodInfo();
            try def.addMethod(self.allocator, mi[1]);
        }

        const iface_count = self.readByte();
        for (0..iface_count) |_| {
            try def.interfaces.append(self.allocator, self.currentChunk().constants.items[self.readU16()].string);
        }
        // every enum implements UnitEnum; backed enums also implement BackedEnum
        try def.interfaces.append(self.allocator, "UnitEnum");
        if (backed_type_byte != 0) try def.interfaces.append(self.allocator, "BackedEnum");

        // traits
        const enum_trait_count = self.readByte();
        var enum_trait_names: [16][]const u8 = undefined;
        for (0..enum_trait_count) |ti| {
            enum_trait_names[ti] = self.currentChunk().constants.items[self.readU16()].string;
        }
        for (enum_trait_names[0..enum_trait_count]) |trait_name| {
            try self.applyTrait(&def, enum_name, trait_name, &.{}, &.{});
        }

        // enum-level attributes
        const enum_attrs = try self.readAttributeDefs();
        for (enum_attrs) |a| try def.attributes.append(self.allocator, a);
        if (enum_attrs.len > 0) self.allocator.free(enum_attrs);

        // method attributes
        const enum_method_attr_count = self.readByte();
        for (0..enum_method_attr_count) |_| {
            const ma_name_idx = self.readU16();
            const ma_name = self.currentChunk().constants.items[ma_name_idx].string;
            const ma_attrs = try self.readAttributeDefs();
            try def.method_attributes.put(self.allocator, ma_name, ma_attrs);
        }

        // case attributes - stored as constant_attributes so
        // ReflectionClassConstant::getAttributes finds them
        const enum_case_attr_count = self.readByte();
        for (0..enum_case_attr_count) |_| {
            const ca_name_idx = self.readU16();
            const ca_name = self.currentChunk().constants.items[ca_name_idx].string;
            const ca_attrs = try self.readAttributeDefs();
            try def.constant_attributes.put(self.allocator, ca_name, ca_attrs);
        }

        // enum constant names (const decls, not cases)
        const enum_const_count = self.readByte();
        for (0..enum_const_count) |_| {
            const ec_name_idx = self.readU16();
            const ec_name = self.currentChunk().constants.items[ec_name_idx].string;
            if (!def.constant_names.contains(ec_name)) {
                try def.constant_order.append(self.allocator, ec_name);
            }
            try def.constant_names.put(self.allocator, ec_name, {});
        }

        try self.registerEnumMethods(enum_name, backed_type_byte);
        try self.classes.put(self.allocator, enum_name, def);
    }

    fn readAttrValue(self: *VM) Value {
        const tag = self.readByte();
        return switch (tag) {
            0x00 => .null,
            0x01 => blk: {
                var bytes: [8]u8 = undefined;
                for (&bytes) |*b| b.* = self.readByte();
                break :blk .{ .int = @bitCast(bytes) };
            },
            0x02 => blk: {
                var bytes: [8]u8 = undefined;
                for (&bytes) |*b| b.* = self.readByte();
                break :blk .{ .float = @bitCast(bytes) };
            },
            0x03 => .{ .bool = true },
            0x04 => .{ .bool = false },
            0x05 => blk: {
                const idx = self.readU16();
                break :blk .{ .string = self.currentChunk().constants.items[idx].string };
            },
            0x06 => blk: {
                const len = self.readU16();
                const arr = self.allocator.create(PhpArray) catch break :blk .null;
                arr.* = .{};
                self.arrays.append(self.allocator, arr) catch {};
                for (0..len) |_| {
                    const v = self.readAttrValue();
                    arr.append(self.allocator, v) catch {};
                }
                break :blk .{ .array = arr };
            },
            0x07 => blk: { // associative array
                const len = self.readU16();
                const arr = self.allocator.create(PhpArray) catch break :blk .null;
                arr.* = .{};
                self.arrays.append(self.allocator, arr) catch {};
                for (0..len) |_| {
                    const key_type = self.readByte();
                    const key: PhpArray.Key = if (key_type == 0x01) k: {
                        const kidx = self.readU16();
                        break :k .{ .string = self.currentChunk().constants.items[kidx].string };
                    } else k: {
                        var bytes: [8]u8 = undefined;
                        for (&bytes) |*b| b.* = self.readByte();
                        break :k .{ .int = @bitCast(bytes) };
                    };
                    const v = self.readAttrValue();
                    arr.set(self.allocator, key, v) catch {};
                }
                break :blk .{ .array = arr };
            },
            else => .null,
        };
    }

    fn readAttributeDefs(self: *VM) RuntimeError![]const AttributeDef {
        const count = self.readByte();
        if (count == 0) return &.{};
        const attrs = try self.allocator.alloc(AttributeDef, count);
        for (0..count) |i| {
            const name_idx = self.readU16();
            const name = self.currentChunk().constants.items[name_idx].string;
            const arg_count = self.readByte();
            if (arg_count > 0) {
                const args = try self.allocator.alloc(Value, arg_count);
                const names = try self.allocator.alloc(?[]const u8, arg_count);
                for (0..arg_count) |ai| {
                    const named_flag = self.readByte();
                    if (named_flag == 1) {
                        const an_idx = self.readU16();
                        names[ai] = self.currentChunk().constants.items[an_idx].string;
                    } else {
                        names[ai] = null;
                    }
                    args[ai] = self.resolveAttrConstant(self.readAttrValue());
                }
                attrs[i] = .{ .name = name, .args = args, .arg_names = names };
            } else {
                attrs[i] = .{ .name = name };
            }
        }
        return attrs;
    }

    fn resolveAttrConstant(self: *VM, val: Value) Value {
        if (val != .string) return val;
        const s = val.string;
        if (s.len == 0) return val;
        // check for Class::CONST pattern
        if (std.mem.indexOf(u8, s, "::")) |sep| {
            const class_name = s[0..sep];
            const const_name = s[sep + 2 ..];
            if (self.getStaticProp(class_name, const_name)) |v| return v;
        }
        // check if it's a PHP constant
        if (self.php_constants.get(s)) |v| return v;
        return val;
    }

    fn readMethodInfo(self: *VM) struct { []const u8, ClassDef.MethodInfo } {
        const mname_idx = self.readU16();
        const method_name = self.currentChunk().constants.items[mname_idx].string;
        const arity = self.readByte();
        const is_static = self.readByte() == 1;
        const vis: ClassDef.Visibility = @enumFromInt(self.readByte());
        const flags = self.readByte();
        return .{ method_name, .{
            .name = method_name,
            .arity = arity,
            .is_static = is_static,
            .visibility = vis,
            .is_abstract = (flags & 1) != 0,
            .is_final = (flags & 2) != 0,
        } };
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
    const AliasRule = struct { method: []const u8, trait: []const u8, alias: []const u8, visibility: u8 = 0 };

    fn applyTrait(self: *VM, def: *ClassDef, class_name: []const u8, trait_name: []const u8, alias_rules: []const AliasRule, insteadof_rules: []const InsteadofRule) !void {
        // autoload the trait if it hasn't been loaded yet
        if (!self.traits.contains(trait_name)) {
            try self.tryAutoload(trait_name);
        }
        // recursively apply sub-traits first
        if (self.trait_uses.get(trait_name)) |subs| {
            for (subs) |sub| {
                try self.applyTrait(def, class_name, sub, &.{}, &.{});
            }
        }

        const TraitMethod = struct { name: []const u8, func: *const ObjFunction };
        var pending: [256]TraitMethod = undefined;
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
                if (std.mem.eql(u8, rule.method, tm.name) and (rule.trait.len == 0 or std.mem.eql(u8, rule.trait, trait_name))) {
                    const rule_vis: ClassDef.Visibility = switch (rule.visibility) {
                        1 => .protected,
                        2 => .private,
                        3 => .public,
                        else => .public,
                    };
                    if (std.mem.eql(u8, rule.alias, rule.method) and rule.visibility != 0) {
                        // visibility-only change on same name
                        vis_override = rule_vis;
                    } else {
                        const alias_method = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ class_name, rule.alias });
                        try self.strings.append(self.allocator, alias_method);
                        if (!self.functions.contains(alias_method)) {
                            try self.functions.put(self.allocator, alias_method, tm.func);
                            try def.addMethod(self.allocator, .{ .name = rule.alias, .arity = tm.func.arity, .visibility = if (rule.visibility != 0) rule_vis else .public });
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
                try def.addMethod(self.allocator, .{
                    .name = tm.name,
                    .arity = tm.func.arity,
                    .visibility = vis_override orelse .public,
                });
            }
        }

        if (self.trait_props.get(trait_name)) |props| {
            for (props) |prop| {
                var exists = false;
                for (def.properties.items) |existing| {
                    if (std.mem.eql(u8, existing.name, prop.name)) { exists = true; break; }
                }
                if (!exists) {
                    try def.properties.append(self.allocator, prop);
                }
            }
        }

        if (self.trait_static_props.get(trait_name)) |sprops| {
            for (sprops) |sp| {
                if (!def.static_props.contains(sp.name)) {
                    try def.static_props.put(self.allocator, sp.name, sp.value);
                }
            }
        }

        if (self.trait_constants.get(trait_name)) |consts| {
            for (consts) |c| {
                if (!def.static_props.contains(c.name)) {
                    try def.static_props.put(self.allocator, c.name, c.value);
                    try def.constant_names.put(self.allocator, c.name, {});
                }
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

    pub const ClosureScope = union(enum) {
        preserve, // keep existing scope ('static' or omitted)
        clear, // explicitly null - remove scope
        set: []const u8, // explicit class name
    };

    fn emitStaticClosureBindWarning(self: *VM) void {
        const msg = "Cannot bind an instance to a static closure, this will be an error in PHP 9";
        const ip = if (self.frame_count > 0) self.currentFrame().ip else 0;
        const line: i64 = if (self.frame_count > 0)
            if (self.currentChunk().getSourceLocation(if (ip > 0) ip - 1 else 0, self.source)) |loc| @intCast(loc.line) else 0
        else
            0;
        const file = self.file_path;
        if (self.error_silenced_depth != 0 or (self.error_reporting_level & 2) == 0) return;
        if (self.output.items.len > 0) {
            const stdout_file = std.fs.File{ .handle = 1 };
            _ = stdout_file.write(self.output.items) catch {};
            self.output.clearRetainingCapacity();
        }
        const stderr_text = std.fmt.allocPrint(self.allocator, "PHP Warning:  {s} in {s} on line {d}\n", .{ msg, file, line }) catch return;
        self.strings.append(self.allocator, stderr_text) catch {};
        const stderr_file = std.fs.File{ .handle = 2 };
        _ = stderr_file.write(stderr_text) catch {};
        const stdout_text = std.fmt.allocPrint(self.allocator, "\nWarning: {s} in {s} on line {d}\n", .{ msg, file, line }) catch return;
        self.strings.append(self.allocator, stdout_text) catch {};
        self.output.appendSlice(self.allocator, stdout_text) catch {};
    }

    pub fn cloneClosureWithThis(self: *VM, closure_name: []const u8, new_this: Value, scope_action: ClosureScope) !Value {
        const func = self.functions.get(closure_name) orelse return .null;

        // static closures cannot be bound to a non-null $this. PHP emits a
        // warning and returns null in that case; match the null return so
        // callers see the same observable behavior
        if (func.is_static and new_this != .null) {
            self.emitStaticClosureBindWarning();
            return .null;
        }

        const id = self.closure_instance_count;
        self.closure_instance_count += 1;
        const new_name = try std.fmt.allocPrint(self.allocator, "__closure_bound_{d}", .{id});
        try self.strings.append(self.allocator, new_name);
        try self.functions.put(self.allocator, new_name, func);

        if (self.capture_index.get(closure_name)) |cr| {
            // copy source captures to a heap buffer to avoid dangling slice
            // when self.captures reallocates during append
            const src_len = cr.len;
            const src_heap = try self.allocator.alloc(CaptureEntry, src_len);
            defer self.allocator.free(src_heap);
            for (0..src_len) |i| src_heap[i] = self.captures.items[cr.start + i];
            const src = src_heap;

            const new_start: u32 = @intCast(self.captures.items.len);
            var has_this = false;
            var has_scope = false;
            for (src) |cap| {
                if (std.mem.eql(u8, cap.var_name, "$__closure_scope")) {
                    has_scope = true;
                    switch (scope_action) {
                        .preserve => try self.captures.append(self.allocator, .{
                            .closure_name = new_name,
                            .var_name = "$__closure_scope",
                            .value = cap.value,
                        }),
                        .clear => {},
                        .set => |s| try self.captures.append(self.allocator, .{
                            .closure_name = new_name,
                            .var_name = "$__closure_scope",
                            .value = .{ .string = s },
                        }),
                    }
                    continue;
                }
                var new_cap = CaptureEntry{
                    .closure_name = new_name,
                    .var_name = cap.var_name,
                    .value = cap.value,
                    .ref_cell = cap.ref_cell,
                };
                if (std.mem.eql(u8, cap.var_name, "$this")) {
                    new_cap.value = new_this;
                    new_cap.ref_cell = null;
                    has_this = true;
                }
                try self.captures.append(self.allocator, new_cap);
            }
            if (!has_this and new_this != .null) {
                try self.captures.append(self.allocator, .{
                    .closure_name = new_name,
                    .var_name = "$this",
                    .value = new_this,
                });
            }
            if (!has_scope) {
                switch (scope_action) {
                    .set => |s| try self.captures.append(self.allocator, .{
                        .closure_name = new_name,
                        .var_name = "$__closure_scope",
                        .value = .{ .string = s },
                    }),
                    .preserve, .clear => {},
                }
            }
            const new_len: u16 = @intCast(self.captures.items.len - new_start);
            try self.capture_index.put(self.allocator, new_name, .{ .start = new_start, .len = new_len, .has_refs = cr.has_refs });
        } else {
            const new_start: u32 = @intCast(self.captures.items.len);
            if (new_this != .null) {
                try self.captures.append(self.allocator, .{
                    .closure_name = new_name,
                    .var_name = "$this",
                    .value = new_this,
                });
            }
            switch (scope_action) {
                .set => |s| try self.captures.append(self.allocator, .{
                    .closure_name = new_name,
                    .var_name = "$__closure_scope",
                    .value = .{ .string = s },
                }),
                .preserve, .clear => {},
            }
            const cap_len = self.captures.items.len - new_start;
            if (cap_len > 0) {
                try self.capture_index.put(self.allocator, new_name, .{ .start = new_start, .len = @intCast(cap_len), .has_refs = false });
            }
        }

        return .{ .string = new_name };
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
        // generator doesn't preserve ref bindings - they re-bind via get_static
        // on resume. drop the maps so frame_count -= 1 on suspend doesn't leak.
        const f = self.currentFrame();
        f.ref_slots.deinit(self.allocator);
        f.ref_array_bindings.deinit(self.allocator);
        f.ref_object_bindings.deinit(self.allocator);
        f.ref_slots = .{};
        f.ref_array_bindings = .{};
        f.ref_object_bindings = .{};
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
                self.saveFrameArgs(arg_count);
                self.sp -= ac;
                try self.fillDefaults(&new_vars, func, bind_count);
                const inherit_cc = self.closureScopeByName(name) orelse self.currentFrame().called_class;
                self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars, .locals = try self.allocLocals(func, &new_vars), .func = func, .ref_slots = closure_refs, .called_class = inherit_cc, .call_name = name };
                self.frames[self.frame_count].entry_sp = self.sp;
                self.setFrameArgCount(arg_count);
                self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
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
            if (i < func.defaults.len) locals[i] = try self.resolveDefault(func.defaults[i]);
        }
        self.saveFrameArgs(arg_count);
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

        self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = .{}, .locals = locals, .func = func, .called_class = self.closureScopeByName(name) orelse self.currentFrame().called_class, .call_name = name };
        self.frames[self.frame_count].entry_sp = self.sp;
        self.setFrameArgCount(arg_count);
        self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
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
            if (i < func.defaults.len) locals[i] = try self.resolveDefault(func.defaults[i]);
        }
        self.saveFrameArgs(arg_count);
        self.sp -= ac;
        self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = .{}, .locals = locals, .func = func, .called_class = self.currentFrame().called_class };
        self.frames[self.frame_count].entry_sp = self.sp;
        self.setFrameArgCount(arg_count);
        self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
        try self.fastLoop();
    }

    // compiled as a separate object (src/runtime/fast_loop.zig) so LLVM
    // optimizes it independently of runLoop
    fn fastLoop(self: *VM) RuntimeError!void {
        return switch (zphp_fast_loop(@ptrCast(self))) {
            0 => {},
            1 => error.RuntimeError,
            2 => error.OutOfMemory,
            else => unreachable,
        };
    }

    fn executeFunctionLocalsOnly(self: *VM, func: *const ObjFunction, args: []const Value) RuntimeError!Value {
        if (self.frame_count >= 2047) {
            self.error_msg = "Fatal error: maximum call stack depth exceeded";
            return error.RuntimeError;
        }
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
            if (i < func.defaults.len) locals[i] = try self.resolveDefault(func.defaults[i]);
        }
        const base_handler = self.handler_count;
        const prev_floor = self.handler_floor;
        self.handler_floor = self.handler_count;
        self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = .{}, .locals = locals, .func = func, .call_name = self.pending_call_name };
        self.frames[self.frame_count].entry_sp = self.sp;
        self.consumePendingArgCount();
        self.saveFrameArgsSlice(args);
        self.pending_call_name = null;
        self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
        self.runUntilFrame(base_frame) catch |err| {
            self.handler_count = base_handler;
            self.handler_floor = prev_floor;
            return err;
        };
        self.handler_count = base_handler;
        self.handler_floor = prev_floor;
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
        self.restoreFrameArgsSp();
        // prune exception handlers that belonged to the popped frame
        while (self.handler_count > self.handler_floor and
            self.exception_handlers[self.handler_count - 1].frame_count > self.frame_count)
        {
            self.handler_count -= 1;
        }
        // if this pop returns to the require-merge depth, leave the slot
        // intact so the require handler can read its vars/locals before
        // doing its own deinit. otherwise PHP's "include leaks top-level
        // vars even after explicit return" semantics is silently dropped
        if (self.require_merge_depth != 0 and self.frame_count + 1 == self.require_merge_depth) {
            return;
        }
        self.deinitFrameSlot(self.frame_count);
    }

    pub fn deinitFrameSlot(self: *VM, idx: usize) void {
        self.frames[idx].ref_slots.deinit(self.allocator);
        self.frames[idx].ref_array_bindings.deinit(self.allocator);
        self.frames[idx].ref_object_bindings.deinit(self.allocator);
        // when the frame belongs to a generator, its vars hashmap is owned by
        // the Generator and will be freed during freeHeapItems. freeing it
        // here too causes a double-free during VM cleanup
        if (self.frames[idx].generator == null) {
            self.frames[idx].vars.deinit(self.allocator);
        }
        if (self.frames[idx].locals.len > 0) {
            self.freeLocals(self.frames[idx].locals);
            self.frames[idx].locals = &.{};
        }
        self.frames[idx].ref_slots = .{};
        self.frames[idx].ref_array_bindings = .{};
        self.frames[idx].ref_object_bindings = .{};
        self.frames[idx].vars = .{};
    }

    pub fn freeLocals(self: *VM, locals: []Value) void {
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
            f.ref_array_bindings.deinit(self.allocator);
            f.ref_object_bindings.deinit(self.allocator);
            if (f.locals.len > 0) self.freeLocals(f.locals);
        }
        fiber.saved_frames.clearRetainingCapacity();
    }

    fn propagateCellWrite(self: *VM, cell: *Value, val: Value) !void {
        // bindings live on the frame that established the ref-to-elem/prop
        // binding, but the cell can be shared via bindRefParams into callee
        // frames. walk all active frames so a callee's write through the
        // shared cell still triggers the writeback registered by the caller
        var fi = self.frame_count;
        while (fi > 0) {
            fi -= 1;
            for (self.frames[fi].ref_array_bindings.items) |binding| {
                if (binding.cell == cell) {
                    try binding.array.set(self.allocator, binding.key, val);
                }
            }
            for (self.frames[fi].ref_object_bindings.items) |binding| {
                if (binding.cell == cell) {
                    try binding.object.set(self.allocator, binding.prop_name, val);
                }
            }
        }
    }

    fn writebackRefs(self: *VM) !void {
        for (self.currentFrame().ref_array_bindings.items) |binding| {
            try binding.array.set(self.allocator, binding.key, binding.cell.*);
        }
        for (self.currentFrame().ref_object_bindings.items) |binding| {
            try binding.object.set(self.allocator, binding.prop_name, binding.cell.*);
        }
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

    fn resolveCallerVar(self: *VM, var_name: []const u8, is_local: bool, slot: u16) Value {
        const frame = self.currentFrame();
        if (is_local and slot < frame.locals.len) {
            return frame.locals[slot];
        }
        if (frame.ref_slots.get(var_name)) |cell| return cell.*;
        return frame.vars.get(var_name) orelse .null;
    }

    fn scanCallerArgSources(self: *VM, ac: usize) [16]RefSource {
        var sources: [16]RefSource = .{.none} ** 16;
        if (ac == 0) return sources;
        const caller = self.currentFrame();
        const chunk = caller.chunk;
        const ip = caller.ip;
        if (ip < 2) return sources;
        const code = chunk.code.items;
        // determine the call op width: try each plausible op width and pick the one
        // whose byte at (ip - width) matches its widthFromByte. .call is 4 bytes;
        // call_indirect / require / method_call_dynamic are 2; etc
        var call_pos: usize = 0;
        var found_call = false;
        const candidates = [_]usize{ 4, 2, 1, 3 };
        for (candidates) |w| {
            if (ip < w) continue;
            const p = ip - w;
            const b = code[p];
            const probe_w = OpCode.widthFromByte(b);
            if (probe_w == w) {
                call_pos = p;
                found_call = true;
                break;
            }
        }
        if (!found_call) return sources;

        // bytes to walk backwards from the call site. each PHP arg can
        // compile to ~3 instructions of ~3 bytes per level of access chain;
        // a 16-deep chain ~= 16*3*3 = 144 bytes per arg. give plenty of
        // headroom so deep ->a->b->c->... chains find their root op
        const max_scan = ac * 96;
        const region_start = if (call_pos > max_scan) call_pos - max_scan else 0;

        var instrs: [128]usize = undefined;
        var instr_count: usize = 0;
        var try_start = region_start;
        while (try_start < call_pos) : (try_start += 1) {
            var pos = try_start;
            var count: usize = 0;
            while (pos < call_pos and count < 128) {
                instrs[count] = pos;
                count += 1;
                pos += OpCode.widthFromByte(code[pos]);
            }
            if (pos == call_pos) {
                instr_count = count;
                break;
            }
        }
        if (instr_count == 0) return sources;

        // for call_indirect (and similar indirect calls), the function name was
        // for both .call and .call_indirect the topmost producers ARE the args
        // (call_indirect pushes the callable first, then args; .call has the
        // function name encoded as a u16 constant in the opcode). scan straight
        var i = instr_count;

        var scan_idx: usize = ac;

        while (scan_idx > 0 and i > 0) {
            scan_idx -= 1;
            var depth: i32 = 0;
            const arg_end = i;
            var bad_op = false;
            while (i > 0 and depth < 1) {
                i -= 1;
                const op: OpCode = std.meta.intToEnum(OpCode, code[instrs[i]]) catch {
                    bad_op = true;
                    break;
                };
                depth += @as(i32, op.stackEffect());
            }
            if (bad_op or depth < 1) break;

            const arg_instr_count = arg_end - i;

            if (arg_instr_count == 1) {
                const aip = instrs[i];
                if (code[aip] == @intFromEnum(OpCode.get_var)) {
                    const ci = (@as(u16, code[aip + 1]) << 8) | code[aip + 2];
                    if (ci < chunk.constants.items.len) {
                        sources[scan_idx] = .{ .simple = chunk.constants.items[ci].string };
                    }
                } else if (code[aip] == @intFromEnum(OpCode.get_local)) {
                    const slot = (@as(u16, code[aip + 1]) << 8) | code[aip + 2];
                    const sn = if (caller.func) |func| func.slot_names else self.global_slot_names;
                    if (slot < sn.len) {
                        sources[scan_idx] = .{ .simple = sn[slot] };
                    }
                }
            } else if (arg_instr_count == 2) {
                // get_var/get_local + get_prop
                const first_ip = instrs[i];
                const second_ip = instrs[i + 1];
                if (code[second_ip] == @intFromEnum(OpCode.get_prop)) {
                    var var_name: ?[]const u8 = null;
                    var is_local = false;
                    var slot: u16 = 0;
                    if (code[first_ip] == @intFromEnum(OpCode.get_var)) {
                        const ci = (@as(u16, code[first_ip + 1]) << 8) | code[first_ip + 2];
                        if (ci < chunk.constants.items.len) var_name = chunk.constants.items[ci].string;
                    } else if (code[first_ip] == @intFromEnum(OpCode.get_local)) {
                        slot = (@as(u16, code[first_ip + 1]) << 8) | code[first_ip + 2];
                        const sn = if (caller.func) |func| func.slot_names else self.global_slot_names;
                        if (slot < sn.len) {
                            var_name = sn[slot];
                            is_local = true;
                        }
                    }
                    if (var_name) |vn| {
                        const prop_ci = (@as(u16, code[second_ip + 1]) << 8) | code[second_ip + 2];
                        if (prop_ci < chunk.constants.items.len) {
                            if (chunk.constants.items[prop_ci] == .string) {
                                sources[scan_idx] = .{ .object_prop = .{
                                    .var_name = vn,
                                    .is_local = is_local,
                                    .slot = slot,
                                    .prop_name = chunk.constants.items[prop_ci].string,
                                } };
                            }
                        }
                    }
                }
            } else if (arg_instr_count >= 3) {
                const first_ip = instrs[i];
                const last_ip = instrs[i + arg_instr_count - 1];
                if (arg_instr_count == 3 and code[last_ip] == @intFromEnum(OpCode.array_get)) {
                    const mid_ip = instrs[i + 1];
                    var var_name: ?[]const u8 = null;
                    var is_local = false;
                    var slot: u16 = 0;
                    if (code[first_ip] == @intFromEnum(OpCode.get_var)) {
                        const ci = (@as(u16, code[first_ip + 1]) << 8) | code[first_ip + 2];
                        if (ci < chunk.constants.items.len) var_name = chunk.constants.items[ci].string;
                    } else if (code[first_ip] == @intFromEnum(OpCode.get_local)) {
                        slot = (@as(u16, code[first_ip + 1]) << 8) | code[first_ip + 2];
                        const sn = if (caller.func) |func| func.slot_names else self.global_slot_names;
                        if (slot < sn.len) {
                            var_name = sn[slot];
                            is_local = true;
                        }
                    }
                    if (var_name) |vn| {
                        var key_val: ?Value = null;
                        if (code[mid_ip] == @intFromEnum(OpCode.constant)) {
                            const ci = (@as(u16, code[mid_ip + 1]) << 8) | code[mid_ip + 2];
                            if (ci < chunk.constants.items.len) key_val = chunk.constants.items[ci];
                        } else if (code[mid_ip] == @intFromEnum(OpCode.get_var)) {
                            const ci = (@as(u16, code[mid_ip + 1]) << 8) | code[mid_ip + 2];
                            if (ci < chunk.constants.items.len) {
                                if (chunk.constants.items[ci] == .string) {
                                    const kname = chunk.constants.items[ci].string;
                                    key_val = caller.vars.get(kname);
                                    if (key_val == null and caller.locals.len > 0) {
                                        const sn = if (caller.func) |func| func.slot_names else self.global_slot_names;
                                        for (sn, 0..) |sn_name, si| {
                                            if (std.mem.eql(u8, sn_name, kname)) {
                                                if (si < caller.locals.len) key_val = caller.locals[si];
                                                break;
                                            }
                                        }
                                    }
                                }
                            }
                        } else if (code[mid_ip] == @intFromEnum(OpCode.get_local)) {
                            const kslot = (@as(u16, code[mid_ip + 1]) << 8) | code[mid_ip + 2];
                            if (kslot < caller.locals.len) key_val = caller.locals[kslot];
                        }
                        if (key_val) |kv| {
                            sources[scan_idx] = .{ .array_elem = .{
                                .var_name = vn,
                                .is_local = is_local,
                                .slot = slot,
                                .key = kv,
                            } };
                        }
                    }
                } else if (arg_instr_count == 4 and code[last_ip] == @intFromEnum(OpCode.array_get)) {
                    // $obj->prop['key'] pattern: get_var/get_local + get_prop + key + array_get
                    const prop_ip = instrs[i + 1];
                    const key_ip = instrs[i + 2];
                    if (code[prop_ip] == @intFromEnum(OpCode.get_prop)) {
                        var var_name: ?[]const u8 = null;
                        var is_local = false;
                        var slot: u16 = 0;
                        if (code[first_ip] == @intFromEnum(OpCode.get_var)) {
                            const ci = (@as(u16, code[first_ip + 1]) << 8) | code[first_ip + 2];
                            if (ci < chunk.constants.items.len) var_name = chunk.constants.items[ci].string;
                        } else if (code[first_ip] == @intFromEnum(OpCode.get_local)) {
                            slot = (@as(u16, code[first_ip + 1]) << 8) | code[first_ip + 2];
                            const sn = if (caller.func) |func| func.slot_names else self.global_slot_names;
                            if (slot < sn.len) {
                                var_name = sn[slot];
                                is_local = true;
                            }
                        }
                        if (var_name) |vn| {
                            const pci = (@as(u16, code[prop_ip + 1]) << 8) | code[prop_ip + 2];
                            if (pci < chunk.constants.items.len and chunk.constants.items[pci] == .string) {
                                const prop_name = chunk.constants.items[pci].string;
                                var key_val: ?Value = null;
                                if (code[key_ip] == @intFromEnum(OpCode.constant)) {
                                    const ci = (@as(u16, code[key_ip + 1]) << 8) | code[key_ip + 2];
                                    if (ci < chunk.constants.items.len) key_val = chunk.constants.items[ci];
                                } else if (code[key_ip] == @intFromEnum(OpCode.get_var)) {
                                    const ci = (@as(u16, code[key_ip + 1]) << 8) | code[key_ip + 2];
                                    if (ci < chunk.constants.items.len) {
                                        if (chunk.constants.items[ci] == .string) {
                                            const kname = chunk.constants.items[ci].string;
                                            key_val = caller.vars.get(kname);
                                            if (key_val == null and caller.locals.len > 0) {
                                                const sn = if (caller.func) |func| func.slot_names else self.global_slot_names;
                                                for (sn, 0..) |sn_name, si| {
                                                    if (std.mem.eql(u8, sn_name, kname)) {
                                                        if (si < caller.locals.len) key_val = caller.locals[si];
                                                        break;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                } else if (code[key_ip] == @intFromEnum(OpCode.get_local)) {
                                    const kslot = (@as(u16, code[key_ip + 1]) << 8) | code[key_ip + 2];
                                    if (kslot < caller.locals.len) key_val = caller.locals[kslot];
                                }
                                if (key_val) |kv| {
                                    sources[scan_idx] = .{ .prop_array_elem = .{
                                        .var_name = vn,
                                        .is_local = is_local,
                                        .slot = slot,
                                        .prop_name = prop_name,
                                        .key = kv,
                                    } };
                                }
                            }
                        }
                    }
                } else if (code[last_ip] == @intFromEnum(OpCode.get_prop) or code[last_ip] == @intFromEnum(OpCode.get_prop_dynamic)) {
                    var var_name: ?[]const u8 = null;
                    var is_local = false;
                    var slot: u16 = 0;
                    if (code[first_ip] == @intFromEnum(OpCode.get_var)) {
                        const ci = (@as(u16, code[first_ip + 1]) << 8) | code[first_ip + 2];
                        if (ci < chunk.constants.items.len) var_name = chunk.constants.items[ci].string;
                    } else if (code[first_ip] == @intFromEnum(OpCode.get_local)) {
                        slot = (@as(u16, code[first_ip + 1]) << 8) | code[first_ip + 2];
                        const sn = if (caller.func) |func| func.slot_names else self.global_slot_names;
                        if (slot < sn.len) {
                            var_name = sn[slot];
                            is_local = true;
                        }
                    }
                    if (var_name) |vn| {
                        var props: [16]?[]const u8 = @splat(null);
                        var valid = true;
                        var prop_count: usize = 0;
                        const is_dynamic = code[last_ip] == @intFromEnum(OpCode.get_prop_dynamic);
                        const chain_end = if (is_dynamic) arg_instr_count - 2 else arg_instr_count - 1;
                        for (1..chain_end) |pi| {
                            const pip = instrs[i + pi];
                            if (code[pip] == @intFromEnum(OpCode.get_prop)) {
                                const pci = (@as(u16, code[pip + 1]) << 8) | code[pip + 2];
                                if (pci < chunk.constants.items.len and chunk.constants.items[pci] == .string) {
                                    if (prop_count < props.len) {
                                        props[prop_count] = chunk.constants.items[pci].string;
                                        prop_count += 1;
                                    }
                                } else {
                                    valid = false;
                                    break;
                                }
                            } else {
                                valid = false;
                                break;
                            }
                        }
                        if (valid and is_dynamic) {
                            const name_ip = instrs[i + arg_instr_count - 2];
                            var dyn_name: ?[]const u8 = null;
                            if (code[name_ip] == @intFromEnum(OpCode.get_var)) {
                                const nci = (@as(u16, code[name_ip + 1]) << 8) | code[name_ip + 2];
                                if (nci < chunk.constants.items.len and chunk.constants.items[nci] == .string) {
                                    const kname = chunk.constants.items[nci].string;
                                    const resolved = caller.vars.get(kname) orelse blk: {
                                        if (caller.locals.len > 0) {
                                            const sn = if (caller.func) |func| func.slot_names else self.global_slot_names;
                                            for (sn, 0..) |sn_name, si| {
                                                if (std.mem.eql(u8, sn_name, kname)) {
                                                    if (si < caller.locals.len) break :blk caller.locals[si];
                                                    break;
                                                }
                                            }
                                        }
                                        break :blk null;
                                    };
                                    if (resolved) |rv| {
                                        if (rv == .string) dyn_name = rv.string;
                                    }
                                }
                            } else if (code[name_ip] == @intFromEnum(OpCode.get_local)) {
                                const ns = (@as(u16, code[name_ip + 1]) << 8) | code[name_ip + 2];
                                if (ns < caller.locals.len) {
                                    if (caller.locals[ns] == .string) dyn_name = caller.locals[ns].string;
                                }
                            }
                            if (dyn_name) |dn| {
                                if (prop_count < props.len) {
                                    props[prop_count] = dn;
                                    prop_count += 1;
                                }
                            } else valid = false;
                        } else if (valid) {
                            const pci = (@as(u16, code[last_ip + 1]) << 8) | code[last_ip + 2];
                            if (pci < chunk.constants.items.len and chunk.constants.items[pci] == .string) {
                                if (prop_count < props.len) {
                                    props[prop_count] = chunk.constants.items[pci].string;
                                    prop_count += 1;
                                }
                            } else valid = false;
                        }
                        if (valid and prop_count > 0) {
                            sources[scan_idx] = .{ .chained_prop = .{
                                .var_name = vn,
                                .is_local = is_local,
                                .slot = slot,
                                .props = props,
                            } };
                        }
                    }
                }
            }
        }
        return sources;
    }

    const ChainedPropTarget = struct { obj: *PhpObject, prop: []const u8 };

    fn resolveChainedProp(self: *VM, cp: std.meta.TagPayload(RefSource, .chained_prop)) ?ChainedPropTarget {
        var cur = self.resolveCallerVar(cp.var_name, cp.is_local, cp.slot);
        var last_prop: ?[]const u8 = null;
        for (cp.props) |mp| {
            const pn = mp orelse break;
            if (last_prop) |lp| {
                if (cur == .object) {
                    cur = cur.object.get(lp);
                } else return null;
            }
            last_prop = pn;
        }
        if (last_prop) |lp| {
            if (cur == .object) return .{ .obj = cur.object, .prop = lp };
        }
        return null;
    }

    fn bindRefParams(
        self: *VM,
        ac: usize,
        func: *const ObjFunction,
        new_vars: *std.StringHashMapUnmanaged(Value),
        refs: *std.StringHashMapUnmanaged(*Value),
        array_bindings: *std.ArrayListUnmanaged(ArrayRefBinding),
        object_bindings: *std.ArrayListUnmanaged(ObjectRefBinding),
    ) !void {
        if (func.ref_params.len == 0) return;
        const arg_sources = self.scanCallerArgSources(ac);
        for (0..@min(ac, func.ref_params.len)) |ri| {
            if (!func.ref_params[ri]) continue;
            switch (arg_sources[ri]) {
                .simple => |caller_var| {
                    if (self.currentFrame().ref_slots.get(caller_var)) |existing_cell| {
                        existing_cell.* = new_vars.get(func.params[ri]) orelse .null;
                        try refs.put(self.allocator, func.params[ri], existing_cell);
                    } else {
                        const cell = try self.allocator.create(Value);
                        cell.* = new_vars.get(func.params[ri]) orelse .null;
                        try self.ref_cells.append(self.allocator, cell);
                        try self.currentFrame().ref_slots.put(self.allocator, caller_var, cell);
                        try refs.put(self.allocator, func.params[ri], cell);
                    }
                },
                .array_elem => |ae| {
                    const arr_val = self.resolveCallerVar(ae.var_name, ae.is_local, ae.slot);
                    if (arr_val == .array) {
                        const cell = try self.allocator.create(Value);
                        cell.* = new_vars.get(func.params[ri]) orelse .null;
                        try self.ref_cells.append(self.allocator, cell);
                        try refs.put(self.allocator, func.params[ri], cell);
                        try array_bindings.append(self.allocator, .{
                            .cell = cell,
                            .array = arr_val.array,
                            .key = Value.toArrayKey(ae.key),
                        });
                    }
                },
                .object_prop => |obj_ref| {
                    const obj_val = self.resolveCallerVar(obj_ref.var_name, obj_ref.is_local, obj_ref.slot);
                    if (obj_val == .object) {
                        const cell = try self.allocator.create(Value);
                        cell.* = new_vars.get(func.params[ri]) orelse .null;
                        try self.ref_cells.append(self.allocator, cell);
                        try refs.put(self.allocator, func.params[ri], cell);
                        try object_bindings.append(self.allocator, .{
                            .cell = cell,
                            .object = obj_val.object,
                            .prop_name = obj_ref.prop_name,
                        });
                    }
                },
                .chained_prop => |cp| {
                    if (self.resolveChainedProp(cp)) |target| {
                        const cell = try self.allocator.create(Value);
                        cell.* = new_vars.get(func.params[ri]) orelse .null;
                        try self.ref_cells.append(self.allocator, cell);
                        try refs.put(self.allocator, func.params[ri], cell);
                        try object_bindings.append(self.allocator, .{
                            .cell = cell,
                            .object = target.obj,
                            .prop_name = target.prop,
                        });
                    }
                },
                .prop_array_elem => |pae| {
                    const obj_val = self.resolveCallerVar(pae.var_name, pae.is_local, pae.slot);
                    if (obj_val == .object) {
                        const prop_val = obj_val.object.get(pae.prop_name);
                        if (prop_val == .array) {
                            const cell = try self.allocator.create(Value);
                            cell.* = new_vars.get(func.params[ri]) orelse .null;
                            try self.ref_cells.append(self.allocator, cell);
                            try refs.put(self.allocator, func.params[ri], cell);
                            try array_bindings.append(self.allocator, .{
                                .cell = cell,
                                .array = prop_val.array,
                                .key = Value.toArrayKey(pae.key),
                            });
                        }
                    }
                },
                .none => {},
            }
        }
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
        // prefer the per-frame call_name so closure instances (which share an
        // ObjFunction) are distinguished for static-var ownership
        if (self.frame_count > 0) {
            if (self.frames[self.frame_count - 1].call_name) |n| return n;
        }
        const chunk_ptr = self.currentChunk();
        var it = self.functions.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.*.chunk.code.items.ptr == chunk_ptr.code.items.ptr) {
                return entry.key_ptr.*;
            }
        }
        return null;
    }

    pub fn tryAutoload(self: *VM, raw_class_name: []const u8) RuntimeError!void {
        const class_name = if (raw_class_name.len > 0 and raw_class_name[0] == '\\') raw_class_name[1..] else raw_class_name;
        if (self.classes.contains(class_name)) return;
        if (self.interfaces.contains(class_name)) return;
        if (self.traits.contains(class_name)) return;
        if (self.autoload_depth >= 64) return;
        self.autoload_depth += 1;
        defer self.autoload_depth -= 1;

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

    // mirror of looseEqualWithStringable for ordered comparisons
    pub fn compareWithStringable(self: *VM, a: Value, b: Value) RuntimeError!i64 {
        if (a == .object and b == .string) {
            if (self.hasMethod(a.object.class_name, "__toString")) {
                const s = try self.callMethod(a.object, "__toString", &.{});
                if (s == .string) return Value.compare(s, b);
            }
        } else if (b == .object and a == .string) {
            if (self.hasMethod(b.object.class_name, "__toString")) {
                const s = try self.callMethod(b.object, "__toString", &.{});
                if (s == .string) return Value.compare(a, s);
            }
        }
        return Value.compare(a, b);
    }

    // PHP's == between an object with __toString and a scalar string runs
    // __toString and compares as strings. Value.equal can't reach into the VM
    // to call methods, so this wrapper does that coercion before delegating
    pub fn looseEqualWithStringable(self: *VM, a: Value, b: Value) RuntimeError!bool {
        if (a == .object and b == .string) {
            if (self.hasMethod(a.object.class_name, "__toString")) {
                const s = try self.callMethod(a.object, "__toString", &.{});
                if (s == .string) return Value.equal(s, b);
            }
        } else if (b == .object and a == .string) {
            if (self.hasMethod(b.object.class_name, "__toString")) {
                const s = try self.callMethod(b.object, "__toString", &.{});
                if (s == .string) return Value.equal(a, s);
            }
        }
        return Value.equal(a, b);
    }

    pub fn isInstanceOf(self: *VM, raw_obj_class: []const u8, raw_target: []const u8) bool {
        // PHP normalizes leading-backslash equivalence for class names
        const obj_class = if (raw_obj_class.len > 0 and raw_obj_class[0] == '\\') raw_obj_class[1..] else raw_obj_class;
        const target_class = if (raw_target.len > 0 and raw_target[0] == '\\') raw_target[1..] else raw_target;
        if (std.mem.eql(u8, target_class, "Stringable") and self.hasMethod(obj_class, "__toString")) return true;
        var current = obj_class;
        while (true) {
            if (std.mem.eql(u8, current, target_class)) return true;
            // built-in exception hierarchy (always checked, even for registered classes)
            if (builtinExceptionParent(current)) |builtin_parent| {
                if (std.mem.eql(u8, target_class, "Throwable") or
                    std.mem.eql(u8, target_class, "Exception") or
                    std.mem.eql(u8, target_class, "Error"))
                {
                    // walk the builtin hierarchy
                    var bp = builtin_parent;
                    while (true) {
                        if (std.mem.eql(u8, bp, target_class)) return true;
                        bp = builtinExceptionParent(bp) orelse break;
                    }
                }
            }
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

    fn builtinExceptionParent(class_name: []const u8) ?[]const u8 {
        if (std.mem.eql(u8, class_name, "Exception") or std.mem.eql(u8, class_name, "Error")) return "Throwable";
        const date_exception_children = [_][]const u8{
            "DateInvalidTimeZoneException", "DateInvalidOperationException",
            "DateMalformedStringException", "DateMalformedIntervalStringException",
            "DateMalformedPeriodStringException",
        };
        for (date_exception_children) |name| {
            if (std.mem.eql(u8, class_name, name)) return "DateException";
        }
        if (std.mem.eql(u8, class_name, "DateException")) return "Exception";
        const date_error_children = [_][]const u8{
            "DateObjectError", "DateRangeError",
        };
        for (date_error_children) |name| {
            if (std.mem.eql(u8, class_name, name)) return "DateError";
        }
        if (std.mem.eql(u8, class_name, "DateError")) return "Error";
        if (std.mem.eql(u8, class_name, "SodiumException")) return "Exception";
        const exception_children = [_][]const u8{
            "RuntimeException",     "LogicException",          "InvalidArgumentException",
            "BadMethodCallException", "BadFunctionCallException", "OutOfRangeException",
            "OverflowException",    "UnderflowException",      "LengthException",
            "DomainException",      "RangeException",          "UnexpectedValueException",
            "JsonException",        "PDOException",
        };
        for (exception_children) |name| {
            if (std.mem.eql(u8, class_name, name)) return "Exception";
        }
        const error_children = [_][]const u8{
            "TypeError",      "ValueError",          "ArithmeticError",
            "DivisionByZeroError", "UnhandledMatchError", "FiberError",
            "ParseError",     "CompileError",
        };
        for (error_children) |name| {
            if (std.mem.eql(u8, class_name, name)) return "Error";
        }
        return null;
    }

    fn checkConstVisibility(self: *VM, class_name: []const u8, const_name: []const u8) RuntimeError!bool {
        var current: ?[]const u8 = class_name;
        var declaring: []const u8 = class_name;
        var vis: ClassDef.Visibility = .public;
        while (current) |cn| {
            if (self.classes.get(cn)) |cls| {
                if (cls.const_visibility.get(const_name)) |v| {
                    declaring = cn;
                    vis = v;
                    break;
                }
                if (cls.constant_names.contains(const_name)) {
                    declaring = cn;
                    vis = .public;
                    break;
                }
                current = cls.parent;
            } else break;
        }
        if (vis == .public) return true;
        if (self.checkVisibility(declaring, vis)) return true;
        const msg = try std.fmt.allocPrint(self.allocator, "Cannot access {s} const {s}::{s}", .{ @tagName(vis), declaring, const_name });
        try self.strings.append(self.allocator, msg);
        _ = try self.throwBuiltinException("Error", msg);
        return false;
    }

    fn visScopeSuffix(self: *VM) []const u8 {
        // PHP's "from global scope" / "from 'X' context" suffix for visibility errors
        const caller = if (self.frame_count > 0)
            self.frames[self.frame_count - 1].called_class orelse self.currentDefiningClass()
        else
            null;
        if (caller) |c| {
            const s = std.fmt.allocPrint(self.allocator, " from '{s}' context", .{c}) catch return " from global scope";
            self.strings.append(self.allocator, s) catch {};
            return s;
        }
        return " from global scope";
    }

    fn checkVisibility(self: *VM, target_class: []const u8, vis: ClassDef.Visibility) bool {
        if (vis == .public) return true;
        if (vis == .private) {
            // for private, check defining class first so parent::__construct()
            // can access its own private properties
            const defining = self.currentDefiningClass();
            if (defining) |dc| {
                if (std.mem.eql(u8, dc, target_class)) return true;
            }
            const caller_class = self.currentFrame().called_class orelse defining orelse return false;
            return std.mem.eql(u8, caller_class, target_class);
        }
        // protected: caller must be same class or in inheritance chain
        const caller_class = self.currentFrame().called_class orelse self.currentDefiningClass() orelse return false;
        return self.isInstanceOf(caller_class, target_class) or self.isInstanceOf(target_class, caller_class);
    }

    pub const VisResult = struct { visibility: ClassDef.Visibility, defining_class: []const u8, is_readonly: bool = false, set_visibility: ClassDef.Visibility = .public };

    pub fn findPropertyVisibility(self: *VM, class_name: []const u8, prop_name: []const u8) VisResult {
        // PHP rule for private properties: each declaring class gets its own
        // slot. When `$this->prop` is read from inside a method of class S,
        // S's own private declaration of `prop` (if any) is preferred over
        // any descendant's, because they're separate slots. Use the current
        // execution scope (the running method's class) to pick the right one
        const scope = if (self.frame_count > 0)
            self.frames[self.frame_count - 1].called_class orelse self.currentDefiningClass()
        else
            null;
        if (scope) |sc| {
            if (self.classes.get(sc)) |scls| {
                for (scls.properties.items) |prop| {
                    if (std.mem.eql(u8, prop.name, prop_name) and prop.visibility == .private) {
                        return .{ .visibility = prop.visibility, .defining_class = sc, .is_readonly = prop.is_readonly, .set_visibility = prop.set_visibility };
                    }
                }
            }
        }
        var current: ?[]const u8 = class_name;
        while (current) |cn| {
            if (self.classes.get(cn)) |cls| {
                for (cls.properties.items) |prop| {
                    if (std.mem.eql(u8, prop.name, prop_name)) return .{ .visibility = prop.visibility, .defining_class = cn, .is_readonly = prop.is_readonly, .set_visibility = prop.set_visibility };
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
        if (std.mem.eql(u8, iface_name, target)) return true;
        if (self.interfaces.get(iface_name)) |idef| {
            // walk every extended interface (PHP allows multi-extension)
            for (idef.parents.items) |p| {
                if (self.implementsInterface(p, target)) return true;
            }
            // legacy single-parent field for older code paths that haven't been
            // converted to push into 'parents' yet
            if (idef.parent) |p| {
                var seen_in_parents = false;
                for (idef.parents.items) |pp| if (std.mem.eql(u8, pp, p)) { seen_in_parents = true; break; };
                if (!seen_in_parents and self.implementsInterface(p, target)) return true;
            }
            return false;
        }
        // not registered as an interface - try autoload then fall back to
        // walking a class's implemented-interface list (for class-as-iface refs)
        if (!self.classes.contains(iface_name)) {
            self.tryAutoload(iface_name) catch {};
        }
        if (self.interfaces.get(iface_name)) |idef| {
            for (idef.parents.items) |p| if (self.implementsInterface(p, target)) return true;
            if (idef.parent) |p| if (self.implementsInterface(p, target)) return true;
        } else if (self.classes.get(iface_name)) |cls| {
            for (cls.interfaces.items) |parent_iface| {
                if (self.implementsInterface(parent_iface, target)) return true;
            }
        }
        return false;
    }

    fn closureScopeForFrame(self: *VM, frame: *const CallFrame) ?[]const u8 {
        const frame_chunk_ptr = frame.chunk;
        var iter = self.functions.iterator();
        while (iter.next()) |entry| {
            if (frame_chunk_ptr == &entry.value_ptr.*.chunk) {
                const name = entry.key_ptr.*;
                if (std.mem.startsWith(u8, name, "__closure_")) {
                    if (self.capture_index.get(name)) |cr| {
                        const caps = self.captures.items[cr.start .. cr.start + cr.len];
                        for (caps) |cap| {
                            if (std.mem.eql(u8, cap.var_name, "$__closure_scope") and cap.value == .string)
                                return cap.value.string;
                        }
                    }
                }
            }
        }
        return null;
    }

    pub fn closureScopeByName(self: *VM, name: []const u8) ?[]const u8 {
        if (self.capture_index.get(name)) |cr| {
            const caps = self.captures.items[cr.start .. cr.start + cr.len];
            for (caps) |cap| {
                if (std.mem.eql(u8, cap.var_name, "$__closure_scope") and cap.value == .string)
                    return cap.value.string;
            }
        }
        return null;
    }

    pub fn closureThisByName(self: *VM, name: []const u8) Value {
        if (self.capture_index.get(name)) |cr| {
            const caps = self.captures.items[cr.start .. cr.start + cr.len];
            for (caps) |cap| {
                if (std.mem.eql(u8, cap.var_name, "$this")) return cap.value;
            }
        }
        return .null;
    }

    fn parentResolvingClass(self: *VM) ?[]const u8 {
        // like currentDefiningClass but skips closure scope check and uses
        // called_class as disambiguator fallback for parent:: resolution
        var fi: usize = self.frame_count;
        while (fi > 0) {
            fi -= 1;
            const frame = &self.frames[fi];
            const frame_chunk_ptr = frame.chunk;
            var best: ?[]const u8 = null;
            const disambig: ?[]const u8 = blk: {
                if (frame.func != null and frame.locals.len > 0 and frame.locals[0] == .object)
                    break :blk frame.locals[0].object.class_name;
                const this_val = frame.vars.get("$this") orelse break :blk frame.called_class;
                if (this_val == .object) break :blk this_val.object.class_name;
                break :blk frame.called_class;
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
                        if (disambig) |tc| {
                            if (std.mem.eql(u8, class_part, tc))
                                return class_part;
                            if (self.isInstanceOf(tc, class_part)) {
                                if (best) |b| {
                                    if (self.traits.contains(b)) {
                                        best = class_part;
                                    } else if (self.isInstanceOf(b, class_part)) {
                                        best = class_part;
                                    } else if (!self.isInstanceOf(tc, b)) {
                                        best = class_part;
                                    }
                                } else best = class_part;
                            } else if (best == null) {
                                best = class_part;
                            }
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

    pub fn currentDefiningClass(self: *VM) ?[]const u8 {
        // bound closure scope takes priority over frame walk
        if (self.frame_count > 0) {
            if (self.closureScopeForFrame(&self.frames[self.frame_count - 1])) |scope|
                return scope;
        }
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
                        if (this_class) |tc| {
                            if (std.mem.eql(u8, class_part, tc))
                                return class_part;
                            if (self.isInstanceOf(tc, class_part)) {
                                if (best) |b| {
                                    // always prefer a non-trait class over a trait
                                    if (self.traits.contains(b)) {
                                        best = class_part;
                                    } else if (self.isInstanceOf(b, class_part)) {
                                        best = class_part;
                                    }
                                } else best = class_part;
                            } else if (best == null) {
                                best = class_part;
                            }
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

    pub fn triggerLazyInit(self: *VM, obj: *PhpObject) RuntimeError!void {
        if (obj.lazy_initializer == .null) return;
        const initializer = obj.lazy_initializer;
        obj.lazy_initializer = .null;
        var ctx = self.makeContext(null);
        _ = ctx.invokeCallable(initializer, &.{.{ .object = obj }}) catch |err| {
            obj.lazy_initializer = initializer;
            return err;
        };
    }

    pub fn propHookName(self: *VM, prop_name: []const u8, kind: enum { get, set }) ?[]const u8 {
        const suffix = switch (kind) { .get => "$hook_get", .set => "$hook_set" };
        const name = std.fmt.allocPrint(self.allocator, "{s}{s}", .{ prop_name, suffix }) catch return null;
        self.strings.append(self.allocator, name) catch {
            self.allocator.free(name);
            return null;
        };
        return name;
    }

    pub fn inPropHook(self: *VM, obj: *PhpObject, prop_name: []const u8) bool {
        const obj_id = @intFromPtr(obj);
        for (self.prop_hook_guard.items) |g| {
            if (g.obj_ptr == obj_id and std.mem.eql(u8, g.prop_name, prop_name)) return true;
        }
        return false;
    }

    pub fn callPropHook(self: *VM, obj: *PhpObject, prop_name: []const u8, kind: enum { get, set }, value: Value) RuntimeError!?Value {
        if (self.inPropHook(obj, prop_name)) return null;
        const suffix = switch (kind) { .get => "$hook_get", .set => "$hook_set" };
        const hook_name = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ prop_name, suffix });
        try self.strings.append(self.allocator, hook_name);
        if (!self.hasMethod(obj.class_name, hook_name)) return null;
        const obj_id = @intFromPtr(obj);
        try self.prop_hook_guard.append(self.allocator, .{ .obj_ptr = obj_id, .prop_name = prop_name });
        defer {
            var i: usize = self.prop_hook_guard.items.len;
            while (i > 0) {
                i -= 1;
                const g = self.prop_hook_guard.items[i];
                if (g.obj_ptr == obj_id and std.mem.eql(u8, g.prop_name, prop_name)) {
                    _ = self.prop_hook_guard.swapRemove(i);
                    break;
                }
            }
        }
        const args: []const Value = if (kind == .set) &.{value} else &.{};
        return try self.callMethod(obj, hook_name, args);
    }

    pub fn hasPropHook(self: *VM, class_name: []const u8, prop_name: []const u8, kind: enum { get, set }) bool {
        const suffix = switch (kind) { .get => "$hook_get", .set => "$hook_set" };
        var buf: [256]u8 = undefined;
        const hook_name = std.fmt.bufPrint(&buf, "{s}{s}", .{ prop_name, suffix }) catch return false;
        return self.hasMethod(class_name, hook_name);
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

    pub fn resolveMethod(self: *VM, class_name: []const u8, method_name: []const u8) RuntimeError![]const u8 {
        // single-entry cache: skip string format + hashmap lookup on repeat calls.
        // verify content as well as pointer because callers may pass stack-local
        // bufPrint slices whose memory address gets reused across calls
        if (self.method_cache_class.ptr == class_name.ptr and
            self.method_cache_class.len == class_name.len and
            self.method_cache_method.len == method_name.len and
            std.mem.eql(u8, self.method_cache_method, method_name))
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
        var tried_autoload = false;
        while (true) {
            const full = std.fmt.bufPrint(&buf, "{s}::{s}", .{ current, method_name }) catch return error.RuntimeError;
            if (self.functions.getEntry(full)) |entry| return entry.key_ptr.*;
            if (self.native_fns.getEntry(full)) |entry| return entry.key_ptr.*;
            if (self.classes.get(current)) |cls| {
                if (cls.parent) |p| {
                    current = p;
                    continue;
                }
            } else if (!tried_autoload and self.autoload_callbacks.items.len > 0) {
                tried_autoload = true;
                try self.tryAutoload(current);
                continue;
            }
            return error.RuntimeError;
        }
    }

    fn buildSlotLayout(self: *VM, def: *const ClassDef) RuntimeError!?*PhpObject.SlotLayout {
        // collect all properties walking parent chain (parent first). PHPUnit
        // and similar mature codebases have >64 props in deep hierarchies, so
        // use a growable list instead of a fixed stack buffer
        var all_names: std.ArrayListUnmanaged([]const u8) = .{};
        var all_defaults: std.ArrayListUnmanaged(Value) = .{};
        defer all_names.deinit(self.allocator);
        defer all_defaults.deinit(self.allocator);

        var walk_name = def.parent;
        while (walk_name) |pname| {
            const pcls = self.classes.get(pname) orelse break;
            if (pcls.slot_layout) |pl| {
                for (0..pl.names.len) |i| {
                    try all_names.append(self.allocator, pl.names[i]);
                    try all_defaults.append(self.allocator, pl.defaults[i]);
                }
                break;
            }
            walk_name = pcls.parent;
        }

        for (def.properties.items) |prop| {
            var found = false;
            for (all_names.items, 0..) |n, i| {
                if (std.mem.eql(u8, n, prop.name)) {
                    all_defaults.items[i] = prop.default;
                    found = true;
                    break;
                }
            }
            if (!found) {
                try all_names.append(self.allocator, prop.name);
                try all_defaults.append(self.allocator, prop.default);
            }
        }

        if (all_names.items.len == 0) return null;

        const layout = self.allocator.create(PhpObject.SlotLayout) catch return error.RuntimeError;
        const names = self.allocator.alloc([]const u8, all_names.items.len) catch return error.RuntimeError;
        const defaults = self.allocator.alloc(Value, all_defaults.items.len) catch return error.RuntimeError;
        @memcpy(names, all_names.items);
        @memcpy(defaults, all_defaults.items);
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

    fn arrayUnion(self: *VM, a: *PhpArray, b: *PhpArray) RuntimeError!*PhpArray {
        const result = try self.cloneArray(a);
        for (b.entries.items) |entry| {
            var found = false;
            for (result.entries.items) |existing| {
                if (PhpArray.Key.eql(existing.key, entry.key)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                try result.entries.append(self.allocator, entry);
                if (entry.key == .string) {
                    result.string_index.put(self.allocator, entry.key.string, result.entries.items.len - 1) catch return error.RuntimeError;
                }
            }
        }
        return result;
    }

    fn cloneArray(self: *VM, src: *PhpArray) RuntimeError!*PhpArray {
        // shallow fast path: when the source has no nested arrays we can
        // copy without any cycle tracking. covers the overwhelming majority
        // of php arrays. cloneArrayDeep only runs when at least one entry
        // is an array, where cycles become possible.
        var has_nested = false;
        for (src.entries.items) |entry| {
            if (entry.value == .array) { has_nested = true; break; }
        }
        if (!has_nested) return try self.cloneArrayFlat(src);
        var visited: std.AutoHashMapUnmanaged(*PhpArray, *PhpArray) = .{};
        defer visited.deinit(self.allocator);
        return try self.cloneArrayInner(src, &visited);
    }

    fn cloneArrayFlat(self: *VM, src: *PhpArray) RuntimeError!*PhpArray {
        const copy = self.allocator.create(PhpArray) catch return error.RuntimeError;
        copy.* = .{ .next_int_key = src.next_int_key, .has_int_keys = src.has_int_keys, .cursor = src.cursor };
        copy.entries.ensureTotalCapacity(self.allocator, src.entries.items.len) catch return error.RuntimeError;
        for (src.entries.items, 0..) |entry, i| {
            copy.entries.appendAssumeCapacity(entry);
            if (entry.key == .string) {
                copy.string_index.put(self.allocator, entry.key.string, i) catch return error.RuntimeError;
            }
        }
        self.arrays.append(self.allocator, copy) catch return error.RuntimeError;
        return copy;
    }

    fn cloneArrayInner(
        self: *VM,
        src: *PhpArray,
        visited: *std.AutoHashMapUnmanaged(*PhpArray, *PhpArray),
    ) RuntimeError!*PhpArray {
        if (visited.get(src)) |existing| return existing;
        const copy = self.allocator.create(PhpArray) catch return error.RuntimeError;
        copy.* = .{ .next_int_key = src.next_int_key, .has_int_keys = src.has_int_keys, .cursor = src.cursor };
        visited.put(self.allocator, src, copy) catch return error.RuntimeError;
        copy.entries.ensureTotalCapacity(self.allocator, src.entries.items.len) catch return error.RuntimeError;
        for (src.entries.items, 0..) |entry, i| {
            copy.entries.appendAssumeCapacity(.{
                .key = entry.key,
                .value = if (entry.value == .array)
                    Value{ .array = try self.cloneArrayInner(entry.value.array, visited) }
                else
                    entry.value,
            });
            if (entry.key == .string) {
                copy.string_index.put(self.allocator, entry.key.string, i) catch return error.RuntimeError;
            }
        }
        self.arrays.append(self.allocator, copy) catch return error.RuntimeError;
        return copy;
    }

    pub fn copyValue(self: *VM, val: Value) RuntimeError!Value {
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
                if (std.mem.eql(u8, cap.var_name, "$__closure_scope")) continue;
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

    pub fn getOrigClosureName(self: *VM, name: []const u8) []const u8 {
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
        if (func.is_variadic and func.arity > 0) {
            const fixed: usize = func.arity - 1;
            const bind_fixed = @min(args.len, fixed);
            for (0..bind_fixed) |i| {
                try vars.put(self.allocator, func.params[i], try self.copyValue(args[i]));
            }
            const rest = try self.allocator.create(PhpArray);
            rest.* = .{};
            for (fixed..args.len) |i| {
                try rest.append(self.allocator, try self.copyValue(args[i]));
            }
            try self.arrays.append(self.allocator, rest);
            try vars.put(self.allocator, func.params[fixed], .{ .array = rest });
            return;
        }
        for (0..args.len) |i| {
            try vars.put(self.allocator, func.params[i], try self.copyValue(args[i]));
        }
        try self.fillDefaults(vars, func, args.len);
    }

    pub fn resolveDefault(self: *VM, val: Value) !Value {
        if (val.isEmptyArrayDefault()) {
            const arr = try self.allocator.create(PhpArray);
            arr.* = .{};
            try self.arrays.append(self.allocator, arr);
            return .{ .array = arr };
        }
        if (val == .array) {
            const arr = try self.allocator.create(PhpArray);
            arr.* = .{};
            try self.arrays.append(self.allocator, arr);
            for (val.array.entries.items) |entry| {
                try arr.set(self.allocator, entry.key, entry.value);
            }
            return .{ .array = arr };
        }
        if (val == .string) {
            const s = val.string;
            // deferred class constant: "\x00CC\x00ClassName\x00CONST_NAME"
            if (s.len > 4 and s[0] == 0 and s[1] == 'C' and s[2] == 'C' and s[3] == 0) {
                const rest = s[4..];
                if (std.mem.indexOfScalar(u8, rest, 0)) |sep| {
                    const class_name = rest[0..sep];
                    const const_name = rest[sep + 1 ..];
                    if (class_name.len == 0) {
                        if (self.php_constants.get(const_name)) |v| return v;
                        return .null;
                    }
                    if (self.getStaticProp(class_name, const_name)) |v| return v;
                    // fall back to class constants (ClassName::CONST_NAME)
                    var buf: [512]u8 = undefined;
                    const full = std.fmt.bufPrint(&buf, "{s}::{s}", .{ class_name, const_name }) catch return .null;
                    if (self.php_constants.get(full)) |v| return v;
                    return .null;
                }
            }
            // deferred new-expression default: "\x00NW\x00<8 byte ptr>"
            if (bytecode.newDefaultPtr(s)) |nd| {
                return self.instantiateForDefault(nd);
            }
        }
        return val;
    }

    fn instantiateForDefault(self: *VM, nd: *const bytecode.NewDefault) RuntimeError!Value {
        var class_name = nd.class_name;
        if (std.mem.eql(u8, class_name, "self") or std.mem.eql(u8, class_name, "static")) {
            if (self.currentDefiningClass()) |dc| class_name = dc;
        } else if (std.mem.eql(u8, class_name, "parent")) {
            if (self.parentResolvingClass()) |dc| {
                if (self.classes.get(dc)) |cls| {
                    if (cls.parent) |p| class_name = p;
                }
            }
        }
        if (!self.classes.contains(class_name)) {
            try self.tryAutoload(class_name);
        }
        if (!self.classes.contains(class_name)) {
            const msg = try std.fmt.allocPrint(self.allocator, "Class \"{s}\" not found", .{class_name});
            try self.strings.append(self.allocator, msg);
            self.error_msg = msg;
            return error.RuntimeError;
        }
        const obj = try self.allocator.create(PhpObject);
        obj.* = .{ .class_name = class_name };
        try self.objects.append(self.allocator, obj);
        try self.initObjectProperties(obj, class_name);

        var resolved_args: [16]Value = undefined;
        const n_args = @min(nd.args.len, resolved_args.len);
        for (0..n_args) |i| resolved_args[i] = try self.resolveDefault(nd.args[i]);

        if (self.resolveMethod(class_name, "__construct") catch null) |_| {
            _ = try self.callMethod(obj, "__construct", resolved_args[0..n_args]);
        }
        return .{ .object = obj };
    }

    fn fillDefaults(self: *VM, vars: *std.StringHashMapUnmanaged(Value), func: *const ObjFunction, arg_count: usize) !void {
        if (arg_count >= func.arity) return;
        for (arg_count..func.arity) |i| {
            if (i < func.defaults.len) {
                try vars.put(self.allocator, func.params[i], try self.resolveDefault(func.defaults[i]));
            } else {
                try vars.put(self.allocator, func.params[i], .null);
            }
        }
    }

    fn executeFunction(self: *VM, func: *const ObjFunction, vars: std.StringHashMapUnmanaged(Value)) RuntimeError!Value {
        if (self.frame_count >= 2047) {
            self.error_msg = "Fatal error: maximum call stack depth exceeded";
            return error.RuntimeError;
        }
        const base_frame = self.frame_count;
        const base_handler = self.handler_count;
        const prev_floor = self.handler_floor;
        self.handler_floor = self.handler_count;
        self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = vars, .locals = try self.allocLocals(func, &vars), .func = func, .call_name = self.pending_call_name };
        self.frames[self.frame_count].entry_sp = self.sp;
        self.consumePendingArgCount();
        if (self.pending_invoke_args) |pia| self.saveFrameArgsSlice(pia);
        self.pending_call_name = null;
        self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
        self.runUntilFrame(base_frame) catch |err| {
            self.handler_count = base_handler;
            self.handler_floor = prev_floor;
            return err;
        };
        self.handler_count = base_handler;
        self.handler_floor = prev_floor;
        return self.pop();
    }

    pub fn executeFunctionWithRefs(self: *VM, func: *const ObjFunction, vars: std.StringHashMapUnmanaged(Value), ref_slots: std.StringHashMapUnmanaged(*Value)) RuntimeError!Value {
        if (self.frame_count >= 2047) {
            self.error_msg = "Fatal error: maximum call stack depth exceeded";
            return error.RuntimeError;
        }
        const base_frame = self.frame_count;
        const base_handler = self.handler_count;
        const prev_floor = self.handler_floor;
        self.handler_floor = self.handler_count;
        self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = vars, .locals = try self.allocLocals(func, &vars), .func = func, .ref_slots = ref_slots, .call_name = self.pending_call_name };
        self.frames[self.frame_count].entry_sp = self.sp;
        self.consumePendingArgCount();
        if (self.pending_invoke_args) |pia| self.saveFrameArgsSlice(pia);
        self.pending_call_name = null;
        self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
        self.runUntilFrame(base_frame) catch |err| {
            self.handler_count = base_handler;
            self.handler_floor = prev_floor;
            return err;
        };
        self.handler_count = base_handler;
        self.handler_floor = prev_floor;
        return self.pop();
    }

    fn varVarName(raw_name: []const u8, buf: *[256]u8) []const u8 {
        if (raw_name.len > 0 and raw_name[0] == '$') return raw_name;
        if (raw_name.len + 1 > buf.len) return raw_name;
        buf[0] = '$';
        @memcpy(buf[1 .. 1 + raw_name.len], raw_name);
        return buf[0 .. 1 + raw_name.len];
    }

    noinline fn valueTypeName(val: Value) []const u8 {
        return switch (val) {
            .int => "int",
            .float => "float",
            // PHP's error messages spell out 'true'/'false' for bool values,
            // not 'bool'. matters for "Call to a member function X() on false"
            .bool => |b| if (b) "true" else "false",
            .string => "string",
            .array => "array",
            .object => |obj| obj.class_name,
            .null => "null",
            .generator => "Generator",
            .fiber => "Fiber",
        };
    }

    fn tryWeakCoerce(self: *VM, val: Value, type_str: []const u8) RuntimeError!?Value {
        var t = type_str;
        if (t.len > 0 and t[0] == '?') t = t[1..];
        // bail on intersection types
        for (t) |c| if (c == '&' or c == '(' or c == ')') return null;
        // unions: try each member in PHP's priority order, returning the first
        // that coerces successfully without lossy conversion. PHP's rule is to
        // pick the type the value already matches; failing that, scalar values
        // prefer int > float > string > bool (and the converse for non-scalars)
        if (std.mem.indexOfScalar(u8, t, '|') != null) {
            return try self.tryWeakCoerceUnion(val, t);
        }
        return try self.tryWeakCoerceSingle(val, t);
    }

    fn tryWeakCoerceSingle(self: *VM, val: Value, t: []const u8) RuntimeError!?Value {
        if (std.mem.eql(u8, t, "int") or std.mem.eql(u8, t, "integer")) {
            return switch (val) {
                .bool => |b| Value{ .int = if (b) @as(i64, 1) else 0 },
                .float => |f| if (std.math.isFinite(f)) Value{ .int = @as(i64, @intFromFloat(f)) } else null,
                .string => |s| if (Value.isNumericString(s)) Value{ .int = Value.toInt(val) } else null,
                else => null,
            };
        }
        if (std.mem.eql(u8, t, "float") or std.mem.eql(u8, t, "double")) {
            return switch (val) {
                .int => |i| Value{ .float = @floatFromInt(i) },
                .bool => |b| Value{ .float = if (b) @as(f64, 1) else 0 },
                .string => |s| if (Value.isNumericString(s)) Value{ .float = Value.toFloat(val) } else null,
                else => null,
            };
        }
        if (std.mem.eql(u8, t, "bool") or std.mem.eql(u8, t, "boolean")) {
            return switch (val) {
                .int => |i| Value{ .bool = i != 0 },
                .float => |f| Value{ .bool = f != 0 },
                .string => |s| Value{ .bool = !(s.len == 0 or (s.len == 1 and s[0] == '0')) },
                .null => Value{ .bool = false },
                else => null,
            };
        }
        if (std.mem.eql(u8, t, "string")) {
            return switch (val) {
                .int, .float, .bool => try self.coerceToStringValue(val),
                else => null,
            };
        }
        return null;
    }

    fn coerceToStringValue(self: *VM, val: Value) RuntimeError!Value {
        var buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer buf.deinit(self.allocator);
        try val.format(&buf, self.allocator);
        const s = try buf.toOwnedSlice(self.allocator);
        try self.strings.append(self.allocator, s);
        return Value{ .string = s };
    }

    // PHP weak-mode union resolution. for a value V against `int|float|string|bool`,
    // PHP checks types in this order: int, float, string, bool. the first type
    // V already matches wins; otherwise the first coercible match wins. when
    // multiple coercions could succeed (e.g. "5" against int|float), int wins
    // since it appears first in the priority order
    fn tryWeakCoerceUnion(self: *VM, val: Value, t: []const u8) RuntimeError!?Value {
        const priority = [_][]const u8{ "int", "float", "string", "bool" };

        // first pass: exact match (no coercion)
        var iter = std.mem.tokenizeScalar(u8, t, '|');
        while (iter.next()) |member| {
            const m = std.mem.trim(u8, member, " \t");
            if (self.checkSingleType(val, m)) return val;
        }

        // second pass: scalar coercion in priority order, but only for types
        // listed in the union
        for (priority) |p| {
            var iter2 = std.mem.tokenizeScalar(u8, t, '|');
            while (iter2.next()) |member| {
                const m = std.mem.trim(u8, member, " \t");
                const canonical: []const u8 = if (std.mem.eql(u8, m, "integer")) "int" else if (std.mem.eql(u8, m, "double")) "float" else if (std.mem.eql(u8, m, "boolean")) "bool" else m;
                if (!std.mem.eql(u8, canonical, p)) continue;
                if (try self.tryWeakCoerceSingle(val, canonical)) |coerced| return coerced;
            }
        }
        return null;
    }

    noinline fn checkSingleType(self: *VM, val: Value, type_name: []const u8) bool {
        if (std.mem.eql(u8, type_name, "mixed")) return true;
        if (std.mem.eql(u8, type_name, "void")) return val == .null;
        if (std.mem.eql(u8, type_name, "int") or std.mem.eql(u8, type_name, "integer")) return val == .int;
        if (std.mem.eql(u8, type_name, "float") or std.mem.eql(u8, type_name, "double")) return val == .float or val == .int;
        if (std.mem.eql(u8, type_name, "bool") or std.mem.eql(u8, type_name, "boolean")) return val == .bool or val == .int;
        if (std.mem.eql(u8, type_name, "string")) {
            if (val == .string) return true;
            if (val == .object and self.hasMethod(val.object.class_name, "__toString")) return true;
            return false;
        }
        if (std.mem.eql(u8, type_name, "array")) return val == .array;
        if (std.mem.eql(u8, type_name, "callable")) return val == .string or val == .array or val == .object;
        if (std.mem.eql(u8, type_name, "null")) return val == .null;
        if (std.mem.eql(u8, type_name, "false")) return val == .bool and !val.bool;
        if (std.mem.eql(u8, type_name, "true")) return val == .bool and val.bool;
        if (std.mem.eql(u8, type_name, "object")) return val == .object;
        if (std.mem.eql(u8, type_name, "iterable")) {
            if (val == .array or val == .generator) return true;
            if (val == .object) {
                if (self.hasMethod(val.object.class_name, "getIterator")) return true;
                if (self.isInstanceOf(val.object.class_name, "Iterator")) return true;
                if (self.isInstanceOf(val.object.class_name, "IteratorAggregate")) return true;
                if (self.isInstanceOf(val.object.class_name, "Traversable")) return true;
            }
            return false;
        }
        if (std.mem.eql(u8, type_name, "self") or std.mem.eql(u8, type_name, "static") or std.mem.eql(u8, type_name, "parent")) return val == .object;
        if (std.mem.eql(u8, type_name, "Traversable") or std.mem.eql(u8, type_name, "Iterator") or std.mem.eql(u8, type_name, "IteratorAggregate")) {
            return val == .object or val == .array or val == .generator;
        }
        if (std.mem.eql(u8, type_name, "Generator")) return val == .generator;
        if (std.mem.eql(u8, type_name, "Fiber")) return val == .fiber;
        if (std.mem.eql(u8, type_name, "Closure")) return val == .string and if (val.string.len > 10) std.mem.startsWith(u8, val.string, "__closure_") else false;
        if (val == .object) {
            // a leading backslash in a type name (e.g. `\DOMNode`) is a fully-qualified
            // marker carried over from the source; class names in the registry never
            // include it. strip it before the instanceof walk
            const stripped = if (type_name.len > 0 and type_name[0] == '\\') type_name[1..] else type_name;
            return self.isInstanceOf(val.object.class_name, stripped);
        }
        return false;
    }

    pub noinline fn checkTypeMatch(self: *VM, val: Value, type_str: []const u8) bool {
        if (type_str.len == 0) return true;
        if (type_str[0] == '?') {
            if (val == .null) return true;
            return self.checkTypeMatch(val, type_str[1..]);
        }
        // top-level union: split on '|' respecting parens
        var depth: i32 = 0;
        var start: usize = 0;
        for (type_str, 0..) |c, i| {
            if (c == '(') depth += 1
            else if (c == ')') depth -= 1
            else if (c == '|' and depth == 0) {
                if (self.checkIntersection(val, type_str[start..i])) return true;
                start = i + 1;
            }
        }
        return self.checkIntersection(val, type_str[start..]);
    }

    noinline fn checkIntersection(self: *VM, val: Value, expr: []const u8) bool {
        if (expr.len == 0) return true;
        var s = expr;
        if (s.len >= 2 and s[0] == '(' and s[s.len - 1] == ')') s = s[1 .. s.len - 1];
        var depth: i32 = 0;
        var start: usize = 0;
        for (s, 0..) |c, i| {
            if (c == '(') depth += 1
            else if (c == ')') depth -= 1
            else if (c == '&' and depth == 0) {
                if (!self.checkSingleType(val, s[start..i])) return false;
                start = i + 1;
            }
        }
        return self.checkSingleType(val, s[start..]);
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
                // weak-mode coercion: PHP's default is non-strict, so a numeric
                // string passes int/float, scalars convert into each other,
                // etc. only fall through to the TypeError path if coercion
                // cannot produce a matching value. caller's file determines the
                // mode - a strict_types=1 file calling a non-strict function
                // still gets strict argument checking
                const caller_strict = blk: {
                    if (self.frame_count >= 2) {
                        const caller = &self.frames[self.frame_count - 2];
                        if (caller.func) |cf| break :blk cf.strict_types;
                    }
                    break :blk self.script_strict_types;
                };
                if (!caller_strict) {
                    if (try self.tryWeakCoerce(val, type_str)) |coerced| {
                        self.stack[self.sp - ac + i] = coerced;
                        continue;
                    }
                }
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
            if (val == .object and self.typeStrAllowsString(type_str) and self.hasMethod(val.object.class_name, "__toString")) {
                const s = try self.objectToString(val.object);
                self.stack[self.sp - ac + i] = .{ .string = s };
            }
        }
        return false;
    }

    noinline fn checkReturnType(self: *VM, val: *Value) RuntimeError!bool {
        if (g_type_info.count() == 0) return false;
        const frame = &self.frames[self.frame_count - 1];
        const func_name = if (frame.func) |f| f.name else return false;
        const ti = g_type_info.get(func_name) orelse return false;
        if (ti.return_type.len == 0) return false;
        if (!self.checkTypeMatch(val.*, ti.return_type)) {
            const msg = std.fmt.allocPrint(self.allocator, "{s}(): Return value must be of type {s}, {s} returned", .{ func_name, ti.return_type, valueTypeName(val.*) }) catch return error.RuntimeError;
            try self.strings.append(self.allocator, msg);
            self.error_msg = msg;
            try self.popFrame();
            if (try self.throwBuiltinException("TypeError", msg)) return true;
            return error.RuntimeError;
        }
        // coerce Stringable -> string when return type allows string
        if (val.* == .object and self.typeStrAllowsString(ti.return_type) and self.hasMethod(val.object.class_name, "__toString")) {
            const s = try self.objectToString(val.object);
            val.* = .{ .string = s };
        }
        return false;
    }

    fn typeStrAllowsString(_: *VM, type_str: []const u8) bool {
        var s = type_str;
        if (s.len > 0 and s[0] == '?') s = s[1..];
        return std.mem.eql(u8, s, "string");
    }

    fn isAncestor(self: *VM, ancestor: []const u8, descendant: []const u8) bool {
        if (std.mem.eql(u8, ancestor, descendant)) return true;
        var current: ?[]const u8 = descendant;
        while (current) |name| {
            const cls = self.classes.get(name) orelse return false;
            current = cls.parent;
            if (current) |p| {
                if (std.mem.eql(u8, p, ancestor)) return true;
            }
        }
        return false;
    }

    fn callStaticFunction(self: *VM, name: []const u8, arg_count: u8, class_name: []const u8) RuntimeError!void {
        const fc_before = self.frame_count;
        const prev_cc = self.currentFrame().called_class;
        // set called_class on current frame so both native fns and localsOnly
        // paths can inherit it (localsOnly executes inline and won't be caught
        // by the post-call fixup below)
        self.currentFrame().called_class = class_name;
        defer self.frames[fc_before - 1].called_class = prev_cc;
        try self.callNamedFunction(name, arg_count);
        if (self.frame_count > fc_before)
            self.frames[self.frame_count - 1].called_class = class_name;
    }

    fn callNamedFunction(self: *VM, raw_name: []const u8, arg_count: u8) RuntimeError!void {
        // PHP normalizes leading-backslash on function callable strings
        const name = if (raw_name.len > 0 and raw_name[0] == '\\') raw_name[1..] else raw_name;
        if (self.native_fns.get(name)) |native| {
            var args: [64]Value = undefined;
            const ac: usize = arg_count;
            for (0..ac) |i| args[i] = self.stack[self.sp - ac + i];
            self.sp -= ac;
            const pre_handler_count = self.handler_count;
            var ctx = self.makeContext(name);
            const result = native(&ctx, args[0..ac]) catch {
                if (self.pending_exception) |exc| {
                    self.pending_exception = null;
                    if (self.handler_count > self.handler_floor) {
                        const handler = self.exception_handlers[self.handler_count - 1];
                        self.handler_count -= 1;
                        while (self.frame_count > handler.frame_count) {
                            self.frame_count -= 1;
                            self.deinitFrameSlot(self.frame_count);
                        }
                        self.sp = handler.sp;
                        self.push(exc);
                        self.currentFrame().ip = handler.catch_ip;
                        return;
                    }
                    self.pending_exception = exc;
                } else if (self.handler_count < pre_handler_count) {
                    // throwBuiltinException already claimed a handler during the
                    // native (decremented handler_count, set ip to catch_ip, pushed
                    // exc on stack). just resume so the catch block runs
                    return;
                }
                return error.RuntimeError;
            };
            self.push(result);
        } else if (self.functions.get(name)) |func| {
            const ac: usize = arg_count;
            if (ac < func.required_params) {
                const msg = std.fmt.allocPrint(self.allocator, "Too few arguments to function {s}(), {d} passed, {d} required", .{ name, ac, func.required_params }) catch "Too few arguments";
                try self.strings.append(self.allocator, msg);
                if (try self.throwBuiltinException("ArgumentCountError", msg)) return;
                self.setErrorMsg("Fatal error: Uncaught ArgumentCountError: {s}\n", .{msg});
                return error.RuntimeError;
            }
            if (g_type_info.count() > 0) {
                if (try self.checkParamTypes(name, arg_count)) return;
            }
            self.pending_call_name = name;
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
                for (@min(ac, fixed)..fixed) |i| {
                    if (i < func.defaults.len) try new_vars.put(self.allocator, func.params[i], try self.resolveDefault(func.defaults[i]));
                }
                const rest_arr = try self.allocator.create(PhpArray);
                rest_arr.* = .{};
                if (ac > fixed) {
                    for (fixed..ac) |i| {
                        try rest_arr.append(self.allocator, self.stack[self.sp - ac + i]);
                    }
                }
                try self.arrays.append(self.allocator, rest_arr);
                try new_vars.put(self.allocator, func.params[fixed], .{ .array = rest_arr });
            } else {
                const bind_count = @min(ac, func.arity);
                for (0..bind_count) |i| {
                    // for ref params, share the caller's value (especially the
                    // array/object pointer) so mutations through the param
                    // surface back. copyValue would deep-clone the array and
                    // sever the ref relationship
                    const is_ref = i < func.ref_params.len and func.ref_params[i];
                    const slot_val = if (is_ref) self.stack[self.sp - ac + i] else try self.copyValue(self.stack[self.sp - ac + i]);
                    try new_vars.put(self.allocator, func.params[i], slot_val);
                }
            }
            self.saveFrameArgs(arg_count);
            self.sp -= ac;
            if (!func.is_variadic) {
                try self.fillDefaults(&new_vars, func, @min(ac, func.arity));
            }
            var callee_refs = closure_refs;
            var callee_array_bindings: std.ArrayListUnmanaged(ArrayRefBinding) = .{};
            var callee_object_bindings: std.ArrayListUnmanaged(ObjectRefBinding) = .{};
            try self.bindRefParams(ac, func, &new_vars, &callee_refs, &callee_array_bindings, &callee_object_bindings);

            if (func.is_generator) {
                // by-ref params: ref_slots on the generator so subsequent
                // function calls inside the body see the cells; array/object
                // bindings aren't represented on Generator yet
                callee_array_bindings.deinit(self.allocator);
                callee_object_bindings.deinit(self.allocator);
                const gen = try self.allocator.create(Generator);
                gen.* = .{ .func = func, .vars = new_vars, .ref_slots = callee_refs };
                try self.generators.append(self.allocator, gen);
                self.push(.{ .generator = gen });
            } else {
                if (self.frame_count >= 2047) {
                    new_vars.deinit(self.allocator);
                    callee_refs.deinit(self.allocator);
                    callee_array_bindings.deinit(self.allocator);
                    callee_object_bindings.deinit(self.allocator);
                    const msg = std.fmt.allocPrint(self.allocator, "Maximum function nesting level of 2048 reached, aborting in {s}()", .{name}) catch "Maximum function nesting level reached";
                    try self.strings.append(self.allocator, msg);
                    if (try self.throwBuiltinException("Error", msg)) return;
                    self.error_msg = msg;
                    return error.RuntimeError;
                }
                const inherit_cc = if (std.mem.startsWith(u8, name, "__closure_"))
                    self.closureScopeByName(name) orelse self.currentFrame().called_class
                else
                    null;
                self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars, .locals = try self.allocLocals(func, &new_vars), .func = func, .ref_slots = callee_refs, .ref_array_bindings = callee_array_bindings, .ref_object_bindings = callee_object_bindings, .called_class = inherit_cc, .call_name = name };
                self.frames[self.frame_count].entry_sp = self.sp;
                self.setFrameArgCount(arg_count);
                self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
            }
        } else {
            if (std.mem.lastIndexOfScalar(u8, name, '\\')) |pos| {
                const base = name[pos + 1 ..];
                if (base.len > 0) return self.callNamedFunction(base, arg_count);
            }
            const msg = std.fmt.allocPrint(self.allocator, "Call to undefined function {s}()", .{name}) catch "Call to undefined function";
            try self.strings.append(self.allocator, msg);
            if (try self.throwBuiltinException("Error", msg)) return;
            self.setErrorMsg("Fatal error: Uncaught Error: {s}\n", .{msg});
            return error.RuntimeError;
        }
    }

    pub fn callMethod(self: *VM, obj: *PhpObject, method_name: []const u8, args: []const Value) RuntimeError!Value {
        if (self.frame_count >= 2047) {
            self.error_msg = "Fatal error: maximum call stack depth exceeded";
            return error.RuntimeError;
        }
        const full_name = self.resolveMethod(obj.class_name, method_name) catch return error.RuntimeError;
        if (self.native_fns.get(full_name)) |native| {
            var tmp_vars: std.StringHashMapUnmanaged(Value) = .{};
            try tmp_vars.put(self.allocator, "$this", .{ .object = obj });
            self.frames[self.frame_count] = .{ .chunk = self.currentChunk(), .ip = self.currentFrame().ip, .vars = tmp_vars };
            self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
            var ctx = self.makeContext(null);
            const result = try native(&ctx, args);
            self.frame_count -= 1;
            self.deinitFrameSlot(self.frame_count);
            return result;
        } else if (self.functions.get(full_name)) |func| {
            if (args.len < func.required_params) return error.RuntimeError;
            var new_vars: std.StringHashMapUnmanaged(Value) = .{};
            try new_vars.put(self.allocator, "$this", .{ .object = obj });
            try self.bindClosures(&new_vars, null, full_name);
            const trimmed = if (func.is_variadic) args else args[0..@min(args.len, func.arity)];
            try self.bindArgs(&new_vars, func, trimmed);
            if (func.is_generator) {
                const gen = try self.allocator.create(Generator);
                gen.* = .{ .func = func, .vars = new_vars };
                try self.generators.append(self.allocator, gen);
                return .{ .generator = gen };
            }
            return self.executeFunction(func, new_vars);
        } else return error.RuntimeError;
    }

    fn callMagicGet(self: *VM, obj: *PhpObject, prop_name: []const u8) RuntimeError!Value {
        const obj_id = @intFromPtr(obj);
        for (self.magic_get_guard.items) |e| {
            if (e.obj_ptr == obj_id and std.mem.eql(u8, e.prop_name, prop_name)) return .null;
        }
        try self.magic_get_guard.append(self.allocator, .{ .obj_ptr = obj_id, .prop_name = prop_name });
        const result = self.callMethod(obj, "__get", &.{.{ .string = prop_name }}) catch |err| blk: {
            self.removeMagicGetGuard(obj_id, prop_name);
            if (err == error.RuntimeError) return error.RuntimeError;
            break :blk .null;
        };
        self.removeMagicGetGuard(obj_id, prop_name);
        return result;
    }

    fn removeMagicGetGuard(self: *VM, obj_id: usize, prop_name: []const u8) void {
        var i: usize = self.magic_get_guard.items.len;
        while (i > 0) {
            i -= 1;
            if (self.magic_get_guard.items[i].obj_ptr == obj_id and std.mem.eql(u8, self.magic_get_guard.items[i].prop_name, prop_name)) {
                _ = self.magic_get_guard.swapRemove(i);
                return;
            }
        }
    }

    fn removeCallGuard(self: *VM, obj_id: usize, method_name: []const u8) void {
        var i: usize = self.magic_call_guard.items.len;
        while (i > 0) {
            i -= 1;
            if (self.magic_call_guard.items[i].obj_ptr == obj_id and std.mem.eql(u8, self.magic_call_guard.items[i].method_name, method_name)) {
                _ = self.magic_call_guard.swapRemove(i);
                return;
            }
        }
    }

    pub fn runShutdownCallbacks(self: *VM) !void {
        // PHP runs shutdown callbacks in registration order, after the script
        // returns; errors in one don't prevent the others from firing.
        for (self.shutdown_callbacks.items) |cb| {
            const result = if (cb == .string) self.callByName(cb.string, &.{}) catch null
                          else if (cb == .object) blk: {
                              if (self.hasMethod(cb.object.class_name, "__invoke")) {
                                  break :blk self.callMethod(cb.object, "__invoke", &.{}) catch null;
                              }
                              break :blk null;
                          } else null;
            _ = result;
        }
        self.shutdown_callbacks.clearRetainingCapacity();
    }

    pub fn callByName(self: *VM, raw_name: []const u8, args: []const Value) RuntimeError!Value {
        // PHP normalizes leading-backslash on function callable strings:
        // call_user_func('\App\f') and call_user_func('App\f') are equivalent
        const name = if (raw_name.len > 0 and raw_name[0] == '\\') raw_name[1..] else raw_name;
        if (self.native_fns.get(name)) |native| {
            var ctx = self.makeContext(null);
            return native(&ctx, args);
        } else if (self.functions.get(name)) |func| {
            if (args.len < func.required_params) return error.RuntimeError;
            if (self.ic) |ic| ic.pending_arg_count = @intCast(@min(args.len, 255));
            self.pending_call_name = name;
            const saved_pia_outer = self.pending_invoke_args;
            self.pending_invoke_args = args;
            defer self.pending_invoke_args = saved_pia_outer;
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
            const trimmed = if (func.is_variadic) args else args[0..@min(args.len, func.arity)];
            try self.bindArgs(&new_vars, func, trimmed);
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

    pub fn getCaptureRange(self: *VM, name: []const u8) ?CaptureRange {
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
            if (i < func.defaults.len) locals[i] = try self.resolveDefault(func.defaults[i]);
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
        const base_handler = self.handler_count;
        const prev_floor = self.handler_floor;
        self.handler_floor = self.handler_count;
        self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = .{}, .locals = locals, .func = func, .called_class = self.closureScopeByName(name) orelse self.currentFrame().called_class };
        self.frames[self.frame_count].entry_sp = self.sp;
        self.consumePendingArgCount();
        self.saveFrameArgsSlice(args);
        self.frame_count += 1;
        if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
        self.fastLoop() catch |err| {
            self.handler_count = base_handler;
            self.handler_floor = prev_floor;
            return err;
        };
        if (self.frame_count > base_frame) {
            self.runUntilFrame(base_frame) catch |err| {
                self.handler_count = base_handler;
                self.handler_floor = prev_floor;
                return err;
            };
        }
        self.handler_count = base_handler;
        self.handler_floor = prev_floor;
        return self.pop();
    }

    pub fn callByNameRef(self: *VM, raw_name: []const u8, args: []Value) RuntimeError!Value {
        const name = if (raw_name.len > 0 and raw_name[0] == '\\') raw_name[1..] else raw_name;
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
                self.frames[self.frame_count].ref_array_bindings.deinit(self.allocator);
                self.frames[self.frame_count].ref_object_bindings.deinit(self.allocator);
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
        for (self.frames[base_frame..self.frame_count]) |*frame| {
            try fiber.saved_frames.append(self.allocator, .{
                .chunk = frame.chunk,
                .ip = frame.ip,
                .vars = frame.vars,
                .locals = frame.locals,
                .func = frame.func,
                .called_class = frame.called_class,
                .generator = frame.generator,
                .ref_slots = frame.ref_slots,
                .ref_array_bindings = frame.ref_array_bindings,
                .ref_object_bindings = frame.ref_object_bindings,
            });
            // null out the source's owned data so VM cleanup can't double-free
            frame.vars = .{};
            frame.ref_slots = .{};
            frame.ref_array_bindings = .{};
            frame.ref_object_bindings = .{};
            frame.locals = &.{};
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
        for (fiber.saved_frames.items, 0..) |*frame, i| {
            self.frames[base_frame + i] = .{
                .chunk = frame.chunk,
                .ip = frame.ip,
                .vars = frame.vars,
                .locals = frame.locals,
                .func = frame.func,
                .called_class = frame.called_class,
                .generator = frame.generator,
                .ref_slots = frame.ref_slots,
                .ref_array_bindings = frame.ref_array_bindings,
                .ref_object_bindings = frame.ref_object_bindings,
            };
            // null out source to avoid double-free if cleanupFiberFrames runs later
            frame.vars = .{};
            frame.ref_slots = .{};
            frame.ref_array_bindings = .{};
            frame.ref_object_bindings = .{};
            frame.locals = &.{};
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

    fn readU32(self: *VM) u32 {
        const b0: u32 = self.readByte();
        const b1: u32 = self.readByte();
        const b2: u32 = self.readByte();
        const b3: u32 = self.readByte();
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
    }

    pub fn currentChunk(self: *const VM) *const Chunk {
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

    fn saveFrameArgs(self: *VM, arg_count: u8) void {
        const ic = self.ic orelse return;
        if (self.frame_count >= 2048) return;
        const ac: usize = arg_count;
        if (ac == 0) {
            ic.fga_offsets[self.frame_count] = ic.fga_sp;
            return;
        }
        const sp = ic.fga_sp;
        if (sp + ac > ic.fga_buf.len) return;
        ic.fga_offsets[self.frame_count] = sp;
        for (0..ac) |i| {
            ic.fga_buf[sp + i] = self.stack[self.sp - ac + i];
        }
        ic.fga_sp = @intCast(sp + ac);
    }

    // saveFrameArgs equivalent for callers that have args in a slice (not on
    // the value stack). without this, native-driven invocations (e.g. PDO
    // sqliteCreateFunction callbacks, sort comparators) leave fga_buf with
    // stale entries from whatever last touched that frame slot, and
    // func_get_args returns the previous call's args
    pub fn saveFrameArgsSlice(self: *VM, args: []const Value) void {
        const ic = self.ic orelse return;
        if (self.frame_count >= 2048) return;
        const ac: usize = args.len;
        if (ac == 0) {
            ic.fga_offsets[self.frame_count] = ic.fga_sp;
            return;
        }
        const sp = ic.fga_sp;
        if (sp + ac > ic.fga_buf.len) {
            // signal "no saved args" by leaving offsets stale; getFrameArgs
            // will read whatever's there but at least we shouldn't crash
            return;
        }
        ic.fga_offsets[self.frame_count] = sp;
        for (0..ac) |i| ic.fga_buf[sp + i] = args[i];
        ic.fga_sp = @intCast(sp + ac);
    }

    fn restoreFrameArgsSp(self: *VM) void {
        const ic = self.ic orelse return;
        ic.fga_sp = ic.fga_offsets[self.frame_count];
    }

    pub fn getFrameArgs(self: *VM) ?[]const Value {
        const ic = self.ic orelse return null;
        const fc = self.frame_count - 1;
        const ac_raw = ic.arg_counts[fc];
        if (ac_raw == 0xFF) return null;
        const ac: usize = ac_raw;
        const offset: usize = ic.fga_offsets[fc];
        if (offset + ac > ic.fga_buf.len) return null;
        return ic.fga_buf[offset..offset + ac];
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

