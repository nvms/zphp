const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const RuntimeError = error{ RuntimeError, OutOfMemory };

// coerce to string with __toString support. preg functions previously
// bailed on Stringable objects (passing a Symfony Path-like wrapper or a
// custom regex builder to preg_match returned false silently)
// pcre checks a utf subject from the start offset to the end on every match,
// so matching a long subject at many offsets costs quadratic time. as php
// does, a subject known to be valid utf-8 skips the check: it is validated
// once, and a string that owns its bytes remembers the result
const UtfCheck = struct {
    valid: bool,
    subject: []const u8,
    utf: bool = false,

    fn init(code: *pcre2.Code, subject: []const u8, holder: ?Value) UtfCheck {
        var all: u32 = 0;
        _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_ALLOPTIONS, @ptrCast(&all));
        if (all & pcre2.UTF == 0) return .{ .valid = false, .subject = subject };
        if (initUtf(subject, holder)) return .{ .valid = true, .subject = subject, .utf = true };
        return .{ .valid = false, .subject = subject, .utf = true };
    }

    fn initUtf(subject: []const u8, holder: ?Value) bool {
        const owner: ?*Value.String.Owner = if (holder) |h| switch (h) {
            .string => |str| if (str.owner) |o| (if (!o.closure and str.ptr == o.bytes.ptr and str.len == o.bytes.len) o else null) else null,
            else => null,
        } else null;
        if (owner) |o| if (o.utf8_valid) return true;
        const valid = std.unicode.utf8ValidateSlice(subject);
        if (valid) if (owner) |o| {
            o.utf8_valid = true;
        };
        return valid;
    }

    // how far past an empty match the next attempt starts: one character
    fn step(self: UtfCheck, at: usize) usize {
        if (!self.utf or at >= self.subject.len) return 1;
        const len = utf8SeqLen(self.subject[at]);
        return if (at + len > self.subject.len) 1 else len;
    }

    // the check may be skipped only from the start of a code point
    fn options(self: UtfCheck, offset: usize) u32 {
        if (!self.valid) return 0;
        if (offset < self.subject.len and self.subject[offset] & 0xc0 == 0x80) return 0;
        return pcre2.NO_UTF_CHECK;
    }
};

// the match context carrying pcre.backtrack_limit and pcre.recursion_limit,
// one per thread, updated when the settings change
threadlocal var match_context: ?*anyopaque = null;
threadlocal var match_context_limits: [2]u32 = .{ 0, 0 };

fn matchContext(ctx: *NativeContext) ?*anyopaque {
    const limits = [2]u32{ iniLimit(ctx, "pcre.backtrack_limit", 1000000), iniLimit(ctx, "pcre.recursion_limit", 100000) };
    if (match_context == null) {
        match_context = pcre2.pcre2_match_context_create_8(null);
        // php's PCRE_JIT_STACK_MIN_SIZE and PCRE_JIT_STACK_MAX_SIZE
        if (match_context) |mc| if (pcre2.pcre2_jit_stack_create_8(32 * 1024, 192 * 1024, null)) |stack|
            pcre2.pcre2_jit_stack_assign_8(mc, null, stack);
    }
    const mc = match_context orelse return null;
    if (!std.mem.eql(u32, &limits, &match_context_limits)) {
        _ = pcre2.pcre2_set_match_limit_8(mc, limits[0]);
        _ = pcre2.pcre2_set_depth_limit_8(mc, limits[1]);
        match_context_limits = limits;
    }
    return mc;
}

fn iniLimit(ctx: *NativeContext, name: []const u8, default: u32) u32 {
    const text = ctx.vm.ini_settings.get(name) orelse return default;
    const value = std.fmt.parseInt(i64, std.mem.trim(u8, text, " "), 10) catch return default;
    return std.math.cast(u32, @max(value, 0)) orelse std.math.maxInt(u32);
}

fn exec(ctx: *NativeContext, code: *pcre2.Code, subject: []const u8, offset: usize, options: u32, match_data: *pcre2.MatchData) c_int {
    // an empty slice's pointer can be anything, and jit code reads through it
    const bytes: [*]const u8 = if (subject.len == 0) "" else subject.ptr;
    return pcre2.pcre2_match_8(code, bytes, subject.len, offset, options, match_data, matchContext(ctx));
}

// a match that failed for a reason other than finding nothing, recorded for
// preg_last_error as php_pcre's pcre_handle_exec_error records it
fn execFailed(rc: c_int) bool {
    if (rc >= 0 or rc == pcre2.ERROR_NOMATCH) return false;
    setPregError(switch (rc) {
        pcre2.ERROR_MATCHLIMIT => 2,
        pcre2.ERROR_DEPTHLIMIT => 3,
        pcre2.ERROR_UTF8_ERR21...pcre2.ERROR_UTF8_ERR1 => 4,
        pcre2.ERROR_BADUTFOFFSET => 5,
        pcre2.ERROR_JIT_STACKLIMIT => 6,
        else => 1,
    });
    return true;
}

fn coerceStrArg(ctx: *NativeContext, v: Value) ?[]const u8 {
    return switch (v) {
        .string => |s| s.bytes(),
        .object => |o| blk: {
            if (!ctx.vm.hasMethod(o.class_name, "__toString")) break :blk null;
            const r = ctx.vm.callMethod(o, "__toString", &.{}) catch break :blk null;
            if (r == .string) break :blk r.string.bytes();
            break :blk null;
        },
        else => null,
    };
}

const pcre2 = struct {
    const Code = opaque {};
    const MatchData = opaque {};

    const CASELESS: u32 = 0x00000008;
    const MULTILINE: u32 = 0x00000400;
    const DOTALL: u32 = 0x00000020;
    const EXTENDED: u32 = 0x00000080;
    const UTF: u32 = 0x00080000;
    const JIT_COMPLETE: u32 = 0x00000001;
    const NO_UTF_CHECK: u32 = 0x40000000;
    const INFO_ALLOPTIONS: u32 = 0;
    const UCP: u32 = 0x00020000;
    const ANCHORED: u32 = 0x80000000;
    const UNGREEDY: u32 = 0x00040000;
    const DOLLAR_ENDONLY: u32 = 0x00000010;
    const DUPNAMES: u32 = 0x00000040;
    const NO_AUTO_CAPTURE: u32 = 0x00002000;

    const SUBSTITUTE_GLOBAL: u32 = 0x00000100;
    const SUBSTITUTE_OVERFLOW_LENGTH: u32 = 0x00001000;

    const INFO_CAPTURECOUNT: u32 = 4;
    const INFO_NAMECOUNT: u32 = 17;
    const INFO_NAMEENTRYSIZE: u32 = 18;
    const INFO_NAMETABLE: u32 = 19;
    const ERROR_NOMEMORY: c_int = -48;
    const ERROR_NOMATCH: c_int = -1;
    const ERROR_UTF8_ERR1: c_int = -3;
    const ERROR_UTF8_ERR21: c_int = -23;
    const ERROR_BADUTFOFFSET: c_int = -36;
    const ERROR_JIT_STACKLIMIT: c_int = -46;
    const ERROR_MATCHLIMIT: c_int = -47;
    const ERROR_DEPTHLIMIT: c_int = -53;
    const UNSET: usize = std.math.maxInt(usize);

    extern "c" fn pcre2_compile_8(
        pattern: [*]const u8,
        length: usize,
        options: u32,
        errorcode: *c_int,
        erroroffset: *usize,
        ccontext: ?*anyopaque,
    ) callconv(.c) ?*Code;

    extern "c" fn pcre2_code_free_8(code: ?*Code) callconv(.c) void;

    extern "c" fn pcre2_get_error_message_8(
        errorcode: c_int,
        buffer: [*]u8,
        bufflen: usize,
    ) callconv(.c) c_int;

    extern "c" fn pcre2_match_data_create_from_pattern_8(
        code: *const Code,
        gcontext: ?*anyopaque,
    ) callconv(.c) ?*MatchData;

    extern "c" fn pcre2_match_data_free_8(match_data: ?*MatchData) callconv(.c) void;

    extern "c" fn pcre2_match_context_create_8(gcontext: ?*anyopaque) callconv(.c) ?*anyopaque;
    extern "c" fn pcre2_jit_compile_8(code: *Code, options: u32) callconv(.c) c_int;
    extern "c" fn pcre2_jit_stack_create_8(startsize: usize, maxsize: usize, gcontext: ?*anyopaque) callconv(.c) ?*anyopaque;
    extern "c" fn pcre2_jit_stack_assign_8(mcontext: *anyopaque, callback: ?*anyopaque, data: ?*anyopaque) callconv(.c) void;
    extern "c" fn pcre2_set_match_limit_8(mcontext: *anyopaque, value: u32) callconv(.c) c_int;
    extern "c" fn pcre2_set_depth_limit_8(mcontext: *anyopaque, value: u32) callconv(.c) c_int;

    extern "c" fn pcre2_match_8(
        code: *const Code,
        subject: [*]const u8,
        length: usize,
        startoffset: usize,
        options: u32,
        match_data: *MatchData,
        mcontext: ?*anyopaque,
    ) callconv(.c) c_int;

    extern "c" fn pcre2_get_ovector_pointer_8(
        match_data: *MatchData,
    ) callconv(.c) [*]usize;

    extern "c" fn pcre2_pattern_info_8(
        code: *const Code,
        what: u32,
        where: *anyopaque,
    ) callconv(.c) c_int;

    extern "c" fn pcre2_get_mark_8(
        match_data: *MatchData,
    ) callconv(.c) ?[*:0]const u8;

    extern "c" fn pcre2_substitute_8(
        code: *const Code,
        subject: [*]const u8,
        length: usize,
        startoffset: usize,
        options: u32,
        match_data: ?*MatchData,
        mcontext: ?*anyopaque,
        replacement: [*]const u8,
        rlength: usize,
        outputbuffer: ?[*]u8,
        outlengthptr: *usize,
    ) callconv(.c) c_int;

    extern "c" fn pcre2_config_8(what: u32, where_: ?*anyopaque) callconv(.c) c_int;
    const CONFIG_VERSION: u32 = 11;
};

