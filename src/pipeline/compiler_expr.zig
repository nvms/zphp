const std = @import("std");
const Compiler = @import("compiler.zig").Compiler;
const Ast = @import("ast.zig").Ast;
const Token = @import("token.zig").Token;
const Value = @import("../runtime/value.zig").Value;
const OpCode = @import("bytecode.zig").OpCode;
const Allocator = std.mem.Allocator;
const Error = Allocator.Error || error{CompileError};

pub fn compileAssign(self: *Compiler, node: Ast.Node) Error!void {
    const target = self.ast.nodes[node.data.lhs];
    const op_tag = self.ast.tokens[node.main_token].tag;

    // `$dst = &…` — emit break_var_ref so the subsequent value-write doesn't
    // propagate through a stale prior ref binding on dst. true ref binding
    // (make_var_ref, make_var_array_elem_ref) is defined in the runtime but
    // not emitted from the compiler yet — enabling it makes correct PHP
    // semantics for `$b = &$a` but exposes a downstream zphp bug where
    // Laravel's Route registration loses the /api prefix on POST routes
    // (the Arr::except → Arr::forget chain run during Route::__construct
    // triggers the divergence). break_var_ref alone preserves today's
    // baseline. see roadmap item #1 for the next push
    // gated: enabling make_var_ref emission below correctly implements
    // PHP's `$b = &$a` aliasing in isolation, but during Laravel's route
    // registration the cumulative effect causes $this->groupStack[last] to
    // lose its 'prefix' key between Router::mergeWithLastGroup invocations.
    // bisected to: somewhere inside RouteGroup::merge → Arr::except → forget,
    // $old (which should be a callLocalsOnly clone of array_last result) gets
    // mutated AND the mutation propagates to $groupStack[last]. callLocalsOnly
    // calls copyValue, which calls cloneArrayInner, which deep-clones nested
    // arrays. yet the source array gets mutated. either there's a clone path
    // that returns the original pointer, or there's a fast_loop path that
    // skips the copy. tracking down requires deeper instrumentation of the
    // call site that produces merge's $old
    if (op_tag == .equal and (target.tag == .variable or target.tag == .identifier)) {
        const rhs_node = self.ast.nodes[node.data.rhs];
        if (rhs_node.tag == .ref_target) {
            const dst_name = self.ast.tokenSlice(target.main_token);
            const dst_idx = try self.addConstant(.{ .string = dst_name });
            const inner = self.ast.nodes[rhs_node.data.lhs];
            // when emitting make_var_ref / make_var_array_elem_ref, do NOT
            // emit break_var_ref first - those opcodes replace dst's ref_slot
            // atomically, and a prior break_var_ref would drop the slot before
            // we push the rhs, causing the rhs's get_var to fall back to stale
            // frame.vars
            if (inner.tag == .variable or inner.tag == .identifier) {
                const src_name = self.ast.tokenSlice(inner.main_token);
                const src_idx = try self.addConstant(.{ .string = src_name });
                try self.emitOp(.make_var_ref);
                try self.emitU16(dst_idx);
                try self.emitU16(src_idx);
                try self.compileNode(rhs_node.data.lhs);
                return;
            }
            if (inner.tag == .array_access) {
                try self.compileNode(inner.data.lhs); // push array (must read via current ref_slot)
                try self.compileNode(inner.data.rhs); // push key
                try self.emitOp(.make_var_array_elem_ref);
                try self.emitU16(dst_idx);
                try self.emitOp(.op_null);
                return;
            }
            if (inner.tag == .property_access and !self.isDynamicProp(inner)) {
                try self.compileNode(inner.data.lhs); // push object
                const prop_idx = try self.addConstant(.{ .string = self.propName(inner) });
                try self.emitOp(.make_var_prop_ref);
                try self.emitU16(dst_idx);
                try self.emitU16(prop_idx);
                try self.emitOp(.op_null);
                return;
            }
            // fallback for shapes we don't yet bind explicitly (dynamic property,
            // static property, chained ref-assign)
            try self.emitOp(.break_var_ref);
            try self.emitU16(dst_idx);
        }
    }

    if (target.tag == .list_destructure or (target.tag == .array_literal and op_tag == .equal)) {
        try self.compileNode(node.data.rhs);
        try self.compileDestructure(target);
        return;
    }

    if (target.tag == .array_push_target) {
        try compileVivifyChain(self,target.data.lhs);
        try self.compileNode(node.data.rhs);
        try self.emitOp(.array_push);
        return;
    }

    if (target.tag == .array_access) {
        if (op_tag == .question_question_equal) {
            // read with coalesce-safe fetch so undefined keys don't warn
            try self.compileNode(target.data.lhs);
            try self.compileNode(target.data.rhs);
            try self.emitOp(.array_get_coalesce);
            const skip_jump = try self.emitJump(.jump_if_not_null);
            try self.emitOp(.pop);
            try compileVivifyChain(self,target.data.lhs);
            try self.compileNode(target.data.rhs);
            try self.compileNode(node.data.rhs);
            try self.emitOp(.array_set);
            self.patchJump(skip_jump);
            return;
        }
        if (op_tag != .equal) {
            try compileVivifyChain(self,target.data.lhs);
            try self.compileNode(target.data.rhs);
            try compileVivifyChain(self,target.data.lhs);
            try self.compileNode(target.data.rhs);
            try self.emitOp(.array_get);
            try self.compileNode(node.data.rhs);
            try emitCompoundOp(self, op_tag);
            try self.emitOp(.array_set);
        } else {
            const target_lhs = self.ast.nodes[target.data.lhs];
            if (target_lhs.tag == .variable) {
                const var_name = self.ast.tokenSlice(target_lhs.main_token);
                var slot_opt: ?u16 = null;
                if (self.local_slots.get(var_name)) |s| {
                    slot_opt = s;
                } else if (!self.inFunctionScope() and var_name.len > 0 and var_name[0] == '$') {
                    slot_opt = self.getOrCreateSlot(var_name);
                }
                if (slot_opt) |slot| {
                    try self.compileNode(target.data.rhs);
                    try self.compileNode(node.data.rhs);
                    try self.emitOp(.array_set_local);
                    try self.emitU16(slot);
                    return;
                }
            }
            try compileVivifyChain(self,target.data.lhs);
            try self.compileNode(target.data.rhs);
            try self.compileNode(node.data.rhs);
            try self.emitOp(.array_set);
        }
        return;
    }

    if (target.tag == .property_access) {
        if (self.isDynamicProp(target)) {
            try self.compileNode(target.data.lhs);
            if (op_tag != .equal) {
                try self.emitOp(.dup);
                if (target.main_token == 0) {
                    try self.compileNode(target.data.rhs);
                } else {
                    const prop_node = self.ast.nodes[target.data.rhs];
                    try self.emitGetVar(self.ast.tokenSlice(prop_node.main_token));
                }
                try self.emitOp(.get_prop_dynamic);
            }
            try self.compileNode(node.data.rhs);
            if (op_tag != .equal) {
                try emitCompoundOp(self, op_tag);
            }
            if (target.main_token == 0) {
                try self.compileNode(target.data.rhs);
            } else {
                const prop_node = self.ast.nodes[target.data.rhs];
                try self.emitGetVar(self.ast.tokenSlice(prop_node.main_token));
            }
            try self.emitOp(.set_prop_dynamic);
            return;
        }
        const prop_node = self.ast.nodes[target.data.rhs];
        var prop_name = self.ast.tokenSlice(prop_node.main_token);
        if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
        const name_idx = try self.addConstant(.{ .string = prop_name });
        if (op_tag == .question_question_equal) {
            try self.compileNode(target.data.lhs);
            try self.emitOp(.dup);
            try self.emitOp(.get_prop);
            try self.emitU16(name_idx);
            const skip_jump = try self.emitJump(.jump_if_not_null);
            try self.emitOp(.pop);
            try self.compileNode(node.data.rhs);
            try self.emitOp(.set_prop);
            try self.emitU16(name_idx);
            const end_jump = try self.emitJump(.jump);
            self.patchJump(skip_jump);
            // not-null path: stack has [obj, prop_value], need to remove obj
            try self.emitOp(.swap);
            try self.emitOp(.pop);
            self.patchJump(end_jump);
            return;
        }
        try self.compileNode(target.data.lhs);
        if (op_tag != .equal) {
            try self.emitOp(.dup);
            try self.emitOp(.get_prop);
            try self.emitU16(name_idx);
        }
        try self.compileNode(node.data.rhs);
        if (op_tag != .equal) {
            try emitCompoundOp(self, op_tag);
        }
        try self.emitOp(.set_prop);
        try self.emitU16(name_idx);
        return;
    }

    if (target.tag == .static_prop_access) {
        const class_node = self.ast.nodes[target.data.lhs];
        const class_name = self.ast.tokenSlice(class_node.main_token);
        var prop_name = self.ast.tokenSlice(target.main_token);
        if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
        const class_idx = try self.addConstant(.{ .string = class_name });
        const prop_idx = try self.addConstant(.{ .string = prop_name });
        if (op_tag == .question_question_equal) {
            try self.emitOp(.get_static_prop);
            try self.emitU16(class_idx);
            try self.emitU16(prop_idx);
            const skip_jump = try self.emitJump(.jump_if_not_null);
            try self.emitOp(.pop);
            try self.compileNode(node.data.rhs);
            try self.emitOp(.set_static_prop);
            try self.emitU16(class_idx);
            try self.emitU16(prop_idx);
            self.patchJump(skip_jump);
            return;
        }
        if (op_tag != .equal) {
            try self.emitOp(.get_static_prop);
            try self.emitU16(class_idx);
            try self.emitU16(prop_idx);
        }
        try self.compileNode(node.data.rhs);
        if (op_tag != .equal) {
            try emitCompoundOp(self, op_tag);
        }
        try self.emitOp(.set_static_prop);
        try self.emitU16(class_idx);
        try self.emitU16(prop_idx);
        return;
    }

    if (op_tag == .question_question_equal) {
        {
            try self.compileGetVar(target);
            const skip_jump = try self.emitJump(.jump_if_not_null);
            try self.emitOp(.pop);
            try self.compileNode(node.data.rhs);
            if (target.tag == .variable or target.tag == .identifier) {
                const name = self.ast.tokenSlice(target.main_token);
                try self.emitSetVar(name);
            }
            self.patchJump(skip_jump);
        }
        return;
    }

    // fast path: $var .= expr uses concat_assign to avoid full string copy
    if (op_tag == .dot_equal and (target.tag == .variable or target.tag == .identifier)) {
        try self.compileNode(node.data.rhs);
        const name = self.ast.tokenSlice(target.main_token);
        const idx = try self.addConstant(.{ .string = name });
        try self.emitOp(.concat_assign);
        try self.emitU16(idx);
        return;
    }

    if (target.tag == .variable_variable) {
        if (op_tag != .equal) {
            try self.compileVariableVariable(target);
        }
        try self.compileNode(node.data.rhs);
        if (op_tag != .equal) {
            try emitCompoundOp(self, op_tag);
        }
        try self.compileNode(target.data.lhs);
        try self.emitOp(.set_var_var);
        return;
    }

    if (op_tag != .equal) {
        try self.compileGetVar(target);
    }

    try self.compileNode(node.data.rhs);

    if (op_tag != .equal) {
        try emitCompoundOp(self, op_tag);
    }

    if (target.tag == .variable or target.tag == .identifier) {
        const name = self.ast.tokenSlice(target.main_token);
        try self.emitSetVar(name);
    }
}

