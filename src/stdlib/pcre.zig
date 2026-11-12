// php's ext/pcre (php_pcre.c): the regex cache with php's delimiter and
// modifier parsing and its warnings, preg_match / preg_match_all
// (php_pcre_match_impl), the replace family (php_pcre_replace_impl and the
// callback variant), preg_split, preg_quote, preg_grep and preg_last_error.
// every match goes through exec, with the per-thread match context carrying
// pcre.backtrack_limit and pcre.recursion_limit and php's jit stack
const std = @import("std");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const PhpArray = value_mod.PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const RuntimeError = error{ RuntimeError, OutOfMemory };
const Args = @import("string_ports.zig").Args;
const array_diff = @import("array_diff.zig");
const callables = @import("../runtime/callables.zig");

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
    const NEVER_BACKSLASH_C: u32 = 0x00100000;
    const EXTRA_CASELESS_RESTRICT: u32 = 0x00000080;
    const NOTEMPTY_ATSTART: u32 = 0x00000008;

    const INFO_CAPTURECOUNT: u32 = 4;
    const INFO_JITSIZE: u32 = 10;
    const INFO_NAMECOUNT: u32 = 17;
    const INFO_NAMEENTRYSIZE: u32 = 18;
    const INFO_NAMETABLE: u32 = 19;
    const ERROR_NOMATCH: c_int = -1;
    const ERROR_UTF8_ERR1: c_int = -3;
    const ERROR_UTF8_ERR21: c_int = -23;
    const ERROR_BADOFFSET: c_int = -33;
    const ERROR_BADUTFOFFSET: c_int = -36;
    const ERROR_JIT_STACKLIMIT: c_int = -46;
    const ERROR_MATCHLIMIT: c_int = -47;
    const ERROR_DEPTHLIMIT: c_int = -53;
    const ERROR_BACKSLASH_C_CALLER_DISABLED: c_int = 183;
    const UNSET: usize = std.math.maxInt(usize);
    const CONFIG_JIT: u32 = 1;
    const CONFIG_VERSION: u32 = 11;

    extern "c" fn pcre2_compile_8(pattern: [*]const u8, length: usize, options: u32, errorcode: *c_int, erroroffset: *usize, ccontext: ?*anyopaque) callconv(.c) ?*Code;
    extern "c" fn pcre2_code_free_8(code: ?*Code) callconv(.c) void;
    extern "c" fn pcre2_get_error_message_8(errorcode: c_int, buffer: [*]u8, bufflen: usize) callconv(.c) c_int;
    extern "c" fn pcre2_match_data_create_from_pattern_8(code: *const Code, gcontext: ?*anyopaque) callconv(.c) ?*MatchData;
    extern "c" fn pcre2_match_data_free_8(match_data: ?*MatchData) callconv(.c) void;
    extern "c" fn pcre2_match_context_create_8(gcontext: ?*anyopaque) callconv(.c) ?*anyopaque;
    extern "c" fn pcre2_compile_context_create_8(gcontext: ?*anyopaque) callconv(.c) ?*anyopaque;
    extern "c" fn pcre2_set_compile_extra_options_8(ccontext: *anyopaque, options: u32) callconv(.c) c_int;
    extern "c" fn pcre2_jit_compile_8(code: *Code, options: u32) callconv(.c) c_int;
    extern "c" fn pcre2_jit_stack_create_8(startsize: usize, maxsize: usize, gcontext: ?*anyopaque) callconv(.c) ?*anyopaque;
    extern "c" fn pcre2_jit_stack_assign_8(mcontext: *anyopaque, callback: ?*anyopaque, data: ?*anyopaque) callconv(.c) void;
    extern "c" fn pcre2_set_match_limit_8(mcontext: *anyopaque, value: u32) callconv(.c) c_int;
    extern "c" fn pcre2_set_depth_limit_8(mcontext: *anyopaque, value: u32) callconv(.c) c_int;
    extern "c" fn pcre2_match_8(code: *const Code, subject: [*]const u8, length: usize, startoffset: usize, options: u32, match_data: *MatchData, mcontext: ?*anyopaque) callconv(.c) c_int;
    extern "c" fn pcre2_get_ovector_pointer_8(match_data: *MatchData) callconv(.c) [*]usize;
    extern "c" fn pcre2_pattern_info_8(code: *const Code, what: u32, where: *anyopaque) callconv(.c) c_int;
    extern "c" fn pcre2_get_mark_8(match_data: *MatchData) callconv(.c) ?[*:0]const u8;
    extern "c" fn pcre2_config_8(what: u32, where_: ?*anyopaque) callconv(.c) c_int;
};

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

const PREG_PATTERN_ORDER: i64 = 1;
const PREG_SET_ORDER: i64 = 2;
const PREG_OFFSET_CAPTURE: i64 = 1 << 8;
const PREG_UNMATCHED_AS_NULL: i64 = 1 << 9;
const PREG_SPLIT_NO_EMPTY: i64 = 1 << 0;
const PREG_SPLIT_DELIM_CAPTURE: i64 = 1 << 1;
const PREG_SPLIT_OFFSET_CAPTURE: i64 = 1 << 2;
const PREG_GREP_INVERT: i64 = 1 << 0;

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

// pcre's section of phpinfo() in text mode (PHP_MINFO_FUNCTION(pcre))
pub fn writeInfo(ctx: *NativeContext, out: *std.ArrayListUnmanaged(u8)) RuntimeError!void {
    const a = ctx.allocator;
    var unicode_buf: [32]u8 = undefined;
    const ul = pcre2.pcre2_config_8(10, &unicode_buf);
    const unicode = if (ul > 1) unicode_buf[0..@intCast(ul - 1)] else "";
    try out.print(a, "\npcre\n\nPCRE (Perl Compatible Regular Expressions) Support => enabled\nPCRE Library Version => {s}\nPCRE Unicode Version => {s}\n", .{ libVersion(), unicode });
    try out.print(a, "PCRE JIT Support => {s}\n", .{if (jitSupported()) "enabled" else "disabled"});
    var target_buf: [128]u8 = undefined;
    const tl = pcre2.pcre2_config_8(2, &target_buf);
    if (tl > 1) try out.print(a, "PCRE JIT Target => {s}\n", .{target_buf[0..@intCast(tl - 1)]});
    try out.appendSlice(a, "\nDirective => Local Value => Master Value\n");
    inline for (.{ .{ "pcre.backtrack_limit", "1000000" }, .{ "pcre.jit", "1" }, .{ "pcre.recursion_limit", "100000" } }) |ini| {
        const local = ctx.vm.ini_settings.get(ini[0]) orelse ini[1];
        try out.print(a, "{s} => {s} => {s}\n", .{ ini[0], local, ini[1] });
    }
}

// PCRE_JIT_SUPPORT
pub fn jitSupported() bool {
    var jit: u32 = 0;
    _ = pcre2.pcre2_config_8(pcre2.CONFIG_JIT, &jit);
    return jit != 0;
}

// ---------------------------------------------------------------------------
// errors (PCRE_G(error_code))

threadlocal var preg_error: i64 = 0;

const NO_ERROR: i64 = 0;
const INTERNAL_ERROR: i64 = 1;

