const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const filesystem = @import("filesystem.zig");
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

fn native_pack(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    const fmt = switch (args[0]) {
        .string => |s| s.bytes(),
        else => return NativeResult.scalar(.{ .bool = false }),
    };

    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);

    var parser = parseFormat(fmt, false);
    var arg_idx: usize = 1;

    while (parser.next()) |entry| {
        switch (entry.code) {
            'a', 'A', 'Z' => {
                if (arg_idx >= args.len) return NativeResult.scalar(.{ .bool = false });
                const s = switch (args[arg_idx]) {
                    .string => |v| v.bytes(),
                    else => "",
                };
                arg_idx += 1;
                const is_star = entry.count == .star;
                const count: usize = switch (entry.count) {
                    .star => if (entry.code == 'Z') s.len + 1 else s.len,
                    .exact => |n| n,
                };
                const pad: u8 = if (entry.code == 'A') ' ' else 0;
                // PHP Z with fixed length reserves the last byte for NUL terminator
                const max_data: usize = if (entry.code == 'Z' and !is_star and count > 0)
                    count - 1
                else
                    count;
                const copy_len = @min(s.len, max_data);
                try buf.appendSlice(ctx.allocator, s[0..copy_len]);
                if (count > copy_len) {
                    try buf.appendNTimes(ctx.allocator, pad, count - copy_len);
                }
            },
            'H', 'h' => {
                if (arg_idx >= args.len) return NativeResult.scalar(.{ .bool = false });
                const s = switch (args[arg_idx]) {
                    .string => |v| v.bytes(),
                    else => "",
                };
                arg_idx += 1;
                // match PHP: truncate requested nibble count to the available string length
                // so pack("H4", "ab") writes only 1 byte (from 2 hex chars) instead of zero-padding
                const requested = switch (entry.count) {
                    .star => s.len,
                    .exact => |n| n,
                };
                const nibbles = @min(requested, s.len);
                const bytes_needed = (nibbles + 1) / 2;
                var i: usize = 0;
                while (i < bytes_needed) : (i += 1) {
                    const ni0: u8 = if (i * 2 < nibbles) hexDigitVal(s[i * 2]) else 0;
                    const ni1: u8 = if (i * 2 + 1 < nibbles) hexDigitVal(s[i * 2 + 1]) else 0;
                    if (entry.code == 'H') {
                        try buf.append(ctx.allocator, (ni0 << 4) | ni1);
                    } else {
                        try buf.append(ctx.allocator, (ni1 << 4) | ni0);
                    }
                }
            },
            'c', 'C' => {
                const repeat = switch (entry.count) {
                    .star => args.len - arg_idx,
                    .exact => |n| n,
                };
                for (0..repeat) |_| {
                    if (arg_idx >= args.len) return NativeResult.scalar(.{ .bool = false });
                    const val: u8 = @truncate(@as(u64, @bitCast(Value.toInt(args[arg_idx]))));
                    arg_idx += 1;
                    try buf.append(ctx.allocator, val);
                }
            },
            's', 'S', 'n', 'v' => {
                const repeat = switch (entry.count) {
                    .star => args.len - arg_idx,
                    .exact => |n| n,
                };
                for (0..repeat) |_| {
                    if (arg_idx >= args.len) return NativeResult.scalar(.{ .bool = false });
                    const val: u16 = @truncate(@as(u64, @bitCast(Value.toInt(args[arg_idx]))));
                    arg_idx += 1;
                    const bytes = switch (entry.code) {
                        'n' => std.mem.toBytes(std.mem.nativeToBig(u16, val)),
                        'v' => std.mem.toBytes(std.mem.nativeToLittle(u16, val)),
                        else => std.mem.toBytes(val),
                    };
                    try buf.appendSlice(ctx.allocator, &bytes);
                }
            },
            'l', 'L', 'N', 'V' => {
                const repeat = switch (entry.count) {
                    .star => args.len - arg_idx,
                    .exact => |n| n,
                };
                for (0..repeat) |_| {
                    if (arg_idx >= args.len) return NativeResult.scalar(.{ .bool = false });
                    const val: u32 = @truncate(@as(u64, @bitCast(Value.toInt(args[arg_idx]))));
                    arg_idx += 1;
                    const bytes = switch (entry.code) {
                        'N' => std.mem.toBytes(std.mem.nativeToBig(u32, val)),
                        'V' => std.mem.toBytes(std.mem.nativeToLittle(u32, val)),
                        else => std.mem.toBytes(val),
                    };
                    try buf.appendSlice(ctx.allocator, &bytes);
                }
            },
            'i', 'I' => {
                const repeat = switch (entry.count) {
                    .star => args.len - arg_idx,
                    .exact => |n| n,
                };
                for (0..repeat) |_| {
                    if (arg_idx >= args.len) return NativeResult.scalar(.{ .bool = false });
                    const int_val = Value.toInt(args[arg_idx]);
                    arg_idx += 1;
                    if (entry.code == 'i') {
                        const val: c_int = @truncate(int_val);
                        try buf.appendSlice(ctx.allocator, std.mem.asBytes(&val));
                    } else {
                        const val: c_uint = @truncate(@as(u64, @bitCast(int_val)));
                        try buf.appendSlice(ctx.allocator, std.mem.asBytes(&val));
                    }
                }
            },
            'q', 'Q', 'J', 'P' => {
                const repeat = switch (entry.count) {
                    .star => args.len - arg_idx,
                    .exact => |n| n,
                };
                for (0..repeat) |_| {
                    if (arg_idx >= args.len) return NativeResult.scalar(.{ .bool = false });
                    const val: u64 = @bitCast(Value.toInt(args[arg_idx]));
                    arg_idx += 1;
                    const bytes = switch (entry.code) {
                        'J' => std.mem.toBytes(std.mem.nativeToBig(u64, val)),
                        'P' => std.mem.toBytes(std.mem.nativeToLittle(u64, val)),
                        else => std.mem.toBytes(val),
                    };
                    try buf.appendSlice(ctx.allocator, &bytes);
                }
            },
            'f', 'g', 'G' => {
                const repeat = switch (entry.count) {
                    .star => args.len - arg_idx,
                    .exact => |n| n,
                };
                for (0..repeat) |_| {
                    if (arg_idx >= args.len) return NativeResult.scalar(.{ .bool = false });
                    const val: f32 = @floatCast(Value.toFloat(args[arg_idx]));
                    arg_idx += 1;
                    const bits: u32 = @bitCast(val);
                    const bytes = switch (entry.code) {
                        'G' => std.mem.toBytes(std.mem.nativeToBig(u32, bits)),
                        'g' => std.mem.toBytes(std.mem.nativeToLittle(u32, bits)),
                        else => std.mem.toBytes(bits),
                    };
                    try buf.appendSlice(ctx.allocator, &bytes);
                }
            },
            'd', 'e', 'E' => {
                const repeat = switch (entry.count) {
                    .star => args.len - arg_idx,
                    .exact => |n| n,
                };
                for (0..repeat) |_| {
                    if (arg_idx >= args.len) return NativeResult.scalar(.{ .bool = false });
                    const val: f64 = Value.toFloat(args[arg_idx]);
                    arg_idx += 1;
                    const bits: u64 = @bitCast(val);
                    const bytes = switch (entry.code) {
                        'E' => std.mem.toBytes(std.mem.nativeToBig(u64, bits)),
                        'e' => std.mem.toBytes(std.mem.nativeToLittle(u64, bits)),
                        else => std.mem.toBytes(bits),
                    };
                    try buf.appendSlice(ctx.allocator, &bytes);
                }
            },
            'x' => {
                const count = switch (entry.count) {
                    .star => @as(usize, 1),
                    .exact => |n| n,
                };
                try buf.appendNTimes(ctx.allocator, 0, count);
            },
            'X' => {
                const count = switch (entry.count) {
                    .star => buf.items.len,
                    .exact => |n| n,
                };
                const to_remove = @min(count, buf.items.len);
                buf.items.len -= to_remove;
            },
            '@' => {
                const pos = switch (entry.count) {
                    .star => return NativeResult.scalar(.{ .bool = false }),
                    .exact => |n| n,
                };
                if (pos > buf.items.len) {
                    try buf.appendNTimes(ctx.allocator, 0, pos - buf.items.len);
                } else {
                    buf.items.len = pos;
                }
            },
            else => return NativeResult.scalar(.{ .bool = false }),
        }
    }

    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, try buf.toOwnedSlice(ctx.allocator)));
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
