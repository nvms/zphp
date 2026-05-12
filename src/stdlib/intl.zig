const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

// libicu uses preprocessor macros to rename its API per ABI version
// (u_strFromUTF8 -> u_strFromUTF8_77 on linux distros). zig's @cImport doesn't
// apply these renames consistently, so we hand-declare extern functions that
// point at unversioned zphp_* wrappers compiled by the C preprocessor.
// see src/stdlib/icu_shim.c

const UChar = u16;
const UNormalizer2 = opaque {};
const UCollator = opaque {};
const UNumberFormat = opaque {};
const UTransliterator = opaque {};

// every ICU function returns negative on success, positive on warning,
// > U_ZERO_ERROR == > 0 on real error. U_ZERO_ERROR itself is 0
const UErrorCode = i32;
const U_ZERO_ERROR: UErrorCode = 0;

extern fn zphp_u_strFromUTF8(dest: [*]UChar, cap: i32, plen: *i32, src: [*]const u8, srcLen: i32, err: *UErrorCode) [*]UChar;
extern fn zphp_u_strToUTF8(dest: [*]u8, cap: i32, plen: *i32, src: [*]const UChar, srcLen: i32, err: *UErrorCode) [*]u8;

extern fn zphp_unorm2_getNFCInstance(err: *UErrorCode) ?*const UNormalizer2;
extern fn zphp_unorm2_getNFDInstance(err: *UErrorCode) ?*const UNormalizer2;
extern fn zphp_unorm2_getNFKCInstance(err: *UErrorCode) ?*const UNormalizer2;
extern fn zphp_unorm2_getNFKDInstance(err: *UErrorCode) ?*const UNormalizer2;
extern fn zphp_unorm2_getNFKCCasefoldInstance(err: *UErrorCode) ?*const UNormalizer2;
extern fn zphp_unorm2_normalize(n: *const UNormalizer2, src: [*]const UChar, srcLen: i32, dest: [*]UChar, cap: i32, err: *UErrorCode) i32;
extern fn zphp_unorm2_isNormalized(n: *const UNormalizer2, src: [*]const UChar, srcLen: i32, err: *UErrorCode) u8;

extern fn zphp_uloc_getDefault() [*:0]const u8;
extern fn zphp_uloc_setDefault(loc: [*:0]const u8, err: *UErrorCode) void;
extern fn zphp_uloc_getLanguage(loc: [*:0]const u8, buf: [*]u8, cap: i32, err: *UErrorCode) i32;
extern fn zphp_uloc_getCountry(loc: [*:0]const u8, buf: [*]u8, cap: i32, err: *UErrorCode) i32;
extern fn zphp_uloc_getScript(loc: [*:0]const u8, buf: [*]u8, cap: i32, err: *UErrorCode) i32;
extern fn zphp_uloc_canonicalize(loc: [*:0]const u8, buf: [*]u8, cap: i32, err: *UErrorCode) i32;
extern fn zphp_uloc_getDisplayName(loc: [*:0]const u8, inLoc: [*:0]const u8, buf: [*]UChar, cap: i32, err: *UErrorCode) i32;
extern fn zphp_uloc_getDisplayLanguage(loc: [*:0]const u8, inLoc: [*:0]const u8, buf: [*]UChar, cap: i32, err: *UErrorCode) i32;
extern fn zphp_uloc_getDisplayCountry(loc: [*:0]const u8, inLoc: [*:0]const u8, buf: [*]UChar, cap: i32, err: *UErrorCode) i32;
extern fn zphp_uloc_getDisplayScript(loc: [*:0]const u8, inLoc: [*:0]const u8, buf: [*]UChar, cap: i32, err: *UErrorCode) i32;

extern fn zphp_ucol_open(loc: [*:0]const u8, err: *UErrorCode) ?*UCollator;
extern fn zphp_ucol_close(c: *UCollator) void;
extern fn zphp_ucol_strcoll(c: *const UCollator, a: [*]const UChar, aLen: i32, b: [*]const UChar, bLen: i32) i32;
extern fn zphp_ucol_setStrength(c: *UCollator, strength: i32) void;
extern fn zphp_ucol_getStrength(c: *const UCollator) i32;

extern fn zphp_unum_open(style: i32, pattern: ?[*]const UChar, patLen: i32, locale: [*:0]const u8, parseErr: ?*anyopaque, err: *UErrorCode) ?*UNumberFormat;
extern fn zphp_unum_close(f: *UNumberFormat) void;
extern fn zphp_unum_formatInt64(f: *const UNumberFormat, v: i64, buf: [*]UChar, cap: i32, pos: ?*anyopaque, err: *UErrorCode) i32;
extern fn zphp_unum_formatDouble(f: *const UNumberFormat, v: f64, buf: [*]UChar, cap: i32, pos: ?*anyopaque, err: *UErrorCode) i32;
extern fn zphp_unum_formatDoubleCurrency(f: *const UNumberFormat, v: f64, ccy: [*]UChar, buf: [*]UChar, cap: i32, pos: ?*anyopaque, err: *UErrorCode) i32;
extern fn zphp_unum_parseDouble(f: *const UNumberFormat, src: [*]const UChar, srcLen: i32, parsePos: ?*i32, err: *UErrorCode) f64;
extern fn zphp_unum_setAttribute(f: *UNumberFormat, attr: i32, v: i32) void;
extern fn zphp_unum_setDoubleAttribute(f: *UNumberFormat, attr: i32, v: f64) void;
extern fn zphp_unum_getAttribute(f: *const UNumberFormat, attr: i32) i32;

extern fn zphp_utrans_openU(id: [*]const UChar, idLen: i32, dir: i32, rules: ?[*]const UChar, rulesLen: i32, parseErr: ?*anyopaque, err: *UErrorCode) ?*UTransliterator;
extern fn zphp_utrans_close(t: *UTransliterator) void;
extern fn zphp_utrans_transUChars(t: *const UTransliterator, text: [*]UChar, textLen: *i32, textCap: i32, start: i32, limit: *i32, err: *UErrorCode) void;

const UDateFormat = opaque {};
extern fn zphp_udat_open(timeStyle: i32, dateStyle: i32, locale: [*:0]const u8, tzId: ?[*]const UChar, tzIdLen: i32, pattern: ?[*]const UChar, patternLen: i32, err: *UErrorCode) ?*UDateFormat;
extern fn zphp_udat_close(f: *UDateFormat) void;
extern fn zphp_udat_format(f: *const UDateFormat, date: f64, result: [*]UChar, resultLen: i32, pos: ?*anyopaque, err: *UErrorCode) i32;
extern fn zphp_udat_parse(f: *const UDateFormat, text: [*]const UChar, textLen: i32, parsePos: ?*i32, err: *UErrorCode) f64;
extern fn zphp_udat_applyPattern(f: *UDateFormat, localized: u8, pattern: [*]const UChar, patternLen: i32) void;
extern fn zphp_udat_toPattern(f: *const UDateFormat, localized: u8, result: [*]UChar, resultLen: i32, err: *UErrorCode) i32;

// MessageFormat lives in ICU's C++ API (the C entry points are variadic).
// icu_msg_shim.cpp wraps the named-args and positional-args formatters
// behind a stable C ABI. ArgEntry must match the C++ struct byte-for-byte
const ArgEntry = extern struct {
    type: i32,
    _pad: u32 = 0,
    ival: i64,
    dval: f64,
    sval: ?[*]const UChar,
    slen: i32,
    _pad2: u32 = 0,
    name: ?[*]const UChar,
    name_len: i32,
    _pad3: u32 = 0,
};
const ARG_INT: i32 = 0;
const ARG_DOUBLE: i32 = 1;
const ARG_STRING: i32 = 2;

extern fn zphp_msgfmt_format(locale: [*:0]const u8, pattern: [*]const UChar, pat_len: i32, args: [*]const ArgEntry, arg_count: i32, result: [*]UChar, result_cap: i32, err: *UErrorCode) i32;
extern fn zphp_msgfmt_format_positional(locale: [*:0]const u8, pattern: [*]const UChar, pat_len: i32, args: [*]const ArgEntry, arg_count: i32, result: [*]UChar, result_cap: i32, err: *UErrorCode) i32;

const UIDNA = opaque {};
const UCalendar = opaque {};

extern fn zphp_ucal_open(zoneID: ?[*]const UChar, len: i32, locale: [*:0]const u8, cal_type: c_int, err: *UErrorCode) ?*UCalendar;
extern fn zphp_ucal_close(cal: *UCalendar) void;
extern fn zphp_ucal_get(cal: *const UCalendar, field: c_int, err: *UErrorCode) i32;
extern fn zphp_ucal_set(cal: *UCalendar, field: c_int, value: i32) void;
extern fn zphp_ucal_add(cal: *UCalendar, field: c_int, amount: i32, err: *UErrorCode) void;
extern fn zphp_ucal_roll(cal: *UCalendar, field: c_int, amount: i32, err: *UErrorCode) void;
extern fn zphp_ucal_getMillis(cal: *const UCalendar, err: *UErrorCode) f64;
extern fn zphp_ucal_setMillis(cal: *UCalendar, dateTime: f64, err: *UErrorCode) void;
extern fn zphp_ucal_setDate(cal: *UCalendar, year: i32, month: i32, date: i32, err: *UErrorCode) void;
extern fn zphp_ucal_setDateTime(cal: *UCalendar, y: i32, mo: i32, d: i32, h: i32, mi: i32, s: i32, err: *UErrorCode) void;
extern fn zphp_ucal_inDaylightTime(cal: *const UCalendar, err: *UErrorCode) u8;
extern fn zphp_ucal_isSet(cal: *const UCalendar, field: c_int) u8;
extern fn zphp_ucal_clear(cal: *UCalendar) void;
extern fn zphp_ucal_clearField(cal: *UCalendar, field: c_int) void;
extern fn zphp_ucal_getLimit(cal: *const UCalendar, field: c_int, limit_type: c_int, err: *UErrorCode) i32;
extern fn zphp_ucal_equivalentTo(a: *const UCalendar, b: *const UCalendar) u8;
extern fn zphp_ucal_getType(cal: *const UCalendar, buf: [*]u8, buf_len: i32, err: *UErrorCode) i32;
extern fn zphp_ucal_getLocaleByType(cal: *const UCalendar, ltype: c_int, buf: [*]u8, buf_len: i32, err: *UErrorCode) i32;
extern fn zphp_ucal_getTimeZoneID(cal: *const UCalendar, buf: [*]UChar, cap: i32, err: *UErrorCode) i32;
extern fn zphp_ucal_setTimeZone(cal: *UCalendar, zoneID: [*]const UChar, len: i32, err: *UErrorCode) void;
extern fn zphp_ucal_getFirstDayOfWeek(cal: *const UCalendar, err: *UErrorCode) i32;
extern fn zphp_ucal_setFirstDayOfWeek(cal: *UCalendar, day: i32) void;
extern fn zphp_ucal_isWeekend(cal: *const UCalendar, date: f64, err: *UErrorCode) u8;
extern fn zphp_ucal_clone(cal: *const UCalendar, err: *UErrorCode) ?*UCalendar;
extern fn zphp_ucal_getLenient(cal: *const UCalendar) u8;
extern fn zphp_ucal_setLenient(cal: *UCalendar, lenient: i32) void;

