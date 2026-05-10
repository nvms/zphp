const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
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
    .{ "log2", native_log2 },
    .{ "log10", native_log10 },
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
    .{ "deg2rad", native_deg2rad },
    .{ "rad2deg", native_rad2deg },
    .{ "hypot", native_hypot },
    .{ "is_finite", native_is_finite },
    .{ "is_infinite", native_is_infinite },
    .{ "is_nan", native_is_nan },
    .{ "mt_rand", native_rand },
    .{ "mt_srand", native_srand_noop },
    .{ "srand", native_srand_noop },
    .{ "mt_getrandmax", native_getrandmax },
    .{ "getrandmax", native_getrandmax },
    .{ "fpow", native_fpow },
    .{ "fdiv", native_fdiv },
};

fn native_abs(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
    return switch (args[0]) {
        .int => |i| if (i == std.math.minInt(i64))
            .{ .float = -@as(f64, @floatFromInt(i)) }
        else
            .{ .int = if (i < 0) -i else i },
        .float => |f| .{ .float = @abs(f) },
        .string => |s| blk: {
            // numeric strings with '.' or exponent should use float path
            const has_float_marker = std.mem.indexOfAny(u8, s, ".eE") != null;
            if (has_float_marker) break :blk Value{ .float = @abs(Value.toFloat(args[0])) };
            const i = Value.toInt(args[0]);
            if (i == std.math.minInt(i64)) break :blk Value{ .float = -@as(f64, @floatFromInt(i)) };
            break :blk Value{ .int = if (i < 0) -i else i };
        },
        else => blk: {
            const i = Value.toInt(args[0]);
            if (i == std.math.minInt(i64)) break :blk Value{ .float = -@as(f64, @floatFromInt(i)) };
            break :blk Value{ .int = if (i < 0) -i else i };
        },
    };
}

fn native_floor(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 0.0 };
    return .{ .float = @floor(Value.toFloat(args[0])) };
}

fn native_ceil(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 0.0 };
    return .{ .float = @ceil(Value.toFloat(args[0])) };
}

fn native_round(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 0.0 };
    const v = Value.toFloat(args[0]);
    const precision: i64 = if (args.len >= 2) Value.toInt(args[1]) else 0;
    const mode: i64 = if (args.len >= 3) Value.toInt(args[2]) else 1; // PHP_ROUND_HALF_UP=1
    const factor = std.math.pow(f64, 10.0, @floatFromInt(precision));
    const scaled = v * factor;
    const rounded = roundWithMode(scaled, mode);
    return .{ .float = rounded / factor };
}

fn roundWithMode(v: f64, mode: i64) f64 {
    if (std.math.isNan(v) or std.math.isInf(v)) return v;
    const sign: f64 = if (v < 0) -1.0 else 1.0;
    const av = @abs(v);
    const floor = @floor(av);
    const frac = av - floor;
    // tolerance for half: use a tiny epsilon for FP noise on values like 1.35*10
    const eps: f64 = 1e-9;
    const is_half = @abs(frac - 0.5) < eps;
    var out: f64 = undefined;
    if (is_half) {
        switch (mode) {
            1 => out = floor + 1.0, // HALF_UP (away from zero)
            2 => out = floor, // HALF_DOWN (toward zero)
            3 => { // HALF_EVEN
                const fi: i64 = @intFromFloat(floor);
                out = if (@mod(fi, 2) == 0) floor else floor + 1.0;
            },
            4 => { // HALF_ODD
                const fi: i64 = @intFromFloat(floor);
                out = if (@mod(fi, 2) == 0) floor + 1.0 else floor;
            },
            else => out = floor + 1.0,
        }
    } else if (frac > 0.5) {
        out = floor + 1.0;
    } else {
        out = floor;
    }
    return out * sign;
}

fn native_min(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .null;
    if (args.len == 1 and args[0] == .array) {
        const arr = args[0].array;
        if (arr.entries.items.len == 0) {
            try ctx.vm.setPendingException("ValueError", "min(): Argument #1 ($value) must contain at least one element");
            return error.RuntimeError;
        }
        var result = arr.entries.items[0].value;
        for (arr.entries.items[1..]) |e| {
            if (Value.lessThan(e.value, result)) result = e.value;
        }
        return result;
    }
    var result = args[0];
    for (args[1..]) |a| {
        if (Value.lessThan(a, result)) result = a;
    }
    return result;
}

fn native_max(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .null;
    if (args.len == 1 and args[0] == .array) {
        const arr = args[0].array;
        if (arr.entries.items.len == 0) {
            try ctx.vm.setPendingException("ValueError", "max(): Argument #1 ($value) must contain at least one element");
            return error.RuntimeError;
        }
        var result = arr.entries.items[0].value;
        for (arr.entries.items[1..]) |e| {
            if (Value.lessThan(result, e.value)) result = e.value;
        }
        return result;
    }
    var result = args[0];
    for (args[1..]) |a| {
        if (Value.lessThan(result, a)) result = a;
    }
    return result;
}

