const std = @import("std");
const parser = @import("pipeline/parser.zig");
const compiler = @import("pipeline/compiler.zig");
const CompileResult = compiler.CompileResult;
const VM = @import("runtime/vm.zig").VM;
const Value = @import("runtime/value.zig").Value;
const PhpArray = @import("runtime/value.zig").PhpArray;
const PhpObject = @import("runtime/value.zig").PhpObject;

const tls = @import("tls.zig");
const h2 = @import("h2.zig");
const env = @import("env.zig");

const Allocator = std.mem.Allocator;
const posix = std.posix;
const zlib = @cImport(@cInclude("zlib.h"));
const ws_proto = @import("websocket.zig");

var signal_pipe: [2]posix.fd_t = .{ -1, -1 };

fn maxPhpMtime(dir_path: []const u8) i128 {
    var max: i128 = 0;
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return 0;
    defer dir.close();
    var walker = dir.walk(std.heap.page_allocator) catch return 0;
    defer walker.deinit();
    while (walker.next() catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".php")) continue;
        if (std.mem.indexOf(u8, entry.path, "vendor/") != null) continue;
        const stat = entry.dir.statFile(entry.basename) catch continue;
        if (stat.mtime > max) max = stat.mtime;
    }
    return max;
}

fn signalHandler(_: c_int) callconv(.c) void {
    _ = posix.write(signal_pipe[1], &[_]u8{1}) catch {};
}

pub const ServeConfig = struct {
    port: u16 = 8080,
    workers: u16 = 0,
    file: []const u8,
    document_root: []const u8 = "",
    tls_cert: ?[]const u8 = null,
    tls_key: ?[]const u8 = null,
    watch: bool = false,
};

const Request = struct {
    method: []const u8 = "GET",
    uri: []const u8 = "/",
    path: []const u8 = "/",
    query_string: []const u8 = "",
    headers: [64]Header = undefined,
    header_count: usize = 0,
    body: []const u8 = "",
    raw: []const u8 = "",

    const Header = struct { name: []const u8, value: []const u8 };

    fn getHeader(self: *const Request, name: []const u8) ?[]const u8 {
        for (self.headers[0..self.header_count]) |h| {
            if (std.ascii.eqlIgnoreCase(h.name, name)) return h.value;
        }
        return null;
    }
};

// connection state machine

const ConnState = enum { tls_handshaking, http_reading, h2_active, ws_idle, closing };

const Connection = struct {
    fd: posix.fd_t,
    stream: std.net.Stream,
    ssl: ?*tls.SSL,
    addr_bytes: u32,
    state: ConnState,
    buf: []u8,
    buffered: usize,
    keep_alive: bool,
    ws_obj: ?*PhpObject,
    h2_session: ?*h2.H2Session,

    fn init(allocator: Allocator, server_conn: std.net.Server.Connection, ssl_ptr: ?*tls.SSL) !Connection {
        return .{
            .fd = server_conn.stream.handle,
            .stream = server_conn.stream,
            .ssl = ssl_ptr,
            .addr_bytes = server_conn.address.in.sa.addr,
            .state = .http_reading,
            .buf = try allocator.alloc(u8, 65536),
            .buffered = 0,
            .keep_alive = true,
            .ws_obj = null,
            .h2_session = null,
        };
    }

    fn ioRead(self: *Connection, buf: []u8) !usize {
        if (self.ssl) |s| return tls.read(s, buf);
        return posix.read(self.fd, buf);
    }

    fn ioWrite(self: *Connection, data: []const u8) !usize {
        if (self.ssl) |s| return tls.write(s, data);
        return self.stream.write(data);
    }

    pub fn write(self: *Connection, data: []const u8) !usize {
        return self.ioWrite(data);
    }

    fn deinit(self: *Connection, allocator: Allocator) void {
        if (self.h2_session) |session| {
            session.deinit();
            allocator.destroy(session);
        }
        if (self.ssl) |s| tls.shutdown(s);
        allocator.free(self.buf);
        self.stream.close();
    }
};

// work queue (shared between main thread and workers)

const WorkItem = struct { conn: std.net.Server.Connection };

fn WorkQueue(comptime capacity: usize) type {
    return struct {
        items: [capacity]WorkItem = undefined,
        head: usize = 0,
        tail: usize = 0,
        count: usize = 0,
        mutex: std.Thread.Mutex = .{},
        not_empty: std.Thread.Condition = .{},
        not_full: std.Thread.Condition = .{},
        shutdown: bool = false,

        const Self = @This();

        fn push(self: *Self, item: WorkItem) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            while (self.count == capacity and !self.shutdown) {
                self.not_full.wait(&self.mutex);
            }
            if (self.shutdown) return;
            self.items[self.tail] = item;
            self.tail = (self.tail + 1) % capacity;
            self.count += 1;
            self.not_empty.signal();
        }

        fn tryPop(self: *Self) ?WorkItem {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (self.count == 0) return null;
            const item = self.items[self.head];
            self.head = (self.head + 1) % capacity;
            self.count -= 1;
            self.not_full.signal();
            return item;
        }

        fn close(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.shutdown = true;
            self.not_empty.broadcast();
            self.not_full.broadcast();
        }

        fn reset(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.shutdown = false;
            self.head = 0;
            self.tail = 0;
            self.count = 0;
        }
    };
}

var queue: WorkQueue(1024) = .{};

// worker state

const MAX_CONNS = 1024;

const Worker = struct {
    allocator: Allocator,
    result: *const CompileResult,
    vm: VM,
    doc_root: []const u8,
    port: u16,
    ws_enabled: bool,
    ws_initialized: bool,
    tls_ctx: ?*tls.SSL_CTX,
    wake_pipe: [2]posix.fd_t,
    poll_fds: [MAX_CONNS + 1]posix.pollfd,
    conns: [MAX_CONNS + 1]?Connection,
    n_fds: usize,
};

fn loadFile(path: []const u8, allocator: Allocator) ?*CompileResult {
    const abs_path = std.fs.cwd().realpathAlloc(allocator, path) catch allocator.dupe(u8, path) catch return null;
    const source = std.fs.cwd().readFileAlloc(allocator, abs_path, 1024 * 1024 * 10) catch {
        allocator.free(abs_path);
        return null;
    };

    var ast = parser.parse(allocator, source) catch {
        allocator.free(source);
        allocator.free(abs_path);
        return null;
    };

    if (ast.errors.len > 0) {
        ast.deinit();
        allocator.free(source);
        allocator.free(abs_path);
        return null;
    }

    var result = compiler.compileWithPath(&ast, allocator, abs_path) catch {
        ast.deinit();
        allocator.free(source);
        allocator.free(abs_path);
        return null;
    };

    const heap_result = allocator.create(CompileResult) catch {
        result.deinit();
        ast.deinit();
        allocator.free(source);
        return null;
    };
    heap_result.* = result;
    ast.deinit();

    heap_result.string_allocs.append(allocator, source) catch {
        allocator.free(source);
        allocator.free(abs_path);
        heap_result.deinit();
        allocator.destroy(heap_result);
        return null;
    };
    heap_result.string_allocs.append(allocator, abs_path) catch {
        allocator.free(abs_path);
        heap_result.deinit();
        allocator.destroy(heap_result);
        return null;
    };

    return heap_result;
}

