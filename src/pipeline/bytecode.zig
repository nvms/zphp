const std = @import("std");
const Value = @import("../runtime/value.zig").Value;

pub const OpCode = enum(u8) {
    constant, // u16: constant pool index
    op_null,
    op_true,
    op_false,
    pop,

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
    closure_bind, // u16: var name constant (peek closure name, get_var, store capture)
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

    // foreach iteration
    iter_begin, // push index 0 (array already on stack)
    iter_check, // u16: exit offset. peek array+index, push key+value or jump
    iter_advance, // pop index, push index+1
    iter_end, // pop index, pop array
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
    params: []const []const u8,
    chunk: Chunk = .{},
};
