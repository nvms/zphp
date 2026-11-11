const std = @import("std");
const Allocator = std.mem.Allocator;
const native_params = @import("../stdlib/native_params.zig");
const deprecations = @import("../stdlib/deprecations_generated.zig");
const byref_args = @import("../stdlib/byref_args.zig");

// the natives a VM can call, each with the argument counts php accepts for it.
// the counts come from the signature table once, at registration, so a call
// checks them without another lookup

pub fn Table(comptime NativeFn: type) type {
    return struct {
        const Self = @This();

        pub const Native = struct {
            call: NativeFn,
            arity: Arity,
            // bit i set: parameter i is `callable` or `?callable`
            callbacks: u32,
            // bit i set: parameter i is a plain `array`; bit 31: so is the
            // variadic parameter that takes the rest
            arrays: u32,
            // bit i set: parameter i is a plain `string` or `?string`
            strings: u32,
            // #[\NoDiscard]'s reason, for a native php marks with it
            no_discard: ?[]const u8,
            // what follows "is deprecated" for a native php marks #[\Deprecated]
            deprecated: ?[]const u8,
            // it takes a parameter by reference
            byref: bool,
        };

        map: std.StringHashMapUnmanaged(Native) = .{},

        pub fn put(self: *Self, allocator: Allocator, name: []const u8, call: NativeFn) !void {
            try self.map.put(allocator, name, .{ .call = call, .arity = Arity.of(name), .callbacks = callbackParams(name), .arrays = arrayParams(name), .strings = stringParams(name), .no_discard = no_discard.get(name), .deprecated = deprecations.functions.get(name), .byref = byref_args.hasByRefParams(name) });
        }

        pub fn get(self: *const Self, name: []const u8) ?Native {
            return self.map.get(name);
        }

        pub fn contains(self: *const Self, name: []const u8) bool {
            return self.map.contains(name);
        }

        pub fn count(self: *const Self) usize {
            return self.map.count();
        }

        pub fn getKey(self: *const Self, name: []const u8) ?[]const u8 {
            return self.map.getKey(name);
        }

        pub fn keyIterator(self: *const Self) std.StringHashMapUnmanaged(Native).KeyIterator {
            return self.map.keyIterator();
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.map.deinit(allocator);
        }
    };
}

// the natives php 8.5 marks #[\NoDiscard], with the reason it gives
const no_discard = std.StaticStringMap([]const u8).initComptime(.{
    .{ "DateTimeImmutable::modify", "as DateTimeImmutable::modify() does not modify the object itself" },
    .{ "DateTimeImmutable::add", "as DateTimeImmutable::add() does not modify the object itself" },
    .{ "DateTimeImmutable::sub", "as DateTimeImmutable::sub() does not modify the object itself" },
    .{ "DateTimeImmutable::setTimezone", "as DateTimeImmutable::setTimezone() does not modify the object itself" },
    .{ "DateTimeImmutable::setTime", "as DateTimeImmutable::setTime() does not modify the object itself" },
    .{ "DateTimeImmutable::setDate", "as DateTimeImmutable::setDate() does not modify the object itself" },
    .{ "DateTimeImmutable::setISODate", "as DateTimeImmutable::setISODate() does not modify the object itself" },
    .{ "DateTimeImmutable::setTimestamp", "as DateTimeImmutable::setTimestamp() does not modify the object itself" },
    .{ "DateTimeImmutable::setMicrosecond", "as DateTimeImmutable::setMicrosecond() does not modify the object itself" },
});

// the parameters php checks as callbacks before the function runs
pub fn callbackParams(name: []const u8) u32 {
    const signature = native_params.get(name) orelse return 0;
    var positions: u32 = 0;
    for (signature.params, 0..) |param, i| {
        if (i >= 32) break;
        if (std.mem.eql(u8, param.type, "callable") or std.mem.eql(u8, param.type, "?callable")) positions |= @as(u32, 1) << @intCast(i);
    }
    return positions;
}

pub const variadic_array_bit: u32 = 1 << 31;