// the linked libpcre2 version string, e.g. "10.42 2022-12-11". php exposes this
// as the PCRE_VERSION constant; vendor polyfills (symfony/polyfill-intl-grapheme)
// gate behaviour on `(float) PCRE_VERSION`, so it must be defined and accurate.
// written into a process-lifetime static buffer so the constant slice stays
// valid without a heap allocation the constants map would leak
var version_buf: [64]u8 = undefined;
pub fn libVersion() []const u8 {
    const n = pcre2.pcre2_config_8(pcre2.CONFIG_VERSION, &version_buf);
    if (n <= 1 or @as(usize, @intCast(n)) > version_buf.len) return "";
    return version_buf[0..@intCast(n - 1)]; // n includes the trailing nul
}

pub const entries = .{
    .{ "preg_match", preg_match },
    .{ "preg_match_all", preg_match_all },
    .{ "preg_replace", preg_replace },
    .{ "preg_filter", preg_filter },
    .{ "preg_replace_callback", preg_replace_callback },
    .{ "preg_replace_callback_array", preg_replace_callback_array },
    .{ "preg_split", preg_split },
    .{ "preg_quote", preg_quote },
    .{ "preg_grep", preg_grep },
    .{ "preg_last_error", preg_last_error },
    .{ "preg_last_error_msg", preg_last_error_msg },
    .{ "mb_split", mb_split },
    .{ "mb_ereg_match", mb_ereg_match },
};

const PatternInfo = struct {
    pattern: []const u8,
    flags: u32,
};

fn parsePattern(raw_in: []const u8) ?PatternInfo {
    // PHP skips leading whitespace before reading the delimiter, so an
    // indented multi-line regex literal (e.g. Symfony's HeaderUtils::split)
    // still parses with its real delimiter
    var ws: usize = 0;
    while (ws < raw_in.len and std.ascii.isWhitespace(raw_in[ws])) ws += 1;
    const raw = raw_in[ws..];
    if (raw.len < 2) return null;
    const delim = raw[0];
    if (delim == '\\' or std.ascii.isAlphanumeric(delim)) return null;

    const close_delim: u8 = switch (delim) {
        '(' => ')',
        '{' => '}',
        '[' => ']',
        '<' => '>',
        else => delim,
    };

    var end = raw.len - 1;
    while (end > 0 and raw[end] != close_delim) end -= 1;
    if (end == 0) return null;

    const pattern = raw[1..end];
    const modifiers = raw[end + 1 ..];

    var flags: u32 = 0;
    for (modifiers) |m| {
        switch (m) {
            'i' => flags |= pcre2.CASELESS,
            'm' => flags |= pcre2.MULTILINE,
            's' => flags |= pcre2.DOTALL,
            'x' => flags |= pcre2.EXTENDED,
            'u' => flags |= pcre2.UTF | pcre2.UCP,
            'A' => flags |= pcre2.ANCHORED,
            'U' => flags |= pcre2.UNGREEDY,
            'D' => flags |= pcre2.DOLLAR_ENDONLY,
            'J' => flags |= pcre2.DUPNAMES,
            'n' => flags |= pcre2.NO_AUTO_CAPTURE,
            // 'S' (study) and 'X' (PCRE_EXTRA) are accepted by PHP but have no
            // PCRE2 equivalent - treat as no-ops rather than rejecting
            'S', 'X' => {},
            // 'e' was removed in PHP 7; any other letter is an unknown
            // modifier. PHP fails the whole call and returns false/null
            else => return null,
        }
    }
    return .{ .pattern = pattern, .flags = flags };
}

// PCRE2 10.43+ (what modern PHP bundles) recognizes {,n} as the quantifier
// {0,n}; older system libpcre2 (ubuntu 24.04 ships 10.42) treats it as a
// literal. rewrite {,n} to {0,n} - identical semantics on every pcre2
// version - so zphp matches PHP regardless of which libpcre2 it links.
// skips escaped braces, character classes, and \Q...\E quoted runs.
// returns null when no rewrite is needed (the common case, no allocation)
fn normalizeOpenBoundQuantifier(pattern: []const u8) ?[]u8 {
    var out: ?std.ArrayListUnmanaged(u8) = null;
    var copied: usize = 0;
    var in_class = false;
    var in_quote = false;
    var i: usize = 0;
    while (i < pattern.len) : (i += 1) {
        const c = pattern[i];
        if (in_quote) {
            if (c == '\\' and i + 1 < pattern.len and pattern[i + 1] == 'E') {
                in_quote = false;
                i += 1;
            }
            continue;
        }
        if (c == '\\') {
            if (i + 1 < pattern.len and pattern[i + 1] == 'Q') in_quote = true;
            i += 1;
            continue;
        }
        if (in_class) {
            if (c == ']') in_class = false;
            continue;
        }
        if (c == '[') {
            in_class = true;
            // a ] right after [ or [^ is a literal member, not the closer
            var j = i + 1;
            if (j < pattern.len and pattern[j] == '^') j += 1;
            if (j < pattern.len and pattern[j] == ']') i = j;
            continue;
        }
        if (c == '{' and i + 2 < pattern.len and pattern[i + 1] == ',' and std.ascii.isDigit(pattern[i + 2])) {
            var j = i + 3;
            while (j < pattern.len and std.ascii.isDigit(pattern[j])) j += 1;
            if (j < pattern.len and pattern[j] == '}') {
                if (out == null) out = .empty;
                out.?.appendSlice(std.heap.c_allocator, pattern[copied .. i + 1]) catch return null;
                out.?.append(std.heap.c_allocator, '0') catch return null;
                copied = i + 1;
                i = j - 1;
            }
        }
    }
    if (out) |*o| {
        o.appendSlice(std.heap.c_allocator, pattern[copied..]) catch return null;
        return o.toOwnedSlice(std.heap.c_allocator) catch return null;
    }
    return null;
}

// compiled patterns are kept per thread, as php keeps its pcre cache, up to
// php's PCRE_CACHE_SIZE entries. past that a pattern is compiled for its call
// and freed after it: a cached code is never freed while a call (or a
// callback it runs) could be using it
const cache_size = 4096;
threadlocal var pattern_cache: std.StringHashMapUnmanaged(*pcre2.Code) = .empty;

const Compiled = struct {
    code: *pcre2.Code,
    owned: bool,

    fn release(self: Compiled) void {
        if (self.owned) pcre2.pcre2_code_free_8(self.code);
    }
};

fn compilePattern(ctx: *NativeContext, pattern: []const u8, flags: u32) ?Compiled {
    var key_buf: [256]u8 = undefined;
    const key_len = pattern.len + 4;
    const key: ?[]u8 = if (key_len <= key_buf.len) key_buf[0..key_len] else null;
    if (key) |k| {
        std.mem.writeInt(u32, k[0..4], flags, .little);
        @memcpy(k[4..], pattern);
        if (pattern_cache.get(k)) |code| return .{ .code = code, .owned = false };
    }
    const code = compileUncached(pattern, flags) orelse return null;
    // as php does with pcre.jit on; a pattern the jit can't take still
    // matches through the interpreter
    if (iniLimit(ctx, "pcre.jit", 1) != 0) _ = pcre2.pcre2_jit_compile_8(code, pcre2.JIT_COMPLETE);
    if (key) |k| if (pattern_cache.count() < cache_size) {
        const kept = std.heap.c_allocator.dupe(u8, k) catch return .{ .code = code, .owned = true };
        pattern_cache.put(std.heap.c_allocator, kept, code) catch {
            std.heap.c_allocator.free(kept);
            return .{ .code = code, .owned = true };
        };
        return .{ .code = code, .owned = false };
    };
    return .{ .code = code, .owned = true };
}

fn compileUncached(pattern: []const u8, flags: u32) ?*pcre2.Code {
    var err_code: c_int = 0;
    var err_offset: usize = 0;
    if (normalizeOpenBoundQuantifier(pattern)) |buf| {
        defer std.heap.c_allocator.free(buf);
        return pcre2.pcre2_compile_8(buf.ptr, buf.len, flags, &err_code, &err_offset, null);
    }
    return pcre2.pcre2_compile_8(
        pattern.ptr,
        pattern.len,
        flags,
        &err_code,
        &err_offset,
        null,
    );
}

