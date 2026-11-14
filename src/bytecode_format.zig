const std = @import("std");
const Value = @import("runtime/value.zig").Value;
const bytecode = @import("pipeline/bytecode.zig");
const Chunk = bytecode.Chunk;
const ObjFunction = bytecode.ObjFunction;
const compiler = @import("pipeline/compiler.zig");
const CompileResult = compiler.CompileResult;
const TypeHint = compiler.TypeHint;

const Allocator = std.mem.Allocator;

const MAGIC = "ZPHPC\x00";
// v10 adds property-hook metadata and interface_decl property operands.
// v15 renumbers opcodes and adds the argument guard operands.
// Older chunks cannot be decoded by the current VM.
// v17 adds owning reference-source and array-literal reference opcodes.
// v16 instantiates capture-free class-scoped static closures.
// v18 adds defer_prop_defaults; v19 gives interface, trait and enum
// declarations their start line, end line and doc comment. v20 gives class
// constants their own opcodes.
pub const FORMAT_VERSION: u16 = 66;

// tag bytes for serialized values
const TAG_NULL: u8 = 0;
const TAG_BOOL_FALSE: u8 = 1;
const TAG_BOOL_TRUE: u8 = 2;
const TAG_INT: u8 = 3;
const TAG_FLOAT: u8 = 4;
const TAG_STRING: u8 = 5;
const TAG_EMPTY_ARRAY: u8 = 6;
const TAG_NEW_DEFAULT: u8 = 7;
const TAG_ARRAY: u8 = 8;
const TAG_DEFERRED_EXPR: u8 = 9;

