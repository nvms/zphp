const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const VM = @import("../runtime/vm.zig").VM;
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
    .{ "debug_backtrace", native_debug_backtrace },
    .{ "debug_print_backtrace", native_debug_print_backtrace },
    .{ "get_defined_functions", native_get_defined_functions },
    .{ "get_defined_vars", native_get_defined_vars },
    .{ "get_defined_classes", native_get_defined_classes },
    .{ "set_time_limit", native_set_time_limit },
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

fn buildBacktrace(ctx: *NativeContext, ignore_args: bool, limit: usize) RuntimeError!*PhpArray {
    const vm = ctx.vm;
    const alloc = ctx.allocator;
    var result = try ctx.createArray();

    if (vm.frame_count <= 1) return result;

    const max = if (limit > 0) @min(limit, vm.frame_count - 1) else vm.frame_count - 1;
    var count: usize = 0;
    var i: usize = vm.frame_count - 1;

    while (i >= 1 and count < max) : ({
        i -= 1;
        count += 1;
    }) {
        var entry = try ctx.createArray();
        try entry.set(alloc, .{ .string = "file" }, .{ .string = vm.file_path });

        const caller = &vm.frames[i - 1];
        if (caller.chunk.getSourceLocation(caller.ip, vm.source)) |loc| {
            try entry.set(alloc, .{ .string = "line" }, .{ .int = @intCast(loc.line) });
        }

        const frame = &vm.frames[i];
        if (frame.func) |func| {
            if (std.mem.indexOf(u8, func.name, "::")) |sep| {
                try entry.set(alloc, .{ .string = "class" }, .{ .string = func.name[0..sep] });
                try entry.set(alloc, .{ .string = "function" }, .{ .string = func.name[sep + 2 ..] });
                try entry.set(alloc, .{ .string = "type" }, .{ .string = "->" });
            } else {
                try entry.set(alloc, .{ .string = "function" }, .{ .string = func.name });
                if (frame.called_class) |cls| {
                    try entry.set(alloc, .{ .string = "class" }, .{ .string = cls });
                    try entry.set(alloc, .{ .string = "type" }, .{ .string = "->" });
                }
            }
        }

        if (!ignore_args) {
            var args_arr = try ctx.createArray();
            if (vm.ic) |ic| {
                const ac = ic.arg_counts[i];
                if (ac != 0xFF) {
                    const offset: usize = ic.fga_offsets[i];
                    const arg_count: usize = ac;
                    if (offset + arg_count <= 256) {
                        for (0..arg_count) |a| {
                            try args_arr.append(alloc, ic.fga_buf[offset + a]);
                        }
                    }
                }
            }
            try entry.set(alloc, .{ .string = "args" }, .{ .array = args_arr });
        }

        try result.append(alloc, .{ .array = entry });
    }

    return result;
}

fn native_debug_backtrace(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const options = if (args.len >= 1) Value.toInt(args[0]) else 0;
    const limit_raw = if (args.len >= 2) Value.toInt(args[1]) else 0;
    const ignore_args = (options & 2) != 0;
    const limit: usize = if (limit_raw > 0) @intCast(limit_raw) else 0;
    return .{ .array = try buildBacktrace(ctx, ignore_args, limit) };
}

fn native_debug_print_backtrace(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const options = if (args.len >= 1) Value.toInt(args[0]) else 0;
    const limit_raw = if (args.len >= 2) Value.toInt(args[1]) else 0;
    const ignore_args = (options & 2) != 0;
    const limit: usize = if (limit_raw > 0) @intCast(limit_raw) else 0;
    const trace = try buildBacktrace(ctx, ignore_args, limit);

    const out = &ctx.vm.output;
    const alloc = ctx.allocator;
    for (trace.entries.items, 0..) |entry, idx| {
        const arr = entry.value.array;
        const func = arr.get(.{ .string = "function" });
        const file = arr.get(.{ .string = "file" });
        const line = arr.get(.{ .string = "line" });
        var num_buf: [20]u8 = undefined;
        const num_str = std.fmt.bufPrint(&num_buf, "{d}", .{idx}) catch "0";
        try out.appendSlice(alloc, "#");
        try out.appendSlice(alloc, num_str);
        try out.appendSlice(alloc, " ");
        if (file == .string) {
            try out.appendSlice(alloc, file.string);
            if (line == .int) {
                try out.appendSlice(alloc, "(");
                var line_buf: [20]u8 = undefined;
                const line_str = std.fmt.bufPrint(&line_buf, "{d}", .{line.int}) catch "0";
                try out.appendSlice(alloc, line_str);
                try out.appendSlice(alloc, ")");
            }
            try out.appendSlice(alloc, ": ");
        }
        try out.appendSlice(alloc, if (func == .string) func.string else "{main}");
        try out.appendSlice(alloc, "()\n");
    }
    return .null;
}

fn native_get_defined_functions(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const vm = ctx.vm;
    const alloc = ctx.allocator;
    var result = try ctx.createArray();

    var internal = try ctx.createArray();
    var iter_n = vm.native_fns.iterator();
    while (iter_n.next()) |entry| {
        try internal.append(alloc, .{ .string = entry.key_ptr.* });
    }

    var user = try ctx.createArray();
    var iter_u = vm.functions.iterator();
    while (iter_u.next()) |entry| {
        try user.append(alloc, .{ .string = entry.key_ptr.* });
    }

    try result.set(alloc, .{ .string = "internal" }, .{ .array = internal });
    try result.set(alloc, .{ .string = "user" }, .{ .array = user });
    return .{ .array = result };
}

fn native_get_defined_vars(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const vm = ctx.vm;
    const alloc = ctx.allocator;
    var result = try ctx.createArray();

    if (vm.frame_count == 0) return .{ .array = result };
    const frame = &vm.frames[vm.frame_count - 1];
    var iter = frame.vars.iterator();
    while (iter.next()) |entry| {
        const name = entry.key_ptr.*;
        if (name.len > 0 and name[0] == '$') continue;
        try result.set(alloc, .{ .string = name }, entry.value_ptr.*);
    }
    return .{ .array = result };
}

fn native_get_defined_classes(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const vm = ctx.vm;
    const alloc = ctx.allocator;
    var result = try ctx.createArray();

    var iter = vm.classes.iterator();
    while (iter.next()) |entry| {
        try result.append(alloc, .{ .string = entry.key_ptr.* });
    }
    return .{ .array = result };
}

fn native_set_time_limit(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = true };
}
