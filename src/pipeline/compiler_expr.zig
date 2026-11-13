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
    if (target.tag != .list_destructure and target.tag != .array_literal) try ensureWritable(self, node.data.lhs, node.main_token);
    if (target.tag == .list_destructure or target.tag == .array_literal) try ensureListWritable(self, node.data.lhs, node.main_token);
    if (self.ast.nodes[node.data.rhs].tag == .ref_target) {
        try assertNotShortCircuited(self, self.ast.nodes[node.data.rhs].data.lhs, node.main_token);
        if (isGlobalsFetch(self, self.ast.nodes[node.data.rhs].data.lhs)) return self.fail(node.main_token, "Cannot acquire reference to $GLOBALS");
    }
    // a list binding references takes them from its source
    if ((target.tag == .list_destructure or target.tag == .array_literal) and listHasRef(self, node.data.lhs)) try assertNotShortCircuited(self, node.data.rhs, node.main_token);
    // zend_try_compile_cv: $this is never written
    if (target.tag == .variable and std.mem.eql(u8, self.ast.tokenSlice(target.main_token), "$this"))
        return self.fail(target.main_token, "Cannot re-assign $this");

    if (op_tag == .equal and (target.tag == .variable or target.tag == .identifier)) {
        const rhs = self.ast.nodes[node.data.rhs];
        if (rhs.tag == .ref_target) {
            const dst = try self.addConstant(.{ .string = Value.String.borrowed(self.ast.tokenSlice(target.main_token)) });
            if (try compileReferenceBinding(self, rhs.data.lhs, dst)) {
                try self.emitGetVar(self.ast.tokenSlice(target.main_token));
                return;
            }
            try self.emitOp(.break_var_ref);
            try self.emitU16(dst);
        }
    }

    if (target.tag == .list_destructure or (target.tag == .array_literal and op_tag == .equal)) {
        try self.compileNode(node.data.rhs);
        try self.compileDestructure(target);
        return;
    }

    if (target.tag == .array_push_target) {
        // ??= must read the element being appended; the other compound
        // operators apply to null and append the result
        if (op_tag == .question_question_equal) return self.fail(target.main_token, "Cannot use [] for reading");
        if (op_tag != .equal) {
            try compileVivifyChain(self, target.data.lhs);
            try self.emitOp(.op_null);
            try self.compileNode(node.data.rhs);
            try emitCompoundOp(self, op_tag);
            try self.emitOp(.array_push_assign);
            return;
        }
        // `$arr[] = &$var` (plain-variable ref source): append a true reference
        if (op_tag == .equal and self.ast.nodes[node.data.rhs].tag == .ref_target) {
            const ref_inner = self.ast.nodes[self.ast.nodes[node.data.rhs].data.lhs];
            if (ref_inner.tag == .variable) {
                const vname = self.ast.tokenSlice(ref_inner.main_token);
                const vidx = try self.addConstant(.{ .string = Value.String.borrowed(vname) });
                try compileVivifyChain(self, target.data.lhs);
                try self.emitOp(.array_push_bind_ref);
                try self.emitU16(vidx);
                return;
            }
            if (ref_inner.tag == .variable_variable) {
                try compileVivifyChain(self, target.data.lhs);
                try self.compileNode(ref_inner.data.lhs);
                try self.emitOp(.array_push_bind_ref_var_var);
                return;
            }
        }
        try compileVivifyChain(self, target.data.lhs);
        try self.compileNode(node.data.rhs);
        try self.emitOp(.array_push_assign);
        return;
    }

    if (op_tag != .equal and op_tag != .question_question_equal and isPlaceTarget(self, node.data.lhs)) {
        // php fetches the target after the right side (zend_delayed_compile_var):
        // only calls in the target run before it
        if (!chainHasCall(self, node.data.lhs)) {
            try self.compileNode(node.data.rhs);
            const place = (try emitPlaceOperands(self, node.data.lhs)).?;
            try emitPlaceCombine(self, place, op_tag);
            return;
        }
        const place = (try emitPlaceOperands(self, node.data.lhs)).?;
        try self.compileNode(node.data.rhs);
        // [operands, value] -> [value, operands]
        if (place.operandCount() > 0) {
            try self.emitOp(.bury);
            try self.emitByte(place.operandCount());
        }
        try emitPlaceCombine(self, place, op_tag);
        return;
    }

    if (target.tag == .array_access) {
        if (op_tag == .question_question_equal and target.data.rhs != 0 and (chainHasCall(self, target.data.lhs) or chainHasCall(self, target.data.rhs))) {
            // a call on the path runs once: its result is both read and
            // written, as php memoizes it
            try compileVivifyChain(self, target.data.lhs);
            try self.compileNode(target.data.rhs);
            try self.emitOp(.dup2);
            try self.emitOp(.array_get_coalesce);
            return emitCoalesceAssignTail(self, node.data.rhs, .array_set);
        }
        if (op_tag == .question_question_equal) {
            // read with coalesce-safe fetch so undefined keys don't warn -
            // recurse on the base too, else a nested `$a[k1][k2] ??= v` warns on
            // the intermediate `$a[k1]` read when k1 is also absent (php's `??=`
            // suppresses the whole read chain)
            try compileCoalesceFetch(self, target.data.lhs);
            try self.compileNode(target.data.rhs);
            try self.emitOp(.array_get_coalesce);
            const skip_jump = try self.emitJump(.jump_if_not_null);
            try self.emitOp(.pop);
            try compileVivifyChain(self, target.data.lhs);
            try self.compileNode(target.data.rhs);
            try self.compileNode(node.data.rhs);
            try self.emitOp(.array_set);
            self.patchJump(skip_jump);
            return;
        }
        {
            const rhs_is_ref = self.ast.nodes[node.data.rhs].tag == .ref_target;
            // `$arr[$key] = &$var` where the ref source is a plain variable:
            // bind the element to $var's storage (a true reference) instead of
            // storing a copy. complex ref sources (&$obj->prop etc) fall through
            if (rhs_is_ref) {
                const ref_inner = self.ast.nodes[self.ast.nodes[node.data.rhs].data.lhs];
                if (ref_inner.tag == .variable) {
                    const vname = self.ast.tokenSlice(ref_inner.main_token);
                    const vidx = try self.addConstant(.{ .string = Value.String.borrowed(vname) });
                    try compileVivifyChain(self, target.data.lhs);
                    try self.compileNode(target.data.rhs);
                    try self.emitOp(.array_bind_ref);
                    try self.emitU16(vidx);
                    return;
                }
                if (ref_inner.tag == .variable_variable) {
                    try compileVivifyChain(self, target.data.lhs);
                    try self.compileNode(target.data.rhs);
                    try self.compileNode(ref_inner.data.lhs);
                    try self.emitOp(.array_bind_ref_var_var);
                    return;
                }
            }
            if (rhs_is_ref and target.data.rhs != 0) {
                const ref_inner = self.ast.nodes[node.data.rhs].data.lhs;
                switch (self.ast.nodes[ref_inner].tag) {
                    .property_access, .array_access, .static_prop_access, .call, .method_call, .static_call => {
                        try compileVivifyChain(self, target.data.lhs);
                        try self.compileNode(target.data.rhs);
                        try compileReferenceSource(self, ref_inner);
                        try self.emitOp(.array_bind_ref_source);
                        return;
                    },
                    else => {},
                }
            }
            const target_lhs = self.ast.nodes[target.data.lhs];
            if (target_lhs.tag == .variable) {
                const var_name = self.ast.tokenSlice(target_lhs.main_token);
                var slot_opt: ?u16 = null;
                if (self.local_slots.get(var_name)) |s| {
                    slot_opt = s;
                } else if (self.arrowCaptureSlot(var_name)) |s| {
                    slot_opt = s;
                } else if (!Compiler.isSuperglobal(var_name) and !self.inFunctionScope() and var_name.len > 0 and var_name[0] == '$') {
                    slot_opt = self.getOrCreateSlot(var_name);
                }
                if (slot_opt) |slot| {
                    try self.compileNode(target.data.rhs);
                    try self.compileNode(node.data.rhs);
                    // ref-assign skips clone so the destination shares the
                    // underlying array pointer (needed for cycle detection
                    // in print_r/var_dump/var_export)
                    try self.emitOp(if (rhs_is_ref) .array_set_local_ref else .array_set_local);
                    try self.emitU16(slot);
                    return;
                }
            }
            // depth-2 chain `$base[k][i] = v` or `$obj->prop[i] = v` —
            // route through array_set_chain so a string at the parent
            // position gets a char-write written back into the parent
            // instead of being clobbered with a new array
            if (target_lhs.tag == .array_access) {
                try compileVivifyChain(self, target_lhs.data.lhs); // push base
                try self.compileNode(target_lhs.data.rhs); // push outer key
                try self.compileNode(target.data.rhs); // push inner key
                try self.compileNode(node.data.rhs); // push value
                try self.emitOp(.array_set_chain);
                return;
            }
            if (target_lhs.tag == .property_access) {
                try compilePropWriteBase(self, target_lhs.data.lhs); // push $obj
                if (self.isDynamicProp(target_lhs)) {
                    try self.compileNode(target_lhs.data.rhs);
                } else {
                    const prop_name = self.propName(target_lhs);
                    const cidx = try self.addConstant(.{ .string = Value.String.borrowed(prop_name) });
                    try self.emitOp(.constant);
                    try self.emitU16(cidx); // push prop name
                }
                try self.compileNode(target.data.rhs); // push inner key
                try self.compileNode(node.data.rhs); // push value
                try self.emitOp(.prop_set_chain);
                return;
            }
            try compileVivifyChain(self, target.data.lhs);
            try self.compileNode(target.data.rhs);
            try self.compileNode(node.data.rhs);
            // a by-name variable may hold a string, whose offset write makes
            // a new string the variable must get
            if (!rhs_is_ref and target_lhs.tag == .variable) {
                const var_name = self.ast.tokenSlice(target_lhs.main_token);
                if (!Compiler.isSuperglobal(var_name) and !std.mem.eql(u8, var_name, "$GLOBALS") and !std.mem.eql(u8, var_name, "$this")) {
                    try self.emitOp(.array_set_var);
                    try self.emitU16(try self.addConstant(.{ .string = Value.String.borrowed(var_name) }));
                    return;
                }
            }
            try self.emitOp(if (rhs_is_ref) .array_set_ref else .array_set);
        }
        return;
    }

    if (target.tag == .property_access) {
        if (op_tag == .equal and self.ast.nodes[node.data.rhs].tag == .ref_target) {
            const ref_inner = self.ast.nodes[self.ast.nodes[node.data.rhs].data.lhs];
            if (ref_inner.tag == .variable or ref_inner.tag == .identifier) {
                const source_idx = try self.addConstant(.{ .string = Value.String.borrowed(self.ast.tokenSlice(ref_inner.main_token)) });
                try compilePropWriteBase(self, target.data.lhs);
                if (self.isDynamicProp(target)) {
                    try self.compileNode(target.data.rhs);
                    try self.emitOp(.prop_bind_ref_dyn);
                } else {
                    const prop_idx = try self.addConstant(.{ .string = Value.String.borrowed(self.propName(target)) });
                    try self.emitOp(.prop_bind_ref);
                    try self.emitU16(prop_idx);
                }
                try self.emitU16(source_idx);
                try self.compileNode(self.ast.nodes[node.data.rhs].data.lhs);
                return;
            }
            switch (ref_inner.tag) {
                .property_access, .array_access, .static_prop_access, .call, .method_call, .static_call => {
                    try self.compileNode(target.data.lhs);
                    const dynamic = self.isDynamicProp(target);
                    if (dynamic) try self.compileNode(target.data.rhs);
                    try compileReferenceSource(self, self.ast.nodes[node.data.rhs].data.lhs);
                    if (dynamic) {
                        try self.emitOp(.prop_bind_ref_source_dyn);
                    } else {
                        try self.emitOp(.prop_bind_ref_source);
                        try self.emitU16(try self.addConstant(.{ .string = Value.String.borrowed(self.propName(target)) }));
                    }
                    return;
                },
                else => {},
            }
        }
        if (self.isDynamicProp(target)) {
            try self.compileNode(target.data.lhs);
            if (op_tag == .question_question_equal) {
                if (target.main_token == 0) {
                    try self.compileNode(target.data.rhs);
                } else {
                    const prop_node = self.ast.nodes[target.data.rhs];
                    try self.emitGetVar(self.ast.tokenSlice(prop_node.main_token));
                }
                try self.emitOp(.dup2);
                try self.emitOp(.get_prop_coalesce_dynamic);
                return emitCoalesceAssignTail(self, node.data.rhs, .set_prop_dynamic);
            }
            // a name in a variable (`->$name = v`) is read as the assignment
            // runs, after the value, as php reads its operand; any other
            // name is evaluated once, before the value
            // compound operators went through emitPlaceCombine
            if (target.main_token != 0) {
                const prop_node = self.ast.nodes[target.data.rhs];
                try self.compileNode(node.data.rhs);
                try self.emitGetVar(self.ast.tokenSlice(prop_node.main_token));
                try self.emitOp(.set_prop_dynamic);
                return;
            }
            try self.compileNode(target.data.rhs);
            try self.compileNode(node.data.rhs);
            // set_prop_dynamic takes the name above the value
            try self.emitOp(.swap);
            try self.emitOp(.set_prop_dynamic);
            return;
        }
        const prop_node = self.ast.nodes[target.data.rhs];
        var prop_name = self.ast.tokenSlice(prop_node.main_token);
        if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
        const name_idx = try self.addConstant(.{ .string = Value.String.borrowed(prop_name) });
        if (op_tag == .question_question_equal) {
            try self.compileNode(target.data.lhs);
            try self.emitOp(.dup);
            // isset-semantics: an uninitialized typed property must not throw
            try self.emitOp(.get_prop_coalesce);
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
        try compilePropWriteBase(self, target.data.lhs);
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
        // dynamic property name: Class::${expr} = v, Class::$$var = v
        if (target.main_token == 0 and target.data.rhs != 0 and op_tag == .equal) {
            if (class_node.tag == .identifier or class_node.tag == .qualified_name) {
                const cn = try resolveNodeClassName(self, class_node);
                const ci = try self.addConstant(.{ .string = Value.String.borrowed(cn) });
                try self.emitOp(.constant);
                try self.emitU16(ci);
            } else {
                try self.compileNode(target.data.lhs);
            }
            try self.compileNode(target.data.rhs);
            try self.compileNode(node.data.rhs);
            try self.emitOp(.set_static_prop_dyn);
            return;
        }
        const class_name = try staticClassOperand(self, class_node);
        var prop_name = self.ast.tokenSlice(target.main_token);
        if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
        const class_idx = try self.addConstant(.{ .string = Value.String.borrowed(class_name) });
        const prop_idx = try self.addConstant(.{ .string = Value.String.borrowed(prop_name) });
        if (op_tag == .equal and self.ast.nodes[node.data.rhs].tag == .ref_target and isReferenceSource(self, self.ast.nodes[node.data.rhs].data.lhs)) {
            try compileReferenceSource(self, self.ast.nodes[node.data.rhs].data.lhs);
            try self.emitOp(.static_prop_bind_ref_source);
            try self.emitU16(class_idx);
            try self.emitU16(prop_idx);
            return;
        }
        if (op_tag == .question_question_equal) {
            // read as isset() reads: an uninitialized typed property is null
            try self.emitOp(.get_static_prop_quiet);
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
            // the read is the left side of ??: no warning when it holds nothing
            const saved = self.quiet_reads;
            self.quiet_reads = true;
            try self.compileGetVar(target);
            self.quiet_reads = saved;
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
    if (op_tag == .dot_equal and (target.tag == .variable or target.tag == .identifier) and !Compiler.isSuperglobal(self.ast.tokenSlice(target.main_token))) {
        try self.compileNode(node.data.rhs);
        const name = self.ast.tokenSlice(target.main_token);
        if (self.inFunctionScope() or (name.len > 0 and name[0] == '$')) {
            try self.emitOp(.concat_assign_local);
            try self.emitU16(self.getOrCreateSlot(name));
            return;
        }
        const idx = try self.addConstant(.{ .string = Value.String.borrowed(name) });
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

    try self.compileNode(node.data.rhs);
    if (op_tag != .equal) {
        // php reads the variable after evaluating the right side
        try self.compileGetVar(target);
        try self.emitOp(.bury);
        try self.emitByte(1);
        try emitCompoundOp(self, op_tag);
    }

    if (target.tag == .variable or target.tag == .identifier) {
        const name = self.ast.tokenSlice(target.main_token);
        // Stage 2 literal-array orphan fix: `$var = [literal]` knows the rhs
        // is a fresh array with no other holder - emit set_local_transfer to
        // skip the runtime copyValue clone. only safe for plain assignment
        // (no compound ops) and only when rhs is array_literal (not a native
        // return or property access where nested arrays might be shared)
        if (!Compiler.isSuperglobal(name) and op_tag == .equal and self.ast.nodes[node.data.rhs].tag == .array_literal and self.inFunctionScope()) {
            const slot = self.getOrCreateSlot(name);
            try self.emitOp(.set_local_transfer);
            try self.emitU16(slot);
            return;
        }
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

// zend_compile_pipe: the operand is evaluated first, as a value. a
// first-class callable of a named function on the right becomes a direct
// call of it with the operand; anything else is called with it
pub fn compilePipeExpr(self: *Compiler, node: Ast.Node) Error!void {
    const callable = self.ast.nodes[node.data.rhs];
    if (callable.tag == .closure_expr and self.ast.tokens[callable.main_token].tag == .kw_fn)
        return self.fail(callable.main_token, "Arrow functions on the right hand side of |> must be parenthesized");
    if (callable.tag == .callable_ref) {
        const callee = self.ast.nodes[callable.data.lhs];
        if (callee.tag == .identifier or callee.tag == .qualified_name) {
            const name = if (callee.tag == .identifier)
                self.resolveFunctionName(self.ast.tokenSlice(callee.main_token))
            else
                try self.resolveQualifiedNonClassName(try self.buildQualifiedString(self.ast.extraSlice(callee.data.lhs)), callee.data.rhs);
            var guards: ArgGuards = .empty;
            errdefer guards.deinit(self.allocator);
            try self.compileNode(node.data.lhs);
            try emitValueGuard(self, .{ .pos = 0, .guards = &guards }, .arg_value);
            const idx = try self.addConstant(.{ .string = Value.String.borrowed(name) });
            return emitCallOp(self, &guards, .call, .{ .a = idx, .argc = 1 });
        }
    }
    try self.compileNode(node.data.lhs);
    try self.compileNode(node.data.rhs);
    // call_indirect takes the callable under its argument
    try self.emitOp(.swap);
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
            const idx = try self.addConstant(.{ .string = Value.String.borrowed(class_name) });
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
        .kw_xor => .logical_xor,
        else => unreachable,
    });
}

// a writable location whose operands (object, name, class) are evaluated once
// and kept on the stack, so a read-modify-write touches each side effect once
const Place = union(enum) {
    var_var, // [name]
    array_elem, // [container, key], the container vivified and separated
    prop: u16, // [object]
    prop_dyn, // [object, name]
    static_prop: struct { class: u16, prop: u16 }, // []
    static_prop_dyn_name: u16, // [name], class constant
    static_prop_dyn_both, // [class, name]

    fn operandCount(self: Place) u8 {
        return switch (self) {
            .static_prop => 0,
            .var_var, .prop, .static_prop_dyn_name => 1,
            .array_elem, .prop_dyn, .static_prop_dyn_both => 2,
        };
    }
};

// pushes the place's operands; null when the target is not a place
fn emitPlaceOperands(self: *Compiler, target_idx: u32) Error!?Place {
    const target = self.ast.nodes[target_idx];
    switch (target.tag) {
        .variable_variable => {
            try self.compileNode(target.data.lhs);
            return .var_var;
        },
        .array_access => {
            if (target.data.rhs == 0) return null;
            try compileVivifyChain(self, target.data.lhs);
            try self.compileNode(target.data.rhs);
            return .array_elem;
        },
        .property_access => {
            try compilePropFetchBase(self, target.data.lhs, true);
            if (!self.isDynamicProp(target)) return .{ .prop = try self.addConstant(.{ .string = Value.String.borrowed(self.propName(target)) }) };
            if (target.main_token == 0) {
                try self.compileNode(target.data.rhs);
            } else {
                try self.emitGetVar(self.ast.tokenSlice(self.ast.nodes[target.data.rhs].main_token));
            }
            return .prop_dyn;
        },
        .static_prop_access => {
            const class_node = self.ast.nodes[target.data.lhs];
            const static_class = class_node.tag == .identifier or class_node.tag == .qualified_name;
            const class_idx: u16 = if (static_class) try self.addConstant(.{ .string = Value.String.borrowed(try resolveNodeClassName(self, class_node)) }) else 0;
            if (target.main_token == 0) {
                if (static_class) {
                    try self.compileNode(target.data.rhs);
                    return .{ .static_prop_dyn_name = class_idx };
                }
                try self.compileNode(target.data.lhs);
                try self.compileNode(target.data.rhs);
                return .static_prop_dyn_both;
            }
            var prop_name = self.ast.tokenSlice(target.main_token);
            if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
            const prop_idx = try self.addConstant(.{ .string = Value.String.borrowed(prop_name) });
            if (static_class) return .{ .static_prop = .{ .class = class_idx, .prop = prop_idx } };
            try self.compileNode(target.data.lhs);
            try self.emitOp(.constant);
            try self.emitU16(prop_idx);
            return .static_prop_dyn_both;
        },
        else => return null,
    }
}

// whether evaluating a write target's container runs a call, so it must be
// evaluated only once
fn chainHasCall(self: *Compiler, node_idx: u32) bool {
    const node = self.ast.nodes[node_idx];
    return switch (node.tag) {
        .variable, .identifier => false,
        .array_access => chainHasCall(self, node.data.lhs) or (node.data.rhs != 0 and chainHasCall(self, node.data.rhs)),
        .property_access => chainHasCall(self, node.data.lhs) or (self.isDynamicProp(node) and node.main_token == 0 and chainHasCall(self, node.data.rhs)),
        .variable_variable => chainHasCall(self, node.data.lhs),
        .integer_literal, .float_literal, .string_literal => false,
        else => true,
    };
}

// the rest of a `??=` on two operands [a, b] with the current value above
// them: when it is null, the right side is stored with `store` (which takes
// [a, b, value] and leaves the value, set_prop_dynamic after a swap);
// otherwise the current value is the result
fn emitCoalesceAssignTail(self: *Compiler, rhs: u32, store: OpCode) Error!void {
    const skip_jump = try self.emitJump(.jump_if_not_null);
    try self.emitOp(.pop);
    try self.compileNode(rhs);
    if (store == .set_prop_dynamic) try self.emitOp(.swap);
    try self.emitOp(store);
    const end_jump = try self.emitJump(.jump);
    self.patchJump(skip_jump);
    try self.emitOp(.bury);
    try self.emitByte(2);
    try self.emitOp(.pop);
    try self.emitOp(.pop);
    self.patchJump(end_jump);
}

// whether emitPlaceOperands takes the target
fn isPlaceTarget(self: *Compiler, target_idx: u32) bool {
    const target = self.ast.nodes[target_idx];
    return switch (target.tag) {
        .variable_variable, .property_access, .static_prop_access => true,
        .array_access => target.data.rhs != 0,
        else => false,
    };
}

// [value, operands] -> [result] for `place op= value`: the target is read
// as the operator runs, after the right side, as php does
fn emitPlaceCombine(self: *Compiler, place: Place, op_tag: Token.Tag) Error!void {
    const k = place.operandCount();
    // -> [value, operands, current]
    try emitPlaceRead(self, place, .assign_op);
    // -> [current, value, operands] -> [operands, current, value]
    try self.emitOp(.bury);
    try self.emitByte(k + 1);
    for (0..k) |_| {
        try self.emitOp(.bury);
        try self.emitByte(k + 1);
    }
    try emitCompoundOp(self, op_tag);
    try emitPlaceWrite(self, place, true);
}

const PlaceAccess = enum(u8) { assign_op = 0, inc_dec = 1 };

// [operands] -> [operands, value], the read of a read-modify-write
fn emitPlaceRead(self: *Compiler, place: Place, access: PlaceAccess) Error!void {
    switch (place.operandCount()) {
        1 => try self.emitOp(.dup),
        2 => try self.emitOp(.dup2),
        else => {},
    }
    switch (place) {
        .var_var => try self.emitOp(.get_var_var),
        .array_elem => {
            try self.emitOp(.check_rw_container);
            try self.emitByte(@intFromEnum(access));
            try self.emitOp(.array_get);
        },
        .prop => |name| {
            // a container that is no object is an Error, not a read
            try self.emitOp(.check_rw_container);
            try self.emitByte(2 + @intFromEnum(access));
            try self.emitOp(.get_prop);
            try self.emitU16(name);
        },
        .prop_dyn => {
            try self.emitOp(.check_rw_container);
            try self.emitByte(4 + @intFromEnum(access));
            try self.emitOp(.get_prop_dynamic);
        },
        .static_prop => |sp| {
            try self.emitOp(.get_static_prop);
            try self.emitU16(sp.class);
            try self.emitU16(sp.prop);
        },
        .static_prop_dyn_name => |class| {
            try self.emitOp(.get_static_prop_dyn_name);
            try self.emitU16(class);
        },
        .static_prop_dyn_both => try self.emitOp(.get_static_prop_dyn_both),
    }
}

// stores the value on top of the stack into a place target and pops it:
// [value] -> []. the place's operands are evaluated after the value, as in
// a foreach or destructuring target
pub fn storeTopInPlace(self: *Compiler, target_idx: u32) Error!void {
    const place = (try emitPlaceOperands(self, target_idx)) orelse unreachable;
    // [value, operands] -> [operands, value]
    for (0..place.operandCount()) |_| {
        try self.emitOp(.bury);
        try self.emitByte(place.operandCount());
    }
    try emitPlaceWrite(self, place, false);
    try self.emitOp(.pop);
}

// [operands, value] -> [value]. rw marks the write of a read-modify-write
fn emitPlaceWrite(self: *Compiler, place: Place, rw: bool) Error!void {
    switch (place) {
        .var_var => {
            try self.emitOp(.swap);
            try self.emitOp(.set_var_var);
        },
        .array_elem => try self.emitOp(.array_set),
        .prop => |name| {
            try self.emitOp(.set_prop);
            try self.emitU16(name);
        },
        .prop_dyn => {
            try self.emitOp(.swap);
            try self.emitOp(.set_prop_dynamic);
        },
        .static_prop => |sp| {
            try self.emitOp(if (rw) .set_static_prop_rw else .set_static_prop);
            try self.emitU16(sp.class);
            try self.emitU16(sp.prop);
        },
        .static_prop_dyn_name => |class| {
            // set_static_prop_dyn takes [class, name, value]
            try self.emitOp(.constant);
            try self.emitU16(class);
            try self.emitOp(.bury);
            try self.emitByte(2);
            try self.emitOp(.set_static_prop_dyn);
        },
        .static_prop_dyn_both => try self.emitOp(.set_static_prop_dyn),
    }
}

// ++/-- on a place: leaves the new value, or the old one for postfix
fn compilePlaceIncDec(self: *Compiler, place: Place, op_tag: Token.Tag, postfix: bool) Error!void {
    try emitPlaceRead(self, place, .inc_dec);
    if (postfix) {
        try self.emitOp(.dup);
        try self.emitOp(.bury);
        try self.emitByte(place.operandCount() + 1);
    }
    try self.emitOp(if (op_tag == .plus_plus) .inc_value else .dec_value);
    try emitPlaceWrite(self, place, true);
    if (postfix) try self.emitOp(.pop);
}

// the write-context fatals php raises at compile time for an increment or
// decrement whose operand is not a variable
fn checkIncDecTarget(self: *Compiler, target_idx: u32, op_token: u32) Error!void {
    return ensureWritable(self, target_idx, op_token);
}

// zend_ensure_writable_variable
pub fn ensureWritable(self: *Compiler, target_idx: u32, op_token: u32) Error!void {
    switch (self.ast.nodes[target_idx].tag) {
        .call, .pipe_expr => return self.fail(op_token, "Can't use function return value in write context"),
        .method_call, .static_call, .dynamic_static_call, .nullsafe_method_call => return self.fail(op_token, "Can't use method return value in write context"),
        else => {},
    }
    if (isShortCircuited(self, target_idx)) return self.fail(op_token, "Can't use nullsafe operator in write context");
    if (isGlobalsFetch(self, target_idx)) return self.fail(op_token, "$GLOBALS can only be modified using the $GLOBALS[$name] = $value syntax");
    const target = self.ast.nodes[target_idx];
    if (target.tag == .array_push_target and isGlobalsFetch(self, target.data.lhs)) return self.fail(op_token, "Cannot append to $GLOBALS");
    try checkTemporaryBase(self, target_idx, op_token);
}

// is_globals_fetch: the variable $GLOBALS itself
pub fn isGlobalsFetch(self: *Compiler, idx: u32) bool {
    const n = self.ast.nodes[idx];
    return n.tag == .variable and std.mem.eql(u8, self.ast.tokenSlice(n.main_token), "$GLOBALS");
}

// the variables a list assignment writes, as ensureWritable checks them
fn ensureListWritable(self: *Compiler, idx: u32, op_token: u32) Error!void {
    if (idx == 0) return;
    const n = self.ast.nodes[idx];
    switch (n.tag) {
        .list_destructure, .array_literal => for (self.ast.extraSlice(n.data.lhs)) |slot| try ensureListWritable(self, slot, op_token),
        .array_element => try ensureListWritable(self, n.data.lhs, op_token),
        .ref_target => {
            if (isGlobalsFetch(self, n.data.lhs)) return self.fail(op_token, "Cannot assign reference to non referenceable value");
            try ensureListWritable(self, n.data.lhs, op_token);
        },
        else => if (isGlobalsFetch(self, idx)) return self.fail(op_token, "$GLOBALS can only be modified using the $GLOBALS[$name] = $value syntax"),
    }
}

// zend_compile_var_inner in a write context: the innermost container of a
// dimension or property chain must be a variable or a call's result
pub fn checkTemporaryBase(self: *Compiler, target_idx: u32, op_token: u32) Error!void {
    var idx = target_idx;
    var chained = false;
    while (true) {
        const n = self.ast.nodes[idx];
        switch (n.tag) {
            .array_access, .array_push_target, .property_access, .nullsafe_property_access => {
                idx = n.data.lhs;
                chained = true;
            },
            .grouped_expr => idx = n.data.lhs,
            .variable, .variable_variable, .call, .method_call, .nullsafe_method_call, .static_call, .dynamic_static_call, .pipe_expr => return,
            // Class::$p is a variable, Class::C (the same node) a constant
            .static_prop_access => {
                const member = if (n.main_token != 0) self.ast.tokenSlice(n.main_token) else "$";
                if (member.len > 0 and member[0] == '$') return;
                if (chained) return self.fail(op_token, "Cannot use temporary expression in write context");
                return;
            },
            else => {
                if (chained) return self.fail(op_token, "Cannot use temporary expression in write context");
                return;
            },
        }
    }
}

// zend_ast_is_short_circuited: a nullsafe link anywhere down the chain
pub fn isShortCircuited(self: *Compiler, target_idx: u32) bool {
    var idx = target_idx;
    while (idx != 0) {
        const n = self.ast.nodes[idx];
        switch (n.tag) {
            .nullsafe_property_access, .nullsafe_method_call => return true,
            .property_access, .array_access, .method_call, .static_prop_access, .static_call, .array_push_target => idx = n.data.lhs,
            else => return false,
        }
    }
    return false;
}

fn listHasRef(self: *Compiler, idx: u32) bool {
    if (idx == 0) return false;
    const n = self.ast.nodes[idx];
    return switch (n.tag) {
        .ref_target => true,
        .list_destructure, .array_literal => for (self.ast.extraSlice(n.data.lhs)) |slot| {
            if (listHasRef(self, slot)) break true;
        } else false,
        .array_element => listHasRef(self, n.data.lhs),
        else => false,
    };
}

// zend_assert_not_short_circuited, for the source of a reference
pub fn assertNotShortCircuited(self: *Compiler, idx: u32, op_token: u32) Error!void {
    if (isShortCircuited(self, idx)) return self.fail(op_token, "Cannot take reference of a nullsafe chain");
}

pub fn compilePrefixOp(self: *Compiler, node: Ast.Node) Error!void {
    const op_tag = self.ast.tokens[node.main_token].tag;

    if (op_tag == .plus_plus or op_tag == .minus_minus) {
        try checkIncDecTarget(self, node.data.lhs, node.main_token);
        const target = self.ast.nodes[node.data.lhs];
        if (try emitPlaceOperands(self, node.data.lhs)) |place| return compilePlaceIncDec(self, place, op_tag, false);
        if (target.tag == .array_access) {
            // COW: the base consumed by array_set (this first load) must be
            // separated; the second load feeds the read-only array_get
            try compileVivifyChain(self, target.data.lhs);
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
    switch (op_tag) {
        // unary `+` coerces to numeric per PHP. an integer/float passes through;
        // a numeric string converts via +0. emit `0 + operand` to leverage the
        // existing arithmetic coercion path without a dedicated opcode
        .plus => {
            const zero_idx = try self.addConstant(.{ .int = 0 });
            try self.emitOp(.constant);
            try self.emitU16(zero_idx);
            try self.emitOp(.add);
        },
        .minus => try self.emitOp(.negate),
        .bang => try self.emitOp(.not),
        .tilde => try self.emitOp(.bit_not),
        else => unreachable,
    }
}

pub fn compilePostfixOp(self: *Compiler, node: Ast.Node) Error!void {
    try checkIncDecTarget(self, node.data.lhs, node.main_token);
    const target = self.ast.nodes[node.data.lhs];
    const op_tag = self.ast.tokens[node.main_token].tag;

    if (target.tag == .array_access) {
        // COW: vivify-load the base so a shared array is separated (and written
        // back to its slot) before the in-place element inc/dec
        try compileVivifyChain(self, target.data.lhs);
        try self.compileNode(target.data.rhs);
        try self.emitOp(if (op_tag == .plus_plus) .array_elem_inc else .array_elem_dec);
        return;
    }
    if (try emitPlaceOperands(self, node.data.lhs)) |place| return compilePlaceIncDec(self, place, op_tag, true);

    // the variable is read once: the read is the expression's value and the
    // stepped copy goes back into the variable
    try self.compileNode(node.data.lhs);
    if (target.tag != .variable) {
        try self.compileNode(node.data.lhs);
        try self.emitOp(if (op_tag == .plus_plus) .inc_value else .dec_value);
        return;
    }
    try self.emitOp(.dup);
    try self.emitOp(if (op_tag == .plus_plus) .inc_value else .dec_value);
    try self.emitSetVar(self.ast.tokenSlice(target.main_token));
    try self.emitOp(.pop);
}

// the truth of a literal operand, which php's zend_compile_short_circuiting
// decides at compile time: `0 && x` is false without compiling x at all
fn literalTruth(self: *Compiler, idx: u32) ?bool {
    const n = self.ast.nodes[idx];
    switch (n.tag) {
        .grouped_expr => return literalTruth(self, n.data.lhs),
        .true_literal => return true,
        .false_literal, .null_literal => return false,
        .integer_literal, .float_literal => return self.evalConstExpr(idx).isTruthy(),
        .string_literal => {
            const raw = self.ast.tokenSlice(n.main_token);
            if (raw.len < 2 or raw[0] != '\'') return null;
            return self.evalConstExpr(idx).isTruthy();
        },
        else => return null,
    }
}

pub fn compileLogicalAnd(self: *Compiler, node: Ast.Node) Error!void {
    if (literalTruth(self, node.data.lhs) == false) {
        try self.emitOp(.op_false);
        return;
    }
    try self.compileNode(node.data.lhs);
    const end_jump = try self.emitJump(.jump_if_false);
    try self.emitOp(.pop_boundary);
    try self.compileNode(node.data.rhs);
    self.patchJump(end_jump);
    try self.emitOp(.cast_bool);
}

pub fn compileLogicalOr(self: *Compiler, node: Ast.Node) Error!void {
    if (literalTruth(self, node.data.lhs) == true) {
        try self.emitOp(.op_true);
        return;
    }
    try self.compileNode(node.data.lhs);
    const end_jump = try self.emitJump(.jump_if_true);
    try self.emitOp(.pop_boundary);
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
    // A property read under `??` uses isset-semantics: an
    // uninitialized typed property must read as null, not throw. recurse so a
    // chain `$a->b->c ?? x` is non-throwing all the way down
    if (n.tag == .property_access) {
        try compileCoalesceFetch(self, n.data.lhs);
        if (self.isDynamicProp(n)) {
            try self.compileNode(n.data.rhs);
            try self.emitOp(.get_prop_coalesce_dynamic);
        } else {
            const name_idx = try self.addConstant(.{ .string = Value.String.borrowed(self.propName(n)) });
            try self.emitOp(.get_prop_coalesce);
            try self.emitU16(name_idx);
        }
        return;
    }
    if (n.tag == .variable_variable) {
        try self.compileNode(n.data.lhs);
        return self.emitOp(.get_var_var_quiet);
    }
    if (n.tag == .variable) {
        const saved = self.quiet_reads;
        self.quiet_reads = true;
        defer self.quiet_reads = saved;
        return self.compileNode(node_idx);
    }
    if (n.tag == .nullsafe_property_access) return compileNullsafePropertyFetch(self, n, true);
    if (n.tag == .static_prop_access) return compileStaticPropRead(self, n, true);
    try self.compileNode(node_idx);
}

// Descend through dimensions, but stop at object interiors: mutating
// $o->restricted->field[k] does not mutate $o->restricted itself.
// the container of an unset($c[..][k]): every array on the path is
// separated from its co-holders (the root by the caller for a variable),
// and nothing missing is created
fn compileUnsetDimensionBase(self: *Compiler, node_idx: u32) Error!void {
    const node = self.ast.nodes[node_idx];
    if (node.tag == .array_access) {
        try compileUnsetDimensionBase(self, node.data.lhs);
        try self.compileNode(node.data.rhs);
        try self.emitOp(.array_get_unset);
    } else if (node.tag == .property_access) {
        try self.compileNode(node.data.lhs);
        if (self.isDynamicProp(node)) {
            try self.compileNode(node.data.rhs);
        } else {
            try self.emitConstant(try self.addConstant(.{ .string = Value.String.borrowed(self.propName(node)) }));
        }
        try self.emitOp(.check_prop_dimension);
        try self.emitOp(.separate_prop_array);
        try self.emitOp(.get_prop_coalesce_dynamic);
    } else if (node.tag == .static_prop_access and node.main_token != 0 and self.ast.nodes[node.data.lhs].tag != .variable) {
        const class_name = try staticClassOperand(self, self.ast.nodes[node.data.lhs]);
        var prop_name = self.ast.tokenSlice(node.main_token);
        if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
        try self.emitOp(.separate_static_prop);
        try self.emitU16(try self.addConstant(.{ .string = Value.String.borrowed(class_name) }));
        try self.emitU16(try self.addConstant(.{ .string = Value.String.borrowed(prop_name) }));
        try compileCoalesceFetch(self, node_idx);
    } else if (node.tag == .variable and !std.mem.eql(u8, self.ast.tokenSlice(node.main_token), "$this")) {
        // the root variable is fetched for unset, which warns when it is
        // undefined
        try self.compileNode(node_idx);
    } else {
        try compileCoalesceFetch(self, node_idx);
    }
}

pub fn compileTernary(self: *Compiler, node: Ast.Node) Error!void {
    const then_node = self.ast.extra_data[node.data.rhs];
    const else_node = self.ast.extra_data[node.data.rhs + 1];

    // zend_compile_conditional: a ternary in an unparenthesized ternary's
    // condition is refused, except two short ones
    const cond = self.ast.nodes[node.data.lhs];
    if (cond.tag == .ternary) {
        const inner_full = self.ast.extra_data[cond.data.rhs] != 0;
        if (inner_full and then_node != 0) return self.fail(node.main_token, "Unparenthesized `a ? b : c ? d : e` is not supported. Use either `(a ? b : c) ? d : e` or `a ? b : (c ? d : e)`");
        if (inner_full) return self.fail(node.main_token, "Unparenthesized `a ? b : c ?: d` is not supported. Use either `(a ? b : c) ?: d` or `a ? b : (c ?: d)`");
        if (then_node != 0) return self.fail(node.main_token, "Unparenthesized `a ?: b ? c : d` is not supported. Use either `(a ?: b) ? c : d` or `a ?: (b ? c : d)`");
    }

    try self.compileNode(node.data.lhs);

    if (then_node != 0) {
        const else_jump = try self.emitJump(.jump_if_false);
        try self.emitOp(.pop_boundary);
        try self.compileNode(then_node);
        const end_jump = try self.emitJump(.jump);
        self.patchJump(else_jump);
        try self.emitOp(.pop_boundary);
        try self.compileNode(else_node);
        self.patchJump(end_jump);
    } else {
        // short ternary: $a ?: $b - reuse the condition value if truthy
        const end_jump = try self.emitJump(.jump_if_true);
        try self.emitOp(.pop_boundary);
        try self.compileNode(else_node);
        self.patchJump(end_jump);
    }
}

// natives that mutate their array argument in place (arg 0). under COW the
// caller's variable may share that array, so the arg must be separated first.
// the compiler emits a separating vivify-load (ensure_array_local) for arg 0
// when the arg is a simple variable / array element, which writes the unshared
// array back to the slot and pushes it - the native then mutates an unshared
// array and the caller's variable reflects the result
fn cowByRefArg0(name: []const u8) bool {
    return @import("../stdlib/byref_args.zig").arg0IsByRef(name);
}

// an lvalue argument (variable, property or dimension chain) is lowered as
// its ordinary read preceded by a guard that names the call it feeds. the
// runtime resolves the callee's by-reference intent for that position before
// the read runs: by value leaves the read untouched, otherwise the read
// records provenance the call binds from. the call opcode is not placed until
// every argument is emitted, so the guards' delta fields are patched afterwards
pub const ArgGuards = std.ArrayListUnmanaged(u32);

pub const ArgPos = struct {
    pub const spread: u8 = 0xFF;
    pub const named: u8 = 0xFE;
    pub const max: u8 = 0xFD;
};

// by_value: the compiler knows the callee takes this argument by value
const ArgGuard = struct { pos: u8, guards: *ArgGuards, by_value: bool = false };

fn emitArgGuard(self: *Compiler, guard: ArgGuard, op: OpCode) Error!void {
    try self.emitOp(op);
    try guard.guards.append(self.allocator, @intCast(self.chunk.offset()));
    try self.emitU16(0);
    try self.emitByte(guard.pos);
}

fn patchArgGuards(self: *Compiler, guards: *ArgGuards, call_ip: usize) void {
    for (guards.items) |field| {
        const delta = call_ip - field;
        if (delta > 0xFFFF) continue;
        self.chunk.code.items[field] = @intCast(delta >> 8);
        self.chunk.code.items[field + 1] = @intCast(delta & 0xff);
    }
    guards.deinit(self.allocator);
}

const CallOperands = struct { a: ?u16 = null, b: ?u16 = null, argc: ?u8 = null };

fn emitCallOp(self: *Compiler, guards: *ArgGuards, op: OpCode, operands: CallOperands) Error!void {
    const call_ip = self.chunk.offset();
    try self.emitOp(op);
    if (operands.a) |a| try self.emitU16(a);
    if (operands.b) |b| try self.emitU16(b);
    if (operands.argc) |argc| try self.emitByte(argc);
    patchArgGuards(self, guards, call_ip);
}

fn compileArgLvalue(self: *Compiler, arg_idx: u32, guard: ArgGuard) Error!void {
    const arg = self.ast.nodes[arg_idx];
    switch (arg.tag) {
        .property_access => try compilePropertyFetch(self, arg, guard),
        .array_access => {
            try compileArgLvalue(self, arg.data.lhs, guard);
            try self.compileNode(arg.data.rhs);
            try emitArgGuard(self, guard, .arg_guard_dim);
            try self.emitOp(.array_get);
        },
        .array_push_target => {
            try compileArgLvalue(self, arg.data.lhs, guard);
            try emitArgGuard(self, guard, .arg_append);
        },
        .static_prop_access => {
            const class_node = self.ast.nodes[arg.data.lhs];
            // Class::CONST is a static_prop_access too; a property is `$name`
            const member = if (arg.main_token != 0) self.ast.tokenSlice(arg.main_token) else "";
            const named = member.len > 1 and member[0] == '$' and (class_node.tag == .identifier or class_node.tag == .qualified_name);
            try self.compileNode(arg_idx);
            // a class constant is a value; `$o::$p` a property all the same
            if (!named) {
                if (member.len > 0 and member[0] == '$') return;
                return emitValueGuard(self, guard, .arg_value);
            }
            const prop_name = member[1..];
            try self.emitOp(.arg_guard_static_prop);
            try self.emitU16(try self.addConstant(.{ .string = Value.String.borrowed(try resolveNodeClassName(self, class_node)) }));
            try self.emitU16(try self.addConstant(.{ .string = Value.String.borrowed(prop_name) }));
            try guard.guards.append(self.allocator, @intCast(self.chunk.offset()));
            try self.emitU16(0);
            try self.emitByte(guard.pos);
        },
        .variable => {
            try self.compileNode(arg_idx);
            try self.emitOp(.arg_variable);
            try self.emitU16(try self.addConstant(.{ .string = Value.String.borrowed(self.ast.tokenSlice(arg.main_token)) }));
            try guard.guards.append(self.allocator, @intCast(self.chunk.offset()));
            try self.emitU16(0);
            try self.emitByte(guard.pos);
        },
        else => {
            try self.compileNode(arg_idx);
            // what php sends where the callee takes a reference: a call's
            // result, with a notice unless it returned one, or a value, which
            // is an Error
            switch (argSendKind(self, arg_idx)) {
                .call => try emitValueGuard(self, guard, .arg_call_result),
                .value => try emitValueGuard(self, guard, .arg_value),
                .reference => {},
            }
        },
    }
}

// a guard for an argument that can't be a reference, unless the compiler
// knows the callee takes it by value (php's SEND_VAL) or the position is
// a spread or named one, which the guard can't place
fn emitValueGuard(self: *Compiler, guard: ArgGuard, op: OpCode) Error!void {
    if (guard.by_value or guard.pos >= ArgPos.named) return;
    try emitArgGuard(self, guard, op);
}

const SendKind = enum { reference, call, value };

// how zend_compile_args sends an argument that is no plain variable: a call
// (or `new`, include, eval: an IS_VAR) by SEND_VAR_NO_REF, a reference
// assignment as the reference it makes, anything else as a value
fn argSendKind(self: *Compiler, idx: u32) SendKind {
    const node = self.ast.nodes[idx];
    return switch (node.tag) {
        .grouped_expr => switch (self.ast.nodes[node.data.lhs].tag) {
            .variable, .variable_variable, .array_access, .property_access, .static_prop_access, .nullsafe_property_access => .reference,
            else => argSendKind(self, node.data.lhs),
        },
        .variable, .variable_variable, .array_access, .array_push_target, .property_access, .static_prop_access, .nullsafe_property_access, .ref_target => .reference,
        .assign => if (self.ast.nodes[node.data.rhs].tag == .ref_target) .reference else .value,
        .call => if (compilesToInstruction(self, node)) .value else .call,
        .method_call, .static_call, .dynamic_static_call, .nullsafe_method_call, .new_expr, .new_expr_dynamic, .anonymous_class, .require_expr => .call,
        else => .value,
    };
}

// zend_try_compile_special_func: a call to one of these builtins compiles
// to an instruction whose result is a temporary, so it is sent as a value
fn compilesToInstruction(self: *Compiler, node: Ast.Node) bool {
    const callee = self.ast.nodes[node.data.lhs];
    if (callee.tag != .identifier) return false;
    const raw = self.ast.tokenSlice(callee.main_token);
    const qualified = raw.len > 0 and raw[0] == '\\';
    const name = if (qualified) raw[1..] else raw;
    if (std.mem.indexOfScalar(u8, name, '\\') != null) return false;
    if (!qualified and self.namespace.len > 0) return false;
    const args = self.ast.extraSlice(node.data.rhs);
    for (args) |a| if (self.ast.nodes[a].tag == .splat_expr) return false;
    const Special = struct { name: []const u8, args: usize };
    const specials = [_]Special{
        .{ .name = "strlen", .args = 1 },        .{ .name = "is_null", .args = 1 },      .{ .name = "is_bool", .args = 1 },
        .{ .name = "is_long", .args = 1 },       .{ .name = "is_int", .args = 1 },       .{ .name = "is_integer", .args = 1 },
        .{ .name = "is_float", .args = 1 },      .{ .name = "is_double", .args = 1 },    .{ .name = "is_string", .args = 1 },
        .{ .name = "is_array", .args = 1 },      .{ .name = "is_object", .args = 1 },    .{ .name = "is_resource", .args = 1 },
        .{ .name = "is_scalar", .args = 1 },     .{ .name = "boolval", .args = 1 },      .{ .name = "intval", .args = 1 },
        .{ .name = "floatval", .args = 1 },      .{ .name = "doubleval", .args = 1 },    .{ .name = "strval", .args = 1 },
        .{ .name = "defined", .args = 1 },       .{ .name = "chr", .args = 1 },          .{ .name = "ord", .args = 1 },
        .{ .name = "count", .args = 1 },         .{ .name = "sizeof", .args = 1 },       .{ .name = "gettype", .args = 1 },
        .{ .name = "get_called_class", .args = 0 }, .{ .name = "func_num_args", .args = 0 }, .{ .name = "func_get_args", .args = 0 },
        .{ .name = "array_key_exists", .args = 2 },
    };
    for (specials) |sp| if (args.len == sp.args and std.ascii.eqlIgnoreCase(name, sp.name)) return true;
    return std.ascii.eqlIgnoreCase(name, "get_class") and args.len <= 1;
}

// whether php already knows, while compiling a call, that the callee takes
// the argument at pos by value: an internal function, or one declared at the
// top of this file before the call. an unqualified name inside a namespace
// is resolved only when the call runs
fn argKnownByValue(self: *Compiler, raw_name: []const u8, pos: usize, call_token: u32) bool {
    const qualified = raw_name.len > 0 and raw_name[0] == '\\';
    const name = if (qualified) raw_name[1..] else raw_name;
    if (std.mem.indexOfScalar(u8, name, '\\') != null) return false;
    if (!qualified and self.namespace.len > 0) return false;
    for (self.ast.extraSlice(self.ast.nodes[0].data.lhs)) |stmt| {
        const decl = self.ast.nodes[stmt];
        if (decl.tag != .function_decl or decl.main_token > call_token) continue;
        if (!std.ascii.eqlIgnoreCase(self.ast.tokenSlice(decl.main_token), name)) continue;
        const params = self.ast.extraSlice(decl.data.lhs);
        if (pos < params.len) return self.ast.nodes[params[pos]].data.rhs & 2 == 0;
        if (params.len == 0) return true;
        const last = self.ast.nodes[params[params.len - 1]].data.rhs;
        return last & 1 == 0 or last & 2 == 0;
    }
    var lower_buf: [128]u8 = undefined;
    if (name.len > lower_buf.len) return false;
    const sig = native_signatures.map.get(std.ascii.lowerString(&lower_buf, name)) orelse return false;
    if (pos < sig.params.len) return !sig.params[pos].by_ref;
    if (sig.params.len == 0) return true;
    const last = sig.params[sig.params.len - 1];
    return !last.variadic or !last.by_ref;
}

const native_signatures = @import("../stdlib/native_params_generated.zig");

fn compileArgs(self: *Compiler, args: []const u32) Error!ArgGuards {
    return compileArgsFor(self, args, null);
}

const KnownCallee = struct { raw_name: []const u8, token: u32 };

fn compileArgsFor(self: *Compiler, args: []const u32, callee: ?KnownCallee) Error!ArgGuards {
    var guards: ArgGuards = .empty;
    errdefer guards.deinit(self.allocator);
    for (args, 0..) |arg, i| {
        const pos: u8 = if (i <= ArgPos.max) @intCast(i) else ArgPos.spread;
        const by_value = if (callee) |c| argKnownByValue(self, c.raw_name, i, c.token) else false;
        try compileArgLvalue(self, arg, .{ .pos = pos, .guards = &guards, .by_value = by_value });
    }
    return guards;
}

pub fn compileCall(self: *Compiler, node: Ast.Node) Error!void {
    const callee = self.ast.nodes[node.data.lhs];
    if (isAssertCall(self, callee)) return compileAssert(self, node);
    return compileCallPlain(self, node);
}

// a call php compiles with zend_compile_assert: `assert` unqualified (which
// may still find a namespaced assert() at run time) or `\assert`
fn isAssertCall(self: *Compiler, callee: Ast.Node) bool {
    if (callee.tag == .identifier) {
        const raw = self.ast.tokenSlice(callee.main_token);
        return std.ascii.eqlIgnoreCase(raw, "assert") and self.use_fn_aliases.get(raw) == null;
    }
    if (callee.tag != .qualified_name or callee.data.rhs != 1) return false;
    const parts = self.ast.extraSlice(callee.data.lhs);
    return parts.len == 1 and std.ascii.eqlIgnoreCase(self.ast.tokenSlice(parts[0]), "assert");
}

// zend_compile_assert: the call runs only while zend.assertions is 1
// (assert_check skips it, leaving true), and a call with only the assertion
// gets "assert(<the assertion as source>)" as its description
fn compileAssert(self: *Compiler, node: Ast.Node) Error!void {
    const callee = self.ast.nodes[node.data.lhs];
    const args = self.ast.extraSlice(node.data.rhs);
    const check = try self.emitJump(.assert_check);
    const arg_tag = if (args.len == 1) self.ast.nodes[args[0]].tag else Ast.Node.Tag.splat_expr;
    if (arg_tag == .splat_expr) {
        try compileCallPlain(self, node);
        self.patchJump(check);
        return;
    }
    const message = try @import("ast_export.zig").assertMessage(self.allocator, self.ast, args[0]);
    try self.string_allocs.append(self.allocator, message);
    const call_offset = self.current_source_offset;
    const name = if (callee.tag == .identifier) self.resolveFunctionName(self.ast.tokenSlice(callee.main_token)) else "assert";
    const name_idx = try self.addConstant(.{ .string = Value.String.borrowed(name) });
    const message_idx = try self.addConstant(.{ .string = Value.String.borrowed(message) });
    if (arg_tag == .named_arg) {
        // a named assertion gets a named description, as positional after
        // named isn't allowed
        var guards = try emitSpreadArgs(self, args);
        try self.emitConstant(try self.addConstant(.{ .string = Value.String.borrowed("description") }));
        try self.emitConstant(message_idx);
        try self.emitOp(.arg_array_set);
        self.current_source_offset = call_offset;
        try emitCallOp(self, &guards, .call_spread, .{ .a = name_idx });
    } else {
        var guards = try compileArgsFor(self, args, null);
        try self.emitConstant(message_idx);
        self.current_source_offset = call_offset;
        try emitCallOp(self, &guards, .call, .{ .a = name_idx, .argc = 2 });
    }
    self.patchJump(check);
}

fn compileCallPlain(self: *Compiler, node: Ast.Node) Error!void {
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
            // an array element or static-name property read uses isset-
            // semantics here: an undefined key or an uninitialized typed
            // property must not warn/throw, just count as empty
            if (arg.tag == .variable or arg.tag == .array_access or arg.tag == .static_prop_access or arg.tag == .nullsafe_property_access or (arg.tag == .property_access and !self.isDynamicProp(arg))) {
                try compileCoalesceFetch(self, args[0]);
                try self.emitOp(.cast_bool);
                try self.emitOp(.not);
                return;
            }
        }
    }

    if (callee.tag == .identifier and std.mem.eql(u8, self.ast.tokenSlice(callee.main_token), "isset")) {
        // zend_compile_isset_or_empty: only a variable has a value to test
        for (args) |arg_idx| {
            var arg = self.ast.nodes[arg_idx];
            while (arg.tag == .grouped_expr) arg = self.ast.nodes[arg.data.lhs];
            const variable = switch (arg.tag) {
                .variable, .variable_variable, .array_access, .array_push_target, .property_access, .nullsafe_property_access => true,
                .static_prop_access => arg.main_token == 0 or self.ast.tokens[arg.main_token].tag == .variable,
                else => false,
            };
            if (!variable) return self.fail(callee.main_token, "Cannot use isset() on the result of an expression (you can use \"null !== expression\" instead)");
        }
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
                        try compileCoalesceFetch(self, arg.data.lhs);
                        const prop_name = self.propName(arg);
                        const prop_idx = try self.addConstant(.{ .string = Value.String.borrowed(prop_name) });
                        try self.emitOp(.isset_prop);
                        try self.emitU16(prop_idx);
                    }
                } else if (arg.tag == .array_access) {
                    // Fetch each chain link once: hooks are reads, not a separate
                    // existence probe followed by another getter invocation.
                    try compileCoalesceFetch(self, arg.data.lhs);
                    try self.compileNode(arg.data.rhs);
                    try self.emitOp(.isset_index);
                } else {
                    try compileCoalesceFetch(self, arg_idx);
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

    if (!hasSplatOrNamed(self.ast, args) and isGlobalSprintf(self, callee) and try compileSprintfRope(self, args)) return;

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
            var guards = try emitSpreadArgs(self, args);
            try emitCallOp(self, &guards, .method_call_dynamic_spread, .{});
        } else if (callee.tag == .identifier) {
            const raw_name = self.ast.tokenSlice(callee.main_token);
            const name = self.resolveFunctionName(raw_name);
            const idx = try self.addConstant(.{ .string = Value.String.borrowed(name) });
            var guards = try emitSpreadArgs(self, args);
            try emitCallOp(self, &guards, .call_spread, .{ .a = idx });
        } else if (callee.tag == .qualified_name) {
            const parts = self.ast.extraSlice(callee.data.lhs);
            const fqn = try self.buildQualifiedString(parts);
            const name = try self.resolveQualifiedNonClassName(fqn, callee.data.rhs);
            const idx = try self.addConstant(.{ .string = Value.String.borrowed(name) });
            var guards = try emitSpreadArgs(self, args);
            try emitCallOp(self, &guards, .call_spread, .{ .a = idx });
        } else if (callee.tag == .static_prop_access and callee.main_token != 0 and self.ast.tokens[callee.main_token].tag == .variable) {
            const class_node = self.ast.nodes[callee.data.lhs];
            const var_name = self.ast.tokenSlice(callee.main_token);
            if (class_node.tag == .variable) {
                try self.compileNode(callee.data.lhs);
            } else {
                const class_name = try resolveNodeClassName(self, class_node);
                const cn_idx = try self.addConstant(.{ .string = Value.String.borrowed(class_name) });
                try self.emitOp(.constant);
                try self.emitU16(cn_idx);
            }
            try self.emitGetVar(var_name);
            var guards = try emitSpreadArgs(self, args);
            try emitCallOp(self, &guards, .static_call_dyn_both_spread, .{});
        } else {
            // the callable is evaluated after its argument array, matching
            // call_indirect_spread's pop order
            var guards = try emitSpreadArgs(self, args);
            try self.compileNode(node.data.lhs);
            try emitCallOp(self, &guards, .call_indirect_spread, .{});
        }
    } else if (callee.tag == .identifier) {
        const call_offset = self.current_source_offset;
        const raw_name = self.ast.tokenSlice(callee.main_token);
        const name = self.resolveFunctionName(raw_name);
        for (args, 0..) |arg, i| {
            const arg_node = self.ast.nodes[arg];
            if (arg_node.tag == .array_push_target and argKnownByValue(self, raw_name, i, callee.main_token))
                return self.fail(arg_node.main_token, "Cannot use [] for reading");
        }
        var guards = try compileArgsFor(self, args, .{ .raw_name = raw_name, .token = callee.main_token });
        self.current_source_offset = call_offset;
        const idx = try self.addConstant(.{ .string = Value.String.borrowed(name) });
        try emitCallOp(self, &guards, .call, .{ .a = idx, .argc = @intCast(args.len) });
    } else if (callee.tag == .qualified_name) {
        const call_offset = self.current_source_offset;
        const parts = self.ast.extraSlice(callee.data.lhs);
        const fqn = try self.buildQualifiedString(parts);
        const name = try self.resolveQualifiedNonClassName(fqn, callee.data.rhs);
        var guards = try compileArgs(self, args);
        self.current_source_offset = call_offset;
        const idx = try self.addConstant(.{ .string = Value.String.borrowed(name) });
        try emitCallOp(self, &guards, .call, .{ .a = idx, .argc = @intCast(args.len) });
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
        var guards = try compileArgs(self, args);
        self.current_source_offset = call_offset;
        try emitCallOp(self, &guards, .method_call_dynamic, .{ .argc = @intCast(args.len) });
    } else if (callee.tag == .static_prop_access and callee.main_token != 0 and self.ast.tokens[callee.main_token].tag == .variable) {
        const call_offset = self.current_source_offset;
        const class_node = self.ast.nodes[callee.data.lhs];
        const var_name = self.ast.tokenSlice(callee.main_token);
        if (class_node.tag == .variable) {
            try self.compileNode(callee.data.lhs);
            try self.emitGetVar(var_name);
            var guards = try compileArgs(self, args);
            self.current_source_offset = call_offset;
            try emitCallOp(self, &guards, .static_call_dyn_both, .{ .argc = @intCast(args.len) });
        } else {
            const class_name = try resolveNodeClassName(self, class_node);
            const class_idx = try self.addConstant(.{ .string = Value.String.borrowed(class_name) });
            try self.emitGetVar(var_name);
            var guards = try compileArgs(self, args);
            self.current_source_offset = call_offset;
            try emitCallOp(self, &guards, .static_call_dyn_method, .{ .a = class_idx, .argc = @intCast(args.len) });
        }
    } else {
        const call_offset = self.current_source_offset;
        try self.compileNode(node.data.lhs);
        var guards = try compileArgs(self, args);
        self.current_source_offset = call_offset;
        try emitCallOp(self, &guards, .call_indirect, .{ .argc = @intCast(args.len) });
    }
}

// a call that names php's own sprintf at compile time: unqualified outside a
// namespace, imported, or fully qualified
fn isGlobalSprintf(self: *Compiler, callee: Ast.Node) bool {
    if (callee.tag == .identifier) {
        return std.ascii.eqlIgnoreCase(self.resolveFunctionName(self.ast.tokenSlice(callee.main_token)), "sprintf");
    }
    // rhs 1 marks a leading backslash
    if (callee.tag != .qualified_name or callee.data.rhs != 1) return false;
    const parts = self.ast.extraSlice(callee.data.lhs);
    return parts.len == 1 and std.ascii.eqlIgnoreCase(self.ast.tokenSlice(parts[0]), "sprintf");
}

// zend_compile_func_sprintf: a literal format of plain %s, %d and %% with one
// value per placeholder compiles to string casts and concatenation, so the
// call leaves no sprintf frame in traces and stops at the first exception.
// false when the call doesn't qualify and nothing was emitted
fn compileSprintfRope(self: *Compiler, args: []const u32) Error!bool {
    if (args.len < 1) return false;
    const fmt_node = self.ast.nodes[args[0]];
    if (fmt_node.tag != .string_literal) return false;
    const tok_tag = self.ast.tokens[fmt_node.main_token].tag;
    if (tok_tag == .heredoc or tok_tag == .nowdoc) return false;
    const lexeme = self.ast.tokenSlice(fmt_node.main_token);
    if (lexeme.len < 2 or (lexeme[0] != '\'' and lexeme[0] != '"')) return false;
    if (lexeme[0] == '"' and std.mem.indexOfScalar(u8, lexeme, '$') != null) return false;
    const fmt_value = self.evalConstExpr(args[0]);
    if (fmt_value != .string) return false;
    const fmt = fmt_value.string.bytes();
    if (fmt.len >= 256) return false;

    var placeholders: usize = 0;
    var i: usize = 0;
    while (std.mem.indexOfScalarPos(u8, fmt, i, '%')) |p| {
        if (p + 1 == fmt.len) return false;
        switch (fmt[p + 1]) {
            's', 'd' => placeholders += 1,
            '%' => {},
            else => return false,
        }
        i = p + 2;
    }
    if (placeholders != args.len - 1) return false;

    const call_offset = self.current_source_offset;
    // the values are evaluated before any of them is converted
    for (args[1..]) |arg| try self.compileNode(arg);
    self.current_source_offset = call_offset;
    // reverse them so the first one is on top
    var depth = placeholders;
    while (depth > 1) {
        depth -= 1;
        try self.emitOp(.bury);
        try self.emitByte(@intCast(depth));
    }

    var literal = std.ArrayListUnmanaged(u8).empty;
    defer literal.deinit(self.allocator);
    var have_acc = false;
    i = 0;
    while (i < fmt.len) {
        const p = std.mem.indexOfScalarPos(u8, fmt, i, '%') orelse {
            try literal.appendSlice(self.allocator, fmt[i..]);
            break;
        };
        try literal.appendSlice(self.allocator, fmt[i..p]);
        const spec = fmt[p + 1];
        i = p + 2;
        if (spec == '%') {
            try literal.append(self.allocator, '%');
            continue;
        }
        // the stack holds the next value on top, with the result so far above it
        if (have_acc) {
            if (literal.items.len > 0) {
                try emitRopeLiteral(self, literal.items);
                try self.emitOp(.concat);
            }
            try self.emitOp(.swap);
            try self.emitOp(if (spec == 'd') .cast_int else .cast_string);
            try self.emitOp(.concat);
        } else {
            try self.emitOp(if (spec == 'd') .cast_int else .cast_string);
            if (spec == 'd' or literal.items.len > 0) {
                try emitRopeLiteral(self, literal.items);
                try self.emitOp(.swap);
                try self.emitOp(.concat);
            }
            have_acc = true;
        }
        literal.clearRetainingCapacity();
    }
    if (!have_acc) {
        try emitRopeLiteral(self, literal.items);
    } else if (literal.items.len > 0) {
        try emitRopeLiteral(self, literal.items);
        try self.emitOp(.concat);
    }
    return true;
}

fn emitRopeLiteral(self: *Compiler, text: []const u8) Error!void {
    const owned = try self.allocator.dupe(u8, text);
    try self.string_allocs.append(self.allocator, owned);
    try self.emitConstant(try self.addConstant(.{ .string = Value.String.borrowed(owned) }));
}

// whether a call compiles to its spread form, which carries its arguments in
// an array: unpacking, named arguments, or more arguments than a call
// opcode's count byte holds (0xFF marks new_obj's spread form)
pub fn hasSplatOrNamed(ast: *const Ast, args: []const u32) bool {
    if (args.len >= 0xFF) return true;
    for (args) |arg_idx| {
        const tag = ast.nodes[arg_idx].tag;
        if (tag == .splat_expr or tag == .named_arg) return true;
    }
    return false;
}

// zend_compile_args: nothing positional after a named or unpacked
// argument, and no unpacking after a named one
fn checkArgOrder(self: *Compiler, args: []const u32) Error!void {
    var named: ?u32 = null;
    var unpacked = false;
    for (args) |arg_idx| {
        const arg = self.ast.nodes[arg_idx];
        switch (arg.tag) {
            .splat_expr => {
                if (named) |tok| return self.fail(tok, "Cannot use argument unpacking after named arguments");
                unpacked = true;
            },
            .named_arg => named = arg.main_token,
            else => {
                if (unpacked) return self.fail(if (arg.main_token != 0) arg.main_token else named orelse 0, "Cannot use positional argument after argument unpacking");
                if (named) |tok| return self.fail(tok, "Cannot use positional argument after named argument");
            },
        }
    }
}

pub fn emitSpreadArgs(self: *Compiler, args: []const u32) Error!ArgGuards {
    try checkArgOrder(self, args);
    var guards: ArgGuards = .empty;
    errdefer guards.deinit(self.allocator);
    try self.emitOp(.array_new);
    for (args) |arg_idx| {
        const arg_node = self.ast.nodes[arg_idx];
        if (arg_node.tag == .splat_expr) {
            try self.compileNode(arg_node.data.lhs);
            try self.emitOp(.array_spread);
        } else if (arg_node.tag == .named_arg) {
            const name = self.ast.tokenSlice(arg_node.main_token);
            const name_const = try self.addConstant(.{ .string = Value.String.borrowed(name) });
            try self.emitOp(.constant);
            try self.emitU16(name_const);
            try compileArgLvalue(self, arg_node.data.lhs, .{ .pos = ArgPos.named, .guards = &guards });
            try self.emitOp(.arg_array_set);
        } else {
            try compileArgLvalue(self, arg_idx, .{ .pos = ArgPos.spread, .guards = &guards });
            try self.emitOp(.arg_array_push);
        }
    }
    return guards;
}

pub fn emitSpreadCallOp(self: *Compiler, guards: *ArgGuards, op: OpCode, a: ?u16, argc: ?u8) Error!void {
    try emitCallOp(self, guards, op, .{ .a = a, .argc = argc });
}

fn compileUnset(self: *Compiler, args: []const u32) Error!void {
    for (args) |arg_idx| {
        const arg = self.ast.nodes[arg_idx];
        if (isShortCircuited(self, arg_idx)) return self.fail(arg.main_token, "Can't use nullsafe operator in write context");
        if (arg.tag == .array_push_target) return self.fail(arg.main_token, "Cannot use [] for unsetting");
        if (isGlobalsFetch(self, arg_idx)) return self.fail(arg.main_token, "$GLOBALS can only be modified using the $GLOBALS[$name] = $value syntax");
        try checkTemporaryBase(self, arg_idx, arg.main_token);
        if (arg.tag == .variable and std.mem.eql(u8, self.ast.tokenSlice(arg.main_token), "$this")) return self.fail(arg.main_token, "Cannot unset $this");
        if (arg.tag == .variable) {
            const name = self.ast.tokenSlice(arg.main_token);
            const idx = try self.addConstant(.{ .string = Value.String.borrowed(name) });
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
                const prop_idx = try self.addConstant(.{ .string = Value.String.borrowed(self.propName(arg)) });
                try self.emitOp(.unset_prop);
                try self.emitU16(prop_idx);
            }
        } else if (arg.tag == .array_access) {
            // COW: removing an element mutates the array in place, so the root
            // variable of the dimension chain must be separated first if it
            // shares its array (non-vivifying - unset of a missing var must not
            // create it). the levels below are separated as the chain descends
            var base = self.ast.nodes[arg.data.lhs];
            while (base.tag == .array_access) base = self.ast.nodes[base.data.lhs];
            if (base.tag == .variable) {
                const bname = self.ast.tokenSlice(base.main_token);
                if (Compiler.isSuperglobal(bname)) {
                    try self.emitOp(.ensure_array_var);
                    try self.emitU16(try self.addConstant(.{ .string = Value.String.borrowed(bname) }));
                    try self.emitByte(1);
                }
                var slot_opt: ?u16 = null;
                if (self.local_slots.get(bname)) |s| {
                    slot_opt = s;
                } else if (self.arrowCaptureSlot(bname)) |s| {
                    slot_opt = s;
                } else if (!Compiler.isSuperglobal(bname) and !self.inFunctionScope() and bname.len > 0 and bname[0] == '$') {
                    slot_opt = self.getOrCreateSlot(bname);
                }
                if (slot_opt) |slot| {
                    try self.emitOp(.cow_separate_local);
                    try self.emitU16(slot);
                }
            }
            // for `unset($a[k1][k2]...[kn])`, the intermediate reads should
            // use coalesce-safe semantics so missing keys don't warn
            try compileUnsetDimensionBase(self, arg.data.lhs);
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

    // settype returns the converted value, we store it back and push true.
    // the variable is passed by reference, so reading it doesn't warn
    const saved = self.quiet_reads;
    self.quiet_reads = true;
    try self.emitGetVar(var_name);
    self.quiet_reads = saved;
    try self.compileNode(args[1]);
    const fn_idx = try self.addConstant(.{ .string = Value.String.borrowed("settype") });
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
        // named as a call names it: in the namespace, falling back to the
        // global function when the closure is made. die is exit's alias,
        // and neither is namespaced
        const tok = self.ast.tokens[callee.main_token].tag;
        const name = if (tok == .kw_exit or tok == .kw_die) "exit" else if (tok == .kw_clone) "clone" else self.resolveFunctionName(self.ast.tokenSlice(callee.main_token));
        const idx = try self.addConstant(.{ .string = Value.String.borrowed(name) });
        try self.emitOp(.constant);
        try self.emitU16(idx);
    } else if (callee.tag == .qualified_name) {
        const parts = self.ast.extraSlice(callee.data.lhs);
        const fqn = try self.buildQualifiedString(parts);
        const name = try self.resolveQualifiedNonClassName(fqn, callee.data.rhs);
        const idx = try self.addConstant(.{ .string = Value.String.borrowed(name) });
        try self.emitOp(.constant);
        try self.emitU16(idx);
    } else if (callee.tag == .method_call or callee.tag == .nullsafe_method_call) {
        // $obj->method(...) => [$obj, 'method']
        if (callee.tag == .nullsafe_method_call or isShortCircuited(self, callee.data.lhs))
            return self.fail(callee.main_token, "Cannot combine nullsafe operator with Closure creation");
        try self.emitOp(.array_new);
        try self.compileNode(callee.data.lhs);
        try self.emitOp(.array_push);
        const method_name = self.ast.tokenSlice(callee.main_token);
        if (self.ast.tokens[callee.main_token].tag == .variable) {
            // $obj->$name(...)
            try self.emitGetVar(method_name);
        } else {
            const method_idx = try self.addConstant(.{ .string = Value.String.borrowed(method_name) });
            try self.emitOp(.constant);
            try self.emitU16(method_idx);
        }
        try self.emitOp(.array_push);
    } else if (callee.tag == .property_access and self.isDynamicProp(callee)) {
        // $obj->{expr}(...) and $obj->$name(...) as the parser leaves them
        if (isShortCircuited(self, callee.data.lhs))
            return self.fail(node.main_token, "Cannot combine nullsafe operator with Closure creation");
        try self.emitOp(.array_new);
        try self.compileNode(callee.data.lhs);
        try self.emitOp(.array_push);
        if (callee.main_token == 0) {
            try self.compileNode(callee.data.rhs);
        } else {
            try self.emitGetVar(self.ast.tokenSlice(self.ast.nodes[callee.data.rhs].main_token));
        }
        try self.emitOp(.array_push);
    } else if (callee.tag == .static_prop_access and callee.main_token != 0 and self.ast.tokens[callee.main_token].tag == .variable) {
        // A::$name(...) and $class::$name(...)
        const class_node = self.ast.nodes[callee.data.lhs];
        try self.emitOp(.array_new);
        if (class_node.tag == .variable) {
            try self.compileNode(callee.data.lhs);
        } else {
            const class_name = try resolveNodeClassName(self, class_node);
            try self.emitConstant(try self.addConstant(.{ .string = Value.String.borrowed(class_name) }));
        }
        try self.emitOp(.array_push);
        try self.emitGetVar(self.ast.tokenSlice(callee.main_token));
        try self.emitOp(.array_push);
    } else if (callee.tag == .static_call) {
        // ClassName::method(...) => ['ClassName', 'method']. in code that
        // runs, self, parent and static stay as written: the closure resolves
        // them where it is made, forwarding the called class. a constant
        // expression (its initializer is named with a leading nul) names
        // its own class
        const class_node = self.ast.nodes[callee.data.lhs];
        const written = self.ast.tokenSlice(class_node.main_token);
        const in_initializer = self.current_function.len > 0 and self.current_function[0] == 0;
        const relative = class_node.tag != .qualified_name and !(in_initializer and !self.in_trait) and (std.ascii.eqlIgnoreCase(written, "self") or std.ascii.eqlIgnoreCase(written, "parent") or std.ascii.eqlIgnoreCase(written, "static"));
        const class_name = if (relative) written else try resolveNodeClassName(self, class_node);
        const method_name = self.ast.tokenSlice(callee.main_token);
        try self.emitOp(.array_new);
        const class_idx = try self.addConstant(.{ .string = Value.String.borrowed(class_name) });
        try self.emitOp(.constant);
        try self.emitU16(class_idx);
        try self.emitOp(.array_push);
        const method_idx = try self.addConstant(.{ .string = Value.String.borrowed(method_name) });
        try self.emitOp(.constant);
        try self.emitU16(method_idx);
        try self.emitOp(.array_push);
    } else {
        try self.compileNode(node.data.lhs);
    }
    try self.emitOp(.callable_closure);
}

pub fn compileArrayAccess(self: *Compiler, node: Ast.Node) Error!void {
    try self.compileNode(node.data.lhs);
    try self.compileNode(node.data.rhs);
    try self.emitOp(.array_get);
}

// the object a property write goes to, fetched for writing as php's
// zend_fetch_property_address does: a variable without the undefined
// warning, a property of a property through prepare_prop_w
fn compilePropWriteBase(self: *Compiler, node_idx: u32) Error!void {
    return compilePropFetchBase(self, node_idx, false);
}

// for a read-modify-write (`+=`, `++`) the variable is fetched as php's
// BP_VAR_RW, which warns when it is undefined
fn compilePropFetchBase(self: *Compiler, node_idx: u32, rw: bool) Error!void {
    const node = self.ast.nodes[node_idx];
    if (!rw and ((node.tag == .variable and !std.mem.eql(u8, self.ast.tokenSlice(node.main_token), "$this")) or node.tag == .variable_variable)) {
        const saved = self.quiet_reads;
        self.quiet_reads = true;
        defer self.quiet_reads = saved;
        return self.compileNode(node_idx);
    }
    if (node.tag == .property_access and !self.isDynamicProp(node)) {
        try compilePropFetchBase(self, node.data.lhs, rw);
        const name_idx = try self.addConstant(.{ .string = Value.String.borrowed(self.propName(node)) });
        try self.emitOp(.prepare_prop_w);
        try self.emitU16(name_idx);
        try self.emitOp(.get_prop);
        try self.emitU16(name_idx);
        return;
    }
    // an element is fetched for writing too (FETCH_DIM_W): the chain is
    // vivified and a missing element created null
    if ((node.tag == .array_access or (node.tag == .array_push_target and !rw)) and dimWriteChainRoot(self, node_idx)) {
        try compileVivifyChain(self, node.data.lhs);
        if (node.tag == .array_push_target) {
            try self.emitOp(.array_append_w);
        } else {
            try self.compileNode(node.data.rhs);
            try self.emitOp(.array_get_w);
            try self.emitByte(@intFromBool(rw));
        }
        return;
    }
    return self.compileNode(node_idx);
}

// whether a dimension chain ends in a variable or a property, the roots
// the vivify chain fetches for writing
fn dimWriteChainRoot(self: *Compiler, node_idx: u32) bool {
    var idx = node_idx;
    while (true) {
        const node = self.ast.nodes[idx];
        switch (node.tag) {
            .array_access, .array_push_target => idx = node.data.lhs,
            .variable => return !std.mem.eql(u8, self.ast.tokenSlice(node.main_token), "$this"),
            .property_access => return true,
            else => return false,
        }
    }
}

pub fn compileVivifyChain(self: *Compiler, node_idx: u32) Error!void {
    const node = self.ast.nodes[node_idx];
    if (node.tag == .array_access) {
        try compileVivifyChain(self, node.data.lhs);
        try self.compileNode(node.data.rhs);
        try self.emitOp(.array_get_vivify);
    } else if (node.tag == .array_push_target) {
        try compileVivifyChain(self, node.data.lhs);
        try self.emitOp(.array_append_vivify);
    } else if (node.tag == .variable or node.tag == .identifier) {
        const name = self.ast.tokenSlice(node.main_token);
        try emitEnsureArray(self, name);
    } else if (node.tag == .property_access) {
        // $obj->prop[]=x / $obj->prop[k] op= v: load the property array for
        // in-place write with COW separation + write-back (ensure_array_prop)
        try compilePropWriteBase(self, node.data.lhs);
        if (self.isDynamicProp(node)) {
            try self.compileNode(node.data.rhs);
            try self.emitOp(.ensure_array_prop_dynamic);
        } else {
            const prop_idx = try self.addConstant(.{ .string = Value.String.borrowed(self.propName(node)) });
            try self.emitOp(.ensure_array_prop);
            try self.emitU16(prop_idx);
        }
    } else if (node.tag == .static_prop_access and self.ast.nodes[node.data.lhs].tag != .variable) {
        // Class::$prop[]=x: load the static-prop array for in-place write with
        // COW separation + write-back (ensure_array_static_prop). dynamic
        // ($var::) class falls through to the plain load below
        const class_node = self.ast.nodes[node.data.lhs];
        const class_name = try staticClassOperand(self, class_node);
        var prop_name = self.ast.tokenSlice(node.main_token);
        if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
        const class_idx = try self.addConstant(.{ .string = Value.String.borrowed(class_name) });
        const prop_idx = try self.addConstant(.{ .string = Value.String.borrowed(prop_name) });
        try self.emitOp(.ensure_array_static_prop);
        try self.emitU16(class_idx);
        try self.emitU16(prop_idx);
    } else if (node.tag == .variable_variable) {
        try self.compileNode(node.data.lhs);
        try self.emitOp(.ensure_array_var_var);
    } else {
        try self.compileNode(node_idx);
    }
}

fn emitEnsureArray(self: *Compiler, name: []const u8) Error!void {
    if (Compiler.isSuperglobal(name)) {
        try self.emitOp(.ensure_array_var);
        try self.emitU16(try self.addConstant(.{ .string = Value.String.borrowed(name) }));
        try self.emitByte(0);
        return;
    }
    if (self.local_slots.get(name)) |slot| {
        try self.emitOp(.ensure_array_local);
        try self.emitU16(slot);
        return;
    }
    if (self.arrowCaptureSlot(name)) |slot| {
        try self.emitOp(.ensure_array_local);
        try self.emitU16(slot);
        return;
    }
    if (!Compiler.isSuperglobal(name) and !self.inFunctionScope() and name.len > 0 and name[0] == '$') {
        const slot = self.getOrCreateSlot(name);
        try self.emitOp(.ensure_array_local);
        try self.emitU16(slot);
        return;
    }
    const idx = try self.addConstant(.{ .string = Value.String.borrowed(name) });
    try self.emitOp(.ensure_array_var);
    try self.emitU16(idx);
    try self.emitByte(0);
}

// Bind a source lvalue without leaving an evaluated value on the stack.
// Assignments, reference returns, and literal entries use the same machinery.
pub fn compileReferenceBinding(self: *Compiler, source: u32, dst: u16) Error!bool {
    const node = self.ast.nodes[source];
    switch (node.tag) {
        .variable, .identifier => {
            try self.emitOp(.make_var_ref);
            try self.emitU16(dst);
            try self.emitU16(try self.addConstant(.{ .string = Value.String.borrowed(self.ast.tokenSlice(node.main_token)) }));
        },
        .array_access, .array_push_target => {
            try compileVivifyChain(self, node.data.lhs);
            if (node.tag == .array_push_target) try self.emitOp(.op_null) else try self.compileNode(node.data.rhs);
            try self.emitOp(.make_var_array_elem_ref);
            try self.emitU16(dst);
        },
        .property_access => {
            try self.compileNode(node.data.lhs);
            if (self.isDynamicProp(node)) {
                try self.compileNode(node.data.rhs);
                try self.emitOp(.make_var_prop_ref_dyn);
                try self.emitU16(dst);
            } else {
                try self.emitOp(.make_var_prop_ref);
                try self.emitU16(dst);
                try self.emitU16(try self.addConstant(.{ .string = Value.String.borrowed(self.propName(node)) }));
            }
        },
        .static_prop_access => {
            const class_name = resolveNodeClassName(self, self.ast.nodes[node.data.lhs]) catch return false;
            var prop_name = self.ast.tokenSlice(node.main_token);
            if (prop_name.len > 0 and prop_name[0] == '$') prop_name = prop_name[1..];
            try self.emitOp(.make_var_static_prop_ref);
            try self.emitU16(dst);
            try self.emitU16(try self.addConstant(.{ .string = Value.String.borrowed(class_name) }));
            try self.emitU16(try self.addConstant(.{ .string = Value.String.borrowed(prop_name) }));
        },
        .call, .method_call, .static_call => {
            try self.emitOp(.reset_return_ref);
            try self.compileNode(source);
            try self.emitOp(.bind_ref_from_return);
            try self.emitU16(dst);
            try self.emitOp(.pop);
        },
        else => return false,
    }
    return true;
}

// what compileReferenceBinding can make a reference of
fn isReferenceSource(self: *Compiler, source: u32) bool {
    return switch (self.ast.nodes[source].tag) {
        .variable, .identifier, .array_access, .array_push_target, .property_access, .call, .method_call, .static_call => true,
        .static_prop_access => blk: {
            _ = resolveNodeClassName(self, self.ast.nodes[self.ast.nodes[source].data.lhs]) catch break :blk false;
            break :blk true;
        },
        else => false,
    };
}

// Move the temporary binding into the owning operand-stack provenance. No
// synthetic variable survives the expression or holds a returned local alive.
fn compileReferenceSource(self: *Compiler, source: u32) Error!void {
    const dst = try self.addConstant(.{ .string = Value.String.borrowed("\x00reference-source") });
    if (!try compileReferenceBinding(self, source, dst)) return error.CompileError;
    try self.emitOp(.reference_source);
    try self.emitU16(dst);
}

pub fn compileArrayLiteral(self: *Compiler, node: Ast.Node) Error!void {
    try self.emitOp(.array_new);
    var last_token = node.main_token;
    for (self.ast.extraSlice(node.data.lhs)) |elem_idx| {
        // an omitted element only means something in a destructuring
        // target; php reports it at the line it last compiled
        if (elem_idx == 0) return self.fail(last_token, "Cannot use empty array elements in arrays");
        const first = self.ast.nodes[self.ast.nodes[elem_idx].data.lhs];
        if (first.main_token != 0) last_token = first.main_token;
        const elem = self.ast.nodes[elem_idx];
        if (elem.tag == .array_spread) {
            try self.compileNode(elem.data.lhs);
            try self.emitOp(.array_spread);
            continue;
        }
        const value = self.ast.nodes[elem.data.lhs];
        if (elem.data.rhs != 0) try self.compileNode(elem.data.rhs);
        // `&$this` can't bind $this: php wraps a copy in a reference only the
        // array holds, which behaves as the plain value
        const this_ref = value.tag == .ref_target and self.ast.nodes[value.data.lhs].tag == .variable and
            std.mem.eql(u8, self.ast.tokenSlice(self.ast.nodes[value.data.lhs].main_token), "$this");
        if (this_ref) {
            try self.compileNode(value.data.lhs);
            try self.emitOp(if (elem.data.rhs != 0) .array_set_elem else .array_push);
        } else if (value.tag == .ref_target) {
            try compileReferenceSource(self, value.data.lhs);
            try self.emitOp(if (elem.data.rhs != 0) .array_set_elem_ref else .array_push_ref);
        } else {
            try self.compileNode(elem.data.lhs);
            try self.emitOp(if (elem.data.rhs != 0) .array_set_elem else .array_push);
        }
    }
}

pub fn compilePropertyAccess(self: *Compiler, node: Ast.Node) Error!void {
    try compilePropertyFetch(self, node, null);
}

fn compilePropertyFetch(self: *Compiler, node: Ast.Node, guard: ?ArgGuard) Error!void {
    // outermost chain link sets up the nullsafe-jump collection. inner nullsafe
    // links append their short-circuit jumps to this list so a `$x?->y()->z`
    // chain skips both `y()` and `z` when $x is null
    var local_jumps: std.ArrayListUnmanaged(usize) = .empty;
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
        if (guard) |g| try emitArgGuard(self, g, .arg_guard_prop_dynamic);
        try self.emitOp(.get_prop_dynamic);
    } else {
        const name_idx = try self.addConstant(.{ .string = Value.String.borrowed(self.propName(node)) });
        if (guard) |g| try emitArgGuard(self, g, .arg_guard_prop);
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
    var local_jumps: std.ArrayListUnmanaged(usize) = .empty;
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
            var guards = try emitSpreadArgs(self, args);
            try emitCallOp(self, &guards, .method_call_dynamic_spread, .{});
        } else {
            var guards = try compileArgs(self, args);
            try emitCallOp(self, &guards, .method_call_dynamic, .{ .argc = @intCast(args.len) });
        }
        return;
    }

    const method_name = self.ast.tokenSlice(node.main_token);
    const name_idx = try self.addConstant(.{ .string = Value.String.borrowed(method_name) });

    if (hasSplatOrNamed(self.ast, args)) {
        var guards = try emitSpreadArgs(self, args);
        try emitCallOp(self, &guards, .method_call_spread, .{ .a = name_idx });
    } else {
        var guards = try compileArgs(self, args);
        try emitCallOp(self, &guards, .method_call, .{ .a = name_idx, .argc = @intCast(args.len) });
    }
}