const ZphpBrk = opaque {};
extern fn zphp_ubrk_open(brk_type: c_int, locale: [*:0]const u8, err: *UErrorCode) ?*ZphpBrk;
extern fn zphp_ubrk_close(w: *ZphpBrk) void;
extern fn zphp_ubrk_setText(w: *ZphpBrk, text: [*]const u8, len: i32, err: *UErrorCode) void;
extern fn zphp_ubrk_getText(w: *ZphpBrk, len: *i32) [*:0]const u8;
extern fn zphp_ubrk_first(w: *ZphpBrk) i32;
extern fn zphp_ubrk_last(w: *ZphpBrk) i32;
extern fn zphp_ubrk_next(w: *ZphpBrk) i32;
extern fn zphp_ubrk_previous(w: *ZphpBrk) i32;
extern fn zphp_ubrk_current(w: *ZphpBrk) i32;
extern fn zphp_ubrk_following(w: *ZphpBrk, off: i32) i32;
extern fn zphp_ubrk_preceding(w: *ZphpBrk, off: i32) i32;
extern fn zphp_ubrk_isBoundary(w: *ZphpBrk, off: i32) u8;
extern fn zphp_ubrk_getRuleStatus(w: *ZphpBrk) i32;
extern fn zphp_ubrk_getLocaleByType(w: *ZphpBrk, ltype: c_int, buf: [*]u8, buf_len: i32, err: *UErrorCode) i32;
extern fn zphp_uidna_openUTS46(options: u32, err: *UErrorCode) ?*UIDNA;
extern fn zphp_uidna_close(idna: *UIDNA) void;
extern fn zphp_uidna_nameToASCII(idna: *const UIDNA, name: [*]const UChar, nameLen: i32, dest: [*]UChar, cap: i32, info: *anyopaque, err: *UErrorCode) i32;
extern fn zphp_uidna_nameToUnicode(idna: *const UIDNA, name: [*]const UChar, nameLen: i32, dest: [*]UChar, cap: i32, info: *anyopaque, err: *UErrorCode) i32;
extern fn zphp_uidna_info_size() usize;
extern fn zphp_uidna_info_init(info: *anyopaque) void;

// ---------------- helpers ----------------

fn dupString(ctx: *NativeContext, s: []const u8) ![]const u8 {
    const owned = try ctx.allocator.dupe(u8, s);
    try ctx.strings.append(ctx.allocator, owned);
    return owned;
}

fn dupZ(ctx: *NativeContext, s: []const u8) ![:0]u8 {
    const z = try ctx.allocator.alloc(u8, s.len + 1);
    @memcpy(z[0..s.len], s);
    z[s.len] = 0;
    try ctx.strings.append(ctx.allocator, z);
    return z[0..s.len :0];
}

fn cstrLen(p: [*:0]const u8) usize {
    var i: usize = 0;
    while (p[i] != 0) : (i += 1) {}
    return i;
}

fn getThis(ctx: *NativeContext) ?*PhpObject {
    if (ctx.vm.frame_count == 0) return null;
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

// utf-8 → utf-16. shrinks to actual length so caller can free the returned slice
fn utf8ToU16(ctx: *NativeContext, s: []const u8) ![]u16 {
    if (s.len == 0) return try ctx.allocator.alloc(u16, 0);
    const cap: i32 = @intCast(s.len * 2 + 1);
    var buf = try ctx.allocator.alloc(u16, @intCast(cap));
    errdefer ctx.allocator.free(buf);
    var actual: i32 = 0;
    var status: UErrorCode = U_ZERO_ERROR;
    _ = zphp_u_strFromUTF8(buf.ptr, cap, &actual, s.ptr, @intCast(s.len), &status);
    if (status > U_ZERO_ERROR) return error.RuntimeError;
    buf = try ctx.allocator.realloc(buf, @intCast(actual));
    return buf;
}

fn u16ToUtf8(ctx: *NativeContext, s: []const u16) ![]const u8 {
    if (s.len == 0) return try dupString(ctx, "");
    const cap: i32 = @intCast(s.len * 3 + 4);
    var buf = try ctx.allocator.alloc(u8, @intCast(cap));
    errdefer ctx.allocator.free(buf);
    var actual: i32 = 0;
    var status: UErrorCode = U_ZERO_ERROR;
    _ = zphp_u_strToUTF8(buf.ptr, cap, &actual, s.ptr, @intCast(s.len), &status);
    if (status > U_ZERO_ERROR) return error.RuntimeError;
    buf = try ctx.allocator.realloc(buf, @intCast(actual));
    try ctx.strings.append(ctx.allocator, buf);
    return buf;
}

// ---------------- Normalizer ----------------

fn getNormalizer(form: i64) ?*const UNormalizer2 {
    var status: UErrorCode = U_ZERO_ERROR;
    // PHP's Normalizer constants:
    //   NONE = 1, FORM_D = NFD = 2, FORM_KD = NFKD = 3,
    //   FORM_C = NFC = 4 (default), FORM_KC = NFKC = 5, FORM_KC_CF = 48
    const n = switch (form) {
        2 => zphp_unorm2_getNFDInstance(&status),
        3 => zphp_unorm2_getNFKDInstance(&status),
        4 => zphp_unorm2_getNFCInstance(&status),
        5 => zphp_unorm2_getNFKCInstance(&status),
        48 => zphp_unorm2_getNFKCCasefoldInstance(&status),
        else => zphp_unorm2_getNFCInstance(&status),
    };
    if (status > U_ZERO_ERROR) return null;
    return n;
}

fn normalizerNormalize(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const form: i64 = if (args.len > 1 and args[1] == .int) args[1].int else 1;
    const norm = getNormalizer(form) orelse return .{ .bool = false };

    const u16src = try utf8ToU16(ctx, args[0].string);
    defer ctx.allocator.free(u16src);

    const cap: i32 = @intCast(u16src.len * 2 + 8);
    const buf = try ctx.allocator.alloc(u16, @intCast(cap));
    defer ctx.allocator.free(buf);
    var status: UErrorCode = U_ZERO_ERROR;
    const actual = zphp_unorm2_normalize(norm, u16src.ptr, @intCast(u16src.len), buf.ptr, cap, &status);
    if (status > U_ZERO_ERROR) return .{ .bool = false };

    const out = try u16ToUtf8(ctx, buf[0..@intCast(actual)]);
    return .{ .string = out };
}

fn normalizerIsNormalized(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const form: i64 = if (args.len > 1 and args[1] == .int) args[1].int else 1;
    const norm = getNormalizer(form) orelse return .{ .bool = false };
    const u16src = try utf8ToU16(ctx, args[0].string);
    defer ctx.allocator.free(u16src);
    var status: UErrorCode = U_ZERO_ERROR;
    const ok = zphp_unorm2_isNormalized(norm, u16src.ptr, @intCast(u16src.len), &status);
    if (status > U_ZERO_ERROR) return .{ .bool = false };
    return .{ .bool = ok != 0 };
}

// ---------------- Locale ----------------

fn localeGetDefault(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const def = zphp_uloc_getDefault();
    return .{ .string = try dupString(ctx, def[0..cstrLen(def)]) };
}

fn localeSetDefault(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    var buf: [256]u8 = undefined;
    const n = @min(args[0].string.len, buf.len - 1);
    @memcpy(buf[0..n], args[0].string[0..n]);
    buf[n] = 0;
    var status: UErrorCode = U_ZERO_ERROR;
    zphp_uloc_setDefault(@ptrCast(&buf), &status);
    return .{ .bool = status <= U_ZERO_ERROR };
}

const KeywordFn = *const fn (loc: [*:0]const u8, buf: [*]u8, cap: i32, err: *UErrorCode) callconv(.c) i32;

fn locKeywordCall(ctx: *NativeContext, args: []const Value, comptime fn_ptr: KeywordFn) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .null;
    const loc_z = try dupZ(ctx, args[0].string);
    var buf: [128]u8 = undefined;
    var status: UErrorCode = U_ZERO_ERROR;
    const n = fn_ptr(loc_z.ptr, &buf, @intCast(buf.len), &status);
    if (status > U_ZERO_ERROR or n <= 0) return .{ .string = try dupString(ctx, "") };
    return .{ .string = try dupString(ctx, buf[0..@intCast(n)]) };
}

fn localeGetPrimaryLanguage(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return locKeywordCall(ctx, args, zphp_uloc_getLanguage);
}
fn localeGetRegion(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return locKeywordCall(ctx, args, zphp_uloc_getCountry);
}
fn localeGetScript(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return locKeywordCall(ctx, args, zphp_uloc_getScript);
}
fn localeCanonicalize(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .null;
    const loc_z = try dupZ(ctx, args[0].string);
    var buf: [256]u8 = undefined;
    var status: UErrorCode = U_ZERO_ERROR;
    const n = zphp_uloc_canonicalize(loc_z.ptr, &buf, @intCast(buf.len), &status);
    if (status > U_ZERO_ERROR or n <= 0) return .{ .string = try dupString(ctx, "") };
    return .{ .string = try dupString(ctx, buf[0..@intCast(n)]) };
}

const DisplayFn = *const fn (loc: [*:0]const u8, inLoc: [*:0]const u8, buf: [*]UChar, cap: i32, err: *UErrorCode) callconv(.c) i32;

fn displayCall(ctx: *NativeContext, args: []const Value, comptime fn_ptr: DisplayFn) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .null;
    const tgt_z = try dupZ(ctx, args[0].string);
    const in_z: ?[:0]u8 = if (args.len > 1 and args[1] == .string) try dupZ(ctx, args[1].string) else null;
    const in_ptr: [*:0]const u8 = if (in_z) |z| z.ptr else zphp_uloc_getDefault();
    var buf: [256]UChar = undefined;
    var status: UErrorCode = U_ZERO_ERROR;
    const n = fn_ptr(tgt_z.ptr, in_ptr, &buf, @intCast(buf.len), &status);
    if (status > U_ZERO_ERROR or n <= 0) return .{ .string = try dupString(ctx, "") };
    const out = try u16ToUtf8(ctx, buf[0..@intCast(n)]);
    return .{ .string = out };
}

fn localeGetDisplayName(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return displayCall(ctx, args, zphp_uloc_getDisplayName); }
fn localeGetDisplayLanguage(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return displayCall(ctx, args, zphp_uloc_getDisplayLanguage); }
fn localeGetDisplayRegion(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return displayCall(ctx, args, zphp_uloc_getDisplayCountry); }
fn localeGetDisplayScript(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return displayCall(ctx, args, zphp_uloc_getDisplayScript); }

// ---------------- Collator ----------------

fn getCollator(obj: *const PhpObject) ?*UCollator {
    const v = obj.get("__coll");
    if (v != .int or v.int == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(v.int)));
}

fn openCollatorFor(ctx: *NativeContext, locale: []const u8) !?*UCollator {
    const loc_z = try dupZ(ctx, locale);
    var status: UErrorCode = U_ZERO_ERROR;
    const c = zphp_ucol_open(loc_z.ptr, &status);
    if (status > U_ZERO_ERROR) return null;
    return c;
}

fn collConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .null;
    const obj = getThis(ctx) orelse return .null;
    const c = (try openCollatorFor(ctx, args[0].string)) orelse return .null;
    try obj.set(ctx.allocator, "__coll", .{ .int = @intCast(@intFromPtr(c)) });
    try obj.set(ctx.allocator, "__locale", .{ .string = try dupString(ctx, args[0].string) });
    return .null;
}

