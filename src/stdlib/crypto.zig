const std = @import("std");
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
    .{ "hash", native_hash },
    .{ "hash_hmac", native_hash_hmac },
    .{ "hash_algos", native_hash_algos },
    .{ "hash_equals", native_hash_equals },
    .{ "hash_file", native_hash_file },
    .{ "hash_init", native_hash_init },
    .{ "hash_update", native_hash_update },
    .{ "hash_update_file", native_hash_update_file },
    .{ "hash_final", native_hash_final },
    .{ "hash_copy", native_hash_copy },
    .{ "hash_pbkdf2", native_hash_pbkdf2 },
};

// PHP's crypt() with bcrypt salt: salt format is "$2y$NN$..." or "$2a$NN$..."
// Generates a bcrypt hash using the provided salt's cost. For non-bcrypt
// salts (DES, MD5, SHA-256, SHA-512) we currently fall back to bcrypt with
// cost 10, which is incorrect but preserves the calling convention.
fn native_crypt(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return Value{ .bool = false };
    const password = args[0].string;
    const salt: []const u8 = if (args.len >= 2 and args[1] == .string) args[1].string else "";

    // bcrypt salt: $2y$NN$22-char-salt or $2a$/$2b$
    if (salt.len >= 7 and salt[0] == '$' and salt[1] == '2' and (salt[2] == 'y' or salt[2] == 'a' or salt[2] == 'b') and salt[3] == '$') {
        var rounds_log: u6 = 10;
        if (salt.len >= 6 and salt[6] == '$') {
            const cost = std.fmt.parseInt(u8, salt[4..6], 10) catch 10;
            if (cost >= 4 and cost <= 31) rounds_log = @intCast(cost);
        }
        var buf: [60]u8 = undefined;
        const hash = std.crypto.pwhash.bcrypt.strHash(password, .{
            .params = .{ .rounds_log = rounds_log, .silently_truncate_password = true },
            .encoding = .crypt,
        }, &buf) catch return Value{ .bool = false };
        const out = try ctx.createString(hash);
        // preserve the variant prefix from the salt ($2y$ vs $2a$ vs $2b$)
        if (out.len >= 4 and out[0] == '$' and out[1] == '2' and out[3] == '$') {
            @as([*]u8, @ptrCast(@constCast(out.ptr)))[2] = salt[2];
        }
        return .{ .string = out };
    }

    // PHP returns a special "*0" or "*1" failure indicator on bad salt
    return .{ .string = "*0" };
}

fn native_password_hash(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return Value{ .bool = false };
    const password = args[0].string;

    // PHP 7.4+ default cost is 12, was 10 in older versions
    var rounds_log: u6 = 12;
    if (args.len >= 3 and args[2] == .array) {
        const opts = args[2].array;
        const cost_val = opts.get(.{ .string = "cost" });
        if (cost_val == .int and cost_val.int >= 4 and cost_val.int <= 31) {
            rounds_log = @intCast(cost_val.int);
        }
    }

    var buf: [60]u8 = undefined;
    const hash = std.crypto.pwhash.bcrypt.strHash(password, .{
        .params = .{ .rounds_log = rounds_log, .silently_truncate_password = true },
        .encoding = .crypt,
    }, &buf) catch return Value{ .bool = false };

    // PHP uses the $2y$ prefix variant; std.crypto produces $2b$. Both are
    // verifiable by any compliant bcrypt impl, but cross-runtime hash exchange
    // (e.g. Laravel sessions) expects the $2y$ form.
    const out = try ctx.createString(hash);
    if (out.len >= 4 and out[0] == '$' and out[1] == '2' and out[2] == 'b' and out[3] == '$') {
        @as([*]u8, @ptrCast(@constCast(out.ptr)))[2] = 'y';
    }
    return .{ .string = out };
}

