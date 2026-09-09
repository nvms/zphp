const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeResult = vm_mod.NativeResult;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

// arbitrary-precision decimal arithmetic mirroring PHP's bcmath.
//
// BcNum stores a normalized decimal number as a sign and a packed digit buffer
// where the decimal point falls `scale` positions from the right. Leading zeros
// in the integer part are stripped except for the canonical "0" case.

const BcNum = struct {
    sign: i8 = 1, // +1 or -1
    digits: std.ArrayListUnmanaged(u8) = .{},
    scale: usize = 0,

    fn deinit(self: *BcNum, allocator: Allocator) void {
        self.digits.deinit(allocator);
    }

    fn isZero(self: BcNum) bool {
        for (self.digits.items) |d| if (d != 0) return false;
        return true;
    }

    fn integerLen(self: BcNum) usize {
        return self.digits.items.len - self.scale;
    }
};

fn allocBc(_: *NativeContext) BcNum {
    return .{};
}

fn parseBc(allocator: Allocator, s: []const u8) !BcNum {
    var n = BcNum{};
    var i: usize = 0;
    while (i < s.len and (s[i] == ' ' or s[i] == '\t')) : (i += 1) {}
    if (i < s.len and (s[i] == '+' or s[i] == '-')) {
        if (s[i] == '-') n.sign = -1;
        i += 1;
    }
    var int_digits = std.ArrayListUnmanaged(u8){};
    defer int_digits.deinit(allocator);
    var frac_digits = std.ArrayListUnmanaged(u8){};
    defer frac_digits.deinit(allocator);

    var saw_dot = false;
    while (i < s.len) : (i += 1) {
        const ch = s[i];
        if (ch == '.') {
            if (saw_dot) break;
            saw_dot = true;
            continue;
        }
        if (ch < '0' or ch > '9') break;
        const d: u8 = ch - '0';
        if (saw_dot) try frac_digits.append(allocator, d) else try int_digits.append(allocator, d);
    }
    if (int_digits.items.len == 0) try int_digits.append(allocator, 0);
    while (int_digits.items.len > 1 and int_digits.items[0] == 0) {
        _ = int_digits.orderedRemove(0);
    }
    try n.digits.appendSlice(allocator, int_digits.items);
    try n.digits.appendSlice(allocator, frac_digits.items);
    n.scale = frac_digits.items.len;
    if (n.isZero()) n.sign = 1;
    return n;
}

fn formatBc(allocator: Allocator, n: BcNum, target_scale: usize) ![]u8 {
    var out = std.ArrayListUnmanaged(u8){};
    errdefer out.deinit(allocator);

    // truncate / extend fractional part to target_scale (PHP truncates, not rounds)
    const int_len = n.integerLen();
    var ints = n.digits.items[0..int_len];
    while (ints.len > 1 and ints[0] == 0) ints = ints[1..];

    const is_zero = blk: {
        for (n.digits.items) |d| if (d != 0) break :blk false;
        break :blk true;
    };
    if (n.sign < 0 and !is_zero) try out.append(allocator, '-');

    for (ints) |d| try out.append(allocator, '0' + d);

    if (target_scale > 0) {
        try out.append(allocator, '.');
        var i: usize = 0;
        while (i < target_scale) : (i += 1) {
            if (i < n.scale) {
                try out.append(allocator, '0' + n.digits.items[int_len + i]);
            } else {
                try out.append(allocator, '0');
            }
        }
    }

    return try out.toOwnedSlice(allocator);
}

// align two numbers to the same scale AND integer length, returning copies
// with identical digit buffer lengths so element-wise add/sub work index-by-index
fn alignScales(allocator: Allocator, a: BcNum, b: BcNum) !struct { a: BcNum, b: BcNum, scale: usize } {
    const scale = @max(a.scale, b.scale);
    const int_len = @max(a.integerLen(), b.integerLen());
    var ac = try copyAndPadBoth(allocator, a, int_len, scale);
    errdefer ac.deinit(allocator);
    const bc = try copyAndPadBoth(allocator, b, int_len, scale);
    return .{ .a = ac, .b = bc, .scale = scale };
}

fn copyAndPadRight(allocator: Allocator, n: BcNum, new_scale: usize) !BcNum {
    var out = BcNum{ .sign = n.sign, .scale = new_scale };
    if (new_scale >= n.scale) {
        try out.digits.appendSlice(allocator, n.digits.items);
        var i: usize = n.scale;
        while (i < new_scale) : (i += 1) try out.digits.append(allocator, 0);
    } else {
        // shrinking scale: truncate fractional tail
        const drop = n.scale - new_scale;
        try out.digits.appendSlice(allocator, n.digits.items[0 .. n.digits.items.len - drop]);
    }
    return out;
}

fn copyAndPadBoth(allocator: Allocator, n: BcNum, target_int_len: usize, target_scale: usize) !BcNum {
    var out = BcNum{ .sign = n.sign, .scale = target_scale };
    const cur_int_len = n.integerLen();
    const left_pad: usize = if (target_int_len > cur_int_len) target_int_len - cur_int_len else 0;
    var i: usize = 0;
    while (i < left_pad) : (i += 1) try out.digits.append(allocator, 0);
    try out.digits.appendSlice(allocator, n.digits.items);
    const right_pad: usize = if (target_scale > n.scale) target_scale - n.scale else 0;
    var j: usize = 0;
    while (j < right_pad) : (j += 1) try out.digits.append(allocator, 0);
    return out;
}

// compare absolute values, returning -1/0/1
fn cmpAbs(a: BcNum, b: BcNum) i32 {
    const al = a.integerLen();
    const bl = b.integerLen();
    if (al != bl) return if (al < bl) -1 else 1;
    var i: usize = 0;
    while (i < al) : (i += 1) {
        const ad = a.digits.items[i];
        const bd = b.digits.items[i];
        if (ad != bd) return if (ad < bd) -1 else 1;
    }
    // integer parts equal, compare fraction up to min(a.scale, b.scale)
    const min_scale = @min(a.scale, b.scale);
    var f: usize = 0;
    while (f < min_scale) : (f += 1) {
        const ad = a.digits.items[al + f];
        const bd = b.digits.items[bl + f];
        if (ad != bd) return if (ad < bd) -1 else 1;
    }
    // longer fraction with non-zero trailing digits is larger
    if (a.scale > b.scale) {
        var j: usize = min_scale;
        while (j < a.scale) : (j += 1) if (a.digits.items[al + j] != 0) return 1;
    } else if (b.scale > a.scale) {
        var j: usize = min_scale;
        while (j < b.scale) : (j += 1) if (b.digits.items[bl + j] != 0) return -1;
    }
    return 0;
}

fn cmpFull(a: BcNum, b: BcNum) i32 {
    if (a.isZero() and b.isZero()) return 0;
    if (a.sign != b.sign) return if (a.sign < 0) -1 else 1;
    const c = cmpAbs(a, b);
    return if (a.sign < 0) -c else c;
}

fn addAbs(allocator: Allocator, a: BcNum, b: BcNum) !BcNum {
    var aligned = try alignScales(allocator, a, b);
    defer aligned.a.deinit(allocator);
    defer aligned.b.deinit(allocator);

    var out = BcNum{ .scale = aligned.scale };
    errdefer out.deinit(allocator);

    const len = aligned.a.digits.items.len;
    try out.digits.resize(allocator, len + 1);
    var carry: u8 = 0;
    var i: usize = len;
    var oi: usize = len + 1;
    while (i > 0) {
        i -= 1;
        oi -= 1;
        const sum = aligned.a.digits.items[i] + aligned.b.digits.items[i] + carry;
        out.digits.items[oi] = sum % 10;
        carry = sum / 10;
    }
    out.digits.items[0] = carry;
    // strip leading zeros from integer part
    var lead: usize = 0;
    const int_len = out.digits.items.len - out.scale;
    while (lead + 1 < int_len and out.digits.items[lead] == 0) lead += 1;
    if (lead > 0) {
        try out.digits.replaceRange(allocator, 0, lead, &.{});
    }
    return out;
}

