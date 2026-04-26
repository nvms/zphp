const std = @import("std");
const zlib = @cImport(@cInclude("zlib.h"));

const Allocator = std.mem.Allocator;

pub const ParseError = error{
    NotAPhar,
    BadManifest,
    UnsupportedCompression,
    CorruptCompressedData,
    EntryNotFound,
    OutOfMemory,
};

pub const Entry = struct {
    name: []const u8,
    uncompressed_size: u32,
    compressed_size: u32,
    timestamp: u32,
    crc32: u32,
    flags: u32,
    data_offset: usize, // absolute offset in the raw phar bytes
};

pub const Phar = struct {
    raw: []const u8, // owned by caller
    entries: std.StringHashMapUnmanaged(Entry),
    dirs: std.StringHashMapUnmanaged(void), // synthesized intermediate directories

    pub fn deinit(self: *Phar, a: Allocator) void {
        var it = self.entries.iterator();
        while (it.next()) |kv| a.free(kv.key_ptr.*);
        self.entries.deinit(a);
        var dit = self.dirs.iterator();
        while (dit.next()) |kv| a.free(kv.key_ptr.*);
        self.dirs.deinit(a);
    }

    pub fn lookup(self: *const Phar, name: []const u8) ?Entry {
        return self.entries.get(name);
    }

    pub fn isDir(self: *const Phar, name: []const u8) bool {
        if (name.len == 0) return true;
        return self.dirs.contains(name);
    }
};

// compression flag bits in entry.flags
pub const COMPRESSION_MASK: u32 = 0x0000F000;
pub const COMPRESSED_GZ: u32 = 0x00001000;
pub const COMPRESSED_BZ2: u32 = 0x00002000;

pub const HALT_TOKEN = "__HALT_COMPILER();";

fn findManifestStart(raw: []const u8) ?usize {
    const idx = std.mem.indexOf(u8, raw, HALT_TOKEN) orelse return null;
    var p = idx + HALT_TOKEN.len;
    // skip optional whitespace, then optional ?>, then optional CR/LF
    while (p < raw.len and (raw[p] == ' ' or raw[p] == '\t')) p += 1;
    if (p + 2 <= raw.len and raw[p] == '?' and raw[p + 1] == '>') p += 2;
    if (p < raw.len and raw[p] == '\r') p += 1;
    if (p < raw.len and raw[p] == '\n') p += 1;
    return p;
}

const Reader = struct {
    raw: []const u8,
    pos: usize,

    fn need(self: *Reader, n: usize) ParseError!void {
        if (self.pos + n > self.raw.len) return ParseError.BadManifest;
    }
    fn u32le(self: *Reader) ParseError!u32 {
        try self.need(4);
        const v = std.mem.readInt(u32, self.raw[self.pos..][0..4], .little);
        self.pos += 4;
        return v;
    }
    fn u16be(self: *Reader) ParseError!u16 {
        try self.need(2);
        const v = std.mem.readInt(u16, self.raw[self.pos..][0..2], .big);
        self.pos += 2;
        return v;
    }
    fn slice(self: *Reader, n: u32) ParseError![]const u8 {
        try self.need(n);
        const s = self.raw[self.pos .. self.pos + n];
        self.pos += n;
        return s;
    }
};

