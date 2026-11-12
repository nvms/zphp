// sprintf and friends, ported from php's ext/standard/formatted_print.c and
// the float conversions it uses from main/snprintf.c and Zend/zend_strtod.c
const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const RuntimeError = error{ RuntimeError, OutOfMemory };
const phpTypeName = @import("types.zig").phpTypeName;
const nativeCast = @import("../runtime/value.zig").nativeCast;

extern "c" fn snprintf(buf: [*c]u8, size: usize, fmt: [*c]const u8, ...) c_int;

pub const entries = .{
    .{ "sprintf", native_sprintf },
    .{ "vsprintf", native_vsprintf },
    .{ "printf", native_printf },
    .{ "vprintf", native_vprintf },
    .{ "fprintf", native_fprintf },
    .{ "vfprintf", native_vfprintf },
};

const int_max: i64 = std.math.maxInt(i32);
const float_precision = 6;
const max_float_precision = 53;
const num_buf_size = 500;
const e_warning = 2;
const e_notice = 8;
const e_deprecated = 8192;

const Align = enum { left, right };

const Out = std.ArrayListUnmanaged(u8);

// the format string reads as if nul terminated, the way php's C loop sees it
inline fn at(format: []const u8, i: usize) u8 {
    return if (i < format.len) format[i] else 0;
}

inline fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

inline fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}

// one call's formatting. a conversion that throws (a __toString, an error
// handler) leaves the exception pending in php while the loop carries on:
// later __toString calls and user error handlers don't run, and an error
// thrown after that gets the pending exception as its previous one
const State = struct {
    ctx: *NativeContext,
    pending: ?Value = null,

    fn warn(self: *State, level: i64, msg: []const u8) RuntimeError!void {
        const vm = self.ctx.vm;
        // zend_call_function won't run the handler then, and the error is lost
        if (self.pending != null and vm.user_error_handler != null and (vm.user_error_handler_mask & level) != 0) return;
        vm.raiseError(level, msg) catch |err| return self.absorb(err);
    }

    // keeps an exception a conversion raised and carries on
    fn absorb(self: *State, err: RuntimeError) RuntimeError!void {
        const vm = self.ctx.vm;
        if (err != error.RuntimeError or vm.uncatchable_fatal or vm.exit_requested) return err;
        const exc = vm.takePending() orelse return err;
        if (self.pending) |old| {
            if (exc == .object and old == .object) _ = try vm.chainPrevious(exc.object, old.object);
            vm.stackRelease(old);
        }
        self.pending = exc;
    }

    fn fail(self: *State, class: []const u8, comptime fmt: []const u8, args: anytype) RuntimeError {
        const vm = self.ctx.vm;
        throw(self.ctx, class, fmt, args) catch {};
        if (self.pending) |old| {
            self.pending = null;
            defer vm.stackRelease(old);
            if (vm.pending_exception) |exc| if (exc == .object and old == .object) {
                _ = try vm.chainPrevious(exc.object, old.object);
            };
        }
        return error.RuntimeError;
    }

    fn valueError(self: *State, comptime fmt: []const u8, args: anytype) RuntimeError {
        return self.fail("ValueError", fmt, args);
    }

    fn release(self: *State) void {
        if (self.pending) |p| self.ctx.vm.stackRelease(p);
        self.pending = null;
    }
};

fn throw(ctx: *NativeContext, class: []const u8, comptime fmt: []const u8, args: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException(class, msg);
    return error.RuntimeError;
}

// php_sprintf_getnumber: strtol over the digits at i, -1 once it reaches INT_MAX
fn getNumber(format: []const u8, i: *usize) i64 {
    var n: i64 = 0;
    while (i.* < format.len and isDigit(format[i.*])) : (i.* += 1) {
        if (n < int_max) n = n * 10 + (format[i.*] - '0');
    }
    return if (n >= int_max) -1 else n;
}

// php_sprintf_get_argnum: an explicit "n$" argument number, or null for the next one
fn getArgnum(st: *State, format: []const u8, i: *usize) RuntimeError!?usize {
    var t = i.*;
    while (t < format.len and isDigit(format[t])) t += 1;
    if (at(format, t) != '$') return null;
    const num = getNumber(format, i);
    if (num <= 0) return st.valueError("Argument number specifier must be greater than zero and less than {d}", .{int_max});
    i.* += 1;
    return @intCast(num - 1);
}

