const std = @import("std");
const vm_mod = @import("runtime/vm.zig");
const VM = vm_mod.VM;
const RuntimeError = vm_mod.RuntimeError;
const Value = @import("runtime/value.zig").Value;
const PhpArray = @import("runtime/value.zig").PhpArray;
const PhpObject = @import("runtime/value.zig").PhpObject;
const OpCode = @import("pipeline/bytecode.zig").OpCode;
const ObjFunction = @import("pipeline/bytecode.zig").ObjFunction;

const InlineCache = VM.InlineCache;

export fn zphp_fast_loop(vm_ptr: *anyopaque) callconv(.c) u8 {
    const self: *VM = @ptrCast(@alignCast(vm_ptr));
    fastLoopImpl(self) catch |err| return switch (err) {
        error.RuntimeError => 1,
        error.OutOfMemory => 2,
    };
    return 0;
}

fn fastLoopImpl(self: *VM) RuntimeError!void {
    const ic = self.ic.?;
    // the operand stack is a fixed reservation, so its base never moves;
    // a local keeps it in a register across stores through it
    const stack = self.stack;
    const entry_fc = self.frame_count;

    reenter: while (true) {
        const frame = &self.frames[self.frame_count - 1];
        const code = frame.chunk.code.items;
        var locals = frame.locals;
        const consts = frame.chunk.constants.items;
        var ip = frame.ip;
        var sp = self.sp;
        // fixed while this frame runs here: every op that could bind a
        // reference or name a variable leaves the fast loop, and a call
        // comes back through reenter
        const no_ref_cells = frame.ref_slots.count() == 0;
        const direct_slots = no_ref_cells and frame.include_parent == null;
        const names_local = namesOnlyInLocals(frame);

        while (true) {
            const byte: OpCode = @enumFromInt(code[ip]);
            ip += 1;

            dispatch: switch (byte) {
                .get_local => {
                    // when a by-ref param binding exists, the local's authoritative
                    // value lives in a ref_slot cell (not locals[slot]). bail so
                    // runLoop can resolve the cell - common after calling a function
                    // with `&$var` from inside a locals_only closure or fiber body
                    if (frame.ref_slots.count() > 0) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    const slot = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    // a variable that holds nothing warns in runLoop
                    if (locals[slot] == .undef) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    // `$x op= number`: get_local, bury 1, the operator, set_local of
                    // the same slot, done in place without moving the operands
                    if (code[ip + 2] == @intFromEnum(OpCode.bury) and code[ip + 3] == 1 and
                        code[ip + 5] == @intFromEnum(OpCode.set_local) and code[ip + 6] == code[ip] and code[ip + 7] == code[ip + 1])
                    {
                        const a = &locals[slot];
                        const b = &stack[sp - 1];
                        const op: OpCode = @enumFromInt(code[ip + 4]);
                        const both_int = a.* == .int and b.* == .int;
                        if ((both_int or (a.* == .float and b.* == .float)) and (op == .add or op == .subtract or op == .multiply)) {
                            const r: Value = switch (op) {
                                .add => if (both_int) Value.intAdd(a.int, b.int) else .{ .float = a.float + b.float },
                                .subtract => if (both_int) Value.intSub(a.int, b.int) else .{ .float = a.float - b.float },
                                else => if (both_int) Value.intMul(a.int, b.int) else .{ .float = a.float * b.float },
                            };
                            b.* = r;
                            ip += 6;
                            continue :dispatch .set_local;
                        }
                    }
                    ip += 2;
                    // an object pushed onto the operand stack takes a reference
                    // (Stage 1); arrays are not stack-owned (refcounting Stage 2)
                    VM.stackRetain(locals[slot]);
                    stack[sp] = locals[slot];
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .set_local => {
                    // bail to runLoop when the frame has ref bindings — those need
                    // propagation through ref_slots / array bindings which fast_loop
                    // doesn't implement
                    if (frame.ref_owner != 0 or frame.ref_slots.count() > 0 or frame.include_parent != null) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    const slot = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    ip += 2;
                    if (!(isScalar(&locals[slot]) and copyScalar(&locals[slot], &stack[sp - 1]))) {
                        const val = stack[sp - 1];
                        // the slot is a durable holder (Stage 1): retain the new value,
                        // release the object the slot previously held
                        const sl_old = locals[slot];
                        if (val == .string) {
                            val.string.retain();
                            locals[slot] = val;
                        } else if (val == .object or val == .resource) {
                            VM.objRetain(if (val == .object) val.object else val.resource);
                            locals[slot] = val;
                        } else if (val == .array) {
                            locals[slot] = try copyValue(self, ic, val);
                        } else {
                            locals[slot] = val;
                        }
                        self.releaseValue(sl_old);
                    }
                    self.sp = sp;
                    if (!names_local) try syncLocalWrite(self, ic, frame, slot, locals[slot]);
                    if (code[ip] == @intFromEnum(OpCode.pop) or code[ip] == @intFromEnum(OpCode.pop_boundary)) {
                        ip += 1;
                        sp -= 1;
                        if (!isScalar(&stack[sp])) self.stackRelease(stack[sp]);
                        // the fused pop is still a statement boundary: free
                        // the temporaries this statement dropped, as .pop does
                        if (self.hasPendingReleases()) {
                            self.sp = sp;
                            ic.slow.drain_pending_destruct(self);
                            sp = self.sp;
                        }
                    }
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .add => {
                    const b = stack[sp - 1];
                    const a = stack[sp - 2];
                    // arrays (union, TypeError) and strings (numeric warnings) take
                    // runLoop's arithmetic
                    if (!isNumber(a) or !isNumber(b)) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    sp -= 2;
                    self.stackRelease(a);
                    self.stackRelease(b);
                    stack[sp] = if (a == .int and b == .int) Value.intAdd(a.int, b.int) else if (a == .float and b == .float) .{ .float = a.float + b.float } else Value.add(a, b);
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .subtract => {
                    const b = stack[sp - 1];
                    const a = stack[sp - 2];
                    // arrays (union, TypeError) and strings (numeric warnings) take
                    // runLoop's arithmetic
                    if (!isNumber(a) or !isNumber(b)) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    sp -= 2;
                    self.stackRelease(a);
                    self.stackRelease(b);
                    stack[sp] = if (a == .int and b == .int) Value.intSub(a.int, b.int) else if (a == .float and b == .float) .{ .float = a.float - b.float } else Value.subtract(a, b);
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .multiply => {
                    const b = stack[sp - 1];
                    const a = stack[sp - 2];
                    // arrays (union, TypeError) and strings (numeric warnings) take
                    // runLoop's arithmetic
                    if (!isNumber(a) or !isNumber(b)) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    sp -= 2;
                    self.stackRelease(a);
                    self.stackRelease(b);
                    stack[sp] = if (a == .int and b == .int) Value.intMul(a.int, b.int) else if (a == .float and b == .float) .{ .float = a.float * b.float } else Value.multiply(a, b);
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .less => {
                    const b = stack[sp - 1];
                    const a = stack[sp - 2];
                    const result = if (a == .int and b == .int) a.int < b.int else if (a == .float and b == .float) a.float < b.float else blk: {
                        if (a == .object or b == .object or a == .resource or b == .resource or a == .array or b == .array) {
                            frame.ip = ip - 1;
                            self.sp = sp;
                            return;
                        }
                        break :blk Value.lessThan(a, b);
                    };
                    sp -= 2;
                    self.stackRelease(a);
                    self.stackRelease(b);
                    stack[sp] = .{ .bool = result };
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .less_equal => {
                    const b = stack[sp - 1];
                    const a = stack[sp - 2];
                    const result = if (a == .int and b == .int) a.int <= b.int else blk: {
                        if (a == .object or b == .object or a == .resource or b == .resource or a == .array or b == .array) {
                            frame.ip = ip - 1;
                            self.sp = sp;
                            return;
                        }
                        break :blk !Value.lessThan(b, a);
                    };
                    sp -= 2;
                    self.stackRelease(a);
                    self.stackRelease(b);
                    stack[sp] = .{ .bool = result };
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .greater => {
                    const b = stack[sp - 1];
                    const a = stack[sp - 2];
                    const result = if (a == .int and b == .int) a.int > b.int else blk: {
                        if (a == .object or b == .object or a == .resource or b == .resource or a == .array or b == .array) {
                            frame.ip = ip - 1;
                            self.sp = sp;
                            return;
                        }
                        break :blk Value.lessThan(b, a);
                    };
                    sp -= 2;
                    self.stackRelease(a);
                    self.stackRelease(b);
                    stack[sp] = .{ .bool = result };
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .greater_equal => {
                    const b = stack[sp - 1];
                    const a = stack[sp - 2];
                    const result = if (a == .int and b == .int) a.int >= b.int else blk: {
                        if (a == .object or b == .object or a == .resource or b == .resource or a == .array or b == .array) {
                            frame.ip = ip - 1;
                            self.sp = sp;
                            return;
                        }
                        break :blk !Value.lessThan(a, b);
                    };
                    sp -= 2;
                    self.stackRelease(a);
                    self.stackRelease(b);
                    stack[sp] = .{ .bool = result };
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .equal => {
                    frame.ip = ip - 1;
                    self.sp = sp;
                    return;
                },
                .not_equal => {
                    frame.ip = ip - 1;
                    self.sp = sp;
                    return;
                },
                .identical => {
                    const b_id = stack[sp - 1];
                    const a_id = stack[sp - 2];
                    // comparing two arrays may throw (recursion), which runLoop does
                    if (a_id == .array and b_id == .array) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    sp -= 2;
                    self.stackRelease(a_id);
                    self.stackRelease(b_id);
                    stack[sp] = .{ .bool = Value.identical(a_id, b_id) };
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .not_identical => {
                    const b_ni = stack[sp - 1];
                    const a_ni = stack[sp - 2];
                    // comparing two arrays may throw (recursion), which runLoop does
                    if (a_ni == .array and b_ni == .array) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    sp -= 2;
                    self.stackRelease(a_ni);
                    self.stackRelease(b_ni);
                    stack[sp] = .{ .bool = !Value.identical(a_ni, b_ni) };
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .modulo => {
                    const b_mod = stack[sp - 1];
                    const a_mod = stack[sp - 2];
                    if (a_mod == .object or b_mod == .object or a_mod == .resource or b_mod == .resource) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    sp -= 2;
                    self.stackRelease(a_mod);
                    self.stackRelease(b_mod);
                    stack[sp] = Value.modulo(a_mod, b_mod);
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .bit_and => {
                    const b_ba = stack[sp - 1];
                    const a_ba = stack[sp - 2];
                    if (a_ba == .int and b_ba == .int) {
                        sp -= 1;
                        stack[sp - 1] = .{ .int = a_ba.int & b_ba.int };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    }
                    frame.ip = ip - 1;
                    self.sp = sp;
                    return;
                },
                .bit_or => {
                    const b_bo = stack[sp - 1];
                    const a_bo = stack[sp - 2];
                    if (a_bo == .int and b_bo == .int) {
                        sp -= 1;
                        stack[sp - 1] = .{ .int = a_bo.int | b_bo.int };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    }
                    frame.ip = ip - 1;
                    self.sp = sp;
                    return;
                },
                .bit_xor => {
                    const b_bx = stack[sp - 1];
                    const a_bx = stack[sp - 2];
                    if (a_bx == .int and b_bx == .int) {
                        sp -= 1;
                        stack[sp - 1] = .{ .int = a_bx.int ^ b_bx.int };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    }
                    frame.ip = ip - 1;
                    self.sp = sp;
                    return;
                },
                .shift_left => {
                    const b_sl = stack[sp - 1];
                    const a_sl = stack[sp - 2];
                    if (a_sl == .int and b_sl == .int and b_sl.int >= 0 and b_sl.int < 64) {
                        sp -= 1;
                        stack[sp - 1] = .{ .int = a_sl.int << @intCast(b_sl.int) };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    }
                    frame.ip = ip - 1;
                    self.sp = sp;
                    return;
                },
                .shift_right => {
                    const b_sr = stack[sp - 1];
                    const a_sr = stack[sp - 2];
                    if (a_sr == .int and b_sr == .int and b_sr.int >= 0 and b_sr.int < 64) {
                        sp -= 1;
                        stack[sp - 1] = .{ .int = a_sr.int >> @intCast(b_sr.int) };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    }
                    frame.ip = ip - 1;
                    self.sp = sp;
                    return;
                },
                .negate => {
                    const operand = stack[sp - 1];
                    if (operand != .int and operand != .float) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    stack[sp - 1] = operand.negate();
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .not => {
                    // read before writing: the result location's tag may be
                    // set before its payload is evaluated
                    const not_operand = stack[sp - 1];
                    const not_result = !not_operand.isTruthy();
                    self.stackRelease(not_operand);
                    stack[sp - 1] = .{ .bool = not_result };
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .jump_back => {
                    const offset = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    ip += 2;
                    // a timeout is reported at the jump, the loop's own line;
                    // fastLoop owns its ip, so flush it for the exception
                    if (self.deadlineReached()) {
                        self.frames[self.frame_count - 1].ip = ip;
                        try status(ic.slow.expire_execution(self));
                    }
                    ip -= offset;
                    self.frames[self.frame_count - 1].ip = ip;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .constant => {
                    const idx = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    ip += 2;
                    stack[sp] = consts[idx];
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .jump_if_false => {
                    const offset = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    ip += 2;
                    if (!isTruthyAt(&stack[sp - 1])) {
                        ip += offset;
                    } else if (code[ip] == @intFromEnum(OpCode.pop) or code[ip] == @intFromEnum(OpCode.pop_boundary)) {
                        ip += 1;
                        sp -= 1;
                        self.stackRelease(stack[sp]);
                        if (self.hasPendingReleases()) {
                            self.sp = sp;
                            ic.slow.drain_pending_destruct(self);
                            sp = self.sp;
                        }
                    }
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .jump_if_true => {
                    const offset = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    ip += 2;
                    if (isTruthyAt(&stack[sp - 1])) {
                        ip += offset;
                    } else if (code[ip] == @intFromEnum(OpCode.pop) or code[ip] == @intFromEnum(OpCode.pop_boundary)) {
                        ip += 1;
                        sp -= 1;
                        self.stackRelease(stack[sp]);
                        if (self.hasPendingReleases()) {
                            self.sp = sp;
                            ic.slow.drain_pending_destruct(self);
                            sp = self.sp;
                        }
                    }
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .jump => {
                    const offset = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    ip += 2;
                    ip += offset;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .pop, .pop_boundary => {
                    sp -= 1;
                    // a discarded operand-stack object releases its reference
                    // (Stage 1; arrays are not stack-owned - refcounting Stage 2)
                    self.stackRelease(stack[sp]);
                    if (self.hasPendingReleases()) {
                        // destructors run nested PHP on the shared operand
                        // stack: publish the local stack pointer first
                        self.sp = sp;
                        ic.slow.drain_pending_destruct(self);
                        sp = self.sp;
                    }
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .dup => {
                    // a duplicated object is a new operand-stack reference (Stage 1)
                    VM.stackRetain(stack[sp - 1]);
                    stack[sp] = stack[sp - 1];
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .dup2 => {
                    VM.stackRetain(stack[sp - 2]);
                    VM.stackRetain(stack[sp - 1]);
                    stack[sp] = stack[sp - 2];
                    stack[sp + 1] = stack[sp - 1];
                    sp += 2;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .bury => {
                    const n = code[ip];
                    ip += 1;
                    const top = stack[sp - 1];
                    const dest = sp - 1 - n;
                    std.mem.copyBackwards(Value, stack[dest + 1 .. sp], stack[dest .. sp - 1]);
                    stack[dest] = top;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .op_null => {
                    stack[sp] = .null;
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .op_true => {
                    stack[sp] = .{ .bool = true };
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .op_false => {
                    stack[sp] = .{ .bool = false };
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .cast_int => {
                    const v = stack[sp - 1];
                    // objects and floats past the int range can warn: the slow path has them
                    if (v == .object or (v == .float and !(v.float >= -9.2233720368547758e18 and v.float < 9.2233720368547758e18))) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    const as_int = Value.toInt(v);
                    self.stackRelease(v);
                    stack[sp - 1] = .{ .int = as_int };
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .concat_assign_local => {
                    const ca_slot = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    ip += 2;
                    const ca_append = stack[sp - 1];
                    const ca_current = locals[ca_slot];
                    if (!direct_slots or ca_append != .string or ca_current != .string) {
                        frame.ip = ip - 3;
                        self.sp = sp;
                        return;
                    }
                    const ca_suffix = ca_append.string.bytes();
                    const ca_owner = ca_current.string.owner;
                    const ca_result: Value = if (ca_owner != null and !ca_owner.?.closure and ca_owner.?.refcount == 1 and ca_current.string.ptr == ca_owner.?.bytes.ptr) grow: {
                        // the variable is the string's only holder: append in place
                        const owner = ca_owner.?;
                        const length = ca_current.string.len + ca_suffix.len;
                        if (length > owner.bytes.len) owner.bytes = try owner.allocator.realloc(owner.bytes, @max(length, owner.bytes.len + owner.bytes.len / 2 + 16));
                        @memcpy(owner.bytes[ca_current.string.len..length], ca_suffix);
                        const grown: Value = .{ .string = .{ .ptr = owner.bytes.ptr, .len = length, .owner = owner } };
                        locals[ca_slot] = grown;
                        break :grow grown;
                    } else fresh: {
                        const bytes = try self.stringAllocator().alloc(u8, ca_current.string.len + ca_suffix.len);
                        @memcpy(bytes[0..ca_current.string.len], ca_current.string.bytes());
                        @memcpy(bytes[ca_current.string.len..], ca_suffix);
                        const joined: Value = .{ .string = try Value.String.adopt(self.stringAllocator(), bytes) };
                        locals[ca_slot] = joined;
                        self.releaseValue(ca_current);
                        break :fresh joined;
                    };
                    self.stackRelease(ca_append);
                    VM.stackRetain(ca_result);
                    stack[sp - 1] = ca_result;
                    if (!names_local) {
                        self.sp = sp;
                        try syncLocalWrite(self, ic, frame, ca_slot, ca_result);
                    }
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .get_class_const => {
                    const gc_site = ip - 1;
                    const gc_class = consts[(@as(u16, code[ip]) << 8) | code[ip + 1]].string.bytes();
                    ip += 4;
                    const gc_class_ptr = classConstReceiver(frame, locals, gc_class);
                    const gc_entry = &ic.class_const[InlineCache.propIndex(@intFromPtr(frame.chunk), gc_site)];
                    if (gc_class_ptr != 0 and gc_entry.key == gc_site and gc_entry.chunk_key == @intFromPtr(frame.chunk) and gc_entry.class_ptr == gc_class_ptr) {
                        VM.stackRetain(gc_entry.value);
                        stack[sp] = gc_entry.value;
                        sp += 1;
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    }
                    frame.ip = gc_site;
                    self.sp = sp;
                    return;
                },
                .cast_bool => {
                    const v = stack[sp - 1];
                    const truthy = v.isTruthy();
                    self.stackRelease(v);
                    stack[sp - 1] = .{ .bool = truthy };
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .inc_value, .dec_value => |step_op| {
                    // ints and floats step in place; anything else (strings,
                    // null, overflow) takes runLoop's phpInc/phpDec
                    const v = stack[sp - 1];
                    const delta: i64 = if (step_op == .inc_value) 1 else -1;
                    if (v == .int) {
                        const r = @addWithOverflow(v.int, delta);
                        if (r[1] != 0) {
                            frame.ip = ip - 1;
                            self.sp = sp;
                            return;
                        }
                        stack[sp - 1] = .{ .int = r[0] };
                    } else if (v == .float) {
                        stack[sp - 1] = .{ .float = v.float + @as(f64, @floatFromInt(delta)) };
                    } else {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .array_get, .array_get_list => {
                    // missing keys (a warning), non-scalar keys (a TypeError),
                    // $GLOBALS (global cells) and anything but arrays and
                    // in-range string offsets take runLoop's path, as does a
                    // destructured string, which php doesn't index
                    const ag_key = stack[sp - 1];
                    const ag_arr = stack[sp - 2];
                    const ag_elem: ?Value = switch (ag_arr) {
                        .array => |arr| if (ag_key == .resource or ag_key == .array or ag_key == .object or arr == self.globals_array)
                            null
                        else if (arr.getPtr(Value.toArrayKey(ag_key))) |entry| entry.value else null,
                        .string => |str| if (code[ip - 1] == @intFromEnum(OpCode.array_get) and ag_key == .int and ag_key.int >= 0 and @as(usize, @intCast(ag_key.int)) < str.len) blk: {
                            const at: usize = @intCast(ag_key.int);
                            break :blk .{ .string = str.retainedSlice(at, at + 1) };
                        } else null,
                        else => null,
                    };
                    const elem = ag_elem orelse {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    };
                    sp -= 2;
                    self.stackRelease(ag_key);
                    if (ag_arr == .string) {
                        // the one-byte view already owns its reference
                        self.stackRelease(ag_arr);
                    } else {
                        // an element pushed onto the operand stack takes a
                        // reference (Stage 1); arrays are not stack-owned
                        VM.stackRetain(elem);
                    }
                    stack[sp] = elem;
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .array_get_vivify => {
                    const agv_key = stack[sp - 1];
                    const agv_arr = stack[sp - 2];
                    sp -= 2;
                    if (agv_arr == .array and agv_key != .resource) {
                        const agv_arr_key = Value.toArrayKey(agv_key);
                        const agv_existing = agv_arr.array.get(agv_arr_key);
                        if (agv_existing == .array) {
                            self.stackRelease(agv_key);
                            stack[sp] = agv_existing;
                            sp += 1;
                            const _next = code[ip];
                            ip += 1;
                            continue :dispatch @as(OpCode, @enumFromInt(_next));
                        } else {
                            frame.ip = ip - 1;
                            self.sp = sp + 2;
                            return;
                        }
                    } else {
                        frame.ip = ip - 1;
                        self.sp = sp + 2;
                        return;
                    }
                },
                .array_elem_inc => {
                    const aei_key = stack[sp - 1];
                    const aei_arr = stack[sp - 2];
                    if (aei_arr == .array and aei_key != .resource) {
                        const ak = Value.toArrayKey(aei_key);
                        const old = aei_arr.array.get(ak);
                        if (old == .int) {
                            aei_arr.array.set(self.allocator, ak, .{ .int = old.int + 1 }) catch {
                                frame.ip = ip - 1;
                                self.sp = sp;
                                return;
                            };
                            self.stackRelease(aei_key);
                            sp -= 1;
                            stack[sp - 1] = old;
                            const _next = code[ip];
                            ip += 1;
                            continue :dispatch @as(OpCode, @enumFromInt(_next));
                        }
                    }
                    frame.ip = ip - 1;
                    self.sp = sp;
                    return;
                },
                .array_elem_dec => {
                    const aei_key = stack[sp - 1];
                    const aei_arr = stack[sp - 2];
                    if (aei_arr == .array and aei_key != .resource) {
                        const ak = Value.toArrayKey(aei_key);
                        const old = aei_arr.array.get(ak);
                        if (old == .int) {
                            aei_arr.array.set(self.allocator, ak, .{ .int = old.int - 1 }) catch {
                                frame.ip = ip - 1;
                                self.sp = sp;
                                return;
                            };
                            self.stackRelease(aei_key);
                            sp -= 1;
                            stack[sp - 1] = old;
                            const _next = code[ip];
                            ip += 1;
                            continue :dispatch @as(OpCode, @enumFromInt(_next));
                        }
                    }
                    frame.ip = ip - 1;
                    self.sp = sp;
                    return;
                },
                .echo => {
                    const echo_val = stack[sp - 1];
                    sp -= 1;
                    if (echo_val == .string) {
                        self.output.appendSlice(self.allocator, echo_val.string.bytes()) catch {
                            frame.ip = ip - 1;
                            self.sp = sp + 1;
                            return;
                        };
                        self.stackRelease(echo_val);
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else if (echo_val == .int) {
                        var tmp: [20]u8 = undefined;
                        const s = std.fmt.bufPrint(&tmp, "{d}", .{echo_val.int}) catch {
                            frame.ip = ip - 1;
                            self.sp = sp + 1;
                            return;
                        };
                        self.output.appendSlice(self.allocator, s) catch {
                            frame.ip = ip - 1;
                            self.sp = sp + 1;
                            return;
                        };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    }
                    frame.ip = ip - 1;
                    self.sp = sp + 1;
                    return;
                },
                .array_set => {
                    const as_val = stack[sp - 1];
                    const as_key = stack[sp - 2];
                    const as_arr = stack[sp - 3];
                    // an object stored into an array element - bail to runLoop's
                    // array_set so the element holder refcounts it (Stage 1)
                    if (as_val == .object or as_val == .resource) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    if (as_arr == .array and as_key != .resource) {
                        arraySetOwned(self, ic, as_arr.array, Value.toArrayKey(as_key), as_val) catch {
                            frame.ip = ip - 1;
                            self.sp = sp;
                            return;
                        };
                        self.stackRelease(as_key);
                        sp -= 2;
                        stack[sp - 1] = as_val;
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    }
                    frame.ip = ip - 1;
                    self.sp = sp;
                    return;
                },
                .array_push => {
                    const ap_val = stack[sp - 1];
                    const ap_arr = stack[sp - 2];
                    if (ap_val == .object or ap_val == .resource) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    if (ap_arr == .array) {
                        ap_arr.array.append(self.allocator, ap_val) catch {
                            frame.ip = ip - 1;
                            self.sp = sp;
                            return;
                        };
                        self.stackRelease(ap_val);
                        sp -= 1;
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    }
                    frame.ip = ip - 1;
                    self.sp = sp;
                    return;
                },
                .array_set_elem => {
                    const ase_val = stack[sp - 1];
                    const ase_key = stack[sp - 2];
                    const ase_arr = stack[sp - 3];
                    if (ase_val == .object or ase_val == .resource) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    if (ase_arr == .array and ase_key != .resource) {
                        arraySetOwned(self, ic, ase_arr.array, Value.toArrayKey(ase_key), ase_val) catch {
                            frame.ip = ip - 1;
                            self.sp = sp;
                            return;
                        };
                        self.stackRelease(ase_val);
                        self.stackRelease(ase_key);
                        sp -= 2;
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    }
                    frame.ip = ip - 1;
                    self.sp = sp;
                    return;
                },
                .call_indirect => {
                    const ci_ac = code[ip];
                    ip += 1;
                    const ci_acn: usize = ci_ac;
                    const ci_name_val = stack[sp - ci_acn - 1];
                    if (ci_name_val != .string) {
                        frame.ip = ip - 2;
                        self.sp = sp;
                        return;
                    }
                    const ci_name = ci_name_val.string.bytes();
                    const ci_func = self.functions.get(ci_name) orelse {
                        frame.ip = ip - 2;
                        self.sp = sp;
                        return;
                    };
                    // too few arguments is runLoop's to report
                    if (!ci_func.locals_only or !try hasCallRoom(self, sp, sp - ci_acn - 1) or ci_ac < ci_func.required_params) {
                        frame.ip = ip - 2;
                        self.sp = sp;
                        return;
                    }
                    const ci_cap_range = self.getCaptureRange(ci_name);
                    if (ci_cap_range != null and !std.mem.startsWith(u8, ci_name, "__closure_")) {
                        frame.ip = ip - 2;
                        self.sp = sp;
                        return;
                    }
                    if (ci_cap_range) |cr| {
                        if (cr.has_refs) {
                            frame.ip = ip - 2;
                            self.sp = sp;
                            return;
                        }
                    }
                    if (ci_func.has_param_types and !argsHoldDeclared(self, ic, ci_func, ci_name, stack[sp - ci_ac .. sp])) {
                        self.sp = sp;
                        if (try checkParamTypes(self, ic, ci_name, ci_ac)) {
                            frame.ip = ip;
                            return;
                        }
                        sp = self.sp;
                    }
                    const ci_lc: usize = ci_func.local_count;
                    const ci_lbase = ic.locals_sp;
                    if (ci_lbase + ci_lc > ic.locals_cap) {
                        frame.ip = ip - 2;
                        self.sp = sp;
                        return;
                    }
                    self.sp = sp;
                    self.clearArgStackFrom(sp - ci_acn - 1);
                    for (0..ci_acn) |i| {
                        stack[sp - ci_acn - 1 + i] = stack[sp - ci_acn + i];
                    }
                    sp -= 1;
                    const ci_locals = ic.locals_buf[ci_lbase .. ci_lbase + ci_lc];
                    @memset(ci_locals, .undef);
                    ic.locals_sp = ci_lbase + ci_lc;
                    const ci_bind = @min(ci_acn, ci_func.arity);
                    for (0..ci_bind) |i| ci_locals[i] = stack[sp - ci_acn + i];
                    // a default can autoload (self::CONST), running nested frames on
                    // the shared operand stack: publish the stack pointer first
                    self.sp = sp;
                    if (try fillDefaults(self, ic, ci_func, ci_locals, ci_bind, 0)) {
                        frame.ip = ip;
                        return;
                    }
                    self.sp = sp;
                    self.saveFrameArgs(ci_ac);
                    self.dropN(ci_acn);
                    sp = self.sp;
                    // the closure value slot was consumed above; the callee
                    // frame retains the instance by call_name
                    self.stackRelease(ci_name_val);
                    if (ci_cap_range) |cr| {
                        const caps = self.captures.items[cr.start .. cr.start + cr.len];
                        for (caps) |cap| {
                            for (ci_func.slot_names, 0..) |sn, si| {
                                if (sn.len == cap.var_name.len and std.mem.eql(u8, sn, cap.var_name)) {
                                    ci_locals[si] = cap.value;
                                    break;
                                }
                            }
                        }
                    }
                    ic.sp_save[self.frame_count - 1] = sp;
                    self.sp = sp;
                    frame.ip = ip;
                    self.frames[self.frame_count] = .{
                        .chunk = &ci_func.chunk,
                        .ip = 0,
                        .entry_sp = sp,
                        .vars = .{},
                        .locals = ci_locals,
                        .func = ci_func,
                        .called_class = closureScope(self, ci_cap_range) orelse frame.called_class,
                        .call_name = if (ci_cap_range != null) ci_name else null,
                    };
                    ic.arg_counts[self.frame_count] = ci_ac;
                    self.frame_count += 1;
                    ic.slow.retain_frame_objects(self, self.frame_count - 1);
                    if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
                    continue :reenter;
                },
                .get_prop => {
                    const gp_ip = ip;
                    ip += 2;
                    const gp_obj_val = stack[sp - 1];
                    if (gp_obj_val == .object) {
                        const gp_obj = gp_obj_val.object;
                        const gp_idx = InlineCache.propIndex(@intFromPtr(frame.chunk), gp_ip);
                        const gp_entry = &ic.prop[gp_idx];
                        if (gp_entry.key == gp_ip and gp_entry.chunk_key == @intFromPtr(frame.chunk) and gp_entry.class_ptr == @intFromPtr(gp_obj.class_name.ptr) and gp_entry.slot_index != 0xFFFF) {
                            if (gp_obj.slots) |s| {
                                const gp_v = s[gp_entry.slot_index];
                                // a null slot may be an uninitialized typed property
                                // - bail so runLoop runs the type check
                                if (gp_v != .null and gp_obj.lazy == null) {
                                    // the receiver slot is replaced by the property
                                    // value: retain the new occupant, release the
                                    // receiver it overwrites (Stage 1)
                                    const gp_recv = stack[sp - 1];
                                    VM.stackRetain(gp_v);
                                    stack[sp - 1] = gp_v;
                                    self.stackRelease(gp_recv);
                                    const _next_gp = code[ip];
                                    ip += 1;
                                    continue :dispatch @as(OpCode, @enumFromInt(_next_gp));
                                }
                            }
                        }
                    }
                    frame.ip = ip - 3;
                    self.sp = sp;
                    return;
                },
                .set_prop => {
                    const sp_ip = ip;
                    ip += 2;
                    const sp_val = stack[sp - 1];
                    const sp_obj_val = stack[sp - 2];
                    if (sp_obj_val == .object) {
                        const sp_obj = sp_obj_val.object;
                        const sp_idx = InlineCache.propIndex(@intFromPtr(frame.chunk), sp_ip);
                        const sp_entry = &ic.prop[sp_idx];
                        // typed properties (prop_type set) need a declared-type
                        // check. when the value's tag already exactly matches a
                        // simple scalar type the write needs no coercion and can
                        // happen inline; anything else bails to runLoop's set_prop
                        // which runs full checkPropertyType (coercion / TypeError)
                        const sp_typed_ok = sp_entry.prop_type.len == 0 or switch (sp_val) {
                            .int => std.mem.eql(u8, sp_entry.prop_type, "int"),
                            .float => std.mem.eql(u8, sp_entry.prop_type, "float"),
                            .string => std.mem.eql(u8, sp_entry.prop_type, "string"),
                            .bool => std.mem.eql(u8, sp_entry.prop_type, "bool"),
                            .array => std.mem.eql(u8, sp_entry.prop_type, "array"),
                            else => false,
                        };
                        if (sp_typed_ok and sp_entry.key == sp_ip and sp_entry.chunk_key == @intFromPtr(frame.chunk) and sp_entry.class_ptr == @intFromPtr(sp_obj.class_name.ptr) and sp_entry.slot_index != 0xFFFF) {
                            if (sp_obj.slots) |s| {
                                // every bail comes before the copy takes its reference
                                if (self.obj_ref_active) {
                                    frame.ip = ip - 3;
                                    self.sp = sp;
                                    return;
                                }
                                // copyValue: clone an array, retain an object for
                                // the property slot - mirrors runLoop set_prop so a
                                // property is a consistent durable holder (Stage 1)
                                const copied = try copyValue(self, ic, sp_val);
                                // resurrect on write - mirrors runLoop set_prop
                                const sp_name_idx: u16 = (@as(u16, code[sp_ip]) << 8) | code[sp_ip + 1];
                                const sp_prop_name = consts[sp_name_idx].string.bytes();
                                sp_obj.clearUnset(self.allocator, sp_prop_name);
                                // overwrite-release: drop the object the slot held
                                const sp_old_prop = s[sp_entry.slot_index];
                                s[sp_entry.slot_index] = copied;
                                self.releaseValue(sp_old_prop);
                                sp -= 1;
                                // copyValue gave the property slot its reference.
                                // release the consumed input value + receiver from
                                // the operand stack, and re-anchor `copied` in the
                                // result slot. stack ops are objects-only - an
                                // array is owned by the property slot, not the
                                // stack (refcounting Stage 2)
                                self.stackRelease(stack[sp]);
                                self.stackRelease(stack[sp - 1]);
                                VM.stackRetain(copied);
                                stack[sp - 1] = copied;
                                const _next_sp = code[ip];
                                ip += 1;
                                continue :dispatch @as(OpCode, @enumFromInt(_next_sp));
                            }
                        }
                    }
                    frame.ip = ip - 3;
                    self.sp = sp;
                    return;
                },
                .method_call => {
                    const mc_arg_count = code[ip + 2];
                    ip += 3;
                    const mc_ac: usize = mc_arg_count;
                    const mc_obj_val = stack[sp - mc_ac - 1];
                    if (mc_obj_val != .object) {
                        frame.ip = ip - 4;
                        self.sp = sp;
                        return;
                    }
                    const mc_obj = mc_obj_val.object;
                    const mc_ip = ip - 4;
                    const mc_chunk_key = @intFromPtr(frame.chunk);
                    const mc_idx = InlineCache.methodIndex(mc_chunk_key, mc_ip);
                    const mc_entry = &ic.method[mc_idx];
                    if (mc_entry.key == mc_ip and mc_entry.chunk_key == mc_chunk_key and mc_entry.class_ptr == @intFromPtr(mc_obj.class_name.ptr)) {
                        if (mc_entry.func) |mc_func| {
                            // a method is never a closure instance, so it has no captures
                            if (mc_func.locals_only and try hasCallRoom(self, sp, sp - mc_ac - 1)) {
                                if (mc_func.has_param_types and !argsHoldDeclared(self, ic, mc_func, mc_func.name, stack[sp - mc_arg_count .. sp])) {
                                    self.sp = sp;
                                    if (try checkParamTypes(self, ic, mc_func.name, mc_arg_count)) {
                                        frame.ip = ip;
                                        return;
                                    }
                                    sp = self.sp;
                                }
                                const mc_lc: usize = mc_func.local_count;
                                const mc_lbase = ic.locals_sp;
                                if (mc_lbase + mc_lc > ic.locals_cap) {
                                    frame.ip = ip - 4;
                                    self.sp = sp;
                                    return;
                                }
                                const mc_locals = ic.locals_buf[mc_lbase .. mc_lbase + mc_lc];
                                @memset(mc_locals, .undef);
                                ic.locals_sp = mc_lbase + mc_lc;
                                // a static method reached through an instance has no $this slot
                                const mc_first: usize = if (mc_func.is_static) 0 else 1;
                                if (!mc_func.is_static) mc_locals[0] = .{ .object = mc_obj };
                                for (0..@min(mc_ac, mc_func.arity)) |i| {
                                    mc_locals[i + mc_first] = stack[sp - mc_ac + i];
                                }
                                self.sp = sp;
                                if (try fillDefaults(self, ic, mc_func, mc_locals, @min(mc_ac, mc_func.arity), mc_first)) {
                                    frame.ip = ip;
                                    return;
                                }
                                self.sp = sp;
                                if (mc_ac > mc_func.arity) self.saveFrameArgs(@intCast(mc_ac)) else self.markArgsUnsaved();
                                self.dropN(mc_ac + 1);
                                sp = self.sp;
                                frame.ip = ip;
                                ic.sp_save[self.frame_count - 1] = sp;
                                self.sp = sp;
                                self.frames[self.frame_count] = .{
                                    .chunk = &mc_func.chunk,
                                    .ip = 0,
                                    .entry_sp = sp,
                                    .vars = .{},
                                    .locals = mc_locals,
                                    .func = mc_func,
                                };
                                ic.arg_counts[self.frame_count] = mc_arg_count;
                                self.frame_count += 1;
                                ic.slow.retain_frame_objects(self, self.frame_count - 1);
                                if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
                                continue :reenter;
                            }
                        }
                    }
                    frame.ip = ip - 4;
                    self.sp = sp;
                    return;
                },
                .new_obj => {
                    // bail to runLoop for all object construction
                    frame.ip = ip - 1;
                    self.sp = sp;
                    return;
                },
                .call => {
                    const name_idx = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    const arg_count = code[ip + 2];
                    ip += 3;

                    const name = consts[name_idx].string.bytes();
                    const func = blk: {
                        if (ic.fn_cache_name.len == name.len and std.mem.eql(u8, ic.fn_cache_name, name))
                            break :blk ic.fn_cache_func.?;
                        if (self.functions.get(name)) |f| {
                            ic.fn_cache_name = name;
                            ic.fn_cache_func = f;
                            break :blk f;
                        }
                        // try inline native handling for hot builtins
                        const native_sp = sp;
                        if (inlineNativeCall(self, name, arg_count, &sp)) {
                            self.sp = native_sp;
                            self.clearArgStackFrom(native_sp - arg_count);
                            const _next = code[ip];
                            ip += 1;
                            continue :dispatch @as(OpCode, @enumFromInt(_next));
                        }
                        frame.ip = ip - 4;
                        self.sp = sp;
                        return;
                    };

                    // a declared function is never a closure instance, so it has no captures.
                    // too few arguments is runLoop's to report
                    if (!func.locals_only or !try hasCallRoom(self, sp, sp - arg_count) or arg_count < func.required_params) {
                        frame.ip = ip - 4;
                        self.sp = sp;
                        return;
                    }

                    if (func.has_param_types and !argsHoldDeclared(self, ic, func, name, stack[sp - arg_count .. sp])) {
                        self.sp = sp;
                        if (try checkParamTypes(self, ic, name, arg_count)) {
                            frame.ip = ip;
                            return;
                        }
                        sp = self.sp;
                    }
                    const ac: usize = arg_count;
                    const lc: usize = func.local_count;
                    const lbase = ic.locals_sp;

                    if (lbase + lc > ic.locals_cap) {
                        frame.ip = ip - 4;
                        self.sp = sp;
                        return;
                    }

                    const new_locals = ic.locals_buf[lbase .. lbase + lc];
                    @memset(new_locals, .undef);
                    ic.locals_sp = lbase + lc;

                    const bind_count = @min(ac, func.arity);
                    for (0..bind_count) |i| {
                        new_locals[i] = stack[sp - ac + i];
                    }
                    self.sp = sp;
                    if (try fillDefaults(self, ic, func, new_locals, bind_count, 0)) {
                        frame.ip = ip;
                        return;
                    }
                    self.sp = sp;
                    // func_get_args reads the call's arguments from here
                    self.saveFrameArgs(arg_count);
                    self.dropN(ac);
                    sp = self.sp;

                    frame.ip = ip;
                    ic.sp_save[self.frame_count - 1] = sp;
                    self.sp = sp;

                    self.frames[self.frame_count] = .{
                        .chunk = &func.chunk,
                        .ip = 0,
                        .entry_sp = sp,
                        .vars = .{},
                        .locals = new_locals,
                        .func = func,
                        .called_class = frame.called_class,
                    };
                    ic.arg_counts[self.frame_count] = arg_count;
                    self.frame_count += 1;
                    ic.slow.retain_frame_objects(self, self.frame_count - 1);
                    if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
                    continue :reenter;
                },
                .return_val => {
                    const result = stack[sp - 1];
                    // a declared return type needs runLoop's checkReturnType to
                    // validate + non-strict-coerce. for a plain scalar return type
                    // bail ONLY when the value's tag doesn't already match (so a
                    // `: int` function returning an int stays on the fast path);
                    // nullable/union/class return types always bail
                    const ret_bail = if (frame.func) |f| switch (f.return_type_kind) {
                        .none => false,
                        .int => result != .int,
                        .float => result != .float,
                        .bool => result != .bool,
                        .string => result != .string,
                        .other => true,
                    } else false;
                    if (!ownsTeardown(self, frame) or ret_bail) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    // pin borrowed results across local teardown. The result's
                    // existing stack retain moves into the caller slot, while a
                    // local alias is released below.
                    const ret_string_pin = if (result == .string and result.string.owner != null) result.string else null;
                    if (ret_string_pin) |s| s.retain();
                    const ret_arr_pin = if (result == .array) result.array else null;
                    if (ret_arr_pin) |a| VM.arrayRetain(a);
                    self.sp = sp;
                    self.clearArgStackFrom(frame.entry_sp);
                    if (frame.call_name) |name| self.releaseClosureByName(name);
                    if (locals.len > 0) {
                        // move model (Stage 1): release $this and the parameter
                        // locals - this consumes the operand-stack retains the
                        // call site transferred in
                        for (locals) |lv| self.releaseValue(lv);
                        self.freeLocals(locals);
                    }
                    self.frame_count -= 1;
                    self.restoreFrameArgsSp();

                    if (self.frame_count < entry_fc) {
                        stack[sp - 1] = result;
                        self.sp = sp;
                        if (ret_string_pin) |s| s.release();
                        if (ret_arr_pin) |a| VM.arrayUnpin(a);
                        return;
                    }

                    sp = ic.sp_save[self.frame_count - 1];
                    stack[sp] = result;
                    sp += 1;
                    self.sp = sp;
                    if (ret_string_pin) |s| s.release();
                    if (ret_arr_pin) |a| VM.arrayUnpin(a);
                    continue :reenter;
                },
                .return_void => {
                    if (!ownsTeardown(self, frame)) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    self.sp = sp;
                    self.clearArgStackFrom(frame.entry_sp);
                    if (frame.call_name) |name| self.releaseClosureByName(name);
                    if (locals.len > 0) {
                        // move model (Stage 1): release $this and parameter locals
                        for (locals) |lv| self.releaseValue(lv);
                        self.freeLocals(locals);
                    }
                    self.frame_count -= 1;
                    self.restoreFrameArgsSp();

                    if (self.frame_count < entry_fc) {
                        stack[sp] = .null;
                        self.sp = sp + 1;
                        return;
                    }

                    sp = ic.sp_save[self.frame_count - 1];
                    stack[sp] = .null;
                    sp += 1;
                    self.sp = sp;
                    continue :reenter;
                },
                .inc_local => {
                    const slot = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    ip += 2;
                    const v = locals[slot];
                    if (direct_slots) {
                        if (v == .int) {
                            const r = @addWithOverflow(v.int, @as(i64, 1));
                            if (r[1] == 0) {
                                locals[slot] = .{ .int = r[0] };
                                if (!names_local) {
                                    self.sp = sp;
                                    try syncLocalWrite(self, ic, frame, slot, locals[slot]);
                                }
                                const _next = code[ip];
                                ip += 1;
                                continue :dispatch @as(OpCode, @enumFromInt(_next));
                            }
                        } else if (v == .float) {
                            locals[slot] = .{ .float = v.float + 1.0 };
                            if (!names_local) {
                                self.sp = sp;
                                try syncLocalWrite(self, ic, frame, slot, locals[slot]);
                            }
                            const _next = code[ip];
                            ip += 1;
                            continue :dispatch @as(OpCode, @enumFromInt(_next));
                        }
                    }
                    frame.ip = ip - 3;
                    self.sp = sp;
                    return;
                },
                .dec_local => {
                    const slot = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    ip += 2;
                    const v = locals[slot];
                    if (direct_slots) {
                        if (v == .int) {
                            const r = @subWithOverflow(v.int, @as(i64, 1));
                            if (r[1] == 0) {
                                locals[slot] = .{ .int = r[0] };
                                if (!names_local) {
                                    self.sp = sp;
                                    try syncLocalWrite(self, ic, frame, slot, locals[slot]);
                                }
                                const _next = code[ip];
                                ip += 1;
                                continue :dispatch @as(OpCode, @enumFromInt(_next));
                            }
                        } else if (v == .float) {
                            locals[slot] = .{ .float = v.float - 1.0 };
                            if (!names_local) {
                                self.sp = sp;
                                try syncLocalWrite(self, ic, frame, slot, locals[slot]);
                            }
                            const _next = code[ip];
                            ip += 1;
                            continue :dispatch @as(OpCode, @enumFromInt(_next));
                        }
                    }
                    frame.ip = ip - 3;
                    self.sp = sp;
                    return;
                },
                .add_local_to_local => {
                    const src_slot = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    const dst_slot = (@as(u16, code[ip + 2]) << 8) | code[ip + 3];
                    ip += 4;
                    const src = locals[src_slot];
                    const dst = locals[dst_slot];
                    if (direct_slots and isNumber(src) and isNumber(dst)) {
                        var ok = true;
                        if (src == .int and dst == .int) {
                            const r = @addWithOverflow(dst.int, src.int);
                            ok = r[1] == 0;
                            if (ok) locals[dst_slot] = .{ .int = r[0] };
                        } else {
                            const a = if (dst == .int) @as(f64, @floatFromInt(dst.int)) else dst.float;
                            const b = if (src == .int) @as(f64, @floatFromInt(src.int)) else src.float;
                            locals[dst_slot] = .{ .float = a + b };
                        }
                        if (ok) {
                            if (!names_local) {
                                self.sp = sp;
                                try syncLocalWrite(self, ic, frame, dst_slot, locals[dst_slot]);
                            }
                            const _next = code[ip];
                            ip += 1;
                            continue :dispatch @as(OpCode, @enumFromInt(_next));
                        }
                    }
                    frame.ip = ip - 5;
                    self.sp = sp;
                    return;
                },
                .sub_local_to_local => {
                    const src_slot = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    const dst_slot = (@as(u16, code[ip + 2]) << 8) | code[ip + 3];
                    ip += 4;
                    const src = locals[src_slot];
                    const dst = locals[dst_slot];
                    if (direct_slots and isNumber(src) and isNumber(dst)) {
                        var ok = true;
                        if (src == .int and dst == .int) {
                            const r = @subWithOverflow(dst.int, src.int);
                            ok = r[1] == 0;
                            if (ok) locals[dst_slot] = .{ .int = r[0] };
                        } else {
                            const a = if (dst == .int) @as(f64, @floatFromInt(dst.int)) else dst.float;
                            const b = if (src == .int) @as(f64, @floatFromInt(src.int)) else src.float;
                            locals[dst_slot] = .{ .float = a - b };
                        }
                        if (ok) {
                            if (!names_local) {
                                self.sp = sp;
                                try syncLocalWrite(self, ic, frame, dst_slot, locals[dst_slot]);
                            }
                            const _next = code[ip];
                            ip += 1;
                            continue :dispatch @as(OpCode, @enumFromInt(_next));
                        }
                    }
                    frame.ip = ip - 5;
                    self.sp = sp;
                    return;
                },
                .mul_local_to_local => {
                    const src_slot = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    const dst_slot = (@as(u16, code[ip + 2]) << 8) | code[ip + 3];
                    ip += 4;
                    const src = locals[src_slot];
                    const dst = locals[dst_slot];
                    if (direct_slots and isNumber(src) and isNumber(dst)) {
                        var ok = true;
                        if (src == .int and dst == .int) {
                            const r = @mulWithOverflow(dst.int, src.int);
                            ok = r[1] == 0;
                            if (ok) locals[dst_slot] = .{ .int = r[0] };
                        } else {
                            const a = if (dst == .int) @as(f64, @floatFromInt(dst.int)) else dst.float;
                            const b = if (src == .int) @as(f64, @floatFromInt(src.int)) else src.float;
                            locals[dst_slot] = .{ .float = a * b };
                        }
                        if (ok) {
                            if (!names_local) {
                                self.sp = sp;
                                try syncLocalWrite(self, ic, frame, dst_slot, locals[dst_slot]);
                            }
                            const _next = code[ip];
                            ip += 1;
                            continue :dispatch @as(OpCode, @enumFromInt(_next));
                        }
                    }
                    frame.ip = ip - 5;
                    self.sp = sp;
                    return;
                },
                .less_local_local_jif => {
                    if (!no_ref_cells) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    const slot_a = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    const slot_b = (@as(u16, code[ip + 2]) << 8) | code[ip + 3];
                    const offset = (@as(u16, code[ip + 4]) << 8) | code[ip + 5];
                    ip += 6;
                    const a = locals[slot_a];
                    const b = locals[slot_b];
                    if (a == .int and b == .int) {
                        if (a.int >= b.int) ip += offset;
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else if (a == .float and b == .float) {
                        if (a.float >= b.float) ip += offset;
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else {
                        frame.ip = ip - 7;
                        self.sp = sp;
                        return;
                    }
                },
                .concat => {
                    const b = stack[sp - 1];
                    const a = stack[sp - 2];
                    if (a == .string and b == .string) {
                        const as = a.string.bytes();
                        const bs = b.string.bytes();
                        const owned = try self.stringAllocator().alloc(u8, as.len + bs.len);
                        @memcpy(owned[0..as.len], as);
                        @memcpy(owned[as.len..], bs);
                        const result = try Value.String.adopt(self.stringAllocator(), owned);
                        self.stackRelease(a);
                        self.stackRelease(b);
                        sp -= 1;
                        stack[sp - 1] = .{ .string = result };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else if (a == .string and b == .int) {
                        var tmp: [20]u8 = undefined;
                        const bs = std.fmt.bufPrint(&tmp, "{d}", .{b.int}) catch {
                            frame.ip = ip - 1;
                            self.sp = sp;
                            return;
                        };
                        const owned = try self.stringAllocator().alloc(u8, a.string.len + bs.len);
                        @memcpy(owned[0..a.string.len], a.string.bytes());
                        @memcpy(owned[a.string.len..], bs);
                        const result = try Value.String.adopt(self.stringAllocator(), owned);
                        self.stackRelease(a);
                        self.stackRelease(b);
                        sp -= 1;
                        stack[sp - 1] = .{ .string = result };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else if (a == .int and b == .string) {
                        var tmp: [20]u8 = undefined;
                        const as = std.fmt.bufPrint(&tmp, "{d}", .{a.int}) catch {
                            frame.ip = ip - 1;
                            self.sp = sp;
                            return;
                        };
                        const owned = try self.stringAllocator().alloc(u8, as.len + b.string.len);
                        @memcpy(owned[0..as.len], as);
                        @memcpy(owned[as.len..], b.string.bytes());
                        const result = try Value.String.adopt(self.stringAllocator(), owned);
                        self.stackRelease(a);
                        self.stackRelease(b);
                        sp -= 1;
                        stack[sp - 1] = .{ .string = result };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                },
                .arg_variable => {
                    const idx = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    const field = ip + 2;
                    const delta = (@as(u16, code[ip + 2]) << 8) | code[ip + 3];
                    const pos = code[ip + 4];
                    self.sp = sp;
                    const capture = self.argCaptureCached(frame.chunk, field, delta, pos, 1) orelse {
                        frame.ip = ip - 1;
                        return;
                    };
                    ip += 5;
                    if (capture) self.setArgSource(sp - 1, .{ .simple = consts[idx].string.bytes() });
                    const next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(next));
                },
                // by value: the plain fetch that follows runs here untouched.
                // capture: runLoop re-executes the guard and the fetch. `byte`
                // is the first opcode of this dispatch chain, not the current
                // one, so the operand count is fixed per arm
                .arg_guard_prop => {
                    const field = ip;
                    const delta = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    const pos = code[ip + 2];
                    self.sp = sp;
                    const capture = self.argCaptureCached(frame.chunk, field, delta, pos, 1) orelse true;
                    if (capture) {
                        frame.ip = ip - 1;
                        return;
                    }
                    ip += 3;
                    const next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(next));
                },
                .arg_guard_prop_dynamic, .arg_guard_dim => {
                    const field = ip;
                    const delta = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    const pos = code[ip + 2];
                    self.sp = sp;
                    const capture = self.argCaptureCached(frame.chunk, field, delta, pos, 2) orelse true;
                    if (capture) {
                        frame.ip = ip - 1;
                        return;
                    }
                    ip += 3;
                    const next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(next));
                },
                else => {
                    frame.ip = ip - 1;
                    self.sp = sp;
                    return;
                },
            }
        }
    }
}

// the main object's error values are not this object's, so its slow paths
// report a status that becomes an error again here
fn status(code: u8) RuntimeError!void {
    return switch (code) {
        VM.SlowPaths.Status.ok => {},
        VM.SlowPaths.Status.out_of_memory => error.OutOfMemory,
        else => error.RuntimeError,
    };
}

inline fn copyValue(self: *VM, ic: *InlineCache, val: Value) RuntimeError!Value {
    var out: Value = .null;
    try status(ic.slow.copy_value(self, val, &out));
    return out;
}

// the defaults of the parameters a call left out. when one raises, the
// pooled locals are given back, since the frame is never entered, and true
// means the error landed in a catch and the fast loop must return
inline fn fillDefaults(self: *VM, ic: *InlineCache, func: *const ObjFunction, locals: []Value, bound: usize, offset: usize) RuntimeError!bool {
    for (bound..func.arity) |i| {
        if (i >= func.defaults.len) continue;
        var dispatched = false;
        status(ic.slow.resolve_default(self, func, i, &locals[i + offset], &dispatched)) catch |err| {
            ic.locals_sp -= locals.len;
            return err;
        };
        if (dispatched) {
            ic.locals_sp -= locals.len;
            return true;
        }
    }
    return false;
}

inline fn checkParamTypes(self: *VM, ic: *InlineCache, name: []const u8, arg_count: u8) RuntimeError!bool {
    var dispatched = false;
    try status(ic.slow.check_param_types(self, name, arg_count, &dispatched));
    return dispatched;
}

inline fn arraySetOwned(self: *VM, ic: *InlineCache, array: *PhpArray, key: PhpArray.Key, value: Value) RuntimeError!void {
    return status(ic.slow.array_set_owned(self, array, key, value));
}

// arguments that already carry their declared scalar types need no check;
// coercion, class types and errors take the full path
inline fn argsHoldDeclared(self: *VM, ic: *InlineCache, func: *const ObjFunction, name: []const u8, args: []const Value) bool {
    if (ic.typed_func != func) {
        ic.typed_params = ic.slow.param_types(self, name);
        ic.typed_func = func;
    }
    for (args, 0..) |arg, i| {
        if (i >= ic.typed_params.len) break;
        if (!VM.declaredScalarHolds(ic.typed_params[i], arg)) return false;
    }
    return true;
}

fn inlineNativeCall(self: *VM, name: []const u8, arg_count: u8, sp: *usize) bool {
    const ac: usize = arg_count;
    if (name.len == 6 and std.mem.eql(u8, name, "substr")) {
        if (ac < 2 or ac > 3) return false;
        const s_val = self.stack[sp.* - ac];
        if (s_val != .string) return false;
        const string = s_val.string;
        const s = string.bytes();
        const slen: i64 = @intCast(s.len);
        // anything but int arguments needs the native's parameter checks
        const start_arg = self.stack[sp.* - ac + 1];
        if (start_arg != .int) return false;
        if (ac >= 3 and self.stack[sp.* - ac + 2] != .int and self.stack[sp.* - ac + 2] != .null) return false;
        var start = start_arg.int;
        if (start < 0) start = @max(0, slen + start);
        if (start >= slen) {
            for (self.stack[sp.* - ac .. sp.*]) |arg| self.stackRelease(arg);
            sp.* -= ac;
            self.stack[sp.*] = .{ .string = Value.String.borrowed("") };
            sp.* += 1;
            return true;
        }
        const ustart: usize = @intCast(start);
        const result = if (ac >= 3 and self.stack[sp.* - ac + 2] != .null) blk: {
            var length = Value.toInt(self.stack[sp.* - ac + 2]);
            if (length < 0) length = @max(0, slen - @as(i64, @intCast(ustart)) + length);
            const end: usize = @min(s.len, ustart + @as(usize, @intCast(@max(0, length))));
            break :blk string.retainedSlice(ustart, end);
        } else string.retainedSlice(ustart, s.len);
        for (self.stack[sp.* - ac .. sp.*]) |arg| self.stackRelease(arg);
        sp.* -= ac;
        self.stack[sp.*] = .{ .string = result };
        sp.* += 1;
        return true;
    }
    if (name.len == 6 and std.mem.eql(u8, name, "strlen")) {
        if (ac != 1) return false;
        const v = self.stack[sp.* - 1];
        if (v != .string) return false;
        sp.* -= 1;
        self.stackRelease(v);
        self.stack[sp.*] = .{ .int = @intCast(v.string.len) };
        sp.* += 1;
        return true;
    }
    if (name.len == 6 and std.mem.eql(u8, name, "strpos")) {
        if (ac < 2 or ac > 3) return false;
        const hay = self.stack[sp.* - ac];
        const needle = self.stack[sp.* - ac + 1];
        if (hay != .string or needle != .string) return false;
        // negative offsets count from the end and out-of-range ones throw:
        // both are the native's business
        const offset_arg: Value = if (ac >= 3) self.stack[sp.* - ac + 2] else .{ .int = 0 };
        if (offset_arg != .int or offset_arg.int < 0 or offset_arg.int > hay.string.len) return false;
        const offset: usize = @intCast(offset_arg.int);
        if (offset >= hay.string.len and needle.string.len > 0) {
            for (self.stack[sp.* - ac .. sp.*]) |arg| self.stackRelease(arg);
            sp.* -= ac;
            self.stack[sp.*] = .{ .bool = false };
            sp.* += 1;
            return true;
        }
        if (std.mem.indexOf(u8, hay.string.bytes()[offset..], needle.string.bytes())) |pos| {
            for (self.stack[sp.* - ac .. sp.*]) |arg| self.stackRelease(arg);
            sp.* -= ac;
            self.stack[sp.*] = .{ .int = @intCast(pos + offset) };
            sp.* += 1;
        } else {
            for (self.stack[sp.* - ac .. sp.*]) |arg| self.stackRelease(arg);
            sp.* -= ac;
            self.stack[sp.*] = .{ .bool = false };
            sp.* += 1;
        }
        return true;
    }
    if (name.len == 7 and std.mem.eql(u8, name, "strrpos")) {
        if (ac != 2) return false;
        const hay = self.stack[sp.* - ac];
        const needle = self.stack[sp.* - ac + 1];
        if (hay != .string or needle != .string) return false;
        if (std.mem.lastIndexOf(u8, hay.string.bytes(), needle.string.bytes())) |pos| {
            for (self.stack[sp.* - ac .. sp.*]) |arg| self.stackRelease(arg);
            sp.* -= ac;
            self.stack[sp.*] = .{ .int = @intCast(pos) };
            sp.* += 1;
        } else {
            for (self.stack[sp.* - ac .. sp.*]) |arg| self.stackRelease(arg);
            sp.* -= ac;
            self.stack[sp.*] = .{ .bool = false };
            sp.* += 1;
        }
        return true;
    }
    if (name.len == 5 and std.mem.eql(u8, name, "count")) {
        if (ac != 1) return false;
        const v = self.stack[sp.* - 1];
        if (v != .array) return false;
        sp.* -= 1;
        self.stack[sp.*] = .{ .int = v.array.length() };
        sp.* += 1;
        return true;
    }
    return false;
}

// the class a get_class_const site reads for, identified the way runLoop's
// resolveStaticClassName would; 0 when only runLoop can resolve it
fn classConstReceiver(frame: anytype, locals: []Value, raw: []const u8) usize {
    if (raw.len == 0 or raw[0] == '$' or raw[0] == '\\') return 0;
    if (!std.mem.eql(u8, raw, "static")) return @intFromPtr(raw.ptr);
    if (frame.called_class) |cc| return @intFromPtr(cc.ptr);
    const func = frame.func orelse return 0;
    if (func.slot_names.len == 0 or locals.len == 0) return 0;
    if (!std.mem.eql(u8, func.slot_names[0], "$this") or locals[0] != .object) return 0;
    return @intFromPtr(locals[0].object.class_name.ptr);
}

// the class a bound closure runs in, as runLoop's closureScopeByName reads it
fn closureScope(self: *VM, range: anytype) ?[]const u8 {
    const r = range orelse return null;
    for (self.captures.items[r.start .. r.start + r.len]) |cap| {
        if (cap.value == .string and std.mem.eql(u8, cap.var_name, "$__closure_scope")) return cap.value.string.bytes();
    }
    return null;
}

// room for a frame entered at entry_sp (the caller's operands, less the
// call's own), grown here as runLoop's calls grow it
inline fn hasCallRoom(self: *VM, sp: usize, entry_sp: usize) RuntimeError!bool {
    if (self.hasCallRoomAt(entry_sp, 1)) return true;
    self.sp = entry_sp;
    var grown = false;
    const result = self.ic.?.slow.grow_call_room(self, &grown);
    self.sp = sp;
    try status(result);
    return grown;
}

// scalars are read and written field by field: copying a whole value the
// previous handler just wrote misses store forwarding and stalls
inline fn isScalar(v: *const Value) bool {
    return switch (v.*) {
        .int, .float, .bool, .null => true,
        else => false,
    };
}

inline fn copyScalar(dst: *Value, src: *const Value) bool {
    switch (src.*) {
        .int => |n| dst.* = .{ .int = n },
        .float => |f| dst.* = .{ .float = f },
        .bool => |b| dst.* = .{ .bool = b },
        .null => dst.* = .null,
        else => return false,
    }
    return true;
}

inline fn isTruthyAt(v: *const Value) bool {
    return switch (v.*) {
        .bool => |b| b,
        .int => |n| n != 0,
        .null => false,
        else => v.isTruthy(),
    };
}

fn isNumber(v: Value) bool {
    return v == .int or v == .float;
}

// a function frame with no named mirror keeps its variables only in locals
inline fn namesOnlyInLocals(frame: anytype) bool {
    const func = frame.func orelse return false;
    return func.locals_only and frame.vars.count() == 0;
}

// a direct slot write reaches the frame's other views of its variables, as
// runLoop's assignLocal does: the named mirror, and at global scope $GLOBALS
// and global cells (for the top script, deferred to VM.flushTopWrites)
inline fn syncLocalWrite(self: *VM, ic: *InlineCache, frame: anytype, slot: u16, value: Value) RuntimeError!void {
    const func = frame.func orelse {
        // the top script's views catch up when control leaves the fast loop
        if (frame == &self.frames[0] and slot < ic.top_dirty.bit_length) {
            ic.top_dirty.set(slot);
            ic.top_dirty_any = true;
            return;
        }
        return status(ic.slow.set_local_global(self, slot, value));
    };
    if (slot >= func.slot_names.len or func.slot_names[slot].len == 0) return;
    if (frame.vars.getPtr(func.slot_names[slot])) |mirror| {
        mirror.* = value;
    } else if (!func.locals_only) {
        try frame.vars.put(self.allocator, func.slot_names[slot], value);
    }
}

// the fast loop's return only releases locals and a closure instance: any
// frame with more to tear down (an allocated named map or reference cells,
// reference bindings, a generator, statics or globals to write back, its own
// exception handlers, an including scope) returns through runLoop's popFrame
fn ownsTeardown(self: *VM, frame: anytype) bool {
    if (frame.func == null or frame.generator != null or frame.ref_owner != 0) return false;
    if (frame.vars.capacity() > 0 or frame.ref_slots.capacity() > 0) return false;
    if (self.static_vars.items.len > 0 or self.global_vars.items.len > 0 or self.require_merge_depth != 0) return false;
    if (self.handler_count > self.handler_floor and self.exception_handlers[self.handler_count - 1].frame_count >= self.frame_count) return false;
    return true;
}
