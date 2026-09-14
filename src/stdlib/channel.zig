// a Zphp\Channel is a bounded queue of serialized values shared between
// threads by identity: every VM that holds one binds its own wrapper object
// to the same Channel, and a wrapper crosses to a worker as the channel's id
const std = @import("std");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const PhpObject = value_mod.PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const RuntimeError = error{ RuntimeError, OutOfMemory };
const workers = @import("workers.zig");
const platform = @import("../platform.zig");

pub const channel_class = "Zphp\\Channel";
const channel_exception = "Zphp\\ChannelException";
const timeout_exception = "Zphp\\TimeoutException";

// ---------------------------------------------------------------------------
// the shared queue

const Wait = union(enum) { none, forever, until: i128 };

fn waitFor(cond: *std.Thread.Condition, mutex: *std.Thread.Mutex, wait: Wait) bool {
    switch (wait) {
        .none => return false,
        .forever => {
            cond.wait(mutex);
            return true;
        },
        .until => |deadline| {
            const now = std.time.nanoTimestamp();
            if (now >= deadline) return false;
            cond.timedWait(mutex, @intCast(deadline - now)) catch {};
            return true;
        },
    }
}

pub const Channel = struct {
    allocator: std.mem.Allocator,
    id: u64,
    items: []workers.Payload,
    head: usize = 0,
    len: usize = 0,
    closed: bool = false,
    mutex: std.Thread.Mutex = .{},
    not_empty: std.Thread.Condition = .{},
    not_full: std.Thread.Condition = .{},
    // one reference per wrapper object, across every vm in the process
    refs: std.atomic.Value(u32) = std.atomic.Value(u32).init(1),

    const SendResult = enum { ok, full, closed, timeout };
    const RecvResult = union(enum) { value: workers.Payload, empty, closed, timeout };

    fn send(ch: *Channel, payload: workers.Payload, wait: Wait) SendResult {
        ch.mutex.lock();
        defer ch.mutex.unlock();
        while (!ch.closed and ch.len == ch.items.len) {
            if (!waitFor(&ch.not_full, &ch.mutex, wait)) return if (wait == .none) .full else .timeout;
        }
        if (ch.closed) return .closed;
        ch.items[(ch.head + ch.len) % ch.items.len] = payload;
        ch.len += 1;
        ch.not_empty.signal();
        return .ok;
    }

    fn recv(ch: *Channel, wait: Wait) RecvResult {
        ch.mutex.lock();
        defer ch.mutex.unlock();
        while (ch.len == 0 and !ch.closed) {
            if (!waitFor(&ch.not_empty, &ch.mutex, wait)) return if (wait == .none) .empty else .timeout;
        }
        if (ch.len == 0) return .closed;
        const payload = ch.items[ch.head];
        ch.head = (ch.head + 1) % ch.items.len;
        ch.len -= 1;
        ch.not_full.signal();
        return .{ .value = payload };
    }

    // buffered values stay receivable; senders and empty receivers are released
    fn close(ch: *Channel) void {
        ch.mutex.lock();
        defer ch.mutex.unlock();
        ch.closed = true;
        ch.not_empty.broadcast();
        ch.not_full.broadcast();
    }

    fn count(ch: *Channel) usize {
        ch.mutex.lock();
        defer ch.mutex.unlock();
        return ch.len;
    }

    fn isClosed(ch: *Channel) bool {
        ch.mutex.lock();
        defer ch.mutex.unlock();
        return ch.closed;
    }

    pub fn retain(ch: *Channel) void {
        _ = ch.refs.fetchAdd(1, .acq_rel);
    }

    // the last wrapper takes the channel out of the registry under its lock,
    // so a lookup racing the release either retains a live channel or misses
    pub fn release(ch: *Channel) void {
        registry_mutex.lock();
        if (ch.refs.fetchSub(1, .acq_rel) != 1) {
            registry_mutex.unlock();
            return;
        }
        _ = registry.remove(ch.id);
        registry_mutex.unlock();
        ch.free();
    }

    fn free(ch: *Channel) void {
        var i: usize = 0;
        while (i < ch.len) : (i += 1) ch.items[(ch.head + i) % ch.items.len].free(ch.allocator);
        ch.allocator.free(ch.items);
        ch.allocator.destroy(ch);
    }
};

// ---------------------------------------------------------------------------
// the process-wide registry that resolves an id back to its channel

var registry_mutex: std.Thread.Mutex = .{};
var registry: std.AutoHashMapUnmanaged(u64, *Channel) = .{};
var next_id: u64 = 1;
const registry_allocator = std.heap.page_allocator;

