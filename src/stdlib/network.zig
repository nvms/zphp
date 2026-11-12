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
const streams = @import("streams.zig");
const user_streams = @import("user_streams.zig");
const value_mod = @import("../runtime/value.zig");
const Args = @import("string_ports.zig").Args;

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
    .{ "stream_context_set_options", native_stream_context_set_options_array },
    .{ "stream_context_set_option", native_stream_context_set_options },
    .{ "stream_context_set_params", native_stream_context_set_params },
    .{ "stream_context_get_default", native_stream_context_get_default },
    .{ "stream_context_set_default", native_stream_context_set_default },
    .{ "checkdnsrr", native_checkdnsrr },
    .{ "dns_check_record", native_checkdnsrr },
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
    key: PhpArray.Key,
    val: Value,
    fd: i64,
    poll_index: ?usize,
    ready: bool = false,
};

const WatchList = std.ArrayListUnmanaged(Watched);
const PollList = std.ArrayListUnmanaged(sys.pollfd);

// stream_select(&$read, &$write, &$except, ?int $seconds, ?int $microseconds = null): int|false
// waits on the streams in each (by-ref) array and rewrites each array to the
// ready subset, keys kept, returning the number ready (false on error). null
// $seconds blocks. a read stream with data in its buffer is ready at once
fn native_stream_select(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    var watched: WatchList = .empty;
    defer watched.deinit(ctx.allocator);
    var pollfds: PollList = .empty;
    defer pollfds.deinit(ctx.allocator);

    const sets = try watchStreams(ctx, args, &watched, &pollfds);
    if (sets == 0) {
        try ctx.vm.setPendingException("ValueError", "No stream arrays were passed");
        return error.RuntimeError;
    }

    const sec_null = args.len < 4 or args[3] == .null;
    const usec_null = args.len < 5 or args[4] == .null;
    const sec: i64 = if (!sec_null) Value.toInt(args[3]) else 0;
    const usec: i64 = if (!usec_null) Value.toInt(args[4]) else 0;
    if (sec_null and !usec_null and usec != 0) {
        try ctx.vm.setPendingException("ValueError", "stream_select(): Argument #5 ($microseconds) must be null when argument #4 ($seconds) is null");
        return error.RuntimeError;
    }
    if (!sec_null) {
        if (sec < 0) {
            try ctx.vm.setPendingException("ValueError", "stream_select(): Argument #4 ($seconds) must be greater than or equal to 0");
            return error.RuntimeError;
        } else if (usec < 0) {
            try ctx.vm.setPendingException("ValueError", "stream_select(): Argument #5 ($microseconds) must be greater than or equal to 0");
            return error.RuntimeError;
        }
    }

    // read streams with buffered data are ready without waiting
    if (args.len > 0 and args[0] == .array) {
        const ready = try ctx.createArray();
        var count: i64 = 0;
        for (args[0].array.entries.items) |entry| {
            const v = if (entry.ref) |r| r.* else entry.value;
            if (v != .resource or !std.mem.eql(u8, v.resource.class_name, "FileHandle")) continue;
            const st = streams.get(v.resource) orelse continue;
            if (st.buffered() == 0) continue;
            try ready.set(ctx.allocator, entry.key, v);
            count += 1;
        }
        if (count > 0) {
            ctx.setCallerVar(0, args.len, .{ .array = ready });
            var slot: usize = 1;
            while (slot < 3) : (slot += 1) {
                if (slot < args.len and args[slot] == .array) ctx.setCallerVar(slot, args.len, .{ .array = try ctx.createArray() });
            }
            return NativeResult.scalar(.{ .int = count });
        }
    }

    const timeout_ms: i32 = if (sec_null) -1 else @intCast(@min(std.math.maxInt(i32), @max(0, sec *| 1000 +| @divTrunc(usec, 1000))));
    // what the script printed is out before it waits, as php's cli has it
    if (timeout_ms != 0) ctx.vm.flushOutputToStdout();
    awaitReady(watched.items, pollfds.items, timeout_ms) catch return NativeResult.scalar(.{ .bool = false });

    var count: i64 = 0;
    var slot: usize = 0;
    while (slot < 3) : (slot += 1) {
        if (slot >= args.len or args[slot] != .array) continue;
        const arr = try ctx.createArray();
        for (watched.items) |w| {
            if (w.slot != slot) continue;
            // php casts each stream again as it builds the result
            if (try selectDescriptor(ctx, w.val.resource, false) == null) continue;
            if (!w.ready) continue;
            try arr.set(ctx.allocator, w.key, w.val);
            count += 1;
        }
        ctx.setCallerVar(slot, args.len, .{ .array = arr });
    }
    return NativeResult.scalar(.{ .int = count });
}