pub fn compileNullsafePropertyAccess(self: *Compiler, node: Ast.Node) Error!void {
    return compileNullsafePropertyFetch(self, node, false);
}

// quiet under `??`: the property reads as isset would, without a warning
fn compileNullsafePropertyFetch(self: *Compiler, node: Ast.Node, quiet: bool) Error!void {
    // create or reuse the chain jump-list. when an outer chain link is
    // collecting, append our short-circuit jump there; otherwise patch locally
    var local_jumps: std.ArrayListUnmanaged(usize) = .empty;
    const owns_chain = self.nullsafe_chain_jumps == null;
    if (owns_chain) self.nullsafe_chain_jumps = &local_jumps;
    defer if (owns_chain) {
        for (local_jumps.items) |j| self.patchJump(j);
        self.nullsafe_chain_jumps = null;
        local_jumps.deinit(self.allocator);
    };

    if (quiet) try compileCoalesceFetch(self, node.data.lhs) else try self.compileNode(node.data.lhs);
    const skip_jump = try self.emitJump(.jump_if_not_null);
    const end_jump = try self.emitJump(.jump);
    self.patchJump(skip_jump);
    const name_idx = try self.addConstant(.{ .string = Value.String.borrowed(self.propName(node)) });
    try self.emitOp(if (quiet) .get_prop_coalesce else .get_prop);
    try self.emitU16(name_idx);
    try self.nullsafe_chain_jumps.?.append(self.allocator, end_jump);
}

