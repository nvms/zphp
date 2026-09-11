// the seam between zphp and the operating system. posix targets pass
// straight through; windows gets the equivalent in terms of the win32 crt
// that mingw exposes, so the rest of the runtime keeps its file-descriptor-
// as-int and byte-string-environment conventions on every platform
const std = @import("std");
const platform = @import("platform.zig");
const builtin = @import("builtin");

pub const is_windows = builtin.os.tag == .windows;
pub const is_macos = builtin.os.tag == .macos;

// environment strings on windows are wtf-16; a lookup converts once and the
// result lives for the process, which is all the debug-flag and config
// callers need
var env_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var env_mutex: std.Thread.Mutex = .{};

pub fn getenv(name: []const u8) ?[]const u8 {
    if (!is_windows) return std.posix.getenv(name);
    env_mutex.lock();
    defer env_mutex.unlock();
    return std.process.getEnvVarOwned(env_arena.allocator(), name) catch null;
}

pub fn stdout() std.fs.File {
    return std.fs.File.stdout();
}

pub fn stderr() std.fs.File {
    return std.fs.File.stderr();
}

pub fn writeStdout(bytes: []const u8) void {
    stdout().writeAll(bytes) catch {};
}

pub fn writeStderr(bytes: []const u8) void {
    stderr().writeAll(bytes) catch {};
}

// php scripts hold open files as small integers. on posix that is the fd
// itself; on windows the crt keeps the same table behind _open_osfhandle
extern "c" fn _open_osfhandle(handle: isize, flags: c_int) c_int;
extern "c" fn _get_osfhandle(fd: c_int) isize;

pub fn fdFromFile(file: std.fs.File) i64 {
    if (!is_windows) return @intCast(file.handle);
    return @intCast(_open_osfhandle(@intCast(@intFromPtr(file.handle)), 0));
}

pub fn fileFromFd(fd: i64) ?std.fs.File {
    if (fd < 0) return null;
    if (!is_windows) return .{ .handle = @intCast(fd) };
    const raw = _get_osfhandle(@intCast(fd));
    if (raw == -1 or raw == -2) return null;
    return .{ .handle = @ptrFromInt(@as(usize, @intCast(raw))) };
}

pub fn stdinFd() i64 {
    return if (is_windows) 0 else std.posix.STDIN_FILENO;
}

// the directory php's sys_get_temp_dir and tmpfile use
pub fn tempDir() []const u8 {
    if (is_windows) return getenv("TEMP") orelse getenv("TMP") orelse "C:\\Windows\\Temp";
    return getenv("TMPDIR") orelse "/tmp";
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
        std.posix.close(@intCast(fd));
    }
}

pub fn isatty(fd: i64) bool {
    if (fd < 0) return false;
    if (is_windows) return _isatty(@intCast(fd)) != 0;
    return std.posix.isatty(@intCast(fd));
}

pub fn isStdout(file: std.fs.File) bool {
    return if (is_windows) file.handle == stdout().handle else file.handle == 1;
}

pub fn isStderr(file: std.fs.File) bool {
    return if (is_windows) file.handle == stderr().handle else file.handle == 2;
}

pub fn isStdio(file: std.fs.File) bool {
    if (is_windows) return file.handle == stdout().handle or file.handle == stderr().handle or file.handle == std.fs.File.stdin().handle;
    return file.handle <= 2;
}

pub fn getpid() i64 {
    if (is_windows) return @intCast(std.os.windows.GetCurrentProcessId());
    return @intCast(std.posix.system.getpid());
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
    const sock = socketFromInt(v) orelse return;
    if (is_windows) {
        _ = std.os.windows.ws2_32.closesocket(sock);
    } else {
        std.posix.close(sock);
    }
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
pub fn openAppend(path: []const u8, read_too: bool) !std.fs.File {
    if (is_windows) {
        const o_rdwr: c_int = 2;
        const o_wronly: c_int = 1;
        const o_append: c_int = 0x8;
        const o_creat: c_int = 0x100;
        const o_binary: c_int = 0x8000;
        var buf: [std.fs.max_path_bytes]u8 = undefined;
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
    const fd = try std.posix.open(path, flags, 0o666);
    return .{ .handle = fd };
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
pub fn closeFile(file: std.fs.File, fd: i64) void {
    if (is_windows) {
        closeFd(fd);
    } else {
        file.close();
    }
}

// windows reports no unix mode; php there synthesizes 0666 for files and
// 0777 for directories, with the type bits on top
pub fn modeOf(st: std.fs.File.Stat) u32 {
    if (!is_windows or st.mode != 0) return @intCast(st.mode);
    return switch (st.kind) {
        .directory => 0o40777,
        .sym_link => 0o120777,
        else => 0o100666,
    };
}

pub fn isSep(c: u8) bool {
    return c == '/' or (is_windows and c == '\\');
}

pub const sep_str: []const u8 = if (is_windows) "\\" else "/";

// stat of a path that may be a directory: on windows statFile opens the path
// as a file, which a directory refuses
pub fn statPath(path: []const u8) !std.fs.File.Stat {
    return std.fs.cwd().statFile(path) catch |err| {
        if (!is_windows) return err;
        var dir = std.fs.cwd().openDir(path, .{}) catch return err;
        defer dir.close();
        return dir.stat();
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

extern "kernel32" fn K32GetProcessMemoryInfo(process: *anyopaque, counters: *ProcessMemoryCounters, cb: u32) callconv(.winapi) c_int;
extern "kernel32" fn GetCurrentProcess() callconv(.winapi) *anyopaque;
extern "kernel32" fn SetFileAttributesW(path: [*:0]const u16, attributes: u32) callconv(.winapi) c_int;

// the process's peak resident size, what memory_get_peak_usage reports
pub fn peakRss() i64 {
    if (is_windows) {
        var counters: ProcessMemoryCounters = undefined;
        counters.cb = @sizeOf(ProcessMemoryCounters);
        if (K32GetProcessMemoryInfo(GetCurrentProcess(), &counters, counters.cb) == 0) return 0;
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
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const wide = std.unicode.wtf8ToWtf16LeAllocZ(fba.allocator(), path) catch return false;
    const attrs = std.os.windows.GetFileAttributesW(wide.ptr) catch return false;
    return (attrs & std.os.windows.FILE_ATTRIBUTE_READONLY) != 0;
}

// FILE_ATTRIBUTE_READONLY on or off, keeping the other attributes
pub fn setReadOnly(path: []const u8, read_only: bool) bool {
    if (!is_windows) return false;
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const wide = std.unicode.wtf8ToWtf16LeAllocZ(fba.allocator(), path) catch return false;
    const attrs = std.os.windows.GetFileAttributesW(wide.ptr) catch return false;
    const readonly_bit: u32 = std.os.windows.FILE_ATTRIBUTE_READONLY;
    const next = if (read_only) attrs | readonly_bit else attrs & ~readonly_bit;
    return SetFileAttributesW(wide.ptr, next) != 0;
}