fn create(allocator: std.mem.Allocator, capacity: usize) !*Channel {
    const ch = try allocator.create(Channel);
    errdefer allocator.destroy(ch);
    const items = try allocator.alloc(workers.Payload, capacity);
    errdefer allocator.free(items);
    registry_mutex.lock();
    defer registry_mutex.unlock();
    ch.* = .{ .allocator = allocator, .id = next_id, .items = items };
    try registry.put(registry_allocator, ch.id, ch);
    next_id += 1;
    return ch;
}

fn lookup(id: u64) ?*Channel {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    const ch = registry.get(id) orelse return null;
    ch.retain();
    return ch;
}

// ---------------------------------------------------------------------------
// php surface

fn getThis(ctx: *NativeContext) ?*PhpObject {
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

fn throwNamed(ctx: *NativeContext, class_name: []const u8, comptime fmt: []const u8, args: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    try ctx.vm.strings.append(ctx.allocator, msg);
    try ctx.vm.setPendingException(class_name, msg);
    return error.RuntimeError;
}

fn channelOf(ctx: *NativeContext, obj: *PhpObject) RuntimeError!*Channel {
    return obj.native.get(Channel, .channel) orelse throwNamed(ctx, channel_exception, "the channel is not open", .{});
}

fn bind(obj: *PhpObject, ch: *Channel) void {
    obj.native = .{ .kind = .channel, .ptr = @intFromPtr(ch) };
}

fn waitArg(args: []const Value, index: usize) Wait {
    if (index >= args.len or args[index] == .null) return .forever;
    const ns = workers.optionalSeconds(args[index]) orelse return .forever;
    return .{ .until = std.time.nanoTimestamp() + @as(i128, ns) };
}

fn flushOutput(vm: *VM) void {
    if (vm.output.items.len == 0) return;
    platform.writeStdout(vm.output.items);
    vm.output.clearRetainingCapacity();
}

fn channelConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    var capacity: usize = 1;
    if (args.len >= 1 and args[0] != .null) {
        if (args[0] != .int or args[0].int < 1) return throwNamed(ctx, channel_exception, "capacity must be a positive integer", .{});
        capacity = @intCast(args[0].int);
    }
    const ch = create(workers.transferAllocator(ctx.allocator), capacity) catch return throwNamed(ctx, channel_exception, "could not create the channel", .{});
    bind(obj, ch);
    return NativeResult.scalar(.null);
}

fn sendValue(ctx: *NativeContext, args: []const Value, wait: Wait) RuntimeError!Channel.SendResult {
    const obj = getThis(ctx) orelse return .closed;
    const ch = try channelOf(ctx, obj);
    if (args.len < 1) return throwNamed(ctx, channel_exception, "send() needs a value", .{});
    const payload = try workers.pack(ctx, args[0], "value", ch.allocator);
    flushOutput(ctx.vm);
    const result = ch.send(payload, wait);
    if (result != .ok) payload.free(ch.allocator);
    return result;
}

fn channelSend(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    switch (try sendValue(ctx, args, waitArg(args, 1))) {
        .ok, .full => return NativeResult.scalar(.null),
        .closed => return throwNamed(ctx, channel_exception, "the channel is closed", .{}),
        .timeout => return throwNamed(ctx, timeout_exception, "the channel did not accept the value in time", .{}),
    }
}

fn channelTrySend(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    switch (try sendValue(ctx, args, .none)) {
        .ok => return NativeResult.scalar(.{ .bool = true }),
        .full, .timeout => return NativeResult.scalar(.{ .bool = false }),
        .closed => return throwNamed(ctx, channel_exception, "the channel is closed", .{}),
    }
}

fn unpackValue(ctx: *NativeContext, ch: *Channel, payload: workers.Payload) RuntimeError!Value {
    return workers.unpack(ctx, payload, ch.allocator) orelse throwNamed(ctx, channel_exception, "the value did not transfer", .{});
}

fn receive(ctx: *NativeContext, ch: *Channel, wait: Wait) Channel.RecvResult {
    flushOutput(ctx.vm);
    return ch.recv(wait);
}

fn channelRecv(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const ch = try channelOf(ctx, obj);
    switch (receive(ctx, ch, waitArg(args, 0))) {
        .value => |payload| return NativeResult.transfer(try unpackValue(ctx, ch, payload)),
        .closed => return throwNamed(ctx, channel_exception, "the channel is closed", .{}),
        .empty, .timeout => return throwNamed(ctx, timeout_exception, "no value arrived in time", .{}),
    }
}

fn channelClose(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const ch = try channelOf(ctx, obj);
    ch.close();
    return NativeResult.scalar(.null);
}

fn channelIsClosed(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const ch = try channelOf(ctx, obj);
    return NativeResult.scalar(.{ .bool = ch.isClosed() });
}

fn channelCount(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const ch = try channelOf(ctx, obj);
    return NativeResult.scalar(.{ .int = @intCast(ch.count()) });
}

fn channelCapacity(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const ch = try channelOf(ctx, obj);
    return NativeResult.scalar(.{ .int = @intCast(ch.items.len) });
}

