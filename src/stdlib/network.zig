const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "gethostbyname", native_gethostbyname },
    .{ "gethostbynamel", native_gethostbynamel },
    .{ "gethostbyaddr", native_gethostbyaddr },
    .{ "gethostname", native_gethostname },
    .{ "inet_pton", native_inet_pton },
    .{ "inet_ntop", native_inet_ntop },
    .{ "ip2long", native_ip2long },
    .{ "long2ip", native_long2ip },
    .{ "fsockopen", native_fsockopen },
    .{ "pfsockopen", native_fsockopen },
    .{ "stream_socket_client", native_stream_socket_client },
    .{ "stream_context_create", native_stream_context_create },
    .{ "stream_context_get_options", native_stream_context_get_options },
    .{ "stream_context_get_params", native_stream_context_get_params },
    .{ "stream_context_set_options", native_stream_context_set_options },
    .{ "stream_context_set_option", native_stream_context_set_options },
    .{ "stream_context_set_params", native_stream_context_set_params },
    .{ "stream_context_get_default", native_stream_context_get_default },
    .{ "stream_context_set_default", native_stream_context_set_default },
    .{ "checkdnsrr", native_checkdnsrr },
    .{ "dns_get_record", native_dns_get_record },
};

fn native_stream_context_create(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = try ctx.vm.allocator.create(PhpObject);
    obj.* = .{ .class_name = "StreamContext" };
    try ctx.vm.objects.append(ctx.vm.allocator, obj);
    if (args.len >= 1 and args[0] == .array) {
        try obj.set(ctx.allocator, "options", args[0]);
    }
    if (args.len >= 2 and args[1] == .array) {
        try obj.set(ctx.allocator, "params", args[1]);
    }
    return .{ .object = obj };
}

fn native_stream_context_get_options(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .object) return .{ .bool = false };
    const opts = args[0].object.get("options");
    if (opts == .array) return opts;
    return .{ .bool = false };
}

fn native_stream_context_get_params(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .object) return .{ .bool = false };
    return args[0].object.get("params");
}

fn native_stream_context_set_options(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .object) return .{ .bool = false };
    // 4-arg form: stream_context_set_option($ctx, $wrapper, $option, $value)
    // merges the (wrapper, option) into the existing options array
    if (args.len >= 4 and args[1] == .string and args[2] == .string) {
        const opts_v = args[0].object.get("options");
        var opts: *PhpArray = undefined;
        if (opts_v == .array) {
            opts = opts_v.array;
        } else {
            opts = try ctx.createArray();
            try args[0].object.set(ctx.allocator, "options", .{ .array = opts });
        }
        const wrap_key: PhpArray.Key = .{ .string = args[1].string };
        const wrap_v = opts.get(wrap_key);
        var wrap_arr: *PhpArray = undefined;
        if (wrap_v == .array) {
            wrap_arr = wrap_v.array;
        } else {
            wrap_arr = try ctx.createArray();
            try opts.set(ctx.allocator, wrap_key, .{ .array = wrap_arr });
        }
        try wrap_arr.set(ctx.allocator, PhpArray.Key{ .string = args[2].string }, args[3]);
        return .{ .bool = true };
    }
    // 3-arg form: stream_context_set_option($ctx, $wrapper, $options_assoc) -
    // PHP also accepts this; merge per-wrapper
    if (args.len == 3 and args[1] == .string and args[2] == .array) {
        const opts_v = args[0].object.get("options");
        var opts: *PhpArray = undefined;
        if (opts_v == .array) opts = opts_v.array else {
            opts = try ctx.createArray();
            try args[0].object.set(ctx.allocator, "options", .{ .array = opts });
        }
        try opts.set(ctx.allocator, PhpArray.Key{ .string = args[1].string }, args[2]);
        return .{ .bool = true };
    }
    if (args[1] == .array) {
        try args[0].object.set(ctx.allocator, "options", args[1]);
        return .{ .bool = true };
    }
    return .{ .bool = false };
}

fn native_stream_context_set_params(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .object) return .{ .bool = false };
    if (args[1] == .array) {
        try args[0].object.set(ctx.allocator, "params", args[1]);
        return .{ .bool = true };
    }
    return .{ .bool = false };
}

fn native_stream_context_get_default(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = try ctx.vm.allocator.create(PhpObject);
    obj.* = .{ .class_name = "StreamContext" };
    try ctx.vm.objects.append(ctx.vm.allocator, obj);
    return .{ .object = obj };
}

fn native_stream_context_set_default(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return native_stream_context_create(ctx, args);
}

fn createString(ctx: *NativeContext, s: []const u8) ![]const u8 {
    const copy = try ctx.allocator.dupe(u8, s);
    try ctx.vm.strings.append(ctx.allocator, copy);
    return copy;
}

