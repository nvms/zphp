const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const std = @import("std");
const platform = @import("../platform.zig");
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
    .{ "stream_select", native_stream_select },
    .{ "stream_socket_pair", native_stream_socket_pair },
};

fn streamFd(v: Value) ?i64 {
    if (v != .object) return null;
    const fdv = v.object.get("__fd");
    if (fdv != .int or fdv.int < 0) return null;
    return fdv.int;
}

fn isNetStream(v: Value) bool {
    const net = v.object.get("__net");
    return net == .bool and net.bool;
}

const poll_events = [_]i16{ std.posix.POLL.IN, std.posix.POLL.OUT, std.posix.POLL.PRI };

// one stream from one of the three select sets. sockets sit in the poll
// list; on windows every other descriptor is a crt handle that WSAPoll
// cannot wait on, so it is checked by hand
const Watched = struct {
    slot: u8,
    val: Value,
    fd: i64,
    poll_index: ?usize,
    ready: bool = false,
};

const WatchList = std.ArrayListUnmanaged(Watched);
const PollList = std.ArrayListUnmanaged(std.posix.pollfd);

// stream_select(&$read, &$write, &$except, ?int $seconds, int $microseconds = 0): int|false
// waits on the streams in each (by-ref) array and rewrites each array to the
// ready subset, returning the number ready (false on error). null $seconds blocks
fn native_stream_select(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    var watched: WatchList = .{};
    defer watched.deinit(ctx.allocator);
    var pollfds: PollList = .{};
    defer pollfds.deinit(ctx.allocator);

    const total_streams = try watchStreams(ctx, args, &watched, &pollfds);
    if (total_streams == 0) {
        try ctx.vm.setPendingException("ValueError", "No stream arrays were passed");
        return error.RuntimeError;
    }

    const block = args.len < 4 or args[3] == .null;
    const sec: i64 = if (!block) Value.toInt(args[3]) else 0;
    const usec: i64 = if (args.len > 4) Value.toInt(args[4]) else 0;
    const timeout_ms: i32 = if (block) -1 else @intCast(@max(0, sec * 1000 + @divTrunc(usec, 1000)));

    awaitReady(watched.items, pollfds.items, timeout_ms) catch return NativeResult.scalar(.{ .bool = false });

    var out = [_]?*PhpArray{ null, null, null };
    var count: i64 = 0;
    for (watched.items) |w| {
        if (!w.ready) continue;
        if (out[w.slot] == null) out[w.slot] = try ctx.createArray();
        try out[w.slot].?.append(ctx.allocator, w.val);
        count += 1;
    }
    var slot: usize = 0;
    while (slot < 3) : (slot += 1) {
        if (slot >= args.len or args[slot] != .array) continue;
        const arr = out[slot] orelse try ctx.createArray();
        ctx.setCallerVar(slot, args.len, .{ .array = arr });
    }
    return NativeResult.scalar(.{ .int = count });
}

fn watchStreams(ctx: *NativeContext, args: []const Value, watched: *WatchList, pollfds: *PollList) !usize {
    var total: usize = 0;
    var slot: usize = 0;
    while (slot < 3) : (slot += 1) {
        if (slot >= args.len or args[slot] != .array) continue;
        for (args[slot].array.entries.items) |entry| {
            total += 1;
            const fd = streamFd(entry.value) orelse continue;
            var poll_index: ?usize = null;
            if (!platform.is_windows or isNetStream(entry.value)) {
                const sock = platform.socketFromInt(fd) orelse continue;
                poll_index = pollfds.items.len;
                try pollfds.append(ctx.allocator, .{ .fd = sock, .events = poll_events[slot], .revents = 0 });
            }
            try watched.append(ctx.allocator, .{ .slot = @intCast(slot), .val = entry.value, .fd = fd, .poll_index = poll_index });
        }
    }
    return total;
}

fn hasHandles(watched: []const Watched) bool {
    for (watched) |w| if (w.poll_index == null) return true;
    return false;
}

fn anyReady(watched: []const Watched) bool {
    for (watched) |w| if (w.ready) return true;
    return false;
}

