const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const NativeHandle = @import("../runtime/value.zig").NativeHandle;
const vm_mod = @import("../runtime/vm.zig");
const object_properties = @import("../runtime/object_properties.zig");
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

// arbitrary-precision integers via libgmp. each GMP php-object wraps a heap
// mpz_t pointer (zphp_mpz*) allocated by the C shim. PHP exposes both a
// GMP class (returned by gmp_init) and dozens of procedural functions

const ZphpMpz = opaque {};

extern fn zphp_mpz_create() ?*ZphpMpz;
extern fn zphp_mpz_destroy(p: ?*ZphpMpz) void;
extern fn zphp_mpz_set(r: *ZphpMpz, a: *const ZphpMpz) void;
extern fn zphp_mpz_set_str(p: *ZphpMpz, s: [*:0]const u8, base: c_int) c_int;
extern fn zphp_mpz_set_si(p: *ZphpMpz, v: i64) i64;
extern fn zphp_mpz_get_si(p: *const ZphpMpz) i64;
extern fn zphp_mpz_get_str(base: c_int, p: *const ZphpMpz) [*c]u8;
extern fn zphp_gmp_free(p: *anyopaque) void;
extern fn zphp_mpz_add(r: *ZphpMpz, a: *const ZphpMpz, b: *const ZphpMpz) void;
extern fn zphp_mpz_sub(r: *ZphpMpz, a: *const ZphpMpz, b: *const ZphpMpz) void;
extern fn zphp_mpz_mul(r: *ZphpMpz, a: *const ZphpMpz, b: *const ZphpMpz) void;
extern fn zphp_mpz_tdiv_q(r: *ZphpMpz, a: *const ZphpMpz, b: *const ZphpMpz) void;
extern fn zphp_mpz_tdiv_r(r: *ZphpMpz, a: *const ZphpMpz, b: *const ZphpMpz) void;
extern fn zphp_mpz_mod(r: *ZphpMpz, a: *const ZphpMpz, b: *const ZphpMpz) void;
extern fn zphp_mpz_pow_ui(r: *ZphpMpz, a: *const ZphpMpz, e: c_ulong) void;
extern fn zphp_mpz_powm(r: *ZphpMpz, a: *const ZphpMpz, e: *const ZphpMpz, m: *const ZphpMpz) void;
extern fn zphp_mpz_sqrt(r: *ZphpMpz, a: *const ZphpMpz) void;
extern fn zphp_mpz_root(r: *ZphpMpz, a: *const ZphpMpz, n: c_ulong) void;
extern fn zphp_mpz_neg(r: *ZphpMpz, a: *const ZphpMpz) void;
extern fn zphp_mpz_abs(r: *ZphpMpz, a: *const ZphpMpz) void;
extern fn zphp_mpz_cmp(a: *const ZphpMpz, b: *const ZphpMpz) c_int;
extern fn zphp_mpz_sgn(a: *const ZphpMpz) c_int;
extern fn zphp_mpz_and(r: *ZphpMpz, a: *const ZphpMpz, b: *const ZphpMpz) void;
extern fn zphp_mpz_ior(r: *ZphpMpz, a: *const ZphpMpz, b: *const ZphpMpz) void;
extern fn zphp_mpz_xor(r: *ZphpMpz, a: *const ZphpMpz, b: *const ZphpMpz) void;
extern fn zphp_mpz_com(r: *ZphpMpz, a: *const ZphpMpz) void;
extern fn zphp_mpz_gcd(r: *ZphpMpz, a: *const ZphpMpz, b: *const ZphpMpz) void;
extern fn zphp_mpz_lcm(r: *ZphpMpz, a: *const ZphpMpz, b: *const ZphpMpz) void;
extern fn zphp_mpz_invert(r: *ZphpMpz, a: *const ZphpMpz, m: *const ZphpMpz) c_int;
extern fn zphp_mpz_mul_2exp(r: *ZphpMpz, a: *const ZphpMpz, e: c_ulong) void;
extern fn zphp_mpz_tdiv_q_2exp(r: *ZphpMpz, a: *const ZphpMpz, e: c_ulong) void;
extern fn zphp_mpz_fdiv_q_2exp(r: *ZphpMpz, a: *const ZphpMpz, e: c_ulong) void;
extern fn zphp_mpz_get_d(a: *const ZphpMpz) f64;
extern fn zphp_mpz_fits_i64(a: *const ZphpMpz) c_int;
extern fn zphp_mpz_probab_prime_p(a: *const ZphpMpz, reps: c_int) c_int;
extern fn zphp_mpz_nextprime(r: *ZphpMpz, a: *const ZphpMpz) void;
extern fn zphp_mpz_sizeinbase(a: *const ZphpMpz, base: c_int) usize;
extern fn zphp_mpz_testbit(a: *const ZphpMpz, bit: c_ulong) c_int;
extern fn zphp_mpz_setbit(a: *ZphpMpz, bit: c_ulong) void;
extern fn zphp_mpz_clrbit(a: *ZphpMpz, bit: c_ulong) void;
extern fn zphp_mpz_popcount(a: *const ZphpMpz) c_ulong;
extern fn zphp_mpz_scan0(a: *const ZphpMpz, start: c_ulong) c_ulong;
extern fn zphp_mpz_scan1(a: *const ZphpMpz, start: c_ulong) c_ulong;
extern fn zphp_mpz_legendre(a: *const ZphpMpz, p: *const ZphpMpz) c_int;
extern fn zphp_mpz_jacobi(a: *const ZphpMpz, b: *const ZphpMpz) c_int;
extern fn zphp_mpz_perfect_square_p(a: *const ZphpMpz) c_int;
extern fn zphp_mpz_fits_ulong_p(a: *const ZphpMpz) c_int;
extern fn zphp_mpz_get_ui64(a: *const ZphpMpz) u64;
extern fn zphp_mpz_odd_p(a: *const ZphpMpz) c_int;
extern fn zphp_mpz_fac_ui(r: *ZphpMpz, n: c_ulong) void;
extern fn zphp_mpz_bin_ui(r: *ZphpMpz, n: *const ZphpMpz, k: c_ulong) void;
extern fn zphp_mpz_powm_sec(r: *ZphpMpz, a: *const ZphpMpz, e: *const ZphpMpz, m: *const ZphpMpz) void;
extern fn zphp_mpz_prevprime(r: *ZphpMpz, a: *const ZphpMpz) c_int;

