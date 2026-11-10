const std = @import("std");
const platform = @import("../platform.zig");
const Value = @import("../runtime/value.zig").Value;
const phpTypeName = @import("types.zig").phpTypeName;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const vm_mod = @import("../runtime/vm.zig");
const NativeContext = vm_mod.NativeContext;
const VM = vm_mod.VM;
const NativeResult = vm_mod.NativeResult;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "array_push", array_push },
    .{ "array_pop", array_pop },
    .{ "array_shift", array_shift },
    .{ "array_keys", array_keys },
    .{ "array_is_list", array_is_list },
    .{ "array_values", array_values },
    .{ "in_array", in_array },
    .{ "array_key_exists", array_key_exists },
    .{ "key_exists", array_key_exists },
    .{ "array_search", array_search },
    .{ "array_reverse", array_reverse },
    .{ "array_merge", array_merge },
    .{ "array_slice", array_slice },
    .{ "array_unique", array_unique },
    .{ "range", native_range },
    .{ "array_map", array_map },
    .{ "array_filter", array_filter },
    .{ "array_splice", array_splice },
    .{ "array_combine", array_combine },
    .{ "array_chunk", array_chunk },
    .{ "array_pad", array_pad },
    .{ "array_flip", array_flip },
    .{ "array_column", array_column },
    .{ "array_fill", array_fill },
    .{ "array_fill_keys", array_fill_keys },
    .{ "array_count_values", array_count_values },
    .{ "array_sum", array_sum },
    .{ "array_product", array_product },
    .{ "array_walk", array_walk },
    .{ "array_unshift", array_unshift },
    .{ "shuffle", native_shuffle },
    .{ "array_rand", array_rand },
    .{ "compact", native_compact },
    .{ "extract", native_extract },
    .{ "array_reduce", array_reduce },
    .{ "array_key_first", array_key_first },
    .{ "array_key_last", array_key_last },
    .{ "array_first", array_first },
    .{ "array_last", array_last },
    .{ "array_replace", array_replace },
    .{ "array_find", array_find },
    .{ "array_find_key", array_find_key },
    .{ "array_any", array_any },
    .{ "array_all", array_all },
    .{ "current", native_current },
    .{ "pos", native_current },
    .{ "next", native_next },
    .{ "prev", native_prev },
    .{ "reset", native_reset },
    .{ "end", native_end },
    .{ "key", native_key },
    .{ "sizeof", native_sizeof },
    .{ "array_replace_recursive", array_replace_recursive },
    .{ "array_walk_recursive", array_walk_recursive },
    .{ "array_merge_recursive", array_merge_recursive },
    .{ "array_change_key_case", array_change_key_case },
};

fn array_push(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(.{ .int = 0 });
    const arr = args[0].array;
    if (args.len >= 2) {
        for (args[1..]) |val| {
            if (!try arr.appendNew(ctx.allocator, val)) return nextElementOccupied(ctx);
        }
    }
    return NativeResult.scalar(.{ .int = arr.length() });
}

fn nextElementOccupied(ctx: *NativeContext) RuntimeError!NativeResult {
    try ctx.vm.setPendingException("Error", "Cannot add element to the array as the next element is already occupied");
    return error.RuntimeError;
}

fn array_pop(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(.null);
    const arr = args[0].array;
    if (arr.entries.items.len == 0) return NativeResult.scalar(.null);
    const entry = arr.entries.pop() orelse return NativeResult.scalar(.null);
    if (entry.key == .string) _ = arr.string_index.remove(entry.key.string.bytes());
    // php hands the popped integer key out again only when it was the last
    // one given
    if (entry.key == .int and entry.key.int == arr.next_int_key - 1) arr.next_int_key -= 1;
    // native strings transfer ownership; other heap results remain borrowed.
    if (entry.key == .string) entry.key.string.release();
    if (entry.value != .string) ctx.vm.releaseValue(entry.value);
    return if (entry.value == .string and entry.value.string.owner != null) NativeResult.takeString(entry.value.string) else NativeResult.share(entry.value);
}

fn array_shift(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(.null);
    const arr = args[0].array;
    if (arr.entries.items.len == 0) return NativeResult.scalar(.null);
    const first = arr.entries.items[0];
    if (first.value == .string) first.value.string.retain();
    ctx.vm.arrayRemoveOwned(arr, first.key);
    // re-index numeric keys starting from 0
    var next_int: i64 = 0;
    for (arr.entries.items) |*entry| {
        switch (entry.key) {
            .int => {
                entry.key = .{ .int = next_int };
                next_int += 1;
            },
            .string => {},
        }
    }
    arr.next_int_key = next_int;
    arr.rebuildStringIndexAssumeCapacity();

    return if (first.value == .string and first.value.string.owner != null) NativeResult.takeString(first.value.string) else NativeResult.share(first.value);
}

