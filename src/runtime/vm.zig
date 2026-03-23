const std = @import("std");
const Value = @import("value.zig").Value;
const PhpArray = @import("value.zig").PhpArray;
const PhpObject = @import("value.zig").PhpObject;
const Chunk = @import("../pipeline/bytecode.zig").Chunk;
const OpCode = @import("../pipeline/bytecode.zig").OpCode;
const ObjFunction = @import("../pipeline/bytecode.zig").ObjFunction;
const CompileResult = @import("../pipeline/compiler.zig").CompileResult;

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };
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
    parent: ?[]const u8 = null,

    const MethodInfo = struct {
        name: []const u8,
        arity: u8,
    };

    const PropertyDef = struct {
        name: []const u8,
        default: Value,
    };

    fn deinit(self: *ClassDef, allocator: Allocator) void {
        self.methods.deinit(allocator);
        self.properties.deinit(allocator);
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
    captures: std.ArrayListUnmanaged(CaptureEntry) = .{},
    php_constants: std.StringHashMapUnmanaged(Value) = .{},
    classes: std.StringHashMapUnmanaged(ClassDef) = .{},
    exception_handlers: [32]ExceptionHandler = undefined,
    handler_count: usize = 0,
    allocator: Allocator,

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
    };

    pub fn init(allocator: Allocator) RuntimeError!VM {
        var vm = VM{ .allocator = allocator };
        try @import("../stdlib/registry.zig").register(&vm.native_fns, allocator);
        try initConstants(&vm.php_constants, allocator);
        try @import("builtins.zig").register(&vm, allocator);
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
        var class_iter = self.classes.valueIterator();
        while (class_iter.next()) |c| c.deinit(self.allocator);
        self.classes.deinit(self.allocator);
    }

    pub fn interpret(self: *VM, result: *const CompileResult) RuntimeError!void {
        for (result.functions.items) |*func| {
            try self.functions.put(self.allocator, func.name, func);
        }
        self.frames[0] = .{ .chunk = &result.chunk, .ip = 0, .vars = .{} };
        self.frame_count = 1;
        try self.run();
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
                .divide => self.binaryOp(Value.divide),
                .modulo => self.binaryOp(Value.modulo),
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
                    // shift args down over the name value
                    var i: usize = 0;
                    while (i < ac) : (i += 1) {
                        self.stack[self.sp - ac - 1 + i] = self.stack[self.sp - ac + i];
                    }
                    self.sp -= 1;
                    try self.callNamedFunction(name, arg_count);
                },
                .return_val => {
                    const result = self.pop();
                    self.frame_count -= 1;
                    self.frames[self.frame_count].vars.deinit(self.allocator);
                    self.push(result);
                    if (self.frame_count <= base_frame) return;
                },
                .return_void => {
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

                .iter_begin => self.push(.{ .int = 0 }),
                .iter_check => {
                    const offset = self.readU16();
                    const idx = Value.toInt(self.stack[self.sp - 1]);
                    const arr_val = self.stack[self.sp - 2];
                    if (arr_val != .array or idx >= arr_val.array.length()) {
                        self.currentFrame().ip += offset;
                    } else {
                        const entry = arr_val.array.entries.items[@intCast(idx)];
                        const key_val: Value = switch (entry.key) {
                            .int => |i| .{ .int = i },
                            .string => |s| .{ .string = s },
                        };
                        self.push(key_val);
                        self.push(entry.value);
                    }
                },
                .iter_advance => {
                    const idx = self.pop();
                    self.push(.{ .int = Value.toInt(idx) + 1 });
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
                        try def.methods.put(self.allocator, method_name, .{
                            .name = method_name,
                            .arity = arity,
                        });
                    }

                    const prop_count = self.readByte();

                    // count how many have defaults (to know how many stack values to collect)
                    // read all property metadata first
                    var prop_names: [32][]const u8 = undefined;
                    var prop_has_default: [32]u8 = undefined;
                    for (0..prop_count) |pi| {
                        const pname_idx = self.readU16();
                        prop_names[pi] = self.currentChunk().constants.items[pname_idx].string;
                        prop_has_default[pi] = self.readByte();
                    }

                    // defaults were pushed in forward order, pop in reverse
                    var defaults: [32]Value = undefined;
                    var default_count: usize = 0;
                    for (0..prop_count) |pi| {
                        if (prop_has_default[pi] == 1) default_count += 1;
                    }
                    // pop all defaults (they were pushed in forward order, so last is on top)
                    // reverse-pop to match forward order
                    var di: usize = default_count;
                    while (di > 0) {
                        di -= 1;
                        defaults[di] = self.pop();
                    }

                    // now assign defaults to properties
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
                        });
                    }

                    const parent_idx = self.readU16();
                    if (parent_idx != 0xffff) {
                        def.parent = self.currentChunk().constants.items[parent_idx].string;
                    }

                    try self.classes.put(self.allocator, class_name, def);
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
                        try obj_val.object.set(self.allocator, prop_name, val);
                    }
                    self.push(val);
                },

                .method_call => {
                    const name_idx = self.readU16();
                    const arg_count = self.readByte();
                    const method_name = self.currentChunk().constants.items[name_idx].string;
                    const ac: usize = arg_count;

                    // object is below args on the stack
                    const obj_val = self.stack[self.sp - ac - 1];
                    if (obj_val != .object) return error.RuntimeError;
                    const obj = obj_val.object;

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
            }
        }
    }

    fn isInstanceOf(self: *VM, obj_class: []const u8, target_class: []const u8) bool {
        var current = obj_class;
        while (true) {
            if (std.mem.eql(u8, current, target_class)) return true;
            if (self.classes.get(current)) |cls| {
                if (cls.parent) |p| {
                    current = p;
                    continue;
                }
            }
            return false;
        }
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
            if (ac < func.required_params or ac > func.arity) return error.RuntimeError;
            var new_vars: std.StringHashMapUnmanaged(Value) = .{};
            for (self.captures.items) |cap| {
                if (std.mem.eql(u8, cap.closure_name, name)) {
                    try new_vars.put(self.allocator, cap.var_name, cap.value);
                }
            }
            for (0..ac) |i| {
                try new_vars.put(self.allocator, func.params[i], self.stack[self.sp - ac + i]);
            }
            self.sp -= ac;
            // fill missing params with defaults
            for (ac..func.arity) |i| {
                if (i < func.defaults.len) {
                    try new_vars.put(self.allocator, func.params[i], func.defaults[i]);
                } else {
                    try new_vars.put(self.allocator, func.params[i], .null);
                }
            }
            self.frames[self.frame_count] = .{ .chunk = &func.chunk, .ip = 0, .vars = new_vars };
            self.frame_count += 1;
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

