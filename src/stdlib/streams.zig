// php's stream layer (main/streams/streams.c): every stream resource carries
// a Stream with php's read buffer, logical position, eof flag, chunk size and
// filter chains. the bytes themselves move through raw operations picked by
// what backs the stream: a descriptor, a socket, a memory buffer, or a user
// wrapper object. reads fill the read buffer a chunk at a time through the
// read filters; writes pass through the write filters to the raw write
const std = @import("std");
const Allocator = std.mem.Allocator;
const platform = @import("../platform.zig");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const PhpObject = value_mod.PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const fs = @import("filesystem.zig");
const filters = @import("stream_filters.zig");
const user_streams = @import("user_streams.zig");
const http = @import("http_wrapper.zig");

const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const chunk_default: usize = 8192;

// set while php_request_shutdown closes what is still open: a user filter
// then sees no stream at all
pub threadlocal var at_shutdown: bool = false;

// php://memory, php://temp and the read-only buffers (data:, php://input,
// phar entries, decompressed files) keep their bytes here, with php's own
// memory stream position and mode
pub const Memory = struct {
    data: std.ArrayListUnmanaged(u8) = .empty,
    fpos: usize = 0,
    mode: Mode = .default,
    // php://temp reads its inner memory stream greedily, so a read that
    // comes up short has reached the end
    temp: bool = false,

    pub const Mode = enum { default, readonly, append };
};

pub const Stream = struct {
    allocator: Allocator,
    readbuf: []u8 = &.{},
    readpos: usize = 0,
    writepos: usize = 0,
    position: i64 = 0,
    chunk_size: usize = chunk_default,
    eof: bool = false,
    fatal_error: bool = false,
    // reads bypass the buffer (php://memory and php://temp)
    no_buffer: bool = false,
    no_seek: bool = false,
    was_written: bool = false,
    // php keeps reading until it has the whole request for plain files and
    // memory streams; every other stream returns what one read brought
    greedy: bool = false,
    detect_eol: bool = false,
    eol_mac: bool = false,
    in_free: bool = false,
    // the stream's ops have no write (data: streams): fwrite gets php's
    // "Stream is not writable" notice
    no_write_op: bool = false,
    // a filter callback or user stream method is running: fclose refuses
    busy: u32 = 0,
    mem: ?*Memory = null,
    readfilters: filters.Chain = .{ .read = true },
    writefilters: filters.Chain = .{},
    // the wrapper's data for stream_get_meta_data (the http response
    // headers), owned
    wrapperdata: Value = .null,
    backend_cache: ?Backend = null,
    // a read may wait (a pipe, a socket, a terminal): php's cli has written
    // every echo by then, so zphp flushes its output first
    may_block: bool = false,

    pub fn buffered(self: *const Stream) usize {
        return self.writepos - self.readpos;
    }

    fn deinit(self: *Stream) void {
        if (self.readbuf.len > 0) self.allocator.free(self.readbuf);
        self.readbuf = &.{};
        if (self.mem) |m| {
            m.data.deinit(self.allocator);
            self.allocator.destroy(m);
            self.mem = null;
        }
    }
};

pub fn get(obj: *PhpObject) ?*Stream {
    return obj.native.get(Stream, .stream);
}

pub const Options = struct {
    greedy: bool = false,
    no_buffer: bool = false,
    memory: ?Memory.Mode = null,
};

// the stream behind a FileHandle, made with php's defaults the first time
// it is needed
pub fn of(ctx: *NativeContext, obj: *PhpObject) RuntimeError!*Stream {
    if (get(obj)) |s| return s;
    return attach(ctx, obj, .{});
}

pub fn attach(ctx: *NativeContext, obj: *PhpObject, opts: Options) RuntimeError!*Stream {
    return attachWith(ctx.allocator, obj, opts);
}