test "normalizeOpenBoundQuantifier" {
    const t = std.testing;
    try t.expectEqual(@as(?[]u8, null), normalizeOpenBoundQuantifier("a{2,4}b"));
    try t.expectEqual(@as(?[]u8, null), normalizeOpenBoundQuantifier("a{,}b"));
    try t.expectEqual(@as(?[]u8, null), normalizeOpenBoundQuantifier("plain"));
    {
        const r = normalizeOpenBoundQuantifier("a{,3}b").?;
        defer std.heap.c_allocator.free(r);
        try t.expectEqualStrings("a{0,3}b", r);
    }
    {
        const r = normalizeOpenBoundQuantifier("a{,3}b{,12}c").?;
        defer std.heap.c_allocator.free(r);
        try t.expectEqualStrings("a{0,3}b{0,12}c", r);
    }
    // escaped brace is a literal, not a quantifier
    try t.expectEqual(@as(?[]u8, null), normalizeOpenBoundQuantifier("a\\{,3}b"));
    // inside a character class braces are literal
    try t.expectEqual(@as(?[]u8, null), normalizeOpenBoundQuantifier("[{,3}]a"));
    try t.expectEqual(@as(?[]u8, null), normalizeOpenBoundQuantifier("[]{,3}]a"));
    try t.expectEqual(@as(?[]u8, null), normalizeOpenBoundQuantifier("[^]{,3}]a"));
    // \Q...\E quotes everything
    try t.expectEqual(@as(?[]u8, null), normalizeOpenBoundQuantifier("\\Qa{,3}\\Eb"));
    {
        const r = normalizeOpenBoundQuantifier("\\Qa{,3}\\Eb{,2}").?;
        defer std.heap.c_allocator.free(r);
        try t.expectEqualStrings("\\Qa{,3}\\Eb{0,2}", r);
    }
    // class followed by a real open-bound quantifier still rewrites
    {
        const r = normalizeOpenBoundQuantifier("[ab]{,3}c").?;
        defer std.heap.c_allocator.free(r);
        try t.expectEqualStrings("[ab]{0,3}c", r);
    }
}

// emit a PHP-format 'preg_<fn>(): Compilation failed: <message> at offset N'
// warning for a pattern that fails to compile. callers should already have
// set preg_last_error to 1 before invoking this
fn emitCompileWarning(ctx: *NativeContext, fn_name: []const u8, pattern: []const u8, flags: u32) RuntimeError!void {
    var err_code: c_int = 0;
    var err_offset: usize = 0;
    const probe = pcre2.pcre2_compile_8(pattern.ptr, pattern.len, flags, &err_code, &err_offset, null);
    if (probe) |p| {
        pcre2.pcre2_code_free_8(p);
        return;
    }
    var msg_buf: [256]u8 = undefined;
    const len = pcre2.pcre2_get_error_message_8(err_code, &msg_buf, msg_buf.len);
    if (len <= 0) return;
    const err_text = msg_buf[0..@intCast(len)];
    const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): Compilation failed: {s} at offset {d}", .{ fn_name, err_text, err_offset });
    defer ctx.allocator.free(msg);
    try ctx.vm.emitWarning(msg);
}

fn preg_match(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.scalar(.{ .bool = false });
    const pat_str = coerceStrArg(ctx, args[0]) orelse return NativeResult.scalar(.{ .bool = false });
    const subj_str = coerceStrArg(ctx, args[1]) orelse return NativeResult.scalar(.{ .bool = false });
    setPregError(0);
    const info = parsePattern(pat_str) orelse {
        setPregError(1);
        return NativeResult.scalar(.{ .bool = false });
    };
    const subject = subj_str;

    const compiled = compilePattern(ctx, info.pattern, info.flags) orelse {
        setPregError(1);
        try emitCompileWarning(ctx, "preg_match", info.pattern, info.flags);
        return NativeResult.scalar(.{ .bool = false });
    };
    defer compiled.release();
    const code = compiled.code;

    const match_data = pcre2.pcre2_match_data_create_from_pattern_8(code, null) orelse return NativeResult.scalar(.{ .bool = false });
    defer pcre2.pcre2_match_data_free_8(match_data);

    const flags: u32 = if (args.len >= 4) @intCast(@max(0, Value.toInt(args[3]))) else 0;
    const offset_capture = (flags & 256) != 0;
    const unmatched_as_null = (flags & 512) != 0;
    const offset: usize = if (args.len >= 5 and args[4] == .int and args[4].int >= 0) @intCast(args[4].int) else 0;
    const utf = UtfCheck.init(code, subject, args[1]);
    const rc = exec(ctx, code, subject, offset, utf.options(offset), match_data);
    if (rc < 0) {
        // no match: $matches must still be set to an empty array so callers
        // can safely iterate without an isset() guard
        if (args.len >= 3) ctx.setCallerVar(2, args.len, .{ .array = try ctx.createArray() });
        return NativeResult.scalar(if (execFailed(rc)) .{ .bool = false } else .{ .int = 0 });
    }

    if (args.len >= 3) {
        // the output variable gets a new array; the one it held may be shared
        const matches_arr = try ctx.createArray();
        const ovector = pcre2.pcre2_get_ovector_pointer_8(match_data);
        const matched_count: usize = @intCast(rc);

        // with PREG_UNMATCHED_AS_NULL, include every group in the pattern
        // (matched or not), so vendor code can index into named groups whose
        // captures didn't fire without triggering "Undefined array key"
        var total_groups: u32 = 0;
        _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_CAPTURECOUNT, @ptrCast(&total_groups));
        const count: usize = if (unmatched_as_null) @as(usize, total_groups) + 1 else matched_count;

        for (0..count) |i| {
            const start = ovector[i * 2];
            const end = ovector[i * 2 + 1];
            if (start == pcre2.UNSET or end == pcre2.UNSET) {
                const val: Value = if (unmatched_as_null) .null else if (offset_capture) try makeOffsetPair(ctx, "", -1) else Value{ .string = Value.String.borrowed("") };
                defer if (val == .string) val.string.release();
                try matches_arr.append(ctx.allocator, val);
            } else {
                const str = subject[start..end];
                const val = if (offset_capture) try makeOffsetPair(ctx, str, @intCast(start)) else Value{ .string = try Value.String.create(ctx.allocator, str) };
                defer if (val == .string) val.string.release();
                try matches_arr.append(ctx.allocator, val);
            }
        }
        try addNamedGroupsInterleaved(ctx, matches_arr, code, ovector, subject, count, offset_capture, unmatched_as_null);
        try setMark(ctx, matches_arr, .{ .string = Value.String.borrowed("MARK") }, match_data);
        ctx.setCallerVar(2, args.len, .{ .array = matches_arr });
    }

    return NativeResult.scalar(.{ .int = 1 });
}

fn addNamedGroupsInterleaved(ctx: *NativeContext, arr: *PhpArray, code: *pcre2.Code, ovector: [*]usize, subject: []const u8, count: usize, offset_capture: bool, unmatched_as_null: bool) !void {
    var name_count: u32 = 0;
    _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMECOUNT, @ptrCast(&name_count));
    if (name_count == 0) return;
    var name_entry_size: u32 = 0;
    _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMEENTRYSIZE, @ptrCast(&name_entry_size));
    if (name_entry_size == 0) return;

    var name_table: [*]const u8 = undefined;
    _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMETABLE, @ptrCast(&name_table));

    // collect named groups sorted by group_num so we can insert in order
    const NamedGroup = struct { group_num: usize, name: []const u8 };
    var groups: [64]NamedGroup = undefined;
    var group_len: usize = 0;
    for (0..name_count) |i| {
        const entry = name_table + i * name_entry_size;
        const group_num = (@as(usize, entry[0]) << 8) | @as(usize, entry[1]);
        const name_end = std.mem.indexOfScalar(u8, entry[2..name_entry_size], 0) orelse (name_entry_size - 2);
        if (group_len < groups.len) {
            groups[group_len] = .{ .group_num = group_num, .name = entry[2 .. 2 + name_end] };
            group_len += 1;
        }
    }
    // sort by group_num descending so we insert from the back
    std.mem.sort(NamedGroup, groups[0..group_len], {}, struct {
        fn f(_: void, a: NamedGroup, b: NamedGroup) bool {
            return a.group_num > b.group_num;
        }
    }.f);

    // With (?J), keep a single named entry per name. Value: pick the matched group
    // (or first by group_num if none matched). Position: before the lowest group_num
    // sharing that name.
    var inserted_names: [64][]const u8 = undefined;
    var inserted_count: usize = 0;
    for (groups[0..group_len]) |ng| {
        if (ng.group_num >= count) continue;
        var dup = false;
        for (inserted_names[0..inserted_count]) |n| {
            if (std.mem.eql(u8, n, ng.name)) {
                dup = true;
                break;
            }
        }
        if (dup) continue;

        var chosen = ng.group_num;
        var lowest = ng.group_num;
        var found_match = false;
        for (groups[0..group_len]) |other| {
            if (!std.mem.eql(u8, other.name, ng.name)) continue;
            if (other.group_num < lowest) lowest = other.group_num;
            if (other.group_num >= count) continue;
            const os = ovector[other.group_num * 2];
            const oe = ovector[other.group_num * 2 + 1];
            if (os != pcre2.UNSET and oe != pcre2.UNSET and !found_match) {
                chosen = other.group_num;
                found_match = true;
            }
        }
        if (!found_match) chosen = lowest;

        const start = ovector[chosen * 2];
        const end = ovector[chosen * 2 + 1];
        const val: Value = if (start == pcre2.UNSET or end == pcre2.UNSET) blk: {
            if (unmatched_as_null) break :blk .null;
            break :blk if (offset_capture) try makeOffsetPair(ctx, "", -1) else Value{ .string = Value.String.borrowed("") };
        } else blk: {
            const s = subject[start..end];
            break :blk if (offset_capture) try makeOffsetPair(ctx, s, @intCast(start)) else Value{ .string = try Value.String.create(ctx.allocator, s) };
        };
        const insert_pos = lowest;
        const named_entry = PhpArray.Entry{ .key = .{ .string = try Value.String.create(ctx.allocator, ng.name) }, .value = val };
        defer named_entry.key.string.release();
        defer if (val == .string) val.string.release();
        try insertNamedMatch(ctx, arr, insert_pos, named_entry);
        arr.rebuildStringIndexAssumeCapacity();
        inserted_names[inserted_count] = ng.name;
        inserted_count += 1;
    }
}