const ulong_max: u64 = std.math.maxInt(c_ulong);

// GMP_Z_PARAM_INTO_MPZ_PTR: a GMP, an int, or an integer string (no NUL in
// it since php 8.6), else php's TypeError or ValueError for the argument
fn mpzArg(ctx: *NativeContext, func: []const u8, args: []const Value, i: usize, pname: []const u8) RuntimeError!*ZphpMpz {
    const v: Value = if (i < args.len) args[i] else .null;
    const p = zphp_mpz_create() orelse return error.OutOfMemory;
    errdefer zphp_mpz_destroy(p);
    switch (v) {
        .int => |n| _ = zphp_mpz_set_si(p, n),
        .float => |f| _ = zphp_mpz_set_si(p, try weakFloat(ctx, f)),
        .bool => |b| _ = zphp_mpz_set_si(p, @intFromBool(b)),
        .string => |s| try convertString(ctx, p, s.bytes(), 0, func, i + 1, pname),
        .object => |o| {
            const src = if (std.mem.eql(u8, o.class_name, "GMP")) getMpz(o) else null;
            zphp_mpz_set(p, src orelse return throwOperand(ctx, "TypeError", "{s}(): Argument #{d} (${s}) must be of type GMP|string|int, {s} given", .{ func, i + 1, pname, o.class_name }));
        },
        else => return throwOperand(ctx, "TypeError", "{s}(): Argument #{d} (${s}) must be of type GMP|string|int, {s} given", .{ func, i + 1, pname, v.typeName() }),
    }
    return p;
}

// convert_zstr_to_gmp: leading whitespace is skipped, base 0 detects the
// 0x, 0o, 0b and 0 prefixes, and a NUL byte or anything gmp can't read is a
// ValueError (worded for the argument, or for an operator's operand when
// func is empty)
fn convertString(ctx: *NativeContext, p: *ZphpMpz, bytes: []const u8, base_in: i64, func: []const u8, arg: usize, pname: []const u8) RuntimeError!void {
    var ok = std.mem.indexOfScalar(u8, bytes, 0) == null;
    if (ok) {
        var str = bytes;
        while (str.len > 0 and std.ascii.isWhitespace(str[0])) str = str[1..];
        var base = base_in;
        if (str.len >= 2 and str[0] == '0') {
            const c = str[1];
            if ((base == 0 or base == 16) and (c == 'x' or c == 'X')) {
                base = 16;
                str = str[2..];
            } else if ((base == 0 or base == 8) and (c == 'o' or c == 'O')) {
                base = 8;
                str = str[2..];
            } else if ((base == 0 or base == 2) and (c == 'b' or c == 'B')) {
                base = 2;
                str = str[2..];
            }
        }
        const z = try dupZ(ctx, str);
        defer ctx.allocator.free(z);
        ok = zphp_mpz_set_str(p, z.ptr, @intCast(base)) == 0;
    }
    if (ok) return;
    if (func.len == 0) return throwOperand(ctx, "ValueError", "Number is not an integer string", .{});
    return throwOperand(ctx, "ValueError", "{s}(): Argument #{d} (${s}) is not an integer string", .{ func, arg, pname });
}

// gmp_verify_base
fn verifyBase(ctx: *NativeContext, func: []const u8, base: i64) RuntimeError!void {
    if (base != 0 and (base < 2 or base > 62)) return throwOperand(ctx, "ValueError", "{s}(): Argument #2 ($base) must be 0 or between 2 and 62", .{func});
}

// gmp_initialize_number: an int, or a string in the given base
fn initializeNumber(ctx: *NativeContext, p: *ZphpMpz, v: Value, base: i64, func: []const u8) RuntimeError!void {
    switch (v) {
        .string => |str| try convertString(ctx, p, str.bytes(), base, func, 1, "num"),
        else => _ = zphp_mpz_set_si(p, Value.toInt(v)),
    }
}

fn longArg(args: []const Value, i: usize) i64 {
    return if (i < args.len) Value.toInt(args[i]) else 0;
}

// ---------------- helpers ----------------

// a null-terminated copy for gmp; the caller frees it
fn dupZ(ctx: *NativeContext, s: []const u8) ![:0]u8 {
    return ctx.allocator.dupeSentinel(u8, s, 0);
}

fn cstrLen(p: [*c]const u8) usize {
    return std.mem.len(p);
}

