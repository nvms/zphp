// php's ext/intl/uchar/uchar.cpp: IntlChar, ICU's uchar.h API. the ICU calls
// go through the unversioned zphp_* wrappers in icu_shim.c, and the class
// constants come from php's arginfo (intlchar_constants_generated.h), valued
// by the ICU zphp links

const std = @import("std");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const callables = @import("../runtime/callables.zig");
const sic = @import("spl_iterator_classes.zig");
const intl = @import("intl.zig");

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

const UChar32 = i32;
const UBool = i8;
const UErrorCode = i32;
const U_ZERO_ERROR: UErrorCode = 0;
const U_ILLEGAL_ARGUMENT_ERROR: UErrorCode = 1;
const U_INTERNAL_PROGRAM_ERROR: UErrorCode = 5;
const UCHAR_MAX_VALUE: i64 = 0x10ffff;
// UCharNameChoice's U_UNICODE_CHAR_NAME, UPropertyNameChoice's U_LONG_PROPERTY_NAME
const U_UNICODE_CHAR_NAME: i64 = 0;
const U_LONG_PROPERTY_NAME: i64 = 1;
const U_FOLD_CASE_DEFAULT: i64 = 0;
const U_MAX_VERSION_LENGTH = 4;

const Constant = extern struct {
    name: [*:0]const u8,
    kind: c_int,
    int_value: i64,
    float_value: f64,
    string_value: ?[*:0]const u8,
};

extern fn zphp_intlchar_constant_at(i: usize) ?*const Constant;
extern fn zphp_u_hasBinaryProperty(c: UChar32, which: i32) UBool;
extern fn zphp_u_getIntPropertyValue(c: UChar32, which: i32) i32;
extern fn zphp_u_getIntPropertyMinValue(which: i32) i32;
extern fn zphp_u_getIntPropertyMaxValue(which: i32) i32;
extern fn zphp_u_getNumericValue(c: UChar32) f64;
extern fn zphp_ublock_getCode(c: UChar32) i32;
extern fn zphp_u_enumCharTypes(f: *const fn (?*anyopaque, i32, i32, i32) callconv(.c) UBool, context: ?*anyopaque) void;
extern fn zphp_u_charName(code: UChar32, choice: i32, buffer: ?[*]u8, cap: i32, err: *UErrorCode) i32;
extern fn zphp_u_charFromName(choice: i32, name: [*:0]const u8, err: *UErrorCode) UChar32;
extern fn zphp_u_enumCharNames(start: UChar32, limit: UChar32, f: *const fn (?*anyopaque, i32, i32, [*]const u8, i32) callconv(.c) UBool, context: ?*anyopaque, choice: i32, err: *UErrorCode) void;
extern fn zphp_u_getPropertyName(property: i32, choice: i32) ?[*:0]const u8;
extern fn zphp_u_getPropertyEnum(alias: [*:0]const u8) i32;
extern fn zphp_u_getPropertyValueName(property: i32, value: i32, choice: i32) ?[*:0]const u8;
extern fn zphp_u_getPropertyValueEnum(property: i32, alias: [*:0]const u8) i32;
extern fn zphp_u_foldCase(c: UChar32, options: u32) UChar32;
extern fn zphp_u_digit(c: UChar32, radix: i8) i32;
extern fn zphp_u_forDigit(digit: i32, radix: i8) UChar32;
extern fn zphp_u_charAge(c: UChar32, version: *[U_MAX_VERSION_LENGTH]u8) void;
extern fn zphp_u_getUnicodeVersion(version: *[U_MAX_VERSION_LENGTH]u8) void;
extern fn zphp_u_getFC_NFKC_Closure(c: UChar32, dest: ?[*]u16, cap: i32, err: *UErrorCode) i32;
extern fn zphp_u_charDirection(c: UChar32) i32;
extern fn zphp_u_charType(c: UChar32) i32;
extern fn zphp_u_getCombiningClass(c: UChar32) i32;
extern fn zphp_u_charDigitValue(c: UChar32) i32;
extern fn zphp_u_charMirror(c: UChar32) UChar32;
extern fn zphp_u_tolower(c: UChar32) UChar32;
extern fn zphp_u_toupper(c: UChar32) UChar32;
extern fn zphp_u_totitle(c: UChar32) UChar32;
extern fn zphp_u_getBidiPairedBracket(c: UChar32) UChar32;

