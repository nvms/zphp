const std = @import("std");
const object_properties = @import("../runtime/object_properties.zig");
const iso_interval = @import("date_iso_interval.zig");
const PhpArray = @import("../runtime/value.zig").PhpArray;
const sync = @import("../sync.zig");
const platform = @import("../platform.zig");
const Value = @import("../runtime/value.zig").Value;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeResult = vm_mod.NativeResult;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };
const zlib = @import("c_zlib");

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
    .{ "date_get_last_errors", dtGetLastErrors },
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
    .{ "date_offset_get", methodAlias("getOffset") },
    .{ "date_isodate_set", methodAlias("setISODate") },
    .{ "timezone_transitions_get", methodAlias("getTransitions") },
    .{ "timezone_location_get", methodAlias("getLocation") },
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
        try dti_const.constants.put(a, c[0], .{ .string = Value.String.borrowed(c[1]) });
    }
    try vm.classes.put(a, "DateTimeInterface", dti_const);

    // DateTime class
    var dt_def = ClassDef{ .name = "DateTime", .native_properties = dateProperties };
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
        try dt_def.constants.put(a, c[0], .{ .string = Value.String.borrowed(c[1]) });
    }
    try dt_def.methods.put(a, "__serialize", .{ .name = "__serialize", .arity = 0 });
    try dt_def.methods.put(a, "__unserialize", .{ .name = "__unserialize", .arity = 1 });
    try dt_def.methods.put(a, "__set_state", .{ .name = "__set_state", .arity = 1, .is_static = true });
    try dt_def.methods.put(a, "__wakeup", .{ .name = "__wakeup", .arity = 0 });
    try vm.native_fns.put(a, "DateTime::__serialize", dateSerialize);
    try vm.native_fns.put(a, "DateTime::__unserialize", dateUnserialize);
    try vm.native_fns.put(a, "DateTime::__set_state", dateSetState);
    try vm.native_fns.put(a, "DateTime::__wakeup", dateWakeup);
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
    var dti_def = ClassDef{ .name = "DateTimeImmutable", .native_properties = dateProperties };
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
    try dti_def.methods.put(a, "setMicrosecond", .{ .name = "setMicrosecond", .arity = 1 });
    try dti_def.methods.put(a, "getLastErrors", .{ .name = "getLastErrors", .arity = 0, .is_static = true });
    try dti_def.methods.put(a, "getTimezone", .{ .name = "getTimezone", .arity = 0 });
    try dti_def.methods.put(a, "setTimezone", .{ .name = "setTimezone", .arity = 1 });
    try dti_def.methods.put(a, "getOffset", .{ .name = "getOffset", .arity = 0 });
    try dti_def.methods.put(a, "createFromFormat", .{ .name = "createFromFormat", .arity = 2, .is_static = true });
    try dti_def.methods.put(a, "createFromMutable", .{ .name = "createFromMutable", .arity = 1, .is_static = true });
    try dti_def.methods.put(a, "createFromInterface", .{ .name = "createFromInterface", .arity = 1, .is_static = true });
    try dti_def.methods.put(a, "setISODate", .{ .name = "setISODate", .arity = 2 });
    inline for (DT_FORMAT_CONSTS) |c| {
        try dti_def.constants.put(a, c[0], .{ .string = Value.String.borrowed(c[1]) });
    }
    try dti_def.methods.put(a, "__serialize", .{ .name = "__serialize", .arity = 0 });
    try dti_def.methods.put(a, "__unserialize", .{ .name = "__unserialize", .arity = 1 });
    try dti_def.methods.put(a, "__set_state", .{ .name = "__set_state", .arity = 1, .is_static = true });
    try dti_def.methods.put(a, "__wakeup", .{ .name = "__wakeup", .arity = 0 });
    try vm.native_fns.put(a, "DateTimeImmutable::__serialize", dateSerialize);
    try vm.native_fns.put(a, "DateTimeImmutable::__unserialize", dateUnserialize);
    try vm.native_fns.put(a, "DateTimeImmutable::__set_state", immutableSetState);
    try vm.native_fns.put(a, "DateTimeImmutable::__wakeup", dateWakeup);
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
    try vm.native_fns.put(a, "DateTimeImmutable::setMicrosecond", dtiSetMicrosecond);
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
    var dtz_def = ClassDef{ .name = "DateTimeZone", .native_properties = timezoneProperties };
    try dtz_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try dtz_def.methods.put(a, "getName", .{ .name = "getName", .arity = 0 });
    try dtz_def.methods.put(a, "getOffset", .{ .name = "getOffset", .arity = 1 });
    try dtz_def.methods.put(a, "__toString", .{ .name = "__toString", .arity = 0 });
    try dtz_def.methods.put(a, "listIdentifiers", .{ .name = "listIdentifiers", .arity = 2, .is_static = true });
    try dtz_def.methods.put(a, "listAbbreviations", .{ .name = "listAbbreviations", .arity = 0, .is_static = true });
    try dtz_def.methods.put(a, "getLocation", .{ .name = "getLocation", .arity = 0 });
    try dtz_def.methods.put(a, "getTransitions", .{ .name = "getTransitions", .arity = 2 });
    try dtz_def.methods.put(a, "__serialize", .{ .name = "__serialize", .arity = 0 });
    try dtz_def.methods.put(a, "__unserialize", .{ .name = "__unserialize", .arity = 1 });
    try dtz_def.methods.put(a, "__set_state", .{ .name = "__set_state", .arity = 1, .is_static = true });
    try dtz_def.methods.put(a, "__wakeup", .{ .name = "__wakeup", .arity = 0 });
    try vm.native_fns.put(a, "DateTimeZone::__serialize", timezoneSerialize);
    try vm.native_fns.put(a, "DateTimeZone::__unserialize", timezoneUnserialize);
    try vm.native_fns.put(a, "DateTimeZone::__set_state", timezoneSetState);
    try vm.native_fns.put(a, "DateTimeZone::__wakeup", timezoneWakeup);
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
    var di_def = ClassDef{ .name = "DateInterval", .native_properties = intervalProperties };
    try di_def.properties.append(a, .{ .name = "y", .default = .{ .int = 0 } });
    try di_def.properties.append(a, .{ .name = "m", .default = .{ .int = 0 } });
    try di_def.properties.append(a, .{ .name = "d", .default = .{ .int = 0 } });
    try di_def.properties.append(a, .{ .name = "h", .default = .{ .int = 0 } });
    try di_def.properties.append(a, .{ .name = "i", .default = .{ .int = 0 } });
    try di_def.properties.append(a, .{ .name = "s", .default = .{ .int = 0 } });
    try di_def.properties.append(a, .{ .name = "f", .default = .{ .float = 0.0 } });
    try di_def.properties.append(a, .{ .name = "invert", .default = .{ .int = 0 } });
    try di_def.properties.append(a, .{ .name = "days", .default = .{ .bool = false } });
    try di_def.properties.append(a, .{ .name = "from_string", .default = .{ .bool = false } });
    try di_def.methods.put(a, "__serialize", .{ .name = "__serialize", .arity = 0 });
    try di_def.methods.put(a, "__unserialize", .{ .name = "__unserialize", .arity = 1 });
    try di_def.methods.put(a, "__set_state", .{ .name = "__set_state", .arity = 1, .is_static = true });
    try di_def.methods.put(a, "__wakeup", .{ .name = "__wakeup", .arity = 0 });
    try vm.native_fns.put(a, "DateInterval::__serialize", intervalSerialize);
    try vm.native_fns.put(a, "DateInterval::__unserialize", intervalUnserialize);
    try vm.native_fns.put(a, "DateInterval::__set_state", intervalSetState);
    try vm.native_fns.put(a, "DateInterval::__wakeup", intervalWakeup);
    try di_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try vm.classes.put(a, "DateInterval", di_def);

    try vm.native_fns.put(a, "DateInterval::__construct", diConstruct);
    try vm.native_fns.put(a, "DateInterval::createFromDateString", diCreateFromDateString);
    try vm.native_fns.put(a, "DateInterval::format", diFormat);

    // DatePeriod
    var dp_def = ClassDef{ .name = "DatePeriod" };
    try dp_def.properties.append(a, .{ .name = "start", .default = .null, .type_str = "?DateTimeInterface", .is_readonly = true, .readonly_undeclared = true });
    try dp_def.properties.append(a, .{ .name = "current", .default = .null, .type_str = "?DateTimeInterface", .is_readonly = true, .readonly_undeclared = true });
    try dp_def.properties.append(a, .{ .name = "end", .default = .null, .type_str = "?DateTimeInterface", .is_readonly = true, .readonly_undeclared = true });
    try dp_def.properties.append(a, .{ .name = "interval", .default = .null, .type_str = "?DateInterval", .is_readonly = true, .readonly_undeclared = true });
    try dp_def.properties.append(a, .{ .name = "recurrences", .default = .{ .int = 1 }, .type_str = "int", .is_readonly = true, .readonly_undeclared = true });
    try dp_def.properties.append(a, .{ .name = "include_start_date", .default = .{ .bool = true }, .type_str = "bool", .is_readonly = true, .readonly_undeclared = true });
    try dp_def.properties.append(a, .{ .name = "include_end_date", .default = .{ .bool = false }, .type_str = "bool", .is_readonly = true, .readonly_undeclared = true });
    try dp_def.methods.put(a, "__serialize", .{ .name = "__serialize", .arity = 0 });
    try dp_def.methods.put(a, "__unserialize", .{ .name = "__unserialize", .arity = 1 });
    try dp_def.methods.put(a, "__set_state", .{ .name = "__set_state", .arity = 1, .is_static = true });
    try dp_def.methods.put(a, "__wakeup", .{ .name = "__wakeup", .arity = 0 });
    try dp_def.methods.put(a, "createFromISO8601String", .{ .name = "createFromISO8601String", .arity = 2, .is_static = true });
    try vm.native_fns.put(a, "DatePeriod::__serialize", periodSerialize);
    try vm.native_fns.put(a, "DatePeriod::__unserialize", periodUnserialize);
    try vm.native_fns.put(a, "DatePeriod::__set_state", periodSetState);
    try vm.native_fns.put(a, "DatePeriod::__wakeup", periodWakeup);
    try vm.native_fns.put(a, "DatePeriod::createFromISO8601String", periodFromIsoString);
    try dp_def.constants.put(a, "EXCLUDE_START_DATE", .{ .int = 1 });
    try dp_def.constants.put(a, "INCLUDE_END_DATE", .{ .int = 2 });
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
const period_fields = [_][]const u8{ "start", "current", "end", "interval", "recurrences", "include_start_date", "include_end_date" };

fn dpConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len >= 1 and args[0] == .string) {
        try ctx.vm.raiseError(VM.E_DEPRECATED, "Calling DatePeriod::__construct(string $isostr, int $options = 0) is deprecated, use DatePeriod::createFromISO8601String() instead");
        try initializePeriodFromIso(ctx, obj, args[0].string.bytes(), if (args.len >= 2) Value.toInt(args[1]) else 0, "DatePeriod::__construct", "DateTime");
        return NativeResult.scalar(.null);
    }
    if (args.len < 3 or args[0] != .object or args[1] != .object) return NativeResult.scalar(.null);
    const options: i64 = if (args.len >= 4) Value.toInt(args[3]) else 0;
    var recurrences: i64 = 0;
    if (args[2] == .object) {
        try obj.set(ctx.allocator, "end", .{ .object = try cloneDateObject(ctx, args[2].object) });
    } else {
        recurrences = Value.toInt(args[2]);
    }
    try obj.set(ctx.allocator, "start", .{ .object = try cloneDateObject(ctx, args[0].object) });
    try obj.set(ctx.allocator, "interval", .{ .object = try cloneDateObject(ctx, args[1].object) });
    try finishPeriod(ctx, obj, recurrences, options, "DatePeriod::__construct");
    return NativeResult.scalar(.null);
}

const max_recurrences: i64 = 2147483639;

// php counts the start and end dates it includes into recurrences
fn setPeriodCount(ctx: *NativeContext, obj: *PhpObject, recurrences: i64, options: i64) RuntimeError!void {
    const include_start = options & 1 == 0;
    const include_end = options & 2 != 0;
    try obj.set(ctx.allocator, "include_start_date", .{ .bool = include_start });
    try obj.set(ctx.allocator, "include_end_date", .{ .bool = include_end });
    try obj.set(ctx.allocator, "recurrences", .{ .int = recurrences + @intFromBool(include_start) + @intFromBool(include_end) });
}

// date_period_init_iso8601_string: start, end, interval and recurrences
// from an ISO 8601 interval string; the dates are UTC, made as base_class
fn initializePeriodFromIso(ctx: *NativeContext, obj: *PhpObject, spec: []const u8, options: i64, func: []const u8, base_class: []const u8) RuntimeError!void {
    const parsed = iso_interval.parse(spec);
    if (parsed.errors > 0) return malformedPeriod(ctx, "Unknown or bad format ({s})", .{spec});
    const begin = parsed.begin orelse return malformedPeriod(ctx, "{s}(): ISO interval must contain a start date, \"{s}\" given", .{ func, spec });
    const period = parsed.period orelse return malformedPeriod(ctx, "{s}(): ISO interval must contain an interval, \"{s}\" given", .{ func, spec });
    if (parsed.end == null and parsed.recurrences == 0) return malformedPeriod(ctx, "{s}(): ISO interval must contain an end date or a recurrence count, \"{s}\" given", .{ func, spec });
    try obj.set(ctx.allocator, "start", .{ .object = try isoDate(ctx, base_class, begin) });
    if (parsed.end) |end| try obj.set(ctx.allocator, "end", .{ .object = try isoDate(ctx, base_class, end) });
    const interval = try ctx.createObject("DateInterval");
    try interval.set(ctx.allocator, "y", .{ .int = period.y });
    try interval.set(ctx.allocator, "m", .{ .int = period.m });
    try interval.set(ctx.allocator, "d", .{ .int = period.d });
    try interval.set(ctx.allocator, "h", .{ .int = period.h });
    try interval.set(ctx.allocator, "i", .{ .int = period.i });
    try interval.set(ctx.allocator, "s", .{ .int = period.s });
    try obj.set(ctx.allocator, "interval", .{ .object = interval });
    try finishPeriod(ctx, obj, parsed.recurrences, options, func);
}

fn isoDate(ctx: *NativeContext, class: []const u8, d: iso_interval.Date) RuntimeError!*PhpObject {
    const date = try ctx.createObject(class);
    try date.set(ctx.allocator, "__timestamp", .{ .int = dateToTimestamp(d.y, d.m, d.d, d.h, d.i, d.s) });
    try date.set(ctx.allocator, "__timezone", .{ .string = Value.String.borrowed("+00:00") });
    return date;
}

// date_period_init_finish
fn finishPeriod(ctx: *NativeContext, obj: *PhpObject, recurrences: i64, options: i64, func: []const u8) RuntimeError!void {
    if (obj.get("end") == .null and (recurrences < 1 or recurrences > max_recurrences)) {
        return malformedPeriod(ctx, "{s}(): Recurrence count must be greater or equal to 1 and lower than 2147483640", .{func});
    }
    try setPeriodCount(ctx, obj, recurrences, options);
}

fn malformedPeriod(ctx: *NativeContext, comptime fmt: []const u8, args: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("DateMalformedPeriodStringException", msg);
    return error.RuntimeError;
}

fn periodFromIsoString(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try ctx.createObject(staticClass(ctx, "DatePeriod"));
    const spec = if (args.len >= 1 and args[0] == .string) args[0].string.bytes() else "";
    try initializePeriodFromIso(ctx, obj, spec, if (args.len >= 2) Value.toInt(args[1]) else 0, "DatePeriod::createFromISO8601String", "DateTimeImmutable");
    return NativeResult.borrowed(.{ .object = obj });
}

// each read hands out a copy, so the period itself never changes
fn periodCopy(ctx: *NativeContext, v: Value) RuntimeError!NativeResult {
    if (v != .object) return NativeResult.scalar(.null);
    return NativeResult.borrowed(.{ .object = try cloneDateObject(ctx, v.object) });
}

fn dpGetStart(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    return periodCopy(ctx, obj.get("start"));
}

fn dpGetEnd(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    return periodCopy(ctx, obj.get("end"));
}

fn dpGetInterval(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    return periodCopy(ctx, obj.get("interval"));
}

// the count given to the constructor, or null for a period with an end date
fn dpGetRecurrences(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const given = Value.toInt(obj.get("recurrences")) - @intFromBool(obj.get("include_start_date").isTruthy()) - @intFromBool(obj.get("include_end_date").isTruthy());
    return NativeResult.scalar(if (given == 0) .null else .{ .int = given });
}

fn dpGetIterator(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const iter = try ctx.vm.allocObject(.{ .class_name = "DatePeriodIterator" });
    try iter.set(ctx.allocator, "__period", .{ .object = obj });
    try iter.set(ctx.allocator, "__index", .{ .int = 0 });
    return NativeResult.borrowed(.{ .object = iter });
}

fn iteratedPeriod(ctx: *NativeContext) ?*PhpObject {
    const this = getThis(ctx) orelse return null;
    const period = this.get("__period");
    return if (period == .object) period.object else null;
}

// date_period_advance: the period's current date moved on by its interval
fn advancePeriod(ctx: *NativeContext, period: *PhpObject) RuntimeError!void {
    const current = period.get("current");
    const interval = period.get("interval");
    if (current != .object or interval != .object) return;
    const us_v = current.object.get("__microseconds");
    const next = try periodStep(ctx, getTimestamp(current.object), if (us_v == .int) us_v.int else 0, objTzName(current.object, ctx.vm.default_tz_name), interval.object);
    const moved = try cloneDateObject(ctx, current.object);
    try moved.set(ctx.allocator, "__timestamp", .{ .int = next.ts });
    if (next.us != 0 or moved.get("__microseconds") != .null) try moved.set(ctx.allocator, "__microseconds", .{ .int = next.us });
    try period.set(ctx.allocator, "current", .{ .object = moved });
}

fn dpiRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const period = iteratedPeriod(ctx) orelse return NativeResult.scalar(.null);
    try getThis(ctx).?.set(ctx.allocator, "__index", .{ .int = 0 });
    const start = period.get("start");
    if (start != .object) {
        try ctx.vm.setPendingException("Error", "The DatePeriod object has not been correctly initialized by its constructor");
        return error.RuntimeError;
    }
    try period.set(ctx.allocator, "current", .{ .object = try cloneDateObject(ctx, start.object) });
    if (!period.get("include_start_date").isTruthy()) try advancePeriod(ctx, period);
    return NativeResult.scalar(.null);
}

// date_period_it_has_more
fn dpiValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const period = iteratedPeriod(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const current = period.get("current");
    if (current != .object) return NativeResult.scalar(.{ .bool = false });
    const end = period.get("end");
    if (end == .object) {
        const ts = getTimestamp(current.object);
        const end_ts = getTimestamp(end.object);
        return NativeResult.scalar(.{ .bool = if (period.get("include_end_date").isTruthy()) ts <= end_ts else ts < end_ts });
    }
    return NativeResult.scalar(.{ .bool = Value.toInt(getThis(ctx).?.get("__index")) < Value.toInt(period.get("recurrences")) });
}

// the current date as the start date's base class, DateTime or
// DateTimeImmutable
fn dpiCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const period = iteratedPeriod(ctx) orelse return NativeResult.scalar(.null);
    const current = period.get("current");
    if (current != .object) return NativeResult.scalar(.null);
    const base: []const u8 = if (ctx.vm.isInstanceOf(current.object.class_name, "DateTimeImmutable")) "DateTimeImmutable" else "DateTime";
    const dt = try ctx.createObject(base);
    try dt.set(ctx.allocator, "__timestamp", current.object.get("__timestamp"));
    if (current.object.get("__timezone") == .string) try dt.set(ctx.allocator, "__timezone", current.object.get("__timezone"));
    if (current.object.get("__microseconds") == .int) try dt.set(ctx.allocator, "__microseconds", current.object.get("__microseconds"));
    return NativeResult.borrowed(.{ .object = dt });
}

fn dpiKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.scalar(this.get("__index"));
}

fn dpiNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const period = iteratedPeriod(ctx) orelse return NativeResult.scalar(.null);
    try advancePeriod(ctx, period);
    const this = getThis(ctx).?;
    try this.set(ctx.allocator, "__index", .{ .int = Value.toInt(this.get("__index")) + 1 });
    return NativeResult.scalar(.null);
}

// the seven fields first, then the object's other properties
fn periodSerialize(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const out = try ctx.createArray();
    for (period_fields) |name| try out.set(ctx.allocator, .{ .string = Value.String.borrowed(name) }, obj.get(name));
    const own = try object_properties.ownTable(ctx.vm, obj);
    for (own.entries.items) |entry| if (!out.contains(entry.key)) try out.set(ctx.allocator, entry.key, entry.value);
    return NativeResult.borrowed(.{ .array = out });
}

