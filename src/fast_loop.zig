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
                const slot = (@as(u16, code[ip]) << 8) | code[ip + 1];
                ip += 2;
                self.stack[sp] = locals[slot];
                sp += 1;
                const _next = code[ip];
                ip += 1;
                continue :dispatch @as(OpCode, @enumFromInt(_next));
            },
            .set_local => {
                const slot = (@as(u16, code[ip]) << 8) | code[ip + 1];
                ip += 2;
                const val = self.stack[sp - 1];
                if (val == .array) {
                    locals[slot] = try self.copyValue(val);
                } else {
                    locals[slot] = val;
                }
                if (code[ip] == @intFromEnum(OpCode.pop)) {
                    ip += 1;
                    sp -= 1;
                }
                const _next = code[ip];
                ip += 1;
                continue :dispatch @as(OpCode, @enumFromInt(_next));
            },
            .add => {
                const b = self.stack[sp - 1];
                const a = self.stack[sp - 2];
                sp -= 2;
                self.stack[sp] = if (a == .int and b == .int) Value.intAdd(a.int, b.int) else if (a == .float and b == .float) .{ .float = a.float + b.float } else Value.add(a, b);
                sp += 1;
                const _next = code[ip];
                ip += 1;
                continue :dispatch @as(OpCode, @enumFromInt(_next));
            },
            .subtract => {
                const b = self.stack[sp - 1];
                const a = self.stack[sp - 2];
                sp -= 2;
                self.stack[sp] = if (a == .int and b == .int) Value.intSub(a.int, b.int) else if (a == .float and b == .float) .{ .float = a.float - b.float } else Value.subtract(a, b);
                sp += 1;
                const _next = code[ip];
                ip += 1;
                continue :dispatch @as(OpCode, @enumFromInt(_next));
            },
            .multiply => {
                const b = self.stack[sp - 1];
                const a = self.stack[sp - 2];
                sp -= 2;
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
                self.stack[sp] = .{ .bool = if (a == .int and b == .int) a.int > b.int else Value.lessThan(b, a) };
                sp += 1;
                const _next = code[ip];
                ip += 1;
                continue :dispatch @as(OpCode, @enumFromInt(_next));
            },
            .identical => {
                const b_id = self.stack[sp - 1];
                const a_id = self.stack[sp - 2];
                sp -= 2;
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
                self.stack[sp] = .{ .bool = !Value.identical(a_ni, b_ni) };
                sp += 1;
                const _next = code[ip];
                ip += 1;
                continue :dispatch @as(OpCode, @enumFromInt(_next));
            },
            .modulo => {
                const b_mod = self.stack[sp - 1];
                const a_mod = self.stack[sp - 2];
                sp -= 2;
                self.stack[sp] = Value.modulo(a_mod, b_mod);
                sp += 1;
                const _next = code[ip];
                ip += 1;
                continue :dispatch @as(OpCode, @enumFromInt(_next));
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
                const _next = code[ip];
                ip += 1;
                continue :dispatch @as(OpCode, @enumFromInt(_next));
            },
            .dup => {
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
                self.stack[sp - 1] = .{ .int = Value.toInt(v) };
                const _next = code[ip];
                ip += 1;
                continue :dispatch @as(OpCode, @enumFromInt(_next));
            },
            .array_get => {
                const ag_key = self.stack[sp - 1];
                const ag_arr = self.stack[sp - 2];
                sp -= 2;
                if (ag_arr == .array) {
                    self.stack[sp] = ag_arr.array.get(Value.toArrayKey(ag_key));
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
                const ci_name = ci_name_val.string;
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
                const ci_lc: usize = ci_func.local_count;
                const ci_lbase = ic.locals_sp;
                if (ci_lbase + ci_lc > ic.locals_cap) {
                    frame.ip = ip - 2;
                    self.sp = sp;
                    return;
                }
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
                sp -= ci_acn;
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
                    .vars = .{},
                    .locals = ci_locals,
                    .func = ci_func,
                };
                self.frame_count += 1;
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
                            self.stack[sp - 1] = s[gp_entry.slot_index];
                            const _next_gp = code[ip];
                            ip += 1;
                            continue :dispatch @as(OpCode, @enumFromInt(_next_gp));
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
                    if (sp_entry.key == sp_ip and sp_entry.chunk_key == @intFromPtr(frame.chunk) and sp_entry.class_ptr == @intFromPtr(sp_obj.class_name.ptr) and sp_entry.slot_index != 0xFFFF) {
                        if (sp_obj.slots) |s| {
                            const copied = if (sp_val == .array) try self.copyValue(sp_val) else sp_val;
                            s[sp_entry.slot_index] = copied;
                            sp -= 1;
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
                const mc_idx = InlineCache.methodIndex(@intFromPtr(frame.chunk), mc_ip);
                const mc_entry = &ic.method[mc_idx];
                if (mc_entry.key == mc_ip and mc_entry.class_ptr == @intFromPtr(mc_obj.class_name.ptr)) {
                    if (mc_entry.func) |mc_func| {
                        if (mc_func.locals_only and self.captures.items.len == 0) {
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
                            sp -= mc_ac + 1;
                            frame.ip = ip;
                            ic.sp_save[self.frame_count - 1] = sp;
                            self.sp = sp;
                            self.frames[self.frame_count] = .{
                                .chunk = &mc_func.chunk,
                                .ip = 0,
                                .vars = .{},
                                .locals = mc_locals,
                                .func = mc_func,
                            };
                            self.frame_count += 1;
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

                const name = consts[name_idx].string;
                const func = blk: {
                    if (ic.fn_cache_name.len == name.len and std.mem.eql(u8, ic.fn_cache_name, name))
                        break :blk ic.fn_cache_func.?;
                    if (self.functions.get(name)) |f| {
                        ic.fn_cache_name = name;
                        ic.fn_cache_func = f;
                        break :blk f;
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
                sp -= ac;

                frame.ip = ip;
                ic.sp_save[self.frame_count - 1] = sp;
                self.sp = sp;

                self.frames[self.frame_count] = .{
                    .chunk = &func.chunk,
                    .ip = 0,
                    .vars = .{},
                    .locals = new_locals,
                    .func = func,
                };
                self.frame_count += 1;
                continue :reenter;
            },
            .return_val => {
                const result = self.stack[sp - 1];
                if (frame.vars.count() > 0 or frame.ref_slots.count() > 0) {
                    frame.ip = ip - 1;
                    self.sp = sp;
                    return;
                }
                if (locals.len > 0) self.freeLocals(locals);
                self.frame_count -= 1;

                if (self.frame_count < entry_fc) {
                    self.stack[sp - 1] = result;
                    self.sp = sp;
                    return;
                }

                sp = ic.sp_save[self.frame_count - 1];
                self.stack[sp] = result;
                sp += 1;
                self.sp = sp;
                continue :reenter;
            },
            .return_void => {
                if (frame.vars.count() > 0 or frame.ref_slots.count() > 0) {
                    frame.ip = ip - 1;
                    self.sp = sp;
                    return;
                }
                if (locals.len > 0) self.freeLocals(locals);
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
                    if (r[1] != 0) { frame.ip = ip - 3; self.sp = sp; return; }
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
                    if (r[1] != 0) { frame.ip = ip - 3; self.sp = sp; return; }
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
                    if (r[1] != 0) { frame.ip = ip - 5; self.sp = sp; return; }
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
                    if (r[1] != 0) { frame.ip = ip - 5; self.sp = sp; return; }
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
                    if (r[1] != 0) { frame.ip = ip - 5; self.sp = sp; return; }
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
                    const as = a.string;
                    const bs = b.string;
                    const owned = try self.allocator.alloc(u8, as.len + bs.len);
                    @memcpy(owned[0..as.len], as);
                    @memcpy(owned[as.len..], bs);
                    try self.strings.append(self.allocator, owned);
                    sp -= 1;
                    self.stack[sp - 1] = .{ .string = owned };
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
                    const owned = try self.allocator.alloc(u8, a.string.len + bs.len);
                    @memcpy(owned[0..a.string.len], a.string);
                    @memcpy(owned[a.string.len..], bs);
                    try self.strings.append(self.allocator, owned);
                    sp -= 1;
                    self.stack[sp - 1] = .{ .string = owned };
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
                    const owned = try self.allocator.alloc(u8, as.len + b.string.len);
                    @memcpy(owned[0..as.len], as);
                    @memcpy(owned[as.len..], b.string);
                    try self.strings.append(self.allocator, owned);
                    sp -= 1;
                    self.stack[sp - 1] = .{ .string = owned };
                    const _next = code[ip];
                    ip += 1;
                    continue :dispatch @as(OpCode, @enumFromInt(_next));
                } else {
                    frame.ip = ip - 1;
                    self.sp = sp;
                    return;
                }
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