const StringTable = struct {
    entries: std.ArrayListUnmanaged([]const u8) = .empty,
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
    var buf = std.ArrayListUnmanaged(u8).empty;
    var strtab = StringTable{};
    defer strtab.deinit(allocator);

    // first pass: intern all strings
    if (result.file_path.len > 0) _ = try strtab.intern(allocator, result.file_path);
    for (result.slot_names) |sn| _ = try strtab.intern(allocator, sn);
    try internChunkStrings(allocator, &strtab, &result.chunk);
    for (result.functions.items) |*func| {
        _ = try strtab.intern(allocator, func.name);
        for (func.params) |p| _ = try strtab.intern(allocator, p);
        for (func.defaults) |d| try internValueStrings(allocator, &strtab, d);
        for (func.static_vars) |sv| {
            _ = try strtab.intern(allocator, sv.name);
            try internValueStrings(allocator, &strtab, sv.initial);
        }
        for (func.slot_names) |sn| _ = try strtab.intern(allocator, sn);
        if (func.file_path.len > 0) _ = try strtab.intern(allocator, func.file_path);
        if (func.doc_comment.len > 0) _ = try strtab.intern(allocator, func.doc_comment);
        if (func.display_name.len > 0) _ = try strtab.intern(allocator, func.display_name);
        if (func.no_discard) |msg| _ = try strtab.intern(allocator, msg);
        if (func.deprecated) |msg| _ = try strtab.intern(allocator, msg);
        try internChunkStrings(allocator, &strtab, &func.chunk);
    }
    for (result.new_defaults.items) |nd| {
        _ = try strtab.intern(allocator, nd.class_name);
        for (nd.args) |a| try internValueStrings(allocator, &strtab, a);
    }
    for (result.warnings.items) |w| _ = try strtab.intern(allocator, w.message);
    for (result.type_hints.items) |th| {
        _ = try strtab.intern(allocator, th.name);
        if (th.return_type.len > 0) _ = try strtab.intern(allocator, th.return_type);
        for (th.param_types) |pt| _ = try strtab.intern(allocator, pt);
    }
    for (result.function_attrs.items) |fa| {
        _ = try strtab.intern(allocator, fa.name);
        for (fa.attrs) |attr| {
            _ = try strtab.intern(allocator, attr.name);
            for (attr.args) |arg| try internValueStrings(allocator, &strtab, arg);
            for (attr.arg_names) |arg_name| {
                if (arg_name) |name| _ = try strtab.intern(allocator, name);
            }
        }
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

    // top-level metadata
    try writeU16(&buf, allocator, result.local_count);
    try writeU16(&buf, allocator, @intCast(result.slot_names.len));
    for (result.slot_names) |sn| {
        try writeU32(&buf, allocator, try strtab.intern(allocator, sn));
    }
    if (result.file_path.len > 0) {
        try writeU32(&buf, allocator, try strtab.intern(allocator, result.file_path));
    } else {
        try writeU32(&buf, allocator, 0xFFFFFFFF);
    }
    try buf.append(allocator, if (result.strict_types) 1 else 0);
    try writeU32(&buf, allocator, compiler.closureCounter());

    // main chunk
    var lines = try LineIndex.init(allocator, result.source);
    defer lines.deinit(allocator);
    try serializeChunk(&buf, allocator, &strtab, &result.chunk, &lines);

    // functions
    try writeU32(&buf, allocator, @intCast(result.functions.items.len));
    for (result.functions.items) |*func| {
        try serializeFunction(&buf, allocator, &strtab, func, &lines);
    }

    // type hints
    try writeU32(&buf, allocator, @intCast(result.type_hints.items.len));
    for (result.type_hints.items) |th| {
        try writeU32(&buf, allocator, try strtab.intern(allocator, th.name));
        try writeU32(&buf, allocator, if (th.return_type.len > 0) try strtab.intern(allocator, th.return_type) else 0xFFFFFFFF);
        try writeU16(&buf, allocator, @intCast(th.param_types.len));
        for (th.param_types) |pt| {
            try writeU32(&buf, allocator, try strtab.intern(allocator, pt));
        }
    }

    // function and closure attributes are registered directly from CompileResult.
    try writeU32(&buf, allocator, @intCast(result.function_attrs.items.len));
    for (result.function_attrs.items) |fa| {
        try writeU32(&buf, allocator, try strtab.intern(allocator, fa.name));
        try writeU16(&buf, allocator, @intCast(fa.attrs.len));
        for (fa.attrs) |attr| {
            try writeU32(&buf, allocator, try strtab.intern(allocator, attr.name));
            try writeU16(&buf, allocator, @intCast(attr.args.len));
            for (attr.args) |arg| try serializeValue(&buf, allocator, &strtab, arg);
            try writeU16(&buf, allocator, @intCast(attr.arg_names.len));
            for (attr.arg_names) |arg_name| {
                try writeU32(&buf, allocator, if (arg_name) |name| try strtab.intern(allocator, name) else 0xFFFFFFFF);
            }
        }
    }

    try writeU32(&buf, allocator, @intCast(result.warnings.items.len));
    for (result.warnings.items) |w| {
        try writeU16(&buf, allocator, w.level);
        try writeU32(&buf, allocator, try strtab.intern(allocator, w.message));
        try writeU32(&buf, allocator, w.line);
    }

    return buf.toOwnedSlice(allocator);
}

fn internChunkStrings(allocator: Allocator, strtab: *StringTable, chunk: *const Chunk) !void {
    for (chunk.constants.items) |val| try internValueStrings(allocator, strtab, val);
}

fn internValueStrings(allocator: Allocator, strtab: *StringTable, val: Value) !void {
    switch (val) {
        .string => |s| {
            if (bytecode.deferredExprPtr(s.bytes())) |de| {
                try internValueStrings(allocator, strtab, de.lhs);
                try internValueStrings(allocator, strtab, de.rhs);
            } else if (bytecode.newDefaultPtr(s.bytes())) |nd| {
                _ = try strtab.intern(allocator, nd.class_name);
                for (nd.args) |arg| try internValueStrings(allocator, strtab, arg);
            } else {
                _ = try strtab.intern(allocator, s.bytes());
            }
        },
        .array => |arr| {
            if (val.isEmptyArrayDefault()) return;
            for (arr.entries.items) |entry| {
                if (entry.key == .string) _ = try strtab.intern(allocator, entry.key.string.bytes());
                try internValueStrings(allocator, strtab, if (entry.ref) |ref| ref.* else entry.value);
            }
        },
        else => {},
    }
}

// the line each byte offset of a source falls on, from the offsets where its
// lines start; empty for bytecode with no source, whose line entries are
// already line numbers
const LineIndex = struct {
    starts: []u32,

    fn init(allocator: Allocator, source: []const u8) !LineIndex {
        if (source.len == 0) return .{ .starts = &.{} };
        var starts: std.ArrayListUnmanaged(u32) = .empty;
        errdefer starts.deinit(allocator);
        try starts.append(allocator, 0);
        for (source, 0..) |c, i| {
            if (c == '\n') try starts.append(allocator, @intCast(i + 1));
        }
        return .{ .starts = try starts.toOwnedSlice(allocator) };
    }

    fn deinit(self: *LineIndex, allocator: Allocator) void {
        allocator.free(self.starts);
    }

    // Chunk.locationFromOffset's line: one plus the newlines before offset
    fn line(self: *const LineIndex, offset: u32) u32 {
        var lo: usize = 0;
        var hi: usize = self.starts.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.starts[mid] <= offset) lo = mid + 1 else hi = mid;
        }
        return @intCast(lo);
    }
};

