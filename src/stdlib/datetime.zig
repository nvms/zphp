const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const io = @import("io.zig");

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub fn register(vm: *VM, a: Allocator) !void {
    // DateTimeInterface
    var iface = vm_mod.InterfaceDef{ .name = "DateTimeInterface" };
    try iface.methods.append(a, "format");
    try iface.methods.append(a, "getTimestamp");
    try vm.interfaces.put(a, "DateTimeInterface", iface);

    // DateTime class
    var dt_def = ClassDef{ .name = "DateTime" };
    try dt_def.properties.append(a, .{ .name = "timestamp", .default = .{ .int = 0 }, .visibility = .private });
    try dt_def.interfaces.append(a, "DateTimeInterface");
    try dt_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try dt_def.methods.put(a, "format", .{ .name = "format", .arity = 1 });
    try dt_def.methods.put(a, "getTimestamp", .{ .name = "getTimestamp", .arity = 0 });
    try dt_def.methods.put(a, "setTimestamp", .{ .name = "setTimestamp", .arity = 1 });
    try dt_def.methods.put(a, "modify", .{ .name = "modify", .arity = 1 });
    try dt_def.methods.put(a, "diff", .{ .name = "diff", .arity = 1 });
    try dt_def.methods.put(a, "setDate", .{ .name = "setDate", .arity = 3 });
    try dt_def.methods.put(a, "setTime", .{ .name = "setTime", .arity = 2 });
    try dt_def.methods.put(a, "createFromTimestamp", .{ .name = "createFromTimestamp", .arity = 1, .is_static = true });
    try dt_def.methods.put(a, "getMicrosecond", .{ .name = "getMicrosecond", .arity = 0 });
    try dt_def.methods.put(a, "setMicrosecond", .{ .name = "setMicrosecond", .arity = 1 });
    try vm.classes.put(a, "DateTime", dt_def);

    try vm.native_fns.put(a, "DateTime::__construct", dtConstruct);
    try vm.native_fns.put(a, "DateTime::format", dtFormat);
    try vm.native_fns.put(a, "DateTime::getTimestamp", dtGetTimestamp);
    try vm.native_fns.put(a, "DateTime::setTimestamp", dtSetTimestamp);
    try vm.native_fns.put(a, "DateTime::modify", dtModify);
    try vm.native_fns.put(a, "DateTime::diff", dtDiff);
    try vm.native_fns.put(a, "DateTime::setDate", dtSetDate);
    try vm.native_fns.put(a, "DateTime::setTime", dtSetTime);
    try vm.native_fns.put(a, "DateTime::createFromTimestamp", dtCreateFromTimestamp);
    try vm.native_fns.put(a, "DateTime::getMicrosecond", dtGetMicrosecond);
    try vm.native_fns.put(a, "DateTime::setMicrosecond", dtSetMicrosecond);

    // DateTimeImmutable
    var dti_def = ClassDef{ .name = "DateTimeImmutable" };
    try dti_def.properties.append(a, .{ .name = "timestamp", .default = .{ .int = 0 }, .visibility = .private });
    try dti_def.interfaces.append(a, "DateTimeInterface");
    try dti_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try dti_def.methods.put(a, "format", .{ .name = "format", .arity = 1 });
    try dti_def.methods.put(a, "getTimestamp", .{ .name = "getTimestamp", .arity = 0 });
    try dti_def.methods.put(a, "modify", .{ .name = "modify", .arity = 1 });
    try dti_def.methods.put(a, "diff", .{ .name = "diff", .arity = 1 });
    try dti_def.methods.put(a, "createFromTimestamp", .{ .name = "createFromTimestamp", .arity = 1, .is_static = true });
    try dti_def.methods.put(a, "getMicrosecond", .{ .name = "getMicrosecond", .arity = 0 });
    try vm.classes.put(a, "DateTimeImmutable", dti_def);

    try vm.native_fns.put(a, "DateTimeImmutable::__construct", dtConstruct);
    try vm.native_fns.put(a, "DateTimeImmutable::format", dtFormat);
    try vm.native_fns.put(a, "DateTimeImmutable::getTimestamp", dtGetTimestamp);
    try vm.native_fns.put(a, "DateTimeImmutable::modify", dtiModify);
    try vm.native_fns.put(a, "DateTimeImmutable::diff", dtDiff);
    try vm.native_fns.put(a, "DateTimeImmutable::createFromTimestamp", dtiCreateFromTimestamp);
    try vm.native_fns.put(a, "DateTimeImmutable::getMicrosecond", dtGetMicrosecond);

    // DateInterval
    var di_def = ClassDef{ .name = "DateInterval" };
    try di_def.properties.append(a, .{ .name = "y", .default = .{ .int = 0 } });
    try di_def.properties.append(a, .{ .name = "m", .default = .{ .int = 0 } });
    try di_def.properties.append(a, .{ .name = "d", .default = .{ .int = 0 } });
    try di_def.properties.append(a, .{ .name = "h", .default = .{ .int = 0 } });
    try di_def.properties.append(a, .{ .name = "i", .default = .{ .int = 0 } });
    try di_def.properties.append(a, .{ .name = "s", .default = .{ .int = 0 } });
    try di_def.properties.append(a, .{ .name = "days", .default = .{ .int = 0 } });
    try di_def.properties.append(a, .{ .name = "invert", .default = .{ .int = 0 } });
    try vm.classes.put(a, "DateInterval", di_def);
}

