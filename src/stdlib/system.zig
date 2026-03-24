const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
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

fn native_sleep(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
    const secs = Value.toInt(args[0]);
    if (secs > 0) std.Thread.sleep(@intCast(secs * 1_000_000_000));
    return .{ .int = 0 };
}

fn native_usleep(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .null;
    const usecs = Value.toInt(args[0]);
    if (usecs > 0) std.Thread.sleep(@intCast(usecs * 1_000));
    return .null;
}

fn native_getenv(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const val = std.process.getEnvVarOwned(ctx.allocator, args[0].string) catch return Value{ .bool = false };
    try ctx.strings.append(ctx.allocator, val);
    return .{ .string = val };
}

fn native_putenv(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    return .{ .bool = true };
}

fn native_uniqid(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const prefix = if (args.len >= 1 and args[0] == .string) args[0].string else "";
    const ns = std.time.nanoTimestamp();
    const abs_ns: u64 = @intCast(if (ns < 0) -ns else ns);
    const usec: u64 = @divTrunc(@mod(abs_ns, 1_000_000_000), 1_000);
    const sec: u64 = @divTrunc(abs_ns, 1_000_000_000);
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
    const is_mac = @import("builtin").os.tag == .macos;
    const is_arm = @import("builtin").cpu.arch == .aarch64;
    return .{ .string = switch (mode) {
        's' => if (is_mac) "Darwin" else "Linux",
        'n' => "localhost",
        'r' => "0.0.0",
        'm' => if (is_arm) "arm64" else "x86_64",
        else => if (is_mac) "Darwin localhost 0.0.0 arm64" else "Linux localhost 0.0.0 x86_64",
    } };
}

fn native_move_uploaded_file(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const from = args[0].string;
    const to = args[1].string;
    if (!std.mem.startsWith(u8, from, "/tmp/zphp_upload_")) return .{ .bool = false };
    std.fs.cwd().rename(from, to) catch {
        const data = std.fs.cwd().readFileAlloc(std.heap.page_allocator, from, 1024 * 1024 * 64) catch return .{ .bool = false };
        defer std.heap.page_allocator.free(data);
        std.fs.cwd().writeFile(.{ .sub_path = to, .data = data }) catch return .{ .bool = false };
        std.fs.cwd().deleteFile(from) catch {};
    };
    return .{ .bool = true };
}

fn native_is_uploaded_file(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    if (!std.mem.startsWith(u8, args[0].string, "/tmp/zphp_upload_")) return .{ .bool = false };
    std.fs.cwd().access(args[0].string, .{}) catch return .{ .bool = false };
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
    const ts: u64 = @intCast(std.time.milliTimestamp());
    var ts_buf: [20]u8 = undefined;
    const ts_str = std.fmt.bufPrint(&ts_buf, "{d}", .{ts}) catch "0";
    try buf.appendSlice(ctx.allocator, ts_str);
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}