fn addNamedGroups(ctx: *NativeContext, arr: *PhpArray, code: *pcre2.Code, ovector: [*]usize, subject: []const u8, count: usize) !void {
    var name_count: u32 = 0;
    _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMECOUNT, @ptrCast(&name_count));
    if (name_count == 0) return;
    var name_entry_size: u32 = 0;
    _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMEENTRYSIZE, @ptrCast(&name_entry_size));
    if (name_entry_size == 0) return;

    var name_table: [*]const u8 = undefined;
    _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMETABLE, @ptrCast(&name_table));

    for (0..name_count) |i| {
        const entry = name_table + i * name_entry_size;
        const group_num = (@as(usize, entry[0]) << 8) | @as(usize, entry[1]);
        const name_end = std.mem.indexOfScalar(u8, entry[2..name_entry_size], 0) orelse (name_entry_size - 2);
        const name = entry[2 .. 2 + name_end];
        if (group_num < count) {
            const start = ovector[group_num * 2];
            const end = ovector[group_num * 2 + 1];
            const val: Value = if (start == pcre2.UNSET or end == pcre2.UNSET)
                .{ .string = Value.String.borrowed("") }
            else
                .{ .string = try Value.String.create(ctx.allocator, subject[start..end]) };
            defer if (val == .string) val.string.release();
            const key = try Value.String.create(ctx.allocator, name);
            defer key.release();
            try arr.set(ctx.allocator, .{ .string = key }, val);
        }
    }
}

// the name of the last (*MARK:name) the match passed, stored under `key`
fn setMark(ctx: *NativeContext, arr: *PhpArray, key: PhpArray.Key, match_data: anytype) RuntimeError!void {
    const mark_ptr = pcre2.pcre2_get_mark_8(match_data) orelse return;
    const mark = std.mem.sliceTo(mark_ptr, 0);
    if (mark.len == 0) return;
    const owned = try Value.String.create(ctx.allocator, mark);
    defer owned.release();
    try arr.set(ctx.allocator, key, .{ .string = owned });
}

fn preg_match_all(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    setPregError(0);
    const info = parsePattern(args[0].string.bytes()) orelse {
        setPregError(1);
        return NativeResult.scalar(.{ .bool = false });
    };
    const subject = args[1].string.bytes();

    const flags: u32 = if (args.len >= 4) @intCast(@max(0, Value.toInt(args[3]))) else 0;
    const set_order = (flags & 2) != 0; // PREG_SET_ORDER
    const offset_capture = (flags & 256) != 0; // PREG_OFFSET_CAPTURE
    const unmatched_as_null = (flags & 512) != 0; // PREG_UNMATCHED_AS_NULL

    const compiled = compilePattern(ctx, info.pattern, info.flags) orelse {
        setPregError(1);
        try emitCompileWarning(ctx, "preg_match_all", info.pattern, info.flags);
        return NativeResult.scalar(.{ .bool = false });
    };
    defer compiled.release();
    const code = compiled.code;

    const match_data = pcre2.pcre2_match_data_create_from_pattern_8(code, null) orelse return NativeResult.scalar(.{ .int = 0 });
    defer pcre2.pcre2_match_data_free_8(match_data);

    var capture_count: u32 = 0;
    _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_CAPTURECOUNT, @ptrCast(&capture_count));
    const group_count: usize = capture_count + 1;

    const out = try ctx.createArray();

    var group_arrays: ?std.ArrayListUnmanaged(*PhpArray) = null;
    if (!set_order) {
        var ga = std.ArrayListUnmanaged(*PhpArray).empty;
        for (0..group_count) |_| {
            try ga.append(ctx.allocator, try ctx.createArray());
        }
        group_arrays = ga;
    }
    defer if (group_arrays) |*ga| ga.deinit(ctx.allocator);

    var total_matches: i64 = 0;
    var offset: usize = 0;
    var marks: ?*PhpArray = null;
    const utf = UtfCheck.init(code, subject, args[1]);

    var failed = false;
    while (offset <= subject.len) {
        const rc = exec(ctx, code, subject, offset, utf.options(offset), match_data);
        if (rc < 0) {
            failed = execFailed(rc);
            break;
        }

        const ovector = pcre2.pcre2_get_ovector_pointer_8(match_data);
        const count: usize = @intCast(rc);

        if (set_order) {
            const match_arr = try ctx.createArray();
            // PHP omits trailing unmatched groups in SET_ORDER unless
            // PREG_UNMATCHED_AS_NULL is set, in which case they appear as null
            const last_idx: usize = if (unmatched_as_null) group_count - 1 else blk: {
                var last_matched: usize = 0;
                for (0..group_count) |i| {
                    if (i < count) {
                        const s = ovector[i * 2];
                        const e = ovector[i * 2 + 1];
                        if (s != pcre2.UNSET and e != pcre2.UNSET) {
                            last_matched = i;
                        }
                    }
                }
                break :blk last_matched;
            };
            for (0..last_idx + 1) |i| {
                const val = try matchGroupValue(ctx, subject, ovector, count, i, offset_capture);
                defer if (val == .string) val.string.release();
                try match_arr.append(ctx.allocator, val);
            }
            try addNamedGroupsToMatch(ctx, match_arr, code, ovector, subject, count, offset_capture);
            try setMark(ctx, match_arr, .{ .string = Value.String.borrowed("MARK") }, match_data);
            try out.append(ctx.allocator, .{ .array = match_arr });
        } else {
            for (0..group_count) |i| {
                const val = try matchGroupValue(ctx, subject, ovector, count, i, offset_capture);
                defer if (val == .string) val.string.release();
                try group_arrays.?.items[i].append(ctx.allocator, val);
            }
            // pattern order keeps the marks in one array keyed by match number
            if (pcre2.pcre2_get_mark_8(match_data) != null) {
                if (marks == null) marks = try ctx.createArray();
                try setMark(ctx, marks.?, .{ .int = total_matches }, match_data);
            }
        }

        total_matches += 1;
        const match_end = ovector[1];
        if (match_end == offset) {
            offset += utf.step(offset);
        } else {
            offset = match_end;
        }
    }

    if (!set_order) {
        // add named group arrays interleaved with their numeric index
        var name_count_val: u32 = 0;
        _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMECOUNT, @ptrCast(&name_count_val));
        var name_entry_size_val: u32 = 0;
        _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMEENTRYSIZE, @ptrCast(&name_entry_size_val));

        const NamedGroup = struct { group_num: usize, name: []const u8 };
        var named_groups: [64]NamedGroup = undefined;
        var named_len: usize = 0;
        if (name_count_val > 0 and name_entry_size_val > 0) {
            var name_table_ptr: [*]const u8 = undefined;
            _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMETABLE, @ptrCast(&name_table_ptr));
            for (0..name_count_val) |ni| {
                const entry = name_table_ptr + ni * name_entry_size_val;
                const gn = (@as(usize, entry[0]) << 8) | @as(usize, entry[1]);
                const ne = std.mem.indexOfScalar(u8, entry[2..name_entry_size_val], 0) orelse (name_entry_size_val - 2);
                if (named_len < named_groups.len) {
                    named_groups[named_len] = .{ .group_num = gn, .name = entry[2 .. 2 + ne] };
                    named_len += 1;
                }
            }
            // sort by group_num descending for insertion
            std.mem.sort(NamedGroup, named_groups[0..named_len], {}, struct {
                fn f(_: void, a: NamedGroup, b: NamedGroup) bool {
                    return a.group_num > b.group_num;
                }
            }.f);
        }

        for (group_arrays.?.items) |arr| {
            try out.append(ctx.allocator, .{ .array = arr });
        }

        // PHP places the named key directly before its numeric counterpart.
        // With (?J) duplicate-named groups, PHP keeps a single entry per name:
        // value comes from the highest-numbered group, position is before the
        // lowest-numbered group with that name.
        var inserted_names: [64][]const u8 = undefined;
        var inserted_count: usize = 0;
        for (named_groups[0..named_len]) |ng| {
            if (ng.group_num >= group_arrays.?.items.len) continue;
            var dup = false;
            for (inserted_names[0..inserted_count]) |n| {
                if (std.mem.eql(u8, n, ng.name)) {
                    dup = true;
                    break;
                }
            }
            if (dup) continue;
            // find lowest group_num among groups sharing this name (named_groups is desc by group_num)
            var lowest = ng.group_num;
            for (named_groups[0..named_len]) |other| {
                if (std.mem.eql(u8, other.name, ng.name) and other.group_num < lowest) lowest = other.group_num;
            }
            const insert_pos = lowest;
            const named_entry = PhpArray.Entry{
                .key = .{ .string = try Value.String.create(ctx.allocator, ng.name) },
                .value = .{ .array = group_arrays.?.items[ng.group_num] },
            };
            defer named_entry.key.string.release();
            try insertNamedMatch(ctx, out, insert_pos, named_entry);
            inserted_names[inserted_count] = ng.name;
            inserted_count += 1;
        }
        out.rebuildStringIndexAssumeCapacity();
        if (marks) |m| try out.set(ctx.allocator, .{ .string = Value.String.borrowed("MARK") }, .{ .array = m });
    }

    if (args.len >= 3) ctx.setCallerVar(2, args.len, .{ .array = out });

    return NativeResult.scalar(if (failed) .{ .bool = false } else .{ .int = total_matches });
}

