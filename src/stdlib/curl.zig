const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const RuntimeError = error{ RuntimeError, OutOfMemory };

const c = @cImport({
    @cInclude("curl/curl.h");
});

pub const entries = .{
    .{ "curl_init", curlInit },
    .{ "curl_setopt", curlSetopt },
    .{ "curl_setopt_array", curlSetoptArray },
    .{ "curl_exec", curlExec },
    .{ "curl_close", curlClose },
    .{ "curl_error", curlError },
    .{ "curl_errno", curlErrno },
    .{ "curl_getinfo", curlGetinfo },
    .{ "curl_reset", curlReset },
    .{ "curl_version", curlVersion },
};

var global_init_done: bool = false;

fn ensureGlobalInit() void {
    if (!global_init_done) {
        _ = c.curl_global_init(c.CURL_GLOBAL_DEFAULT);
        global_init_done = true;
    }
}

fn getHandle(obj: *PhpObject) ?*c.CURL {
    const v = obj.get("__curl_ptr");
    if (v != .int or v.int == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(v.int)));
}

fn getThis(ctx: *NativeContext) ?*PhpObject {
    if (ctx.vm.frame_count == 0) return null;
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

fn getThisObj(args: []const Value) ?*PhpObject {
    if (args.len == 0) return null;
    if (args[0] != .object) return null;
    return args[0].object;
}

fn dupeZ(ctx: *NativeContext, s: []const u8) ![:0]u8 {
    const z = try ctx.allocator.alloc(u8, s.len + 1);
    @memcpy(z[0..s.len], s);
    z[s.len] = 0;
    try ctx.strings.append(ctx.allocator, z);
    return z[0..s.len :0];
}

fn curlInit(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureGlobalInit();

    const handle = c.curl_easy_init() orelse return .{ .bool = false };

    const obj = try ctx.createObject("CurlHandle");
    try obj.set(ctx.allocator, "__curl_ptr", .{ .int = @intCast(@intFromPtr(handle)) });
    try obj.set(ctx.allocator, "__error", .{ .string = "" });
    try obj.set(ctx.allocator, "__errno", .{ .int = 0 });
    try obj.set(ctx.allocator, "__return_transfer", .{ .bool = false });
    try obj.set(ctx.allocator, "__header_out", .{ .bool = false });
    try obj.set(ctx.allocator, "__http_code", .{ .int = 0 });

    // store slist pointers for cleanup
    try obj.set(ctx.allocator, "__slist_ptr", .{ .int = 0 });

    if (args.len > 0 and args[0] == .string) {
        const url_z = try dupeZ(ctx, args[0].string);
        _ = c.curl_easy_setopt(handle, c.CURLOPT_URL, url_z.ptr);
    }

    return .{ .object = obj };
}

fn curlSetopt(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3) return .{ .bool = false };
    const obj = getThisObj(args) orelse return .{ .bool = false };
    const handle = getHandle(obj) orelse return .{ .bool = false };
    if (args[1] != .int) return .{ .bool = false };
    const option = args[1].int;
    return applySetopt(ctx, handle, obj, option, args[2]);
}

