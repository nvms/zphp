// socket addresses and blocking streams over raw descriptors. php hands
// scripts plain socket descriptors and drives them with poll, so zphp keeps
// sockets as kernel handles and goes through sys.zig rather than std.Io.net
const std = @import("std");
const builtin = @import("builtin");
const sys = @import("sys.zig");
const posix = std.posix;

const is_windows = builtin.os.tag == .windows;
const IoNet = std.Io.net;

pub const has_unix_sockets = IoNet.has_unix_sockets;

// a socket address in the kernel's own layout, so it passes straight to
// bind, connect, accept and getsockname
pub const Address = extern union {
    any: posix.sockaddr,
    in: Ip4,
    in6: Ip6,
    un: if (has_unix_sockets) posix.sockaddr.un else void,

    pub const Ip4 = extern struct { sa: posix.sockaddr.in };
    pub const Ip6 = extern struct { sa: posix.sockaddr.in6 };

    pub fn parseIp(name: []const u8, port: u16) !Address {
        if (parseIp4(name, port)) |a| return a else |_| {}
        if (parseIp6(name, port)) |a| return a else |_| {}
        return error.InvalidIPAddressFormat;
    }

    pub fn parseIp4(text: []const u8, port: u16) !Address {
        const ip = try IoNet.Ip4Address.parse(text, port);
        return initIp4(ip.bytes, port);
    }

    pub fn parseIp6(text: []const u8, port: u16) !Address {
        const ip = try IoNet.Ip6Address.parse(text, port);
        return initIp6(ip.bytes, port, ip.flow, ip.interface.index);
    }

    pub fn initIp4(bytes: [4]u8, port: u16) Address {
        return .{ .in = .{ .sa = .{ .port = std.mem.nativeToBig(u16, port), .addr = @bitCast(bytes) } } };
    }

    pub fn initIp6(bytes: [16]u8, port: u16, flowinfo: u32, scope_id: u32) Address {
        return .{ .in6 = .{ .sa = .{ .port = std.mem.nativeToBig(u16, port), .flowinfo = flowinfo, .addr = bytes, .scope_id = scope_id } } };
    }

    pub fn initUnix(path: []const u8) !Address {
        var sa: posix.sockaddr.un = .{ .family = posix.AF.UNIX, .path = undefined };
        // the path keeps a terminating nul for every platform's sake
        if (path.len + 1 > sa.path.len) return error.NameTooLong;
        @memset(&sa.path, 0);
        @memcpy(sa.path[0..path.len], path);
        return .{ .un = sa };
    }

    pub fn getPort(a: Address) u16 {
        return switch (a.any.family) {
            posix.AF.INET => std.mem.bigToNative(u16, a.in.sa.port),
            posix.AF.INET6 => std.mem.bigToNative(u16, a.in6.sa.port),
            else => unreachable,
        };
    }

    pub fn format(a: Address, w: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (a.any.family) {
            posix.AF.INET => try (IoNet.Ip4Address{ .bytes = @bitCast(a.in.sa.addr), .port = a.getPort() }).format(w),
            posix.AF.INET6 => {
                const ip: IoNet.Ip6Address = .{ .bytes = a.in6.sa.addr, .port = a.getPort(), .flow = a.in6.sa.flowinfo };
                try ip.format(w);
            },
            posix.AF.UNIX => if (has_unix_sockets) try w.writeAll(std.mem.sliceTo(&a.un.path, 0)) else unreachable,
            else => unreachable,
        }
    }

    pub fn getOsSockLen(a: Address) posix.socklen_t {
        return switch (a.any.family) {
            posix.AF.INET => @sizeOf(posix.sockaddr.in),
            posix.AF.INET6 => @sizeOf(posix.sockaddr.in6),
            // the full structure: the path is nul terminated, and the kernel
            // needs the whole buffer when it writes an address back
            posix.AF.UNIX => if (has_unix_sockets) @sizeOf(posix.sockaddr.un) else unreachable,
            else => unreachable,
        };
    }
};