fn native_gethostbyname(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const host = args[0].string;
    var list = std.net.getAddressList(ctx.allocator, host, 0) catch return args[0];
    defer list.deinit();
    if (list.addrs.len == 0) return args[0];
    for (list.addrs) |addr| {
        if (addr.any.family == std.posix.AF.INET) {
            var buf: [32]u8 = undefined;
            const written = std.fmt.bufPrint(&buf, "{f}", .{addr}) catch return args[0];
            // strip port if present (Address.format adds :port)
            const colon = std.mem.lastIndexOfScalar(u8, written, ':') orelse written.len;
            return .{ .string = try createString(ctx, written[0..colon]) };
        }
    }
    return args[0];
}

// gethostbynamel: like gethostbyname but returns all resolved IPv4 addresses
// as a numerically-indexed array, or false on failure
fn native_gethostbynamel(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const host = args[0].string;
    var list = std.net.getAddressList(ctx.allocator, host, 0) catch return .{ .bool = false };
    defer list.deinit();
    if (list.addrs.len == 0) return .{ .bool = false };
    const arr = try ctx.createArray();
    var seen = std.StringHashMapUnmanaged(void){};
    defer seen.deinit(ctx.allocator);
    for (list.addrs) |addr| {
        if (addr.any.family != std.posix.AF.INET) continue;
        var buf: [32]u8 = undefined;
        const written = std.fmt.bufPrint(&buf, "{f}", .{addr}) catch continue;
        const colon = std.mem.lastIndexOfScalar(u8, written, ':') orelse written.len;
        const ip_str = written[0..colon];
        // dedup - the same IP can come back multiple times for different ports
        if (seen.contains(ip_str)) continue;
        const owned = try createString(ctx, ip_str);
        try seen.put(ctx.allocator, owned, {});
        try arr.append(ctx.allocator, .{ .string = owned });
    }
    if (arr.entries.items.len == 0) return .{ .bool = false };
    return .{ .array = arr };
}

fn native_gethostbyaddr(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    // best-effort: just echo back the IP if we can't reverse-resolve
    return .{ .string = try createString(ctx, args[0].string) };
}

fn native_gethostname(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    var buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const name = std.posix.gethostname(&buf) catch return .{ .bool = false };
    return .{ .string = try createString(ctx, name) };
}

fn native_inet_pton(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const s = args[0].string;
    // try IPv4
    if (std.net.Address.parseIp4(s, 0)) |addr| {
        const bytes = std.mem.toBytes(addr.in.sa.addr);
        return .{ .string = try createString(ctx, &bytes) };
    } else |_| {}
    // try IPv6
    if (std.net.Address.parseIp6(s, 0)) |addr| {
        return .{ .string = try createString(ctx, &addr.in6.sa.addr) };
    } else |_| {}
    return .{ .bool = false };
}

fn native_inet_ntop(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const bytes = args[0].string;
    if (bytes.len == 4) {
        var buf: [32]u8 = undefined;
        const out = std.fmt.bufPrint(&buf, "{d}.{d}.{d}.{d}", .{ bytes[0], bytes[1], bytes[2], bytes[3] }) catch return .{ .bool = false };
        return .{ .string = try createString(ctx, out) };
    }
    if (bytes.len == 16) {
        var addr: [16]u8 = undefined;
        @memcpy(&addr, bytes);
        const ip = std.net.Address.initIp6(addr, 0, 0, 0);
        var buf: [64]u8 = undefined;
        const out = std.fmt.bufPrint(&buf, "{f}", .{ip}) catch return .{ .bool = false };
        // strip [...]:port wrapping
        var s = out;
        if (s.len > 0 and s[0] == '[') {
            const close = std.mem.indexOfScalar(u8, s, ']') orelse return .{ .bool = false };
            s = s[1..close];
        }
        return .{ .string = try createString(ctx, s) };
    }
    return .{ .bool = false };
}

fn native_ip2long(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    var parts: [4]u32 = undefined;
    var idx: usize = 0;
    var it = std.mem.splitScalar(u8, args[0].string, '.');
    while (it.next()) |part| {
        if (idx >= 4) return .{ .bool = false };
        parts[idx] = std.fmt.parseUnsigned(u8, part, 10) catch return .{ .bool = false };
        idx += 1;
    }
    if (idx != 4) return .{ .bool = false };
    const long: i64 = @intCast((parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]);
    return .{ .int = long };
}