fn native_password_verify(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return Value{ .bool = false };
    const password = args[0].string;
    const hash = args[1].string;

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
        }) catch return Value{ .bool = false };
        return Value{ .bool = true };
    }

    std.crypto.pwhash.bcrypt.strVerify(hash, password, .{
        .silently_truncate_password = true,
    }) catch return Value{ .bool = false };

    return Value{ .bool = true };
}

fn native_password_get_info(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const PhpArray = @import("../runtime/value.zig").PhpArray;
    const info = try ctx.allocator.create(PhpArray);
    info.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, info);

    if (args.len == 0 or args[0] != .string) {
        try info.set(ctx.allocator, .{ .string = "algo" }, .null);
        try info.set(ctx.allocator, .{ .string = "algoName" }, .{ .string = "unknown" });
        const empty = try ctx.allocator.create(PhpArray);
        empty.* = .{};
        try ctx.vm.arrays.append(ctx.allocator, empty);
        try info.set(ctx.allocator, .{ .string = "options" }, .{ .array = empty });
        return .{ .array = info };
    }

    const hash = args[0].string;
    var algo: Value = .null;
    var algo_name: []const u8 = "unknown";
    const options = try ctx.allocator.create(PhpArray);
    options.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, options);

    if (hash.len >= 7 and hash[0] == '$' and hash[1] == '2' and (hash[2] == 'y' or hash[2] == 'b' or hash[2] == 'a')) {
        algo = .{ .string = try ctx.createString("2y") };
        algo_name = "bcrypt";
        // parse cost: $2y$XX$
        const cost_start: usize = 4;
        if (hash.len >= 6 and hash[cost_start - 1] == '$') {
            const dollar_after = std.mem.indexOfScalarPos(u8, hash, cost_start, '$') orelse hash.len;
            if (std.fmt.parseInt(i64, hash[cost_start..dollar_after], 10)) |cost| {
                try options.set(ctx.allocator, .{ .string = "cost" }, .{ .int = cost });
            } else |_| {}
        }
    }

    try info.set(ctx.allocator, .{ .string = "algo" }, algo);
    try info.set(ctx.allocator, .{ .string = "algoName" }, .{ .string = try ctx.createString(algo_name) });
    try info.set(ctx.allocator, .{ .string = "options" }, .{ .array = options });
    return .{ .array = info };
}

fn native_password_algos(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const PhpArray = @import("../runtime/value.zig").PhpArray;
    const arr = try ctx.allocator.create(PhpArray);
    arr.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, arr);
    try arr.append(ctx.allocator, .{ .string = "2y" });
    return .{ .array = arr };
}

fn native_password_needs_rehash(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string) return Value{ .bool = true };
    const hash = args[0].string;

    // PHP's default cost was 10 for years; 7.4+ raised it to 12
    var target_cost: u6 = 12;
    if (args.len >= 3 and args[2] == .array) {
        const opts = args[2].array;
        const cost_val = opts.get(.{ .string = "cost" });
        if (cost_val == .int and cost_val.int >= 4 and cost_val.int <= 31) {
            target_cost = @intCast(cost_val.int);
        }
    }

    // parse cost from $2y$XX$ or $2b$XX$ format
    if (hash.len < 7 or hash[0] != '$' or hash[1] != '2' or hash[3] != '$') return Value{ .bool = true };
    const cost = std.fmt.parseInt(u6, hash[4..6], 10) catch return Value{ .bool = true };

    return Value{ .bool = cost != target_cost };
}

fn native_random_bytes(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return Value{ .bool = false };
    const length = Value.toInt(args[0]);
    if (length < 1) {
        try ctx.vm.setPendingException("ValueError", "random_bytes(): Argument #1 ($length) must be greater than 0");
        return error.RuntimeError;
    }
    if (length > 1048576) return Value{ .bool = false };

    const len: usize = @intCast(length);
    const buf = try ctx.allocator.alloc(u8, len);
    std.crypto.random.bytes(buf);
    try ctx.strings.append(ctx.allocator, buf);
    return .{ .string = buf };
}

