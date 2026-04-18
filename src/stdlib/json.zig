const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const vm_mod = @import("../runtime/vm.zig");
const NativeContext = vm_mod.NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

const PhpObject = @import("../runtime/value.zig").PhpObject;
const JSON_HEX_TAG: i64 = 1;
const JSON_HEX_AMP: i64 = 2;
const JSON_HEX_APOS: i64 = 4;
const JSON_HEX_QUOT: i64 = 8;
const JSON_FORCE_OBJECT: i64 = 16;
const JSON_NUMERIC_CHECK: i64 = 32;
const JSON_UNESCAPED_SLASHES: i64 = 64;
const JSON_PRETTY_PRINT: i64 = 128;
const JSON_UNESCAPED_UNICODE: i64 = 256;
const JSON_PRESERVE_ZERO_FRACTION: i64 = 1024;
const JSON_BIGINT_AS_STRING: i64 = 2;
const JSON_OBJECT_AS_ARRAY: i64 = 1;
const JSON_INVALID_UTF8_IGNORE: i64 = 1048576;
const JSON_INVALID_UTF8_SUBSTITUTE: i64 = 2097152;
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
    const depth: usize = if (args.len >= 3) @intCast(@max(1, Value.toInt(args[2]))) else 512;
    var buf = std.ArrayListUnmanaged(u8){};
    last_error = 0;
    last_error_msg = "No error";
    encodeValue(&buf, ctx.allocator, args[0], 0, depth, flags, ctx.vm) catch {
        buf.deinit(ctx.allocator);
        if (last_error == 0) {
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

fn encodeValue(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, val: Value, depth: usize, max_depth: usize, flags: i64, vm: ?*vm_mod.VM) !void {
    const pretty = (flags & JSON_PRETTY_PRINT) != 0;
    if ((val == .array or val == .object) and depth >= max_depth) {
        last_error = 1;
        last_error_msg = "Maximum stack depth exceeded";
        return error.RuntimeError;
    }
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
                last_error = 7;
                last_error_msg = "Inf and NaN cannot be JSON encoded";
                return error.RuntimeError;
            }
            const preserve_zero = (flags & JSON_PRESERVE_ZERO_FRACTION) != 0;
            if (f == @trunc(f) and @abs(f) < 1e15) {
                const i: i64 = @intFromFloat(f);
                var tmp: [32]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return;
                try buf.appendSlice(a, s);
                if (preserve_zero) try buf.appendSlice(a, ".0");
            } else {
                var tmp: [64]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{f}) catch return;
                try buf.appendSlice(a, s);
            }
        },
        .string => |s| {
            if ((flags & JSON_NUMERIC_CHECK) != 0 and s.len > 0) {
                if (std.fmt.parseInt(i64, s, 10)) |int_val| {
                    var tmp: [32]u8 = undefined;
                    const ns = std.fmt.bufPrint(&tmp, "{d}", .{int_val}) catch "";
                    try buf.appendSlice(a, ns);
                    return;
                } else |_| {
                    if (std.fmt.parseFloat(f64, s)) |float_val| {
                        if (!std.math.isNan(float_val) and !std.math.isInf(float_val)) {
                            if (float_val == @trunc(float_val) and @abs(float_val) < 1e15) {
                                const iv: i64 = @intFromFloat(float_val);
                                var tmp: [32]u8 = undefined;
                                const ns = std.fmt.bufPrint(&tmp, "{d}", .{iv}) catch "";
                                try buf.appendSlice(a, ns);
                            } else {
                                var tmp: [64]u8 = undefined;
                                const ns = std.fmt.bufPrint(&tmp, "{d}", .{float_val}) catch "";
                                try buf.appendSlice(a, ns);
                            }
                            return;
                        }
                    } else |_| {}
                }
            }
            const hex_tag = (flags & JSON_HEX_TAG) != 0;
            const hex_amp = (flags & JSON_HEX_AMP) != 0;
            const hex_quot = (flags & JSON_HEX_QUOT) != 0;
            const hex_apos = (flags & JSON_HEX_APOS) != 0;
            try buf.append(a, '"');
            var i: usize = 0;
            while (i < s.len) {
                const c = s[i];
                switch (c) {
                    '"' => {
                        if (hex_quot) {
                            try buf.appendSlice(a, "\\u0022");
                        } else {
                            try buf.appendSlice(a, "\\\"");
                        }
                    },
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
                    '<' => {
                        if (hex_tag) try buf.appendSlice(a, "\\u003C") else try buf.append(a, '<');
                    },
                    '>' => {
                        if (hex_tag) try buf.appendSlice(a, "\\u003E") else try buf.append(a, '>');
                    },
                    '&' => {
                        if (hex_amp) try buf.appendSlice(a, "\\u0026") else try buf.append(a, '&');
                    },
                    '\'' => {
                        if (hex_apos) try buf.appendSlice(a, "\\u0027") else try buf.append(a, '\'');
                    },
                    else => {
                        if (c < 0x20) {
                            try buf.appendSlice(a, "\\u00");
                            const hex = "0123456789abcdef";
                            try buf.append(a, hex[c >> 4]);
                            try buf.append(a, hex[c & 0x0f]);
                        } else if (c >= 0x80) {
                            const utf8_ignore = (flags & JSON_INVALID_UTF8_IGNORE) != 0;
                            const utf8_subst = (flags & JSON_INVALID_UTF8_SUBSTITUTE) != 0;
                            const seq_len_or = std.unicode.utf8ByteSequenceLength(c);
                            const codepoint: ?u21 = blk: {
                                const sl = seq_len_or catch break :blk null;
                                if (i + sl > s.len) break :blk null;
                                const cp = std.unicode.utf8Decode(s[i..][0..sl]) catch break :blk null;
                                break :blk cp;
                            };
                            if (codepoint == null) {
                                if (utf8_ignore) {
                                    i += 1;
                                    continue;
                                } else if (utf8_subst) {
                                    if (unescape_unicode) {
                                        try buf.appendSlice(a, "\xef\xbf\xbd");
                                    } else {
                                        try buf.appendSlice(a, "\\ufffd");
                                    }
                                    i += 1;
                                    continue;
                                } else {
                                    last_error = 5;
                                    last_error_msg = "Malformed UTF-8 characters, possibly incorrectly encoded";
                                    return error.RuntimeError;
                                }
                            }
                            const cp = codepoint.?;
                            const sl = seq_len_or catch unreachable;
                            if (unescape_unicode) {
                                try buf.appendSlice(a, s[i..][0..sl]);
                            } else if (cp <= 0xFFFF) {
                                var hex_buf: [6]u8 = undefined;
                                const hex_str = std.fmt.bufPrint(&hex_buf, "\\u{x:0>4}", .{cp}) catch unreachable;
                                try buf.appendSlice(a, hex_str);
                            } else {
                                const cp_off = cp - 0x10000;
                                const high: u16 = @intCast(0xD800 + (cp_off >> 10));
                                const low: u16 = @intCast(0xDC00 + (cp_off & 0x3FF));
                                var hex_buf: [12]u8 = undefined;
                                const hex_str = std.fmt.bufPrint(&hex_buf, "\\u{x:0>4}\\u{x:0>4}", .{ high, low }) catch unreachable;
                                try buf.appendSlice(a, hex_str);
                            }
                            i += sl;
                            continue;
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
            const force_object = (flags & JSON_FORCE_OBJECT) != 0;
            if (!force_object and isSequential(arr)) {
                try buf.append(a, '[');
                for (arr.entries.items, 0..) |entry, idx| {
                    if (idx > 0) try buf.append(a, ',');
                    if (pretty) {
                        try buf.append(a, '\n');
                        try appendIndent(buf, a, depth + 1);
                    }
                    try encodeValue(buf, a, entry.value, depth + 1, max_depth, flags, vm);
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
                    try encodeValue(buf, a, entry.value, depth + 1, max_depth, flags, vm);
                }
                if (pretty and arr.entries.items.len > 0) {
                    try buf.append(a, '\n');
                    try appendIndent(buf, a, depth);
                }
                try buf.append(a, '}');
            }
        },
        .object => |obj| {
            if (vm) |v| {
                if (v.isInstanceOf(obj.class_name, "JsonSerializable")) {
                    const result = v.callMethod(obj, "jsonSerialize", &.{}) catch {
                        try buf.appendSlice(a, "{}");
                        return;
                    };
                    try encodeValue(buf, a, result, depth, max_depth, flags, vm);
                    return;
                }
            }

            // collect public property names in stable order
            const PropEntry = struct { name: []const u8, value: Value };
            var props: [128]PropEntry = undefined;
            var prop_count: usize = 0;

            // slots first (declared properties in class order)
            if (obj.slot_layout) |layout| {
                for (layout.names, 0..) |name, i| {
                    const is_public = if (vm) |v| blk: {
                        const vr = v.findPropertyVisibility(obj.class_name, name);
                        break :blk vr.visibility == .public;
                    } else true;
                    if (is_public and obj.slots != null and i < obj.slots.?.len) {
                        props[prop_count] = .{ .name = name, .value = obj.slots.?[i] };
                        prop_count += 1;
                    }
                }
            }

            // dynamic properties (always public)
            var dyn_iter = obj.properties.iterator();
            while (dyn_iter.next()) |entry| {
                // skip if already in slots
                var in_slots = false;
                if (obj.slot_layout) |layout| {
                    for (layout.names) |sn| {
                        if (std.mem.eql(u8, sn, entry.key_ptr.*)) { in_slots = true; break; }
                    }
                }
                if (!in_slots and prop_count < props.len) {
                    props[prop_count] = .{ .name = entry.key_ptr.*, .value = entry.value_ptr.* };
                    prop_count += 1;
                }
            }

            if (prop_count == 0) {
                try buf.appendSlice(a, "{}");
                return;
            }

            try buf.append(a, '{');
            for (props[0..prop_count], 0..) |prop, idx| {
                if (idx > 0) try buf.append(a, ',');
                if (pretty) {
                    try buf.append(a, '\n');
                    try appendIndent(buf, a, depth + 1);
                }
                try buf.append(a, '"');
                try buf.appendSlice(a, prop.name);
                try buf.append(a, '"');
                try buf.append(a, ':');
                if (pretty) try buf.append(a, ' ');
                try encodeValue(buf, a, prop.value, depth + 1, max_depth, flags, vm);
            }
            if (pretty) {
                try buf.append(a, '\n');
                try appendIndent(buf, a, depth);
            }
            try buf.append(a, '}');
        },
        .generator, .fiber => try buf.appendSlice(a, "{}"),
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
    const flags = if (args.len >= 4) Value.toInt(args[3]) else 0;
    var assoc = if (args.len >= 2) (args[1] == .bool and args[1].bool) else false;
    if ((flags & JSON_OBJECT_AS_ARRAY) != 0) assoc = true;
    if (args.len >= 2 and args[1] == .null and (flags & JSON_OBJECT_AS_ARRAY) != 0) assoc = true;
    const depth: usize = if (args.len >= 3) @intCast(@max(1, Value.toInt(args[2]))) else 512;
    var pos: usize = 0;
    const result = parseValue(ctx, s, &pos, assoc, depth, 0, flags) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        const msg = if (last_error == 1) last_error_msg else "Syntax error";
        if (last_error != 1) {
            last_error = 4;
            last_error_msg = "Syntax error";
        }
        if ((flags & JSON_THROW_ON_ERROR) != 0) {
            return throwJsonException(ctx, msg);
        }
        return .null;
    };
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

fn parseValue(ctx: *NativeContext, s: []const u8, pos: *usize, assoc: bool, max_depth: usize, cur_depth: usize, flags: i64) RuntimeError!Value {
    skipWhitespace(s, pos);
    if (pos.* >= s.len) return .null;

    return switch (s[pos.*]) {
        '"' => parseString(ctx, s, pos),
        't' => parseTrue(s, pos),
        'f' => parseFalse(s, pos),
        'n' => parseNull(s, pos),
        '[' => parseArray(ctx, s, pos, assoc, max_depth, cur_depth, flags),
        '{' => parseObject(ctx, s, pos, assoc, max_depth, cur_depth, flags),
        '-', '0'...'9' => parseNumber(ctx, s, pos, flags),
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
                'b' => try buf.append(ctx.allocator, 0x08),
                'f' => try buf.append(ctx.allocator, 0x0C),
                'u' => {
                    pos.* += 1;
                    if (pos.* + 4 <= s.len) {
                        const high = std.fmt.parseInt(u21, s[pos.*..][0..4], 16) catch 0xFFFD;
                        pos.* += 3;
                        var codepoint: u21 = high;
                        // surrogate pair: high surrogate followed by \uXXXX low surrogate
                        if (high >= 0xD800 and high <= 0xDBFF and pos.* + 7 < s.len and
                            s[pos.* + 1] == '\\' and s[pos.* + 2] == 'u')
                        {
                            const low = std.fmt.parseInt(u21, s[pos.* + 3 ..][0..4], 16) catch 0;
                            if (low >= 0xDC00 and low <= 0xDFFF) {
                                codepoint = 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00);
                                pos.* += 6;
                            } else {
                                codepoint = 0xFFFD;
                            }
                        } else if (high >= 0xD800 and high <= 0xDFFF) {
                            // unpaired surrogate
                            codepoint = 0xFFFD;
                        }
                        var utf8_buf: [4]u8 = undefined;
                        const len = std.unicode.utf8Encode(codepoint, &utf8_buf) catch blk: {
                            const r = std.unicode.utf8Encode(0xFFFD, &utf8_buf) catch 0;
                            break :blk r;
                        };
                        try buf.appendSlice(ctx.allocator, utf8_buf[0..len]);
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

fn parseNumber(ctx: *NativeContext, s: []const u8, pos: *usize, flags: i64) !Value {
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
        if ((flags & JSON_BIGINT_AS_STRING) != 0) {
            const dup = try ctx.allocator.dupe(u8, num_str);
            try ctx.strings.append(ctx.allocator, dup);
            return .{ .string = dup };
        }
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

fn parseArray(ctx: *NativeContext, s: []const u8, pos: *usize, assoc: bool, max_depth: usize, cur_depth: usize, flags: i64) !Value {
    if (cur_depth >= max_depth) {
        last_error = 1;
        last_error_msg = "Maximum stack depth exceeded";
        return error.RuntimeError;
    }
    pos.* += 1;
    var arr = try ctx.createArray();
    skipWhitespace(s, pos);
    if (pos.* < s.len and s[pos.*] == ']') {
        pos.* += 1;
        return .{ .array = arr };
    }
    while (pos.* < s.len) {
        const val = try parseValue(ctx, s, pos, assoc, max_depth, cur_depth + 1, flags);
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

fn parseObject(ctx: *NativeContext, s: []const u8, pos: *usize, assoc: bool, max_depth: usize, cur_depth: usize, flags: i64) !Value {
    if (cur_depth >= max_depth) {
        last_error = 1;
        last_error_msg = "Maximum stack depth exceeded";
        return error.RuntimeError;
    }
    pos.* += 1;
    skipWhitespace(s, pos);

    if (assoc) {
        var arr = try ctx.createArray();
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
            const val = try parseValue(ctx, s, pos, assoc, max_depth, cur_depth + 1, flags);
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

    const obj = try ctx.allocator.create(PhpObject);
    obj.* = .{ .class_name = "stdClass" };
    try ctx.vm.objects.append(ctx.allocator, obj);
    if (pos.* < s.len and s[pos.*] == '}') {
        pos.* += 1;
        return .{ .object = obj };
    }
    while (pos.* < s.len) {
        skipWhitespace(s, pos);
        if (pos.* >= s.len or s[pos.*] != '"') break;
        const key_val = try parseString(ctx, s, pos);
        const key_str = if (key_val == .string) key_val.string else "";
        skipWhitespace(s, pos);
        if (pos.* < s.len and s[pos.*] == ':') pos.* += 1;
        const val = try parseValue(ctx, s, pos, assoc, max_depth, cur_depth + 1, flags);
        try obj.set(ctx.allocator, key_str, val);
        skipWhitespace(s, pos);
        if (pos.* < s.len and s[pos.*] == ',') {
            pos.* += 1;
        } else break;
    }
    skipWhitespace(s, pos);
    if (pos.* < s.len and s[pos.*] == '}') pos.* += 1;
    return .{ .object = obj };
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
