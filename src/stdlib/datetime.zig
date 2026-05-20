const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

const DT_FORMAT_CONSTS = .{
    .{ "ATOM", "Y-m-d\\TH:i:sP" },
    .{ "COOKIE", "l, d-M-Y H:i:s T" },
    .{ "ISO8601", "Y-m-d\\TH:i:sO" },
    .{ "ISO8601_EXPANDED", "X-m-d\\TH:i:sP" },
    .{ "RFC822", "D, d M y H:i:s O" },
    .{ "RFC850", "l, d-M-y H:i:s T" },
    .{ "RFC1036", "D, d M y H:i:s O" },
    .{ "RFC1123", "D, d M Y H:i:s O" },
    .{ "RFC2822", "D, d M Y H:i:s O" },
    .{ "RFC3339", "Y-m-d\\TH:i:sP" },
    .{ "RFC3339_EXTENDED", "Y-m-d\\TH:i:s.vP" },
    .{ "RFC7231", "D, d M Y H:i:s \\G\\M\\T" },
    .{ "RSS", "D, d M Y H:i:s O" },
    .{ "W3C", "Y-m-d\\TH:i:sP" },
};

pub const entries = .{
    .{ "date", native_date },
    .{ "date_create", native_date_create },
    .{ "date_create_immutable", native_date_create_immutable },
    .{ "date_create_from_format", native_date_create_from_format },
    .{ "date_create_immutable_from_format", native_date_create_immutable_from_format },
    .{ "date_format", native_date_format },
    .{ "date_modify", native_date_modify },
    .{ "date_add", native_date_add },
    .{ "date_sub", native_date_sub },
    .{ "date_diff", native_date_diff },
    .{ "date_timestamp_get", native_date_timestamp_get },
    .{ "date_timestamp_set", native_date_timestamp_set },
    .{ "date_date_set", native_date_date_set },
    .{ "date_time_set", native_date_time_set },
    .{ "date_parse", native_date_parse },
    .{ "date_parse_from_format", native_date_parse_from_format },
    .{ "mktime", native_mktime },
    .{ "gmmktime", native_gmmktime },
    .{ "strtotime", native_strtotime },
    .{ "time", native_time },
    .{ "microtime", native_microtime },
    .{ "hrtime", native_hrtime },
    .{ "checkdate", native_checkdate },
    .{ "cal_days_in_month", native_cal_days_in_month },
    .{ "getdate", native_getdate },
    .{ "gmdate", native_gmdate },
    .{ "date_default_timezone_set", native_tz_set },
    .{ "date_default_timezone_get", native_tz_get },
    .{ "timezone_identifiers_list", dtzListIdentifiers },
    .{ "timezone_abbreviations_list", dtzListAbbreviations },
    .{ "timezone_name_get", native_timezone_name_get },
    .{ "timezone_offset_get", native_timezone_offset_get },
    .{ "timezone_open", native_timezone_open },
    .{ "date_timezone_get", native_date_timezone_get },
    .{ "date_timezone_set", native_date_timezone_set },
    .{ "localtime", native_localtime },
    .{ "idate", native_idate },
    .{ "date_interval_create_from_date_string", native_date_interval_create_from_date_string },
    .{ "date_interval_format", native_date_interval_format },
};

pub fn register(vm: *VM, a: Allocator) !void {
    // DateTimeInterface
    var iface = vm_mod.InterfaceDef{ .name = "DateTimeInterface" };
    try iface.methods.append(a, "format");
    try iface.methods.append(a, "getTimestamp");
    try vm.interfaces.put(a, "DateTimeInterface", iface);

    // shadow class so DateTimeInterface::ATOM-style constant lookups resolve
    var dti_const = ClassDef{ .name = "DateTimeInterface", .is_abstract = true };
    inline for (DT_FORMAT_CONSTS) |c| {
        try dti_const.static_props.put(a, c[0], .{ .string = c[1] });
    }
    try vm.classes.put(a, "DateTimeInterface", dti_const);

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
    try dt_def.methods.put(a, "setTime", .{ .name = "setTime", .arity = 4 });
    try dt_def.methods.put(a, "setISODate", .{ .name = "setISODate", .arity = 2 });
    try dt_def.methods.put(a, "createFromTimestamp", .{ .name = "createFromTimestamp", .arity = 1, .is_static = true });
    try dt_def.methods.put(a, "createFromFormat", .{ .name = "createFromFormat", .arity = 2, .is_static = true });
    try dt_def.methods.put(a, "getMicrosecond", .{ .name = "getMicrosecond", .arity = 0 });
    try dt_def.methods.put(a, "setMicrosecond", .{ .name = "setMicrosecond", .arity = 1 });
    try dt_def.methods.put(a, "getLastErrors", .{ .name = "getLastErrors", .arity = 0, .is_static = true });
    try dt_def.methods.put(a, "getTimezone", .{ .name = "getTimezone", .arity = 0 });
    try dt_def.methods.put(a, "setTimezone", .{ .name = "setTimezone", .arity = 1 });
    try dt_def.methods.put(a, "getOffset", .{ .name = "getOffset", .arity = 0 });
    try dt_def.methods.put(a, "createFromImmutable", .{ .name = "createFromImmutable", .arity = 1, .is_static = true });
    try dt_def.methods.put(a, "createFromInterface", .{ .name = "createFromInterface", .arity = 1, .is_static = true });
    inline for (DT_FORMAT_CONSTS) |c| {
        try dt_def.static_props.put(a, c[0], .{ .string = c[1] });
    }
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
    try vm.native_fns.put(a, "DateTime::setISODate", dtSetISODate);
    try vm.native_fns.put(a, "DateTime::createFromTimestamp", dtCreateFromTimestamp);
    try vm.native_fns.put(a, "DateTime::createFromFormat", dtCreateFromFormat);
    try vm.native_fns.put(a, "DateTime::getMicrosecond", dtGetMicrosecond);
    try vm.native_fns.put(a, "DateTime::setMicrosecond", dtSetMicrosecond);
    try vm.native_fns.put(a, "DateTime::getLastErrors", dtGetLastErrors);
    try vm.native_fns.put(a, "DateTime::getTimezone", dtGetTimezone);
    try vm.native_fns.put(a, "DateTime::setTimezone", dtSetTimezone);
    try vm.native_fns.put(a, "DateTime::getOffset", dtGetOffset);
    try vm.native_fns.put(a, "DateTimeImmutable::getOffset", dtGetOffset);

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
    try dti_def.methods.put(a, "getOffset", .{ .name = "getOffset", .arity = 0 });
    try dti_def.methods.put(a, "createFromFormat", .{ .name = "createFromFormat", .arity = 2, .is_static = true });
    try dti_def.methods.put(a, "createFromMutable", .{ .name = "createFromMutable", .arity = 1, .is_static = true });
    try dti_def.methods.put(a, "createFromInterface", .{ .name = "createFromInterface", .arity = 1, .is_static = true });
    try dti_def.methods.put(a, "setISODate", .{ .name = "setISODate", .arity = 2 });
    inline for (DT_FORMAT_CONSTS) |c| {
        try dti_def.static_props.put(a, c[0], .{ .string = c[1] });
    }
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
    try vm.native_fns.put(a, "DateTimeImmutable::setDate", dtiSetDate);
    try vm.native_fns.put(a, "DateTimeImmutable::setTime", dtiSetTime);
    try vm.native_fns.put(a, "DateTimeImmutable::setISODate", dtiSetISODate);
    try vm.native_fns.put(a, "DateTimeImmutable::setTimestamp", dtiSetTimestamp);
    try vm.native_fns.put(a, "DateTimeImmutable::createFromMutable", dtiCreateFromMutable);
    try vm.native_fns.put(a, "DateTime::createFromImmutable", dtCreateFromImmutable);
    try vm.native_fns.put(a, "DateTime::createFromInterface", dtCreateFromInterface);
    try vm.native_fns.put(a, "DateTimeImmutable::createFromInterface", dtiCreateFromInterface);

    // DateTimeZone class
    var dtz_def = ClassDef{ .name = "DateTimeZone" };
    try dtz_def.properties.append(a, .{ .name = "timezone", .default = .{ .string = "UTC" }, .visibility = .private });
    try dtz_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try dtz_def.methods.put(a, "getName", .{ .name = "getName", .arity = 0 });
    try dtz_def.methods.put(a, "getOffset", .{ .name = "getOffset", .arity = 1 });
    try dtz_def.methods.put(a, "__toString", .{ .name = "__toString", .arity = 0 });
    try dtz_def.methods.put(a, "listIdentifiers", .{ .name = "listIdentifiers", .arity = 2, .is_static = true });
    try dtz_def.methods.put(a, "listAbbreviations", .{ .name = "listAbbreviations", .arity = 0, .is_static = true });
    try dtz_def.methods.put(a, "getLocation", .{ .name = "getLocation", .arity = 0 });
    try dtz_def.methods.put(a, "getTransitions", .{ .name = "getTransitions", .arity = 2 });
    try vm.classes.put(a, "DateTimeZone", dtz_def);

    try vm.native_fns.put(a, "DateTimeZone::__construct", dtzConstruct);
    try vm.native_fns.put(a, "DateTimeZone::getName", dtzGetName);
    try vm.native_fns.put(a, "DateTimeZone::getOffset", dtzGetOffset);
    try vm.native_fns.put(a, "DateTimeZone::__toString", dtzGetName);
    try vm.native_fns.put(a, "DateTimeZone::listIdentifiers", dtzListIdentifiers);
    try vm.native_fns.put(a, "DateTimeZone::listAbbreviations", dtzListAbbreviations);
    try vm.native_fns.put(a, "DateTimeZone::getLocation", dtzGetLocation);
    try vm.native_fns.put(a, "DateTimeZone::getTransitions", dtzGetTransitions);

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
    try vm.native_fns.put(a, "DateInterval::createFromDateString", diCreateFromDateString);
    try vm.native_fns.put(a, "DateInterval::format", diFormat);

    // DatePeriod
    var dp_def = ClassDef{ .name = "DatePeriod" };
    try dp_def.static_props.put(a, "EXCLUDE_START_DATE", .{ .int = 1 });
    try dp_def.static_props.put(a, "INCLUDE_END_DATE", .{ .int = 2 });
    try dp_def.constant_names.put(a, "EXCLUDE_START_DATE", {});
    try dp_def.constant_names.put(a, "INCLUDE_END_DATE", {});
    try dp_def.interfaces.append(a, "IteratorAggregate");
    try dp_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 3 });
    try dp_def.methods.put(a, "getStartDate", .{ .name = "getStartDate", .arity = 0 });
    try dp_def.methods.put(a, "getEndDate", .{ .name = "getEndDate", .arity = 0 });
    try dp_def.methods.put(a, "getDateInterval", .{ .name = "getDateInterval", .arity = 0 });
    try dp_def.methods.put(a, "getRecurrences", .{ .name = "getRecurrences", .arity = 0 });
    try dp_def.methods.put(a, "getIterator", .{ .name = "getIterator", .arity = 0 });
    try vm.classes.put(a, "DatePeriod", dp_def);
    try vm.native_fns.put(a, "DatePeriod::__construct", dpConstruct);
    try vm.native_fns.put(a, "DatePeriod::getStartDate", dpGetStart);
    try vm.native_fns.put(a, "DatePeriod::getEndDate", dpGetEnd);
    try vm.native_fns.put(a, "DatePeriod::getDateInterval", dpGetInterval);
    try vm.native_fns.put(a, "DatePeriod::getRecurrences", dpGetRecurrences);
    try vm.native_fns.put(a, "DatePeriod::getIterator", dpGetIterator);

    var dpi_def = ClassDef{ .name = "DatePeriodIterator" };
    try dpi_def.interfaces.append(a, "Iterator");
    try dpi_def.methods.put(a, "current", .{ .name = "current", .arity = 0 });
    try dpi_def.methods.put(a, "key", .{ .name = "key", .arity = 0 });
    try dpi_def.methods.put(a, "next", .{ .name = "next", .arity = 0 });
    try dpi_def.methods.put(a, "rewind", .{ .name = "rewind", .arity = 0 });
    try dpi_def.methods.put(a, "valid", .{ .name = "valid", .arity = 0 });
    try vm.classes.put(a, "DatePeriodIterator", dpi_def);
    try vm.native_fns.put(a, "DatePeriodIterator::current", dpiCurrent);
    try vm.native_fns.put(a, "DatePeriodIterator::key", dpiKey);
    try vm.native_fns.put(a, "DatePeriodIterator::next", dpiNext);
    try vm.native_fns.put(a, "DatePeriodIterator::rewind", dpiRewind);
    try vm.native_fns.put(a, "DatePeriodIterator::valid", dpiValid);
}

// parse a "YYYY-MM-DD" or "YYYY-MM-DDTHH:MM:SS" (optional trailing Z) date
// string to a unix timestamp interpreted as UTC. used by the ISO 8601
// DatePeriod string form
fn parseIsoDateToTs(s: []const u8) ?i64 {
    if (s.len < 10 or s[4] != '-' or s[7] != '-') return null;
    const year = std.fmt.parseInt(i64, s[0..4], 10) catch return null;
    const month = std.fmt.parseInt(i64, s[5..7], 10) catch return null;
    const day = std.fmt.parseInt(i64, s[8..10], 10) catch return null;
    var hour: i64 = 0;
    var min: i64 = 0;
    var sec: i64 = 0;
    if (s.len >= 19 and (s[10] == 'T' or s[10] == ' ') and s[13] == ':' and s[16] == ':') {
        hour = std.fmt.parseInt(i64, s[11..13], 10) catch 0;
        min = std.fmt.parseInt(i64, s[14..16], 10) catch 0;
        sec = std.fmt.parseInt(i64, s[17..19], 10) catch 0;
    }
    return dateToTimestamp(year, month, day, hour, min, sec);
}

fn dpConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;

    // ISO 8601 recurring-interval string form: "R<n>/<start>/<interval>"
    // e.g. new DatePeriod('R3/2024-01-01T00:00:00Z/P1D'). PHP's string
    // constructor only accepts the R-prefixed recurring form; the bare
    // start/interval/end string is a DateMalformedPeriodStringException there
    if (args.len >= 1 and args[0] == .string) {
        const spec = args[0].string;
        var it = std.mem.splitScalar(u8, spec, '/');
        const p0 = it.next() orelse return .null;
        const p1 = it.next() orelse return .null;
        const p2 = it.next() orelse return .null;
        if (p0.len < 2 or (p0[0] != 'R' and p0[0] != 'r')) return .null;
        const recurrences = std.fmt.parseInt(i64, p0[1..], 10) catch 0;
        const start_ts = parseIsoDateToTs(p1) orelse return .null;
        const start_obj = try ctx.createObject("DateTime");
        try start_obj.set(ctx.allocator, "timestamp", .{ .int = start_ts });
        try obj.set(ctx.allocator, "__start", .{ .object = start_obj });

        const dur = parseIsoDuration(p2);
        const di_obj = try ctx.createObject("DateInterval");
        try di_obj.set(ctx.allocator, "y", .{ .int = dur.y });
        try di_obj.set(ctx.allocator, "m", .{ .int = dur.m });
        try di_obj.set(ctx.allocator, "d", .{ .int = dur.d });
        try di_obj.set(ctx.allocator, "h", .{ .int = dur.h });
        try di_obj.set(ctx.allocator, "i", .{ .int = dur.mi });
        try di_obj.set(ctx.allocator, "s", .{ .int = dur.s });
        try di_obj.set(ctx.allocator, "f", .{ .float = dur.f });
        try di_obj.set(ctx.allocator, "invert", .{ .int = 0 });
        try di_obj.set(ctx.allocator, "days", .{ .bool = false });
        try obj.set(ctx.allocator, "__interval", .{ .object = di_obj });

        try obj.set(ctx.allocator, "__recurrences", .{ .int = recurrences });
        if (args.len >= 2 and args[1] == .int) try obj.set(ctx.allocator, "__options", args[1]);
        return .null;
    }

    if (args.len < 3) return .null;
    if (args[0] != .object or args[1] != .object) return .null;
    try obj.set(ctx.allocator, "__start", args[0]);
    try obj.set(ctx.allocator, "__interval", args[1]);
    if (args[2] == .object) {
        try obj.set(ctx.allocator, "__end", args[2]);
    } else if (args[2] == .int) {
        try obj.set(ctx.allocator, "__recurrences", args[2]);
    }
    if (args.len >= 4) try obj.set(ctx.allocator, "__options", args[3]);
    return .null;
}

fn dpGetStart(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    return obj.get("__start");
}

fn dpGetEnd(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    return obj.get("__end");
}

fn dpGetInterval(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    return obj.get("__interval");
}

fn dpGetRecurrences(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    // explicitly stored recurrence count (third constructor arg was an int).
    // when constructed with an end-DateTime instead, PHP returns null
    const rec = obj.get("__recurrences");
    if (rec == .int) return rec;
    return .null;
}

fn dpGetIterator(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const iter = try ctx.vm.allocator.create(@import("../runtime/value.zig").PhpObject);
    iter.* = .{ .class_name = "DatePeriodIterator" };
    try ctx.vm.objects.append(ctx.vm.allocator, iter);
    try iter.set(ctx.allocator, "__start", obj.get("__start"));
    try iter.set(ctx.allocator, "__end", obj.get("__end"));
    try iter.set(ctx.allocator, "__interval", obj.get("__interval"));
    try iter.set(ctx.allocator, "__recurrences", obj.get("__recurrences"));
    const opts = obj.get("__options");
    const exclude_start = opts == .int and (opts.int & 1) != 0;
    const include_end = opts == .int and (opts.int & 2) != 0;
    const start_v = obj.get("__start");
    if (start_v != .object) return .null;
    var ts = getTimestamp(start_v.object);
    if (exclude_start) {
        const di = obj.get("__interval");
        if (di == .object) {
            const tz_name = objTzName(start_v.object, ctx.vm.default_tz_name);
            ts = applyIntervalTz(ts, di.object, 1, tz_name);
        }
    }
    try iter.set(ctx.allocator, "__cursor_ts", .{ .int = ts });
    try iter.set(ctx.allocator, "__index", .{ .int = 0 });
    try iter.set(ctx.allocator, "__exclude_start", .{ .bool = exclude_start });
    try iter.set(ctx.allocator, "__include_end", .{ .bool = include_end });
    return .{ .object = iter };
}

fn dpiTimestampInRange(this: *@import("../runtime/value.zig").PhpObject) bool {
    const ts = Value.toInt(this.get("__cursor_ts"));
    const end_v = this.get("__end");
    if (end_v == .object) {
        const end_ts = getTimestamp(end_v.object);
        const include_end = this.get("__include_end") == .bool and this.get("__include_end").bool;
        return if (include_end) ts <= end_ts else ts < end_ts;
    }
    const rec_v = this.get("__recurrences");
    if (rec_v == .int) {
        const exclude_start = this.get("__exclude_start") == .bool and this.get("__exclude_start").bool;
        const idx = Value.toInt(this.get("__index"));
        return if (exclude_start) idx < rec_v.int else idx <= rec_v.int;
    }
    return false;
}

