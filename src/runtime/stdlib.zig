const std = @import("std");
const Value = @import("value.zig").Value;
const PhpArray = @import("value.zig").PhpArray;
const vm_mod = @import("vm.zig");
const NativeContext = vm_mod.NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

// ======================================================================
// registration
// ======================================================================

pub fn register(map: *std.StringHashMapUnmanaged(*const fn (*NativeContext, []const Value) RuntimeError!Value), allocator: std.mem.Allocator) !void {
    const fns = .{
        .{ "count", count },
        .{ "strlen", strlen },
        .{ "intval", intval },
        .{ "floatval", floatval },
        .{ "strval", strval },
        .{ "gettype", gettype },
        .{ "is_array", is_array },
        .{ "is_null", is_null },
        .{ "is_int", is_int },
        .{ "is_integer", is_int },
        .{ "is_long", is_int },
        .{ "is_float", is_float },
        .{ "is_double", is_float },
        .{ "is_string", is_string },
        .{ "is_bool", is_bool },
        .{ "is_numeric", is_numeric },
        .{ "isset", native_isset },
        .{ "empty", native_empty },
        .{ "var_dump", var_dump },
        .{ "print_r", print_r },
        // math
        .{ "abs", native_abs },
        .{ "floor", native_floor },
        .{ "ceil", native_ceil },
        .{ "round", native_round },
        .{ "min", native_min },
        .{ "max", native_max },
        .{ "rand", native_rand },
        // string
        .{ "substr", substr },
        .{ "strpos", strpos },
        .{ "str_replace", str_replace },
        .{ "explode", explode },
        .{ "implode", implode },
        .{ "join", implode },
        .{ "trim", trim },
        .{ "ltrim", ltrim },
        .{ "rtrim", rtrim },
        .{ "strtolower", strtolower },
        .{ "strtoupper", strtoupper },
        .{ "str_contains", str_contains },
        .{ "str_starts_with", str_starts_with },
        .{ "str_ends_with", str_ends_with },
        .{ "str_repeat", str_repeat },
        .{ "ucfirst", ucfirst },
        .{ "lcfirst", lcfirst },
        .{ "str_pad", str_pad },
        // array
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
    inline for (fns) |f| try map.put(allocator, f[0], f[1]);
}

// ======================================================================
// type functions
// ======================================================================

fn count(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
    return switch (args[0]) {
        .array => |a| .{ .int = a.length() },
        else => .{ .int = 1 },
    };
}

fn intval(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
    return .{ .int = Value.toInt(args[0]) };
}

fn floatval(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 0.0 };
    return .{ .float = Value.toFloat(args[0]) };
}

fn strval(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    if (args[0] == .string) return args[0];
    var buf = std.ArrayListUnmanaged(u8){};
    try args[0].format(&buf, ctx.allocator);
    const s = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, s);
    return .{ .string = s };
}

fn gettype(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "NULL" };
    return .{ .string = switch (args[0]) {
        .null => "NULL",
        .bool => "boolean",
        .int => "integer",
        .float => "double",
        .string => "string",
        .array => "array",
    } };
}

fn is_array(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return .{ .bool = args.len > 0 and args[0] == .array };
}

fn is_null(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return .{ .bool = args.len == 0 or args[0] == .null };
}

fn is_int(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return .{ .bool = args.len > 0 and args[0] == .int };
}

fn is_float(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return .{ .bool = args.len > 0 and args[0] == .float };
}

fn is_string(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return .{ .bool = args.len > 0 and args[0] == .string };
}

fn is_bool(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return .{ .bool = args.len > 0 and args[0] == .bool };
}

fn is_numeric(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    return .{ .bool = switch (args[0]) {
        .int, .float => true,
        .string => |s| if (std.fmt.parseFloat(f64, s)) |_| true else |_| false,
        else => false,
    } };
}

fn native_isset(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    return .{ .bool = args[0] != .null };
}

fn native_empty(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = true };
    return .{ .bool = !args[0].isTruthy() };
}

fn strlen(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
    return switch (args[0]) {
        .string => |s| .{ .int = @intCast(s.len) },
        else => .{ .int = 0 },
    };
}

// ======================================================================
// var_dump / print_r
// ======================================================================

fn var_dump(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    _ = ctx;
    _ = args;
    return .null;
}

fn print_r(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    _ = ctx;
    _ = args;
    return .null;
}

// ======================================================================
// math
// ======================================================================

fn native_abs(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
    return switch (args[0]) {
        .int => |i| .{ .int = if (i < 0) -i else i },
        .float => |f| .{ .float = @abs(f) },
        else => .{ .int = @as(i64, if (Value.toInt(args[0]) < 0) -Value.toInt(args[0]) else Value.toInt(args[0])) },
    };
}