fn getThis(ctx: *NativeContext) ?*PhpObject {
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

fn getTimestamp(obj: *PhpObject) i64 {
    return Value.toInt(obj.get("timestamp"));
}

fn dtConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    var ts: i64 = std.time.timestamp();

    if (args.len >= 1 and args[0] == .string) {
        const s = args[0].string;
        if (s.len == 0 or std.mem.eql(u8, s, "now")) {
            // default: current time
        } else if (s.len >= 10 and s[4] == '-' and s[7] == '-') {
            const year = std.fmt.parseInt(i64, s[0..4], 10) catch 1970;
            const month = std.fmt.parseInt(i64, s[5..7], 10) catch 1;
            const day = std.fmt.parseInt(i64, s[8..10], 10) catch 1;
            var hour: i64 = 0;
            var min: i64 = 0;
            var sec: i64 = 0;
            if (s.len >= 19 and (s[10] == ' ' or s[10] == 'T') and s[13] == ':' and s[16] == ':') {
                hour = std.fmt.parseInt(i64, s[11..13], 10) catch 0;
                min = std.fmt.parseInt(i64, s[14..16], 10) catch 0;
                sec = std.fmt.parseInt(i64, s[17..19], 10) catch 0;
            }
            ts = io.dateToTimestamp(year, month, day, hour, min, sec);
        } else {
            const result = io.parseRelativeTime(s, ts);
            if (result == .int) ts = result.int;
        }
    }

    try obj.set(ctx.allocator, "timestamp", .{ .int = ts });
    return .null;
}

fn dtFormat(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len == 0 or args[0] != .string) return .{ .string = "" };
    const ts = getTimestamp(obj);
    return formatTimestamp(ctx, ts, args[0].string);
}

