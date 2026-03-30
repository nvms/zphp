const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
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
    .{ "sort", native_sort },
    .{ "rsort", native_rsort },
    .{ "range", native_range },
    .{ "array_map", array_map },
    .{ "array_filter", array_filter },
    .{ "usort", native_usort },
    .{ "array_splice", array_splice },
    .{ "array_combine", array_combine },
    .{ "array_chunk", array_chunk },
    .{ "array_pad", array_pad },
    .{ "array_flip", array_flip },
    .{ "array_column", array_column },
    .{ "array_fill", array_fill },
    .{ "array_fill_keys", array_fill_keys },
    .{ "array_intersect", array_intersect },
    .{ "array_diff", array_diff },
    .{ "array_diff_key", array_diff_key },
    .{ "array_count_values", array_count_values },
    .{ "array_sum", array_sum },
    .{ "array_product", array_product },
    .{ "array_walk", array_walk },
    .{ "array_unshift", array_unshift },
    .{ "shuffle", native_shuffle },
    .{ "array_rand", array_rand },
    .{ "compact", native_compact },
    .{ "extract", native_extract },
    .{ "ksort", native_ksort },
    .{ "krsort", native_krsort },
    .{ "asort", native_asort },
    .{ "arsort", native_arsort },
    .{ "array_reduce", array_reduce },
    .{ "array_key_first", array_key_first },
    .{ "array_key_last", array_key_last },
    .{ "uasort", native_uasort },
    .{ "uksort", native_uksort },
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
    .{ "array_intersect_key", array_intersect_key },
    .{ "array_diff_assoc", array_diff_assoc },
    .{ "array_replace_recursive", array_replace_recursive },
    .{ "array_walk_recursive", array_walk_recursive },
    .{ "array_merge_recursive", array_merge_recursive },
    .{ "array_intersect_assoc", array_intersect_assoc },
    .{ "array_multisort", array_multisort },
    .{ "array_diff_uassoc", array_diff_uassoc },
    .{ "array_diff_ukey", array_diff_ukey },
    .{ "array_change_key_case", array_change_key_case },
};

fn array_push(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .{ .int = 0 };
    const arr = args[0].array;
    for (args[1..]) |val| try arr.append(ctx.allocator, val);
    return .{ .int = arr.length() };
}

fn array_pop(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .null;
    const arr = args[0].array;
    if (arr.entries.items.len == 0) return .null;
    return (arr.entries.pop() orelse return .null).value;
}

fn array_shift(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .null;
    const arr = args[0].array;
    if (arr.entries.items.len == 0) return .null;
    const first = arr.entries.orderedRemove(0);
    return first.value;
}

fn array_keys(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .null;
    const src = args[0].array;
    var arr = try ctx.createArray();
    for (src.entries.items) |entry| {
        const key_val: Value = switch (entry.key) {
            .int => |i| .{ .int = i },
            .string => |s| .{ .string = s },
        };
        try arr.append(ctx.allocator, key_val);
    }
    return .{ .array = arr };
}

fn array_is_list(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .{ .bool = false };
    const arr = args[0].array;
    for (arr.entries.items, 0..) |entry, i| {
        switch (entry.key) {
            .int => |k| {
                if (k != @as(i64, @intCast(i))) return .{ .bool = false };
            },
            .string => return .{ .bool = false },
        }
    }
    return .{ .bool = true };
}

fn array_values(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .null;
    const src = args[0].array;
    var arr = try ctx.createArray();
    for (src.entries.items) |entry| {
        try arr.append(ctx.allocator, entry.value);
    }
    return .{ .array = arr };
}

fn in_array(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[1] != .array) return .{ .bool = false };
    const needle = args[0];
    const arr = args[1].array;
    const strict = args.len >= 3 and args[2].isTruthy();
    for (arr.entries.items) |entry| {
        if (strict) {
            if (Value.identical(needle, entry.value)) return .{ .bool = true };
        } else {
            if (Value.equal(needle, entry.value)) return .{ .bool = true };
        }
    }
    return .{ .bool = false };
}

fn array_key_exists(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[1] != .array) return .{ .bool = false };
    const key = Value.toArrayKey(args[0]);
    const arr = args[1].array;
    for (arr.entries.items) |entry| {
        if (entry.key.eql(key)) return .{ .bool = true };
    }
    return .{ .bool = false };
}

fn array_search(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[1] != .array) return .{ .bool = false };
    const needle = args[0];
    const arr = args[1].array;
    for (arr.entries.items) |entry| {
        if (Value.equal(needle, entry.value)) {
            return switch (entry.key) {
                .int => |i| .{ .int = i },
                .string => |s| .{ .string = s },
            };
        }
    }
    return .{ .bool = false };
}

fn array_reverse(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .null;
    const src = args[0].array;
    var arr = try ctx.createArray();
    var i: usize = src.entries.items.len;
    while (i > 0) {
        i -= 1;
        try arr.append(ctx.allocator, src.entries.items[i].value);
    }
    return .{ .array = arr };
}