fn getMpz(obj: *const PhpObject) ?*ZphpMpz {
    return obj.native.get(ZphpMpz, .gmp);
}

fn setMpz(obj: *PhpObject, p: ?*ZphpMpz) void {
    obj.native = .{ .kind = .gmp, .ptr = NativeHandle.addr(p) };
}

fn createGmpObj(ctx: *NativeContext) !*PhpObject {
    const obj = try ctx.createObject("GMP");
    const p = zphp_mpz_create() orelse return error.OutOfMemory;
    setMpz(obj, p);
    return obj;
}

// ---------------- top-level functions ----------------

fn gmpInit(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const base: i64 = if (args.len > 1) Value.toInt(args[1]) else 0;
    try verifyBase(ctx, "gmp_init", base);
    // the object exists before the number converts (INIT_GMP_RETVAL), so a
    // failed conversion frees its handle as php's does
    const obj = try createGmpObj(ctx);
    try initializeNumber(ctx, getMpz(obj).?, if (args.len > 0) args[0] else Value{ .int = 0 }, base, "gmp_init");
    return NativeResult.borrowed(.{ .object = obj });
}

fn gmpStrval(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1) return NativeResult.scalar(.null);
    var base: c_int = 10;
    if (args.len > 1 and args[1] == .int) base = @intCast(args[1].int);
    const src = try mpzArg(ctx, "gmp_strval", args, 0, "num");
    defer zphp_mpz_destroy(src);
    const cstr = zphp_mpz_get_str(base, src);
    if (cstr == null) return try NativeResult.copyString(ctx.allocator, "");
    const slice = cstr[0..cstrLen(cstr)];
    const owned = try Value.String.create(ctx.allocator, slice);
    zphp_gmp_free(cstr);
    return NativeResult.takeString(owned);
}

fn gmpIntval(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1) return NativeResult.scalar(.{ .int = 0 });
    const src = try mpzArg(ctx, "gmp_intval", args, 0, "num");
    defer zphp_mpz_destroy(src);
    return NativeResult.scalar(.{ .int = zphp_mpz_get_si(src) });
}

const Binop = *const fn (r: *ZphpMpz, a: *const ZphpMpz, b: *const ZphpMpz) callconv(.c) void;
const Unop = *const fn (r: *ZphpMpz, a: *const ZphpMpz) callconv(.c) void;

fn binOpCall(ctx: *NativeContext, args: []const Value, op: Binop, func: []const u8) RuntimeError!NativeResult {
    const a = try mpzArg(ctx, func, args, 0, "num1");
    defer zphp_mpz_destroy(a);
    const b = try mpzArg(ctx, func, args, 1, "num2");
    defer zphp_mpz_destroy(b);
    const obj = try createGmpObj(ctx);
    op(getMpz(obj).?, a, b);
    return NativeResult.borrowed(.{ .object = obj });
}

fn unOpCall(ctx: *NativeContext, args: []const Value, op: Unop, func: []const u8) RuntimeError!NativeResult {
    const a = try mpzArg(ctx, func, args, 0, "num");
    defer zphp_mpz_destroy(a);
    const obj = try createGmpObj(ctx);
    op(getMpz(obj).?, a);
    return NativeResult.borrowed(.{ .object = obj });
}

fn gmpBinomial(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const n = try mpzArg(ctx, "gmp_binomial", args, 0, "n");
    defer zphp_mpz_destroy(n);
    const k = longArg(args, 1);
    if (k < 0 or @as(u64, @intCast(@max(k, 0))) > ulong_max) return throwOperand(ctx, "ValueError", "gmp_binomial(): Argument #2 ($k) must be between 0 and {d}", .{ulong_max});
    const obj = try createGmpObj(ctx);
    zphp_mpz_bin_ui(getMpz(obj).?, n, @intCast(k));
    return NativeResult.borrowed(.{ .object = obj });
}

fn gmpFact(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const a = try mpzArg(ctx, "gmp_fact", args, 0, "num");
    defer zphp_mpz_destroy(a);
    if (zphp_mpz_fits_ulong_p(a) == 0) return throwOperand(ctx, "ValueError", "gmp_fact(): Argument #1 ($num) must be between 0 and {d}", .{ulong_max});
    const obj = try createGmpObj(ctx);
    zphp_mpz_fac_ui(getMpz(obj).?, @intCast(zphp_mpz_get_ui64(a)));
    return NativeResult.borrowed(.{ .object = obj });
}

// gmp_prevprime (php 8.6): the largest prime below the number; the optional
// second argument learns whether it is surely prime
fn gmpPrevprime(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const a = try mpzArg(ctx, "gmp_prevprime", args, 0, "num");
    defer zphp_mpz_destroy(a);
    const two = zphp_mpz_create() orelse return error.OutOfMemory;
    defer zphp_mpz_destroy(two);
    _ = zphp_mpz_set_si(two, 2);
    if (zphp_mpz_cmp(a, two) <= 0) return throwOperand(ctx, "ValueError", "gmp_prevprime(): Argument #1 ($num) must be greater than 2", .{});
    // the output goes back before the result object is made
    const tmp = zphp_mpz_create() orelse return error.OutOfMemory;
    defer zphp_mpz_destroy(tmp);
    const res = zphp_mpz_prevprime(tmp, a);
    if (args.len > 1) ctx.setCallerVar(1, args.len, .{ .bool = res == 2 });
    const obj = try createGmpObj(ctx);
    zphp_mpz_set(getMpz(obj).?, tmp);
    return NativeResult.borrowed(.{ .object = obj });
}

