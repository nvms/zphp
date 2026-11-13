const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const std = @import("std");
const platform = @import("../platform.zig");
const crypt = @import("crypt.zig");
const filesystem = @import("filesystem.zig");
const php_types = @import("../pipeline/php_types.zig");

const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "crypt", native_crypt },
    .{ "password_hash", native_password_hash },
    .{ "password_verify", native_password_verify },
    .{ "password_needs_rehash", native_password_needs_rehash },
    .{ "password_get_info", native_password_get_info },
    .{ "password_algos", native_password_algos },
    .{ "random_bytes", native_random_bytes },
    .{ "random_int", native_random_int },
};

fn throwMsg(ctx: *NativeContext, class: []const u8, comptime fmt: []const u8, args: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException(class, msg);
    return error.RuntimeError;
}

// PHP_FUNCTION(crypt): the salt is cut to CRYPT_SALT_LENGTH (123) bytes
fn native_crypt(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(Value{ .bool = false });
    const password = args[0].string.bytes();
    const salt_in = args[1].string.bytes();
    const salt = salt_in[0..@min(salt_in.len, crypt.max_salt_len)];
    if (try crypt.phpCrypt(ctx.allocator, password, salt)) |hash| {
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, hash));
    }
    const c = std.mem.sliceTo(salt, 0);
    if (c.len >= 2 and c[0] == '*' and c[1] == '0') return NativeResult.literal("*1");
    return NativeResult.literal("*0");
}

// ext/standard/password.c: the registered algorithms, keyed by the
// identifier between a hash's first two '$'
const Algo = enum {
    bcrypt,
    argon2i,
    argon2id,

    fn ident(self: Algo) []const u8 {
        return switch (self) {
            .bcrypt => "2y",
            .argon2i => "argon2i",
            .argon2id => "argon2id",
        };
    }

    fn name(self: Algo) []const u8 {
        return switch (self) {
            .bcrypt => "bcrypt",
            .argon2i => "argon2i",
            .argon2id => "argon2id",
        };
    }

    fn find(id: []const u8) ?Algo {
        if (std.mem.eql(u8, id, "2y")) return .bcrypt;
        if (std.mem.eql(u8, id, "argon2i")) return .argon2i;
        if (std.mem.eql(u8, id, "argon2id")) return .argon2id;
        return null;
    }

    // php_password_bcrypt_valid; the argon2 algorithms have no check
    fn valid(self: Algo, hash: []const u8) bool {
        return switch (self) {
            .bcrypt => hash.len == 60 and hash[0] == '$' and hash[1] == '2' and hash[2] == 'y',
            else => true,
        };
    }
};

const bcrypt_default_cost = 12;
const argon2_default_memory = 64 << 10;
const argon2_default_time = 4;
const argon2_default_threads = 1;

// php_password_algo_extract_ident
fn extractIdent(hash: []const u8) ?[]const u8 {
    if (hash.len < 3) return null;
    const rest = std.mem.sliceTo(hash[1..], 0);
    const end = std.mem.indexOfScalar(u8, rest, '$') orelse return null;
    return rest[0..end];
}

// php_password_algo_identify_ex
fn identify(hash: []const u8, default: ?Algo) ?Algo {
    const id = extractIdent(hash) orelse return default;
    const algo = Algo.find(id) orelse return default;
    return if (algo.valid(hash)) algo else default;
}

// Z_PARAM_STR_OR_LONG_OR_NULL for $algo, then php_password_algo_find_zval:
// null when no algorithm has that name or number
fn algoArg(ctx: *NativeContext, func: []const u8, args: []const Value) RuntimeError!?Algo {
    var v: Value = if (args.len >= 2) args[1] else .null;
    switch (v) {
        .null, .undef, .int, .string => {},
        else => {
            const coerced = if (ctx.vm.topFrameStrict()) null else try ctx.vm.weakScalarHint(php_types.LONG | php_types.STRING, v);
            if (ctx.vm.pending_exception != null) return error.RuntimeError;
            v = coerced orelse return throwMsg(ctx, "TypeError", "{s}(): Argument #2 ($algo) must be of type string|int|null, {s} given", .{ func, v.typeName() });
        },
    }
    return switch (v) {
        .int => |n| switch (n) {
            0, 1 => .bcrypt,
            2 => .argon2i,
            3 => .argon2id,
            else => null,
        },
        .string => |s| Algo.find(s.bytes()),
        else => .bcrypt,
    };
}

