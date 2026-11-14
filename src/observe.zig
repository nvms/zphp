// production observability for `zphp serve`: request ids, JSON Lines logs,
// server-wide metrics and the admin listener that serves /health, /ready and
// /metrics. everything here is configured once before any worker starts and
// is read-only afterwards, so the request path never takes a lock
const std = @import("std");
const platform = @import("platform.zig");
const sys = @import("sys.zig");
const net = @import("net.zig");

const posix = std.posix;

// ---------------------------------------------------------------- request ids

pub const max_request_id_len = 64;
const id_header_prefix = "X-Request-Id: ";

// an incoming id is echoed into a response header and the logs, so only a
// short token of plain characters is accepted; anything else gets a fresh id
pub fn validRequestId(id: []const u8) bool {
    if (id.len == 0 or id.len > max_request_id_len) return false;
    for (id) |ch| {
        if (!std.ascii.isAlphanumeric(ch) and ch != '-' and ch != '_' and ch != '.' and ch != ':') return false;
    }
    return true;
}

// the effective id of the request a worker is running, kept with its
// response header line so writing it costs a single copy
pub const RequestId = struct {
    buf: [id_header_prefix.len + max_request_id_len + 2]u8 = undefined,
    len: usize = 0,

    pub fn assign(self: *RequestId, incoming: ?[]const u8, prng: *std.Random.DefaultPrng) void {
        @memcpy(self.buf[0..id_header_prefix.len], id_header_prefix);
        var id_len: usize = 32;
        const trimmed = if (incoming) |raw| std.mem.trim(u8, raw, " \t") else "";
        if (validRequestId(trimmed)) {
            id_len = trimmed.len;
            @memcpy(self.buf[id_header_prefix.len..][0..id_len], trimmed);
        } else {
            const bytes = std.mem.toBytes(prng.next()) ++ std.mem.toBytes(prng.next());
            const hex = std.fmt.bytesToHex(bytes, .lower);
            @memcpy(self.buf[id_header_prefix.len..][0..id_len], &hex);
        }
        self.len = id_header_prefix.len + id_len + 2;
        self.buf[self.len - 2] = '\r';
        self.buf[self.len - 1] = '\n';
    }

    pub fn id(self: *const RequestId) []const u8 {
        if (self.len == 0) return "";
        return self.buf[id_header_prefix.len .. self.len - 2];
    }

    pub fn header(self: *const RequestId) []const u8 {
        return self.buf[0..self.len];
    }
};

pub fn seededPrng() std.Random.DefaultPrng {
    var seed: u64 = undefined;
    platform.random.bytes(std.mem.asBytes(&seed));
    return .init(seed);
}

// ---------------------------------------------------------------- settings

// set by serve() before any thread starts
pub var log_json = false;
pub var access_log = false;
pub var request_ids = false;
pub var metrics_enabled = false;

var log_file: ?std.Io.File = null;
var log_file_owned = false;

pub fn openLog(path: ?[]const u8) !void {
    if (path) |p| {
        log_file = try platform.openAppend(p, false);
        log_file_owned = true;
    } else {
        log_file = platform.stdout();
    }
}

pub fn closeLog() void {
    if (log_file_owned) if (log_file) |f| f.close(platform.io);
    log_file = null;
    log_file_owned = false;
}

// ---------------------------------------------------------------- JSON Lines

