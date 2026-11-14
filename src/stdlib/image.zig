// php's ext/standard/image.c (getimagesize, getimagesizefromstring,
// image_type_to_mime_type, image_type_to_extension) with the svg handler
// ext/libxml registers, and iptc.c (iptcparse, iptcembed). images are read
// through php streams exactly as php reads them, so short files, seeks past
// the end and the warnings fall out the same way
const std = @import("std");
const vm_mod = @import("../runtime/vm.zig");
const NativeContext = vm_mod.NativeContext;
const NativeResult = vm_mod.NativeResult;
const RuntimeError = vm_mod.RuntimeError;
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const streams = @import("streams.zig");
const fs = @import("filesystem.zig");
const Args = @import("string_ports.zig").Args;
const avif = @import("avifinfo.zig");
const zlib = @import("c_zlib");
const xml = @import("c_xmlreader");

pub const entries = .{
    .{ "getimagesize", native_getimagesize },
    .{ "getimagesizefromstring", native_getimagesizefromstring },
    .{ "image_type_to_mime_type", native_image_type_to_mime_type },
    .{ "image_type_to_extension", native_image_type_to_extension },
    .{ "iptcparse", native_iptcparse },
    .{ "iptcembed", native_iptcembed },
};

// IMAGE_FILETYPE_*; svg is the one handler php registers (ext/libxml), so it
// takes the first id after the fixed ones
pub const Type = enum(i64) {
    unknown = 0,
    gif = 1,
    jpeg = 2,
    png = 3,
    swf = 4,
    psd = 5,
    bmp = 6,
    tiff_ii = 7,
    tiff_mm = 8,
    jpc = 9,
    jp2 = 10,
    jpx = 11,
    jb2 = 12,
    swc = 13,
    iff = 14,
    wbmp = 15,
    xbm = 16,
    ico = 17,
    webp = 18,
    avif = 19,
    heif = 20,
    svg = 21,
    _,
};

pub const constants = .{
    .{ "IMAGETYPE_GIF", 1 },
    .{ "IMAGETYPE_JPEG", 2 },
    .{ "IMAGETYPE_PNG", 3 },
    .{ "IMAGETYPE_SWF", 4 },
    .{ "IMAGETYPE_PSD", 5 },
    .{ "IMAGETYPE_BMP", 6 },
    .{ "IMAGETYPE_TIFF_II", 7 },
    .{ "IMAGETYPE_TIFF_MM", 8 },
    .{ "IMAGETYPE_JPC", 9 },
    .{ "IMAGETYPE_JP2", 10 },
    .{ "IMAGETYPE_JPX", 11 },
    .{ "IMAGETYPE_JB2", 12 },
    .{ "IMAGETYPE_SWC", 13 },
    .{ "IMAGETYPE_IFF", 14 },
    .{ "IMAGETYPE_WBMP", 15 },
    .{ "IMAGETYPE_JPEG2000", 9 },
    .{ "IMAGETYPE_XBM", 16 },
    .{ "IMAGETYPE_ICO", 17 },
    .{ "IMAGETYPE_WEBP", 18 },
    .{ "IMAGETYPE_AVIF", 19 },
    .{ "IMAGETYPE_HEIF", 20 },
    .{ "IMAGETYPE_UNKNOWN", 0 },
    .{ "IMAGETYPE_COUNT", 22 },
    .{ "IMAGETYPE_SVG", 21 },
};

const GfxInfo = struct {
    width: u32 = 0,
    height: u32 = 0,
    bits: u32 = 0,
    channels: u32 = 0,
    // owned by the caller's allocator; null means px
    width_unit: ?[]u8 = null,
    height_unit: ?[]u8 = null,
};

// a php_stream as image.c uses it
const Src = struct {
    ctx: *NativeContext,
    obj: *PhpObject,

    fn read(self: Src, buf: []u8) RuntimeError!isize {
        if (buf.len == 0) return 0;
        return streams.read(self.ctx, self.obj, buf);
    }

    // php_stream_read(...) == n
    fn readFull(self: Src, buf: []u8) RuntimeError!bool {
        const n = try self.read(buf);
        return n >= 0 and @as(usize, @intCast(n)) == buf.len;
    }

    // php_stream_getc: -1 at the end
    fn getc(self: Src) RuntimeError!i32 {
        const c = try streams.getc(self.ctx, self.obj);
        return if (c) |b| b else -1;
    }

    // php_stream_seek: true when it failed
    fn seekCur(self: Src, offset: i64) RuntimeError!bool {
        return (try streams.seek(self.ctx, self.obj, offset, 1)) != 0;
    }

    fn seekSet(self: Src, offset: i64) RuntimeError!bool {
        return (try streams.seek(self.ctx, self.obj, offset, 0)) != 0;
    }

    fn rewind(self: Src) RuntimeError!bool {
        return self.seekSet(0);
    }

    fn eof(self: Src) RuntimeError!bool {
        return streams.eof(self.ctx, self.obj);
    }

    fn chunkSize(self: Src) usize {
        return if (streams.get(self.obj)) |s| s.chunk_size else streams.chunk_default;
    }
};

fn be16(b: []const u8) u32 {
    return (@as(u32, b[0]) << 8) | b[1];
}

fn be32(b: []const u8) u32 {
    return (@as(u32, b[0]) << 24) | (@as(u32, b[1]) << 16) | (@as(u32, b[2]) << 8) | b[3];
}

// ---------------------------------------------------------------- handlers

fn handleGif(src: Src) RuntimeError!?GfxInfo {
    if (try src.seekCur(3)) return null;
    var dim: [5]u8 = undefined;
    if (!try src.readFull(&dim)) return null;
    return .{
        .width = @as(u32, dim[0]) | (@as(u32, dim[1]) << 8),
        .height = @as(u32, dim[2]) | (@as(u32, dim[3]) << 8),
        .bits = if (dim[4] & 0x80 != 0) (@as(u32, dim[4]) & 0x07) + 1 else 0,
        .channels = 3,
    };
}

