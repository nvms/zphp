const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const std = @import("std");
const platform = @import("../platform.zig");
const net = std.net;
const posix = std.posix;
const Value = @import("../runtime/value.zig").Value;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "ftp_connect", native_ftp_connect },
    .{ "ftp_ssl_connect", native_ftp_ssl_connect },
    .{ "ftp_login", native_ftp_login },
    .{ "ftp_close", native_ftp_close },
    .{ "ftp_quit", native_ftp_close },
    .{ "ftp_pwd", native_ftp_pwd },
    .{ "ftp_chdir", native_ftp_chdir },
    .{ "ftp_cdup", native_ftp_cdup },
    .{ "ftp_mkdir", native_ftp_mkdir },
    .{ "ftp_rmdir", native_ftp_rmdir },
    .{ "ftp_delete", native_ftp_delete },
    .{ "ftp_rename", native_ftp_rename },
    .{ "ftp_size", native_ftp_size },
    .{ "ftp_mdtm", native_ftp_mdtm },
    .{ "ftp_nlist", native_ftp_nlist },
    .{ "ftp_rawlist", native_ftp_rawlist },
    .{ "ftp_raw", native_ftp_raw },
    .{ "ftp_get", native_ftp_get },
    .{ "ftp_put", native_ftp_put },
    .{ "ftp_pasv", native_ftp_pasv },
    .{ "ftp_systype", native_ftp_systype },
    .{ "ftp_set_option", native_ftp_set_option },
    .{ "ftp_get_option", native_ftp_get_option },
    .{ "ftp_alloc", native_ftp_alloc },
    .{ "ftp_site", native_ftp_site },
    .{ "ftp_exec", native_ftp_exec },
    .{ "ftp_chmod", native_ftp_chmod },
};

fn getFd(obj: *PhpObject) ?posix.socket_t {
    const v = obj.get("__fd");
    if (v == .int and v.int >= 0) return platform.socketFromInt(v.int);
    return null;
}

fn getHandle(args: []const Value) ?*PhpObject {
    if (args.len < 1 or args[0] != .object) return null;
    const o = args[0].object;
    if (!std.mem.eql(u8, o.class_name, "FTPHandle")) return null;
    return o;
}

fn readLine(fd: posix.socket_t, buf: []u8) !usize {
    var i: usize = 0;
    while (i < buf.len) {
        var b: [1]u8 = undefined;
        const n = posix.recv(fd, &b, 0) catch return error.IoError;
        if (n == 0) break;
        buf[i] = b[0];
        i += 1;
        if (b[0] == '\n') break;
    }
    return i;
}

const Reply = struct { code: u16, body: []u8 };

// reads a full server reply, handling multi-line responses where the first
// line starts with "NNN-" and continues until a line begins with "NNN "
fn readReply(allocator: std.mem.Allocator, fd: posix.socket_t) !Reply {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);
    var line: [4096]u8 = undefined;
    const first_n = try readLine(fd, &line);
    if (first_n < 4) return error.BadReply;
    try buf.appendSlice(allocator, line[0..first_n]);
    const code_str = line[0..3];
    const code = std.fmt.parseInt(u16, code_str, 10) catch return error.BadReply;
    if (line[3] == '-') {
        // multi-line
        while (true) {
            const n = try readLine(fd, &line);
            if (n == 0) break;
            try buf.appendSlice(allocator, line[0..n]);
            if (n >= 4 and std.mem.eql(u8, line[0..3], code_str) and line[3] == ' ') break;
        }
    }
    return .{ .code = code, .body = try buf.toOwnedSlice(allocator) };
}

fn sendCmd(fd: posix.socket_t, line: []const u8) !void {
    _ = try posix.send(fd, line, 0);
    _ = try posix.send(fd, "\r\n", 0);
}

fn runCmd(allocator: std.mem.Allocator, fd: posix.socket_t, line: []const u8) !Reply {
    try sendCmd(fd, line);
    return try readReply(allocator, fd);
}

fn connectTcp(host: []const u8, port: u16, allocator: std.mem.Allocator) !posix.socket_t {
    const list = try net.getAddressList(allocator, host, port);
    defer list.deinit();
    for (list.addrs) |addr| {
        const sock = platform.tcpSocket(addr.any.family) catch continue;
        posix.connect(sock, &addr.any, addr.getOsSockLen()) catch {
            posix.close(sock);
            continue;
        };
        return sock;
    }
    return error.ConnectFailed;
}