fn matchGroupValue(ctx: *NativeContext, subject: []const u8, ovector: [*]usize, count: usize, i: usize, offset_capture: bool) RuntimeError!Value {
    if (i < count) {
        const start = ovector[i * 2];
        const end = ovector[i * 2 + 1];
        if (start == pcre2.UNSET or end == pcre2.UNSET) {
            return if (offset_capture) try makeOffsetPair(ctx, "", -1) else Value{ .string = Value.String.borrowed("") };
        }
        const str = subject[start..end];
        return if (offset_capture) try makeOffsetPair(ctx, str, @intCast(start)) else Value{ .string = try Value.String.create(ctx.allocator, str) };
    }
    return if (offset_capture) try makeOffsetPair(ctx, "", -1) else Value{ .string = Value.String.borrowed("") };
}

fn makeOffsetPair(ctx: *NativeContext, str: []const u8, offset: i64) RuntimeError!Value {
    const pair = try ctx.createArray();
    const owned = try Value.String.create(ctx.allocator, str);
    defer owned.release();
    try pair.append(ctx.allocator, .{ .string = owned });
    try pair.append(ctx.allocator, .{ .int = offset });
    return Value{ .array = pair };
}

fn addNamedGroupsToMatch(ctx: *NativeContext, arr: *PhpArray, code: *pcre2.Code, ovector: [*]usize, subject: []const u8, count: usize, offset_capture: bool) !void {
    var name_count: u32 = 0;
    _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMECOUNT, @ptrCast(&name_count));
    if (name_count == 0) return;
    var name_entry_size: u32 = 0;
    _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMEENTRYSIZE, @ptrCast(&name_entry_size));
    if (name_entry_size == 0) return;

    var name_table: [*]const u8 = undefined;
    _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMETABLE, @ptrCast(&name_table));

    const NamedGroup = struct { group_num: usize, name: []const u8 };
    var groups: [64]NamedGroup = undefined;
    var group_len: usize = 0;
    for (0..name_count) |i| {
        const entry = name_table + i * name_entry_size;
        const group_num = (@as(usize, entry[0]) << 8) | @as(usize, entry[1]);
        const name_end = std.mem.indexOfScalar(u8, entry[2..name_entry_size], 0) orelse (name_entry_size - 2);
        if (group_len < groups.len) {
            groups[group_len] = .{ .group_num = group_num, .name = entry[2 .. 2 + name_end] };
            group_len += 1;
        }
    }
    std.mem.sort(NamedGroup, groups[0..group_len], {}, struct {
        fn f(_: void, a: NamedGroup, b: NamedGroup) bool {
            return a.group_num > b.group_num;
        }
    }.f);

    for (groups[0..group_len]) |ng| {
        if (ng.group_num >= count) continue;
        const start = ovector[ng.group_num * 2];
        const end = ovector[ng.group_num * 2 + 1];
        const val: Value = if (start == pcre2.UNSET or end == pcre2.UNSET) blk: {
            break :blk if (offset_capture) try makeOffsetPair(ctx, "", -1) else Value{ .string = Value.String.borrowed("") };
        } else blk: {
            const s = subject[start..end];
            break :blk if (offset_capture) try makeOffsetPair(ctx, s, @intCast(start)) else Value{ .string = try Value.String.create(ctx.allocator, s) };
        };
        const insert_pos = ng.group_num;
        const named_entry = PhpArray.Entry{ .key = .{ .string = try Value.String.create(ctx.allocator, ng.name) }, .value = val };
        defer named_entry.key.string.release();
        defer if (val == .string) val.string.release();
        try insertNamedMatch(ctx, arr, insert_pos, named_entry);
    }
    arr.rebuildStringIndexAssumeCapacity();
}

fn insertNamedMatch(ctx: *NativeContext, arr: *PhpArray, position: usize, entry: PhpArray.Entry) !void {
    try arr.set(ctx.allocator, entry.key, entry.value);
    const last = arr.entries.items.len - 1;
    if (position < last) {
        const stored = arr.entries.items[last];
        std.mem.copyBackwards(PhpArray.Entry, arr.entries.items[position + 1 ..], arr.entries.items[position..last]);
        arr.entries.items[position] = stored;
        arr.rebuildStringIndexAssumeCapacity();
    }
}

fn translateReplacement(allocator: std.mem.Allocator, src: []const u8) ![]u8 {
    var out = std.ArrayListUnmanaged(u8).empty;
    defer out.deinit(allocator);
    var i: usize = 0;
    while (i < src.len) {
        const c = src[i];
        // PHP preg_replace only expands $N / ${N} (numeric) - keep ${name}
        // literal so pcre2 doesn't substitute it as a named group reference.
        // pcre2 uses `$$` to emit a literal `$`.
        if (c == '$' and i + 1 < src.len and src[i + 1] == '{') {
            if (i + 2 < src.len and !(src[i + 2] >= '0' and src[i + 2] <= '9')) {
                try out.append(allocator, '$');
                try out.append(allocator, '$');
                i += 1;
                continue;
            }
        }
        if (c == '\\' and i + 1 < src.len) {
            const n = src[i + 1];
            if (n >= '0' and n <= '9') {
                try out.append(allocator, '$');
                try out.append(allocator, n);
                i += 2;
                continue;
            }
            if (n == '\\') {
                try out.append(allocator, '\\');
                i += 2;
                continue;
            }
            if (n == '$') {
                // PHP '\$' means a literal '$' in the output. PCRE2 substitute
                // emits a literal '$' for '$$', so translate accordingly
                try out.append(allocator, '$');
                try out.append(allocator, '$');
                i += 2;
                continue;
            }
            try out.append(allocator, c);
            i += 1;
            continue;
        }
        try out.append(allocator, c);
        i += 1;
    }
    return out.toOwnedSlice(allocator);
}

fn preg_filter(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    setPregError(0);
    if (args.len < 3) return NativeResult.scalar(.null);
    if (args[2] == .array) {
        const subj_arr = args[2].array;
        const out = try ctx.vm.allocArray();
        for (subj_arr.entries.items) |se| {
            var sub_args: [3]Value = .{ args[0], args[1], se.value };
            const replaced = (try preg_replace(ctx, sub_args[0..3])).value;
            defer if (replaced == .string) replaced.string.release();
            // PHP preg_filter keeps only entries where the replacement actually
            // changed the string (i.e. at least one match)
            if (replaced == .string and se.value == .string and !std.mem.eql(u8, replaced.string.bytes(), se.value.string.bytes())) {
                try out.set(ctx.allocator, se.key, replaced);
            }
        }
        return NativeResult.borrowed(.{ .array = out });
    }
    const replaced = try preg_replace(ctx, args);
    if (replaced.value == .string and args[2] == .string and !std.mem.eql(u8, replaced.value.string.bytes(), args[2].string.bytes())) return replaced;
    if (replaced.value == .string) replaced.value.string.release();
    return NativeResult.scalar(.null);
}

// PHP coerces a scalar subject to string before matching, so a scalar
// always comes back as a string even when nothing matched
fn replaceWithCoercedSubject(ctx: *NativeContext, args: []const Value, comptime idx: usize, comptime native: anytype) RuntimeError!?NativeResult {
    if (args.len <= idx or args[idx] == .string or args[idx] == .array or args[idx] == .object) return null;
    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);
    try args[idx].format(&buf, ctx.allocator);
    const subject = try Value.String.create(ctx.allocator, buf.items);
    defer subject.release();
    var coerced: [5]Value = undefined;
    if (args.len > coerced.len) return null;
    @memcpy(coerced[0..args.len], args);
    coerced[idx] = .{ .string = subject };
    return try native(ctx, coerced[0..args.len]);
}