fn appendString(ctx: *NativeContext, out: *Out, add_in: []const u8, min_width: usize, max_width: usize, padding: u8, alignment: Align, neg: bool, expprec: bool, always_sign: bool) RuntimeError!void {
    const a = ctx.allocator;
    var add = add_in;
    var copy_len = if (expprec) @min(max_width, add.len) else add.len;
    const npad = if (min_width < copy_len) 0 else min_width - copy_len;
    const m_width = @max(min_width, copy_len);
    // php's buffer positions are ints
    if (m_width > @as(usize, @intCast(int_max)) -% out.items.len -% 1) {
        var buf: [96]u8 = undefined;
        return ctx.vm.raiseFatal(std.fmt.bufPrint(&buf, "Field width {d} is too long", .{m_width}) catch unreachable);
    }
    try out.ensureUnusedCapacity(a, m_width);
    if (alignment == .right) {
        if ((neg or always_sign) and padding == '0') {
            out.appendAssumeCapacity(if (neg) '-' else '+');
            add = add[1..];
            copy_len -= 1;
        }
        out.appendNTimesAssumeCapacity(padding, npad);
    }
    out.appendSliceAssumeCapacity(add[0..copy_len]);
    if (alignment == .left) out.appendNTimesAssumeCapacity(padding, npad);
}

fn appendInt(ctx: *NativeContext, out: *Out, number: i64, width: usize, padding_in: u8, alignment: Align, always_sign: bool) RuntimeError!void {
    var numbuf: [24]u8 = undefined;
    var i: usize = numbuf.len;
    const neg = number < 0;
    var magn: u64 = @abs(number);
    // can't right-pad 0's on integers
    const padding = if (alignment == .left and padding_in == '0') ' ' else padding_in;
    while (true) {
        i -= 1;
        numbuf[i] = @intCast('0' + magn % 10);
        magn /= 10;
        if (magn == 0) break;
    }
    if (neg) {
        i -= 1;
        numbuf[i] = '-';
    } else if (always_sign) {
        i -= 1;
        numbuf[i] = '+';
    }
    // the common case: nothing to pad
    if (width <= numbuf.len - i) return out.appendSlice(ctx.allocator, numbuf[i..]);
    return appendString(ctx, out, numbuf[i..], width, 0, padding, alignment, neg, false, always_sign);
}

fn appendUint(ctx: *NativeContext, out: *Out, number: u64, width: usize, padding_in: u8, alignment: Align) RuntimeError!void {
    var numbuf: [24]u8 = undefined;
    var i: usize = numbuf.len;
    var magn = number;
    const padding = if (alignment == .left and padding_in == '0') ' ' else padding_in;
    while (true) {
        i -= 1;
        numbuf[i] = @intCast('0' + magn % 10);
        magn /= 10;
        if (magn == 0) break;
    }
    return appendString(ctx, out, numbuf[i..], width, 0, padding, alignment, false, false, false);
}

fn append2n(ctx: *NativeContext, out: *Out, number: i64, width: usize, padding: u8, alignment: Align, comptime n: u6, chartable: *const [16]u8, expprec: bool) RuntimeError!void {
    var numbuf: [64]u8 = undefined;
    var i: usize = numbuf.len;
    var num: u64 = @bitCast(number);
    const andbits: u64 = (1 << n) - 1;
    while (true) {
        i -= 1;
        numbuf[i] = chartable[@intCast(num & andbits)];
        num >>= n;
        if (num == 0) break;
    }
    // a precision makes php copy none of the digits
    return appendString(ctx, out, numbuf[i..], width, 0, padding, alignment, false, expprec, false);
}

fn appendDouble(st: *State, out: *Out, number: f64, width: usize, padding: u8, alignment: Align, precision_in: i64, adjust_precision: bool, fmt: u8, always_sign: bool) RuntimeError!void {
    var precision = precision_in;
    if (!adjust_precision) {
        precision = float_precision;
    } else if (precision > max_float_precision) {
        var buf: [160]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "{s}(): Requested precision of {d} digits was truncated to PHP maximum of {d} digits", .{ st.ctx.call_name orelse "sprintf", precision, max_float_precision }) catch unreachable;
        try st.warn(e_notice, msg);
        precision = max_float_precision;
    }

    if (std.math.isNan(number)) {
        return appendString(st.ctx, out, "NaN", 3, 0, padding, alignment, false, false, always_sign);
    }
    if (std.math.isInf(number)) {
        const is_negative = number < 0;
        const str: []const u8 = if (is_negative) "-INF" else "INF";
        return appendString(st.ctx, out, str, str.len, 0, padding, alignment, is_negative, false, always_sign);
    }

    var num_buf: [num_buf_size]u8 = undefined;
    var s: []const u8 = undefined;
    var is_negative = false;
    switch (fmt) {
        'e', 'E', 'f', 'F' => {
            const body = convFp(if (fmt == 'f') 'F' else fmt, number, @intCast(precision), &is_negative, num_buf[1..]);
            if (is_negative) {
                num_buf[0] = '-';
                s = num_buf[0 .. body.len + 1];
            } else if (always_sign) {
                num_buf[0] = '+';
                s = num_buf[0 .. body.len + 1];
            } else s = body;
        },
        else => {
            if (precision == 0) precision = 1;
            const exp_char: u8 = if (fmt == 'G' or fmt == 'H') 'E' else 'e';
            const body = gcvt(number, @intCast(precision), '.', exp_char, num_buf[1..]);
            if (body[0] == '-') {
                is_negative = true;
                s = body;
            } else if (always_sign) {
                num_buf[0] = '+';
                s = num_buf[0 .. body.len + 1];
            } else s = body;
        },
    }
    return appendString(st.ctx, out, s, width, 0, padding, alignment, is_negative, false, always_sign);
}

