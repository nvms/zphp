const std = @import("std");

extern "c" fn snprintf(buf: [*c]u8, size: usize, fmt: [*c]const u8, ...) c_int;
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
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
    .{ "strcasecmp", native_strcasecmp },
    .{ "strnatcmp", native_strnatcmp },
    .{ "strnatcasecmp", native_strnatcasecmp },
    .{ "strncmp", native_strncmp },
    .{ "strncasecmp", native_strncasecmp },
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
    .{ "fprintf", native_fprintf },
    .{ "addslashes", native_addslashes },
    .{ "stripslashes", native_stripslashes },
    .{ "htmlspecialchars", native_htmlspecialchars },
    .{ "htmlspecialchars_decode", native_htmlspecialchars_decode },
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
    .{ "iconv", native_iconv },
    .{ "iconv_strlen", native_mb_strlen },
    .{ "iconv_strpos", native_mb_strpos },
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
    .{ "mb_strstr", native_mb_strstr },
    .{ "mb_stristr", native_mb_stristr },
    .{ "mb_strcut", native_mb_strcut },
    .{ "mb_str_pad", native_mb_str_pad },
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
    .{ "html_entity_decode", native_html_entity_decode },
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
    .{ "htmlentities", native_htmlentities },
    .{ "get_html_translation_table", native_get_html_translation_table },
    .{ "quoted_printable_encode", native_qp_encode },
    .{ "quoted_printable_decode", native_qp_decode },
    .{ "parse_url", native_parse_url },
    .{ "parse_str", native_parse_str },
    .{ "strstr", native_strstr },
    .{ "strrchr", native_strrchr },
    .{ "addcslashes", native_addcslashes },
    .{ "stripcslashes", native_stripcslashes },
    .{ "strchr", native_strstr },
    .{ "strtr", native_strtr },
    .{ "vsprintf", native_vsprintf },
    .{ "vprintf", native_vprintf },
    .{ "sscanf", native_sscanf },
    .{ "fscanf", native_fscanf },
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

fn substr(_: *NativeContext, args: []const Value) RuntimeError!Value {
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
        return .{ .string = s[ustart..end] };
    }
    return .{ .string = s[ustart..] };
}

fn strpos(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .bool = false };
    const haystack = if (args[0] == .string) args[0].string else return Value{ .bool = false };
    const needle = if (args[1] == .string) args[1].string else return Value{ .bool = false };
    const hlen: i64 = @intCast(haystack.len);
    const raw_off: i64 = if (args.len >= 3) Value.toInt(args[2]) else 0;
    const off_i: i64 = if (raw_off < 0) @max(0, hlen + raw_off) else raw_off;
    if (off_i > hlen) return .{ .bool = false };
    const offset: usize = @intCast(off_i);
    if (std.mem.indexOf(u8, haystack[offset..], needle)) |pos| {
        return .{ .int = @intCast(pos + offset) };
    }
    return .{ .bool = false };
}

const ReplaceResult = struct { str: []const u8, count: i64 };

fn replaceOne(ctx: *NativeContext, subject: []const u8, search: []const u8, replace: []const u8) !ReplaceResult {
    if (search.len == 0) return .{ .str = subject, .count = 0 };
    var buf = std.ArrayListUnmanaged(u8){};
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
    try ctx.strings.append(ctx.allocator, s);
    return .{ .str = s, .count = cnt };
}

fn str_replace(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3) return if (args.len >= 3) args[2] else Value{ .string = "" };

    var total_count: i64 = 0;

    // subject is an array: apply replacement element-wise, return an array
    if (args[2] == .array) {
        const subject_arr = args[2].array;
        const out = try ctx.createArray();
        for (subject_arr.entries.items) |se| {
            const elem_str: []const u8 = if (se.value == .string) se.value.string else "";
            const replaced = try strReplaceOnSingle(ctx, args[0], args[1], elem_str, &total_count);
            try out.set(ctx.allocator, se.key, .{ .string = replaced });
        }
        if (args.len >= 4) ctx.setCallerVar(3, args.len, .{ .int = total_count });
        return .{ .array = out };
    }

    const subject = if (args[2] == .string) args[2].string else return args[2];
    const replaced = try strReplaceOnSingle(ctx, args[0], args[1], subject, &total_count);
    if (args.len >= 4) ctx.setCallerVar(3, args.len, .{ .int = total_count });
    return .{ .string = replaced };
}

fn strReplaceOnSingle(ctx: *NativeContext, search: Value, replace: Value, subject: []const u8, total_count: *i64) ![]const u8 {
    if (search == .array) {
        var result = subject;
        for (search.array.entries.items, 0..) |entry, idx| {
            const needle = if (entry.value == .string) entry.value.string else continue;
            const replacement = if (replace == .array) blk: {
                break :blk if (idx < replace.array.entries.items.len)
                    (if (replace.array.entries.items[idx].value == .string) replace.array.entries.items[idx].value.string else "")
                else
                    "";
            } else if (replace == .string) replace.string else "";
            const r = try replaceOne(ctx, result, needle, replacement);
            result = r.str;
            total_count.* += r.count;
        }
        return result;
    }
    const s = if (search == .string) search.string else return subject;
    const rep = if (replace == .string) replace.string else "";
    const r = try replaceOne(ctx, subject, s, rep);
    total_count.* += r.count;
    return r.str;
}

fn explode(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .null;
    const delim = if (args[0] == .string) args[0].string else return Value.null;
    const s = if (args[1] == .string) args[1].string else return Value.null;
    if (delim.len == 0) return .{ .bool = false };

    var limit: i64 = if (args.len >= 3) args[2].toInt() else std.math.maxInt(i64);
    // PHP: limit 0 is treated as 1
    if (limit == 0) limit = 1;

    var arr = try ctx.createArray();
    var i: usize = 0;
    var count: i64 = 0;
    while (i <= s.len) {
        if (limit > 0 and count >= limit - 1) {
            try arr.append(ctx.allocator, .{ .string = try ctx.createString(s[i..]) });
            break;
        }
        if (std.mem.indexOf(u8, s[i..], delim)) |pos| {
            try arr.append(ctx.allocator, .{ .string = try ctx.createString(s[i .. i + pos]) });
            i += pos + delim.len;
            count += 1;
        } else {
            try arr.append(ctx.allocator, .{ .string = try ctx.createString(s[i..]) });
            break;
        }
    }

    if (limit < 0) {
        const drop: usize = @intCast(@min(@as(i64, @intCast(arr.entries.items.len)), -limit));
        arr.entries.items.len = arr.entries.items.len -| drop;
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

// build the trim char set, expanding `a..b` ranges
fn buildTrimSet(chars: []const u8) [256]bool {
    var set: [256]bool = .{false} ** 256;
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

fn trim(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const chars = if (args.len >= 2 and args[1] == .string) args[1].string else default_trim_chars;
    const set = buildTrimSet(chars);
    return .{ .string = try ctx.createString(trimWithSet(s, set, true, true)) };
}

fn ltrim(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const chars = if (args.len >= 2 and args[1] == .string) args[1].string else default_trim_chars;
    const set = buildTrimSet(chars);
    return .{ .string = try ctx.createString(trimWithSet(s, set, true, false)) };
}

fn rtrim(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const chars = if (args.len >= 2 and args[1] == .string) args[1].string else default_trim_chars;
    const set = buildTrimSet(chars);
    return .{ .string = try ctx.createString(trimWithSet(s, set, false, true)) };
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
    if (pad_str.len == 0) {
        try ctx.vm.setPendingException("ValueError", "str_pad(): Argument #3 ($pad_string) must not be empty");
        return error.RuntimeError;
    }
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

fn native_strcasecmp(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .int = 0 };
    const a = if (args[0] == .string) args[0].string else "";
    const b = if (args[1] == .string) args[1].string else "";
    const min_len = @min(a.len, b.len);
    for (0..min_len) |i| {
        const ca = std.ascii.toLower(a[i]);
        const cb = std.ascii.toLower(b[i]);
        if (ca != cb) return .{ .int = @as(i64, ca) - @as(i64, cb) };
    }
    if (a.len != b.len) return .{ .int = @as(i64, @intCast(a.len)) - @as(i64, @intCast(b.len)) };
    return .{ .int = 0 };
}

fn natCompare(a: []const u8, b: []const u8, fold_case: bool) i64 {
    var ai: usize = 0;
    var bi: usize = 0;
    while (ai < a.len and bi < b.len) {
        const ca = a[ai];
        const cb = b[bi];
        if (std.ascii.isDigit(ca) and std.ascii.isDigit(cb)) {
            // skip leading zeros
            var as = ai;
            while (as < a.len and a[as] == '0') as += 1;
            var ae = as;
            while (ae < a.len and std.ascii.isDigit(a[ae])) ae += 1;
            var bs = bi;
            while (bs < b.len and b[bs] == '0') bs += 1;
            var be = bs;
            while (be < b.len and std.ascii.isDigit(b[be])) be += 1;
            const al = ae - as;
            const bl = be - bs;
            if (al != bl) return @as(i64, @intCast(al)) - @as(i64, @intCast(bl));
            for (a[as..ae], b[bs..be]) |x, y| {
                if (x != y) return @as(i64, x) - @as(i64, y);
            }
            // skip past digits
            ai = ae;
            bi = be;
            continue;
        }
        const xa: u8 = if (fold_case) std.ascii.toLower(ca) else ca;
        const xb: u8 = if (fold_case) std.ascii.toLower(cb) else cb;
        if (xa != xb) return @as(i64, xa) - @as(i64, xb);
        ai += 1;
        bi += 1;
    }
    if (a.len != b.len) return @as(i64, @intCast(a.len)) - @as(i64, @intCast(b.len));
    return 0;
}

fn native_strnatcmp(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .int = 0 };
    const a = if (args[0] == .string) args[0].string else "";
    const b = if (args[1] == .string) args[1].string else "";
    return .{ .int = natCompare(a, b, false) };
}

fn native_strnatcasecmp(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .int = 0 };
    const a = if (args[0] == .string) args[0].string else "";
    const b = if (args[1] == .string) args[1].string else "";
    return .{ .int = natCompare(a, b, true) };
}

fn native_strncasecmp(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3) return .{ .int = 0 };
    const a = if (args[0] == .string) args[0].string else "";
    const b = if (args[1] == .string) args[1].string else "";
    const n: usize = @intCast(@max(0, Value.toInt(args[2])));
    const sa = a[0..@min(n, a.len)];
    const sb = b[0..@min(n, b.len)];
    const min_len = @min(sa.len, sb.len);
    for (0..min_len) |i| {
        const ca = std.ascii.toLower(sa[i]);
        const cb = std.ascii.toLower(sb[i]);
        if (ca != cb) return .{ .int = @as(i64, ca) - @as(i64, cb) };
    }
    if (sa.len != sb.len) return .{ .int = @as(i64, @intCast(sa.len)) - @as(i64, @intCast(sb.len)) };
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
        try arr.append(ctx.allocator, .{ .string = try ctx.createString(s[i..end]) });
        i = end;
    }
    return .{ .array = arr };
}