// pcre_handle_exec_error
fn handleExecError(rc: c_int) void {
    preg_error = switch (rc) {
        pcre2.ERROR_MATCHLIMIT => 2,
        pcre2.ERROR_DEPTHLIMIT => 3,
        pcre2.ERROR_BADUTFOFFSET => 5,
        pcre2.ERROR_JIT_STACKLIMIT => 6,
        pcre2.ERROR_UTF8_ERR21...pcre2.ERROR_UTF8_ERR1 => 4,
        else => INTERNAL_ERROR,
    };
}

fn preg_last_error(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = preg_error });
}

fn preg_last_error_msg(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const msg: []const u8 = switch (preg_error) {
        0 => "No error",
        1 => "Internal error",
        2 => "Backtrack limit exhausted",
        3 => "Recursion limit exhausted",
        4 => "Malformed UTF-8 characters, possibly incorrectly encoded",
        5 => "The offset did not correspond to the beginning of a valid UTF-8 code point",
        6 => "JIT stack limit exhausted",
        else => "Unknown error",
    };
    return NativeResult.copyString(ctx.allocator, msg);
}

// ---------------------------------------------------------------------------
// matching

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

// pcre checks a utf subject from the start offset to the end on every match,
// so matching a long subject at many offsets costs quadratic time. as php
// does, a subject known to be valid utf-8 skips the check: it is validated
// once, and a string that owns its bytes remembers the result
fn utfKnownValid(subject: []const u8, holder: ?Value) bool {
    const owner: ?*Value.String.Owner = if (holder) |h| switch (h) {
        .string => |str| if (str.owner) |o| (if (str.ptr == o.bytes.ptr and str.len == o.bytes.len) o else null) else null,
        else => null,
    } else null;
    if (owner) |o| if (o.utf8_valid) return true;
    const valid = std.unicode.utf8ValidateSlice(subject);
    if (valid) if (owner) |o| {
        o.utf8_valid = true;
    };
    return valid;
}

// the options of a subject's first match: the utf check is skipped for a
// subject known valid, from the start of a code point (is_known_valid_utf8)
fn firstOptions(entry: *const Entry, subject: []const u8, holder: ?Value, offset: usize) u32 {
    if (entry.coptions & pcre2.UTF == 0) return pcre2.NO_UTF_CHECK;
    if (!utfKnownValid(subject, holder)) return 0;
    if (offset < subject.len and subject[offset] & 0xc0 == 0x80) return 0;
    return pcre2.NO_UTF_CHECK;
}

// calculate_unit_length: how far past an empty match the next attempt starts
fn unitLength(entry: *const Entry, subject: []const u8, at: usize) usize {
    if (entry.coptions & pcre2.UTF == 0) return 1;
    var end = at + 1;
    while (end < subject.len and subject[end] & 0xc0 == 0x80) end += 1;
    return end - at;
}

// ---------------------------------------------------------------------------
// the regex cache (pcre_get_compiled_regex_cache)

const Entry = struct {
    code: *pcre2.Code,
    coptions: u32,
    capture_count: u32,
    name_count: u32,
    // the group names by number, made the first time a match needs them;
    // the names point into the compiled code's name table
    names: ?[]?[]const u8 = null,

    fn destroy(self: *Entry) void {
        pcre2.pcre2_code_free_8(self.code);
        if (self.names) |n| std.heap.c_allocator.free(n);
        std.heap.c_allocator.destroy(self);
    }

    // make_subpats_table
    fn subpatNames(self: *Entry) RuntimeError!?[]?[]const u8 {
        if (self.name_count == 0) return null;
        if (self.names) |n| return n;
        var table: [*]const u8 = undefined;
        var entry_size: u32 = 0;
        _ = pcre2.pcre2_pattern_info_8(self.code, pcre2.INFO_NAMETABLE, @ptrCast(&table));
        _ = pcre2.pcre2_pattern_info_8(self.code, pcre2.INFO_NAMEENTRYSIZE, @ptrCast(&entry_size));
        const names = try std.heap.c_allocator.alloc(?[]const u8, self.capture_count + 1);
        @memset(names, null);
        for (0..self.name_count) |i| {
            const e = table + i * entry_size;
            const idx = (@as(usize, e[0]) << 8) | e[1];
            names[idx] = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(e + 2)), 0);
        }
        self.names = names;
        return names;
    }
};

// php's PCRE_CACHE_SIZE. past it a pattern is compiled for its call and
// freed after it: a cached code is never freed while a call (or a callback
// it runs) could be using it
const cache_size = 4096;
threadlocal var pattern_cache: std.StringHashMapUnmanaged(*Entry) = .empty;
threadlocal var compile_context: ?*anyopaque = null;

const Compiled = struct {
    entry: *Entry,
    owned: bool,

    fn release(self: Compiled) void {
        if (self.owned) self.entry.destroy();
    }
};

const Parsed = struct {
    pattern: []const u8,
    coptions: u32,
    eoptions: u32,
};

const Problem = union(enum) {
    empty,
    delimiter,
    no_end: u8,
    no_end_matching: u8,
    modifier: u8,
    compile: struct { code: c_int, offset: usize },
};

fn isSpace(c: u8) bool {
    return c == ' ' or (c >= '\t' and c <= '\r');
}

// the delimiters and modifiers of a regex
fn parseRegex(regex: []const u8) union(enum) { ok: Parsed, problem: Problem } {
    var p: usize = 0;
    while (p < regex.len and isSpace(regex[p])) p += 1;
    if (p >= regex.len) return .{ .problem = .empty };
    const start_delimiter = regex[p];
    p += 1;
    if (std.ascii.isAlphanumeric(start_delimiter) or start_delimiter == '\\' or start_delimiter == 0) return .{ .problem = .delimiter };
    const end_delimiter: u8 = switch (start_delimiter) {
        '(' => ')',
        '[' => ']',
        '{' => '}',
        '<' => '>',
        else => start_delimiter,
    };
    var pp = p;
    if (start_delimiter == end_delimiter) {
        while (pp < regex.len) : (pp += 1) {
            if (regex[pp] == '\\' and pp + 1 < regex.len) {
                pp += 1;
            } else if (regex[pp] == end_delimiter) break;
        }
    } else {
        var brackets: usize = 1;
        while (pp < regex.len) : (pp += 1) {
            if (regex[pp] == '\\' and pp + 1 < regex.len) {
                pp += 1;
            } else if (regex[pp] == end_delimiter) {
                brackets -= 1;
                if (brackets == 0) break;
            } else if (regex[pp] == start_delimiter) brackets += 1;
        }
    }
    if (pp >= regex.len) return .{ .problem = if (start_delimiter == end_delimiter) .{ .no_end = end_delimiter } else .{ .no_end_matching = end_delimiter } };
    var parsed: Parsed = .{ .pattern = regex[p..pp], .coptions = 0, .eoptions = 0 };
    for (regex[pp + 1 ..]) |m| {
        switch (m) {
            'i' => parsed.coptions |= pcre2.CASELESS,
            'm' => parsed.coptions |= pcre2.MULTILINE,
            'n' => parsed.coptions |= pcre2.NO_AUTO_CAPTURE,
            's' => parsed.coptions |= pcre2.DOTALL,
            'x' => parsed.coptions |= pcre2.EXTENDED,
            'A' => parsed.coptions |= pcre2.ANCHORED,
            'D' => parsed.coptions |= pcre2.DOLLAR_ENDONLY,
            'r' => parsed.eoptions |= pcre2.EXTRA_CASELESS_RESTRICT,
            'S', 'X' => {},
            'U' => parsed.coptions |= pcre2.UNGREEDY,
            // \C is unsafe in utf mode
            'u' => parsed.coptions |= pcre2.UTF | pcre2.UCP | pcre2.NEVER_BACKSLASH_C,
            'J' => parsed.coptions |= pcre2.DUPNAMES,
            ' ', '\n', '\r' => {},
            else => return .{ .problem = .{ .modifier = m } },
        }
    }
    return .{ .ok = parsed };
}