// php_conv_fp for 'F', 'e' and 'E': the digits of a finite number without its
// sign. c's printf produces them exactly and rounds ties to even, which is
// what zend_dtoa's modes 2 and 3 do
fn convFp(format: u8, num: f64, precision: usize, is_negative: *bool, buf: []u8) []const u8 {
    // zero, negative or not, prints unsigned
    is_negative.* = num < 0;
    const v = @abs(num);
    if (format == 'F') {
        const n = snprintf(buf.ptr, buf.len, "%.*f", @as(c_int, @intCast(precision)), v);
        return buf[0..@intCast(n)];
    }
    var tmp: [96]u8 = undefined;
    const n: usize = @intCast(snprintf(&tmp, tmp.len, "%.*e", @as(c_int, @intCast(precision)), v));
    const e_at = std.mem.lastIndexOfScalar(u8, tmp[0..n], 'e').?;
    @memcpy(buf[0..e_at], tmp[0..e_at]);
    var len = e_at;
    buf[len] = format;
    len += 1;
    const exp = std.fmt.parseInt(i32, tmp[e_at + 1 .. n], 10) catch 0;
    if (exp == 0) {
        buf[len] = '+';
        buf[len + 1] = '0';
        return buf[0 .. len + 2];
    }
    buf[len] = if (exp < 0) '-' else '+';
    len += 1;
    const digits = std.fmt.bufPrint(buf[len..], "{d}", .{@abs(exp)}) catch unreachable;
    return buf[0 .. len + digits.len];
}

const Dtoa = struct {
    buf: [832]u8 = undefined,
    len: usize = 0,
    decpt: i32 = 0,
    sign: bool = false,

    fn digits(self: *const Dtoa) []const u8 {
        return self.buf[0..self.len];
    }
};

// zend_dtoa mode 2 (ndigit significant digits, trailing zeros dropped) or,
// for ndigit < 0, mode 0 (the shortest digits that round trip)
fn dtoa(value: f64, ndigit: i32, d: *Dtoa) void {
    d.sign = std.math.signbit(value);
    const v = @abs(value);
    if (v == 0) {
        d.buf[0] = '0';
        d.len = 1;
        d.decpt = 1;
        return;
    }
    // zend_dtoa's path for integers below 1e15 rounds an exact tie down
    // without dropping the zeros it already wrote (6005e9 to 3 digits is 600)
    if (ndigit > 0 and v < 1e15 and v == @trunc(v)) {
        const n: u64 = @intFromFloat(v);
        var nd: usize = 1;
        var p: u64 = 10;
        while (p <= n) : (p *= 10) nd += 1;
        const want: usize = @intCast(ndigit);
        if (want < nd) {
            const divisor = std.math.pow(u64, 10, nd - want);
            const q = n / divisor;
            if (2 * (n % divisor) == divisor and q % 2 == 0) {
                const s = std.fmt.bufPrint(&d.buf, "{d}", .{q}) catch unreachable;
                d.len = s.len;
                d.decpt = @intCast(nd);
                return;
            }
        }
    }
    var tmp: [832]u8 = undefined;
    if (ndigit > 0 and roundShortest(v, @intCast(ndigit), d)) return;
    const sci: []const u8 = if (ndigit < 0)
        std.fmt.float.render(&tmp, v, .{ .mode = .scientific }) catch unreachable
    else
        tmp[0..@intCast(snprintf(&tmp, tmp.len, "%.*e", @as(c_int, @min(ndigit, 800) - 1), v))];
    const e_at = std.mem.lastIndexOfScalar(u8, sci, 'e').?;
    d.len = 0;
    for (sci[0..e_at]) |c| if (c != '.') {
        d.buf[d.len] = c;
        d.len += 1;
    };
    while (d.len > 1 and d.buf[d.len - 1] == '0') d.len -= 1;
    d.decpt = (std.fmt.parseInt(i32, sci[e_at + 1 ..], 10) catch 0) + 1;
}