fn dpiCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    if (!dpiTimestampInRange(this)) return .{ .bool = false };
    const ts = Value.toInt(this.get("__cursor_ts"));
    const dt = try ctx.createObject("DateTime");
    try dt.set(ctx.allocator, "timestamp", .{ .int = ts });
    const start_v = this.get("__start");
    if (start_v == .object) {
        const tz = start_v.object.get("__timezone");
        if (tz == .string) try dt.set(ctx.allocator, "__timezone", tz);
    }
    return .{ .object = dt };
}

fn dpiKey(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    return this.get("__index");
}

fn dpiNext(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const di = this.get("__interval");
    if (di == .object) {
        const cur = Value.toInt(this.get("__cursor_ts"));
        const start_v = this.get("__start");
        const tz_name = if (start_v == .object) objTzName(start_v.object, ctx.vm.default_tz_name) else ctx.vm.default_tz_name;
        try this.set(ctx.allocator, "__cursor_ts", .{ .int = applyIntervalTz(cur, di.object, 1, tz_name) });
    }
    const idx = Value.toInt(this.get("__index"));
    try this.set(ctx.allocator, "__index", .{ .int = idx + 1 });
    return .null;
}

fn dpiRewind(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .null;
}

fn dpiValid(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    return .{ .bool = dpiTimestampInRange(this) };
}

fn dtGetLastErrors(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    // PHP 8.2+: returns false when the most recent parse succeeded;
    // returns the structured error array on failure. zphp tracks failure
    // as a single flag without preserving per-position error detail (porting
    // PHP's full parser would be substantial), so emit two placeholder
    // entries that match the count() shape of PHP's typical responses
    if (!ctx.vm.last_dt_parse_failed) return .{ .bool = false };
    var result = try ctx.createArray();
    try result.set(ctx.allocator, .{ .string = "warning_count" }, .{ .int = 0 });
    try result.set(ctx.allocator, .{ .string = "warnings" }, .{ .array = try ctx.createArray() });
    try result.set(ctx.allocator, .{ .string = "error_count" }, .{ .int = @intCast(ctx.vm.last_dt_error_count) });
    var errors_arr = try ctx.createArray();
    try errors_arr.set(ctx.allocator, .{ .int = 0 }, .{ .string = "A four digit year could not be found" });
    try errors_arr.set(ctx.allocator, .{ .int = @intCast(ctx.vm.last_dt_error_pos) }, .{ .string = ctx.vm.last_dt_error_text });
    try result.set(ctx.allocator, .{ .string = "errors" }, .{ .array = errors_arr });
    return .{ .array = result };
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

    // extract timezone from second arg
    var tz_name = ctx.vm.default_tz_name;
    if (args.len >= 2) {
        tz_name = extractTimezoneName(args[1..]);
    }
    try obj.set(ctx.allocator, "__timezone", .{ .string = tz_name });

    if (args.len >= 1 and args[0] == .string) {
        const s = args[0].string;
        if (s.len == 0 or std.mem.eql(u8, s, "now")) {
            // default: current time (UTC), no conversion needed
        } else if (s.len >= 2 and s[0] == '@') {
            ts = std.fmt.parseInt(i64, s[1..], 10) catch ts;
        } else if (s.len >= 10 and s[4] == '-' and s[7] == '-') {
            const year = std.fmt.parseInt(i64, s[0..4], 10) catch 1970;
            const month = std.fmt.parseInt(i64, s[5..7], 10) catch 1;
            const day = std.fmt.parseInt(i64, s[8..10], 10) catch 1;
            var hour: i64 = 0;
            var min: i64 = 0;
            var sec: i64 = 0;
            var pos: usize = 10;
            if (s.len >= 19 and (s[10] == ' ' or s[10] == 'T') and s[13] == ':' and s[16] == ':') {
                hour = std.fmt.parseInt(i64, s[11..13], 10) catch 0;
                min = std.fmt.parseInt(i64, s[14..16], 10) catch 0;
                sec = std.fmt.parseInt(i64, s[17..19], 10) catch 0;
                pos = 19;
            } else if (s.len >= 16 and (s[10] == ' ' or s[10] == 'T') and s[13] == ':') {
                hour = std.fmt.parseInt(i64, s[11..13], 10) catch 0;
                min = std.fmt.parseInt(i64, s[14..16], 10) catch 0;
                pos = 16;
            }
            // skip fractional seconds
            if (pos < s.len and s[pos] == '.') {
                pos += 1;
                while (pos < s.len and s[pos] >= '0' and s[pos] <= '9') pos += 1;
            }
            while (pos < s.len and s[pos] == ' ') pos += 1;
            // try trailing timezone
            var explicit_offset: ?i64 = null;
            var explicit_name: ?[]const u8 = null;
            if (pos < s.len) {
                const rest = s[pos..];
                if (rest.len >= 1 and (rest[0] == 'Z' or rest[0] == 'z')) {
                    explicit_offset = 0;
                    explicit_name = "+00:00";
                } else if (parseTimezoneOffset(rest)) |off| {
                    explicit_offset = off;
                    // when the suffix is a named zone (not numeric +HH:MM),
                    // preserve the name so format('T'/'e') can report the
                    // abbreviation correctly instead of just an offset
                    const trimmed = std.mem.trim(u8, rest, " \t");
                    const is_numeric = trimmed.len > 0 and (trimmed[0] == '+' or trimmed[0] == '-');
                    if (!is_numeric) {
                        const owned = try ctx.allocator.dupe(u8, trimmed);
                        try ctx.vm.strings.append(ctx.allocator, owned);
                        explicit_name = owned;
                    } else {
                        const abs_off: i64 = if (off < 0) -off else off;
                        const oh: i64 = @divTrunc(abs_off, 3600);
                        const om: i64 = @mod(@divTrunc(abs_off, 60), 60);
                        var nm_buf: [8]u8 = undefined;
                        nm_buf[0] = if (off < 0) '-' else '+';
                        nm_buf[1] = @intCast(@divTrunc(oh, 10) + '0');
                        nm_buf[2] = @intCast(@mod(oh, 10) + '0');
                        nm_buf[3] = ':';
                        nm_buf[4] = @intCast(@divTrunc(om, 10) + '0');
                        nm_buf[5] = @intCast(@mod(om, 10) + '0');
                        const nm = nm_buf[0..6];
                        const owned = try ctx.allocator.dupe(u8, nm);
                        try ctx.vm.strings.append(ctx.allocator, owned);
                        explicit_name = owned;
                    }
                }
            }
            ts = dateToTimestamp(year, month, day, hour, min, sec);
            if (explicit_offset) |off| {
                ts -= off;
                try obj.set(ctx.allocator, "__timezone", .{ .string = explicit_name.? });
            } else if (lookupTimezone(tz_name)) |tz| {
                ts -= @as(i64, tzOffsetForWall(tz, ts));
            }
        } else {
            const result = parseRelativeTime(s, ts);
            if (result == .int) {
                ts = result.int;
            } else {
                // parseRelativeTime returns bool(false) when it failed to
                // recognize the format at all - PHP throws
                // DateMalformedStringException here
                const msg = try std.fmt.allocPrint(ctx.allocator, "Failed to parse time string ({s}) at position 0", .{s});
                try ctx.strings.append(ctx.allocator, msg);
                try ctx.vm.setPendingException("DateMalformedStringException", msg);
                return error.RuntimeError;
            }
        }
    }

    try obj.set(ctx.allocator, "timestamp", .{ .int = ts });
    return .null;
}

fn dtFormat(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len == 0 or args[0] != .string) return .{ .string = "" };
    const ts = getTimestamp(obj);
    const tz_val = obj.get("__timezone");
    const tz_name = if (tz_val == .string) tz_val.string else ctx.vm.default_tz_name;
    const offset = if (lookupTimezone(tz_name)) |tz| tzOffsetAt(tz, ts) else @as(i32, 0);
    const us_v = obj.get("__microseconds");
    const us: i64 = if (us_v == .int) us_v.int else 0;
    return formatTimestampTzMicros(ctx, ts, args[0].string, offset, tz_name, us);
}

pub fn formatTimestamp(ctx: *NativeContext, timestamp: i64, format: []const u8) RuntimeError!Value {
    const tz_name = ctx.vm.default_tz_name;
    const offset = if (lookupTimezone(tz_name)) |tz| tzOffsetAt(tz, timestamp) else @as(i32, 0);
    return formatTimestampTzMicros(ctx, timestamp, format, offset, tz_name, 0);
}

pub fn formatTimestampTz(ctx: *NativeContext, timestamp: i64, format: []const u8, tz_offset: i32, tz_name: []const u8) RuntimeError!Value {
    return formatTimestampTzMicros(ctx, timestamp, format, tz_offset, tz_name, 0);
}

pub fn formatTimestampTzMicros(ctx: *NativeContext, timestamp: i64, format: []const u8, tz_offset: i32, tz_name: []const u8, microseconds: i64) RuntimeError!Value {
    const local_ts = timestamp + @as(i64, tz_offset);
    const dc = baseComponents(local_ts);
    const day_seconds = FmtDaySec{ .h = @intCast(dc.hour), .mi = @intCast(dc.min), .s = @intCast(dc.sec) };
    const epoch_day = FmtEpochDay{ .day = @divFloor(local_ts, 86400) };
    const year_day = FmtYearDay{ .year = dc.year };
    const month_day = FmtMonthDay{ .month = .{ .v = @intCast(dc.month) }, .day_index = @intCast(dc.day - 1) };
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
            'h' => {
                const h = day_seconds.getHoursIntoDay();
                const h12: u32 = if (h == 0) 12 else if (h > 12) h - 12 else h;
                var tmp: [4]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d:0>2}", .{h12}) catch "00";
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
                const s = std.fmt.bufPrint(&tmp, "{d}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}", .{
                    year_day.year,
                    month_day.month.numeric(),
                    month_day.day_index + 1,
                    day_seconds.getHoursIntoDay(),
                    day_seconds.getMinutesIntoHour(),
                    day_seconds.getSecondsIntoMinute(),
                }) catch "0000-00-00T00:00:00";
                try buf.appendSlice(a, s);
                try appendOffsetColon(&buf, a, tz_offset);
            },
            'r' => {
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
                const s2 = std.fmt.bufPrint(&tmp, " {d} {d:0>2}:{d:0>2}:{d:0>2} ", .{
                    year_day.year,
                    day_seconds.getHoursIntoDay(),
                    day_seconds.getMinutesIntoHour(),
                    day_seconds.getSecondsIntoMinute(),
                }) catch " 0000 00:00:00 ";
                try buf.appendSlice(a, s2);
                try appendOffsetCompact(&buf, a, tz_offset);
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
                const week = isoWeek(@intCast(epoch_day.day));
                var tmp: [4]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d:0>2}", .{week.week}) catch "01";
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
                const week = isoWeek(@intCast(epoch_day.day));
                var tmp: [8]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{week.year}) catch "0000";
                try buf.appendSlice(a, s);
            },
            'X' => {
                // PHP 8.4: ISO 8601 expanded year with mandatory leading sign,
                // four-digit minimum
                var tmp: [12]u8 = undefined;
                const yr = year_day.year;
                const s = if (yr >= 0)
                    std.fmt.bufPrint(&tmp, "+{d:0>4}", .{@as(u64, @intCast(yr))}) catch "+0000"
                else
                    std.fmt.bufPrint(&tmp, "-{d:0>4}", .{@as(u64, @intCast(-yr))}) catch "-0000";
                try buf.appendSlice(a, s);
            },
            'x' => {
                // PHP 8.4: like X but the leading sign is omitted for years
                // in [0, 9999]
                var tmp: [12]u8 = undefined;
                const yr = year_day.year;
                const s = if (yr < 0)
                    std.fmt.bufPrint(&tmp, "-{d:0>4}", .{@as(u64, @intCast(-yr))}) catch "-0000"
                else if (yr > 9999)
                    std.fmt.bufPrint(&tmp, "+{d}", .{@as(u64, @intCast(yr))}) catch "+0000"
                else
                    std.fmt.bufPrint(&tmp, "{d:0>4}", .{@as(u64, @intCast(yr))}) catch "0000";
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
            'u' => {
                var tmp: [16]u8 = undefined;
                const us_abs: u64 = @intCast(if (microseconds < 0) -microseconds else microseconds);
                const s = std.fmt.bufPrint(&tmp, "{d:0>6}", .{us_abs}) catch "000000";
                try buf.appendSlice(a, s);
            },
            'v' => {
                var tmp: [16]u8 = undefined;
                const ms_abs: u64 = @intCast(@divFloor(if (microseconds < 0) -microseconds else microseconds, 1000));
                const s = std.fmt.bufPrint(&tmp, "{d:0>3}", .{ms_abs}) catch "000";
                try buf.appendSlice(a, s);
            },
            'Z' => {
                var tmp: [12]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{tz_offset}) catch "0";
                try buf.appendSlice(a, s);
            },
            'e' => {
                try buf.appendSlice(a, tz_name);
            },
            'T' => {
                if (lookupTimezone(tz_name)) |tz| {
                    try buf.appendSlice(a, tzAbbrevAt(tz, timestamp));
                } else {
                    try buf.appendSlice(a, tz_name);
                }
            },
            'P' => {
                try appendOffsetColon(&buf, a, tz_offset);
            },
            'O' => {
                try appendOffsetCompact(&buf, a, tz_offset);
            },
            'I' => try buf.append(a, '0'),
            'B' => {
                // Swatch internet time: BMT = UTC+1; 1000 beats per day; .beats = (utc_secs+3600) / 86.4 % 1000
                const utc_secs: i64 = @mod(timestamp, 86400);
                const bmt = @mod(utc_secs + 3600, 86400);
                const beats: u32 = @intFromFloat(@as(f64, @floatFromInt(bmt)) / 86.4);
                var tmp: [4]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d:0>3}", .{beats}) catch "000";
                try buf.appendSlice(a, s);
            },
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

// add a DateInterval to a timestamp using calendar arithmetic for y/m/d so
// month-length variation and 31st-of-month rollover behave like PHP
fn applyInterval(ts: i64, interval: *PhpObject, sign: i64) i64 {
    return applyIntervalTz(ts, interval, sign, ctx_default_tz);
}

var ctx_default_tz: []const u8 = "UTC";

fn applyIntervalTz(ts: i64, interval: *PhpObject, sign: i64, tz_name: []const u8) i64 {
    const y = Value.toInt(interval.get("y"));
    const m = Value.toInt(interval.get("m"));
    const d = Value.toInt(interval.get("d"));
    const h = Value.toInt(interval.get("h"));
    const i = Value.toInt(interval.get("i"));
    const s = Value.toInt(interval.get("s"));
    const invert = Value.toInt(interval.get("invert"));
    const direction: i64 = if (invert != 0) -sign else sign;

    // calendar arithmetic for y/m/d happens in the receiver's timezone so
    // crossing DST doesn't bleed into the wall-clock time
    const tz = lookupTimezone(tz_name);
    const off_in: i64 = if (tz) |t| @as(i64, tzOffsetAt(t, ts)) else 0;
    const c = baseComponents(ts + off_in);
    var year: i64 = c.year + direction * y;
    var month: i64 = c.month + direction * m;
    while (month > 12) : ({ month -= 12; year += 1; }) {}
    while (month < 1) : ({ month += 12; year -= 1; }) {}
    const day: i64 = c.day + direction * d;

    var local_ts = dateToTimestamp(year, month, day, c.hour, c.min, c.sec);
    // convert local back to UTC
    if (tz) |t| {
        const off_out: i64 = @as(i64, tzOffsetAt(t, local_ts));
        local_ts -= off_out;
    }
    local_ts += direction * (h * 3600 + i * 60 + s);
    return local_ts;
}

fn objTzName(obj: *PhpObject, fallback: []const u8) []const u8 {
    const v = obj.get("__timezone");
    return if (v == .string) v.string else fallback;
}

fn dtAdd(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len == 0 or args[0] != .object) return .{ .object = obj };
    const ts = getTimestamp(obj);
    const new_ts = applyIntervalTz(ts, args[0].object, 1, objTzName(obj, ctx.vm.default_tz_name));
    try obj.set(ctx.allocator, "timestamp", .{ .int = new_ts });
    return .{ .object = obj };
}

fn dtSub(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len == 0 or args[0] != .object) return .{ .object = obj };
    const ts = getTimestamp(obj);
    const new_ts = applyIntervalTz(ts, args[0].object, -1, objTzName(obj, ctx.vm.default_tz_name));
    try obj.set(ctx.allocator, "timestamp", .{ .int = new_ts });
    return .{ .object = obj };
}

fn dtiAdd(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len == 0 or args[0] != .object) return .{ .object = obj };
    const ts = getTimestamp(obj);
    const new_ts = applyIntervalTz(ts, args[0].object, 1, objTzName(obj, ctx.vm.default_tz_name));
    const new_obj = try ctx.createObject("DateTimeImmutable");
    try new_obj.set(ctx.allocator, "timestamp", .{ .int = new_ts });
    if (obj.get("__timezone") == .string) try new_obj.set(ctx.allocator, "__timezone", obj.get("__timezone"));
    return .{ .object = new_obj };
}

fn dtiSub(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len == 0 or args[0] != .object) return .{ .object = obj };
    const ts = getTimestamp(obj);
    const new_ts = applyIntervalTz(ts, args[0].object, -1, objTzName(obj, ctx.vm.default_tz_name));
    const new_obj = try ctx.createObject("DateTimeImmutable");
    try new_obj.set(ctx.allocator, "timestamp", .{ .int = new_ts });
    if (obj.get("__timezone") == .string) try new_obj.set(ctx.allocator, "__timezone", obj.get("__timezone"));
    return .{ .object = new_obj };
}

