// the array_diff and array_intersect families, ported from php's
// ext/standard/array.c (php_array_diff, php_array_intersect,
// php_array_diff_key, php_array_intersect_key and array_diff's own fast
// path). the callback variants sort copies of every array with zend_sort and
// walk them side by side, so the order and number of callback calls (which
// scripts can see) follow php's exactly

const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const vm_mod = @import("../runtime/vm.zig");
const callables = @import("../runtime/callables.zig");
const phpTypeName = @import("types.zig").phpTypeName;
const NativeContext = vm_mod.NativeContext;
const NativeResult = vm_mod.NativeResult;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "array_diff", array_diff },
    .{ "array_diff_key", array_diff_key },
    .{ "array_diff_assoc", array_diff_assoc },
    .{ "array_udiff_assoc", array_udiff_assoc },
    .{ "array_diff_ukey", array_diff_ukey },
    .{ "array_diff_uassoc", array_diff_uassoc },
    .{ "array_udiff", array_udiff },
    .{ "array_udiff_uassoc", array_udiff_uassoc },
    .{ "array_intersect", array_intersect },
    .{ "array_intersect_key", array_intersect_key },
    .{ "array_intersect_assoc", array_intersect_assoc },
    .{ "array_uintersect_assoc", array_uintersect_assoc },
    .{ "array_intersect_ukey", array_intersect_ukey },
    .{ "array_intersect_uassoc", array_intersect_uassoc },
    .{ "array_uintersect", array_uintersect },
    .{ "array_uintersect_uassoc", array_uintersect_uassoc },
};

// zend_sort: insertion sort up to 16 elements, otherwise a quicksort whose
// pivot is the median of 3 (or 5 past 1024 elements). php's array sorts and
// these functions all go through it, so a comparison callback sees the same
// pairs in the same order. cmp(a, b) > 0 means a sorts after b
pub fn zendSort(comptime T: type, items: []T, context: anytype) RuntimeError!void {
    var base = items;
    while (true) {
        const n = base.len;
        if (n <= 16) return insertSort(T, base, context);
        const offset = n >> 1;
        if (n >> 10 != 0) {
            const delta = offset >> 1;
            try sort5(T, base, 0, delta, offset, offset + delta, n - 1, context);
        } else {
            try sort3(T, base, 0, offset, n - 1, context);
        }
        std.mem.swap(T, &base[1], &base[offset]);
        const pivot: usize = 1;
        var i: usize = pivot + 1;
        var j: usize = n - 1;
        partition: while (true) {
            while (try context.cmp(base[pivot], base[i]) > 0) {
                i += 1;
                if (i == j) break :partition;
            }
            j -= 1;
            if (j == i) break :partition;
            while (try context.cmp(base[j], base[pivot]) > 0) {
                j -= 1;
                if (j == i) break :partition;
            }
            std.mem.swap(T, &base[i], &base[j]);
            i += 1;
            if (i == j) break :partition;
        }
        std.mem.swap(T, &base[pivot], &base[i - 1]);
        // recurse into the smaller side, loop on the larger
        if (i - 1 < n - i) {
            try zendSort(T, base[0 .. i - 1], context);
            base = base[i..];
        } else {
            try zendSort(T, base[i..], context);
            base = base[0 .. i - 1];
        }
    }
}

fn sort2(comptime T: type, s: []T, a: usize, b: usize, context: anytype) RuntimeError!void {
    if (try context.cmp(s[a], s[b]) > 0) std.mem.swap(T, &s[a], &s[b]);
}

fn sort3(comptime T: type, s: []T, a: usize, b: usize, c: usize, context: anytype) RuntimeError!void {
    if (!(try context.cmp(s[a], s[b]) > 0)) {
        if (!(try context.cmp(s[b], s[c]) > 0)) return;
        std.mem.swap(T, &s[b], &s[c]);
        if (try context.cmp(s[a], s[b]) > 0) std.mem.swap(T, &s[a], &s[b]);
        return;
    }
    if (!(try context.cmp(s[c], s[b]) > 0)) {
        std.mem.swap(T, &s[a], &s[c]);
        return;
    }
    std.mem.swap(T, &s[a], &s[b]);
    if (try context.cmp(s[b], s[c]) > 0) std.mem.swap(T, &s[b], &s[c]);
}