fn array_merge(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    var arr = try ctx.createArray();
    for (args) |arg| {
        if (arg != .array) continue;
        for (arg.array.entries.items) |entry| {
            switch (entry.key) {
                .int => try arr.append(ctx.allocator, entry.value),
                .string => |s| try arr.set(ctx.allocator, .{ .string = s }, entry.value),
            }
        }
    }
    return .{ .array = arr };
}

fn array_slice(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .null;
    const src = args[0].array;
    const slen: i64 = @intCast(src.entries.items.len);
    var offset = Value.toInt(args[1]);
    if (offset < 0) offset = @max(0, slen + offset);
    if (offset >= slen) {
        return .{ .array = try ctx.createArray() };
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
    return .{ .array = arr };
}

fn array_unique(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .null;
    const src = args[0].array;
    var arr = try ctx.createArray();
    for (src.entries.items) |entry| {
        var found = false;
        for (arr.entries.items) |existing| {
            if (Value.equal(entry.value, existing.value)) {
                found = true;
                break;
            }
        }
        if (!found) try arr.set(ctx.allocator, entry.key, entry.value);
    }
    return .{ .array = arr };
}

fn native_sort(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .{ .bool = false };
    const arr = args[0].array;
    std.mem.sort(PhpArray.Entry, arr.entries.items, {}, struct {
        fn lessThan(_: void, a: PhpArray.Entry, b: PhpArray.Entry) bool {
            return Value.lessThan(a.value, b.value);
        }
    }.lessThan);
    reindexArray(arr);
    return .{ .bool = true };
}

fn native_rsort(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .{ .bool = false };
    const arr = args[0].array;
    std.mem.sort(PhpArray.Entry, arr.entries.items, {}, struct {
        fn lessThan(_: void, a: PhpArray.Entry, b: PhpArray.Entry) bool {
            return Value.lessThan(b.value, a.value);
        }
    }.lessThan);
    reindexArray(arr);
    return .{ .bool = true };
}

fn reindexArray(arr: *PhpArray) void {
    for (arr.entries.items, 0..) |*entry, i| entry.key = .{ .int = @intCast(i) };
    arr.next_int_key = @intCast(arr.entries.items.len);
}

fn array_map(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .null;
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
        return .{ .array = result };
    }

    if (args[1] != .array) return .null;
    const src = args[1].array;

    // null callback with single array returns a copy
    if (callback == .null) {
        var result = try ctx.createArray();
        for (src.entries.items) |entry| {
            try result.append(ctx.allocator, entry.value);
        }
        return .{ .array = result };
    }

    // multi-array: callback receives one element from each array
    if (args.len > 2) {
        var max_len: usize = 0;
        for (args[1..]) |a| {
            if (a == .array) max_len = @max(max_len, a.array.entries.items.len);
        }
        var cb_args_buf: [8]Value = undefined;
        const n_arrays = args.len - 1;
        var result = try ctx.createArray();
        for (0..max_len) |i| {
            for (0..n_arrays) |j| {
                const arr = if (args[1 + j] == .array) args[1 + j].array else null;
                cb_args_buf[j] = if (arr != null and i < arr.?.entries.items.len) arr.?.entries.items[i].value else .null;
            }
            const mapped = try ctx.invokeCallable(callback, cb_args_buf[0..n_arrays]);
            try result.append(ctx.allocator, mapped);
        }
        return .{ .array = result };
    }

    var result = try ctx.createArray();
    for (src.entries.items) |entry| {
        const mapped = try ctx.invokeCallable(callback, &.{entry.value});
        try result.set(ctx.allocator, entry.key, mapped);
    }
    return .{ .array = result };
}

fn array_filter(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .null;
    const src = args[0].array;

    var result = try ctx.createArray();
    if (args.len < 2) {
        for (src.entries.items) |entry| {
            if (entry.value.isTruthy()) try result.set(ctx.allocator, entry.key, entry.value);
        }
    } else {
        for (src.entries.items) |entry| {
            const keep = try ctx.invokeCallable(args[1], &.{entry.value});
            if (keep.isTruthy()) try result.set(ctx.allocator, entry.key, entry.value);
        }
    }
    return .{ .array = result };
}

fn native_usort(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .{ .bool = false };
    const arr = args[0].array;
    const callback = args[1];

    var n = arr.entries.items.len;
    while (n > 1) {
        var swapped = false;
        for (0..n - 1) |i| {
            const a_val = arr.entries.items[i].value;
            const b_val = arr.entries.items[i + 1].value;
            const cmp = try ctx.invokeCallable(callback, &.{ a_val, b_val });
            if (Value.toInt(cmp) > 0) {
                const tmp = arr.entries.items[i];
                arr.entries.items[i] = arr.entries.items[i + 1];
                arr.entries.items[i + 1] = tmp;
                swapped = true;
            }
        }
        if (!swapped) break;
        n -= 1;
    }
    reindexArray(arr);
    return .{ .bool = true };
}

