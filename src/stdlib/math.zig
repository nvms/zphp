const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const std = @import("std");
const platform = @import("../platform.zig");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const phpTypeName = @import("types.zig").phpTypeName;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "abs", native_abs },
    .{ "floor", native_floor },
    .{ "ceil", native_ceil },
    .{ "round", native_round },
    .{ "min", native_min },
    .{ "max", native_max },
    .{ "rand", native_rand },
    .{ "lcg_value", native_lcg_value },
    .{ "pow", native_pow },
    .{ "sqrt", native_sqrt },
    .{ "log", native_log },
    .{ "log10", native_log10 },
    .{ "log1p", native_log1p },
    .{ "expm1", native_expm1 },
    .{ "exp", native_exp },
    .{ "pi", native_pi },
    .{ "fmod", native_fmod },
    .{ "intdiv", native_intdiv },
    .{ "base_convert", native_base_convert },
    .{ "bindec", native_bindec },
    .{ "octdec", native_octdec },
    .{ "hexdec", native_hexdec },
    .{ "decbin", native_decbin },
    .{ "decoct", native_decoct },
    .{ "dechex", native_dechex },
    .{ "sin", native_sin },
    .{ "cos", native_cos },
    .{ "tan", native_tan },
    .{ "asin", native_asin },
    .{ "acos", native_acos },
    .{ "atan", native_atan },
    .{ "atan2", native_atan2 },
    .{ "sinh", native_sinh },
    .{ "cosh", native_cosh },
    .{ "tanh", native_tanh },
    .{ "asinh", native_asinh },
    .{ "acosh", native_acosh },
    .{ "atanh", native_atanh },
    .{ "deg2rad", native_deg2rad },
    .{ "rad2deg", native_rad2deg },
    .{ "hypot", native_hypot },
    .{ "is_finite", native_is_finite },
    .{ "is_infinite", native_is_infinite },
    .{ "is_nan", native_is_nan },
    .{ "mt_rand", native_rand },
    .{ "mt_srand", native_mt_srand },
    .{ "srand", native_mt_srand },
    .{ "mt_getrandmax", native_getrandmax },
    .{ "getrandmax", native_getrandmax },
    .{ "fpow", native_fpow },
    .{ "fdiv", native_fdiv },
    .{ "number_format", native_number_format },
};

const Args = @import("string_ports.zig").Args;

// the c library's math, as php calls it. zig's compiler_rt defines sin, cos,
// tan, exp, log, log2 and log10 inside the executable, and they differ from
// glibc's in the last bit for some inputs (exp(1), sin(-2.5)), so on linux
// those come from libm itself; elsewhere compiler_rt's are what links
const C1 = *const fn (f64) callconv(.c) f64;
extern fn sin(f64) f64;
extern fn cos(f64) f64;
extern fn tan(f64) f64;
extern fn exp(f64) f64;
extern fn log(f64) f64;
extern fn log2(f64) f64;
extern fn log10(f64) f64;

const Libm = struct {
    sin: C1 = &sin,
    cos: C1 = &cos,
    tan: C1 = &tan,
    exp: C1 = &exp,
    log: C1 = &log,
    log2: C1 = &log2,
    log10: C1 = &log10,
};

var libm_table: Libm = .{};
var libm_once = std.atomic.Value(bool).init(false);
var libm_mutex: @import("../sync.zig").Mutex = .{};

fn libm() *const Libm {
    if (libm_once.load(.acquire)) return &libm_table;
    libm_mutex.lock();
    defer libm_mutex.unlock();
    if (!libm_once.load(.monotonic)) {
        if (@import("builtin").os.tag == .linux and @import("builtin").abi.isGnu()) {
            if (std.DynLib.open("libm.so.6")) |opened| {
                var lib = opened;
                inline for (.{ "sin", "cos", "tan", "exp", "log", "log2", "log10" }) |name| {
                    if (lib.lookup(C1, name)) |f| @field(libm_table, name) = f;
                }
            } else |_| {}
        }
        libm_once.store(true, .release);
    }
    return &libm_table;
}

