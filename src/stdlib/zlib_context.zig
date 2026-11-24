// ext/zlib's incremental api: deflate_init/deflate_add and
// inflate_init/inflate_add over DeflateContext and InflateContext objects,
// ported from php's zlib.c
const std = @import("std");
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const PhpObject = value_mod.PhpObject;
const PhpArray = value_mod.PhpArray;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const Args = @import("string_ports.zig").Args;
const zlib = @import("c_zlib");

const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "deflate_init", native_deflate_init },
    .{ "deflate_add", native_deflate_add },
    .{ "inflate_init", native_inflate_init },
    .{ "inflate_add", native_inflate_add },
    .{ "inflate_get_status", native_inflate_get_status },
    .{ "inflate_get_read_len", native_inflate_get_read_len },
};

const deflate_class = "DeflateContext";
const inflate_class = "InflateContext";

const encoding_raw: i64 = -0x0f;
const encoding_gzip: i64 = 0x1f;
const encoding_deflate: i64 = 0x0f;

// php_zlib_context
const State = struct {
    z: zlib.z_stream,
    deflating: bool,
    status: c_int = zlib.Z_OK,
    // an inflate dictionary waiting for Z_NEED_DICT
    dict: ?[]u8 = null,
};

fn stateOf(obj: *PhpObject) ?*State {
    return obj.native.get(State, .zlib_context);
}

fn destroyState(s: *State) void {
    if (s.deflating) _ = zlib.deflateEnd(&s.z) else _ = zlib.inflateEnd(&s.z);
    if (s.dict) |d| std.heap.c_allocator.free(d);
    std.heap.c_allocator.destroy(s);
}

fn cleanupContext(obj: *PhpObject) bool {
    if (stateOf(obj)) |s| destroyState(s);
    obj.native = .{};
    return true;
}

pub fn cleanupResources(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    for (objects.items) |obj| {
        if (obj.pooled or obj.native.kind != .zlib_context) continue;
        _ = cleanupContext(obj);
    }
}

fn throwFmt(ctx: *NativeContext, class: []const u8, comptime fmt: []const u8, args: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException(class, msg);
    return error.RuntimeError;
}

fn warn(ctx: *NativeContext, func: []const u8, comptime fmt: []const u8, args: anytype) RuntimeError!void {
    const text = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(text);
    const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): {s}", .{ func, text });
    defer ctx.allocator.free(msg);
    try ctx.vm.emitWarning(msg);
}

// Z_PARAM_ARRAY_HT_OR_OBJECT_HT: an option by name, or null
fn option(options: Value, name: []const u8) ?Value {
    switch (options) {
        .array => |arr| {
            const entry = arr.getPtr(.{ .string = Value.String.borrowed(name) }) orelse return null;
            return if (entry.ref) |cell| cell.* else entry.value;
        },
        .object => |obj| {
            const v = obj.get(name);
            if (v == .undef) return null;
            if (v == .null and !obj.properties.contains(name) and obj.getSlotIndex(name) == null) return null;
            return v;
        },
        else => return null,
    }
}

fn optionLong(options: Value, name: []const u8, default: i64) i64 {
    const v = option(options, name) orelse return default;
    return v.toInt();
}

fn optionsArg(p: Args, index: usize) RuntimeError!Value {
    if (index >= p.args.len) return .null;
    const v = p.args[index];
    if (v == .array or v == .object) return v;
    return p.typeError(index, "options", "array");
}

// zlib_create_dictionary_string: a string, or an array of non-empty strings
// without NUL bytes joined each followed by a NUL
fn dictionaryOption(ctx: *NativeContext, func: []const u8, options: Value) RuntimeError!?[]u8 {
    const v = option(options, "dictionary") orelse return null;
    switch (v) {
        .string => |s| return try std.heap.c_allocator.dupe(u8, s.bytes()),
        .array => |arr| {
            if (arr.entries.items.len == 0) return null;
            var out: std.ArrayListUnmanaged(u8) = .empty;
            errdefer out.deinit(std.heap.c_allocator);
            for (arr.entries.items) |entry| {
                const item = if (entry.ref) |cell| cell.* else entry.value;
                const text = try ctx.vm.valueToString(item);
                if (ctx.vm.pending_exception != null) return error.RuntimeError;
                if (text.len == 0) return throwFmt(ctx, "ValueError", "{s}(): Argument #2 ($options) must not contain empty strings", .{func});
                if (std.mem.indexOfScalar(u8, text, 0) != null) return throwFmt(ctx, "ValueError", "{s}(): Argument #2 ($options) must not contain strings with null bytes", .{func});
                try out.appendSlice(std.heap.c_allocator, text);
                try out.append(std.heap.c_allocator, 0);
            }
            return try out.toOwnedSlice(std.heap.c_allocator);
        },
        else => return throwFmt(ctx, "TypeError", "{s}(): Argument #2 ($options) must be of type zero-terminated string or array, {s} given", .{ func, @import("types.zig").phpTypeName(v) }),
    }
}