// one log line, built on the stack and handed to the destination in a single
// write. the log file is opened for append and a pipe keeps writes up to
// PIPE_BUF whole, so lines from concurrent workers do not interleave.
// fields that do not fit are dropped whole and strings are cut short, which
// keeps every line valid JSON whatever the input
pub const Record = struct {
    buf: [4096]u8 = undefined,
    len: usize = 0,

    const tail = 2; // "}\n"

    pub fn init(level: []const u8, component: []const u8, msg: []const u8) Record {
        var r: Record = .{};
        r.put("{\"ts\":\"");
        r.timestamp(platform.milliTimestamp());
        r.put("\"");
        r.str("level", level);
        r.str("component", component);
        r.str("msg", msg);
        return r;
    }

    fn room(r: *const Record) usize {
        return r.buf.len - tail - r.len;
    }

    fn put(r: *Record, data: []const u8) void {
        @memcpy(r.buf[r.len..][0..data.len], data);
        r.len += data.len;
    }

    fn key(r: *Record, name: []const u8) void {
        r.put(",\"");
        r.put(name);
        r.put("\":");
    }

    pub fn str(r: *Record, name: []const u8, value: []const u8) void {
        if (r.room() < name.len + 8) return;
        r.key(name);
        r.put("\"");
        r.escape(value);
        r.put("\"");
    }

    pub fn int(r: *Record, name: []const u8, value: anytype) void {
        if (r.room() < name.len + 24) return;
        r.key(name);
        r.len += (std.fmt.bufPrint(r.buf[r.len..], "{d}", .{value}) catch unreachable).len;
    }

    pub fn boolean(r: *Record, name: []const u8, value: bool) void {
        if (r.room() < name.len + 8) return;
        r.key(name);
        r.put(if (value) "true" else "false");
    }

    // milliseconds with microsecond precision
    pub fn millis(r: *Record, name: []const u8, ns: u64) void {
        if (r.room() < name.len + 28) return;
        r.key(name);
        const us = ns / std.time.ns_per_us;
        r.len += (std.fmt.bufPrint(r.buf[r.len..], "{d}.{d:0>3}", .{ us / 1000, us % 1000 }) catch unreachable).len;
    }

    // invalid UTF-8 becomes U+FFFD and control bytes are \u escaped, so
    // request paths and exception messages cannot break or forge a line.
    // one byte is always left for the closing quote
    fn escape(r: *Record, s: []const u8) void {
        var i: usize = 0;
        while (i < s.len) {
            // runs of printable ascii, the common case, are copied whole
            var end = i;
            while (end < s.len and s[end] >= 0x20 and s[end] < 0x7f and s[end] != '"' and s[end] != '\\') end += 1;
            if (end > i) {
                const n = @min(end - i, r.room() -| 1);
                r.put(s[i..][0..n]);
                if (n < end - i) return;
                i = end;
                continue;
            }
            if (r.room() < 7) return;
            const ch = s[i];
            if (ch < 0x80) {
                switch (ch) {
                    '"' => r.put("\\\""),
                    '\\' => r.put("\\\\"),
                    '\n' => r.put("\\n"),
                    '\r' => r.put("\\r"),
                    '\t' => r.put("\\t"),
                    0...0x08, 0x0b, 0x0c, 0x0e...0x1f, 0x7f => {
                        r.len += (std.fmt.bufPrint(r.buf[r.len..], "\\u{x:0>4}", .{ch}) catch unreachable).len;
                    },
                    else => r.put(&[_]u8{ch}),
                }
                i += 1;
                continue;
            }
            const n = std.unicode.utf8ByteSequenceLength(ch) catch 0;
            if (n == 0 or i + n > s.len or !std.unicode.utf8ValidateSlice(s[i .. i + n])) {
                r.put("\\ufffd");
                i += 1;
                continue;
            }
            r.put(s[i .. i + n]);
            i += n;
        }
    }

    // the calendar part changes once a second, so each thread keeps the last
    // one it formatted
    threadlocal var ts_second: u64 = std.math.maxInt(u64);
    threadlocal var ts_text: [19]u8 = undefined;

    fn timestamp(r: *Record, ms: i64) void {
        const total_ms: u64 = @intCast(@max(ms, 0));
        const second = total_ms / 1000;
        if (second != ts_second) {
            const secs = std.time.epoch.EpochSeconds{ .secs = second };
            const year_day = secs.getEpochDay().calculateYearDay();
            const month_day = year_day.calculateMonthDay();
            const day_secs = secs.getDaySeconds();
            _ = std.fmt.bufPrint(&ts_text, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}", .{
                year_day.year,
                month_day.month.numeric(),
                month_day.day_index + 1,
                day_secs.getHoursIntoDay(),
                day_secs.getMinutesIntoHour(),
                day_secs.getSecondsIntoMinute(),
            }) catch @memcpy(&ts_text, "9999-12-31T23:59:59");
            ts_second = second;
        }
        r.put(&ts_text);
        const frac: u16 = @intCast(total_ms % 1000);
        r.put(&.{ '.', @intCast('0' + frac / 100), @intCast('0' + frac / 10 % 10), @intCast('0' + frac % 10), 'Z' });
    }

    pub fn bytes(r: *Record) []const u8 {
        r.put("}\n");
        return r.buf[0..r.len];
    }

    // a failed write is counted and otherwise ignored: logging must never
    // take down a request or the server
    pub fn emit(r: *Record) void {
        const line = r.bytes();
        const file = log_file orelse return;
        platform.writeAll(file, line) catch {
            _ = global.log_errors.fetchAdd(1, .monotonic);
        };
    }
};

