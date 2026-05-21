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
    get_var_var, // dynamic: pop name string, push value
    set_var_var, // dynamic: peek value, pop name string, set variable

    add,
    subtract,
    // PHP `++`/`--` aren't just `+ 1` / `- 1`: alphabetic strings increment
    // ('a'++ -> 'b', 'z'++ -> 'aa') and non-numeric strings don't decrement
    // ('b'-- stays 'b'). emitted in place of `add 1` / `subtract 1` for ++/--
    inc_value,
    dec_value,
    multiply,
    divide,
    modulo,
    power,
    negate,
    concat,

    bit_and,
    bit_or,
    bit_xor,
    logical_xor,
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
    cast_object,
    return_val,
    return_void,

    echo,
    halt,

    // arrays
    array_new, // push new empty array
    array_push, // pop value, append to array at stack top
    array_set_elem, // pop value, pop key, set on array at stack top
    array_get, // pop key, pop array, push value
    array_get_coalesce, // pop key, pop array, push value or null (OOB string offset and missing assoc keys become null - for `??` semantics)
    array_get_vivify, // pop key, pop array, push value (create intermediate arrays if missing)
    array_set, // pop value, pop key, pop array, set, push value (value-assign: clones array values)
    array_set_ref, // same as array_set but does NOT clone (for `$arr[k] = &$other` ref-assign)
    array_set_if_present, // foreach by-ref writeback: only write if arr has key. silent no-op when body unset()'d the key during iteration. doesn't push back the value
    array_set_local, // u16: slot - pop value, pop key, set on local at slot (string char-write or array set with vivify), push value (value-assign: clones)
    array_set_local_ref, // same as array_set_local but does NOT clone
    ensure_array_local, // u16: slot - read local, vivify null/false to array, error on scalar, push result
    ensure_array_var, // u16: name const - read var, vivify null/false to array, error on scalar, push result

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
    method_call_dynamic, // u8: arg count (method name string on stack below args, object below that)
    method_call_dynamic_spread, // no operands (method name string and args array on stack, object below)
    static_call, // u16: class name, u16: method name, u8: arg count
    static_call_spread, // u16: class name, u16: method name (args array on stack)
    static_call_dynamic, // u16: method name, u8: arg count (class name string on stack before args)
    static_call_dyn_method, // u16: class name, u8: arg count (method name string on stack below args)
    interface_decl, // u16: name, u16: method count, then method_count * u16 method name, u8: parent_count, then parent_count * u16 parent name, u8: const_count, then const_count * u16 const name
    trait_decl, // u16: name, u8: sub_trait_count, then sub_trait_count * u16 sub_trait_name
    enum_decl, // u16: enum name, u8: backed_type (0=none, 1=int, 2=string), u8: case_count, then case_count * (u16 name, u8 has_value), then method/implements like class_decl
    get_static_prop, // u16: class name, u16: property name
    set_static_prop, // u16: class name, u16: property name
    get_static_prop_dynamic, // u16: property name (class name on stack)
    get_static_prop_dyn_name, // u16: class name constant (property name string on stack)
    get_static_prop_dyn_both, // no operand: class name then property name on stack
    set_static_prop_dyn, // no operand: class name, property name, value on stack

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
    iter_end, // pop index, pop iterable
    iter_end_close, // pop index, pop iterable; if iterable is a suspended generator, close it (runs finally)

    silence_begin, // increment vm.error_silenced_depth
    silence_end, // decrement vm.error_silenced_depth

    // u16 name_idx: pops [src_array, key]. Allocates a heap Value cell initialized
    // to src_array[key]. Registers ref_slots[name] = cell and a writeback binding
    // so subsequent writes to $name propagate to src_array[key]. Used by list/array
    // destructuring with `&` (e.g. `[, &$b] = $arr`).
    bind_array_ref,

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
    unset_prop_dynamic, // pop prop name, pop object, remove property
    unset_array_elem, // pop key, pop array, remove element

    // isset on property - dispatches to __isset magic method
    isset_prop, // u16: prop name - pop object, push bool
    isset_prop_dynamic, // pop prop name, pop object, push bool
    isset_index, // pop key, pop array/object, push bool (offsetExists for objects)

    // optimized concat-assign: $var .= expr without full copy
    concat_assign, // u16: var name constant index - pop value, append to var's string

    // `$dst = &$src` between two plain variables — installs a shared Value cell
    // in ref_slots for both names. seeds the cell with src's current value
    // (uncopied pointer for arrays so the alias is genuine)
    make_var_ref, // u16: dst name const, u16: src name const

    // `$dst = &$arr[$key]` — pops [array, key], creates a cell holding the
    // (uncopied) array[key] value, registers a writeback so subsequent
    // assignments to $dst propagate to array[key], and installs the cell in
    // ref_slots[dst]. tolerates missing keys (vivifies to null)
    make_var_array_elem_ref, // u16: dst name const

    // `$dst = &$obj->prop` — pops [object], reads prop_name from constants,
    // creates a cell holding the (uncopied) prop value, registers a writeback
    // so subsequent assignments to $dst propagate to obj->prop, installs the
    // cell in ref_slots[dst]
    make_var_prop_ref, // u16: dst name const, u16: prop name const

    // remove a name from ref_slots so a subsequent normal assignment doesn't
    // write through an existing ref-binding. emitted before the value-write
    // path for `=&` shapes we don't yet bind explicitly
    break_var_ref, // u16: dst name const

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
    static_call_dyn_both, // u8: arg count (class name string and method name string on stack below args)
    static_call_dyn_both_spread, // no operands (class name, method name, and args array on stack)
    get_obj_class, // pop value, push its class name string (for $var::class)
    array_elem_inc, // pop key, pop array, arr[key]++, push old value
    array_elem_dec, // pop key, pop array, arr[key]--, push old value

    // `$arr[k][i] = v` for depth-2 chains where the inner can be a string
    // (char-write), an array (set element), or absent (vivify). pops
    // [val, i, k, base_arr] and writes back into base_arr at k when the inner
    // is a string. push val. avoids the legacy clobber-string-with-array
    // behaviour of array_get_vivify + array_set
    array_set_chain,
    // `$obj->prop[i] = v` — variant for property-rooted chains. always
    // accesses prop directly (never routes through offsetGet/offsetSet
    // on the base object). pops [val, i, prop_name, base_obj]
    prop_set_chain,

    // Class::CONST read - u16 class name, u16 constant name. throws a fatal
    // Error on a miss (unlike get_static_prop which nulls). appended at the
    // end of the enum so existing opcode numbers are untouched
    get_class_const,

    pub fn width(self: OpCode) usize {
        return switch (self) {
            .constant, .get_var, .set_var, .jump, .jump_back, .jump_if_false, .jump_if_true,
            .jump_if_not_null, .push_handler, .get_prop, .set_prop, .get_local, .set_local,
            .get_global, .concat_assign, .unset_var, .unset_prop, .isset_prop,
            .closure_bind, .closure_bind_ref, .define_const,
            .iter_check, .inc_local, .dec_local,
            .get_static_prop_dynamic,
            .ensure_array_local, .ensure_array_var,
            .make_var_array_elem_ref, .break_var_ref,
            .array_set_local, .array_set_local_ref,
            => 3,
            .call, .call_spread, .new_obj, .method_call, .method_call_spread, .static_call_dyn_method, .make_var_ref, .make_var_prop_ref => 4,
            .get_static_prop, .get_class_const, .set_static_prop, .get_static, .set_static,
            .static_call_spread, .add_local_to_local, .sub_local_to_local, .mul_local_to_local,
            => 5,
            .static_call => 6,
            .less_local_local_jif => 7,
            .require, .call_indirect, .call_indirect_spread, .method_call_dynamic, .static_call_dyn_both => 2,
            .class_decl, .interface_decl, .enum_decl, .trait_decl => 1,
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
            .get_global, .get_static,
            .get_static_prop, .get_class_const, .array_new, .clone_obj, .isset_prop, .isset_index,
            .ensure_array_local, .ensure_array_var,
            => 1,
            // pop object, push property value (net 0: pop obj, push val)
            .get_prop,
            => 0,
            // binary ops: pop 2, push 1
            .array_get, .array_get_coalesce, .array_get_vivify,
            .get_prop_dynamic,
            .isset_prop_dynamic,
            .array_elem_inc, .array_elem_dec,
            .add, .subtract, .multiply, .divide, .modulo, .power, .concat,
            .bit_and, .bit_or, .bit_xor, .logical_xor, .shift_left, .shift_right,
            .equal, .not_equal, .identical, .not_identical,
            .less, .less_equal, .greater, .greater_equal, .spaceship,
            .instance_check,
            => -1,
            // unary ops: pop 1, push 1
            .negate, .bit_not, .not, .cast_int, .cast_float, .cast_string,
            .cast_bool, .cast_array, .cast_object, .get_obj_class,
            .inc_value, .dec_value,
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
        if (ip >= self.lines.items.len) return null;
        const byte_offset = self.lines.items[ip];
        if (source.len == 0) {
            // bytecode mode: lines store pre-converted line numbers
            return .{ .line = byte_offset, .column = 0, .line_start = 0, .line_end = 0 };
        }
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

pub const NewDefault = struct {
    class_name: []const u8,
    args: []Value,
};

pub const NEW_DEFAULT_PREFIX = "\x00NW\x00";

pub fn isNewDefaultSentinel(s: []const u8) bool {
    return s.len == NEW_DEFAULT_PREFIX.len + 8 and std.mem.startsWith(u8, s, NEW_DEFAULT_PREFIX);
}

pub fn newDefaultPtr(s: []const u8) ?*NewDefault {
    if (!isNewDefaultSentinel(s)) return null;
    const bytes = s[NEW_DEFAULT_PREFIX.len..][0..8];
    const ptr_int = std.mem.readInt(u64, bytes, .little);
    return @ptrFromInt(ptr_int);
}

pub fn encodeNewDefaultSentinel(allocator: std.mem.Allocator, nd: *const NewDefault) ![]u8 {
    var buf = try allocator.alloc(u8, NEW_DEFAULT_PREFIX.len + 8);
    @memcpy(buf[0..NEW_DEFAULT_PREFIX.len], NEW_DEFAULT_PREFIX);
    std.mem.writeInt(u64, buf[NEW_DEFAULT_PREFIX.len..][0..8], @intFromPtr(nd), .little);
    return buf;
}

pub const ReturnTypeKind = enum { none, int, float, bool, string, other };

pub const ObjFunction = struct {
    name: []const u8,
    arity: u8,
    required_params: u8 = 0,
    is_variadic: bool = false,
    is_generator: bool = false,
    is_arrow: bool = false,
    is_static: bool = false,
    locals_only: bool = false,
    params: []const []const u8,
    defaults: []const Value = &.{},
    ref_params: []const bool = &.{},
    chunk: Chunk = .{},
    local_count: u16 = 0,
    slot_names: []const []const u8 = &.{},
    strict_types: bool = false,
    // declared return type kind. fastLoop's return_val uses this to decide
    // whether to bail to runLoop for type-check + non-strict coercion: for a
    // plain scalar kind it bails only when the return value's tag doesn't
    // already match (so a `: int` function returning an int stays fast);
    // `other` (nullable/union/class) always bails; `none` never bails
    return_type_kind: ReturnTypeKind = .none,
    file_path: []const u8 = "",
    start_line: u32 = 0,
    end_line: u32 = 0,
    doc_comment: []const u8 = "",
};
