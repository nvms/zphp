const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const std = @import("std");
const platform = @import("../platform.zig");

extern "c" fn snprintf(buf: [*c]u8, size: usize, fmt: [*c]const u8, ...) c_int;
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };
const phpTypeName = @import("types.zig").phpTypeName;
const html = @import("html.zig");
const url_parse = @import("url.zig");

pub const entries = .{
    .{ "substr", substr },
    .{ "strtolower", strtolower },
    .{ "strtoupper", strtoupper },
    .{ "str_contains", str_contains },
    .{ "str_starts_with", str_starts_with },
    .{ "str_ends_with", str_ends_with },
    .{ "str_repeat", str_repeat },
    .{ "str_shuffle", str_shuffle },
    .{ "ucfirst", ucfirst },
    .{ "lcfirst", lcfirst },
    .{ "str_split", native_str_split },
    .{ "addslashes", native_addslashes },
    .{ "hex2bin", native_hex2bin },
    .{ "bin2hex", native_bin2hex },
    .{ "mb_strlen", native_mb_strlen },
    .{ "mb_str_split", native_mb_str_split },
    .{ "mb_strtolower", native_mb_strtolower },
    .{ "mb_strtoupper", native_mb_strtoupper },
    .{ "mb_convert_case", native_mb_convert_case },
    .{ "mb_check_encoding", native_mb_check_encoding },
    .{ "mb_detect_encoding", native_mb_detect_encoding },
    .{ "mb_convert_encoding", native_mb_convert_encoding },
    .{ "mb_convert_variables", native_mb_convert_variables },
    .{ "utf8_encode", native_utf8_encode },
    .{ "utf8_decode", native_utf8_decode },
    .{ "iconv", native_iconv },
    .{ "iconv_strlen", native_mb_strlen },
    .{ "iconv_strpos", native_mb_strpos },
    .{ "iconv_strrpos", native_mb_strrpos },
    .{ "iconv_substr", native_mb_substr },
    .{ "mb_strpos", native_mb_strpos },
    .{ "mb_strrpos", native_mb_strrpos },
    .{ "mb_substr_count", native_mb_substr_count },
    .{ "mb_internal_encoding", native_mb_internal_encoding },
    .{ "mb_substitute_character", native_mb_substitute_character },
    .{ "mb_strwidth", native_mb_strwidth },
    .{ "mb_encode_numericentity", native_mb_encode_numericentity },
    .{ "mb_decode_numericentity", native_mb_decode_numericentity },
    .{ "mb_chr", native_mb_chr },
    .{ "mb_ord", native_mb_ord },
    .{ "mb_stripos", native_mb_stripos },
    .{ "mb_strripos", native_mb_strripos },
    .{ "mb_strstr", native_mb_strstr },
    .{ "mb_stristr", native_mb_stristr },
    .{ "mb_strrchr", native_mb_strrchr },
    .{ "mb_strimwidth", native_mb_strimwidth },
    .{ "mb_strcut", native_mb_strcut },
    .{ "mb_str_pad", native_mb_str_pad },
    .{ "mb_encoding_aliases", native_mb_encoding_aliases },
    .{ "mb_list_encodings", native_mb_list_encodings },
    .{ "str_getcsv", @import("csv.zig").str_getcsv },
    .{ "base64_encode", native_base64_encode },
    .{ "base64_decode", native_base64_decode },
    .{ "urlencode", native_urlencode },
    .{ "urldecode", native_urldecode },
    .{ "rawurlencode", native_rawurlencode },
    .{ "rawurldecode", native_rawurldecode },
    .{ "md5", native_md5 },
    .{ "sha1", native_sha1 },
    .{ "mb_substr", native_mb_substr },
    .{ "strrev", native_strrev },
    .{ "crc32", native_crc32 },
    .{ "str_rot13", native_str_rot13 },
    .{ "quotemeta", native_quotemeta },
    .{ "mb_trim", native_mb_trim },
    .{ "mb_ltrim", native_mb_ltrim },
    .{ "mb_rtrim", native_mb_rtrim },
    .{ "mb_ucfirst", native_mb_ucfirst },
    .{ "mb_lcfirst", native_mb_lcfirst },
    .{ "mb_strrichr", native_mb_strrichr },
    .{ "mb_scrub", native_mb_scrub },
    .{ "mb_http_input", native_mb_http_input },
    .{ "mb_http_output", native_mb_http_output },
    .{ "mb_language", native_mb_language },
    .{ "mb_preferred_mime_name", native_mb_preferred_mime_name },
    .{ "mb_detect_order", native_mb_detect_order },
    .{ "mb_get_info", native_mb_get_info },
    .{ "mb_parse_str", native_mb_parse_str },
    .{ "strip_tags", native_strip_tags },
    .{ "http_build_query", native_http_build_query },
    .{ "quoted_printable_decode", native_qp_decode },
    .{ "parse_url", native_parse_url },
    .{ "parse_str", native_parse_str },
    .{ "levenshtein", native_levenshtein },
    .{ "similar_text", native_similar_text },
    .{ "strcspn", native_strcspn },
    .{ "strspn", native_strspn },
} ++ @import("html.zig").entries;

fn substr(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.literal("");
    if (try rejectArrayParam(ctx, args[0], "substr")) return error.RuntimeError;
    const s = try coerceToString(ctx, args[0]);
    const slen: i64 = @intCast(s.len);
    var start = Value.toInt(args[1]);
    if (start < 0) start = @max(0, slen + start);
    if (start >= slen) return NativeResult.literal("");
    const ustart: usize = @intCast(start);

    if (args.len >= 3 and args[2] != .null) {
        var length = Value.toInt(args[2]);
        if (length < 0) {
            length = @max(0, slen - @as(i64, @intCast(ustart)) + length);
        }
        const end: usize = @min(s.len, ustart + @as(usize, @intCast(@max(0, length))));
        if (args[0] == .string) return NativeResult.shareString(args[0].string.borrowedSlice(ustart, end));
        return NativeResult.copyString(ctx.allocator, s[ustart..end]);
    }
    if (args[0] == .string) return NativeResult.shareString(args[0].string.borrowedSlice(ustart, s.len));
    return NativeResult.copyString(ctx.allocator, s[ustart..]);
}

const ReplaceResult = struct { str: Value.String, count: i64 };

fn replaceOne(ctx: *NativeContext, subject: []const u8, search: []const u8, replace: []const u8) !ReplaceResult {
    if (search.len == 0) return .{ .str = try Value.String.create(ctx.allocator, subject), .count = 0 };
    var buf = std.ArrayListUnmanaged(u8).empty;
    errdefer buf.deinit(ctx.allocator);
    var i: usize = 0;
    var cnt: i64 = 0;
    while (i < subject.len) {
        if (i + search.len <= subject.len and std.mem.eql(u8, subject[i .. i + search.len], search)) {
            try buf.appendSlice(ctx.allocator, replace);
            i += search.len;
            cnt += 1;
        } else {
            try buf.append(ctx.allocator, subject[i]);
            i += 1;
        }
    }
    const s = try buf.toOwnedSlice(ctx.allocator);
    return .{ .str = try Value.String.adopt(ctx.allocator, s), .count = cnt };
}

fn strReplaceOnSingle(ctx: *NativeContext, search: Value, replace: Value, subject: []const u8, total_count: *i64) !Value.String {
    if (search == .array) {
        var result = try Value.String.create(ctx.allocator, subject);
        errdefer result.release();
        for (search.array.entries.items, 0..) |entry, idx| {
            const needle = if (entry.value == .string) entry.value.string.bytes() else continue;
            const replacement = if (replace == .array) blk: {
                break :blk if (idx < replace.array.entries.items.len)
                    (if (replace.array.entries.items[idx].value == .string) replace.array.entries.items[idx].value.string.bytes() else "")
                else
                    "";
            } else if (replace == .string) replace.string.bytes() else "";
            const r = try replaceOne(ctx, result.bytes(), needle, replacement);
            result.release();
            result = r.str;
            total_count.* += r.count;
        }
        return result;
    }
    const s = if (search == .string) search.string.bytes() else return try Value.String.create(ctx.allocator, subject);
    const rep = if (replace == .string) replace.string.bytes() else "";
    const r = try replaceOne(ctx, subject, s, rep);
    total_count.* += r.count;
    return r.str;
}

const default_trim_chars = " \t\n\r\x0b\x00";

// build the trim char set, expanding `a..b` ranges
fn buildTrimSet(chars: []const u8) [256]bool {
    var set: [256]bool = @splat(false);
    var i: usize = 0;
    while (i < chars.len) {
        if (i + 3 < chars.len and chars[i + 1] == '.' and chars[i + 2] == '.') {
            const lo = chars[i];
            const hi = chars[i + 3];
            if (lo <= hi) {
                var c: usize = lo;
                while (c <= hi) : (c += 1) set[c] = true;
                i += 4;
                continue;
            }
        }
        set[chars[i]] = true;
        i += 1;
    }
    return set;
}

fn trimWithSet(s: []const u8, set: [256]bool, left: bool, right: bool) []const u8 {
    var lo: usize = 0;
    var hi: usize = s.len;
    if (left) while (lo < hi and set[s[lo]]) : (lo += 1) {};
    if (right) while (hi > lo and set[s[hi - 1]]) : (hi -= 1) {};
    return s[lo..hi];
}

fn strtolower(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    if (try rejectArrayParam(ctx, args[0], "strtolower")) return error.RuntimeError;
    const s = try coerceToString(ctx, args[0]);
    const buf = try ctx.allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| buf[i] = std.ascii.toLower(c);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, buf));
}

fn strtoupper(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len != 1) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "strtoupper() expects exactly 1 argument, {d} given", .{args.len});
        defer ctx.allocator.free(msg);
        try ctx.vm.setPendingException("ArgumentCountError", msg);
        return error.RuntimeError;
    }
    if (try rejectArrayParam(ctx, args[0], "strtoupper")) return error.RuntimeError;
    const s = try coerceToString(ctx, args[0]);
    const buf = try ctx.allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| buf[i] = std.ascii.toUpper(c);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, buf));
}

fn str_contains(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.scalar(.{ .bool = false });
    const haystack = try coerceToString(ctx, args[0]);
    const needle = try coerceToString(ctx, args[1]);
    if (needle.len == 0) return NativeResult.scalar(.{ .bool = true });
    return NativeResult.scalar(.{ .bool = std.mem.indexOf(u8, haystack, needle) != null });
}

fn str_starts_with(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.scalar(.{ .bool = false });
    const haystack = try coerceToString(ctx, args[0]);
    const needle = try coerceToString(ctx, args[1]);
    return NativeResult.scalar(.{ .bool = std.mem.startsWith(u8, haystack, needle) });
}

fn str_ends_with(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.scalar(.{ .bool = false });
    const haystack = try coerceToString(ctx, args[0]);
    const needle = try coerceToString(ctx, args[1]);
    return NativeResult.scalar(.{ .bool = std.mem.endsWith(u8, haystack, needle) });
}

fn str_shuffle(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    const s = try coerceToString(ctx, args[0]);
    if (s.len <= 1) return if (args[0] == .string) NativeResult.share(args[0]) else NativeResult.copyString(ctx.allocator, s);
    const buf = try ctx.allocator.alloc(u8, s.len);
    @memcpy(buf, s);
    // php_binary_string_shuffle over the default engine, mt_rand's
    if (!ctx.vm.rng_seeded) {
        var entropy: [4]u8 = undefined;
        platform.random.bytes(&entropy);
        ctx.vm.mt19937.seed(std.mem.readInt(u32, &entropy, .little));
        ctx.vm.rng_seeded = true;
    }
    var n_left: usize = buf.len - 1;
    while (n_left > 0) : (n_left -= 1) {
        const j: usize = @intCast(ctx.vm.mt19937.nextRange(0, @intCast(n_left)));
        if (j != n_left) std.mem.swap(u8, &buf[n_left], &buf[j]);
    }
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, buf));
}

fn str_repeat(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.literal("");
    const s = try coerceToString(ctx, args[0]);
    const raw_times = Value.toInt(args[1]);
    if (raw_times < 0) {
        try ctx.vm.setPendingException("ValueError", "str_repeat(): Argument #2 ($times) must be greater than or equal to 0");
        return error.RuntimeError;
    }
    const times: usize = std.math.cast(usize, raw_times) orelse return error.OutOfMemory;
    if (times == 0 or s.len == 0) return NativeResult.literal("");
    const length = std.math.mul(usize, s.len, times) catch return error.OutOfMemory;
    const result = try ctx.allocator.alloc(u8, length);
    for (0..times) |i| @memcpy(result[i * s.len ..][0..s.len], s);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result));
}

fn ucfirst(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    const s = try coerceToString(ctx, args[0]);
    if (s.len == 0) return NativeResult.literal("");
    const buf = try ctx.allocator.alloc(u8, s.len);
    @memcpy(buf, s);
    buf[0] = std.ascii.toUpper(buf[0]);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, buf));
}

fn lcfirst(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    const s = try coerceToString(ctx, args[0]);
    if (s.len == 0) return NativeResult.literal("");
    const buf = try ctx.allocator.alloc(u8, s.len);
    @memcpy(buf, s);
    buf[0] = std.ascii.toLower(buf[0]);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, buf));
}

fn native_str_split(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.null);
    const s = if (args[0] == .string) args[0].string.bytes() else return NativeResult.scalar(.null);
    if (args.len >= 2) {
        const len = Value.toInt(args[1]);
        if (len <= 0) {
            try ctx.vm.setPendingException("ValueError", "str_split(): Argument #2 ($length) must be greater than 0");
            return error.RuntimeError;
        }
    }
    const chunk_len: usize = if (args.len >= 2) @intCast(@max(1, Value.toInt(args[1]))) else 1;

    var arr = try ctx.createArray();
    var i: usize = 0;
    while (i < s.len) {
        const end = @min(i + chunk_len, s.len);
        const part = try Value.String.create(ctx.allocator, s[i..end]);
        defer part.release();
        try arr.append(ctx.allocator, .{ .string = part });
        i = end;
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn substrReplaceOne(ctx: *NativeContext, s: []const u8, replacement: []const u8, start_in: i64, len_opt: ?i64) !Value.String {
    const slen: i64 = @intCast(s.len);
    var start = start_in;
    if (start < 0) start = @max(0, slen + start);
    if (start > slen) start = slen;
    const ustart: usize = @intCast(start);

    var end: usize = s.len;
    if (len_opt) |length| {
        if (length < 0) {
            end = @intCast(@max(0, slen + length));
            if (end < ustart) end = ustart;
        } else {
            end = @min(s.len, ustart + @as(usize, @intCast(@max(0, length))));
        }
    }

    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);
    try buf.appendSlice(ctx.allocator, s[0..ustart]);
    try buf.appendSlice(ctx.allocator, replacement);
    if (end < s.len) try buf.appendSlice(ctx.allocator, s[end..]);
    const result = try buf.toOwnedSlice(ctx.allocator);
    return Value.String.adopt(ctx.allocator, result);
}

fn native_addslashes(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    const s = try coerceToString(ctx, args[0]);
    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);
    for (s) |c| {
        if (c == 0) {
            // PHP encodes NUL as the literal sequence "\0" (backslash + zero digit)
            try buf.append(ctx.allocator, '\\');
            try buf.append(ctx.allocator, '0');
            continue;
        }
        if (c == '\'' or c == '"' or c == '\\') {
            try buf.append(ctx.allocator, '\\');
        }
        try buf.append(ctx.allocator, c);
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result));
}

fn appendCodepoint(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, code: u32) !void {
    if (code < 0x80) {
        try buf.append(allocator, @intCast(code));
    } else if (code < 0x800) {
        try buf.append(allocator, @intCast(0xC0 | (code >> 6)));
        try buf.append(allocator, @intCast(0x80 | (code & 0x3F)));
    } else if (code < 0x10000) {
        try buf.append(allocator, @intCast(0xE0 | (code >> 12)));
        try buf.append(allocator, @intCast(0x80 | ((code >> 6) & 0x3F)));
        try buf.append(allocator, @intCast(0x80 | (code & 0x3F)));
    } else if (code < 0x110000) {
        try buf.append(allocator, @intCast(0xF0 | (code >> 18)));
        try buf.append(allocator, @intCast(0x80 | ((code >> 12) & 0x3F)));
        try buf.append(allocator, @intCast(0x80 | ((code >> 6) & 0x3F)));
        try buf.append(allocator, @intCast(0x80 | (code & 0x3F)));
    }
}

fn native_hex2bin(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    const s = try coerceToString(ctx, args[0]);
    if (s.len % 2 != 0) {
        try ctx.vm.emitWarning("hex2bin(): Hexadecimal input string must have an even length");
        return NativeResult.scalar(.{ .bool = false });
    }
    const out_len = s.len / 2;
    const buf = try ctx.allocator.alloc(u8, out_len);
    for (0..out_len) |j| {
        const hi = hexVal(s[j * 2]) orelse {
            ctx.allocator.free(buf);
            try ctx.vm.emitWarning("hex2bin(): Input string must be hexadecimal string");
            return NativeResult.scalar(.{ .bool = false });
        };
        const lo = hexVal(s[j * 2 + 1]) orelse {
            ctx.allocator.free(buf);
            try ctx.vm.emitWarning("hex2bin(): Input string must be hexadecimal string");
            return NativeResult.scalar(.{ .bool = false });
        };
        buf[j] = (hi << 4) | lo;
    }
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, buf));
}

fn hexVal(c: u8) ?u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    return null;
}

fn native_bin2hex(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    const s = try coerceToString(ctx, args[0]);
    const hex_chars = "0123456789abcdef";
    const buf = try ctx.allocator.alloc(u8, s.len * 2);
    for (s, 0..) |c, j| {
        buf[j * 2] = hex_chars[c >> 4];
        buf[j * 2 + 1] = hex_chars[c & 0x0f];
    }
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, buf));
}