const bool_fns = .{
    .{ "isUAlphabetic", "zphp_u_isUAlphabetic" },     .{ "isULowercase", "zphp_u_isULowercase" },
    .{ "isUUppercase", "zphp_u_isUUppercase" },       .{ "isUWhiteSpace", "zphp_u_isUWhiteSpace" },
    .{ "islower", "zphp_u_islower" },                 .{ "isupper", "zphp_u_isupper" },
    .{ "istitle", "zphp_u_istitle" },                 .{ "isdigit", "zphp_u_isdigit" },
    .{ "isalpha", "zphp_u_isalpha" },                 .{ "isalnum", "zphp_u_isalnum" },
    .{ "isxdigit", "zphp_u_isxdigit" },               .{ "ispunct", "zphp_u_ispunct" },
    .{ "isgraph", "zphp_u_isgraph" },                 .{ "isblank", "zphp_u_isblank" },
    .{ "isdefined", "zphp_u_isdefined" },             .{ "isspace", "zphp_u_isspace" },
    .{ "isJavaSpaceChar", "zphp_u_isJavaSpaceChar" }, .{ "isWhitespace", "zphp_u_isWhitespace" },
    .{ "iscntrl", "zphp_u_iscntrl" },                 .{ "isISOControl", "zphp_u_isISOControl" },
    .{ "isprint", "zphp_u_isprint" },                 .{ "isbase", "zphp_u_isbase" },
    .{ "isMirrored", "zphp_u_isMirrored" },           .{ "isIDStart", "zphp_u_isIDStart" },
    .{ "isIDPart", "zphp_u_isIDPart" },               .{ "isIDIgnorable", "zphp_u_isIDIgnorable" },
    .{ "isJavaIDStart", "zphp_u_isJavaIDStart" },     .{ "isJavaIDPart", "zphp_u_isJavaIDPart" },
};

const int_fns = .{
    .{ "charDirection", zphp_u_charDirection },         .{ "charType", zphp_u_charType },
    .{ "getCombiningClass", zphp_u_getCombiningClass }, .{ "charDigitValue", zphp_u_charDigitValue },
};

const char_fns = .{
    .{ "charMirror", zphp_u_charMirror },                     .{ "tolower", zphp_u_tolower },
    .{ "toupper", zphp_u_toupper },                           .{ "totitle", zphp_u_totitle },
    .{ "getBidiPairedBracket", zphp_u_getBidiPairedBracket },
};

// the methods, in php's declaration order, with how many arguments they take
const methods = [_]struct { []const u8, u8 }{
    .{ "hasBinaryProperty", 2 },      .{ "charAge", 1 },                .{ "charDigitValue", 1 },
    .{ "charDirection", 1 },          .{ "charFromName", 2 },           .{ "charMirror", 1 },
    .{ "charName", 2 },               .{ "charType", 1 },               .{ "chr", 1 },
    .{ "digit", 2 },                  .{ "enumCharNames", 4 },          .{ "enumCharTypes", 1 },
    .{ "foldCase", 2 },               .{ "forDigit", 2 },               .{ "getBidiPairedBracket", 1 },
    .{ "getBlockCode", 1 },           .{ "getCombiningClass", 1 },      .{ "getFC_NFKC_Closure", 1 },
    .{ "getIntPropertyMaxValue", 1 }, .{ "getIntPropertyMinValue", 1 }, .{ "getIntPropertyValue", 2 },
    .{ "getNumericValue", 1 },        .{ "getPropertyEnum", 1 },        .{ "getPropertyName", 2 },
    .{ "getPropertyValueEnum", 2 },   .{ "getPropertyValueName", 3 },   .{ "getUnicodeVersion", 0 },
    .{ "isalnum", 1 },                .{ "isalpha", 1 },                .{ "isbase", 1 },
    .{ "isblank", 1 },                .{ "iscntrl", 1 },                .{ "isdefined", 1 },
    .{ "isdigit", 1 },                .{ "isgraph", 1 },                .{ "isIDIgnorable", 1 },
    .{ "isIDPart", 1 },               .{ "isIDStart", 1 },              .{ "isISOControl", 1 },
    .{ "isJavaIDPart", 1 },           .{ "isJavaIDStart", 1 },          .{ "isJavaSpaceChar", 1 },
    .{ "islower", 1 },                .{ "isMirrored", 1 },             .{ "isprint", 1 },
    .{ "ispunct", 1 },                .{ "isspace", 1 },                .{ "istitle", 1 },
    .{ "isUAlphabetic", 1 },          .{ "isULowercase", 1 },           .{ "isupper", 1 },
    .{ "isUUppercase", 1 },           .{ "isUWhiteSpace", 1 },          .{ "isWhitespace", 1 },
    .{ "isxdigit", 1 },               .{ "ord", 1 },                    .{ "tolower", 1 },
    .{ "totitle", 1 },                .{ "toupper", 1 },
};

