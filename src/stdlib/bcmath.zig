const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
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

fn formatBc(allocator: Allocator, n: BcNum, target_scale: usize) ![]const u8 {
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

    // make a' = a * 10^(target_scale + b.scale - a.scale) (integer), b' = b (integer)
    const extra_a: usize = target_scale + b.scale - a.scale + 1;

    var num_digits = std.ArrayListUnmanaged(u8){};
    defer num_digits.deinit(allocator);
    try num_digits.appendSlice(allocator, a.digits.items);
    var i: usize = 0;
    while (i < extra_a) : (i += 1) try num_digits.append(allocator, 0);

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
        .string => |s| s,
        else => null,
    };
}

fn returnStr(ctx: *NativeContext, s: []const u8) !Value {
    const owned = try ctx.allocator.dupe(u8, s);
    try ctx.strings.append(ctx.allocator, owned);
    return .{ .string = owned };
}

fn bcAdd(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const sa = argToString(args, 0) orelse return .null;
    const sb = argToString(args, 1) orelse return .null;
    const scale = resolveScale(args, 2);
    var a = try parseBc(ctx.allocator, sa);
    defer a.deinit(ctx.allocator);
    var b = try parseBc(ctx.allocator, sb);
    defer b.deinit(ctx.allocator);
    var r = try bcAddInternal(ctx.allocator, a, b);
    defer r.deinit(ctx.allocator);
    const out = try formatBc(ctx.allocator, r, scale);
    defer ctx.allocator.free(out);
    return try returnStr(ctx, out);
}

fn bcSub(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const sa = argToString(args, 0) orelse return .null;
    const sb = argToString(args, 1) orelse return .null;
    const scale = resolveScale(args, 2);
    var a = try parseBc(ctx.allocator, sa);
    defer a.deinit(ctx.allocator);
    var b = try parseBc(ctx.allocator, sb);
    defer b.deinit(ctx.allocator);
    var r = try bcSubInternal(ctx.allocator, a, b);
    defer r.deinit(ctx.allocator);
    const out = try formatBc(ctx.allocator, r, scale);
    defer ctx.allocator.free(out);
    return try returnStr(ctx, out);
}

fn bcMul(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const sa = argToString(args, 0) orelse return .null;
    const sb = argToString(args, 1) orelse return .null;
    const scale = resolveScale(args, 2);
    var a = try parseBc(ctx.allocator, sa);
    defer a.deinit(ctx.allocator);
    var b = try parseBc(ctx.allocator, sb);
    defer b.deinit(ctx.allocator);
    var r = try bcMulInternal(ctx.allocator, a, b);
    defer r.deinit(ctx.allocator);
    const out = try formatBc(ctx.allocator, r, scale);
    defer ctx.allocator.free(out);
    return try returnStr(ctx, out);
}

fn bcDiv(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const sa = argToString(args, 0) orelse return .null;
    const sb = argToString(args, 1) orelse return .null;
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
        defer ctx.allocator.free(out);
        return try returnStr(ctx, out);
    }
    return .null;
}

fn bcMod(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const sa = argToString(args, 0) orelse return .null;
    const sb = argToString(args, 1) orelse return .null;
    const scale = resolveScale(args, 2);
    var a = try parseBc(ctx.allocator, sa);
    defer a.deinit(ctx.allocator);
    var b = try parseBc(ctx.allocator, sb);
    defer b.deinit(ctx.allocator);
    if (b.isZero()) {
        try ctx.vm.setPendingException("DivisionByZeroError", "Modulo by zero");
        return .null;
    }
    // mod = a - (a / b truncated to scale=0) * b. then format to target scale
    var q_opt = try bcDivInternal(ctx.allocator, a, b, 0);
    if (q_opt == null) return .null;
    defer q_opt.?.deinit(ctx.allocator);
    var qb = try bcMulInternal(ctx.allocator, q_opt.?, b);
    defer qb.deinit(ctx.allocator);
    var r = try bcSubInternal(ctx.allocator, a, qb);
    defer r.deinit(ctx.allocator);
    const out = try formatBc(ctx.allocator, r, scale);
    defer ctx.allocator.free(out);
    return try returnStr(ctx, out);
}

