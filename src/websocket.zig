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

fn writeAllTo(writer: anytype, data: []const u8) !void {
    var total: usize = 0;
    while (total < data.len) {
        const n = writer.write(data[total..]) catch return error.IoError;
        if (n == 0) return error.IoError;
        total += n;
    }
}

pub fn writeHandshakeResponse(writer: anytype, accept_key: []const u8) !void {
    var hdr_buf: [256]u8 = undefined;
    const hdr = std.fmt.bufPrint(&hdr_buf, "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {s}\r\n\r\n", .{accept_key}) catch return error.IoError;
    try writeAllTo(writer, hdr);
}

fn readExact(stream: std.net.Stream, buf: []u8) ReadError!void {
    var total: usize = 0;
    while (total < buf.len) {
        const n = stream.read(buf[total..]) catch return ReadError.IoError;
        if (n == 0) return ReadError.ConnectionClosed;
        total += n;
    }
}

// validates the first byte of a frame (FIN + RSV + opcode). returns the opcode
// if the frame header is well-formed per RFC 6455 §5.2 / §5.5, or an error otherwise.
fn validateFrameHeader(b0: u8) ReadError!struct { fin: bool, opcode: Opcode } {
    // RSV1/2/3 must be zero (no extensions negotiated)
    if (b0 & 0x70 != 0) return ReadError.ProtocolError;

    const fin = b0 & 0x80 != 0;
    const opcode_raw: u4 = @truncate(b0 & 0x0F);
    const opcode: Opcode = @enumFromInt(opcode_raw);

    // reject reserved opcodes 0x3-0x7 and 0xB-0xF
    const valid = switch (opcode) {
        .continuation, .text, .binary, .close, .ping, .pong => true,
        else => false,
    };
    if (!valid) return ReadError.ProtocolError;

    // control frames (opcode high bit set) must not be fragmented
    const is_control = opcode_raw & 0x8 != 0;
    if (is_control and !fin) return ReadError.ProtocolError;

    return .{ .fin = fin, .opcode = opcode };
}

fn isControlOpcode(opcode: Opcode) bool {
    return @intFromEnum(opcode) & 0x8 != 0;
}

pub fn readFrame(stream: std.net.Stream, buf: []u8, max_size: usize) ReadError!Frame {
    var hdr: [2]u8 = undefined;
    try readExact(stream, &hdr);

    const h = try validateFrameHeader(hdr[0]);
    const masked = hdr[1] & 0x80 != 0;
    var payload_len: u64 = hdr[1] & 0x7F;

    // control frame payloads must be <= 125 bytes (and thus never use the extended forms)
    if (isControlOpcode(h.opcode) and payload_len > 125) return ReadError.ProtocolError;

    if (payload_len == 126) {
        var ext: [2]u8 = undefined;
        try readExact(stream, &ext);
        payload_len = std.mem.readInt(u16, &ext, .big);
    } else if (payload_len == 127) {
        var ext: [8]u8 = undefined;
        try readExact(stream, &ext);
        payload_len = std.mem.readInt(u64, &ext, .big);
        // RFC 6455: MSB of 8-byte length must be zero
        if (payload_len & (@as(u64, 1) << 63) != 0) return ReadError.ProtocolError;
    }

    // RFC 6455: client frames must be masked
    if (!masked) return ReadError.ProtocolError;

    if (payload_len > max_size or payload_len > buf.len) return ReadError.MessageTooLarge;
    const len: usize = @intCast(payload_len);

    var mask_key: [4]u8 = undefined;
    try readExact(stream, &mask_key);

    if (len > 0) {
        try readExact(stream, buf[0..len]);
        for (0..len) |i| buf[i] ^= mask_key[i % 4];
    }

    return .{ .fin = h.fin, .opcode = h.opcode, .payload = buf[0..len] };
}

pub const ParsedFrame = struct {
    frame: Frame,
    consumed: usize,
};

