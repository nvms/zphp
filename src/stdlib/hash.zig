// php's ext/hash (hash.c): hash(), the hmac and file variants, HashContext
// with its streaming, copying and serialization, the key derivations
// (hash_pbkdf2, hash_hkdf) and the mhash compatibility functions. the
// algorithms are in hash_algos.zig
const std = @import("std");
const algos = @import("hash_algos.zig");
const Ops = algos.Ops;
const InitArgs = algos.InitArgs;
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const PhpArray = value_mod.PhpArray;
const PhpObject = value_mod.PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const RuntimeError = error{ RuntimeError, OutOfMemory };
const Args = @import("string_ports.zig").Args;
const filesystem = @import("filesystem.zig");
const streams = @import("streams.zig");

pub const entries = .{
    .{ "hash", native_hash },
    .{ "hash_file", native_hash_file },
    .{ "hash_hmac", native_hash_hmac },
    .{ "hash_hmac_file", native_hash_hmac_file },
    .{ "hash_init", native_hash_init },
    .{ "hash_update", native_hash_update },
    .{ "hash_update_stream", native_hash_update_stream },
    .{ "hash_update_file", native_hash_update_file },
    .{ "hash_final", native_hash_final },
    .{ "hash_copy", native_hash_copy },
    .{ "hash_algos", native_hash_algos },
    .{ "hash_hmac_algos", native_hash_hmac_algos },
    .{ "hash_pbkdf2", native_hash_pbkdf2 },
    .{ "hash_equals", native_hash_equals },
    .{ "hash_hkdf", native_hash_hkdf },
    .{ "md5_file", native_md5_file },
    .{ "sha1_file", native_sha1_file },
    .{ "mhash", native_mhash },
    .{ "mhash_get_hash_name", native_mhash_get_hash_name },
    .{ "mhash_count", native_mhash_count },
    .{ "mhash_get_block_size", native_mhash_get_block_size },
    .{ "mhash_keygen_s2k", native_mhash_keygen_s2k },
};

const class_name = "HashContext";
const hmac_option: i64 = 1;

// a context buffer for a one-shot computation, zeroed as php's
// php_hash_alloc_context zeroes one
const Scratch = struct {
    bytes: [algos.max_context_size]u8 align(algos.context_align),
};

fn ctxPtr(s: *Scratch, ops: *const Ops) *anyopaque {
    @memset(s.bytes[0..ops.context_size], 0);
    return @ptrCast(&s.bytes);
}

// ---------------------------------------------------------------------------
// argument helpers

fn throwFmt(ctx: *NativeContext, class: []const u8, comptime fmt: []const u8, args: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException(class, msg);
    return error.RuntimeError;
}

// Z_PARAM_ARRAY_HT
fn arrayArg(p: Args, index: usize, name: []const u8) RuntimeError!?*PhpArray {
    if (index >= p.args.len) return null;
    const v = p.args[index];
    if (v == .array) return v.array;
    return p.typeError(index, name, "array");
}

// Z_PARAM_PATH: a string without NUL bytes
fn pathArg(p: Args, index: usize, name: []const u8) RuntimeError![]const u8 {
    const path = try p.strAs(index, name, "string");
    if (std.mem.indexOfScalar(u8, path, 0) != null) return p.valueError(index, name, "must not contain any null bytes");
    return path;
}