// php_date_period_initialize_from_hash
fn initializePeriodFromHash(ctx: *NativeContext, obj: *PhpObject, data: *const PhpArray) RuntimeError!bool {
    for ([_][]const u8{ "start", "end", "current" }) |name| {
        const key: PhpArray.Key = .{ .string = Value.String.borrowed(name) };
        if (!data.contains(key)) return false;
        const v = data.get(key);
        if (v == .object and ctx.vm.isInstanceOf(v.object.class_name, "DateTimeInterface")) {
            if (v.object.get("__timestamp") == .null) return false;
            try obj.set(ctx.allocator, name, .{ .object = try cloneDateObject(ctx, v.object) });
        } else if (v == .null) {
            try obj.set(ctx.allocator, name, .null);
        } else return false;
    }
    const interval = data.get(.{ .string = Value.String.borrowed("interval") });
    if (interval != .object or !ctx.vm.isInstanceOf(interval.object.class_name, "DateInterval")) return false;
    try obj.set(ctx.allocator, "interval", .{ .object = try cloneDateObject(ctx, interval.object) });
    const recurrences = data.get(.{ .string = Value.String.borrowed("recurrences") });
    if (recurrences != .int or recurrences.int < 0 or recurrences.int > std.math.maxInt(i32)) return false;
    try obj.set(ctx.allocator, "recurrences", recurrences);
    for ([_][]const u8{ "include_start_date", "include_end_date" }) |name| {
        const v = data.get(.{ .string = Value.String.borrowed(name) });
        if (v != .bool) return false;
        try obj.set(ctx.allocator, name, v);
    }
    return true;
}

fn periodUnserialize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len == 0 or args[0] != .array or !try initializePeriodFromHash(ctx, obj, args[0].array)) return invalidSerialization(ctx, "DatePeriod");
    try restoreCustomProperties(ctx, obj, args[0].array, &period_fields);
    return NativeResult.scalar(.null);
}

fn periodSetState(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try ctx.createObject("DatePeriod");
    if (args.len == 0 or args[0] != .array or !try initializePeriodFromHash(ctx, obj, args[0].array)) return invalidSerialization(ctx, "DatePeriod");
    return NativeResult.borrowed(.{ .object = obj });
}

fn periodWakeup(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const own = try object_properties.ownTable(ctx.vm, obj);
    if (!try initializePeriodFromHash(ctx, obj, own)) return invalidSerialization(ctx, "DatePeriod");
    return NativeResult.scalar(.null);
}

fn dtGetLastErrors(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // false when the last parse had neither warnings nor errors (php 8.2+)
    if (!ctx.vm.last_dt.set) return NativeResult.scalar(.{ .bool = false });
    const result = try ctx.createArray();
    try putErrorContainer(ctx, result, &ctx.vm.last_dt);
    return NativeResult.borrowed(.{ .array = result });
}

// what php shows of a date object for every output purpose: its own
// properties, then date, timezone_type and timezone (date_object_to_hash)
fn dateProperties(ctx: *NativeContext, obj: *PhpObject, _: object_properties.Purpose) RuntimeError!?*PhpArray {
    const table = try object_properties.ownTable(ctx.vm, obj);
    try putDateFields(ctx, obj, table);
    return table;
}

fn putDateFields(ctx: *NativeContext, obj: *PhpObject, table: *PhpArray) RuntimeError!void {
    // a subclass that never called the parent constructor has no date
    if (obj.get("__timestamp") == .null) return;
    const ts = getTimestamp(obj);
    const zone_v = obj.get("__timezone");
    const zone = if (zone_v == .string) ParseZone.of(zone_v.string.bytes(), false) else ParseZone.of(ctx.vm.default_tz_name, true);
    const us_v = obj.get("__microseconds");
    const formatted = try formatTimestampTzMicros(ctx, ts, "x-m-d H:i:s.u", @intCast(zone.totalOffset(ctx.allocator, ts)), zone.name(), if (us_v == .int) us_v.int else 0);
    defer if (formatted.value == .string) formatted.value.string.release();
    try table.set(ctx.allocator, .{ .string = Value.String.borrowed("date") }, formatted.value);
    try putZoneFields(ctx, &zone, table);
}

fn putZoneFields(ctx: *NativeContext, zone: *const ParseZone, table: *PhpArray) RuntimeError!void {
    try table.set(ctx.allocator, .{ .string = Value.String.borrowed("timezone_type") }, .{ .int = zone.kind });
    const name = try Value.String.create(ctx.allocator, zone.name());
    defer name.release();
    try table.set(ctx.allocator, .{ .string = Value.String.borrowed("timezone") }, .{ .string = name });
}

// a DateTimeZone shows timezone_type and timezone
fn timezoneProperties(ctx: *NativeContext, obj: *PhpObject, _: object_properties.Purpose) RuntimeError!?*PhpArray {
    const table = try object_properties.ownTable(ctx.vm, obj);
    const name = obj.get("__timezone");
    if (name == .string) try putZoneFields(ctx, &ParseZone.of(name.string.bytes(), false), table);
    return table;
}

// __serialize: the date fields first, then the object's own properties
fn dateSerialize(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    try requireInitializedDate(ctx, obj);
    const out = try ctx.createArray();
    try putDateFields(ctx, obj, out);
    try appendOwnMissing(ctx, obj, out);
    return NativeResult.borrowed(.{ .array = out });
}

fn timezoneSerialize(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const out = try ctx.createArray();
    const name = obj.get("__timezone");
    if (name == .string) try putZoneFields(ctx, &ParseZone.of(name.string.bytes(), false), out);
    try appendOwnMissing(ctx, obj, out);
    return NativeResult.borrowed(.{ .array = out });
}

fn appendOwnMissing(ctx: *NativeContext, obj: *PhpObject, out: *PhpArray) RuntimeError!void {
    const own = try object_properties.ownTable(ctx.vm, obj);
    for (own.entries.items) |entry| {
        if (!out.contains(entry.key)) try out.set(ctx.allocator, entry.key, entry.value);
    }
}

fn requireInitializedDate(ctx: *NativeContext, obj: *PhpObject) RuntimeError!void {
    if (obj.get("__timestamp") != .null) return;
    const msg = try std.fmt.allocPrint(ctx.allocator, "The DateTimeInterface object has not been correctly initialized by its constructor", .{});
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("Error", msg);
    return error.RuntimeError;
}

// php_date_initialize_from_hash: date, timezone_type and timezone rebuild the
// date; an offset or abbreviation is read back as part of the date string
fn initializeDateFromHash(ctx: *NativeContext, obj: *PhpObject, data: *const PhpArray) RuntimeError!bool {
    const date = data.get(.{ .string = Value.String.borrowed("date") });
    const zone_type = data.get(.{ .string = Value.String.borrowed("timezone_type") });
    const zone = data.get(.{ .string = Value.String.borrowed("timezone") });
    if (date != .string or zone_type != .int or zone != .string) return false;
    switch (zone_type.int) {
        dp.ZONETYPE_OFFSET, dp.ZONETYPE_ABBR => {
            const input = try std.fmt.allocPrint(ctx.allocator, "{s} {s}", .{ date.string.bytes(), zone.string.bytes() });
            defer ctx.allocator.free(input);
            const instant = (try resolveDate(ctx, input, null, false)) orelse return false;
            try storeInstant(ctx, obj, instant.ts, instant.us, &instant.zone);
            return true;
        },
        dp.ZONETYPE_ID => {
            const parsed = (try timezoneInitialize(ctx, zone.string.bytes(), "", false)) orelse return false;
            if (parsed.kind != dp.ZONETYPE_ID) return false;
            const instant = (try resolveDate(ctx, date.string.bytes(), parsed.name(), false)) orelse return false;
            try storeInstant(ctx, obj, instant.ts, instant.us, &instant.zone);
            return true;
        },
        else => return false,
    }
}

// php_date_timezone_initialize_from_hash
fn initializeTimezoneFromHash(ctx: *NativeContext, obj: *PhpObject, data: *const PhpArray) RuntimeError!bool {
    const zone_type = data.get(.{ .string = Value.String.borrowed("timezone_type") });
    const zone = data.get(.{ .string = Value.String.borrowed("timezone") });
    if (zone_type != .int or zone_type.int < dp.ZONETYPE_OFFSET or zone_type.int > dp.ZONETYPE_ID or zone != .string) return false;
    const parsed = (try timezoneInitialize(ctx, zone.string.bytes(), "", false)) orelse return false;
    try obj.setCopiedString(ctx.allocator, "__timezone", parsed.name());
    return true;
}

// the properties a serialized date carries besides its own fields go back
// onto the object
fn restoreCustomProperties(ctx: *NativeContext, obj: *PhpObject, data: *const PhpArray, internal: []const []const u8) RuntimeError!void {
    entries: for (data.entries.items) |entry| {
        if (entry.key != .string or entry.ref != null) continue;
        const key = entry.key.string.bytes();
        for (internal) |name| if (std.mem.eql(u8, key, name)) continue :entries;
        const name = if (key.len > 0 and key[0] == 0) if (std.mem.lastIndexOfScalar(u8, key[1..], 0)) |end| key[end + 2 ..] else key else key;
        try obj.set(ctx.allocator, name, entry.value);
    }
}

fn invalidSerialization(ctx: *NativeContext, class: []const u8) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, "Invalid serialization data for {s} object", .{class});
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("Error", msg);
    return error.RuntimeError;
}

fn dateBaseClass(ctx: *NativeContext, obj: *PhpObject) []const u8 {
    return if (ctx.vm.isInstanceOf(obj.class_name, "DateTimeImmutable")) "DateTimeImmutable" else "DateTime";
}

fn dateUnserialize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len == 0 or args[0] != .array or !try initializeDateFromHash(ctx, obj, args[0].array)) return invalidSerialization(ctx, dateBaseClass(ctx, obj));
    try restoreCustomProperties(ctx, obj, args[0].array, &.{ "date", "timezone_type", "timezone" });
    return NativeResult.scalar(.null);
}

fn timezoneUnserialize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len == 0 or args[0] != .array or !try initializeTimezoneFromHash(ctx, obj, args[0].array)) return invalidSerialization(ctx, "DateTimeZone");
    try restoreCustomProperties(ctx, obj, args[0].array, &.{ "timezone_type", "timezone" });
    return NativeResult.scalar(.null);
}

// __set_state builds the base class, never a subclass
fn dateSetStateOf(ctx: *NativeContext, args: []const Value, class: []const u8) RuntimeError!NativeResult {
    const obj = try ctx.createObject(class);
    if (args.len == 0 or args[0] != .array or !try initializeDateFromHash(ctx, obj, args[0].array)) return invalidSerialization(ctx, class);
    return NativeResult.borrowed(.{ .object = obj });
}

fn dateSetState(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return dateSetStateOf(ctx, args, "DateTime");
}

fn immutableSetState(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return dateSetStateOf(ctx, args, "DateTimeImmutable");
}

fn timezoneSetState(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try ctx.createObject("DateTimeZone");
    if (args.len == 0 or args[0] != .array or !try initializeTimezoneFromHash(ctx, obj, args[0].array)) return invalidSerialization(ctx, "DateTimeZone");
    return NativeResult.borrowed(.{ .object = obj });
}

// __wakeup rebuilds the date from the object's own properties
fn dateWakeup(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const own = try object_properties.ownTable(ctx.vm, obj);
    if (!try initializeDateFromHash(ctx, obj, own)) return invalidSerialization(ctx, dateBaseClass(ctx, obj));
    return NativeResult.scalar(.null);
}

fn timezoneWakeup(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const own = try object_properties.ownTable(ctx.vm, obj);
    if (!try initializeTimezoneFromHash(ctx, obj, own)) return invalidSerialization(ctx, "DateTimeZone");
    return NativeResult.scalar(.null);
}

fn getThis(ctx: *NativeContext) ?*PhpObject {
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

fn getTimestamp(obj: *PhpObject) i64 {
    return Value.toInt(obj.get("__timestamp"));
}

fn dtConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const input: []const u8 = if (args.len >= 1 and args[0] == .string) args[0].string.bytes() else "";
    const instant = (try resolveDate(ctx, input, tzArgName(args, 1), true)) orelse return error.RuntimeError;
    try storeInstant(ctx, obj, instant.ts, instant.us, &instant.zone);
    return NativeResult.scalar(.null);
}

// the zone name of an optional DateTimeZone argument
fn tzArgName(args: []const Value, idx: usize) ?[]const u8 {
    if (args.len <= idx or args[idx] != .object) return null;
    const v = args[idx].object.get("__timezone");
    return if (v == .string) v.string.bytes() else null;
}

// a copy of a date object of the same class, for the immutable methods
fn cloneDateObject(ctx: *NativeContext, src: *PhpObject) RuntimeError!*PhpObject {
    const copy = try ctx.createObject(src.class_name);
    if (src.slots) |ss| if (copy.slots) |cs| if (cs.len == ss.len) {
        for (ss, 0..) |v, i| cs[i] = try ctx.vm.copyValue(v);
    };
    var it = src.properties.iterator();
    while (it.next()) |e| try copy.set(ctx.allocator, e.key_ptr.*, e.value_ptr.*);
    return copy;
}

fn dtFormat(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len == 0 or args[0] != .string) return NativeResult.literal("");
    const ts = getTimestamp(obj);
    const tz_val = obj.get("__timezone");
    const tz_name = if (tz_val == .string) tz_val.string.bytes() else ctx.vm.default_tz_name;
    const offset = tzOffsetForName(ctx.allocator, tz_name, ts);
    const us_v = obj.get("__microseconds");
    const us: i64 = if (us_v == .int) us_v.int else 0;
    return formatTimestampTzMicros(ctx, ts, args[0].string.bytes(), offset, tz_name, us);
}

pub fn formatTimestamp(ctx: *NativeContext, timestamp: i64, format: []const u8) RuntimeError!NativeResult {
    const tz_name = ctx.vm.default_tz_name;
    const offset = tzOffsetForName(ctx.allocator, tz_name, timestamp);
    return formatTimestampTzMicros(ctx, timestamp, format, offset, tz_name, 0);
}

pub fn formatTimestampTz(ctx: *NativeContext, timestamp: i64, format: []const u8, tz_offset: i32, tz_name: []const u8) RuntimeError!NativeResult {
    return formatTimestampTzMicros(ctx, timestamp, format, tz_offset, tz_name, 0);
}

// the year as 'c' and 'r' print it: four characters with the sign counted,
// so -2 is "-002"
fn paddedYear(buf: *[24]u8, year: i64) []const u8 {
    if (year >= 0) return std.fmt.bufPrint(buf, "{d:0>4}", .{@as(u64, @intCast(year))}) catch "0000";
    return std.fmt.bufPrint(buf, "-{d:0>3}", .{@abs(year)}) catch "-000";
}

pub fn formatTimestampTzMicros(ctx: *NativeContext, timestamp: i64, format: []const u8, tz_offset: i32, tz_name: []const u8, microseconds: i64) RuntimeError!NativeResult {
    // wraps at the ends of the range, as php's c arithmetic does
    const local_ts = timestamp +% @as(i64, tz_offset);
    const dc = baseComponents(local_ts);
    const day_seconds = FmtDaySec{ .h = @intCast(dc.hour), .mi = @intCast(dc.min), .s = @intCast(dc.sec) };
    const epoch_day = FmtEpochDay{ .day = @divFloor(local_ts, 86400) };
    const year_day = FmtYearDay{ .year = dc.year };
    const month_day = FmtMonthDay{ .month = .{ .v = @intCast(dc.month) }, .day_index = @intCast(dc.day - 1) };
    const a = ctx.allocator;

    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(a);
    var fi: usize = 0;
    while (fi < format.len) : (fi += 1) {
        const c = format[fi];
        switch (c) {
            'Y' => {
                // at least four digits, with the sign outside the padding
                try buf.print(a, "{s}{d:0>4}", .{ if (year_day.year < 0) "-" else "", @abs(year_day.year) });
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
                var tmp: [24]u8 = undefined;
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
                try buf.print(a, "{d}", .{daysInMonth(month_day.month.numeric(), year_day.year)});
            },
            'c' => {
                // ISO 8601: YYYY-MM-DDTHH:MM:SS+00:00
                var tmp: [32]u8 = undefined;
                var ybuf: [24]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{s}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}", .{
                    paddedYear(&ybuf, year_day.year),
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
                var ybuf: [24]u8 = undefined;
                const s2 = std.fmt.bufPrint(&tmp, " {s} {d:0>2}:{d:0>2}:{d:0>2} ", .{
                    paddedYear(&ybuf, year_day.year),
                    day_seconds.getHoursIntoDay(),
                    day_seconds.getMinutesIntoHour(),
                    day_seconds.getSecondsIntoMinute(),
                }) catch " 0000 00:00:00 ";
                try buf.appendSlice(a, s2);
                try appendOffsetCompact(&buf, a, tz_offset);
            },
            'z' => {
                const jan1_day = @divFloor(dateToTimestamp(year_day.year, 1, 1, 0, 0, 0), 86400);
                try buf.print(a, "{d}", .{@as(i64, epoch_day.day) - jan1_day});
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
                try buf.append(a, if (isLeapYear(year_day.year)) '1' else '0');
            },
            'o' => {
                const week = isoWeek(@intCast(epoch_day.day));
                var tmp: [24]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{week.year}) catch "0000";
                try buf.appendSlice(a, s);
            },
            'X' => {
                // PHP 8.4: ISO 8601 expanded year with mandatory leading sign,
                // four-digit minimum
                var tmp: [24]u8 = undefined;
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
                var tmp: [24]u8 = undefined;
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
                // a fixed-offset zone has no abbreviation; php spells it GMT+hhmm
                if (parseFixedOffset(tz_name)) |off| {
                    const abs: u32 = @intCast(if (off < 0) -off else off);
                    try buf.print(a, "GMT{c}{d:0>2}{d:0>2}", .{ @as(u8, if (off < 0) '-' else '+'), abs / 3600, (abs % 3600) / 60 });
                } else if (tzAbbrevForName(a, tz_name, timestamp)) |ab| {
                    defer a.free(ab);
                    try buf.appendSlice(a, ab);
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
            'I' => try buf.append(a, if (tzIsDstForName(a, tz_name, timestamp)) '1' else '0'),
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
    return NativeResult.takeString(try Value.String.adopt(a, result));
}

fn dtGetTimestamp(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.scalar(.{ .int = getTimestamp(obj) });
}

fn dtModify(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len == 0 or args[0] != .string) return NativeResult.borrowed(.{ .object = obj });
    _ = try modifyDateObject(ctx, obj, args[0].string.bytes(), "DateTime::modify(): ", true);
    return NativeResult.borrowed(.{ .object = obj });
}

fn dtiModify(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len == 0 or args[0] != .string) return NativeResult.borrowed(.{ .object = obj });
    const new_obj = try cloneDateObject(ctx, obj);
    _ = try modifyDateObject(ctx, new_obj, args[0].string.bytes(), "DateTimeImmutable::modify(): ", true);
    return NativeResult.borrowed(.{ .object = new_obj });
}

// a DateInterval as timelib_rel_time. f holds the microseconds as a float;
// rounding recovers the integer every native interval was made from. an
// interval from a date string keeps its weekday and special parts only in the
// string, so they are read back from it
const IntervalSpec = struct { rel: dp.Rel, invert: bool, wall: bool };

fn intervalSpec(ctx: *NativeContext, iv: *PhpObject) RuntimeError!IntervalSpec {
    var rel = dp.Rel{};
    if (iv.get("from_string") == .bool and iv.get("from_string").bool and iv.get("__date_string") == .string) {
        var p = try parseDate(ctx, iv.get("__date_string").string.bytes());
        defer p.deinit(ctx.allocator);
        rel = p.time.relative;
    }
    rel.y = Value.toInt(iv.get("y"));
    rel.m = Value.toInt(iv.get("m"));
    rel.d = Value.toInt(iv.get("d"));
    rel.h = Value.toInt(iv.get("h"));
    rel.i = Value.toInt(iv.get("i"));
    rel.s = Value.toInt(iv.get("s"));
    const f = Value.toFloat(iv.get("f"));
    rel.us = if (f == f and @abs(f) < 9.2e12) @intFromFloat(@round(f * 1e6)) else 0;
    return .{ .rel = rel, .invert = Value.toInt(iv.get("invert")) != 0, .wall = iv.get("__wall") == .bool and iv.get("__wall").bool };
}

// the object's instant as timelib holds it: wall-clock fields in its zone
fn objTime(ctx: *NativeContext, obj: *PhpObject) dp.Time {
    const zone = ParseZone.of(objTzName(obj, ctx.vm.default_tz_name), false);
    const us_v = obj.get("__microseconds");
    return wallTime(ctx.allocator, getTimestamp(obj), if (us_v == .int) us_v.int else 0, &zone);
}

fn storeTime(ctx: *NativeContext, obj: *PhpObject, t: *const dp.Time) RuntimeError!void {
    const zone = ParseZone.of(objTzName(obj, ctx.vm.default_tz_name), false);
    try storeInstant(ctx, obj, t.sse, t.us, &zone);
}

