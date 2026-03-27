const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
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

fn native_pack(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    const fmt = switch (args[0]) {
        .string => |s| s,
        else => return .{ .bool = false },
    };

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(ctx.allocator);

    var parser = parseFormat(fmt, false);
    var arg_idx: usize = 1;

    while (parser.next()) |entry| {
        switch (entry.code) {
            'a', 'A', 'Z' => {
                if (arg_idx >= args.len) return .{ .bool = false };
                const s = switch (args[arg_idx]) {
                    .string => |v| v,
                    else => "",
                };
                arg_idx += 1;
                const count = switch (entry.count) {
                    .star => s.len,
                    .exact => |n| n,
                };
                const pad: u8 = if (entry.code == 'A') ' ' else 0;
                const copy_len = @min(s.len, count);
                try buf.appendSlice(ctx.allocator, s[0..copy_len]);
                if (count > copy_len) {
                    try buf.appendNTimes(ctx.allocator, pad, count - copy_len);
                }
            },
            'H', 'h' => {
                if (arg_idx >= args.len) return .{ .bool = false };
                const s = switch (args[arg_idx]) {
                    .string => |v| v,
                    else => "",
                };
                arg_idx += 1;
                const nibbles = switch (entry.count) {
                    .star => s.len,
                    .exact => |n| n,
                };
                const bytes_needed = (nibbles + 1) / 2;
                var i: usize = 0;
                while (i < bytes_needed) : (i += 1) {
                    const ni0: u8 = if (i * 2 < nibbles) hexDigitVal(if (i * 2 < s.len) s[i * 2] else '0') else 0;
                    const ni1: u8 = if (i * 2 + 1 < nibbles) hexDigitVal(if (i * 2 + 1 < s.len) s[i * 2 + 1] else '0') else 0;
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
                    if (arg_idx >= args.len) return .{ .bool = false };
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
                    if (arg_idx >= args.len) return .{ .bool = false };
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
                    if (arg_idx >= args.len) return .{ .bool = false };
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
                    if (arg_idx >= args.len) return .{ .bool = false };
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
                    if (arg_idx >= args.len) return .{ .bool = false };
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
                    if (arg_idx >= args.len) return .{ .bool = false };
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
                    if (arg_idx >= args.len) return .{ .bool = false };
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
                    .star => return .{ .bool = false },
                    .exact => |n| n,
                };
                if (pos > buf.items.len) {
                    try buf.appendNTimes(ctx.allocator, 0, pos - buf.items.len);
                } else {
                    buf.items.len = pos;
                }
            },
            else => return .{ .bool = false },
        }
    }

    const result = try ctx.allocator.alloc(u8, buf.items.len);
    @memcpy(result, buf.items);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn native_unpack(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .bool = false };
    const fmt = switch (args[0]) {
        .string => |s| s,
        else => return .{ .bool = false },
    };
    const data = switch (args[1]) {
        .string => |s| s,
        else => return .{ .bool = false },
    };
    var offset: usize = 0;
    if (args.len >= 3) {
        const off_val = Value.toInt(args[2]);
        if (off_val < 0) return .{ .bool = false };
        offset = @intCast(off_val);
    }

    var arr = try ctx.createArray();
    var parser = parseFormat(fmt, true);
    var unnamed_idx: i64 = 1;

    while (parser.next()) |entry| {
        switch (entry.code) {
            'a', 'A', 'Z' => {
                const count = switch (entry.count) {
                    .star => if (data.len > offset) data.len - offset else 0,
                    .exact => |n| n,
                };
                if (offset + count > data.len) return .{ .bool = false };
                var slice = data[offset .. offset + count];
                offset += count;

                if (entry.code == 'A') {
                    var end = slice.len;
                    while (end > 0 and (slice[end - 1] == ' ' or slice[end - 1] == 0)) end -= 1;
                    slice = slice[0..end];
                } else if (entry.code == 'Z') {
                    if (std.mem.indexOfScalar(u8, slice, 0)) |nul_pos| {
                        slice = slice[0..nul_pos];
                    }
                }

                const owned = try ctx.createString(slice);
                const key = unpackKey(entry.name, &unnamed_idx);
                try arr.set(ctx.allocator, key, .{ .string = owned });
            },
            'H', 'h' => {
                const nibbles = switch (entry.count) {
                    .star => if (data.len > offset) (data.len - offset) * 2 else 0,
                    .exact => |n| n,
                };
                const bytes_needed = (nibbles + 1) / 2;
                if (offset + bytes_needed > data.len) return .{ .bool = false };

                const hex_buf = try ctx.allocator.alloc(u8, nibbles);
                try ctx.strings.append(ctx.allocator, hex_buf);

                for (0..nibbles) |i| {
                    const byte = data[offset + i / 2];
                    const nibble: u4 = if (entry.code == 'H')
                        (if (i % 2 == 0) @as(u4, @truncate(byte >> 4)) else @as(u4, @truncate(byte & 0x0f)))
                    else
                        (if (i % 2 == 0) @as(u4, @truncate(byte & 0x0f)) else @as(u4, @truncate(byte >> 4)));
                    hex_buf[i] = hexChar(nibble);
                }
                offset += bytes_needed;

                const key = unpackKey(entry.name, &unnamed_idx);
                try arr.set(ctx.allocator, key, .{ .string = hex_buf });
            },
            'c' => {
                const repeat = resolveRepeat(entry.count, 1, data.len, offset);
                if (offset + repeat > data.len) return .{ .bool = false };
                for (0..repeat) |i| {
                    const val: i8 = @bitCast(data[offset]);
                    offset += 1;
                    const key = unpackKeyIndexed(entry.name, &unnamed_idx, i, repeat);
                    try arr.set(ctx.allocator, key, .{ .int = val });
                }
            },
            'C' => {
                const repeat = resolveRepeat(entry.count, 1, data.len, offset);
                if (offset + repeat > data.len) return .{ .bool = false };
                for (0..repeat) |i| {
                    const val = data[offset];
                    offset += 1;
                    const key = unpackKeyIndexed(entry.name, &unnamed_idx, i, repeat);
                    try arr.set(ctx.allocator, key, .{ .int = val });
                }
            },
            's' => {
                const repeat = resolveRepeat(entry.count, 2, data.len, offset);
                if (offset + repeat * 2 > data.len) return .{ .bool = false };
                for (0..repeat) |i| {
                    const val: i16 = @bitCast(data[offset..][0..2].*);
                    offset += 2;
                    const key = unpackKeyIndexed(entry.name, &unnamed_idx, i, repeat);
                    try arr.set(ctx.allocator, key, .{ .int = val });
                }
            },
            'S' => {
                const repeat = resolveRepeat(entry.count, 2, data.len, offset);
                if (offset + repeat * 2 > data.len) return .{ .bool = false };
                for (0..repeat) |i| {
                    const val: u16 = @bitCast(data[offset..][0..2].*);
                    offset += 2;
                    const key = unpackKeyIndexed(entry.name, &unnamed_idx, i, repeat);
                    try arr.set(ctx.allocator, key, .{ .int = val });
                }
            },
            'n' => {
                const repeat = resolveRepeat(entry.count, 2, data.len, offset);
                if (offset + repeat * 2 > data.len) return .{ .bool = false };
                for (0..repeat) |i| {
                    const val = std.mem.bigToNative(u16, @bitCast(data[offset..][0..2].*));
                    offset += 2;
                    const key = unpackKeyIndexed(entry.name, &unnamed_idx, i, repeat);
                    try arr.set(ctx.allocator, key, .{ .int = val });
                }
            },
            'v' => {
                const repeat = resolveRepeat(entry.count, 2, data.len, offset);
                if (offset + repeat * 2 > data.len) return .{ .bool = false };
                for (0..repeat) |i| {
                    const val = std.mem.littleToNative(u16, @bitCast(data[offset..][0..2].*));
                    offset += 2;
                    const key = unpackKeyIndexed(entry.name, &unnamed_idx, i, repeat);
                    try arr.set(ctx.allocator, key, .{ .int = val });
                }
            },
            'l' => {
                const repeat = resolveRepeat(entry.count, 4, data.len, offset);
                if (offset + repeat * 4 > data.len) return .{ .bool = false };
                for (0..repeat) |i| {
                    const val: i32 = @bitCast(data[offset..][0..4].*);
                    offset += 4;
                    const key = unpackKeyIndexed(entry.name, &unnamed_idx, i, repeat);
                    try arr.set(ctx.allocator, key, .{ .int = val });
                }
            },
            'L' => {
                const repeat = resolveRepeat(entry.count, 4, data.len, offset);
                if (offset + repeat * 4 > data.len) return .{ .bool = false };
                for (0..repeat) |i| {
                    const val: u32 = @bitCast(data[offset..][0..4].*);
                    offset += 4;
                    const key = unpackKeyIndexed(entry.name, &unnamed_idx, i, repeat);
                    try arr.set(ctx.allocator, key, .{ .int = val });
                }
            },
            'N' => {
                const repeat = resolveRepeat(entry.count, 4, data.len, offset);
                if (offset + repeat * 4 > data.len) return .{ .bool = false };
                for (0..repeat) |i| {
                    const val = std.mem.bigToNative(u32, @bitCast(data[offset..][0..4].*));
                    offset += 4;
                    const key = unpackKeyIndexed(entry.name, &unnamed_idx, i, repeat);
                    try arr.set(ctx.allocator, key, .{ .int = val });
                }
            },
            'V' => {
                const repeat = resolveRepeat(entry.count, 4, data.len, offset);
                if (offset + repeat * 4 > data.len) return .{ .bool = false };
                for (0..repeat) |i| {
                    const val = std.mem.littleToNative(u32, @bitCast(data[offset..][0..4].*));
                    offset += 4;
                    const key = unpackKeyIndexed(entry.name, &unnamed_idx, i, repeat);
                    try arr.set(ctx.allocator, key, .{ .int = val });
                }
            },
            'i' => {
                const sz = @sizeOf(c_int);
                const repeat = resolveRepeat(entry.count, sz, data.len, offset);
                if (offset + repeat * sz > data.len) return .{ .bool = false };
                for (0..repeat) |i| {
                    var bytes: [@sizeOf(c_int)]u8 = undefined;
                    @memcpy(&bytes, data[offset .. offset + sz]);
                    const val: c_int = @bitCast(bytes);
                    offset += sz;
                    const key = unpackKeyIndexed(entry.name, &unnamed_idx, i, repeat);
                    try arr.set(ctx.allocator, key, .{ .int = val });
                }
            },
            'I' => {
                const sz = @sizeOf(c_uint);
                const repeat = resolveRepeat(entry.count, sz, data.len, offset);
                if (offset + repeat * sz > data.len) return .{ .bool = false };
                for (0..repeat) |i| {
                    var bytes: [@sizeOf(c_uint)]u8 = undefined;
                    @memcpy(&bytes, data[offset .. offset + sz]);
                    const val: c_uint = @bitCast(bytes);
                    offset += sz;
                    const key = unpackKeyIndexed(entry.name, &unnamed_idx, i, repeat);
                    try arr.set(ctx.allocator, key, .{ .int = @intCast(val) });
                }
            },
            'q' => {
                const repeat = resolveRepeat(entry.count, 8, data.len, offset);
                if (offset + repeat * 8 > data.len) return .{ .bool = false };
                for (0..repeat) |i| {
                    const val: i64 = @bitCast(data[offset..][0..8].*);
                    offset += 8;
                    const key = unpackKeyIndexed(entry.name, &unnamed_idx, i, repeat);
                    try arr.set(ctx.allocator, key, .{ .int = val });
                }
            },
            'Q' => {
                const repeat = resolveRepeat(entry.count, 8, data.len, offset);
                if (offset + repeat * 8 > data.len) return .{ .bool = false };
                for (0..repeat) |i| {
                    const val: u64 = @bitCast(data[offset..][0..8].*);
                    offset += 8;
                    const key = unpackKeyIndexed(entry.name, &unnamed_idx, i, repeat);
                    const int_val: i64 = if (val > std.math.maxInt(i64)) @bitCast(val) else @intCast(val);
                    try arr.set(ctx.allocator, key, .{ .int = int_val });
                }
            },
            'J' => {
                const repeat = resolveRepeat(entry.count, 8, data.len, offset);
                if (offset + repeat * 8 > data.len) return .{ .bool = false };
                for (0..repeat) |i| {
                    const val = std.mem.bigToNative(u64, @bitCast(data[offset..][0..8].*));
                    offset += 8;
                    const key = unpackKeyIndexed(entry.name, &unnamed_idx, i, repeat);
                    const int_val: i64 = if (val > std.math.maxInt(i64)) @bitCast(val) else @intCast(val);
                    try arr.set(ctx.allocator, key, .{ .int = int_val });
                }
            },
            'P' => {
                const repeat = resolveRepeat(entry.count, 8, data.len, offset);
                if (offset + repeat * 8 > data.len) return .{ .bool = false };
                for (0..repeat) |i| {
                    const val = std.mem.littleToNative(u64, @bitCast(data[offset..][0..8].*));
                    offset += 8;
                    const key = unpackKeyIndexed(entry.name, &unnamed_idx, i, repeat);
                    const int_val: i64 = if (val > std.math.maxInt(i64)) @bitCast(val) else @intCast(val);
                    try arr.set(ctx.allocator, key, .{ .int = int_val });
                }
            },
            'f', 'g', 'G' => {
                const repeat = resolveRepeat(entry.count, 4, data.len, offset);
                if (offset + repeat * 4 > data.len) return .{ .bool = false };
                for (0..repeat) |i| {
                    var bits: u32 = @bitCast(data[offset..][0..4].*);
                    offset += 4;
                    bits = switch (entry.code) {
                        'G' => std.mem.bigToNative(u32, bits),
                        'g' => std.mem.littleToNative(u32, bits),
                        else => bits,
                    };
                    const val: f32 = @bitCast(bits);
                    const key = unpackKeyIndexed(entry.name, &unnamed_idx, i, repeat);
                    try arr.set(ctx.allocator, key, .{ .float = val });
                }
            },
            'd', 'e', 'E' => {
                const repeat = resolveRepeat(entry.count, 8, data.len, offset);
                if (offset + repeat * 8 > data.len) return .{ .bool = false };
                for (0..repeat) |i| {
                    var bits: u64 = @bitCast(data[offset..][0..8].*);
                    offset += 8;
                    bits = switch (entry.code) {
                        'E' => std.mem.bigToNative(u64, bits),
                        'e' => std.mem.littleToNative(u64, bits),
                        else => bits,
                    };
                    const val: f64 = @bitCast(bits);
                    const key = unpackKeyIndexed(entry.name, &unnamed_idx, i, repeat);
                    try arr.set(ctx.allocator, key, .{ .float = val });
                }
            },
            'x' => {
                const count = switch (entry.count) {
                    .star => @as(usize, 1),
                    .exact => |n| n,
                };
                offset += count;
            },
            'X' => {
                const count = switch (entry.count) {
                    .star => offset,
                    .exact => |n| n,
                };
                if (count > offset) return .{ .bool = false };
                offset -= count;
            },
            '@' => {
                const pos = switch (entry.count) {
                    .star => return .{ .bool = false },
                    .exact => |n| n,
                };
                offset = pos;
            },
            else => return .{ .bool = false },
        }
    }

    return .{ .array = arr };
}