fn native_range(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .null;

    // character range: single-char strings
    if (args[0] == .string and args[0].string.len == 1 and args[1] == .string and args[1].string.len == 1) {
        const lo = args[0].string[0];
        const hi = args[1].string[0];
        const step: u8 = if (args.len >= 3) @intCast(@max(1, Value.toInt(args[2]))) else 1;
        var arr = try ctx.createArray();
        if (lo <= hi) {
            var c = lo;
            while (c <= hi) {
                const s = try ctx.allocator.alloc(u8, 1);
                s[0] = c;
                try ctx.strings.append(ctx.allocator, s);
                try arr.append(ctx.allocator, .{ .string = s });
                if (c > hi - step) break;
                c += step;
            }
        } else {
            var c = lo;
            while (c >= hi) {
                const s = try ctx.allocator.alloc(u8, 1);
                s[0] = c;
                try ctx.strings.append(ctx.allocator, s);
                try arr.append(ctx.allocator, .{ .string = s });
                if (c < hi + step) break;
                c -= step;
            }
        }
        return .{ .array = arr };
    }

    const lo = Value.toInt(args[0]);
    const hi = Value.toInt(args[1]);
    const step = if (args.len >= 3) @max(1, Value.toInt(args[2])) else @as(i64, 1);
    var arr = try ctx.createArray();
    if (lo <= hi) {
        var i = lo;
        while (i <= hi) : (i += step) try arr.append(ctx.allocator, .{ .int = i });
    } else {
        var i = lo;
        while (i >= hi) : (i -= step) try arr.append(ctx.allocator, .{ .int = i });
    }
    return .{ .array = arr };
}

fn array_splice(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .null;
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

    var removed = try ctx.createArray();
    for (0..length) |_| {
        const entry = arr.entries.orderedRemove(uoffset);
        try removed.append(ctx.allocator, entry.value);
    }

    if (args.len >= 4 and args[3] == .array) {
        const replacement = args[3].array;
        var insert_idx = uoffset;
        for (replacement.entries.items) |entry| {
            try arr.entries.insert(ctx.allocator, insert_idx, .{ .key = .{ .int = 0 }, .value = entry.value });
            insert_idx += 1;
        }
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

    return .{ .array = removed };
}

fn array_combine(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array or args[1] != .array) return .{ .bool = false };
    const keys_arr = args[0].array;
    const vals_arr = args[1].array;
    if (keys_arr.entries.items.len != vals_arr.entries.items.len) return .{ .bool = false };

    var arr = try ctx.createArray();
    for (keys_arr.entries.items, vals_arr.entries.items) |k, v| {
        const key = Value.toArrayKey(k.value);
        try arr.set(ctx.allocator, key, v.value);
    }
    return .{ .array = arr };
}

fn array_chunk(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .null;
    const src = args[0].array;
    const size: usize = @intCast(@max(1, Value.toInt(args[1])));
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
    return .{ .array = result };
}

fn array_pad(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[0] != .array) return .null;
    const src = args[0].array;
    const target: i64 = Value.toInt(args[1]);
    const pad_val = args[2];
    const abs_target: usize = @intCast(if (target < 0) -target else target);
    const current: usize = src.entries.items.len;

    if (current >= abs_target) {
        var result = try ctx.createArray();
        for (src.entries.items) |entry| try result.append(ctx.allocator, entry.value);
        return .{ .array = result };
    }

    var result = try ctx.createArray();
    const pad_count = abs_target - current;
    if (target < 0) {
        for (0..pad_count) |_| try result.append(ctx.allocator, pad_val);
    }
    for (src.entries.items) |entry| try result.append(ctx.allocator, entry.value);
    if (target > 0) {
        for (0..pad_count) |_| try result.append(ctx.allocator, pad_val);
    }
    return .{ .array = result };
}

fn array_flip(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .null;
    const src = args[0].array;
    var result = try ctx.createArray();
    for (src.entries.items) |entry| {
        const new_key = Value.toArrayKey(entry.value);
        const new_val: Value = switch (entry.key) {
            .int => |i| .{ .int = i },
            .string => |s| .{ .string = s },
        };
        try result.set(ctx.allocator, new_key, new_val);
    }
    return .{ .array = result };
}

fn array_column(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .null;
    const src = args[0].array;
    const col_key = args[1];

    var result = try ctx.createArray();
    for (src.entries.items) |entry| {
        if (entry.value != .array) continue;
        const row = entry.value.array;
        const val = if (col_key == .null) entry.value else blk: {
            const v = row.get(Value.toArrayKey(col_key));
            if (v == .null) continue;
            break :blk v;
        };
        if (args.len >= 3 and args[2] != .null) {
            const idx_key = Value.toArrayKey(args[2]);
            const idx_val = row.get(idx_key);
            try result.set(ctx.allocator, Value.toArrayKey(idx_val), val);
        } else {
            try result.append(ctx.allocator, val);
        }
    }
    return .{ .array = result };
}