fn array_keys(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(.null);
    const src = args[0].array;
    const has_search = args.len >= 2;
    const search_val = if (has_search) args[1] else Value.null;
    const strict = args.len >= 3 and args[2] == .bool and args[2].bool;
    var arr = try ctx.createArray();
    for (src.entries.items) |entry| {
        if (has_search) {
            const match = if (strict) Value.identical(search_val, entry.value) else Value.equal(search_val, entry.value);
            if (!match) continue;
        }
        const key_val: Value = switch (entry.key) {
            .int => |i| .{ .int = i },
            .string => |s| .{ .string = s },
        };
        try arr.append(ctx.allocator, key_val);
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn array_is_list(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(.{ .bool = false });
    const arr = args[0].array;
    for (arr.entries.items, 0..) |entry, i| {
        switch (entry.key) {
            .int => |k| {
                if (k != @as(i64, @intCast(i))) return NativeResult.scalar(.{ .bool = false });
            },
            .string => return NativeResult.scalar(.{ .bool = false }),
        }
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn array_values(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.null);
    if (args[0] != .array) {
        try ctx.vm.setPendingException("TypeError", "array_values(): Argument #1 ($array) must be of type array");
        return error.RuntimeError;
    }
    const src = args[0].array;
    var arr = try ctx.createArray();
    for (src.entries.items) |entry| {
        try arr.append(ctx.allocator, entry.value);
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn in_array(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .array) return NativeResult.scalar(.{ .bool = false });
    const needle = args[0];
    const arr = args[1].array;
    const strict = args.len >= 3 and args[2].isTruthy();
    for (arr.entries.items) |entry| {
        if (strict) {
            if (Value.identical(needle, entry.value)) return NativeResult.scalar(.{ .bool = true });
        } else {
            if (try ctx.vm.looseEqualWithStringable(needle, entry.value)) return NativeResult.scalar(.{ .bool = true });
        }
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn array_key_exists(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .array) return NativeResult.scalar(.{ .bool = false });
    const key = PhpArray.normalizeKey(Value.toArrayKey(args[0]));
    const arr = args[1].array;
    for (arr.entries.items) |entry| {
        if (entry.key.eql(key)) return NativeResult.scalar(.{ .bool = true });
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn array_search(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .array) return NativeResult.scalar(.{ .bool = false });
    const needle = args[0];
    const arr = args[1].array;
    const strict = args.len >= 3 and args[2] == .bool and args[2].bool;
    for (arr.entries.items) |entry| {
        const match = if (strict) Value.identical(needle, entry.value) else Value.equal(needle, entry.value);
        if (match) {
            return switch (entry.key) {
                .int => |i| NativeResult.scalar(.{ .int = i }),
                .string => |s| NativeResult.shareString(s),
            };
        }
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn array_reverse(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(.null);
    const src = args[0].array;
    const preserve = args.len >= 2 and args[1].isTruthy();
    var arr = try ctx.createArray();
    var i: usize = src.entries.items.len;
    while (i > 0) {
        i -= 1;
        const entry = src.entries.items[i];
        switch (entry.key) {
            .int => if (preserve) try arr.set(ctx.allocator, entry.key, entry.value) else try arr.append(ctx.allocator, entry.value),
            .string => try arr.set(ctx.allocator, entry.key, entry.value),
        }
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn array_merge(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    for (args) |arg| {
        if (arg != .array) continue;
        for (arg.array.entries.items) |entry| {
            switch (entry.key) {
                .int => try arr.append(ctx.allocator, entry.value),
                .string => |s| try ctx.vm.arraySetOwned(arr, .{ .string = s }, entry.value),
            }
        }
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn array_slice(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .array) return NativeResult.scalar(.null);
    const src = args[0].array;
    const slen: i64 = @intCast(src.entries.items.len);
    var offset = Value.toInt(args[1]);
    if (offset < 0) offset = @max(0, slen + offset);
    if (offset >= slen) {
        return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    }
    const uoffset: usize = @intCast(offset);
    var raw_length: i64 = if (args.len >= 3 and args[2] != .null) Value.toInt(args[2]) else slen - offset;
    if (raw_length < 0) raw_length = @max(0, slen - offset + raw_length);
    const length: usize = @intCast(@max(0, @min(slen - offset, raw_length)));
    const end = @min(src.entries.items.len, uoffset + length);
    const preserve_keys = args.len >= 4 and args[3].isTruthy();

    var arr = try ctx.createArray();
    for (src.entries.items[uoffset..end]) |entry| {
        switch (entry.key) {
            .string => try arr.set(ctx.allocator, entry.key, entry.value),
            .int => if (preserve_keys) {
                try arr.set(ctx.allocator, entry.key, entry.value);
            } else {
                try arr.append(ctx.allocator, entry.value);
            },
        }
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn array_unique(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(.null);
    const src = args[0].array;
    // default in PHP is SORT_STRING (2)
    const raw_flag: i64 = if (args.len >= 2) Value.toInt(args[1]) else 2;
    const case_insensitive = (raw_flag & 8) != 0; // SORT_FLAG_CASE
    const flag = raw_flag & ~@as(i64, 8);
    var arr = try ctx.createArray();
    for (src.entries.items) |entry| {
        var found = false;
        for (arr.entries.items) |existing| {
            const eq = switch (flag) {
                1 => Value.toFloat(entry.value) == Value.toFloat(existing.value), // SORT_NUMERIC
                2, 5, 6 => blk: { // SORT_STRING, SORT_LOCALE_STRING, SORT_NATURAL
                    const a_str = try valueAsStringForCompare(ctx, entry.value);
                    defer a_str.release();
                    const b_str = try valueAsStringForCompare(ctx, existing.value);
                    defer b_str.release();
                    break :blk if (case_insensitive) std.ascii.eqlIgnoreCase(a_str.bytes(), b_str.bytes()) else std.mem.eql(u8, a_str.bytes(), b_str.bytes());
                },
                else => Value.equal(entry.value, existing.value), // SORT_REGULAR
            };
            if (eq) {
                found = true;
                break;
            }
        }
        if (!found) try arr.set(ctx.allocator, entry.key, entry.value);
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn valueAsString(v: Value, buf: *[64]u8) []const u8 {
    return switch (v) {
        .string => |s| s.bytes(),
        .int => |i| std.fmt.bufPrint(buf, "{d}", .{i}) catch "",
        .float => |f| std.fmt.bufPrint(buf, "{d}", .{f}) catch "",
        .bool => |b| if (b) "1" else "",
        .null => "",
        else => "",
    };
}

fn valueAsStringForCompare(ctx: *NativeContext, v: Value) RuntimeError!Value.String {
    if (v == .object) {
        if (ctx.vm.hasMethod(v.object.class_name, "__toString")) {
            const result = try ctx.vm.callMethod(v.object, "__toString", &.{});
            if (result == .string) {
                result.string.retain();
                return result.string;
            }
        }
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Object of class {s} could not be converted to string", .{@import("../runtime/class_names.zig").display(v.object.class_name)}) catch "Object could not be converted to string";
        try ctx.vm.setPendingException("Error", msg);
        return error.RuntimeError;
    }
    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);
    try v.format(&buf, ctx.allocator);
    const owned = try buf.toOwnedSlice(ctx.allocator);
    return Value.String.adopt(ctx.allocator, owned);
}

fn throwArrayTypeError(ctx: *NativeContext, fn_name: []const u8, arg_pos: u8, got: Value) RuntimeError {
    const msg = std.fmt.allocPrint(ctx.allocator, "{s}(): Argument #{d} ($array) must be of type array, {s} given", .{ fn_name, arg_pos, phpTypeName(got) }) catch return error.RuntimeError;
    defer ctx.allocator.free(msg);
    ctx.vm.setPendingException("TypeError", msg) catch {};
    return error.RuntimeError;
}

fn reindexArray(arr: *PhpArray) void {
    for (arr.entries.items, 0..) |*entry, i| {
        if (entry.key == .string) entry.key.string.release();
        entry.key = .{ .int = @intCast(i) };
    }
    arr.next_int_key = @intCast(arr.entries.items.len);
    arr.has_int_keys = arr.entries.items.len > 0;
    arr.string_index.clearRetainingCapacity();
    arr.cursor = 0;
}

fn array_map(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.scalar(.null);
    for (args[1..], 1..) |a, i| {
        if (a != .array) {
            // PHP labels arg #2 as '($array)' but drops the param-name for
            // subsequent array args (#3 → 'Argument #3 must be of type array')
            const pos: u8 = @intCast(i + 1);
            const msg = if (pos == 2)
                try std.fmt.allocPrint(ctx.allocator, "array_map(): Argument #2 ($array) must be of type array, {s} given", .{phpTypeName(a)})
            else
                try std.fmt.allocPrint(ctx.allocator, "array_map(): Argument #{d} must be of type array, {s} given", .{ pos, phpTypeName(a) });
            defer ctx.allocator.free(msg);
            try ctx.vm.setPendingException("TypeError", msg);
            return error.RuntimeError;
        }
    }
    const callback = args[0];

    // null callback with multiple arrays = zip
    if (callback == .null and args.len > 2) {
        var max_len: usize = 0;
        for (args[1..]) |a| {
            if (a == .array) max_len = @max(max_len, a.array.entries.items.len);
        }
        var result = try ctx.createArray();
        for (0..max_len) |i| {
            var tuple = try ctx.createArray();
            for (args[1..]) |a| {
                if (a == .array and i < a.array.entries.items.len) {
                    try tuple.append(ctx.allocator, a.array.entries.items[i].value);
                } else {
                    try tuple.append(ctx.allocator, .null);
                }
            }
            try result.append(ctx.allocator, .{ .array = tuple });
        }
        return NativeResult.borrowed(.{ .array = result });
    }

    if (args[1] != .array) return NativeResult.scalar(.null);
    const src = args[1].array;

    // null callback with single array returns a copy preserving keys
    if (callback == .null) {
        var result = try ctx.createArray();
        for (src.entries.items) |entry| {
            try result.set(ctx.allocator, entry.key, entry.value);
        }
        return NativeResult.borrowed(.{ .array = result });
    }

    // multi-array: callback receives one element from each array
    if (args.len > 2) {
        var max_len: usize = 0;
        for (args[1..]) |a| {
            if (a == .array) max_len = @max(max_len, a.array.entries.items.len);
        }
        const n_arrays = args.len - 1;
        const cb_args_buf = try ctx.allocator.alloc(Value, n_arrays);
        defer ctx.allocator.free(cb_args_buf);
        var result = try ctx.createArray();
        for (0..max_len) |i| {
            for (0..n_arrays) |j| {
                const arr = if (args[1 + j] == .array) args[1 + j].array else null;
                cb_args_buf[j] = if (arr != null and i < arr.?.entries.items.len) arr.?.entries.items[i].value else .null;
            }
            const mapped = try ctx.invokeCallable(callback, cb_args_buf[0..n_arrays]);
            try result.append(ctx.allocator, mapped);
        }
        return NativeResult.borrowed(.{ .array = result });
    }

    var result = try ctx.createArray();
    for (src.entries.items) |entry| {
        const mapped = try ctx.invokeCallable(callback, &.{entry.value});
        try result.set(ctx.allocator, entry.key, mapped);
    }
    return NativeResult.borrowed(.{ .array = result });
}

fn array_filter(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(.null);
    const src = args[0].array;
    const flag: i64 = if (args.len >= 3) Value.toInt(args[2]) else 0;

    var result = try ctx.createArray();
    if (args.len < 2) {
        for (src.entries.items) |entry| {
            if (entry.value.isTruthy()) try result.set(ctx.allocator, entry.key, entry.value);
        }
    } else {
        for (src.entries.items) |entry| {
            const key_val: Value = switch (entry.key) {
                .int => |i| .{ .int = i },
                .string => |s| .{ .string = s },
            };
            const keep = if (flag == 1)
                // ARRAY_FILTER_USE_BOTH
                try ctx.invokeCallable(args[1], &.{ entry.value, key_val })
            else if (flag == 2)
                // ARRAY_FILTER_USE_KEY
                try ctx.invokeCallable(args[1], &.{key_val})
            else
                try ctx.invokeCallable(args[1], &.{entry.value});
            if (keep.isTruthy()) try result.set(ctx.allocator, entry.key, entry.value);
        }
    }
    return NativeResult.borrowed(.{ .array = result });
}

fn native_range(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.scalar(.null);

    // character range: single-char strings
    if (args[0] == .string and args[0].string.bytes().len == 1 and args[1] == .string and args[1].string.bytes().len == 1) {
        const lo = args[0].string.bytes()[0];
        const hi = args[1].string.bytes()[0];
        const step: u8 = if (args.len >= 3) @intCast(@max(1, Value.toInt(args[2]))) else 1;
        var arr = try ctx.createArray();
        if (lo <= hi) {
            var c = lo;
            while (c <= hi) {
                const s = try ctx.allocator.alloc(u8, 1);
                s[0] = c;
                const owned = try Value.String.adopt(ctx.allocator, s);
                defer owned.release();
                try arr.append(ctx.allocator, .{ .string = owned });
                if (c > hi - step) break;
                c += step;
            }
        } else {
            var c = lo;
            while (c >= hi) {
                const s = try ctx.allocator.alloc(u8, 1);
                s[0] = c;
                const owned = try Value.String.adopt(ctx.allocator, s);
                defer owned.release();
                try arr.append(ctx.allocator, .{ .string = owned });
                if (c < hi + step) break;
                c -= step;
            }
        }
        return NativeResult.borrowed(.{ .array = arr });
    }

    // use floats if any arg is a float
    const use_float = args[0] == .float or args[1] == .float or (args.len >= 3 and args[2] == .float);
    if (use_float) {
        const lo_f = Value.toFloat(args[0]);
        const hi_f = Value.toFloat(args[1]);
        const raw_step_f: f64 = if (args.len >= 3) Value.toFloat(args[2]) else 1.0;
        if (raw_step_f == 0) {
            try ctx.vm.setPendingException("ValueError", "range(): Argument #3 ($step) cannot be 0");
            return error.RuntimeError;
        }
        if (raw_step_f < 0 and lo_f < hi_f) {
            try ctx.vm.setPendingException("ValueError", "range(): Argument #3 ($step) must be greater than 0 for increasing ranges");
            return error.RuntimeError;
        }
        if (raw_step_f > 0 and lo_f > hi_f and args.len >= 3 and args[2] != .null) {
            // explicit positive step on a decreasing range is fine in PHP - no error
        }
        const step_f = @abs(raw_step_f);
        const span = @abs(hi_f - lo_f);
        if (step_f > span and lo_f != hi_f) {
            try ctx.vm.setPendingException("ValueError", "range(): Argument #3 ($step) must be less than the range spanned by argument #1 ($start) and argument #2 ($end)");
            return error.RuntimeError;
        }
        var arr = try ctx.createArray();
        const direction: f64 = if (lo_f <= hi_f) 1.0 else -1.0;
        const tol = step_f * 1e-9;
        var i: i64 = 0;
        while (true) {
            const v = lo_f + direction * step_f * @as(f64, @floatFromInt(i));
            if (direction > 0 and v > hi_f + tol) break;
            if (direction < 0 and v < hi_f - tol) break;
            try arr.append(ctx.allocator, .{ .float = v });
            i += 1;
            if (i > 100_000_000) break; // sanity cap
        }
        return NativeResult.borrowed(.{ .array = arr });
    }

    const lo = Value.toInt(args[0]);
    const hi = Value.toInt(args[1]);
    const raw_step: i64 = if (args.len >= 3) Value.toInt(args[2]) else 1;
    if (raw_step == 0) {
        try ctx.vm.setPendingException("ValueError", "range(): Argument #3 ($step) cannot be 0");
        return error.RuntimeError;
    }
    if (raw_step < 0 and lo < hi) {
        try ctx.vm.setPendingException("ValueError", "range(): Argument #3 ($step) must be greater than 0 for increasing ranges");
        return error.RuntimeError;
    }
    const step: i64 = if (raw_step < 0) -raw_step else raw_step;
    const span: i64 = if (lo <= hi) hi - lo else lo - hi;
    if (step > span and lo != hi) {
        try ctx.vm.setPendingException("ValueError", "range(): Argument #3 ($step) must be less than the range spanned by argument #1 ($start) and argument #2 ($end)");
        return error.RuntimeError;
    }
    var arr = try ctx.createArray();
    if (lo <= hi) {
        var i = lo;
        while (i <= hi) : (i += step) try arr.append(ctx.allocator, .{ .int = i });
    } else {
        var i = lo;
        while (i >= hi) : (i -= step) try arr.append(ctx.allocator, .{ .int = i });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn array_splice(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .array) return NativeResult.scalar(.null);
    const arr = args[0].array;
    const alen: i64 = @intCast(arr.entries.items.len);
    var offset = Value.toInt(args[1]);
    if (offset < 0) offset = @max(0, alen + offset);
    if (offset > alen) offset = alen;
    const uoffset: usize = @intCast(offset);

    var length: usize = if (args.len >= 3) blk: {
        var l = Value.toInt(args[2]);
        if (l < 0) l = @max(0, alen - offset + l);
        break :blk @intCast(@max(0, l));
    } else @intCast(alen - offset);
    length = @min(length, arr.entries.items.len - uoffset);

    const replacement_values: []Value = if (args.len >= 4 and args[3] == .array) blk: {
        const source = args[3].array.entries.items;
        const values = try ctx.allocator.alloc(Value, source.len);
        for (source, values) |entry, *value| {
            value.* = entry.value;
            VM.retainValue(value.*);
        }
        break :blk values;
    } else if (args.len >= 4 and args[3] == .object) blk: {
        const object = args[3].object.storage();
        var values: std.ArrayListUnmanaged(Value) = .empty;
        errdefer {
            for (values.items) |value| ctx.vm.releaseValue(value);
            values.deinit(ctx.allocator);
        }
        try values.ensureTotalCapacity(ctx.allocator, (if (object.slots) |slots| slots.len else 0) + object.properties.count());
        if (object.slots) |slots| {
            if (object.slot_layout) |layout| {
                for (slots, 0..) |value, i| {
                    const name = layout.names[i];
                    if (object.isLazySlot(name, layout.declaring_classes[i]) or object.isUnset(name)) continue;
                    const property = ctx.vm.findPropertyVisibility(layout.declaring_classes[i], name);
                    if (value == .null and ctx.vm.typedPropForbidsNull(property.type_str)) continue;
                    VM.retainValue(value);
                    values.appendAssumeCapacity(value);
                }
            }
        }
        for (object.properties.values()) |value| {
            VM.retainValue(value);
            values.appendAssumeCapacity(value);
        }
        break :blk try values.toOwnedSlice(ctx.allocator);
    } else blk: {
        const count: usize = if (args.len >= 4 and args[3] != .null) 1 else 0;
        const values = try ctx.allocator.alloc(Value, count);
        if (count != 0) {
            values[0] = args[3];
            VM.retainValue(values[0]);
        }
        break :blk values;
    };
    defer {
        for (replacement_values) |value| ctx.vm.releaseValue(value);
        ctx.allocator.free(replacement_values);
    }
    try arr.entries.ensureUnusedCapacity(ctx.allocator, replacement_values.len);
    const removed = try ctx.createArray();
    var removed_int_idx: i64 = 0;
    for (arr.entries.items[uoffset..][0..length]) |entry| {
        switch (entry.key) {
            .string => try removed.set(ctx.allocator, entry.key, entry.value),
            .int => {
                try removed.set(ctx.allocator, .{ .int = removed_int_idx }, entry.value);
                removed_int_idx += 1;
            },
        }
    }
    for (0..length) |_| ctx.vm.arrayRemoveOwned(arr, arr.entries.items[uoffset].key);
    for (replacement_values, 0..) |value, i| {
        VM.retainValue(value);
        arr.entries.insertAssumeCapacity(uoffset + i, .{ .key = .{ .int = 0 }, .value = value });
    }

    // re-index numeric keys
    var next_int: i64 = 0;
    for (arr.entries.items) |*entry| {
        if (entry.key == .int) {
            entry.key = .{ .int = next_int };
            next_int += 1;
        }
    }
    arr.next_int_key = next_int;
    arr.has_int_keys = next_int > 0;
    arr.rebuildStringIndexAssumeCapacity();

    return NativeResult.borrowed(.{ .array = removed });
}

fn array_combine(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .array or args[1] != .array) return NativeResult.scalar(.{ .bool = false });
    const keys_arr = args[0].array;
    const vals_arr = args[1].array;
    if (keys_arr.entries.items.len != vals_arr.entries.items.len) {
        const obj = try ctx.vm.allocObject(.{ .class_name = "ValueError" });
        try obj.set(ctx.allocator, "message", .{ .string = Value.String.borrowed("array_combine(): Argument #1 ($keys) and argument #2 ($values) must have the same number of elements") });
        try obj.set(ctx.allocator, "code", .{ .int = 0 });
        ctx.vm.raise(.{ .object = obj });
        return error.RuntimeError;
    }

    const arr = try ctx.createArray();
    for (keys_arr.entries.items, vals_arr.entries.items) |k, v| {
        if (k.value == .object or k.value == .array) {
            try ctx.vm.setPendingException("TypeError", "array_combine(): Argument #1 ($keys) must contain only string and integer keys");
            return error.RuntimeError;
        }
        // PHP array_combine casts each key to string first, then canonicalizes.
        var temporary: ?Value.String = null;
        defer if (temporary) |value| value.release();
        const key: PhpArray.Key = switch (k.value) {
            .int => |i| .{ .int = i },
            .string => |s| PhpArray.normalizeKey(.{ .string = s }),
            else => blk: {
                var buf = std.ArrayListUnmanaged(u8).empty;
                defer buf.deinit(ctx.allocator);
                try k.value.format(&buf, ctx.allocator);
                const owned = try buf.toOwnedSlice(ctx.allocator);
                temporary = try Value.String.adopt(ctx.allocator, owned);
                break :blk PhpArray.normalizeKey(.{ .string = temporary.? });
            },
        };
        try ctx.vm.arraySetOwned(arr, key, v.value);
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn array_chunk(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .array) return NativeResult.scalar(.null);
    const src = args[0].array;
    const raw_size = Value.toInt(args[1]);
    if (raw_size <= 0) {
        try ctx.vm.setPendingException("ValueError", "array_chunk(): Argument #2 ($length) must be greater than 0");
        return error.RuntimeError;
    }
    const size: usize = @intCast(raw_size);
    const preserve_keys = args.len >= 3 and Value.isTruthy(args[2]);

    var result = try ctx.createArray();
    var i: usize = 0;
    while (i < src.entries.items.len) {
        var chunk = try ctx.createArray();
        const end = @min(i + size, src.entries.items.len);
        for (src.entries.items[i..end]) |entry| {
            if (preserve_keys) {
                try chunk.set(ctx.allocator, entry.key, entry.value);
            } else {
                try chunk.append(ctx.allocator, entry.value);
            }
        }
        try result.append(ctx.allocator, .{ .array = chunk });
        i = end;
    }
    return NativeResult.borrowed(.{ .array = result });
}

fn array_pad(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 3 or args[0] != .array) return NativeResult.scalar(.null);
    const src = args[0].array;
    const target: i64 = Value.toInt(args[1]);
    const pad_val = args[2];
    const abs_target_i64: i64 = if (target < 0) -target else target;
    if (abs_target_i64 > 1_073_741_823) {
        try ctx.vm.setPendingException("ValueError", "array_pad(): Argument #2 ($length) must be less than or equal to 1073741823");
        return error.RuntimeError;
    }
    const abs_target: usize = @intCast(abs_target_i64);
    const current: usize = src.entries.items.len;

    var result = try ctx.createArray();
    if (current >= abs_target) {
        for (src.entries.items) |entry| try result.set(ctx.allocator, entry.key, entry.value);
        return NativeResult.borrowed(.{ .array = result });
    }

    const pad_count = abs_target - current;
    if (target < 0) {
        for (0..pad_count) |_| try result.append(ctx.allocator, pad_val);
    }
    // preserve original keys (string keys retain, int keys reindex via append)
    for (src.entries.items) |entry| {
        switch (entry.key) {
            .string => try result.set(ctx.allocator, entry.key, entry.value),
            .int => try result.append(ctx.allocator, entry.value),
        }
    }
    if (target > 0) {
        for (0..pad_count) |_| try result.append(ctx.allocator, pad_val);
    }
    return NativeResult.borrowed(.{ .array = result });
}

fn array_flip(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(.null);
    const src = args[0].array;
    const result = try ctx.createArray();
    for (src.entries.items) |entry| {
        if (entry.value != .int and entry.value != .string) continue;
        const new_key = Value.toArrayKey(entry.value);
        const new_val: Value = switch (entry.key) {
            .int => |i| .{ .int = i },
            .string => |s| .{ .string = s },
        };
        try ctx.vm.arraySetOwned(result, new_key, new_val);
    }
    return NativeResult.borrowed(.{ .array = result });
}

fn array_column(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .array) return NativeResult.scalar(.null);
    const src = args[0].array;
    const col_key = args[1];

    var result = try ctx.createArray();
    for (src.entries.items) |entry| {
        const row_val = entry.value;
        const is_array = row_val == .array;
        const is_object = row_val == .object;
        if (!is_array and !is_object) continue;

        const val = if (col_key == .null) row_val else v: {
            const v = rowGet(row_val, col_key);
            if (v == .null) continue;
            break :v v;
        };
        if (args.len >= 3 and args[2] != .null) {
            const idx_val = rowGet(row_val, args[2]);
            if (idx_val == .null) {
                try result.append(ctx.allocator, val);
            } else {
                try ctx.vm.arraySetOwned(result, Value.toArrayKey(idx_val), val);
            }
        } else {
            try result.append(ctx.allocator, val);
        }
    }
    return NativeResult.borrowed(.{ .array = result });
}

fn rowGet(row: Value, key: Value) Value {
    return switch (row) {
        .array => |a| a.get(Value.toArrayKey(key)),
        .object => |o| switch (key) {
            .string => |s| o.get(s.bytes()),
            .int => |i| blk: {
                var buf: [32]u8 = undefined;
                const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch break :blk .null;
                break :blk o.get(s);
            },
            else => .null,
        },
        else => .null,
    };
}

fn array_fill(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 3) return NativeResult.scalar(.null);
    const start_idx = Value.toInt(args[0]);
    const num = Value.toInt(args[1]);
    const val = args[2];
    if (num < 0) {
        try ctx.vm.setPendingException("ValueError", "array_fill(): Argument #2 ($count) must be greater than or equal to 0");
        return error.RuntimeError;
    }
    if (num > std.math.maxInt(i32)) {
        try ctx.vm.setPendingException("ValueError", "array_fill(): Argument #2 ($count) is too large");
        return error.RuntimeError;
    }
    if (num > 0 and start_idx > std.math.maxInt(i64) - num + 1) return nextElementOccupied(ctx);
    const count: usize = @intCast(num);

    var result = try ctx.createArray();
    try result.entries.ensureTotalCapacity(ctx.allocator, count);
    for (0..count) |i| {
        VM.retainValue(val);
        result.entries.appendAssumeCapacity(.{ .key = .{ .int = start_idx + @as(i64, @intCast(i)) }, .value = val });
    }
    if (count > 0) result.noteIntKey(start_idx + @as(i64, @intCast(count - 1)));
    return NativeResult.borrowed(.{ .array = result });
}

fn array_fill_keys(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .array) return NativeResult.scalar(.null);
    const keys_arr = args[0].array;
    const val = args[1];

    const result = try ctx.createArray();
    for (keys_arr.entries.items) |entry| {
        const key = try arrayFillKeysKey(ctx, entry.value);
        defer if (key == .string) key.string.release();
        try ctx.vm.arraySetOwned(result, key, val);
    }
    return NativeResult.borrowed(.{ .array = result });
}

// PHP's array_fill_keys uses a different key conversion than normal array
// assignment: floats become string "1.5" (instead of being truncated to 1),
// and bool false / null both become the empty string "" (not 0).
fn arrayFillKeysKey(ctx: *NativeContext, v: Value) !PhpArray.Key {
    return switch (v) {
        .int => |i| .{ .int = i },
        .string => |value| blk: {
            value.retain();
            break :blk .{ .string = value };
        },
        .bool => |b| if (b) PhpArray.Key{ .int = 1 } else PhpArray.Key{ .string = Value.String.borrowed("") },
        .null => .{ .string = Value.String.borrowed("") },
        .float => |f| blk: {
            var buf = std.ArrayListUnmanaged(u8).empty;
            defer buf.deinit(ctx.allocator);
            try (Value{ .float = f }).format(&buf, ctx.allocator);
            const s = try buf.toOwnedSlice(ctx.allocator);
            break :blk PhpArray.Key{ .string = try Value.String.adopt(ctx.allocator, s) };
        },
        else => .{ .int = 0 },
    };
}

fn array_count_values(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(.null);
    const src = args[0].array;
    var result = try ctx.createArray();
    for (src.entries.items) |entry| {
        if (entry.value != .string and entry.value != .int) {
            // PHP emits a warning per non-int/string entry encountered
            try ctx.vm.emitWarning("array_count_values(): Can only count string and integer values, entry skipped");
            continue;
        }
        const key = Value.toArrayKey(entry.value);
        const existing = result.get(key);
        if (existing == .int) {
            try result.set(ctx.allocator, key, .{ .int = existing.int + 1 });
        } else {
            try result.set(ctx.allocator, key, .{ .int = 1 });
        }
    }
    return NativeResult.borrowed(.{ .array = result });
}

fn array_sum(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .int = 0 });
    if (args[0] != .array) return throwArrayTypeError(ctx, "array_sum", 1, args[0]);
    const src = args[0].array;
    var has_float = false;
    var int_sum: i64 = 0;
    var float_sum: f64 = 0;
    for (src.entries.items) |entry| {
        switch (entry.value) {
            .int => |i| {
                int_sum +%= i;
                float_sum += @floatFromInt(i);
            },
            .float => |f| {
                has_float = true;
                float_sum += f;
            },
            else => {
                const operand = (try arithmeticOperand(ctx, entry.value, "array_sum(): Addition")) orelse continue;
                switch (operand) {
                    .int => |i| {
                        int_sum +%= i;
                        float_sum += @floatFromInt(i);
                    },
                    .float => |f| {
                        has_float = true;
                        float_sum += f;
                    },
                    else => {
                        const v = Value.toFloat(operand);
                        if (v != 0) {
                            float_sum += v;
                            if (v != @trunc(v)) has_float = true;
                            int_sum +%= Value.toInt(operand);
                        }
                    },
                }
            },
        }
    }
    if (has_float) return NativeResult.scalar(.{ .float = float_sum });
    return NativeResult.scalar(.{ .int = int_sum });
}

// an element array_sum/array_product can use: arrays and objects that do
// not convert to a number are skipped with php's warning
fn arithmeticOperand(ctx: *NativeContext, v: Value, comptime what: []const u8) RuntimeError!?Value {
    switch (v) {
        .array => {
            try ctx.vm.emitWarning(what ++ " is not supported on type array");
            return null;
        },
        .object => |o| {
            if (@import("../runtime/value.zig").nativeCast(o, .number)) |n| return n;
            const msg = try std.fmt.allocPrint(ctx.allocator, what ++ " is not supported on type {s}", .{o.class_name});
            defer ctx.allocator.free(msg);
            try ctx.vm.emitWarning(msg);
            return null;
        },
        else => return v,
    }
}

fn array_product(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .int = 0 });
    if (args[0] != .array) return throwArrayTypeError(ctx, "array_product", 1, args[0]);
    const src = args[0].array;
    if (src.entries.items.len == 0) return NativeResult.scalar(.{ .int = 1 });
    var has_float = false;
    var int_prod: i64 = 1;
    var float_prod: f64 = 1;
    for (src.entries.items) |entry| {
        switch (entry.value) {
            .int => |i| {
                int_prod *%= i;
                float_prod *= @floatFromInt(i);
            },
            .float => |f| {
                has_float = true;
                float_prod *= f;
            },
            else => {
                const operand = (try arithmeticOperand(ctx, entry.value, "array_product(): Multiplication")) orelse continue;
                if (operand == .float) has_float = true;
                int_prod *%= Value.toInt(operand);
                float_prod *= Value.toFloat(operand);
            },
        }
    }
    if (has_float) return NativeResult.scalar(.{ .float = float_prod });
    return NativeResult.scalar(.{ .int = int_prod });
}

fn array_walk(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.scalar(.{ .bool = false });
    if (args[0] != .array and !(args[0] == .object and ctx.vm.isInstanceOf(args[0].object.class_name, "Traversable"))) {
        try ctx.vm.setPendingException("TypeError", "array_walk(): Argument #1 ($array) must be of type array|object");
        return error.RuntimeError;
    }
    if (args[0] != .array) return NativeResult.scalar(.{ .bool = false });
    const arr = args[0].array;
    const callback = args[1];
    const has_userdata = args.len >= 3;

    // PHP's array_walk iterates by position (not snapshotted), so callbacks
    // that append to the array also have those new elements visited. track
    // by index and re-read len each step so growth is observed and removals
    // are skipped. when the callback removes the current entry the key
    // lookup re-locates by-key on writeback to apply to the original element
    var i: usize = 0;
    while (i < arr.entries.items.len) : (i += 1) {
        const key = arr.entries.items[i].key;
        if (key == .string) key.string.retain();
        defer if (key == .string) key.string.release();
        const key_val: Value = switch (key) {
            .int => |k| .{ .int = k },
            .string => |s| .{ .string = s },
        };
        var call_args = [3]Value{ arr.entries.items[i].value, key_val, if (has_userdata) args[2] else .null };
        const slice: []Value = if (has_userdata) call_args[0..3] else call_args[0..2];
        _ = try ctx.invokeCallableRef(callback, slice);
        // re-locate the original entry by key in case the callback reordered
        // or removed entries before it
        if (findEntryIndex(arr, key) != null) try ctx.vm.arraySetOwned(arr, key, call_args[0]);
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn findEntryIndex(arr: *PhpArray, key: PhpArray.Key) ?usize {
    if (key == .string) {
        if (arr.string_index.get(key.string.bytes())) |i| return i;
        return null;
    }
    for (arr.entries.items, 0..) |e, i| {
        if (e.key.eql(key)) return i;
    }
    return null;
}

fn array_unshift(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .array) return NativeResult.scalar(.{ .int = 0 });
    const arr = args[0].array;

    try arr.entries.ensureUnusedCapacity(ctx.allocator, args.len - 1);
    var insert_idx: usize = 0;
    for (args[1..]) |val| {
        VM.retainValue(val);
        try arr.entries.insert(ctx.allocator, insert_idx, .{ .key = .{ .int = 0 }, .value = val });
        insert_idx += 1;
    }
    // PHP renumbers all numeric keys starting from 0; string keys preserved
    var next_int: i64 = 0;
    for (arr.entries.items) |*entry| {
        if (entry.key == .int) {
            entry.key = .{ .int = next_int };
            next_int += 1;
        }
    }
    arr.next_int_key = next_int;
    arr.has_int_keys = next_int > 0;
    arr.rebuildStringIndexAssumeCapacity();
    return NativeResult.scalar(.{ .int = arr.length() });
}

fn native_shuffle(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(.{ .bool = false });
    const arr = args[0].array;
    var i: usize = arr.entries.items.len;
    while (i > 1) {
        i -= 1;
        const j = platform.random.intRangeAtMost(usize, 0, i);
        const tmp = arr.entries.items[i];
        arr.entries.items[i] = arr.entries.items[j];
        arr.entries.items[j] = tmp;
    }
    reindexArray(arr);
    return NativeResult.scalar(.{ .bool = true });
}

fn array_rand(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(.null);
    const arr = args[0].array;
    if (arr.entries.items.len == 0) return NativeResult.scalar(.null);
    const num: i64 = if (args.len >= 2) Value.toInt(args[1]) else 1;
    if (num < 1 or num > @as(i64, @intCast(arr.entries.items.len))) {
        try ctx.vm.setPendingException("ValueError", "array_rand(): Argument #2 ($num) must be between 1 and the number of elements in argument #1 ($array)");
        return error.RuntimeError;
    }
    // php returns a scalar key whenever num is 1, whether $num was omitted or
    // passed explicitly, an array of keys only for num > 1
    if (num == 1) {
        const idx = platform.random.intRangeAtMost(usize, 0, arr.entries.items.len - 1);
        return switch (arr.entries.items[idx].key) {
            .int => |i| NativeResult.scalar(.{ .int = i }),
            .string => |s| NativeResult.shareString(s),
        };
    }
    // Fisher-Yates partial shuffle for `num` distinct picks
    var pool = try ctx.allocator.alloc(usize, arr.entries.items.len);
    defer ctx.allocator.free(pool);
    for (0..pool.len) |i| pool[i] = i;
    var i: usize = 0;
    const n: usize = @intCast(num);
    while (i < n) : (i += 1) {
        const j = platform.random.intRangeAtMost(usize, i, pool.len - 1);
        const tmp = pool[i];
        pool[i] = pool[j];
        pool[j] = tmp;
    }
    // PHP returns the picks in ascending order of their original index
    std.mem.sort(usize, pool[0..n], {}, std.sort.asc(usize));
    const out = try ctx.createArray();
    for (pool[0..n]) |idx| {
        const v: Value = switch (arr.entries.items[idx].key) {
            .int => |k| .{ .int = k },
            .string => |s| .{ .string = s },
        };
        try out.append(ctx.allocator, v);
    }
    return NativeResult.borrowed(.{ .array = out });
}

fn native_compact(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    const frame = ctx.vm.currentFrame();
    for (args) |arg| try compactValue(ctx, arg, arr, frame);
    return NativeResult.borrowed(.{ .array = arr });
}

fn compactValue(ctx: *NativeContext, arg: Value, arr: *PhpArray, frame: anytype) RuntimeError!void {
    if (arg == .string) {
        const name = arg.string.bytes();
        const var_name = try std.fmt.allocPrint(ctx.allocator, "${s}", .{name});
        defer ctx.allocator.free(var_name);
        if (ctx.vm.frameVariable(frame, var_name)) |val| {
            try ctx.vm.arraySetOwned(arr, .{ .string = arg.string }, val);
        } else {
            const w = try std.fmt.allocPrint(ctx.allocator, "compact(): Undefined variable ${s}", .{name});
            defer ctx.allocator.free(w);
            try ctx.vm.emitWarning(w);
        }
    } else if (arg == .array) {
        // an array of names that contains itself is php's "Recursion detected"
        const names = arg.array;
        const Recursion = @import("../runtime/value.zig").Recursion;
        if (names.recursion & Recursion.gc != 0) {
            try ctx.vm.setPendingException("Error", "Recursion detected");
            return error.RuntimeError;
        }
        names.recursion |= Recursion.gc;
        defer names.recursion &= ~Recursion.gc;
        for (names.entries.items) |entry| try compactValue(ctx, entry.value, arr, frame);
    }
}

fn native_extract(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(.{ .int = 0 });
    const arr = args[0].array;
    const flags: i64 = if (args.len >= 2) Value.toInt(args[1]) else 0;
    // strip EXTR_REFS bit (256) so the type bits stay intact
    const type_flag = flags & 0xff;
    const prefix = if (args.len >= 3 and args[2] == .string) args[2].string.bytes() else "";
    const frame = ctx.vm.currentFrame();
    const slot_names = if (frame.func) |func| func.slot_names else ctx.vm.global_slot_names;

    const existsInScope = struct {
        fn f(fr: anytype, names: []const []const u8, name: []const u8) bool {
            for (names, 0..) |sn, i| {
                if (std.mem.eql(u8, sn, name)) {
                    if (i < fr.locals.len and fr.locals[i] != .undef) return true;
                    break;
                }
            }
            return fr.vars.contains(name);
        }
    }.f;

    const isValidIdent = struct {
        fn f(name: []const u8) bool {
            if (name.len <= 1) return false;
            const c0 = name[1];
            if (!(c0 == '_' or (c0 >= 'a' and c0 <= 'z') or (c0 >= 'A' and c0 <= 'Z'))) return false;
            var i: usize = 2;
            while (i < name.len) : (i += 1) {
                const c = name[i];
                if (!(c == '_' or (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9'))) return false;
            }
            return true;
        }
    }.f;

    var count_val: i64 = 0;
    for (arr.entries.items) |entry| {
        if (entry.key != .string) continue;
        const key = entry.key.string.bytes();
        const base = try ctx.vm.internVarName(key);
        const prefixed = try internVarName(ctx, "${s}_{s}", .{ prefix, key });

        var var_name: []const u8 = base;
        const base_valid = isValidIdent(base);

        switch (type_flag) {
            1 => { // EXTR_SKIP
                if (!base_valid or existsInScope(frame, slot_names, base)) continue;
            },
            2 => { // EXTR_PREFIX_SAME
                if (existsInScope(frame, slot_names, base)) var_name = prefixed;
                if (!isValidIdent(var_name)) continue;
            },
            3 => { // EXTR_PREFIX_ALL
                var_name = prefixed;
                if (!isValidIdent(var_name)) continue;
            },
            4 => { // EXTR_PREFIX_INVALID
                if (!base_valid) var_name = prefixed;
                if (!isValidIdent(var_name)) continue;
            },
            5 => { // EXTR_IF_EXISTS
                if (!base_valid or !existsInScope(frame, slot_names, base)) continue;
            },
            6 => { // EXTR_PREFIX_IF_EXISTS
                if (existsInScope(frame, slot_names, base)) {
                    var_name = prefixed;
                    if (!isValidIdent(var_name)) continue;
                } else {
                    if (!base_valid) continue;
                }
            },
            else => { // EXTR_OVERWRITE
                if (!base_valid) continue;
            },
        }

        try ctx.vm.setVariableByName(frame, var_name, try ctx.vm.copyValue(entry.value));
        count_val += 1;
    }
    return NativeResult.scalar(.{ .int = count_val });
}

// a variable name a frame's vars map will borrow: interned, so repeated calls
// reuse one copy
fn internVarName(ctx: *NativeContext, comptime fmt: []const u8, args: anytype) ![]const u8 {
    const name = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(name);
    return ctx.vm.internName(name);
}

fn array_reduce(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .array) return NativeResult.scalar(.null);
    const arr = args[0].array;
    var carry: Value = if (args.len >= 3) args[2] else .null;
    if (carry == .string) carry.string.retain();
    defer if (carry == .string) carry.string.release();
    for (arr.entries.items) |entry| {
        const next = try ctx.invokeCallable(args[1], &.{ carry, entry.value });
        if (next == .string) next.string.retain();
        if (carry == .string) carry.string.release();
        carry = next;
    }
    return NativeResult.share(carry);
}

fn retainReturnedString(value: Value) Value {
    if (value == .string) value.string.retain();
    return value;
}

fn array_key_first(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(.null);
    const arr = args[0].array;
    if (arr.entries.items.len == 0) return NativeResult.scalar(.null);
    return switch (arr.entries.items[0].key) {
        .int => |i| NativeResult.scalar(.{ .int = i }),
        .string => |s| NativeResult.shareString(s),
    };
}

fn array_key_last(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(.null);
    const arr = args[0].array;
    if (arr.entries.items.len == 0) return NativeResult.scalar(.null);
    return switch (arr.entries.items[arr.entries.items.len - 1].key) {
        .int => |i| NativeResult.scalar(.{ .int = i }),
        .string => |s| NativeResult.shareString(s),
    };
}

fn array_first(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // PHP 8.4
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(.null);
    const arr = args[0].array;
    if (arr.entries.items.len == 0) return NativeResult.scalar(.null);
    return NativeResult.share(arr.entries.items[0].value);
}

fn array_last(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // PHP 8.4
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(.null);
    const arr = args[0].array;
    if (arr.entries.items.len == 0) return NativeResult.scalar(.null);
    return NativeResult.share(arr.entries.items[arr.entries.items.len - 1].value);
}

fn array_replace(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // unlike array_merge, array_replace requires at least one argument
    if (args.len == 0) {
        try ctx.vm.setPendingException("ArgumentCountError", "array_replace() expects at least 1 argument, 0 given");
        return error.RuntimeError;
    }
    if (args[0] != .array) return NativeResult.scalar(.null);
    const result = try ctx.createArray();
    for (args[0].array.entries.items) |entry| {
        try ctx.vm.arraySetOwned(result, entry.key, entry.value);
    }
    for (args[1..]) |arg| {
        if (arg != .array) continue;
        for (arg.array.entries.items) |entry| {
            try ctx.vm.arraySetOwned(result, entry.key, entry.value);
        }
    }
    return NativeResult.borrowed(.{ .array = result });
}

fn array_find(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.scalar(.null);
    if (args[0] != .array) {
        try ctx.vm.setPendingException("TypeError", "array_find(): Argument #1 ($array) must be of type array");
        return error.RuntimeError;
    }
    const arr = args[0].array;
    for (arr.entries.items) |entry| {
        const key_val: Value = switch (entry.key) {
            .int => |i| .{ .int = i },
            .string => |s| .{ .string = s },
        };
        const result = try ctx.invokeCallable(args[1], &.{ entry.value, key_val });
        if (result.isTruthy()) return NativeResult.share(entry.value);
    }
    return NativeResult.scalar(.null);
}

fn array_find_key(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.scalar(.null);
    if (args[0] != .array) {
        try ctx.vm.setPendingException("TypeError", "array_find_key(): Argument #1 ($array) must be of type array");
        return error.RuntimeError;
    }
    const arr = args[0].array;
    for (arr.entries.items) |entry| {
        const key_val: Value = switch (entry.key) {
            .int => |i| .{ .int = i },
            .string => |s| .{ .string = s },
        };
        const result = try ctx.invokeCallable(args[1], &.{ entry.value, key_val });
        if (result.isTruthy()) {
            return switch (entry.key) {
                .int => |i| NativeResult.scalar(.{ .int = i }),
                .string => |s| NativeResult.shareString(s),
            };
        }
    }
    return NativeResult.scalar(.null);
}

fn array_any(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.scalar(.{ .bool = false });
    if (args[0] != .array) {
        try ctx.vm.setPendingException("TypeError", "array_any(): Argument #1 ($array) must be of type array");
        return error.RuntimeError;
    }
    const arr = args[0].array;
    for (arr.entries.items) |entry| {
        const key_val: Value = switch (entry.key) {
            .int => |i| .{ .int = i },
            .string => |s| .{ .string = s },
        };
        const result = try ctx.invokeCallable(args[1], &.{ entry.value, key_val });
        if (result.isTruthy()) return NativeResult.scalar(.{ .bool = true });
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn array_all(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.scalar(.{ .bool = true });
    if (args[0] != .array) {
        try ctx.vm.setPendingException("TypeError", "array_all(): Argument #1 ($array) must be of type array");
        return error.RuntimeError;
    }
    const arr = args[0].array;
    for (arr.entries.items) |entry| {
        const key_val: Value = switch (entry.key) {
            .int => |i| .{ .int = i },
            .string => |s| .{ .string = s },
        };
        const result = try ctx.invokeCallable(args[1], &.{ entry.value, key_val });
        if (!result.isTruthy()) return NativeResult.scalar(.{ .bool = false });
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn native_current(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(Value{ .bool = false });
    const arr = args[0].array;
    if (arr.cursor >= arr.entries.items.len) return NativeResult.scalar(Value{ .bool = false });
    return NativeResult.share(arr.entries.items[arr.cursor].value);
}

fn native_next(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(Value{ .bool = false });
    const arr = args[0].array;
    if (arr.cursor < arr.entries.items.len) arr.cursor += 1;
    if (arr.cursor >= arr.entries.items.len) return NativeResult.scalar(Value{ .bool = false });
    return NativeResult.share(arr.entries.items[arr.cursor].value);
}

fn native_prev(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(Value{ .bool = false });
    const arr = args[0].array;
    if (arr.cursor == 0 or arr.cursor > arr.entries.items.len) {
        arr.cursor = std.math.maxInt(usize);
        return NativeResult.scalar(Value{ .bool = false });
    }
    arr.cursor -= 1;
    return NativeResult.share(arr.entries.items[arr.cursor].value);
}

fn native_reset(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(Value{ .bool = false });
    const arr = args[0].array;
    arr.cursor = 0;
    if (arr.entries.items.len == 0) return NativeResult.scalar(Value{ .bool = false });
    return NativeResult.share(arr.entries.items[0].value);
}

fn native_end(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(Value{ .bool = false });
    const arr = args[0].array;
    if (arr.entries.items.len == 0) return NativeResult.scalar(Value{ .bool = false });
    arr.cursor = arr.entries.items.len - 1;
    return NativeResult.share(arr.entries.items[arr.cursor].value);
}

fn native_key(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(.null);
    const arr = args[0].array;
    if (arr.cursor >= arr.entries.items.len) return NativeResult.scalar(.null);
    return switch (arr.entries.items[arr.cursor].key) {
        .int => |i| NativeResult.scalar(.{ .int = i }),
        .string => |s| NativeResult.shareString(s),
    };
}

fn native_sizeof(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = args[0].array.length() });
}

fn deepReplace(ctx: *NativeContext, base: *PhpArray, overlay: *PhpArray) RuntimeError!*PhpArray {
    const result = try ctx.createArray();
    for (base.entries.items) |entry| {
        try ctx.vm.arraySetOwned(result, entry.key, entry.value);
    }
    for (overlay.entries.items) |entry| {
        const existing = result.get(entry.key);
        if (existing == .array and entry.value == .array) {
            const merged = try deepReplace(ctx, existing.array, entry.value.array);
            try ctx.vm.arraySetOwned(result, entry.key, .{ .array = merged });
        } else {
            try ctx.vm.arraySetOwned(result, entry.key, entry.value);
        }
    }
    return result;
}

fn array_replace_recursive(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(.null);
    var result = args[0].array;
    for (args[1..]) |arg| {
        if (arg != .array) continue;
        result = try deepReplace(ctx, result, arg.array);
    }
    return NativeResult.borrowed(.{ .array = result });
}

fn walkRecursive(ctx: *NativeContext, arr: *PhpArray, callback: Value, userdata: ?Value) RuntimeError!void {
    for (arr.entries.items) |entry| {
        if (entry.value == .array) {
            try walkRecursive(ctx, entry.value.array, callback, userdata);
        } else {
            const key_val: Value = switch (entry.key) {
                .int => |k| Value{ .int = k },
                .string => |s| Value{ .string = s },
            };
            var call_args = [3]Value{ entry.value, key_val, userdata orelse .null };
            const slice: []Value = if (userdata != null) call_args[0..3] else call_args[0..2];
            _ = try ctx.invokeCallableRef(callback, slice);
            try ctx.vm.arraySetOwned(arr, entry.key, call_args[0]);
        }
    }
}

fn array_walk_recursive(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .array) return NativeResult.scalar(.{ .bool = false });
    const userdata: ?Value = if (args.len >= 3) args[2] else null;
    try walkRecursive(ctx, args[0].array, args[1], userdata);
    return NativeResult.scalar(.{ .bool = true });
}

// php_array_merge_recursive: integer keys are appended; a string key already
// in dest turns that entry into an array (a scalar becomes its only element,
// null an array holding null) and src's value is merged into it, an array
// recursively and anything else appended
fn mergeRecursiveInto(ctx: *NativeContext, dest: *PhpArray, src: *PhpArray) RuntimeError!void {
    for (src.entries.items) |entry| {
        const value = if (entry.ref) |ref| ref.* else entry.value;
        switch (entry.key) {
            .int => if (!try dest.appendNew(ctx.allocator, value)) {
                _ = try nextElementOccupied(ctx);
            },
            .string => {
                if (!dest.contains(entry.key)) {
                    try ctx.vm.arraySetOwned(dest, entry.key, value);
                    continue;
                }
                const existing = dest.get(entry.key);
                // the array being merged into is protected while its merge
                // runs: meeting it again is php's "Recursion detected"
                const Recursion = @import("../runtime/value.zig").Recursion;
                const protected: ?*PhpArray = if (existing == .array) existing.array else null;
                if (protected) |arr| if (arr.recursion & Recursion.gc != 0) {
                    try ctx.vm.setPendingException("Error", "Recursion detected");
                    return error.RuntimeError;
                };
                const target = try ctx.vm.allocArray();
                switch (existing) {
                    .array => |arr| for (arr.entries.items) |e| try target.set(ctx.allocator, e.key, if (e.ref) |ref| ref.* else e.value),
                    .null => try target.append(ctx.allocator, .null),
                    else => {
                        const converted = try ctx.vm.castToArray(existing);
                        for (converted.array.entries.items) |e| try target.set(ctx.allocator, e.key, e.value);
                    },
                }
                try ctx.vm.arraySetOwned(dest, entry.key, .{ .array = target });
                const incoming = if (value == .object) try ctx.vm.castToArray(value) else value;
                if (incoming == .array) {
                    if (protected) |arr| arr.recursion |= Recursion.gc;
                    defer if (protected) |arr| {
                        arr.recursion &= ~Recursion.gc;
                    };
                    try mergeRecursiveInto(ctx, target, incoming.array);
                } else if (!try target.appendNew(ctx.allocator, incoming)) {
                    _ = try nextElementOccupied(ctx);
                }
            },
        }
    }
}

fn array_merge_recursive(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // PHP allows array_merge_recursive() with no arguments, returning []
    if (args.len == 0) return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    for (args, 1..) |arg, position| {
        if (arg == .array) continue;
        const msg = try std.fmt.allocPrint(ctx.allocator, "array_merge_recursive(): Argument #{d} must be of type array, {s} given", .{ position, phpTypeName(arg) });
        defer ctx.allocator.free(msg);
        try ctx.vm.setPendingException("TypeError", msg);
        return error.RuntimeError;
    }
    const result = try ctx.createArray();
    for (args) |arg| try mergeRecursiveInto(ctx, result, arg.array);
    return NativeResult.borrowed(.{ .array = result });
}

fn array_change_key_case(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(.null);
    const src = args[0].array;
    const case_upper = args.len >= 2 and args[1] == .int and args[1].int == 1;
    const result = try ctx.createArray();

    for (src.entries.items) |entry| {
        const new_key: PhpArray.Key = switch (entry.key) {
            .string => |s| blk: {
                const buf = try ctx.allocator.alloc(u8, s.bytes().len);
                for (s.bytes(), 0..) |c, i| {
                    buf[i] = if (case_upper) std.ascii.toUpper(c) else std.ascii.toLower(c);
                }
                break :blk .{ .string = try Value.String.adopt(ctx.allocator, buf) };
            },
            .int => entry.key,
        };
        defer if (new_key == .string) new_key.string.release();
        try ctx.vm.arraySetOwned(result, new_key, entry.value);
    }
    return NativeResult.borrowed(.{ .array = result });
}

test "unshift allocation failure preserves entries and ownership" {
    const testing = std.testing;
    var vm = try VM.init(testing.allocator);
    defer vm.deinit();
    const arr = try vm.allocArray();
    const owned = try Value.String.create(testing.allocator, "owned");
    defer owned.release();
    var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    var ctx: NativeContext = .{ .allocator = failing.allocator(), .arrays = &vm.arrays, .strings = &vm.strings, .vm = &vm };
    const count = owned.owner.?.refcount;
    try testing.expectError(error.OutOfMemory, array_unshift(&ctx, &.{ .{ .array = arr }, .{ .string = owned } }));
    try testing.expectEqual(@as(usize, 0), arr.entries.items.len);
    try testing.expectEqual(count, owned.owner.?.refcount);
    ctx.allocator = testing.allocator;
    _ = try array_unshift(&ctx, &.{ .{ .array = arr }, .{ .string = owned } });
    try testing.expectEqualStrings("owned", arr.get(.{ .int = 0 }).string.bytes());
}
