const std = @import("std");
const Value = @import("../runtime/value.zig").Value;

pub const OpCode = enum(u8) {
    constant, // u16: constant pool index
    op_null,
    op_true,
    op_false,
    pop,
    dup,
    swap,

    get_var, // u16: name constant index
    set_var, // u16: name constant index

    add,
    subtract,
    multiply,
    divide,
    modulo,
    power,
    negate,
    concat,

    bit_and,
    bit_or,
    bit_xor,
    bit_not,
    shift_left,
    shift_right,

    equal,
    not_equal,
    identical,
    not_identical,
    less,
    less_equal,
    greater,
    greater_equal,
    spaceship,

    not,

    jump, // u16: forward offset
    jump_back, // u16: backward offset
    jump_if_false, // u16: forward offset (peek, no pop)
    jump_if_true, // u16: forward offset (peek, no pop)
    jump_if_not_null, // u16: forward offset (peek, no pop)

    call, // u16: name constant index, u8: arg count
    call_indirect, // u8: arg count (function name on stack below args)
    call_spread, // u16: name constant index (args array on stack)
    call_indirect_spread, // (function name below args array on stack)
    closure_bind, // u16: var name constant (peek closure name, get_var, store capture)
    closure_bind_ref, // u16: var name constant (by-reference capture)
    define_const, // u16: name constant index (pop value, store in constants table)
    cast_int,
    cast_float,
    cast_string,
    cast_bool,
    cast_array,
    return_val,
    return_void,

    echo,
    halt,

    // arrays
    array_new, // push new empty array
    array_push, // pop value, append to array at stack top
    array_set_elem, // pop value, pop key, set on array at stack top
    array_get, // pop key, pop array, push value
    array_get_vivify, // pop key, pop array, push value (create intermediate arrays if missing)
    array_set, // pop value, pop key, pop array, set, push value

    // exceptions
    throw,
    push_handler, // u16: catch offset
    pop_handler,
    instance_check, // pop class name string, pop object, push bool

    // classes
    class_decl, // u16: class name, u8: method count, then method_count * (u16 name, u8 arity)
    new_obj, // u16: class name constant, u8: arg count
    new_obj_dynamic, // class name on stack, u8: arg count
    get_prop, // u16: property name constant
    set_prop, // u16: property name constant
    get_prop_dynamic, // property name on stack (from variable)
    set_prop_dynamic, // property name on stack, value on stack (from variable)
    method_call, // u16: method name constant, u8: arg count
    method_call_spread, // u16: method name constant (args array on stack above object)
    static_call, // u16: class name, u16: method name, u8: arg count
    static_call_spread, // u16: class name, u16: method name (args array on stack)
    static_call_dynamic, // u16: method name, u8: arg count (class name string on stack before args)
    interface_decl, // u16: name, u8: method count, then method_count * u16 method name, u16: parent (0xffff = none)
    trait_decl, // u16: name (just registers the trait exists)
    enum_decl, // u16: enum name, u8: backed_type (0=none, 1=int, 2=string), u8: case_count, then case_count * (u16 name, u8 has_value), then method/implements like class_decl
    get_static_prop, // u16: class name, u16: property name
    set_static_prop, // u16: class name, u16: property name

    // scope
    get_global, // u16: var name constant (copy from frame 0)
    get_static, // u16: var name constant, u16: func name constant (get persistent static)
    set_static, // u16: var name constant, u16: func name constant (save persistent static)

    // variadic
    array_spread, // pop array, push each element onto the array below it
    splat_call, // pop array, spread as args to function call

    // file inclusion
    require, // u8: 0=require, 1=require_once, 2=include, 3=include_once (path string on stack)

    // foreach iteration
    iter_begin, // push index 0 (array already on stack)
    iter_check, // u16: exit offset. peek array+index, push key+value or jump
    iter_advance, // pop index, push index+1
    iter_end, // pop index, pop array

    // generators
    yield_value, // pop value, suspend generator, push received value on resume
    yield_pair, // pop value, pop key, suspend generator
    generator_return, // pop value, mark generator completed
    yield_from, // pop iterable, delegate yield, push return value

    // object
    clone_obj, // shallow copy object on top of stack

    // unset
    unset_var, // u16: name constant index - remove variable from current scope
    unset_prop, // u16: prop name - pop object, remove property
    unset_array_elem, // pop key, pop array, remove element

    // isset on property - dispatches to __isset magic method
    isset_prop, // u16: prop name - pop object, push bool
    isset_index, // pop key, pop array/object, push bool (offsetExists for objects)

    // optimized concat-assign: $var .= expr without full copy
    concat_assign, // u16: var name constant index - pop value, append to var's string

    // local variable slots (indexed access, no hash lookup)
    get_local, // u16: slot index - push locals[slot]
    set_local, // u16: slot index - peek value, store in locals[slot]

    // superinstructions - fused opcode sequences for hot loops
    inc_local, // u16: slot index - locals[slot] += 1, no stack effect
    dec_local, // u16: slot index - locals[slot] -= 1, no stack effect
    add_local_to_local, // u16: src slot, u16: dst slot - locals[dst] += locals[src], no stack effect
    sub_local_to_local, // u16: src slot, u16: dst slot - locals[dst] -= locals[src], no stack effect
    mul_local_to_local, // u16: src slot, u16: dst slot - locals[dst] *= locals[src], no stack effect
    less_local_local_jif, // u16: slot_a, u16: slot_b, u16: jump offset - if !(locals[a] < locals[b]) jump

    pub fn width(self: OpCode) usize {
        return switch (self) {
            .constant, .get_var, .set_var, .jump, .jump_back, .jump_if_false, .jump_if_true,
            .jump_if_not_null, .push_handler, .get_prop, .set_prop, .get_local, .set_local,
            .get_global, .concat_assign, .unset_var, .unset_prop, .isset_prop,
            .closure_bind, .closure_bind_ref, .define_const,
            .iter_check, .inc_local, .dec_local, .trait_decl,
            => 3,
            .call, .call_spread, .new_obj, .method_call, .method_call_spread => 4,
            .get_static_prop, .set_static_prop, .get_static, .set_static,
            .static_call_spread, .add_local_to_local, .sub_local_to_local, .mul_local_to_local,
            => 5,
            .static_call => 6,
            .less_local_local_jif => 7,
            .require, .call_indirect, .call_indirect_spread => 2,
            .class_decl, .interface_decl, .enum_decl => 1,
            else => 1,
        };
    }

    pub fn widthFromByte(b: u8) usize {
        const op: OpCode = std.meta.intToEnum(OpCode, b) catch return 1;
        return op.width();
    }

    // net stack effect: +1 = pushes a value, 0 = neutral, -1 = consumes one net
    pub fn stackEffect(self: OpCode) i8 {
        return switch (self) {
            // push a value
            .constant, .op_null, .op_true, .op_false, .dup, .get_var, .get_local,
            .get_global, .get_static, .get_prop, .get_prop_dynamic,
            .get_static_prop, .array_new, .clone_obj, .isset_prop, .isset_index,
            => 1,
            // binary ops: pop 2, push 1
            .add, .subtract, .multiply, .divide, .modulo, .power, .concat,
            .bit_and, .bit_or, .bit_xor, .shift_left, .shift_right,
            .equal, .not_equal, .identical, .not_identical,
            .less, .less_equal, .greater, .greater_equal, .spaceship,
            .instance_check,
            => -1,
            // unary ops: pop 1, push 1
            .negate, .bit_not, .not, .cast_int, .cast_float, .cast_string,
            .cast_bool, .cast_array,
            => 0,
            else => 0,
        };
    }
};