// gmp_powm_sec (php 8.6): powm with a side-channel quiet algorithm, which
// needs a positive exponent and an odd modulus
fn gmpPowmSec(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const base = try mpzArg(ctx, "gmp_powm_sec", args, 0, "num");
    defer zphp_mpz_destroy(base);
    const e = try mpzArg(ctx, "gmp_powm_sec", args, 1, "exponent");
    defer zphp_mpz_destroy(e);
    const m = try mpzArg(ctx, "gmp_powm_sec", args, 2, "modulus");
    defer zphp_mpz_destroy(m);
    if (zphp_mpz_sgn(e) <= 0) return throwOperand(ctx, "ValueError", "gmp_powm_sec(): Argument #2 ($exponent) must be greater than 0", .{});
    if (zphp_mpz_odd_p(m) == 0) {
        if (zphp_mpz_sgn(m) == 0) return throwOperand(ctx, "DivisionByZeroError", "gmp_powm_sec(): Argument #3 ($modulus) Modulo by zero", .{});
        return throwOperand(ctx, "ValueError", "gmp_powm_sec(): Argument #3 ($modulus) must be odd", .{});
    }
    const obj = try createGmpObj(ctx);
    zphp_mpz_powm_sec(getMpz(obj).?, base, e, m);
    return NativeResult.borrowed(.{ .object = obj });
}

fn gmpAdd(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return binOpCall(ctx, args, zphp_mpz_add, "gmp_add");
}
fn gmpSub(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return binOpCall(ctx, args, zphp_mpz_sub, "gmp_sub");
}
fn gmpMul(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return binOpCall(ctx, args, zphp_mpz_mul, "gmp_mul");
}
fn gmpAnd(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return binOpCall(ctx, args, zphp_mpz_and, "gmp_and");
}
fn gmpOr(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return binOpCall(ctx, args, zphp_mpz_ior, "gmp_or");
}
fn gmpXor(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return binOpCall(ctx, args, zphp_mpz_xor, "gmp_xor");
}
fn gmpGcd(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return binOpCall(ctx, args, zphp_mpz_gcd, "gmp_gcd");
}
fn gmpLcm(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return binOpCall(ctx, args, zphp_mpz_lcm, "gmp_lcm");
}
fn gmpDivQ(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return binOpCall(ctx, args, zphp_mpz_tdiv_q, "gmp_div_q");
}
fn gmpDivR(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return binOpCall(ctx, args, zphp_mpz_tdiv_r, "gmp_div_r");
}
fn gmpDiv(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return binOpCall(ctx, args, zphp_mpz_tdiv_q, "gmp_div");
}
fn gmpMod(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return binOpCall(ctx, args, zphp_mpz_mod, "gmp_mod");
}

fn gmpNeg(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return unOpCall(ctx, args, zphp_mpz_neg, "gmp_neg");
}
fn gmpAbs(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return unOpCall(ctx, args, zphp_mpz_abs, "gmp_abs");
}
fn gmpCom(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return unOpCall(ctx, args, zphp_mpz_com, "gmp_com");
}
fn gmpSqrt(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return unOpCall(ctx, args, zphp_mpz_sqrt, "gmp_sqrt");
}
fn gmpNextprime(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return unOpCall(ctx, args, zphp_mpz_nextprime, "gmp_nextprime");
}

fn gmpCmp(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.scalar(.null);
    const a = try mpzArg(ctx, "gmp_cmp", args, 0, "num1");
    defer zphp_mpz_destroy(a);
    const b = try mpzArg(ctx, "gmp_cmp", args, 1, "num2");
    defer zphp_mpz_destroy(b);
    const r = zphp_mpz_cmp(a, b);
    return NativeResult.scalar(.{ .int = if (r > 0) 1 else if (r < 0) -1 else 0 });
}

fn gmpSign(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1) return NativeResult.scalar(.{ .int = 0 });
    const a = try mpzArg(ctx, "gmp_sign", args, 0, "num");
    defer zphp_mpz_destroy(a);
    const r = zphp_mpz_sgn(a);
    return NativeResult.scalar(.{ .int = if (r > 0) 1 else if (r < 0) -1 else 0 });
}

fn gmpPow(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const a = try mpzArg(ctx, "gmp_pow", args, 0, "num");
    defer zphp_mpz_destroy(a);
    const exp = longArg(args, 1);
    if (exp < 0 or @as(u64, @intCast(@max(exp, 0))) > ulong_max) return throwOperand(ctx, "ValueError", "gmp_pow(): Argument #2 ($exponent) must be between 0 and {d}", .{ulong_max});
    const obj = try createGmpObj(ctx);
    zphp_mpz_pow_ui(getMpz(obj).?, a, @intCast(exp));
    return NativeResult.borrowed(.{ .object = obj });
}

fn gmpPowm(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const a = try mpzArg(ctx, "gmp_powm", args, 0, "num");
    defer zphp_mpz_destroy(a);
    const e = try mpzArg(ctx, "gmp_powm", args, 1, "exponent");
    defer zphp_mpz_destroy(e);
    const m = try mpzArg(ctx, "gmp_powm", args, 2, "modulus");
    defer zphp_mpz_destroy(m);
    if (zphp_mpz_sgn(e) < 0) return throwOperand(ctx, "ValueError", "gmp_powm(): Argument #2 ($exponent) must be greater than or equal to 0", .{});
    if (zphp_mpz_sgn(m) == 0) return throwOperand(ctx, "DivisionByZeroError", "gmp_powm(): Argument #3 ($modulus) Modulo by zero", .{});
    const obj = try createGmpObj(ctx);
    zphp_mpz_powm(getMpz(obj).?, a, e, m);
    return NativeResult.borrowed(.{ .object = obj });
}