fn initWorker(allocator: Allocator, result: *const CompileResult, doc_root: []const u8, port: u16, ws_enabled: bool, tls_ctx: ?*tls.SSL_CTX) !Worker {
    var vm = try VM.init(allocator);
    vm.file_loader = &loadFile;
    return .{
        .allocator = allocator,
        .result = result,
        .vm = vm,
        .doc_root = doc_root,
        .port = port,
        .ws_enabled = ws_enabled,
        .ws_initialized = false,
        .tls_ctx = tls_ctx,
        .wake_pipe = try posix.pipe(),
        .poll_fds = [_]posix.pollfd{.{ .fd = -1, .events = 0, .revents = 0 }} ** (MAX_CONNS + 1),
        .conns = [_]?Connection{null} ** (MAX_CONNS + 1),
        .n_fds = 1,
    };
}

fn deinitWorker(w: *Worker) void {
    var i: usize = 1;
    while (i < w.n_fds) : (i += 1) {
        if (w.conns[i]) |*conn| {
            if (conn.h2_session) |session| session.submitGoaway();
            conn.deinit(w.allocator);
        }
    }
    posix.close(w.wake_pipe[0]);
    posix.close(w.wake_pipe[1]);
    w.vm.deinit();
}

fn setNonBlocking(fd: posix.fd_t) void {
    const O_NONBLOCK: u32 = if (@import("builtin").os.tag == .linux) 0x800 else 0x4;
    const flags = posix.fcntl(fd, 3, 0) catch return;
    _ = posix.fcntl(fd, 4, flags | O_NONBLOCK) catch return;
}

fn certMtime(path: []const u8) i128 {
    const f = std.fs.cwd().openFile(path, .{}) catch return 0;
    defer f.close();
    const stat = f.stat() catch return 0;
    return stat.mtime;
}

// main serve entry point

pub fn serve(allocator: Allocator, config: ServeConfig) !void {
    env.loadEnvFile(allocator);

    const worker_count: usize = if (config.workers > 0)
        config.workers
    else blk: {
        const cpus = std.Thread.getCpuCount() catch 4;
        break :blk @max(cpus, 1);
    };

    signal_pipe = try posix.pipe();
    defer {
        posix.close(signal_pipe[0]);
        posix.close(signal_pipe[1]);
    }

    var sa: posix.Sigaction = .{
        .handler = .{ .handler = signalHandler },
        .mask = posix.sigemptyset(),
        .flags = 0,
    };
    posix.sigaction(posix.SIG.INT, &sa, null);
    posix.sigaction(posix.SIG.TERM, &sa, null);

    var tls_ctx: ?*tls.SSL_CTX = null;
    var tls_cert_z: ?[:0]u8 = null;
    var tls_key_z: ?[:0]u8 = null;
    var tls_cert_mtime: i128 = 0;
    if (config.tls_cert) |cert| {
        const key = config.tls_key orelse {
            try writeStderr("error: --tls-key required when --tls-cert is specified\n");
            std.process.exit(1);
        };
        tls_cert_z = try allocator.dupeZ(u8, cert);
        tls_key_z = try allocator.dupeZ(u8, key);
        tls_ctx = tls.initContext(tls_cert_z.?, tls_key_z.?) orelse {
            try writeStderr("error: failed to initialize TLS (check cert/key paths)\n");
            std.process.exit(1);
        };
        tls_cert_mtime = certMtime(cert);
    }
    defer {
        if (tls_cert_z) |z| allocator.free(z);
        if (tls_key_z) |z| allocator.free(z);
    }

    const addr = std.net.Address.parseIp4("0.0.0.0", config.port) catch unreachable;
    var server = try addr.listen(.{ .reuse_address = true });
    defer server.deinit();

    const abs_path = std.fs.cwd().realpathAlloc(allocator, config.file) catch
        try allocator.dupe(u8, config.file);
    defer allocator.free(abs_path);

    const doc_root = if (config.document_root.len > 0)
        try allocator.dupe(u8, config.document_root)
    else blk: {
        if (std.fs.path.dirname(abs_path)) |dir| {
            break :blk try allocator.dupe(u8, dir);
        }
        break :blk try allocator.dupe(u8, ".");
    };
    defer allocator.free(doc_root);

    const workers_data = try allocator.alloc(Worker, worker_count);
    defer allocator.free(workers_data);
    const threads = try allocator.alloc(std.Thread, worker_count);
    defer allocator.free(threads);

    setNonBlocking(server.stream.handle);

    var watch_mtime: i128 = if (config.watch) maxPhpMtime(doc_root) else 0;
    var first_run = true;

    while (true) {
        const source = std.fs.cwd().readFileAlloc(allocator, config.file, 1024 * 1024 * 10) catch |err| {
            try writeStderr("error: could not read '");
            try writeStderr(config.file);
            try writeStderr("'\n");
            return err;
        };

        var ast = parser.parse(allocator, source) catch {
            allocator.free(source);
            if (config.watch) {
                try writeStderr("parse error, waiting for fix...\n");
                std.Thread.sleep(1_000_000_000);
                continue;
            }
            std.process.exit(1);
        };

        if (ast.errors.len > 0) {
            ast.deinit();
            allocator.free(source);
            if (config.watch) {
                try writeStderr("parse error, waiting for fix...\n");
                std.Thread.sleep(1_000_000_000);
                continue;
            }
            try writeStderr("parse error in ");
            try writeStderr(config.file);
            try writeStderr("\n");
            std.process.exit(1);
        }

        var result = compiler.compileWithPath(&ast, allocator, abs_path) catch {
            ast.deinit();
            allocator.free(source);
            if (config.watch) {
                try writeStderr("compile error, waiting for fix...\n");
                std.Thread.sleep(1_000_000_000);
                continue;
            }
            try writeStderr("compile error\n");
            std.process.exit(1);
        };

        const ws_enabled = blk: {
            for (result.functions.items) |*f| {
                if (std.mem.eql(u8, f.name, "ws_onMessage")) break :blk true;
            }
            break :blk false;
        };

        if (first_run) {
            var port_buf: [8]u8 = undefined;
            const port_str = std.fmt.bufPrint(&port_buf, "{d}", .{config.port}) catch "?";
            try writeStderr("zphp serving ");
            try writeStderr(config.file);
            if (tls_ctx != null) try writeStderr(" (https) on :") else try writeStderr(" on :");
            try writeStderr(port_str);
            try writeStderr(" (");
            var wc_buf: [8]u8 = undefined;
            const wc_str = std.fmt.bufPrint(&wc_buf, "{d}", .{worker_count}) catch "?";
            try writeStderr(wc_str);
            try writeStderr(" workers");
            if (config.watch) try writeStderr(", watch");
            try writeStderr(")\n");
            first_run = false;
        }

        queue.reset();
        for (workers_data, threads) |*wd, *t| {
            wd.* = initWorker(allocator, &result, doc_root, config.port, ws_enabled, tls_ctx) catch continue;
            wd.poll_fds[0] = .{ .fd = wd.wake_pipe[0], .events = posix.POLL.IN, .revents = 0 };
            t.* = try std.Thread.spawn(.{}, eventLoop, .{wd});
        }

        var main_poll: [2]posix.pollfd = .{
            .{ .fd = server.stream.handle, .events = posix.POLL.IN, .revents = 0 },
            .{ .fd = signal_pipe[0], .events = posix.POLL.IN, .revents = 0 },
        };

        const poll_timeout: i32 = if (config.watch or tls_ctx != null) 1000 else -1;
        var robin: usize = 0;
        var needs_restart = false;
        while (true) {
            _ = posix.poll(&main_poll, poll_timeout) catch continue;

            if (main_poll[1].revents & posix.POLL.IN != 0) {
                try writeStderr("\nshutting down...\n");
                break;
            }

            if (main_poll[0].revents & posix.POLL.IN != 0) {
                const conn = server.accept() catch continue;
                queue.push(.{ .conn = conn });
                _ = posix.write(workers_data[robin].wake_pipe[1], &[_]u8{1}) catch {};
                robin = (robin + 1) % worker_count;
            }

            if (tls_cert_z != null and tls_key_z != null) {
                const new_mtime = certMtime(config.tls_cert.?);
                if (new_mtime != tls_cert_mtime and new_mtime != 0) {
                    if (tls.initContext(tls_cert_z.?, tls_key_z.?)) |new_ctx| {
                        tls_ctx = new_ctx;
                        tls_cert_mtime = new_mtime;
                        for (workers_data) |*wd| wd.tls_ctx = new_ctx;
                        try writeStderr("tls: certificate reloaded\n");
                    }
                }
            }

            if (config.watch) {
                const new_mtime = maxPhpMtime(doc_root);
                if (new_mtime != watch_mtime and new_mtime != 0) {
                    watch_mtime = new_mtime;
                    needs_restart = true;
                    try writeStderr("file change detected, reloading...\n");
                    break;
                }
            }
        }

        queue.close();
        for (workers_data) |*wd| {
            _ = posix.write(wd.wake_pipe[1], &[_]u8{1}) catch {};
        }
        for (threads) |t| t.join();
        for (workers_data) |*wd| deinitWorker(wd);

        result.deinit();
        ast.deinit();
        allocator.free(source);

        if (!needs_restart) break;
    }
}