pub fn register(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "IntlChar" };
    var i: usize = 0;
    while (zphp_intlchar_constant_at(i)) |c| : (i += 1) {
        const name = std.mem.span(c.name);
        const value: Value = switch (c.kind) {
            0 => .{ .int = c.int_value },
            1 => .{ .float = c.float_value },
            else => .{ .string = Value.String.borrowed(std.mem.span(c.string_value.?)) },
        };
        try def.constants.put(a, name, value);
        try def.constant_order.append(a, name);
    }
    for (methods) |m| try def.methods.put(a, m[0], .{ .name = m[0], .arity = m[1], .is_static = true });
    try vm.classes.put(a, "IntlChar", def);

    const natives = .{
        .{ "chr", chr },                                   .{ "ord", ord },
        .{ "hasBinaryProperty", hasBinaryProperty },       .{ "getIntPropertyValue", getIntPropertyValue },
        .{ "getIntPropertyMinValue", getIntPropertyMin },  .{ "getIntPropertyMaxValue", getIntPropertyMax },
        .{ "getNumericValue", getNumericValue },           .{ "enumCharTypes", enumCharTypes },
        .{ "getBlockCode", getBlockCode },                 .{ "charName", charName },
        .{ "charFromName", charFromName },                 .{ "enumCharNames", enumCharNames },
        .{ "getPropertyName", getPropertyName },           .{ "getPropertyEnum", getPropertyEnum },
        .{ "getPropertyValueName", getPropertyValueName }, .{ "getPropertyValueEnum", getPropertyValueEnum },
        .{ "foldCase", foldCase },                         .{ "digit", digit },
        .{ "forDigit", forDigit },                         .{ "charAge", charAge },
        .{ "getUnicodeVersion", getUnicodeVersion },       .{ "getFC_NFKC_Closure", getFcNfkcClosure },
    };
    inline for (natives) |n| try vm.native_fns.put(a, "IntlChar::" ++ n[0], n[1]);
    inline for (bool_fns) |f| try vm.native_fns.put(a, "IntlChar::" ++ f[0], boolMethod(f[0], f[1]));
    inline for (int_fns) |f| try vm.native_fns.put(a, "IntlChar::" ++ f[0], intMethod(f[0], f[1]));
    inline for (char_fns) |f| try vm.native_fns.put(a, "IntlChar::" ++ f[0], charMethod(f[0], f[1]));
}

// ---------------------------------------------------------------- arguments

// intl_error_set_code with intl_error_set_custom_msg
fn setError(vm: *VM, code: UErrorCode, msg: []const u8) void {
    _ = intl.intlRecord(vm, code);
    vm.last_intl_error_msg = msg;
}

// every method starts with intl_error_reset
fn reset(vm: *VM) void {
    vm.last_intl_error_code = 0;
    vm.last_intl_error_msg = "";
    vm.last_intl_error_fn = "";
}

const Codepoint = union(enum) { string: []const u8, int: i64 };