fn native_floor(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 0.0 };
    return .{ .float = @floor(Value.toFloat(args[0])) };
}

fn native_ceil(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 0.0 };
    return .{ .float = @ceil(Value.toFloat(args[0])) };
}

fn native_round(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 0.0 };
    const v = Value.toFloat(args[0]);
    return .{ .float = @round(v) };
}

fn native_min(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .null;
    if (args.len == 1 and args[0] == .array) {
        const arr = args[0].array;
        if (arr.entries.items.len == 0) return .null;
        var result = arr.entries.items[0].value;
        for (arr.entries.items[1..]) |e| {
            if (Value.lessThan(e.value, result)) result = e.value;
        }
        return result;
    }
    var result = args[0];
    for (args[1..]) |a| {
        if (Value.lessThan(a, result)) result = a;
    }
    return result;
}

fn native_max(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .null;
    if (args.len == 1 and args[0] == .array) {
        const arr = args[0].array;
        if (arr.entries.items.len == 0) return .null;
        var result = arr.entries.items[0].value;
        for (arr.entries.items[1..]) |e| {
            if (Value.lessThan(result, e.value)) result = e.value;
        }
        return result;
    }
    var result = args[0];
    for (args[1..]) |a| {
        if (Value.lessThan(result, a)) result = a;
    }
    return result;
}

fn native_rand(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const lo: i64 = if (args.len >= 1) Value.toInt(args[0]) else 0;
    const hi: i64 = if (args.len >= 2) Value.toInt(args[1]) else 2147483647;
    if (lo >= hi) return .{ .int = lo };
    const range: u64 = @intCast(hi - lo + 1);
    const r = std.crypto.random.intRangeAtMost(u64, 0, range - 1);
    return .{ .int = lo + @as(i64, @intCast(r)) };
}

// ======================================================================
// string functions
// ======================================================================

fn substr(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const slen: i64 = @intCast(s.len);
    var start = Value.toInt(args[1]);
    if (start < 0) start = @max(0, slen + start);
    if (start >= slen) return .{ .string = "" };
    const ustart: usize = @intCast(start);

    if (args.len >= 3) {
        var length = Value.toInt(args[2]);
        if (length < 0) {
            length = @max(0, slen - @as(i64, @intCast(ustart)) + length);
        }
        const end: usize = @min(s.len, ustart + @as(usize, @intCast(@max(0, length))));
        return .{ .string = try ctx.createString(s[ustart..end]) };
    }
    return .{ .string = try ctx.createString(s[ustart..]) };
}

fn strpos(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .bool = false };
    const haystack = if (args[0] == .string) args[0].string else return Value{ .bool = false };
    const needle = if (args[1] == .string) args[1].string else return Value{ .bool = false };
    const offset: usize = if (args.len >= 3) @intCast(@max(0, Value.toInt(args[2]))) else 0;
    if (offset >= haystack.len) return .{ .bool = false };
    if (std.mem.indexOf(u8, haystack[offset..], needle)) |pos| {
        return .{ .int = @intCast(pos + offset) };
    }
    return .{ .bool = false };
}

fn str_replace(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3) return if (args.len >= 3) args[2] else Value{ .string = "" };
    const search = if (args[0] == .string) args[0].string else return args[2];
    const replace = if (args[1] == .string) args[1].string else return args[2];
    const subject = if (args[2] == .string) args[2].string else return args[2];
    if (search.len == 0) return args[2];

    var buf = std.ArrayListUnmanaged(u8){};
    var i: usize = 0;
    while (i < subject.len) {
        if (i + search.len <= subject.len and std.mem.eql(u8, subject[i .. i + search.len], search)) {
            try buf.appendSlice(ctx.allocator, replace);
            i += search.len;
        } else {
            try buf.append(ctx.allocator, subject[i]);
            i += 1;
        }
    }
    const s = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, s);
    return .{ .string = s };
}

fn explode(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .null;
    const delim = if (args[0] == .string) args[0].string else return Value.null;
    const s = if (args[1] == .string) args[1].string else return Value.null;
    if (delim.len == 0) return .{ .bool = false };

    var arr = try ctx.createArray();
    var i: usize = 0;
    while (i <= s.len) {
        if (std.mem.indexOf(u8, s[i..], delim)) |pos| {
            try arr.append(ctx.allocator, .{ .string = try ctx.createString(s[i .. i + pos]) });
            i += pos + delim.len;
        } else {
            try arr.append(ctx.allocator, .{ .string = try ctx.createString(s[i..]) });
            break;
        }
    }
    return .{ .array = arr };
}