fn collCreateStatic(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .null;
    const obj = try ctx.createObject("Collator");
    const c = (try openCollatorFor(ctx, args[0].string)) orelse return .null;
    try obj.set(ctx.allocator, "__coll", .{ .int = @intCast(@intFromPtr(c)) });
    try obj.set(ctx.allocator, "__locale", .{ .string = try dupString(ctx, args[0].string) });
    return .{ .object = obj };
}

fn collCompare(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const c = getCollator(obj) orelse return .{ .bool = false };
    const a = try utf8ToU16(ctx, args[0].string);
    defer ctx.allocator.free(a);
    const b = try utf8ToU16(ctx, args[1].string);
    defer ctx.allocator.free(b);
    return .{ .int = @intCast(zphp_ucol_strcoll(c, a.ptr, @intCast(a.len), b.ptr, @intCast(b.len))) };
}

fn collSetStrength(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .int) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const c = getCollator(obj) orelse return .{ .bool = false };
    zphp_ucol_setStrength(c, @intCast(args[0].int));
    return .{ .bool = true };
}

fn collGetStrength(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    const c = getCollator(obj) orelse return .{ .int = 0 };
    return .{ .int = @intCast(zphp_ucol_getStrength(c)) };
}

fn collGetLocale(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .string = try dupString(ctx, "") };
    const v = obj.get("__locale");
    if (v == .string) return v;
    return .{ .string = try dupString(ctx, "") };
}

fn collSort(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .array) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const c = getCollator(obj) orelse return .{ .bool = false };

    const arr = args[0].array;
    const SortContext = struct { coll: *UCollator, ctx: *NativeContext };
    var sctx = SortContext{ .coll = c, .ctx = ctx };

    const lessThan = struct {
        fn lt(sc: *SortContext, ka: PhpArray.Entry, kb: PhpArray.Entry) bool {
            const sa = if (ka.value == .string) ka.value.string else "";
            const sb = if (kb.value == .string) kb.value.string else "";
            const ua = utf8ToU16(sc.ctx, sa) catch return false;
            defer sc.ctx.allocator.free(ua);
            const ub = utf8ToU16(sc.ctx, sb) catch return false;
            defer sc.ctx.allocator.free(ub);
            return zphp_ucol_strcoll(sc.coll, ua.ptr, @intCast(ua.len), ub.ptr, @intCast(ub.len)) < 0;
        }
    }.lt;
    std.sort.pdq(PhpArray.Entry, arr.entries.items, &sctx, lessThan);

    for (arr.entries.items, 0..) |*e, i| e.key = .{ .int = @intCast(i) };
    arr.string_index.clearRetainingCapacity();
    arr.next_int_key = @intCast(arr.entries.items.len);
    arr.has_int_keys = true;
    return .{ .bool = true };
}

// ---------------- NumberFormatter ----------------

fn getNumFmt(obj: *const PhpObject) ?*UNumberFormat {
    const v = obj.get("__nfmt");
    if (v != .int or v.int == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(v.int)));
}

fn openNumFmt(ctx: *NativeContext, locale: []const u8, style: i32) !?*UNumberFormat {
    const loc_z = try dupZ(ctx, locale);
    var status: UErrorCode = U_ZERO_ERROR;
    const f = zphp_unum_open(style, null, 0, loc_z.ptr, null, &status);
    if (status > U_ZERO_ERROR) return null;
    return f;
}

fn nfConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string) return .null;
    const obj = getThis(ctx) orelse return .null;
    const style: i32 = if (args[1] == .int) @intCast(args[1].int) else 1;
    const f = (try openNumFmt(ctx, args[0].string, style)) orelse return .null;
    try obj.set(ctx.allocator, "__nfmt", .{ .int = @intCast(@intFromPtr(f)) });
    return .null;
}

fn nfCreateStatic(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string) return .null;
    const obj = try ctx.createObject("NumberFormatter");
    const style: i32 = if (args[1] == .int) @intCast(args[1].int) else 1;
    const f = (try openNumFmt(ctx, args[0].string, style)) orelse return .null;
    try obj.set(ctx.allocator, "__nfmt", .{ .int = @intCast(@intFromPtr(f)) });
    return .{ .object = obj };
}

fn nfFormat(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const f = getNumFmt(obj) orelse return .{ .bool = false };

    var buf: [128]UChar = undefined;
    var status: UErrorCode = U_ZERO_ERROR;
    var n: i32 = 0;

    switch (args[0]) {
        .int => |i| n = zphp_unum_formatInt64(f, i, &buf, @intCast(buf.len), null, &status),
        .float => |fl| n = zphp_unum_formatDouble(f, fl, &buf, @intCast(buf.len), null, &status),
        else => return .{ .bool = false },
    }
    if (status > U_ZERO_ERROR) return .{ .bool = false };
    const out = try u16ToUtf8(ctx, buf[0..@intCast(n)]);
    return .{ .string = out };
}

fn nfFormatCurrency(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[1] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const f = getNumFmt(obj) orelse return .{ .bool = false };
    const amount: f64 = switch (args[0]) {
        .int => |i| @floatFromInt(i),
        .float => |fl| fl,
        else => return .{ .bool = false },
    };
    const ccy_u16 = try utf8ToU16(ctx, args[1].string);
    defer ctx.allocator.free(ccy_u16);
    var buf: [128]UChar = undefined;
    var status: UErrorCode = U_ZERO_ERROR;
    const n = zphp_unum_formatDoubleCurrency(f, amount, ccy_u16.ptr, &buf, @intCast(buf.len), null, &status);
    if (status > U_ZERO_ERROR) return .{ .bool = false };
    const out = try u16ToUtf8(ctx, buf[0..@intCast(n)]);
    return .{ .string = out };
}

fn nfParse(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const f = getNumFmt(obj) orelse return .{ .bool = false };
    const u16src = try utf8ToU16(ctx, args[0].string);
    defer ctx.allocator.free(u16src);
    var pos: i32 = 0;
    var status: UErrorCode = U_ZERO_ERROR;
    const result = zphp_unum_parseDouble(f, u16src.ptr, @intCast(u16src.len), &pos, &status);
    if (status > U_ZERO_ERROR) return .{ .bool = false };
    if (@trunc(result) == result and result < 1e15 and result > -1e15) {
        return .{ .int = @intFromFloat(result) };
    }
    return .{ .float = result };
}

fn nfSetAttribute(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .int) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const f = getNumFmt(obj) orelse return .{ .bool = false };
    switch (args[1]) {
        .int => |i| zphp_unum_setAttribute(f, @intCast(args[0].int), @intCast(i)),
        .float => |fl| zphp_unum_setDoubleAttribute(f, @intCast(args[0].int), fl),
        else => return .{ .bool = false },
    }
    return .{ .bool = true };
}

fn nfGetAttribute(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .int) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const f = getNumFmt(obj) orelse return .{ .bool = false };
    return .{ .int = @intCast(zphp_unum_getAttribute(f, @intCast(args[0].int))) };
}

// ---------------- Transliterator ----------------

fn getTranslit(obj: *const PhpObject) ?*UTransliterator {
    const v = obj.get("__trans");
    if (v != .int or v.int == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(v.int)));
}

fn transCreateStatic(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .null;
    const id_u16 = try utf8ToU16(ctx, args[0].string);
    defer ctx.allocator.free(id_u16);
    var status: UErrorCode = U_ZERO_ERROR;
    const dir: i32 = if (args.len > 1 and args[1] == .int and args[1].int == 1) 1 else 0;
    const t = zphp_utrans_openU(id_u16.ptr, @intCast(id_u16.len), dir, null, 0, null, &status);
    if (status > U_ZERO_ERROR or t == null) return .null;
    const obj = try ctx.createObject("Transliterator");
    try obj.set(ctx.allocator, "__trans", .{ .int = @intCast(@intFromPtr(t.?)) });
    try obj.set(ctx.allocator, "id", .{ .string = try dupString(ctx, args[0].string) });
    return .{ .object = obj };
}

fn transTransliterate(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const t = getTranslit(obj) orelse return .{ .bool = false };
    const u16src = try utf8ToU16(ctx, args[0].string);
    defer ctx.allocator.free(u16src);

    const cap: i32 = @intCast(u16src.len * 4 + 16);
    const buf = try ctx.allocator.alloc(u16, @intCast(cap));
    defer ctx.allocator.free(buf);
    @memcpy(buf[0..u16src.len], u16src);

    var text_len: i32 = @intCast(u16src.len);
    var limit: i32 = text_len;
    var status: UErrorCode = U_ZERO_ERROR;
    zphp_utrans_transUChars(t, buf.ptr, &text_len, cap, 0, &limit, &status);
    if (status > U_ZERO_ERROR) return .{ .bool = false };
    const out = try u16ToUtf8(ctx, buf[0..@intCast(text_len)]);
    return .{ .string = out };
}

// ---------------- IntlDateFormatter ----------------

fn getDateFmt(obj: *const PhpObject) ?*UDateFormat {
    const v = obj.get("__dfmt");
    if (v != .int or v.int == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(v.int)));
}

fn openDateFmt(ctx: *NativeContext, locale: []const u8, date_style: i32, time_style: i32, tz: ?[]const u8, pattern: ?[]const u8) !?*UDateFormat {
    const loc_z = try dupZ(ctx, locale);
    const tz_u16: ?[]u16 = if (tz) |t| try utf8ToU16(ctx, t) else null;
    defer if (tz_u16) |b| ctx.allocator.free(b);
    const pat_u16: ?[]u16 = if (pattern) |p| try utf8ToU16(ctx, p) else null;
    defer if (pat_u16) |b| ctx.allocator.free(b);

    const tz_ptr: ?[*]const UChar = if (tz_u16) |b| b.ptr else null;
    const tz_len: i32 = if (tz_u16) |b| @intCast(b.len) else -1;
    const pat_ptr: ?[*]const UChar = if (pat_u16) |b| b.ptr else null;
    const pat_len: i32 = if (pat_u16) |b| @intCast(b.len) else -1;

    // when a pattern is supplied PHP forces both styles to UDAT_PATTERN (-2);
    // otherwise honor the requested style constants
    const t_style: i32 = if (pat_u16 != null) -2 else time_style;
    const d_style: i32 = if (pat_u16 != null) -2 else date_style;

    var status: UErrorCode = U_ZERO_ERROR;
    const f = zphp_udat_open(t_style, d_style, loc_z.ptr, tz_ptr, tz_len, pat_ptr, pat_len, &status);
    if (status > U_ZERO_ERROR) return null;
    return f;
}

fn defaultTzName(ctx: *NativeContext) []const u8 {
    return ctx.vm.default_tz_name;
}

fn dfConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[0] != .string) return .null;
    const obj = getThis(ctx) orelse return .null;
    const date_style: i32 = if (args[1] == .int) @intCast(args[1].int) else 0;
    const time_style: i32 = if (args[2] == .int) @intCast(args[2].int) else 0;
    const tz_opt: ?[]const u8 = if (args.len > 3 and args[3] == .string and args[3].string.len > 0) args[3].string else defaultTzName(ctx);
    // skip args[4] (calendar) for now
    const pat_opt: ?[]const u8 = if (args.len > 5 and args[5] == .string and args[5].string.len > 0) args[5].string else null;

    const f = (try openDateFmt(ctx, args[0].string, date_style, time_style, tz_opt, pat_opt)) orelse return .null;
    try obj.set(ctx.allocator, "__dfmt", .{ .int = @intCast(@intFromPtr(f)) });
    return .null;
}