fn c_sin(x: f64) callconv(.c) f64 {
    return libm().sin(x);
}
fn c_cos(x: f64) callconv(.c) f64 {
    return libm().cos(x);
}
fn c_tan(x: f64) callconv(.c) f64 {
    return libm().tan(x);
}
fn c_exp(x: f64) callconv(.c) f64 {
    return libm().exp(x);
}
fn c_log(x: f64) callconv(.c) f64 {
    return libm().log(x);
}
fn c_log2(x: f64) callconv(.c) f64 {
    return libm().log2(x);
}
fn c_log10(x: f64) callconv(.c) f64 {
    return libm().log10(x);
}

extern fn asin(f64) f64;
extern fn acos(f64) f64;
extern fn atan(f64) f64;
extern fn atan2(f64, f64) f64;
extern fn sinh(f64) f64;
extern fn cosh(f64) f64;
extern fn tanh(f64) f64;
extern fn asinh(f64) f64;
extern fn acosh(f64) f64;
extern fn atanh(f64) f64;
extern fn expm1(f64) f64;
extern fn log1p(f64) f64;
extern fn sqrt(f64) f64;
extern fn hypot(f64, f64) f64;
extern fn fmod(f64, f64) f64;
extern fn snprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ...) c_int;

const m_pi: f64 = 3.14159265358979323846;

fn native_abs(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const v = try Args.init(ctx, "abs", args).number(0, "num");
    return NativeResult.scalar(switch (v) {
        .int => |i| if (i == std.math.minInt(i64))
            .{ .float = -@as(f64, @floatFromInt(i)) }
        else
            .{ .int = if (i < 0) -i else i },
        else => .{ .float = @abs(v.float) },
    });
}

fn native_floor(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const v = try Args.init(ctx, "floor", args).number(0, "num");
    return NativeResult.scalar(.{ .float = if (v == .int) @floatFromInt(v.int) else @floor(v.float) });
}

fn native_ceil(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const v = try Args.init(ctx, "ceil", args).number(0, "num");
    return NativeResult.scalar(.{ .float = if (v == .int) @floatFromInt(v.int) else @ceil(v.float) });
}

fn native_round(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "round", args);
    const num = try p.number(0, "num");
    var places: i32 = 0;
    if (p.has(1)) {
        const precision = try p.long(1, "precision");
        places = @intCast(std.math.clamp(precision, std.math.minInt(i32), std.math.maxInt(i32)));
    }
    var mode: i64 = round_half_up;
    if (p.has(2)) {
        const m = args[2];
        if (m == .object and ctx.vm.isInstanceOf(m.object.class_name, "RoundingMode")) {
            const case_name = m.object.get("name");
            if (case_name == .string) mode = roundingModeOfCase(case_name.string.bytes());
        } else if (m == .object) {
            return p.typeError(2, "mode", "RoundingMode|int");
        } else {
            mode = try p.longAs(2, "mode", "RoundingMode|int");
        }
    }
    if (mode < round_half_up or mode > round_away_from_zero) {
        try ctx.vm.setPendingException("ValueError", "round(): Argument #3 ($mode) must be a valid rounding mode (RoundingMode::*)");
        return error.RuntimeError;
    }
    // an int that needs no rounding comes back as a float unchanged
    if (num == .int and places >= 0) return NativeResult.scalar(.{ .float = @floatFromInt(num.int) });
    const f: f64 = if (num == .int) @floatFromInt(num.int) else num.float;
    return NativeResult.scalar(.{ .float = phpRound(f, places, mode) });
}

// php_math_round_mode.h
const round_half_up = 1;
const round_half_down = 2;
const round_half_even = 3;
const round_half_odd = 4;
const round_ceiling = 5;
const round_floor = 6;
const round_toward_zero = 7;
const round_away_from_zero = 8;

fn roundingModeOfCase(name: []const u8) i64 {
    const modes = [_]struct { []const u8, i64 }{
        .{ "HalfAwayFromZero", round_half_up },  .{ "HalfTowardsZero", round_half_down }, .{ "HalfEven", round_half_even },
        .{ "HalfOdd", round_half_odd },          .{ "TowardsZero", round_toward_zero },   .{ "AwayFromZero", round_away_from_zero },
        .{ "NegativeInfinity", round_floor },    .{ "PositiveInfinity", round_ceiling },
    };
    for (modes) |m| if (std.mem.eql(u8, m[0], name)) return m[1];
    return round_half_up;
}

