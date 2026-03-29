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
    .{ "strcmp", native_strcmp },
    .{ "strncmp", native_strncmp },
    .{ "ord", native_ord },
    .{ "chr", native_chr },
    .{ "str_split", native_str_split },
    .{ "substr_count", native_substr_count },
    .{ "substr_replace", native_substr_replace },
    .{ "str_word_count", native_str_word_count },
    .{ "nl2br", native_nl2br },
    .{ "wordwrap", native_wordwrap },
    .{ "chunk_split", native_chunk_split },
    .{ "number_format", native_number_format },
    .{ "sprintf", native_sprintf },
    .{ "printf", native_printf },
    .{ "addslashes", native_addslashes },
    .{ "stripslashes", native_stripslashes },
    .{ "htmlspecialchars", native_htmlspecialchars },
    .{ "htmlspecialchars_decode", native_htmlspecialchars_decode },
    .{ "hex2bin", native_hex2bin },
    .{ "bin2hex", native_bin2hex },
    .{ "mb_strlen", native_mb_strlen },
    .{ "mb_strtolower", native_mb_strtolower },
    .{ "mb_strtoupper", native_mb_strtoupper },
    .{ "mb_detect_encoding", native_mb_detect_encoding },
    .{ "mb_convert_encoding", native_mb_convert_encoding },
    .{ "iconv", native_iconv },
    .{ "iconv_strlen", native_mb_strlen },
    .{ "iconv_strpos", native_mb_strpos },
    .{ "iconv_substr", native_mb_substr },
    .{ "mb_strpos", native_mb_strpos },
    .{ "mb_strrpos", native_mb_strrpos },
    .{ "mb_substr_count", native_mb_substr_count },
    .{ "mb_internal_encoding", native_mb_internal_encoding },
    .{ "mb_substitute_character", native_mb_substitute_character },
    .{ "str_getcsv", native_str_getcsv },
    .{ "base64_encode", native_base64_encode },
    .{ "base64_decode", native_base64_decode },
    .{ "urlencode", native_urlencode },
    .{ "urldecode", native_urldecode },
    .{ "rawurlencode", native_rawurlencode },
    .{ "rawurldecode", native_rawurldecode },
    .{ "md5", native_md5 },
    .{ "sha1", native_sha1 },
    .{ "mb_substr", native_mb_substr },
    .{ "html_entity_decode", native_htmlspecialchars_decode },
    .{ "strrev", native_strrev },
    .{ "stripos", native_stripos },
    .{ "strrpos", native_strrpos },
    .{ "strripos", native_strripos },
    .{ "str_ireplace", native_str_ireplace },
    .{ "ucwords", native_ucwords },
    .{ "crc32", native_crc32 },
    .{ "str_rot13", native_str_rot13 },
    .{ "quotemeta", native_quotemeta },
    .{ "mb_trim", native_mb_trim },
    .{ "mb_ltrim", native_mb_ltrim },
    .{ "mb_rtrim", native_mb_rtrim },
    .{ "mb_ucfirst", native_mb_ucfirst },
    .{ "mb_lcfirst", native_mb_lcfirst },
    .{ "strip_tags", native_strip_tags },
    .{ "http_build_query", native_http_build_query },
    .{ "htmlentities", native_htmlspecialchars },
    .{ "quoted_printable_encode", native_qp_encode },
    .{ "quoted_printable_decode", native_qp_decode },
    .{ "parse_url", native_parse_url },
    .{ "parse_str", native_parse_str },
    .{ "strstr", native_strstr },
    .{ "strchr", native_strstr },
    .{ "strtr", native_strtr },
    .{ "vsprintf", native_vsprintf },
    .{ "levenshtein", native_levenshtein },
    .{ "similar_text", native_similar_text },
    .{ "soundex", native_soundex },
    .{ "metaphone", native_metaphone },
    .{ "count_chars", native_count_chars },
    .{ "str_increment", native_str_increment },
    .{ "str_decrement", native_str_decrement },
    .{ "substr_compare", native_substr_compare },
    .{ "strcspn", native_strcspn },
    .{ "strspn", native_strspn },
    .{ "strpbrk", native_strpbrk },
};

fn substr(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const slen: i64 = @intCast(s.len);
    var start = Value.toInt(args[1]);
    if (start < 0) start = @max(0, slen + start);
    if (start >= slen) return .{ .string = "" };
    const ustart: usize = @intCast(start);

    if (args.len >= 3 and args[2] != .null) {
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

fn replaceOne(ctx: *NativeContext, subject: []const u8, search: []const u8, replace: []const u8) ![]const u8 {
    if (search.len == 0) return subject;
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
    return s;
}

fn str_replace(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3) return if (args.len >= 3) args[2] else Value{ .string = "" };

    if (args[0] == .array) {
        const searches = args[0].array;
        var result = if (args[2] == .string) args[2].string else return args[2];
        for (searches.entries.items, 0..) |entry, idx| {
            const needle = if (entry.value == .string) entry.value.string else continue;
            const replacement = if (args[1] == .array) blk: {
                break :blk if (idx < args[1].array.entries.items.len)
                    (if (args[1].array.entries.items[idx].value == .string) args[1].array.entries.items[idx].value.string else "")
                else
                    "";
            } else if (args[1] == .string) args[1].string else "";
            result = try replaceOne(ctx, result, needle, replacement);
        }
        return .{ .string = result };
    }

    const search = if (args[0] == .string) args[0].string else return args[2];
    const replace = if (args[1] == .string) args[1].string else return args[2];
    const subject = if (args[2] == .string) args[2].string else return args[2];
    const s = try replaceOne(ctx, subject, search, replace);
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

const default_trim_chars = " \t\n\r\x0b\x00";

fn trim(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const chars = if (args.len >= 2 and args[1] == .string) args[1].string else default_trim_chars;
    return .{ .string = try ctx.createString(std.mem.trim(u8, s, chars)) };
}

fn ltrim(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const chars = if (args.len >= 2 and args[1] == .string) args[1].string else default_trim_chars;
    return .{ .string = try ctx.createString(std.mem.trimLeft(u8, s, chars)) };
}

fn rtrim(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const chars = if (args.len >= 2 and args[1] == .string) args[1].string else default_trim_chars;
    return .{ .string = try ctx.createString(std.mem.trimRight(u8, s, chars)) };
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
    } else if (pad_type == 2) {
        const left = diff / 2;
        const right = diff - left;
        var i: usize = 0;
        while (i < left) : (i += 1) try buf.append(ctx.allocator, pad_str[i % pad_str.len]);
        try buf.appendSlice(ctx.allocator, s);
        i = 0;
        while (i < right) : (i += 1) try buf.append(ctx.allocator, pad_str[i % pad_str.len]);
    } else {
        try buf.appendSlice(ctx.allocator, s);
        var i: usize = 0;
        while (i < diff) : (i += 1) try buf.append(ctx.allocator, pad_str[i % pad_str.len]);
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn native_strcmp(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .int = 0 };
    const a = if (args[0] == .string) args[0].string else "";
    const b = if (args[1] == .string) args[1].string else "";
    const min_len = @min(a.len, b.len);
    for (0..min_len) |i| {
        if (a[i] != b[i]) return .{ .int = @as(i64, a[i]) - @as(i64, b[i]) };
    }
    if (a.len != b.len) return .{ .int = @as(i64, @intCast(a.len)) - @as(i64, @intCast(b.len)) };
    return .{ .int = 0 };
}

fn native_strncmp(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3) return .{ .int = 0 };
    const a = if (args[0] == .string) args[0].string else "";
    const b = if (args[1] == .string) args[1].string else "";
    const n: usize = @intCast(@max(0, Value.toInt(args[2])));
    const sa = a[0..@min(n, a.len)];
    const sb = b[0..@min(n, b.len)];
    return .{ .int = switch (std.mem.order(u8, sa, sb)) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    } };
}

fn native_ord(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
    const s = if (args[0] == .string) args[0].string else return Value{ .int = 0 };
    if (s.len == 0) return .{ .int = 0 };
    return .{ .int = s[0] };
}

fn native_chr(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "\x00" };
    const code: u8 = @truncate(@as(u64, @bitCast(Value.toInt(args[0]))));
    const buf = try ctx.allocator.alloc(u8, 1);
    buf[0] = code;
    try ctx.strings.append(ctx.allocator, buf);
    return .{ .string = buf };
}

fn native_str_split(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .null;
    const s = if (args[0] == .string) args[0].string else return Value.null;
    const chunk_len: usize = if (args.len >= 2) @intCast(@max(1, Value.toInt(args[1]))) else 1;

    var arr = try ctx.createArray();
    var i: usize = 0;
    while (i < s.len) {
        const end = @min(i + chunk_len, s.len);
        try arr.append(ctx.allocator, .{ .string = try ctx.createString(s[i..end]) });
        i = end;
    }
    if (s.len == 0) try arr.append(ctx.allocator, .{ .string = "" });
    return .{ .array = arr };
}