fn applySetopt(ctx: *NativeContext, handle: *c.CURL, obj: *PhpObject, option: i64, value: Value) RuntimeError!Value {
    // string options
    if (option == c.CURLOPT_URL or
        option == c.CURLOPT_USERAGENT or
        option == c.CURLOPT_REFERER or
        option == c.CURLOPT_COOKIE or
        option == c.CURLOPT_COOKIEFILE or
        option == c.CURLOPT_COOKIEJAR or
        option == c.CURLOPT_USERPWD or
        option == c.CURLOPT_PROXY or
        option == c.CURLOPT_PROXYUSERPWD or
        option == c.CURLOPT_CUSTOMREQUEST or
        option == c.CURLOPT_ENCODING or
        option == c.CURLOPT_CAINFO or
        option == c.CURLOPT_CAPATH or
        option == c.CURLOPT_SSLCERT or
        option == c.CURLOPT_SSLKEY or
        option == c.CURLOPT_RANGE or
        option == c.CURLOPT_INTERFACE or
        option == c.CURLOPT_UNIX_SOCKET_PATH)
    {
        const s = switch (value) {
            .string => value.string,
            .null => "",
            else => return .{ .bool = false },
        };
        const z = try dupeZ(ctx, s);
        const code: c_uint = @intCast(c.curl_easy_setopt(handle, @intCast(option), z.ptr));
        return .{ .bool = code == c.CURLE_OK };
    }

    // long options
    if (option == c.CURLOPT_PORT or
        option == c.CURLOPT_TIMEOUT or
        option == c.CURLOPT_TIMEOUT_MS or
        option == c.CURLOPT_CONNECTTIMEOUT or
        option == c.CURLOPT_CONNECTTIMEOUT_MS or
        option == c.CURLOPT_MAXREDIRS or
        option == c.CURLOPT_SSL_VERIFYPEER or
        option == c.CURLOPT_SSL_VERIFYHOST or
        option == c.CURLOPT_VERBOSE or
        option == c.CURLOPT_NOBODY or
        option == c.CURLOPT_FAILONERROR or
        option == c.CURLOPT_FRESH_CONNECT or
        option == c.CURLOPT_FORBID_REUSE or
        option == c.CURLOPT_TCP_NODELAY or
        option == c.CURLOPT_PROXYPORT or
        option == c.CURLOPT_PROXYTYPE or
        option == c.CURLOPT_HTTPAUTH or
        option == c.CURLOPT_SSLVERSION)
    {
        const v: c_long = switch (value) {
            .int => @intCast(value.int),
            .bool => if (value.bool) @as(c_long, 1) else 0,
            else => return .{ .bool = false },
        };
        const code: c_uint = @intCast(c.curl_easy_setopt(handle, @intCast(option), v));
        return .{ .bool = code == c.CURLE_OK };
    }

    // CURLOPT_RETURNTRANSFER - PHP-specific, not a real libcurl option
    if (option == 19913) {
        const rt = switch (value) {
            .bool => value.bool,
            .int => value.int != 0,
            else => false,
        };
        try obj.set(ctx.allocator, "__return_transfer", .{ .bool = rt });
        return .{ .bool = true };
    }

    // CURLOPT_FOLLOWLOCATION
    if (option == c.CURLOPT_FOLLOWLOCATION) {
        const v: c_long = switch (value) {
            .int => @intCast(value.int),
            .bool => if (value.bool) @as(c_long, 1) else 0,
            else => return .{ .bool = false },
        };
        const code: c_uint = @intCast(c.curl_easy_setopt(handle, c.CURLOPT_FOLLOWLOCATION, v));
        return .{ .bool = code == c.CURLE_OK };
    }

    // CURLOPT_POST
    if (option == c.CURLOPT_POST) {
        const v: c_long = switch (value) {
            .int => @intCast(value.int),
            .bool => if (value.bool) @as(c_long, 1) else 0,
            else => return .{ .bool = false },
        };
        const code: c_uint = @intCast(c.curl_easy_setopt(handle, c.CURLOPT_POST, v));
        return .{ .bool = code == c.CURLE_OK };
    }

    // CURLOPT_POSTFIELDS
    if (option == c.CURLOPT_POSTFIELDS) {
        const s = switch (value) {
            .string => value.string,
            else => return .{ .bool = false },
        };
        const z = try dupeZ(ctx, s);
        const code: c_uint = @intCast(c.curl_easy_setopt(handle, c.CURLOPT_POSTFIELDS, z.ptr));
        if (code != c.CURLE_OK) return .{ .bool = false };
        const len_code: c_uint = @intCast(c.curl_easy_setopt(handle, c.CURLOPT_POSTFIELDSIZE, @as(c_long, @intCast(s.len))));
        return .{ .bool = len_code == c.CURLE_OK };
    }

    // CURLOPT_HTTPHEADER
    if (option == c.CURLOPT_HTTPHEADER) {
        if (value != .array) return .{ .bool = false };

        // free previous slist if any
        const prev_v = obj.get("__slist_ptr");
        if (prev_v == .int and prev_v.int != 0) {
            const prev: *c.struct_curl_slist = @ptrFromInt(@as(usize, @intCast(prev_v.int)));
            c.curl_slist_free_all(prev);
        }

        var slist: ?*c.struct_curl_slist = null;
        for (value.array.entries.items) |entry| {
            if (entry.value == .string) {
                const z = try dupeZ(ctx, entry.value.string);
                slist = c.curl_slist_append(slist, z.ptr);
            }
        }
        if (slist) |sl| {
            try obj.set(ctx.allocator, "__slist_ptr", .{ .int = @intCast(@intFromPtr(sl)) });
            const code: c_uint = @intCast(c.curl_easy_setopt(handle, c.CURLOPT_HTTPHEADER, sl));
            return .{ .bool = code == c.CURLE_OK };
        }
        return .{ .bool = true };
    }

    // CURLOPT_PUT
    if (option == c.CURLOPT_PUT) {
        const v: c_long = switch (value) {
            .int => @intCast(value.int),
            .bool => if (value.bool) @as(c_long, 1) else 0,
            else => return .{ .bool = false },
        };
        const code: c_uint = @intCast(c.curl_easy_setopt(handle, c.CURLOPT_PUT, v));
        return .{ .bool = code == c.CURLE_OK };
    }

    // CURLOPT_HEADER - include headers in output
    if (option == c.CURLOPT_HEADER) {
        const v: c_long = switch (value) {
            .int => @intCast(value.int),
            .bool => if (value.bool) @as(c_long, 1) else 0,
            else => return .{ .bool = false },
        };
        const code: c_uint = @intCast(c.curl_easy_setopt(handle, c.CURLOPT_HEADER, v));
        return .{ .bool = code == c.CURLE_OK };
    }

    // CURLINFO_HEADER_OUT (debug)
    if (option == c.CURLINFO_HEADER_OUT) {
        const v = switch (value) {
            .bool => value.bool,
            .int => value.int != 0,
            else => false,
        };
        try obj.set(ctx.allocator, "__header_out", .{ .bool = v });
        if (v) {
            const code: c_uint = @intCast(c.curl_easy_setopt(handle, c.CURLOPT_VERBOSE, @as(c_long, 1)));
            _ = code;
        }
        return .{ .bool = true };
    }

    return .{ .bool = false };
}

