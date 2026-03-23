const std = @import("std");
const Value = @import("value.zig").Value;
const PhpArray = @import("value.zig").PhpArray;
const Chunk = @import("../pipeline/bytecode.zig").Chunk;
const OpCode = @import("../pipeline/bytecode.zig").OpCode;
const ObjFunction = @import("../pipeline/bytecode.zig").ObjFunction;
const CompileResult = @import("../pipeline/compiler.zig").CompileResult;
const parser = @import("../pipeline/parser.zig");

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
    captures: std.ArrayListUnmanaged(CaptureEntry) = .{},
    allocator: Allocator,

    const CallFrame = struct {
        chunk: *const Chunk,
        ip: usize,
        vars: std.StringHashMapUnmanaged(Value),
    };

    pub fn init(allocator: Allocator) RuntimeError!VM {
        var vm = VM{ .allocator = allocator };
        try @import("stdlib.zig").register(&vm.native_fns, allocator);
        return vm;
    }

    pub fn deinit(self: *VM) void {
        for (0..self.frame_count) |i| self.frames[i].vars.deinit(self.allocator);
        self.functions.deinit(self.allocator);
        self.native_fns.deinit(self.allocator);
        self.output.deinit(self.allocator);
        for (self.strings.items) |s| self.allocator.free(s);
        self.strings.deinit(self.allocator);
        self.captures.deinit(self.allocator);
        for (self.arrays.items) |a| {
            a.deinit(self.allocator);
            self.allocator.destroy(a);
        }
        self.arrays.deinit(self.allocator);
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

                .get_var => {
                    const idx = self.readU16();
                    const name = self.currentChunk().constants.items[idx].string;
                    const val = self.currentFrame().vars.get(name) orelse .null;
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
            if (arg_count != func.arity) return error.RuntimeError;
            var new_vars: std.StringHashMapUnmanaged(Value) = .{};
            for (self.captures.items) |cap| {
                if (std.mem.eql(u8, cap.closure_name, name)) {
                    try new_vars.put(self.allocator, cap.var_name, cap.value);
                }
            }
            const ac: usize = arg_count;
            for (0..ac) |i| {
                try new_vars.put(self.allocator, func.params[i], self.stack[self.sp - ac + i]);
            }
            self.sp -= ac;
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
            if (args.len != func.arity) return error.RuntimeError;
            var new_vars: std.StringHashMapUnmanaged(Value) = .{};
            for (self.captures.items) |cap| {
                if (std.mem.eql(u8, cap.closure_name, name)) {
                    try new_vars.put(self.allocator, cap.var_name, cap.value);
                }
            }
            for (0..args.len) |i| {
                try new_vars.put(self.allocator, func.params[i], args[i]);
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

    fn currentFrame(self: *VM) *CallFrame {
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

// ==========================================================================
// integration tests
// ==========================================================================

fn expectOutput(source: []const u8, expected: []const u8) !void {
    const alloc = std.testing.allocator;

    var ast = try parser.parse(alloc, source);
    defer ast.deinit();

    var result = try @import("../pipeline/compiler.zig").compile(&ast, alloc);
    defer result.deinit();

    var vm = try VM.init(alloc);
    defer vm.deinit();
    try vm.interpret(&result);

    errdefer std.debug.print("\nexpected: \"{s}\"\n  actual: \"{s}\"\n", .{ expected, vm.output.items });
    try std.testing.expectEqualStrings(expected, vm.output.items);
}

test "echo integer" {
    try expectOutput("<?php echo 42;", "42");
}

test "echo string" {
    try expectOutput("<?php echo 'hello';", "hello");
}

test "echo true false null" {
    try expectOutput("<?php echo true;", "1");
    try expectOutput("<?php echo false;", "");
    try expectOutput("<?php echo null;", "");
}

test "arithmetic" {
    try expectOutput("<?php echo 2 + 3;", "5");
    try expectOutput("<?php echo 10 - 3;", "7");
    try expectOutput("<?php echo 4 * 5;", "20");
    try expectOutput("<?php echo 9 / 3;", "3");
    try expectOutput("<?php echo 10 % 3;", "1");
}

test "float arithmetic" {
    try expectOutput("<?php echo 1.5 + 2.5;", "4");
    try expectOutput("<?php echo 10 / 4;", "2.5");
}

test "negation" {
    try expectOutput("<?php echo -42;", "-42");
}

test "variable assignment and read" {
    try expectOutput("<?php $x = 42; echo $x;", "42");
}

test "compound assignment" {
    try expectOutput("<?php $x = 10; $x += 5; echo $x;", "15");
}

test "multiple variables" {
    try expectOutput("<?php $a = 3; $b = 4; echo $a + $b;", "7");
}

test "if true" {
    try expectOutput("<?php if (true) { echo 'yes'; }", "yes");
}

test "if false" {
    try expectOutput("<?php if (false) { echo 'yes'; }", "");
}

test "if else" {
    try expectOutput("<?php if (false) { echo 'a'; } else { echo 'b'; }", "b");
}

test "while loop" {
    try expectOutput("<?php $i = 0; while ($i < 3) { echo $i; $i++; }", "012");
}

test "for loop" {
    try expectOutput("<?php for ($i = 0; $i < 5; $i++) { echo $i; }", "01234");
}

test "comparison" {
    try expectOutput("<?php echo 1 < 2 ? 'y' : 'n';", "y");
    try expectOutput("<?php echo 2 < 1 ? 'y' : 'n';", "n");
}

test "logical and short circuit" {
    try expectOutput("<?php echo false && true ? 'y' : 'n';", "n");
    try expectOutput("<?php echo true && true ? 'y' : 'n';", "y");
}

test "logical or short circuit" {
    try expectOutput("<?php echo false || true ? 'y' : 'n';", "y");
    try expectOutput("<?php echo false || false ? 'y' : 'n';", "n");
}

test "null coalesce" {
    try expectOutput("<?php $x = null; echo $x ?? 'default';", "default");
    try expectOutput("<?php $x = 42; echo $x ?? 'default';", "42");
}

test "function call" {
    try expectOutput("<?php function add($a, $b) { return $a + $b; } echo add(3, 4);", "7");
}

test "function scoping" {
    try expectOutput("<?php $x = 100; function foo($x) { return $x + 1; } echo foo(42); echo $x;", "43100");
}

test "nested calls" {
    try expectOutput("<?php function double($n) { return $n * 2; } function quad($n) { return double(double($n)); } echo quad(3);", "12");
}

test "break in while" {
    try expectOutput("<?php $i = 0; while (true) { if ($i == 3) { break; } echo $i; $i++; }", "012");
}

test "echo multiple" {
    try expectOutput("<?php echo 'a', 'b', 'c';", "abc");
}

test "string concat" {
    try expectOutput("<?php echo 'hello' . ' ' . 'world';", "hello world");
}

test "pre increment" {
    try expectOutput("<?php $x = 5; echo ++$x;", "6");
}

test "post increment" {
    try expectOutput("<?php $x = 5; echo $x++;", "5");
    try expectOutput("<?php $x = 5; $x++; echo $x;", "6");
}

test "mixed html and php" {
    try expectOutput("Hello <?php echo 'World';", "Hello World");
}

test "do while" {
    try expectOutput("<?php $i = 0; do { echo $i; $i++; } while ($i < 3);", "012");
}

test "not operator" {
    try expectOutput("<?php echo !true ? 'y' : 'n';", "n");
    try expectOutput("<?php echo !false ? 'y' : 'n';", "y");
}

test "spaceship operator" {
    try expectOutput("<?php echo 1 <=> 2;", "-1");
    try expectOutput("<?php echo 2 <=> 2;", "0");
    try expectOutput("<?php echo 3 <=> 2;", "1");
}

test "fizzbuzz" {
    try expectOutput(
        \\<?php
        \\for ($i = 1; $i <= 15; $i++) {
        \\    if ($i % 15 == 0) { echo 'FizzBuzz'; }
        \\    elseif ($i % 3 == 0) { echo 'Fizz'; }
        \\    elseif ($i % 5 == 0) { echo 'Buzz'; }
        \\    else { echo $i; }
        \\}
    , "12Fizz4BuzzFizz78FizzBuzz11Fizz1314FizzBuzz");
}

test "array literal" {
    try expectOutput("<?php $a = [1, 2, 3]; echo count($a);", "3");
}

test "array access" {
    try expectOutput("<?php $a = [10, 20, 30]; echo $a[1];", "20");
}

test "array set" {
    try expectOutput("<?php $a = [1, 2, 3]; $a[1] = 99; echo $a[1];", "99");
}

test "array with string keys" {
    try expectOutput("<?php $a = ['x' => 10, 'y' => 20]; echo $a['x'];", "10");
}

test "foreach" {
    try expectOutput("<?php $a = [1, 2, 3]; foreach ($a as $v) { echo $v; }", "123");
}

test "foreach with key" {
    try expectOutput("<?php $a = ['a' => 1, 'b' => 2]; foreach ($a as $k => $v) { echo $k . $v; }", "a1b2");
}

test "count" {
    try expectOutput("<?php echo count([]);", "0");
    try expectOutput("<?php echo count([1, 2, 3]);", "3");
}

test "strlen" {
    try expectOutput("<?php echo strlen('hello');", "5");
    try expectOutput("<?php echo strlen('');", "0");
}

test "is_array" {
    try expectOutput("<?php echo is_array([1]) ? 'y' : 'n';", "y");
    try expectOutput("<?php echo is_array(42) ? 'y' : 'n';", "n");
}

test "closure assigned to variable" {
    try expectOutput("<?php $add = function($a, $b) { return $a + $b; }; echo $add(3, 4);", "7");
}

test "closure passed to function" {
    try expectOutput(
        \\<?php
        \\function apply($fn, $val) { return $fn($val); }
        \\$double = function($x) { return $x * 2; };
        \\echo apply($double, 5);
    , "10");
}

test "arrow function" {
    try expectOutput("<?php $sq = fn($x) => $x * $x; echo $sq(6);", "36");
}

test "array_map" {
    try expectOutput(
        \\<?php
        \\$nums = [1, 2, 3];
        \\$doubled = array_map(function($x) { return $x * 2; }, $nums);
        \\foreach ($doubled as $v) { echo $v; }
    , "246");
}

test "array_filter" {
    try expectOutput(
        \\<?php
        \\$nums = [1, 2, 3, 4, 5];
        \\$even = array_filter($nums, function($x) { return $x % 2 == 0; });
        \\foreach ($even as $v) { echo $v; }
    , "24");
}

test "usort" {
    try expectOutput(
        \\<?php
        \\$a = [3, 1, 2];
        \\usort($a, function($a, $b) { return $a - $b; });
        \\foreach ($a as $v) { echo $v; }
    , "123");
}

test "array_map with arrow function" {
    try expectOutput(
        \\<?php
        \\$result = array_map(fn($x) => $x + 10, [1, 2, 3]);
        \\foreach ($result as $v) { echo $v . ' '; }
    , "11 12 13 ");
}

test "inline closure call" {
    try expectOutput("<?php echo (function($x) { return $x + 1; })(41);", "42");
}

test "named function as callback string" {
    try expectOutput(
        \\<?php
        \\function triple($x) { return $x * 3; }
        \\$result = array_map('triple', [1, 2, 3]);
        \\foreach ($result as $v) { echo $v; }
    , "369");
}

test "closure use clause" {
    try expectOutput(
        \\<?php
        \\$x = 10;
        \\$add = function($y) use ($x) { return $x + $y; };
        \\echo $add(5);
    , "15");
}

test "closure use multiple vars" {
    try expectOutput(
        \\<?php
        \\$a = 'hello';
        \\$b = ' world';
        \\$greet = function() use ($a, $b) { return $a . $b; };
        \\echo $greet();
    , "hello world");
}

test "closure use captures at creation time" {
    try expectOutput(
        \\<?php
        \\$x = 1;
        \\$fn = function() use ($x) { return $x; };
        \\$x = 99;
        \\echo $fn();
    , "1");
}

test "closure use with array_map" {
    try expectOutput(
        \\<?php
        \\$multiplier = 3;
        \\$result = array_map(function($x) use ($multiplier) { return $x * $multiplier; }, [1, 2, 3]);
        \\foreach ($result as $v) { echo $v . ' '; }
    , "3 6 9 ");
}

test "string interpolation simple" {
    try expectOutput("<?php $name = 'World'; echo \"Hello $name\";", "Hello World");
}

test "string interpolation multiple" {
    try expectOutput("<?php $a = 'foo'; $b = 'bar'; echo \"$a and $b\";", "foo and bar");
}

test "string interpolation curly" {
    try expectOutput("<?php $x = 'test'; echo \"Value: {$x}!\";", "Value: test!");
}

test "string interpolation with expr after" {
    try expectOutput("<?php $n = 42; echo \"num=$n.\";", "num=42.");
}

test "string interpolation escaped dollar" {
    try expectOutput("<?php echo \"price is \\$5\";", "price is $5");
}

test "string interpolation array access" {
    try expectOutput("<?php $a = ['x', 'y']; echo \"val=$a[1]\";", "val=y");
}

test "string interpolation curly array" {
    try expectOutput("<?php $a = ['k' => 'v']; echo \"{$a['k']}\";", "v");
}

test "string no interpolation single quotes" {
    try expectOutput("<?php $x = 1; echo '$x';", "$x");
}