fn optionsArg(args: []const Value) ?*PhpArray {
    return if (args.len >= 3 and args[2] == .array) args[2].array else null;
}

fn option(options: ?*PhpArray, key: []const u8) ?Value {
    const o = options orelse return null;
    if (!o.contains(.{ .string = Value.String.borrowed(key) })) return null;
    return o.get(.{ .string = Value.String.borrowed(key) });
}

// php_password_make_salt: `length` characters of base64 over random bytes,
// '+' written as '.'
fn makeSalt(out: []u8) void {
    var raw: [32]u8 = undefined;
    const raw_len = out.len * 3 / 4 + 1;
    platform.random.bytes(raw[0..raw_len]);
    var enc: [48]u8 = undefined;
    const b64 = std.base64.standard.Encoder.encode(&enc, raw[0..raw_len]);
    for (out, 0..) |*c, i| c.* = if (b64[i] == '+') '.' else b64[i];
}

fn saltOptionWarning(ctx: *NativeContext, options: ?*PhpArray) RuntimeError!void {
    if (option(options, "salt") != null) {
        try filesystem.warnDocref(ctx, "The \"salt\" option has been ignored, since providing a custom salt is no longer supported", .{});
    }
}

fn bcryptHash(ctx: *NativeContext, password: []const u8, options: ?*PhpArray) RuntimeError![]u8 {
    if (std.mem.indexOfScalar(u8, password, 0) != null) return throwMsg(ctx, "ValueError", "Bcrypt password must not contain null character", .{});
    var cost: i64 = bcrypt_default_cost;
    if (option(options, "cost")) |c| cost = c.toInt();
    if (cost < 4 or cost > 31) return throwMsg(ctx, "ValueError", "Invalid bcrypt cost parameter specified: {d}", .{cost});
    try saltOptionWarning(ctx, options);
    var setting: [29]u8 = undefined;
    _ = std.fmt.bufPrint(&setting, "$2y${d:0>2}$", .{@as(u64, @intCast(cost))}) catch unreachable;
    makeSalt(setting[7..29]);
    const hash = (try crypt.phpCrypt(ctx.allocator, password, &setting)) orelse
        return throwMsg(ctx, "Error", "Password hashing failed for unknown reason", .{});
    if (hash.len < 13) {
        ctx.allocator.free(hash);
        return throwMsg(ctx, "Error", "Password hashing failed for unknown reason", .{});
    }
    return hash;
}

// sscanf(p, "%ld"): leading space, a sign and digits; null when no digits
fn scanLong(s: []const u8, pos: *usize) ?i64 {
    var i = pos.*;
    while (i < s.len and std.ascii.isWhitespace(s[i])) i += 1;
    var neg = false;
    if (i < s.len and (s[i] == '+' or s[i] == '-')) {
        neg = s[i] == '-';
        i += 1;
    }
    const start = i;
    var v: i64 = 0;
    while (i < s.len and std.ascii.isDigit(s[i])) : (i += 1) {
        v = std.math.mul(i64, v, 10) catch std.math.maxInt(i64);
        v = std.math.add(i64, v, s[i] - '0') catch std.math.maxInt(i64);
    }
    if (i == start) return null;
    pos.* = i;
    return if (neg) -%v else v;
}

// sscanf(hash, "$2y$%ld$", &cost)
fn bcryptCost(hash: []const u8) i64 {
    if (!std.mem.startsWith(u8, hash, "$2y$")) return bcrypt_default_cost;
    var pos: usize = 4;
    return scanLong(hash, &pos) orelse bcrypt_default_cost;
}

const Argon2Params = struct { v: i64, m: i64, t: i64, p: i64 };