// event loop (runs on each worker thread)

fn eventLoop(w: *Worker) void {
    while (!queue.shutdown) {
        _ = posix.poll(w.poll_fds[0..w.n_fds], 1000) catch continue;

        // check wake pipe
        if (w.poll_fds[0].revents & posix.POLL.IN != 0) {
            var drain: [64]u8 = undefined;
            _ = posix.read(w.wake_pipe[0], &drain) catch {};
            while (queue.tryPop()) |item| {
                registerConnection(w, item.conn);
            }
        }

        // process ready connections
        var i: usize = 1;
        while (i < w.n_fds) : (i += 1) {
            const revents = w.poll_fds[i].revents;
            if (revents == 0) continue;

            if (revents & (posix.POLL.ERR | posix.POLL.HUP) != 0) {
                if (w.conns[i]) |*c| c.state = .closing;
                continue;
            }

            if (revents & (posix.POLL.IN | posix.POLL.OUT) != 0) {
                if (w.conns[i]) |*c| {
                    switch (c.state) {
                        .tls_handshaking => processTlsHandshake(w, c, i),
                        .http_reading => processHttpRead(w, c),
                        .h2_active => processH2Read(w, c),
                        .ws_idle => processWsRead(w, c),
                        .closing => {},
                    }
                }
            }
        }

        compactConnections(w);
    }
}

fn registerConnection(w: *Worker, server_conn: std.net.Server.Connection) void {
    if (w.n_fds >= MAX_CONNS + 1) {
        server_conn.stream.close();
        return;
    }
    setNonBlocking(server_conn.stream.handle);
    var ssl_ptr: ?*tls.SSL = null;
    var initial_state: ConnState = .http_reading;
    var poll_events: i16 = posix.POLL.IN;
    if (w.tls_ctx) |ctx| {
        ssl_ptr = tls.beginAccept(ctx, server_conn.stream.handle) orelse {
            server_conn.stream.close();
            return;
        };
        switch (tls.continueAccept(ssl_ptr.?)) {
            .complete => {},
            .want_read => {
                initial_state = .tls_handshaking;
                poll_events = posix.POLL.IN;
            },
            .want_write => {
                initial_state = .tls_handshaking;
                poll_events = posix.POLL.OUT;
            },
            .failed => {
                tls.shutdown(ssl_ptr.?);
                server_conn.stream.close();
                return;
            },
        }
    }
    var c = Connection.init(w.allocator, server_conn, ssl_ptr) catch {
        if (ssl_ptr) |s| tls.shutdown(s);
        server_conn.stream.close();
        return;
    };
    c.state = initial_state;
    const slot = w.n_fds;
    w.poll_fds[slot] = .{ .fd = c.fd, .events = poll_events, .revents = 0 };
    w.conns[slot] = c;
    w.n_fds += 1;
}

fn compactConnections(w: *Worker) void {
    var i: usize = 1;
    while (i < w.n_fds) {
        if (w.conns[i]) |*c| {
            if (c.state == .closing) {
                if (c.ws_obj) |ws_obj| {
                    ws_obj.set(w.allocator, "__ws_closed", .{ .bool = true }) catch {};
                    ws_obj.set(w.allocator, "__ws_ssl", .{ .int = 0 }) catch {};
                    if (w.vm.functions.contains("ws_onClose")) {
                        _ = w.vm.callByName("ws_onClose", &.{Value{ .object = ws_obj }}) catch {};
                    }
                }
                if (c.h2_session) |session| session.submitGoaway();
                c.deinit(w.allocator);
                const last = w.n_fds - 1;
                if (i != last) {
                    w.poll_fds[i] = w.poll_fds[last];
                    w.conns[i] = w.conns[last];
                }
                w.conns[last] = null;
                w.poll_fds[last] = .{ .fd = -1, .events = 0, .revents = 0 };
                w.n_fds -= 1;
                continue;
            }
        }
        i += 1;
    }
}

fn shiftBuffer(c: *Connection, consumed: usize) void {
    if (consumed < c.buffered) {
        std.mem.copyForwards(u8, c.buf[0 .. c.buffered - consumed], c.buf[consumed..c.buffered]);
        c.buffered -= consumed;
    } else {
        c.buffered = 0;
    }
}

const ChunkedResult = struct { body_len: usize, raw_len: usize };

fn decodeChunkedBody(data: []u8) ?ChunkedResult {
    var read_pos: usize = 0;
    var write_pos: usize = 0;

    while (read_pos < data.len) {
        const size_end = std.mem.indexOfPos(u8, data, read_pos, "\r\n") orelse return null;
        const size_str = data[read_pos..size_end];
        const chunk_len = std.fmt.parseInt(usize, size_str, 16) catch return null;

        if (chunk_len == 0) {
            const final_end = size_end + 2;
            if (final_end + 2 > data.len) return null;
            return .{ .body_len = write_pos, .raw_len = final_end + 2 };
        }

        const chunk_start = size_end + 2;
        const chunk_end = chunk_start + chunk_len;
        if (chunk_end + 2 > data.len) return null;

        std.mem.copyForwards(u8, data[write_pos .. write_pos + chunk_len], data[chunk_start..chunk_end]);
        write_pos += chunk_len;
        read_pos = chunk_end + 2;
    }

    return null;
}

// TLS handshake continuation