pub const SourceLocation = struct {
    line: u32,
    column: u32,
    line_start: usize,
    line_end: usize,
};

pub const Chunk = struct {
    code: std.ArrayListUnmanaged(u8) = .{},
    constants: std.ArrayListUnmanaged(Value) = .{},
    lines: std.ArrayListUnmanaged(u32) = .{},

    pub fn deinit(self: *Chunk, allocator: std.mem.Allocator) void {
        self.code.deinit(allocator);
        self.constants.deinit(allocator);
        self.lines.deinit(allocator);
    }

    pub fn write(self: *Chunk, allocator: std.mem.Allocator, byte: u8, source_offset: u32) !void {
        try self.code.append(allocator, byte);
        try self.lines.append(allocator, source_offset);
    }

    pub fn addConstant(self: *Chunk, allocator: std.mem.Allocator, value: Value) !u16 {
        try self.constants.append(allocator, value);
        return @intCast(self.constants.items.len - 1);
    }

    pub fn offset(self: *const Chunk) usize {
        return self.code.items.len;
    }

    pub fn getSourceLocation(self: *const Chunk, ip: usize, source: []const u8) ?SourceLocation {
        if (ip >= self.lines.items.len or source.len == 0) return null;
        const byte_offset = self.lines.items[ip];
        return locationFromOffset(source, byte_offset);
    }

    pub fn locationFromOffset(source: []const u8, byte_offset: u32) SourceLocation {
        var line: u32 = 1;
        var line_start: usize = 0;
        const clamped = @min(byte_offset, source.len);

        for (source[0..clamped], 0..) |c, i| {
            if (c == '\n') {
                line += 1;
                line_start = i + 1;
            }
        }

        var line_end: usize = clamped;
        while (line_end < source.len and source[line_end] != '\n') line_end += 1;

        return .{
            .line = line,
            .column = @intCast(clamped - line_start + 1),
            .line_start = line_start,
            .line_end = line_end,
        };
    }
};

pub const ObjFunction = struct {
    name: []const u8,
    arity: u8,
    required_params: u8 = 0,
    is_variadic: bool = false,
    is_generator: bool = false,
    is_arrow: bool = false,
    locals_only: bool = false,
    params: []const []const u8,
    defaults: []const Value = &.{},
    ref_params: []const bool = &.{},
    chunk: Chunk = .{},
    local_count: u16 = 0,
    slot_names: []const []const u8 = &.{},
};