// extract_argon2_parameters: sscanf "v=%ld$m=%ld,t=%ld,p=%ld" after the
// prefix, keeping what it couldn't read
fn argon2Params(hash: []const u8, defaults: Argon2Params) Argon2Params {
    var r = defaults;
    if (hash.len < "$argon2id$".len + 1) return r;
    var pos: usize = if (std.mem.startsWith(u8, hash, "$argon2i$"))
        "$argon2i$".len
    else if (std.mem.startsWith(u8, hash, "$argon2id$"))
        "$argon2id$".len
    else
        return r;
    const fields = [_]struct { lit: []const u8, dst: *i64 }{
        .{ .lit = "v=", .dst = &r.v },
        .{ .lit = "$m=", .dst = &r.m },
        .{ .lit = ",t=", .dst = &r.t },
        .{ .lit = ",p=", .dst = &r.p },
    };
    for (fields) |f| {
        if (!std.mem.startsWith(u8, hash[pos..], f.lit)) return r;
        pos += f.lit.len;
        f.dst.* = scanLong(hash, &pos) orelse return r;
    }
    return r;
}

const argon2 = std.crypto.pwhash.argon2;

fn argon2Hash(ctx: *NativeContext, password: []const u8, options: ?*PhpArray, algo: Algo) RuntimeError![]u8 {
    // size_t comparisons in php: a negative value is a huge one
    var memory: u64 = argon2_default_memory;
    if (option(options, "memory_cost")) |v| memory = @bitCast(v.toInt());
    if (memory > 0xFFFFFFFF or memory < 8) return throwMsg(ctx, "ValueError", "Memory cost is outside of allowed memory range", .{});
    var time: u64 = argon2_default_time;
    if (option(options, "time_cost")) |v| time = @bitCast(v.toInt());
    if (time > 0xFFFFFFFF or time < 1) return throwMsg(ctx, "ValueError", "Time cost is outside of allowed time range", .{});
    var threads: u64 = argon2_default_threads;
    if (option(options, "threads")) |v| threads = @bitCast(v.toInt());
    if (threads > 0xFFFFFF or threads == 0) return throwMsg(ctx, "ValueError", "Invalid number of threads", .{});
    try saltOptionWarning(ctx, options);
    if (memory < 8 * threads) return throwMsg(ctx, "ValueError", "Memory cost is too small", .{});

    var salt: [16]u8 = undefined;
    makeSalt(&salt);
    var out: [32]u8 = undefined;
    const mode: argon2.Mode = if (algo == .argon2i) .argon2i else .argon2id;
    argon2.kdf(ctx.allocator, &out, password, &salt, .{
        .t = @intCast(time),
        .m = @intCast(memory),
        .p = @intCast(threads),
    }, mode, platform.io) catch |err| switch (err) {
        error.OutOfMemory => return throwMsg(ctx, "ValueError", "Memory allocation error", .{}),
        else => return throwMsg(ctx, "ValueError", "Password hashing failed for unknown reason", .{}),
    };
    const enc = std.base64.standard_no_pad.Encoder;
    var salt_b64: [24]u8 = undefined;
    var out_b64: [44]u8 = undefined;
    return std.fmt.allocPrint(ctx.allocator, "${s}$v=19$m={d},t={d},p={d}${s}${s}", .{
        algo.ident(),
        memory,
        time,
        threads,
        enc.encode(&salt_b64, &salt),
        enc.encode(&out_b64, &out),
    });
}

