// php's array sorts, ported from ext/standard/array.c: sort, rsort, asort,
// arsort, ksort, krsort, natsort, natcasesort, usort, uasort, uksort and
// array_multisort. every one runs zend_sort over the array's buckets with
// php's comparison functions and the original position as the tie-breaker,
// so mixed-type arrays and comparison callbacks see what php does

const std = @import("std");
const value_mod = @import("../runtime/value.zig");
const class_names = @import("../runtime/class_names.zig");
const Value = value_mod.Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const vm_mod = @import("../runtime/vm.zig");
const array_diff = @import("array_diff.zig");
const html = @import("html.zig");
const phpTypeName = @import("types.zig").phpTypeName;
const NativeContext = vm_mod.NativeContext;
const NativeResult = vm_mod.NativeResult;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "sort", native_sort },
    .{ "rsort", native_rsort },
    .{ "asort", native_asort },
    .{ "arsort", native_arsort },
    .{ "ksort", native_ksort },
    .{ "krsort", native_krsort },
    .{ "natsort", native_natsort },
    .{ "natcasesort", native_natcasesort },
    .{ "usort", native_usort },
    .{ "uasort", native_uasort },
    .{ "uksort", native_uksort },
    .{ "array_multisort", native_array_multisort },
};

const sort_regular = 0;
const sort_numeric = 1;
const sort_string = 2;
const sort_desc = 3;
const sort_asc = 4;
const sort_locale_string = 5;
const sort_natural = 6;
const sort_flag_case = 8;

pub const Kind = enum { regular, numeric, string, string_case, natural, natural_case, locale };

// php_get_data_compare_func and php_get_key_compare_func pick by these
pub fn kindFromFlags(flags: i64) Kind {
    const case = flags & sort_flag_case != 0;
    return switch (flags & ~@as(i64, sort_flag_case)) {
        sort_numeric => .numeric,
        sort_string => if (case) .string_case else .string,
        sort_natural => if (case) .natural_case else .natural,
        sort_locale_string => .locale,
        else => .regular,
    };
}

fn entryValue(entry: PhpArray.Entry) Value {
    return if (entry.ref) |cell| cell.* else entry.value;
}

fn keyValue(key: PhpArray.Key) Value {
    return switch (key) {
        .int => |i| .{ .int = i },
        .string => |s| .{ .string = s },
    };
}

fn sign(n: anytype) i32 {
    return if (n > 0) 1 else if (n < 0) -1 else 0;
}

fn threeWay(a: f64, b: f64) i32 {
    return if (a == b) 0 else if (a < b) -1 else 1;
}

