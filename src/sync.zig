// locks and condition variables for zphp's own threads (serve workers, php
// worker pools, channels). they block the os thread on the process's io
// implementation and are never cancelation points: php code has no notion of
// a canceled lock wait
const std = @import("std");
const platform = @import("platform.zig");

pub const Mutex = struct {
    inner: std.Io.Mutex = .init,

    pub fn lock(m: *Mutex) void {
        m.inner.lockUncancelable(platform.io);
    }

    pub fn tryLock(m: *Mutex) bool {
        return m.inner.tryLock();
    }

    pub fn unlock(m: *Mutex) void {
        m.inner.unlock(platform.io);
    }
};

// std.Io.Condition with a timed wait, which php's worker and channel
// deadlines need
pub const Condition = struct {
    state: std.atomic.Value(State) = .init(.{ .waiters = 0, .signals = 0 }),
    // bumped on every signal; waiters sleep on it
    epoch: std.atomic.Value(u32) = .init(0),

    const State = packed struct(u32) {
        waiters: u16,
        signals: u16,
    };

    pub fn wait(cond: *Condition, mutex: *Mutex) void {
        cond.waitUntil(mutex, null) catch unreachable;
    }

    // waits at most timeout_ns; error.Timeout when no signal came in time
    pub fn timedWait(cond: *Condition, mutex: *Mutex, timeout_ns: u64) error{Timeout}!void {
        const io = platform.io;
        const deadline = std.Io.Clock.Timestamp.fromNow(io, .{ .raw = .fromNanoseconds(timeout_ns), .clock = .awake });
        return cond.waitUntil(mutex, deadline);
    }

    fn waitUntil(cond: *Condition, mutex: *Mutex, deadline: ?std.Io.Clock.Timestamp) error{Timeout}!void {
        const io = platform.io;
        var epoch = cond.epoch.load(.acquire);
        _ = cond.state.fetchAdd(.{ .waiters = 1, .signals = 0 }, .monotonic);

        mutex.unlock();
        defer mutex.lock();

        while (true) {
            if (deadline) |d| {
                io.futexWaitTimeout(u32, &cond.epoch.raw, epoch, .{ .deadline = d }) catch {};
            } else {
                io.futexWaitUncancelable(u32, &cond.epoch.raw, epoch);
            }
            epoch = cond.epoch.load(.acquire);

            // consume a pending signal before deciding this was a timeout,
            // or a signal could be left with no waiter to take it
            var prev = cond.state.load(.monotonic);
            while (prev.signals > 0) {
                prev = cond.state.cmpxchgWeak(prev, .{
                    .waiters = prev.waiters - 1,
                    .signals = prev.signals - 1,
                }, .acquire, .monotonic) orelse return;
            }

            if (deadline) |d| {
                if (d.durationFromNow(io).raw.nanoseconds <= 0) {
                    _ = cond.state.fetchSub(.{ .waiters = 1, .signals = 0 }, .monotonic);
                    return error.Timeout;
                }
            }
        }
    }

    pub fn signal(cond: *Condition) void {
        cond.wake(.one);
    }

    pub fn broadcast(cond: *Condition) void {
        cond.wake(.all);
    }

    fn wake(cond: *Condition, comptime which: enum { one, all }) void {
        var prev = cond.state.load(.monotonic);
        while (prev.waiters > prev.signals) {
            const next_signals = if (which == .one) prev.signals + 1 else prev.waiters;
            prev = cond.state.cmpxchgWeak(prev, .{
                .waiters = prev.waiters,
                .signals = next_signals,
            }, .release, .monotonic) orelse {
                _ = cond.epoch.fetchAdd(1, .release);
                platform.io.futexWake(u32, &cond.epoch.raw, next_signals - prev.signals);
                return;
            };
        }
    }
};

// runs a function once across every thread, the first time it is asked for
pub fn Once(comptime f: fn () void) type {
    return struct {
        done: std.atomic.Value(bool) = .init(false),
        mutex: Mutex = .{},

        pub fn call(self: *@This()) void {
            if (self.done.load(.acquire)) return;
            self.mutex.lock();
            defer self.mutex.unlock();
            if (self.done.load(.monotonic)) return;
            f();
            self.done.store(true, .release);
        }
    };
}

pub fn once(comptime f: fn () void) Once(f) {
    return .{};
}