// subAbs: a >= b in magnitude. computes a - b
fn subAbs(allocator: Allocator, a: BcNum, b: BcNum) !BcNum {
    var aligned = try alignScales(allocator, a, b);
    defer aligned.a.deinit(allocator);
    defer aligned.b.deinit(allocator);

    var out = BcNum{ .scale = aligned.scale };
    errdefer out.deinit(allocator);
    try out.digits.resize(allocator, aligned.a.digits.items.len);

    var borrow: i32 = 0;
    var i: usize = aligned.a.digits.items.len;
    while (i > 0) {
        i -= 1;
        var diff: i32 = @as(i32, aligned.a.digits.items[i]) - @as(i32, aligned.b.digits.items[i]) - borrow;
        if (diff < 0) {
            diff += 10;
            borrow = 1;
        } else {
            borrow = 0;
        }
        out.digits.items[i] = @intCast(diff);
    }
    // strip leading zeros
    var lead: usize = 0;
    const int_len = out.digits.items.len - out.scale;
    while (lead + 1 < int_len and out.digits.items[lead] == 0) lead += 1;
    if (lead > 0) {
        try out.digits.replaceRange(allocator, 0, lead, &.{});
    }
    return out;
}

fn bcAddInternal(allocator: Allocator, a: BcNum, b: BcNum) !BcNum {
    if (a.sign == b.sign) {
        var r = try addAbs(allocator, a, b);
        r.sign = a.sign;
        if (r.isZero()) r.sign = 1;
        return r;
    }
    const cmp = cmpAbs(a, b);
    if (cmp == 0) return BcNum{ .sign = 1, .scale = @max(a.scale, b.scale), .digits = blk: {
        var d = std.ArrayListUnmanaged(u8){};
        const total = 1 + @max(a.scale, b.scale);
        try d.resize(allocator, total);
        @memset(d.items, 0);
        break :blk d;
    } };
    var r: BcNum = undefined;
    if (cmp > 0) {
        r = try subAbs(allocator, a, b);
        r.sign = a.sign;
    } else {
        r = try subAbs(allocator, b, a);
        r.sign = b.sign;
    }
    if (r.isZero()) r.sign = 1;
    return r;
}

fn bcSubInternal(allocator: Allocator, a: BcNum, b: BcNum) !BcNum {
    var bneg = b;
    bneg.sign = -b.sign;
    return bcAddInternal(allocator, a, bneg);
}

fn bcMulInternal(allocator: Allocator, a: BcNum, b: BcNum) !BcNum {
    var out = BcNum{ .scale = a.scale + b.scale, .sign = a.sign * b.sign };
    errdefer out.deinit(allocator);

    const al = a.digits.items.len;
    const bl = b.digits.items.len;
    if (al == 0 or bl == 0) {
        try out.digits.append(allocator, 0);
        out.scale = 0;
        out.sign = 1;
        return out;
    }

    try out.digits.resize(allocator, al + bl);
    @memset(out.digits.items, 0);

    var i: usize = al;
    while (i > 0) {
        i -= 1;
        var carry: u16 = 0;
        var j: usize = bl;
        while (j > 0) {
            j -= 1;
            const product: u16 = @as(u16, a.digits.items[i]) * @as(u16, b.digits.items[j]) + @as(u16, out.digits.items[i + j + 1]) + carry;
            out.digits.items[i + j + 1] = @intCast(product % 10);
            carry = product / 10;
        }
        out.digits.items[i] += @intCast(carry);
    }
    // strip leading zeros from integer part
    var lead: usize = 0;
    const int_len = out.digits.items.len - out.scale;
    while (lead + 1 < int_len and out.digits.items[lead] == 0) lead += 1;
    if (lead > 0) {
        try out.digits.replaceRange(allocator, 0, lead, &.{});
    }
    if (out.isZero()) out.sign = 1;
    return out;
}

fn bcDivInternal(allocator: Allocator, a: BcNum, b: BcNum, target_scale: usize) !?BcNum {
    if (b.isZero()) return null;

    // shift dividend left by (target_scale + 1) - a.scale + b.scale so that
    // integer division gives us the answer at target_scale, with one extra digit
    // we can truncate. simpler approach: convert both to integer reps with extra
    // zeros to control the scale.

    // make a' = a * 10^(target_scale + b.scale - a.scale) (integer), b' = b (integer).
    // a dividend more precise than the target needs its low digits dropped
    // instead: truncating before an integer division truncates the quotient
    // at the same place
    const shift: i64 = @as(i64, @intCast(target_scale + b.scale + 1)) - @as(i64, @intCast(a.scale));

    var num_digits = std.ArrayListUnmanaged(u8){};
    defer num_digits.deinit(allocator);
    if (shift >= 0) {
        try num_digits.appendSlice(allocator, a.digits.items);
        var i: usize = 0;
        while (i < @as(usize, @intCast(shift))) : (i += 1) try num_digits.append(allocator, 0);
    } else {
        const drop: usize = @intCast(-shift);
        const keep = if (drop >= a.digits.items.len) 0 else a.digits.items.len - drop;
        try num_digits.appendSlice(allocator, a.digits.items[0..keep]);
        if (num_digits.items.len == 0) try num_digits.append(allocator, 0);
    }

    var div_digits = std.ArrayListUnmanaged(u8){};
    defer div_digits.deinit(allocator);
    try div_digits.appendSlice(allocator, b.digits.items);

    // strip leading zeros from divisor
    while (div_digits.items.len > 1 and div_digits.items[0] == 0) _ = div_digits.orderedRemove(0);

    // long division: produce quotient digit-by-digit
    var quot = std.ArrayListUnmanaged(u8){};
    errdefer quot.deinit(allocator);
    var rem = std.ArrayListUnmanaged(u8){};
    defer rem.deinit(allocator);

    for (num_digits.items) |d| {
        try rem.append(allocator, d);
        while (rem.items.len > 1 and rem.items[0] == 0) _ = rem.orderedRemove(0);

        // find largest q in 0..9 with q*div <= rem
        var q: u8 = 0;
        while (q < 9) {
            // multiply div by (q+1) and compare to rem
            const test_q = q + 1;
            var prod = std.ArrayListUnmanaged(u8){};
            defer prod.deinit(allocator);
            var carry: u8 = 0;
            var j: usize = div_digits.items.len;
            try prod.resize(allocator, div_digits.items.len);
            while (j > 0) {
                j -= 1;
                const v: u8 = div_digits.items[j] * test_q + carry;
                prod.items[j] = v % 10;
                carry = v / 10;
            }
            if (carry > 0) try prod.insert(allocator, 0, carry);
            // compare prod to rem
            const cmp = cmpDigits(prod.items, rem.items);
            if (cmp > 0) break;
            q = test_q;
        }
        try quot.append(allocator, q);

        if (q > 0) {
            // subtract q*div from rem
            var prod = std.ArrayListUnmanaged(u8){};
            defer prod.deinit(allocator);
            var carry: u8 = 0;
            try prod.resize(allocator, div_digits.items.len);
            var j: usize = div_digits.items.len;
            while (j > 0) {
                j -= 1;
                const v: u8 = div_digits.items[j] * q + carry;
                prod.items[j] = v % 10;
                carry = v / 10;
            }
            if (carry > 0) try prod.insert(allocator, 0, carry);

            // subtract prod from rem
            const diff_len = rem.items.len;
            var pad: usize = 0;
            if (prod.items.len < diff_len) pad = diff_len - prod.items.len;
            // align prod to rem by left-padding zeros conceptually
            var borrow: i32 = 0;
            var k: usize = diff_len;
            while (k > 0) {
                k -= 1;
                const pv: i32 = if (k >= pad) @intCast(prod.items[k - pad]) else 0;
                var diff: i32 = @as(i32, rem.items[k]) - pv - borrow;
                if (diff < 0) {
                    diff += 10;
                    borrow = 1;
                } else borrow = 0;
                rem.items[k] = @intCast(diff);
            }
        }
    }

    var out = BcNum{ .sign = a.sign * b.sign };
    errdefer out.deinit(allocator);

    // quot has digits for: int_part of a (a.integerLen()) + extra_a positions
    // total digits = a.digits.len + extra_a
    // scale of result = target_scale + 1 (the extra digit). truncate to target_scale
    const total = quot.items.len;
    const wanted = target_scale;
    // last digit is the "extra" — drop it (truncate)
    const useful = total - 1;
    try out.digits.appendSlice(allocator, quot.items[0..useful]);
    out.scale = wanted;
    quot.deinit(allocator);

    // strip leading zeros
    var lead: usize = 0;
    const int_len_out = out.digits.items.len - out.scale;
    while (lead + 1 < int_len_out and out.digits.items[lead] == 0) lead += 1;
    if (lead > 0) try out.digits.replaceRange(allocator, 0, lead, &.{});

    if (out.isZero()) out.sign = 1;
    return out;
}