// Z_PARAM_STR_OR_LONG: a string stays a string; anything else that is no
// array or object becomes an int, null with a deprecation
fn strOrLong(ctx: *NativeContext, label: []const u8, args: []const Value, i: usize, pname: []const u8) RuntimeError!Codepoint {
    const v = args[i];
    switch (v) {
        .string => |s| return .{ .string = s.bytes() },
        .int => |n| return .{ .int = n },
        .bool => |b| return .{ .int = @intFromBool(b) },
        .float => return .{ .int = (try sic.argLong(ctx, label, args, i, pname, 0)) orelse return error.RuntimeError },
        .null => {
            const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): Passing null to parameter #{d} (${s}) of type string|int is deprecated", .{ label, i + 1, pname });
            defer ctx.allocator.free(msg);
            try ctx.vm.raiseError(VM.E_DEPRECATED, msg);
            if (ctx.vm.pending_exception != null) return error.RuntimeError;
            return .{ .int = 0 };
        },
        else => {},
    }
    try sic.typeError(ctx, label, i + 1, pname, "string|int", v);
    return error.RuntimeError;
}

fn long(ctx: *NativeContext, label: []const u8, args: []const Value, i: usize, pname: []const u8, default: i64) RuntimeError!i64 {
    return (try sic.argLong(ctx, label, args, i, pname, default)) orelse error.RuntimeError;
}

fn string(ctx: *NativeContext, label: []const u8, args: []const Value, i: usize, pname: []const u8) RuntimeError!Value.String {
    return (try sic.argString(ctx, label, args, i, pname)) orelse error.RuntimeError;
}

// every method checks its argument count first: the name it gives is the
// one intl_error_set_custom_msg puts before a message
fn count(ctx: *NativeContext, label: []const u8, args: []const Value, min: usize, max: usize) RuntimeError!void {
    ctx.vm.last_intl_error_fn = label;
    if (!try sic.argCount(ctx, label, args.len, min, max)) return error.RuntimeError;
}

// convert_cp: one UTF-8 character, or a codepoint in range; null when not
fn convertCp(vm: *VM, cp: Codepoint) ?UChar32 {
    const n: i64 = switch (cp) {
        .int => |n| n,
        .string => |s| blk: {
            // U8_NEXT over the whole string: one well-formed sequence
            const decoded = decodeOne(s) orelse {
                setError(vm, U_ILLEGAL_ARGUMENT_ERROR, "Passing a UTF-8 character for codepoint requires a string which is exactly one UTF-8 codepoint long.");
                return null;
            };
            break :blk decoded;
        },
    };
    if (n < 0 or n > UCHAR_MAX_VALUE) {
        setError(vm, U_ILLEGAL_ARGUMENT_ERROR, "Codepoint out of range");
        return null;
    }
    return @intCast(n);
}

// U8_NEXT on the string's start: the codepoint when it is the whole string,
// a negative value (out of range) for an ill-formed sequence that is
fn decodeOne(s: []const u8) ?i64 {
    if (s.len == 0) return null;
    const len = std.unicode.utf8ByteSequenceLength(s[0]) catch return if (s.len == 1) -1 else null;
    if (len > s.len) return null;
    const cp = std.unicode.utf8Decode(s[0..len]) catch return if (len == s.len) -1 else null;
    if (len != s.len) return null;
    return cp;
}

fn codepointArg(ctx: *NativeContext, comptime label: []const u8, args: []const Value) RuntimeError!?UChar32 {
    return codepointArgNamed(ctx, label, args, "codepoint");
}

fn codepointArgNamed(ctx: *NativeContext, comptime label: []const u8, args: []const Value, pname: []const u8) RuntimeError!?UChar32 {
    try count(ctx, label, args, 1, 1);
    return convertCp(ctx.vm, try strOrLong(ctx, label, args, 0, pname));
}

fn utf8(ctx: *NativeContext, cp: UChar32) RuntimeError!NativeResult {
    var buf: [4]u8 = undefined;
    const n = encodeUnsafe(cp, &buf);
    return NativeResult.copyString(ctx.allocator, buf[0..n]);
}