fn emitCompoundOp(self: *Compiler, tag: Token.Tag) Error!void {
    try self.emitOp(switch (tag) {
        .plus_equal => .add,
        .minus_equal => .subtract,
        .star_equal => .multiply,
        .slash_equal => .divide,
        .percent_equal => .modulo,
        .star_star_equal => .power,
        .dot_equal => .concat,
        .amp_equal => .bit_and,
        .pipe_equal => .bit_or,
        .caret_equal => .bit_xor,
        .lt_lt_equal => .shift_left,
        .gt_gt_equal => .shift_right,
        else => unreachable,
    });
}

pub fn compilePipeExpr(self: *Compiler, node: Ast.Node) Error!void {
    try self.compileNode(node.data.rhs);
    try self.compileNode(node.data.lhs);
    try self.emitOp(.call_indirect);
    try self.emitByte(1);
}

pub fn compileBinaryOp(self: *Compiler, node: Ast.Node) Error!void {
    const op_tag = self.ast.tokens[node.main_token].tag;

    if (op_tag == .kw_instanceof) {
        try self.compileNode(node.data.lhs);
        const rhs = self.ast.nodes[node.data.rhs];
        if (rhs.tag == .variable or rhs.tag == .variable_variable or rhs.tag == .property_access or rhs.tag == .array_access) {
            try self.compileNode(node.data.rhs);
        } else {
            const class_name = try resolveNodeClassName(self, rhs);
            const idx = try self.addConstant(.{ .string = class_name });
            try self.emitOp(.constant);
            try self.emitU16(idx);
        }
        try self.emitOp(.instance_check);
        return;
    }

    try self.compileNode(node.data.lhs);
    try self.compileNode(node.data.rhs);
    try self.emitOp(switch (op_tag) {
        .plus => .add,
        .minus => .subtract,
        .star => .multiply,
        .slash => .divide,
        .percent => .modulo,
        .star_star => .power,
        .dot => .concat,
        .equal_equal => .equal,
        .bang_equal => .not_equal,
        .equal_equal_equal => .identical,
        .bang_equal_equal => .not_identical,
        .lt => .less,
        .lt_equal => .less_equal,
        .gt => .greater,
        .gt_equal => .greater_equal,
        .spaceship => .spaceship,
        .amp => .bit_and,
        .pipe => .bit_or,
        .caret => .bit_xor,
        .lt_lt => .shift_left,
        .gt_gt => .shift_right,
        .lt_gt => .not_equal,
        .kw_xor => .bit_xor,
        else => unreachable,
    });
}