fn dfCreateStatic(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[0] != .string) return .null;
    const obj = try ctx.createObject("IntlDateFormatter");
    const date_style: i32 = if (args[1] == .int) @intCast(args[1].int) else 0;
    const time_style: i32 = if (args[2] == .int) @intCast(args[2].int) else 0;
    const tz_opt: ?[]const u8 = if (args.len > 3 and args[3] == .string and args[3].string.len > 0) args[3].string else defaultTzName(ctx);
    const pat_opt: ?[]const u8 = if (args.len > 5 and args[5] == .string and args[5].string.len > 0) args[5].string else null;
    const f = (try openDateFmt(ctx, args[0].string, date_style, time_style, tz_opt, pat_opt)) orelse return .null;
    try obj.set(ctx.allocator, "__dfmt", .{ .int = @intCast(@intFromPtr(f)) });
    return .{ .object = obj };
}

fn dfFormat(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const f = getDateFmt(obj) orelse return .{ .bool = false };
    const millis: f64 = switch (args[0]) {
        .int => |i| @as(f64, @floatFromInt(i)) * 1000.0,
        .float => |fl| fl * 1000.0,
        else => return .{ .bool = false },
    };
    var buf: [256]UChar = undefined;
    var status: UErrorCode = U_ZERO_ERROR;
    const n = zphp_udat_format(f, millis, &buf, @intCast(buf.len), null, &status);
    if (status > U_ZERO_ERROR) return .{ .bool = false };
    const out = try u16ToUtf8(ctx, buf[0..@intCast(n)]);
    return .{ .string = out };
}

fn dfParse(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const f = getDateFmt(obj) orelse return .{ .bool = false };
    const u16src = try utf8ToU16(ctx, args[0].string);
    defer ctx.allocator.free(u16src);
    var pos: i32 = 0;
    var status: UErrorCode = U_ZERO_ERROR;
    const millis = zphp_udat_parse(f, u16src.ptr, @intCast(u16src.len), &pos, &status);
    if (status > U_ZERO_ERROR) return .{ .bool = false };
    return .{ .int = @intFromFloat(millis / 1000.0) };
}

fn dfGetPattern(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const f = getDateFmt(obj) orelse return .{ .bool = false };
    var buf: [256]UChar = undefined;
    var status: UErrorCode = U_ZERO_ERROR;
    const n = zphp_udat_toPattern(f, 0, &buf, @intCast(buf.len), &status);
    if (status > U_ZERO_ERROR) return .{ .bool = false };
    const out = try u16ToUtf8(ctx, buf[0..@intCast(n)]);
    return .{ .string = out };
}

fn dfSetPattern(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const f = getDateFmt(obj) orelse return .{ .bool = false };
    const u16src = try utf8ToU16(ctx, args[0].string);
    defer ctx.allocator.free(u16src);
    zphp_udat_applyPattern(f, 0, u16src.ptr, @intCast(u16src.len));
    return .{ .bool = true };
}

// ---------------- IDNA (idn_to_ascii / idn_to_utf8) ----------------

fn idnConvert(ctx: *NativeContext, args: []const Value, to_ascii: bool) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    var status: UErrorCode = U_ZERO_ERROR;
    const idna = zphp_uidna_openUTS46(0, &status) orelse return .{ .bool = false };
    defer zphp_uidna_close(idna);
    if (status > U_ZERO_ERROR) return .{ .bool = false };

    const info_size = zphp_uidna_info_size();
    const info_buf = try ctx.allocator.alloc(u8, info_size);
    defer ctx.allocator.free(info_buf);
    zphp_uidna_info_init(@ptrCast(info_buf.ptr));

    const u16src = try utf8ToU16(ctx, args[0].string);
    defer ctx.allocator.free(u16src);
    var dest: [512]UChar = undefined;
    status = U_ZERO_ERROR;
    const n = if (to_ascii)
        zphp_uidna_nameToASCII(idna, u16src.ptr, @intCast(u16src.len), &dest, @intCast(dest.len), @ptrCast(info_buf.ptr), &status)
    else
        zphp_uidna_nameToUnicode(idna, u16src.ptr, @intCast(u16src.len), &dest, @intCast(dest.len), @ptrCast(info_buf.ptr), &status);
    if (status > U_ZERO_ERROR or n < 0) return .{ .bool = false };
    const out = try u16ToUtf8(ctx, dest[0..@intCast(n)]);
    return .{ .string = out };
}

fn idnToAscii(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return idnConvert(ctx, args, true);
}

fn idnToUtf8(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return idnConvert(ctx, args, false);
}

// ---------------- MessageFormatter ----------------

fn buildArgEntries(ctx: *NativeContext, arr: *PhpArray, owned_u16: *std.ArrayListUnmanaged([]u16)) ![]ArgEntry {
    const out = try ctx.allocator.alloc(ArgEntry, arr.entries.items.len);
    for (arr.entries.items, 0..) |e, i| {
        var ent = ArgEntry{ .type = ARG_STRING, .ival = 0, .dval = 0, .sval = null, .slen = 0, .name = null, .name_len = 0 };

        if (e.key == .string) {
            const name_u16 = try utf8ToU16(ctx, e.key.string);
            try owned_u16.append(ctx.allocator, name_u16);
            ent.name = name_u16.ptr;
            ent.name_len = @intCast(name_u16.len);
        }

        switch (e.value) {
            .int => |n| {
                ent.type = ARG_INT;
                ent.ival = n;
            },
            .float => |f| {
                ent.type = ARG_DOUBLE;
                ent.dval = f;
            },
            .string => |s| {
                ent.type = ARG_STRING;
                const u16s = try utf8ToU16(ctx, s);
                try owned_u16.append(ctx.allocator, u16s);
                ent.sval = u16s.ptr;
                ent.slen = @intCast(u16s.len);
            },
            .bool => |b| {
                ent.type = ARG_INT;
                ent.ival = if (b) 1 else 0;
            },
            else => {
                ent.type = ARG_STRING;
                const u16s = try utf8ToU16(ctx, "");
                try owned_u16.append(ctx.allocator, u16s);
                ent.sval = u16s.ptr;
                ent.slen = 0;
            },
        }
        out[i] = ent;
    }
    return out;
}

fn msgFormatCommon(ctx: *NativeContext, locale: []const u8, pattern: []const u8, args_val: Value) RuntimeError!Value {
    if (args_val != .array) return .{ .bool = false };
    const arr = args_val.array;

    const loc_z = try dupZ(ctx, locale);
    const pat_u16 = try utf8ToU16(ctx, pattern);
    defer ctx.allocator.free(pat_u16);

    var owned_u16 = std.ArrayListUnmanaged([]u16){};
    defer {
        for (owned_u16.items) |b| ctx.allocator.free(b);
        owned_u16.deinit(ctx.allocator);
    }

    const arg_entries = try buildArgEntries(ctx, arr, &owned_u16);
    defer ctx.allocator.free(arg_entries);

    var any_named = false;
    for (arr.entries.items) |e| if (e.key == .string) { any_named = true; break; };

    var status: UErrorCode = U_ZERO_ERROR;
    var buf: [4096]UChar = undefined;
    const n = if (any_named)
        zphp_msgfmt_format(loc_z.ptr, pat_u16.ptr, @intCast(pat_u16.len), arg_entries.ptr, @intCast(arg_entries.len), &buf, @intCast(buf.len), &status)
    else
        zphp_msgfmt_format_positional(loc_z.ptr, pat_u16.ptr, @intCast(pat_u16.len), arg_entries.ptr, @intCast(arg_entries.len), &buf, @intCast(buf.len), &status);

    if (status > U_ZERO_ERROR or n < 0) return .{ .bool = false };
    const out = try u16ToUtf8(ctx, buf[0..@intCast(n)]);
    return .{ .string = out };
}

fn mfConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .null;
    const obj = getThis(ctx) orelse return .null;
    try obj.set(ctx.allocator, "__locale", .{ .string = try dupString(ctx, args[0].string) });
    try obj.set(ctx.allocator, "__pattern", .{ .string = try dupString(ctx, args[1].string) });
    return .null;
}

fn mfCreate(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const obj = try ctx.createObject("MessageFormatter");
    try obj.set(ctx.allocator, "__locale", .{ .string = try dupString(ctx, args[0].string) });
    try obj.set(ctx.allocator, "__pattern", .{ .string = try dupString(ctx, args[1].string) });
    return .{ .object = obj };
}

fn mfFormat(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const loc = obj.get("__locale");
    const pat = obj.get("__pattern");
    if (loc != .string or pat != .string) return .{ .bool = false };
    return msgFormatCommon(ctx, loc.string, pat.string, args[0]);
}

fn mfFormatMessage(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    return msgFormatCommon(ctx, args[0].string, args[1].string, args[2]);
}

fn mfGetPattern(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .string = try dupString(ctx, "") };
    const v = obj.get("__pattern");
    if (v == .string) return v;
    return .{ .string = try dupString(ctx, "") };
}

fn mfSetPattern(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    try obj.set(ctx.allocator, "__pattern", .{ .string = try dupString(ctx, args[0].string) });
    return .{ .bool = true };
}

fn mfGetLocale(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .string = try dupString(ctx, "") };
    const v = obj.get("__locale");
    if (v == .string) return v;
    return .{ .string = try dupString(ctx, "") };
}

// ---------------- IntlCalendar ----------------

fn getCal(obj: *const PhpObject) ?*UCalendar {
    const v = obj.get("__cal");
    if (v != .int or v.int == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(v.int)));
}

fn openCalendar(ctx: *NativeContext, tz_opt: ?[]const u8, locale: []const u8, cal_type: c_int) !?*UCalendar {
    var status: UErrorCode = U_ZERO_ERROR;
    const loc_z = try dupZ(ctx, locale);
    const tz_u16: ?[]u16 = if (tz_opt) |t| try utf8ToU16(ctx, t) else null;
    defer if (tz_u16) |b| ctx.allocator.free(b);
    const tz_ptr: ?[*]const UChar = if (tz_u16) |b| b.ptr else null;
    const tz_len: i32 = if (tz_u16) |b| @intCast(b.len) else 0;
    const cal = zphp_ucal_open(tz_ptr, tz_len, loc_z.ptr, cal_type, &status);
    if (status > U_ZERO_ERROR) return null;
    return cal;
}

fn calCreateInstance(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    var tz_opt: ?[]const u8 = null;
    if (args.len > 0 and args[0] == .string) tz_opt = args[0].string;
    var locale: []const u8 = "";
    if (args.len > 1 and args[1] == .string) locale = args[1].string;
    if (locale.len == 0) {
        const def = zphp_uloc_getDefault();
        locale = def[0..cstrLen(def)];
    }
    const cal = (try openCalendar(ctx, tz_opt, locale, 0)) orelse return .null;
    const obj = try ctx.createObject("IntlGregorianCalendar");
    try obj.set(ctx.allocator, "__cal", .{ .int = @intCast(@intFromPtr(cal)) });
    try obj.set(ctx.allocator, "__locale", .{ .string = try dupString(ctx, locale) });
    return .{ .object = obj };
}