// zend_binary_strcmp / zend_binary_strcasecmp
fn binaryCompare(a: []const u8, b: []const u8, fold: bool) i32 {
    const n = @min(a.len, b.len);
    for (a[0..n], b[0..n]) |x, y| {
        const cx = if (fold) std.ascii.toLower(x) else x;
        const cy = if (fold) std.ascii.toLower(y) else y;
        if (cx != cy) return if (cx < cy) -1 else 1;
    }
    return sign(@as(i64, @intCast(a.len)) - @as(i64, @intCast(b.len)));
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isSpace(c: u8) bool {
    return c == ' ' or (c >= '\t' and c <= '\r');
}

// php's strnatcmp_ex (ext/standard/strnatcmp.c)
pub fn strnatcmp(a: []const u8, b: []const u8, fold_case: bool) i32 {
    if (a.len == 0 or b.len == 0) return if (a.len == b.len) 0 else if (a.len > b.len) 1 else -1;
    // the strings are c strings in php: a read at the end sees the terminator
    const at = struct {
        fn f(s: []const u8, i: usize) u8 {
            return if (i < s.len) s[i] else 0;
        }
    }.f;
    var ap: usize = 0;
    var bp: usize = 0;
    var ca = a[0];
    var cb = b[0];
    while (ca == '0' and ap + 1 < a.len and isDigit(a[ap + 1])) {
        ap += 1;
        ca = a[ap];
    }
    while (cb == '0' and bp + 1 < b.len and isDigit(b[bp + 1])) {
        bp += 1;
        cb = b[bp];
    }
    while (true) {
        while (isSpace(ca)) {
            ap += 1;
            ca = at(a, ap);
        }
        while (isSpace(cb)) {
            bp += 1;
            cb = at(b, bp);
        }
        if (isDigit(ca) and isDigit(cb)) {
            const fractional = ca == '0' or cb == '0';
            const result = if (fractional) compareLeft(a, &ap, b, &bp) else compareRight(a, &ap, b, &bp);
            if (result != 0) return result;
            if (ap == a.len and bp == b.len) return 0;
            if (ap == a.len) return -1;
            if (bp == b.len) return 1;
            ca = a[ap];
            cb = b[bp];
        }
        if (fold_case) {
            ca = std.ascii.toUpper(ca);
            cb = std.ascii.toUpper(cb);
        }
        if (ca < cb) return -1;
        if (ca > cb) return 1;
        ap += 1;
        bp += 1;
        if (ap >= a.len and bp >= b.len) return 0;
        if (ap >= a.len) return -1;
        if (bp >= b.len) return 1;
        ca = a[ap];
        cb = b[bp];
    }
}

fn digitAt(s: []const u8, i: usize) bool {
    return i < s.len and isDigit(s[i]);
}

// the longest run of digits wins; otherwise the first difference decides
fn compareRight(a: []const u8, ap: *usize, b: []const u8, bp: *usize) i32 {
    var bias: i32 = 0;
    while (true) : ({
        ap.* += 1;
        bp.* += 1;
    }) {
        const da = digitAt(a, ap.*);
        const db = digitAt(b, bp.*);
        if (!da and !db) return bias;
        if (!da) return -1;
        if (!db) return 1;
        if (a[ap.*] < b[bp.*]) {
            if (bias == 0) bias = -1;
        } else if (a[ap.*] > b[bp.*]) {
            if (bias == 0) bias = 1;
        }
    }
}

fn compareLeft(a: []const u8, ap: *usize, b: []const u8, bp: *usize) i32 {
    while (true) : ({
        ap.* += 1;
        bp.* += 1;
    }) {
        const da = digitAt(a, ap.*);
        const db = digitAt(b, bp.*);
        if (!da and !db) return 0;
        if (!da) return -1;
        if (!db) return 1;
        if (a[ap.*] < b[bp.*]) return -1;
        if (a[ap.*] > b[bp.*]) return 1;
    }
}

// zval_get_double: an object without a numeric cast warns and counts as 1
fn toDouble(ctx: *NativeContext, v: Value) RuntimeError!f64 {
    return switch (v) {
        .array => |arr| if (arr.entries.items.len > 0) 1.0 else 0.0,
        .object => |o| {
            if (value_mod.nativeCast(o, .number)) |n| return Value.toFloat(n);
            const msg = try std.fmt.allocPrint(ctx.allocator, "Object of class {s} could not be converted to float", .{class_names.display(o.class_name)});
            defer ctx.allocator.free(msg);
            try ctx.vm.emitWarning(msg);
            return 1.0;
        },
        else => Value.toFloat(v),
    };
}

fn isEnum(ctx: *NativeContext, v: Value) bool {
    if (v != .object) return false;
    const def = ctx.vm.classes.getPtr(v.object.class_name) orelse return false;
    return def.is_enum;
}

// php_array_data_compare_unstable_i and friends: two values under a sort kind
pub fn compareValues(ctx: *NativeContext, kind: Kind, a: Value, b: Value) RuntimeError!i32 {
    switch (kind) {
        .regular => {
            const result = sign(try ctx.vm.compareWithStringable(a, b));
            // enums are uncomparable; php groups equal cases and moves the
            // rest to the end so array_unique still works
            if (result == 1 and isEnum(ctx, b)) {
                if (isEnum(ctx, a)) return if (a.object == b.object) 0 else if (a.object.id < b.object.id) -1 else 1;
                return -1;
            }
            return result;
        },
        .numeric => {
            const da = try toDouble(ctx, a);
            return threeWay(da, try toDouble(ctx, b));
        },
        .string, .string_case, .locale, .natural, .natural_case => {
            var buf_a: [128]u8 = undefined;
            var buf_b: [128]u8 = undefined;
            const sa = try array_diff.tmpString(ctx, a, &buf_a);
            defer sa.release(ctx);
            const sb = try array_diff.tmpString(ctx, b, &buf_b);
            defer sb.release(ctx);
            return switch (kind) {
                .natural => strnatcmp(sa.bytes, sb.bytes, false),
                .natural_case => strnatcmp(sa.bytes, sb.bytes, true),
                .string_case => binaryCompare(sa.bytes, sb.bytes, true),
                else => binaryCompare(sa.bytes, sb.bytes, false),
            };
        },
    }
}

fn keyText(key: PhpArray.Key, buf: *[24]u8) []const u8 {
    return switch (key) {
        .string => |s| s.bytes(),
        .int => |i| std.fmt.bufPrint(buf, "{d}", .{i}) catch unreachable,
    };
}

// php_array_key_compare_*_unstable_i
fn compareKeys(ctx: *NativeContext, kind: Kind, a: PhpArray.Key, b: PhpArray.Key) RuntimeError!i32 {
    switch (kind) {
        .regular => {
            if (a == .int and b == .int) return if (a.int > b.int) 1 else -1;
            if (a == .string and b == .string) return sign(try ctx.vm.compareWithStringable(keyValue(a), keyValue(b)));
            return sign(try ctx.vm.compareWithStringable(keyValue(a), keyValue(b)));
        },
        .numeric => {
            if (a == .int and b == .int) return if (a.int > b.int) 1 else -1;
            const da: f64 = switch (a) {
                .int => |i| @floatFromInt(i),
                .string => |s| strtodPrefix(s.bytes()),
            };
            const db: f64 = switch (b) {
                .int => |i| @floatFromInt(i),
                .string => |s| strtodPrefix(s.bytes()),
            };
            return threeWay(da, db);
        },
        else => {
            var buf_a: [24]u8 = undefined;
            var buf_b: [24]u8 = undefined;
            const sa = keyText(a, &buf_a);
            const sb = keyText(b, &buf_b);
            return switch (kind) {
                .natural => strnatcmp(sa, sb, false),
                .natural_case => strnatcmp(sa, sb, true),
                .string_case => binaryCompare(sa, sb, true),
                else => binaryCompare(sa, sb, false),
            };
        },
    }
}

// zend_strtod over a key: the longest numeric prefix, 0 when there is none
fn strtodPrefix(s: []const u8) f64 {
    var i: usize = 0;
    while (i < s.len and isSpace(s[i])) i += 1;
    const start = i;
    if (i < s.len and (s[i] == '+' or s[i] == '-')) i += 1;
    const digits_start = i;
    while (i < s.len and isDigit(s[i])) i += 1;
    var mantissa_digits = i - digits_start;
    if (i < s.len and s[i] == '.') {
        const dot = i;
        i += 1;
        const frac_start = i;
        while (i < s.len and isDigit(s[i])) i += 1;
        mantissa_digits += i - frac_start;
        if (mantissa_digits == 0) i = dot;
    }
    if (mantissa_digits == 0) return 0;
    if (i < s.len and (s[i] == 'e' or s[i] == 'E')) {
        var j = i + 1;
        if (j < s.len and (s[j] == '+' or s[j] == '-')) j += 1;
        if (j < s.len and isDigit(s[j])) {
            while (j < s.len and isDigit(s[j])) j += 1;
            i = j;
        }
    }
    return std.fmt.parseFloat(f64, s[start..i]) catch 0;
}

// php_get_long over a comparison callback's result
fn callbackLong(v: Value) i64 {
    return switch (v) {
        .int => |i| i,
        .float => |f| if (std.math.isFinite(f) and f >= -9.223372036854775808e18 and f < 9.223372036854775808e18) @intFromFloat(@trunc(f)) else 0,
        else => Value.toInt(v),
    };
}

pub const Item = struct {
    entry: PhpArray.Entry,
    idx: usize,
};

const SortContext = struct {
    ctx: *NativeContext,
    kind: Kind = .regular,
    by_key: bool = false,
    reverse: bool = false,
    // a user comparison (usort, uasort, uksort)
    callback: ?Value = null,
    name: []const u8 = "",
    deprecation_thrown: bool = false,

    // php_array_user_compare_unstable: a bool result is deprecated, and
    // false asks again with the operands swapped
    fn user(self: *SortContext, a: Value, b: Value) RuntimeError!i32 {
        const callback = self.callback.?;
        const ret = try self.ctx.invokeCallable(callback, &.{ a, b });
        if (ret == .bool) {
            if (!self.deprecation_thrown) {
                self.deprecation_thrown = true;
                const msg = try std.fmt.allocPrint(self.ctx.allocator, "{s}(): Returning bool from comparison function is deprecated, return an integer less than, equal to, or greater than zero", .{self.name});
                defer self.ctx.allocator.free(msg);
                try self.ctx.vm.raiseError(8192, msg);
                if (self.ctx.vm.pending_exception != null) return error.RuntimeError;
            }
            if (!ret.bool) {
                const swapped = try self.ctx.invokeCallable(callback, &.{ b, a });
                return -sign(callbackLong(swapped));
            }
        }
        return sign(callbackLong(ret));
    }

    fn unstable(self: *SortContext, a: Item, b: Item) RuntimeError!i32 {
        if (self.callback != null) {
            if (self.by_key) return self.user(keyValue(a.entry.key), keyValue(b.entry.key));
            return self.user(entryValue(a.entry), entryValue(b.entry));
        }
        if (self.by_key) {
            // the reversed natural key compares swap the operands instead of
            // negating the result
            if (self.reverse and (self.kind == .natural or self.kind == .natural_case)) return compareKeys(self.ctx, self.kind, b.entry.key, a.entry.key);
            const r = try compareKeys(self.ctx, self.kind, a.entry.key, b.entry.key);
            return if (self.reverse) -r else r;
        }
        const r = try compareValues(self.ctx, self.kind, entryValue(a.entry), entryValue(b.entry));
        return if (self.reverse) -r else r;
    }

    pub fn cmp(self: *SortContext, a: Item, b: Item) RuntimeError!i32 {
        const r = try self.unstable(a, b);
        if (r != 0) return r;
        return if (a.idx > b.idx) 1 else if (a.idx < b.idx) -1 else 0;
    }
};

// zend_hash_sort_internal: sort the buckets, then renumber them or keep their
// keys, and reset the internal pointer
fn sortArray(sc: *SortContext, arr: *PhpArray, renumber: bool) RuntimeError!void {
    const n = arr.entries.items.len;
    if (!(n > 1) and !(renumber and n > 0)) return;
    const items = try sc.ctx.allocator.alloc(Item, n);
    defer sc.ctx.allocator.free(items);
    for (arr.entries.items, 0..) |e, i| items[i] = .{ .entry = e, .idx = i };
    try array_diff.zendSort(Item, items, sc);
    // a comparison that ran php code may have changed the array under the
    // sort; php sorts a copy then, and its changes are lost either way
    if (arr.entries.items.len != n) return;
    for (items, 0..) |item, i| arr.entries.items[i] = item.entry;
    if (renumber) {
        for (arr.entries.items, 0..) |*entry, i| {
            if (entry.key == .string) entry.key.string.release();
            entry.key = .{ .int = @intCast(i) };
        }
        arr.next_int_key = @intCast(n);
        arr.has_int_keys = true;
        arr.string_index.clearRetainingCapacity();
    } else {
        arr.rebuildStringIndexAssumeCapacity();
    }
    arr.cursor = 0;
}

fn arrayArg(ctx: *NativeContext, func: []const u8, args: []const Value) RuntimeError!*PhpArray {
    if (args.len > 0 and args[0] == .array) return args[0].array;
    const got: Value = if (args.len > 0) args[0] else .null;
    const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): Argument #1 ($array) must be of type array, {s} given", .{ func, phpTypeName(got) });
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("TypeError", msg);
    return error.RuntimeError;
}