pub fn attachWith(allocator: Allocator, obj: *PhpObject, opts: Options) RuntimeError!*Stream {
    if (get(obj)) |s| {
        s.greedy = opts.greedy;
        s.no_buffer = opts.no_buffer;
        return s;
    }
    const s = try allocator.create(Stream);
    s.* = .{ .allocator = allocator, .greedy = opts.greedy, .no_buffer = opts.no_buffer };
    s.readfilters.owner = obj;
    s.writefilters.owner = obj;
    if (opts.memory) |mode| {
        const m = try allocator.create(Memory);
        m.* = .{ .mode = mode };
        s.mem = m;
    } else switch (backend(obj)) {
        .fd => |io| {
            s.may_block = io.socket or !fs.isRegularFile(io.file);
            if (io.socket) {
                s.no_seek = true;
            } else if (!fs.isSeekable(obj)) {
                s.no_seek = true;
                s.position = -1;
            } else {
                s.position = @intCast(platform.getPos(io.file) catch 0);
            }
        },
        .user => {},
        else => {},
    }
    obj.native = .{ .kind = .stream, .ptr = @intFromPtr(s) };
    return s;
}

// the memory a memory stream keeps, adopting bytes as its contents
pub fn setMemory(s: *Stream, bytes: []const u8) RuntimeError!void {
    const m = s.mem orelse return;
    m.data.clearRetainingCapacity();
    try m.data.appendSlice(s.allocator, bytes);
    m.fpos = 0;
}

pub fn memoryOf(obj: *PhpObject) ?*Memory {
    const s = get(obj) orelse return null;
    return s.mem;
}

// frees the native state when the resource object goes away
pub fn release(obj: *PhpObject) void {
    const s = get(obj) orelse return;
    filters.releaseChain(&s.readfilters);
    filters.releaseChain(&s.writefilters);
    s.deinit();
    const a = s.allocator;
    a.destroy(s);
    obj.native = .{};
}

// --- notifications (php_stream_notify_*) --------------------------------------

fn contextOf(obj: *PhpObject) ?*PhpObject {
    const c = obj.get("__context");
    return if (c == .resource) c.resource else null;
}

// php_stream_notify_progress_init: the notifier starts counting
pub fn progressInit(ctx: *NativeContext, context: ?*PhpObject, max: i64) RuntimeError!void {
    const c = context orelse return;
    if (c.get("notification") == .null) return;
    try c.set(ctx.allocator, "__progress", .{ .int = 0 });
    try c.set(ctx.allocator, "__progress_max", .{ .int = max });
    try http.notify(ctx, c, http.NOTIFY_PROGRESS, 0, null, 0, 0, max);
}

// php_stream_notify_progress_increment, for a counting notifier
pub fn progressIncrement(ctx: *NativeContext, context: ?*PhpObject, n: i64) RuntimeError!void {
    const c = context orelse return;
    const sofar = c.get("__progress");
    if (sofar != .int) return;
    const now = sofar.int + n;
    try c.set(ctx.allocator, "__progress", .{ .int = now });
    try http.notify(ctx, c, http.NOTIFY_PROGRESS, 0, null, 0, now, Value.toInt(c.get("__progress_max")));
}

fn notifyCompleted(ctx: *NativeContext, obj: *PhpObject) RuntimeError!void {
    const c = contextOf(obj) orelse return;
    if (c.get("notification") == .null) return;
    try http.notify(ctx, c, http.NOTIFY_COMPLETED, 0, null, 0, Value.toInt(c.get("__progress")), Value.toInt(c.get("__progress_max")));
}

// --- raw operations ---------------------------------------------------------

pub const Backend = union(enum) {
    none,
    user: *PhpObject,
    memory: *Memory,
    // a write-only accumulator (compress.zlib:// writes, popen "w")
    accumulate,
    fd: fs.StreamIo,
};

// what moves the stream's bytes, worked out once per stream: the
// properties that say it don't change while the stream is open
pub fn backend(obj: *PhpObject) Backend {
    const s = get(obj) orelse return findBackend(obj);
    if (s.backend_cache) |b| return b;
    const b = findBackend(obj);
    s.backend_cache = b;
    return b;
}

fn findBackend(obj: *PhpObject) Backend {
    if (fs.fileHandleWrapper(obj)) |w| return .{ .user = w };
    if (get(obj)) |s| if (s.mem) |m| return .{ .memory = m };
    if (fs.isAccumulating(obj)) return .accumulate;
    if (fs.streamIo(obj)) |io| return .{ .fd = io };
    return .none;
}