fn calConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    // PHP: new IntlGregorianCalendar(...) supports several arg shapes:
    //   ()                          - default tz, default locale
    //   (string $tz, string $loc)   - explicit
    //   (int y, int m, int d)       - by-date
    //   (int y, int m, int d, int h, int mi, int s)
    const obj = getThis(ctx) orelse return .null;

    // tz/locale form
    if (args.len <= 2 and (args.len == 0 or args[0] == .string or args[0] == .null)) {
        var tz_opt: ?[]const u8 = null;
        if (args.len > 0 and args[0] == .string) tz_opt = args[0].string;
        var locale: []const u8 = "";
        if (args.len > 1 and args[1] == .string) locale = args[1].string;
        if (locale.len == 0) {
            const def = zphp_uloc_getDefault();
            locale = def[0..cstrLen(def)];
        }
        const cal = (try openCalendar(ctx, tz_opt, locale, 0)) orelse return .null;
        try obj.set(ctx.allocator, "__cal", .{ .int = @intCast(@intFromPtr(cal)) });
        try obj.set(ctx.allocator, "__locale", .{ .string = try dupString(ctx, locale) });
        return .null;
    }

    // integer form: y, m, d, [h, mi, s]
    const def_locale_ptr = zphp_uloc_getDefault();
    const def_locale = def_locale_ptr[0..cstrLen(def_locale_ptr)];
    const cal = (try openCalendar(ctx, null, def_locale, 0)) orelse return .null;
    try obj.set(ctx.allocator, "__cal", .{ .int = @intCast(@intFromPtr(cal)) });
    try obj.set(ctx.allocator, "__locale", .{ .string = try dupString(ctx, def_locale) });
    if (args.len >= 3 and args[0] == .int and args[1] == .int and args[2] == .int) {
        var status: UErrorCode = U_ZERO_ERROR;
        if (args.len >= 6 and args[3] == .int and args[4] == .int and args[5] == .int) {
            zphp_ucal_setDateTime(cal, @intCast(args[0].int), @intCast(args[1].int), @intCast(args[2].int), @intCast(args[3].int), @intCast(args[4].int), @intCast(args[5].int), &status);
        } else {
            zphp_ucal_setDate(cal, @intCast(args[0].int), @intCast(args[1].int), @intCast(args[2].int), &status);
        }
    }
    return .null;
}

fn calGet(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .int) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const cal = getCal(obj) orelse return .{ .bool = false };
    var status: UErrorCode = U_ZERO_ERROR;
    const r = zphp_ucal_get(cal, @intCast(args[0].int), &status);
    if (status > U_ZERO_ERROR) return .{ .bool = false };
    return .{ .int = @intCast(r) };
}

fn calSet(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .int or args[1] != .int) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const cal = getCal(obj) orelse return .{ .bool = false };
    zphp_ucal_set(cal, @intCast(args[0].int), @intCast(args[1].int));
    return .{ .bool = true };
}

fn calAdd(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .int or args[1] != .int) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const cal = getCal(obj) orelse return .{ .bool = false };
    var status: UErrorCode = U_ZERO_ERROR;
    zphp_ucal_add(cal, @intCast(args[0].int), @intCast(args[1].int), &status);
    return .{ .bool = status <= U_ZERO_ERROR };
}

fn calRoll(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .int) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const cal = getCal(obj) orelse return .{ .bool = false };
    const amount: i32 = switch (args[1]) {
        .int => |i| @intCast(i),
        .bool => |b| if (b) 1 else -1,
        else => return .{ .bool = false },
    };
    var status: UErrorCode = U_ZERO_ERROR;
    zphp_ucal_roll(cal, @intCast(args[0].int), amount, &status);
    return .{ .bool = status <= U_ZERO_ERROR };
}

fn calGetTime(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const cal = getCal(obj) orelse return .{ .bool = false };
    var status: UErrorCode = U_ZERO_ERROR;
    const millis = zphp_ucal_getMillis(cal, &status);
    if (status > U_ZERO_ERROR) return .{ .bool = false };
    return .{ .float = millis };
}

fn calSetTime(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const cal = getCal(obj) orelse return .{ .bool = false };
    const millis: f64 = switch (args[0]) {
        .int => |i| @floatFromInt(i),
        .float => |f| f,
        else => return .{ .bool = false },
    };
    var status: UErrorCode = U_ZERO_ERROR;
    zphp_ucal_setMillis(cal, millis, &status);
    return .{ .bool = status <= U_ZERO_ERROR };
}

fn calInDaylightTime(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const cal = getCal(obj) orelse return .{ .bool = false };
    var status: UErrorCode = U_ZERO_ERROR;
    return .{ .bool = zphp_ucal_inDaylightTime(cal, &status) != 0 };
}

fn calIsSet(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .int) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const cal = getCal(obj) orelse return .{ .bool = false };
    return .{ .bool = zphp_ucal_isSet(cal, @intCast(args[0].int)) != 0 };
}

fn calClear(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const cal = getCal(obj) orelse return .{ .bool = false };
    if (args.len > 0 and args[0] == .int) {
        zphp_ucal_clearField(cal, @intCast(args[0].int));
    } else {
        zphp_ucal_clear(cal);
    }
    return .{ .bool = true };
}

fn calGetTimeZoneId(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const cal = getCal(obj) orelse return .{ .bool = false };
    var buf: [128]UChar = undefined;
    var status: UErrorCode = U_ZERO_ERROR;
    const n = zphp_ucal_getTimeZoneID(cal, &buf, @intCast(buf.len), &status);
    if (status > U_ZERO_ERROR or n <= 0) return .{ .string = try dupString(ctx, "") };
    const out = try u16ToUtf8(ctx, buf[0..@intCast(n)]);
    return .{ .string = out };
}

fn calSetTimeZone(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const cal = getCal(obj) orelse return .{ .bool = false };
    const u16src = try utf8ToU16(ctx, args[0].string);
    defer ctx.allocator.free(u16src);
    var status: UErrorCode = U_ZERO_ERROR;
    zphp_ucal_setTimeZone(cal, u16src.ptr, @intCast(u16src.len), &status);
    return .{ .bool = status <= U_ZERO_ERROR };
}

fn calGetFirstDayOfWeek(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    const cal = getCal(obj) orelse return .{ .int = 0 };
    var status: UErrorCode = U_ZERO_ERROR;
    return .{ .int = @intCast(zphp_ucal_getFirstDayOfWeek(cal, &status)) };
}

fn calSetFirstDayOfWeek(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .int) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const cal = getCal(obj) orelse return .{ .bool = false };
    zphp_ucal_setFirstDayOfWeek(cal, @intCast(args[0].int));
    return .{ .bool = true };
}

fn calIsWeekend(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const cal = getCal(obj) orelse return .{ .bool = false };
    var status: UErrorCode = U_ZERO_ERROR;
    const date: f64 = if (args.len > 0) switch (args[0]) {
        .int => |i| @floatFromInt(i),
        .float => |f| f,
        else => zphp_ucal_getMillis(cal, &status),
    } else zphp_ucal_getMillis(cal, &status);
    return .{ .bool = zphp_ucal_isWeekend(cal, date, &status) != 0 };
}

fn calGetType(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const cal = getCal(obj) orelse return .{ .bool = false };
    var buf: [64]u8 = undefined;
    var status: UErrorCode = U_ZERO_ERROR;
    const n = zphp_ucal_getType(cal, &buf, @intCast(buf.len), &status);
    if (status > U_ZERO_ERROR or n <= 0) return .{ .string = try dupString(ctx, "") };
    return .{ .string = try dupString(ctx, buf[0..@intCast(n)]) };
}

fn calGetLocale(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const cal = getCal(obj) orelse return .{ .bool = false };
    var buf: [128]u8 = undefined;
    var status: UErrorCode = U_ZERO_ERROR;
    const ltype: c_int = if (args.len > 0 and args[0] == .int) @intCast(args[0].int) else 0;
    const n = zphp_ucal_getLocaleByType(cal, ltype, &buf, @intCast(buf.len), &status);
    if (status > U_ZERO_ERROR or n <= 0) return .{ .string = try dupString(ctx, "") };
    return .{ .string = try dupString(ctx, buf[0..@intCast(n)]) };
}

fn calGetActualMaximum(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .int) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const cal = getCal(obj) orelse return .{ .bool = false };
    var status: UErrorCode = U_ZERO_ERROR;
    // UCAL_ACTUAL_MAXIMUM = 5: this-calendar's actual maximum for the field
    // (e.g. 29 for Feb in a leap year). UCAL_LEAST_MAXIMUM (3) would return
    // 28 across all years which is the wrong thing
    return .{ .int = @intCast(zphp_ucal_getLimit(cal, @intCast(args[0].int), 5, &status)) };
}

fn calGetActualMinimum(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .int) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const cal = getCal(obj) orelse return .{ .bool = false };
    var status: UErrorCode = U_ZERO_ERROR;
    // UCAL_ACTUAL_MINIMUM = 4
    return .{ .int = @intCast(zphp_ucal_getLimit(cal, @intCast(args[0].int), 4, &status)) };
}

fn calIsLenient(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const cal = getCal(obj) orelse return .{ .bool = false };
    return .{ .bool = zphp_ucal_getLenient(cal) != 0 };
}

fn calSetLenient(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .bool) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const cal = getCal(obj) orelse return .{ .bool = false };
    zphp_ucal_setLenient(cal, if (args[0].bool) 1 else 0);
    return .{ .bool = true };
}

fn calEquals(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    // PHP's IntlCalendar::equals compares calendars by their effective wall
    // time. ucal_equivalentTo is the wrong check - it tests calendar-type
    // and tz equivalence which is stricter than what PHP does
    if (args.len < 1 or args[0] != .object) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const a = getCal(obj) orelse return .{ .bool = false };
    const b = getCal(args[0].object) orelse return .{ .bool = false };
    var s1: UErrorCode = U_ZERO_ERROR;
    var s2: UErrorCode = U_ZERO_ERROR;
    return .{ .bool = zphp_ucal_getMillis(a, &s1) == zphp_ucal_getMillis(b, &s2) };
}

// ---------------- IntlBreakIterator ----------------

fn getBrk(obj: *const PhpObject) ?*ZphpBrk {
    const v = obj.get("__brk");
    if (v != .int or v.int == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(v.int)));
}

fn openBrk(ctx: *NativeContext, brk_type: c_int, locale: []const u8) !?*ZphpBrk {
    var status: UErrorCode = U_ZERO_ERROR;
    const loc = if (locale.len > 0) locale else blk: {
        const def = zphp_uloc_getDefault();
        break :blk def[0..cstrLen(def)];
    };
    const loc_z = try dupZ(ctx, loc);
    const w = zphp_ubrk_open(brk_type, loc_z.ptr, &status);
    if (status > U_ZERO_ERROR) return null;
    return w;
}

fn brkMakeInstance(ctx: *NativeContext, brk_type: c_int, locale: []const u8) RuntimeError!Value {
    const w = (try openBrk(ctx, brk_type, locale)) orelse return .null;
    const obj = try ctx.createObject("IntlBreakIterator");
    try obj.set(ctx.allocator, "__brk", .{ .int = @intCast(@intFromPtr(w)) });
    try obj.set(ctx.allocator, "__type", .{ .int = @intCast(brk_type) });
    try obj.set(ctx.allocator, "__locale", .{ .string = try dupString(ctx, locale) });
    return .{ .object = obj };
}

fn brkCreateWord(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const locale = if (args.len > 0 and args[0] == .string) args[0].string else "";
    return brkMakeInstance(ctx, 1, locale);
}

fn brkCreateChar(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const locale = if (args.len > 0 and args[0] == .string) args[0].string else "";
    return brkMakeInstance(ctx, 0, locale);
}