fn flagSort(ctx: *NativeContext, comptime func: []const u8, args: []const Value, by_key: bool, reverse: bool, renumber: bool) RuntimeError!NativeResult {
    const arr = try arrayArg(ctx, func, args);
    const params = html.Params{ .ctx = ctx, .func = func, .args = args };
    const flags = try params.int(1, "flags", sort_regular);
    var sc = SortContext{ .ctx = ctx, .kind = kindFromFlags(flags), .by_key = by_key, .reverse = reverse };
    try sortArray(&sc, arr, renumber);
    return NativeResult.scalar(.{ .bool = true });
}

fn native_sort(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return flagSort(ctx, "sort", args, false, false, true);
}

fn native_rsort(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return flagSort(ctx, "rsort", args, false, true, true);
}

fn native_asort(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return flagSort(ctx, "asort", args, false, false, false);
}

fn native_arsort(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return flagSort(ctx, "arsort", args, false, true, false);
}

fn native_ksort(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return flagSort(ctx, "ksort", args, true, false, false);
}

fn native_krsort(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return flagSort(ctx, "krsort", args, true, true, false);
}

fn natSort(ctx: *NativeContext, comptime func: []const u8, args: []const Value, fold_case: bool) RuntimeError!NativeResult {
    const arr = try arrayArg(ctx, func, args);
    var sc = SortContext{ .ctx = ctx, .kind = if (fold_case) .natural_case else .natural };
    try sortArray(&sc, arr, false);
    return NativeResult.scalar(.{ .bool = true });
}