fn cmpDigits(a: []const u8, b: []const u8) i32 {
    if (a.len != b.len) return if (a.len < b.len) -1 else 1;
    for (a, b) |x, y| {
        if (x != y) return if (x < y) -1 else 1;
    }
    return 0;
}

// ---------------- bcscale state ----------------

var global_scale_lock = std.Thread.Mutex{};
var global_scale: usize = 0;

fn currentScale() usize {
    global_scale_lock.lock();
    defer global_scale_lock.unlock();
    return global_scale;
}

fn setScale(v: usize) void {
    global_scale_lock.lock();
    defer global_scale_lock.unlock();
    global_scale = v;
}

fn resolveScale(args: []const Value, scale_idx: usize) usize {
    if (args.len > scale_idx and args[scale_idx] == .int and args[scale_idx].int >= 0) {
        return @intCast(args[scale_idx].int);
    }
    return currentScale();
}

// ---------------- top-level functions ----------------

fn argToString(args: []const Value, idx: usize) ?[]const u8 {
    if (args.len <= idx) return null;
    return switch (args[idx]) {
        .string => |s| s.bytes(),
        else => null,
    };
}

fn bcAdd(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const sa = argToString(args, 0) orelse return NativeResult.scalar(.null);
    const sb = argToString(args, 1) orelse return NativeResult.scalar(.null);
    const scale = resolveScale(args, 2);
    var a = try parseBc(ctx.allocator, sa);
    defer a.deinit(ctx.allocator);
    var b = try parseBc(ctx.allocator, sb);
    defer b.deinit(ctx.allocator);
    var r = try bcAddInternal(ctx.allocator, a, b);
    defer r.deinit(ctx.allocator);
    const out = try formatBc(ctx.allocator, r, scale);

    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

fn bcSub(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const sa = argToString(args, 0) orelse return NativeResult.scalar(.null);
    const sb = argToString(args, 1) orelse return NativeResult.scalar(.null);
    const scale = resolveScale(args, 2);
    var a = try parseBc(ctx.allocator, sa);
    defer a.deinit(ctx.allocator);
    var b = try parseBc(ctx.allocator, sb);
    defer b.deinit(ctx.allocator);
    var r = try bcSubInternal(ctx.allocator, a, b);
    defer r.deinit(ctx.allocator);
    const out = try formatBc(ctx.allocator, r, scale);

    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

fn bcMul(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const sa = argToString(args, 0) orelse return NativeResult.scalar(.null);
    const sb = argToString(args, 1) orelse return NativeResult.scalar(.null);
    const scale = resolveScale(args, 2);
    var a = try parseBc(ctx.allocator, sa);
    defer a.deinit(ctx.allocator);
    var b = try parseBc(ctx.allocator, sb);
    defer b.deinit(ctx.allocator);
    var r = try bcMulInternal(ctx.allocator, a, b);
    defer r.deinit(ctx.allocator);
    const out = try formatBc(ctx.allocator, r, scale);

    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

fn bcDiv(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const sa = argToString(args, 0) orelse return NativeResult.scalar(.null);
    const sb = argToString(args, 1) orelse return NativeResult.scalar(.null);
    const scale = resolveScale(args, 2);
    var a = try parseBc(ctx.allocator, sa);
    defer a.deinit(ctx.allocator);
    var b = try parseBc(ctx.allocator, sb);
    defer b.deinit(ctx.allocator);
    if (b.isZero()) {
        try ctx.vm.setPendingException("DivisionByZeroError", "Division by zero");
        return error.RuntimeError;
    }
    var r_opt = try bcDivInternal(ctx.allocator, a, b, scale);
    if (r_opt) |*r| {
        defer r.deinit(ctx.allocator);
        const out = try formatBc(ctx.allocator, r.*, scale);

        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
    }
    return NativeResult.scalar(.null);
}

fn bcMod(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const sa = argToString(args, 0) orelse return NativeResult.scalar(.null);
    const sb = argToString(args, 1) orelse return NativeResult.scalar(.null);
    const scale = resolveScale(args, 2);
    var a = try parseBc(ctx.allocator, sa);
    defer a.deinit(ctx.allocator);
    var b = try parseBc(ctx.allocator, sb);
    defer b.deinit(ctx.allocator);
    if (b.isZero()) {
        try ctx.vm.setPendingException("DivisionByZeroError", "Modulo by zero");
        return NativeResult.scalar(.null);
    }
    // mod = a - (a / b truncated to scale=0) * b. then format to target scale
    var q_opt = try bcDivInternal(ctx.allocator, a, b, 0);
    if (q_opt == null) return NativeResult.scalar(.null);
    defer q_opt.?.deinit(ctx.allocator);
    var qb = try bcMulInternal(ctx.allocator, q_opt.?, b);
    defer qb.deinit(ctx.allocator);
    var r = try bcSubInternal(ctx.allocator, a, qb);
    defer r.deinit(ctx.allocator);
    const out = try formatBc(ctx.allocator, r, scale);

    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

fn bcDivmod(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const sa = argToString(args, 0) orelse return NativeResult.scalar(.null);
    const sb = argToString(args, 1) orelse return NativeResult.scalar(.null);
    const scale = resolveScale(args, 2);
    var a = try parseBc(ctx.allocator, sa);
    defer a.deinit(ctx.allocator);
    var b = try parseBc(ctx.allocator, sb);
    defer b.deinit(ctx.allocator);
    if (b.isZero()) {
        try ctx.vm.setPendingException("DivisionByZeroError", "Division by zero");
        return NativeResult.scalar(.null);
    }
    var q_opt = try bcDivInternal(ctx.allocator, a, b, 0);
    if (q_opt == null) return NativeResult.scalar(.null);
    const q = q_opt.?;
    defer @constCast(&q).deinit(ctx.allocator);
    var qb = try bcMulInternal(ctx.allocator, q, b);
    defer qb.deinit(ctx.allocator);
    var r = try bcSubInternal(ctx.allocator, a, qb);
    defer r.deinit(ctx.allocator);
    _ = &q_opt;

    const q_str = try formatBc(ctx.allocator, q, 0);
    const q_owned = try Value.String.adopt(ctx.allocator, q_str);
    defer q_owned.release();
    const r_str = try formatBc(ctx.allocator, r, scale);
    const r_owned = try Value.String.adopt(ctx.allocator, r_str);
    defer r_owned.release();

    const arr = try ctx.createArray();
    try arr.append(ctx.allocator, .{ .string = q_owned });
    try arr.append(ctx.allocator, .{ .string = r_owned });
    return NativeResult.borrowed(.{ .array = arr });
}

fn bcPow(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const sa = argToString(args, 0) orelse return NativeResult.scalar(.null);
    const sb = argToString(args, 1) orelse return NativeResult.scalar(.null);
    const scale = resolveScale(args, 2);
    var a = try parseBc(ctx.allocator, sa);
    defer a.deinit(ctx.allocator);
    // exponent must be a non-negative integer (PHP allows negative but truncates)
    const exp_str = sb;
    var exp: i64 = std.fmt.parseInt(i64, std.mem.trim(u8, exp_str, " \t"), 10) catch return NativeResult.scalar(.null);
    var negative_exp = false;
    if (exp < 0) {
        negative_exp = true;
        exp = -exp;
    }

    // result = 1
    var r = try parseBc(ctx.allocator, "1");
    errdefer r.deinit(ctx.allocator);
    var base = try parseBc(ctx.allocator, "0");
    base.deinit(ctx.allocator);
    base = try parseBc(ctx.allocator, sa);
    defer base.deinit(ctx.allocator);

    while (exp > 0) {
        if (exp & 1 == 1) {
            const tmp = try bcMulInternal(ctx.allocator, r, base);
            r.deinit(ctx.allocator);
            r = tmp;
        }
        exp >>= 1;
        if (exp > 0) {
            const tmp = try bcMulInternal(ctx.allocator, base, base);
            base.deinit(ctx.allocator);
            base = tmp;
        }
    }

    if (negative_exp) {
        // 1 / r with target scale
        var one = try parseBc(ctx.allocator, "1");
        defer one.deinit(ctx.allocator);
        var inv = (try bcDivInternal(ctx.allocator, one, r, scale)) orelse {
            r.deinit(ctx.allocator);
            return NativeResult.scalar(.null);
        };
        defer inv.deinit(ctx.allocator);
        r.deinit(ctx.allocator);
        const out = try formatBc(ctx.allocator, inv, scale);

        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
    }

    defer r.deinit(ctx.allocator);
    const out = try formatBc(ctx.allocator, r, scale);

    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

// modular exponentiation: base^exp mod mod. arbitrary precision via the same
// BcNum primitives bcpow uses, but exp is also a BcNum so it can be larger
// than i64. PHP truncates fractional bits of all three args.
fn bcPowmod(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const sa = argToString(args, 0) orelse return NativeResult.scalar(.null);
    const sb = argToString(args, 1) orelse return NativeResult.scalar(.null);
    const sm = argToString(args, 2) orelse return NativeResult.scalar(.null);
    const scale = resolveScale(args, 3);

    // truncate fractional parts (PHP semantics for bcpowmod)
    var base = try parseBc(ctx.allocator, sa);
    base.scale = 0;
    if (base.digits.items.len > 0) {
        // keep integer part only
        const int_digits = base.digits.items.len;
        _ = int_digits;
    }
    defer base.deinit(ctx.allocator);
    var exp = try parseBc(ctx.allocator, sb);
    defer exp.deinit(ctx.allocator);
    var mod = try parseBc(ctx.allocator, sm);
    defer mod.deinit(ctx.allocator);

    if (mod.isZero()) {
        try ctx.vm.setPendingException("DivisionByZeroError", "Modulo by zero");
        return NativeResult.scalar(.null);
    }
    if (exp.sign < 0) {
        try ctx.vm.setPendingException("ValueError", "bcpowmod(): Argument #2 ($exponent) must be greater than or equal to 0");
        return NativeResult.scalar(.null);
    }

    // result = 1
    var result = try parseBc(ctx.allocator, "1");
    errdefer result.deinit(ctx.allocator);

    // base = base mod mod (so subsequent multiplies stay bounded)
    {
        var q = (try bcDivInternal(ctx.allocator, base, mod, 0)) orelse return NativeResult.scalar(.null);
        defer q.deinit(ctx.allocator);
        var qm = try bcMulInternal(ctx.allocator, q, mod);
        defer qm.deinit(ctx.allocator);
        const new_base = try bcSubInternal(ctx.allocator, base, qm);
        base.deinit(ctx.allocator);
        base = new_base;
    }

    // square-and-multiply with bcnum-sized exponent
    var two = try parseBc(ctx.allocator, "2");
    defer two.deinit(ctx.allocator);

    while (!exp.isZero()) {
        // exp odd? -> last digit % 2 == 1 (digits are decimal; check the
        // ones place). BcNum digits are stored with integer/fractional split
        // so the ones-place digit is at index integer_count - 1
        const odd = blk: {
            // a BcNum that's all zeros isn't reached (loop exits). check ones digit
            // by computing exp mod 2
            var q2 = (try bcDivInternal(ctx.allocator, exp, two, 0)) orelse return NativeResult.scalar(.null);
            defer q2.deinit(ctx.allocator);
            var qm2 = try bcMulInternal(ctx.allocator, q2, two);
            defer qm2.deinit(ctx.allocator);
            var rem = try bcSubInternal(ctx.allocator, exp, qm2);
            defer rem.deinit(ctx.allocator);
            break :blk !rem.isZero();
        };

        if (odd) {
            var rb = try bcMulInternal(ctx.allocator, result, base);
            defer rb.deinit(ctx.allocator);
            var q = (try bcDivInternal(ctx.allocator, rb, mod, 0)) orelse return NativeResult.scalar(.null);
            defer q.deinit(ctx.allocator);
            var qm = try bcMulInternal(ctx.allocator, q, mod);
            defer qm.deinit(ctx.allocator);
            const new_r = try bcSubInternal(ctx.allocator, rb, qm);
            result.deinit(ctx.allocator);
            result = new_r;
        }

        // exp = exp / 2
        {
            const new_exp = (try bcDivInternal(ctx.allocator, exp, two, 0)) orelse return NativeResult.scalar(.null);
            exp.deinit(ctx.allocator);
            exp = new_exp;
        }
        if (exp.isZero()) break;

        // base = (base * base) mod mod
        {
            var bb = try bcMulInternal(ctx.allocator, base, base);
            defer bb.deinit(ctx.allocator);
            var q = (try bcDivInternal(ctx.allocator, bb, mod, 0)) orelse return NativeResult.scalar(.null);
            defer q.deinit(ctx.allocator);
            var qm = try bcMulInternal(ctx.allocator, q, mod);
            defer qm.deinit(ctx.allocator);
            const new_base = try bcSubInternal(ctx.allocator, bb, qm);
            base.deinit(ctx.allocator);
            base = new_base;
        }
    }

    const out = try formatBc(ctx.allocator, result, scale);

    result.deinit(ctx.allocator);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

fn bcSqrt(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const sa = argToString(args, 0) orelse return NativeResult.scalar(.null);
    const scale = resolveScale(args, 1);
    var a = try parseBc(ctx.allocator, sa);
    defer a.deinit(ctx.allocator);
    if (a.sign < 0) return NativeResult.scalar(.null);
    if (a.isZero()) {
        const z = try makeZeroString(ctx.allocator, scale);

        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, z));
    }

    // newton's method on the full-precision string. work with scale+2 internal precision
    const work_scale = scale + 2;
    var x = try parseBc(ctx.allocator, sa);
    defer x.deinit(ctx.allocator);

    var iters: usize = 0;
    while (iters < 200) : (iters += 1) {
        // x_next = (x + a/x) / 2
        var ax = (try bcDivInternal(ctx.allocator, a, x, work_scale)) orelse return NativeResult.scalar(.null);
        defer ax.deinit(ctx.allocator);
        var sum = try bcAddInternal(ctx.allocator, x, ax);
        defer sum.deinit(ctx.allocator);
        var two = try parseBc(ctx.allocator, "2");
        defer two.deinit(ctx.allocator);
        const next = (try bcDivInternal(ctx.allocator, sum, two, work_scale)) orelse return NativeResult.scalar(.null);
        // check convergence: if |next - x| < 10^-work_scale
        var diff = try bcSubInternal(ctx.allocator, next, x);
        defer diff.deinit(ctx.allocator);
        const converged = diff.isZero();
        x.deinit(ctx.allocator);
        x = next;
        if (converged) break;
    }
    const out = try formatBc(ctx.allocator, x, scale);

    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

fn makeZeroString(allocator: Allocator, scale: usize) ![]u8 {
    var out = std.ArrayListUnmanaged(u8){};
    errdefer out.deinit(allocator);
    try out.append(allocator, '0');
    if (scale > 0) {
        try out.append(allocator, '.');
        var i: usize = 0;
        while (i < scale) : (i += 1) try out.append(allocator, '0');
    }
    return try out.toOwnedSlice(allocator);
}

fn bcComp(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const sa = argToString(args, 0) orelse return NativeResult.scalar(.null);
    const sb = argToString(args, 1) orelse return NativeResult.scalar(.null);
    const scale = resolveScale(args, 2);
    var a = try parseBc(ctx.allocator, sa);
    defer a.deinit(ctx.allocator);
    var b = try parseBc(ctx.allocator, sb);
    defer b.deinit(ctx.allocator);
    // compare at the requested scale: truncate both to scale
    var ta = try copyAndPadRight(ctx.allocator, a, scale);
    defer ta.deinit(ctx.allocator);
    if (ta.scale > scale) {
        try ta.digits.resize(ctx.allocator, ta.digits.items.len - (ta.scale - scale));
        ta.scale = scale;
    }
    var tb = try copyAndPadRight(ctx.allocator, b, scale);
    defer tb.deinit(ctx.allocator);
    if (tb.scale > scale) {
        try tb.digits.resize(ctx.allocator, tb.digits.items.len - (tb.scale - scale));
        tb.scale = scale;
    }
    return NativeResult.scalar(.{ .int = @intCast(cmpFull(ta, tb)) });
}

fn bcScale(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const prev = currentScale();
    if (args.len > 0 and args[0] == .int and args[0].int >= 0) {
        setScale(@intCast(args[0].int));
        return NativeResult.scalar(.{ .int = @intCast(prev) });
    }
    return NativeResult.scalar(.{ .int = @intCast(prev) });
}

// ---------------- ceil / floor / round (PHP 8.4) ----------------

const NumParts = struct { neg: bool, int_part: []const u8, frac_part: []const u8 };

fn splitNumber(s: []const u8) NumParts {
    var i: usize = 0;
    var neg = false;
    if (i < s.len and (s[i] == '+' or s[i] == '-')) {
        neg = s[i] == '-';
        i += 1;
    }
    const int_start = i;
    while (i < s.len and s[i] >= '0' and s[i] <= '9') i += 1;
    const int_part = if (i > int_start) s[int_start..i] else "0";
    var frac: []const u8 = "";
    if (i < s.len and s[i] == '.') {
        i += 1;
        const frac_start = i;
        while (i < s.len and s[i] >= '0' and s[i] <= '9') i += 1;
        frac = s[frac_start..i];
    }
    return .{ .neg = neg, .int_part = int_part, .frac_part = frac };
}

fn fracNonZero(frac: []const u8) bool {
    for (frac) |c| if (c != '0') return true;
    return false;
}

fn incrementDigits(allocator: Allocator, digits: []const u8) ![]u8 {
    // returns digits + 1, may grow by one (e.g. "999" -> "1000")
    var buf = try allocator.alloc(u8, digits.len + 1);
    @memcpy(buf[1..], digits);
    buf[0] = '0';
    var i: usize = buf.len;
    var carry: u8 = 1;
    while (i > 0 and carry > 0) : (i -= 1) {
        const v = (buf[i - 1] - '0') + carry;
        buf[i - 1] = '0' + (v % 10);
        carry = v / 10;
    }
    if (buf[0] == '0') {
        const out = try allocator.alloc(u8, buf.len - 1);
        @memcpy(out, buf[1..]);
        allocator.free(buf);
        return out;
    }
    return buf;
}

fn signedResult(allocator: Allocator, neg: bool, digits: []const u8) ![]u8 {
    // strip leading zeros from the integer portion, but keep at least one and
    // never eat the zero before a decimal point (so "0.50" stays as-is)
    var start: usize = 0;
    const dot = std.mem.indexOfScalar(u8, digits, '.') orelse digits.len;
    while (start + 1 < dot and digits[start] == '0') start += 1;
    const body = digits[start..];
    const is_zero = blk: {
        for (body) |c| if (c != '0' and c != '.') break :blk false;
        break :blk true;
    };
    if (neg and !is_zero) {
        const out = try allocator.alloc(u8, body.len + 1);
        out[0] = '-';
        @memcpy(out[1..], body);
        return out;
    }
    return try allocator.dupe(u8, body);
}

fn bcCeil(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const s = argToString(args, 0) orelse return NativeResult.scalar(.null);
    const p = splitNumber(s);
    const has_frac = fracNonZero(p.frac_part);
    var result: []u8 = undefined;
    if (!has_frac) {
        result = try signedResult(ctx.allocator, p.neg, p.int_part);
    } else if (p.neg) {
        // negative number rounding toward +inf: drop the fraction
        result = try signedResult(ctx.allocator, true, p.int_part);
    } else {
        const inc = try incrementDigits(ctx.allocator, p.int_part);
        defer ctx.allocator.free(inc);
        result = try signedResult(ctx.allocator, false, inc);
    }

    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result));
}

fn bcFloor(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const s = argToString(args, 0) orelse return NativeResult.scalar(.null);
    const p = splitNumber(s);
    const has_frac = fracNonZero(p.frac_part);
    var result: []u8 = undefined;
    if (!has_frac) {
        result = try signedResult(ctx.allocator, p.neg, p.int_part);
    } else if (!p.neg) {
        result = try signedResult(ctx.allocator, false, p.int_part);
    } else {
        const inc = try incrementDigits(ctx.allocator, p.int_part);
        defer ctx.allocator.free(inc);
        result = try signedResult(ctx.allocator, true, inc);
    }

    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result));
}

fn bcRound(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const s = argToString(args, 0) orelse return NativeResult.scalar(.null);
    const precision: i64 = if (args.len > 1 and args[1] == .int) args[1].int else 0;
    const p = splitNumber(s);

    // build combined digit stream (int_part ++ frac_part) and remember the
    // decimal position. the result keeps `precision` digits after the point.
    // half-away-from-zero rounding: inspect the digit immediately past the cut
    var combined_buf: std.ArrayListUnmanaged(u8) = .{};
    defer combined_buf.deinit(ctx.allocator);
    try combined_buf.appendSlice(ctx.allocator, p.int_part);
    try combined_buf.appendSlice(ctx.allocator, p.frac_part);

    const dec_pos: i64 = @intCast(p.int_part.len);
    const want_len: i64 = dec_pos + precision;

    var result_buf: std.ArrayListUnmanaged(u8) = .{};
    defer result_buf.deinit(ctx.allocator);

    if (want_len <= 0) {
        // result is "0" with precision decimal places, plus possibly a carry
        // from the leading digit of combined
        var rounded_zero = true;
        if (combined_buf.items.len > 0) {
            const cut_idx: i64 = want_len;
            // first kept digit is at position want_len-1; round digit is at want_len
            // if want_len <= 0, we look at combined_buf[0] essentially
            if (cut_idx < @as(i64, @intCast(combined_buf.items.len))) {
                const idx: usize = if (cut_idx < 0) 0 else @intCast(cut_idx);
                if (idx < combined_buf.items.len and combined_buf.items[idx] >= '5') {
                    rounded_zero = false;
                }
            }
        }
        if (rounded_zero or want_len < 0) {
            try result_buf.append(ctx.allocator, '0');
            if (precision > 0) {
                try result_buf.append(ctx.allocator, '.');
                for (0..@intCast(precision)) |_| try result_buf.append(ctx.allocator, '0');
            }
        } else {
            // 0.5 rounded with precision=0 -> 1
            try result_buf.append(ctx.allocator, '1');
            if (precision > 0) {
                try result_buf.append(ctx.allocator, '.');
                for (0..@intCast(precision)) |_| try result_buf.append(ctx.allocator, '0');
            }
        }
    } else {
        const cut_u: usize = @intCast(want_len);
        var kept = try ctx.allocator.alloc(u8, cut_u);
        defer ctx.allocator.free(kept);
        for (0..cut_u) |i| kept[i] = if (i < combined_buf.items.len) combined_buf.items[i] else '0';
        var round_up = false;
        if (cut_u < combined_buf.items.len and combined_buf.items[cut_u] >= '5') round_up = true;
        if (round_up) {
            const inc = try incrementDigits(ctx.allocator, kept);
            defer ctx.allocator.free(inc);
            const new_int_len = @as(i64, @intCast(inc.len)) - precision;
            const ni: usize = @intCast(@max(@as(i64, 1), new_int_len));
            try result_buf.appendSlice(ctx.allocator, inc[0..ni]);
            if (precision > 0) {
                try result_buf.append(ctx.allocator, '.');
                try result_buf.appendSlice(ctx.allocator, inc[ni..]);
            }
        } else {
            const int_keep_len: usize = @intCast(dec_pos);
            try result_buf.appendSlice(ctx.allocator, kept[0..int_keep_len]);
            if (precision > 0) {
                try result_buf.append(ctx.allocator, '.');
                try result_buf.appendSlice(ctx.allocator, kept[int_keep_len..]);
            }
        }
    }

    const out = try signedResult(ctx.allocator, p.neg, result_buf.items);

    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

// ---------------- registration ----------------

pub const entries = .{
    .{ "bcadd", bcAdd },
    .{ "bcsub", bcSub },
    .{ "bcmul", bcMul },
    .{ "bcdiv", bcDiv },
    .{ "bcmod", bcMod },
    .{ "bcdivmod", bcDivmod },
    .{ "bcpow", bcPow },
    .{ "bcpowmod", bcPowmod },
    .{ "bcsqrt", bcSqrt },
    .{ "bccomp", bcComp },
    .{ "bcscale", bcScale },
    .{ "bcceil", bcCeil },
    .{ "bcfloor", bcFloor },
    .{ "bcround", bcRound },
};

// ---------------- BcMath\Number (PHP 8.4) ----------------
//
// an immutable arbitrary-precision decimal: `value` is the canonical digit
// string, `scale` its count of fractional digits. every operation is routed
// through the procedural natives above with the scale PHP picks: add/sub/mod
// use the larger operand scale, mul the sum, div/sqrt/negative pow compute
// ten extra digits and drop trailing zeros back down to the left operand's
// scale, positive pow multiplies the scale by the exponent

const number_class = "BcMath\\Number";

pub fn register(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = number_class, .is_final = true, .is_readonly = true, .native_binop = numberBinop };
    try def.properties.append(a, .{ .name = "value", .default = .{ .string = Value.String.borrowed("0") }, .has_default = true, .is_readonly = true, .type_str = "string" });
    try def.properties.append(a, .{ .name = "scale", .default = .{ .int = 0 }, .has_default = true, .is_readonly = true, .type_str = "int" });
    const methods = .{
        .{ "__construct", 1 }, .{ "add", 2 },     .{ "sub", 2 },        .{ "mul", 2 },         .{ "div", 2 },           .{ "mod", 2 },
        .{ "divmod", 2 },      .{ "powmod", 3 },  .{ "pow", 2 },        .{ "sqrt", 1 },        .{ "floor", 0 },         .{ "ceil", 0 },
        .{ "round", 2 },       .{ "compare", 2 }, .{ "__toString", 0 }, .{ "__serialize", 0 }, .{ "__unserialize", 1 },
    };
    inline for (methods) |m| try def.methods.put(a, m[0], .{ .name = m[0], .arity = m[1] });
    try vm.classes.put(a, number_class, def);
    const natives = .{
        .{ "__construct", numberConstruct },     .{ "add", numberAdd },         .{ "sub", numberSub },             .{ "mul", numberMul },
        .{ "div", numberDiv },                   .{ "mod", numberMod },         .{ "divmod", numberDivmod },       .{ "powmod", numberPowmod },
        .{ "pow", numberPow },                   .{ "sqrt", numberSqrt },       .{ "floor", numberFloor },         .{ "ceil", numberCeil },
        .{ "round", numberRound },               .{ "compare", numberCompare }, .{ "__toString", numberToString }, .{ "__serialize", numberSerialize },
        .{ "__unserialize", numberUnserialize },
    };
    inline for (natives) |n| try vm.native_fns.put(a, number_class ++ "::" ++ n[0], n[1]);
}

fn isNumberObject(v: Value) bool {
    return v == .object and std.mem.eql(u8, v.object.class_name, number_class);
}

fn numberThis(ctx: *NativeContext) ?*PhpObject {
    const this_v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (!isNumberObject(this_v)) return null;
    return this_v.object;
}

fn wellFormed(s: []const u8) bool {
    var i: usize = 0;
    if (i < s.len and (s[i] == '+' or s[i] == '-')) i += 1;
    var digits: usize = 0;
    while (i < s.len and std.ascii.isDigit(s[i])) : (i += 1) digits += 1;
    if (i < s.len and s[i] == '.') {
        i += 1;
        while (i < s.len and std.ascii.isDigit(s[i])) : (i += 1) digits += 1;
    }
    return i == s.len and digits > 0;
}

fn scaleOf(s: []const u8) usize {
    const dot = std.mem.indexOfScalar(u8, s, '.') orelse return 0;
    return s.len - dot - 1;
}

// canonical form: no plus sign, no leading zeros in the integer part, the
// fractional digits exactly as given, and no sign on zero
fn canonical(allocator: Allocator, raw: []const u8) ![]u8 {
    var s = raw;
    var neg = false;
    if (s.len > 0 and (s[0] == '+' or s[0] == '-')) {
        neg = s[0] == '-';
        s = s[1..];
    }
    const dot = std.mem.indexOfScalar(u8, s, '.');
    var int_part = if (dot) |d| s[0..d] else s;
    const frac_part = if (dot) |d| s[d + 1 ..] else "";
    while (int_part.len > 1 and int_part[0] == '0') int_part = int_part[1..];
    if (int_part.len == 0) int_part = "0";
    var nonzero = false;
    for (int_part) |c| if (c != '0') {
        nonzero = true;
    };
    for (frac_part) |c| if (c != '0') {
        nonzero = true;
    };
    var out = std.ArrayListUnmanaged(u8){};
    errdefer out.deinit(allocator);
    if (neg and nonzero) try out.append(allocator, '-');
    try out.appendSlice(allocator, int_part);
    if (frac_part.len > 0) {
        try out.append(allocator, '.');
        try out.appendSlice(allocator, frac_part);
    }
    return out.toOwnedSlice(allocator);
}

// drops trailing fractional zeros, never below `min_scale` digits
fn stripToScale(s: []const u8, min_scale: usize) []const u8 {
    const dot = std.mem.indexOfScalar(u8, s, '.') orelse return s;
    var end = s.len;
    while (end > dot + 1 + min_scale and s[end - 1] == '0') end -= 1;
    if (end == dot + 1) end = dot;
    return s[0..end];
}

fn throwNotWellFormed(ctx: *NativeContext, comptime method: []const u8, comptime arg: []const u8) RuntimeError {
    _ = ctx.vm.throwBuiltinException("ValueError", number_class ++ "::" ++ method ++ "(): Argument #1 ($" ++ arg ++ ") is not well-formed") catch {};
    return error.RuntimeError;
}

// the decimal string an operand contributes; owned by the caller
fn operandString(ctx: *NativeContext, v: Value, comptime method: []const u8, comptime arg: []const u8) RuntimeError![]u8 {
    switch (v) {
        .object => |obj| {
            if (!isNumberObject(v)) return throwNotWellFormed(ctx, method, arg);
            const val = obj.get("value");
            return try ctx.allocator.dupe(u8, if (val == .string) val.string.bytes() else "0");
        },
        .int => |i| return try std.fmt.allocPrint(ctx.allocator, "{d}", .{i}),
        .float => |f| return try std.fmt.allocPrint(ctx.allocator, "{d}", .{@as(i64, @intFromFloat(f))}),
        .bool => |b| return try ctx.allocator.dupe(u8, if (b) "1" else "0"),
        .string => |str| {
            if (str.len == 0) return try ctx.allocator.dupe(u8, "0");
            if (!wellFormed(str.bytes())) return throwNotWellFormed(ctx, method, arg);
            return try canonical(ctx.allocator, str.bytes());
        },
        else => return throwNotWellFormed(ctx, method, arg),
    }
}

fn makeNumber(ctx: *NativeContext, raw: []const u8) RuntimeError!*PhpObject {
    const obj = try ctx.createObject(number_class);
    try setNumber(ctx, obj, raw);
    return obj;
}

fn setNumber(ctx: *NativeContext, obj: *PhpObject, raw: []const u8) RuntimeError!void {
    const canon = try canonical(ctx.allocator, raw);
    defer ctx.allocator.free(canon);
    const owned = try Value.String.create(ctx.allocator, canon);
    defer owned.release();
    try obj.set(ctx.allocator, "value", .{ .string = owned });
    try obj.set(ctx.allocator, "scale", .{ .int = @intCast(scaleOf(canon)) });
}

fn explicitScale(args: []const Value, idx: usize) ?usize {
    if (args.len > idx and args[idx] == .int and args[idx].int >= 0) return @intCast(args[idx].int);
    return null;
}

// runs a procedural native on two decimal strings at a fixed scale and hands
// back the result string; released by the caller
fn runNative(ctx: *NativeContext, comptime native: anytype, a: []const u8, b: ?[]const u8, scale: usize) RuntimeError!Value.String {
    var args: [3]Value = .{ .{ .string = Value.String.borrowed(a) }, .{ .int = @intCast(scale) }, .null };
    var n: usize = 2;
    if (b) |bs| {
        args[1] = .{ .string = Value.String.borrowed(bs) };
        args[2] = .{ .int = @intCast(scale) };
        n = 3;
    }
    const result = try native(ctx, args[0..n]);
    if (result.value != .string) {
        if (result.value == .array) {
            // divmod hands back its pair through the array path
        }
        return error.RuntimeError;
    }
    return result.value.string;
}

const BinaryScale = enum { larger, sum, expand };

fn numberBinary(ctx: *NativeContext, this: *PhpObject, other: Value, args: []const Value, comptime method: []const u8, comptime native: anytype, comptime rule: BinaryScale) RuntimeError!NativeResult {
    const a = try operandString(ctx, .{ .object = this }, method, "num");
    defer ctx.allocator.free(a);
    const b = try operandString(ctx, other, method, "num");
    defer ctx.allocator.free(b);
    return NativeResult.borrowed(.{ .object = try binaryResult(ctx, a, b, explicitScale(args, 1), native, rule) });
}

fn binaryResult(ctx: *NativeContext, a: []const u8, b: []const u8, explicit: ?usize, comptime native: anytype, comptime rule: BinaryScale) RuntimeError!*PhpObject {
    const sa = scaleOf(a);
    const sb = scaleOf(b);
    const natural: usize = switch (rule) {
        .larger => @max(sa, sb),
        .sum => sa + sb,
        .expand => sa + 10,
    };
    const scale = explicit orelse natural;
    const result = try runNative(ctx, native, a, b, scale);
    defer result.release();
    const bytes = if (explicit == null and rule == .expand) stripToScale(result.bytes(), sa) else result.bytes();
    return makeNumber(ctx, bytes);
}

fn numberConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = numberThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    const s = try operandString(ctx, args[0], "__construct", "num");
    defer ctx.allocator.free(s);
    try setNumber(ctx, this, s);
    return NativeResult.scalar(.null);
}