fn dtDiff(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len == 0 or args[0] != .object) return .null;
    const other = args[0].object;
    const ts1 = getTimestamp(obj);
    const ts2 = getTimestamp(other);
    // PHP: $a->diff($b) — invert is 1 only if $b is earlier than $a
    var diff_secs = ts2 - ts1;
    const invert: i64 = if (diff_secs < 0) 1 else 0;
    if (diff_secs < 0) diff_secs = -diff_secs;

    // `days` is the total elapsed days, rounded to nearest. floor would
    // mis-report `Mar 9 00:00 → Mar 10 00:00` (which spans spring forward and
    // is 82800s real, i.e. 0.958 days) as 0 — PHP reports 1
    const total_days = @divFloor(diff_secs + 43200, 86400);

    const early_ts = if (ts1 < ts2) ts1 else ts2;
    const late_ts = if (ts1 < ts2) ts2 else ts1;
    // calendar arithmetic happens in the receiver's timezone so DST boundaries
    // don't bleed into hour-of-day computation
    const tz_val = obj.get("__timezone");
    const tz_name = if (tz_val == .string) tz_val.string else ctx.vm.default_tz_name;
    const tz = lookupTimezone(tz_name);
    const off_early: i64 = if (tz) |t| @as(i64, tzOffsetAt(t, early_ts)) else 0;
    const off_late: i64 = if (tz) |t| @as(i64, tzOffsetAt(t, late_ts)) else 0;
    const c1 = baseComponents(early_ts + off_early);
    const c2 = baseComponents(late_ts + off_late);

    var s = c2.sec - c1.sec;
    var mi = c2.min - c1.min;
    var hh = c2.hour - c1.hour;
    var d = c2.day - c1.day;
    var mo = c2.month - c1.month;
    var y = c2.year - c1.year;
    if (s < 0) { s += 60; mi -= 1; }
    if (mi < 0) { mi += 60; hh -= 1; }
    if (hh < 0) { hh += 24; d -= 1; }
    if (d < 0) {
        const borrow_month: i64 = if (invert == 0) c2.month - 1 else c1.month;
        const borrow_year: i64 = if (invert == 0) c2.year else c1.year;
        var bm = borrow_month;
        var by = borrow_year;
        if (bm == 0) { bm = 12; by -= 1; }
        d += daysInMonth(bm, by);
        mo -= 1;
    }
    if (mo < 0) { mo += 12; y -= 1; }

    // DST correction: when the diff is entirely within one calendar day, PHP
    // reports REAL elapsed h/i/s rather than wall-clock subtraction, so
    // spring-forward `01:30 EST → 03:30 EDT` is 1h (real) not 2h (wall) and
    // fall-back `01:30 EDT → 03:30 EST` is 3h (real) not 1h (wall).
    // for multi-day diffs we leave the calendar walk alone — PHP's algorithm
    // there treats d as wall-calendar days
    if (y == 0 and mo == 0 and d == 0 and total_days == 0) {
        const remaining_secs = diff_secs;
        s = @mod(remaining_secs, 60);
        mi = @mod(@divFloor(remaining_secs, 60), 60);
        hh = @divFloor(remaining_secs, 3600);
    }

    const interval = try ctx.createObject("DateInterval");
    try interval.set(ctx.allocator, "y", .{ .int = y });
    try interval.set(ctx.allocator, "m", .{ .int = mo });
    try interval.set(ctx.allocator, "d", .{ .int = d });
    try interval.set(ctx.allocator, "days", .{ .int = total_days });
    try interval.set(ctx.allocator, "h", .{ .int = hh });
    try interval.set(ctx.allocator, "i", .{ .int = mi });
    try interval.set(ctx.allocator, "s", .{ .int = s });
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
    // 4th arg is microseconds (PHP 7.1+); the 'u'/'v' format specifiers read
    // __microseconds. setTime with <4 args resets the sub-second part to 0
    const micros: i64 = if (args.len >= 4) Value.toInt(args[3]) else 0;
    try obj.set(ctx.allocator, "__microseconds", .{ .int = micros });
    return .{ .object = obj };
}

fn dtiSetDate(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
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
    const new_obj = try ctx.createObject("DateTimeImmutable");
    try new_obj.set(ctx.allocator, "timestamp", .{ .int = new_ts });
    const tz = obj.get("__timezone");
    if (tz != .null) try new_obj.set(ctx.allocator, "__timezone", tz);
    return .{ .object = new_obj };
}

// ISO 8601 week date -> Gregorian date: jan 4 always falls in ISO week 1
// (the iso-week that contains the first Thursday of the year). The Monday
// of week 1 is jan4 minus (iso_dow_of_jan4 - 1) days, then advance by
// (week - 1) * 7 + (day - 1) days
fn isoWeekDateToTimestamp(year: i64, week: i64, day_of_week: i64, h: i64, m: i64, s: i64) i64 {
    // jan 4 unix timestamp at 00:00
    const jan4_ts = dateToTimestamp(year, 1, 4, 0, 0, 0);
    // PHP date('N') for jan 4: 1..7 (Monday..Sunday)
    const day_of_jan4 = @divFloor(jan4_ts, 86400);
    // 1970-01-01 was Thursday -> N=4. so iso_dow = ((day_of_jan4 + 3) mod 7) + 1
    var dow = @mod(day_of_jan4 + 3, 7) + 1;
    if (dow < 1) dow += 7;
    const offset_days = (week - 1) * 7 + (day_of_week - 1) - (dow - 1);
    const target_ts = jan4_ts + offset_days * 86400;
    return target_ts + h * 3600 + m * 60 + s;
}

fn dtSetISODate(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len < 2) return .{ .object = obj };
    const year = Value.toInt(args[0]);
    const week = Value.toInt(args[1]);
    const dow = if (args.len >= 3) Value.toInt(args[2]) else 1;
    const ts = getTimestamp(obj);
    const epoch_secs: u64 = @intCast(if (ts < 0) 0 else ts);
    const es = std.time.epoch.EpochSeconds{ .secs = epoch_secs };
    const day_seconds = es.getDaySeconds();
    const h: i64 = day_seconds.getHoursIntoDay();
    const m: i64 = day_seconds.getMinutesIntoHour();
    const s: i64 = day_seconds.getSecondsIntoMinute();
    try obj.set(ctx.allocator, "timestamp", .{ .int = isoWeekDateToTimestamp(year, week, dow, h, m, s) });
    return .{ .object = obj };
}

fn dtiSetISODate(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len < 2) return .{ .object = obj };
    const year = Value.toInt(args[0]);
    const week = Value.toInt(args[1]);
    const dow = if (args.len >= 3) Value.toInt(args[2]) else 1;
    const ts = getTimestamp(obj);
    const epoch_secs: u64 = @intCast(if (ts < 0) 0 else ts);
    const es = std.time.epoch.EpochSeconds{ .secs = epoch_secs };
    const day_seconds = es.getDaySeconds();
    const h: i64 = day_seconds.getHoursIntoDay();
    const m: i64 = day_seconds.getMinutesIntoHour();
    const s: i64 = day_seconds.getSecondsIntoMinute();
    const new_obj = try ctx.createObject("DateTimeImmutable");
    try new_obj.set(ctx.allocator, "timestamp", .{ .int = isoWeekDateToTimestamp(year, week, dow, h, m, s) });
    const tz = obj.get("__timezone");
    if (tz != .null) try new_obj.set(ctx.allocator, "__timezone", tz);
    return .{ .object = new_obj };
}

fn dtiSetTime(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
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
    const new_obj = try ctx.createObject("DateTimeImmutable");
    try new_obj.set(ctx.allocator, "timestamp", .{ .int = new_ts });
    const tz = obj.get("__timezone");
    if (tz != .null) try new_obj.set(ctx.allocator, "__timezone", tz);
    return .{ .object = new_obj };
}

fn dtiSetTimestamp(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len < 1) return .{ .object = obj };
    const new_obj = try ctx.createObject("DateTimeImmutable");
    try new_obj.set(ctx.allocator, "timestamp", .{ .int = Value.toInt(args[0]) });
    const tz = obj.get("__timezone");
    if (tz != .null) try new_obj.set(ctx.allocator, "__timezone", tz);
    return .{ .object = new_obj };
}

fn dtCreateFromTimestamp(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .null;
    const obj = try ctx.createObject("DateTime");
    try obj.set(ctx.allocator, "timestamp", .{ .int = Value.toInt(args[0]) });
    return .{ .object = obj };
}

fn dtCreateFromFormat(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return createFromFormatImpl(ctx, args, "DateTime");
}

fn dtCreateFromImmutable(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .null;
    const src = args[0].object;
    const obj = try ctx.createObject("DateTime");
    try obj.set(ctx.allocator, "timestamp", src.get("timestamp"));
    if (src.get("__timezone") == .string) try obj.set(ctx.allocator, "__timezone", src.get("__timezone"));
    return .{ .object = obj };
}

fn dtiCreateFromMutable(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .null;
    const src = args[0].object;
    const obj = try ctx.createObject("DateTimeImmutable");
    try obj.set(ctx.allocator, "timestamp", src.get("timestamp"));
    if (src.get("__timezone") == .string) try obj.set(ctx.allocator, "__timezone", src.get("__timezone"));
    return .{ .object = obj };
}

// createFromInterface accepts either DateTime or DateTimeImmutable and produces
// the corresponding target type (called as DateTime::createFromInterface or
// DateTimeImmutable::createFromInterface)
fn dtCreateFromInterface(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return dtCreateFromImmutable(ctx, args);
}

fn dtiCreateFromInterface(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return dtiCreateFromMutable(ctx, args);
}

fn native_date_create_from_format(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return createFromFormatImpl(ctx, args, "DateTime");
}

fn native_date_create_immutable_from_format(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return createFromFormatImpl(ctx, args, "DateTimeImmutable");
}

fn createBareDt(ctx: *NativeContext, class_name: []const u8, args: []const Value) RuntimeError!Value {
    const tz_name = if (args.len >= 2) extractTimezoneName(args[1..]) else ctx.vm.default_tz_name;
    var ts: i64 = std.time.timestamp();
    if (args.len >= 1 and args[0] == .string) {
        const s = args[0].string;
        if (s.len == 0 or std.mem.eql(u8, s, "now")) {
            // current
        } else if (s.len >= 2 and s[0] == '@') {
            ts = std.fmt.parseInt(i64, s[1..], 10) catch ts;
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
            if (lookupTimezone(tz_name)) |tz| {
                ts -= @as(i64, tzOffsetForWall(tz, ts));
            }
        } else {
            const result = parseRelativeTime(s, ts);
            if (result == .int) ts = result.int;
        }
    }
    const obj = try ctx.createObject(class_name);
    try obj.set(ctx.allocator, "__timezone", .{ .string = tz_name });
    try obj.set(ctx.allocator, "timestamp", .{ .int = ts });
    return .{ .object = obj };
}

fn native_date_create(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return createBareDt(ctx, "DateTime", args);
}

fn native_date_create_immutable(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return createBareDt(ctx, "DateTimeImmutable", args);
}

fn argObj(args: []const Value) ?*PhpObject {
    if (args.len == 0 or args[0] != .object) return null;
    return args[0].object;
}

fn isImmutable(obj: *PhpObject) bool {
    return std.mem.eql(u8, obj.class_name, "DateTimeImmutable");
}

fn native_date_format(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = argObj(args) orelse return .{ .bool = false };
    if (args.len < 2 or args[1] != .string) return .{ .string = "" };
    const ts = getTimestamp(obj);
    const tz_val = obj.get("__timezone");
    const tz_name = if (tz_val == .string) tz_val.string else ctx.vm.default_tz_name;
    const offset = if (lookupTimezone(tz_name)) |tz| tzOffsetAt(tz, ts) else @as(i32, 0);
    return formatTimestampTz(ctx, ts, args[1].string, offset, tz_name);
}

// procedural alias for DateInterval::createFromDateString
fn native_date_interval_create_from_date_string(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return diCreateFromDateString(ctx, args);
}

// procedural alias for DateInterval::format($interval, $format)
fn native_date_interval_format(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .object or args[1] != .string) return .{ .bool = false };
    const saved = ctx.vm.currentFrame().vars.get("$this");
    try ctx.vm.currentFrame().vars.put(ctx.allocator, "$this", args[0]);
    defer if (saved) |s| (ctx.vm.currentFrame().vars.put(ctx.allocator, "$this", s) catch {});
    return diFormat(ctx, args[1..]);
}

fn native_date_modify(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = argObj(args) orelse return .{ .bool = false };
    if (args.len < 2 or args[1] != .string) return .{ .object = obj };
    const ts = getTimestamp(obj);
    const result = parseRelativeTime(args[1].string, ts);
    if (result != .int) return .{ .bool = false };
    if (isImmutable(obj)) {
        const new_obj = try ctx.createObject("DateTimeImmutable");
        try new_obj.set(ctx.allocator, "timestamp", result);
        if (obj.get("__timezone") == .string) try new_obj.set(ctx.allocator, "__timezone", obj.get("__timezone"));
        return .{ .object = new_obj };
    }
    try obj.set(ctx.allocator, "timestamp", result);
    return .{ .object = obj };
}

fn applyIntervalProc(ctx: *NativeContext, args: []const Value, sign: i64) RuntimeError!Value {
    const obj = argObj(args) orelse return .{ .bool = false };
    if (args.len < 2 or args[1] != .object) return .{ .object = obj };
    const ts = getTimestamp(obj);
    const new_ts = applyInterval(ts, args[1].object, sign);
    if (isImmutable(obj)) {
        const new_obj = try ctx.createObject("DateTimeImmutable");
        try new_obj.set(ctx.allocator, "timestamp", .{ .int = new_ts });
        if (obj.get("__timezone") == .string) try new_obj.set(ctx.allocator, "__timezone", obj.get("__timezone"));
        return .{ .object = new_obj };
    }
    try obj.set(ctx.allocator, "timestamp", .{ .int = new_ts });
    return .{ .object = obj };
}

fn native_date_add(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return applyIntervalProc(ctx, args, 1);
}

fn native_date_sub(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return applyIntervalProc(ctx, args, -1);
}

fn native_date_diff(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .object or args[1] != .object) return .{ .bool = false };
    const synth = [_]Value{args[1]};
    const saved_this = ctx.vm.currentFrame().vars.get("$this");
    try ctx.vm.currentFrame().vars.put(ctx.allocator, "$this", args[0]);
    defer {
        if (saved_this) |v| {
            ctx.vm.currentFrame().vars.put(ctx.allocator, "$this", v) catch {};
        } else {
            _ = ctx.vm.currentFrame().vars.remove("$this");
        }
    }
    return dtDiff(ctx, &synth);
}

fn native_date_timestamp_get(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = argObj(args) orelse return .{ .bool = false };
    return .{ .int = getTimestamp(obj) };
}

fn native_date_timestamp_set(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = argObj(args) orelse return .{ .bool = false };
    if (args.len < 2) return .{ .object = obj };
    try obj.set(ctx.allocator, "timestamp", .{ .int = Value.toInt(args[1]) });
    return .{ .object = obj };
}

fn native_date_date_set(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = argObj(args) orelse return .{ .bool = false };
    if (args.len < 4) return .{ .object = obj };
    const ts = getTimestamp(obj);
    const epoch_secs: u64 = @intCast(if (ts < 0) 0 else ts);
    const es = std.time.epoch.EpochSeconds{ .secs = epoch_secs };
    const day_seconds = es.getDaySeconds();
    const h: i64 = day_seconds.getHoursIntoDay();
    const m: i64 = day_seconds.getMinutesIntoHour();
    const s: i64 = day_seconds.getSecondsIntoMinute();
    const new_ts = dateToTimestamp(Value.toInt(args[1]), Value.toInt(args[2]), Value.toInt(args[3]), h, m, s);
    try obj.set(ctx.allocator, "timestamp", .{ .int = new_ts });
    return .{ .object = obj };
}

fn native_date_time_set(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = argObj(args) orelse return .{ .bool = false };
    if (args.len < 3) return .{ .object = obj };
    const ts = getTimestamp(obj);
    const epoch_secs: u64 = @intCast(if (ts < 0) 0 else ts);
    const es = std.time.epoch.EpochSeconds{ .secs = epoch_secs };
    const epoch_day = es.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const sec: i64 = if (args.len >= 4) Value.toInt(args[3]) else 0;
    const new_ts = dateToTimestamp(@intCast(year_day.year), month_day.month.numeric(), month_day.day_index + 1, Value.toInt(args[1]), Value.toInt(args[2]), sec);
    try obj.set(ctx.allocator, "timestamp", .{ .int = new_ts });
    return .{ .object = obj };
}

fn dtiCreateFromFormat(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return createFromFormatImpl(ctx, args, "DateTimeImmutable");
}

fn createFromFormatImpl(ctx: *NativeContext, args: []const Value, default_class: []const u8) RuntimeError!Value {
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
        break :blk default_class;
    };

    const res = parseDateTimeFormat(format, datetime, std.time.timestamp()) orelse {
        ctx.vm.last_dt_parse_failed = true;
        ctx.vm.last_dt_error_count = 3;
        ctx.vm.last_dt_error_text = "Not enough data available to satisfy format";
        ctx.vm.last_dt_error_pos = @intCast(datetime.len);
        return .{ .bool = false };
    };
    ctx.vm.last_dt_parse_failed = false;
    const obj = try ctx.createObject(class_name);

    // optional 3rd arg: DateTimeZone. PHP applies it as the default zone when
    // the format string didn't already specify one. without this, an explicit
    // tz arg to createFromFormat was ignored and DST/regional offsets were
    // wrong (everything treated as UTC)
    var final_ts = res.ts;
    var tz_name_opt: ?[]const u8 = null;
    if (res.tz_offset_seconds) |off| {
        const sign: u8 = if (off < 0) '-' else '+';
        const abs: u32 = @intCast(if (off < 0) -off else off);
        const hh = abs / 3600;
        const mm = (abs % 3600) / 60;
        const n = try std.fmt.allocPrint(ctx.allocator, "{c}{d:0>2}:{d:0>2}", .{ sign, hh, mm });
        try ctx.strings.append(ctx.allocator, n);
        tz_name_opt = n;
    } else if (args.len >= 3 and args[2] == .object and std.mem.eql(u8, args[2].object.class_name, "DateTimeZone")) {
        const nv = args[2].object.get("timezone");
        if (nv == .string) {
            tz_name_opt = nv.string;
            // adjust timestamp: parseDateTimeFormat returned a UTC-interpreted
            // ts but the user meant the wall clock in the explicit zone.
            // subtract the zone's offset at that moment to get the real UTC ts
            const off: i64 = if (lookupTimezone(nv.string)) |tz| tzOffsetAt(tz, res.ts) else 0;
            final_ts = res.ts - off;
        }
    }
    try obj.set(ctx.allocator, "timestamp", .{ .int = final_ts });
    if (tz_name_opt) |n| try obj.set(ctx.allocator, "__timezone", .{ .string = n });
    if (res.microseconds != 0) try obj.set(ctx.allocator, "__microseconds", .{ .int = res.microseconds });
    return .{ .object = obj };
}

const ParsedDateTime = struct { ts: i64, tz_offset_seconds: ?i32, microseconds: i64 = 0 };