fn handlePsd(src: Src) RuntimeError!?GfxInfo {
    if (try src.seekCur(11)) return null;
    var dim: [8]u8 = undefined;
    if (!try src.readFull(&dim)) return null;
    return .{ .height = be32(dim[0..4]), .width = be32(dim[4..8]) };
}

fn handleBmp(src: Src) RuntimeError!?GfxInfo {
    if (try src.seekCur(11)) return null;
    var dim: [16]u8 = undefined;
    if (!try src.readFull(&dim)) return null;
    const size = std.mem.readInt(u32, dim[0..4], .little);
    if (size == 12) {
        return .{
            .width = std.mem.readInt(u16, dim[4..6], .little),
            .height = std.mem.readInt(u16, dim[6..8], .little),
            .bits = dim[11],
        };
    } else if (size > 12 and (size <= 64 or size == 108 or size == 124)) {
        const h: i32 = std.mem.readInt(i32, dim[8..12], .little);
        return .{
            .width = std.mem.readInt(u32, dim[4..8], .little),
            // abs((int32_t)height)
            .height = @bitCast(if (h == std.math.minInt(i32)) h else if (h < 0) -h else h),
            .bits = std.mem.readInt(u16, dim[14..16], .little),
        };
    }
    return null;
}

fn swfBits(buffer: []const u8, pos: u32, count: u32) u64 {
    var result: u64 = 0;
    var loop = pos;
    while (loop < pos + count) : (loop += 1) {
        const byte: u64 = if (loop / 8 < buffer.len) buffer[loop / 8] else 0;
        const bit = (byte >> @intCast(7 - (loop % 8))) & 1;
        const shift = count - (loop - pos) - 1;
        if (shift < 64) result +%= bit << @intCast(shift);
    }
    return result;
}

fn swfSize(b: []const u8, info: *GfxInfo) void {
    const bits: u32 = @intCast(swfBits(b, 0, 5));
    info.width = @truncate((swfBits(b, 5 + bits, bits) -% swfBits(b, 5, bits)) / 20);
    info.height = @truncate((swfBits(b, 5 + 3 * bits, bits) -% swfBits(b, 5 + 2 * bits, bits)) / 20);
}

fn handleSwf(src: Src) RuntimeError!?GfxInfo {
    if (try src.seekCur(5)) return null;
    var a: [32]u8 = undefined;
    if (!try src.readFull(&a)) return null;
    var info: GfxInfo = .{};
    swfSize(&a, &info);
    return info;
}

// a compressed swf: the first 64 bytes inflated, or the whole rest of the
// file with growing buffers, as php_handle_swc does
fn handleSwc(src: Src) RuntimeError!?GfxInfo {
    const allocator = src.ctx.allocator;
    if (try src.seekCur(5)) return null;
    var a: [64]u8 = undefined;
    if (!try src.readFull(&a)) return null;
    var b: [65]u8 = @splat(0);
    var len: zlib.uLongf = 64;
    var status: c_int = zlib.uncompress(&b, &len, &a, a.len);
    if (status != zlib.Z_OK) {
        if (try src.seekSet(8)) return null;
        const bufz = (try streams.copyToMem(src.ctx, src.obj, null)) orelse return null;
        defer allocator.free(bufz);
        var factor: u64 = 1;
        const maxfactor: u64 = 1 << 15;
        var buf: []u8 = &.{};
        defer if (buf.len > 0) allocator.free(buf);
        while (true) {
            factor <<= 1;
            if (bufz.len > std.math.maxInt(c_ulong) / factor) {
                status = zlib.Z_MEM_ERROR;
                break;
            }
            var szlength: zlib.uLongf = @intCast(bufz.len * factor);
            buf = if (buf.len == 0) allocator.alloc(u8, szlength) catch return null else allocator.realloc(buf, szlength) catch return null;
            status = zlib.uncompress(buf.ptr, &szlength, bufz.ptr, @intCast(bufz.len));
            if (!(status == zlib.Z_BUF_ERROR and factor < maxfactor)) break;
        }
        if (status == zlib.Z_OK) @memcpy(b[0..64], buf[0..64]);
    }
    if (status != 0) return null;
    var info: GfxInfo = .{};
    swfSize(&b, &info);
    return info;
}

fn handlePng(src: Src) RuntimeError!?GfxInfo {
    if (try src.seekCur(8)) return null;
    var dim: [9]u8 = undefined;
    const n = try src.read(&dim);
    if (n < dim.len) return null;
    return .{ .width = be32(dim[0..4]), .height = be32(dim[4..8]), .bits = dim[8] };
}

const M_SOF0 = 0xC0;
const M_SOF15 = 0xCF;
const M_SOI = 0xD8;
const M_EOI = 0xD9;
const M_SOS = 0xDA;
const M_APP0 = 0xe0;
const M_APP1 = 0xe1;
const M_APP13 = 0xed;
const M_APP15 = 0xef;
const M_PSEUDO = 0xFFD8;

fn isSof(marker: u32) bool {
    return switch (marker) {
        0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF => true,
        else => false,
    };
}

fn read2(src: Src) RuntimeError!u32 {
    var a: [2]u8 = undefined;
    const n = try src.read(&a);
    if (n < 2) return 0;
    return be16(&a);
}

fn read4(src: Src) RuntimeError!u32 {
    var a: [4]u8 = undefined;
    if (!try src.readFull(&a)) return 0;
    return be32(&a);
}

