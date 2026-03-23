const std = @import("std");
const parser = @import("pipeline/parser.zig");
const compiler = @import("pipeline/compiler.zig");
const CompileResult = compiler.CompileResult;
const VM = @import("runtime/vm.zig").VM;
const Value = @import("runtime/value.zig").Value;
const PhpArray = @import("runtime/value.zig").PhpArray;

const Allocator = std.mem.Allocator;
const posix = std.posix;

pub const ServeConfig = struct {
    port: u16 = 8080,
    workers: u16 = 0,
    file: []const u8,
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

    const worker_count: usize = if (config.workers > 0)
        config.workers
    else blk: {
        const cpus = std.Thread.getCpuCount() catch 4;
        break :blk @max(cpus, 1);
    };

    const addr = std.net.Address.parseIp4("0.0.0.0", config.port) catch unreachable;
    var server = try addr.listen(.{ .reuse_address = true });
    defer server.deinit();

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
        w.* = try std.Thread.spawn(.{}, workerLoop, .{ allocator, &result });
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

fn workerLoop(allocator: Allocator, result: *const CompileResult) void {
    while (true) {
        const item = queue.pop() orelse return;
        handleConnection(allocator, result, item.conn) catch {};
    }
}

fn handleConnection(allocator: Allocator, result: *const CompileResult, conn: std.net.Server.Connection) !void {
    defer conn.stream.close();

    var buf: [65536]u8 = undefined;
    const n = conn.stream.read(&buf) catch return;
    if (n == 0) return;
    const raw = buf[0..n];

    var req = parseRequest(raw);

    var vm = VM.init(allocator) catch return;
    defer vm.deinit();

    populateSuperglobals(&vm, &req, conn) catch {};

    vm.interpret(result) catch {
        const body = "500 Internal Server Error";
        writeResponse(conn.stream, 500, "text/plain", null, body) catch {};
        return;
    };

    // read response metadata from frame vars
    const frame_vars = &vm.frames[0].vars;
    const ct_val = frame_vars.get("__response_content_type") orelse Value{ .string = "text/html" };
    const ct = if (ct_val == .string) ct_val.string else "text/html";

    const code_val = frame_vars.get("__response_code") orelse Value{ .int = 200 };
    const code = if (code_val == .int) code_val.int else 200;

    // collect extra headers
    const extra_headers = if (frame_vars.get("__response_headers")) |v|
        (if (v == .array) v.array else null)
    else
        null;

    writeResponse(conn.stream, code, ct, extra_headers, vm.output.items) catch {};
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

fn populateSuperglobals(vm: *VM, req: *const Request, conn: std.net.Server.Connection) !void {
    const a = vm.allocator;

    // $_SERVER
    const server_arr = try a.create(PhpArray);
    server_arr.* = .{};
    try vm.arrays.append(a, server_arr);

    try server_arr.set(a, .{ .string = "REQUEST_METHOD" }, .{ .string = req.method });
    try server_arr.set(a, .{ .string = "REQUEST_URI" }, .{ .string = req.uri });
    try server_arr.set(a, .{ .string = "QUERY_STRING" }, .{ .string = req.query_string });
    try server_arr.set(a, .{ .string = "SERVER_PROTOCOL" }, .{ .string = "HTTP/1.1" });
    try server_arr.set(a, .{ .string = "SERVER_PORT" }, .{ .string = "8080" });
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

fn writeResponse(stream: std.net.Stream, code: i64, content_type: []const u8, extra_headers: ?*PhpArray, body: []const u8) !void {
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

    var hdr_buf: [4096]u8 = undefined;
    var pos: usize = 0;
    const base = std.fmt.bufPrint(&hdr_buf, "HTTP/1.1 {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n", .{
        status_text,
        content_type,
        body.len,
    }) catch return;
    pos = base.len;

    if (extra_headers) |hdrs| {
        for (hdrs.entries.items) |entry| {
            if (entry.value == .string) {
                const hdr = entry.value.string;
                // skip Content-Type since we already handle it
                if (std.mem.startsWith(u8, hdr, "Content-Type:") or std.mem.startsWith(u8, hdr, "content-type:")) continue;
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
    if (body.len > 0) {
        _ = stream.write(body) catch return;
    }
}

fn writeStderr(msg: []const u8) !void {
    _ = try posix.write(posix.STDERR_FILENO, msg);
}