fn native_ftp_connect(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const host = args[0].string.bytes();
    const port: u16 = if (args.len > 1 and args[1] == .int) @intCast(args[1].int) else 21;
    const fd = connectTcp(host, port, ctx.allocator) catch return NativeResult.scalar(.{ .bool = false });
    const reply = readReply(ctx.allocator, fd) catch {
        posix.close(fd);
        return NativeResult.scalar(.{ .bool = false });
    };
    ctx.allocator.free(reply.body);
    if (reply.code != 220) {
        posix.close(fd);
        return NativeResult.scalar(.{ .bool = false });
    }
    const obj = try ctx.createObject("FTPHandle");
    try obj.set(ctx.allocator, "__fd", .{ .int = platform.socketToInt(fd) });
    try obj.set(ctx.allocator, "__pasv", .{ .bool = true });
    try obj.set(ctx.allocator, "__host", args[0]);
    return NativeResult.borrowed(.{ .object = obj });
}

fn native_ftp_ssl_connect(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // FTPS would need TLS over the control + data connections. not yet supported
    return NativeResult.scalar(.{ .bool = false });
}

fn native_ftp_login(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const o = getHandle(args) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 3 or args[1] != .string or args[2] != .string) return NativeResult.scalar(.{ .bool = false });
    const fd = getFd(o) orelse return NativeResult.scalar(.{ .bool = false });
    const user_line = try std.fmt.allocPrint(ctx.allocator, "USER {s}", .{args[1].string.bytes()});
    defer ctx.allocator.free(user_line);
    const r1 = runCmd(ctx.allocator, fd, user_line) catch return NativeResult.scalar(.{ .bool = false });
    defer ctx.allocator.free(r1.body);
    if (r1.code == 230) return NativeResult.scalar(.{ .bool = true });
    if (r1.code != 331) return NativeResult.scalar(.{ .bool = false });
    const pass_line = try std.fmt.allocPrint(ctx.allocator, "PASS {s}", .{args[2].string.bytes()});
    defer ctx.allocator.free(pass_line);
    const r2 = runCmd(ctx.allocator, fd, pass_line) catch return NativeResult.scalar(.{ .bool = false });
    defer ctx.allocator.free(r2.body);
    return NativeResult.scalar(.{ .bool = r2.code == 230 });
}

fn native_ftp_close(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const o = getHandle(args) orelse return NativeResult.scalar(.{ .bool = false });
    const fd = getFd(o) orelse return NativeResult.scalar(.{ .bool = true });
    sendCmd(fd, "QUIT") catch {};
    posix.close(fd);
    o.set(@import("std").heap.page_allocator, "__fd", .{ .int = -1 }) catch {};
    return NativeResult.scalar(.{ .bool = true });
}

fn cmdResult(ctx: *NativeContext, args: []const Value, line: []const u8, ok_codes: []const u16) RuntimeError!bool {
    const o = getHandle(args) orelse return false;
    const fd = getFd(o) orelse return false;
    const r = runCmd(ctx.allocator, fd, line) catch return false;
    defer ctx.allocator.free(r.body);
    for (ok_codes) |c| if (c == r.code) return true;
    return false;
}

fn native_ftp_pwd(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const o = getHandle(args) orelse return NativeResult.scalar(.{ .bool = false });
    const fd = getFd(o) orelse return NativeResult.scalar(.{ .bool = false });
    const r = runCmd(ctx.allocator, fd, "PWD") catch return NativeResult.scalar(.{ .bool = false });
    defer ctx.allocator.free(r.body);
    if (r.code != 257) return NativeResult.scalar(.{ .bool = false });
    // body looks like: 257 "/path" comment\r\n
    const start = std.mem.indexOfScalar(u8, r.body, '"') orelse return NativeResult.scalar(.{ .bool = false });
    const end = std.mem.lastIndexOfScalar(u8, r.body, '"') orelse return NativeResult.scalar(.{ .bool = false });
    if (end <= start) return NativeResult.scalar(.{ .bool = false });
    const path = try ctx.allocator.dupe(u8, r.body[start + 1 .. end]);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, path));
}

fn native_ftp_chdir(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const line = try std.fmt.allocPrint(ctx.allocator, "CWD {s}", .{args[1].string.bytes()});
    defer ctx.allocator.free(line);
    return NativeResult.scalar(.{ .bool = try cmdResult(ctx, args, line, &[_]u16{ 200, 250 }) });
}