// php_stream_cast(PHP_STREAM_AS_FD_FOR_SELECT): the descriptor select waits
// on, through a user stream's stream_cast; php's warning for a stream that
// has none
pub fn selectDescriptor(ctx: *NativeContext, obj: *PhpObject, report: bool) RuntimeError!?i64 {
    if (!std.mem.eql(u8, obj.class_name, "FileHandle") or value_mod.resourceClosed(obj)) return null;
    const st = streams.get(obj);
    if (st) |s_| if (s_.readfilters.head != null or s_.writefilters.head != null) {
        try filesystem.warnDocref(ctx, "Cannot cast a filtered stream on this system", .{});
        return null;
    };
    if (filesystem.fileHandleWrapper(obj)) |w| {
        if (try user_streams.cast(ctx, obj, w, user_streams.CAST_FOR_SELECT, true)) |inner| {
            if (try selectDescriptor(ctx, inner, report)) |fd| return fd;
        }
        try filesystem.warnDocref(ctx, "Cannot represent a stream of type user-space as a select()able descriptor", .{});
        return null;
    }
    if (streams.memoryOf(obj) != null) {
        const path = obj.get("__path");
        const label: []const u8 = if (path == .string and std.ascii.startsWithIgnoreCase(path.string.bytes(), "php://temp")) "TEMP" else if (path == .string and std.ascii.startsWithIgnoreCase(path.string.bytes(), "php://memory")) "MEMORY" else "RFC2397";
        try filesystem.warnDocref(ctx, "Cannot represent a stream of type {s} as a select()able descriptor", .{label});
        return null;
    }
    return objectFd(obj);
}

// the streams of each set with their descriptors; the count of sets that
// had at least one
fn watchStreams(ctx: *NativeContext, args: []const Value, watched: *WatchList, pollfds: *PollList) !usize {
    var sets: usize = 0;
    var slot: usize = 0;
    while (slot < 3) : (slot += 1) {
        if (slot >= args.len or args[slot] != .array) continue;
        var any = false;
        for (args[slot].array.entries.items) |entry| {
            const v = if (entry.ref) |r| r.* else entry.value;
            if (v != .resource) continue;
            const fd = (try selectDescriptor(ctx, v.resource, true)) orelse continue;
            any = true;
            var poll_index: ?usize = null;
            if (!platform.is_windows or isNetStream(v)) {
                const sock = platform.socketFromInt(fd) orelse continue;
                poll_index = pollfds.items.len;
                try pollfds.append(ctx.allocator, .{ .fd = sock, .events = poll_events[slot], .revents = 0 });
            }
            try watched.append(ctx.allocator, .{ .slot = @intCast(slot), .key = entry.key, .val = v, .fd = fd, .poll_index = poll_index });
        }
        if (any) sets += 1;
    }
    return sets;
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
    const options = try optionalArray(ctx, args, 0, "stream_context_create", "options");
    const params = try optionalArray(ctx, args, 1, "stream_context_create", "params");
    const context = try ctx.createResource("StreamContext");
    if (options) |o| try mergeContextOptions(ctx, context, o);
    if (params) |p| try applyContextParams(ctx, context, p, "stream_context_create(): Argument #1 ($options)");
    return NativeResult.borrowed(.{ .resource = context });
}

// a ?array parameter: null when absent or null, php's TypeError otherwise
fn optionalArray(ctx: *NativeContext, args: []const Value, index: usize, comptime func: []const u8, comptime name: []const u8) RuntimeError!?*PhpArray {
    if (index >= args.len or args[index] == .null) return null;
    if (args[index] == .array) return args[index].array;
    return throwContext(ctx, func ++ "(): Argument #{d} ($" ++ name ++ ") must be of type ?array, {s} given", .{ index + 1, args[index].valueName() });
}