fn array_fill(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3) return .null;
    const start_idx = Value.toInt(args[0]);
    const count: usize = @intCast(@max(0, Value.toInt(args[1])));
    const val = args[2];

    var result = try ctx.createArray();
    for (0..count) |i| {
        try result.set(ctx.allocator, .{ .int = start_idx + @as(i64, @intCast(i)) }, val);
    }
    return .{ .array = result };
}

fn array_fill_keys(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .null;
    const keys_arr = args[0].array;
    const val = args[1];

    var result = try ctx.createArray();
    for (keys_arr.entries.items) |entry| {
        try result.set(ctx.allocator, Value.toArrayKey(entry.value), val);
    }
    return .{ .array = result };
}

fn array_intersect(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .null;
    const src = args[0].array;

    var result = try ctx.createArray();
    for (src.entries.items) |entry| {
        var in_all = true;
        for (args[1..]) |arg| {
            if (arg != .array) {
                in_all = false;
                break;
            }
            var found = false;
            for (arg.array.entries.items) |other| {
                if (Value.equal(entry.value, other.value)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                in_all = false;
                break;
            }
        }
        if (in_all) try result.set(ctx.allocator, entry.key, entry.value);
    }
    return .{ .array = result };
}

fn array_diff(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .null;
    const src = args[0].array;

    var result = try ctx.createArray();
    for (src.entries.items) |entry| {
        var in_any = false;
        for (args[1..]) |arg| {
            if (arg != .array) continue;
            for (arg.array.entries.items) |other| {
                if (Value.equal(entry.value, other.value)) {
                    in_any = true;
                    break;
                }
            }
            if (in_any) break;
        }
        if (!in_any) try result.set(ctx.allocator, entry.key, entry.value);
    }
    return .{ .array = result };
}

fn array_diff_key(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .null;
    const src = args[0].array;

    var result = try ctx.createArray();
    for (src.entries.items) |entry| {
        var in_any = false;
        for (args[1..]) |arg| {
            if (arg != .array) continue;
            for (arg.array.entries.items) |other| {
                if (entry.key.eql(other.key)) {
                    in_any = true;
                    break;
                }
            }
            if (in_any) break;
        }
        if (!in_any) try result.set(ctx.allocator, entry.key, entry.value);
    }
    return .{ .array = result };
}

fn array_count_values(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .null;
    const src = args[0].array;
    var result = try ctx.createArray();
    for (src.entries.items) |entry| {
        if (entry.value != .string and entry.value != .int) continue;
        const key = Value.toArrayKey(entry.value);
        const existing = result.get(key);
        if (existing == .int) {
            try result.set(ctx.allocator, key, .{ .int = existing.int + 1 });
        } else {
            try result.set(ctx.allocator, key, .{ .int = 1 });
        }
    }
    return .{ .array = result };
}

fn array_sum(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .{ .int = 0 };
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
                const v = Value.toFloat(entry.value);
                if (v != 0) {
                    float_sum += v;
                    if (v != @trunc(v)) has_float = true;
                    int_sum +%= Value.toInt(entry.value);
                }
            },
        }
    }
    if (has_float) return .{ .float = float_sum };
    return .{ .int = int_sum };
}

fn array_product(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .{ .int = 0 };
    const src = args[0].array;
    if (src.entries.items.len == 0) return .{ .int = 1 };
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
                int_prod *%= Value.toInt(entry.value);
                float_prod *= Value.toFloat(entry.value);
            },
        }
    }
    if (has_float) return .{ .float = float_prod };
    return .{ .int = int_prod };
}

fn array_walk(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .{ .bool = false };
    const arr = args[0].array;
    const callback = args[1];

    for (arr.entries.items, 0..) |entry, idx| {
        const key_val: Value = switch (entry.key) {
            .int => |k| .{ .int = k },
            .string => |s| .{ .string = s },
        };
        var call_args = [2]Value{ entry.value, key_val };
        _ = try ctx.invokeCallableRef(callback, &call_args);
        arr.entries.items[idx].value = call_args[0];
    }
    return .{ .bool = true };
}

fn array_unshift(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .{ .int = 0 };
    const arr = args[0].array;

    var insert_idx: usize = 0;
    for (args[1..]) |val| {
        try arr.entries.insert(ctx.allocator, insert_idx, .{ .key = .{ .int = 0 }, .value = val });
        insert_idx += 1;
    }
    return .{ .int = arr.length() };
}

fn native_shuffle(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .{ .bool = false };
    const arr = args[0].array;
    var i: usize = arr.entries.items.len;
    while (i > 1) {
        i -= 1;
        const j = std.crypto.random.intRangeAtMost(usize, 0, i);
        const tmp = arr.entries.items[i];
        arr.entries.items[i] = arr.entries.items[j];
        arr.entries.items[j] = tmp;
    }
    reindexArray(arr);
    return .{ .bool = true };
}