fn sort4(comptime T: type, s: []T, a: usize, b: usize, c: usize, d: usize, context: anytype) RuntimeError!void {
    try sort3(T, s, a, b, c, context);
    if (try context.cmp(s[c], s[d]) > 0) {
        std.mem.swap(T, &s[c], &s[d]);
        if (try context.cmp(s[b], s[c]) > 0) {
            std.mem.swap(T, &s[b], &s[c]);
            if (try context.cmp(s[a], s[b]) > 0) std.mem.swap(T, &s[a], &s[b]);
        }
    }
}

fn sort5(comptime T: type, s: []T, a: usize, b: usize, c: usize, d: usize, e: usize, context: anytype) RuntimeError!void {
    try sort4(T, s, a, b, c, d, context);
    if (try context.cmp(s[d], s[e]) > 0) {
        std.mem.swap(T, &s[d], &s[e]);
        if (try context.cmp(s[c], s[d]) > 0) {
            std.mem.swap(T, &s[c], &s[d]);
            if (try context.cmp(s[b], s[c]) > 0) {
                std.mem.swap(T, &s[b], &s[c]);
                if (try context.cmp(s[a], s[b]) > 0) std.mem.swap(T, &s[a], &s[b]);
            }
        }
    }
}

// zend_insert_sort. past the first six elements it probes two slots at a
// time, which changes which pairs get compared
fn insertSort(comptime T: type, s: []T, context: anytype) RuntimeError!void {
    switch (s.len) {
        0, 1 => {},
        2 => try sort2(T, s, 0, 1, context),
        3 => try sort3(T, s, 0, 1, 2, context),
        4 => try sort4(T, s, 0, 1, 2, 3, context),
        5 => try sort5(T, s, 0, 1, 2, 3, 4, context),
        else => {
            var i: usize = 1;
            while (i < 6) : (i += 1) {
                var j = i - 1;
                if (!(try context.cmp(s[j], s[i]) > 0)) continue;
                while (j != 0) {
                    j -= 1;
                    if (!(try context.cmp(s[j], s[i]) > 0)) {
                        j += 1;
                        break;
                    }
                }
                rotateInto(T, s, j, i);
            }
            while (i < s.len) : (i += 1) {
                var j = i - 1;
                if (!(try context.cmp(s[j], s[i]) > 0)) continue;
                while (true) {
                    j -= 2;
                    if (!(try context.cmp(s[j], s[i]) > 0)) {
                        j += 1;
                        if (!(try context.cmp(s[j], s[i]) > 0)) j += 1;
                        break;
                    }
                    if (j == 0) break;
                    if (j == 1) {
                        j -= 1;
                        if (try context.cmp(s[i], s[j]) > 0) j += 1;
                        break;
                    }
                }
                rotateInto(T, s, j, i);
            }
        },
    }
}

// moves s[i] down to s[j], shifting the ones between up, as php's chain of
// swaps does
fn rotateInto(comptime T: type, s: []T, j: usize, i: usize) void {
    if (j >= i) return;
    const tmp = s[i];
    std.mem.copyBackwards(T, s[j + 1 .. i + 1], s[j..i]);
    s[j] = tmp;
}

// one element of a sorted copy: php's Bucket. idx is the element's position
// in its array, for deleting it from the result
const Bucket = struct {
    key: PhpArray.Key,
    val: Value,
    idx: usize,
};

fn entryValue(entry: PhpArray.Entry) Value {
    return if (entry.ref) |cell| cell.* else entry.value;
}

fn keyValue(key: PhpArray.Key) Value {
    return switch (key) {
        .int => |i| .{ .int = i },
        .string => |s| .{ .string = s },
    };
}