fn native_stream_context_get_options(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const context = (try contextArg(ctx, args, "stream_context_get_options", .create)).?;
    return NativeResult.borrowed(.{ .array = try contextOptions(ctx, context) });
}

fn native_stream_context_get_params(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const result = try ctx.createArray();
    const context = (try contextArg(ctx, args, "stream_context_get_params", .create)).?;
    const notification = context.get("notification");
    if (notification != .null) try ctx.vm.arraySetOwned(result, .{ .string = Value.String.borrowed("notification") }, notification);
    const options = try contextOptions(ctx, context);
    try ctx.vm.arraySetOwned(result, .{ .string = Value.String.borrowed("options") }, .{ .array = options });
    return NativeResult.borrowed(.{ .array = result });
}

// stream_context_set_option($context, $wrapper, $option, $value), or the
// deprecated array form; stream_context_set_options($context, $options)
fn native_stream_context_set_options(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 2) {
        try ctx.vm.raiseError(8192, "Calling stream_context_set_option() with 2 arguments is deprecated, use stream_context_set_options() instead");
        if (ctx.vm.pending_exception != null) return error.RuntimeError;
    }
    const v1: Value = if (args.len > 1) args[1] else .null;
    if (v1 != .array and v1 != .string) return throwContext(ctx, "stream_context_set_option(): Argument #2 ($wrapper_or_options) must be of type array|string, {s} given", .{v1.valueName()});
    const context = (try contextArg(ctx, args, "stream_context_set_option", .create)).?;
    const option_name: Value = if (args.len > 2) args[2] else .null;
    if (v1 == .array) {
        if (option_name != .null) return throwValue(ctx, "stream_context_set_option(): Argument #3 ($option_name) must be null when argument #2 ($wrapper_or_options) is an array");
        if (args.len > 3) return throwValue(ctx, "stream_context_set_option(): Argument #4 ($value) cannot be provided when argument #2 ($wrapper_or_options) is an array");
        try mergeContextOptions(ctx, context, v1.array);
        return NativeResult.scalar(.{ .bool = true });
    }
    if (option_name == .null) return throwValue(ctx, "stream_context_set_option(): Argument #3 ($option_name) cannot be null when argument #2 ($wrapper_or_options) is a string");
    if (args.len < 4) return throwValue(ctx, "stream_context_set_option(): Argument #4 ($value) must be provided when argument #2 ($wrapper_or_options) is a string");
    const name = try (@import("html.zig").Params{ .ctx = ctx, .func = "stream_context_set_option", .args = args }).string(2, "option_name", "");
    try setContextOption(ctx, context, v1.string.bytes(), name, args[3]);
    return NativeResult.scalar(.{ .bool = true });
}

fn native_stream_context_set_options_array(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const context = (try contextArg(ctx, args, "stream_context_set_options", .create)).?;
    if (args.len < 2 or args[1] != .array) return throwContext(ctx, "stream_context_set_options(): Argument #2 ($options) must be of type array, {s} given", .{if (args.len > 1) args[1].valueName() else "null"});
    try mergeContextOptions(ctx, context, args[1].array);
    return NativeResult.scalar(.{ .bool = true });
}

fn throwValue(ctx: *NativeContext, msg: []const u8) RuntimeError {
    try ctx.vm.setPendingException("ValueError", msg);
    return error.RuntimeError;
}

// php_stream_context_set_option: options[wrapper][option] = value
fn setContextOption(ctx: *NativeContext, context: *PhpObject, wrapper_name: []const u8, option: []const u8, value: Value) RuntimeError!void {
    const merged = try freshArray(ctx, context.get("options"));
    const wkey = try Value.String.adopt(ctx.allocator, try ctx.allocator.dupe(u8, wrapper_name));
    defer wkey.release();
    const wrapper_key = PhpArray.Key{ .string = wkey };
    const wrapper = try freshArray(ctx, merged.get(wrapper_key));
    const okey = try Value.String.adopt(ctx.allocator, try ctx.allocator.dupe(u8, option));
    defer okey.release();
    try ctx.vm.arraySetOwned(wrapper, .{ .string = okey }, value);
    try ctx.vm.arraySetOwned(merged, wrapper_key, .{ .array = wrapper });
    try context.set(ctx.allocator, "options", .{ .array = merged });
}