// PHP createFromFormat parser. Supports the common specifiers: Y y m n M F d j D l
// H G h g i s U a A e T P O Z, plus literal escape (\X) and reset markers (! and |).
// Returns null on parse failure (caller maps to PHP `false`).
fn parseDateTimeFormat(format: []const u8, datetime: []const u8, now: i64) ?ParsedDateTime {
    const ncomps = baseComponents(now);
    var year: i64 = ncomps.year;
    var month: i64 = ncomps.month;
    var day: i64 = ncomps.day;
    var hour: i64 = ncomps.hour;
    var min: i64 = ncomps.min;
    var sec: i64 = ncomps.sec;
    var u_ts: ?i64 = null;
    var tz_offset: i64 = 0;
    var tz_parsed: bool = false;
    var is_pm: ?bool = null;
    var hour_is_12: bool = false;
    var microseconds: i64 = 0;

    // PHP `!` reset semantics: track which fields have been parsed so far so `|` can reset the rest
    var parsed_year = false;
    var parsed_month = false;
    var parsed_day = false;
    var parsed_hour = false;
    var parsed_min = false;
    var parsed_sec = false;

    var fi: usize = 0;
    var di: usize = 0;
    while (fi < format.len) : (fi += 1) {
        const c = format[fi];
        switch (c) {
            '!' => {
                year = 1970; month = 1; day = 1;
                hour = 0; min = 0; sec = 0;
                parsed_year = true; parsed_month = true; parsed_day = true;
                parsed_hour = true; parsed_min = true; parsed_sec = true;
            },
            '|' => {
                if (!parsed_year) year = 1970;
                if (!parsed_month) month = 1;
                if (!parsed_day) day = 1;
                if (!parsed_hour) hour = 0;
                if (!parsed_min) min = 0;
                if (!parsed_sec) sec = 0;
            },
            '\\' => {
                fi += 1;
                if (fi >= format.len) return null;
                if (di >= datetime.len or datetime[di] != format[fi]) return null;
                di += 1;
            },
            'Y' => {
                if (di + 4 > datetime.len) return null;
                year = std.fmt.parseInt(i64, datetime[di..di+4], 10) catch return null;
                di += 4;
                parsed_year = true;
            },
            'y' => {
                if (di + 2 > datetime.len) return null;
                const yy = std.fmt.parseInt(i64, datetime[di..di+2], 10) catch return null;
                year = if (yy < 70) 2000 + yy else 1900 + yy;
                di += 2;
                parsed_year = true;
            },
            'm' => {
                if (di + 2 > datetime.len) return null;
                month = std.fmt.parseInt(i64, datetime[di..di+2], 10) catch return null;
                di += 2;
                parsed_month = true;
            },
            'n' => {
                const took = takeDigits(datetime, di, 1, 2) orelse return null;
                month = took.value;
                di = took.next;
                parsed_month = true;
            },
            'd' => {
                if (di + 2 > datetime.len) return null;
                day = std.fmt.parseInt(i64, datetime[di..di+2], 10) catch return null;
                di += 2;
                parsed_day = true;
            },
            'j' => {
                const took = takeDigits(datetime, di, 1, 2) orelse return null;
                day = took.value;
                di = took.next;
                parsed_day = true;
            },
            'H' => {
                if (di + 2 > datetime.len) return null;
                hour = std.fmt.parseInt(i64, datetime[di..di+2], 10) catch return null;
                di += 2;
                parsed_hour = true;
            },
            'G' => {
                const took = takeDigits(datetime, di, 1, 2) orelse return null;
                hour = took.value;
                di = took.next;
                parsed_hour = true;
            },
            'h' => {
                if (di + 2 > datetime.len) return null;
                hour = std.fmt.parseInt(i64, datetime[di..di+2], 10) catch return null;
                di += 2;
                parsed_hour = true;
                hour_is_12 = true;
            },
            'g' => {
                const took = takeDigits(datetime, di, 1, 2) orelse return null;
                hour = took.value;
                di = took.next;
                parsed_hour = true;
                hour_is_12 = true;
            },
            'i' => {
                if (di + 2 > datetime.len) return null;
                min = std.fmt.parseInt(i64, datetime[di..di+2], 10) catch return null;
                di += 2;
                parsed_min = true;
            },
            's' => {
                if (di + 2 > datetime.len) return null;
                sec = std.fmt.parseInt(i64, datetime[di..di+2], 10) catch return null;
                di += 2;
                parsed_sec = true;
            },
            'U' => {
                const start = di;
                if (di < datetime.len and datetime[di] == '-') di += 1;
                while (di < datetime.len and datetime[di] >= '0' and datetime[di] <= '9') : (di += 1) {}
                if (di == start or (di == start + 1 and datetime[start] == '-')) return null;
                u_ts = std.fmt.parseInt(i64, datetime[start..di], 10) catch return null;
            },
            'u' => {
                const start = di;
                while (di < datetime.len and di - start < 6 and datetime[di] >= '0' and datetime[di] <= '9') : (di += 1) {}
                if (di == start) return null;
                var parsed_u = std.fmt.parseInt(i64, datetime[start..di], 10) catch 0;
                // pad to 6-digit microsecond resolution (PHP's u is microseconds)
                var pad = 6 - (di - start);
                while (pad > 0) : (pad -= 1) parsed_u *= 10;
                microseconds = parsed_u;
            },
            'v' => {
                const start = di;
                while (di < datetime.len and di - start < 3 and datetime[di] >= '0' and datetime[di] <= '9') : (di += 1) {}
                if (di == start) return null;
                var parsed_v = std.fmt.parseInt(i64, datetime[start..di], 10) catch 0;
                // v is milliseconds; scale to microseconds
                var pad = 3 - (di - start);
                while (pad > 0) : (pad -= 1) parsed_v *= 10;
                microseconds = parsed_v * 1000;
            },
            'a', 'A' => {
                if (di + 2 > datetime.len) return null;
                const seg = datetime[di..di+2];
                if (eqlLower(seg, "am")) is_pm = false
                else if (eqlLower(seg, "pm")) is_pm = true
                else return null;
                di += 2;
            },
            'M' => {
                const m = parseShortMonth(datetime[di..]) orelse return null;
                month = m;
                di += 3;
                parsed_month = true;
            },
            'F' => {
                const len = monthNameLen(datetime[di..]);
                if (len == 0) return null;
                month = parseMonthName(datetime[di..]) orelse return null;
                di += len;
                parsed_month = true;
            },
            'D' => {
                if (di + 3 > datetime.len) return null;
                di += 3;
            },
            'l' => {
                const len = weekdayNameLen(datetime[di..]) orelse return null;
                di += len;
            },
            'e', 'T' => {
                // timezone name: consume identifier-ish chars
                const start = di;
                while (di < datetime.len and (isAlpha(datetime[di]) or datetime[di] == '/' or datetime[di] == '_' or datetime[di] == '+' or datetime[di] == '-' or (datetime[di] >= '0' and datetime[di] <= '9'))) : (di += 1) {}
                if (di == start) return null;
            },
            'O', 'P' => {
                // +0200 or +02:00
                if (di >= datetime.len) return null;
                const sign: i64 = if (datetime[di] == '+') 1 else if (datetime[di] == '-') -1 else return null;
                di += 1;
                if (di + 2 > datetime.len) return null;
                const hh = std.fmt.parseInt(i64, datetime[di..di+2], 10) catch return null;
                di += 2;
                var mm: i64 = 0;
                if (di < datetime.len and datetime[di] == ':') di += 1;
                if (di + 2 <= datetime.len and datetime[di] >= '0' and datetime[di] <= '9' and datetime[di+1] >= '0' and datetime[di+1] <= '9') {
                    mm = std.fmt.parseInt(i64, datetime[di..di+2], 10) catch 0;
                    di += 2;
                }
                tz_offset = sign * (hh * 3600 + mm * 60);
                tz_parsed = true;
            },
            'Z' => {
                const start = di;
                if (di < datetime.len and (datetime[di] == '+' or datetime[di] == '-')) di += 1;
                while (di < datetime.len and datetime[di] >= '0' and datetime[di] <= '9') : (di += 1) {}
                if (di == start or (di == start + 1 and !isDigit(datetime[start]))) return null;
                tz_offset = std.fmt.parseInt(i64, datetime[start..di], 10) catch return null;
                tz_parsed = true;
            },
            ' ' => {
                while (di < datetime.len and datetime[di] == ' ') di += 1;
            },
            else => {
                if (di >= datetime.len or datetime[di] != c) return null;
                di += 1;
            },
        }
    }

    const parsed_off: ?i32 = if (tz_parsed) @intCast(tz_offset) else null;

    if (u_ts) |ts| return .{ .ts = ts - tz_offset, .tz_offset_seconds = parsed_off, .microseconds = microseconds };

    if (hour_is_12) {
        if (is_pm) |pm| {
            if (pm and hour < 12) hour += 12
            else if (!pm and hour == 12) hour = 0;
        }
    }

    // PHP zeroes unset time components when ANY time component is parsed.
    // Without this, an "Y-m-d H:i" format would leave seconds at current time.
    const any_time_parsed = parsed_hour or parsed_min or parsed_sec;
    if (any_time_parsed) {
        if (!parsed_hour) hour = 0;
        if (!parsed_min) min = 0;
        if (!parsed_sec) sec = 0;
    }

    return .{ .ts = dateToTimestamp(year, month, day, hour, min, sec) - tz_offset, .tz_offset_seconds = parsed_off, .microseconds = microseconds };
}

fn isDigit(c: u8) bool { return c >= '0' and c <= '9'; }
fn isAlpha(c: u8) bool { return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z'); }

fn takeDigits(s: []const u8, start: usize, min_n: usize, max_n: usize) ?struct { value: i64, next: usize } {
    var i = start;
    while (i < s.len and i - start < max_n and isDigit(s[i])) : (i += 1) {}
    const got = i - start;
    if (got < min_n) return null;
    const v = std.fmt.parseInt(i64, s[start..i], 10) catch return null;
    return .{ .value = v, .next = i };
}

fn parseShortMonth(s: []const u8) ?i64 {
    const months = [_][]const u8{ "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec" };
    if (s.len < 3) return null;
    for (months, 1..) |name, i| {
        if (eqlLower(s[0..3], name)) return @intCast(i);
    }
    return null;
}

fn weekdayNameLen(s: []const u8) ?usize {
    const days = [_][]const u8{ "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday" };
    for (days) |name| {
        if (s.len >= name.len and eqlLower(s[0..name.len], name)) return name.len;
    }
    return null;
}

fn dtiCreateFromTimestamp(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .null;
    const obj = try ctx.createObject("DateTimeImmutable");
    try obj.set(ctx.allocator, "timestamp", .{ .int = Value.toInt(args[0]) });
    return .{ .object = obj };
}

fn dtGetMicrosecond(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    const v = obj.get("__microseconds");
    if (v == .int) return v;
    return .{ .int = 0 };
}

fn dtSetMicrosecond(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len >= 1 and args[0] == .int) {
        try obj.set(ctx.allocator, "__microseconds", .{ .int = args[0].int });
    }
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

fn dtGetOffset(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    const tz_val = obj.get("__timezone");
    const tz_name = if (tz_val == .string) tz_val.string else "UTC";
    const ts = getTimestamp(obj);
    if (lookupTimezone(tz_name)) |tz| {
        return .{ .int = @intCast(tzOffsetAt(tz, ts)) };
    }
    return .{ .int = 0 };
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
        const name = args[0].string;
        // accept fixed-offset forms (+HH, +HH:MM, UTC, GMT) or known zones.
        // PHP normalizes fixed-offset input to '+HH:MM' / '-HH:MM' (e.g.
        // 'GMT+5' -> '+05:00'). zone names + 'UTC' / 'GMT' alone pass through
        var stored: []const u8 = name;
        var is_named_passthrough = false;
        if (std.mem.eql(u8, name, "UTC") or std.mem.eql(u8, name, "GMT")) {
            is_named_passthrough = true;
        }
        if (lookupTimezone(name) != null) is_named_passthrough = true;
        if (!is_named_passthrough) {
            if (parseTimezoneOffset(name)) |off| {
                const sign: u8 = if (off < 0) '-' else '+';
                const abs: u32 = @intCast(if (off < 0) -off else off);
                const hh = abs / 3600;
                const mm = (abs % 3600) / 60;
                const n = try std.fmt.allocPrint(ctx.allocator, "{c}{d:0>2}:{d:0>2}", .{ sign, hh, mm });
                try ctx.strings.append(ctx.allocator, n);
                stored = n;
            } else {
                const msg = try std.fmt.allocPrint(ctx.allocator, "DateTimeZone::__construct(): Unknown or bad timezone ({s})", .{name});
                try ctx.strings.append(ctx.allocator, msg);
                try ctx.vm.setPendingException("DateInvalidTimeZoneException", msg);
                return error.RuntimeError;
            }
        }
        try obj.set(ctx.allocator, "timezone", .{ .string = stored });
    }
    return .null;
}

