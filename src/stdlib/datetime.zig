const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "date", native_date },
    .{ "mktime", native_mktime },
    .{ "strtotime", native_strtotime },
    .{ "time", native_time },
    .{ "microtime", native_microtime },
    .{ "checkdate", native_checkdate },
    .{ "getdate", native_getdate },
    .{ "gmdate", native_gmdate },
    .{ "date_default_timezone_set", native_tz_set },
    .{ "date_default_timezone_get", native_tz_get },
};

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
    try dt_def.methods.put(a, "add", .{ .name = "add", .arity = 1 });
    try dt_def.methods.put(a, "sub", .{ .name = "sub", .arity = 1 });
    try dt_def.methods.put(a, "diff", .{ .name = "diff", .arity = 1 });
    try dt_def.methods.put(a, "setDate", .{ .name = "setDate", .arity = 3 });
    try dt_def.methods.put(a, "setTime", .{ .name = "setTime", .arity = 2 });
    try dt_def.methods.put(a, "createFromTimestamp", .{ .name = "createFromTimestamp", .arity = 1, .is_static = true });
    try dt_def.methods.put(a, "createFromFormat", .{ .name = "createFromFormat", .arity = 2, .is_static = true });
    try dt_def.methods.put(a, "getMicrosecond", .{ .name = "getMicrosecond", .arity = 0 });
    try dt_def.methods.put(a, "setMicrosecond", .{ .name = "setMicrosecond", .arity = 1 });
    try dt_def.methods.put(a, "getLastErrors", .{ .name = "getLastErrors", .arity = 0, .is_static = true });
    try dt_def.methods.put(a, "getTimezone", .{ .name = "getTimezone", .arity = 0 });
    try dt_def.methods.put(a, "setTimezone", .{ .name = "setTimezone", .arity = 1 });
    try vm.classes.put(a, "DateTime", dt_def);

    try vm.native_fns.put(a, "DateTime::__construct", dtConstruct);
    try vm.native_fns.put(a, "DateTime::format", dtFormat);
    try vm.native_fns.put(a, "DateTime::getTimestamp", dtGetTimestamp);
    try vm.native_fns.put(a, "DateTime::setTimestamp", dtSetTimestamp);
    try vm.native_fns.put(a, "DateTime::modify", dtModify);
    try vm.native_fns.put(a, "DateTime::add", dtAdd);
    try vm.native_fns.put(a, "DateTime::sub", dtSub);
    try vm.native_fns.put(a, "DateTime::diff", dtDiff);
    try vm.native_fns.put(a, "DateTime::setDate", dtSetDate);
    try vm.native_fns.put(a, "DateTime::setTime", dtSetTime);
    try vm.native_fns.put(a, "DateTime::createFromTimestamp", dtCreateFromTimestamp);
    try vm.native_fns.put(a, "DateTime::createFromFormat", dtCreateFromFormat);
    try vm.native_fns.put(a, "DateTime::getMicrosecond", dtGetMicrosecond);
    try vm.native_fns.put(a, "DateTime::setMicrosecond", dtSetMicrosecond);
    try vm.native_fns.put(a, "DateTime::getLastErrors", dtGetLastErrors);
    try vm.native_fns.put(a, "DateTime::getTimezone", dtGetTimezone);
    try vm.native_fns.put(a, "DateTime::setTimezone", dtSetTimezone);

    // DateTimeImmutable
    var dti_def = ClassDef{ .name = "DateTimeImmutable" };
    try dti_def.properties.append(a, .{ .name = "timestamp", .default = .{ .int = 0 }, .visibility = .private });
    try dti_def.interfaces.append(a, "DateTimeInterface");
    try dti_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try dti_def.methods.put(a, "format", .{ .name = "format", .arity = 1 });
    try dti_def.methods.put(a, "getTimestamp", .{ .name = "getTimestamp", .arity = 0 });
    try dti_def.methods.put(a, "modify", .{ .name = "modify", .arity = 1 });
    try dti_def.methods.put(a, "add", .{ .name = "add", .arity = 1 });
    try dti_def.methods.put(a, "sub", .{ .name = "sub", .arity = 1 });
    try dti_def.methods.put(a, "diff", .{ .name = "diff", .arity = 1 });
    try dti_def.methods.put(a, "createFromTimestamp", .{ .name = "createFromTimestamp", .arity = 1, .is_static = true });
    try dti_def.methods.put(a, "getMicrosecond", .{ .name = "getMicrosecond", .arity = 0 });
    try dti_def.methods.put(a, "getLastErrors", .{ .name = "getLastErrors", .arity = 0, .is_static = true });
    try dti_def.methods.put(a, "getTimezone", .{ .name = "getTimezone", .arity = 0 });
    try dti_def.methods.put(a, "setTimezone", .{ .name = "setTimezone", .arity = 1 });
    try dti_def.methods.put(a, "createFromFormat", .{ .name = "createFromFormat", .arity = 2, .is_static = true });
    try vm.classes.put(a, "DateTimeImmutable", dti_def);

    try vm.native_fns.put(a, "DateTimeImmutable::__construct", dtConstruct);
    try vm.native_fns.put(a, "DateTimeImmutable::format", dtFormat);
    try vm.native_fns.put(a, "DateTimeImmutable::getTimestamp", dtGetTimestamp);
    try vm.native_fns.put(a, "DateTimeImmutable::modify", dtiModify);
    try vm.native_fns.put(a, "DateTimeImmutable::add", dtiAdd);
    try vm.native_fns.put(a, "DateTimeImmutable::sub", dtiSub);
    try vm.native_fns.put(a, "DateTimeImmutable::diff", dtDiff);
    try vm.native_fns.put(a, "DateTimeImmutable::createFromTimestamp", dtiCreateFromTimestamp);
    try vm.native_fns.put(a, "DateTimeImmutable::getMicrosecond", dtGetMicrosecond);
    try vm.native_fns.put(a, "DateTimeImmutable::getLastErrors", dtGetLastErrors);
    try vm.native_fns.put(a, "DateTimeImmutable::getTimezone", dtGetTimezone);
    try vm.native_fns.put(a, "DateTimeImmutable::setTimezone", dtiSetTimezone);
    try vm.native_fns.put(a, "DateTimeImmutable::createFromFormat", dtiCreateFromFormat);

    // DateTimeZone class
    var dtz_def = ClassDef{ .name = "DateTimeZone" };
    try dtz_def.properties.append(a, .{ .name = "timezone", .default = .{ .string = "UTC" }, .visibility = .private });
    try dtz_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try dtz_def.methods.put(a, "getName", .{ .name = "getName", .arity = 0 });
    try dtz_def.methods.put(a, "getOffset", .{ .name = "getOffset", .arity = 1 });
    try dtz_def.methods.put(a, "__toString", .{ .name = "__toString", .arity = 0 });
    try vm.classes.put(a, "DateTimeZone", dtz_def);

    try vm.native_fns.put(a, "DateTimeZone::__construct", dtzConstruct);
    try vm.native_fns.put(a, "DateTimeZone::getName", dtzGetName);
    try vm.native_fns.put(a, "DateTimeZone::getOffset", dtzGetOffset);
    try vm.native_fns.put(a, "DateTimeZone::__toString", dtzGetName);

    // DateInterval
    var di_def = ClassDef{ .name = "DateInterval" };
    try di_def.properties.append(a, .{ .name = "y", .default = .{ .int = 0 } });
    try di_def.properties.append(a, .{ .name = "m", .default = .{ .int = 0 } });
    try di_def.properties.append(a, .{ .name = "d", .default = .{ .int = 0 } });
    try di_def.properties.append(a, .{ .name = "h", .default = .{ .int = 0 } });
    try di_def.properties.append(a, .{ .name = "i", .default = .{ .int = 0 } });
    try di_def.properties.append(a, .{ .name = "s", .default = .{ .int = 0 } });
    try di_def.properties.append(a, .{ .name = "f", .default = .{ .float = 0.0 } });
    try di_def.properties.append(a, .{ .name = "days", .default = .{ .int = 0 } });
    try di_def.properties.append(a, .{ .name = "invert", .default = .{ .int = 0 } });
    try di_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try di_def.methods.put(a, "invert", .{ .name = "invert", .arity = 1 });
    try vm.classes.put(a, "DateInterval", di_def);

    try vm.native_fns.put(a, "DateInterval::__construct", diConstruct);
    try vm.native_fns.put(a, "DateInterval::invert", diInvert);
}