fn native_ftp_cdup(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = try cmdResult(ctx, args, "CDUP", &[_]u16{ 200, 250 }) });
}

fn native_ftp_mkdir(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const o = getHandle(args) orelse return NativeResult.scalar(.{ .bool = false });
    const fd = getFd(o) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 2 or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const line = try std.fmt.allocPrint(ctx.allocator, "MKD {s}", .{args[1].string.bytes()});
    defer ctx.allocator.free(line);
    const r = runCmd(ctx.allocator, fd, line) catch return NativeResult.scalar(.{ .bool = false });
    defer ctx.allocator.free(r.body);
    if (r.code != 257) return NativeResult.scalar(.{ .bool = false });
    const path = try ctx.allocator.dupe(u8, args[1].string.bytes());
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, path));
}

fn native_ftp_rmdir(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const line = try std.fmt.allocPrint(ctx.allocator, "RMD {s}", .{args[1].string.bytes()});
    defer ctx.allocator.free(line);
    return NativeResult.scalar(.{ .bool = try cmdResult(ctx, args, line, &[_]u16{250}) });
}

fn native_ftp_delete(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const line = try std.fmt.allocPrint(ctx.allocator, "DELE {s}", .{args[1].string.bytes()});
    defer ctx.allocator.free(line);
    return NativeResult.scalar(.{ .bool = try cmdResult(ctx, args, line, &[_]u16{250}) });
}

fn native_ftp_rename(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const o = getHandle(args) orelse return NativeResult.scalar(.{ .bool = false });
    const fd = getFd(o) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 3 or args[1] != .string or args[2] != .string) return NativeResult.scalar(.{ .bool = false });
    const l1 = try std.fmt.allocPrint(ctx.allocator, "RNFR {s}", .{args[1].string.bytes()});
    defer ctx.allocator.free(l1);
    const r1 = runCmd(ctx.allocator, fd, l1) catch return NativeResult.scalar(.{ .bool = false });
    defer ctx.allocator.free(r1.body);
    if (r1.code != 350) return NativeResult.scalar(.{ .bool = false });
    const l2 = try std.fmt.allocPrint(ctx.allocator, "RNTO {s}", .{args[2].string.bytes()});
    defer ctx.allocator.free(l2);
    const r2 = runCmd(ctx.allocator, fd, l2) catch return NativeResult.scalar(.{ .bool = false });
    defer ctx.allocator.free(r2.body);
    return NativeResult.scalar(.{ .bool = r2.code == 250 });
}

fn native_ftp_size(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const o = getHandle(args) orelse return NativeResult.scalar(.{ .int = -1 });
    const fd = getFd(o) orelse return NativeResult.scalar(.{ .int = -1 });
    if (args.len < 2 or args[1] != .string) return NativeResult.scalar(.{ .int = -1 });
    const type_reply = runCmd(ctx.allocator, fd, "TYPE I") catch return NativeResult.scalar(.{ .int = -1 });
    defer ctx.allocator.free(type_reply.body);
    const line = try std.fmt.allocPrint(ctx.allocator, "SIZE {s}", .{args[1].string.bytes()});
    defer ctx.allocator.free(line);
    const r = runCmd(ctx.allocator, fd, line) catch return NativeResult.scalar(.{ .int = -1 });
    defer ctx.allocator.free(r.body);
    if (r.code != 213) return NativeResult.scalar(.{ .int = -1 });
    // 213 NNN\r\n
    var iter = std.mem.tokenizeAny(u8, r.body, " \r\n");
    _ = iter.next(); // code
    const num_str = iter.next() orelse return NativeResult.scalar(.{ .int = -1 });
    const sz = std.fmt.parseInt(i64, num_str, 10) catch return NativeResult.scalar(.{ .int = -1 });
    return NativeResult.scalar(.{ .int = sz });
}

