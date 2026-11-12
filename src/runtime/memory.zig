const std = @import("std");
const Allocator = std.mem.Allocator;

// php's view of a VM's memory: the bytes its allocator hands out, counted
// from a baseline (what the VM holds before a script or request runs), and
// memory_limit enforced on that count. an allocation that would cross the
// limit fails, and so does every one after it until the VM reports the
// exhaustion, so a swallowed failure cannot let a script run on unlimited
// the allocator under every account: memory that outlives the VM that
// allocated it, like values in flight between threads, comes from here
pub fn root(allocator: Allocator) Allocator {
    var current = allocator;
    while (current.vtable == &MemoryAccount.vtable) {
        const account: *MemoryAccount = @ptrCast(@alignCast(current.ptr));
        current = account.parent;
    }
    return current;
}

pub const MemoryAccount = struct {
    parent: Allocator,
    // frees can come from other threads when values cross into worker pools
    used: std.atomic.Value(usize) = .init(0),
    peak: std.atomic.Value(usize) = .init(0),
    baseline: usize = 0,
    // bytes allowed above the baseline; 0 is unlimited
    limit: usize = 0,
    // the size of the allocation the limit refused
    refused: ?usize = null,
    // set while the VM reports the exhaustion, which needs memory of its own
    reporting: bool = false,

    const vtable: Allocator.VTable = .{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };

    pub fn allocator(self: *MemoryAccount) Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    // bytes in use above the baseline
    pub fn usage(self: *const MemoryAccount) usize {
        return self.used.load(.monotonic) -| self.baseline;
    }

    pub fn peakUsage(self: *const MemoryAccount) usize {
        return self.peak.load(.monotonic) -| self.baseline;
    }

    pub fn resetPeak(self: *MemoryAccount) void {
        self.peak.store(self.used.load(.monotonic), .monotonic);
    }

    // start counting from what is held now, as a fresh request does
    pub fn rebase(self: *MemoryAccount) void {
        self.baseline = self.used.load(.monotonic);
        self.resetPeak();
        self.refused = null;
        self.reporting = false;
    }

    // memory the VM commits itself rather than through the allocator (its
    // call stack regions); false when memory_limit refuses it
    pub fn chargeExternal(self: *MemoryAccount, len: usize) bool {
        if (!self.admit(len)) return false;
        self.charge(len);
        return true;
    }

    fn admit(self: *MemoryAccount, len: usize) bool {
        if (self.limit == 0 or self.reporting) return true;
        if (self.refused == null and self.usage() + len <= self.limit) return true;
        if (self.refused == null) self.refused = len;
        return false;
    }

    fn charge(self: *MemoryAccount, len: usize) void {
        const now = self.used.fetchAdd(len, .monotonic) + len;
        _ = self.peak.fetchMax(now, .monotonic);
    }

    fn discharge(self: *MemoryAccount, len: usize) void {
        var current = self.used.load(.monotonic);
        while (self.used.cmpxchgWeak(current, current -| len, .monotonic, .monotonic)) |seen| current = seen;
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *MemoryAccount = @ptrCast(@alignCast(ctx));
        if (!self.admit(len)) return null;
        const ptr = self.parent.rawAlloc(len, alignment, ret_addr) orelse return null;
        self.charge(len);
        return ptr;
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *MemoryAccount = @ptrCast(@alignCast(ctx));
        if (new_len > memory.len and !self.admit(new_len - memory.len)) return false;
        if (!self.parent.rawResize(memory, alignment, new_len, ret_addr)) return false;
        self.adjust(memory.len, new_len);
        return true;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *MemoryAccount = @ptrCast(@alignCast(ctx));
        if (new_len > memory.len and !self.admit(new_len - memory.len)) return null;
        const ptr = self.parent.rawRemap(memory, alignment, new_len, ret_addr) orelse return null;
        self.adjust(memory.len, new_len);
        return ptr;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *MemoryAccount = @ptrCast(@alignCast(ctx));
        self.parent.rawFree(memory, alignment, ret_addr);
        self.discharge(memory.len);
    }

    fn adjust(self: *MemoryAccount, old_len: usize, new_len: usize) void {
        if (new_len > old_len) self.charge(new_len - old_len) else self.discharge(old_len - new_len);
    }
};