fn newContext(ctx: *NativeContext, class: []const u8, deflating: bool) RuntimeError!struct { obj: *PhpObject, state: *State } {
    const obj = try ctx.vm.allocObject(.{ .class_name = class });
    const s = try std.heap.c_allocator.create(State);
    s.* = .{ .z = std.mem.zeroes(zlib.z_stream), .deflating = deflating };
    obj.native = .{ .kind = .zlib_context, .ptr = @intFromPtr(s) };
    return .{ .obj = obj, .state = s };
}

// the window bits zlib takes for an encoding: negative raw, 15 deflate, 31 gzip
fn windowBits(encoding: i64, window: i64) c_int {
    return @intCast(if (encoding < 0) encoding + (15 - window) else encoding - (15 - window));
}

fn validEncoding(encoding: i64) bool {
    return encoding == encoding_raw or encoding == encoding_gzip or encoding == encoding_deflate;
}

fn native_deflate_init(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const func = "deflate_init";
    const p = Args.init(ctx, func, args);
    const encoding = try p.long(0, "encoding");
    const options = try optionsArg(p, 1);
    const level = optionLong(options, "level", -1);
    if (level < -1 or level > 9) return throwFmt(ctx, "ValueError", "deflate_init(): \"level\" option must be between -1 and 9", .{});
    const memory = optionLong(options, "memory", 8);
    if (memory < 1 or memory > 9) return throwFmt(ctx, "ValueError", "deflate_init(): \"memory\" option must be between 1 and 9", .{});
    const window = optionLong(options, "window", 15);
    if (window < 8 or window > 15) return throwFmt(ctx, "ValueError", "deflate_init(): \"window\" option must be between 8 and 15", .{});
    const strategy = optionLong(options, "strategy", zlib.Z_DEFAULT_STRATEGY);
    switch (strategy) {
        zlib.Z_FILTERED, zlib.Z_HUFFMAN_ONLY, zlib.Z_RLE, zlib.Z_FIXED, zlib.Z_DEFAULT_STRATEGY => {},
        else => return throwFmt(ctx, "ValueError", "deflate_init(): \"strategy\" option must be one of ZLIB_FILTERED, ZLIB_HUFFMAN_ONLY, ZLIB_RLE, ZLIB_FIXED, or ZLIB_DEFAULT_STRATEGY", .{}),
    }
    if (!validEncoding(encoding)) return p.valueError(0, "encoding", "must be one of ZLIB_ENCODING_RAW, ZLIB_ENCODING_GZIP, or ZLIB_ENCODING_DEFLATE");
    const dict = try dictionaryOption(ctx, func, options);
    defer if (dict) |d| std.heap.c_allocator.free(d);

    const made = try newContext(ctx, deflate_class, true);
    if (zlib.deflateInit2_(&made.state.z, @intCast(level), zlib.Z_DEFLATED, windowBits(encoding, window), @intCast(memory), @intCast(strategy), zlib.zlibVersion(), @sizeOf(zlib.z_stream)) != zlib.Z_OK) {
        std.heap.c_allocator.destroy(made.state);
        made.obj.native = .{};
        ctx.vm.releaseValue(.{ .object = made.obj });
        try warn(ctx, func, "Failed allocating zlib.deflate context", .{});
        return NativeResult.scalar(.{ .bool = false });
    }
    if (dict) |d| _ = zlib.deflateSetDictionary(&made.state.z, d.ptr, @intCast(d.len));
    return NativeResult.transfer(.{ .object = made.obj });
}

fn flushMode(p: Args, index: usize) RuntimeError!c_int {
    const mode = try p.optLong(index, "flush_mode", zlib.Z_SYNC_FLUSH);
    switch (mode) {
        zlib.Z_NO_FLUSH, zlib.Z_PARTIAL_FLUSH, zlib.Z_SYNC_FLUSH, zlib.Z_FULL_FLUSH, zlib.Z_BLOCK, zlib.Z_FINISH => return @intCast(mode),
        else => return p.valueError(index, "flush_mode", "must be one of ZLIB_NO_FLUSH, ZLIB_PARTIAL_FLUSH, ZLIB_SYNC_FLUSH, ZLIB_FULL_FLUSH, ZLIB_BLOCK, or ZLIB_FINISH"),
    }
}