fn dtGetLastErrors(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = false };
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
            ts = dateToTimestamp(year, month, day, hour, min, sec);
        } else {
            const result = parseRelativeTime(s, ts);
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

pub fn formatTimestamp(ctx: *NativeContext, timestamp: i64, format: []const u8) RuntimeError!Value {
    const epoch_secs: u64 = @intCast(if (timestamp < 0) 0 else timestamp);
    const es = std.time.epoch.EpochSeconds{ .secs = epoch_secs };
    const day_seconds = es.getDaySeconds();
    const epoch_day = es.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const a = ctx.allocator;

    var buf = std.ArrayListUnmanaged(u8){};
    var fi: usize = 0;
    while (fi < format.len) : (fi += 1) {
        const c = format[fi];
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
            'c' => {
                // ISO 8601: YYYY-MM-DDTHH:MM:SS+00:00
                var tmp: [32]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}+00:00", .{
                    year_day.year,
                    month_day.month.numeric(),
                    month_day.day_index + 1,
                    day_seconds.getHoursIntoDay(),
                    day_seconds.getMinutesIntoHour(),
                    day_seconds.getSecondsIntoMinute(),
                }) catch "0000-00-00T00:00:00+00:00";
                try buf.appendSlice(a, s);
            },
            'r' => {
                // RFC 2822: Day, DD Mon YYYY HH:MM:SS +0000
                const day_num: i64 = @intCast(epoch_day.day);
                const dow: usize = @intCast(@mod(day_num + 3, 7));
                const day_names = [_][]const u8{ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };
                const mon_names = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
                try buf.appendSlice(a, day_names[dow]);
                try buf.appendSlice(a, ", ");
                var tmp: [32]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d:0>2} ", .{month_day.day_index + 1}) catch "01 ";
                try buf.appendSlice(a, s);
                try buf.appendSlice(a, mon_names[month_day.month.numeric() - 1]);
                const s2 = std.fmt.bufPrint(&tmp, " {d} {d:0>2}:{d:0>2}:{d:0>2} +0000", .{
                    year_day.year,
                    day_seconds.getHoursIntoDay(),
                    day_seconds.getMinutesIntoHour(),
                    day_seconds.getSecondsIntoMinute(),
                }) catch " 0000 00:00:00 +0000";
                try buf.appendSlice(a, s2);
            },
            'z' => {
                const jan1_ts = dateToTimestamp(year_day.year, 1, 1, 0, 0, 0);
                const jan1_es = std.time.epoch.EpochSeconds{ .secs = @intCast(if (jan1_ts < 0) 0 else jan1_ts) };
                const jan1_day: i64 = @intCast(jan1_es.getEpochDay().day);
                const cur_day: i64 = @intCast(epoch_day.day);
                const yday = cur_day - jan1_day;
                var tmp: [4]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{@as(u32, @intCast(@max(0, yday)))}) catch "0";
                try buf.appendSlice(a, s);
            },
            'W' => {
                // iso 8601 week number - week 1 contains the first thursday
                const cur_day: i64 = @intCast(epoch_day.day);
                const dow = @mod(cur_day + 3, 7); // 0=mon
                // thursday of this week
                const thu = cur_day + 3 - dow;
                // jan 1 of the thursday's year
                const thu_es = std.time.epoch.EpochSeconds{ .secs = @intCast(@max(0, thu * 86400)) };
                const thu_year = thu_es.getEpochDay().calculateYearDay().year;
                const jan1_ts = dateToTimestamp(thu_year, 1, 1, 0, 0, 0);
                const jan1_day = @divFloor(jan1_ts, 86400);
                const week = @divFloor(thu - jan1_day, 7) + 1;
                var tmp: [4]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d:0>2}", .{@as(u32, @intCast(@max(1, week)))}) catch "01";
                try buf.appendSlice(a, s);
            },
            'w' => {
                const day_num: i64 = @intCast(epoch_day.day);
                const dow: u8 = @intCast(@mod(day_num + 4, 7)); // 0=sunday
                var tmp: [2]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{dow}) catch "0";
                try buf.appendSlice(a, s);
            },
            'L' => {
                const yr: u32 = @intCast(year_day.year);
                const leap = yr % 4 == 0 and (yr % 100 != 0 or yr % 400 == 0);
                try buf.append(a, if (leap) '1' else '0');
            },
            'o' => {
                var tmp: [8]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{year_day.year}) catch "0000";
                try buf.appendSlice(a, s);
            },
            'S' => {
                const day_val = month_day.day_index + 1;
                const suffix: []const u8 = if (day_val == 11 or day_val == 12 or day_val == 13)
                    "th"
                else switch (@as(u8, @intCast(day_val % 10))) {
                    1 => "st",
                    2 => "nd",
                    3 => "rd",
                    else => "th",
                };
                try buf.appendSlice(a, suffix);
            },
            'u' => try buf.appendSlice(a, "000000"),
            'v' => try buf.appendSlice(a, "000"),
            'Z' => try buf.append(a, '0'),
            'e', 'T' => try buf.appendSlice(a, "UTC"),
            'P' => try buf.appendSlice(a, "+00:00"),
            'O' => try buf.appendSlice(a, "+0000"),
            'I' => try buf.append(a, '0'),
            '\\' => {
                fi += 1;
                if (fi < format.len) try buf.append(a, format[fi]);
            },
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
    const result = parseRelativeTime(args[0].string, ts);
    if (result == .int) try obj.set(ctx.allocator, "timestamp", result);
    return .{ .object = obj };
}

fn dtiModify(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len == 0 or args[0] != .string) return .{ .object = obj };
    const ts = getTimestamp(obj);
    const result = parseRelativeTime(args[0].string, ts);
    if (result != .int) return .{ .object = obj };

    // immutable: create a new DateTime object
    const new_obj = try ctx.createObject("DateTimeImmutable");
    try new_obj.set(ctx.allocator, "timestamp", result);
    return .{ .object = new_obj };
}