fn resolveRepeat(count: FormatEntry.Count, byte_size: usize, data_len: usize, offset: usize) usize {
    return switch (count) {
        .star => if (data_len > offset) (data_len - offset) / byte_size else 0,
        .exact => |n| n,
    };
}

fn unpackKey(name: ?[]const u8, unnamed_idx: *i64) PhpArray.Key {
    if (name) |n| return .{ .string = n };
    const idx = unnamed_idx.*;
    unnamed_idx.* += 1;
    return .{ .int = idx };
}

fn unpackKeyIndexed(name: ?[]const u8, unnamed_idx: *i64, i: usize, repeat: usize) PhpArray.Key {
    if (name) |n| {
        if (repeat <= 1) return .{ .string = n };
        _ = i;
        return .{ .string = n };
    }
    const idx = unnamed_idx.*;
    unnamed_idx.* += 1;
    return .{ .int = idx };
}

fn hexDigitVal(c: u8) u4 {
    return switch (c) {
        '0'...'9' => @truncate(c - '0'),
        'a'...'f' => @truncate(c - 'a' + 10),
        'A'...'F' => @truncate(c - 'A' + 10),
        else => 0,
    };
}

fn hexChar(nibble: u4) u8 {
    const chars = "0123456789abcdef";
    return chars[nibble];
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
