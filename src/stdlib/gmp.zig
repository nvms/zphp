const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
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

fn cstrLen(p: [*c]const u8) usize {
    return std.mem.len(p);
}

fn getMpz(obj: *const PhpObject) ?*ZphpMpz {
    const v = obj.get("__mpz");
    if (v != .int or v.int == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(v.int)));
}

fn setMpz(obj: *PhpObject, allocator: Allocator, p: ?*ZphpMpz) !void {
    const i: i64 = if (p) |x| @intCast(@intFromPtr(x)) else 0;
    try obj.set(allocator, "__mpz", .{ .int = i });
}

fn createGmpObj(ctx: *NativeContext) !*PhpObject {
    const obj = try ctx.createObject("GMP");
    const p = zphp_mpz_create() orelse return error.OutOfMemory;
    try setMpz(obj, ctx.allocator, p);
    return obj;
}

// coerce a php value into a freshly-created mpz. caller frees with zphp_mpz_destroy
fn coerceArgToMpz(ctx: *NativeContext, v: Value) !?*ZphpMpz {
    const p = zphp_mpz_create() orelse return error.OutOfMemory;
    switch (v) {
        .int => |i| {
            _ = zphp_mpz_set_si(p, i);
            return p;
        },
        .string => |s| {
            const z = try dupZ(ctx, s);
            const rc = zphp_mpz_set_str(p, z.ptr, 0);
            if (rc != 0) {
                zphp_mpz_destroy(p);
                return null;
            }
            return p;
        },
        .object => |o| {
            if (std.mem.eql(u8, o.class_name, "GMP")) {
                if (getMpz(o)) |src| {
                    // copy via string round-trip is expensive but correct; alternatively
                    // expose a mpz_set wrapper. for now use the source pointer directly
                    // by adding/subtracting 0 from it through a new value
                    const zero = zphp_mpz_create() orelse {
                        zphp_mpz_destroy(p);
                        return error.OutOfMemory;
                    };
                    defer zphp_mpz_destroy(zero);
                    zphp_mpz_add(p, src, zero);
                    return p;
                }
            }
            zphp_mpz_destroy(p);
            return null;
        },
        else => {
            zphp_mpz_destroy(p);
            return null;
        },
    }
}

// ---------------- top-level functions ----------------

fn gmpInit(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return .{ .bool = false };
    const obj = try createGmpObj(ctx);
    const dst = getMpz(obj).?;

    // explicit base via second arg (PHP signature: gmp_init($num, $base = 0))
    // 0 = autodetect from prefix, 2..62 = explicit base
    if (args[0] == .string and args.len >= 2 and args[1] == .int) {
        const base: c_int = @intCast(args[1].int);
        const z = try dupZ(ctx, args[0].string);
        if (zphp_mpz_set_str(dst, z.ptr, base) != 0) return .{ .bool = false };
        return .{ .object = obj };
    }

    const src = (try coerceArgToMpz(ctx, args[0])) orelse return .{ .bool = false };
    defer zphp_mpz_destroy(src);
    const zero = zphp_mpz_create() orelse return error.OutOfMemory;
    defer zphp_mpz_destroy(zero);
    zphp_mpz_add(dst, src, zero);
    return .{ .object = obj };
}

fn gmpStrval(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return .null;
    var base: c_int = 10;
    if (args.len > 1 and args[1] == .int) base = @intCast(args[1].int);
    const src = (try coerceArgToMpz(ctx, args[0])) orelse return .null;
    defer zphp_mpz_destroy(src);
    const cstr = zphp_mpz_get_str(base, src);
    if (cstr == null) return .{ .string = try dupString(ctx, "") };
    const slice = cstr[0..cstrLen(cstr)];
    const owned = try dupString(ctx, slice);
    zphp_gmp_free(cstr);
    return .{ .string = owned };
}

fn gmpIntval(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return .{ .int = 0 };
    const src = (try coerceArgToMpz(ctx, args[0])) orelse return .{ .int = 0 };
    defer zphp_mpz_destroy(src);
    return .{ .int = zphp_mpz_get_si(src) };
}

const Binop = *const fn (r: *ZphpMpz, a: *const ZphpMpz, b: *const ZphpMpz) callconv(.c) void;
const Unop = *const fn (r: *ZphpMpz, a: *const ZphpMpz) callconv(.c) void;