fn serializeChunk(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, strtab: *StringTable, chunk: *const Chunk, lines: *const LineIndex) !void {
    // code
    try writeU32(buf, allocator, @intCast(chunk.code.items.len));
    try buf.appendSlice(allocator, chunk.code.items);

    // constants
    try writeU16(buf, allocator, @intCast(chunk.constants.items.len));
    for (chunk.constants.items) |val| {
        try serializeValue(buf, allocator, strtab, val);
    }

    // lines (convert byte offsets to line numbers)
    try writeU32(buf, allocator, @intCast(chunk.lines.items.len));
    for (chunk.lines.items) |byte_offset| {
        try writeU32(buf, allocator, if (lines.starts.len > 0) lines.line(byte_offset) else byte_offset);
    }
}

fn serializeFunction(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, strtab: *StringTable, func: *const ObjFunction, lines: *const LineIndex) !void {
    try writeU32(buf, allocator, try strtab.intern(allocator, func.name));
    try buf.append(allocator, func.arity);
    try buf.append(allocator, func.required_params);

    var flags: u8 = 0;
    if (func.is_variadic) flags |= 1;
    if (func.is_generator) flags |= 2;
    if (func.is_arrow) flags |= 4;
    if (func.is_static) flags |= 8;
    if (func.returns_ref) flags |= 16;
    if (func.locals_only) flags |= 32;
    if (func.strict_types) flags |= 64;
    if (func.has_param_types) flags |= 128;
    try buf.append(allocator, flags);
    try buf.append(allocator, func.method_visibility | (if (func.is_final) @as(u8, 4) else 0) | (if (func.is_abstract) @as(u8, 8) else 0));
    try writeU16(buf, allocator, func.cond_id);
    try buf.append(allocator, @intFromEnum(func.return_type_kind));
    try writeU32(buf, allocator, if (func.file_path.len > 0) try strtab.intern(allocator, func.file_path) else 0xFFFFFFFF);
    try writeU32(buf, allocator, func.start_line);
    try writeU32(buf, allocator, func.end_line);
    try writeU32(buf, allocator, if (func.doc_comment.len > 0) try strtab.intern(allocator, func.doc_comment) else 0xFFFFFFFF);
    try writeU32(buf, allocator, if (func.display_name.len > 0) try strtab.intern(allocator, func.display_name) else 0xFFFFFFFF);
    try writeU32(buf, allocator, if (func.no_discard) |msg| try strtab.intern(allocator, msg) else 0xFFFFFFFF);
    try writeU32(buf, allocator, if (func.deprecated) |msg| try strtab.intern(allocator, msg) else 0xFFFFFFFF);

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

    try writeU16(buf, allocator, @intCast(func.static_vars.len));
    for (func.static_vars) |sv| {
        try writeU32(buf, allocator, try strtab.intern(allocator, sv.name));
        try serializeValue(buf, allocator, strtab, sv.initial);
    }

    try writeU16(buf, allocator, func.local_count);
    try writeU16(buf, allocator, @intCast(func.slot_names.len));
    for (func.slot_names) |sn| {
        try writeU32(buf, allocator, try strtab.intern(allocator, sn));
    }

    try serializeChunk(buf, allocator, strtab, &func.chunk, lines);
}