pub fn tryParseFrame(buf: []u8, max_size: usize) ReadError!?ParsedFrame {
    if (buf.len < 2) return null;

    const h = try validateFrameHeader(buf[0]);
    const masked = buf[1] & 0x80 != 0;
    if (!masked) return ReadError.ProtocolError;

    var payload_len: u64 = buf[1] & 0x7F;
    var offset: usize = 2;

    if (isControlOpcode(h.opcode) and payload_len > 125) return ReadError.ProtocolError;

    if (payload_len == 126) {
        if (buf.len < 4) return null;
        payload_len = std.mem.readInt(u16, buf[2..4], .big);
        offset = 4;
    } else if (payload_len == 127) {
        if (buf.len < 10) return null;
        payload_len = std.mem.readInt(u64, buf[2..10], .big);
        if (payload_len & (@as(u64, 1) << 63) != 0) return ReadError.ProtocolError;
        offset = 10;
    }

    if (payload_len > max_size) return ReadError.MessageTooLarge;
    const mask_offset = offset;
    offset += 4;
    const len: usize = @intCast(payload_len);
    const total = offset + len;
    if (buf.len < total) return null;

    // unmask in place (4 bytes at a time where possible)
    const mask_key = buf[mask_offset..][0..4];
    const payload_ptr = buf[offset..];
    const mask32: u32 = @bitCast(mask_key.*);
    var i: usize = 0;
    while (i + 4 <= len) : (i += 4) {
        const chunk: *align(1) u32 = @ptrCast(payload_ptr[i..][0..4]);
        chunk.* ^= mask32;
    }
    while (i < len) : (i += 1) payload_ptr[i] ^= mask_key[i % 4];

    return ParsedFrame{
        .frame = .{ .fin = h.fin, .opcode = h.opcode, .payload = buf[offset..][0..len] },
        .consumed = total,
    };
}

pub fn writeFrame(writer: anytype, opcode: Opcode, payload: []const u8) !void {
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

    if (payload.len > 0 and hdr_len + payload.len <= 4096) {
        var buf: [4096]u8 = undefined;
        @memcpy(buf[0..hdr_len], hdr[0..hdr_len]);
        @memcpy(buf[hdr_len .. hdr_len + payload.len], payload);
        try writeAllTo(writer, buf[0 .. hdr_len + payload.len]);
    } else {
        try writeAllTo(writer, hdr[0..hdr_len]);
        if (payload.len > 0) try writeAllTo(writer, payload);
    }
}

