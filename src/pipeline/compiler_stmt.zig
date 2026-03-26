const std = @import("std");
const Compiler = @import("compiler.zig").Compiler;
const Ast = @import("ast.zig").Ast;
const Token = @import("token.zig").Token;
const Value = @import("../runtime/value.zig").Value;
const Allocator = std.mem.Allocator;
const Error = Allocator.Error || error{CompileError};

pub fn compileIfSimple(self: *Compiler, node: Ast.Node) Error!void {
    try self.compileNode(node.data.lhs);
    const then_jump = try self.emitJump(.jump_if_false);
    try self.emitOp(.pop);
    try self.compileNode(node.data.rhs);
    const end_jump = try self.emitJump(.jump);
    self.patchJump(then_jump);
    try self.emitOp(.pop);
    self.patchJump(end_jump);
}

pub fn compileIfElse(self: *Compiler, node: Ast.Node) Error!void {
    const then_node = self.ast.extra_data[node.data.rhs];
    const else_node = self.ast.extra_data[node.data.rhs + 1];

    try self.compileNode(node.data.lhs);
    const then_jump = try self.emitJump(.jump_if_false);
    try self.emitOp(.pop);
    try self.compileNode(then_node);
    const else_jump = try self.emitJump(.jump);
    self.patchJump(then_jump);
    try self.emitOp(.pop);
    try self.compileNode(else_node);
    self.patchJump(else_jump);
}

pub fn compileWhile(self: *Compiler, node: Ast.Node) Error!void {
    const prev_start = self.loop_start;
    var prev_breaks = self.break_jumps;
    var prev_continues = self.continue_jumps;
    self.break_jumps = .{};
    self.continue_jumps = .{};
    self.loop_depth += 1;

    const loop_top = self.chunk.offset();
    self.loop_start = loop_top;

    try self.compileNode(node.data.lhs);
    const exit_jump = try self.emitJump(.jump_if_false);
    try self.emitOp(.pop);
    try self.compileNode(node.data.rhs);
    try self.emitLoop(loop_top);
    self.patchJump(exit_jump);
    try self.emitOp(.pop);

    try self.patchBreaks(&prev_breaks);
    try self.patchContinues(&prev_continues);
    self.break_jumps = prev_breaks;
    self.continue_jumps = prev_continues;
    self.loop_depth -= 1;
    self.loop_start = prev_start;
}

pub fn compileDoWhile(self: *Compiler, node: Ast.Node) Error!void {
    const prev_start = self.loop_start;
    var prev_breaks = self.break_jumps;
    var prev_continues = self.continue_jumps;
    self.break_jumps = .{};
    self.continue_jumps = .{};
    self.loop_depth += 1;

    const loop_top = self.chunk.offset();
    self.loop_start = loop_top;

    try self.compileNode(node.data.lhs);
    try self.compileNode(node.data.rhs);
    const exit_jump = try self.emitJump(.jump_if_false);
    try self.emitOp(.pop);
    try self.emitLoop(loop_top);
    self.patchJump(exit_jump);
    try self.emitOp(.pop);

    try self.patchBreaks(&prev_breaks);
    try self.patchContinues(&prev_continues);
    self.break_jumps = prev_breaks;
    self.continue_jumps = prev_continues;
    self.loop_depth -= 1;
    self.loop_start = prev_start;
}

