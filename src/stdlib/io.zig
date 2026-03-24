const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "file_get_contents", file_get_contents },
    .{ "file_put_contents", file_put_contents },
    .{ "file_exists", file_exists },
    .{ "is_file", native_is_file },
    .{ "is_dir", native_is_dir },
    .{ "basename", native_basename },
    .{ "dirname", native_dirname },
    .{ "pathinfo", native_pathinfo },
    .{ "realpath", native_realpath },
    .{ "ob_start", native_ob_start },
    .{ "ob_get_clean", native_ob_get_clean },
    .{ "ob_end_clean", native_ob_end_clean },
    .{ "ob_get_contents", native_ob_get_contents },
    .{ "ob_get_level", native_ob_get_level },
    .{ "header", native_header },
    .{ "http_response_code", native_http_response_code },
    .{ "sleep", native_sleep },
    .{ "usleep", native_usleep },
    .{ "getenv", native_getenv },
    .{ "putenv", native_putenv },
    .{ "uniqid", native_uniqid },
    .{ "getcwd", native_getcwd },
    .{ "php_uname", native_php_uname },
    .{ "move_uploaded_file", native_move_uploaded_file },
    .{ "is_uploaded_file", native_is_uploaded_file },
    .{ "sys_get_temp_dir", native_sys_get_temp_dir },
    .{ "tempnam", native_tempnam },
};

fn file_get_contents(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const path = args[0].string;
    const content = std.fs.cwd().readFileAlloc(ctx.allocator, path, 1024 * 1024 * 64) catch return Value{ .bool = false };
    try ctx.strings.append(ctx.allocator, content);
    return .{ .string = content };
}

fn file_put_contents(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string) return .{ .bool = false };
    const path = args[0].string;
    const data = if (args[1] == .string) args[1].string else blk: {
        var buf = std.ArrayListUnmanaged(u8){};
        try args[1].format(&buf, ctx.allocator);
        const s = try buf.toOwnedSlice(ctx.allocator);
        try ctx.strings.append(ctx.allocator, s);
        break :blk s;
    };
    std.fs.cwd().writeFile(.{ .sub_path = path, .data = data }) catch return Value{ .bool = false };
    return .{ .int = @intCast(data.len) };
}

fn file_exists(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    std.fs.cwd().access(args[0].string, .{}) catch return Value{ .bool = false };
    return .{ .bool = true };
}

fn native_is_file(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const stat = std.fs.cwd().statFile(args[0].string) catch return Value{ .bool = false };
    return .{ .bool = stat.kind == .file };
}

fn native_is_dir(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    var dir = std.fs.cwd().openDir(args[0].string, .{}) catch return Value{ .bool = false };
    dir.close();
    return .{ .bool = true };
}

fn native_basename(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .string = "" };
    const path = args[0].string;
    if (std.mem.lastIndexOf(u8, path, "/")) |pos| {
        return .{ .string = try ctx.createString(path[pos + 1 ..]) };
    }
    return args[0];
}

fn native_dirname(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .string = "" };
    const path = args[0].string;
    if (std.mem.lastIndexOf(u8, path, "/")) |pos| {
        if (pos == 0) return .{ .string = "/" };
        return .{ .string = try ctx.createString(path[0..pos]) };
    }
    return .{ .string = "." };
}

fn native_pathinfo(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .null;
    const path = args[0].string;
    var arr = try ctx.createArray();

    const dir = if (std.mem.lastIndexOf(u8, path, "/")) |pos| blk: {
        break :blk if (pos == 0) "/" else try ctx.createString(path[0..pos]);
    } else ".";
    try arr.set(ctx.allocator, .{ .string = "dirname" }, .{ .string = dir });

    const base = if (std.mem.lastIndexOf(u8, path, "/")) |pos| try ctx.createString(path[pos + 1 ..]) else path;
    try arr.set(ctx.allocator, .{ .string = "basename" }, .{ .string = base });

    if (std.mem.lastIndexOf(u8, base, ".")) |dot| {
        try arr.set(ctx.allocator, .{ .string = "extension" }, .{ .string = try ctx.createString(base[dot + 1 ..]) });
        try arr.set(ctx.allocator, .{ .string = "filename" }, .{ .string = try ctx.createString(base[0..dot]) });
    } else {
        try arr.set(ctx.allocator, .{ .string = "extension" }, .{ .string = "" });
        try arr.set(ctx.allocator, .{ .string = "filename" }, .{ .string = base });
    }
    return .{ .array = arr };
}

fn native_realpath(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const resolved = std.fs.cwd().realpath(args[0].string, &buf) catch return Value{ .bool = false };
    return .{ .string = try ctx.createString(resolved) };
}


fn native_header(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .null;
    const hdr = args[0].string;

    // check for Content-Type header specifically
    if (io_startsWith(hdr, "Content-Type:") or io_startsWith(hdr, "content-type:")) {
        if (std.mem.indexOf(u8, hdr, ": ")) |sep| {
            try ctx.vm.currentFrame().vars.put(ctx.allocator, "__response_content_type", .{ .string = hdr[sep + 2 ..] });
        }
    }

    // store all headers in a response headers array
    const key = "__response_headers";
    const existing = ctx.vm.currentFrame().vars.get(key);
    if (existing != null and existing.? == .array) {
        try existing.?.array.append(ctx.allocator, .{ .string = hdr });
    } else {
        const arr = try ctx.createArray();
        try arr.append(ctx.allocator, .{ .string = hdr });
        try ctx.vm.currentFrame().vars.put(ctx.allocator, key, .{ .array = arr });
    }
    return .null;
}

fn io_startsWith(s: []const u8, prefix: []const u8) bool {
    return s.len >= prefix.len and std.ascii.eqlIgnoreCase(s[0..prefix.len], prefix);
}