fn dtzListIdentifiers(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    // full IANA zone list (419 entries) matching PHP 8.4's tzdb snapshot. used
    // for membership checks in user code that whitelists allowed zones; the
    // names themselves are also valid `DateTimeZone` constructor inputs
    const ids = [_][]const u8{
        "Africa/Abidjan",       "Africa/Accra",        "Africa/Addis_Ababa",
        "Africa/Algiers",       "Africa/Asmara",       "Africa/Bamako",
        "Africa/Bangui",        "Africa/Banjul",       "Africa/Bissau",
        "Africa/Blantyre",      "Africa/Brazzaville",  "Africa/Bujumbura",
        "Africa/Cairo",         "Africa/Casablanca",   "Africa/Ceuta",
        "Africa/Conakry",       "Africa/Dakar",        "Africa/Dar_es_Salaam",
        "Africa/Djibouti",      "Africa/Douala",       "Africa/El_Aaiun",
        "Africa/Freetown",      "Africa/Gaborone",     "Africa/Harare",
        "Africa/Johannesburg",  "Africa/Juba",         "Africa/Kampala",
        "Africa/Khartoum",      "Africa/Kigali",       "Africa/Kinshasa",
        "Africa/Lagos",         "Africa/Libreville",   "Africa/Lome",
        "Africa/Luanda",        "Africa/Lubumbashi",   "Africa/Lusaka",
        "Africa/Malabo",        "Africa/Maputo",       "Africa/Maseru",
        "Africa/Mbabane",       "Africa/Mogadishu",    "Africa/Monrovia",
        "Africa/Nairobi",       "Africa/Ndjamena",     "Africa/Niamey",
        "Africa/Nouakchott",    "Africa/Ouagadougou",  "Africa/Porto-Novo",
        "Africa/Sao_Tome",      "Africa/Tripoli",      "Africa/Tunis",
        "Africa/Windhoek",      "America/Adak",        "America/Anchorage",
        "America/Anguilla",     "America/Antigua",     "America/Araguaina",
        "America/Argentina/Buenos_Aires", "America/Argentina/Catamarca",
        "America/Argentina/Cordoba",      "America/Argentina/Jujuy",
        "America/Argentina/La_Rioja",     "America/Argentina/Mendoza",
        "America/Argentina/Rio_Gallegos", "America/Argentina/Salta",
        "America/Argentina/San_Juan",     "America/Argentina/San_Luis",
        "America/Argentina/Tucuman",      "America/Argentina/Ushuaia",
        "America/Aruba",        "America/Asuncion",    "America/Atikokan",
        "America/Bahia",        "America/Bahia_Banderas", "America/Barbados",
        "America/Belem",        "America/Belize",      "America/Blanc-Sablon",
        "America/Boa_Vista",    "America/Bogota",      "America/Boise",
        "America/Cambridge_Bay","America/Campo_Grande","America/Cancun",
        "America/Caracas",      "America/Cayenne",     "America/Cayman",
        "America/Chicago",      "America/Chihuahua",   "America/Ciudad_Juarez",
        "America/Costa_Rica",   "America/Coyhaique",   "America/Creston",
        "America/Cuiaba",       "America/Curacao",     "America/Danmarkshavn",
        "America/Dawson",       "America/Dawson_Creek","America/Denver",
        "America/Detroit",      "America/Dominica",    "America/Edmonton",
        "America/Eirunepe",     "America/El_Salvador", "America/Fort_Nelson",
        "America/Fortaleza",    "America/Glace_Bay",   "America/Goose_Bay",
        "America/Grand_Turk",   "America/Grenada",     "America/Guadeloupe",
        "America/Guatemala",    "America/Guayaquil",   "America/Guyana",
        "America/Halifax",      "America/Havana",      "America/Hermosillo",
        "America/Indiana/Indianapolis", "America/Indiana/Knox",
        "America/Indiana/Marengo",      "America/Indiana/Petersburg",
        "America/Indiana/Tell_City",    "America/Indiana/Vevay",
        "America/Indiana/Vincennes",    "America/Indiana/Winamac",
        "America/Inuvik",       "America/Iqaluit",     "America/Jamaica",
        "America/Juneau",       "America/Kentucky/Louisville",
        "America/Kentucky/Monticello",  "America/Kralendijk",
        "America/La_Paz",       "America/Lima",        "America/Los_Angeles",
        "America/Lower_Princes","America/Maceio",      "America/Managua",
        "America/Manaus",       "America/Marigot",     "America/Martinique",
        "America/Matamoros",    "America/Mazatlan",    "America/Menominee",
        "America/Merida",       "America/Metlakatla",  "America/Mexico_City",
        "America/Miquelon",     "America/Moncton",     "America/Monterrey",
        "America/Montevideo",   "America/Montserrat",  "America/Nassau",
        "America/New_York",     "America/Nome",        "America/Noronha",
        "America/North_Dakota/Beulah",  "America/North_Dakota/Center",
        "America/North_Dakota/New_Salem","America/Nuuk", "America/Ojinaga",
        "America/Panama",       "America/Paramaribo",  "America/Phoenix",
        "America/Port-au-Prince","America/Port_of_Spain","America/Porto_Velho",
        "America/Puerto_Rico",  "America/Punta_Arenas","America/Rankin_Inlet",
        "America/Recife",       "America/Regina",      "America/Resolute",
        "America/Rio_Branco",   "America/Santarem",    "America/Santiago",
        "America/Santo_Domingo","America/Sao_Paulo",   "America/Scoresbysund",
        "America/Sitka",        "America/St_Barthelemy","America/St_Johns",
        "America/St_Kitts",     "America/St_Lucia",    "America/St_Thomas",
        "America/St_Vincent",   "America/Swift_Current","America/Tegucigalpa",
        "America/Thule",        "America/Tijuana",     "America/Toronto",
        "America/Tortola",      "America/Vancouver",   "America/Whitehorse",
        "America/Winnipeg",     "America/Yakutat",     "Antarctica/Casey",
        "Antarctica/Davis",     "Antarctica/DumontDUrville", "Antarctica/Macquarie",
        "Antarctica/Mawson",    "Antarctica/McMurdo",  "Antarctica/Palmer",
        "Antarctica/Rothera",   "Antarctica/Syowa",    "Antarctica/Troll",
        "Antarctica/Vostok",    "Arctic/Longyearbyen", "Asia/Aden",
        "Asia/Almaty",          "Asia/Amman",          "Asia/Anadyr",
        "Asia/Aqtau",           "Asia/Aqtobe",         "Asia/Ashgabat",
        "Asia/Atyrau",          "Asia/Baghdad",        "Asia/Bahrain",
        "Asia/Baku",            "Asia/Bangkok",        "Asia/Barnaul",
        "Asia/Beirut",          "Asia/Bishkek",        "Asia/Brunei",
        "Asia/Chita",           "Asia/Colombo",        "Asia/Damascus",
        "Asia/Dhaka",           "Asia/Dili",           "Asia/Dubai",
        "Asia/Dushanbe",        "Asia/Famagusta",      "Asia/Gaza",
        "Asia/Hebron",          "Asia/Ho_Chi_Minh",    "Asia/Hong_Kong",
        "Asia/Hovd",            "Asia/Irkutsk",        "Asia/Jakarta",
        "Asia/Jayapura",        "Asia/Jerusalem",      "Asia/Kabul",
        "Asia/Kamchatka",       "Asia/Karachi",        "Asia/Kathmandu",
        "Asia/Khandyga",        "Asia/Kolkata",        "Asia/Krasnoyarsk",
        "Asia/Kuala_Lumpur",    "Asia/Kuching",        "Asia/Kuwait",
        "Asia/Macau",           "Asia/Magadan",        "Asia/Makassar",
        "Asia/Manila",          "Asia/Muscat",         "Asia/Nicosia",
        "Asia/Novokuznetsk",    "Asia/Novosibirsk",    "Asia/Omsk",
        "Asia/Oral",            "Asia/Phnom_Penh",     "Asia/Pontianak",
        "Asia/Pyongyang",       "Asia/Qatar",          "Asia/Qostanay",
        "Asia/Qyzylorda",       "Asia/Riyadh",         "Asia/Sakhalin",
        "Asia/Samarkand",       "Asia/Seoul",          "Asia/Shanghai",
        "Asia/Singapore",       "Asia/Srednekolymsk",  "Asia/Taipei",
        "Asia/Tashkent",        "Asia/Tbilisi",        "Asia/Tehran",
        "Asia/Thimphu",         "Asia/Tokyo",          "Asia/Tomsk",
        "Asia/Ulaanbaatar",     "Asia/Urumqi",         "Asia/Ust-Nera",
        "Asia/Vientiane",       "Asia/Vladivostok",    "Asia/Yakutsk",
        "Asia/Yangon",          "Asia/Yekaterinburg",  "Asia/Yerevan",
        "Atlantic/Azores",      "Atlantic/Bermuda",    "Atlantic/Canary",
        "Atlantic/Cape_Verde",  "Atlantic/Faroe",      "Atlantic/Madeira",
        "Atlantic/Reykjavik",   "Atlantic/South_Georgia","Atlantic/St_Helena",
        "Atlantic/Stanley",     "Australia/Adelaide",  "Australia/Brisbane",
        "Australia/Broken_Hill","Australia/Darwin",    "Australia/Eucla",
        "Australia/Hobart",     "Australia/Lindeman",  "Australia/Lord_Howe",
        "Australia/Melbourne",  "Australia/Perth",     "Australia/Sydney",
        "Europe/Amsterdam",     "Europe/Andorra",      "Europe/Astrakhan",
        "Europe/Athens",        "Europe/Belgrade",     "Europe/Berlin",
        "Europe/Bratislava",    "Europe/Brussels",     "Europe/Bucharest",
        "Europe/Budapest",      "Europe/Busingen",     "Europe/Chisinau",
        "Europe/Copenhagen",    "Europe/Dublin",       "Europe/Gibraltar",
        "Europe/Guernsey",      "Europe/Helsinki",     "Europe/Isle_of_Man",
        "Europe/Istanbul",      "Europe/Jersey",       "Europe/Kaliningrad",
        "Europe/Kirov",         "Europe/Kyiv",         "Europe/Lisbon",
        "Europe/Ljubljana",     "Europe/London",       "Europe/Luxembourg",
        "Europe/Madrid",        "Europe/Malta",        "Europe/Mariehamn",
        "Europe/Minsk",         "Europe/Monaco",       "Europe/Moscow",
        "Europe/Oslo",          "Europe/Paris",        "Europe/Podgorica",
        "Europe/Prague",        "Europe/Riga",         "Europe/Rome",
        "Europe/Samara",        "Europe/San_Marino",   "Europe/Sarajevo",
        "Europe/Saratov",       "Europe/Simferopol",   "Europe/Skopje",
        "Europe/Sofia",         "Europe/Stockholm",    "Europe/Tallinn",
        "Europe/Tirane",        "Europe/Ulyanovsk",    "Europe/Vaduz",
        "Europe/Vatican",       "Europe/Vienna",       "Europe/Vilnius",
        "Europe/Volgograd",     "Europe/Warsaw",       "Europe/Zagreb",
        "Europe/Zurich",        "Indian/Antananarivo", "Indian/Chagos",
        "Indian/Christmas",     "Indian/Cocos",        "Indian/Comoro",
        "Indian/Kerguelen",     "Indian/Mahe",         "Indian/Maldives",
        "Indian/Mauritius",     "Indian/Mayotte",      "Indian/Reunion",
        "Pacific/Apia",         "Pacific/Auckland",    "Pacific/Bougainville",
        "Pacific/Chatham",      "Pacific/Chuuk",       "Pacific/Easter",
        "Pacific/Efate",        "Pacific/Fakaofo",     "Pacific/Fiji",
        "Pacific/Funafuti",     "Pacific/Galapagos",   "Pacific/Gambier",
        "Pacific/Guadalcanal",  "Pacific/Guam",        "Pacific/Honolulu",
        "Pacific/Kanton",       "Pacific/Kiritimati",  "Pacific/Kosrae",
        "Pacific/Kwajalein",    "Pacific/Majuro",      "Pacific/Marquesas",
        "Pacific/Midway",       "Pacific/Nauru",       "Pacific/Niue",
        "Pacific/Norfolk",      "Pacific/Noumea",      "Pacific/Pago_Pago",
        "Pacific/Palau",        "Pacific/Pitcairn",    "Pacific/Pohnpei",
        "Pacific/Port_Moresby", "Pacific/Rarotonga",   "Pacific/Saipan",
        "Pacific/Tahiti",       "Pacific/Tarawa",      "Pacific/Tongatapu",
        "Pacific/Wake",         "Pacific/Wallis",      "UTC",
    };
    var arr = try ctx.createArray();
    for (ids) |id| try arr.append(ctx.allocator, .{ .string = id });
    return .{ .array = arr };
}

fn dtzListAbbreviations(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const arr = try ctx.createArray();
    // PHP keys are lowercase abbreviation strings; each value is a list of
    // {dst, offset, timezone_id} entries. iterate our tz_table and emit one
    // entry per (zone, dst-side) where the abbreviation is non-empty.
    for (tz_table) |z| {
        // build the canonical PHP timezone id (e.g. "America/New_York" from
        // the lowercased table name). reusing the tz_table entry's name as
        // lowercase is fine — PHP accepts case-insensitive zone names
        var key_buf: [16]u8 = undefined;
        // emit std side
        if (z.std_abbrev.len > 0 and z.std_abbrev.len < key_buf.len) {
            for (z.std_abbrev, 0..) |c, i| key_buf[i] = std.ascii.toLower(c);
            const key = try ctx.allocator.dupe(u8, key_buf[0..z.std_abbrev.len]);
            try ctx.vm.strings.append(ctx.allocator, key);
            const canonical = try canonicalizeZoneName(ctx, z.name);
            try appendAbbrevEntry(ctx, arr, key, false, z.std_offset, canonical);
        }
        // emit dst side only when distinct
        if (z.dst_rule != .none and z.dst_abbrev.len > 0 and !std.mem.eql(u8, z.std_abbrev, z.dst_abbrev) and z.dst_abbrev.len < key_buf.len) {
            for (z.dst_abbrev, 0..) |c, i| key_buf[i] = std.ascii.toLower(c);
            const key = try ctx.allocator.dupe(u8, key_buf[0..z.dst_abbrev.len]);
            try ctx.vm.strings.append(ctx.allocator, key);
            const canonical = try canonicalizeZoneName(ctx, z.name);
            try appendAbbrevEntry(ctx, arr, key, true, z.dst_offset, canonical);
        }
    }
    return .{ .array = arr };
}

fn canonicalizeZoneName(ctx: *NativeContext, lower_name: []const u8) ![]const u8 {
    // turn "america/new_york" into "America/New_York"
    const out = try ctx.allocator.dupe(u8, lower_name);
    var capitalize_next = true;
    for (out, 0..) |c, i| {
        if (c == '/' or c == '_') {
            capitalize_next = true;
        } else if (capitalize_next) {
            out[i] = std.ascii.toUpper(c);
            capitalize_next = false;
        }
    }
    try ctx.vm.strings.append(ctx.allocator, out);
    return out;
}

fn appendAbbrevEntry(ctx: *NativeContext, outer: *@import("../runtime/value.zig").PhpArray, key: []const u8, dst: bool, offset: i32, tz_id: []const u8) !void {
    const PA = @import("../runtime/value.zig").PhpArray;
    var list: *PA = undefined;
    const existing = outer.get(.{ .string = key });
    if (existing == .array) {
        list = existing.array;
    } else {
        list = try ctx.createArray();
        try outer.set(ctx.allocator, .{ .string = key }, .{ .array = list });
    }
    const entry = try ctx.createArray();
    try entry.set(ctx.allocator, .{ .string = "dst" }, .{ .bool = dst });
    try entry.set(ctx.allocator, .{ .string = "offset" }, .{ .int = @as(i64, offset) });
    try entry.set(ctx.allocator, .{ .string = "timezone_id" }, .{ .string = tz_id });
    try list.append(ctx.allocator, .{ .array = entry });
}

fn dtzGetName(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .string = "UTC" };
    const tz_val = obj.get("timezone");
    return if (tz_val == .string) tz_val else .{ .string = "UTC" };
}

fn dtzGetOffset(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    const tz_val = obj.get("timezone");
    const tz_name = if (tz_val == .string) tz_val.string else "UTC";

    // getOffset takes a DateTime argument for DST calculation
    var ref_ts: i64 = std.time.timestamp();
    if (args.len >= 1 and args[0] == .object) {
        ref_ts = getTimestamp(args[0].object);
    }

    if (lookupTimezone(tz_name)) |tz| {
        return .{ .int = @intCast(tzOffsetAt(tz, ref_ts)) };
    }
    return .{ .int = 0 };
}

// PHP's getLocation returns {country_code, latitude, longitude, comments}
// for named tz, and false for offset-only zones. zphp doesn't ship the IANA
// tzdata, so named zones return placeholder data with the right structure
fn dtzGetLocation(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const tz_val = obj.get("timezone");
    const tz_name = if (tz_val == .string) tz_val.string else "UTC";
    // offset-only zones report false
    if (tz_name.len > 0 and (tz_name[0] == '+' or tz_name[0] == '-')) return .{ .bool = false };
    const arr = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .string = "country_code" }, .{ .string = "??" });
    try arr.set(ctx.allocator, .{ .string = "latitude" }, .{ .float = 0.0 });
    try arr.set(ctx.allocator, .{ .string = "longitude" }, .{ .float = 0.0 });
    try arr.set(ctx.allocator, .{ .string = "comments" }, .{ .string = "" });
    return .{ .array = arr };
}

// stub that returns an empty list - we don't track historical transitions
fn dtzGetTransitions(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .array = try ctx.createArray() };
}

// standalone PHP functions: date(), mktime(), strtotime(), time(), microtime()

fn appendOffsetColon(buf: *std.ArrayListUnmanaged(u8), a: Allocator, offset: i32) !void {
    const abs: u32 = if (offset < 0) @intCast(-offset) else @intCast(offset);
    const h = abs / 3600;
    const m = (abs % 3600) / 60;
    var tmp: [8]u8 = undefined;
    const s = std.fmt.bufPrint(&tmp, "{c}{d:0>2}:{d:0>2}", .{
        @as(u8, if (offset < 0) '-' else '+'),
        h,
        m,
    }) catch "+00:00";
    try buf.appendSlice(a, s);
}

fn appendOffsetCompact(buf: *std.ArrayListUnmanaged(u8), a: Allocator, offset: i32) !void {
    const abs: u32 = if (offset < 0) @intCast(-offset) else @intCast(offset);
    const h = abs / 3600;
    const m = (abs % 3600) / 60;
    var tmp: [8]u8 = undefined;
    const s = std.fmt.bufPrint(&tmp, "{c}{d:0>2}{d:0>2}", .{
        @as(u8, if (offset < 0) '-' else '+'),
        h,
        m,
    }) catch "+0000";
    try buf.appendSlice(a, s);
}

fn native_date(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .string = "" };
    const format = args[0].string;
    const timestamp: i64 = if (args.len >= 2) Value.toInt(args[1]) else std.time.timestamp();
    return formatTimestamp(ctx, timestamp, format);
}

fn native_mktime(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const hour: i64 = if (args.len > 0) Value.toInt(args[0]) else 0;
    const min: i64 = if (args.len > 1) Value.toInt(args[1]) else 0;
    const sec: i64 = if (args.len > 2) Value.toInt(args[2]) else 0;
    const month: i64 = if (args.len > 3) Value.toInt(args[3]) else 1;
    const day: i64 = if (args.len > 4) Value.toInt(args[4]) else 1;
    const year: i64 = if (args.len > 5) Value.toInt(args[5]) else 1970;
    var ts = dateToTimestamp(year, month, day, hour, min, sec);
    if (lookupTimezone(ctx.vm.default_tz_name)) |tz| {
        ts -= @as(i64, tzOffsetForWall(tz, ts));
    }
    return .{ .int = ts };
}

fn native_gmmktime(_: *NativeContext, args: []const Value) RuntimeError!Value {
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

    // ISO 8601 week date: YYYY-Www-D (e.g. 2024-W10-1) or YYYY-Www (Monday)
    if (input.len >= 8 and input[4] == '-' and (input[5] == 'W' or input[5] == 'w')
        and input[6] >= '0' and input[6] <= '9' and input[7] >= '0' and input[7] <= '9')
    {
        const year = std.fmt.parseInt(i64, input[0..4], 10) catch return Value{ .bool = false };
        const week = std.fmt.parseInt(i64, input[6..8], 10) catch return Value{ .bool = false };
        var dow: i64 = 1;
        if (input.len >= 10 and input[8] == '-' and input[9] >= '1' and input[9] <= '7') {
            dow = input[9] - '0';
        }
        return .{ .int = isoWeekDateToTimestamp(year, week, dow, 0, 0, 0) };
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
        var consumed: usize = 10;
        if (input.len > 10 and (input[10] == ' ' or input[10] == 'T')) {
            var time_start: usize = 11;
            while (time_start < input.len and input[time_start] == ' ') time_start += 1;
            const tail = input[time_start..];
            if (parseTimeOfDay(tail)) |tod| {
                hour = tod.hour;
                min = tod.min;
                sec = tod.sec;
                // advance consumed past the parsed HH:MM[:SS]
                var i: usize = 0;
                while (i < tail.len and tail[i] >= '0' and tail[i] <= '9') i += 1;
                if (i < tail.len and tail[i] == ':') {
                    i += 1;
                    while (i < tail.len and tail[i] >= '0' and tail[i] <= '9') i += 1;
                    if (i < tail.len and tail[i] == ':') {
                        i += 1;
                        while (i < tail.len and tail[i] >= '0' and tail[i] <= '9') i += 1;
                    }
                }
                consumed = time_start + i;
                var rest = input[consumed..];
                while (rest.len > 0 and rest[0] == ' ') { rest = rest[1..]; consumed += 1; }
                if (rest.len > 0) {
                    if (parseTimezoneOffset(rest)) |off| {
                        tz_offset = off;
                        consumed = input.len;
                    }
                }
            }
        }
        var base_ts = dateToTimestamp(year, month, day, hour, min, sec) - tz_offset;
        var trailing = input[consumed..];
        while (trailing.len > 0 and trailing[0] == ' ') trailing = trailing[1..];
        if (trailing.len > 0) {
            const rel = parseRelativeTime(trailing, base_ts);
            if (rel == .int) base_ts = rel.int;
        }
        return .{ .int = base_ts };
    }

    // YYYY/MM/DD slash date (PHP accepts this alongside YYYY-MM-DD)
    if (input.len >= 10 and input[4] == '/' and input[7] == '/') {
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

    // bare time-of-day ("14:30", "2:30pm", "09:15:00") - PHP keeps base's
    // calendar date and replaces the time
    if (tryParseBareTime(input)) |tod| {
        const dc = baseComponents(base);
        return .{ .int = dateToTimestamp(dc.year, dc.month, dc.day, tod.hour, tod.min, tod.sec) };
    }

    return parseRelativeTime(input, base);
}

// returns a TimeOfDay only when the whole input is a standalone time, i.e.
// starts with HH:MM and has nothing left over besides am/pm and whitespace
fn tryParseBareTime(input: []const u8) ?TimeOfDay {
    var s = input;
    while (s.len > 0 and s[0] == ' ') s = s[1..];
    while (s.len > 0 and s[s.len - 1] == ' ') s = s[0 .. s.len - 1];
    // must begin with 1-2 digits then a colon
    var i: usize = 0;
    while (i < s.len and s[i] >= '0' and s[i] <= '9') i += 1;
    if (i == 0 or i > 2 or i >= s.len or s[i] != ':') return null;
    // walk minutes (and optional seconds)
    i += 1;
    var d: usize = 0;
    while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) d += 1;
    if (d == 0) return null;
    if (i < s.len and s[i] == ':') {
        i += 1;
        d = 0;
        while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) d += 1;
        if (d == 0) return null;
    }
    // only whitespace + an optional am/pm marker may follow
    var rest = s[i..];
    while (rest.len > 0 and rest[0] == ' ') rest = rest[1..];
    if (rest.len != 0) {
        if (!(rest.len == 2 and (eqlLower(rest, "am") or eqlLower(rest, "pm")))) return null;
    }
    return parseTimeOfDay(s);
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
        // DD Month YYYY [HH:MM[:SS]]
        while (s.len > 0 and (s[0] == ' ' or s[0] == ',')) s = s[1..];
        var yend: usize = 0;
        while (yend < s.len and s[yend] >= '0' and s[yend] <= '9') yend += 1;
        if (yend == 0) return null;
        const year = std.fmt.parseInt(i64, s[0..yend], 10) catch return null;
        s = s[yend..];
        const tod = parseTrailingTime(s);
        return dateToTimestamp(year, month_num.?, dd, tod.hour, tod.min, tod.sec);
    }

    // Month DD[,] YYYY [HH:MM[:SS]]
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
    s = s[yend..];
    const tod = parseTrailingTime(s);
    return dateToTimestamp(year, month_num.?, day, tod.hour, tod.min, tod.sec);
}