pub fn parse(a: Allocator, raw: []const u8) ParseError!Phar {
    const m_start = findManifestStart(raw) orelse return ParseError.NotAPhar;
    var r = Reader{ .raw = raw, .pos = m_start };
    const manifest_len = try r.u32le();
    const num_files = try r.u32le();
    _ = try r.u16be(); // api version
    _ = try r.u32le(); // global flags
    const alias_len = try r.u32le();
    _ = try r.slice(alias_len);
    const meta_len = try r.u32le();
    _ = try r.slice(meta_len);

    var phar = Phar{
        .raw = raw,
        .entries = .{},
        .dirs = .{},
    };
    errdefer phar.deinit(a);

    // read entries (just metadata; data offsets computed after the loop)
    const EntryRaw = struct {
        name: []const u8,
        uncompressed_size: u32,
        compressed_size: u32,
        timestamp: u32,
        crc32: u32,
        flags: u32,
    };
    var entry_list = std.ArrayListUnmanaged(EntryRaw){};
    defer entry_list.deinit(a);

    var i: u32 = 0;
    while (i < num_files) : (i += 1) {
        const name_len = try r.u32le();
        const name = try r.slice(name_len);
        const uncompressed_size = try r.u32le();
        const timestamp = try r.u32le();
        const compressed_size = try r.u32le();
        const crc32 = try r.u32le();
        const flags = try r.u32le();
        const entry_meta_len = try r.u32le();
        _ = try r.slice(entry_meta_len);
        try entry_list.append(a, .{
            .name = name,
            .uncompressed_size = uncompressed_size,
            .compressed_size = compressed_size,
            .timestamp = timestamp,
            .crc32 = crc32,
            .flags = flags,
        });
    }

    // sanity: r.pos should equal m_start + 4 + manifest_len (the 4 is the length field itself)
    const expected_end = m_start + 4 + manifest_len;
    if (r.pos != expected_end) return ParseError.BadManifest;

    // file data follows the manifest, entries packed in declaration order
    var data_pos: usize = expected_end;
    for (entry_list.items) |er| {
        const name_copy = try a.dupe(u8, er.name);
        errdefer a.free(name_copy);
        try phar.entries.put(a, name_copy, .{
            .name = name_copy,
            .uncompressed_size = er.uncompressed_size,
            .compressed_size = er.compressed_size,
            .timestamp = er.timestamp,
            .crc32 = er.crc32,
            .flags = er.flags,
            .data_offset = data_pos,
        });
        data_pos += er.compressed_size;
        // synthesize parent directories
        var slash_search: usize = name_copy.len;
        while (slash_search > 0) {
            slash_search -= 1;
            if (name_copy[slash_search] == '/') {
                const dir = name_copy[0..slash_search];
                if (dir.len == 0) break;
                if (!phar.dirs.contains(dir)) {
                    const dir_copy = try a.dupe(u8, dir);
                    try phar.dirs.put(a, dir_copy, {});
                }
            }
        }
    }

    return phar;
}

pub fn extract(a: Allocator, phar: *const Phar, entry: Entry) ![]u8 {
    if (entry.data_offset + entry.compressed_size > phar.raw.len) return ParseError.BadManifest;
    const blob = phar.raw[entry.data_offset .. entry.data_offset + entry.compressed_size];
    const compression = entry.flags & COMPRESSION_MASK;
    return switch (compression) {
        0 => try a.dupe(u8, blob),
        COMPRESSED_GZ => try inflateRaw(a, blob, entry.uncompressed_size),
        COMPRESSED_BZ2 => ParseError.UnsupportedCompression,
        else => ParseError.UnsupportedCompression,
    };
}

pub const default_stub = "<?php __HALT_COMPILER(); ?>\r\n";

pub const SIG_FLAG_MD5: u32 = 0x0001;
pub const SIG_FLAG_SHA1: u32 = 0x0002;

pub const GLOBAL_FLAG_SIGNATURE: u32 = 0x00010000;

pub const WriteEntry = struct {
    name: []const u8,
    contents: []const u8,
    timestamp: u32 = 0,
    compress: u32 = 0, // 0, COMPRESSED_GZ, or COMPRESSED_BZ2
};

