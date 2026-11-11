const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const value_mod = @import("../runtime/value.zig");
const vm_mod = @import("../runtime/vm.zig");
const NativeContext = vm_mod.NativeContext;
const NativeResult = vm_mod.NativeResult;
const RuntimeError = error{ RuntimeError, OutOfMemory };

const PhpObject = @import("../runtime/value.zig").PhpObject;
const object_properties = @import("../runtime/object_properties.zig");
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
    .{ "json_validate", json_validate },
};

fn json_encode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    const flags = if (args.len >= 2) Value.toInt(args[1]) else 0;
    const depth: usize = if (args.len >= 3) @intCast(@max(1, Value.toInt(args[2]))) else 512;
    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);
    last_error = 0;
    last_error_msg = "No error";
    encodeValue(&buf, ctx.allocator, args[0], 0, depth, flags, ctx.vm) catch {
        if (last_error == 0) {
            last_error = 5;
            last_error_msg = "Malformed UTF-8 characters, possibly incorrectly encoded";
        }
        if ((flags & JSON_THROW_ON_ERROR) != 0) {
            return throwJsonException(ctx, last_error_msg);
        }
        return NativeResult.scalar(.{ .bool = false });
    };
    last_error = 0;
    last_error_msg = "No error";
    const result = try buf.toOwnedSlice(ctx.allocator);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result));
}

// php's recursion protection: the flag is on the array or object itself, so
// a json_encode nested inside jsonSerialize sees what the outer one is in
const Recursion = value_mod.Recursion;

// a value met again while it is being encoded. with partial output it
// encodes as null and the rest carries on
fn recursionFound(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, flags: i64) !void {
    if ((flags & 0x200) != 0) { // JSON_PARTIAL_OUTPUT_ON_ERROR
        try buf.appendSlice(a, "null");
        return;
    }
    last_error = 6;
    last_error_msg = "Recursion detected";
    return error.RuntimeError;
}