fn binOpCall(ctx: *NativeContext, args: []const Value, op: Binop) RuntimeError!Value {
    if (args.len < 2) return .null;
    const a = (try coerceArgToMpz(ctx, args[0])) orelse return .null;
    defer zphp_mpz_destroy(a);
    const b = (try coerceArgToMpz(ctx, args[1])) orelse return .null;
    defer zphp_mpz_destroy(b);
    const obj = try createGmpObj(ctx);
    op(getMpz(obj).?, a, b);
    return .{ .object = obj };
}

fn unOpCall(ctx: *NativeContext, args: []const Value, op: Unop) RuntimeError!Value {
    if (args.len < 1) return .null;
    const a = (try coerceArgToMpz(ctx, args[0])) orelse return .null;
    defer zphp_mpz_destroy(a);
    const obj = try createGmpObj(ctx);
    op(getMpz(obj).?, a);
    return .{ .object = obj };
}

fn gmpBinomial(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .null;
    const an = (try coerceArgToMpz(ctx, args[0])) orelse return .null;
    defer zphp_mpz_destroy(an);
    const ak = (try coerceArgToMpz(ctx, args[1])) orelse return .null;
    defer zphp_mpz_destroy(ak);
    const n = zphp_mpz_get_si(an);
    const k_raw = zphp_mpz_get_si(ak);
    const obj = try createGmpObj(ctx);
    const result = getMpz(obj).?;
    if (k_raw < 0 or n < 0 or k_raw > n) {
        _ = zphp_mpz_set_si(result, 0);
        return .{ .object = obj };
    }
    // use C(n,k) = C(n,n-k) and pick the smaller k for efficiency
    var k = k_raw;
    if (k > n - k) k = n - k;
    _ = zphp_mpz_set_si(result, 1);
    const cur = zphp_mpz_create() orelse return error.OutOfMemory;
    defer zphp_mpz_destroy(cur);
    const divisor = zphp_mpz_create() orelse return error.OutOfMemory;
    defer zphp_mpz_destroy(divisor);
    var i: i64 = 0;
    while (i < k) : (i += 1) {
        _ = zphp_mpz_set_si(cur, n - i);
        zphp_mpz_mul(result, result, cur);
        _ = zphp_mpz_set_si(divisor, i + 1);
        zphp_mpz_tdiv_q(result, result, divisor);
    }
    return .{ .object = obj };
}

fn gmpFact(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return .null;
    const a = (try coerceArgToMpz(ctx, args[0])) orelse return .null;
    defer zphp_mpz_destroy(a);
    const n = zphp_mpz_get_si(a);
    const obj = try createGmpObj(ctx);
    const result = getMpz(obj).?;
    _ = zphp_mpz_set_si(result, 1);
    if (n <= 1) return .{ .object = obj };
    const cur = zphp_mpz_create() orelse return error.OutOfMemory;
    defer zphp_mpz_destroy(cur);
    var i: i64 = 2;
    while (i <= n) : (i += 1) {
        _ = zphp_mpz_set_si(cur, i);
        zphp_mpz_mul(result, result, cur);
    }
    return .{ .object = obj };
}

fn gmpAdd(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return binOpCall(ctx, args, zphp_mpz_add); }
fn gmpSub(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return binOpCall(ctx, args, zphp_mpz_sub); }
fn gmpMul(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return binOpCall(ctx, args, zphp_mpz_mul); }
fn gmpAnd(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return binOpCall(ctx, args, zphp_mpz_and); }
fn gmpOr(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return binOpCall(ctx, args, zphp_mpz_ior); }
fn gmpXor(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return binOpCall(ctx, args, zphp_mpz_xor); }
fn gmpGcd(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return binOpCall(ctx, args, zphp_mpz_gcd); }
fn gmpLcm(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return binOpCall(ctx, args, zphp_mpz_lcm); }
fn gmpDivQ(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return binOpCall(ctx, args, zphp_mpz_tdiv_q); }
fn gmpDivR(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return binOpCall(ctx, args, zphp_mpz_tdiv_r); }
fn gmpMod(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return binOpCall(ctx, args, zphp_mpz_mod); }

fn gmpNeg(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return unOpCall(ctx, args, zphp_mpz_neg); }
fn gmpAbs(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return unOpCall(ctx, args, zphp_mpz_abs); }
fn gmpCom(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return unOpCall(ctx, args, zphp_mpz_com); }
fn gmpSqrt(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return unOpCall(ctx, args, zphp_mpz_sqrt); }
fn gmpNextprime(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return unOpCall(ctx, args, zphp_mpz_nextprime); }