fn native_substr_count(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .int = 0 };
    const haystack = if (args[0] == .string) args[0].string else return Value{ .int = 0 };
    const needle = if (args[1] == .string) args[1].string else return Value{ .int = 0 };
    if (needle.len == 0) return .{ .int = 0 };
    const offset: usize = if (args.len >= 3) @intCast(@max(0, @min(Value.toInt(args[2]), @as(i64, @intCast(haystack.len))))) else 0;
    const end: usize = if (args.len >= 4) @intCast(@min(@as(i64, @intCast(haystack.len)), @max(0, Value.toInt(args[2]) + Value.toInt(args[3])))) else haystack.len;
    const search_region = haystack[offset..end];
    var count: i64 = 0;
    var i: usize = 0;
    while (i + needle.len <= search_region.len) {
        if (std.mem.eql(u8, search_region[i .. i + needle.len], needle)) {
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

    if (args[0] == .array) {
        const src_arr = args[0].array;
        var out = try ctx.createArray();
        for (src_arr.entries.items, 0..) |entry, i| {
            const elem_str: []const u8 = if (entry.value == .string) entry.value.string else "";
            const repl_str: []const u8 = blk: {
                if (args[1] == .array) {
                    if (i < args[1].array.entries.items.len) {
                        const v = args[1].array.entries.items[i].value;
                        if (v == .string) break :blk v.string;
                    }
                    break :blk "";
                }
                break :blk if (args[1] == .string) args[1].string else "";
            };
            const start_val: i64 = blk: {
                if (args[2] == .array) {
                    if (i < args[2].array.entries.items.len)
                        break :blk Value.toInt(args[2].array.entries.items[i].value);
                    break :blk 0;
                }
                break :blk Value.toInt(args[2]);
            };
            const len_val: ?i64 = if (args.len >= 4) blk: {
                if (args[3] == .array) {
                    if (i < args[3].array.entries.items.len)
                        break :blk Value.toInt(args[3].array.entries.items[i].value);
                    break :blk 0;
                }
                break :blk Value.toInt(args[3]);
            } else null;

            const replaced = try substrReplaceOne(ctx, elem_str, repl_str, start_val, len_val);
            try out.append(ctx.allocator, .{ .string = replaced });
        }
        return .{ .array = out };
    }

    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const replacement = if (args[1] == .string) args[1].string else "";
    const start_val = Value.toInt(args[2]);
    const len_val: ?i64 = if (args.len >= 4) Value.toInt(args[3]) else null;
    const result = try substrReplaceOne(ctx, s, replacement, start_val, len_val);
    return .{ .string = result };
}

fn substrReplaceOne(ctx: *NativeContext, s: []const u8, replacement: []const u8, start_in: i64, len_opt: ?i64) ![]const u8 {
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

    var buf = std.ArrayListUnmanaged(u8){};
    try buf.appendSlice(ctx.allocator, s[0..ustart]);
    try buf.appendSlice(ctx.allocator, replacement);
    if (end < s.len) try buf.appendSlice(ctx.allocator, s[end..]);
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return result;
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
    const use_xhtml = if (args.len >= 2) args[1].isTruthy() else true;
    const br = if (use_xhtml) "<br />" else "<br>";
    var buf = std.ArrayListUnmanaged(u8){};
    var i: usize = 0;
    while (i < s.len) {
        const c = s[i];
        if (c == '\r' or c == '\n') {
            try buf.appendSlice(ctx.allocator, br);
            try buf.append(ctx.allocator, c);
            i += 1;
            if (c == '\r' and i < s.len and s[i] == '\n') {
                try buf.append(ctx.allocator, '\n');
                i += 1;
            }
        } else {
            try buf.append(ctx.allocator, c);
            i += 1;
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
    const decimals_signed: i64 = if (args.len >= 2) Value.toInt(args[1]) else 0;
    const decimals: usize = if (decimals_signed > 0) @intCast(decimals_signed) else 0;
    const dec_point = if (args.len >= 3 and args[2] == .string) args[2].string else ".";
    const thousands_sep = if (args.len >= 4 and args[3] == .string) args[3].string else ",";

    // negative decimals: round to nearest 10^|n| (half-up away from zero)
    if (decimals_signed < 0) {
        const num = Value.toFloat(args[0]);
        const power = std.math.pow(f64, 10.0, @floatFromInt(-decimals_signed));
        var rounded = @round(num / power) * power;
        if (rounded == 0) rounded = 0; // normalize -0
        // recurse with decimals=0
        var combined: [4]Value = undefined;
        combined[0] = .{ .float = rounded };
        combined[1] = .{ .int = 0 };
        var n: usize = 2;
        if (args.len >= 3) { combined[2] = args[2]; n = 3; }
        if (args.len >= 4) { combined[3] = args[3]; n = 4; }
        return native_number_format(ctx, combined[0..n]);
    }

    var int_part_buf: [64]u8 = undefined;
    var frac_part_buf: [64]u8 = undefined;
    var formatted: RoundedFloat = undefined;

    // for int inputs, format the int directly to preserve full PHP_INT_MAX precision
    if (args[0] == .int) {
        const i = args[0].int;
        const is_neg = i < 0;
        var abs_u: u64 = undefined;
        if (i == std.math.minInt(i64)) {
            abs_u = @as(u64, std.math.maxInt(i64)) + 1;
        } else {
            abs_u = @intCast(if (i < 0) -i else i);
        }
        const ip_str = std.fmt.bufPrint(&int_part_buf, "{d}", .{abs_u}) catch return Value{ .string = "0" };
        var fp_len: usize = 0;
        while (fp_len < decimals and fp_len < frac_part_buf.len) : (fp_len += 1) frac_part_buf[fp_len] = '0';
        formatted = .{
            .is_negative = is_neg,
            .int_part = int_part_buf[0..ip_str.len],
            .frac_part = frac_part_buf[0..fp_len],
        };
    } else {
        const num = Value.toFloat(args[0]);
        formatted = try roundFloatToDecimals(num, decimals, &int_part_buf, &frac_part_buf);
    }

    var buf = std.ArrayListUnmanaged(u8){};
    if (formatted.is_negative) try buf.append(ctx.allocator, '-');

    const int_str = formatted.int_part;
    if (thousands_sep.len > 0 and int_str.len > 3) {
        const first_group = int_str.len % 3;
        if (first_group > 0) try buf.appendSlice(ctx.allocator, int_str[0..first_group]);
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
        try buf.appendSlice(ctx.allocator, formatted.frac_part);
    }

    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

const RoundedFloat = struct { is_negative: bool, int_part: []const u8, frac_part: []const u8 };

// Round a float to `decimals` places using string-based half-away-from-zero rounding
// against the shortest round-trip representation (avoids 1.005 → 1.00 binary noise).
fn roundFloatToDecimals(num: f64, decimals: usize, int_buf: []u8, frac_buf: []u8) !RoundedFloat {
    const is_negative = num < 0 or (num == 0 and std.math.signbit(num));
    var abs_val = @abs(num);
    if (std.math.isNan(abs_val) or std.math.isInf(abs_val)) abs_val = 0;

    var src_buf: [64]u8 = undefined;
    var src = std.fmt.bufPrint(&src_buf, "{d}", .{abs_val}) catch "0";

    // expand scientific form (e.g. "1e-5", "1.5e10") to plain decimal
    var expanded_buf: [128]u8 = undefined;
    if (std.mem.indexOfAny(u8, src, "eE")) |_| {
        src = expandScientific(src, &expanded_buf) catch src;
    }

    const dot = std.mem.indexOfScalar(u8, src, '.');
    const int_in: []const u8 = if (dot) |d| src[0..d] else src;
    const frac_in: []const u8 = if (dot) |d| src[d + 1 ..] else "";

    // build a digit buffer combining int + frac with `decimals + 1` frac digits to inspect rounding digit
    var combined: [128]u8 = undefined;
    var c_len: usize = 0;
    for (int_in) |b| {
        if (c_len >= combined.len) break;
        combined[c_len] = b;
        c_len += 1;
    }
    var int_len = c_len;
    if (int_len == 0) {
        combined[0] = '0';
        int_len = 1;
        c_len = 1;
    }
    var fi: usize = 0;
    while (fi < decimals + 1) : (fi += 1) {
        if (c_len >= combined.len) break;
        combined[c_len] = if (fi < frac_in.len) frac_in[fi] else '0';
        c_len += 1;
    }

    // round-half-away-from-zero based on the digit at position int_len + decimals
    const round_pos = int_len + decimals;
    if (round_pos < c_len and combined[round_pos] >= '5') {
        var k: usize = round_pos;
        while (k > 0) {
            k -= 1;
            if (combined[k] < '9') {
                combined[k] += 1;
                break;
            } else {
                combined[k] = '0';
                if (k == 0) {
                    // need to prepend '1'
                    if (c_len >= combined.len) c_len = combined.len - 1;
                    var j: usize = c_len;
                    while (j > 0) : (j -= 1) combined[j] = combined[j - 1];
                    combined[0] = '1';
                    c_len += 1;
                    int_len += 1;
                    break;
                }
            }
        }
    }

    // copy out int part (strip leading zeros, keep at least one)
    var i_start: usize = 0;
    while (i_start < int_len - 1 and combined[i_start] == '0') i_start += 1;
    const ip_slice = combined[i_start..int_len];
    const ip_len = ip_slice.len;
    if (ip_len > int_buf.len) return .{ .is_negative = is_negative, .int_part = "0", .frac_part = "" };
    @memcpy(int_buf[0..ip_len], ip_slice);

    // copy frac part (exactly `decimals` digits)
    if (decimals > frac_buf.len) return .{ .is_negative = is_negative, .int_part = int_buf[0..ip_len], .frac_part = "" };
    var fp_len: usize = 0;
    while (fp_len < decimals) : (fp_len += 1) {
        const idx = int_len + fp_len;
        frac_buf[fp_len] = if (idx < c_len) combined[idx] else '0';
    }

    // suppress -0
    const all_zero = blk: {
        for (int_buf[0..ip_len]) |b| if (b != '0') break :blk false;
        for (frac_buf[0..fp_len]) |b| if (b != '0') break :blk false;
        break :blk true;
    };

    return .{
        .is_negative = is_negative and !all_zero,
        .int_part = int_buf[0..ip_len],
        .frac_part = frac_buf[0..fp_len],
    };
}

fn expandScientific(src: []const u8, out: []u8) ![]const u8 {
    const e_idx = std.mem.indexOfAny(u8, src, "eE") orelse return src;
    const mant = src[0..e_idx];
    const exp_str = src[e_idx + 1 ..];
    const exp = std.fmt.parseInt(i32, exp_str, 10) catch return src;

    const dot = std.mem.indexOfScalar(u8, mant, '.');
    const ip = if (dot) |d| mant[0..d] else mant;
    const fp = if (dot) |d| mant[d + 1 ..] else "";

    var digits_buf: [128]u8 = undefined;
    var dlen: usize = 0;
    for (ip) |b| {
        if (dlen >= digits_buf.len) break;
        digits_buf[dlen] = b;
        dlen += 1;
    }
    for (fp) |b| {
        if (dlen >= digits_buf.len) break;
        digits_buf[dlen] = b;
        dlen += 1;
    }
    // current decimal point sits after ip.len digits; new position = ip.len + exp
    const new_dot: i32 = @as(i32, @intCast(ip.len)) + exp;

    var ol: usize = 0;
    if (new_dot <= 0) {
        if (ol >= out.len) return src;
        out[ol] = '0';
        ol += 1;
        if (ol >= out.len) return src;
        out[ol] = '.';
        ol += 1;
        var pad: i32 = -new_dot;
        while (pad > 0) : (pad -= 1) {
            if (ol >= out.len) return src;
            out[ol] = '0';
            ol += 1;
        }
        for (digits_buf[0..dlen]) |b| {
            if (ol >= out.len) return src;
            out[ol] = b;
            ol += 1;
        }
    } else {
        const nd: usize = @intCast(new_dot);
        if (nd >= dlen) {
            for (digits_buf[0..dlen]) |b| {
                if (ol >= out.len) return src;
                out[ol] = b;
                ol += 1;
            }
            var pad: usize = nd - dlen;
            while (pad > 0) : (pad -= 1) {
                if (ol >= out.len) return src;
                out[ol] = '0';
                ol += 1;
            }
        } else {
            for (digits_buf[0..nd]) |b| {
                if (ol >= out.len) return src;
                out[ol] = b;
                ol += 1;
            }
            if (ol >= out.len) return src;
            out[ol] = '.';
            ol += 1;
            for (digits_buf[nd..dlen]) |b| {
                if (ol >= out.len) return src;
                out[ol] = b;
                ol += 1;
            }
        }
    }
    return out[0..ol];
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

fn native_fprintf(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .int = 0 };
    const fmt_str = if (args[1] == .string) args[1].string else return Value{ .int = 0 };
    const result = try sprintfImpl(ctx, fmt_str, args[2..]);
    const written = try ctx.vm.callByName("fwrite", &.{ args[0], .{ .string = result } });
    return written;
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

            // check for argument swapping: %N$
            var explicit_arg: ?usize = null;
            {
                var j = i;
                var num: usize = 0;
                var has_digits = false;
                while (j < fmt_str.len and fmt_str[j] >= '0' and fmt_str[j] <= '9') {
                    num = num * 10 + (fmt_str[j] - '0');
                    has_digits = true;
                    j += 1;
                }
                if (has_digits and j < fmt_str.len and fmt_str[j] == '$') {
                    explicit_arg = if (num > 0) num - 1 else 0;
                    i = j + 1;
                }
            }

            var pad_char: u8 = ' ';
            var left_align = false;
            var show_sign = false;

            // flags can appear in any order
            while (i < fmt_str.len) {
                const c = fmt_str[i];
                if (c == '-') {
                    left_align = true;
                    i += 1;
                } else if (c == '+') {
                    show_sign = true;
                    i += 1;
                } else if (c == '0') {
                    pad_char = '0';
                    i += 1;
                } else if (c == ' ') {
                    i += 1;
                } else if (c == '\'' and i + 1 < fmt_str.len) {
                    pad_char = fmt_str[i + 1];
                    i += 2;
                } else break;
            }

            var width: usize = 0;
            while (i < fmt_str.len and fmt_str[i] >= '0' and fmt_str[i] <= '9') {
                width = width * 10 + (fmt_str[i] - '0');
                i += 1;
            }

            var precision: ?usize = null;
            if (i < fmt_str.len and fmt_str[i] == '.') {
                i += 1;
                if (i < fmt_str.len and fmt_str[i] == '*') {
                    // dynamic precision from next arg
                    const prec_arg = if (arg_idx < args.len) args[arg_idx] else Value.null;
                    arg_idx += 1;
                    precision = @intCast(@max(0, Value.toInt(prec_arg)));
                    i += 1;
                } else {
                    precision = 0;
                    while (i < fmt_str.len and fmt_str[i] >= '0' and fmt_str[i] <= '9') {
                        precision.? = precision.? * 10 + (fmt_str[i] - '0');
                        i += 1;
                    }
                }
            }

            if (i >= fmt_str.len) break;
            const spec = fmt_str[i];
            i += 1;
            const arg = if (explicit_arg) |ea|
                (if (ea < args.len) args[ea] else Value.null)
            else blk: {
                const a = if (arg_idx < args.len) args[arg_idx] else Value.null;
                arg_idx += 1;
                break :blk a;
            };

            var tmp_buf = std.ArrayListUnmanaged(u8){};
            switch (spec) {
                's' => {
                    const s = blk: {
                        if (arg == .string) break :blk arg.string;
                        if (arg == .object) {
                            if (ctx.vm.callMethod(arg.object, "__toString", &.{})) |ret| {
                                if (ret == .string) break :blk ret.string;
                            } else |_| {}
                        }
                        try arg.format(&tmp_buf, ctx.allocator);
                        break :blk @as(?[]const u8, null);
                    };
                    if (s) |str| {
                        if (precision) |p| {
                            try tmp_buf.appendSlice(ctx.allocator, str[0..@min(p, str.len)]);
                        } else {
                            try tmp_buf.appendSlice(ctx.allocator, str);
                        }
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
                    var v = Value.toFloat(arg);
                    // php's %f drops the negative-zero sign
                    if (v == 0 and std.math.signbit(v)) v = 0;
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
                'u' => {
                    const v: u64 = @bitCast(Value.toInt(arg));
                    var num_buf: [32]u8 = undefined;
                    const s = std.fmt.bufPrint(&num_buf, "{d}", .{v}) catch "0";
                    try tmp_buf.appendSlice(ctx.allocator, s);
                },
                'e' => {
                    const v = Value.toFloat(arg);
                    const prec = precision orelse 6;
                    if (show_sign and v >= 0) try tmp_buf.append(ctx.allocator, '+');
                    try formatScientific(&tmp_buf, ctx.allocator, v, prec, 'e');
                },
                'E' => {
                    const v = Value.toFloat(arg);
                    const prec = precision orelse 6;
                    if (show_sign and v >= 0) try tmp_buf.append(ctx.allocator, '+');
                    try formatScientific(&tmp_buf, ctx.allocator, v, prec, 'E');
                },
                'g', 'G' => {
                    const v = Value.toFloat(arg);
                    const prec = if (precision) |p| @max(p, 1) else 6;
                    if (show_sign and v >= 0) try tmp_buf.append(ctx.allocator, '+');
                    try formatGeneral(&tmp_buf, ctx.allocator, v, prec, spec);
                },
                else => {
                    try buf.append(ctx.allocator, '%');
                    try buf.append(ctx.allocator, spec);
                    continue;
                },
            }

            const formatted = tmp_buf.items;
            // when left-align is combined with zero-pad flag, php ignores zero
            // pad (left-align always right-pads with spaces)
            const effective_pad: u8 = if (left_align and pad_char == '0') ' ' else pad_char;
            if (width > formatted.len) {
                const padding = width - formatted.len;
                if (left_align) {
                    try buf.appendSlice(ctx.allocator, formatted);
                    for (0..padding) |_| try buf.append(ctx.allocator, effective_pad);
                } else if (effective_pad == '0' and formatted.len > 0 and (formatted[0] == '+' or formatted[0] == '-')) {
                    try buf.append(ctx.allocator, formatted[0]);
                    for (0..padding) |_| try buf.append(ctx.allocator, '0');
                    try buf.appendSlice(ctx.allocator, formatted[1..]);
                } else {
                    for (0..padding) |_| try buf.append(ctx.allocator, effective_pad);
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
    if (std.math.isNan(val)) {
        try buf.appendSlice(a, "NaN");
        return;
    }
    if (std.math.isInf(val)) {
        if (val < 0) try buf.append(a, '-');
        try buf.appendSlice(a, "INF");
        return;
    }
    // Use C snprintf for bit-exact decimal expansion + banker's rounding,
    // matching PHP's printf-derived behaviour for %.Nf (e.g. 1.005 → "1.00",
    // 2.675 → "2.67"). On failure, fall back to Zig's formatter.
    var fmt_buf: [16]u8 = undefined;
    const fmt_str = std.fmt.bufPrintZ(&fmt_buf, "%.{d}f", .{prec}) catch {
        const s = std.fmt.allocPrint(a, "{d:.[1]}", .{ val, prec }) catch return;
        defer a.free(s);
        try buf.appendSlice(a, s);
        return;
    };
    var out_buf: [512]u8 = undefined;
    const n = snprintf(&out_buf, out_buf.len, fmt_str.ptr, val);
    if (n <= 0 or @as(usize, @intCast(n)) >= out_buf.len) {
        const s = std.fmt.allocPrint(a, "{d:.[1]}", .{ val, prec }) catch return;
        defer a.free(s);
        try buf.appendSlice(a, s);
        return;
    }
    var slice = out_buf[0..@intCast(n)];
    // PHP keeps the negative sign even when the rounded result is "0.00..." —
    // C snprintf does the same, so just pass through.
    // (Special: when val is -0.0 with no fraction part PHP does NOT show '-' for %f;
    // C's printf may show -0. Detect and strip in that one case.)
    if (val == 0 and std.math.signbit(val) and prec > 0 and slice[0] == '-') {
        slice = slice[1..];
    }
    try buf.appendSlice(a, slice);
}

const RoundedFloatBanker = struct { is_negative: bool, int_part: []const u8, frac_part: []const u8 };

// Round half-to-even (banker's) using shortest-roundtrip representation.
fn bankersRoundFloat(num: f64, decimals: usize, int_buf: []u8, frac_buf: []u8) !RoundedFloatBanker {
    const is_negative = num < 0;
    var abs_val = @abs(num);
    if (std.math.isNan(abs_val) or std.math.isInf(abs_val)) abs_val = 0;

    var src_buf: [64]u8 = undefined;
    var src = std.fmt.bufPrint(&src_buf, "{d}", .{abs_val}) catch "0";

    var expanded_buf: [128]u8 = undefined;
    if (std.mem.indexOfAny(u8, src, "eE")) |_| {
        src = expandScientific(src, &expanded_buf) catch src;
    }

    const dot = std.mem.indexOfScalar(u8, src, '.');
    const int_in: []const u8 = if (dot) |d| src[0..d] else src;
    const frac_in: []const u8 = if (dot) |d| src[d + 1 ..] else "";

    var combined: [256]u8 = undefined;
    var c_len: usize = 0;
    for (int_in) |b| {
        if (c_len >= combined.len) break;
        combined[c_len] = b;
        c_len += 1;
    }
    var int_len = c_len;
    if (int_len == 0) {
        combined[0] = '0';
        int_len = 1;
        c_len = 1;
    }
    var fi: usize = 0;
    while (fi < decimals + 1) : (fi += 1) {
        if (c_len >= combined.len) break;
        combined[c_len] = if (fi < frac_in.len) frac_in[fi] else '0';
        c_len += 1;
    }

    const round_pos = int_len + decimals;
    if (round_pos < c_len) {
        const round_digit = combined[round_pos];
        var should_round_up = false;
        if (round_digit > '5') {
            should_round_up = true;
        } else if (round_digit == '5') {
            // banker's: round up only if any digit beyond is non-zero,
            // otherwise round to even (round up only when preceding digit is odd)
            var has_more = false;
            var k: usize = round_pos + 1;
            while (k < c_len) : (k += 1) {
                if (combined[k] != '0') {
                    has_more = true;
                    break;
                }
            }
            if (!has_more) {
                var fk: usize = decimals + 1;
                while (fk < frac_in.len) : (fk += 1) {
                    if (frac_in[fk] != '0') {
                        has_more = true;
                        break;
                    }
                }
            }
            if (has_more) {
                should_round_up = true;
            } else {
                const prev_digit: u8 = if (round_pos == 0) '0' else combined[round_pos - 1];
                if ((prev_digit - '0') % 2 == 1) should_round_up = true;
            }
        }
        if (should_round_up) {
            var k: usize = round_pos;
            while (k > 0) {
                k -= 1;
                if (combined[k] < '9') {
                    combined[k] += 1;
                    break;
                } else {
                    combined[k] = '0';
                    if (k == 0) {
                        if (c_len >= combined.len) c_len = combined.len - 1;
                        var j: usize = c_len;
                        while (j > 0) : (j -= 1) combined[j] = combined[j - 1];
                        combined[0] = '1';
                        c_len += 1;
                        int_len += 1;
                        break;
                    }
                }
            }
        }
    }

    var i_start: usize = 0;
    while (i_start < int_len - 1 and combined[i_start] == '0') i_start += 1;
    const ip_slice = combined[i_start..int_len];
    if (ip_slice.len > int_buf.len) return error.Overflow;
    @memcpy(int_buf[0..ip_slice.len], ip_slice);

    if (decimals > frac_buf.len) return error.Overflow;
    var fp_len: usize = 0;
    while (fp_len < decimals) : (fp_len += 1) {
        const idx = int_len + fp_len;
        frac_buf[fp_len] = if (idx < c_len) combined[idx] else '0';
    }

    return .{
        .is_negative = is_negative,
        .int_part = int_buf[0..ip_slice.len],
        .frac_part = frac_buf[0..fp_len],
    };
}


fn formatScientific(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, val: f64, prec: usize, e_char: u8) !void {
    if (std.math.isNan(val)) {
        try buf.appendSlice(a, "NaN");
        return;
    }
    if (std.math.isInf(val)) {
        if (val < 0) try buf.append(a, '-');
        try buf.appendSlice(a, "INF");
        return;
    }
    if (val == 0) {
        try buf.appendSlice(a, "0.");
        for (0..prec) |_| try buf.append(a, '0');
        try buf.append(a, e_char);
        try buf.appendSlice(a, "+0");
        return;
    }
    const is_neg = val < 0;
    const abs_val = @abs(val);
    const exp_val: i32 = @intFromFloat(@floor(std.math.log10(abs_val)));
    const mantissa = abs_val / std.math.pow(f64, 10.0, @as(f64, @floatFromInt(exp_val)));

    if (is_neg) try buf.append(a, '-');
    try formatFixedFloat(buf, a, mantissa, prec);
    try buf.append(a, e_char);
    try buf.append(a, if (exp_val >= 0) '+' else '-');
    var exp_buf: [16]u8 = undefined;
    const abs_exp: u32 = @intCast(if (exp_val < 0) -exp_val else exp_val);
    const exp_str = std.fmt.bufPrint(&exp_buf, "{d}", .{abs_exp}) catch "0";
    try buf.appendSlice(a, exp_str);
}

fn formatGeneral(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, val: f64, prec: usize, g_char: u8) !void {
    if (val == 0) {
        try buf.append(a, '0');
        return;
    }
    if (std.math.isNan(val)) {
        try buf.appendSlice(a, "NaN");
        return;
    }
    if (std.math.isInf(val)) {
        if (val < 0) try buf.append(a, '-');
        try buf.appendSlice(a, "INF");
        return;
    }
    const is_neg = val < 0;
    const abs_val = @abs(val);
    const exp_val: i32 = @intFromFloat(@floor(std.math.log10(abs_val)));
    // C/PHP: precision 0 is treated as 1 for %g
    const sig: i32 = @intCast(if (prec == 0) 1 else prec);

    if (exp_val >= sig or exp_val < -4) {
        if (is_neg) try buf.append(a, '-');
        const mantissa = abs_val / std.math.pow(f64, 10.0, @as(f64, @floatFromInt(exp_val)));
        const sci_prec = if (sig > 1) @as(usize, @intCast(sig - 1)) else 0;
        const before_mant = buf.items.len;
        try formatFixedFloat(buf, a, mantissa, sci_prec);
        // strip trailing zeros after decimal point
        stripTrailingZeros(buf);
        // ensure mantissa has at least ".0" so output is "1.0e+3" not "1e+3"
        const mant_slice = buf.items[before_mant..];
        var has_dot = false;
        for (mant_slice) |c| if (c == '.') { has_dot = true; break; };
        if (!has_dot) try buf.appendSlice(a, ".0");
        const e_char: u8 = if (g_char == 'G') 'E' else 'e';
        try buf.append(a, e_char);
        try buf.append(a, if (exp_val >= 0) '+' else '-');
        var exp_buf: [16]u8 = undefined;
        const abs_exp: u32 = @intCast(if (exp_val < 0) -exp_val else exp_val);
        const exp_str = std.fmt.bufPrint(&exp_buf, "{d}", .{abs_exp}) catch "0";
        try buf.appendSlice(a, exp_str);
    } else {
        const fixed_prec = if (sig > exp_val + 1) @as(usize, @intCast(sig - exp_val - 1)) else 0;
        const round_factor = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(fixed_prec)));
        const rounded = roundHalfToEven(abs_val * round_factor) / round_factor;
        if (is_neg) try buf.append(a, '-');
        try formatFixedFloat(buf, a, rounded, fixed_prec);
        stripTrailingZeros(buf);
    }
}

fn roundHalfToEven(x: f64) f64 {
    const fl = @floor(x);
    const diff = x - fl;
    if (diff < 0.5) return fl;
    if (diff > 0.5) return fl + 1;
    // exact half: round to even
    const fl_i: i64 = @intFromFloat(fl);
    if (@mod(fl_i, 2) == 0) return fl;
    return fl + 1;
}

fn stripTrailingZeros(buf: *std.ArrayListUnmanaged(u8)) void {
    var has_dot = false;
    for (buf.items) |c| {
        if (c == '.') { has_dot = true; break; }
    }
    if (!has_dot) return;
    while (buf.items.len > 0 and buf.items[buf.items.len - 1] == '0') {
        buf.items.len -= 1;
    }
    if (buf.items.len > 0 and buf.items[buf.items.len - 1] == '.') {
        buf.items.len -= 1;
    }
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

fn latin1NamedEntity(cp: u21) ?[]const u8 {
    return switch (cp) {
        0x00A0 => "&nbsp;",
        0x00A1 => "&iexcl;",
        0x00A2 => "&cent;",
        0x00A3 => "&pound;",
        0x00A4 => "&curren;",
        0x00A5 => "&yen;",
        0x00A6 => "&brvbar;",
        0x00A7 => "&sect;",
        0x00A8 => "&uml;",
        0x00A9 => "&copy;",
        0x00AA => "&ordf;",
        0x00AB => "&laquo;",
        0x00AC => "&not;",
        0x00AD => "&shy;",
        0x00AE => "&reg;",
        0x00AF => "&macr;",
        0x00B0 => "&deg;",
        0x00B1 => "&plusmn;",
        0x00B2 => "&sup2;",
        0x00B3 => "&sup3;",
        0x00B4 => "&acute;",
        0x00B5 => "&micro;",
        0x00B6 => "&para;",
        0x00B7 => "&middot;",
        0x00B8 => "&cedil;",
        0x00B9 => "&sup1;",
        0x00BA => "&ordm;",
        0x00BB => "&raquo;",
        0x00BC => "&frac14;",
        0x00BD => "&frac12;",
        0x00BE => "&frac34;",
        0x00BF => "&iquest;",
        0x00C0 => "&Agrave;",
        0x00C1 => "&Aacute;",
        0x00C2 => "&Acirc;",
        0x00C3 => "&Atilde;",
        0x00C4 => "&Auml;",
        0x00C5 => "&Aring;",
        0x00C6 => "&AElig;",
        0x00C7 => "&Ccedil;",
        0x00C8 => "&Egrave;",
        0x00C9 => "&Eacute;",
        0x00CA => "&Ecirc;",
        0x00CB => "&Euml;",
        0x00CC => "&Igrave;",
        0x00CD => "&Iacute;",
        0x00CE => "&Icirc;",
        0x00CF => "&Iuml;",
        0x00D0 => "&ETH;",
        0x00D1 => "&Ntilde;",
        0x00D2 => "&Ograve;",
        0x00D3 => "&Oacute;",
        0x00D4 => "&Ocirc;",
        0x00D5 => "&Otilde;",
        0x00D6 => "&Ouml;",
        0x00D7 => "&times;",
        0x00D8 => "&Oslash;",
        0x00D9 => "&Ugrave;",
        0x00DA => "&Uacute;",
        0x00DB => "&Ucirc;",
        0x00DC => "&Uuml;",
        0x00DD => "&Yacute;",
        0x00DE => "&THORN;",
        0x00DF => "&szlig;",
        0x00E0 => "&agrave;",
        0x00E1 => "&aacute;",
        0x00E2 => "&acirc;",
        0x00E3 => "&atilde;",
        0x00E4 => "&auml;",
        0x00E5 => "&aring;",
        0x00E6 => "&aelig;",
        0x00E7 => "&ccedil;",
        0x00E8 => "&egrave;",
        0x00E9 => "&eacute;",
        0x00EA => "&ecirc;",
        0x00EB => "&euml;",
        0x00EC => "&igrave;",
        0x00ED => "&iacute;",
        0x00EE => "&icirc;",
        0x00EF => "&iuml;",
        0x00F0 => "&eth;",
        0x00F1 => "&ntilde;",
        0x00F2 => "&ograve;",
        0x00F3 => "&oacute;",
        0x00F4 => "&ocirc;",
        0x00F5 => "&otilde;",
        0x00F6 => "&ouml;",
        0x00F7 => "&divide;",
        0x00F8 => "&oslash;",
        0x00F9 => "&ugrave;",
        0x00FA => "&uacute;",
        0x00FB => "&ucirc;",
        0x00FC => "&uuml;",
        0x00FD => "&yacute;",
        0x00FE => "&thorn;",
        0x00FF => "&yuml;",
        // common HTML5 entities beyond Latin-1 that PHP's htmlentities emits by default
        0x0152 => "&OElig;",   0x0153 => "&oelig;",
        0x0160 => "&Scaron;",  0x0161 => "&scaron;",
        0x0178 => "&Yuml;",
        0x0192 => "&fnof;",
        0x02C6 => "&circ;",    0x02DC => "&tilde;",
        0x2002 => "&ensp;",    0x2003 => "&emsp;",   0x2009 => "&thinsp;",
        0x200C => "&zwnj;",    0x200D => "&zwj;",
        0x200E => "&lrm;",     0x200F => "&rlm;",
        0x2013 => "&ndash;",   0x2014 => "&mdash;",
        0x2018 => "&lsquo;",   0x2019 => "&rsquo;",  0x201A => "&sbquo;",
        0x201C => "&ldquo;",   0x201D => "&rdquo;",  0x201E => "&bdquo;",
        0x2020 => "&dagger;",  0x2021 => "&Dagger;",
        0x2022 => "&bull;",    0x2026 => "&hellip;",
        0x2030 => "&permil;",
        0x2039 => "&lsaquo;",  0x203A => "&rsaquo;",
        0x20AC => "&euro;",
        0x2122 => "&trade;",
        0x2190 => "&larr;",    0x2191 => "&uarr;",   0x2192 => "&rarr;",   0x2193 => "&darr;",
        0x2194 => "&harr;",
        0x21B5 => "&crarr;",
        0x2208 => "&isin;",    0x2209 => "&notin;",  0x220B => "&ni;",
        0x2211 => "&sum;",     0x2212 => "&minus;",
        0x221A => "&radic;",   0x221E => "&infin;",
        0x2245 => "&cong;",    0x2248 => "&asymp;",
        0x2260 => "&ne;",      0x2261 => "&equiv;",
        0x2264 => "&le;",      0x2265 => "&ge;",
        0x2282 => "&sub;",     0x2283 => "&sup;",    0x2286 => "&sube;",   0x2287 => "&supe;",
        0x2295 => "&oplus;",   0x2297 => "&otimes;",
        0x22A5 => "&perp;",
        0x22C5 => "&sdot;",
        0x2308 => "&lceil;",   0x2309 => "&rceil;",
        0x230A => "&lfloor;",  0x230B => "&rfloor;",
        0x2329 => "&lang;",    0x232A => "&rang;",
        0x25CA => "&loz;",
        0x2660 => "&spades;",  0x2663 => "&clubs;",  0x2665 => "&hearts;", 0x2666 => "&diams;",
        else => null,
    };
}

fn native_get_html_translation_table(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const table_kind: i64 = if (args.len >= 1) Value.toInt(args[0]) else 0;
    const flags: i64 = if (args.len >= 2) Value.toInt(args[1]) else 3;
    const escape_double = (flags & 2) != 0;
    const escape_single = (flags & 1) != 0;

    var arr = try ctx.createArray();

    // base 5 (always present): < > & " '
    if (escape_double) try arr.set(ctx.allocator, .{ .string = "\"" }, .{ .string = "&quot;" });
    if (escape_single) try arr.set(ctx.allocator, .{ .string = "'" }, .{ .string = "&#039;" });
    try arr.set(ctx.allocator, .{ .string = "&" }, .{ .string = "&amp;" });
    try arr.set(ctx.allocator, .{ .string = "<" }, .{ .string = "&lt;" });
    try arr.set(ctx.allocator, .{ .string = ">" }, .{ .string = "&gt;" });

    if (table_kind == 1) { // HTML_ENTITIES adds Latin-1 named entities
        var cp: u21 = 0xA0;
        while (cp <= 0xFF) : (cp += 1) {
            if (latin1NamedEntity(cp)) |ent| {
                var enc: [4]u8 = undefined;
                const elen = std.unicode.utf8Encode(cp, &enc) catch continue;
                const key = try ctx.allocator.dupe(u8, enc[0..elen]);
                try ctx.vm.strings.append(ctx.allocator, key);
                try arr.set(ctx.allocator, .{ .string = key }, .{ .string = ent });
            }
        }
    }

    return .{ .array = arr };
}

fn native_htmlentities(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    if (args[0] == .null) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else blk: {
        var buf = std.ArrayListUnmanaged(u8){};
        try args[0].format(&buf, ctx.allocator);
        const c = try buf.toOwnedSlice(ctx.allocator);
        try ctx.strings.append(ctx.allocator, c);
        break :blk c;
    };
    const flags: i64 = if (args.len >= 2) Value.toInt(args[1]) else 3;
    const escape_double = (flags & 2) != 0;
    const escape_single = (flags & 1) != 0;

    var buf = std.ArrayListUnmanaged(u8){};
    var i: usize = 0;
    while (i < s.len) {
        const b = s[i];
        if (b < 0x80) {
            switch (b) {
                '&' => try buf.appendSlice(ctx.allocator, "&amp;"),
                '"' => if (escape_double) try buf.appendSlice(ctx.allocator, "&quot;") else try buf.append(ctx.allocator, '"'),
                '\'' => if (escape_single) try buf.appendSlice(ctx.allocator, "&#039;") else try buf.append(ctx.allocator, '\''),
                '<' => try buf.appendSlice(ctx.allocator, "&lt;"),
                '>' => try buf.appendSlice(ctx.allocator, "&gt;"),
                else => try buf.append(ctx.allocator, b),
            }
            i += 1;
            continue;
        }
        const len = std.unicode.utf8ByteSequenceLength(b) catch {
            try buf.append(ctx.allocator, b);
            i += 1;
            continue;
        };
        if (i + len > s.len) {
            try buf.append(ctx.allocator, b);
            i += 1;
            continue;
        }
        const cp = std.unicode.utf8Decode(s[i .. i + len]) catch {
            try buf.appendSlice(ctx.allocator, s[i .. i + len]);
            i += len;
            continue;
        };
        if (latin1NamedEntity(cp)) |ent| {
            try buf.appendSlice(ctx.allocator, ent);
        } else {
            try buf.appendSlice(ctx.allocator, s[i .. i + len]);
        }
        i += len;
    }
    const out = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, out);
    return .{ .string = out };
}

fn native_htmlspecialchars(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    if (args[0] == .null) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else blk: {
        var buf = std.ArrayListUnmanaged(u8){};
        try args[0].format(&buf, ctx.allocator);
        const converted = try buf.toOwnedSlice(ctx.allocator);
        try ctx.strings.append(ctx.allocator, converted);
        break :blk converted;
    };
    const flags: i64 = if (args.len >= 2) Value.toInt(args[1]) else 3;
    const escape_double = (flags & 2) != 0;
    const escape_single = (flags & 1) != 0;
    const double_encode: bool = if (args.len >= 4) args[3].isTruthy() else true;
    var buf = std.ArrayListUnmanaged(u8){};
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        switch (c) {
            '&' => {
                const entity_len: ?usize = if (double_encode) null else htmlEntityAt(s, i);
                if (entity_len) |elen| {
                    try buf.appendSlice(ctx.allocator, s[i .. i + elen]);
                    i += elen - 1;
                } else {
                    try buf.appendSlice(ctx.allocator, "&amp;");
                }
            },
            '"' => if (escape_double) try buf.appendSlice(ctx.allocator, "&quot;") else try buf.append(ctx.allocator, '"'),
            '\'' => if (escape_single) try buf.appendSlice(ctx.allocator, "&#039;") else try buf.append(ctx.allocator, '\''),
            '<' => try buf.appendSlice(ctx.allocator, "&lt;"),
            '>' => try buf.appendSlice(ctx.allocator, "&gt;"),
            else => try buf.append(ctx.allocator, c),
        }
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

// returns total entity length (including '&' and ';') if s[i..] starts with a
// valid htmlspecialchars entity (&amp;, &lt;, &gt;, &quot;, &#039;/&apos;, or
// numeric &#NNN;/&#xNN;), else null. arbitrary &word; sequences are NOT valid
// here (htmlspecialchars only preserves the five chars it actually encodes).
fn htmlEntityAt(s: []const u8, i: usize) ?usize {
    if (i >= s.len or s[i] != '&') return null;
    var j: usize = i + 1;
    if (j < s.len and s[j] == '#') {
        j += 1;
        const is_hex = j < s.len and (s[j] == 'x' or s[j] == 'X');
        if (is_hex) j += 1;
        const start = j;
        while (j < s.len) : (j += 1) {
            const c = s[j];
            const ok = if (is_hex) std.ascii.isHex(c) else std.ascii.isDigit(c);
            if (!ok) break;
        }
        if (j > start and j < s.len and s[j] == ';') return j - i + 1;
        return null;
    }
    const start = j;
    while (j < s.len and std.ascii.isAlphanumeric(s[j])) : (j += 1) {}
    if (j == start or j >= s.len or s[j] != ';') return null;
    const name = s[start..j];
    const is_hsc = std.mem.eql(u8, name, "amp") or std.mem.eql(u8, name, "lt") or
        std.mem.eql(u8, name, "gt") or std.mem.eql(u8, name, "quot") or
        std.mem.eql(u8, name, "apos");
    if (is_hsc) return j - i + 1;
    if (latin1EntityToCodepoint(name) != null) return j - i + 1;
    if (html5EntityToCodepoint(name) != null) return j - i + 1;
    return null;
}

fn html5EntityToCodepoint(name: []const u8) ?u21 {
    const map = .{
        .{ "OElig", 0x0152 },  .{ "oelig", 0x0153 },
        .{ "Scaron", 0x0160 }, .{ "scaron", 0x0161 },
        .{ "Yuml", 0x0178 },   .{ "fnof", 0x0192 },
        .{ "circ", 0x02C6 },   .{ "tilde", 0x02DC },
        .{ "ensp", 0x2002 },   .{ "emsp", 0x2003 },   .{ "thinsp", 0x2009 },
        .{ "zwnj", 0x200C },   .{ "zwj", 0x200D },
        .{ "lrm", 0x200E },    .{ "rlm", 0x200F },
        .{ "ndash", 0x2013 },  .{ "mdash", 0x2014 },
        .{ "lsquo", 0x2018 },  .{ "rsquo", 0x2019 },  .{ "sbquo", 0x201A },
        .{ "ldquo", 0x201C },  .{ "rdquo", 0x201D },  .{ "bdquo", 0x201E },
        .{ "dagger", 0x2020 }, .{ "Dagger", 0x2021 },
        .{ "bull", 0x2022 },   .{ "hellip", 0x2026 }, .{ "permil", 0x2030 },
        .{ "lsaquo", 0x2039 }, .{ "rsaquo", 0x203A },
        .{ "euro", 0x20AC },   .{ "trade", 0x2122 },
        .{ "larr", 0x2190 },   .{ "uarr", 0x2191 },   .{ "rarr", 0x2192 },   .{ "darr", 0x2193 },
        .{ "harr", 0x2194 },   .{ "crarr", 0x21B5 },
        .{ "isin", 0x2208 },   .{ "notin", 0x2209 },  .{ "ni", 0x220B },
        .{ "sum", 0x2211 },    .{ "minus", 0x2212 },
        .{ "radic", 0x221A },  .{ "infin", 0x221E },
        .{ "cong", 0x2245 },   .{ "asymp", 0x2248 },
        .{ "ne", 0x2260 },     .{ "equiv", 0x2261 },
        .{ "le", 0x2264 },     .{ "ge", 0x2265 },
        .{ "sub", 0x2282 },    .{ "sup", 0x2283 },    .{ "sube", 0x2286 },   .{ "supe", 0x2287 },
        .{ "oplus", 0x2295 },  .{ "otimes", 0x2297 }, .{ "perp", 0x22A5 },   .{ "sdot", 0x22C5 },
        .{ "lceil", 0x2308 },  .{ "rceil", 0x2309 },  .{ "lfloor", 0x230A }, .{ "rfloor", 0x230B },
        .{ "lang", 0x2329 },   .{ "rang", 0x232A },
        .{ "loz", 0x25CA },
        .{ "spades", 0x2660 }, .{ "clubs", 0x2663 },  .{ "hearts", 0x2665 }, .{ "diams", 0x2666 },
    };
    inline for (map) |entry| {
        if (std.mem.eql(u8, entry[0], name)) return @as(u21, entry[1]);
    }
    return null;
}

fn latin1EntityToCodepoint(name: []const u8) ?u21 {
    const map = .{
        .{ "nbsp", 0x00A0 },  .{ "iexcl", 0x00A1 },  .{ "cent", 0x00A2 },
        .{ "pound", 0x00A3 }, .{ "curren", 0x00A4 }, .{ "yen", 0x00A5 },
        .{ "brvbar", 0x00A6 },.{ "sect", 0x00A7 },   .{ "uml", 0x00A8 },
        .{ "copy", 0x00A9 },  .{ "ordf", 0x00AA },   .{ "laquo", 0x00AB },
        .{ "not", 0x00AC },   .{ "shy", 0x00AD },    .{ "reg", 0x00AE },
        .{ "macr", 0x00AF },  .{ "deg", 0x00B0 },    .{ "plusmn", 0x00B1 },
        .{ "sup2", 0x00B2 },  .{ "sup3", 0x00B3 },   .{ "acute", 0x00B4 },
        .{ "micro", 0x00B5 }, .{ "para", 0x00B6 },   .{ "middot", 0x00B7 },
        .{ "cedil", 0x00B8 }, .{ "sup1", 0x00B9 },   .{ "ordm", 0x00BA },
        .{ "raquo", 0x00BB }, .{ "frac14", 0x00BC }, .{ "frac12", 0x00BD },
        .{ "frac34", 0x00BE },.{ "iquest", 0x00BF }, .{ "Agrave", 0x00C0 },
        .{ "Aacute", 0x00C1 },.{ "Acirc", 0x00C2 },  .{ "Atilde", 0x00C3 },
        .{ "Auml", 0x00C4 },  .{ "Aring", 0x00C5 },  .{ "AElig", 0x00C6 },
        .{ "Ccedil", 0x00C7 },.{ "Egrave", 0x00C8 }, .{ "Eacute", 0x00C9 },
        .{ "Ecirc", 0x00CA }, .{ "Euml", 0x00CB },   .{ "Igrave", 0x00CC },
        .{ "Iacute", 0x00CD },.{ "Icirc", 0x00CE },  .{ "Iuml", 0x00CF },
        .{ "ETH", 0x00D0 },   .{ "Ntilde", 0x00D1 }, .{ "Ograve", 0x00D2 },
        .{ "Oacute", 0x00D3 },.{ "Ocirc", 0x00D4 },  .{ "Otilde", 0x00D5 },
        .{ "Ouml", 0x00D6 },  .{ "times", 0x00D7 },  .{ "Oslash", 0x00D8 },
        .{ "Ugrave", 0x00D9 },.{ "Uacute", 0x00DA }, .{ "Ucirc", 0x00DB },
        .{ "Uuml", 0x00DC },  .{ "Yacute", 0x00DD }, .{ "THORN", 0x00DE },
        .{ "szlig", 0x00DF }, .{ "agrave", 0x00E0 }, .{ "aacute", 0x00E1 },
        .{ "acirc", 0x00E2 }, .{ "atilde", 0x00E3 }, .{ "auml", 0x00E4 },
        .{ "aring", 0x00E5 }, .{ "aelig", 0x00E6 }, .{ "ccedil", 0x00E7 },
        .{ "egrave", 0x00E8 },.{ "eacute", 0x00E9 }, .{ "ecirc", 0x00EA },
        .{ "euml", 0x00EB },  .{ "igrave", 0x00EC }, .{ "iacute", 0x00ED },
        .{ "icirc", 0x00EE }, .{ "iuml", 0x00EF }, .{ "eth", 0x00F0 },
        .{ "ntilde", 0x00F1 },.{ "ograve", 0x00F2 }, .{ "oacute", 0x00F3 },
        .{ "ocirc", 0x00F4 }, .{ "otilde", 0x00F5 }, .{ "ouml", 0x00F6 },
        .{ "divide", 0x00F7 },.{ "oslash", 0x00F8 }, .{ "ugrave", 0x00F9 },
        .{ "uacute", 0x00FA },.{ "ucirc", 0x00FB }, .{ "uuml", 0x00FC },
        .{ "yacute", 0x00FD },.{ "thorn", 0x00FE }, .{ "yuml", 0x00FF },
    };
    inline for (map) |entry| {
        if (std.mem.eql(u8, entry[0], name)) return @as(u21, entry[1]);
    }
    return null;
}

fn native_html_entity_decode(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const flags: i64 = if (args.len >= 2) Value.toInt(args[1]) else 11;
    // HTML5/XHTML/XML1 modes (bits 4-5) recognize &apos;; HTML401 default does not
    const html5_mode = (flags & 48) != 0;
    var buf = std.ArrayListUnmanaged(u8){};
    var j: usize = 0;
    while (j < s.len) {
        if (s[j] == '&') {
            if (matchEntity(s[j..])) |ent| {
                try buf.append(ctx.allocator, ent.char);
                j += ent.len;
                continue;
            }
            if (matchNumericEntity(s[j..])) |ne| {
                try appendCodepoint(&buf, ctx.allocator, ne.code);
                j += ne.len;
                continue;
            }
            // Try named entity: scan to ';' looking up in latin-1 then HTML5 tables
            var k = j + 1;
            while (k < s.len and k < j + 16 and (std.ascii.isAlphanumeric(s[k]))) : (k += 1) {}
            if (k < s.len and s[k] == ';' and k > j + 1) {
                const name = s[j + 1 .. k];
                if (html5_mode and std.mem.eql(u8, name, "apos")) {
                    try buf.append(ctx.allocator, '\'');
                    j = k + 1;
                    continue;
                }
                if (latin1EntityToCodepoint(name)) |cp| {
                    try appendCodepoint(&buf, ctx.allocator, @intCast(cp));
                    j = k + 1;
                    continue;
                }
                if (html5EntityToCodepoint(name)) |cp| {
                    try appendCodepoint(&buf, ctx.allocator, @intCast(cp));
                    j = k + 1;
                    continue;
                }
            }
        }
        try buf.append(ctx.allocator, s[j]);
        j += 1;
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn native_htmlspecialchars_decode(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    const flags: i64 = if (args.len >= 2) Value.toInt(args[1]) else 3; // default ENT_QUOTES | ENT_HTML401
    const decode_double = (flags & 2) != 0;
    const decode_single = (flags & 1) != 0;
    var buf = std.ArrayListUnmanaged(u8){};
    var j: usize = 0;
    while (j < s.len) {
        if (s[j] == '&') {
            if (matchEntity(s[j..])) |ent| {
                const skip = (ent.char == '"' and !decode_double) or (ent.char == '\'' and !decode_single);
                if (!skip) {
                    try buf.append(ctx.allocator, ent.char);
                    j += ent.len;
                    continue;
                }
            }
            if (matchNumericEntity(s[j..])) |ne| {
                const skip = (ne.code == 34 and !decode_double) or (ne.code == 39 and !decode_single);
                if (!skip) {
                    try appendCodepoint(&buf, ctx.allocator, ne.code);
                    j += ne.len;
                    continue;
                }
            }
        }
        try buf.append(ctx.allocator, s[j]);
        j += 1;
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn matchNumericEntity(s: []const u8) ?struct { code: u32, len: usize } {
    if (s.len < 4 or s[0] != '&' or s[1] != '#') return null;
    var pos: usize = 2;
    const is_hex = s[pos] == 'x' or s[pos] == 'X';
    if (is_hex) pos += 1;
    const start = pos;
    while (pos < s.len and s[pos] != ';') : (pos += 1) {
        const c = s[pos];
        if (is_hex) {
            if (!((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F'))) return null;
        } else {
            if (c < '0' or c > '9') return null;
        }
    }
    if (pos >= s.len or s[pos] != ';' or pos == start) return null;
    const code = std.fmt.parseInt(u32, s[start..pos], if (is_hex) 16 else 10) catch return null;
    return .{ .code = code, .len = pos + 1 };
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

fn native_mb_str_split(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .null;
    const s = if (args[0] == .string) args[0].string else return Value.null;
    const chunk_len: usize = if (args.len >= 2) @intCast(@max(1, Value.toInt(args[1]))) else 1;
    var arr = try ctx.createArray();
    if (s.len == 0) {
        try arr.append(ctx.allocator, .{ .string = "" });
        return .{ .array = arr };
    }
    var i: usize = 0;
    while (i < s.len) {
        const start = i;
        var taken: usize = 0;
        while (taken < chunk_len and i < s.len) {
            const byte = s[i];
            if (byte < 0x80) i += 1
            else if (byte < 0xE0) i += 2
            else if (byte < 0xF0) i += 3
            else i += 4;
            if (i > s.len) i = s.len;
            taken += 1;
        }
        try arr.append(ctx.allocator, .{ .string = try ctx.createString(s[start..i]) });
    }
    return .{ .array = arr };
}

fn native_mb_strlen(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
    const s = if (args[0] == .string) args[0].string else return Value{ .int = 0 };
    if (args.len >= 2 and args[1] == .string) {
        const enc = args[1].string;
        if (std.ascii.eqlIgnoreCase(enc, "8bit") or std.ascii.eqlIgnoreCase(enc, "binary")) {
            return .{ .int = @intCast(s.len) };
        }
    }
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
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    return .{ .string = try utfCaseConvert(ctx, s, false) };
}

fn native_mb_strtoupper(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    return .{ .string = try utfCaseConvert(ctx, s, true) };
}

fn native_mb_convert_case(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string) return .{ .string = "" };
    const s = args[0].string;
    const mode = Value.toInt(args[1]);
    return switch (mode) {
        0 => .{ .string = try utfCaseConvert(ctx, s, true) },
        1 => .{ .string = try utfCaseConvert(ctx, s, false) },
        2 => .{ .string = try utfTitleCase(ctx, s) },
        else => .{ .string = try ctx.createString(s) },
    };
}

fn utfTitleCase(ctx: *NativeContext, s: []const u8) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    var i: usize = 0;
    var at_word_start = true;
    while (i < s.len) {
        const byte = s[i];
        if (byte < 0x80) {
            const is_alpha = std.ascii.isAlphabetic(byte);
            const is_word = is_alpha or std.ascii.isDigit(byte);
            if (at_word_start and is_alpha) {
                try buf.append(ctx.allocator, std.ascii.toUpper(byte));
                at_word_start = false;
            } else if (is_alpha) {
                try buf.append(ctx.allocator, std.ascii.toLower(byte));
            } else {
                try buf.append(ctx.allocator, byte);
                if (!is_word) at_word_start = true;
            }
            i += 1;
        } else {
            const len = std.unicode.utf8ByteSequenceLength(byte) catch {
                try buf.append(ctx.allocator, byte);
                i += 1;
                continue;
            };
            if (i + len > s.len) {
                try buf.append(ctx.allocator, byte);
                i += 1;
                continue;
            }
            const cp = std.unicode.utf8Decode(s[i..][0..len]) catch {
                try buf.appendSlice(ctx.allocator, s[i .. i + len]);
                i += len;
                continue;
            };
            const mapped = if (at_word_start) unicodeToUpper(cp) else unicodeToLower(cp);
            var enc: [4]u8 = undefined;
            const enc_len = std.unicode.utf8Encode(mapped, &enc) catch {
                try buf.appendSlice(ctx.allocator, s[i .. i + len]);
                i += len;
                continue;
            };
            try buf.appendSlice(ctx.allocator, enc[0..enc_len]);
            at_word_start = false;
            i += len;
        }
    }
    const out = try ctx.allocator.dupe(u8, buf.items);
    buf.deinit(ctx.allocator);
    try ctx.strings.append(ctx.allocator, out);
    return out;
}

fn native_mb_check_encoding(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    _ = ctx;
    if (args.len == 0) return .{ .bool = true };
    if (args[0] != .string) return .{ .bool = false };
    const s = args[0].string;
    var i: usize = 0;
    while (i < s.len) {
        const byte = s[i];
        if (byte < 0x80) {
            i += 1;
            continue;
        }
        const len = std.unicode.utf8ByteSequenceLength(byte) catch return .{ .bool = false };
        if (i + len > s.len) return .{ .bool = false };
        _ = std.unicode.utf8Decode(s[i..][0..len]) catch return .{ .bool = false };
        i += len;
    }
    return .{ .bool = true };
}

fn utfCaseConvert(ctx: *NativeContext, s: []const u8, to_upper: bool) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    var i: usize = 0;
    while (i < s.len) {
        const byte = s[i];
        if (byte < 0x80) {
            try buf.append(ctx.allocator, if (to_upper) std.ascii.toUpper(byte) else std.ascii.toLower(byte));
            i += 1;
        } else {
            const len = std.unicode.utf8ByteSequenceLength(byte) catch {
                try buf.append(ctx.allocator, byte);
                i += 1;
                continue;
            };
            if (i + len > s.len) {
                try buf.append(ctx.allocator, byte);
                i += 1;
                continue;
            }
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
    try ctx.strings.append(ctx.allocator, result);
    return result;
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
    // latin extended-a pairs (0100-017E): odd codepoints are lowercase
    if (cp >= 0x0100 and cp <= 0x017E) {
        if (cp % 2 == 1) return cp - 1;
    }
    // greek lowercase to uppercase (03B1-03C9 -> 0391-03A9)
    if (cp >= 0x03B1 and cp <= 0x03C9) return cp - 0x20;
    // cyrillic lowercase to uppercase (0430-044F -> 0410-042F)
    if (cp >= 0x0430 and cp <= 0x044F) return cp - 0x20;
    return cp;
}

fn unicodeToLower(cp: u21) u21 {
    // latin-1 supplement: A-with-grave through O-with-diaeresis
    if (cp >= 0x00C0 and cp <= 0x00D6) return cp + 0x20;
    // latin-1 supplement: O-with-slash through Thorn
    if (cp >= 0x00D8 and cp <= 0x00DE) return cp + 0x20;
    // latin extended-a pairs (0100-017E): even codepoints are uppercase
    if (cp >= 0x0100 and cp <= 0x017E) {
        if (cp % 2 == 0) return cp + 1;
    }
    // greek uppercase to lowercase (0391-03A9 -> 03B1-03C9)
    if (cp >= 0x0391 and cp <= 0x03A9) return cp + 0x20;
    // cyrillic uppercase to lowercase (0410-042F -> 0430-044F)
    if (cp >= 0x0410 and cp <= 0x042F) return cp + 0x20;
    return cp;
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

fn native_mb_strwidth(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .int = 0 };
    const s = args[0].string;
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
    return .{ .int = width };
}

fn parseEntityMap(arr: *PhpArray) ?[4]i64 {
    if (arr.entries.items.len < 4) return null;
    var out: [4]i64 = .{ 0, 0, 0, 0 };
    for (arr.entries.items[0..4], 0..) |entry, i| out[i] = Value.toInt(entry.value);
    return out;
}

fn native_mb_encode_numericentity(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .array) return if (args.len > 0) args[0] else .{ .string = "" };
    const s = args[0].string;
    const map = parseEntityMap(args[1].array) orelse return args[0];
    const hex = args.len >= 4 and args[3].isTruthy();

    var buf = std.ArrayListUnmanaged(u8){};
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
    try ctx.strings.append(ctx.allocator, out);
    return .{ .string = out };
}

fn native_mb_decode_numericentity(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .array) return if (args.len > 0) args[0] else .{ .string = "" };
    const s = args[0].string;
    const map = parseEntityMap(args[1].array) orelse return args[0];

    var buf = std.ArrayListUnmanaged(u8){};
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
    try ctx.strings.append(ctx.allocator, out);
    return .{ .string = out };
}

fn native_mb_chr(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    const cp_int = Value.toInt(args[0]);
    if (cp_int < 0 or cp_int > 0x10FFFF) return .{ .bool = false };
    const cp: u21 = @intCast(cp_int);
    var buf: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(cp, &buf) catch return .{ .bool = false };
    const out = try ctx.allocator.dupe(u8, buf[0..n]);
    try ctx.strings.append(ctx.allocator, out);
    return .{ .string = out };
}

fn native_mb_ord(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const s = args[0].string;
    if (s.len == 0) {
        try ctx.vm.setPendingException("ValueError", "mb_ord(): Argument #1 ($string) must not be empty");
        return error.RuntimeError;
    }
    const len = std.unicode.utf8ByteSequenceLength(s[0]) catch return .{ .bool = false };
    if (len > s.len) return .{ .bool = false };
    const cp = std.unicode.utf8Decode(s[0..len]) catch return .{ .bool = false };
    return .{ .int = @intCast(cp) };
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

fn native_mb_stripos(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const haystack = args[0].string;
    const needle = args[1].string;
    if (needle.len == 0) return .{ .bool = false };
    const start_char: i64 = if (args.len >= 3) Value.toInt(args[2]) else 0;
    var byte_offset: usize = 0;
    var c: i64 = 0;
    while (byte_offset < haystack.len and c < start_char) {
        byte_offset += utf8CharLen(haystack[byte_offset]);
        c += 1;
    }
    var i = byte_offset;
    while (i < haystack.len) {
        if (matchAtCi(haystack, i, needle)) return .{ .int = byteToCharPos(haystack, i) };
        i += utf8CharLen(haystack[i]);
    }
    return .{ .bool = false };
}

fn native_mb_strstr(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const haystack = args[0].string;
    const needle = args[1].string;
    if (needle.len == 0) return .{ .bool = false };
    const before: bool = if (args.len >= 3) Value.isTruthy(args[2]) else false;
    if (std.mem.indexOf(u8, haystack, needle)) |pos| {
        const slice = if (before) haystack[0..pos] else haystack[pos..];
        return .{ .string = try ctx.createString(slice) };
    }
    return .{ .bool = false };
}

fn native_mb_stristr(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const haystack = args[0].string;
    const needle = args[1].string;
    if (needle.len == 0) return .{ .bool = false };
    const before: bool = if (args.len >= 3) Value.isTruthy(args[2]) else false;
    var i: usize = 0;
    while (i < haystack.len) : (i += utf8CharLen(haystack[i])) {
        if (matchAtCi(haystack, i, needle)) {
            const slice = if (before) haystack[0..i] else haystack[i..];
            return .{ .string = try ctx.createString(slice) };
        }
    }
    return .{ .bool = false };
}

fn native_mb_strcut(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .string = "" };
    const s = args[0].string;
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
    if (end <= ustart) return .{ .string = "" };
    return .{ .string = try ctx.createString(s[ustart..end]) };
}

fn native_mb_str_pad(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string) return args[0];
    const s = args[0].string;
    const target_chars: i64 = Value.toInt(args[1]);
    const pad_str: []const u8 = if (args.len >= 3 and args[2] == .string) args[2].string else " ";
    const pad_type: i64 = if (args.len >= 4) Value.toInt(args[3]) else 1; // STR_PAD_RIGHT
    if (pad_str.len == 0 or target_chars <= 0) return args[0];

    var s_chars: i64 = 0;
    var i: usize = 0;
    while (i < s.len) : (i += utf8CharLen(s[i])) s_chars += 1;
    if (s_chars >= target_chars) return args[0];
    const pad_needed: i64 = target_chars - s_chars;

    var pad_chars: i64 = 0;
    var pi: usize = 0;
    while (pi < pad_str.len) : (pi += utf8CharLen(pad_str[pi])) pad_chars += 1;
    if (pad_chars == 0) return args[0];

    const left_chars: i64 = switch (pad_type) {
        0 => pad_needed, // STR_PAD_LEFT
        2 => @divFloor(pad_needed, 2), // STR_PAD_BOTH
        else => 0,
    };
    const right_chars: i64 = pad_needed - left_chars;

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(ctx.allocator);

    try appendPadChars(ctx, &buf, pad_str, left_chars);
    try buf.appendSlice(ctx.allocator, s);
    try appendPadChars(ctx, &buf, pad_str, right_chars);

    return .{ .string = try ctx.createString(buf.items) };
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

fn native_str_getcsv(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .null;
    const s = if (args[0] == .string) args[0].string else return Value.null;
    const sep: u8 = if (args.len >= 2 and args[1] == .string and args[1].string.len > 0) args[1].string[0] else ',';
    const enc: u8 = if (args.len >= 3 and args[2] == .string and args[2].string.len > 0) args[2].string[0] else '"';

    var arr = try ctx.createArray();

    if (s.len == 0) {
        try arr.append(ctx.allocator, .{ .string = "" });
        return .{ .array = arr };
    }

    var field = std.ArrayListUnmanaged(u8){};
    var in_quotes = false;
    var at_field_start = true;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (in_quotes) {
            if (c == enc) {
                if (i + 1 < s.len and s[i + 1] == enc) {
                    try field.append(ctx.allocator, enc);
                    i += 1;
                } else {
                    in_quotes = false;
                }
            } else {
                try field.append(ctx.allocator, c);
            }
        } else {
            if (c == enc and at_field_start) {
                in_quotes = true;
                at_field_start = false;
            } else if (c == sep) {
                const f = try field.toOwnedSlice(ctx.allocator);
                try ctx.strings.append(ctx.allocator, f);
                try arr.append(ctx.allocator, .{ .string = f });
                at_field_start = true;
            } else {
                try field.append(ctx.allocator, c);
                at_field_start = false;
            }
        }
    }
    const f = try field.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, f);
    try arr.append(ctx.allocator, .{ .string = f });

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

    const strict = args.len >= 2 and args[1] == .bool and args[1].bool;

    var buf = std.ArrayListUnmanaged(u8){};
    var accum: u24 = 0;
    var bits: u5 = 0;
    var pad_count: usize = 0;
    for (s) |c| {
        if (c == '=') {
            pad_count += 1;
            continue;
        }
        if (pad_count > 0 and strict) {
            buf.deinit(ctx.allocator);
            return .{ .bool = false };
        }
        if (c == ' ' or c == '\n' or c == '\r' or c == '\t') {
            // PHP allows whitespace in both strict and non-strict modes
            continue;
        }
        const val = base64Decode(c) orelse {
            if (strict) {
                buf.deinit(ctx.allocator);
                return .{ .bool = false };
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
    const raw_output = args.len >= 2 and args[1].isTruthy();
    var hash: [16]u8 = undefined;
    std.crypto.hash.Md5.hash(s, &hash, .{});
    if (raw_output) return .{ .string = try ctx.createString(&hash) };
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
    const raw_output = args.len >= 2 and args[1].isTruthy();
    var hash: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(s, &hash, .{});
    if (raw_output) return .{ .string = try ctx.createString(&hash) };
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
    if (needle.len == 0) return .{ .bool = false };
    const hlen: i64 = @intCast(haystack.len);
    const raw_off: i64 = if (args.len >= 3) Value.toInt(args[2]) else 0;
    const off_i: i64 = if (raw_off < 0) @max(0, hlen + raw_off) else raw_off;
    if (off_i > hlen) return .{ .bool = false };
    const offset: usize = @intCast(off_i);
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
    return strrposImpl(haystack, needle, args);
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

fn native_strripos(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .bool = false };
    const haystack = if (args[0] == .string) args[0].string else return Value{ .bool = false };
    const needle = if (args[1] == .string) args[1].string else return Value{ .bool = false };
    if (needle.len == 0 or haystack.len == 0) return .{ .bool = false };
    const h_lower = try toLowerBuf(ctx.allocator, haystack);
    defer ctx.allocator.free(h_lower);
    const n_lower = try toLowerBuf(ctx.allocator, needle);
    defer ctx.allocator.free(n_lower);
    return strrposImpl(h_lower, n_lower, args);
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
    return .{ .string = try mbCaseFirst(ctx, s, true) };
}

fn native_mb_lcfirst(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const s = if (args[0] == .string) args[0].string else return Value{ .string = "" };
    return .{ .string = try mbCaseFirst(ctx, s, false) };
}

fn mbCaseFirst(ctx: *NativeContext, s: []const u8, to_upper: bool) ![]const u8 {
    if (s.len == 0) return "";
    const first_len = std.unicode.utf8ByteSequenceLength(s[0]) catch 1;
    if (first_len > s.len) {
        const buf = try ctx.allocator.alloc(u8, s.len);
        @memcpy(buf, s);
        try ctx.strings.append(ctx.allocator, buf);
        return buf;
    }
    if (first_len == 1) {
        const buf = try ctx.allocator.alloc(u8, s.len);
        @memcpy(buf, s);
        buf[0] = if (to_upper) std.ascii.toUpper(s[0]) else std.ascii.toLower(s[0]);
        try ctx.strings.append(ctx.allocator, buf);
        return buf;
    }
    const cp = std.unicode.utf8Decode(s[0..first_len]) catch {
        const buf = try ctx.allocator.alloc(u8, s.len);
        @memcpy(buf, s);
        try ctx.strings.append(ctx.allocator, buf);
        return buf;
    };
    const new_cp = if (to_upper) unicodeToUpper(cp) else unicodeToLower(cp);
    var enc: [4]u8 = undefined;
    const enc_len = std.unicode.utf8Encode(new_cp, &enc) catch first_len;
    const total = (s.len - first_len) + enc_len;
    const buf = try ctx.allocator.alloc(u8, total);
    @memcpy(buf[0..enc_len], enc[0..enc_len]);
    @memcpy(buf[enc_len..], s[first_len..]);
    try ctx.strings.append(ctx.allocator, buf);
    return buf;
}

fn native_strip_tags(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .string = "" };
    const s = args[0].string;

    var allowed_tags_buf: [64][64]u8 = undefined;
    var allowed_tags_lens: [64]usize = undefined;
    var n_allowed: usize = 0;
    if (args.len >= 2) {
        if (args[1] == .string) {
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
        } else if (args[1] == .array) {
            for (args[1].array.entries.items) |e| {
                if (e.value != .string or n_allowed >= 64) continue;
                const tag = e.value.string;
                var tlen: usize = 0;
                for (tag) |c| {
                    if (tlen < 64) {
                        allowed_tags_buf[n_allowed][tlen] = toLowerAscii(c);
                        tlen += 1;
                    }
                }
                allowed_tags_lens[n_allowed] = tlen;
                n_allowed += 1;
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
    const prefix_str: []const u8 = if (args.len >= 2 and args[1] == .string) args[1].string else "";
    // arg_separator default "&"
    const arg_sep: []const u8 = if (args.len >= 3 and args[2] == .string and args[2].string.len > 0) args[2].string else "&";
    // encoding: PHP_QUERY_RFC1738 = 1 (default, space → +), PHP_QUERY_RFC3986 = 2 (space → %20)
    const enc_type: i64 = if (args.len >= 4) Value.toInt(args[3]) else 1;
    const rfc3986 = enc_type == 2;

    var buf = std.ArrayListUnmanaged(u8){};
    var first = true;
    for (arr.entries.items) |entry| {
        var key_buf: [32]u8 = undefined;
        const key_str: []const u8 = switch (entry.key) {
            .string => |s| s,
            .int => |n| blk: {
                // top-level integer key: prepend numeric prefix
                if (prefix_str.len > 0) {
                    const composed = std.fmt.bufPrint(&key_buf, "{s}{d}", .{ prefix_str, n }) catch "";
                    break :blk composed;
                }
                break :blk std.fmt.bufPrint(&key_buf, "{d}", .{n}) catch "";
            },
        };
        try buildQueryPairs(&buf, ctx.allocator, key_str, entry.value, &first, arg_sep, rfc3986);
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn buildQueryPairs(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, prefix: []const u8, value: Value, first: *bool, sep: []const u8, rfc3986: bool) !void {
    // PHP omits keys with null values
    if (value == .null) return;
    if (value == .array) {
        for (value.array.entries.items) |entry| {
            var key_buf: [32]u8 = undefined;
            const sub_key = switch (entry.key) {
                .string => |s| s,
                .int => |n| std.fmt.bufPrint(&key_buf, "{d}", .{n}) catch "",
            };
            var nested_key = std.ArrayListUnmanaged(u8){};
            defer nested_key.deinit(a);
            try nested_key.appendSlice(a, prefix);
            try nested_key.appendSlice(a, "[");
            try nested_key.appendSlice(a, sub_key);
            try nested_key.appendSlice(a, "]");
            try buildQueryPairs(buf, a, nested_key.items, entry.value, first, sep, rfc3986);
        }
    } else {
        if (!first.*) try buf.appendSlice(a, sep);
        first.* = false;
        try appendUrlEncodedMode(buf, a, prefix, rfc3986);
        try buf.append(a, '=');
        switch (value) {
            .string => |s| try appendUrlEncodedMode(buf, a, s, rfc3986),
            .bool => |b| try buf.append(a, if (b) '1' else '0'),
            else => {
                var tmp = std.ArrayListUnmanaged(u8){};
                try value.format(&tmp, a);
                const s = try tmp.toOwnedSlice(a);
                defer a.free(s);
                try appendUrlEncodedMode(buf, a, s, rfc3986);
            },
        }
    }
}

fn appendUrlEncoded(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, s: []const u8) !void {
    try appendUrlEncodedMode(buf, a, s, false);
}

fn appendUrlEncodedMode(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, s: []const u8, rfc3986: bool) !void {
    for (s) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
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

        if (std.mem.lastIndexOf(u8, authority, "@")) |pos| {
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

    // PHP rejects URLs whose authority section (after //) is invalid:
    //   - no host but port or userinfo present ("http://:80", "http://user@:80")
    //   - empty host with any non-file scheme ("http:///", "ftp:///")
    //   - file:// is the one exception that allows an empty host
    if (has_authority) {
        const host_empty = if (host) |h| h.len == 0 else true;
        if (host_empty) {
            if (port != null or user != null or pass != null) return Value{ .bool = false };
            const is_file_scheme = if (scheme) |s| std.ascii.eqlIgnoreCase(s, "file") else false;
            if (scheme != null and !is_file_scheme) return Value{ .bool = false };
        }
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
        const decoded_val = try urlDecodeSlice(ctx, val);
        try insertParsedKey(ctx, arr, decoded_key, .{ .string = decoded_val });
    }
    if (args.len >= 2) {
        ctx.setCallerVar(1, args.len, .{ .array = arr });
    }
    return .null;
}

// PHP coerces invalid PHP-variable chars in the base part of parse_str keys
// (the bit before the first '[') to underscores: space, '.', '['. The chars
// inside brackets are kept as-is.
fn sanitizeParseStrKey(ctx: *NativeContext, name: []const u8) ![]const u8 {
    var needs_fix = false;
    for (name) |c| {
        if (c == ' ' or c == '.' or c == '[') { needs_fix = true; break; }
    }
    if (!needs_fix) return name;
    const buf = try ctx.allocator.alloc(u8, name.len);
    for (name, 0..) |c, i| {
        buf[i] = if (c == ' ' or c == '.' or c == '[') '_' else c;
    }
    try ctx.strings.append(ctx.allocator, buf);
    return buf;
}

fn insertParsedKey(ctx: *NativeContext, root: *PhpArray, key: []const u8, value: Value) !void {
    // split "a[b][c]" -> base="a", segs=["b","c"]. an empty segment "[]" means append.
    const open = std.mem.indexOfScalar(u8, key, '[');
    const raw_base = if (open) |o| key[0..o] else key;
    const base_name = try sanitizeParseStrKey(ctx, raw_base);
    if (open == null) {
        try root.set(ctx.allocator, .{ .string = base_name }, value);
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
            const new_a = try ctx.allocator.create(PhpArray);
            new_a.* = .{};
            try ctx.vm.arrays.append(ctx.allocator, new_a);
            try current_arr.set(ctx.allocator, current_key, .{ .array = new_a });
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
                current_key = .{ .string = seg };
            }
        }
    }
    try current_arr.set(ctx.allocator, current_key, value);
}

fn native_addcslashes(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return if (args.len >= 1) args[0] else Value.null;
    const s = args[0].string;
    const charset = args[1].string;
    // expand "a..z" ranges
    var mask = [_]bool{false} ** 256;
    var i: usize = 0;
    while (i < charset.len) : (i += 1) {
        if (i + 3 < charset.len and charset[i + 1] == '.' and charset[i + 2] == '.') {
            const lo = charset[i];
            const hi = charset[i + 3];
            if (lo <= hi) {
                var c: u16 = lo;
                while (c <= hi) : (c += 1) mask[c] = true;
                i += 3;
                continue;
            }
        }
        mask[charset[i]] = true;
    }
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(ctx.allocator);
    for (s) |c| {
        if (mask[c]) {
            // PHP uses readable single-char escapes for common control chars
            const named: ?u8 = switch (c) {
                '\n' => 'n',
                '\t' => 't',
                '\r' => 'r',
                7 => 'a',
                8 => 'b',
                12 => 'f',
                11 => 'v',
                else => null,
            };
            if (named) |ch| {
                try buf.append(ctx.allocator, '\\');
                try buf.append(ctx.allocator, ch);
            } else if (c < 32 or c >= 127) {
                var tmp: [4]u8 = undefined;
                const oct = std.fmt.bufPrint(&tmp, "\\{o:0>3}", .{c}) catch continue;
                try buf.appendSlice(ctx.allocator, oct);
            } else {
                try buf.append(ctx.allocator, '\\');
                try buf.append(ctx.allocator, c);
            }
        } else {
            try buf.append(ctx.allocator, c);
        }
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn native_stripcslashes(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .null;
    const s = args[0].string;
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(ctx.allocator);
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] != '\\' or i + 1 >= s.len) {
            try buf.append(ctx.allocator, s[i]);
            continue;
        }
        const next = s[i + 1];
        const c: u8 = switch (next) {
            'n' => '\n',
            't' => '\t',
            'r' => '\r',
            'a' => 7,
            'b' => 8,
            'f' => 12,
            'v' => 11,
            '0'...'9' => blk: {
                var end = i + 1;
                var v: u16 = 0;
                while (end < s.len and end - i < 4 and s[end] >= '0' and s[end] <= '7') : (end += 1) {
                    v = v * 8 + (s[end] - '0');
                }
                i = end - 1;
                break :blk @intCast(v & 0xff);
            },
            'x' => blk: {
                var end = i + 2;
                var v: u16 = 0;
                while (end < s.len and end - (i + 2) < 2) : (end += 1) {
                    const ch = s[end];
                    const d: u8 = if (ch >= '0' and ch <= '9') ch - '0'
                        else if (ch >= 'a' and ch <= 'f') ch - 'a' + 10
                        else if (ch >= 'A' and ch <= 'F') ch - 'A' + 10
                        else break;
                    v = v * 16 + d;
                }
                if (end == i + 2) {
                    try buf.append(ctx.allocator, '\\');
                    try buf.append(ctx.allocator, 'x');
                    continue;
                }
                i = end - 1;
                break :blk @intCast(v & 0xff);
            },
            else => next,
        };
        try buf.append(ctx.allocator, c);
        if (next != '0' and next < '0' or next > '9') {
            if (next != 'x') i += 1;
        }
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn native_strrchr(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const haystack = args[0].string;
    const needle = args[1].string;
    if (needle.len == 0) return .{ .bool = false };
    const c = needle[0];
    if (std.mem.lastIndexOfScalar(u8, haystack, c)) |pos| {
        const before = args.len >= 3 and args[2].isTruthy();
        if (before) return .{ .string = try ctx.createString(haystack[0..pos]) };
        return .{ .string = try ctx.createString(haystack[pos..]) };
    }
    return .{ .bool = false };
}

fn native_strstr(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return Value{ .bool = false };
    const haystack = if (args[0] == .string) args[0].string else return Value{ .bool = false };
    const needle = if (args[1] == .string) args[1].string else return Value{ .bool = false };
    if (needle.len == 0) return Value{ .bool = false };

    const before_needle: bool = args.len >= 3 and args[2].isTruthy();

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

fn native_vprintf(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .int = 0 };
    const fmt_str = if (args[0] == .string) args[0].string else return Value{ .int = 0 };
    if (args[1] != .array) return .{ .int = 0 };
    const arr = args[1].array;
    var vals = try ctx.allocator.alloc(Value, arr.entries.items.len);
    defer ctx.allocator.free(vals);
    for (arr.entries.items, 0..) |entry, i| vals[i] = entry.value;
    const result = try sprintfImpl(ctx, fmt_str, vals);
    try ctx.vm.output.appendSlice(ctx.allocator, result);
    return .{ .int = @intCast(result.len) };
}

fn native_fscanf(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .object) return .null;
    // read one line via fgets
    const line = try ctx.vm.callByName("fgets", &.{args[0]});
    if (line == .bool and !line.bool) return .{ .bool = false };
    if (line != .string) return .null;
    // delegate to sscanf with the line as input
    var sscanf_args = std.ArrayListUnmanaged(Value){};
    defer sscanf_args.deinit(ctx.allocator);
    try sscanf_args.append(ctx.allocator, line);
    for (args[1..]) |a| try sscanf_args.append(ctx.allocator, a);
    return native_sscanf(ctx, sscanf_args.items);
}

fn native_sscanf(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .null;
    const input = args[0].string;
    const fmt = args[1].string;

    var captures = std.ArrayListUnmanaged(Value){};
    defer captures.deinit(ctx.allocator);
    var ip: usize = 0;
    var fp: usize = 0;
    while (fp < fmt.len) {
        const c = fmt[fp];
        if (c == ' ' or c == '\t' or c == '\n') {
            // whitespace in format matches any whitespace
            fp += 1;
            while (ip < input.len and (input[ip] == ' ' or input[ip] == '\t' or input[ip] == '\n')) ip += 1;
            continue;
        }
        if (c != '%') {
            if (ip >= input.len or input[ip] != c) break;
            fp += 1;
            ip += 1;
            continue;
        }
        // % spec
        fp += 1;
        if (fp >= fmt.len) break;
        // skip optional width
        var width: usize = 0;
        var has_width = false;
        while (fp < fmt.len and fmt[fp] >= '0' and fmt[fp] <= '9') {
            width = width * 10 + (fmt[fp] - '0');
            has_width = true;
            fp += 1;
        }
        if (fp >= fmt.len) break;
        const spec = fmt[fp];
        fp += 1;
        // %c, %% and %[ do not skip leading whitespace; everything else does
        if (spec != 'c' and spec != '%' and spec != '[') {
            while (ip < input.len and (input[ip] == ' ' or input[ip] == '\t' or input[ip] == '\n')) ip += 1;
        }
        switch (spec) {
            'd', 'i' => {
                const start = ip;
                if (ip < input.len and (input[ip] == '+' or input[ip] == '-')) ip += 1;
                while (ip < input.len and input[ip] >= '0' and input[ip] <= '9') {
                    if (has_width and ip - start >= width) break;
                    ip += 1;
                }
                if (ip == start or (ip == start + 1 and (input[start] == '+' or input[start] == '-'))) {
                    try captures.append(ctx.allocator, .null);
                    continue;
                }
                const v = std.fmt.parseInt(i64, input[start..ip], 10) catch 0;
                try captures.append(ctx.allocator, .{ .int = v });
            },
            'f', 'e', 'g' => {
                const start = ip;
                if (ip < input.len and (input[ip] == '+' or input[ip] == '-')) ip += 1;
                while (ip < input.len and ((input[ip] >= '0' and input[ip] <= '9') or input[ip] == '.' or input[ip] == 'e' or input[ip] == 'E' or input[ip] == '+' or input[ip] == '-')) {
                    if (has_width and ip - start >= width) break;
                    ip += 1;
                }
                const v = std.fmt.parseFloat(f64, input[start..ip]) catch 0;
                try captures.append(ctx.allocator, .{ .float = v });
            },
            's' => {
                const start = ip;
                while (ip < input.len and input[ip] != ' ' and input[ip] != '\t' and input[ip] != '\n') {
                    if (has_width and ip - start >= width) break;
                    ip += 1;
                }
                const s = try ctx.allocator.dupe(u8, input[start..ip]);
                try ctx.strings.append(ctx.allocator, s);
                try captures.append(ctx.allocator, .{ .string = s });
            },
            'c' => {
                const want: usize = if (has_width) width else 1;
                const end = @min(ip + want, input.len);
                const s = try ctx.allocator.dupe(u8, input[ip..end]);
                try ctx.strings.append(ctx.allocator, s);
                ip = end;
                try captures.append(ctx.allocator, .{ .string = s });
            },
            'x', 'X' => {
                // optional 0x / 0X prefix
                if (ip + 1 < input.len and input[ip] == '0' and (input[ip + 1] == 'x' or input[ip + 1] == 'X')) ip += 2;
                const start = ip;
                while (ip < input.len and std.ascii.isHex(input[ip])) {
                    if (has_width and ip - start >= width) break;
                    ip += 1;
                }
                const v = std.fmt.parseInt(i64, input[start..ip], 16) catch 0;
                try captures.append(ctx.allocator, .{ .int = v });
            },
            'o' => {
                const start = ip;
                while (ip < input.len and input[ip] >= '0' and input[ip] <= '7') {
                    if (has_width and ip - start >= width) break;
                    ip += 1;
                }
                const v = std.fmt.parseInt(i64, input[start..ip], 8) catch 0;
                try captures.append(ctx.allocator, .{ .int = v });
            },
            '%' => {
                if (ip < input.len and input[ip] == '%') ip += 1;
            },
            '[' => {
                // %[...] character class. supports leading ^ for negation and
                // a-b ranges. terminated by literal ]; a leading ] is part of
                // the set per traditional sscanf rules.
                var negate = false;
                if (fp < fmt.len and fmt[fp] == '^') {
                    negate = true;
                    fp += 1;
                }
                var class_set: [256]bool = .{false} ** 256;
                var first = true;
                while (fp < fmt.len) {
                    const cc = fmt[fp];
                    if (cc == ']' and !first) break;
                    first = false;
                    if (fp + 2 < fmt.len and fmt[fp + 1] == '-' and fmt[fp + 2] != ']') {
                        const lo = cc;
                        const hi = fmt[fp + 2];
                        var x: usize = lo;
                        while (x <= hi) : (x += 1) class_set[x] = true;
                        fp += 3;
                    } else {
                        class_set[cc] = true;
                        fp += 1;
                    }
                }
                if (fp < fmt.len) fp += 1; // skip ]
                const start = ip;
                while (ip < input.len) {
                    const matches = class_set[input[ip]];
                    if (negate == matches) break;
                    if (has_width and ip - start >= width) break;
                    ip += 1;
                }
                if (ip == start) {
                    try captures.append(ctx.allocator, .null);
                    continue;
                }
                const s = try ctx.allocator.dupe(u8, input[start..ip]);
                try ctx.strings.append(ctx.allocator, s);
                try captures.append(ctx.allocator, .{ .string = s });
            },
            else => {},
        }
    }

    // if optional output args provided, write to them and return count
    if (args.len > 2) {
        var written: i64 = 0;
        for (captures.items, 0..) |v, i| {
            if (2 + i >= args.len) break;
            ctx.setCallerVar(2 + i, args.len, v);
            written += 1;
        }
        return .{ .int = written };
    }

    var arr = try ctx.createArray();
    for (captures.items) |v| try arr.append(ctx.allocator, v);
    return .{ .array = arr };
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
    if (input.len == 0) return .{ .string = "0000" };

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
