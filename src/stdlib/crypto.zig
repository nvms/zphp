const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const std = @import("std");
const platform = @import("../platform.zig");

const Value = @import("../runtime/value.zig").Value;
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

// PHP's crypt() with bcrypt salt: salt format is "$2y$NN$..." or "$2a$NN$..."
// Generates a bcrypt hash using the provided salt's cost. For non-bcrypt
// salts (DES, MD5, SHA-256, SHA-512) we currently fall back to bcrypt with
// cost 10, which is incorrect but preserves the calling convention.
fn native_crypt(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(Value{ .bool = false });
    const password = args[0].string.bytes();
    const salt: []const u8 = if (args.len >= 2 and args[1] == .string) args[1].string.bytes() else "";

    // bcrypt salt: $2y$NN$22-char-salt[31-char-hash]. crypt() must be
    // deterministic on the input salt - strHash generates its own random
    // salt, so we decode the supplied salt bytes and feed bcrypt() directly
    if (salt.len >= 29 and salt[0] == '$' and salt[1] == '2' and (salt[2] == 'y' or salt[2] == 'a' or salt[2] == 'b') and salt[3] == '$' and salt[6] == '$') {
        var rounds_log: u6 = 10;
        const cost = std.fmt.parseInt(u8, salt[4..6], 10) catch 10;
        if (cost >= 4 and cost <= 31) rounds_log = @intCast(cost);

        var salt_bytes: [16]u8 = undefined;
        if (!bcryptB64Decode(&salt_bytes, salt[7..29])) return NativeResult.literal("*0");

        // PHP canonicalizes the salt encoding by re-encoding the 16 decoded
        // bytes, which forces the trailing unused bits in the last base64
        // character to 0 ($..uv -> $..uu). preserve that behavior so verify
        // round-trips
        var salt_b64_buf: [22]u8 = undefined;
        bcryptB64Encode(&salt_b64_buf, &salt_bytes);

        const hash = std.crypto.pwhash.bcrypt.bcrypt(password, &salt_bytes, .{
            .rounds_log = rounds_log,
            .silently_truncate_password = true,
        });

        var hash_b64_buf: [31]u8 = undefined;
        bcryptB64Encode(&hash_b64_buf, &hash);

        var out_buf: [60]u8 = undefined;
        const out = std.fmt.bufPrint(&out_buf, "$2{c}${d}{d}${s}{s}", .{
            salt[2],
            rounds_log / 10,
            rounds_log % 10,
            salt_b64_buf,
            hash_b64_buf,
        }) catch return NativeResult.literal("*0");
        return NativeResult.copyString(ctx.allocator, out);
    }

    // PHP returns a special "*0" or "*1" failure indicator on bad salt
    return NativeResult.literal("*0");
}

const bcrypt_alphabet = "./ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

fn bcryptB64DecodeChar(c: u8) ?u6 {
    for (bcrypt_alphabet, 0..) |a, i| if (a == c) return @intCast(i);
    return null;
}

fn bcryptB64Decode(out: []u8, b64: []const u8) bool {
    // bcrypt's variant of base64: 22 chars → 16 bytes (drops the trailing 2 bits)
    var ob: usize = 0;
    var i: usize = 0;
    while (i + 4 <= b64.len and ob < out.len) {
        const c0 = bcryptB64DecodeChar(b64[i + 0]) orelse return false;
        const c1 = bcryptB64DecodeChar(b64[i + 1]) orelse return false;
        const c2 = bcryptB64DecodeChar(b64[i + 2]) orelse return false;
        const c3 = bcryptB64DecodeChar(b64[i + 3]) orelse return false;
        out[ob + 0] = (@as(u8, c0) << 2) | (@as(u8, c1) >> 4);
        if (ob + 1 < out.len) out[ob + 1] = ((@as(u8, c1) & 0x0f) << 4) | (@as(u8, c2) >> 2);
        if (ob + 2 < out.len) out[ob + 2] = ((@as(u8, c2) & 0x03) << 6) | @as(u8, c3);
        ob += 3;
        i += 4;
    }
    // handle the trailing partial group (b64 len 22 -> i=20, 2 chars left -> 1 byte)
    if (i + 2 <= b64.len and ob < out.len) {
        const c0 = bcryptB64DecodeChar(b64[i + 0]) orelse return false;
        const c1 = bcryptB64DecodeChar(b64[i + 1]) orelse return false;
        out[ob] = (@as(u8, c0) << 2) | (@as(u8, c1) >> 4);
    }
    return true;
}