pub fn compileFor(self: *Compiler, node: Ast.Node) Error!void {
    const init_n = self.ast.extra_data[node.data.lhs];
    const cond_n = self.ast.extra_data[node.data.lhs + 1];
    const update_n = self.ast.extra_data[node.data.lhs + 2];

    const prev_start = self.loop_start;
    var prev_breaks = self.break_jumps;
    var prev_continues = self.continue_jumps;
    const prev_use_cj = self.use_continue_jumps;
    self.break_jumps = .{};
    self.continue_jumps = .{};
    self.use_continue_jumps = (update_n != 0);
    self.loop_depth += 1;

    if (init_n != 0) {
        try self.compileNode(init_n);
        try self.emitOp(.pop);
    }

    const loop_top = self.chunk.offset();
    self.loop_start = loop_top;

    var exit_jump: ?usize = null;
    if (cond_n != 0) {
        try self.compileNode(cond_n);
        exit_jump = try self.emitJump(.jump_if_false);
        try self.emitOp(.pop);
    }

    try self.compileNode(node.data.rhs);

    // continue lands here - patch continue forward jumps for this depth
    try self.patchContinues(&prev_continues);

    if (update_n != 0) {
        try self.compileNode(update_n);
        try self.emitOp(.pop);
    }

    try self.emitLoop(loop_top);

    if (exit_jump) |ej| {
        self.patchJump(ej);
        try self.emitOp(.pop);
    }

    try self.patchBreaks(&prev_breaks);
    self.break_jumps = prev_breaks;
    self.continue_jumps = prev_continues;
    self.use_continue_jumps = prev_use_cj;
    self.loop_depth -= 1;
    self.loop_start = prev_start;
}

pub fn compileForeach(self: *Compiler, node: Ast.Node) Error!void {
    const iter_n = self.ast.extra_data[node.data.lhs];
    const val_n = self.ast.extra_data[node.data.lhs + 1];
    const key_n = self.ast.extra_data[node.data.lhs + 2];
    const val_by_ref = self.ast.extra_data[node.data.lhs + 3] != 0;

    const prev_start = self.loop_start;
    var prev_breaks = self.break_jumps;
    var prev_continues = self.continue_jumps;
    const prev_use_cj = self.use_continue_jumps;
    self.break_jumps = .{};
    self.continue_jumps = .{};
    self.use_continue_jumps = true;
    self.loop_depth += 1;
    self.foreach_depth += 1;

    try self.compileNode(iter_n);
    try self.emitOp(.iter_begin);

    const loop_top = self.chunk.offset();
    self.loop_start = loop_top;

    const exit_jump = try self.emitJump(.iter_check);

    // iter_check pushed: key, value (value on top)
    var ref_key_name: ?[]const u8 = null;
    var ref_val_name: ?[]const u8 = null;

    const val_node = self.ast.nodes[val_n];
    if (val_node.tag == .array_literal or val_node.tag == .list_destructure) {
        try self.compileDestructure(val_node);
        try self.emitOp(.pop);
    } else {
        const val_name = self.ast.tokenSlice(val_node.main_token);
        try self.emitSetVar(val_name);
        try self.emitOp(.pop);
        if (val_by_ref) ref_val_name = val_name;
    }

    if (key_n != 0) {
        const key_name = self.ast.tokenSlice(self.ast.nodes[key_n].main_token);
        try self.emitSetVar(key_name);
        try self.emitOp(.pop);
        if (val_by_ref) ref_key_name = key_name;
    } else {
        if (val_by_ref) {
            const synth_name = "__foreach_key";
            try self.emitSetVar(synth_name);
            try self.emitOp(.pop);
            ref_key_name = synth_name;
        } else {
            try self.emitOp(.pop);
        }
    }

    try self.compileNode(node.data.rhs);

    // continue lands here, before iter_advance (same pattern as for loop update)
    try self.patchContinues(&prev_continues);

    // by-ref writeback: $arr[$key] = $val
    if (ref_val_name) |vn| {
        if (ref_key_name) |kn| {
            try self.compileNode(iter_n);
            try self.emitGetVar(kn);
            try self.emitGetVar(vn);
            try self.emitOp(.array_set);
            try self.emitOp(.pop);
        }
    }

    try self.emitOp(.iter_advance);
    try self.emitLoop(loop_top);

    self.patchJump(exit_jump);
    try self.emitOp(.iter_end);

    try self.patchBreaks(&prev_breaks);
    self.break_jumps = prev_breaks;
    self.continue_jumps = prev_continues;
    self.use_continue_jumps = prev_use_cj;
    self.loop_depth -= 1;
    self.foreach_depth -= 1;
    self.loop_start = prev_start;
}