fn gmpCmp(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .null;
    const a = (try coerceArgToMpz(ctx, args[0])) orelse return .null;
    defer zphp_mpz_destroy(a);
    const b = (try coerceArgToMpz(ctx, args[1])) orelse return .null;
    defer zphp_mpz_destroy(b);
    const r = zphp_mpz_cmp(a, b);
    return .{ .int = if (r > 0) 1 else if (r < 0) -1 else 0 };
}

fn gmpSign(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return .{ .int = 0 };
    const a = (try coerceArgToMpz(ctx, args[0])) orelse return .{ .int = 0 };
    defer zphp_mpz_destroy(a);
    const r = zphp_mpz_sgn(a);
    return .{ .int = if (r > 0) 1 else if (r < 0) -1 else 0 };
}

fn gmpPow(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[1] != .int) return .null;
    const a = (try coerceArgToMpz(ctx, args[0])) orelse return .null;
    defer zphp_mpz_destroy(a);
    const obj = try createGmpObj(ctx);
    const e: c_ulong = @intCast(args[1].int);
    zphp_mpz_pow_ui(getMpz(obj).?, a, e);
    return .{ .object = obj };
}

fn gmpPowm(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3) return .null;
    const a = (try coerceArgToMpz(ctx, args[0])) orelse return .null;
    defer zphp_mpz_destroy(a);
    const e = (try coerceArgToMpz(ctx, args[1])) orelse return .null;
    defer zphp_mpz_destroy(e);
    const m = (try coerceArgToMpz(ctx, args[2])) orelse return .null;
    defer zphp_mpz_destroy(m);
    const obj = try createGmpObj(ctx);
    zphp_mpz_powm(getMpz(obj).?, a, e, m);
    return .{ .object = obj };
}

fn gmpInvert(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .bool = false };
    const a = (try coerceArgToMpz(ctx, args[0])) orelse return .{ .bool = false };
    defer zphp_mpz_destroy(a);
    const m = (try coerceArgToMpz(ctx, args[1])) orelse return .{ .bool = false };
    defer zphp_mpz_destroy(m);
    const obj = try createGmpObj(ctx);
    if (zphp_mpz_invert(getMpz(obj).?, a, m) == 0) return .{ .bool = false };
    return .{ .object = obj };
}

fn gmpProbPrime(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return .{ .int = 0 };
    const reps: c_int = if (args.len > 1 and args[1] == .int) @intCast(args[1].int) else 10;
    const a = (try coerceArgToMpz(ctx, args[0])) orelse return .{ .int = 0 };
    defer zphp_mpz_destroy(a);
    return .{ .int = @intCast(zphp_mpz_probab_prime_p(a, reps)) };
}

fn gmpSetbit(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .object or args[1] != .int) return .null;
    const obj = args[0].object;
    if (!std.mem.eql(u8, obj.class_name, "GMP")) return .null;
    const p = getMpz(obj) orelse return .null;
    const bit: c_ulong = @intCast(args[1].int);
    const set_val: bool = if (args.len > 2 and args[2] == .bool) args[2].bool else true;
    if (set_val) zphp_mpz_setbit(p, bit) else zphp_mpz_clrbit(p, bit);
    return .null;
}

fn gmpClrbit(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .object or args[1] != .int) return .null;
    const obj = args[0].object;
    if (!std.mem.eql(u8, obj.class_name, "GMP")) return .null;
    const p = getMpz(obj) orelse return .null;
    zphp_mpz_clrbit(p, @intCast(args[1].int));
    return .null;
}

fn gmpTestbit(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[1] != .int) return .{ .bool = false };
    const a = (try coerceArgToMpz(ctx, args[0])) orelse return .{ .bool = false };
    defer zphp_mpz_destroy(a);
    return .{ .bool = zphp_mpz_testbit(a, @intCast(args[1].int)) != 0 };
}

fn gmpPopcount(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return .{ .int = 0 };
    const a = (try coerceArgToMpz(ctx, args[0])) orelse return .{ .int = 0 };
    defer zphp_mpz_destroy(a);
    return .{ .int = @intCast(zphp_mpz_popcount(a)) };
}

fn gmpScan0(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[1] != .int) return .{ .int = -1 };
    const a = (try coerceArgToMpz(ctx, args[0])) orelse return .{ .int = -1 };
    defer zphp_mpz_destroy(a);
    const r = zphp_mpz_scan0(a, @intCast(@max(args[1].int, 0)));
    // GMP returns ULONG_MAX when no zero bit is found; map to -1 like PHP
    if (r == std.math.maxInt(c_ulong)) return .{ .int = -1 };
    return .{ .int = @intCast(r) };
}

