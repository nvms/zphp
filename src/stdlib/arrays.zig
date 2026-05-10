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
    .{ "natsort", natsort_impl },
    .{ "natcasesort", natcasesort_impl },
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
    .{ "array_udiff", array_udiff },
    .{ "array_udiff_assoc", array_udiff_assoc },
    .{ "array_udiff_uassoc", array_udiff_uassoc },
    .{ "array_uintersect", array_uintersect },
    .{ "array_uintersect_assoc", array_uintersect_assoc },
    .{ "array_uintersect_uassoc", array_uintersect_uassoc },
    .{ "array_intersect_ukey", array_intersect_ukey },
    .{ "array_intersect_uassoc", array_intersect_uassoc },
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
    const entry = arr.entries.pop() orelse return .null;
    if (entry.key == .string) _ = arr.string_index.remove(entry.key.string);
    // PHP: array_pop recomputes next int key from the remaining entries
    var max_int: i64 = -1;
    for (arr.entries.items) |e| {
        if (e.key == .int and e.key.int > max_int) max_int = e.key.int;
    }
    arr.next_int_key = max_int + 1;
    return entry.value;
}

fn array_shift(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .null;
    const arr = args[0].array;
    if (arr.entries.items.len == 0) return .null;
    const first = arr.entries.orderedRemove(0);
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
    try arr.rebuildStringIndex(ctx.allocator);
    return first.value;
}