pub fn compilePrefixOp(self: *Compiler, node: Ast.Node) Error!void {
    const op_tag = self.ast.tokens[node.main_token].tag;

    if (op_tag == .plus_plus or op_tag == .minus_minus) {
        const target = self.ast.nodes[node.data.lhs];
        if (target.tag == .property_access) {
            // stack: [obj] -> dup -> [obj, obj] -> get_prop -> [obj, val] -> +1 -> [obj, new_val] -> set_prop
            try self.compileNode(target.data.lhs);
            try self.emitOp(.dup);
            const prop_idx = try self.addConstant(.{ .string = self.propName(target) });
            try self.emitOp(.get_prop);
            try self.emitU16(prop_idx);
            try self.emitOp(if (op_tag == .plus_plus) .inc_value else .dec_value);
            try self.emitOp(.set_prop);
            try self.emitU16(prop_idx);
            return;
        }
        if (target.tag == .static_prop_access) {
            const class_node = self.ast.nodes[target.data.lhs];
            const class_name = self.ast.tokenSlice(class_node.main_token);
            var prop_name = self.ast.tokenSlice(target.main_token);
            if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
            const class_idx = try self.addConstant(.{ .string = class_name });
            const sprop_idx = try self.addConstant(.{ .string = prop_name });
            try self.emitOp(.get_static_prop);
            try self.emitU16(class_idx);
            try self.emitU16(sprop_idx);
            try self.emitOp(if (op_tag == .plus_plus) .inc_value else .dec_value);
            try self.emitOp(.set_static_prop);
            try self.emitU16(class_idx);
            try self.emitU16(sprop_idx);
            return;
        }
        if (target.tag == .array_access) {
            try self.compileNode(target.data.lhs);
            try self.compileNode(target.data.rhs);
            try self.compileNode(target.data.lhs);
            try self.compileNode(target.data.rhs);
            try self.emitOp(.array_get);
            try self.emitOp(if (op_tag == .plus_plus) .inc_value else .dec_value);
            try self.emitOp(.array_set);
            return;
        }
        try self.compileNode(node.data.lhs);
        try self.emitOp(if (op_tag == .plus_plus) .inc_value else .dec_value);
        if (target.tag == .variable) {
            const name = self.ast.tokenSlice(target.main_token);
            try self.emitSetVar(name);
        }
        return;
    }

    if (op_tag == .at) {
        try self.emitOp(.silence_begin);
        try self.compileNode(node.data.lhs);
        try self.emitOp(.silence_end);
        return;
    }
    if (op_tag == .kw_clone) {
        try self.compileNode(node.data.lhs);
        try self.emitOp(.clone_obj);
        return;
    }
    try self.compileNode(node.data.lhs);
    try self.emitOp(switch (op_tag) {
        .minus => .negate,
        .bang => .not,
        .tilde => .bit_not,
        else => unreachable,
    });
}

pub fn compilePostfixOp(self: *Compiler, node: Ast.Node) Error!void {
    const target = self.ast.nodes[node.data.lhs];
    const op_tag = self.ast.tokens[node.main_token].tag;

    if (target.tag == .property_access) {
        const prop_idx = try self.addConstant(.{ .string = self.propName(target) });
        // get old value (the postfix return value)
        try self.compileNode(target.data.lhs);
        try self.emitOp(.get_prop);
        try self.emitU16(prop_idx);
        // stack: [old_val]
        // now set obj.prop = old_val +/- 1
        try self.compileNode(target.data.lhs);
        try self.compileNode(target.data.lhs);
        try self.emitOp(.get_prop);
        try self.emitU16(prop_idx);
        try self.emitOp(if (op_tag == .plus_plus) .inc_value else .dec_value);
        try self.emitOp(.set_prop);
        try self.emitU16(prop_idx);
        try self.emitOp(.pop);
        return;
    }

    if (target.tag == .static_prop_access) {
        const class_node = self.ast.nodes[target.data.lhs];
        var class_name = self.ast.tokenSlice(class_node.main_token);
        if (std.mem.eql(u8, class_name, "self") or std.mem.eql(u8, class_name, "static") or std.mem.eql(u8, class_name, "parent")) {} else {
            class_name = self.ast.tokenSlice(class_node.main_token);
        }
        var prop_name = self.ast.tokenSlice(target.main_token);
        if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
        const class_idx = try self.addConstant(.{ .string = class_name });
        const sprop_idx = try self.addConstant(.{ .string = prop_name });
        try self.emitOp(.get_static_prop);
        try self.emitU16(class_idx);
        try self.emitU16(sprop_idx);
        try self.emitOp(.get_static_prop);
        try self.emitU16(class_idx);
        try self.emitU16(sprop_idx);
        try self.emitOp(if (op_tag == .plus_plus) .inc_value else .dec_value);
        try self.emitOp(.set_static_prop);
        try self.emitU16(class_idx);
        try self.emitU16(sprop_idx);
        try self.emitOp(.pop);
        return;
    }

    if (target.tag == .array_access) {
        try self.compileNode(target.data.lhs);
        try self.compileNode(target.data.rhs);
        try self.emitOp(if (op_tag == .plus_plus) .array_elem_inc else .array_elem_dec);
        return;
    }

    try self.compileNode(node.data.lhs);
    try self.compileNode(node.data.lhs);
    try self.emitOp(if (op_tag == .plus_plus) .inc_value else .dec_value);

    if (target.tag == .variable) {
        const name = self.ast.tokenSlice(target.main_token);
        try self.emitSetVar(name);
        try self.emitOp(.pop);
    }
}

pub fn compileLogicalAnd(self: *Compiler, node: Ast.Node) Error!void {
    try self.compileNode(node.data.lhs);
    const end_jump = try self.emitJump(.jump_if_false);
    try self.emitOp(.pop);
    try self.compileNode(node.data.rhs);
    self.patchJump(end_jump);
    try self.emitOp(.cast_bool);
}

pub fn compileLogicalOr(self: *Compiler, node: Ast.Node) Error!void {
    try self.compileNode(node.data.lhs);
    const end_jump = try self.emitJump(.jump_if_true);
    try self.emitOp(.pop);
    try self.compileNode(node.data.rhs);
    self.patchJump(end_jump);
    try self.emitOp(.cast_bool);
}

pub fn compileNullCoalesce(self: *Compiler, node: Ast.Node) Error!void {
    // PHP's `??` uses isset() semantics on the LHS rather than a plain null
    // compare: an undefined array key or out-of-bounds string offset should
    // route through to the RHS even though `array_get` would normally
    // synthesize "" or push a warning. For nested array_access chains we
    // emit array_get_coalesce all the way down so intermediate misses don't
    // warn either
    try compileCoalesceFetch(self, node.data.lhs);
    const end_jump = try self.emitJump(.jump_if_not_null);
    try self.emitOp(.pop);
    try self.compileNode(node.data.rhs);
    self.patchJump(end_jump);
}

