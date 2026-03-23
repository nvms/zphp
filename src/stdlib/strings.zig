const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
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
};

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
