const std = @import("std");
const Value = @import("value.zig").Value;
const PhpArray = @import("value.zig").PhpArray;
const PhpObject = @import("value.zig").PhpObject;
const Generator = @import("value.zig").Generator;
const Chunk = @import("../pipeline/bytecode.zig").Chunk;
const OpCode = @import("../pipeline/bytecode.zig").OpCode;
const ObjFunction = @import("../pipeline/bytecode.zig").ObjFunction;
const CompileResult = @import("../pipeline/compiler.zig").CompileResult;

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const FileLoader = fn (path: []const u8, allocator: Allocator) ?*CompileResult;
pub const NativeContext = struct {
    allocator: Allocator,
    arrays: *std.ArrayListUnmanaged(*PhpArray),
    strings: *std.ArrayListUnmanaged([]const u8),
    vm: *VM,

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
};

const NativeFn = *const fn (*NativeContext, []const Value) RuntimeError!Value;

const CaptureEntry = struct {
    closure_name: []const u8,
    var_name: []const u8,
    value: Value,
};

pub const ClassDef = struct {
    name: []const u8,
    methods: std.StringHashMapUnmanaged(MethodInfo) = .{},
    properties: std.ArrayListUnmanaged(PropertyDef) = .{},
    static_props: std.StringHashMapUnmanaged(Value) = .{},
    parent: ?[]const u8 = null,
    interfaces: std.ArrayListUnmanaged([]const u8) = .{},

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
    };

    fn deinit(self: *ClassDef, allocator: Allocator) void {
        self.methods.deinit(allocator);
        self.properties.deinit(allocator);
        self.static_props.deinit(allocator);
        self.interfaces.deinit(allocator);
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
    captures: std.ArrayListUnmanaged(CaptureEntry) = .{},
    php_constants: std.StringHashMapUnmanaged(Value) = .{},
    classes: std.StringHashMapUnmanaged(ClassDef) = .{},
    interfaces: std.StringHashMapUnmanaged(InterfaceDef) = .{},
    traits: std.StringHashMapUnmanaged(void) = .{},
    statics: std.StringHashMapUnmanaged(Value) = .{},
    static_vars: std.ArrayListUnmanaged(StaticEntry) = .{},
    file_loader: ?*const FileLoader = null,
    loaded_files: std.StringHashMapUnmanaged(void) = .{},
    compile_results: std.ArrayListUnmanaged(*CompileResult) = .{},
    error_msg: ?[]const u8 = null,
    ob_stack: std.ArrayListUnmanaged(usize) = .{},
    exception_handlers: [32]ExceptionHandler = undefined,
    handler_count: usize = 0,
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
    };

    pub fn init(allocator: Allocator) RuntimeError!VM {
        var vm = VM{ .allocator = allocator };
        try @import("../stdlib/registry.zig").register(&vm.native_fns, allocator);
        try initConstants(&vm.php_constants, allocator);
        try @import("builtins.zig").register(&vm, allocator);
        try @import("../stdlib/datetime.zig").register(&vm, allocator);
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
        try c.put(a, "PHP_MINOR_VERSION", .{ .int = 3 });
        try c.put(a, "PHP_VERSION", .{ .string = "8.3.0" });
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
    }

    pub fn deinit(self: *VM) void {
        for (0..self.frame_count) |i| self.frames[i].vars.deinit(self.allocator);
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
        self.loaded_files.deinit(self.allocator);
        for (self.compile_results.items) |r| {
            var result = r;
            result.deinit();
            self.allocator.destroy(result);
        }
        self.compile_results.deinit(self.allocator);
        self.ob_stack.deinit(self.allocator);
    }

    pub fn interpret(self: *VM, result: *const CompileResult) RuntimeError!void {
        for (result.functions.items) |*func| {
            try self.registerFunction(func);
        }
        self.frames[0] = .{ .chunk = &result.chunk, .ip = 0, .vars = .{} };
        self.frame_count = 1;
        try self.run();
    }

    fn registerFunction(self: *VM, func: *const ObjFunction) RuntimeError!void {
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

    fn run(self: *VM) RuntimeError!void {
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
                    const val = self.currentFrame().vars.get(name) orelse
                        self.php_constants.get(name) orelse .null;
                    self.push(val);
                },
                .set_var => {
                    const idx = self.readU16();
                    const name = self.currentChunk().constants.items[idx].string;
                    try self.currentFrame().vars.put(self.allocator, name, self.peek());
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
                    try a.format(&buf, self.allocator);
                    try b.format(&buf, self.allocator);
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
                    if (name_val != .string) return error.RuntimeError;
                    const name = name_val.string;
                    var i: usize = 0;
                    while (i < ac) : (i += 1) {
                        self.stack[self.sp - ac - 1 + i] = self.stack[self.sp - ac + i];
                    }
                    self.sp -= 1;
                    try self.callNamedFunction(name, arg_count);
                },
                .call_spread => {
                    const name_idx = self.readU16();
                    const name = self.currentChunk().constants.items[name_idx].string;
                    // args array is on top of stack
                    const args_val = self.pop();
                    if (args_val != .array) return error.RuntimeError;
                    const arr = args_val.array;
                    // push each element onto the stack as individual args
                    for (arr.entries.items) |entry| {
                        self.push(entry.value);
                    }
                    const ac: u8 = @intCast(arr.entries.items.len);
                    try self.callNamedFunction(name, ac);
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
                    self.frame_count -= 1;
                    self.frames[self.frame_count].vars.deinit(self.allocator);
                    self.push(result);
                    if (self.frame_count <= base_frame) return;
                },
                .return_void => {
                    try self.writebackStatics();
                    self.frame_count -= 1;
                    self.frames[self.frame_count].vars.deinit(self.allocator);
                    self.push(.null);
                    if (self.frame_count <= base_frame) return;
                },

                .echo => {
                    const v = self.pop();
                    try v.format(&self.output, self.allocator);
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
                    if (arr_val == .array) try arr_val.array.set(self.allocator, Value.toArrayKey(key), val);
                },
                .array_get => {
                    const key = self.pop();
                    const arr_val = self.pop();
                    if (arr_val == .array) {
                        self.push(arr_val.array.get(Value.toArrayKey(key)));
                    } else {
                        self.push(.null);
                    }
                },
                .array_set => {
                    const val = self.pop();
                    const key = self.pop();
                    const arr_val = self.pop();
                    if (arr_val == .array) try arr_val.array.set(self.allocator, Value.toArrayKey(key), val);
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
                    const closure_name = self.peek().string;
                    const val = self.currentFrame().vars.get(var_name) orelse .null;
                    try self.captures.append(self.allocator, .{
                        .closure_name = closure_name,
                        .var_name = var_name,
                        .value = val,
                    });
                },

                .throw => {
                    const exception = self.pop();
                    if (self.handler_count == 0) return error.RuntimeError;

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
                    // copy variable from frame 0 (global scope)
                    const global_val = if (self.frame_count > 1)
                        self.frames[0].vars.get(name) orelse
                            self.php_constants.get(name) orelse .null
                    else
                        self.currentFrame().vars.get(name) orelse .null;
                    try self.currentFrame().vars.put(self.allocator, name, global_val);
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
                    for (0..prop_count) |pi| {
                        const pname_idx = self.readU16();
                        prop_names[pi] = self.currentChunk().constants.items[pname_idx].string;
                        prop_has_default[pi] = self.readByte();
                        prop_vis[pi] = @enumFromInt(self.readByte());
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
                    for (0..trait_count) |_| {
                        const tname_idx = self.readU16();
                        const trait_name = self.currentChunk().constants.items[tname_idx].string;

                        // copy trait methods: TraitName::method -> ClassName::method
                        var fn_iter = self.functions.iterator();
                        while (fn_iter.next()) |entry| {
                            const fn_name = entry.key_ptr.*;
                            if (fn_name.len > trait_name.len + 2 and
                                std.mem.eql(u8, fn_name[0..trait_name.len], trait_name) and
                                std.mem.eql(u8, fn_name[trait_name.len .. trait_name.len + 2], "::"))
                            {
                                const method_name = fn_name[trait_name.len + 2 ..];
                                const class_method = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ class_name, method_name });
                                try self.strings.append(self.allocator, class_method);
                                if (!self.functions.contains(class_method)) {
                                    try self.functions.put(self.allocator, class_method, entry.value_ptr.*);
                                    try def.methods.put(self.allocator, method_name, .{
                                        .name = method_name,
                                        .arity = entry.value_ptr.*.arity,
                                    });
                                }
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

                .new_obj => {
                    const name_idx = self.readU16();
                    const arg_count = self.readByte();
                    const class_name = self.currentChunk().constants.items[name_idx].string;

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

                            var ctx = NativeContext{
                                .allocator = self.allocator,
                                .arrays = &self.arrays,
                                .strings = &self.strings,
                                .vm = self,
                            };
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
                    const val = self.pop();
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

                        var ctx = NativeContext{
                            .allocator = self.allocator,
                            .arrays = &self.arrays,
                            .strings = &self.strings,
                            .vm = self,
                        };
                        const result = try native(&ctx, args_buf[0..ac]);

                        self.frame_count -= 1;
                        self.frames[self.frame_count].vars.deinit(self.allocator);
                        self.push(result);
                    } else if (self.functions.get(full_name)) |func| {
                        var new_vars: std.StringHashMapUnmanaged(Value) = .{};
                        try new_vars.put(self.allocator, "$this", .{ .object = obj });

                        for (self.captures.items) |cap| {
                            if (std.mem.eql(u8, cap.closure_name, full_name)) {
                                try new_vars.put(self.allocator, cap.var_name, cap.value);
                            }
                        }

                        for (0..ac) |i| {
                            try new_vars.put(self.allocator, func.params[i], self.stack[self.sp - ac + i]);
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
                    gen.state = .suspended;
                    self.frame_count -= 1;
                    return;
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

                    const val = self.peek();
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

    fn throwBuiltinException(self: *VM, class_name: []const u8, message: []const u8) !bool {
        const obj = try self.allocator.create(PhpObject);
        obj.* = .{ .class_name = class_name };
        try obj.set(self.allocator, "message", .{ .string = message });
        try obj.set(self.allocator, "code", .{ .int = 0 });
        try self.objects.append(self.allocator, obj);

        if (self.handler_count == 0) return false;

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

        gen.state = .running;
        const saved_sp = self.sp;
        const return_frame = self.frame_count;
        self.frames[self.frame_count] = .{
            .chunk = &gen.func.chunk,
            .ip = gen.ip,
            .vars = gen.vars,
            .generator = gen,
        };
        self.frame_count += 1;

        // if resuming from a yield, push the sent value as the yield expression result
        if (gen.ip > 0) {
            self.push(sent_value);
        }

        self.runUntilFrame(return_frame) catch |err| {
            if (gen.state == .suspended or gen.state == .completed) return;
            return err;
        };
        if (gen.state == .running) {
            gen.state = .completed;
        }
        // restore stack to saved position (yield/return already saved their state)
        self.sp = saved_sp;
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

    fn isInstanceOf(self: *VM, obj_class: []const u8, target_class: []const u8) bool {
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

    const VisResult = struct { visibility: ClassDef.Visibility, defining_class: []const u8 };

    fn findPropertyVisibility(self: *VM, class_name: []const u8, prop_name: []const u8) VisResult {
        var current: ?[]const u8 = class_name;
        while (current) |cn| {
            if (self.classes.get(cn)) |cls| {
                for (cls.properties.items) |prop| {
                    if (std.mem.eql(u8, prop.name, prop_name)) return .{ .visibility = prop.visibility, .defining_class = cn };
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
                try obj.set(self.allocator, prop.name, prop.default);
            }
        }
    }

    fn callNamedFunction(self: *VM, name: []const u8, arg_count: u8) RuntimeError!void {
        if (self.native_fns.get(name)) |native| {
            var args: [16]Value = undefined;
            const ac: usize = arg_count;
            for (0..ac) |i| args[i] = self.stack[self.sp - ac + i];
            self.sp -= ac;
            var ctx = NativeContext{
                .allocator = self.allocator,
                .arrays = &self.arrays,
                .strings = &self.strings,
                .vm = self,
            };
            self.push(try native(&ctx, args[0..ac]));
        } else if (self.functions.get(name)) |func| {
            const ac: usize = arg_count;
            if (!func.is_variadic and (ac < func.required_params or ac > func.arity))
                return error.RuntimeError;
            if (func.is_variadic and ac < func.required_params)
                return error.RuntimeError;
            var new_vars: std.StringHashMapUnmanaged(Value) = .{};
            for (self.captures.items) |cap| {
                if (std.mem.eql(u8, cap.closure_name, name)) {
                    try new_vars.put(self.allocator, cap.var_name, cap.value);
                }
            }
            if (func.is_variadic) {
                // bind non-variadic params normally
                const fixed: usize = func.arity - 1;
                for (0..@min(ac, fixed)) |i| {
                    try new_vars.put(self.allocator, func.params[i], self.stack[self.sp - ac + i]);
                }
                // collect remaining args into an array for the variadic param
                const rest_arr = try self.allocator.create(PhpArray);
                rest_arr.* = .{};
                for (fixed..ac) |i| {
                    try rest_arr.append(self.allocator, self.stack[self.sp - ac + i]);
                }
                try self.arrays.append(self.allocator, rest_arr);
                try new_vars.put(self.allocator, func.params[fixed], .{ .array = rest_arr });
            } else {
                for (0..ac) |i| {
                    try new_vars.put(self.allocator, func.params[i], self.stack[self.sp - ac + i]);
                }
            }
            self.sp -= ac;
            // fill missing non-variadic params with defaults
            if (!func.is_variadic) {
                for (ac..func.arity) |i| {
                    if (i < func.defaults.len) {
                        try new_vars.put(self.allocator, func.params[i], func.defaults[i]);
                    } else {
                        try new_vars.put(self.allocator, func.params[i], .null);
                    }
                }
            }
            if (func.is_generator) {
                const gen = try self.allocator.create(Generator);
                gen.* = .{ .func = func, .vars = new_vars };
                try self.generators.append(self.allocator, gen);
                self.push(.{ .generator = gen });
            } else {
                self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars };
                self.frame_count += 1;
            }
        } else return error.RuntimeError;
    }

    pub fn callByName(self: *VM, name: []const u8, args: []const Value) RuntimeError!Value {
        if (self.native_fns.get(name)) |native| {
            var ctx = NativeContext{
                .allocator = self.allocator,
                .arrays = &self.arrays,
                .strings = &self.strings,
                .vm = self,
            };
            return native(&ctx, args);
        } else if (self.functions.get(name)) |func| {
            if (args.len < func.required_params or args.len > func.arity) return error.RuntimeError;
            var new_vars: std.StringHashMapUnmanaged(Value) = .{};
            for (self.captures.items) |cap| {
                if (std.mem.eql(u8, cap.closure_name, name)) {
                    try new_vars.put(self.allocator, cap.var_name, cap.value);
                }
            }
            for (0..args.len) |i| {
                try new_vars.put(self.allocator, func.params[i], args[i]);
            }
            for (args.len..func.arity) |i| {
                if (i < func.defaults.len) {
                    try new_vars.put(self.allocator, func.params[i], func.defaults[i]);
                } else {
                    try new_vars.put(self.allocator, func.params[i], .null);
                }
            }
            const base_frame = self.frame_count;
            self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars };
            self.frame_count += 1;

            try self.runUntilFrame(base_frame);

            return self.pop();
        } else return error.RuntimeError;
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