fn formatTimestamp(ctx: *NativeContext, timestamp: i64, format: []const u8) RuntimeError!Value {
    const epoch_secs: u64 = @intCast(if (timestamp < 0) 0 else timestamp);
    const es = std.time.epoch.EpochSeconds{ .secs = epoch_secs };
    const day_seconds = es.getDaySeconds();
    const epoch_day = es.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const a = ctx.allocator;

    var buf = std.ArrayListUnmanaged(u8){};
    for (format) |c| {
        switch (c) {
            'Y' => {
                var tmp: [8]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{year_day.year}) catch "0000";
                try buf.appendSlice(a, s);
            },
            'm' => {
                var tmp: [4]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d:0>2}", .{month_day.month.numeric()}) catch "00";
                try buf.appendSlice(a, s);
            },
            'd' => {
                var tmp: [4]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d:0>2}", .{month_day.day_index + 1}) catch "00";
                try buf.appendSlice(a, s);
            },
            'H' => {
                var tmp: [4]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d:0>2}", .{day_seconds.getHoursIntoDay()}) catch "00";
                try buf.appendSlice(a, s);
            },
            'i' => {
                var tmp: [4]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d:0>2}", .{day_seconds.getMinutesIntoHour()}) catch "00";
                try buf.appendSlice(a, s);
            },
            's' => {
                var tmp: [4]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d:0>2}", .{day_seconds.getSecondsIntoMinute()}) catch "00";
                try buf.appendSlice(a, s);
            },
            'U' => {
                var tmp: [16]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{timestamp}) catch "0";
                try buf.appendSlice(a, s);
            },
            'N' => {
                const day_num: i64 = @intCast(epoch_day.day);
                const dow: u8 = @intCast(@mod(day_num + 3, 7) + 1);
                var tmp: [2]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{dow}) catch "0";
                try buf.appendSlice(a, s);
            },
            'j' => {
                var tmp: [4]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{month_day.day_index + 1}) catch "0";
                try buf.appendSlice(a, s);
            },
            'n' => {
                var tmp: [4]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{month_day.month.numeric()}) catch "0";
                try buf.appendSlice(a, s);
            },
            'G' => {
                var tmp: [4]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{day_seconds.getHoursIntoDay()}) catch "0";
                try buf.appendSlice(a, s);
            },
            'g' => {
                const h = day_seconds.getHoursIntoDay();
                const h12: u32 = if (h == 0) 12 else if (h > 12) h - 12 else h;
                var tmp: [4]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{h12}) catch "0";
                try buf.appendSlice(a, s);
            },
            'A' => try buf.appendSlice(a, if (day_seconds.getHoursIntoDay() < 12) "AM" else "PM"),
            'a' => try buf.appendSlice(a, if (day_seconds.getHoursIntoDay() < 12) "am" else "pm"),
            'l' => {
                const day_num: i64 = @intCast(epoch_day.day);
                const dow: usize = @intCast(@mod(day_num + 3, 7));
                const names = [_][]const u8{ "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" };
                try buf.appendSlice(a, names[dow]);
            },
            'D' => {
                const day_num: i64 = @intCast(epoch_day.day);
                const dow: usize = @intCast(@mod(day_num + 3, 7));
                const names = [_][]const u8{ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };
                try buf.appendSlice(a, names[dow]);
            },
            'F' => {
                const names = [_][]const u8{ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };
                try buf.appendSlice(a, names[month_day.month.numeric() - 1]);
            },
            'M' => {
                const names = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
                try buf.appendSlice(a, names[month_day.month.numeric() - 1]);
            },
            'y' => {
                var tmp: [4]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d:0>2}", .{@as(u32, @intCast(@mod(year_day.year, 100)))}) catch "00";
                try buf.appendSlice(a, s);
            },
            't' => {
                const days = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
                var d: u8 = days[month_day.month.numeric() - 1];
                if (month_day.month.numeric() == 2) {
                    const yr: u32 = @intCast(year_day.year);
                    if (yr % 4 == 0 and (yr % 100 != 0 or yr % 400 == 0)) d = 29;
                }
                var tmp: [4]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{d}) catch "0";
                try buf.appendSlice(a, s);
            },
            '\\' => {}, // next char literal (simplified: just skip the backslash)
            else => try buf.append(a, c),
        }
    }
    const result = try buf.toOwnedSlice(a);
    try ctx.strings.append(a, result);
    return .{ .string = result };
}

fn dtGetTimestamp(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    return .{ .int = getTimestamp(obj) };
}

fn dtSetTimestamp(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len >= 1) try obj.set(ctx.allocator, "timestamp", .{ .int = Value.toInt(args[0]) });
    return .{ .object = obj };
}

fn dtModify(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len == 0 or args[0] != .string) return .{ .object = obj };
    const ts = getTimestamp(obj);
    const result = io.parseRelativeTime(args[0].string, ts);
    if (result == .int) try obj.set(ctx.allocator, "timestamp", result);
    return .{ .object = obj };
}