// U8_APPEND_UNSAFE
fn encodeUnsafe(cp: UChar32, buf: *[4]u8) usize {
    const c: u32 = @bitCast(cp);
    if (c <= 0x7f) {
        buf[0] = @intCast(c);
        return 1;
    }
    if (c <= 0x7ff) {
        buf[0] = @intCast((c >> 6) | 0xc0);
        buf[1] = @intCast((c & 0x3f) | 0x80);
        return 2;
    }
    if (c <= 0xffff) {
        buf[0] = @intCast((c >> 12) | 0xe0);
        buf[1] = @intCast(((c >> 6) & 0x3f) | 0x80);
        buf[2] = @intCast((c & 0x3f) | 0x80);
        return 3;
    }
    buf[0] = @intCast(((c >> 18) & 0x07) | 0xf0);
    buf[1] = @intCast(((c >> 12) & 0x3f) | 0x80);
    buf[2] = @intCast(((c >> 6) & 0x3f) | 0x80);
    buf[3] = @intCast((c & 0x3f) | 0x80);
    return 4;
}

fn versionArray(ctx: *NativeContext, version: [U_MAX_VERSION_LENGTH]u8) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    for (version) |part| try arr.append(ctx.allocator, .{ .int = part });
    return NativeResult.borrowed(.{ .array = arr });
}

fn zString(ctx: *NativeContext, s: []const u8) RuntimeError![:0]u8 {
    return ctx.allocator.dupeSentinel(u8, s, 0);
}

// ---------------------------------------------------------------- methods

fn chr(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    reset(ctx.vm);
    const cp = (try codepointArg(ctx, "IntlChar::chr", args)) orelse return NativeResult.scalar(.null);
    return utf8(ctx, cp);
}

fn ord(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    reset(ctx.vm);
    const cp = (try codepointArgNamed(ctx, "IntlChar::ord", args, "character")) orelse return NativeResult.scalar(.null);
    return NativeResult.scalar(.{ .int = cp });
}

fn propertyCall(ctx: *NativeContext, comptime label: []const u8, args: []const Value) RuntimeError!?struct { cp: UChar32, prop: i32 } {
    try count(ctx, label, args, 2, 2);
    const raw = try strOrLong(ctx, label, args, 0, "codepoint");
    const prop = try long(ctx, label, args, 1, "property", 0);
    const cp = convertCp(ctx.vm, raw) orelse return null;
    return .{ .cp = cp, .prop = @truncate(prop) };
}

fn hasBinaryProperty(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    reset(ctx.vm);
    const p = (try propertyCall(ctx, "IntlChar::hasBinaryProperty", args)) orelse return NativeResult.scalar(.null);
    return NativeResult.scalar(.{ .bool = zphp_u_hasBinaryProperty(p.cp, p.prop) != 0 });
}

fn getIntPropertyValue(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    reset(ctx.vm);
    const p = (try propertyCall(ctx, "IntlChar::getIntPropertyValue", args)) orelse return NativeResult.scalar(.null);
    return NativeResult.scalar(.{ .int = zphp_u_getIntPropertyValue(p.cp, p.prop) });
}

fn getIntPropertyMin(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    reset(ctx.vm);
    try count(ctx, "IntlChar::getIntPropertyMinValue", args, 1, 1);
    const prop = try long(ctx, "IntlChar::getIntPropertyMinValue", args, 0, "property", 0);
    return NativeResult.scalar(.{ .int = zphp_u_getIntPropertyMinValue(@truncate(prop)) });
}

fn getIntPropertyMax(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    reset(ctx.vm);
    try count(ctx, "IntlChar::getIntPropertyMaxValue", args, 1, 1);
    const prop = try long(ctx, "IntlChar::getIntPropertyMaxValue", args, 0, "property", 0);
    return NativeResult.scalar(.{ .int = zphp_u_getIntPropertyMaxValue(@truncate(prop)) });
}

fn getNumericValue(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    reset(ctx.vm);
    const cp = (try codepointArg(ctx, "IntlChar::getNumericValue", args)) orelse return NativeResult.scalar(.null);
    return NativeResult.scalar(.{ .float = zphp_u_getNumericValue(cp) });
}

// the callable parameter was checked before the call (its deprecations
// included); it is resolved again quietly for the calls
fn resolveCallable(ctx: *NativeContext, v: Value) RuntimeError!callables.Callee {
    return switch (try callables.resolveCallback(ctx.vm, v, .{ .deprecations = false })) {
        .callee => |c| c,
        .failure => error.RuntimeError,
    };
}

const CallbackState = struct { ctx: *NativeContext, callee: callables.Callee, failed: bool = false };

