const std = @import("std");

const Allocator = std.mem.Allocator;

pub const ParseError = error{
    NotAPhar,
    BadManifest,
    UnsupportedCompression,
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

const HALT_TOKEN = "__HALT_COMPILER();";

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
    if (compression != 0) return ParseError.UnsupportedCompression;
    return try a.dupe(u8, blob);
}