fn digestResult(ctx: *NativeContext, digest: []const u8, binary: bool) RuntimeError!NativeResult {
    if (binary) return NativeResult.copyString(ctx.allocator, digest);
    const hex = "0123456789abcdef";
    const out = try ctx.allocator.alloc(u8, digest.len * 2);
    for (digest, 0..) |b, i| {
        out[i * 2] = hex[b >> 4];
        out[i * 2 + 1] = hex[b & 0x0f];
    }
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

fn initContext(ctx: *NativeContext, ops: *const Ops, context: *anyopaque, options: ?*PhpArray, func: []const u8) RuntimeError!void {
    try ops.init(context, .{ .ctx = ctx, .options = options, .func = func });
    if (ctx.vm.pending_exception != null) return error.RuntimeError;
}

// ---------------------------------------------------------------------------
// hmac (php_hash_hmac_prep_key, php_hash_hmac_round)

fn prepKey(k: []u8, ops: *const Ops, context: *anyopaque, key: []const u8) RuntimeError!void {
    @memset(k, 0);
    if (key.len > ops.block_size) {
        try ops.init(context, .{});
        ops.update(context, key);
        ops.final(k, context);
    } else {
        @memcpy(k[0..key.len], key);
    }
    for (k) |*b| b.* ^= 0x36;
}

fn hmacRound(out: []u8, ops: *const Ops, context: *anyopaque, key: []const u8, data: []const u8) RuntimeError!void {
    try ops.init(context, .{});
    ops.update(context, key);
    ops.update(context, data);
    ops.final(out, context);
}

fn xorKey(k: []u8, with: u8) void {
    for (k) |*b| b.* ^= with;
}

// ---------------------------------------------------------------------------
// hash(), hash_file(), hash_hmac(), hash_hmac_file()

// php_hash_do_hash: the data is the bytes to hash, or a filename
fn doHash(ctx: *NativeContext, comptime func: []const u8, algo: []const u8, data: []const u8, binary: bool, is_file: bool, options: ?*PhpArray) RuntimeError!NativeResult {
    const ops = algos.fetch(algo) orelse return throwFmt(ctx, "ValueError", func ++ "(): Argument #1 ($algo) must be a valid hashing algorithm", .{});
    var input: ?Value.String = null;
    defer if (input) |s| s.release();
    if (is_file) {
        if (std.mem.indexOfScalar(u8, data, 0) != null) return throwFmt(ctx, "ValueError", func ++ "(): Argument #1 ($algo) must not contain any null bytes", .{});
        input = (try filesystem.readPathAs(ctx, data, func)) orelse return NativeResult.scalar(.{ .bool = false });
    }
    var scratch: Scratch = undefined;
    const context = ctxPtr(&scratch, ops);
    try initContext(ctx, ops, context, options, func);
    ops.update(context, if (input) |s| s.bytes() else data);
    var digest: [algos.max_digest_size]u8 = undefined;
    ops.final(digest[0..ops.digest_size], context);
    return digestResult(ctx, digest[0..ops.digest_size], binary);
}

// php_hash_do_hash_hmac
fn doHmac(ctx: *NativeContext, comptime func: []const u8, algo: []const u8, data: []const u8, key: []const u8, binary: bool, is_file: bool) RuntimeError!NativeResult {
    const ops = algos.fetch(algo) orelse return throwFmt(ctx, "ValueError", func ++ "(): Argument #1 ($algo) must be a valid cryptographic hashing algorithm", .{});
    if (!ops.is_crypto) return throwFmt(ctx, "ValueError", func ++ "(): Argument #1 ($algo) must be a valid cryptographic hashing algorithm", .{});
    var input: ?Value.String = null;
    defer if (input) |s| s.release();
    if (is_file) {
        if (std.mem.indexOfScalar(u8, data, 0) != null) return throwFmt(ctx, "ValueError", func ++ "(): Argument #2 ($filename) must not contain any null bytes", .{});
        input = (try filesystem.readPathAs(ctx, data, func)) orelse return NativeResult.scalar(.{ .bool = false });
    }
    var digest: [algos.max_digest_size]u8 = undefined;
    try hmac(ops, if (input) |s| s.bytes() else data, key, digest[0..ops.digest_size]);
    return digestResult(ctx, digest[0..ops.digest_size], binary);
}

fn hmac(ops: *const Ops, data: []const u8, key: []const u8, out: []u8) RuntimeError!void {
    var scratch: Scratch = undefined;
    const context = ctxPtr(&scratch, ops);
    var kbuf: [algos.max_block_size]u8 = undefined;
    const k = kbuf[0..ops.block_size];
    try prepKey(k, ops, context, key);
    try hmacRound(out, ops, context, k, data);
    xorKey(k, 0x6A);
    var inner: [algos.max_digest_size]u8 = undefined;
    @memcpy(inner[0..out.len], out);
    try hmacRound(out, ops, context, k, inner[0..out.len]);
    std.crypto.secureZero(u8, k);
}

fn native_hash(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "hash", args);
    const algo = try p.str(0, "algo");
    const data = try p.str(1, "data");
    const binary = try p.boolean(2, "binary", false);
    const options = try arrayArg(p, 3, "options");
    return doHash(ctx, "hash", algo, data, binary, false, options);
}

fn native_hash_file(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "hash_file", args);
    const algo = try p.str(0, "algo");
    const filename = try p.str(1, "filename");
    const binary = try p.boolean(2, "binary", false);
    const options = try arrayArg(p, 3, "options");
    return doHash(ctx, "hash_file", algo, filename, binary, true, options);
}

fn native_hash_hmac(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "hash_hmac", args);
    const algo = try p.str(0, "algo");
    const data = try p.str(1, "data");
    const key = try p.str(2, "key");
    const binary = try p.boolean(3, "binary", false);
    return doHmac(ctx, "hash_hmac", algo, data, key, binary, false);
}

fn native_hash_hmac_file(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "hash_hmac_file", args);
    const algo = try p.str(0, "algo");
    const filename = try p.str(1, "filename");
    const key = try p.str(2, "key");
    const binary = try p.boolean(3, "binary", false);
    return doHmac(ctx, "hash_hmac_file", algo, filename, key, binary, true);
}

// md5_file() and sha1_file() are ext/standard's, on the same contexts
fn native_md5_file(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "md5_file", args);
    const path = try p.str(0, "filename");
    const binary = try p.boolean(1, "binary", false);
    return digestFile(ctx, "md5_file", &algos.md5_ops, path, binary);
}

fn native_sha1_file(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "sha1_file", args);
    const path = try p.str(0, "filename");
    const binary = try p.boolean(1, "binary", false);
    return digestFile(ctx, "sha1_file", &algos.sha1_ops, path, binary);
}

fn digestFile(ctx: *NativeContext, comptime func: []const u8, ops: *const Ops, path: []const u8, binary: bool) RuntimeError!NativeResult {
    const content = (try filesystem.readPathAs(ctx, path, func)) orelse return NativeResult.scalar(.{ .bool = false });
    defer content.release();
    var scratch: Scratch = undefined;
    const context = ctxPtr(&scratch, ops);
    try ops.init(context, .{});
    ops.update(context, content.bytes());
    var digest: [algos.max_digest_size]u8 = undefined;
    ops.final(digest[0..ops.digest_size], context);
    return digestResult(ctx, digest[0..ops.digest_size], binary);
}

// ---------------------------------------------------------------------------
// HashContext