fn compileParsed(parsed: Parsed, err_code: *c_int, err_offset: *usize) ?*pcre2.Code {
    if (compile_context == null) compile_context = pcre2.pcre2_compile_context_create_8(null);
    const cctx = compile_context orelse return null;
    _ = pcre2.pcre2_set_compile_extra_options_8(cctx, parsed.eoptions);
    if (normalizeOpenBoundQuantifier(parsed.pattern)) |buf| {
        defer std.heap.c_allocator.free(buf);
        return pcre2.pcre2_compile_8(buf.ptr, buf.len, parsed.coptions, err_code, err_offset, cctx);
    }
    const bytes: [*]const u8 = if (parsed.pattern.len == 0) "" else parsed.pattern.ptr;
    return pcre2.pcre2_compile_8(bytes, parsed.pattern.len, parsed.coptions, err_code, err_offset, cctx);
}

// the warning text for a regex php refuses, without the function's name
fn problemText(problem: Problem, buf: []u8) []const u8 {
    return switch (problem) {
        .empty => "Empty regular expression",
        .delimiter => "Delimiter must not be alphanumeric, backslash, or NUL byte",
        .no_end => |c| std.fmt.bufPrint(buf, "No ending delimiter '{c}' found", .{c}) catch "",
        .no_end_matching => |c| std.fmt.bufPrint(buf, "No ending matching delimiter '{c}' found", .{c}) catch "",
        .modifier => |c| if (c == 0) "NUL byte is not a valid modifier" else std.fmt.bufPrint(buf, "Unknown modifier '{c}'", .{c}) catch "",
        .compile => |e| blk: {
            var msg_buf: [256]u8 = undefined;
            const msg: []const u8 = if (e.code == pcre2.ERROR_BACKSLASH_C_CALLER_DISABLED) "using \\C is incompatible with the 'u' modifier" else msg: {
                const n = pcre2.pcre2_get_error_message_8(e.code, &msg_buf, msg_buf.len);
                break :msg if (n > 0) msg_buf[0..@intCast(n)] else "";
            };
            break :blk std.fmt.bufPrint(buf, "Compilation failed: {s} at offset {d}", .{ msg, e.offset }) catch "";
        },
    };
}

// pcre_get_compiled_regex_cache: a regex php can't use is warned about as
// the running function's and leaves PREG_INTERNAL_ERROR
fn getCompiled(ctx: *NativeContext, func: []const u8, regex: []const u8) RuntimeError!?Compiled {
    if (pattern_cache.get(regex)) |entry| return .{ .entry = entry, .owned = false };
    var problem: ?Problem = null;
    var code: ?*pcre2.Code = null;
    var parsed: Parsed = undefined;
    switch (parseRegex(regex)) {
        .problem => |p| problem = p,
        .ok => |pr| {
            parsed = pr;
            var err_code: c_int = 0;
            var err_offset: usize = 0;
            code = compileParsed(pr, &err_code, &err_offset);
            if (code == null) problem = .{ .compile = .{ .code = err_code, .offset = err_offset } };
        },
    }
    if (problem) |p| {
        var buf: [512]u8 = undefined;
        const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): {s}", .{ func, problemText(p, &buf) });
        defer ctx.allocator.free(msg);
        try ctx.vm.emitWarning(msg);
        preg_error = INTERNAL_ERROR;
        return null;
    }
    const c = code.?;
    // as php does with pcre.jit on; a pattern the jit can't take still
    // matches through the interpreter
    if (iniLimit(ctx, "pcre.jit", 1) != 0) _ = pcre2.pcre2_jit_compile_8(c, pcre2.JIT_COMPLETE);
    const entry = std.heap.c_allocator.create(Entry) catch {
        pcre2.pcre2_code_free_8(c);
        return error.OutOfMemory;
    };
    entry.* = .{ .code = c, .coptions = parsed.coptions, .capture_count = 0, .name_count = 0 };
    _ = pcre2.pcre2_pattern_info_8(c, pcre2.INFO_CAPTURECOUNT, @ptrCast(&entry.capture_count));
    _ = pcre2.pcre2_pattern_info_8(c, pcre2.INFO_NAMECOUNT, @ptrCast(&entry.name_count));
    if (pattern_cache.count() < cache_size) {
        const key = std.heap.c_allocator.dupe(u8, regex) catch return .{ .entry = entry, .owned = true };
        pattern_cache.put(std.heap.c_allocator, key, entry) catch {
            std.heap.c_allocator.free(key);
            return .{ .entry = entry, .owned = true };
        };
        return .{ .entry = entry, .owned = false };
    }
    return .{ .entry = entry, .owned = true };
}

// what php's pcre_get_compiled_regex_cache warns about a regex it can't
// use, without the function prefix; null for a usable one. the caller owns
// the message
pub fn patternProblem(ctx: *NativeContext, regex: []const u8) RuntimeError!?[]u8 {
    switch (parseRegex(regex)) {
        .problem => |p| {
            var buf: [512]u8 = undefined;
            return try ctx.allocator.dupe(u8, problemText(p, &buf));
        },
        .ok => |parsed| {
            var err_code: c_int = 0;
            var err_offset: usize = 0;
            if (compileParsed(parsed, &err_code, &err_offset)) |code| {
                pcre2.pcre2_code_free_8(code);
                return null;
            }
            var buf: [512]u8 = undefined;
            return try ctx.allocator.dupe(u8, problemText(.{ .compile = .{ .code = err_code, .offset = err_offset } }, &buf));
        },
    }
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

// a compiled pattern for mb_split and mb_ereg_match, which name their
// options themselves
fn compileRaw(ctx: *NativeContext, pattern: []const u8, coptions: u32) ?Compiled {
    var key_buf: [260]u8 = undefined;
    if (pattern.len + 5 <= key_buf.len) {
        key_buf[0] = 0;
        std.mem.writeInt(u32, key_buf[1..5], coptions, .little);
        @memcpy(key_buf[5..][0..pattern.len], pattern);
        if (pattern_cache.get(key_buf[0 .. pattern.len + 5])) |entry| return .{ .entry = entry, .owned = false };
    }
    var err_code: c_int = 0;
    var err_offset: usize = 0;
    const code = compileParsed(.{ .pattern = pattern, .coptions = coptions, .eoptions = 0 }, &err_code, &err_offset) orelse return null;
    if (iniLimit(ctx, "pcre.jit", 1) != 0) _ = pcre2.pcre2_jit_compile_8(code, pcre2.JIT_COMPLETE);
    const entry = std.heap.c_allocator.create(Entry) catch {
        pcre2.pcre2_code_free_8(code);
        return null;
    };
    entry.* = .{ .code = code, .coptions = coptions, .capture_count = 0, .name_count = 0 };
    _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_CAPTURECOUNT, @ptrCast(&entry.capture_count));
    if (pattern.len + 5 <= key_buf.len and pattern_cache.count() < cache_size) {
        const key = std.heap.c_allocator.dupe(u8, key_buf[0 .. pattern.len + 5]) catch return .{ .entry = entry, .owned = true };
        pattern_cache.put(std.heap.c_allocator, key, entry) catch {
            std.heap.c_allocator.free(key);
            return .{ .entry = entry, .owned = true };
        };
        return .{ .entry = entry, .owned = false };
    }
    return .{ .entry = entry, .owned = true };
}