const c_pow = @import("../runtime/value.zig").c_pow;

fn intPow10(power: i32) f64 {
    const powers = [_]f64{ 1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11, 1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22 };
    // php calls c's pow here, whose result for some powers (10^23 is a
    // tie between two doubles) is not the correctly rounded literal
    if (power < 0 or power > 22) return c_pow(10.0, @floatFromInt(power));
    return powers[@intCast(power)];
}

// php's _php_math_round (ext/standard/math.c)
pub fn phpRound(value: f64, places_in: i32, mode: i64) f64 {
    if (!std.math.isFinite(value) or value == 0.0) return value;
    if (places_in == 0 and value == @trunc(value)) return value;
    const places = @max(places_in, std.math.minInt(i32) + 1);
    const exponent = intPow10(@intCast(@abs(places)));
    var tmp: f64 = undefined;
    var tmp2: f64 = undefined;
    // the scaled value can be one off as a decimal (0.285 * 1e10 is
    // 2849999999.9999995): try the next integral and keep it when it scales
    // back to the value exactly
    if (value >= 0.0) {
        tmp = @floor(if (places > 0) value * exponent else value / exponent);
        tmp2 = tmp + 1.0;
    } else {
        tmp = @ceil(if (places > 0) value * exponent else value / exponent);
        tmp2 = tmp - 1.0;
    }
    if ((if (places > 0) tmp2 / exponent else tmp2 * exponent) == value) tmp = tmp2;
    // beyond a double's precision rounding changes nothing
    if (@abs(tmp) >= 1e16) return value;
    tmp = roundHelper(tmp, value, exponent, places, mode);
    if (@abs(places) < 23) return if (places > 0) tmp / exponent else tmp * exponent;
    // php prints the integral with "%15fe%d" and parses it back
    var buf: [64]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d:15.6}e{d}", .{ tmp, -places }) catch return value;
    const back = std.fmt.parseFloat(f64, std.mem.trim(u8, text, " ")) catch return value;
    // zend_strtod gives an unsigned zero
    if (back == 0) return 0.0;
    return if (std.math.isFinite(back)) back else value;
}

fn roundHelper(integral: f64, value: f64, exponent: f64, places: i32, mode: i64) f64 {
    const value_abs = @abs(value);
    const away = std.math.copysign(@as(f64, 1.0), integral);
    const basic_edge = @abs(if (places > 0) (integral + std.math.copysign(@as(f64, 0.5), integral)) / exponent else (integral + std.math.copysign(@as(f64, 0.5), integral)) * exponent);
    const zero_edge = @abs(if (places > 0) integral / exponent else integral * exponent);
    return switch (mode) {
        round_half_up => if (value_abs >= basic_edge) integral + away else integral,
        round_half_down => if (value_abs > basic_edge) integral + away else integral,
        round_ceiling => if (value > 0.0 and value_abs > zero_edge) integral + 1.0 else integral,
        round_floor => if (value < 0.0 and value_abs > zero_edge) integral - 1.0 else integral,
        round_toward_zero => integral,
        round_away_from_zero => if (value_abs > zero_edge) integral + away else integral,
        round_half_even, round_half_odd => blk: {
            if (value_abs > basic_edge) break :blk integral + away;
            if (value_abs == basic_edge) {
                const even = @mod(integral, 2.0) == 0;
                if (even != (mode == round_half_even)) break :blk integral + away;
            }
            break :blk integral;
        },
        else => integral,
    };
}

fn native_lcg_value(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .float = platform.random.float(f64) });
}