fn bcDivmod(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const sa = argToString(args, 0) orelse return .null;
    const sb = argToString(args, 1) orelse return .null;
    const scale = resolveScale(args, 2);
    var a = try parseBc(ctx.allocator, sa);
    defer a.deinit(ctx.allocator);
    var b = try parseBc(ctx.allocator, sb);
    defer b.deinit(ctx.allocator);
    if (b.isZero()) {
        try ctx.vm.setPendingException("DivisionByZeroError", "Division by zero");
        return .null;
    }
    var q_opt = try bcDivInternal(ctx.allocator, a, b, 0);
    if (q_opt == null) return .null;
    const q = q_opt.?;
    defer @constCast(&q).deinit(ctx.allocator);
    var qb = try bcMulInternal(ctx.allocator, q, b);
    defer qb.deinit(ctx.allocator);
    var r = try bcSubInternal(ctx.allocator, a, qb);
    defer r.deinit(ctx.allocator);
    _ = &q_opt;

    const q_str = try formatBc(ctx.allocator, q, 0);
    defer ctx.allocator.free(q_str);
    const r_str = try formatBc(ctx.allocator, r, scale);
    defer ctx.allocator.free(r_str);

    const q_owned = try ctx.allocator.dupe(u8, q_str);
    try ctx.vm.strings.append(ctx.allocator, q_owned);
    const r_owned = try ctx.allocator.dupe(u8, r_str);
    try ctx.vm.strings.append(ctx.allocator, r_owned);

    const arr = try ctx.allocator.create(@import("../runtime/value.zig").PhpArray);
    arr.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, arr);
    try arr.append(ctx.allocator, .{ .string = q_owned });
    try arr.append(ctx.allocator, .{ .string = r_owned });
    return .{ .array = arr };
}

fn bcPow(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const sa = argToString(args, 0) orelse return .null;
    const sb = argToString(args, 1) orelse return .null;
    const scale = resolveScale(args, 2);
    var a = try parseBc(ctx.allocator, sa);
    defer a.deinit(ctx.allocator);
    // exponent must be a non-negative integer (PHP allows negative but truncates)
    const exp_str = sb;
    var exp: i64 = std.fmt.parseInt(i64, std.mem.trim(u8, exp_str, " \t"), 10) catch return .null;
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
            return .null;
        };
        defer inv.deinit(ctx.allocator);
        r.deinit(ctx.allocator);
        const out = try formatBc(ctx.allocator, inv, scale);
        defer ctx.allocator.free(out);
        return try returnStr(ctx, out);
    }

    defer r.deinit(ctx.allocator);
    const out = try formatBc(ctx.allocator, r, scale);
    defer ctx.allocator.free(out);
    return try returnStr(ctx, out);
}

