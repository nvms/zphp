const std = @import("std");
const tls = @import("tls.zig");
const posix = std.posix;
const Allocator = std.mem.Allocator;

const c = @cImport({
    @cInclude("nghttp2/nghttp2.h");
});

pub const MAX_STREAMS: usize = 64;

pub const Header = struct { name: []const u8, value: []const u8 };

pub const H2Stream = struct {
    stream_id: i32,
    method: []const u8 = "GET",
    path: []const u8 = "/",
    authority: []const u8 = "",
    scheme: []const u8 = "https",
    headers: [64]Header = undefined,
    header_count: usize = 0,
    body: std.ArrayListUnmanaged(u8) = .{},
    complete: bool = false,
    active: bool = false,

    pub fn reset(self: *H2Stream, allocator: Allocator) void {
        self.body.deinit(allocator);
        self.* = .{ .stream_id = 0 };
    }
};

const SessionConn = struct {
    ssl: *tls.SSL,
    fd: posix.fd_t,
};

pub const H2Session = struct {
    session: *c.nghttp2_session,
    allocator: Allocator,
    streams: [MAX_STREAMS]H2Stream = [_]H2Stream{.{ .stream_id = 0 }} ** MAX_STREAMS,
    io: SessionConn,
    send_buf: std.ArrayListUnmanaged(u8) = .{},

    // call initSession after allocating on heap so user_data pointer is stable
    pub fn initSession(self: *H2Session, allocator: Allocator, ssl: *tls.SSL, fd: posix.fd_t) !void {
        self.allocator = allocator;
        self.io = .{ .ssl = ssl, .fd = fd };
        self.streams = [_]H2Stream{.{ .stream_id = 0 }} ** MAX_STREAMS;
        self.send_buf = .{};

        var callbacks: ?*c.nghttp2_session_callbacks = null;
        if (c.nghttp2_session_callbacks_new(&callbacks) != 0) return error.OutOfMemory;
        defer c.nghttp2_session_callbacks_del(callbacks);

        c.nghttp2_session_callbacks_set_on_begin_headers_callback(callbacks, onBeginHeaders);
        c.nghttp2_session_callbacks_set_on_header_callback(callbacks, onHeader);
        c.nghttp2_session_callbacks_set_on_data_chunk_recv_callback(callbacks, onDataChunk);
        c.nghttp2_session_callbacks_set_on_frame_recv_callback(callbacks, onFrameRecv);
        c.nghttp2_session_callbacks_set_on_stream_close_callback(callbacks, onStreamClose);

        var session: ?*c.nghttp2_session = null;
        // self is heap-allocated, so this pointer is stable
        if (c.nghttp2_session_server_new(&session, callbacks, @ptrCast(self)) != 0)
            return error.OutOfMemory;
        self.session = session.?;

        const settings = [_]c.nghttp2_settings_entry{
            .{ .settings_id = c.NGHTTP2_SETTINGS_MAX_CONCURRENT_STREAMS, .value = MAX_STREAMS },
        };
        _ = c.nghttp2_submit_settings(self.session, c.NGHTTP2_FLAG_NONE, &settings, settings.len);
    }

    pub fn deinit(self: *H2Session) void {
        for (&self.streams) |*s| {
            if (s.active) s.reset(self.allocator);
        }
        self.send_buf.deinit(self.allocator);
        c.nghttp2_session_del(self.session);
    }

    pub fn recv(self: *H2Session, data: []const u8) isize {
        return c.nghttp2_session_mem_recv(self.session, data.ptr, data.len);
    }

    pub fn flush(self: *H2Session) !void {
        while (true) {
            var data: [*c]const u8 = null;
            const len = c.nghttp2_session_mem_send(self.session, &data);
            if (len < 0) return error.RuntimeError;
            if (len == 0) break;
            const ulen: usize = @intCast(len);
            var sent: usize = 0;
            while (sent < ulen) {
                const n = tls.write(self.io.ssl, data[sent..ulen]) catch |err| {
                    if (err == error.WouldBlock) {
                        // buffer remaining for later
                        try self.send_buf.appendSlice(self.allocator, data[sent..ulen]);
                        return;
                    }
                    return err;
                };
                sent += n;
            }
        }
    }

    pub fn flushBuffered(self: *H2Session) !void {
        if (self.send_buf.items.len == 0) return;
        var sent: usize = 0;
        while (sent < self.send_buf.items.len) {
            const n = tls.write(self.io.ssl, self.send_buf.items[sent..]) catch |err| {
                if (err == error.WouldBlock) {
                    // shift remaining to front
                    const remaining = self.send_buf.items.len - sent;
                    std.mem.copyForwards(u8, self.send_buf.items[0..remaining], self.send_buf.items[sent..]);
                    self.send_buf.items.len = remaining;
                    return;
                }
                return err;
            };
            sent += n;
        }
        self.send_buf.items.len = 0;
    }

    pub fn findCompletedStream(self: *H2Session) ?*H2Stream {
        for (&self.streams) |*s| {
            if (s.active and s.complete) return s;
        }
        return null;
    }

    fn findStream(self: *H2Session, stream_id: i32) ?*H2Stream {
        for (&self.streams) |*s| {
            if (s.active and s.stream_id == stream_id) return s;
        }
        return null;
    }

    fn allocStream(self: *H2Session, stream_id: i32) ?*H2Stream {
        for (&self.streams) |*s| {
            if (!s.active) {
                s.* = .{ .stream_id = stream_id, .active = true };
                return s;
            }
        }
        return null;
    }

    pub fn submitResponse(self: *H2Session, stream_id: i32, status: u16, content_type: []const u8, body: []const u8) void {
        var status_buf: [3]u8 = undefined;
        const status_str = std.fmt.bufPrint(&status_buf, "{d}", .{status}) catch "200";

        var nv = [_]c.nghttp2_nv{
            makeNv(":status", status_str),
            makeNv("content-type", content_type),
        };

        if (body.len > 0) {
            const src = self.allocator.create(BodySource) catch return;
            src.* = .{ .data = self.allocator.dupe(u8, body) catch return, .pos = 0 };
            var prd = c.nghttp2_data_provider{
                .source = .{ .ptr = @ptrCast(src) },
                .read_callback = bodyReadCb,
            };
            _ = c.nghttp2_submit_response(self.session, stream_id, &nv, nv.len, &prd);
        } else {
            _ = c.nghttp2_submit_response(self.session, stream_id, &nv, nv.len, null);
        }
    }
};