fn order(a: []const u8, b: []const u8) i32 {
    return switch (std.mem.order(u8, a, b)) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

// zval_get_tmp_string: a value's string form, owned only when converting it
// made a new string. arrays warn, objects run __toString
const TmpString = struct {
    bytes: []const u8,
    owned: ?Value.String = null,
    heap: ?[]u8 = null,

    fn release(self: TmpString, ctx: *NativeContext) void {
        if (self.owned) |s| s.release();
        if (self.heap) |h| ctx.allocator.free(h);
    }
};

// closures travel as strings with this prefix
fn isClosure(v: Value) bool {
    return v == .string and std.mem.startsWith(u8, v.string.bytes(), "__closure_");
}

fn tmpString(ctx: *NativeContext, v: Value, buf: []u8) RuntimeError!TmpString {
    switch (v) {
        .string => |s| {
            if (isClosure(v)) {
                try ctx.vm.setPendingException("Error", "Object of class Closure could not be converted to string");
                return error.RuntimeError;
            }
            return .{ .bytes = s.bytes() };
        },
        .int => |i| return .{ .bytes = std.fmt.bufPrint(buf, "{d}", .{i}) catch unreachable },
        .null, .undef => return .{ .bytes = "" },
        .bool => |b| return .{ .bytes = if (b) "1" else "" },
        .array => {
            try ctx.vm.emitWarning("Array to string conversion");
            return .{ .bytes = "Array" };
        },
        .object => |o| {
            const s = try ctx.vm.objectString(o);
            return .{ .bytes = s.bytes(), .owned = s };
        },
        else => {
            var fba = std.heap.FixedBufferAllocator.init(buf);
            var list: std.ArrayListUnmanaged(u8) = .empty;
            if (v.format(&list, fba.allocator())) |_| return .{ .bytes = list.items } else |_| {}
            var heap: std.ArrayListUnmanaged(u8) = .empty;
            errdefer heap.deinit(ctx.allocator);
            try v.format(&heap, ctx.allocator);
            const owned = try heap.toOwnedSlice(ctx.allocator);
            return .{ .bytes = owned, .heap = owned };
        },
    }
}

// string_compare_function
fn stringCompare(ctx: *NativeContext, a: Value, b: Value) RuntimeError!i32 {
    if (a == .string and b == .string and !isClosure(a) and !isClosure(b)) return order(a.string.bytes(), b.string.bytes());
    var buf_a: [128]u8 = undefined;
    var buf_b: [128]u8 = undefined;
    const sa = try tmpString(ctx, a, &buf_a);
    defer sa.release(ctx);
    const sb = try tmpString(ctx, b, &buf_b);
    defer sb.release(ctx);
    return order(sa.bytes, sb.bytes);
}

// php_array_key_compare_string: integer keys compare as their decimal text
fn keyStringCompare(a: PhpArray.Key, b: PhpArray.Key) i32 {
    var buf_a: [24]u8 = undefined;
    var buf_b: [24]u8 = undefined;
    const sa = switch (a) {
        .string => |s| s.bytes(),
        .int => |i| std.fmt.bufPrint(&buf_a, "{d}", .{i}) catch unreachable,
    };
    const sb = switch (b) {
        .string => |s| s.bytes(),
        .int => |i| std.fmt.bufPrint(&buf_b, "{d}", .{i}) catch unreachable,
    };
    return order(sa, sb);
}

fn normalize(n: i64) i32 {
    return if (n > 0) 1 else if (n < 0) -1 else 0;
}

// the state php keeps in BG(user_compare_fci): the callback the user
// comparisons call is whichever was installed last, which matters where php
// forgets to switch back (array_uintersect_uassoc with three arrays or more)
const Compare = struct {
    ctx: *NativeContext,
    name: []const u8,
    current: Value = .null,
    deprecation_thrown: bool = false,

    // php_array_user_compare_unstable and php_array_user_key_compare_unstable:
    // a bool result is deprecated, and false asks again with the operands
    // swapped
    fn user(self: *Compare, a: Value, b: Value) RuntimeError!i32 {
        const ret = try self.ctx.invokeCallable(self.current, &.{ a, b });
        if (ret == .bool) {
            if (!self.deprecation_thrown) {
                self.deprecation_thrown = true;
                const msg = try std.fmt.allocPrint(self.ctx.allocator, "{s}(): Returning bool from comparison function is deprecated, return an integer less than, equal to, or greater than zero", .{self.name});
                defer self.ctx.allocator.free(msg);
                try self.ctx.vm.raiseError(8192, msg);
                if (self.ctx.vm.pending_exception != null) return error.RuntimeError;
            }
            if (!ret.bool) {
                const swapped = try self.ctx.invokeCallable(self.current, &.{ b, a });
                return -normalize(Value.toInt(swapped));
            }
        }
        return normalize(Value.toInt(ret));
    }

    fn data(self: *Compare, comptime kind: DataCmp, a: Bucket, b: Bucket) RuntimeError!i32 {
        return switch (kind) {
            .internal => stringCompare(self.ctx, a.val, b.val),
            .user => self.user(a.val, b.val),
        };
    }

    fn key(self: *Compare, comptime kind: KeyCmp, a: Bucket, b: Bucket) RuntimeError!i32 {
        return switch (kind) {
            .internal => keyStringCompare(a.key, b.key),
            .user => self.user(keyValue(a.key), keyValue(b.key)),
        };
    }
};

const DataCmp = enum { internal, user };
const KeyCmp = enum { internal, user };
const Behavior = enum { normal, key, assoc };

fn SortBy(comptime by_key: bool, comptime kind: anytype) type {
    return struct {
        cmp_state: *Compare,
        pub fn cmp(self: @This(), a: Bucket, b: Bucket) RuntimeError!i32 {
            return if (by_key) self.cmp_state.key(kind, a, b) else self.cmp_state.data(kind, a, b);
        }
    };
}

fn throwArgCount(ctx: *NativeContext, name: []const u8, min: usize, given: usize) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, "{s}() expects at least {d} argument{s}, {d} given", .{ name, min, if (min == 1) "" else "s", given });
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("ArgumentCountError", msg);
    return error.RuntimeError;
}

