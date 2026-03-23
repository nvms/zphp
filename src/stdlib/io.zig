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
    .{ "time", native_time },
    .{ "microtime", native_microtime },
    .{ "date", native_date },
    .{ "ob_start", native_ob_start },
    .{ "ob_get_clean", native_ob_get_clean },
    .{ "ob_end_clean", native_ob_end_clean },
    .{ "ob_get_contents", native_ob_get_contents },
    .{ "ob_get_level", native_ob_get_level },
    .{ "mktime", native_mktime },
    .{ "strtotime", native_strtotime },
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

fn native_time(_: *NativeContext, _: []const Value) RuntimeError!Value {
    const ts = std.time.timestamp();
    return .{ .int = ts };
}

fn native_microtime(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const as_float = args.len >= 1 and args[0].isTruthy();
    const ns = std.time.nanoTimestamp();
    if (as_float) {
        const secs: f64 = @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
        return .{ .float = secs };
    }
    const ts: i64 = @intCast(@divTrunc(ns, 1_000_000_000));
    const usec: i64 = @intCast(@divTrunc(@mod(ns, 1_000_000_000), 1_000));
    var buf = std.ArrayListUnmanaged(u8){};
    var tmp: [32]u8 = undefined;
    try buf.appendSlice(ctx.allocator, "0.");
    const usec_str = std.fmt.bufPrint(&tmp, "{d:0>6}", .{@as(u64, @intCast(if (usec < 0) -usec else usec))}) catch "000000";
    try buf.appendSlice(ctx.allocator, usec_str);
    try buf.appendSlice(ctx.allocator, " ");
    const ts_str = std.fmt.bufPrint(&tmp, "{d}", .{ts}) catch "0";
    try buf.appendSlice(ctx.allocator, ts_str);
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
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

fn native_date(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .string = "" };
    const format = args[0].string;
    const timestamp: i64 = if (args.len >= 2) Value.toInt(args[1]) else std.time.timestamp();

    const epoch_secs: u64 = @intCast(if (timestamp < 0) 0 else timestamp);
    const es = std.time.epoch.EpochSeconds{ .secs = epoch_secs };
    const day_seconds = es.getDaySeconds();
    const epoch_day = es.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    var buf = std.ArrayListUnmanaged(u8){};
    for (format) |c| {
        switch (c) {
            'Y' => {
                var tmp: [8]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{year_day.year}) catch "0000";
                try buf.appendSlice(ctx.allocator, s);
            },
            'm' => {
                var tmp: [4]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d:0>2}", .{month_day.month.numeric()}) catch "00";
                try buf.appendSlice(ctx.allocator, s);
            },
            'd' => {
                var tmp: [4]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d:0>2}", .{month_day.day_index + 1}) catch "00";
                try buf.appendSlice(ctx.allocator, s);
            },
            'H' => {
                var tmp: [4]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d:0>2}", .{day_seconds.getHoursIntoDay()}) catch "00";
                try buf.appendSlice(ctx.allocator, s);
            },
            'i' => {
                var tmp: [4]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d:0>2}", .{day_seconds.getMinutesIntoHour()}) catch "00";
                try buf.appendSlice(ctx.allocator, s);
            },
            's' => {
                var tmp: [4]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d:0>2}", .{day_seconds.getSecondsIntoMinute()}) catch "00";
                try buf.appendSlice(ctx.allocator, s);
            },
            'U' => {
                var tmp: [16]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{timestamp}) catch "0";
                try buf.appendSlice(ctx.allocator, s);
            },
            'N' => {
                // unix epoch (1970-01-01) was a thursday (4)
                const day_num: i64 = @intCast(epoch_day.day);
                const dow: u8 = @intCast(@mod(day_num + 3, 7) + 1);
                var tmp: [2]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{dow}) catch "0";
                try buf.appendSlice(ctx.allocator, s);
            },
            else => try buf.append(ctx.allocator, c),
        }
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn native_mktime(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const hour: i64 = if (args.len > 0) Value.toInt(args[0]) else 0;
    const min: i64 = if (args.len > 1) Value.toInt(args[1]) else 0;
    const sec: i64 = if (args.len > 2) Value.toInt(args[2]) else 0;
    const month: i64 = if (args.len > 3) Value.toInt(args[3]) else 1;
    const day: i64 = if (args.len > 4) Value.toInt(args[4]) else 1;
    const year: i64 = if (args.len > 5) Value.toInt(args[5]) else 1970;

    const ts = dateToTimestamp(year, month, day, hour, min, sec);
    return .{ .int = ts };
}