// zend_ini_parse_quantity: a number (decimal, or 0x/0o/0b prefixed) whose
// last character may be a K, M or G multiplier. what php warns about comes
// back in `problem`; the value is what php uses anyway
pub const Quantity = struct {
    value: i64,
    problem: ?Problem = null,

    pub const Problem = union(enum) {
        no_digits,
        unknown_multiplier: struct { multiplier: u8, used: []const u8 },
        out_of_range,
    };
};

pub fn parseQuantity(text: []const u8) Quantity {
    const trimmed = std.mem.trim(u8, text, " \t\n\r\x0b\x0c");
    if (trimmed.len == 0) return .{ .value = 0 };
    var i: usize = 0;
    var negative = false;
    if (trimmed[0] == '-' or trimmed[0] == '+') {
        negative = trimmed[0] == '-';
        i = 1;
    }
    var base: u8 = 10;
    if (i + 1 < trimmed.len and trimmed[i] == '0') {
        switch (trimmed[i + 1]) {
            'x', 'X' => base = 16,
            'o', 'O' => base = 8,
            'b', 'B' => base = 2,
            else => {},
        }
        if (base != 10) i += 2;
    }
    const digits_start = i;
    var magnitude: u64 = 0;
    var overflow = false;
    while (i < trimmed.len) : (i += 1) {
        const d = std.fmt.charToDigit(trimmed[i], base) catch break;
        const next = @mulWithOverflow(magnitude, base);
        const sum = @addWithOverflow(next[0], d);
        overflow = overflow or next[1] != 0 or sum[1] != 0;
        magnitude = sum[0];
    }
    if (i == digits_start) return .{ .value = 0, .problem = .no_digits };
    var value: i64 = @bitCast(if (negative) 0 -% magnitude else magnitude);
    const last = trimmed[trimmed.len - 1];
    if (i == trimmed.len) return .{ .value = value, .problem = if (overflow) .out_of_range else null };
    const shift: u6 = switch (last) {
        'k', 'K' => 10,
        'm', 'M' => 20,
        'g', 'G' => 30,
        else => return .{ .value = value, .problem = .{ .unknown_multiplier = .{ .multiplier = last, .used = trimmed[0..i] } } },
    };
    const scaled = @shlWithOverflow(value, shift);
    value = scaled[0];
    overflow = overflow or scaled[1] != 0;
    return .{ .value = value, .problem = if (overflow) .out_of_range else null };
}

// php's zend_ini_parse_quantity_internal, with its messages: the value php
// uses and, when it complains, what it says (allocated)
pub const QuantityReport = struct { value: u64, message: ?[]u8 = null };

fn isQuantitySpace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == 0x0b or c == 0x0c;
}

// smart_str_append_escaped
fn appendEscaped(out: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, s: []const u8) !void {
    for (s) |c| {
        if (c < 32 or c == '\\' or c > 126) {
            try out.append(allocator, '\\');
            switch (c) {
                '\n' => try out.append(allocator, 'n'),
                '\r' => try out.append(allocator, 'r'),
                '\t' => try out.append(allocator, 't'),
                0x0c => try out.append(allocator, 'f'),
                0x0b => try out.append(allocator, 'v'),
                '\\' => try out.append(allocator, '\\'),
                27 => try out.append(allocator, 'e'),
                else => {
                    const hex = "0123456789ABCDEF";
                    try out.appendSlice(allocator, &.{ 'x', hex[c >> 4], hex[c & 0xf] });
                },
            }
        } else try out.append(allocator, c);
    }
}

fn quantityMessage(allocator: std.mem.Allocator, comptime fmt: []const u8, parts: anytype) ![]u8 {
    var escaped: [parts.len]std.ArrayListUnmanaged(u8) = @splat(.empty);
    defer for (&escaped) |*e| e.deinit(allocator);
    var args: [parts.len][]const u8 = undefined;
    inline for (parts, 0..) |p, k| {
        try appendEscaped(&escaped[k], allocator, p);
        args[k] = escaped[k].items;
    }
    return switch (parts.len) {
        1 => std.fmt.allocPrint(allocator, fmt, .{args[0]}),
        2 => std.fmt.allocPrint(allocator, fmt, .{ args[0], args[1] }),
        else => std.fmt.allocPrint(allocator, fmt, .{ args[0], args[1], args[2] }),
    };
}