fn parseTrailingTime(rest: []const u8) TimeOfDay {
    var s = rest;
    while (s.len > 0 and (s[0] == ' ' or s[0] == 'T' or s[0] == ',')) s = s[1..];
    if (s.len == 0) return .{ .hour = 0, .min = 0, .sec = 0 };
    return parseTimeOfDay(s) orelse TimeOfDay{ .hour = 0, .min = 0, .sec = 0 };
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

fn native_cal_days_in_month(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    // cal_days_in_month($calendar, $month, $year). only CAL_GREGORIAN (0) is
    // commonly used; zphp treats every calendar id as Gregorian
    if (args.len < 3) return .{ .bool = false };
    const month = Value.toInt(args[1]);
    const year = Value.toInt(args[2]);
    if (month < 1 or month > 12) {
        try ctx.vm.setPendingException("ValueError", "Invalid date");
        return error.RuntimeError;
    }
    return .{ .int = daysInMonth(month, year) };
}

fn buildDateParseResult(ctx: *NativeContext, year: ?i64, month: ?i64, day: ?i64, hour: ?i64, minute: ?i64, second: ?i64, fraction: f64, errors: []const []const u8) !Value {
    const PhpArray = @import("../runtime/value.zig").PhpArray;
    var arr = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .string = "year" }, if (year) |y| .{ .int = y } else .{ .bool = false });
    try arr.set(ctx.allocator, .{ .string = "month" }, if (month) |m| .{ .int = m } else .{ .bool = false });
    try arr.set(ctx.allocator, .{ .string = "day" }, if (day) |d| .{ .int = d } else .{ .bool = false });
    try arr.set(ctx.allocator, .{ .string = "hour" }, if (hour) |h| .{ .int = h } else .{ .bool = false });
    try arr.set(ctx.allocator, .{ .string = "minute" }, if (minute) |m| .{ .int = m } else .{ .bool = false });
    try arr.set(ctx.allocator, .{ .string = "second" }, if (second) |s| .{ .int = s } else .{ .bool = false });
    try arr.set(ctx.allocator, .{ .string = "fraction" }, .{ .float = fraction });
    try arr.set(ctx.allocator, .{ .string = "warning_count" }, .{ .int = 0 });
    const warns = try ctx.allocator.create(PhpArray);
    warns.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, warns);
    try arr.set(ctx.allocator, .{ .string = "warnings" }, .{ .array = warns });
    try arr.set(ctx.allocator, .{ .string = "error_count" }, .{ .int = @intCast(errors.len) });
    const errs = try ctx.allocator.create(PhpArray);
    errs.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, errs);
    for (errors, 0..) |e, i| try errs.set(ctx.allocator, .{ .int = @intCast(i) }, .{ .string = e });
    try arr.set(ctx.allocator, .{ .string = "errors" }, .{ .array = errs });
    try arr.set(ctx.allocator, .{ .string = "is_localtime" }, .{ .bool = false });
    return .{ .array = arr };
}

fn native_date_parse(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const s = args[0].string;
    var year: ?i64 = null;
    var month: ?i64 = null;
    var day: ?i64 = null;
    var hour: ?i64 = null;
    var minute: ?i64 = null;
    var second: ?i64 = null;
    if (s.len >= 10 and s[4] == '-' and s[7] == '-') {
        year = std.fmt.parseInt(i64, s[0..4], 10) catch null;
        month = std.fmt.parseInt(i64, s[5..7], 10) catch null;
        day = std.fmt.parseInt(i64, s[8..10], 10) catch null;
        if (s.len >= 16 and (s[10] == ' ' or s[10] == 'T') and s[13] == ':') {
            hour = std.fmt.parseInt(i64, s[11..13], 10) catch null;
            minute = std.fmt.parseInt(i64, s[14..16], 10) catch null;
            if (s.len >= 19 and s[16] == ':') {
                second = std.fmt.parseInt(i64, s[17..19], 10) catch null;
            } else {
                second = 0;
            }
        }
    }
    return buildDateParseResult(ctx, year, month, day, hour, minute, second, 0.0, &.{});
}

fn native_date_parse_from_format(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const format = args[0].string;
    const datetime = args[1].string;

    var year: ?i64 = null;
    var month: ?i64 = null;
    var day: ?i64 = null;
    var hour: ?i64 = null;
    var minute: ?i64 = null;
    var second: ?i64 = null;
    var fraction: ?f64 = null;
    var is_pm: ?bool = null;
    var hour_is_12: bool = false;

    var errors_buf: [16][]const u8 = undefined;
    var n_errors: usize = 0;

    var fi: usize = 0;
    var di: usize = 0;
    while (fi < format.len) : (fi += 1) {
        const c = format[fi];
        switch (c) {
            'Y' => {
                if (di + 4 <= datetime.len) {
                    if (std.fmt.parseInt(i64, datetime[di..di+4], 10)) |v| { year = v; di += 4; }
                    else |_| { if (n_errors < errors_buf.len) { errors_buf[n_errors] = "A four digit year could not be found"; n_errors += 1; } }
                } else if (n_errors < errors_buf.len) { errors_buf[n_errors] = "A four digit year could not be found"; n_errors += 1; }
            },
            'y' => {
                if (di + 2 <= datetime.len) {
                    if (std.fmt.parseInt(i64, datetime[di..di+2], 10)) |yy| { year = if (yy < 70) 2000 + yy else 1900 + yy; di += 2; }
                    else |_| {}
                }
            },
            'm' => {
                if (di + 2 <= datetime.len) {
                    if (std.fmt.parseInt(i64, datetime[di..di+2], 10)) |v| { month = v; di += 2; } else |_| {}
                }
            },
            'n' => {
                if (takeDigits(datetime, di, 1, 2)) |t| { month = t.value; di = t.next; }
            },
            'd' => {
                if (di + 2 <= datetime.len) {
                    if (std.fmt.parseInt(i64, datetime[di..di+2], 10)) |v| { day = v; di += 2; } else |_| {}
                }
            },
            'j' => {
                if (takeDigits(datetime, di, 1, 2)) |t| { day = t.value; di = t.next; }
            },
            'H' => {
                if (di + 2 <= datetime.len) {
                    if (std.fmt.parseInt(i64, datetime[di..di+2], 10)) |v| { hour = v; di += 2; } else |_| {}
                }
            },
            'G' => {
                if (takeDigits(datetime, di, 1, 2)) |t| { hour = t.value; di = t.next; }
            },
            'h' => {
                if (di + 2 <= datetime.len) {
                    if (std.fmt.parseInt(i64, datetime[di..di+2], 10)) |v| { hour = v; di += 2; hour_is_12 = true; } else |_| {}
                }
            },
            'g' => {
                if (takeDigits(datetime, di, 1, 2)) |t| { hour = t.value; di = t.next; hour_is_12 = true; }
            },
            'i' => {
                if (di + 2 <= datetime.len) {
                    if (std.fmt.parseInt(i64, datetime[di..di+2], 10)) |v| { minute = v; di += 2; } else |_| {}
                }
            },
            's' => {
                if (di + 2 <= datetime.len) {
                    if (std.fmt.parseInt(i64, datetime[di..di+2], 10)) |v| { second = v; di += 2; } else |_| {}
                }
            },
            'u' => {
                // microseconds, variable digits
                var end = di;
                while (end < datetime.len and datetime[end] >= '0' and datetime[end] <= '9') end += 1;
                if (end > di) {
                    const us = std.fmt.parseInt(i64, datetime[di..end], 10) catch 0;
                    const digits = end - di;
                    var divisor: f64 = 1;
                    var dd: usize = 0;
                    while (dd < digits) : (dd += 1) divisor *= 10;
                    fraction = @as(f64, @floatFromInt(us)) / divisor;
                    di = end;
                }
            },
            'v' => {
                // milliseconds 3 digits
                if (di + 3 <= datetime.len) {
                    if (std.fmt.parseInt(i64, datetime[di..di+3], 10)) |ms| {
                        fraction = @as(f64, @floatFromInt(ms)) / 1000.0;
                        di += 3;
                    } else |_| {}
                }
            },
            'a', 'A' => {
                if (di + 2 <= datetime.len) {
                    const tok = datetime[di..di+2];
                    if (std.ascii.eqlIgnoreCase(tok, "am")) { is_pm = false; di += 2; }
                    else if (std.ascii.eqlIgnoreCase(tok, "pm")) { is_pm = true; di += 2; }
                }
            },
            'D', 'l' => {
                // skip alphabetic day name
                while (di < datetime.len and std.ascii.isAlphabetic(datetime[di])) di += 1;
            },
            'M', 'F' => {
                // month name - look up
                var end = di;
                while (end < datetime.len and std.ascii.isAlphabetic(datetime[end])) end += 1;
                if (end > di) {
                    const name = datetime[di..end];
                    const months = [_][]const u8{ "january","february","march","april","may","june","july","august","september","october","november","december" };
                    for (months, 0..) |mn, idx| {
                        if (std.ascii.startsWithIgnoreCase(mn, name) and (name.len == mn.len or name.len == 3)) {
                            month = @intCast(idx + 1);
                            break;
                        }
                    }
                    di = end;
                }
            },
            ' ', '\t' => {
                while (di < datetime.len and (datetime[di] == ' ' or datetime[di] == '\t')) di += 1;
            },
            '\\' => {
                fi += 1;
                if (fi < format.len and di < datetime.len and datetime[di] == format[fi]) di += 1;
            },
            '!' => {
                if (year == null) year = 1970;
                if (month == null) month = 1;
                if (day == null) day = 1;
                if (hour == null) hour = 0;
                if (minute == null) minute = 0;
                if (second == null) second = 0;
                if (fraction == null) fraction = 0;
            },
            '|' => {
                if (year == null) year = 1970;
                if (month == null) month = 1;
                if (day == null) day = 1;
                if (hour == null) hour = 0;
                if (minute == null) minute = 0;
                if (second == null) second = 0;
            },
            else => {
                // literal char: PHP advances input if it matches; mismatches
                // are silent (no errors row) for ordinary punctuation
                if (di < datetime.len and datetime[di] == c) di += 1;
            },
        }
    }

    if (hour_is_12) {
        if (is_pm) |pm| {
            if (pm and (hour orelse 0) < 12) hour = (hour orelse 0) + 12
            else if (!pm and (hour orelse 0) == 12) hour = 0;
        }
    }

    // PHP: if any time component was parsed, the other time components default
    // to 0 (rather than remaining unset). hour-implies-min-sec-fraction-min,
    // etc. all of h/m/s/fraction become 0 when ANY time field is touched
    const any_time = hour != null or minute != null or second != null or fraction != null;
    if (any_time) {
        if (hour == null) hour = 0;
        if (minute == null) minute = 0;
        if (second == null) second = 0;
        if (fraction == null) fraction = 0;
    }

    return buildDateParseResultOpt(ctx, year, month, day, hour, minute, second, fraction, errors_buf[0..n_errors]);
}

fn buildDateParseResultOpt(ctx: *NativeContext, year: ?i64, month: ?i64, day: ?i64, hour: ?i64, minute: ?i64, second: ?i64, fraction: ?f64, errors: []const []const u8) !Value {
    const PhpArray = @import("../runtime/value.zig").PhpArray;
    var arr = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .string = "year" }, if (year) |y| .{ .int = y } else .{ .bool = false });
    try arr.set(ctx.allocator, .{ .string = "month" }, if (month) |m| .{ .int = m } else .{ .bool = false });
    try arr.set(ctx.allocator, .{ .string = "day" }, if (day) |d| .{ .int = d } else .{ .bool = false });
    try arr.set(ctx.allocator, .{ .string = "hour" }, if (hour) |h| .{ .int = h } else .{ .bool = false });
    try arr.set(ctx.allocator, .{ .string = "minute" }, if (minute) |m| .{ .int = m } else .{ .bool = false });
    try arr.set(ctx.allocator, .{ .string = "second" }, if (second) |s| .{ .int = s } else .{ .bool = false });
    try arr.set(ctx.allocator, .{ .string = "fraction" }, if (fraction) |f| .{ .float = f } else .{ .bool = false });
    try arr.set(ctx.allocator, .{ .string = "warning_count" }, .{ .int = 0 });
    const warns = try ctx.allocator.create(PhpArray);
    warns.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, warns);
    try arr.set(ctx.allocator, .{ .string = "warnings" }, .{ .array = warns });
    try arr.set(ctx.allocator, .{ .string = "error_count" }, .{ .int = @intCast(errors.len) });
    const errs = try ctx.allocator.create(PhpArray);
    errs.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, errs);
    for (errors, 0..) |e, i| try errs.set(ctx.allocator, .{ .int = @intCast(i) }, .{ .string = e });
    try arr.set(ctx.allocator, .{ .string = "errors" }, .{ .array = errs });
    try arr.set(ctx.allocator, .{ .string = "is_localtime" }, .{ .bool = false });
    return .{ .array = arr };
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

