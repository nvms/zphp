const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const filesystem = @import("filesystem.zig");
const formatted_print = @import("formatted_print.zig");
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "pack", native_pack },
    .{ "unpack", native_unpack },
};

const FormatEntry = struct {
    code: u8,
    count: Count,
    name: ?[]const u8 = null,

    const Count = union(enum) {
        exact: usize,
        star,
    };
};

fn parseFormat(fmt: []const u8, named: bool) FormatParser {
    return .{ .fmt = fmt, .pos = 0, .named = named };
}

const FormatParser = struct {
    fmt: []const u8,
    pos: usize,
    named: bool,

    fn next(self: *FormatParser) ?FormatEntry {
        if (self.pos >= self.fmt.len) return null;
        const code = self.fmt[self.pos];
        self.pos += 1;

        var count: FormatEntry.Count = .{ .exact = 1 };

        if (self.pos < self.fmt.len) {
            if (self.fmt[self.pos] == '*') {
                count = .star;
                self.pos += 1;
            } else if (std.ascii.isDigit(self.fmt[self.pos])) {
                var n: usize = 0;
                while (self.pos < self.fmt.len and std.ascii.isDigit(self.fmt[self.pos])) {
                    n = n * 10 + (self.fmt[self.pos] - '0');
                    self.pos += 1;
                }
                count = .{ .exact = n };
            }
        }

        var name: ?[]const u8 = null;
        if (self.named and self.pos < self.fmt.len) {
            const start = self.pos;
            while (self.pos < self.fmt.len and self.fmt[self.pos] != '/') {
                self.pos += 1;
            }
            if (self.pos > start) {
                name = self.fmt[start..self.pos];
            }
            if (self.pos < self.fmt.len and self.fmt[self.pos] == '/') {
                self.pos += 1;
            }
        }

        return .{ .code = code, .count = count, .name = name };
    }
};

fn isFormatCode(c: u8) bool {
    return switch (c) {
        'a', 'A', 'h', 'H', 'c', 'C', 's', 'S', 'n', 'v', 'i', 'I', 'l', 'L', 'N', 'V', 'q', 'Q', 'J', 'P', 'f', 'g', 'G', 'd', 'e', 'E', 'x', 'X', 'Z', '@' => true,
        else => false,
    };
}

fn formatByteSize(code: u8) ?usize {
    return switch (code) {
        'c', 'C' => 1,
        's', 'S', 'n', 'v' => 2,
        'l', 'L', 'N', 'V' => 4,
        'i', 'I' => @sizeOf(c_int),
        'q', 'Q', 'J', 'P' => 8,
        'f', 'g', 'G' => 4,
        'd', 'e', 'E' => 8,
        else => null,
    };
}

// zval_get_long as pack() reads its integer arguments: a float past the int
// range is php 8.5's warning, then the modular cast
fn argLong(ctx: *NativeContext, v: Value) RuntimeError!i64 {
    if (v == .float) {
        const f = v.float;
        if (!(f >= -9.2233720368547758e18 and f < 9.2233720368547758e18)) {
            var tmp: [64]u8 = undefined;
            const m = try std.fmt.allocPrint(ctx.allocator, "The float {s} is not representable as an int, cast occurred", .{formatted_print.gcvt(f, -1, '.', 'E', &tmp)});
            defer ctx.allocator.free(m);
            try ctx.vm.emitWarning(m);
        }
    }
    return Value.toInt(v);
}

// zval_get_tmp_string
fn argString(ctx: *NativeContext, v: Value) RuntimeError![]const u8 {
    return switch (v) {
        .string => |s| s.bytes(),
        .object => |o| try ctx.vm.objectToString(o),
        .array => blk: {
            try ctx.vm.emitWarning("Array to string conversion");
            break :blk "Array";
        },
        else => (try ctx.vm.transientFormatted(v)).bytes(),
    };
}

fn packValueError(ctx: *NativeContext, comptime fmt: []const u8, args: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("ValueError", msg);
    return error.RuntimeError;
}