fn gmpInvert(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.scalar(.{ .bool = false });
    const a = try mpzArg(ctx, "gmp_invert", args, 0, "num1");
    defer zphp_mpz_destroy(a);
    const m = try mpzArg(ctx, "gmp_invert", args, 1, "num2");
    defer zphp_mpz_destroy(m);
    const obj = try createGmpObj(ctx);
    if (zphp_mpz_invert(getMpz(obj).?, a, m) == 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.borrowed(.{ .object = obj });
}

fn gmpProbPrime(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1) return NativeResult.scalar(.{ .int = 0 });
    const reps: c_int = if (args.len > 1 and args[1] == .int) @intCast(args[1].int) else 10;
    const a = try mpzArg(ctx, "gmp_prob_prime", args, 0, "num");
    defer zphp_mpz_destroy(a);
    return NativeResult.scalar(.{ .int = @intCast(zphp_mpz_probab_prime_p(a, reps)) });
}

fn gmpSetbit(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .object or args[1] != .int) return NativeResult.scalar(.null);
    const obj = args[0].object;
    if (!std.mem.eql(u8, obj.class_name, "GMP")) return NativeResult.scalar(.null);
    const p = getMpz(obj) orelse return NativeResult.scalar(.null);
    const bit: c_ulong = @intCast(args[1].int);
    const set_val: bool = if (args.len > 2 and args[2] == .bool) args[2].bool else true;
    if (set_val) zphp_mpz_setbit(p, bit) else zphp_mpz_clrbit(p, bit);
    return NativeResult.scalar(.null);
}

fn gmpClrbit(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .object or args[1] != .int) return NativeResult.scalar(.null);
    const obj = args[0].object;
    if (!std.mem.eql(u8, obj.class_name, "GMP")) return NativeResult.scalar(.null);
    const p = getMpz(obj) orelse return NativeResult.scalar(.null);
    zphp_mpz_clrbit(p, @intCast(args[1].int));
    return NativeResult.scalar(.null);
}

fn gmpTestbit(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .int) return NativeResult.scalar(.{ .bool = false });
    const a = try mpzArg(ctx, "gmp_testbit", args, 0, "num");
    defer zphp_mpz_destroy(a);
    return NativeResult.scalar(.{ .bool = zphp_mpz_testbit(a, @intCast(args[1].int)) != 0 });
}

fn gmpPopcount(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1) return NativeResult.scalar(.{ .int = 0 });
    const a = try mpzArg(ctx, "gmp_popcount", args, 0, "num");
    defer zphp_mpz_destroy(a);
    return NativeResult.scalar(.{ .int = @intCast(zphp_mpz_popcount(a)) });
}

fn gmpScan0(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .int) return NativeResult.scalar(.{ .int = -1 });
    const a = try mpzArg(ctx, "gmp_scan0", args, 0, "num1");
    defer zphp_mpz_destroy(a);
    const r = zphp_mpz_scan0(a, @intCast(@max(args[1].int, 0)));
    // GMP returns ULONG_MAX when no zero bit is found; map to -1 like PHP
    if (r == std.math.maxInt(c_ulong)) return NativeResult.scalar(.{ .int = -1 });
    return NativeResult.scalar(.{ .int = @intCast(r) });
}

fn gmpScan1(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .int) return NativeResult.scalar(.{ .int = -1 });
    const a = try mpzArg(ctx, "gmp_scan1", args, 0, "num1");
    defer zphp_mpz_destroy(a);
    const r = zphp_mpz_scan1(a, @intCast(@max(args[1].int, 0)));
    if (r == std.math.maxInt(c_ulong)) return NativeResult.scalar(.{ .int = -1 });
    return NativeResult.scalar(.{ .int = @intCast(r) });
}

fn gmpHamdist(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.scalar(.{ .int = 0 });
    const a = try mpzArg(ctx, "gmp_hamdist", args, 0, "num1");
    defer zphp_mpz_destroy(a);
    const b = try mpzArg(ctx, "gmp_hamdist", args, 1, "num2");
    defer zphp_mpz_destroy(b);
    const xored = zphp_mpz_create() orelse return error.OutOfMemory;
    defer zphp_mpz_destroy(xored);
    zphp_mpz_xor(xored, a, b);
    return NativeResult.scalar(.{ .int = @intCast(zphp_mpz_popcount(xored)) });
}

fn gmpLegendre(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.scalar(.{ .int = 0 });
    const a = try mpzArg(ctx, "gmp_legendre", args, 0, "num1");
    defer zphp_mpz_destroy(a);
    const p = try mpzArg(ctx, "gmp_legendre", args, 1, "num2");
    defer zphp_mpz_destroy(p);
    return NativeResult.scalar(.{ .int = @intCast(zphp_mpz_legendre(a, p)) });
}

fn gmpJacobi(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.scalar(.{ .int = 0 });
    const a = try mpzArg(ctx, "gmp_jacobi", args, 0, "num1");
    defer zphp_mpz_destroy(a);
    const b = try mpzArg(ctx, "gmp_jacobi", args, 1, "num2");
    defer zphp_mpz_destroy(b);
    return NativeResult.scalar(.{ .int = @intCast(zphp_mpz_jacobi(a, b)) });
}