fn native_mb_str_split(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.null);
    const s = if (args[0] == .string) args[0].string.bytes() else return NativeResult.scalar(.null);
    const raw_len: i64 = if (args.len >= 2) Value.toInt(args[1]) else 1;
    if (raw_len < 1) {
        try ctx.vm.setPendingException("ValueError", "mb_str_split(): Argument #2 ($length) must be greater than 0");
        return error.RuntimeError;
    }
    const chunk_len: usize = @intCast(raw_len);
    var arr = try ctx.createArray();
    if (s.len == 0) return NativeResult.borrowed(.{ .array = arr });
    var i: usize = 0;
    while (i < s.len) {
        const start = i;
        var taken: usize = 0;
        while (taken < chunk_len and i < s.len) : (taken += 1) {
            i = @min(s.len, i + utf8LeadLength(s[i]));
        }
        const part = try Value.String.create(ctx.allocator, s[start..i]);
        defer part.release();
        try arr.append(ctx.allocator, .{ .string = part });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_mb_strlen(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .int = 0 });
    const s = if (args[0] == .string) args[0].string.bytes() else return NativeResult.scalar(Value{ .int = 0 });
    if (args.len >= 2 and args[1] == .string) {
        const enc = args[1].string.bytes();
        if (std.ascii.eqlIgnoreCase(enc, "8bit") or std.ascii.eqlIgnoreCase(enc, "binary")) {
            return NativeResult.scalar(.{ .int = @intCast(s.len) });
        }
    }
    return NativeResult.scalar(.{ .int = mbCharCount(s) });
}

fn native_mb_strtolower(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    const s = if (args[0] == .string) args[0].string.bytes() else return NativeResult.literal("");
    return NativeResult.takeString(try utfCaseConvert(ctx, s, false));
}

fn native_mb_strtoupper(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    const s = if (args[0] == .string) args[0].string.bytes() else return NativeResult.literal("");
    return NativeResult.takeString(try utfCaseConvert(ctx, s, true));
}

fn native_mb_convert_case(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string) return NativeResult.literal("");
    const s = args[0].string.bytes();
    const mode = Value.toInt(args[1]);
    return switch (mode) {
        0 => NativeResult.takeString(try utfCaseConvert(ctx, s, true)),
        1 => NativeResult.takeString(try utfCaseConvert(ctx, s, false)),
        2 => NativeResult.takeString(try utfTitleCase(ctx, s)),
        else => NativeResult.share(args[0]),
    };
}

// MB_CASE_TITLE the way php's mbstring does it: a character is title-cased
// unless the last character that is not case-ignorable was cased, in which
// case it is lower-cased
fn utfTitleCase(ctx: *NativeContext, s: []const u8) !Value.String {
    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);
    var i: usize = 0;
    var in_word = false;
    while (i < s.len) {
        const step = utf8Step(s, i);
        defer i += step.len;
        if (!step.valid) {
            try buf.append(ctx.allocator, '?');
            continue;
        }
        const cp: u21 = if (step.len == 1) s[i] else std.unicode.utf8Decode(s[i .. i + step.len]) catch unreachable;
        if (in_word) {
            try appendCodepoint(&buf, ctx.allocator, caseLower(cp));
        } else if (caseExpansionTitle(cp)) |seq| {
            try buf.appendSlice(ctx.allocator, seq);
        } else {
            try appendCodepoint(&buf, ctx.allocator, unicodeToTitle(cp));
        }
        if (!caseIgnorable(cp)) in_word = isCased(cp);
    }
    return Value.String.adopt(ctx.allocator, try buf.toOwnedSlice(ctx.allocator));
}

// the titlecase mapping: uppercase except for the digraphs that have a
// dedicated titlecase letter
fn unicodeToTitle(cp: u21) u21 {
    if (cp < 0x80) return std.ascii.toUpper(@intCast(cp));
    return switch (cp) {
        0x01C4...0x01C6 => 0x01C5,
        0x01C7...0x01C9 => 0x01C8,
        0x01CA...0x01CC => 0x01CB,
        0x01F1...0x01F3 => 0x01F2,
        else => unicodeToUpper(cp),
    };
}

// titlecase mappings that expand to several characters
fn caseExpansionTitle(cp: u21) ?[]const u8 {
    return switch (cp) {
        0x00DF => "Ss",
        0xFB00 => "Ff",
        0xFB01 => "Fi",
        0xFB02 => "Fl",
        0xFB03 => "Ffi",
        0xFB04 => "Ffl",
        0xFB05, 0xFB06 => "St",
        0x0587 => "\xD4\xB5\xD6\x82",
        else => caseExpansionUpper(cp),
    };
}

fn caseLower(cp: u21) u21 {
    return if (cp < 0x80) std.ascii.toLower(@intCast(cp)) else unicodeToLower(cp);
}

fn isCased(cp: u21) bool {
    return unicodeToTitle(cp) != cp or caseLower(cp) != cp or caseExpansionUpper(cp) != null;
}

// Unicode's Case_Ignorable: marks, format characters, modifier letters and
// symbols, and the word-internal punctuation (apostrophes, periods, colons)
fn caseIgnorable(cp: u21) bool {
    return switch (cp) {
        '\'', '.', ':', '^', '`', 0xA8, 0xAD, 0xAF, 0xB4, 0xB7, 0xB8 => true,
        0x02B0...0x036F, 0x0374, 0x0375, 0x037A, 0x0384, 0x0385, 0x0387 => true,
        0x0483...0x0489, 0x0591...0x05BD, 0x05BF, 0x05C1, 0x05C2, 0x05C4, 0x05C5, 0x05C7, 0x05F4 => true,
        0x0610...0x061A, 0x061C, 0x0640, 0x064B...0x065F, 0x0670, 0x06D6...0x06DD, 0x06DF...0x06E8, 0x06EA...0x06ED => true,
        0x0900...0x0903, 0x093A...0x094F, 0x0951...0x0957, 0x0962, 0x0963 => true,
        0x1AB0...0x1AFF, 0x1DC0...0x1DFF => true,
        0x200B...0x200F, 0x2018, 0x2019, 0x2024, 0x2027, 0x202A...0x202E, 0x2060...0x2064, 0x2066...0x206F => true,
        0x20D0...0x20FF, 0x2C7C, 0x2C7D, 0x3005, 0x3031...0x3035, 0x303B, 0x309B...0x309E, 0x30FC...0x30FE => true,
        0xFE00...0xFE0F, 0xFE13, 0xFE20...0xFE2F, 0xFE52, 0xFE55, 0xFEFF, 0xFF07, 0xFF0E, 0xFF1A, 0xFF3E, 0xFF40, 0xFF70, 0xFF9E, 0xFF9F => true,
        0xE0001, 0xE0020...0xE007F, 0xE0100...0xE01EF => true,
        else => false,
    };
}

fn native_mb_check_encoding(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = true });
    if (args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const s = args[0].string.bytes();
    // encoding arg defaults to mb_internal_encoding (UTF-8)
    var is_ascii = false;
    if (args.len >= 2 and args[1] == .string) {
        const enc = args[1].string.bytes();
        // case-insensitive ASCII check
        if (enc.len >= 5) {
            var lo: [16]u8 = undefined;
            const cap = @min(enc.len, lo.len);
            for (enc[0..cap], 0..) |c, i| lo[i] = std.ascii.toLower(c);
            const l = lo[0..cap];
            if (std.mem.eql(u8, l, "ascii") or std.mem.eql(u8, l, "us-ascii") or std.mem.eql(u8, l, "7bit")) is_ascii = true;
        }
    }
    if (is_ascii) {
        for (s) |b| if (b >= 0x80) return NativeResult.scalar(.{ .bool = false });
        return NativeResult.scalar(.{ .bool = true });
    }
    var i: usize = 0;
    while (i < s.len) {
        const byte = s[i];
        if (byte < 0x80) {
            i += 1;
            continue;
        }
        const len = std.unicode.utf8ByteSequenceLength(byte) catch return NativeResult.scalar(.{ .bool = false });
        if (i + len > s.len) return NativeResult.scalar(.{ .bool = false });
        _ = std.unicode.utf8Decode(s[i..][0..len]) catch return NativeResult.scalar(.{ .bool = false });
        i += len;
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn utfCaseConvert(ctx: *NativeContext, s: []const u8, to_upper: bool) !Value.String {
    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);
    var i: usize = 0;
    while (i < s.len) {
        const byte = s[i];
        if (byte < 0x80) {
            try buf.append(ctx.allocator, if (to_upper) std.ascii.toUpper(byte) else std.ascii.toLower(byte));
            i += 1;
        } else {
            // an ill-formed sequence decodes to '?', as php's mbstring does
            const step = utf8Step(s, i);
            if (!step.valid) {
                try buf.append(ctx.allocator, '?');
                i += step.len;
                continue;
            }
            const len = step.len;
            const cp = std.unicode.utf8Decode(s[i..][0..len]) catch {
                try buf.appendSlice(ctx.allocator, s[i .. i + len]);
                i += len;
                continue;
            };
            // expansion mappings: one codepoint to multiple codepoints
            if (to_upper) {
                if (caseExpansionUpper(cp)) |seq| {
                    try buf.appendSlice(ctx.allocator, seq);
                    i += len;
                    continue;
                }
            }
            const mapped = if (to_upper) unicodeToUpper(cp) else unicodeToLower(cp);
            var enc: [4]u8 = undefined;
            const enc_len = std.unicode.utf8Encode(mapped, &enc) catch {
                try buf.appendSlice(ctx.allocator, s[i .. i + len]);
                i += len;
                continue;
            };
            try buf.appendSlice(ctx.allocator, enc[0..enc_len]);
            i += len;
        }
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    return Value.String.adopt(ctx.allocator, result);
}

fn caseExpansionUpper(cp: u21) ?[]const u8 {
    return switch (cp) {
        0x00DF => "SS", // sharp s -> SS
        0x0149 => "\xCA\xBCN", // n preceded by apostrophe
        0x01F0 => "J\xCC\x8C", // j with caron
        0x0390 => "\xCE\x99\xCC\x88\xCC\x81", // greek iota with dialytika tonos
        0x03B0 => "\xCE\xA5\xCC\x88\xCC\x81", // greek upsilon with dialytika tonos
        0x0587 => "\xD4\xB5\xD5\x92", // armenian small ligature ech yiwn
        0xFB00 => "FF",
        0xFB01 => "FI",
        0xFB02 => "FL",
        0xFB03 => "FFI",
        0xFB04 => "FFL",
        0xFB05 => "ST",
        0xFB06 => "ST",
        else => null,
    };
}

fn unicodeToUpper(cp: u21) u21 {
    // latin-1 supplement: a-with-grave through o-with-diaeresis
    if (cp >= 0x00E0 and cp <= 0x00F6) return cp - 0x20;
    // latin-1 supplement: o-with-slash through thorn
    if (cp >= 0x00F8 and cp <= 0x00FE) return cp - 0x20;
    // latin extended-a: pairing alternates per subrange. 0100-0137 and
    // 014A-0177 pair even-upper/odd-lower; 0139-0148 and 0179-017E pair
    // odd-upper/even-lower. 0138 (kra) and 0149 have no uppercase pair
    if (cp >= 0x0100 and cp <= 0x0137 and cp % 2 == 1) return cp - 1;
    if (cp >= 0x014A and cp <= 0x0177 and cp % 2 == 1) return cp - 1;
    if (cp >= 0x013A and cp <= 0x0148 and cp % 2 == 0) return cp - 1;
    if (cp >= 0x017A and cp <= 0x017E and cp % 2 == 0) return cp - 1;
    switch (cp) {
        0x00FF => return 0x0178, // y with diaeresis
        0x01C6, 0x01C5 => return 0x01C4, // dž digraph
        0x01C9, 0x01C8 => return 0x01C7, // lj digraph
        0x01CC, 0x01CB => return 0x01CA, // nj digraph
        0x01F3, 0x01F2 => return 0x01F1, // dz digraph
        else => {},
    }
    // greek lowercase to uppercase (03B1-03C9 -> 0391-03A9)
    if (cp >= 0x03B1 and cp <= 0x03C9) return cp - 0x20;
    // greek precomposed lowercase letters with tonos
    switch (cp) {
        0x03AC => return 0x0386, // ά -> Ά
        0x03AD => return 0x0388, // έ -> Έ
        0x03AE => return 0x0389, // ή -> Ή
        0x03AF => return 0x038A, // ί -> Ί
        0x03CC => return 0x038C, // ό -> Ό
        0x03CD => return 0x038E, // ύ -> Ύ
        0x03CE => return 0x038F, // ώ -> Ώ
        0x03CA => return 0x03AA, // ϊ -> Ϊ
        0x03CB => return 0x03AB, // ϋ -> Ϋ
        else => {},
    }
    // cyrillic lowercase to uppercase (0430-044F -> 0410-042F)
    if (cp >= 0x0430 and cp <= 0x044F) return cp - 0x20;
    return cp;
}

pub fn unicodeToLower(cp: u21) u21 {
    // latin-1 supplement: A-with-grave through O-with-diaeresis
    if (cp >= 0x00C0 and cp <= 0x00D6) return cp + 0x20;
    // latin-1 supplement: O-with-slash through Thorn
    if (cp >= 0x00D8 and cp <= 0x00DE) return cp + 0x20;
    // latin extended-a: pairing alternates per subrange (see unicodeToUpper)
    if (cp >= 0x0100 and cp <= 0x0137 and cp % 2 == 0) return cp + 1;
    if (cp >= 0x014A and cp <= 0x0177 and cp % 2 == 0) return cp + 1;
    if (cp >= 0x0139 and cp <= 0x0147 and cp % 2 == 1) return cp + 1;
    if (cp >= 0x0179 and cp <= 0x017D and cp % 2 == 1) return cp + 1;
    switch (cp) {
        0x0178 => return 0x00FF, // Y with diaeresis
        0x01C4, 0x01C5 => return 0x01C6, // DŽ digraph
        0x01C7, 0x01C8 => return 0x01C9, // LJ digraph
        0x01CA, 0x01CB => return 0x01CC, // NJ digraph
        0x01F1, 0x01F2 => return 0x01F3, // DZ digraph
        else => {},
    }
    // greek uppercase to lowercase (0391-03A9 -> 03B1-03C9)
    if (cp >= 0x0391 and cp <= 0x03A9) return cp + 0x20;
    // greek precomposed uppercase letters with tonos
    switch (cp) {
        0x0386 => return 0x03AC,
        0x0388 => return 0x03AD,
        0x0389 => return 0x03AE,
        0x038A => return 0x03AF,
        0x038C => return 0x03CC,
        0x038E => return 0x03CD,
        0x038F => return 0x03CE,
        0x03AA => return 0x03CA,
        0x03AB => return 0x03CB,
        else => {},
    }
    // cyrillic uppercase to lowercase (0410-042F -> 0430-044F)
    if (cp >= 0x0410 and cp <= 0x042F) return cp + 0x20;
    return cp;
}

fn native_mb_detect_encoding(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const s = args[0].string.bytes();
    // walk the candidate list in order and return the first encoding the
    // input is valid for. matches PHP behavior - ASCII before UTF-8 in the
    // candidate list will report ASCII for plain ASCII text
    const Probe = struct {
        fn isAscii(input: []const u8) bool {
            for (input) |b| if (b > 0x7f) return false;
            return true;
        }
        fn isUtf8(input: []const u8) bool {
            var i: usize = 0;
            while (i < input.len) {
                const b = input[i];
                if (b < 0x80) {
                    i += 1;
                    continue;
                }
                const len: usize = if ((b & 0xe0) == 0xc0) 2 else if ((b & 0xf0) == 0xe0) 3 else if ((b & 0xf8) == 0xf0) 4 else return false;
                if (i + len > input.len) return false;
                var j: usize = 1;
                while (j < len) : (j += 1) if ((input[i + j] & 0xc0) != 0x80) return false;
                i += len;
            }
            return true;
        }
        fn match(input: []const u8, candidate: []const u8) ?[]const u8 {
            if (isAsciiEncoding(candidate)) {
                if (isAscii(input)) return "ASCII";
            } else if (isUtf8Encoding(candidate)) {
                if (isUtf8(input)) return "UTF-8";
            } else if (isLatin1Encoding(candidate)) {
                return "ISO-8859-1";
            }
            return null;
        }
    };

    if (args.len >= 2 and args[1] == .array) {
        for (args[1].array.entries.items) |entry| {
            if (entry.value == .string) {
                if (Probe.match(s, entry.value.string.bytes())) |hit| return NativeResult.copyString(ctx.allocator, hit);
            }
        }
        return NativeResult.scalar(.{ .bool = false });
    }
    if (args.len >= 2 and args[1] == .string) {
        if (Probe.match(s, args[1].string.bytes())) |hit| return NativeResult.copyString(ctx.allocator, hit);
        return NativeResult.scalar(.{ .bool = false });
    }
    if (Probe.isAscii(s)) return NativeResult.literal("ASCII");
    if (Probe.isUtf8(s)) return NativeResult.literal("UTF-8");
    return NativeResult.scalar(.{ .bool = false });
}

fn encodingMatches(name: []const u8, options: anytype) bool {
    var buf: [32]u8 = undefined;
    const n = @min(name.len, buf.len);
    for (0..n) |i| buf[i] = std.ascii.toLower(name[i]);
    const lower = buf[0..n];
    inline for (options) |opt| {
        if (std.mem.eql(u8, lower, opt)) return true;
    }
    return false;
}

fn isUtf8Encoding(name: []const u8) bool {
    return encodingMatches(name, .{ "utf-8", "utf8" });
}

fn isLatin1Encoding(name: []const u8) bool {
    return encodingMatches(name, .{ "iso-8859-1", "iso8859-1", "latin1" });
}

fn isAsciiEncoding(name: []const u8) bool {
    return encodingMatches(name, .{ "ascii", "us-ascii" });
}

fn isUtf16Encoding(name: []const u8) bool {
    return encodingMatches(name, .{ "utf-16", "utf16", "utf-16be", "utf16be", "utf-16le", "utf16le" });
}

fn isUtf16LE(name: []const u8) bool {
    return encodingMatches(name, .{ "utf-16le", "utf16le" });
}

fn isUtf32Encoding(name: []const u8) bool {
    return encodingMatches(name, .{ "utf-32", "utf32", "utf-32be", "utf32be", "utf-32le", "utf32le" });
}

fn isUtf32LE(name: []const u8) bool {
    return encodingMatches(name, .{ "utf-32le", "utf32le" });
}

fn convertUtf8ToUtf16(allocator: std.mem.Allocator, input: []const u8, little_endian: bool) ![]u8 {
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < input.len) {
        const b = input[i];
        const len = utf8CharLen(b);
        if (i + len > input.len) break;
        var cp: u21 = 0;
        switch (len) {
            1 => cp = b,
            2 => cp = (@as(u21, b & 0x1f) << 6) | @as(u21, input[i + 1] & 0x3f),
            3 => cp = (@as(u21, b & 0x0f) << 12) | (@as(u21, input[i + 1] & 0x3f) << 6) | @as(u21, input[i + 2] & 0x3f),
            4 => cp = (@as(u21, b & 0x07) << 18) | (@as(u21, input[i + 1] & 0x3f) << 12) | (@as(u21, input[i + 2] & 0x3f) << 6) | @as(u21, input[i + 3] & 0x3f),
            else => cp = '?',
        }
        if (cp <= 0xFFFF) {
            try appendU16(&out, allocator, @intCast(cp), little_endian);
        } else {
            const adjusted: u21 = cp - 0x10000;
            const high: u16 = 0xD800 + @as(u16, @intCast(adjusted >> 10));
            const low: u16 = 0xDC00 + @as(u16, @intCast(adjusted & 0x3FF));
            try appendU16(&out, allocator, high, little_endian);
            try appendU16(&out, allocator, low, little_endian);
        }
        i += len;
    }
    return try out.toOwnedSlice(allocator);
}

fn appendU16(out: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, val: u16, little_endian: bool) !void {
    if (little_endian) {
        try out.append(allocator, @intCast(val & 0xFF));
        try out.append(allocator, @intCast(val >> 8));
    } else {
        try out.append(allocator, @intCast(val >> 8));
        try out.append(allocator, @intCast(val & 0xFF));
    }
}

fn convertUtf16ToUtf8(allocator: std.mem.Allocator, input: []const u8, little_endian: bool) ![]u8 {
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i + 1 < input.len) : (i += 2) {
        const hi: u16 = if (little_endian)
            @as(u16, input[i]) | (@as(u16, input[i + 1]) << 8)
        else
            (@as(u16, input[i]) << 8) | @as(u16, input[i + 1]);
        var cp: u21 = hi;
        if (hi >= 0xD800 and hi <= 0xDBFF and i + 3 < input.len) {
            const lo: u16 = if (little_endian)
                @as(u16, input[i + 2]) | (@as(u16, input[i + 3]) << 8)
            else
                (@as(u16, input[i + 2]) << 8) | @as(u16, input[i + 3]);
            if (lo >= 0xDC00 and lo <= 0xDFFF) {
                cp = 0x10000 + ((@as(u21, hi) - 0xD800) << 10) + (@as(u21, lo) - 0xDC00);
                i += 2;
            }
        }
        try appendUtf8(&out, allocator, cp);
    }
    return try out.toOwnedSlice(allocator);
}