// php_hashcontext_object: the context is null once the object is finalized
// (or before __unserialize gave it one)
const State = struct {
    ops: ?*const Ops = null,
    context: ?[]align(algos.context_align) u8 = null,
    options: i64 = 0,
    key: ?[]u8 = null,

    fn freeContext(self: *State) void {
        if (self.context) |c| {
            std.crypto.secureZero(u8, c);
            std.heap.c_allocator.free(c);
        }
        self.context = null;
    }

    fn freeKey(self: *State) void {
        if (self.key) |k| {
            std.crypto.secureZero(u8, k);
            std.heap.c_allocator.free(k);
        }
        self.key = null;
    }

    fn allocContext(self: *State, ops: *const Ops) RuntimeError!*anyopaque {
        const c = try std.heap.c_allocator.alignedAlloc(u8, .fromByteUnits(algos.context_align), ops.context_size);
        @memset(c, 0);
        self.context = c;
        return @ptrCast(c.ptr);
    }
};

fn stateOf(obj: *PhpObject) ?*State {
    return obj.native.get(State, .hash_context);
}

fn ensureState(obj: *PhpObject) RuntimeError!*State {
    if (stateOf(obj)) |s| return s;
    const s = try std.heap.c_allocator.create(State);
    s.* = .{};
    obj.native = .{ .kind = .hash_context, .ptr = @intFromPtr(s) };
    return s;
}

fn cleanupHashContext(obj: *PhpObject) bool {
    if (stateOf(obj)) |s| {
        s.freeContext();
        s.freeKey();
        std.heap.c_allocator.destroy(s);
    }
    obj.native = .{};
    return true;
}

pub fn cleanupResources(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    for (objects.items) |obj| {
        if (obj.pooled or obj.native.kind != .hash_context) continue;
        _ = cleanupHashContext(obj);
    }
}

// php_hashcontext_clone: a finalized context can't be cloned
fn copyState(vm: *VM, src: *PhpObject, copy: *PhpObject) RuntimeError!bool {
    const old = stateOf(src);
    if (old == null or old.?.context == null) {
        try vm.setPendingException("ValueError", "Cannot clone a finalized HashContext");
        return false;
    }
    const o = old.?;
    const ops = o.ops.?;
    const s = try ensureState(copy);
    s.ops = ops;
    s.options = o.options;
    const context = try s.allocContext(ops);
    @memcpy(s.context.?, o.context.?);
    if (ops.fixup_copy) |fix| fix(context, @ptrCast(o.context.?.ptr));
    if (o.key) |k| s.key = try std.heap.c_allocator.dupe(u8, k);
    return true;
}

fn cloneHashContext(vm: *VM, src: *PhpObject, copy: *PhpObject) bool {
    return copyState(vm, src, copy) catch false;
}

fn thisObject(ctx: *NativeContext) ?*PhpObject {
    if (ctx.vm.frame_count == 0) return null;
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    return if (v == .object) v.object else null;
}

// Z_PARAM_OBJ_OF_CLASS(HashContext) and PHP_HASHCONTEXT_VERIFY
fn liveContext(p: Args, index: usize) RuntimeError!*State {
    const obj = try p.object(index, "context", class_name);
    if (stateOf(obj)) |s| if (s.context != null) return s;
    return throwFmt(p.ctx, "TypeError", "{s}(): Argument #{d} ($context) must be a valid, non-finalized HashContext", .{ p.func, index + 1 });
}

fn native_hash_init(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "hash_init", args);
    const algo = try p.str(0, "algo");
    const options = try p.optLong(1, "flags", 0);
    const key = try p.optStr(2, "key", "");
    const init_args = try arrayArg(p, 3, "options");
    const ops = algos.fetch(algo) orelse return throwFmt(ctx, "ValueError", "hash_init(): Argument #1 ($algo) must be a valid hashing algorithm", .{});
    if (options & hmac_option != 0) {
        if (!ops.is_crypto) return throwFmt(ctx, "ValueError", "hash_init(): Argument #1 ($algo) must be a cryptographic hashing algorithm if HMAC is requested", .{});
        if (key.len == 0) return throwFmt(ctx, "ValueError", "hash_init(): Argument #3 ($key) must not be empty when HMAC is requested", .{});
    }
    const obj = try ctx.vm.allocObject(.{ .class_name = class_name });
    // an init that throws (xxh3's secret) frees the object, as php's
    // return value is
    errdefer {
        obj.retain();
        ctx.vm.releaseValue(.{ .object = obj });
    }
    const s = try ensureState(obj);
    s.ops = ops;
    s.options = options;
    const context = try s.allocContext(ops);
    try initContext(ctx, ops, context, init_args, "hash_init");
    if (options & hmac_option != 0) {
        const k = try std.heap.c_allocator.alloc(u8, ops.block_size);
        @memset(k, 0);
        if (key.len > ops.block_size) {
            ops.update(context, key);
            ops.final(k, context);
            try ops.init(context, .{ .ctx = ctx, .options = init_args, .func = "hash_init" });
        } else {
            @memcpy(k[0..key.len], key);
        }
        xorKey(k, 0x36);
        ops.update(context, k);
        s.key = k;
    }
    return NativeResult.borrowed(.{ .object = obj });
}

fn native_hash_update(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "hash_update", args);
    const s = try liveContext(p, 0);
    const data = try p.str(1, "data");
    s.ops.?.update(@ptrCast(s.context.?.ptr), data);
    return NativeResult.scalar(.{ .bool = true });
}