fn numberAdd(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = numberThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    return numberBinary(ctx, this, args[0], args, "add", bcAdd, .larger);
}

fn numberSub(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = numberThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    return numberBinary(ctx, this, args[0], args, "sub", bcSub, .larger);
}

fn numberMul(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = numberThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    return numberBinary(ctx, this, args[0], args, "mul", bcMul, .sum);
}

fn numberDiv(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = numberThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    return numberBinary(ctx, this, args[0], args, "div", bcDiv, .expand);
}

fn numberMod(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = numberThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    return numberBinary(ctx, this, args[0], args, "mod", bcMod, .larger);
}

fn numberDivmod(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = numberThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    const a = try operandString(ctx, .{ .object = this }, "divmod", "num");
    defer ctx.allocator.free(a);
    const b = try operandString(ctx, args[0], "divmod", "num");
    defer ctx.allocator.free(b);
    const scale = explicitScale(args, 1) orelse @max(scaleOf(a), scaleOf(b));
    var call_args: [3]Value = .{ .{ .string = Value.String.borrowed(a) }, .{ .string = Value.String.borrowed(b) }, .{ .int = @intCast(scale) } };
    const pair = try bcDivmod(ctx, &call_args);
    if (pair.value != .array) return error.RuntimeError;
    const out = try ctx.createArray();
    for (pair.value.array.entries.items) |entry| {
        if (entry.value != .string) continue;
        try out.append(ctx.allocator, .{ .object = try makeNumber(ctx, entry.value.string.bytes()) });
    }
    return NativeResult.borrowed(.{ .array = out });
}

