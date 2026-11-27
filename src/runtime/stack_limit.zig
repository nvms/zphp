// how deep native recursion may go on the running thread, php's
// zend_call_stack: php code re-entered from a native (a callback, a magic
// method, a nested fiber or generator) and natives that walk nested values
// recursively check it and fail the way php does instead of overflowing
const std = @import("std");
const builtin = @import("builtin");

// what is kept free below the limit: the entry that finds the limit passed
// may be one interpreter level past it, and building the Error and unwinding
// to its handler run below that. zphp's interpreter frames are much larger
// than php's (php keeps 48K; a debug build's runLoop frame alone is over
// half a megabyte), so this is larger too
pub const reserve: usize = 2 * 1024 * 1024;

const Bounds = struct { low: usize, high: usize };

threadlocal var limit: usize = 0;
threadlocal var usable: usize = 0;
// whether walkers of nested input may go on past the limit on more stack
// (stack_grow.zig): not when zend.max_allowed_stack_size sets the size,
// which php enforces, nor when nothing is checked
threadlocal var growable: bool = false;

// the first address below which the thread is out of stack
pub inline fn overflowed() bool {
    // the fast loop's object has its own copy of this file; the limits are
    // the main object's
    if (@import("build_role").fast_loop_object) return zphp_stack_limit() > @frameAddress();
    if (limit == 0) init();
    return @frameAddress() < limit;
}

extern fn zphp_stack_limit() callconv(.c) usize;

// the running thread's limit, for the fast loop's object
pub fn current() usize {
    if (limit == 0) init();
    return limit;
}

// the size php reports: zend.max_allowed_stack_size - zend.reserved_stack_size
pub fn allowedSize() usize {
    if (limit == 0) init();
    return usable;
}

pub fn canGrow() bool {
    if (limit == 0) init();
    return growable;
}

// the limits in force on the running stack, kept by whoever switches to
// another stack (a fiber's) and put back when it switches back
pub const Saved = struct { limit: usize, usable: usize };

pub fn save() Saved {
    if (limit == 0) init();
    return .{ .limit = limit, .usable = usable };
}

pub fn restore(saved: Saved) void {
    limit = saved.limit;
    usable = saved.usable;
}

// the limits of a stack about to run, from its bounds (a fiber's stack);
// with none known (windows keeps them in the teb) the running thread's are
// read again on the next check
pub fn enter(low: usize, high: usize) void {
    if (high <= low) {
        limit = 0;
        return;
    }
    setFrom(.{ .low = low, .high = high });
}

// the limit on a segment continuing the running stack (stack_grow.zig): the
// size php reports stays the thread's
pub fn enterExtension(low: usize, high: usize) void {
    const kept = usable;
    setFrom(.{ .low = low, .high = high });
    usable = kept;
}

pub const message_format = "Maximum call stack size of {d} bytes (zend.max_allowed_stack_size - zend.reserved_stack_size) reached. Infinite recursion?";

fn init() void {
    growable = false;
    const bounds = threadBounds() orelse {
        // a platform whose stack can't be found isn't checked
        limit = 1;
        usable = 0;
        return;
    };
    // zend_call_stack_init: zend.max_allowed_stack_size 0 detects the
    // stack, -1 checks nothing, and a size counts down from the stack's
    // base, less zend.reserved_stack_size. a size the real stack can't hold
    // with zphp's own reserve below it falls back to the detected one
    const max = configuredSize("zend.max_allowed_stack_size");
    if (max == -1) {
        limit = 1;
        usable = 0;
        return;
    }
    if (max > 0) {
        const size: usize = @intCast(max);
        const reserved: usize = @max(@as(usize, @intCast(@max(configuredSize("zend.reserved_stack_size"), 0))), min_reserved);
        if (size + reserve < bounds.high - bounds.low) {
            limit = bounds.high - size + reserved;
            usable = size -| reserved;
            return;
        }
    }
    setFrom(bounds);
    growable = true;
}

// OnUpdateReservedStackSize's minimum: ZEND_ALLOCA_MAX_SIZE plus 16K
const min_reserved: usize = 32 * 1024 + 16 * 1024;

fn configuredSize(name: []const u8) i64 {
    const text = @import("../ini_config.zig").get(name) orelse return 0;
    return @import("memory.zig").parseQuantity(text).value;
}

fn setFrom(bounds: Bounds) void {
    const size = bounds.high - bounds.low;
    usable = size -| reserve;
    // a stack too small for the reserve still gets half of itself
    limit = if (size > 2 * reserve) bounds.low + reserve else bounds.low + size / 2;
}

const PthreadAttr = extern struct { bytes: [128]u8 align(16) = undefined };
extern "c" fn pthread_self() usize;
extern "c" fn pthread_getattr_np(thread: usize, attr: *PthreadAttr) c_int;
extern "c" fn pthread_attr_getstack(attr: *const PthreadAttr, addr: *?*anyopaque, size: *usize) c_int;
extern "c" fn pthread_attr_destroy(attr: *PthreadAttr) c_int;
extern "c" fn pthread_get_stackaddr_np(thread: usize) ?*anyopaque;
extern "c" fn pthread_get_stacksize_np(thread: usize) usize;
extern "kernel32" fn GetCurrentThreadStackLimits(low: *usize, high: *usize) callconv(.winapi) void;

fn threadBounds() ?Bounds {
    switch (builtin.os.tag) {
        .linux => {
            var attr: PthreadAttr = .{};
            if (pthread_getattr_np(pthread_self(), &attr) != 0) return null;
            defer _ = pthread_attr_destroy(&attr);
            var addr: ?*anyopaque = null;
            var size: usize = 0;
            if (pthread_attr_getstack(&attr, &addr, &size) != 0) return null;
            const low = @intFromPtr(addr orelse return null);
            const high = low + size;
            // the main thread's stack grows on demand up to RLIMIT_STACK
            // (raised at startup to the size the executable asks for). musl
            // reports only the part mapped so far, so the limit decides
            const linux = std.os.linux;
            if (linux.gettid() == linux.getpid()) {
                const rl = std.posix.getrlimit(.STACK) catch return .{ .low = low, .high = high };
                if (rl.cur != linux.RLIM.INFINITY and rl.cur > 0 and rl.cur < high) {
                    return .{ .low = high - @as(usize, @intCast(rl.cur)), .high = high };
                }
            }
            return .{ .low = low, .high = high };
        },
        .macos, .ios => {
            const self = pthread_self();
            const high = @intFromPtr(pthread_get_stackaddr_np(self) orelse return null);
            const size = pthread_get_stacksize_np(self);
            return .{ .low = high - size, .high = high };
        },
        .windows => {
            var low: usize = 0;
            var high: usize = 0;
            GetCurrentThreadStackLimits(&low, &high);
            if (high <= low) return null;
            return .{ .low = low, .high = high };
        },
        else => return null,
    }
}