fn processTlsHandshake(w: *Worker, conn: *Connection, poll_idx: usize) void {
    const ssl = conn.ssl orelse {
        conn.state = .closing;
        return;
    };
    switch (tls.continueAccept(ssl)) {
        .complete => {
            if (tls.getAlpnProtocol(ssl) == .h2) {
                const session = w.allocator.create(h2.H2Session) catch {
                    conn.state = .closing;
                    return;
                };
                session.initSession(w.allocator, ssl, conn.fd) catch {
                    w.allocator.destroy(session);
                    conn.state = .closing;
                    return;
                };
                conn.h2_session = session;
                conn.state = .h2_active;
                session.flush() catch {
                    conn.state = .closing;
                };
            } else {
                conn.state = .http_reading;
            }
            w.poll_fds[poll_idx].events = posix.POLL.IN;
        },
        .want_read => w.poll_fds[poll_idx].events = posix.POLL.IN,
        .want_write => w.poll_fds[poll_idx].events = posix.POLL.OUT,
        .failed => conn.state = .closing,
    }
}

// HTTP processing

fn processHttpRead(w: *Worker, c: *Connection) void {
    const n = c.ioRead(c.buf[c.buffered..]) catch |err| {
        if (err == error.WouldBlock) return;
        c.state = .closing;
        return;
    };
    if (n == 0) { c.state = .closing; return; }
    c.buffered += n;

    const raw = c.buf[0..c.buffered];
    const hdr_end_pos = std.mem.indexOf(u8, raw, "\r\n\r\n") orelse return;
    const header_end = hdr_end_pos + 4;

    var req = parseRequest(raw);

    const is_chunked = blk: {
        const te = req.getHeader("Transfer-Encoding") orelse break :blk false;
        break :blk std.mem.indexOf(u8, te, "chunked") != null;
    };

    var body_len: usize = 0;
    var consumed: usize = undefined;

    if (is_chunked) {
        const body_start = raw[header_end..c.buffered];
        const decoded_len = decodeChunkedBody(body_start) orelse return;
        body_len = decoded_len.body_len;
        consumed = header_end + decoded_len.raw_len;
        req.body = raw[header_end .. header_end + body_len];
    } else {
        if (req.getHeader("Content-Length")) |cl| {
            body_len = std.fmt.parseInt(usize, cl, 10) catch 0;
        }
        consumed = header_end + body_len;
        if (c.buffered < consumed) return;
    }

    const conn_hdr = req.getHeader("Connection");
    c.keep_alive = if (conn_hdr) |h| !std.ascii.eqlIgnoreCase(h, "close") else true;

    // websocket upgrade
    if (w.ws_enabled) {
        const upgrade_hdr = req.getHeader("Upgrade");
        if (upgrade_hdr != null and std.ascii.eqlIgnoreCase(upgrade_hdr.?, "websocket")) {
            const ws_key = req.getHeader("Sec-WebSocket-Key") orelse {
                c.state = .closing;
                return;
            };
            handleWsUpgrade(w, c, ws_key);
            shiftBuffer(c, consumed);
            return;
        }
    }

    // static file
    if (tryServeStatic(w.allocator, c, w.doc_root, &req, c.keep_alive)) {
        shiftBuffer(c, consumed);
        if (!c.keep_alive) c.state = .closing;
        return;
    }

    // PHP execution
    w.vm.reset();
    const mock_conn = std.net.Server.Connection{
        .stream = c.stream,
        .address = std.net.Address{ .in = .{ .sa = .{ .port = 0, .addr = c.addr_bytes, .zero = [_]u8{0} ** 8 } } },
    };
    populateSuperglobals(&w.vm, &req, mock_conn, w.port) catch {
        c.state = .closing;
        return;
    };

    w.vm.interpret(w.result) catch {
        writeResponse(c, 500, "text/plain", null, "500 Internal Server Error", c.keep_alive, false, w.allocator) catch {};
        shiftBuffer(c, consumed);
        if (!c.keep_alive) c.state = .closing;
        return;
    };

    // persist session data if session was started
    var session_ctx = w.vm.makeContext(null);
    @import("stdlib/session.zig").finalizeSession(&session_ctx);

    const ct: []const u8 = if (w.vm.frame_count > 0) blk: {
        const v = w.vm.frames[0].vars.get("__response_content_type") orelse break :blk "text/html";
        break :blk if (v == .string) v.string else "text/html";
    } else "text/html";
    const code: i64 = if (w.vm.frame_count > 0) blk: {
        const v = w.vm.frames[0].vars.get("__response_code") orelse break :blk @as(i64, 200);
        break :blk if (v == .int) v.int else 200;
    } else 200;
    const extra_headers: ?*PhpArray = if (w.vm.frame_count > 0) blk: {
        const v = w.vm.frames[0].vars.get("__response_headers") orelse break :blk null;
        break :blk if (v == .array) v.array else null;
    } else null;

    writeResponse(c, code, ct, extra_headers, w.vm.output.items, c.keep_alive, acceptsGzip(&req), w.allocator) catch {};
    shiftBuffer(c, consumed);
    if (!c.keep_alive) c.state = .closing;
}

// HTTP/2 processing

fn processH2Read(w: *Worker, conn: *Connection) void {
    const session = conn.h2_session orelse {
        conn.state = .closing;
        return;
    };

    session.flushBuffered() catch {
        conn.state = .closing;
        return;
    };

    const n = conn.ioRead(conn.buf[conn.buffered..]) catch |err| {
        if (err == error.WouldBlock) return;
        conn.state = .closing;
        return;
    };
    if (n == 0) { conn.state = .closing; return; }
    conn.buffered += n;

    const consumed = session.recv(conn.buf[0..conn.buffered]);
    if (consumed < 0) { conn.state = .closing; return; }
    const uconsumed: usize = @intCast(consumed);
    if (uconsumed > 0) shiftBuffer(conn, uconsumed);

    while (session.findCompletedStream()) |stream| {
        handleH2Request(w, conn, session, stream);
    }

    session.flush() catch { conn.state = .closing; };
}

fn handleH2Request(w: *Worker, conn: *Connection, session: *h2.H2Session, stream: *h2.H2Stream) void {
    const stream_id = stream.stream_id;

    // build Request from h2 stream
    var req = Request{
        .method = stream.method,
        .uri = stream.path,
        .path = stream.path,
        .query_string = "",
    };
    if (std.mem.indexOf(u8, stream.path, "?")) |q| {
        req.path = stream.path[0..q];
        req.query_string = stream.path[q + 1 ..];
    }
    for (stream.headers[0..stream.header_count], 0..) |hdr, i| {
        if (i < 64) {
            req.headers[i] = .{ .name = hdr.name, .value = hdr.value };
        }
    }
    req.header_count = stream.header_count;
    req.body = stream.body.items;

    // try static file
    if (w.doc_root.len > 0 and tryServeStaticH2(w.allocator, session, stream_id, w.doc_root, &req)) {
        stream.resetRequest(w.allocator);
        return;
    }

    // PHP execution
    w.vm.reset();
    const mock_conn = std.net.Server.Connection{
        .stream = conn.stream,
        .address = std.net.Address{ .in = .{ .sa = .{ .port = 0, .addr = conn.addr_bytes, .zero = [_]u8{0} ** 8 } } },
    };
    populateSuperglobals(&w.vm, &req, mock_conn, w.port) catch {
        session.submitResponse(stream_id, 500, "text/plain", "Internal Server Error");
        stream.resetRequest(w.allocator);
        return;
    };
    // override SERVER_PROTOCOL for h2
    if (w.vm.request_vars.get("$_SERVER")) |sv| {
        if (sv == .array) sv.array.set(w.allocator, .{ .string = "SERVER_PROTOCOL" }, .{ .string = "HTTP/2.0" }) catch {};
    }
    // set Host from :authority if not already set by header
    if (stream.authority.len > 0) {
        if (w.vm.request_vars.get("$_SERVER")) |sv| {
            if (sv == .array) sv.array.set(w.allocator, .{ .string = "HTTP_HOST" }, .{ .string = stream.authority }) catch {};
        }
    }

    w.vm.interpret(w.result) catch {
        session.submitResponse(stream_id, 500, "text/plain", "Internal Server Error");
        stream.resetRequest(w.allocator);
        return;
    };

    var session_ctx = w.vm.makeContext(null);
    @import("stdlib/session.zig").finalizeSession(&session_ctx);

    const ct: []const u8 = if (w.vm.frame_count > 0) blk: {
        const v = w.vm.frames[0].vars.get("__response_content_type") orelse break :blk "text/html";
        break :blk if (v == .string) v.string else "text/html";
    } else "text/html";
    const code: u16 = if (w.vm.frame_count > 0) blk: {
        const v = w.vm.frames[0].vars.get("__response_code") orelse break :blk @as(u16, 200);
        break :blk if (v == .int) std.math.cast(u16, v.int) orelse 200 else 200;
    } else 200;

    session.submitResponse(stream_id, code, ct, w.vm.output.items);
    stream.resetRequest(w.allocator);
}

