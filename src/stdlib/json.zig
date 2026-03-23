const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "json_encode", json_encode },
    .{ "json_decode", json_decode },
};

fn json_encode(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    var buf = std.ArrayListUnmanaged(u8){};
    encodeValue(&buf, ctx.allocator, args[0], 0, false) catch return Value{ .bool = false };
    const result = buf.toOwnedSlice(ctx.allocator) catch return Value{ .bool = false };
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn encodeValue(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, val: Value, depth: usize, pretty: bool) !void {
    switch (val) {
        .null => try buf.appendSlice(a, "null"),
        .bool => |b| try buf.appendSlice(a, if (b) "true" else "false"),
        .int => |i| {
            var tmp: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return;
            try buf.appendSlice(a, s);
        },
        .float => |f| {
            if (std.math.isNan(f) or std.math.isInf(f)) {
                try buf.appendSlice(a, "null");
                return;
            }
            if (f == @trunc(f) and @abs(f) < 1e15) {
                const i: i64 = @intFromFloat(f);
                var tmp: [32]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return;
                try buf.appendSlice(a, s);
            } else {
                var tmp: [64]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{f}) catch return;
                try buf.appendSlice(a, s);
            }
        },
        .string => |s| {
            try buf.append(a, '"');
            for (s) |c| {
                switch (c) {
                    '"' => try buf.appendSlice(a, "\\\""),
                    '\\' => try buf.appendSlice(a, "\\\\"),
                    '\n' => try buf.appendSlice(a, "\\n"),
                    '\r' => try buf.appendSlice(a, "\\r"),
                    '\t' => try buf.appendSlice(a, "\\t"),
                    else => {
                        if (c < 0x20) {
                            try buf.appendSlice(a, "\\u00");
                            const hex = "0123456789abcdef";
                            try buf.append(a, hex[c >> 4]);
                            try buf.append(a, hex[c & 0x0f]);
                        } else {
                            try buf.append(a, c);
                        }
                    },
                }
            }
            try buf.append(a, '"');
        },
        .array => |arr| {
            if (isSequential(arr)) {
                try buf.append(a, '[');
                for (arr.entries.items, 0..) |entry, idx| {
                    if (idx > 0) try buf.append(a, ',');
                    if (pretty) {
                        try buf.append(a, '\n');
                        try appendIndent(buf, a, depth + 1);
                    }
                    try encodeValue(buf, a, entry.value, depth + 1, pretty);
                }
                if (pretty and arr.entries.items.len > 0) {
                    try buf.append(a, '\n');
                    try appendIndent(buf, a, depth);
                }
                try buf.append(a, ']');
            } else {
                try buf.append(a, '{');
                for (arr.entries.items, 0..) |entry, idx| {
                    if (idx > 0) try buf.append(a, ',');
                    if (pretty) {
                        try buf.append(a, '\n');
                        try appendIndent(buf, a, depth + 1);
                    }
                    switch (entry.key) {
                        .string => |s| {
                            try buf.append(a, '"');
                            try buf.appendSlice(a, s);
                            try buf.append(a, '"');
                        },
                        .int => |i| {
                            try buf.append(a, '"');
                            var tmp: [32]u8 = undefined;
                            const s = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return;
                            try buf.appendSlice(a, s);
                            try buf.append(a, '"');
                        },
                    }
                    try buf.append(a, ':');
                    if (pretty) try buf.append(a, ' ');
                    try encodeValue(buf, a, entry.value, depth + 1, pretty);
                }
                if (pretty and arr.entries.items.len > 0) {
                    try buf.append(a, '\n');
                    try appendIndent(buf, a, depth);
                }
                try buf.append(a, '}');
            }
        },
        .object => try buf.appendSlice(a, "{}"),
    }
}

fn isSequential(arr: *const PhpArray) bool {
    for (arr.entries.items, 0..) |entry, idx| {
        if (entry.key != .int or entry.key.int != @as(i64, @intCast(idx))) return false;
    }
    return true;
}

fn appendIndent(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, depth: usize) !void {
    for (0..depth) |_| try buf.appendSlice(a, "    ");
}

fn json_decode(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .null;
    const s = args[0].string;
    var pos: usize = 0;
    return parseValue(ctx, s, &pos) catch .null;
}

fn parseValue(ctx: *NativeContext, s: []const u8, pos: *usize) RuntimeError!Value {
    skipWhitespace(s, pos);
    if (pos.* >= s.len) return .null;

    return switch (s[pos.*]) {
        '"' => parseString(ctx, s, pos),
        't' => parseTrue(s, pos),
        'f' => parseFalse(s, pos),
        'n' => parseNull(s, pos),
        '[' => parseArray(ctx, s, pos),
        '{' => parseObject(ctx, s, pos),
        '-', '0'...'9' => parseNumber(s, pos),
        else => .null,
    };
}