fn native_substr_count(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .int = 0 };
    const haystack = if (args[0] == .string) args[0].string else return Value{ .int = 0 };
    const needle = if (args[1] == .string) args[1].string else return Value{ .int = 0 };
    if (needle.len == 0) return .{ .int = 0 };
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
    return .{ .int = count };
}

fn native_substr_replace(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3) return if (args.len > 0) args[0] else Value{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const replacement = if (args[1] == .string) args[1].string else "";
    const slen: i64 = @intCast(s.len);
    var start = Value.toInt(args[2]);
    if (start < 0) start = @max(0, slen + start);
    if (start > slen) start = slen;
    const ustart: usize = @intCast(start);

    var end: usize = s.len;
    if (args.len >= 4) {
        const length = Value.toInt(args[3]);
        if (length < 0) {
            end = @intCast(@max(0, slen + length));
            if (end < ustart) end = ustart;
        } else {
            end = @min(s.len, ustart + @as(usize, @intCast(@max(0, length))));
        }
    }

    var buf = std.ArrayListUnmanaged(u8){};
    try buf.appendSlice(ctx.allocator, s[0..ustart]);
    try buf.appendSlice(ctx.allocator, replacement);
    if (end < s.len) try buf.appendSlice(ctx.allocator, s[end..]);
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn native_str_word_count(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
    const s = if (args[0] == .string) args[0].string else return Value{ .int = 0 };
    const format: i64 = if (args.len > 1) Value.toInt(args[1]) else 0;

    if (format == 0) {
        var count: i64 = 0;
        var in_word = false;
        for (s) |c| {
            if (std.ascii.isAlphabetic(c) or c == '\'' or c == '-') {
                if (!in_word) {
                    count += 1;
                    in_word = true;
                }
            } else {
                in_word = false;
            }
        }
        return .{ .int = count };
    }

    var arr = try ctx.createArray();
    var in_word = false;
    var word_start: usize = 0;
    for (s, 0..) |c, i| {
        if (std.ascii.isAlphabetic(c) or c == '\'' or c == '-') {
            if (!in_word) {
                word_start = i;
                in_word = true;
            }
        } else {
            if (in_word) {
                const word = s[word_start..i];
                if (format == 2) {
                    try arr.set(ctx.allocator, .{ .int = @intCast(word_start) }, .{ .string = word });
                } else {
                    try arr.append(ctx.allocator, .{ .string = word });
                }
                in_word = false;
            }
        }
    }
    if (in_word) {
        const word = s[word_start..];
        if (format == 2) {
            try arr.set(ctx.allocator, .{ .int = @intCast(word_start) }, .{ .string = word });
        } else {
            try arr.append(ctx.allocator, .{ .string = word });
        }
    }
    return .{ .array = arr };
}

fn native_nl2br(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    var buf = std.ArrayListUnmanaged(u8){};
    for (s) |c| {
        if (c == '\n') {
            try buf.appendSlice(ctx.allocator, "<br />\n");
        } else {
            try buf.append(ctx.allocator, c);
        }
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn native_wordwrap(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const width: usize = if (args.len >= 2) @intCast(@max(1, Value.toInt(args[1]))) else 75;
    const brk = if (args.len >= 3 and args[2] == .string) args[2].string else "\n";
    const cut = args.len >= 4 and args[3].isTruthy();

    var buf = std.ArrayListUnmanaged(u8){};
    var line_start: usize = 0;
    var last_space: ?usize = null;
    var i: usize = 0;

    while (i < s.len) {
        if (s[i] == '\n') {
            try buf.appendSlice(ctx.allocator, s[line_start .. i + 1]);
            i += 1;
            line_start = i;
            last_space = null;
            continue;
        }
        if (s[i] == ' ') last_space = i;
        const line_len = i - line_start;
        if (line_len >= width) {
            if (last_space) |sp| {
                try buf.appendSlice(ctx.allocator, s[line_start..sp]);
                try buf.appendSlice(ctx.allocator, brk);
                line_start = sp + 1;
                last_space = null;
            } else if (cut) {
                try buf.appendSlice(ctx.allocator, s[line_start..i]);
                try buf.appendSlice(ctx.allocator, brk);
                line_start = i;
                last_space = null;
            }
        }
        i += 1;
    }
    if (line_start < s.len) try buf.appendSlice(ctx.allocator, s[line_start..]);
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn native_chunk_split(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const chunklen: usize = if (args.len >= 2) @intCast(@max(1, Value.toInt(args[1]))) else 76;
    const end = if (args.len >= 3 and args[2] == .string) args[2].string else "\r\n";

    var buf = std.ArrayListUnmanaged(u8){};
    var i: usize = 0;
    while (i < s.len) {
        const chunk_end = @min(i + chunklen, s.len);
        try buf.appendSlice(ctx.allocator, s[i..chunk_end]);
        try buf.appendSlice(ctx.allocator, end);
        i = chunk_end;
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn native_number_format(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "0" };
    const num = Value.toFloat(args[0]);
    const decimals: usize = if (args.len >= 2) @intCast(@max(0, Value.toInt(args[1]))) else 0;
    const dec_point = if (args.len >= 3 and args[2] == .string) args[2].string else ".";
    const thousands_sep = if (args.len >= 4 and args[3] == .string) args[3].string else ",";

    const rounded = if (decimals == 0) @round(num) else blk: {
        const factor = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(decimals)));
        break :blk @round(num * factor) / factor;
    };
    const is_negative = rounded < 0;
    const abs_val = @abs(rounded);

    const int_part: u64 = @intFromFloat(abs_val);
    var int_buf: [32]u8 = undefined;
    const int_str = std.fmt.bufPrint(&int_buf, "{d}", .{int_part}) catch return Value{ .string = "0" };

    var buf = std.ArrayListUnmanaged(u8){};
    if (is_negative) try buf.append(ctx.allocator, '-');

    if (thousands_sep.len > 0 and int_str.len > 3) {
        const first_group = int_str.len % 3;
        if (first_group > 0) {
            try buf.appendSlice(ctx.allocator, int_str[0..first_group]);
        }
        var i: usize = first_group;
        while (i < int_str.len) {
            if (i > 0) try buf.appendSlice(ctx.allocator, thousands_sep);
            try buf.appendSlice(ctx.allocator, int_str[i .. i + 3]);
            i += 3;
        }
    } else {
        try buf.appendSlice(ctx.allocator, int_str);
    }

    if (decimals > 0) {
        try buf.appendSlice(ctx.allocator, dec_point);
        const frac = abs_val - @as(f64, @floatFromInt(int_part));
        const factor = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(decimals)));
        const frac_int: u64 = @intFromFloat(@round(frac * factor));
        var frac_buf: [32]u8 = undefined;
        const frac_str = std.fmt.bufPrint(&frac_buf, "{d}", .{frac_int}) catch "0";
        var pad: usize = if (decimals > frac_str.len) decimals - frac_str.len else 0;
        while (pad > 0) : (pad -= 1) try buf.append(ctx.allocator, '0');
        try buf.appendSlice(ctx.allocator, frac_str[0..@min(frac_str.len, decimals)]);
    }

    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn native_sprintf(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const fmt_str = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const result = try sprintfImpl(ctx, fmt_str, args[1..]);
    return .{ .string = result };
}

fn native_printf(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
    const fmt_str = if (args[0] == .string) args[0].string else return Value{ .int = 0 };
    const result = try sprintfImpl(ctx, fmt_str, args[1..]);
    try ctx.vm.output.appendSlice(ctx.allocator, result);
    return .{ .int = @intCast(result.len) };
}

fn sprintfImpl(ctx: *NativeContext, fmt_str: []const u8, args: []const Value) ![]const u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    var i: usize = 0;
    var arg_idx: usize = 0;
    while (i < fmt_str.len) {
        if (fmt_str[i] == '%') {
            i += 1;
            if (i >= fmt_str.len) break;
            if (fmt_str[i] == '%') {
                try buf.append(ctx.allocator, '%');
                i += 1;
                continue;
            }

            var pad_char: u8 = ' ';
            var left_align = false;
            var show_sign = false;

            if (i < fmt_str.len and fmt_str[i] == '-') {
                left_align = true;
                i += 1;
            }
            if (i < fmt_str.len and fmt_str[i] == '+') {
                show_sign = true;
                i += 1;
            }
            if (i < fmt_str.len and fmt_str[i] == '0') {
                pad_char = '0';
                i += 1;
            }
            if (i + 1 < fmt_str.len and fmt_str[i] == '\'') {
                pad_char = fmt_str[i + 1];
                i += 2;
            }

            var width: usize = 0;
            while (i < fmt_str.len and fmt_str[i] >= '0' and fmt_str[i] <= '9') {
                width = width * 10 + (fmt_str[i] - '0');
                i += 1;
            }

            var precision: ?usize = null;
            if (i < fmt_str.len and fmt_str[i] == '.') {
                i += 1;
                precision = 0;
                while (i < fmt_str.len and fmt_str[i] >= '0' and fmt_str[i] <= '9') {
                    precision.? = precision.? * 10 + (fmt_str[i] - '0');
                    i += 1;
                }
            }

            if (i >= fmt_str.len) break;
            const spec = fmt_str[i];
            i += 1;
            const arg = if (arg_idx < args.len) args[arg_idx] else Value.null;
            arg_idx += 1;

            var tmp_buf = std.ArrayListUnmanaged(u8){};
            switch (spec) {
                's' => {
                    if (arg == .string) {
                        const s = arg.string;
                        if (precision) |p| {
                            try tmp_buf.appendSlice(ctx.allocator, s[0..@min(p, s.len)]);
                        } else {
                            try tmp_buf.appendSlice(ctx.allocator, s);
                        }
                    } else {
                        try arg.format(&tmp_buf, ctx.allocator);
                    }
                },
                'd' => {
                    const v = Value.toInt(arg);
                    if (show_sign and v >= 0) try tmp_buf.append(ctx.allocator, '+');
                    var num_buf: [32]u8 = undefined;
                    const s = std.fmt.bufPrint(&num_buf, "{d}", .{v}) catch "0";
                    try tmp_buf.appendSlice(ctx.allocator, s);
                },
                'f' => {
                    const v = Value.toFloat(arg);
                    const prec = precision orelse 6;
                    if (show_sign and v >= 0) try tmp_buf.append(ctx.allocator, '+');
                    try formatFixedFloat(&tmp_buf, ctx.allocator, v, prec);
                },
                'x' => {
                    const v: u64 = @bitCast(Value.toInt(arg));
                    var num_buf: [17]u8 = undefined;
                    const s = std.fmt.bufPrint(&num_buf, "{x}", .{v}) catch "0";
                    try tmp_buf.appendSlice(ctx.allocator, s);
                },
                'X' => {
                    const v: u64 = @bitCast(Value.toInt(arg));
                    var num_buf: [17]u8 = undefined;
                    const s = std.fmt.bufPrint(&num_buf, "{X}", .{v}) catch "0";
                    try tmp_buf.appendSlice(ctx.allocator, s);
                },
                'o' => {
                    const v: u64 = @bitCast(Value.toInt(arg));
                    var num_buf: [32]u8 = undefined;
                    const s = std.fmt.bufPrint(&num_buf, "{o}", .{v}) catch "0";
                    try tmp_buf.appendSlice(ctx.allocator, s);
                },
                'b' => {
                    const v: u64 = @bitCast(Value.toInt(arg));
                    var num_buf: [65]u8 = undefined;
                    const s = std.fmt.bufPrint(&num_buf, "{b}", .{v}) catch "0";
                    try tmp_buf.appendSlice(ctx.allocator, s);
                },
                'c' => {
                    const v: u8 = @truncate(@as(u64, @bitCast(Value.toInt(arg))));
                    try tmp_buf.append(ctx.allocator, v);
                },
                'e' => {
                    const v = Value.toFloat(arg);
                    const prec = precision orelse 6;
                    if (show_sign and v >= 0) try tmp_buf.append(ctx.allocator, '+');
                    try formatScientific(&tmp_buf, ctx.allocator, v, prec);
                },
                else => {
                    try buf.append(ctx.allocator, '%');
                    try buf.append(ctx.allocator, spec);
                    continue;
                },
            }

            const formatted = tmp_buf.items;
            if (width > formatted.len) {
                const padding = width - formatted.len;
                if (left_align) {
                    try buf.appendSlice(ctx.allocator, formatted);
                    for (0..padding) |_| try buf.append(ctx.allocator, pad_char);
                } else {
                    for (0..padding) |_| try buf.append(ctx.allocator, pad_char);
                    try buf.appendSlice(ctx.allocator, formatted);
                }
            } else {
                try buf.appendSlice(ctx.allocator, formatted);
            }
            tmp_buf.deinit(ctx.allocator);
        } else {
            try buf.append(ctx.allocator, fmt_str[i]);
            i += 1;
        }
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return result;
}

fn formatFixedFloat(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, val: f64, prec: usize) !void {
    const is_neg = val < 0;
    const abs_val = @abs(val);
    const int_part: u64 = @intFromFloat(abs_val);
    const factor = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(prec)));
    const frac = @abs(abs_val - @as(f64, @floatFromInt(int_part)));
    const frac_int: u64 = @intFromFloat(@round(frac * factor));

    if (is_neg) try buf.append(a, '-');
    var int_buf: [32]u8 = undefined;
    const int_str = std.fmt.bufPrint(&int_buf, "{d}", .{int_part}) catch "0";
    try buf.appendSlice(a, int_str);

    if (prec > 0) {
        try buf.append(a, '.');
        var frac_buf: [32]u8 = undefined;
        const frac_str = std.fmt.bufPrint(&frac_buf, "{d}", .{frac_int}) catch "0";
        var pad: usize = if (prec > frac_str.len) prec - frac_str.len else 0;
        while (pad > 0) : (pad -= 1) try buf.append(a, '0');
        try buf.appendSlice(a, frac_str[0..@min(frac_str.len, prec)]);
    }
}