fn bcryptB64Encode(out: []u8, data: []const u8) void {
    var oi: usize = 0;
    var i: usize = 0;
    while (i < data.len) {
        const b0 = data[i];
        const b1: u8 = if (i + 1 < data.len) data[i + 1] else 0;
        const b2: u8 = if (i + 2 < data.len) data[i + 2] else 0;
        if (oi < out.len) out[oi] = bcrypt_alphabet[b0 >> 2];
        oi += 1;
        if (oi < out.len) out[oi] = bcrypt_alphabet[((b0 & 0x03) << 4) | (b1 >> 4)];
        oi += 1;
        if (i + 1 < data.len and oi < out.len) {
            out[oi] = bcrypt_alphabet[((b1 & 0x0f) << 2) | (b2 >> 6)];
            oi += 1;
        }
        if (i + 2 < data.len and oi < out.len) {
            out[oi] = bcrypt_alphabet[b2 & 0x3f];
            oi += 1;
        }
        i += 3;
    }
}

fn native_password_hash(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(Value{ .bool = false });
    const password = args[0].string.bytes();

    // dispatch on the algo arg: bcrypt (default), argon2i, or argon2id.
    // argon2 family is routed to sodium_crypto_pwhash_str which produces the
    // PHP-compatible $argon2id$... encoding. without this, PASSWORD_ARGON2*
    // silently fell back to bcrypt
    // php_password_algo_find_zval: null and 0 are the default, 1-3 the
    // legacy numbers of bcrypt, argon2i and argon2id
    const algo: []const u8 = switch (if (args.len >= 2) args[1] else Value.null) {
        .null, .undef => "2y",
        .int => |n| switch (n) {
            0, 1 => "2y",
            2 => "argon2i",
            3 => "argon2id",
            else => "",
        },
        .string => |s| s.bytes(),
        else => "",
    };
    if (!std.mem.eql(u8, algo, "2y") and !std.mem.eql(u8, algo, "argon2i") and !std.mem.eql(u8, algo, "argon2id")) {
        try ctx.vm.setPendingException("ValueError", "password_hash(): Argument #2 ($algo) must be a valid password hashing algorithm");
        return error.RuntimeError;
    }
    if (std.mem.eql(u8, algo, "argon2i") or std.mem.eql(u8, algo, "argon2id")) {
        // default-ish "interactive" cost; PHP's default is memory_cost=65536, time_cost=4
        var ops: i64 = 4;
        var mem_kb: i64 = 65536;
        if (args.len >= 3 and args[2] == .array) {
            const opts = args[2].array;
            const t = opts.get(.{ .string = Value.String.borrowed("time_cost") });
            if (t == .int) ops = t.int;
            const m = opts.get(.{ .string = Value.String.borrowed("memory_cost") });
            if (m == .int) mem_kb = m.int;
        }
        const r = ctx.vm.callByName("sodium_crypto_pwhash_str", &.{
            .{ .string = args[0].string },
            .{ .int = ops },
            .{ .int = mem_kb * 1024 },
        }) catch return NativeResult.scalar(Value{ .bool = false });
        return NativeResult.share(r);
    }

    // PHP 7.4+ default cost is 12, was 10 in older versions
    var rounds_log: u6 = 12;
    if (args.len >= 3 and args[2] == .array) {
        const opts = args[2].array;
        const cost_val = opts.get(.{ .string = Value.String.borrowed("cost") });
        if (cost_val == .int and cost_val.int >= 4 and cost_val.int <= 31) {
            rounds_log = @intCast(cost_val.int);
        }
    }

    var buf: [60]u8 = undefined;
    const hash = std.crypto.pwhash.bcrypt.strHash(password, .{
        .params = .{ .rounds_log = rounds_log, .silently_truncate_password = true },
        .encoding = .crypt,
    }, &buf, platform.io) catch return NativeResult.scalar(Value{ .bool = false });

    // PHP uses the $2y$ prefix variant; std.crypto produces $2b$. Both are
    // verifiable by any compliant bcrypt impl, but cross-runtime hash exchange
    // (e.g. Laravel sessions) expects the $2y$ form.
    const owned = try Value.String.create(ctx.allocator, hash);
    const out = owned.bytes();
    if (out.len >= 4 and out[0] == '$' and out[1] == '2' and out[2] == 'b' and out[3] == '$') {
        @as([*]u8, @ptrCast(@constCast(out.ptr)))[2] = 'y';
    }
    return NativeResult.takeString(owned);
}