fn serializeValue(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, strtab: *StringTable, val: Value) !void {
    switch (val) {
        .null, .undef => try buf.append(allocator, TAG_NULL),
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
            if (bytecode.deferredExprPtr(s.bytes())) |de| {
                try buf.append(allocator, TAG_DEFERRED_EXPR);
                try buf.append(allocator, @intFromEnum(de.op));
                try serializeValue(buf, allocator, strtab, de.lhs);
                try serializeValue(buf, allocator, strtab, de.rhs);
            } else if (bytecode.newDefaultPtr(s.bytes())) |nd| {
                try buf.append(allocator, TAG_NEW_DEFAULT);
                try writeU32(buf, allocator, try strtab.intern(allocator, nd.class_name));
                try buf.append(allocator, @intCast(nd.args.len));
                for (nd.args) |a| try serializeValue(buf, allocator, strtab, a);
            } else {
                try buf.append(allocator, TAG_STRING);
                try writeU32(buf, allocator, try strtab.intern(allocator, s.bytes()));
            }
        },
        .array => |arr| {
            if (val.isEmptyArrayDefault()) {
                try buf.append(allocator, TAG_EMPTY_ARRAY);
            } else {
                try buf.append(allocator, TAG_ARRAY);
                try writeU32(buf, allocator, @intCast(arr.entries.items.len));
                for (arr.entries.items) |entry| {
                    switch (entry.key) {
                        .int => |key| {
                            try buf.append(allocator, 0);
                            try writeI64(buf, allocator, key);
                        },
                        .string => |key| {
                            try buf.append(allocator, 1);
                            try writeU32(buf, allocator, try strtab.intern(allocator, key.bytes()));
                        },
                    }
                    try serializeValue(buf, allocator, strtab, if (entry.ref) |ref| ref.* else entry.value);
                }
            }
        },
        .object, .generator, .fiber, .resource => return error.UnsupportedValue,
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

fn relocate(allocator: Allocator, raw: []const u8, move: Relocation) ![]u8 {
    const under = std.mem.startsWith(u8, raw, move.from) and
        (raw.len == move.from.len or raw[move.from.len] == '/' or raw[move.from.len] == '\\');
    if (under) return std.mem.concat(allocator, u8, &.{ move.to, raw[move.from.len..] });
    // an anonymous class's name holds the file it was declared in, after a
    // NUL, and so does every string that embeds the name
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(allocator);
    var copied: usize = 0;
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, raw, at, "@anonymous\x00")) |marker| {
        const path = marker + "@anonymous\x00".len;
        at = path;
        const rest = raw[path..];
        if (!std.mem.startsWith(u8, rest, move.from) or rest.len == move.from.len) continue;
        if (rest[move.from.len] != '/' and rest[move.from.len] != '\\') continue;
        try out.appendSlice(allocator, raw[copied..path]);
        try out.appendSlice(allocator, move.to);
        copied = path + move.from.len;
        at = copied;
    }
    if (copied == 0) return allocator.dupe(u8, raw);
    try out.appendSlice(allocator, raw[copied..]);
    return out.toOwnedSlice(allocator);
}

const DeserCtx = struct {
    allocator: Allocator,
    strings: []const []const u8,
    new_defaults: *std.ArrayListUnmanaged(*bytecode.NewDefault),
    deferred_exprs: *std.ArrayListUnmanaged(*bytecode.DeferredExpr),
    string_allocs: *std.ArrayListUnmanaged([]const u8),
};

pub fn deserialize(allocator: Allocator, data: []const u8) DeserializeError!CompileResult {
    return deserializeRelocated(allocator, data, null);
}

