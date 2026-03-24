const std = @import("std");
const parser = @import("pipeline/parser.zig");
const compiler = @import("pipeline/compiler.zig");
const CompileResult = compiler.CompileResult;
const VM = @import("runtime/vm.zig").VM;
const Value = @import("runtime/value.zig").Value;
const PhpArray = @import("runtime/value.zig").PhpArray;
const PhpObject = @import("runtime/value.zig").PhpObject;

const Allocator = std.mem.Allocator;
const posix = std.posix;
const zlib = @cImport(@cInclude("zlib.h"));

pub const ServeConfig = struct {
    port: u16 = 8080,
    workers: u16 = 0,
    file: []const u8,
    document_root: []const u8 = "",
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

const WorkItem = struct {
    conn: std.net.Server.Connection,
};

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

        fn pop(self: *Self) ?WorkItem {
            self.mutex.lock();
            defer self.mutex.unlock();
            while (self.count == 0 and !self.shutdown) {
                self.not_empty.wait(&self.mutex);
            }
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
    };
}

var queue: WorkQueue(1024) = .{};

pub fn serve(allocator: Allocator, config: ServeConfig) !void {
    const source = std.fs.cwd().readFileAlloc(allocator, config.file, 1024 * 1024 * 10) catch |err| {
        try writeStderr("error: could not read '");
        try writeStderr(config.file);
        try writeStderr("'\n");
        return err;
    };
    defer allocator.free(source);

    const abs_path = std.fs.cwd().realpathAlloc(allocator, config.file) catch
        try allocator.dupe(u8, config.file);
    defer allocator.free(abs_path);

    var ast = try parser.parse(allocator, source);
    defer ast.deinit();

    if (ast.errors.len > 0) {
        try writeStderr("parse error in ");
        try writeStderr(config.file);
        try writeStderr("\n");
        std.process.exit(1);
    }

    var result = compiler.compileWithPath(&ast, allocator, abs_path) catch {
        try writeStderr("compile error\n");
        std.process.exit(1);
    };
    defer result.deinit();

    const ws_enabled = blk: {
        for (result.functions.items) |*f| {
            if (std.mem.eql(u8, f.name, "ws_onMessage")) break :blk true;
        }
        break :blk false;
    };

    const worker_count: usize = if (config.workers > 0)
        config.workers
    else blk: {
        const cpus = std.Thread.getCpuCount() catch 4;
        break :blk @max(cpus, 1);
    };

    const addr = std.net.Address.parseIp4("0.0.0.0", config.port) catch unreachable;
    var server = try addr.listen(.{ .reuse_address = true });
    defer server.deinit();

    // resolve document root
    const doc_root = if (config.document_root.len > 0)
        try allocator.dupe(u8, config.document_root)
    else blk: {
        if (std.fs.path.dirname(abs_path)) |dir| {
            break :blk try allocator.dupe(u8, dir);
        }
        break :blk try allocator.dupe(u8, ".");
    };
    defer allocator.free(doc_root);

    var port_buf: [8]u8 = undefined;
    const port_str = std.fmt.bufPrint(&port_buf, "{d}", .{config.port}) catch "?";
    try writeStderr("zphp serving ");
    try writeStderr(config.file);
    try writeStderr(" on :");
    try writeStderr(port_str);
    try writeStderr(" (");
    var wc_buf: [8]u8 = undefined;
    const wc_str = std.fmt.bufPrint(&wc_buf, "{d}", .{worker_count}) catch "?";
    try writeStderr(wc_str);
    try writeStderr(" workers)\n");

    const workers = try allocator.alloc(std.Thread, worker_count);
    defer allocator.free(workers);

    for (workers) |*w| {
        w.* = try std.Thread.spawn(.{}, workerLoop, .{ allocator, &result, doc_root, config.port, ws_enabled });
    }

    while (true) {
        const conn = server.accept() catch |err| {
            if (err == error.SocketNotListening) break;
            continue;
        };
        queue.push(.{ .conn = conn });
    }

    queue.close();
    for (workers) |w| w.join();
}

fn workerLoop(allocator: Allocator, result: *const CompileResult, doc_root: []const u8, port: u16, ws_enabled: bool) void {
    var vm = VM.init(allocator) catch return;
    defer vm.deinit();

    while (true) {
        const item = queue.pop() orelse return;
        handleConnection(allocator, result, &vm, doc_root, item.conn, port, ws_enabled);
    }
}