fn native_password_verify(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(Value{ .bool = false });
    const password = args[0].string.bytes();
    const hash = args[1].string.bytes();

    // argon2 family: delegate to libsodium
    if (std.mem.startsWith(u8, hash, "$argon2")) {
        const r = ctx.vm.callByName("sodium_crypto_pwhash_str_verify", &.{
            .{ .string = args[1].string },
            .{ .string = args[0].string },
        }) catch return NativeResult.scalar(Value{ .bool = false });
        return NativeResult.share(r);
    }

    // std.crypto.pwhash.bcrypt only knows the $2b$ variant; PHP-generated and
    // legacy hashes use $2y$ and $2a$. Normalize before verification.
    var normalized: []const u8 = hash;
    if (hash.len >= 4 and hash[0] == '$' and hash[1] == '2' and (hash[2] == 'y' or hash[2] == 'a') and hash[3] == '$') {
        const dup = try ctx.allocator.dupe(u8, hash);
        defer ctx.allocator.free(dup);
        dup[2] = 'b';
        normalized = dup;
        std.crypto.pwhash.bcrypt.strVerify(normalized, password, .{
            .silently_truncate_password = true,
        }) catch return NativeResult.scalar(Value{ .bool = false });
        return NativeResult.scalar(Value{ .bool = true });
    }

    std.crypto.pwhash.bcrypt.strVerify(hash, password, .{
        .silently_truncate_password = true,
    }) catch return NativeResult.scalar(Value{ .bool = false });

    return NativeResult.scalar(Value{ .bool = true });
}

fn native_password_get_info(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const info = try ctx.vm.allocArray();

    if (args.len == 0 or args[0] != .string) {
        try info.set(ctx.allocator, .{ .string = Value.String.borrowed("algo") }, .null);
        try info.set(ctx.allocator, .{ .string = Value.String.borrowed("algoName") }, .{ .string = Value.String.borrowed("unknown") });
        const empty = try ctx.vm.allocArray();
        try info.set(ctx.allocator, .{ .string = Value.String.borrowed("options") }, .{ .array = empty });
        return NativeResult.borrowed(.{ .array = info });
    }

    const hash = args[0].string.bytes();
    var algo: Value = .null;
    var algo_name: []const u8 = "unknown";
    const options = try ctx.vm.allocArray();

    if (hash.len >= 7 and hash[0] == '$' and hash[1] == '2' and (hash[2] == 'y' or hash[2] == 'b' or hash[2] == 'a')) {
        algo = .{ .string = Value.String.borrowed("2y") };
        algo_name = "bcrypt";
        // parse cost: $2y$XX$
        const cost_start: usize = 4;
        if (hash.len >= 6 and hash[cost_start - 1] == '$') {
            const dollar_after = std.mem.indexOfScalarPos(u8, hash, cost_start, '$') orelse hash.len;
            if (std.fmt.parseInt(i64, hash[cost_start..dollar_after], 10)) |cost| {
                try options.set(ctx.allocator, .{ .string = Value.String.borrowed("cost") }, .{ .int = cost });
            } else |_| {}
        }
    }

    try info.set(ctx.allocator, .{ .string = Value.String.borrowed("algo") }, algo);
    try info.set(ctx.allocator, .{ .string = Value.String.borrowed("algoName") }, .{ .string = Value.String.borrowed(algo_name) });
    try info.set(ctx.allocator, .{ .string = Value.String.borrowed("options") }, .{ .array = options });
    return NativeResult.borrowed(.{ .array = info });
}

fn native_password_algos(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.vm.allocArray();
    try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("2y") });
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_password_needs_rehash(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string) return NativeResult.scalar(Value{ .bool = true });
    const hash = args[0].string.bytes();

    // PHP's default cost was 10 for years; 7.4+ raised it to 12
    var target_cost: u6 = 12;
    if (args.len >= 3 and args[2] == .array) {
        const opts = args[2].array;
        const cost_val = opts.get(.{ .string = Value.String.borrowed("cost") });
        if (cost_val == .int and cost_val.int >= 4 and cost_val.int <= 31) {
            target_cost = @intCast(cost_val.int);
        }
    }

    // parse cost from $2y$XX$ or $2b$XX$ format
    if (hash.len < 7 or hash[0] != '$' or hash[1] != '2' or hash[3] != '$') return NativeResult.scalar(Value{ .bool = true });
    const cost = std.fmt.parseInt(u6, hash[4..6], 10) catch return NativeResult.scalar(Value{ .bool = true });

    return NativeResult.scalar(Value{ .bool = cost != target_cost });
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