// sockets wait in poll. with crt handles in the mix (windows only) the wait
// is sliced: each slice peeks the handles, then polls or sleeps for the
// slice, until something is ready or the timeout runs out
fn awaitReady(watched: []Watched, pollfds: []std.posix.pollfd, timeout_ms: i32) !void {
    if (!platform.is_windows or !hasHandles(watched)) {
        try pollSockets(pollfds, timeout_ms);
        markSocketsReady(watched, pollfds);
        return;
    }
    const slice_ms: i32 = 10;
    var remaining = timeout_ms;
    while (true) {
        const handle_ready = markHandlesReady(watched);
        const wait_ms: i32 = if (handle_ready or remaining == 0) 0 else if (remaining < 0) slice_ms else @min(slice_ms, remaining);
        try pollSockets(pollfds, wait_ms);
        markSocketsReady(watched, pollfds);
        if (anyReady(watched) or remaining == 0) return;
        if (pollfds.len == 0) std.Thread.sleep(@as(u64, @intCast(wait_ms)) * std.time.ns_per_ms);
        if (remaining > 0) remaining -= wait_ms;
    }
}

fn pollSockets(pollfds: []std.posix.pollfd, timeout_ms: i32) !void {
    if (pollfds.len == 0) return;
    _ = std.posix.poll(pollfds, timeout_ms) catch return error.PollFailed;
}

fn markSocketsReady(watched: []Watched, pollfds: []const std.posix.pollfd) void {
    for (watched) |*w| {
        const idx = w.poll_index orelse continue;
        const mask = poll_events[w.slot] | std.posix.POLL.ERR | std.posix.POLL.HUP;
        if ((pollfds[idx].revents & mask) != 0) w.ready = true;
    }
}

fn markHandlesReady(watched: []Watched) bool {
    var any = false;
    for (watched) |*w| {
        if (w.poll_index != null) continue;
        w.ready = switch (w.slot) {
            0 => handleReadable(w.fd),
            1 => true,
            else => false,
        };
        if (w.ready) any = true;
    }
    return any;
}

const win = std.os.windows;
const FILE_TYPE_PIPE: u32 = 3;
extern "kernel32" fn GetFileType(handle: win.HANDLE) callconv(.winapi) u32;
extern "kernel32" fn PeekNamedPipe(pipe: win.HANDLE, buffer: ?*anyopaque, size: u32, read: ?*u32, available: ?*u32, left: ?*u32) callconv(.winapi) win.BOOL;

// a pipe is readable once bytes are pending or its writer is gone; a disk
// file or console reads without waiting, which is what php's own select
// emulation on windows reports
fn handleReadable(fd: i64) bool {
    const file = platform.fileFromFd(fd) orelse return true;
    if (GetFileType(file.handle) != FILE_TYPE_PIPE) return true;
    var available: u32 = 0;
    if (PeekNamedPipe(file.handle, null, 0, null, &available, null) != 0) return available > 0;
    return win.GetLastError() == .BROKEN_PIPE;
}

// stream_socket_pair(int $domain, int $type, int $protocol): array|false
// a connected pair of stream sockets (a unix pair, or the loopback tcp pair
// php itself uses on windows) returned as two net stream objects
fn native_stream_socket_pair(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const pair = platform.socketPair() catch return NativeResult.scalar(.{ .bool = false });
    const arr = try ctx.createArray();
    for (pair) |sock| {
        const obj = try socketStream(ctx, sock);
        try arr.append(ctx.allocator, .{ .object = obj });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn socketStream(ctx: *NativeContext, sock: std.posix.socket_t) !*PhpObject {
    const obj = try ctx.allocator.create(PhpObject);
    obj.* = .{ .class_name = "FileHandle" };
    try ctx.vm.objects.append(ctx.allocator, obj);
    try obj.set(ctx.allocator, "__fd", .{ .int = platform.socketToInt(sock) });
    try obj.set(ctx.allocator, "__open", .{ .bool = true });
    try obj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed("r+") });
    try obj.set(ctx.allocator, "__net", .{ .bool = true });
    return obj;
}

fn native_stream_context_create(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try ctx.vm.allocator.create(PhpObject);
    obj.* = .{ .class_name = "StreamContext" };
    try ctx.vm.objects.append(ctx.vm.allocator, obj);
    if (args.len >= 1 and args[0] == .array) {
        try obj.set(ctx.allocator, "options", args[0]);
    }
    if (args.len >= 2 and args[1] == .array) {
        try obj.set(ctx.allocator, "params", args[1]);
    }
    return NativeResult.borrowed(.{ .object = obj });
}

fn native_stream_context_get_options(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const opts = args[0].object.get("options");
    if (opts == .array) return NativeResult.borrowed(opts);
    return NativeResult.scalar(.{ .bool = false });
}

fn native_stream_context_get_params(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.share(args[0].object.get("params"));
}