// modular exponentiation: base^exp mod mod. arbitrary precision via the same
// BcNum primitives bcpow uses, but exp is also a BcNum so it can be larger
// than i64. PHP truncates fractional bits of all three args.
fn bcPowmod(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const sa = argToString(args, 0) orelse return .null;
    const sb = argToString(args, 1) orelse return .null;
    const sm = argToString(args, 2) orelse return .null;
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
        return .null;
    }
    if (exp.sign < 0) {
        try ctx.vm.setPendingException("ValueError", "bcpowmod(): Argument #2 ($exponent) must be greater than or equal to 0");
        return .null;
    }

    // result = 1
    var result = try parseBc(ctx.allocator, "1");
    errdefer result.deinit(ctx.allocator);

    // base = base mod mod (so subsequent multiplies stay bounded)
    {
        var q = (try bcDivInternal(ctx.allocator, base, mod, 0)) orelse return .null;
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
            var q2 = (try bcDivInternal(ctx.allocator, exp, two, 0)) orelse return .null;
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
            var q = (try bcDivInternal(ctx.allocator, rb, mod, 0)) orelse return .null;
            defer q.deinit(ctx.allocator);
            var qm = try bcMulInternal(ctx.allocator, q, mod);
            defer qm.deinit(ctx.allocator);
            const new_r = try bcSubInternal(ctx.allocator, rb, qm);
            result.deinit(ctx.allocator);
            result = new_r;
        }

        // exp = exp / 2
        {
            const new_exp = (try bcDivInternal(ctx.allocator, exp, two, 0)) orelse return .null;
            exp.deinit(ctx.allocator);
            exp = new_exp;
        }
        if (exp.isZero()) break;

        // base = (base * base) mod mod
        {
            var bb = try bcMulInternal(ctx.allocator, base, base);
            defer bb.deinit(ctx.allocator);
            var q = (try bcDivInternal(ctx.allocator, bb, mod, 0)) orelse return .null;
            defer q.deinit(ctx.allocator);
            var qm = try bcMulInternal(ctx.allocator, q, mod);
            defer qm.deinit(ctx.allocator);
            const new_base = try bcSubInternal(ctx.allocator, bb, qm);
            base.deinit(ctx.allocator);
            base = new_base;
        }
    }

    const out = try formatBc(ctx.allocator, result, scale);
    defer ctx.allocator.free(out);
    result.deinit(ctx.allocator);
    return try returnStr(ctx, out);
}

fn bcSqrt(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const sa = argToString(args, 0) orelse return .null;
    const scale = resolveScale(args, 1);
    var a = try parseBc(ctx.allocator, sa);
    defer a.deinit(ctx.allocator);
    if (a.sign < 0) return .null;
    if (a.isZero()) {
        const z = try makeZeroString(ctx.allocator, scale);
        defer ctx.allocator.free(z);
        return try returnStr(ctx, z);
    }

    // newton's method on the full-precision string. work with scale+2 internal precision
    const work_scale = scale + 2;
    var x = try parseBc(ctx.allocator, sa);
    defer x.deinit(ctx.allocator);

    var iters: usize = 0;
    while (iters < 200) : (iters += 1) {
        // x_next = (x + a/x) / 2
        var ax = (try bcDivInternal(ctx.allocator, a, x, work_scale)) orelse return .null;
        defer ax.deinit(ctx.allocator);
        var sum = try bcAddInternal(ctx.allocator, x, ax);
        defer sum.deinit(ctx.allocator);
        var two = try parseBc(ctx.allocator, "2");
        defer two.deinit(ctx.allocator);
        const next = (try bcDivInternal(ctx.allocator, sum, two, work_scale)) orelse return .null;
        // check convergence: if |next - x| < 10^-work_scale
        var diff = try bcSubInternal(ctx.allocator, next, x);
        defer diff.deinit(ctx.allocator);
        const converged = diff.isZero();
        x.deinit(ctx.allocator);
        x = next;
        if (converged) break;
    }
    const out = try formatBc(ctx.allocator, x, scale);
    defer ctx.allocator.free(out);
    return try returnStr(ctx, out);
}

fn makeZeroString(allocator: Allocator, scale: usize) ![]const u8 {
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

fn bcComp(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const sa = argToString(args, 0) orelse return .null;
    const sb = argToString(args, 1) orelse return .null;
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
    return .{ .int = @intCast(cmpFull(ta, tb)) };
}

fn bcScale(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const prev = currentScale();
    if (args.len > 0 and args[0] == .int and args[0].int >= 0) {
        setScale(@intCast(args[0].int));
        return .{ .int = @intCast(prev) };
    }
    return .{ .int = @intCast(prev) };
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

fn bcCeil(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const s = argToString(args, 0) orelse return .null;
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
    defer ctx.allocator.free(result);
    return try returnStr(ctx, result);
}

fn bcFloor(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const s = argToString(args, 0) orelse return .null;
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
    defer ctx.allocator.free(result);
    return try returnStr(ctx, result);
}

fn bcRound(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const s = argToString(args, 0) orelse return .null;
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
    defer ctx.allocator.free(out);
    return try returnStr(ctx, out);
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