fn compileCoalesceFetch(self: *Compiler, node_idx: u32) Error!void {
    const n = self.ast.nodes[node_idx];
    if (n.tag == .array_access) {
        try compileCoalesceFetch(self, n.data.lhs);
        try self.compileNode(n.data.rhs);
        try self.emitOp(.array_get_coalesce);
        return;
    }
    try self.compileNode(node_idx);
}

pub fn compileTernary(self: *Compiler, node: Ast.Node) Error!void {
    const then_node = self.ast.extra_data[node.data.rhs];
    const else_node = self.ast.extra_data[node.data.rhs + 1];

    try self.compileNode(node.data.lhs);

    if (then_node != 0) {
        const else_jump = try self.emitJump(.jump_if_false);
        try self.emitOp(.pop);
        try self.compileNode(then_node);
        const end_jump = try self.emitJump(.jump);
        self.patchJump(else_jump);
        try self.emitOp(.pop);
        try self.compileNode(else_node);
        self.patchJump(end_jump);
    } else {
        // short ternary: $a ?: $b - reuse the condition value if truthy
        const end_jump = try self.emitJump(.jump_if_true);
        try self.emitOp(.pop);
        try self.compileNode(else_node);
        self.patchJump(end_jump);
    }
}

pub fn compileCall(self: *Compiler, node: Ast.Node) Error!void {
    const callee = self.ast.nodes[node.data.lhs];
    const args = self.ast.extraSlice(node.data.rhs);

    if (callee.tag == .identifier and std.mem.eql(u8, self.ast.tokenSlice(callee.main_token), "unset")) {
        try compileUnset(self, args);
        return;
    }

    if (callee.tag == .identifier and std.mem.eql(u8, self.ast.tokenSlice(callee.main_token), "settype")) {
        try compileSettype(self, args);
        return;
    }

    if (callee.tag == .identifier and std.mem.eql(u8, self.ast.tokenSlice(callee.main_token), "empty")) {
        // empty() uses isset semantics for the read so undefined keys/props
        // don't warn; the result is "not truthy" rather than "isset"
        if (args.len == 1) {
            const arg = self.ast.nodes[args[0]];
            if (arg.tag == .array_access) {
                try compileCoalesceFetch(self, args[0]);
                try self.emitOp(.cast_bool);
                try self.emitOp(.not);
                return;
            }
        }
    }

    if (callee.tag == .identifier and std.mem.eql(u8, self.ast.tokenSlice(callee.main_token), "isset")) {
        if (args.len > 0) {
            var end_jumps: [16]usize = undefined;
            var jump_count: usize = 0;
            for (args, 0..) |arg_idx, i| {
                const arg = self.ast.nodes[arg_idx];
                if (arg.tag == .property_access) {
                    if (self.isDynamicProp(arg)) {
                        try self.compileNode(arg.data.lhs);
                        try self.compileNode(arg.data.rhs);
                        try self.emitOp(.isset_prop_dynamic);
                    } else {
                        try self.compileNode(arg.data.lhs);
                        const prop_name = self.propName(arg);
                        const prop_idx = try self.addConstant(.{ .string = prop_name });
                        try self.emitOp(.isset_prop);
                        try self.emitU16(prop_idx);
                    }
                } else if (arg.tag == .array_access) {
                    const lhs_node = self.ast.nodes[arg.data.lhs];
                    if (lhs_node.tag == .property_access and !self.isDynamicProp(lhs_node)) {
                        // for isset($obj->prop[key]), PHP first calls __isset('prop')
                        // and short-circuits to false without calling __get when the
                        // property isn't set. emit: obj, dup, isset_prop, branch on
                        // false (drop the obj, push false), else get_prop and isset_index
                        try self.compileNode(lhs_node.data.lhs);
                        try self.emitOp(.dup);
                        const prop_name = self.propName(lhs_node);
                        const prop_idx = try self.addConstant(.{ .string = prop_name });
                        try self.emitOp(.isset_prop);
                        try self.emitU16(prop_idx);
                        // stack: [obj, bool]
                        const false_jump = try self.emitJump(.jump_if_false);
                        try self.emitOp(.pop); // drop true bool → [obj]
                        try self.emitOp(.get_prop);
                        try self.emitU16(prop_idx);
                        try self.compileNode(arg.data.rhs);
                        try self.emitOp(.isset_index); // → [bool]
                        const done_jump = try self.emitJump(.jump);
                        self.patchJump(false_jump);
                        // stack: [obj, false] — swap and drop obj to leave [false]
                        try self.emitOp(.swap);
                        try self.emitOp(.pop);
                        self.patchJump(done_jump);
                    } else {
                        // use coalesce fetch for the LHS chain so nested
                        // isset($a[x][y]) doesn't warn on the inner read
                        try compileCoalesceFetch(self, arg.data.lhs);
                        try self.compileNode(arg.data.rhs);
                        try self.emitOp(.isset_index);
                    }
                } else {
                    try self.compileNode(arg_idx);
                    try self.emitOp(.op_null);
                    try self.emitOp(.not_identical);
                }
                if (i < args.len - 1 and jump_count < end_jumps.len) {
                    end_jumps[jump_count] = try self.emitJump(.jump_if_false);
                    jump_count += 1;
                    try self.emitOp(.pop);
                }
            }
            for (end_jumps[0..jump_count]) |j| self.patchJump(j);
            return;
        }
    }

    if (hasSplatOrNamed(self.ast, args)) {
        if (callee.tag == .property_access and self.isDynamicProp(callee)) {
            try self.compileNode(callee.data.lhs);
            if (callee.main_token == 0) {
                try self.compileNode(callee.data.rhs);
            } else {
                const prop_node = self.ast.nodes[callee.data.rhs];
                const var_name = self.ast.tokenSlice(prop_node.main_token);
                try self.emitGetVar(var_name);
            }
            try emitSpreadArgs(self, args);
            try self.emitOp(.method_call_dynamic_spread);
        } else {
            try emitSpreadArgs(self, args);
            if (callee.tag == .identifier) {
                const raw_name = self.ast.tokenSlice(callee.main_token);
                const name = self.resolveFunctionName(raw_name);
                const idx = try self.addConstant(.{ .string = name });
                try self.emitOp(.call_spread);
                try self.emitU16(idx);
            } else if (callee.tag == .qualified_name) {
                const parts = self.ast.extraSlice(callee.data.lhs);
                const fqn = try self.buildQualifiedString(parts);
                const name = if (fqn.len > 0 and fqn[0] == '\\') fqn[1..] else fqn;
                const idx = try self.addConstant(.{ .string = name });
                try self.emitOp(.call_spread);
                try self.emitU16(idx);
            } else if (callee.tag == .static_prop_access and callee.main_token != 0 and self.ast.tokens[callee.main_token].tag == .variable) {
                const class_node = self.ast.nodes[callee.data.lhs];
                const var_name = self.ast.tokenSlice(callee.main_token);
                if (class_node.tag == .variable) {
                    try self.compileNode(callee.data.lhs);
                } else {
                    const class_name = try resolveNodeClassName(self, class_node);
                    const cn_idx = try self.addConstant(.{ .string = class_name });
                    try self.emitOp(.constant);
                    try self.emitU16(cn_idx);
                }
                try self.emitGetVar(var_name);
                try emitSpreadArgs(self, args);
                try self.emitOp(.static_call_dyn_both_spread);
            } else {
                try self.compileNode(node.data.lhs);
                try self.emitOp(.call_indirect_spread);
            }
        }
    } else if (callee.tag == .identifier) {
        const call_offset = self.current_source_offset;
        for (args) |arg| try self.compileNode(arg);
        self.current_source_offset = call_offset;
        const raw_name = self.ast.tokenSlice(callee.main_token);
        const name = self.resolveFunctionName(raw_name);
        const idx = try self.addConstant(.{ .string = name });
        try self.emitOp(.call);
        try self.emitU16(idx);
        try self.emitByte(@intCast(args.len));
    } else if (callee.tag == .qualified_name) {
        const call_offset = self.current_source_offset;
        for (args) |arg| try self.compileNode(arg);
        self.current_source_offset = call_offset;
        const parts = self.ast.extraSlice(callee.data.lhs);
        const fqn = try self.buildQualifiedString(parts);
        const name = if (fqn.len > 0 and fqn[0] == '\\') fqn[1..] else fqn;
        const idx = try self.addConstant(.{ .string = name });
        try self.emitOp(.call);
        try self.emitU16(idx);
        try self.emitByte(@intCast(args.len));
    } else if (callee.tag == .property_access and self.isDynamicProp(callee)) {
        const call_offset = self.current_source_offset;
        try self.compileNode(callee.data.lhs);
        if (callee.main_token == 0) {
            try self.compileNode(callee.data.rhs);
        } else {
            const prop_node = self.ast.nodes[callee.data.rhs];
            const var_name = self.ast.tokenSlice(prop_node.main_token);
            try self.emitGetVar(var_name);
        }
        for (args) |arg| try self.compileNode(arg);
        self.current_source_offset = call_offset;
        try self.emitOp(.method_call_dynamic);
        try self.emitByte(@intCast(args.len));
    } else if (callee.tag == .static_prop_access and callee.main_token != 0 and self.ast.tokens[callee.main_token].tag == .variable) {
        const call_offset = self.current_source_offset;
        const class_node = self.ast.nodes[callee.data.lhs];
        const var_name = self.ast.tokenSlice(callee.main_token);
        if (class_node.tag == .variable) {
            try self.compileNode(callee.data.lhs);
            try self.emitGetVar(var_name);
            for (args) |arg| try self.compileNode(arg);
            self.current_source_offset = call_offset;
            try self.emitOp(.static_call_dyn_both);
            try self.emitByte(@intCast(args.len));
        } else {
            const class_name = try resolveNodeClassName(self, class_node);
            const class_idx = try self.addConstant(.{ .string = class_name });
            try self.emitGetVar(var_name);
            for (args) |arg| try self.compileNode(arg);
            self.current_source_offset = call_offset;
            try self.emitOp(.static_call_dyn_method);
            try self.emitU16(class_idx);
            try self.emitByte(@intCast(args.len));
        }
    } else {
        const call_offset = self.current_source_offset;
        try self.compileNode(node.data.lhs);
        for (args) |arg| try self.compileNode(arg);
        self.current_source_offset = call_offset;
        try self.emitOp(.call_indirect);
        try self.emitByte(@intCast(args.len));
    }
}