fn intervalToSeconds(interval: *PhpObject) i64 {
    const y = Value.toInt(interval.get("y"));
    const m = Value.toInt(interval.get("m"));
    const d = Value.toInt(interval.get("d"));
    const h = Value.toInt(interval.get("h"));
    const i = Value.toInt(interval.get("i"));
    const s = Value.toInt(interval.get("s"));
    const invert = Value.toInt(interval.get("invert"));
    const total = y * 365 * 86400 + m * 30 * 86400 + d * 86400 + h * 3600 + i * 60 + s;
    return if (invert != 0) -total else total;
}

fn dtAdd(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len == 0 or args[0] != .object) return .{ .object = obj };
    const ts = getTimestamp(obj);
    const delta = intervalToSeconds(args[0].object);
    try obj.set(ctx.allocator, "timestamp", .{ .int = ts + delta });
    return .{ .object = obj };
}

fn dtSub(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len == 0 or args[0] != .object) return .{ .object = obj };
    const ts = getTimestamp(obj);
    const delta = intervalToSeconds(args[0].object);
    try obj.set(ctx.allocator, "timestamp", .{ .int = ts - delta });
    return .{ .object = obj };
}

fn dtiAdd(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len == 0 or args[0] != .object) return .{ .object = obj };
    const ts = getTimestamp(obj);
    const delta = intervalToSeconds(args[0].object);
    const new_obj = try ctx.createObject("DateTimeImmutable");
    try new_obj.set(ctx.allocator, "timestamp", .{ .int = ts + delta });
    return .{ .object = new_obj };
}

fn dtiSub(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len == 0 or args[0] != .object) return .{ .object = obj };
    const ts = getTimestamp(obj);
    const delta = intervalToSeconds(args[0].object);
    const new_obj = try ctx.createObject("DateTimeImmutable");
    try new_obj.set(ctx.allocator, "timestamp", .{ .int = ts - delta });
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

    // compute calendar-based y/m/d
    const early_ts = if (ts1 < ts2) ts1 else ts2;
    const late_ts = if (ts1 < ts2) ts2 else ts1;
    const c1 = baseComponents(early_ts);
    const c2 = baseComponents(late_ts);
    var diff_y = c2.year - c1.year;
    var diff_m = c2.month - c1.month;
    var diff_d = c2.day - c1.day;
    if (diff_d < 0) {
        diff_m -= 1;
        diff_d += daysInMonth(c1.month, c1.year);
    }
    if (diff_m < 0) {
        diff_y -= 1;
        diff_m += 12;
    }

    const interval = try ctx.createObject("DateInterval");
    try interval.set(ctx.allocator, "y", .{ .int = diff_y });
    try interval.set(ctx.allocator, "m", .{ .int = diff_m });
    try interval.set(ctx.allocator, "d", .{ .int = diff_d });
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
    const new_ts = dateToTimestamp(Value.toInt(args[0]), Value.toInt(args[1]), Value.toInt(args[2]), h, m, s);
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
    const new_ts = dateToTimestamp(@intCast(year_day.year), month_day.month.numeric(), month_day.day_index + 1, Value.toInt(args[0]), Value.toInt(args[1]), sec);
    try obj.set(ctx.allocator, "timestamp", .{ .int = new_ts });
    return .{ .object = obj };
}

fn dtCreateFromTimestamp(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .null;
    const obj = try ctx.createObject("DateTime");
    try obj.set(ctx.allocator, "timestamp", .{ .int = Value.toInt(args[0]) });
    return .{ .object = obj };
}

fn dtCreateFromFormat(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const format = args[0].string;
    const datetime = args[1].string;

    // late static binding: if called from a subclass (e.g. Carbon), create that class
    const class_name = blk: {
        var fi: usize = ctx.vm.frame_count;
        while (fi > 0) {
            fi -= 1;
            if (ctx.vm.frames[fi].called_class) |cc| {
                if (ctx.vm.classes.contains(cc)) break :blk cc;
            }
        }
        break :blk "DateTime";
    };
    const obj = try ctx.createObject(class_name);

    // handle the most common format Carbon uses: "U.u" (unix timestamp with microseconds)
    if (std.mem.eql(u8, format, "U.u") or std.mem.eql(u8, format, "U")) {
        // parse timestamp from string like "1234567890.123456" or "1234567890"
        var ts: i64 = 0;
        var neg = false;
        var i: usize = 0;
        if (i < datetime.len and datetime[i] == '-') { neg = true; i += 1; }
        while (i < datetime.len and datetime[i] >= '0' and datetime[i] <= '9') : (i += 1) {
            ts = ts * 10 + @as(i64, datetime[i] - '0');
        }
        if (neg) ts = -ts;
        try obj.set(ctx.allocator, "timestamp", .{ .int = ts });
        return .{ .object = obj };
    }

    // for other formats, try parsing the datetime string as a general date
    const parsed = parseRelativeTime(datetime, std.time.timestamp());
    if (parsed == .int) {
        try obj.set(ctx.allocator, "timestamp", parsed);
    } else {
        try obj.set(ctx.allocator, "timestamp", .{ .int = std.time.timestamp() });
    }
    return .{ .object = obj };
}

fn dtiCreateFromFormat(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const format = args[0].string;
    const datetime = args[1].string;

    const class_name = blk: {
        var fi: usize = ctx.vm.frame_count;
        while (fi > 0) {
            fi -= 1;
            if (ctx.vm.frames[fi].called_class) |cc| {
                if (ctx.vm.classes.contains(cc)) break :blk cc;
            }
        }
        break :blk "DateTimeImmutable";
    };
    const obj = try ctx.createObject(class_name);

    if (std.mem.eql(u8, format, "U.u") or std.mem.eql(u8, format, "U")) {
        var ts: i64 = 0;
        var neg = false;
        var i: usize = 0;
        if (i < datetime.len and datetime[i] == '-') { neg = true; i += 1; }
        while (i < datetime.len and datetime[i] >= '0' and datetime[i] <= '9') : (i += 1) {
            ts = ts * 10 + @as(i64, datetime[i] - '0');
        }
        if (neg) ts = -ts;
        try obj.set(ctx.allocator, "timestamp", .{ .int = ts });
        return .{ .object = obj };
    }

    const parsed = parseRelativeTime(datetime, std.time.timestamp());
    if (parsed == .int) {
        try obj.set(ctx.allocator, "timestamp", parsed);
    } else {
        try obj.set(ctx.allocator, "timestamp", .{ .int = std.time.timestamp() });
    }
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

fn dtGetTimezone(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const tz_val = obj.get("__timezone");
    const tz_name = if (tz_val == .string) tz_val.string else "UTC";
    const tz_obj = try ctx.createObject("DateTimeZone");
    try tz_obj.set(ctx.allocator, "timezone", .{ .string = tz_name });
    return .{ .object = tz_obj };
}

fn dtSetTimezone(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const tz_name = extractTimezoneName(args);
    try obj.set(ctx.allocator, "__timezone", .{ .string = tz_name });
    return .{ .object = obj };
}

fn dtiSetTimezone(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const tz_name = extractTimezoneName(args);
    const new_obj = try ctx.createObject("DateTimeImmutable");
    const ts = obj.get("timestamp");
    try new_obj.set(ctx.allocator, "timestamp", if (ts == .null) .{ .int = 0 } else ts);
    try new_obj.set(ctx.allocator, "__timezone", .{ .string = tz_name });
    return .{ .object = new_obj };
}

fn extractTimezoneName(args: []const Value) []const u8 {
    if (args.len == 0) return "UTC";
    if (args[0] == .string) return args[0].string;
    if (args[0] == .object) {
        const tz_val = args[0].object.get("timezone");
        if (tz_val == .string) return tz_val.string;
    }
    return "UTC";
}

fn dtzConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len >= 1 and args[0] == .string) {
        try obj.set(ctx.allocator, "timezone", .{ .string = args[0].string });
    }
    return .null;
}