// mode 2 from the shortest round-trip digits, which are much cheaper than
// snprintf's exact expansion. they differ from the exact value by less than
// half an ulp, a few units at the 17th digit, so rounding them gives the
// exact rounding unless the dropped digits are that close to a tie; then
// false, and the caller expands exactly
fn roundShortest(v: f64, ndigit: usize, d: *Dtoa) bool {
    // a subnormal's shortest digits, and 16 or 17 requested, can be off by
    // more than the margin below allows
    if (ndigit > 15 or v < std.math.floatMin(f64)) return false;
    var tmp: [64]u8 = undefined;
    const sci = std.fmt.float.render(&tmp, v, .{ .mode = .scientific }) catch return false;
    const e_at = std.mem.lastIndexOfScalar(u8, sci, 'e') orelse return false;
    var digits: [32]u8 = undefined;
    var len: usize = 0;
    for (sci[0..e_at]) |c| if (c != '.') {
        if (len == digits.len) return false;
        digits[len] = c;
        len += 1;
    };
    var decpt = (std.fmt.parseInt(i32, sci[e_at + 1 ..], 10) catch return false) + 1;
    if (len > ndigit) {
        // the dropped digits against half a unit of the last kept one, both
        // scaled to the 17th significant digit
        const dropped = digits[ndigit..len];
        if (dropped.len > 17) return false;
        var tail: u64 = 0;
        for (dropped) |c| tail = tail * 10 + (c - '0');
        const scale = std.math.pow(u64, 10, 17 - @min(17, len));
        const half = 5 * std.math.pow(u64, 10, dropped.len - 1) * scale;
        const t = tail * scale;
        // a whole ulp in units of the 17th significant digit, plus one
        const ulp = std.math.nextAfter(f64, v, std.math.inf(f64)) - v;
        const unit = std.math.pow(f64, 10, @as(f64, @floatFromInt(decpt - 17)));
        // the largest double's next neighbour is infinity
        const units = ulp / unit;
        if (!std.math.isFinite(units) or units > 1e6) return false;
        const margin: u64 = @as(u64, @intFromFloat(@ceil(units))) + 1;
        if (t + margin >= half and t <= half + margin) return false;
        len = ndigit;
        if (t > half) {
            var i = len;
            while (i > 0) {
                i -= 1;
                if (digits[i] == '9') {
                    digits[i] = '0';
                    if (i == 0) {
                        digits[0] = '1';
                        len = 1;
                        decpt += 1;
                    }
                } else {
                    digits[i] += 1;
                    break;
                }
            }
        }
    }
    while (len > 1 and digits[len - 1] == '0') len -= 1;
    @memcpy(d.buf[0..len], digits[0..len]);
    d.len = len;
    d.decpt = decpt;
    return true;
}

// zend_gcvt: %g style output, in buf
pub fn gcvt(value: f64, ndigit_in: i32, dec_point: u8, exponent: u8, buf: []u8) []const u8 {
    var ndigit = ndigit_in;
    const mode0 = ndigit < 0;
    if (mode0) ndigit = 17;
    if (std.math.isNan(value) or std.math.isInf(value)) {
        const full: []const u8 = if (std.math.isNan(value)) "NAN" else if (value < 0) "-INF" else "INF";
        // php writes it with snprintf into ndigit + 1 bytes
        const n = @min(full.len, @as(usize, @intCast(ndigit)));
        @memcpy(buf[0..n], full[0..n]);
        return buf[0..n];
    }
    var d: Dtoa = .{};
    // zend_dtoa takes 0 digits in mode 2 as 1; the format below still
    // compares against 0
    dtoa(value, if (mode0) -1 else @max(ndigit, 1), &d);
    const digits = d.digits();
    var decpt = d.decpt;
    var dst: usize = 0;
    if (d.sign) {
        buf[0] = '-';
        dst = 1;
    }
    if ((decpt >= 0 and decpt > ndigit) or decpt < -3) {
        // exponential format (e.g. 1.2345e+13)
        decpt -= 1;
        const neg_exp = decpt < 0;
        if (neg_exp) decpt = -decpt;
        buf[dst] = digits[0];
        buf[dst + 1] = dec_point;
        dst += 2;
        if (digits.len == 1) {
            buf[dst] = '0';
            dst += 1;
        } else {
            @memcpy(buf[dst .. dst + digits.len - 1], digits[1..]);
            dst += digits.len - 1;
        }
        buf[dst] = exponent;
        buf[dst + 1] = if (neg_exp) '-' else '+';
        dst += 2;
        const e = std.fmt.bufPrint(buf[dst..], "{d}", .{decpt}) catch unreachable;
        dst += e.len;
    } else if (decpt < 0) {
        // standard format 0.
        buf[dst] = '0';
        buf[dst + 1] = dec_point;
        dst += 2;
        while (decpt < 0) : (decpt += 1) {
            buf[dst] = '0';
            dst += 1;
        }
        @memcpy(buf[dst .. dst + digits.len], digits);
        dst += digits.len;
    } else {
        // standard format
        const ip: usize = @intCast(decpt);
        var src: usize = 0;
        for (0..ip) |_| {
            if (src < digits.len) {
                buf[dst] = digits[src];
                src += 1;
            } else buf[dst] = '0';
            dst += 1;
        }
        if (src < digits.len) {
            if (src == 0) {
                buf[dst] = '0';
                dst += 1;
            }
            buf[dst] = dec_point;
            dst += 1;
            @memcpy(buf[dst .. dst + digits.len - ip], digits[ip..]);
            dst += digits.len - ip;
        }
    }
    return buf[0..dst];
}