fn native_deflate_add(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "deflate_add", args);
    const obj = try p.object(0, "context", deflate_class);
    const data = try p.str(1, "data");
    const flush = try flushMode(p, 2);
    const s = stateOf(obj) orelse return NativeResult.scalar(.{ .bool = false });
    if (data.len == 0 and flush != zlib.Z_FINISH) return NativeResult.copyString(ctx.allocator, "");

    // PHP_ZLIB_BUFFER_SIZE_GUESS, at least 64 bytes
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(ctx.allocator);
    const guess = @max(@as(usize, @intFromFloat(@ceil(@as(f64, @floatFromInt(data.len)) * 1.015))) + 10 + 8 + 4 + 1, 64);
    try out.resize(ctx.allocator, guess);
    s.z.next_in = @constCast(data.ptr);
    s.z.avail_in = @intCast(data.len);
    s.z.next_out = out.items.ptr;
    s.z.avail_out = @intCast(out.items.len);
    var used: usize = 0;
    var status: c_int = undefined;
    while (true) {
        if (s.z.avail_out == 0) {
            // more output space; php grows by 64 bytes at a time
            try out.resize(ctx.allocator, out.items.len + 64);
            s.z.avail_out = 64;
            s.z.next_out = out.items.ptr + used;
        }
        status = zlib.deflate(&s.z, flush);
        used = out.items.len - s.z.avail_out;
        if (!(status == zlib.Z_OK and s.z.avail_out == 0)) break;
    }
    switch (status) {
        zlib.Z_OK, zlib.Z_STREAM_END => {
            if (status == zlib.Z_STREAM_END) _ = zlib.deflateReset(&s.z);
            out.shrinkRetainingCapacity(used);
            return NativeResult.takeString(try Value.String.adopt(ctx.allocator, try out.toOwnedSlice(ctx.allocator)));
        },
        else => {
            out.deinit(ctx.allocator);
            try warn(ctx, "deflate_add", "zlib error ({s})", .{std.mem.span(zlib.zError(status))});
            return NativeResult.scalar(.{ .bool = false });
        },
    }
}

fn native_inflate_init(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const func = "inflate_init";
    const p = Args.init(ctx, func, args);
    const encoding = try p.long(0, "encoding");
    const options = try optionsArg(p, 1);
    const window = optionLong(options, "window", 15);
    if (window < 8 or window > 15) return throwFmt(ctx, "ValueError", "zlib window size (logarithm) ({d}) must be within 8..15", .{window});
    if (!validEncoding(encoding)) return throwFmt(ctx, "ValueError", "inflate_init(): Argument #1 ($encoding) must be one of ZLIB_ENCODING_RAW, ZLIB_ENCODING_GZIP, or ZLIB_ENCODING_DEFLATE", .{});
    const dict = try dictionaryOption(ctx, func, options);

    const made = try newContext(ctx, inflate_class, false);
    made.state.dict = dict;
    if (zlib.inflateInit2_(&made.state.z, windowBits(encoding, window), zlib.zlibVersion(), @sizeOf(zlib.z_stream)) != zlib.Z_OK) {
        if (dict) |d| std.heap.c_allocator.free(d);
        std.heap.c_allocator.destroy(made.state);
        made.obj.native = .{};
        ctx.vm.releaseValue(.{ .object = made.obj });
        try warn(ctx, func, "Failed allocating zlib.inflate context", .{});
        return NativeResult.scalar(.{ .bool = false });
    }
    if (encoding == encoding_raw) if (made.state.dict) |d| {
        const r = zlib.inflateSetDictionary(&made.state.z, d.ptr, @intCast(d.len));
        std.heap.c_allocator.free(d);
        made.state.dict = null;
        if (r == zlib.Z_DATA_ERROR) try warn(ctx, func, "Dictionary does not match expected dictionary (incorrect adler32 hash)", .{});
    };
    return NativeResult.transfer(.{ .object = made.obj });
}