// one DatePeriod step from an instant in a zone
fn periodStep(ctx: *NativeContext, ts: i64, us: i64, tz_name: []const u8, iv: *PhpObject) RuntimeError!struct { ts: i64, us: i64 } {
    const spec = try intervalSpec(ctx, iv);
    const zone = ParseZone.of(tz_name, false);
    var t = wallTime(ctx.allocator, ts, us, &zone);
    dp.periodAdvance(&t, &spec.rel, parse_db);
    return .{ .ts = t.sse, .us = t.us };
}

// the setters (setDate, setTime, setISODate) work on the wall-clock time in
// the object's own timezone: split the instant into local fields, change some,
// and turn the result back into an instant with the offset in effect then

fn wallFields(ctx: *NativeContext, obj: *PhpObject) DateComponents {
    const ts = getTimestamp(obj);
    return baseComponents(ts + tzOffsetForName(ctx.allocator, objTzName(obj, ctx.vm.default_tz_name), ts));
}

fn instantOfWall(ctx: *NativeContext, obj: *PhpObject, wall: i64) i64 {
    return wall - tzOffsetForWallByName(ctx.allocator, objTzName(obj, ctx.vm.default_tz_name), wall);
}

fn objTzName(obj: *PhpObject, fallback: []const u8) []const u8 {
    const v = obj.get("__timezone");
    return if (v == .string) v.string.bytes() else fallback;
}

// the setters change an object in place; DateTime's methods apply them to
// $this and DateTimeImmutable's to a clone, so both keep every other field
// (microseconds, the zone, a subclass's own properties)
const Mutation = fn (*NativeContext, *PhpObject, []const Value) RuntimeError!void;

fn mutating(comptime f: Mutation) fn (*NativeContext, []const Value) RuntimeError!NativeResult {
    return struct {
        fn call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
            const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
            try f(ctx, obj, args);
            return NativeResult.borrowed(.{ .object = obj });
        }
    }.call;
}

fn immutable(comptime f: Mutation) fn (*NativeContext, []const Value) RuntimeError!NativeResult {
    return struct {
        fn call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
            const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
            const copy = try cloneDateObject(ctx, obj);
            try f(ctx, copy, args);
            return NativeResult.borrowed(.{ .object = copy });
        }
    }.call;
}

fn addOn(ctx: *NativeContext, obj: *PhpObject, args: []const Value) RuntimeError!void {
    if (args.len == 0 or args[0] != .object) return;
    const spec = try intervalSpec(ctx, args[0].object);
    var t = objTime(ctx, obj);
    if (spec.wall) dp.addWall(&t, &spec.rel, spec.invert, 1, parse_db) else dp.add(&t, &spec.rel, spec.invert, parse_db);
    try storeTime(ctx, obj, &t);
}

// php_date_sub. a weekday or special interval can't be subtracted: the
// methods throw, date_sub() (no method name) warns
fn dtSubOn(ctx: *NativeContext, obj: *PhpObject, args: []const Value) RuntimeError!void {
    return subWith(ctx, obj, args, "DateTime::sub");
}

fn dtiSubOn(ctx: *NativeContext, obj: *PhpObject, args: []const Value) RuntimeError!void {
    return subWith(ctx, obj, args, "DateTimeImmutable::sub");
}

fn subWith(ctx: *NativeContext, obj: *PhpObject, args: []const Value, method: ?[]const u8) RuntimeError!void {
    if (args.len == 0 or args[0] != .object) return;
    const spec = try intervalSpec(ctx, args[0].object);
    if (spec.rel.have_weekday_relative or spec.rel.have_special_relative) {
        const what = "Only non-special relative time specifications are supported for subtraction";
        if (method) |m| {
            const msg = std.fmt.allocPrint(ctx.allocator, "{s}(): {s}", .{ m, what }) catch return error.OutOfMemory;
            defer ctx.allocator.free(msg);
            try ctx.vm.setPendingException("DateInvalidOperationException", msg);
            return error.RuntimeError;
        }
        const msg = std.fmt.allocPrint(ctx.allocator, "date_sub(): {s}", .{what}) catch return error.OutOfMemory;
        defer ctx.allocator.free(msg);
        try ctx.vm.emitWarning(msg);
        return;
    }
    var t = objTime(ctx, obj);
    if (spec.wall) dp.addWall(&t, &spec.rel, spec.invert, -1, parse_db) else dp.sub(&t, &spec.rel, spec.invert, parse_db);
    try storeTime(ctx, obj, &t);
}

fn setDateOn(ctx: *NativeContext, obj: *PhpObject, args: []const Value) RuntimeError!void {
    if (args.len < 3) return;
    const c = wallFields(ctx, obj);
    try obj.set(ctx.allocator, "__timestamp", .{ .int = instantOfWall(ctx, obj, dateToTimestamp(Value.toInt(args[0]), Value.toInt(args[1]), Value.toInt(args[2]), c.hour, c.min, c.sec)) });
}

fn setTimeOn(ctx: *NativeContext, obj: *PhpObject, args: []const Value) RuntimeError!void {
    if (args.len < 2) return;
    const c = wallFields(ctx, obj);
    const sec: i64 = if (args.len >= 3) Value.toInt(args[2]) else 0;
    try obj.set(ctx.allocator, "__timestamp", .{ .int = instantOfWall(ctx, obj, dateToTimestamp(c.year, c.month, c.day, Value.toInt(args[0]), Value.toInt(args[1]), sec)) });
    // the 4th argument is microseconds, and without it they reset to 0
    try obj.set(ctx.allocator, "__microseconds", .{ .int = if (args.len >= 4) Value.toInt(args[3]) else 0 });
}

fn setISODateOn(ctx: *NativeContext, obj: *PhpObject, args: []const Value) RuntimeError!void {
    if (args.len < 2) return;
    const dow = if (args.len >= 3) Value.toInt(args[2]) else 1;
    const c = wallFields(ctx, obj);
    try obj.set(ctx.allocator, "__timestamp", .{ .int = instantOfWall(ctx, obj, isoWeekDateToTimestamp(Value.toInt(args[0]), Value.toInt(args[1]), dow, c.hour, c.min, c.sec)) });
}

fn setTimestampOn(ctx: *NativeContext, obj: *PhpObject, args: []const Value) RuntimeError!void {
    if (args.len < 1) return;
    try obj.set(ctx.allocator, "__timestamp", .{ .int = Value.toInt(args[0]) });
    if (obj.get("__microseconds") != .null) try obj.set(ctx.allocator, "__microseconds", .{ .int = 0 });
}

fn setTimezoneOn(ctx: *NativeContext, obj: *PhpObject, args: []const Value) RuntimeError!void {
    try obj.setCopiedString(ctx.allocator, "__timezone", extractTimezoneName(args));
}

fn setMicrosecondOn(ctx: *NativeContext, obj: *PhpObject, args: []const Value) RuntimeError!void {
    if (args.len >= 1 and args[0] == .int) try obj.set(ctx.allocator, "__microseconds", .{ .int = args[0].int });
}

const dtAdd = mutating(addOn);
const dtSub = mutating(dtSubOn);
const dtSetDate = mutating(setDateOn);
const dtSetTime = mutating(setTimeOn);
const dtSetISODate = mutating(setISODateOn);
const dtSetTimestamp = mutating(setTimestampOn);
const dtSetTimezone = mutating(setTimezoneOn);
const dtSetMicrosecond = mutating(setMicrosecondOn);
const dtiAdd = immutable(addOn);
const dtiSub = immutable(dtiSubOn);
const dtiSetDate = immutable(setDateOn);
const dtiSetTime = immutable(setTimeOn);
const dtiSetISODate = immutable(setISODateOn);
const dtiSetTimestamp = immutable(setTimestampOn);
const dtiSetTimezone = immutable(setTimezoneOn);
const dtiSetMicrosecond = immutable(setMicrosecondOn);

fn objMicros(obj: *PhpObject) i64 {
    const v = obj.get("__microseconds");
    return if (v == .int) v.int else 0;
}

fn dtDiff(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.null);
    const absolute = args.len >= 2 and args[1].isTruthy();
    return diffObjects(ctx, obj, args[0].object, absolute);
}

// timelib_diff over the two objects' wall-clock times
fn diffObjects(ctx: *NativeContext, obj: *PhpObject, other: *PhpObject, absolute: bool) RuntimeError!NativeResult {
    const zone1 = ParseZone.of(objTzName(obj, ctx.vm.default_tz_name), false);
    const zone2 = ParseZone.of(objTzName(other, ctx.vm.default_tz_name), false);
    const one = wallTime(ctx.allocator, getTimestamp(obj), objMicros(obj), &zone1);
    const two = wallTime(ctx.allocator, getTimestamp(other), objMicros(other), &zone2);
    const rt = dp.diff(&one, &two, parse_db);
    const interval = try ctx.createObject("DateInterval");
    try interval.set(ctx.allocator, "y", .{ .int = rt.y });
    try interval.set(ctx.allocator, "m", .{ .int = rt.m });
    try interval.set(ctx.allocator, "d", .{ .int = rt.d });
    try interval.set(ctx.allocator, "days", .{ .int = rt.days });
    try interval.set(ctx.allocator, "h", .{ .int = rt.h });
    try interval.set(ctx.allocator, "i", .{ .int = rt.i });
    try interval.set(ctx.allocator, "s", .{ .int = rt.s });
    try interval.set(ctx.allocator, "f", .{ .float = @as(f64, @floatFromInt(rt.us)) / 1_000_000.0 });
    try interval.set(ctx.allocator, "invert", .{ .int = if (rt.invert and !absolute) 1 else 0 });
    return NativeResult.borrowed(.{ .object = interval });
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

// a float timestamp keeps its sub-second part as microseconds
fn setTimestampWithFraction(ctx: *NativeContext, obj: *PhpObject, ts: Value) !void {
    if (ts == .float) {
        const whole = @floor(ts.float);
        try obj.set(ctx.allocator, "__timestamp", .{ .int = Value.dvalToLval(whole) });
        const micros: i64 = Value.dvalToLval(@round((ts.float - whole) * 1_000_000.0));
        if (micros != 0) try obj.set(ctx.allocator, "__microseconds", .{ .int = micros });
        return;
    }
    try obj.set(ctx.allocator, "__timestamp", .{ .int = Value.toInt(ts) });
}

fn dtCreateFromTimestamp(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.null);
    const obj = try ctx.createObject("DateTime");
    try setTimestampWithFraction(ctx, obj, args[0]);
    return NativeResult.borrowed(.{ .object = obj });
}

fn dtCreateFromFormat(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return createFromFormatImpl(ctx, args, "DateTime", "DateTime::createFromFormat");
}

fn dtCreateFromImmutable(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return convertDateObject(ctx, args, "DateTime");
}

// a DateTime from a DateTimeImmutable or the reverse: same instant, zone, and
// microseconds
fn convertDateObject(ctx: *NativeContext, args: []const Value, class_name: []const u8) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.null);
    const src = args[0].object;
    const obj = try ctx.createObject(class_name);
    try obj.set(ctx.allocator, "__timestamp", src.get("__timestamp"));
    if (src.get("__timezone") == .string) try obj.set(ctx.allocator, "__timezone", src.get("__timezone"));
    if (src.get("__microseconds") == .int) try obj.set(ctx.allocator, "__microseconds", src.get("__microseconds"));
    return NativeResult.borrowed(.{ .object = obj });
}

fn dtiCreateFromMutable(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return convertDateObject(ctx, args, "DateTimeImmutable");
}

// createFromInterface accepts either DateTime or DateTimeImmutable and produces
// the corresponding target type (called as DateTime::createFromInterface or
// DateTimeImmutable::createFromInterface)
fn dtCreateFromInterface(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return dtCreateFromImmutable(ctx, args);
}

fn dtiCreateFromInterface(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return dtiCreateFromMutable(ctx, args);
}

fn native_date_create_from_format(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return createFromFormatImpl(ctx, args, "DateTime", "date_create_from_format");
}

fn native_date_create_immutable_from_format(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return createFromFormatImpl(ctx, args, "DateTimeImmutable", "date_create_immutable_from_format");
}

fn createBareDt(ctx: *NativeContext, class_name: []const u8, args: []const Value) RuntimeError!NativeResult {
    const input: []const u8 = if (args.len >= 1 and args[0] == .string) args[0].string.bytes() else "";
    const instant = (try resolveDate(ctx, input, tzArgName(args, 1), false)) orelse return NativeResult.scalar(.{ .bool = false });
    const obj = try ctx.createObject(class_name);
    try storeInstant(ctx, obj, instant.ts, instant.us, &instant.zone);
    return NativeResult.borrowed(.{ .object = obj });
}

fn native_date_create(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return createBareDt(ctx, "DateTime", args);
}

fn native_date_create_immutable(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return createBareDt(ctx, "DateTimeImmutable", args);
}

fn argObj(args: []const Value) ?*PhpObject {
    if (args.len == 0 or args[0] != .object) return null;
    return args[0].object;
}

fn isImmutable(obj: *PhpObject) bool {
    return std.mem.eql(u8, obj.class_name, "DateTimeImmutable");
}

fn native_date_format(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = argObj(args) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 2 or args[1] != .string) return NativeResult.literal("");
    const ts = getTimestamp(obj);
    const tz_val = obj.get("__timezone");
    const tz_name = if (tz_val == .string) tz_val.string.bytes() else ctx.vm.default_tz_name;
    const offset = tzOffsetForName(ctx.allocator, tz_name, ts);
    return formatTimestampTz(ctx, ts, args[1].string.bytes(), offset, tz_name);
}

// procedural alias for DateInterval::createFromDateString
fn native_date_interval_create_from_date_string(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return intervalFromDateString(ctx, args, false);
}

// procedural alias for DateInterval::format($interval, $format)
fn native_date_interval_format(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .object or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const saved = ctx.vm.currentFrame().vars.get("$this");
    try ctx.vm.putFrameVar(&ctx.vm.currentFrame().vars, "$this", args[0]);
    defer if (saved) |s| (ctx.vm.putFrameVar(&ctx.vm.currentFrame().vars, "$this", s) catch {});
    return diFormat(ctx, args[1..]);
}

fn native_date_modify(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = argObj(args) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 2 or args[1] != .string) return NativeResult.borrowed(.{ .object = obj });
    const target = if (isImmutable(obj)) try cloneDateObject(ctx, obj) else obj;
    if (!try modifyDateObject(ctx, target, args[1].string.bytes(), "date_modify(): ", false)) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.borrowed(.{ .object = target });
}

fn applyIntervalProc(ctx: *NativeContext, args: []const Value, sign: i64) RuntimeError!NativeResult {
    const obj = argObj(args) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 2 or args[1] != .object) return NativeResult.borrowed(.{ .object = obj });
    const target = if (isImmutable(obj)) try cloneDateObject(ctx, obj) else obj;
    if (sign > 0) try addOn(ctx, target, args[1..]) else try subWith(ctx, target, args[1..], null);
    return NativeResult.borrowed(.{ .object = target });
}

fn native_date_add(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return applyIntervalProc(ctx, args, 1);
}

fn native_date_sub(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return applyIntervalProc(ctx, args, -1);
}

fn native_date_diff(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .object or args[1] != .object) return NativeResult.scalar(.{ .bool = false });
    return diffObjects(ctx, args[0].object, args[1].object, args.len >= 3 and args[2].isTruthy());
}

fn native_date_timestamp_get(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = argObj(args) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = getTimestamp(obj) });
}

fn native_date_timestamp_set(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = argObj(args) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 2) return NativeResult.borrowed(.{ .object = obj });
    try obj.set(ctx.allocator, "__timestamp", .{ .int = Value.toInt(args[1]) });
    return NativeResult.borrowed(.{ .object = obj });
}

// a procedural function that is a method of its first argument
// (date_offset_get($d) is $d->getOffset())
fn methodAlias(comptime method: []const u8) fn (*NativeContext, []const Value) RuntimeError!NativeResult {
    return struct {
        fn call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
            if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
            return NativeResult.share(try ctx.vm.callMethod(args[0].object, method, args[1..]));
        }
    }.call;
}

fn native_date_date_set(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = argObj(args) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 4) return NativeResult.borrowed(.{ .object = obj });
    const c = wallFields(ctx, obj);
    const new_ts = instantOfWall(ctx, obj, dateToTimestamp(Value.toInt(args[1]), Value.toInt(args[2]), Value.toInt(args[3]), c.hour, c.min, c.sec));
    try obj.set(ctx.allocator, "__timestamp", .{ .int = new_ts });
    return NativeResult.borrowed(.{ .object = obj });
}

fn native_date_time_set(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = argObj(args) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 3) return NativeResult.borrowed(.{ .object = obj });
    const c = wallFields(ctx, obj);
    const sec: i64 = if (args.len >= 4) Value.toInt(args[3]) else 0;
    const new_ts = instantOfWall(ctx, obj, dateToTimestamp(c.year, c.month, c.day, Value.toInt(args[1]), Value.toInt(args[2]), sec));
    try obj.set(ctx.allocator, "__timestamp", .{ .int = new_ts });
    return NativeResult.borrowed(.{ .object = obj });
}

fn dtiCreateFromFormat(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return createFromFormatImpl(ctx, args, "DateTimeImmutable", "DateTimeImmutable::createFromFormat");
}

// the class a static factory was called on (Carbon::createFromFormat makes a
// Carbon): the static call leaves it on the calling frame, and anything that
// isn't a subclass of the factory's own class is not it
fn staticClass(ctx: *NativeContext, base: []const u8) []const u8 {
    if (ctx.vm.frame_count == 0) return base;
    const called = ctx.vm.currentFrame().called_class orelse return base;
    return if (ctx.vm.isInstanceOf(called, base)) ctx.vm.declaredClassName(called) else base;
}

fn createFromFormatImpl(ctx: *NativeContext, args: []const Value, default_class: []const u8, fn_name: []const u8) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    try rejectNulBytes(ctx, fn_name, 2, "datetime", args[1].string.bytes());

    const class_name = staticClass(ctx, default_class);

    const instant = (try resolveDateWith(ctx, args[1].string.bytes(), args[0].string.bytes(), tzArgName(args, 2), false)) orelse return NativeResult.scalar(.{ .bool = false });
    const obj = try ctx.createObject(class_name);
    try storeInstant(ctx, obj, instant.ts, instant.us, &instant.zone);
    return NativeResult.borrowed(.{ .object = obj });
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}
fn dtiCreateFromTimestamp(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.null);
    const obj = try ctx.createObject("DateTimeImmutable");
    try setTimestampWithFraction(ctx, obj, args[0]);
    return NativeResult.borrowed(.{ .object = obj });
}

fn dtGetMicrosecond(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const v = obj.get("__microseconds");
    if (v == .int) return NativeResult.scalar(v);
    return NativeResult.scalar(.{ .int = 0 });
}

fn dtGetTimezone(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const tz_val = obj.get("__timezone");
    const tz_obj = try ctx.createObject("DateTimeZone");
    try tz_obj.set(ctx.allocator, "__timezone", if (tz_val == .string) tz_val else .{ .string = Value.String.borrowed("UTC") });
    return NativeResult.borrowed(.{ .object = tz_obj });
}

fn dtGetOffset(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const tz_val = obj.get("__timezone");
    const tz_name = if (tz_val == .string) tz_val.string.bytes() else "UTC";
    const ts = getTimestamp(obj);
    return NativeResult.scalar(.{ .int = @intCast(tzOffsetForName(ctx.allocator, tz_name, ts)) });
}

fn extractTimezoneName(args: []const Value) []const u8 {
    if (args.len == 0) return "UTC";
    if (args[0] == .string) return args[0].string.bytes();
    if (args[0] == .object) {
        const tz_val = args[0].object.get("__timezone");
        if (tz_val == .string) return tz_val.string.bytes();
    }
    return "UTC";
}

// Z_PARAM_PATH: php rejects a string argument with a nul byte in it
fn rejectNulBytes(ctx: *NativeContext, fn_name: []const u8, pos: usize, param: []const u8, v: []const u8) RuntimeError!void {
    if (std.mem.indexOfScalar(u8, v, 0) == null) return;
    const msg = std.fmt.allocPrint(ctx.allocator, "{s}(): Argument #{d} (${s}) must not contain any null bytes", .{ fn_name, pos, param }) catch return error.OutOfMemory;
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("ValueError", msg);
    return error.RuntimeError;
}

fn dtzConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len >= 1 and args[0] == .string) {
        try rejectNulBytes(ctx, "DateTimeZone::__construct", 1, "timezone", args[0].string.bytes());
        const zone = (try timezoneInitialize(ctx, args[0].string.bytes(), "DateTimeZone::__construct(): ", true)) orelse return error.RuntimeError;
        try obj.setCopiedString(ctx.allocator, "__timezone", zone.name());
    }
    return NativeResult.scalar(.null);
}

