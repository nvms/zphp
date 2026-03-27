const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const vm_mod = @import("../runtime/vm.zig");
const NativeContext = vm_mod.NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

const PhpObject = @import("../runtime/value.zig").PhpObject;
const JSON_UNESCAPED_SLASHES: i64 = 64;
const JSON_PRETTY_PRINT: i64 = 128;
const JSON_UNESCAPED_UNICODE: i64 = 256;
const JSON_THROW_ON_ERROR: i64 = 4194304;

var last_error: i64 = 0;
var last_error_msg: []const u8 = "No error";

pub const entries = .{
    .{ "json_encode", json_encode },
    .{ "json_decode", json_decode },
    .{ "json_last_error", native_json_last_error },
    .{ "json_last_error_msg", native_json_last_error_msg },
};

fn json_encode(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    const flags = if (args.len >= 2) Value.toInt(args[1]) else 0;
    var buf = std.ArrayListUnmanaged(u8){};
    encodeValue(&buf, ctx.allocator, args[0], 0, flags) catch {
        buf.deinit(ctx.allocator);
        // check if it was a NaN/Inf error
        if (args[0] == .float and (std.math.isNan(args[0].float) or std.math.isInf(args[0].float))) {
            last_error = 5;
            last_error_msg = "Inf and NaN cannot be JSON encoded";
        } else {
            last_error = 5;
            last_error_msg = "Malformed UTF-8 characters, possibly incorrectly encoded";
        }
        if ((flags & JSON_THROW_ON_ERROR) != 0) {
            return throwJsonException(ctx, last_error_msg);
        }
        return .{ .bool = false };
    };
    last_error = 0;
    last_error_msg = "No error";
    const result = buf.toOwnedSlice(ctx.allocator) catch return .{ .bool = false };
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn encodeValue(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, val: Value, depth: usize, flags: i64) !void {
    const pretty = (flags & JSON_PRETTY_PRINT) != 0;
    const unescape_slashes = (flags & JSON_UNESCAPED_SLASHES) != 0;
    const unescape_unicode = (flags & JSON_UNESCAPED_UNICODE) != 0;
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
                if ((flags & JSON_THROW_ON_ERROR) != 0) return error.RuntimeError;
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
            var i: usize = 0;
            while (i < s.len) {
                const c = s[i];
                switch (c) {
                    '"' => try buf.appendSlice(a, "\\\""),
                    '\\' => try buf.appendSlice(a, "\\\\"),
                    '\n' => try buf.appendSlice(a, "\\n"),
                    '\r' => try buf.appendSlice(a, "\\r"),
                    '\t' => try buf.appendSlice(a, "\\t"),
                    '/' => {
                        if (unescape_slashes) {
                            try buf.append(a, '/');
                        } else {
                            try buf.appendSlice(a, "\\/");
                        }
                    },
                    else => {
                        if (c < 0x20) {
                            try buf.appendSlice(a, "\\u00");
                            const hex = "0123456789abcdef";
                            try buf.append(a, hex[c >> 4]);
                            try buf.append(a, hex[c & 0x0f]);
                        } else if (c >= 0x80 and !unescape_unicode) {
                            // encode non-ASCII as \uXXXX
                            const seq_len = std.unicode.utf8ByteSequenceLength(c) catch {
                                try buf.append(a, c);
                                i += 1;
                                continue;
                            };
                            if (i + seq_len <= s.len) {
                                const codepoint = std.unicode.utf8Decode(s[i..][0..seq_len]) catch {
                                    try buf.append(a, c);
                                    i += 1;
                                    continue;
                                };
                                if (codepoint <= 0xFFFF) {
                                    var hex_buf: [6]u8 = undefined;
                                    const hex_str = std.fmt.bufPrint(&hex_buf, "\\u{x:0>4}", .{codepoint}) catch {
                                        try buf.append(a, c);
                                        i += 1;
                                        continue;
                                    };
                                    try buf.appendSlice(a, hex_str);
                                } else {
                                    // surrogate pair for codepoints > 0xFFFF
                                    const cp = codepoint - 0x10000;
                                    const high: u16 = @intCast(0xD800 + (cp >> 10));
                                    const low: u16 = @intCast(0xDC00 + (cp & 0x3FF));
                                    var hex_buf: [12]u8 = undefined;
                                    const hex_str = std.fmt.bufPrint(&hex_buf, "\\u{x:0>4}\\u{x:0>4}", .{ high, low }) catch {
                                        try buf.append(a, c);
                                        i += 1;
                                        continue;
                                    };
                                    try buf.appendSlice(a, hex_str);
                                }
                                i += seq_len;
                                continue;
                            } else {
                                try buf.append(a, c);
                            }
                        } else {
                            try buf.append(a, c);
                        }
                    },
                }
                i += 1;
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
                    try encodeValue(buf, a, entry.value, depth + 1, flags);
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
                        .int => |ki| {
                            try buf.append(a, '"');
                            var tmp: [32]u8 = undefined;
                            const s = std.fmt.bufPrint(&tmp, "{d}", .{ki}) catch return;
                            try buf.appendSlice(a, s);
                            try buf.append(a, '"');
                        },
                    }
                    try buf.append(a, ':');
                    if (pretty) try buf.append(a, ' ');
                    try encodeValue(buf, a, entry.value, depth + 1, flags);
                }
                if (pretty and arr.entries.items.len > 0) {
                    try buf.append(a, '\n');
                    try appendIndent(buf, a, depth);
                }
                try buf.append(a, '}');
            }
        },
        .object, .generator, .fiber => try buf.appendSlice(a, "{}"),
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
    // flags can be arg 2 (assoc bool) or arg 4 (flags int)
    const flags = if (args.len >= 4) Value.toInt(args[3]) else 0;
    var pos: usize = 0;
    const result = parseValue(ctx, s, &pos) catch {
        last_error = 4;
        last_error_msg = "Syntax error";
        if ((flags & JSON_THROW_ON_ERROR) != 0) {
            return throwJsonException(ctx, "Syntax error");
        }
        return .null;
    };
    // check for trailing non-whitespace (invalid json)
    skipWhitespace(s, &pos);
    if (pos < s.len) {
        last_error = 4;
        last_error_msg = "Syntax error";
        if ((flags & JSON_THROW_ON_ERROR) != 0) {
            return throwJsonException(ctx, "Syntax error");
        }
        return .null;
    }
    last_error = 0;
    last_error_msg = "No error";
    return result;
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

fn throwJsonException(ctx: *NativeContext, msg: []const u8) RuntimeError {
    const obj = ctx.allocator.create(PhpObject) catch return error.OutOfMemory;
    obj.* = .{ .class_name = "JsonException" };
    obj.set(ctx.allocator, "message", .{ .string = msg }) catch {};
    obj.set(ctx.allocator, "code", .{ .int = 0 }) catch {};
    ctx.vm.objects.append(ctx.allocator, obj) catch {};
    ctx.vm.pending_exception = .{ .object = obj };
    return error.RuntimeError;
}

fn native_json_last_error(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = last_error };
}

fn native_json_last_error_msg(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .string = last_error_msg };
}