fn dtiModify(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len == 0 or args[0] != .string) return .{ .object = obj };
    const ts = getTimestamp(obj);
    const result = io.parseRelativeTime(args[0].string, ts);
    if (result != .int) return .{ .object = obj };

    // immutable: create a new DateTime object
    const new_obj = try ctx.createObject("DateTimeImmutable");
    try new_obj.set(ctx.allocator, "timestamp", result);
    return .{ .object = new_obj };
}

fn dtDiff(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len == 0 or args[0] != .object) return .null;
    const other = args[0].object;
    const ts1 = getTimestamp(obj);
    const ts2 = getTimestamp(other);
    var diff_secs = ts1 - ts2;
    const invert: i64 = if (diff_secs < 0) 1 else 0;
    if (diff_secs < 0) diff_secs = -diff_secs;

    const total_days = @divFloor(diff_secs, 86400);
    const rem = @mod(diff_secs, 86400);
    const hours = @divFloor(rem, 3600);
    const mins = @divFloor(@mod(rem, 3600), 60);
    const secs = @mod(rem, 60);

    const interval = try ctx.createObject("DateInterval");
    try interval.set(ctx.allocator, "days", .{ .int = total_days });
    try interval.set(ctx.allocator, "h", .{ .int = hours });
    try interval.set(ctx.allocator, "i", .{ .int = mins });
    try interval.set(ctx.allocator, "s", .{ .int = secs });
    try interval.set(ctx.allocator, "invert", .{ .int = invert });
    return .{ .object = interval };
}

fn dtSetDate(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len < 3) return .{ .object = obj };
    const ts = getTimestamp(obj);
    const epoch_secs: u64 = @intCast(if (ts < 0) 0 else ts);
    const es = std.time.epoch.EpochSeconds{ .secs = epoch_secs };
    const day_seconds = es.getDaySeconds();
    const h: i64 = day_seconds.getHoursIntoDay();
    const m: i64 = day_seconds.getMinutesIntoHour();
    const s: i64 = day_seconds.getSecondsIntoMinute();
    const new_ts = io.dateToTimestamp(Value.toInt(args[0]), Value.toInt(args[1]), Value.toInt(args[2]), h, m, s);
    try obj.set(ctx.allocator, "timestamp", .{ .int = new_ts });
    return .{ .object = obj };
}

fn dtSetTime(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len < 2) return .{ .object = obj };
    const ts = getTimestamp(obj);
    const epoch_secs: u64 = @intCast(if (ts < 0) 0 else ts);
    const es = std.time.epoch.EpochSeconds{ .secs = epoch_secs };
    const epoch_day = es.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const sec: i64 = if (args.len >= 3) Value.toInt(args[2]) else 0;
    const new_ts = io.dateToTimestamp(@intCast(year_day.year), month_day.month.numeric(), month_day.day_index + 1, Value.toInt(args[0]), Value.toInt(args[1]), sec);
    try obj.set(ctx.allocator, "timestamp", .{ .int = new_ts });
    return .{ .object = obj };
}

fn dtCreateFromTimestamp(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .null;
    const obj = try ctx.createObject("DateTime");
    try obj.set(ctx.allocator, "timestamp", .{ .int = Value.toInt(args[0]) });
    return .{ .object = obj };
}

fn dtiCreateFromTimestamp(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .null;
    const obj = try ctx.createObject("DateTimeImmutable");
    try obj.set(ctx.allocator, "timestamp", .{ .int = Value.toInt(args[0]) });
    return .{ .object = obj };
}

fn dtGetMicrosecond(_: *NativeContext, _: []const Value) RuntimeError!Value {
    // zphp timestamps are second-precision, microseconds always 0
    return .{ .int = 0 };
}

fn dtSetMicrosecond(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    // no-op since we don't store microseconds, return $this
    const obj = getThis(ctx) orelse return .null;
    return .{ .object = obj };
}