fn tryServeStaticH2(allocator: Allocator, session: *h2.H2Session, stream_id: i32, doc_root: []const u8, req: *const Request) bool {
    const path = req.path;
    if (std.mem.endsWith(u8, path, ".php")) return false;
    if (path.len <= 1) return false;
    const rel = if (path[0] == '/') path[1..] else path;
    if (rel.len == 0) return false;
    if (std.mem.indexOf(u8, rel, "..") != null) return false;

    const file_path = std.fs.path.join(allocator, &.{ doc_root, rel }) catch return false;
    defer allocator.free(file_path);
    const file = std.fs.cwd().openFile(file_path, .{}) catch return false;
    defer file.close();
    const stat = file.stat() catch return false;
    if (stat.kind != .file) return false;

    const size: usize = @intCast(stat.size);
    if (size > 10 * 1024 * 1024) return false;

    const body = allocator.alloc(u8, size) catch return false;
    defer allocator.free(body);
    const bytes_read = file.readAll(body) catch return false;

    const mime = mimeType(rel);
    session.submitResponse(stream_id, 200, mime, body[0..bytes_read]);
    return true;
}

// WebSocket processing

fn handleWsUpgrade(w: *Worker, c: *Connection, ws_key: []const u8) void {
    var accept_buf: [28]u8 = undefined;
    const accept = ws_proto.computeAcceptKey(ws_key, &accept_buf);
    ws_proto.writeHandshakeResponse(c, accept) catch {
        c.state = .closing;
        return;
    };

    if (!w.ws_initialized) {
        w.vm.reset();
        w.vm.interpret(w.result) catch {
            c.state = .closing;
            return;
        };
        w.ws_initialized = true;
    }

    const ws_obj = w.allocator.create(PhpObject) catch {
        c.state = .closing;
        return;
    };
    ws_obj.* = .{ .class_name = "WebSocketConnection" };
    ws_obj.set(w.allocator, "__ws_fd", .{ .int = @intCast(c.fd) }) catch {
        c.state = .closing;
        return;
    };
    ws_obj.set(w.allocator, "__ws_ssl", .{ .int = if (c.ssl) |s| @intCast(@intFromPtr(s)) else @as(i64, 0) }) catch {
        c.state = .closing;
        return;
    };
    ws_obj.set(w.allocator, "__ws_closed", .{ .bool = false }) catch {
        c.state = .closing;
        return;
    };
    w.vm.objects.append(w.allocator, ws_obj) catch {
        c.state = .closing;
        return;
    };
    c.ws_obj = ws_obj;
    c.state = .ws_idle;
    c.buffered = 0;

    if (w.vm.functions.contains("ws_onOpen")) {
        _ = w.vm.callByName("ws_onOpen", &.{Value{ .object = ws_obj }}) catch {};
    }
}

fn processWsRead(w: *Worker, c: *Connection) void {
    const max_msg_size: usize = 1024 * 1024;

    const n = c.ioRead(c.buf[c.buffered..]) catch |err| {
        if (err == error.WouldBlock) return;
        c.state = .closing;
        return;
    };
    if (n == 0) { c.state = .closing; return; }
    c.buffered += n;

    // parse all complete frames from buffer, defer shift to end
    var consumed_total: usize = 0;
    while (true) {
        const remaining = c.buf[consumed_total..c.buffered];
        const parsed = ws_proto.tryParseFrame(remaining, max_msg_size) orelse break;

        switch (parsed.frame.opcode) {
            .text, .binary => {
                const data = w.allocator.dupe(u8, parsed.frame.payload) catch break;
                w.vm.strings.append(w.allocator, data) catch {
                    w.allocator.free(data);
                    break;
                };
                const ws_val = Value{ .object = c.ws_obj.? };
                _ = w.vm.callByName("ws_onMessage", &.{ ws_val, Value{ .string = data } }) catch {};
            },
            .ping => {
                ws_proto.writeFrame(c, .pong, parsed.frame.payload) catch {
                    c.state = .closing;
                    break;
                };
            },
            .close => {
                ws_proto.writeCloseFrame(c, 1000) catch {};
                c.state = .closing;
                break;
            },
            .pong, .continuation => {},
            _ => {
                c.state = .closing;
                break;
            },
        }

        consumed_total += parsed.consumed;
    }

    if (consumed_total > 0) shiftBuffer(c, consumed_total);
}

// unchanged helper functions below

fn parseRequest(raw: []const u8) Request {
    var req = Request{ .raw = raw };
    const line_end = std.mem.indexOf(u8, raw, "\r\n") orelse raw.len;
    const line = raw[0..line_end];
    const method_end = std.mem.indexOf(u8, line, " ") orelse return req;
    req.method = line[0..method_end];
    const uri_start = method_end + 1;
    const uri_end = std.mem.indexOfPos(u8, line, uri_start, " ") orelse line.len;
    req.uri = line[uri_start..uri_end];
    if (std.mem.indexOf(u8, req.uri, "?")) |q| {
        req.path = req.uri[0..q];
        req.query_string = req.uri[q + 1 ..];
    } else {
        req.path = req.uri;
    }
    var pos = line_end + 2;
    while (pos < raw.len) {
        const hdr_end = std.mem.indexOfPos(u8, raw, pos, "\r\n") orelse break;
        if (hdr_end == pos) { pos = hdr_end + 2; break; }
        const hdr_line = raw[pos..hdr_end];
        if (std.mem.indexOf(u8, hdr_line, ": ")) |sep| {
            if (req.header_count < 64) {
                req.headers[req.header_count] = .{ .name = hdr_line[0..sep], .value = hdr_line[sep + 2 ..] };
                req.header_count += 1;
            }
        }
        pos = hdr_end + 2;
    }
    if (pos < raw.len) req.body = raw[pos..];
    return req;
}