pub fn hasSplatOrNamed(ast: *const Ast, args: []const u32) bool {
    for (args) |arg_idx| {
        const tag = ast.nodes[arg_idx].tag;
        if (tag == .splat_expr or tag == .named_arg) return true;
    }
    return false;
}

pub fn emitSpreadArgs(self: *Compiler, args: []const u32) Error!void {
    try self.emitOp(.array_new);
    for (args) |arg_idx| {
        const arg_node = self.ast.nodes[arg_idx];
        if (arg_node.tag == .splat_expr) {
            try self.compileNode(arg_node.data.lhs);
            try self.emitOp(.array_spread);
        } else if (arg_node.tag == .named_arg) {
            const name = self.ast.tokenSlice(arg_node.main_token);
            const name_const = try self.addConstant(.{ .string = name });
            try self.emitOp(.constant);
            try self.emitU16(name_const);
            try self.compileNode(arg_node.data.lhs);
            try self.emitOp(.array_set_elem);
        } else {
            try self.compileNode(arg_idx);
            try self.emitOp(.array_push);
        }
    }
}

fn compileUnset(self: *Compiler, args: []const u32) Error!void {
    for (args) |arg_idx| {
        const arg = self.ast.nodes[arg_idx];
        if (arg.tag == .variable) {
            const name = self.ast.tokenSlice(arg.main_token);
            const idx = try self.addConstant(.{ .string = name });
            try self.emitOp(.unset_var);
            try self.emitU16(idx);
        } else if (arg.tag == .property_access) {
            try self.compileNode(arg.data.lhs);
            if (self.isDynamicProp(arg)) {
                if (arg.main_token == 0) {
                    try self.compileNode(arg.data.rhs);
                } else {
                    const prop_node = self.ast.nodes[arg.data.rhs];
                    const var_name = self.ast.tokenSlice(prop_node.main_token);
                    try self.emitGetVar(var_name);
                }
                try self.emitOp(.unset_prop_dynamic);
            } else {
                const prop_idx = try self.addConstant(.{ .string = self.propName(arg) });
                try self.emitOp(.unset_prop);
                try self.emitU16(prop_idx);
            }
        } else if (arg.tag == .array_access) {
            // for `unset($a[k1][k2]...[kn])`, the intermediate reads should
            // use coalesce-safe semantics so missing keys don't warn
            try compileCoalesceFetch(self, arg.data.lhs);
            try self.compileNode(arg.data.rhs);
            try self.emitOp(.unset_array_elem);
        }
    }
    try self.emitOp(.op_null);
}

fn compileSettype(self: *Compiler, args: []const u32) Error!void {
    if (args.len < 2) {
        try self.emitOp(.op_false);
        return;
    }
    const target = self.ast.nodes[args[0]];
    if (target.tag != .variable) {
        try self.emitOp(.op_false);
        return;
    }
    const var_name = self.ast.tokenSlice(target.main_token);

    // settype returns the converted value, we store it back and push true
    try self.emitGetVar(var_name);
    try self.compileNode(args[1]);
    const fn_idx = try self.addConstant(.{ .string = "settype" });
    try self.emitOp(.call);
    try self.emitU16(fn_idx);
    try self.emitByte(2);
    try self.emitSetVar(var_name);
    try self.emitOp(.pop);
    try self.emitOp(.op_true);
}