fn native_long2ip(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    const n = Value.toInt(args[0]);
    const u: u32 = @truncate(@as(u64, @bitCast(n)));
    var buf: [32]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "{d}.{d}.{d}.{d}", .{ (u >> 24) & 0xff, (u >> 16) & 0xff, (u >> 8) & 0xff, u & 0xff }) catch return .{ .bool = false };
    return .{ .string = try createString(ctx, out) };
}

fn parseHostPort(target: []const u8) ?struct { host: []const u8, port: u16, scheme: []const u8 } {
    var s = target;
    var scheme: []const u8 = "tcp";
    if (std.mem.indexOf(u8, s, "://")) |idx| {
        scheme = s[0..idx];
        s = s[idx + 3 ..];
    }
    var host = s;
    var port: u16 = 0;
    if (std.mem.lastIndexOfScalar(u8, s, ':')) |idx| {
        host = s[0..idx];
        port = std.fmt.parseUnsigned(u16, s[idx + 1 ..], 10) catch 0;
    }
    return .{ .host = host, .port = port, .scheme = scheme };
}

fn openTcpHandle(ctx: *NativeContext, host: []const u8, port: u16) !*PhpObject {
    const addr_list = std.net.getAddressList(ctx.allocator, host, port) catch return error.RuntimeError;
    defer addr_list.deinit();
    if (addr_list.addrs.len == 0) return error.RuntimeError;
    const stream = std.net.tcpConnectToAddress(addr_list.addrs[0]) catch return error.RuntimeError;
    const obj = try ctx.allocator.create(PhpObject);
    obj.* = .{ .class_name = "FileHandle" };
    try ctx.vm.objects.append(ctx.allocator, obj);
    try obj.set(ctx.allocator, "__fd", .{ .int = @intCast(stream.handle) });
    try obj.set(ctx.allocator, "__open", .{ .bool = true });
    try obj.set(ctx.allocator, "__mode", .{ .string = "r+" });
    try obj.set(ctx.allocator, "__net", .{ .bool = true });
    return obj;
}

fn native_fsockopen(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const host = args[0].string;
    const port: u16 = if (args.len >= 2) @intCast(@max(0, Value.toInt(args[1]))) else 80;
    if (port == 0) return .{ .bool = false };
    const obj = openTcpHandle(ctx, host, port) catch return .{ .bool = false };
    return .{ .object = obj };
}

fn native_stream_socket_client(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const target = parseHostPort(args[0].string) orelse return .{ .bool = false };
    if (target.port == 0) return .{ .bool = false };
    const obj = openTcpHandle(ctx, target.host, target.port) catch return .{ .bool = false };
    return .{ .object = obj };
}

fn native_checkdnsrr(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    var list = std.net.getAddressList(ctx.allocator, args[0].string, 0) catch return .{ .bool = false };
    defer list.deinit();
    return .{ .bool = list.addrs.len > 0 };
}

fn native_dns_get_record(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const result = try ctx.allocator.create(PhpArray);
    result.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, result);
    var list = std.net.getAddressList(ctx.allocator, args[0].string, 0) catch return .{ .array = result };
    defer list.deinit();
    for (list.addrs) |addr| {
        const entry = try ctx.allocator.create(PhpArray);
        entry.* = .{};
        try ctx.vm.arrays.append(ctx.allocator, entry);
        try entry.set(ctx.allocator, .{ .string = "host" }, .{ .string = try createString(ctx, args[0].string) });
        try entry.set(ctx.allocator, .{ .string = "class" }, .{ .string = "IN" });
        if (addr.any.family == std.posix.AF.INET) {
            const bytes = std.mem.toBytes(addr.in.sa.addr);
            var buf: [32]u8 = undefined;
            const ip = std.fmt.bufPrint(&buf, "{d}.{d}.{d}.{d}", .{ bytes[0], bytes[1], bytes[2], bytes[3] }) catch continue;
            try entry.set(ctx.allocator, .{ .string = "type" }, .{ .string = "A" });
            try entry.set(ctx.allocator, .{ .string = "ip" }, .{ .string = try createString(ctx, ip) });
        } else if (addr.any.family == std.posix.AF.INET6) {
            try entry.set(ctx.allocator, .{ .string = "type" }, .{ .string = "AAAA" });
            var buf: [64]u8 = undefined;
            const raw = std.fmt.bufPrint(&buf, "{f}", .{addr}) catch continue;
            var out: []const u8 = raw;
            if (out.len > 0 and out[0] == '[') {
                if (std.mem.indexOfScalar(u8, out, ']')) |ci| out = out[1..ci];
            }
            try entry.set(ctx.allocator, .{ .string = "ipv6" }, .{ .string = try createString(ctx, out) });
        }
        try result.append(ctx.allocator, .{ .array = entry });
    }
    return .{ .array = result };
}