fn native_strtotime(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const input = args[0].string;
    const base: i64 = if (args.len >= 2) Value.toInt(args[1]) else std.time.timestamp();

    if (input.len >= 10 and input[4] == '-' and input[7] == '-') {
        const year = std.fmt.parseInt(i64, input[0..4], 10) catch return Value{ .bool = false };
        const month = std.fmt.parseInt(i64, input[5..7], 10) catch return Value{ .bool = false };
        const day = std.fmt.parseInt(i64, input[8..10], 10) catch return Value{ .bool = false };
        var hour: i64 = 0;
        var min: i64 = 0;
        var sec: i64 = 0;
        if (input.len >= 19 and input[10] == ' ' and input[13] == ':' and input[16] == ':') {
            hour = std.fmt.parseInt(i64, input[11..13], 10) catch 0;
            min = std.fmt.parseInt(i64, input[14..16], 10) catch 0;
            sec = std.fmt.parseInt(i64, input[17..19], 10) catch 0;
        }
        return .{ .int = dateToTimestamp(year, month, day, hour, min, sec) };
    }

    return parseRelativeTime(input, base);
}

pub fn parseRelativeTime(input: []const u8, base: i64) Value {
    var s = input;
    var sign: i64 = 1;
    if (s.len > 0 and s[0] == '-') {
        sign = -1;
        s = s[1..];
    } else if (s.len > 0 and s[0] == '+') {
        s = s[1..];
    }
    while (s.len > 0 and s[0] == ' ') s = s[1..];

    var num_end: usize = 0;
    while (num_end < s.len and s[num_end] >= '0' and s[num_end] <= '9') num_end += 1;
    if (num_end == 0) return .{ .bool = false };
    const num = std.fmt.parseInt(i64, s[0..num_end], 10) catch return Value{ .bool = false };
    s = s[num_end..];
    while (s.len > 0 and s[0] == ' ') s = s[1..];

    const seconds: i64 = if (startsWith(s, "second"))
        num * sign
    else if (startsWith(s, "minute"))
        num * sign * 60
    else if (startsWith(s, "hour"))
        num * sign * 3600
    else if (startsWith(s, "day"))
        num * sign * 86400
    else if (startsWith(s, "week"))
        num * sign * 604800
    else if (startsWith(s, "month"))
        num * sign * 2592000
    else if (startsWith(s, "year"))
        num * sign * 31536000
    else
        return .{ .bool = false };

    return .{ .int = base + seconds };
}

pub fn startsWith(s: []const u8, prefix: []const u8) bool {
    return s.len >= prefix.len and std.mem.eql(u8, s[0..prefix.len], prefix);
}

pub fn dateToTimestamp(year: i64, month: i64, day: i64, hour: i64, min: i64, sec: i64) i64 {
    // Howard Hinnant's civil_from_days algorithm (shifted so March = month 0)
    const m = if (month < 1) @as(i64, 1) else if (month > 12) @as(i64, 12) else month;
    const y = year - @as(i64, if (m <= 2) 1 else 0);
    const era: i64 = @divFloor(if (y >= 0) y else y - 399, 400);
    const yoe: i64 = y - era * 400;
    const mp: i64 = if (m > 2) m - 3 else m + 9;
    const doy = @divFloor(153 * mp + 2, 5) + day - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    const days = era * 146097 + doe - 719468;
    return days * 86400 + hour * 3600 + min * 60 + sec;
}