fn native_random_int(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return Value{ .bool = false };
    const min = Value.toInt(args[0]);
    const max = Value.toInt(args[1]);
    if (min > max) {
        try ctx.vm.setPendingException("ValueError", "random_int(): Argument #1 ($min) must be less than or equal to argument #2 ($max)");
        return error.RuntimeError;
    }
    if (min == max) return Value{ .int = min };

    // span as unsigned to avoid overflow on PHP_INT_MIN .. PHP_INT_MAX
    const umin: u64 = @bitCast(min);
    const umax: u64 = @bitCast(max);
    const range: u64 = umax -% umin;
    const random = if (range == std.math.maxInt(u64))
        std.crypto.random.int(u64)
    else
        std.crypto.random.intRangeAtMost(u64, 0, range);
    const result_u: u64 = umin +% random;
    return Value{ .int = @bitCast(result_u) };
}

const HashAlgo = enum {
    md5,
    sha1,
    sha256,
    sha384,
    sha512,
    sha3_224,
    sha3_256,
    sha3_384,
    sha3_512,
    crc32,
    crc32b,
    xxh32,
    xxh64,
    xxh3,
    xxh128,

    fn fromString(name: []const u8) ?HashAlgo {
        if (std.mem.eql(u8, name, "md5")) return .md5;
        if (std.mem.eql(u8, name, "sha1")) return .sha1;
        if (std.mem.eql(u8, name, "sha256")) return .sha256;
        if (std.mem.eql(u8, name, "sha384")) return .sha384;
        if (std.mem.eql(u8, name, "sha512")) return .sha512;
        if (std.mem.eql(u8, name, "sha3-224")) return .sha3_224;
        if (std.mem.eql(u8, name, "sha3-256")) return .sha3_256;
        if (std.mem.eql(u8, name, "sha3-384")) return .sha3_384;
        if (std.mem.eql(u8, name, "sha3-512")) return .sha3_512;
        if (std.mem.eql(u8, name, "crc32")) return .crc32;
        if (std.mem.eql(u8, name, "crc32b")) return .crc32b;
        if (std.mem.eql(u8, name, "xxh32")) return .xxh32;
        if (std.mem.eql(u8, name, "xxh64")) return .xxh64;
        if (std.mem.eql(u8, name, "xxh3")) return .xxh3;
        if (std.mem.eql(u8, name, "xxh128")) return .xxh128;
        return null;
    }

    fn digestLen(self: HashAlgo) usize {
        return switch (self) {
            .md5 => 16,
            .sha1 => 20,
            .sha256, .sha3_256 => 32,
            .sha384, .sha3_384 => 48,
            .sha512, .sha3_512 => 64,
            .sha3_224 => 28,
            .crc32, .crc32b, .xxh32 => 4,
            .xxh64, .xxh3 => 8,
            .xxh128 => 16,
        };
    }
};