fn native_hash_update_stream(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "hash_update_stream", args);
    const s = try liveContext(p, 0);
    const stream = try filesystem.streamArg(ctx, args, .{ .func = "hash_update_stream", .index = 1 });
    var length = try p.optLong(2, "length", -1);
    var didread: i64 = 0;
    var buf: [1024]u8 = undefined;
    while (length != 0) {
        var toread: usize = buf.len;
        if (length > 0 and toread > length) toread = @intCast(length);
        const n = try streams.read(ctx, stream, buf[0..toread]);
        if (n <= 0) break;
        const got: usize = @intCast(n);
        s.ops.?.update(@ptrCast(s.context.?.ptr), buf[0..got]);
        length -= n;
        didread += n;
    }
    return NativeResult.scalar(.{ .int = didread });
}

fn native_hash_update_file(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "hash_update_file", args);
    _ = try p.object(0, "context", class_name);
    const path = try pathArg(p, 1, "filename");
    const s = try liveContext(p, 0);
    const content = (try filesystem.readPathAs(ctx, path, "hash_update_file")) orelse return NativeResult.scalar(.{ .bool = false });
    defer content.release();
    s.ops.?.update(@ptrCast(s.context.?.ptr), content.bytes());
    return NativeResult.scalar(.{ .bool = true });
}

fn native_hash_final(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "hash_final", args);
    const s = try liveContext(p, 0);
    const binary = try p.boolean(1, "binary", false);
    const ops = s.ops.?;
    const context: *anyopaque = @ptrCast(s.context.?.ptr);
    var digest: [algos.max_digest_size]u8 = undefined;
    const d = digest[0..ops.digest_size];
    ops.final(d, context);
    if (s.options & hmac_option != 0) {
        if (s.key) |k| {
            xorKey(k, 0x6A);
            try ops.init(context, .{});
            ops.update(context, k);
            ops.update(context, d);
            ops.final(d, context);
        }
        s.freeKey();
    }
    s.freeContext();
    return digestResult(ctx, d, binary);
}

fn native_hash_copy(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "hash_copy", args);
    _ = try liveContext(p, 0);
    const src = args[0].object;
    const copy = try ctx.vm.allocObject(.{ .class_name = class_name });
    var it = src.properties.iterator();
    while (it.next()) |e| try copy.set(ctx.allocator, e.key_ptr.*, e.value_ptr.*);
    if (!try copyState(ctx.vm, src, copy)) return error.RuntimeError;
    return NativeResult.borrowed(.{ .object = copy });
}

fn native_hash_algos(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    for (algos.registry) |entry| try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(entry[0]) });
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_hash_hmac_algos(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    for (algos.registry) |entry| {
        if (entry[1].is_crypto) try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(entry[0]) });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

// ---------------------------------------------------------------------------
// HashContext's methods and serialization

fn methodConstruct(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return throwFmt(ctx, "Error", "Illegal call to private/final constructor", .{});
}

fn methodDebugInfo(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    if (thisObject(ctx)) |obj| if (stateOf(obj)) |s| if (s.ops) |ops| {
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("algo") }, .{ .string = Value.String.borrowed(ops.name) });
    };
    return NativeResult.borrowed(.{ .array = arr });
}

const Spec = struct {
    text: []const u8,
    at: usize = 0,
    pos: usize = 0,
    max_align: usize = 1,

    const Item = struct { size: usize, count: usize, skip: bool };

    fn done(self: *const Spec) bool {
        return self.at >= self.text.len or self.text[self.at] == '.';
    }

    // parse_serialize_spec
    fn next(self: *Spec) Item {
        const ch = self.text[self.at];
        const size: usize, const alignment: usize = switch (std.ascii.toLower(ch)) {
            's' => .{ 2, 2 },
            'l', 'i' => .{ 4, 4 },
            'q' => .{ 8, 8 },
            else => .{ 1, 1 },
        };
        self.pos = alignTo(self.pos, alignment);
        self.max_align = @max(self.max_align, alignment);
        self.at += 1;
        var count: usize = 1;
        if (self.at < self.text.len and std.ascii.isDigit(self.text[self.at])) {
            count = 0;
            while (self.at < self.text.len and std.ascii.isDigit(self.text[self.at])) : (self.at += 1) count = count * 10 + (self.text[self.at] - '0');
        }
        return .{ .size = size, .count = count, .skip = std.ascii.isUpper(ch) };
    }

    fn sizeMatches(self: *const Spec, context_size: usize) bool {
        if (self.at < self.text.len and self.text[self.at] == '.') return alignTo(self.pos, self.max_align) == context_size;
        return true;
    }
};

fn alignTo(pos: usize, alignment: usize) usize {
    const offset = pos & (alignment - 1);
    return pos + (if (offset != 0) alignment - offset else 0);
}

fn readWord(size: usize, buf: []const u8) u64 {
    return switch (size) {
        2 => std.mem.readInt(u16, buf[0..2], .little),
        4 => std.mem.readInt(u32, buf[0..4], .little),
        8 => std.mem.readInt(u64, buf[0..8], .little),
        else => buf[0],
    };
}

fn writeWord(size: usize, buf: []u8, v: u64) void {
    switch (size) {
        2 => std.mem.writeInt(u16, buf[0..2], @truncate(v), .little),
        4 => std.mem.writeInt(u32, buf[0..4], @truncate(v), .little),
        8 => std.mem.writeInt(u64, buf[0..8], v, .little),
        else => buf[0] = @truncate(v),
    }
}

