// proc_open on windows. the descriptor spec becomes inheritable child ends
// (CreatePipe pairs, opened files, duplicated stream handles), cmd.exe runs
// the command through CreateProcessW, and the parent pipe ends turn into
// crt descriptors so the FileHandle natives use them like any other stream
const std = @import("std");
const windows = std.os.windows;
const kernel32 = windows.kernel32;
const platform = @import("../platform.zig");
const filesystem = @import("filesystem.zig");
const vm_mod = @import("../runtime/vm.zig");
const NativeContext = vm_mod.NativeContext;
const ProcChild = vm_mod.ProcChild;
const ProcPipe = vm_mod.ProcPipe;
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const PhpObject = value_mod.PhpObject;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const RuntimeError = error{ RuntimeError, OutOfMemory };

extern "c" fn _get_osfhandle(fd: c_int) isize;
extern "kernel32" fn PeekNamedPipe(
    pipe: windows.HANDLE,
    buffer: ?*anyopaque,
    size: u32,
    bytes_read: ?*u32,
    available: ?*u32,
    left: ?*u32,
) callconv(.winapi) windows.BOOL;

const terminate_exit_code: u32 = 255;

const inheritable: windows.SECURITY_ATTRIBUTES = .{
    .nLength = @sizeOf(windows.SECURITY_ATTRIBUTES),
    .lpSecurityDescriptor = null,
    .bInheritHandle = windows.TRUE,
};

const Spec = union(enum) {
    pipe_r,
    pipe_w,
    file: struct { path: []const u8, mode: []const u8 },
    redirect: i64,
    blackhole,
};

const Desc = struct { role: i64, spec: Spec };

// one descriptor's handles around the spawn: the child end is closed once
// the child holds its own copy, the parent end outlives the call as a pipe
const Slot = struct {
    role: i64,
    child: ?windows.HANDLE = null,
    parent: ?windows.HANDLE = null,

    fn closeAll(self: *Slot) void {
        if (self.child) |h| windows.CloseHandle(h);
        if (self.parent) |h| windows.CloseHandle(h);
        self.child = null;
        self.parent = null;
    }
};

fn warn(ctx: *NativeContext, comptime fmt: []const u8, args: anytype) RuntimeError!void {
    const msg = try std.fmt.allocPrint(ctx.allocator, "proc_open(): " ++ fmt, args);
    try ctx.vm.strings.append(ctx.allocator, msg);
    ctx.vm.emitWarning(msg);
}

fn parseSpec(ctx: *NativeContext, item: Value) RuntimeError!?Spec {
    if (item == .object) {
        const fdv = item.object.get("__fd");
        if (fdv != .int or fdv.int < 0) return null;
        return .{ .redirect = fdv.int };
    }
    if (item != .array) {
        try ctx.vm.setPendingException("ValueError", "proc_open(): Argument #2 ($descriptor_spec) must only contain arrays and streams");
        return error.RuntimeError;
    }
    const tag = item.array.get(.{ .int = 0 });
    if (tag != .string) return null;
    const kind = tag.string.bytes();
    if (std.mem.eql(u8, kind, "pipe")) {
        const mode = item.array.get(.{ .int = 1 });
        const reads = mode == .string and mode.string.bytes().len > 0 and mode.string.bytes()[0] == 'r';
        return if (reads) .pipe_r else .pipe_w;
    }
    if (std.mem.eql(u8, kind, "file")) {
        const path = item.array.get(.{ .int = 1 });
        const mode = item.array.get(.{ .int = 2 });
        if (path != .string or mode != .string) return null;
        return .{ .file = .{ .path = path.string.bytes(), .mode = mode.string.bytes() } };
    }
    if (std.mem.eql(u8, kind, "null")) return .blackhole;
    if (std.mem.eql(u8, kind, "pty")) {
        try warn(ctx, "PTY (pseudoterminal) not supported on this system", .{});
        return error.RuntimeError;
    }
    if (std.mem.eql(u8, kind, "socket")) {
        try warn(ctx, "socket descriptors are not supported on Windows", .{});
        return error.RuntimeError;
    }
    try warn(ctx, "{s} is not a valid descriptor spec/mode", .{kind});
    return error.RuntimeError;
}