fn channelId(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const ch = try channelOf(ctx, obj);
    return NativeResult.scalar(.{ .int = @intCast(ch.id) });
}

// ---------------------------------------------------------------------------
// iteration: foreach pulls values until the channel is closed and drained.
// the pending value and its position live on the wrapper, so each consumer
// iterates independently

fn channelRewind(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.null);
}

fn channelValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const ch = try channelOf(ctx, obj);
    if (obj.get("__ready") == .bool and obj.get("__ready").bool) return NativeResult.scalar(.{ .bool = true });
    switch (receive(ctx, ch, .forever)) {
        .value => |payload| {
            const v = try unpackValue(ctx, ch, payload);
            try obj.set(ctx.allocator, "__current", v);
            if (v == .string) v.string.release();
            try obj.set(ctx.allocator, "__ready", .{ .bool = true });
            return NativeResult.scalar(.{ .bool = true });
        },
        else => return NativeResult.scalar(.{ .bool = false }),
    }
}

fn channelCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(obj.get("__current"));
}

fn channelKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const key = obj.get("__key");
    return NativeResult.scalar(.{ .int = if (key == .int) key.int else 0 });
}

fn channelNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const key = obj.get("__key");
    try obj.set(ctx.allocator, "__key", .{ .int = if (key == .int) key.int + 1 else 1 });
    try obj.set(ctx.allocator, "__ready", .{ .bool = false });
    try obj.set(ctx.allocator, "__current", .null);
    return NativeResult.scalar(.null);
}

// ---------------------------------------------------------------------------
// transfer: a channel serializes as its id and binds to the same channel
// wherever it is unserialized in this process

fn channelSerialize(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const ch = try channelOf(ctx, obj);
    const arr = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("id") }, .{ .int = @intCast(ch.id) });
    return NativeResult.borrowed(.{ .array = arr });
}

fn channelUnserialize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (obj.native.kind != .none) return NativeResult.scalar(.null);
    const id: u64 = blk: {
        if (args.len < 1 or args[0] != .array) break :blk 0;
        const v = args[0].array.get(.{ .string = Value.String.borrowed("id") });
        break :blk if (v == .int and v.int > 0) @intCast(v.int) else 0;
    };
    const ch = lookup(id) orelse return throwNamed(ctx, channel_exception, "channel {d} does not exist in this process", .{id});
    bind(obj, ch);
    return NativeResult.scalar(.null);
}

// ---------------------------------------------------------------------------
// lifetimes

fn cleanupChannel(obj: *PhpObject) bool {
    const ch = obj.native.get(Channel, .channel) orelse return true;
    obj.native = .{};
    ch.release();
    return true;
}

pub fn cleanupResources(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    for (objects.items) |obj| {
        if (obj.pooled) continue;
        if (obj.native.kind == .channel) _ = cleanupChannel(obj);
    }
}

// ---------------------------------------------------------------------------
// registration

const methods = [_]struct { name: []const u8, arity: u8, native: vm_mod.NativeFn }{
    .{ .name = "__construct", .arity = 1, .native = channelConstruct },
    .{ .name = "send", .arity = 2, .native = channelSend },
    .{ .name = "trySend", .arity = 1, .native = channelTrySend },
    .{ .name = "recv", .arity = 1, .native = channelRecv },
    .{ .name = "close", .arity = 0, .native = channelClose },
    .{ .name = "isClosed", .arity = 0, .native = channelIsClosed },
    .{ .name = "count", .arity = 0, .native = channelCount },
    .{ .name = "capacity", .arity = 0, .native = channelCapacity },
    .{ .name = "id", .arity = 0, .native = channelId },
    .{ .name = "rewind", .arity = 0, .native = channelRewind },
    .{ .name = "valid", .arity = 0, .native = channelValid },
    .{ .name = "current", .arity = 0, .native = channelCurrent },
    .{ .name = "key", .arity = 0, .native = channelKey },
    .{ .name = "next", .arity = 0, .native = channelNext },
    .{ .name = "__serialize", .arity = 0, .native = channelSerialize },
    .{ .name = "__unserialize", .arity = 1, .native = channelUnserialize },
};

pub fn register(vm: *VM, a: std.mem.Allocator) !void {
    var def = ClassDef{ .name = channel_class, .is_final = true, .native_cleanup = cleanupChannel };
    try def.interfaces.append(a, "Iterator");
    try def.interfaces.append(a, "Countable");
    inline for (methods) |m| {
        try def.methods.put(a, m.name, .{ .name = m.name, .arity = m.arity });
        try vm.native_fns.put(a, channel_class ++ "::" ++ m.name, m.native);
    }
    try vm.classes.put(a, channel_class, def);
    try vm.classes.put(a, channel_exception, ClassDef{ .name = channel_exception, .parent = "Exception" });
}