pub fn compileNullsafeMethodCall(self: *Compiler, node: Ast.Node) Error!void {
    var local_jumps: std.ArrayListUnmanaged(usize) = .empty;
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
    const name_idx = try self.addConstant(.{ .string = Value.String.borrowed(method_name) });

    if (hasSplatOrNamed(self.ast, args)) {
        var guards = try emitSpreadArgs(self, args);
        try emitCallOp(self, &guards, .method_call_spread, .{ .a = name_idx });
    } else {
        var guards = try compileArgs(self, args);
        try emitCallOp(self, &guards, .method_call, .{ .a = name_idx, .argc = @intCast(args.len) });
    }
    try self.nullsafe_chain_jumps.?.append(self.allocator, end_jump);
}

// parent::$prop::get() / parent::$prop::set($v) inside that property's own
// hook (zend_compile_parent_property_hook_call); written in parentheses it
// is an ordinary static call on the static property's value
fn compileParentHookCall(self: *Compiler, node: Ast.Node) Error!bool {
    const class_node = self.ast.nodes[node.data.lhs];
    if (class_node.tag != .static_prop_access or class_node.main_token == 0) return false;
    const written = self.ast.tokenSlice(class_node.main_token);
    if (written.len < 2 or written[0] != '$') return false;
    const parent_node = self.ast.nodes[class_node.data.lhs];
    if (parent_node.tag != .identifier or !std.ascii.eqlIgnoreCase(self.ast.tokenSlice(parent_node.main_token), "parent")) return false;
    const method = self.ast.tokenSlice(node.main_token);
    const is_set = std.ascii.eqlIgnoreCase(method, "set");
    if (!is_set and !std.ascii.eqlIgnoreCase(method, "get")) return false;
    const prop = written[1..];
    const kind: []const u8 = if (is_set) "set" else "get";
    if (self.current_class.len == 0) return self.fail(node.main_token, "Cannot use \"parent\" when no class scope is active");
    if (self.hook_property.len == 0) return self.failFmt(node.main_token, "Must not use parent::${s}::{s}() outside a property hook", .{ prop, kind });
    if (!std.mem.eql(u8, prop, self.hook_property)) return self.failFmt(node.main_token, "Must not use parent::${s}::{s}() in a different property (${s})", .{ prop, kind, self.hook_property });
    if (is_set != self.hook_is_set) return self.failFmt(node.main_token, "Must not use parent::${s}::{s}() in a different property hook ({s})", .{ prop, kind, if (self.hook_is_set) "set" else "get" });

    const args = self.ast.extraSlice(node.data.rhs);
    for (args) |a| try self.compileNode(a);
    const prop_idx = try self.addConstant(.{ .string = Value.String.borrowed(prop) });
    try self.emitOp(.parent_hook_call);
    try self.emitU16(prop_idx);
    try self.emitByte(@intFromBool(is_set));
    try self.emitByte(@intCast(args.len));
    try self.emitU16(3);
    try self.emitOp(if (is_set) .set_prop else .get_prop);
    try self.emitU16(prop_idx);
    return true;
}