fn encodeValue(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, val: Value, depth: usize, max_depth: usize, flags: i64, vm: ?*vm_mod.VM) !void {
    const pretty = (flags & JSON_PRETTY_PRINT) != 0;
    // php_json_check_stack_limit: out of native stack is a depth error
    if ((val == .array or val == .object) and (depth >= max_depth or vm_mod.stack_limit.overflowed())) {
        last_error = 1;
        last_error_msg = "Maximum stack depth exceeded";
        return error.RuntimeError;
    }
    const unescape_slashes = (flags & JSON_UNESCAPED_SLASHES) != 0;
    const unescape_unicode = (flags & JSON_UNESCAPED_UNICODE) != 0;
    switch (val) {
        .null, .undef => try buf.appendSlice(a, "null"),
        .bool => |b| try buf.appendSlice(a, if (b) "true" else "false"),
        .int => |i| {
            var tmp: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return;
            try buf.appendSlice(a, s);
        },
        .float => |f| {
            if (std.math.isNan(f) or std.math.isInf(f)) {
                if ((flags & 0x200) != 0) { // JSON_PARTIAL_OUTPUT_ON_ERROR
                    try buf.appendSlice(a, "0");
                    return;
                }
                last_error = 7;
                last_error_msg = "Inf and NaN cannot be JSON encoded";
                return error.RuntimeError;
            }
            // smart_str_append_double: the shortest round-trip digits with a
            // lowercase exponent, ".0" only under JSON_PRESERVE_ZERO_FRACTION
            var tmp: [64]u8 = undefined;
            const text = @import("formatted_print.zig").gcvt(f, -1, '.', 'e', &tmp);
            try buf.appendSlice(a, text);
            if ((flags & JSON_PRESERVE_ZERO_FRACTION) != 0 and std.mem.indexOfAny(u8, text, ".eE") == null) try buf.appendSlice(a, ".0");
        },
        .string => |s| {
            if ((flags & JSON_NUMERIC_CHECK) != 0 and s.len > 0) {
                if (std.fmt.parseInt(i64, s.bytes(), 10)) |int_val| {
                    var tmp: [32]u8 = undefined;
                    const ns = std.fmt.bufPrint(&tmp, "{d}", .{int_val}) catch "";
                    try buf.appendSlice(a, ns);
                    return;
                } else |_| {
                    if (std.fmt.parseFloat(f64, s.bytes())) |float_val| {
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
                const c = s.bytes()[i];
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
                    0x08 => try buf.appendSlice(a, "\\b"),
                    0x0c => try buf.appendSlice(a, "\\f"),
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
                                const cp = std.unicode.utf8Decode(s.bytes()[i..][0..sl]) catch break :blk null;
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
                            const unescape_line_term = (flags & 2048) != 0; // JSON_UNESCAPED_LINE_TERMINATORS
                            const is_line_term = cp == 0x2028 or cp == 0x2029;
                            if (unescape_unicode and !(is_line_term and !unescape_line_term)) {
                                try buf.appendSlice(a, s.bytes()[i..][0..sl]);
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
            if (arr.recursion & Recursion.gc != 0) return recursionFound(buf, a, flags);
            arr.recursion |= Recursion.gc;
            defer arr.recursion &= ~Recursion.gc;
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
                            // route through encodeValue so the key gets the
                            // same escaping (\n, \t, unicode etc) as values
                            try encodeValue(buf, a, .{ .string = s }, depth, max_depth, flags, vm);
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
        .object => |proxy| {
            if (vm) |runtime| try runtime.triggerLazyInit(proxy);
            const obj = proxy.storage();
            if (vm) |v| {
                if (v.classes.get(obj.class_name)) |cd| {
                    if (cd.is_enum) {
                        if (cd.backed_type == .none) {
                            try v.setPendingException("JsonException", "Non-backed enums have no default serialization");
                            return error.RuntimeError;
                        }
                        const enum_val = obj.get("value");
                        try encodeValue(buf, a, enum_val, depth, max_depth, flags, vm);
                        return;
                    }
                }
                if (std.mem.eql(u8, obj.class_name, "SimpleXMLElement")) {
                    // hand off to the simplexml helper that walks the underlying
                    // libxml tree; json_encode on a SimpleXMLElement folds
                    // attributes under "@attributes" and groups same-named
                    // children into arrays
                    if (vm) |vv| {
                        var nctx: vm_mod.NativeContext = .{
                            .vm = vv,
                            .allocator = a,
                            .arrays = &vv.arrays,
                            .strings = &vv.strings,
                        };
                        const built = @import("simplexml.zig").elementToJsonValue(&nctx, obj) catch null;
                        if (built) |bv| {
                            try encodeValue(buf, a, bv, depth, max_depth, flags, vm);
                            return;
                        }
                    }
                }
                if (v.isInstanceOf(obj.class_name, "JsonSerializable")) {
                    // php's JSON recursion guard: jsonSerialize isn't run for
                    // an object whose jsonSerialize is running
                    if (obj.recursion & Recursion.json != 0) return recursionFound(buf, a, flags);
                    obj.recursion |= Recursion.json;
                    var guarded = true;
                    defer if (guarded) {
                        obj.recursion &= ~Recursion.json;
                    };
                    const result = v.callMethod(obj, "jsonSerialize", &.{}) catch {
                        try buf.appendSlice(a, "{}");
                        return;
                    };
                    // an object that serializes to itself is encoded by its
                    // properties, with the guard already lifted
                    if (!(result == .object and result.object.storage() == obj)) {
                        try encodeValue(buf, a, result, depth, max_depth, flags, vm);
                        return;
                    }
                    obj.recursion &= ~Recursion.json;
                    guarded = false;
                }
                if (std.mem.eql(u8, obj.class_name, "SplFixedArray")) {
                    const data = obj.get("__data");
                    if (data == .array) {
                        try encodeValue(buf, a, data, depth, max_depth, flags, vm);
                        return;
                    }
                }
            }

            if (obj.recursion & Recursion.gc != 0) return recursionFound(buf, a, flags);
            obj.recursion |= Recursion.gc;
            defer obj.recursion &= ~Recursion.gc;

            // the public properties, or the table the object's class builds
            // for json (ArrayObject's storage); a json encoder without a vm
            // sees only dynamic properties
            const PropEntry = struct { key: object_properties.Key, value: Value };
            var props: std.ArrayListUnmanaged(PropEntry) = .empty;
            defer props.deinit(a);
            // what get hooks returned, which props borrow
            var hook_values: ?*value_mod.PhpArray = null;
            defer if (vm) |v| object_properties.releaseHolder(v, hook_values);
            if (vm) |v| {
                var listing = try object_properties.list(v, obj, .json, a);
                defer listing.deinit(a);
                hook_values = listing.takeHolder();
                for (listing.items.items) |prop| {
                    if (prop.visibility != .public) continue;
                    try props.append(a, .{ .key = prop.key, .value = prop.value });
                }
            } else {
                var it = obj.properties.iterator();
                while (it.next()) |entry| try props.append(a, .{ .key = .{ .name = entry.key_ptr.* }, .value = entry.value_ptr.* });
            }
            const prop_count = props.items.len;

            if (prop_count == 0) {
                try buf.appendSlice(a, "{}");
                return;
            }

            try buf.append(a, '{');
            for (props.items, 0..) |prop, idx| {
                if (idx > 0) try buf.append(a, ',');
                if (pretty) {
                    try buf.append(a, '\n');
                    try appendIndent(buf, a, depth + 1);
                }
                switch (prop.key) {
                    .name => |name| try encodeValue(buf, a, .{ .string = Value.String.borrowed(name) }, depth, max_depth, flags, vm),
                    .int => |i| try buf.print(a, "\"{d}\"", .{i}),
                }
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
        .resource => {
            if ((flags & 0x200) != 0) { // JSON_PARTIAL_OUTPUT_ON_ERROR
                try buf.appendSlice(a, "null");
                return;
            }
            last_error = 8;
            last_error_msg = "Type is not supported";
            return error.RuntimeError;
        },
    }
}

fn formatJsonScientific(buf: *[64]u8, f: f64) []const u8 {
    // zig {e} produces shortest round-trippable scientific form. post-process
    // to match php's `1.0e+300` shape: ensure mantissa has a decimal point
    // (append `.0` if integral) and exponent always carries an explicit sign.
    var raw_buf: [64]u8 = undefined;
    const raw = std.fmt.bufPrint(&raw_buf, "{e}", .{f}) catch return "0";
    const e_idx = std.mem.indexOfScalar(u8, raw, 'e') orelse return std.fmt.bufPrint(buf, "{s}", .{raw}) catch "0";
    const mant = raw[0..e_idx];
    const exp = raw[e_idx + 1 ..];
    const has_dot = std.mem.indexOfScalar(u8, mant, '.') != null;
    const exp_has_sign = exp.len > 0 and (exp[0] == '+' or exp[0] == '-');
    if (has_dot and exp_has_sign) {
        return std.fmt.bufPrint(buf, "{s}", .{raw}) catch "0";
    }
    if (!has_dot and !exp_has_sign) {
        return std.fmt.bufPrint(buf, "{s}.0e+{s}", .{ mant, exp }) catch "0";
    }
    if (!has_dot) {
        return std.fmt.bufPrint(buf, "{s}.0e{s}", .{ mant, exp }) catch "0";
    }
    // has_dot, no sign on exp
    return std.fmt.bufPrint(buf, "{s}e+{s}", .{ mant, exp }) catch "0";
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

fn json_decode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.null);
    const s = args[0].string.bytes();
    const flags = if (args.len >= 4) Value.toInt(args[3]) else 0;
    // PHP semantics: JSON_OBJECT_AS_ARRAY only applies when $associative is
    // null (default); an explicit true/false wins over the flag.
    const has_explicit_assoc = args.len >= 2 and args[1] == .bool;
    const assoc = if (has_explicit_assoc)
        args[1].bool
    else
        (flags & JSON_OBJECT_AS_ARRAY) != 0;
    const depth: usize = if (args.len >= 3) @intCast(@max(1, Value.toInt(args[2]))) else 512;
    last_error = 0;
    last_error_msg = "No error";
    if (s.len == 0) {
        last_error = 4;
        last_error_msg = "Syntax error";
        if ((flags & JSON_THROW_ON_ERROR) != 0) {
            return throwJsonException(ctx, "Syntax error");
        }
        return NativeResult.scalar(.null);
    }
    var pos: usize = 0;
    const result = parseValue(ctx, s, &pos, assoc, depth, 0, flags) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        if (last_error == 0) {
            last_error = 4;
            last_error_msg = "Syntax error";
        }
        if ((flags & JSON_THROW_ON_ERROR) != 0) {
            return throwJsonException(ctx, last_error_msg);
        }
        return NativeResult.scalar(.null);
    };
    defer if (result == .string) result.string.release();
    skipWhitespace(s, &pos);
    if (pos < s.len) {
        ctx.vm.discardOrphan(result);
        last_error = 4;
        last_error_msg = "Syntax error";
        if ((flags & JSON_THROW_ON_ERROR) != 0) {
            return throwJsonException(ctx, "Syntax error");
        }
        return NativeResult.scalar(.null);
    }
    last_error = 0;
    last_error_msg = "No error";
    return NativeResult.share(result);
}

// Match PHP's array-key coercion: a string key that looks like a decimal
// integer (no leading zeros, no plus sign, no whitespace) and fits in i64
// becomes an int key. Used by json_decode in assoc mode.
fn decodeKeyToArrayKey(s: []const u8) PhpArray.Key {
    if (s.len == 0) return .{ .string = Value.String.borrowed(s) };
    var i: usize = 0;
    if (s[0] == '-') {
        if (s.len == 1) return .{ .string = Value.String.borrowed(s) };
        i = 1;
    }
    if (i >= s.len) return .{ .string = Value.String.borrowed(s) };
    if (s[i] == '0') {
        if (s.len - i != 1) return .{ .string = Value.String.borrowed(s) };
    } else if (s[i] < '1' or s[i] > '9') {
        return .{ .string = Value.String.borrowed(s) };
    }
    var j: usize = i + 1;
    while (j < s.len) : (j += 1) {
        if (s[j] < '0' or s[j] > '9') return .{ .string = Value.String.borrowed(s) };
    }
    const v = std.fmt.parseInt(i64, s, 10) catch return .{ .string = Value.String.borrowed(s) };
    return .{ .int = v };
}

fn setSyntaxError() void {
    last_error = 4;
    last_error_msg = "Syntax error";
}

fn parseValue(ctx: *NativeContext, s: []const u8, pos: *usize, assoc: bool, max_depth: usize, cur_depth: usize, flags: i64) RuntimeError!Value {
    skipWhitespace(s, pos);
    if (pos.* >= s.len) {
        setSyntaxError();
        return error.RuntimeError;
    }

    return switch (s[pos.*]) {
        '"' => parseString(ctx, s, pos),
        't' => parseTrue(s, pos),
        'f' => parseFalse(s, pos),
        'n' => parseNull(s, pos),
        '[' => parseArray(ctx, s, pos, assoc, max_depth, cur_depth, flags),
        '{' => parseObject(ctx, s, pos, assoc, max_depth, cur_depth, flags),
        '-', '0'...'9' => parseNumber(ctx, s, pos, flags),
        else => {
            setSyntaxError();
            return error.RuntimeError;
        },
    };
}

fn parseString(ctx: *NativeContext, s: []const u8, pos: *usize) !Value {
    pos.* += 1;
    var buf = std.ArrayListUnmanaged(u8).empty;
    errdefer buf.deinit(ctx.allocator);
    while (pos.* < s.len and s[pos.*] != '"') {
        if (s[pos.*] == '\\') {
            pos.* += 1;
            if (pos.* >= s.len) {
                last_error = 3;
                last_error_msg = "Control character error, possibly incorrectly encoded";
                return error.RuntimeError;
            }
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
                    if (pos.* + 4 > s.len) {
                        setSyntaxError();
                        return error.RuntimeError;
                    }
                    const high = std.fmt.parseInt(u21, s[pos.*..][0..4], 16) catch {
                        setSyntaxError();
                        return error.RuntimeError;
                    };
                    pos.* += 3;
                    var codepoint: u21 = high;
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
                        codepoint = 0xFFFD;
                    }
                    var utf8_buf: [4]u8 = undefined;
                    const len = std.unicode.utf8Encode(codepoint, &utf8_buf) catch blk: {
                        const r = std.unicode.utf8Encode(0xFFFD, &utf8_buf) catch 0;
                        break :blk r;
                    };
                    try buf.appendSlice(ctx.allocator, utf8_buf[0..len]);
                },
                else => {
                    setSyntaxError();
                    return error.RuntimeError;
                },
            }
        } else if (s[pos.*] < 0x20) {
            last_error = 3;
            last_error_msg = "Control character error, possibly incorrectly encoded";
            return error.RuntimeError;
        } else {
            try buf.append(ctx.allocator, s[pos.*]);
        }
        pos.* += 1;
    }
    if (pos.* >= s.len) {
        last_error = 3;
        last_error_msg = "Control character error, possibly incorrectly encoded";
        return error.RuntimeError;
    }
    pos.* += 1;
    const result = try buf.toOwnedSlice(ctx.allocator);
    return .{ .string = try Value.String.adopt(ctx.allocator, result) };
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
            return .{ .string = try Value.String.create(ctx.allocator, num_str) };
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
    setSyntaxError();
    return error.RuntimeError;
}

fn parseFalse(s: []const u8, pos: *usize) !Value {
    if (pos.* + 5 <= s.len and std.mem.eql(u8, s[pos.*..][0..5], "false")) {
        pos.* += 5;
        return .{ .bool = false };
    }
    setSyntaxError();
    return error.RuntimeError;
}

fn parseNull(s: []const u8, pos: *usize) !Value {
    if (pos.* + 4 <= s.len and std.mem.eql(u8, s[pos.*..][0..4], "null")) {
        pos.* += 4;
        return .null;
    }
    setSyntaxError();
    return error.RuntimeError;
}

fn parseArray(ctx: *NativeContext, s: []const u8, pos: *usize, assoc: bool, max_depth: usize, cur_depth: usize, flags: i64) !Value {
    if (cur_depth + 1 >= max_depth) {
        last_error = 1;
        last_error_msg = "Maximum stack depth exceeded";
        return error.RuntimeError;
    }
    pos.* += 1;
    var arr = try ctx.createArray();
    errdefer ctx.vm.discardOrphan(.{ .array = arr });
    skipWhitespace(s, pos);
    if (pos.* < s.len and s[pos.*] == ']') {
        pos.* += 1;
        return .{ .array = arr };
    }
    while (pos.* < s.len) {
        const val = try parseValue(ctx, s, pos, assoc, max_depth, cur_depth + 1, flags);
        defer if (val == .string) val.string.release();
        try arr.append(ctx.allocator, val);
        skipWhitespace(s, pos);
        if (pos.* < s.len and s[pos.*] == ',') {
            pos.* += 1;
            skipWhitespace(s, pos);
            if (pos.* < s.len and s[pos.*] == ']') {
                setSyntaxError();
                return error.RuntimeError;
            }
        } else break;
    }
    skipWhitespace(s, pos);
    if (pos.* >= s.len or s[pos.*] != ']') {
        setSyntaxError();
        return error.RuntimeError;
    }
    pos.* += 1;
    return .{ .array = arr };
}

fn parseObject(ctx: *NativeContext, s: []const u8, pos: *usize, assoc: bool, max_depth: usize, cur_depth: usize, flags: i64) !Value {
    if (cur_depth + 1 >= max_depth) {
        last_error = 1;
        last_error_msg = "Maximum stack depth exceeded";
        return error.RuntimeError;
    }
    pos.* += 1;
    skipWhitespace(s, pos);

    if (assoc) {
        const arr = try ctx.createArray();
        errdefer ctx.vm.discardOrphan(.{ .array = arr });
        if (pos.* < s.len and s[pos.*] == '}') {
            pos.* += 1;
            return .{ .array = arr };
        }
        while (pos.* < s.len) {
            skipWhitespace(s, pos);
            if (pos.* >= s.len or s[pos.*] != '"') {
                setSyntaxError();
                return error.RuntimeError;
            }
            const key_val = try parseString(ctx, s, pos);
            defer key_val.string.release();
            const key_str = if (key_val == .string) key_val.string.bytes() else "";
            skipWhitespace(s, pos);
            if (pos.* >= s.len or s[pos.*] != ':') {
                setSyntaxError();
                return error.RuntimeError;
            }
            pos.* += 1;
            const val = try parseValue(ctx, s, pos, assoc, max_depth, cur_depth + 1, flags);
            defer if (val == .string) val.string.release();
            var key = decodeKeyToArrayKey(key_str);
            if (key == .string) key.string = key_val.string;
            try ctx.vm.arraySetOwned(arr, key, val);
            skipWhitespace(s, pos);
            if (pos.* < s.len and s[pos.*] == ',') {
                pos.* += 1;
            } else break;
        }
        skipWhitespace(s, pos);
        if (pos.* >= s.len or s[pos.*] != '}') {
            setSyntaxError();
            return error.RuntimeError;
        }
        pos.* += 1;
        return .{ .array = arr };
    }

    // php's parser makes the object once its first member's value is
    // parsed, so objects nested there are numbered before it
    var made: ?*PhpObject = null;
    errdefer if (made) |obj| ctx.vm.discardOrphan(.{ .object = obj });
    if (pos.* < s.len and s[pos.*] == '}') {
        pos.* += 1;
        return .{ .object = try ctx.vm.allocObject(.{ .class_name = "stdClass" }) };
    }
    while (pos.* < s.len) {
        skipWhitespace(s, pos);
        if (pos.* >= s.len or s[pos.*] != '"') {
            setSyntaxError();
            return error.RuntimeError;
        }
        const key_val = try parseString(ctx, s, pos);
        defer key_val.string.release();
        const key_str = if (key_val == .string) key_val.string.bytes() else "";
        skipWhitespace(s, pos);
        if (pos.* >= s.len or s[pos.*] != ':') {
            setSyntaxError();
            return error.RuntimeError;
        }
        pos.* += 1;
        const val = try parseValue(ctx, s, pos, assoc, max_depth, cur_depth + 1, flags);
        defer if (val == .string) val.string.release();
        const obj = made orelse blk: {
            made = try ctx.vm.allocObject(.{ .class_name = "stdClass" });
            break :blk made.?;
        };
        try obj.set(ctx.allocator, key_str, val);
        skipWhitespace(s, pos);
        if (pos.* < s.len and s[pos.*] == ',') {
            pos.* += 1;
        } else break;
    }
    skipWhitespace(s, pos);
    if (pos.* >= s.len or s[pos.*] != '}') {
        setSyntaxError();
        return error.RuntimeError;
    }
    pos.* += 1;
    return .{ .object = made orelse try ctx.vm.allocObject(.{ .class_name = "stdClass" }) };
}

fn skipWhitespace(s: []const u8, pos: *usize) void {
    while (pos.* < s.len and (s[pos.*] == ' ' or s[pos.*] == '\t' or s[pos.*] == '\n' or s[pos.*] == '\r')) pos.* += 1;
}

fn throwJsonException(ctx: *NativeContext, msg: []const u8) RuntimeError {
    ctx.vm.setPendingException("JsonException", msg) catch return error.OutOfMemory;
    return error.RuntimeError;
}

fn json_validate(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const s = args[0].string.bytes();
    const depth: usize = if (args.len >= 2) @intCast(@max(1, Value.toInt(args[1]))) else 512;
    const flags = if (args.len >= 3) Value.toInt(args[2]) else 0;
    last_error = 0;
    last_error_msg = "No error";
    if (s.len == 0) {
        last_error = 4;
        last_error_msg = "Syntax error";
        return NativeResult.scalar(.{ .bool = false });
    }
    var pos: usize = 0;
    const parsed = parseValue(ctx, s, &pos, true, depth, 0, flags) catch {
        if (last_error == 0) {
            last_error = 4;
            last_error_msg = "Syntax error";
        }
        return NativeResult.scalar(.{ .bool = false });
    };
    defer if (parsed == .string) parsed.string.release();
    skipWhitespace(s, &pos);
    if (pos < s.len) {
        last_error = 4;
        last_error_msg = "Syntax error";
        return NativeResult.scalar(.{ .bool = false });
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn native_json_last_error(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = last_error });
}

fn native_json_last_error_msg(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.copyString(ctx.allocator, last_error_msg);
}