// ---------------------------------------------------------------- metrics

// a value with a single writer: plain loads and stores, no read-modify-write,
// so a worker never contends with anyone over its own counters
const Cell = struct {
    v: std.atomic.Value(u64) = .init(0),

    pub inline fn add(c: *Cell, n: u64) void {
        c.v.store(c.v.load(.monotonic) +% n, .monotonic);
    }

    pub inline fn set(c: *Cell, n: u64) void {
        c.v.store(n, .monotonic);
    }

    pub inline fn get(c: *const Cell) u64 {
        return c.v.load(.monotonic);
    }
};

// request duration bucket bounds, in microseconds and as Prometheus labels
const bucket_bounds_us = [_]u64{ 1_000, 2_500, 5_000, 10_000, 25_000, 50_000, 100_000, 250_000, 500_000, 1_000_000, 2_500_000, 5_000_000, 10_000_000 };
const bucket_labels = [_][]const u8{ "0.001", "0.0025", "0.005", "0.01", "0.025", "0.05", "0.1", "0.25", "0.5", "1", "2.5", "5", "10" };
const status_labels = [_][]const u8{ "1xx", "2xx", "3xx", "4xx", "5xx" };

fn bucketIndex(ns: u64) usize {
    for (bucket_bounds_us, 0..) |us, i| {
        if (ns <= us * std.time.ns_per_us) return i;
    }
    return bucket_bounds_us.len;
}

// written only by the worker that owns it; the admin thread sums all of them.
// each worker gets its own cache lines so no counter is ever shared
pub const WorkerStats = struct {
    requests: [status_labels.len]Cell align(std.atomic.cache_line) = @splat(.{}),
    buckets: [bucket_bounds_us.len + 1]Cell = @splat(.{}),
    duration_ns: Cell = .{},
    busy: Cell = .{},
    connections: Cell = .{},
    connections_dropped: Cell = .{},
    vm_memory: Cell = .{},

    pub fn requestStarted(s: *WorkerStats) void {
        s.busy.set(1);
    }

    pub fn requestFinished(s: *WorkerStats, status: i64, elapsed_ns: u64, vm_memory: usize) void {
        const class: usize = @intCast(std.math.clamp(@divTrunc(status, 100), 1, 5) - 1);
        s.buckets[bucketIndex(elapsed_ns)].add(1);
        s.duration_ns.add(elapsed_ns);
        s.requests[class].add(1);
        s.vm_memory.set(vm_memory);
        s.busy.set(0);
    }

    pub fn setConnections(s: *WorkerStats, n: usize) void {
        s.connections.set(n);
    }

    pub fn connectionDropped(s: *WorkerStats) void {
        s.connections_dropped.add(1);
    }

    // a stopped worker holds no connections and runs nothing; its totals stay
    pub fn stopped(s: *WorkerStats) void {
        s.busy.set(0);
        s.connections.set(0);
    }
};