fn populateSuperglobals(vm: *VM, req: *const Request, conn: std.net.Server.Connection, port: u16) !void {
    const a = vm.allocator;
    const server_arr = try a.create(PhpArray);
    server_arr.* = .{};
    try vm.arrays.append(a, server_arr);

    try server_arr.set(a, .{ .string = "REQUEST_METHOD" }, .{ .string = req.method });
    try server_arr.set(a, .{ .string = "REQUEST_URI" }, .{ .string = req.uri });
    try server_arr.set(a, .{ .string = "QUERY_STRING" }, .{ .string = req.query_string });
    try server_arr.set(a, .{ .string = "SERVER_PROTOCOL" }, .{ .string = "HTTP/1.1" });
    var port_buf: [8]u8 = undefined;
    const port_str = std.fmt.bufPrint(&port_buf, "{d}", .{port}) catch "8080";
    try server_arr.set(a, .{ .string = "SERVER_PORT" }, .{ .string = port_str });
    try server_arr.set(a, .{ .string = "SCRIPT_NAME" }, .{ .string = req.path });
    try server_arr.set(a, .{ .string = "PATH_INFO" }, .{ .string = req.path });

    if (req.getHeader("Host")) |host| try server_arr.set(a, .{ .string = "HTTP_HOST" }, .{ .string = host });
    if (req.getHeader("User-Agent")) |ua| try server_arr.set(a, .{ .string = "HTTP_USER_AGENT" }, .{ .string = ua });
    if (req.getHeader("Content-Type")) |ct| try server_arr.set(a, .{ .string = "CONTENT_TYPE" }, .{ .string = ct });
    if (req.getHeader("Content-Length")) |cl| try server_arr.set(a, .{ .string = "CONTENT_LENGTH" }, .{ .string = cl });

    const addr_bytes = conn.address.in.sa.addr;
    var addr_buf: [16]u8 = undefined;
    const addr_str = std.fmt.bufPrint(&addr_buf, "{d}.{d}.{d}.{d}", .{
        @as(u8, @truncate(addr_bytes)),
        @as(u8, @truncate(addr_bytes >> 8)),
        @as(u8, @truncate(addr_bytes >> 16)),
        @as(u8, @truncate(addr_bytes >> 24)),
    }) catch "0.0.0.0";
    const addr_owned = try a.dupe(u8, addr_str);
    try vm.strings.append(a, addr_owned);
    try server_arr.set(a, .{ .string = "REMOTE_ADDR" }, .{ .string = addr_owned });

    try vm.request_vars.put(a, "$_SERVER", .{ .array = server_arr });

    const get_arr = try a.create(PhpArray);
    get_arr.* = .{};
    try vm.arrays.append(a, get_arr);
    parseQueryString(a, vm, get_arr, req.query_string) catch {};
    try vm.request_vars.put(a, "$_GET", .{ .array = get_arr });

    const post_arr = try a.create(PhpArray);
    post_arr.* = .{};
    try vm.arrays.append(a, post_arr);

    const files_arr = try a.create(PhpArray);
    files_arr.* = .{};
    try vm.arrays.append(a, files_arr);

    if (req.getHeader("Content-Type")) |ct| {
        if (std.mem.startsWith(u8, ct, "application/x-www-form-urlencoded")) {
            parseQueryString(a, vm, post_arr, req.body) catch {};
        } else if (std.mem.startsWith(u8, ct, "multipart/form-data")) {
            if (extractBoundary(ct)) |boundary| {
                parseMultipart(a, vm, req.body, boundary, post_arr, files_arr) catch {};
            }
        }
    }
    try vm.request_vars.put(a, "$_POST", .{ .array = post_arr });
    try vm.request_vars.put(a, "$_FILES", .{ .array = files_arr });

    const request_arr = try a.create(PhpArray);
    request_arr.* = .{};
    try vm.arrays.append(a, request_arr);
    for (get_arr.entries.items) |entry| try request_arr.set(a, entry.key, entry.value);
    for (post_arr.entries.items) |entry| try request_arr.set(a, entry.key, entry.value);
    try vm.request_vars.put(a, "$_REQUEST", .{ .array = request_arr });

    const cookie_arr = try a.create(PhpArray);
    cookie_arr.* = .{};
    try vm.arrays.append(a, cookie_arr);
    if (req.getHeader("Cookie")) |cookies| parseCookies(a, vm, cookie_arr, cookies) catch {};
    try vm.request_vars.put(a, "$_COOKIE", .{ .array = cookie_arr });

    try env.populateEnvSuperglobal(vm, a);

    // raw body for php://input
    if (req.body.len > 0) {
        const body_copy = try a.dupe(u8, req.body);
        try vm.strings.append(a, body_copy);
        try vm.request_vars.put(a, "__raw_body", .{ .string = body_copy });
    }
}

fn parseQueryString(a: Allocator, vm: *VM, arr: *PhpArray, qs: []const u8) !void {
    if (qs.len == 0) return;
    var iter = std.mem.splitScalar(u8, qs, '&');
    while (iter.next()) |pair| {
        if (pair.len == 0) continue;
        if (std.mem.indexOf(u8, pair, "=")) |eq| {
            const key = try urlDecode(a, pair[0..eq]);
            try vm.strings.append(a, key);
            const val = try urlDecode(a, pair[eq + 1 ..]);
            try vm.strings.append(a, val);
            try arr.set(a, .{ .string = key }, .{ .string = val });
        } else {
            const key = try urlDecode(a, pair);
            try vm.strings.append(a, key);
            try arr.set(a, .{ .string = key }, .{ .string = "" });
        }
    }
}

fn parseCookies(a: Allocator, vm: *VM, arr: *PhpArray, cookies: []const u8) !void {
    var iter = std.mem.splitSequence(u8, cookies, "; ");
    while (iter.next()) |pair| {
        if (std.mem.indexOf(u8, pair, "=")) |eq| {
            const key = try a.dupe(u8, pair[0..eq]);
            try vm.strings.append(a, key);
            const val = try a.dupe(u8, pair[eq + 1 ..]);
            try vm.strings.append(a, val);
            try arr.set(a, .{ .string = key }, .{ .string = val });
        }
    }
}

fn extractBoundary(ct: []const u8) ?[]const u8 {
    const marker = "boundary=";
    const pos = std.mem.indexOf(u8, ct, marker) orelse return null;
    const start = pos + marker.len;
    if (start >= ct.len) return null;
    const rest = ct[start..];
    if (rest.len > 0 and rest[0] == '"') {
        const end = std.mem.indexOfPos(u8, rest, 1, "\"") orelse return null;
        return rest[1..end];
    }
    if (std.mem.indexOfScalar(u8, rest, ';')) |end| return rest[0..end];
    return std.mem.trimRight(u8, rest, " \t\r\n");
}