fn array_rand(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .null;
    const arr = args[0].array;
    if (arr.entries.items.len == 0) return .null;
    const idx = std.crypto.random.intRangeAtMost(usize, 0, arr.entries.items.len - 1);
    return switch (arr.entries.items[idx].key) {
        .int => |i| .{ .int = i },
        .string => |s| .{ .string = s },
    };
}

fn native_compact(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const arr = try ctx.createArray();
    const frame = ctx.vm.currentFrame();
    const slot_names = if (frame.func) |func| func.slot_names else ctx.vm.global_slot_names;
    for (args) |arg| {
        if (arg != .string) continue;
        const name = arg.string;
        const var_name = try std.fmt.allocPrint(ctx.allocator, "${s}", .{name});
        try ctx.strings.append(ctx.allocator, var_name);
        var found = false;
        for (slot_names, 0..) |sn, i| {
            if (std.mem.eql(u8, sn, var_name)) {
                if (i < frame.locals.len and frame.locals[i] != .null) {
                    try arr.set(ctx.allocator, .{ .string = name }, frame.locals[i]);
                    found = true;
                }
                break;
            }
        }
        if (!found) {
            if (frame.vars.get(var_name)) |val| {
                try arr.set(ctx.allocator, .{ .string = name }, val);
            }
        }
    }
    return .{ .array = arr };
}

fn native_extract(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .{ .int = 0 };
    const arr = args[0].array;
    const frame = ctx.vm.currentFrame();
    var count_val: i64 = 0;
    for (arr.entries.items) |entry| {
        if (entry.key != .string) continue;
        const var_name = try std.fmt.allocPrint(ctx.allocator, "${s}", .{entry.key.string});
        try ctx.strings.append(ctx.allocator, var_name);
        try frame.vars.put(ctx.allocator, var_name, entry.value);
        count_val += 1;
    }
    return .{ .int = count_val };
}

fn keyLessThan(_: void, a: PhpArray.Entry, b: PhpArray.Entry) bool {
    if (a.key == .int and b.key == .int) return a.key.int < b.key.int;
    if (a.key == .string and b.key == .string) return std.mem.order(u8, a.key.string, b.key.string) == .lt;
    if (a.key == .int) return true;
    return false;
}

fn native_ksort(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .{ .bool = false };
    const arr = args[0].array;
    std.mem.sort(PhpArray.Entry, arr.entries.items, {}, keyLessThan);
    return .{ .bool = true };
}

fn native_krsort(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .{ .bool = false };
    const arr = args[0].array;
    std.mem.sort(PhpArray.Entry, arr.entries.items, {}, struct {
        fn f(_: void, a: PhpArray.Entry, b: PhpArray.Entry) bool {
            return keyLessThan({}, b, a);
        }
    }.f);
    return .{ .bool = true };
}

fn native_asort(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .{ .bool = false };
    const arr = args[0].array;
    std.mem.sort(PhpArray.Entry, arr.entries.items, {}, struct {
        fn f(_: void, a: PhpArray.Entry, b: PhpArray.Entry) bool {
            return Value.lessThan(a.value, b.value);
        }
    }.f);
    return .{ .bool = true };
}

fn native_arsort(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .{ .bool = false };
    const arr = args[0].array;
    std.mem.sort(PhpArray.Entry, arr.entries.items, {}, struct {
        fn f(_: void, a: PhpArray.Entry, b: PhpArray.Entry) bool {
            return Value.lessThan(b.value, a.value);
        }
    }.f);
    return .{ .bool = true };
}

fn array_reduce(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .null;
    const arr = args[0].array;
    var carry: Value = if (args.len >= 3) args[2] else .null;
    for (arr.entries.items) |entry| {
        carry = try ctx.invokeCallable(args[1], &.{ carry, entry.value });
    }
    return carry;
}

fn array_key_first(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .null;
    const arr = args[0].array;
    if (arr.entries.items.len == 0) return .null;
    return switch (arr.entries.items[0].key) {
        .int => |i| .{ .int = i },
        .string => |s| .{ .string = s },
    };
}

fn array_key_last(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .null;
    const arr = args[0].array;
    if (arr.entries.items.len == 0) return .null;
    return switch (arr.entries.items[arr.entries.items.len - 1].key) {
        .int => |i| .{ .int = i },
        .string => |s| .{ .string = s },
    };
}

fn native_uasort(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .{ .bool = false };
    const arr = args[0].array;
    const callback = args[1];
    const items = arr.entries.items;
    var n = items.len;
    while (n > 1) {
        var swapped = false;
        for (0..n - 1) |i| {
            const cmp = try ctx.invokeCallable(callback, &.{ items[i].value, items[i + 1].value });
            if (Value.toInt(cmp) > 0) {
                const tmp = items[i];
                items[i] = items[i + 1];
                items[i + 1] = tmp;
                swapped = true;
            }
        }
        if (!swapped) break;
        n -= 1;
    }
    return .{ .bool = true };
}