pub fn compileCallableRef(self: *Compiler, node: Ast.Node) Error!void {
    const callee = self.ast.nodes[node.data.lhs];
    if (callee.tag == .identifier) {
        const name = self.ast.tokenSlice(callee.main_token);
        const idx = try self.addConstant(.{ .string = name });
        try self.emitOp(.constant);
        try self.emitU16(idx);
    } else if (callee.tag == .method_call) {
        // $obj->method(...) => [$obj, 'method']
        try self.emitOp(.array_new);
        try self.compileNode(callee.data.lhs);
        try self.emitOp(.array_push);
        const method_name = self.ast.tokenSlice(callee.main_token);
        const method_idx = try self.addConstant(.{ .string = method_name });
        try self.emitOp(.constant);
        try self.emitU16(method_idx);
        try self.emitOp(.array_push);
    } else if (callee.tag == .static_call) {
        // ClassName::method(...) => ['ClassName', 'method']
        const class_node = self.ast.nodes[callee.data.lhs];
        const class_name = try resolveNodeClassName(self, class_node);
        const method_name = self.ast.tokenSlice(callee.main_token);
        try self.emitOp(.array_new);
        const class_idx = try self.addConstant(.{ .string = class_name });
        try self.emitOp(.constant);
        try self.emitU16(class_idx);
        try self.emitOp(.array_push);
        const method_idx = try self.addConstant(.{ .string = method_name });
        try self.emitOp(.constant);
        try self.emitU16(method_idx);
        try self.emitOp(.array_push);
    } else {
        try self.compileNode(node.data.lhs);
    }
}

pub fn compileArrayAccess(self: *Compiler, node: Ast.Node) Error!void {
    try self.compileNode(node.data.lhs);
    try self.compileNode(node.data.rhs);
    try self.emitOp(.array_get);
}

pub fn compileVivifyChain(self: *Compiler, node_idx: u32) Error!void {
    const node = self.ast.nodes[node_idx];
    if (node.tag == .array_access) {
        try compileVivifyChain(self, node.data.lhs);
        try self.compileNode(node.data.rhs);
        try self.emitOp(.array_get_vivify);
    } else if (node.tag == .variable or node.tag == .identifier) {
        const name = self.ast.tokenSlice(node.main_token);
        try emitEnsureArray(self, name);
    } else {
        try self.compileNode(node_idx);
    }
}

fn emitEnsureArray(self: *Compiler, name: []const u8) Error!void {
    if (self.local_slots.get(name)) |slot| {
        try self.emitOp(.ensure_array_local);
        try self.emitU16(slot);
        return;
    }
    if (!self.inFunctionScope() and name.len > 0 and name[0] == '$') {
        const slot = self.getOrCreateSlot(name);
        try self.emitOp(.ensure_array_local);
        try self.emitU16(slot);
        return;
    }
    const idx = try self.addConstant(.{ .string = name });
    try self.emitOp(.ensure_array_var);
    try self.emitU16(idx);
}

pub fn compileArrayLiteral(self: *Compiler, node: Ast.Node) Error!void {
    try self.emitOp(.array_new);
    for (self.ast.extraSlice(node.data.lhs)) |elem_idx| {
        const elem = self.ast.nodes[elem_idx];
        if (elem.tag == .array_spread) {
            try self.compileNode(elem.data.lhs);
            try self.emitOp(.array_spread);
        } else if (elem.data.rhs != 0) {
            try self.compileNode(elem.data.rhs);
            try self.compileNode(elem.data.lhs);
            try self.emitOp(.array_set_elem);
        } else {
            try self.compileNode(elem.data.lhs);
            try self.emitOp(.array_push);
        }
    }
}

pub fn compilePropertyAccess(self: *Compiler, node: Ast.Node) Error!void {
    // outermost chain link sets up the nullsafe-jump collection. inner nullsafe
    // links append their short-circuit jumps to this list so a `$x?->y()->z`
    // chain skips both `y()` and `z` when $x is null
    var local_jumps: std.ArrayListUnmanaged(usize) = .{};
    const owns_chain = self.nullsafe_chain_jumps == null and lhsIsChainLink(self.ast, node);
    if (owns_chain) self.nullsafe_chain_jumps = &local_jumps;
    defer if (owns_chain) {
        for (local_jumps.items) |j| self.patchJump(j);
        self.nullsafe_chain_jumps = null;
        local_jumps.deinit(self.allocator);
    };

    try self.compileNode(node.data.lhs);
    if (self.isDynamicProp(node)) {
        if (node.main_token == 0) {
            // $obj->{expr}: compile the expression as property name
            try self.compileNode(node.data.rhs);
        } else {
            // $obj->$field: load variable value as property name
            const prop_node = self.ast.nodes[node.data.rhs];
            const var_name = self.ast.tokenSlice(prop_node.main_token);
            try self.emitGetVar(var_name);
        }
        try self.emitOp(.get_prop_dynamic);
    } else {
        const name_idx = try self.addConstant(.{ .string = self.propName(node) });
        try self.emitOp(.get_prop);
        try self.emitU16(name_idx);
    }

}

fn lhsIsChainLink(ast: anytype, node: Ast.Node) bool {
    const lhs = ast.nodes[node.data.lhs];
    return switch (lhs.tag) {
        .property_access, .method_call, .nullsafe_property_access, .nullsafe_method_call => true,
        else => false,
    };
}

pub fn compileMethodCall(self: *Compiler, node: Ast.Node) Error!void {
    var local_jumps: std.ArrayListUnmanaged(usize) = .{};
    const owns_chain = self.nullsafe_chain_jumps == null and lhsIsChainLink(self.ast, node);
    if (owns_chain) self.nullsafe_chain_jumps = &local_jumps;
    defer if (owns_chain) {
        for (local_jumps.items) |j| self.patchJump(j);
        self.nullsafe_chain_jumps = null;
        local_jumps.deinit(self.allocator);
    };

    try self.compileNode(node.data.lhs);
    const args = self.ast.extraSlice(node.data.rhs);

    if (self.ast.tokens[node.main_token].tag == .variable) {
        const var_name = self.ast.tokenSlice(node.main_token);
        try self.emitGetVar(var_name);
        if (hasSplatOrNamed(self.ast, args)) {
            try emitSpreadArgs(self, args);
            try self.emitOp(.method_call_dynamic_spread);
        } else {
            for (args) |arg| try self.compileNode(arg);
            try self.emitOp(.method_call_dynamic);
            try self.emitByte(@intCast(args.len));
        }
        return;
    }

    const method_name = self.ast.tokenSlice(node.main_token);
    const name_idx = try self.addConstant(.{ .string = method_name });

    if (hasSplatOrNamed(self.ast, args)) {
        try emitSpreadArgs(self, args);
        try self.emitOp(.method_call_spread);
        try self.emitU16(name_idx);
    } else {
        for (args) |arg| try self.compileNode(arg);
        try self.emitOp(.method_call);
        try self.emitU16(name_idx);
        try self.emitByte(@intCast(args.len));
    }
}