fn handleConnection(allocator: Allocator, result: *const CompileResult, vm: *VM, doc_root: []const u8, conn: std.net.Server.Connection, port: u16, ws_enabled: bool) void {
    var buf: [65536]u8 = undefined;
    var buffered: usize = 0;
    var keep_alive = true;

    while (keep_alive) {
        if (buffered == 0 or std.mem.indexOf(u8, buf[0..buffered], "\r\n\r\n") == null) {
            const n = conn.stream.read(buf[buffered..]) catch break;
            if (n == 0) break;
            buffered += n;
        }

        const raw = buf[0..buffered];
        var req = parseRequest(raw);

        const conn_hdr = req.getHeader("Connection");
        keep_alive = if (conn_hdr) |h| !std.ascii.eqlIgnoreCase(h, "close") else true;

        // calculate consumed bytes (headers + body)
        const header_end = (std.mem.indexOf(u8, raw, "\r\n\r\n") orelse break) + 4;
        var body_len: usize = 0;
        if (req.getHeader("Content-Length")) |cl| {
            body_len = std.fmt.parseInt(usize, cl, 10) catch 0;
        }
        const consumed = header_end + body_len;

        // websocket upgrade
        if (ws_enabled) {
            const upgrade_hdr = req.getHeader("Upgrade");
            if (upgrade_hdr != null and std.ascii.eqlIgnoreCase(upgrade_hdr.?, "websocket")) {
                const ws_key = req.getHeader("Sec-WebSocket-Key") orelse break;
                handleWebSocket(allocator, result, vm, conn.stream, ws_key);
                return;
            }
        }

        // try static file first (skip for PHP files)
        if (tryServeStatic(allocator, conn.stream, doc_root, &req, keep_alive)) {
            if (consumed < buffered) {
                std.mem.copyForwards(u8, buf[0..buffered - consumed], buf[consumed..buffered]);
                buffered -= consumed;
            } else {
                buffered = 0;
            }
            if (!keep_alive) break;
            continue;
        }

        vm.reset();
        populateSuperglobals(vm, &req, conn, port) catch break;

        vm.interpret(result) catch {
            writeResponse(conn.stream, 500, "text/plain", null, "500 Internal Server Error", keep_alive, false, allocator) catch break;
            if (!keep_alive) break;
            continue;
        };

        const frame_vars = &vm.frames[0].vars;
        const ct_val = frame_vars.get("__response_content_type") orelse Value{ .string = "text/html" };
        const ct = if (ct_val == .string) ct_val.string else "text/html";

        const code_val = frame_vars.get("__response_code") orelse Value{ .int = 200 };
        const code = if (code_val == .int) code_val.int else 200;

        const extra_headers = if (frame_vars.get("__response_headers")) |v|
            (if (v == .array) v.array else null)
        else
            null;

        writeResponse(conn.stream, code, ct, extra_headers, vm.output.items, keep_alive, acceptsGzip(&req), allocator) catch break;

        // shift remaining data to front of buffer
        if (consumed < buffered) {
            std.mem.copyForwards(u8, buf[0..buffered - consumed], buf[consumed..buffered]);
            buffered -= consumed;
        } else {
            buffered = 0;
        }

        if (!keep_alive) break;
    }

    conn.stream.close();
}

fn parseRequest(raw: []const u8) Request {
    var req = Request{ .raw = raw };

    // request line: METHOD URI HTTP/VERSION
    const line_end = std.mem.indexOf(u8, raw, "\r\n") orelse raw.len;
    const line = raw[0..line_end];

    // method
    const method_end = std.mem.indexOf(u8, line, " ") orelse return req;
    req.method = line[0..method_end];

    // uri
    const uri_start = method_end + 1;
    const uri_end = std.mem.indexOfPos(u8, line, uri_start, " ") orelse line.len;
    req.uri = line[uri_start..uri_end];

    // split path and query string
    if (std.mem.indexOf(u8, req.uri, "?")) |q| {
        req.path = req.uri[0..q];
        req.query_string = req.uri[q + 1 ..];
    } else {
        req.path = req.uri;
    }

    // headers
    var pos = line_end + 2;
    while (pos < raw.len) {
        const hdr_end = std.mem.indexOfPos(u8, raw, pos, "\r\n") orelse break;
        if (hdr_end == pos) {
            // empty line = end of headers
            pos = hdr_end + 2;
            break;
        }
        const hdr_line = raw[pos..hdr_end];
        if (std.mem.indexOf(u8, hdr_line, ": ")) |sep| {
            if (req.header_count < 64) {
                req.headers[req.header_count] = .{
                    .name = hdr_line[0..sep],
                    .value = hdr_line[sep + 2 ..],
                };
                req.header_count += 1;
            }
        }
        pos = hdr_end + 2;
    }

    // body (everything after headers)
    if (pos < raw.len) {
        req.body = raw[pos..];
    }

    return req;
}