// ops->read: the byte count, or -1 on failure
pub fn rawRead(ctx: *NativeContext, obj: *PhpObject, s: *Stream, dest: []u8) RuntimeError!isize {
    switch (backend(obj)) {
        .user => |w| return user_streams.read(ctx, obj, s, w, dest),
        .memory => |m| {
            if (m.fpos >= m.data.items.len) {
                s.eof = true;
                return 0;
            }
            const n = @min(dest.len, m.data.items.len - m.fpos);
            @memcpy(dest[0..n], m.data.items[m.fpos..][0..n]);
            m.fpos += n;
            if (m.temp and n < dest.len) s.eof = true;
            return @intCast(n);
        },
        .fd => |io| {
            if (s.may_block) ctx.vm.flushOutputToStdout();
            const n = io.read(dest) catch |err| {
                if (err == error.WouldBlock) return 0;
                if (io.socket) {
                    s.eof = true;
                } else {
                    try fs.ioFailure(ctx, "Read", dest.len, err);
                    if (err != error.NotOpenForReading) s.eof = true;
                }
                return -1;
            };
            if (n == 0) s.eof = true;
            if (io.socket and n > 0) try progressIncrement(ctx, contextOf(obj), @intCast(n));
            return @intCast(n);
        },
        .accumulate, .none => return -1,
    }
}

// ops->write: the byte count, or -1 on failure
pub fn rawWrite(ctx: *NativeContext, obj: *PhpObject, s: *Stream, data: []const u8) RuntimeError!isize {
    switch (backend(obj)) {
        .user => |w| return user_streams.write(ctx, obj, s, w, data),
        .memory => |m| {
            if (m.mode == .readonly) return -1;
            if (m.mode == .append) m.fpos = m.data.items.len;
            const end = m.fpos + data.len;
            if (end > m.data.items.len) {
                const old = m.data.items.len;
                try m.data.resize(s.allocator, end);
                if (m.fpos > old) @memset(m.data.items[old..m.fpos], 0);
            }
            @memcpy(m.data.items[m.fpos..end], data);
            m.fpos = end;
            return @intCast(data.len);
        },
        .accumulate => return @intCast(try fs.accumulate(ctx, obj, data)),
        .fd => |io| return fs.fdWrite(ctx, obj, io, data),
        .none => return -1,
    }
}

// ops->seek: the new position, or null when the stream refused
pub fn rawSeek(ctx: *NativeContext, obj: *PhpObject, s: *Stream, offset: i64, whence: u2) RuntimeError!?i64 {
    switch (backend(obj)) {
        .user => |w| return user_streams.seek(ctx, obj, s, w, offset, whence),
        .memory => |m| {
            const len: i64 = @intCast(m.data.items.len);
            const fpos: i64 = @intCast(m.fpos);
            const target: i64 = switch (whence) {
                1 => fpos + offset,
                2 => len + offset,
                else => offset,
            };
            if (target < 0) {
                // php leaves the memory stream at 0 with its position unknown
                m.fpos = 0;
                return -1;
            }
            m.fpos = @intCast(target);
            s.eof = false;
            s.fatal_error = false;
            return target;
        },
        .fd => |io| {
            if (io.socket) return null;
            switch (whence) {
                0 => platform.seekTo(io.file, std.math.cast(u64, offset) orelse return null) catch return null,
                1 => platform.seekBy(io.file, offset) catch return null,
                else => platform.seekFromEnd(io.file, offset) catch return null,
            }
            return @intCast(platform.getPos(io.file) catch return null);
        },
        .accumulate, .none => return null,
    }
}

fn hasSeek(obj: *PhpObject) bool {
    return switch (backend(obj)) {
        .user, .memory => true,
        .fd => |io| !io.socket,
        else => false,
    };
}

fn rawFlush(ctx: *NativeContext, obj: *PhpObject) RuntimeError!bool {
    return switch (backend(obj)) {
        .user => |w| user_streams.flush(ctx, w),
        else => true,
    };
}

// --- reading -----------------------------------------------------------------