fn integralString(s: []const u8) bool {
    return scaleOf(stripToScale(s, 0)) == 0;
}

fn numberPow(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = numberThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    const a = try operandString(ctx, .{ .object = this }, "pow", "exponent");
    defer ctx.allocator.free(a);
    const e = try operandString(ctx, args[0], "pow", "exponent");
    defer ctx.allocator.free(e);
    if (!integralString(e)) {
        _ = ctx.vm.throwBuiltinException("ValueError", number_class ++ "::pow(): Argument #1 ($exponent) exponent cannot have a fractional part") catch {};
        return error.RuntimeError;
    }
    const exp = std.fmt.parseInt(i64, stripToScale(e, 0), 10) catch return error.RuntimeError;
    return NativeResult.borrowed(.{ .object = try powResult(ctx, a, exp, explicitScale(args, 1)) });
}

fn powResult(ctx: *NativeContext, a: []const u8, exp: i64, explicit: ?usize) RuntimeError!*PhpObject {
    const sa = scaleOf(a);
    const natural: usize = if (exp > 0) sa * @as(usize, @intCast(exp)) else sa + 10;
    const scale = explicit orelse natural;
    var exp_buf: [24]u8 = undefined;
    const e = std.fmt.bufPrint(&exp_buf, "{d}", .{exp}) catch return error.RuntimeError;
    const result = try runNative(ctx, bcPow, a, e, scale);
    defer result.release();
    const bytes = if (explicit == null and exp <= 0) stripToScale(result.bytes(), 0) else result.bytes();
    return makeNumber(ctx, bytes);
}