fn curlSetoptArray(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .bool = false };
    const obj = getThisObj(args) orelse return .{ .bool = false };
    const handle = getHandle(obj) orelse return .{ .bool = false };
    if (args[1] != .array) return .{ .bool = false };

    for (args[1].array.entries.items) |entry| {
        if (entry.key != .int) continue;
        const result = try applySetopt(ctx, handle, obj, entry.key.int, entry.value);
        if (result == .bool and !result.bool) return .{ .bool = false };
    }
    return .{ .bool = true };
}

const WriteCallbackData = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayListUnmanaged(u8),
};

fn writeCallback(data: [*]u8, size: usize, nmemb: usize, userdata: *anyopaque) callconv(.c) usize {
    const total = size * nmemb;
    const cb_data: *WriteCallbackData = @ptrCast(@alignCast(userdata));
    cb_data.buffer.appendSlice(cb_data.allocator, data[0..total]) catch return 0;
    return total;
}

fn curlExec(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    const obj = getThisObj(args) orelse return .{ .bool = false };
    const handle = getHandle(obj) orelse return .{ .bool = false };

    const return_transfer_v = obj.get("__return_transfer");
    const return_transfer = return_transfer_v == .bool and return_transfer_v.bool;

    var cb_data = WriteCallbackData{
        .allocator = ctx.allocator,
        .buffer = .{},
    };
    defer cb_data.buffer.deinit(cb_data.allocator);

    if (return_transfer) {
        _ = c.curl_easy_setopt(handle, c.CURLOPT_WRITEFUNCTION, @as(?*const fn ([*]u8, usize, usize, *anyopaque) callconv(.c) usize, &writeCallback));
        _ = c.curl_easy_setopt(handle, c.CURLOPT_WRITEDATA, @as(*anyopaque, @ptrCast(&cb_data)));
    }

    const result = c.curl_easy_perform(handle);

    // store error info
    if (result != c.CURLE_OK) {
        const err_msg = c.curl_easy_strerror(result);
        const msg = std.mem.span(err_msg);
        const owned = try ctx.createString(msg);
        try obj.set(ctx.allocator, "__error", .{ .string = owned });
        try obj.set(ctx.allocator, "__errno", .{ .int = @intCast(result) });
        return .{ .bool = false };
    }

    try obj.set(ctx.allocator, "__error", .{ .string = "" });
    try obj.set(ctx.allocator, "__errno", .{ .int = 0 });

    // store http code
    var http_code: c_long = 0;
    _ = c.curl_easy_getinfo(handle, c.CURLINFO_RESPONSE_CODE, &http_code);
    try obj.set(ctx.allocator, "__http_code", .{ .int = @intCast(http_code) });

    if (return_transfer) {
        const str = try ctx.createString(cb_data.buffer.items);
        return .{ .string = str };
    }

    return .{ .bool = true };
}