// zval conversions, with the warnings php gives for them

fn warnFloatToInt(st: *State, f: f64) RuntimeError!void {
    var fbuf: [64]u8 = undefined;
    var buf: [128]u8 = undefined;
    const shown: []const u8 = if (std.math.isNan(f)) "NAN" else if (std.math.isInf(f)) (if (f < 0) "-INF" else "INF") else gcvt(f, -1, '.', 'E', &fbuf);
    try st.warn(e_warning, std.fmt.bufPrint(&buf, "The float {s} is not representable as an int, cast occurred", .{shown}) catch unreachable);
}

fn warnObject(st: *State, class: []const u8, comptime target: []const u8) RuntimeError!void {
    const msg = try std.fmt.allocPrint(st.ctx.allocator, "Object of class {s} could not be converted to " ++ target, .{class});
    defer st.ctx.allocator.free(msg);
    try st.warn(e_warning, msg);
}

inline fn isSpace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == 0x0b or c == 0x0c;
}

// the numeric prefix of s: leading whitespace, a sign, digits with an
// optional fraction and exponent. int_like when there is no fraction or exponent
const NumericPrefix = struct { text: []const u8, int_like: bool };

fn numericPrefix(s: []const u8) ?NumericPrefix {
    var i: usize = 0;
    while (i < s.len and isSpace(s[i])) i += 1;
    const start = i;
    if (i < s.len and (s[i] == '-' or s[i] == '+')) i += 1;
    var digits = false;
    while (i < s.len and isDigit(s[i])) : (i += 1) digits = true;
    var int_like = true;
    if (i < s.len and s[i] == '.') {
        int_like = false;
        i += 1;
        while (i < s.len and isDigit(s[i])) : (i += 1) digits = true;
    }
    if (!digits) return null;
    if (i < s.len and (s[i] == 'e' or s[i] == 'E')) {
        var j = i + 1;
        if (j < s.len and (s[j] == '-' or s[j] == '+')) j += 1;
        if (j < s.len and isDigit(s[j])) {
            int_like = false;
            while (j < s.len and isDigit(s[j])) j += 1;
            i = j;
        }
    }
    return .{ .text = s[start..i], .int_like = int_like };
}

fn parsePrefixFloat(text: []const u8) f64 {
    return std.fmt.parseFloat(f64, text) catch 0;
}

fn stringToLong(s: []const u8) i64 {
    const p = numericPrefix(s) orelse return 0;
    if (p.int_like) {
        if (std.fmt.parseInt(i64, p.text, 10)) |n| return n else |_| {}
    }
    // a float string saturates (zend_dval_to_lval_cap)
    const d = parsePrefixFloat(p.text);
    if (!std.math.isFinite(d)) return 0;
    if (!(d >= -9.2233720368547758e18 and d < 9.2233720368547758e18)) return if (d > 0) std.math.maxInt(i64) else std.math.minInt(i64);
    return @intFromFloat(d);
}

fn stringToDouble(s: []const u8) f64 {
    // zend_strtod: whitespace, sign, then digits; no hex
    const p = numericPrefix(s) orelse return 0;
    return parsePrefixFloat(p.text);
}

fn getLong(st: *State, v: Value) RuntimeError!i64 {
    return switch (v) {
        .int => |i| i,
        .float => |f| {
            if (!std.math.isFinite(f)) {
                try warnFloatToInt(st, f);
                return 0;
            }
            if (!(f >= -9.2233720368547758e18 and f < 9.2233720368547758e18)) try warnFloatToInt(st, f);
            return Value.dvalToLval(f);
        },
        .string => |s| stringToLong(s.bytes()),
        .null, .undef => 0,
        .bool => |b| @intFromBool(b),
        .array => |arr| @intFromBool(arr.entries.items.len > 0),
        .resource => |r| r.id,
        .object => |o| {
            if (nativeCast(o, .int)) |n| return Value.toInt(n);
            try warnObject(st, o.class_name, "int");
            return 1;
        },
        .generator => {
            try warnObject(st, "Generator", "int");
            return 1;
        },
        .fiber => {
            try warnObject(st, "Fiber", "int");
            return 1;
        },
    };
}