// process-wide values. the main thread is the only writer of everything but
// log_errors, which any thread may bump
pub const Global = struct {
    start_ms: i64 = 0,
    ready: std.atomic.Value(bool) = .init(false),
    workers_configured: Cell = .{},
    workers_running: Cell = .{},
    worker_start_failures: Cell = .{},
    reloads: Cell = .{},
    accepted: Cell = .{},
    log_errors: std.atomic.Value(u64) = .init(0),

    pub fn connectionAccepted(g: *Global) void {
        g.accepted.add(1);
    }

    pub fn workerStartFailed(g: *Global) void {
        g.worker_start_failures.add(1);
    }

    pub fn reloaded(g: *Global) void {
        g.reloads.add(1);
    }

    pub fn setWorkers(g: *Global, running: usize, ready_now: bool) void {
        g.workers_running.set(running);
        g.ready.store(ready_now and running > 0, .release);
    }
};

pub var global: Global = .{};

// one slot per configured worker. allocated before the admin thread starts
// and freed only after it has been joined
pub var worker_stats: []WorkerStats = &.{};

pub fn statsFor(slot: usize) ?*WorkerStats {
    if (slot >= worker_stats.len) return null;
    return &worker_stats[slot];
}

const Totals = struct {
    requests: [status_labels.len]u64 = @splat(0),
    buckets: [bucket_bounds_us.len + 1]u64 = @splat(0),
    duration_ns: u64 = 0,
    busy: u64 = 0,
    connections: u64 = 0,
    connections_dropped: u64 = 0,
    vm_memory: u64 = 0,
};

fn sumWorkers() Totals {
    var t: Totals = .{};
    for (worker_stats) |*s| {
        for (&t.requests, &s.requests) |*dst, *src| dst.* +%= src.get();
        for (&t.buckets, &s.buckets) |*dst, *src| dst.* +%= src.get();
        t.duration_ns +%= s.duration_ns.get();
        t.busy += s.busy.get();
        t.connections += s.connections.get();
        t.connections_dropped +%= s.connections_dropped.get();
        t.vm_memory += s.vm_memory.get();
    }
    return t;
}

fn seconds(w: *std.Io.Writer, ns: u64) !void {
    try w.print("{d}.{d:0>9}", .{ ns / std.time.ns_per_s, ns % std.time.ns_per_s });
}

fn metric(w: *std.Io.Writer, name: []const u8, kind: []const u8, help: []const u8) !void {
    try w.print("# HELP {s} {s}\n# TYPE {s} {s}\n", .{ name, help, name, kind });
}