fn native_uksort(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .{ .bool = false };
    const arr = args[0].array;
    const callback = args[1];
    const items = arr.entries.items;
    var n = items.len;
    while (n > 1) {
        var swapped = false;
        for (0..n - 1) |i| {
            const a_key: Value = switch (items[i].key) {
                .int => |ki| .{ .int = ki },
                .string => |ks| .{ .string = ks },
            };
            const b_key: Value = switch (items[i + 1].key) {
                .int => |ki| .{ .int = ki },
                .string => |ks| .{ .string = ks },
            };
            const cmp = try ctx.invokeCallable(callback, &.{ a_key, b_key });
            if (Value.toInt(cmp) > 0) {
                const tmp = items[i];
                items[i] = items[i + 1];
                items[i + 1] = tmp;
                swapped = true;
            }
        }
        if (!swapped) break;
        n -= 1;
    }
    return .{ .bool = true };
}

fn array_replace(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .null;
    var result = try ctx.createArray();
    for (args[0].array.entries.items) |entry| {
        try result.set(ctx.allocator, entry.key, entry.value);
    }
    for (args[1..]) |arg| {
        if (arg != .array) continue;
        for (arg.array.entries.items) |entry| {
            try result.set(ctx.allocator, entry.key, entry.value);
        }
    }
    return .{ .array = result };
}

fn array_find(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .null;
    const arr = args[0].array;
    for (arr.entries.items) |entry| {
        const result = try ctx.invokeCallable(args[1], &.{entry.value});
        if (result.isTruthy()) return entry.value;
    }
    return .null;
}

fn array_find_key(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .null;
    const arr = args[0].array;
    for (arr.entries.items) |entry| {
        const result = try ctx.invokeCallable(args[1], &.{entry.value});
        if (result.isTruthy()) {
            return switch (entry.key) {
                .int => |i| .{ .int = i },
                .string => |s| .{ .string = s },
            };
        }
    }
    return .null;
}

fn array_any(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .{ .bool = false };
    const arr = args[0].array;
    for (arr.entries.items) |entry| {
        const result = try ctx.invokeCallable(args[1], &.{entry.value});
        if (result.isTruthy()) return .{ .bool = true };
    }
    return .{ .bool = false };
}

fn array_all(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .{ .bool = true };
    const arr = args[0].array;
    for (arr.entries.items) |entry| {
        const result = try ctx.invokeCallable(args[1], &.{entry.value});
        if (!result.isTruthy()) return .{ .bool = false };
    }
    return .{ .bool = true };
}

fn native_current(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return Value{ .bool = false };
    const arr = args[0].array;
    if (arr.cursor >= arr.entries.items.len) return Value{ .bool = false };
    return arr.entries.items[arr.cursor].value;
}

fn native_next(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return Value{ .bool = false };
    const arr = args[0].array;
    if (arr.cursor < arr.entries.items.len) arr.cursor += 1;
    if (arr.cursor >= arr.entries.items.len) return Value{ .bool = false };
    return arr.entries.items[arr.cursor].value;
}

fn native_prev(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return Value{ .bool = false };
    const arr = args[0].array;
    if (arr.cursor == 0) return Value{ .bool = false };
    arr.cursor -= 1;
    return arr.entries.items[arr.cursor].value;
}

fn native_reset(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return Value{ .bool = false };
    const arr = args[0].array;
    arr.cursor = 0;
    if (arr.entries.items.len == 0) return Value{ .bool = false };
    return arr.entries.items[0].value;
}

fn native_end(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return Value{ .bool = false };
    const arr = args[0].array;
    if (arr.entries.items.len == 0) return Value{ .bool = false };
    arr.cursor = arr.entries.items.len - 1;
    return arr.entries.items[arr.cursor].value;
}

fn native_key(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .null;
    const arr = args[0].array;
    if (arr.cursor >= arr.entries.items.len) return .null;
    return switch (arr.entries.items[arr.cursor].key) {
        .int => |i| Value{ .int = i },
        .string => |s| Value{ .string = s },
    };
}

fn native_sizeof(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .{ .int = 0 };
    return .{ .int = args[0].array.length() };
}

