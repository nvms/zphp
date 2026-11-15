// native stacks for fibers: each php fiber runs its interpreter loop on a
// machine stack of its own, as php's zend_fiber does, so a Fiber::suspend()
// reached through native code (a generator resumed by foreach, a callback a
// native calls, a magic method) leaves that native code waiting on the
// fiber's stack instead of unwinding it. posix switches with the
// register-clobbering switch std.Io uses; windows uses its fiber api, which
// keeps the thread's stack bounds in the teb right
const std = @import("std");
const builtin = @import("builtin");

const is_windows = builtin.os.tag == .windows;

pub const supported = is_windows or switch (builtin.cpu.arch) {
    .x86_64, .aarch64 => true,
    else => false,
};

// the cpu state of a stack that isn't running
pub const Context = if (is_windows) struct {
    fiber: ?*anyopaque = null,
} else if (supported) std.Io.fiber.Context else struct {};

pub const empty_context: Context = std.mem.zeroes(Context);

pub const Entry = *const fn (arg: *anyopaque) noreturn;

// a machine stack and the context that starts on it
pub const Coroutine = struct {
    context: Context = empty_context,
    // posix: the mapping, guard page included
    memory: []align(std.heap.page_size_min) u8 = &.{},
    entry: Entry = undefined,
    arg: *anyopaque = undefined,
    // the usable part of the stack, low to high (windows learns it when the
    // fiber first runs)
    low: usize = 0,
    high: usize = 0,

    pub fn bounds(self: *const Coroutine) struct { low: usize, high: usize } {
        return .{ .low = self.low, .high = self.high };
    }
};

// the block a fresh posix stack starts with, at its top
const StartBlock = extern struct {
    co: *Coroutine,
    pad: usize = 0,
};

pub fn create(co: *Coroutine, size: usize, entry: Entry, arg: *anyopaque) !void {
    co.* = .{ .entry = entry, .arg = arg };
    if (is_windows) {
        const fiber = CreateFiberEx(64 * 1024, size, FIBER_FLAG_FLOAT_SWITCH, &windowsStart, co) orelse return error.OutOfMemory;
        co.context = .{ .fiber = fiber };
        return;
    }
    if (!supported) return error.Unsupported;
    const page = std.heap.pageSize();
    const bytes = std.mem.alignForward(usize, size, page) + page;
    const memory = try std.posix.mmap(null, bytes, .{ .READ = true, .WRITE = true }, mapFlags(), -1, 0);
    errdefer std.posix.munmap(memory);
    // the lowest page faults instead of letting an overflow reach other memory
    try protectNone(memory[0..page]);
    co.memory = memory;
    const top = @intFromPtr(memory.ptr) + memory.len;
    co.low = @intFromPtr(memory.ptr) + page;
    co.high = top;
    const block_addr = std.mem.alignBackward(usize, top - @sizeOf(StartBlock), 16);
    const block: *StartBlock = @ptrFromInt(block_addr);
    block.* = .{ .co = co };
    co.context = switch (builtin.cpu.arch) {
        .x86_64 => .{ .rsp = block_addr - 8, .rbp = 0, .rip = @intFromPtr(&posixStart) },
        .aarch64 => .{ .sp = block_addr, .fp = 0, .pc = @intFromPtr(&posixStart) },
        else => unreachable,
    };
}

pub fn destroy(co: *Coroutine) void {
    if (is_windows) {
        if (co.context.fiber) |fiber| DeleteFiber(fiber);
    } else if (co.memory.len > 0) {
        std.posix.munmap(co.memory);
    }
    co.* = .{};
}

// saves the running stack's state in `from` and continues the one in `to`.
// returns when something switches back to `from`
pub fn switchTo(from: *Context, to: *Context) void {
    if (is_windows) {
        from.fiber = currentWindowsFiber();
        SwitchToFiber(to.fiber.?);
        return;
    }
    if (!supported) unreachable;
    _ = std.Io.fiber.contextSwitch(&.{ .old = from, .new = to });
}