fn appendUtf8(out: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, cp: u21) !void {
    if (cp < 0x80) {
        try out.append(allocator, @intCast(cp));
    } else if (cp < 0x800) {
        try out.append(allocator, @intCast(0xc0 | (cp >> 6)));
        try out.append(allocator, @intCast(0x80 | (cp & 0x3f)));
    } else if (cp < 0x10000) {
        try out.append(allocator, @intCast(0xe0 | (cp >> 12)));
        try out.append(allocator, @intCast(0x80 | ((cp >> 6) & 0x3f)));
        try out.append(allocator, @intCast(0x80 | (cp & 0x3f)));
    } else {
        try out.append(allocator, @intCast(0xf0 | (cp >> 18)));
        try out.append(allocator, @intCast(0x80 | ((cp >> 12) & 0x3f)));
        try out.append(allocator, @intCast(0x80 | ((cp >> 6) & 0x3f)));
        try out.append(allocator, @intCast(0x80 | (cp & 0x3f)));
    }
}

fn convertUtf8ToUtf32(allocator: std.mem.Allocator, input: []const u8, little_endian: bool) ![]u8 {
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < input.len) {
        const b = input[i];
        const len = utf8CharLen(b);
        if (i + len > input.len) break;
        var cp: u32 = 0;
        switch (len) {
            1 => cp = b,
            2 => cp = (@as(u32, b & 0x1f) << 6) | @as(u32, input[i + 1] & 0x3f),
            3 => cp = (@as(u32, b & 0x0f) << 12) | (@as(u32, input[i + 1] & 0x3f) << 6) | @as(u32, input[i + 2] & 0x3f),
            4 => cp = (@as(u32, b & 0x07) << 18) | (@as(u32, input[i + 1] & 0x3f) << 12) | (@as(u32, input[i + 2] & 0x3f) << 6) | @as(u32, input[i + 3] & 0x3f),
            else => cp = '?',
        }
        try appendU32(&out, allocator, cp, little_endian);
        i += len;
    }
    return try out.toOwnedSlice(allocator);
}

fn appendU32(out: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, val: u32, little_endian: bool) !void {
    var bytes: [4]u8 = undefined;
    if (little_endian) {
        bytes[0] = @intCast(val & 0xFF);
        bytes[1] = @intCast((val >> 8) & 0xFF);
        bytes[2] = @intCast((val >> 16) & 0xFF);
        bytes[3] = @intCast((val >> 24) & 0xFF);
    } else {
        bytes[0] = @intCast((val >> 24) & 0xFF);
        bytes[1] = @intCast((val >> 16) & 0xFF);
        bytes[2] = @intCast((val >> 8) & 0xFF);
        bytes[3] = @intCast(val & 0xFF);
    }
    try out.appendSlice(allocator, &bytes);
}

fn convertUtf32ToUtf8(allocator: std.mem.Allocator, input: []const u8, little_endian: bool) ![]u8 {
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i + 3 < input.len) : (i += 4) {
        const cp: u32 = if (little_endian)
            @as(u32, input[i]) | (@as(u32, input[i + 1]) << 8) | (@as(u32, input[i + 2]) << 16) | (@as(u32, input[i + 3]) << 24)
        else
            (@as(u32, input[i]) << 24) | (@as(u32, input[i + 1]) << 16) | (@as(u32, input[i + 2]) << 8) | @as(u32, input[i + 3]);
        if (cp > 0x10FFFF) {
            try appendUtf8(&out, allocator, '?');
        } else {
            try appendUtf8(&out, allocator, @intCast(cp));
        }
    }
    return try out.toOwnedSlice(allocator);
}

fn convertUtf8ToLatin1(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < input.len) {
        const b = input[i];
        if (b < 0x80) {
            try out.append(allocator, b);
            i += 1;
        } else if ((b & 0xe0) == 0xc0 and i + 1 < input.len) {
            const b2 = input[i + 1];
            const cp: u21 = (@as(u21, b & 0x1f) << 6) | @as(u21, b2 & 0x3f);
            try out.append(allocator, if (cp < 0x100) @intCast(cp) else '?');
            i += 2;
        } else {
            try out.append(allocator, '?');
            i += utf8CharLen(b);
        }
    }
    return try out.toOwnedSlice(allocator);
}

fn convertLatin1ToUtf8(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(allocator);
    for (input) |b| {
        if (b < 0x80) {
            try out.append(allocator, b);
        } else {
            try out.append(allocator, 0xc0 | (b >> 6));
            try out.append(allocator, 0x80 | (b & 0x3f));
        }
    }
    return try out.toOwnedSlice(allocator);
}

fn native_utf8_encode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const out = convertLatin1ToUtf8(ctx.allocator, args[0].string.bytes()) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

fn native_utf8_decode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const out = convertUtf8ToLatin1(ctx.allocator, args[0].string.bytes()) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

fn convertVarEncoding(ctx: *NativeContext, val: Value, to: []const u8, from: []const u8) RuntimeError!NativeResult {
    return switch (val) {
        .string => try native_mb_convert_encoding(ctx, &.{ val, .{ .string = Value.String.borrowed(to) }, .{ .string = Value.String.borrowed(from) } }),
        .array => blk: {
            const arr = try ctx.createArray();
            for (val.array.entries.items) |e| {
                const converted = try convertVarEncoding(ctx, e.value, to, from);
                defer if (converted.value == .string) converted.value.string.release();
                try arr.set(ctx.allocator, e.key, converted.value);
            }
            break :blk NativeResult.borrowed(.{ .array = arr });
        },
        else => NativeResult.borrowed(val),
    };
}

// mb_convert_variables(string $to, array|string $from, mixed &$var, mixed &...$vars):
// converts the encoding of each var IN PLACE (by reference, recursing into
// arrays) and returns the source encoding. Symfony Console's splitStringByWidth
// calls this on its line array - without it, error rendering throws and cascades
fn native_mb_convert_variables(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 3 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const to = args[0].string.bytes();
    // $from may be a comma-separated candidate list or an array of candidates;
    // take the first (detection among ASCII/UTF-8/Latin1 is near-identity anyway)
    const from: []const u8 = blk: {
        if (args[1] == .string) {
            const s = args[1].string.bytes();
            if (std.mem.indexOfScalar(u8, s, ',')) |c| break :blk std.mem.trim(u8, s[0..c], " ");
            break :blk s;
        }
        if (args[1] == .array and args[1].array.entries.items.len > 0) {
            const f = args[1].array.entries.items[0].value;
            if (f == .string) break :blk f.string.bytes();
        }
        break :blk "UTF-8";
    };
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const converted = try convertVarEncoding(ctx, args[i], to, from);
        defer if (converted.value == .string) converted.value.string.release();
        ctx.setCallerVar(i, args.len, converted.value);
    }
    return NativeResult.copyString(ctx.allocator, from);
}

fn native_mb_convert_encoding(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const to = args[1].string.bytes();
    const from: []const u8 = if (args.len >= 3 and args[2] == .string) args[2].string.bytes() else "UTF-8";
    // ill-formed UTF-8 converts as '?', whatever the target
    const sanitized = if (isUtf8Encoding(from)) try sanitizeUtf8(ctx.allocator, args[0].string.bytes()) else null;
    defer if (sanitized) |b| ctx.allocator.free(b);
    const input = sanitized orelse args[0].string.bytes();
    if (sanitized != null and isUtf8Encoding(to)) return NativeResult.copyString(ctx.allocator, input);

    if ((isUtf8Encoding(from) and isUtf8Encoding(to)) or
        (isLatin1Encoding(from) and isLatin1Encoding(to)) or
        (isAsciiEncoding(from) and isAsciiEncoding(to)))
    {
        return NativeResult.share(args[0]);
    }
    if (isUtf8Encoding(from) and isLatin1Encoding(to)) {
        const out = convertUtf8ToLatin1(ctx.allocator, input) catch return NativeResult.scalar(.{ .bool = false });
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
    }
    if (isLatin1Encoding(from) and isUtf8Encoding(to)) {
        const out = convertLatin1ToUtf8(ctx.allocator, input) catch return NativeResult.scalar(.{ .bool = false });
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
    }
    if (isAsciiEncoding(from) and (isUtf8Encoding(to) or isLatin1Encoding(to))) {
        return NativeResult.share(args[0]); // ascii is a subset of both
    }
    if ((isUtf8Encoding(from) or isLatin1Encoding(from)) and isAsciiEncoding(to)) {
        // strip non-ascii bytes
        var out = std.ArrayListUnmanaged(u8).empty;
        errdefer out.deinit(ctx.allocator);
        var i: usize = 0;
        while (i < input.len) {
            const b = input[i];
            if (b < 0x80) {
                try out.append(ctx.allocator, b);
                i += 1;
            } else if (isUtf8Encoding(from)) {
                try out.append(ctx.allocator, '?');
                i += utf8CharLen(b);
            } else {
                try out.append(ctx.allocator, '?');
                i += 1;
            }
        }
        const owned = try out.toOwnedSlice(ctx.allocator);
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, owned));
    }
    // UTF-8/Latin1/ASCII <-> UTF-16{,BE,LE}. "UTF-16" without suffix is BE
    if (isUtf8Encoding(from) and isUtf16Encoding(to)) {
        const out = convertUtf8ToUtf16(ctx.allocator, input, isUtf16LE(to)) catch return NativeResult.scalar(.{ .bool = false });
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
    }
    if (isUtf16Encoding(from) and isUtf8Encoding(to)) {
        const out = convertUtf16ToUtf8(ctx.allocator, input, isUtf16LE(from)) catch return NativeResult.scalar(.{ .bool = false });
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
    }
    if (isUtf8Encoding(from) and isUtf32Encoding(to)) {
        const out = convertUtf8ToUtf32(ctx.allocator, input, isUtf32LE(to)) catch return NativeResult.scalar(.{ .bool = false });
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
    }
    if (isUtf32Encoding(from) and isUtf8Encoding(to)) {
        const out = convertUtf32ToUtf8(ctx.allocator, input, isUtf32LE(from)) catch return NativeResult.scalar(.{ .bool = false });
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
    }
    if (isLatin1Encoding(from) and isUtf16Encoding(to)) {
        const tmp = convertLatin1ToUtf8(ctx.allocator, input) catch return NativeResult.scalar(.{ .bool = false });
        defer ctx.allocator.free(tmp);
        const out = convertUtf8ToUtf16(ctx.allocator, tmp, isUtf16LE(to)) catch return NativeResult.scalar(.{ .bool = false });
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
    }
    if (isUtf16Encoding(from) and isLatin1Encoding(to)) {
        const tmp = convertUtf16ToUtf8(ctx.allocator, input, isUtf16LE(from)) catch return NativeResult.scalar(.{ .bool = false });
        defer ctx.allocator.free(tmp);
        const out = convertUtf8ToLatin1(ctx.allocator, tmp) catch return NativeResult.scalar(.{ .bool = false });
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
    }
    // unknown encoding pair - pass through
    return NativeResult.share(args[0]);
}

fn native_iconv(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 3 or args[0] != .string or args[1] != .string or args[2] != .string) return NativeResult.scalar(.{ .bool = false });
    const from = args[0].string.bytes();
    const to_raw = args[1].string.bytes();
    // iconv supports "//IGNORE" and "//TRANSLIT" suffixes after the target
    // encoding. IGNORE drops un-convertible chars instead of substituting
    // with '?'; TRANSLIT does a best-effort replacement (currently mapped
    // to IGNORE since the full transliteration tables aren't shipped here)
    var to = to_raw;
    var ignore = false;
    var translit = false;
    if (std.mem.indexOf(u8, to_raw, "//")) |sep| {
        to = to_raw[0..sep];
        const suffix = to_raw[sep + 2 ..];
        if (std.mem.indexOf(u8, suffix, "IGNORE") != null) ignore = true;
        if (std.mem.indexOf(u8, suffix, "TRANSLIT") != null) translit = true;
    }

    // ill-formed UTF-8 input fails the conversion; //IGNORE skips an illegal
    // sequence but never one cut short by the end of the input
    var cleaned: std.ArrayListUnmanaged(u8) = .empty;
    defer cleaned.deinit(ctx.allocator);
    var source = args[2];
    if (isUtf8Encoding(from) and !std.unicode.utf8ValidateSlice(args[2].string.bytes())) {
        const raw = args[2].string.bytes();
        var i: usize = 0;
        while (i < raw.len) {
            const step = utf8Step(raw, i);
            if (!step.valid) {
                if (step.truncated) {
                    try ctx.vm.raiseError(8, "iconv(): Detected an incomplete multibyte character in input string");
                    return NativeResult.scalar(.{ .bool = false });
                }
                if (!ignore) {
                    try ctx.vm.raiseError(8, "iconv(): Detected an illegal character in input string");
                    return NativeResult.scalar(.{ .bool = false });
                }
            } else try cleaned.appendSlice(ctx.allocator, raw[i .. i + step.len]);
            i += step.len;
        }
        source = .{ .string = Value.String.borrowed(cleaned.items) };
    }

    // a character the target cannot hold fails the conversion unless
    // //TRANSLIT approximates it or //IGNORE drops it
    var representable: std.ArrayListUnmanaged(u8) = .empty;
    defer representable.deinit(ctx.allocator);
    if (!translit and isUtf8Encoding(from) and (isLatin1Encoding(to) or isAsciiEncoding(to))) {
        const limit: u21 = if (isAsciiEncoding(to)) 0x7F else 0xFF;
        const input = source.string.bytes();
        var i: usize = 0;
        while (i < input.len) {
            const len = utf8Step(input, i).len;
            const cp: u21 = if (len == 1) input[i] else std.unicode.utf8Decode(input[i .. i + len]) catch unreachable;
            if (cp <= limit) {
                try representable.appendSlice(ctx.allocator, input[i .. i + len]);
            } else if (!ignore) {
                try ctx.vm.raiseError(8, "iconv(): Detected an illegal character in input string");
                return NativeResult.scalar(.{ .bool = false });
            }
            i += len;
        }
        source = .{ .string = Value.String.borrowed(representable.items) };
    }

    // fast path for IGNORE/TRANSLIT when going to ASCII: drop non-ASCII bytes
    // directly so callers don't get the '?' substitutions
    if ((ignore or translit) and isAsciiEncoding(to) and (isUtf8Encoding(from) or isLatin1Encoding(from))) {
        const input = source.string.bytes();
        var out = std.ArrayListUnmanaged(u8).empty;
        errdefer out.deinit(ctx.allocator);
        var i: usize = 0;
        while (i < input.len) {
            const b = input[i];
            if (b < 0x80) {
                try out.append(ctx.allocator, b);
                i += 1;
            } else if (isUtf8Encoding(from)) {
                i += utf8CharLen(b);
            } else {
                i += 1;
            }
        }
        const owned = try out.toOwnedSlice(ctx.allocator);
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, owned));
    }

    const args2 = [_]Value{ source, .{ .string = Value.String.borrowed(to) }, .{ .string = Value.String.borrowed(from) } };
    return try native_mb_convert_encoding(ctx, &args2);
}

