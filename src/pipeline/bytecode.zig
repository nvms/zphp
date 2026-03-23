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
    return_val,
    return_void,

    echo,
    halt,
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