// timezone_initialize: a zone string read the way the date parser reads one,
// so "cest" is the abbreviation CEST, "+0530" the offset +05:30, and anything
// left over makes it a bad timezone
fn timezoneInitialize(ctx: *NativeContext, name: []const u8, prefix: []const u8, throws: bool) RuntimeError!?ParseZone {
    const zp = dp.parseZoneString(name, parse_db);
    var what: ?[]const u8 = null;
    if (zp.time.z >= 100 * 3600 or zp.time.z <= -100 * 3600) {
        what = "Timezone offset is out of range";
    } else if (zp.not_found or zp.rest != 0 or std.mem.indexOfScalar(u8, name, 0) != null) {
        what = "Unknown or bad timezone";
    }
    if (what) |w| {
        const msg = std.fmt.allocPrint(ctx.allocator, "{s}{s} ({s})", .{ prefix, w, name }) catch return error.OutOfMemory;
        defer ctx.allocator.free(msg);
        if (throws) {
            try ctx.vm.setPendingException("DateInvalidTimeZoneException", msg);
        } else {
            try ctx.vm.emitWarning(msg);
        }
        return null;
    }
    return ParseZone.ofTime(&zp.time);
}

fn dtzListIdentifiers(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // full IANA zone list (419 entries) matching PHP 8.4's tzdb snapshot. used
    // for membership checks in user code that whitelists allowed zones; the
    // names themselves are also valid `DateTimeZone` constructor inputs
    const ids = [_][]const u8{
        "Africa/Abidjan",                 "Africa/Accra",                "Africa/Addis_Ababa",
        "Africa/Algiers",                 "Africa/Asmara",               "Africa/Bamako",
        "Africa/Bangui",                  "Africa/Banjul",               "Africa/Bissau",
        "Africa/Blantyre",                "Africa/Brazzaville",          "Africa/Bujumbura",
        "Africa/Cairo",                   "Africa/Casablanca",           "Africa/Ceuta",
        "Africa/Conakry",                 "Africa/Dakar",                "Africa/Dar_es_Salaam",
        "Africa/Djibouti",                "Africa/Douala",               "Africa/El_Aaiun",
        "Africa/Freetown",                "Africa/Gaborone",             "Africa/Harare",
        "Africa/Johannesburg",            "Africa/Juba",                 "Africa/Kampala",
        "Africa/Khartoum",                "Africa/Kigali",               "Africa/Kinshasa",
        "Africa/Lagos",                   "Africa/Libreville",           "Africa/Lome",
        "Africa/Luanda",                  "Africa/Lubumbashi",           "Africa/Lusaka",
        "Africa/Malabo",                  "Africa/Maputo",               "Africa/Maseru",
        "Africa/Mbabane",                 "Africa/Mogadishu",            "Africa/Monrovia",
        "Africa/Nairobi",                 "Africa/Ndjamena",             "Africa/Niamey",
        "Africa/Nouakchott",              "Africa/Ouagadougou",          "Africa/Porto-Novo",
        "Africa/Sao_Tome",                "Africa/Tripoli",              "Africa/Tunis",
        "Africa/Windhoek",                "America/Adak",                "America/Anchorage",
        "America/Anguilla",               "America/Antigua",             "America/Araguaina",
        "America/Argentina/Buenos_Aires", "America/Argentina/Catamarca", "America/Argentina/Cordoba",
        "America/Argentina/Jujuy",        "America/Argentina/La_Rioja",  "America/Argentina/Mendoza",
        "America/Argentina/Rio_Gallegos", "America/Argentina/Salta",     "America/Argentina/San_Juan",
        "America/Argentina/San_Luis",     "America/Argentina/Tucuman",   "America/Argentina/Ushuaia",
        "America/Aruba",                  "America/Asuncion",            "America/Atikokan",
        "America/Bahia",                  "America/Bahia_Banderas",      "America/Barbados",
        "America/Belem",                  "America/Belize",              "America/Blanc-Sablon",
        "America/Boa_Vista",              "America/Bogota",              "America/Boise",
        "America/Cambridge_Bay",          "America/Campo_Grande",        "America/Cancun",
        "America/Caracas",                "America/Cayenne",             "America/Cayman",
        "America/Chicago",                "America/Chihuahua",           "America/Ciudad_Juarez",
        "America/Costa_Rica",             "America/Coyhaique",           "America/Creston",
        "America/Cuiaba",                 "America/Curacao",             "America/Danmarkshavn",
        "America/Dawson",                 "America/Dawson_Creek",        "America/Denver",
        "America/Detroit",                "America/Dominica",            "America/Edmonton",
        "America/Eirunepe",               "America/El_Salvador",         "America/Fort_Nelson",
        "America/Fortaleza",              "America/Glace_Bay",           "America/Goose_Bay",
        "America/Grand_Turk",             "America/Grenada",             "America/Guadeloupe",
        "America/Guatemala",              "America/Guayaquil",           "America/Guyana",
        "America/Halifax",                "America/Havana",              "America/Hermosillo",
        "America/Indiana/Indianapolis",   "America/Indiana/Knox",        "America/Indiana/Marengo",
        "America/Indiana/Petersburg",     "America/Indiana/Tell_City",   "America/Indiana/Vevay",
        "America/Indiana/Vincennes",      "America/Indiana/Winamac",     "America/Inuvik",
        "America/Iqaluit",                "America/Jamaica",             "America/Juneau",
        "America/Kentucky/Louisville",    "America/Kentucky/Monticello", "America/Kralendijk",
        "America/La_Paz",                 "America/Lima",                "America/Los_Angeles",
        "America/Lower_Princes",          "America/Maceio",              "America/Managua",
        "America/Manaus",                 "America/Marigot",             "America/Martinique",
        "America/Matamoros",              "America/Mazatlan",            "America/Menominee",
        "America/Merida",                 "America/Metlakatla",          "America/Mexico_City",
        "America/Miquelon",               "America/Moncton",             "America/Monterrey",
        "America/Montevideo",             "America/Montserrat",          "America/Nassau",
        "America/New_York",               "America/Nome",                "America/Noronha",
        "America/North_Dakota/Beulah",    "America/North_Dakota/Center", "America/North_Dakota/New_Salem",
        "America/Nuuk",                   "America/Ojinaga",             "America/Panama",
        "America/Paramaribo",             "America/Phoenix",             "America/Port-au-Prince",
        "America/Port_of_Spain",          "America/Porto_Velho",         "America/Puerto_Rico",
        "America/Punta_Arenas",           "America/Rankin_Inlet",        "America/Recife",
        "America/Regina",                 "America/Resolute",            "America/Rio_Branco",
        "America/Santarem",               "America/Santiago",            "America/Santo_Domingo",
        "America/Sao_Paulo",              "America/Scoresbysund",        "America/Sitka",
        "America/St_Barthelemy",          "America/St_Johns",            "America/St_Kitts",
        "America/St_Lucia",               "America/St_Thomas",           "America/St_Vincent",
        "America/Swift_Current",          "America/Tegucigalpa",         "America/Thule",
        "America/Tijuana",                "America/Toronto",             "America/Tortola",
        "America/Vancouver",              "America/Whitehorse",          "America/Winnipeg",
        "America/Yakutat",                "Antarctica/Casey",            "Antarctica/Davis",
        "Antarctica/DumontDUrville",      "Antarctica/Macquarie",        "Antarctica/Mawson",
        "Antarctica/McMurdo",             "Antarctica/Palmer",           "Antarctica/Rothera",
        "Antarctica/Syowa",               "Antarctica/Troll",            "Antarctica/Vostok",
        "Arctic/Longyearbyen",            "Asia/Aden",                   "Asia/Almaty",
        "Asia/Amman",                     "Asia/Anadyr",                 "Asia/Aqtau",
        "Asia/Aqtobe",                    "Asia/Ashgabat",               "Asia/Atyrau",
        "Asia/Baghdad",                   "Asia/Bahrain",                "Asia/Baku",
        "Asia/Bangkok",                   "Asia/Barnaul",                "Asia/Beirut",
        "Asia/Bishkek",                   "Asia/Brunei",                 "Asia/Chita",
        "Asia/Colombo",                   "Asia/Damascus",               "Asia/Dhaka",
        "Asia/Dili",                      "Asia/Dubai",                  "Asia/Dushanbe",
        "Asia/Famagusta",                 "Asia/Gaza",                   "Asia/Hebron",
        "Asia/Ho_Chi_Minh",               "Asia/Hong_Kong",              "Asia/Hovd",
        "Asia/Irkutsk",                   "Asia/Jakarta",                "Asia/Jayapura",
        "Asia/Jerusalem",                 "Asia/Kabul",                  "Asia/Kamchatka",
        "Asia/Karachi",                   "Asia/Kathmandu",              "Asia/Khandyga",
        "Asia/Kolkata",                   "Asia/Krasnoyarsk",            "Asia/Kuala_Lumpur",
        "Asia/Kuching",                   "Asia/Kuwait",                 "Asia/Macau",
        "Asia/Magadan",                   "Asia/Makassar",               "Asia/Manila",
        "Asia/Muscat",                    "Asia/Nicosia",                "Asia/Novokuznetsk",
        "Asia/Novosibirsk",               "Asia/Omsk",                   "Asia/Oral",
        "Asia/Phnom_Penh",                "Asia/Pontianak",              "Asia/Pyongyang",
        "Asia/Qatar",                     "Asia/Qostanay",               "Asia/Qyzylorda",
        "Asia/Riyadh",                    "Asia/Sakhalin",               "Asia/Samarkand",
        "Asia/Seoul",                     "Asia/Shanghai",               "Asia/Singapore",
        "Asia/Srednekolymsk",             "Asia/Taipei",                 "Asia/Tashkent",
        "Asia/Tbilisi",                   "Asia/Tehran",                 "Asia/Thimphu",
        "Asia/Tokyo",                     "Asia/Tomsk",                  "Asia/Ulaanbaatar",
        "Asia/Urumqi",                    "Asia/Ust-Nera",               "Asia/Vientiane",
        "Asia/Vladivostok",               "Asia/Yakutsk",                "Asia/Yangon",
        "Asia/Yekaterinburg",             "Asia/Yerevan",                "Atlantic/Azores",
        "Atlantic/Bermuda",               "Atlantic/Canary",             "Atlantic/Cape_Verde",
        "Atlantic/Faroe",                 "Atlantic/Madeira",            "Atlantic/Reykjavik",
        "Atlantic/South_Georgia",         "Atlantic/St_Helena",          "Atlantic/Stanley",
        "Australia/Adelaide",             "Australia/Brisbane",          "Australia/Broken_Hill",
        "Australia/Darwin",               "Australia/Eucla",             "Australia/Hobart",
        "Australia/Lindeman",             "Australia/Lord_Howe",         "Australia/Melbourne",
        "Australia/Perth",                "Australia/Sydney",            "Europe/Amsterdam",
        "Europe/Andorra",                 "Europe/Astrakhan",            "Europe/Athens",
        "Europe/Belgrade",                "Europe/Berlin",               "Europe/Bratislava",
        "Europe/Brussels",                "Europe/Bucharest",            "Europe/Budapest",
        "Europe/Busingen",                "Europe/Chisinau",             "Europe/Copenhagen",
        "Europe/Dublin",                  "Europe/Gibraltar",            "Europe/Guernsey",
        "Europe/Helsinki",                "Europe/Isle_of_Man",          "Europe/Istanbul",
        "Europe/Jersey",                  "Europe/Kaliningrad",          "Europe/Kirov",
        "Europe/Kyiv",                    "Europe/Lisbon",               "Europe/Ljubljana",
        "Europe/London",                  "Europe/Luxembourg",           "Europe/Madrid",
        "Europe/Malta",                   "Europe/Mariehamn",            "Europe/Minsk",
        "Europe/Monaco",                  "Europe/Moscow",               "Europe/Oslo",
        "Europe/Paris",                   "Europe/Podgorica",            "Europe/Prague",
        "Europe/Riga",                    "Europe/Rome",                 "Europe/Samara",
        "Europe/San_Marino",              "Europe/Sarajevo",             "Europe/Saratov",
        "Europe/Simferopol",              "Europe/Skopje",               "Europe/Sofia",
        "Europe/Stockholm",               "Europe/Tallinn",              "Europe/Tirane",
        "Europe/Ulyanovsk",               "Europe/Vaduz",                "Europe/Vatican",
        "Europe/Vienna",                  "Europe/Vilnius",              "Europe/Volgograd",
        "Europe/Warsaw",                  "Europe/Zagreb",               "Europe/Zurich",
        "Indian/Antananarivo",            "Indian/Chagos",               "Indian/Christmas",
        "Indian/Cocos",                   "Indian/Comoro",               "Indian/Kerguelen",
        "Indian/Mahe",                    "Indian/Maldives",             "Indian/Mauritius",
        "Indian/Mayotte",                 "Indian/Reunion",              "Pacific/Apia",
        "Pacific/Auckland",               "Pacific/Bougainville",        "Pacific/Chatham",
        "Pacific/Chuuk",                  "Pacific/Easter",              "Pacific/Efate",
        "Pacific/Fakaofo",                "Pacific/Fiji",                "Pacific/Funafuti",
        "Pacific/Galapagos",              "Pacific/Gambier",             "Pacific/Guadalcanal",
        "Pacific/Guam",                   "Pacific/Honolulu",            "Pacific/Kanton",
        "Pacific/Kiritimati",             "Pacific/Kosrae",              "Pacific/Kwajalein",
        "Pacific/Majuro",                 "Pacific/Marquesas",           "Pacific/Midway",
        "Pacific/Nauru",                  "Pacific/Niue",                "Pacific/Norfolk",
        "Pacific/Noumea",                 "Pacific/Pago_Pago",           "Pacific/Palau",
        "Pacific/Pitcairn",               "Pacific/Pohnpei",             "Pacific/Port_Moresby",
        "Pacific/Rarotonga",              "Pacific/Saipan",              "Pacific/Tahiti",
        "Pacific/Tarawa",                 "Pacific/Tongatapu",           "Pacific/Wake",
        "Pacific/Wallis",                 "UTC",
    };
    var arr = try ctx.createArray();
    for (ids) |id| try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(id) });
    return NativeResult.borrowed(.{ .array = arr });
}

fn dtzListAbbreviations(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
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
            const key = try Value.String.create(ctx.allocator, key_buf[0..z.std_abbrev.len]);
            defer key.release();
            const canonical = try canonicalizeZoneName(ctx, z.name);
            defer canonical.release();
            try appendAbbrevEntry(ctx, arr, key, false, z.std_offset, canonical);
        }
        // emit dst side only when distinct
        if (z.dst_rule != .none and z.dst_abbrev.len > 0 and !std.mem.eql(u8, z.std_abbrev, z.dst_abbrev) and z.dst_abbrev.len < key_buf.len) {
            for (z.dst_abbrev, 0..) |c, i| key_buf[i] = std.ascii.toLower(c);
            const key = try Value.String.create(ctx.allocator, key_buf[0..z.dst_abbrev.len]);
            defer key.release();
            const canonical = try canonicalizeZoneName(ctx, z.name);
            defer canonical.release();
            try appendAbbrevEntry(ctx, arr, key, true, z.dst_offset, canonical);
        }
    }
    // the single-letter military timezones (RFC 822 / NATO phonetic). these are
    // fixed by definition, not derived from the tz database, so they're stable
    // across tzdb versions. PHP lists each with a null timezone_id. 'j' (local)
    // is intentionally absent. the multi-letter historical abbreviations PHP
    // also returns are intentionally NOT fully reproduced here: that set is
    // coupled to PHP's bundled timezonedb version (per-abbreviation zone lists
    // shift across releases), so chasing byte-for-byte parity would be brittle
    // for a near-unused function - treated as implementation-defined
    const military = [_]struct { c: u8, off: i32 }{
        .{ .c = 'a', .off = 3600 },   .{ .c = 'b', .off = 7200 },   .{ .c = 'c', .off = 10800 },
        .{ .c = 'd', .off = 14400 },  .{ .c = 'e', .off = 18000 },  .{ .c = 'f', .off = 21600 },
        .{ .c = 'g', .off = 25200 },  .{ .c = 'h', .off = 28800 },  .{ .c = 'i', .off = 32400 },
        .{ .c = 'k', .off = 36000 },  .{ .c = 'l', .off = 39600 },  .{ .c = 'm', .off = 43200 },
        .{ .c = 'n', .off = -3600 },  .{ .c = 'o', .off = -7200 },  .{ .c = 'p', .off = -10800 },
        .{ .c = 'q', .off = -14400 }, .{ .c = 'r', .off = -18000 }, .{ .c = 's', .off = -21600 },
        .{ .c = 't', .off = -25200 }, .{ .c = 'u', .off = -28800 }, .{ .c = 'v', .off = -32400 },
        .{ .c = 'w', .off = -36000 }, .{ .c = 'x', .off = -39600 }, .{ .c = 'y', .off = -43200 },
        .{ .c = 'z', .off = 0 },
    };
    for (military) |m| {
        if (arr.get(.{ .string = Value.String.borrowed(&[_]u8{m.c}) }) != .null) continue;
        const key = try Value.String.create(ctx.allocator, &[_]u8{m.c});
        defer key.release();
        const list = try ctx.createArray();
        const entry = try ctx.createArray();
        try entry.set(ctx.allocator, .{ .string = Value.String.borrowed("dst") }, .{ .bool = false });
        try entry.set(ctx.allocator, .{ .string = Value.String.borrowed("offset") }, .{ .int = @as(i64, m.off) });
        try entry.set(ctx.allocator, .{ .string = Value.String.borrowed("timezone_id") }, .null);
        try list.append(ctx.allocator, .{ .array = entry });
        try arr.set(ctx.allocator, .{ .string = key }, .{ .array = list });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn canonicalizeZoneName(ctx: *NativeContext, lower_name: []const u8) !Value.String {
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
    return Value.String.adopt(ctx.allocator, out);
}

fn appendAbbrevEntry(ctx: *NativeContext, outer: *@import("../runtime/value.zig").PhpArray, key: Value.String, dst: bool, offset: i32, tz_id: Value.String) !void {
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
    try entry.set(ctx.allocator, .{ .string = Value.String.borrowed("dst") }, .{ .bool = dst });
    try entry.set(ctx.allocator, .{ .string = Value.String.borrowed("offset") }, .{ .int = @as(i64, offset) });
    try entry.set(ctx.allocator, .{ .string = Value.String.borrowed("timezone_id") }, .{ .string = tz_id });
    try list.append(ctx.allocator, .{ .array = entry });
}

fn dtzGetName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.literal("UTC");
    const tz_val = obj.get("__timezone");
    return if (tz_val == .string) NativeResult.shareString(tz_val.string) else NativeResult.literal("UTC");
}

fn dtzGetOffset(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const tz_val = obj.get("__timezone");
    const tz_name = if (tz_val == .string) tz_val.string.bytes() else "UTC";

    // getOffset takes a DateTime argument for DST calculation
    var ref_ts: i64 = platform.timestamp();
    if (args.len >= 1 and args[0] == .object) {
        ref_ts = getTimestamp(args[0].object);
    }

    return NativeResult.scalar(.{ .int = @intCast(tzOffsetForName(ctx.allocator, tz_name, ref_ts)) });
}

// PHP's getLocation returns {country_code, latitude, longitude, comments}
// for named tz, and false for offset-only zones. zphp doesn't ship the IANA
// tzdata, so named zones return placeholder data with the right structure
fn dtzGetLocation(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const tz_val = obj.get("__timezone");
    const tz_name = if (tz_val == .string) tz_val.string.bytes() else "UTC";
    // offset-only zones report false
    if (tz_name.len > 0 and (tz_name[0] == '+' or tz_name[0] == '-')) return NativeResult.scalar(.{ .bool = false });
    const arr = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("country_code") }, .{ .string = Value.String.borrowed("??") });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("latitude") }, .{ .float = 0.0 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("longitude") }, .{ .float = 0.0 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("comments") }, .{ .string = Value.String.borrowed("") });
    return NativeResult.borrowed(.{ .array = arr });
}

// stub that returns an empty list - we don't track historical transitions
fn dtzGetTransitions(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.borrowed(.{ .array = try ctx.createArray() });
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

fn native_date(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.literal("");
    const format = args[0].string.bytes();
    const timestamp: i64 = if (args.len >= 2) Value.toInt(args[1]) else platform.timestamp();
    return formatTimestamp(ctx, timestamp, format);
}

fn native_mktime(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const hour: i64 = if (args.len > 0) Value.toInt(args[0]) else 0;
    const min: i64 = if (args.len > 1) Value.toInt(args[1]) else 0;
    const sec: i64 = if (args.len > 2) Value.toInt(args[2]) else 0;
    const month: i64 = if (args.len > 3) Value.toInt(args[3]) else 1;
    const day: i64 = if (args.len > 4) Value.toInt(args[4]) else 1;
    const year: i64 = if (args.len > 5) Value.toInt(args[5]) else 1970;
    var ts = dateToTimestamp(year, month, day, hour, min, sec);
    ts -= @as(i64, tzOffsetForWallByName(ctx.allocator, ctx.vm.default_tz_name, ts));
    return NativeResult.scalar(.{ .int = ts });
}

fn native_gmmktime(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const hour: i64 = if (args.len > 0) Value.toInt(args[0]) else 0;
    const min: i64 = if (args.len > 1) Value.toInt(args[1]) else 0;
    const sec: i64 = if (args.len > 2) Value.toInt(args[2]) else 0;
    const month: i64 = if (args.len > 3) Value.toInt(args[3]) else 1;
    const day: i64 = if (args.len > 4) Value.toInt(args[4]) else 1;
    const year: i64 = if (args.len > 5) Value.toInt(args[5]) else 1970;
    return NativeResult.scalar(.{ .int = dateToTimestamp(year, month, day, hour, min, sec) });
}

fn native_strtotime(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const input = args[0].string.bytes();
    if (input.len == 0) return NativeResult.scalar(.{ .bool = false });
    const base: i64 = if (args.len >= 2 and args[1] != .null) Value.toInt(args[1]) else platform.timestamp();
    const ts = (try strtotimeIn(ctx, input, base)) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = ts });
}