fn native_hrtime(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const as_int = args.len >= 1 and args[0].isTruthy();
    const ns = std.time.nanoTimestamp();
    if (as_int) {
        return .{ .int = @intCast(ns) };
    }
    const secs: i64 = @intCast(@divTrunc(ns, 1_000_000_000));
    const remainder: i64 = @intCast(@mod(ns, 1_000_000_000));
    var arr = try ctx.createArray();
    try arr.append(ctx.allocator, .{ .int = secs });
    try arr.append(ctx.allocator, .{ .int = remainder });
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

    // RFC 2822 / 7231 - "Mon, 15 Jan 2024 10:30:00 GMT"
    if (tryParseRfc2822(s)) |ts| return .{ .int = ts };

    // textual month dates
    if (tryParseTextualDate(s)) |ts| return .{ .int = ts };

    // "today", "yesterday", "tomorrow", "midnight", "noon"
    if (tryParseKeyword(s, base)) |ts| return .{ .int = ts };

    // ordinal weekday: "first Monday of March 2025", "second Tuesday of next month", "last Friday of December"
    if (tryParseOrdinalWeekday(s, base)) |ts| return .{ .int = ts };

    // "first day of ..." / "last day of ..."
    if (tryParseFirstLastDay(s, base)) |ts| return .{ .int = ts };

    // "next/last <weekday>" or "next/last month/year"
    if (tryParseNextLast(s, base)) |ts| return .{ .int = ts };

    // "<weekday> this|next|last week" - the named weekday within the ISO
    // week (Monday-anchored) of base, optionally shifted a week
    if (parseWeekdayName(s)) |target_dow| {
        const wname_len = weekdayNameLen(s) orelse 0;
        if (wname_len > 0 and wname_len < s.len) {
            var rest = s[wname_len..];
            while (rest.len > 0 and rest[0] == ' ') rest = rest[1..];
            var week_dir: ?i64 = null;
            if (startsWithLower(rest, "this week")) week_dir = 0
            else if (startsWithLower(rest, "next week")) week_dir = 1
            else if (startsWithLower(rest, "last week")) week_dir = -1;
            if (week_dir) |wd| {
                const midnight = baseMidnight(base);
                const epoch_secs: u64 = @intCast(if (midnight < 0) 0 else midnight);
                const es = std.time.epoch.EpochSeconds{ .secs = epoch_secs };
                const day_num: i64 = @intCast(es.getEpochDay().day);
                const current_dow: i64 = @mod(day_num + 3, 7); // 0=Mon
                const monday = midnight - current_dow * 86400 + wd * 7 * 86400;
                return .{ .int = monday + @as(i64, target_dow) * 86400 };
            }
        }
    }

    // weekday name alone ("Monday", "Thursday") - PHP returns TODAY at
    // midnight when the current weekday matches; otherwise the next occurrence
    if (parseWeekdayName(s)) |target_dow| {
        return .{ .int = resolveThisWeekday(base, target_dow) };
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

// parses "+N month(s)", "-N month(s)", "N months ago", "+/- N year(s)" ...
// returns a signed delta in months. only month-grained for now since the
// helper is used by "first/last day of <month-relative>"
fn parseSignedMonthDelta(input: []const u8) ?i64 {
    var s = input;
    var sign: i64 = 1;
    var ago = false;
    if (s.len > 0 and s[0] == '+') { s = s[1..]; }
    else if (s.len > 0 and s[0] == '-') { sign = -1; s = s[1..]; }
    while (s.len > 0 and s[0] == ' ') s = s[1..];
    if (s.len == 0 or s[0] < '0' or s[0] > '9') return null;
    var end: usize = 0;
    while (end < s.len and s[end] >= '0' and s[end] <= '9') end += 1;
    const n = std.fmt.parseInt(i64, s[0..end], 10) catch return null;
    var rest = s[end..];
    while (rest.len > 0 and rest[0] == ' ') rest = rest[1..];
    var unit_months: i64 = 0;
    if (startsWithLower(rest, "months")) { unit_months = 1; rest = rest[6..]; }
    else if (startsWithLower(rest, "month")) { unit_months = 1; rest = rest[5..]; }
    else if (startsWithLower(rest, "years")) { unit_months = 12; rest = rest[5..]; }
    else if (startsWithLower(rest, "year")) { unit_months = 12; rest = rest[4..]; }
    else return null;
    while (rest.len > 0 and rest[0] == ' ') rest = rest[1..];
    if (startsWithLower(rest, "ago")) { ago = true; rest = rest[3..]; }
    while (rest.len > 0 and rest[0] == ' ') rest = rest[1..];
    if (rest.len != 0) return null;
    var delta = n * unit_months * sign;
    if (ago) delta = -delta;
    return delta;
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
    } else if (parseSignedMonthDelta(s)) |delta| {
        // "+N month(s)", "-N month(s)", "N months ago"
        month += delta;
        while (month > 12) { month -= 12; year += 1; }
        while (month < 1) { month += 12; year -= 1; }
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
    var is_this = false;
    if (startsWithLower(s, "next ")) {
        direction = 1;
        s = s[5..];
    } else if (startsWithLower(s, "last ")) {
        direction = -1;
        s = s[5..];
    } else if (startsWithLower(s, "this ")) {
        is_this = true;
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

    // next/last <weekday> [time-of-day]
    if (parseWeekdayName(s)) |target_dow| {
        const wname_len = weekdayNameLen(s) orelse s.len;
        var rest = s[wname_len..];
        while (rest.len > 0 and rest[0] == ' ') rest = rest[1..];
        const ts = if (is_this)
            resolveThisWeekday(base, target_dow)
        else if (direction > 0)
            resolveNextWeekday(base, target_dow)
        else
            resolveLastWeekday(base, target_dow);
        if (rest.len == 0) return ts;
        if (parseTimeOfDay(rest)) |tod| {
            return baseMidnight(ts) + tod.hour * 3600 + tod.min * 60 + tod.sec;
        }
        return ts;
    }

    return null;
}

const TimeOfDay = struct { hour: i64, min: i64, sec: i64 };

fn parseTimeOfDay(input: []const u8) ?TimeOfDay {
    var s = input;
    while (s.len > 0 and s[0] == ' ') s = s[1..];
    if (s.len == 0) return null;
    var i: usize = 0;
    while (i < s.len and s[i] >= '0' and s[i] <= '9') i += 1;
    if (i == 0) return null;
    const hour = std.fmt.parseInt(i64, s[0..i], 10) catch return null;
    var min: i64 = 0;
    var sec: i64 = 0;
    s = s[i..];
    if (s.len > 0 and s[0] == ':') {
        s = s[1..];
        i = 0;
        while (i < s.len and s[i] >= '0' and s[i] <= '9') i += 1;
        if (i == 0) return null;
        min = std.fmt.parseInt(i64, s[0..i], 10) catch return null;
        s = s[i..];
        if (s.len > 0 and s[0] == ':') {
            s = s[1..];
            i = 0;
            while (i < s.len and s[i] >= '0' and s[i] <= '9') i += 1;
            if (i == 0) return null;
            sec = std.fmt.parseInt(i64, s[0..i], 10) catch return null;
            s = s[i..];
        }
    }
    while (s.len > 0 and s[0] == ' ') s = s[1..];
    var h = hour;
    if (s.len >= 2 and eqlLower(s[0..2], "am")) {
        if (h == 12) h = 0;
    } else if (s.len >= 2 and eqlLower(s[0..2], "pm")) {
        if (h < 12) h += 12;
    }
    if (h < 0 or h > 23 or min < 0 or min > 59 or sec < 0 or sec > 59) return null;
    return .{ .hour = h, .min = min, .sec = sec };
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

// PHP semantics for bare 'monday' / 'this monday': returns today at midnight
// when the current weekday matches the target; otherwise the next occurrence.
// resolveNextWeekday always advances at least 1 day, matching 'next monday'
fn resolveThisWeekday(base: i64, target_dow: u3) i64 {
    const midnight = baseMidnight(base);
    const epoch_secs: u64 = @intCast(if (midnight < 0) 0 else midnight);
    const es = std.time.epoch.EpochSeconds{ .secs = epoch_secs };
    const epoch_day = es.getEpochDay();
    const day_num: i64 = @intCast(epoch_day.day);
    const current_dow: u3 = @intCast(@mod(day_num + 3, 7));
    var diff: i64 = @as(i64, target_dow) - @as(i64, current_dow);
    if (diff < 0) diff += 7;
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

const FmtDaySec = struct {
    h: u32, mi: u32, s: u32,
    pub fn getHoursIntoDay(self: @This()) u32 { return self.h; }
    pub fn getMinutesIntoHour(self: @This()) u32 { return self.mi; }
    pub fn getSecondsIntoMinute(self: @This()) u32 { return self.s; }
};
const FmtEpochDay = struct { day: i64 };
const FmtYearDay = struct { year: i64 };
const FmtMonth = struct { v: u32, pub fn numeric(s: @This()) u32 { return s.v; } };
const FmtMonthDay = struct { month: FmtMonth, day_index: u32 };

const IsoWeek = struct { year: i64, week: u32 };

fn isoWeek(day_num: i64) IsoWeek {
    // iso 8601 week-numbering: week 1 contains the year's first Thursday.
    // the iso year is the calendar year of the Thursday in the same week.
    const dow = @mod(day_num + 3, 7); // 0=mon
    const thu = day_num + 3 - dow;
    const thu_secs = thu * 86400;
    const thu_dc = baseComponents(thu_secs);
    const jan1_ts = dateToTimestamp(thu_dc.year, 1, 1, 0, 0, 0);
    const jan1_day = @divFloor(jan1_ts, 86400);
    const week_num: u32 = @intCast(@divFloor(thu - jan1_day, 7) + 1);
    return .{ .year = thu_dc.year, .week = week_num };
}

fn baseComponents(base: i64) DateComponents {
    // Howard Hinnant's civil_from_days, works for any year including pre-1970
    var days = @divFloor(base, 86400);
    var sod: i64 = base - days * 86400; // seconds-of-day in [0,86400)
    if (sod < 0) { sod += 86400; days -= 1; }
    const z = days + 719468;
    const era = @divFloor(z, 146097);
    const doe: i64 = z - era * 146097;
    const yoe: i64 = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const y_civil: i64 = yoe + era * 400;
    const doy: i64 = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp: i64 = @divFloor(5 * doy + 2, 153);
    const d_civil: i64 = doy - @divFloor(153 * mp + 2, 5) + 1;
    const m_civil: i64 = if (mp < 10) mp + 3 else mp - 9;
    const year: i64 = if (m_civil <= 2) y_civil + 1 else y_civil;
    return .{
        .year = year,
        .month = m_civil,
        .day = d_civil,
        .hour = @divFloor(sod, 3600),
        .min = @divFloor(@mod(sod, 3600), 60),
        .sec = @mod(sod, 60),
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

const DstRule = enum { none, us, eu };

const TzEntry = struct {
    name: []const u8,
    std_offset: i32,
    dst_offset: i32,
    dst_rule: DstRule,
    std_abbrev: []const u8,
    dst_abbrev: []const u8,
};

// us dst: second sunday of march 2:00 -> first sunday of november 2:00
// eu dst: last sunday of march 1:00 utc -> last sunday of october 1:00 utc
const tz_table = [_]TzEntry{
    // north america
    .{ .name = "america/new_york", .std_offset = -5 * 3600, .dst_offset = -4 * 3600, .dst_rule = .us, .std_abbrev = "EST", .dst_abbrev = "EDT" },
    .{ .name = "america/chicago", .std_offset = -6 * 3600, .dst_offset = -5 * 3600, .dst_rule = .us, .std_abbrev = "CST", .dst_abbrev = "CDT" },
    .{ .name = "america/denver", .std_offset = -7 * 3600, .dst_offset = -6 * 3600, .dst_rule = .us, .std_abbrev = "MST", .dst_abbrev = "MDT" },
    .{ .name = "america/los_angeles", .std_offset = -8 * 3600, .dst_offset = -7 * 3600, .dst_rule = .us, .std_abbrev = "PST", .dst_abbrev = "PDT" },
    .{ .name = "america/anchorage", .std_offset = -9 * 3600, .dst_offset = -8 * 3600, .dst_rule = .us, .std_abbrev = "AKST", .dst_abbrev = "AKDT" },
    .{ .name = "america/phoenix", .std_offset = -7 * 3600, .dst_offset = -7 * 3600, .dst_rule = .none, .std_abbrev = "MST", .dst_abbrev = "MST" },
    .{ .name = "america/toronto", .std_offset = -5 * 3600, .dst_offset = -4 * 3600, .dst_rule = .us, .std_abbrev = "EST", .dst_abbrev = "EDT" },
    .{ .name = "america/vancouver", .std_offset = -8 * 3600, .dst_offset = -7 * 3600, .dst_rule = .us, .std_abbrev = "PST", .dst_abbrev = "PDT" },
    .{ .name = "america/mexico_city", .std_offset = -6 * 3600, .dst_offset = -6 * 3600, .dst_rule = .none, .std_abbrev = "CST", .dst_abbrev = "CST" },
    .{ .name = "america/sao_paulo", .std_offset = -3 * 3600, .dst_offset = -3 * 3600, .dst_rule = .none, .std_abbrev = "BRT", .dst_abbrev = "BRT" },
    .{ .name = "america/argentina/buenos_aires", .std_offset = -3 * 3600, .dst_offset = -3 * 3600, .dst_rule = .none, .std_abbrev = "ART", .dst_abbrev = "ART" },
    .{ .name = "pacific/honolulu", .std_offset = -10 * 3600, .dst_offset = -10 * 3600, .dst_rule = .none, .std_abbrev = "HST", .dst_abbrev = "HST" },
    // europe
    .{ .name = "europe/london", .std_offset = 0, .dst_offset = 3600, .dst_rule = .eu, .std_abbrev = "GMT", .dst_abbrev = "BST" },
    .{ .name = "europe/paris", .std_offset = 3600, .dst_offset = 2 * 3600, .dst_rule = .eu, .std_abbrev = "CET", .dst_abbrev = "CEST" },
    .{ .name = "europe/berlin", .std_offset = 3600, .dst_offset = 2 * 3600, .dst_rule = .eu, .std_abbrev = "CET", .dst_abbrev = "CEST" },
    .{ .name = "europe/amsterdam", .std_offset = 3600, .dst_offset = 2 * 3600, .dst_rule = .eu, .std_abbrev = "CET", .dst_abbrev = "CEST" },
    .{ .name = "europe/brussels", .std_offset = 3600, .dst_offset = 2 * 3600, .dst_rule = .eu, .std_abbrev = "CET", .dst_abbrev = "CEST" },
    .{ .name = "europe/madrid", .std_offset = 3600, .dst_offset = 2 * 3600, .dst_rule = .eu, .std_abbrev = "CET", .dst_abbrev = "CEST" },
    .{ .name = "europe/rome", .std_offset = 3600, .dst_offset = 2 * 3600, .dst_rule = .eu, .std_abbrev = "CET", .dst_abbrev = "CEST" },
    .{ .name = "europe/zurich", .std_offset = 3600, .dst_offset = 2 * 3600, .dst_rule = .eu, .std_abbrev = "CET", .dst_abbrev = "CEST" },
    .{ .name = "europe/vienna", .std_offset = 3600, .dst_offset = 2 * 3600, .dst_rule = .eu, .std_abbrev = "CET", .dst_abbrev = "CEST" },
    .{ .name = "europe/moscow", .std_offset = 3 * 3600, .dst_offset = 3 * 3600, .dst_rule = .none, .std_abbrev = "MSK", .dst_abbrev = "MSK" },
    .{ .name = "europe/istanbul", .std_offset = 3 * 3600, .dst_offset = 3 * 3600, .dst_rule = .none, .std_abbrev = "TRT", .dst_abbrev = "TRT" },
    .{ .name = "europe/athens", .std_offset = 2 * 3600, .dst_offset = 3 * 3600, .dst_rule = .eu, .std_abbrev = "EET", .dst_abbrev = "EEST" },
    .{ .name = "europe/helsinki", .std_offset = 2 * 3600, .dst_offset = 3 * 3600, .dst_rule = .eu, .std_abbrev = "EET", .dst_abbrev = "EEST" },
    .{ .name = "europe/bucharest", .std_offset = 2 * 3600, .dst_offset = 3 * 3600, .dst_rule = .eu, .std_abbrev = "EET", .dst_abbrev = "EEST" },
    .{ .name = "europe/lisbon", .std_offset = 0, .dst_offset = 3600, .dst_rule = .eu, .std_abbrev = "WET", .dst_abbrev = "WEST" },
    .{ .name = "europe/warsaw", .std_offset = 3600, .dst_offset = 2 * 3600, .dst_rule = .eu, .std_abbrev = "CET", .dst_abbrev = "CEST" },
    // asia
    .{ .name = "asia/tokyo", .std_offset = 9 * 3600, .dst_offset = 9 * 3600, .dst_rule = .none, .std_abbrev = "JST", .dst_abbrev = "JST" },
    .{ .name = "asia/shanghai", .std_offset = 8 * 3600, .dst_offset = 8 * 3600, .dst_rule = .none, .std_abbrev = "CST", .dst_abbrev = "CST" },
    .{ .name = "asia/hong_kong", .std_offset = 8 * 3600, .dst_offset = 8 * 3600, .dst_rule = .none, .std_abbrev = "HKT", .dst_abbrev = "HKT" },
    .{ .name = "asia/singapore", .std_offset = 8 * 3600, .dst_offset = 8 * 3600, .dst_rule = .none, .std_abbrev = "SGT", .dst_abbrev = "SGT" },
    .{ .name = "asia/kolkata", .std_offset = 5 * 3600 + 1800, .dst_offset = 5 * 3600 + 1800, .dst_rule = .none, .std_abbrev = "IST", .dst_abbrev = "IST" },
    .{ .name = "asia/dubai", .std_offset = 4 * 3600, .dst_offset = 4 * 3600, .dst_rule = .none, .std_abbrev = "GST", .dst_abbrev = "GST" },
    .{ .name = "asia/seoul", .std_offset = 9 * 3600, .dst_offset = 9 * 3600, .dst_rule = .none, .std_abbrev = "KST", .dst_abbrev = "KST" },
    .{ .name = "asia/bangkok", .std_offset = 7 * 3600, .dst_offset = 7 * 3600, .dst_rule = .none, .std_abbrev = "ICT", .dst_abbrev = "ICT" },
    .{ .name = "asia/jakarta", .std_offset = 7 * 3600, .dst_offset = 7 * 3600, .dst_rule = .none, .std_abbrev = "WIB", .dst_abbrev = "WIB" },
    .{ .name = "asia/tehran", .std_offset = 3 * 3600 + 1800, .dst_offset = 3 * 3600 + 1800, .dst_rule = .none, .std_abbrev = "IRST", .dst_abbrev = "IRST" },
    .{ .name = "asia/karachi", .std_offset = 5 * 3600, .dst_offset = 5 * 3600, .dst_rule = .none, .std_abbrev = "PKT", .dst_abbrev = "PKT" },
    .{ .name = "asia/dhaka", .std_offset = 6 * 3600, .dst_offset = 6 * 3600, .dst_rule = .none, .std_abbrev = "BST", .dst_abbrev = "BST" },
    .{ .name = "asia/kathmandu", .std_offset = 5 * 3600 + 2700, .dst_offset = 5 * 3600 + 2700, .dst_rule = .none, .std_abbrev = "NPT", .dst_abbrev = "NPT" },
    // oceania
    .{ .name = "australia/sydney", .std_offset = 10 * 3600, .dst_offset = 11 * 3600, .dst_rule = .none, .std_abbrev = "AEST", .dst_abbrev = "AEDT" },
    .{ .name = "australia/melbourne", .std_offset = 10 * 3600, .dst_offset = 11 * 3600, .dst_rule = .none, .std_abbrev = "AEST", .dst_abbrev = "AEDT" },
    .{ .name = "australia/perth", .std_offset = 8 * 3600, .dst_offset = 8 * 3600, .dst_rule = .none, .std_abbrev = "AWST", .dst_abbrev = "AWST" },
    .{ .name = "pacific/auckland", .std_offset = 12 * 3600, .dst_offset = 13 * 3600, .dst_rule = .none, .std_abbrev = "NZST", .dst_abbrev = "NZDT" },
    // africa
    .{ .name = "africa/cairo", .std_offset = 2 * 3600, .dst_offset = 2 * 3600, .dst_rule = .none, .std_abbrev = "EET", .dst_abbrev = "EET" },
    .{ .name = "africa/lagos", .std_offset = 3600, .dst_offset = 3600, .dst_rule = .none, .std_abbrev = "WAT", .dst_abbrev = "WAT" },
    .{ .name = "africa/johannesburg", .std_offset = 2 * 3600, .dst_offset = 2 * 3600, .dst_rule = .none, .std_abbrev = "SAST", .dst_abbrev = "SAST" },
    .{ .name = "africa/nairobi", .std_offset = 3 * 3600, .dst_offset = 3 * 3600, .dst_rule = .none, .std_abbrev = "EAT", .dst_abbrev = "EAT" },
    // aliases
    .{ .name = "utc", .std_offset = 0, .dst_offset = 0, .dst_rule = .none, .std_abbrev = "UTC", .dst_abbrev = "UTC" },
    .{ .name = "gmt", .std_offset = 0, .dst_offset = 0, .dst_rule = .none, .std_abbrev = "GMT", .dst_abbrev = "GMT" },
    .{ .name = "us/eastern", .std_offset = -5 * 3600, .dst_offset = -4 * 3600, .dst_rule = .us, .std_abbrev = "EST", .dst_abbrev = "EDT" },
    .{ .name = "us/central", .std_offset = -6 * 3600, .dst_offset = -5 * 3600, .dst_rule = .us, .std_abbrev = "CST", .dst_abbrev = "CDT" },
    .{ .name = "us/mountain", .std_offset = -7 * 3600, .dst_offset = -6 * 3600, .dst_rule = .us, .std_abbrev = "MST", .dst_abbrev = "MDT" },
    .{ .name = "us/pacific", .std_offset = -8 * 3600, .dst_offset = -7 * 3600, .dst_rule = .us, .std_abbrev = "PST", .dst_abbrev = "PDT" },
    .{ .name = "est", .std_offset = -5 * 3600, .dst_offset = -5 * 3600, .dst_rule = .none, .std_abbrev = "EST", .dst_abbrev = "EST" },
    .{ .name = "mst", .std_offset = -7 * 3600, .dst_offset = -7 * 3600, .dst_rule = .none, .std_abbrev = "MST", .dst_abbrev = "MST" },
    .{ .name = "hst", .std_offset = -10 * 3600, .dst_offset = -10 * 3600, .dst_rule = .none, .std_abbrev = "HST", .dst_abbrev = "HST" },
};

fn lookupTimezone(name: []const u8) ?TzEntry {
    // try fixed offset first: +05:30, -08:00, +0530, etc
    if (name.len >= 5 and (name[0] == '+' or name[0] == '-')) {
        const offset = parseFixedOffset(name) orelse return null;
        return TzEntry{
            .name = name,
            .std_offset = offset,
            .dst_offset = offset,
            .dst_rule = .none,
            .std_abbrev = name,
            .dst_abbrev = name,
        };
    }

    for (tz_table) |entry| {
        if (eqlLower(name, entry.name)) return entry;
    }
    return null;
}

fn parseFixedOffset(s: []const u8) ?i32 {
    if (s.len < 5 or (s[0] != '+' and s[0] != '-')) return null;
    const sign: i32 = if (s[0] == '-') -1 else 1;
    if (s.len >= 6 and s[3] == ':') {
        const h = std.fmt.parseInt(i32, s[1..3], 10) catch return null;
        const m = std.fmt.parseInt(i32, s[4..6], 10) catch return null;
        return sign * (h * 3600 + m * 60);
    }
    const h = std.fmt.parseInt(i32, s[1..3], 10) catch return null;
    const m = std.fmt.parseInt(i32, s[3..5], 10) catch return null;
    return sign * (h * 3600 + m * 60);
}

// find nth occurrence of target_dow (0=sun) in given month/year, or last if n=5
fn nthWeekday(year: i64, month: i64, n: u8, target_dow: u8) i64 {
    if (n == 5) {
        // last occurrence
        const last_day = daysInMonth(month, year);
        var day = last_day;
        while (day >= 1) : (day -= 1) {
            const ts = dateToTimestamp(year, month, day, 0, 0, 0);
            const dow: u8 = @intCast(@mod(@divFloor(ts, 86400) + 4, 7));
            if (dow == target_dow) return day;
        }
        return 1;
    }
    var count: u8 = 0;
    var day: i64 = 1;
    const last_day = daysInMonth(month, year);
    while (day <= last_day) : (day += 1) {
        const ts = dateToTimestamp(year, month, day, 0, 0, 0);
        const dow: u8 = @intCast(@mod(@divFloor(ts, 86400) + 4, 7));
        if (dow == target_dow) {
            count += 1;
            if (count == n) return day;
        }
    }
    return 1;
}

fn isDst(utc_ts: i64, tz: TzEntry) bool {
    if (tz.dst_rule == .none) return false;
    const comps = baseComponents(utc_ts);
    const year = comps.year;

    if (tz.dst_rule == .us) {
        // 2:00 local on second Sunday of March -> 2:00 local on first Sunday of November.
        // local 2:00 = UTC 2:00 - std_offset (subtracting a negative offset adds hours).
        const march_day = nthWeekday(year, 3, 2, 0);
        const nov_day = nthWeekday(year, 11, 1, 0);
        const dst_start = dateToTimestamp(year, 3, march_day, 2, 0, 0) - @as(i64, tz.std_offset);
        const dst_end = dateToTimestamp(year, 11, nov_day, 2, 0, 0) - @as(i64, tz.dst_offset);
        return utc_ts >= dst_start and utc_ts < dst_end;
    }

    if (tz.dst_rule == .eu) {
        // 1:00 UTC on last Sunday of March -> 1:00 UTC on last Sunday of October
        const march_day = nthWeekday(year, 3, 5, 0);
        const oct_day = nthWeekday(year, 10, 5, 0);
        const dst_start = dateToTimestamp(year, 3, march_day, 1, 0, 0);
        const dst_end = dateToTimestamp(year, 10, oct_day, 1, 0, 0);
        return utc_ts >= dst_start and utc_ts < dst_end;
    }

    return false;
}

pub fn tzOffsetAt(tz: TzEntry, utc_ts: i64) i32 {
    if (isDst(utc_ts, tz)) return tz.dst_offset;
    return tz.std_offset;
}

// resolve the local offset for a wall-clock-naive timestamp (seconds as if
// the local wall clock were UTC). probe DST first: if interpreting the wall
// time as a DST-local moment lands inside the DST window, use the DST
// offset; otherwise fall back to standard. this picks the earlier
// interpretation for ambiguous fall-back times (01:00-02:00 local) and
// shifts forward for missing spring-forward times (02:00-03:00 local),
// matching PHP
pub fn tzOffsetForWall(tz: TzEntry, wall_naive_ts: i64) i32 {
    if (tz.dst_rule != .none) {
        if (isDst(wall_naive_ts - tz.dst_offset, tz)) return tz.dst_offset;
    }
    return tz.std_offset;
}

fn tzAbbrevAt(tz: TzEntry, utc_ts: i64) []const u8 {
    if (isDst(utc_ts, tz)) return tz.dst_abbrev;
    return tz.std_abbrev;
}

fn parseTimezoneOffset(s: []const u8) ?i64 {
    // signed offset: +H, +HH, +HHMM, +H:MM, +HH:MM (and minus variants)
    if (s.len >= 2 and (s[0] == '+' or s[0] == '-')) {
        const sign: i64 = if (s[0] == '-') -1 else 1;
        const rest = s[1..];
        if (std.mem.indexOf(u8, rest, ":")) |colon| {
            const h = std.fmt.parseInt(i64, rest[0..colon], 10) catch return null;
            const m = std.fmt.parseInt(i64, rest[colon + 1 ..], 10) catch return null;
            return sign * (h * 3600 + m * 60);
        }
        if (rest.len == 4) {
            const h = std.fmt.parseInt(i64, rest[0..2], 10) catch return null;
            const m = std.fmt.parseInt(i64, rest[2..4], 10) catch return null;
            return sign * (h * 3600 + m * 60);
        }
        const h = std.fmt.parseInt(i64, rest, 10) catch return null;
        return sign * h * 3600;
    }
    // 'GMT+N', 'GMT-N', 'GMT+HH:MM' - PHP accepts these as offset names
    // (UTC+N is NOT accepted; bare UTC is a named zone)
    if (s.len > 3 and std.mem.eql(u8, s[0..3], "GMT") and (s[3] == '+' or s[3] == '-')) {
        return parseTimezoneOffset(s[3..]);
    }
    // named: look up in table
    if (lookupTimezone(s)) |tz| {
        return @intCast(tz.std_offset);
    }
    // short abbreviations for backwards compat
    const abbrevs = [_]struct { name: []const u8, offset: i64 }{
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
    for (abbrevs) |z| {
        // exact match only - prefix matching wrongly accepted 'UTC+9' as 'UTC'
        if (s.len == z.name.len and eqlLower(s, z.name)) return z.offset;
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
    if (args.len == 0 or args[0] != .string) return .{ .string = "" };
    const format = args[0].string;
    const timestamp: i64 = if (args.len >= 2) Value.toInt(args[1]) else std.time.timestamp();
    return formatTimestampTz(ctx, timestamp, format, 0, "UTC");
}

fn native_tz_set(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const name = args[0].string;
    if (lookupTimezone(name)) |_| {
        ctx.vm.default_tz_name = name;
        return .{ .bool = true };
    }
    return .{ .bool = false };
}

fn native_timezone_name_get(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .object) return .{ .bool = false };
    const name = args[0].object.get("timezone");
    if (name == .string) return name;
    return .{ .string = "UTC" };
}

fn native_timezone_offset_get(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .object or args[1] != .object) return .{ .bool = false };
    const tz_obj = args[0].object;
    const dt_obj = args[1].object;
    const tz_name = if (tz_obj.get("timezone") == .string) tz_obj.get("timezone").string else "UTC";
    const ts = getTimestamp(dt_obj);
    if (lookupTimezone(tz_name)) |tz| return .{ .int = @intCast(tzOffsetAt(tz, ts)) };
    return .{ .int = 0 };
}

fn native_timezone_open(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const name = args[0].string;
    // validate against the same rules as DateTimeZone::__construct: accept
    // fixed-offset forms (+HH, +HH:MM, UTC, GMT) and known IANA zones. on
    // failure, PHP emits a Warning and returns false (rather than throwing
    // like the constructor does)
    const valid = blk: {
        if (parseTimezoneOffset(name) != null) break :blk true;
        if (lookupTimezone(name) != null) break :blk true;
        break :blk false;
    };
    if (!valid) {
        const msg = std.fmt.allocPrint(ctx.allocator, "timezone_open(): Unknown or bad timezone ({s})", .{name}) catch return .{ .bool = false };
        ctx.vm.strings.append(ctx.allocator, msg) catch {};
        ctx.vm.emitWarning(msg);
        return .{ .bool = false };
    }
    const obj = try ctx.createObject("DateTimeZone");
    try obj.set(ctx.allocator, "timezone", args[0]);
    return .{ .object = obj };
}

fn native_date_timezone_get(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .object) return .{ .bool = false };
    const tz_v = args[0].object.get("__timezone");
    if (tz_v != .string) return .{ .bool = false };
    const tz_obj = try ctx.createObject("DateTimeZone");
    try tz_obj.set(ctx.allocator, "timezone", tz_v);
    return .{ .object = tz_obj };
}

fn native_date_timezone_set(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .object or args[1] != .object) return .{ .bool = false };
    const tz_name = args[1].object.get("timezone");
    if (tz_name == .string) {
        try args[0].object.set(ctx.allocator, "__timezone", tz_name);
    }
    return args[0];
}

fn native_tz_get(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .string = ctx.vm.default_tz_name };
}

fn native_localtime(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const timestamp: i64 = if (args.len >= 1) Value.toInt(args[0]) else std.time.timestamp();
    const assoc = args.len >= 2 and args[1].isTruthy();
    const epoch_secs: u64 = @intCast(if (timestamp < 0) 0 else timestamp);
    const es = std.time.epoch.EpochSeconds{ .secs = epoch_secs };
    const day_seconds = es.getDaySeconds();
    const epoch_day = es.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_num: i64 = @intCast(epoch_day.day);
    const dow: i64 = @intCast(@mod(day_num + 4, 7));
    const jan1_ts = dateToTimestamp(year_day.year, 1, 1, 0, 0, 0);
    const jan1_es = std.time.epoch.EpochSeconds{ .secs = @intCast(if (jan1_ts < 0) 0 else jan1_ts) };
    const jan1_day: i64 = @intCast(jan1_es.getEpochDay().day);
    const cur_day: i64 = @intCast(epoch_day.day);
    const yday = cur_day - jan1_day;

    var arr = try ctx.createArray();
    if (assoc) {
        try arr.set(ctx.allocator, .{ .string = "tm_sec" }, .{ .int = day_seconds.getSecondsIntoMinute() });
        try arr.set(ctx.allocator, .{ .string = "tm_min" }, .{ .int = day_seconds.getMinutesIntoHour() });
        try arr.set(ctx.allocator, .{ .string = "tm_hour" }, .{ .int = day_seconds.getHoursIntoDay() });
        try arr.set(ctx.allocator, .{ .string = "tm_mday" }, .{ .int = @as(i64, month_day.day_index) + 1 });
        try arr.set(ctx.allocator, .{ .string = "tm_mon" }, .{ .int = month_day.month.numeric() - 1 });
        try arr.set(ctx.allocator, .{ .string = "tm_year" }, .{ .int = year_day.year - 1900 });
        try arr.set(ctx.allocator, .{ .string = "tm_wday" }, .{ .int = dow });
        try arr.set(ctx.allocator, .{ .string = "tm_yday" }, .{ .int = yday });
        try arr.set(ctx.allocator, .{ .string = "tm_isdst" }, .{ .int = 0 });
    } else {
        try arr.append(ctx.allocator, .{ .int = day_seconds.getSecondsIntoMinute() });
        try arr.append(ctx.allocator, .{ .int = day_seconds.getMinutesIntoHour() });
        try arr.append(ctx.allocator, .{ .int = day_seconds.getHoursIntoDay() });
        try arr.append(ctx.allocator, .{ .int = @as(i64, month_day.day_index) + 1 });
        try arr.append(ctx.allocator, .{ .int = month_day.month.numeric() - 1 });
        try arr.append(ctx.allocator, .{ .int = year_day.year - 1900 });
        try arr.append(ctx.allocator, .{ .int = dow });
        try arr.append(ctx.allocator, .{ .int = yday });
        try arr.append(ctx.allocator, .{ .int = 0 });
    }
    return .{ .array = arr };
}

fn native_idate(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string or args[0].string.len == 0) return .{ .bool = false };
    const fmt = args[0].string[0];
    const timestamp: i64 = if (args.len >= 2) Value.toInt(args[1]) else std.time.timestamp();
    const epoch_secs: u64 = @intCast(if (timestamp < 0) 0 else timestamp);
    const es = std.time.epoch.EpochSeconds{ .secs = epoch_secs };
    const day_seconds = es.getDaySeconds();
    const epoch_day = es.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_num: i64 = @intCast(epoch_day.day);
    const dow: i64 = @intCast(@mod(day_num + 4, 7));

    const v: i64 = switch (fmt) {
        'd' => @as(i64, month_day.day_index) + 1,
        'h' => blk: {
            const h12 = @mod(day_seconds.getHoursIntoDay(), 12);
            break :blk if (h12 == 0) @as(@TypeOf(h12), 12) else h12;
        },
        'H' => day_seconds.getHoursIntoDay(),
        'i' => day_seconds.getMinutesIntoHour(),
        'm' => month_day.month.numeric(),
        's' => day_seconds.getSecondsIntoMinute(),
        'U' => timestamp,
        'w' => dow,
        'y' => @mod(year_day.year, 100),
        'Y' => year_day.year,
        't' => daysInMonth(month_day.month.numeric(), year_day.year),
        'z' => year_day.day,
        'I' => 0, // DST flag - approximate as 0 (no DST awareness here)
        'L' => if (isLeapYear(year_day.year)) @as(i64, 1) else 0,
        'N' => if (dow == 0) @as(i64, 7) else dow, // ISO 8601 day of week, Monday=1..Sunday=7
        'B' => @intCast(@mod(@divTrunc(day_seconds.secs, 86), 1000)), // Swatch internet time (rough)
        'Z' => 0, // timezone offset in seconds; without TZ context, default to UTC
        else => return .{ .bool = false },
    };
    return .{ .int = v };
}

fn isLeapYear(y: u16) bool {
    return (y % 4 == 0 and y % 100 != 0) or (y % 400 == 0);
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
    try obj.set(ctx.allocator, "days", .{ .bool = false });
    return .null;
}

fn diCreateFromDateString(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const dur = parseRelativeDuration(args[0].string);
    const obj = try ctx.createObject("DateInterval");
    try obj.set(ctx.allocator, "y", .{ .int = dur.y });
    try obj.set(ctx.allocator, "m", .{ .int = dur.m });
    try obj.set(ctx.allocator, "d", .{ .int = dur.d });
    try obj.set(ctx.allocator, "h", .{ .int = dur.h });
    try obj.set(ctx.allocator, "i", .{ .int = dur.mi });
    try obj.set(ctx.allocator, "s", .{ .int = dur.s });
    try obj.set(ctx.allocator, "f", .{ .float = 0 });
    try obj.set(ctx.allocator, "invert", .{ .int = 0 });
    try obj.set(ctx.allocator, "days", .{ .bool = false });
    return .{ .object = obj };
}

const RelDuration = struct { y: i64 = 0, m: i64 = 0, d: i64 = 0, h: i64 = 0, mi: i64 = 0, s: i64 = 0 };

fn parseRelativeDuration(input: []const u8) RelDuration {
    var out = RelDuration{};
    var i: usize = 0;
    while (i < input.len) {
        while (i < input.len and (input[i] == ' ' or input[i] == '\t')) : (i += 1) {}
        if (i >= input.len) break;

        // optional sign
        var sign: i64 = 1;
        if (input[i] == '+' or input[i] == '-') {
            if (input[i] == '-') sign = -1;
            i += 1;
        }

        // digits
        const num_start = i;
        while (i < input.len and isDigit(input[i])) : (i += 1) {}
        if (i == num_start) {
            // not a number — skip a token to make progress
            while (i < input.len and input[i] != ' ' and input[i] != '\t') : (i += 1) {}
            continue;
        }
        const value = sign * (std.fmt.parseInt(i64, input[num_start..i], 10) catch 0);

        // optional whitespace before unit
        while (i < input.len and (input[i] == ' ' or input[i] == '\t')) : (i += 1) {}

        // unit
        const unit_start = i;
        while (i < input.len and isAlpha(input[i])) : (i += 1) {}
        const unit = input[unit_start..i];
        if (unit.len == 0) continue;

        // check for trailing " ago" which inverts the value
        var save_i = i;
        while (save_i < input.len and (input[save_i] == ' ' or input[save_i] == '\t')) : (save_i += 1) {}
        var v = value;
        if (save_i + 3 <= input.len and eqlLower(input[save_i .. save_i + 3], "ago")) {
            v = -v;
            i = save_i + 3;
        }

        if (matchUnit(unit, "year")) out.y += v
        else if (matchUnit(unit, "month")) out.m += v
        else if (matchUnit(unit, "week")) out.d += v * 7
        else if (matchUnit(unit, "day")) out.d += v
        else if (matchUnit(unit, "hour")) out.h += v
        else if (matchUnit(unit, "minute") or matchUnit(unit, "min")) out.mi += v
        else if (matchUnit(unit, "second") or matchUnit(unit, "sec")) out.s += v;
    }
    return out;
}

fn matchUnit(actual: []const u8, base: []const u8) bool {
    if (eqlLower(actual, base)) return true;
    if (actual.len == base.len + 1 and (actual[actual.len - 1] == 's' or actual[actual.len - 1] == 'S') and eqlLower(actual[0..base.len], base)) return true;
    return false;
}

fn diFormat(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len == 0 or args[0] != .string) return .{ .string = "" };
    const fmt = args[0].string;

    // raw signed values (PHP's lowercase %d/%h/etc print signed values for
    // intervals created from date strings); uppercase variants use abs/2-digit
    const y_signed = Value.toInt(obj.get("y"));
    const m_signed = Value.toInt(obj.get("m"));
    const d_signed = Value.toInt(obj.get("d"));
    const h_signed = Value.toInt(obj.get("h"));
    const i_signed = Value.toInt(obj.get("i"));
    const s_signed = Value.toInt(obj.get("s"));
    const y: u64 = @intCast(@abs(y_signed));
    const m: u64 = @intCast(@abs(m_signed));
    const d: u64 = @intCast(@abs(d_signed));
    const h: u64 = @intCast(@abs(h_signed));
    const mi: u64 = @intCast(@abs(i_signed));
    const s: u64 = @intCast(@abs(s_signed));
    const f_us: u64 = blk: {
        const fv = obj.get("f");
        if (fv == .float) {
            const us: i64 = @intFromFloat(fv.float * 1_000_000.0);
            break :blk @intCast(@abs(us));
        }
        break :blk 0;
    };
    const days_v = obj.get("days");
    const has_days = days_v == .int;
    const days_total: u64 = if (has_days) @intCast(@abs(days_v.int)) else 0;
    const invert = Value.toInt(obj.get("invert")) != 0;

    var buf = std.array_list.Managed(u8).init(ctx.allocator);
    defer buf.deinit();
    const w = buf.writer();

    var i: usize = 0;
    while (i < fmt.len) : (i += 1) {
        const c = fmt[i];
        if (c != '%' or i + 1 >= fmt.len) {
            try w.writeByte(c);
            continue;
        }
        i += 1;
        switch (fmt[i]) {
            'Y' => try w.print("{d:0>2}", .{y}),
            'y' => try w.print("{d}", .{y_signed}),
            'M' => try w.print("{d:0>2}", .{m}),
            'm' => try w.print("{d}", .{m_signed}),
            'D' => try w.print("{d:0>2}", .{d}),
            'd' => try w.print("{d}", .{d_signed}),
            'a' => if (has_days) try w.print("{d}", .{days_total}) else try w.writeAll("(unknown)"),
            'H' => try w.print("{d:0>2}", .{h}),
            'h' => try w.print("{d}", .{h_signed}),
            'I' => try w.print("{d:0>2}", .{mi}),
            'i' => try w.print("{d}", .{i_signed}),
            'S' => try w.print("{d:0>2}", .{s}),
            's' => try w.print("{d}", .{s_signed}),
            'F' => try w.print("{d:0>6}", .{f_us}),
            'f' => try w.print("{d}", .{f_us}),
            'R' => try w.writeByte(if (invert) '-' else '+'),
            'r' => if (invert) try w.writeByte('-'),
            '%' => try w.writeByte('%'),
            else => {
                try w.writeByte('%');
                try w.writeByte(fmt[i]);
            },
        }
    }

    const dup = try ctx.allocator.dupe(u8, buf.items);
    try ctx.strings.append(ctx.allocator, dup);
    return .{ .string = dup };
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