fn array_intersect_key(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .null;
    const src = args[0].array;

    var result = try ctx.createArray();
    for (src.entries.items) |entry| {
        var in_all = true;
        for (args[1..]) |arg| {
            if (arg != .array) continue;
            var found = false;
            for (arg.array.entries.items) |other| {
                if (entry.key.eql(other.key)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                in_all = false;
                break;
            }
        }
        if (in_all) try result.set(ctx.allocator, entry.key, entry.value);
    }
    return .{ .array = result };
}

fn array_diff_assoc(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .null;
    const src = args[0].array;

    var result = try ctx.createArray();
    for (src.entries.items) |entry| {
        var in_any = false;
        for (args[1..]) |arg| {
            if (arg != .array) continue;
            for (arg.array.entries.items) |other| {
                if (entry.key.eql(other.key) and Value.equal(entry.value, other.value)) {
                    in_any = true;
                    break;
                }
            }
            if (in_any) break;
        }
        if (!in_any) try result.set(ctx.allocator, entry.key, entry.value);
    }
    return .{ .array = result };
}

fn deepReplace(ctx: *NativeContext, base: *PhpArray, overlay: *PhpArray) RuntimeError!*PhpArray {
    var result = try ctx.createArray();
    for (base.entries.items) |entry| {
        try result.set(ctx.allocator, entry.key, entry.value);
    }
    for (overlay.entries.items) |entry| {
        const existing = result.get(entry.key);
        if (existing == .array and entry.value == .array) {
            const merged = try deepReplace(ctx, existing.array, entry.value.array);
            try result.set(ctx.allocator, entry.key, .{ .array = merged });
        } else {
            try result.set(ctx.allocator, entry.key, entry.value);
        }
    }
    return result;
}

fn array_replace_recursive(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .null;
    var result = args[0].array;
    for (args[1..]) |arg| {
        if (arg != .array) continue;
        result = try deepReplace(ctx, result, arg.array);
    }
    return .{ .array = result };
}

fn walkRecursive(ctx: *NativeContext, arr: *PhpArray, callback: Value) RuntimeError!void {
    for (arr.entries.items) |entry| {
        if (entry.value == .array) {
            try walkRecursive(ctx, entry.value.array, callback);
        } else {
            var call_args = [2]Value{ entry.value, switch (entry.key) {
                .int => |k| Value{ .int = k },
                .string => |s| Value{ .string = s },
            } };
            _ = try ctx.invokeCallableRef(callback, &call_args);
        }
    }
}

fn array_walk_recursive(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .{ .bool = false };
    try walkRecursive(ctx, args[0].array, args[1]);
    return .{ .bool = true };
}

fn deepMerge(ctx: *NativeContext, a: *PhpArray, b: *PhpArray) RuntimeError!*PhpArray {
    var result = try ctx.createArray();
    for (a.entries.items) |entry| {
        try result.set(ctx.allocator, entry.key, entry.value);
    }
    for (b.entries.items) |entry| {
        switch (entry.key) {
            .int => try result.append(ctx.allocator, entry.value),
            .string => {
                const existing = result.get(entry.key);
                if (existing == .array and entry.value == .array) {
                    const merged = try deepMerge(ctx, existing.array, entry.value.array);
                    try result.set(ctx.allocator, entry.key, .{ .array = merged });
                } else if (existing != .null) {
                    // both are scalars - wrap into array
                    if (entry.value == .array) {
                        // existing is scalar, incoming is array
                        var merged = try ctx.createArray();
                        try merged.append(ctx.allocator, existing);
                        for (entry.value.array.entries.items) |sub| {
                            try merged.append(ctx.allocator, sub.value);
                        }
                        try result.set(ctx.allocator, entry.key, .{ .array = merged });
                    } else if (existing == .array) {
                        // existing is array, incoming is scalar
                        var merged = try ctx.createArray();
                        for (existing.array.entries.items) |sub| {
                            try merged.append(ctx.allocator, sub.value);
                        }
                        try merged.append(ctx.allocator, entry.value);
                        try result.set(ctx.allocator, entry.key, .{ .array = merged });
                    } else {
                        // both scalars - combine into array
                        var merged = try ctx.createArray();
                        try merged.append(ctx.allocator, existing);
                        try merged.append(ctx.allocator, entry.value);
                        try result.set(ctx.allocator, entry.key, .{ .array = merged });
                    }
                } else {
                    try result.set(ctx.allocator, entry.key, entry.value);
                }
            },
        }
    }
    return result;
}

fn array_merge_recursive(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .null;
    if (args[0] != .array) return .null;
    var result = args[0].array;
    for (args[1..]) |arg| {
        if (arg != .array) continue;
        result = try deepMerge(ctx, result, arg.array);
    }
    return .{ .array = result };
}

fn array_intersect_assoc(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .null;
    const src = args[0].array;

    var result = try ctx.createArray();
    for (src.entries.items) |entry| {
        var in_all = true;
        for (args[1..]) |arg| {
            if (arg != .array) continue;
            var found = false;
            for (arg.array.entries.items) |other| {
                if (entry.key.eql(other.key) and Value.equal(entry.value, other.value)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                in_all = false;
                break;
            }
        }
        if (in_all) try result.set(ctx.allocator, entry.key, entry.value);
    }
    return .{ .array = result };
}

fn array_multisort(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .{ .bool = false };

    const SortSpec = struct { arr: *PhpArray, order: i64, kind: i64 };
    var specs: [32]SortSpec = undefined;
    var spec_count: usize = 0;

    for (args) |arg| {
        if (arg == .array) {
            specs[spec_count] = .{ .arr = arg.array, .order = 4, .kind = 0 };
            spec_count += 1;
            if (spec_count >= 32) break;
        } else if (arg == .int and spec_count > 0) {
            const v = arg.int;
            if (v == 3 or v == 4) {
                specs[spec_count - 1].order = v;
            } else {
                specs[spec_count - 1].kind = v;
            }
        }
    }

    if (spec_count == 0) return .{ .bool = false };

    const n = specs[0].arr.entries.items.len;
    for (specs[0..spec_count]) |s| {
        if (s.arr.entries.items.len != n) return .{ .bool = false };
    }

    var indices = try ctx.allocator.alloc(usize, n);
    defer ctx.allocator.free(indices);
    for (0..n) |i| indices[i] = i;

    const sort_specs = specs[0..spec_count];
    std.mem.sort(usize, indices, sort_specs, struct {
        fn lessThan(sp: []const SortSpec, a: usize, b: usize) bool {
            for (sp) |s| {
                const va = s.arr.entries.items[a].value;
                const vb = s.arr.entries.items[b].value;
                const cmp = cmpValues(va, vb, s.kind);
                if (cmp != 0) return if (s.order == 3) cmp > 0 else cmp < 0;
            }
            return false;
        }

        fn cmpValues(a: Value, b: Value, k: i64) i32 {
            if (k == 2) {
                const sa = if (a == .string) a.string else "";
                const sb = if (b == .string) b.string else "";
                return switch (std.mem.order(u8, sa, sb)) {
                    .lt => -1, .gt => 1, .eq => 0,
                };
            }
            if (k == 1) {
                const fa = Value.toFloat(a);
                const fb = Value.toFloat(b);
                if (fa < fb) return -1;
                if (fa > fb) return 1;
                return 0;
            }
            if (Value.lessThan(a, b)) return -1;
            if (Value.lessThan(b, a)) return 1;
            return 0;
        }
    }.lessThan);

    for (sort_specs) |s| {
        var tmp = try ctx.allocator.alloc(PhpArray.Entry, n);
        defer ctx.allocator.free(tmp);
        for (indices, 0..) |src, dst| tmp[dst] = s.arr.entries.items[src];
        @memcpy(s.arr.entries.items[0..n], tmp);
        reindexArray(s.arr);
    }

    return .{ .bool = true };
}

fn keyToValue(key: PhpArray.Key) Value {
    return switch (key) {
        .int => |i| .{ .int = i },
        .string => |s| .{ .string = s },
    };
}

fn array_diff_uassoc(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[0] != .array) return .null;
    const src = args[0].array;
    const callback = args[args.len - 1];

    var result = try ctx.createArray();
    for (src.entries.items) |entry| {
        var in_any = false;
        for (args[1 .. args.len - 1]) |arg| {
            if (arg != .array) continue;
            for (arg.array.entries.items) |other| {
                if (!Value.equal(entry.value, other.value)) continue;
                const cmp = try ctx.invokeCallable(callback, &.{ keyToValue(entry.key), keyToValue(other.key) });
                if (Value.toInt(cmp) == 0) {
                    in_any = true;
                    break;
                }
            }
            if (in_any) break;
        }
        if (!in_any) try result.set(ctx.allocator, entry.key, entry.value);
    }
    return .{ .array = result };
}

fn array_diff_ukey(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[0] != .array) return .null;
    const src = args[0].array;
    const callback = args[args.len - 1];

    var result = try ctx.createArray();
    for (src.entries.items) |entry| {
        var in_any = false;
        for (args[1 .. args.len - 1]) |arg| {
            if (arg != .array) continue;
            for (arg.array.entries.items) |other| {
                const cmp = try ctx.invokeCallable(callback, &.{ keyToValue(entry.key), keyToValue(other.key) });
                if (Value.toInt(cmp) == 0) {
                    in_any = true;
                    break;
                }
            }
            if (in_any) break;
        }
        if (!in_any) try result.set(ctx.allocator, entry.key, entry.value);
    }
    return .{ .array = result };
}

fn array_change_key_case(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .null;
    const src = args[0].array;
    const case_upper = args.len >= 2 and args[1] == .int and args[1].int == 1;
    const result = try ctx.createArray();

    for (src.entries.items) |entry| {
        const new_key: PhpArray.Key = switch (entry.key) {
            .string => |s| blk: {
                const buf = ctx.allocator.alloc(u8, s.len) catch break :blk .{ .string = s };
                ctx.strings.append(ctx.allocator, buf) catch {};
                for (s, 0..) |c, i| {
                    buf[i] = if (case_upper) std.ascii.toUpper(c) else std.ascii.toLower(c);
                }
                break :blk .{ .string = buf };
            },
            .int => entry.key,
        };
        try result.set(ctx.allocator, new_key, entry.value);
    }
    return .{ .array = result };
}