// zend_argument_type_error: only the first argument has a name, the rest are
// the variadic tail
fn throwNotArray(ctx: *NativeContext, name: []const u8, pos: usize, got: Value) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): Argument #{d}{s} must be of type array, {s} given", .{ name, pos, if (pos == 1) " ($array)" else "", phpTypeName(got) });
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("TypeError", msg);
    return error.RuntimeError;
}

// zend_parse_parameters with "+", "+f" or "+ff": at least one value, then
// the callbacks at the end, checked before any argument's type. answers the
// leading arguments, the arrays to be
fn parseArgs(ctx: *NativeContext, name: []const u8, args: []const Value, comptime callbacks: usize) RuntimeError![]const Value {
    if (args.len < 1 + callbacks) return throwArgCount(ctx, name, 1 + callbacks, args.len);
    const split = args.len - callbacks;
    for (args[split..], split..) |cb, i| {
        switch (try callables.resolveCallback(ctx.vm, cb, .{})) {
            .callee => {},
            .failure => |failure| {
                var buf: std.ArrayListUnmanaged(u8) = .empty;
                defer buf.deinit(ctx.allocator);
                try buf.print(ctx.allocator, "{s}(): Argument #{d} must be a valid callback, ", .{ name, i + 1 });
                try callables.writeReason(failure, &buf, ctx.allocator);
                try ctx.vm.setPendingException("TypeError", buf.items);
                return error.RuntimeError;
            },
        }
    }
    return args[0..split];
}

fn checkArrays(ctx: *NativeContext, name: []const u8, arrays: []const Value) RuntimeError!void {
    for (arrays, 1..) |arg, pos| if (arg != .array) return throwNotArray(ctx, name, pos, arg);
}

// finds an array's element by key the way a hash lookup would. arrays whose
// integer keys are not their positions get an index built on first need
const Lookup = struct {
    arr: *PhpArray,
    ints: ?std.AutoHashMapUnmanaged(i64, usize) = null,

    fn deinit(self: *Lookup, ctx: *NativeContext) void {
        if (self.ints) |*m| m.deinit(ctx.allocator);
    }

    fn find(self: *Lookup, ctx: *NativeContext, key: PhpArray.Key) RuntimeError!?Value {
        const items = self.arr.entries.items;
        switch (key) {
            .string => |s| {
                const idx = self.arr.string_index.get(s.bytes()) orelse return null;
                return entryValue(items[idx]);
            },
            .int => |n| {
                if (n >= 0 and n < items.len) {
                    const e = items[@intCast(n)];
                    if (e.key == .int and e.key.int == n) return entryValue(e);
                }
                if (!self.arr.has_int_keys) return null;
                if (items.len <= 8) {
                    for (items) |e| if (e.key == .int and e.key.int == n) return entryValue(e);
                    return null;
                }
                if (self.ints == null) {
                    var m: std.AutoHashMapUnmanaged(i64, usize) = .{};
                    errdefer m.deinit(ctx.allocator);
                    for (items, 0..) |e, i| if (e.key == .int) try m.put(ctx.allocator, e.key.int, i);
                    self.ints = m;
                }
                const idx = self.ints.?.get(n) orelse return null;
                return entryValue(items[idx]);
            },
        }
    }
};