fn nextMarker(src: Src, ff_read: bool) RuntimeError!u32 {
    var marker: i32 = 0;
    if (!ff_read) {
        var extraneous: usize = 0;
        while (true) {
            marker = try src.getc();
            if (marker == 0xff) break;
            if (marker == -1) return M_EOI;
            extraneous += 1;
        }
        if (extraneous > 0) try fs.warnDocref(src.ctx, "Corrupt JPEG data: {d} extraneous bytes before marker", .{extraneous});
    }
    var a: u32 = 1;
    while (true) {
        marker = try src.getc();
        if (marker == -1) return M_EOI;
        a += 1;
        if (marker != 0xff) break;
    }
    if (a < 2) return M_EOI;
    return @intCast(marker);
}

fn skipVariable(src: Src) RuntimeError!bool {
    const length: i64 = try read2(src);
    if (length < 2) return false;
    _ = try src.seekCur(length - 2);
    return true;
}

fn readAllChunks(src: Src, buffer: []u8) RuntimeError!bool {
    var total: usize = 0;
    while (true) {
        const n = try src.read(buffer[total..]);
        const now: usize = if (n < 0) 0 else @intCast(n);
        total += now;
        if (now < src.chunkSize() and total != buffer.len) return false;
        if (total >= buffer.len) return true;
        if (now == 0) return false;
    }
}

fn readApp(src: Src, marker: u32, info: *PhpArray) RuntimeError!bool {
    const allocator = src.ctx.allocator;
    var length: usize = try read2(src);
    if (length < 2) return false;
    length -= 2;
    const buffer = try allocator.alloc(u8, length);
    defer allocator.free(buffer);
    if (!try readAllChunks(src, buffer)) return false;
    var name_buf: [16]u8 = undefined;
    const name = std.fmt.bufPrint(&name_buf, "APP{d}", .{marker - M_APP0}) catch unreachable;
    const key: PhpArray.Key = .{ .string = Value.String.borrowed(name) };
    // only the first tag of a kind
    if (!info.contains(key)) {
        const owned = try Value.String.create(allocator, buffer);
        defer owned.release();
        try info.setCopiedKey(allocator, name, .{ .string = owned });
    }
    return true;
}

fn handleJpeg(src: Src, info: ?*PhpArray) RuntimeError!?GfxInfo {
    var result: ?GfxInfo = null;
    var ff_read = true;
    while (true) {
        const marker = try nextMarker(src, ff_read);
        ff_read = false;
        if (isSof(marker)) {
            if (result == null) {
                var r: GfxInfo = .{};
                const length = try read2(src);
                r.bits = @bitCast(try src.getc());
                r.height = try read2(src);
                r.width = try read2(src);
                r.channels = @bitCast(try src.getc());
                result = r;
                if (info == null or length < 8) return result;
                if (try src.seekCur(@as(i64, length) - 8)) return result;
            } else if (!try skipVariable(src)) return result;
        } else if (marker >= M_APP0 and marker <= M_APP15) {
            if (info) |arr| {
                if (!try readApp(src, marker, arr)) return result;
            } else if (!try skipVariable(src)) return result;
        } else if (marker == M_SOS or marker == M_EOI) {
            return result;
        } else if (!try skipVariable(src)) return result;
    }
}

fn handleJpc(src: Src) RuntimeError!?GfxInfo {
    const first = try src.getc();
    if (first != 0x51) {
        try fs.warnDocref(src.ctx, "JPEG2000 codestream corrupt(Expected SIZ marker not found after SOC)", .{});
        return null;
    }
    var r: GfxInfo = .{};
    _ = try read2(src);
    _ = try read2(src);
    r.width = try read4(src);
    r.height = try read4(src);
    if (try src.seekCur(24)) return null;
    r.channels = try read2(src);
    if ((r.channels == 0 and try src.eof()) or r.channels > 256) return null;
    var highest: i32 = 0;
    var i: u32 = 0;
    while (i < r.channels) : (i += 1) {
        const depth = (try src.getc()) + 1;
        if (depth > highest) highest = depth;
        _ = try src.getc();
        _ = try src.getc();
    }
    r.bits = @bitCast(highest);
    return r;
}

fn handleJp2(src: Src) RuntimeError!?GfxInfo {
    var result: ?GfxInfo = null;
    while (true) {
        const box_length = try read4(src);
        var box_type: [4]u8 = undefined;
        if (!try src.readFull(&box_type)) break;
        if (box_length == 1) return null;
        if (std.mem.eql(u8, &box_type, "jp2c")) {
            _ = try src.seekCur(3);
            result = try handleJpc(src);
            break;
        }
        if (@as(i32, @bitCast(box_length)) <= 0) break;
        if (try src.seekCur(@as(i64, box_length) - 8)) break;
    }
    if (result == null) try fs.warnDocref(src.ctx, "JP2 file has no codestreams at root level", .{});
    return result;
}

fn ifd16(b: []const u8, motorola: bool) u32 {
    return if (motorola) (@as(u32, b[0]) << 8) | b[1] else (@as(u32, b[1]) << 8) | b[0];
}

fn ifd32(b: []const u8, motorola: bool) u32 {
    return if (motorola) be32(b) else std.mem.readInt(u32, b[0..4], .little);
}

