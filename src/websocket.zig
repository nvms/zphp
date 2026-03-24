const std = @import("std");

const ws_guid = "258EAFA5-E914-47DA-95CA-5AB9DC76B45E";

pub const Opcode = enum(u4) {
    continuation = 0x0,
    text = 0x1,
    binary = 0x2,
    close = 0x8,
    ping = 0x9,
    pong = 0xA,
    _,
};

pub const Frame = struct {
    fin: bool,
    opcode: Opcode,
    payload: []const u8,
};

pub const ReadError = error{
    ConnectionClosed,
    ProtocolError,
    MessageTooLarge,
    IoError,
};

pub fn computeAcceptKey(key: []const u8, buf: *[28]u8) []const u8 {
    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(key);
    hasher.update(ws_guid);
    const hash = hasher.finalResult();
    return std.base64.standard.Encoder.encode(buf, &hash);
}

pub fn writeHandshakeResponse(stream: std.net.Stream, accept_key: []const u8) !void {
    var hdr_buf: [256]u8 = undefined;
    const hdr = std.fmt.bufPrint(&hdr_buf, "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {s}\r\n\r\n", .{accept_key}) catch return error.IoError;
    _ = stream.write(hdr) catch return error.IoError;
}

fn readExact(stream: std.net.Stream, buf: []u8) ReadError!void {
    var total: usize = 0;
    while (total < buf.len) {
        const n = stream.read(buf[total..]) catch return ReadError.IoError;
        if (n == 0) return ReadError.ConnectionClosed;
        total += n;
    }
}

pub fn readFrame(stream: std.net.Stream, buf: []u8, max_size: usize) ReadError!Frame {
    var hdr: [2]u8 = undefined;
    try readExact(stream, &hdr);

    const fin = hdr[0] & 0x80 != 0;
    const opcode: Opcode = @enumFromInt(@as(u4, @truncate(hdr[0] & 0x0F)));
    const masked = hdr[1] & 0x80 != 0;
    var payload_len: u64 = hdr[1] & 0x7F;

    if (payload_len == 126) {
        var ext: [2]u8 = undefined;
        try readExact(stream, &ext);
        payload_len = std.mem.readInt(u16, &ext, .big);
    } else if (payload_len == 127) {
        var ext: [8]u8 = undefined;
        try readExact(stream, &ext);
        payload_len = std.mem.readInt(u64, &ext, .big);
    }

    if (payload_len > max_size or payload_len > buf.len) return ReadError.MessageTooLarge;
    const len: usize = @intCast(payload_len);

    var mask_key: [4]u8 = undefined;
    if (masked) {
        try readExact(stream, &mask_key);
    }

    if (len > 0) {
        try readExact(stream, buf[0..len]);
        if (masked) {
            for (0..len) |i| buf[i] ^= mask_key[i % 4];
        }
    }

    return .{ .fin = fin, .opcode = opcode, .payload = buf[0..len] };
}

pub fn writeFrame(stream: std.net.Stream, opcode: Opcode, payload: []const u8) !void {
    var hdr: [10]u8 = undefined;
    var hdr_len: usize = 2;

    hdr[0] = 0x80 | @as(u8, @intFromEnum(opcode));

    if (payload.len < 126) {
        hdr[1] = @intCast(payload.len);
    } else if (payload.len <= 65535) {
        hdr[1] = 126;
        std.mem.writeInt(u16, hdr[2..4], @intCast(payload.len), .big);
        hdr_len = 4;
    } else {
        hdr[1] = 127;
        std.mem.writeInt(u64, hdr[2..10], @intCast(payload.len), .big);
        hdr_len = 10;
    }

    _ = try stream.write(hdr[0..hdr_len]);
    if (payload.len > 0) {
        _ = try stream.write(payload);
    }
}

pub fn writeCloseFrame(stream: std.net.Stream, code: u16) !void {
    var payload: [2]u8 = undefined;
    std.mem.writeInt(u16, &payload, code, .big);
    try writeFrame(stream, .close, &payload);
}

// tests

test "accept key computation" {
    var buf: [28]u8 = undefined;
    const result = computeAcceptKey("dGhlIHNhbXBsZSBub25jZQ==", &buf);
    // verified against python hashlib.sha1 + base64
    try std.testing.expectEqualStrings("7PUt+8lkGD5HVZbKJuYuOJV1CNA=", result);
}

fn makeSocketPair() ![2]std.net.Stream {
    var fds: [2]std.posix.fd_t = undefined;
    if (std.c.socketpair(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0, &fds) != 0) return error.IoError;
    return .{
        std.net.Stream{ .handle = fds[0] },
        std.net.Stream{ .handle = fds[1] },
    };
}

test "frame write read roundtrip" {
    const pair = try makeSocketPair();
    defer pair[0].close();
    defer pair[1].close();

    try writeFrame(pair[0], .text, "hello");

    var buf: [256]u8 = undefined;
    const frame = try readFrame(pair[1], &buf, 256);
    try std.testing.expect(frame.fin);
    try std.testing.expectEqual(Opcode.text, frame.opcode);
    try std.testing.expectEqualStrings("hello", frame.payload);
}

test "close frame encoding" {
    const pair = try makeSocketPair();
    defer pair[0].close();
    defer pair[1].close();

    try writeCloseFrame(pair[0], 1000);

    var buf: [256]u8 = undefined;
    const frame = try readFrame(pair[1], &buf, 256);
    try std.testing.expectEqual(Opcode.close, frame.opcode);
    try std.testing.expectEqual(@as(usize, 2), frame.payload.len);
    const code = std.mem.readInt(u16, frame.payload[0..2], .big);
    try std.testing.expectEqual(@as(u16, 1000), code);
}
