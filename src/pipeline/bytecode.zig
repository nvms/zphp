const std = @import("std");
const Value = @import("../runtime/value.zig").Value;

pub const OpCode = enum(u8) {
    constant, // u16: constant pool index
    op_null,
    op_true,
    op_false,
    pop,
    dup,

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
    array_set, // pop value, pop key, pop array, set, push value

    // exceptions
    throw,
    push_handler, // u16: catch offset
    pop_handler,
    instance_check, // pop class name string, pop object, push bool

    // classes
    class_decl, // u16: class name, u8: method count, then method_count * (u16 name, u8 arity)
    new_obj, // u16: class name constant, u8: arg count
    get_prop, // u16: property name constant
    set_prop, // u16: property name constant
    method_call, // u16: method name constant, u8: arg count
    method_call_spread, // u16: method name constant (args array on stack above object)
    static_call, // u16: class name, u16: method name, u8: arg count
    static_call_spread, // u16: class name, u16: method name (args array on stack)
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

    pub fn write(self: *Chunk, allocator: std.mem.Allocator, byte: u8, line: u32) !void {
        try self.code.append(allocator, byte);
        try self.lines.append(allocator, line);
    }

    pub fn addConstant(self: *Chunk, allocator: std.mem.Allocator, value: Value) !u16 {
        try self.constants.append(allocator, value);
        return @intCast(self.constants.items.len - 1);
    }

    pub fn offset(self: *const Chunk) usize {
        return self.code.items.len;
    }
};

pub const ObjFunction = struct {
    name: []const u8,
    arity: u8,
    required_params: u8 = 0,
    is_variadic: bool = false,
    is_generator: bool = false,
    is_arrow: bool = false,
    params: []const []const u8,
    defaults: []const Value = &.{},
    ref_params: []const bool = &.{},
    chunk: Chunk = .{},
};