const KeyData = enum { none, internal, user };

// php_array_diff_key and php_array_intersect_key: a hash lookup of each key
// of the first array in the others, then a comparison of the two values
// (none for the _key functions, value first)
fn byKey(ctx: *NativeContext, name: []const u8, args: []const Value, comptime data: KeyData, comptime intersect: bool) RuntimeError!NativeResult {
    const arrays = try parseArgs(ctx, name, args, if (data == .user) 1 else 0);
    const callback: Value = if (data == .user) args[args.len - 1] else .null;
    try checkArrays(ctx, name, arrays);
    const src = arrays[0].array;
    const n = src.entries.items.len;

    const keep = try ctx.allocator.alloc(bool, n);
    defer ctx.allocator.free(keep);
    const lookups = try ctx.allocator.alloc(Lookup, arrays.len - 1);
    defer {
        for (lookups) |*l| l.deinit(ctx);
        ctx.allocator.free(lookups);
    }
    for (lookups, arrays[1..]) |*l, a| l.* = .{ .arr = a.array };

    var i: usize = 0;
    while (i < n) : (i += 1) {
        // a callback may change the array; php walks its own hash in place
        if (i >= src.entries.items.len) {
            @memset(keep[i..], false);
            break;
        }
        const entry = src.entries.items[i];
        const val = entryValue(entry);
        var ok = true;
        for (lookups) |*l| {
            const found = try l.find(ctx, entry.key);
            const other = found orelse {
                if (intersect) {
                    ok = false;
                    break;
                }
                continue;
            };
            const same = switch (data) {
                .none => true,
                .internal => try stringCompare(ctx, val, other) == 0,
                .user => normalize(Value.toInt(try ctx.invokeCallable(callback, &.{ val, other }))) == 0,
            };
            if (intersect and !same) {
                ok = false;
                break;
            }
            if (!intersect and same) {
                ok = false;
                break;
            }
        }
        keep[i] = ok;
    }
    const result = try ctx.vm.copyKeptEntries(src, keep[0..@min(n, src.entries.items.len)], false);
    return NativeResult.borrowed(.{ .array = result });
}

// the sorted copies of every array, built and sorted in argument order so a
// later argument's type error comes after the earlier ones' callbacks
fn sortedLists(
    ctx: *NativeContext,
    name: []const u8,
    arrays: []const Value,
    cmp_state: *Compare,
    comptime by_key: bool,
    comptime kind: anytype,
) RuntimeError![][]Bucket {
    const lists = try ctx.allocator.alloc([]Bucket, arrays.len);
    var built: usize = 0;
    errdefer {
        for (lists[0..built]) |l| ctx.allocator.free(l);
        ctx.allocator.free(lists);
    }
    for (arrays, 0..) |arg, i| {
        if (arg != .array) return throwNotArray(ctx, name, i + 1, arg);
        const items = arg.array.entries.items;
        const list = try ctx.allocator.alloc(Bucket, items.len);
        for (items, 0..) |e, idx| list[idx] = .{ .key = e.key, .val = entryValue(e), .idx = idx };
        lists[i] = list;
        built += 1;
        if (list.len > 1) try zendSort(Bucket, list, SortBy(by_key, kind){ .cmp_state = cmp_state });
    }
    return lists;
}

fn freeLists(ctx: *NativeContext, lists: [][]Bucket) void {
    for (lists) |l| ctx.allocator.free(l);
    ctx.allocator.free(lists);
}