pub fn compileNullsafePropertyAccess(self: *Compiler, node: Ast.Node) Error!void {
    // create or reuse the chain jump-list. when an outer chain link is
    // collecting, append our short-circuit jump there; otherwise patch locally
    var local_jumps: std.ArrayListUnmanaged(usize) = .{};
    const owns_chain = self.nullsafe_chain_jumps == null;
    if (owns_chain) self.nullsafe_chain_jumps = &local_jumps;
    defer if (owns_chain) {
        for (local_jumps.items) |j| self.patchJump(j);
        self.nullsafe_chain_jumps = null;
        local_jumps.deinit(self.allocator);
    };

    try self.compileNode(node.data.lhs);
    const skip_jump = try self.emitJump(.jump_if_not_null);
    const end_jump = try self.emitJump(.jump);
    self.patchJump(skip_jump);
    const name_idx = try self.addConstant(.{ .string = self.propName(node) });
    try self.emitOp(.get_prop);
    try self.emitU16(name_idx);
    try self.nullsafe_chain_jumps.?.append(self.allocator, end_jump);
}

pub fn compileNullsafeMethodCall(self: *Compiler, node: Ast.Node) Error!void {
    var local_jumps: std.ArrayListUnmanaged(usize) = .{};
    const owns_chain = self.nullsafe_chain_jumps == null;
    if (owns_chain) self.nullsafe_chain_jumps = &local_jumps;
    defer if (owns_chain) {
        for (local_jumps.items) |j| self.patchJump(j);
        self.nullsafe_chain_jumps = null;
        local_jumps.deinit(self.allocator);
    };

    try self.compileNode(node.data.lhs);
    const skip_jump = try self.emitJump(.jump_if_not_null);
    const end_jump = try self.emitJump(.jump);
    self.patchJump(skip_jump);
    const args = self.ast.extraSlice(node.data.rhs);
    const method_name = self.ast.tokenSlice(node.main_token);
    const name_idx = try self.addConstant(.{ .string = method_name });

    if (hasSplatOrNamed(self.ast, args)) {
        try emitSpreadArgs(self, args);
        try self.emitOp(.method_call_spread);
        try self.emitU16(name_idx);
    } else {
        for (args) |arg| try self.compileNode(arg);
        try self.emitOp(.method_call);
        try self.emitU16(name_idx);
        try self.emitByte(@intCast(args.len));
    }
    try self.nullsafe_chain_jumps.?.append(self.allocator, end_jump);
}

pub fn compileStaticCall(self: *Compiler, node: Ast.Node) Error!void {
    // unwrap (grouped_expr) wrapping so (new X())::foo() is dispatched as a
    // dynamic static call against the inner new-expression
    var class_lhs_idx = node.data.lhs;
    var class_node = self.ast.nodes[class_lhs_idx];
    while (class_node.tag == .grouped_expr) {
        class_lhs_idx = class_node.data.lhs;
        class_node = self.ast.nodes[class_lhs_idx];
    }
    const method_name = self.ast.tokenSlice(node.main_token);
    const args = self.ast.extraSlice(node.data.rhs);

    if (class_node.tag == .variable) {
        try self.compileNode(class_lhs_idx);
        const method_idx = try self.addConstant(.{ .string = method_name });
        for (args) |arg| try self.compileNode(arg);
        try self.emitOp(.static_call_dynamic);
        try self.emitU16(method_idx);
        try self.emitByte(@intCast(args.len));
        return;
    }

    // Class::method when the class side is an expression that produces an
    // object (e.g. (new X())::foo()): evaluate the object, derive its class,
    // then emit static_call_dynamic
    switch (class_node.tag) {
        .new_expr, .method_call, .nullsafe_method_call, .call,
        .property_access, .nullsafe_property_access, .array_access => {
            try self.compileNode(class_lhs_idx);
            try self.emitOp(.get_obj_class);
            const method_idx = try self.addConstant(.{ .string = method_name });
            for (args) |arg| try self.compileNode(arg);
            try self.emitOp(.static_call_dynamic);
            try self.emitU16(method_idx);
            try self.emitByte(@intCast(args.len));
            return;
        },
        else => {},
    }

    const class_name = try resolveNodeClassName(self, class_node);
    const class_idx = try self.addConstant(.{ .string = class_name });
    const method_idx = try self.addConstant(.{ .string = method_name });

    if (hasSplatOrNamed(self.ast, args)) {
        try emitSpreadArgs(self, args);
        try self.emitOp(.static_call_spread);
        try self.emitU16(class_idx);
        try self.emitU16(method_idx);
    } else {
        for (args) |arg| try self.compileNode(arg);
        try self.emitOp(.static_call);
        try self.emitU16(class_idx);
        try self.emitU16(method_idx);
        try self.emitByte(@intCast(args.len));
    }
}

pub fn compileDynamicStaticCall(self: *Compiler, node: Ast.Node) Error!void {
    const class_node = self.ast.nodes[node.data.lhs];
    const extra = self.ast.extraSlice(node.data.rhs);
    const method_expr = extra[0];
    const args = extra[1..];

    if (class_node.tag == .variable) {
        try self.compileNode(node.data.lhs);
        try self.compileNode(method_expr);
        for (args) |arg| try self.compileNode(arg);
        try self.emitOp(.static_call_dyn_both);
        try self.emitByte(@intCast(args.len));
    } else {
        const class_name = try resolveNodeClassName(self, class_node);
        const class_idx = try self.addConstant(.{ .string = class_name });
        try self.compileNode(method_expr);
        for (args) |arg| try self.compileNode(arg);
        try self.emitOp(.static_call_dyn_method);
        try self.emitU16(class_idx);
        try self.emitByte(@intCast(args.len));
    }
}