fn ensureRoom(s: *Stream, room: usize) RuntimeError!void {
    if (s.readbuf.len - s.writepos >= room) return;
    // reduce buffer memory consumption if possible, to avoid a realloc
    if (s.readpos > 0) {
        const avail = s.writepos - s.readpos;
        std.mem.copyForwards(u8, s.readbuf[0..avail], s.readbuf[s.readpos..s.writepos]);
        s.writepos = avail;
        s.readpos = 0;
    }
    if (s.readbuf.len - s.writepos >= room) return;
    const newlen = s.readbuf.len + room;
    s.readbuf = if (s.readbuf.len == 0) try s.allocator.alloc(u8, newlen) else try s.allocator.realloc(s.readbuf, newlen);
}

fn appendToReadBuffer(s: *Stream, bytes: []const u8) RuntimeError!void {
    if (s.readbuf.len > 0 and s.readbuf.len - s.writepos < bytes.len and s.writepos > s.readpos) {
        const avail = s.writepos - s.readpos;
        std.mem.copyForwards(u8, s.readbuf[0..avail], s.readbuf[s.readpos..s.writepos]);
        s.writepos = avail;
        s.readpos = 0;
    } else if (s.readbuf.len > 0 and s.readbuf.len - s.writepos < bytes.len) {
        s.writepos -= s.readpos;
        s.readpos = 0;
    }
    if (s.readbuf.len - s.writepos < bytes.len) {
        const newlen = s.readbuf.len + bytes.len;
        s.readbuf = if (s.readbuf.len == 0) try s.allocator.alloc(u8, newlen) else try s.allocator.realloc(s.readbuf, newlen);
    }
    @memcpy(s.readbuf[s.writepos..][0..bytes.len], bytes);
    s.writepos += bytes.len;
}

// _php_stream_fill_read_buffer: false on failure
pub fn fillReadBuffer(ctx: *NativeContext, obj: *PhpObject, s: *Stream, size: usize) RuntimeError!bool {
    const old_eof = s.eof;
    const ok = try fillReadBufferInner(ctx, obj, s, size);
    if (old_eof != s.eof) try notifyCompleted(ctx, obj);
    return ok;
}

fn fillReadBufferInner(ctx: *NativeContext, obj: *PhpObject, s: *Stream, size: usize) RuntimeError!bool {
    if (s.readfilters.head != null) {
        const to_read_now = @min(size, s.chunk_size);
        const chunk = try s.allocator.alloc(u8, s.chunk_size);
        defer s.allocator.free(chunk);
        while (!s.eof and s.writepos - s.readpos < to_read_now) {
            var brig_in: filters.Brigade = .{};
            var brig_out: filters.Brigade = .{};
            const justread = try rawRead(ctx, obj, s, chunk);
            var flags: filters.Flags = undefined;
            if (justread < 0 and s.writepos == s.readpos) return false;
            if (justread > 0) {
                try brig_in.append(try filters.Bucket.create(s.allocator, chunk[0..@intCast(justread)]));
                flags = if (s.eof) .flush_close else .normal;
            } else {
                flags = if (s.eof) .flush_close else .flush_inc;
            }
            const status = try filters.runChain(ctx, obj, &s.readfilters, s.readfilters.head, &brig_in, &brig_out, null, flags);
            switch (status.status) {
                .pass_on => {
                    const out = status.output;
                    while (out.head) |bucket| {
                        bucket.unlink();
                        defer bucket.delref();
                        try appendToReadBuffer(s, bucket.bytes());
                    }
                },
                .feed_me => {
                    status.discardOutput();
                },
                .err_fatal => {
                    s.eof = true;
                    s.fatal_error = true;
                    brig_in.clear();
                    brig_out.clear();
                    return false;
                },
            }
            if (justread <= 0) break;
        }
        return true;
    }
    if (s.writepos - s.readpos < size) {
        try ensureRoom(s, s.chunk_size);
        const justread = try rawRead(ctx, obj, s, s.readbuf[s.writepos..]);
        if (justread < 0) return false;
        s.writepos += @intCast(justread);
    }
    return true;
}