pub const Stream = struct {
    handle: posix.socket_t,

    pub fn close(s: Stream) void {
        sys.closeSocket(s.handle);
    }

    pub fn read(s: Stream, buf: []u8) !usize {
        return sys.recv(s.handle, buf, 0);
    }

    pub fn write(s: Stream, bytes: []const u8) !usize {
        return sys.send(s.handle, bytes, 0);
    }

    pub fn writeAll(s: Stream, bytes: []const u8) !void {
        var i: usize = 0;
        while (i < bytes.len) i += try s.write(bytes[i..]);
    }
};

pub const Server = struct {
    listen_address: Address,
    stream: Stream,

    pub const Connection = struct {
        stream: Stream,
        address: Address,
    };

    pub fn deinit(s: *Server) void {
        s.stream.close();
        s.* = undefined;
    }

    pub fn accept(s: *Server) !Connection {
        var address: Address = undefined;
        var len: posix.socklen_t = @sizeOf(Address);
        const fd = try sys.accept(s.stream.handle, &address.any, &len, if (is_windows) 0 else posix.SOCK.CLOEXEC);
        return .{ .stream = .{ .handle = fd }, .address = address };
    }
};

pub const AddressList = struct {
    arena: std.heap.ArenaAllocator,
    addrs: []Address,
    canon_name: ?[]u8,

    pub fn deinit(self: *AddressList) void {
        // the list lives inside its own arena
        var arena = self.arena;
        arena.deinit();
    }
};

const addrinfo = if (is_windows) sys.ws2.addrinfo else std.c.addrinfo;

// every address a host name resolves to, through the system resolver
pub fn getAddressList(gpa: std.mem.Allocator, name: []const u8, port: u16) !*AddressList {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const a = arena.allocator();
    const result = try a.create(AddressList);
    result.* = .{ .arena = undefined, .addrs = &.{}, .canon_name = null };

    const name_z = try a.dupeSentinel(u8, name, 0);
    var port_buf: [8]u8 = undefined;
    const port_z = std.fmt.bufPrintSentinel(&port_buf, "{d}", .{port}, 0) catch unreachable;

    var hints = std.mem.zeroes(addrinfo);
    hints.flags = if (is_windows) .{ .NUMERICSERV = true } else .{ .NUMERICSERV = true };
    hints.family = posix.AF.UNSPEC;
    hints.socktype = posix.SOCK.STREAM;
    hints.protocol = posix.IPPROTO.TCP;

    var res: ?*addrinfo = null;
    if (is_windows) {
        try sys.winsockStartup();
        if (sys.ws2.getaddrinfo(name_z.ptr, port_z.ptr, &hints, &res) != 0) return error.UnknownHostName;
    } else switch (std.c.getaddrinfo(name_z.ptr, port_z.ptr, &hints, &res)) {
        @as(std.c.EAI, @fromBackingInt(@intCast(0))) => {},
        .AGAIN => return error.TemporaryNameServerFailure,
        .FAIL => return error.NameServerFailure,
        .MEMORY => return error.OutOfMemory,
        else => return error.UnknownHostName,
    }
    defer if (res) |some| (if (is_windows) sys.ws2.freeaddrinfo(some) else std.c.freeaddrinfo(some));

    var count: usize = 0;
    var it = res;
    while (it) |info| : (it = info.next) {
        if (info.addr != null) count += 1;
    }
    const addrs = try a.alloc(Address, count);
    var i: usize = 0;
    it = res;
    while (it) |info| : (it = info.next) {
        const sa = info.addr orelse continue;
        addrs[i] = switch (sa.family) {
            posix.AF.INET => .{ .in = .{ .sa = @as(*align(1) const posix.sockaddr.in, @ptrCast(sa)).* } },
            posix.AF.INET6 => .{ .in6 = .{ .sa = @as(*align(1) const posix.sockaddr.in6, @ptrCast(sa)).* } },
            else => continue,
        };
        if (info.canonname) |n| {
            if (result.canon_name == null) result.canon_name = try a.dupe(u8, std.mem.sliceTo(n, 0));
        }
        i += 1;
    }
    result.addrs = addrs[0..i];
    result.arena = arena;
    return result;
}