// ---------------------------------------------------------------------------
// match arrays

fn subjectString(ctx: *NativeContext, subject: []const u8, start: usize, end: usize) RuntimeError!Value {
    return .{ .string = try Value.String.create(ctx.allocator, subject[start..end]) };
}

// a value appended to an array the array now holds
fn appendOwned(ctx: *NativeContext, arr: *PhpArray, v: Value) RuntimeError!void {
    try arr.append(ctx.allocator, v);
    if (v == .string) v.string.release();
}

// populate_match_value
fn matchValue(ctx: *NativeContext, subject: []const u8, ov: [*]const usize, i: usize, unmatched_as_null: bool) RuntimeError!Value {
    if (ov[2 * i] == pcre2.UNSET) return if (unmatched_as_null) .null else .{ .string = Value.String.borrowed("") };
    return subjectString(ctx, subject, ov[2 * i], ov[2 * i + 1]);
}

// the (match, offset) pair of add_offset_pair
fn offsetPair(ctx: *NativeContext, subject: []const u8, start: usize, end: usize, unmatched_as_null: bool) RuntimeError!Value {
    const pair = try ctx.createArray();
    if (start == pcre2.UNSET) {
        try pair.append(ctx.allocator, if (unmatched_as_null) .null else .{ .string = Value.String.borrowed("") });
        try pair.append(ctx.allocator, .{ .int = -1 });
    } else {
        try appendOwned(ctx, pair, try subjectString(ctx, subject, start, end));
        try pair.append(ctx.allocator, .{ .int = @intCast(start) });
    }
    return .{ .array = pair };
}

// add_named: with duplicate names the group that matched wins
fn addNamed(ctx: *NativeContext, arr: *PhpArray, name: []const u8, v: Value, unmatched: bool) RuntimeError!void {
    const key = try Value.String.create(ctx.allocator, name);
    defer key.release();
    if (unmatched and arr.contains(.{ .string = key })) return;
    try arr.set(ctx.allocator, .{ .string = key }, v);
}

fn addMark(ctx: *NativeContext, arr: *PhpArray, md: *pcre2.MatchData) RuntimeError!void {
    const mark = pcre2.pcre2_get_mark_8(md) orelse return;
    const s = try Value.String.create(ctx.allocator, std.mem.sliceTo(mark, 0));
    defer s.release();
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("MARK") }, .{ .string = s });
}

// populate_subpat_array
fn populateSubpats(ctx: *NativeContext, arr: *PhpArray, subject: []const u8, ov: [*]const usize, names: ?[]?[]const u8, num_subpats: usize, count: usize, md: *pcre2.MatchData, flags: i64) RuntimeError!void {
    const offset_capture = flags & PREG_OFFSET_CAPTURE != 0;
    const unmatched_as_null = flags & PREG_UNMATCHED_AS_NULL != 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const v = if (offset_capture) try offsetPair(ctx, subject, ov[2 * i], ov[2 * i + 1], unmatched_as_null) else try matchValue(ctx, subject, ov, i, unmatched_as_null);
        if (names) |n| if (n[i]) |name| try addNamed(ctx, arr, name, v, ov[2 * i] == pcre2.UNSET);
        try appendOwned(ctx, arr, v);
    }
    if (unmatched_as_null) {
        while (i < num_subpats) : (i += 1) {
            const v = if (offset_capture) try offsetPair(ctx, subject, pcre2.UNSET, pcre2.UNSET, true) else Value.null;
            if (names) |n| if (n[i]) |name| try addNamed(ctx, arr, name, v, true);
            try arr.append(ctx.allocator, v);
        }
    }
    try addMark(ctx, arr, md);
}

fn countFrom(rc: c_int, num_subpats: usize) usize {
    // "Matched, but too many substrings" can't happen: the match data comes
    // from the pattern
    return if (rc == 0) num_subpats else @intCast(rc);
}

// ---------------------------------------------------------------------------
// preg_match, preg_match_all

fn preg_match(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return doMatch(ctx, args, false);
}

fn preg_match_all(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return doMatch(ctx, args, true);
}

// php_do_pcre_match
fn doMatch(ctx: *NativeContext, args: []const Value, global: bool) RuntimeError!NativeResult {
    const func: []const u8 = if (global) "preg_match_all" else "preg_match";
    const p = Args.init(ctx, func, args);
    const regex = try p.str(0, "pattern");
    const subject = try p.str(1, "subject");
    const want_matches = args.len > 2;
    const flags = try p.optLong(3, "flags", 0);
    const start_offset = try p.optLong(4, "offset", 0);
    const compiled = (try getCompiled(ctx, func, regex)) orelse return NativeResult.scalar(.{ .bool = false });
    defer compiled.release();
    if (start_offset == std.math.minInt(i64)) return throwFmt(ctx, "ValueError", "{s}(): Argument #5 ($offset) must be greater than {d}", .{ func, std.math.minInt(i64) });
    return matchImpl(ctx, compiled.entry, subject, args[1], want_matches, args.len, global, flags, start_offset);
}

fn throwFmt(ctx: *NativeContext, class: []const u8, comptime fmt: []const u8, fargs: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, fargs);
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException(class, msg);
    return error.RuntimeError;
}