fn curlClose(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    _ = ctx;
    if (args.len == 0) return .null;
    const obj = getThisObj(args) orelse return .null;
    cleanupHandle(obj);
    return .null;
}

fn cleanupHandle(obj: *PhpObject) void {
    // free slist
    const slist_v = obj.get("__slist_ptr");
    if (slist_v == .int and slist_v.int != 0) {
        const sl: *c.struct_curl_slist = @ptrFromInt(@as(usize, @intCast(slist_v.int)));
        c.curl_slist_free_all(sl);
        obj.properties.put(std.heap.page_allocator, "__slist_ptr", .{ .int = 0 }) catch {};
    }

    // free curl handle
    if (getHandle(obj)) |handle| {
        c.curl_easy_cleanup(handle);
        obj.properties.put(std.heap.page_allocator, "__curl_ptr", .{ .int = 0 }) catch {};
    }
}

fn curlError(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const obj = getThisObj(args) orelse return .{ .string = "" };
    return obj.get("__error");
}

fn curlErrno(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
    const obj = getThisObj(args) orelse return .{ .int = 0 };
    return obj.get("__errno");
}

fn curlGetinfo(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    const obj = getThisObj(args) orelse return .{ .bool = false };
    const handle = getHandle(obj) orelse return .{ .bool = false };

    // no specific option - return all info as array
    if (args.len < 2 or args[1] == .null) {
        return getAllInfo(ctx, handle);
    }

    if (args[1] != .int) return .{ .bool = false };
    const option = args[1].int;
    return getInfoOption(ctx, handle, option);
}

fn getInfoOption(ctx: *NativeContext, handle: *c.CURL, option: i64) RuntimeError!Value {
    // string info types
    if (option == c.CURLINFO_EFFECTIVE_URL or
        option == c.CURLINFO_CONTENT_TYPE or
        option == c.CURLINFO_REDIRECT_URL or
        option == c.CURLINFO_PRIMARY_IP or
        option == c.CURLINFO_LOCAL_IP or
        option == c.CURLINFO_SCHEME)
    {
        var ptr: [*c]u8 = null;
        const code: c_uint = @intCast(c.curl_easy_getinfo(handle, @intCast(option), &ptr));
        if (code != c.CURLE_OK or ptr == null) return .{ .bool = false };
        const s = std.mem.span(ptr);
        const owned = try ctx.createString(s);
        return .{ .string = owned };
    }

    // long info types
    if (option == c.CURLINFO_RESPONSE_CODE or
        option == c.CURLINFO_HTTP_CONNECTCODE or
        option == c.CURLINFO_FILETIME or
        option == c.CURLINFO_REDIRECT_COUNT or
        option == c.CURLINFO_HEADER_SIZE or
        option == c.CURLINFO_REQUEST_SIZE or
        option == c.CURLINFO_SSL_VERIFYRESULT or
        option == c.CURLINFO_PRIMARY_PORT or
        option == c.CURLINFO_LOCAL_PORT)
    {
        var val: c_long = 0;
        const code: c_uint = @intCast(c.curl_easy_getinfo(handle, @intCast(option), &val));
        if (code != c.CURLE_OK) return .{ .bool = false };
        return .{ .int = @intCast(val) };
    }

    // double info types
    if (option == c.CURLINFO_TOTAL_TIME or
        option == c.CURLINFO_NAMELOOKUP_TIME or
        option == c.CURLINFO_CONNECT_TIME or
        option == c.CURLINFO_PRETRANSFER_TIME or
        option == c.CURLINFO_STARTTRANSFER_TIME or
        option == c.CURLINFO_REDIRECT_TIME or
        option == c.CURLINFO_SIZE_UPLOAD_T or
        option == c.CURLINFO_SIZE_DOWNLOAD_T or
        option == c.CURLINFO_SPEED_UPLOAD_T or
        option == c.CURLINFO_SPEED_DOWNLOAD_T or
        option == c.CURLINFO_CONTENT_LENGTH_DOWNLOAD or
        option == c.CURLINFO_CONTENT_LENGTH_UPLOAD)
    {
        var val: f64 = 0;
        const code: c_uint = @intCast(c.curl_easy_getinfo(handle, @intCast(option), &val));
        if (code != c.CURLE_OK) return .{ .bool = false };
        return .{ .float = val };
    }

    return .{ .bool = false };
}