fn gmpPerfectSquare(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1) return NativeResult.scalar(.{ .bool = false });
    const a = try mpzArg(ctx, "gmp_perfect_square", args, 0, "num");
    defer zphp_mpz_destroy(a);
    return NativeResult.scalar(.{ .bool = zphp_mpz_perfect_square_p(a) != 0 });
}

fn gmpRoot(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const a = try mpzArg(ctx, "gmp_root", args, 0, "num");
    defer zphp_mpz_destroy(a);
    const nth = longArg(args, 1);
    if (nth <= 0 or @as(u64, @intCast(nth)) > ulong_max) return throwOperand(ctx, "ValueError", "gmp_root(): Argument #2 ($nth) must be between 1 and {d}", .{ulong_max});
    if (@rem(nth, 2) == 0 and zphp_mpz_sgn(a) < 0) return throwOperand(ctx, "ValueError", "gmp_root(): Argument #2 ($nth) must be odd if argument #1 ($num) is negative", .{});
    const obj = try createGmpObj(ctx);
    zphp_mpz_root(getMpz(obj).?, a, @intCast(nth));
    return NativeResult.borrowed(.{ .object = obj });
}

// ---------------- registration ----------------

pub const entries = .{
    .{ "gmp_init", gmpInit },
    .{ "gmp_strval", gmpStrval },
    .{ "gmp_intval", gmpIntval },
    .{ "gmp_add", gmpAdd },
    .{ "gmp_sub", gmpSub },
    .{ "gmp_mul", gmpMul },
    .{ "gmp_div_q", gmpDivQ },
    .{ "gmp_div_r", gmpDivR },
    .{ "gmp_div", gmpDiv },
    .{ "gmp_mod", gmpMod },
    .{ "gmp_pow", gmpPow },
    .{ "gmp_powm", gmpPowm },
    .{ "gmp_sqrt", gmpSqrt },
    .{ "gmp_root", gmpRoot },
    .{ "gmp_neg", gmpNeg },
    .{ "gmp_abs", gmpAbs },
    .{ "gmp_cmp", gmpCmp },
    .{ "gmp_sign", gmpSign },
    .{ "gmp_and", gmpAnd },
    .{ "gmp_or", gmpOr },
    .{ "gmp_xor", gmpXor },
    .{ "gmp_com", gmpCom },
    .{ "gmp_gcd", gmpGcd },
    .{ "gmp_lcm", gmpLcm },
    .{ "gmp_fact", gmpFact },
    .{ "gmp_binomial", gmpBinomial },
    .{ "gmp_invert", gmpInvert },
    .{ "gmp_prob_prime", gmpProbPrime },
    .{ "gmp_nextprime", gmpNextprime },
    .{ "gmp_prevprime", gmpPrevprime },
    .{ "gmp_powm_sec", gmpPowmSec },
    .{ "gmp_setbit", gmpSetbit },
    .{ "gmp_clrbit", gmpClrbit },
    .{ "gmp_testbit", gmpTestbit },
    .{ "gmp_popcount", gmpPopcount },
    .{ "gmp_scan0", gmpScan0 },
    .{ "gmp_scan1", gmpScan1 },
    .{ "gmp_hamdist", gmpHamdist },
    .{ "gmp_legendre", gmpLegendre },
    .{ "gmp_jacobi", gmpJacobi },
    .{ "gmp_perfect_square", gmpPerfectSquare },
};

fn cleanupGmp(obj: *PhpObject) bool {
    if (getMpz(obj)) |p| zphp_mpz_destroy(p);
    obj.native.ptr = 0;
    return true;
}

fn cloneGmp(_: *VM, src: *PhpObject, copy: *PhpObject) bool {
    const p = zphp_mpz_create() orelse return false;
    if (getMpz(src)) |orig| zphp_mpz_set(p, orig);
    setMpz(copy, p);
    return true;
}

pub fn register(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "GMP", .is_final = true, .native_cleanup = cleanupGmp, .native_clone = cloneGmp, .native_properties = gmpProperties, .native_binop = gmpBinop, .native_cast = gmpCast };
    // GMP is mostly a value-holding class; user-facing methods are
    // PHP's procedural ones. providing __toString lets `(string)$gmp` work
    try def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 0 });
    try def.methods.put(a, "__toString", .{ .name = "__toString", .arity = 0 });
    try def.methods.put(a, "__serialize", .{ .name = "__serialize", .arity = 0 });
    try def.methods.put(a, "__unserialize", .{ .name = "__unserialize", .arity = 1 });
    try vm.classes.put(a, "GMP", def);
    try vm.native_fns.put(a, "GMP::__construct", gmpConstruct);
    try vm.native_fns.put(a, "GMP::__toString", gmpToString);
    try vm.native_fns.put(a, "GMP::__serialize", gmpSerialize);
    try vm.native_fns.put(a, "GMP::__unserialize", gmpUnserialize);
    try vm.php_constants.put(a, "GMP_ROUND_ZERO", .{ .int = 0 });
    try vm.php_constants.put(a, "GMP_ROUND_PLUSINF", .{ .int = 1 });
    try vm.php_constants.put(a, "GMP_ROUND_MINUSINF", .{ .int = 2 });
    try vm.php_constants.put(a, "GMP_MSW_FIRST", .{ .int = 1 });
    try vm.php_constants.put(a, "GMP_LSW_FIRST", .{ .int = 2 });
    try vm.php_constants.put(a, "GMP_LITTLE_ENDIAN", .{ .int = 4 });
    try vm.php_constants.put(a, "GMP_BIG_ENDIAN", .{ .int = 8 });
    try vm.php_constants.put(a, "GMP_NATIVE_ENDIAN", .{ .int = 16 });
}