fn parseDescriptors(ctx: *NativeContext, spec: Value, out: *std.ArrayListUnmanaged(Desc)) RuntimeError!void {
    if (spec != .array) return;
    for (spec.array.entries.items) |entry| {
        if (entry.key != .int or entry.key.int < 0) continue;
        const parsed = try parseSpec(ctx, entry.value) orelse continue;
        try out.append(ctx.allocator, .{ .role = entry.key.int, .spec = parsed });
    }
}

fn setInherit(handle: windows.HANDLE, inherit: bool) !void {
    const flag: u32 = if (inherit) windows.HANDLE_FLAG_INHERIT else 0;
    if (kernel32.SetHandleInformation(handle, windows.HANDLE_FLAG_INHERIT, flag) == 0) return error.ProcSpawnFailed;
}

fn makePipe(slot: *Slot, child_reads: bool) !void {
    var rd: windows.HANDLE = undefined;
    var wr: windows.HANDLE = undefined;
    windows.CreatePipe(&rd, &wr, &inheritable) catch return error.ProcSpawnFailed;
    slot.child = if (child_reads) rd else wr;
    slot.parent = if (child_reads) wr else rd;
    try setInherit(slot.parent.?, false);
}

fn duplicateInheritable(source: windows.HANDLE) !windows.HANDLE {
    const me = kernel32.GetCurrentProcess();
    var dup: windows.HANDLE = undefined;
    if (kernel32.DuplicateHandle(me, source, me, &dup, 0, windows.TRUE, windows.DUPLICATE_SAME_ACCESS) == 0) return error.ProcSpawnFailed;
    return dup;
}

fn openBlackhole() !windows.HANDLE {
    const nul = std.unicode.utf8ToUtf16LeStringLiteral("nul");
    const handle = kernel32.CreateFileW(
        nul,
        windows.GENERIC_READ | windows.GENERIC_WRITE,
        windows.FILE_SHARE_READ | windows.FILE_SHARE_WRITE,
        @constCast(&inheritable),
        windows.OPEN_EXISTING,
        0,
        null,
    );
    if (handle == windows.INVALID_HANDLE_VALUE) return error.ProcSpawnFailed;
    return handle;
}

fn prepareSlot(slot: *Slot, spec: Spec) !void {
    switch (spec) {
        .pipe_r => try makePipe(slot, true),
        .pipe_w => try makePipe(slot, false),
        .file => |f| {
            const file = try filesystem.openWithMode(f.path, f.mode);
            slot.child = file.handle;
            try setInherit(file.handle, true);
        },
        .redirect => |fd| {
            const raw = _get_osfhandle(@intCast(fd));
            if (raw == -1 or raw == -2) return error.ProcSpawnFailed;
            slot.child = try duplicateInheritable(@ptrFromInt(@as(usize, @intCast(raw))));
        },
        .blackhole => slot.child = try openBlackhole(),
    }
}

fn stdHandle(id: u32) ?windows.HANDLE {
    return windows.GetStdHandle(id) catch null;
}

fn startupInfo(slots: []const Slot) windows.STARTUPINFOW {
    var si: windows.STARTUPINFOW = std.mem.zeroes(windows.STARTUPINFOW);
    si.cb = @sizeOf(windows.STARTUPINFOW);
    si.dwFlags = windows.STARTF_USESTDHANDLES;
    si.hStdInput = stdHandle(windows.STD_INPUT_HANDLE);
    si.hStdOutput = stdHandle(windows.STD_OUTPUT_HANDLE);
    si.hStdError = stdHandle(windows.STD_ERROR_HANDLE);
    for (slots) |slot| switch (slot.role) {
        0 => si.hStdInput = slot.child,
        1 => si.hStdOutput = slot.child,
        2 => si.hStdError = slot.child,
        else => {},
    };
    return si;
}

// php's windows build hands the command to cmd.exe as `/s /c "<command>"`
// so cmd strips exactly the outer quotes and runs the rest verbatim
fn commandLine(allocator: std.mem.Allocator, command: []const u8) ![:0]u16 {
    const argv = platform.shellArgv(command);
    const joined = try std.fmt.allocPrint(allocator, "{s} /s {s} \"{s}\"", .{ argv[0], argv[1], command });
    defer allocator.free(joined);
    return std.unicode.wtf8ToWtf16LeAllocZ(allocator, joined);
}

fn appendEnvString(allocator: std.mem.Allocator, block: *std.ArrayListUnmanaged(u16), text: []const u8) !void {
    const wide = try std.unicode.wtf8ToWtf16LeAlloc(allocator, text);
    defer allocator.free(wide);
    try block.appendSlice(allocator, wide);
}