fn getAllInfo(ctx: *NativeContext, handle: *c.CURL) RuntimeError!Value {
    const arr = try ctx.createArray();

    var url_ptr: [*c]u8 = null;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_EFFECTIVE_URL, &url_ptr) == c.CURLE_OK) {
        if (url_ptr != null) {
            const s = try ctx.createString(std.mem.span(url_ptr));
            try arr.set(ctx.allocator, .{ .string = "url" }, .{ .string = s });
        }
    }

    var content_type_ptr: [*c]u8 = null;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_CONTENT_TYPE, &content_type_ptr) == c.CURLE_OK) {
        if (content_type_ptr != null) {
            const s = try ctx.createString(std.mem.span(content_type_ptr));
            try arr.set(ctx.allocator, .{ .string = "content_type" }, .{ .string = s });
        } else {
            try arr.set(ctx.allocator, .{ .string = "content_type" }, .null);
        }
    }

    var http_code: c_long = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_RESPONSE_CODE, &http_code) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = "http_code" }, .{ .int = @intCast(http_code) });

    var header_size: c_long = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_HEADER_SIZE, &header_size) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = "header_size" }, .{ .int = @intCast(header_size) });

    var request_size: c_long = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_REQUEST_SIZE, &request_size) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = "request_size" }, .{ .int = @intCast(request_size) });

    var redirect_count: c_long = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_REDIRECT_COUNT, &redirect_count) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = "redirect_count" }, .{ .int = @intCast(redirect_count) });

    var total_time: f64 = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_TOTAL_TIME, &total_time) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = "total_time" }, .{ .float = total_time });

    var namelookup_time: f64 = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_NAMELOOKUP_TIME, &namelookup_time) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = "namelookup_time" }, .{ .float = namelookup_time });

    var connect_time: f64 = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_CONNECT_TIME, &connect_time) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = "connect_time" }, .{ .float = connect_time });

    var pretransfer_time: f64 = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_PRETRANSFER_TIME, &pretransfer_time) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = "pretransfer_time" }, .{ .float = pretransfer_time });

    var starttransfer_time: f64 = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_STARTTRANSFER_TIME, &starttransfer_time) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = "starttransfer_time" }, .{ .float = starttransfer_time });

    var redirect_time: f64 = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_REDIRECT_TIME, &redirect_time) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = "redirect_time" }, .{ .float = redirect_time });

    var primary_ip_ptr: [*c]u8 = null;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_PRIMARY_IP, &primary_ip_ptr) == c.CURLE_OK) {
        if (primary_ip_ptr != null) {
            const s = try ctx.createString(std.mem.span(primary_ip_ptr));
            try arr.set(ctx.allocator, .{ .string = "primary_ip" }, .{ .string = s });
        }
    }

    var primary_port: c_long = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_PRIMARY_PORT, &primary_port) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = "primary_port" }, .{ .int = @intCast(primary_port) });

    var ssl_verify: c_long = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_SSL_VERIFYRESULT, &ssl_verify) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = "ssl_verify_result" }, .{ .int = @intCast(ssl_verify) });

    var scheme_ptr: [*c]u8 = null;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_SCHEME, &scheme_ptr) == c.CURLE_OK) {
        if (scheme_ptr != null) {
            const s = try ctx.createString(std.mem.span(scheme_ptr));
            try arr.set(ctx.allocator, .{ .string = "scheme" }, .{ .string = s });
        }
    }

    return .{ .array = arr };
}

fn curlReset(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .null;
    const obj = getThisObj(args) orelse return .null;
    const handle = getHandle(obj) orelse return .null;
    c.curl_easy_reset(handle);
    try obj.set(ctx.allocator, "__return_transfer", .{ .bool = false });
    try obj.set(ctx.allocator, "__header_out", .{ .bool = false });
    try obj.set(ctx.allocator, "__error", .{ .string = "" });
    try obj.set(ctx.allocator, "__errno", .{ .int = 0 });
    try obj.set(ctx.allocator, "__http_code", .{ .int = 0 });

    // free slist
    const slist_v = obj.get("__slist_ptr");
    if (slist_v == .int and slist_v.int != 0) {
        const sl: *c.struct_curl_slist = @ptrFromInt(@as(usize, @intCast(slist_v.int)));
        c.curl_slist_free_all(sl);
        try obj.set(ctx.allocator, "__slist_ptr", .{ .int = 0 });
    }

    return .null;
}