fn computeHash(algo: HashAlgo, data: []const u8, out: []u8) void {
    switch (algo) {
        .md5 => std.crypto.hash.Md5.hash(data, out[0..16], .{}),
        .sha1 => std.crypto.hash.Sha1.hash(data, out[0..20], .{}),
        .sha256 => std.crypto.hash.sha2.Sha256.hash(data, out[0..32], .{}),
        .sha384 => std.crypto.hash.sha2.Sha384.hash(data, out[0..48], .{}),
        .sha512 => std.crypto.hash.sha2.Sha512.hash(data, out[0..64], .{}),
        .sha3_224 => std.crypto.hash.sha3.Sha3_224.hash(data, out[0..28], .{}),
        .sha3_256 => std.crypto.hash.sha3.Sha3_256.hash(data, out[0..32], .{}),
        .sha3_384 => std.crypto.hash.sha3.Sha3_384.hash(data, out[0..48], .{}),
        .sha3_512 => std.crypto.hash.sha3.Sha3_512.hash(data, out[0..64], .{}),
        .crc32 => {
            // PHP "crc32" uses CRC-32/BZIP2 polynomial with bytes in little-endian order
            const c = std.hash.crc.Crc32Bzip2.hash(data);
            out[0] = @intCast(c & 0xff);
            out[1] = @intCast((c >> 8) & 0xff);
            out[2] = @intCast((c >> 16) & 0xff);
            out[3] = @intCast((c >> 24) & 0xff);
        },
        .crc32b => {
            const c = std.hash.crc.Crc32IsoHdlc.hash(data);
            out[0] = @intCast((c >> 24) & 0xff);
            out[1] = @intCast((c >> 16) & 0xff);
            out[2] = @intCast((c >> 8) & 0xff);
            out[3] = @intCast(c & 0xff);
        },
        .xxh32 => {
            const c = std.hash.XxHash32.hash(0, data);
            out[0] = @intCast((c >> 24) & 0xff);
            out[1] = @intCast((c >> 16) & 0xff);
            out[2] = @intCast((c >> 8) & 0xff);
            out[3] = @intCast(c & 0xff);
        },
        .xxh64 => {
            const c = std.hash.XxHash64.hash(0, data);
            var i: usize = 0;
            while (i < 8) : (i += 1) out[i] = @intCast((c >> @intCast((7 - i) * 8)) & 0xff);
        },
        .xxh3 => {
            const c = std.hash.XxHash3.hash(0, data);
            var i: usize = 0;
            while (i < 8) : (i += 1) out[i] = @intCast((c >> @intCast((7 - i) * 8)) & 0xff);
        },
        .xxh128 => {
            // use first 128 bits of sha256 as xxh128 substitute
            var full: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(data, &full, .{});
            @memcpy(out[0..16], full[0..16]);
        },
    }
}

fn computeHmac(algo: HashAlgo, data: []const u8, key: []const u8, out: []u8) void {
    switch (algo) {
        .md5 => std.crypto.auth.hmac.HmacMd5.create(out[0..16], data, key),
        .sha1 => std.crypto.auth.hmac.HmacSha1.create(out[0..20], data, key),
        .sha256 => std.crypto.auth.hmac.sha2.HmacSha256.create(out[0..32], data, key),
        .sha384 => std.crypto.auth.hmac.sha2.HmacSha384.create(out[0..48], data, key),
        .sha512 => std.crypto.auth.hmac.sha2.HmacSha512.create(out[0..64], data, key),
        // hmac is only defined for proper cryptographic hashes; for crc/xxh
        // PHP rejects them, but we just hash the data without keying for now
        .sha3_224, .sha3_256, .sha3_384, .sha3_512, .crc32, .crc32b, .xxh32, .xxh64, .xxh3, .xxh128 => computeHash(algo, data, out),
    }
}

fn toHexString(ctx: *NativeContext, digest: []const u8) ![]const u8 {
    const hex = "0123456789abcdef";
    const result = try ctx.allocator.alloc(u8, digest.len * 2);
    for (digest, 0..) |b, i| {
        result[i * 2] = hex[b >> 4];
        result[i * 2 + 1] = hex[b & 0x0f];
    }
    try ctx.strings.append(ctx.allocator, result);
    return result;
}

fn native_hash(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return Value{ .bool = false };
    const algo_name = args[0].string;
    const data = args[1].string;
    const raw_output = args.len >= 3 and args[2].isTruthy();

    const algo = HashAlgo.fromString(algo_name) orelse return Value{ .bool = false };
    var digest: [64]u8 = undefined;
    const dlen = algo.digestLen();
    computeHash(algo, data, digest[0..dlen]);

    if (raw_output) {
        return .{ .string = try ctx.createString(digest[0..dlen]) };
    }
    return .{ .string = try toHexString(ctx, digest[0..dlen]) };
}