fn handleTiff(src: Src, motorola: bool) RuntimeError!?GfxInfo {
    const allocator = src.ctx.allocator;
    var ifd_ptr: [4]u8 = undefined;
    if (!try src.readFull(&ifd_ptr)) return null;
    const ifd_addr: i64 = ifd32(&ifd_ptr, motorola);
    if (try src.seekCur(ifd_addr - 8)) return null;
    var head: [2]u8 = undefined;
    if (!try src.readFull(&head)) return null;
    const num_entries = ifd16(&head, motorola);
    const dir_size: usize = 2 + 12 * @as(usize, num_entries) + 4;
    const ifd_data = try allocator.alloc(u8, dir_size);
    defer allocator.free(ifd_data);
    if (!try src.readFull(ifd_data[2..])) return null;
    var width: u64 = 0;
    var height: u64 = 0;
    var i: usize = 0;
    while (i < num_entries) : (i += 1) {
        const entry = ifd_data[2 + i * 12 ..][0..12];
        const tag = ifd16(entry[0..2], motorola);
        const fmt = ifd16(entry[2..4], motorola);
        // size_t entry_value, so signed values sign-extend
        const value: u64 = switch (fmt) {
            1, 6 => entry[8],
            3 => ifd16(entry[8..10], motorola),
            8 => @bitCast(@as(i64, @as(i16, @bitCast(@as(u16, @intCast(ifd16(entry[8..10], motorola))))))),
            4 => ifd32(entry[8..12], motorola),
            9 => @bitCast(@as(i64, @as(i32, @bitCast(ifd32(entry[8..12], motorola))))),
            else => continue,
        };
        switch (tag) {
            0x0100, 0xA002 => width = value,
            0x0101, 0xA003 => height = value,
            else => {},
        }
    }
    if (width != 0 and height != 0) return .{ .width = @truncate(width), .height = @truncate(height) };
    return null;
}

fn handleIff(src: Src) RuntimeError!?GfxInfo {
    var a: [10]u8 = undefined;
    if (!try src.readFull(a[0..8])) return null;
    if (!std.mem.eql(u8, a[4..8], "ILBM") and !std.mem.eql(u8, a[4..8], "PBM ")) return null;
    while (true) {
        if (!try src.readFull(a[0..8])) return null;
        const chunk_id: i32 = @bitCast(be32(a[0..4]));
        var size: i32 = @bitCast(be32(a[4..8]));
        if (size < 0) return null;
        if (size & 1 == 1) {
            if (size == std.math.maxInt(i32)) return null;
            size += 1;
        }
        if (chunk_id == 0x424d4844) {
            if (size < 9 or !try src.readFull(a[0..9])) return null;
            const width: i16 = @bitCast(@as(u16, @intCast(be16(a[0..2]))));
            const height: i16 = @bitCast(@as(u16, @intCast(be16(a[2..4]))));
            const bits: i16 = a[8];
            if (width > 0 and height > 0 and bits > 0 and bits < 33) {
                return .{ .width = @intCast(width), .height = @intCast(height), .bits = @intCast(bits) };
            }
        } else if (try src.seekCur(size)) return null;
    }
}

// php_get_wbmp: the type when the stream reads as one, with its size
fn getWbmp(src: Src, result: ?*GfxInfo) RuntimeError!bool {
    if (try src.rewind()) return false;
    if (try src.getc() != 0) return false;
    var i: i32 = 0;
    while (true) {
        i = try src.getc();
        if (i < 0) return false;
        if (i & 0x80 == 0) break;
    }
    var width: i32 = 0;
    var height: i32 = 0;
    while (true) {
        i = try src.getc();
        if (i < 0) return false;
        width = (width << 7) | (i & 0x7f);
        if (width > 2048) return false;
        if (i & 0x80 == 0) break;
    }
    while (true) {
        i = try src.getc();
        if (i < 0) return false;
        height = (height << 7) | (i & 0x7f);
        if (height > 2048) return false;
        if (i & 0x80 == 0) break;
    }
    if (height == 0 or width == 0) return false;
    if (result) |r| {
        r.width = @intCast(width);
        r.height = @intCast(height);
    }
    return true;
}

// sscanf(fline, "#define %s %d", iname, &value) == 2
fn scanDefine(line: []const u8) ?struct { name: []const u8, value: i32 } {
    var rest = line;
    if (!std.mem.startsWith(u8, rest, "#define")) return null;
    rest = rest["#define".len..];
    // a space in the format matches any run of whitespace, including none
    rest = std.mem.trimStart(u8, rest, " \t\n\r\x0b\x0c");
    var end: usize = 0;
    while (end < rest.len and !std.ascii.isWhitespace(rest[end])) end += 1;
    if (end == 0) return null;
    const name = rest[0..end];
    rest = std.mem.trimStart(u8, rest[end..], " \t\n\r\x0b\x0c");
    var j: usize = 0;
    if (j < rest.len and (rest[j] == '-' or rest[j] == '+')) j += 1;
    const digits_start = j;
    while (j < rest.len and std.ascii.isDigit(rest[j])) j += 1;
    if (j == digits_start) return null;
    const parsed = std.fmt.parseInt(i64, rest[0..j], 10) catch blk: {
        break :blk if (rest[0] == '-') @as(i64, std.math.minInt(i64)) else @as(i64, std.math.maxInt(i64));
    };
    return .{ .name = name, .value = @truncate(parsed) };
}

fn getXbm(src: Src, result: ?*GfxInfo) RuntimeError!bool {
    const allocator = src.ctx.allocator;
    if (try src.rewind()) return false;
    var width: u32 = 0;
    var height: u32 = 0;
    while (try streams.getLine(src.ctx, src.obj, null)) |line| {
        defer allocator.free(line);
        const def = scanDefine(line) orelse continue;
        const kind = if (std.mem.lastIndexOfScalar(u8, def.name, '_')) |u| def.name[u + 1 ..] else def.name;
        if (std.mem.eql(u8, kind, "width")) {
            width = @bitCast(def.value);
            if (height != 0) break;
        }
        if (std.mem.eql(u8, kind, "height")) {
            height = @bitCast(def.value);
            if (width != 0) break;
        }
    }
    if (width != 0 and height != 0) {
        if (result) |r| {
            r.width = width;
            r.height = height;
        }
        return true;
    }
    return false;
}