// strtoul: digits of `base` (0 picks it from a 0x or 0 prefix) after
// optional whitespace and sign; the end, and whether it overflowed
fn strtoul(s: []const u8, base_in: u8) struct { value: u64, end: usize, overflow: bool } {
    var i: usize = 0;
    while (i < s.len and isQuantitySpace(s[i])) i += 1;
    var negative = false;
    if (i < s.len and (s[i] == '+' or s[i] == '-')) {
        negative = s[i] == '-';
        i += 1;
    }
    var base = base_in;
    if ((base == 0 or base == 16) and i + 2 < s.len + 1 and i + 1 < s.len and s[i] == '0' and (s[i + 1] == 'x' or s[i + 1] == 'X') and i + 2 < s.len and std.ascii.isHex(s[i + 2])) {
        i += 2;
        base = 16;
    } else if (base == 0) {
        base = if (i < s.len and s[i] == '0') 8 else 10;
    }
    const start = i;
    var value: u64 = 0;
    var overflow = false;
    while (i < s.len) : (i += 1) {
        const d = std.fmt.charToDigit(s[i], base) catch break;
        const m = @mulWithOverflow(value, base);
        const a = @addWithOverflow(m[0], d);
        if (m[1] != 0 or a[1] != 0) overflow = true;
        value = a[0];
    }
    if (i == start) return .{ .value = 0, .end = 0, .overflow = false };
    if (overflow) value = std.math.maxInt(u64);
    if (negative and !overflow) value = 0 -% value;
    return .{ .value = value, .end = i, .overflow = overflow };
}