pub fn compileSwitch(self: *Compiler, node: Ast.Node) Error!void {
    const prev_start = self.loop_start;
    const prev_breaks = self.break_jumps;
    self.break_jumps = .{};
    self.loop_start = null;

    try self.compileNode(node.data.lhs);
    const temp_name = try std.fmt.allocPrint(self.allocator, "__switch_{d}", .{self.closure_count});
    try self.string_allocs.append(self.allocator, temp_name);
    self.closure_count += 1;
    try self.emitSetVar(temp_name);
    try self.emitOp(.pop);

    const case_nodes = self.ast.extraSlice(node.data.rhs);

    // phase 1: emit comparison chain, collect jumps to bodies
    var body_jumps = std.ArrayListUnmanaged(usize){};
    defer body_jumps.deinit(self.allocator);
    var default_jump: ?usize = null;

    for (case_nodes) |case_idx| {
        const case_node = self.ast.nodes[case_idx];
        if (case_node.tag == .switch_default) {
            try body_jumps.append(self.allocator, 0);
            continue;
        }

        const values = self.ast.extraSlice(case_node.data.lhs);
        var hit_jumps = std.ArrayListUnmanaged(usize){};
        defer hit_jumps.deinit(self.allocator);

        for (values, 0..) |val, vi| {
            try self.emitGetVar(temp_name);
            try self.compileNode(val);
            try self.emitOp(.equal);
            if (vi < values.len - 1) {
                const hit = try self.emitJump(.jump_if_true);
                try hit_jumps.append(self.allocator, hit);
                try self.emitOp(.pop);
            } else {
                const skip = try self.emitJump(.jump_if_false);
                // matched: patch all hit_jumps to here
                for (hit_jumps.items) |hj| self.patchJump(hj);
                try self.emitOp(.pop);
                const body_jmp = try self.emitJump(.jump);
                try body_jumps.append(self.allocator, body_jmp);
                self.patchJump(skip);
                try self.emitOp(.pop);
            }
        }
    }

    // jump to default or past all bodies
    for (case_nodes, 0..) |case_idx, i| {
        if (self.ast.nodes[case_idx].tag == .switch_default) {
            default_jump = try self.emitJump(.jump);
            body_jumps.items[i] = default_jump.?;
            break;
        }
    }
    const end_no_match = if (default_jump == null) try self.emitJump(.jump) else null;

    // phase 2: emit bodies sequentially (enables fallthrough)
    for (case_nodes, 0..) |case_idx, i| {
        const case_node = self.ast.nodes[case_idx];
        self.patchJump(body_jumps.items[i]);

        const stmts = if (case_node.tag == .switch_default)
            self.ast.extraSlice(case_node.data.lhs)
        else
            self.ast.extraSlice(case_node.data.rhs);

        for (stmts) |stmt| try self.compileNode(stmt);
    }

    if (end_no_match) |j| self.patchJump(j);
    for (self.break_jumps.items) |bj| self.patchJump(bj.offset);
    self.break_jumps.deinit(self.allocator);
    self.break_jumps = prev_breaks;
    self.loop_start = prev_start;
}