// Prometheus text exposition format 0.0.4
pub fn renderMetrics(w: *std.Io.Writer) !void {
    const t = sumWorkers();

    try metric(w, "zphp_http_requests_total", "counter", "HTTP requests answered, by status class.");
    for (status_labels, t.requests) |label, n| try w.print("zphp_http_requests_total{{code=\"{s}\"}} {d}\n", .{ label, n });

    // the count is the sum of the buckets read here, so +Inf always equals it
    try metric(w, "zphp_http_request_duration_seconds", "histogram", "Time from a complete request to its response being written.");
    var cumulative: u64 = 0;
    for (bucket_labels, 0..) |label, i| {
        cumulative += t.buckets[i];
        try w.print("zphp_http_request_duration_seconds_bucket{{le=\"{s}\"}} {d}\n", .{ label, cumulative });
    }
    cumulative += t.buckets[bucket_labels.len];
    try w.print("zphp_http_request_duration_seconds_bucket{{le=\"+Inf\"}} {d}\n", .{cumulative});
    try w.writeAll("zphp_http_request_duration_seconds_sum ");
    try seconds(w, t.duration_ns);
    try w.print("\nzphp_http_request_duration_seconds_count {d}\n", .{cumulative});

    try metric(w, "zphp_http_requests_active", "gauge", "Requests being handled right now.");
    try w.print("zphp_http_requests_active {d}\n", .{t.busy});

    try metric(w, "zphp_connections_active", "gauge", "Client connections held by workers.");
    try w.print("zphp_connections_active {d}\n", .{t.connections});
    try metric(w, "zphp_connections_accepted_total", "counter", "Client connections accepted.");
    try w.print("zphp_connections_accepted_total {d}\n", .{global.accepted.get()});
    try metric(w, "zphp_connections_dropped_total", "counter", "Connections closed on arrival because a worker's connection table was full.");
    try w.print("zphp_connections_dropped_total {d}\n", .{t.connections_dropped});

    try metric(w, "zphp_workers", "gauge", "Configured worker threads.");
    try w.print("zphp_workers {d}\n", .{global.workers_configured.get()});
    try metric(w, "zphp_workers_running", "gauge", "Worker threads currently running.");
    try w.print("zphp_workers_running {d}\n", .{global.workers_running.get()});
    try metric(w, "zphp_worker_busy_seconds_total", "counter", "Time workers spent handling requests; its rate over the worker count is utilization.");
    try w.writeAll("zphp_worker_busy_seconds_total ");
    try seconds(w, t.duration_ns);
    try w.writeAll("\n");
    try metric(w, "zphp_worker_start_failures_total", "counter", "Workers that failed to start.");
    try w.print("zphp_worker_start_failures_total {d}\n", .{global.worker_start_failures.get()});
    try metric(w, "zphp_reloads_total", "counter", "Worker restarts triggered by --watch.");
    try w.print("zphp_reloads_total {d}\n", .{global.reloads.get()});

    try metric(w, "zphp_vm_memory_bytes", "gauge", "PHP memory in use by the worker VMs at the end of their last request.");
    try w.print("zphp_vm_memory_bytes {d}\n", .{t.vm_memory});
    if (platform.currentRss()) |rss| {
        try metric(w, "process_resident_memory_bytes", "gauge", "Resident memory size in bytes.");
        try w.print("process_resident_memory_bytes {d}\n", .{rss});
    }
    try metric(w, "process_resident_memory_max_bytes", "gauge", "Peak resident memory size in bytes.");
    try w.print("process_resident_memory_max_bytes {d}\n", .{platform.peakRss()});
    try metric(w, "process_start_time_seconds", "gauge", "Start time of the process since the unix epoch in seconds.");
    const start_ms: u64 = @intCast(@max(global.start_ms, 0));
    try w.print("process_start_time_seconds {d}.{d:0>3}\n", .{ start_ms / 1000, start_ms % 1000 });
    try metric(w, "zphp_uptime_seconds", "gauge", "Seconds since the server started.");
    try w.print("zphp_uptime_seconds {d}\n", .{@divFloor(@max(platform.milliTimestamp() - global.start_ms, 0), 1000)});

    try metric(w, "zphp_ready", "gauge", "1 when the server accepts application requests, as /ready reports.");
    try w.print("zphp_ready {d}\n", .{@intFromBool(global.ready.load(.acquire))});
    try metric(w, "zphp_log_write_errors_total", "counter", "Log lines that could not be written.");
    try w.print("zphp_log_write_errors_total {d}\n", .{global.log_errors.load(.monotonic)});
}

// ---------------------------------------------------------------- admin listener

