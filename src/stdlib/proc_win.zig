// proc_open on win32. the descriptor spec becomes inheritable child ends
// (CreatePipe pairs, opened files, duplicated stream handles), cmd.exe runs
// the command through CreateProcessW, and the parent pipe ends turn into
// crt descriptors so the FileHandle natives use them like any other stream
const std = @import("std");
const win32 = @import("../win32.zig");
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

const terminate_exit_code: u32 = 255;

const inheritable: win32.SECURITY_ATTRIBUTES = .{
    .nLength = @sizeOf(win32.SECURITY_ATTRIBUTES),
    .lpSecurityDescriptor = null,
    .bInheritHandle = win32.TRUE,
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
    child: ?win32.HANDLE = null,
    parent: ?win32.HANDLE = null,

    fn closeAll(self: *Slot) void {
        if (self.child) |h| _ = win32.CloseHandle(h);
        if (self.parent) |h| _ = win32.CloseHandle(h);
        self.child = null;
        self.parent = null;
    }
};

fn warn(ctx: *NativeContext, comptime fmt: []const u8, args: anytype) RuntimeError!void {
    const msg = try std.fmt.allocPrint(ctx.allocator, "proc_open(): " ++ fmt, args);
    defer ctx.allocator.free(msg);
    try ctx.vm.emitWarning(msg);
}

