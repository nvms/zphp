const std = @import("std");
const Value = @import("runtime/value.zig").Value;
const Chunk = @import("pipeline/bytecode.zig").Chunk;
const ObjFunction = @import("pipeline/bytecode.zig").ObjFunction;
const CompileResult = @import("pipeline/compiler.zig").CompileResult;

const Allocator = std.mem.Allocator;

const MAGIC = "ZPHPC\x00";
const FORMAT_VERSION: u16 = 1;

// tag bytes for serialized values
const TAG_NULL: u8 = 0;
const TAG_BOOL_FALSE: u8 = 1;
const TAG_BOOL_TRUE: u8 = 2;
const TAG_INT: u8 = 3;
const TAG_FLOAT: u8 = 4;
const TAG_STRING: u8 = 5;

const StringTable = struct {
    entries: std.ArrayListUnmanaged([]const u8) = .{},
    map: std.StringHashMapUnmanaged(u32) = .{},

    fn intern(self: *StringTable, allocator: Allocator, s: []const u8) !u32 {
        if (self.map.get(s)) |idx| return idx;
        const idx: u32 = @intCast(self.entries.items.len);
        try self.entries.append(allocator, s);
        try self.map.put(allocator, s, idx);
        return idx;
    }

    fn deinit(self: *StringTable, allocator: Allocator) void {
        self.entries.deinit(allocator);
        self.map.deinit(allocator);
    }
};

// =========================================================
// serialization
// =========================================================

pub fn serialize(allocator: Allocator, result: *const CompileResult) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    var strtab = StringTable{};
    defer strtab.deinit(allocator);

    // first pass: intern all strings
    try internChunkStrings(allocator, &strtab, &result.chunk);
    for (result.functions.items) |*func| {
        _ = try strtab.intern(allocator, func.name);
        for (func.params) |p| _ = try strtab.intern(allocator, p);
        for (func.slot_names) |sn| _ = try strtab.intern(allocator, sn);
        try internChunkStrings(allocator, &strtab, &func.chunk);
    }

    // header
    try buf.appendSlice(allocator, MAGIC);
    try writeU16(&buf, allocator, FORMAT_VERSION);

    // string table
    try writeU32(&buf, allocator, @intCast(strtab.entries.items.len));
    for (strtab.entries.items) |s| {
        try writeU32(&buf, allocator, @intCast(s.len));
        try buf.appendSlice(allocator, s);
    }

    // main chunk
    try serializeChunk(&buf, allocator, &strtab, &result.chunk);

    // functions
    try writeU32(&buf, allocator, @intCast(result.functions.items.len));
    for (result.functions.items) |*func| {
        try serializeFunction(&buf, allocator, &strtab, func);
    }

    return buf.toOwnedSlice(allocator);
}

fn internChunkStrings(allocator: Allocator, strtab: *StringTable, chunk: *const Chunk) !void {
    for (chunk.constants.items) |val| {
        if (val == .string) _ = try strtab.intern(allocator, val.string);
    }
}

fn serializeChunk(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, strtab: *StringTable, chunk: *const Chunk) !void {
    // code
    try writeU32(buf, allocator, @intCast(chunk.code.items.len));
    try buf.appendSlice(allocator, chunk.code.items);

    // constants
    try writeU16(buf, allocator, @intCast(chunk.constants.items.len));
    for (chunk.constants.items) |val| {
        try serializeValue(buf, allocator, strtab, val);
    }

    // lines
    try writeU32(buf, allocator, @intCast(chunk.lines.items.len));
    for (chunk.lines.items) |line| {
        try writeU32(buf, allocator, line);
    }
}

