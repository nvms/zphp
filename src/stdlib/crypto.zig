const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "password_hash", native_password_hash },
    .{ "password_verify", native_password_verify },
    .{ "password_needs_rehash", native_password_needs_rehash },
    .{ "random_bytes", native_random_bytes },
    .{ "random_int", native_random_int },
    .{ "hash", native_hash },
    .{ "hash_hmac", native_hash_hmac },
    .{ "hash_algos", native_hash_algos },
    .{ "hash_equals", native_hash_equals },
};

fn native_password_hash(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return Value{ .bool = false };
    const password = args[0].string;

    // default cost 10, PHP's PASSWORD_BCRYPT default
    var rounds_log: u6 = 10;
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

    return .{ .string = try ctx.createString(hash) };
}

fn native_password_verify(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return Value{ .bool = false };
    const password = args[0].string;
    const hash = args[1].string;

    std.crypto.pwhash.bcrypt.strVerify(hash, password, .{
        .silently_truncate_password = true,
    }) catch return Value{ .bool = false };

    return Value{ .bool = true };
}

fn native_password_needs_rehash(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string) return Value{ .bool = true };
    const hash = args[0].string;

    var target_cost: u6 = 10;
    if (args.len >= 3 and args[2] == .array) {
        const opts = args[2].array;
        const cost_val = opts.get(.{ .string = "cost" });
        if (cost_val == .int and cost_val.int >= 4 and cost_val.int <= 31) {
            target_cost = @intCast(cost_val.int);
        }
    }

    // parse cost from $2y$XX$ or $2b$XX$ format
    if (hash.len < 7 or hash[0] != '$' or hash[1] != '2') return Value{ .bool = true };
    const cost_start: usize = if (hash[2] == '$') 3 else if (hash[3] == '$') 4 else return Value{ .bool = true };
    const cost = std.fmt.parseInt(u6, hash[cost_start .. cost_start + 2], 10) catch return Value{ .bool = true };

    return Value{ .bool = cost != target_cost };
}

fn native_random_bytes(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .int) return Value{ .bool = false };
    const length = args[0].int;
    if (length < 1 or length > 1048576) return Value{ .bool = false };

    const len: usize = @intCast(length);
    const buf = try ctx.allocator.alloc(u8, len);
    std.crypto.random.bytes(buf);
    try ctx.strings.append(ctx.allocator, buf);
    return .{ .string = buf };
}

fn native_random_int(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .int or args[1] != .int) return Value{ .bool = false };
    const min = args[0].int;
    const max = args[1].int;
    if (min > max) return Value{ .bool = false };
    if (min == max) return Value{ .int = min };

    const range: u64 = @intCast(max - min);
    const random = std.crypto.random.intRangeAtMost(u64, 0, range);
    return Value{ .int = min + @as(i64, @intCast(random)) };
}

const HashAlgo = enum {
    md5,
    sha1,
    sha256,
    sha384,
    sha512,
    crc32,

    fn fromString(name: []const u8) ?HashAlgo {
        if (std.mem.eql(u8, name, "md5")) return .md5;
        if (std.mem.eql(u8, name, "sha1")) return .sha1;
        if (std.mem.eql(u8, name, "sha256")) return .sha256;
        if (std.mem.eql(u8, name, "sha384")) return .sha384;
        if (std.mem.eql(u8, name, "sha512")) return .sha512;
        if (std.mem.eql(u8, name, "crc32")) return .crc32;
        return null;
    }

    fn digestLen(self: HashAlgo) usize {
        return switch (self) {
            .md5 => 16,
            .sha1 => 20,
            .sha256 => 32,
            .sha384 => 48,
            .sha512 => 64,
            .crc32 => 4,
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
        .crc32 => {
            const c = std.hash.crc.Crc32IsoHdlc.hash(data);
            out[0] = @intCast((c >> 24) & 0xff);
            out[1] = @intCast((c >> 16) & 0xff);
            out[2] = @intCast((c >> 8) & 0xff);
            out[3] = @intCast(c & 0xff);
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
        .crc32 => {
            // crc32 doesn't have hmac, just hash the data
            const c = std.hash.crc.Crc32IsoHdlc.hash(data);
            out[0] = @intCast((c >> 24) & 0xff);
            out[1] = @intCast((c >> 16) & 0xff);
            out[2] = @intCast((c >> 8) & 0xff);
            out[3] = @intCast(c & 0xff);
        },
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
    const raw_output = args.len >= 3 and args[2] == .bool and args[2].bool;

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
    const raw_output = args.len >= 4 and args[3] == .bool and args[3].bool;

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

fn native_hash_equals(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const known = args[0].string;
    const user = args[1].string;
    if (known.len != user.len) return .{ .bool = false };
    var result: u8 = 0;
    for (known, user) |a, b| result |= a ^ b;
    return .{ .bool = result == 0 };
}