fn native_ftp_mdtm(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const o = getHandle(args) orelse return NativeResult.scalar(.{ .int = -1 });
    const fd = getFd(o) orelse return NativeResult.scalar(.{ .int = -1 });
    if (args.len < 2 or args[1] != .string) return NativeResult.scalar(.{ .int = -1 });
    const line = try std.fmt.allocPrint(ctx.allocator, "MDTM {s}", .{args[1].string.bytes()});
    defer ctx.allocator.free(line);
    const r = runCmd(ctx.allocator, fd, line) catch return NativeResult.scalar(.{ .int = -1 });
    defer ctx.allocator.free(r.body);
    if (r.code != 213) return NativeResult.scalar(.{ .int = -1 });
    var iter = std.mem.tokenizeAny(u8, r.body, " \r\n");
    _ = iter.next();
    const ts = iter.next() orelse return NativeResult.scalar(.{ .int = -1 });
    if (ts.len < 14) return NativeResult.scalar(.{ .int = -1 });
    // YYYYMMDDHHMMSS UTC
    const year = std.fmt.parseInt(i32, ts[0..4], 10) catch return NativeResult.scalar(.{ .int = -1 });
    const mon = std.fmt.parseInt(u8, ts[4..6], 10) catch return NativeResult.scalar(.{ .int = -1 });
    const day = std.fmt.parseInt(u8, ts[6..8], 10) catch return NativeResult.scalar(.{ .int = -1 });
    const hr = std.fmt.parseInt(u8, ts[8..10], 10) catch return NativeResult.scalar(.{ .int = -1 });
    const mn = std.fmt.parseInt(u8, ts[10..12], 10) catch return NativeResult.scalar(.{ .int = -1 });
    const sc = std.fmt.parseInt(u8, ts[12..14], 10) catch return NativeResult.scalar(.{ .int = -1 });
    const epoch_days = daysFromCivil(year, mon, day);
    const epoch = @as(i64, epoch_days) * 86400 + @as(i64, hr) * 3600 + @as(i64, mn) * 60 + sc;
    return NativeResult.scalar(.{ .int = epoch });
}

fn daysFromCivil(y_in: i32, m: u8, d: u8) i64 {
    // Howard Hinnant algorithm
    var y: i32 = y_in;
    if (m <= 2) y -= 1;
    const era: i32 = @divFloor(if (y >= 0) y else y - 399, 400);
    const yoe: i32 = y - era * 400;
    const mi: i32 = @intCast(m);
    const di: i32 = @intCast(d);
    const doy: i32 = @divTrunc((153 * (if (mi > 2) mi - 3 else mi + 9) + 2), 5) + di - 1;
    const doe: i32 = yoe * 365 + @divTrunc(yoe, 4) - @divTrunc(yoe, 100) + doy;
    return @as(i64, era) * 146097 + @as(i64, doe) - 719468;
}

fn enterPasv(allocator: std.mem.Allocator, ctrl: posix.socket_t) !posix.socket_t {
    const r = try runCmd(allocator, ctrl, "PASV");
    defer allocator.free(r.body);
    if (r.code != 227) return error.PasvFailed;
    // body: "227 Entering Passive Mode (h1,h2,h3,h4,p1,p2)."
    const lp = std.mem.indexOfScalar(u8, r.body, '(') orelse return error.PasvFailed;
    const rp = std.mem.indexOfScalar(u8, r.body, ')') orelse return error.PasvFailed;
    const inner = r.body[lp + 1 .. rp];
    var iter = std.mem.tokenizeScalar(u8, inner, ',');
    var parts: [6]u16 = undefined;
    var idx: usize = 0;
    while (iter.next()) |t| {
        if (idx >= 6) return error.PasvFailed;
        parts[idx] = try std.fmt.parseInt(u16, t, 10);
        idx += 1;
    }
    if (idx != 6) return error.PasvFailed;
    var buf: [32]u8 = undefined;
    const host = try std.fmt.bufPrint(&buf, "{d}.{d}.{d}.{d}", .{ parts[0], parts[1], parts[2], parts[3] });
    const port: u16 = parts[4] * 256 + parts[5];
    return try connectTcp(host, port, allocator);
}

fn readAll(allocator: std.mem.Allocator, fd: posix.socket_t) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);
    var tmp: [8192]u8 = undefined;
    while (true) {
        const n = posix.recv(fd, &tmp, 0) catch return error.IoError;
        if (n == 0) break;
        try buf.appendSlice(allocator, tmp[0..n]);
    }
    return try buf.toOwnedSlice(allocator);
}