// _php_stream_read: bytes read (0 at eof), or -1 on failure
pub fn read(ctx: *NativeContext, obj: *PhpObject, dest: []u8) RuntimeError!isize {
    const s = try of(ctx, obj);
    var didread: usize = 0;
    var size = dest.len;
    var buf = dest;
    while (size > 0) {
        if (s.writepos > s.readpos) {
            const toread = @min(s.writepos - s.readpos, size);
            @memcpy(buf[0..toread], s.readbuf[s.readpos..][0..toread]);
            s.readpos += toread;
            size -= toread;
            buf = buf[toread..];
            didread += toread;
        }
        if (size == 0) break;
        var toread: usize = 0;
        if (s.readfilters.head == null and (s.no_buffer or s.chunk_size == 1)) {
            const n = try rawRead(ctx, obj, s, buf[0..size]);
            if (n < 0) {
                if (didread == 0) return n;
                break;
            }
            toread = @intCast(n);
        } else {
            if (!try fillReadBuffer(ctx, obj, s, size)) {
                if (didread == 0) return -1;
                break;
            }
            toread = @min(s.writepos - s.readpos, size);
            if (toread > 0) {
                @memcpy(buf[0..toread], s.readbuf[s.readpos..][0..toread]);
                s.readpos += toread;
            }
        }
        if (toread == 0) break;
        didread += toread;
        buf = buf[toread..];
        size -= toread;
        if (!s.greedy) break;
    }
    if (didread > 0) s.position += @intCast(didread);
    return @intCast(didread);
}

pub fn getc(ctx: *NativeContext, obj: *PhpObject) RuntimeError!?u8 {
    var b: [1]u8 = undefined;
    if (try read(ctx, obj, &b) > 0) return b[0];
    return null;
}

fn locateEol(s: *Stream) ?usize {
    const avail = s.readbuf[s.readpos..s.writepos];
    if (s.detect_eol) {
        const cr = std.mem.indexOfScalar(u8, avail, '\r');
        const lf = std.mem.indexOfScalar(u8, avail, '\n');
        if (cr != null and (lf == null or lf.? != cr.? + 1) and !(lf != null and lf.? < cr.?)) {
            s.detect_eol = false;
            s.eol_mac = true;
            return cr;
        } else if (lf != null) {
            s.detect_eol = false;
            return lf;
        }
        return null;
    }
    if (s.eol_mac) return std.mem.indexOfScalar(u8, avail, '\r');
    return std.mem.indexOfScalar(u8, avail, '\n');
}

// _php_stream_get_line: the next line through its end of line, owned by the
// caller; maxlen counts php's terminating nul (fgets' length), null reads
// the whole line however long. null at the end of the stream
pub fn getLine(ctx: *NativeContext, obj: *PhpObject, maxlen_arg: ?usize) RuntimeError!?[]u8 {
    const s = try of(ctx, obj);
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(ctx.allocator);
    const grow = maxlen_arg == null;
    var maxlen: usize = maxlen_arg orelse 0;
    if (!grow and maxlen == 0) return null;
    while (true) {
        const avail = s.writepos - s.readpos;
        if (avail > 0) {
            var done = false;
            var cpysz: usize = avail;
            if (locateEol(s)) |eol| {
                cpysz = eol + 1;
                done = true;
            }
            if (!grow and cpysz >= maxlen - 1) {
                cpysz = maxlen - 1;
                done = true;
            }
            try out.appendSlice(ctx.allocator, s.readbuf[s.readpos..][0..cpysz]);
            s.position += @intCast(cpysz);
            s.readpos += cpysz;
            if (!grow) maxlen -= cpysz;
            if (done) break;
        } else if (s.eof) {
            break;
        } else {
            const toread: usize = if (grow) s.chunk_size else @min(maxlen - 1, s.chunk_size);
            if (!try fillReadBuffer(ctx, obj, s, toread) and s.fatal_error) {
                out.deinit(ctx.allocator);
                return null;
            }
            if (s.writepos - s.readpos == 0) break;
        }
    }
    if (out.items.len == 0) {
        out.deinit(ctx.allocator);
        return null;
    }
    return try out.toOwnedSlice(ctx.allocator);
}

fn searchDelim(s: *Stream, maxlen: usize, skiplen: usize, delim: []const u8) ?usize {
    const seek_len = @min(s.writepos - s.readpos, maxlen);
    if (seek_len <= skiplen) return null;
    const hay = s.readbuf[s.readpos..][0..seek_len];
    const at = if (delim.len == 1) std.mem.indexOfScalarPos(u8, hay, skiplen, delim[0]) else std.mem.indexOfPos(u8, hay, skiplen, delim);
    return at;
}