// code compiled under one directory and run from another: every string the
// code carries that names a path under `from` (its file, __FILE__, __DIR__,
// paths built from them at compile time) is moved under `to`
pub const Relocation = struct { from: []const u8, to: []const u8 };

pub fn deserializeRelocated(allocator: Allocator, data: []const u8, relocation: ?Relocation) DeserializeError!CompileResult {
    var r = Reader{ .data = data };

    // header
    const magic = r.readSlice(6) catch return error.InvalidFormat;
    if (!std.mem.eql(u8, magic, MAGIC)) return error.InvalidFormat;
    const version = r.readU16() catch return error.InvalidFormat;
    if (version != FORMAT_VERSION) return error.InvalidFormat;

    // string table
    const str_count = r.readU32() catch return error.InvalidFormat;
    var strings = try allocator.alloc([]const u8, str_count);
    var string_allocs = std.ArrayListUnmanaged([]const u8).empty;
    errdefer {
        for (string_allocs.items) |s| allocator.free(s);
        string_allocs.deinit(allocator);
        allocator.free(strings);
    }

    for (0..str_count) |i| {
        const slen = r.readU32() catch return error.InvalidFormat;
        const raw = r.readSlice(slen) catch return error.InvalidFormat;
        const owned = if (relocation) |move| try relocate(allocator, raw, move) else try allocator.dupe(u8, raw);
        try string_allocs.append(allocator, owned);
        strings[i] = owned;
    }

    // top-level metadata
    const local_count = r.readU16() catch return error.InvalidFormat;
    const slot_name_count = r.readU16() catch return error.InvalidFormat;
    const slot_names = allocator.alloc([]const u8, slot_name_count) catch return error.OutOfMemory;
    for (0..slot_name_count) |i| {
        const sidx = r.readU32() catch return error.InvalidFormat;
        slot_names[i] = strings[sidx];
    }
    const file_path_idx = r.readU32() catch return error.InvalidFormat;
    const file_path: []const u8 = if (file_path_idx == 0xFFFFFFFF) "" else strings[file_path_idx];
    const strict_types = (r.readByte() catch return error.InvalidFormat) != 0;
    const closure_counter = r.readU32() catch return error.InvalidFormat;
    if (closure_counter > compiler.closureCounter()) compiler.setClosureCounter(closure_counter);

    var new_defaults = std.ArrayListUnmanaged(*bytecode.NewDefault).empty;
    errdefer {
        for (new_defaults.items) |nd| {
            allocator.free(nd.args);
            allocator.destroy(nd);
        }
        new_defaults.deinit(allocator);
    }
    var deferred_exprs = std.ArrayListUnmanaged(*bytecode.DeferredExpr).empty;
    errdefer {
        for (deferred_exprs.items) |de| allocator.destroy(de);
        deferred_exprs.deinit(allocator);
    }
    var ctx = DeserCtx{
        .allocator = allocator,
        .strings = strings,
        .new_defaults = &new_defaults,
        .deferred_exprs = &deferred_exprs,
        .string_allocs = &string_allocs,
    };

    // main chunk
    var chunk = deserializeChunk(&r, &ctx) catch return error.InvalidFormat;
    errdefer chunk.deinit(allocator);

    // functions
    const func_count = r.readU32() catch return error.InvalidFormat;
    var functions = std.ArrayListUnmanaged(ObjFunction).empty;
    errdefer {
        for (functions.items) |*f| {
            f.chunk.deinit(allocator);
            allocator.free(f.params);
            if (f.defaults.len > 0) allocator.free(f.defaults);
            if (f.ref_params.len > 0) allocator.free(f.ref_params);
            if (f.slot_names.len > 0) allocator.free(f.slot_names);
            if (f.static_vars.len > 0) allocator.free(f.static_vars);
        }
        functions.deinit(allocator);
    }

    for (0..func_count) |_| {
        const func = deserializeFunction(&r, &ctx) catch return error.InvalidFormat;
        try functions.append(allocator, func);
    }

    // type hints
    var type_hints = std.ArrayListUnmanaged(TypeHint).empty;
    errdefer {
        for (type_hints.items) |th| if (th.param_types.len > 0) allocator.free(th.param_types);
        type_hints.deinit(allocator);
    }
    const th_count = r.readU32() catch return error.InvalidFormat;
    for (0..th_count) |_| {
        const th_name_idx = try readStringIndex(&r, strings);
        const th_ret_idx = r.readU32() catch return error.InvalidFormat;
        if (th_ret_idx != 0xFFFFFFFF and th_ret_idx >= strings.len) return error.InvalidFormat;
        const th_param_count = r.readU16() catch return error.InvalidFormat;
        const param_types = allocator.alloc([]const u8, th_param_count) catch return error.OutOfMemory;
        errdefer allocator.free(param_types);
        for (0..th_param_count) |pi| param_types[pi] = strings[try readStringIndex(&r, strings)];
        try type_hints.append(allocator, .{
            .name = strings[th_name_idx],
            .return_type = if (th_ret_idx == 0xFFFFFFFF) "" else strings[th_ret_idx],
            .param_types = param_types,
        });
    }

    var function_attrs = std.ArrayListUnmanaged(@import("pipeline/compiler.zig").FunctionAttrEntry).empty;
    const function_attr_count = r.readU32() catch return error.InvalidFormat;
    for (0..function_attr_count) |_| {
        const fn_name = strings[try readStringIndex(&r, strings)];
        const attr_count = r.readU16() catch return error.InvalidFormat;
        const attrs = try allocator.alloc(@import("runtime/vm.zig").AttributeDef, attr_count);
        for (0..attr_count) |ai| {
            const attr_name = strings[try readStringIndex(&r, strings)];
            const arg_count = r.readU16() catch return error.InvalidFormat;
            const args = try allocator.alloc(Value, arg_count);
            for (0..arg_count) |i| args[i] = try deserializeValue(&r, &ctx);
            const arg_name_count = r.readU16() catch return error.InvalidFormat;
            const arg_names = try allocator.alloc(?[]const u8, arg_name_count);
            for (0..arg_name_count) |i| {
                const idx = r.readU32() catch return error.InvalidFormat;
                if (idx != 0xFFFFFFFF and idx >= strings.len) return error.InvalidFormat;
                arg_names[i] = if (idx == 0xFFFFFFFF) null else strings[idx];
            }
            attrs[ai] = .{ .name = attr_name, .args = args, .arg_names = arg_names };
        }
        try function_attrs.append(allocator, .{ .name = fn_name, .attrs = attrs });
    }

    var warnings = std.ArrayListUnmanaged(@import("pipeline/compiler.zig").CompileWarning).empty;
    errdefer warnings.deinit(allocator);
    const warning_count = r.readU32() catch return error.InvalidFormat;
    for (0..warning_count) |_| {
        const level = r.readU16() catch return error.InvalidFormat;
        const message = strings[try readStringIndex(&r, strings)];
        const line = r.readU32() catch return error.InvalidFormat;
        try warnings.append(allocator, .{ .level = level, .message = message, .line = line });
    }
    if (r.pos != data.len) return error.InvalidFormat;

    allocator.free(strings);

    return .{
        .chunk = chunk,
        .functions = functions,
        .string_allocs = string_allocs,
        .allocator = allocator,
        .local_count = local_count,
        .slot_names = slot_names,
        .file_path = file_path,
        .strict_types = strict_types,
        .type_hints = type_hints,
        .function_attrs = function_attrs,
        .new_defaults = new_defaults,
        .deferred_exprs = deferred_exprs,
        .warnings = warnings,
    };
}