// php_pcre_match_impl
fn matchImpl(ctx: *NativeContext, entry: *Entry, subject: []const u8, holder: Value, want_matches: bool, arg_count: usize, global: bool, flags: i64, start_offset: i64) RuntimeError!NativeResult {
    const a = ctx.allocator;
    // the output variable gets a new array; the one it held may be shared
    const subpats: ?*PhpArray = if (want_matches) try ctx.createArray() else null;
    if (subpats) |s| ctx.setCallerVar(2, arg_count, .{ .array = s });
    var order: i64 = if (global) PREG_PATTERN_ORDER else 0;
    if (flags & 0xff != 0) {
        order = flags & 0xff;
        if ((global and (order < PREG_PATTERN_ORDER or order > PREG_SET_ORDER)) or (!global and order != 0)) {
            const func: []const u8 = if (global) "preg_match_all" else "preg_match";
            return throwFmt(ctx, "ValueError", "{s}(): Argument #4 ($flags) must be a PREG_* constant", .{func});
        }
    }
    const offset_capture = flags & PREG_OFFSET_CAPTURE != 0;
    const unmatched_as_null = flags & PREG_UNMATCHED_AS_NULL != 0;

    var offset: usize = if (start_offset < 0)
        (if (@as(u64, @intCast(-start_offset)) <= subject.len) subject.len - @as(usize, @intCast(-start_offset)) else 0)
    else
        @intCast(@min(start_offset, std.math.maxInt(i64)));
    if (offset > subject.len) {
        handleExecError(pcre2.ERROR_BADOFFSET);
        return NativeResult.scalar(.{ .bool = false });
    }
    const num_subpats: usize = entry.capture_count + 1;
    const names = if (subpats != null) try entry.subpatNames() else null;
    preg_error = NO_ERROR;
    const md = pcre2.pcre2_match_data_create_from_pattern_8(entry.code, null) orelse {
        preg_error = INTERNAL_ERROR;
        return NativeResult.scalar(.{ .bool = false });
    };
    defer pcre2.pcre2_match_data_free_8(md);

    // the per-group arrays of PREG_PATTERN_ORDER
    var match_sets: ?[]*PhpArray = null;
    defer if (match_sets) |sets| a.free(sets);
    if (global and subpats != null and order == PREG_PATTERN_ORDER) {
        const sets = try a.alloc(*PhpArray, num_subpats);
        for (sets) |*s| s.* = try ctx.createArray();
        match_sets = sets;
    }
    var marks: ?*PhpArray = null;
    const ov = pcre2.pcre2_get_ovector_pointer_8(md);
    var matched: i64 = 0;
    var rc = exec(ctx, entry.code, subject, offset, firstOptions(entry, subject, holder, offset), md);
    while (true) {
        if (rc >= 0) {
            var count = countFrom(rc, num_subpats);
            while (true) {
                matched += 1;
                if (subpats) |out| {
                    if (global) {
                        if (match_sets) |sets| {
                            for (0..count) |i| try appendOwned(ctx, sets[i], if (offset_capture) try offsetPair(ctx, subject, ov[2 * i], ov[2 * i + 1], unmatched_as_null) else try matchValue(ctx, subject, ov, i, unmatched_as_null));
                            if (pcre2.pcre2_get_mark_8(md)) |mark| {
                                if (marks == null) marks = try ctx.createArray();
                                const s = try Value.String.create(a, std.mem.sliceTo(mark, 0));
                                defer s.release();
                                try marks.?.set(a, .{ .int = matched - 1 }, .{ .string = s });
                            }
                            // groups past the last that took part are padded
                            for (count..num_subpats) |i| {
                                const v: Value = if (offset_capture) try offsetPair(ctx, subject, pcre2.UNSET, pcre2.UNSET, unmatched_as_null) else if (unmatched_as_null) .null else .{ .string = Value.String.borrowed("") };
                                try sets[i].append(a, v);
                            }
                        } else {
                            const set = try ctx.createArray();
                            try populateSubpats(ctx, set, subject, ov, names, num_subpats, count, md, flags);
                            try out.append(a, .{ .array = set });
                        }
                    } else {
                        try populateSubpats(ctx, out, subject, ov, names, num_subpats, count, md, flags);
                        break;
                    }
                }
                // an empty match is tried again where it is, as long as it
                // isn't empty; if that fails the search moves one character
                offset = ov[1];
                if (offset != ov[0]) break;
                rc = exec(ctx, entry.code, subject, offset, pcre2.NO_UTF_CHECK | pcre2.NOTEMPTY_ATSTART | pcre2.ANCHORED, md);
                if (rc >= 0) {
                    if (!global) break;
                    count = countFrom(rc, num_subpats);
                    continue;
                }
                if (rc == pcre2.ERROR_NOMATCH) {
                    if (offset < subject.len) {
                        offset += unitLength(entry, subject, offset);
                        rc = 0;
                    }
                } else {
                    handleExecError(rc);
                }
                break;
            }
            // a failed retry at the end of the subject, or an error
            if (rc < 0) break;
        } else {
            if (rc != pcre2.ERROR_NOMATCH) handleExecError(rc);
            break;
        }
        if (!global or (subpats != null and !global)) break;
        rc = exec(ctx, entry.code, subject, offset, pcre2.NO_UTF_CHECK, md);
    }

    if (match_sets) |sets| {
        const out = subpats.?;
        for (sets, 0..) |set, i| {
            if (names) |n| if (n[i]) |name| {
                const key = try Value.String.create(a, name);
                defer key.release();
                try out.set(a, .{ .string = key }, .{ .array = set });
            };
            try out.append(a, .{ .array = set });
        }
        if (marks) |m| try out.set(a, .{ .string = Value.String.borrowed("MARK") }, .{ .array = m });
    }
    if (preg_error != NO_ERROR) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = matched });
}

// ---------------------------------------------------------------------------
// replacing

// preg_get_backref: \n, $n or ${n}, one or two digits
fn getBackref(s: []const u8, at: *usize) ?usize {
    var walk = at.*;
    if (walk + 1 >= s.len or s[walk + 1] == 0) return null;
    var in_brace = false;
    if (s[walk] == '$' and s[walk + 1] == '{') {
        in_brace = true;
        walk += 1;
    }
    walk += 1;
    if (walk >= s.len or !std.ascii.isDigit(s[walk])) return null;
    var backref: usize = s[walk] - '0';
    walk += 1;
    if (walk < s.len and std.ascii.isDigit(s[walk])) {
        backref = backref * 10 + (s[walk] - '0');
        walk += 1;
    }
    if (in_brace) {
        if (walk >= s.len or s[walk] != '}') return null;
        walk += 1;
    }
    at.* = walk;
    return backref;
}

// the replacement of one match, with its backreferences and escapes
fn appendReplacement(out: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, replace: []const u8, subject: []const u8, ov: [*]const usize, count: usize) RuntimeError!void {
    if (std.mem.indexOfAny(u8, replace, "\\$") == null) return out.appendSlice(a, replace);
    var walk: usize = 0;
    var walk_last: u8 = 0;
    while (walk < replace.len) {
        const c = replace[walk];
        if (c == '\\' or c == '$') {
            if (walk_last == '\\') {
                out.items[out.items.len - 1] = c;
                walk += 1;
                walk_last = 0;
                continue;
            }
            if (getBackref(replace, &walk)) |backref| {
                if (backref < count and ov[2 * backref] != pcre2.UNSET) try out.appendSlice(a, subject[ov[2 * backref]..ov[2 * backref + 1]]);
                continue;
            }
        }
        try out.append(a, c);
        walk += 1;
        walk_last = c;
    }
}

const Replacer = union(enum) {
    string: []const u8,
    callback: struct { callable: Value, flags: i64 },
};