fn populateSuperglobals(vm: *VM, req: *const Request, conn: std.net.Server.Connection, port: u16) !void {
    const a = vm.allocator;

    // $_SERVER
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

    if (req.getHeader("Host")) |host| {
        try server_arr.set(a, .{ .string = "HTTP_HOST" }, .{ .string = host });
    }
    if (req.getHeader("User-Agent")) |ua| {
        try server_arr.set(a, .{ .string = "HTTP_USER_AGENT" }, .{ .string = ua });
    }
    if (req.getHeader("Content-Type")) |ct| {
        try server_arr.set(a, .{ .string = "CONTENT_TYPE" }, .{ .string = ct });
    }
    if (req.getHeader("Content-Length")) |cl| {
        try server_arr.set(a, .{ .string = "CONTENT_LENGTH" }, .{ .string = cl });
    }

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

    // $_GET - parse query string
    const get_arr = try a.create(PhpArray);
    get_arr.* = .{};
    try vm.arrays.append(a, get_arr);
    parseQueryString(a, get_arr, req.query_string) catch {};
    try vm.request_vars.put(a, "$_GET", .{ .array = get_arr });

    // $_POST - parse body for form data
    const post_arr = try a.create(PhpArray);
    post_arr.* = .{};
    try vm.arrays.append(a, post_arr);
    if (req.getHeader("Content-Type")) |ct| {
        if (std.mem.startsWith(u8, ct, "application/x-www-form-urlencoded")) {
            parseQueryString(a, post_arr, req.body) catch {};
        }
    }
    try vm.request_vars.put(a, "$_POST", .{ .array = post_arr });

    // $_REQUEST = $_GET + $_POST
    const request_arr = try a.create(PhpArray);
    request_arr.* = .{};
    try vm.arrays.append(a, request_arr);
    for (get_arr.entries.items) |entry| {
        try request_arr.set(a, entry.key, entry.value);
    }
    for (post_arr.entries.items) |entry| {
        try request_arr.set(a, entry.key, entry.value);
    }
    try vm.request_vars.put(a, "$_REQUEST", .{ .array = request_arr });

    // $_COOKIE
    const cookie_arr = try a.create(PhpArray);
    cookie_arr.* = .{};
    try vm.arrays.append(a, cookie_arr);
    if (req.getHeader("Cookie")) |cookies| {
        parseCookies(a, cookie_arr, cookies) catch {};
    }
    try vm.request_vars.put(a, "$_COOKIE", .{ .array = cookie_arr });
}

fn parseQueryString(a: Allocator, arr: *PhpArray, qs: []const u8) !void {
    if (qs.len == 0) return;
    var iter = std.mem.splitScalar(u8, qs, '&');
    while (iter.next()) |pair| {
        if (pair.len == 0) continue;
        if (std.mem.indexOf(u8, pair, "=")) |eq| {
            const key = try urlDecode(a, pair[0..eq]);
            const val = try urlDecode(a, pair[eq + 1 ..]);
            try arr.set(a, .{ .string = key }, .{ .string = val });
        } else {
            const key = try urlDecode(a, pair);
            try arr.set(a, .{ .string = key }, .{ .string = "" });
        }
    }
}

fn parseCookies(a: Allocator, arr: *PhpArray, cookies: []const u8) !void {
    var iter = std.mem.splitSequence(u8, cookies, "; ");
    while (iter.next()) |pair| {
        if (std.mem.indexOf(u8, pair, "=")) |eq| {
            const key = try a.dupe(u8, pair[0..eq]);
            const val = try a.dupe(u8, pair[eq + 1 ..]);
            try arr.set(a, .{ .string = key }, .{ .string = val });
        }
    }
}