fn native_mb_strpos(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const haystack = args[0].string.bytes();
    const needle = args[1].string.bytes();
    const byte_offset: usize = if (args.len >= 3) blk: {
        const off = Value.toInt(args[2]);
        if (off < 0) break :blk 0;
        var bo: usize = 0;
        var chars: usize = 0;
        while (bo < haystack.len and chars < @as(usize, @intCast(off))) {
            bo += utf8CharLen(haystack[bo]);
            chars += 1;
        }
        break :blk bo;
    } else 0;
    if (byte_offset >= haystack.len) return NativeResult.scalar(.{ .bool = false });
    if (std.mem.indexOf(u8, haystack[byte_offset..], needle)) |pos| {
        var char_pos: i64 = 0;
        var j: usize = 0;
        while (j < byte_offset + pos) {
            j += utf8CharLen(haystack[j]);
            char_pos += 1;
        }
        return NativeResult.scalar(.{ .int = char_pos });
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn native_mb_strrpos(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const haystack = args[0].string.bytes();
    const needle = args[1].string.bytes();
    if (std.mem.lastIndexOf(u8, haystack, needle)) |pos| {
        var char_pos: i64 = 0;
        var j: usize = 0;
        while (j < pos) {
            j += utf8CharLen(haystack[j]);
            char_pos += 1;
        }
        return NativeResult.scalar(.{ .int = char_pos });
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn native_mb_substr_count(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .int = 0 });
    const haystack = args[0].string.bytes();
    const needle = args[1].string.bytes();
    if (needle.len == 0) {
        try ctx.vm.setPendingException("ValueError", "mb_substr_count(): Argument #2 ($needle) must not be empty");
        return error.RuntimeError;
    }
    var count: i64 = 0;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) {
        if (std.mem.eql(u8, haystack[i .. i + needle.len], needle)) {
            count += 1;
            i += needle.len;
        } else {
            i += 1;
        }
    }
    return NativeResult.scalar(.{ .int = count });
}

fn native_mb_internal_encoding(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.literal("UTF-8");
}

fn native_mb_substitute_character(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = true });
}

fn cjkWidth(cp: u21) usize {
    // East Asian Wide / Fullwidth ranges (subset matching PHP's mb_strwidth)
    if (cp >= 0x1100 and cp <= 0x115F) return 2; // Hangul Jamo
    if (cp >= 0x2E80 and cp <= 0x303E) return 2; // CJK radicals, kangxi, ideo desc
    if (cp >= 0x3041 and cp <= 0x33FF) return 2; // Hiragana, Katakana, Bopomofo, etc.
    if (cp >= 0x3400 and cp <= 0x4DBF) return 2; // CJK Ext A
    if (cp >= 0x4E00 and cp <= 0x9FFF) return 2; // CJK Unified Ideographs
    if (cp >= 0xA000 and cp <= 0xA4CF) return 2; // Yi
    if (cp >= 0xAC00 and cp <= 0xD7A3) return 2; // Hangul Syllables
    if (cp >= 0xF900 and cp <= 0xFAFF) return 2; // CJK Compatibility Ideographs
    if (cp >= 0xFE30 and cp <= 0xFE4F) return 2; // CJK Compatibility Forms
    if (cp >= 0xFF00 and cp <= 0xFF60) return 2; // Fullwidth Forms
    if (cp >= 0xFFE0 and cp <= 0xFFE6) return 2; // Fullwidth signs
    if (cp >= 0x20000 and cp <= 0x2FFFD) return 2; // CJK Ext B-F
    if (cp >= 0x30000 and cp <= 0x3FFFD) return 2;
    return 1;
}

fn native_mb_strwidth(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .int = 0 });
    const s = args[0].string.bytes();
    var width: i64 = 0;
    var i: usize = 0;
    while (i < s.len) {
        const len = std.unicode.utf8ByteSequenceLength(s[i]) catch 1;
        if (i + len > s.len) {
            width += 1;
            i += 1;
            continue;
        }
        const cp = std.unicode.utf8Decode(s[i .. i + len]) catch {
            width += 1;
            i += 1;
            continue;
        };
        width += @intCast(cjkWidth(cp));
        i += len;
    }
    return NativeResult.scalar(.{ .int = width });
}

fn parseEntityMap(arr: *PhpArray) ?[4]i64 {
    if (arr.entries.items.len < 4) return null;
    var out: [4]i64 = .{ 0, 0, 0, 0 };
    for (arr.entries.items[0..4], 0..) |entry, i| out[i] = Value.toInt(entry.value);
    return out;
}

fn native_mb_encode_numericentity(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .array) return if (args.len > 0) NativeResult.share(args[0]) else NativeResult.literal("");
    const s = args[0].string.bytes();
    const map = parseEntityMap(args[1].array) orelse return NativeResult.share(args[0]);
    const hex = args.len >= 4 and args[3].isTruthy();

    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);
    var i: usize = 0;
    while (i < s.len) {
        const len = std.unicode.utf8ByteSequenceLength(s[i]) catch 1;
        if (i + len > s.len) {
            try buf.append(ctx.allocator, s[i]);
            i += 1;
            continue;
        }
        const cp = std.unicode.utf8Decode(s[i .. i + len]) catch {
            try buf.append(ctx.allocator, s[i]);
            i += 1;
            continue;
        };
        const cp_i: i64 = @intCast(cp);
        if (cp_i >= map[0] and cp_i <= map[1]) {
            const value = (cp_i - map[2]) & map[3];
            var num_buf: [32]u8 = undefined;
            const written = if (hex)
                std.fmt.bufPrint(&num_buf, "&#x{X};", .{value}) catch null
            else
                std.fmt.bufPrint(&num_buf, "&#{d};", .{value}) catch null;
            if (written) |w| {
                try buf.appendSlice(ctx.allocator, w);
            } else {
                try buf.appendSlice(ctx.allocator, s[i .. i + len]);
                i += len;
                continue;
            }
        } else {
            try buf.appendSlice(ctx.allocator, s[i .. i + len]);
        }
        i += len;
    }
    const out = try buf.toOwnedSlice(ctx.allocator);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

fn native_mb_decode_numericentity(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .array) return if (args.len > 0) NativeResult.share(args[0]) else NativeResult.literal("");
    const s = args[0].string.bytes();
    const map = parseEntityMap(args[1].array) orelse return NativeResult.share(args[0]);

    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '&' and i + 1 < s.len and s[i + 1] == '#') {
            var j = i + 2;
            const is_hex = j < s.len and (s[j] == 'x' or s[j] == 'X');
            if (is_hex) j += 1;
            const num_start = j;
            while (j < s.len) : (j += 1) {
                const c = s[j];
                const ok = if (is_hex) std.ascii.isHex(c) else std.ascii.isDigit(c);
                if (!ok) break;
            }
            if (j > num_start and j < s.len and s[j] == ';') {
                const base: u8 = if (is_hex) 16 else 10;
                const value = std.fmt.parseInt(i64, s[num_start..j], base) catch {
                    try buf.append(ctx.allocator, s[i]);
                    i += 1;
                    continue;
                };
                const cp_i = (value & map[3]) + map[2];
                if (cp_i >= map[0] and cp_i <= map[1] and cp_i >= 0 and cp_i <= 0x10FFFF) {
                    var enc: [4]u8 = undefined;
                    const elen = std.unicode.utf8Encode(@intCast(cp_i), &enc) catch 0;
                    if (elen > 0) {
                        try buf.appendSlice(ctx.allocator, enc[0..elen]);
                        i = j + 1;
                        continue;
                    }
                }
            }
        }
        try buf.append(ctx.allocator, s[i]);
        i += 1;
    }
    const out = try buf.toOwnedSlice(ctx.allocator);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

fn native_mb_chr(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    const cp_int = Value.toInt(args[0]);
    if (cp_int < 0 or cp_int > 0x10FFFF) return NativeResult.scalar(.{ .bool = false });
    const cp: u21 = @intCast(cp_int);
    var buf: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(cp, &buf) catch return NativeResult.scalar(.{ .bool = false });
    const out = try ctx.allocator.dupe(u8, buf[0..n]);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

fn native_mb_ord(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const s = args[0].string.bytes();
    if (s.len == 0) {
        try ctx.vm.setPendingException("ValueError", "mb_ord(): Argument #1 ($string) must not be empty");
        return error.RuntimeError;
    }
    const len = std.unicode.utf8ByteSequenceLength(s[0]) catch return NativeResult.scalar(.{ .bool = false });
    if (len > s.len) return NativeResult.scalar(.{ .bool = false });
    const cp = std.unicode.utf8Decode(s[0..len]) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(cp) });
}

fn lowerCpUtf8(s: []const u8, i: usize) struct { cp: u21, len: usize } {
    const b = s[i];
    if (b < 0x80) return .{ .cp = std.ascii.toLower(b), .len = 1 };
    const len = std.unicode.utf8ByteSequenceLength(b) catch return .{ .cp = b, .len = 1 };
    if (i + len > s.len) return .{ .cp = b, .len = 1 };
    const cp = std.unicode.utf8Decode(s[i .. i + len]) catch return .{ .cp = b, .len = 1 };
    return .{ .cp = unicodeToLower(cp), .len = len };
}

fn matchAtCi(haystack: []const u8, hi: usize, needle: []const u8) bool {
    var ni: usize = 0;
    var hj: usize = hi;
    while (ni < needle.len) {
        if (hj >= haystack.len) return false;
        const h = lowerCpUtf8(haystack, hj);
        const n = lowerCpUtf8(needle, ni);
        if (h.cp != n.cp) return false;
        hj += h.len;
        ni += n.len;
    }
    return true;
}

fn byteToCharPos(s: []const u8, byte_pos: usize) i64 {
    var i: usize = 0;
    var c: i64 = 0;
    while (i < byte_pos and i < s.len) {
        i += utf8CharLen(s[i]);
        c += 1;
    }
    return c;
}