fn dtzGetName(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .string = "UTC" };
    const tz_val = obj.get("timezone");
    return if (tz_val == .string) tz_val else .{ .string = "UTC" };
}

fn dtzGetOffset(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = 0 };
}

// standalone PHP functions: date(), mktime(), strtotime(), time(), microtime()

fn native_date(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .string = "" };
    const format = args[0].string;
    const timestamp: i64 = if (args.len >= 2) Value.toInt(args[1]) else std.time.timestamp();
    return formatTimestamp(ctx, timestamp, format);
}

fn native_mktime(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const hour: i64 = if (args.len > 0) Value.toInt(args[0]) else 0;
    const min: i64 = if (args.len > 1) Value.toInt(args[1]) else 0;
    const sec: i64 = if (args.len > 2) Value.toInt(args[2]) else 0;
    const month: i64 = if (args.len > 3) Value.toInt(args[3]) else 1;
    const day: i64 = if (args.len > 4) Value.toInt(args[4]) else 1;
    const year: i64 = if (args.len > 5) Value.toInt(args[5]) else 1970;
    return .{ .int = dateToTimestamp(year, month, day, hour, min, sec) };
}

fn native_strtotime(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const input = args[0].string;
    const base: i64 = if (args.len >= 2) Value.toInt(args[1]) else std.time.timestamp();

    // @timestamp - unix timestamp literal
    if (input.len >= 2 and input[0] == '@') {
        const ts = std.fmt.parseInt(i64, input[1..], 10) catch return Value{ .bool = false };
        return .{ .int = ts };
    }

    // YYYY-MM-DD with optional time (space or T separator) and optional timezone
    if (input.len >= 10 and input[4] == '-' and input[7] == '-') {
        const year = std.fmt.parseInt(i64, input[0..4], 10) catch return Value{ .bool = false };
        const month = std.fmt.parseInt(i64, input[5..7], 10) catch return Value{ .bool = false };
        const day = std.fmt.parseInt(i64, input[8..10], 10) catch return Value{ .bool = false };
        var hour: i64 = 0;
        var min: i64 = 0;
        var sec: i64 = 0;
        var tz_offset: i64 = 0;
        if (input.len >= 19 and (input[10] == ' ' or input[10] == 'T') and input[13] == ':' and input[16] == ':') {
            hour = std.fmt.parseInt(i64, input[11..13], 10) catch 0;
            min = std.fmt.parseInt(i64, input[14..16], 10) catch 0;
            sec = std.fmt.parseInt(i64, input[17..19], 10) catch 0;
            var rest = input[19..];
            while (rest.len > 0 and rest[0] == ' ') rest = rest[1..];
            if (rest.len > 0) {
                if (parseTimezoneOffset(rest)) |off| tz_offset = off;
            }
        }
        return .{ .int = dateToTimestamp(year, month, day, hour, min, sec) - tz_offset };
    }

    // MM/DD/YYYY US date format with optional timezone
    if (input.len >= 10 and input[2] == '/' and input[5] == '/') {
        const month = std.fmt.parseInt(i64, input[0..2], 10) catch return Value{ .bool = false };
        const day = std.fmt.parseInt(i64, input[3..5], 10) catch return Value{ .bool = false };
        const year = std.fmt.parseInt(i64, input[6..10], 10) catch return Value{ .bool = false };
        var hour: i64 = 0;
        var min: i64 = 0;
        var sec: i64 = 0;
        var tz_offset: i64 = 0;
        if (input.len >= 19 and input[10] == ' ' and input[13] == ':' and input[16] == ':') {
            hour = std.fmt.parseInt(i64, input[11..13], 10) catch 0;
            min = std.fmt.parseInt(i64, input[14..16], 10) catch 0;
            sec = std.fmt.parseInt(i64, input[17..19], 10) catch 0;
            var rest = input[19..];
            while (rest.len > 0 and rest[0] == ' ') rest = rest[1..];
            if (rest.len > 0) {
                if (parseTimezoneOffset(rest)) |off| tz_offset = off;
            }
        }
        return .{ .int = dateToTimestamp(year, month, day, hour, min, sec) - tz_offset };
    }

    // DD.MM.YYYY EU date format
    if (input.len >= 10 and input[2] == '.' and input[5] == '.') {
        const day = std.fmt.parseInt(i64, input[0..2], 10) catch null;
        const month = std.fmt.parseInt(i64, input[3..5], 10) catch null;
        const year = std.fmt.parseInt(i64, input[6..10], 10) catch null;
        if (day != null and month != null and year != null) {
            var hour: i64 = 0;
            var min: i64 = 0;
            var sec: i64 = 0;
            if (input.len >= 19 and input[10] == ' ' and input[13] == ':' and input[16] == ':') {
                hour = std.fmt.parseInt(i64, input[11..13], 10) catch 0;
                min = std.fmt.parseInt(i64, input[14..16], 10) catch 0;
                sec = std.fmt.parseInt(i64, input[17..19], 10) catch 0;
            }
            return .{ .int = dateToTimestamp(year.?, month.?, day.?, hour, min, sec) };
        }
    }

    // RFC 2822: "Mon, 15 Jan 2025 10:30:45 +0000" or "15 Jan 2025 10:30:45 GMT"
    if (tryParseRfc2822(input)) |ts| return .{ .int = ts };

    // textual month dates: "January 15, 2025", "Jan 15, 2025", "Jan 15 2025", "15 Jan 2025"
    if (tryParseTextualDate(input)) |ts| return .{ .int = ts };

    return parseRelativeTime(input, base);
}

fn tryParseTextualDate(input: []const u8) ?i64 {
    const full_months = [_][]const u8{ "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december" };
    const short_months = [_][]const u8{ "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec" };

    var s = input;
    while (s.len > 0 and s[0] == ' ') s = s[1..];

    // check if starts with a number (DD Month YYYY format)
    var leading_day: ?i64 = null;
    if (s.len >= 2 and s[0] >= '0' and s[0] <= '9') {
        var dend: usize = 0;
        while (dend < s.len and s[dend] >= '0' and s[dend] <= '9') dend += 1;
        if (dend <= 2 and dend < s.len and s[dend] == ' ') {
            leading_day = std.fmt.parseInt(i64, s[0..dend], 10) catch null;
            if (leading_day != null) s = s[dend + 1 ..];
        }
    }

    var month_num: ?i64 = null;
    var match_len: usize = 0;
    for (full_months, 1..) |name, i| {
        if (s.len >= name.len and eqlLower(s[0..name.len], name)) {
            month_num = @intCast(i);
            match_len = name.len;
            break;
        }
    }
    if (month_num == null) {
        for (short_months, 1..) |name, i| {
            if (s.len >= name.len and eqlLower(s[0..name.len], name)) {
                month_num = @intCast(i);
                match_len = name.len;
                break;
            }
        }
    }
    if (month_num == null) return null;
    s = s[match_len..];

    if (leading_day) |dd| {
        // DD Month YYYY
        while (s.len > 0 and (s[0] == ' ' or s[0] == ',')) s = s[1..];
        var yend: usize = 0;
        while (yend < s.len and s[yend] >= '0' and s[yend] <= '9') yend += 1;
        if (yend == 0) return null;
        const year = std.fmt.parseInt(i64, s[0..yend], 10) catch return null;
        return dateToTimestamp(year, month_num.?, dd, 0, 0, 0);
    }

    // Month DD[,] YYYY or Month DD
    while (s.len > 0 and s[0] == ' ') s = s[1..];
    var dend: usize = 0;
    while (dend < s.len and s[dend] >= '0' and s[dend] <= '9') dend += 1;
    if (dend == 0) return null;
    const day = std.fmt.parseInt(i64, s[0..dend], 10) catch return null;
    s = s[dend..];
    while (s.len > 0 and (s[0] == ' ' or s[0] == ',')) s = s[1..];
    if (s.len == 0) return null;
    var yend: usize = 0;
    while (yend < s.len and s[yend] >= '0' and s[yend] <= '9') yend += 1;
    if (yend == 0) return null;
    const year = std.fmt.parseInt(i64, s[0..yend], 10) catch return null;
    return dateToTimestamp(year, month_num.?, day, 0, 0, 0);
}

