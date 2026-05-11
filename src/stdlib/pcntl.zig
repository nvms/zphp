const std = @import("std");
const posix = std.posix;
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "pcntl_fork", native_pcntl_fork },
    .{ "pcntl_wait", native_pcntl_wait },
    .{ "pcntl_waitpid", native_pcntl_waitpid },
    .{ "pcntl_exec", native_pcntl_exec },
    .{ "pcntl_alarm", native_pcntl_alarm },
    .{ "pcntl_signal", native_pcntl_signal },
    .{ "pcntl_signal_get_handler", native_pcntl_signal_get_handler },
    .{ "pcntl_signal_dispatch", native_pcntl_signal_dispatch },
    .{ "pcntl_async_signals", native_pcntl_async_signals },
    .{ "pcntl_wifexited", native_pcntl_wifexited },
    .{ "pcntl_wexitstatus", native_pcntl_wexitstatus },
    .{ "pcntl_wifsignaled", native_pcntl_wifsignaled },
    .{ "pcntl_wtermsig", native_pcntl_wtermsig },
    .{ "pcntl_wifstopped", native_pcntl_wifstopped },
    .{ "pcntl_wstopsig", native_pcntl_wstopsig },
    .{ "pcntl_get_last_error", native_pcntl_get_last_error },
    .{ "pcntl_errno", native_pcntl_get_last_error },
    .{ "pcntl_strerror", native_pcntl_strerror },
    .{ "pcntl_sigprocmask", native_pcntl_sigprocmask },
};

extern "c" fn strerror(errnum: c_int) ?[*:0]const u8;
extern "c" fn alarm(seconds: c_uint) c_uint;
extern "c" fn execve(path: [*:0]const u8, argv: [*]const ?[*:0]const u8, envp: [*]const ?[*:0]const u8) c_int;

const MAX_SIG: usize = 64;

var pending_signals: [MAX_SIG]std.atomic.Value(u32) = blk: {
    var arr: [MAX_SIG]std.atomic.Value(u32) = undefined;
    for (&arr) |*a| a.* = std.atomic.Value(u32).init(0);
    break :blk arr;
};

var signal_handlers: [MAX_SIG]Value = blk: {
    var arr: [MAX_SIG]Value = undefined;
    for (&arr) |*a| a.* = .null;
    break :blk arr;
};

var async_enabled: bool = false;
var last_errno: c_int = 0;

fn cHandler(sig: c_int) callconv(.c) void {
    const idx: usize = @intCast(sig);
    if (idx < MAX_SIG) _ = pending_signals[idx].fetchAdd(1, .seq_cst);
}

fn native_pcntl_fork(_: *NativeContext, _: []const Value) RuntimeError!Value {
    const pid = std.c.fork();
    if (pid < 0) {
        last_errno = std.c._errno().*;
        return .{ .int = -1 };
    }
    return .{ .int = @intCast(pid) };
}

fn native_pcntl_wait(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    var status: c_int = 0;
    const options: c_int = if (args.len > 1 and args[1] == .int) @intCast(args[1].int) else 0;
    const rc = std.c.waitpid(-1, &status, options);
    if (args.len > 0) {
        ctx.setCallerVar(0, args.len, .{ .int = @intCast(status) });
    }
    if (rc < 0) last_errno = std.c._errno().*;
    return .{ .int = @intCast(rc) };
}

fn native_pcntl_waitpid(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .int) return .{ .int = -1 };
    var status: c_int = 0;
    const options: c_int = if (args.len > 2 and args[2] == .int) @intCast(args[2].int) else 0;
    const rc = std.c.waitpid(@intCast(args[0].int), &status, options);
    if (args.len > 1) {
        ctx.setCallerVar(1, args.len, .{ .int = @intCast(status) });
    }
    if (rc < 0) last_errno = std.c._errno().*;
    return .{ .int = @intCast(rc) };
}

fn native_pcntl_exec(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const path_z = try ctx.allocator.dupeZ(u8, args[0].string);
    defer ctx.allocator.free(path_z);

    var argv = std.ArrayListUnmanaged(?[*:0]const u8){};
    defer {
        for (argv.items) |a| if (a) |s| ctx.allocator.free(std.mem.span(s));
        argv.deinit(ctx.allocator);
    }
    try argv.append(ctx.allocator, (try ctx.allocator.dupeZ(u8, args[0].string)).ptr);
    if (args.len > 1 and args[1] == .array) {
        for (args[1].array.entries.items) |entry| {
            const s = switch (entry.value) {
                .string => |str| str,
                else => continue,
            };
            try argv.append(ctx.allocator, (try ctx.allocator.dupeZ(u8, s)).ptr);
        }
    }
    try argv.append(ctx.allocator, null);

    var envp = std.ArrayListUnmanaged(?[*:0]const u8){};
    defer {
        for (envp.items) |e| if (e) |s| ctx.allocator.free(std.mem.span(s));
        envp.deinit(ctx.allocator);
    }
    if (args.len > 2 and args[2] == .array) {
        for (args[2].array.entries.items) |entry| {
            const k = switch (entry.key) {
                .string => |s| s,
                .int => |i| try std.fmt.allocPrint(ctx.allocator, "{d}", .{i}),
            };
            defer if (entry.key == .int) ctx.allocator.free(k);
            const v = switch (entry.value) {
                .string => |s| s,
                else => continue,
            };
            const tmp = try std.fmt.allocPrint(ctx.allocator, "{s}={s}", .{ k, v });
            defer ctx.allocator.free(tmp);
            const ev = try ctx.allocator.dupeZ(u8, tmp);
            try envp.append(ctx.allocator, ev.ptr);
        }
        try envp.append(ctx.allocator, null);
    } else {
        try envp.append(ctx.allocator, null);
    }

    const rc = execve(path_z, argv.items.ptr, envp.items.ptr);
    last_errno = std.c._errno().*;
    return .{ .bool = rc == 0 };
}