fn native_lcg_value(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .float = std.crypto.random.float(f64) };
}

fn native_srand_noop(_: *NativeContext, _: []const Value) RuntimeError!Value {
    // we use crypto.random which is not seedable; accept the call as a no-op
    return .null;
}

fn native_getrandmax(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = 2147483647 };
}

fn native_rand(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const lo: i64 = if (args.len >= 1) Value.toInt(args[0]) else 0;
    const hi: i64 = if (args.len >= 2) Value.toInt(args[1]) else 2147483647;
    if (lo >= hi) return .{ .int = lo };
    const range: u64 = @intCast(hi - lo + 1);
    const r = std.crypto.random.intRangeAtMost(u64, 0, range - 1);
    return .{ .int = lo + @as(i64, @intCast(r)) };
}

fn native_pow(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .int = 0 };
    return Value.power(args[0], args[1]);
}

fn native_sqrt(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 0.0 };
    return .{ .float = @sqrt(Value.toFloat(args[0])) };
}

fn native_log(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 0.0 };
    const v = Value.toFloat(args[0]);
    if (args.len >= 2) {
        const base = Value.toFloat(args[1]);
        return .{ .float = @log(v) / @log(base) };
    }
    return .{ .float = @log(v) };
}

fn native_log2(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 0.0 };
    return .{ .float = std.math.log2(Value.toFloat(args[0])) };
}

fn native_log10(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 0.0 };
    return .{ .float = std.math.log10(Value.toFloat(args[0])) };
}

fn native_exp(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 1.0 };
    return .{ .float = @exp(Value.toFloat(args[0])) };
}

fn native_pi(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .float = std.math.pi };
}

fn native_fmod(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .float = 0.0 };
    const x = Value.toFloat(args[0]);
    const y = Value.toFloat(args[1]);
    if (y == 0.0) return .{ .float = std.math.nan(f64) };
    return .{ .float = @rem(x, y) };
}

fn native_intdiv(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .int = 0 };
    const a = Value.toInt(args[0]);
    const b = Value.toInt(args[1]);
    if (b == 0) {
        try ctx.vm.setPendingException("DivisionByZeroError", "Division by zero");
        return error.RuntimeError;
    }
    if (a == std.math.minInt(i64) and b == -1) {
        try ctx.vm.setPendingException("ArithmeticError", "Division of PHP_INT_MIN by -1 is not an integer");
        return error.RuntimeError;
    }
    return .{ .int = @divTrunc(a, b) };
}

fn native_base_convert(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3) return .{ .string = "0" };
    var num_str = if (args[0] == .string) args[0].string else return Value{ .string = "0" };
    const from_base: u8 = @intCast(@max(2, @min(36, Value.toInt(args[1]))));
    const to_base: u8 = @intCast(@max(2, @min(36, Value.toInt(args[2]))));
    if (num_str.len > 0 and (num_str[0] == '-' or num_str[0] == '+')) num_str = num_str[1..];
    const val = std.fmt.parseInt(u64, num_str, from_base) catch return Value{ .string = "0" };
    const digits = "0123456789abcdefghijklmnopqrstuvwxyz";
    var buf: [65]u8 = undefined;
    var pos: usize = buf.len;
    var v = val;
    if (v == 0) {
        pos -= 1;
        buf[pos] = '0';
    } else {
        while (v > 0) {
            pos -= 1;
            buf[pos] = digits[@intCast(v % to_base)];
            v /= to_base;
        }
    }
    return .{ .string = try ctx.createString(buf[pos..]) };
}

// parses digits in `base`, returning int if it fits in i64 and float on
// overflow (matching PHP's bindec/octdec/hexdec behavior). non-digit chars
// in PHP's accepted set are skipped silently.
fn baseDecimal(s: []const u8, base: u8) Value {
    var int_val: u64 = 0;
    var float_val: f64 = 0;
    var overflowed = false;
    for (s) |c| {
        const d: ?u8 = switch (base) {
            2 => if (c == '0' or c == '1') c - '0' else null,
            8 => if (c >= '0' and c <= '7') c - '0' else null,
            16 => if (c >= '0' and c <= '9') c - '0'
                else if (c >= 'a' and c <= 'f') 10 + (c - 'a')
                else if (c >= 'A' and c <= 'F') 10 + (c - 'A')
                else null,
            else => null,
        };
        if (d == null) continue;
        if (!overflowed) {
            const m = @mulWithOverflow(int_val, base);
            const a = if (m[1] == 0) @addWithOverflow(m[0], d.?) else .{ @as(u64, 0), @as(u1, 1) };
            if (m[1] != 0 or a[1] != 0) {
                overflowed = true;
                float_val = @floatFromInt(int_val);
            } else {
                int_val = a[0];
            }
        }
        if (overflowed) {
            float_val = float_val * @as(f64, @floatFromInt(base)) + @as(f64, @floatFromInt(d.?));
        }
    }
    if (overflowed) return .{ .float = float_val };
    // i64 cast: values up to 2^63-1 stay int, 2^63..2^64-1 also stay int
    // (PHP treats them as negative i64 for signed int max range), but
    // PHP returns float for values > PHP_INT_MAX
    if (int_val > std.math.maxInt(i64)) return .{ .float = @floatFromInt(int_val) };
    return .{ .int = @intCast(int_val) };
}