fn serializeFunction(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, strtab: *StringTable, func: *const ObjFunction) !void {
    try writeU32(buf, allocator, try strtab.intern(allocator, func.name));
    try buf.append(allocator, func.arity);
    try buf.append(allocator, func.required_params);

    var flags: u8 = 0;
    if (func.is_variadic) flags |= 1;
    if (func.is_generator) flags |= 2;
    if (func.is_arrow) flags |= 4;
    try buf.append(allocator, flags);

    try buf.append(allocator, @intCast(func.params.len));
    for (func.params) |p| {
        try writeU32(buf, allocator, try strtab.intern(allocator, p));
    }

    try buf.append(allocator, @intCast(func.defaults.len));
    for (func.defaults) |d| {
        try serializeValue(buf, allocator, strtab, d);
    }

    try buf.append(allocator, @intCast(func.ref_params.len));
    for (func.ref_params) |r| {
        try buf.append(allocator, if (r) @as(u8, 1) else @as(u8, 0));
    }

    try writeU16(buf, allocator, func.local_count);
    try writeU16(buf, allocator, @intCast(func.slot_names.len));
    for (func.slot_names) |sn| {
        try writeU32(buf, allocator, try strtab.intern(allocator, sn));
    }

    try serializeChunk(buf, allocator, strtab, &func.chunk);
}

fn serializeValue(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, strtab: *StringTable, val: Value) !void {
    switch (val) {
        .null => try buf.append(allocator, TAG_NULL),
        .bool => |b| try buf.append(allocator, if (b) TAG_BOOL_TRUE else TAG_BOOL_FALSE),
        .int => |i| {
            try buf.append(allocator, TAG_INT);
            try writeI64(buf, allocator, i);
        },
        .float => |f| {
            try buf.append(allocator, TAG_FLOAT);
            try writeF64(buf, allocator, f);
        },
        .string => |s| {
            try buf.append(allocator, TAG_STRING);
            try writeU32(buf, allocator, try strtab.intern(allocator, s));
        },
        else => try buf.append(allocator, TAG_NULL),
    }
}

fn writeU16(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, val: u16) !void {
    const bytes: [2]u8 = @bitCast(val);
    try buf.appendSlice(allocator, &bytes);
}

fn writeU32(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, val: u32) !void {
    const bytes: [4]u8 = @bitCast(val);
    try buf.appendSlice(allocator, &bytes);
}

fn writeI64(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, val: i64) !void {
    const bytes: [8]u8 = @bitCast(val);
    try buf.appendSlice(allocator, &bytes);
}

fn writeF64(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, val: f64) !void {
    const bytes: [8]u8 = @bitCast(val);
    try buf.appendSlice(allocator, &bytes);
}

// =========================================================
// deserialization
// =========================================================

const Reader = struct {
    data: []const u8,
    pos: usize = 0,

    fn readByte(self: *Reader) !u8 {
        if (self.pos >= self.data.len) return error.UnexpectedEof;
        const b = self.data[self.pos];
        self.pos += 1;
        return b;
    }

    fn readU16(self: *Reader) !u16 {
        if (self.pos + 2 > self.data.len) return error.UnexpectedEof;
        const val: u16 = @bitCast(self.data[self.pos..][0..2].*);
        self.pos += 2;
        return val;
    }

    fn readU32(self: *Reader) !u32 {
        if (self.pos + 4 > self.data.len) return error.UnexpectedEof;
        const val: u32 = @bitCast(self.data[self.pos..][0..4].*);
        self.pos += 4;
        return val;
    }

    fn readI64(self: *Reader) !i64 {
        if (self.pos + 8 > self.data.len) return error.UnexpectedEof;
        const val: i64 = @bitCast(self.data[self.pos..][0..8].*);
        self.pos += 8;
        return val;
    }

    fn readF64(self: *Reader) !f64 {
        if (self.pos + 8 > self.data.len) return error.UnexpectedEof;
        const val: f64 = @bitCast(self.data[self.pos..][0..8].*);
        self.pos += 8;
        return val;
    }

    fn readSlice(self: *Reader, len: usize) ![]const u8 {
        if (self.pos + len > self.data.len) return error.UnexpectedEof;
        const s = self.data[self.pos .. self.pos + len];
        self.pos += len;
        return s;
    }
};