fn urlDecode(a: Allocator, input: []const u8) ![]const u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '%' and i + 2 < input.len) {
            const hi = std.fmt.charToDigit(input[i + 1], 16) catch {
                try buf.append(a, input[i]);
                i += 1;
                continue;
            };
            const lo = std.fmt.charToDigit(input[i + 2], 16) catch {
                try buf.append(a, input[i]);
                i += 1;
                continue;
            };
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

fn handleWebSocket(allocator: Allocator, result: *const CompileResult, vm: *VM, stream: std.net.Stream, ws_key: []const u8) void {
    const ws = @import("websocket.zig");
    const max_msg_size: usize = 1024 * 1024;

    // handshake
    var accept_buf: [28]u8 = undefined;
    const accept = ws.computeAcceptKey(ws_key, &accept_buf);
    ws.writeHandshakeResponse(stream, accept) catch return;

    // run script once to register functions
    vm.reset();
    vm.interpret(result) catch return;

    // create $ws object
    const ws_obj = allocator.create(PhpObject) catch return;
    ws_obj.* = .{ .class_name = "WebSocketConnection" };
    ws_obj.set(allocator, "__ws_fd", .{ .int = @intCast(stream.handle) }) catch return;
    ws_obj.set(allocator, "__ws_closed", .{ .bool = false }) catch return;
    vm.objects.append(allocator, ws_obj) catch return;
    const ws_val = Value{ .object = ws_obj };

    // call ws_onOpen
    if (vm.functions.contains("ws_onOpen")) {
        _ = vm.callByName("ws_onOpen", &.{ws_val}) catch {};
    }

    // frame loop
    const msg_buf = allocator.alloc(u8, max_msg_size) catch return;
    defer allocator.free(msg_buf);

    while (true) {
        const frame = ws.readFrame(stream, msg_buf, max_msg_size) catch |err| {
            if (err == ws.ReadError.MessageTooLarge) {
                ws.writeCloseFrame(stream, 1009) catch {}; // 1009 = message too big
            } else if (err == ws.ReadError.ProtocolError) {
                ws.writeCloseFrame(stream, 1002) catch {}; // 1002 = protocol error
            }
            break;
        };

        switch (frame.opcode) {
            .text, .binary => {
                const data = allocator.dupe(u8, frame.payload) catch break;
                vm.strings.append(allocator, data) catch {
                    allocator.free(data);
                    break;
                };
                _ = vm.callByName("ws_onMessage", &.{ ws_val, Value{ .string = data } }) catch {};
            },
            .ping => {
                ws.writeFrame(stream, .pong, frame.payload) catch break;
            },
            .close => {
                ws.writeCloseFrame(stream, 1000) catch {};
                break;
            },
            .pong, .continuation => {},
            _ => break,
        }
    }

    // call ws_onClose
    if (vm.functions.contains("ws_onClose")) {
        _ = vm.callByName("ws_onClose", &.{ws_val}) catch {};
    }

    stream.close();
}

fn tryServeStatic(allocator: Allocator, stream: std.net.Stream, doc_root: []const u8, req: *const Request, keep_alive: bool) bool {
    const path = req.path;

    // skip PHP files - let the VM handle those
    if (std.mem.endsWith(u8, path, ".php")) return false;

    // skip root path - that's the PHP entry point
    if (path.len <= 1) return false;

    // strip leading slash and resolve relative to doc_root
    const rel = if (path.len > 0 and path[0] == '/') path[1..] else path;
    if (rel.len == 0) return false;

    // prevent directory traversal
    if (std.mem.indexOf(u8, rel, "..") != null) return false;

    const file_path = std.fs.path.join(allocator, &.{ doc_root, rel }) catch return false;
    defer allocator.free(file_path);

    const file = std.fs.cwd().openFile(file_path, .{}) catch return false;
    defer file.close();

    const stat = file.stat() catch return false;
    if (stat.kind != .file) return false;

    const size = stat.size;
    const mime = mimeType(rel);

    // ETag based on size + mtime
    var etag_buf: [64]u8 = undefined;
    const mtime_s: u64 = @intCast(@divFloor(stat.mtime, 1_000_000_000));
    const etag = std.fmt.bufPrint(&etag_buf, "\"{x}-{x}\"", .{ size, mtime_s }) catch return false;

    // check If-None-Match
    if (req.getHeader("If-None-Match")) |inm| {
        if (std.mem.eql(u8, inm, etag)) {
            const conn_val = if (keep_alive) "keep-alive" else "close";
            var hdr_buf: [512]u8 = undefined;
            const hdr = std.fmt.bufPrint(&hdr_buf, "HTTP/1.1 304 Not Modified\r\nETag: {s}\r\nConnection: {s}\r\n\r\n", .{ etag, conn_val }) catch return false;
            _ = stream.write(hdr) catch return false;
            return true;
        }
    }

    const conn_val = if (keep_alive) "keep-alive" else "close";
    const use_gzip = acceptsGzip(req) and isCompressible(mime) and size <= 1024 * 1024;

    if (use_gzip) {
        // read file into memory and compress
        const raw = allocator.alloc(u8, size) catch return false;
        defer allocator.free(raw);
        const bytes_read = file.readAll(raw) catch return false;

        if (gzipCompress(allocator, raw[0..bytes_read])) |compressed| {
            defer allocator.free(compressed);
            var hdr_buf: [512]u8 = undefined;
            const hdr = std.fmt.bufPrint(&hdr_buf, "HTTP/1.1 200 OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nContent-Encoding: gzip\r\nETag: {s}\r\nCache-Control: public, max-age=3600\r\nVary: Accept-Encoding\r\nConnection: {s}\r\n\r\n", .{ mime, compressed.len, etag, conn_val }) catch return false;
            _ = stream.write(hdr) catch return false;
            _ = stream.write(compressed) catch return true;
            return true;
        }
        // compression didn't help, fall through to uncompressed
    }

    var hdr_buf: [512]u8 = undefined;
    const hdr = std.fmt.bufPrint(&hdr_buf, "HTTP/1.1 200 OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nETag: {s}\r\nCache-Control: public, max-age=3600\r\nConnection: {s}\r\n\r\n", .{ mime, size, etag, conn_val }) catch return false;
    _ = stream.write(hdr) catch return false;

    var fbuf: [32768]u8 = undefined;
    var remaining: u64 = size;
    while (remaining > 0) {
        const to_read = @min(remaining, fbuf.len);
        const n = file.read(fbuf[0..to_read]) catch return true;
        if (n == 0) break;
        _ = stream.write(fbuf[0..n]) catch return true;
        remaining -= n;
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

fn writeResponse(stream: std.net.Stream, code: i64, content_type: []const u8, extra_headers: ?*PhpArray, body: []const u8, keep_alive: bool, use_gzip: bool, allocator: Allocator) !void {
    const status_text = switch (code) {
        200 => "200 OK",
        201 => "201 Created",
        204 => "204 No Content",
        301 => "301 Moved Permanently",
        302 => "302 Found",
        304 => "304 Not Modified",
        400 => "400 Bad Request",
        401 => "401 Unauthorized",
        403 => "403 Forbidden",
        404 => "404 Not Found",
        405 => "405 Method Not Allowed",
        500 => "500 Internal Server Error",
        else => "200 OK",
    };

    const compressed = if (use_gzip and body.len > 0 and isCompressible(content_type))
        gzipCompress(allocator, body)
    else
        null;
    defer if (compressed) |c| allocator.free(c);

    const actual_body = if (compressed) |c| c else body;
    var hdr_buf: [4096]u8 = undefined;
    var pos: usize = 0;
    const conn_val = if (keep_alive) "keep-alive" else "close";
    const base = std.fmt.bufPrint(&hdr_buf, "HTTP/1.1 {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: {s}\r\n", .{
        status_text,
        content_type,
        actual_body.len,
        conn_val,
    }) catch return;
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
                // reject headers containing \r or \n to prevent header injection
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

    if (pos + 2 <= hdr_buf.len) {
        hdr_buf[pos] = '\r';
        hdr_buf[pos + 1] = '\n';
        pos += 2;
    }

    _ = stream.write(hdr_buf[0..pos]) catch return;
    if (actual_body.len > 0) {
        _ = stream.write(actual_body) catch return;
    }
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
    // 15 + 16 = gzip format
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

    if (rc != zlib.Z_STREAM_END) {
        allocator.free(out);
        return null;
    }

    const compressed_len = out.len - stream.avail_out;
    if (compressed_len >= input.len) {
        allocator.free(out);
        return null;
    }

    // shrink to actual size so free matches alloc
    if (allocator.resize(out, compressed_len)) {
        return out[0..compressed_len];
    }
    // resize not supported, copy to exact-sized buffer
    const exact = allocator.alloc(u8, compressed_len) catch {
        allocator.free(out);
        return null;
    };
    @memcpy(exact, out[0..compressed_len]);
    allocator.free(out);
    return exact;
}

fn writeStderr(msg: []const u8) !void {
    _ = try posix.write(posix.STDERR_FILENO, msg);
}