// php_hash_serialize_spec: words as (32-bit signed) ints, a 64-bit word as
// two of them low half first, a run of bytes as one string
fn serializeSpec(ctx: *NativeContext, buf: []const u8, spec_text: []const u8) RuntimeError!?*PhpArray {
    const arr = try ctx.createArray();
    var spec: Spec = .{ .text = spec_text };
    while (!spec.done()) {
        const item = spec.next();
        if (spec.pos + item.count * item.size > buf.len) return null;
        if (item.skip) {
            spec.pos += item.count * item.size;
        } else if (item.size == 1 and item.count > 1) {
            const s = try Value.String.create(ctx.allocator, buf[spec.pos..][0..item.count]);
            defer s.release();
            try arr.append(ctx.allocator, .{ .string = s });
            spec.pos += item.count;
        } else {
            for (0..item.count) |_| {
                const v = readWord(item.size, buf[spec.pos..]);
                spec.pos += item.size;
                try arr.append(ctx.allocator, .{ .int = @as(i32, @bitCast(@as(u32, @truncate(v)))) });
                if (item.size == 8) try arr.append(ctx.allocator, .{ .int = @as(i32, @bitCast(@as(u32, @truncate(v >> 32)))) });
            }
        }
    }
    if (!spec.sizeMatches(buf.len)) return null;
    return arr;
}

const wrong_context_size: i64 = -999;
const byte_offset_pos_error: i64 = -1000;
const context_validation_failure: i64 = -2000;

// php_hash_unserialize_spec: 0 on success, else php's failure code
fn unserializeSpec(buf: []u8, zv: Value, spec_text: []const u8) i64 {
    if (zv != .array) return -1;
    const arr = zv.array;
    var spec: Spec = .{ .text = spec_text };
    var j: i64 = 0;
    while (!spec.done()) {
        const item = spec.next();
        if (spec.pos + item.count * item.size > buf.len) return wrong_context_size;
        if (item.skip) {
            spec.pos += item.count * item.size;
        } else if (item.size == 1 and item.count > 1) {
            const elt = elementAt(arr, j);
            if (elt == null or elt.? != .string or elt.?.string.bytes().len != item.count) return byte_offset_pos_error - @as(i64, @intCast(spec.pos));
            j += 1;
            @memcpy(buf[spec.pos..][0..item.count], elt.?.string.bytes());
            spec.pos += item.count;
        } else {
            for (0..item.count) |_| {
                var elt = elementAt(arr, j);
                if (elt == null or elt.? != .int) return byte_offset_pos_error - @as(i64, @intCast(spec.pos));
                j += 1;
                var v: u64 = @as(u32, @truncate(@as(u64, @bitCast(elt.?.int))));
                if (item.size == 8) {
                    elt = elementAt(arr, j);
                    if (elt == null or elt.? != .int) return byte_offset_pos_error - @as(i64, @intCast(spec.pos));
                    j += 1;
                    v +%= @as(u64, @bitCast(elt.?.int)) << 32;
                }
                writeWord(item.size, buf[spec.pos..], v);
                spec.pos += item.size;
            }
        }
    }
    if (!spec.sizeMatches(buf.len)) return wrong_context_size;
    return 0;
}

fn elementAt(arr: *PhpArray, index: i64) ?Value {
    const entry = arr.getPtr(.{ .int = index }) orelse return null;
    return if (entry.ref) |cell| cell.* else entry.value;
}

fn methodSerialize(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = thisObject(ctx) orelse return NativeResult.scalar(.null);
    const s = stateOf(obj) orelse return throwFmt(ctx, "Exception", "HashContext for algorithm \"\" cannot be serialized", .{});
    const ops = s.ops.?;
    if (s.options & hmac_option != 0) return throwFmt(ctx, "Exception", "HashContext with HASH_HMAC option cannot be serialized", .{});
    const state: ?*PhpArray = if (ops.spec != null and s.context != null) try serializeSpec(ctx, s.context.?, ops.spec.?) else null;
    const st = state orelse return throwFmt(ctx, "Exception", "HashContext for algorithm \"{s}\" cannot be serialized", .{ops.name});
    const arr = try ctx.createArray();
    try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(ops.name) });
    try arr.append(ctx.allocator, .{ .int = s.options });
    try arr.append(ctx.allocator, .{ .array = st });
    try arr.append(ctx.allocator, .{ .int = ops.magic });
    const members = try ctx.createArray();
    var it = obj.properties.iterator();
    while (it.next()) |e| try members.setCopiedKey(ctx.allocator, e.key_ptr.*, e.value_ptr.*);
    try arr.append(ctx.allocator, .{ .array = members });
    return NativeResult.borrowed(.{ .array = arr });
}