const DeserializeError = error{ InvalidFormat, UnexpectedEof, OutOfMemory };

pub fn deserialize(allocator: Allocator, data: []const u8) DeserializeError!CompileResult {
    var r = Reader{ .data = data };

    // header
    const magic = r.readSlice(6) catch return error.InvalidFormat;
    if (!std.mem.eql(u8, magic, MAGIC)) return error.InvalidFormat;
    const version = r.readU16() catch return error.InvalidFormat;
    if (version != FORMAT_VERSION) return error.InvalidFormat;

    // string table
    const str_count = r.readU32() catch return error.InvalidFormat;
    var strings = try allocator.alloc([]const u8, str_count);
    var string_allocs = std.ArrayListUnmanaged([]const u8){};
    errdefer {
        for (string_allocs.items) |s| allocator.free(s);
        string_allocs.deinit(allocator);
        allocator.free(strings);
    }

    for (0..str_count) |i| {
        const slen = r.readU32() catch return error.InvalidFormat;
        const raw = r.readSlice(slen) catch return error.InvalidFormat;
        const owned = try allocator.dupe(u8, raw);
        try string_allocs.append(allocator, owned);
        strings[i] = owned;
    }

    // main chunk
    var chunk = deserializeChunk(&r, allocator, strings) catch return error.InvalidFormat;
    errdefer chunk.deinit(allocator);

    // functions
    const func_count = r.readU32() catch return error.InvalidFormat;
    var functions = std.ArrayListUnmanaged(ObjFunction){};
    errdefer {
        for (functions.items) |*f| {
            f.chunk.deinit(allocator);
            allocator.free(f.params);
            if (f.defaults.len > 0) allocator.free(f.defaults);
            if (f.ref_params.len > 0) allocator.free(f.ref_params);
            if (f.slot_names.len > 0) allocator.free(f.slot_names);
        }
        functions.deinit(allocator);
    }

    for (0..func_count) |_| {
        const func = deserializeFunction(&r, allocator, strings) catch return error.InvalidFormat;
        try functions.append(allocator, func);
    }

    allocator.free(strings);

    return .{
        .chunk = chunk,
        .functions = functions,
        .string_allocs = string_allocs,
        .allocator = allocator,
    };
}

fn deserializeChunk(r: *Reader, allocator: Allocator, strings: []const []const u8) !Chunk {
    var chunk = Chunk{};
    errdefer chunk.deinit(allocator);

    const code_len = try r.readU32();
    const code_data = try r.readSlice(code_len);
    try chunk.code.appendSlice(allocator, code_data);

    const const_count = try r.readU16();
    for (0..const_count) |_| {
        try chunk.constants.append(allocator, try deserializeValue(r, strings));
    }

    const line_count = try r.readU32();
    for (0..line_count) |_| {
        try chunk.lines.append(allocator, try r.readU32());
    }

    return chunk;
}

fn deserializeFunction(r: *Reader, allocator: Allocator, strings: []const []const u8) !ObjFunction {
    const name_idx = try r.readU32();
    const arity = try r.readByte();
    const required = try r.readByte();
    const flags = try r.readByte();

    const param_count = try r.readByte();
    const params = try allocator.alloc([]const u8, param_count);
    for (0..param_count) |i| {
        const pidx = try r.readU32();
        params[i] = strings[pidx];
    }

    const default_count = try r.readByte();
    const defaults = try allocator.alloc(Value, default_count);
    for (0..default_count) |i| {
        defaults[i] = try deserializeValue(r, strings);
    }

    const ref_count = try r.readByte();
    const ref_params = try allocator.alloc(bool, ref_count);
    for (0..ref_count) |i| {
        ref_params[i] = (try r.readByte()) != 0;
    }

    const local_count = try r.readU16();
    const slot_name_count = try r.readU16();
    const slot_names = try allocator.alloc([]const u8, slot_name_count);
    for (0..slot_name_count) |i| {
        const sidx = try r.readU32();
        slot_names[i] = strings[sidx];
    }

    const chunk = try deserializeChunk(r, allocator, strings);

    return .{
        .name = strings[name_idx],
        .arity = arity,
        .required_params = required,
        .is_variadic = (flags & 1) != 0,
        .is_generator = (flags & 2) != 0,
        .is_arrow = (flags & 4) != 0,
        .params = params,
        .defaults = defaults,
        .ref_params = ref_params,
        .chunk = chunk,
        .local_count = local_count,
        .slot_names = slot_names,
    };
}