// php_pcre_replace_impl and php_pcre_replace_func_impl: null when the
// match failed (or the callback threw)
fn replaceImpl(ctx: *NativeContext, entry: *Entry, subject: []const u8, holder: ?Value, replacer: Replacer, limit_in: usize, replace_count: *i64) RuntimeError!?Value.String {
    const a = ctx.allocator;
    var limit = limit_in;
    const num_subpats: usize = entry.capture_count + 1;
    const names = if (replacer == .callback) try entry.subpatNames() else null;
    preg_error = NO_ERROR;
    const md = pcre2.pcre2_match_data_create_from_pattern_8(entry.code, null) orelse {
        preg_error = INTERNAL_ERROR;
        return null;
    };
    defer pcre2.pcre2_match_data_free_8(md);
    const ov = pcre2.pcre2_get_ovector_pointer_8(md);
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(a);
    var replaced = false;
    var start_offset: usize = 0;
    var last_end: usize = 0;
    var rc = exec(ctx, entry.code, subject, 0, firstOptions(entry, subject, holder, 0), md);
    while (true) {
        if (rc >= 0 and limit > 0) {
            var count = countFrom(rc, num_subpats);
            while (true) {
                replace_count.* += 1;
                replaced = true;
                try out.appendSlice(a, subject[last_end..ov[0]]);
                switch (replacer) {
                    .string => |r| try appendReplacement(&out, a, r, subject, ov, count),
                    .callback => |cb| {
                        // a callback that threw fails this subject; the
                        // caller raises the exception once it has gone
                        // through the rest (preg_do_repl_func)
                        if (ctx.vm.pending_exception != null) {
                            preg_error = INTERNAL_ERROR;
                            return null;
                        }
                        const arg = try ctx.createArray();
                        try populateSubpats(ctx, arg, subject, ov, names, num_subpats, count, md, cb.flags);
                        const result = ctx.invokeCallable(cb.callable, &.{.{ .array = arg }}) catch |err| {
                            // anything but a thrown exception (exit, a fiber
                            // switching away) unwinds through the call
                            if (err == error.OutOfMemory or ctx.vm.pending_exception == null) return err;
                            preg_error = INTERNAL_ERROR;
                            return null;
                        };
                        if (result == .string) {
                            try out.appendSlice(a, result.string.bytes());
                        } else {
                            var buf: [128]u8 = undefined;
                            const s = array_diff.tmpString(ctx, result, &buf) catch |err| {
                                if (err == error.OutOfMemory) return err;
                                preg_error = INTERNAL_ERROR;
                                return null;
                            };
                            defer s.release(ctx);
                            try out.appendSlice(a, s.bytes);
                        }
                    },
                }
                limit -= 1;
                start_offset = ov[1];
                last_end = ov[1];
                if (start_offset != ov[0]) break;
                // an empty match: tried again where it is, as long as it
                // isn't empty, else the search moves one character on
                rc = exec(ctx, entry.code, subject, start_offset, pcre2.NO_UTF_CHECK | pcre2.NOTEMPTY_ATSTART | pcre2.ANCHORED, md);
                if (rc >= 0 and limit > 0) {
                    count = countFrom(rc, num_subpats);
                    continue;
                }
                if (rc == pcre2.ERROR_NOMATCH or limit == 0) {
                    if (start_offset < subject.len) {
                        start_offset += unitLength(entry, subject, start_offset);
                        rc = 0;
                    } else {
                        rc = pcre2.ERROR_NOMATCH;
                    }
                } else {
                    handleExecError(rc);
                    return null;
                }
                break;
            }
            if (rc == pcre2.ERROR_NOMATCH) {
                // the end of the subject after an empty match
                try out.appendSlice(a, subject[last_end..]);
                return try Value.String.create(a, out.items);
            }
        } else if (rc == pcre2.ERROR_NOMATCH or limit == 0) {
            if (!replaced) return try Value.String.create(a, subject);
            try out.appendSlice(a, subject[last_end..]);
            return try Value.String.create(a, out.items);
        } else {
            handleExecError(rc);
            return null;
        }
        rc = exec(ctx, entry.code, subject, start_offset, pcre2.NO_UTF_CHECK, md);
    }
}

// zval_get_tmp_string's bytes, kept alive for the call
fn tmpBytes(ctx: *NativeContext, v_in: Value) RuntimeError![]const u8 {
    const v = v_in;
    if (v == .string) return v.string.bytes();
    var buf: [128]u8 = undefined;
    const s = try array_diff.tmpString(ctx, v, &buf);
    defer s.release(ctx);
    // zval_try_get_string: an object without __toString, one whose
    // __toString threw, or any conversion while an exception is pending
    if (ctx.vm.pending_exception != null) return error.RuntimeError;
    return (try ctx.vm.transientBytes(s.bytes)).bytes();
}

fn entryValue(e: PhpArray.Entry) Value {
    return if (e.ref) |cell| cell.* else e.value;
}

// php_pcre_replace: a regex compiled (or warned about) and applied
fn replaceOne(ctx: *NativeContext, func: []const u8, regex: []const u8, subject: []const u8, holder: ?Value, replacer: Replacer, limit: usize, replace_count: *i64) RuntimeError!?Value.String {
    // php_pcre_replace aborts on a pending exception (a __toString that threw)
    if (replacer == .string and ctx.vm.pending_exception != null) return null;
    const compiled = (try getCompiled(ctx, func, regex)) orelse return null;
    defer compiled.release();
    return replaceImpl(ctx, compiled.entry, subject, holder, replacer, limit, replace_count);
}

// php_replace_in_subject / php_replace_in_subject_func: every regex of an
// array applied in turn, each to the last one's result
fn replaceInSubject(ctx: *NativeContext, func: []const u8, regex: Value, replacement: ?Value, callback: ?Value, cb_flags: i64, subject: []const u8, holder: ?Value, limit: usize, replace_count: *i64) RuntimeError!?Value.String {
    if (regex != .array) {
        const replacer: Replacer = if (callback) |cb| .{ .callback = .{ .callable = cb, .flags = cb_flags } } else .{ .string = replacement.?.string.bytes() };
        return replaceOne(ctx, func, regex.string.bytes(), subject, holder, replacer, limit, replace_count);
    }
    var current = try Value.String.create(ctx.allocator, subject);
    var replace_idx: usize = 0;
    for (regex.array.entries.items) |e| {
        const regex_bytes = tmpBytes(ctx, entryValue(e)) catch |err| {
            // the callback form stops at a regex that won't convert and
            // keeps what it has (php_replace_in_subject_func)
            if (callback != null and ctx.vm.pending_exception != null) return current;
            current.release();
            return err;
        };
        var replacer: Replacer = undefined;
        if (callback) |cb| {
            replacer = .{ .callback = .{ .callable = cb, .flags = cb_flags } };
        } else if (replacement.? == .array) {
            const items = replacement.?.array.entries.items;
            const r: []const u8 = if (replace_idx < items.len) (tmpBytes(ctx, entryValue(items[replace_idx])) catch |err| {
                current.release();
                return err;
            }) else "";
            replace_idx += 1;
            replacer = .{ .string = r };
        } else {
            replacer = .{ .string = replacement.?.string.bytes() };
        }
        const next = replaceOne(ctx, func, regex_bytes, current.bytes(), .{ .string = current }, replacer, limit, replace_count) catch |err| {
            current.release();
            return err;
        };
        current.release();
        current = next orelse return null;
    }
    return current;
}

fn limitArg(limit: i64) usize {
    return if (limit < 0) std.math.maxInt(usize) else @intCast(limit);
}

