// php's locale functions: setlocale and localeconv go to the c library as
// php's do, and the multibyte scanning php does under LC_CTYPE (php_mblen)
// reads characters with the c library's mbrlen
const std = @import("std");
const builtin = @import("builtin");
const platform = @import("../platform.zig");
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const Value = @import("../runtime/value.zig").Value;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const strings = @import("strings.zig");
const RuntimeError = error{ RuntimeError, OutOfMemory };

extern "c" fn setlocale(category: c_int, locale: ?[*:0]const u8) ?[*:0]const u8;
extern "c" fn mbrlen(s: [*]const u8, n: usize, ps: *anyopaque) usize;
extern "c" fn localeconv() *const Lconv;
extern "c" fn strcoll(a: [*:0]const u8, b: [*:0]const u8) c_int;

// the members c requires, in its order; libraries add theirs after them
const Lconv = extern struct {
    decimal_point: [*:0]const u8,
    thousands_sep: [*:0]const u8,
    grouping: [*:0]const u8,
    int_curr_symbol: [*:0]const u8,
    currency_symbol: [*:0]const u8,
    mon_decimal_point: [*:0]const u8,
    mon_thousands_sep: [*:0]const u8,
    mon_grouping: [*:0]const u8,
    positive_sign: [*:0]const u8,
    negative_sign: [*:0]const u8,
    int_frac_digits: c_char,
    frac_digits: c_char,
    p_cs_precedes: c_char,
    p_sep_by_space: c_char,
    n_cs_precedes: c_char,
    n_sep_by_space: c_char,
    p_sign_posn: c_char,
    n_sign_posn: c_char,
};

// the LC_* values of the c library php is built against
pub const Categories = struct { all: i64, collate: i64, ctype: i64, monetary: i64, numeric: i64, time: i64, messages: ?i64 };
pub const lc: Categories = switch (builtin.os.tag) {
    .linux => .{ .ctype = 0, .numeric = 1, .time = 2, .collate = 3, .monetary = 4, .messages = 5, .all = 6 },
    .windows => .{ .all = 0, .collate = 1, .ctype = 2, .monetary = 3, .numeric = 4, .time = 5, .messages = null },
    else => .{ .all = 0, .collate = 1, .ctype = 2, .monetary = 3, .numeric = 4, .time = 5, .messages = 6 },
};

pub const entries = .{
    .{ "setlocale", native_setlocale },
    .{ "localeconv", native_localeconv },
    .{ "strcoll", native_strcoll },
};

// set by a script's setlocale, so the end of a request puts the startup
// locale back (php's BG(locale_changed))
var changed = false;

// zend_reset_lc_ctype_locale: LC_CTYPE is C.UTF-8 where the library has it,
// so multibyte input reads as utf-8 without changing single-byte behavior
pub fn resetCtype() void {
    if (setlocale(@intCast(lc.ctype), "C.UTF-8") == null) _ = setlocale(@intCast(lc.ctype), "C");
}

// the end of a request: a locale the script set goes back to the startup one
pub fn resetAfterRequest() void {
    if (!changed) return;
    changed = false;
    _ = setlocale(@intCast(lc.all), "C");
    resetCtype();
}

// php_mblen's shift state, per thread as php keeps it per request
threadlocal var mb_state: [128]u8 align(16) = @splat(0);

pub fn mbReset() void {
    @memset(&mb_state, 0);
}

// php_mblen: the length of the character at the start of s under LC_CTYPE,
// -1 for an invalid sequence, -2 for one cut short. every php caller resets
// the shift state after either, so this does
pub fn mblen(s: []const u8) i32 {
    if (s.len == 0) return 0;
    const r = mbrlen(s.ptr, s.len, &mb_state);
    if (r == std.math.maxInt(usize) or r == std.math.maxInt(usize) - 1) {
        mbReset();
        return if (r == std.math.maxInt(usize)) -1 else -2;
    }
    return @intCast(r);
}

// try_setlocale_str: the library's name for the locale it switched to, or
// null when it has no such locale. "0" asks for the current one
fn trySetlocale(ctx: *NativeContext, category: i64, loc: []const u8) RuntimeError!?[]const u8 {
    const query = std.mem.eql(u8, loc, "0");
    if (!query and loc.len >= 255) {
        try ctx.vm.raiseError(2, "setlocale(): Specified locale name is too long");
        return null;
    }
    const cat = std.math.cast(c_int, category) orelse return null;
    var name_buf: [256]u8 = undefined;
    const retval = if (query) setlocale(cat, null) else blk: {
        if (platform.is_windows and windowsRefuses(loc)) break :blk null;
        @memcpy(name_buf[0..loc.len], loc);
        name_buf[loc.len] = 0;
        break :blk setlocale(cat, name_buf[0..loc.len :0].ptr);
    };
    const result = std.mem.span(retval orelse return null);
    if (!query) changed = true;
    return result;
}