fn methodUnserialize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = thisObject(ctx) orelse return NativeResult.scalar(.null);
    const p = Args.init(ctx, "HashContext::__unserialize", args);
    const data = (try arrayArg(p, 0, "data")) orelse return p.typeError(0, "data", "array");
    if (stateOf(obj)) |s| if (s.context != null) return throwFmt(ctx, "Exception", "HashContext::__unserialize called on initialized object", .{});
    const algo_v = elementAt(data, 0);
    const options_v = elementAt(data, 1);
    const hash_v = elementAt(data, 2);
    const magic_v = elementAt(data, 3);
    const members_v = elementAt(data, 4);
    if (algo_v == null or algo_v.? != .string or magic_v == null or magic_v.? != .int or options_v == null or options_v.? != .int or hash_v == null or members_v == null or members_v.? != .array) {
        return throwFmt(ctx, "Exception", "Incomplete or ill-formed serialization data", .{});
    }
    const options = options_v.?.int;
    if (options & hmac_option != 0) return throwFmt(ctx, "Exception", "HashContext with HASH_HMAC option cannot be serialized", .{});
    const ops = algos.fetch(algo_v.?.string.bytes()) orelse return throwFmt(ctx, "Exception", "Unknown hash algorithm", .{});
    const s = try ensureState(obj);
    s.ops = ops;
    s.options = options;
    const context = try s.allocContext(ops);
    try ops.init(context, .{});
    var code: i64 = -1;
    if (ops.spec != null and magic_v.?.int == ops.magic) {
        code = unserializeSpec(s.context.?, hash_v.?, ops.spec.?);
        if (code == 0) if (ops.valid) |valid| {
            if (!valid(context)) code = context_validation_failure;
        };
    }
    if (code != 0) {
        s.freeContext();
        s.freeKey();
        return throwFmt(ctx, "Exception", "Incomplete or ill-formed serialization data (\"{s}\" code {d})", .{ ops.name, code });
    }
    // object_properties_load
    for (members_v.?.array.entries.items) |e| {
        const v = if (e.ref) |cell| cell.* else e.value;
        switch (e.key) {
            .string => |k| try obj.set(ctx.allocator, k.bytes(), v),
            .int => |i| {
                var nb: [24]u8 = undefined;
                try obj.set(ctx.allocator, std.fmt.bufPrint(&nb, "{d}", .{i}) catch unreachable, v);
            },
        }
    }
    return NativeResult.scalar(.null);
}

// ---------------------------------------------------------------------------
// hash_pbkdf2(), hash_equals(), hash_hkdf()

fn native_hash_pbkdf2(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "hash_pbkdf2", args);
    const algo = try p.str(0, "algo");
    const password = try p.str(1, "password");
    const salt = try p.str(2, "salt");
    const iterations = try p.long(3, "iterations");
    var length = try p.optLong(4, "length", 0);
    const binary = try p.boolean(5, "binary", false);
    const options = try arrayArg(p, 6, "options");
    const ops = algos.fetch(algo) orelse return throwFmt(ctx, "ValueError", "hash_pbkdf2(): Argument #1 ($algo) must be a valid cryptographic hashing algorithm", .{});
    if (!ops.is_crypto) return throwFmt(ctx, "ValueError", "hash_pbkdf2(): Argument #1 ($algo) must be a valid cryptographic hashing algorithm", .{});
    if (salt.len > std.math.maxInt(i32) - 4) return throwFmt(ctx, "ValueError", "hash_pbkdf2(): Argument #3 ($salt) must be less than or equal to INT_MAX - 4 bytes", .{});
    if (iterations <= 0) return throwFmt(ctx, "ValueError", "hash_pbkdf2(): Argument #4 ($iterations) must be greater than 0", .{});
    if (length < 0) return throwFmt(ctx, "ValueError", "hash_pbkdf2(): Argument #5 ($length) must be greater than or equal to 0", .{});

    var scratch: Scratch = undefined;
    const context = ctxPtr(&scratch, ops);
    try initContext(ctx, ops, context, options, "hash_pbkdf2");
    var k1buf: [algos.max_block_size]u8 = undefined;
    var k2buf: [algos.max_block_size]u8 = undefined;
    const k1 = k1buf[0..ops.block_size];
    const k2 = k2buf[0..ops.block_size];
    try prepKey(k1, ops, context, password);
    for (k1, k2) |a, *b| b.* = a ^ 0x6A;

    if (length == 0) {
        length = @intCast(ops.digest_size);
        if (!binary) length *= 2;
    }
    var digest_length = length;
    if (!binary) digest_length = @divTrunc(length, 2) + @rem(length, 2);
    const dsize: i64 = @intCast(ops.digest_size);
    const loops = @divTrunc(digest_length - 1, dsize) + 1;
    const result_len = std.math.mul(usize, @intCast(loops), ops.digest_size) catch return error.OutOfMemory;
    const result = try ctx.allocator.alloc(u8, result_len);
    defer ctx.allocator.free(result);
    const computed_salt = try ctx.allocator.alloc(u8, salt.len + 4);
    defer ctx.allocator.free(computed_salt);
    @memcpy(computed_salt[0..salt.len], salt);
    var digest: [algos.max_digest_size]u8 = undefined;
    var temp: [algos.max_digest_size]u8 = undefined;
    const d = digest[0..ops.digest_size];
    const t = temp[0..ops.digest_size];
    var i: i64 = 1;
    while (i <= loops) : (i += 1) {
        std.mem.writeInt(u32, computed_salt[salt.len..][0..4], @truncate(@as(u64, @bitCast(i))), .big);
        try hmacRound(d, ops, context, k1, computed_salt);
        @memcpy(t, d);
        try hmacRound(d, ops, context, k2, t);
        @memcpy(t, d);
        var j: i64 = 1;
        while (j < iterations) : (j += 1) {
            var tmp: [algos.max_digest_size]u8 = undefined;
            @memcpy(tmp[0..d.len], d);
            try hmacRound(d, ops, context, k1, tmp[0..d.len]);
            @memcpy(tmp[0..d.len], d);
            try hmacRound(d, ops, context, k2, tmp[0..d.len]);
            for (t, d) |*a, b| a.* ^= b;
        }
        const at: usize = @intCast((i - 1) * dsize);
        @memcpy(result[at..][0..ops.digest_size], t);
    }
    std.crypto.secureZero(u8, k1);
    std.crypto.secureZero(u8, k2);

    const out_len: usize = @intCast(length);
    const out = try ctx.allocator.alloc(u8, out_len);
    if (binary) {
        @memcpy(out, result[0..out_len]);
    } else {
        const hex = "0123456789abcdef";
        const dl: usize = @intCast(digest_length);
        for (result[0..dl], 0..) |b, n| {
            if (n * 2 < out_len) out[n * 2] = hex[b >> 4];
            if (n * 2 + 1 < out_len) out[n * 2 + 1] = hex[b & 0x0f];
        }
    }
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