fn deserializeChunk(r: *Reader, ctx: *DeserCtx) !Chunk {
    var chunk = Chunk{};
    errdefer chunk.deinit(ctx.allocator);

    const code_len = try r.readU32();
    const code_data = try r.readSlice(code_len);
    try chunk.code.appendSlice(ctx.allocator, code_data);

    const const_count = try r.readU16();
    for (0..const_count) |_| {
        try chunk.constants.append(ctx.allocator, try deserializeValue(r, ctx));
    }

    const line_count = try r.readU32();
    for (0..line_count) |_| {
        try chunk.lines.append(ctx.allocator, try r.readU32());
    }

    return chunk;
}

fn readStringIndex(r: *Reader, strings: []const []const u8) !u32 {
    const idx = try r.readU32();
    if (idx >= strings.len) return error.InvalidFormat;
    return idx;
}

fn deserializeFunction(r: *Reader, ctx: *DeserCtx) !ObjFunction {
    const allocator = ctx.allocator;
    const strings = ctx.strings;
    const name_idx = try r.readU32();
    const arity = try r.readByte();
    const required = try r.readByte();
    const flags = try r.readByte();
    const method_flags = try r.readByte();
    const cond_id = try r.readU16();
    const return_type_kind = std.enums.fromInt(bytecode.ReturnTypeKind, try r.readByte()) orelse return error.InvalidFormat;
    const file_path_idx = try r.readU32();
    const start_line = try r.readU32();
    const end_line = try r.readU32();
    const doc_comment_idx = try r.readU32();
    const display_name_idx = try r.readU32();
    const no_discard_idx = try r.readU32();
    const deprecated_idx = try r.readU32();

    const param_count = try r.readByte();
    const params = try allocator.alloc([]const u8, param_count);
    for (0..param_count) |i| {
        const pidx = try r.readU32();
        params[i] = strings[pidx];
    }

    const default_count = try r.readByte();
    const defaults = try allocator.alloc(Value, default_count);
    for (0..default_count) |i| {
        defaults[i] = try deserializeValue(r, ctx);
    }

    const ref_count = try r.readByte();
    const ref_params = try allocator.alloc(bool, ref_count);
    for (0..ref_count) |i| {
        ref_params[i] = (try r.readByte()) != 0;
    }

    const static_count = try r.readU16();
    const static_vars = try allocator.alloc(bytecode.StaticVar, static_count);
    for (0..static_count) |i| {
        const sidx = try r.readU32();
        static_vars[i] = .{ .name = strings[sidx], .initial = try deserializeValue(r, ctx) };
    }

    const local_count = try r.readU16();
    const slot_name_count = try r.readU16();
    const slot_names = try allocator.alloc([]const u8, slot_name_count);
    for (0..slot_name_count) |i| {
        const sidx = try r.readU32();
        slot_names[i] = strings[sidx];
    }

    const chunk = try deserializeChunk(r, ctx);

    return .{
        .name = strings[name_idx],
        .arity = arity,
        .required_params = required,
        .is_variadic = (flags & 1) != 0,
        .is_generator = (flags & 2) != 0,
        .is_arrow = (flags & 4) != 0,
        .is_static = (flags & 8) != 0,
        .returns_ref = (flags & 16) != 0,
        .locals_only = (flags & 32) != 0,
        .strict_types = (flags & 64) != 0,
        .has_param_types = (flags & 128) != 0,
        .method_visibility = method_flags & 3,
        .is_final = (method_flags & 4) != 0,
        .is_abstract = (method_flags & 8) != 0,
        .return_type_kind = return_type_kind,
        .file_path = if (file_path_idx == 0xFFFFFFFF) "" else strings[file_path_idx],
        .start_line = start_line,
        .end_line = end_line,
        .doc_comment = if (doc_comment_idx == 0xFFFFFFFF) "" else strings[doc_comment_idx],
        .display_name = if (display_name_idx == 0xFFFFFFFF) "" else strings[display_name_idx],
        .no_discard = if (no_discard_idx == 0xFFFFFFFF) null else strings[no_discard_idx],
        .deprecated = if (deprecated_idx == 0xFFFFFFFF) null else strings[deprecated_idx],
        .cond_id = cond_id,
        .params = params,
        .defaults = defaults,
        .ref_params = ref_params,
        .chunk = chunk,
        .local_count = local_count,
        .slot_names = slot_names,
        .static_vars = static_vars,
    };
}