fn getDouble(st: *State, v: Value) RuntimeError!f64 {
    return switch (v) {
        .float => |f| f,
        .int => |i| @floatFromInt(i),
        .string => |s| stringToDouble(s.bytes()),
        .null, .undef => 0,
        .bool => |b| if (b) 1 else 0,
        .array => |arr| if (arr.entries.items.len > 0) 1 else 0,
        .resource => |r| @floatFromInt(r.id),
        .object => |o| {
            if (nativeCast(o, .float)) |n| return Value.toFloat(n);
            try warnObject(st, o.class_name, "float");
            return 1;
        },
        .generator => {
            try warnObject(st, "Generator", "float");
            return 1;
        },
        .fiber => {
            try warnObject(st, "Fiber", "float");
            return 1;
        },
    };
}

// zval_get_tmp_string; scratch holds the bytes of numbers
fn getString(st: *State, v: Value, scratch: []u8) RuntimeError![]const u8 {
    return switch (v) {
        .string => |s| s.bytes(),
        .int => |i| std.fmt.bufPrint(scratch, "{d}", .{i}) catch unreachable,
        // php's precision ini, 14 by default
        .float => |f| {
            const precision = @import("../runtime/value.zig").hooks().precision;
            const str = gcvt(f, if (precision == 0) 1 else precision, '.', 'E', scratch);
            if (std.math.isNan(f)) try st.warn(e_warning, "unexpected NAN value was coerced to string");
            return str;
        },
        .null, .undef => "",
        .bool => |b| if (b) "1" else "",
        .array => {
            try st.warn(e_warning, "Array to string conversion");
            return "Array";
        },
        .resource => |r| std.fmt.bufPrint(scratch, "Resource id #{d}", .{r.id}) catch unreachable,
        .object => |o| {
            // with an exception pending, php neither calls __toString nor throws again
            if (st.pending != null) return "";
            return st.ctx.vm.objectToString(o) catch |err| {
                try st.absorb(err);
                return "";
            };
        },
        .generator, .fiber => {
            if (st.pending == null) try st.absorb(throw(st.ctx, "Error", "Object of class {s} could not be converted to string", .{if (v == .generator) "Generator" else "Fiber"}));
            return "";
        },
    };
}

const hexchars = "0123456789abcdef";
const HEXCHARS = "0123456789ABCDEF";