fn native_pcntl_alarm(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .int) return .{ .int = 0 };
    const prev = alarm(@intCast(args[0].int));
    return .{ .int = @intCast(prev) };
}

fn native_pcntl_signal(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .int) return .{ .bool = false };
    const sig: usize = @intCast(args[0].int);
    if (sig == 0 or sig >= MAX_SIG) return .{ .bool = false };

    // SIG_DFL (0), SIG_IGN (1) are the only special int values PHP uses
    if (args[1] == .int and (args[1].int == 0 or args[1].int == 1)) {
        const action: usize = if (args[1].int == 0)
            @intFromPtr(@as(*const anyopaque, @ptrCast(&std.c.SIG.DFL)))
        else
            @intFromPtr(@as(*const anyopaque, @ptrCast(&std.c.SIG.IGN)));
        _ = action;
        var sa = posix.Sigaction{
            .handler = .{ .handler = if (args[1].int == 0) posix.SIG.DFL else posix.SIG.IGN },
            .mask = posix.sigemptyset(),
            .flags = 0,
        };
        posix.sigaction(@intCast(sig), &sa, null);
        signal_handlers[sig] = .null;
        return .{ .bool = true };
    }

    signal_handlers[sig] = args[1];

    var sa = posix.Sigaction{
        .handler = .{ .handler = cHandler },
        .mask = posix.sigemptyset(),
        .flags = 0,
    };
    posix.sigaction(@intCast(sig), &sa, null);
    return .{ .bool = true };
}

fn native_pcntl_signal_get_handler(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .int) return .{ .int = 0 };
    const sig: usize = @intCast(args[0].int);
    if (sig >= MAX_SIG) return .{ .int = 0 };
    if (signal_handlers[sig] == .null) return .{ .int = 0 }; // SIG_DFL
    return signal_handlers[sig];
}

fn native_pcntl_signal_dispatch(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    var i: usize = 1;
    while (i < MAX_SIG) : (i += 1) {
        const pending = pending_signals[i].swap(0, .seq_cst);
        if (pending == 0) continue;
        const cb = signal_handlers[i];
        if (cb == .null) continue;
        const sig_val = Value{ .int = @intCast(i) };
        const sigi_val = Value{ .int = @intCast(i) };
        const info_arr = try ctx.createArray();
        try info_arr.set(ctx.allocator, .{ .string = "signo" }, sigi_val);
        const argv = [_]Value{ sig_val, .{ .array = info_arr } };
        _ = ctx.invokeCallable(cb, &argv) catch continue;
    }
    return .{ .bool = true };
}

fn native_pcntl_async_signals(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const prev = async_enabled;
    if (args.len > 0 and args[0] == .bool) async_enabled = args[0].bool;
    return .{ .bool = prev };
}

inline fn wifexited(st: c_int) bool {
    return (st & 0x7f) == 0;
}
inline fn wexitstatus(st: c_int) c_int {
    return (st >> 8) & 0xff;
}
inline fn wifsignaled(st: c_int) bool {
    const s = st & 0x7f;
    return s != 0 and s != 0x7f;
}
inline fn wtermsig(st: c_int) c_int {
    return st & 0x7f;
}
inline fn wifstopped(st: c_int) bool {
    return (st & 0xff) == 0x7f;
}
inline fn wstopsig(st: c_int) c_int {
    return (st >> 8) & 0xff;
}

fn intArg(args: []const Value) c_int {
    if (args.len < 1 or args[0] != .int) return 0;
    return @intCast(args[0].int);
}

fn native_pcntl_wifexited(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return .{ .bool = wifexited(intArg(args)) };
}
fn native_pcntl_wexitstatus(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return .{ .int = @intCast(wexitstatus(intArg(args))) };
}
fn native_pcntl_wifsignaled(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return .{ .bool = wifsignaled(intArg(args)) };
}
fn native_pcntl_wtermsig(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return .{ .int = @intCast(wtermsig(intArg(args))) };
}
fn native_pcntl_wifstopped(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return .{ .bool = wifstopped(intArg(args)) };
}
fn native_pcntl_wstopsig(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return .{ .int = @intCast(wstopsig(intArg(args))) };
}

fn native_pcntl_get_last_error(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = @intCast(last_errno) };
}

fn native_pcntl_strerror(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .int) return .{ .string = "" };
    const s = strerror(@intCast(args[0].int)) orelse return .{ .string = "" };
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {}
    const owned = try ctx.allocator.dupe(u8, s[0..i]);
    try ctx.strings.append(ctx.allocator, owned);
    return .{ .string = owned };
}

fn native_pcntl_sigprocmask(_: *NativeContext, _: []const Value) RuntimeError!Value {
    // best-effort no-op: returns true. correct impl would translate the mask array
    return .{ .bool = true };
}

pub fn isAsyncEnabled() bool {
    return async_enabled;
}

pub fn hasPendingSignals() bool {
    var i: usize = 1;
    while (i < MAX_SIG) : (i += 1) {
        if (pending_signals[i].load(.acquire) != 0) return true;
    }
    return false;
}

pub fn dispatchPending(ctx: *NativeContext) void {
    _ = native_pcntl_signal_dispatch(ctx, &[_]Value{}) catch {};
}

test {}