fn gmpToString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    if (ctx.vm.frame_count == 0) return NativeResult.scalar(.null);
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return NativeResult.scalar(.null);
    if (v != .object) return NativeResult.scalar(.null);
    const p = getMpz(v.object) orelse return try NativeResult.copyString(ctx.allocator, "0");
    const cstr = zphp_mpz_get_str(10, p);
    if (cstr == null) return try NativeResult.copyString(ctx.allocator, "0");
    const slice = cstr[0..cstrLen(cstr)];
    const owned = try Value.String.create(ctx.allocator, slice);
    zphp_gmp_free(cstr);
    return NativeResult.takeString(owned);
}

// new GMP(int|string $num = 0, int $base = 0), the object gmp_init returns
fn gmpConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = thisObject(ctx) orelse return NativeResult.scalar(.null);
    const base: i64 = if (args.len > 1) Value.toInt(args[1]) else 0;
    try verifyBase(ctx, "GMP::__construct", base);
    const p = zphp_mpz_create() orelse return error.OutOfMemory;
    errdefer zphp_mpz_destroy(p);
    try initializeNumber(ctx, p, if (args.len > 0) args[0] else Value{ .int = 0 }, base, "GMP::__construct");
    if (getMpz(obj)) |old_p| zphp_mpz_destroy(old_p);
    setMpz(obj, p);
    return NativeResult.scalar(.null);
}

fn thisObject(ctx: *NativeContext) ?*PhpObject {
    if (ctx.vm.frame_count == 0) return null;
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    return if (v == .object) v.object else null;
}

