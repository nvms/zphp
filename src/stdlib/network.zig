const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const std = @import("std");
const net = @import("../net.zig");
const sys = @import("../sys.zig");
const platform = @import("../platform.zig");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };
const filesystem = @import("filesystem.zig");

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
    .{ "stream_socket_server", native_stream_socket_server },
    .{ "stream_socket_accept", native_stream_socket_accept },
    .{ "stream_socket_get_name", native_stream_socket_get_name },
    .{ "stream_socket_shutdown", native_stream_socket_shutdown },
};

fn streamFd(v: Value) ?i64 {
    if (v != .resource) return null;
    return objectFd(v.resource);
}

fn objectFd(obj: *PhpObject) ?i64 {
    const fdv = obj.get("__fd");
    if (fdv != .int or fdv.int < 0) return null;
    return fdv.int;
}

fn isNetStream(v: Value) bool {
    const flag = v.resource.get("__net");
    return flag == .bool and flag.bool;
}

const poll_events = [_]i16{ sys.POLL.IN, sys.POLL.OUT, sys.POLL.PRI };

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
const PollList = std.ArrayListUnmanaged(sys.pollfd);

// stream_select(&$read, &$write, &$except, ?int $seconds, int $microseconds = 0): int|false
// waits on the streams in each (by-ref) array and rewrites each array to the
// ready subset, returning the number ready (false on error). null $seconds blocks
fn native_stream_select(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    var watched: WatchList = .empty;
    defer watched.deinit(ctx.allocator);
    var pollfds: PollList = .empty;
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
fn awaitReady(watched: []Watched, pollfds: []sys.pollfd, timeout_ms: i32) !void {
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
        if (pollfds.len == 0) platform.sleep(@as(u64, @intCast(wait_ms)) * std.time.ns_per_ms);
        if (remaining > 0) remaining -= wait_ms;
    }
}

fn pollSockets(pollfds: []sys.pollfd, timeout_ms: i32) !void {
    if (pollfds.len == 0) return;
    _ = sys.poll(pollfds, timeout_ms) catch return error.PollFailed;
}