fn native_hash_equals(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "hash_equals", args);
    if (args.len < 1 or args[0] != .string) return p.typeError(0, "known_string", "string");
    if (args.len < 2 or args[1] != .string) return p.typeError(1, "user_string", "string");
    const known = args[0].string.bytes();
    const user = args[1].string.bytes();
    if (known.len != user.len) return NativeResult.scalar(.{ .bool = false });
    var diff: u8 = 0;
    for (known, user) |a, b| diff |= a ^ b;
    return NativeResult.scalar(.{ .bool = diff == 0 });
}

fn native_hash_hkdf(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "hash_hkdf", args);
    const algo = try p.str(0, "algo");
    const ikm = try p.str(1, "key");
    var length = try p.optLong(2, "length", 0);
    const info = try p.optStr(3, "info", "");
    const salt = try p.optStr(4, "salt", "");
    const ops = algos.fetch(algo) orelse return throwFmt(ctx, "ValueError", "hash_hkdf(): Argument #1 ($algo) must be a valid cryptographic hashing algorithm", .{});
    if (!ops.is_crypto) return throwFmt(ctx, "ValueError", "hash_hkdf(): Argument #1 ($algo) must be a valid cryptographic hashing algorithm", .{});
    if (ikm.len == 0) return throwFmt(ctx, "ValueError", "hash_hkdf(): Argument #2 ($key) must not be empty", .{});
    const dsize: i64 = @intCast(ops.digest_size);
    if (length < 0) return throwFmt(ctx, "ValueError", "hash_hkdf(): Argument #3 ($length) must be greater than or equal to 0", .{});
    if (length == 0) {
        length = dsize;
    } else if (length > dsize * 255) {
        return throwFmt(ctx, "ValueError", "hash_hkdf(): Argument #3 ($length) must be less than or equal to {d}", .{dsize * 255});
    }

    var scratch: Scratch = undefined;
    const context = ctxPtr(&scratch, ops);
    try ops.init(context, .{});
    var kbuf: [algos.max_block_size]u8 = undefined;
    const k = kbuf[0..ops.block_size];
    // extract
    try prepKey(k, ops, context, salt);
    var prk_buf: [algos.max_digest_size]u8 = undefined;
    const prk = prk_buf[0..ops.digest_size];
    try hmacRound(prk, ops, context, k, ikm);
    xorKey(k, 0x6A);
    var tmp: [algos.max_digest_size]u8 = undefined;
    @memcpy(tmp[0..prk.len], prk);
    try hmacRound(prk, ops, context, k, tmp[0..prk.len]);
    std.crypto.secureZero(u8, k);

    // expand
    const out_len: usize = @intCast(length);
    const out = try ctx.allocator.alloc(u8, out_len);
    var digest_buf: [algos.max_digest_size]u8 = undefined;
    const digest = digest_buf[0..ops.digest_size];
    const rounds = (out_len - 1) / ops.digest_size + 1;
    var i: usize = 1;
    while (i <= rounds) : (i += 1) {
        const c = [1]u8{@truncate(i)};
        try prepKey(k, ops, context, prk);
        try ops.init(context, .{});
        ops.update(context, k);
        if (i > 1) ops.update(context, digest);
        if (info.len > 0) ops.update(context, info);
        ops.update(context, &c);
        ops.final(digest, context);
        xorKey(k, 0x6A);
        @memcpy(tmp[0..digest.len], digest);
        try hmacRound(digest, ops, context, k, tmp[0..digest.len]);
        const at = (i - 1) * ops.digest_size;
        const n = if (i == rounds) out_len - at else ops.digest_size;
        @memcpy(out[at..][0..n], digest[0..n]);
    }
    std.crypto.secureZero(u8, k);
    std.crypto.secureZero(u8, digest);
    std.crypto.secureZero(u8, prk);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

// ---------------------------------------------------------------------------
// mhash compatibility (PHP_MHASH_BC)

const mhash_algos = [42]?struct { []const u8, []const u8 }{
    .{ "CRC32", "crc32" },         .{ "MD5", "md5" },             .{ "SHA1", "sha1" },           .{ "HAVAL256", "haval256,3" },
    null,                          .{ "RIPEMD160", "ripemd160" }, null,                          .{ "TIGER", "tiger192,3" },
    .{ "GOST", "gost" },           .{ "CRC32B", "crc32b" },       .{ "HAVAL224", "haval224,3" }, .{ "HAVAL192", "haval192,3" },
    .{ "HAVAL160", "haval160,3" }, .{ "HAVAL128", "haval128,3" }, .{ "TIGER128", "tiger128,3" }, .{ "TIGER160", "tiger160,3" },
    .{ "MD4", "md4" },             .{ "SHA256", "sha256" },       .{ "ADLER32", "adler32" },     .{ "SHA224", "sha224" },
    .{ "SHA512", "sha512" },       .{ "SHA384", "sha384" },       .{ "WHIRLPOOL", "whirlpool" }, .{ "RIPEMD128", "ripemd128" },
    .{ "RIPEMD256", "ripemd256" }, .{ "RIPEMD320", "ripemd320" }, null,                          .{ "SNEFRU256", "snefru256" },
    .{ "MD2", "md2" },             .{ "FNV132", "fnv132" },       .{ "FNV1A32", "fnv1a32" },     .{ "FNV164", "fnv164" },
    .{ "FNV1A64", "fnv1a64" },     .{ "JOAAT", "joaat" },         .{ "CRC32C", "crc32c" },       .{ "MURMUR3A", "murmur3a" },
    .{ "MURMUR3C", "murmur3c" },   .{ "MURMUR3F", "murmur3f" },   .{ "XXH32", "xxh32" },         .{ "XXH64", "xxh64" },
    .{ "XXH3", "xxh3" },           .{ "XXH128", "xxh128" },
};