// PHP_FUNCTION(pack) (ext/standard/pack.c): the format is read once into
// codes and counts, the output sized, then written
fn native_pack(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const format = args[0].string.bytes();
    const argv = args[1..];
    const num_args: i64 = @intCast(argv.len);
    const int_max: i64 = std.math.maxInt(i32);

    const codes = try ctx.allocator.alloc(u8, format.len);
    defer ctx.allocator.free(codes);
    const counts = try ctx.allocator.alloc(i64, format.len);
    defer ctx.allocator.free(counts);
    // a '*' string argument converted once, as php converts it in place
    const star_strings = try ctx.allocator.alloc(?[]const u8, format.len);
    defer ctx.allocator.free(star_strings);
    var formatcount: usize = 0;
    var currentarg: i64 = 0;

    var i: usize = 0;
    while (i < format.len) : (formatcount += 1) {
        const code = format[i];
        i += 1;
        var arg: i64 = 1;
        star_strings[formatcount] = null;
        if (i < format.len) {
            const c = format[i];
            if (c == '*') {
                arg = -1;
                i += 1;
            } else if (c >= '0' and c <= '9') {
                // atoi: the digits as a C int
                var end = i;
                while (end < format.len and format[end] >= '0' and format[end] <= '9') end += 1;
                const wide = std.fmt.parseInt(u64, format[i..end], 10) catch std.math.maxInt(u64);
                arg = @as(i32, @truncate(@as(i64, @bitCast(wide))));
                i = end;
            }
        }
        switch (code) {
            'x', 'X', '@' => if (arg < 0) {
                try filesystem.warnDocref(ctx, "Type {c}: '*' ignored", .{code});
                arg = 1;
            },
            'a', 'A', 'Z', 'h', 'H' => {
                if (currentarg >= num_args) return packValueError(ctx, "Type {c}: not enough arguments", .{code});
                if (arg < 0) {
                    const s = try argString(ctx, argv[@intCast(currentarg)]);
                    if (ctx.vm.pending_exception != null) return error.RuntimeError;
                    star_strings[formatcount] = s;
                    arg = @intCast(s.len);
                    if (code == 'Z') arg += 1;
                }
                currentarg += 1;
            },
            'q', 'Q', 'J', 'P', 'c', 'C', 's', 'S', 'i', 'I', 'l', 'L', 'n', 'N', 'v', 'V', 'f', 'g', 'G', 'd', 'e', 'E' => {
                if (arg < 0) arg = num_args - currentarg;
                if (currentarg > int_max - arg) return packValueError(ctx, "Type {c}: too few arguments", .{code});
                currentarg += arg;
                if (currentarg > num_args) return packValueError(ctx, "Type {c}: too few arguments", .{code});
            },
            else => return packValueError(ctx, "Type {c}: unknown format code", .{code}),
        }
        codes[formatcount] = code;
        counts[formatcount] = arg;
    }
    if (currentarg < num_args) try filesystem.warnDocref(ctx, "{d} arguments unused", .{num_args - currentarg});

    var outputpos: i64 = 0;
    var outputsize: i64 = 0;
    for (codes[0..formatcount], counts[0..formatcount]) |code, arg| {
        const unit: i64 = switch (code) {
            'h', 'H', 'a', 'A', 'Z', 'c', 'C', 'x' => 1,
            's', 'S', 'n', 'v' => 2,
            'i', 'I', 'l', 'L', 'N', 'V', 'f', 'g', 'G' => 4,
            'q', 'Q', 'J', 'P', 'd', 'e', 'E' => 8,
            else => 0,
        };
        if (unit != 0) {
            const a = if (code == 'h' or code == 'H') @divTrunc(arg, 2) + @rem(arg, 2) else arg;
            if (a < 0 or @divTrunc(int_max - outputpos, unit) < a) return packValueError(ctx, "Type {c}: integer overflow in format string", .{code});
            outputpos += a * unit;
        } else if (code == 'X') {
            outputpos -= arg;
            if (outputpos < 0) {
                try filesystem.warnDocref(ctx, "Type {c}: outside of string", .{code});
                outputpos = 0;
            }
        } else if (code == '@') {
            outputpos = arg;
        }
        if (outputsize < outputpos) outputsize = outputpos;
    }

    const output = try ctx.allocator.alloc(u8, @intCast(outputsize));
    errdefer ctx.allocator.free(output);
    @memset(output, 0);
    outputpos = 0;
    currentarg = 0;
    for (codes[0..formatcount], counts[0..formatcount], star_strings[0..formatcount]) |code, count, star| {
        var arg = count;
        switch (code) {
            'a', 'A', 'Z' => {
                const arg_cp: usize = @intCast(if (code != 'Z') arg else @max(0, arg - 1));
                const str = star orelse try argString(ctx, argv[@intCast(currentarg)]);
                currentarg += 1;
                const start: usize = @intCast(outputpos);
                @memset(output[start..][0..@intCast(arg)], if (code == 'A') ' ' else 0);
                const n = @min(str.len, arg_cp);
                @memcpy(output[start..][0..n], str[0..n]);
                outputpos += arg;
            },
            'h', 'H' => {
                var nibbleshift: u3 = if (code == 'h') 0 else 4;
                var first = true;
                const str = star orelse try argString(ctx, argv[@intCast(currentarg)]);
                currentarg += 1;
                outputpos -= 1;
                if (arg > @as(i64, @intCast(str.len))) {
                    try filesystem.warnDocref(ctx, "Type {c}: not enough characters in string", .{code});
                    arg = @intCast(str.len);
                }
                var vi: usize = 0;
                while (arg > 0) : (arg -= 1) {
                    var n = str[vi];
                    vi += 1;
                    if (n >= '0' and n <= '9') {
                        n -= '0';
                    } else if (n >= 'A' and n <= 'F') {
                        n -= 'A' - 10;
                    } else if (n >= 'a' and n <= 'f') {
                        n -= 'a' - 10;
                    } else {
                        try filesystem.warnDocref(ctx, "Type {c}: illegal hex digit {c}", .{ code, n });
                        n = 0;
                    }
                    if (first) {
                        outputpos += 1;
                        output[@intCast(outputpos)] = 0;
                        first = false;
                    } else {
                        first = true;
                    }
                    output[@intCast(outputpos)] |= n << nibbleshift;
                    nibbleshift = if (nibbleshift == 0) 4 else 0;
                }
                outputpos += 1;
            },
            'c', 'C', 's', 'S', 'n', 'v', 'i', 'I', 'l', 'L', 'N', 'V', 'q', 'Q', 'J', 'P' => {
                const size: usize = switch (code) {
                    'c', 'C' => 1,
                    's', 'S', 'n', 'v' => 2,
                    'i', 'I', 'l', 'L', 'N', 'V' => 4,
                    else => 8,
                };
                const big = code == 'n' or code == 'N' or code == 'J';
                while (arg > 0) : (arg -= 1) {
                    const v: u64 = @bitCast(try argLong(ctx, argv[@intCast(currentarg)]));
                    currentarg += 1;
                    var bytes: [8]u8 = undefined;
                    std.mem.writeInt(u64, &bytes, v, .little);
                    const dst = output[@intCast(outputpos)..][0..size];
                    if (big) {
                        for (0..size) |k| dst[k] = bytes[size - 1 - k];
                    } else @memcpy(dst, bytes[0..size]);
                    outputpos += @intCast(size);
                }
            },
            'f', 'g', 'G' => while (arg > 0) : (arg -= 1) {
                const v: f32 = @floatCast(Value.toFloat(argv[@intCast(currentarg)]));
                currentarg += 1;
                std.mem.writeInt(u32, output[@intCast(outputpos)..][0..4], @bitCast(v), if (code == 'G') .big else .little);
                outputpos += 4;
            },
            'd', 'e', 'E' => while (arg > 0) : (arg -= 1) {
                const v: f64 = Value.toFloat(argv[@intCast(currentarg)]);
                currentarg += 1;
                std.mem.writeInt(u64, output[@intCast(outputpos)..][0..8], @bitCast(v), if (code == 'E') .big else .little);
                outputpos += 8;
            },
            'x' => {
                @memset(output[@intCast(outputpos)..][0..@intCast(arg)], 0);
                outputpos += arg;
            },
            'X' => {
                outputpos -= arg;
                if (outputpos < 0) outputpos = 0;
            },
            '@' => {
                if (arg > outputpos) @memset(output[@intCast(outputpos)..@intCast(arg)], 0);
                outputpos = arg;
            },
            else => unreachable,
        }
    }
    const len: usize = @intCast(outputpos);
    if (len == 0) {
        ctx.allocator.free(output);
        return NativeResult.literal("");
    }
    const result = try ctx.allocator.realloc(output, len);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result));
}