fn envValueText(allocator: std.mem.Allocator, v: Value) !?[]const u8 {
    return switch (v) {
        .string => |s| try allocator.dupe(u8, s.bytes()),
        .int => |i| try std.fmt.allocPrint(allocator, "{d}", .{i}),
        .float => |f| try std.fmt.allocPrint(allocator, "{d}", .{f}),
        .bool => |b| try allocator.dupe(u8, if (b) "1" else ""),
        .null => try allocator.dupe(u8, ""),
        else => null,
    };
}

// a unicode environment block: NUL-separated `name=value` strings with a
// second NUL at the end, which an empty block still needs
fn envBlock(allocator: std.mem.Allocator, env: Value) !?[]u16 {
    if (env != .array) return null;
    var block: std.ArrayListUnmanaged(u16) = .{};
    errdefer block.deinit(allocator);
    for (env.array.entries.items) |entry| {
        const text = try envValueText(allocator, entry.value) orelse continue;
        defer allocator.free(text);
        switch (entry.key) {
            .string => |k| try appendEnvString(allocator, &block, k.bytes()),
            .int => |k| {
                const key = try std.fmt.allocPrint(allocator, "{d}", .{k});
                defer allocator.free(key);
                try appendEnvString(allocator, &block, key);
            },
        }
        try block.append(allocator, '=');
        try appendEnvString(allocator, &block, text);
        try block.append(allocator, 0);
    }
    try block.append(allocator, 0);
    if (block.items.len == 1) try block.append(allocator, 0);
    return try block.toOwnedSlice(allocator);
}

const Spawned = struct {
    process: windows.HANDLE,
    pid: u32,
    pipes: std.ArrayListUnmanaged(ProcPipe),
};

const SpawnOptions = struct {
    command: []const u8,
    descs: []const Desc,
    cwd: ?[]const u8,
    env: Value,
};

fn createProcess(allocator: std.mem.Allocator, opts: SpawnOptions, slots: []Slot) !windows.PROCESS_INFORMATION {
    const cmdline = try commandLine(allocator, opts.command);
    defer allocator.free(cmdline);
    const env = try envBlock(allocator, opts.env);
    defer if (env) |e| allocator.free(e);
    const cwd_w: ?[:0]u16 = if (opts.cwd) |dir| try std.unicode.wtf8ToWtf16LeAllocZ(allocator, dir) else null;
    defer if (cwd_w) |w| allocator.free(w);

    var si = startupInfo(slots);
    var pi: windows.PROCESS_INFORMATION = undefined;
    const flags: windows.CreateProcessFlags = .{
        .normal_priority_class = true,
        .create_unicode_environment = env != null,
    };
    const ok = kernel32.CreateProcessW(
        null,
        cmdline.ptr,
        null,
        null,
        windows.TRUE,
        flags,
        if (env) |e| @ptrCast(e.ptr) else null,
        if (cwd_w) |w| w.ptr else null,
        &si,
        &pi,
    );
    if (ok == 0) return error.ProcSpawnFailed;
    return pi;
}

fn spawn(allocator: std.mem.Allocator, opts: SpawnOptions) !Spawned {
    const slots = try allocator.alloc(Slot, opts.descs.len);
    defer allocator.free(slots);
    for (opts.descs, 0..) |desc, i| slots[i] = .{ .role = desc.role };
    errdefer for (slots) |*slot| slot.closeAll();
    for (opts.descs, 0..) |desc, i| try prepareSlot(&slots[i], desc.spec);

    const pi = try createProcess(allocator, opts, slots);
    windows.CloseHandle(pi.hThread);
    for (slots) |*slot| if (slot.child) |h| {
        windows.CloseHandle(h);
        slot.child = null;
    };

    var pipes: std.ArrayListUnmanaged(ProcPipe) = .{};
    errdefer pipes.deinit(allocator);
    for (slots) |*slot| if (slot.parent) |h| {
        try pipes.append(allocator, .{ .role = slot.role, .fd = @intCast(platform.fdFromFile(.{ .handle = h })) });
        slot.parent = null;
    };
    return .{ .process = pi.hProcess, .pid = pi.dwProcessId, .pipes = pipes };
}