// builds a complete phar byte stream: stub, manifest, file data, signature.
// caller owns returned bytes
pub fn write(a: Allocator, stub: []const u8, alias: []const u8, entries: []const WriteEntry) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(a);

    // stub must contain __HALT_COMPILER();. if it doesn't, fall back to default
    const effective_stub = if (std.mem.indexOf(u8, stub, HALT_TOKEN) != null) stub else default_stub;
    try buf.appendSlice(a, effective_stub);
    if (std.mem.indexOf(u8, effective_stub, HALT_TOKEN) != null and !std.mem.endsWith(u8, effective_stub, "\n")) {
        try buf.appendSlice(a, "\r\n");
    }

    // compress entry data first so we know compressed sizes for the manifest
    var blobs = try a.alloc([]u8, entries.len);
    defer {
        for (blobs) |b| a.free(b);
        a.free(blobs);
    }
    for (entries, 0..) |entry, i| {
        if (entry.compress == COMPRESSED_GZ and entry.contents.len > 0) {
            blobs[i] = try deflateRaw(a, entry.contents);
        } else {
            blobs[i] = try a.dupe(u8, entry.contents);
        }
    }

    // build manifest body (everything after the 4-byte length prefix, up through per-file entries)
    var mbody = std.ArrayListUnmanaged(u8){};
    defer mbody.deinit(a);

    try writeU32LE(a, &mbody, @intCast(entries.len));
    try writeU16BE(a, &mbody, 0x1100); // api 1.1.0
    try writeU32LE(a, &mbody, GLOBAL_FLAG_SIGNATURE);
    try writeU32LE(a, &mbody, @intCast(alias.len));
    try mbody.appendSlice(a, alias);
    try writeU32LE(a, &mbody, 0); // global metadata length

    for (entries, 0..) |entry, i| {
        const blob = blobs[i];
        try writeU32LE(a, &mbody, @intCast(entry.name.len));
        try mbody.appendSlice(a, entry.name);
        try writeU32LE(a, &mbody, @intCast(entry.contents.len));
        try writeU32LE(a, &mbody, entry.timestamp);
        try writeU32LE(a, &mbody, @intCast(blob.len));
        try writeU32LE(a, &mbody, crc32sum(entry.contents));
        try writeU32LE(a, &mbody, entry.compress);
        try writeU32LE(a, &mbody, 0); // entry metadata length
    }

    // emit manifest length + body
    try writeU32LE(a, &buf, @intCast(mbody.items.len));
    try buf.appendSlice(a, mbody.items);

    // emit file data
    for (blobs) |blob| try buf.appendSlice(a, blob);

    // signature: SHA1 over everything written so far (stub + manifest + data)
    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(buf.items);
    var digest: [20]u8 = undefined;
    hasher.final(&digest);
    try buf.appendSlice(a, &digest);
    try writeU32LE(a, &buf, SIG_FLAG_SHA1);
    try buf.appendSlice(a, "GBMB");

    return try buf.toOwnedSlice(a);
}

fn writeU32LE(a: Allocator, buf: *std.ArrayListUnmanaged(u8), v: u32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, v, .little);
    try buf.appendSlice(a, &bytes);
}

fn writeU16BE(a: Allocator, buf: *std.ArrayListUnmanaged(u8), v: u16) !void {
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, v, .big);
    try buf.appendSlice(a, &bytes);
}

fn crc32sum(data: []const u8) u32 {
    return std.hash.Crc32.hash(data);
}

fn deflateRaw(a: Allocator, input: []const u8) ![]u8 {
    var stream: zlib.z_stream = std.mem.zeroes(zlib.z_stream);
    if (zlib.deflateInit2_(
        &stream,
        zlib.Z_DEFAULT_COMPRESSION,
        zlib.Z_DEFLATED,
        -15,
        8,
        zlib.Z_DEFAULT_STRATEGY,
        zlib.zlibVersion(),
        @sizeOf(zlib.z_stream),
    ) != zlib.Z_OK) {
        return error.DeflateInitFailed;
    }
    defer _ = zlib.deflateEnd(&stream);

    const bound = zlib.deflateBound(&stream, @intCast(input.len));
    const out = try a.alloc(u8, bound);
    errdefer a.free(out);

    stream.next_in = @constCast(input.ptr);
    stream.avail_in = @intCast(input.len);
    stream.next_out = out.ptr;
    stream.avail_out = @intCast(out.len);

    const rc = zlib.deflate(&stream, zlib.Z_FINISH);
    if (rc != zlib.Z_STREAM_END) return error.DeflateFailed;

    const final = try a.realloc(out, stream.total_out);
    return final;
}

// raw deflate (no zlib or gzip wrapper) is what phar uses for gz-compressed entries.
// inflateInit2 with negative windowBits selects raw mode
fn inflateRaw(a: Allocator, input: []const u8, uncompressed_size: u32) ![]u8 {
    if (uncompressed_size == 0) return try a.alloc(u8, 0);

    const out = try a.alloc(u8, uncompressed_size);
    errdefer a.free(out);

    var stream: zlib.z_stream = std.mem.zeroes(zlib.z_stream);
    if (zlib.inflateInit2_(&stream, -15, zlib.zlibVersion(), @sizeOf(zlib.z_stream)) != zlib.Z_OK) {
        return ParseError.CorruptCompressedData;
    }
    defer _ = zlib.inflateEnd(&stream);

    stream.next_in = @constCast(input.ptr);
    stream.avail_in = @intCast(input.len);
    stream.next_out = out.ptr;
    stream.avail_out = @intCast(out.len);

    const rc = zlib.inflate(&stream, zlib.Z_FINISH);
    if (rc != zlib.Z_STREAM_END) return ParseError.CorruptCompressedData;
    if (stream.total_out != uncompressed_size) return ParseError.CorruptCompressedData;

    return out;
}