fn native_mb_stripos(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const haystack = args[0].string.bytes();
    const needle = args[1].string.bytes();
    if (needle.len == 0) return NativeResult.scalar(.{ .bool = false });
    const start_char: i64 = if (args.len >= 3) Value.toInt(args[2]) else 0;
    var byte_offset: usize = 0;
    var c: i64 = 0;
    while (byte_offset < haystack.len and c < start_char) {
        byte_offset += utf8CharLen(haystack[byte_offset]);
        c += 1;
    }
    var i = byte_offset;
    while (i < haystack.len) {
        if (matchAtCi(haystack, i, needle)) return NativeResult.scalar(.{ .int = byteToCharPos(haystack, i) });
        i += utf8CharLen(haystack[i]);
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn native_mb_strripos(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const haystack = args[0].string.bytes();
    const needle = args[1].string.bytes();
    if (needle.len == 0) return NativeResult.scalar(.{ .bool = false });
    // walk to the end recording the last case-insensitive match position
    var last: ?usize = null;
    var i: usize = 0;
    while (i < haystack.len) {
        if (matchAtCi(haystack, i, needle)) last = i;
        i += utf8CharLen(haystack[i]);
    }
    if (last) |bi| return NativeResult.scalar(.{ .int = byteToCharPos(haystack, bi) });
    return NativeResult.scalar(.{ .bool = false });
}

fn native_mb_strstr(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const haystack = args[0].string.bytes();
    const needle = args[1].string.bytes();
    if (needle.len == 0) return NativeResult.scalar(.{ .bool = false });
    const before: bool = if (args.len >= 3) Value.isTruthy(args[2]) else false;
    if (std.mem.indexOf(u8, haystack, needle)) |pos| {
        const slice = if (before) haystack[0..pos] else haystack[pos..];
        return NativeResult.copyString(ctx.allocator, slice);
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn native_mb_stristr(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const haystack = args[0].string.bytes();
    const needle = args[1].string.bytes();
    if (needle.len == 0) return NativeResult.scalar(.{ .bool = false });
    const before: bool = if (args.len >= 3) Value.isTruthy(args[2]) else false;
    var i: usize = 0;
    while (i < haystack.len) : (i += utf8CharLen(haystack[i])) {
        if (matchAtCi(haystack, i, needle)) {
            const slice = if (before) haystack[0..i] else haystack[i..];
            return NativeResult.copyString(ctx.allocator, slice);
        }
    }
    return NativeResult.scalar(.{ .bool = false });
}

// last-occurrence variant of mb_strstr. PHP: mb_strrchr(haystack, needle, before=false)
// returns the slice starting at the LAST occurrence of needle (or the part
// before it when $before_needle=true). only the first character of $needle
// is used in PHP. case-sensitive
fn native_mb_strrchr(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const haystack = args[0].string.bytes();
    const needle = args[1].string.bytes();
    if (needle.len == 0) return NativeResult.scalar(.{ .bool = false });
    const nch_len = utf8CharLen(needle[0]);
    if (nch_len > needle.len) return NativeResult.scalar(.{ .bool = false });
    const before: bool = if (args.len >= 3) Value.isTruthy(args[2]) else false;
    var last: ?usize = null;
    var i: usize = 0;
    while (i < haystack.len) {
        const cl = utf8CharLen(haystack[i]);
        if (cl == nch_len and i + cl <= haystack.len and std.mem.eql(u8, haystack[i .. i + cl], needle[0..nch_len])) {
            last = i;
        }
        i += cl;
    }
    if (last) |pos| {
        const slice = if (before) haystack[0..pos] else haystack[pos..];
        return NativeResult.copyString(ctx.allocator, slice);
    }
    return NativeResult.scalar(.{ .bool = false });
}

// trim string to a maximum display width and optionally append a marker.
// PHP weighs CJK / full-width chars as 2 and everything else as 1; we use a
// simplified East Asian Wide range that covers CJK ideographs, hangul, and
// the basic emoji range - close enough for the common case
fn eastAsianWidth(cp: u32) u8 {
    if (cp < 0x1100) return 1;
    if ((cp >= 0x1100 and cp <= 0x115F) // Hangul Jamo
    or (cp >= 0x2E80 and cp <= 0x303E) // CJK Radicals, Kangxi
    or (cp >= 0x3041 and cp <= 0x33FF) // Hiragana, Katakana, CJK
    or (cp >= 0x3400 and cp <= 0x4DBF) // CJK Ext A
    or (cp >= 0x4E00 and cp <= 0x9FFF) // CJK Unified
    or (cp >= 0xA000 and cp <= 0xA4CF) // Yi
    or (cp >= 0xAC00 and cp <= 0xD7A3) // Hangul Syllables
    or (cp >= 0xF900 and cp <= 0xFAFF) // CJK Compat Ideographs
    or (cp >= 0xFE30 and cp <= 0xFE4F) // CJK Compat Forms
    or (cp >= 0xFF00 and cp <= 0xFF60) // Fullwidth ASCII
    or (cp >= 0xFFE0 and cp <= 0xFFE6) // Fullwidth signs
    or (cp >= 0x1F300 and cp <= 0x1FAFF) // Emoji / Symbols
    or (cp >= 0x20000 and cp <= 0x2FFFD) // CJK Ext B-F
    or (cp >= 0x30000 and cp <= 0x3FFFD)) return 2; // CJK Ext G+
    return 1;
}

fn decodeUtf8(s: []const u8, i: usize) struct { cp: u32, len: usize } {
    if (i >= s.len) return .{ .cp = 0, .len = 0 };
    const b0 = s[i];
    if (b0 < 0x80) return .{ .cp = b0, .len = 1 };
    if (b0 < 0xC0) return .{ .cp = b0, .len = 1 }; // invalid lead - treat as 1
    if (b0 < 0xE0) {
        if (i + 1 >= s.len) return .{ .cp = b0, .len = 1 };
        return .{ .cp = (@as(u32, b0 & 0x1F) << 6) | (s[i + 1] & 0x3F), .len = 2 };
    }
    if (b0 < 0xF0) {
        if (i + 2 >= s.len) return .{ .cp = b0, .len = 1 };
        return .{ .cp = (@as(u32, b0 & 0x0F) << 12) | (@as(u32, s[i + 1] & 0x3F) << 6) | (s[i + 2] & 0x3F), .len = 3 };
    }
    if (i + 3 >= s.len) return .{ .cp = b0, .len = 1 };
    return .{ .cp = (@as(u32, b0 & 0x07) << 18) | (@as(u32, s[i + 1] & 0x3F) << 12) | (@as(u32, s[i + 2] & 0x3F) << 6) | (s[i + 3] & 0x3F), .len = 4 };
}

fn native_mb_strimwidth(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 3 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const s = args[0].string.bytes();
    const start: i64 = Value.toInt(args[1]);
    const max_width: i64 = Value.toInt(args[2]);
    if (max_width <= 0) return NativeResult.literal("");
    const marker = if (args.len >= 4 and args[3] == .string) args[3].string.bytes() else "";

    // marker width
    var marker_w: i64 = 0;
    {
        var mi: usize = 0;
        while (mi < marker.len) {
            const d = decodeUtf8(marker, mi);
            marker_w += eastAsianWidth(d.cp);
            mi += d.len;
        }
    }

    // skip 'start' chars (chars, not bytes; matches PHP byte-positional? actually
    // PHP mb_strimwidth's start is in chars under the given encoding)
    var bi: usize = 0;
    {
        var skipped: i64 = 0;
        while (skipped < start and bi < s.len) {
            const d = decodeUtf8(s, bi);
            bi += d.len;
            skipped += 1;
        }
    }

    var out = std.ArrayListUnmanaged(u8).empty;
    defer out.deinit(ctx.allocator);
    const target = max_width - marker_w;
    // first try to fit without the marker
    var probe = bi;
    var probe_w: i64 = 0;
    while (probe < s.len) {
        const d = decodeUtf8(s, probe);
        probe_w += eastAsianWidth(d.cp);
        if (probe_w > max_width) break;
        probe += d.len;
    }
    if (probe == s.len) {
        try out.appendSlice(ctx.allocator, s[bi..]);
    } else {
        var ti = bi;
        var tw: i64 = 0;
        while (ti < s.len) {
            const d = decodeUtf8(s, ti);
            const next_w = tw + eastAsianWidth(d.cp);
            if (next_w > target) break;
            try out.appendSlice(ctx.allocator, s[ti .. ti + d.len]);
            tw = next_w;
            ti += d.len;
        }
        try out.appendSlice(ctx.allocator, marker);
    }
    const owned = try out.toOwnedSlice(ctx.allocator);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, owned));
}

fn native_mb_strcut(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.literal("");
    const s = args[0].string.bytes();
    var start: i64 = if (args.len >= 2) Value.toInt(args[1]) else 0;
    if (start < 0) start = @max(0, @as(i64, @intCast(s.len)) + start);
    var ustart: usize = @intCast(@min(start, @as(i64, @intCast(s.len))));
    // align to leading byte
    while (ustart < s.len and (s[ustart] & 0xC0) == 0x80) ustart += 1;
    var end: usize = s.len;
    if (args.len >= 3 and args[2] != .null) {
        const len: i64 = Value.toInt(args[2]);
        if (len < 0) {
            const e_signed = @as(i64, @intCast(s.len)) + len;
            end = @intCast(@max(@as(i64, @intCast(ustart)), e_signed));
        } else {
            const e = ustart + @as(usize, @intCast(len));
            end = @min(e, s.len);
        }
        // align end to leading byte (don't split a multibyte char)
        while (end > ustart and end < s.len and (s[end] & 0xC0) == 0x80) end -= 1;
    }
    if (end <= ustart) return NativeResult.literal("");
    return NativeResult.copyString(ctx.allocator, s[ustart..end]);
}

fn native_mb_encoding_aliases(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const enc = args[0].string.bytes();
    var lower_buf: [32]u8 = undefined;
    if (enc.len > lower_buf.len) return NativeResult.scalar(.{ .bool = false });
    for (enc, 0..) |c, i| lower_buf[i] = std.ascii.toLower(c);
    const e = lower_buf[0..enc.len];
    const arr = try ctx.createArray();
    // small known-alias table covering encodings zphp actually surfaces
    if (std.mem.eql(u8, e, "utf-8") or std.mem.eql(u8, e, "utf8")) {
        try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("utf8") });
    } else if (std.mem.eql(u8, e, "ascii") or std.mem.eql(u8, e, "us-ascii")) {
        try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("ANSI_X3.4-1968") });
        try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("iso-ir-6") });
    } else if (std.mem.eql(u8, e, "iso-8859-1") or std.mem.eql(u8, e, "latin1")) {
        try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("ISO_8859-1") });
        try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("latin1") });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_mb_list_encodings(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    // mirrors PHP 8.4's mb_list_encodings() output, in the same order.
    // zphp doesn't actually transcode most of these - it lists them so feature
    // detection in libraries (intl, symfony, wp) finds the names it expects
    const list = [_][]const u8{
        "BASE64",       "UUENCODE",            "HTML-ENTITIES",       "Quoted-Printable",        "7bit",                  "8bit",
        "UCS-4",        "UCS-4BE",             "UCS-4LE",             "UCS-2",                   "UCS-2BE",               "UCS-2LE",
        "UTF-32",       "UTF-32BE",            "UTF-32LE",            "UTF-16",                  "UTF-16BE",              "UTF-16LE",
        "UTF-8",        "UTF-7",               "UTF7-IMAP",           "ASCII",                   "EUC-JP",                "SJIS",
        "eucJP-win",    "EUC-JP-2004",         "SJIS-Mobile#DOCOMO",  "SJIS-Mobile#KDDI",        "SJIS-Mobile#SOFTBANK",  "SJIS-mac",
        "SJIS-2004",    "UTF-8-Mobile#DOCOMO", "UTF-8-Mobile#KDDI-A", "UTF-8-Mobile#KDDI-B",     "UTF-8-Mobile#SOFTBANK", "CP932",
        "SJIS-win",     "CP51932",             "JIS",                 "ISO-2022-JP",             "ISO-2022-JP-MS",        "GB18030",
        "GB18030-2022", "Windows-1252",        "Windows-1254",        "ISO-8859-1",              "ISO-8859-2",            "ISO-8859-3",
        "ISO-8859-4",   "ISO-8859-5",          "ISO-8859-6",          "ISO-8859-7",              "ISO-8859-8",            "ISO-8859-9",
        "ISO-8859-10",  "ISO-8859-13",         "ISO-8859-14",         "ISO-8859-15",             "ISO-8859-16",           "EUC-CN",
        "CP936",        "HZ",                  "EUC-TW",              "BIG-5",                   "CP950",                 "EUC-KR",
        "UHC",          "ISO-2022-KR",         "Windows-1251",        "CP866",                   "KOI8-R",                "KOI8-U",
        "ArmSCII-8",    "CP850",               "ISO-2022-JP-2004",    "ISO-2022-JP-MOBILE#KDDI", "CP50220",               "CP50221",
        "CP50222",
    };
    for (list) |n| try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(n) });
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_mb_str_pad(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    if (args.len < 2 or args[0] != .string) return NativeResult.share(args[0]);
    const s = args[0].string.bytes();
    const target_chars: i64 = Value.toInt(args[1]);
    const pad_str: []const u8 = if (args.len >= 3 and args[2] == .string) args[2].string.bytes() else " ";
    const pad_type: i64 = if (args.len >= 4) Value.toInt(args[3]) else 1; // STR_PAD_RIGHT
    if (pad_str.len == 0 or target_chars <= 0) return NativeResult.share(args[0]);

    var s_chars: i64 = 0;
    var i: usize = 0;
    while (i < s.len) : (i += utf8CharLen(s[i])) s_chars += 1;
    if (s_chars >= target_chars) return NativeResult.share(args[0]);
    const pad_needed: i64 = target_chars - s_chars;

    var pad_chars: i64 = 0;
    var pi: usize = 0;
    while (pi < pad_str.len) : (pi += utf8CharLen(pad_str[pi])) pad_chars += 1;
    if (pad_chars == 0) return NativeResult.share(args[0]);

    const left_chars: i64 = switch (pad_type) {
        0 => pad_needed, // STR_PAD_LEFT
        2 => @divFloor(pad_needed, 2), // STR_PAD_BOTH
        else => 0,
    };
    const right_chars: i64 = pad_needed - left_chars;

    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);

    try appendPadChars(ctx, &buf, pad_str, left_chars);
    try buf.appendSlice(ctx.allocator, s);
    try appendPadChars(ctx, &buf, pad_str, right_chars);

    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, try buf.toOwnedSlice(ctx.allocator)));
}

fn appendPadChars(ctx: *NativeContext, buf: *std.ArrayListUnmanaged(u8), pad_str: []const u8, count: i64) !void {
    var produced: i64 = 0;
    var pi: usize = 0;
    while (produced < count) {
        if (pi >= pad_str.len) pi = 0;
        const cl = utf8CharLen(pad_str[pi]);
        const end = @min(pi + cl, pad_str.len);
        try buf.appendSlice(ctx.allocator, pad_str[pi..end]);
        pi += cl;
        produced += 1;
    }
}

fn utf8CharLen(byte: u8) usize {
    if (byte < 0x80) return 1;
    if (byte < 0xE0) return 2;
    if (byte < 0xF0) return 3;
    return 4;
}

const base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

fn native_base64_encode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    const s = if (args[0] == .string) args[0].string.bytes() else return NativeResult.literal("");
    if (s.len == 0) return NativeResult.literal("");

    const out_len = ((s.len + 2) / 3) * 4;
    const buf = try ctx.allocator.alloc(u8, out_len);
    var di: usize = 0;
    var si: usize = 0;
    while (si + 3 <= s.len) {
        const n: u24 = @as(u24, s[si]) << 16 | @as(u24, s[si + 1]) << 8 | @as(u24, s[si + 2]);
        buf[di] = base64_chars[@intCast((n >> 18) & 0x3f)];
        buf[di + 1] = base64_chars[@intCast((n >> 12) & 0x3f)];
        buf[di + 2] = base64_chars[@intCast((n >> 6) & 0x3f)];
        buf[di + 3] = base64_chars[@intCast(n & 0x3f)];
        si += 3;
        di += 4;
    }
    const remaining = s.len - si;
    if (remaining == 1) {
        const n: u24 = @as(u24, s[si]) << 16;
        buf[di] = base64_chars[@intCast((n >> 18) & 0x3f)];
        buf[di + 1] = base64_chars[@intCast((n >> 12) & 0x3f)];
        buf[di + 2] = '=';
        buf[di + 3] = '=';
    } else if (remaining == 2) {
        const n: u24 = @as(u24, s[si]) << 16 | @as(u24, s[si + 1]) << 8;
        buf[di] = base64_chars[@intCast((n >> 18) & 0x3f)];
        buf[di + 1] = base64_chars[@intCast((n >> 12) & 0x3f)];
        buf[di + 2] = base64_chars[@intCast((n >> 6) & 0x3f)];
        buf[di + 3] = '=';
    }
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, buf));
}

fn base64Decode(c: u8) ?u6 {
    if (c >= 'A' and c <= 'Z') return @intCast(c - 'A');
    if (c >= 'a' and c <= 'z') return @intCast(c - 'a' + 26);
    if (c >= '0' and c <= '9') return @intCast(c - '0' + 52);
    if (c == '+') return 62;
    if (c == '/') return 63;
    return null;
}

fn native_base64_decode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    const s = if (args[0] == .string) args[0].string.bytes() else return NativeResult.scalar(Value{ .bool = false });
    if (s.len == 0) return NativeResult.literal("");

    const strict = args.len >= 2 and args[1] == .bool and args[1].bool;

    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);
    var accum: u24 = 0;
    var bits: u5 = 0;
    var pad_count: usize = 0;
    for (s) |c| {
        if (c == '=') {
            pad_count += 1;
            continue;
        }
        if (pad_count > 0 and strict) {
            return NativeResult.scalar(.{ .bool = false });
        }
        if (c == ' ' or c == '\n' or c == '\r' or c == '\t') {
            // PHP allows whitespace in both strict and non-strict modes
            continue;
        }
        const val = base64Decode(c) orelse {
            if (strict) {
                return NativeResult.scalar(.{ .bool = false });
            }
            continue;
        };
        accum = (accum << 6) | val;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            try buf.append(ctx.allocator, @truncate(accum >> bits));
        }
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result));
}

fn decodeUuChar(c: u8) u8 {
    // backtick = 0; otherwise (c - 0x20) & 0x3f
    if (c == 0x60) return 0;
    return (c - 0x20) & 0x3f;
}

fn native_urlencode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    const s = if (args[0] == .string) args[0].string.bytes() else return NativeResult.literal("");
    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);
    const hex = "0123456789ABCDEF";
    for (s) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.') {
            try buf.append(ctx.allocator, c);
        } else if (c == ' ') {
            try buf.append(ctx.allocator, '+');
        } else {
            try buf.append(ctx.allocator, '%');
            try buf.append(ctx.allocator, hex[c >> 4]);
            try buf.append(ctx.allocator, hex[c & 0x0f]);
        }
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result));
}

fn native_urldecode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    const s = if (args[0] == .string) args[0].string.bytes() else return NativeResult.literal("");
    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '%' and i + 2 < s.len) {
            const hi = hexVal(s[i + 1]) orelse {
                try buf.append(ctx.allocator, s[i]);
                i += 1;
                continue;
            };
            const lo = hexVal(s[i + 2]) orelse {
                try buf.append(ctx.allocator, s[i]);
                i += 1;
                continue;
            };
            try buf.append(ctx.allocator, (hi << 4) | lo);
            i += 3;
        } else if (s[i] == '+') {
            try buf.append(ctx.allocator, ' ');
            i += 1;
        } else {
            try buf.append(ctx.allocator, s[i]);
            i += 1;
        }
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result));
}

fn native_rawurlencode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    const s = if (args[0] == .string) args[0].string.bytes() else return NativeResult.literal("");
    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);
    const hex = "0123456789ABCDEF";
    for (s) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
            try buf.append(ctx.allocator, c);
        } else {
            try buf.append(ctx.allocator, '%');
            try buf.append(ctx.allocator, hex[c >> 4]);
            try buf.append(ctx.allocator, hex[c & 0x0f]);
        }
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result));
}

fn native_rawurldecode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    const s = if (args[0] == .string) args[0].string.bytes() else return NativeResult.literal("");
    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '%' and i + 2 < s.len) {
            const hi = hexVal(s[i + 1]) orelse {
                try buf.append(ctx.allocator, s[i]);
                i += 1;
                continue;
            };
            const lo = hexVal(s[i + 2]) orelse {
                try buf.append(ctx.allocator, s[i]);
                i += 1;
                continue;
            };
            try buf.append(ctx.allocator, (hi << 4) | lo);
            i += 3;
        } else {
            try buf.append(ctx.allocator, s[i]);
            i += 1;
        }
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result));
}

/// PHP's `string` parameter type rejects arrays with a TypeError. Most native
/// string functions in this file go through coerceToString which silently
/// returns "" for arrays; call this first to match PHP behavior on the strict
/// parameters
fn rejectArrayParam(ctx: *NativeContext, v: Value, comptime func_name: []const u8) !bool {
    // PHP throws TypeError on any non-stringable: array, closure, and any
    // object without __toString (objects WITH __toString stringify normally).
    // emit the same 'must be of type string, <type> given' format
    const bad_type: ?[]const u8 = switch (v) {
        .array => "array",
        .object => |o| if (ctx.vm.hasMethod(o.class_name, "__toString")) null else o.class_name,
        else => null,
    };
    if (bad_type) |bt| {
        const msg = try std.fmt.allocPrint(
            ctx.allocator,
            "{s}(): Argument #1 ($string) must be of type string, {s} given",
            .{ func_name, bt },
        );
        defer ctx.allocator.free(msg);
        try ctx.vm.setPendingException("TypeError", msg);
        return true;
    }
    return false;
}

pub fn coerceToString(ctx: *NativeContext, v: Value) ![]const u8 {
    return switch (v) {
        .string => |s| s.bytes(),
        .int => (try ctx.vm.transientFormatted(v)).bytes(),
        .float => (try ctx.vm.transientFormatted(v)).bytes(),
        .bool => |b| if (b) "1" else "",
        .null => "",
        .object => |o| blk: {
            if (ctx.vm.hasMethod(o.class_name, "__toString")) {
                const r = try ctx.vm.callMethod(o, "__toString", &.{});
                if (r == .string) break :blk r.string.bytes();
            }
            break :blk "";
        },
        else => "",
    };
}

// a `string` parameter as php's argument parsing takes it: scalars and
// Stringable objects convert in weak mode, null is deprecated there, and
// anything else is a TypeError
pub fn stringParam(ctx: *NativeContext, comptime func: []const u8, args: []const Value, index: usize, comptime name: []const u8) RuntimeError![]const u8 {
    const v: Value = if (index < args.len) args[index] else .null;
    if (v == .string) return v.string.bytes();
    const strict = ctx.vm.script_strict_types;
    switch (v) {
        .null, .undef => if (!strict) {
            const msg = try std.fmt.allocPrint(ctx.allocator, func ++ "(): Passing null to parameter #{d} ($" ++ name ++ ") of type string is deprecated", .{index + 1});
            defer ctx.allocator.free(msg);
            try ctx.vm.raiseError(8192, msg);
            return "";
        },
        .int, .float, .bool => if (!strict) {
            if (v == .float and std.math.isNan(v.float)) try ctx.vm.emitWarning("unexpected NAN value was coerced to string");
            return coerceToString(ctx, v);
        },
        .object => |o| if (!strict and ctx.vm.hasMethod(o.class_name, "__toString")) return ctx.vm.objectToString(o),
        else => {},
    }
    const msg = try std.fmt.allocPrint(ctx.allocator, func ++ "(): Argument #{d} ($" ++ name ++ ") must be of type string, {s} given", .{ index + 1, phpTypeName(v) });
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("TypeError", msg);
    return error.RuntimeError;
}

fn native_md5(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    const s = try coerceToString(ctx, args[0]);
    const raw_output = args.len >= 2 and args[1].isTruthy();
    var hash: [16]u8 = undefined;
    std.crypto.hash.Md5.hash(s, &hash, .{});
    if (raw_output) return NativeResult.copyString(ctx.allocator, &hash);
    const hex = "0123456789abcdef";
    var buf: [32]u8 = undefined;
    for (hash, 0..) |byte, i| {
        buf[i * 2] = hex[byte >> 4];
        buf[i * 2 + 1] = hex[byte & 0x0f];
    }
    return NativeResult.copyString(ctx.allocator, &buf);
}