// a separate loopback-by-default listener on its own thread, so probes and
// scrapes never collide with application routes, never run PHP, and keep
// answering while every worker is busy. clients are served one at a time
// with a short deadline, which bounds what a stalled client can hold
pub const Admin = struct {
    server: net.Server,
    wake: [2]posix.socket_t,
    thread: std.Thread,

    const io_deadline_ns: i128 = 2 * std.time.ns_per_s;

    pub fn start(self: *Admin, addr: net.Address) !void {
        self.server = try platform.tcpListen(addr, true);
        errdefer self.server.deinit();
        try platform.setNonBlocking(self.server.stream.handle, true);
        self.wake = try platform.socketPair();
        errdefer closePair(self.wake);
        self.thread = try std.Thread.spawn(.{}, loop, .{self});
    }

    pub fn stop(self: *Admin) void {
        _ = platform.send(self.wake[1], &[_]u8{1}) catch {};
        self.thread.join();
        closePair(self.wake);
        self.server.deinit();
    }

    fn closePair(pair: [2]posix.socket_t) void {
        platform.closeSocket(platform.socketToInt(pair[0]));
        platform.closeSocket(platform.socketToInt(pair[1]));
    }

    fn loop(self: *Admin) void {
        var fds = [2]sys.pollfd{
            .{ .fd = self.server.stream.handle, .events = sys.POLL.IN, .revents = 0 },
            .{ .fd = self.wake[0], .events = sys.POLL.IN, .revents = 0 },
        };
        while (true) {
            _ = sys.poll(&fds, -1) catch {
                platform.sleep(10 * std.time.ns_per_ms);
                continue;
            };
            if (fds[1].revents != 0) return;
            if (fds[0].revents & sys.POLL.IN == 0) continue;
            const conn = self.server.accept() catch continue;
            handle(conn.stream.handle);
            conn.stream.close();
        }
    }

    fn waitFor(sock: posix.socket_t, events: i16, deadline: i128) bool {
        const left = deadline - platform.monotonicNanos();
        if (left <= 0) return false;
        var fds = [1]sys.pollfd{.{ .fd = sock, .events = events, .revents = 0 }};
        const ms: i32 = @intCast(@min(@divTrunc(left, std.time.ns_per_ms) + 1, std.math.maxInt(i32)));
        const ready = sys.poll(&fds, ms) catch return false;
        return ready > 0;
    }

    fn sendAll(sock: posix.socket_t, data: []const u8, deadline: i128) bool {
        var sent: usize = 0;
        while (sent < data.len) {
            const n = platform.send(sock, data[sent..]) catch |err| {
                if (err == error.WouldBlock and waitFor(sock, sys.POLL.OUT, deadline)) continue;
                return false;
            };
            sent += n;
        }
        return true;
    }

    fn handle(sock: posix.socket_t) void {
        platform.setNonBlocking(sock, true) catch return;
        const deadline = platform.monotonicNanos() + io_deadline_ns;
        var buf: [2048]u8 = undefined;
        var n: usize = 0;
        while (std.mem.indexOf(u8, buf[0..n], "\r\n\r\n") == null) {
            if (n == buf.len) return respond(sock, deadline, 431, "Request Header Fields Too Large", "text/plain; charset=utf-8", "request too large\n", false);
            const got = platform.recv(sock, buf[n..]) catch |err| {
                if (err == error.WouldBlock and waitFor(sock, sys.POLL.IN, deadline)) continue;
                return;
            };
            if (got == 0) return;
            n += got;
        }
        const line = buf[0 .. std.mem.indexOf(u8, buf[0..n], "\r\n") orelse n];
        var parts = std.mem.tokenizeScalar(u8, line, ' ');
        const method = parts.next() orelse "";
        const target = parts.next() orelse "";
        const path = target[0 .. std.mem.indexOfScalar(u8, target, '?') orelse target.len];
        const head = std.mem.eql(u8, method, "HEAD");
        if (!head and !std.mem.eql(u8, method, "GET")) {
            return respond(sock, deadline, 405, "Method Not Allowed", "text/plain; charset=utf-8", "method not allowed\n", false);
        }

        if (std.mem.eql(u8, path, "/health")) {
            respond(sock, deadline, 200, "OK", "text/plain; charset=utf-8", "ok\n", head);
        } else if (std.mem.eql(u8, path, "/ready")) {
            if (global.ready.load(.acquire)) {
                respond(sock, deadline, 200, "OK", "text/plain; charset=utf-8", "ready\n", head);
            } else {
                respond(sock, deadline, 503, "Service Unavailable", "text/plain; charset=utf-8", "not ready\n", head);
            }
        } else if (std.mem.eql(u8, path, "/metrics")) {
            var body: [16384]u8 = undefined;
            var w: std.Io.Writer = .fixed(&body);
            renderMetrics(&w) catch {};
            respond(sock, deadline, 200, "OK", "text/plain; version=0.0.4; charset=utf-8", w.buffered(), head);
        } else {
            respond(sock, deadline, 404, "Not Found", "text/plain; charset=utf-8", "not found\n", head);
        }
    }

    fn respond(sock: posix.socket_t, deadline: i128, code: u16, reason: []const u8, content_type: []const u8, body: []const u8, head: bool) void {
        var hdr: [256]u8 = undefined;
        const allow = if (code == 405) "Allow: GET, HEAD\r\n" else "";
        const text = std.fmt.bufPrint(&hdr, "HTTP/1.1 {d} {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nCache-Control: no-store\r\n{s}Connection: close\r\n\r\n", .{ code, reason, content_type, body.len, allow }) catch return;
        if (!sendAll(sock, text, deadline)) return;
        if (!head) _ = sendAll(sock, body, deadline);
    }
};

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "request ids accept safe incoming tokens and replace anything else" {
    var prng = std.Random.DefaultPrng.init(1);
    var rid: RequestId = .{};

    rid.assign("abc-123_x.y:z", &prng);
    try testing.expectEqualStrings("abc-123_x.y:z", rid.id());
    try testing.expectEqualStrings("X-Request-Id: abc-123_x.y:z\r\n", rid.header());

    rid.assign("  padded  ", &prng);
    try testing.expectEqualStrings("padded", rid.id());

    const hostile = [_][]const u8{ "", "a\r\nSet-Cookie: x=1", "a b", "\"quoted\"", &@as([65]u8, @splat('x')), "caf\xc3\xa9", "a\x00b" };
    for (hostile) |bad| {
        rid.assign(bad, &prng);
        try testing.expectEqual(@as(usize, 32), rid.id().len);
        for (rid.id()) |ch| try testing.expect(std.ascii.isHex(ch));
    }

    rid.assign(&@as([64]u8, @splat('x')), &prng);
    try testing.expectEqual(@as(usize, 64), rid.id().len);

    rid.assign(null, &prng);
    const first = rid.id()[0..32].*;
    rid.assign(null, &prng);
    try testing.expect(!std.mem.eql(u8, &first, rid.id()));
}