fn preg_replace(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 3) return NativeResult.scalar(.null);
    setPregError(0);
    if (try replaceWithCoercedSubject(ctx, args, 2, preg_replace)) |coerced| return coerced;
    // subject can be an array - apply replacements element-wise and return array
    if (args[2] == .array) {
        const subj_arr = args[2].array;
        const result_arr = try ctx.vm.allocArray();
        for (subj_arr.entries.items) |se| {
            var sub_args: [4]Value = undefined;
            sub_args[0] = args[0];
            sub_args[1] = args[1];
            sub_args[2] = se.value;
            var n: usize = 3;
            if (args.len >= 4) {
                sub_args[3] = args[3];
                n = 4;
            }
            const replaced = (try preg_replace(ctx, sub_args[0..n])).value;
            defer if (replaced == .string) replaced.string.release();
            // a subject the match failed on is left out
            if (replaced == .null) continue;
            try result_arr.set(ctx.allocator, se.key, replaced);
        }
        return NativeResult.borrowed(.{ .array = result_arr });
    }
    // pattern can be array - call recursively for each (pattern, replacement) pair
    if (args[0] == .array) {
        return try pregReplaceArrayPattern(ctx, args);
    }
    if (args[0] != .string or args[2] != .string) return if (args[2] == .string) NativeResult.takeString(try Value.String.create(ctx.allocator, args[2].string.bytes())) else NativeResult.share(args[2]);
    const info = parsePattern(args[0].string.bytes()) orelse {
        setPregError(1);
        return NativeResult.scalar(.null);
    };
    const replacement = if (args[1] == .string) args[1].string.bytes() else return if (args[2] == .string) NativeResult.takeString(try Value.String.create(ctx.allocator, args[2].string.bytes())) else NativeResult.share(args[2]);
    const subject = args[2].string.bytes();
    const limit: i64 = if (args.len >= 4 and args[3] != .null) Value.toInt(args[3]) else -1;

    if (limit == 0) {
        if (args.len >= 5) ctx.setCallerVar(4, args.len, .{ .int = 0 });
        return NativeResult.takeString(try Value.String.create(ctx.allocator, subject));
    }

    const compiled = compilePattern(ctx, info.pattern, info.flags) orelse {
        setPregError(1);
        try emitCompileWarning(ctx, "preg_replace", info.pattern, info.flags);
        return NativeResult.scalar(.null);
    };
    defer compiled.release();
    const code = compiled.code;

    const match_data = pcre2.pcre2_match_data_create_from_pattern_8(code, null) orelse return if (args[2] == .string) NativeResult.takeString(try Value.String.create(ctx.allocator, args[2].string.bytes())) else NativeResult.share(args[2]);
    defer pcre2.pcre2_match_data_free_8(match_data);

    if (limit > 0) {
        return pregReplaceLimited(ctx, code, match_data, subject, replacement, @intCast(limit), args);
    }

    const xrep = try translateReplacement(ctx.allocator, replacement);
    defer ctx.allocator.free(xrep);

    const sub_opts: u32 = pcre2.SUBSTITUTE_OVERFLOW_LENGTH | pcre2.SUBSTITUTE_GLOBAL | UtfCheck.init(code, subject, args[2]).options(0);

    var out_len: usize = 0;
    var rc = pcre2.pcre2_substitute_8(
        code,
        if (subject.len == 0) "" else subject.ptr,
        subject.len,
        0,
        sub_opts,
        match_data,
        matchContext(ctx),
        xrep.ptr,
        xrep.len,
        null,
        &out_len,
    );

    if (rc >= 0) {
        ctx.setCallerVar(4, args.len, .{ .int = @intCast(rc) });
        return if (args[2] == .string) NativeResult.takeString(try Value.String.create(ctx.allocator, args[2].string.bytes())) else NativeResult.share(args[2]);
    }
    if (rc != pcre2.ERROR_NOMEMORY) {
        ctx.setCallerVar(4, args.len, .{ .int = 0 });
        if (execFailed(rc)) return NativeResult.scalar(.null);
        return if (args[2] == .string) NativeResult.takeString(try Value.String.create(ctx.allocator, args[2].string.bytes())) else NativeResult.share(args[2]);
    }

    const buf = try ctx.allocator.alloc(u8, out_len);
    rc = pcre2.pcre2_substitute_8(
        code,
        if (subject.len == 0) "" else subject.ptr,
        subject.len,
        0,
        sub_opts,
        match_data,
        matchContext(ctx),
        xrep.ptr,
        xrep.len,
        buf.ptr,
        &out_len,
    );

    if (rc < 0) {
        ctx.allocator.free(buf);
        ctx.setCallerVar(4, args.len, .{ .int = 0 });
        if (execFailed(rc)) return NativeResult.scalar(.null);
        return if (args[2] == .string) NativeResult.takeString(try Value.String.create(ctx.allocator, args[2].string.bytes())) else NativeResult.share(args[2]);
    }

    ctx.setCallerVar(4, args.len, .{ .int = @intCast(rc) });
    const result = try Value.String.adopt(ctx.allocator, buf);
    return NativeResult.takeString(result.borrowedSlice(0, out_len));
}

fn pregReplaceArrayPattern(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const patterns = args[0].array;
    var current: NativeResult = if (args[2] == .string) NativeResult.takeString(try Value.String.create(ctx.allocator, args[2].string.bytes())) else NativeResult.share(args[2]);
    errdefer if (current.value == .string) current.value.string.release();
    var total_count: i64 = 0;
    const limit_per: i64 = if (args.len >= 4) Value.toInt(args[3]) else -1;
    for (patterns.entries.items, 0..) |pe, idx| {
        if (pe.value != .string) continue;
        var replacement: Value = if (args[1] == .string) args[1] else Value{ .string = Value.String.borrowed("") };
        if (args[1] == .array) {
            const rep_arr = args[1].array;
            if (idx < rep_arr.entries.items.len and rep_arr.entries.items[idx].value == .string) {
                replacement = rep_arr.entries.items[idx].value;
            }
        }
        // count matches against the current subject (respecting limit)
        if (current.value == .string) {
            const before = current.value.string.bytes();
            if (parsePattern(pe.value.string.bytes())) |info| {
                if (compilePattern(ctx, info.pattern, info.flags)) |compiled| {
                    defer compiled.release();
                    const code = compiled.code;
                    if (pcre2.pcre2_match_data_create_from_pattern_8(code, null)) |md| {
                        defer pcre2.pcre2_match_data_free_8(md);
                        var off: usize = 0;
                        var matched: i64 = 0;
                        const utf = UtfCheck.init(code, before, current.value);
                        while (off <= before.len) {
                            if (limit_per >= 0 and matched >= limit_per) break;
                            const rc = exec(ctx, code, before, off, utf.options(off), md);
                            if (rc < 0) break;
                            const ov = pcre2.pcre2_get_ovector_pointer_8(md);
                            const me = ov[1];
                            matched += 1;
                            if (me == off) off += utf.step(off) else off = me;
                        }
                        total_count += matched;
                    }
                }
            }
        }
        var rest: [3]Value = undefined;
        rest[0] = pe.value;
        rest[1] = replacement;
        rest[2] = current.value;
        var single_args: [4]Value = undefined;
        single_args[0] = rest[0];
        single_args[1] = rest[1];
        single_args[2] = rest[2];
        var n: usize = 3;
        if (args.len >= 4) {
            single_args[3] = args[3];
            n = 4;
        }
        const next = try preg_replace(ctx, single_args[0..n]);
        if (current.value == .string) current.value.string.release();
        current = next;
    }
    ctx.setCallerVar(4, args.len, .{ .int = total_count });
    return current;
}

fn pregReplaceLimited(ctx: *NativeContext, code: *pcre2.Code, match_data: *pcre2.MatchData, subject: []const u8, replacement: []const u8, limit: usize, args: []const Value) RuntimeError!NativeResult {
    var parts = std.ArrayListUnmanaged(u8).empty;
    defer parts.deinit(ctx.allocator);
    var offset: usize = 0;
    var count: usize = 0;
    const utf = UtfCheck.init(code, subject, null);

    while (offset <= subject.len and count < limit) {
        const rc = exec(ctx, code, subject, offset, utf.options(offset), match_data);
        if (rc < 0) {
            if (execFailed(rc)) return NativeResult.scalar(.null);
            break;
        }

        const ovector = pcre2.pcre2_get_ovector_pointer_8(match_data);
        const ms = ovector[0];
        const me = ovector[1];

        try parts.appendSlice(ctx.allocator, subject[offset..ms]);

        // handle backreferences in replacement
        var ri: usize = 0;
        while (ri < replacement.len) {
            if (replacement[ri] == '$' and ri + 1 < replacement.len and replacement[ri + 1] >= '0' and replacement[ri + 1] <= '9') {
                const group = replacement[ri + 1] - '0';
                ri += 2;
                if (group < @as(u8, @intCast(rc))) {
                    const gs = ovector[2 * @as(usize, group)];
                    const ge = ovector[2 * @as(usize, group) + 1];
                    if (gs <= subject.len and ge <= subject.len) {
                        try parts.appendSlice(ctx.allocator, subject[gs..ge]);
                    }
                }
            } else if (replacement[ri] == '\\' and ri + 1 < replacement.len and replacement[ri + 1] >= '0' and replacement[ri + 1] <= '9') {
                const group = replacement[ri + 1] - '0';
                ri += 2;
                if (group < @as(u8, @intCast(rc))) {
                    const gs = ovector[2 * @as(usize, group)];
                    const ge = ovector[2 * @as(usize, group) + 1];
                    if (gs <= subject.len and ge <= subject.len) {
                        try parts.appendSlice(ctx.allocator, subject[gs..ge]);
                    }
                }
            } else if (replacement[ri] == '\\' and ri + 1 < replacement.len and (replacement[ri + 1] == '\\' or replacement[ri + 1] == '$')) {
                // \\ -> literal \; \$ -> literal $
                try parts.append(ctx.allocator, replacement[ri + 1]);
                ri += 2;
            } else {
                try parts.append(ctx.allocator, replacement[ri]);
                ri += 1;
            }
        }

        count += 1;
        if (me == offset) {
            const step = utf.step(offset);
            if (offset < subject.len) {
                try parts.appendSlice(ctx.allocator, subject[offset..@min(offset + step, subject.len)]);
            }
            offset += step;
        } else {
            offset = me;
        }
    }

    if (offset <= subject.len) {
        try parts.appendSlice(ctx.allocator, subject[offset..]);
    }

    const buf = try ctx.allocator.alloc(u8, parts.items.len);
    @memcpy(buf, parts.items);
    ctx.setCallerVar(4, args.len, .{ .int = @intCast(count) });
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, buf));
}