fn native_hash_hmac(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[0] != .string or args[1] != .string or args[2] != .string) return Value{ .bool = false };
    const algo_name = args[0].string;
    const data = args[1].string;
    const key = args[2].string;
    const raw_output = args.len >= 4 and args[3].isTruthy();

    const algo = HashAlgo.fromString(algo_name) orelse return Value{ .bool = false };
    if (algo == .crc32) return Value{ .bool = false };

    var digest: [64]u8 = undefined;
    const dlen = algo.digestLen();
    computeHmac(algo, data, key, digest[0..dlen]);

    if (raw_output) {
        return .{ .string = try ctx.createString(digest[0..dlen]) };
    }
    return .{ .string = try toHexString(ctx, digest[0..dlen]) };
}

fn native_hash_algos(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    var arr = try ctx.createArray();
    const algos = [_][]const u8{ "md5", "sha1", "sha256", "sha384", "sha512", "crc32" };
    for (algos) |name| {
        try arr.append(ctx.allocator, .{ .string = name });
    }
    return .{ .array = arr };
}

fn native_hash_file(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return Value{ .bool = false };
    const algo_name = args[0].string;
    const filename = args[1].string;
    const raw_output = args.len >= 3 and args[2].isTruthy();
    const algo = HashAlgo.fromString(algo_name) orelse return Value{ .bool = false };
    const data = std.fs.cwd().readFileAlloc(ctx.allocator, filename, 10 * 1024 * 1024) catch return Value{ .bool = false };
    var digest: [64]u8 = undefined;
    const dlen = algo.digestLen();
    computeHash(algo, data, digest[0..dlen]);
    if (raw_output) return .{ .string = try ctx.createString(digest[0..dlen]) };
    return .{ .string = try toHexString(ctx, digest[0..dlen]) };
}

fn native_hash_equals(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const known = args[0].string;
    const user = args[1].string;
    if (known.len != user.len) return .{ .bool = false };
    var result: u8 = 0;
    for (known, user) |a, b| result |= a ^ b;
    return .{ .bool = result == 0 };
}

const PhpObject = @import("../runtime/value.zig").PhpObject;

fn native_hash_init(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const algo = HashAlgo.fromString(args[0].string) orelse return .{ .bool = false };
    _ = algo;
    const obj = try ctx.allocator.create(PhpObject);
    obj.* = .{ .class_name = "HashContext" };
    try ctx.vm.objects.append(ctx.allocator, obj);
    try obj.set(ctx.allocator, "algo", .{ .string = try ctx.createString(args[0].string) });
    // store accumulated bytes in a string buffer that grows
    try obj.set(ctx.allocator, "buffer", .{ .string = "" });
    if (args.len >= 3 and args[2] == .string) {
        try obj.set(ctx.allocator, "key", .{ .string = try ctx.createString(args[2].string) });
    }
    return .{ .object = obj };
}

fn native_hash_update(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .object or args[1] != .string) return .{ .bool = false };
    const obj = args[0].object;
    const cur = obj.get("buffer");
    const cur_str: []const u8 = if (cur == .string) cur.string else "";
    const new_buf = try ctx.allocator.alloc(u8, cur_str.len + args[1].string.len);
    @memcpy(new_buf[0..cur_str.len], cur_str);
    @memcpy(new_buf[cur_str.len..], args[1].string);
    try ctx.vm.strings.append(ctx.allocator, new_buf);
    try obj.set(ctx.allocator, "buffer", .{ .string = new_buf });
    return .{ .bool = true };
}

fn native_hash_update_file(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .object or args[1] != .string) return .{ .bool = false };
    const data = std.fs.cwd().readFileAlloc(ctx.allocator, args[1].string, 64 * 1024 * 1024) catch return .{ .bool = false };
    return native_hash_update(ctx, &.{ args[0], .{ .string = data } });
}