// mt_srand and srand: a seed, or a random one for null, and the mode; any
// mode but MT_RAND_PHP is MT_RAND_MT19937
fn native_mt_srand(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const legacy = args.len >= 2 and Value.toInt(args[1]) == 1;
    if (legacy) try ctx.vm.raiseError(@import("../runtime/vm.zig").VM.E_DEPRECATED, "The MT_RAND_PHP variant of Mt19937 is deprecated");
    const seed: u32 = if (args.len >= 1 and args[0] != .null) blk: {
        const v = Value.toInt(args[0]);
        break :blk @as(u32, @truncate(@as(u64, @bitCast(v))));
    } else blk: {
        var entropy: [4]u8 = undefined;
        platform.random.bytes(&entropy);
        break :blk std.mem.readInt(u32, &entropy, .little);
    };
    ctx.vm.mt19937.mode = if (legacy) .php else .mt19937;
    ctx.vm.mt19937.seed(seed);
    ctx.vm.rng_seeded = true;
    return NativeResult.scalar(.null);
}

fn native_getrandmax(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = 2147483647 });
}

fn native_rand(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (!ctx.vm.rng_seeded) {
        var entropy: [4]u8 = undefined;
        platform.random.bytes(&entropy);
        const sd: u32 = std.mem.readInt(u32, &entropy, .little);
        ctx.vm.mt19937.seed(sd);
        ctx.vm.rng_seeded = true;
    }
    const lo: i64 = if (args.len >= 1) Value.toInt(args[0]) else 0;
    const hi: i64 = if (args.len >= 2) Value.toInt(args[1]) else 2147483647;
    // mt_rand() with no args returns a 31-bit value
    if (args.len < 2) return NativeResult.scalar(.{ .int = ctx.vm.mt19937.next31() });
    // PHP 8+: mt_rand throws ValueError if max < min. rand silently swaps
    // (a historical alias quirk preserved for back-compat). distinguish by
    // the calling-name in ctx.call_name
    if (lo > hi) {
        const fn_name: []const u8 = if (ctx.call_name) |c| c else "mt_rand";
        if (std.mem.eql(u8, fn_name, "rand")) {
            return NativeResult.scalar(.{ .int = ctx.vm.mt19937.nextCommon(hi, lo) });
        }
        const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): Argument #2 ($max) must be greater than or equal to argument #1 ($min)", .{fn_name});
        defer ctx.allocator.free(msg);
        try ctx.vm.setPendingException("ValueError", msg);
        return error.RuntimeError;
    }
    return NativeResult.scalar(.{ .int = ctx.vm.mt19937.nextCommon(lo, hi) });
}

fn native_pow(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return NativeResult.transfer(try ctx.vm.powFunction(args[0], args[1]));
}

const e_deprecated = 8192;

fn floatFn(comptime name: []const u8, comptime f: fn (f64) callconv(.c) f64) fn (*NativeContext, []const Value) RuntimeError!NativeResult {
    return struct {
        fn call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
            const x = try Args.init(ctx, name, args).double(0, "num");
            return NativeResult.scalar(.{ .float = f(x) });
        }
    }.call;
}

const native_sin = floatFn("sin", c_sin);
const native_cos = floatFn("cos", c_cos);
const native_tan = floatFn("tan", c_tan);
const native_asin = floatFn("asin", asin);
const native_acos = floatFn("acos", acos);
const native_atan = floatFn("atan", atan);
const native_sinh = floatFn("sinh", sinh);
const native_cosh = floatFn("cosh", cosh);
const native_tanh = floatFn("tanh", tanh);
const native_asinh = floatFn("asinh", asinh);
const native_acosh = floatFn("acosh", acosh);
const native_atanh = floatFn("atanh", atanh);
const native_exp = floatFn("exp", c_exp);
const native_expm1 = floatFn("expm1", expm1);
const native_log1p = floatFn("log1p", log1p);
const native_log10 = floatFn("log10", c_log10);
const native_sqrt = floatFn("sqrt", sqrt);

fn native_atan2(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "atan2", args);
    const y = try p.double(0, "y");
    const x = try p.double(1, "x");
    return NativeResult.scalar(.{ .float = atan2(y, x) });
}

fn native_log(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "log", args);
    const num = try p.double(0, "num");
    if (!p.has(1)) return NativeResult.scalar(.{ .float = c_log(num) });
    const base = try p.double(1, "base");
    if (base == 2.0) return NativeResult.scalar(.{ .float = c_log2(num) });
    if (base == 10.0) return NativeResult.scalar(.{ .float = c_log10(num) });
    if (base == 1.0) return NativeResult.scalar(.{ .float = std.math.nan(f64) });
    if (base <= 0.0) return p.valueError(1, "base", "must be greater than 0");
    return NativeResult.scalar(.{ .float = c_log(num) / c_log(base) });
}