// PHP_FUNCTION(unpack) (ext/standard/pack.c): each format code with its
// repeater and name, read from the data after `offset`
fn native_unpack(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    var format = args[0].string.bytes();
    const all_input = args[1].string.bytes();
    const offset: i64 = if (args.len >= 3) Value.toInt(args[2]) else 0;
    if (offset < 0 or offset > @as(i64, @intCast(all_input.len))) {
        try ctx.vm.setPendingException("ValueError", "unpack(): Argument #3 ($offset) must be contained in argument #2 ($data)");
        return error.RuntimeError;
    }
    const input = all_input[@intCast(offset)..];
    const inputlen: i64 = @intCast(input.len);
    var inputpos: i64 = 0;
    const int_max: i64 = std.math.maxInt(i32);

    const arr = try ctx.createArray();
    while (format.len > 0) {
        const type_code = format[0];
        format = format[1..];
        var repetitions: i64 = 1;
        if (format.len > 0) {
            const c = format[0];
            if (c >= '0' and c <= '9') {
                var digits: usize = 0;
                while (digits < format.len and format[digits] >= '0' and format[digits] <= '9') digits += 1;
                const tmp = std.fmt.parseInt(i64, format[0..digits], 10) catch std.math.maxInt(i64);
                if (tmp > int_max) {
                    try filesystem.warnDocref(ctx, "Type {c}: integer overflow", .{type_code});
                    return NativeResult.scalar(.{ .bool = false });
                }
                repetitions = tmp;
                format = format[digits..];
            } else if (c == '*') {
                repetitions = -1;
                format = format[1..];
            }
        }
        const name_end = std.mem.indexOfScalar(u8, format, '/') orelse format.len;
        const name = format[0..@min(name_end, 200)];
        format = format[name_end..];
        const argb = repetitions;

        var size: i64 = 0;
        switch (type_code) {
            'X' => {
                size = -1;
                if (repetitions < 0) {
                    try filesystem.warnDocref(ctx, "Type {c}: '*' ignored", .{type_code});
                    repetitions = 1;
                }
            },
            '@' => size = 0,
            'a', 'A', 'Z' => {
                size = repetitions;
                repetitions = 1;
            },
            'h', 'H' => {
                size = if (repetitions > 0) @divTrunc(repetitions + 1, 2) else repetitions;
                repetitions = 1;
            },
            'c', 'C', 'x' => size = 1,
            's', 'S', 'n', 'v' => size = 2,
            'i', 'I', 'l', 'L', 'N', 'V', 'f', 'g', 'G' => size = 4,
            'q', 'Q', 'J', 'P', 'd', 'e', 'E' => size = 8,
            else => {
                const msg = try std.fmt.allocPrint(ctx.allocator, "Invalid format type {c}", .{type_code});
                defer ctx.allocator.free(msg);
                try ctx.vm.setPendingException("ValueError", msg);
                return error.RuntimeError;
            },
        }

        var i: i64 = 0;
        while (i != repetitions) : (i += 1) {
            if (size != 0 and size != -1 and int_max - size + 1 < inputpos) {
                try filesystem.warnDocref(ctx, "Type {c}: integer overflow", .{type_code});
                return NativeResult.scalar(.{ .bool = false });
            }
            if (inputpos + size <= inputlen) {
                const pos: usize = @intCast(@max(inputpos, 0));
                var val: ?Value = null;
                switch (type_code) {
                    'a', 'A', 'Z' => {
                        var len = inputlen - inputpos;
                        if (size >= 0 and len > size) len = size;
                        size = len;
                        var bytes = input[pos..][0..@intCast(len)];
                        if (type_code == 'A') {
                            var end = bytes.len;
                            while (end > 0) : (end -= 1) switch (bytes[end - 1]) {
                                0, ' ', '\t', '\r', '\n' => {},
                                else => break,
                            };
                            bytes = bytes[0..end];
                        } else if (type_code == 'Z') {
                            bytes = bytes[0 .. std.mem.indexOfScalar(u8, bytes, 0) orelse bytes.len];
                        }
                        val = .{ .string = try Value.String.create(ctx.allocator, bytes) };
                    },
                    'h', 'H' => {
                        var len = (inputlen - inputpos) * 2;
                        if (size > @divTrunc(int_max, 2)) {
                            const msg = try std.fmt.allocPrint(ctx.allocator, "unpack(): Argument #1 ($format) repeater must be less than or equal to {d}", .{@divTrunc(int_max, 2)});
                            defer ctx.allocator.free(msg);
                            try ctx.vm.setPendingException("ValueError", msg);
                            return error.RuntimeError;
                        }
                        if (size >= 0 and len > size * 2) len = size * 2;
                        if (len > 0 and argb > 0) len -= @rem(argb, 2);
                        const buf = try ctx.allocator.alloc(u8, @intCast(@max(len, 0)));
                        var nibbleshift: u3 = if (type_code == 'h') 0 else 4;
                        var first = true;
                        var ipos: usize = 0;
                        for (buf) |*out| {
                            const cc: u8 = (input[pos + ipos] >> nibbleshift) & 0xf;
                            out.* = if (cc < 10) cc + '0' else cc - 10 + 'a';
                            nibbleshift = if (nibbleshift == 0) 4 else 0;
                            if (!first) ipos += 1;
                            first = !first;
                        }
                        val = .{ .string = try Value.String.adopt(ctx.allocator, buf) };
                    },
                    'c' => val = .{ .int = @as(i8, @bitCast(input[pos])) },
                    'C' => val = .{ .int = input[pos] },
                    's' => val = .{ .int = std.mem.readInt(i16, input[pos..][0..2], .little) },
                    'S', 'v' => val = .{ .int = std.mem.readInt(u16, input[pos..][0..2], .little) },
                    'n' => val = .{ .int = std.mem.readInt(u16, input[pos..][0..2], .big) },
                    'i', 'l' => val = .{ .int = std.mem.readInt(i32, input[pos..][0..4], .little) },
                    'I', 'L', 'V' => val = .{ .int = std.mem.readInt(u32, input[pos..][0..4], .little) },
                    'N' => val = .{ .int = std.mem.readInt(u32, input[pos..][0..4], .big) },
                    'q', 'Q', 'P' => val = .{ .int = std.mem.readInt(i64, input[pos..][0..8], .little) },
                    'J' => val = .{ .int = std.mem.readInt(i64, input[pos..][0..8], .big) },
                    'f', 'g', 'G' => {
                        const bits = std.mem.readInt(u32, input[pos..][0..4], if (type_code == 'G') .big else .little);
                        val = .{ .float = @as(f32, @bitCast(bits)) };
                    },
                    'd', 'e', 'E' => {
                        const bits = std.mem.readInt(u64, input[pos..][0..8], if (type_code == 'E') .big else .little);
                        val = .{ .float = @bitCast(bits) };
                    },
                    'x' => {},
                    'X' => {
                        if (inputpos < size) {
                            inputpos = -size;
                            i = repetitions - 1;
                            if (repetitions >= 0) try filesystem.warnDocref(ctx, "Type {c}: outside of string", .{type_code});
                        }
                    },
                    '@' => {
                        if (repetitions <= inputlen) {
                            inputpos = repetitions;
                        } else {
                            try filesystem.warnDocref(ctx, "Type {c}: outside of string", .{type_code});
                        }
                        i = repetitions - 1;
                    },
                    else => unreachable,
                }
                if (val) |v| {
                    defer if (v == .string) v.string.release();
                    // the 1-based element number goes after the name of a
                    // repeated code; a numeric name is an integer key
                    if (name.len == 0) {
                        try ctx.vm.arraySetOwned(arr, .{ .int = i + 1 }, v);
                    } else {
                        const key_bytes = if (repetitions == 1)
                            try ctx.allocator.dupe(u8, name)
                        else
                            try std.fmt.allocPrint(ctx.allocator, "{s}{d}", .{ name, i + 1 });
                        const key = try Value.String.adopt(ctx.allocator, key_bytes);
                        defer key.release();
                        try ctx.vm.arraySetOwned(arr, .{ .string = key }, v);
                    }
                }
                inputpos += size;
                if (inputpos < 0) {
                    if (size != -1) try filesystem.warnDocref(ctx, "Type {c}: outside of string", .{type_code});
                    inputpos = 0;
                }
            } else if (repetitions < 0) {
                break;
            } else {
                const have = inputlen - inputpos;
                try filesystem.warnDocref(ctx, "Type {c}: not enough input values, need {d} values but only {d} {s} provided", .{ type_code, size, have, @as([]const u8, if (have == 1) "was" else "were") });
                return NativeResult.scalar(.{ .bool = false });
            }
        }
        if (format.len > 0) format = format[1..];
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn hexDigitVal(c: u8) u4 {
    return switch (c) {
        '0'...'9' => @truncate(c - '0'),
        'a'...'f' => @truncate(c - 'a' + 10),
        'A'...'F' => @truncate(c - 'A' + 10),
        else => 0,
    };
}

test "format parser" {
    var p = parseFormat("Nlen/a4data/Cflags", true);
    const e1 = p.next().?;
    try std.testing.expectEqual('N', e1.code);
    try std.testing.expectEqualStrings("len", e1.name.?);

    const e2 = p.next().?;
    try std.testing.expectEqual('a', e2.code);
    try std.testing.expectEqual(FormatEntry.Count{ .exact = 4 }, e2.count);
    try std.testing.expectEqualStrings("data", e2.name.?);

    const e3 = p.next().?;
    try std.testing.expectEqual('C', e3.code);
    try std.testing.expectEqualStrings("flags", e3.name.?);

    try std.testing.expectEqual(null, p.next());
}

test "format parser star" {
    var p = parseFormat("a*", false);
    const e = p.next().?;
    try std.testing.expectEqual('a', e.code);
    try std.testing.expectEqual(FormatEntry.Count.star, e.count);
}