pub fn compileStaticCall(self: *Compiler, node: Ast.Node) Error!void {
    if (try compileParentHookCall(self, node)) return;
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

    // `$var::m()` and `A::$prop::m()`: the class is the value
    const static_prop = class_node.tag == .static_prop_access and class_node.main_token != 0 and
        std.mem.startsWith(u8, self.ast.tokenSlice(class_node.main_token), "$");
    if (class_node.tag == .variable or static_prop) {
        try self.compileNode(class_lhs_idx);
        const method_idx = try self.addConstant(.{ .string = Value.String.borrowed(method_name) });
        if (hasSplatOrNamed(self.ast, args)) return emitDynStaticSpread(self, method_idx, args);
        var guards = try compileArgs(self, args);
        try emitCallOp(self, &guards, .static_call_dynamic, .{ .a = method_idx, .argc = @intCast(args.len) });
        return;
    }

    // Class::method when the class side is an expression that produces an
    // object (e.g. (new X())::foo()): evaluate the object, derive its class,
    // then emit static_call_dynamic
    switch (class_node.tag) {
        .new_expr, .method_call, .nullsafe_method_call, .call, .property_access, .nullsafe_property_access, .array_access => {
            try self.compileNode(class_lhs_idx);
            try self.emitOp(.get_obj_class);
            const method_idx = try self.addConstant(.{ .string = Value.String.borrowed(method_name) });
            if (hasSplatOrNamed(self.ast, args)) return emitDynStaticSpread(self, method_idx, args);
            var guards = try compileArgs(self, args);
            try emitCallOp(self, &guards, .static_call_dynamic, .{ .a = method_idx, .argc = @intCast(args.len) });
            return;
        },
        else => {},
    }

    const class_name = try resolveNodeClassName(self, class_node);
    const class_idx = try self.addConstant(.{ .string = Value.String.borrowed(class_name) });
    const method_idx = try self.addConstant(.{ .string = Value.String.borrowed(method_name) });

    if (hasSplatOrNamed(self.ast, args)) {
        var guards = try emitSpreadArgs(self, args);
        try emitCallOp(self, &guards, .static_call_spread, .{ .a = class_idx, .b = method_idx });
    } else {
        var guards = try compileArgs(self, args);
        try emitCallOp(self, &guards, .static_call, .{ .a = class_idx, .b = method_idx, .argc = @intCast(args.len) });
    }
}