fn callBack(state: *CallbackState, args: []const Value) bool {
    const result = callables.invoke(state.ctx.vm, state.callee, args) catch {
        state.failed = true;
        return false;
    };
    state.ctx.vm.releaseValue(result);
    if (state.ctx.vm.pending_exception != null) {
        state.failed = true;
        return false;
    }
    return true;
}

fn charTypesCallback(context: ?*anyopaque, start: i32, limit: i32, kind: i32) callconv(.c) UBool {
    const state: *CallbackState = @ptrCast(@alignCast(context.?));
    // $start is inclusive, $limit exclusive: (0, 32, 15) means 0..31
    return @intFromBool(callBack(state, &.{ .{ .int = start }, .{ .int = limit }, .{ .int = kind } }));
}

fn enumCharTypes(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    reset(ctx.vm);
    try count(ctx, "IntlChar::enumCharTypes", args, 1, 1);
    var state = CallbackState{ .ctx = ctx, .callee = try resolveCallable(ctx, args[0]) };
    zphp_u_enumCharTypes(charTypesCallback, &state);
    if (state.failed and ctx.vm.pending_exception != null) return error.RuntimeError;
    return NativeResult.scalar(.null);
}

fn getBlockCode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    reset(ctx.vm);
    const cp = (try codepointArg(ctx, "IntlChar::getBlockCode", args)) orelse return NativeResult.scalar(.null);
    return NativeResult.scalar(.{ .int = zphp_ublock_getCode(cp) });
}

fn charName(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    reset(ctx.vm);
    const label = "IntlChar::charName";
    try count(ctx, label, args, 1, 2);
    const raw = try strOrLong(ctx, label, args, 0, "codepoint");
    const choice = try long(ctx, label, args, 1, "type", U_UNICODE_CHAR_NAME);
    const cp = convertCp(ctx.vm, raw) orelse return NativeResult.scalar(.null);
    var err: UErrorCode = U_ZERO_ERROR;
    const len = zphp_u_charName(cp, @truncate(choice), null, 0, &err);
    const buf = try ctx.allocator.alloc(u8, @as(usize, @intCast(@max(len, 0))) + 1);
    defer ctx.allocator.free(buf);
    err = U_ZERO_ERROR;
    const written = zphp_u_charName(cp, @truncate(choice), buf.ptr, @intCast(buf.len), &err);
    _ = intl.intlRecord(ctx.vm, err);
    if (err > U_ZERO_ERROR) {
        ctx.vm.last_intl_error_msg = "Failure getting character name";
        return NativeResult.scalar(.null);
    }
    return NativeResult.copyString(ctx.allocator, buf[0..@intCast(@max(written, 0))]);
}

fn charFromName(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    reset(ctx.vm);
    const label = "IntlChar::charFromName";
    try count(ctx, label, args, 1, 2);
    const name = try string(ctx, label, args, 0, "name");
    defer name.release();
    const choice = try long(ctx, label, args, 1, "type", U_UNICODE_CHAR_NAME);
    const z = try zString(ctx, name.bytes());
    defer ctx.allocator.free(z);
    var err: UErrorCode = U_ZERO_ERROR;
    const cp = zphp_u_charFromName(@truncate(choice), z.ptr, &err);
    _ = intl.intlRecord(ctx.vm, err);
    if (err > U_ZERO_ERROR) return NativeResult.scalar(.null);
    return NativeResult.scalar(.{ .int = cp });
}

fn charNamesCallback(context: ?*anyopaque, code: i32, choice: i32, name: [*]const u8, length: i32) callconv(.c) UBool {
    const state: *CallbackState = @ptrCast(@alignCast(context.?));
    const s = Value.String.create(state.ctx.allocator, name[0..@intCast(length)]) catch {
        state.failed = true;
        return 0;
    };
    defer s.release();
    return @intFromBool(callBack(state, &.{ .{ .int = code }, .{ .int = choice }, .{ .string = s } }));
}