fn implode(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    var glue: []const u8 = "";
    var arr_val: Value = .null;

    if (args.len == 1) {
        arr_val = args[0];
    } else {
        glue = if (args[0] == .string) args[0].string else "";
        arr_val = args[1];
    }

    if (arr_val != .array) return .{ .string = "" };
    const arr = arr_val.array;
    if (arr.entries.items.len == 0) return .{ .string = "" };

    var buf = std.ArrayListUnmanaged(u8){};
    for (arr.entries.items, 0..) |entry, i| {
        if (i > 0) try buf.appendSlice(ctx.allocator, glue);
        try entry.value.format(&buf, ctx.allocator);
    }
    const s = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, s);
    return .{ .string = s };
}

fn trim(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const trimmed = std.mem.trim(u8, s, " \t\n\r\x0b\x00");
    return .{ .string = try ctx.createString(trimmed) };
}

fn ltrim(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const trimmed = std.mem.trimLeft(u8, s, " \t\n\r\x0b\x00");
    return .{ .string = try ctx.createString(trimmed) };
}

fn rtrim(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const trimmed = std.mem.trimRight(u8, s, " \t\n\r\x0b\x00");
    return .{ .string = try ctx.createString(trimmed) };
}

fn strtolower(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const buf = try ctx.allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| buf[i] = std.ascii.toLower(c);
    try ctx.strings.append(ctx.allocator, buf);
    return .{ .string = buf };
}

fn strtoupper(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const buf = try ctx.allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| buf[i] = std.ascii.toUpper(c);
    try ctx.strings.append(ctx.allocator, buf);
    return .{ .string = buf };
}

fn str_contains(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .bool = false };
    const haystack = if (args[0] == .string) args[0].string else return Value{ .bool = false };
    const needle = if (args[1] == .string) args[1].string else return Value{ .bool = false };
    return .{ .bool = std.mem.indexOf(u8, haystack, needle) != null };
}

fn str_starts_with(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .bool = false };
    const haystack = if (args[0] == .string) args[0].string else return Value{ .bool = false };
    const needle = if (args[1] == .string) args[1].string else return Value{ .bool = false };
    return .{ .bool = std.mem.startsWith(u8, haystack, needle) };
}

fn str_ends_with(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .bool = false };
    const haystack = if (args[0] == .string) args[0].string else return Value{ .bool = false };
    const needle = if (args[1] == .string) args[1].string else return Value{ .bool = false };
    return .{ .bool = std.mem.endsWith(u8, haystack, needle) };
}

fn str_repeat(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const times = @max(0, Value.toInt(args[1]));
    if (times == 0 or s.len == 0) return .{ .string = "" };

    var buf = std.ArrayListUnmanaged(u8){};
    var i: i64 = 0;
    while (i < times) : (i += 1) try buf.appendSlice(ctx.allocator, s);
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn ucfirst(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    if (s.len == 0) return .{ .string = "" };
    const buf = try ctx.allocator.alloc(u8, s.len);
    @memcpy(buf, s);
    buf[0] = std.ascii.toUpper(buf[0]);
    try ctx.strings.append(ctx.allocator, buf);
    return .{ .string = buf };
}

fn lcfirst(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    if (s.len == 0) return .{ .string = "" };
    const buf = try ctx.allocator.alloc(u8, s.len);
    @memcpy(buf, s);
    buf[0] = std.ascii.toLower(buf[0]);
    try ctx.strings.append(ctx.allocator, buf);
    return .{ .string = buf };
}

fn str_pad(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return if (args.len > 0) args[0] else Value{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const target_len: usize = @intCast(@max(0, Value.toInt(args[1])));
    if (s.len >= target_len) return args[0];
    const pad_str = if (args.len >= 3 and args[2] == .string) args[2].string else " ";
    if (pad_str.len == 0) return args[0];
    const pad_type = if (args.len >= 4) Value.toInt(args[3]) else 1;
    const diff = target_len - s.len;

    var buf = std.ArrayListUnmanaged(u8){};
    if (pad_type == 0) {
        var i: usize = 0;
        while (i < diff) : (i += 1) try buf.append(ctx.allocator, pad_str[i % pad_str.len]);
        try buf.appendSlice(ctx.allocator, s);
    } else {
        try buf.appendSlice(ctx.allocator, s);
        var i: usize = 0;
        while (i < diff) : (i += 1) try buf.append(ctx.allocator, pad_str[i % pad_str.len]);
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

// ======================================================================
// array functions
// ======================================================================

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

    // bubble sort using the callback comparator
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
