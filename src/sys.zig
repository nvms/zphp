// the system calls php's semantics need directly: descriptors, sockets,
// processes and signals. posix targets call libc, which zphp always links;
// windows sockets go through winsock. std.Io covers files and directories,
// but php exposes raw descriptors that scripts poll, fork around and pass to
// child processes, so these stay plain calls on plain handles
const std = @import("std");
const sync = @import("sync.zig");
const builtin = @import("builtin");
const posix = std.posix;
const c = std.c;
const win32 = @import("win32.zig");

const is_windows = builtin.os.tag == .windows;
const E = posix.E;

fn unexpected(err: E) error{Unexpected} {
    if (builtin.mode == .debug) std.debug.print("unexpected errno: {t}\n", .{err});
    return error.Unexpected;
}

fn errnoOf(rc: anytype) E {
    return c.errno(rc);
}

extern "c" fn strerror(errnum: c_int) ?[*:0]const u8;

// strerror(errno) after a failed libc call: the text php's filesystem
// warnings carry
pub fn errnoText() []const u8 {
    if (is_windows) {
        return "Unknown error";
    } else {
        const s = strerror(c._errno().*) orelse return "Unknown error";
        return std.mem.span(s);
    }
}

pub fn close(fd: posix.fd_t) void {
    _ = c.close(fd);
}

pub fn closeSocket(sock: posix.socket_t) void {
    if (is_windows) {
        _ = ws2.closesocket(sock);
    } else {
        _ = c.close(sock);
    }
}

pub fn isatty(fd: posix.fd_t) bool {
    return c.isatty(fd) != 0;
}

pub fn getenv(name: []const u8) ?[:0]const u8 {
    var buf: [256]u8 = undefined;
    if (name.len >= buf.len) return null;
    @memcpy(buf[0..name.len], name);
    buf[name.len] = 0;
    const value = c.getenv(@ptrCast(&buf)) orelse return null;
    return std.mem.span(value);
}

pub const OpenError = error{
    AccessDenied,
    FileNotFound,
    IsDir,
    NotDir,
    NameTooLong,
    PathAlreadyExists,
    NoSpaceLeft,
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
    SymLinkLoop,
    FileBusy,
    WouldBlock,
    Unexpected,
};

pub fn open(path: []const u8, flags: posix.O, mode: posix.mode_t) OpenError!posix.fd_t {
    const path_z = posix.toPosixPath(path) catch return error.NameTooLong;
    while (true) {
        const rc = c.open(&path_z, flags, mode);
        switch (errnoOf(rc)) {
            .SUCCESS => return rc,
            .INTR => continue,
            .ACCES, .PERM, .ROFS => return error.AccessDenied,
            .NOENT => return error.FileNotFound,
            .ISDIR => return error.IsDir,
            .NOTDIR => return error.NotDir,
            .NAMETOOLONG => return error.NameTooLong,
            .EXIST => return error.PathAlreadyExists,
            .NOSPC => return error.NoSpaceLeft,
            .MFILE => return error.ProcessFdQuotaExceeded,
            .NFILE => return error.SystemFdQuotaExceeded,
            .LOOP => return error.SymLinkLoop,
            .BUSY, .TXTBSY => return error.FileBusy,
            .AGAIN => return error.WouldBlock,
            else => |err| return unexpected(err),
        }
    }
}

pub const WriteError = error{ WouldBlock, BrokenPipe, NoSpaceLeft, InputOutput, AccessDenied, Unexpected };