fn numberPowmod(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = numberThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 2) return NativeResult.scalar(.null);
    const a = try operandString(ctx, .{ .object = this }, "powmod", "exponent");
    defer ctx.allocator.free(a);
    const e = try operandString(ctx, args[0], "powmod", "exponent");
    defer ctx.allocator.free(e);
    const m = try operandString(ctx, args[1], "powmod", "modulus");
    defer ctx.allocator.free(m);
    if (!integralString(a)) {
        _ = ctx.vm.throwBuiltinException("ValueError", "Base number cannot have a fractional part") catch {};
        return error.RuntimeError;
    }
    const scale = explicitScale(args, 2) orelse 0;
    var call_args: [4]Value = .{ .{ .string = Value.String.borrowed(a) }, .{ .string = Value.String.borrowed(e) }, .{ .string = Value.String.borrowed(m) }, .{ .int = @intCast(scale) } };
    const result = try bcPowmod(ctx, &call_args);
    if (result.value != .string) return error.RuntimeError;
    defer result.value.string.release();
    return NativeResult.borrowed(.{ .object = try makeNumber(ctx, result.value.string.bytes()) });
}

fn numberSqrt(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = numberThis(ctx) orelse return NativeResult.scalar(.null);
    const a = try operandString(ctx, .{ .object = this }, "sqrt", "scale");
    defer ctx.allocator.free(a);
    const explicit = explicitScale(args, 0);
    const sa = scaleOf(a);
    const result = try runNative(ctx, bcSqrt, a, null, explicit orelse sa + 10);
    defer result.release();
    const bytes = if (explicit == null) stripToScale(result.bytes(), sa) else result.bytes();
    return NativeResult.borrowed(.{ .object = try makeNumber(ctx, bytes) });
}