// php_stream_get_record (stream_get_line): up to maxlen bytes or through the
// delimiter, which is consumed but not returned
pub fn getRecord(ctx: *NativeContext, obj: *PhpObject, maxlen: usize, delim: []const u8) RuntimeError!?[]u8 {
    const s = try of(ctx, obj);
    if (maxlen == 0) return null;
    const has_delim = delim.len > 0;
    var found: ?usize = if (has_delim) searchDelim(s, maxlen, 0, delim) else null;
    var buffered_len = s.writepos - s.readpos;
    while (found == null and buffered_len < maxlen) {
        const to_read_now = @min(maxlen - buffered_len, s.chunk_size);
        if (!try fillReadBuffer(ctx, obj, s, buffered_len + to_read_now) and s.fatal_error) return null;
        const just_read = (s.writepos - s.readpos) -| buffered_len;
        if (just_read == 0) break;
        if (has_delim) {
            found = searchDelim(s, maxlen, if (buffered_len >= delim.len - 1) buffered_len - (delim.len - 1) else 0, delim);
            if (found != null) break;
        }
        buffered_len += just_read;
    }
    const amount = s.writepos - s.readpos;
    var tent: usize = undefined;
    if (has_delim and found != null) {
        tent = found.?;
    } else if (!has_delim and amount >= maxlen) {
        tent = maxlen;
    } else {
        if (amount < maxlen and !s.eof) return null;
        if (amount == 0 and s.eof) return null;
        tent = @min(amount, maxlen);
    }
    const out = try ctx.allocator.alloc(u8, tent);
    errdefer ctx.allocator.free(out);
    const got = try read(ctx, obj, out);
    const len: usize = if (got > 0) @intCast(got) else 0;
    if (found != null) {
        s.readpos += delim.len;
        s.position += @intCast(delim.len);
    }
    if (len < tent) return try ctx.allocator.realloc(out, len);
    return out;
}

pub fn eof(ctx: *NativeContext, obj: *PhpObject) RuntimeError!bool {
    const s = try of(ctx, obj);
    if (s.writepos > s.readpos) return false;
    if (!s.eof) {
        if (backend(obj) == .user) {
            if (try user_streams.checkLiveness(ctx, obj, s, fs.fileHandleWrapper(obj).?)) s.eof = true;
        }
    }
    return s.eof;
}

// _php_stream_copy_to_mem: everything up to maxlen (null for all), or null
// when nothing could be read
pub fn copyToMem(ctx: *NativeContext, obj: *PhpObject, maxlen: ?usize) RuntimeError!?[]u8 {
    if (maxlen) |m| if (m == 0) return try ctx.allocator.alloc(u8, 0);
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(ctx.allocator);
    if (maxlen) |m| if (m < 4 * chunk_default) {
        try out.resize(ctx.allocator, m);
        var len: usize = 0;
        while (len < m and !try eof(ctx, obj)) {
            const n = try read(ctx, obj, out.items[len..m]);
            if (n <= 0) break;
            len += @intCast(n);
        }
        if (len == 0) {
            out.deinit(ctx.allocator);
            return null;
        }
        out.shrinkRetainingCapacity(len);
        return try out.toOwnedSlice(ctx.allocator);
    };
    var chunk: [chunk_default]u8 = undefined;
    while (true) {
        const want = if (maxlen) |m| @min(chunk.len, m - out.items.len) else chunk.len;
        if (want == 0) break;
        const n = try read(ctx, obj, chunk[0..want]);
        if (n <= 0) break;
        try out.appendSlice(ctx.allocator, chunk[0..@intCast(n)]);
    }
    if (out.items.len == 0) {
        out.deinit(ctx.allocator);
        return null;
    }
    return try out.toOwnedSlice(ctx.allocator);
}

// --- writing -----------------------------------------------------------------