// php_array_diff, for every variant but array_diff itself and the ones by
// key lookup
fn sortedDiff(
    ctx: *NativeContext,
    name: []const u8,
    args: []const Value,
    comptime behavior: Behavior,
    comptime data_cmp: DataCmp,
    comptime key_cmp: KeyCmp,
) RuntimeError!NativeResult {
    const callbacks = @as(usize, @intFromBool(data_cmp == .user and behavior != .key)) + @intFromBool(key_cmp == .user and behavior != .normal);
    const arrays = try parseArgs(ctx, name, args, callbacks);
    // the data callback comes first when there are two
    const data_cb: Value = if (data_cmp == .user) args[arrays.len] else .null;
    const key_cb: Value = if (key_cmp == .user) args[args.len - 1] else .null;

    var cmp: Compare = .{ .ctx = ctx, .name = name };
    if (behavior == .normal and data_cmp == .user) cmp.current = data_cb;
    if (behavior != .normal and key_cmp == .user) cmp.current = key_cb;

    const lists = if (behavior == .normal)
        try sortedLists(ctx, name, arrays, &cmp, false, data_cmp)
    else
        try sortedLists(ctx, name, arrays, &cmp, true, key_cmp);
    defer freeLists(ctx, lists);

    const src = arrays[0].array;
    const keep = try ctx.allocator.alloc(bool, src.entries.items.len);
    defer ctx.allocator.free(keep);
    @memset(keep, true);
    const ptrs = try ctx.allocator.alloc(usize, arrays.len);
    defer ctx.allocator.free(ptrs);
    @memset(ptrs, 0);

    const l0 = lists[0];
    walk: while (ptrs[0] < l0.len) {
        if (behavior != .normal and key_cmp == .user) cmp.current = key_cb;
        var c: i32 = 1;
        var i: usize = 1;
        while (i < arrays.len) : (i += 1) {
            const li = lists[i];
            var ptr = ptrs[i];
            if (behavior == .normal) {
                while (ptrs[i] < li.len) {
                    c = try cmp.data(data_cmp, l0[ptrs[0]], li[ptrs[i]]);
                    if (c <= 0) break;
                    ptrs[i] += 1;
                }
            } else {
                while (ptr < li.len) {
                    c = try cmp.key(key_cmp, l0[ptrs[0]], li[ptr]);
                    if (c == 0) break;
                    ptr += 1;
                }
            }
            if (c == 0) {
                if (behavior == .normal) {
                    if (ptrs[i] < li.len) ptrs[i] += 1;
                    break;
                } else if (behavior == .assoc) {
                    if (ptr < li.len) {
                        if (data_cmp == .user) cmp.current = data_cb;
                        if (try cmp.data(data_cmp, l0[ptrs[0]], li[ptr]) != 0) {
                            c = -1;
                            if (key_cmp == .user) cmp.current = key_cb;
                        } else break;
                    }
                } else break;
            }
        }
        if (c == 0) {
            // in another array: drop it, and every equal value after it
            while (true) {
                keep[l0[ptrs[0]].idx] = false;
                ptrs[0] += 1;
                if (ptrs[0] == l0.len) break :walk;
                if (behavior != .normal) break;
                if (try cmp.data(data_cmp, l0[ptrs[0] - 1], l0[ptrs[0]]) != 0) break;
            }
        } else {
            while (true) {
                ptrs[0] += 1;
                if (ptrs[0] == l0.len) break :walk;
                if (behavior != .normal) break;
                if (try cmp.data(data_cmp, l0[ptrs[0] - 1], l0[ptrs[0]]) != 0) break;
            }
        }
    }
    return keptResult(ctx, src, keep);
}

// the result of php's dup of the first array with entries deleted: the next
// free index stays the first array's
fn keptResult(ctx: *NativeContext, src: *PhpArray, keep: []const bool) RuntimeError!NativeResult {
    // a callback can shrink the array php had already copied
    const n = @min(keep.len, src.entries.items.len);
    const result = try ctx.vm.copyKeptEntries(src, keep[0..n], true);
    return NativeResult.borrowed(.{ .array = result });
}

