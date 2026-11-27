const std = @import("std");
const Allocator = std.mem.Allocator;

// php's view of a VM's memory: the bytes its allocator hands out, counted
// from a baseline (what the VM holds before a script or request runs) the
// way zend_alloc counts them, and memory_limit enforced on that count.
//
// each allocation is counted at the size php's allocator would give it (its
// small bin, or whole pages), and the limit is checked as zend_mm_check_limit
// does: against the memory in use rounded up to 2MB chunks (php's real
// size), when a new chunk or a huge block is needed. memory_limit is php 8.5's soft limit: an allocation
// that crosses it still succeeds, leaving the exhaustion pending for the VM
// to report at its next interrupt point, up to the hard limit (twice the
// soft one, or 1GB above it), past which allocations fail

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

// the account an allocator charges, if it is one
pub fn accountOf(allocator: Allocator) ?*MemoryAccount {
    if (allocator.vtable != &MemoryAccount.vtable) return null;
    return @ptrCast(@alignCast(allocator.ptr));
}

pub const chunk_size: usize = 2 * 1024 * 1024;
const page_size: usize = 4096;
// ZEND_MM_MAX_LARGE_SIZE: anything bigger is a huge block of its own
const max_large_size: usize = chunk_size - page_size;

const bins = [_]u16{ 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 448, 512, 640, 768, 896, 1024, 1280, 1536, 1792, 2048, 2560, 3072 };

// the bin of a small size, by (size - 1) / 8
const bin_of = blk: {
    @setEvalBranchQuota(10000);
    var table: [3072 / 8]u16 = undefined;
    var bin: usize = 0;
    for (&table, 0..) |*slot, i| {
        const size = (i + 1) * 8;
        while (bins[bin] < size) bin += 1;
        slot.* = bins[bin];
    }
    break :blk table;
};

// what zend_mm_alloc takes for a request of `len` bytes
pub fn phpSize(len: usize) usize {
    if (len == 0) return 0;
    if (len <= 3072) return bin_of[(len - 1) >> 3];
    if (len > std.math.maxInt(usize) - page_size) return len;
    return std.mem.alignForward(usize, len, page_size);
}

fn isHuge(size: usize) bool {
    return size > max_large_size;
}