fn formatScientific(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, val: f64, prec: usize) !void {
    if (val == 0) {
        try buf.appendSlice(a, "0.");
        for (0..prec) |_| try buf.append(a, '0');
        try buf.appendSlice(a, "e+0");
        return;
    }
    const is_neg = val < 0;
    const abs_val = @abs(val);
    const exp_val: i32 = @intFromFloat(@floor(std.math.log10(abs_val)));
    const mantissa = abs_val / std.math.pow(f64, 10.0, @as(f64, @floatFromInt(exp_val)));

    if (is_neg) try buf.append(a, '-');
    try formatFixedFloat(buf, a, mantissa, prec);
    try buf.append(a, 'e');
    try buf.append(a, if (exp_val >= 0) '+' else '-');
    var exp_buf: [16]u8 = undefined;
    const abs_exp: u32 = @intCast(if (exp_val < 0) -exp_val else exp_val);
    const exp_str = std.fmt.bufPrint(&exp_buf, "{d}", .{abs_exp}) catch "0";
    try buf.appendSlice(a, exp_str);
}

fn native_addslashes(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    var buf = std.ArrayListUnmanaged(u8){};
    for (s) |c| {
        if (c == '\'' or c == '"' or c == '\\' or c == 0) {
            try buf.append(ctx.allocator, '\\');
        }
        try buf.append(ctx.allocator, c);
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn native_stripslashes(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    var buf = std.ArrayListUnmanaged(u8){};
    var j: usize = 0;
    while (j < s.len) {
        if (s[j] == '\\' and j + 1 < s.len) {
            j += 1;
        }
        try buf.append(ctx.allocator, s[j]);
        j += 1;
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn native_htmlspecialchars(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    var buf = std.ArrayListUnmanaged(u8){};
    for (s) |c| {
        switch (c) {
            '&' => try buf.appendSlice(ctx.allocator, "&amp;"),
            '"' => try buf.appendSlice(ctx.allocator, "&quot;"),
            '\'' => try buf.appendSlice(ctx.allocator, "&#039;"),
            '<' => try buf.appendSlice(ctx.allocator, "&lt;"),
            '>' => try buf.appendSlice(ctx.allocator, "&gt;"),
            else => try buf.append(ctx.allocator, c),
        }
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn native_htmlspecialchars_decode(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    var buf = std.ArrayListUnmanaged(u8){};
    var j: usize = 0;
    while (j < s.len) {
        if (s[j] == '&') {
            if (matchEntity(s[j..])) |ent| {
                try buf.append(ctx.allocator, ent.char);
                j += ent.len;
                continue;
            }
        }
        try buf.append(ctx.allocator, s[j]);
        j += 1;
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

const EntityMatch = struct { char: u8, len: usize };

fn matchEntity(s: []const u8) ?EntityMatch {
    const entities = .{
        .{ "&amp;", '&' },
        .{ "&quot;", '"' },
        .{ "&#039;", '\'' },
        .{ "&lt;", '<' },
        .{ "&gt;", '>' },
    };
    inline for (entities) |ent| {
        if (s.len >= ent[0].len and std.mem.eql(u8, s[0..ent[0].len], ent[0])) {
            return .{ .char = ent[1], .len = ent[0].len };
        }
    }
    return null;
}

fn native_hex2bin(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    const s = if (args[0] == .string) args[0].string else return Value{ .bool = false };
    if (s.len % 2 != 0) return .{ .bool = false };
    const out_len = s.len / 2;
    const buf = try ctx.allocator.alloc(u8, out_len);
    for (0..out_len) |j| {
        const hi = hexVal(s[j * 2]) orelse {
            ctx.allocator.free(buf);
            return .{ .bool = false };
        };
        const lo = hexVal(s[j * 2 + 1]) orelse {
            ctx.allocator.free(buf);
            return .{ .bool = false };
        };
        buf[j] = (hi << 4) | lo;
    }
    try ctx.strings.append(ctx.allocator, buf);
    return .{ .string = buf };
}

fn hexVal(c: u8) ?u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    return null;
}

fn native_bin2hex(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const hex_chars = "0123456789abcdef";
    const buf = try ctx.allocator.alloc(u8, s.len * 2);
    for (s, 0..) |c, j| {
        buf[j * 2] = hex_chars[c >> 4];
        buf[j * 2 + 1] = hex_chars[c & 0x0f];
    }
    try ctx.strings.append(ctx.allocator, buf);
    return .{ .string = buf };
}

fn native_mb_strlen(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
    const s = if (args[0] == .string) args[0].string else return Value{ .int = 0 };
    var count: i64 = 0;
    var j: usize = 0;
    while (j < s.len) {
        const byte = s[j];
        if (byte < 0x80) {
            j += 1;
        } else if (byte < 0xE0) {
            j += 2;
        } else if (byte < 0xF0) {
            j += 3;
        } else {
            j += 4;
        }
        count += 1;
    }
    return .{ .int = count };
}

fn native_mb_strtolower(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return strtolower(ctx, args);
}

fn native_mb_strtoupper(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return strtoupper(ctx, args);
}

fn native_mb_detect_encoding(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    return .{ .string = "UTF-8" };
}

fn native_mb_convert_encoding(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string) return .{ .bool = false };
    return args[0];
}

fn native_iconv(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[2] != .string) return .{ .bool = false };
    return args[2];
}

fn native_mb_strpos(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const haystack = args[0].string;
    const needle = args[1].string;
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
    if (byte_offset >= haystack.len) return .{ .bool = false };
    if (std.mem.indexOf(u8, haystack[byte_offset..], needle)) |pos| {
        var char_pos: i64 = 0;
        var j: usize = 0;
        while (j < byte_offset + pos) {
            j += utf8CharLen(haystack[j]);
            char_pos += 1;
        }
        return .{ .int = char_pos };
    }
    return .{ .bool = false };
}

fn native_mb_strrpos(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const haystack = args[0].string;
    const needle = args[1].string;
    if (std.mem.lastIndexOf(u8, haystack, needle)) |pos| {
        var char_pos: i64 = 0;
        var j: usize = 0;
        while (j < pos) {
            j += utf8CharLen(haystack[j]);
            char_pos += 1;
        }
        return .{ .int = char_pos };
    }
    return .{ .bool = false };
}

fn native_mb_substr_count(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .int = 0 };
    const haystack = args[0].string;
    const needle = args[1].string;
    if (needle.len == 0) return .{ .int = 0 };
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
    return .{ .int = count };
}

fn native_mb_internal_encoding(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .string = "UTF-8" };
}

fn native_mb_substitute_character(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = true };
}

fn utf8CharLen(byte: u8) usize {
    if (byte < 0x80) return 1;
    if (byte < 0xE0) return 2;
    if (byte < 0xF0) return 3;
    return 4;
}

fn native_str_getcsv(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .null;
    const s = if (args[0] == .string) args[0].string else return Value.null;
    const sep: u8 = if (args.len >= 2 and args[1] == .string and args[1].string.len > 0) args[1].string[0] else ',';
    const enc: u8 = if (args.len >= 3 and args[2] == .string and args[2].string.len > 0) args[2].string[0] else '"';

    var arr = try ctx.createArray();
    var j: usize = 0;
    while (j < s.len) {
        if (s[j] == enc) {
            j += 1;
            var field = std.ArrayListUnmanaged(u8){};
            while (j < s.len) {
                if (s[j] == enc) {
                    if (j + 1 < s.len and s[j + 1] == enc) {
                        try field.append(ctx.allocator, enc);
                        j += 2;
                    } else {
                        j += 1;
                        break;
                    }
                } else {
                    try field.append(ctx.allocator, s[j]);
                    j += 1;
                }
            }
            const f = try field.toOwnedSlice(ctx.allocator);
            try ctx.strings.append(ctx.allocator, f);
            try arr.append(ctx.allocator, .{ .string = f });
            if (j < s.len and s[j] == sep) j += 1;
        } else {
            var end = j;
            while (end < s.len and s[end] != sep) end += 1;
            try arr.append(ctx.allocator, .{ .string = try ctx.createString(s[j..end]) });
            j = if (end < s.len) end + 1 else end + 1;
        }
    }
    return .{ .array = arr };
}

const base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

fn native_base64_encode(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    if (s.len == 0) return .{ .string = "" };

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
    try ctx.strings.append(ctx.allocator, buf);
    return .{ .string = buf };
}

fn base64Decode(c: u8) ?u6 {
    if (c >= 'A' and c <= 'Z') return @intCast(c - 'A');
    if (c >= 'a' and c <= 'z') return @intCast(c - 'a' + 26);
    if (c >= '0' and c <= '9') return @intCast(c - '0' + 52);
    if (c == '+') return 62;
    if (c == '/') return 63;
    return null;
}

fn native_base64_decode(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    const s = if (args[0] == .string) args[0].string else return Value{ .bool = false };
    if (s.len == 0) return .{ .string = "" };

    var buf = std.ArrayListUnmanaged(u8){};
    var accum: u24 = 0;
    var bits: u5 = 0;
    for (s) |c| {
        if (c == '=') break;
        if (c == ' ' or c == '\n' or c == '\r' or c == '\t') continue;
        const val = base64Decode(c) orelse continue;
        accum = (accum << 6) | val;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            try buf.append(ctx.allocator, @truncate(accum >> bits));
        }
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn native_urlencode(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    var buf = std.ArrayListUnmanaged(u8){};
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
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn native_urldecode(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    var buf = std.ArrayListUnmanaged(u8){};
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
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn native_rawurlencode(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    var buf = std.ArrayListUnmanaged(u8){};
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
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn native_rawurldecode(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    var buf = std.ArrayListUnmanaged(u8){};
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
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn native_md5(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    var hash: [16]u8 = undefined;
    std.crypto.hash.Md5.hash(s, &hash, .{});
    const hex = "0123456789abcdef";
    var buf: [32]u8 = undefined;
    for (hash, 0..) |byte, i| {
        buf[i * 2] = hex[byte >> 4];
        buf[i * 2 + 1] = hex[byte & 0x0f];
    }
    return .{ .string = try ctx.createString(&buf) };
}

fn native_sha1(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    var hash: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(s, &hash, .{});
    const hex = "0123456789abcdef";
    var buf: [40]u8 = undefined;
    for (hash, 0..) |byte, i| {
        buf[i * 2] = hex[byte >> 4];
        buf[i * 2 + 1] = hex[byte & 0x0f];
    }
    return .{ .string = try ctx.createString(&buf) };
}

fn native_mb_substr(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const char_count = mbCharCount(s);
    var start = Value.toInt(args[1]);
    if (start < 0) start = @max(0, char_count + start);
    if (start >= char_count) return .{ .string = "" };

    var length = if (args.len >= 3 and args[2] != .null) Value.toInt(args[2]) else char_count - start;
    if (length < 0) length = @max(0, char_count - start + length);
    if (length <= 0) return .{ .string = "" };

    var byte_start: usize = 0;
    var ci: i64 = 0;
    var bi: usize = 0;
    while (bi < s.len and ci < start) {
        bi += mbCharLen(s[bi]);
        ci += 1;
    }
    byte_start = bi;

    var chars_remaining = length;
    while (bi < s.len and chars_remaining > 0) {
        bi += mbCharLen(s[bi]);
        chars_remaining -= 1;
    }

    return .{ .string = try ctx.createString(s[byte_start..bi]) };
}

fn mbCharCount(s: []const u8) i64 {
    var count: i64 = 0;
    var i: usize = 0;
    while (i < s.len) {
        i += mbCharLen(s[i]);
        count += 1;
    }
    return count;
}

fn mbCharLen(byte: u8) usize {
    if (byte < 0x80) return 1;
    if (byte < 0xE0) return 2;
    if (byte < 0xF0) return 3;
    return 4;
}

fn native_strrev(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    if (s.len == 0) return .{ .string = "" };
    const buf = try ctx.allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| buf[s.len - 1 - i] = c;
    try ctx.strings.append(ctx.allocator, buf);
    return .{ .string = buf };
}

fn toLowerBuf(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    const buf = try allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| buf[i] = std.ascii.toLower(c);
    return buf;
}

fn native_stripos(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .bool = false };
    const haystack = if (args[0] == .string) args[0].string else return Value{ .bool = false };
    const needle = if (args[1] == .string) args[1].string else return Value{ .bool = false };
    const offset: usize = if (args.len >= 3) @intCast(@max(0, Value.toInt(args[2]))) else 0;
    if (offset >= haystack.len or needle.len == 0) return .{ .bool = false };
    const h_lower = try toLowerBuf(ctx.allocator, haystack[offset..]);
    defer ctx.allocator.free(h_lower);
    const n_lower = try toLowerBuf(ctx.allocator, needle);
    defer ctx.allocator.free(n_lower);
    if (std.mem.indexOf(u8, h_lower, n_lower)) |pos| {
        return .{ .int = @intCast(pos + offset) };
    }
    return .{ .bool = false };
}

fn native_strrpos(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .bool = false };
    const haystack = if (args[0] == .string) args[0].string else return Value{ .bool = false };
    const needle = if (args[1] == .string) args[1].string else return Value{ .bool = false };
    if (needle.len == 0 or haystack.len == 0) return .{ .bool = false };
    if (std.mem.lastIndexOf(u8, haystack, needle)) |pos| {
        return .{ .int = @intCast(pos) };
    }
    return .{ .bool = false };
}

fn native_strripos(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .bool = false };
    const haystack = if (args[0] == .string) args[0].string else return Value{ .bool = false };
    const needle = if (args[1] == .string) args[1].string else return Value{ .bool = false };
    if (needle.len == 0 or haystack.len == 0) return .{ .bool = false };
    const h_lower = try toLowerBuf(ctx.allocator, haystack);
    defer ctx.allocator.free(h_lower);
    const n_lower = try toLowerBuf(ctx.allocator, needle);
    defer ctx.allocator.free(n_lower);
    if (std.mem.lastIndexOf(u8, h_lower, n_lower)) |pos| {
        return .{ .int = @intCast(pos) };
    }
    return .{ .bool = false };
}

fn native_str_ireplace(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3) return if (args.len >= 3) args[2] else Value{ .string = "" };
    const search = if (args[0] == .string) args[0].string else return args[2];
    const replace = if (args[1] == .string) args[1].string else return args[2];
    const subject = if (args[2] == .string) args[2].string else return args[2];
    if (search.len == 0) return args[2];

    const s_lower = try toLowerBuf(ctx.allocator, subject);
    defer ctx.allocator.free(s_lower);
    const n_lower = try toLowerBuf(ctx.allocator, search);
    defer ctx.allocator.free(n_lower);

    var buf = std.ArrayListUnmanaged(u8){};
    var i: usize = 0;
    while (i < subject.len) {
        if (i + search.len <= subject.len and std.mem.eql(u8, s_lower[i .. i + search.len], n_lower)) {
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

fn native_ucwords(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    if (s.len == 0) return .{ .string = "" };
    const delimiters = if (args.len >= 2 and args[1] == .string) args[1].string else " \t\r\n\x0b";
    const buf = try ctx.allocator.alloc(u8, s.len);
    var capitalize_next = true;
    for (s, 0..) |c, i| {
        if (isDelimiter(c, delimiters)) {
            buf[i] = c;
            capitalize_next = true;
        } else if (capitalize_next) {
            buf[i] = std.ascii.toUpper(c);
            capitalize_next = false;
        } else {
            buf[i] = c;
        }
    }
    try ctx.strings.append(ctx.allocator, buf);
    return .{ .string = buf };
}

fn isDelimiter(c: u8, delimiters: []const u8) bool {
    for (delimiters) |d| {
        if (c == d) return true;
    }
    return false;
}

fn native_crc32(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
    const s = if (args[0] == .string) args[0].string else return Value{ .int = 0 };
    const result = std.hash.crc.Crc32IsoHdlc.hash(s);
    const signed: i32 = @bitCast(result);
    return .{ .int = signed };
}

fn native_str_rot13(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    if (s.len == 0) return .{ .string = "" };
    const buf = try ctx.allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| {
        buf[i] = if (c >= 'a' and c <= 'z')
            (c - 'a' + 13) % 26 + 'a'
        else if (c >= 'A' and c <= 'Z')
            (c - 'A' + 13) % 26 + 'A'
        else
            c;
    }
    try ctx.strings.append(ctx.allocator, buf);
    return .{ .string = buf };
}

fn native_mb_trim(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const chars = if (args.len >= 2 and args[1] == .string) args[1].string else " \t\n\r\x0b\x00";
    const trimmed = std.mem.trim(u8, s, chars);
    return .{ .string = try ctx.createString(trimmed) };
}

fn native_mb_ltrim(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const chars = if (args.len >= 2 and args[1] == .string) args[1].string else " \t\n\r\x0b\x00";
    const trimmed = std.mem.trimLeft(u8, s, chars);
    return .{ .string = try ctx.createString(trimmed) };
}

fn native_mb_rtrim(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const chars = if (args.len >= 2 and args[1] == .string) args[1].string else " \t\n\r\x0b\x00";
    const trimmed = std.mem.trimRight(u8, s, chars);
    return .{ .string = try ctx.createString(trimmed) };
}

fn native_quotemeta(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    if (s.len == 0) return .{ .string = "" };
    var buf = std.ArrayListUnmanaged(u8){};
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
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn native_mb_ucfirst(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    if (s.len == 0) return .{ .string = "" };
    const buf = try ctx.allocator.alloc(u8, s.len);
    @memcpy(buf, s);
    buf[0] = std.ascii.toUpper(s[0]);
    try ctx.strings.append(ctx.allocator, buf);
    return .{ .string = buf };
}

fn native_mb_lcfirst(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    if (s.len == 0) return .{ .string = "" };
    const buf = try ctx.allocator.alloc(u8, s.len);
    @memcpy(buf, s);
    buf[0] = std.ascii.toLower(s[0]);
    try ctx.strings.append(ctx.allocator, buf);
    return .{ .string = buf };
}

fn native_strip_tags(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .string = "" };
    const s = args[0].string;

    var allowed_tags_buf: [64][64]u8 = undefined;
    var allowed_tags_lens: [64]usize = undefined;
    var n_allowed: usize = 0;
    if (args.len >= 2 and args[1] == .string) {
        const allow = args[1].string;
        var ai: usize = 0;
        while (ai < allow.len and n_allowed < 64) {
            if (allow[ai] == '<') {
                ai += 1;
                var tlen: usize = 0;
                while (ai < allow.len and allow[ai] != '>') : (ai += 1) {
                    if (tlen < 64) {
                        allowed_tags_buf[n_allowed][tlen] = toLowerAscii(allow[ai]);
                        tlen += 1;
                    }
                }
                if (ai < allow.len) ai += 1;
                allowed_tags_lens[n_allowed] = tlen;
                n_allowed += 1;
            } else {
                ai += 1;
            }
        }
    }

    var buf = std.ArrayListUnmanaged(u8){};
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '<') {
            const tag_start = i;
            i += 1;
            const is_closing = i < s.len and s[i] == '/';
            if (is_closing) i += 1;
            var name_buf: [64]u8 = undefined;
            var name_len: usize = 0;
            while (i < s.len and s[i] != '>' and s[i] != ' ' and s[i] != '/') : (i += 1) {
                if (name_len < 64) {
                    name_buf[name_len] = toLowerAscii(s[i]);
                    name_len += 1;
                }
            }
            while (i < s.len and s[i] != '>') : (i += 1) {}
            if (i < s.len) i += 1;

            var keep = false;
            for (0..n_allowed) |ai| {
                const alen = allowed_tags_lens[ai];
                if (alen == name_len and std.mem.eql(u8, allowed_tags_buf[ai][0..alen], name_buf[0..name_len])) {
                    keep = true;
                    break;
                }
            }
            if (keep) {
                try buf.appendSlice(ctx.allocator, s[tag_start..i]);
            }
        } else {
            try buf.append(ctx.allocator, s[i]);
            i += 1;
        }
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn toLowerAscii(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}

fn native_http_build_query(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .array) return .{ .string = "" };
    const arr = args[0].array;
    var buf = std.ArrayListUnmanaged(u8){};
    var first = true;
    for (arr.entries.items) |entry| {
        var key_buf: [20]u8 = undefined;
        const key_str = switch (entry.key) {
            .string => |s| s,
            .int => |n| std.fmt.bufPrint(&key_buf, "{d}", .{n}) catch "",
        };
        try buildQueryPairs(&buf, ctx.allocator, key_str, entry.value, &first);
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn buildQueryPairs(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, prefix: []const u8, value: Value, first: *bool) !void {
    if (value == .array) {
        for (value.array.entries.items) |entry| {
            var key_buf: [20]u8 = undefined;
            const sub_key = switch (entry.key) {
                .string => |s| s,
                .int => |n| std.fmt.bufPrint(&key_buf, "{d}", .{n}) catch "",
            };
            // build "prefix[subkey]" into a temp buffer
            var nested_key = std.ArrayListUnmanaged(u8){};
            defer nested_key.deinit(a);
            try nested_key.appendSlice(a, prefix);
            try nested_key.appendSlice(a, "[");
            try nested_key.appendSlice(a, sub_key);
            try nested_key.appendSlice(a, "]");
            try buildQueryPairs(buf, a, nested_key.items, entry.value, first);
        }
    } else {
        if (!first.*) try buf.append(a, '&');
        first.* = false;
        try appendUrlEncoded(buf, a, prefix);
        try buf.append(a, '=');
        if (value == .string) {
            try appendUrlEncoded(buf, a, value.string);
        } else {
            var tmp = std.ArrayListUnmanaged(u8){};
            try value.format(&tmp, a);
            const s = try tmp.toOwnedSlice(a);
            defer a.free(s);
            try appendUrlEncoded(buf, a, s);
        }
    }
}

fn appendUrlEncoded(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, s: []const u8) !void {
    for (s) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
            try buf.append(a, c);
        } else if (c == ' ') {
            try buf.append(a, '+');
        } else {
            try buf.append(a, '%');
            const hex = "0123456789ABCDEF";
            try buf.append(a, hex[c >> 4]);
            try buf.append(a, hex[c & 0xf]);
        }
    }
}

fn native_qp_encode(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .string = "" };
    const s = args[0].string;
    var buf = std.ArrayListUnmanaged(u8){};
    const hex = "0123456789ABCDEF";
    var line_len: usize = 0;
    var i: usize = 0;
    while (i < s.len) {
        if (i + 1 < s.len and s[i] == '\r' and s[i + 1] == '\n') {
            try buf.appendSlice(ctx.allocator, "\r\n");
            line_len = 0;
            i += 2;
            continue;
        }
        if (s[i] == '\n') {
            try buf.appendSlice(ctx.allocator, "\r\n");
            line_len = 0;
            i += 1;
            continue;
        }
        const c = s[i];
        const need: usize = if ((c >= 33 and c <= 126 and c != '=') or c == ' ' or c == '\t') 1 else 3;
        if (line_len + need > 75) {
            try buf.appendSlice(ctx.allocator, "=\r\n");
            line_len = 0;
        }
        if (need == 1) {
            try buf.append(ctx.allocator, c);
        } else {
            try buf.append(ctx.allocator, '=');
            try buf.append(ctx.allocator, hex[c >> 4]);
            try buf.append(ctx.allocator, hex[c & 0xf]);
        }
        line_len += need;
        i += 1;
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn native_qp_decode(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .string = "" };
    const s = args[0].string;
    var buf = std.ArrayListUnmanaged(u8){};
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
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn native_parse_url(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return Value{ .bool = false };
    const url = args[0].string;

    const component: ?i64 = if (args.len >= 2 and args[1] == .int) args[1].int else null;

    var scheme_end: usize = 0;
    var scheme: ?[]const u8 = null;
    var authority_start: usize = 0;
    var has_authority = false;

    if (std.mem.indexOf(u8, url, "://")) |pos| {
        scheme = url[0..pos];
        scheme_end = pos + 3;
        authority_start = scheme_end;
        has_authority = true;
    } else if (url.len >= 2 and url[0] == '/' and url[1] == '/') {
        authority_start = 2;
        scheme_end = 2;
        has_authority = true;
    } else if (std.mem.indexOf(u8, url, ":")) |colon| {
        // scheme:path (no //) - e.g. mailto:user@example.com
        if (colon > 0) {
            var valid_scheme = true;
            for (url[0..colon]) |c| {
                if (!std.ascii.isAlphabetic(c) and c != '+' and c != '-' and c != '.') {
                    valid_scheme = false;
                    break;
                }
            }
            if (valid_scheme) {
                scheme = url[0..colon];
                scheme_end = colon + 1;
                authority_start = scheme_end;
            }
        }
    }

    var rest = url[authority_start..];

    // split off fragment
    var fragment: ?[]const u8 = null;
    if (std.mem.indexOf(u8, rest, "#")) |pos| {
        fragment = rest[pos + 1 ..];
        rest = rest[0..pos];
    }

    // split off query
    var query: ?[]const u8 = null;
    if (std.mem.indexOf(u8, rest, "?")) |pos| {
        query = rest[pos + 1 ..];
        rest = rest[0..pos];
    }

    // split authority from path
    var host: ?[]const u8 = null;
    var port: ?i64 = null;
    var user: ?[]const u8 = null;
    var pass: ?[]const u8 = null;
    var path: ?[]const u8 = null;

    if (has_authority) {
        var authority = rest;
        if (std.mem.indexOf(u8, rest, "/")) |pos| {
            authority = rest[0..pos];
            path = rest[pos..];
        }

        if (std.mem.indexOf(u8, authority, "@")) |pos| {
            const userinfo = authority[0..pos];
            authority = authority[pos + 1 ..];
            if (std.mem.indexOf(u8, userinfo, ":")) |cp| {
                user = userinfo[0..cp];
                pass = userinfo[cp + 1 ..];
            } else {
                user = userinfo;
            }
        }

        if (authority.len > 0 and authority[0] == '[') {
            if (std.mem.indexOf(u8, authority, "]")) |bracket| {
                host = authority[0 .. bracket + 1];
                if (bracket + 1 < authority.len and authority[bracket + 1] == ':') {
                    port = std.fmt.parseInt(i64, authority[bracket + 2 ..], 10) catch null;
                }
            } else {
                host = authority;
            }
        } else if (std.mem.lastIndexOf(u8, authority, ":")) |pos| {
            host = authority[0..pos];
            port = std.fmt.parseInt(i64, authority[pos + 1 ..], 10) catch null;
        } else if (authority.len > 0) {
            host = authority;
        }
    } else {
        // for non-authority URLs, set path if non-empty OR if the entire URL is empty
        if (rest.len > 0 or url.len == 0) path = rest;
    }

    if (component) |c| {
        return switch (c) {
            0 => if (scheme) |s| Value{ .string = try ctx.createString(s) } else .null,
            1 => if (host) |h| Value{ .string = try ctx.createString(h) } else .null,
            2 => if (port) |p| Value{ .int = p } else .null,
            3 => if (user) |u| Value{ .string = try ctx.createString(u) } else .null,
            4 => if (pass) |p| Value{ .string = try ctx.createString(p) } else .null,
            5 => if (path) |p| Value{ .string = try ctx.createString(p) } else .null,
            6 => if (query) |q| Value{ .string = try ctx.createString(q) } else .null,
            7 => if (fragment) |f| Value{ .string = try ctx.createString(f) } else .null,
            else => Value{ .bool = false },
        };
    }

    var arr = try ctx.createArray();
    if (scheme) |s| try arr.set(ctx.allocator, .{ .string = "scheme" }, .{ .string = try ctx.createString(s) });
    if (host) |h| try arr.set(ctx.allocator, .{ .string = "host" }, .{ .string = try ctx.createString(h) });
    if (port) |p| try arr.set(ctx.allocator, .{ .string = "port" }, .{ .int = p });
    if (user) |u| try arr.set(ctx.allocator, .{ .string = "user" }, .{ .string = try ctx.createString(u) });
    if (pass) |p| try arr.set(ctx.allocator, .{ .string = "pass" }, .{ .string = try ctx.createString(p) });
    if (path) |p| try arr.set(ctx.allocator, .{ .string = "path" }, .{ .string = try ctx.createString(p) });
    if (query) |q| try arr.set(ctx.allocator, .{ .string = "query" }, .{ .string = try ctx.createString(q) });
    if (fragment) |f| try arr.set(ctx.allocator, .{ .string = "fragment" }, .{ .string = try ctx.createString(f) });
    return .{ .array = arr };
}

fn urlDecodeSlice(ctx: *NativeContext, s: []const u8) ![]const u8 {
    var buf = std.ArrayListUnmanaged(u8){};
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
    try ctx.strings.append(ctx.allocator, result);
    return result;
}

fn native_parse_str(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .null;
    const s = args[0].string;

    var arr = try ctx.createArray();
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
        const decoded_val = try urlDecodeSlice(ctx, val);
        try arr.set(ctx.allocator, .{ .string = decoded_key }, .{ .string = decoded_val });
    }
    if (args.len >= 2) {
        ctx.setCallerVar(1, args.len, .{ .array = arr });
    }
    return .null;
}

fn native_strstr(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return Value{ .bool = false };
    const haystack = if (args[0] == .string) args[0].string else return Value{ .bool = false };
    const needle = if (args[1] == .string) args[1].string else return Value{ .bool = false };
    if (needle.len == 0) return Value{ .bool = false };

    const before_needle: bool = args.len >= 3 and args[2] == .bool and args[2].bool;

    if (std.mem.indexOf(u8, haystack, needle)) |pos| {
        if (before_needle) {
            return .{ .string = try ctx.createString(haystack[0..pos]) };
        }
        return .{ .string = try ctx.createString(haystack[pos..]) };
    }
    return Value{ .bool = false };
}

fn native_strtr(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string) return .null;
    const str = args[0].string;

    if (args.len >= 3 and args[1] == .string and args[2] == .string) {
        const from = args[1].string;
        const to = args[2].string;
        const len = @min(from.len, to.len);
        const buf = try ctx.allocator.alloc(u8, str.len);
        try ctx.strings.append(ctx.allocator, buf);
        for (str, 0..) |c, i| {
            var replaced = false;
            for (0..len) |j| {
                if (c == from[j]) {
                    buf[i] = to[j];
                    replaced = true;
                    break;
                }
            }
            if (!replaced) buf[i] = c;
        }
        return .{ .string = buf };
    }

    if (args[1] == .array) {
        const replacements = args[1].array;
        var result = try ctx.allocator.alloc(u8, str.len * 4);
        try ctx.strings.append(ctx.allocator, result);
        var out_len: usize = 0;
        var i: usize = 0;
        while (i < str.len) {
            var matched = false;
            for (replacements.entries.items) |entry| {
                if (entry.key != .string) continue;
                const search = entry.key.string;
                if (search.len == 0) continue;
                if (i + search.len <= str.len and std.mem.eql(u8, str[i .. i + search.len], search)) {
                    const repl = if (entry.value == .string) entry.value.string else "";
                    if (out_len + repl.len > result.len) {
                        result = try ctx.allocator.realloc(result, result.len * 2 + repl.len);
                    }
                    @memcpy(result[out_len .. out_len + repl.len], repl);
                    out_len += repl.len;
                    i += search.len;
                    matched = true;
                    break;
                }
            }
            if (!matched) {
                if (out_len >= result.len) {
                    result = try ctx.allocator.realloc(result, result.len * 2);
                }
                result[out_len] = str[i];
                out_len += 1;
                i += 1;
            }
        }
        return .{ .string = result[0..out_len] };
    }

    return .null;
}

fn native_vsprintf(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .string = "" };
    const fmt_str = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    if (args[1] != .array) return .{ .string = "" };

    // convert array values to a slice for sprintfImpl
    const arr = args[1].array;
    var vals = try ctx.allocator.alloc(Value, arr.entries.items.len);
    defer ctx.allocator.free(vals);
    for (arr.entries.items, 0..) |entry, i| {
        vals[i] = entry.value;
    }
    const result = try sprintfImpl(ctx, fmt_str, vals);
    return .{ .string = result };
}

fn native_levenshtein(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .int = -1 };
    const s1 = args[0].string;
    const s2 = args[1].string;

    if (s1.len > 255 or s2.len > 255) return .{ .int = -1 };
    if (s1.len == 0) return .{ .int = @intCast(s2.len) };
    if (s2.len == 0) return .{ .int = @intCast(s1.len) };

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
    return .{ .int = prev[s2.len] };
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

fn native_similar_text(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .int = 0 };
    const s1 = args[0].string;
    const s2 = args[1].string;

    var matching: i64 = 0;
    similarTextImpl(s1, s2, &matching);

    if (args.len >= 3) {
        const total: f64 = @floatFromInt(s1.len + s2.len);
        const pct: f64 = if (total > 0) @as(f64, @floatFromInt(matching * 2)) * 100.0 / total else 0.0;
        ctx.setCallerVar(2, args.len, .{ .float = pct });
    }

    return .{ .int = matching };
}

fn native_soundex(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .string = "" };
    const input = args[0].string;
    if (input.len == 0) return .{ .string = "" };

    const correct_table = [26]u8{
        '0', '1', '2', '3', '0', '1', '2', '0', '0', '2', '2', '4', '5',
        '5', '0', '1', '2', '6', '2', '3', '0', '1', '0', '2', '0', '2',
    };
    var first: u8 = 0;
    var start: usize = 0;
    for (input, 0..) |c, i| {
        const upper = std.ascii.toUpper(c);
        if (upper >= 'A' and upper <= 'Z') {
            first = upper;
            start = i + 1;
            break;
        }
    }
    if (first == 0) return .{ .string = "" };

    var result_buf: [4]u8 = .{ first, '0', '0', '0' };
    var pos: usize = 1;
    var last_code = correct_table[first - 'A'];

    for (input[start..]) |c| {
        if (pos >= 4) break;
        const upper = std.ascii.toUpper(c);
        if (upper < 'A' or upper > 'Z') continue;
        const code = correct_table[upper - 'A'];
        if (code != '0' and code != last_code) {
            result_buf[pos] = code;
            pos += 1;
        }
        last_code = code;
    }

    const result = try ctx.allocator.alloc(u8, 4);
    @memcpy(result, &result_buf);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn native_metaphone(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .string = "" };
    const input = args[0].string;
    const max_phonemes: usize = if (args.len >= 2) @intCast(@max(Value.toInt(args[1]), 0)) else 32;
    if (input.len == 0) return .{ .string = "" };

    var buf = std.ArrayListUnmanaged(u8){};
    var upper = try ctx.allocator.alloc(u8, input.len);
    defer ctx.allocator.free(upper);
    for (input, 0..) |c, i| upper[i] = std.ascii.toUpper(c);

    var i: usize = 0;

    // skip initial silent consonant pairs
    if (upper.len >= 2) {
        const pair = upper[0..2];
        if (std.mem.eql(u8, pair, "AE") or std.mem.eql(u8, pair, "GN") or
            std.mem.eql(u8, pair, "KN") or std.mem.eql(u8, pair, "PN") or
            std.mem.eql(u8, pair, "WR"))
        {
            i = 1;
        }
    }

    while (i < upper.len and buf.items.len < max_phonemes) {
        const c = upper[i];
        const prev: u8 = if (i > 0) upper[i - 1] else 0;
        const next: u8 = if (i + 1 < upper.len) upper[i + 1] else 0;

        if (!std.ascii.isAlphabetic(c)) {
            i += 1;
            continue;
        }

        // vowels only at start
        if (c == 'A' or c == 'E' or c == 'I' or c == 'O' or c == 'U') {
            if (i == 0) try buf.append(ctx.allocator, c);
            i += 1;
            continue;
        }

        // skip doubled letters (except C)
        if (c == prev and c != 'C') {
            i += 1;
            continue;
        }

        switch (c) {
            'B' => {
                if (prev != 'M') try buf.append(ctx.allocator, 'B');
                i += 1;
            },
            'C' => {
                if (next == 'I' or next == 'E' or next == 'Y') {
                    if (next == 'I' and i + 2 < upper.len and upper[i + 2] == 'A') {
                        try buf.append(ctx.allocator, 'X');
                        i += 3;
                    } else {
                        try buf.append(ctx.allocator, 'S');
                        i += 2;
                    }
                } else {
                    try buf.append(ctx.allocator, 'K');
                    i += 1;
                }
            },
            'D' => {
                if (next == 'G' and i + 2 < upper.len) {
                    const after = upper[i + 2];
                    if (after == 'I' or after == 'E' or after == 'Y') {
                        try buf.append(ctx.allocator, 'J');
                        i += 3;
                    } else {
                        try buf.append(ctx.allocator, 'T');
                        i += 1;
                    }
                } else {
                    try buf.append(ctx.allocator, 'T');
                    i += 1;
                }
            },
            'F' => {
                try buf.append(ctx.allocator, 'F');
                i += 1;
            },
            'G' => {
                if (next == 'H') {
                    const after_h: u8 = if (i + 2 < upper.len) upper[i + 2] else 0;
                    const after_is_vowel = after_h == 'A' or after_h == 'E' or after_h == 'I' or after_h == 'O' or after_h == 'U';
                    const prev_is_vowel = prev == 'A' or prev == 'E' or prev == 'I' or prev == 'O' or prev == 'U';
                    if (prev_is_vowel and !after_is_vowel) {
                        try buf.append(ctx.allocator, 'F');
                        i += 2;
                        continue;
                    } else if (i == 0) {
                        // GH at start -> hard G
                        try buf.append(ctx.allocator, 'K');
                        i += 2;
                        continue;
                    } else if (!after_is_vowel) {
                        i += 2;
                        continue;
                    }
                }
                if (i > 0 and (next == 'N' or (next == 0 and prev != 0))) {
                    if (next == 0 or (i + 2 >= upper.len and next == 'N')) {
                        i += 1;
                        continue;
                    }
                }
                if (prev == 'G') {
                    i += 1;
                    continue;
                }
                if (next == 'I' or next == 'E' or next == 'Y') {
                    try buf.append(ctx.allocator, 'J');
                } else {
                    try buf.append(ctx.allocator, 'K');
                }
                i += 1;
            },
            'H' => {
                if ((prev == 'A' or prev == 'E' or prev == 'I' or prev == 'O' or prev == 'U') or
                    (next == 'A' or next == 'E' or next == 'I' or next == 'O' or next == 'U'))
                {
                    if (next == 'A' or next == 'E' or next == 'I' or next == 'O' or next == 'U') {
                        if (!(prev == 'S' or prev == 'C' or prev == 'P' or prev == 'T' or prev == 'G')) {
                            try buf.append(ctx.allocator, 'H');
                        }
                    }
                }
                i += 1;
            },
            'J' => {
                try buf.append(ctx.allocator, 'J');
                i += 1;
            },
            'K' => {
                if (prev != 'C') try buf.append(ctx.allocator, 'K');
                i += 1;
            },
            'L' => {
                try buf.append(ctx.allocator, 'L');
                i += 1;
            },
            'M' => {
                try buf.append(ctx.allocator, 'M');
                i += 1;
            },
            'N' => {
                try buf.append(ctx.allocator, 'N');
                i += 1;
            },
            'P' => {
                if (next == 'H') {
                    try buf.append(ctx.allocator, 'F');
                    i += 2;
                } else {
                    try buf.append(ctx.allocator, 'P');
                    i += 1;
                }
            },
            'Q' => {
                try buf.append(ctx.allocator, 'K');
                i += 1;
            },
            'R' => {
                try buf.append(ctx.allocator, 'R');
                i += 1;
            },
            'S' => {
                if (next == 'H' or (next == 'I' and i + 2 < upper.len and (upper[i + 2] == 'O' or upper[i + 2] == 'A'))) {
                    try buf.append(ctx.allocator, 'X');
                    i += 2;
                } else {
                    try buf.append(ctx.allocator, 'S');
                    i += 1;
                }
            },
            'T' => {
                if (next == 'H') {
                    try buf.append(ctx.allocator, '0');
                    i += 2;
                } else if (next == 'I' and i + 2 < upper.len and (upper[i + 2] == 'O' or upper[i + 2] == 'A')) {
                    try buf.append(ctx.allocator, 'X');
                    i += 3;
                } else {
                    try buf.append(ctx.allocator, 'T');
                    i += 1;
                }
            },
            'V' => {
                try buf.append(ctx.allocator, 'F');
                i += 1;
            },
            'W', 'Y' => {
                if (next == 'A' or next == 'E' or next == 'I' or next == 'O' or next == 'U') {
                    try buf.append(ctx.allocator, c);
                }
                i += 1;
            },
            'X' => {
                try buf.append(ctx.allocator, 'K');
                try buf.append(ctx.allocator, 'S');
                i += 1;
            },
            'Z' => {
                try buf.append(ctx.allocator, 'S');
                i += 1;
            },
            else => i += 1,
        }
    }

    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn native_count_chars(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .null;
    const s = args[0].string;
    const mode: i64 = if (args.len >= 2) Value.toInt(args[1]) else 0;

    var freq: [256]i64 = [_]i64{0} ** 256;
    for (s) |c| freq[c] += 1;

    if (mode == 3) {
        var buf2 = std.ArrayListUnmanaged(u8){};
        for (0..256) |i| {
            if (freq[i] > 0) try buf2.append(ctx.allocator, @intCast(i));
        }
        const r = try buf2.toOwnedSlice(ctx.allocator);
        try ctx.strings.append(ctx.allocator, r);
        return .{ .string = r };
    }

    if (mode == 4) {
        var buf2 = std.ArrayListUnmanaged(u8){};
        for (0..256) |i| {
            if (freq[i] == 0) try buf2.append(ctx.allocator, @intCast(i));
        }
        const r = try buf2.toOwnedSlice(ctx.allocator);
        try ctx.strings.append(ctx.allocator, r);
        return .{ .string = r };
    }

    var arr = try ctx.createArray();
    for (0..256) |i| {
        const include = switch (mode) {
            0 => true,
            1 => freq[i] > 0,
            2 => freq[i] == 0,
            else => true,
        };
        if (include) {
            try arr.set(ctx.allocator, .{ .int = @intCast(i) }, .{ .int = freq[i] });
        }
    }
    return .{ .array = arr };
}

fn native_str_increment(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .string = "" };
    const s = args[0].string;
    if (s.len == 0) return .{ .string = "" };

    var buf3 = try ctx.allocator.alloc(u8, s.len + 1);
    @memcpy(buf3[1..], s);

    var carry = true;
    var j: usize = s.len;
    while (carry and j > 0) {
        j -= 1;
        const c = buf3[j + 1];
        if (c >= 'a' and c <= 'z') {
            if (c == 'z') {
                buf3[j + 1] = 'a';
            } else {
                buf3[j + 1] = c + 1;
                carry = false;
            }
        } else if (c >= 'A' and c <= 'Z') {
            if (c == 'Z') {
                buf3[j + 1] = 'A';
            } else {
                buf3[j + 1] = c + 1;
                carry = false;
            }
        } else if (c >= '0' and c <= '9') {
            if (c == '9') {
                buf3[j + 1] = '0';
            } else {
                buf3[j + 1] = c + 1;
                carry = false;
            }
        } else {
            buf3[j + 1] = c + 1;
            carry = false;
        }
    }

    if (carry) {
        const first = s[0];
        if (first >= 'a' and first <= 'z') {
            buf3[0] = 'a';
        } else if (first >= 'A' and first <= 'Z') {
            buf3[0] = 'A';
        } else {
            buf3[0] = '1';
        }
        try ctx.strings.append(ctx.allocator, buf3);
        return .{ .string = buf3 };
    }

    const r2 = buf3[1..];
    try ctx.strings.append(ctx.allocator, buf3);
    return .{ .string = r2 };
}

fn native_str_decrement(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .string = "" };
    const s = args[0].string;
    if (s.len == 0) return .{ .string = "" };

    if (s.len == 1) {
        if (s[0] == 'a' or s[0] == 'A' or s[0] == '0') return .{ .string = s };
    }

    var buf3 = try ctx.allocator.alloc(u8, s.len);
    @memcpy(buf3, s);

    var borrow = true;
    var j: usize = s.len;
    while (borrow and j > 0) {
        j -= 1;
        const c = buf3[j];
        if (c >= 'a' and c <= 'z') {
            if (c == 'a') {
                buf3[j] = 'z';
            } else {
                buf3[j] = c - 1;
                borrow = false;
            }
        } else if (c >= 'A' and c <= 'Z') {
            if (c == 'A') {
                buf3[j] = 'Z';
            } else {
                buf3[j] = c - 1;
                borrow = false;
            }
        } else if (c >= '0' and c <= '9') {
            if (c == '0') {
                buf3[j] = '9';
            } else {
                buf3[j] = c - 1;
                borrow = false;
            }
        } else {
            buf3[j] = c - 1;
            borrow = false;
        }
    }

    var start: usize = 0;
    if (borrow and buf3.len > 1) start = 1;

    const r2 = buf3[start..];
    try ctx.strings.append(ctx.allocator, buf3);
    return .{ .string = r2 };
}