fn native_natsort(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return natSort(ctx, "natsort", args, false);
}

fn native_natcasesort(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return natSort(ctx, "natcasesort", args, true);
}

fn userSort(ctx: *NativeContext, comptime func: []const u8, args: []const Value, by_key: bool, renumber: bool) RuntimeError!NativeResult {
    const arr = try arrayArg(ctx, func, args);
    if (arr.entries.items.len == 0) return NativeResult.scalar(.{ .bool = true });
    var sc = SortContext{ .ctx = ctx, .by_key = by_key, .callback = args[1], .name = func };
    try sortArray(&sc, arr, renumber);
    return NativeResult.scalar(.{ .bool = true });
}

fn native_usort(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return userSort(ctx, "usort", args, false, true);
}

fn native_uasort(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return userSort(ctx, "uasort", args, false, false);
}

fn native_uksort(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return userSort(ctx, "uksort", args, true, false);
}

// one sort column of array_multisort
const Column = struct {
    arr: *PhpArray,
    kind: Kind = .regular,
    reverse: bool = false,
};

const MultisortContext = struct {
    ctx: *NativeContext,
    columns: []const Column,
    // each column's values as the sort began: a comparison that runs php
    // code may change or empty the arrays, and php compares its own copies
    values: []const []Value,

    // php_multisort_compare: column by column, then the original row
    pub fn cmp(self: *MultisortContext, a: usize, b: usize) RuntimeError!i32 {
        for (self.columns, self.values) |col, items| {
            const r = try compareValues(self.ctx, col.kind, items[a], items[b]);
            const result = if (col.reverse) -r else r;
            if (result != 0) return sign(result);
        }
        return if (a > b) 1 else if (a < b) -1 else 0;
    }
};