fn native_hash_final(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .object) return .{ .bool = false };
    const obj = args[0].object;
    const algo_v = obj.get("algo");
    const buf_v = obj.get("buffer");
    if (algo_v != .string) return .{ .bool = false };
    const data: []const u8 = if (buf_v == .string) buf_v.string else "";
    const algo = HashAlgo.fromString(algo_v.string) orelse return .{ .bool = false };
    const raw_output = args.len >= 2 and args[1].isTruthy();
    var digest: [64]u8 = undefined;
    const dlen = algo.digestLen();
    const key_v = obj.get("key");
    if (key_v == .string and key_v.string.len > 0) {
        computeHmac(algo, data, key_v.string, digest[0..dlen]);
    } else {
        computeHash(algo, data, digest[0..dlen]);
    }
    if (raw_output) return .{ .string = try ctx.createString(digest[0..dlen]) };
    return .{ .string = try toHexString(ctx, digest[0..dlen]) };
}

fn native_hash_copy(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .object) return .{ .bool = false };
    const orig = args[0].object;
    const obj = try ctx.allocator.create(PhpObject);
    obj.* = .{ .class_name = "HashContext" };
    try ctx.vm.objects.append(ctx.allocator, obj);
    try obj.set(ctx.allocator, "algo", orig.get("algo"));
    try obj.set(ctx.allocator, "buffer", orig.get("buffer"));
    try obj.set(ctx.allocator, "key", orig.get("key"));
    return .{ .object = obj };
}

fn native_hash_pbkdf2(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 4 or args[0] != .string or args[1] != .string or args[2] != .string) return .{ .bool = false };
    const algo_name = args[0].string;
    const password = args[1].string;
    const salt = args[2].string;
    const iterations: usize = @intCast(@max(1, Value.toInt(args[3])));
    const length_arg: usize = if (args.len >= 5) @intCast(@max(0, Value.toInt(args[4]))) else 0;
    const raw_output = args.len >= 6 and args[5].isTruthy();
    const algo = HashAlgo.fromString(algo_name) orelse return .{ .bool = false };
    const dlen = algo.digestLen();

    const out_bytes: usize = blk: {
        if (length_arg == 0) break :blk dlen;
        if (raw_output) break :blk length_arg;
        break :blk (length_arg + 1) / 2;
    };
    const out = try ctx.allocator.alloc(u8, out_bytes);

    // basic PBKDF2-HMAC implementation
    var block_index: u32 = 1;
    var written: usize = 0;
    while (written < out_bytes) : (block_index += 1) {
        var u_buf: [64]u8 = undefined;
        const salted = try ctx.allocator.alloc(u8, salt.len + 4);
        defer ctx.allocator.free(salted);
        @memcpy(salted[0..salt.len], salt);
        salted[salt.len] = @intCast((block_index >> 24) & 0xff);
        salted[salt.len + 1] = @intCast((block_index >> 16) & 0xff);
        salted[salt.len + 2] = @intCast((block_index >> 8) & 0xff);
        salted[salt.len + 3] = @intCast(block_index & 0xff);
        computeHmac(algo, salted, password, u_buf[0..dlen]);
        var t_buf: [64]u8 = undefined;
        @memcpy(t_buf[0..dlen], u_buf[0..dlen]);
        var iter: usize = 1;
        while (iter < iterations) : (iter += 1) {
            var next_u: [64]u8 = undefined;
            computeHmac(algo, u_buf[0..dlen], password, next_u[0..dlen]);
            @memcpy(u_buf[0..dlen], next_u[0..dlen]);
            for (0..dlen) |i| t_buf[i] ^= u_buf[i];
        }
        const take: usize = @min(dlen, out_bytes - written);
        @memcpy(out[written..written + take], t_buf[0..take]);
        written += take;
    }

    if (raw_output) {
        try ctx.vm.strings.append(ctx.allocator, out);
        return .{ .string = out };
    }
    const hex = try toHexString(ctx, out);
    ctx.allocator.free(out);
    if (length_arg > 0 and length_arg < hex.len) return .{ .string = hex[0..length_arg] };
    return .{ .string = hex };
}