fn native_http_response_code(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len >= 1 and args[0] == .int) {
        try ctx.vm.currentFrame().vars.put(ctx.allocator, "__response_code", args[0]);
    }
    const code = ctx.vm.currentFrame().vars.get("__response_code") orelse Value{ .int = 200 };
    return code;
}

fn native_ob_start(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    try ctx.vm.ob_stack.append(ctx.allocator, ctx.vm.output.items.len);
    return .{ .bool = true };
}

fn native_ob_get_clean(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    if (ctx.vm.ob_stack.items.len == 0) return .{ .bool = false };
    const start = ctx.vm.ob_stack.pop().?;
    const content = try ctx.createString(ctx.vm.output.items[start..]);
    ctx.vm.output.shrinkRetainingCapacity(start);
    return .{ .string = content };
}

fn native_ob_end_clean(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    if (ctx.vm.ob_stack.items.len == 0) return .{ .bool = false };
    const start = ctx.vm.ob_stack.pop().?;
    ctx.vm.output.shrinkRetainingCapacity(start);
    return .{ .bool = true };
}

fn native_ob_get_contents(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    if (ctx.vm.ob_stack.items.len == 0) return .{ .bool = false };
    const start = ctx.vm.ob_stack.getLast();
    return .{ .string = try ctx.createString(ctx.vm.output.items[start..]) };
}

fn native_ob_get_level(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = @intCast(ctx.vm.ob_stack.items.len) };
}


fn native_sleep(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
    const secs = Value.toInt(args[0]);
    if (secs > 0) {
        std.Thread.sleep(@intCast(secs * 1_000_000_000));
    }
    return .{ .int = 0 };
}

fn native_usleep(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .null;
    const usecs = Value.toInt(args[0]);
    if (usecs > 0) {
        std.Thread.sleep(@intCast(usecs * 1_000));
    }
    return .null;
}

fn native_getenv(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const name = args[0].string;
    const val = std.process.getEnvVarOwned(ctx.allocator, name) catch return Value{ .bool = false };
    try ctx.strings.append(ctx.allocator, val);
    return .{ .string = val };
}

fn native_putenv(_: *NativeContext, args: []const Value) RuntimeError!Value {
    // putenv("KEY=VALUE") - we parse but can't actually set env in zig safely
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    return .{ .bool = true };
}

fn native_uniqid(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const prefix = if (args.len >= 1 and args[0] == .string) args[0].string else "";
    const ns = std.time.nanoTimestamp();
    const usec: u64 = @intCast(@divTrunc(@mod(if (ns < 0) -ns else ns, 1_000_000_000), 1_000));
    const sec: u64 = @intCast(@divTrunc(if (ns < 0) -ns else ns, 1_000_000_000));
    var buf: [64]u8 = undefined;
    const hex = std.fmt.bufPrint(&buf, "{s}{x:0>8}{x:0>5}", .{ prefix, sec, usec }) catch return Value{ .string = "" };
    return .{ .string = try ctx.createString(hex) };
}

fn native_getcwd(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = std.fs.cwd().realpath(".", &buf) catch return Value{ .bool = false };
    return .{ .string = try ctx.createString(cwd) };
}

fn native_php_uname(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const mode = if (args.len >= 1 and args[0] == .string and args[0].string.len > 0) args[0].string[0] else 'a';
    return .{ .string = switch (mode) {
        's' => if (@import("builtin").os.tag == .macos) "Darwin" else "Linux",
        'n' => "localhost",
        'r' => "0.0.0",
        'm' => if (@import("builtin").cpu.arch == .aarch64) "arm64" else "x86_64",
        else => if (@import("builtin").os.tag == .macos) "Darwin localhost 0.0.0 arm64" else "Linux localhost 0.0.0 x86_64",
    } };
}

fn native_move_uploaded_file(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const from = args[0].string;
    const to = args[1].string;
    if (!std.mem.startsWith(u8, from, "/tmp/zphp_upload_")) return .{ .bool = false };
    std.fs.cwd().rename(from, to) catch {
        // cross-device: copy then delete
        const data = std.fs.cwd().readFileAlloc(std.heap.page_allocator, from, 1024 * 1024 * 64) catch return .{ .bool = false };
        defer std.heap.page_allocator.free(data);
        std.fs.cwd().writeFile(.{ .sub_path = to, .data = data }) catch return .{ .bool = false };
        std.fs.cwd().deleteFile(from) catch {};
    };
    return .{ .bool = true };
}

fn native_is_uploaded_file(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const path = args[0].string;
    if (!std.mem.startsWith(u8, path, "/tmp/zphp_upload_")) return .{ .bool = false };
    std.fs.cwd().access(path, .{}) catch return .{ .bool = false };
    return .{ .bool = true };
}

fn native_sys_get_temp_dir(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .string = "/tmp" };
}

fn native_tempnam(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const dir = if (args.len >= 1 and args[0] == .string) args[0].string else "/tmp";
    const prefix = if (args.len >= 2 and args[1] == .string) args[1].string else "tmp";
    var buf = std.ArrayListUnmanaged(u8){};
    try buf.appendSlice(ctx.allocator, dir);
    if (dir.len > 0 and dir[dir.len - 1] != '/') try buf.append(ctx.allocator, '/');
    try buf.appendSlice(ctx.allocator, prefix);
    // simple unique suffix from timestamp
    const ts: u64 = @intCast(std.time.milliTimestamp());
    var ts_buf: [20]u8 = undefined;
    const ts_str = std.fmt.bufPrint(&ts_buf, "{d}", .{ts}) catch "0";
    try buf.appendSlice(ctx.allocator, ts_str);
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}