pub fn compileStaticPropAccess(self: *Compiler, node: Ast.Node) Error!void {
    const class_node = self.ast.nodes[node.data.lhs];

    // Class::{expr} - dynamic constant/property name. parser sets main_token=0
    // and stores the name expression in node.data.rhs
    if (node.main_token == 0 and node.data.rhs != 0) {
        const class_name = try resolveNodeClassName(self, class_node);
        const class_idx = try self.addConstant(.{ .string = class_name });
        try self.compileNode(node.data.rhs);
        try self.emitOp(.get_static_prop_dyn_name);
        try self.emitU16(class_idx);
        return;
    }

    if (node.main_token != 0 and self.ast.tokens[node.main_token].tag == .kw_class and
        class_node.tag != .identifier and class_node.tag != .qualified_name)
    {
        try self.compileNode(node.data.lhs);
        try self.emitOp(.get_obj_class);
        return;
    }

    // dynamic class expression (function call, method call, etc.)
    if (class_node.tag != .identifier and class_node.tag != .qualified_name) {
        try self.compileNode(node.data.lhs);
        var prop_name = self.ast.tokenSlice(node.main_token);
        if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
        const prop_idx = try self.addConstant(.{ .string = prop_name });
        try self.emitOp(.get_static_prop_dynamic);
        try self.emitU16(prop_idx);
        return;
    }

    const class_name = try resolveNodeClassName(self, class_node);
    var prop_name = self.ast.tokenSlice(node.main_token);
    if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
    const class_idx = try self.addConstant(.{ .string = class_name });
    const prop_idx = try self.addConstant(.{ .string = prop_name });
    try self.emitOp(.get_static_prop);
    try self.emitU16(class_idx);
    try self.emitU16(prop_idx);
}

pub fn resolveNodeClassName(self: *Compiler, class_node: Ast.Node) ![]const u8 {
    if (class_node.tag == .qualified_name) {
        const parts = self.ast.extraSlice(class_node.data.lhs);
        const name = try self.buildQualifiedString(parts);
        if (class_node.data.rhs == 1) return name;
        // check if the first segment is a use alias
        if (std.mem.indexOf(u8, name, "\\")) |sep| {
            const first_segment = name[0..sep];
            if (self.use_aliases.get(first_segment)) |alias_fqn| {
                const qualified = std.fmt.allocPrint(self.allocator, "{s}{s}", .{ alias_fqn, name[sep..] }) catch return name;
                self.string_allocs.append(self.allocator, qualified) catch return name;
                return qualified;
            }
        }
        if (self.namespace.len == 0) return name;
        const qualified = std.fmt.allocPrint(self.allocator, "{s}\\{s}", .{ self.namespace, name }) catch return name;
        self.string_allocs.append(self.allocator, qualified) catch return name;
        return qualified;
    }
    return self.resolveClassName(self.ast.tokenSlice(class_node.main_token));
}

pub fn resolveQualifiedNewName(self: *Compiler, node: Ast.Node) !struct { name: []const u8, is_absolute: bool } {
    const first = self.ast.tokenSlice(node.main_token);
    const rhs_raw = node.data.rhs & ~(@as(u32, 1) << 31);
    const is_absolute = (node.data.rhs & (1 << 31)) != 0;
    if (rhs_raw == 0) return .{ .name = first, .is_absolute = is_absolute };
    const parts = self.ast.extraSlice(rhs_raw);
    var buf = std.ArrayListUnmanaged(u8){};
    try buf.appendSlice(self.allocator, first);
    for (parts[1..]) |part_tok| {
        try buf.append(self.allocator, '\\');
        try buf.appendSlice(self.allocator, self.ast.tokenSlice(part_tok));
    }
    const owned = try buf.toOwnedSlice(self.allocator);
    try self.string_allocs.append(self.allocator, owned);
    return .{ .name = owned, .is_absolute = is_absolute };
}

pub fn compileNewExpr(self: *Compiler, node: Ast.Node) Error!void {
    const resolved = try resolveQualifiedNewName(self, node);
    const raw_name = resolved.name;
    const class_name = if (resolved.is_absolute)
        raw_name
    else if (std.mem.indexOf(u8, raw_name, "\\")) |sep| blk: {
        // check if the first segment is a use alias
        const first_segment = raw_name[0..sep];
        if (self.use_aliases.get(first_segment)) |alias_fqn| {
            const qualified = std.fmt.allocPrint(self.allocator, "{s}{s}", .{ alias_fqn, raw_name[sep..] }) catch return error.CompileError;
            self.string_allocs.append(self.allocator, qualified) catch return error.CompileError;
            break :blk qualified;
        }
        if (self.namespace.len > 0) {
            const qualified = std.fmt.allocPrint(self.allocator, "{s}\\{s}", .{ self.namespace, raw_name }) catch return error.CompileError;
            self.string_allocs.append(self.allocator, qualified) catch return error.CompileError;
            break :blk qualified;
        }
        break :blk raw_name;
    } else self.resolveClassName(raw_name);
    const args = self.ast.extraSlice(node.data.lhs);
    const name_idx = try self.addConstant(.{ .string = class_name });
    if (hasSplatOrNamed(self.ast, args)) {
        try emitSpreadArgs(self, args);
        try self.emitOp(.new_obj);
        try self.emitU16(name_idx);
        try self.emitByte(0xFF);
    } else {
        for (args) |arg| try self.compileNode(arg);
        try self.emitOp(.new_obj);
        try self.emitU16(name_idx);
        try self.emitByte(@intCast(args.len));
    }
}

pub fn compileNewExprDynamic(self: *Compiler, node: Ast.Node) Error!void {
    try self.compileNode(node.data.lhs);
    const args = self.ast.extraSlice(node.data.rhs);
    if (hasSplatOrNamed(self.ast, args)) {
        try emitSpreadArgs(self, args);
        try self.emitOp(.new_obj_dynamic);
        try self.emitByte(0xFF);
    } else {
        for (args) |arg| try self.compileNode(arg);
        try self.emitOp(.new_obj_dynamic);
        try self.emitByte(@intCast(args.len));
    }
}

pub fn compileYield(self: *Compiler, node: Ast.Node) Error!void {
    if (node.data.lhs != 0) {
        try self.compileNode(node.data.lhs);
    } else {
        try self.emitOp(.op_null);
    }
    try self.emitOp(.yield_value);
}

pub fn compileYieldPair(self: *Compiler, node: Ast.Node) Error!void {
    try self.compileNode(node.data.lhs);
    try self.compileNode(node.data.rhs);
    try self.emitOp(.yield_pair);
}

pub fn compileYieldFrom(self: *Compiler, node: Ast.Node) Error!void {
    try self.compileNode(node.data.lhs);
    try self.emitOp(.yield_from);
}

pub fn compileCast(self: *Compiler, node: Ast.Node) Error!void {
    try self.compileNode(node.data.lhs);
    const type_name = self.ast.tokenSlice(node.main_token);
    if (std.mem.eql(u8, type_name, "int") or std.mem.eql(u8, type_name, "integer")) {
        try self.emitOp(.cast_int);
    } else if (std.mem.eql(u8, type_name, "float") or std.mem.eql(u8, type_name, "double") or std.mem.eql(u8, type_name, "real")) {
        try self.emitOp(.cast_float);
    } else if (std.mem.eql(u8, type_name, "string")) {
        try self.emitOp(.cast_string);
    } else if (std.mem.eql(u8, type_name, "bool") or std.mem.eql(u8, type_name, "boolean")) {
        try self.emitOp(.cast_bool);
    } else if (std.mem.eql(u8, type_name, "array")) {
        try self.emitOp(.cast_array);
    } else if (std.mem.eql(u8, type_name, "object")) {
        try self.emitOp(.cast_object);
    }
}