// a static call on a class only known at run time, its arguments in an array:
// the class value is on the stack, the method name a constant
fn emitDynStaticSpread(self: *Compiler, method_idx: u16, args: []const u32) Error!void {
    try self.emitOp(.constant);
    try self.emitU16(method_idx);
    var guards = try emitSpreadArgs(self, args);
    try emitCallOp(self, &guards, .static_call_dyn_both_spread, .{});
}

pub fn compileDynamicStaticCall(self: *Compiler, node: Ast.Node) Error!void {
    const class_node = self.ast.nodes[node.data.lhs];
    const extra = self.ast.extraSlice(node.data.rhs);
    const method_expr = extra[0];
    const args = extra[1..];

    if (hasSplatOrNamed(self.ast, args)) {
        if (class_node.tag == .variable) {
            try self.compileNode(node.data.lhs);
        } else {
            const class_name = try resolveNodeClassName(self, class_node);
            try self.emitOp(.constant);
            try self.emitU16(try self.addConstant(.{ .string = Value.String.borrowed(class_name) }));
        }
        try self.compileNode(method_expr);
        var guards = try emitSpreadArgs(self, args);
        try emitCallOp(self, &guards, .static_call_dyn_both_spread, .{});
        return;
    }

    if (class_node.tag == .variable) {
        try self.compileNode(node.data.lhs);
        try self.compileNode(method_expr);
        var guards = try compileArgs(self, args);
        try emitCallOp(self, &guards, .static_call_dyn_both, .{ .argc = @intCast(args.len) });
    } else {
        const class_name = try resolveNodeClassName(self, class_node);
        const class_idx = try self.addConstant(.{ .string = Value.String.borrowed(class_name) });
        try self.compileNode(method_expr);
        var guards = try compileArgs(self, args);
        try emitCallOp(self, &guards, .static_call_dyn_method, .{ .a = class_idx, .argc = @intCast(args.len) });
    }
}