// php on windows doesn't hand a name shaped like `xx_YY` (or `xx_YY.cp`) to
// the library, which would take it as a language and country, except uk_UK
// and us_US
fn windowsRefuses(loc: []const u8) bool {
    if (loc.len < 5 or loc[2] != '_') return false;
    if (!std.ascii.isLower(loc[0]) or !std.ascii.isLower(loc[1]) or !std.ascii.isUpper(loc[3]) or !std.ascii.isUpper(loc[4])) return false;
    if (loc.len > 5 and loc[5] != '.') return false;
    const legacy = loc[0] == 'u' and (loc[1] == 'k' or loc[1] == 's') and loc[3] == 'U' and (loc[4] == 'K' or loc[4] == 'S') and loc.len == 5;
    return !legacy;
}

fn native_setlocale(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const category = Value.toInt(args[0]);
    var names = std.ArrayListUnmanaged(?[]const u8).empty;
    defer names.deinit(ctx.allocator);
    for (args[1..], 2..) |arg, position| {
        const name: ?[]const u8 = switch (arg) {
            .array => null,
            .null, .undef => "",
            .string => |s| s.bytes(),
            .int, .float, .bool => try strings.coerceToString(ctx, arg),
            .object => |o| if (ctx.vm.hasMethod(o.class_name, "__toString")) try ctx.vm.objectToString(o) else return wrongType(ctx, position, arg),
            else => return wrongType(ctx, position, arg),
        };
        try names.append(ctx.allocator, name);
    }
    for (args[1..], names.items) |arg, name| {
        if (name) |loc| {
            if (try trySetlocale(ctx, category, loc)) |result| return NativeResult.copyString(ctx.allocator, result);
            continue;
        }
        for (arg.array.entries.items) |entry| {
            const loc = switch (entry.value) {
                .string => |s| s.bytes(),
                .object => |o| try ctx.vm.objectToString(o),
                else => try strings.coerceToString(ctx, entry.value),
            };
            if (ctx.vm.pending_exception != null) return error.RuntimeError;
            if (try trySetlocale(ctx, category, loc)) |result| return NativeResult.copyString(ctx.allocator, result);
        }
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn wrongType(ctx: *NativeContext, position: usize, arg: Value) RuntimeError!NativeResult {
    // a variadic argument has no name to give
    const name = if (position == 2) " ($locales)" else "";
    const msg = try std.fmt.allocPrint(ctx.allocator, "setlocale(): Argument #{d}{s} must be of type array|string|null, {s} given", .{ position, name, @import("types.zig").phpTypeName(arg) });
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("TypeError", msg);
    return error.RuntimeError;
}

fn native_localeconv(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const conv = localeconv();
    const arr = try ctx.createArray();
    const text_fields = .{ "decimal_point", "thousands_sep", "int_curr_symbol", "currency_symbol", "mon_decimal_point", "mon_thousands_sep", "positive_sign", "negative_sign" };
    inline for (text_fields) |field| {
        const text = Value.String.borrowed(try ctx.createString(std.mem.span(@field(conv, field))));
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(field) }, .{ .string = text });
    }
    const numbers = .{ "int_frac_digits", "frac_digits", "p_cs_precedes", "p_sep_by_space", "n_cs_precedes", "n_sep_by_space", "p_sign_posn", "n_sign_posn" };
    inline for (numbers) |field| {
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(field) }, .{ .int = @as(i64, @field(conv, field)) });
    }
    inline for (.{ "grouping", "mon_grouping" }) |field| {
        const groups = try ctx.createArray();
        for (std.mem.span(@field(conv, field))) |g| {
            try groups.append(ctx.allocator, .{ .int = @as(i64, @as(c_char, @bitCast(g))) });
        }
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(field) }, .{ .array = groups });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

// php's strcoll is the c library's under LC_COLLATE, its result as given;
// like php's, it compares up to the first nul byte
fn native_strcoll(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const a = try ctx.allocator.dupeSentinel(u8, try strings.stringParam(ctx, "strcoll", args, 0, "string1"), 0);
    defer ctx.allocator.free(a);
    const b = try ctx.allocator.dupeSentinel(u8, try strings.stringParam(ctx, "strcoll", args, 1, "string2"), 0);
    defer ctx.allocator.free(b);
    return NativeResult.scalar(.{ .int = strcoll(a.ptr, b.ptr) });
}