// php_array_intersect
fn sortedIntersect(
    ctx: *NativeContext,
    name: []const u8,
    args: []const Value,
    comptime behavior: Behavior,
    comptime data_cmp: DataCmp,
    comptime key_cmp: KeyCmp,
) RuntimeError!NativeResult {
    const callbacks = @as(usize, @intFromBool(data_cmp == .user and behavior != .key)) + @intFromBool(key_cmp == .user and behavior != .normal);
    const arrays = try parseArgs(ctx, name, args, callbacks);
    const data_cb: Value = if (data_cmp == .user) args[arrays.len] else .null;
    const key_cb: Value = if (key_cmp == .user) args[args.len - 1] else .null;

    var cmp: Compare = .{ .ctx = ctx, .name = name };
    if (behavior == .normal and data_cmp == .user) cmp.current = data_cb;
    if (behavior != .normal and key_cmp == .user) cmp.current = key_cb;

    const lists = if (behavior == .normal)
        try sortedLists(ctx, name, arrays, &cmp, false, data_cmp)
    else
        try sortedLists(ctx, name, arrays, &cmp, true, key_cmp);
    defer freeLists(ctx, lists);

    const src = arrays[0].array;
    const keep = try ctx.allocator.alloc(bool, src.entries.items.len);
    defer ctx.allocator.free(keep);
    @memset(keep, true);
    const ptrs = try ctx.allocator.alloc(usize, arrays.len);
    defer ctx.allocator.free(ptrs);
    @memset(ptrs, 0);

    const l0 = lists[0];
    var c: i32 = 0;
    walk: while (ptrs[0] < l0.len) {
        if (behavior != .normal and key_cmp == .user) cmp.current = key_cb;
        var i: usize = 1;
        while (i < arrays.len) : (i += 1) {
            const li = lists[i];
            if (behavior == .normal) {
                while (ptrs[i] < li.len) {
                    c = try cmp.data(data_cmp, l0[ptrs[0]], li[ptrs[i]]);
                    if (c <= 0) break;
                    ptrs[i] += 1;
                }
            } else {
                while (ptrs[i] < li.len) {
                    c = try cmp.key(key_cmp, l0[ptrs[0]], li[ptrs[i]]);
                    if (c <= 0) break;
                    ptrs[i] += 1;
                }
                if (c == 0 and ptrs[i] < li.len and behavior == .assoc) {
                    if (data_cmp == .user) cmp.current = data_cb;
                    // on a match php leaves the data callback installed for
                    // the next array's key comparisons
                    if (try cmp.data(data_cmp, l0[ptrs[0]], li[ptrs[i]]) != 0) {
                        c = 1;
                        if (key_cmp == .user) cmp.current = key_cb;
                    }
                }
            }
            if (ptrs[i] == li.len) {
                // this array has run out: nothing left of the first is in it
                while (ptrs[0] < l0.len) : (ptrs[0] += 1) keep[l0[ptrs[0]].idx] = false;
                break :walk;
            }
            if (c != 0) break;
            ptrs[i] += 1;
        }
        if (c != 0) {
            // not in every array: drop it and everything below ptrs[i]
            while (true) {
                keep[l0[ptrs[0]].idx] = false;
                ptrs[0] += 1;
                if (ptrs[0] == l0.len) break :walk;
                if (behavior != .normal) break;
                if (try cmp.data(data_cmp, l0[ptrs[0]], lists[i][ptrs[i]]) >= 0) break;
            }
        } else {
            while (true) {
                ptrs[0] += 1;
                if (ptrs[0] == l0.len) break :walk;
                if (behavior != .normal) break;
                if (try cmp.data(data_cmp, l0[ptrs[0] - 1], l0[ptrs[0]]) != 0) break;
            }
        }
    }
    return keptResult(ctx, src, keep);
}