// php's wire format: the number in hex at key 0, then the object's own
// properties at key 1 when it has any
fn gmpSerialize(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = thisObject(ctx) orelse return NativeResult.scalar(.null);
    const arr = try ctx.createArray();
    const cstr = if (getMpz(obj)) |p| zphp_mpz_get_str(16, p) else null;
    const hex = try Value.String.create(ctx.allocator, if (cstr) |c| c[0..cstrLen(c)] else "0");
    if (cstr) |c| zphp_gmp_free(c);
    defer hex.release();
    try arr.append(ctx.allocator, .{ .string = hex });
    if (obj.properties.count() > 0) {
        const props = try ctx.createArray();
        var it = obj.properties.iterator();
        while (it.next()) |e| try props.setCopiedKey(ctx.allocator, e.key_ptr.*, e.value_ptr.*);
        try arr.append(ctx.allocator, .{ .array = props });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn gmpUnserialize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = thisObject(ctx) orelse return NativeResult.scalar(.null);
    const data = if (args.len > 0 and args[0] == .array) args[0].array else return unserializeFailed(ctx);
    const num = data.get(.{ .int = 0 });
    if (num != .string or num.string.bytes().len == 0) return unserializeFailed(ctx);
    const z = try ctx.allocator.dupeSentinel(u8, num.string.bytes(), 0);
    defer ctx.allocator.free(z);
    const p = zphp_mpz_create() orelse return error.OutOfMemory;
    if (zphp_mpz_set_str(p, z.ptr, 16) != 0) {
        zphp_mpz_destroy(p);
        return unserializeFailed(ctx);
    }
    if (getMpz(obj)) |old| zphp_mpz_destroy(old);
    setMpz(obj, p);
    const props = data.get(.{ .int = 1 });
    if (props == .array) for (props.array.entries.items) |e| {
        if (e.key == .string) try obj.set(ctx.allocator, e.key.string.bytes(), e.value);
    };
    return NativeResult.scalar(.null);
}

// ---------------------------------------------------------------------------
// operators: php overloads arithmetic, bitwise, shift, and comparison
// operators for GMP, converting the other operand the way the gmp_*
// functions do and raising their errors

// left pending: an operator can be reached from inside a native (sort, max),
// which must unwind before anything is dispatched
fn throwOperand(ctx: *NativeContext, class_name: []const u8, comptime fmt: []const u8, args: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException(class_name, msg);
    return error.RuntimeError;
}

// (int) keeps the low bits the way mpz_get_si does; the numeric conversion
// array_sum uses falls back to float when the value does not fit
fn gmpCast(obj: *PhpObject, target: @import("../runtime/value.zig").NumericCast) ?Value {
    const p = getMpz(obj) orelse return null;
    return switch (target) {
        .int => .{ .int = zphp_mpz_get_si(p) },
        .float => .{ .float = zphp_mpz_get_d(p) },
        .bool => .{ .bool = zphp_mpz_sgn(p) != 0 },
        .number => if (zphp_mpz_fits_i64(p) != 0) .{ .int = zphp_mpz_get_si(p) } else .{ .float = zphp_mpz_get_d(p) },
    };
}

// zend_parse_arg_long_weak for a float: a fractional one is deprecated
fn weakFloat(ctx: *NativeContext, f: f64) RuntimeError!i64 {
    if (std.math.isFinite(f) and @floor(f) != f) {
        var buf: [64]u8 = undefined;
        const msg = try std.fmt.allocPrint(ctx.allocator, "Implicit conversion from float {s} to int loses precision", .{@import("formatted_print.zig").gcvt(f, -1, '.', 'E', &buf)});
        defer ctx.allocator.free(msg);
        try ctx.vm.raiseError(8192, msg);
    }
    return Value.toInt(.{ .float = f });
}

// a fresh mpz holding the operand; the caller destroys it
fn operandMpz(ctx: *NativeContext, v: Value) RuntimeError!*ZphpMpz {
    const p = zphp_mpz_create() orelse return error.OutOfMemory;
    errdefer zphp_mpz_destroy(p);
    switch (v) {
        .int => |i| _ = zphp_mpz_set_si(p, i),
        .bool => |b| _ = zphp_mpz_set_si(p, @intFromBool(b)),
        .float => |f| _ = zphp_mpz_set_si(p, try weakFloat(ctx, f)),
        .string => |str| try convertString(ctx, p, str.bytes(), 0, "", 0, ""),
        .object => |o| {
            const src = if (std.mem.eql(u8, o.class_name, "GMP")) getMpz(o) else null;
            zphp_mpz_set(p, src orelse return throwOperand(ctx, "TypeError", "Number must be of type GMP|string|int, {s} given", .{o.class_name}));
        },
        else => return throwOperand(ctx, "TypeError", "Number must be of type GMP|string|int, {s} given", .{v.typeName()}),
    }
    return p;
}

// a shift count or exponent: an unsigned long. a GMP must fit one (php 8.6
// no longer truncates it); a float that isn't integral is deprecated
fn operandCount(ctx: *NativeContext, v: Value, comptime what: []const u8) RuntimeError!c_ulong {
    const p = try operandMpz(ctx, v);
    defer zphp_mpz_destroy(p);
    if (zphp_mpz_fits_ulong_p(p) == 0) return throwOperand(ctx, "ValueError", what ++ " must be between 0 and {d}", .{ulong_max});
    return @intCast(zphp_mpz_get_ui64(p));
}

fn gmpBinop(ctx: *NativeContext, op: vm_mod.NativeBinop, a: Value, b: Value) RuntimeError!?Value {
    const lhs = try operandMpz(ctx, a);
    defer zphp_mpz_destroy(lhs);
    const unary = op == .negate or op == .bit_not;
    if (op == .compare) {
        const rhs = try operandMpz(ctx, b);
        defer zphp_mpz_destroy(rhs);
        const r = zphp_mpz_cmp(lhs, rhs);
        return .{ .int = if (r > 0) 1 else if (r < 0) -1 else 0 };
    }
    const obj = try createGmpObj(ctx);
    const out = getMpz(obj).?;
    if (unary) {
        if (op == .negate) zphp_mpz_neg(out, lhs) else zphp_mpz_com(out, lhs);
        return .{ .object = obj };
    }
    switch (op) {
        .pow => zphp_mpz_pow_ui(out, lhs, try operandCount(ctx, b, "Exponent")),
        .shl => zphp_mpz_mul_2exp(out, lhs, try operandCount(ctx, b, "Shift")),
        .shr => zphp_mpz_fdiv_q_2exp(out, lhs, try operandCount(ctx, b, "Shift")),
        else => {
            const rhs = try operandMpz(ctx, b);
            defer zphp_mpz_destroy(rhs);
            if ((op == .div or op == .mod) and zphp_mpz_sgn(rhs) == 0) {
                return throwOperand(ctx, "DivisionByZeroError", "{s}", .{if (op == .div) "Division by zero" else "Modulo by zero"});
            }
            switch (op) {
                .add => zphp_mpz_add(out, lhs, rhs),
                .sub => zphp_mpz_sub(out, lhs, rhs),
                .mul => zphp_mpz_mul(out, lhs, rhs),
                .div => zphp_mpz_tdiv_q(out, lhs, rhs),
                .mod => zphp_mpz_mod(out, lhs, rhs),
                .bit_and => zphp_mpz_and(out, lhs, rhs),
                .bit_or => zphp_mpz_ior(out, lhs, rhs),
                .bit_xor => zphp_mpz_xor(out, lhs, rhs),
                else => unreachable,
            }
        },
    }
    return .{ .object = obj };
}

// php lists a GMP's own properties and then its value in decimal as num
// var_dump and print_r show the number as "num"
fn gmpProperties(ctx: *NativeContext, obj: *PhpObject, purpose: object_properties.Purpose) RuntimeError!?*@import("../runtime/value.zig").PhpArray {
    if (purpose != .debug) return null;
    const arr = try object_properties.ownTable(ctx.vm, obj);
    const cstr = if (getMpz(obj)) |p| zphp_mpz_get_str(10, p) else null;
    const num = try Value.String.create(ctx.allocator, if (cstr) |c| c[0..cstrLen(c)] else "0");
    if (cstr) |c| zphp_gmp_free(c);
    defer num.release();
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("num") }, .{ .string = num });
    return arr;
}

fn unserializeFailed(ctx: *NativeContext) RuntimeError!NativeResult {
    try ctx.vm.setPendingException("Exception", "Could not unserialize number");
    return error.RuntimeError;
}

pub fn cleanupResources(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    for (objects.items) |obj| {
        if (obj.pooled or obj.native.kind != .gmp) continue;
        _ = cleanupGmp(obj);
    }
}
