const std = @import("std");
const vm_mod = @import("runtime/vm.zig");
const VM = vm_mod.VM;
const RuntimeError = vm_mod.RuntimeError;
const Value = @import("runtime/value.zig").Value;
const PhpArray = @import("runtime/value.zig").PhpArray;
const PhpObject = @import("runtime/value.zig").PhpObject;
const OpCode = @import("pipeline/bytecode.zig").OpCode;

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
    const entry_fc = self.frame_count;

    reenter: while (true) {
        const frame = &self.frames[self.frame_count - 1];
        const code = frame.chunk.code.items;
        var locals = frame.locals;
        const consts = frame.chunk.constants.items;
        var ip = frame.ip;
        var sp = self.sp;

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
                    ip += 2;
                    // an object pushed onto the operand stack takes a reference
                    // (Stage 1); arrays are not stack-owned (refcounting Stage 2)
                    VM.stackRetain(locals[slot]);
                    self.stack[sp] = locals[slot];
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
                    const val = self.stack[sp - 1];
                    // the slot is a durable holder (Stage 1): retain the new value,
                    // release the object the slot previously held
                    const sl_old = locals[slot];
                    if (val == .string) {
                        val.string.retain();
                        locals[slot] = val;
                    } else if (val == .object) {
                        VM.objRetain(val.object);
                        locals[slot] = val;
                    } else if (val == .array) {
                        locals[slot] = try self.copyValue(val);
                    } else {
                        locals[slot] = val;
                    }
                    self.releaseValue(sl_old);
                    if (frame.vars.count() > 0) {
                        if (frame.func) |func| {
                            if (slot < func.slot_names.len) {
                                if (frame.vars.getPtr(func.slot_names[slot])) |mirror| mirror.* = locals[slot];
                            }
                        }
                    }
                    if (code[ip] == @intFromEnum(OpCode.pop)) {
                        ip += 1;
                        sp -= 1;
                        self.stackRelease(val);
                        // the fused pop is still a statement boundary: free
                        // the temporaries this statement dropped, as .pop does
                        if (self.hasPendingReleases()) {
                            self.sp = sp;
                            self.drainPendingDestruct();
                            sp = self.sp;
                        }
                    }
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .add => {
                    const b = self.stack[sp - 1];
                    const a = self.stack[sp - 2];
                    if (a == .object or b == .object) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    sp -= 2;
                    self.stackRelease(a);
                    self.stackRelease(b);
                    self.stack[sp] = if (a == .int and b == .int) Value.intAdd(a.int, b.int) else if (a == .float and b == .float) .{ .float = a.float + b.float } else Value.add(a, b);
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .subtract => {
                    const b = self.stack[sp - 1];
                    const a = self.stack[sp - 2];
                    if (a == .object or b == .object) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    sp -= 2;
                    self.stackRelease(a);
                    self.stackRelease(b);
                    self.stack[sp] = if (a == .int and b == .int) Value.intSub(a.int, b.int) else if (a == .float and b == .float) .{ .float = a.float - b.float } else Value.subtract(a, b);
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .multiply => {
                    const b = self.stack[sp - 1];
                    const a = self.stack[sp - 2];
                    if (a == .object or b == .object) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    sp -= 2;
                    self.stackRelease(a);
                    self.stackRelease(b);
                    self.stack[sp] = if (a == .int and b == .int) Value.intMul(a.int, b.int) else if (a == .float and b == .float) .{ .float = a.float * b.float } else Value.multiply(a, b);
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .less => {
                    const b = self.stack[sp - 1];
                    const a = self.stack[sp - 2];
                    sp -= 2;
                    self.stackRelease(a);
                    self.stackRelease(b);
                    self.stack[sp] = .{ .bool = if (a == .int and b == .int) a.int < b.int else if (a == .float and b == .float) a.float < b.float else Value.lessThan(a, b) };
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .less_equal => {
                    const b = self.stack[sp - 1];
                    const a = self.stack[sp - 2];
                    sp -= 2;
                    self.stackRelease(a);
                    self.stackRelease(b);
                    self.stack[sp] = .{ .bool = if (a == .int and b == .int) a.int <= b.int else !Value.lessThan(b, a) };
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .greater => {
                    const b = self.stack[sp - 1];
                    const a = self.stack[sp - 2];
                    sp -= 2;
                    self.stackRelease(a);
                    self.stackRelease(b);
                    self.stack[sp] = .{ .bool = if (a == .int and b == .int) a.int > b.int else Value.lessThan(b, a) };
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .greater_equal => {
                    const b = self.stack[sp - 1];
                    const a = self.stack[sp - 2];
                    sp -= 2;
                    self.stackRelease(a);
                    self.stackRelease(b);
                    self.stack[sp] = .{ .bool = if (a == .int and b == .int) a.int >= b.int else !Value.lessThan(a, b) };
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
                    const b_id = self.stack[sp - 1];
                    const a_id = self.stack[sp - 2];
                    sp -= 2;
                    self.stackRelease(a_id);
                    self.stackRelease(b_id);
                    self.stack[sp] = .{ .bool = Value.identical(a_id, b_id) };
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .not_identical => {
                    const b_ni = self.stack[sp - 1];
                    const a_ni = self.stack[sp - 2];
                    sp -= 2;
                    self.stackRelease(a_ni);
                    self.stackRelease(b_ni);
                    self.stack[sp] = .{ .bool = !Value.identical(a_ni, b_ni) };
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .modulo => {
                    const b_mod = self.stack[sp - 1];
                    const a_mod = self.stack[sp - 2];
                    if (a_mod == .object or b_mod == .object) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    sp -= 2;
                    self.stackRelease(a_mod);
                    self.stackRelease(b_mod);
                    self.stack[sp] = Value.modulo(a_mod, b_mod);
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .bit_and => {
                    const b_ba = self.stack[sp - 1];
                    const a_ba = self.stack[sp - 2];
                    if (a_ba == .int and b_ba == .int) {
                        sp -= 1;
                        self.stack[sp - 1] = .{ .int = a_ba.int & b_ba.int };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    }
                    frame.ip = ip - 1;
                    self.sp = sp;
                    return;
                },
                .bit_or => {
                    const b_bo = self.stack[sp - 1];
                    const a_bo = self.stack[sp - 2];
                    if (a_bo == .int and b_bo == .int) {
                        sp -= 1;
                        self.stack[sp - 1] = .{ .int = a_bo.int | b_bo.int };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    }
                    frame.ip = ip - 1;
                    self.sp = sp;
                    return;
                },
                .bit_xor => {
                    const b_bx = self.stack[sp - 1];
                    const a_bx = self.stack[sp - 2];
                    if (a_bx == .int and b_bx == .int) {
                        sp -= 1;
                        self.stack[sp - 1] = .{ .int = a_bx.int ^ b_bx.int };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    }
                    frame.ip = ip - 1;
                    self.sp = sp;
                    return;
                },
                .shift_left => {
                    const b_sl = self.stack[sp - 1];
                    const a_sl = self.stack[sp - 2];
                    if (a_sl == .int and b_sl == .int and b_sl.int >= 0 and b_sl.int < 64) {
                        sp -= 1;
                        self.stack[sp - 1] = .{ .int = a_sl.int << @intCast(b_sl.int) };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    }
                    frame.ip = ip - 1;
                    self.sp = sp;
                    return;
                },
                .shift_right => {
                    const b_sr = self.stack[sp - 1];
                    const a_sr = self.stack[sp - 2];
                    if (a_sr == .int and b_sr == .int and b_sr.int >= 0 and b_sr.int < 64) {
                        sp -= 1;
                        self.stack[sp - 1] = .{ .int = a_sr.int >> @intCast(b_sr.int) };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    }
                    frame.ip = ip - 1;
                    self.sp = sp;
                    return;
                },
                .negate => {
                    self.stack[sp - 1] = self.stack[sp - 1].negate();
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .not => {
                    self.stack[sp - 1] = .{ .bool = !self.stack[sp - 1].isTruthy() };
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .jump_back => {
                    const offset = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    ip += 2;
                    ip -= offset;
                    // fastLoop owns its own ip; flush it before the deadline check
                    // so a timeout-thrown exception sees a coherent frame state
                    self.frames[self.frame_count - 1].ip = ip;
                    try self.pollExecutionDeadline();
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .constant => {
                    const idx = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    ip += 2;
                    self.stack[sp] = consts[idx];
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .jump_if_false => {
                    const offset = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    ip += 2;
                    if (!self.stack[sp - 1].isTruthy()) {
                        ip += offset;
                    } else if (code[ip] == @intFromEnum(OpCode.pop)) {
                        ip += 1;
                        sp -= 1;
                        self.stackRelease(self.stack[sp]);
                        if (self.hasPendingReleases()) {
                            self.sp = sp;
                            self.drainPendingDestruct();
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
                    if (self.stack[sp - 1].isTruthy()) {
                        ip += offset;
                    } else if (code[ip] == @intFromEnum(OpCode.pop)) {
                        ip += 1;
                        sp -= 1;
                        self.stackRelease(self.stack[sp]);
                        if (self.hasPendingReleases()) {
                            self.sp = sp;
                            self.drainPendingDestruct();
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
                .pop => {
                    sp -= 1;
                    // a discarded operand-stack object releases its reference
                    // (Stage 1; arrays are not stack-owned - refcounting Stage 2)
                    self.stackRelease(self.stack[sp]);
                    if (self.hasPendingReleases()) {
                        // destructors run nested PHP on the shared operand
                        // stack: publish the local stack pointer first
                        self.sp = sp;
                        self.drainPendingDestruct();
                        sp = self.sp;
                    }
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .dup => {
                    // a duplicated object is a new operand-stack reference (Stage 1)
                    VM.stackRetain(self.stack[sp - 1]);
                    self.stack[sp] = self.stack[sp - 1];
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .op_null => {
                    self.stack[sp] = .null;
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .op_true => {
                    self.stack[sp] = .{ .bool = true };
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .op_false => {
                    self.stack[sp] = .{ .bool = false };
                    sp += 1;
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .cast_int => {
                    const v = self.stack[sp - 1];
                    if (v == .object) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    self.stack[sp - 1] = .{ .int = Value.toInt(v) };
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                },
                .array_get => {
                    if (self.globals_cells.count() > 0) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    const ag_key = self.stack[sp - 1];
                    const ag_arr = self.stack[sp - 2];
                    sp -= 2;
                    if (ag_arr == .array) {
                        if (self.globals_array) |ga| {
                            if (ag_arr.array == ga) {
                                frame.ip = ip - 1;
                                self.sp = sp + 2;
                                return;
                            }
                        }
                        const ag_elem = ag_arr.array.get(Value.toArrayKey(ag_key));
                        self.stackRelease(ag_key);
                        // an object element pushed onto the operand stack takes a
                        // reference (Stage 1); arrays are not stack-owned
                        VM.stackRetain(ag_elem);
                        self.stack[sp] = ag_elem;
                        sp += 1;
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else {
                        frame.ip = ip - 1;
                        self.sp = sp + 2;
                        return;
                    }
                },
                .array_get_vivify => {
                    const agv_key = self.stack[sp - 1];
                    const agv_arr = self.stack[sp - 2];
                    sp -= 2;
                    if (agv_arr == .array) {
                        const agv_arr_key = Value.toArrayKey(agv_key);
                        const agv_existing = agv_arr.array.get(agv_arr_key);
                        if (agv_existing == .array) {
                            self.stackRelease(agv_key);
                            self.stack[sp] = agv_existing;
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
                    const aei_key = self.stack[sp - 1];
                    const aei_arr = self.stack[sp - 2];
                    if (aei_arr == .array) {
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
                            self.stack[sp - 1] = old;
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
                    const aei_key = self.stack[sp - 1];
                    const aei_arr = self.stack[sp - 2];
                    if (aei_arr == .array) {
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
                            self.stack[sp - 1] = old;
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
                    const echo_val = self.stack[sp - 1];
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
                    const as_val = self.stack[sp - 1];
                    const as_key = self.stack[sp - 2];
                    const as_arr = self.stack[sp - 3];
                    // an object stored into an array element - bail to runLoop's
                    // array_set so the element holder refcounts it (Stage 1)
                    if (as_val == .object) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    if (as_arr == .array) {
                        self.arraySetOwned(as_arr.array, Value.toArrayKey(as_key), as_val) catch {
                            frame.ip = ip - 1;
                            self.sp = sp;
                            return;
                        };
                        self.stackRelease(as_key);
                        sp -= 2;
                        self.stack[sp - 1] = as_val;
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    }
                    frame.ip = ip - 1;
                    self.sp = sp;
                    return;
                },
                .array_push => {
                    const ap_val = self.stack[sp - 1];
                    const ap_arr = self.stack[sp - 2];
                    if (ap_val == .object) {
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
                    const ase_val = self.stack[sp - 1];
                    const ase_key = self.stack[sp - 2];
                    const ase_arr = self.stack[sp - 3];
                    if (ase_val == .object) {
                        frame.ip = ip - 1;
                        self.sp = sp;
                        return;
                    }
                    if (ase_arr == .array) {
                        self.arraySetOwned(ase_arr.array, Value.toArrayKey(ase_key), ase_val) catch {
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
                    const ci_name_val = self.stack[sp - ci_acn - 1];
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
                    if (!ci_func.locals_only) {
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
                    if (ci_func.has_param_types) {
                        self.sp = sp;
                        if (try self.checkParamTypes(ci_name, ci_ac)) {
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
                        self.stack[sp - ci_acn - 1 + i] = self.stack[sp - ci_acn + i];
                    }
                    sp -= 1;
                    const ci_locals = ic.locals_buf[ci_lbase .. ci_lbase + ci_lc];
                    @memset(ci_locals, .null);
                    ic.locals_sp = ci_lbase + ci_lc;
                    const ci_bind = @min(ci_acn, ci_func.arity);
                    for (0..ci_bind) |i| ci_locals[i] = self.stack[sp - ci_acn + i];
                    for (ci_bind..ci_func.arity) |i| {
                        if (i < ci_func.defaults.len) ci_locals[i] = try self.resolveDefault(ci_func.defaults[i]);
                    }
                    self.sp = sp;
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
                        .call_name = if (ci_cap_range != null) ci_name else null,
                    };
                    ic.arg_counts[self.frame_count] = ci_ac;
                    self.frame_count += 1;
                    self.retainFrameObjects(self.frame_count - 1);
                    if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
                    continue :reenter;
                },
                .get_prop => {
                    const gp_ip = ip;
                    ip += 2;
                    const gp_obj_val = self.stack[sp - 1];
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
                                    const gp_recv = self.stack[sp - 1];
                                    VM.stackRetain(gp_v);
                                    self.stack[sp - 1] = gp_v;
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
                    const sp_val = self.stack[sp - 1];
                    const sp_obj_val = self.stack[sp - 2];
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
                                // copyValue: clone an array, retain an object for
                                // the property slot - mirrors runLoop set_prop so a
                                // property is a consistent durable holder (Stage 1)
                                const copied = try self.copyValue(sp_val);
                                // resurrect on write - mirrors runLoop set_prop
                                const sp_name_idx: u16 = (@as(u16, code[sp_ip]) << 8) | code[sp_ip + 1];
                                const sp_prop_name = consts[sp_name_idx].string.bytes();
                                if (self.obj_ref_active) {
                                    frame.ip = ip - 3;
                                    self.sp = sp;
                                    return;
                                }
                                sp_obj.clearUnset(sp_prop_name);
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
                                self.stackRelease(self.stack[sp]);
                                self.stackRelease(self.stack[sp - 1]);
                                VM.stackRetain(copied);
                                self.stack[sp - 1] = copied;
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
                    const mc_obj_val = self.stack[sp - mc_ac - 1];
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
                            if (mc_func.locals_only and self.captures.items.len == 0) {
                                if (mc_func.has_param_types) {
                                    self.sp = sp;
                                    if (try self.checkParamTypes(mc_func.name, mc_arg_count)) {
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
                                @memset(mc_locals, .null);
                                ic.locals_sp = mc_lbase + mc_lc;
                                mc_locals[0] = .{ .object = mc_obj };
                                for (0..@min(mc_ac, mc_func.arity)) |i| {
                                    mc_locals[i + 1] = self.stack[sp - mc_ac + i];
                                }
                                for (@min(mc_ac, mc_func.arity)..mc_func.arity) |i| {
                                    if (i < mc_func.defaults.len) mc_locals[i + 1] = try self.resolveDefault(mc_func.defaults[i]);
                                }
                                self.sp = sp;
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
                                self.retainFrameObjects(self.frame_count - 1);
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

                    if (!func.locals_only or self.captures.items.len > 0) {
                        frame.ip = ip - 4;
                        self.sp = sp;
                        return;
                    }

                    if (func.has_param_types) {
                        self.sp = sp;
                        if (try self.checkParamTypes(name, arg_count)) {
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
                    @memset(new_locals, .null);
                    ic.locals_sp = lbase + lc;

                    const bind_count = @min(ac, func.arity);
                    for (0..bind_count) |i| {
                        new_locals[i] = self.stack[sp - ac + i];
                    }
                    for (bind_count..func.arity) |i| {
                        if (i < func.defaults.len) new_locals[i] = try self.resolveDefault(func.defaults[i]);
                    }
                    self.sp = sp;
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
                    };
                    ic.arg_counts[self.frame_count] = arg_count;
                    self.frame_count += 1;
                    self.retainFrameObjects(self.frame_count - 1);
                    if (self.frame_count > self.frame_high_water) self.frame_high_water = self.frame_count;
                    continue :reenter;
                },
                .return_val => {
                    const result = self.stack[sp - 1];
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
                    if (frame.vars.count() > 0 or frame.ref_slots.count() > 0 or ret_bail) {
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

                    if (self.frame_count < entry_fc) {
                        self.stack[sp - 1] = result;
                        self.sp = sp;
                        if (ret_string_pin) |s| s.release();
                        if (ret_arr_pin) |a| VM.arrayUnpin(a);
                        return;
                    }

                    sp = ic.sp_save[self.frame_count - 1];
                    self.stack[sp] = result;
                    sp += 1;
                    self.sp = sp;
                    if (ret_string_pin) |s| s.release();
                    if (ret_arr_pin) |a| VM.arrayUnpin(a);
                    continue :reenter;
                },
                .return_void => {
                    if (frame.vars.count() > 0 or frame.ref_slots.count() > 0) {
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

                    if (self.frame_count < entry_fc) {
                        self.stack[sp] = .null;
                        self.sp = sp + 1;
                        return;
                    }

                    sp = ic.sp_save[self.frame_count - 1];
                    self.stack[sp] = .null;
                    sp += 1;
                    self.sp = sp;
                    continue :reenter;
                },
                .inc_local => {
                    const slot = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    ip += 2;
                    const v = locals[slot];
                    if (v == .int) {
                        const r = @addWithOverflow(v.int, @as(i64, 1));
                        if (r[1] != 0) {
                            frame.ip = ip - 3;
                            self.sp = sp;
                            return;
                        }
                        locals[slot] = .{ .int = r[0] };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else if (v == .float) {
                        locals[slot] = .{ .float = v.float + 1.0 };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else {
                        frame.ip = ip - 3;
                        self.sp = sp;
                        return;
                    }
                },
                .dec_local => {
                    const slot = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    ip += 2;
                    const v = locals[slot];
                    if (v == .int) {
                        const r = @subWithOverflow(v.int, @as(i64, 1));
                        if (r[1] != 0) {
                            frame.ip = ip - 3;
                            self.sp = sp;
                            return;
                        }
                        locals[slot] = .{ .int = r[0] };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else if (v == .float) {
                        locals[slot] = .{ .float = v.float - 1.0 };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else {
                        frame.ip = ip - 3;
                        self.sp = sp;
                        return;
                    }
                },
                .add_local_to_local => {
                    const src_slot = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    const dst_slot = (@as(u16, code[ip + 2]) << 8) | code[ip + 3];
                    ip += 4;
                    const src = locals[src_slot];
                    const dst = locals[dst_slot];
                    if (src == .int and dst == .int) {
                        const r = @addWithOverflow(dst.int, src.int);
                        if (r[1] != 0) {
                            frame.ip = ip - 5;
                            self.sp = sp;
                            return;
                        }
                        locals[dst_slot] = .{ .int = r[0] };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else if (src == .float and dst == .float) {
                        locals[dst_slot] = .{ .float = dst.float + src.float };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else if (src == .int and dst == .float) {
                        locals[dst_slot] = .{ .float = dst.float + @as(f64, @floatFromInt(src.int)) };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else if (src == .float and dst == .int) {
                        locals[dst_slot] = .{ .float = @as(f64, @floatFromInt(dst.int)) + src.float };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else {
                        frame.ip = ip - 5;
                        self.sp = sp;
                        return;
                    }
                },
                .sub_local_to_local => {
                    const src_slot = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    const dst_slot = (@as(u16, code[ip + 2]) << 8) | code[ip + 3];
                    ip += 4;
                    const src = locals[src_slot];
                    const dst = locals[dst_slot];
                    if (src == .int and dst == .int) {
                        const r = @subWithOverflow(dst.int, src.int);
                        if (r[1] != 0) {
                            frame.ip = ip - 5;
                            self.sp = sp;
                            return;
                        }
                        locals[dst_slot] = .{ .int = r[0] };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else if (src == .float and dst == .float) {
                        locals[dst_slot] = .{ .float = dst.float - src.float };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else {
                        frame.ip = ip - 5;
                        self.sp = sp;
                        return;
                    }
                },
                .mul_local_to_local => {
                    const src_slot = (@as(u16, code[ip]) << 8) | code[ip + 1];
                    const dst_slot = (@as(u16, code[ip + 2]) << 8) | code[ip + 3];
                    ip += 4;
                    const src = locals[src_slot];
                    const dst = locals[dst_slot];
                    if (src == .int and dst == .int) {
                        const r = @mulWithOverflow(dst.int, src.int);
                        if (r[1] != 0) {
                            frame.ip = ip - 5;
                            self.sp = sp;
                            return;
                        }
                        locals[dst_slot] = .{ .int = r[0] };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else if (src == .float and dst == .float) {
                        locals[dst_slot] = .{ .float = dst.float * src.float };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else if (src == .float and dst == .int) {
                        locals[dst_slot] = .{ .float = @as(f64, @floatFromInt(dst.int)) * src.float };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else if (src == .int and dst == .float) {
                        locals[dst_slot] = .{ .float = dst.float * @as(f64, @floatFromInt(src.int)) };
                        const _next = code[ip];
                        ip += 1;
                        continue :dispatch @as(OpCode, @enumFromInt(_next));
                    } else {
                        frame.ip = ip - 5;
                        self.sp = sp;
                        return;
                    }
                },
                .less_local_local_jif => {
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
                    const b = self.stack[sp - 1];
                    const a = self.stack[sp - 2];
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
                        self.stack[sp - 1] = .{ .string = result };
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
                        self.stack[sp - 1] = .{ .string = result };
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
                        self.stack[sp - 1] = .{ .string = result };
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

fn inlineNativeCall(self: *VM, name: []const u8, arg_count: u8, sp: *usize) bool {
    const ac: usize = arg_count;
    if (name.len == 6 and std.mem.eql(u8, name, "substr")) {
        if (ac < 2 or ac > 3) return false;
        const s_val = self.stack[sp.* - ac];
        if (s_val != .string) return false;
        const string = s_val.string;
        const s = string.bytes();
        const slen: i64 = @intCast(s.len);
        var start = Value.toInt(self.stack[sp.* - ac + 1]);
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
        const offset: usize = if (ac >= 3) @intCast(@max(0, Value.toInt(self.stack[sp.* - ac + 2]))) else 0;
        if (offset >= hay.string.len) {
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
        if (ac < 2) return false;
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