fn native_time(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = platform.timestamp() });
}

fn native_checkdate(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 3) return NativeResult.scalar(.{ .bool = false });
    const month = Value.toInt(args[0]);
    const day = Value.toInt(args[1]);
    const year = Value.toInt(args[2]);
    if (year < 1 or year > 32767 or month < 1 or month > 12 or day < 1) return NativeResult.scalar(.{ .bool = false });
    const days_in_month = [_]i64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var max_day = days_in_month[@intCast(month - 1)];
    if (month == 2) {
        const y: u32 = @intCast(year);
        if (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)) max_day = 29;
    }
    return NativeResult.scalar(.{ .bool = day <= max_day });
}

fn native_cal_days_in_month(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // cal_days_in_month($calendar, $month, $year). only CAL_GREGORIAN (0) is
    // commonly used; zphp treats every calendar id as Gregorian
    if (args.len < 3) return NativeResult.scalar(.{ .bool = false });
    const month = Value.toInt(args[1]);
    const year = Value.toInt(args[2]);
    if (month < 1 or month > 12) {
        try ctx.vm.setPendingException("ValueError", "Invalid date");
        return error.RuntimeError;
    }
    return NativeResult.scalar(.{ .int = daysInMonth(month, year) });
}

fn native_date_parse(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    var p = try parseDate(ctx, args[0].string.bytes());
    defer p.deinit(ctx.allocator);
    return parsedTimeArray(ctx, &p);
}

fn native_date_parse_from_format(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    try rejectNulBytes(ctx, "date_parse_from_format", 2, "datetime", args[1].string.bytes());
    var p = dp.parseFromFormat(ctx.allocator, args[0].string.bytes(), args[1].string.bytes(), parse_db) catch return error.OutOfMemory;
    defer p.deinit(ctx.allocator);
    return parsedTimeArray(ctx, &p);
}

fn native_getdate(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const timestamp: i64 = if (args.len >= 1 and args[0] != .null) Value.toInt(args[0]) else platform.timestamp();
    const lp = localParts(ctx.allocator, timestamp, ctx.vm.default_tz_name);
    const weekdays = [_][]const u8{ "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" };
    const months = [_][]const u8{ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };

    var arr = try ctx.createArray();
    const ints = [_]struct { []const u8, i64 }{
        .{ "seconds", lp.dc.sec },
        .{ "minutes", lp.dc.min },
        .{ "hours", lp.dc.hour },
        .{ "mday", lp.dc.day },
        .{ "wday", lp.dow },
        .{ "mon", lp.dc.month },
        .{ "year", lp.dc.year },
        .{ "yday", lp.yday },
    };
    for (ints) |f| try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(f[0]) }, .{ .int = f[1] });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("weekday") }, .{ .string = Value.String.borrowed(weekdays[@intCast(lp.dow)]) });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("month") }, .{ .string = Value.String.borrowed(months[@intCast(lp.dc.month - 1)]) });
    try arr.set(ctx.allocator, .{ .int = 0 }, .{ .int = timestamp });
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_hrtime(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const as_int = args.len >= 1 and args[0].isTruthy();
    const ns = platform.nanoTimestamp();
    if (as_int) {
        return NativeResult.scalar(.{ .int = @intCast(ns) });
    }
    const secs: i64 = @intCast(@divTrunc(ns, 1_000_000_000));
    const remainder: i64 = @intCast(@mod(ns, 1_000_000_000));
    var arr = try ctx.createArray();
    try arr.append(ctx.allocator, .{ .int = secs });
    try arr.append(ctx.allocator, .{ .int = remainder });
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_microtime(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const as_float = args.len >= 1 and args[0].isTruthy();
    const ns = platform.nanoTimestamp();
    if (as_float) {
        const secs: f64 = @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
        return NativeResult.scalar(.{ .float = secs });
    }
    const ts: i64 = @intCast(@divTrunc(ns, 1_000_000_000));
    const usec: i64 = @intCast(@divTrunc(@mod(ns, 1_000_000_000), 1_000));
    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);
    var tmp: [32]u8 = undefined;
    try buf.appendSlice(ctx.allocator, "0.");
    const usec_str = std.fmt.bufPrint(&tmp, "{d:0>6}", .{@as(u64, @intCast(if (usec < 0) -usec else usec))}) catch "000000";
    try buf.appendSlice(ctx.allocator, usec_str);
    try buf.appendSlice(ctx.allocator, " ");
    const ts_str = std.fmt.bufPrint(&tmp, "{d}", .{ts}) catch "0";
    try buf.appendSlice(ctx.allocator, ts_str);
    const result = try buf.toOwnedSlice(ctx.allocator);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result));
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

const DateComponents = struct { year: i64, month: i64, day: i64, hour: i64, min: i64, sec: i64 };

const FmtDaySec = struct {
    h: u32,
    mi: u32,
    s: u32,
    pub fn getHoursIntoDay(self: @This()) u32 {
        return self.h;
    }
    pub fn getMinutesIntoHour(self: @This()) u32 {
        return self.mi;
    }
    pub fn getSecondsIntoMinute(self: @This()) u32 {
        return self.s;
    }
};
const FmtEpochDay = struct { day: i64 };
const FmtYearDay = struct { year: i64 };
const FmtMonth = struct {
    v: u32,
    pub fn numeric(s: @This()) u32 {
        return s.v;
    }
};
const FmtMonthDay = struct { month: FmtMonth, day_index: u32 };

const IsoWeek = struct { year: i64, week: u32 };

fn isoWeek(day_num: i64) IsoWeek {
    // iso 8601 week-numbering: week 1 contains the year's first Thursday.
    // the iso year is the calendar year of the Thursday in the same week.
    // counted in days, so the extreme years php can hold don't overflow
    const dow = @mod(@mod(day_num, 7) + 3, 7); // 0 is monday; 1970-01-01 was a thursday
    const thu = day_num +% 3 -% dow;
    var t = dp.Time{ .m = 1, .d = 1 };
    var m: i64 = 0;
    var d: i64 = 0;
    dp.dateFromEpochDays(thu, &t.y, &m, &d);
    const jan1_day = dp.epochDaysFromTime(&t);
    const week_num: u32 = @intCast(@divFloor(thu -% jan1_day, 7) + 1);
    return .{ .year = t.y, .week = week_num };
}