// Class::{expr} and $class::{expr}
pub fn compileDynamicClassConst(self: *Compiler, node: Ast.Node) Error!void {
    const class_node = self.ast.nodes[node.data.lhs];
    if (class_node.tag == .identifier or class_node.tag == .qualified_name) {
        const class_name = try resolveNodeClassName(self, class_node);
        const class_idx = try self.addConstant(.{ .string = Value.String.borrowed(class_name) });
        try self.compileNode(node.data.rhs);
        try self.emitOp(.get_class_const_dyn_name);
        try self.emitU16(class_idx);
        return;
    }
    try self.compileNode(node.data.lhs);
    try self.compileNode(node.data.rhs);
    try self.emitOp(.get_class_const_dyn_both);
}

pub fn compileStaticPropAccess(self: *Compiler, node: Ast.Node) Error!void {
    return compileStaticPropRead(self, node, false);
}

// a quiet read (isset, ??, empty) finds nothing instead of throwing when the
// class or the static property does not exist
fn compileStaticPropRead(self: *Compiler, node: Ast.Node, quiet: bool) Error!void {
    const class_node = self.ast.nodes[node.data.lhs];

    // Class::{expr} / Class::$$var / Class::${expr} - dynamic property name.
    // parser sets main_token=0 and stores the name expression in node.data.rhs
    if (node.main_token == 0 and node.data.rhs != 0) {
        // dynamic class expression too ($cls::${expr}) - both names runtime
        if (class_node.tag != .identifier and class_node.tag != .qualified_name) {
            try self.compileNode(node.data.lhs);
            try self.compileNode(node.data.rhs);
            try self.emitOp(if (quiet) .get_static_prop_dyn_both_quiet else .get_static_prop_dyn_both);
            return;
        }
        const class_name = try resolveNodeClassName(self, class_node);
        const class_idx = try self.addConstant(.{ .string = Value.String.borrowed(class_name) });
        try self.compileNode(node.data.rhs);
        try self.emitOp(if (quiet) .get_static_prop_dyn_name_quiet else .get_static_prop_dyn_name);
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
        const raw_name = self.ast.tokenSlice(node.main_token);
        const is_prop = raw_name.len > 0 and raw_name[0] == '$';
        const prop_idx = try self.addConstant(.{ .string = Value.String.borrowed(if (is_prop) raw_name[1..] else raw_name) });
        try self.emitOp(if (!is_prop) .get_class_const_dynamic else if (quiet) .get_static_prop_dynamic_quiet else .get_static_prop_dynamic);
        try self.emitU16(prop_idx);
        return;
    }

    const raw = self.ast.tokenSlice(node.main_token);
    const is_static_prop = raw.len > 0 and raw[0] == '$';
    const written_class = if (class_node.tag == .identifier) self.ast.tokenSlice(class_node.main_token) else "";
    const keep_written = self.relative_const_classes and !is_static_prop and (std.ascii.eqlIgnoreCase(written_class, "self") or std.ascii.eqlIgnoreCase(written_class, "parent"));
    const class_name = if (keep_written) written_class else try resolveNodeClassName(self, class_node);
    const prop_name = if (is_static_prop) raw[1..] else raw;
    const class_idx = try self.addConstant(.{ .string = Value.String.borrowed(class_name) });
    const prop_idx = try self.addConstant(.{ .string = Value.String.borrowed(prop_name) });
    // a bare-identifier member (not $prop, not ::class) is a class constant or
    // enum case - get_class_const throws Error on a miss instead of nulling
    if (!is_static_prop and !std.mem.eql(u8, prop_name, "class")) {
        try self.emitOp(.get_class_const);
    } else {
        try self.emitOp(if (quiet and is_static_prop) .get_static_prop_quiet else .get_static_prop);
    }
    try self.emitU16(class_idx);
    try self.emitU16(prop_idx);
}