fn multisortError(ctx: *NativeContext, class: []const u8, index: usize, comptime text: []const u8) RuntimeError {
    // php names the first parameter, the variadic rest are unnamed
    const msg = if (index == 0)
        try std.fmt.allocPrint(ctx.allocator, "array_multisort(): Argument #1 ($array) " ++ text, .{})
    else
        try std.fmt.allocPrint(ctx.allocator, "array_multisort(): Argument #{d} " ++ text, .{index + 1});
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException(class, msg);
    return error.RuntimeError;
}

fn native_array_multisort(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    var columns: std.ArrayListUnmanaged(Column) = .empty;
    defer columns.deinit(ctx.allocator);
    var order_allowed = false;
    var type_allowed = false;
    var sort_order: i64 = sort_asc;
    var sort_type: i64 = sort_regular;
    for (args, 0..) |arg, i| {
        switch (arg) {
            .array => |arr| {
                if (columns.items.len > 0) {
                    const last = &columns.items[columns.items.len - 1];
                    last.kind = kindFromFlags(sort_type);
                    last.reverse = sort_order != sort_asc;
                    sort_order = sort_asc;
                    sort_type = sort_regular;
                }
                try columns.append(ctx.allocator, .{ .arr = arr });
                order_allowed = true;
                type_allowed = true;
            },
            .int => |flag| switch (flag & ~@as(i64, sort_flag_case)) {
                sort_asc, sort_desc => {
                    if (!order_allowed) return multisortError(ctx, "TypeError", i, "must be an array or a sort flag that has not already been specified");
                    sort_order = if (flag == sort_desc) sort_desc else sort_asc;
                    order_allowed = false;
                },
                sort_regular, sort_numeric, sort_string, sort_natural, sort_locale_string => {
                    if (!type_allowed) return multisortError(ctx, "TypeError", i, "must be an array or a sort flag that has not already been specified");
                    sort_type = flag;
                    type_allowed = false;
                },
                else => return multisortError(ctx, "ValueError", i, "must be a valid sort flag"),
            },
            else => return multisortError(ctx, "TypeError", i, "must be an array or a sort flag"),
        }
    }
    if (columns.items.len == 0) return multisortError(ctx, "TypeError", 0, "must be an array or a sort flag");
    const size = columns.items[0].arr.entries.items.len;
    for (columns.items[1..]) |col| {
        if (col.arr.entries.items.len != size) {
            try ctx.vm.setPendingException("ValueError", "Array sizes are inconsistent");
            return error.RuntimeError;
        }
    }
    if (size < 1) return NativeResult.scalar(.{ .bool = true });
    const last = &columns.items[columns.items.len - 1];
    last.kind = kindFromFlags(sort_type);
    last.reverse = sort_order != sort_asc;

    const rows = try ctx.allocator.alloc(usize, size);
    defer ctx.allocator.free(rows);
    for (rows, 0..) |*r, i| r.* = i;
    const values = try ctx.allocator.alloc([]Value, columns.items.len);
    defer ctx.allocator.free(values);
    var filled: usize = 0;
    defer for (values[0..filled]) |column| {
        for (column) |v| ctx.vm.releaseValue(v);
        ctx.allocator.free(column);
    };
    for (columns.items, values) |col, *column| {
        column.* = try ctx.allocator.alloc(Value, size);
        for (col.arr.entries.items, column.*) |entry, *v| {
            v.* = entryValue(entry);
            @import("../runtime/vm.zig").VM.retainValue(v.*);
        }
        filled += 1;
    }
    var mc = MultisortContext{ .ctx = ctx, .columns = columns.items, .values = values };
    try array_diff.zendSort(usize, rows, &mc);

    const tmp = try ctx.allocator.alloc(PhpArray.Entry, size);
    defer ctx.allocator.free(tmp);
    for (columns.items) |col| {
        const arr = col.arr;
        // a comparison that ran php code may have changed an array; php
        // keeps its own copies of the rows, which this can't
        if (arr.entries.items.len != size) continue;
        for (rows, 0..) |src, dst| tmp[dst] = arr.entries.items[src];
        @memcpy(arr.entries.items, tmp);
        // integer keys are renumbered, string keys kept, and the next free
        // index is the row count
        var next: i64 = 0;
        for (arr.entries.items) |*entry| {
            if (entry.key == .int) {
                entry.key = .{ .int = next };
                next += 1;
            }
        }
        arr.next_int_key = @intCast(size);
        arr.has_int_keys = true;
        arr.rebuildStringIndexAssumeCapacity();
        arr.cursor = 0;
    }
    return NativeResult.scalar(.{ .bool = true });
}