fn writeBuffer(ctx: *NativeContext, obj: *PhpObject, s: *Stream, data: []const u8) RuntimeError!isize {
    // a seekable stream writes at its logical position: drop what the read
    // buffer holds and move the descriptor back there
    if (hasSeek(obj) and !s.no_seek and s.readpos != s.writepos) {
        s.readpos = 0;
        s.writepos = 0;
        if (try rawSeek(ctx, obj, s, s.position, 0)) |p| s.position = p;
    }
    // user streams take at most a chunk per write
    const chunk = if (backend(obj) == .user) s.chunk_size else data.len;
    var didwrite: usize = 0;
    var rest = data;
    while (rest.len > 0) {
        const n = try rawWrite(ctx, obj, s, rest[0..@min(chunk, rest.len)]);
        if (n <= 0) {
            if (didwrite == 0) return n;
            break;
        }
        const w: usize = @intCast(n);
        rest = rest[w..];
        didwrite += w;
        s.position += n;
    }
    return @intCast(didwrite);
}

fn writeFiltered(ctx: *NativeContext, obj: *PhpObject, s: *Stream, data: ?[]const u8, flags: filters.Flags) RuntimeError!isize {
    var consumed: usize = 0;
    var brig_in: filters.Brigade = .{};
    var brig_out: filters.Brigade = .{};
    if (data) |bytes| try brig_in.append(try filters.Bucket.create(s.allocator, bytes));
    const result = try filters.runChain(ctx, obj, &s.writefilters, s.writefilters.head, &brig_in, &brig_out, &consumed, flags);
    var ret: isize = @intCast(consumed);
    switch (result.status) {
        .pass_on => {
            const out = result.output;
            while (out.head) |bucket| {
                bucket.unlink();
                defer bucket.delref();
                if (try writeBuffer(ctx, obj, s, bucket.bytes()) < 0) ret = -1;
            }
        },
        .err_fatal => {
            ret = -1;
            result.discardOutput();
        },
        .feed_me => result.discardOutput(),
    }
    return ret;
}

// _php_stream_write: bytes written (or consumed by the first write filter),
// -1 on failure
pub fn write(ctx: *NativeContext, obj: *PhpObject, data: []const u8) RuntimeError!isize {
    if (data.len == 0) return 0;
    const s = try of(ctx, obj);
    if (s.no_write_op or backend(obj) == .none) {
        try fs.noticeDocref(ctx, "Stream is not writable", .{});
        return -1;
    }
    const bytes = if (s.writefilters.head != null)
        try writeFiltered(ctx, obj, s, data, .normal)
    else
        try writeBuffer(ctx, obj, s, data);
    if (bytes != 0) s.was_written = true;
    return bytes;
}

pub fn flush(ctx: *NativeContext, obj: *PhpObject, closing: bool) RuntimeError!bool {
    const s = try of(ctx, obj);
    if (s.writefilters.head != null) _ = try writeFiltered(ctx, obj, s, null, if (closing) .flush_close else .flush_inc);
    s.was_written = false;
    return rawFlush(ctx, obj);
}

// --- positioning -------------------------------------------------------------

pub fn tell(ctx: *NativeContext, obj: *PhpObject) RuntimeError!i64 {
    return (try of(ctx, obj)).position;
}

// _php_stream_seek: 0 or -1
pub fn seek(ctx: *NativeContext, obj: *PhpObject, offset_arg: i64, whence_arg: u2) RuntimeError!i32 {
    const s = try of(ctx, obj);
    var offset = offset_arg;
    var whence = whence_arg;
    if (!s.no_buffer) {
        switch (whence) {
            1 => if (offset > 0 and offset <= @as(i64, @intCast(s.writepos - s.readpos))) {
                s.readpos += @intCast(offset);
                s.position += offset;
                s.eof = false;
                s.fatal_error = false;
                return 0;
            },
            0 => if (offset > s.position and offset <= s.position + @as(i64, @intCast(s.writepos - s.readpos))) {
                s.readpos += @intCast(offset - s.position);
                s.position = offset;
                s.eof = false;
                s.fatal_error = false;
                return 0;
            },
            else => {},
        }
    }
    if (hasSeek(obj) and !s.no_seek) {
        if (s.writefilters.head != null) _ = try flush(ctx, obj, false);
        switch (whence) {
            1 => {
                offset = if (offset > std.math.maxInt(i64) - s.position) std.math.maxInt(i64) else s.position + offset;
                whence = 0;
            },
            0 => if (offset < 0) return -1,
            else => {},
        }
        const result = try rawSeek(ctx, obj, s, offset, whence);
        if (result) |p| {
            s.position = p;
            s.eof = false;
            s.fatal_error = false;
        } else if (s.no_seek) {
            // the stream found out it can't seek after all: emulate below
            return emulateSeek(ctx, obj, s, offset_arg, whence_arg);
        }
        s.readpos = 0;
        s.writepos = 0;
        if (result) |p| return if (p < 0) -1 else 0;
        return -1;
    }
    return emulateSeek(ctx, obj, s, offset, whence);
}