// argon2_verify: decode_string's format, then the same hash again
fn argon2Verify(ctx: *NativeContext, password: []const u8, hash_bytes: []const u8, algo: Algo) bool {
    const hash = std.mem.sliceTo(hash_bytes, 0);
    const prefix: []const u8 = if (algo == .argon2i) "$argon2i" else "$argon2id";
    if (!std.mem.startsWith(u8, hash, prefix)) return false;
    var pos: usize = prefix.len;
    var version: i64 = 0x10;
    if (std.mem.startsWith(u8, hash[pos..], "$v=")) {
        pos += 3;
        version = scanU32(hash, &pos) orelse return false;
    }
    var vals: [3]i64 = undefined;
    for ([_][]const u8{ "$m=", ",t=", ",p=" }, 0..) |lit, i| {
        if (!std.mem.startsWith(u8, hash[pos..], lit)) return false;
        pos += lit.len;
        vals[i] = scanU32(hash, &pos) orelse return false;
    }
    if (version != 0x13) return false;
    if (pos >= hash.len or hash[pos] != '$') return false;
    pos += 1;
    const salt_end = std.mem.indexOfScalarPos(u8, hash, pos, '$') orelse return false;
    const dec = std.base64.standard_no_pad.Decoder;
    var salt: [256]u8 = undefined;
    const salt_len = dec.calcSizeForSlice(hash[pos..salt_end]) catch return false;
    if (salt_len > salt.len) return false;
    dec.decode(salt[0..salt_len], hash[pos..salt_end]) catch return false;
    const want_b64 = hash[salt_end + 1 ..];
    var want: [256]u8 = undefined;
    const want_len = dec.calcSizeForSlice(want_b64) catch return false;
    if (want_len > want.len or want_len < 4 or salt_len < 8) return false;
    dec.decode(want[0..want_len], want_b64) catch return false;
    const m = vals[0];
    const t = vals[1];
    const p = vals[2];
    if (t < 1 or p < 1 or p > 0xFFFFFF or m < 8 * p) return false;
    const got = ctx.allocator.alloc(u8, want_len) catch return false;
    defer ctx.allocator.free(got);
    argon2.kdf(ctx.allocator, got, password, salt[0..salt_len], .{
        .t = @intCast(t),
        .m = @intCast(m),
        .p = @intCast(p),
    }, if (algo == .argon2i) .argon2i else .argon2id, platform.io) catch return false;
    return constantTimeEql(got, want[0..want_len]);
}

// php_safe_bcmp: every byte is compared
fn constantTimeEql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var acc: u8 = 0;
    for (a, b) |x, y| acc |= x ^ y;
    return acc == 0;
}

// libargon2's DECIMAL_U32: digits only, no sign, no leading zero, fits u32
fn scanU32(s: []const u8, pos: *usize) ?i64 {
    var i = pos.*;
    const start = i;
    var v: u64 = 0;
    while (i < s.len and std.ascii.isDigit(s[i])) : (i += 1) {
        v = v * 10 + (s[i] - '0');
        if (v > 0xFFFFFFFF) return null;
    }
    if (i == start or (s[start] == '0' and i - start > 1)) return null;
    pos.* = i;
    return @intCast(v);
}

fn native_password_hash(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(Value{ .bool = false });
    const algo = (try algoArg(ctx, "password_hash", args)) orelse
        return throwMsg(ctx, "ValueError", "password_hash(): Argument #2 ($algo) must be a valid password hashing algorithm", .{});
    const password = args[0].string.bytes();
    const options = optionsArg(args);
    const hash = switch (algo) {
        .bcrypt => try bcryptHash(ctx, password, options),
        .argon2i, .argon2id => try argon2Hash(ctx, password, options, algo),
    };
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, hash));
}

fn native_password_verify(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(Value{ .bool = false });
    const password = args[0].string.bytes();
    const hash = args[1].string.bytes();
    const ok = switch (identify(hash, .bcrypt).?) {
        // php_password_bcrypt_verify: whatever crypt() makes of the hash
        // as a salt must give back the hash
        .bcrypt => blk: {
            const ret = (try crypt.phpCrypt(ctx.allocator, password, hash)) orelse break :blk false;
            defer ctx.allocator.free(ret);
            if (hash.len < 13 or ret.len != hash.len) break :blk false;
            break :blk constantTimeEql(ret, hash);
        },
        .argon2i, .argon2id => |a| argon2Verify(ctx, password, hash, a),
    };
    return NativeResult.scalar(Value{ .bool = ok });
}