// the class operand of a static property write: a written class name resolved
// against the namespace and imports, or a `$var` the vm reads at run time
fn staticClassOperand(self: *Compiler, class_node: Ast.Node) ![]const u8 {
    if (class_node.tag == .identifier or class_node.tag == .qualified_name) return resolveNodeClassName(self, class_node);
    return self.ast.tokenSlice(class_node.main_token);
}

pub fn resolveNodeClassName(self: *Compiler, class_node: Ast.Node) ![]const u8 {
    if (class_node.tag == .qualified_name) {
        const parts = self.ast.extraSlice(class_node.data.lhs);
        const name = try self.buildQualifiedString(parts);
        if (class_node.data.rhs == 1) return name;
        if (class_node.data.rhs == 2) {
            // `namespace\X` - relative to the current namespace, no alias lookup
            if (self.namespace.len == 0) return name;
            const qualified = std.fmt.allocPrint(self.allocator, "{s}\\{s}", .{ self.namespace, name }) catch return name;
            self.string_allocs.append(self.allocator, qualified) catch return name;
            return qualified;
        }
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
    try ensureValidClassFetch(self, class_node.main_token);
    return self.resolveClassName(self.ast.tokenSlice(class_node.main_token));
}

// zend_ensure_valid_class_fetch_type: self, parent and static need a class,
// which the compiler can tell inside a named function or a class (not in a
// closure, a trait, or a file's own code, which runs where it is included)
fn ensureValidClassFetch(self: *Compiler, token: u32) Error!void {
    const written = self.ast.tokenSlice(token);
    const which: []const u8 = if (std.ascii.eqlIgnoreCase(written, "self")) "self" else if (std.ascii.eqlIgnoreCase(written, "parent")) "parent" else if (std.ascii.eqlIgnoreCase(written, "static")) "static" else return;
    if (self.closure_signature or std.mem.startsWith(u8, self.current_function, "{closure:")) return;
    const known = if (self.current_class.len == 0) self.current_function.len > 0 else !self.in_trait;
    if (!known) return;
    if (self.current_class.len == 0) return self.failFmt(token, "Cannot use \"{s}\" when no class scope is active", .{which});
}

pub fn resolveQualifiedNewName(self: *Compiler, node: Ast.Node) !struct { name: []const u8, is_absolute: bool, ns_relative: bool } {
    const first = self.ast.tokenSlice(node.main_token);
    // rhs: bit 31 = absolute, bit 30 = `namespace\` relative, rest = extra index
    const rhs_raw = node.data.rhs & ~((@as(u32, 1) << 31) | (@as(u32, 1) << 30));
    const is_absolute = (node.data.rhs & (1 << 31)) != 0;
    const ns_relative = (node.data.rhs & (1 << 30)) != 0;
    if (rhs_raw == 0) return .{ .name = first, .is_absolute = is_absolute, .ns_relative = ns_relative };
    const parts = self.ast.extraSlice(rhs_raw);
    var buf = std.ArrayListUnmanaged(u8).empty;
    try buf.appendSlice(self.allocator, first);
    for (parts[1..]) |part_tok| {
        try buf.append(self.allocator, '\\');
        try buf.appendSlice(self.allocator, self.ast.tokenSlice(part_tok));
    }
    const owned = try buf.toOwnedSlice(self.allocator);
    try self.string_allocs.append(self.allocator, owned);
    return .{ .name = owned, .is_absolute = is_absolute, .ns_relative = ns_relative };
}

pub fn compileNewExpr(self: *Compiler, node: Ast.Node) Error!void {
    const resolved = try resolveQualifiedNewName(self, node);
    const raw_name = resolved.name;
    const class_name = if (resolved.is_absolute)
        raw_name
    else if (resolved.ns_relative) blk: {
        // `new namespace\Cls` - prepend the current namespace, no alias lookup
        if (self.namespace.len == 0) break :blk raw_name;
        const qualified = std.fmt.allocPrint(self.allocator, "{s}\\{s}", .{ self.namespace, raw_name }) catch return error.CompileError;
        self.string_allocs.append(self.allocator, qualified) catch return error.CompileError;
        break :blk qualified;
    } else if (std.mem.indexOf(u8, raw_name, "\\")) |sep| blk: {
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
    const name_idx = try self.addConstant(.{ .string = Value.String.borrowed(class_name) });
    try self.emitOp(.new_reserve_class);
    try self.emitU16(name_idx);
    if (hasSplatOrNamed(self.ast, args)) {
        var guards = try emitSpreadArgs(self, args);
        try emitCallOp(self, &guards, .new_obj, .{ .a = name_idx, .argc = 0xFF });
    } else {
        var guards = try compileArgs(self, args);
        try emitCallOp(self, &guards, .new_obj, .{ .a = name_idx, .argc = @intCast(args.len) });
    }
    try self.emitOp(.new_end);
}

pub fn compileNewExprDynamic(self: *Compiler, node: Ast.Node) Error!void {
    try self.compileNode(node.data.lhs);
    const args = self.ast.extraSlice(node.data.rhs);
    if (hasSplatOrNamed(self.ast, args)) {
        var guards = try emitSpreadArgs(self, args);
        try emitCallOp(self, &guards, .new_obj_dynamic, .{ .argc = 0xFF });
    } else {
        var guards = try compileArgs(self, args);
        try emitCallOp(self, &guards, .new_obj_dynamic, .{ .argc = @intCast(args.len) });
    }
}

// a function containing yield compiles as a generator; anywhere else php
// refuses it when compiling
fn checkYieldPlace(self: *Compiler, node: Ast.Node) Error!void {
    if (!self.is_generator) return self.fail(node.main_token, "The \"yield\" expression can only be used inside a function");
    // php's zend_mark_function_as_generator: a declared return type must
    // admit a Generator
    const declared = std.mem.trim(u8, self.declared_return, " \t\r\n");
    if (declared.len > 0 and !generatorCompatibleType(declared)) {
        return self.failFmt(if (self.function_token != 0) self.function_token else node.main_token, "Generator return type must be a supertype of Generator, {s} given", .{declared});
    }
}

fn generatorCompatibleType(declared: []const u8) bool {
    var members = std.mem.tokenizeAny(u8, declared, "|()&");
    while (members.next()) |raw| {
        var t = std.mem.trim(u8, raw, " \t\r\n?");
        if (t.len > 0 and t[0] == '\\') t = t[1..];
        for ([_][]const u8{ "object", "mixed", "iterable", "Traversable", "Iterator", "Generator" }) |ok| {
            if (std.ascii.eqlIgnoreCase(t, ok)) return true;
        }
    }
    return false;
}

// php's ZEND_YIELD in a function returning by reference: the yielded
// variable, element, property or reference-returning call becomes a
// reference the generator hands out; anything else is yielded by value
// with php's notice
fn compileYieldRef(self: *Compiler, value_node: u32, has_key: bool) Error!void {
    const name = try self.addConstant(.{ .string = Value.String.borrowed("\x00yield-reference") });
    var flags: u8 = if (has_key) 1 else 0;
    var target = value_node;
    while (target != 0 and self.ast.nodes[target].tag == .grouped_expr) target = self.ast.nodes[target].data.lhs;
    const tag = if (target != 0) self.ast.nodes[target].tag else .grouped_expr;
    if (target != 0 and (tag == .call or tag == .method_call or tag == .static_call)) flags |= 2;
    if (target == 0 or !try compileReferenceBinding(self, target, name)) {
        if (value_node != 0) try self.compileNode(value_node) else try self.emitOp(.op_null);
        // a bare yield gives null without the notice
        flags |= if (value_node != 0) 4 else 8;
    }
    try self.emitOp(.yield_ref);
    try self.emitU16(name);
    try self.emitByte(flags);
}

pub fn compileYield(self: *Compiler, node: Ast.Node) Error!void {
    try checkYieldPlace(self, node);
    if (self.returns_ref) return compileYieldRef(self, node.data.lhs, false);
    if (node.data.lhs != 0) {
        try self.compileNode(node.data.lhs);
    } else {
        try self.emitOp(.op_null);
    }
    try self.emitOp(.yield_value);
}

pub fn compileYieldPair(self: *Compiler, node: Ast.Node) Error!void {
    try checkYieldPlace(self, node);
    if (self.returns_ref) {
        try self.compileNode(node.data.lhs);
        return compileYieldRef(self, node.data.rhs, true);
    }
    try self.compileNode(node.data.lhs);
    try self.compileNode(node.data.rhs);
    try self.emitOp(.yield_pair);
}

pub fn compileYieldFrom(self: *Compiler, node: Ast.Node) Error!void {
    try checkYieldPlace(self, node);
    if (self.returns_ref) return self.fail(node.main_token, "Cannot use \"yield from\" inside a by-reference generator");
    try self.compileNode(node.data.lhs);
    try self.emitOp(.yield_from);
}

// both arguments are evaluated before the clone is made, as for a call:
// [object, properties] -> [properties, object] -> [properties, clone] -> [clone]
pub fn compileCloneWith(self: *Compiler, node: Ast.Node) Error!void {
    try self.compileNode(node.data.lhs);
    try self.compileNode(node.data.rhs);
    try self.emitOp(.swap);
    try self.emitOp(.clone_obj);
    try self.emitOp(.swap);
    try self.emitOp(.clone_with);
}

pub fn compileCast(self: *Compiler, node: Ast.Node) Error!void {
    const type_name = self.ast.tokenSlice(node.main_token);
    const eql = std.ascii.eqlIgnoreCase;
    if (eql(type_name, "unset")) return self.fail(node.main_token, "The (unset) cast is no longer supported");
    // the long spellings' deprecation is raised for the whole file at the
    // end of compileWithOrigin, as php's scanner reads them even in code
    // the compiler skips
    try self.compileNode(node.data.lhs);
    if (eql(type_name, "int") or eql(type_name, "integer")) {
        try self.emitOp(.cast_int);
    } else if (eql(type_name, "float") or eql(type_name, "double")) {
        try self.emitOp(.cast_float);
    } else if (eql(type_name, "string") or eql(type_name, "binary")) {
        try self.emitOp(.cast_string);
    } else if (eql(type_name, "bool") or eql(type_name, "boolean")) {
        try self.emitOp(.cast_bool);
    } else if (eql(type_name, "array")) {
        try self.emitOp(.cast_array);
    } else if (eql(type_name, "object")) {
        try self.emitOp(.cast_object);
    } else if (eql(type_name, "void")) {
        // the parser only allows (void) where the value is discarded; the
        // statement pops whatever is left, so leave null in its place
        try self.emitOp(.pop);
        try self.emitOp(.op_null);
    }
}