fn parseSpec(ctx: *NativeContext, item: Value) RuntimeError!?Spec {
    if (item == .resource) {
        const fdv = item.resource.get("__fd");
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

fn setInherit(handle: win32.HANDLE, inherit: bool) !void {
    const flag: u32 = if (inherit) win32.HANDLE_FLAG_INHERIT else 0;
    if (win32.SetHandleInformation(handle, win32.HANDLE_FLAG_INHERIT, flag) == 0) return error.ProcSpawnFailed;
}

fn makePipe(slot: *Slot, child_reads: bool) !void {
    var rd: win32.HANDLE = undefined;
    var wr: win32.HANDLE = undefined;
    if (win32.CreatePipe(&rd, &wr, &inheritable, 0) == 0) return error.ProcSpawnFailed;
    slot.child = if (child_reads) rd else wr;
    slot.parent = if (child_reads) wr else rd;
    try setInherit(slot.parent.?, false);
}

fn duplicateInheritable(source: win32.HANDLE) !win32.HANDLE {
    const me = win32.GetCurrentProcess();
    var dup: win32.HANDLE = undefined;
    if (win32.DuplicateHandle(me, source, me, &dup, 0, win32.TRUE, win32.DUPLICATE_SAME_ACCESS) == 0) return error.ProcSpawnFailed;
    return dup;
}

fn openBlackhole() !win32.HANDLE {
    const nul = std.unicode.utf8ToUtf16LeStringLiteral("nul");
    const handle = win32.CreateFileW(
        nul,
        win32.GENERIC_READ | win32.GENERIC_WRITE,
        win32.FILE_SHARE_READ | win32.FILE_SHARE_WRITE,
        @constCast(&inheritable),
        win32.OPEN_EXISTING,
        0,
        null,
    );
    if (handle == win32.INVALID_HANDLE_VALUE) return error.ProcSpawnFailed;
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

fn stdHandle(id: u32) ?win32.HANDLE {
    const h = win32.GetStdHandle(id) orelse return null;
    return if (h == win32.INVALID_HANDLE_VALUE) null else h;
}

fn startupInfo(slots: []const Slot) win32.STARTUPINFOW {
    var si: win32.STARTUPINFOW = std.mem.zeroes(win32.STARTUPINFOW);
    si.cb = @sizeOf(win32.STARTUPINFOW);
    si.dwFlags = win32.STARTF_USESTDHANDLES;
    si.hStdInput = stdHandle(win32.STD_INPUT_HANDLE);
    si.hStdOutput = stdHandle(win32.STD_OUTPUT_HANDLE);
    si.hStdError = stdHandle(win32.STD_ERROR_HANDLE);
    for (slots) |slot| switch (slot.role) {
        0 => si.hStdInput = slot.child,
        1 => si.hStdOutput = slot.child,
        2 => si.hStdError = slot.child,
        else => {},
    };
    return si;
}

// a string command goes to cmd.exe as `/s /c "<command>"`, so cmd strips
// exactly the outer quotes and runs the rest verbatim; an array command
// runs directly, each argument quoted the way the C runtime splits them
fn commandLine(allocator: std.mem.Allocator, command: Command) ![:0]u16 {
    const joined = switch (command) {
        .shell => |line| blk: {
            const argv = platform.shellArgv(line);
            break :blk try std.fmt.allocPrint(allocator, "{s} /s {s} \"{s}\"", .{ argv[0], argv[1], line });
        },
        .argv => |words| try argvLine(allocator, words),
    };
    defer allocator.free(joined);
    return std.unicode.wtf8ToWtf16LeAllocZ(allocator, joined);
}

const Command = union(enum) { shell: []const u8, argv: []const []const u8 };

fn argvLine(allocator: std.mem.Allocator, words: []const []const u8) ![]u8 {
    var line: std.ArrayListUnmanaged(u8) = .empty;
    errdefer line.deinit(allocator);
    for (words, 0..) |word, i| {
        if (i > 0) try line.append(allocator, ' ');
        try appendQuotedArg(allocator, &line, word);
    }
    return line.toOwnedSlice(allocator);
}

// backslashes are literal unless they precede a quote, where each one needs
// doubling; a quote is escaped, and an argument with a space or tab, or an
// empty one, is wrapped in quotes
fn appendQuotedArg(allocator: std.mem.Allocator, line: *std.ArrayListUnmanaged(u8), arg: []const u8) !void {
    const quote = arg.len == 0 or std.mem.indexOfAny(u8, arg, " \t") != null;
    if (quote) try line.append(allocator, '"');
    var backslashes: usize = 0;
    for (arg) |c| {
        if (c == '\\') {
            backslashes += 1;
            continue;
        }
        const run = if (c == '"') backslashes * 2 + 1 else backslashes;
        try line.appendNTimes(allocator, '\\', run);
        backslashes = 0;
        try line.append(allocator, c);
    }
    try line.appendNTimes(allocator, '\\', if (quote) backslashes * 2 else backslashes);
    if (quote) try line.append(allocator, '"');
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
    var block: std.ArrayListUnmanaged(u16) = .empty;
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
    process: win32.HANDLE,
    pid: u32,
    pipes: std.ArrayListUnmanaged(ProcPipe),
};

const SpawnOptions = struct {
    command: Command,
    descs: []const Desc,
    cwd: ?[]const u8,
    env: Value,
};

fn createProcess(allocator: std.mem.Allocator, opts: SpawnOptions, slots: []Slot) !win32.PROCESS_INFORMATION {
    const cmdline = try commandLine(allocator, opts.command);
    defer allocator.free(cmdline);
    const env = try envBlock(allocator, opts.env);
    defer if (env) |e| allocator.free(e);
    const cwd_w: ?[:0]u16 = if (opts.cwd) |dir| try std.unicode.wtf8ToWtf16LeAllocZ(allocator, dir) else null;
    defer if (cwd_w) |w| allocator.free(w);

    var si = startupInfo(slots);
    var pi: win32.PROCESS_INFORMATION = undefined;
    const flags: win32.DWORD = win32.NORMAL_PRIORITY_CLASS | (if (env != null) win32.CREATE_UNICODE_ENVIRONMENT else 0);
    const ok = win32.CreateProcessW(
        null,
        cmdline.ptr,
        null,
        null,
        win32.TRUE,
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
    _ = win32.CloseHandle(pi.hThread);
    for (slots) |*slot| if (slot.child) |h| {
        _ = win32.CloseHandle(h);
        slot.child = null;
    };

    var pipes: std.ArrayListUnmanaged(ProcPipe) = .empty;
    errdefer pipes.deinit(allocator);
    for (slots) |*slot| if (slot.parent) |h| {
        try pipes.append(allocator, .{ .role = slot.role, .fd = @intCast(platform.fdFromFile(platform.fileFromHandle(h))) });
        slot.parent = null;
    };
    return .{ .process = pi.hProcess, .pid = pi.dwProcessId, .pipes = pipes };
}

// shell_exec, exec, system and passthru: the line runs as proc_open's does,
// stdout comes back through a pipe, stdin and stderr stay zphp's
pub fn runShell(allocator: std.mem.Allocator, command: []const u8) !struct { stdout: []u8, exit_code: i64 } {
    const descs = [_]Desc{.{ .role = 1, .spec = .pipe_w }};
    var spawned = try spawn(allocator, .{ .command = .{ .shell = command }, .descs = &descs, .cwd = null, .env = .null });
    defer spawned.pipes.deinit(allocator);
    defer _ = win32.CloseHandle(spawned.process);
    const fd = spawned.pipes.items[0].fd;
    defer platform.closeFd(fd);
    const file = platform.fileFromFd(fd) orelse return error.ProcSpawnFailed;
    const stdout = try platform.readToEndAlloc(file, allocator, 64 * 1024 * 1024);
    return .{ .stdout = stdout, .exit_code = waitExit(spawned.process) };
}

fn flushInheritedOutput(ctx: *NativeContext, descs: []const Desc) void {
    var stdout_owned = false;
    var stderr_owned = false;
    for (descs) |desc| {
        if (desc.role == 1) stdout_owned = true;
        if (desc.role == 2) stderr_owned = true;
    }
    if (stdout_owned and stderr_owned) return;
    ctx.vm.flushOutputToStdout();
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
    const handle = try ctx.createResource("FileHandle");
    try handle.set(ctx.allocator, "__open", .{ .bool = true });
    try handle.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed(mode) });
    try handle.set(ctx.allocator, "__fd", .{ .int = @intCast(fd) });
    try handle.set(ctx.allocator, "__proc_ref", .{ .resource = proc });
    try handle.set(ctx.allocator, "__proc_role", .{ .int = role });
    return handle;
}

fn buildPipesArray(ctx: *NativeContext, proc: *PhpObject, descs: []const Desc, pipes: []const ProcPipe) RuntimeError!Value {
    const arr = try ctx.createArray();
    for (descs) |desc| {
        const mode = pipeMode(desc.spec) orelse continue;
        const fd = pipeFd(pipes, desc.role) orelse continue;
        const handle = try makePipeHandle(ctx, proc, desc.role, fd, mode);
        try arr.set(ctx.allocator, .{ .int = desc.role }, .{ .resource = handle });
        ctx.vm.adoptProcPipe(proc, desc.role, handle);
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
    if (args.len < 3 or (args[0] != .string and args[0] != .array)) return NativeResult.scalar(.{ .bool = false });
    var words: std.ArrayListUnmanaged([]const u8) = .empty;
    defer words.deinit(ctx.allocator);
    if (args[0] == .array) {
        for (args[0].array.entries.items) |entry| try words.append(ctx.allocator, try filesystem.ownedText(ctx, entry.value));
        if (words.items.len == 0) {
            try ctx.vm.setPendingException("ValueError", "proc_open(): Argument #1 ($command) must not be empty");
            return error.RuntimeError;
        }
    }
    const cmd_str = try Value.String.adopt(ctx.vm.allocator, if (args[0] == .string)
        try ctx.vm.allocator.dupe(u8, args[0].string.bytes())
    else
        try argvLine(ctx.vm.allocator, words.items));
    defer cmd_str.release();
    const cmd_copy = cmd_str.bytes();

    const proc = try ctx.vm.allocResource("ProcessResource");
    try proc.set(ctx.allocator, "__cmd", .{ .string = cmd_str });
    try proc.set(ctx.allocator, "__exit", .{ .int = 0 });
    try proc.set(ctx.allocator, "__running", .{ .bool = true });

    var descs: std.ArrayListUnmanaged(Desc) = .empty;
    defer descs.deinit(ctx.allocator);
    parseDescriptors(ctx, args[1], &descs) catch |err| {
        if (err == error.OutOfMemory) return err;
        if (ctx.vm.pending_exception != null) return err;
        return NativeResult.scalar(.{ .bool = false });
    };
    flushInheritedOutput(ctx, descs.items);

    const opts: SpawnOptions = .{
        .command = if (args[0] == .string) .{ .shell = cmd_copy } else .{ .argv = words.items },
        .descs = descs.items,
        .cwd = if (args.len >= 4 and args[3] == .string) args[3].string.bytes() else null,
        .env = if (args.len >= 5) args[4] else .null,
    };
    const spawned = spawn(ctx.vm.allocator, opts) catch |err| {
        const code = win32.GetLastError();
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
    ctx.vm.numberResource(proc);
    ctx.setCallerVar(2, args.len, pipes);
    return NativeResult.borrowed(.{ .resource = proc });
}

fn processHandle(pc: *const ProcChild) ?win32.HANDLE {
    if (pc.process == 0) return null;
    return @ptrFromInt(pc.process);
}

// php reads the DWORD exit code into an int
fn exitCodeOf(handle: win32.HANDLE) i64 {
    var code: u32 = 0;
    if (win32.GetExitCodeProcess(handle, &code) == 0) return -1;
    return @as(i32, @bitCast(code));
}

// the exit code once the process has ended, null while it still runs
fn pollExit(handle: win32.HANDLE) ?i64 {
    if (win32.WaitForSingleObject(handle, 0) != win32.WAIT_OBJECT_0) return null;
    return exitCodeOf(handle);
}

fn waitExit(handle: win32.HANDLE) i64 {
    _ = win32.WaitForSingleObject(handle, win32.INFINITE);
    return exitCodeOf(handle);
}

fn cacheExit(ctx: *NativeContext, proc: *PhpObject, pc: *ProcChild, code: i64) void {
    pc.reaped = true;
    proc.set(ctx.allocator, "__reaped", .{ .bool = true }) catch {};
    proc.set(ctx.allocator, "__running", .{ .bool = false }) catch {};
    proc.set(ctx.allocator, "__exit", .{ .int = code }) catch {};
}

fn cachedExit(proc: *PhpObject) i64 {
    const exit = proc.get("__exit");
    return if (exit == .int) exit.int else 0;
}

pub fn native_proc_close(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const proc = try filesystem.processArg(ctx, args, "proc_close");
    try proc.set(ctx.allocator, "__open", .{ .bool = false });
    const pc = ctx.vm.lookupProcChild(proc) orelse return NativeResult.scalar(.{ .int = cachedExit(proc) });
    for (pc.pipe_fds.items) |*pipe| if (pipe.role == 0) pipe.close();
    if (processHandle(pc)) |handle| {
        if (!pc.reaped) cacheExit(ctx, proc, pc, waitExit(handle));
        _ = win32.CloseHandle(handle);
        pc.process = 0;
    }
    ctx.vm.closeProcChild(proc);
    return NativeResult.scalar(.{ .int = cachedExit(proc) });
}

pub fn native_proc_get_status(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const proc = try filesystem.processArg(ctx, args, "proc_get_status");
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
    const proc = try filesystem.processArg(ctx, args, "proc_terminate");
    const pc = ctx.vm.lookupProcChild(proc) orelse return NativeResult.scalar(.{ .bool = false });
    const handle = processHandle(pc) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = win32.TerminateProcess(handle, terminate_exit_code) != 0 });
}

// whether a read on the crt descriptor would return without blocking: data
// is waiting, the writer has gone away, or the handle is not a pipe at all
pub fn pipeReadable(fd: i64) bool {
    if (fd < 0) return true;
    const raw = _get_osfhandle(@intCast(fd));
    if (raw == -1 or raw == -2) return true;
    const handle: win32.HANDLE = @ptrFromInt(@as(usize, @intCast(raw)));
    var available: u32 = 0;
    if (win32.PeekNamedPipe(handle, null, 0, null, &available, null) == 0) return true;
    return available > 0;
}