fn brkCreateLine(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const locale = if (args.len > 0 and args[0] == .string) args[0].string else "";
    return brkMakeInstance(ctx, 2, locale);
}

fn brkCreateSentence(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const locale = if (args.len > 0 and args[0] == .string) args[0].string else "";
    return brkMakeInstance(ctx, 3, locale);
}

fn brkCreateTitle(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const locale = if (args.len > 0 and args[0] == .string) args[0].string else "";
    return brkMakeInstance(ctx, 4, locale);
}

fn brkSetText(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const w = getBrk(obj) orelse return .{ .bool = false };
    var status: UErrorCode = U_ZERO_ERROR;
    const txt = args[0].string;
    const ptr: [*]const u8 = if (txt.len > 0) txt.ptr else @ptrCast(""[0..]);
    zphp_ubrk_setText(w, ptr, @intCast(txt.len), &status);
    if (status > U_ZERO_ERROR) return .{ .bool = false };
    // also store the text so getText round-trips without losing it
    try obj.set(ctx.allocator, "__text", .{ .string = try dupString(ctx, txt) });
    return .{ .bool = true };
}

fn brkGetText(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const v = obj.get("__text");
    if (v == .string) return v;
    return .{ .string = try dupString(ctx, "") };
}

fn brkFirst(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = -1 };
    const w = getBrk(obj) orelse return .{ .int = -1 };
    return .{ .int = @intCast(zphp_ubrk_first(w)) };
}

fn brkLast(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = -1 };
    const w = getBrk(obj) orelse return .{ .int = -1 };
    return .{ .int = @intCast(zphp_ubrk_last(w)) };
}

fn brkNext(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = -1 };
    const w = getBrk(obj) orelse return .{ .int = -1 };
    // PHP's next($offset) advances by that many boundaries when given
    if (args.len > 0 and args[0] == .int) {
        const n = args[0].int;
        var last: i32 = zphp_ubrk_current(w);
        if (n > 0) {
            var i: i64 = 0;
            while (i < n) : (i += 1) {
                last = zphp_ubrk_next(w);
                if (last == -1) break;
            }
        } else if (n < 0) {
            var i: i64 = 0;
            while (i < -n) : (i += 1) {
                last = zphp_ubrk_previous(w);
                if (last == -1) break;
            }
        }
        return .{ .int = @intCast(last) };
    }
    return .{ .int = @intCast(zphp_ubrk_next(w)) };
}

fn brkPrevious(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = -1 };
    const w = getBrk(obj) orelse return .{ .int = -1 };
    return .{ .int = @intCast(zphp_ubrk_previous(w)) };
}

fn brkCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = -1 };
    const w = getBrk(obj) orelse return .{ .int = -1 };
    return .{ .int = @intCast(zphp_ubrk_current(w)) };
}

fn brkFollowing(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .int) return .{ .int = -1 };
    const obj = getThis(ctx) orelse return .{ .int = -1 };
    const w = getBrk(obj) orelse return .{ .int = -1 };
    return .{ .int = @intCast(zphp_ubrk_following(w, @intCast(args[0].int))) };
}

fn brkPreceding(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .int) return .{ .int = -1 };
    const obj = getThis(ctx) orelse return .{ .int = -1 };
    const w = getBrk(obj) orelse return .{ .int = -1 };
    return .{ .int = @intCast(zphp_ubrk_preceding(w, @intCast(args[0].int))) };
}

fn brkIsBoundary(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .int) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const w = getBrk(obj) orelse return .{ .bool = false };
    return .{ .bool = zphp_ubrk_isBoundary(w, @intCast(args[0].int)) != 0 };
}

fn brkGetRuleStatus(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    const w = getBrk(obj) orelse return .{ .int = 0 };
    return .{ .int = @intCast(zphp_ubrk_getRuleStatus(w)) };
}

fn brkGetLocale(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .string = try dupString(ctx, "") };
    const w = getBrk(obj) orelse return .{ .string = try dupString(ctx, "") };
    var buf: [128]u8 = undefined;
    var status: UErrorCode = U_ZERO_ERROR;
    const ltype: c_int = if (args.len > 0 and args[0] == .int) @intCast(args[0].int) else 0;
    const n = zphp_ubrk_getLocaleByType(w, ltype, &buf, @intCast(buf.len), &status);
    if (status > U_ZERO_ERROR or n <= 0) return .{ .string = try dupString(ctx, "") };
    return .{ .string = try dupString(ctx, buf[0..@intCast(n)]) };
}

// ---------------- registration ----------------

pub const entries = .{
    .{ "locale_get_default", localeGetDefault },
    .{ "locale_set_default", localeSetDefault },
    .{ "locale_get_primary_language", localeGetPrimaryLanguage },
    .{ "locale_get_region", localeGetRegion },
    .{ "locale_get_script", localeGetScript },
    .{ "locale_canonicalize", localeCanonicalize },
    .{ "locale_get_display_name", localeGetDisplayName },
    .{ "locale_get_display_language", localeGetDisplayLanguage },
    .{ "locale_get_display_region", localeGetDisplayRegion },
    .{ "locale_get_display_script", localeGetDisplayScript },
    .{ "normalizer_normalize", normalizerNormalize },
    .{ "normalizer_is_normalized", normalizerIsNormalized },
    .{ "idn_to_ascii", idnToAscii },
    .{ "idn_to_utf8", idnToUtf8 },
    .{ "transliterator_transliterate", transliteratorTransliterate },
    .{ "transliterator_create", transCreateStatic },
    .{ "msgfmt_create", mfCreate },
    .{ "msgfmt_format_message", mfFormatMessage },
};

// procedural shim: accepts a Transliterator instance or an ID string
fn transliteratorTransliterate(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[1] != .string) return .{ .bool = false };

    var t_obj: ?*PhpObject = null;
    var owned = false;
    defer if (owned and t_obj != null) {
        if (getTranslit(t_obj.?)) |tr| zphp_utrans_close(tr);
    };

    switch (args[0]) {
        .object => |o| {
            if (!std.mem.eql(u8, o.class_name, "Transliterator")) return .{ .bool = false };
            t_obj = o;
        },
        .string => {
            const created = try transCreateStatic(ctx, args[0..1]);
            if (created != .object) return .{ .bool = false };
            t_obj = created.object;
            owned = false; // the wrapper is tracked by ctx; native close would double-free
        },
        else => return .{ .bool = false },
    }

    const t = getTranslit(t_obj.?) orelse return .{ .bool = false };
    const u16src = try utf8ToU16(ctx, args[1].string);
    defer ctx.allocator.free(u16src);

    const cap: i32 = @intCast(u16src.len * 4 + 16);
    const buf = try ctx.allocator.alloc(u16, @intCast(cap));
    defer ctx.allocator.free(buf);
    @memcpy(buf[0..u16src.len], u16src);

    var text_len: i32 = @intCast(u16src.len);
    var limit: i32 = text_len;
    var status: UErrorCode = U_ZERO_ERROR;
    zphp_utrans_transUChars(t, buf.ptr, &text_len, cap, 0, &limit, &status);
    if (status > U_ZERO_ERROR) return .{ .bool = false };
    const out = try u16ToUtf8(ctx, buf[0..@intCast(text_len)]);
    return .{ .string = out };
}

pub fn register(vm: *VM, a: Allocator) !void {
    try registerNormalizerClass(vm, a);
    try registerLocaleClass(vm, a);
    try registerCollatorClass(vm, a);
    try registerNumberFormatterClass(vm, a);
    try registerTransliteratorClass(vm, a);
    try registerDateFormatterClass(vm, a);
    try registerMessageFormatterClass(vm, a);
    try registerIntlCalendarClass(vm, a);
    try registerBreakIteratorClass(vm, a);
    try registerConstants(vm, a);
}

fn registerBreakIteratorClass(vm: *VM, a: Allocator) !void {
    inline for (.{ "IntlBreakIterator", "IntlRuleBasedBreakIterator", "IntlCodePointBreakIterator" }) |cls_name| {
        var def = ClassDef{ .name = cls_name };
        if (comptime !std.mem.eql(u8, cls_name, "IntlBreakIterator")) {
            def.parent = "IntlBreakIterator";
        }
        try def.methods.put(a, "createWordInstance", .{ .name = "createWordInstance", .arity = 0, .is_static = true });
        try def.methods.put(a, "createCharacterInstance", .{ .name = "createCharacterInstance", .arity = 0, .is_static = true });
        try def.methods.put(a, "createLineInstance", .{ .name = "createLineInstance", .arity = 0, .is_static = true });
        try def.methods.put(a, "createSentenceInstance", .{ .name = "createSentenceInstance", .arity = 0, .is_static = true });
        try def.methods.put(a, "createTitleInstance", .{ .name = "createTitleInstance", .arity = 0, .is_static = true });
        try def.methods.put(a, "setText", .{ .name = "setText", .arity = 1 });
        try def.methods.put(a, "getText", .{ .name = "getText", .arity = 0 });
        try def.methods.put(a, "first", .{ .name = "first", .arity = 0 });
        try def.methods.put(a, "last", .{ .name = "last", .arity = 0 });
        try def.methods.put(a, "next", .{ .name = "next", .arity = 0 });
        try def.methods.put(a, "previous", .{ .name = "previous", .arity = 0 });
        try def.methods.put(a, "current", .{ .name = "current", .arity = 0 });
        try def.methods.put(a, "following", .{ .name = "following", .arity = 1 });
        try def.methods.put(a, "preceding", .{ .name = "preceding", .arity = 1 });
        try def.methods.put(a, "isBoundary", .{ .name = "isBoundary", .arity = 1 });
        try def.methods.put(a, "getRuleStatus", .{ .name = "getRuleStatus", .arity = 0 });
        try def.methods.put(a, "getLocale", .{ .name = "getLocale", .arity = 0 });

        try def.constant_order.append(a, "DONE");
        try def.constant_names.put(a, "DONE", {});
        try def.static_props.put(a, "DONE", .{ .int = -1 });
        // rule status tag ranges (PHP exposes these constants on the class)
        const tag_consts = .{
            .{ "WORD_NONE", 0 }, .{ "WORD_NONE_LIMIT", 100 },
            .{ "WORD_NUMBER", 100 }, .{ "WORD_NUMBER_LIMIT", 200 },
            .{ "WORD_LETTER", 200 }, .{ "WORD_LETTER_LIMIT", 300 },
            .{ "WORD_KANA", 300 }, .{ "WORD_KANA_LIMIT", 400 },
            .{ "WORD_IDEO", 400 }, .{ "WORD_IDEO_LIMIT", 500 },
            .{ "LINE_SOFT", 0 }, .{ "LINE_SOFT_LIMIT", 100 },
            .{ "LINE_HARD", 100 }, .{ "LINE_HARD_LIMIT", 200 },
            .{ "SENTENCE_TERM", 0 }, .{ "SENTENCE_TERM_LIMIT", 100 },
            .{ "SENTENCE_SEP", 100 }, .{ "SENTENCE_SEP_LIMIT", 200 },
        };
        inline for (tag_consts) |k| {
            try def.constant_order.append(a, k[0]);
            try def.constant_names.put(a, k[0], {});
            try def.static_props.put(a, k[0], .{ .int = k[1] });
        }

        try vm.classes.put(a, cls_name, def);

        try vm.native_fns.put(a, cls_name ++ "::createWordInstance", brkCreateWord);
        try vm.native_fns.put(a, cls_name ++ "::createCharacterInstance", brkCreateChar);
        try vm.native_fns.put(a, cls_name ++ "::createLineInstance", brkCreateLine);
        try vm.native_fns.put(a, cls_name ++ "::createSentenceInstance", brkCreateSentence);
        try vm.native_fns.put(a, cls_name ++ "::createTitleInstance", brkCreateTitle);
        try vm.native_fns.put(a, cls_name ++ "::setText", brkSetText);
        try vm.native_fns.put(a, cls_name ++ "::getText", brkGetText);
        try vm.native_fns.put(a, cls_name ++ "::first", brkFirst);
        try vm.native_fns.put(a, cls_name ++ "::last", brkLast);
        try vm.native_fns.put(a, cls_name ++ "::next", brkNext);
        try vm.native_fns.put(a, cls_name ++ "::previous", brkPrevious);
        try vm.native_fns.put(a, cls_name ++ "::current", brkCurrent);
        try vm.native_fns.put(a, cls_name ++ "::following", brkFollowing);
        try vm.native_fns.put(a, cls_name ++ "::preceding", brkPreceding);
        try vm.native_fns.put(a, cls_name ++ "::isBoundary", brkIsBoundary);
        try vm.native_fns.put(a, cls_name ++ "::getRuleStatus", brkGetRuleStatus);
        try vm.native_fns.put(a, cls_name ++ "::getLocale", brkGetLocale);
    }
}