fn dataTransfer(ctx: *NativeContext, ctrl: posix.socket_t, list_cmd: []const u8, type_cmd: []const u8) ![]u8 {
    const type_reply = try runCmd(ctx.allocator, ctrl, type_cmd);
    defer ctx.allocator.free(type_reply.body);
    const data_fd = try enterPasv(ctx.allocator, ctrl);
    defer posix.close(data_fd);
    try sendCmd(ctrl, list_cmd);
    const r1 = try readReply(ctx.allocator, ctrl);
    defer ctx.allocator.free(r1.body);
    if (r1.code != 150 and r1.code != 125) return error.BadReply;
    const data = try readAll(ctx.allocator, data_fd);
    errdefer ctx.allocator.free(data);
    const r2 = try readReply(ctx.allocator, ctrl);
    defer ctx.allocator.free(r2.body);
    if (r2.code != 226 and r2.code != 250) {
        return error.BadReply;
    }
    return data;
}

fn native_ftp_nlist(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const o = getHandle(args) orelse return NativeResult.scalar(.{ .bool = false });
    const fd = getFd(o) orelse return NativeResult.scalar(.{ .bool = false });
    const path = if (args.len > 1 and args[1] == .string) args[1].string.bytes() else ".";
    const line = try std.fmt.allocPrint(ctx.allocator, "NLST {s}", .{path});
    defer ctx.allocator.free(line);
    const data = dataTransfer(ctx, fd, line, "TYPE A") catch return NativeResult.scalar(.{ .bool = false });
    defer ctx.allocator.free(data);
    const arr = try ctx.createArray();
    var iter = std.mem.tokenizeAny(u8, data, "\r\n");
    while (iter.next()) |item| {
        const s = try Value.String.create(ctx.allocator, item);
        defer s.release();
        try arr.set(ctx.allocator, .{ .int = arr.next_int_key }, .{ .string = s });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_ftp_rawlist(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const o = getHandle(args) orelse return NativeResult.scalar(.{ .bool = false });
    const fd = getFd(o) orelse return NativeResult.scalar(.{ .bool = false });
    const path = if (args.len > 1 and args[1] == .string) args[1].string.bytes() else ".";
    const line = try std.fmt.allocPrint(ctx.allocator, "LIST {s}", .{path});
    defer ctx.allocator.free(line);
    const data = dataTransfer(ctx, fd, line, "TYPE A") catch return NativeResult.scalar(.{ .bool = false });
    defer ctx.allocator.free(data);
    const arr = try ctx.createArray();
    var iter = std.mem.tokenizeAny(u8, data, "\r\n");
    while (iter.next()) |item| {
        const s = try Value.String.create(ctx.allocator, item);
        defer s.release();
        try arr.set(ctx.allocator, .{ .int = arr.next_int_key }, .{ .string = s });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_ftp_raw(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const o = getHandle(args) orelse return NativeResult.scalar(.{ .bool = false });
    const fd = getFd(o) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 2 or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const r = runCmd(ctx.allocator, fd, args[1].string.bytes()) catch return NativeResult.scalar(.{ .bool = false });
    defer ctx.allocator.free(r.body);
    const arr = try ctx.createArray();
    var iter = std.mem.tokenizeAny(u8, r.body, "\r\n");
    while (iter.next()) |item| {
        const s = try Value.String.create(ctx.allocator, item);
        defer s.release();
        try arr.set(ctx.allocator, .{ .int = arr.next_int_key }, .{ .string = s });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_ftp_get(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const o = getHandle(args) orelse return NativeResult.scalar(.{ .bool = false });
    const fd = getFd(o) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 3 or args[1] != .string or args[2] != .string) return NativeResult.scalar(.{ .bool = false });
    const mode: i64 = if (args.len > 3 and args[3] == .int) args[3].int else 2; // FTP_BINARY
    const tcmd: []const u8 = if (mode == 1) "TYPE A" else "TYPE I";
    const line = try std.fmt.allocPrint(ctx.allocator, "RETR {s}", .{args[2].string.bytes()});
    defer ctx.allocator.free(line);
    const data = dataTransfer(ctx, fd, line, tcmd) catch return NativeResult.scalar(.{ .bool = false });
    defer ctx.allocator.free(data);
    var f = std.fs.cwd().createFile(args[1].string.bytes(), .{ .truncate = true }) catch return NativeResult.scalar(.{ .bool = false });
    defer f.close();
    f.writeAll(data) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn native_ftp_put(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const o = getHandle(args) orelse return NativeResult.scalar(.{ .bool = false });
    const fd = getFd(o) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 3 or args[1] != .string or args[2] != .string) return NativeResult.scalar(.{ .bool = false });
    const mode: i64 = if (args.len > 3 and args[3] == .int) args[3].int else 2;
    const tcmd: []const u8 = if (mode == 1) "TYPE A" else "TYPE I";
    const type_reply = runCmd(ctx.allocator, fd, tcmd) catch return NativeResult.scalar(.{ .bool = false });
    defer ctx.allocator.free(type_reply.body);
    const data_fd = enterPasv(ctx.allocator, fd) catch return NativeResult.scalar(.{ .bool = false });
    defer posix.close(data_fd);
    const line = try std.fmt.allocPrint(ctx.allocator, "STOR {s}", .{args[1].string.bytes()});
    defer ctx.allocator.free(line);
    sendCmd(fd, line) catch return NativeResult.scalar(.{ .bool = false });
    const r1 = readReply(ctx.allocator, fd) catch return NativeResult.scalar(.{ .bool = false });
    defer ctx.allocator.free(r1.body);
    if (r1.code != 150 and r1.code != 125) return NativeResult.scalar(.{ .bool = false });

    var f = std.fs.cwd().openFile(args[2].string.bytes(), .{}) catch return NativeResult.scalar(.{ .bool = false });
    defer f.close();
    var buf: [8192]u8 = undefined;
    while (true) {
        const n = f.read(&buf) catch return NativeResult.scalar(.{ .bool = false });
        if (n == 0) break;
        _ = posix.send(data_fd, buf[0..n], 0) catch return NativeResult.scalar(.{ .bool = false });
    }
    posix.shutdown(data_fd, .both) catch {};
    const r2 = readReply(ctx.allocator, fd) catch return NativeResult.scalar(.{ .bool = false });
    defer ctx.allocator.free(r2.body);
    return NativeResult.scalar(.{ .bool = r2.code == 226 or r2.code == 250 });
}

fn native_ftp_pasv(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const o = getHandle(args) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len > 1 and args[1] == .bool) {
        o.set(std.heap.page_allocator, "__pasv", .{ .bool = args[1].bool }) catch {};
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn native_ftp_systype(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const o = getHandle(args) orelse return NativeResult.scalar(.{ .bool = false });
    const fd = getFd(o) orelse return NativeResult.scalar(.{ .bool = false });
    const r = runCmd(ctx.allocator, fd, "SYST") catch return NativeResult.scalar(.{ .bool = false });
    defer ctx.allocator.free(r.body);
    if (r.code != 215) return NativeResult.scalar(.{ .bool = false });
    var iter = std.mem.tokenizeAny(u8, r.body, " \r\n");
    _ = iter.next();
    const sys = iter.next() orelse return NativeResult.scalar(.{ .bool = false });
    const s = try ctx.allocator.dupe(u8, sys);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, s));
}

fn native_ftp_set_option(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = true });
}

fn native_ftp_get_option(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // option 0 = FTP_TIMEOUT_SEC, return 90 as a stable default
    if (args.len > 1 and args[1] == .int) return NativeResult.scalar(.{ .int = 90 });
    return NativeResult.scalar(.{ .bool = false });
}

fn native_ftp_alloc(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = true });
}