fn enumCharNames(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    reset(ctx.vm);
    const label = "IntlChar::enumCharNames";
    try count(ctx, label, args, 3, 4);
    const raw_start = try strOrLong(ctx, label, args, 0, "start");
    const raw_end = try strOrLong(ctx, label, args, 1, "end");
    var state = CallbackState{ .ctx = ctx, .callee = try resolveCallable(ctx, args[2]) };
    const choice = try long(ctx, label, args, 3, "type", U_UNICODE_CHAR_NAME);
    const start = convertCp(ctx.vm, raw_start) orelse return NativeResult.scalar(.{ .bool = false });
    const end = convertCp(ctx.vm, raw_end) orelse return NativeResult.scalar(.{ .bool = false });
    var err: UErrorCode = U_ZERO_ERROR;
    zphp_u_enumCharNames(start, end, charNamesCallback, &state, @truncate(choice), &err);
    if (state.failed and ctx.vm.pending_exception != null) return error.RuntimeError;
    _ = intl.intlRecord(ctx.vm, err);
    if (err > U_ZERO_ERROR) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn nameResult(ctx: *NativeContext, name: ?[*:0]const u8) RuntimeError!NativeResult {
    const n = name orelse {
        setError(ctx.vm, U_ILLEGAL_ARGUMENT_ERROR, "Failed to get property name");
        return NativeResult.scalar(.{ .bool = false });
    };
    return NativeResult.copyString(ctx.allocator, std.mem.span(n));
}

fn getPropertyName(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    reset(ctx.vm);
    const label = "IntlChar::getPropertyName";
    try count(ctx, label, args, 1, 2);
    const property = try long(ctx, label, args, 0, "property", 0);
    const choice = try long(ctx, label, args, 1, "type", U_LONG_PROPERTY_NAME);
    return nameResult(ctx, zphp_u_getPropertyName(@truncate(property), @truncate(choice)));
}

fn getPropertyEnum(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    reset(ctx.vm);
    const label = "IntlChar::getPropertyEnum";
    try count(ctx, label, args, 1, 1);
    const alias = try string(ctx, label, args, 0, "alias");
    defer alias.release();
    const z = try zString(ctx, alias.bytes());
    defer ctx.allocator.free(z);
    return NativeResult.scalar(.{ .int = zphp_u_getPropertyEnum(z.ptr) });
}

fn getPropertyValueName(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    reset(ctx.vm);
    const label = "IntlChar::getPropertyValueName";
    try count(ctx, label, args, 2, 3);
    const property = try long(ctx, label, args, 0, "property", 0);
    const value = try long(ctx, label, args, 1, "value", 0);
    const choice = try long(ctx, label, args, 2, "type", U_LONG_PROPERTY_NAME);
    return nameResult(ctx, zphp_u_getPropertyValueName(@truncate(property), @truncate(value), @truncate(choice)));
}

fn getPropertyValueEnum(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    reset(ctx.vm);
    const label = "IntlChar::getPropertyValueEnum";
    try count(ctx, label, args, 2, 2);
    const property = try long(ctx, label, args, 0, "property", 0);
    const name = try string(ctx, label, args, 1, "name");
    defer name.release();
    const z = try zString(ctx, name.bytes());
    defer ctx.allocator.free(z);
    return NativeResult.scalar(.{ .int = zphp_u_getPropertyValueEnum(@truncate(property), z.ptr) });
}

fn foldCase(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    reset(ctx.vm);
    const label = "IntlChar::foldCase";
    try count(ctx, label, args, 1, 2);
    const raw = try strOrLong(ctx, label, args, 0, "codepoint");
    const options = try long(ctx, label, args, 1, "options", U_FOLD_CASE_DEFAULT);
    const cp = convertCp(ctx.vm, raw) orelse return NativeResult.scalar(.null);
    const folded = zphp_u_foldCase(cp, @truncate(@as(u64, @bitCast(options))));
    if (raw == .string) return utf8(ctx, folded);
    return NativeResult.scalar(.{ .int = folded });
}

fn digit(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    reset(ctx.vm);
    const label = "IntlChar::digit";
    try count(ctx, label, args, 1, 2);
    const raw = try strOrLong(ctx, label, args, 0, "codepoint");
    const base = try long(ctx, label, args, 1, "base", 10);
    const cp = convertCp(ctx.vm, raw) orelse return NativeResult.scalar(.null);
    const d = zphp_u_digit(cp, @truncate(base));
    if (d < 0) {
        setError(ctx.vm, U_ILLEGAL_ARGUMENT_ERROR, "Invalid digit");
        return NativeResult.scalar(.{ .bool = false });
    }
    return NativeResult.scalar(.{ .int = d });
}

fn forDigit(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    reset(ctx.vm);
    const label = "IntlChar::forDigit";
    try count(ctx, label, args, 1, 2);
    const d = try long(ctx, label, args, 0, "digit", 0);
    const base = try long(ctx, label, args, 1, "base", 10);
    return NativeResult.scalar(.{ .int = zphp_u_forDigit(@truncate(d), @truncate(base)) });
}

fn charAge(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    reset(ctx.vm);
    const cp = (try codepointArg(ctx, "IntlChar::charAge", args)) orelse return NativeResult.scalar(.null);
    var version: [U_MAX_VERSION_LENGTH]u8 = undefined;
    zphp_u_charAge(cp, &version);
    return versionArray(ctx, version);
}

fn getUnicodeVersion(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    reset(ctx.vm);
    try count(ctx, "IntlChar::getUnicodeVersion", args, 0, 0);
    var version: [U_MAX_VERSION_LENGTH]u8 = undefined;
    zphp_u_getUnicodeVersion(&version);
    return versionArray(ctx, version);
}

fn getFcNfkcClosure(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    reset(ctx.vm);
    const cp = (try codepointArg(ctx, "IntlChar::getFC_NFKC_Closure", args)) orelse return NativeResult.scalar(.null);
    var err: UErrorCode = U_ZERO_ERROR;
    const len = zphp_u_getFC_NFKC_Closure(cp, null, 0, &err);
    if (len <= 0) return NativeResult.literal("");
    const units = try ctx.allocator.alloc(u16, @intCast(len + 1));
    defer ctx.allocator.free(units);
    err = U_ZERO_ERROR;
    const written = zphp_u_getFC_NFKC_Closure(cp, units.ptr, len, &err);
    _ = intl.intlRecord(ctx.vm, err);
    if (err > U_ZERO_ERROR) {
        ctx.vm.last_intl_error_msg = "Failed getting closure";
        return NativeResult.scalar(.{ .bool = false });
    }
    const text = std.unicode.utf16LeToUtf8Alloc(ctx.allocator, units[0..@intCast(written)]) catch {
        setError(ctx.vm, 10, "Failed converting output to UTF8");
        return NativeResult.scalar(.{ .bool = false });
    };
    defer ctx.allocator.free(text);
    return NativeResult.copyString(ctx.allocator, text);
}

fn boolMethod(comptime name: []const u8, comptime symbol: []const u8) vm_mod.NativeFn {
    const f = @extern(*const fn (UChar32) callconv(.c) UBool, .{ .name = symbol });
    return struct {
        fn call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
            reset(ctx.vm);
            const cp = (try codepointArg(ctx, "IntlChar::" ++ name, args)) orelse return NativeResult.scalar(.null);
            return NativeResult.scalar(.{ .bool = f(cp) != 0 });
        }
    }.call;
}

fn intMethod(comptime name: []const u8, comptime f: fn (UChar32) callconv(.c) i32) vm_mod.NativeFn {
    return struct {
        fn call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
            reset(ctx.vm);
            const cp = (try codepointArg(ctx, "IntlChar::" ++ name, args)) orelse return NativeResult.scalar(.null);
            return NativeResult.scalar(.{ .int = f(cp) });
        }
    }.call;
}

// a codepoint given as a UTF-8 character comes back as one
fn charMethod(comptime name: []const u8, comptime f: fn (UChar32) callconv(.c) UChar32) vm_mod.NativeFn {
    return struct {
        fn call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
            reset(ctx.vm);
            const label = "IntlChar::" ++ name;
            try count(ctx, label, args, 1, 1);
            const raw = try strOrLong(ctx, label, args, 0, "codepoint");
            const cp = convertCp(ctx.vm, raw) orelse return NativeResult.scalar(.null);
            const mapped = f(cp);
            if (raw == .string) return utf8(ctx, mapped);
            return NativeResult.scalar(.{ .int = mapped });
        }
    }.call;
}