// the parameters php's argument parsing requires to be strings, for natives
// (methods check their own)
pub fn stringParams(name: []const u8) u32 {
    if (std.mem.indexOf(u8, name, "::") != null) return 0;
    const signature = native_params.get(name) orelse return 0;
    var positions: u32 = 0;
    for (signature.params, 0..) |param, i| {
        if (i >= 31 or param.variadic) break;
        if (std.mem.eql(u8, param.type, "string") or std.mem.eql(u8, param.type, "?string")) positions |= @as(u32, 1) << @intCast(i);
    }
    return positions;
}

// the parameters php's argument parsing requires to be arrays, for natives
// (methods check their own)
pub fn arrayParams(name: []const u8) u32 {
    if (std.mem.indexOf(u8, name, "::") != null) return 0;
    // these take their callbacks off the end first and check them themselves
    if (variadic_callbacks.has(name)) return 0;
    const signature = native_params.get(name) orelse return 0;
    var positions: u32 = 0;
    for (signature.params, 0..) |param, i| {
        if (i >= 31) break;
        if (!std.mem.eql(u8, param.type, "array")) continue;
        if (param.variadic) {
            positions |= variadic_array_bit | (~@as(u32, 0) << @intCast(i) & ~variadic_array_bit);
        } else positions |= @as(u32, 1) << @intCast(i);
    }
    return positions;
}

// natives whose signature is (array $array, ...$rest) but whose argument
// parsing ("+f", "+ff") takes one or two callbacks after the arrays, so php
// counts them as required
const variadic_callbacks = std.StaticStringMap(u16).initComptime(.{
    .{ "array_udiff", 2 },
    .{ "array_udiff_assoc", 2 },
    .{ "array_udiff_uassoc", 3 },
    .{ "array_uintersect", 2 },
    .{ "array_uintersect_assoc", 2 },
    .{ "array_uintersect_uassoc", 3 },
    .{ "array_diff_ukey", 2 },
    .{ "array_diff_uassoc", 2 },
    .{ "array_intersect_ukey", 2 },
    .{ "array_intersect_uassoc", 2 },
});

// how many arguments php lets a call pass; a native without a signature
// accepts any number
pub const Arity = struct {
    min: u16 = 0,
    max: u16 = unbounded,

    pub const unbounded = std.math.maxInt(u16);

    pub fn of(name: []const u8) Arity {
        if (variadic_callbacks.get(name)) |min| return .{ .min = min, .max = unbounded };
        // tries several argument lists and words its own TypeError
        if (std.mem.eql(u8, name, "DatePeriod::__construct")) return .{};
        const signature = native_params.get(name) orelse return .{};
        var arity: Arity = .{ .max = 0 };
        for (signature.params) |param| {
            if (param.variadic) return .{ .min = arity.min, .max = unbounded };
            arity.max += 1;
            if (param.default == .required) arity.min = arity.max;
        }
        return arity;
    }

    pub fn admits(self: Arity, given: usize) bool {
        return given >= self.min and (self.max == unbounded or given <= self.max);
    }

    // php's ArgumentCountError message for a call that passed `given`
    pub fn describe(self: Arity, buf: []u8, name: []const u8, given: usize) []const u8 {
        const exact = self.min == self.max;
        const bound: u16 = if (given < self.min) self.min else self.max;
        const kind = if (exact) "exactly" else if (given < self.min) "at least" else "at most";
        const noun = if (bound == 1) "argument" else "arguments";
        return std.fmt.bufPrint(buf, "{s}() expects {s} {d} {s}, {d} given", .{ name, kind, bound, noun, given }) catch "wrong argument count";
    }
};

test "arity follows the signature" {
    const strlen = Arity.of("strlen");
    try std.testing.expect(strlen.admits(1));
    try std.testing.expect(!strlen.admits(0));
    try std.testing.expect(!strlen.admits(2));
    var buf: [128]u8 = undefined;
    try std.testing.expectEqualStrings("strlen() expects exactly 1 argument, 0 given", strlen.describe(&buf, "strlen", 0));
    const sprintf = Arity.of("sprintf");
    try std.testing.expect(sprintf.admits(9));
    try std.testing.expectEqualStrings("sprintf() expects at least 1 argument, 0 given", sprintf.describe(&buf, "sprintf", 0));
    const explode = Arity.of("explode");
    try std.testing.expectEqualStrings("explode() expects at most 3 arguments, 4 given", explode.describe(&buf, "explode", 4));
    try std.testing.expect(Arity.of("zphp_unknown_native").admits(40));
}