fn numberFloor(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return numberUnary(ctx, bcFloor);
}

fn numberCeil(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return numberUnary(ctx, bcCeil);
}

fn numberUnary(ctx: *NativeContext, comptime native: anytype) RuntimeError!NativeResult {
    const this = numberThis(ctx) orelse return NativeResult.scalar(.null);
    const a = try operandString(ctx, .{ .object = this }, "floor", "num");
    defer ctx.allocator.free(a);
    var call_args: [1]Value = .{.{ .string = Value.String.borrowed(a) }};
    const result = try native(ctx, &call_args);
    if (result.value != .string) return error.RuntimeError;
    defer result.value.string.release();
    return NativeResult.borrowed(.{ .object = try makeNumber(ctx, result.value.string.bytes()) });
}

const RoundMode = enum { half_away, half_towards, half_even, half_odd, towards_zero, away_from_zero, negative_inf, positive_inf };

fn roundModeOf(v: Value) RoundMode {
    if (v == .object and std.mem.eql(u8, v.object.class_name, "RoundingMode")) {
        const name = v.object.get("name");
        if (name == .string) {
            const n = name.string.bytes();
            const table = .{ .{ "HalfAwayFromZero", RoundMode.half_away }, .{ "HalfTowardsZero", RoundMode.half_towards }, .{ "HalfEven", RoundMode.half_even }, .{ "HalfOdd", RoundMode.half_odd }, .{ "TowardsZero", RoundMode.towards_zero }, .{ "AwayFromZero", RoundMode.away_from_zero }, .{ "NegativeInfinity", RoundMode.negative_inf }, .{ "PositiveInfinity", RoundMode.positive_inf } };
            inline for (table) |entry| if (std.mem.eql(u8, n, entry[0])) return entry[1];
        }
    }
    if (v == .int) return switch (v.int) {
        2 => .half_towards,
        3 => .half_even,
        4 => .half_odd,
        else => .half_away,
    };
    return .half_away;
}