fn parseString(ctx: *NativeContext, s: []const u8, pos: *usize) !Value {
    pos.* += 1;
    var buf = std.ArrayListUnmanaged(u8){};
    while (pos.* < s.len and s[pos.*] != '"') {
        if (s[pos.*] == '\\') {
            pos.* += 1;
            if (pos.* >= s.len) break;
            switch (s[pos.*]) {
                '"' => try buf.append(ctx.allocator, '"'),
                '\\' => try buf.append(ctx.allocator, '\\'),
                '/' => try buf.append(ctx.allocator, '/'),
                'n' => try buf.append(ctx.allocator, '\n'),
                'r' => try buf.append(ctx.allocator, '\r'),
                't' => try buf.append(ctx.allocator, '\t'),
                'u' => {
                    pos.* += 1;
                    if (pos.* + 4 <= s.len) {
                        const code = std.fmt.parseInt(u21, s[pos.*..][0..4], 16) catch 0xFFFD;
                        var utf8_buf: [4]u8 = undefined;
                        const len = std.unicode.utf8Encode(code, &utf8_buf) catch 0;
                        try buf.appendSlice(ctx.allocator, utf8_buf[0..len]);
                        pos.* += 3;
                    }
                },
                else => try buf.append(ctx.allocator, s[pos.*]),
            }
        } else {
            try buf.append(ctx.allocator, s[pos.*]);
        }
        pos.* += 1;
    }
    if (pos.* < s.len) pos.* += 1;
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn parseNumber(s: []const u8, pos: *usize) !Value {
    const start = pos.*;
    if (pos.* < s.len and s[pos.*] == '-') pos.* += 1;
    while (pos.* < s.len and s[pos.*] >= '0' and s[pos.*] <= '9') pos.* += 1;
    var is_float = false;
    if (pos.* < s.len and s[pos.*] == '.') {
        is_float = true;
        pos.* += 1;
        while (pos.* < s.len and s[pos.*] >= '0' and s[pos.*] <= '9') pos.* += 1;
    }
    if (pos.* < s.len and (s[pos.*] == 'e' or s[pos.*] == 'E')) {
        is_float = true;
        pos.* += 1;
        if (pos.* < s.len and (s[pos.*] == '+' or s[pos.*] == '-')) pos.* += 1;
        while (pos.* < s.len and s[pos.*] >= '0' and s[pos.*] <= '9') pos.* += 1;
    }
    const num_str = s[start..pos.*];
    if (is_float) {
        const f = std.fmt.parseFloat(f64, num_str) catch 0.0;
        return .{ .float = f };
    }
    const i = std.fmt.parseInt(i64, num_str, 10) catch {
        const f = std.fmt.parseFloat(f64, num_str) catch 0.0;
        return .{ .float = f };
    };
    return .{ .int = i };
}

fn parseTrue(s: []const u8, pos: *usize) !Value {
    if (pos.* + 4 <= s.len and std.mem.eql(u8, s[pos.*..][0..4], "true")) {
        pos.* += 4;
        return .{ .bool = true };
    }
    return .null;
}

fn parseFalse(s: []const u8, pos: *usize) !Value {
    if (pos.* + 5 <= s.len and std.mem.eql(u8, s[pos.*..][0..5], "false")) {
        pos.* += 5;
        return .{ .bool = false };
    }
    return .null;
}

fn parseNull(s: []const u8, pos: *usize) !Value {
    if (pos.* + 4 <= s.len and std.mem.eql(u8, s[pos.*..][0..4], "null")) {
        pos.* += 4;
        return .null;
    }
    return .null;
}

fn parseArray(ctx: *NativeContext, s: []const u8, pos: *usize) !Value {
    pos.* += 1;
    var arr = try ctx.createArray();
    skipWhitespace(s, pos);
    if (pos.* < s.len and s[pos.*] == ']') {
        pos.* += 1;
        return .{ .array = arr };
    }
    while (pos.* < s.len) {
        const val = try parseValue(ctx, s, pos);
        try arr.append(ctx.allocator, val);
        skipWhitespace(s, pos);
        if (pos.* < s.len and s[pos.*] == ',') {
            pos.* += 1;
        } else break;
    }
    skipWhitespace(s, pos);
    if (pos.* < s.len and s[pos.*] == ']') pos.* += 1;
    return .{ .array = arr };
}

fn parseObject(ctx: *NativeContext, s: []const u8, pos: *usize) !Value {
    pos.* += 1;
    var arr = try ctx.createArray();
    skipWhitespace(s, pos);
    if (pos.* < s.len and s[pos.*] == '}') {
        pos.* += 1;
        return .{ .array = arr };
    }
    while (pos.* < s.len) {
        skipWhitespace(s, pos);
        if (pos.* >= s.len or s[pos.*] != '"') break;
        const key_val = try parseString(ctx, s, pos);
        const key_str = if (key_val == .string) key_val.string else "";
        skipWhitespace(s, pos);
        if (pos.* < s.len and s[pos.*] == ':') pos.* += 1;
        const val = try parseValue(ctx, s, pos);
        try arr.set(ctx.allocator, .{ .string = key_str }, val);
        skipWhitespace(s, pos);
        if (pos.* < s.len and s[pos.*] == ',') {
            pos.* += 1;
        } else break;
    }
    skipWhitespace(s, pos);
    if (pos.* < s.len and s[pos.*] == '}') pos.* += 1;
    return .{ .array = arr };
}

fn skipWhitespace(s: []const u8, pos: *usize) void {
    while (pos.* < s.len and (s[pos.*] == ' ' or s[pos.*] == '\t' or s[pos.*] == '\n' or s[pos.*] == '\r')) pos.* += 1;
}