fn native_stream_context_set_options(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
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
            try ctx.vm.arraySetOwned(opts, wrap_key, .{ .array = wrap_arr });
        }
        try ctx.vm.arraySetOwned(wrap_arr, PhpArray.Key{ .string = args[2].string }, args[3]);
        return NativeResult.scalar(.{ .bool = true });
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
        try ctx.vm.arraySetOwned(opts, PhpArray.Key{ .string = args[1].string }, args[2]);
        return NativeResult.scalar(.{ .bool = true });
    }
    if (args[1] == .array) {
        try args[0].object.set(ctx.allocator, "options", args[1]);
        return NativeResult.scalar(.{ .bool = true });
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn native_stream_context_set_params(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    if (args[1] == .array) {
        try args[0].object.set(ctx.allocator, "params", args[1]);
        return NativeResult.scalar(.{ .bool = true });
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn native_stream_context_get_default(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = try ctx.vm.allocator.create(PhpObject);
    obj.* = .{ .class_name = "StreamContext" };
    try ctx.vm.objects.append(ctx.vm.allocator, obj);
    return NativeResult.borrowed(.{ .object = obj });
}

fn native_stream_context_set_default(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return native_stream_context_create(ctx, args);
}

fn native_gethostbyname(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const host = args[0].string.bytes();
    var list = std.net.getAddressList(ctx.allocator, host, 0) catch return NativeResult.share(args[0]);
    defer list.deinit();
    if (list.addrs.len == 0) return NativeResult.share(args[0]);
    for (list.addrs) |addr| {
        if (addr.any.family == std.posix.AF.INET) {
            var buf: [32]u8 = undefined;
            const written = std.fmt.bufPrint(&buf, "{f}", .{addr}) catch return NativeResult.share(args[0]);
            // strip port if present (Address.format adds :port)
            const colon = std.mem.lastIndexOfScalar(u8, written, ':') orelse written.len;
            return NativeResult.copyString(ctx.allocator, written[0..colon]);
        }
    }
    return NativeResult.share(args[0]);
}

// gethostbynamel: like gethostbyname but returns all resolved IPv4 addresses
// as a numerically-indexed array, or false on failure
fn native_gethostbynamel(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const host = args[0].string.bytes();
    var list = std.net.getAddressList(ctx.allocator, host, 0) catch return NativeResult.scalar(.{ .bool = false });
    defer list.deinit();
    if (list.addrs.len == 0) return NativeResult.scalar(.{ .bool = false });
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
        const owned = try Value.String.create(ctx.allocator, ip_str);
        defer owned.release();
        try seen.put(ctx.allocator, owned.bytes(), {});
        try arr.append(ctx.allocator, .{ .string = owned });
    }
    if (arr.entries.items.len == 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_gethostbyaddr(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    // best-effort: just echo back the IP if we can't reverse-resolve
    return NativeResult.copyString(ctx.allocator, args[0].string.bytes());
}

fn native_gethostname(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    var buf: [256]u8 = undefined;
    const name = platform.hostname(&buf) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.copyString(ctx.allocator, name);
}

fn native_inet_pton(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const s = args[0].string.bytes();
    // try IPv4
    if (std.net.Address.parseIp4(s, 0)) |addr| {
        const bytes = std.mem.toBytes(addr.in.sa.addr);
        return NativeResult.copyString(ctx.allocator, &bytes);
    } else |_| {}
    // try IPv6
    if (std.net.Address.parseIp6(s, 0)) |addr| {
        return NativeResult.copyString(ctx.allocator, &addr.in6.sa.addr);
    } else |_| {}
    return NativeResult.scalar(.{ .bool = false });
}

fn native_inet_ntop(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const bytes = args[0].string.bytes();
    if (bytes.len == 4) {
        var buf: [32]u8 = undefined;
        const out = std.fmt.bufPrint(&buf, "{d}.{d}.{d}.{d}", .{ bytes[0], bytes[1], bytes[2], bytes[3] }) catch return NativeResult.scalar(.{ .bool = false });
        return NativeResult.copyString(ctx.allocator, out);
    }
    if (bytes.len == 16) {
        var addr: [16]u8 = undefined;
        @memcpy(&addr, bytes);
        const ip = std.net.Address.initIp6(addr, 0, 0, 0);
        var buf: [64]u8 = undefined;
        const out = std.fmt.bufPrint(&buf, "{f}", .{ip}) catch return NativeResult.scalar(.{ .bool = false });
        // strip [...]:port wrapping
        var s = out;
        if (s.len > 0 and s[0] == '[') {
            const close = std.mem.indexOfScalar(u8, s, ']') orelse return NativeResult.scalar(.{ .bool = false });
            s = s[1..close];
        }
        return NativeResult.copyString(ctx.allocator, s);
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn native_ip2long(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    var parts: [4]u32 = undefined;
    var idx: usize = 0;
    var it = std.mem.splitScalar(u8, args[0].string.bytes(), '.');
    while (it.next()) |part| {
        if (idx >= 4) return NativeResult.scalar(.{ .bool = false });
        parts[idx] = std.fmt.parseUnsigned(u8, part, 10) catch return NativeResult.scalar(.{ .bool = false });
        idx += 1;
    }
    if (idx != 4) return NativeResult.scalar(.{ .bool = false });
    const long: i64 = @intCast((parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]);
    return NativeResult.scalar(.{ .int = long });
}

fn native_long2ip(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    const n = Value.toInt(args[0]);
    const u: u32 = @truncate(@as(u64, @bitCast(n)));
    var buf: [32]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "{d}.{d}.{d}.{d}", .{ (u >> 24) & 0xff, (u >> 16) & 0xff, (u >> 8) & 0xff, u & 0xff }) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.copyString(ctx.allocator, out);
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
    const stream = platform.tcpConnect(addr_list.addrs[0]) catch return error.RuntimeError;
    return socketStream(ctx, stream.handle);
}

fn native_fsockopen(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const host = args[0].string.bytes();
    const port: u16 = if (args.len >= 2) @intCast(@max(0, Value.toInt(args[1]))) else 80;
    if (port == 0) return NativeResult.scalar(.{ .bool = false });
    const obj = openTcpHandle(ctx, host, port) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.borrowed(.{ .object = obj });
}

fn native_stream_socket_client(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const target = parseHostPort(args[0].string.bytes()) orelse return NativeResult.scalar(.{ .bool = false });
    if (target.port == 0) return NativeResult.scalar(.{ .bool = false });
    const obj = openTcpHandle(ctx, target.host, target.port) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.borrowed(.{ .object = obj });
}

fn native_checkdnsrr(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    var list = std.net.getAddressList(ctx.allocator, args[0].string.bytes(), 0) catch return NativeResult.scalar(.{ .bool = false });
    defer list.deinit();
    return NativeResult.scalar(.{ .bool = list.addrs.len > 0 });
}

fn native_dns_get_record(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const result = try ctx.createArray();
    var list = std.net.getAddressList(ctx.allocator, args[0].string.bytes(), 0) catch return NativeResult.borrowed(.{ .array = result });
    defer list.deinit();
    for (list.addrs) |addr| {
        const entry = try ctx.createArray();
        try entry.set(ctx.allocator, .{ .string = Value.String.borrowed("host") }, args[0]);
        try entry.set(ctx.allocator, .{ .string = Value.String.borrowed("class") }, .{ .string = Value.String.borrowed("IN") });
        if (addr.any.family == std.posix.AF.INET) {
            const bytes = std.mem.toBytes(addr.in.sa.addr);
            var buf: [32]u8 = undefined;
            const ip = std.fmt.bufPrint(&buf, "{d}.{d}.{d}.{d}", .{ bytes[0], bytes[1], bytes[2], bytes[3] }) catch continue;
            try entry.set(ctx.allocator, .{ .string = Value.String.borrowed("type") }, .{ .string = Value.String.borrowed("A") });
            const owned = try Value.String.create(ctx.allocator, ip);
            defer owned.release();
            try entry.set(ctx.allocator, .{ .string = Value.String.borrowed("ip") }, .{ .string = owned });
        } else if (addr.any.family == std.posix.AF.INET6) {
            try entry.set(ctx.allocator, .{ .string = Value.String.borrowed("type") }, .{ .string = Value.String.borrowed("AAAA") });
            var buf: [64]u8 = undefined;
            const raw = std.fmt.bufPrint(&buf, "{f}", .{addr}) catch continue;
            var out: []const u8 = raw;
            if (out.len > 0 and out[0] == '[') {
                if (std.mem.indexOfScalar(u8, out, ']')) |ci| out = out[1..ci];
            }
            const owned = try Value.String.create(ctx.allocator, out);
            defer owned.release();
            try entry.set(ctx.allocator, .{ .string = Value.String.borrowed("ipv6") }, .{ .string = owned });
        }
        try result.append(ctx.allocator, .{ .array = entry });
    }
    return NativeResult.borrowed(.{ .array = result });
}