fn native_pi(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .float = m_pi });
}

fn native_hypot(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "hypot", args);
    const x = try p.double(0, "x");
    const y = try p.double(1, "y");
    return NativeResult.scalar(.{ .float = hypot(x, y) });
}

fn native_deg2rad(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const deg = try Args.init(ctx, "deg2rad", args).double(0, "num");
    return NativeResult.scalar(.{ .float = (deg / 180.0) * m_pi });
}

fn native_rad2deg(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const rad = try Args.init(ctx, "rad2deg", args).double(0, "num");
    return NativeResult.scalar(.{ .float = (rad / m_pi) * 180.0 });
}

fn native_is_finite(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const x = try Args.init(ctx, "is_finite", args).double(0, "num");
    return NativeResult.scalar(.{ .bool = std.math.isFinite(x) });
}

fn native_is_infinite(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const x = try Args.init(ctx, "is_infinite", args).double(0, "num");
    return NativeResult.scalar(.{ .bool = std.math.isInf(x) });
}

fn native_is_nan(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const x = try Args.init(ctx, "is_nan", args).double(0, "num");
    return NativeResult.scalar(.{ .bool = std.math.isNan(x) });
}

fn native_fmod(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "fmod", args);
    const x = try p.double(0, "num1");
    const y = try p.double(1, "num2");
    return NativeResult.scalar(.{ .float = fmod(x, y) });
}

fn native_fdiv(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "fdiv", args);
    const x = try p.double(0, "num1");
    const y = try p.double(1, "num2");
    return NativeResult.scalar(.{ .float = x / y });
}

fn native_fpow(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "fpow", args);
    const x = try p.double(0, "num");
    const y = try p.double(1, "exponent");
    return NativeResult.scalar(.{ .float = c_pow(x, y) });
}

fn native_intdiv(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "intdiv", args);
    const a = try p.long(0, "num1");
    const b = try p.long(1, "num2");
    if (b == 0) {
        try ctx.vm.setPendingException("DivisionByZeroError", "Division by zero");
        return error.RuntimeError;
    }
    if (a == std.math.minInt(i64) and b == -1) {
        try ctx.vm.setPendingException("ArithmeticError", "Division of PHP_INT_MIN by -1 is not an integer");
        return error.RuntimeError;
    }
    return NativeResult.scalar(.{ .int = @divTrunc(a, b) });
}

const digit_chars = "0123456789abcdefghijklmnopqrstuvwxyz";

// _php_math_basetozval: the digits of `base` in s, skipping surrounding
// whitespace and the base's 0x/0o/0b prefix, as an int or, past
// PHP_INT_MAX, a float; any other character is ignored with a deprecation
fn baseToValue(ctx: *NativeContext, str: []const u8, base: u8) RuntimeError!Value {
    var s = str;
    while (s.len > 0 and isSpace(s[0])) s = s[1..];
    while (s.len > 0 and isSpace(s[s.len - 1])) s = s[0 .. s.len - 1];
    if (s.len >= 2 and s[0] == '0') {
        const p = std.ascii.toLower(s[1]);
        if ((base == 16 and p == 'x') or (base == 8 and p == 'o') or (base == 2 and p == 'b')) s = s[2..];
    }
    const cutoff = @divTrunc(std.math.maxInt(i64), @as(i64, base));
    const cutlim = @rem(std.math.maxInt(i64), @as(i64, base));
    var num: i64 = 0;
    var fnum: f64 = 0;
    var float_mode = false;
    var invalid = false;
    for (s) |ch| {
        const c: u8 = switch (ch) {
            '0'...'9' => ch - '0',
            'A'...'Z' => ch - 'A' + 10,
            'a'...'z' => ch - 'a' + 10,
            else => {
                invalid = true;
                continue;
            },
        };
        if (c >= base) {
            invalid = true;
            continue;
        }
        if (!float_mode) {
            if (num < cutoff or (num == cutoff and c <= cutlim)) {
                num = num * base + c;
                continue;
            }
            fnum = @floatFromInt(num);
            float_mode = true;
        }
        fnum = fnum * @as(f64, @floatFromInt(base)) + @as(f64, @floatFromInt(c));
    }
    if (invalid) try ctx.vm.raiseError(e_deprecated, "Invalid characters passed for attempted conversion, these have been ignored");
    return if (float_mode) .{ .float = fnum } else .{ .int = num };
}