// preg_replace_common
fn replaceCommon(ctx: *NativeContext, args: []const Value, comptime func: []const u8, is_filter: bool) RuntimeError!NativeResult {
    const p = Args.init(ctx, func, args);
    const regex = try regexOrArray(p, 0, "pattern");
    const replacement = try regexOrArray(p, 1, "replacement");
    const subject = try regexOrArray(p, 2, "subject");
    const limit = limitArg(try p.optLong(3, "limit", -1));
    if (replacement == .array and regex != .array) return throwFmt(ctx, "TypeError", func ++ "(): Argument #1 ($pattern) must be of type array when argument #2 ($replacement) is an array, string given", .{});
    var replace_count: i64 = 0;
    var result: NativeResult = undefined;
    if (subject != .array) {
        const r = try replaceInSubject(ctx, func, regex, replacement, null, 0, subject.string.bytes(), args[2], limit, &replace_count);
        if (r) |s| {
            if (!is_filter or replace_count > 0) {
                result = NativeResult.takeString(s);
            } else {
                s.release();
                result = NativeResult.scalar(.null);
            }
        } else result = NativeResult.scalar(.null);
    } else {
        const out = try ctx.createArray();
        for (subject.array.entries.items) |e| {
            const old_count = replace_count;
            const v = entryValue(e);
            const bytes = try tmpBytes(ctx, v);
            const r = (try replaceInSubject(ctx, func, regex, replacement, null, 0, bytes, v, limit, &replace_count)) orelse continue;
            defer r.release();
            if (!is_filter or replace_count > old_count) try out.set(ctx.allocator, e.key, .{ .string = r });
        }
        result = NativeResult.borrowed(.{ .array = out });
    }
    if (args.len > 4) ctx.setCallerVar(4, args.len, .{ .int = replace_count });
    if (ctx.vm.pending_exception != null) {
        dropResult(ctx, result.value);
        return error.RuntimeError;
    }
    return result;
}

// Z_PARAM_ARRAY_HT_OR_STR as a Value: the array, or a string the call
// keeps alive
fn regexOrArray(p: Args, index: usize, name: []const u8) RuntimeError!Value {
    if (index < p.args.len and p.args[index] == .array) return p.args[index];
    if (index < p.args.len and p.args[index] == .string) return p.args[index];
    const s = try p.strAs(index, name, "array|string");
    return .{ .string = try p.ctx.vm.transientBytes(s) };
}

fn preg_replace(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return replaceCommon(ctx, args, "preg_replace", false);
}

fn preg_filter(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return replaceCommon(ctx, args, "preg_filter", true);
}

// php_preg_replace_func_impl: the string result, or the array of results
// for an array subject; null when the replacement failed
fn replaceFuncImpl(ctx: *NativeContext, func: []const u8, regex: Value, callback: Value, subject: Value, limit: usize, flags: i64, replace_count: *i64) RuntimeError!Value {
    if (subject != .array) {
        const r = (try replaceInSubject(ctx, func, regex, null, callback, flags, subject.string.bytes(), subject, limit, replace_count)) orelse return .null;
        return .{ .string = r };
    }
    const out = try ctx.createArray();
    for (subject.array.entries.items) |e| {
        const v = entryValue(e);
        const bytes = tmpBytes(ctx, v) catch |err| {
            if (ctx.vm.pending_exception != null) break;
            return err;
        };
        const r = (try replaceInSubject(ctx, func, regex, null, callback, flags, bytes, v, limit, replace_count)) orelse continue;
        defer r.release();
        try out.set(ctx.allocator, e.key, .{ .string = r });
    }
    return .{ .array = out };
}

fn preg_replace_callback(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "preg_replace_callback", args);
    const regex = try regexOrArray(p, 0, "pattern");
    const subject = try regexOrArray(p, 2, "subject");
    const limit = limitArg(try p.optLong(3, "limit", -1));
    const flags = try p.optLong(5, "flags", 0);
    var replace_count: i64 = 0;
    const result = try replaceFuncImpl(ctx, "preg_replace_callback", regex, args[1], subject, limit, flags, &replace_count);
    if (args.len > 4) ctx.setCallerVar(4, args.len, .{ .int = replace_count });
    if (ctx.vm.pending_exception != null) {
        dropResult(ctx, result);
        return error.RuntimeError;
    }
    if (result == .string) return NativeResult.takeString(result.string);
    return NativeResult.borrowed(result);
}

fn preg_replace_callback_array(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "preg_replace_callback_array", args);
    const patterns: *PhpArray = if (args.len > 0 and args[0] == .array) args[0].array else return p.typeError(0, "pattern", "array");
    // the current subject: the argument, then each pattern's result, which
    // this call owns
    var current = try regexOrArray(p, 1, "subject");
    var owned = false;
    defer if (owned) dropResult(ctx, current);
    const limit = limitArg(try p.optLong(2, "limit", -1));
    const flags = try p.optLong(4, "flags", 0);
    var replace_count: i64 = 0;
    for (patterns.entries.items) |e| {
        if (e.key != .string) return throwFmt(ctx, "TypeError", "preg_replace_callback_array(): Argument #1 ($pattern) must contain only string patterns as keys", .{});
        const callback = entryValue(e);
        const resolution = try callables.resolveCallback(ctx.vm, callback, .{});
        if (ctx.vm.pending_exception != null) return error.RuntimeError;
        if (resolution != .callee) return throwFmt(ctx, "TypeError", "preg_replace_callback_array(): Argument #1 ($pattern) must contain only valid callbacks", .{});
        const next = try replaceFuncImpl(ctx, "preg_replace_callback_array", .{ .string = e.key.string }, callback, current, limit, flags, &replace_count);
        if (owned) dropResult(ctx, current);
        current = next;
        owned = true;
        if (ctx.vm.pending_exception != null) return error.RuntimeError;
        if (next == .null) return NativeResult.scalar(.null);
    }
    if (args.len > 3) ctx.setCallerVar(3, args.len, .{ .int = replace_count });
    if (!owned) return NativeResult.share(current);
    owned = false;
    if (current == .string) return NativeResult.takeString(current.string);
    return NativeResult.borrowed(current);
}

fn dropResult(ctx: *NativeContext, v: Value) void {
    if (v == .string) v.string.release() else ctx.vm.discardOrphan(v);
}

// ---------------------------------------------------------------------------
// preg_split