pub fn writeCloseFrame(writer: anytype, code: u16) !void {
    var payload: [2]u8 = undefined;
    std.mem.writeInt(u16, &payload, code, .big);
    try writeFrame(writer, .close, &payload);
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

fn writeMaskedFrame(stream: std.net.Stream, opcode: Opcode, payload: []const u8) !void {
    var hdr: [14]u8 = undefined;
    var hdr_len: usize = 2;
    hdr[0] = 0x80 | @as(u8, @intFromEnum(opcode));
    if (payload.len < 126) {
        hdr[1] = 0x80 | @as(u8, @intCast(payload.len));
    } else {
        hdr[1] = 0x80 | 126;
        std.mem.writeInt(u16, hdr[2..4], @intCast(payload.len), .big);
        hdr_len = 4;
    }
    // mask key
    const mask = [4]u8{ 0x12, 0x34, 0x56, 0x78 };
    @memcpy(hdr[hdr_len .. hdr_len + 4], &mask);
    hdr_len += 4;
    _ = try stream.write(hdr[0..hdr_len]);
    // write masked payload
    var masked: [256]u8 = undefined;
    for (0..payload.len) |i| masked[i] = payload[i] ^ mask[i % 4];
    if (payload.len > 0) _ = try stream.write(masked[0..payload.len]);
}

test "masked frame write read roundtrip" {
    const pair = try makeSocketPair();
    defer pair[0].close();
    defer pair[1].close();

    try writeMaskedFrame(pair[0], .text, "hello");

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

    // send masked close frame (as client would)
    var close_payload: [2]u8 = undefined;
    std.mem.writeInt(u16, &close_payload, 1000, .big);
    try writeMaskedFrame(pair[0], .close, &close_payload);

    var buf: [256]u8 = undefined;
    const frame = try readFrame(pair[1], &buf, 256);
    try std.testing.expectEqual(Opcode.close, frame.opcode);
    try std.testing.expectEqual(@as(usize, 2), frame.payload.len);
    const code = std.mem.readInt(u16, frame.payload[0..2], .big);
    try std.testing.expectEqual(@as(u16, 1000), code);
}

test "tryParseFrame from buffer" {
    // build a masked text frame in a buffer
    const msg = "hello";
    const mask = [4]u8{ 0xAA, 0xBB, 0xCC, 0xDD };
    var buf: [256]u8 = undefined;
    buf[0] = 0x81; // FIN + text
    buf[1] = 0x80 | msg.len; // masked + length
    @memcpy(buf[2..6], &mask);
    for (0..msg.len) |i| buf[6 + i] = msg[i] ^ mask[i % 4];
    const total = 6 + msg.len;

    // incomplete buffer returns null (no error)
    try std.testing.expect((try tryParseFrame(buf[0..3], 256)) == null);

    // complete buffer returns frame
    const result = (try tryParseFrame(buf[0..total], 256)).?;
    try std.testing.expect(result.frame.fin);
    try std.testing.expectEqual(Opcode.text, result.frame.opcode);
    try std.testing.expectEqualStrings("hello", result.frame.payload);
    try std.testing.expectEqual(total, result.consumed);
}

test "unmasked frame rejected" {
    const pair = try makeSocketPair();
    defer pair[0].close();
    defer pair[1].close();

    // write an unmasked frame (server-style)
    try writeFrame(pair[0], .text, "bad");

    var buf: [256]u8 = undefined;
    const result = readFrame(pair[1], &buf, 256);
    try std.testing.expectError(ReadError.ProtocolError, result);
}

test "tryParseFrame returns error for unmasked" {
    var buf: [16]u8 = undefined;
    buf[0] = 0x81; // FIN + text
    buf[1] = 3; // length 3, NO mask bit
    buf[2] = 'h';
    buf[3] = 'i';
    buf[4] = '!';
    const result = tryParseFrame(buf[0..5], 256);
    try std.testing.expectError(ReadError.ProtocolError, result);
}

test "tryParseFrame returns error for oversized payload" {
    var buf: [16]u8 = undefined;
    buf[0] = 0x81;
    buf[1] = 0x80 | 126;
    std.mem.writeInt(u16, buf[2..4], 9999, .big);
    @memset(buf[4..8], 0);
    const result = tryParseFrame(buf[0..8], 100);
    try std.testing.expectError(ReadError.MessageTooLarge, result);
}

test "rsv bits rejected" {
    var buf: [16]u8 = undefined;
    buf[0] = 0x81 | 0x40; // FIN + text + RSV1
    buf[1] = 0x80 | 0;
    @memset(buf[2..6], 0);
    const result = tryParseFrame(buf[0..6], 256);
    try std.testing.expectError(ReadError.ProtocolError, result);
}

test "reserved opcodes rejected" {
    var buf: [16]u8 = undefined;
    // opcode 0x3 is reserved
    buf[0] = 0x83;
    buf[1] = 0x80 | 0;
    @memset(buf[2..6], 0);
    const result = tryParseFrame(buf[0..6], 256);
    try std.testing.expectError(ReadError.ProtocolError, result);
}

test "fragmented control frame rejected" {
    var buf: [16]u8 = undefined;
    // ping with FIN=0
    buf[0] = 0x09;
    buf[1] = 0x80 | 0;
    @memset(buf[2..6], 0);
    const result = tryParseFrame(buf[0..6], 256);
    try std.testing.expectError(ReadError.ProtocolError, result);
}

test "oversized control frame rejected" {
    var buf: [200]u8 = undefined;
    // ping with 126-byte payload (max control payload is 125)
    buf[0] = 0x89;
    buf[1] = 0x80 | 126;
    @memset(buf[2..], 0);
    const result = tryParseFrame(buf[0..200], 256);
    try std.testing.expectError(ReadError.ProtocolError, result);
}

test "127-length with msb set rejected" {
    var buf: [32]u8 = undefined;
    buf[0] = 0x81;
    buf[1] = 0x80 | 127;
    // set high bit of 8-byte length
    std.mem.writeInt(u64, buf[2..10], @as(u64, 1) << 63, .big);
    @memset(buf[10..14], 0);
    const result = tryParseFrame(buf[0..14], 1 << 20);
    try std.testing.expectError(ReadError.ProtocolError, result);
}