// c's isspace in the C locale
fn isSpace(c: u8) bool {
    return c == ' ' or (c >= '\t' and c <= '\r');
}

fn longToBase(ctx: *NativeContext, value: i64, base: u8) RuntimeError!NativeResult {
    var buf: [65]u8 = undefined;
    var pos: usize = buf.len;
    var v: u64 = @bitCast(value);
    while (true) {
        pos -= 1;
        buf[pos] = digit_chars[@intCast(v % base)];
        v /= base;
        if (v == 0) break;
    }
    return NativeResult.copyString(ctx.allocator, buf[pos..]);
}

fn baseDec(comptime name: []const u8, comptime base: u8) fn (*NativeContext, []const Value) RuntimeError!NativeResult {
    return struct {
        fn call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
            const s = try Args.init(ctx, name, args).str(0, if (base == 16) "hex_string" else if (base == 8) "octal_string" else "binary_string");
            return NativeResult.scalar(try baseToValue(ctx, s, base));
        }
    }.call;
}

fn decBase(comptime name: []const u8, comptime base: u8) fn (*NativeContext, []const Value) RuntimeError!NativeResult {
    return struct {
        fn call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
            const n = try Args.init(ctx, name, args).long(0, "num");
            return longToBase(ctx, n, base);
        }
    }.call;
}

const native_bindec = baseDec("bindec", 2);
const native_octdec = baseDec("octdec", 8);
const native_hexdec = baseDec("hexdec", 16);
const native_decbin = decBase("decbin", 2);
const native_decoct = decBase("decoct", 8);
const native_dechex = decBase("dechex", 16);

fn native_base_convert(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "base_convert", args);
    const number = try p.str(0, "num");
    const from = try p.long(1, "from_base");
    const to = try p.long(2, "to_base");
    if (from < 2 or from > 36) return p.valueError(1, "from_base", "must be between 2 and 36 (inclusive)");
    if (to < 2 or to > 36) return p.valueError(2, "to_base", "must be between 2 and 36 (inclusive)");
    const base: u8 = @intCast(to);
    const v = try baseToValue(ctx, number, @intCast(from));
    if (v == .int) return longToBase(ctx, v.int, base);
    // _php_math_zvaltobase for a float: digits by fmod until under 1
    var fvalue = @floor(v.float);
    if (std.math.isInf(fvalue)) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "An infinite value cannot be converted to base {d}", .{base});
        defer ctx.allocator.free(msg);
        try ctx.vm.setPendingException("ValueError", msg);
        return error.RuntimeError;
    }
    var buf: [1080]u8 = undefined;
    var pos: usize = buf.len;
    while (true) {
        pos -= 1;
        buf[pos] = digit_chars[@intFromFloat(fmod(fvalue, @floatFromInt(base)))];
        fvalue /= @floatFromInt(base);
        if (pos == 0 or @abs(fvalue) < 1) break;
    }
    return NativeResult.copyString(ctx.allocator, buf[pos..]);
}

fn native_number_format(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "number_format", args);
    const num = try p.number(0, "num");
    const dec: i64 = if (p.has(1)) try p.long(1, "decimals") else 0;
    const dec_point = (try p.strOrNull(2, "decimal_separator")) orelse ".";
    const thousand_sep = (try p.strOrNull(3, "thousands_separator")) orelse ",";
    switch (num) {
        .int => |i| return numberFormatLong(ctx, i, dec, dec_point, thousand_sep),
        else => {
            const d = num.float;
            // a double of 2^52 or more has no fraction left: format it as
            // the long it is
            if ((d >= 4503599627370496.0 or d <= -4503599627370496.0) and Value.floatFitsInt(d)) {
                return numberFormatLong(ctx, @intFromFloat(d), dec, dec_point, thousand_sep);
            }
            const dec_int: i32 = @intCast(std.math.clamp(dec, std.math.minInt(i32), std.math.maxInt(i32)));
            return numberFormatDouble(ctx, d, dec_int, dec_point, thousand_sep);
        },
    }
}

