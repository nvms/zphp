// more stack for walkers of nested input. the compiler over a deeply nested
// expression, the parser, a dump of a deeply nested array: each recurses once
// per level, and zphp's frames are many times php's, so nesting php's 8 MB
// stack holds can overflow zphp's (or a fiber's, or a worker thread's). such
// a walker checks `needed()` where it recurses; once the running stack is at
// its limit the call continues on a segment of fresh stack, switched to the
// way fibers are (coro.zig), and the walker is back on the stack it came
// from when the call returns. growth is bounded: past `budget`, or where it
// can't happen, `call` returns null and the walker raises php's stack-size
// error, as php does at its own limit
const std = @import("std");
const builtin = @import("builtin");
const coro = @import("coro.zig");
const stack_limit = @import("stack_limit.zig");

// each segment's size. posix maps it without reserving memory, so only the
// pages a walk touches count
const segment_size: usize = 64 * 1024 * 1024;

// how much stack a thread's segments in use may add up to
const budget: usize = 4 * segment_size;

// what a finished segment keeps of the pages it touched, for the next growth
const kept_top: usize = 256 * 1024;

const Segment = struct {
    co: coro.Coroutine = .{},
    // where the call that switched to the segment waits
    resumer: coro.Context = coro.empty_context,
    job: *const fn (*anyopaque) void = undefined,
    job_arg: *anyopaque = undefined,
};

threadlocal var in_use: usize = 0;
// the last finished segment: a walk at the limit grows once for each of a
// node's children, which shouldn't map a stack each time
threadlocal var spare: ?*Segment = null;
// a call refused since the last `takeRefused`: walkers that can't fail
// themselves (predicates) return a stand-in and leave the error to code that
// can (the compiler checks after each node)
threadlocal var refused: bool = false;

// whether the running stack is at its limit, so the next level of a walk
// goes through `call`
pub inline fn needed() bool {
    return stack_limit.overflowed();
}

pub inline fn takeRefused() bool {
    if (!refused) return false;
    refused = false;
    return true;
}

fn Result(comptime func: anytype) type {
    return @typeInfo(@TypeOf(func)).@"fn".return_type.?;
}

// runs `func` on a fresh segment and returns its result; null when no stack
// may be added: the thread's budget is used up, there is no memory for it,
// the platform has no coroutines, or zend.max_allowed_stack_size sets the
// stack's size (php enforces it; walkers php guards fail there)
pub noinline fn call(comptime func: anytype, args: std.meta.ArgsTuple(@TypeOf(func))) ?Result(func) {
    if (!stack_limit.canGrow()) {
        refused = true;
        return null;
    }
    return callAlways(func, args);
}

// the same past a configured stack size, for walkers whose php counterpart
// doesn't use the machine stack (php's parser keeps its states on the heap)
pub noinline fn callAlways(comptime func: anytype, args: std.meta.ArgsTuple(@TypeOf(func))) ?Result(func) {
    const Job = struct {
        args: @TypeOf(args),
        result: Result(func) = undefined,

        fn run(p: *anyopaque) void {
            const job: *@This() = @ptrCast(@alignCast(p));
            job.result = @call(.auto, func, job.args);
        }
    };
    var job: Job = .{ .args = args };
    const seg = acquire() orelse {
        refused = true;
        return null;
    };
    defer release(seg);
    const saved = stack_limit.save();
    defer stack_limit.restore(saved);
    seg.job = &Job.run;
    seg.job_arg = &job;
    coro.switchTo(&seg.resumer, &seg.co.context);
    return job.result;
}

fn segmentMain(arg: *anyopaque) noreturn {
    const seg: *Segment = @ptrCast(@alignCast(arg));
    while (true) {
        // windows learns the bounds as the fiber first runs
        stack_limit.enterExtension(seg.co.low, seg.co.high);
        seg.job(seg.job_arg);
        coro.switchTo(&seg.co.context, &seg.resumer);
    }
}

fn acquire() ?*Segment {
    if (!coro.supported) return null;
    if (in_use + segment_size > budget) return null;
    const seg = spare orelse blk: {
        const created = std.heap.page_allocator.create(Segment) catch return null;
        created.* = .{};
        coro.create(&created.co, segment_size, &segmentMain, created) catch {
            std.heap.page_allocator.destroy(created);
            return null;
        };
        break :blk created;
    };
    spare = null;
    in_use += segment_size;
    return seg;
}

fn release(seg: *Segment) void {
    in_use -= segment_size;
    if (spare != null) return destroy(seg);
    // the pages a deep walk touched go back; the top ones a shallow call
    // uses stay
    if (builtin.os.tag != .windows and seg.co.high - seg.co.low > kept_top) {
        const low = seg.co.low;
        const len = seg.co.high - kept_top - low;
        std.posix.madvise(@ptrFromInt(low), len, std.posix.MADV.DONTNEED) catch {};
    }
    spare = seg;
}

fn destroy(seg: *Segment) void {
    coro.destroy(&seg.co);
    std.heap.page_allocator.destroy(seg);
}

// frees the running thread's spare segment, as a thread that grew winds down
pub fn releaseSpare() void {
    const seg = spare orelse return;
    spare = null;
    destroy(seg);
}

test "a deep recursion continues on segments and returns to its stack" {
    if (!coro.supported) return error.SkipZigTest;
    const Walk = struct {
        var deepest_grown: usize = 0;

        fn depth(n: usize) usize {
            // a frame of a few kilobytes, as the compiler's are
            var pad: [4096]u8 = undefined;
            std.mem.doNotOptimizeAway(&pad);
            if (n == 0) return 0;
            deepest_grown = @max(deepest_grown, in_use);
            if (needed()) return (call(depth, .{n - 1}) orelse return 0) + 1;
            return depth(n - 1) + 1;
        }
    };
    const before = @frameAddress();
    // far more than any thread's own stack holds
    try std.testing.expectEqual(@as(usize, 40_000), Walk.depth(40_000));
    try std.testing.expect(Walk.deepest_grown > 0);
    try std.testing.expectEqual(@as(usize, 0), in_use);
    try std.testing.expectEqual(before, @frameAddress());
    releaseSpare();
}