fn native_password_get_info(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const info = try ctx.vm.allocArray();
    const options = try ctx.vm.allocArray();
    const hash: []const u8 = if (args.len >= 1 and args[0] == .string) args[0].string.bytes() else "";
    const id = extractIdent(hash);
    const algo: ?Algo = if (id) |i| Algo.find(i) else null;
    if (algo == null or !algo.?.valid(hash)) {
        try info.set(ctx.allocator, .{ .string = Value.String.borrowed("algo") }, .null);
        try info.set(ctx.allocator, .{ .string = Value.String.borrowed("algoName") }, .{ .string = Value.String.borrowed("unknown") });
        try info.set(ctx.allocator, .{ .string = Value.String.borrowed("options") }, .{ .array = options });
        return NativeResult.borrowed(.{ .array = info });
    }
    const algo_name = try Value.String.create(ctx.allocator, id.?);
    defer algo_name.release();
    try info.set(ctx.allocator, .{ .string = Value.String.borrowed("algo") }, .{ .string = algo_name });
    try info.set(ctx.allocator, .{ .string = Value.String.borrowed("algoName") }, .{ .string = Value.String.borrowed(algo.?.name()) });
    switch (algo.?) {
        .bcrypt => try options.set(ctx.allocator, .{ .string = Value.String.borrowed("cost") }, .{ .int = bcryptCost(hash) }),
        .argon2i, .argon2id => {
            const p = argon2Params(hash, .{ .v = 0, .m = argon2_default_memory, .t = argon2_default_time, .p = argon2_default_threads });
            try options.set(ctx.allocator, .{ .string = Value.String.borrowed("memory_cost") }, .{ .int = p.m });
            try options.set(ctx.allocator, .{ .string = Value.String.borrowed("time_cost") }, .{ .int = p.t });
            try options.set(ctx.allocator, .{ .string = Value.String.borrowed("threads") }, .{ .int = p.p });
        },
    }
    try info.set(ctx.allocator, .{ .string = Value.String.borrowed("options") }, .{ .array = options });
    return NativeResult.borrowed(.{ .array = info });
}

fn native_password_algos(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.vm.allocArray();
    for ([_]Algo{ .bcrypt, .argon2i, .argon2id }) |a| try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(a.ident()) });
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_password_needs_rehash(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(Value{ .bool = true });
    const new_algo = (try algoArg(ctx, "password_needs_rehash", args)) orelse return NativeResult.scalar(Value{ .bool = false });
    const hash = args[0].string.bytes();
    const old_algo = identify(hash, null) orelse return NativeResult.scalar(Value{ .bool = true });
    if (old_algo != new_algo) return NativeResult.scalar(Value{ .bool = true });
    const options = optionsArg(args);
    const rehash = switch (old_algo) {
        .bcrypt => blk: {
            var new_cost: i64 = bcrypt_default_cost;
            if (option(options, "cost")) |c| new_cost = c.toInt();
            break :blk bcryptCost(hash) != new_cost;
        },
        .argon2i, .argon2id => blk: {
            var want = Argon2Params{ .v = 0, .m = argon2_default_memory, .t = argon2_default_time, .p = argon2_default_threads };
            if (option(options, "memory_cost")) |v| want.m = v.toInt();
            if (option(options, "time_cost")) |v| want.t = v.toInt();
            if (option(options, "threads")) |v| want.p = v.toInt();
            const have = argon2Params(hash, .{ .v = 0, .m = 0, .t = 0, .p = 0 });
            break :blk want.t != have.t or want.m != have.m or want.p != have.p;
        },
    };
    return NativeResult.scalar(Value{ .bool = rehash });
}

fn native_random_bytes(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(Value{ .bool = false });
    const length = Value.toInt(args[0]);
    if (length < 1) {
        try ctx.vm.setPendingException("ValueError", "random_bytes(): Argument #1 ($length) must be greater than 0");
        return error.RuntimeError;
    }
    if (length > 1048576) return NativeResult.scalar(Value{ .bool = false });

    const len: usize = @intCast(length);
    const buf = try ctx.allocator.alloc(u8, len);
    platform.random.bytes(buf);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, buf));
}

fn native_random_int(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.scalar(Value{ .bool = false });
    const min = Value.toInt(args[0]);
    const max = Value.toInt(args[1]);
    if (min > max) {
        try ctx.vm.setPendingException("ValueError", "random_int(): Argument #1 ($min) must be less than or equal to argument #2 ($max)");
        return error.RuntimeError;
    }
    if (min == max) return NativeResult.scalar(Value{ .int = min });

    // span as unsigned to avoid overflow on PHP_INT_MIN .. PHP_INT_MAX
    const umin: u64 = @bitCast(min);
    const umax: u64 = @bitCast(max);
    const range: u64 = umax -% umin;
    const random = if (range == std.math.maxInt(u64))
        platform.random.int(u64)
    else
        platform.random.intRangeAtMost(u64, 0, range);
    const result_u: u64 = umin +% random;
    return NativeResult.scalar(Value{ .int = @bitCast(result_u) });
}