fn handleIco(src: Src) RuntimeError!?GfxInfo {
    var dim: [16]u8 = undefined;
    if (!try src.readFull(dim[0..2])) return null;
    var num_icons: u32 = std.mem.readInt(u16, dim[0..2], .little);
    if (num_icons < 1 or num_icons > 255) return null;
    var r: GfxInfo = .{};
    while (num_icons > 0) : (num_icons -= 1) {
        if (!try src.readFull(&dim)) break;
        const bits: u32 = std.mem.readInt(u16, dim[6..8], .little);
        if (bits >= r.bits) {
            r.width = dim[0];
            r.height = dim[1];
            r.bits = bits;
        }
    }
    if (r.width == 0) r.width = 256;
    if (r.height == 0) r.height = 256;
    return r;
}

fn handleWebp(src: Src) RuntimeError!?GfxInfo {
    var buf: [18]u8 = undefined;
    if (!try src.readFull(&buf)) return null;
    if (!std.mem.eql(u8, buf[0..3], "VP8")) return null;
    var r: GfxInfo = .{ .bits = 8 };
    switch (buf[3]) {
        ' ' => {
            r.width = buf[14] + (@as(u32, buf[15] & 0x3F) << 8);
            r.height = buf[16] + (@as(u32, buf[17] & 0x3F) << 8);
        },
        'L' => {
            r.width = buf[9] + (@as(u32, buf[10] & 0x3F) << 8) + 1;
            r.height = (buf[10] >> 6) + (@as(u32, buf[11]) << 2) + (@as(u32, buf[12] & 0xF) << 10) + 1;
        },
        'X' => {
            r.width = buf[12] + (@as(u32, buf[13]) << 8) + (@as(u32, buf[14]) << 16) + 1;
            r.height = buf[15] + (@as(u32, buf[16]) << 8) + (@as(u32, buf[17]) << 16) + 1;
        },
        else => return null,
    }
    return r;
}

// the stream as libavifinfo reads it: a failed read or seek fails every
// later call
const AvifStream = struct {
    src: Src,
    failed: bool = false,
    buffer: [avif.max_num_read_bytes]u8 = undefined,
    err: ?RuntimeError = null,

    pub fn read(self: *AvifStream, n: usize) ?[]const u8 {
        if (self.failed) return null;
        const got = self.src.read(self.buffer[0..n]) catch |e| {
            self.err = e;
            self.failed = true;
            return null;
        };
        if (got < 0 or @as(usize, @intCast(got)) != n) {
            self.failed = true;
            return null;
        }
        return self.buffer[0..n];
    }

    pub fn skip(self: *AvifStream, n: usize) void {
        if (self.failed) return;
        const failed = self.src.seekCur(@intCast(n)) catch |e| {
            self.err = e;
            self.failed = true;
            return;
        };
        if (failed) self.failed = true;
    }
};

fn handleAvif(src: Src) RuntimeError!?GfxInfo {
    var stream: AvifStream = .{ .src = src };
    const features = avif.getFeaturesStream(&stream);
    if (stream.err) |e| return e;
    const f = features orelse return null;
    return .{ .width = f.width, .height = f.height, .bits = f.bit_depth, .channels = f.num_channels };
}

fn isAvif(src: Src) RuntimeError!bool {
    var stream: AvifStream = .{ .src = src };
    const ok = avif.identifyStream(&stream);
    if (stream.err) |e| return e;
    return ok;
}

// ext/libxml's svg handler: the root element must be <svg> with a width and
// height of digits and an optional unit
fn parseDimension(input: []const u8) ?usize {
    if (input.len == 0 or !std.ascii.isDigit(input[0])) return null;
    var i: usize = 1;
    while (i < input.len and std.ascii.isDigit(input[i])) i += 1;
    const unit = i;
    while (i < input.len) : (i += 1) {
        if (!std.ascii.isAlphabetic(input[i])) return null;
    }
    return unit;
}

fn svgHandle(src: Src, want: bool) RuntimeError!?GfxInfo {
    const allocator = src.ctx.allocator;
    if (try src.rewind()) return null;
    if (try src.getc() != '<') return null;
    if (try src.rewind()) return null;
    const data = (try streams.copyToMem(src.ctx, src.obj, null)) orelse return null;
    defer allocator.free(data);
    const reader = xml.xmlReaderForMemory(data.ptr, @intCast(data.len), null, null, xml.XML_PARSE_NOWARNING | xml.XML_PARSE_NOERROR | xml.XML_PARSE_NONET) orelse return null;
    defer xml.xmlFreeTextReader(reader);
    while (xml.xmlTextReaderRead(reader) == 1) {
        if (xml.xmlTextReaderNodeType(reader) != xml.XML_READER_TYPE_ELEMENT) continue;
        const name_ptr = xml.xmlTextReaderConstLocalName(reader);
        if (name_ptr == null or !std.ascii.eqlIgnoreCase(std.mem.span(@as([*:0]const u8, @ptrCast(name_ptr))), "svg")) return null;
        const w_ptr = xml.xmlTextReaderGetAttribute(reader, "width");
        defer if (w_ptr != null) xml.xmlFree.?(w_ptr);
        const h_ptr = xml.xmlTextReaderGetAttribute(reader, "height");
        defer if (h_ptr != null) xml.xmlFree.?(h_ptr);
        if (w_ptr == null or h_ptr == null) return null;
        const w = std.mem.span(@as([*:0]const u8, @ptrCast(w_ptr)));
        const h = std.mem.span(@as([*:0]const u8, @ptrCast(h_ptr)));
        const wu = parseDimension(w) orelse return null;
        const hu = parseDimension(h) orelse return null;
        var r: GfxInfo = .{};
        if (!want) return r;
        r.width = @truncate(@as(u64, @bitCast(strtol(w[0..wu]))));
        r.height = @truncate(@as(u64, @bitCast(strtol(h[0..hu]))));
        if (wu < w.len) r.width_unit = try allocator.dupe(u8, w[wu..]);
        if (hu < h.len) r.height_unit = try allocator.dupe(u8, h[hu..]);
        return r;
    }
    return null;
}