fn mhashEntry(algorithm: i64) ?struct { []const u8, []const u8 } {
    if (algorithm < 0 or algorithm >= mhash_algos.len) return null;
    return mhash_algos[@intCast(algorithm)];
}

// MHASH_* constants are deprecated since 8.5
pub fn isMhashConstant(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, "MHASH_")) return false;
    for (mhash_algos) |entry| {
        if (entry) |e| if (std.mem.eql(u8, e[0], name[6..])) return true;
    }
    return false;
}

fn native_mhash(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "mhash", args);
    const algorithm = try p.long(0, "algo");
    const data = try p.str(1, "data");
    const key = try p.strOrNull(2, "key");
    const entry = mhashEntry(algorithm) orelse return NativeResult.scalar(.{ .bool = false });
    if (key) |k| return doHmac(ctx, "mhash", entry[1], data, k, true, false);
    return doHash(ctx, "mhash", entry[1], data, true, false, null);
}

fn native_mhash_get_hash_name(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const algorithm = try Args.init(ctx, "mhash_get_hash_name", args).long(0, "algo");
    const entry = mhashEntry(algorithm) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.copyString(ctx.allocator, entry[0]);
}

fn native_mhash_count(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = mhash_algos.len - 1 });
}

fn native_mhash_get_block_size(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const algorithm = try Args.init(ctx, "mhash_get_block_size", args).long(0, "algo");
    const entry = mhashEntry(algorithm) orelse return NativeResult.scalar(.{ .bool = false });
    const ops = algos.fetch(entry[1]) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(ops.digest_size) });
}

fn native_mhash_keygen_s2k(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "mhash_keygen_s2k", args);
    const algorithm = try p.long(0, "algo");
    const password = try p.str(1, "password");
    const salt = try p.str(2, "salt");
    const l_bytes = try p.long(3, "length");
    const bytes: i32 = @truncate(l_bytes);
    if (bytes <= 0) return throwFmt(ctx, "ValueError", "mhash_keygen_s2k(): Argument #4 ($length) must be a greater than 0", .{});
    var padded_salt: [8]u8 = @splat(0);
    const salt_len = @min(salt.len, 8);
    @memcpy(padded_salt[0..salt_len], salt[0..salt_len]);
    const entry = mhashEntry(algorithm) orelse return NativeResult.scalar(.{ .bool = false });
    const ops = algos.fetch(entry[1]) orelse return NativeResult.scalar(.{ .bool = false });
    const nbytes: usize = @intCast(bytes);
    const block_size = ops.digest_size;
    const times = nbytes / block_size + @intFromBool(nbytes % block_size != 0);
    const key = try ctx.allocator.alloc(u8, times * block_size);
    defer ctx.allocator.free(key);
    var scratch: Scratch = undefined;
    const context = ctxPtr(&scratch, ops);
    var digest: [algos.max_digest_size]u8 = undefined;
    for (0..times) |i| {
        try ops.init(context, .{});
        for (0..i) |_| ops.update(context, &[_]u8{0});
        ops.update(context, &padded_salt);
        ops.update(context, password);
        ops.final(digest[0..block_size], context);
        @memcpy(key[i * block_size ..][0..block_size], digest[0..block_size]);
    }
    const result = try NativeResult.copyString(ctx.allocator, key[0..nbytes]);
    std.crypto.secureZero(u8, key);
    return result;
}

// ---------------------------------------------------------------------------
// registration

pub fn register(vm: *VM, a: std.mem.Allocator) !void {
    var def = ClassDef{ .name = class_name, .is_final = true, .native_cleanup = cleanupHashContext, .native_clone = cloneHashContext };
    try def.addMethod(a, .{ .name = "__construct", .arity = 0, .visibility = .private });
    try def.addMethod(a, .{ .name = "__serialize", .arity = 0 });
    try def.addMethod(a, .{ .name = "__unserialize", .arity = 1 });
    try def.addMethod(a, .{ .name = "__debugInfo", .arity = 0 });
    try vm.classes.put(a, class_name, def);
    try vm.native_fns.put(a, class_name ++ "::__construct", methodConstruct);
    try vm.native_fns.put(a, class_name ++ "::__serialize", methodSerialize);
    try vm.native_fns.put(a, class_name ++ "::__unserialize", methodUnserialize);
    try vm.native_fns.put(a, class_name ++ "::__debugInfo", methodDebugInfo);
    inline for (mhash_algos, 0..) |entry, i| {
        if (entry) |e| try vm.php_constants.put(a, "MHASH_" ++ e[0], .{ .int = i });
    }
}