// php_formatted_print. nb_additional_parameters is how many parameters come
// before the values, for the ArgumentCountError, or null when the values come
// from an array (a ValueError instead)
fn formattedPrint(st: *State, out: *Out, format: []const u8, args: []const Value, nb_additional_parameters: ?usize) RuntimeError!void {
    const a = st.ctx.allocator;
    var i: usize = 0;
    var currarg: usize = 0;
    var max_missing_argnum: ?usize = null;

    while (i < format.len) {
        const pct = std.mem.indexOfScalarPos(u8, format, i, '%') orelse {
            try out.appendSlice(a, format[i..]);
            break;
        };
        if (pct != i) try out.appendSlice(a, format[i..pct]);
        i = pct + 1;

        if (at(format, i) == '%') {
            try out.append(a, '%');
            i += 1;
            continue;
        }

        // starting a new format specifier
        var alignment: Align = .right;
        var adjust_precision = false;
        var padding: u8 = ' ';
        var always_sign = false;
        var expprec = false;
        var width: usize = 0;
        var precision: i64 = 0;
        var argnum: ?usize = null;

        if (!isAlpha(at(format, i))) {
            argnum = try getArgnum(st, format, &i);

            // after argnum comes modifiers
            while (true) : (i += 1) {
                const c = at(format, i);
                if (c == ' ' or c == '0') {
                    padding = c;
                } else if (c == '-') {
                    alignment = .left;
                } else if (c == '+') {
                    always_sign = true;
                } else if (c == '\'') {
                    if (format.len - i > 1) {
                        i += 1;
                        padding = format[i];
                    } else return st.valueError("Missing padding character", .{});
                } else break;
            }

            // after modifiers comes width
            if (at(format, i) == '*') {
                i += 1;
                const width_argnum = (try getArgnum(st, format, &i)) orelse blk: {
                    currarg += 1;
                    break :blk currarg - 1;
                };
                if (width_argnum >= args.len) {
                    max_missing_argnum = @max(max_missing_argnum orelse 0, width_argnum);
                    continue;
                }
                const tmp = args[width_argnum];
                if (tmp != .int) return st.valueError("Width must be an integer", .{});
                if (tmp.int < 0 or tmp.int > int_max) return st.valueError("Width must be between 0 and {d}", .{int_max});
                width = @intCast(tmp.int);
            } else if (isDigit(at(format, i))) {
                const w = getNumber(format, &i);
                if (w < 0) return st.valueError("Width must be between 0 and {d}", .{int_max});
                width = @intCast(w);
            }

            // after width and argnum comes precision
            if (at(format, i) == '.') {
                i += 1;
                adjust_precision = true;
                if (at(format, i) == '*') {
                    i += 1;
                    const prec_argnum = (try getArgnum(st, format, &i)) orelse blk: {
                        currarg += 1;
                        break :blk currarg - 1;
                    };
                    if (prec_argnum >= args.len) {
                        max_missing_argnum = @max(max_missing_argnum orelse 0, prec_argnum);
                        continue;
                    }
                    const tmp = args[prec_argnum];
                    if (tmp != .int) return st.valueError("Precision must be an integer", .{});
                    if (tmp.int < -1 or tmp.int > int_max) return st.valueError("Precision must be between -1 and {d}", .{int_max});
                    precision = tmp.int;
                    expprec = true;
                } else if (isDigit(at(format, i))) {
                    precision = getNumber(format, &i);
                    if (precision < 0) return st.valueError("Precision must be between 0 and {d}", .{int_max});
                    expprec = true;
                }
            }
        }

        if (at(format, i) == 'l') i += 1;

        const arg_index = argnum orelse blk: {
            currarg += 1;
            break :blk currarg - 1;
        };
        if (arg_index >= args.len) {
            // php carries on scanning, so the specifier reads as plain text
            max_missing_argnum = @max(max_missing_argnum orelse 0, arg_index);
            continue;
        }

        const spec = at(format, i);
        if (expprec and precision == -1 and spec != 'g' and spec != 'G' and spec != 'h' and spec != 'H') {
            return st.valueError("Precision -1 is only supported for %g, %G, %h and %H", .{});
        }

        const arg = args[arg_index];
        const ctx = st.ctx;
        switch (spec) {
            's' => {
                var scratch: [1100]u8 = undefined;
                const str = try getString(st, arg, &scratch);
                if (width == 0 and !expprec) {
                    try out.appendSlice(a, str);
                } else {
                    try appendString(ctx, out, str, width, @intCast(precision), padding, alignment, false, expprec, false);
                }
            },
            'd' => try appendInt(ctx, out, try getLong(st, arg), width, padding, alignment, always_sign),
            'u' => try appendUint(ctx, out, @bitCast(try getLong(st, arg)), width, padding, alignment),
            'e', 'E', 'f', 'F', 'g', 'G', 'h', 'H' => try appendDouble(st, out, try getDouble(st, arg), width, padding, alignment, precision, adjust_precision, spec, always_sign),
            'c' => try out.append(a, @truncate(@as(u64, @bitCast(try getLong(st, arg))))),
            'o' => try append2n(ctx, out, try getLong(st, arg), width, padding, alignment, 3, hexchars, expprec),
            'x' => try append2n(ctx, out, try getLong(st, arg), width, padding, alignment, 4, hexchars, expprec),
            'X' => try append2n(ctx, out, try getLong(st, arg), width, padding, alignment, 4, HEXCHARS, expprec),
            'b' => try append2n(ctx, out, try getLong(st, arg), width, padding, alignment, 1, hexchars, expprec),
            '%' => try out.append(a, '%'),
            else => {
                if (spec == 0 and i >= format.len) return st.valueError("Missing format specifier at end of string", .{});
                // php builds the message as a C string, so a nul ends it
                if (spec == 0) return st.valueError("Unknown format specifier \"", .{});
                return st.valueError("Unknown format specifier \"{c}\"", .{spec});
            },
        }
        i += 1;
    }

    if (max_missing_argnum) |m| {
        if (nb_additional_parameters) |nb| {
            return st.fail("ArgumentCountError", "{d} arguments are required, {d} given", .{ m + nb + 1, args.len + nb });
        }
        return st.valueError("The arguments array must contain {d} items, {d} given", .{ m + 1, args.len });
    }
}

// parameter parsing for the stream, format and values parameters

fn typeError(ctx: *NativeContext, func: []const u8, index: usize, name: []const u8, expected: []const u8, got: Value) RuntimeError {
    return throw(ctx, "TypeError", "{s}(): Argument #{d} (${s}) must be of type {s}, {s} given", .{ func, index + 1, name, expected, phpTypeName(got) });
}

fn formatArg(ctx: *NativeContext, func: []const u8, args: []const Value, index: usize, scratch: []u8) RuntimeError![]const u8 {
    const v: Value = if (index < args.len) args[index] else .null;
    if (v == .string) return v.string.bytes();
    if (ctx.vm.script_strict_types) return typeError(ctx, func, index, "format", "string", v);
    switch (v) {
        .null, .undef => {
            var buf: [128]u8 = undefined;
            try ctx.vm.raiseError(e_deprecated, std.fmt.bufPrint(&buf, "{s}(): Passing null to parameter #{d} ($format) of type string is deprecated", .{ func, index + 1 }) catch unreachable);
            return "";
        },
        .int, .float, .bool => {
            var st: State = .{ .ctx = ctx };
            return getString(&st, v, scratch);
        },
        .object => |o| if (ctx.vm.hasMethod(o.class_name, "__toString")) return ctx.vm.objectToString(o),
        else => {},
    }
    return typeError(ctx, func, index, "format", "string", v);
}