pub fn compileMatch(self: *Compiler, node: Ast.Node) Error!void {
    try self.compileNode(node.data.lhs);
    const temp_name = try std.fmt.allocPrint(self.allocator, "__match_{d}", .{self.closure_count});
    try self.string_allocs.append(self.allocator, temp_name);
    self.closure_count += 1;
    try self.emitSetVar(temp_name);
    try self.emitOp(.pop);

    const arm_nodes = self.ast.extraSlice(node.data.rhs);
    var end_jumps = std.ArrayListUnmanaged(usize){};
    defer end_jumps.deinit(self.allocator);
    var default_arm: ?u32 = null;

    for (arm_nodes) |arm_idx| {
        const arm = self.ast.nodes[arm_idx];
        const values = self.ast.extraSlice(arm.data.lhs);

        if (values.len == 0) {
            default_arm = arm_idx;
            continue;
        }

        var hit_jumps = std.ArrayListUnmanaged(usize){};
        defer hit_jumps.deinit(self.allocator);

        for (values, 0..) |val, vi| {
            try self.emitGetVar(temp_name);
            try self.compileNode(val);
            try self.emitOp(.identical);
            if (vi < values.len - 1) {
                const hit = try self.emitJump(.jump_if_true);
                try hit_jumps.append(self.allocator, hit);
                try self.emitOp(.pop);
            } else {
                const skip = try self.emitJump(.jump_if_false);
                for (hit_jumps.items) |hj| self.patchJump(hj);
                try self.emitOp(.pop);
                try self.compileNode(arm.data.rhs);
                const end_j = try self.emitJump(.jump);
                try end_jumps.append(self.allocator, end_j);
                self.patchJump(skip);
                try self.emitOp(.pop);
            }
        }
    }

    if (default_arm) |da| {
        try self.compileNode(self.ast.nodes[da].data.rhs);
    } else {
        // no default: throw UnhandledMatchError
        const cls_idx = try self.addConstant(.{ .string = "UnhandledMatchError" });
        const msg_idx = try self.addConstant(.{ .string = "Unhandled match case" });
        try self.emitConstant(msg_idx);
        try self.emitOp(.new_obj);
        try self.emitU16(cls_idx);
        try self.emitByte(1);
        try self.emitOp(.throw);
    }

    for (end_jumps.items) |ej| self.patchJump(ej);
}

pub fn compileThrow(self: *Compiler, node: Ast.Node) Error!void {
    try self.compileNode(node.data.lhs);
    try self.emitOp(.throw);
}

pub fn compileTryCatch(self: *Compiler, node: Ast.Node) Error!void {
    const catch_count = self.ast.extra_data[node.data.rhs];
    const catch_nodes = self.ast.extra_data[node.data.rhs + 1 .. node.data.rhs + 1 + catch_count];
    const finally_node = self.ast.extra_data[node.data.rhs + 1 + catch_count];

    // emit push_handler with placeholder catch offset
    try self.emitOp(.push_handler);
    const handler_offset_pos = self.chunk.offset();
    try self.emitU16(0xffff);

    // compile try body
    try self.compileNode(node.data.lhs);

    // normal exit: pop handler and jump past catches
    try self.emitOp(.pop_handler);
    const skip_catches = try self.emitJump(.jump);

    // patch catch offset to here
    self.patchJump(handler_offset_pos);

    // exception is on the stack when we arrive here
    var end_jumps = std.ArrayListUnmanaged(usize){};
    defer end_jumps.deinit(self.allocator);

    for (catch_nodes) |catch_idx| {
        const catch_node = self.ast.nodes[catch_idx];
        const types_extra = catch_node.data.lhs;
        const body_idx = catch_node.data.rhs;

        const type_count = self.ast.extra_data[types_extra];

        if (type_count > 0) {
            const type_nodes = self.ast.extra_data[types_extra + 1 .. types_extra + 1 + type_count];

            // for each type: dup exc, check instanceof, if true jump to match
            var match_jumps = std.ArrayListUnmanaged(usize){};
            defer match_jumps.deinit(self.allocator);

            for (type_nodes) |tn| {
                try self.emitOp(.dup); // [exc, exc]
                const type_name = self.ast.tokenSlice(self.ast.nodes[tn].main_token);
                const tidx = try self.addConstant(.{ .string = type_name });
                try self.emitConstant(tidx); // [exc, exc, type]
                try self.emitOp(.instance_check); // [exc, bool]
                const mj = try self.emitJump(.jump_if_true); // peek bool
                try match_jumps.append(self.allocator, mj);
                try self.emitOp(.pop); // [exc] (remove false bool)
            }

            // none matched, stack: [exc] - skip to next catch
            const skip = try self.emitJump(.jump);

            // match: stack: [exc, bool(true)]
            for (match_jumps.items) |mj| self.patchJump(mj);
            try self.emitOp(.pop); // remove bool -> [exc]

            if (catch_node.main_token != 0) {
                const var_name = self.ast.tokenSlice(catch_node.main_token);
                try self.emitSetVar(var_name);
            }
            try self.emitOp(.pop); // remove exc

            try self.compileNode(body_idx);
            const ej = try self.emitJump(.jump);
            try end_jumps.append(self.allocator, ej);

            // skip lands here, stack: [exc] (preserved for next catch)
            self.patchJump(skip);
        } else {
            // untyped catch-all
            if (catch_node.main_token != 0) {
                const var_name = self.ast.tokenSlice(catch_node.main_token);
                try self.emitSetVar(var_name);
            }
            try self.emitOp(.pop);

            try self.compileNode(body_idx);
            const ej = try self.emitJump(.jump);
            try end_jumps.append(self.allocator, ej);
        }
    }

    // if no catch matched, re-throw
    try self.emitOp(.throw);

    self.patchJump(skip_catches);
    for (end_jumps.items) |ej| self.patchJump(ej);

    // finally block runs on both paths
    if (finally_node != 0) {
        try self.compileNode(finally_node);
    }
}

