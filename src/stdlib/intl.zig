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

const UIDNA = opaque {};
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

fn dfConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[0] != .string) return .null;
    const obj = getThis(ctx) orelse return .null;
    const date_style: i32 = if (args[1] == .int) @intCast(args[1].int) else 0;
    const time_style: i32 = if (args[2] == .int) @intCast(args[2].int) else 0;
    const tz_opt: ?[]const u8 = if (args.len > 3 and args[3] == .string and args[3].string.len > 0) args[3].string else null;
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
    const tz_opt: ?[]const u8 = if (args.len > 3 and args[3] == .string and args[3].string.len > 0) args[3].string else null;
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
    try registerConstants(vm, a);
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
        }
    }
}
