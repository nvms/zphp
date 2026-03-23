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
};

fn array_push(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .{ .int = 0 };
    const arr = args[0].array;
    for (args[1..]) |val| try arr.append(std.heap.page_allocator, val);
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
    const cb_name = if (callback == .string) callback.string else return Value.null;

    var result = try ctx.createArray();
    for (src.entries.items) |entry| {
        const mapped = try ctx.callFunction(cb_name, &.{entry.value});
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
        const cb_name = if (args[1] == .string) args[1].string else return Value.null;
        for (src.entries.items) |entry| {
            const keep = try ctx.callFunction(cb_name, &.{entry.value});
            if (keep.isTruthy()) try result.set(ctx.allocator, entry.key, entry.value);
        }
    }
    return .{ .array = result };
}

fn native_usort(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return .{ .bool = false };
    const arr = args[0].array;
    const cb_name = if (args[1] == .string) args[1].string else return Value{ .bool = false };

    const items = arr.entries.items;
    var n = items.len;
    while (n > 1) {
        var swapped = false;
        for (0..n - 1) |i| {
            const cmp = try ctx.callFunction(cb_name, &.{ items[i].value, items[i + 1].value });
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
