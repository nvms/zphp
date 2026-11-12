const std = @import("std");
const platform = @import("../platform.zig");
const Value = @import("../runtime/value.zig").Value;
const phpTypeName = @import("types.zig").phpTypeName;
const html = @import("html.zig");
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
    arr.cursor = 0;
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
    arr.cursor = 0;

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
    const arr = try ctx.createArray();
    for (src.entries.items) |entry| try ctx.vm.arrayAddCarried(arr, null, entry, src);
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
    const arr = try ctx.createArray();
    var i: usize = src.entries.items.len;
    while (i > 0) {
        i -= 1;
        const entry = src.entries.items[i];
        const key: ?PhpArray.Key = if (entry.key == .int and !preserve) null else entry.key;
        try ctx.vm.arrayAddCarried(arr, key, entry, src);
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn array_merge(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    for (args) |arg| {
        if (arg != .array) continue;
        for (arg.array.entries.items) |entry| {
            const key: ?PhpArray.Key = if (entry.key == .int) null else entry.key;
            try ctx.vm.arrayAddCarried(arr, key, entry, arg.array);
        }
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn array_slice(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .array) return NativeResult.scalar(.null);
    const src = args[0].array;
    const slen: i64 = @intCast(src.entries.items.len);
    const p = @import("string_ports.zig").Args.init(ctx, "array_slice", args);
    var offset = try p.long(1, "offset");
    const length_arg = try p.longOrNull(2, "length");
    const preserve_keys = try p.boolean(3, "preserve_keys", false);
    if (offset < 0) offset = @max(0, slen + offset);
    if (offset >= slen) {
        return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    }
    const uoffset: usize = @intCast(offset);
    var raw_length: i64 = length_arg orelse slen - offset;
    if (raw_length < 0) raw_length = @max(0, slen - offset + raw_length);
    const length: usize = @intCast(@max(0, @min(slen - offset, raw_length)));
    const end = @min(src.entries.items.len, uoffset + length);

    const arr = try ctx.createArray();
    for (src.entries.items[uoffset..end]) |entry| {
        const key: ?PhpArray.Key = if (entry.key == .int and !preserve_keys) null else entry.key;
        try ctx.vm.arrayAddCarried(arr, key, entry, src);
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn array_unique(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(.null);
    const src = args[0].array;
    // default in PHP is SORT_STRING (2)
    const raw_flag: i64 = if (args.len >= 2) Value.toInt(args[1]) else 2;

    // nothing to compare: the array as it is
    if (src.entries.items.len <= 1) {
        const arr = try ctx.createArray();
        for (src.entries.items) |entry| try ctx.vm.arrayAddCarried(arr, entry.key, entry, src);
        return NativeResult.borrowed(.{ .array = arr });
    }

    // SORT_STRING: the first element of each string value, in order
    if (raw_flag == 2) {
        var seen = std.StringHashMapUnmanaged(void).empty;
        var held = std.ArrayListUnmanaged(Value.String).empty;
        defer {
            seen.deinit(ctx.allocator);
            for (held.items) |s| s.release();
            held.deinit(ctx.allocator);
        }
        const arr = try ctx.createArray();
        for (src.entries.items) |entry| {
            const v = if (entry.ref) |cell| cell.* else entry.value;
            const text: []const u8 = switch (v) {
                .string => |s| s.bytes(),
                .array => blk: {
                    try ctx.vm.emitWarning("Array to string conversion");
                    break :blk "Array";
                },
                else => blk: {
                    const s = try valueAsStringForCompare(ctx, v);
                    try held.append(ctx.allocator, s);
                    break :blk s.bytes();
                },
            };
            const gop = try seen.getOrPut(ctx.allocator, text);
            if (gop.found_existing) continue;
            try ctx.vm.arrayAddCarried(arr, entry.key, entry, src);
        }
        return NativeResult.borrowed(.{ .array = arr });
    }

    // the other flags compare pairs; php sorts and drops the later of equal
    // neighbours, which keeps each value's first element
    const case_insensitive = (raw_flag & 8) != 0; // SORT_FLAG_CASE
    const flag = raw_flag & ~@as(i64, 8);
    const keep = try ctx.allocator.alloc(bool, src.entries.items.len);
    defer ctx.allocator.free(keep);
    for (src.entries.items, 0..) |entry, i| {
        keep[i] = true;
        for (src.entries.items[0..i], keep[0..i]) |existing, kept| {
            if (!kept) continue;
            const eq = switch (flag) {
                1 => Value.toFloat(entry.value) == Value.toFloat(existing.value), // SORT_NUMERIC
                2, 5, 6 => blk: { // SORT_STRING with SORT_FLAG_CASE, SORT_LOCALE_STRING, SORT_NATURAL
                    const a_str = try valueAsStringForCompare(ctx, entry.value);
                    defer a_str.release();
                    const b_str = try valueAsStringForCompare(ctx, existing.value);
                    defer b_str.release();
                    break :blk if (case_insensitive) std.ascii.eqlIgnoreCase(a_str.bytes(), b_str.bytes()) else std.mem.eql(u8, a_str.bytes(), b_str.bytes());
                },
                else => Value.equal(entry.value, existing.value), // SORT_REGULAR
            };
            if (eq) {
                keep[i] = false;
                break;
            }
        }
    }
    return NativeResult.borrowed(.{ .array = try ctx.vm.copyKeptEntries(src, keep, true) });
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
                    // ZVAL_COPY: a reference stays one
                    const entry = a.array.entries.items[i];
                    try ctx.vm.arrayAddEntry(tuple, null, entry, entry.ref);
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
        const result = try ctx.createArray();
        for (src.entries.items) |entry| try ctx.vm.arrayAddCarried(result, entry.key, entry, src);
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

    const result = try ctx.createArray();
    if (args.len < 2) {
        for (src.entries.items) |entry| {
            if (entry.value.isTruthy()) try ctx.vm.arrayAddCarried(result, entry.key, entry, src);
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
            if (keep.isTruthy()) try ctx.vm.arrayAddCarried(result, entry.key, entry, src);
        }
    }
    return NativeResult.borrowed(.{ .array = result });
}

fn array_splice(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .array) return NativeResult.scalar(.null);
    const arr = args[0].array;
    const alen: i64 = @intCast(arr.entries.items.len);
    const p = @import("string_ports.zig").Args.init(ctx, "array_splice", args);
    var offset = try p.long(1, "offset");
    const length_arg = try p.longOrNull(2, "length");
    if (offset < 0) offset = @max(0, alen + offset);
    if (offset > alen) offset = alen;
    const uoffset: usize = @intCast(offset);

    // a null length runs to the end, as an omitted one does
    var length: usize = if (length_arg) |given| blk: {
        var l = given;
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
    } else if (args.len >= 4 and args[3] == .object and !std.mem.eql(u8, args[3].object.class_name, "Closure")) blk: {
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
                    if (value == .undef or (value == .null and ctx.vm.typedPropForbidsNull(property.type_str))) continue;
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
    // php_splice moves elements as they are: a reference stays one in the
    // removed array and an inserted reference is inserted as one
    ctx.vm.detachArrayRefs(arr);
    const removed = try ctx.createArray();
    for (arr.entries.items[uoffset..][0..length]) |entry| {
        try ctx.vm.arrayAddEntry(removed, if (entry.key == .string) entry.key else null, entry, entry.ref);
    }
    for (0..length) |_| ctx.vm.arrayRemoveOwned(arr, arr.entries.items[uoffset].key);
    const replacement_refs: []const PhpArray.Entry = if (args.len >= 4 and args[3] == .array) args[3].array.entries.items else &.{};
    for (replacement_values, 0..) |value, i| {
        VM.retainValue(value);
        arr.entries.insertAssumeCapacity(uoffset + i, .{ .key = .{ .int = 0 }, .value = value });
        if (i < replacement_refs.len) if (replacement_refs[i].ref) |cell| ctx.vm.setEntryRef(&arr.entries.items[uoffset + i], cell);
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
    try ctx.vm.attachArrayRefs(arr);

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
        const chunk = try ctx.createArray();
        const end = @min(i + size, src.entries.items.len);
        for (src.entries.items[i..end]) |entry| try ctx.vm.arrayAddCarried(chunk, if (preserve_keys) entry.key else null, entry, src);
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
    if (abs_target_i64 > 1_073_741_824) {
        try ctx.vm.setPendingException("ValueError", "array_pad(): Argument #2 ($length) must not exceed the maximum allowed array size");
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
        const value = if (entry.ref) |cell| cell.* else entry.value;
        if (value != .int and value != .string) {
            try ctx.vm.emitWarning("array_flip(): Can only flip string and integer values, entry skipped");
            continue;
        }
        const new_key = Value.toArrayKey(value);
        const new_val: Value = switch (entry.key) {
            .int => |i| .{ .int = i },
            .string => |s| .{ .string = s },
        };
        try ctx.vm.arraySetOwned(result, new_key, new_val);
    }
    return NativeResult.borrowed(.{ .array = result });
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
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(.{ .int = 0 });
    if (args.len == 1) return NativeResult.scalar(.{ .int = args[0].array.length() });
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

// php_array_data_shuffle over the default engine, mt_rand's
fn native_shuffle(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(.{ .bool = false });
    const arr = args[0].array;
    if (!ctx.vm.rng_seeded) {
        var entropy: [4]u8 = undefined;
        platform.random.bytes(&entropy);
        ctx.vm.mt19937.seed(std.mem.readInt(u32, &entropy, .little));
        ctx.vm.rng_seeded = true;
    }
    var i: usize = arr.entries.items.len;
    while (i > 1) {
        i -= 1;
        const j: usize = @intCast(ctx.vm.mt19937.nextRange(0, @intCast(i)));
        if (j != i) std.mem.swap(PhpArray.Entry, &arr.entries.items[i], &arr.entries.items[j]);
    }
    reindexArray(arr);
    return NativeResult.scalar(.{ .bool = true });
}

fn array_rand(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(.null);
    const arr = args[0].array;
    const num: i64 = if (args.len >= 2) try (html.Params{ .ctx = ctx, .func = "array_rand", .args = args }).int(1, "num", 1) else 1;
    if (arr.entries.items.len == 0) {
        try ctx.vm.setPendingException("ValueError", "array_rand(): Argument #1 ($array) must not be empty");
        return error.RuntimeError;
    }
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
        try ctx.vm.arrayAddCarried(result, entry.key, entry, args[0].array);
    }
    for (args[1..]) |arg| {
        if (arg != .array) continue;
        for (arg.array.entries.items) |entry| {
            try ctx.vm.arrayAddCarried(result, entry.key, entry, args[0].array);
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
            .int => {
                const before = dest.entries.items.len;
                try ctx.vm.arrayAddCarried(dest, null, entry, src);
                if (dest.entries.items.len == before) _ = try nextElementOccupied(ctx);
            },
            .string => {
                if (!dest.contains(entry.key)) {
                    try ctx.vm.arrayAddCarried(dest, entry.key, entry, src);
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
    const case_upper = (try (html.Params{ .ctx = ctx, .func = "array_change_key_case", .args = args }).int(1, "case", 0)) != 0;
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
// php_array_binop: each element through add_function or mul_function, with
// php's warnings for the types they refuse
fn arrayBinop(ctx: *NativeContext, comptime func: []const u8, comptime op_name: []const u8, args: []const Value, comptime multiply: bool) RuntimeError!NativeResult {
    if (args[0] != .array) return throwArrayTypeError(ctx, func, 1, args[0]);
    const src = args[0].array;
    var acc: Value = .{ .int = if (multiply) 1 else 0 };
    if (src.entries.items.len == 0) return NativeResult.scalar(acc);
    var i: usize = 0;
    while (i < src.entries.items.len) : (i += 1) {
        const entry = src.entries.items[i];
        const v = if (entry.ref) |cell| cell.* else entry.value;
        const operand: Value = switch (v) {
            .int, .float => v,
            .null => .{ .int = 0 },
            .bool => |b| .{ .int = @intFromBool(b) },
            .string => |s| blk: {
                if (numericPrefix(s.bytes())) |n| {
                    if (!n.whole) try ctx.vm.emitWarning("A non-numeric value encountered");
                    break :blk n.value;
                }
                // php used to count a non-numeric string as 0
                _ = try unsupportedOperand(ctx, func, op_name, "string");
                break :blk Value{ .int = 0 };
            },
            .object => |o| if (@import("../runtime/value.zig").nativeCast(o, .number)) |n| n else {
                _ = try unsupportedOperand(ctx, func, op_name, @import("../runtime/class_names.zig").display(o.class_name));
                continue;
            },
            .resource => |r| blk: {
                // and a resource as its number
                _ = try unsupportedOperand(ctx, func, op_name, "resource");
                break :blk Value{ .int = r.id };
            },
            else => {
                _ = try unsupportedOperand(ctx, func, op_name, phpTypeName(v));
                continue;
            },
        };
        acc = arith(acc, operand, multiply);
    }
    return NativeResult.scalar(acc);
}

fn unsupportedOperand(ctx: *NativeContext, comptime func: []const u8, comptime op_name: []const u8, type_name: []const u8) RuntimeError!?Value {
    const msg = try std.fmt.allocPrint(ctx.allocator, func ++ "(): " ++ op_name ++ " is not supported on type {s}", .{type_name});
    defer ctx.allocator.free(msg);
    try ctx.vm.emitWarning(msg);
    return null;
}

// integer arithmetic that overflows into a float, as php's does
fn arith(a: Value, b: Value, multiply: bool) Value {
    if (a == .int and b == .int) {
        const r = if (multiply) @mulWithOverflow(a.int, b.int) else @addWithOverflow(a.int, b.int);
        if (r[1] == 0) return .{ .int = r[0] };
        const fa: f64 = @floatFromInt(a.int);
        const fb: f64 = @floatFromInt(b.int);
        return .{ .float = if (multiply) fa * fb else fa + fb };
    }
    const fa = Value.toFloat(a);
    const fb = Value.toFloat(b);
    return .{ .float = if (multiply) fa * fb else fa + fb };
}

const NumericPrefix = struct { value: Value, whole: bool };

// the number a string starts with (php's leading-numeric strings), and
// whether that is the whole string apart from whitespace
fn numericPrefix(s: []const u8) ?NumericPrefix {
    const ws = " \t\n\r\x0b\x0c";
    var i: usize = 0;
    while (i < s.len and std.mem.indexOfScalar(u8, ws, s[i]) != null) i += 1;
    const start = i;
    if (i < s.len and (s[i] == '+' or s[i] == '-')) i += 1;
    var digits: usize = 0;
    while (i < s.len and std.ascii.isDigit(s[i])) : (i += 1) digits += 1;
    var is_float = false;
    if (i < s.len and s[i] == '.') {
        const dot = i;
        i += 1;
        var frac: usize = 0;
        while (i < s.len and std.ascii.isDigit(s[i])) : (i += 1) frac += 1;
        if (digits + frac == 0) i = dot else is_float = true;
        digits += frac;
    }
    if (digits == 0) return null;
    if (i < s.len and (s[i] == 'e' or s[i] == 'E')) {
        var j = i + 1;
        if (j < s.len and (s[j] == '+' or s[j] == '-')) j += 1;
        if (j < s.len and std.ascii.isDigit(s[j])) {
            while (j < s.len and std.ascii.isDigit(s[j])) j += 1;
            i = j;
            is_float = true;
        }
    }
    const text = s[start..i];
    var end = i;
    while (end < s.len and std.mem.indexOfScalar(u8, ws, s[end]) != null) end += 1;
    const whole = end == s.len;
    if (!is_float) {
        if (std.fmt.parseInt(i64, text, 10)) |n| return .{ .value = .{ .int = n }, .whole = whole } else |_| {}
    }
    const f = std.fmt.parseFloat(f64, text) catch return null;
    return .{ .value = .{ .float = f }, .whole = whole };
}

fn array_sum(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return arrayBinop(ctx, "array_sum", "Addition", args, false);
}

fn array_product(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return arrayBinop(ctx, "array_product", "Multiplication", args, true);
}
fn array_key_exists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const arr = args[1].array;
    const key: PhpArray.Key = switch (args[0]) {
        .string => |s| PhpArray.normalizeKey(.{ .string = s }),
        .int => |i| .{ .int = i },
        .null, .undef => blk: {
            try ctx.vm.raiseError(8192, "Using null as the key parameter for array_key_exists() is deprecated, use an empty string instead");
            if (ctx.vm.pending_exception != null) return error.RuntimeError;
            break :blk .{ .string = Value.String.borrowed("") };
        },
        .float => |f| blk: {
            // zend_dval_to_lval_safe
            if (!Value.floatFitsInt(f) or f != @trunc(f)) {
                var tmp: [64]u8 = undefined;
                const msg = try std.fmt.allocPrint(ctx.allocator, "Implicit conversion from float {s} to int loses precision", .{@import("output.zig").formatFloat(&tmp, f)});
                defer ctx.allocator.free(msg);
                try ctx.vm.raiseError(8192, msg);
                if (ctx.vm.pending_exception != null) return error.RuntimeError;
            }
            break :blk .{ .int = if (Value.floatFitsInt(f)) @intFromFloat(@trunc(f)) else 0 };
        },
        .bool => |b| .{ .int = @intFromBool(b) },
        .resource => |r| blk: {
            try ctx.vm.warnResourceOffset(args[0]);
            break :blk .{ .int = r.id };
        },
        else => return invalidKeyExistsOffset(ctx, args[0]),
    };
    return NativeResult.scalar(.{ .bool = arr.contains(key) });
}

fn invalidKeyExistsOffset(ctx: *NativeContext, key: Value) RuntimeError!NativeResult {
    const msg = try std.fmt.allocPrint(ctx.allocator, "Cannot access offset of type {s} on array", .{phpTypeName(key)});
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("TypeError", msg);
    return error.RuntimeError;
}
// php_valid_var_name: [a-zA-Z_\x7f-\xff][a-zA-Z0-9_\x7f-\xff]*
fn validVarName(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name, 0..) |c, i| {
        const ok = c == '_' or std.ascii.isAlphabetic(c) or c >= 0x7f or (i > 0 and std.ascii.isDigit(c));
        if (!ok) return false;
    }
    return true;
}

const extr_overwrite = 0;
const extr_skip = 1;
const extr_prefix_same = 2;
const extr_prefix_all = 3;
const extr_prefix_invalid = 4;
const extr_if_exists = 6;
const extr_prefix_if_exists = 5;
const extr_refs = 0x100;

fn native_extract(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = html.Params{ .ctx = ctx, .func = "extract", .args = args };
    const arr = args[0].array;
    const flags = try p.int(1, "flags", extr_overwrite);
    const prefix_arg: ?[]const u8 = if (args.len >= 3) try p.string(2, "prefix", "") else null;
    const extract_type = flags & 0xff;
    if (extract_type < extr_overwrite or extract_type > extr_if_exists) return extractError(ctx, "ValueError", "extract(): Argument #2 ($flags) must be a valid extract type");
    if (extract_type > extr_skip and extract_type <= extr_prefix_if_exists and args.len < 3) return extractError(ctx, "ValueError", "extract(): Argument #3 ($prefix) is required when using this extract type");
    const prefix = prefix_arg orelse "";
    if (prefix.len > 0 and !validVarName(prefix)) return extractError(ctx, "ValueError", "extract(): Argument #3 ($prefix) must be a valid identifier");

    const frame = ctx.vm.currentFrame();
    const slot_names = if (frame.slot_names.len > 0) frame.slot_names else if (frame.func) |func| func.slot_names else ctx.vm.global_slot_names;
    // the variable as php's symbol table has it: defined when it holds a
    // value; a compiled variable that is unset is there but undefined
    const defined = struct {
        fn f(c: *NativeContext, fr: anytype, names: []const []const u8, name: []const u8) bool {
            _ = names;
            var buf: [256]u8 = undefined;
            const var_name = std.fmt.bufPrint(&buf, "${s}", .{name}) catch return false;
            const v = c.vm.frameVariable(fr, var_name) orelse return false;
            return v != .undef;
        }
    }.f;

    const undefSlot = struct {
        fn f(c: *NativeContext, fr: anytype, names: []const []const u8, name: []const u8) bool {
            var buf: [256]u8 = undefined;
            const var_name = std.fmt.bufPrint(&buf, "${s}", .{name}) catch return false;
            for (names) |sn| {
                if (std.mem.eql(u8, sn, var_name)) return (c.vm.frameVariable(fr, var_name) orelse @as(Value, .undef)) == .undef;
            }
            return false;
        }
    }.f;

    var count: i64 = 0;
    var i: usize = 0;
    while (i < arr.entries.items.len) : (i += 1) {
        const entry = arr.entries.items[i];
        const value = if (entry.ref) |cell| cell.* else entry.value;
        var key_buf: [24]u8 = undefined;
        const key: []const u8 = switch (entry.key) {
            .string => |s| s.bytes(),
            .int => |n| blk: {
                if (extract_type != extr_prefix_all and extract_type != extr_prefix_invalid) continue;
                break :blk std.fmt.bufPrint(&key_buf, "{d}", .{n}) catch unreachable;
            },
        };
        const prefixed = try std.fmt.allocPrint(ctx.allocator, "{s}_{s}", .{ prefix, key });
        defer ctx.allocator.free(prefixed);
        var target: ?[]const u8 = null;
        switch (extract_type) {
            extr_overwrite => {
                if (!validVarName(key)) continue;
                if (std.mem.eql(u8, key, "this")) return extractError(ctx, "Error", "Cannot re-assign $this");
                // $GLOBALS is no variable to php: the key lands in the symbol table
                // where nothing reads it
                if (std.mem.eql(u8, key, "GLOBALS")) {
                    count += 1;
                    continue;
                }
                target = key;
            },
            extr_skip => {
                if (!validVarName(key) or std.mem.eql(u8, key, "this")) continue;
                if (defined(ctx, frame, slot_names, key)) continue;
                target = key;
            },
            extr_if_exists => {
                if (!defined(ctx, frame, slot_names, key)) continue;
                if (!validVarName(key) or std.mem.eql(u8, key, "GLOBALS")) continue;
                if (std.mem.eql(u8, key, "this")) return extractError(ctx, "Error", "Cannot re-assign $this");
                target = key;
            },
            extr_prefix_same => {
                if (key.len == 0) continue;
                if (defined(ctx, frame, slot_names, key) or std.mem.eql(u8, key, "this")) {
                    if (!validVarName(prefixed)) continue;
                    target = prefixed;
                } else {
                    if (!validVarName(key)) continue;
                    target = key;
                }
            },
            extr_prefix_if_exists => {
                // a compiled variable that is unset takes the value itself
                if (undefSlot(ctx, frame, slot_names, key)) {
                    target = key;
                } else if (!defined(ctx, frame, slot_names, key)) continue;
                if (target != null) {
                    const var_name = try internVarName(ctx, "${s}", .{key});
                    try ctx.vm.setVariableByName(frame, var_name, try ctx.vm.copyValue(value));
                    count += 1;
                    continue;
                }
                if (!validVarName(prefixed)) continue;
                target = prefixed;
            },
            extr_prefix_all => {
                if (entry.key == .string and key.len == 0) continue;
                if (!validVarName(prefixed)) continue;
                target = prefixed;
            },
            else => { // EXTR_PREFIX_INVALID
                if (entry.key == .string and validVarName(key) and !std.mem.eql(u8, key, "this")) {
                    target = key;
                } else {
                    if (!validVarName(prefixed)) continue;
                    target = prefixed;
                }
            },
        }
        const name = target.?;
        if (std.mem.eql(u8, name, "this")) return extractError(ctx, "Error", "Cannot re-assign $this");
        const var_name = try internVarName(ctx, "${s}", .{name});
        try ctx.vm.setVariableByName(frame, var_name, try ctx.vm.copyValue(value));
        count += 1;
    }
    return NativeResult.scalar(.{ .int = count });
}

fn extractError(ctx: *NativeContext, class: []const u8, msg: []const u8) RuntimeError!NativeResult {
    try ctx.vm.setPendingException(class, msg);
    return error.RuntimeError;
}
fn native_compact(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    const frame = ctx.vm.currentFrame();
    for (args, 1..) |arg, pos| try compactValue(ctx, arg, arr, frame, pos);
    return NativeResult.borrowed(.{ .array = arr });
}

// php_compact_var
fn compactValue(ctx: *NativeContext, arg_in: Value, arr: *PhpArray, frame: anytype, pos: usize) RuntimeError!void {
    const arg = arg_in;
    if (arg == .string) {
        const name = arg.string.bytes();
        const var_name = try std.fmt.allocPrint(ctx.allocator, "${s}", .{name});
        defer ctx.allocator.free(var_name);
        const found = ctx.vm.frameVariable(frame, var_name);
        if (std.mem.eql(u8, name, "this")) {
            // $this is no variable: only an object in scope is taken
            if (found) |val| if (val == .object) try ctx.vm.arraySetOwned(arr, .{ .string = arg.string }, val);
            return;
        }
        if (found) |val| if (val != .undef) {
            try ctx.vm.arraySetOwned(arr, .{ .string = arg.string }, val);
            return;
        };
        const w = try std.fmt.allocPrint(ctx.allocator, "compact(): Undefined variable ${s}", .{name});
        defer ctx.allocator.free(w);
        try ctx.vm.emitWarning(w);
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
        for (names.entries.items) |entry| try compactValue(ctx, if (entry.ref) |cell| cell.* else entry.value, arr, frame, pos);
    } else {
        const shown: []const u8 = switch (arg) {
            .bool => |b| if (b) "true" else "false",
            .object => |o| @import("../runtime/class_names.zig").display(o.class_name),
            else => phpTypeName(arg),
        };
        const w = try std.fmt.allocPrint(ctx.allocator, "compact(): Argument #{d} must be string or array of strings, {s} given", .{ pos, shown });
        defer ctx.allocator.free(w);
        try ctx.vm.emitWarning(w);
    }
}
const RangeInput = enum { failed, long, double, string, digit };

const RangeValue = struct { kind: RangeInput, long: i64 = 0, double: f64 = 0 };

// is_numeric_str_function: a numeric string as an int or a float
fn numericString(s: []const u8) ?Value {
    if (!Value.isNumericString(s)) return null;
    const t = std.mem.trim(u8, s, " \t\n\r\x0b\x0c");
    const is_float = std.mem.indexOfAny(u8, t, ".eE") != null;
    if (!is_float) {
        if (std.fmt.parseInt(i64, t, 10)) |n| return .{ .int = n } else |_| {}
    }
    return .{ .float = std.fmt.parseFloat(f64, t) catch return null };
}

fn rangeError(ctx: *NativeContext, comptime fmt: []const u8, args: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("ValueError", msg);
    return error.RuntimeError;
}

// php_range_process_input, after Z_PARAM_NUMBER_OR_STR
fn rangeInput(ctx: *NativeContext, v_in: Value, comptime arg: usize, comptime name: []const u8) RuntimeError!RangeValue {
    var v = v_in;
    switch (v) {
        .null, .undef => {
            if (ctx.vm.topFrameStrict()) return rangeTypeError(ctx, arg, name, v);
            try ctx.vm.raiseError(8192, "range(): Passing null to parameter #" ++ std.fmt.comptimePrint("{d}", .{arg}) ++ " ($" ++ name ++ ") of type string|int|float is deprecated");
            if (ctx.vm.pending_exception != null) return error.RuntimeError;
            v = .{ .int = 0 };
        },
        .bool => |b| {
            if (ctx.vm.topFrameStrict()) return rangeTypeError(ctx, arg, name, v);
            v = .{ .int = @intFromBool(b) };
        },
        .object => |o| {
            if (!ctx.vm.hasMethod(o.class_name, "__toString")) return rangeTypeError(ctx, arg, name, v);
            v = .{ .string = ctx.vm.transientOwned(try ctx.vm.objectString(o)) };
        },
        .int, .float => {},
        .string => {},
        else => return rangeTypeError(ctx, arg, name, v),
    }
    switch (v) {
        .int => |i| return .{ .kind = .long, .long = i, .double = @floatFromInt(i) },
        .float => |f| return checkFinite(ctx, f, arg, name),
        .string => |s| {
            const bytes = s.bytes();
            if (bytes.len == 0) {
                try ctx.vm.emitWarning("range(): Argument #" ++ std.fmt.comptimePrint("{d}", .{arg}) ++ " ($" ++ name ++ ") must not be empty, casted to 0");
                return .{ .kind = .long };
            }
            if (numericString(bytes)) |n| {
                if (n == .float) return checkFinite(ctx, n.float, arg, name);
                return .{ .kind = if (bytes.len == 1) .digit else .long, .long = n.int, .double = @floatFromInt(n.int) };
            }
            if (bytes.len != 1) try ctx.vm.emitWarning("range(): Argument #" ++ std.fmt.comptimePrint("{d}", .{arg}) ++ " ($" ++ name ++ ") must be a single byte, subsequent bytes are ignored");
            return .{ .kind = .string };
        },
        else => unreachable,
    }
}

fn checkFinite(ctx: *NativeContext, f: f64, comptime arg: usize, comptime name: []const u8) RuntimeError!RangeValue {
    if (std.math.isInf(f)) return rangeError(ctx, "range(): Argument #{d} (${s}) must be a finite number, INF provided", .{ arg, name });
    if (std.math.isNan(f)) return rangeError(ctx, "range(): Argument #{d} (${s}) must be a finite number, NAN provided", .{ arg, name });
    return .{ .kind = .double, .double = f };
}

fn rangeTypeError(ctx: *NativeContext, comptime arg: usize, comptime name: []const u8, v: Value) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, "range(): Argument #{d} (${s}) must be of type string|int|float, {s} given", .{ arg, name, phpTypeName(v) });
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("TypeError", msg);
    return error.RuntimeError;
}

const ht_max_size: u64 = 0x40000000;

fn native_range(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    var is_step_double = false;
    var is_step_negative = false;
    var step_double: f64 = 1.0;
    var step: i64 = 1;
    if (args.len >= 3) {
        var sv = args[2];
        // Z_PARAM_NUMBER
        switch (sv) {
            .int, .float => {},
            .string => |s| if (!ctx.vm.topFrameStrict()) {
                sv = numericString(s.bytes()) orelse return stepTypeError(ctx, sv);
            } else return stepTypeError(ctx, sv),
            .null, .undef => {
                if (ctx.vm.topFrameStrict()) return stepTypeError(ctx, sv);
                try ctx.vm.raiseError(8192, "range(): Passing null to parameter #3 ($step) of type int|float is deprecated");
                if (ctx.vm.pending_exception != null) return error.RuntimeError;
                sv = .{ .int = 0 };
            },
            .bool => |b| {
                if (ctx.vm.topFrameStrict()) return stepTypeError(ctx, sv);
                sv = .{ .int = @intFromBool(b) };
            },
            else => return stepTypeError(ctx, sv),
        }
        if (sv == .float) {
            step_double = sv.float;
            if (std.math.isInf(step_double)) return rangeError(ctx, "range(): Argument #3 ($step) must be a finite number, INF provided", .{});
            if (std.math.isNan(step_double)) return rangeError(ctx, "range(): Argument #3 ($step) must be a finite number, NAN provided", .{});
            if (step_double < 0.0) {
                is_step_negative = true;
                step_double *= -1;
            }
            step = if (Value.floatFitsInt(step_double)) @intFromFloat(step_double) else 0;
            if (@as(f64, @floatFromInt(step)) != step_double) is_step_double = true;
        } else {
            step = sv.int;
            if (step < 0) {
                if (step == std.math.minInt(i64)) return rangeError(ctx, "range(): Argument #3 ($step) must be greater than {d}", .{step});
                is_step_negative = true;
                step = -step;
            }
            step_double = @floatFromInt(step);
        }
        if (step_double == 0.0) return rangeError(ctx, "range(): Argument #3 ($step) cannot be 0", .{});
    }

    var start = try rangeInput(ctx, args[0], 1, "start");
    var end = try rangeInput(ctx, args[1], 2, "end");
    const arr = try ctx.createArray();
    const is_str = struct {
        fn f(k: RangeInput) bool {
            return k == .string or k == .digit;
        }
    }.f;

    if (is_str(start.kind) or is_str(end.kind)) chars: {
        if (!is_str(start.kind) or !is_str(end.kind)) {
            if (!is_str(start.kind)) {
                if (end.kind != .digit) try ctx.vm.emitWarning("range(): Argument #1 ($start) must be a single byte string if argument #2 ($end) is a single byte string, argument #2 ($end) converted to 0");
                end.kind = .long;
            } else {
                if (start.kind != .digit) try ctx.vm.emitWarning("range(): Argument #2 ($end) must be a single byte string if argument #1 ($start) is a single byte string, argument #1 ($start) converted to 0");
                start.kind = .long;
            }
            break :chars;
        }
        if (is_step_double) {
            if (start.kind == .string or end.kind == .string) try ctx.vm.emitWarning("range(): Argument #3 ($step) must be of type int when generating an array of characters, inputs converted to 0");
            start.kind = .long;
            end.kind = .long;
            break :chars;
        }
        const s0 = try stringBytes(ctx, args[0]);
        const s1 = try stringBytes(ctx, args[1]);
        var low: i64 = s0[0];
        const high: i64 = s1[0];
        if (low > high) {
            if (low - high < step) return boundaryError(ctx);
            while (low >= high) : (low -= step) {
                try appendChar(ctx, arr, @intCast(low));
                if (low - step < 0) break;
            }
        } else if (high > low) {
            if (is_step_negative) return negativeStepError(ctx);
            if (high - low < step) return boundaryError(ctx);
            while (low <= high) : (low += step) {
                try appendChar(ctx, arr, @intCast(low));
                if (low + step > 255) break;
            }
        } else {
            try appendChar(ctx, arr, @intCast(low));
        }
        return NativeResult.borrowed(.{ .array = arr });
    }

    if (start.kind == .double or end.kind == .double or is_step_double) {
        const sd = start.double;
        const ed = end.double;
        if (sd > ed) {
            if (sd - ed < step_double) return boundaryError(ctx);
            const size = try doubleRangeSize(ctx, sd, ed, step_double);
            var i: u64 = 0;
            var element = sd;
            while (i < size and element >= ed) {
                try arr.append(ctx.allocator, .{ .float = element });
                i += 1;
                element = sd - (@as(f64, @floatFromInt(i)) * step_double);
            }
        } else if (ed > sd) {
            if (is_step_negative) return negativeStepError(ctx);
            if (ed - sd < step_double) return boundaryError(ctx);
            const size = try doubleRangeSize(ctx, ed, sd, step_double);
            var i: u64 = 0;
            var element = sd;
            while (i < size and element <= ed) {
                try arr.append(ctx.allocator, .{ .float = element });
                i += 1;
                element = sd + (@as(f64, @floatFromInt(i)) * step_double);
            }
        } else {
            try arr.append(ctx.allocator, .{ .float = sd });
        }
        return NativeResult.borrowed(.{ .array = arr });
    }

    const ustep: u64 = @intCast(step);
    const sl = start.long;
    const el = end.long;
    if (sl > el) {
        const span: u64 = @as(u64, @bitCast(sl)) -% @as(u64, @bitCast(el));
        if (span < ustep) return boundaryError(ctx);
        const size = try longRangeSize(ctx, span, sl, el, step);
        try arr.entries.ensureTotalCapacity(ctx.allocator, size);
        var i: u64 = 0;
        while (i < size) : (i += 1) try arr.append(ctx.allocator, .{ .int = @bitCast(@as(u64, @bitCast(sl)) -% i *% ustep) });
    } else if (el > sl) {
        if (is_step_negative) return negativeStepError(ctx);
        const span: u64 = @as(u64, @bitCast(el)) -% @as(u64, @bitCast(sl));
        if (span < ustep) return boundaryError(ctx);
        const size = try longRangeSize(ctx, span, el, sl, step);
        try arr.entries.ensureTotalCapacity(ctx.allocator, size);
        var i: u64 = 0;
        while (i < size) : (i += 1) try arr.append(ctx.allocator, .{ .int = @bitCast(@as(u64, @bitCast(sl)) +% i *% ustep) });
    } else {
        try arr.append(ctx.allocator, .{ .int = sl });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn stringBytes(ctx: *NativeContext, v: Value) RuntimeError![]const u8 {
    return switch (v) {
        .string => |s| s.bytes(),
        .object => |o| ctx.vm.objectToString(o),
        else => "0",
    };
}

fn appendChar(ctx: *NativeContext, arr: *PhpArray, c: u8) RuntimeError!void {
    const s = try Value.String.create(ctx.allocator, &.{c});
    defer s.release();
    try arr.append(ctx.allocator, .{ .string = s });
}

fn doubleRangeSize(ctx: *NativeContext, hi: f64, lo: f64, step: f64) RuntimeError!u64 {
    const calc = ((hi - lo) / step) + 1;
    const max: f64 = @floatFromInt(ht_max_size);
    if (calc >= max) return rangeError(ctx, "The supplied range exceeds the maximum array size by {d:.1} elements: start={d:.1}, end={d:.1}, step={d:.1}. Max size: {d:.0}", .{ calc - max, lo, hi, step, max });
    return @intFromFloat(@round(calc));
}

fn longRangeSize(ctx: *NativeContext, span: u64, hi: i64, lo: i64, step: i64) RuntimeError!u64 {
    const calc = span / @as(u64, @intCast(step));
    if (calc >= ht_max_size - 1) return rangeError(ctx, "The supplied range exceeds the maximum array size by {d} elements: start={d}, end={d}, step={d}. Calculated size: {d}. Maximum size: {d}.", .{ calc - (ht_max_size - 1), lo, hi, step, calc, ht_max_size });
    return calc + 1;
}

fn boundaryError(ctx: *NativeContext) RuntimeError {
    return rangeError(ctx, "range(): Argument #3 ($step) must be less than the range spanned by argument #1 ($start) and argument #2 ($end)", .{});
}

fn negativeStepError(ctx: *NativeContext) RuntimeError {
    return rangeError(ctx, "range(): Argument #3 ($step) must be greater than 0 for increasing ranges", .{});
}

fn stepTypeError(ctx: *NativeContext, v: Value) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, "range(): Argument #3 ($step) must be of type int|float, {s} given", .{phpTypeName(v)});
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("TypeError", msg);
    return error.RuntimeError;
}

fn native_sizeof(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return @import("types.zig").countAs(ctx, "sizeof", args);
}
const ColumnKey = union(enum) { none, long: i64, str: []const u8 };

// Z_PARAM_STR_OR_LONG_OR_NULL
fn columnKeyParam(ctx: *NativeContext, args: []const Value, index: usize, comptime name: []const u8) RuntimeError!ColumnKey {
    if (index >= args.len) return .none;
    const v = args[index];
    const strict = ctx.vm.topFrameStrict();
    switch (v) {
        .null, .undef => return .none,
        .int => |i| return .{ .long = i },
        .string => |s| {
            if (!strict) if (numericKeyLong(s.bytes())) |n| return .{ .long = n };
            return .{ .str = s.bytes() };
        },
        .float => |f| if (!strict) {
            if (Value.floatFitsInt(f)) return .{ .long = try (html.Params{ .ctx = ctx, .func = "array_column", .args = args }).int(index, name, 0) };
            return .{ .str = (try ctx.vm.transientFormatted(v)).bytes() };
        },
        .bool => |b| if (!strict) return .{ .long = @intFromBool(b) },
        .object => |o| if (!strict and ctx.vm.hasMethod(o.class_name, "__toString")) return .{ .str = try ctx.vm.objectToString(o) },
        else => {},
    }
    const msg = try std.fmt.allocPrint(ctx.allocator, "array_column(): Argument #{d} (${s}) must be of type string|int|null, {s} given", .{ index + 1, name, phpTypeName(v) });
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("TypeError", msg);
    return error.RuntimeError;
}

fn numericKeyLong(s: []const u8) ?i64 {
    if (!Value.isNumericString(s)) return null;
    const t = std.mem.trim(u8, s, " \t\n\r\x0b\x0c");
    if (std.mem.indexOfAny(u8, t, ".eE") != null) return null;
    return std.fmt.parseInt(i64, t, 10) catch null;
}

// whether the running scope may read a property declared with vis
fn propertyAccessible(ctx: *NativeContext, vis: VM.VisResult) bool {
    if (!vis.declared or vis.visibility == .public) return true;
    const scope = ctx.vm.currentDefiningClass() orelse return false;
    if (vis.visibility == .private) return std.mem.eql(u8, scope, vis.defining_class);
    return ctx.vm.isInstanceOf(scope, vis.defining_class) or ctx.vm.isInstanceOf(vis.defining_class, scope);
}

// array_column_fetch_prop
fn columnFetch(ctx: *NativeContext, data: Value, key: ColumnKey) RuntimeError!?Value {
    switch (data) {
        .array => |a| {
            const k: PhpArray.Key = switch (key) {
                .long => |n| .{ .int = n },
                .str => |s| PhpArray.normalizeKey(.{ .string = Value.String.borrowed(s) }),
                .none => return null,
            };
            if (!a.contains(k)) return null;
            for (a.entries.items) |e| {
                if (e.key.eql(k)) return if (e.ref) |cell| cell.* else e.value;
            }
            return a.get(k);
        },
        .object => |o| {
            var buf: [24]u8 = undefined;
            const name: []const u8 = switch (key) {
                .long => |n| std.fmt.bufPrint(&buf, "{d}", .{n}) catch unreachable,
                .str => |s| s,
                .none => return null,
            };
            const vis = ctx.vm.findPropertyVisibility(o.class_name, name);
            if (propertyAccessible(ctx, vis)) {
                const exists = if (vis.declared and ctx.vm.classDeclaresProperty(o.class_name, name)) o.getForScope(name, vis.defining_class) != .undef else o.properties.contains(name);
                if (exists) return o.getForScope(name, vis.defining_class);
            }
            if (!ctx.vm.hasMethod(o.class_name, "__isset")) return null;
            const name_str = try Value.String.create(ctx.allocator, name);
            defer name_str.release();
            const isset = try ctx.vm.callMethod(o, "__isset", &.{.{ .string = name_str }});
            if (!isset.isTruthy()) return null;
            if (!ctx.vm.hasMethod(o.class_name, "__get")) return null;
            return try ctx.vm.callMethod(o, "__get", &.{.{ .string = name_str }});
        },
        else => return null,
    }
}

fn array_column(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const src = args[0].array;
    const column = try columnKeyParam(ctx, args, 1, "column_key");
    const index = try columnKeyParam(ctx, args, 2, "index_key");
    const result = try ctx.createArray();
    var i: usize = 0;
    while (i < src.entries.items.len) : (i += 1) {
        const e = src.entries.items[i];
        const data = if (e.ref) |cell| cell.* else e.value;
        const colval: Value = if (column == .none) data else (try columnFetch(ctx, data, column)) orelse continue;
        if (index != .none) {
            if (try columnFetch(ctx, data, index)) |keyval| {
                // array_set_zval_key
                const key: ?PhpArray.Key = switch (keyval) {
                    .int => |n| .{ .int = n },
                    .string => |s| PhpArray.normalizeKey(.{ .string = s }),
                    .null => .{ .string = Value.String.borrowed("") },
                    .bool => |b| .{ .int = @intFromBool(b) },
                    .float => |f| .{ .int = if (Value.floatFitsInt(f)) @intFromFloat(@trunc(f)) else 0 },
                    else => null,
                };
                if (key) |k| {
                    try ctx.vm.arraySetOwned(result, k, colval);
                    continue;
                }
                const msg = try std.fmt.allocPrint(ctx.allocator, "Cannot access offset of type {s} on array", .{phpTypeName(keyval)});
                defer ctx.allocator.free(msg);
                try ctx.vm.setPendingException("TypeError", msg);
                return error.RuntimeError;
            }
        }
        if (!try result.appendNew(ctx.allocator, colval)) {
            try ctx.vm.setPendingException("Error", "Cannot add element to the array as the next element is already occupied");
            return error.RuntimeError;
        }
    }
    return NativeResult.borrowed(.{ .array = result });
}