fn deserializeValue(r: *Reader, strings: []const []const u8) !Value {
    const tag = try r.readByte();
    return switch (tag) {
        TAG_NULL => .null,
        TAG_BOOL_FALSE => .{ .bool = false },
        TAG_BOOL_TRUE => .{ .bool = true },
        TAG_INT => .{ .int = try r.readI64() },
        TAG_FLOAT => .{ .float = try r.readF64() },
        TAG_STRING => .{ .string = strings[try r.readU32()] },
        else => .null,
    };
}

// =========================================================
// standalone executable support
// =========================================================

const TRAILER_MAGIC = "ZPHPEXE\x00";
const TRAILER_SIZE = 16; // 8 bytes magic + 4 bytes offset + 4 bytes length

pub fn appendToExecutable(allocator: Allocator, exe_path: []const u8, bytecode: []const u8, out_path: []const u8) !void {
    const exe_data = try std.fs.cwd().readFileAlloc(allocator, exe_path, 256 * 1024 * 1024);
    defer allocator.free(exe_data);

    const file = try std.fs.cwd().createFile(out_path, .{});
    defer file.close();

    try file.writeAll(exe_data);
    const bc_offset: u32 = @intCast(exe_data.len);
    const bc_length: u32 = @intCast(bytecode.len);
    try file.writeAll(bytecode);

    // trailer: magic + offset + length
    try file.writeAll(TRAILER_MAGIC);
    const off_bytes: [4]u8 = @bitCast(bc_offset);
    try file.writeAll(&off_bytes);
    const len_bytes: [4]u8 = @bitCast(bc_length);
    try file.writeAll(&len_bytes);

    // make executable
    const out_z = try allocator.dupeZ(u8, out_path);
    defer allocator.free(out_z);
    _ = std.c.chmod(out_z.ptr, 0o755);
}

pub fn detectEmbeddedBytecode(allocator: Allocator) ?[]const u8 {
    const exe_path = std.fs.selfExePathAlloc(allocator) catch return null;
    defer allocator.free(exe_path);

    const file = std.fs.cwd().openFile(exe_path, .{}) catch return null;
    defer file.close();

    const file_size = file.getEndPos() catch return null;
    if (file_size < TRAILER_SIZE) return null;

    // read trailer from end of file
    file.seekTo(file_size - TRAILER_SIZE) catch return null;
    var trailer: [TRAILER_SIZE]u8 = undefined;
    const n = file.readAll(&trailer) catch return null;
    if (n != TRAILER_SIZE) return null;

    if (!std.mem.eql(u8, trailer[0..8], TRAILER_MAGIC)) return null;

    const bc_offset: u32 = @bitCast(trailer[8..12].*);
    const bc_length: u32 = @bitCast(trailer[12..16].*);

    if (@as(u64, bc_offset) + bc_length + TRAILER_SIZE > file_size) return null;

    file.seekTo(bc_offset) catch return null;
    const bc = allocator.alloc(u8, bc_length) catch return null;
    const read = file.readAll(bc) catch {
        allocator.free(bc);
        return null;
    };
    if (read != bc_length) {
        allocator.free(bc);
        return null;
    }
    return bc;
}