// rounds the canonical decimal `s` to `precision` fractional digits (negative
// precision rounds integer positions) by inspecting the digits past the cut
fn roundDecimal(allocator: Allocator, s: []const u8, precision: i64, mode: RoundMode) ![]u8 {
    const neg = s.len > 0 and s[0] == '-';
    const body = if (neg) s[1..] else s;
    const dot = std.mem.indexOfScalar(u8, body, '.');
    const int_part = if (dot) |d| body[0..d] else body;
    const frac_part = if (dot) |d| body[d + 1 ..] else "";
    var digits = std.ArrayListUnmanaged(u8){};
    defer digits.deinit(allocator);
    try digits.appendSlice(allocator, int_part);
    try digits.appendSlice(allocator, frac_part);
    // cut is the count of digits kept from the front; it may run past either end
    const cut_signed: i64 = @as(i64, @intCast(int_part.len)) + precision;
    const cut: usize = @intCast(@max(cut_signed, 0));
    var kept = std.ArrayListUnmanaged(u8){};
    defer kept.deinit(allocator);
    if (cut <= digits.items.len) {
        try kept.appendSlice(allocator, digits.items[0..cut]);
    } else {
        try kept.appendSlice(allocator, digits.items);
        try kept.appendNTimes(allocator, '0', cut - digits.items.len);
    }
    const rest = if (cut < digits.items.len) digits.items[cut..] else "";
    var rest_nonzero = false;
    for (rest) |c| if (c != '0') {
        rest_nonzero = true;
    };
    const first: u8 = if (rest.len > 0) rest[0] else '0';
    var tail_nonzero = false;
    if (rest.len > 1) for (rest[1..]) |c| if (c != '0') {
        tail_nonzero = true;
    };
    const above_half = first > '5' or (first == '5' and tail_nonzero);
    const exactly_half = first == '5' and !tail_nonzero;
    const last_digit: u8 = if (kept.items.len > 0) kept.items[kept.items.len - 1] else '0';
    const last_odd = (last_digit - '0') % 2 == 1;
    const bump = switch (mode) {
        .half_away => above_half or exactly_half,
        .half_towards => above_half,
        .half_even => above_half or (exactly_half and last_odd),
        .half_odd => above_half or (exactly_half and !last_odd),
        .towards_zero => false,
        .away_from_zero => rest_nonzero,
        .negative_inf => neg and rest_nonzero,
        .positive_inf => !neg and rest_nonzero,
    };
    if (bump) {
        var i: usize = kept.items.len;
        var carry = true;
        while (carry and i > 0) {
            i -= 1;
            if (kept.items[i] == '9') {
                kept.items[i] = '0';
            } else {
                kept.items[i] += 1;
                carry = false;
            }
        }
        if (carry) try kept.insert(allocator, 0, '1');
    }
    // kept digits end `precision` places after the point; rebuild the string
    var out = std.ArrayListUnmanaged(u8){};
    errdefer out.deinit(allocator);
    if (neg) try out.append(allocator, '-');
    if (precision <= 0) {
        try out.appendSlice(allocator, if (kept.items.len == 0) "0" else kept.items);
        try out.appendNTimes(allocator, '0', @intCast(-precision));
    } else {
        const frac_len: usize = @intCast(precision);
        if (kept.items.len <= frac_len) {
            try out.append(allocator, '0');
            try out.append(allocator, '.');
            try out.appendNTimes(allocator, '0', frac_len - kept.items.len);
            try out.appendSlice(allocator, kept.items);
        } else {
            try out.appendSlice(allocator, kept.items[0 .. kept.items.len - frac_len]);
            try out.append(allocator, '.');
            try out.appendSlice(allocator, kept.items[kept.items.len - frac_len ..]);
        }
    }
    return out.toOwnedSlice(allocator);
}

fn numberRound(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = numberThis(ctx) orelse return NativeResult.scalar(.null);
    const a = try operandString(ctx, .{ .object = this }, "round", "precision");
    defer ctx.allocator.free(a);
    const precision: i64 = if (args.len > 0 and args[0] == .int) args[0].int else 0;
    const mode = if (args.len > 1) roundModeOf(args[1]) else RoundMode.half_away;
    const rounded = try roundDecimal(ctx.allocator, a, precision, mode);
    defer ctx.allocator.free(rounded);
    return NativeResult.borrowed(.{ .object = try makeNumber(ctx, rounded) });
}

fn numberCompare(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = numberThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    const a = try operandString(ctx, .{ .object = this }, "compare", "num");
    defer ctx.allocator.free(a);
    const b = try operandString(ctx, args[0], "compare", "num");
    defer ctx.allocator.free(b);
    return NativeResult.scalar(.{ .int = try compareStrings(ctx, a, b, explicitScale(args, 1)) });
}

fn compareStrings(ctx: *NativeContext, a: []const u8, b: []const u8, explicit: ?usize) RuntimeError!i64 {
    const scale = explicit orelse @max(scaleOf(a), scaleOf(b));
    var call_args: [3]Value = .{ .{ .string = Value.String.borrowed(a) }, .{ .string = Value.String.borrowed(b) }, .{ .int = @intCast(scale) } };
    const result = try bcComp(ctx, &call_args);
    return if (result.value == .int) result.value.int else 0;
}

fn numberToString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = numberThis(ctx) orelse return NativeResult.literal("");
    return NativeResult.share(this.get("value"));
}

fn numberSerialize(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = numberThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("value") }, this.get("value"));
    return NativeResult.borrowed(.{ .array = arr });
}

fn numberUnserialize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = numberThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .array) return NativeResult.scalar(.null);
    const v = args[0].array.get(.{ .string = Value.String.borrowed("value") });
    if (v == .string and wellFormed(v.string.bytes())) try setNumber(ctx, this, v.string.bytes());
    return NativeResult.scalar(.null);
}

// operator overloading: the Number side supplies the semantics, the other
// operand may be a Number, an int, or a numeric string. anything else is
// left to the VM's ordinary TypeError
fn numberBinop(ctx: *NativeContext, op: vm_mod.NativeBinop, a: Value, b: Value) RuntimeError!?Value {
    const supported = struct {
        fn ok(v: Value) bool {
            return isNumberObject(v) or v == .int or v == .string or v == .float or v == .bool;
        }
    };
    if (!supported.ok(a)) return null;
    if (op != .negate and !supported.ok(b)) return null;
    const sa = try operandString(ctx, a, "add", "num");
    defer ctx.allocator.free(sa);
    switch (op) {
        .negate => {
            const result = try binaryResult(ctx, "0", sa, null, bcSub, .larger);
            return .{ .object = result };
        },
        .compare => {
            const sb = try operandString(ctx, b, "compare", "num");
            defer ctx.allocator.free(sb);
            return .{ .int = try compareStrings(ctx, sa, sb, null) };
        },
        .pow => {
            const sb = try operandString(ctx, b, "pow", "exponent");
            defer ctx.allocator.free(sb);
            if (!integralString(sb)) {
                _ = ctx.vm.throwBuiltinException("ValueError", number_class ++ "::pow(): Argument #1 ($exponent) exponent cannot have a fractional part") catch {};
                return error.RuntimeError;
            }
            const exp = std.fmt.parseInt(i64, stripToScale(sb, 0), 10) catch return error.RuntimeError;
            return .{ .object = try powResult(ctx, sa, exp, null) };
        },
        else => {
            const sb = try operandString(ctx, b, "add", "num");
            defer ctx.allocator.free(sb);
            const result = switch (op) {
                .add => try binaryResult(ctx, sa, sb, null, bcAdd, .larger),
                .sub => try binaryResult(ctx, sa, sb, null, bcSub, .larger),
                .mul => try binaryResult(ctx, sa, sb, null, bcMul, .sum),
                .div => try binaryResult(ctx, sa, sb, null, bcDiv, .expand),
                .mod => try binaryResult(ctx, sa, sb, null, bcMod, .larger),
                else => unreachable,
            };
            return .{ .object = result };
        },
    }
}