fn native_sha1(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    const s = if (args[0] == .string) args[0].string.bytes() else return NativeResult.literal("");
    const raw_output = args.len >= 2 and args[1].isTruthy();
    var hash: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(s, &hash, .{});
    if (raw_output) return NativeResult.copyString(ctx.allocator, &hash);
    const hex = "0123456789abcdef";
    var buf: [40]u8 = undefined;
    for (hash, 0..) |byte, i| {
        buf[i * 2] = hex[byte >> 4];
        buf[i * 2 + 1] = hex[byte & 0x0f];
    }
    return NativeResult.copyString(ctx.allocator, &buf);
}

fn native_mb_substr(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.literal("");
    const s = if (args[0] == .string) args[0].string.bytes() else return NativeResult.literal("");
    const char_count = mbCharCount(s);
    var start = Value.toInt(args[1]);
    if (start < 0) start = @max(0, char_count + start);
    if (start >= char_count) return NativeResult.literal("");

    var length = if (args.len >= 3 and args[2] != .null) Value.toInt(args[2]) else char_count - start;
    if (length < 0) length = @max(0, char_count - start + length);
    if (length <= 0) return NativeResult.literal("");

    var bi: usize = 0;
    var ci: i64 = 0;
    while (bi < s.len and ci < start) : (ci += 1) bi += utf8Step(s, bi).len;

    // php decodes the input: an ill-formed sequence comes out as '?'
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(ctx.allocator);
    var remaining = length;
    while (bi < s.len and remaining > 0) : (remaining -= 1) {
        const step = utf8Step(s, bi);
        if (step.valid) try out.appendSlice(ctx.allocator, s[bi .. bi + step.len]) else try out.append(ctx.allocator, '?');
        bi += step.len;
    }
    return NativeResult.copyString(ctx.allocator, out.items);
}

fn mbCharCount(s: []const u8) i64 {
    var count: i64 = 0;
    var i: usize = 0;
    while (i < s.len) : (count += 1) i += utf8Step(s, i).len;
    return count;
}

const Utf8Step = struct {
    len: usize,
    valid: bool,
    // ill-formed only because the input ended mid-sequence
    truncated: bool = false,
};

// s with each ill-formed sequence replaced by '?', the way mbstring decodes
// it; null when s is already well formed
fn sanitizeUtf8(allocator: std.mem.Allocator, s: []const u8) !?[]u8 {
    if (std.unicode.utf8ValidateSlice(s)) return null;
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < s.len) {
        const step = utf8Step(s, i);
        if (step.valid) try out.appendSlice(allocator, s[i .. i + step.len]) else try out.append(allocator, '?');
        i += step.len;
    }
    return try out.toOwnedSlice(allocator);
}

// the byte count php's mbstring assigns a UTF-8 lead byte when it splits a
// string without decoding it (mb_str_split); stray continuation bytes and
// bytes that can never start a sequence stand alone
fn utf8LeadLength(byte: u8) usize {
    return switch (byte) {
        0xC2...0xDF => 2,
        0xE0...0xEF => 3,
        0xF0...0xF4 => 4,
        else => 1,
    };
}

// one character of s at i, decoded the way php's mbstring does (the WHATWG
// rules): a well-formed sequence, or the maximal ill-formed prefix of one,
// which counts as a single character
fn utf8Step(s: []const u8, i: usize) Utf8Step {
    const b0 = s[i];
    if (b0 < 0x80) return .{ .len = 1, .valid = true };
    const need: usize, const lo: u8, const hi: u8 = switch (b0) {
        0xC2...0xDF => .{ 1, 0x80, 0xBF },
        0xE0 => .{ 2, 0xA0, 0xBF },
        0xE1...0xEC, 0xEE...0xEF => .{ 2, 0x80, 0xBF },
        0xED => .{ 2, 0x80, 0x9F },
        0xF0 => .{ 3, 0x90, 0xBF },
        0xF1...0xF3 => .{ 3, 0x80, 0xBF },
        0xF4 => .{ 3, 0x80, 0x8F },
        else => return .{ .len = 1, .valid = false },
    };
    var k: usize = 1;
    while (k <= need) : (k += 1) {
        if (i + k >= s.len) return .{ .len = k, .valid = false, .truncated = true };
        const b = s[i + k];
        const first_lo: u8 = if (k == 1) lo else 0x80;
        const first_hi: u8 = if (k == 1) hi else 0xBF;
        if (b < first_lo or b > first_hi) return .{ .len = k, .valid = false };
    }
    return .{ .len = need + 1, .valid = true };
}

fn native_strrev(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    const s = try coerceToString(ctx, args[0]);
    if (s.len == 0) return NativeResult.literal("");
    const buf = try ctx.allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| buf[s.len - 1 - i] = c;
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, buf));
}

fn toLowerBuf(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    const buf = try allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| buf[i] = std.ascii.toLower(c);
    return buf;
}

fn strrposImpl(haystack: []const u8, needle: []const u8, args: []const Value) Value {
    const hlen: i64 = @intCast(haystack.len);
    const raw_off: i64 = if (args.len >= 3) Value.toInt(args[2]) else 0;
    // positive offset: match starting position must be >= offset
    // negative offset: match starting position must be <= hlen + offset
    var min_start: usize = 0;
    var max_start_inclusive: i64 = hlen - @as(i64, @intCast(needle.len));
    if (max_start_inclusive < 0) return .{ .bool = false };
    if (raw_off >= 0) {
        if (raw_off > hlen) return .{ .bool = false };
        min_start = @intCast(raw_off);
    } else {
        const limit = hlen + raw_off;
        if (limit < 0) return .{ .bool = false };
        if (limit < max_start_inclusive) max_start_inclusive = limit;
    }
    var i: i64 = max_start_inclusive;
    while (i >= @as(i64, @intCast(min_start))) : (i -= 1) {
        const u: usize = @intCast(i);
        if (std.mem.eql(u8, haystack[u .. u + needle.len], needle)) {
            return .{ .int = i };
        }
    }
    return .{ .bool = false };
}

fn strIreplaceOne(ctx: *NativeContext, subject: []const u8, search: []const u8, replace: []const u8, count: *i64) !Value.String {
    if (search.len == 0) return Value.String.create(ctx.allocator, subject);
    const s_lower = try toLowerBuf(ctx.allocator, subject);
    defer ctx.allocator.free(s_lower);
    const n_lower = try toLowerBuf(ctx.allocator, search);
    defer ctx.allocator.free(n_lower);

    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);
    var i: usize = 0;
    while (i < subject.len) {
        if (i + search.len <= subject.len and std.mem.eql(u8, s_lower[i .. i + search.len], n_lower)) {
            try buf.appendSlice(ctx.allocator, replace);
            i += search.len;
            count.* += 1;
        } else {
            try buf.append(ctx.allocator, subject[i]);
            i += 1;
        }
    }
    const out = try buf.toOwnedSlice(ctx.allocator);
    return Value.String.adopt(ctx.allocator, out);
}

fn strIreplaceOnSingle(ctx: *NativeContext, search: Value, replace: Value, subject: []const u8, total_count: *i64) !Value.String {
    if (search == .array) {
        var result = try Value.String.create(ctx.allocator, subject);
        errdefer result.release();
        for (search.array.entries.items, 0..) |entry, idx| {
            const needle = if (entry.value == .string) entry.value.string.bytes() else continue;
            const replacement = if (replace == .array) blk: {
                if (idx < replace.array.entries.items.len) {
                    if (replace.array.entries.items[idx].value == .string) break :blk replace.array.entries.items[idx].value.string.bytes();
                }
                break :blk "";
            } else if (replace == .string) replace.string.bytes() else "";
            const next = try strIreplaceOne(ctx, result.bytes(), needle, replacement, total_count);
            result.release();
            result = next;
        }
        return result;
    }
    const s = if (search == .string) search.string.bytes() else return Value.String.create(ctx.allocator, subject);
    const rep = if (replace == .string) replace.string.bytes() else "";
    return strIreplaceOne(ctx, subject, s, rep, total_count);
}

fn isDelimiter(c: u8, delimiters: []const u8) bool {
    for (delimiters) |d| {
        if (c == d) return true;
    }
    return false;
}

fn native_crc32(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .int = 0 });
    const s = if (args[0] == .string) args[0].string.bytes() else return NativeResult.scalar(Value{ .int = 0 });
    const result = std.hash.Crc32.hash(s);
    // PHP returns the unsigned 32-bit value (zero-extended into signed 64-bit)
    return NativeResult.scalar(.{ .int = @as(i64, result) });
}

fn native_str_rot13(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    const s = if (args[0] == .string) args[0].string.bytes() else return NativeResult.literal("");
    if (s.len == 0) return NativeResult.literal("");
    const buf = try ctx.allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| {
        buf[i] = if (c >= 'a' and c <= 'z')
            (c - 'a' + 13) % 26 + 'a'
        else if (c >= 'A' and c <= 'Z')
            (c - 'A' + 13) % 26 + 'A'
        else
            c;
    }
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, buf));
}

// PHP's default Unicode-whitespace set for mb_trim family. matches what PHP
// docs list as "characters with the White_Space property", restricted to the
// ones PHP actually uses
const DEFAULT_MB_TRIM_CPS = [_]u21{
    0x0009, 0x000A, 0x000B, 0x000C, 0x000D, 0x0020,
    0x0085, 0x00A0, 0x1680, 0x2000, 0x2001, 0x2002,
    0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008,
    0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F,
    0x3000, 0xFEFF,
};

fn decodeUtf8At(s: []const u8, pos: usize) struct { cp: u21, len: u3 } {
    if (pos >= s.len) return .{ .cp = 0, .len = 0 };
    const len = std.unicode.utf8ByteSequenceLength(s[pos]) catch return .{ .cp = s[pos], .len = 1 };
    if (pos + len > s.len) return .{ .cp = s[pos], .len = 1 };
    const cp = std.unicode.utf8Decode(s[pos .. pos + len]) catch return .{ .cp = s[pos], .len = 1 };
    return .{ .cp = cp, .len = len };
}

// previous-codepoint length walking backwards from `pos`. returns 0 if none.
fn prevUtf8Len(s: []const u8, pos: usize) u3 {
    if (pos == 0) return 0;
    var i: usize = pos;
    var back: u3 = 0;
    while (i > 0 and back < 4) {
        i -= 1;
        back += 1;
        const b = s[i];
        // continuation byte is 10xxxxxx; stop at a non-continuation
        if ((b & 0xC0) != 0x80) return back;
    }
    return back;
}

fn buildMbTrimSet(allocator: std.mem.Allocator, arg: ?[]const u8) ![]u21 {
    if (arg) |a| {
        var list: std.ArrayListUnmanaged(u21) = .empty;
        var i: usize = 0;
        while (i < a.len) {
            const d = decodeUtf8At(a, i);
            try list.append(allocator, d.cp);
            i += if (d.len == 0) 1 else d.len;
        }
        return list.toOwnedSlice(allocator);
    }
    const out = try allocator.alloc(u21, DEFAULT_MB_TRIM_CPS.len);
    @memcpy(out, &DEFAULT_MB_TRIM_CPS);
    return out;
}

fn cpInSet(set: []const u21, cp: u21) bool {
    for (set) |x| if (x == cp) return true;
    return false;
}

fn mbTrimImpl(ctx: *NativeContext, s: []const u8, set: []const u21, left: bool, right: bool) !Value.String {
    var start: usize = 0;
    if (left) {
        while (start < s.len) {
            const d = decodeUtf8At(s, start);
            if (d.len == 0 or !cpInSet(set, d.cp)) break;
            start += d.len;
        }
    }
    var end: usize = s.len;
    if (right) {
        while (end > start) {
            const pl = prevUtf8Len(s, end);
            if (pl == 0) break;
            const d = decodeUtf8At(s, end - pl);
            if (d.len == 0 or !cpInSet(set, d.cp)) break;
            end -= pl;
        }
    }
    return Value.String.create(ctx.allocator, s[start..end]);
}

fn native_mb_trim(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    const s = if (args[0] == .string) args[0].string.bytes() else return NativeResult.literal("");
    const arg_chars: ?[]const u8 = if (args.len >= 2 and args[1] == .string) args[1].string.bytes() else null;
    const set = try buildMbTrimSet(ctx.allocator, arg_chars);
    defer ctx.allocator.free(set);
    return NativeResult.takeString(try mbTrimImpl(ctx, s, set, true, true));
}

fn native_mb_ltrim(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    const s = if (args[0] == .string) args[0].string.bytes() else return NativeResult.literal("");
    const arg_chars: ?[]const u8 = if (args.len >= 2 and args[1] == .string) args[1].string.bytes() else null;
    const set = try buildMbTrimSet(ctx.allocator, arg_chars);
    defer ctx.allocator.free(set);
    return NativeResult.takeString(try mbTrimImpl(ctx, s, set, true, false));
}

fn native_mb_rtrim(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    const s = if (args[0] == .string) args[0].string.bytes() else return NativeResult.literal("");
    const arg_chars: ?[]const u8 = if (args.len >= 2 and args[1] == .string) args[1].string.bytes() else null;
    const set = try buildMbTrimSet(ctx.allocator, arg_chars);
    defer ctx.allocator.free(set);
    return NativeResult.takeString(try mbTrimImpl(ctx, s, set, false, true));
}

fn native_quotemeta(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    const s = if (args[0] == .string) args[0].string.bytes() else return NativeResult.literal("");
    if (s.len == 0) return NativeResult.literal("");
    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);
    for (s) |c| {
        if (c == '.' or c == '\\' or c == '+' or c == '*' or c == '?' or
            c == '[' or c == '^' or c == ']' or c == '(' or c == ')' or
            c == '$')
        {
            try buf.append(ctx.allocator, '\\');
        }
        try buf.append(ctx.allocator, c);
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result));
}

fn native_mb_ucfirst(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    const s = if (args[0] == .string) args[0].string.bytes() else return NativeResult.literal("");
    return NativeResult.takeString(try mbCaseFirst(ctx, s, true));
}

fn native_mb_lcfirst(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    const s = if (args[0] == .string) args[0].string.bytes() else return NativeResult.literal("");
    return NativeResult.takeString(try mbCaseFirst(ctx, s, false));
}

fn mbCaseFirst(ctx: *NativeContext, s: []const u8, to_upper: bool) !Value.String {
    if (s.len == 0) return Value.String.create(ctx.allocator, "");
    const first_len = std.unicode.utf8ByteSequenceLength(s[0]) catch 1;
    if (first_len > s.len) {
        const buf = try ctx.allocator.alloc(u8, s.len);
        @memcpy(buf, s);
        return Value.String.adopt(ctx.allocator, buf);
    }
    if (first_len == 1) {
        const buf = try ctx.allocator.alloc(u8, s.len);
        @memcpy(buf, s);
        buf[0] = if (to_upper) std.ascii.toUpper(s[0]) else std.ascii.toLower(s[0]);
        return Value.String.adopt(ctx.allocator, buf);
    }
    const cp = std.unicode.utf8Decode(s[0..first_len]) catch {
        const buf = try ctx.allocator.alloc(u8, s.len);
        @memcpy(buf, s);
        return Value.String.adopt(ctx.allocator, buf);
    };
    const new_cp = if (to_upper) unicodeToUpper(cp) else unicodeToLower(cp);
    var enc: [4]u8 = undefined;
    const enc_len = std.unicode.utf8Encode(new_cp, &enc) catch first_len;
    const total = (s.len - first_len) + enc_len;
    const buf = try ctx.allocator.alloc(u8, total);
    @memcpy(buf[0..enc_len], enc[0..enc_len]);
    @memcpy(buf[enc_len..], s[first_len..]);
    return Value.String.adopt(ctx.allocator, buf);
}

fn native_strip_tags(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const params = html.Params{ .ctx = ctx, .func = "strip_tags", .args = args };
    const s = try params.string(0, "string", "");
    var tags: std.ArrayListUnmanaged(u8) = .empty;
    defer tags.deinit(ctx.allocator);
    var allow: ?[]const u8 = null;
    if (args.len >= 2) switch (args[1]) {
        .null, .undef => {},
        // php joins an array's tags into one "<a><b>" string
        .array => |arr| {
            for (arr.entries.items) |entry| {
                if (entry.value == .array) try ctx.vm.emitWarning("Array to string conversion");
                const tag = if (entry.value == .array) "Array" else try coerceToString(ctx, entry.value);
                try tags.append(ctx.allocator, '<');
                try tags.appendSlice(ctx.allocator, tag);
                try tags.append(ctx.allocator, '>');
            }
            if (tags.items.len > 0) allow = tags.items;
        },
        .string => |str| allow = str.bytes(),
        .int, .float, .bool => allow = try coerceToString(ctx, args[1]),
        .object => |o| if (ctx.vm.hasMethod(o.class_name, "__toString")) {
            allow = try coerceToString(ctx, args[1]);
        } else return params.typeError(1, "allowed_tags", "array|string|null"),
        else => return params.typeError(1, "allowed_tags", "array|string|null"),
    };
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(ctx.allocator);
    try stripTags(ctx.allocator, s, allow, false, &out);
    return NativeResult.copyString(ctx.allocator, out.items);
}

