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

extern fn zphp_fast_loop(vm_ptr: *anyopaque) callconv(.c) u8;

const TypeInfo = struct {
    param_types: []const []const u8 = &.{},
    return_type: []const u8 = "",
};
var g_type_info: std.StringHashMapUnmanaged(TypeInfo) = .{};
var g_type_info_allocator: ?Allocator = null;

pub fn getTypeInfo(key: []const u8) ?TypeInfo {
    return g_type_info.get(key);
}

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
        try self.vm.initObjectProperties(obj, class_name);
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
        if (caller.ip < 4) return;
        const call_pos = caller.ip - 4;
        const code = chunk.code.items;

        // forward-scan to find instruction boundaries leading to the call
        // argument expressions don't contain variable-length instructions
        const max_scan = arg_count * 12;
        const region_start = if (call_pos > max_scan) call_pos - max_scan else 0;

        // try alignments until forward scan lands exactly on call_pos
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
        if (instr_count == 0) return;

        // walk backward through instructions using stack simulation to group into args
        var arg_vars: [16]?[]const u8 = .{null} ** 16;
        var scan_idx: usize = arg_count;
        var i = instr_count;

        while (scan_idx > 0 and i > 0) {
            scan_idx -= 1;
            var depth: i32 = 0;
            const arg_end = i;
            while (i > 0 and depth < 1) {
                i -= 1;
                const op: OpCode = @enumFromInt(code[instrs[i]]);
                depth += @as(i32, op.stackEffect());
            }
            if (depth < 1) break;

            // single-instruction variable arg: exactly one instruction that's get_var/get_local
            if (arg_end - i == 1) {
                const ip = instrs[i];
                if (code[ip] == @intFromEnum(OpCode.get_var)) {
                    const const_idx = (@as(u16, code[ip + 1]) << 8) | code[ip + 2];
                    if (const_idx < chunk.constants.items.len) {
                        arg_vars[scan_idx] = chunk.constants.items[const_idx].string;
                    }
                } else if (code[ip] == @intFromEnum(OpCode.get_local)) {
                    const slot = (@as(u16, code[ip + 1]) << 8) | code[ip + 2];
                    const sn = if (caller.func) |func| func.slot_names else vm.global_slot_names;
                    if (slot < sn.len) {
                        arg_vars[scan_idx] = sn[slot];
                    }
                }
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

pub const CaptureRange = struct {
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
    used_traits: std.ArrayListUnmanaged([]const u8) = .{},

    pub const Visibility = enum(u8) { public = 0, protected = 1, private = 2 };

    pub const MethodInfo = struct {
        name: []const u8,
        arity: u8,
        is_static: bool = false,
        visibility: Visibility = .public,
    };

    pub const PropertyDef = struct {
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
        self.used_traits.deinit(allocator);
        self.case_order.deinit(allocator);
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

    fn deinit(self: *InterfaceDef, allocator: Allocator) void {
        self.methods.deinit(allocator);
    }
};

pub const VM = struct {
    frames: [2048]CallFrame = undefined,
    frame_count: usize = 0,
    stack: [2048]Value = undefined,
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
    trait_uses: std.StringHashMapUnmanaged([]const []const u8) = .{},
    trait_props: std.StringHashMapUnmanaged([]const ClassDef.PropertyDef) = .{},
    trait_static_props: std.StringHashMapUnmanaged([]const TraitStaticProp) = .{},
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
    autoload_depth: u8 = 0,
    magic_get_guard: std.ArrayListUnmanaged(struct { obj_ptr: usize, prop_name: []const u8 }) = .{},
    magic_call_guard: std.ArrayListUnmanaged(struct { obj_ptr: usize, method_name: []const u8 }) = .{},
    user_error_handler: ?Value = null,
    prev_error_handler: ?Value = null,
    ob_stack: std.ArrayListUnmanaged(usize) = .{},
    request_vars: std.StringHashMapUnmanaged(Value) = .{},
    exception_handlers: [1024]ExceptionHandler = undefined,
    handler_count: usize = 0,
    handler_floor: usize = 0,
    pending_exception: ?Value = null,
    exception_dispatched: bool = false,
    run_base_frame: usize = 0,
    allocator: Allocator,
    global_slot_names: []const []const u8 = &.{},
    global_vars_dirty: bool = false,
    method_cache_class: []const u8 = "",
    method_cache_method: []const u8 = "",
    method_cache_result: []const u8 = "",
    ic: ?*InlineCache = null,
    serve_mode: bool = false,
    serve_compile_cache: std.StringHashMapUnmanaged(*CompileResult) = .{},
    serve_cache_keys: std.ArrayListUnmanaged([]const u8) = .{},

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
        called_class: ?[]const u8 = null,
        entry_sp: usize = 0,
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
        try @import("../stdlib/registry.zig").register(&vm.native_fns, allocator);
        try initConstants(&vm.php_constants, allocator);
        try @import("../stdlib/exceptions.zig").register(vm, allocator);
        try @import("../stdlib/datetime.zig").register(vm, allocator);
        try @import("../stdlib/spl.zig").register(vm, allocator);
        try @import("../stdlib/spl_iterators.zig").register(vm, allocator);
        try @import("../stdlib/pdo.zig").register(vm, allocator);
        try @import("../stdlib/websocket.zig").register(vm, allocator);
        try @import("../stdlib/filesystem.zig").register(vm, allocator);
        try @import("../stdlib/reflection.zig").register(vm, allocator);
        vm.ic = try allocator.create(InlineCache);
        vm.ic.?.* = .{};
        const locals_buf = try allocator.alloc(Value, 8192);
        vm.ic.?.locals_buf = locals_buf.ptr;
        vm.ic.?.locals_cap = 8192;
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
        try c.put(a, "PHP_VERSION", .{ .string = "8.4.0" });
        try c.put(a, "PHP_VERSION_ID", .{ .int = 80400 });
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
        try c.put(a, "PREG_PATTERN_ORDER", .{ .int = 1 });
        try c.put(a, "PREG_SET_ORDER", .{ .int = 2 });
        try c.put(a, "PREG_OFFSET_CAPTURE", .{ .int = 256 });
        try c.put(a, "PREG_SPLIT_DELIM_CAPTURE", .{ .int = 2 });
        try c.put(a, "PREG_SPLIT_NO_EMPTY", .{ .int = 1 });
        try c.put(a, "PREG_SPLIT_OFFSET_CAPTURE", .{ .int = 4 });
        try c.put(a, "PREG_NO_ERROR", .{ .int = 0 });
        try c.put(a, "PREG_INTERNAL_ERROR", .{ .int = 1 });
        try c.put(a, "PREG_BACKTRACK_LIMIT_ERROR", .{ .int = 2 });
        try c.put(a, "PREG_RECURSION_LIMIT_ERROR", .{ .int = 3 });
        try c.put(a, "PREG_BAD_UTF8_ERROR", .{ .int = 4 });
        try c.put(a, "PREG_BAD_UTF8_OFFSET_ERROR", .{ .int = 5 });
        try c.put(a, "PREG_JIT_STACKLIMIT_ERROR", .{ .int = 6 });
        try c.put(a, "LOCK_SH", .{ .int = 1 });
        try c.put(a, "LOCK_EX", .{ .int = 2 });
        try c.put(a, "LOCK_UN", .{ .int = 8 });
        try c.put(a, "LOCK_NB", .{ .int = 4 });
        try c.put(a, "FILE_APPEND", .{ .int = 8 });
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
        try c.put(a, "FILTER_SANITIZE_EMAIL", .{ .int = 517 });
        try c.put(a, "FILTER_SANITIZE_URL", .{ .int = 518 });
        try c.put(a, "FILTER_SANITIZE_NUMBER_INT", .{ .int = 519 });
        try c.put(a, "FILTER_SANITIZE_NUMBER_FLOAT", .{ .int = 520 });
        try c.put(a, "FILTER_SANITIZE_ENCODED", .{ .int = 514 });
        try c.put(a, "FILTER_FLAG_IPV4", .{ .int = 1048576 });
        try c.put(a, "FILTER_FLAG_IPV6", .{ .int = 2097152 });
        try c.put(a, "FILTER_FLAG_NO_ENCODE_QUOTES", .{ .int = 128 });
        try c.put(a, "FILTER_FLAG_STRIP_LOW", .{ .int = 4 });
        try c.put(a, "FILTER_FLAG_STRIP_HIGH", .{ .int = 8 });
        try c.put(a, "FILTER_DEFAULT", .{ .int = 516 });
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
        var tu_iter = self.trait_uses.valueIterator();
        while (tu_iter.next()) |subs| self.allocator.free(subs.*);
        self.trait_uses.deinit(self.allocator);
        var tp_iter = self.trait_props.valueIterator();
        while (tp_iter.next()) |props| self.allocator.free(props.*);
        self.trait_props.deinit(self.allocator);
        var tsp_iter = self.trait_static_props.valueIterator();
        while (tsp_iter.next()) |props| self.allocator.free(props.*);
        self.trait_static_props.deinit(self.allocator);
        self.statics.deinit(self.allocator);
        self.static_vars.deinit(self.allocator);
        self.global_vars.deinit(self.allocator);
        self.loaded_files.deinit(self.allocator);
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
        for (self.serve_cache_keys.items) |k| self.allocator.free(k);
        self.serve_cache_keys.deinit(self.allocator);
        self.serve_compile_cache.deinit(self.allocator);
    }

    pub fn reset(self: *VM) void {
        self.releaseFrames();
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
        self.statics.clearRetainingCapacity();
        self.static_vars.clearRetainingCapacity();
        self.global_vars.clearRetainingCapacity();
        self.loaded_files.clearRetainingCapacity();
        if (self.serve_mode) {
            self.functions.clearRetainingCapacity();
            self.php_constants.clearRetainingCapacity();
            initConstants(&self.php_constants, self.allocator) catch {};
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
        if (self.functions.contains(func.name)) return;
        try self.functions.put(self.allocator, func.name, func);
    }

    fn runUntilFrame(self: *VM, base_frame: usize) RuntimeError!void {
        if (self.frame_count <= base_frame) return;
        self.runLoop(base_frame) catch {
            if (self.pending_exception != null) {
                if (self.dispatchPendingException(self.run_base_frame)) {
                    self.exception_dispatched = true;
                    return;
                }
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
                    if (self.currentFrame().ref_slots.get(name)) |cell| {
                        self.push(cell.*);
                    } else if (self.currentFrame().vars.get(name)) |val| {
                        self.push(val);
                    } else if (self.php_constants.get(name)) |val| {
                        self.push(val);
                    } else if (name.len > 2 and name[0] == '$' and name[1] == '_') {
                        self.push(self.request_vars.get(name) orelse .null);
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
                        self.push(Value.add(a, b));
                    }
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
                        for (arr.entries.items) |entry| self.push(entry.value);
                        const ac: u8 = @intCast(arr.entries.items.len);
                        try self.callNamedFunction(name_val.string, ac);
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
                    } else {
                        var buf2: [256]u8 = undefined;
                        const msg = std.fmt.bufPrint(&buf2, "Value of type {s} is not callable", .{valueTypeName(name_val)}) catch "Value is not callable";
                        if (try self.throwBuiltinException("TypeError", msg)) continue;
                        return error.RuntimeError;
                    }
                },
                .return_val => {
                    const result = self.pop();
                    if (g_type_info.count() > 0) {
                        if (try self.checkReturnType(result)) continue;
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
                        self.push(arr_val.array.get(Value.toArrayKey(key)));
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
                .array_set => {
                    const val = self.pop();
                    const key = self.pop();
                    const arr_val = self.pop();
                    if (arr_val == .array) {
                        try arr_val.array.set(self.allocator, Value.toArrayKey(key), val);
                    } else if (arr_val == .object and self.hasMethod(arr_val.object.class_name, "offsetSet")) {
                        _ = self.callMethod(arr_val.object, "offsetSet", &.{ key, val }) catch {
                            if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                            return error.RuntimeError;
                        };
                    }
                    self.push(val);
                },

                .iter_begin => {
                    var iterable = self.stack[self.sp - 1];
                    if (iterable == .generator) {
                        self.resumeGenerator(iterable.generator, .null) catch {
                            if (self.dispatchPendingException(base_frame)) continue;
                            return error.RuntimeError;
                        };
                        self.push(.{ .int = -1 }); // sentinel: -1 means generator iteration
                    } else if (iterable == .object) {
                        // IteratorAggregate: replace iterable with getIterator() result
                        if (self.hasMethod(iterable.object.class_name, "getIterator")) {
                            const inner = self.callMethod(iterable.object, "getIterator", &.{}) catch .null;
                            self.stack[self.sp - 1] = inner;
                            iterable = inner;
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
                            if (obj.slots) |slots| {
                                if (obj.slot_layout) |layout| {
                                    for (layout.names, 0..) |name, i| {
                                        if (i < slots.len) {
                                            try arr.set(self.allocator, .{ .string = name }, slots[i]);
                                        }
                                    }
                                }
                            }
                            var it = obj.properties.iterator();
                            while (it.next()) |entry| {
                                try arr.set(self.allocator, .{ .string = entry.key_ptr.* }, entry.value_ptr.*);
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
                        const valid = self.callMethod(iterable.object, "valid", &.{}) catch Value{ .bool = false };
                        if (!valid.isTruthy()) {
                            self.currentFrame().ip += offset;
                        } else {
                            const key = self.callMethod(iterable.object, "key", &.{}) catch .null;
                            const current = self.callMethod(iterable.object, "current", &.{}) catch .null;
                            self.push(key);
                            self.push(current);
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
                        try self.setLocalGlobal(slot, val, frame);
                    }
                },
                .inc_local => {
                    const slot = self.readU16();
                    const frame_il = self.currentFrame();
                    if (slot < frame_il.locals.len) {
                        const v = frame_il.locals[slot];
                        frame_il.locals[slot] = if (v == .int) Value.intInc(v.int) else if (v == .float) .{ .float = v.float + 1.0 } else Value.add(v, .{ .int = 1 });
                    }
                },
                .dec_local => {
                    const slot = self.readU16();
                    const frame_dl = self.currentFrame();
                    if (slot < frame_dl.locals.len) {
                        const v = frame_dl.locals[slot];
                        frame_dl.locals[slot] = if (v == .int) Value.intDec(v.int) else if (v == .float) .{ .float = v.float - 1.0 } else Value.subtract(v, .{ .int = 1 });
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
                    if (arr_val == .object and self.hasMethod(arr_val.object.class_name, "offsetExists")) {
                        const result = self.callMethod(arr_val.object, "offsetExists", &.{key}) catch {
                            if (self.pending_exception != null and self.dispatchPendingException(base_frame)) continue;
                            return error.RuntimeError;
                        };
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

                .get_obj_class => {
                    const v = self.pop();
                    if (v == .object) {
                        self.push(.{ .string = v.object.class_name });
                    } else {
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Cannot use \"::class\" on non-object", .{}) catch null;
                        return error.RuntimeError;
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
                    } else if (v == .object) {
                        const obj = v.object;
                        const arr = try self.allocator.create(PhpArray);
                        arr.* = .{};
                        try self.arrays.append(self.allocator, arr);
                        if (obj.slots) |slots| {
                            if (obj.slot_layout) |layout| {
                                for (layout.names, 0..) |name, i| {
                                    if (i < slots.len) {
                                        try arr.set(self.allocator, .{ .string = name }, slots[i]);
                                    }
                                }
                            }
                        }
                        var it = obj.properties.iterator();
                        while (it.next()) |entry| {
                            try arr.set(self.allocator, .{ .string = entry.key_ptr.* }, entry.value_ptr.*);
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
                            const from_cache = self.serve_mode and self.serve_compile_cache.contains(path);
                            const result: ?*CompileResult = if (from_cache)
                                self.serve_compile_cache.get(path).?
                            else if (self.file_loader) |loader|
                                loader(path, self.allocator)
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
                                self.frames[self.frame_count] = .{
                                    .chunk = &r.chunk,
                                    .ip = 0,
                                    .vars = inherited_vars,
                                    .locals = req_locals,
                                };
                                self.frames[self.frame_count].entry_sp = self.sp;
                                self.frame_count += 1;
                                self.runUntilFrame(return_frame) catch {
                                    while (self.frame_count > return_frame) {
                                        self.frame_count -= 1;
                                        self.frames[self.frame_count].vars.deinit(self.allocator);
                                        if (self.frames[self.frame_count].locals.len > 0) {
                                            self.freeLocals(self.frames[self.frame_count].locals);
                                            self.frames[self.frame_count].locals = &.{};
                                        }
                                    }
                                    self.global_slot_names = saved_slot_names;

                                    if (self.pending_exception) |exc| {
                                        if (self.handler_count > self.handler_floor) {
                                            const handler = self.exception_handlers[self.handler_count - 1];
                                            if (handler.frame_count > base_frame or base_frame == 0) {
                                                self.pending_exception = null;
                                                self.handler_count -= 1;
                                                while (self.frame_count > handler.frame_count) {
                                                    self.frame_count -= 1;
                                                    self.frames[self.frame_count].vars.deinit(self.allocator);
                                                    if (self.frames[self.frame_count].locals.len > 0) {
                                                        self.freeLocals(self.frames[self.frame_count].locals);
                                                        self.frames[self.frame_count].locals = &.{};
                                                    }
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
                                            self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: require(): Failed opening required '{s}'", .{path}) catch null;
                                        }
                                        return error.RuntimeError;
                                    }
                                    self.push(.{ .bool = false });
                                    continue;
                                };
                                while (self.frame_count > return_frame) {
                                    self.frame_count -= 1;
                                    self.frames[self.frame_count].vars.deinit(self.allocator);
                                    if (self.frames[self.frame_count].locals.len > 0) {
                                        self.freeLocals(self.frames[self.frame_count].locals);
                                        self.frames[self.frame_count].locals = &.{};
                                    }
                                }
                                self.global_slot_names = saved_slot_names;
                                if (self.sp <= sp_before) self.push(.{ .bool = true });
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
                        }
                        self.sp -= const_count;
                    } else {
                        // read const names even when 0 (shouldn't have any)
                    }
                    for (0..parent_count) |pi| {
                        try def.interfaces.append(self.allocator, parent_names[pi]);
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
                            for (entries) |entry| self.push(entry.value);
                            arg_count = @intCast(entries.len);
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

                            const saved_fc = self.frame_count;
                            var ctx = self.makeContext(null);
                            _ = native(&ctx, args_buf[0..ac]) catch {
                                // clean up temp frame if throwBuiltinException didn't already unwind past it
                                if (self.frame_count >= saved_fc) {
                                    self.frame_count -= 1;
                                    self.frames[self.frame_count].vars.deinit(self.allocator);
                                }
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
                                if (func.is_variadic) {
                                    const fixed: usize = func.arity - 1;
                                    for (0..@min(ac, fixed)) |i| {
                                        ctor_locals[i + 1] = self.stack[self.sp - ac + i];
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
                    const class_name = if (name_val == .string) name_val.string else if (name_val == .object) name_val.object.class_name else {
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Class name must be a valid object or a string", .{}) catch null;
                        return error.RuntimeError;
                    };
                    if (!self.classes.contains(class_name)) try self.tryAutoload(class_name);

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
                            var ctx = self.makeContext(null);
                            _ = native(&ctx, args_buf[0..ac]) catch {
                                self.frame_count -= 1;
                                self.frames[self.frame_count].vars.deinit(self.allocator);
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
                                        continue;
                                    }
                                    self.pending_exception = exc;
                                } else {
                                    continue;
                                }
                                return error.RuntimeError;
                            };
                            self.frame_count -= 1;
                            self.frames[self.frame_count].vars.deinit(self.allocator);
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

                        // IC: slot-indexed fast path
                        if (self.ic) |ic| {
                            const gp_idx = InlineCache.propIndex(@intFromPtr(self.currentChunk()), gp_ip);
                            const gp_entry = &ic.prop[gp_idx];
                            const gp_chunk_key = @intFromPtr(self.currentChunk());
                            if (gp_entry.key == gp_ip and gp_entry.chunk_key == gp_chunk_key and gp_entry.class_ptr == @intFromPtr(obj.class_name.ptr)) {
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
                        if (!has_prop and self.hasMethod(obj.class_name, "__set")) {
                            _ = self.callMethod(obj, "__set", &.{ .{ .string = prop_name }, new_val }) catch {};
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

                    if (obj_val == .string and std.mem.startsWith(u8, obj_val.string, "__closure_")) {
                        const closure_name = obj_val.string;
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
                            self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught Error: Call to undefined method Closure::{s}()", .{method_name}) catch null;
                            return error.RuntimeError;
                        }
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
                                        if (i < func.defaults.len) mc_locals[i + 1] = try self.resolveDefault(func.defaults[i]);
                                    }
                                    self.saveFrameArgs(arg_count);
                                    self.sp -= ac + 1;
                                    self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = .{}, .locals = mc_locals, .func = func };
                                    self.setFrameArgCount(arg_count);
                                    self.frames[self.frame_count].entry_sp = self.sp;
                    self.frame_count += 1;
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
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught Error: {s}", .{msg}) catch null;
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
                        const saved_fc = self.frame_count;

                        var ctx = self.makeContext(null);
                        const result = native(&ctx, args_buf[0..ac]) catch {
                            if (self.frame_count >= saved_fc) {
                                self.frame_count -= 1;
                                self.frames[self.frame_count].vars.deinit(self.allocator);
                            }
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
                        self.saveFrameArgs(arg_count);
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
                            self.setFrameArgCount(arg_count);
                            self.frames[self.frame_count].entry_sp = self.sp;
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
                        const saved_fc = self.frame_count;
                        var ctx = self.makeContext(null);
                        const result = native(&ctx, args_buf[0..ac]) catch {
                            if (self.frame_count >= saved_fc) {
                                self.frame_count -= 1;
                                self.frames[self.frame_count].vars.deinit(self.allocator);
                            }
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
                    } else {
                        self.sp -= ac + 1;
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught Error: Call to undefined method {s}::{s}()", .{ obj.class_name, method_name }) catch null;
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
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught Error: Call to a member function {s}() on {s}", .{ method_name, valueTypeName(obj_val) }) catch null;
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
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught Error: Call to undefined method {s}::{s}()", .{ obj.class_name, method_name }) catch null;
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
                        const saved_fc = self.frame_count;
                        var ctx = self.makeContext(null);
                        const result = native(&ctx, args_buf[0..ac]) catch {
                            if (self.frame_count >= saved_fc) {
                                self.frame_count -= 1;
                                self.frames[self.frame_count].vars.deinit(self.allocator);
                            }
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
                            self.frames[self.frame_count].vars.deinit(self.allocator);
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
                            const rest_arr = try self.allocator.create(PhpArray);
                            rest_arr.* = .{};
                            try self.arrays.append(self.allocator, rest_arr);
                            for (fixed..ac) |ai| try rest_arr.append(self.allocator, self.stack[self.sp - ac + ai]);
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
                    } else {
                        self.sp -= ac + 1;
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught Error: Call to undefined method {s}::{s}()", .{ obj.class_name, method_name }) catch null;
                        return error.RuntimeError;
                    }
                },

                .method_call_dynamic_spread => {
                    // stack: [object, method_name, args_array]
                    const args_val = self.pop();
                    const method_name_val = self.pop();
                    const obj_val = self.pop();
                    if (args_val != .array) {
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught TypeError: Argument unpacking requires an array", .{}) catch null;
                        return error.RuntimeError;
                    }
                    if (method_name_val != .string) {
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught TypeError: Method name must be a string", .{}) catch null;
                        return error.RuntimeError;
                    }
                    if (obj_val != .object) {
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught Error: Call to a member function {s}() on {s}", .{ method_name_val.string, valueTypeName(obj_val) }) catch null;
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
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught Error: Call to undefined method {s}::{s}()", .{ obj.class_name, method_name }) catch null;
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
                        const saved_fc = self.frame_count;
                        var ctx = self.makeContext(null);
                        const result = native(&ctx, args_buf[0..ac]) catch {
                            if (self.frame_count >= saved_fc) {
                                self.frame_count -= 1;
                                self.frames[self.frame_count].vars.deinit(self.allocator);
                            }
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
                            self.frames[self.frame_count].vars.deinit(self.allocator);
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
                            const rest_arr = try self.allocator.create(PhpArray);
                            rest_arr.* = .{};
                            try self.arrays.append(self.allocator, rest_arr);
                            for (fixed..ac) |ai| try rest_arr.append(self.allocator, self.stack[self.sp - ac + ai]);
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
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught Error: {s}", .{msg}) catch null;
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
                                for (0..@min(ac, func.arity)) |i| {
                                    try new_vars.put(self.allocator, func.params[i], self.stack[self.sp - ac + i]);
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
                                var ctx = self.makeContext(null);
                                const result = native(&ctx, args_buf[0..ac]) catch {
                                    if (self.frame_count > sc_saved_fc) {
                                        self.frame_count -= 1;
                                        self.frames[self.frame_count].vars.deinit(self.allocator);
                                    }
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
                                            continue;
                                        }
                                        self.pending_exception = exc;
                                    } else {
                                        continue;
                                    }
                                    return error.RuntimeError;
                                };
                                self.frame_count -= 1;
                                self.frames[self.frame_count].vars.deinit(self.allocator);
                                self.push(result);
                            } else {
                                const msg = std.fmt.allocPrint(self.allocator, "Call to undefined method {s}::{s}()", .{ class_name, method_name }) catch "Call to undefined method";
                                try self.strings.append(self.allocator, msg);
                                if (try self.throwBuiltinException("Error", msg)) continue;
                                self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught Error: {s}", .{msg}) catch null;
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
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught TypeError: Argument unpacking requires an array", .{}) catch null;
                        return error.RuntimeError;
                    }
                    const arr = args_val.array;
                    const ac = arr.entries.items.len;

                    const this_val = self.currentFrame().vars.get("$this");
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
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught Error: Call to undefined method {s}::{s}()", .{ class_name, method_name }) catch null;
                        return error.RuntimeError;
                    };
                    for (arr.entries.items) |entry| self.push(entry.value);

                    if (this_val) |tv| {
                        if (tv == .object) {
                            if (self.functions.get(full_name)) |func| {
                                if (func.is_generator) {
                                    try self.callStaticFunction(full_name, @intCast(ac), effective_called);
                                } else {
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
                                        if (i < func.defaults.len) try new_vars.put(self.allocator, func.params[i], try self.resolveDefault(func.defaults[i]));
                                    }
                                }
                                const scs_ac: u8 = @intCast(@min(ac, 255));
                                self.saveFrameArgs(scs_ac);
                                self.sp -= ac;
                                self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars, .locals = try self.allocLocals(func, &new_vars), .func = func, .called_class = effective_called };
                                self.setFrameArgCount(scs_ac);
                                self.frames[self.frame_count].entry_sp = self.sp;
                    self.frame_count += 1;
                                }
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

                .static_call_dynamic => {
                    const method_idx = self.readU16();
                    const arg_count = self.readByte();
                    const method_name = self.currentChunk().constants.items[method_idx].string;
                    const ac: usize = arg_count;
                    const class_val = self.stack[self.sp - ac - 1];
                    const class_name = if (class_val == .string)
                        class_val.string
                    else if (class_val == .object)
                        class_val.object.class_name
                    else {
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught TypeError: {s}::method() requires a class name string", .{method_name}) catch null;
                        return error.RuntimeError;
                    };
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
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught Error: {s}", .{msg}) catch null;
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
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: dynamic method name must be a string", .{}) catch null;
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
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught Error: {s}", .{msg}) catch null;
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
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: dynamic method name must be a string", .{}) catch null;
                        return error.RuntimeError;
                    };
                    var class_name = if (class_val == .string) class_val.string else if (class_val == .object) class_val.object.class_name else {
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: dynamic class name must be a string", .{}) catch null;
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
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught Error: {s}", .{msg}) catch null;
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
                        self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught Error: {s}", .{msg}) catch null;
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

                .get_static_prop_dynamic => {
                    const prop_idx = self.readU16();
                    const prop_name = self.currentChunk().constants.items[prop_idx].string;
                    const class_val = self.pop();
                    const class_name = if (class_val == .string) class_val.string else "";

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
            if (local_val == .string) return local_val.string;
            if (self.currentFrame().vars.get(name)) |val| {
                if (val == .string) return val.string;
            }
            return name;
        }
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

    pub fn throwBuiltinException(self: *VM, class_name: []const u8, message: []const u8) !bool {
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
            self.frames[self.frame_count].vars.deinit(self.allocator);
        }

        self.sp = handler.sp;
        self.push(.{ .object = obj });
        self.currentFrame().ip = handler.catch_ip;
        return true;
    }

    fn dispatchPendingException(self: *VM, base_frame: usize) bool {
        const exc = self.pending_exception orelse return false;
        if (self.handler_count <= self.handler_floor) return false;
        const handler = self.exception_handlers[self.handler_count - 1];
        if (handler.frame_count <= base_frame and base_frame > 0) return false;
        self.pending_exception = null;
        self.handler_count -= 1;
        while (self.frame_count > handler.frame_count) {
            self.frame_count -= 1;
            self.frames[self.frame_count].vars.deinit(self.allocator);
            if (self.frames[self.frame_count].locals.len > 0) {
                self.freeLocals(self.frames[self.frame_count].locals);
                self.frames[self.frame_count].locals = &.{};
            }
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
                    }
                }
                try frame.vars.put(self.allocator, name, val);
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
        const name_idx = self.readU16();
        const class_name = self.currentChunk().constants.items[name_idx].string;
        const method_count = self.readU16();

        var def = ClassDef{ .name = class_name };

        for (0..method_count) |_| {
            const mi = self.readMethodInfo();
            try def.methods.put(self.allocator, mi[0], mi[1]);
        }

        const prop_count = self.readU16();
        var prop_names: [256][]const u8 = undefined;
        var prop_has_default: [256]u8 = undefined;
        var prop_vis: [256]ClassDef.Visibility = undefined;
        var prop_readonly: [256]bool = .{false} ** 256;
        for (0..prop_count) |pi| {
            const pname_idx = self.readU16();
            prop_names[pi] = self.currentChunk().constants.items[pname_idx].string;
            prop_has_default[pi] = self.readByte();
            const vis_byte = self.readByte();
            prop_vis[pi] = @enumFromInt(vis_byte & 0x03);
            prop_readonly[pi] = (vis_byte & 0x04) != 0;
        }

        const static_prop_count = self.readU16();
        var sprop_names: [256][]const u8 = undefined;
        var sprop_has_default: [256]u8 = undefined;
        for (0..static_prop_count) |pi| {
            const pname_idx = self.readU16();
            sprop_names[pi] = self.currentChunk().constants.items[pname_idx].string;
            sprop_has_default[pi] = self.readByte();
            _ = self.readByte();
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
                alias_rules[alias_count] = .{ .method = method_name, .trait = rule_trait, .alias = self.currentChunk().constants.items[self.readU16()].string };
                alias_count += 1;
            }
        }

        for (trait_names[0..trait_count]) |trait_name| {
            try self.applyTrait(&def, class_name, trait_name, alias_rules[0..alias_count], insteadof_rules[0..insteadof_count]);
            try def.used_traits.append(self.allocator, trait_name);
        }

        if (def.parent) |parent_name| {
            if (!self.classes.contains(parent_name)) try self.tryAutoload(parent_name);
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

        const method_count = self.readU16();
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

    pub fn cloneClosureWithThis(self: *VM, closure_name: []const u8, new_this: Value, scope_action: ClosureScope) !Value {
        const func = self.functions.get(closure_name) orelse return .null;

        const id = self.closure_instance_count;
        self.closure_instance_count += 1;
        const new_name = try std.fmt.allocPrint(self.allocator, "__closure_bound_{d}", .{id});
        try self.strings.append(self.allocator, new_name);
        try self.functions.put(self.allocator, new_name, func);

        if (self.capture_index.get(closure_name)) |cr| {
            // copy source captures to a stack buffer to avoid dangling slice
            // when self.captures reallocates during append
            var src_buf: [32]CaptureEntry = undefined;
            const src_len = cr.len;
            for (0..src_len) |i| src_buf[i] = self.captures.items[cr.start + i];
            const src = src_buf[0..src_len];

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

        self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = .{}, .locals = locals, .func = func, .called_class = self.closureScopeByName(name) orelse self.currentFrame().called_class };
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
            if (i < func.defaults.len) locals[i] = try self.resolveDefault(func.defaults[i]);
        }
        self.saveFrameArgs(arg_count);
        self.sp -= ac;
        self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = .{}, .locals = locals, .func = func, .called_class = self.currentFrame().called_class };
        self.setFrameArgCount(arg_count);
        self.frame_count += 1;
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
        self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = .{}, .locals = locals, .func = func };
        self.consumePendingArgCount();
        self.frame_count += 1;
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
        // prune exception handlers that belonged to the popped frame
        while (self.handler_count > self.handler_floor and
            self.exception_handlers[self.handler_count - 1].frame_count > self.frame_count)
        {
            self.handler_count -= 1;
        }
        self.frames[self.frame_count].ref_slots.deinit(self.allocator);
        self.frames[self.frame_count].vars.deinit(self.allocator);
        if (self.frames[self.frame_count].locals.len > 0) {
            self.freeLocals(self.frames[self.frame_count].locals);
            self.frames[self.frame_count].locals = &.{};
        }
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

    pub fn isInstanceOf(self: *VM, obj_class: []const u8, target_class: []const u8) bool {
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

    pub const VisResult = struct { visibility: ClassDef.Visibility, defining_class: []const u8, is_readonly: bool = false };

    pub fn findPropertyVisibility(self: *VM, class_name: []const u8, prop_name: []const u8) VisResult {
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
            } else {
                if (!self.classes.contains(name)) {
                    self.tryAutoload(name) catch {};
                }
                if (self.interfaces.get(name)) |idef| {
                    current = idef.parent;
                } else {
                    // also check the ClassDef's interfaces list as fallback
                    if (self.classes.get(name)) |cls| {
                        for (cls.interfaces.items) |parent_iface| {
                            if (self.implementsInterface(parent_iface, target)) return true;
                        }
                    }
                    break;
                }
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

    fn closureScopeByName(self: *VM, name: []const u8) ?[]const u8 {
        if (self.capture_index.get(name)) |cr| {
            const caps = self.captures.items[cr.start .. cr.start + cr.len];
            for (caps) |cap| {
                if (std.mem.eql(u8, cap.var_name, "$__closure_scope") and cap.value == .string)
                    return cap.value.string;
            }
        }
        return null;
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

    fn currentDefiningClass(self: *VM) ?[]const u8 {
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
            }
        }
        return result;
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
                    if (self.getStaticProp(class_name, const_name)) |v| return v;
                    // fall back to class constants (ClassName::CONST_NAME)
                    var buf: [512]u8 = undefined;
                    const full = std.fmt.bufPrint(&buf, "{s}::{s}", .{ class_name, const_name }) catch return .null;
                    if (self.php_constants.get(full)) |v| return v;
                    return .null;
                }
            }
        }
        return val;
    }

    fn fillDefaults(self: *VM, vars: *std.StringHashMapUnmanaged(Value), func: *const ObjFunction, arg_count: usize) !void {
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
        self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = vars, .locals = try self.allocLocals(func, &vars), .func = func };
        self.consumePendingArgCount();
        self.frame_count += 1;
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
        self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = vars, .locals = try self.allocLocals(func, &vars), .func = func, .ref_slots = ref_slots };
        self.consumePendingArgCount();
        self.frame_count += 1;
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
        if (std.mem.eql(u8, type_name, "bool") or std.mem.eql(u8, type_name, "boolean")) return val == .bool or val == .int;
        if (std.mem.eql(u8, type_name, "string")) return val == .string;
        if (std.mem.eql(u8, type_name, "array")) return val == .array;
        if (std.mem.eql(u8, type_name, "callable")) return val == .string or val == .array or val == .object;
        if (std.mem.eql(u8, type_name, "null")) return val == .null;
        if (std.mem.eql(u8, type_name, "false")) return val == .bool and !val.bool;
        if (std.mem.eql(u8, type_name, "true")) return val == .bool and val.bool;
        if (std.mem.eql(u8, type_name, "object")) return val == .object;
        if (std.mem.eql(u8, type_name, "iterable")) return val == .array or val == .generator;
        if (std.mem.eql(u8, type_name, "self") or std.mem.eql(u8, type_name, "static") or std.mem.eql(u8, type_name, "parent")) return val == .object;
        if (std.mem.eql(u8, type_name, "Traversable") or std.mem.eql(u8, type_name, "Iterator") or std.mem.eql(u8, type_name, "IteratorAggregate")) {
            return val == .object or val == .array or val == .generator;
        }
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

    fn callNamedFunction(self: *VM, name: []const u8, arg_count: u8) RuntimeError!void {
        if (self.native_fns.get(name)) |native| {
            var args: [64]Value = undefined;
            const ac: usize = arg_count;
            for (0..ac) |i| args[i] = self.stack[self.sp - ac + i];
            self.sp -= ac;
            var ctx = self.makeContext(name);
            const result = native(&ctx, args[0..ac]) catch {
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
                    self.pending_exception = exc;
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
                self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught ArgumentCountError: {s}\n", .{msg}) catch null;
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
            self.saveFrameArgs(arg_count);
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
                const inherit_cc = if (std.mem.startsWith(u8, name, "__closure_"))
                    self.closureScopeByName(name) orelse self.currentFrame().called_class
                else
                    null;
                self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars, .locals = try self.allocLocals(func, &new_vars), .func = func, .ref_slots = callee_refs, .called_class = inherit_cc };
                self.setFrameArgCount(arg_count);
                self.frame_count += 1;
            }
        } else {
            if (std.mem.lastIndexOfScalar(u8, name, '\\')) |pos| {
                const base = name[pos + 1 ..];
                if (base.len > 0) return self.callNamedFunction(base, arg_count);
            }
            const msg = std.fmt.allocPrint(self.allocator, "Call to undefined function {s}()", .{name}) catch "Call to undefined function";
            try self.strings.append(self.allocator, msg);
            if (try self.throwBuiltinException("Error", msg)) return;
            self.error_msg = std.fmt.allocPrint(self.allocator, "Fatal error: Uncaught Error: {s}\n", .{msg}) catch null;
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
        self.consumePendingArgCount();
        self.frame_count += 1;
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

    fn saveFrameArgs(self: *VM, arg_count: u8) void {
        const ic = self.ic orelse return;
        if (self.frame_count >= 2048) return;
        const ac: usize = arg_count;
        if (ac == 0) {
            ic.fga_offsets[self.frame_count] = ic.fga_sp;
            return;
        }
        const sp = ic.fga_sp;
        if (sp + ac > 256) return;
        ic.fga_offsets[self.frame_count] = sp;
        for (0..ac) |i| {
            ic.fga_buf[sp + i] = self.stack[self.sp - ac + i];
        }
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
        if (offset + ac > 256) return null;
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