fn registerIntlCalendarClass(vm: *VM, a: Allocator) !void {
    inline for (.{ "IntlCalendar", "IntlGregorianCalendar" }) |cls_name| {
        var def = ClassDef{ .name = cls_name };
        if (comptime std.mem.eql(u8, cls_name, "IntlGregorianCalendar")) {
            def.parent = "IntlCalendar";
        }
        try def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 0 });
        try def.methods.put(a, "createInstance", .{ .name = "createInstance", .arity = 0, .is_static = true });
        try def.methods.put(a, "get", .{ .name = "get", .arity = 1 });
        try def.methods.put(a, "set", .{ .name = "set", .arity = 2 });
        try def.methods.put(a, "add", .{ .name = "add", .arity = 2 });
        try def.methods.put(a, "roll", .{ .name = "roll", .arity = 2 });
        try def.methods.put(a, "getTime", .{ .name = "getTime", .arity = 0 });
        try def.methods.put(a, "setTime", .{ .name = "setTime", .arity = 1 });
        try def.methods.put(a, "inDaylightTime", .{ .name = "inDaylightTime", .arity = 0 });
        try def.methods.put(a, "isSet", .{ .name = "isSet", .arity = 1 });
        try def.methods.put(a, "clear", .{ .name = "clear", .arity = 0 });
        try def.methods.put(a, "setTimeZone", .{ .name = "setTimeZone", .arity = 1 });
        try def.methods.put(a, "getFirstDayOfWeek", .{ .name = "getFirstDayOfWeek", .arity = 0 });
        try def.methods.put(a, "setFirstDayOfWeek", .{ .name = "setFirstDayOfWeek", .arity = 1 });
        try def.methods.put(a, "isWeekend", .{ .name = "isWeekend", .arity = 0 });
        try def.methods.put(a, "getType", .{ .name = "getType", .arity = 0 });
        try def.methods.put(a, "getLocale", .{ .name = "getLocale", .arity = 0 });
        try def.methods.put(a, "getActualMaximum", .{ .name = "getActualMaximum", .arity = 1 });
        try def.methods.put(a, "getActualMinimum", .{ .name = "getActualMinimum", .arity = 1 });
        try def.methods.put(a, "isLenient", .{ .name = "isLenient", .arity = 0 });
        try def.methods.put(a, "setLenient", .{ .name = "setLenient", .arity = 1 });
        try def.methods.put(a, "equals", .{ .name = "equals", .arity = 1 });

        // calendar field constants. these double as both class constants and
        // PHP integer values the user passes to get()/set()/add()
        const fields = .{
            .{ "FIELD_ERA", 0 },             .{ "FIELD_YEAR", 1 },
            .{ "FIELD_MONTH", 2 },           .{ "FIELD_WEEK_OF_YEAR", 3 },
            .{ "FIELD_WEEK_OF_MONTH", 4 },   .{ "FIELD_DATE", 5 },
            .{ "FIELD_DAY_OF_YEAR", 6 },     .{ "FIELD_DAY_OF_WEEK", 7 },
            .{ "FIELD_DAY_OF_WEEK_IN_MONTH", 8 }, .{ "FIELD_AM_PM", 9 },
            .{ "FIELD_HOUR", 10 },           .{ "FIELD_HOUR_OF_DAY", 11 },
            .{ "FIELD_MINUTE", 12 },         .{ "FIELD_SECOND", 13 },
            .{ "FIELD_MILLISECOND", 14 },    .{ "FIELD_ZONE_OFFSET", 15 },
            .{ "FIELD_DST_OFFSET", 16 },     .{ "FIELD_YEAR_WOY", 17 },
            .{ "FIELD_DOW_LOCAL", 18 },      .{ "FIELD_EXTENDED_YEAR", 19 },
            .{ "FIELD_JULIAN_DAY", 20 },     .{ "FIELD_MILLISECONDS_IN_DAY", 21 },
            .{ "FIELD_IS_LEAP_MONTH", 22 },
            .{ "DOW_SUNDAY", 1 }, .{ "DOW_MONDAY", 2 }, .{ "DOW_TUESDAY", 3 },
            .{ "DOW_WEDNESDAY", 4 }, .{ "DOW_THURSDAY", 5 }, .{ "DOW_FRIDAY", 6 },
            .{ "DOW_SATURDAY", 7 },
            .{ "DOW_TYPE_WEEKDAY", 0 }, .{ "DOW_TYPE_WEEKEND", 1 },
            .{ "DOW_TYPE_WEEKEND_OFFSET", 2 }, .{ "DOW_TYPE_WEEKEND_CEASE", 3 },
            .{ "WALLTIME_FIRST", 1 }, .{ "WALLTIME_LAST", 0 }, .{ "WALLTIME_NEXT_VALID", 2 },
        };
        inline for (fields) |k| {
            try def.constant_order.append(a, k[0]);
            try def.constant_names.put(a, k[0], {});
            try def.static_props.put(a, k[0], .{ .int = k[1] });
        }

        try vm.classes.put(a, cls_name, def);

        try vm.native_fns.put(a, cls_name ++ "::__construct", calConstruct);
        try vm.native_fns.put(a, cls_name ++ "::createInstance", calCreateInstance);
        try vm.native_fns.put(a, cls_name ++ "::get", calGet);
        try vm.native_fns.put(a, cls_name ++ "::set", calSet);
        try vm.native_fns.put(a, cls_name ++ "::add", calAdd);
        try vm.native_fns.put(a, cls_name ++ "::roll", calRoll);
        try vm.native_fns.put(a, cls_name ++ "::getTime", calGetTime);
        try vm.native_fns.put(a, cls_name ++ "::setTime", calSetTime);
        try vm.native_fns.put(a, cls_name ++ "::inDaylightTime", calInDaylightTime);
        try vm.native_fns.put(a, cls_name ++ "::isSet", calIsSet);
        try vm.native_fns.put(a, cls_name ++ "::clear", calClear);
        try vm.native_fns.put(a, cls_name ++ "::setTimeZone", calSetTimeZone);
        try vm.native_fns.put(a, cls_name ++ "::getFirstDayOfWeek", calGetFirstDayOfWeek);
        try vm.native_fns.put(a, cls_name ++ "::setFirstDayOfWeek", calSetFirstDayOfWeek);
        try vm.native_fns.put(a, cls_name ++ "::isWeekend", calIsWeekend);
        try vm.native_fns.put(a, cls_name ++ "::getType", calGetType);
        try vm.native_fns.put(a, cls_name ++ "::getLocale", calGetLocale);
        try vm.native_fns.put(a, cls_name ++ "::getActualMaximum", calGetActualMaximum);
        try vm.native_fns.put(a, cls_name ++ "::getActualMinimum", calGetActualMinimum);
        try vm.native_fns.put(a, cls_name ++ "::isLenient", calIsLenient);
        try vm.native_fns.put(a, cls_name ++ "::setLenient", calSetLenient);
        try vm.native_fns.put(a, cls_name ++ "::equals", calEquals);
    }
}

fn registerMessageFormatterClass(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "MessageFormatter" };
    try def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 2 });
    try def.methods.put(a, "create", .{ .name = "create", .arity = 2, .is_static = true });
    try def.methods.put(a, "format", .{ .name = "format", .arity = 1 });
    try def.methods.put(a, "formatMessage", .{ .name = "formatMessage", .arity = 3, .is_static = true });
    try def.methods.put(a, "getPattern", .{ .name = "getPattern", .arity = 0 });
    try def.methods.put(a, "setPattern", .{ .name = "setPattern", .arity = 1 });
    try def.methods.put(a, "getLocale", .{ .name = "getLocale", .arity = 0 });
    try vm.classes.put(a, "MessageFormatter", def);
    try vm.native_fns.put(a, "MessageFormatter::__construct", mfConstruct);
    try vm.native_fns.put(a, "MessageFormatter::create", mfCreate);
    try vm.native_fns.put(a, "MessageFormatter::format", mfFormat);
    try vm.native_fns.put(a, "MessageFormatter::formatMessage", mfFormatMessage);
    try vm.native_fns.put(a, "MessageFormatter::getPattern", mfGetPattern);
    try vm.native_fns.put(a, "MessageFormatter::setPattern", mfSetPattern);
    try vm.native_fns.put(a, "MessageFormatter::getLocale", mfGetLocale);
}

fn registerDateFormatterClass(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "IntlDateFormatter" };
    try def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 3 });
    try def.methods.put(a, "create", .{ .name = "create", .arity = 3, .is_static = true });
    try def.methods.put(a, "format", .{ .name = "format", .arity = 1 });
    try def.methods.put(a, "parse", .{ .name = "parse", .arity = 1 });
    try def.methods.put(a, "getPattern", .{ .name = "getPattern", .arity = 0 });
    try def.methods.put(a, "setPattern", .{ .name = "setPattern", .arity = 1 });

    const dfs = .{
        .{ "FULL", 0 }, .{ "LONG", 1 }, .{ "MEDIUM", 2 }, .{ "SHORT", 3 }, .{ "NONE", -1 },
        .{ "RELATIVE_FULL", 128 }, .{ "RELATIVE_LONG", 129 },
        .{ "RELATIVE_MEDIUM", 130 }, .{ "RELATIVE_SHORT", 131 },
        .{ "GREGORIAN", 1 }, .{ "TRADITIONAL", 0 },
    };
    inline for (dfs) |k| {
        try def.constant_order.append(a, k[0]);
        try def.constant_names.put(a, k[0], {});
        try def.static_props.put(a, k[0], .{ .int = k[1] });
    }

    try vm.classes.put(a, "IntlDateFormatter", def);
    try vm.native_fns.put(a, "IntlDateFormatter::__construct", dfConstruct);
    try vm.native_fns.put(a, "IntlDateFormatter::create", dfCreateStatic);
    try vm.native_fns.put(a, "IntlDateFormatter::format", dfFormat);
    try vm.native_fns.put(a, "IntlDateFormatter::parse", dfParse);
    try vm.native_fns.put(a, "IntlDateFormatter::getPattern", dfGetPattern);
    try vm.native_fns.put(a, "IntlDateFormatter::setPattern", dfSetPattern);
}