fn preg_replace_callback(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    setPregError(0);
    if (args.len < 3) return NativeResult.scalar(.null);
    if (try replaceWithCoercedSubject(ctx, args, 2, preg_replace_callback)) |coerced| return coerced;
    if (args[2] == .array) {
        const result = try ctx.createArray();
        for (args[2].array.entries.items) |entry| {
            var sub_args: [5]Value = undefined;
            sub_args[0] = args[0];
            sub_args[1] = args[1];
            sub_args[2] = entry.value;
            if (args.len >= 4) sub_args[3] = args[3];
            const replaced = (try preg_replace_callback(ctx, sub_args[0..@min(args.len, 4)])).value;
            defer if (replaced == .string) replaced.string.release();
            try result.set(ctx.allocator, entry.key, replaced);
        }
        return NativeResult.borrowed(.{ .array = result });
    }
    if (args[0] == .array) {
        var current: NativeResult = if (args[2] == .string) NativeResult.takeString(try Value.String.create(ctx.allocator, args[2].string.bytes())) else NativeResult.share(args[2]);
        errdefer if (current.value == .string) current.value.string.release();
        for (args[0].array.entries.items) |pat_entry| {
            if (pat_entry.value != .string) continue;
            var sub_args: [5]Value = undefined;
            sub_args[0] = pat_entry.value;
            sub_args[1] = args[1];
            sub_args[2] = current.value;
            if (args.len >= 4) sub_args[3] = args[3];
            const next = try preg_replace_callback(ctx, sub_args[0..@min(args.len, 4)]);
            if (current.value == .string) current.value.string.release();
            current = next;
        }
        return current;
    }
    if (args[0] != .string or args[2] != .string) return if (args[2] == .string) NativeResult.takeString(try Value.String.create(ctx.allocator, args[2].string.bytes())) else NativeResult.share(args[2]);
    const info = parsePattern(args[0].string.bytes()) orelse return if (args[2] == .string) NativeResult.takeString(try Value.String.create(ctx.allocator, args[2].string.bytes())) else NativeResult.share(args[2]);
    const callback = args[1];
    const subject = args[2].string.bytes();

    const compiled = compilePattern(ctx, info.pattern, info.flags) orelse return if (args[2] == .string) NativeResult.takeString(try Value.String.create(ctx.allocator, args[2].string.bytes())) else NativeResult.share(args[2]);
    defer compiled.release();
    const code = compiled.code;

    const match_data = pcre2.pcre2_match_data_create_from_pattern_8(code, null) orelse return if (args[2] == .string) NativeResult.takeString(try Value.String.create(ctx.allocator, args[2].string.bytes())) else NativeResult.share(args[2]);
    defer pcre2.pcre2_match_data_free_8(match_data);

    var capture_count: u32 = 0;
    _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_CAPTURECOUNT, @ptrCast(&capture_count));
    const group_count: usize = capture_count + 1;

    // collect named-group info once
    var name_count: u32 = 0;
    _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMECOUNT, @ptrCast(&name_count));
    var name_entry_size: u32 = 0;
    _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMEENTRYSIZE, @ptrCast(&name_entry_size));
    var name_table_ptr: [*]const u8 = undefined;
    if (name_count > 0) _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMETABLE, @ptrCast(&name_table_ptr));

    var result = std.ArrayListUnmanaged(u8).empty;
    defer result.deinit(ctx.allocator);
    var offset: usize = 0;
    var replace_count: i64 = 0;
    const limit: i64 = if (args.len >= 4) Value.toInt(args[3]) else -1;
    const utf = UtfCheck.init(code, subject, args[2]);

    while (offset <= subject.len) {
        if (limit >= 0 and replace_count >= limit) break;
        const rc = exec(ctx, code, subject, offset, utf.options(offset), match_data);
        if (rc < 0) {
            if (execFailed(rc)) return NativeResult.scalar(.null);
            break;
        }

        const ovector = pcre2.pcre2_get_ovector_pointer_8(match_data);
        const match_start = ovector[0];
        const match_end = ovector[1];

        try result.appendSlice(ctx.allocator, subject[offset..match_start]);

        const matches_arr = try ctx.createArray();
        for (0..group_count) |gi| {
            const gs = ovector[gi * 2];
            const ge = ovector[gi * 2 + 1];
            const slice: []const u8 = if (gs == pcre2.UNSET or ge == pcre2.UNSET or gs > subject.len or ge > subject.len)
                ""
            else
                subject[gs..ge];
            const capture = try Value.String.create(ctx.allocator, slice);
            defer capture.release();
            // PHP places the named entry just before the numeric one
            if (name_count > 0 and name_entry_size > 0) {
                for (0..name_count) |ni| {
                    const entry = name_table_ptr + ni * name_entry_size;
                    const gn = (@as(usize, entry[0]) << 8) | @as(usize, entry[1]);
                    if (gn == gi) {
                        const ne = std.mem.indexOfScalar(u8, entry[2..name_entry_size], 0) orelse (name_entry_size - 2);
                        const name = entry[2 .. 2 + ne];
                        const key = try Value.String.create(ctx.allocator, name);
                        defer key.release();
                        try matches_arr.set(ctx.allocator, .{ .string = key }, .{ .string = capture });
                    }
                }
            }
            try matches_arr.append(ctx.allocator, .{ .string = capture });
        }

        try setMark(ctx, matches_arr, .{ .string = Value.String.borrowed("MARK") }, match_data);
        const cb_result = try ctx.invokeCallable(callback, &.{.{ .array = matches_arr }});
        if (cb_result == .string) {
            try result.appendSlice(ctx.allocator, cb_result.string.bytes());
        } else {
            var buf = std.ArrayListUnmanaged(u8).empty;
            try cb_result.format(&buf, ctx.allocator);
            defer buf.deinit(ctx.allocator);
            try result.appendSlice(ctx.allocator, buf.items);
        }

        replace_count += 1;
        if (match_end == offset) {
            const step = utf.step(offset);
            if (offset < subject.len) {
                try result.appendSlice(ctx.allocator, subject[offset..@min(offset + step, subject.len)]);
            }
            offset += step;
        } else {
            offset = match_end;
        }
    }

    if (offset < subject.len) {
        try result.appendSlice(ctx.allocator, subject[offset..]);
    }

    if (args.len >= 5) ctx.setCallerVar(4, args.len, .{ .int = replace_count });

    const s = try result.toOwnedSlice(ctx.allocator);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, s));
}

fn preg_replace_callback_array(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    setPregError(0);
    if (args.len < 2 or args[0] != .array) return if (args.len >= 2) NativeResult.share(args[1]) else NativeResult.scalar(.null);
    if (try replaceWithCoercedSubject(ctx, args, 1, preg_replace_callback_array)) |coerced| return coerced;
    const map = args[0].array;
    if (args[1] == .array) {
        const result = try ctx.createArray();
        for (args[1].array.entries.items) |entry| {
            var sub_args: [4]Value = undefined;
            sub_args[0] = args[0];
            sub_args[1] = entry.value;
            if (args.len >= 3) sub_args[2] = args[2];
            const replaced = (try preg_replace_callback_array(ctx, sub_args[0..args.len])).value;
            defer if (replaced == .string) replaced.string.release();
            try result.set(ctx.allocator, entry.key, replaced);
        }
        return NativeResult.borrowed(.{ .array = result });
    }
    if (args[1] != .string) return NativeResult.share(args[1]);
    var current = NativeResult.takeString(try Value.String.create(ctx.allocator, args[1].string.bytes()));
    errdefer current.value.string.release();
    var total_count: i64 = 0;
    const limit: i64 = if (args.len >= 3) Value.toInt(args[2]) else -1;

    for (map.entries.items) |entry| {
        if (entry.key != .string) continue;
        // count matches in current subject for this pattern
        if (current.value == .string) {
            const subject = current.value.string.bytes();
            if (parsePattern(entry.key.string.bytes())) |info| {
                if (compilePattern(ctx, info.pattern, info.flags)) |compiled| {
                    defer compiled.release();
                    const code = compiled.code;
                    if (pcre2.pcre2_match_data_create_from_pattern_8(code, null)) |md| {
                        defer pcre2.pcre2_match_data_free_8(md);
                        var off: usize = 0;
                        var matched: i64 = 0;
                        const utf = UtfCheck.init(code, subject, current.value);
                        while (off <= subject.len) {
                            if (limit >= 0 and matched >= limit) break;
                            const rc = exec(ctx, code, subject, off, utf.options(off), md);
                            if (rc < 0) break;
                            const ov = pcre2.pcre2_get_ovector_pointer_8(md);
                            const me = ov[1];
                            matched += 1;
                            if (me == off) off += utf.step(off) else off = me;
                        }
                        total_count += matched;
                    }
                }
            }
        }
        var sub_args: [4]Value = undefined;
        sub_args[0] = .{ .string = entry.key.string };
        sub_args[1] = entry.value;
        sub_args[2] = current.value;
        var n: usize = 3;
        if (args.len >= 3) {
            sub_args[3] = args[2];
            n = 4;
        }
        const r = try preg_replace_callback(ctx, sub_args[0..n]);
        if (r.value == .string) {
            current.value.string.release();
            current = r;
        }
    }
    ctx.setCallerVar(3, args.len, .{ .int = total_count });
    return current;
}

fn utf8SeqLen(lead: u8) usize {
    if (lead < 0x80) return 1;
    if (lead >= 0xF0) return 4;
    if (lead >= 0xE0) return 3;
    if (lead >= 0xC0) return 2;
    return 1; // continuation byte / invalid - treat as single byte
}