// php's php_tag_find: the tag in tbuf ("<a href=...>", "</a>") normalized to
// "<a>" and looked up in the lowercased allow set, which php searches with
// strstr, so it ends at a nul
fn tagAllowed(allocator: std.mem.Allocator, tag: []const u8, set: []const u8) !bool {
    if (tag.len == 0) return false;
    var norm: std.ArrayListUnmanaged(u8) = .empty;
    defer norm.deinit(allocator);
    // the tag buffer is nul-terminated in php, so reads past its end see 0
    const at = struct {
        fn f(t: []const u8, i: usize) u8 {
            return if (i < t.len) toLowerAscii(t[i]) else 0;
        }
    }.f;
    var t: usize = 0;
    var state: u8 = 0;
    var done = false;
    while (!done) {
        const c = at(tag, t);
        switch (c) {
            '<' => try norm.append(allocator, c),
            '>' => done = true,
            else => {
                if (!isCSpace(c)) {
                    if (state == 0) state = 1;
                    const prev: u8 = if (t > 0) tag[t - 1] else 0;
                    if (c != '/' or (prev != '<' and at(tag, t + 1) != '>')) try norm.append(allocator, c);
                } else if (state == 1) done = true;
            },
        }
        t += 1;
    }
    try norm.append(allocator, '>');
    const haystack = if (std.mem.indexOfScalar(u8, set, 0)) |nul| set[0..nul] else set;
    // php's normalized tag is a c string too
    const needle = if (std.mem.indexOfScalar(u8, norm.items, 0)) |nul| norm.items[0..nul] else norm.items;
    return std.mem.indexOf(u8, haystack, needle) != null;
}

fn isCSpace(c: u8) bool {
    return c == ' ' or (c >= '\t' and c <= '\r');
}

// php's php_strip_tags_ex state machine: 0 is output, 1 inside an html tag,
// 2 inside php code, 3 inside <! (comments and doctype), 4 inside <!-- -->
pub fn stripTags(allocator: std.mem.Allocator, buf: []const u8, allow_in: ?[]const u8, allow_tag_spaces: bool, out: *std.ArrayListUnmanaged(u8)) !void {
    var allow_lower: ?[]u8 = null;
    defer if (allow_lower) |a| allocator.free(a);
    if (allow_in) |a| {
        allow_lower = try allocator.alloc(u8, a.len);
        for (a, 0..) |c, i| allow_lower.?[i] = toLowerAscii(c);
    }
    const allow = allow_lower;
    var tbuf: std.ArrayListUnmanaged(u8) = .empty;
    defer tbuf.deinit(allocator);
    const end = buf.len;
    // reads at the end see the c string's terminator
    const byteAt = struct {
        fn f(b: []const u8, i: usize) u8 {
            return if (i < b.len) b[i] else 0;
        }
    }.f;
    var p: usize = 0;
    var lc: u8 = 0;
    var br: i64 = 0;
    var depth: i64 = 0;
    var in_q: u8 = 0;
    var state: u8 = 0;
    var is_xml = false;
    while (p < end) {
        const c = buf[p];
        switch (state) {
            0 => switch (c) {
                0 => {},
                '<' => {
                    if (in_q != 0) {} else if (isCSpace(byteAt(buf, p + 1)) and !allow_tag_spaces) {
                        try out.append(allocator, c);
                    } else {
                        lc = '<';
                        state = 1;
                        if (allow != null) try tbuf.append(allocator, '<');
                    }
                },
                '>' => {
                    if (depth != 0) {
                        depth -= 1;
                    } else if (in_q == 0) try out.append(allocator, c);
                },
                else => try out.append(allocator, c),
            },
            1 => reg: {
                switch (c) {
                    0 => break :reg,
                    '<' => {
                        if (in_q != 0) break :reg;
                        if (!(isCSpace(byteAt(buf, p + 1)) and !allow_tag_spaces)) {
                            depth += 1;
                            break :reg;
                        }
                    },
                    '>' => {
                        if (depth != 0) {
                            depth -= 1;
                            break :reg;
                        }
                        if (in_q != 0) break :reg;
                        lc = '>';
                        if (is_xml and p >= 1 and buf[p - 1] == '-') break :reg;
                        in_q = 0;
                        state = 0;
                        is_xml = false;
                        if (allow) |set| {
                            try tbuf.append(allocator, '>');
                            if (try tagAllowed(allocator, tbuf.items, set)) try out.appendSlice(allocator, tbuf.items);
                            tbuf.clearRetainingCapacity();
                        }
                        break :reg;
                    },
                    '"', '\'' => {
                        if (p != 0 and (in_q == 0 or c == in_q)) in_q = if (in_q != 0) 0 else c;
                    },
                    '!' => if (p >= 1 and buf[p - 1] == '<') {
                        state = 3;
                        lc = c;
                        break :reg;
                    },
                    '?' => if (p >= 1 and buf[p - 1] == '<') {
                        br = 0;
                        state = 2;
                        break :reg;
                    },
                    else => {},
                }
                if (allow != null) try tbuf.append(allocator, c);
            },
            2 => switch (c) {
                '(' => if (lc != '"' and lc != '\'') {
                    lc = '(';
                    br += 1;
                },
                ')' => if (lc != '"' and lc != '\'') {
                    lc = ')';
                    br -= 1;
                },
                '>' => {
                    if (depth != 0) {
                        depth -= 1;
                    } else if (in_q == 0 and br == 0 and p >= 1 and lc != '"' and buf[p - 1] == '?') {
                        in_q = 0;
                        state = 0;
                        tbuf.clearRetainingCapacity();
                    }
                },
                '"', '\'' => if (p >= 1 and buf[p - 1] != '\\') {
                    if (lc == c) {
                        lc = 0;
                    } else if (lc != '\\') lc = c;
                    if (p != 0 and (in_q == 0 or c == in_q)) in_q = if (in_q != 0) 0 else c;
                },
                'l', 'L' => if (p > 4 and (buf[p - 1] == 'm' or buf[p - 1] == 'M') and (buf[p - 2] == 'x' or buf[p - 2] == 'X') and buf[p - 3] == '?' and buf[p - 4] == '<') {
                    // <?xml is markup, not php
                    state = 1;
                    is_xml = true;
                },
                else => {},
            },
            3 => switch (c) {
                '>' => {
                    if (depth != 0) {
                        depth -= 1;
                    } else if (in_q == 0) {
                        state = 0;
                        tbuf.clearRetainingCapacity();
                    }
                },
                '"', '\'' => if (p != 0 and buf[p - 1] != '\\' and (in_q == 0 or c == in_q)) {
                    in_q = if (in_q != 0) 0 else c;
                },
                '-' => if (p >= 2 and buf[p - 1] == '-' and buf[p - 2] == '!') {
                    state = 4;
                },
                'E', 'e' => if (p > 6 and std.ascii.eqlIgnoreCase(buf[p - 6 .. p], "doctyp")) {
                    // <!DOCTYPE is an html tag
                    state = 1;
                },
                else => {},
            },
            else => if (c == '>' and in_q == 0 and p >= 2 and buf[p - 1] == '-' and buf[p - 2] == '-') {
                in_q = 0;
                state = 0;
                tbuf.clearRetainingCapacity();
            },
        }
        p += 1;
    }
}

fn toLowerAscii(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}

// http_build_query: php_url_encode_hash_ex over the array, or over the
// properties of an object the calling scope can see
fn native_http_build_query(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = html.Params{ .ctx = ctx, .func = "http_build_query", .args = args };
    const data: Value = if (args.len > 0) args[0] else .null;
    if (data != .array and data != .object) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "http_build_query(): Argument #1 ($data) must be of type array, {s} given", .{data.valueName()});
        defer ctx.allocator.free(msg);
        try ctx.vm.setPendingException("TypeError", msg);
        return error.RuntimeError;
    }
    const prefix = try p.string(1, "numeric_prefix", "");
    const sep_arg: ?[]const u8 = if (args.len > 2 and args[2] != .null) try p.string(2, "arg_separator", "") else null;
    const enc_type = try p.int(3, "encoding_type", 1);
    if (data == .object) if (ctx.vm.classes.get(data.object.class_name)) |cd| if (cd.is_enum) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "http_build_query(): Argument #1 ($data) must not be an enum, {s} given", .{ctx.vm.declaredClassName(data.object.class_name)});
        defer ctx.allocator.free(msg);
        try ctx.vm.setPendingException("TypeError", msg);
        return error.RuntimeError;
    };
    var sep: []const u8 = sep_arg orelse (ctx.vm.ini_settings.get("arg_separator.output") orelse "&");
    if (sep.len == 0) sep = "&";
    var q = QueryBuilder{ .ctx = ctx, .sep = sep, .rfc3986 = enc_type == 2 };
    defer q.buf.deinit(ctx.allocator);
    defer q.visited.deinit(ctx.allocator);
    try q.encode(data, if (prefix.len > 0) prefix else null, null);
    const result = try q.buf.toOwnedSlice(ctx.allocator);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result));
}

const QueryBuilder = struct {
    ctx: *NativeContext,
    sep: []const u8,
    rfc3986: bool,
    buf: std.ArrayListUnmanaged(u8) = .empty,
    visited: std.ArrayListUnmanaged(usize) = .empty,

    fn encode(self: *QueryBuilder, container: Value, num_prefix: ?[]const u8, key_prefix: ?[]const u8) RuntimeError!void {
        const a = self.ctx.allocator;
        const id: usize = switch (container) {
            .array => |arr| @intFromPtr(arr),
            .object => |o| @intFromPtr(o),
            else => return,
        };
        // a container already being encoded is skipped, as php's recursion guard does
        for (self.visited.items) |v| if (v == id) return;
        try self.visited.append(a, id);
        defer _ = self.visited.pop();
        var owned: ?*PhpArray = null;
        const arr: *PhpArray = switch (container) {
            .array => |x| x,
            .object => |o| blk: {
                const r = try native_get_object_vars_for(self.ctx, o);
                owned = r;
                break :blk r;
            },
            else => unreachable,
        };
        defer if (owned) |o| self.ctx.vm.releaseUnheldArray(o);
        for (arr.entries.items) |entry| {
            const v = if (entry.ref) |r| r.* else entry.value;
            var idx_buf: [32]u8 = undefined;
            const is_str = entry.key == .string;
            const name: []const u8 = switch (entry.key) {
                .string => |k| k.bytes(),
                .int => |n| std.fmt.bufPrint(&idx_buf, "{d}", .{n}) catch unreachable,
            };
            const is_enum = v == .object and if (self.ctx.vm.classes.get(v.object.class_name)) |cd| cd.is_enum else false;
            if (v == .array or (v == .object and !is_enum)) {
                var new_prefix: std.ArrayListUnmanaged(u8) = .empty;
                defer new_prefix.deinit(a);
                if (is_str) {
                    if (key_prefix) |kp| try new_prefix.appendSlice(a, kp);
                    try appendUrlEncodedMode(&new_prefix, a, name, self.rfc3986);
                    try new_prefix.appendSlice(a, if (key_prefix != null) "%5D%5B" else "%5B");
                } else {
                    if (key_prefix) |kp| try new_prefix.appendSlice(a, kp);
                    if (num_prefix) |np| try new_prefix.appendSlice(a, np);
                    try new_prefix.appendSlice(a, name);
                    try new_prefix.appendSlice(a, if (key_prefix != null) "%5D%5B" else "%5B");
                }
                try self.encode(v, null, new_prefix.items);
                continue;
            }
            if (v == .null or v == .resource) continue;
            if (self.buf.items.len > 0) try self.buf.appendSlice(a, self.sep);
            if (key_prefix) |kp| try self.buf.appendSlice(a, kp);
            if (is_str) {
                try appendUrlEncodedMode(&self.buf, a, name, self.rfc3986);
            } else {
                if (num_prefix) |np| try self.buf.appendSlice(a, np);
                try self.buf.appendSlice(a, name);
            }
            if (key_prefix != null) try self.buf.appendSlice(a, "%5D");
            try self.buf.append(a, '=');
            var scalar = v;
            if (is_enum) {
                const cd = self.ctx.vm.classes.get(v.object.class_name).?;
                if (cd.backed_type == .none) {
                    const msg = try std.fmt.allocPrint(a, "Unbacked enum {s} cannot be converted to a string", .{self.ctx.vm.declaredClassName(v.object.class_name)});
                    defer a.free(msg);
                    try self.ctx.vm.setPendingException("ValueError", msg);
                    return error.RuntimeError;
                }
                scalar = v.object.get("value");
            }
            switch (scalar) {
                .string => |str| try appendUrlEncodedMode(&self.buf, a, str.bytes(), self.rfc3986),
                .bool => |b| try self.buf.append(a, if (b) '1' else '0'),
                else => {
                    var tmp = std.ArrayListUnmanaged(u8).empty;
                    defer tmp.deinit(a);
                    try scalar.format(&tmp, a);
                    try appendUrlEncodedMode(&self.buf, a, tmp.items, self.rfc3986);
                },
            }
        }
    }
};

// the properties of o the calling scope can see, as get_object_vars lists them
fn native_get_object_vars_for(ctx: *NativeContext, o: *PhpObject) RuntimeError!*PhpArray {
    const r = try @import("types.zig").getObjectVars(ctx, o);
    return r;
}

fn appendUrlEncoded(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, s: []const u8) !void {
    try appendUrlEncodedMode(buf, a, s, false);
}

fn appendUrlEncodedMode(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, s: []const u8, rfc3986: bool) !void {
    for (s) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or (c == '~' and rfc3986)) {
            try buf.append(a, c);
        } else if (c == ' ' and !rfc3986) {
            try buf.append(a, '+');
        } else {
            try buf.append(a, '%');
            const hex = "0123456789ABCDEF";
            try buf.append(a, hex[c >> 4]);
            try buf.append(a, hex[c & 0xf]);
        }
    }
}

fn native_qp_decode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.literal("");
    const s = args[0].string.bytes();
    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '=' and i + 2 < s.len) {
            if (s[i + 1] == '\r' or s[i + 1] == '\n') {
                i += 2;
                if (i < s.len and s[i] == '\n') i += 1;
                continue;
            }
            const hi = std.fmt.charToDigit(s[i + 1], 16) catch {
                try buf.append(ctx.allocator, s[i]);
                i += 1;
                continue;
            };
            const lo = std.fmt.charToDigit(s[i + 2], 16) catch {
                try buf.append(ctx.allocator, s[i]);
                i += 1;
                continue;
            };
            try buf.append(ctx.allocator, hi * 16 + lo);
            i += 3;
        } else {
            try buf.append(ctx.allocator, s[i]);
            i += 1;
        }
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result));
}

fn native_parse_url(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const url = url_parse.parse(args[0].string.bytes()) orelse return NativeResult.scalar(.{ .bool = false });
    const key: i64 = if (args.len >= 2 and args[1] == .int) args[1].int else -1;

    if (key > -1) {
        const part: ?[]const u8 = switch (key) {
            0 => url.scheme,
            1 => url.host,
            2 => return if (url.has_port) NativeResult.scalar(.{ .int = url.port }) else NativeResult.scalar(.null),
            3 => url.user,
            4 => url.pass,
            5 => url.path,
            6 => url.query,
            7 => url.fragment,
            else => {
                const msg = try std.fmt.allocPrint(ctx.allocator, "parse_url(): Argument #2 ($component) must be a valid URL component identifier, {d} given", .{key});
                defer ctx.allocator.free(msg);
                try ctx.vm.setPendingException("ValueError", msg);
                return error.RuntimeError;
            },
        };
        const bytes = part orelse return NativeResult.scalar(.null);
        const copy = try ctx.allocator.dupe(u8, bytes);
        url_parse.replaceControlChars(copy);
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, copy));
    }

    var arr = try ctx.createArray();
    if (url.scheme) |s| try setUrlComponent(ctx, arr, "scheme", s);
    if (url.host) |h| try setUrlComponent(ctx, arr, "host", h);
    if (url.has_port) try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("port") }, .{ .int = url.port });
    if (url.user) |u| try setUrlComponent(ctx, arr, "user", u);
    if (url.pass) |p| try setUrlComponent(ctx, arr, "pass", p);
    if (url.path) |p| try setUrlComponent(ctx, arr, "path", p);
    if (url.query) |q| try setUrlComponent(ctx, arr, "query", q);
    if (url.fragment) |f| try setUrlComponent(ctx, arr, "fragment", f);
    return NativeResult.borrowed(.{ .array = arr });
}

fn urlDecodeSlice(ctx: *NativeContext, s: []const u8) !Value.String {
    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '%' and i + 2 < s.len) {
            const hi = hexVal(s[i + 1]) orelse {
                try buf.append(ctx.allocator, s[i]);
                i += 1;
                continue;
            };
            const lo = hexVal(s[i + 2]) orelse {
                try buf.append(ctx.allocator, s[i]);
                i += 1;
                continue;
            };
            try buf.append(ctx.allocator, (hi << 4) | lo);
            i += 3;
        } else if (s[i] == '+') {
            try buf.append(ctx.allocator, ' ');
            i += 1;
        } else {
            try buf.append(ctx.allocator, s[i]);
            i += 1;
        }
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    return Value.String.adopt(ctx.allocator, result);
}

fn native_parse_str(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.null);
    const s = args[0].string.bytes();

    const arr = try ctx.createArray();
    var rest = s;
    while (rest.len > 0) {
        var pair: []const u8 = undefined;
        if (std.mem.indexOf(u8, rest, "&")) |pos| {
            pair = rest[0..pos];
            rest = rest[pos + 1 ..];
        } else {
            pair = rest;
            rest = rest[rest.len..];
        }
        if (pair.len == 0) continue;

        var key: []const u8 = undefined;
        var val: []const u8 = "";
        if (std.mem.indexOf(u8, pair, "=")) |eq| {
            key = pair[0..eq];
            val = pair[eq + 1 ..];
        } else {
            key = pair;
        }

        const decoded_key = try urlDecodeSlice(ctx, key);
        defer decoded_key.release();
        const decoded_val = try urlDecodeSlice(ctx, val);
        defer decoded_val.release();
        try insertParsedKey(ctx, arr, decoded_key.bytes(), .{ .string = decoded_val });
    }
    if (args.len >= 2) {
        ctx.setCallerVar(1, args.len, .{ .array = arr });
    }
    return NativeResult.scalar(.null);
}