fn gmpScan1(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[1] != .int) return .{ .int = -1 };
    const a = (try coerceArgToMpz(ctx, args[0])) orelse return .{ .int = -1 };
    defer zphp_mpz_destroy(a);
    const r = zphp_mpz_scan1(a, @intCast(@max(args[1].int, 0)));
    if (r == std.math.maxInt(c_ulong)) return .{ .int = -1 };
    return .{ .int = @intCast(r) };
}

fn gmpHamdist(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .int = 0 };
    const a = (try coerceArgToMpz(ctx, args[0])) orelse return .{ .int = 0 };
    defer zphp_mpz_destroy(a);
    const b = (try coerceArgToMpz(ctx, args[1])) orelse return .{ .int = 0 };
    defer zphp_mpz_destroy(b);
    const xored = zphp_mpz_create() orelse return error.OutOfMemory;
    defer zphp_mpz_destroy(xored);
    zphp_mpz_xor(xored, a, b);
    return .{ .int = @intCast(zphp_mpz_popcount(xored)) };
}

fn gmpLegendre(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .int = 0 };
    const a = (try coerceArgToMpz(ctx, args[0])) orelse return .{ .int = 0 };
    defer zphp_mpz_destroy(a);
    const p = (try coerceArgToMpz(ctx, args[1])) orelse return .{ .int = 0 };
    defer zphp_mpz_destroy(p);
    return .{ .int = @intCast(zphp_mpz_legendre(a, p)) };
}

fn gmpJacobi(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .int = 0 };
    const a = (try coerceArgToMpz(ctx, args[0])) orelse return .{ .int = 0 };
    defer zphp_mpz_destroy(a);
    const b = (try coerceArgToMpz(ctx, args[1])) orelse return .{ .int = 0 };
    defer zphp_mpz_destroy(b);
    return .{ .int = @intCast(zphp_mpz_jacobi(a, b)) };
}

fn gmpPerfectSquare(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return .{ .bool = false };
    const a = (try coerceArgToMpz(ctx, args[0])) orelse return .{ .bool = false };
    defer zphp_mpz_destroy(a);
    return .{ .bool = zphp_mpz_perfect_square_p(a) != 0 };
}

fn gmpRoot(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[1] != .int) return .null;
    const a = (try coerceArgToMpz(ctx, args[0])) orelse return .null;
    defer zphp_mpz_destroy(a);
    const obj = try createGmpObj(ctx);
    zphp_mpz_root(getMpz(obj).?, a, @intCast(args[1].int));
    return .{ .object = obj };
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
    .{ "gmp_div", gmpDivQ },
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

pub fn register(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "GMP" };
    // GMP is mostly a value-holding class; user-facing methods are
    // PHP's procedural ones. providing __toString lets `(string)$gmp` work
    try def.methods.put(a, "__toString", .{ .name = "__toString", .arity = 0 });
    try vm.classes.put(a, "GMP", def);
    try vm.native_fns.put(a, "GMP::__toString", gmpToString);
    try vm.php_constants.put(a, "GMP_ROUND_ZERO", .{ .int = 0 });
    try vm.php_constants.put(a, "GMP_ROUND_PLUSINF", .{ .int = 1 });
    try vm.php_constants.put(a, "GMP_ROUND_MINUSINF", .{ .int = 2 });
    try vm.php_constants.put(a, "GMP_MSW_FIRST", .{ .int = 1 });
    try vm.php_constants.put(a, "GMP_LSW_FIRST", .{ .int = 2 });
    try vm.php_constants.put(a, "GMP_LITTLE_ENDIAN", .{ .int = 4 });
    try vm.php_constants.put(a, "GMP_BIG_ENDIAN", .{ .int = 8 });
    try vm.php_constants.put(a, "GMP_NATIVE_ENDIAN", .{ .int = 16 });
}

fn gmpToString(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    if (ctx.vm.frame_count == 0) return .null;
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return .null;
    if (v != .object) return .null;
    const p = getMpz(v.object) orelse return .{ .string = try dupString(ctx, "0") };
    const cstr = zphp_mpz_get_str(10, p);
    if (cstr == null) return .{ .string = try dupString(ctx, "0") };
    const slice = cstr[0..cstrLen(cstr)];
    const owned = try dupString(ctx, slice);
    zphp_gmp_free(cstr);
    return .{ .string = owned };
}

pub fn cleanupResources(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    for (objects.items) |obj| {
        if (!std.mem.eql(u8, obj.class_name, "GMP")) continue;
        if (getMpz(obj)) |p| zphp_mpz_destroy(p);
    }
}