const Dest = enum { string, output, stream };

// the six functions: an optional stream, the format, then the values as
// arguments or as one array
fn formattedCall(ctx: *NativeContext, args: []const Value, comptime func: []const u8, comptime dest: Dest, comptime from_array: bool) RuntimeError!NativeResult {
    const format_index: usize = if (dest == .stream) 1 else 0;
    if (dest == .stream) _ = try @import("filesystem.zig").streamArg(ctx, args, .{ .func = func });
    var scratch: [1100]u8 = undefined;
    const format = try formatArg(ctx, func, args, format_index, &scratch);

    var vbuf: [16]Value = undefined;
    var values: []const Value = if (args.len > format_index + 1) args[format_index + 1 ..] else &.{};
    if (from_array) {
        const v: Value = if (args.len > format_index + 1) args[format_index + 1] else .null;
        if (v != .array) return typeError(ctx, func, format_index + 1, "values", "array", v);
        values = try ctx.argsFromArray(v.array, &vbuf);
    }
    defer if (from_array) ctx.freeArgs(@constCast(values), &vbuf);

    var out: Out = .empty;
    defer out.deinit(ctx.allocator);
    try out.ensureTotalCapacity(ctx.allocator, format.len + 32);
    var st: State = .{ .ctx = ctx };
    errdefer st.release();
    try formattedPrint(&st, &out, format, values, if (from_array) null else format_index + 1);

    // an exception a conversion left pending is thrown once the result is out
    const len = out.items.len;
    var result: NativeResult = undefined;
    switch (dest) {
        .string => {
            if (st.pending != null) return reraise(&st);
            result = NativeResult.takeString(try Value.String.adopt(ctx.allocator, try out.toOwnedSlice(ctx.allocator)));
        },
        .output => {
            try ctx.vm.output.appendSlice(ctx.allocator, out.items);
            result = NativeResult.scalar(.{ .int = @intCast(len) });
        },
        .stream => {
            const s = try Value.String.adopt(ctx.allocator, try out.toOwnedSlice(ctx.allocator));
            defer s.release();
            _ = try ctx.vm.callByName("fwrite", &.{ args[0], .{ .string = s } });
            // php answers the formatted length whatever the write did
            result = NativeResult.scalar(.{ .int = @intCast(len) });
        },
    }
    if (st.pending != null) return reraise(&st);
    return result;
}

fn reraise(st: *State) RuntimeError {
    st.ctx.vm.setPendingOwned(st.pending.?);
    st.pending = null;
    return error.RuntimeError;
}

fn native_sprintf(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return formattedCall(ctx, args, "sprintf", .string, false);
}

fn native_vsprintf(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return formattedCall(ctx, args, "vsprintf", .string, true);
}

fn native_printf(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return formattedCall(ctx, args, "printf", .output, false);
}

fn native_vprintf(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return formattedCall(ctx, args, "vprintf", .output, true);
}

fn native_fprintf(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return formattedCall(ctx, args, "fprintf", .stream, false);
}

fn native_vfprintf(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return formattedCall(ctx, args, "vfprintf", .stream, true);
}

test "gcvt matches php's %g layout" {
    var buf: [128]u8 = undefined;
    try std.testing.expectEqualStrings("1.0E+20", gcvt(1e20, -1, '.', 'E', &buf));
    try std.testing.expectEqualStrings("0.3", gcvt(0.1 + 0.2, 14, '.', 'E', &buf));
    try std.testing.expectEqualStrings("1.2345678901235E+14", gcvt(123456789012345.678, 14, '.', 'E', &buf));
    try std.testing.expectEqualStrings("-0", gcvt(-0.0, 6, '.', 'e', &buf));
    try std.testing.expectEqualStrings("1.0e-5", gcvt(1e-5, 6, '.', 'e', &buf));
    try std.testing.expectEqualStrings("0.0001", gcvt(1e-4, 6, '.', 'e', &buf));
    try std.testing.expectEqualStrings("100000", gcvt(1e5, 6, '.', 'e', &buf));
    try std.testing.expectEqualStrings("1.0e+6", gcvt(1e6, 6, '.', 'e', &buf));
}

test "convFp writes php's exponent without padding" {
    var buf: [128]u8 = undefined;
    var neg = false;
    try std.testing.expectEqualStrings("1.234500e+3", convFp('e', 1234.5, 6, &neg, &buf));
    try std.testing.expectEqualStrings("0.000e+0", convFp('e', -0.0, 3, &neg, &buf));
    try std.testing.expect(!neg);
    try std.testing.expectEqualStrings("5.6000", convFp('F', -5.6, 4, &neg, &buf));
    try std.testing.expect(neg);
}