fn native_ftp_site(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const line = try std.fmt.allocPrint(ctx.allocator, "SITE {s}", .{args[1].string.bytes()});
    defer ctx.allocator.free(line);
    return NativeResult.scalar(.{ .bool = try cmdResult(ctx, args, line, &[_]u16{ 200, 250 }) });
}

fn native_ftp_exec(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const line = try std.fmt.allocPrint(ctx.allocator, "SITE EXEC {s}", .{args[1].string.bytes()});
    defer ctx.allocator.free(line);
    return NativeResult.scalar(.{ .bool = try cmdResult(ctx, args, line, &[_]u16{ 200, 250 }) });
}

fn native_ftp_chmod(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 3 or args[1] != .int or args[2] != .string) return NativeResult.scalar(.{ .bool = false });
    const line = try std.fmt.allocPrint(ctx.allocator, "SITE CHMOD {o} {s}", .{ @as(u64, @intCast(args[1].int)), args[2].string.bytes() });
    defer ctx.allocator.free(line);
    if (try cmdResult(ctx, args, line, &[_]u16{ 200, 250 })) return NativeResult.scalar(.{ .int = args[1].int });
    return NativeResult.scalar(.{ .bool = false });
}

pub fn cleanupResources(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    for (objects.items) |obj| {
        if (!std.mem.eql(u8, obj.class_name, "FTPHandle")) continue;
        const v = obj.get("__fd");
        if (v == .int and v.int >= 0) {
            platform.closeSocket(v.int);
        }
    }
}

test {}