fn mapFlags() std.posix.MAP {
    var flags: std.posix.MAP = .{ .TYPE = .PRIVATE, .ANONYMOUS = true };
    if (builtin.os.tag == .linux) {
        flags.NORESERVE = true;
        flags.STACK = true;
    }
    return flags;
}

fn protectNone(memory: []align(std.heap.page_size_min) u8) !void {
    if (std.c.mprotect(memory.ptr, memory.len, .{}) != 0) return error.OutOfMemory;
}

fn posixStart() callconv(.naked) void {
    switch (builtin.cpu.arch) {
        .x86_64 => asm volatile (
            \\ leaq 8(%%rsp), %%rdi
            \\ jmp %[call:P]
            :
            : [call] "X" (&posixCall),
        ),
        .aarch64 => asm volatile (
            \\ mov x0, sp
            \\ b %[call]
            :
            : [call] "X" (&posixCall),
        ),
        else => {},
    }
}

fn posixCall(block: *StartBlock) callconv(.withStackAlign(.c, 16)) noreturn {
    const co = block.co;
    co.entry(co.arg);
}

// windows

const FIBER_FLAG_FLOAT_SWITCH: u32 = 1;
const FiberProc = *const fn (param: ?*anyopaque) callconv(.winapi) void;
extern "kernel32" fn CreateFiberEx(commit: usize, reserve: usize, flags: u32, start: FiberProc, param: ?*anyopaque) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn DeleteFiber(fiber: *anyopaque) callconv(.winapi) void;
extern "kernel32" fn SwitchToFiber(fiber: *anyopaque) callconv(.winapi) void;
extern "kernel32" fn ConvertThreadToFiber(param: ?*anyopaque) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn IsThreadAFiber() callconv(.winapi) c_int;
extern "kernel32" fn GetCurrentThreadStackLimits(low: *usize, high: *usize) callconv(.winapi) void;

fn windowsStart(param: ?*anyopaque) callconv(.winapi) void {
    const co: *Coroutine = @ptrCast(@alignCast(param.?));
    GetCurrentThreadStackLimits(&co.low, &co.high);
    co.entry(co.arg);
}

// the thread's own stack becomes a fiber the first time it switches
fn currentWindowsFiber() *anyopaque {
    if (IsThreadAFiber() == 0) return ConvertThreadToFiber(null).?;
    return switch (builtin.cpu.arch) {
        .x86_64 => asm volatile ("movq %%gs:0x20, %[ret]"
            : [ret] "=r" (-> *anyopaque),
        ),
        .aarch64 => asm volatile ("ldr %[ret], [x18, #0x20]"
            : [ret] "=r" (-> *anyopaque),
        ),
        else => @compileError("unsupported windows architecture"),
    };
}

test "a coroutine switches back and forth and keeps its stack" {
    if (!supported) return error.SkipZigTest;
    const State = struct {
        main: Context = empty_context,
        co: Coroutine = .{},
        log: [8]u32 = undefined,
        n: usize = 0,

        fn run(arg: *anyopaque) noreturn {
            const s: *@This() = @ptrCast(@alignCast(arg));
            var local: u32 = 10;
            while (true) {
                s.log[s.n] = local;
                s.n += 1;
                local += 1;
                switchTo(&s.co.context, &s.main);
            }
        }
    };
    var s: State = .{};
    try create(&s.co, 256 * 1024, &State.run, &s);
    defer destroy(&s.co);
    switchTo(&s.main, &s.co.context);
    switchTo(&s.main, &s.co.context);
    switchTo(&s.main, &s.co.context);
    try std.testing.expectEqual(@as(usize, 3), s.n);
    try std.testing.expectEqualSlices(u32, &.{ 10, 11, 12 }, s.log[0..3]);
}
