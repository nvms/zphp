// the seam between zphp and the operating system. posix targets pass
// straight through; windows gets the equivalent in terms of the win32 crt
// that mingw exposes, so the rest of the runtime keeps its file-descriptor-
// as-int and byte-string-environment conventions on every platform
const std = @import("std");
const builtin = @import("builtin");
const sys = @import("sys.zig");
const net = @import("net.zig");
const sync = @import("sync.zig");
const win32 = @import("win32.zig");

pub const is_windows = builtin.os.tag == .windows;
pub const is_macos = builtin.os.tag == .macos;

// the process's io implementation. main installs the one it builds at
// startup; unit tests use the test runner's, and until main runs a
// single-threaded instance serves
pub var io: std.Io = if (builtin.is_test) std.testing.io else std.Io.Threaded.global_single_threaded.io();

pub const File = std.Io.File;

// a loaded shared library; std has no windows implementation
pub const DynLib = if (is_windows) win32.DynLib else std.DynLib;

// a php-visible descriptor as a blocking std file
pub fn fileFromHandle(handle: File.Handle) File {
    return .{ .handle = handle, .flags = .{ .nonblocking = false } };
}

// wall-clock time, what php's time functions report
pub fn nanoTimestamp() i128 {
    return std.Io.Clock.real.now(io).nanoseconds;
}

pub fn microTimestamp() i64 {
    return @intCast(@divFloor(nanoTimestamp(), std.time.ns_per_us));
}

pub fn milliTimestamp() i64 {
    return @intCast(@divFloor(nanoTimestamp(), std.time.ns_per_ms));
}

pub fn timestamp() i64 {
    return @intCast(@divFloor(nanoTimestamp(), std.time.ns_per_s));
}

// a clock that never jumps, for measuring intervals and deadlines
pub fn monotonicNanos() i128 {
    return std.Io.Clock.awake.now(io).nanoseconds;
}

pub fn sleep(ns: u64) void {
    io.sleep(.fromNanoseconds(ns), .awake) catch {};
}

// a file's descriptor-level position, shared with whoever else holds it
pub fn seekTo(file: File, offset: u64) !void {
    _ = try sys.lseek(file.handle, @intCast(offset), .set);
}

pub fn seekBy(file: File, offset: i64) !void {
    _ = try sys.lseek(file.handle, offset, .cur);
}

pub fn seekFromEnd(file: File, offset: i64) !void {
    _ = try sys.lseek(file.handle, offset, .end);
}

pub fn getPos(file: File) !u64 {
    return sys.lseek(file.handle, 0, .cur);
}

pub fn getEndPos(file: File) !u64 {
    return file.length(io);
}

// reads at the current position; 0 at end of file
pub fn read(file: File, buf: []u8) !usize {
    if (buf.len == 0) return 0;
    return file.readStreaming(io, &.{buf}) catch |err| switch (err) {
        error.EndOfStream => 0,
        else => |e| e,
    };
}

pub fn readAll(file: File, buf: []u8) !usize {
    var n: usize = 0;
    while (n < buf.len) {
        const got = try read(file, buf[n..]);
        if (got == 0) break;
        n += got;
    }
    return n;
}

pub fn write(file: File, bytes: []const u8) !usize {
    return file.writeStreaming(io, "", &.{bytes}, 1);
}

pub fn writeAll(file: File, bytes: []const u8) !void {
    return file.writeStreamingAll(io, bytes);
}

// environment strings on windows are wtf-16; a lookup converts once and the
// result lives for the process, which is all the debug-flag and config
// callers need
var env_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var env_mutex: sync.Mutex = .{};

pub fn getenv(name: []const u8) ?[]const u8 {
    if (!is_windows) return sys.getenv(name);
    env_mutex.lock();
    defer env_mutex.unlock();
    const a = env_arena.allocator();
    const wide_name = std.unicode.wtf8ToWtf16LeAllocZ(a, name) catch return null;
    const len = win32.GetEnvironmentVariableW(wide_name.ptr, null, 0);
    if (len == 0) return null;
    const buf = a.alloc(u16, len) catch return null;
    const got = win32.GetEnvironmentVariableW(wide_name.ptr, buf.ptr, len);
    if (got == 0 or got >= len) return null;
    return std.unicode.wtf16LeToWtf8Alloc(a, buf[0..got]) catch null;
}