// ZEND_STRTOL over digits: saturates
fn strtol(digits: []const u8) i64 {
    return std.fmt.parseInt(i64, digits, 10) catch std.math.maxInt(i64);
}

// ---------------------------------------------------------------- detection

fn readError(src: Src, input: []const u8) RuntimeError!Type {
    try fs.noticeDocref(src.ctx, "Error reading from {s}!", .{input});
    return .unknown;
}

// php_getimagetype
fn getImageType(src: Src, input: []const u8) RuntimeError!Type {
    var ft: [12]u8 = undefined;
    if (!try src.readFull(ft[0..3])) return readError(src, input);
    if (std.mem.eql(u8, ft[0..3], "GIF")) return .gif;
    if (std.mem.eql(u8, ft[0..3], "\xff\xd8\xff")) return .jpeg;
    if (std.mem.eql(u8, ft[0..3], "\x89PN")) {
        if (!try src.readFull(ft[3..8])) return readError(src, input);
        if (std.mem.eql(u8, ft[0..8], "\x89PNG\x0d\x0a\x1a\x0a")) return .png;
        try fs.warnDocref(src.ctx, "PNG file corrupted by ASCII conversion", .{});
        return .unknown;
    }
    if (std.mem.eql(u8, ft[0..3], "FWS")) return .swf;
    if (std.mem.eql(u8, ft[0..3], "CWS")) return .swc;
    if (std.mem.eql(u8, ft[0..3], "8BP")) return .psd;
    if (std.mem.eql(u8, ft[0..2], "BM")) return .bmp;
    if (std.mem.eql(u8, ft[0..3], "\xff\x4f\xff")) return .jpc;
    if (std.mem.eql(u8, ft[0..3], "RIF")) {
        if (!try src.readFull(ft[3..12])) return readError(src, input);
        if (std.mem.eql(u8, ft[8..12], "WEBP")) return .webp;
        return .unknown;
    }
    if (!try src.readFull(ft[3..4])) return readError(src, input);
    if (std.mem.eql(u8, ft[0..4], "II\x2a\x00")) return .tiff_ii;
    if (std.mem.eql(u8, ft[0..4], "MM\x00\x2a")) return .tiff_mm;
    if (std.mem.eql(u8, ft[0..4], "FORM")) return .iff;
    if (std.mem.eql(u8, ft[0..4], "\x00\x00\x01\x00")) return .ico;
    // a wbmp may be shorter than twelve bytes
    const twelve = try src.readFull(ft[4..12]);
    if (twelve and std.mem.eql(u8, &ft, "\x00\x00\x00\x0c\x6a\x50\x20\x20\x0d\x0a\x87\x0a")) return .jp2;
    if (!try src.rewind() and try isAvif(src)) return .avif;
    // after the avif check, which would otherwise read as heif (GH-20201)
    if (twelve and std.mem.eql(u8, ft[4..8], "ftyp") and
        (std.mem.eql(u8, ft[8..12], "mif1") or std.mem.eql(u8, ft[8..12], "heic") or std.mem.eql(u8, ft[8..12], "heix"))) return .heif;
    if (try getWbmp(src, null)) return .wbmp;
    if (!twelve) return readError(src, input);
    if (try getXbm(src, null)) return .xbm;
    // the registered handlers: svg
    if (try svgHandle(src, false) != null) return .svg;
    return .unknown;
}

pub fn mimeType(t: i64) []const u8 {
    return switch (t) {
        1 => "image/gif",
        2 => "image/jpeg",
        3 => "image/png",
        4, 13 => "application/x-shockwave-flash",
        5 => "image/psd",
        6 => "image/bmp",
        7, 8 => "image/tiff",
        14 => "image/iff",
        15 => "image/vnd.wap.wbmp",
        9 => "application/octet-stream",
        10 => "image/jp2",
        16 => "image/xbm",
        17 => "image/vnd.microsoft.icon",
        18 => "image/webp",
        19 => "image/avif",
        20 => "image/heif",
        21 => "image/svg+xml",
        else => "application/octet-stream",
    };
}

fn extension(t: i64) ?[]const u8 {
    return switch (t) {
        1 => ".gif",
        2 => ".jpeg",
        3 => ".png",
        4, 13 => ".swf",
        5 => ".psd",
        6, 15 => ".bmp",
        7, 8 => ".tiff",
        14 => ".iff",
        9 => ".jpc",
        10 => ".jp2",
        11 => ".jpx",
        12 => ".jb2",
        16 => ".xbm",
        17 => ".ico",
        18 => ".webp",
        19 => ".avif",
        20 => ".heif",
        21 => ".svg",
        else => null,
    };
}