fn native_substr_compare(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const haystack = args[0].string;
    const needle = args[1].string;
    var offset: i64 = Value.toInt(args[2]);
    const length: ?usize = if (args.len >= 4 and args[3] != .null)
        @intCast(@max(Value.toInt(args[3]), 0))
    else
        null;
    const case_insensitive = args.len >= 5 and args[4].isTruthy();

    if (offset < 0) {
        offset = @as(i64, @intCast(haystack.len)) + offset;
        if (offset < 0) offset = 0;
    }
    const off: usize = @intCast(offset);
    if (off > haystack.len) return .{ .bool = false };

    const hay_sub = haystack[off..];
    const hay_len = if (length) |l| @min(l, hay_sub.len) else hay_sub.len;
    const ndl_len = if (length) |l| @min(l, needle.len) else needle.len;
    const cmp_len = @min(hay_len, ndl_len);

    var i: usize = 0;
    while (i < cmp_len) : (i += 1) {
        var a = hay_sub[i];
        var b = needle[i];
        if (case_insensitive) {
            a = std.ascii.toLower(a);
            b = std.ascii.toLower(b);
        }
        if (a < b) return .{ .int = -1 };
        if (a > b) return .{ .int = 1 };
    }

    if (hay_len < ndl_len) return .{ .int = -1 };
    if (hay_len > ndl_len) return .{ .int = 1 };
    return .{ .int = 0 };
}