pub fn write(fd: posix.fd_t, bytes: []const u8) WriteError!usize {
    while (true) {
        const rc = c.write(fd, bytes.ptr, bytes.len);
        switch (errnoOf(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => continue,
            .AGAIN => return error.WouldBlock,
            .PIPE => return error.BrokenPipe,
            .NOSPC, .DQUOT => return error.NoSpaceLeft,
            .IO => return error.InputOutput,
            .PERM, .ACCES => return error.AccessDenied,
            else => |err| return unexpected(err),
        }
    }
}

pub const SeekError = error{ Unseekable, Unexpected };

pub const Whence = enum(c_int) { set = 0, cur = 1, end = 2 };

// the descriptor's own position, shared with every process holding it, which
// is the position php's fseek and ftell work with
pub fn lseek(fd: posix.fd_t, offset: i64, whence: Whence) SeekError!u64 {
    if (is_windows) {
        var new_pos: i64 = 0;
        if (win32.SetFilePointerEx(fd, offset, &new_pos, @intCast(@backingInt(whence))) == 0) return error.Unseekable;
        return @intCast(new_pos);
    }
    const rc = c.lseek(fd, offset, @backingInt(whence));
    switch (errnoOf(rc)) {
        .SUCCESS => return @intCast(rc),
        .SPIPE, .INVAL, .OVERFLOW => return error.Unseekable,
        else => |err| return unexpected(err),
    }
}

pub const MkdirError = error{ AccessDenied, PermissionDenied, ReadOnlyFileSystem, PathAlreadyExists, FileNotFound, NotDir, NameTooLong, NoSpaceLeft, SymLinkLoop, Unexpected };

pub fn mkdir(path: []const u8, mode: posix.mode_t) MkdirError!void {
    const path_z = posix.toPosixPath(path) catch return error.NameTooLong;
    switch (errnoOf(c.mkdir(&path_z, mode))) {
        .SUCCESS => {},
        .ACCES => return error.AccessDenied,
        .PERM => return error.PermissionDenied,
        .ROFS => return error.ReadOnlyFileSystem,
        .EXIST => return error.PathAlreadyExists,
        .NOENT => return error.FileNotFound,
        .NOTDIR => return error.NotDir,
        .NAMETOOLONG => return error.NameTooLong,
        .NOSPC, .DQUOT => return error.NoSpaceLeft,
        .LOOP => return error.SymLinkLoop,
        else => |err| return unexpected(err),
    }
}

pub fn access(path: []const u8, mode: u32) error{ AccessDenied, FileNotFound, NameTooLong, Unexpected }!void {
    const path_z = posix.toPosixPath(path) catch return error.NameTooLong;
    switch (errnoOf(c.access(&path_z, mode))) {
        .SUCCESS => {},
        .NOENT, .NOTDIR => return error.FileNotFound,
        .NAMETOOLONG => return error.NameTooLong,
        else => return error.AccessDenied,
    }
}

pub fn flock(fd: posix.fd_t, operation: i32) error{ WouldBlock, Unexpected }!void {
    while (true) switch (errnoOf(c.flock(fd, operation))) {
        .SUCCESS => return,
        .INTR => continue,
        .AGAIN => return error.WouldBlock,
        else => |err| return unexpected(err),
    };
}

pub fn fcntl(fd: posix.fd_t, cmd: i32, arg: usize) error{ BadDescriptor, Unexpected }!usize {
    while (true) {
        const rc = c.fcntl(fd, cmd, arg);
        switch (errnoOf(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => continue,
            .BADF => return error.BadDescriptor,
            else => |err| return unexpected(err),
        }
    }
}

pub const FileKind = enum { file, directory, sym_link, other };

// the kind of the entry at a path without following a final symlink
pub fn lstatKind(path: []const u8) StatError!FileKind {
    const st = try lstat(path);
    return switch (st.mode & posix.S.IFMT) {
        posix.S.IFREG => .file,
        posix.S.IFDIR => .directory,
        posix.S.IFLNK => .sym_link,
        else => .other,
    };
}

// the fields of a stat(2) result php reports
pub const Stat = struct {
    dev: u64,
    ino: u64,
    mode: u32,
    rdev: u64,
    nlink: u64,
    uid: u32,
    gid: u32,
    size: i64,
    blksize: i64,
    blocks: i64,
    atime: i64,
    mtime: i64,
    ctime: i64,
};

pub const StatError = error{ AccessDenied, FileNotFound, NameTooLong, Unexpected };

pub fn stat(path: []const u8) StatError!Stat {
    return statAt(path, false);
}

pub fn lstat(path: []const u8) StatError!Stat {
    return statAt(path, true);
}

const c_lstat = @extern(*const fn (noalias [*:0]const u8, noalias *c.Stat) callconv(.c) c_int, .{ .name = "lstat" });

// the stat of an open descriptor, what fstat() reports
pub fn fstat(fd: posix.fd_t) StatError!Stat {
    if (builtin.os.tag == .linux) return statx(fd, "", posix.AT.EMPTY_PATH);
    var st: c.Stat = undefined;
    switch (errnoOf(c.fstat(fd, &st))) {
        .SUCCESS => {},
        else => |err| return statError(err),
    }
    return fromCStat(&st);
}

fn statAt(path: []const u8, no_follow: bool) StatError!Stat {
    const path_z = posix.toPosixPath(path) catch return error.NameTooLong;
    if (builtin.os.tag == .linux) return statx(posix.AT.FDCWD, &path_z, if (no_follow) posix.AT.SYMLINK_NOFOLLOW else 0);
    var st: c.Stat = undefined;
    const rc = if (no_follow) c_lstat(&path_z, &st) else c.stat(&path_z, &st);
    switch (errnoOf(rc)) {
        .SUCCESS => {},
        else => |err| return statError(err),
    }
    return fromCStat(&st);
}

fn statx(dirfd: posix.fd_t, path_z: [*:0]const u8, flags: u32) StatError!Stat {
    const linux = std.os.linux;
    var sx: linux.Statx = undefined;
    const mask: linux.STATX = .{ .TYPE = true, .MODE = true, .NLINK = true, .UID = true, .GID = true, .ATIME = true, .MTIME = true, .CTIME = true, .INO = true, .SIZE = true, .BLOCKS = true };
    switch (errnoOf(c.statx(dirfd, path_z, flags, mask, &sx))) {
        .SUCCESS => {},
        else => |err| return statError(err),
    }
    return .{
        .dev = makedev(sx.dev_major, sx.dev_minor),
        .rdev = makedev(sx.rdev_major, sx.rdev_minor),
        .ino = sx.ino,
        .mode = sx.mode,
        .nlink = sx.nlink,
        .uid = sx.uid,
        .gid = sx.gid,
        .size = @intCast(sx.size),
        .blksize = sx.blksize,
        .blocks = @intCast(sx.blocks),
        .atime = sx.atime.sec,
        .mtime = sx.mtime.sec,
        .ctime = sx.ctime.sec,
    };
}

fn fromCStat(st: *const c.Stat) Stat {
    return .{
        .dev = @intCast(st.dev),
        .rdev = @intCast(st.rdev),
        .ino = @intCast(st.ino),
        .mode = @intCast(st.mode),
        .nlink = @intCast(st.nlink),
        .uid = @intCast(st.uid),
        .gid = @intCast(st.gid),
        .size = @intCast(st.size),
        .blksize = @intCast(st.blksize),
        .blocks = @intCast(st.blocks),
        .atime = @intCast(st.atime().sec),
        .mtime = @intCast(st.mtime().sec),
        .ctime = @intCast(st.ctime().sec),
    };
}

// glibc's encoding of a device number, what struct stat's st_dev holds
fn makedev(major: u32, minor: u32) u64 {
    const ma: u64 = major;
    const mi: u64 = minor;
    return ((ma & 0xfffff000) << 32) | ((ma & 0xfff) << 8) | ((mi & 0xffffff00) << 12) | (mi & 0xff);
}

fn statError(err: E) StatError {
    return switch (err) {
        .ACCES, .PERM => error.AccessDenied,
        .NOENT, .NOTDIR => error.FileNotFound,
        .NAMETOOLONG => error.NameTooLong,
        else => unexpected(err),
    };
}

// processes

pub fn fork() error{ SystemResources, Unexpected }!posix.pid_t {
    const rc = c.fork();
    switch (errnoOf(rc)) {
        .SUCCESS => return @intCast(rc),
        .AGAIN, .NOMEM => return error.SystemResources,
        else => |err| return unexpected(err),
    }
}

pub const ExecError = error{ AccessDenied, FileNotFound, NotDir, NameTooLong, InvalidExe, SystemResources, Unexpected };

fn execError(err: E) ExecError {
    return switch (err) {
        .ACCES, .PERM => error.AccessDenied,
        .NOENT => error.FileNotFound,
        .NOTDIR => error.NotDir,
        .NAMETOOLONG => error.NameTooLong,
        .NOEXEC, .ISDIR => error.InvalidExe,
        .NOMEM, .@"2BIG" => error.SystemResources,
        else => blk: {
            if (builtin.os.tag == .linux) {
                if (err == .LIBBAD) break :blk error.InvalidExe;
            }
            break :blk unexpected(err);
        },
    };
}

pub fn execve(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) ExecError {
    _ = c.execve(path, argv, envp);
    return execError(c.errno(@as(c_int, -1)));
}

// execve searching PATH for a bare name, as the shell would. macOS libc has
// no execvpe, so the search is done here on every platform
pub fn execvpe(file: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) ExecError {
    const name = std.mem.span(file);
    if (std.mem.indexOfScalar(u8, name, '/') != null) return execve(file, argv, envp);
    const search = getenv("PATH") orelse "/usr/local/bin:/bin:/usr/bin";
    var first_err: ?ExecError = null;
    var it = std.mem.tokenizeScalar(u8, search, ':');
    var buf: [posix.PATH_MAX]u8 = undefined;
    while (it.next()) |dir| {
        if (dir.len + 1 + name.len + 1 > buf.len) continue;
        @memcpy(buf[0..dir.len], dir);
        buf[dir.len] = '/';
        @memcpy(buf[dir.len + 1 ..][0..name.len], name);
        buf[dir.len + 1 + name.len] = 0;
        const err = execve(@ptrCast(&buf), argv, envp);
        switch (err) {
            error.FileNotFound, error.NotDir => {},
            else => if (first_err == null) {
                first_err = err;
            },
        }
    }
    return first_err orelse error.FileNotFound;
}

pub fn dup2(old: posix.fd_t, new: posix.fd_t) error{ BadDescriptor, Unexpected }!void {
    while (true) switch (errnoOf(c.dup2(old, new))) {
        .SUCCESS => return,
        .INTR, .BUSY => continue,
        .BADF => return error.BadDescriptor,
        else => |err| return unexpected(err),
    };
}

pub fn chdir(path: [*:0]const u8) error{ AccessDenied, FileNotFound, NotDir, Unexpected }!void {
    switch (errnoOf(c.chdir(path))) {
        .SUCCESS => {},
        .ACCES, .PERM => return error.AccessDenied,
        .NOENT => return error.FileNotFound,
        .NOTDIR => return error.NotDir,
        else => |err| return unexpected(err),
    }
}

pub const WaitResult = struct { pid: posix.pid_t, status: u32 };

pub fn waitpid(pid: posix.pid_t, flags: u32) WaitResult {
    var status: c_int = 0;
    while (true) {
        const rc = c.waitpid(pid, &status, @intCast(flags));
        switch (errnoOf(rc)) {
            .SUCCESS => return .{ .pid = @intCast(rc), .status = @bitCast(status) },
            .INTR => continue,
            // no such child: reported as nothing reaped
            else => return .{ .pid = 0, .status = 0 },
        }
    }
}

pub fn pipe() error{ ProcessFdQuotaExceeded, SystemFdQuotaExceeded, Unexpected }![2]posix.fd_t {
    var fds: [2]posix.fd_t = undefined;
    switch (errnoOf(c.pipe(&fds))) {
        .SUCCESS => return fds,
        .MFILE => return error.ProcessFdQuotaExceeded,
        .NFILE => return error.SystemFdQuotaExceeded,
        else => |err| return unexpected(err),
    }
}

// a pipe whose ends close on exec, so children see only what they're given
pub fn pipeCloexec() error{ ProcessFdQuotaExceeded, SystemFdQuotaExceeded, Unexpected }![2]posix.fd_t {
    if (builtin.os.tag == .linux or builtin.os.tag.isBSD() and !builtin.os.tag.isDarwin()) {
        var fds: [2]posix.fd_t = undefined;
        switch (errnoOf(c.pipe2(&fds, .{ .CLOEXEC = true }))) {
            .SUCCESS => return fds,
            .MFILE => return error.ProcessFdQuotaExceeded,
            .NFILE => return error.SystemFdQuotaExceeded,
            else => |err| return unexpected(err),
        }
    }
    const fds = try pipe();
    for (fds) |fd| _ = c.fcntl(fd, posix.F.SETFD, @as(c_int, posix.FD_CLOEXEC));
    return fds;
}

pub fn mprotect(memory: []align(std.heap.page_size_min) u8, protection: posix.PROT) error{ AccessDenied, OutOfMemory, Unexpected }!void {
    switch (errnoOf(c.mprotect(memory.ptr, memory.len, protection))) {
        .SUCCESS => {},
        .ACCES => return error.AccessDenied,
        .NOMEM => return error.OutOfMemory,
        else => |err| return unexpected(err),
    }
}

// sockets

pub const SocketError = error{
    AccessDenied,
    AddressFamilyNotSupported,
    ProtocolNotSupported,
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
    SystemResources,
    SocketCreationFailed,
    Unexpected,
};

pub fn socket(domain: u32, socket_type: u32, protocol: u32) SocketError!posix.socket_t {
    if (is_windows) {
        const s = ws2.WSASocketW(@intCast(domain), @intCast(socket_type), @intCast(protocol), null, 0, ws2.WSA_FLAG_NO_HANDLE_INHERIT);
        if (s == ws2.INVALID_SOCKET) return error.SocketCreationFailed;
        return s;
    }
    const rc = c.socket(domain, socket_type, protocol);
    switch (errnoOf(rc)) {
        .SUCCESS => return rc,
        .ACCES, .PERM => return error.AccessDenied,
        .AFNOSUPPORT => return error.AddressFamilyNotSupported,
        .PROTONOSUPPORT, .PROTOTYPE, .INVAL => return error.ProtocolNotSupported,
        .MFILE => return error.ProcessFdQuotaExceeded,
        .NFILE => return error.SystemFdQuotaExceeded,
        .NOBUFS, .NOMEM => return error.SystemResources,
        else => |err| return unexpected(err),
    }
}

pub const SocketOpError = error{
    AccessDenied,
    AddressInUse,
    AddressNotAvailable,
    AlreadyConnected,
    ConnectionRefused,
    ConnectionResetByPeer,
    ConnectionTimedOut,
    ConnectionPending,
    ConnectionAborted,
    NetworkUnreachable,
    SocketNotConnected,
    BrokenPipe,
    WouldBlock,
    FileNotFound,
    InvalidProtocolOption,
    OperationUnsupported,
    MessageTooBig,
    SystemResources,
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
    Unexpected,
};

fn socketError(err: E) SocketOpError {
    return switch (err) {
        .ACCES, .PERM => error.AccessDenied,
        .ADDRINUSE => error.AddressInUse,
        .ADDRNOTAVAIL => error.AddressNotAvailable,
        .ISCONN => error.AlreadyConnected,
        .CONNREFUSED => error.ConnectionRefused,
        .CONNRESET => error.ConnectionResetByPeer,
        .TIMEDOUT => error.ConnectionTimedOut,
        .INPROGRESS, .ALREADY => error.ConnectionPending,
        .CONNABORTED => error.ConnectionAborted,
        .NETUNREACH, .HOSTUNREACH => error.NetworkUnreachable,
        .NOTCONN => error.SocketNotConnected,
        .PIPE => error.BrokenPipe,
        .AGAIN => error.WouldBlock,
        .NOENT => error.FileNotFound,
        .NOPROTOOPT => error.InvalidProtocolOption,
        .OPNOTSUPP => error.OperationUnsupported,
        .MSGSIZE => error.MessageTooBig,
        .NOBUFS, .NOMEM => error.SystemResources,
        .MFILE => error.ProcessFdQuotaExceeded,
        .NFILE => error.SystemFdQuotaExceeded,
        else => unexpected(err),
    };
}

fn winsockError() SocketOpError {
    const code = ws2.WSAGetLastError();
    return switch (code) {
        ws2.WSAEACCES => error.AccessDenied,
        ws2.WSAEADDRINUSE => error.AddressInUse,
        ws2.WSAEADDRNOTAVAIL => error.AddressNotAvailable,
        ws2.WSAEISCONN => error.AlreadyConnected,
        ws2.WSAECONNREFUSED => error.ConnectionRefused,
        ws2.WSAECONNRESET => error.ConnectionResetByPeer,
        ws2.WSAETIMEDOUT => error.ConnectionTimedOut,
        ws2.WSAEINPROGRESS, ws2.WSAEALREADY => error.ConnectionPending,
        ws2.WSAEWOULDBLOCK => error.WouldBlock,
        ws2.WSAECONNABORTED => error.ConnectionAborted,
        ws2.WSAENETUNREACH, ws2.WSAEHOSTUNREACH => error.NetworkUnreachable,
        ws2.WSAENOTCONN => error.SocketNotConnected,
        ws2.WSAEMSGSIZE => error.MessageTooBig,
        ws2.WSAENOBUFS => error.SystemResources,
        ws2.WSAEMFILE => error.ProcessFdQuotaExceeded,
        else => error.Unexpected,
    };
}

pub fn bind(sock: posix.socket_t, addr: *const posix.sockaddr, len: posix.socklen_t) SocketOpError!void {
    if (is_windows) {
        if (ws2.bind(sock, addr, @intCast(len)) != 0) return winsockError();
        return;
    }
    switch (errnoOf(c.bind(sock, addr, len))) {
        .SUCCESS => {},
        else => |err| return socketError(err),
    }
}

pub fn listen(sock: posix.socket_t, backlog: u31) SocketOpError!void {
    if (is_windows) {
        if (ws2.listen(sock, backlog) != 0) return winsockError();
        return;
    }
    switch (errnoOf(c.listen(sock, backlog))) {
        .SUCCESS => {},
        else => |err| return socketError(err),
    }
}

pub fn getsockname(sock: posix.socket_t, addr: *posix.sockaddr, len: *posix.socklen_t) SocketOpError!void {
    if (is_windows) {
        var wlen: i32 = @intCast(len.*);
        if (ws2.getsockname(sock, addr, &wlen) != 0) return winsockError();
        len.* = @intCast(wlen);
        return;
    }
    switch (errnoOf(c.getsockname(sock, addr, len))) {
        .SUCCESS => {},
        else => |err| return socketError(err),
    }
}

pub fn connect(sock: posix.socket_t, addr: *const posix.sockaddr, len: posix.socklen_t) SocketOpError!void {
    if (is_windows) {
        if (ws2.connect(sock, addr, @intCast(len)) != 0) return winsockError();
        return;
    }
    while (true) switch (errnoOf(c.connect(sock, addr, len))) {
        .SUCCESS => return,
        .INTR => continue,
        else => |err| return socketError(err),
    };
}

const has_accept4 = switch (builtin.os.tag) {
    .linux, .freebsd, .netbsd, .openbsd, .dragonfly => true,
    else => false,
};

pub fn accept(sock: posix.socket_t, addr: ?*posix.sockaddr, len: ?*posix.socklen_t, flags: u32) SocketOpError!posix.socket_t {
    if (is_windows) {
        var wlen: i32 = if (len) |l| @intCast(l.*) else 0;
        const s = ws2.accept(sock, addr, if (len != null) &wlen else null);
        if (s == ws2.INVALID_SOCKET) return winsockError();
        if (len) |l| l.* = @intCast(wlen);
        return s;
    }
    while (true) {
        const rc = if (has_accept4) c.accept4(sock, addr, len, flags) else c.accept(sock, addr, len);
        switch (errnoOf(rc)) {
            .SUCCESS => {
                if (!(has_accept4) and flags & posix.SOCK.CLOEXEC != 0) {
                    _ = c.fcntl(rc, posix.F.SETFD, @as(usize, posix.FD_CLOEXEC));
                }
                return rc;
            },
            .INTR, .CONNABORTED => continue,
            else => |err| return socketError(err),
        }
    }
}

pub fn setsockopt(sock: posix.socket_t, level: i32, name: u32, value: []const u8) SocketOpError!void {
    if (is_windows) {
        if (ws2.setsockopt(sock, level, @intCast(name), value.ptr, @intCast(value.len)) != 0) return winsockError();
        return;
    }
    switch (errnoOf(c.setsockopt(sock, level, name, value.ptr, @intCast(value.len)))) {
        .SUCCESS => {},
        else => |err| return socketError(err),
    }
}

// the pending error of a socket, how a non-blocking connect reports its outcome
pub fn getsockoptError(sock: posix.socket_t) SocketOpError!void {
    var code: i32 = 0;
    if (is_windows) {
        var len: i32 = @sizeOf(i32);
        if (ws2.getsockopt(sock, posix.SOL.SOCKET, posix.SO.ERROR, @ptrCast(&code), &len) != 0) return error.Unexpected;
        if (code == 0) return;
        ws2.WSASetLastError(code);
        return winsockError();
    }
    var len: posix.socklen_t = @sizeOf(i32);
    switch (errnoOf(c.getsockopt(sock, posix.SOL.SOCKET, posix.SO.ERROR, @ptrCast(&code), &len))) {
        .SUCCESS => {},
        else => |err| return socketError(err),
    }
    if (code != 0) return socketError(@fromBackingInt(@intCast(code)));
}

pub fn send(sock: posix.socket_t, bytes: []const u8, flags: u32) SocketOpError!usize {
    if (is_windows) {
        const rc = ws2.send(sock, bytes.ptr, @intCast(@min(bytes.len, std.math.maxInt(i32))), flags);
        if (rc < 0) return winsockError();
        return @intCast(rc);
    }
    // a peer that hung up fails the write instead of raising SIGPIPE
    const nosignal: u32 = if (builtin.os.tag == .linux) posix.MSG.NOSIGNAL else 0;
    while (true) {
        const rc = c.send(sock, bytes.ptr, bytes.len, flags | nosignal);
        switch (errnoOf(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => continue,
            // a descriptor that isn't a socket: a pipe or file used as a stream
            .NOTSOCK => return write(sock, bytes) catch |err| switch (err) {
                error.WouldBlock => error.WouldBlock,
                error.BrokenPipe => error.BrokenPipe,
                else => error.Unexpected,
            },
            else => |err| return socketError(err),
        }
    }
}

pub fn recv(sock: posix.socket_t, buf: []u8, flags: u32) SocketOpError!usize {
    if (is_windows) {
        const rc = ws2.recv(sock, buf.ptr, @intCast(@min(buf.len, std.math.maxInt(i32))), @intCast(flags));
        if (rc < 0) return winsockError();
        return @intCast(rc);
    }
    while (true) {
        const rc = c.recv(sock, buf.ptr, buf.len, @intCast(flags));
        switch (errnoOf(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => continue,
            .NOTSOCK => return posix.read(sock, buf) catch |err| switch (err) {
                error.WouldBlock => error.WouldBlock,
                else => error.Unexpected,
            },
            else => |err| return socketError(err),
        }
    }
}

pub const ShutdownHow = enum { recv, send, both };

pub fn shutdown(sock: posix.socket_t, how: ShutdownHow) SocketOpError!void {
    const code: i32 = switch (how) {
        .recv => 0,
        .send => 1,
        .both => 2,
    };
    if (is_windows) {
        if (ws2.shutdown(sock, code) != 0) return winsockError();
        return;
    }
    switch (errnoOf(c.shutdown(sock, code))) {
        .SUCCESS => {},
        else => |err| return socketError(err),
    }
}

// winsock's poll structure and flags; std keeps them for posix only
pub const pollfd = if (is_windows) extern struct { fd: posix.socket_t, events: i16, revents: i16 } else posix.pollfd;
pub const POLL = if (is_windows) struct {
    pub const RDNORM: i16 = 256;
    pub const RDBAND: i16 = 512;
    pub const PRI: i16 = 1024;
    pub const WRNORM: i16 = 16;
    pub const ERR: i16 = 1;
    pub const HUP: i16 = 2;
    pub const NVAL: i16 = 4;
    pub const IN: i16 = RDNORM | RDBAND;
    pub const OUT: i16 = WRNORM;
} else posix.POLL;

pub fn poll(fds: []pollfd, timeout_ms: i32) error{ SystemResources, Unexpected }!usize {
    if (is_windows) {
        const rc = ws2.WSAPoll(fds.ptr, @intCast(fds.len), timeout_ms);
        if (rc < 0) return error.Unexpected;
        return @intCast(rc);
    }
    return posix.poll(fds, timeout_ms) catch |err| switch (err) {
        error.SystemResources => error.SystemResources,
        else => error.Unexpected,
    };
}

pub fn socketPair() error{SocketPairFailed}![2]posix.socket_t {
    var pair: [2]posix.socket_t = undefined;
    if (c.socketpair(posix.AF.UNIX, posix.SOCK.STREAM, 0, &pair) != 0) return error.SocketPairFailed;
    return pair;
}

var winsock_once = sync.once(winsockInit);
var winsock_ok = false;

fn winsockInit() void {
    var data: ws2.WSADATA = undefined;
    winsock_ok = ws2.WSAStartup(0x0202, &data) == 0;
}

// winsock needs WSAStartup before any other call; std.Io does it for its own
// sockets, and zphp's raw ones may come first
pub fn winsockStartup() error{SystemResources}!void {
    if (!is_windows) return;
    winsock_once.call();
    if (!winsock_ok) return error.SystemResources;
}

pub const ws2 = struct {
    const SOCKET = posix.socket_t;
    pub const INVALID_SOCKET: SOCKET = if (is_windows) @ptrFromInt(std.math.maxInt(usize)) else -1;
    pub const WSA_FLAG_NO_HANDLE_INHERIT: u32 = 0x80;
    pub const FIONBIO: i32 = @bitCast(@as(u32, 0x8004667e));

    pub const WSAEINPROGRESS: i32 = 10036;
    pub const WSAEALREADY: i32 = 10037;
    pub const WSAEWOULDBLOCK: i32 = 10035;
    pub const WSAEMSGSIZE: i32 = 10040;
    pub const WSAEADDRINUSE: i32 = 10048;
    pub const WSAEADDRNOTAVAIL: i32 = 10049;
    pub const WSAENETUNREACH: i32 = 10051;
    pub const WSAECONNABORTED: i32 = 10053;
    pub const WSAECONNRESET: i32 = 10054;
    pub const WSAENOBUFS: i32 = 10055;
    pub const WSAEISCONN: i32 = 10056;
    pub const WSAENOTCONN: i32 = 10057;
    pub const WSAETIMEDOUT: i32 = 10060;
    pub const WSAECONNREFUSED: i32 = 10061;
    pub const WSAEHOSTUNREACH: i32 = 10065;
    pub const WSAEACCES: i32 = 10013;
    pub const WSAEMFILE: i32 = 10024;

    pub const WSADATA = extern struct {
        version: u16,
        high_version: u16,
        // the 32-bit and 64-bit layouts differ only in field order; zphp
        // never reads past the version, so the rest is opaque storage
        rest: [512]u8,
    };

    pub const addrinfo = extern struct {
        flags: packed struct(i32) {
            PASSIVE: bool = false,
            CANONNAME: bool = false,
            NUMERICHOST: bool = false,
            NUMERICSERV: bool = false,
            _: u28 = 0,
        },
        family: i32,
        socktype: i32,
        protocol: i32,
        addrlen: usize,
        canonname: ?[*:0]u8,
        addr: ?*posix.sockaddr,
        next: ?*addrinfo,
    };

    pub extern "ws2_32" fn WSAStartup(version: u16, data: *WSADATA) callconv(.winapi) i32;
    pub extern "ws2_32" fn WSAGetLastError() callconv(.winapi) i32;
    pub extern "ws2_32" fn WSASetLastError(code: i32) callconv(.winapi) void;
    pub extern "ws2_32" fn WSASocketW(af: i32, kind: i32, protocol: i32, info: ?*anyopaque, group: u32, flags: u32) callconv(.winapi) SOCKET;
    pub extern "ws2_32" fn WSAPoll(fds: [*]pollfd, count: u32, timeout: i32) callconv(.winapi) i32;
    pub extern "ws2_32" fn closesocket(s: SOCKET) callconv(.winapi) i32;
    pub extern "ws2_32" fn bind(s: SOCKET, name: *const posix.sockaddr, len: i32) callconv(.winapi) i32;
    pub extern "ws2_32" fn listen(s: SOCKET, backlog: i32) callconv(.winapi) i32;
    pub extern "ws2_32" fn accept(s: SOCKET, addr: ?*posix.sockaddr, len: ?*i32) callconv(.winapi) SOCKET;
    pub extern "ws2_32" fn connect(s: SOCKET, name: *const posix.sockaddr, len: i32) callconv(.winapi) i32;
    pub extern "ws2_32" fn getsockname(s: SOCKET, name: *posix.sockaddr, len: *i32) callconv(.winapi) i32;
    pub extern "ws2_32" fn getpeername(s: SOCKET, name: *posix.sockaddr, len: *i32) callconv(.winapi) i32;
    pub extern "ws2_32" fn getsockopt(s: SOCKET, level: i32, name: i32, value: [*]u8, len: *i32) callconv(.winapi) i32;
    pub extern "ws2_32" fn setsockopt(s: SOCKET, level: i32, name: i32, value: ?[*]const u8, len: i32) callconv(.winapi) i32;
    pub extern "ws2_32" fn ioctlsocket(s: SOCKET, cmd: i32, arg: *u32) callconv(.winapi) i32;
    pub extern "ws2_32" fn send(s: SOCKET, buf: [*]const u8, len: i32, flags: u32) callconv(.winapi) i32;
    pub extern "ws2_32" fn recv(s: SOCKET, buf: [*]u8, len: i32, flags: i32) callconv(.winapi) i32;
    pub extern "ws2_32" fn shutdown(s: SOCKET, how: i32) callconv(.winapi) i32;
    pub extern "ws2_32" fn getaddrinfo(node: ?[*:0]const u8, service: ?[*:0]const u8, hints: ?*const addrinfo, result: *?*addrinfo) callconv(.winapi) i32;
    pub extern "ws2_32" fn freeaddrinfo(info: *addrinfo) callconv(.winapi) void;
};