fn fromStream(ctx: *NativeContext, src: Src, input: []const u8, info: ?*PhpArray) RuntimeError!NativeResult {
    const t = try getImageType(src, input);
    var result: ?GfxInfo = switch (t) {
        .gif => try handleGif(src),
        .jpeg => try handleJpeg(src, info),
        .png => try handlePng(src),
        .swf => try handleSwf(src),
        .swc => try handleSwc(src),
        .psd => try handlePsd(src),
        .bmp => try handleBmp(src),
        .tiff_ii => try handleTiff(src, false),
        .tiff_mm => try handleTiff(src, true),
        .jpc => try handleJpc(src),
        .jp2 => try handleJp2(src),
        .iff => try handleIff(src),
        .wbmp => blk: {
            var r: GfxInfo = .{};
            break :blk if (try getWbmp(src, &r)) r else null;
        },
        .xbm => blk: {
            var r: GfxInfo = .{};
            break :blk if (try getXbm(src, &r)) r else null;
        },
        .ico => try handleIco(src),
        .webp => try handleWebp(src),
        .avif => try handleAvif(src),
        .heif => if (!try src.rewind()) try handleAvif(src) else null,
        .svg => try svgHandle(src, true),
        else => null,
    };
    const r = &(result orelse return NativeResult.scalar(.{ .bool = false }));
    defer {
        if (r.width_unit) |u| ctx.allocator.free(u);
        if (r.height_unit) |u| ctx.allocator.free(u);
    }
    const arr = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .int = 0 }, .{ .int = r.width });
    try arr.set(ctx.allocator, .{ .int = 1 }, .{ .int = r.height });
    try arr.set(ctx.allocator, .{ .int = 2 }, .{ .int = @intFromEnum(t) });
    const px_w = r.width_unit == null or std.mem.eql(u8, r.width_unit.?, "px");
    const px_h = r.height_unit == null or std.mem.eql(u8, r.height_unit.?, "px");
    if (px_w and px_h) {
        // printed with %d
        var buf: [64]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "width=\"{d}\" height=\"{d}\"", .{ @as(i32, @bitCast(r.width)), @as(i32, @bitCast(r.height)) }) catch unreachable;
        try arr.setCopiedString(ctx.allocator, .{ .int = 3 }, text);
    }
    if (r.bits != 0) try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("bits") }, .{ .int = r.bits });
    if (r.channels != 0) try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("channels") }, .{ .int = r.channels });
    try arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("mime") }, mimeType(@intFromEnum(t)));
    try arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("width_unit") }, r.width_unit orelse "px");
    try arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("height_unit") }, r.height_unit orelse "px");
    return NativeResult.borrowed(.{ .array = arr });
}

fn fromAny(ctx: *NativeContext, args: []const Value, comptime from_path: bool) RuntimeError!NativeResult {
    const name = if (from_path) "getimagesize" else "getimagesizefromstring";
    const p = Args.init(ctx, name, args);
    const input = if (from_path) try p.path(0, "filename") else try p.str(0, "string");
    // zend_try_array_init: the second argument is an empty array first
    var info: ?*PhpArray = null;
    if (args.len >= 2) {
        const arr = try ctx.createArray();
        ctx.setCallerVar(1, args.len, .{ .array = arr });
        info = arr;
    }
    const stream: Value = if (from_path)
        (try fs.openStreamValue(ctx, input, "rb", null)) orelse return NativeResult.scalar(.{ .bool = false })
    else blk: {
        const obj = try ctx.createResource("FileHandle");
        const s = try streams.attach(ctx, obj, .{ .memory = .readonly, .greedy = true, .no_buffer = true });
        try streams.setMemory(s, input);
        try obj.set(ctx.allocator, "__open", .{ .bool = true });
        try obj.setCopiedString(ctx.allocator, "__mode", "rb");
        try obj.setCopiedString(ctx.allocator, "__path", "php://memory");
        break :blk .{ .resource = obj };
    };
    stream.resource.retain();
    defer ctx.vm.releaseValue(stream);
    const result = fromStream(ctx, .{ .ctx = ctx, .obj = stream.resource }, input, info) catch |err| {
        _ = fs.closeStream(ctx, stream.resource) catch {};
        return err;
    };
    _ = try fs.closeStream(ctx, stream.resource);
    return result;
}

fn native_getimagesize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return fromAny(ctx, args, true);
}

fn native_getimagesizefromstring(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return fromAny(ctx, args, false);
}

fn native_image_type_to_mime_type(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "image_type_to_mime_type", args);
    return NativeResult.copyString(ctx.allocator, mimeType(try p.long(0, "image_type")));
}

fn native_image_type_to_extension(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "image_type_to_extension", args);
    const t = try p.long(0, "image_type");
    const inc_dot = try p.boolean(1, "include_dot", true);
    const ext = extension(t) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.copyString(ctx.allocator, if (inc_dot) ext else ext[1..]);
}

// ---------------------------------------------------------------- iptc

fn native_iptcparse(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "iptcparse", args);
    const buffer = try p.str(0, "iptc_block");
    const len = buffer.len;
    var inx: usize = 0;
    // the byte past the end reads as php's terminating nul
    const at = struct {
        fn f(b: []const u8, i: usize) u8 {
            return if (i < b.len) b[i] else 0;
        }
    }.f;
    while (inx < len) {
        if (buffer[inx] == 0x1c and (at(buffer, inx + 1) == 0x01 or at(buffer, inx + 1) == 0x02)) break;
        inx += 1;
    }
    var result: ?*PhpArray = null;
    while (inx < len) {
        if (buffer[inx] != 0x1c) break;
        inx += 1;
        if (inx + 4 >= len) break;
        const dataset = buffer[inx];
        const recnum = buffer[inx + 1];
        inx += 2;
        var size: usize = 0;
        if (buffer[inx] & 0x80 != 0) {
            if (inx + 6 >= len) break;
            size = be32(buffer[inx + 2 .. inx + 6]);
            inx += 6;
        } else {
            size = be16(buffer[inx .. inx + 2]);
            inx += 2;
        }
        if (size > len or inx + size > len) break;
        var key_buf: [16]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "{d}#{d:0>3}", .{ dataset, recnum }) catch unreachable;
        const out = result orelse blk: {
            const created = try ctx.createArray();
            result = created;
            break :blk created;
        };
        const k: PhpArray.Key = .{ .string = Value.String.borrowed(key) };
        const list = if (out.contains(k)) out.get(k).array else blk: {
            const created = try ctx.createArray();
            try out.setCopiedKey(ctx.allocator, key, .{ .array = created });
            break :blk created;
        };
        try list.appendCopiedString(ctx.allocator, buffer[inx .. inx + size]);
        inx += size;
    }
    if (result) |r| return NativeResult.borrowed(.{ .array = r });
    return NativeResult.scalar(.{ .bool = false });
}