// the sorts ArrayObject and ArrayIterator run on their storage, which php
// does by calling asort, ksort, uasort, uksort, natsort and natcasesort
pub const Request = union(enum) {
    values: i64,
    keys: i64,
    user_values: Value,
    user_keys: Value,
    natural: bool,
};

pub fn sortStorage(ctx: *NativeContext, arr: *PhpArray, request: Request) RuntimeError!void {
    var sc: SortContext = switch (request) {
        .values => |flags| .{ .ctx = ctx, .kind = kindFromFlags(flags) },
        .keys => |flags| .{ .ctx = ctx, .kind = kindFromFlags(flags), .by_key = true },
        .user_values => |callback| .{ .ctx = ctx, .callback = callback, .name = "uasort" },
        .user_keys => |callback| .{ .ctx = ctx, .callback = callback, .by_key = true, .name = "uksort" },
        .natural => |fold_case| .{ .ctx = ctx, .kind = if (fold_case) .natural_case else .natural },
    };
    try sortArray(&sc, arr, false);
}

test "strnatcmp" {
    try std.testing.expectEqual(@as(i32, -1), strnatcmp("img2", "img10", false));
    try std.testing.expectEqual(@as(i32, 1), strnatcmp("a1", "A01", false));
    try std.testing.expectEqual(@as(i32, 0), strnatcmp("abc", "ABC", true));
    try std.testing.expectEqual(@as(i32, -1), strnatcmp("", "a", false));
}