// PHP coerces invalid PHP-variable chars in the base part of parse_str keys
// (the bit before the first '[') to underscores: space, '.', '['. The chars
// inside brackets are kept as-is.
fn sanitizeParseStrKey(ctx: *NativeContext, name: []const u8) !Value.String {
    var needs_fix = false;
    for (name) |c| {
        if (c == ' ' or c == '.' or c == '[') {
            needs_fix = true;
            break;
        }
    }
    if (!needs_fix) return Value.String.create(ctx.allocator, name);
    const buf = try ctx.allocator.alloc(u8, name.len);
    for (name, 0..) |c, i| {
        buf[i] = if (c == ' ' or c == '.' or c == '[') '_' else c;
    }
    return Value.String.adopt(ctx.allocator, buf);
}

fn insertParsedKey(ctx: *NativeContext, root: *PhpArray, key: []const u8, value: Value) !void {
    // split "a[b][c]" -> base="a", segs=["b","c"]. an empty segment "[]" means append.
    const open = std.mem.indexOfScalar(u8, key, '[');
    const raw_base = if (open) |o| key[0..o] else key;
    // PHP drops keys with empty base name when bracket segments follow (e.g. "[a]=1")
    if (raw_base.len == 0 and open != null) return;
    const base_name = try sanitizeParseStrKey(ctx, raw_base);
    defer base_name.release();
    if (open == null) {
        try setParsedEntry(ctx, root, .{ .string = base_name }, value);
        return;
    }
    var segments: [16][]const u8 = undefined;
    var seg_count: usize = 0;
    var pos: usize = open.?;
    while (pos < key.len and seg_count < segments.len) {
        if (key[pos] != '[') break;
        const close = std.mem.indexOfScalarPos(u8, key, pos + 1, ']') orelse break;
        segments[seg_count] = key[pos + 1 .. close];
        seg_count += 1;
        pos = close + 1;
    }

    const base_key: PhpArray.Key = .{ .string = base_name };
    var current_arr: *PhpArray = root;
    var current_key: PhpArray.Key = base_key;
    var i: usize = 0;
    while (i < seg_count) : (i += 1) {
        const cur_v = current_arr.get(current_key);
        const next_arr: *PhpArray = blk: {
            if (cur_v == .array) break :blk cur_v.array;
            const new_a = try ctx.createArray();
            try setParsedEntry(ctx, current_arr, current_key, .{ .array = new_a });
            break :blk new_a;
        };
        const seg = segments[i];
        if (seg.len == 0) {
            // append: next_arr.append decides the int key
            current_arr = next_arr;
            // pre-compute next int key
            var max_int: i64 = -1;
            for (next_arr.entries.items) |e| {
                if (e.key == .int and e.key.int > max_int) max_int = e.key.int;
            }
            current_key = .{ .int = max_int + 1 };
        } else {
            current_arr = next_arr;
            if (std.fmt.parseInt(i64, seg, 10)) |n| {
                current_key = .{ .int = n };
            } else |_| {
                current_key = .{ .string = Value.String.borrowed(seg) };
            }
        }
    }
    try setParsedEntry(ctx, current_arr, current_key, value);
}

fn native_levenshtein(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .int = -1 });
    const s1 = args[0].string.bytes();
    const s2 = args[1].string.bytes();

    // PHP 8 lifted the historical 255-char cap; computes regardless of length.
    if (s1.len == 0) return NativeResult.scalar(.{ .int = @intCast(s2.len) });
    if (s2.len == 0) return NativeResult.scalar(.{ .int = @intCast(s1.len) });

    const cost_ins: i64 = if (args.len >= 3) Value.toInt(args[2]) else 1;
    const cost_rep: i64 = if (args.len >= 4) Value.toInt(args[3]) else 1;
    const cost_del: i64 = if (args.len >= 5) Value.toInt(args[4]) else 1;

    const rows = s1.len + 1;
    const cols = s2.len + 1;
    var prev = try ctx.allocator.alloc(i64, cols);
    defer ctx.allocator.free(prev);
    var curr = try ctx.allocator.alloc(i64, cols);
    defer ctx.allocator.free(curr);

    for (0..cols) |j| prev[j] = @as(i64, @intCast(j)) * cost_ins;

    for (0..s1.len) |i| {
        curr[0] = @as(i64, @intCast(i + 1)) * cost_del;
        for (0..s2.len) |j| {
            if (s1[i] == s2[j]) {
                curr[j + 1] = prev[j];
            } else {
                const ins = curr[j] + cost_ins;
                const del = prev[j + 1] + cost_del;
                const rep = prev[j] + cost_rep;
                curr[j + 1] = @min(ins, @min(del, rep));
            }
        }
        const tmp = prev;
        prev = curr;
        curr = tmp;
    }

    _ = rows;
    return NativeResult.scalar(.{ .int = prev[s2.len] });
}

fn similarTextImpl(s1: []const u8, s2: []const u8, longest: *i64) void {
    var max_len: i64 = 0;
    var best_s1: usize = 0;
    var best_s2: usize = 0;

    for (0..s1.len) |i| {
        for (0..s2.len) |j| {
            var l: usize = 0;
            while (i + l < s1.len and j + l < s2.len and s1[i + l] == s2[j + l]) l += 1;
            if (@as(i64, @intCast(l)) > max_len) {
                max_len = @intCast(l);
                best_s1 = i;
                best_s2 = j;
            }
        }
    }

    longest.* += max_len;
    if (max_len > 0) {
        if (best_s1 > 0 and best_s2 > 0) {
            similarTextImpl(s1[0..best_s1], s2[0..best_s2], longest);
        }
        const end1 = best_s1 + @as(usize, @intCast(max_len));
        const end2 = best_s2 + @as(usize, @intCast(max_len));
        if (end1 < s1.len and end2 < s2.len) {
            similarTextImpl(s1[end1..], s2[end2..], longest);
        }
    }
}

fn native_similar_text(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .int = 0 });
    const s1 = args[0].string.bytes();
    const s2 = args[1].string.bytes();

    var matching: i64 = 0;
    similarTextImpl(s1, s2, &matching);

    if (args.len >= 3) {
        const total: f64 = @floatFromInt(s1.len + s2.len);
        const pct: f64 = if (total > 0) @as(f64, @floatFromInt(matching * 2)) * 100.0 / total else 0.0;
        ctx.setCallerVar(2, args.len, .{ .float = pct });
    }

    return NativeResult.scalar(.{ .int = matching });
}

fn spanResolveRange(slen: i64, args: []const Value) struct { start: usize, end: usize } {
    var s_off: i64 = if (args.len >= 3) Value.toInt(args[2]) else 0;
    if (s_off < 0) s_off = @max(0, slen + s_off);
    if (s_off > slen) s_off = slen;
    const has_len = args.len >= 4 and args[3] != .null;
    var l_val: i64 = if (has_len) Value.toInt(args[3]) else slen - s_off;
    if (l_val < 0) l_val = @max(0, slen - s_off + l_val);
    var end_i: i64 = s_off + l_val;
    if (end_i > slen) end_i = slen;
    return .{ .start = @intCast(s_off), .end = @intCast(end_i) };
}

fn native_strcspn(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .int = 0 });
    const s = args[0].string.bytes();
    const chars = args[1].string.bytes();
    const r = spanResolveRange(@intCast(s.len), args);

    for (r.start..r.end) |i| {
        for (chars) |c| {
            if (s[i] == c) return NativeResult.scalar(.{ .int = @intCast(i - r.start) });
        }
    }
    return NativeResult.scalar(.{ .int = @intCast(r.end - r.start) });
}

fn native_strspn(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .int = 0 });
    const s = args[0].string.bytes();
    const chars = args[1].string.bytes();
    const r = spanResolveRange(@intCast(s.len), args);

    for (r.start..r.end) |i| {
        var found = false;
        for (chars) |c| {
            if (s[i] == c) {
                found = true;
                break;
            }
        }
        if (!found) return NativeResult.scalar(.{ .int = @intCast(i - r.start) });
    }
    return NativeResult.scalar(.{ .int = @intCast(r.end - r.start) });
}

// case-insensitive last-occurrence variant of mb_strstr - mirrors mb_strrchr
// but folds case on both sides. only the first character of $needle is used
fn native_mb_strrichr(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const haystack = args[0].string.bytes();
    const needle = args[1].string.bytes();
    if (needle.len == 0) return NativeResult.scalar(.{ .bool = false });
    const before: bool = if (args.len >= 3) Value.isTruthy(args[2]) else false;
    const n_first = lowerCpUtf8(needle, 0);
    var last: ?usize = null;
    var i: usize = 0;
    while (i < haystack.len) {
        const h = lowerCpUtf8(haystack, i);
        if (h.cp == n_first.cp) last = i;
        i += h.len;
    }
    if (last) |pos| {
        const slice = if (before) haystack[0..pos] else haystack[pos..];
        return NativeResult.copyString(ctx.allocator, slice);
    }
    return NativeResult.scalar(.{ .bool = false });
}

// replace invalid UTF-8 byte sequences with the substitute character. PHP's
// default substitute is `?` (0x3F) - one `?` per invalid byte, not per
// invalid sequence
fn native_mb_scrub(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.literal("");
    const s = args[0].string.bytes();
    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);
    var i: usize = 0;
    while (i < s.len) {
        const b = s[i];
        if (b < 0x80) {
            try buf.append(ctx.allocator, b);
            i += 1;
            continue;
        }
        const len = std.unicode.utf8ByteSequenceLength(b) catch {
            try buf.append(ctx.allocator, '?');
            i += 1;
            continue;
        };
        if (i + len > s.len) {
            try buf.append(ctx.allocator, '?');
            i += 1;
            continue;
        }
        _ = std.unicode.utf8Decode(s[i .. i + len]) catch {
            try buf.append(ctx.allocator, '?');
            i += 1;
            continue;
        };
        try buf.appendSlice(ctx.allocator, s[i .. i + len]);
        i += len;
    }
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, try buf.toOwnedSlice(ctx.allocator)));
}

// CLI always returns false (no HTTP input encoding context). when called with
// a setter arg, PHP returns true on success
fn native_mb_http_input(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len >= 1) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = false });
}

// default HTTP output encoding. setter returns true; getter returns "UTF-8"
fn native_mb_http_output(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len >= 1 and args[0] == .string) return NativeResult.scalar(.{ .bool = true });
    return NativeResult.literal("UTF-8");
}

// default language. setter accepts neutral/uni/japanese/english/german/etc.
// we don't differentiate behavior - getter always returns "neutral"
fn native_mb_language(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len >= 1 and args[0] == .string) return NativeResult.scalar(.{ .bool = true });
    return NativeResult.literal("neutral");
}

// map an internal encoding name to its MIME charset label
fn native_mb_preferred_mime_name(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const enc = args[0].string.bytes();
    var lo: [32]u8 = undefined;
    const cap = @min(enc.len, lo.len);
    for (enc[0..cap], 0..) |c, i| lo[i] = std.ascii.toLower(c);
    const l = lo[0..cap];
    if (std.mem.eql(u8, l, "utf-8") or std.mem.eql(u8, l, "utf8")) return NativeResult.literal("UTF-8");
    if (std.mem.eql(u8, l, "ascii") or std.mem.eql(u8, l, "us-ascii")) return NativeResult.literal("US-ASCII");
    if (std.mem.eql(u8, l, "iso-8859-1") or std.mem.eql(u8, l, "iso8859-1") or std.mem.eql(u8, l, "latin1")) return NativeResult.literal("ISO-8859-1");
    if (std.mem.eql(u8, l, "iso-8859-15")) return NativeResult.literal("ISO-8859-15");
    if (std.mem.eql(u8, l, "sjis") or std.mem.eql(u8, l, "shift_jis") or std.mem.eql(u8, l, "shift-jis")) return NativeResult.literal("Shift_JIS");
    if (std.mem.eql(u8, l, "euc-jp") or std.mem.eql(u8, l, "eucjp")) return NativeResult.literal("EUC-JP");
    if (std.mem.eql(u8, l, "iso-2022-jp")) return NativeResult.literal("ISO-2022-JP");
    if (std.mem.eql(u8, l, "utf-16")) return NativeResult.literal("UTF-16");
    if (std.mem.eql(u8, l, "utf-16be")) return NativeResult.literal("UTF-16BE");
    if (std.mem.eql(u8, l, "utf-16le")) return NativeResult.literal("UTF-16LE");
    if (std.mem.eql(u8, l, "utf-32")) return NativeResult.literal("UTF-32");
    const msg = try std.fmt.allocPrint(ctx.allocator, "mb_preferred_mime_name(): Argument #1 ($encoding) must be a valid encoding, \"{s}\" given", .{enc});
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("ValueError", msg);
    return error.RuntimeError;
}

// detection order. getter returns ['ASCII', 'UTF-8']; setter (array or
// comma-separated string) returns true
fn native_mb_detect_order(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len >= 1) {
        if (args[0] == .string or args[0] == .array) return NativeResult.scalar(.{ .bool = true });
        return NativeResult.scalar(.{ .bool = false });
    }
    var arr = try ctx.createArray();
    try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("ASCII") });
    try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("UTF-8") });
    return NativeResult.borrowed(.{ .array = arr });
}

// PHP returns either the full info array, a specific key's value, or false
// for an unknown key
fn native_mb_get_info(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const key: ?[]const u8 = if (args.len >= 1 and args[0] == .string) args[0].string.bytes() else null;
    if (key) |k| {
        if (std.mem.eql(u8, k, "internal_encoding")) return NativeResult.literal("UTF-8");
        if (std.mem.eql(u8, k, "http_input")) return NativeResult.literal("UTF-8");
        if (std.mem.eql(u8, k, "http_output")) return NativeResult.literal("UTF-8");
        if (std.mem.eql(u8, k, "http_output_conv_mimetypes")) return NativeResult.literal("^(text/|application/xhtml\\+xml)");
        if (std.mem.eql(u8, k, "mail_charset")) return NativeResult.literal("UTF-8");
        if (std.mem.eql(u8, k, "mail_header_encoding")) return NativeResult.literal("BASE64");
        if (std.mem.eql(u8, k, "mail_body_encoding")) return NativeResult.literal("BASE64");
        if (std.mem.eql(u8, k, "illegal_chars")) return NativeResult.scalar(.{ .int = 0 });
        if (std.mem.eql(u8, k, "encoding_translation")) return NativeResult.literal("Off");
        if (std.mem.eql(u8, k, "language")) return NativeResult.literal("neutral");
        if (std.mem.eql(u8, k, "detect_order")) {
            var arr = try ctx.createArray();
            try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("ASCII") });
            try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("UTF-8") });
            return NativeResult.borrowed(.{ .array = arr });
        }
        if (std.mem.eql(u8, k, "substitute_character")) return NativeResult.scalar(.{ .int = 63 });
        if (std.mem.eql(u8, k, "strict_detection")) return NativeResult.literal("Off");
        if (std.mem.eql(u8, k, "all")) {} // fall through to full array
        else {
            try ctx.vm.emitWarning("mb_get_info(): argument #1 ($type) must be a valid type");
            return NativeResult.scalar(.{ .bool = false });
        }
    }
    var arr = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("internal_encoding") }, .{ .string = Value.String.borrowed("UTF-8") });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("http_output") }, .{ .string = Value.String.borrowed("UTF-8") });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("http_output_conv_mimetypes") }, .{ .string = Value.String.borrowed("^(text/|application/xhtml\\+xml)") });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("mail_charset") }, .{ .string = Value.String.borrowed("UTF-8") });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("mail_header_encoding") }, .{ .string = Value.String.borrowed("BASE64") });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("mail_body_encoding") }, .{ .string = Value.String.borrowed("BASE64") });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("illegal_chars") }, .{ .int = 0 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("encoding_translation") }, .{ .string = Value.String.borrowed("Off") });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("language") }, .{ .string = Value.String.borrowed("neutral") });
    var order = try ctx.createArray();
    try order.append(ctx.allocator, .{ .string = Value.String.borrowed("ASCII") });
    try order.append(ctx.allocator, .{ .string = Value.String.borrowed("UTF-8") });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("detect_order") }, .{ .array = order });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("substitute_character") }, .{ .int = 63 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("strict_detection") }, .{ .string = Value.String.borrowed("Off") });
    return NativeResult.borrowed(.{ .array = arr });
}

// for UTF-8 input mb_parse_str is byte-identical to parse_str; delegate
fn native_mb_parse_str(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return native_parse_str(ctx, args);
}

fn setParsedEntry(ctx: *NativeContext, array: *PhpArray, key: PhpArray.Key, value: Value) !void {
    if (key == .string) {
        const owned = try Value.String.create(ctx.allocator, key.string.bytes());
        defer owned.release();
        try ctx.vm.arraySetOwned(array, .{ .string = owned }, value);
    } else {
        try ctx.vm.arraySetOwned(array, key, value);
    }
}

fn setUrlComponent(ctx: *NativeContext, array: *PhpArray, comptime name: []const u8, bytes: []const u8) !void {
    const copy = try ctx.allocator.dupe(u8, bytes);
    url_parse.replaceControlChars(copy);
    const value = try Value.String.adopt(ctx.allocator, copy);
    defer value.release();
    try array.set(ctx.allocator, .{ .string = Value.String.borrowed(name) }, .{ .string = value });
}