fn flushInheritedOutput(ctx: *NativeContext, descs: []const Desc) void {
    var stdout_owned = false;
    var stderr_owned = false;
    for (descs) |desc| {
        if (desc.role == 1) stdout_owned = true;
        if (desc.role == 2) stderr_owned = true;
    }
    if (stdout_owned and stderr_owned) return;
    if (ctx.vm.output.items.len == 0) return;
    platform.writeStdout(ctx.vm.output.items);
    ctx.vm.output.clearRetainingCapacity();
}

fn pipeMode(spec: Spec) ?[]const u8 {
    return switch (spec) {
        .pipe_r => "w",
        .pipe_w => "r",
        else => null,
    };
}

fn pipeFd(pipes: []const ProcPipe, role: i64) ?platform.Fd {
    for (pipes) |pipe| if (pipe.role == role) return pipe.fd;
    return null;
}

fn makePipeHandle(ctx: *NativeContext, proc: *PhpObject, role: i64, fd: platform.Fd, mode: []const u8) RuntimeError!*PhpObject {
    const handle = try ctx.createObject("FileHandle");
    try handle.set(ctx.allocator, "__open", .{ .bool = true });
    try handle.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed(mode) });
    try handle.set(ctx.allocator, "__fd", .{ .int = @intCast(fd) });
    try handle.set(ctx.allocator, "__proc_ref", .{ .object = proc });
    try handle.set(ctx.allocator, "__proc_role", .{ .int = role });
    return handle;
}

fn buildPipesArray(ctx: *NativeContext, proc: *PhpObject, descs: []const Desc, pipes: []const ProcPipe) RuntimeError!Value {
    const arr = try ctx.createArray();
    for (descs) |desc| {
        const mode = pipeMode(desc.spec) orelse continue;
        const fd = pipeFd(pipes, desc.role) orelse continue;
        const handle = try makePipeHandle(ctx, proc, desc.role, fd, mode);
        try arr.set(ctx.allocator, .{ .int = desc.role }, .{ .object = handle });
    }
    return .{ .array = arr };
}

fn markSpawnFailed(ctx: *NativeContext, proc: *PhpObject) RuntimeError!void {
    try proc.set(ctx.allocator, "__pid", .{ .int = 0 });
    try proc.set(ctx.allocator, "__reaped", .{ .bool = true });
    try proc.set(ctx.allocator, "__running", .{ .bool = false });
    try proc.set(ctx.allocator, "__exit", .{ .int = -1 });
}

pub fn native_proc_open(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 3 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const cmd_copy = try ctx.vm.allocator.dupe(u8, args[0].string.bytes());
    try ctx.vm.strings.append(ctx.allocator, cmd_copy);

    const proc = try ctx.createObject("ProcessResource");
    try proc.set(ctx.allocator, "__cmd", .{ .string = Value.String.borrowed(cmd_copy) });
    try proc.set(ctx.allocator, "__exit", .{ .int = 0 });
    try proc.set(ctx.allocator, "__running", .{ .bool = true });

    var descs: std.ArrayListUnmanaged(Desc) = .{};
    defer descs.deinit(ctx.allocator);
    parseDescriptors(ctx, args[1], &descs) catch |err| {
        if (err == error.OutOfMemory) return err;
        if (ctx.vm.pending_exception != null) return err;
        return NativeResult.scalar(.{ .bool = false });
    };
    flushInheritedOutput(ctx, descs.items);

    const opts: SpawnOptions = .{
        .command = cmd_copy,
        .descs = descs.items,
        .cwd = if (args.len >= 4 and args[3] == .string) args[3].string.bytes() else null,
        .env = if (args.len >= 5) args[4] else .null,
    };
    const spawned = spawn(ctx.vm.allocator, opts) catch |err| {
        const code = @intFromEnum(windows.GetLastError());
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try markSpawnFailed(ctx, proc);
        try warn(ctx, "CreateProcess failed: error code {d}", .{code});
        return NativeResult.scalar(.{ .bool = false });
    };
    try ctx.vm.registerProcChild(proc, @intCast(spawned.pid), spawned.pipes);
    ctx.vm.lookupProcChild(proc).?.process = @intFromPtr(spawned.process);
    try proc.set(ctx.allocator, "__pid", .{ .int = @intCast(spawned.pid) });
    try proc.set(ctx.allocator, "__reaped", .{ .bool = false });

    const pipes = try buildPipesArray(ctx, proc, descs.items, spawned.pipes.items);
    ctx.setCallerVar(2, args.len, pipes);
    return NativeResult.borrowed(.{ .object = proc });
}