fn preg_split(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    setPregError(0);
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const info = parsePattern(args[0].string.bytes()) orelse {
        setPregError(1);
        return NativeResult.scalar(.{ .bool = false });
    };
    const subject = args[1].string.bytes();
    const limit: i64 = if (args.len >= 3 and args[2] != .null) Value.toInt(args[2]) else -1;
    const flags: i64 = if (args.len >= 4) Value.toInt(args[3]) else 0;
    const delim_capture = (flags & 2) != 0;
    const no_empty = (flags & 1) != 0;
    const offset_capture = (flags & 4) != 0;

    const compiled = compilePattern(ctx, info.pattern, info.flags) orelse return NativeResult.scalar(.null);
    defer compiled.release();
    const code = compiled.code;

    const match_data = pcre2.pcre2_match_data_create_from_pattern_8(code, null) orelse return NativeResult.scalar(.null);
    defer pcre2.pcre2_match_data_free_8(match_data);

    var result = try ctx.createArray();
    // prev_end: source position where the next piece begins (end of last
    // match). search: where to look for the next match. they diverge only
    // around zero-width matches, where search advances a char past the match
    // but the piece still starts at prev_end so each delimiter char becomes
    // its own following piece (this is how '//' splits into characters)
    var prev_end: usize = 0;
    var search: usize = 0;
    var splits: i64 = 1;
    const is_utf = (info.flags & pcre2.UTF) != 0;
    const utf = UtfCheck.init(code, subject, args[1]);

    while (search <= subject.len) {
        if (limit > 0 and splits >= limit) break;

        const rc = exec(ctx, code, subject, search, utf.options(search), match_data);
        if (rc < 0) {
            if (execFailed(rc)) return NativeResult.scalar(.{ .bool = false });
            break;
        }

        const ovector = pcre2.pcre2_get_ovector_pointer_8(match_data);
        const match_start = ovector[0];
        const match_end = ovector[1];
        const zero_width = match_end == match_start;

        // a zero-width match exactly at prev_end (other than at string start)
        // would emit an empty piece in place - skip it and advance the search
        if (zero_width and match_start == prev_end and search > 0) {
            var step: usize = 1;
            if (is_utf and search < subject.len) {
                step = utf8SeqLen(subject[search]);
                if (search + step > subject.len) step = 1;
            }
            search += step;
            continue;
        }

        const piece = try Value.String.create(ctx.allocator, subject[prev_end..match_start]);
        defer piece.release();
        if (!no_empty or piece.len > 0) {
            if (offset_capture) {
                var pair = try ctx.createArray();
                try pair.append(ctx.allocator, .{ .string = piece });
                try pair.append(ctx.allocator, .{ .int = @intCast(prev_end) });
                try result.append(ctx.allocator, .{ .array = pair });
            } else {
                try result.append(ctx.allocator, .{ .string = piece });
            }
        }
        splits += 1;

        if (delim_capture and rc > 1) {
            var i: usize = 1;
            while (i < @as(usize, @intCast(rc))) : (i += 1) {
                const gs = ovector[2 * i];
                const ge = ovector[2 * i + 1];
                if (gs <= subject.len and ge <= subject.len) {
                    const cap = try Value.String.create(ctx.allocator, subject[gs..ge]);
                    defer cap.release();
                    if (!no_empty or cap.len > 0) {
                        if (offset_capture) {
                            var pair = try ctx.createArray();
                            try pair.append(ctx.allocator, .{ .string = cap });
                            try pair.append(ctx.allocator, .{ .int = @intCast(gs) });
                            try result.append(ctx.allocator, .{ .array = pair });
                        } else {
                            try result.append(ctx.allocator, .{ .string = cap });
                        }
                    }
                } else if (!no_empty) {
                    if (offset_capture) {
                        var pair = try ctx.createArray();
                        try pair.append(ctx.allocator, .{ .string = Value.String.borrowed("") });
                        try pair.append(ctx.allocator, .{ .int = 0 });
                        try result.append(ctx.allocator, .{ .array = pair });
                    } else {
                        try result.append(ctx.allocator, .{ .string = Value.String.borrowed("") });
                    }
                }
            }
        }

        prev_end = match_end;
        if (zero_width) {
            // advance the search past one char so we make progress; the
            // skipped char stays in subject and becomes the next piece
            var step: usize = 1;
            if (is_utf and match_end < subject.len) {
                step = utf8SeqLen(subject[match_end]);
                if (match_end + step > subject.len) step = 1;
            }
            search = match_end + step;
        } else {
            search = match_end;
        }
    }

    const tail = try Value.String.create(ctx.allocator, subject[prev_end..]);
    defer tail.release();
    if (!no_empty or tail.len > 0) {
        if (offset_capture) {
            var pair = try ctx.createArray();
            try pair.append(ctx.allocator, .{ .string = tail });
            try pair.append(ctx.allocator, .{ .int = @intCast(prev_end) });
            try result.append(ctx.allocator, .{ .array = pair });
        } else {
            try result.append(ctx.allocator, .{ .string = tail });
        }
    }

    return NativeResult.borrowed(.{ .array = result });
}

fn preg_quote(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.literal("");
    const input = args[0].string.bytes();
    const delimiter: ?u8 = if (args.len >= 2 and args[1] == .string and args[1].string.bytes().len > 0) args[1].string.bytes()[0] else null;

    // pcre special chars: . \ + * ? [ ^ ] $ ( ) { } = ! < > | : - #
    const specials = ".\\+*?[^]$(){}=!<>|:-#";

    var buf = std.ArrayListUnmanaged(u8).empty;
    for (input) |c| {
        if (delimiter != null and c == delimiter.?) {
            try buf.append(ctx.allocator, '\\');
        } else if (std.mem.indexOfScalar(u8, specials, c) != null) {
            try buf.append(ctx.allocator, '\\');
        }
        try buf.append(ctx.allocator, c);
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result));
}

fn preg_grep(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    setPregError(0);
    if (args.len < 2 or args[0] != .string or args[1] != .array) return NativeResult.scalar(.{ .bool = false });
    const info = parsePattern(args[0].string.bytes()) orelse {
        setPregError(1);
        return NativeResult.scalar(.{ .bool = false });
    };
    const input = args[1].array;
    const invert = args.len >= 3 and Value.toInt(args[2]) == 1;

    const compiled = compilePattern(ctx, info.pattern, info.flags) orelse return NativeResult.scalar(.null);
    defer compiled.release();
    const code = compiled.code;

    const match_data = pcre2.pcre2_match_data_create_from_pattern_8(code, null) orelse return NativeResult.scalar(.null);
    defer pcre2.pcre2_match_data_free_8(match_data);

    var result = try ctx.createArray();
    for (input.entries.items) |entry| {
        const str = if (entry.value == .string) entry.value.string.bytes() else continue;
        const rc = exec(ctx, code, str, 0, UtfCheck.init(code, str, entry.value).options(0), match_data);
        if (execFailed(rc)) break;
        const matched = rc >= 0;
        if (matched != invert) {
            try result.set(ctx.allocator, entry.key, entry.value);
        }
    }
    return NativeResult.borrowed(.{ .array = result });
}

// global preg_last_error state - mirrors PHP's per-thread last error
threadlocal var preg_last_error_code: i64 = 0;

fn setPregError(code: i64) void {
    preg_last_error_code = code;
}

fn preg_last_error(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = preg_last_error_code });
}

fn preg_last_error_msg(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const msg: []const u8 = switch (preg_last_error_code) {
        0 => "No error",
        1 => "Internal error",
        2 => "Backtrack limit exhausted",
        3 => "Recursion limit exhausted",
        4 => "Malformed UTF-8 characters, possibly incorrectly encoded",
        5 => "The offset did not correspond to the beginning of a valid UTF-8 code point",
        6 => "JIT stack limit exhausted",
        else => "Unknown error",
    };
    return try NativeResult.copyString(ctx.allocator, msg);
}

fn mb_split(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.null);
    const pattern = args[0].string.bytes();
    const subject = args[1].string.bytes();
    const limit: i64 = if (args.len >= 3 and args[2] != .null) Value.toInt(args[2]) else -1;

    const compiled = compilePattern(ctx, pattern, pcre2.UTF) orelse return NativeResult.scalar(.null);
    defer compiled.release();
    const code = compiled.code;

    const match_data = pcre2.pcre2_match_data_create_from_pattern_8(code, null) orelse return NativeResult.scalar(.null);
    defer pcre2.pcre2_match_data_free_8(match_data);

    var result = try ctx.createArray();
    var offset: usize = 0;
    var splits: i64 = 1;
    const utf = UtfCheck.init(code, subject, args[1]);

    while (offset <= subject.len) {
        if (limit > 0 and splits >= limit) break;

        const rc = exec(ctx, code, subject, offset, utf.options(offset), match_data);
        if (rc < 0) break;

        const ovector = pcre2.pcre2_get_ovector_pointer_8(match_data);
        const match_start = ovector[0];
        const match_end = ovector[1];

        try result.appendCopiedString(ctx.allocator, subject[offset..match_start]);
        splits += 1;

        if (match_end == offset) {
            const step = utf.step(offset);
            if (offset < subject.len) {
                try result.appendCopiedString(ctx.allocator, subject[offset..@min(offset + step, subject.len)]);
            }
            offset += step;
        } else {
            offset = match_end;
        }
    }

    if (offset <= subject.len) {
        try result.appendCopiedString(ctx.allocator, subject[offset..]);
    }

    return NativeResult.borrowed(.{ .array = result });
}

fn mb_ereg_match(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const pattern = args[0].string.bytes();
    const subject = args[1].string.bytes();

    const compiled = compilePattern(ctx, pattern, pcre2.UTF | pcre2.ANCHORED) orelse return NativeResult.scalar(.{ .bool = false });
    defer compiled.release();
    const code = compiled.code;

    const match_data = pcre2.pcre2_match_data_create_from_pattern_8(code, null) orelse return NativeResult.scalar(.{ .bool = false });
    defer pcre2.pcre2_match_data_free_8(match_data);

    const rc = exec(ctx, code, subject, 0, UtfCheck.init(code, subject, args[1]).options(0), match_data);
    return NativeResult.scalar(.{ .bool = rc >= 0 });
}