fn baseComponents(base: i64) DateComponents {
    // Howard Hinnant's civil_from_days, works for any year including pre-1970
    // seconds-of-day in [0,86400); @mod keeps the extreme timestamps from
    // overflowing days * 86400
    const days = @divFloor(base, 86400);
    const sod: i64 = @mod(base, 86400);
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

fn eqlLower(a: []const u8, lower_b: []const u8) bool {
    if (a.len != lower_b.len) return false;
    for (a, lower_b) |ca, cb| {
        const la: u8 = if (ca >= 'A' and ca <= 'Z') ca + 32 else ca;
        if (la != cb) return false;
    }
    return true;
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

const DstRule = enum { none, us, eu, au, nz };

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
    .{ .name = "america/sao_paulo", .std_offset = -3 * 3600, .dst_offset = -3 * 3600, .dst_rule = .none, .std_abbrev = "-03", .dst_abbrev = "-03" },
    .{ .name = "america/argentina/buenos_aires", .std_offset = -3 * 3600, .dst_offset = -3 * 3600, .dst_rule = .none, .std_abbrev = "-03", .dst_abbrev = "-03" },
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
    .{ .name = "europe/istanbul", .std_offset = 3 * 3600, .dst_offset = 3 * 3600, .dst_rule = .none, .std_abbrev = "+03", .dst_abbrev = "+03" },
    .{ .name = "europe/athens", .std_offset = 2 * 3600, .dst_offset = 3 * 3600, .dst_rule = .eu, .std_abbrev = "EET", .dst_abbrev = "EEST" },
    .{ .name = "europe/helsinki", .std_offset = 2 * 3600, .dst_offset = 3 * 3600, .dst_rule = .eu, .std_abbrev = "EET", .dst_abbrev = "EEST" },
    .{ .name = "europe/bucharest", .std_offset = 2 * 3600, .dst_offset = 3 * 3600, .dst_rule = .eu, .std_abbrev = "EET", .dst_abbrev = "EEST" },
    .{ .name = "europe/lisbon", .std_offset = 0, .dst_offset = 3600, .dst_rule = .eu, .std_abbrev = "WET", .dst_abbrev = "WEST" },
    .{ .name = "europe/warsaw", .std_offset = 3600, .dst_offset = 2 * 3600, .dst_rule = .eu, .std_abbrev = "CET", .dst_abbrev = "CEST" },
    // asia
    .{ .name = "asia/tokyo", .std_offset = 9 * 3600, .dst_offset = 9 * 3600, .dst_rule = .none, .std_abbrev = "JST", .dst_abbrev = "JST" },
    .{ .name = "asia/shanghai", .std_offset = 8 * 3600, .dst_offset = 8 * 3600, .dst_rule = .none, .std_abbrev = "CST", .dst_abbrev = "CST" },
    .{ .name = "asia/hong_kong", .std_offset = 8 * 3600, .dst_offset = 8 * 3600, .dst_rule = .none, .std_abbrev = "HKT", .dst_abbrev = "HKT" },
    .{ .name = "asia/singapore", .std_offset = 8 * 3600, .dst_offset = 8 * 3600, .dst_rule = .none, .std_abbrev = "+08", .dst_abbrev = "+08" },
    .{ .name = "asia/kolkata", .std_offset = 5 * 3600 + 1800, .dst_offset = 5 * 3600 + 1800, .dst_rule = .none, .std_abbrev = "IST", .dst_abbrev = "IST" },
    .{ .name = "asia/dubai", .std_offset = 4 * 3600, .dst_offset = 4 * 3600, .dst_rule = .none, .std_abbrev = "+04", .dst_abbrev = "+04" },
    .{ .name = "asia/seoul", .std_offset = 9 * 3600, .dst_offset = 9 * 3600, .dst_rule = .none, .std_abbrev = "KST", .dst_abbrev = "KST" },
    .{ .name = "asia/bangkok", .std_offset = 7 * 3600, .dst_offset = 7 * 3600, .dst_rule = .none, .std_abbrev = "+07", .dst_abbrev = "+07" },
    .{ .name = "asia/jakarta", .std_offset = 7 * 3600, .dst_offset = 7 * 3600, .dst_rule = .none, .std_abbrev = "WIB", .dst_abbrev = "WIB" },
    .{ .name = "asia/tehran", .std_offset = 3 * 3600 + 1800, .dst_offset = 3 * 3600 + 1800, .dst_rule = .none, .std_abbrev = "+0330", .dst_abbrev = "+0330" },
    .{ .name = "asia/karachi", .std_offset = 5 * 3600, .dst_offset = 5 * 3600, .dst_rule = .none, .std_abbrev = "PKT", .dst_abbrev = "PKT" },
    .{ .name = "asia/dhaka", .std_offset = 6 * 3600, .dst_offset = 6 * 3600, .dst_rule = .none, .std_abbrev = "+06", .dst_abbrev = "+06" },
    .{ .name = "asia/kathmandu", .std_offset = 5 * 3600 + 2700, .dst_offset = 5 * 3600 + 2700, .dst_rule = .none, .std_abbrev = "+0545", .dst_abbrev = "+0545" },
    // oceania
    .{ .name = "australia/sydney", .std_offset = 10 * 3600, .dst_offset = 11 * 3600, .dst_rule = .au, .std_abbrev = "AEST", .dst_abbrev = "AEDT" },
    .{ .name = "australia/melbourne", .std_offset = 10 * 3600, .dst_offset = 11 * 3600, .dst_rule = .au, .std_abbrev = "AEST", .dst_abbrev = "AEDT" },
    .{ .name = "australia/hobart", .std_offset = 10 * 3600, .dst_offset = 11 * 3600, .dst_rule = .au, .std_abbrev = "AEST", .dst_abbrev = "AEDT" },
    .{ .name = "australia/brisbane", .std_offset = 10 * 3600, .dst_offset = 10 * 3600, .dst_rule = .none, .std_abbrev = "AEST", .dst_abbrev = "AEST" },
    .{ .name = "australia/perth", .std_offset = 8 * 3600, .dst_offset = 8 * 3600, .dst_rule = .none, .std_abbrev = "AWST", .dst_abbrev = "AWST" },
    .{ .name = "pacific/auckland", .std_offset = 12 * 3600, .dst_offset = 13 * 3600, .dst_rule = .nz, .std_abbrev = "NZST", .dst_abbrev = "NZDT" },
    // africa
    // africa/cairo intentionally NOT tabled: Egypt's DST is irregular (announced
    // yearly, Fri/Thu transitions - not a Sunday rule), so it resolves via TZif
    // for correctness (the old .none entry was wrong every summer: +02 not +03)
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

// ---- TZif (system zoneinfo) fallback for zones not in the hardcoded table ----
// parses /usr/share/zoneinfo/<Zone> (the IANA tzdb binary) to give correct
// offsets/DST/abbreviations/historical transitions for ANY zone. the hardcoded
// table is tried first (fast, no I/O, works where zoneinfo is absent e.g. musl);
// this only runs for zones the table doesn't cover.

const TzifRes = struct { offset: i32, is_dst: bool, abbrev_buf: [16]u8 = undefined, abbrev_len: u8 = 0 };

fn tzNameValid(name: []const u8) bool {
    if (name.len == 0 or name.len > 64) return false;
    if (name[0] == '/' or name[0] == '+' or name[0] == '-') return false;
    if (std.mem.indexOf(u8, name, "..") != null) return false;
    for (name) |c| {
        if (!(std.ascii.isAlphanumeric(c) or c == '/' or c == '_' or c == '-' or c == '+')) return false;
    }
    return true;
}

fn readZoneInfo(allocator: Allocator, name: []const u8) ?[]u8 {
    if (!tzNameValid(name)) return null;
    const dirs = [_][]const u8{ "/usr/share/zoneinfo/", "/etc/zoneinfo/", "/usr/lib/zoneinfo/", "/usr/share/lib/zoneinfo/" };
    for (dirs) |dir| {
        var pathbuf: [320]u8 = undefined;
        const path = std.fmt.bufPrint(&pathbuf, "{s}{s}", .{ dir, name }) catch continue;
        const file = std.Io.Dir.openFileAbsolute(platform.io, path, .{}) catch continue;
        defer file.close(platform.io);
        const data = platform.readToEndAlloc(file, allocator, 1 << 20) catch continue;
        return data;
    }
    return null;
}

// embedded IANA tzdb, used when the host has no /usr/share/zoneinfo (musl /
// Alpine). bundles the TZif bytes for the zones zphp advertises via
// timezone_identifiers_list(). regenerate with scripts/gen-tzdata. format:
// "ZTZ1" | u32 count | { u16 name_len, name, u32 data_len, tzif_bytes }*
const tzdata_gz = @embedFile("tzdata.bin.gz");

// the decompressed blob lives for the process lifetime (read-only after init),
// so it's allocated from the page allocator rather than a request arena and
// never freed. guarded so concurrent first-touch in threaded serve workers
// can't double-decompress
var g_tz_mutex: sync.Mutex = .{};
var g_tz_blob: ?[]const u8 = null;
var g_tz_init = false;

fn inflateGzipPage(input: []const u8) ?[]u8 {
    var stream: zlib.z_stream = std.mem.zeroes(zlib.z_stream);
    // 15 window bits + 16 selects gzip framing
    if (zlib.inflateInit2_(&stream, 15 + 16, zlib.zlibVersion(), @sizeOf(zlib.z_stream)) != zlib.Z_OK) return null;
    defer _ = zlib.inflateEnd(&stream);
    const a = std.heap.page_allocator;
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(a);
    stream.next_in = @constCast(input.ptr);
    stream.avail_in = @intCast(input.len);
    var chunk: [32 * 1024]u8 = undefined;
    while (true) {
        stream.next_out = &chunk;
        stream.avail_out = chunk.len;
        const rc = zlib.inflate(&stream, zlib.Z_NO_FLUSH);
        const produced = chunk.len - stream.avail_out;
        if (produced > 0) out.appendSlice(a, chunk[0..produced]) catch return null;
        if (rc == zlib.Z_STREAM_END) break;
        if (rc != zlib.Z_OK) return null;
        if (stream.avail_in == 0 and produced == 0) break;
    }
    return out.toOwnedSlice(a) catch null;
}

fn embeddedBlob() ?[]const u8 {
    g_tz_mutex.lock();
    defer g_tz_mutex.unlock();
    if (g_tz_init) return g_tz_blob;
    g_tz_init = true;
    g_tz_blob = inflateGzipPage(tzdata_gz);
    return g_tz_blob;
}

// borrowed TZif bytes for `name` from the embedded blob (valid for the process
// lifetime, never freed), or null. exact-case match, mirroring readZoneInfo's
// case-sensitive path lookup
fn embeddedZoneInfo(name: []const u8) ?[]const u8 {
    const z = embeddedZone(name, false) orelse return null;
    return z.data;
}

// zone ids match case-insensitively, as in php ("america/new_york")
fn embeddedZone(name: []const u8, ignore_case: bool) ?struct { name: []const u8, data: []const u8 } {
    if (!tzNameValid(name)) return null;
    const blob = embeddedBlob() orelse return null;
    if (blob.len < 8 or !std.mem.eql(u8, blob[0..4], "ZTZ1")) return null;
    var off: usize = 4;
    const count = std.mem.readInt(u32, blob[off..][0..4], .little);
    off += 4;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        if (off + 2 > blob.len) return null;
        const nl = std.mem.readInt(u16, blob[off..][0..2], .little);
        off += 2;
        if (off + nl + 4 > blob.len) return null;
        const ename = blob[off .. off + nl];
        off += nl;
        const dl = std.mem.readInt(u32, blob[off..][0..4], .little);
        off += 4;
        if (off + dl > blob.len) return null;
        const data = blob[off .. off + dl];
        off += dl;
        const hit = if (ignore_case) std.ascii.eqlIgnoreCase(ename, name) else std.mem.eql(u8, ename, name);
        if (hit) return .{ .name = ename, .data = data };
    }
    return null;
}

// TZif bytes for a zone: system zoneinfo first (owned, must be freed), then the
// embedded blob (borrowed, must NOT be freed). centralizes the system-then-
// embedded fallback so every call site handles ownership uniformly
const TzBytes = struct {
    bytes: []const u8,
    owned: bool,
    fn deinit(self: TzBytes, allocator: Allocator) void {
        if (self.owned) allocator.free(@constCast(self.bytes));
    }
};

// zone files are read once per process: tzdata does not change while zphp
// runs and every date() call in a timezone-aware app would otherwise reopen
// /usr/share/zoneinfo/<name>. entries are keyed by the requested name and
// never freed (a few KB per distinct zone); the mutex covers threaded serve
var zone_cache: std.StringHashMapUnmanaged([]const u8) = .{};
var zone_cache_mutex: sync.Mutex = .{};

// the zone this thread resolved last; cached bytes are never freed, so a hit
// skips the shared lock and hash lookup that date code repeats per call
threadlocal var last_zone_name: [64]u8 = undefined;
threadlocal var last_zone_len: usize = 0;
threadlocal var last_zone_bytes: []const u8 = &.{};

fn resolveTzif(allocator: Allocator, name: []const u8) ?TzBytes {
    if (last_zone_len > 0 and std.mem.eql(u8, name, last_zone_name[0..last_zone_len])) return .{ .bytes = last_zone_bytes, .owned = false };
    zone_cache_mutex.lock();
    defer zone_cache_mutex.unlock();
    if (zone_cache.get(name)) |b| {
        if (name.len <= last_zone_name.len) {
            @memcpy(last_zone_name[0..name.len], name);
            last_zone_len = name.len;
            last_zone_bytes = b;
        }
        return .{ .bytes = b, .owned = false };
    }
    const bytes: []const u8 = readZoneInfo(std.heap.page_allocator, name) orelse embeddedZoneInfo(name) orelse blk: {
        // a differently-cased id resolves through its canonical spelling
        const z = embeddedZone(name, true) orelse return null;
        break :blk readZoneInfo(std.heap.page_allocator, z.name) orelse z.data;
    };
    const key = std.heap.page_allocator.dupe(u8, name) catch return .{ .bytes = bytes, .owned = false };
    zone_cache.put(std.heap.page_allocator, key, bytes) catch {};
    _ = allocator;
    return .{ .bytes = bytes, .owned = false };
}

test "embedded tzdata resolves non-table zones without system zoneinfo" {
    // exercises the musl/Alpine fallback path directly: decompress the embedded
    // blob, find the zone, parse its TZif. independent of the host filesystem so
    // it proves the fallback works where /usr/share/zoneinfo is absent.
    // 2026-01-01T00:00:00Z (well clear of any DST edge for these zones)
    const ts: i64 = 1767225600;

    // Kathmandu is the canonical odd offset: +5:45, no DST
    const kt = embeddedZoneInfo("Asia/Kathmandu") orelse return error.ZoneMissing;
    const ktr = tzifLookupUtc(kt, ts) orelse return error.TzifParseFailed;
    try std.testing.expectEqual(@as(i32, 5 * 3600 + 45 * 60), ktr.offset);

    // Chatham: +12:45 standard (NZ summer DST in January -> +13:45)
    const ch = embeddedZoneInfo("Pacific/Chatham") orelse return error.ZoneMissing;
    const chr = tzifLookupUtc(ch, ts) orelse return error.TzifParseFailed;
    try std.testing.expectEqual(@as(i32, 13 * 3600 + 45 * 60), chr.offset);

    // a zone that lives in the hardcoded table is still present in the blob
    const ny = embeddedZoneInfo("America/New_York") orelse return error.ZoneMissing;
    const nyr = tzifLookupUtc(ny, ts) orelse return error.TzifParseFailed;
    try std.testing.expectEqual(@as(i32, -5 * 3600), nyr.offset); // EST in January

    // bogus names resolve to nothing
    try std.testing.expect(embeddedZoneInfo("Not/AReal_Zone") == null);
}

fn firstNonDstType(bytes: []const u8, ttinfo_off: usize, typecnt: usize) u8 {
    var t: usize = 0;
    while (t < typecnt) : (t += 1) {
        if (bytes[ttinfo_off + t * 6 + 4] == 0) return @intCast(t);
    }
    return 0;
}

// ---- the TZif footer: a posix TZ rule ("EST5EDT,M3.2.0,M11.1.0") that
// governs every instant after the last listed transition (parse_posix.c) ----

const PosixSpec = struct {
    kind: enum { julian_no_feb29, julian_feb29, mwd } = .julian_feb29,
    days: i64 = 0,
    month: i64 = 0,
    week: i64 = 0,
    dow: i64 = 0,
    hour: i64 = 7200,
};

const PosixRule = struct {
    std_name: []const u8,
    std_offset: i64,
    dst_name: []const u8 = "",
    dst_offset: i64 = 0,
    begin: ?PosixSpec = null,
    end: ?PosixSpec = null,
};

const PosixReader = struct {
    s: []const u8,
    i: usize = 0,

    fn c(r: *const PosixReader) u8 {
        return if (r.i < r.s.len) r.s[r.i] else 0;
    }

    fn description(r: *PosixReader) ?[]const u8 {
        if (r.c() == '<') {
            r.i += 1;
            const begin = r.i;
            while (r.c() != 0 and r.c() != '>') r.i += 1;
            if (r.c() == 0) return null;
            const name = r.s[begin..r.i];
            r.i += 1;
            return if (name.len < 1) null else name;
        }
        const begin = r.i;
        while (std.ascii.isAlphabetic(r.c())) r.i += 1;
        return if (r.i == begin) null else r.s[begin..r.i];
    }

    fn number(r: *PosixReader) ?i64 {
        const begin = r.i;
        var acc: i64 = 0;
        while (std.ascii.isDigit(r.c())) {
            acc = acc *% 10 +% (r.c() - '0');
            r.i += 1;
        }
        return if (r.i == begin) null else acc;
    }

    // "5", "-3:30", "+2:00:15" read as a utc offset, which is the negation
    fn offset(r: *PosixReader) ?i64 {
        var bias: i64 = 1;
        if (r.c() == '+') {
            r.i += 1;
        } else if (r.c() == '-') {
            bias = -1;
            r.i += 1;
        }
        const hours = r.number() orelse return null;
        var minutes: i64 = 0;
        var seconds: i64 = 0;
        if (r.c() == ':') {
            r.i += 1;
            minutes = r.number() orelse return null;
        }
        if (r.c() == ':') {
            r.i += 1;
            seconds = r.number() orelse return null;
        }
        return -bias * (hours * 3600 + minutes * 60 + seconds);
    }

    fn spec(r: *PosixReader) ?PosixSpec {
        var sp = PosixSpec{};
        if (r.c() == 'M') {
            r.i += 1;
            sp.kind = .mwd;
            sp.month = r.number() orelse return null;
            if (r.c() != '.') return null;
            r.i += 1;
            sp.week = r.number() orelse return null;
            if (r.c() != '.') return null;
            r.i += 1;
            sp.dow = r.number() orelse return null;
        } else {
            if (r.c() == 'J') {
                sp.kind = .julian_no_feb29;
                r.i += 1;
            }
            sp.days = r.number() orelse return null;
        }
        if (r.c() == '/') {
            r.i += 1;
            sp.hour = -(r.offset() orelse return null);
        }
        return sp;
    }
};

fn parsePosixRule(text: []const u8) ?PosixRule {
    var r = PosixReader{ .s = text };
    var rule = PosixRule{ .std_name = r.description() orelse return null, .std_offset = r.offset() orelse return null };
    if (r.c() == 0) return rule;
    rule.dst_offset = rule.std_offset + 3600;
    rule.dst_name = r.description() orelse return null;
    if (r.c() != ',' and r.c() != 0) rule.dst_offset = r.offset() orelse return null;
    if (r.c() != ',') return null;
    r.i += 1;
    rule.begin = r.spec() orelse return null;
    if (r.c() != ',') return null;
    r.i += 1;
    rule.end = r.spec() orelse return null;
    if (r.c() != 0) return null;
    return rule;
}

const posix_month_lengths = [2][12]i64{
    .{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 },
    .{ 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 },
};

// seconds from the start of `year` to the transition day (tzcode's transtime)
fn posixTransition(sp: PosixSpec, year: i64) i64 {
    const leap: usize = if (dp.isLeap(year)) 1 else 0;
    switch (sp.kind) {
        .julian_no_feb29 => {
            var value = sp.days - 1;
            if (leap == 1 and sp.days >= 60) value += 1;
            return value *% 86400;
        },
        .julian_feb29 => return sp.days *% 86400,
        .mwd => {
            if (sp.month < 1 or sp.month > 12) return 0;
            const m1 = @rem(sp.month + 9, 12) + 1;
            const yy0 = if (sp.month <= 2) year - 1 else year;
            const yy1 = @divTrunc(yy0, 100);
            const yy2 = @rem(yy0, 100);
            var dow = @rem(@divTrunc(26 * m1 - 2, 10) + 1 + yy2 + @divTrunc(yy2, 4) + @divTrunc(yy1, 4) - 2 * yy1, 7);
            if (dow < 0) dow += 7;
            var d = sp.dow - dow;
            if (d < 0) d += 7;
            var i: i64 = 1;
            while (i < sp.week) : (i += 1) {
                if (d + 7 >= posix_month_lengths[leap][@intCast(sp.month - 1)]) break;
                d += 7;
            }
            var value = d * 86400;
            var k: usize = 0;
            while (k < @as(usize, @intCast(sp.month - 1))) : (k += 1) value += posix_month_lengths[leap][k] * 86400;
            return value;
        },
    }
}

fn tsAtStartOfYear(year: i64) i64 {
    const leaps = struct {
        fn f(y0: i64) i64 {
            const y = y0 - 1;
            return @divTrunc(y, 4) - @divTrunc(y, 100) + @divTrunc(y, 400);
        }
    }.f;
    return 86400 *% ((year -% 1970) *% 365 +% leaps(year) -% leaps(1970));
}

const PosixPeriod = struct { offset: i64, is_dst: bool, abbr: []const u8, transition: i64 };

// the period of the footer rule that holds `ts`; `last` is the table's final
// transition, which a rule without dst keeps as its start
fn posixLookup(rule: PosixRule, ts: i64, last: i64) ?PosixPeriod {
    const begin = rule.begin orelse return .{ .offset = rule.std_offset, .is_dst = false, .abbr = rule.std_name, .transition = last };
    const end = rule.end orelse return null;
    var y: i64 = undefined;
    var m: i64 = undefined;
    var d: i64 = undefined;
    dp.dateFromEpochDays(@divFloor(ts, 86400), &y, &m, &d);
    var times: [6]i64 = undefined;
    var dst: [6]bool = undefined;
    var n: usize = 0;
    var year = y - 1;
    while (year <= y + 1) : (year += 1) {
        const start = tsAtStartOfYear(year);
        const tb = start +% posixTransition(begin, year) +% begin.hour -% rule.std_offset;
        const te = start +% posixTransition(end, year) +% end.hour -% rule.dst_offset;
        if (tb < te) {
            times[n] = tb;
            dst[n] = true;
            times[n + 1] = te;
            dst[n + 1] = false;
        } else {
            times[n] = te;
            dst[n] = false;
            times[n + 1] = tb;
            dst[n + 1] = true;
        }
        n += 2;
    }
    var i: usize = 1;
    while (i < n) : (i += 1) {
        if (ts < times[i]) {
            const is_dst = dst[i - 1];
            return .{
                .offset = if (is_dst) rule.dst_offset else rule.std_offset,
                .is_dst = is_dst,
                .abbr = if (is_dst) rule.dst_name else rule.std_name,
                .transition = times[i - 1],
            };
        }
    }
    return null;
}

// the TZif v2+ footer text between its newlines, or null
fn tzifFooter(bytes: []const u8) ?[]const u8 {
    if (bytes.len < 44 or !std.mem.eql(u8, bytes[0..4], "TZif") or (bytes[4] != '2' and bytes[4] != '3' and bytes[4] != '4')) return null;
    const rdU32 = struct {
        fn f(b: []const u8, off: usize) usize {
            return std.mem.readInt(u32, b[off..][0..4], .big);
        }
    }.f;
    const v1 = rdU32(bytes, 32) * 5 + rdU32(bytes, 36) * 6 + rdU32(bytes, 40) + rdU32(bytes, 28) * 8 + rdU32(bytes, 24) + rdU32(bytes, 20);
    const h = 44 + v1;
    if (h + 44 > bytes.len or !std.mem.eql(u8, bytes[h .. h + 4], "TZif")) return null;
    const v2 = rdU32(bytes, h + 32) * 9 + rdU32(bytes, h + 36) * 6 + rdU32(bytes, h + 40) + rdU32(bytes, h + 28) * 12 + rdU32(bytes, h + 24) + rdU32(bytes, h + 20);
    const start = h + 44 + v2;
    if (start >= bytes.len or bytes[start] != '\n') return null;
    const end = std.mem.indexOfScalarPos(u8, bytes, start + 1, '\n') orelse return null;
    return bytes[start + 1 .. end];
}

// resolve offset/isdst/abbrev in effect at a UTC timestamp from TZif bytes.
// supports v1 (32-bit) and v2/v3 (64-bit, preferred). null on malformed input.
fn tzifLookupUtc(bytes: []const u8, utc_ts: i64) ?TzifRes {
    if (bytes.len < 44 or !std.mem.eql(u8, bytes[0..4], "TZif")) return null;
    const ver = bytes[4];
    const rdU32 = struct {
        fn f(b: []const u8, off: usize) usize {
            return std.mem.readInt(u32, b[off..][0..4], .big);
        }
    }.f;
    const v1_isutcnt = rdU32(bytes, 20);
    const v1_isstdcnt = rdU32(bytes, 24);
    const v1_leapcnt = rdU32(bytes, 28);
    const v1_timecnt = rdU32(bytes, 32);
    const v1_typecnt = rdU32(bytes, 36);
    const v1_charcnt = rdU32(bytes, 40);

    var timecnt = v1_timecnt;
    var typecnt = v1_typecnt;
    var charcnt = v1_charcnt;
    var base: usize = 44;
    var time_size: usize = 4;

    if (ver == '2' or ver == '3') {
        const v1_data = v1_timecnt * 4 + v1_timecnt + v1_typecnt * 6 + v1_charcnt + v1_leapcnt * 8 + v1_isstdcnt + v1_isutcnt;
        const v2_hdr = 44 + v1_data;
        if (v2_hdr + 44 > bytes.len or !std.mem.eql(u8, bytes[v2_hdr .. v2_hdr + 4], "TZif")) return null;
        timecnt = rdU32(bytes, v2_hdr + 32);
        typecnt = rdU32(bytes, v2_hdr + 36);
        charcnt = rdU32(bytes, v2_hdr + 40);
        base = v2_hdr + 44;
        time_size = 8;
    }
    if (typecnt == 0) return null;

    const times_off = base;
    const types_off = times_off + timecnt * time_size;
    const ttinfo_off = types_off + timecnt;
    const abbrev_off = ttinfo_off + typecnt * 6;
    if (abbrev_off + charcnt > bytes.len) return null;

    const readTime = struct {
        fn f(b: []const u8, off: usize, sz: usize) i64 {
            return if (sz == 8) std.mem.readInt(i64, b[off..][0..8], .big) else @as(i64, std.mem.readInt(i32, b[off..][0..4], .big));
        }
    }.f;

    // largest transition <= utc_ts
    var lo: usize = 0;
    var hi: usize = timecnt;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (readTime(bytes, times_off + mid * time_size, time_size) <= utc_ts) lo = mid + 1 else hi = mid;
    }
    if (lo == timecnt and time_size == 8) {
        if (tzifFooter(bytes)) |footer| if (parsePosixRule(footer)) |rule| {
            const last = if (timecnt > 0) readTime(bytes, times_off + (timecnt - 1) * time_size, time_size) else std.math.minInt(i64);
            if (posixLookup(rule, utc_ts, last)) |period| {
                var res = TzifRes{ .offset = @intCast(period.offset), .is_dst = period.is_dst };
                const n = @min(period.abbr.len, res.abbrev_buf.len);
                @memcpy(res.abbrev_buf[0..n], period.abbr[0..n]);
                res.abbrev_len = @intCast(n);
                return res;
            }
        };
    }
    const type_idx: u8 = if (lo == 0) firstNonDstType(bytes, ttinfo_off, typecnt) else bytes[types_off + (lo - 1)];
    if (type_idx >= typecnt) return null;
    const ti = ttinfo_off + @as(usize, type_idx) * 6;
    var res = TzifRes{ .offset = std.mem.readInt(i32, bytes[ti..][0..4], .big), .is_dst = bytes[ti + 4] != 0 };
    const abbrind: usize = bytes[ti + 5];
    var i = abbrev_off + abbrind;
    while (i < abbrev_off + charcnt and bytes[i] != 0 and res.abbrev_len < res.abbrev_buf.len) : (i += 1) {
        res.abbrev_buf[res.abbrev_len] = bytes[i];
        res.abbrev_len += 1;
    }
    return res;
}

// wall-clock (naive local) -> resolved offset. Around a forward transition the
// missing interval is interpreted with the old offset, which shifts the wall
// time forward by the size of the gap. During a backward transition PHP's
// default is the offset in effect when the naive wall timestamp is treated as
// UTC. Outside transition windows one refinement resolves the ordinary case.
fn tzifLookupWall(bytes: []const u8, wall_ts: i64) ?TzifRes {
    const g0 = tzifLookupUtc(bytes, wall_ts) orelse return null;
    if (bytes.len < 44 or !std.mem.eql(u8, bytes[0..4], "TZif")) return g0;

    const rdU32 = struct {
        fn f(b: []const u8, off: usize) usize {
            return std.mem.readInt(u32, b[off..][0..4], .big);
        }
    }.f;
    const v1_isutcnt = rdU32(bytes, 20);
    const v1_isstdcnt = rdU32(bytes, 24);
    const v1_leapcnt = rdU32(bytes, 28);
    const v1_timecnt = rdU32(bytes, 32);
    const v1_typecnt = rdU32(bytes, 36);
    const v1_charcnt = rdU32(bytes, 40);
    var timecnt = v1_timecnt;
    var base: usize = 44;
    var time_size: usize = 4;
    if (bytes[4] == '2' or bytes[4] == '3') {
        const v1_data = v1_timecnt * 4 + v1_timecnt + v1_typecnt * 6 + v1_charcnt + v1_leapcnt * 8 + v1_isstdcnt + v1_isutcnt;
        const v2_hdr = 44 + v1_data;
        if (v2_hdr + 44 > bytes.len or !std.mem.eql(u8, bytes[v2_hdr .. v2_hdr + 4], "TZif")) return g0;
        timecnt = rdU32(bytes, v2_hdr + 32);
        base = v2_hdr + 44;
        time_size = 8;
    }
    if (base + timecnt * time_size > bytes.len) return g0;

    const readTime = struct {
        fn f(b: []const u8, off: usize, size: usize) i64 {
            return if (size == 8) std.mem.readInt(i64, b[off..][0..8], .big) else @as(i64, std.mem.readInt(i32, b[off..][0..4], .big));
        }
    }.f;
    var lo: usize = 0;
    var hi = timecnt;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (readTime(bytes, base + mid * time_size, time_size) <= wall_ts) lo = mid + 1 else hi = mid;
    }
    const first = lo -| 2;
    const last = @min(timecnt, lo + 2);
    for (first..last) |i| {
        const transition = readTime(bytes, base + i * time_size, time_size);
        const before = tzifLookupUtc(bytes, transition - 1) orelse continue;
        const after = tzifLookupUtc(bytes, transition) orelse continue;
        const local_before = transition + before.offset;
        const local_after = transition + after.offset;
        if (after.offset > before.offset and wall_ts >= local_before and wall_ts < local_after) return before;
        if (after.offset < before.offset and wall_ts >= local_after and wall_ts < local_before) return g0;
    }

    return tzifLookupUtc(bytes, wall_ts - g0.offset) orelse g0;
}

// table-first, TZif-fallback. these replace the bare `lookupTimezone(name) ->
// tzOffsetAt(tz, ts)` pattern at the call sites so non-table zones work too.
pub fn tzOffsetForName(allocator: Allocator, name: []const u8, utc_ts: i64) i32 {
    if (abbrZone(name)) |hit| return @intCast(hit.offset);
    if (resolveTzif(allocator, name)) |h| {
        defer h.deinit(allocator);
        if (tzifLookupUtc(h.bytes, utc_ts)) |r| return r.offset;
    }
    if (lookupTimezone(name)) |tz| return tzOffsetAt(tz, utc_ts);
    return 0;
}

pub fn tzIsDstForName(allocator: Allocator, name: []const u8, utc_ts: i64) bool {
    if (abbrZone(name)) |hit| return hit.dst;
    if (resolveTzif(allocator, name)) |h| {
        defer h.deinit(allocator);
        if (tzifLookupUtc(h.bytes, utc_ts)) |r| return r.is_dst;
    }
    if (lookupTimezone(name)) |tz| return isDst(utc_ts, tz);
    return false;
}

pub fn tzOffsetForWallByName(allocator: Allocator, name: []const u8, wall_ts: i64) i32 {
    if (abbrZone(name)) |hit| return @intCast(hit.offset);
    if (resolveTzif(allocator, name)) |h| {
        defer h.deinit(allocator);
        if (tzifLookupWall(h.bytes, wall_ts)) |r| return r.offset;
    }
    if (lookupTimezone(name)) |tz| return tzOffsetForWall(tz, wall_ts);
    return 0;
}

// resolve the abbreviation for a zone+timestamp into an owned slice (caller
// frees), or null if unknown. table abbrevs are static; TZif ones are duped
// returns a freshly-allocated abbrev (caller frees) so table + TZif cases are
// uniform, or null if unknown
pub fn tzAbbrevForName(allocator: Allocator, name: []const u8, utc_ts: i64) ?[]const u8 {
    if (abbrZone(name) != null) return std.ascii.allocUpperString(allocator, name) catch null;
    if (resolveTzif(allocator, name)) |h| {
        defer h.deinit(allocator);
        if (tzifLookupUtc(h.bytes, utc_ts)) |r| {
            return allocator.dupe(u8, r.abbrev_buf[0..r.abbrev_len]) catch null;
        }
    }
    if (lookupTimezone(name)) |tz| return allocator.dupe(u8, tzAbbrevAt(tz, utc_ts)) catch null;
    return null;
}

// is this a zone zphp can resolve (table, system zoneinfo, or embedded blob)?
pub fn tzIsKnown(allocator: Allocator, name: []const u8) bool {
    if (lookupTimezone(name) != null) return true;
    if (resolveTzif(allocator, name)) |h| {
        defer h.deinit(allocator);
        return tzifLookupUtc(h.bytes, 0) != null;
    }
    return false;
}