fn markSocketsReady(watched: []Watched, pollfds: []const sys.pollfd) void {
    for (watched) |*w| {
        const idx = w.poll_index orelse continue;
        const mask = poll_events[w.slot] | sys.POLL.ERR | sys.POLL.HUP;
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

const win32 = @import("../win32.zig");

// a pipe is readable once bytes are pending or its writer is gone; a disk
// file or console reads without waiting, which is what php's own select
// emulation on windows reports
fn handleReadable(fd: i64) bool {
    const file = platform.fileFromFd(fd) orelse return true;
    if (win32.GetFileType(file.handle) != win32.FILE_TYPE_PIPE) return true;
    var available: u32 = 0;
    if (win32.PeekNamedPipe(file.handle, null, 0, null, &available, null) != 0) return available > 0;
    return win32.GetLastError() == win32.ERROR_BROKEN_PIPE;
}

// stream_socket_pair(int $domain, int $type, int $protocol): array|false
// a connected pair of stream sockets (a unix pair, or the loopback tcp pair
// php itself uses on windows) returned as two net stream objects
fn native_stream_socket_pair(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const pair = platform.socketPair() catch return NativeResult.scalar(.{ .bool = false });
    const arr = try ctx.createArray();
    for (pair) |sock| {
        const obj = try socketStream(ctx, sock);
        try arr.append(ctx.allocator, .{ .resource = obj });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

pub fn socketStream(ctx: *NativeContext, sock: std.posix.socket_t) !*PhpObject {
    const obj = try ctx.createResource("FileHandle");
    try obj.set(ctx.allocator, "__fd", .{ .int = platform.socketToInt(sock) });
    try obj.set(ctx.allocator, "__open", .{ .bool = true });
    try obj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed("r+") });
    try obj.set(ctx.allocator, "__net", .{ .bool = true });
    return obj;
}

// stream contexts hold php's {wrapper: {option: value}} options in an
// "options" array and an optional "notification" callback. every write
// builds fresh arrays, since the old ones may be shared with a script that
// read them through stream_context_get_options

fn native_stream_context_create(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const context = try ctx.createResource("StreamContext");
    if (args.len >= 1 and args[0] == .array) try mergeContextOptions(ctx, context, args[0].array);
    if (args.len >= 2 and args[1] == .array) try applyContextParams(ctx, context, args[1].array);
    return NativeResult.borrowed(.{ .resource = context });
}

fn native_stream_context_get_options(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const context = (try contextArg(ctx, args, "stream_context_get_options", .existing)) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    return NativeResult.borrowed(.{ .array = try contextOptions(ctx, context) });
}

fn native_stream_context_get_params(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const result = try ctx.createArray();
    const context = try contextArg(ctx, args, "stream_context_get_params", .existing);
    if (context) |c| {
        const notification = c.get("notification");
        if (notification != .null) try ctx.vm.arraySetOwned(result, .{ .string = Value.String.borrowed("notification") }, notification);
    }
    const options = if (context) |c| try contextOptions(ctx, c) else try ctx.createArray();
    try ctx.vm.arraySetOwned(result, .{ .string = Value.String.borrowed("options") }, .{ .array = options });
    return NativeResult.borrowed(.{ .array = result });
}

// stream_context_set_option($context, $wrapper, $option, $value), or the
// array form that stream_context_set_options also takes
fn native_stream_context_set_options(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const context = (try contextArg(ctx, args, "stream_context_set_option", .create)).?;
    if (args.len >= 2 and args[1] == .array) {
        try mergeContextOptions(ctx, context, args[1].array);
        return NativeResult.scalar(.{ .bool = true });
    }
    if (args.len < 4 or args[1] != .string or args[2] != .string) return NativeResult.scalar(.{ .bool = false });
    const merged = try freshArray(ctx, context.get("options"));
    const wrapper_key = PhpArray.Key{ .string = args[1].string };
    const wrapper = try freshArray(ctx, merged.get(wrapper_key));
    try ctx.vm.arraySetOwned(wrapper, .{ .string = args[2].string }, args[3]);
    try ctx.vm.arraySetOwned(merged, wrapper_key, .{ .array = wrapper });
    try context.set(ctx.allocator, "options", .{ .array = merged });
    return NativeResult.scalar(.{ .bool = true });
}

fn native_stream_context_set_params(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const context = (try contextArg(ctx, args, "stream_context_set_params", .create)).?;
    if (args.len < 2 or args[1] != .array) return NativeResult.scalar(.{ .bool = false });
    try applyContextParams(ctx, context, args[1].array);
    return NativeResult.scalar(.{ .bool = true });
}

fn native_stream_context_get_default(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const context = try defaultContext(ctx);
    if (args.len >= 1 and args[0] == .array) try mergeContextOptions(ctx, context, args[0].array);
    return NativeResult.borrowed(.{ .resource = context });
}

fn native_stream_context_set_default(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const context = try defaultContext(ctx);
    if (args.len >= 1 and args[0] == .array) try mergeContextOptions(ctx, context, args[0].array);
    return NativeResult.borrowed(.{ .resource = context });
}

// php's default context, made the first time something needs it; it takes
// the next resource id then, which is why a first fopen() returns resource 5
pub fn defaultContext(ctx: *NativeContext) RuntimeError!*PhpObject {
    if (ctx.vm.default_stream_context) |context| return context;
    const context = try ctx.createResource("StreamContext");
    context.retain();
    ctx.vm.default_stream_context = context;
    return context;
}

// the context a stream-opening native runs with: its argument, or the
// default context php falls back to
pub fn streamContext(ctx: *NativeContext, arg: ?Value) RuntimeError!*PhpObject {
    if (arg) |v| if (v == .resource and std.mem.eql(u8, v.resource.class_name, "StreamContext")) return v.resource;
    return defaultContext(ctx);
}

const ContextLookup = enum { existing, create };

// a context argument, or the context of a stream argument (made on demand
// when .create); null for a stream that has none yet
fn contextArg(ctx: *NativeContext, args: []const Value, comptime func: []const u8, lookup: ContextLookup) RuntimeError!?*PhpObject {
    const v: Value = if (args.len > 0) args[0] else .null;
    const param = comptime if (std.mem.eql(u8, func, "stream_context_set_params")) "context" else "stream_or_context";
    const prefix = func ++ "(): Argument #1 ($" ++ param ++ ") must be ";
    if (v != .resource) return throwContext(ctx, prefix ++ "of type resource, {s} given", .{v.typeName()});
    const r = v.resource;
    if (std.mem.eql(u8, r.class_name, "StreamContext")) return r;
    if (!std.mem.eql(u8, r.class_name, "FileHandle") or @import("../runtime/value.zig").resourceClosed(r)) return throwContext(ctx, prefix ++ "a valid stream/context", .{});
    const own = r.get("__context");
    if (own == .resource) return own.resource;
    if (lookup == .existing) return null;
    const context = try ctx.createResource("StreamContext");
    try r.set(ctx.allocator, "__context", .{ .resource = context });
    return context;
}

fn throwContext(ctx: *NativeContext, comptime fmt: []const u8, args: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("TypeError", msg);
    return error.RuntimeError;
}

fn contextOptions(ctx: *NativeContext, context: *PhpObject) RuntimeError!*PhpArray {
    const options = context.get("options");
    return if (options == .array) options.array else ctx.createArray();
}

fn freshArray(ctx: *NativeContext, existing: Value) RuntimeError!*PhpArray {
    return if (existing == .array) ctx.vm.cloneArray(existing.array) else ctx.createArray();
}

fn mergeContextOptions(ctx: *NativeContext, context: *PhpObject, options: *PhpArray) RuntimeError!void {
    const merged = try freshArray(ctx, context.get("options"));
    for (options.entries.items) |entry| {
        const wrapper_options = if (entry.ref) |cell| cell.* else entry.value;
        if (wrapper_options != .array) {
            try ctx.vm.setPendingException("ValueError", "Options should have the form [\"wrappername\"][\"optionname\"] = $value");
            return error.RuntimeError;
        }
        const wrapper = try freshArray(ctx, merged.get(entry.key));
        for (wrapper_options.array.entries.items) |option| {
            try ctx.vm.arraySetOwned(wrapper, option.key, if (option.ref) |cell| cell.* else option.value);
        }
        try ctx.vm.arraySetOwned(merged, entry.key, .{ .array = wrapper });
    }
    try context.set(ctx.allocator, "options", .{ .array = merged });
}

fn applyContextParams(ctx: *NativeContext, context: *PhpObject, params: *PhpArray) RuntimeError!void {
    const notification = params.get(.{ .string = Value.String.borrowed("notification") });
    if (notification != .null) try context.set(ctx.allocator, "notification", notification);
    const options = params.get(.{ .string = Value.String.borrowed("options") });
    if (options == .array) try mergeContextOptions(ctx, context, options.array);
}

fn native_gethostbyname(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const host = args[0].string.bytes();
    var list = net.getAddressList(ctx.allocator, host, 0) catch return NativeResult.share(args[0]);
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
    var list = net.getAddressList(ctx.allocator, host, 0) catch return NativeResult.scalar(.{ .bool = false });
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
    if (net.Address.parseIp4(s, 0)) |addr| {
        const bytes = std.mem.toBytes(addr.in.sa.addr);
        return NativeResult.copyString(ctx.allocator, &bytes);
    } else |_| {}
    // try IPv6
    if (net.Address.parseIp6(s, 0)) |addr| {
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
        const ip = net.Address.initIp6(addr, 0, 0, 0);
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

// a transport address as stream_socket_client/server take it
const Endpoint = union(enum) {
    tcp: net.Address,
    unix: []const u8,
};

const SocketError = struct { code: i64, message: []const u8 };

// errno values and strerror text for the failures sockets report
fn socketError(err: anyerror) SocketError {
    const E = std.posix.E;
    const mac = @import("builtin").os.tag.isDarwin();
    return switch (err) {
        error.AddressInUse => .{ .code = @intFromEnum(E.ADDRINUSE), .message = "Address already in use" },
        error.ConnectionRefused => .{ .code = @intFromEnum(E.CONNREFUSED), .message = "Connection refused" },
        error.AccessDenied, error.PermissionDenied => .{ .code = @intFromEnum(E.ACCES), .message = "Permission denied" },
        error.NetworkUnreachable => .{ .code = @intFromEnum(E.NETUNREACH), .message = "Network is unreachable" },
        error.AddressNotAvailable => .{ .code = @intFromEnum(E.ADDRNOTAVAIL), .message = "Can't assign requested address" },
        error.ConnectionTimedOut, error.Timeout => .{ .code = @intFromEnum(E.TIMEDOUT), .message = if (mac) "Operation timed out" else "Connection timed out" },
        error.FileNotFound => .{ .code = @intFromEnum(E.NOENT), .message = "No such file or directory" },
        error.UnknownHostName, error.HostNotFound => .{ .code = 0, .message = "php_network_getaddresses: getaddrinfo failed" },
        else => .{ .code = 0, .message = @errorName(err) },
    };
}

// tcp://host:port (the default transport), [v6]:port, unix:///path
fn parseEndpoint(allocator: std.mem.Allocator, target: []const u8) !Endpoint {
    var scheme: []const u8 = "tcp";
    var rest = target;
    if (std.mem.indexOf(u8, target, "://")) |idx| {
        scheme = target[0..idx];
        rest = target[idx + 3 ..];
    }
    if (std.ascii.eqlIgnoreCase(scheme, "unix")) return .{ .unix = rest };
    if (!std.ascii.eqlIgnoreCase(scheme, "tcp")) return error.UnsupportedTransport;
    const colon = std.mem.lastIndexOfScalar(u8, rest, ':') orelse return error.MissingPort;
    var host = rest[0..colon];
    const port = std.fmt.parseUnsigned(u16, rest[colon + 1 ..], 10) catch return error.MissingPort;
    if (host.len >= 2 and host[0] == '[' and host[host.len - 1] == ']') host = host[1 .. host.len - 1];
    if (net.Address.parseIp(host, port)) |addr| return .{ .tcp = addr } else |_| {}
    const list = try net.getAddressList(allocator, host, port);
    defer list.deinit();
    if (list.addrs.len == 0) return error.UnknownHostName;
    return .{ .tcp = list.addrs[0] };
}

fn endpointAddress(endpoint: Endpoint) !net.Address {
    return switch (endpoint) {
        .tcp => |addr| addr,
        .unix => |path| net.Address.initUnix(path),
    };
}

fn newSocket(family: u32) !std.posix.socket_t {
    if (family == std.posix.AF.UNIX) return sys.socket(family, if (platform.is_windows) std.posix.SOCK.STREAM else std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC, 0);
    return platform.tcpSocket(family);
}

// connects, waiting at most timeout_ms (null blocks); async leaves the
// connection in progress on a non-blocking socket, as STREAM_CLIENT_ASYNC_CONNECT does
fn connectSocket(addr: net.Address, timeout_ms: ?i32, async_connect: bool) !std.posix.socket_t {
    const sock = try newSocket(addr.any.family);
    errdefer platform.closeSocket(platform.socketToInt(sock));
    if (!async_connect and timeout_ms == null) {
        try sys.connect(sock, &addr.any, addr.getOsSockLen());
        return sock;
    }
    try platform.setNonBlocking(sock, true);
    sys.connect(sock, &addr.any, addr.getOsSockLen()) catch |err| switch (err) {
        error.WouldBlock, error.ConnectionPending => {},
        else => return err,
    };
    if (async_connect) return sock;
    var fds = [_]sys.pollfd{.{ .fd = sock, .events = sys.POLL.OUT, .revents = 0 }};
    if (try sys.poll(&fds, timeout_ms.?) == 0) return error.ConnectionTimedOut;
    try platform.connectResult(sock);
    try platform.setNonBlocking(sock, false);
    return sock;
}

fn timeoutMs(ctx: *NativeContext, v: ?Value) ?i32 {
    const seconds: f64 = if (v) |t| (if (t == .null) defaultSocketTimeout(ctx) else Value.toFloat(t)) else defaultSocketTimeout(ctx);
    if (!(seconds >= 0)) return null;
    return @intFromFloat(@min(seconds * 1000.0, @as(f64, std.math.maxInt(i32))));
}

fn defaultSocketTimeout(ctx: *NativeContext) f64 {
    const v = ctx.vm.ini_settings.get("default_socket_timeout") orelse return 60;
    return std.fmt.parseFloat(f64, v) catch 60;
}

// the by-reference $error_code / $error_message outputs; unconnected they
// read 0 and ""
fn reportSocketError(ctx: *NativeContext, args: []const Value, code_index: usize, err: ?SocketError) !void {
    const e = err orelse SocketError{ .code = 0, .message = "" };
    ctx.setCallerVar(code_index, args.len, .{ .int = e.code });
    const message = try Value.String.create(ctx.allocator, e.message);
    defer message.release();
    ctx.setCallerVar(code_index + 1, args.len, .{ .string = message });
}

fn failConnect(ctx: *NativeContext, args: []const Value, code_index: usize, comptime func: []const u8, target: []const u8, err: anyerror) RuntimeError!NativeResult {
    const e = socketError(err);
    try reportSocketError(ctx, args, code_index, e);
    // php had already made the stream when the connect failed, so its id is gone
    ctx.vm.skipResourceId();
    const msg = try std.fmt.allocPrint(ctx.allocator, func ++ "(): Unable to connect to {s} ({s})", .{ target, e.message });
    defer ctx.allocator.free(msg);
    try ctx.vm.emitWarning(msg);
    return NativeResult.scalar(.{ .bool = false });
}

fn endpointStream(ctx: *NativeContext, sock: std.posix.socket_t, endpoint: Endpoint, blocking: bool, uri: ?[]const u8) !*PhpObject {
    const obj = try socketStream(ctx, sock);
    if (uri) |u| try obj.setCopiedString(ctx.allocator, "__path", u);
    try obj.set(ctx.allocator, "__sock_type", .{ .string = Value.String.borrowed(if (endpoint == .unix) "unix_socket" else "tcp_socket/ssl") });
    if (!blocking) try obj.set(ctx.allocator, "__blocking", .{ .bool = false });
    return obj;
}

fn native_fsockopen(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const host = args[0].string.bytes();
    const port: i64 = if (args.len >= 2 and args[1] != .null) Value.toInt(args[1]) else -1;
    const target = if (port >= 0)
        try std.fmt.allocPrint(ctx.allocator, "{s}:{d}", .{ host, port })
    else
        try ctx.allocator.dupe(u8, host);
    defer ctx.allocator.free(target);
    return connectStream(ctx, args, 2, target, if (args.len > 4) args[4] else null, false, "fsockopen");
}

// stream_socket_client(string $address, &$error_code, &$error_message, ?float $timeout, int $flags, $context)
fn native_stream_socket_client(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const flags: i64 = if (args.len > 4) Value.toInt(args[4]) else 4;
    _ = try streamContext(ctx, if (args.len > 5) args[5] else null);
    return connectStream(ctx, args, 1, args[0].string.bytes(), if (args.len > 3) args[3] else null, (flags & 2) != 0, "stream_socket_client");
}

fn connectStream(ctx: *NativeContext, args: []const Value, code_index: usize, target: []const u8, timeout: ?Value, async_connect: bool, comptime func: []const u8) RuntimeError!NativeResult {
    const endpoint = parseEndpoint(ctx.allocator, target) catch |err| return failConnect(ctx, args, code_index, func, target, err);
    const addr = endpointAddress(endpoint) catch |err| return failConnect(ctx, args, code_index, func, target, err);
    const sock = connectSocket(addr, timeoutMs(ctx, timeout), async_connect) catch |err| return failConnect(ctx, args, code_index, func, target, err);
    try reportSocketError(ctx, args, code_index, null);
    return NativeResult.borrowed(.{ .resource = try endpointStream(ctx, sock, endpoint, !async_connect, target) });
}

// stream_socket_server(string $address, &$error_code, &$error_message, int $flags = BIND|LISTEN, $context)
fn native_stream_socket_server(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const target = args[0].string.bytes();
    const flags: i64 = if (args.len > 3) Value.toInt(args[3]) else 12;
    const context = try streamContext(ctx, if (args.len > 4) args[4] else null);
    const endpoint = parseEndpoint(ctx.allocator, target) catch |err| return failConnect(ctx, args, 1, "stream_socket_server", target, err);
    const sock = listenSocket(endpoint, flags, contextBacklog(context)) catch |err| return failConnect(ctx, args, 1, "stream_socket_server", target, err);
    try reportSocketError(ctx, args, 1, null);
    const obj = try endpointStream(ctx, sock, endpoint, true, target);
    try obj.set(ctx.allocator, "__server", .{ .bool = true });
    return NativeResult.borrowed(.{ .resource = obj });
}

fn listenSocket(endpoint: Endpoint, flags: i64, backlog: u31) !std.posix.socket_t {
    const addr = try endpointAddress(endpoint);
    const sock = try newSocket(addr.any.family);
    errdefer platform.closeSocket(platform.socketToInt(sock));
    // php sets it on every platform; on windows that lets a second server
    // take a port that is already bound, which php allows there too
    if (endpoint == .tcp) try sys.setsockopt(sock, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
    if ((flags & 4) != 0) try sys.bind(sock, &addr.any, addr.getOsSockLen());
    if ((flags & 8) != 0) try sys.listen(sock, backlog);
    return sock;
}

// the context's socket.backlog option, php's default otherwise
fn contextBacklog(context: *PhpObject) u31 {
    const options = context.get("options");
    if (options != .array) return 32;
    const socket_opts = options.array.get(.{ .string = Value.String.borrowed("socket") });
    if (socket_opts != .array) return 32;
    const backlog = socket_opts.array.get(.{ .string = Value.String.borrowed("backlog") });
    if (backlog == .null) return 32;
    return @intCast(std.math.clamp(Value.toInt(backlog), 1, std.math.maxInt(u31)));
}

// stream_socket_accept($socket, ?float $timeout = null, &$peer_name): a new
// stream for the next connection, or false once the timeout passes
fn native_stream_socket_accept(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const listener = try filesystem.streamArg(ctx, args, .{ .func = "stream_socket_accept", .param = "socket" });
    const server = platform.socketFromInt(objectFd(listener) orelse return NativeResult.scalar(.{ .bool = false })) orelse return NativeResult.scalar(.{ .bool = false });
    var fds = [_]sys.pollfd{.{ .fd = server, .events = sys.POLL.IN, .revents = 0 }};
    const ready = sys.poll(&fds, timeoutMs(ctx, if (args.len > 1) args[1] else null) orelse -1) catch 0;
    if (ready == 0) {
        try ctx.vm.emitWarning("stream_socket_accept(): Accept failed: " ++ comptime socketError(error.Timeout).message);
        return NativeResult.scalar(.{ .bool = false });
    }
    var peer: net.Address = undefined;
    var len: std.posix.socklen_t = @sizeOf(net.Address);
    const sock = sys.accept(server, &peer.any, &len, if (platform.is_windows) 0 else std.posix.SOCK.CLOEXEC) catch |err| {
        const msg = try std.fmt.allocPrint(ctx.allocator, "stream_socket_accept(): Accept failed: {s}", .{socketError(err).message});
        defer ctx.allocator.free(msg);
        try ctx.vm.emitWarning(msg);
        return NativeResult.scalar(.{ .bool = false });
    };
    // the connection keeps whatever mode the OS gives it: BSDs and windows
    // inherit the listener's non-blocking mode, linux does not. php reports
    // that real mode
    const listener_blocks = listener.get("__blocking") != .bool or listener.get("__blocking").bool;
    const is_unix = peer.any.family == std.posix.AF.UNIX;
    const obj = try endpointStream(ctx, sock, if (is_unix) .{ .unix = "" } else .{ .tcp = peer }, platform.isBlocking(sock, listener_blocks), null);
    if (args.len > 2) {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const name = try Value.String.create(ctx.allocator, addressName(&buf, peer, len));
        defer name.release();
        ctx.setCallerVar(2, args.len, .{ .string = name });
    }
    return NativeResult.borrowed(.{ .resource = obj });
}

// stream_socket_get_name($socket, bool $remote): "host:port", a unix path,
// or false when there is no such end
fn native_stream_socket_get_name(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const stream = try filesystem.streamArg(ctx, args, .{ .func = "stream_socket_get_name", .param = "socket" });
    const sock = platform.socketFromInt(objectFd(stream) orelse return NativeResult.scalar(.{ .bool = false })) orelse return NativeResult.scalar(.{ .bool = false });
    const remote = args.len > 1 and args[1].isTruthy();
    var addr: net.Address = undefined;
    var len: std.posix.socklen_t = @sizeOf(net.Address);
    // not connected (a listener asked for its peer) is an answer, not a fault
    const rc = if (remote) std.c.getpeername(sock, &addr.any, &len) else std.c.getsockname(sock, &addr.any, &len);
    if (rc != 0) return NativeResult.scalar(.{ .bool = false });
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    return NativeResult.copyString(ctx.allocator, addressName(&buf, addr, len));
}

fn addressName(buf: []u8, addr: net.Address, len: std.posix.socklen_t) []const u8 {
    if (addr.any.family == std.posix.AF.UNIX) {
        const path_len = @as(usize, len) -| @offsetOf(std.posix.sockaddr.un, "path");
        return std.mem.sliceTo(addr.un.path[0..@min(path_len, addr.un.path.len)], 0);
    }
    return std.fmt.bufPrint(buf, "{f}", .{addr}) catch "";
}

// stream_socket_shutdown($stream, int $mode): STREAM_SHUT_RD, _WR or _RDWR
fn native_stream_socket_shutdown(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const stream = try filesystem.streamArg(ctx, args, .{ .func = "stream_socket_shutdown" });
    const sock = platform.socketFromInt(objectFd(stream) orelse return NativeResult.scalar(.{ .bool = false })) orelse return NativeResult.scalar(.{ .bool = false });
    const how: sys.ShutdownHow = switch (if (args.len > 1) Value.toInt(args[1]) else 2) {
        0 => .recv,
        1 => .send,
        else => .both,
    };
    sys.shutdown(sock, how) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn native_checkdnsrr(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    var list = net.getAddressList(ctx.allocator, args[0].string.bytes(), 0) catch return NativeResult.scalar(.{ .bool = false });
    defer list.deinit();
    return NativeResult.scalar(.{ .bool = list.addrs.len > 0 });
}

fn native_dns_get_record(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const result = try ctx.createArray();
    var list = net.getAddressList(ctx.allocator, args[0].string.bytes(), 0) catch return NativeResult.borrowed(.{ .array = result });
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