fn native_inflate_add(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const func = "inflate_add";
    const p = Args.init(ctx, func, args);
    const obj = try p.object(0, "context", inflate_class);
    const data = try p.str(1, "data");
    const flush = try flushMode(p, 2);
    const s = stateOf(obj) orelse return NativeResult.scalar(.{ .bool = false });
    // reset lazily, so total_in stays readable until the next call
    if (s.status == zlib.Z_STREAM_END) {
        s.status = zlib.Z_OK;
        _ = zlib.inflateReset(&s.z);
    }
    if (data.len == 0 and flush != zlib.Z_FINISH) return NativeResult.copyString(ctx.allocator, "");

    const chunk: usize = 8192;
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(ctx.allocator);
    try out.resize(ctx.allocator, @max(data.len, chunk));
    s.z.next_in = @constCast(data.ptr);
    s.z.avail_in = @intCast(data.len);
    s.z.next_out = out.items.ptr;
    s.z.avail_out = @intCast(out.items.len);
    var used: usize = 0;
    while (true) {
        const status = zlib.inflate(&s.z, flush);
        used = out.items.len - s.z.avail_out;
        s.status = status;
        switch (status) {
            zlib.Z_OK => {
                if (s.z.avail_out != 0) break;
                try grow(ctx, &out, used, chunk, &s.z);
            },
            zlib.Z_STREAM_END => break,
            zlib.Z_BUF_ERROR => {
                if (!(flush == zlib.Z_FINISH and s.z.avail_out == 0)) break;
                try grow(ctx, &out, used, chunk, &s.z);
            },
            zlib.Z_NEED_DICT => {
                const d = s.dict orelse {
                    out.deinit(ctx.allocator);
                    try warn(ctx, func, "Inflating this data requires a preset dictionary, please specify it in the options array of inflate_init()", .{});
                    return NativeResult.scalar(.{ .bool = false });
                };
                const r = zlib.inflateSetDictionary(&s.z, d.ptr, @intCast(d.len));
                std.heap.c_allocator.free(d);
                s.dict = null;
                if (r == zlib.Z_DATA_ERROR) {
                    out.deinit(ctx.allocator);
                    try warn(ctx, func, "Dictionary does not match expected dictionary (incorrect adler32 hash)", .{});
                    return NativeResult.scalar(.{ .bool = false });
                }
            },
            else => {
                out.deinit(ctx.allocator);
                try warn(ctx, func, "{s}", .{std.mem.span(zlib.zError(status))});
                return NativeResult.scalar(.{ .bool = false });
            },
        }
    }
    out.shrinkRetainingCapacity(used);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, try out.toOwnedSlice(ctx.allocator)));
}

// php_zlib_inflate_grow
fn grow(ctx: *NativeContext, out: *std.ArrayListUnmanaged(u8), used: usize, chunk: usize, z: *zlib.z_stream) RuntimeError!void {
    try out.resize(ctx.allocator, out.items.len + chunk);
    z.avail_out = @intCast(chunk);
    z.next_out = out.items.ptr + used;
}

fn native_inflate_get_status(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "inflate_get_status", args);
    const obj = try p.object(0, "context", inflate_class);
    const s = stateOf(obj) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = s.status });
}

fn native_inflate_get_read_len(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "inflate_get_read_len", args);
    const obj = try p.object(0, "context", inflate_class);
    const s = stateOf(obj) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = @intCast(s.z.total_in) });
}

pub fn register(vm: *VM, a: std.mem.Allocator) !void {
    inline for (.{ deflate_class, inflate_class }) |c| {
        try vm.classes.put(a, c, ClassDef{ .name = c, .is_final = true, .native_cleanup = cleanupContext });
    }
    const constants = .{
        .{ "ZLIB_NO_FLUSH", zlib.Z_NO_FLUSH },
        .{ "ZLIB_PARTIAL_FLUSH", zlib.Z_PARTIAL_FLUSH },
        .{ "ZLIB_SYNC_FLUSH", zlib.Z_SYNC_FLUSH },
        .{ "ZLIB_FULL_FLUSH", zlib.Z_FULL_FLUSH },
        .{ "ZLIB_BLOCK", zlib.Z_BLOCK },
        .{ "ZLIB_FINISH", zlib.Z_FINISH },
        .{ "ZLIB_FILTERED", zlib.Z_FILTERED },
        .{ "ZLIB_HUFFMAN_ONLY", zlib.Z_HUFFMAN_ONLY },
        .{ "ZLIB_RLE", zlib.Z_RLE },
        .{ "ZLIB_FIXED", zlib.Z_FIXED },
        .{ "ZLIB_DEFAULT_STRATEGY", zlib.Z_DEFAULT_STRATEGY },
        .{ "ZLIB_OK", zlib.Z_OK },
        .{ "ZLIB_STREAM_END", zlib.Z_STREAM_END },
        .{ "ZLIB_NEED_DICT", zlib.Z_NEED_DICT },
        .{ "ZLIB_ERRNO", zlib.Z_ERRNO },
        .{ "ZLIB_STREAM_ERROR", zlib.Z_STREAM_ERROR },
        .{ "ZLIB_DATA_ERROR", zlib.Z_DATA_ERROR },
        .{ "ZLIB_MEM_ERROR", zlib.Z_MEM_ERROR },
        .{ "ZLIB_BUF_ERROR", zlib.Z_BUF_ERROR },
        .{ "ZLIB_VERSION_ERROR", zlib.Z_VERSION_ERROR },
    };
    inline for (constants) |c| try vm.php_constants.put(a, c[0], .{ .int = c[1] });
}