fn parseFixedOffset(s: []const u8) ?i32 {
    if (s.len < 5 or (s[0] != '+' and s[0] != '-')) return null;
    const sign: i32 = if (s[0] == '-') -1 else 1;
    if (s.len >= 6 and s[3] == ':') {
        const h = std.fmt.parseInt(i32, s[1..3], 10) catch return null;
        const m = std.fmt.parseInt(i32, s[4..6], 10) catch return null;
        // "+05:30:15", as php names an offset with seconds
        const sec = if (s.len >= 9 and s[6] == ':') std.fmt.parseInt(i32, s[7..9], 10) catch return null else 0;
        return sign * (h * 3600 + m * 60 + sec);
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

    if (tz.dst_rule == .au or tz.dst_rule == .nz) {
        // southern hemisphere: DST is active in the SUMMER, which wraps the
        // year boundary - from a spring start (this calendar year) through the
        // end of the year, AND from the start of the year through an autumn end.
        // AU (NSW/VIC/ACT/TAS): 02:00 std first Sunday October -> 03:00 dst first
        // Sunday April. NZ: 02:00 std last Sunday September -> 03:00 dst first
        // Sunday April. local 02:00 std = UTC 02:00 - std_offset
        const start_month: u8 = if (tz.dst_rule == .nz) 9 else 10;
        const start_nth: u8 = if (tz.dst_rule == .nz) 5 else 1; // NZ last Sun, AU first Sun
        const start_day = nthWeekday(year, start_month, start_nth, 0);
        const apr_day = nthWeekday(year, 4, 1, 0);
        const dst_start = dateToTimestamp(year, start_month, start_day, 2, 0, 0) - @as(i64, tz.std_offset);
        const dst_end = dateToTimestamp(year, 4, apr_day, 3, 0, 0) - @as(i64, tz.dst_offset);
        return utc_ts >= dst_start or utc_ts < dst_end;
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

// gmdate is identical to date since zphp timestamps are always UTC
fn native_gmdate(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.literal("");
    const format = args[0].string.bytes();
    const timestamp: i64 = if (args.len >= 2) Value.toInt(args[1]) else platform.timestamp();
    return formatTimestampTz(ctx, timestamp, format, 0, "UTC");
}

fn native_tz_set(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const name = args[0].string.bytes();
    // a zone id, never an offset; php keeps the spelling it was given
    const valid = name.len > 0 and name.len <= ctx.vm.default_tz_buf.len and name[0] != '+' and name[0] != '-' and tzIsKnown(ctx.allocator, name);
    if (!valid) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "date_default_timezone_set(): Timezone ID '{s}' is invalid", .{name});
        defer ctx.allocator.free(msg);
        try ctx.vm.raiseError(8, msg);
        return NativeResult.scalar(.{ .bool = false });
    }
    @memcpy(ctx.vm.default_tz_buf[0..name.len], name);
    ctx.vm.default_tz_name = ctx.vm.default_tz_buf[0..name.len];
    return NativeResult.scalar(.{ .bool = true });
}

fn native_timezone_name_get(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const name = args[0].object.get("__timezone");
    if (name == .string) return NativeResult.shareString(name.string);
    return NativeResult.literal("UTC");
}

fn native_timezone_offset_get(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .object or args[1] != .object) return NativeResult.scalar(.{ .bool = false });
    const tz_obj = args[0].object;
    const dt_obj = args[1].object;
    const tz_name = if (tz_obj.get("__timezone") == .string) tz_obj.get("__timezone").string.bytes() else "UTC";
    const ts = getTimestamp(dt_obj);
    if (lookupTimezone(tz_name)) |tz| return NativeResult.scalar(.{ .int = @intCast(tzOffsetAt(tz, ts)) });
    return NativeResult.scalar(.{ .int = 0 });
}

fn native_timezone_open(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    try rejectNulBytes(ctx, "timezone_open", 1, "timezone", args[0].string.bytes());
    const zone = (try timezoneInitialize(ctx, args[0].string.bytes(), "timezone_open(): ", false)) orelse return NativeResult.scalar(.{ .bool = false });
    const obj = try ctx.createObject("DateTimeZone");
    try obj.setCopiedString(ctx.allocator, "__timezone", zone.name());
    return NativeResult.borrowed(.{ .object = obj });
}

fn native_date_timezone_get(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const tz_v = args[0].object.get("__timezone");
    if (tz_v != .string) return NativeResult.scalar(.{ .bool = false });
    const tz_obj = try ctx.createObject("DateTimeZone");
    try tz_obj.set(ctx.allocator, "__timezone", tz_v);
    return NativeResult.borrowed(.{ .object = tz_obj });
}

fn native_date_timezone_set(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .object or args[1] != .object) return NativeResult.scalar(.{ .bool = false });
    const tz_name = args[1].object.get("__timezone");
    if (tz_name == .string) {
        try args[0].object.set(ctx.allocator, "__timezone", tz_name);
    }
    return NativeResult.share(args[0]);
}

fn native_tz_get(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return try NativeResult.copyString(ctx.allocator, ctx.vm.default_tz_name);
}

// the broken-down local time of a timestamp in a zone, as localtime() and
// idate() report it
const LocalParts = struct {
    dc: DateComponents,
    offset: i32,
    dst: bool,
    dow: i64, // 0 = sunday
    yday: i64,
    day_num: i64,
    local_ts: i64,
};

fn localParts(a: Allocator, timestamp: i64, tz_name: []const u8) LocalParts {
    const offset = tzOffsetForName(a, tz_name, timestamp);
    const local_ts = timestamp + offset;
    const dc = baseComponents(local_ts);
    const day_num = @divFloor(local_ts, 86400);
    return .{
        .dc = dc,
        .offset = offset,
        .dst = tzIsDstForName(a, tz_name, timestamp),
        .dow = @mod(day_num + 4, 7),
        .yday = day_num - @divFloor(dateToTimestamp(dc.year, 1, 1, 0, 0, 0), 86400),
        .day_num = day_num,
        .local_ts = local_ts,
    };
}

fn native_localtime(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const timestamp: i64 = if (args.len >= 1 and args[0] != .null) Value.toInt(args[0]) else platform.timestamp();
    const assoc = args.len >= 2 and args[1].isTruthy();
    const lp = localParts(ctx.allocator, timestamp, ctx.vm.default_tz_name);
    const fields = [_]struct { []const u8, i64 }{
        .{ "tm_sec", lp.dc.sec },
        .{ "tm_min", lp.dc.min },
        .{ "tm_hour", lp.dc.hour },
        .{ "tm_mday", lp.dc.day },
        .{ "tm_mon", lp.dc.month - 1 },
        .{ "tm_year", lp.dc.year - 1900 },
        .{ "tm_wday", lp.dow },
        .{ "tm_yday", lp.yday },
        .{ "tm_isdst", @intFromBool(lp.dst) },
    };
    var arr = try ctx.createArray();
    for (fields) |f| {
        if (assoc) {
            try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(f[0]) }, .{ .int = f[1] });
        } else {
            try arr.append(ctx.allocator, .{ .int = f[1] });
        }
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_idate(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string or args[0].string.bytes().len == 0) return NativeResult.scalar(.{ .bool = false });
    const fmt = args[0].string.bytes()[0];
    const timestamp: i64 = if (args.len >= 2 and args[1] != .null) Value.toInt(args[1]) else platform.timestamp();
    const lp = localParts(ctx.allocator, timestamp, ctx.vm.default_tz_name);
    const dc = lp.dc;

    const v: i64 = switch (fmt) {
        'd' => dc.day,
        'h' => if (@mod(dc.hour, 12) == 0) 12 else @mod(dc.hour, 12),
        'H' => dc.hour,
        'i' => dc.min,
        'm' => dc.month,
        's' => dc.sec,
        // php hands idate's result through a c int
        'U' => @as(i32, @truncate(timestamp)),
        'w' => lp.dow,
        'y' => @mod(dc.year, 100),
        'Y' => dc.year,
        't' => daysInMonth(dc.month, dc.year),
        'z' => lp.yday,
        'I' => @intFromBool(lp.dst),
        'L' => @intFromBool(isLeapYear(dc.year)),
        'N' => if (lp.dow == 0) 7 else lp.dow,
        'o' => isoWeek(lp.day_num).year,
        'W' => isoWeek(lp.day_num).week,
        // swatch beats are measured in utc+1
        'B' => @divFloor(@mod(timestamp + 3600, 86400) * 10, 864),
        'Z' => lp.offset,
        else => return NativeResult.scalar(.{ .bool = false }),
    };
    return NativeResult.scalar(.{ .int = v });
}

fn isLeapYear(y: i64) bool {
    return (@mod(y, 4) == 0 and @mod(y, 100) != 0) or @mod(y, 400) == 0;
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
                    result.s = Value.dvalToLval(val);
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

fn diConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len > 0 and args[0] == .string) {
        const dur = parseIsoDuration(args[0].string.bytes());
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
    // intervals from a duration add hours, minutes, and seconds as elapsed
    // time (timelib_add_wall); the others add on the wall clock
    try obj.set(ctx.allocator, "__wall", .{ .bool = true });
    return NativeResult.scalar(.null);
}

fn diCreateFromDateString(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return intervalFromDateString(ctx, args, true);
}

// date_interval_create_from_date_string: the relative part of a date string.
// a parse error or a date, time, or zone in the string throws from the method
// and warns from the function
fn intervalFromDateString(ctx: *NativeContext, args: []const Value, throws: bool) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const input = args[0].string.bytes();
    var p = try parseDate(ctx, input);
    defer p.deinit(ctx.allocator);
    const t = &p.time;
    var msg: ?[]u8 = null;
    defer if (msg) |m| ctx.allocator.free(m);
    if (p.errors.items.len > 0) {
        const e = p.errors.items[0];
        msg = std.fmt.allocPrint(ctx.allocator, "Unknown or bad format ({s}) at position {d} ({c}): {s}", .{ input, e.pos, if (e.char == 0) ' ' else e.char, e.msg }) catch return error.OutOfMemory;
    } else if (t.have_date != 0 or t.have_time != 0 or t.have_zone != 0) {
        msg = std.fmt.allocPrint(ctx.allocator, "String '{s}' contains non-relative elements", .{input}) catch return error.OutOfMemory;
    }
    if (msg) |m| {
        if (throws) {
            try ctx.vm.setPendingException("DateMalformedIntervalStringException", m);
            return error.RuntimeError;
        }
        const w = std.fmt.allocPrint(ctx.allocator, "date_interval_create_from_date_string(): {s}", .{m}) catch return error.OutOfMemory;
        defer ctx.allocator.free(w);
        try ctx.vm.emitWarning(w);
        return NativeResult.scalar(.{ .bool = false });
    }
    const obj = try ctx.createObject("DateInterval");
    try storeStringInterval(ctx, obj, input, &t.relative);
    return NativeResult.borrowed(.{ .object = obj });
}

// an interval made from a date string: its relative part, and the string,
// which is what php shows and serializes
fn storeStringInterval(ctx: *NativeContext, obj: *PhpObject, input: []const u8, r: *const dp.Rel) RuntimeError!void {
    try obj.set(ctx.allocator, "y", .{ .int = r.y });
    try obj.set(ctx.allocator, "m", .{ .int = r.m });
    try obj.set(ctx.allocator, "d", .{ .int = r.d });
    try obj.set(ctx.allocator, "h", .{ .int = r.h });
    try obj.set(ctx.allocator, "i", .{ .int = r.i });
    try obj.set(ctx.allocator, "s", .{ .int = r.s });
    try obj.set(ctx.allocator, "f", .{ .float = @as(f64, @floatFromInt(r.us)) / 1000000.0 });
    try obj.set(ctx.allocator, "invert", .{ .int = 0 });
    try obj.set(ctx.allocator, "days", .{ .bool = false });
    try obj.set(ctx.allocator, "from_string", .{ .bool = true });
    try obj.setCopiedString(ctx.allocator, "__date_string", input);
}

const interval_fields = [_][]const u8{ "y", "m", "d", "h", "i", "s", "f", "invert", "days", "from_string" };

fn isIntervalField(key: PhpArray.Key) bool {
    if (key != .string) return false;
    for (interval_fields) |name| if (std.mem.eql(u8, key.string.bytes(), name)) return true;
    return std.mem.eql(u8, key.string.bytes(), "date_string");
}

// date_interval_object_to_hash: the ten fields, or for an interval from a
// date string only from_string and date_string
fn putIntervalFields(ctx: *NativeContext, obj: *PhpObject, table: *PhpArray) RuntimeError!void {
    const from_string = obj.get("from_string");
    if (from_string == .bool and from_string.bool) {
        try table.set(ctx.allocator, .{ .string = Value.String.borrowed("from_string") }, .{ .bool = true });
        try table.set(ctx.allocator, .{ .string = Value.String.borrowed("date_string") }, obj.get("__date_string"));
        return;
    }
    for (interval_fields) |name| try table.set(ctx.allocator, .{ .string = Value.String.borrowed(name) }, obj.get(name));
}

// the object's own properties, then its fields, as php's get_properties
// handler builds them
fn intervalProperties(ctx: *NativeContext, obj: *PhpObject, _: object_properties.Purpose) RuntimeError!?*PhpArray {
    const own = try object_properties.ownTable(ctx.vm, obj);
    const table = try ctx.vm.allocArray();
    for (own.entries.items) |entry| if (!isIntervalField(entry.key)) try table.set(ctx.allocator, entry.key, entry.value);
    try putIntervalFields(ctx, obj, table);
    return table;
}

fn intervalSerialize(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const out = try ctx.createArray();
    try putIntervalFields(ctx, obj, out);
    const own = try object_properties.ownTable(ctx.vm, obj);
    for (own.entries.items) |entry| if (!isIntervalField(entry.key) and !out.contains(entry.key)) try out.set(ctx.allocator, entry.key, entry.value);
    return NativeResult.borrowed(.{ .array = out });
}

// php_date_interval_initialize_from_hash: a date string is parsed again;
// otherwise each field is read with php's default, and an interval with no
// civil_or_wall adds on the wall clock's civil rules
fn initializeIntervalFromHash(ctx: *NativeContext, obj: *PhpObject, data: *const PhpArray) RuntimeError!void {
    const date_string = data.get(.{ .string = Value.String.borrowed("date_string") });
    if (date_string == .string) {
        const input = date_string.string.bytes();
        var p = try parseDate(ctx, input);
        defer p.deinit(ctx.allocator);
        if (p.errors.items.len > 0) {
            const e = p.errors.items[0];
            const msg = try std.fmt.allocPrint(ctx.allocator, "Unknown or bad format ({s}) at position {d} ({c}) while unserializing: {s}", .{ input, e.pos, if (e.char == 0) ' ' else e.char, e.msg });
            defer ctx.allocator.free(msg);
            try ctx.vm.setPendingException("Exception", msg);
            return error.RuntimeError;
        }
        try storeStringInterval(ctx, obj, input, &p.time.relative);
        try obj.set(ctx.allocator, "__wall", .{ .bool = false });
        return;
    }
    for ([_][]const u8{ "y", "m", "d", "h", "i", "s" }) |name| {
        const v = data.get(.{ .string = Value.String.borrowed(name) });
        try obj.set(ctx.allocator, name, .{ .int = if (isScalarField(v)) v.toInt() else -1 });
    }
    const f = data.get(.{ .string = Value.String.borrowed("f") });
    const us: i64 = if (data.contains(.{ .string = Value.String.borrowed("f") })) Value.dvalToLval(Value.toFloat(f) * 1000000.0) else 0;
    try obj.set(ctx.allocator, "f", .{ .float = @as(f64, @floatFromInt(us)) / 1000000.0 });
    const invert = data.get(.{ .string = Value.String.borrowed("invert") });
    try obj.set(ctx.allocator, "invert", .{ .int = if (isScalarField(invert)) invert.toInt() else 0 });
    const days = data.get(.{ .string = Value.String.borrowed("days") });
    const days_value: Value = if (days == .bool and !days.bool) .{ .bool = false } else if (isScalarField(days)) .{ .int = days.toInt() } else .{ .int = -1 };
    try obj.set(ctx.allocator, "days", days_value);
    try obj.set(ctx.allocator, "from_string", .{ .bool = false });
    const civil_or_wall = data.get(.{ .string = Value.String.borrowed("civil_or_wall") });
    try obj.set(ctx.allocator, "__wall", .{ .bool = civil_or_wall != .null and civil_or_wall.toInt() == 2 });
}

// what php reads as a number from a serialized field: null, a bool, a number
// or a string
fn isScalarField(v: Value) bool {
    return switch (v) {
        .null, .bool, .int, .float, .string => true,
        else => false,
    };
}

fn intervalUnserialize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len == 0 or args[0] != .array) return NativeResult.scalar(.null);
    try initializeIntervalFromHash(ctx, obj, args[0].array);
    entries: for (args[0].array.entries.items) |entry| {
        if (entry.key != .string or entry.ref != null or isIntervalField(entry.key)) continue :entries;
        const key = entry.key.string.bytes();
        const name = if (key.len > 0 and key[0] == 0) if (std.mem.lastIndexOfScalar(u8, key[1..], 0)) |end| key[end + 2 ..] else key else key;
        try obj.set(ctx.allocator, name, entry.value);
    }
    return NativeResult.scalar(.null);
}

fn intervalSetState(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try ctx.createObject("DateInterval");
    if (args.len > 0 and args[0] == .array) try initializeIntervalFromHash(ctx, obj, args[0].array);
    return NativeResult.borrowed(.{ .object = obj });
}

fn intervalWakeup(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const own = try ctx.vm.allocArray();
    for (interval_fields) |name| try own.set(ctx.allocator, .{ .string = Value.String.borrowed(name) }, obj.get(name));
    if (obj.get("__date_string") == .string) try own.set(ctx.allocator, .{ .string = Value.String.borrowed("date_string") }, obj.get("__date_string"));
    try initializeIntervalFromHash(ctx, obj, own);
    return NativeResult.scalar(.null);
}

fn diFormat(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len == 0 or args[0] != .string) return NativeResult.literal("");
    const fmt = args[0].string.bytes();

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
            // diff() stores whole microseconds as f, which can come back a
            // hair under the integer (0.250001 * 1e6 = 250000.99...)
            const us: i64 = Value.dvalToLval(@round(fv.float * 1_000_000.0));
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

    var i: usize = 0;
    while (i < fmt.len) : (i += 1) {
        const c = fmt[i];
        if (c != '%' or i + 1 >= fmt.len) {
            try buf.append(c);
            continue;
        }
        i += 1;
        switch (fmt[i]) {
            'Y' => try buf.print("{d:0>2}", .{y}),
            'y' => try buf.print("{d}", .{y_signed}),
            'M' => try buf.print("{d:0>2}", .{m}),
            'm' => try buf.print("{d}", .{m_signed}),
            'D' => try buf.print("{d:0>2}", .{d}),
            'd' => try buf.print("{d}", .{d_signed}),
            'a' => if (has_days) try buf.print("{d}", .{days_total}) else try buf.appendSlice("(unknown)"),
            'H' => try buf.print("{d:0>2}", .{h}),
            'h' => try buf.print("{d}", .{h_signed}),
            'I' => try buf.print("{d:0>2}", .{mi}),
            'i' => try buf.print("{d}", .{i_signed}),
            'S' => try buf.print("{d:0>2}", .{s}),
            's' => try buf.print("{d}", .{s_signed}),
            'F' => try buf.print("{d:0>6}", .{f_us}),
            'f' => try buf.print("{d}", .{f_us}),
            'R' => try buf.append(if (invert) '-' else '+'),
            'r' => if (invert) try buf.append('-'),
            '%' => try buf.append('%'),
            else => {
                try buf.append('%');
                try buf.append(fmt[i]);
            },
        }
    }

    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, try buf.toOwnedSlice()));
}

// ---- the date string parser (date_parse.zig) wired to zphp's zones ----

const dp = @import("date_parse.zig");