fn native_stream_context_set_params(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const context = (try contextArg(ctx, args, "stream_context_set_params", .create)).?;
    if (args.len < 2 or args[1] != .array) return throwContext(ctx, "stream_context_set_params(): Argument #2 ($params) must be of type array, {s} given", .{if (args.len > 1) args[1].valueName() else "null"});
    try applyContextParams(ctx, context, args[1].array, "stream_context_set_params(): Argument #1 ($context)");
    return NativeResult.scalar(.{ .bool = true });
}

fn native_stream_context_get_default(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const options = try optionalArray(ctx, args, 0, "stream_context_get_default", "options");
    const context = try defaultContext(ctx);
    if (options) |o| try mergeContextOptions(ctx, context, o);
    return NativeResult.borrowed(.{ .resource = context });
}

fn native_stream_context_set_default(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .array) return throwContext(ctx, "stream_context_set_default(): Argument #1 ($options) must be of type array, {s} given", .{if (args.len > 0) args[0].valueName() else "null"});
    const context = try defaultContext(ctx);
    try mergeContextOptions(ctx, context, args[0].array);
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

// decode_context_param: a context, or the context of a stream (made on
// demand when .create); php's TypeError for anything else
fn contextArg(ctx: *NativeContext, args: []const Value, comptime func: []const u8, lookup: ContextLookup) RuntimeError!?*PhpObject {
    const v: Value = if (args.len > 0) args[0] else .null;
    const param = comptime if (std.mem.eql(u8, func, "stream_context_set_params") or std.mem.eql(u8, func, "stream_context_set_options") or std.mem.eql(u8, func, "stream_context_get_params")) "context" else "stream_or_context";
    if (v != .resource) return throwContext(ctx, func ++ "(): Argument #1 ($" ++ param ++ ") must be of type resource, {s} given", .{v.valueName()});
    const r = v.resource;
    if (std.mem.eql(u8, r.class_name, "StreamContext") and !@import("../runtime/value.zig").resourceClosed(r)) return r;
    if (!std.mem.eql(u8, r.class_name, "FileHandle") or @import("../runtime/value.zig").resourceClosed(r)) return throwContext(ctx, func ++ "(): Argument #1 ($" ++ param ++ ") must be a valid stream/context", .{});
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

// parse_context_options: each wrapper's options (a list is skipped), or
// php's ValueError for an entry that isn't a named array
fn mergeContextOptions(ctx: *NativeContext, context: *PhpObject, options: *PhpArray) RuntimeError!void {
    for (options.entries.items) |entry| {
        const wrapper_options = if (entry.ref) |cell| cell.* else entry.value;
        if (entry.key != .string or wrapper_options != .array) {
            try ctx.vm.setPendingException("ValueError", "Options should have the form [\"wrappername\"][\"optionname\"] = $value");
            return error.RuntimeError;
        }
        if (isPacked(wrapper_options.array)) continue;
        for (wrapper_options.array.entries.items) |option| {
            if (option.key != .string) continue;
            try setContextOption(ctx, context, entry.key.string.bytes(), option.key.string.bytes(), if (option.ref) |cell| cell.* else option.value);
        }
    }
}

// HT_IS_PACKED: the keys are 0, 1, 2... (an empty array included)
fn isPacked(arr: *PhpArray) bool {
    for (arr.entries.items, 0..) |e, i| {
        if (e.key != .int or e.key.int != @as(i64, @intCast(i))) return false;
    }
    return true;
}

// parse_context_params: a notification callback, checked; options merged.
// a bad callback is blamed on the calling function's first argument, as
// zend_argument_type_error(1, ...) does
fn applyContextParams(ctx: *NativeContext, context: *PhpObject, params: *PhpArray, comptime arg1: []const u8) RuntimeError!void {
    const nkey: PhpArray.Key = .{ .string = Value.String.borrowed("notification") };
    if (params.contains(nkey)) {
        const notification = params.get(nkey);
        const callables = @import("../runtime/callables.zig");
        switch (try callables.resolveCallback(ctx.vm, notification, .{})) {
            .failure => |f| {
                var buf: std.ArrayListUnmanaged(u8) = .empty;
                defer buf.deinit(ctx.allocator);
                try buf.appendSlice(ctx.allocator, arg1 ++ " must be an array with valid callbacks as values, ");
                try callables.writeReason(f, &buf, ctx.allocator);
                try ctx.vm.setPendingException("TypeError", buf.items);
                return error.RuntimeError;
            },
            .callee => {},
        }
        try context.set(ctx.allocator, "notification", notification);
    }
    const okey: PhpArray.Key = .{ .string = Value.String.borrowed("options") };
    if (params.contains(okey)) {
        const options = params.get(okey);
        if (options != .array) {
            try ctx.vm.setPendingException("TypeError", "Invalid stream/context parameter");
            return error.RuntimeError;
        }
        try mergeContextOptions(ctx, context, options.array);
    }
}

fn native_gethostbyname(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const host = try Args.init(ctx, "gethostbyname", args).path(0, "hostname");
    if (host.len > max_fqdn_len) {
        try filesystem.warnDocref(ctx, "Host name cannot be longer than {d} characters", .{max_fqdn_len});
        return NativeResult.share(args[0]);
    }
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
    const host = try Args.init(ctx, "gethostbynamel", args).path(0, "hostname");
    if (host.len > max_fqdn_len) {
        try filesystem.warnDocref(ctx, "Host name cannot be longer than {d} characters", .{max_fqdn_len});
        return NativeResult.scalar(.{ .bool = false });
    }
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

extern "c" fn getnameinfo(sa: *const anyopaque, salen: u32, host: [*]u8, hostlen: u32, serv: ?[*]u8, servlen: u32, flags: c_int) c_int;

// php_gethostbyaddr: an address inet_pton doesn't take is a warning, one
// without a name comes back as given
fn native_gethostbyaddr(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const ip = try Args.init(ctx, "gethostbyaddr", args).path(0, "ip");
    const addr = net.Address.parseIp6(ip, 0) catch net.Address.parseIp4(ip, 0) catch {
        try filesystem.warnDocref(ctx, "Address is not a valid IPv4 or IPv6 address", .{});
        return NativeResult.scalar(.{ .bool = false });
    };
    if (!platform.is_windows) {
        var host: [1025]u8 = undefined;
        // NI_NAMEREQD
        if (getnameinfo(&addr.any, addr.getOsSockLen(), &host, host.len, null, 0, 8) == 0) {
            return NativeResult.copyString(ctx.allocator, std.mem.sliceTo(&host, 0));
        }
    }
    return NativeResult.copyString(ctx.allocator, ip);
}

// MAXFQDNLEN: longer names never reach the resolver (CVE-2015-0235)
const max_fqdn_len = 255;

fn native_gethostname(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    var buf: [256]u8 = undefined;
    const name = platform.hostname(&buf) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.copyString(ctx.allocator, name);
}

fn native_inet_pton(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const s = try Args.init(ctx, "inet_pton", args).path(0, "ip");
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

// inet_pton(AF_INET): four decimal parts of at most 255, no leading zeros
fn inetPton4(s: []const u8) ?u32 {
    var value: u32 = 0;
    var parts: usize = 0;
    var i: usize = 0;
    while (true) {
        const start = i;
        var part: u32 = 0;
        while (i < s.len and std.ascii.isDigit(s[i])) : (i += 1) {
            part = part * 10 + (s[i] - '0');
            if (part > 255 or i - start > 2) return null;
        }
        if (i == start) return null;
        if (s[start] == '0' and i - start > 1) return null;
        value = (value << 8) | part;
        parts += 1;
        if (i == s.len) break;
        if (s[i] != '.' or parts == 4) return null;
        i += 1;
    }
    return if (parts == 4) value else null;
}

fn native_ip2long(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const ip = try Args.init(ctx, "ip2long", args).path(0, "ip");
    const value = inetPton4(ip) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = value });
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

// the host and port of a tcp target as php's parse_ip_address_ex reads
// them: "[v6]:port" or "host:port", the port as atoi takes it
fn parseEndpoint(allocator: std.mem.Allocator, target: []const u8) !Endpoint {
    var scheme: []const u8 = "tcp";
    var rest = target;
    if (std.mem.indexOf(u8, target, "://")) |idx| {
        scheme = target[0..idx];
        rest = target[idx + 3 ..];
    }
    if (std.ascii.eqlIgnoreCase(scheme, "unix")) return .{ .unix = rest };
    if (!std.ascii.eqlIgnoreCase(scheme, "tcp")) return error.UnsupportedTransport;
    if (std.mem.indexOfScalar(u8, rest, 0) != null) return error.NulInHostname;
    var host: []const u8 = undefined;
    var port_text: []const u8 = undefined;
    if (rest.len > 1 and rest[0] == '[') {
        const close = std.mem.indexOfScalar(u8, rest[1 .. rest.len - 1], ']') orelse return error.ParseIpv6Address;
        const p = close + 1;
        if (p + 1 >= rest.len or rest[p + 1] != ':') return error.ParseIpv6Address;
        host = rest[1..p];
        port_text = rest[p + 2 ..];
    } else {
        const colon = if (rest.len > 0) std.mem.indexOfScalar(u8, rest[0 .. rest.len - 1], ':') else null;
        const c = colon orelse return error.ParseAddress;
        host = rest[0..c];
        port_text = rest[c + 1 ..];
    }
    const port: u16 = @truncate(@as(u64, @bitCast(atoi(port_text))));
    if (net.Address.parseIp(host, port)) |addr| return .{ .tcp = addr } else |_| {}
    const list = try net.getAddressList(allocator, host, port);
    defer list.deinit();
    if (list.addrs.len == 0) return error.UnknownHostName;
    return .{ .tcp = list.addrs[0] };
}

fn atoi(s: []const u8) i64 {
    var i: usize = 0;
    while (i < s.len and std.ascii.isWhitespace(s[i])) i += 1;
    var neg = false;
    if (i < s.len and (s[i] == '-' or s[i] == '+')) {
        neg = s[i] == '-';
        i += 1;
    }
    var n: i64 = 0;
    while (i < s.len and std.ascii.isDigit(s[i])) : (i += 1) n = n *% 10 +% (s[i] - '0');
    return if (neg) -n else n;
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

pub fn defaultSocketTimeoutSeconds(ctx: *NativeContext) f64 {
    return defaultSocketTimeout(ctx);
}

// php_stream_xport_create for a client: the connected socket stream for a
// transport url ("tcp://host:port"), or null with why in the wrapper's
// error log
pub fn connectTransport(ctx: *NativeContext, target: []const u8, timeout_s: f64, options: i64) RuntimeError!?*PhpObject {
    const timeout_ms: ?i32 = if (timeout_s >= 0) @intFromFloat(@min(timeout_s * 1000.0, @as(f64, std.math.maxInt(i32)))) else null;
    const endpoint = parseEndpoint(ctx.allocator, target) catch |err| {
        try user_streams.logError(ctx, options, "{s}", .{socketError(err).message});
        return null;
    };
    const addr = endpointAddress(endpoint) catch |err| {
        try user_streams.logError(ctx, options, "{s}", .{socketError(err).message});
        return null;
    };
    const sock = connectSocket(addr, timeout_ms, false) catch |err| {
        // php made the stream before the connect failed
        ctx.vm.skipResourceId();
        try user_streams.logError(ctx, options, "{s}", .{socketError(err).message});
        return null;
    };
    return try endpointStream(ctx, sock, endpoint, true, null);
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
    var e = socketError(err);
    var owned: ?[]u8 = null;
    defer if (owned) |o| ctx.allocator.free(o);
    // php's parse failures name the address they couldn't read
    const rest = if (std.mem.indexOf(u8, target, "://")) |i| target[i + 3 ..] else target;
    switch (err) {
        error.ParseAddress => owned = try std.fmt.allocPrint(ctx.allocator, "Failed to parse address \"{s}\"", .{rest}),
        error.ParseIpv6Address => owned = try std.fmt.allocPrint(ctx.allocator, "Failed to parse IPv6 address \"{s}\"", .{rest}),
        error.NulInHostname => owned = try ctx.allocator.dupe(u8, "The hostname must not contain null bytes"),
        error.UnsupportedTransport => owned = try std.fmt.allocPrint(ctx.allocator, "Unable to find the socket transport \"{s}\" - did you forget to enable it when you configured PHP?", .{target[0 .. std.mem.indexOf(u8, target, "://") orelse 0]}),
        else => {},
    }
    if (owned) |o| e = .{ .code = 0, .message = o };
    try reportSocketError(ctx, args, code_index, e);
    // php had already made the stream when the connect failed, so its id is gone
    ctx.vm.skipResourceId();
    // stream_socket_client quotes the target with php_addslashes
    var quoted: std.ArrayListUnmanaged(u8) = .empty;
    defer quoted.deinit(ctx.allocator);
    if (comptime std.mem.eql(u8, func, "stream_socket_client")) {
        for (target) |c| switch (c) {
            0 => try quoted.appendSlice(ctx.allocator, "\\0"),
            '\'', '"', '\\' => try quoted.appendSlice(ctx.allocator, &.{ '\\', c }),
            else => try quoted.append(ctx.allocator, c),
        };
    } else if (comptime std.mem.eql(u8, func, "fsockopen")) {
        // php_fsockopen_stream names the host as a c string and the port
        const host = if (args[0] == .string) args[0].string.bytes() else "";
        const port: i64 = if (args.len >= 2 and args[1] != .null) Value.toInt(args[1]) else -1;
        try quoted.print(ctx.allocator, "{s}:{d}", .{ host[0 .. std.mem.indexOfScalar(u8, host, 0) orelse host.len], port });
    } else try quoted.appendSlice(ctx.allocator, target);
    const name = if (comptime std.mem.eql(u8, func, "fsockopen")) ctx.call_name orelse func else func;
    const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): Unable to connect to {s} ({s})", .{ name, quoted.items, e.message });
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
    if (args.len > 4 and args[4] != .null) {
        const timeout = Value.toFloat(args[4]);
        const top: f64 = @as(f64, @floatFromInt(std.math.maxInt(u64))) / 1000000.0;
        if (timeout != -1.0 and !(timeout >= 0.0 and timeout <= top)) {
            const name = ctx.call_name orelse "fsockopen";
            const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): Argument #5 ($timeout) must be -1 or between 0 and {d}", .{ name, @as(u64, @intFromFloat(top)) });
            defer ctx.allocator.free(msg);
            try ctx.vm.setPendingException("ValueError", msg);
            return error.RuntimeError;
        }
    }
    const target = if (port > 0)
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
    ctx.vm.flushOutputToStdout();
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
    // an unnamed socket (a unix client, an abstract name) has no name to give
    const name = addressName(&buf, addr, len);
    if (name.len == 0 or name[0] == 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.copyString(ctx.allocator, name);
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
    const name = ctx.call_name orelse "checkdnsrr";
    const p = Args.init(ctx, name, args);
    const host = try p.path(0, "hostname");
    if (host.len == 0) return p.valueError(0, "hostname", "must not be empty");
    if (args.len > 1) {
        const t = try p.str(1, "type");
        const types = [_][]const u8{ "A", "NS", "MX", "PTR", "ANY", "SOA", "CAA", "TXT", "CNAME", "AAAA", "SRV", "NAPTR", "A6" };
        var known = false;
        for (types) |k| if (std.ascii.eqlIgnoreCase(t, k)) {
            known = true;
        };
        if (!known) return p.valueError(1, "type", "must be a valid DNS record type");
    }
    var list = net.getAddressList(ctx.allocator, host, 0) catch return NativeResult.scalar(.{ .bool = false });
    defer list.deinit();
    return NativeResult.scalar(.{ .bool = list.addrs.len > 0 });
}

fn native_dns_get_record(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "dns_get_record", args);
    _ = try p.path(0, "hostname");
    const dns_type: i64 = if (args.len > 1) try p.long(1, "type") else 268435456;
    const raw_mode = args.len > 4 and try p.boolean(4, "raw", false);
    if (!raw_mode) {
        // PHP_DNS_ALL, and PHP_DNS_ANY on its own
        if ((dns_type & ~@as(i64, 251721779)) != 0 and dns_type != 268435456) return p.valueError(1, "type", "must be a DNS_* constant");
    } else if (dns_type < 1 or dns_type > 65535) {
        return p.valueError(1, "type", "must be between 1 and 65535 when argument #5 ($raw) is true");
    }
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