fn registerNormalizerClass(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "Normalizer" };
    try def.methods.put(a, "normalize", .{ .name = "normalize", .arity = 0, .is_static = true });
    try def.methods.put(a, "isNormalized", .{ .name = "isNormalized", .arity = 0, .is_static = true });

    const ncs = .{
        .{ "NONE", 1 },
        .{ "FORM_D", 2 }, .{ "NFD", 2 },
        .{ "FORM_KD", 3 }, .{ "NFKD", 3 },
        .{ "FORM_C", 4 }, .{ "NFC", 4 }, .{ "FORM_DEFAULT", 4 },
        .{ "FORM_KC", 5 }, .{ "NFKC", 5 },
        .{ "FORM_KC_CF", 48 },
    };
    inline for (ncs) |k| {
        try def.constant_order.append(a, k[0]);
        try def.constant_names.put(a, k[0], {});
        try def.static_props.put(a, k[0], .{ .int = k[1] });
    }

    try vm.classes.put(a, "Normalizer", def);
    try vm.native_fns.put(a, "Normalizer::normalize", normalizerNormalize);
    try vm.native_fns.put(a, "Normalizer::isNormalized", normalizerIsNormalized);
}

fn registerLocaleClass(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "Locale" };
    inline for (.{
        "getDefault", "setDefault", "getPrimaryLanguage", "getRegion", "getScript",
        "canonicalize", "getDisplayName", "getDisplayLanguage", "getDisplayRegion",
        "getDisplayScript",
    }) |m| {
        try def.methods.put(a, m, .{ .name = m, .arity = 0, .is_static = true });
    }
    try vm.classes.put(a, "Locale", def);
    try vm.native_fns.put(a, "Locale::getDefault", localeGetDefault);
    try vm.native_fns.put(a, "Locale::setDefault", localeSetDefault);
    try vm.native_fns.put(a, "Locale::getPrimaryLanguage", localeGetPrimaryLanguage);
    try vm.native_fns.put(a, "Locale::getRegion", localeGetRegion);
    try vm.native_fns.put(a, "Locale::getScript", localeGetScript);
    try vm.native_fns.put(a, "Locale::canonicalize", localeCanonicalize);
    try vm.native_fns.put(a, "Locale::getDisplayName", localeGetDisplayName);
    try vm.native_fns.put(a, "Locale::getDisplayLanguage", localeGetDisplayLanguage);
    try vm.native_fns.put(a, "Locale::getDisplayRegion", localeGetDisplayRegion);
    try vm.native_fns.put(a, "Locale::getDisplayScript", localeGetDisplayScript);
}

fn registerCollatorClass(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "Collator" };
    try def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try def.methods.put(a, "create", .{ .name = "create", .arity = 1, .is_static = true });
    try def.methods.put(a, "compare", .{ .name = "compare", .arity = 2 });
    try def.methods.put(a, "setStrength", .{ .name = "setStrength", .arity = 1 });
    try def.methods.put(a, "getStrength", .{ .name = "getStrength", .arity = 0 });
    try def.methods.put(a, "getLocale", .{ .name = "getLocale", .arity = 0 });
    try def.methods.put(a, "sort", .{ .name = "sort", .arity = 1 });

    const cs = .{
        .{ "PRIMARY", 0 }, .{ "SECONDARY", 1 }, .{ "TERTIARY", 2 },
        .{ "QUATERNARY", 3 }, .{ "IDENTICAL", 15 }, .{ "DEFAULT_STRENGTH", 2 },
        .{ "DEFAULT_VALUE", -1 }, .{ "OFF", 16 }, .{ "ON", 17 }, .{ "SHIFTED", 20 },
        .{ "NON_IGNORABLE", 21 }, .{ "LOWER_FIRST", 24 }, .{ "UPPER_FIRST", 25 },
        .{ "SORT_REGULAR", 0 }, .{ "SORT_STRING", 1 }, .{ "SORT_NUMERIC", 2 },
    };
    inline for (cs) |k| {
        try def.constant_order.append(a, k[0]);
        try def.constant_names.put(a, k[0], {});
        try def.static_props.put(a, k[0], .{ .int = k[1] });
    }

    try vm.classes.put(a, "Collator", def);
    try vm.native_fns.put(a, "Collator::__construct", collConstruct);
    try vm.native_fns.put(a, "Collator::create", collCreateStatic);
    try vm.native_fns.put(a, "Collator::compare", collCompare);
    try vm.native_fns.put(a, "Collator::setStrength", collSetStrength);
    try vm.native_fns.put(a, "Collator::getStrength", collGetStrength);
    try vm.native_fns.put(a, "Collator::getLocale", collGetLocale);
    try vm.native_fns.put(a, "Collator::sort", collSort);
}

fn registerNumberFormatterClass(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "NumberFormatter" };
    try def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 2 });
    try def.methods.put(a, "create", .{ .name = "create", .arity = 2, .is_static = true });
    try def.methods.put(a, "format", .{ .name = "format", .arity = 1 });
    try def.methods.put(a, "formatCurrency", .{ .name = "formatCurrency", .arity = 2 });
    try def.methods.put(a, "parse", .{ .name = "parse", .arity = 1 });
    try def.methods.put(a, "setAttribute", .{ .name = "setAttribute", .arity = 2 });
    try def.methods.put(a, "getAttribute", .{ .name = "getAttribute", .arity = 1 });

    const nfs = .{
        .{ "PATTERN_DECIMAL", 0 }, .{ "DECIMAL", 1 }, .{ "CURRENCY", 2 },
        .{ "PERCENT", 3 }, .{ "SCIENTIFIC", 4 }, .{ "SPELLOUT", 5 },
        .{ "ORDINAL", 6 }, .{ "DURATION", 7 }, .{ "PATTERN_RULEBASED", 9 },
        .{ "IGNORE", 0 }, .{ "DEFAULT_STYLE", 1 },
        .{ "ROUND_CEILING", 0 }, .{ "ROUND_FLOOR", 1 },
        .{ "ROUND_DOWN", 2 }, .{ "ROUND_UP", 3 },
        .{ "ROUND_HALFEVEN", 4 }, .{ "ROUND_HALFDOWN", 5 }, .{ "ROUND_HALFUP", 6 },
        .{ "PAD_BEFORE_PREFIX", 0 }, .{ "PAD_AFTER_PREFIX", 1 },
        .{ "PAD_BEFORE_SUFFIX", 2 }, .{ "PAD_AFTER_SUFFIX", 3 },
        .{ "PARSE_INT_ONLY", 0 }, .{ "GROUPING_USED", 1 },
        .{ "DECIMAL_ALWAYS_SHOWN", 2 }, .{ "MAX_INTEGER_DIGITS", 3 },
        .{ "MIN_INTEGER_DIGITS", 4 }, .{ "INTEGER_DIGITS", 5 },
        .{ "MAX_FRACTION_DIGITS", 6 }, .{ "MIN_FRACTION_DIGITS", 7 },
        .{ "FRACTION_DIGITS", 8 }, .{ "MULTIPLIER", 9 },
        .{ "GROUPING_SIZE", 10 }, .{ "ROUNDING_MODE", 11 },
        .{ "ROUNDING_INCREMENT", 12 }, .{ "FORMAT_WIDTH", 13 },
        .{ "PADDING_POSITION", 14 }, .{ "SECONDARY_GROUPING_SIZE", 15 },
        .{ "SIGNIFICANT_DIGITS_USED", 16 }, .{ "MIN_SIGNIFICANT_DIGITS", 17 },
        .{ "MAX_SIGNIFICANT_DIGITS", 18 }, .{ "LENIENT_PARSE", 19 },
    };
    inline for (nfs) |k| {
        try def.constant_order.append(a, k[0]);
        try def.constant_names.put(a, k[0], {});
        try def.static_props.put(a, k[0], .{ .int = k[1] });
    }

    try vm.classes.put(a, "NumberFormatter", def);
    try vm.native_fns.put(a, "NumberFormatter::__construct", nfConstruct);
    try vm.native_fns.put(a, "NumberFormatter::create", nfCreateStatic);
    try vm.native_fns.put(a, "NumberFormatter::format", nfFormat);
    try vm.native_fns.put(a, "NumberFormatter::formatCurrency", nfFormatCurrency);
    try vm.native_fns.put(a, "NumberFormatter::parse", nfParse);
    try vm.native_fns.put(a, "NumberFormatter::setAttribute", nfSetAttribute);
    try vm.native_fns.put(a, "NumberFormatter::getAttribute", nfGetAttribute);
}

fn registerTransliteratorClass(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "Transliterator" };
    try def.methods.put(a, "create", .{ .name = "create", .arity = 1, .is_static = true });
    try def.methods.put(a, "transliterate", .{ .name = "transliterate", .arity = 1 });
    try def.constant_order.append(a, "FORWARD");
    try def.constant_names.put(a, "FORWARD", {});
    try def.static_props.put(a, "FORWARD", .{ .int = 0 });
    try def.constant_order.append(a, "REVERSE");
    try def.constant_names.put(a, "REVERSE", {});
    try def.static_props.put(a, "REVERSE", .{ .int = 1 });
    try vm.classes.put(a, "Transliterator", def);
    try vm.native_fns.put(a, "Transliterator::create", transCreateStatic);
    try vm.native_fns.put(a, "Transliterator::transliterate", transTransliterate);
}

fn registerConstants(vm: *VM, a: Allocator) !void {
    const cs = .{
        .{ "INTL_MAX_LOCALE_LEN", 80 },
        .{ "INTL_ICU_VERSION", 0 },
        .{ "U_USING_FALLBACK_WARNING", -128 },
        .{ "U_USING_DEFAULT_WARNING", -127 },
        .{ "U_SAFECLONE_ALLOCATED_WARNING", -126 },
        .{ "U_STATE_OLD_WARNING", -125 },
        .{ "U_STRING_NOT_TERMINATED_WARNING", -124 },
    };
    inline for (cs) |k| {
        try vm.php_constants.put(a, k[0], .{ .int = k[1] });
    }
}

pub fn cleanupResources(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    for (objects.items) |obj| {
        if (std.mem.eql(u8, obj.class_name, "Collator")) {
            if (getCollator(obj)) |c| zphp_ucol_close(c);
        } else if (std.mem.eql(u8, obj.class_name, "NumberFormatter")) {
            if (getNumFmt(obj)) |f| zphp_unum_close(f);
        } else if (std.mem.eql(u8, obj.class_name, "Transliterator")) {
            if (getTranslit(obj)) |t| zphp_utrans_close(t);
        } else if (std.mem.eql(u8, obj.class_name, "IntlDateFormatter")) {
            if (getDateFmt(obj)) |f| zphp_udat_close(f);
        } else if (std.mem.eql(u8, obj.class_name, "IntlCalendar") or std.mem.eql(u8, obj.class_name, "IntlGregorianCalendar")) {
            if (getCal(obj)) |c| zphp_ucal_close(c);
        } else if (std.mem.eql(u8, obj.class_name, "IntlBreakIterator") or
            std.mem.eql(u8, obj.class_name, "IntlRuleBasedBreakIterator") or
            std.mem.eql(u8, obj.class_name, "IntlCodePointBreakIterator"))
        {
            if (getBrk(obj)) |w| zphp_ubrk_close(w);
        }
    }
}
