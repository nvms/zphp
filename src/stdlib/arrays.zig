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
    .{ "array_values", array_values },
    .{ "in_array", in_array },
    .{ "array_key_exists", array_key_exists },
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
    const length: usize = if (args.len >= 3) @intCast(@max(0, @min(slen - offset, Value.toInt(args[2])))) else @intCast(slen - offset);
    const end = @min(src.entries.items.len, uoffset + length);

    var arr = try ctx.createArray();
    for (src.entries.items[uoffset..end]) |entry| {
        try arr.append(ctx.allocator, entry.value);
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
    return .{ .bool = true };
}

fn array_map(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .null;
    const callback = args[0];
    if (args[1] != .array) return .null;
    const src = args[1].array;

    var result = try ctx.createArray();
    for (src.entries.items) |entry| {
        const mapped = try ctx.invokeCallable(callback, &.{entry.value});
        try result.append(ctx.allocator, mapped);
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

fn native_range(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .null;
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

    var result = try ctx.createArray();
    var i: usize = 0;
    while (i < src.entries.items.len) {
        var chunk = try ctx.createArray();
        const end = @min(i + size, src.entries.items.len);
        for (src.entries.items[i..end]) |entry| {
            try chunk.append(ctx.allocator, entry.value);
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
        const key = Value.toArrayKey(col_key);
        const val = row.get(key);
        if (val != .null) {
            if (args.len >= 3 and args[2] != .null) {
                const idx_key = Value.toArrayKey(args[2]);
                const idx_val = row.get(idx_key);
                try result.set(ctx.allocator, Value.toArrayKey(idx_val), val);
            } else {
                try result.append(ctx.allocator, val);
            }
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

    for (arr.entries.items) |entry| {
        _ = try ctx.invokeCallable(args[1], &.{entry.value});
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
    const items = arr.entries.items;
    var i: usize = items.len;
    while (i > 1) {
        i -= 1;
        const j = std.crypto.random.intRangeAtMost(usize, 0, i);
        const tmp = items[i];
        items[i] = items[j];
        items[j] = tmp;
    }
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
    for (args) |arg| {
        if (arg != .string) continue;
        const name = arg.string;
        const var_name = try std.fmt.allocPrint(ctx.allocator, "${s}", .{name});
        try ctx.strings.append(ctx.allocator, var_name);
        if (frame.vars.get(var_name)) |val| {
            try arr.set(ctx.allocator, .{ .string = name }, val);
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