// the integral digits of `digits` with a separator every three, then the
// rest; the caller writes the sign first
fn appendGrouped(out: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, digits: []const u8, sep: []const u8) !void {
    for (digits, 0..) |c, i| {
        if (i > 0 and (digits.len - i) % 3 == 0) try out.appendSlice(a, sep);
        try out.append(a, c);
    }
}

// _php_math_number_format_ex
fn numberFormatDouble(ctx: *NativeContext, d_in: f64, dec_in: i32, dec_point: []const u8, thousand_sep: []const u8) RuntimeError!NativeResult {
    var d = d_in;
    var is_negative = false;
    if (d < 0) {
        is_negative = true;
        d = -d;
    }
    d = phpRound(d, dec_in, round_half_up);
    const dec: usize = @intCast(@max(0, dec_in));
    // php's "%.*F" caps the precision at NDIG - 2 and prints nan and inf
    // as words
    if (std.math.isNan(d)) return NativeResult.literal("nan");
    if (std.math.isInf(d)) return NativeResult.literal("inf");
    const precision: usize = @min(dec, 318);
    const tmp = try ctx.allocator.alloc(u8, 400 + precision);
    defer ctx.allocator.free(tmp);
    const n: usize = @intCast(snprintf(tmp.ptr, tmp.len, "%.*f", @as(c_int, @intCast(precision)), @abs(d)));
    const printed = tmp[0..n];
    if (is_negative and d == 0) is_negative = false;
    const dp = if (dec > 0) std.mem.indexOfAny(u8, printed, ".,") else null;
    const integral = if (dp) |i| printed[0..i] else printed;
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(ctx.allocator);
    if (is_negative) try out.append(ctx.allocator, '-');
    try appendGrouped(&out, ctx.allocator, integral, thousand_sep);
    if (dec > 0) {
        try out.appendSlice(ctx.allocator, dec_point);
        const frac = if (dp) |i| printed[i + 1 ..] else "";
        try out.appendSlice(ctx.allocator, frac);
        try out.appendNTimes(ctx.allocator, '0', dec - frac.len);
    }
    return NativeResult.copyString(ctx.allocator, out.items);
}

// _php_math_number_format_long
fn numberFormatLong(ctx: *NativeContext, num: i64, dec: i64, dec_point: []const u8, thousand_sep: []const u8) RuntimeError!NativeResult {
    var is_negative = num < 0;
    var tmpnum: u64 = if (num < 0) @as(u64, @intCast(-(num + 1))) + 1 else @intCast(num);
    if (dec < 0) {
        if (dec < -19) {
            tmpnum = 0;
        } else {
            const power = std.math.pow(u64, 10, @intCast(-dec));
            const rest = tmpnum % power;
            tmpnum /= power;
            // php's unsigned arithmetic wraps where the rounded value passes 2^64
            tmpnum = if (rest >= power / 2) tmpnum *% power +% power else tmpnum *% power;
        }
        if (tmpnum == 0) is_negative = false;
    }
    var digits_buf: [24]u8 = undefined;
    const digits = std.fmt.bufPrint(&digits_buf, "{d}", .{tmpnum}) catch unreachable;
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(ctx.allocator);
    if (is_negative) try out.append(ctx.allocator, '-');
    try appendGrouped(&out, ctx.allocator, digits, thousand_sep);
    if (dec > 0) {
        try out.appendSlice(ctx.allocator, dec_point);
        try out.appendNTimes(ctx.allocator, '0', @intCast(dec));
    }
    return NativeResult.copyString(ctx.allocator, out.items);
}

fn longFitsDouble(l: i64) bool {
    const d: f64 = @floatFromInt(l);
    return Value.floatFitsInt(d) and @as(i64, @intFromFloat(d)) == l;
}