fn deserializeValue(r: *Reader, ctx: *DeserCtx) !Value {
    const tag = try r.readByte();
    return switch (tag) {
        TAG_NULL => .null,
        TAG_BOOL_FALSE => .{ .bool = false },
        TAG_BOOL_TRUE => .{ .bool = true },
        TAG_INT => .{ .int = try r.readI64() },
        TAG_FLOAT => .{ .float = try r.readF64() },
        TAG_STRING => .{ .string = Value.String.borrowed(ctx.strings[try readStringIndex(r, ctx.strings)]) },
        TAG_EMPTY_ARRAY => Value.empty_array_default,
        TAG_ARRAY => blk: {
            const arr = try ctx.allocator.create(@import("runtime/value.zig").PhpArray);
            errdefer ctx.allocator.destroy(arr);
            arr.* = .{};
            errdefer arr.deinit(ctx.allocator);
            const count = try r.readU32();
            for (0..count) |_| {
                const key_tag = try r.readByte();
                const key: @import("runtime/value.zig").PhpArray.Key = switch (key_tag) {
                    0 => .{ .int = try r.readI64() },
                    1 => .{ .string = Value.String.borrowed(ctx.strings[try readStringIndex(r, ctx.strings)]) },
                    else => return error.InvalidFormat,
                };
                try arr.set(ctx.allocator, key, try deserializeValue(r, ctx));
            }
            break :blk .{ .array = arr };
        },
        TAG_NEW_DEFAULT => blk: {
            const class_idx = try readStringIndex(r, ctx.strings);
            const arg_count = try r.readByte();
            const args = try ctx.allocator.alloc(Value, arg_count);
            errdefer ctx.allocator.free(args);
            for (0..arg_count) |i| args[i] = try deserializeValue(r, ctx);
            const nd = try ctx.allocator.create(bytecode.NewDefault);
            errdefer ctx.allocator.destroy(nd);
            nd.* = .{ .class_name = ctx.strings[class_idx], .args = args };
            try ctx.new_defaults.append(ctx.allocator, nd);
            const sentinel = bytecode.encodeNewDefaultSentinel(ctx.allocator, nd) catch return error.OutOfMemory;
            try ctx.string_allocs.append(ctx.allocator, sentinel);
            break :blk .{ .string = Value.String.borrowed(sentinel) };
        },
        TAG_DEFERRED_EXPR => blk: {
            const op = std.enums.fromInt(bytecode.DeferredExpr.Op, try r.readByte()) orelse return error.InvalidFormat;
            const lhs = try deserializeValue(r, ctx);
            const rhs = try deserializeValue(r, ctx);
            const de = try ctx.allocator.create(bytecode.DeferredExpr);
            errdefer ctx.allocator.destroy(de);
            de.* = .{ .op = op, .lhs = lhs, .rhs = rhs };
            try ctx.deferred_exprs.append(ctx.allocator, de);
            const sentinel = bytecode.encodeDeferredExprSentinel(ctx.allocator, de) catch return error.OutOfMemory;
            try ctx.string_allocs.append(ctx.allocator, sentinel);
            break :blk .{ .string = Value.String.borrowed(sentinel) };
        },
        else => return error.InvalidFormat,
    };
}

test "property hook interface bytecode rejects pre-hook format" {
    const allocator = std.testing.allocator;
    var ast = try @import("pipeline/parser.zig").parse(
        allocator,
        "<?php interface CachedContract { public int $value { get; } }",
    );
    defer ast.deinit();
    var compiled = try compiler.compile(&ast, allocator);
    defer compiled.deinit();
    const data = try serialize(allocator, &compiled);
    defer allocator.free(data);

    var decoded = try deserialize(allocator, data);
    defer decoded.deinit();
    try std.testing.expectEqualSlices(u8, compiled.chunk.code.items, decoded.chunk.code.items);

    // A v9 cache can have the same source identity but lacks the new operands.
    // Reject it at the header, rather than passing incompatible code to the VM.
    data[MAGIC.len] = 9;
    data[MAGIC.len + 1] = 0;
    try std.testing.expectError(error.InvalidFormat, deserialize(allocator, data));
}