fn curlVersion(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const info = c.curl_version_info(c.CURLVERSION_NOW) orelse return .{ .bool = false };
    const arr = try ctx.createArray();

    if (info.*.version) |ver| {
        const s = try ctx.createString(std.mem.span(ver));
        try arr.set(ctx.allocator, .{ .string = "version" }, .{ .string = s });
    }
    try arr.set(ctx.allocator, .{ .string = "version_number" }, .{ .int = @intCast(info.*.version_num) });
    if (info.*.host) |host| {
        const s = try ctx.createString(std.mem.span(host));
        try arr.set(ctx.allocator, .{ .string = "host" }, .{ .string = s });
    }
    if (info.*.ssl_version) |ssl| {
        const s = try ctx.createString(std.mem.span(ssl));
        try arr.set(ctx.allocator, .{ .string = "ssl_version" }, .{ .string = s });
    }
    if (info.*.libz_version) |zlib| {
        const s = try ctx.createString(std.mem.span(zlib));
        try arr.set(ctx.allocator, .{ .string = "libz_version" }, .{ .string = s });
    }

    return .{ .array = arr };
}

pub fn register(vm: *VM, a: std.mem.Allocator) !void {
    var curl_def = ClassDef{ .name = "CurlHandle" };
    try vm.classes.put(a, "CurlHandle", curl_def);
    _ = &curl_def;

    // CURLOPT constants
    try vm.php_constants.put(a, "CURLOPT_URL", .{ .int = c.CURLOPT_URL });
    try vm.php_constants.put(a, "CURLOPT_PORT", .{ .int = c.CURLOPT_PORT });
    try vm.php_constants.put(a, "CURLOPT_RETURNTRANSFER", .{ .int = 19913 });
    try vm.php_constants.put(a, "CURLOPT_FOLLOWLOCATION", .{ .int = c.CURLOPT_FOLLOWLOCATION });
    try vm.php_constants.put(a, "CURLOPT_MAXREDIRS", .{ .int = c.CURLOPT_MAXREDIRS });
    try vm.php_constants.put(a, "CURLOPT_POST", .{ .int = c.CURLOPT_POST });
    try vm.php_constants.put(a, "CURLOPT_POSTFIELDS", .{ .int = c.CURLOPT_POSTFIELDS });
    try vm.php_constants.put(a, "CURLOPT_HTTPHEADER", .{ .int = c.CURLOPT_HTTPHEADER });
    try vm.php_constants.put(a, "CURLOPT_USERAGENT", .{ .int = c.CURLOPT_USERAGENT });
    try vm.php_constants.put(a, "CURLOPT_REFERER", .{ .int = c.CURLOPT_REFERER });
    try vm.php_constants.put(a, "CURLOPT_COOKIE", .{ .int = c.CURLOPT_COOKIE });
    try vm.php_constants.put(a, "CURLOPT_COOKIEFILE", .{ .int = c.CURLOPT_COOKIEFILE });
    try vm.php_constants.put(a, "CURLOPT_COOKIEJAR", .{ .int = c.CURLOPT_COOKIEJAR });
    try vm.php_constants.put(a, "CURLOPT_USERPWD", .{ .int = c.CURLOPT_USERPWD });
    try vm.php_constants.put(a, "CURLOPT_TIMEOUT", .{ .int = c.CURLOPT_TIMEOUT });
    try vm.php_constants.put(a, "CURLOPT_TIMEOUT_MS", .{ .int = c.CURLOPT_TIMEOUT_MS });
    try vm.php_constants.put(a, "CURLOPT_CONNECTTIMEOUT", .{ .int = c.CURLOPT_CONNECTTIMEOUT });
    try vm.php_constants.put(a, "CURLOPT_CONNECTTIMEOUT_MS", .{ .int = c.CURLOPT_CONNECTTIMEOUT_MS });
    try vm.php_constants.put(a, "CURLOPT_SSL_VERIFYPEER", .{ .int = c.CURLOPT_SSL_VERIFYPEER });
    try vm.php_constants.put(a, "CURLOPT_SSL_VERIFYHOST", .{ .int = c.CURLOPT_SSL_VERIFYHOST });
    try vm.php_constants.put(a, "CURLOPT_CUSTOMREQUEST", .{ .int = c.CURLOPT_CUSTOMREQUEST });
    try vm.php_constants.put(a, "CURLOPT_HEADER", .{ .int = c.CURLOPT_HEADER });
    try vm.php_constants.put(a, "CURLOPT_NOBODY", .{ .int = c.CURLOPT_NOBODY });
    try vm.php_constants.put(a, "CURLOPT_PUT", .{ .int = c.CURLOPT_PUT });
    try vm.php_constants.put(a, "CURLOPT_ENCODING", .{ .int = c.CURLOPT_ENCODING });
    try vm.php_constants.put(a, "CURLOPT_VERBOSE", .{ .int = c.CURLOPT_VERBOSE });
    try vm.php_constants.put(a, "CURLOPT_FAILONERROR", .{ .int = c.CURLOPT_FAILONERROR });
    try vm.php_constants.put(a, "CURLOPT_FRESH_CONNECT", .{ .int = c.CURLOPT_FRESH_CONNECT });
    try vm.php_constants.put(a, "CURLOPT_FORBID_REUSE", .{ .int = c.CURLOPT_FORBID_REUSE });
    try vm.php_constants.put(a, "CURLOPT_TCP_NODELAY", .{ .int = c.CURLOPT_TCP_NODELAY });
    try vm.php_constants.put(a, "CURLOPT_PROXY", .{ .int = c.CURLOPT_PROXY });
    try vm.php_constants.put(a, "CURLOPT_PROXYPORT", .{ .int = c.CURLOPT_PROXYPORT });
    try vm.php_constants.put(a, "CURLOPT_PROXYTYPE", .{ .int = c.CURLOPT_PROXYTYPE });
    try vm.php_constants.put(a, "CURLOPT_PROXYUSERPWD", .{ .int = c.CURLOPT_PROXYUSERPWD });
    try vm.php_constants.put(a, "CURLOPT_HTTPAUTH", .{ .int = c.CURLOPT_HTTPAUTH });
    try vm.php_constants.put(a, "CURLOPT_SSLVERSION", .{ .int = c.CURLOPT_SSLVERSION });
    try vm.php_constants.put(a, "CURLOPT_CAINFO", .{ .int = c.CURLOPT_CAINFO });
    try vm.php_constants.put(a, "CURLOPT_CAPATH", .{ .int = c.CURLOPT_CAPATH });
    try vm.php_constants.put(a, "CURLOPT_SSLCERT", .{ .int = c.CURLOPT_SSLCERT });
    try vm.php_constants.put(a, "CURLOPT_SSLKEY", .{ .int = c.CURLOPT_SSLKEY });
    try vm.php_constants.put(a, "CURLOPT_RANGE", .{ .int = c.CURLOPT_RANGE });
    try vm.php_constants.put(a, "CURLOPT_INTERFACE", .{ .int = c.CURLOPT_INTERFACE });
    try vm.php_constants.put(a, "CURLOPT_UNIX_SOCKET_PATH", .{ .int = c.CURLOPT_UNIX_SOCKET_PATH });

    // CURLINFO constants
    try vm.php_constants.put(a, "CURLINFO_EFFECTIVE_URL", .{ .int = c.CURLINFO_EFFECTIVE_URL });
    try vm.php_constants.put(a, "CURLINFO_HTTP_CODE", .{ .int = c.CURLINFO_RESPONSE_CODE });
    try vm.php_constants.put(a, "CURLINFO_RESPONSE_CODE", .{ .int = c.CURLINFO_RESPONSE_CODE });
    try vm.php_constants.put(a, "CURLINFO_CONTENT_TYPE", .{ .int = c.CURLINFO_CONTENT_TYPE });
    try vm.php_constants.put(a, "CURLINFO_HEADER_SIZE", .{ .int = c.CURLINFO_HEADER_SIZE });
    try vm.php_constants.put(a, "CURLINFO_REQUEST_SIZE", .{ .int = c.CURLINFO_REQUEST_SIZE });
    try vm.php_constants.put(a, "CURLINFO_REDIRECT_COUNT", .{ .int = c.CURLINFO_REDIRECT_COUNT });
    try vm.php_constants.put(a, "CURLINFO_REDIRECT_URL", .{ .int = c.CURLINFO_REDIRECT_URL });
    try vm.php_constants.put(a, "CURLINFO_TOTAL_TIME", .{ .int = c.CURLINFO_TOTAL_TIME });
    try vm.php_constants.put(a, "CURLINFO_NAMELOOKUP_TIME", .{ .int = c.CURLINFO_NAMELOOKUP_TIME });
    try vm.php_constants.put(a, "CURLINFO_CONNECT_TIME", .{ .int = c.CURLINFO_CONNECT_TIME });
    try vm.php_constants.put(a, "CURLINFO_PRETRANSFER_TIME", .{ .int = c.CURLINFO_PRETRANSFER_TIME });
    try vm.php_constants.put(a, "CURLINFO_STARTTRANSFER_TIME", .{ .int = c.CURLINFO_STARTTRANSFER_TIME });
    try vm.php_constants.put(a, "CURLINFO_REDIRECT_TIME", .{ .int = c.CURLINFO_REDIRECT_TIME });
    try vm.php_constants.put(a, "CURLINFO_PRIMARY_IP", .{ .int = c.CURLINFO_PRIMARY_IP });
    try vm.php_constants.put(a, "CURLINFO_PRIMARY_PORT", .{ .int = c.CURLINFO_PRIMARY_PORT });
    try vm.php_constants.put(a, "CURLINFO_SSL_VERIFYRESULT", .{ .int = c.CURLINFO_SSL_VERIFYRESULT });
    try vm.php_constants.put(a, "CURLINFO_CONTENT_LENGTH_DOWNLOAD", .{ .int = c.CURLINFO_CONTENT_LENGTH_DOWNLOAD });
    try vm.php_constants.put(a, "CURLINFO_CONTENT_LENGTH_UPLOAD", .{ .int = c.CURLINFO_CONTENT_LENGTH_UPLOAD });
    try vm.php_constants.put(a, "CURLINFO_SCHEME", .{ .int = c.CURLINFO_SCHEME });
    try vm.php_constants.put(a, "CURLINFO_HEADER_OUT", .{ .int = c.CURLINFO_HEADER_OUT });

    // CURLAUTH constants
    try vm.php_constants.put(a, "CURLAUTH_BASIC", .{ .int = c.CURLAUTH_BASIC });
    try vm.php_constants.put(a, "CURLAUTH_DIGEST", .{ .int = c.CURLAUTH_DIGEST });
    try vm.php_constants.put(a, "CURLAUTH_BEARER", .{ .int = c.CURLAUTH_BEARER });

    // CURL_HTTP_VERSION constants
    try vm.php_constants.put(a, "CURL_HTTP_VERSION_NONE", .{ .int = 0 });
    try vm.php_constants.put(a, "CURL_HTTP_VERSION_1_0", .{ .int = 1 });
    try vm.php_constants.put(a, "CURL_HTTP_VERSION_1_1", .{ .int = 2 });
    try vm.php_constants.put(a, "CURL_HTTP_VERSION_2_0", .{ .int = 3 });

    // error code constants
    try vm.php_constants.put(a, "CURLE_OK", .{ .int = c.CURLE_OK });
    try vm.php_constants.put(a, "CURLE_UNSUPPORTED_PROTOCOL", .{ .int = c.CURLE_UNSUPPORTED_PROTOCOL });
    try vm.php_constants.put(a, "CURLE_URL_MALFORMAT", .{ .int = c.CURLE_URL_MALFORMAT });
    try vm.php_constants.put(a, "CURLE_COULDNT_RESOLVE_HOST", .{ .int = c.CURLE_COULDNT_RESOLVE_HOST });
    try vm.php_constants.put(a, "CURLE_COULDNT_CONNECT", .{ .int = c.CURLE_COULDNT_CONNECT });
    try vm.php_constants.put(a, "CURLE_OPERATION_TIMEDOUT", .{ .int = c.CURLE_OPERATION_TIMEDOUT });
    try vm.php_constants.put(a, "CURLE_SSL_CONNECT_ERROR", .{ .int = c.CURLE_SSL_CONNECT_ERROR });
}

pub fn cleanupResources(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    for (objects.items) |obj| {
        if (std.mem.eql(u8, obj.class_name, "CurlHandle")) {
            cleanupHandle(obj);
        }
    }
}