fn emulateSeek(ctx: *NativeContext, obj: *PhpObject, s: *Stream, offset_arg: i64, whence: u2) RuntimeError!i32 {
    if (whence == 1 and offset_arg >= 0) {
        var offset = offset_arg;
        var tmp: [1024]u8 = undefined;
        while (offset > 0) {
            const n = try read(ctx, obj, tmp[0..@min(@as(usize, @intCast(offset)), tmp.len)]);
            if (n <= 0) return -1;
            offset -= n;
        }
        s.eof = false;
        s.fatal_error = false;
        return 0;
    }
    try fs.warnDocref(ctx, "Stream does not support seeking", .{});
    return -1;
}

// --- options -----------------------------------------------------------------

pub fn setChunkSize(ctx: *NativeContext, obj: *PhpObject, size: usize) RuntimeError!usize {
    const s = try of(ctx, obj);
    const old = s.chunk_size;
    s.chunk_size = size;
    return old;
}

pub fn setReadBuffer(ctx: *NativeContext, obj: *PhpObject, none: bool) RuntimeError!void {
    const s = try of(ctx, obj);
    s.no_buffer = none;
}

// --- closing -----------------------------------------------------------------

// what php does to a stream before its handle closes: flush what was
// written (through the write filters), then let the filters go
pub fn beforeClose(ctx: *NativeContext, obj: *PhpObject) RuntimeError!void {
    const s = get(obj) orelse return;
    if (s.in_free) return;
    s.in_free = true;
    defer s.in_free = false;
    if (s.was_written or s.writefilters.head != null) _ = try flush(ctx, obj, true);
}

pub fn removeFilters(ctx: *NativeContext, obj: *PhpObject) RuntimeError!void {
    const s = get(obj) orelse return;
    // the wrapper data goes with the stream
    const data = s.wrapperdata;
    s.wrapperdata = .null;
    ctx.vm.releaseValue(data);
    try filters.removeAll(ctx, &s.readfilters);
    try filters.removeAll(ctx, &s.writefilters);
}

// a stream resource freed without fclose: php flushes it, closes the
// handle (a user stream's stream_close) and removes its filters
pub fn destroyed(vm: *VM, obj: *PhpObject) void {
    const s = get(obj) orelse return;
    if (s.in_free) return;
    if (value_mod.resourceClosed(obj)) return;
    var ctx = vm.makeContext(null);
    // the resource is gone already: a filter sees no stream
    obj.set(s.allocator, "__open", .{ .bool = false }) catch {};
    beforeClose(&ctx, obj) catch {};
    s.in_free = true;
    if (fs.fileHandleWrapper(obj)) |w| user_streams.close(&ctx, obj, w) catch {};
    removeFilters(&ctx, obj) catch {};
    s.in_free = false;
}

// php_request_shutdown closes the resources still open, last made first,
// after the destructors and the output buffers
pub fn closeAllAtShutdown(vm: *VM) void {
    var open: std.ArrayListUnmanaged(*PhpObject) = .empty;
    defer open.deinit(vm.allocator);
    for (vm.objects.items) |obj| {
        if (!obj.resource or obj.pooled or obj.native.kind != .stream) continue;
        if (value_mod.resourceClosed(obj)) continue;
        open.append(vm.allocator, obj) catch return;
    }
    std.mem.sort(*PhpObject, open.items, {}, struct {
        fn gt(_: void, a: *PhpObject, b: *PhpObject) bool {
            return a.id > b.id;
        }
    }.gt);
    const saved = fs.docref_fallback;
    fs.docref_fallback = "Unknown";
    at_shutdown = true;
    defer {
        fs.docref_fallback = saved;
        at_shutdown = false;
    }
    for (open.items) |obj| {
        destroyed(vm, obj);
        vm.discardPending();
    }
}