fn native_time(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = std.time.timestamp() };
}

fn native_checkdate(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3) return .{ .bool = false };
    const month = Value.toInt(args[0]);
    const day = Value.toInt(args[1]);
    const year = Value.toInt(args[2]);
    if (year < 1 or year > 32767 or month < 1 or month > 12 or day < 1) return .{ .bool = false };
    const days_in_month = [_]i64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var max_day = days_in_month[@intCast(month - 1)];
    if (month == 2) {
        const y: u32 = @intCast(year);
        if (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)) max_day = 29;
    }
    return .{ .bool = day <= max_day };
}

fn native_getdate(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const timestamp: i64 = if (args.len >= 1) Value.toInt(args[0]) else std.time.timestamp();
    const epoch_secs: u64 = @intCast(if (timestamp < 0) 0 else timestamp);
    const es = std.time.epoch.EpochSeconds{ .secs = epoch_secs };
    const day_seconds = es.getDaySeconds();
    const epoch_day = es.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_num: i64 = @intCast(epoch_day.day);
    const dow: i64 = @intCast(@mod(day_num + 4, 7)); // 0=sunday

    var arr = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .string = "seconds" }, .{ .int = day_seconds.getSecondsIntoMinute() });
    try arr.set(ctx.allocator, .{ .string = "minutes" }, .{ .int = day_seconds.getMinutesIntoHour() });
    try arr.set(ctx.allocator, .{ .string = "hours" }, .{ .int = day_seconds.getHoursIntoDay() });
    try arr.set(ctx.allocator, .{ .string = "mday" }, .{ .int = @as(i64, month_day.day_index) + 1 });
    try arr.set(ctx.allocator, .{ .string = "wday" }, .{ .int = dow });
    try arr.set(ctx.allocator, .{ .string = "mon" }, .{ .int = month_day.month.numeric() });
    try arr.set(ctx.allocator, .{ .string = "year" }, .{ .int = year_day.year });
    const jan1_ts = dateToTimestamp(year_day.year, 1, 1, 0, 0, 0);
    const jan1_es = std.time.epoch.EpochSeconds{ .secs = @intCast(if (jan1_ts < 0) 0 else jan1_ts) };
    const jan1_day: i64 = @intCast(jan1_es.getEpochDay().day);
    const cur_day: i64 = @intCast(epoch_day.day);
    try arr.set(ctx.allocator, .{ .string = "yday" }, .{ .int = cur_day - jan1_day });
    try arr.set(ctx.allocator, .{ .string = "weekday" }, .{ .string = ([_][]const u8{ "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" })[@intCast(dow)] });
    try arr.set(ctx.allocator, .{ .string = "month" }, .{ .string = ([_][]const u8{ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" })[@intCast(month_day.month.numeric() - 1)] });
    try arr.set(ctx.allocator, .{ .string = "0" }, .{ .int = timestamp });
    return .{ .array = arr };
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

// date/time utilities

pub fn dateToTimestamp(year: i64, month: i64, day: i64, hour: i64, min: i64, sec: i64) i64 {
    // normalize month overflow/underflow (e.g. month 13 -> january next year)
    const adj_month = @mod(month - 1, @as(i64, 12)) + 1;
    const adj_year = year + @divFloor(month - 1, @as(i64, 12));
    const m = adj_month;
    const y = adj_year - @as(i64, if (m <= 2) 1 else 0);
    const era: i64 = @divFloor(if (y >= 0) y else y - 399, 400);
    const yoe: i64 = y - era * 400;
    const mp: i64 = if (m > 2) m - 3 else m + 9;
    const doy = @divFloor(153 * mp + 2, 5) + day - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    const days = era * 146097 + doe - 719468;
    return days * 86400 + hour * 3600 + min * 60 + sec;
}

pub fn parseRelativeTime(input: []const u8, base: i64) Value {
    var s = input;
    while (s.len > 0 and s[0] == ' ') s = s[1..];
    while (s.len > 0 and s[s.len - 1] == ' ') s = s[0 .. s.len - 1];
    if (s.len == 0) return .{ .bool = false };

    // "now"
    if (eqlLower(s, "now")) return .{ .int = base };

    // "today", "yesterday", "tomorrow", "midnight", "noon"
    if (tryParseKeyword(s, base)) |ts| return .{ .int = ts };

    // ordinal weekday: "first Monday of March 2025", "second Tuesday of next month", "last Friday of December"
    if (tryParseOrdinalWeekday(s, base)) |ts| return .{ .int = ts };

    // "first day of ..." / "last day of ..."
    if (tryParseFirstLastDay(s, base)) |ts| return .{ .int = ts };

    // "next/last <weekday>" or "next/last month/year"
    if (tryParseNextLast(s, base)) |ts| return .{ .int = ts };

    // weekday name alone ("Monday", "Thursday") - next occurrence
    if (parseWeekdayName(s)) |target_dow| {
        return .{ .int = resolveNextWeekday(base, target_dow) };
    }

    // numeric relative: "+3 days", "-1 month", "2 weeks", "3 days ago"
    return parseNumericRelative(s, base);
}

fn tryParseKeyword(s: []const u8, base: i64) ?i64 {
    const midnight_ts = baseMidnight(base);
    if (eqlLower(s, "today") or eqlLower(s, "midnight")) return midnight_ts;
    if (eqlLower(s, "yesterday")) return midnight_ts - 86400;
    if (eqlLower(s, "tomorrow")) return midnight_ts + 86400;
    if (eqlLower(s, "noon")) return midnight_ts + 43200;
    return null;
}

fn tryParseFirstLastDay(input: []const u8, base: i64) ?i64 {
    var s = input;
    const is_first = startsWithLower(s, "first day of ");
    const is_last = startsWithLower(s, "last day of ");
    if (!is_first and !is_last) return null;

    s = if (is_first) s[13..] else s[12..];
    while (s.len > 0 and s[0] == ' ') s = s[1..];

    const comps = baseComponents(base);
    var year = comps.year;
    var month = comps.month;
    var hour = comps.hour;
    var min = comps.min;
    var sec = comps.sec;

    if (eqlLower(s, "this month")) {
        // use current month
    } else if (eqlLower(s, "next month")) {
        month += 1;
        if (month > 12) { month = 1; year += 1; }
    } else if (eqlLower(s, "last month") or eqlLower(s, "previous month")) {
        month -= 1;
        if (month < 1) { month = 12; year -= 1; }
    } else if (parseMonthName(s) != null) {
        month = parseMonthName(s).?;
        const mname_len = monthNameLen(s);
        var rest = s[mname_len..];
        while (rest.len > 0 and rest[0] == ' ') rest = rest[1..];
        if (rest.len >= 4) {
            if (std.fmt.parseInt(i64, rest[0..4], 10) catch null) |y| {
                year = y;
            }
        }
        hour = 0;
        min = 0;
        sec = 0;
    } else {
        return null;
    }

    const day: i64 = if (is_first) 1 else daysInMonth(month, year);
    return dateToTimestamp(year, month, day, hour, min, sec);
}

fn tryParseNextLast(input: []const u8, base: i64) ?i64 {
    var s = input;
    var direction: i64 = 0;
    if (startsWithLower(s, "next ")) {
        direction = 1;
        s = s[5..];
    } else if (startsWithLower(s, "last ")) {
        direction = -1;
        s = s[5..];
    } else {
        return null;
    }
    while (s.len > 0 and s[0] == ' ') s = s[1..];

    // next/last month or year
    if (eqlLower(s, "month") or eqlLower(s, "year")) {
        const comps = baseComponents(base);
        var year = comps.year;
        var month = comps.month;
        if (eqlLower(s, "year")) {
            year += direction;
        } else {
            month += direction;
        }
        if (month > 12) { year += @divFloor(month - 1, 12); month = @mod(month - 1, 12) + 1; }
        if (month < 1) { year += @divFloor(month - 12, 12); month = @mod(month - 1, 12) + 1; }
        return dateToTimestamp(year, month, comps.day, comps.hour, comps.min, comps.sec);
    }

    // next/last week - Monday of next/previous week, preserving time
    if (eqlLower(s, "week")) {
        const comps = baseComponents(base);
        const midnight = baseMidnight(base);
        const epoch_secs: u64 = @intCast(if (midnight < 0) 0 else midnight);
        const es = std.time.epoch.EpochSeconds{ .secs = epoch_secs };
        const epoch_day = es.getEpochDay();
        const day_num: i64 = @intCast(epoch_day.day);
        const current_dow: i64 = @mod(day_num + 3, 7); // 0=Mon
        const current_monday = midnight - current_dow * 86400;
        const target_monday = current_monday + direction * 7 * 86400;
        return target_monday + comps.hour * 3600 + comps.min * 60 + comps.sec;
    }

    // next/last <weekday>
    if (parseWeekdayName(s)) |target_dow| {
        if (direction > 0) {
            return resolveNextWeekday(base, target_dow);
        } else {
            return resolveLastWeekday(base, target_dow);
        }
    }

    return null;
}

fn parseNumericRelative(input: []const u8, base: i64) Value {
    var s = input;
    var result = base;

    // handle chained relative parts: "+1 year 2 months 3 days"
    while (s.len > 0) {
        while (s.len > 0 and s[0] == ' ') s = s[1..];
        if (s.len == 0) break;

        var sign: i64 = 1;
        if (s[0] == '-') {
            sign = -1;
            s = s[1..];
        } else if (s[0] == '+') {
            s = s[1..];
        }
        while (s.len > 0 and s[0] == ' ') s = s[1..];

        var num_end: usize = 0;
        while (num_end < s.len and s[num_end] >= '0' and s[num_end] <= '9') num_end += 1;
        if (num_end == 0) return .{ .bool = false };
        const num = std.fmt.parseInt(i64, s[0..num_end], 10) catch return Value{ .bool = false };
        s = s[num_end..];
        while (s.len > 0 and s[0] == ' ') s = s[1..];

        const unit = parseUnit(s) orelse return Value{ .bool = false };
        s = s[unit.consumed..];
        while (s.len > 0 and s[0] == ' ') s = s[1..];

        // check for "ago" suffix
        var effective_sign = sign;
        if (startsWithLower(s, "ago")) {
            effective_sign = -effective_sign;
            s = s[3..];
            while (s.len > 0 and s[0] == ' ') s = s[1..];
        }

        result = applyUnit(result, num * effective_sign, unit.kind);
    }

    if (result == base and input.len > 0) return .{ .bool = false };
    return .{ .int = result };
}

const UnitKind = enum { second, minute, hour, day, week, month, year };
const UnitResult = struct { kind: UnitKind, consumed: usize };

fn parseUnit(s: []const u8) ?UnitResult {
    const units = [_]struct { prefix: []const u8, kind: UnitKind }{
        .{ .prefix = "second", .kind = .second },
        .{ .prefix = "minute", .kind = .minute },
        .{ .prefix = "hour", .kind = .hour },
        .{ .prefix = "day", .kind = .day },
        .{ .prefix = "week", .kind = .week },
        .{ .prefix = "month", .kind = .month },
        .{ .prefix = "year", .kind = .year },
    };
    for (units) |u| {
        if (startsWithLower(s, u.prefix)) {
            var consumed = u.prefix.len;
            if (consumed < s.len and (s[consumed] == 's' or s[consumed] == 'S')) consumed += 1;
            return .{ .kind = u.kind, .consumed = consumed };
        }
    }
    return null;
}

fn applyUnit(base: i64, delta: i64, kind: UnitKind) i64 {
    return switch (kind) {
        .second => base + delta,
        .minute => base + delta * 60,
        .hour => base + delta * 3600,
        .day => base + delta * 86400,
        .week => base + delta * 604800,
        .month, .year => blk: {
            const comps = baseComponents(base);
            var year = comps.year;
            var month = comps.month;
            if (kind == .year) { year += delta; } else { month += delta; }
            if (month > 12) { year += @divFloor(month - 1, 12); month = @mod(month - 1, 12) + 1; }
            if (month < 1) { year += @divFloor(month - 12, 12); month = @mod(month - 1, 12) + 1; }
            break :blk dateToTimestamp(year, month, comps.day, comps.hour, comps.min, comps.sec);
        },
    };
}

fn parseWeekdayName(s: []const u8) ?u3 {
    const full = [_][]const u8{ "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday" };
    const short = [_][]const u8{ "mon", "tue", "wed", "thu", "fri", "sat", "sun" };
    for (full, 0..) |name, i| {
        if (s.len >= name.len and eqlLower(s[0..name.len], name)) return @intCast(i);
    }
    for (short, 0..) |name, i| {
        if (s.len == name.len and eqlLower(s[0..name.len], name)) return @intCast(i);
    }
    return null;
}

fn resolveNextWeekday(base: i64, target_dow: u3) i64 {
    const midnight = baseMidnight(base);
    const epoch_secs: u64 = @intCast(if (midnight < 0) 0 else midnight);
    const es = std.time.epoch.EpochSeconds{ .secs = epoch_secs };
    const epoch_day = es.getEpochDay();
    const day_num: i64 = @intCast(epoch_day.day);
    const current_dow: u3 = @intCast(@mod(day_num + 3, 7));
    var diff: i64 = @as(i64, target_dow) - @as(i64, current_dow);
    if (diff <= 0) diff += 7;
    return midnight + diff * 86400;
}

fn resolveLastWeekday(base: i64, target_dow: u3) i64 {
    const midnight = baseMidnight(base);
    const epoch_secs: u64 = @intCast(if (midnight < 0) 0 else midnight);
    const es = std.time.epoch.EpochSeconds{ .secs = epoch_secs };
    const epoch_day = es.getEpochDay();
    const day_num: i64 = @intCast(epoch_day.day);
    const current_dow: u3 = @intCast(@mod(day_num + 3, 7));
    var diff: i64 = @as(i64, current_dow) - @as(i64, target_dow);
    if (diff <= 0) diff += 7;
    return midnight - diff * 86400;
}

const DateComponents = struct { year: i64, month: i64, day: i64, hour: i64, min: i64, sec: i64 };

fn baseComponents(base: i64) DateComponents {
    const epoch_secs: u64 = @intCast(if (base < 0) 0 else base);
    const es = std.time.epoch.EpochSeconds{ .secs = epoch_secs };
    const day_seconds = es.getDaySeconds();
    const epoch_day = es.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    return .{
        .year = @intCast(year_day.year),
        .month = @intCast(month_day.month.numeric()),
        .day = @intCast(month_day.day_index + 1),
        .hour = @intCast(day_seconds.getHoursIntoDay()),
        .min = @intCast(day_seconds.getMinutesIntoHour()),
        .sec = @intCast(day_seconds.getSecondsIntoMinute()),
    };
}

fn baseMidnight(base: i64) i64 {
    return base - @mod(base, 86400);
}

fn parseMonthName(s: []const u8) ?i64 {
    const months = [_][]const u8{ "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december" };
    for (months, 1..) |name, i| {
        if (s.len >= name.len and eqlLower(s[0..name.len], name)) return @intCast(i);
    }
    return null;
}

fn monthNameLen(s: []const u8) usize {
    const months = [_][]const u8{ "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december" };
    for (months) |name| {
        if (s.len >= name.len and eqlLower(s[0..name.len], name)) return name.len;
    }
    return 0;
}

fn eqlLower(a: []const u8, lower_b: []const u8) bool {
    if (a.len != lower_b.len) return false;
    for (a, lower_b) |ca, cb| {
        const la: u8 = if (ca >= 'A' and ca <= 'Z') ca + 32 else ca;
        if (la != cb) return false;
    }
    return true;
}

fn startsWithLower(s: []const u8, lower_prefix: []const u8) bool {
    if (s.len < lower_prefix.len) return false;
    return eqlLower(s[0..lower_prefix.len], lower_prefix);
}

fn daysInMonth(month: i64, year: i64) i64 {
    const days = [_]i64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    const m: usize = @intCast(if (month < 1) 0 else if (month > 12) 11 else month - 1);
    var d = days[m];
    if (m == 1) {
        const y = if (year < 0) -year else year;
        if (@mod(y, 4) == 0 and (@mod(y, 100) != 0 or @mod(y, 400) == 0)) d = 29;
    }
    return d;
}

fn parseTimezoneOffset(s: []const u8) ?i64 {
    // numeric: +0000, -0500, +05:30
    if (s.len >= 5 and (s[0] == '+' or s[0] == '-')) {
        const sign: i64 = if (s[0] == '-') -1 else 1;
        if (s.len >= 6 and s[3] == ':') {
            // +05:30 format
            const h = std.fmt.parseInt(i64, s[1..3], 10) catch return null;
            const m = std.fmt.parseInt(i64, s[4..6], 10) catch return null;
            return sign * (h * 3600 + m * 60);
        }
        const h = std.fmt.parseInt(i64, s[1..3], 10) catch return null;
        const m = std.fmt.parseInt(i64, s[3..5], 10) catch return null;
        return sign * (h * 3600 + m * 60);
    }
    // named abbreviations
    const zones = [_]struct { name: []const u8, offset: i64 }{
        .{ .name = "utc", .offset = 0 },
        .{ .name = "gmt", .offset = 0 },
        .{ .name = "est", .offset = -5 * 3600 },
        .{ .name = "edt", .offset = -4 * 3600 },
        .{ .name = "cst", .offset = -6 * 3600 },
        .{ .name = "cdt", .offset = -5 * 3600 },
        .{ .name = "mst", .offset = -7 * 3600 },
        .{ .name = "mdt", .offset = -6 * 3600 },
        .{ .name = "pst", .offset = -8 * 3600 },
        .{ .name = "pdt", .offset = -7 * 3600 },
    };
    for (zones) |z| {
        if (s.len >= z.name.len and eqlLower(s[0..z.name.len], z.name)) return z.offset;
    }
    return null;
}

fn tryParseRfc2822(input: []const u8) ?i64 {
    var s = input;
    while (s.len > 0 and s[0] == ' ') s = s[1..];

    // skip optional "Day, " prefix (e.g. "Mon, ")
    if (s.len >= 5 and s[3] == ',' and s[4] == ' ') {
        s = s[5..];
        while (s.len > 0 and s[0] == ' ') s = s[1..];
    }

    // DD Mon YYYY HH:MM:SS
    var dend: usize = 0;
    while (dend < s.len and s[dend] >= '0' and s[dend] <= '9') dend += 1;
    if (dend == 0 or dend > 2 or dend >= s.len or s[dend] != ' ') return null;
    const day = std.fmt.parseInt(i64, s[0..dend], 10) catch return null;
    s = s[dend + 1 ..];

    // month abbreviation
    const short_months = [_][]const u8{ "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec" };
    var month: i64 = 0;
    for (short_months, 1..) |name, i| {
        if (s.len >= 3 and eqlLower(s[0..3], name)) {
            month = @intCast(i);
            break;
        }
    }
    if (month == 0) return null;
    s = s[3..];
    if (s.len == 0 or s[0] != ' ') return null;
    s = s[1..];

    // YYYY
    if (s.len < 4) return null;
    const year = std.fmt.parseInt(i64, s[0..4], 10) catch return null;
    s = s[4..];

    var hour: i64 = 0;
    var min: i64 = 0;
    var sec: i64 = 0;
    var tz_offset: i64 = 0;

    if (s.len >= 9 and s[0] == ' ' and s[3] == ':' and s[6] == ':') {
        hour = std.fmt.parseInt(i64, s[1..3], 10) catch 0;
        min = std.fmt.parseInt(i64, s[4..6], 10) catch 0;
        sec = std.fmt.parseInt(i64, s[7..9], 10) catch 0;
        s = s[9..];
        while (s.len > 0 and s[0] == ' ') s = s[1..];
        if (s.len > 0) {
            if (parseTimezoneOffset(s)) |off| tz_offset = off;
        }
    }

    return dateToTimestamp(year, month, day, hour, min, sec) - tz_offset;
}

fn tryParseOrdinalWeekday(input: []const u8, base: i64) ?i64 {
    var s = input;
    while (s.len > 0 and s[0] == ' ') s = s[1..];

    // parse ordinal: first/second/third/fourth/fifth/last or 1st/2nd/3rd/4th/5th
    const ordinals = [_]struct { name: []const u8, val: i64 }{
        .{ .name = "first", .val = 1 },
        .{ .name = "second", .val = 2 },
        .{ .name = "third", .val = 3 },
        .{ .name = "fourth", .val = 4 },
        .{ .name = "fifth", .val = 5 },
    };
    var ordinal: i64 = 0;
    var is_last = false;
    if (startsWithLower(s, "last ")) {
        is_last = true;
        s = s[5..];
    } else {
        for (ordinals) |o| {
            if (startsWithLower(s, o.name) and s.len > o.name.len and s[o.name.len] == ' ') {
                ordinal = o.val;
                s = s[o.name.len + 1 ..];
                break;
            }
        }
        if (ordinal == 0) return null;
    }

    // parse weekday name
    while (s.len > 0 and s[0] == ' ') s = s[1..];
    const target_dow = parseWeekdayName(s) orelse return null;
    // advance past weekday name
    const full_days = [_][]const u8{ "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday" };
    const short_days = [_][]const u8{ "mon", "tue", "wed", "thu", "fri", "sat", "sun" };
    var consumed: usize = 0;
    for (full_days) |name| {
        if (s.len >= name.len and eqlLower(s[0..name.len], name)) {
            consumed = name.len;
            break;
        }
    }
    if (consumed == 0) {
        for (short_days) |name| {
            if (s.len >= name.len and eqlLower(s[0..name.len], name)) {
                consumed = name.len;
                break;
            }
        }
    }
    s = s[consumed..];
    while (s.len > 0 and s[0] == ' ') s = s[1..];

    // expect "of"
    if (!startsWithLower(s, "of ")) return null;
    s = s[3..];
    while (s.len > 0 and s[0] == ' ') s = s[1..];

    // parse month context: "March 2025", "next month", "last month", "January", month name alone
    const comps = baseComponents(base);
    var year = comps.year;
    var month: i64 = comps.month;

    if (startsWithLower(s, "next month")) {
        month += 1;
        if (month > 12) { month = 1; year += 1; }
    } else if (startsWithLower(s, "last month")) {
        month -= 1;
        if (month < 1) { month = 12; year -= 1; }
    } else if (startsWithLower(s, "this month")) {
        // use current
    } else if (parseMonthName(s)) |m| {
        month = m;
        const mlen = monthNameLen(s);
        var rest = s[mlen..];
        while (rest.len > 0 and rest[0] == ' ') rest = rest[1..];
        if (rest.len >= 4) {
            if (std.fmt.parseInt(i64, rest[0..4], 10) catch null) |y| year = y;
        }
    } else {
        return null;
    }

    if (is_last) {
        // find the last occurrence of target_dow in the month
        const dim = daysInMonth(month, year);
        const last_day_ts = dateToTimestamp(year, month, dim, 0, 0, 0);
        const last_epoch: u64 = @intCast(if (last_day_ts < 0) 0 else last_day_ts);
        const last_es = std.time.epoch.EpochSeconds{ .secs = last_epoch };
        const last_day_num: i64 = @intCast(last_es.getEpochDay().day);
        const last_dow: i64 = @mod(last_day_num + 3, 7); // 0=Mon
        var diff = last_dow - @as(i64, target_dow);
        if (diff < 0) diff += 7;
        return dateToTimestamp(year, month, dim - diff, 0, 0, 0);
    }

    // find the Nth occurrence of target_dow in the month
    const first_ts = dateToTimestamp(year, month, 1, 0, 0, 0);
    const first_epoch: u64 = @intCast(if (first_ts < 0) 0 else first_ts);
    const first_es = std.time.epoch.EpochSeconds{ .secs = first_epoch };
    const first_day_num: i64 = @intCast(first_es.getEpochDay().day);
    const first_dow: i64 = @mod(first_day_num + 3, 7); // 0=Mon
    var days_to_first = @as(i64, target_dow) - first_dow;
    if (days_to_first < 0) days_to_first += 7;
    const result_day = 1 + days_to_first + (ordinal - 1) * 7;
    if (result_day > daysInMonth(month, year)) return null;
    return dateToTimestamp(year, month, result_day, 0, 0, 0);
}

fn startsWith(s: []const u8, prefix: []const u8) bool {
    return s.len >= prefix.len and std.mem.eql(u8, s[0..prefix.len], prefix);
}

// gmdate is identical to date since zphp timestamps are always UTC
fn native_gmdate(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return native_date(ctx, args);
}

// timezone stubs - zphp always runs in UTC
fn native_tz_set(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = true };
}

fn native_tz_get(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    _ = ctx;
    return .{ .string = "UTC" };
}

const IsoDuration = struct { y: i64, m: i64, d: i64, h: i64, mi: i64, s: i64, f: f64 };

fn parseIsoDuration(spec: []const u8) IsoDuration {
    var result = IsoDuration{ .y = 0, .m = 0, .d = 0, .h = 0, .mi = 0, .s = 0, .f = 0 };
    if (spec.len == 0 or spec[0] != 'P') return result;
    var in_time = false;
    var num_start: ?usize = null;
    for (spec[1..], 1..) |c, idx| {
        if (c >= '0' and c <= '9' or c == '.') {
            if (num_start == null) num_start = idx;
        } else if (c == 'T') {
            in_time = true;
            num_start = null;
        } else if (num_start) |ns| {
            const num_str = spec[ns..idx];
            if (std.mem.indexOf(u8, num_str, ".")) |_| {
                const val = std.fmt.parseFloat(f64, num_str) catch 0.0;
                if (in_time and c == 'S') {
                    result.s = @intFromFloat(val);
                    result.f = val - @as(f64, @floatFromInt(result.s));
                }
            } else {
                const val = std.fmt.parseInt(i64, num_str, 10) catch 0;
                if (!in_time) {
                    switch (c) {
                        'Y' => result.y = val,
                        'M' => result.m = val,
                        'D' => result.d = val,
                        'W' => result.d = val * 7,
                        else => {},
                    }
                } else {
                    switch (c) {
                        'H' => result.h = val,
                        'M' => result.mi = val,
                        'S' => result.s = val,
                        else => {},
                    }
                }
            }
            num_start = null;
        }
    }
    return result;
}

fn diConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len > 0 and args[0] == .string) {
        const dur = parseIsoDuration(args[0].string);
        try obj.set(ctx.allocator, "y", .{ .int = dur.y });
        try obj.set(ctx.allocator, "m", .{ .int = dur.m });
        try obj.set(ctx.allocator, "d", .{ .int = dur.d });
        try obj.set(ctx.allocator, "h", .{ .int = dur.h });
        try obj.set(ctx.allocator, "i", .{ .int = dur.mi });
        try obj.set(ctx.allocator, "s", .{ .int = dur.s });
        try obj.set(ctx.allocator, "f", .{ .float = dur.f });
    }
    try obj.set(ctx.allocator, "invert", .{ .int = 0 });
    try obj.set(ctx.allocator, "days", .{ .int = 0 });
    return .null;
}

fn diInvert(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len > 0) {
        const invert = if (args[0] == .bool) (if (args[0].bool) @as(i64, 1) else @as(i64, 0))
        else if (args[0] == .int) (if (args[0].int != 0) @as(i64, 1) else @as(i64, 0))
        else @as(i64, 0);
        try obj.set(ctx.allocator, "invert", .{ .int = invert });
    }
    return .{ .object = obj };
}