fn parseMultipart(a: Allocator, vm: *VM, body: []const u8, boundary: []const u8, post_arr: *PhpArray, files_arr: *PhpArray) !void {
    const delim = try std.mem.concat(a, u8, &.{ "--", boundary });
    defer a.free(delim);

    var pos: usize = 0;
    // skip preamble - find first boundary
    pos = (std.mem.indexOf(u8, body, delim) orelse return) + delim.len;
    if (pos + 2 <= body.len and body[pos] == '\r' and body[pos + 1] == '\n') pos += 2;

    while (pos < body.len) {
        const next = std.mem.indexOfPos(u8, body, pos, delim) orelse break;
        // part data ends 2 bytes before boundary (the \r\n before delimiter)
        const part_end = if (next >= 2) next - 2 else next;
        const part = body[pos..part_end];

        // parse part headers
        const hdr_end_pos = std.mem.indexOf(u8, part, "\r\n\r\n") orelse {
            pos = next + delim.len + 2;
            continue;
        };
        const headers = part[0..hdr_end_pos];
        const part_body = part[hdr_end_pos + 4 ..];

        const disposition = findPartHeader(headers, "Content-Disposition") orelse {
            pos = next + delim.len + 2;
            continue;
        };

        const name = extractParam(disposition, "name") orelse {
            pos = next + delim.len + 2;
            continue;
        };

        const name_owned = try a.dupe(u8, name);
        try vm.strings.append(a, name_owned);

        if (extractParam(disposition, "filename")) |filename| {
            const part_ct = findPartHeader(headers, "Content-Type") orelse "application/octet-stream";

            const file_entry = try a.create(PhpArray);
            file_entry.* = .{};
            try vm.arrays.append(a, file_entry);

            const fname = try a.dupe(u8, filename);
            try vm.strings.append(a, fname);
            try file_entry.set(a, .{ .string = "name" }, .{ .string = fname });

            const mime = try a.dupe(u8, part_ct);
            try vm.strings.append(a, mime);
            try file_entry.set(a, .{ .string = "type" }, .{ .string = mime });

            try file_entry.set(a, .{ .string = "size" }, .{ .int = @intCast(part_body.len) });
            try file_entry.set(a, .{ .string = "error" }, .{ .int = 0 });

            // write to temp file
            const tmp_path = writeTempFile(a, part_body) catch blk: {
                try file_entry.set(a, .{ .string = "error" }, .{ .int = 6 }); // UPLOAD_ERR_NO_TMP_DIR
                break :blk try a.dupe(u8, "");
            };
            try vm.strings.append(a, tmp_path);
            try file_entry.set(a, .{ .string = "tmp_name" }, .{ .string = tmp_path });

            try files_arr.set(a, .{ .string = name_owned }, .{ .array = file_entry });
        } else {
            const val = try a.dupe(u8, part_body);
            try vm.strings.append(a, val);
            try post_arr.set(a, .{ .string = name_owned }, .{ .string = val });
        }

        // advance past delimiter
        pos = next + delim.len;
        if (pos + 2 <= body.len and body[pos] == '-' and body[pos + 1] == '-') break;
        if (pos + 2 <= body.len and body[pos] == '\r' and body[pos + 1] == '\n') pos += 2;
    }
}

fn findPartHeader(headers: []const u8, name: []const u8) ?[]const u8 {
    var iter = std.mem.splitSequence(u8, headers, "\r\n");
    while (iter.next()) |line| {
        const sep = std.mem.indexOf(u8, line, ": ") orelse continue;
        if (std.ascii.eqlIgnoreCase(line[0..sep], name)) return line[sep + 2 ..];
    }
    return null;
}

fn extractParam(header: []const u8, name: []const u8) ?[]const u8 {
    // look for name="value" pattern
    var search_buf: [64]u8 = undefined;
    const needle = std.fmt.bufPrint(&search_buf, "{s}=\"", .{name}) catch return null;
    const start = (std.mem.indexOf(u8, header, needle) orelse return null) + needle.len;
    const end = std.mem.indexOfPos(u8, header, start, "\"") orelse return null;
    return header[start..end];
}

const c_mkstemp = @cImport(@cInclude("stdlib.h"));

fn writeTempFile(a: Allocator, data: []const u8) ![]const u8 {
    const template = "/tmp/zphp_upload_XXXXXX";
    const buf = try a.alloc(u8, template.len + 1);
    @memcpy(buf[0..template.len], template);
    buf[template.len] = 0;

    const fd = c_mkstemp.mkstemp(buf.ptr);
    if (fd < 0) { a.free(buf); return error.TempFileCreation; }
    defer posix.close(fd);

    var written: usize = 0;
    while (written < data.len) {
        const n = posix.write(fd, data[written..]) catch { a.free(buf); return error.TempFileWrite; };
        written += n;
    }

    // return path without null terminator, but keep same allocation
    const path = try a.dupe(u8, buf[0..template.len]);
    a.free(buf);
    return path;
}

fn urlDecode(a: Allocator, input: []const u8) ![]const u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '%' and i + 2 < input.len) {
            const hi = std.fmt.charToDigit(input[i + 1], 16) catch { try buf.append(a, input[i]); i += 1; continue; };
            const lo = std.fmt.charToDigit(input[i + 2], 16) catch { try buf.append(a, input[i]); i += 1; continue; };
            try buf.append(a, hi * 16 + lo);
            i += 3;
        } else if (input[i] == '+') {
            try buf.append(a, ' ');
            i += 1;
        } else {
            try buf.append(a, input[i]);
            i += 1;
        }
    }
    return buf.toOwnedSlice(a);
}

fn tryServeStatic(allocator: Allocator, conn: *Connection, doc_root: []const u8, req: *const Request, keep_alive: bool) bool {
    const path = req.path;
    if (std.mem.endsWith(u8, path, ".php")) return false;
    if (path.len <= 1) return false;
    const rel = if (path.len > 0 and path[0] == '/') path[1..] else path;
    if (rel.len == 0) return false;
    if (std.mem.indexOf(u8, rel, "..") != null) return false;

    const file_path = std.fs.path.join(allocator, &.{ doc_root, rel }) catch return false;
    defer allocator.free(file_path);
    const file = std.fs.cwd().openFile(file_path, .{}) catch return false;
    defer file.close();
    const stat = file.stat() catch return false;
    if (stat.kind != .file) return false;

    const size = stat.size;
    const mime = mimeType(rel);

    var etag_buf: [64]u8 = undefined;
    const mtime_s: u64 = @intCast(@divFloor(stat.mtime, 1_000_000_000));
    const etag = std.fmt.bufPrint(&etag_buf, "\"{x}-{x}\"", .{ size, mtime_s }) catch return false;

    if (req.getHeader("If-None-Match")) |inm| {
        if (std.mem.eql(u8, inm, etag)) {
            const conn_val = if (keep_alive) "keep-alive" else "close";
            var hdr_buf: [512]u8 = undefined;
            const hdr = std.fmt.bufPrint(&hdr_buf, "HTTP/1.1 304 Not Modified\r\nETag: {s}\r\nConnection: {s}\r\n\r\n", .{ etag, conn_val }) catch return false;
            _ = conn.ioWrite(hdr) catch return false;
            return true;
        }
    }

    const conn_val = if (keep_alive) "keep-alive" else "close";
    const use_gzip = acceptsGzip(req) and isCompressible(mime) and size <= 1024 * 1024;

    if (use_gzip) {
        const raw = allocator.alloc(u8, size) catch return false;
        defer allocator.free(raw);
        const bytes_read = file.readAll(raw) catch return false;
        if (gzipCompress(allocator, raw[0..bytes_read])) |compressed| {
            defer allocator.free(compressed);
            var hdr_buf: [512]u8 = undefined;
            const hdr = std.fmt.bufPrint(&hdr_buf, "HTTP/1.1 200 OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nContent-Encoding: gzip\r\nETag: {s}\r\nCache-Control: public, max-age=3600\r\nVary: Accept-Encoding\r\nConnection: {s}\r\n\r\n", .{ mime, compressed.len, etag, conn_val }) catch return false;
            _ = conn.ioWrite(hdr) catch return false;
            _ = conn.ioWrite(compressed) catch return true;
            return true;
        }
    }

    var hdr_buf: [512]u8 = undefined;
    const hdr = std.fmt.bufPrint(&hdr_buf, "HTTP/1.1 200 OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nETag: {s}\r\nCache-Control: public, max-age=3600\r\nConnection: {s}\r\n\r\n", .{ mime, size, etag, conn_val }) catch return false;
    _ = conn.ioWrite(hdr) catch return false;

    var fbuf: [32768]u8 = undefined;
    var remaining: u64 = size;
    while (remaining > 0) {
        const to_read = @min(remaining, fbuf.len);
        const nr = file.read(fbuf[0..to_read]) catch return true;
        if (nr == 0) break;
        _ = conn.ioWrite(fbuf[0..nr]) catch return true;
        remaining -= nr;
    }
    return true;
}