// iptc.c's spool: 0 returns the new file, 1 also prints it, 2 only prints it
const Spool = struct {
    ctx: *NativeContext,
    data: []const u8,
    pos: usize = 0,
    spool: i64,
    buf: ?std.ArrayListUnmanaged(u8),
    cap: usize = 0,

    // PUTC: php_output_write, so an output handler sees every byte
    fn emit(self: *Spool, c: u8) RuntimeError!void {
        const vm = self.ctx.vm;
        try vm.output.append(self.ctx.allocator, c);
        if (vm.ob_stack.items.len == 0) vm.headers_sent = true;
        if (vm.ob_chunk_watch) try @import("output_control.zig").checkChunks(vm);
    }

    fn put1(self: *Spool, c: u8) RuntimeError!bool {
        if (self.spool > 0) try self.emit(c);
        if (self.buf) |*b| {
            if (b.items.len >= self.cap) return false;
            try b.append(self.ctx.allocator, c);
        }
        return true;
    }

    fn getRaw(self: *Spool) ?u8 {
        if (self.pos >= self.data.len) return null;
        self.pos += 1;
        return self.data[self.pos - 1];
    }

    // php_iptc_get1: null for EOF (also when the spool buffer is full)
    fn get1(self: *Spool, spool: bool) RuntimeError!?u8 {
        const c = self.getRaw() orelse return null;
        if (spool) {
            if (self.spool > 0) try self.emit(c);
            if (self.buf) |*b| {
                if (b.items.len >= self.cap) return null;
                try b.append(self.ctx.allocator, c);
            }
        }
        return c;
    }

    fn readRemaining(self: *Spool) RuntimeError!void {
        while (try self.get1(true) != null) {}
    }

    fn skipVariable(self: *Spool, spool: bool) RuntimeError!void {
        const c1 = (try self.get1(spool)) orelse return;
        const c2 = (try self.get1(spool)) orelse return;
        var length: u32 = (@as(u32, c1) << 8) + c2;
        length -%= 2;
        while (length > 0) : (length -= 1) {
            if (try self.get1(spool) == null) return;
        }
    }

    fn nextMarker(self: *Spool) RuntimeError!u32 {
        var c = (try self.get1(true)) orelse return M_EOI;
        while (c != 0xff) c = (try self.get1(true)) orelse return M_EOI;
        while (true) {
            c = self.getRaw() orelse return M_EOI;
            if (c == 0xff) _ = try self.put1(c) else break;
        }
        return c;
    }
};

fn native_iptcembed(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "iptcembed", args);
    const iptc_in = try p.str(0, "iptc_data");
    const path = try p.path(1, "filename");
    const spool: i64 = if (args.len > 2) try p.long(2, "spool") else 0;
    if (try fs.basedirDenies(ctx, "iptcembed", path)) return NativeResult.scalar(.{ .bool = false });
    const data = @import("../bundle.zig").readFileAlloc(ctx.allocator, path, std.math.maxInt(usize)) catch {
        try fs.warnDocref(ctx, "Unable to open {s}", .{path});
        return NativeResult.scalar(.{ .bool = false });
    };
    defer ctx.allocator.free(data);
    var psheader = "\xFF\xED\x00\x00Photoshop 3.0\x008BIM\x04\x04\x00\x00\x00\x00".*;
    var s: Spool = .{ .ctx = ctx, .data = data, .spool = spool, .buf = null };
    if (spool < 2) {
        s.buf = .empty;
        // php sizes the buffer from the data, its header (with the nul) and
        // the file
        s.cap = iptc_in.len + (psheader.len + 1) + 1024 + 1 + data.len;
    }
    defer if (s.buf) |*b| b.deinit(ctx.allocator);
    if (try s.get1(true) != 0xFF) return NativeResult.scalar(.{ .bool = false });
    if (try s.get1(true) != 0xD8) return NativeResult.scalar(.{ .bool = false });
    var iptc_len = iptc_in.len;
    var written = false;
    var done = false;
    while (!done) {
        const marker = try s.nextMarker();
        if (marker == M_EOI) break;
        if (marker != M_APP13) {
            if (!try s.put1(@intCast(marker))) return NativeResult.scalar(.{ .bool = false });
        }
        switch (marker) {
            M_APP13 => {
                // the old APP13 is dropped for the new one
                try s.skipVariable(false);
                _ = s.getRaw();
                try s.readRemaining();
                done = true;
            },
            M_APP0, M_APP1 => {
                if (written) continue;
                written = true;
                try s.skipVariable(true);
                if (iptc_len & 1 != 0) iptc_len += 1;
                psheader[2] = @truncate((iptc_len + 28) >> 8);
                psheader[3] = @truncate(iptc_len + 28);
                for (psheader[0..28]) |c| if (!try s.put1(c)) return NativeResult.scalar(.{ .bool = false });
                if (!try s.put1(@truncate(iptc_len >> 8))) return NativeResult.scalar(.{ .bool = false });
                if (!try s.put1(@truncate(iptc_len))) return NativeResult.scalar(.{ .bool = false });
                // an odd length reads the string's terminating nul
                for (0..iptc_len) |i| if (!try s.put1(if (i < iptc_in.len) iptc_in[i] else 0)) return NativeResult.scalar(.{ .bool = false });
            },
            M_SOS => {
                try s.readRemaining();
                done = true;
            },
            else => try s.skipVariable(true),
        }
    }
    if (spool < 2) return NativeResult.copyString(ctx.allocator, s.buf.?.items);
    return NativeResult.scalar(.{ .bool = true });
}