// the transition in effect at a utc instant, the way timelib looks it up:
// the period's offset, when it began (minInt before the first transition),
// and whether it is dst
fn tzifOffsetInfo(bytes: []const u8, utc_ts: i64) ?dp.OffsetInfo {
    if (bytes.len < 44 or !std.mem.eql(u8, bytes[0..4], "TZif")) return null;
    const rdU32 = struct {
        fn f(b: []const u8, off: usize) usize {
            return std.mem.readInt(u32, b[off..][0..4], .big);
        }
    }.f;
    var timecnt = rdU32(bytes, 32);
    var typecnt = rdU32(bytes, 36);
    var charcnt = rdU32(bytes, 40);
    var base: usize = 44;
    var time_size: usize = 4;
    if (bytes[4] == '2' or bytes[4] == '3') {
        const v1_data = timecnt * 4 + timecnt + typecnt * 6 + charcnt + rdU32(bytes, 28) * 8 + rdU32(bytes, 24) + rdU32(bytes, 20);
        const v2_hdr = 44 + v1_data;
        if (v2_hdr + 44 > bytes.len or !std.mem.eql(u8, bytes[v2_hdr .. v2_hdr + 4], "TZif")) return null;
        timecnt = rdU32(bytes, v2_hdr + 32);
        typecnt = rdU32(bytes, v2_hdr + 36);
        charcnt = rdU32(bytes, v2_hdr + 40);
        base = v2_hdr + 44;
        time_size = 8;
    }
    if (typecnt == 0) return null;
    const types_off = base + timecnt * time_size;
    const ttinfo_off = types_off + timecnt;
    if (ttinfo_off + typecnt * 6 > bytes.len) return null;
    const readTime = struct {
        fn f(b: []const u8, off: usize, sz: usize) i64 {
            return if (sz == 8) std.mem.readInt(i64, b[off..][0..8], .big) else @as(i64, std.mem.readInt(i32, b[off..][0..4], .big));
        }
    }.f;
    var lo: usize = 0;
    var hi: usize = timecnt;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (readTime(bytes, base + mid * time_size, time_size) <= utc_ts) lo = mid + 1 else hi = mid;
    }
    if (lo == timecnt and time_size == 8) {
        if (tzifFooter(bytes)) |footer| if (parsePosixRule(footer)) |rule| {
            const last = if (timecnt > 0) readTime(bytes, base + (timecnt - 1) * time_size, time_size) else std.math.minInt(i64);
            if (posixLookup(rule, utc_ts, last)) |period| return .{ .offset = period.offset, .transition_time = period.transition, .is_dst = period.is_dst };
        };
    }
    var transition: i64 = std.math.minInt(i64);
    var type_idx: usize = undefined;
    if (lo == 0) {
        type_idx = firstNonDstType(bytes, ttinfo_off, typecnt);
    } else {
        transition = readTime(bytes, base + (lo - 1) * time_size, time_size);
        type_idx = bytes[types_off + (lo - 1)];
    }
    if (type_idx >= typecnt) return null;
    const ti = ttinfo_off + type_idx * 6;
    return .{
        .offset = std.mem.readInt(i32, bytes[ti..][0..4], .big),
        .transition_time = transition,
        .is_dst = bytes[ti + 4] != 0,
    };
}

// a zone id is matched case-insensitively and keeps the spelling it was given,
// as timelib_tzinfo_ctor does
fn dbLookupId(name: []const u8, out: *[64]u8) ?[]const u8 {
    if (name.len == 0 or name.len > out.len) return null;
    if (embeddedZone(name, true) == null) {
        if (std.mem.eql(u8, name, "localtime") or std.mem.eql(u8, name, "posixrules")) return null;
        if (!tzNameValid(name) or !tzIsKnown(std.heap.page_allocator, name)) return null;
    }
    @memcpy(out[0..name.len], name);
    return out[0..name.len];
}

fn dbOffsetInfo(id: []const u8, ts: i64) ?dp.OffsetInfo {
    if (resolveTzif(std.heap.page_allocator, id)) |h| {
        if (tzifOffsetInfo(h.bytes, ts)) |r| return r;
    }
    if (lookupTimezone(id)) |tz| return .{ .offset = tzOffsetAt(tz, ts), .transition_time = std.math.minInt(i64), .is_dst = isDst(ts, tz) };
    return null;
}

const parse_db = dp.TzDb{ .lookupId = dbLookupId, .offsetInfo = dbOffsetInfo };

// an abbreviation zone ("EDT", "CEST", "Z"): php reads a name shorter than six
// characters as an abbreviation before trying it as a zone id, and keeps its
// offset and dst flag fixed. exact "UTC" stays the zone id
fn abbrZone(name: []const u8) ?dp.AbbrHit {
    if (name.len == 0 or name.len >= dp.MAX_ABBR_LEN or std.mem.eql(u8, name, "UTC")) return null;
    if (name[0] == '+' or name[0] == '-') return null;
    return dp.abbrSearch(name);
}

// a zone as php's timelib_time carries it: an id, a fixed offset, or an
// abbreviation (std offset plus a dst flag)
const ParseZone = struct {
    kind: u8 = dp.ZONETYPE_ID,
    buf: [64]u8 = undefined,
    len: u8 = 0,
    z: i64 = 0,
    dst: i64 = 0,

    fn name(self: *const ParseZone) []const u8 {
        return self.buf[0..self.len];
    }

    fn setName(self: *ParseZone, s: []const u8) void {
        const n = @min(s.len, self.buf.len);
        @memcpy(self.buf[0..n], s[0..n]);
        self.len = @intCast(n);
    }

    // the zone a stored name denotes; the default zone is always an id
    fn of(n: []const u8, force_id: bool) ParseZone {
        var zone = ParseZone{};
        zone.setName(n);
        if (force_id) return zone;
        if (n.len > 0 and (n[0] == '+' or n[0] == '-')) {
            zone.kind = dp.ZONETYPE_OFFSET;
            zone.z = if (parseFixedOffset(n)) |o| o else if (parseTimezoneOffset(n)) |o| o else 0;
        } else if (abbrZone(n)) |hit| {
            zone.kind = dp.ZONETYPE_ABBR;
            zone.dst = if (hit.dst) 1 else 0;
            zone.z = hit.offset - zone.dst * 3600;
        }
        return zone;
    }

    // the zone a resolved time ended up in, named the way php's getName() does
    fn ofTime(t: *const dp.Time) ParseZone {
        var zone = ParseZone{ .kind = t.zone_type, .z = t.z, .dst = t.dst };
        switch (t.zone_type) {
            dp.ZONETYPE_OFFSET => {
                var b: [16]u8 = undefined;
                zone.setName(offsetName(&b, t.z));
            },
            dp.ZONETYPE_ABBR => zone.setName(t.abbr() orelse "UTC"),
            else => zone.setName(t.id() orelse "UTC"),
        }
        return zone;
    }

    fn totalOffset(self: *const ParseZone, a: Allocator, ts: i64) i64 {
        return switch (self.kind) {
            dp.ZONETYPE_OFFSET => self.z,
            dp.ZONETYPE_ABBR => self.z + self.dst * 3600,
            else => tzOffsetForName(a, self.name(), ts),
        };
    }
};

// "+05:30" (and "+05:30:15" for an offset with seconds)
fn offsetName(buf: *[16]u8, z: i64) []const u8 {
    const sign: u8 = if (z < 0) '-' else '+';
    const abs: u64 = @abs(z);
    const h = abs / 3600;
    const m = (abs % 3600) / 60;
    const s = abs % 60;
    if (s != 0) return std.fmt.bufPrint(buf, "{c}{d:0>2}:{d:0>2}:{d:0>2}", .{ sign, h, m, s }) catch "+00:00";
    return std.fmt.bufPrint(buf, "{c}{d:0>2}:{d:0>2}", .{ sign, h, m }) catch "+00:00";
}

// wall-clock fields of an instant in a zone (timelib_unixtime2local)
fn wallTime(a: Allocator, ts: i64, us: i64, zone: *const ParseZone) dp.Time {
    var t = dp.Time{ .sse = ts };
    const off = zone.totalOffset(a, ts);
    const wall = ts +% off;
    const days = @divFloor(wall, 86400);
    const secs = wall - days * 86400;
    dp.dateFromEpochDays(days, &t.y, &t.m, &t.d);
    t.h = @divTrunc(secs, 3600);
    t.i = @divTrunc(@rem(secs, 3600), 60);
    t.s = @rem(secs, 60);
    t.us = us;
    t.zone_type = zone.kind;
    t.is_localtime = true;
    t.have_zone = 1;
    switch (zone.kind) {
        dp.ZONETYPE_OFFSET => {
            t.z = zone.z;
            t.dst = 0;
        },
        dp.ZONETYPE_ABBR => {
            t.z = zone.z;
            t.dst = zone.dst;
            t.setAbbr(zone.name());
        },
        else => {
            t.z = off;
            t.dst = if (tzIsDstForName(a, zone.name(), ts)) 1 else 0;
            t.setId(zone.name());
        },
    }
    return t;
}

fn nowOf(a: Allocator, ts: i64, us: i64, zone: *const ParseZone) dp.Now {
    const t = wallTime(a, ts, us, zone);
    return .{ .y = t.y, .m = t.m, .d = t.d, .h = t.h, .i = t.i, .s = t.s, .us = us, .z = t.z, .dst = t.dst, .zone_type = zone.kind, .name = zone.name() };
}

fn parseDate(ctx: *NativeContext, input: []const u8) RuntimeError!dp.Parsed {
    return dp.parse(ctx.allocator, input, parse_db) catch return error.OutOfMemory;
}

fn recordLastErrors(ctx: *NativeContext, p: *const dp.Parsed) void {
    var rec = vm_mod.DtLastErrors{};
    for (p.warnings.items) |w| rec.addWarning(w.pos, w.msg);
    for (p.errors.items) |e| rec.addError(e.pos, e.msg);
    rec.set = rec.warning_count > 0 or rec.error_count > 0;
    ctx.vm.last_dt = rec;
}

// "Failed to parse time string (%s) at position %d (%c): %s", with an optional
// "Class::method(): " prefix
fn parseFailure(ctx: *NativeContext, prefix: []const u8, input: []const u8, p: *const dp.Parsed) RuntimeError![]u8 {
    const e = p.errors.items[0];
    const c: u8 = if (e.char == 0) ' ' else e.char;
    return std.fmt.allocPrint(ctx.allocator, "{s}Failed to parse time string ({s}) at position {d} ({c}): {s}", .{ prefix, input, e.pos, c, e.msg }) catch error.OutOfMemory;
}

fn currentTimeMicros() struct { ts: i64, us: i64 } {
    const ns = platform.nanoTimestamp();
    return .{ .ts = @intCast(@divFloor(ns, 1_000_000_000)), .us = @intCast(@divFloor(@mod(ns, 1_000_000_000), 1_000)) };
}

// zone names live for the process: there are few distinct ones, and date
// objects then share one borrowed string instead of copying it per object
var zone_names: std.StringHashMapUnmanaged(void) = .{};
var zone_names_mutex: sync.Mutex = .{};
threadlocal var last_zone_name_interned: []const u8 = "";

fn internZoneName(name: []const u8) []const u8 {
    if (std.mem.eql(u8, name, last_zone_name_interned)) return last_zone_name_interned;
    zone_names_mutex.lock();
    defer zone_names_mutex.unlock();
    const kept = if (zone_names.getKey(name)) |k| k else blk: {
        const copy = std.heap.page_allocator.dupe(u8, name) catch return "UTC";
        zone_names.put(std.heap.page_allocator, copy, {}) catch return "UTC";
        break :blk copy;
    };
    last_zone_name_interned = kept;
    return kept;
}

fn storeInstant(ctx: *NativeContext, obj: *PhpObject, ts: i64, us: i64, zone: *const ParseZone) RuntimeError!void {
    try obj.set(ctx.allocator, "__timestamp", .{ .int = ts });
    const cur_zone = obj.get("__timezone");
    if (cur_zone != .string or !std.mem.eql(u8, cur_zone.string.bytes(), zone.name())) {
        try obj.set(ctx.allocator, "__timezone", .{ .string = Value.String.borrowed(internZoneName(zone.name())) });
    }
    // a missing __microseconds reads as 0
    if (us != 0 or obj.get("__microseconds") != .null) try obj.set(ctx.allocator, "__microseconds", .{ .int = us });
}

// php_date_initialize: the constructors and date_create(). a parse error
// throws when `throws` is set (the constructors) and otherwise only makes the
// call fail. tz_arg is the DateTimeZone argument's zone name
const Instant = struct { ts: i64, us: i64, zone: ParseZone };

fn resolveDate(ctx: *NativeContext, input: []const u8, tz_arg: ?[]const u8, throws: bool) RuntimeError!?Instant {
    return resolveDateWith(ctx, input, null, tz_arg, throws);
}

// with a format, the string is read by timelib_parse_from_format and unset
// time fields come from now instead of midnight (createFromFormat)
fn resolveDateWith(ctx: *NativeContext, input_arg: []const u8, format: ?[]const u8, tz_arg: ?[]const u8, throws: bool) RuntimeError!?Instant {
    const input = if (input_arg.len == 0 and format == null) "now" else input_arg;
    var p = if (format) |f|
        dp.parseFromFormat(ctx.allocator, f, input, parse_db) catch return error.OutOfMemory
    else
        try parseDate(ctx, input);
    defer p.deinit(ctx.allocator);
    recordLastErrors(ctx, &p);
    if (p.errors.items.len > 0) {
        if (throws) {
            const msg = try parseFailure(ctx, "", input, &p);
            defer ctx.allocator.free(msg);
            try ctx.vm.setPendingException("DateMalformedStringException", msg);
        }
        return null;
    }
    const zone = if (tz_arg) |n|
        ParseZone.of(n, false)
    else if (p.time.zone_type == dp.ZONETYPE_ID and p.time.id() != null)
        ParseZone.of(p.time.id().?, true)
    else
        ParseZone.of(ctx.vm.default_tz_name, true);
    const now_t = currentTimeMicros();
    if (format == null and std.mem.eql(u8, input, "now")) return .{ .ts = now_t.ts, .us = now_t.us, .zone = zone };
    const now = nowOf(ctx.allocator, now_t.ts, now_t.us, &zone);
    dp.fillHoles(&p.time, &now, format != null);
    dp.updateTs(&p.time, if (zone.kind == dp.ZONETYPE_ID) zone.name() else null, parse_db);
    return .{ .ts = p.time.sse, .us = p.time.us, .zone = ParseZone.ofTime(&p.time) };
}

// php_date_modify: the parsed fields replace the object's wall-clock fields,
// then the relative part applies. a parsed zone is ignored, except that
// "@ts" moves the object to +00:00
fn modifyDateObject(ctx: *NativeContext, obj: *PhpObject, input: []const u8, prefix: []const u8, throws: bool) RuntimeError!bool {
    var p = try parseDate(ctx, input);
    defer p.deinit(ctx.allocator);
    recordLastErrors(ctx, &p);
    if (p.errors.items.len > 0) {
        const msg = try parseFailure(ctx, prefix, input, &p);
        defer ctx.allocator.free(msg);
        if (throws) {
            try ctx.vm.setPendingException("DateMalformedStringException", msg);
            return error.RuntimeError;
        }
        try ctx.vm.emitWarning(msg);
        return false;
    }
    const zone = ParseZone.of(objTzName(obj, ctx.vm.default_tz_name), false);
    const us_v = obj.get("__microseconds");
    var t = wallTime(ctx.allocator, getTimestamp(obj), if (us_v == .int) us_v.int else 0, &zone);
    const tmp = &p.time;
    t.relative = tmp.relative;
    t.have_relative = tmp.have_relative;
    if (tmp.y != dp.UNSET) t.y = tmp.y;
    if (tmp.m != dp.UNSET) t.m = tmp.m;
    if (tmp.d != dp.UNSET) t.d = tmp.d;
    if (tmp.h != dp.UNSET) {
        t.h = tmp.h;
        if (tmp.i != dp.UNSET) {
            t.i = tmp.i;
            t.s = if (tmp.s != dp.UNSET) tmp.s else 0;
        } else {
            t.i = 0;
            t.s = 0;
        }
    }
    if (tmp.us != dp.UNSET) t.us = tmp.us;
    if (tmp.y == 1970 and tmp.m == 1 and tmp.d == 1 and tmp.h == 0 and tmp.i == 0 and tmp.s == 0 and tmp.us == 0 and
        tmp.have_zone != 0 and tmp.zone_type == dp.ZONETYPE_OFFSET and tmp.z == 0 and tmp.dst == 0)
    {
        t.zone_type = dp.ZONETYPE_OFFSET;
        t.z = 0;
        t.dst = 0;
        t.has_id = false;
        t.has_abbr = false;
    }
    dp.updateTs(&t, null, parse_db);
    const result_zone = ParseZone.ofTime(&t);
    try storeInstant(ctx, obj, t.sse, t.us, &result_zone);
    return true;
}

// strtotime(): unset fields come from the base time in the default zone
fn strtotimeIn(ctx: *NativeContext, input: []const u8, base: i64) RuntimeError!?i64 {
    var p = try parseDate(ctx, input);
    defer p.deinit(ctx.allocator);
    if (p.errors.items.len > 0) return null;
    const zone = ParseZone.of(ctx.vm.default_tz_name, true);
    const now = nowOf(ctx.allocator, base, 0, &zone);
    dp.fillHoles(&p.time, &now, false);
    dp.updateTs(&p.time, zone.name(), parse_db);
    return p.time.sse;
}

fn putAssoc(ctx: *NativeContext, arr: *@import("../runtime/value.zig").PhpArray, key: []const u8, v: Value) RuntimeError!void {
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(key) }, v);
}

fn putAssocStr(ctx: *NativeContext, arr: *@import("../runtime/value.zig").PhpArray, key: []const u8, bytes: []const u8) RuntimeError!void {
    const str = try Value.String.create(ctx.allocator, bytes);
    defer str.release();
    try putAssoc(ctx, arr, key, .{ .string = str });
}

fn messagesArray(ctx: *NativeContext, msgs: []const vm_mod.DtMsg) RuntimeError!*@import("../runtime/value.zig").PhpArray {
    const arr = try ctx.createArray();
    for (msgs) |m| try arr.set(ctx.allocator, .{ .int = @intCast(m.pos) }, .{ .string = Value.String.borrowed(m.msg) });
    return arr;
}

fn putErrorContainer(ctx: *NativeContext, arr: *@import("../runtime/value.zig").PhpArray, rec: *const vm_mod.DtLastErrors) RuntimeError!void {
    try putAssoc(ctx, arr, "warning_count", .{ .int = rec.warning_count });
    try putAssoc(ctx, arr, "warnings", .{ .array = try messagesArray(ctx, rec.warnings[0..rec.warnings_len]) });
    try putAssoc(ctx, arr, "error_count", .{ .int = rec.error_count });
    try putAssoc(ctx, arr, "errors", .{ .array = try messagesArray(ctx, rec.errors[0..rec.errors_len]) });
}

// php_date_do_return_parsed_time
fn parsedTimeArray(ctx: *NativeContext, p: *const dp.Parsed) RuntimeError!NativeResult {
    const t = &p.time;
    const arr = try ctx.createArray();
    const field = struct {
        fn f(v: i64) Value {
            return if (v == dp.UNSET) .{ .bool = false } else .{ .int = v };
        }
    }.f;
    try putAssoc(ctx, arr, "year", field(t.y));
    try putAssoc(ctx, arr, "month", field(t.m));
    try putAssoc(ctx, arr, "day", field(t.d));
    try putAssoc(ctx, arr, "hour", field(t.h));
    try putAssoc(ctx, arr, "minute", field(t.i));
    try putAssoc(ctx, arr, "second", field(t.s));
    try putAssoc(ctx, arr, "fraction", if (t.us == dp.UNSET) .{ .bool = false } else .{ .float = @as(f64, @floatFromInt(t.us)) / 1000000.0 });
    var rec = vm_mod.DtLastErrors{};
    for (p.warnings.items) |w| rec.addWarning(w.pos, w.msg);
    for (p.errors.items) |e| rec.addError(e.pos, e.msg);
    try putErrorContainer(ctx, arr, &rec);
    try putAssoc(ctx, arr, "is_localtime", .{ .bool = t.is_localtime });
    if (t.is_localtime) {
        try putAssoc(ctx, arr, "zone_type", .{ .int = t.zone_type });
        switch (t.zone_type) {
            dp.ZONETYPE_OFFSET => {
                try putAssoc(ctx, arr, "zone", field(t.z));
                try putAssoc(ctx, arr, "is_dst", .{ .bool = t.dst != 0 });
            },
            dp.ZONETYPE_ID => {
                if (t.abbr()) |ab| try putAssocStr(ctx, arr, "tz_abbr", ab);
                if (t.id()) |id| try putAssocStr(ctx, arr, "tz_id", id);
            },
            dp.ZONETYPE_ABBR => {
                try putAssoc(ctx, arr, "zone", field(t.z));
                try putAssoc(ctx, arr, "is_dst", .{ .bool = t.dst != 0 });
                try putAssocStr(ctx, arr, "tz_abbr", t.abbr() orelse "");
            },
            else => {},
        }
    }
    if (t.have_relative) {
        const rel = try ctx.createArray();
        const r = &t.relative;
        try putAssoc(ctx, rel, "year", .{ .int = r.y });
        try putAssoc(ctx, rel, "month", .{ .int = r.m });
        try putAssoc(ctx, rel, "day", .{ .int = r.d });
        try putAssoc(ctx, rel, "hour", .{ .int = r.h });
        try putAssoc(ctx, rel, "minute", .{ .int = r.i });
        try putAssoc(ctx, rel, "second", .{ .int = r.s });
        if (r.have_weekday_relative) try putAssoc(ctx, rel, "weekday", .{ .int = r.weekday });
        if (r.have_special_relative and r.special_type == dp.SPECIAL_WEEKDAY) try putAssoc(ctx, rel, "weekdays", .{ .int = r.special_amount });
        if (r.first_last_day_of != 0) try putAssoc(ctx, rel, if (r.first_last_day_of == dp.FIRST_DAY_OF_MONTH) "first_day_of_month" else "last_day_of_month", .{ .bool = true });
        try putAssoc(ctx, arr, "relative", .{ .array = rel });
    }
    return NativeResult.borrowed(.{ .array = arr });
}