// php's min() and max(): the array form through zend_hash_minmax, the list
// form with its int and float fast paths, falling back to zend_compare
fn minmax(ctx: *NativeContext, comptime func: []const u8, args: []const Value, comptime is_max: bool) RuntimeError!NativeResult {
    const better = struct {
        // whether candidate replaces current
        fn f(c: *NativeContext, candidate: Value, current: Value) RuntimeError!bool {
            const r = try c.vm.compareWithStringable(candidate, current);
            return if (is_max) r > 0 else r < 0;
        }
    }.f;
    if (args.len == 1) {
        if (args[0] != .array) {
            const msg = try std.fmt.allocPrint(ctx.allocator, func ++ "(): Argument #1 ($value) must be of type array, {s} given", .{phpTypeName(args[0])});
            defer ctx.allocator.free(msg);
            try ctx.vm.setPendingException("TypeError", msg);
            return error.RuntimeError;
        }
        const arr = args[0].array;
        if (arr.entries.items.len == 0) {
            try ctx.vm.setPendingException("ValueError", func ++ "(): Argument #1 ($value) must contain at least one element");
            return error.RuntimeError;
        }
        const val = struct {
            fn f(e: PhpArray.Entry) Value {
                return if (e.ref) |cell| cell.* else e.value;
            }
        }.f;
        var result = val(arr.entries.items[0]);
        var i: usize = 1;
        while (i < arr.entries.items.len) : (i += 1) {
            const v = val(arr.entries.items[i]);
            // zend_hash_minmax compares the kept value against the next
            const r = try ctx.vm.compareWithStringable(result, v);
            if (if (is_max) r < 0 else r > 0) result = v;
        }
        return NativeResult.share(result);
    }
    if (args.len == 2) {
        // php's frameless two-argument form: a tie keeps the right operand
        // for min and the left one for max
        const lhs = args[0];
        const rhs = args[1];
        const num = struct {
            fn f(v: Value) ?f64 {
                return switch (v) {
                    .float => |d| d,
                    .int => |n| if (longFitsDouble(n)) @floatFromInt(n) else null,
                    else => null,
                };
            }
        }.f;
        const take_lhs = if (lhs == .int and rhs == .int)
            (if (is_max) lhs.int >= rhs.int else lhs.int < rhs.int)
        else if ((lhs == .float or rhs == .float) and num(lhs) != null and num(rhs) != null)
            (if (is_max) num(lhs).? >= num(rhs).? else num(lhs).? < num(rhs).?)
        else blk: {
            const r = try ctx.vm.compareWithStringable(lhs, rhs);
            break :blk if (is_max) r >= 0 else r < 0;
        };
        return NativeResult.share(if (take_lhs) lhs else rhs);
    }
    var best: usize = 0;
    var i: usize = 1;
    if (args[0] == .int) {
        var lval = args[0].int;
        while (i < args.len) : (i += 1) {
            if (args[i] == .int) {
                if (if (is_max) lval < args[i].int else lval > args[i].int) {
                    lval = args[i].int;
                    best = i;
                }
            } else if (args[i] == .float and longFitsDouble(lval)) {
                break;
            } else {
                // generic from here on
                while (i < args.len) : (i += 1) {
                    if (try better(ctx, args[i], args[best])) best = i;
                }
                return NativeResult.share(args[best]);
            }
        }
        if (i == args.len) return NativeResult.scalar(.{ .int = lval });
    }
    if (args[best] == .int or args[best] == .float) {
        var dval: f64 = if (args[best] == .int) @floatFromInt(args[best].int) else args[best].float;
        while (i < args.len) : (i += 1) {
            const d: f64 = switch (args[i]) {
                .float => |f| f,
                .int => |n| if (longFitsDouble(n)) @floatFromInt(n) else break,
                else => break,
            };
            if (if (is_max) dval < d else dval > d) {
                dval = d;
                best = i;
            }
        }
    }
    while (i < args.len) : (i += 1) {
        if (try better(ctx, args[i], args[best])) best = i;
    }
    return NativeResult.share(args[best]);
}

fn native_min(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return minmax(ctx, "min", args, false);
}

fn native_max(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return minmax(ctx, "max", args, true);
}