fn native_strcspn(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .int = 0 };
    const s = args[0].string;
    const chars = args[1].string;
    const start: usize = if (args.len >= 3) @intCast(@max(0, Value.toInt(args[2]))) else 0;
    const length: usize = if (args.len >= 4) @intCast(@max(0, Value.toInt(args[3]))) else s.len;
    const end = @min(start + length, s.len);

    for (start..end) |i| {
        for (chars) |c| {
            if (s[i] == c) return .{ .int = @intCast(i - start) };
        }
    }
    return .{ .int = @intCast(end - start) };
}

fn native_strspn(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .int = 0 };
    const s = args[0].string;
    const chars = args[1].string;
    const start: usize = if (args.len >= 3) @intCast(@max(0, Value.toInt(args[2]))) else 0;
    const length: usize = if (args.len >= 4) @intCast(@max(0, Value.toInt(args[3]))) else s.len;
    const end = @min(start + length, s.len);

    for (start..end) |i| {
        var found = false;
        for (chars) |c| {
            if (s[i] == c) { found = true; break; }
        }
        if (!found) return .{ .int = @intCast(i - start) };
    }
    return .{ .int = @intCast(end - start) };
}

fn native_strpbrk(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const s = args[0].string;
    const chars = args[1].string;
    for (s, 0..) |ch, i| {
        for (chars) |c| {
            if (ch == c) {
                const result = try ctx.allocator.dupe(u8, s[i..]);
                try ctx.vm.strings.append(ctx.allocator, result);
                return .{ .string = result };
            }
        }
    }
    return .{ .bool = false };
}