const BodySource = struct {
    data: []const u8,
    pos: usize,
};

fn bodyReadCb(
    _: ?*c.nghttp2_session,
    _: i32,
    buf: [*c]u8,
    length: usize,
    data_flags: [*c]u32,
    source: [*c]c.nghttp2_data_source,
    _: ?*anyopaque,
) callconv(.c) isize {
    const src: *BodySource = @ptrCast(@alignCast(source.*.ptr));
    const remaining = src.data.len - src.pos;
    if (remaining == 0) {
        data_flags.* |= c.NGHTTP2_DATA_FLAG_EOF;
        return 0;
    }
    const to_copy = @min(remaining, length);
    @memcpy(buf[0..to_copy], src.data[src.pos..][0..to_copy]);
    src.pos += to_copy;
    if (src.pos >= src.data.len) {
        data_flags.* |= c.NGHTTP2_DATA_FLAG_EOF;
    }
    return @intCast(to_copy);
}

fn makeNv(name: []const u8, value: []const u8) c.nghttp2_nv {
    return .{
        .name = @constCast(name.ptr),
        .value = @constCast(value.ptr),
        .namelen = name.len,
        .valuelen = value.len,
        .flags = c.NGHTTP2_NV_FLAG_NONE,
    };
}

// nghttp2 callbacks

fn onBeginHeaders(
    _: ?*c.nghttp2_session,
    frame: [*c]const c.nghttp2_frame,
    user_data: ?*anyopaque,
) callconv(.c) c_int {
    const self: *H2Session = @ptrCast(@alignCast(user_data));
    if (frame.*.hd.type != c.NGHTTP2_HEADERS) return 0;
    if (frame.*.headers.cat != c.NGHTTP2_HCAT_REQUEST) return 0;
    _ = self.allocStream(frame.*.hd.stream_id) orelse return c.NGHTTP2_ERR_CALLBACK_FAILURE;
    return 0;
}

fn onHeader(
    _: ?*c.nghttp2_session,
    frame: [*c]const c.nghttp2_frame,
    name_ptr: [*c]const u8,
    namelen: usize,
    value_ptr: [*c]const u8,
    valuelen: usize,
    _: u8,
    user_data: ?*anyopaque,
) callconv(.c) c_int {
    const self: *H2Session = @ptrCast(@alignCast(user_data));
    if (frame.*.hd.type != c.NGHTTP2_HEADERS) return 0;
    const stream = self.findStream(frame.*.hd.stream_id) orelse return 0;
    const name = self.allocator.dupe(u8, name_ptr[0..namelen]) catch return c.NGHTTP2_ERR_CALLBACK_FAILURE;
    const value = self.allocator.dupe(u8, value_ptr[0..valuelen]) catch return c.NGHTTP2_ERR_CALLBACK_FAILURE;

    if (name.len > 0 and name[0] == ':') {
        if (std.mem.eql(u8, name, ":method")) {
            stream.method = value;
        } else if (std.mem.eql(u8, name, ":path")) {
            stream.path = value;
        } else if (std.mem.eql(u8, name, ":authority")) {
            stream.authority = value;
        } else if (std.mem.eql(u8, name, ":scheme")) {
            stream.scheme = value;
        }
    } else {
        if (stream.header_count < 64) {
            stream.headers[stream.header_count] = .{ .name = name, .value = value };
            stream.header_count += 1;
        }
    }
    return 0;
}

fn onDataChunk(
    _: ?*c.nghttp2_session,
    _: u8,
    stream_id: i32,
    data: [*c]const u8,
    len: usize,
    user_data: ?*anyopaque,
) callconv(.c) c_int {
    const self: *H2Session = @ptrCast(@alignCast(user_data));
    const stream = self.findStream(stream_id) orelse return 0;
    stream.body.appendSlice(self.allocator, data[0..len]) catch return c.NGHTTP2_ERR_CALLBACK_FAILURE;
    return 0;
}

fn onFrameRecv(
    _: ?*c.nghttp2_session,
    frame: [*c]const c.nghttp2_frame,
    user_data: ?*anyopaque,
) callconv(.c) c_int {
    const self: *H2Session = @ptrCast(@alignCast(user_data));
    const hd = frame.*.hd;

    // mark stream complete when END_STREAM received on HEADERS or DATA
    if (hd.type == c.NGHTTP2_HEADERS or hd.type == c.NGHTTP2_DATA) {
        if ((hd.flags & c.NGHTTP2_FLAG_END_STREAM) != 0) {
            if (self.findStream(hd.stream_id)) |stream| {
                stream.complete = true;
            }
        }
    }
    return 0;
}

fn onStreamClose(
    _: ?*c.nghttp2_session,
    stream_id: i32,
    _: u32,
    user_data: ?*anyopaque,
) callconv(.c) c_int {
    const self: *H2Session = @ptrCast(@alignCast(user_data));
    if (self.findStream(stream_id)) |stream| {
        stream.reset(self.allocator);
    }
    return 0;
}