pub fn reportQuantity(allocator: std.mem.Allocator, text: []const u8, signed: bool) !QuantityReport {
    var digits: usize = 0;
    var str_end: usize = text.len;
    while (digits < str_end and isQuantitySpace(text[digits])) digits += 1;
    while (digits < str_end and isQuantitySpace(text[str_end - 1])) str_end -= 1;
    if (digits == str_end) return .{ .value = 0 };
    var negative = false;
    if (text[digits] == '+') {
        digits += 1;
    } else if (text[digits] == '-') {
        negative = true;
        digits += 1;
    }
    const at = struct {
        fn c(t: []const u8, i: usize) u8 {
            return if (i < t.len) t[i] else 0;
        }
    }.c;
    if (!std.ascii.isDigit(at(text, digits))) {
        return .{ .value = 0, .message = try quantityMessage(allocator, "Invalid quantity \"{s}\": no valid leading digits, interpreting as \"0\" for backwards compatibility", [_][]const u8{text}) };
    }
    var base: u8 = 0;
    evaluation: {
        if (text[digits] != '0' or std.ascii.isDigit(at(text, digits + 1))) break :evaluation;
        if (digits + 1 == str_end) return .{ .value = 0 };
        switch (text[digits + 1]) {
            'g', 'G', 'm', 'M', 'k', 'K' => break :evaluation,
            'x', 'X' => base = 16,
            'o', 'O' => base = 8,
            'b', 'B' => base = 2,
            else => return .{ .value = 0, .message = try std.fmt.allocPrint(allocator, "Invalid prefix \"0{c}\", interpreting as \"0\" for backwards compatibility", .{text[digits + 1]}) },
        }
        digits += 2;
        // what strtoul would skip again (whitespace, a sign, another prefix)
        // makes the prefix invalid
        var consumed = digits;
        while (consumed < str_end and isQuantitySpace(text[consumed])) consumed += 1;
        if (at(text, consumed) == '+' or at(text, consumed) == '-') consumed += 1;
        if (at(text, consumed) == '0' and !std.ascii.isDigit(at(text, consumed + 1)) and consumed + 1 != str_end) {
            switch (at(text, consumed + 1)) {
                'x', 'X', 'o', 'O' => consumed += 2,
                'b', 'B' => if (base != 16) {
                    consumed += 2;
                },
                else => {},
            }
        }
        if (digits == str_end or digits != consumed) {
            return .{ .value = 0, .message = try quantityMessage(allocator, "Invalid quantity \"{s}\": no digits after base prefix, interpreting as \"0\" for backwards compatibility", [_][]const u8{text}) };
        }
    }
    const parsed = strtoul(text[digits..str_end], base);
    var retval = parsed.value;
    var overflow = parsed.overflow;
    if (!overflow) {
        if (!signed) {
            if (negative) {
                if (retval == 1 and digits + parsed.end == str_end) retval = std.math.maxInt(u64) else overflow = true;
            }
        } else {
            if (negative and retval == @as(u64, std.math.maxInt(i64)) + 1) {
                retval = 0 -% retval;
            } else if (@as(i64, @bitCast(retval)) < 0) {
                overflow = true;
            } else if (negative) {
                retval = 0 -% retval;
            }
        }
    }
    if (parsed.end == 0) {
        return .{ .value = 0, .message = try quantityMessage(allocator, "Invalid quantity \"{s}\": no valid leading digits, interpreting as \"0\" for backwards compatibility", [_][]const u8{text}) };
    }
    var digits_end = digits + parsed.end;
    while (digits_end < str_end and isQuantitySpace(text[digits_end])) digits_end += 1;
    if (digits_end != str_end) {
        const factor: u64 = switch (text[str_end - 1]) {
            'g', 'G' => 1 << 30,
            'm', 'M' => 1 << 20,
            'k', 'K' => 1 << 10,
            else => return .{ .value = retval, .message = try quantityMessage(allocator, "Invalid quantity \"{s}\": unknown multiplier \"{s}\", interpreting as \"{s}\" for backwards compatibility", [_][]const u8{ text, text[str_end - 1 .. str_end], text[0..digits_end] }) },
        };
        if (!overflow) {
            if (signed) {
                const sv: i64 = @bitCast(retval);
                const f: i64 = @intCast(factor);
                overflow = if (sv > 0) sv > @divTrunc(std.math.maxInt(i64), f) else sv < @divTrunc(std.math.minInt(i64), f);
            } else overflow = retval > std.math.maxInt(u64) / factor;
        }
        retval *%= factor;
        if (digits_end != str_end - 1) {
            return .{ .value = retval, .message = try quantityMessage(allocator, "Invalid quantity \"{s}\", interpreting as \"{s}{s}\" for backwards compatibility", [_][]const u8{ text, text[0..digits_end], text[str_end - 1 .. str_end] }) };
        }
    }
    if (overflow) return .{ .value = retval, .message = try quantityMessage(allocator, "Invalid quantity \"{s}\": value is out of range, using overflow result for backwards compatibility", [_][]const u8{text}) };
    return .{ .value = retval };
}

test "the account counts, limits and rebases" {
    var account = MemoryAccount{ .parent = std.testing.allocator };
    const a = account.allocator();
    const first = try a.alloc(u8, 100);
    try std.testing.expectEqual(@as(usize, 100), account.usage());
    account.rebase();
    account.limit = 150;
    const second = try a.alloc(u8, 150);
    try std.testing.expectError(error.OutOfMemory, a.alloc(u8, 1));
    try std.testing.expectEqual(@as(?usize, 1), account.refused);
    a.free(second);
    try std.testing.expectError(error.OutOfMemory, a.alloc(u8, 1));
    account.reporting = true;
    const third = try a.alloc(u8, 8);
    a.free(third);
    a.free(first);
    try std.testing.expectEqual(@as(usize, 0), account.used.load(.monotonic));
    try std.testing.expectEqual(@as(i64, 128 << 20), parseQuantity("128M").value);
    try std.testing.expectEqual(@as(i64, -1), parseQuantity("-1").value);
    try std.testing.expectEqual(@as(i64, 512), parseQuantity(" 512 ").value);
    try std.testing.expectEqual(@as(i64, 16 << 20), parseQuantity("0x10M").value);
    try std.testing.expectEqual(@as(i64, 256), parseQuantity("256MB").value);
    try std.testing.expect(parseQuantity("abc").problem.? == .no_digits);
}