test "log records are valid JSON whatever the input" {
    var r = Record.init("info", "access", "request");
    r.str("path", "/a\"b\\c\n\r\t\x01\x7f\xff\xc3(caf\xc3\xa9");
    r.int("status", @as(i64, 200));
    r.boolean("tls", false);
    r.millis("duration_ms", 1_234_567);
    const line = r.bytes();
    try testing.expect(std.mem.endsWith(u8, line, "}\n"));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, line, "\n"));

    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, line, .{});
    defer parsed.deinit();
    const obj = parsed.value.object;
    try testing.expectEqualStrings("/a\"b\\c\n\r\t\x01\x7f\u{fffd}\u{fffd}(café", obj.get("path").?.string);
    try testing.expectEqual(@as(i64, 200), obj.get("status").?.integer);
    try testing.expectEqualStrings("access", obj.get("component").?.string);
    try testing.expectEqual(@as(f64, 1.234), obj.get("duration_ms").?.float);
    try testing.expect(obj.get("ts").?.string.len == "2026-01-01T00:00:00.000Z".len);
}

test "oversized log fields are cut short and the line stays valid" {
    var r = Record.init("error", "php", "uncaught exception");
    const huge: [5000]u8 = @splat(1);
    r.str("message", &huge);
    r.str("exception", "RuntimeException");
    r.int("line", @as(i64, 42));
    const line = r.bytes();
    try testing.expect(line.len <= 4096);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, line, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value.object.get("message") != null);

    var plain = Record.init("info", "access", "request");
    const long: [5000]u8 = @splat('a');
    plain.str("path", &long);
    plain.int("status", @as(i64, 200));
    const plain_line = plain.bytes();
    try testing.expectEqual(@as(usize, 4096), plain_line.len);
    const plain_parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, plain_line, .{});
    defer plain_parsed.deinit();
    try testing.expect(plain_parsed.value.object.get("path").?.string.len > 3900);
}