fn array_keys(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .null;
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
    if (args.len == 0) return .null;
    if (args[0] != .array) {
        try ctx.vm.setPendingException("TypeError", "array_values(): Argument #1 ($array) must be of type array");
        return error.RuntimeError;
    }
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
    const strict = args.len >= 3 and args[2] == .bool and args[2].bool;
    for (arr.entries.items) |entry| {
        const match = if (strict) Value.identical(needle, entry.value) else Value.equal(needle, entry.value);
        if (match) {
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
    // default in PHP is SORT_STRING (2)
    const flag = if (args.len >= 2) Value.toInt(args[1]) else 2;
    var arr = try ctx.createArray();
    for (src.entries.items) |entry| {
        var found = false;
        for (arr.entries.items) |existing| {
            const eq = switch (flag) {
                1 => Value.toFloat(entry.value) == Value.toFloat(existing.value), // SORT_NUMERIC
                2, 5, 6 => blk: { // SORT_STRING, SORT_LOCALE_STRING, SORT_NATURAL
                    const a_str = try valueAsStringForCompare(ctx, entry.value);
                    const b_str = try valueAsStringForCompare(ctx, existing.value);
                    break :blk std.mem.eql(u8, a_str, b_str);
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
    return .{ .array = arr };
}

fn valueAsString(v: Value, buf: *[64]u8) []const u8 {
    return switch (v) {
        .string => |s| s,
        .int => |i| std.fmt.bufPrint(buf, "{d}", .{i}) catch "",
        .float => |f| std.fmt.bufPrint(buf, "{d}", .{f}) catch "",
        .bool => |b| if (b) "1" else "",
        .null => "",
        else => "",
    };
}

fn valueAsStringForCompare(ctx: *NativeContext, v: Value) RuntimeError![]const u8 {
    if (v == .object) {
        if (ctx.vm.hasMethod(v.object.class_name, "__toString")) {
            const result = try ctx.vm.callMethod(v.object, "__toString", &.{});
            if (result == .string) return result.string;
        }
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Object of class {s} could not be converted to string", .{v.object.class_name}) catch "Object could not be converted to string";
        try ctx.vm.setPendingException("Error", msg);
        return error.RuntimeError;
    }
    var buf = std.ArrayListUnmanaged(u8){};
    try v.format(&buf, ctx.allocator);
    const owned = try buf.toOwnedSlice(ctx.allocator);
    try ctx.vm.strings.append(ctx.allocator, owned);
    return owned;
}

const SortFlags = struct {
    flags: i64,
    reverse: bool,
    comptime field: enum { value, key } = .value,

    fn compare(self: SortFlags, a_val: Value, b_val: Value) bool {
        const x = if (self.reverse) b_val else a_val;
        const y = if (self.reverse) a_val else b_val;
        const sort_type = self.flags & 0x7; // mask out SORT_FLAG_CASE
        const case_insensitive = (self.flags & 8) != 0; // SORT_FLAG_CASE
        return switch (sort_type) {
            1 => Value.toFloat(x) < Value.toFloat(y), // SORT_NUMERIC
            2, 5 => blk: { // SORT_STRING, SORT_LOCALE_STRING
                var xbuf: [64]u8 = undefined;
                var ybuf: [64]u8 = undefined;
                const xs = valueToSortStr(x, &xbuf);
                const ys = valueToSortStr(y, &ybuf);
                if (case_insensitive) {
                    var lxbuf: [64]u8 = undefined;
                    var lybuf: [64]u8 = undefined;
                    const lxs = lowerInto(&lxbuf, xs);
                    const lys = lowerInto(&lybuf, ys);
                    break :blk std.mem.order(u8, lxs, lys) == .lt;
                }
                break :blk std.mem.order(u8, xs, ys) == .lt;
            },
            6 => blk: { // SORT_NATURAL
                var xbuf: [64]u8 = undefined;
                var ybuf: [64]u8 = undefined;
                const xs = valueToSortStr(x, &xbuf);
                const ys = valueToSortStr(y, &ybuf);
                if (case_insensitive) {
                    var lxbuf: [64]u8 = undefined;
                    var lybuf: [64]u8 = undefined;
                    const lxs = lowerInto(&lxbuf, xs);
                    const lys = lowerInto(&lybuf, ys);
                    break :blk naturalCompare(lxs, lys) < 0;
                }
                break :blk naturalCompare(xs, ys) < 0;
            },
            else => Value.lessThan(x, y), // SORT_REGULAR
        };
    }

    fn lowerInto(buf: []u8, s: []const u8) []const u8 {
        const n = @min(buf.len, s.len);
        for (s[0..n], 0..) |c, i| {
            buf[i] = if (c >= 'A' and c <= 'Z') c + 32 else c;
        }
        return buf[0..n];
    }

    fn valueToSortStr(v: Value, buf: *[64]u8) []const u8 {
        return switch (v) {
            .string => |s| s,
            .int => |i| std.fmt.bufPrint(buf, "{d}", .{i}) catch "",
            .float => |f| std.fmt.bufPrint(buf, "{d}", .{f}) catch "",
            .bool => |b| if (b) "1" else "",
            .null => "",
            else => "",
        };
    }

    fn naturalCompare(a: []const u8, b: []const u8) i32 {
        var ai: usize = 0;
        var bi: usize = 0;
        while (ai < a.len and bi < b.len) {
            const a_digit = a[ai] >= '0' and a[ai] <= '9';
            const b_digit = b[bi] >= '0' and b[bi] <= '9';
            if (a_digit and b_digit) {
                while (ai < a.len and a[ai] == '0') ai += 1;
                while (bi < b.len and b[bi] == '0') bi += 1;
                const a_start = ai;
                const b_start = bi;
                while (ai < a.len and a[ai] >= '0' and a[ai] <= '9') ai += 1;
                while (bi < b.len and b[bi] >= '0' and b[bi] <= '9') bi += 1;
                const a_len = ai - a_start;
                const b_len = bi - b_start;
                if (a_len != b_len) return if (a_len < b_len) @as(i32, -1) else 1;
                for (a_start..ai, b_start..bi) |aj, bj| {
                    if (a[aj] != b[bj]) return if (a[aj] < b[bj]) @as(i32, -1) else 1;
                }
            } else {
                if (a[ai] != b[bi]) return if (a[ai] < b[bi]) @as(i32, -1) else 1;
                ai += 1;
                bi += 1;
            }
        }
        if (ai < a.len) return 1;
        if (bi < b.len) return -1;
        return 0;
    }
};

pub fn sortWithFlags(arr: *PhpArray, flags: i64, reverse: bool) void {
    const ctx_val = SortFlags{ .flags = flags, .reverse = reverse };
    std.mem.sort(PhpArray.Entry, arr.entries.items, ctx_val, struct {
        fn f(c: SortFlags, a: PhpArray.Entry, b: PhpArray.Entry) bool {
            return c.compare(a.value, b.value);
        }
    }.f);
}

fn sortKeyAsValue(k: PhpArray.Key) Value {
    return switch (k) {
        .int => |i| .{ .int = i },
        .string => |s| .{ .string = s },
    };
}

pub fn sortKeysWithFlags(arr: *PhpArray, flags: i64, reverse: bool) void {
    const ctx_val = SortFlags{ .flags = flags, .reverse = reverse };
    std.mem.sort(PhpArray.Entry, arr.entries.items, ctx_val, struct {
        fn f(c: SortFlags, a: PhpArray.Entry, b: PhpArray.Entry) bool {
            return c.compare(sortKeyAsValue(a.key), sortKeyAsValue(b.key));
        }
    }.f);
}

fn natCompareStr(a: []const u8, b: []const u8, fold_case: bool) i64 {
    var ai: usize = 0;
    var bi: usize = 0;
    while (ai < a.len and bi < b.len) {
        const ca = a[ai];
        const cb = b[bi];
        if (std.ascii.isDigit(ca) and std.ascii.isDigit(cb)) {
            var as = ai;
            while (as < a.len and a[as] == '0') as += 1;
            var ae = as;
            while (ae < a.len and std.ascii.isDigit(a[ae])) ae += 1;
            var bs = bi;
            while (bs < b.len and b[bs] == '0') bs += 1;
            var be = bs;
            while (be < b.len and std.ascii.isDigit(b[be])) be += 1;
            const al = ae - as;
            const bl = be - bs;
            if (al != bl) return @as(i64, @intCast(al)) - @as(i64, @intCast(bl));
            for (a[as..ae], b[bs..be]) |x, y| {
                if (x != y) return @as(i64, x) - @as(i64, y);
            }
            ai = ae;
            bi = be;
            continue;
        }
        const xa: u8 = if (fold_case) std.ascii.toLower(ca) else ca;
        const xb: u8 = if (fold_case) std.ascii.toLower(cb) else cb;
        if (xa != xb) return @as(i64, xa) - @as(i64, xb);
        ai += 1;
        bi += 1;
    }
    if (a.len != b.len) return @as(i64, @intCast(a.len)) - @as(i64, @intCast(b.len));
    return 0;
}

fn natsortImpl(arr: *PhpArray, fold_case: bool) void {
    const N = arr.entries.items.len;
    if (N < 2) return;
    var i: usize = 1;
    while (i < N) : (i += 1) {
        const tmp = arr.entries.items[i];
        var j: usize = i;
        while (j > 0) {
            const av = arr.entries.items[j - 1].value;
            const sa: []const u8 = if (av == .string) av.string else "";
            const sb: []const u8 = if (tmp.value == .string) tmp.value.string else "";
            if (natCompareStr(sa, sb, fold_case) <= 0) break;
            arr.entries.items[j] = arr.entries.items[j - 1];
            j -= 1;
        }
        arr.entries.items[j] = tmp;
    }
    arr.string_index.clearRetainingCapacity();
}

fn natsort_impl(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .{ .bool = false };
    natsortImpl(args[0].array, false);
    return .{ .bool = true };
}

fn natcasesort_impl(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .{ .bool = false };
    natsortImpl(args[0].array, true);
    return .{ .bool = true };
}

fn native_sort(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .{ .bool = false };
    const arr = args[0].array;
    const flags: i64 = if (args.len >= 2) Value.toInt(args[1]) else 0;
    sortWithFlags(arr, flags, false);
    reindexArray(arr);
    return .{ .bool = true };
}

fn native_rsort(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .{ .bool = false };
    const arr = args[0].array;
    const flags: i64 = if (args.len >= 2) Value.toInt(args[1]) else 0;
    sortWithFlags(arr, flags, true);
    reindexArray(arr);
    return .{ .bool = true };
}

fn reindexArray(arr: *PhpArray) void {
    for (arr.entries.items, 0..) |*entry, i| entry.key = .{ .int = @intCast(i) };
    arr.next_int_key = @intCast(arr.entries.items.len);
    arr.has_int_keys = arr.entries.items.len > 0;
    arr.string_index.clearRetainingCapacity();
    arr.cursor = 0;
}

pub const SortField = enum { value, key };

pub fn mergeSort(comptime T: type, items: []T, ctx: *NativeContext, callback: Value, comptime field: SortField) RuntimeError!void {
    if (items.len <= 1) return;
    if (items.len <= 16) {
        // insertion sort for small slices
        for (1..items.len) |i| {
            const tmp = items[i];
            var j: usize = i;
            while (j > 0) {
                const cmp = try invokeSortCmp(T, items[j - 1], tmp, ctx, callback, field);
                if (Value.toInt(cmp) <= 0) break;
                items[j] = items[j - 1];
                j -= 1;
            }
            items[j] = tmp;
        }
        return;
    }
    const mid = items.len / 2;
    try mergeSort(T, items[0..mid], ctx, callback, field);
    try mergeSort(T, items[mid..], ctx, callback, field);
    const buf = ctx.allocator.alloc(T, items.len) catch return;
    defer ctx.allocator.free(buf);
    var l: usize = 0;
    var r: usize = mid;
    var k: usize = 0;
    while (l < mid and r < items.len) {
        const cmp = try invokeSortCmp(T, items[l], items[r], ctx, callback, field);
        if (Value.toInt(cmp) <= 0) {
            buf[k] = items[l];
            l += 1;
        } else {
            buf[k] = items[r];
            r += 1;
        }
        k += 1;
    }
    while (l < mid) : (l += 1) { buf[k] = items[l]; k += 1; }
    while (r < items.len) : (r += 1) { buf[k] = items[r]; k += 1; }
    @memcpy(items, buf[0..items.len]);
}

fn invokeSortCmp(comptime T: type, a: T, b: T, ctx: *NativeContext, callback: Value, comptime field: SortField) RuntimeError!Value {
    if (field == .key) {
        const ak: Value = switch (a.key) {
            .int => |ki| .{ .int = ki },
            .string => |ks| .{ .string = ks },
        };
        const bk: Value = switch (b.key) {
            .int => |ki| .{ .int = ki },
            .string => |ks| .{ .string = ks },
        };
        return ctx.invokeCallable(callback, &.{ ak, bk });
    }
    return ctx.invokeCallable(callback, &.{ a.value, b.value });
}

fn array_map(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .null;
    for (args[1..], 1..) |a, i| {
        if (a != .array) {
            const msg = try std.fmt.allocPrint(ctx.allocator, "array_map(): Argument #{d} must be of type array", .{i + 1});
            try ctx.strings.append(ctx.allocator, msg);
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
        return .{ .array = result };
    }

    if (args[1] != .array) return .null;
    const src = args[1].array;

    // null callback with single array returns a copy preserving keys
    if (callback == .null) {
        var result = try ctx.createArray();
        for (src.entries.items) |entry| {
            try result.set(ctx.allocator, entry.key, entry.value);
        }
        return .{ .array = result };
    }

    // validate callable - PHP throws TypeError for unknown function names
    if (callback == .string) {
        const cb_name = callback.string;
        if (!ctx.vm.functions.contains(cb_name) and !ctx.vm.native_fns.contains(cb_name)) {
            const msg = std.fmt.allocPrint(ctx.allocator, "array_map(): Argument #1 ($callback) must be a valid callback or null, function \"{s}\" not found or invalid function name", .{cb_name}) catch "array_map(): Argument #1 ($callback) must be a valid callback or null";
            try ctx.strings.append(ctx.allocator, msg);
            try ctx.vm.setPendingException("TypeError", msg);
            return error.RuntimeError;
        }
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
    return .{ .array = result };
}

fn native_usort(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .{ .bool = false };
    const arr = args[0].array;
    const callback = args[1];
    try mergeSort(PhpArray.Entry, arr.entries.items, ctx, callback, .value);
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
        return .{ .array = arr };
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

    if (args.len >= 4) {
        if (args[3] == .array) {
            const replacement = args[3].array;
            var insert_idx = uoffset;
            for (replacement.entries.items) |entry| {
                try arr.entries.insert(ctx.allocator, insert_idx, .{ .key = .{ .int = 0 }, .value = entry.value });
                insert_idx += 1;
            }
        } else if (args[3] != .null) {
            // PHP: a non-array, non-null replacement is treated as a single element
            try arr.entries.insert(ctx.allocator, uoffset, .{ .key = .{ .int = 0 }, .value = args[3] });
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
    arr.has_int_keys = next_int > 0;
    try arr.rebuildStringIndex(ctx.allocator);

    return .{ .array = removed };
}

fn array_combine(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array or args[1] != .array) return .{ .bool = false };
    const keys_arr = args[0].array;
    const vals_arr = args[1].array;
    if (keys_arr.entries.items.len != vals_arr.entries.items.len) {
        const obj = try ctx.allocator.create(@import("../runtime/value.zig").PhpObject);
        obj.* = .{ .class_name = "ValueError" };
        try obj.set(ctx.allocator, "message", .{ .string = "array_combine(): Argument #1 ($keys) and argument #2 ($values) must have the same number of elements" });
        try obj.set(ctx.allocator, "code", .{ .int = 0 });
        try ctx.vm.objects.append(ctx.allocator, obj);
        ctx.vm.pending_exception = .{ .object = obj };
        return error.RuntimeError;
    }

    var arr = try ctx.createArray();
    for (keys_arr.entries.items, vals_arr.entries.items) |k, v| {
        if (k.value == .object or k.value == .array) {
            try ctx.vm.setPendingException("TypeError", "array_combine(): Argument #1 ($keys) must contain only string and integer keys");
            return error.RuntimeError;
        }
        // PHP array_combine casts each key to string first, then canonicalizes.
        const key: PhpArray.Key = switch (k.value) {
            .int => |i| .{ .int = i },
            .string => |s| PhpArray.normalizeKey(.{ .string = s }),
            else => blk: {
                var buf = std.ArrayListUnmanaged(u8){};
                try k.value.format(&buf, ctx.allocator);
                const owned = try buf.toOwnedSlice(ctx.allocator);
                try ctx.vm.strings.append(ctx.allocator, owned);
                break :blk PhpArray.normalizeKey(.{ .string = owned });
            },
        };
        try arr.set(ctx.allocator, key, v.value);
    }
    return .{ .array = arr };
}

fn array_chunk(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .null;
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
    return .{ .array = result };
}

fn array_pad(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[0] != .array) return .null;
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
        return .{ .array = result };
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
            try result.set(ctx.allocator, Value.toArrayKey(idx_val), val);
        } else {
            try result.append(ctx.allocator, val);
        }
    }
    return .{ .array = result };
}

fn rowGet(row: Value, key: Value) Value {
    return switch (row) {
        .array => |a| a.get(Value.toArrayKey(key)),
        .object => |o| switch (key) {
            .string => |s| o.get(s),
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

fn array_fill(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3) return .null;
    const start_idx = Value.toInt(args[0]);
    const count: usize = @intCast(@max(0, Value.toInt(args[1])));
    const val = args[2];

    var result = try ctx.createArray();
    try result.entries.ensureTotalCapacity(ctx.allocator, count);
    for (0..count) |i| {
        result.entries.appendAssumeCapacity(.{ .key = .{ .int = start_idx + @as(i64, @intCast(i)) }, .value = val });
    }
    result.next_int_key = start_idx + @as(i64, @intCast(count));
    result.has_int_keys = count > 0;
    return .{ .array = result };
}

fn array_fill_keys(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .null;
    const keys_arr = args[0].array;
    const val = args[1];

    var result = try ctx.createArray();
    for (keys_arr.entries.items) |entry| {
        const key = try arrayFillKeysKey(ctx, entry.value);
        try result.set(ctx.allocator, key, val);
    }
    return .{ .array = result };
}

// PHP's array_fill_keys uses a different key conversion than normal array
// assignment: floats become string "1.5" (instead of being truncated to 1),
// and bool false / null both become the empty string "" (not 0).
fn arrayFillKeysKey(ctx: *NativeContext, v: Value) !PhpArray.Key {
    return switch (v) {
        .int => |i| .{ .int = i },
        .string => |s| .{ .string = s },
        .bool => |b| if (b) PhpArray.Key{ .int = 1 } else PhpArray.Key{ .string = "" },
        .null => .{ .string = "" },
        .float => |f| blk: {
            var buf = std.ArrayListUnmanaged(u8){};
            try (Value{ .float = f }).format(&buf, ctx.allocator);
            const s = try buf.toOwnedSlice(ctx.allocator);
            try ctx.strings.append(ctx.allocator, s);
            break :blk PhpArray.Key{ .string = s };
        },
        else => .{ .int = 0 },
    };
}

fn valuesEqualAsString(a: Value, b: Value) bool {
    var ga = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = ga.deinit();
    const alloc = ga.allocator();
    var ba = std.ArrayListUnmanaged(u8){};
    var bb = std.ArrayListUnmanaged(u8){};
    defer ba.deinit(alloc);
    defer bb.deinit(alloc);
    a.format(&ba, alloc) catch return Value.equal(a, b);
    b.format(&bb, alloc) catch return Value.equal(a, b);
    return std.mem.eql(u8, ba.items, bb.items);
}

const ArrayCmp = enum { values, keys, assoc };

fn arraySetOp(comptime cmp: ArrayCmp, comptime keep_matches: bool) fn (*NativeContext, []const Value) RuntimeError!Value {
    return struct {
        fn f(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
            if (args.len < 2 or args[0] != .array) return .null;
            const src = args[0].array;
            var result = try ctx.createArray();
            for (src.entries.items) |entry| {
                if (keep_matches) {
                    // intersect: keep if found in ALL other arrays
                    if (matchesAll(entry, args[1..])) try result.set(ctx.allocator, entry.key, entry.value);
                } else {
                    // diff: keep if found in NONE of the other arrays
                    if (!matchesAny(entry, args[1..])) try result.set(ctx.allocator, entry.key, entry.value);
                }
            }
            return .{ .array = result };
        }
        fn matchesAll(entry: PhpArray.Entry, others: []const Value) bool {
            for (others) |arg| {
                if (arg != .array) return false;
                if (!foundIn(entry, arg.array)) return false;
            }
            return true;
        }
        fn matchesAny(entry: PhpArray.Entry, others: []const Value) bool {
            for (others) |arg| {
                if (arg != .array) continue;
                if (foundIn(entry, arg.array)) return true;
            }
            return false;
        }
        fn foundIn(entry: PhpArray.Entry, arr: *const PhpArray) bool {
            for (arr.entries.items) |other| {
                const hit = switch (cmp) {
                    .values => valuesEqualAsString(entry.value, other.value),
                    .keys => entry.key.eql(other.key),
                    .assoc => entry.key.eql(other.key) and valuesEqualAsString(entry.value, other.value),
                };
                if (hit) return true;
            }
            return false;
        }
    }.f;
}

const array_intersect = arraySetOp(.values, true);
const array_diff = arraySetOp(.values, false);
const array_intersect_key = arraySetOp(.keys, true);
const array_diff_key = arraySetOp(.keys, false);
const array_intersect_assoc = arraySetOp(.assoc, true);
const array_diff_assoc = arraySetOp(.assoc, false);

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
    if (args.len < 2) return .{ .bool = false };
    if (args[0] != .array and !(args[0] == .object and ctx.vm.isInstanceOf(args[0].object.class_name, "Traversable"))) {
        try ctx.vm.setPendingException("TypeError", "array_walk(): Argument #1 ($array) must be of type array|object");
        return error.RuntimeError;
    }
    if (args[0] != .array) return .{ .bool = false };
    const arr = args[0].array;
    const callback = args[1];
    const has_userdata = args.len >= 3;

    // snapshot keys so callback mutations to the array don't corrupt iteration
    const initial_len = arr.entries.items.len;
    var keys = try ctx.allocator.alloc(PhpArray.Key, initial_len);
    defer ctx.allocator.free(keys);
    for (arr.entries.items[0..initial_len], 0..) |entry, i| keys[i] = entry.key;

    for (keys) |key| {
        const cur_idx = findEntryIndex(arr, key) orelse continue;
        const key_val: Value = switch (key) {
            .int => |k| .{ .int = k },
            .string => |s| .{ .string = s },
        };
        var call_args = [3]Value{ arr.entries.items[cur_idx].value, key_val, if (has_userdata) args[2] else .null };
        const slice: []Value = if (has_userdata) call_args[0..3] else call_args[0..2];
        _ = try ctx.invokeCallableRef(callback, slice);
        // entry may have been removed during the call
        if (findEntryIndex(arr, key)) |i| arr.entries.items[i].value = call_args[0];
    }
    return .{ .bool = true };
}

fn findEntryIndex(arr: *PhpArray, key: PhpArray.Key) ?usize {
    if (key == .string) {
        if (arr.string_index.get(key.string)) |i| return i;
        return null;
    }
    for (arr.entries.items, 0..) |e, i| {
        if (e.key.eql(key)) return i;
    }
    return null;
}

fn array_unshift(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .{ .int = 0 };
    const arr = args[0].array;

    var insert_idx: usize = 0;
    for (args[1..]) |val| {
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
    try arr.rebuildStringIndex(ctx.allocator);
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

fn array_rand(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .null;
    const arr = args[0].array;
    if (arr.entries.items.len == 0) return .null;
    const num: i64 = if (args.len >= 2) Value.toInt(args[1]) else 1;
    if (num < 1 or num > @as(i64, @intCast(arr.entries.items.len))) {
        try ctx.vm.setPendingException("ValueError", "array_rand(): Argument #2 ($num) must be between 1 and the number of elements in argument #1 ($array)");
        return error.RuntimeError;
    }
    if (num == 1 and (args.len < 2 or Value.toInt(args[1]) == 1 and args.len == 1)) {
        // single-arg form returns scalar
        const idx = std.crypto.random.intRangeAtMost(usize, 0, arr.entries.items.len - 1);
        return switch (arr.entries.items[idx].key) {
            .int => |i| .{ .int = i },
            .string => |s| .{ .string = s },
        };
    }
    // PHP returns scalar key when num=1 (default), array of keys otherwise.
    if (num == 1) {
        const out = try ctx.createArray();
        const idx = std.crypto.random.intRangeAtMost(usize, 0, arr.entries.items.len - 1);
        const v: Value = switch (arr.entries.items[idx].key) {
            .int => |i| .{ .int = i },
            .string => |s| .{ .string = s },
        };
        try out.append(ctx.allocator, v);
        return .{ .array = out };
    }
    // Fisher-Yates partial shuffle for `num` distinct picks
    var pool = try ctx.allocator.alloc(usize, arr.entries.items.len);
    defer ctx.allocator.free(pool);
    for (0..pool.len) |i| pool[i] = i;
    var i: usize = 0;
    const n: usize = @intCast(num);
    while (i < n) : (i += 1) {
        const j = std.crypto.random.intRangeAtMost(usize, i, pool.len - 1);
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
    return .{ .array = out };
}

fn native_compact(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const arr = try ctx.createArray();
    const frame = ctx.vm.currentFrame();
    const slot_names = if (frame.func) |func| func.slot_names else ctx.vm.global_slot_names;
    for (args) |arg| try compactValue(ctx, arg, arr, frame, slot_names);
    return .{ .array = arr };
}

fn compactValue(ctx: *NativeContext, arg: Value, arr: *PhpArray, frame: anytype, slot_names: []const []const u8) RuntimeError!void {
    if (arg == .string) {
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
    } else if (arg == .array) {
        for (arg.array.entries.items) |entry| try compactValue(ctx, entry.value, arr, frame, slot_names);
    }
}

fn native_extract(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .{ .int = 0 };
    const arr = args[0].array;
    const flags: i64 = if (args.len >= 2) Value.toInt(args[1]) else 0;
    // strip EXTR_REFS bit (0x100) so the type bits stay intact
    const type_flag = flags & 0xff;
    const prefix = if (args.len >= 3 and args[2] == .string) args[2].string else "";
    const frame = ctx.vm.currentFrame();
    const slot_names = if (frame.func) |func| func.slot_names else ctx.vm.global_slot_names;

    var count_val: i64 = 0;
    for (arr.entries.items) |entry| {
        if (entry.key != .string) continue;
        const key = entry.key.string;
        const var_name = switch (type_flag) {
            2 => try std.fmt.allocPrint(ctx.allocator, "${s}_{s}", .{ prefix, key }), // EXTR_PREFIX_ALL (zphp's value)
            else => try std.fmt.allocPrint(ctx.allocator, "${s}", .{key}),
        };
        try ctx.strings.append(ctx.allocator, var_name);

        // EXTR_SKIP (=1): skip if variable already exists in current scope
        if (type_flag == 1) {
            var exists = false;
            for (slot_names, 0..) |sn, i| {
                if (std.mem.eql(u8, sn, var_name)) {
                    if (i < frame.locals.len and frame.locals[i] != .null) exists = true;
                    break;
                }
            }
            if (!exists) {
                if (frame.vars.get(var_name)) |v| {
                    if (v != .null) exists = true;
                }
            }
            if (exists) continue;
        }

        try frame.vars.put(ctx.allocator, var_name, entry.value);
        for (slot_names, 0..) |sn, si| {
            if (std.mem.eql(u8, sn, var_name)) {
                if (si < frame.locals.len) frame.locals[si] = entry.value;
                break;
            }
        }
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

fn native_ksort(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .{ .bool = false };
    const arr = args[0].array;
    const flags: i64 = if (args.len >= 2) Value.toInt(args[1]) else 0;
    sortKeysWithFlags(arr, flags, false);
    try arr.rebuildStringIndex(ctx.allocator);
    arr.cursor = 0;
    return .{ .bool = true };
}

fn native_krsort(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .{ .bool = false };
    const arr = args[0].array;
    const flags: i64 = if (args.len >= 2) Value.toInt(args[1]) else 0;
    sortKeysWithFlags(arr, flags, true);
    try arr.rebuildStringIndex(ctx.allocator);
    arr.cursor = 0;
    return .{ .bool = true };
}

fn native_asort(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .{ .bool = false };
    const arr = args[0].array;
    const flags: i64 = if (args.len >= 2) Value.toInt(args[1]) else 0;
    sortWithFlags(arr, flags, false);
    try arr.rebuildStringIndex(ctx.allocator);
    arr.cursor = 0;
    return .{ .bool = true };
}

fn native_arsort(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .{ .bool = false };
    const arr = args[0].array;
    const flags: i64 = if (args.len >= 2) Value.toInt(args[1]) else 0;
    sortWithFlags(arr, flags, true);
    try arr.rebuildStringIndex(ctx.allocator);
    arr.cursor = 0;
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
    try mergeSort(PhpArray.Entry, arr.entries.items, ctx, callback, .value);
    try arr.rebuildStringIndex(ctx.allocator);
    arr.cursor = 0;
    return .{ .bool = true };
}

fn native_uksort(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .{ .bool = false };
    const arr = args[0].array;
    const callback = args[1];
    try mergeSort(PhpArray.Entry, arr.entries.items, ctx, callback, .key);
    try arr.rebuildStringIndex(ctx.allocator);
    arr.cursor = 0;
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
    if (arr.cursor == 0 or arr.cursor > arr.entries.items.len) {
        arr.cursor = std.math.maxInt(usize);
        return Value{ .bool = false };
    }
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

fn walkRecursive(ctx: *NativeContext, arr: *PhpArray, callback: Value, userdata: ?Value) RuntimeError!void {
    for (arr.entries.items, 0..) |entry, idx| {
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
            arr.entries.items[idx].value = call_args[0];
        }
    }
}

fn array_walk_recursive(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .{ .bool = false };
    const userdata: ?Value = if (args.len >= 3) args[2] else null;
    try walkRecursive(ctx, args[0].array, args[1], userdata);
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

fn array_udiff(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[0] != .array) return .null;
    const src = args[0].array;
    const callback = args[args.len - 1];
    var result = try ctx.createArray();
    for (src.entries.items) |entry| {
        var in_any = false;
        for (args[1 .. args.len - 1]) |arg| {
            if (arg != .array) continue;
            for (arg.array.entries.items) |other| {
                const cmp = try ctx.invokeCallable(callback, &.{ entry.value, other.value });
                if (Value.toInt(cmp) == 0) { in_any = true; break; }
            }
            if (in_any) break;
        }
        if (!in_any) try result.set(ctx.allocator, entry.key, entry.value);
    }
    return .{ .array = result };
}

fn array_uintersect(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[0] != .array) return .null;
    const src = args[0].array;
    const callback = args[args.len - 1];
    var result = try ctx.createArray();
    for (src.entries.items) |entry| {
        var in_all = true;
        for (args[1 .. args.len - 1]) |arg| {
            if (arg != .array) { in_all = false; break; }
            var found = false;
            for (arg.array.entries.items) |other| {
                const cmp = try ctx.invokeCallable(callback, &.{ entry.value, other.value });
                if (Value.toInt(cmp) == 0) { found = true; break; }
            }
            if (!found) { in_all = false; break; }
        }
        if (in_all) try result.set(ctx.allocator, entry.key, entry.value);
    }
    return .{ .array = result };
}

fn array_udiff_assoc(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[0] != .array) return .null;
    const src = args[0].array;
    const callback = args[args.len - 1];
    var result = try ctx.createArray();
    for (src.entries.items) |entry| {
        var in_any = false;
        for (args[1 .. args.len - 1]) |arg| {
            if (arg != .array) continue;
            for (arg.array.entries.items) |other| {
                if (!entry.key.eql(other.key)) continue;
                const cmp = try ctx.invokeCallable(callback, &.{ entry.value, other.value });
                if (Value.toInt(cmp) == 0) { in_any = true; break; }
            }
            if (in_any) break;
        }
        if (!in_any) try result.set(ctx.allocator, entry.key, entry.value);
    }
    return .{ .array = result };
}

fn array_uintersect_assoc(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[0] != .array) return .null;
    const src = args[0].array;
    const callback = args[args.len - 1];
    var result = try ctx.createArray();
    for (src.entries.items) |entry| {
        var in_all = true;
        for (args[1 .. args.len - 1]) |arg| {
            if (arg != .array) { in_all = false; break; }
            var found = false;
            for (arg.array.entries.items) |other| {
                if (!entry.key.eql(other.key)) continue;
                const cmp = try ctx.invokeCallable(callback, &.{ entry.value, other.value });
                if (Value.toInt(cmp) == 0) { found = true; break; }
            }
            if (!found) { in_all = false; break; }
        }
        if (in_all) try result.set(ctx.allocator, entry.key, entry.value);
    }
    return .{ .array = result };
}

fn array_udiff_uassoc(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 4 or args[0] != .array) return .null;
    const src = args[0].array;
    const value_cb = args[args.len - 2];
    const key_cb = args[args.len - 1];
    var result = try ctx.createArray();
    for (src.entries.items) |entry| {
        var in_any = false;
        for (args[1 .. args.len - 2]) |arg| {
            if (arg != .array) continue;
            for (arg.array.entries.items) |other| {
                const kcmp = try ctx.invokeCallable(key_cb, &.{ keyToValue(entry.key), keyToValue(other.key) });
                if (Value.toInt(kcmp) != 0) continue;
                const vcmp = try ctx.invokeCallable(value_cb, &.{ entry.value, other.value });
                if (Value.toInt(vcmp) == 0) { in_any = true; break; }
            }
            if (in_any) break;
        }
        if (!in_any) try result.set(ctx.allocator, entry.key, entry.value);
    }
    return .{ .array = result };
}

fn array_uintersect_uassoc(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 4 or args[0] != .array) return .null;
    const src = args[0].array;
    const value_cb = args[args.len - 2];
    const key_cb = args[args.len - 1];
    var result = try ctx.createArray();
    for (src.entries.items) |entry| {
        var in_all = true;
        for (args[1 .. args.len - 2]) |arg| {
            if (arg != .array) { in_all = false; break; }
            var found = false;
            for (arg.array.entries.items) |other| {
                const kcmp = try ctx.invokeCallable(key_cb, &.{ keyToValue(entry.key), keyToValue(other.key) });
                if (Value.toInt(kcmp) != 0) continue;
                const vcmp = try ctx.invokeCallable(value_cb, &.{ entry.value, other.value });
                if (Value.toInt(vcmp) == 0) { found = true; break; }
            }
            if (!found) { in_all = false; break; }
        }
        if (in_all) try result.set(ctx.allocator, entry.key, entry.value);
    }
    return .{ .array = result };
}

fn array_intersect_uassoc(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[0] != .array) return .null;
    const src = args[0].array;
    const callback = args[args.len - 1];
    var result = try ctx.createArray();
    for (src.entries.items) |entry| {
        var in_all = true;
        for (args[1 .. args.len - 1]) |arg| {
            if (arg != .array) { in_all = false; break; }
            var found = false;
            for (arg.array.entries.items) |other| {
                const key_cmp = try ctx.invokeCallable(callback, &.{ keyToValue(entry.key), keyToValue(other.key) });
                if (Value.toInt(key_cmp) == 0 and Value.equal(entry.value, other.value)) { found = true; break; }
            }
            if (!found) { in_all = false; break; }
        }
        if (in_all) try result.set(ctx.allocator, entry.key, entry.value);
    }
    return .{ .array = result };
}

fn array_intersect_ukey(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[0] != .array) return .null;
    const src = args[0].array;
    const callback = args[args.len - 1];
    var result = try ctx.createArray();
    for (src.entries.items) |entry| {
        var in_all = true;
        for (args[1 .. args.len - 1]) |arg| {
            if (arg != .array) { in_all = false; break; }
            var found = false;
            for (arg.array.entries.items) |other| {
                const cmp = try ctx.invokeCallable(callback, &.{ keyToValue(entry.key), keyToValue(other.key) });
                if (Value.toInt(cmp) == 0) { found = true; break; }
            }
            if (!found) { in_all = false; break; }
        }
        if (in_all) try result.set(ctx.allocator, entry.key, entry.value);
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