// array_diff has its own path: the string forms of every other array's
// values go into a set, and the first array keeps what isn't in it
fn array_diff(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const name = "array_diff";
    if (args.len < 1) return throwArgCount(ctx, name, 1, args.len);
    if (args[0] != .array) return throwNotArray(ctx, name, 1, args[0]);
    const src = args[0].array;
    const n = src.entries.items.len;
    if (n == 0) {
        try checkArrays(ctx, name, args);
        return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    }
    var buf: [128]u8 = undefined;
    var other_buf: [128]u8 = undefined;
    if (n == 1) {
        const search = try tmpString(ctx, entryValue(src.entries.items[0]), &buf);
        defer search.release(ctx);
        var found = false;
        for (args[1..], 2..) |arg, pos| {
            if (arg != .array) return throwNotArray(ctx, name, pos, arg);
            if (found) continue;
            for (arg.array.entries.items) |e| {
                const s = try tmpString(ctx, entryValue(e), &other_buf);
                defer s.release(ctx);
                if (std.mem.eql(u8, search.bytes, s.bytes)) {
                    found = true;
                    break;
                }
            }
        }
        if (found) return NativeResult.borrowed(.{ .array = try ctx.createArray() });
        return NativeResult.borrowed(args[0]);
    }

    var total: usize = 0;
    for (args[1..], 2..) |arg, pos| {
        if (arg != .array) return throwNotArray(ctx, name, pos, arg);
        total += arg.array.entries.items.len;
    }
    if (total == 0) return NativeResult.borrowed(args[0]);

    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();
    var exclude: std.StringHashMapUnmanaged(void) = .{};
    defer exclude.deinit(ctx.allocator);
    try exclude.ensureTotalCapacity(ctx.allocator, @intCast(total));
    for (args[1..]) |arg| {
        for (arg.array.entries.items) |e| {
            const v = entryValue(e);
            if (v == .string and !isClosure(v)) {
                exclude.putAssumeCapacity(v.string.bytes(), {});
                continue;
            }
            const s = try tmpString(ctx, v, &other_buf);
            defer s.release(ctx);
            exclude.putAssumeCapacity(try arena.allocator().dupe(u8, s.bytes), {});
        }
    }

    const keep = try ctx.allocator.alloc(bool, n);
    defer ctx.allocator.free(keep);
    for (src.entries.items, keep) |e, *k| {
        const s = try tmpString(ctx, entryValue(e), &buf);
        defer s.release(ctx);
        k.* = !exclude.contains(s.bytes);
    }
    const result = try ctx.vm.copyKeptEntries(src, keep, false);
    return NativeResult.borrowed(.{ .array = result });
}

fn array_diff_key(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return byKey(ctx, "array_diff_key", args, .none, false);
}

fn array_diff_assoc(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return byKey(ctx, "array_diff_assoc", args, .internal, false);
}

fn array_udiff_assoc(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return byKey(ctx, "array_udiff_assoc", args, .user, false);
}

fn array_intersect_key(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return byKey(ctx, "array_intersect_key", args, .none, true);
}

fn array_intersect_assoc(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return byKey(ctx, "array_intersect_assoc", args, .internal, true);
}

fn array_uintersect_assoc(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return byKey(ctx, "array_uintersect_assoc", args, .user, true);
}

fn array_diff_ukey(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return sortedDiff(ctx, "array_diff_ukey", args, .key, .internal, .user);
}

fn array_diff_uassoc(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return sortedDiff(ctx, "array_diff_uassoc", args, .assoc, .internal, .user);
}

fn array_udiff(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return sortedDiff(ctx, "array_udiff", args, .normal, .user, .internal);
}

fn array_udiff_uassoc(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return sortedDiff(ctx, "array_udiff_uassoc", args, .assoc, .user, .user);
}

fn array_intersect(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return sortedIntersect(ctx, "array_intersect", args, .normal, .internal, .internal);
}

fn array_intersect_ukey(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return sortedIntersect(ctx, "array_intersect_ukey", args, .key, .internal, .user);
}

fn array_intersect_uassoc(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return sortedIntersect(ctx, "array_intersect_uassoc", args, .assoc, .internal, .user);
}

fn array_uintersect(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return sortedIntersect(ctx, "array_uintersect", args, .normal, .user, .internal);
}

fn array_uintersect_uassoc(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return sortedIntersect(ctx, "array_uintersect_uassoc", args, .assoc, .user, .user);
}

test "zendSort orders like php's hybrid sort" {
    const Ctx = struct {
        pub fn cmp(_: @This(), a: i64, b: i64) RuntimeError!i32 {
            return if (a > b) 1 else if (a < b) -1 else 0;
        }
    };
    var prng = std.Random.DefaultPrng.init(42);
    const rand = prng.random();
    for ([_]usize{ 0, 1, 2, 3, 4, 5, 6, 7, 15, 16, 17, 100, 1500 }) |len| {
        const items = try std.testing.allocator.alloc(i64, len);
        defer std.testing.allocator.free(items);
        for (items) |*x| x.* = rand.intRangeAtMost(i64, -50, 50);
        try zendSort(i64, items, Ctx{});
        if (len > 1) for (1..len) |k| try std.testing.expect(items[k - 1] <= items[k]);
    }
}