test "log timestamps are RFC 3339 UTC" {
    const cases = [_]struct { ms: i64, text: []const u8 }{
        .{ .ms = 951_782_400_123, .text = "2000-02-29T00:00:00.123Z" },
        .{ .ms = 951_782_400_004, .text = "2000-02-29T00:00:00.004Z" },
        .{ .ms = 951_782_399_999, .text = "2000-02-28T23:59:59.999Z" },
        .{ .ms = 0, .text = "1970-01-01T00:00:00.000Z" },
    };
    for (cases) |case| {
        var r: Record = .{};
        r.timestamp(case.ms);
        try testing.expectEqualStrings(case.text, r.buf[0..r.len]);
    }
}

test "metrics aggregate every worker and keep the histogram consistent" {
    var slots: [2]WorkerStats = .{ .{}, .{} };
    const saved = worker_stats;
    const saved_global = global;
    worker_stats = &slots;
    global.start_ms = 1_700_000_000_042;
    defer {
        worker_stats = saved;
        global = saved_global;
    }

    slots[0].requestStarted();
    slots[0].requestFinished(200, 500 * std.time.ns_per_us, 1000);
    slots[1].requestFinished(404, 30 * std.time.ns_per_ms, 2000);
    slots[1].requestFinished(503, 20 * std.time.ns_per_s, 2000);
    slots[1].requestFinished(0, 0, 2000);
    slots[1].requestStarted();
    slots[0].setConnections(3);
    slots[1].setConnections(4);

    var buf: [16384]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try renderMetrics(&w);
    const out = w.buffered();

    const expect = [_][]const u8{
        "zphp_http_requests_total{code=\"1xx\"} 1\n",
        "zphp_http_requests_total{code=\"2xx\"} 1\n",
        "zphp_http_requests_total{code=\"4xx\"} 1\n",
        "zphp_http_requests_total{code=\"5xx\"} 1\n",
        "zphp_http_request_duration_seconds_bucket{le=\"0.001\"} 2\n",
        "zphp_http_request_duration_seconds_bucket{le=\"0.025\"} 2\n",
        "zphp_http_request_duration_seconds_bucket{le=\"0.05\"} 3\n",
        "zphp_http_request_duration_seconds_bucket{le=\"10\"} 3\n",
        "zphp_http_request_duration_seconds_bucket{le=\"+Inf\"} 4\n",
        "zphp_http_request_duration_seconds_count 4\n",
        "zphp_http_request_duration_seconds_sum 20.030500000\n",
        "zphp_http_requests_active 1\n",
        "zphp_connections_active 7\n",
        "zphp_vm_memory_bytes 3000\n",
        "process_start_time_seconds 1700000000.042\n",
    };
    for (expect) |line| {
        if (std.mem.indexOf(u8, out, line) == null) {
            std.debug.print("missing: {s}\n{s}\n", .{ line, out });
            return error.TestExpectedEqual;
        }
    }

    slots[1].stopped();
    w = .fixed(&buf);
    try renderMetrics(&w);
    try testing.expect(std.mem.indexOf(u8, w.buffered(), "zphp_connections_active 3\n") != null);
    try testing.expect(std.mem.indexOf(u8, w.buffered(), "zphp_http_requests_active 0\n") != null);
}