// the environment as it stands now, putenv changes included
pub fn liveEnviron() std.process.Environ {
    if (is_windows) return .{ .block = .global };
    return .{ .block = .{ .slice = std.mem.sliceTo(@as([*:null]const ?[*:0]const u8, @ptrCast(std.c.environ)), null) } };
}

pub fn getEnvMap(a: std.mem.Allocator) !std.process.Environ.Map {
    return liveEnviron().createMap(a);
}

pub fn getCwd(buf: []u8) ![]u8 {
    const n = try std.process.currentPath(io, buf);
    return buf[0..n];
}

pub fn getCwdAlloc(a: std.mem.Allocator) ![]u8 {
    var buf: [max_path_bytes]u8 = undefined;
    return a.dupe(u8, try getCwd(&buf));
}

pub fn selfExePathAlloc(a: std.mem.Allocator) ![]u8 {
    var buf: [max_path_bytes]u8 = undefined;
    const n = try std.process.executablePath(io, &buf);
    return a.dupe(u8, buf[0..n]);
}

// the canonical absolute form of a path, symlinks resolved
pub fn realpath(path: []const u8, buf: []u8) ![]u8 {
    const n = try std.Io.Dir.cwd().realPathFile(io, path, buf);
    return buf[0..n];
}

pub fn realpathAlloc(a: std.mem.Allocator, path: []const u8) ![]u8 {
    var buf: [max_path_bytes]u8 = undefined;
    return a.dupe(u8, try realpath(path, &buf));
}

// where zphp keeps per-user data such as the compile cache
pub fn appDataDir(a: std.mem.Allocator, app: []const u8) ![]u8 {
    if (is_windows) {
        const base = getenv("LOCALAPPDATA") orelse return error.AppDataDirUnavailable;
        return std.fs.path.join(a, &.{ base, app });
    }
    const home = getenv("HOME") orelse return error.AppDataDirUnavailable;
    if (is_macos) return std.fs.path.join(a, &.{ home, "Library", "Application Support", app });
    if (getenv("XDG_DATA_HOME")) |xdg| {
        if (xdg.len > 0) return std.fs.path.join(a, &.{ xdg, app });
    }
    return std.fs.path.join(a, &.{ home, ".local", "share", app });
}

pub fn getenvOwned(a: std.mem.Allocator, name: []const u8) ![]u8 {
    return a.dupe(u8, getenv(name) orelse return error.EnvironmentVariableNotFound);
}

fn fillRandom(_: *anyopaque, buf: []u8) void {
    io.random(buf);
}

// the process's cryptographically secure random source
pub const random: std.Random = .{ .ptr = @ptrCast(&io), .fillFn = fillRandom };

pub fn readToEndAlloc(file: File, a: std.mem.Allocator, max_bytes: usize) ![]u8 {
    var reader = file.readerStreaming(io, &.{});
    return reader.interface.allocRemaining(a, .limited(max_bytes)) catch |err| switch (err) {
        error.ReadFailed => reader.err.?,
        error.StreamTooLong => error.FileTooBig,
        error.OutOfMemory => error.OutOfMemory,
    };
}

pub const ChildStdio = enum { inherit, pipe, ignore };

pub const ChildResult = struct {
    stdout: []u8,
    stderr: []u8,
    term: std.process.Child.Term,
};