fn mimeType(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);
    if (ext.len == 0) return "application/octet-stream";
    if (std.mem.eql(u8, ext, ".html") or std.mem.eql(u8, ext, ".htm")) return "text/html; charset=utf-8";
    if (std.mem.eql(u8, ext, ".css")) return "text/css; charset=utf-8";
    if (std.mem.eql(u8, ext, ".js") or std.mem.eql(u8, ext, ".mjs")) return "application/javascript; charset=utf-8";
    if (std.mem.eql(u8, ext, ".json")) return "application/json; charset=utf-8";
    if (std.mem.eql(u8, ext, ".xml")) return "application/xml; charset=utf-8";
    if (std.mem.eql(u8, ext, ".txt")) return "text/plain; charset=utf-8";
    if (std.mem.eql(u8, ext, ".csv")) return "text/csv; charset=utf-8";
    if (std.mem.eql(u8, ext, ".png")) return "image/png";
    if (std.mem.eql(u8, ext, ".jpg") or std.mem.eql(u8, ext, ".jpeg")) return "image/jpeg";
    if (std.mem.eql(u8, ext, ".gif")) return "image/gif";
    if (std.mem.eql(u8, ext, ".svg")) return "image/svg+xml";
    if (std.mem.eql(u8, ext, ".ico")) return "image/x-icon";
    if (std.mem.eql(u8, ext, ".webp")) return "image/webp";
    if (std.mem.eql(u8, ext, ".avif")) return "image/avif";
    if (std.mem.eql(u8, ext, ".woff")) return "font/woff";
    if (std.mem.eql(u8, ext, ".woff2")) return "font/woff2";
    if (std.mem.eql(u8, ext, ".ttf")) return "font/ttf";
    if (std.mem.eql(u8, ext, ".otf")) return "font/otf";
    if (std.mem.eql(u8, ext, ".pdf")) return "application/pdf";
    if (std.mem.eql(u8, ext, ".zip")) return "application/zip";
    if (std.mem.eql(u8, ext, ".wasm")) return "application/wasm";
    if (std.mem.eql(u8, ext, ".map")) return "application/json";
    return "application/octet-stream";
}

fn writeResponse(conn: *Connection, code: i64, content_type: []const u8, extra_headers: ?*PhpArray, body: []const u8, keep_alive: bool, use_gzip: bool, allocator: Allocator) !void {
    const status_text = switch (code) {
        200 => "200 OK", 201 => "201 Created", 204 => "204 No Content",
        301 => "301 Moved Permanently", 302 => "302 Found", 304 => "304 Not Modified",
        400 => "400 Bad Request", 401 => "401 Unauthorized", 403 => "403 Forbidden",
        404 => "404 Not Found", 405 => "405 Method Not Allowed", 500 => "500 Internal Server Error",
        else => "200 OK",
    };

    const compressed = if (use_gzip and body.len > 0 and isCompressible(content_type)) gzipCompress(allocator, body) else null;
    defer if (compressed) |c| allocator.free(c);

    const actual_body = if (compressed) |c| c else body;
    var hdr_buf: [4096]u8 = undefined;
    var pos: usize = 0;
    const conn_val = if (keep_alive) "keep-alive" else "close";
    const base = std.fmt.bufPrint(&hdr_buf, "HTTP/1.1 {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: {s}\r\n", .{ status_text, content_type, actual_body.len, conn_val }) catch return;
    pos = base.len;

    if (compressed != null) {
        const enc_hdr = "Content-Encoding: gzip\r\nVary: Accept-Encoding\r\n";
        if (pos + enc_hdr.len < hdr_buf.len) {
            @memcpy(hdr_buf[pos .. pos + enc_hdr.len], enc_hdr);
            pos += enc_hdr.len;
        }
    }

    if (extra_headers) |hdrs| {
        for (hdrs.entries.items) |entry| {
            if (entry.value == .string) {
                const hdr = entry.value.string;
                if (std.mem.startsWith(u8, hdr, "Content-Type:") or std.mem.startsWith(u8, hdr, "content-type:")) continue;
                if (std.mem.indexOfScalar(u8, hdr, '\r') != null or std.mem.indexOfScalar(u8, hdr, '\n') != null) continue;
                if (pos + hdr.len + 2 < hdr_buf.len) {
                    @memcpy(hdr_buf[pos .. pos + hdr.len], hdr);
                    pos += hdr.len;
                    hdr_buf[pos] = '\r';
                    hdr_buf[pos + 1] = '\n';
                    pos += 2;
                }
            }
        }
    }

    if (pos + 2 <= hdr_buf.len) { hdr_buf[pos] = '\r'; hdr_buf[pos + 1] = '\n'; pos += 2; }
    _ = conn.ioWrite(hdr_buf[0..pos]) catch return;
    if (actual_body.len > 0) _ = conn.ioWrite(actual_body) catch return;
}

fn acceptsGzip(req: *const Request) bool {
    const enc = req.getHeader("Accept-Encoding") orelse return false;
    return std.mem.indexOf(u8, enc, "gzip") != null;
}

fn isCompressible(mime: []const u8) bool {
    return std.mem.startsWith(u8, mime, "text/") or
        std.mem.startsWith(u8, mime, "application/javascript") or
        std.mem.startsWith(u8, mime, "application/json") or
        std.mem.startsWith(u8, mime, "application/xml") or
        std.mem.startsWith(u8, mime, "image/svg+xml");
}

fn gzipCompress(allocator: Allocator, input: []const u8) ?[]u8 {
    if (input.len == 0) return null;
    const bound = zlib.compressBound(input.len);
    const out = allocator.alloc(u8, bound) catch return null;

    var stream: zlib.z_stream = std.mem.zeroes(zlib.z_stream);
    if (zlib.deflateInit2(&stream, zlib.Z_DEFAULT_COMPRESSION, zlib.Z_DEFLATED, 15 + 16, 8, zlib.Z_DEFAULT_STRATEGY) != zlib.Z_OK) {
        allocator.free(out);
        return null;
    }

    stream.next_in = @constCast(input.ptr);
    stream.avail_in = @intCast(input.len);
    stream.next_out = out.ptr;
    stream.avail_out = @intCast(out.len);

    const rc = zlib.deflate(&stream, zlib.Z_FINISH);
    _ = zlib.deflateEnd(&stream);

    if (rc != zlib.Z_STREAM_END) { allocator.free(out); return null; }

    const compressed_len = out.len - stream.avail_out;
    if (compressed_len >= input.len) { allocator.free(out); return null; }

    if (allocator.resize(out, compressed_len)) return out[0..compressed_len];
    const exact = allocator.alloc(u8, compressed_len) catch { allocator.free(out); return null; };
    @memcpy(exact, out[0..compressed_len]);
    allocator.free(out);
    return exact;
}

fn writeStderr(msg: []const u8) !void {
    _ = try posix.write(posix.STDERR_FILENO, msg);
}