fn processHandle(pc: *const ProcChild) ?windows.HANDLE {
    if (pc.process == 0) return null;
    return @ptrFromInt(pc.process);
}

fn exitCodeOf(handle: windows.HANDLE) i64 {
    var code: u32 = 0;
    if (kernel32.GetExitCodeProcess(handle, &code) == 0) return -1;
    return @intCast(code);
}

// the exit code once the process has ended, null while it still runs
fn pollExit(handle: windows.HANDLE) ?i64 {
    if (kernel32.WaitForSingleObject(handle, 0) != windows.WAIT_OBJECT_0) return null;
    return exitCodeOf(handle);
}

fn waitExit(handle: windows.HANDLE) i64 {
    _ = kernel32.WaitForSingleObject(handle, windows.INFINITE);
    return exitCodeOf(handle);
}

fn cacheExit(ctx: *NativeContext, proc: *PhpObject, pc: *ProcChild, code: i64) void {
    pc.reaped = true;
    proc.set(ctx.allocator, "__reaped", .{ .bool = true }) catch {};
    proc.set(ctx.allocator, "__running", .{ .bool = false }) catch {};
    proc.set(ctx.allocator, "__exit", .{ .int = code }) catch {};
}

fn closePipe(pipe: *ProcPipe) void {
    if (pipe.fd == -1) return;
    platform.closeFd(pipe.fd);
    pipe.fd = -1;
}

fn cachedExit(proc: *PhpObject) i64 {
    const exit = proc.get("__exit");
    return if (exit == .int) exit.int else 0;
}

pub fn native_proc_close(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.{ .int = -1 });
    const proc = args[0].object;
    const pc = ctx.vm.lookupProcChild(proc) orelse return NativeResult.scalar(.{ .int = cachedExit(proc) });
    for (pc.pipe_fds.items) |*pipe| if (pipe.role == 0) closePipe(pipe);
    if (processHandle(pc)) |handle| {
        if (!pc.reaped) cacheExit(ctx, proc, pc, waitExit(handle));
        windows.CloseHandle(handle);
        pc.process = 0;
    }
    for (pc.pipe_fds.items) |*pipe| closePipe(pipe);
    pc.pipe_fds.deinit(ctx.allocator);
    ctx.vm.removeProcChild(proc);
    return NativeResult.scalar(.{ .int = cachedExit(proc) });
}

pub fn native_proc_get_status(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const proc = args[0].object;
    var running = false;
    if (ctx.vm.lookupProcChild(proc)) |pc| {
        if (!pc.reaped) {
            if (processHandle(pc)) |handle| {
                if (pollExit(handle)) |code| cacheExit(ctx, proc, pc, code) else running = true;
            }
        }
    }
    const result = try ctx.createArray();
    const cmd = proc.get("__cmd");
    const pid = proc.get("__pid");
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("command") }, if (cmd == .string) cmd else .{ .string = Value.String.borrowed("") });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("pid") }, if (pid == .int) pid else .{ .int = 0 });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("running") }, .{ .bool = running });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("signaled") }, .{ .bool = false });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("stopped") }, .{ .bool = false });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("exitcode") }, .{ .int = if (running) -1 else cachedExit(proc) });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("termsig") }, .{ .int = 0 });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("stopsig") }, .{ .int = 0 });
    return NativeResult.borrowed(.{ .array = result });
}

// php's windows build ignores the signal argument and always ends the
// process with exit code 255
pub fn native_proc_terminate(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const pc = ctx.vm.lookupProcChild(args[0].object) orelse return NativeResult.scalar(.{ .bool = false });
    const handle = processHandle(pc) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = kernel32.TerminateProcess(handle, terminate_exit_code) != 0 });
}

// whether a read on the crt descriptor would return without blocking: data
// is waiting, the writer has gone away, or the handle is not a pipe at all
pub fn pipeReadable(fd: i64) bool {
    if (fd < 0) return true;
    const raw = _get_osfhandle(@intCast(fd));
    if (raw == -1 or raw == -2) return true;
    const handle: windows.HANDLE = @ptrFromInt(@as(usize, @intCast(raw)));
    var available: u32 = 0;
    if (PeekNamedPipe(handle, null, 0, null, &available, null) == 0) return true;
    return available > 0;
}