pub const MemoryAccount = struct {
    parent: Allocator,
    // frees can come from other threads when values cross into worker pools
    used: std.atomic.Value(usize) = .init(0),
    // arrays counted at php's size for their storage rather than at the
    // bytes they take (skew); signed, as it is mostly a reduction
    adjusted: std.atomic.Value(isize) = .init(0),
    peak: std.atomic.Value(usize) = .init(0),
    baseline: usize = 0,
    // bytes allowed above the baseline; 0 is unlimited
    limit: usize = 0,
    // the size of the allocation that first crossed the limit: php's
    // pending (delayed) out of memory error
    refused: ?usize = null,
    // set while the VM reports the exhaustion, which needs memory of its own
    reporting: bool = false,
    // told when the limit is first crossed, while the code that asked for
    // the memory is still running: php reports the fatal as from there
    on_refuse: ?*const fn (owner: *anyopaque) void = null,
    owner: ?*anyopaque = null,
    // above zero while php's allocations would be infallible (compiling,
    // some internal functions): past the hard limit php ends the process
    // (zend_mm_hard_limit_error) instead of failing the allocation
    infallible: u32 = 0,
    on_hard_limit: ?*const fn (owner: *anyopaque, add: usize) noreturn = null,

    const vtable: Allocator.VTable = .{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };

    pub fn allocator(self: *MemoryAccount) Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    fn total(self: *const MemoryAccount) usize {
        const sum = @as(isize, @intCast(self.used.load(.monotonic))) + self.adjusted.load(.monotonic);
        return if (sum < 0) 0 else @intCast(sum);
    }

    // usage that may run below zero for a moment: an array's storage is
    // counted at php's (smaller) size just before its bytes are asked for
    fn signedUsage(self: *const MemoryAccount) isize {
        return @as(isize, @intCast(self.used.load(.monotonic))) + self.adjusted.load(.monotonic) - @as(isize, @intCast(self.baseline));
    }

    // the real size once `add` more bytes are in use, the room php's
    // chunks had left taken first when usage is below zero
    fn realWith(in_use: isize, add: usize) usize {
        if (in_use >= 0) return realOf(@intCast(in_use)) +| add;
        const after = in_use + @as(isize, @intCast(@min(add, std.math.maxInt(isize))));
        return realOf(if (after < 0) 0 else @intCast(after));
    }

    // bytes in use above the baseline (heap->size)
    pub fn usage(self: *const MemoryAccount) usize {
        return self.total() -| self.baseline;
    }

    pub fn peakUsage(self: *const MemoryAccount) usize {
        return self.peak.load(.monotonic) -| self.baseline;
    }

    // heap->real_size: the 2MB chunks the memory in use takes, at least one
    pub fn realUsage(self: *const MemoryAccount) usize {
        return realOf(self.usage());
    }

    fn realOf(bytes: usize) usize {
        return @max(chunk_size, std.mem.alignForward(usize, bytes, chunk_size));
    }

    pub fn resetPeak(self: *MemoryAccount) void {
        self.peak.store(self.total(), .monotonic);
    }

    // start counting from what is held now, as a fresh request does
    pub fn rebase(self: *MemoryAccount) void {
        self.baseline = self.total();
        self.resetPeak();
        self.refused = null;
        self.reporting = false;
    }

    // zend_mm_update_hard_limit with memory_hard_limit_percent at -1
    pub fn hardLimit(self: *const MemoryAccount) usize {
        const gb: usize = 1024 * 1024 * 1024;
        if (self.limit > gb) return self.limit +| gb;
        return self.limit *| 2;
    }

    // memory the VM commits itself rather than through the allocator (its
    // call stack regions); false when memory_limit refuses it
    pub fn chargeExternal(self: *MemoryAccount, len: usize) bool {
        if (!self.admit(phpSize(len))) return false;
        self.chargeSized(phpSize(len));
        return true;
    }

    pub fn dischargeExternal(self: *MemoryAccount, len: usize) void {
        self.dischargeSized(phpSize(len));
    }

    // what an array holds counted at php's size for it rather than at the
    // bytes zphp's layout takes: positive charges, negative discharges, with
    // no limit check (the bytes were already admitted)
    pub fn skew(self: *MemoryAccount, delta: i64) void {
        _ = self.adjusted.fetchAdd(@intCast(delta), .monotonic);
        if (delta > 0) _ = self.peak.fetchMax(self.total(), .monotonic);
    }

    // for an allocator layered on the account's parent (the string pool):
    // the same checks and counts its own vtable makes
    pub fn admitLen(self: *MemoryAccount, len: usize) bool {
        return self.admit(phpSize(len));
    }

    pub fn admitGrowthLen(self: *MemoryAccount, old_len: usize, new_len: usize) bool {
        return new_len <= old_len or self.admitGrowth(old_len, new_len);
    }

    pub fn chargeLen(self: *MemoryAccount, len: usize) void {
        self.chargeSized(phpSize(len));
    }

    pub fn dischargeLen(self: *MemoryAccount, len: usize) void {
        self.dischargeSized(phpSize(len));
    }

    pub fn adjustLen(self: *MemoryAccount, old_len: usize, new_len: usize) void {
        self.adjust(old_len, new_len);
    }

    // zend_mm_check_limit: a php-sized request is checked when it needs a
    // new chunk (small and large ones) or is a huge block. past the soft
    // limit it is let through and the exhaustion left pending; past the
    // hard limit it fails
    fn admit(self: *MemoryAccount, size: usize) bool {
        if (self.limit == 0 or self.reporting) return true;
        const in_use = self.signedUsage();
        var add = size;
        if (!isHuge(size)) {
            // the chunks in use have room: no new memory from the system
            if (in_use < 0 or realOf(@as(usize, @intCast(in_use)) + size) <= realOf(@intCast(in_use))) return true;
            add = chunk_size;
        }
        const need = realWith(in_use, add);
        if (need <= self.limit) return true;
        return self.admitPastLimit(need, add);
    }

    fn admitPastLimit(self: *MemoryAccount, need: usize, add: usize) bool {
        if (need > self.hardLimit() and self.infallible > 0) if (self.on_hard_limit) |end| end(self.owner.?, add);
        if (self.refused == null) {
            self.refused = add;
            if (self.on_refuse) |notify| notify(self.owner.?);
        }
        return need <= self.hardLimit();
    }

    fn charge(self: *MemoryAccount, len: usize) void {
        _ = self.used.fetchAdd(len, .monotonic);
        _ = self.peak.fetchMax(self.total(), .monotonic);
    }

    fn discharge(self: *MemoryAccount, len: usize) void {
        var current = self.used.load(.monotonic);
        while (self.used.cmpxchgWeak(current, current -| len, .monotonic, .monotonic)) |seen| current = seen;
    }

    // a huge block also takes the node php's heap lists it in
    // (zend_mm_add_huge_block's zend_mm_huge_list, 32 bytes)
    fn withHugeList(size: usize) usize {
        return if (isHuge(size)) size +| 32 else size;
    }

    fn chargeSized(self: *MemoryAccount, size: usize) void {
        self.charge(withHugeList(size));
    }

    fn dischargeSized(self: *MemoryAccount, size: usize) void {
        self.discharge(withHugeList(size));
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *MemoryAccount = @ptrCast(@alignCast(ctx));
        const size = phpSize(len);
        if (!self.admit(size)) return null;
        const ptr = self.parent.rawAlloc(len, alignment, ret_addr) orelse return null;
        self.chargeSized(size);
        return ptr;
    }

    // a block growing within its php size needs nothing more; a huge block
    // growing in place is checked for its growth (zend_mm_realloc_huge),
    // anything else as the new allocation php's realloc makes
    fn admitGrowth(self: *MemoryAccount, old_len: usize, new_len: usize) bool {
        const old_size = phpSize(old_len);
        const new_size = phpSize(new_len);
        if (new_size <= old_size) return true;
        if (isHuge(old_size)) return self.admitHugeGrowth(new_size - old_size);
        return self.admit(new_size);
    }

    fn admitHugeGrowth(self: *MemoryAccount, add: usize) bool {
        if (self.limit == 0 or self.reporting) return true;
        const need = realWith(self.signedUsage(), add);
        if (need <= self.limit) return true;
        return self.admitPastLimit(need, add);
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *MemoryAccount = @ptrCast(@alignCast(ctx));
        if (new_len > memory.len and !self.admitGrowth(memory.len, new_len)) return false;
        if (!self.parent.rawResize(memory, alignment, new_len, ret_addr)) return false;
        self.adjust(memory.len, new_len);
        return true;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *MemoryAccount = @ptrCast(@alignCast(ctx));
        if (new_len > memory.len and !self.admitGrowth(memory.len, new_len)) return null;
        const ptr = self.parent.rawRemap(memory, alignment, new_len, ret_addr) orelse return null;
        self.adjust(memory.len, new_len);
        return ptr;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *MemoryAccount = @ptrCast(@alignCast(ctx));
        self.parent.rawFree(memory, alignment, ret_addr);
        self.dischargeSized(phpSize(memory.len));
    }

    fn adjust(self: *MemoryAccount, old_len: usize, new_len: usize) void {
        const old_size = phpSize(old_len);
        const new_size = phpSize(new_len);
        if (old_size == new_size) return;
        self.dischargeSized(old_size);
        self.chargeSized(new_size);
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
    // counted at php's bin sizes
    const first = try a.alloc(u8, 100);
    try std.testing.expectEqual(@as(usize, 112), account.usage());
    account.rebase();
    account.limit = 4 << 20;
    try std.testing.expectEqual(@as(usize, 2 << 20), account.realUsage());
    // past the soft limit: let through, the exhaustion left pending
    const second = try a.alloc(u8, 3 << 20);
    try std.testing.expectEqual(@as(?usize, 3 << 20), account.refused);
    try std.testing.expectEqual(@as(usize, 4 << 20), account.realUsage());
    // past the hard limit (twice the soft one): refused
    try std.testing.expectError(error.OutOfMemory, a.alloc(u8, 5 << 20));
    try std.testing.expectEqual(@as(?usize, 3 << 20), account.refused);
    account.reporting = true;
    const third = try a.alloc(u8, 8);
    a.free(third);
    a.free(second);
    a.free(first);
    try std.testing.expectEqual(@as(usize, 0), account.used.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 8), phpSize(1));
    try std.testing.expectEqual(@as(usize, 2560), phpSize(2049));
    try std.testing.expectEqual(@as(usize, 3072), phpSize(3072));
    try std.testing.expectEqual(@as(usize, 8192), phpSize(4097));
    try std.testing.expectEqual(@as(i64, 128 << 20), parseQuantity("128M").value);
    try std.testing.expectEqual(@as(i64, -1), parseQuantity("-1").value);
    try std.testing.expectEqual(@as(i64, 512), parseQuantity(" 512 ").value);
    try std.testing.expectEqual(@as(i64, 16 << 20), parseQuantity("0x10M").value);
    try std.testing.expectEqual(@as(i64, 256), parseQuantity("256MB").value);
    try std.testing.expect(parseQuantity("abc").problem.? == .no_digits);
}