fn preg_split(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "preg_split", args);
    const regex = try p.str(0, "pattern");
    const subject = try p.str(1, "subject");
    var limit = try p.optLong(2, "limit", -1);
    const flags = try p.optLong(3, "flags", 0);
    const compiled = (try getCompiled(ctx, "preg_split", regex)) orelse return NativeResult.scalar(.{ .bool = false });
    defer compiled.release();
    const entry = compiled.entry;
    const a = ctx.allocator;
    const no_empty = flags & PREG_SPLIT_NO_EMPTY != 0;
    const delim_capture = flags & PREG_SPLIT_DELIM_CAPTURE != 0;
    const offset_capture = flags & PREG_SPLIT_OFFSET_CAPTURE != 0;
    const out = try ctx.createArray();
    preg_error = NO_ERROR;
    var last_match: usize = 0;
    if (limit == 0) limit = -1;
    if (limit == -1 or limit > 1) {
        const md = pcre2.pcre2_match_data_create_from_pattern_8(entry.code, null) orelse {
            preg_error = INTERNAL_ERROR;
            return NativeResult.scalar(.{ .bool = false });
        };
        defer pcre2.pcre2_match_data_free_8(md);
        const ov = pcre2.pcre2_get_ovector_pointer_8(md);
        var start_offset: usize = 0;
        var rc = exec(ctx, entry.code, subject, 0, firstOptions(entry, subject, args[1], 0), md);
        outer: while (true) {
            if (rc >= 0) {
                var count = countFrom(rc, entry.capture_count + 1);
                while (true) {
                    if (!no_empty or ov[0] != last_match) {
                        if (offset_capture) {
                            try out.append(a, try offsetPair(ctx, subject, last_match, ov[0], false));
                        } else {
                            try appendOwned(ctx, out, try subjectString(ctx, subject, last_match, ov[0]));
                        }
                        if (limit != -1) limit -= 1;
                    }
                    if (delim_capture) {
                        for (1..count) |i| {
                            if (!no_empty or ov[2 * i] != ov[2 * i + 1]) {
                                const s = ov[2 * i];
                                const e = ov[2 * i + 1];
                                if (offset_capture) {
                                    try out.append(a, try offsetPair(ctx, subject, s, e, false));
                                } else if (s == pcre2.UNSET) {
                                    try out.append(a, .{ .string = Value.String.borrowed("") });
                                } else {
                                    try appendOwned(ctx, out, try subjectString(ctx, subject, s, e));
                                }
                            }
                        }
                    }
                    start_offset = ov[1];
                    last_match = ov[1];
                    if (start_offset != ov[0]) break;
                    if (limit != -1 and limit <= 1) break :outer;
                    rc = exec(ctx, entry.code, subject, start_offset, pcre2.NO_UTF_CHECK | pcre2.NOTEMPTY_ATSTART | pcre2.ANCHORED, md);
                    if (rc >= 0) {
                        count = countFrom(rc, entry.capture_count + 1);
                        continue;
                    }
                    if (rc == pcre2.ERROR_NOMATCH) {
                        if (start_offset < subject.len) {
                            start_offset += unitLength(entry, subject, start_offset);
                        } else break :outer;
                    } else {
                        handleExecError(rc);
                        break :outer;
                    }
                    break;
                }
            } else {
                if (rc != pcre2.ERROR_NOMATCH) handleExecError(rc);
                break;
            }
            if (limit != -1 and limit <= 1) break;
            rc = exec(ctx, entry.code, subject, start_offset, pcre2.NO_UTF_CHECK, md);
        }
        if (preg_error != NO_ERROR) {
            ctx.vm.discardOrphan(.{ .array = out });
            return NativeResult.scalar(.{ .bool = false });
        }
    }
    // the last piece, from the end of the last match
    if (!no_empty or last_match < subject.len) {
        if (offset_capture) {
            try out.append(a, try offsetPair(ctx, subject, last_match, subject.len, false));
        } else if (last_match == 0 and args[1] == .string) {
            try out.append(a, args[1]);
        } else {
            try appendOwned(ctx, out, try subjectString(ctx, subject, last_match, subject.len));
        }
    }
    return NativeResult.borrowed(.{ .array = out });
}

// ---------------------------------------------------------------------------
// preg_quote, preg_grep

fn preg_quote(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "preg_quote", args);
    const str = try p.str(0, "str");
    const delim = try p.strOrNull(1, "delimiter");
    if (str.len == 0) return NativeResult.copyString(ctx.allocator, "");
    const delim_char: u8 = if (delim) |d| (if (d.len > 0) d[0] else 0) else 0;
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(ctx.allocator);
    try out.ensureTotalCapacity(ctx.allocator, str.len);
    for (str) |c| {
        switch (c) {
            '.', '\\', '+', '*', '?', '[', '^', ']', '$', '(', ')', '{', '}', '=', '!', '>', '<', '|', ':', '-', '#' => {
                try out.append(ctx.allocator, '\\');
                try out.append(ctx.allocator, c);
            },
            0 => try out.appendSlice(ctx.allocator, "\\000"),
            else => {
                if (c == delim_char) try out.append(ctx.allocator, '\\');
                try out.append(ctx.allocator, c);
            },
        }
    }
    return NativeResult.copyString(ctx.allocator, out.items);
}

fn preg_grep(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "preg_grep", args);
    const regex = try p.str(0, "pattern");
    const input: *PhpArray = if (args.len > 1 and args[1] == .array) args[1].array else return p.typeError(1, "array", "array");
    const flags = try p.optLong(2, "flags", 0);
    const compiled = (try getCompiled(ctx, "preg_grep", regex)) orelse return NativeResult.scalar(.{ .bool = false });
    defer compiled.release();
    const entry = compiled.entry;
    const invert = flags & PREG_GREP_INVERT != 0;
    const out = try ctx.createArray();
    preg_error = NO_ERROR;
    const md = pcre2.pcre2_match_data_create_from_pattern_8(entry.code, null) orelse {
        preg_error = INTERNAL_ERROR;
        return NativeResult.borrowed(.{ .array = out });
    };
    defer pcre2.pcre2_match_data_free_8(md);
    for (input.entries.items) |e| {
        const v = entryValue(e);
        const bytes = try tmpBytes(ctx, v);
        const rc = exec(ctx, entry.code, bytes, 0, firstOptions(entry, bytes, v, 0), md);
        if (rc >= 0) {
            if (!invert) try ctx.vm.arrayAddEntry(out, e.key, e, e.ref);
        } else if (rc == pcre2.ERROR_NOMATCH) {
            if (invert) try ctx.vm.arrayAddEntry(out, e.key, e, e.ref);
        } else {
            handleExecError(rc);
            break;
        }
    }
    return NativeResult.borrowed(.{ .array = out });
}

// ---------------------------------------------------------------------------
// mbstring's regex functions on pcre

fn mb_split(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.null);
    const pattern = args[0].string.bytes();
    const subject = args[1].string.bytes();
    const limit: i64 = if (args.len >= 3 and args[2] != .null) Value.toInt(args[2]) else -1;

    const compiled = compileRaw(ctx, pattern, pcre2.UTF) orelse return NativeResult.scalar(.null);
    defer compiled.release();
    const entry = compiled.entry;

    const md = pcre2.pcre2_match_data_create_from_pattern_8(entry.code, null) orelse return NativeResult.scalar(.null);
    defer pcre2.pcre2_match_data_free_8(md);

    // php_mbregex's loop: a match that ends past the search position closes
    // a piece; an empty one only moves the search on
    var result = try ctx.createArray();
    var chunk: usize = 0;
    var pos: usize = 0;
    var pieces: i64 = 1;

    while (pos < subject.len) {
        if (limit > 0 and pieces >= limit) break;
        const rc = exec(ctx, entry.code, subject, pos, firstOptions(entry, subject, args[1], pos), md);
        if (rc < 0) break;
        const ov = pcre2.pcre2_get_ovector_pointer_8(md);
        const match_start = ov[0];
        const match_end = ov[1];
        if (match_end > pos) {
            try result.appendCopiedString(ctx.allocator, subject[chunk..@max(chunk, match_start)]);
            pieces += 1;
            chunk = match_end;
            pos = match_end;
        } else {
            pos += unitLength(entry, subject, pos);
        }
    }
    try result.appendCopiedString(ctx.allocator, subject[chunk..]);

    return NativeResult.borrowed(.{ .array = result });
}

fn mb_ereg_match(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const pattern = args[0].string.bytes();
    const subject = args[1].string.bytes();

    const compiled = compileRaw(ctx, pattern, pcre2.UTF | pcre2.ANCHORED) orelse return NativeResult.scalar(.{ .bool = false });
    defer compiled.release();
    const entry = compiled.entry;

    const md = pcre2.pcre2_match_data_create_from_pattern_8(entry.code, null) orelse return NativeResult.scalar(.{ .bool = false });
    defer pcre2.pcre2_match_data_free_8(md);

    const rc = exec(ctx, entry.code, subject, 0, firstOptions(entry, subject, args[1], 0), md);
    return NativeResult.scalar(.{ .bool = rc >= 0 });
}