// runs a command to completion with the current environment (putenv
// included), feeding it stdin_data and collecting the piped streams
pub fn runChild(a: std.mem.Allocator, argv: []const []const u8, options: struct {
    stdin_data: ?[]const u8 = null,
    stdin: ChildStdio = .inherit,
    stdout: ChildStdio = .pipe,
    stderr: ChildStdio = .inherit,
    max_output: usize = 64 * 1024 * 1024,
}) !ChildResult {
    var env = try getEnvMap(a);
    defer env.deinit();
    const stdio = struct {
        fn of(b: ChildStdio) std.process.SpawnOptions.StdIo {
            return switch (b) {
                .inherit => .inherit,
                .pipe => .pipe,
                .ignore => .ignore,
            };
        }
    }.of;
    var child = try std.process.spawn(io, .{
        .argv = argv,
        .environ_map = &env,
        .stdin = if (options.stdin_data != null) .pipe else stdio(options.stdin),
        .stdout = stdio(options.stdout),
        .stderr = stdio(options.stderr),
    });
    defer if (child.id != null) child.kill(io);
    if (options.stdin_data) |data| {
        if (child.stdin) |stdin_file| {
            stdin_file.writeStreamingAll(io, data) catch {};
            stdin_file.close(io);
            child.stdin = null;
        }
    }
    var out: []u8 = &.{};
    var err_out: []u8 = &.{};
    errdefer a.free(out);
    errdefer a.free(err_out);
    if (child.stdout != null and child.stderr != null) {
        var buffer: std.Io.File.MultiReader.Buffer(2) = undefined;
        var multi: std.Io.File.MultiReader = undefined;
        multi.init(a, io, buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
        defer multi.deinit();
        while (multi.fill(64, .none)) |_| {
            if (multi.reader(0).buffered().len > options.max_output or multi.reader(1).buffered().len > options.max_output) return error.StreamTooLong;
        } else |e| switch (e) {
            error.EndOfStream => {},
            else => |other| return other,
        }
        try multi.checkAnyError();
        out = try multi.toOwnedSlice(0);
        err_out = try multi.toOwnedSlice(1);
    } else if (child.stdout) |f| {
        out = try readToEndAlloc(f, a, options.max_output);
    } else if (child.stderr) |f| {
        err_out = try readToEndAlloc(f, a, options.max_output);
    }
    const term = try child.wait(io);
    return .{ .stdout = out, .stderr = err_out, .term = term };
}

// php's view of how a child ended: its exit status, or 128 plus the signal
pub fn exitStatus(term: std.process.Child.Term) i64 {
    return switch (term) {
        .exited => |c| @intCast(c),
        .signal => |sig| @as(i64, @backingInt(sig)) + 128,
        else => -1,
    };
}

pub fn stdout() File {
    return File.stdout();
}

pub fn stderr() File {
    return File.stderr();
}

pub fn writeStdout(bytes: []const u8) void {
    writeAll(stdout(), bytes) catch {};
}

pub fn writeStderr(bytes: []const u8) void {
    writeAll(stderr(), bytes) catch {};
}

// php scripts hold open files as small integers. on posix that is the fd
// itself; on windows the crt keeps the same table behind _open_osfhandle
extern "c" fn _open_osfhandle(handle: isize, flags: c_int) c_int;
extern "c" fn _get_osfhandle(fd: c_int) isize;

pub fn fdFromFile(file: File) i64 {
    if (!is_windows) return @intCast(file.handle);
    return @intCast(_open_osfhandle(@intCast(@intFromPtr(file.handle)), 0));
}

pub fn fileFromFd(fd: i64) ?File {
    if (fd < 0) return null;
    if (!is_windows) return fileFromHandle(@intCast(fd));
    const raw = _get_osfhandle(@intCast(fd));
    if (raw == -1 or raw == -2) return null;
    return fileFromHandle(@ptrFromInt(@as(usize, @intCast(raw))));
}

pub fn stdinFd() i64 {
    return if (is_windows) 0 else std.posix.STDIN_FILENO;
}

// the directory php's sys_get_temp_dir and tmpfile use
pub fn tempDir() []const u8 {
    if (is_windows) return getenv("TEMP") orelse getenv("TMP") orelse "C:\\Windows\\Temp";
    return getenv("TMPDIR") orelse "/tmp";
}

// ends the process with php's int exit status: posix passes on its low byte,
// windows the whole value
pub fn exitWithStatus(code: i32) noreturn {
    if (is_windows) {
        const ExitProcess = @extern(*const fn (u32) callconv(.winapi) noreturn, .{ .name = "ExitProcess", .library_name = "kernel32" });
        ExitProcess(@bitCast(code));
    }
    std.process.exit(@truncate(@as(u32, @bitCast(code))));
}

// argv for running a shell command line the way php's shell functions do
pub fn shellArgv(command: []const u8) [3][]const u8 {
    return if (is_windows) .{ "cmd.exe", "/c", command } else .{ "/bin/sh", "-c", command };
}

// small-integer descriptors and pids as php scripts and the proc registry
// see them; on posix these are the kernel's own types
pub const Fd = i32;
pub const Pid = if (is_windows) i32 else std.posix.pid_t;

extern "c" fn _close(fd: c_int) c_int;
extern "c" fn _isatty(fd: c_int) c_int;

pub fn closeFd(fd: i64) void {
    if (fd < 0) return;
    if (is_windows) {
        _ = _close(@intCast(fd));
    } else {
        sys.close(@intCast(fd));
    }
}

pub fn isatty(fd: i64) bool {
    if (fd < 0) return false;
    if (is_windows) return _isatty(@intCast(fd)) != 0;
    return sys.isatty(@intCast(fd));
}

pub fn isStdout(file: File) bool {
    return if (is_windows) file.handle == stdout().handle else file.handle == 1;
}

pub fn isStderr(file: File) bool {
    return if (is_windows) file.handle == stderr().handle else file.handle == 2;
}

pub fn isStdio(file: File) bool {
    if (is_windows) return file.handle == stdout().handle or file.handle == stderr().handle or file.handle == File.stdin().handle;
    return file.handle <= 2;
}

pub fn getpid() i64 {
    if (is_windows) return @intCast(win32.GetCurrentProcessId());
    return @intCast(std.c.getpid());
}

// sockets are handles on windows and descriptors elsewhere; php sees ints
pub fn socketToInt(sock: std.posix.socket_t) i64 {
    if (is_windows) return @intCast(@intFromPtr(sock));
    return @intCast(sock);
}

pub fn socketFromInt(v: i64) ?std.posix.socket_t {
    if (v < 0) return null;
    if (is_windows) return @ptrFromInt(@as(usize, @intCast(v)));
    return @intCast(v);
}

pub fn closeSocket(v: i64) void {
    sys.closeSocket(socketFromInt(v) orelse return);
}

pub fn hostname(buf: []u8) ?[]const u8 {
    if (is_windows) {
        const name = getenv("COMPUTERNAME") orelse return null;
        if (name.len > buf.len) return null;
        @memcpy(buf[0..name.len], name);
        return buf[0..name.len];
    }
    var local: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const name = std.posix.gethostname(&local) catch return null;
    if (name.len > buf.len) return null;
    @memcpy(buf[0..name.len], name);
    return buf[0..name.len];
}

extern "c" fn _wopen(path: [*:0]const u16, flags: c_int, mode: c_int) c_int;

// fopen's 'a' modes: every write goes to the end, whatever the position. on
// windows the crt's O_APPEND gives exactly php's behavior there (ftell reads
// 0 until the first write), so the file comes from the crt
pub fn openAppend(path: []const u8, read_too: bool) !File {
    if (is_windows) {
        const o_rdwr: c_int = 2;
        const o_wronly: c_int = 1;
        const o_append: c_int = 0x8;
        const o_creat: c_int = 0x100;
        const o_binary: c_int = 0x8000;
        var buf: [max_path_bytes]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        const wide = std.unicode.wtf8ToWtf16LeAllocZ(fba.allocator(), path) catch return error.NameTooLong;
        const fd = _wopen(wide.ptr, (if (read_too) o_rdwr else o_wronly) | o_append | o_creat | o_binary, 0o666);
        if (fd < 0) return error.FileNotFound;
        return fileFromFd(fd) orelse error.FileNotFound;
    }
    const flags: std.posix.O = .{
        .ACCMODE = if (read_too) .RDWR else .WRONLY,
        .APPEND = true,
        .CREAT = true,
    };
    return fileFromHandle(try sys.open(path, flags, 0o666));
}

// std.posix.socket's flag handling references fcntl even on windows, where
// no crt provides it; the call sits behind the windows branch that already
// returned, so a stub that is never reached satisfies the linker. exported
// from main.zig only, so the fast_loop object does not define it twice
pub fn fcntlStub(_: c_int, _: c_int, ...) callconv(.c) c_int {
    return -1;
}

// closing a php handle: the crt owns windows descriptors, so the crt closes
// them (which closes the handle too)
pub fn closeFile(file: File, fd: i64) void {
    if (is_windows) {
        closeFd(fd);
    } else {
        file.close(io);
    }
}

// windows reports no unix mode; php there synthesizes 0666 for files and
// 0777 for directories, with the type bits on top
pub fn modeOf(st: File.Stat) u32 {
    if (!is_windows) return @as(u32, @intCast(@backingInt(st.permissions))) | typeBits(st.kind);
    return switch (st.kind) {
        .directory => 0o40777,
        .sym_link => 0o120777,
        else => 0o100666,
    };
}

pub fn permissionsFromMode(mode: u32) File.Permissions {
    if (is_windows) return if (mode & 0o222 == 0) @fromBackingInt(@intCast(file_attribute_readonly)) else .default_file;
    return .fromMode(@intCast(mode));
}

fn typeBits(kind: File.Kind) u32 {
    return switch (kind) {
        .directory => 0o040000,
        .sym_link => 0o120000,
        .character_device => 0o020000,
        .block_device => 0o060000,
        .named_pipe => 0o010000,
        .unix_domain_socket => 0o140000,
        else => 0o100000,
    };
}

pub const max_path_bytes = std.fs.max_path_bytes;

pub fn isSep(c: u8) bool {
    return c == '/' or (is_windows and c == '\\');
}

pub const sep_str: []const u8 = if (is_windows) "\\" else "/";

// stat of a path that may be a directory: on windows statFile opens the path
// as a file, which a directory refuses
pub fn statPath(path: []const u8) !File.Stat {
    const cwd = std.Io.Dir.cwd();
    return cwd.statFile(io, path, .{}) catch |err| {
        if (!is_windows) return err;
        var dir = cwd.openDir(io, path, .{}) catch return err;
        defer dir.close(io);
        return dir.stat(io);
    };
}

const ProcessMemoryCounters = extern struct {
    cb: u32,
    page_fault_count: u32,
    peak_working_set_size: usize,
    working_set_size: usize,
    quota_peak_paged_pool_usage: usize,
    quota_paged_pool_usage: usize,
    quota_peak_non_paged_pool_usage: usize,
    quota_non_paged_pool_usage: usize,
    pagefile_usage: usize,
    peak_pagefile_usage: usize,
};

extern "kernel32" fn K32GetProcessMemoryInfo(process: win32.HANDLE, counters: *ProcessMemoryCounters, cb: u32) callconv(.winapi) c_int;
const file_attribute_readonly: u32 = 0x1;
const invalid_file_attributes: u32 = 0xffffffff;

// the process's peak resident size, what memory_get_peak_usage reports
pub fn peakRss() i64 {
    if (is_windows) {
        var counters: ProcessMemoryCounters = undefined;
        counters.cb = @sizeOf(ProcessMemoryCounters);
        if (K32GetProcessMemoryInfo(win32.GetCurrentProcess(), &counters, counters.cb) == 0) return 0;
        return @intCast(counters.peak_working_set_size);
    } else {
        var usage: std.c.rusage = undefined;
        if (std.c.getrusage(std.c.rusage.SELF, &usage) != 0) return 0;
        const mult: i64 = if (is_macos) 1 else 1024;
        return @as(i64, @intCast(usage.maxrss)) * mult;
    }
}

// windows' read-only attribute is the only "not writable" a plain file has
pub fn isReadOnly(path: []const u8) bool {
    if (!is_windows) return false;
    var buf: [max_path_bytes]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const wide = std.unicode.wtf8ToWtf16LeAllocZ(fba.allocator(), path) catch return false;
    const attrs = win32.GetFileAttributesW(wide.ptr);
    if (attrs == invalid_file_attributes) return false;
    return (attrs & file_attribute_readonly) != 0;
}

// FILE_ATTRIBUTE_READONLY on or off, keeping the other attributes
pub fn setReadOnly(path: []const u8, read_only: bool) bool {
    if (!is_windows) return false;
    var buf: [max_path_bytes]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const wide = std.unicode.wtf8ToWtf16LeAllocZ(fba.allocator(), path) catch return false;
    const attrs = win32.GetFileAttributesW(wide.ptr);
    if (attrs == invalid_file_attributes) return false;
    const readonly_bit: u32 = file_attribute_readonly;
    const next = if (read_only) attrs | readonly_bit else attrs & ~readonly_bit;
    return win32.SetFileAttributesW(wide.ptr, next) != 0;
}

// tcp sockets are created here so windows gets synchronous (non-overlapped)
// handles, which work with ReadFile/WriteFile as well as winsock calls
pub fn tcpSocket(family: u32) !std.posix.socket_t {
    try sys.winsockStartup();
    if (is_windows) return sys.socket(family, std.posix.SOCK.STREAM, std.posix.IPPROTO.TCP);
    return sys.socket(family, std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC, 0);
}

pub fn tcpListen(addr: net.Address, reuse_address: bool) !net.Server {
    const sock = try tcpSocket(addr.any.family);
    errdefer sys.closeSocket(sock);
    if (reuse_address) try sys.setsockopt(sock, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
    var len = addr.getOsSockLen();
    try sys.bind(sock, &addr.any, len);
    try sys.listen(sock, 128);
    var bound: net.Address = undefined;
    try sys.getsockname(sock, &bound.any, &len);
    return .{ .listen_address = bound, .stream = .{ .handle = sock } };
}

pub fn tcpConnect(addr: net.Address) !net.Stream {
    const sock = try tcpSocket(addr.any.family);
    errdefer sys.closeSocket(sock);
    try sys.connect(sock, &addr.any, addr.getOsSockLen());
    return .{ .handle = sock };
}

// a connected pair of stream sockets: unix domain elsewhere, a loopback tcp
// connection on windows, where WSAPoll only waits on sockets so this is
// also the wakeup primitive serve uses instead of a pipe
pub fn socketPair() ![2]std.posix.socket_t {
    if (!is_windows) return sys.socketPair();
    var server = try tcpListen(net.Address.initIp4(.{ 127, 0, 0, 1 }, 0), false);
    defer server.deinit();
    const client = try tcpConnect(server.listen_address);
    errdefer client.close();
    const accepted = try server.accept();
    return .{ client.handle, accepted.stream.handle };
}

// the outcome of a non-blocking connect once the socket polls writable
pub fn connectResult(sock: std.posix.socket_t) !void {
    return sys.getsockoptError(sock);
}

pub fn setNonBlocking(sock: std.posix.socket_t, enabled: bool) !void {
    if (is_windows) {
        var mode: u32 = if (enabled) 1 else 0;
        if (sys.ws2.ioctlsocket(sock, sys.ws2.FIONBIO, &mode) != 0) return error.SetNonBlockingFailed;
        return;
    }
    const nonblock: usize = @as(usize, 1) << @bitOffsetOf(std.posix.O, "NONBLOCK");
    const flags = try sys.fcntl(sock, std.posix.F.GETFL, 0);
    const next = if (enabled) flags | nonblock else flags & ~nonblock;
    _ = try sys.fcntl(sock, std.posix.F.SETFL, next);
}

// whether a descriptor is in blocking mode; windows cannot be asked, so the
// caller's knowledge (inherit) answers there
pub fn isBlocking(sock: std.posix.socket_t, inherit: bool) bool {
    if (is_windows) return inherit;
    const nonblock: usize = @as(usize, 1) << @bitOffsetOf(std.posix.O, "NONBLOCK");
    const flags = sys.fcntl(sock, std.posix.F.GETFL, 0) catch return inherit;
    return flags & nonblock == 0;
}

pub fn recv(sock: std.posix.socket_t, buf: []u8) !usize {
    return sys.recv(sock, buf, 0);
}

pub fn send(sock: std.posix.socket_t, buf: []const u8) !usize {
    return sys.send(sock, buf, 0);
}

// SIGINT/SIGTERM elsewhere, the console control handler on windows; the
// callback runs on a signal or console thread and may only touch a socket
var shutdown_callback: ?*const fn () void = null;

fn posixShutdownSignal(_: std.posix.SIG) callconv(.c) void {
    if (shutdown_callback) |cb| cb();
}

fn windowsShutdownSignal(_: u32) callconv(.winapi) win32.BOOL {
    if (shutdown_callback) |cb| cb();
    return win32.TRUE;
}

pub fn installShutdownHandler(cb: *const fn () void) !void {
    shutdown_callback = cb;
    if (is_windows) {
        if (win32.SetConsoleCtrlHandler(windowsShutdownSignal, win32.TRUE) == win32.FALSE) return error.Unexpected;
        return;
    }
    const action: std.posix.Sigaction = .{ .handler = .{ .handler = posixShutdownSignal }, .mask = std.posix.sigemptyset(), .flags = 0 };
    std.posix.sigaction(std.posix.SIG.INT, &action, null);
    std.posix.sigaction(std.posix.SIG.TERM, &action, null);
}

comptime {
    _ = &tcpListen;
    _ = &tcpConnect;
    _ = &socketPair;
    _ = &setNonBlocking;
    _ = &recv;
    _ = &send;
    _ = &installShutdownHandler;
}