pub fn compileGlobal(self: *Compiler, node: Ast.Node) Error!void {
    for (self.ast.extraSlice(node.data.lhs)) |var_idx| {
        const var_node = self.ast.nodes[var_idx];
        const name = self.ast.tokenSlice(var_node.main_token);
        const name_idx = try self.addConstant(.{ .string = name });
        try self.emitOp(.get_global);
        try self.emitU16(name_idx);
    }
}

pub fn compileStaticVar(self: *Compiler, node: Ast.Node) Error!void {
    const var_name = self.ast.tokenSlice(node.main_token);
    const var_idx = try self.addConstant(.{ .string = var_name });

    // get_static pushes the current value (or null if uninitialized)
    // VM derives the storage key from current function name + var name
    try self.emitOp(.get_static);
    try self.emitU16(var_idx);

    // if null (first call), initialize with default
    if (node.data.lhs != 0) {
        const skip = try self.emitJump(.jump_if_not_null);
        try self.emitOp(.pop);
        try self.compileNode(node.data.lhs);
        self.patchJump(skip);
    }

    try self.emitOp(.set_var);
    try self.emitU16(var_idx);
}

pub fn compileNamespace(self: *Compiler, node: Ast.Node) Error!void {
    // reconstruct namespace name from token indices
    const parts = self.ast.extraSlice(node.data.lhs);
    self.namespace = try self.buildQualifiedString(parts);
}

pub fn compileUse(self: *Compiler, node: Ast.Node) Error!void {
    const parts = self.ast.extraSlice(node.data.lhs);
    const fqn = try self.buildQualifiedString(parts);

    // alias is either explicit (use Foo\Bar as Baz;) or last part of the name
    const alias = if (node.data.rhs != 0)
        self.ast.tokenSlice(node.data.rhs)
    else
        self.ast.tokenSlice(parts[parts.len - 1]);

    try self.use_aliases.put(self.allocator, alias, fqn);
}

pub fn compileRequire(self: *Compiler, node: Ast.Node) Error!void {
    try self.compileNode(node.data.lhs);
    const tok_tag = self.ast.tokens[node.main_token].tag;
    const variant: u8 = switch (tok_tag) {
        .kw_require => 0,
        .kw_require_once => 1,
        .kw_include => 2,
        .kw_include_once => 3,
        else => 0,
    };
    try self.emitOp(.require);
    try self.emitByte(variant);
}
