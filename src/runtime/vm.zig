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
const RuntimeError = error{ RuntimeError, OutOfMemory };

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
            } else {
                break;
            }
        }
        if (arg_vars[arg_index]) |var_name| {
            caller.vars.put(vm.allocator, var_name, value) catch return;
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
};

const NativeFn = *const fn (*NativeContext, []const Value) RuntimeError!Value;

const CaptureEntry = struct {
    closure_name: []const u8,
    var_name: []const u8,
    value: Value,
    ref_cell: ?*Value = null,
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
    autoload_callbacks: std.ArrayListUnmanaged(Value) = .{},
    ob_stack: std.ArrayListUnmanaged(usize) = .{},
    request_vars: std.StringHashMapUnmanaged(Value) = .{},
    exception_handlers: [32]ExceptionHandler = undefined,
    handler_count: usize = 0,
    handler_floor: usize = 0,
    pending_exception: ?Value = null,
    allocator: Allocator,

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
        generator: ?*Generator = null,
        ref_slots: std.StringHashMapUnmanaged(*Value) = .{},
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
        try c.put(a, "LOCK_SH", .{ .int = 1 });
        try c.put(a, "LOCK_EX", .{ .int = 2 });
        try c.put(a, "LOCK_UN", .{ .int = 8 });
        try c.put(a, "LOCK_NB", .{ .int = 4 });
    }

    pub fn deinit(self: *VM) void {
        for (0..self.frame_count) |i| {
            self.frames[i].ref_slots.deinit(self.allocator);
            self.frames[i].vars.deinit(self.allocator);
        }
        self.functions.deinit(self.allocator);
        self.native_fns.deinit(self.allocator);
        self.output.deinit(self.allocator);
        for (self.strings.items) |s| self.allocator.free(s);
        self.strings.deinit(self.allocator);
        self.captures.deinit(self.allocator);
        self.php_constants.deinit(self.allocator);
        for (self.arrays.items) |a| {
            a.deinit(self.allocator);
            self.allocator.destroy(a);
        }
        self.arrays.deinit(self.allocator);
        @import("../stdlib/pdo.zig").cleanupResources(self.objects);
        @import("../stdlib/filesystem.zig").cleanupHandles(self.objects);
        for (self.objects.items) |o| {
            o.deinit(self.allocator);
            self.allocator.destroy(o);
        }
        self.objects.deinit(self.allocator);
        for (self.generators.items) |g| {
            g.deinit(self.allocator);
            self.allocator.destroy(g);
        }
        self.generators.deinit(self.allocator);
        for (self.fibers.items) |f| {
            f.deinit(self.allocator);
            self.allocator.destroy(f);
        }
        self.fibers.deinit(self.allocator);
        for (self.ref_cells.items) |c| self.allocator.destroy(c);
        self.ref_cells.deinit(self.allocator);
        var class_iter = self.classes.valueIterator();
        while (class_iter.next()) |c| c.deinit(self.allocator);
        self.classes.deinit(self.allocator);
        var iface_iter = self.interfaces.valueIterator();
        while (iface_iter.next()) |i| i.deinit(self.allocator);
        self.interfaces.deinit(self.allocator);
        self.traits.deinit(self.allocator);
        // free statics keys (heap allocated)
        var statics_iter = self.statics.keyIterator();
        while (statics_iter.next()) |k| self.allocator.free(k.*);
        self.statics.deinit(self.allocator);
        self.static_vars.deinit(self.allocator);
        self.global_vars.deinit(self.allocator);
        self.loaded_files.deinit(self.allocator);
        for (self.compile_results.items) |r| {
            var result = r;
            result.deinit();
            self.allocator.destroy(result);
        }
        self.compile_results.deinit(self.allocator);
        self.ob_stack.deinit(self.allocator);
        self.request_vars.deinit(self.allocator);
        self.autoload_callbacks.deinit(self.allocator);
    }

    pub fn reset(self: *VM) void {
        // clear per-request state, keep stdlib/builtins/constants/classes
        for (0..self.frame_count) |i| {
            self.frames[i].ref_slots.deinit(self.allocator);
            self.frames[i].vars.deinit(self.allocator);
        }
        self.frame_count = 0;
        self.sp = 0;
        self.handler_count = 0;
        self.output.clearRetainingCapacity();
        for (self.strings.items) |s| self.allocator.free(s);
        self.strings.clearRetainingCapacity();
        for (self.arrays.items) |a| {
            a.deinit(self.allocator);
            self.allocator.destroy(a);
        }
        self.arrays.clearRetainingCapacity();
        @import("../stdlib/pdo.zig").cleanupResources(self.objects);
        @import("../stdlib/filesystem.zig").cleanupHandles(self.objects);
        for (self.objects.items) |o| {
            o.deinit(self.allocator);
            self.allocator.destroy(o);
        }
        self.objects.clearRetainingCapacity();
        for (self.generators.items) |g| {
            g.deinit(self.allocator);
            self.allocator.destroy(g);
        }
        self.generators.clearRetainingCapacity();
        for (self.fibers.items) |f| {
            f.deinit(self.allocator);
            self.allocator.destroy(f);
        }
        self.fibers.clearRetainingCapacity();
        for (self.ref_cells.items) |c| self.allocator.destroy(c);
        self.ref_cells.clearRetainingCapacity();
        self.current_fiber = null;
        self.fiber_suspend_pending = false;
        self.fiber_suspend_value = .null;
        self.handler_floor = 0;
        self.captures.clearRetainingCapacity();
        self.ob_stack.clearRetainingCapacity();
        self.request_vars.clearRetainingCapacity();
        // clear user-defined static vars but keep the statics table
        var statics_iter = self.statics.keyIterator();
        while (statics_iter.next()) |k| self.allocator.free(k.*);
        self.statics.clearRetainingCapacity();
        self.static_vars.clearRetainingCapacity();
        self.global_vars.clearRetainingCapacity();
        self.loaded_files.clearRetainingCapacity();
        for (self.compile_results.items) |r| {
            var result = r;
            result.deinit();
            self.allocator.destroy(result);
        }
        self.compile_results.clearRetainingCapacity();
        self.error_msg = null;
    }

    pub fn interpret(self: *VM, result: *const CompileResult) RuntimeError!void {
        for (result.functions.items) |*func| {
            try self.registerFunction(func);
        }
        var vars: std.StringHashMapUnmanaged(Value) = .{};
        var it = self.request_vars.iterator();
        while (it.next()) |entry| {
            try vars.put(self.allocator, entry.key_ptr.*, entry.value_ptr.*);
        }
        self.frames[0] = .{ .chunk = &result.chunk, .ip = 0, .vars = vars };
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
                    } else {
                        self.push(self.currentFrame().vars.get(name) orelse
                            self.php_constants.get(name) orelse .null);
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
                },

                .add => self.binaryOp(Value.add),
                .subtract => self.binaryOp(Value.subtract),
                .multiply => self.binaryOp(Value.multiply),
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
                .power => self.binaryOp(Value.power),
                .negate => {
                    const v = self.pop();
                    self.push(v.negate());
                },
                .concat => {
                    const b = self.pop();
                    const a = self.pop();
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
                    try self.callNamedFunction(name, arg_count);
                },
                .call_indirect => {
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
                    } else if (name_val == .array) {
                        const arr = name_val.array;
                        if (arr.entries.items.len != 2) return error.RuntimeError;
                        const target = arr.entries.items[0].value;
                        const method_val = arr.entries.items[1].value;
                        if (method_val != .string) return error.RuntimeError;
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
                        } else return error.RuntimeError;
                        self.push(result);
                    } else return error.RuntimeError;
                },
                .call_spread => {
                    const name_idx = self.readU16();
                    const name = self.currentChunk().constants.items[name_idx].string;
                    const args_val = self.pop();
                    if (args_val != .array) return error.RuntimeError;
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
                    if (args_val != .array or name_val != .string) return error.RuntimeError;
                    const arr = args_val.array;
                    for (arr.entries.items) |entry| {
                        self.push(entry.value);
                    }
                    const ac: u8 = @intCast(arr.entries.items.len);
                    try self.callNamedFunction(name_val.string, ac);
                },
                .return_val => {
                    const result = self.pop();
                    try self.writebackStatics();
                    try self.writebackGlobals();
                    try self.writebackRefs();
                    self.frame_count -= 1;
                    self.frames[self.frame_count].ref_slots.deinit(self.allocator);
                    self.frames[self.frame_count].vars.deinit(self.allocator);
                    self.push(result);
                    if (self.frame_count <= base_frame) return;
                },
                .return_void => {
                    try self.writebackStatics();
                    try self.writebackGlobals();
                    try self.writebackRefs();
                    self.frame_count -= 1;
                    self.frames[self.frame_count].ref_slots.deinit(self.allocator);
                    self.frames[self.frame_count].vars.deinit(self.allocator);
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
                    if (arr_val == .array) try arr_val.array.append(self.allocator, val);
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

                .clone_obj => {
                    const val = self.pop();
                    if (val == .object) {
                        const src = val.object;
                        const copy = try self.allocator.create(PhpObject);
                        copy.* = .{ .class_name = src.class_name };
                        var it = src.properties.iterator();
                        while (it.next()) |entry| {
                            try copy.properties.put(self.allocator, entry.key_ptr.*, entry.value_ptr.*);
                        }
                        try self.objects.append(self.allocator, copy);
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
                    const var_idx = self.readU16();
                    const var_name = self.currentChunk().constants.items[var_idx].string;
                    const compile_name = self.peek().string;

                    // if stack still holds the compile-time name, create a unique runtime instance
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

                    const closure_name = self.peek().string;
                    const val = if (self.currentFrame().ref_slots.get(var_name)) |cell|
                        cell.*
                    else
                        self.currentFrame().vars.get(var_name) orelse .null;
                    try self.captures.append(self.allocator, .{
                        .closure_name = closure_name,
                        .var_name = var_name,
                        .value = val,
                    });
                },

                .closure_bind_ref => {
                    const var_idx = self.readU16();
                    const var_name = self.currentChunk().constants.items[var_idx].string;
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

                    const closure_name = self.peek().string;
                    // get or create a ref cell for this variable
                    const cell = if (self.currentFrame().ref_slots.get(var_name)) |existing|
                        existing
                    else blk: {
                        const c = try self.allocator.create(Value);
                        c.* = self.currentFrame().vars.get(var_name) orelse .null;
                        try self.ref_cells.append(self.allocator, c);
                        try self.currentFrame().ref_slots.put(self.allocator, var_name, c);
                        break :blk c;
                    };
                    try self.captures.append(self.allocator, .{
                        .closure_name = closure_name,
                        .var_name = var_name,
                        .value = .null,
                        .ref_cell = cell,
                    });
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

                                    // execute via runUntilFrame so halt pops back here
                                    const return_frame = self.frame_count;
                                    self.frames[self.frame_count] = .{
                                        .chunk = &result.chunk,
                                        .ip = 0,
                                        .vars = .{},
                                    };
                                    self.frame_count += 1;
                                    self.runUntilFrame(return_frame) catch {
                                        if (is_require) return error.RuntimeError;
                                        self.push(.{ .bool = false });
                                        continue;
                                    };
                                    // clean up the included file's frame if halt left it
                                    while (self.frame_count > return_frame) {
                                        self.frame_count -= 1;
                                        self.frames[self.frame_count].vars.deinit(self.allocator);
                                    }
                                    self.push(.{ .bool = true });
                                } else {
                                    if (is_require) return error.RuntimeError;
                                    self.push(.{ .bool = false });
                                }
                            } else {
                                if (is_require) return error.RuntimeError;
                                self.push(.{ .bool = false });
                            }
                        }
                    }
                },

                .array_spread => {
                    // pop source array, spread its elements into the array on top of stack
                    const src = self.pop();
                    if (src == .array) {
                        const target = self.peek();
                        if (target == .array) {
                            for (src.array.entries.items) |entry| {
                                try target.array.append(self.allocator, entry.value);
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

                .class_decl => {
                    const name_idx = self.readU16();
                    const class_name = self.currentChunk().constants.items[name_idx].string;
                    const method_count = self.readByte();

                    var def = ClassDef{ .name = class_name };

                    for (0..method_count) |_| {
                        const mname_idx = self.readU16();
                        const method_name = self.currentChunk().constants.items[mname_idx].string;
                        const arity = self.readByte();
                        const is_static = self.readByte() == 1;
                        const vis: ClassDef.Visibility = @enumFromInt(self.readByte());
                        try def.methods.put(self.allocator, method_name, .{
                            .name = method_name,
                            .arity = arity,
                            .is_static = is_static,
                            .visibility = vis,
                        });
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
                        _ = self.readByte(); // visibility (stored but not enforced for static props yet)
                    }

                    // pop static property defaults (on top of stack, pushed last)
                    var sdefaults: [32]Value = undefined;
                    var sdefault_count: usize = 0;
                    for (0..static_prop_count) |pi| {
                        if (sprop_has_default[pi] == 1) sdefault_count += 1;
                    }
                    var si: usize = sdefault_count;
                    while (si > 0) {
                        si -= 1;
                        sdefaults[si] = self.pop();
                    }

                    // pop instance property defaults
                    var defaults: [32]Value = undefined;
                    var default_count: usize = 0;
                    for (0..prop_count) |pi| {
                        if (prop_has_default[pi] == 1) default_count += 1;
                    }
                    var di: usize = default_count;
                    while (di > 0) {
                        di -= 1;
                        defaults[di] = self.pop();
                    }

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

                    // read implements list
                    const iface_count = self.readByte();
                    for (0..iface_count) |_| {
                        const iname_idx = self.readU16();
                        const iface_name = self.currentChunk().constants.items[iname_idx].string;
                        try def.interfaces.append(self.allocator, iface_name);
                    }

                    // read trait list and copy trait methods
                    const trait_count = self.readByte();
                    var trait_names: [16][]const u8 = undefined;
                    for (0..trait_count) |ti| {
                        const tname_idx = self.readU16();
                        trait_names[ti] = self.currentChunk().constants.items[tname_idx].string;
                    }

                    // read conflict resolution rules
                    const InsteadofRule = struct { method: []const u8, preferred: []const u8, excluded: [16][]const u8, excluded_count: u8 };
                    const AliasRule = struct { method: []const u8, trait: []const u8, alias: []const u8 };
                    var insteadof_rules: [32]InsteadofRule = undefined;
                    var insteadof_count: usize = 0;
                    var alias_rules: [32]AliasRule = undefined;
                    var alias_count: usize = 0;
                    const conflict_count = self.readByte();
                    for (0..conflict_count) |_| {
                        const method_idx = self.readU16();
                        const method_name = self.currentChunk().constants.items[method_idx].string;
                        const rule_trait_idx = self.readU16();
                        const rule_trait = self.currentChunk().constants.items[rule_trait_idx].string;
                        const rule_type = self.readByte();
                        if (rule_type == 1) {
                            var rule = InsteadofRule{ .method = method_name, .preferred = rule_trait, .excluded = undefined, .excluded_count = self.readByte() };
                            for (0..rule.excluded_count) |ei| {
                                const eidx = self.readU16();
                                rule.excluded[ei] = self.currentChunk().constants.items[eidx].string;
                            }
                            insteadof_rules[insteadof_count] = rule;
                            insteadof_count += 1;
                        } else {
                            const aidx = self.readU16();
                            alias_rules[alias_count] = .{ .method = method_name, .trait = rule_trait, .alias = self.currentChunk().constants.items[aidx].string };
                            alias_count += 1;
                        }
                    }

                    for (trait_names[0..trait_count]) |trait_name| {
                        // collect trait methods first to avoid iterator invalidation
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
                                    pending[pending_count] = .{
                                        .name = fn_name[trait_name.len + 2 ..],
                                        .func = entry.value_ptr.*,
                                    };
                                    pending_count += 1;
                                }
                            }
                        }
                        for (pending[0..pending_count]) |tm| {
                            // alias rules apply regardless of insteadof exclusion
                            var vis_override: ?ClassDef.Visibility = null;
                            for (alias_rules[0..alias_count]) |rule| {
                                if (std.mem.eql(u8, rule.method, tm.name) and std.mem.eql(u8, rule.trait, trait_name)) {
                                    // visibility-only change
                                    if (std.mem.eql(u8, rule.alias, "public")) {
                                        vis_override = .public;
                                    } else if (std.mem.eql(u8, rule.alias, "protected")) {
                                        vis_override = .protected;
                                    } else if (std.mem.eql(u8, rule.alias, "private")) {
                                        vis_override = .private;
                                    } else {
                                        // name alias
                                        const alias_method = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ class_name, rule.alias });
                                        try self.strings.append(self.allocator, alias_method);
                                        if (!self.functions.contains(alias_method)) {
                                            try self.functions.put(self.allocator, alias_method, tm.func);
                                            try def.methods.put(self.allocator, rule.alias, .{
                                                .name = rule.alias,
                                                .arity = tm.func.arity,
                                            });
                                        }
                                    }
                                }
                            }

                            // check insteadof rules: is this method excluded for this trait?
                            var excluded = false;
                            for (insteadof_rules[0..insteadof_count]) |rule| {
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

                    try self.classes.put(self.allocator, class_name, def);
                },

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

                .enum_decl => {
                    const name_idx = self.readU16();
                    const enum_name = self.currentChunk().constants.items[name_idx].string;
                    const backed_type_byte = self.readByte();
                    const case_count = self.readByte();

                    var def = ClassDef{ .name = enum_name, .is_enum = true };
                    def.backed_type = @enumFromInt(backed_type_byte);

                    var case_names: [64][]const u8 = undefined;
                    var case_has_value: [64]u8 = undefined;
                    for (0..case_count) |ci| {
                        const cname_idx = self.readU16();
                        case_names[ci] = self.currentChunk().constants.items[cname_idx].string;
                        case_has_value[ci] = self.readByte();
                    }

                    // pop case values (pushed in order, pop in reverse)
                    var case_values: [64]Value = undefined;
                    var value_count: usize = 0;
                    for (0..case_count) |ci| {
                        if (case_has_value[ci] == 1) value_count += 1;
                    }
                    var vi: usize = value_count;
                    while (vi > 0) {
                        vi -= 1;
                        case_values[vi] = self.pop();
                    }

                    // create singleton objects for each case
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

                    // read methods
                    const method_count = self.readByte();
                    for (0..method_count) |_| {
                        const mname_idx = self.readU16();
                        const method_name = self.currentChunk().constants.items[mname_idx].string;
                        const arity = self.readByte();
                        const is_static = self.readByte() == 1;
                        const vis: ClassDef.Visibility = @enumFromInt(self.readByte());
                        try def.methods.put(self.allocator, method_name, .{
                            .name = method_name,
                            .arity = arity,
                            .is_static = is_static,
                            .visibility = vis,
                        });
                    }

                    // read implements
                    const iface_count = self.readByte();
                    for (0..iface_count) |_| {
                        const iname_idx = self.readU16();
                        const iface_name = self.currentChunk().constants.items[iname_idx].string;
                        try def.interfaces.append(self.allocator, iface_name);
                    }

                    // register native methods: cases, from, tryFrom
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

                    try self.classes.put(self.allocator, enum_name, def);
                },

                .new_obj => {
                    const name_idx = self.readU16();
                    const arg_count = self.readByte();
                    var class_name = self.currentChunk().constants.items[name_idx].string;
                    if (std.mem.eql(u8, class_name, "self") or std.mem.eql(u8, class_name, "static")) {
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
                            var new_vars: std.StringHashMapUnmanaged(Value) = .{};
                            try new_vars.put(self.allocator, "$this", .{ .object = obj });
                            for (0..ac) |i| {
                                try new_vars.put(self.allocator, func.params[i], self.stack[self.sp - ac + i]);
                            }
                            self.sp -= ac;
                            // fill missing params with defaults
                            for (ac..func.arity) |i| {
                                const default = if (i < func.defaults.len) func.defaults[i] else Value.null;
                                try new_vars.put(self.allocator, func.params[i], default);
                            }
                            self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars };
                            self.frame_count += 1;

                            const ctor_base = self.frame_count - 1;
                            try self.runUntilFrame(ctor_base);

                            _ = self.pop();
                        } else {
                            self.sp -= ac;
                        }
                    } else {
                        self.sp -= ac;
                    }

                    self.push(.{ .object = obj });
                },

                .get_prop => {
                    const name_idx = self.readU16();
                    const prop_name = self.currentChunk().constants.items[name_idx].string;
                    const obj_val = self.pop();
                    if (obj_val == .object) {
                        const vr = self.findPropertyVisibility(obj_val.object.class_name, prop_name);
                        if (!self.checkVisibility(vr.defining_class, vr.visibility)) {
                            const msg = try std.fmt.allocPrint(self.allocator, "Cannot access {s} property {s}::${s}", .{
                                @tagName(vr.visibility), vr.defining_class, prop_name,
                            });
                            try self.strings.append(self.allocator, msg);
                            if (try self.throwBuiltinException("Error", msg)) continue;
                            return error.RuntimeError;
                        }
                        self.push(obj_val.object.get(prop_name));
                    } else {
                        self.push(.null);
                    }
                },

                .set_prop => {
                    const name_idx = self.readU16();
                    const prop_name = self.currentChunk().constants.items[name_idx].string;
                    const val = try self.copyValue(self.pop());
                    const obj_val = self.pop();
                    if (obj_val == .object) {
                        const vr = self.findPropertyVisibility(obj_val.object.class_name, prop_name);
                        if (!self.checkVisibility(vr.defining_class, vr.visibility)) {
                            const msg = try std.fmt.allocPrint(self.allocator, "Cannot access {s} property {s}::${s}", .{
                                @tagName(vr.visibility), vr.defining_class, prop_name,
                            });
                            try self.strings.append(self.allocator, msg);
                            if (try self.throwBuiltinException("Error", msg)) continue;
                            return error.RuntimeError;
                        }
                        if (vr.is_readonly) {
                            const existing = obj_val.object.get(prop_name);
                            if (existing != .null) {
                                const msg = try std.fmt.allocPrint(self.allocator, "Cannot modify readonly property {s}::${s}", .{
                                    vr.defining_class, prop_name,
                                });
                                try self.strings.append(self.allocator, msg);
                                if (try self.throwBuiltinException("Error", msg)) continue;
                                return error.RuntimeError;
                            }
                        }
                        try obj_val.object.set(self.allocator, prop_name, val);
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
                            return error.RuntimeError;
                        }
                        continue;
                    }

                    if (obj_val != .object) return error.RuntimeError;
                    const obj = obj_val.object;

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
                    const full_name = try self.resolveMethod(obj.class_name, method_name);
                    if (self.native_fns.get(full_name)) |native| {
                        // native method - call with $this in a temporary frame
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
                        self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars, .ref_slots = method_refs };
                        self.frame_count += 1;
                    } else return error.RuntimeError;
                },

                .method_call_spread => {
                    const name_idx = self.readU16();
                    const method_name = self.currentChunk().constants.items[name_idx].string;
                    const args_val = self.pop();
                    if (args_val != .array) return error.RuntimeError;
                    const arr = args_val.array;
                    const ac = arr.entries.items.len;
                    for (arr.entries.items) |entry| self.push(entry.value);
                    // object is now below args on the stack (it was pushed before the args array)
                    // reuse the method_call dispatch by setting up ip to re-read this instruction
                    // actually, just inline the dispatch
                    const obj_val = self.stack[self.sp - ac - 1];
                    if (obj_val != .object) return error.RuntimeError;
                    const obj = obj_val.object;
                    const mvr = self.findMethodVisibility(obj.class_name, method_name);
                    if (!self.checkVisibility(mvr.defining_class, mvr.visibility)) {
                        self.sp -= ac + 1;
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
                        self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars };
                        self.frame_count += 1;
                    } else return error.RuntimeError;
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

                    // resolve parent/self relative to the defining class, not $this
                    const this_val = self.currentFrame().vars.get("$this");
                    if (std.mem.eql(u8, class_name, "parent") or std.mem.eql(u8, class_name, "self")) {
                        // find the defining class from the current function name (ClassName::method)
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
                                self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars };
                                self.frame_count += 1;
                            } else return error.RuntimeError;
                        } else {
                            try self.callNamedFunction(full_name, arg_count);
                        }
                    } else {
                        try self.callNamedFunction(full_name, arg_count);
                    }
                },

                .static_call_spread => {
                    const class_idx = self.readU16();
                    const method_idx = self.readU16();
                    var class_name = self.currentChunk().constants.items[class_idx].string;
                    const method_name = self.currentChunk().constants.items[method_idx].string;
                    const args_val = self.pop();
                    if (args_val != .array) return error.RuntimeError;
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
                                self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars };
                                self.frame_count += 1;
                            } else return error.RuntimeError;
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

                    if (self.getStaticProp(class_name, prop_name)) |val| {
                        self.push(val);
                    } else {
                        self.push(.null);
                    }
                },

                .yield_value => {
                    const val = self.pop();
                    const gen = self.currentFrame().generator orelse return error.RuntimeError;
                    gen.current_value = val;
                    gen.current_key = .{ .int = gen.implicit_key };
                    gen.implicit_key += 1;
                    gen.ip = self.currentFrame().ip;
                    gen.vars = self.currentFrame().vars;
                    try self.saveGeneratorStack(gen);
                    gen.state = .suspended;
                    self.frame_count -= 1;
                    return;
                },

                .yield_pair => {
                    const val = self.pop();
                    const key = self.pop();
                    const gen = self.currentFrame().generator orelse return error.RuntimeError;
                    gen.current_value = val;
                    gen.current_key = key;
                    if (key == .int and key.int >= gen.implicit_key) gen.implicit_key = key.int + 1;
                    gen.ip = self.currentFrame().ip;
                    gen.vars = self.currentFrame().vars;
                    try self.saveGeneratorStack(gen);
                    gen.state = .suspended;
                    self.frame_count -= 1;
                    return;
                },

                .yield_from => {
                    const iterable = self.pop();
                    const outer_gen = self.currentFrame().generator orelse return error.RuntimeError;

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
                        }
                        continue;
                    };
                    gen.return_value = val;
                    gen.current_value = .null;
                    gen.current_key = .null;
                    gen.state = .completed;
                    gen.vars = self.currentFrame().vars;
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
        if (std.mem.eql(u8, name, "self") or std.mem.eql(u8, name, "static")) {
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

        self.frames[self.frame_count] = .{
            .chunk = &gen.func.chunk,
            .ip = gen.ip,
            .vars = gen.vars,
            .generator = gen,
        };
        self.frame_count += 1;

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

    fn writebackGlobals(self: *VM) !void {
        var i: usize = 0;
        while (i < self.global_vars.items.len) {
            const entry = self.global_vars.items[i];
            if (entry.frame_depth == self.frame_count) {
                const val = try self.copyValue(self.currentFrame().vars.get(entry.var_name) orelse .null);
                try self.frames[0].vars.put(self.allocator, entry.var_name, val);
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
            self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars };
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
        // find which class the currently executing function belongs to
        // by scanning function names for ClassName::method pattern
        const current_chunk = self.currentChunk();
        var iter = self.functions.iterator();
        while (iter.next()) |entry| {
            if (&entry.value_ptr.*.chunk == current_chunk) {
                const name = entry.key_ptr.*;
                if (std.mem.indexOf(u8, name, "::")) |sep| {
                    return name[0..sep];
                }
            }
        }
        return null;
    }

    fn hasMethod(self: *VM, class_name: []const u8, method_name: []const u8) bool {
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
        var current = class_name;
        var buf: [256]u8 = undefined;
        while (true) {
            const full = std.fmt.bufPrint(&buf, "{s}::{s}", .{ current, method_name }) catch return error.RuntimeError;
            // check compiled functions
            if (self.functions.get(full)) |_| {
                var iter = self.functions.keyIterator();
                while (iter.next()) |k| {
                    if (std.mem.eql(u8, k.*, full)) return k.*;
                }
            }
            // check native functions
            if (self.native_fns.get(full)) |_| {
                var iter = self.native_fns.keyIterator();
                while (iter.next()) |k| {
                    if (std.mem.eql(u8, k.*, full)) return k.*;
                }
            }
            if (self.classes.get(current)) |cls| {
                if (cls.parent) |p| {
                    current = p;
                    continue;
                }
            }
            return error.RuntimeError;
        }
    }

    fn initObjectProperties(self: *VM, obj: *PhpObject, class_name: []const u8) RuntimeError!void {
        // walk parent chain first (parent properties set first, child overrides)
        if (self.classes.get(class_name)) |cls| {
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

    fn bindClosures(self: *VM, vars: *std.StringHashMapUnmanaged(Value), ref_slots: ?*std.StringHashMapUnmanaged(*Value), name: []const u8) !void {
        for (self.captures.items) |cap| {
            if (std.mem.eql(u8, cap.closure_name, name)) {
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
        self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = vars };
        self.frame_count += 1;
        try self.runUntilFrame(base_frame);
        return self.pop();
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
            if (ac < func.required_params)
                return error.RuntimeError;
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
                self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars, .ref_slots = callee_refs };
                self.frame_count += 1;
            }
        } else return error.RuntimeError;
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
            var new_vars: std.StringHashMapUnmanaged(Value) = .{};
            try self.bindClosures(&new_vars, null, name);
            try self.bindArgs(&new_vars, func, args[0..@min(args.len, func.arity)]);
            return self.executeFunction(func, new_vars);
        } else return error.RuntimeError;
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
        for (fiber.saved_frames.items) |*f| {
            f.vars.deinit(self.allocator);
            f.ref_slots.deinit(self.allocator);
        }
        fiber.saved_frames.clearRetainingCapacity();
        fiber.saved_stack.clearRetainingCapacity();
        fiber.saved_handlers.clearRetainingCapacity();

        // save frames (move ownership of vars/ref_bindings to fiber)
        for (self.frames[base_frame..self.frame_count]) |frame| {
            try fiber.saved_frames.append(self.allocator, .{
                .chunk = frame.chunk,
                .ip = frame.ip,
                .vars = frame.vars,
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