fn native_bindec(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
    const s = if (args[0] == .string) args[0].string else return Value{ .int = 0 };
    return baseDecimal(s, 2);
}

fn native_octdec(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
    const s = if (args[0] == .string) args[0].string else return Value{ .int = 0 };
    return baseDecimal(s, 8);
}

fn native_hexdec(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
    const s = if (args[0] == .string) args[0].string else return Value{ .int = 0 };
    return baseDecimal(s, 16);
}

fn native_decbin(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "0" };
    const val = Value.toInt(args[0]);
    var buf: [65]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{b}", .{@as(u64, @bitCast(val))}) catch return Value{ .string = "0" };
    return .{ .string = try ctx.createString(s) };
}

fn native_decoct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "0" };
    const val = Value.toInt(args[0]);
    var buf: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{o}", .{@as(u64, @bitCast(val))}) catch return Value{ .string = "0" };
    return .{ .string = try ctx.createString(s) };
}

fn native_dechex(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "0" };
    const val = Value.toInt(args[0]);
    var buf: [17]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{x}", .{@as(u64, @bitCast(val))}) catch return Value{ .string = "0" };
    return .{ .string = try ctx.createString(s) };
}

fn native_sin(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 0.0 };
    return .{ .float = @sin(Value.toFloat(args[0])) };
}

fn native_cos(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 0.0 };
    return .{ .float = @cos(Value.toFloat(args[0])) };
}

fn native_tan(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 0.0 };
    return .{ .float = @tan(Value.toFloat(args[0])) };
}

fn native_asin(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 0.0 };
    return .{ .float = std.math.asin(Value.toFloat(args[0])) };
}

fn native_acos(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 0.0 };
    return .{ .float = std.math.acos(Value.toFloat(args[0])) };
}

fn native_atan(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 0.0 };
    return .{ .float = std.math.atan(Value.toFloat(args[0])) };
}

fn native_atan2(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .float = 0.0 };
    return .{ .float = std.math.atan2(Value.toFloat(args[0]), Value.toFloat(args[1])) };
}

fn native_sinh(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 0.0 };
    const x = Value.toFloat(args[0]);
    return .{ .float = (@exp(x) - @exp(-x)) / 2.0 };
}

fn native_cosh(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 0.0 };
    const x = Value.toFloat(args[0]);
    return .{ .float = (@exp(x) + @exp(-x)) / 2.0 };
}

fn native_tanh(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 0.0 };
    const x = Value.toFloat(args[0]);
    const ex = @exp(x);
    const enx = @exp(-x);
    return .{ .float = (ex - enx) / (ex + enx) };
}

fn native_deg2rad(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 0.0 };
    return .{ .float = Value.toFloat(args[0]) * (std.math.pi / 180.0) };
}

fn native_rad2deg(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 0.0 };
    return .{ .float = Value.toFloat(args[0]) * (180.0 / std.math.pi) };
}

fn native_hypot(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .float = 0.0 };
    const x = Value.toFloat(args[0]);
    const y = Value.toFloat(args[1]);
    return .{ .float = @sqrt(x * x + y * y) };
}

fn native_is_finite(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = true };
    return .{ .bool = switch (args[0]) {
        .float => |f| !std.math.isNan(f) and !std.math.isInf(f),
        .int => true,
        else => true,
    } };
}

fn native_is_infinite(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    return .{ .bool = switch (args[0]) {
        .float => |f| std.math.isInf(f),
        else => false,
    } };
}

fn native_is_nan(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    return .{ .bool = switch (args[0]) {
        .float => |f| std.math.isNan(f),
        else => false,
    } };
}

fn native_fpow(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .float = 0.0 };
    return .{ .float = std.math.pow(f64, Value.toFloat(args[0]), Value.toFloat(args[1])) };
}

fn native_fdiv(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .float = 0.0 };
    const num = Value.toFloat(args[0]);
    const den = Value.toFloat(args[1]);
    return .{ .float = num / den };
}
