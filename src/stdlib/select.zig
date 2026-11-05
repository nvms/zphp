// Zphp\select waits on several channels and futures at once. every source
// keeps a list of waiters it notifies when it changes (a channel gains a
// value or closes, a task settles); the selecting thread registers one
// waiter on all of its sources, polls them, and sleeps on the waiter until
// one of them fires
const std = @import("std");
const sync = @import("../sync.zig");
const platform = @import("../platform.zig");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const PhpObject = value_mod.PhpObject;
const PhpArray = value_mod.PhpArray;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const RuntimeError = error{ RuntimeError, OutOfMemory };
const workers = @import("workers.zig");
const channel = @import("channel.zig");

pub const Waiter = struct {
    mutex: sync.Mutex = .{},
    changed: sync.Condition = .{},
    fired: bool = false,

    // sources call this with their own lock held; the waiter lock is always
    // taken second, so a source never waits on a selector
    fn notify(w: *Waiter) void {
        w.mutex.lock();
        defer w.mutex.unlock();
        w.fired = true;
        w.changed.signal();
    }

    fn arm(w: *Waiter) void {
        w.mutex.lock();
        defer w.mutex.unlock();
        w.fired = false;
    }

    // false once the deadline passes without a notification
    fn sleep(w: *Waiter, deadline: ?i128) bool {
        w.mutex.lock();
        defer w.mutex.unlock();
        while (!w.fired) {
            const until = deadline orelse {
                w.changed.wait(&w.mutex);
                continue;
            };
            const now = platform.nanoTimestamp();
            if (now >= until) return false;
            w.changed.timedWait(&w.mutex, @intCast(until - now)) catch {};
        }
        return true;
    }
};

// guarded by the owning source's mutex
pub const WaitList = struct {
    waiters: std.ArrayListUnmanaged(*Waiter) = .empty,

    pub fn add(self: *WaitList, a: std.mem.Allocator, w: *Waiter) !void {
        try self.waiters.append(a, w);
    }

    pub fn remove(self: *WaitList, w: *Waiter) void {
        for (self.waiters.items, 0..) |item, i| {
            if (item != w) continue;
            _ = self.waiters.swapRemove(i);
            return;
        }
    }

    pub fn notifyAll(self: *WaitList) void {
        for (self.waiters.items) |w| w.notify();
    }

    pub fn deinit(self: *WaitList, a: std.mem.Allocator) void {
        self.waiters.deinit(a);
    }
};

// ---------------------------------------------------------------------------
// sources

const Source = struct {
    key: PhpArray.Key,
    kind: union(enum) { channel: *channel.Channel, future: struct { obj: *PhpObject, task: *workers.Task } },

    fn watch(s: Source, w: *Waiter) !void {
        switch (s.kind) {
            .channel => |ch| try ch.watch(w),
            .future => |f| try f.task.watch(w),
        }
    }

    fn unwatch(s: Source, w: *Waiter) void {
        switch (s.kind) {
            .channel => |ch| ch.unwatch(w),
            .future => |f| f.task.unwatch(w),
        }
    }
};

fn throwNamed(ctx: *NativeContext, class_name: []const u8, comptime fmt: []const u8, args: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException(class_name, msg);
    return error.RuntimeError;
}

fn collectSources(ctx: *NativeContext, arr: *PhpArray, out: *std.ArrayListUnmanaged(Source)) RuntimeError!void {
    for (arr.entries.items) |entry| {
        const v = if (entry.ref) |cell| cell.* else entry.value;
        const source: Source = blk: {
            if (v == .object) {
                if (v.object.native.get(channel.Channel, .channel)) |ch| break :blk .{ .key = entry.key, .kind = .{ .channel = ch } };
                if (workers.futureTask(v.object)) |task| break :blk .{ .key = entry.key, .kind = .{ .future = .{ .obj = v.object, .task = task } } };
            }
            return throwNamed(ctx, "TypeError", "Zphp\\select(): Argument #1 ($sources) must contain only Zphp\\Channel and Zphp\\Future, {s} given", .{v.typeName()});
        };
        try out.append(ctx.allocator, source);
    }
}

// one pass over every source, starting at a rotating offset so a busy
// source early in the list cannot starve the rest. a channel that is closed
// and drained is skipped; when nothing else is left, select fails the way
// recv does
threadlocal var turn: usize = 0;

fn readyIndex(ctx: *NativeContext, sources: []const Source) RuntimeError!?struct { index: usize, value: Value } {
    turn +%= 1;
    var live = false;
    for (0..sources.len) |i| {
        const index = (turn + i) % sources.len;
        switch (sources[index].kind) {
            .channel => |ch| switch (ch.recv(.none)) {
                .value => |payload| return .{ .index = index, .value = try channel.unpackValue(ctx, ch, payload) },
                .empty, .timeout => live = true,
                .closed => {},
            },
            .future => |f| {
                if (f.task.isSettled()) return .{ .index = index, .value = .{ .object = f.obj } };
                live = true;
            },
        }
    }
    if (!live) return throwNamed(ctx, channel.channel_exception, "every channel is closed", .{});
    return null;
}

fn pair(ctx: *NativeContext, key: PhpArray.Key, v: Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    try arr.append(ctx.allocator, switch (key) {
        .int => |i| .{ .int = i },
        .string => |s| .{ .string = s },
    });
    try arr.append(ctx.allocator, v);
    if (v == .string) v.string.release();
    return NativeResult.borrowed(.{ .array = arr });
}

fn deadlineArg(ctx: *NativeContext, args: []const Value) RuntimeError!?i128 {
    if (args.len < 2 or args[1] == .null) return null;
    const ns = workers.optionalSeconds(args[1]) orelse return throwNamed(ctx, "ValueError", "Zphp\\select(): Argument #2 ($timeout) must be a number of seconds greater than or equal to 0", .{});
    return platform.nanoTimestamp() + @as(i128, ns);
}

fn nativeSelect(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .array) return throwNamed(ctx, "TypeError", "Zphp\\select(): Argument #1 ($sources) must be of type array, {s} given", .{Value.typeName(if (args.len > 0) args[0] else .null)});
    if (args[0].array.entries.items.len == 0) return throwNamed(ctx, "ValueError", "Zphp\\select(): Argument #1 ($sources) must not be empty", .{});
    const deadline = try deadlineArg(ctx, args);
    var sources: std.ArrayListUnmanaged(Source) = .empty;
    defer sources.deinit(ctx.allocator);
    try collectSources(ctx, args[0].array, &sources);

    if (try readyIndex(ctx, sources.items)) |hit| return pair(ctx, sources.items[hit.index].key, hit.value);
    if (deadline) |d| if (platform.nanoTimestamp() >= d) return NativeResult.scalar(.null);

    workers.flushOutput(ctx.vm);
    var waiter = Waiter{};
    var watched: usize = 0;
    defer for (sources.items[0..watched]) |s| s.unwatch(&waiter);
    for (sources.items) |s| {
        try s.watch(&waiter);
        watched += 1;
    }
    while (true) {
        waiter.arm();
        if (try readyIndex(ctx, sources.items)) |hit| return pair(ctx, sources.items[hit.index].key, hit.value);
        if (!waiter.sleep(deadline)) return NativeResult.scalar(.null);
    }
}

pub fn register(vm: *VM, a: std.mem.Allocator) !void {
    try vm.native_fns.put(a, "Zphp\\select", nativeSelect);
}
