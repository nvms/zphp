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
const tzdb = @import("tzdb.zig");
const date_format = @import("date_format.zig");
const tz_abbr_table = @import("tz_abbr_table.zig");
const string_ports = @import("string_ports.zig");
const strings = @import("strings.zig");

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
    .{ "timezone_identifiers_list", native_timezone_identifiers_list },
    .{ "timezone_name_from_abbr", native_timezone_name_from_abbr },
    .{ "timezone_version_get", native_timezone_version_get },
    .{ "timezone_abbreviations_list", dtzListAbbreviations },
    .{ "timezone_name_get", native_timezone_name_get },
    .{ "timezone_offset_get", native_timezone_offset_get },
    .{ "timezone_open", native_timezone_open },
    .{ "date_timezone_get", native_date_timezone_get },
    .{ "date_timezone_set", native_date_timezone_set },
    .{ "localtime", native_localtime },
    .{ "idate", native_idate },
    .{ "date_sun_info", native_date_sun_info },
    .{ "strftime", native_strftime },
    .{ "gmstrftime", native_gmstrftime },
    .{ "date_sunrise", native_date_sunrise },
    .{ "date_sunset", native_date_sunset },
    .{ "date_interval_create_from_date_string", native_date_interval_create_from_date_string },
    .{ "date_interval_format", native_date_interval_format },
    .{ "date_offset_get", native_date_offset_get },
    .{ "date_isodate_set", native_date_isodate_set },
    .{ "timezone_transitions_get", native_timezone_transitions_get },
    .{ "timezone_location_get", native_timezone_location_get },
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
    var dt_def = ClassDef{ .name = "DateTime", .native_properties = dateProperties, .native_binop = dateBinop };
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
    try vm.native_fns.put(a, "DateTimeImmutable::getOffset", dtiGetOffset);

    // DateTimeImmutable
    var dti_def = ClassDef{ .name = "DateTimeImmutable", .native_properties = dateProperties, .native_binop = dateBinop };
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

    try vm.native_fns.put(a, "DateTimeImmutable::__construct", dtiConstruct);
    try vm.native_fns.put(a, "DateTimeImmutable::format", dtiFormat);
    try vm.native_fns.put(a, "DateTimeImmutable::getTimestamp", dtiGetTimestamp);
    try vm.native_fns.put(a, "DateTimeImmutable::modify", dtiModify);
    try vm.native_fns.put(a, "DateTimeImmutable::add", dtiAdd);
    try vm.native_fns.put(a, "DateTimeImmutable::sub", dtiSub);
    try vm.native_fns.put(a, "DateTimeImmutable::diff", dtiDiff);
    try vm.native_fns.put(a, "DateTimeImmutable::createFromTimestamp", dtiCreateFromTimestamp);
    try vm.native_fns.put(a, "DateTimeImmutable::getMicrosecond", dtiGetMicrosecond);
    try vm.native_fns.put(a, "DateTimeImmutable::setMicrosecond", dtiSetMicrosecond);
    try vm.native_fns.put(a, "DateTimeImmutable::getLastErrors", dtGetLastErrors);
    try vm.native_fns.put(a, "DateTimeImmutable::getTimezone", dtiGetTimezone);
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
    var dtz_def = ClassDef{ .name = "DateTimeZone", .native_properties = timezoneProperties, .native_binop = dateBinop };
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
    inline for (.{ .{ "AFRICA", 1 }, .{ "AMERICA", 2 }, .{ "ANTARCTICA", 4 }, .{ "ARCTIC", 8 }, .{ "ASIA", 16 }, .{ "ATLANTIC", 32 }, .{ "AUSTRALIA", 64 }, .{ "EUROPE", 128 }, .{ "INDIAN", 256 }, .{ "PACIFIC", 512 }, .{ "UTC", 1024 }, .{ "ALL", 2047 }, .{ "ALL_WITH_BC", 4095 }, .{ "PER_COUNTRY", 4096 } }) |c| {
        try dtz_def.constants.put(a, c[0], .{ .int = c[1] });
    }
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
    var di_def = ClassDef{ .name = "DateInterval", .native_properties = intervalProperties, .native_binop = dateBinop };
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
    var dp_def = ClassDef{ .name = "DatePeriod", .native_properties = periodProperties, .native_binop = dateBinop };
    try dp_def.properties.append(a, .{ .name = "start", .default = .null, .type_str = "?DateTimeInterface", .is_readonly = true, .readonly_undeclared = true });
    try dp_def.properties.append(a, .{ .name = "current", .default = .null, .type_str = "?DateTimeInterface", .is_readonly = true, .readonly_undeclared = true });
    try dp_def.properties.append(a, .{ .name = "end", .default = .null, .type_str = "?DateTimeInterface", .is_readonly = true, .readonly_undeclared = true });
    try dp_def.properties.append(a, .{ .name = "interval", .default = .null, .type_str = "?DateInterval", .is_readonly = true, .readonly_undeclared = true });
    try dp_def.properties.append(a, .{ .name = "recurrences", .default = .undef, .type_str = "int", .is_readonly = true, .readonly_undeclared = true });
    try dp_def.properties.append(a, .{ .name = "include_start_date", .default = .undef, .type_str = "bool", .is_readonly = true, .readonly_undeclared = true });
    try dp_def.properties.append(a, .{ .name = "include_end_date", .default = .undef, .type_str = "bool", .is_readonly = true, .readonly_undeclared = true });
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
}

// ---- DatePeriod ----

const period_fields = [_][]const u8{ "start", "current", "end", "interval", "recurrences", "include_start_date", "include_end_date" };

fn isPeriodField(key: PhpArray.Key) bool {
    if (key != .string) return false;
    for (period_fields) |name| if (std.mem.eql(u8, key.string.bytes(), name)) return true;
    return false;
}

fn periodInitialized(obj: *PhpObject) bool {
    return obj.get("__init") == .bool;
}

// the period's copy of an interval: its relative time, shown as plain fields
// (create_date_period_interval keeps neither from_string nor civil_or_wall);
// the date string stays behind for its weekday and special parts
fn periodInterval(ctx: *NativeContext, iv: *PhpObject) RuntimeError!*PhpObject {
    const copy = try ctx.createObject("DateInterval");
    for (interval_fields) |name| try copy.set(ctx.allocator, name, iv.get(name));
    try copy.set(ctx.allocator, "from_string", .{ .bool = false });
    if (iv.get("__date_string") == .string) try copy.set(ctx.allocator, "__date_string", iv.get("__date_string"));
    try copy.set(ctx.allocator, "__wall", .{ .bool = false });
    try markInterval(ctx, copy);
    return copy;
}

const PeriodArgs = union(enum) {
    recurrences: struct { start: *PhpObject, interval: *PhpObject, count: i64, options: i64 },
    end: struct { start: *PhpObject, interval: *PhpObject, end: *PhpObject, options: i64 },
    iso: struct { spec: []const u8, options: i64 },
};

// a long the way zend_parse_parameters reads one, or null where it would fail
fn quietLong(v: Value) ?i64 {
    return switch (v) {
        .int => |i| i,
        .bool => |b| @intFromBool(b),
        .float => |f| if (std.math.isNan(f) or !Value.floatFitsInt(f)) null else @as(i64, @intFromFloat(@trunc(f))),
        .string => |s| if (Value.isNumericString(s.bytes())) Value.toInt(v) else null,
        else => null,
    };
}

fn isDateObject(ctx: *NativeContext, v: Value, class: []const u8) bool {
    return v == .object and ctx.vm.isInstanceOf(v.object.class_name, class);
}

// DatePeriod::__construct's three argument lists, tried in turn as php
// tries them quietly
fn periodArgs(ctx: *NativeContext, args: []const Value) RuntimeError!?PeriodArgs {
    if (args.len >= 3 and args.len <= 4 and isDateObject(ctx, args[0], "DateTimeInterface") and isDateObject(ctx, args[1], "DateInterval")) {
        const options: ?i64 = if (args.len == 4) quietLong(args[3]) else 0;
        if (options) |opt| {
            if (args[2] != .object and args[2] != .null) if (quietLong(args[2])) |count| {
                return .{ .recurrences = .{ .start = args[0].object, .interval = args[1].object, .count = count, .options = opt } };
            };
            if (isDateObject(ctx, args[2], "DateTimeInterface")) {
                return .{ .end = .{ .start = args[0].object, .interval = args[1].object, .end = args[2].object, .options = opt } };
            }
        }
    }
    if (args.len >= 1 and args.len <= 2) {
        const options: ?i64 = if (args.len == 2) quietLong(args[1]) else 0;
        if (options) |opt| switch (args[0]) {
            .string => |s| return .{ .iso = .{ .spec = s.bytes(), .options = opt } },
            .int, .float, .bool => return .{ .iso = .{ .spec = try strings.coerceToString(ctx, args[0]), .options = opt } },
            .null, .undef => {
                try ctx.vm.raiseError(VM.E_DEPRECATED, "DatePeriod::__construct(): Passing null to parameter #1 ($start) of type string is deprecated");
                return .{ .iso = .{ .spec = "", .options = opt } };
            },
            else => {},
        };
    }
    return null;
}

fn dpConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const parsed = (try periodArgs(ctx, args)) orelse {
        try ctx.vm.setPendingException("TypeError", "DatePeriod::__construct() accepts (DateTimeInterface, DateInterval, int [, int]), or (DateTimeInterface, DateInterval, DateTime [, int]), or (string [, int]) as arguments");
        return error.RuntimeError;
    };
    switch (parsed) {
        .iso => |iso| {
            try ctx.vm.raiseError(VM.E_DEPRECATED, "Calling DatePeriod::__construct(string $isostr, int $options = 0) is deprecated, use DatePeriod::createFromISO8601String() instead");
            if (ctx.vm.pending_exception != null) return error.RuntimeError;
            try initializePeriodFromIso(ctx, obj, iso.spec, iso.options, "DatePeriod::__construct", "DateTime");
        },
        .recurrences, .end => {
            const start, const interval, const end, const count, const options = switch (parsed) {
                .recurrences => |r| .{ r.start, r.interval, @as(?*PhpObject, null), r.count, r.options },
                .end => |e| .{ e.start, e.interval, @as(?*PhpObject, e.end), @as(i64, 0), e.options },
                else => unreachable,
            };
            // DATE_CHECK_INITIALIZED names the interface for the dates
            if (start.get("__timestamp") == .null) return throwUninitialized(ctx, "DateTimeInterface");
            if (end) |e| if (e.get("__timestamp") == .null) return throwUninitialized(ctx, "DateTimeInterface");
            _ = try intervalOf(ctx, interval);
            try obj.set(ctx.allocator, "start", .{ .object = try cloneDateObject(ctx, start) });
            try obj.set(ctx.allocator, "interval", .{ .object = try periodInterval(ctx, interval) });
            if (end) |e| try obj.set(ctx.allocator, "end", .{ .object = try cloneDateObject(ctx, e) });
            try finishPeriod(ctx, obj, count, options, "DatePeriod::__construct");
        },
    }
    return NativeResult.scalar(.null);
}

const max_recurrences: i64 = 2147483639;

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
    try putRelFields(ctx, interval, period.y, period.m, period.d, period.h, period.i, period.s, 0, false, null);
    try markInterval(ctx, interval);
    try obj.set(ctx.allocator, "interval", .{ .object = interval });
    try finishPeriod(ctx, obj, parsed.recurrences, options, func);
}

fn isoDate(ctx: *NativeContext, class: []const u8, d: iso_interval.Date) RuntimeError!*PhpObject {
    var t = isoTime(d);
    dp.updateTs(&t, null, parse_db);
    const date = try ctx.createObject(class);
    const zone = ParseZone.of("+00:00", false);
    try storeInstant(ctx, date, t.sse, 0, &zone);
    return date;
}

// date_period_init_finish
fn finishPeriod(ctx: *NativeContext, obj: *PhpObject, recurrences: i64, options: i64, func: []const u8) RuntimeError!void {
    if (obj.get("end") == .null and (recurrences < 1 or recurrences > max_recurrences)) {
        return malformedPeriod(ctx, "{s}(): Recurrence count must be greater or equal to 1 and lower than 2147483640", .{func});
    }
    const include_start = options & 1 == 0;
    const include_end = options & 2 != 0;
    const total = recurrences + @intFromBool(include_start) + @intFromBool(include_end);
    if (total > max_recurrences) {
        return throwFmt(ctx, "DateMalformedStringException", "{s}(): Recurrence count must be greater or equal to 1 and lower than 2147483640 (including options)", .{func});
    }
    try obj.set(ctx.allocator, "include_start_date", .{ .bool = include_start });
    try obj.set(ctx.allocator, "include_end_date", .{ .bool = include_end });
    try obj.set(ctx.allocator, "recurrences", .{ .int = total });
    try obj.set(ctx.allocator, "__init", .{ .bool = true });
}

fn malformedPeriod(ctx: *NativeContext, comptime fmt: []const u8, args: anytype) RuntimeError {
    return throwFmt(ctx, "DateMalformedPeriodStringException", fmt, args);
}

fn periodFromIsoString(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "DatePeriod::createFromISO8601String", args);
    const spec = try p.str(0, "specification");
    const options = try p.optLong(1, "options", 0);
    const obj = try ctx.createObject(staticClass(ctx, "DatePeriod"));
    try initializePeriodFromIso(ctx, obj, spec, options, "DatePeriod::createFromISO8601String", "DateTimeImmutable");
    return NativeResult.borrowed(.{ .object = obj });
}

// each read hands out a copy, so the period itself never changes
fn dpGetStart(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const start = obj.get("start");
    if (start != .object) return throwUninitialized(ctx, obj.class_name);
    return NativeResult.borrowed(.{ .object = try cloneDateObject(ctx, start.object) });
}

fn dpGetEnd(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const end = obj.get("end");
    if (end != .object) return NativeResult.scalar(.null);
    return NativeResult.borrowed(.{ .object = try cloneDateObject(ctx, end.object) });
}

fn dpGetInterval(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const interval = obj.get("interval");
    if (interval != .object) return throwUninitialized(ctx, obj.class_name);
    return NativeResult.borrowed(.{ .object = try periodInterval(ctx, interval.object) });
}

// the count given to the constructor, or null for a period with an end date
fn dpGetRecurrences(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (!periodInitialized(obj)) return NativeResult.scalar(.null);
    const given = Value.toInt(obj.get("recurrences")) - @intFromBool(obj.get("include_start_date").isTruthy()) - @intFromBool(obj.get("include_end_date").isTruthy());
    return NativeResult.scalar(if (given == 0) .null else .{ .int = given });
}

// an InternalIterator over the period (zend_create_internal_iterator_zval)
fn dpGetIterator(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.borrowed(.{ .object = try @import("spl_fixedarray.zig").internalIterator(ctx, obj) });
}

// ---- the period's iterator (date_period_it_*); php keeps the current date
// in the period and the position in the iterator ----

fn stateIndex(state: *PhpObject) i64 {
    const v = state.get("__dp_index");
    return if (v == .int) v.int else 0;
}

// date_period_advance: the period's current date moved on by its interval
fn advancePeriod(ctx: *NativeContext, period: *PhpObject) RuntimeError!void {
    const current = period.get("current");
    const interval = period.get("interval");
    if (current != .object or interval != .object) return;
    const next = try periodStep(ctx, getTimestamp(current.object), objMicros(current.object), &objZoneOr(ctx, current.object), interval.object);
    const moved = try cloneDateObject(ctx, current.object);
    try moved.set(ctx.allocator, "__timestamp", .{ .int = next.ts });
    if (next.us != 0 or moved.get("__microseconds") != .null) try moved.set(ctx.allocator, "__microseconds", .{ .int = next.us });
    try period.set(ctx.allocator, "current", .{ .object = moved });
}

pub fn periodIterRewind(ctx: *NativeContext, period: *PhpObject, state: *PhpObject) RuntimeError!void {
    try state.set(ctx.allocator, "__dp_index", .{ .int = 0 });
    const start = period.get("start");
    if (start != .object) return throwUninitialized(ctx, "DatePeriod");
    try period.set(ctx.allocator, "current", .{ .object = try cloneDateObject(ctx, start.object) });
    if (!period.get("include_start_date").isTruthy()) try advancePeriod(ctx, period);
}

// date_period_it_has_more
pub fn periodIterValid(period: *PhpObject, state: *PhpObject) bool {
    const current = period.get("current");
    if (current != .object) return false;
    const end = period.get("end");
    if (end == .object) {
        const ts = getTimestamp(current.object);
        const end_ts = getTimestamp(end.object);
        if (ts == end_ts) {
            const us = objMicros(current.object);
            const end_us = objMicros(end.object);
            return if (period.get("include_end_date").isTruthy()) us <= end_us else us < end_us;
        }
        return ts < end_ts;
    }
    return stateIndex(state) < Value.toInt(period.get("recurrences"));
}

// the current date as the start date's base class, DateTime or
// DateTimeImmutable
pub fn periodIterCurrent(ctx: *NativeContext, period: *PhpObject) RuntimeError!Value {
    const current = period.get("current");
    if (current != .object) return .null;
    const base: []const u8 = if (ctx.vm.isInstanceOf(current.object.class_name, "DateTimeImmutable")) "DateTimeImmutable" else "DateTime";
    const dt = try ctx.createObject(base);
    try storeInstant(ctx, dt, getTimestamp(current.object), objMicros(current.object), &objZoneOr(ctx, current.object));
    return .{ .object = dt };
}

pub fn periodIterKey(state: *PhpObject) Value {
    return .{ .int = stateIndex(state) };
}

pub fn periodIterNext(ctx: *NativeContext, period: *PhpObject, state: *PhpObject) RuntimeError!void {
    try advancePeriod(ctx, period);
    try state.set(ctx.allocator, "__dp_index", .{ .int = stateIndex(state) + 1 });
}

// date_period_object_to_hash: the seven fields
fn putPeriodFields(ctx: *NativeContext, obj: *PhpObject, table: *PhpArray) RuntimeError!void {
    for (period_fields) |name| try table.set(ctx.allocator, .{ .string = Value.String.borrowed(name) }, obj.get(name));
}

// the object's own properties, then the fields of an initialized period
fn periodProperties(ctx: *NativeContext, obj: *PhpObject, _: object_properties.Purpose) RuntimeError!?*PhpArray {
    const own = try object_properties.ownTable(ctx.vm, obj);
    const table = try ctx.vm.allocArray();
    for (own.entries.items) |entry| if (!isPeriodField(entry.key)) try table.set(ctx.allocator, entry.key, entry.value);
    if (periodInitialized(obj)) try putPeriodFields(ctx, obj, table);
    return table;
}

// the seven fields first, then the object's other properties
fn periodSerialize(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (obj.get("start") != .object) return throwUninitialized(ctx, obj.class_name);
    const out = try ctx.createArray();
    try putPeriodFields(ctx, obj, out);
    const own = try object_properties.ownTable(ctx.vm, obj);
    for (own.entries.items) |entry| if (!out.contains(entry.key)) try out.set(ctx.allocator, entry.key, entry.value);
    return NativeResult.borrowed(.{ .array = out });
}

// php_date_period_initialize_from_hash
fn initializePeriodFromHash(ctx: *NativeContext, obj: *PhpObject, data: *const PhpArray) RuntimeError!bool {
    var have_start = false;
    for ([_][]const u8{ "start", "end", "current" }) |name| {
        const v = hashField(data, name) orelse return false;
        if (v == .object and ctx.vm.isInstanceOf(v.object.class_name, "DateTimeInterface")) {
            if (v.object.get("__timestamp") == .null) return false;
            if (!std.mem.eql(u8, name, "start") and !have_start) return false;
            if (std.mem.eql(u8, name, "start")) have_start = true;
            try obj.set(ctx.allocator, name, .{ .object = try cloneDateObject(ctx, v.object) });
        } else if (v != .null) return false;
    }
    const interval = hashField(data, "interval") orelse return false;
    if (interval != .object or !std.mem.eql(u8, ctx.vm.declaredClassName(interval.object.class_name), "DateInterval") or !intervalInitialized(interval.object)) return false;
    try obj.set(ctx.allocator, "interval", .{ .object = try periodInterval(ctx, interval.object) });
    const recurrences = hashField(data, "recurrences") orelse return false;
    if (recurrences != .int or recurrences.int < 0 or recurrences.int > std.math.maxInt(i32)) return false;
    try obj.set(ctx.allocator, "recurrences", recurrences);
    for ([_][]const u8{ "include_start_date", "include_end_date" }) |name| {
        const v = hashField(data, name) orelse return false;
        if (v != .bool) return false;
        try obj.set(ctx.allocator, name, v);
    }
    try obj.set(ctx.allocator, "__init", .{ .bool = true });
    return true;
}

fn periodUnserialize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const data = try arrayArg(ctx, "DatePeriod::__unserialize", args, "data");
    if (!try initializePeriodFromHash(ctx, obj, data)) return invalidSerialization(ctx, "DatePeriod");
    try restoreCustomProperties(ctx, obj, data, &period_fields);
    return NativeResult.scalar(.null);
}

fn periodSetState(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const data = try arrayArg(ctx, "DatePeriod::__set_state", args, "array");
    const obj = try ctx.createObject("DatePeriod");
    if (!try initializePeriodFromHash(ctx, obj, data)) return invalidSerialization(ctx, "DatePeriod");
    return NativeResult.borrowed(.{ .object = obj });
}

fn periodWakeup(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const own = try object_properties.ownTable(ctx.vm, obj);
    if (!try initializePeriodFromHash(ctx, obj, own)) return invalidSerialization(ctx, "DatePeriod");
    try restoreCustomProperties(ctx, obj, own, &period_fields);
    return NativeResult.scalar(.null);
}

// ---- sunrise, sunset and twilight (date_sun_info, date_sunrise, date_sunset) ----

const astro = @import("date_astro.zig");

// the day timelib_astro_rise_set_altitude works on: the local noon of the
// instant's date in the default zone, and the utc midnight of that date
const SunDay = struct { noon: i64, midnight: i64 };

fn sunDay(ctx: *NativeContext, ts: i64) SunDay {
    const zone = defaultZone(ctx);
    var t = wallTime(ctx.allocator, ts, 0, &zone);
    t.h = 12;
    t.i = 0;
    t.s = 0;
    dp.updateTs(&t, null, parse_db);
    var u = dp.Time{};
    u.y = t.y;
    u.m = t.m;
    u.d = t.d;
    u.h = 0;
    u.i = 0;
    u.s = 0;
    u.us = 0;
    u.z = 0;
    u.dst = 0;
    dp.updateTs(&u, null, parse_db);
    return .{ .noon = t.sse, .midnight = u.sse };
}

fn putSunPair(ctx: *NativeContext, arr: *PhpArray, r: astro.RiseSet, begin: []const u8, end: []const u8) RuntimeError!void {
    switch (r.rc) {
        -1 => {
            try putAssoc(ctx, arr, begin, .{ .bool = false });
            try putAssoc(ctx, arr, end, .{ .bool = false });
        },
        1 => {
            try putAssoc(ctx, arr, begin, .{ .bool = true });
            try putAssoc(ctx, arr, end, .{ .bool = true });
        },
        else => {
            try putAssoc(ctx, arr, begin, .{ .int = r.rise });
            try putAssoc(ctx, arr, end, .{ .int = r.set });
        },
    }
}

fn native_date_sun_info(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "date_sun_info", args);
    const ts = try p.long(0, "timestamp");
    const lat = try p.double(1, "latitude");
    const lon = try p.double(2, "longitude");
    if (!std.math.isFinite(lat)) return p.valueError(1, "latitude", "must be finite");
    if (!std.math.isFinite(lon)) return p.valueError(2, "longitude", "must be finite");
    const day = sunDay(ctx, ts);
    const arr = try ctx.createArray();
    const sun = astro.riseSetAltitude(day.noon, day.midnight, lon, lat, -35.0 / 60.0, true);
    try putSunPair(ctx, arr, sun, "sunrise", "sunset");
    try putAssoc(ctx, arr, "transit", .{ .int = sun.transit });
    try putSunPair(ctx, arr, astro.riseSetAltitude(day.noon, day.midnight, lon, lat, -6.0, false), "civil_twilight_begin", "civil_twilight_end");
    try putSunPair(ctx, arr, astro.riseSetAltitude(day.noon, day.midnight, lon, lat, -12.0, false), "nautical_twilight_begin", "nautical_twilight_end");
    try putSunPair(ctx, arr, astro.riseSetAltitude(day.noon, day.midnight, lon, lat, -18.0, false), "astronomical_twilight_begin", "astronomical_twilight_end");
    return NativeResult.borrowed(.{ .array = arr });
}

// INI_FLT
fn iniFloat(ctx: *NativeContext, name: []const u8, default: []const u8) f64 {
    const raw = ctx.vm.ini_settings.get(name) orelse default;
    return Value.toFloat(.{ .string = Value.String.borrowed(raw) });
}

// php_do_date_sunrise_sunset
fn sunriseSunset(ctx: *NativeContext, args: []const Value, comptime func: []const u8, sunset: bool) RuntimeError!NativeResult {
    const p = Args.init(ctx, func, args);
    const ts = try p.long(0, "timestamp");
    const format = try p.optLong(1, "returnFormat", 1);
    const lat = (try p.doubleOrNull(2, "latitude")) orelse iniFloat(ctx, "date.default_latitude", "31.7667");
    const lon = (try p.doubleOrNull(3, "longitude")) orelse iniFloat(ctx, "date.default_longitude", "35.2333");
    const zenith = (try p.doubleOrNull(4, "zenith")) orelse if (sunset) iniFloat(ctx, "date.sunset_zenith", "90.833333") else iniFloat(ctx, "date.sunrise_zenith", "90.833333");
    const offset_arg = try p.doubleOrNull(5, "utcOffset");
    if (format < 0 or format > 2) return p.valueError(1, "returnFormat", "must be one of SUNFUNCS_RET_TIMESTAMP, SUNFUNCS_RET_STRING, or SUNFUNCS_RET_DOUBLE");
    if (!std.math.isFinite(lat) or !std.math.isFinite(lon)) return NativeResult.scalar(.{ .bool = false });
    // timelib_get_current_offset on a time whose sse is still 0
    const gmt_offset = offset_arg orelse @as(f64, @floatFromInt(idOffset(defaultZone(ctx).name(), 0).offset)) / 3600.0;
    const day = sunDay(ctx, ts);
    const r = astro.riseSetAltitude(day.noon, day.midnight, lon, lat, 90 - zenith, true);
    if (r.rc != 0) return NativeResult.scalar(.{ .bool = false });
    if (format == 0) return NativeResult.scalar(.{ .int = if (sunset) r.set else r.rise });
    var n = (if (sunset) r.h_set.? else r.h_rise.?) + gmt_offset;
    if (n > 24 or n < 0) n -= @floor(n / 24) * 24;
    if (!(n <= 24 and n >= 0)) return NativeResult.scalar(.{ .bool = false });
    if (format == 2) return NativeResult.scalar(.{ .float = n });
    const hours: i32 = @intFromFloat(@trunc(n));
    const minutes: i32 = @intFromFloat(@trunc(60 * (n - @as(f64, @floatFromInt(hours)))));
    var out = std.ArrayListUnmanaged(u8).empty;
    defer out.deinit(ctx.allocator);
    try date_format.padded(&out, ctx.allocator, hours, 2);
    try out.append(ctx.allocator, ':');
    try date_format.padded(&out, ctx.allocator, minutes, 2);
    return NativeResult.copyString(ctx.allocator, out.items);
}

fn native_date_sunrise(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return sunriseSunset(ctx, args, "date_sunrise", false);
}

fn native_date_sunset(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return sunriseSunset(ctx, args, "date_sunset", true);
}

// ---- strftime() and gmstrftime() (php_strftime): the C library's strftime
// over the time's broken-down fields, as php calls it ----

const CTm = if (platform.is_windows) extern struct {
    tm_sec: c_int,
    tm_min: c_int,
    tm_hour: c_int,
    tm_mday: c_int,
    tm_mon: c_int,
    tm_year: c_int,
    tm_wday: c_int,
    tm_yday: c_int,
    tm_isdst: c_int,
} else extern struct {
    tm_sec: c_int,
    tm_min: c_int,
    tm_hour: c_int,
    tm_mday: c_int,
    tm_mon: c_int,
    tm_year: c_int,
    tm_wday: c_int,
    tm_yday: c_int,
    tm_isdst: c_int,
    tm_gmtoff: c_long,
    tm_zone: [*:0]const u8,
};

extern "c" fn strftime(s: [*]u8, max: usize, format: [*:0]const u8, tm: *const CTm) usize;

fn strftimeAs(ctx: *NativeContext, args: []const Value, comptime func: []const u8, gmt: bool) RuntimeError!NativeResult {
    const p = Args.init(ctx, func, args);
    const format = try p.str(0, "format");
    const ts = (try p.longOrNull(1, "timestamp")) orelse platform.timestamp();
    if (format.len == 0) return NativeResult.scalar(.{ .bool = false });
    const t = if (gmt) blk: {
        var g = date_format.Local{ .y = 0, .m = 1, .d = 1, .h = 0, .i = 0, .s = 0, .sse = ts, .localtime = false, .abbr = "GMT" };
        date_format.fieldsAt(ts, 0, &g);
        break :blk g;
    } else defaultLocal(ctx, ts);
    const a = ctx.allocator;
    const zone_z = try a.dupeSentinel(u8, t.abbr, 0);
    defer a.free(zone_z);
    var tm: CTm = undefined;
    tm.tm_sec = @truncate(t.s);
    tm.tm_min = @truncate(t.i);
    tm.tm_hour = @truncate(t.h);
    tm.tm_mday = @truncate(t.d);
    tm.tm_mon = @truncate(t.m - 1);
    tm.tm_year = @truncate(t.y - 1900);
    tm.tm_wday = @truncate(dp.dayOfWeek(t.y, t.m, t.d));
    tm.tm_yday = @truncate(dp.dayOfYear(t.y, t.m, t.d));
    tm.tm_isdst = @intFromBool(t.is_dst);
    if (!platform.is_windows) {
        tm.tm_gmtoff = @intCast(if (gmt) 0 else t.offset);
        tm.tm_zone = zone_z.ptr;
    }
    // the format stops at a nul, as it does for php's call
    const fmt_z = try a.dupeSentinel(u8, format[0 .. std.mem.indexOfScalar(u8, format, 0) orelse format.len], 0);
    defer a.free(fmt_z);
    var buf_len: usize = 256;
    var reallocs: usize = 5;
    var buf = try a.alloc(u8, buf_len);
    defer a.free(buf);
    var real_len = strftime(buf.ptr, buf_len, fmt_z.ptr, &tm);
    while (real_len == buf_len or real_len == 0) {
        buf_len *= 2;
        buf = try a.realloc(buf, buf_len);
        reallocs -= 1;
        if (reallocs == 0) break;
        real_len = strftime(buf.ptr, buf_len, fmt_z.ptr, &tm);
    }
    if (real_len == 0 or real_len == buf_len) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.copyString(a, buf[0..real_len]);
}

fn native_strftime(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return strftimeAs(ctx, args, "strftime", false);
}

fn native_gmstrftime(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return strftimeAs(ctx, args, "gmstrftime", true);
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
    const zone = objZoneOr(ctx, obj);
    const us_v = obj.get("__microseconds");
    const formatted = try formatIn(ctx, ts, if (us_v == .int) us_v.int else 0, &zone, "x-m-d H:i:s.u");
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
    if (objZone(obj)) |zone| try putZoneFields(ctx, &zone, table);
    return table;
}

// __serialize: the date fields first, then the object's own properties
fn dateSerialize(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    _ = try instantOf(ctx, obj);
    const out = try ctx.createArray();
    try putDateFields(ctx, obj, out);
    try appendOwnMissing(ctx, obj, out);
    return NativeResult.borrowed(.{ .array = out });
}

fn timezoneSerialize(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const zone = try zoneOf(ctx, obj);
    const out = try ctx.createArray();
    try putZoneFields(ctx, &zone, out);
    try appendOwnMissing(ctx, obj, out);
    return NativeResult.borrowed(.{ .array = out });
}

fn appendOwnMissing(ctx: *NativeContext, obj: *PhpObject, out: *PhpArray) RuntimeError!void {
    const own = try object_properties.ownTable(ctx.vm, obj);
    for (own.entries.items) |entry| {
        if (!out.contains(entry.key)) try out.set(ctx.allocator, entry.key, entry.value);
    }
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
            // php_date_parse_tzfile: only a database id, quietly
            if (!tzdb.isValid(zone.string.bytes())) return false;
            const parsed = ParseZone.of(zone.string.bytes(), true);
            const instant = (try resolveDate(ctx, date.string.bytes(), parsed, false)) orelse return false;
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
    if (std.mem.indexOfScalar(u8, zone.string.bytes(), 0) != null) return false;
    const parsed = (try timezoneInitialize(ctx, zone.string.bytes(), "", .silent)) orelse return false;
    try setObjZone(ctx, obj, &parsed);
    return true;
}

// the properties a serialized date carries besides its own fields go back
// onto the object
fn restoreCustomProperties(ctx: *NativeContext, obj: *PhpObject, data: *const PhpArray, internal: []const []const u8) RuntimeError!void {
    entries: for (data.entries.items) |entry| {
        if (entry.key != .string or entry.ref != null) continue;
        const key = entry.key.string.bytes();
        for (internal) |name| if (std.mem.eql(u8, key, name)) continue :entries;
        var name = key;
        if (key.len > 0 and key[0] == 0) {
            // update_property: a private property of a class that doesn't
            // exist is dropped
            const end = std.mem.indexOfScalarPos(u8, key, 1, 0) orelse continue;
            const class = key[1..end];
            if (!std.mem.eql(u8, class, "*") and !ctx.vm.classes.contains(class)) continue;
            name = key[end + 1 ..];
        }
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

// Z_PARAM_ARRAY for the hash the restoring methods take
fn arrayArg(ctx: *NativeContext, func: []const u8, args: []const Value, name: []const u8) RuntimeError!*PhpArray {
    if (args.len > 0 and args[0] == .array) return args[0].array;
    return Args.init(ctx, func, args).typeError(0, name, "array");
}

fn dateUnserialize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    _ = try arrayArg(ctx, if (std.mem.eql(u8, dateBaseClass(ctx, obj), "DateTime")) "DateTime::__unserialize" else "DateTimeImmutable::__unserialize", args, "data");
    if (!try initializeDateFromHash(ctx, obj, args[0].array)) return invalidSerialization(ctx, dateBaseClass(ctx, obj));
    try restoreCustomProperties(ctx, obj, args[0].array, &.{ "date", "timezone_type", "timezone" });
    return NativeResult.scalar(.null);
}

fn timezoneUnserialize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    _ = try arrayArg(ctx, "DateTimeZone::__unserialize", args, "data");
    if (!try initializeTimezoneFromHash(ctx, obj, args[0].array)) return invalidSerialization(ctx, "DateTimeZone");
    try restoreCustomProperties(ctx, obj, args[0].array, &.{ "timezone_type", "timezone" });
    return NativeResult.scalar(.null);
}

// __set_state builds the base class, never a subclass
fn dateSetStateOf(ctx: *NativeContext, args: []const Value, comptime class: []const u8) RuntimeError!NativeResult {
    const data = try arrayArg(ctx, class ++ "::__set_state", args, "array");
    const obj = try ctx.createObject(class);
    if (!try initializeDateFromHash(ctx, obj, data)) return invalidSerialization(ctx, class);
    return NativeResult.borrowed(.{ .object = obj });
}

fn dateSetState(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return dateSetStateOf(ctx, args, "DateTime");
}

fn immutableSetState(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return dateSetStateOf(ctx, args, "DateTimeImmutable");
}

fn timezoneSetState(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const data = try arrayArg(ctx, "DateTimeZone::__set_state", args, "array");
    const obj = try ctx.createObject("DateTimeZone");
    if (!try initializeTimezoneFromHash(ctx, obj, data)) return invalidSerialization(ctx, "DateTimeZone");
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

// the zone of an optional DateTimeZone argument
fn tzArgZone(args: []const Value, idx: usize) ?ParseZone {
    if (args.len <= idx or args[idx] != .object) return null;
    return objZone(args[idx].object);
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

// date() and DateTimeInterface::format() over date_format.zig: the time's
// wall-clock fields in its zone and the offset in effect
pub fn formatTimestamp(ctx: *NativeContext, timestamp: i64, format: []const u8) RuntimeError!NativeResult {
    return formatIn(ctx, timestamp, 0, &defaultZone(ctx), format);
}

fn localOf(ts: i64, us: i64, zone: *const ParseZone) date_format.Local {
    var t = date_format.Local{ .y = 0, .m = 1, .d = 1, .h = 0, .i = 0, .s = 0, .us = us, .sse = ts, .zone_type = zone.kind };
    switch (zone.kind) {
        dp.ZONETYPE_OFFSET => t.offset = zone.z,
        dp.ZONETYPE_ABBR => {
            t.offset = zone.z + zone.dst * 3600;
            t.is_dst = zone.dst != 0;
            t.abbr = zone.name();
        },
        else => {
            t.tz_name = zone.name();
            if (tzdb.info(zone.name())) |inf| if (inf.fetch(ts)) |f| {
                t.offset = f.t.offset;
                t.is_dst = f.t.isdst;
                t.abbr = inf.abbr(f.t);
            };
        },
    }
    date_format.fieldsAt(ts, t.offset, &t);
    return t;
}

fn formatIn(ctx: *NativeContext, ts: i64, us: i64, zone: *const ParseZone, format: []const u8) RuntimeError!NativeResult {
    const t = localOf(ts, us, zone);
    const out = date_format.format(ctx.allocator, format, &t) catch return error.OutOfMemory;
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

// gmdate(): utc, with the zone characters printing utc's
fn formatGmt(ctx: *NativeContext, ts: i64, format: []const u8) RuntimeError!NativeResult {
    var t = date_format.Local{ .y = 0, .m = 1, .d = 1, .h = 0, .i = 0, .s = 0, .sse = ts, .localtime = false };
    date_format.fieldsAt(ts, 0, &t);
    const out = date_format.format(ctx.allocator, format, &t) catch return error.OutOfMemory;
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

// a DateInterval as timelib_rel_time. f holds the microseconds as a float;
// rounding recovers the integer every native interval was made from. an
// interval from a date string keeps its weekday and special parts only in the
// string, so they are read back from it
const IntervalSpec = struct { rel: dp.Rel, invert: bool, wall: bool };

fn intervalSpec(ctx: *NativeContext, iv: *PhpObject) RuntimeError!IntervalSpec {
    var rel = dp.Rel{};
    if (iv.get("__date_string") == .string) {
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
    const zone = objZoneOr(ctx, obj);
    const us_v = obj.get("__microseconds");
    return wallTime(ctx.allocator, getTimestamp(obj), if (us_v == .int) us_v.int else 0, &zone);
}

fn storeTime(ctx: *NativeContext, obj: *PhpObject, t: *const dp.Time) RuntimeError!void {
    const zone = objZoneOr(ctx, obj);
    try storeInstant(ctx, obj, t.sse, t.us, &zone);
}

// one DatePeriod step from an instant in a zone
fn periodStep(ctx: *NativeContext, ts: i64, us: i64, zone: *const ParseZone, iv: *PhpObject) RuntimeError!struct { ts: i64, us: i64 } {
    const spec = try intervalSpec(ctx, iv);
    var t = wallTime(ctx.allocator, ts, us, zone);
    dp.periodAdvance(&t, &spec.rel, parse_db);
    return .{ .ts = t.sse, .us = t.us };
}

// the setters (setDate, setTime, setISODate) work on the wall-clock time in
// the object's own timezone: split the instant into local fields, change some,
// and turn the result back into an instant with the offset in effect then

// a date or DateTimeZone object's zone: `__timezone` names it, and
// `__zone_type` marks an id whose name alone reads as an abbreviation (the
// default zone "CET" is the id, a DateTimeZone("CET") the abbreviation)
fn objZone(obj: *PhpObject) ?ParseZone {
    const v = obj.get("__timezone");
    if (v != .string) return null;
    const k = obj.get("__zone_type");
    return ParseZone.of(v.string.bytes(), k == .int and k.int == dp.ZONETYPE_ID);
}

fn objZoneOr(ctx: *NativeContext, obj: *PhpObject) ParseZone {
    return objZone(obj) orelse defaultZone(ctx);
}

// the default zone is always an id
fn defaultZone(ctx: *NativeContext) ParseZone {
    return ParseZone.of(ctx.vm.default_tz_name, true);
}

fn setObjZone(ctx: *NativeContext, obj: *PhpObject, zone: *const ParseZone) RuntimeError!void {
    const cur = obj.get("__timezone");
    if (cur != .string or !std.mem.eql(u8, cur.string.bytes(), zone.name())) {
        try obj.set(ctx.allocator, "__timezone", .{ .string = Value.String.borrowed(internZoneName(zone.name())) });
    }
    const marked = zone.kind == dp.ZONETYPE_ID and ParseZone.of(zone.name(), false).kind != dp.ZONETYPE_ID;
    if (marked) {
        try obj.set(ctx.allocator, "__zone_type", .{ .int = dp.ZONETYPE_ID });
    } else if (obj.get("__zone_type") != .null) {
        try obj.set(ctx.allocator, "__zone_type", .null);
    }
}

// the class a static factory was called on (Carbon::createFromFormat makes a
// Carbon): the static call leaves it on the calling frame, and anything that
// isn't a subclass of the factory's own class is not it
fn staticClass(ctx: *NativeContext, base: []const u8) []const u8 {
    if (ctx.vm.frame_count == 0) return base;
    const called = ctx.vm.currentFrame().called_class orelse return base;
    return if (ctx.vm.isInstanceOf(called, base)) ctx.vm.declaredClassName(called) else base;
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}
// ---- DateTime and DateTimeImmutable (php_date.c) ----

const CompareKind = enum { date, zone, interval, period };

fn compareKind(ctx: *NativeContext, v: Value) ?CompareKind {
    if (v != .object) return null;
    const class = v.object.class_name;
    if (ctx.vm.isInstanceOf(class, "DateTime") or ctx.vm.isInstanceOf(class, "DateTimeImmutable")) return .date;
    if (ctx.vm.isInstanceOf(class, "DateTimeZone")) return .zone;
    if (ctx.vm.isInstanceOf(class, "DateInterval")) return .interval;
    if (ctx.vm.isInstanceOf(class, "DatePeriod")) return .period;
    return null;
}

fn ownNonPeriod(ctx: *NativeContext, obj: *PhpObject) RuntimeError!*PhpArray {
    const own = try object_properties.ownTable(ctx.vm, obj);
    const out = try ctx.createArray();
    for (own.entries.items) |entry| if (!isPeriodField(entry.key)) try out.set(ctx.allocator, entry.key, entry.value);
    return out;
}

fn throwPlain(ctx: *NativeContext, class: []const u8, msg: []const u8) RuntimeError {
    try ctx.vm.setPendingException(class, msg);
    return error.RuntimeError;
}

// the compare handlers of the date classes; objects of different kinds fall
// back to php's standard object comparison
fn dateBinop(ctx: *NativeContext, op: vm_mod.NativeBinop, a: Value, b: Value) RuntimeError!?Value {
    if (op != .compare) return null;
    const ka = compareKind(ctx, a) orelse return null;
    const kb = compareKind(ctx, b) orelse return null;
    if (ka != kb) return null;
    // zend_compare finds an object equal to itself before any handler runs
    if (a.object == b.object) return .{ .int = 0 };
    switch (ka) {
        .date => {
            const ta = a.object.get("__timestamp");
            const tb = b.object.get("__timestamp");
            if (ta == .null or tb == .null) return throwPlain(ctx, "DateObjectError", "Trying to compare an incomplete DateTime or DateTimeImmutable object");
            const sa = Value.toInt(ta);
            const sb = Value.toInt(tb);
            if (sa != sb) return .{ .int = if (sa < sb) -1 else 1 };
            const ua = objMicros(a.object);
            const ub = objMicros(b.object);
            return .{ .int = if (ua == ub) 0 else if (ua < ub) -1 else 1 };
        },
        .zone => {
            const za = objZone(a.object);
            const zb = objZone(b.object);
            if (za == null or zb == null) return throwPlain(ctx, "DateObjectError", "Trying to compare uninitialized DateTimeZone objects");
            if (za.?.kind != zb.?.kind) return throwPlain(ctx, "DateException", "Cannot compare two different kinds of DateTimeZone objects");
            const same = if (za.?.kind == dp.ZONETYPE_OFFSET) za.?.z == zb.?.z else std.mem.eql(u8, za.?.name(), zb.?.name());
            return .{ .int = if (same) 0 else 1 };
        },
        .interval => {
            try ctx.vm.emitWarning("Cannot compare DateInterval objects");
            return .{ .int = 1 };
        },
        // the standard comparison, over what php keeps as properties: the
        // seven fields are virtual
        .period => {
            if (!std.mem.eql(u8, a.object.class_name, b.object.class_name)) return .{ .int = 1 };
            const oa = try ownNonPeriod(ctx, a.object);
            const ob = try ownNonPeriod(ctx, b.object);
            return .{ .int = Value.compare(.{ .array = oa }, .{ .array = ob }) };
        },
    }
}

// a date object's time as timelib holds it, or DateObjectError when its
// constructor never ran
fn timeOf(ctx: *NativeContext, obj: *PhpObject) RuntimeError!dp.Time {
    _ = try instantOf(ctx, obj);
    return objTime(ctx, obj);
}

fn objMicros(obj: *PhpObject) i64 {
    const v = obj.get("__microseconds");
    return if (v == .int) v.int else 0;
}

// an interval made by a constructor, a factory, diff() or unserialization
fn markInterval(ctx: *NativeContext, obj: *PhpObject) RuntimeError!void {
    try obj.set(ctx.allocator, "__init", .{ .bool = true });
}

fn intervalOf(ctx: *NativeContext, obj: *PhpObject) RuntimeError!*PhpObject {
    if (obj.get("__init") != .bool) return throwUninitialized(ctx, obj.class_name);
    return obj;
}

// an optional DateTimeZone argument; one whose constructor never ran is an
// Error, as php_date_initialize finds it without a zone type
fn zoneArg(ctx: *NativeContext, p: Args, index: usize, name: []const u8) RuntimeError!?ParseZone {
    const tz = (try p.objectOrNull(index, name, "DateTimeZone")) orelse return null;
    return objZone(tz) orelse {
        try ctx.vm.setPendingException("Error", "The DateTimeZone object has not been correctly initialized by its constructor");
        return error.RuntimeError;
    };
}

fn constructAs(comptime class: []const u8) NativeFn {
    return struct {
        fn call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
            const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
            const p = Args.init(ctx, class ++ "::__construct", args);
            const input = try p.optStr(0, "datetime", "now");
            const zone = try zoneArg(ctx, p, 1, "timezone");
            const instant = (try resolveDateWith(ctx, input, null, zone, true)) orelse return error.RuntimeError;
            try storeInstant(ctx, obj, instant.ts, instant.us, &instant.zone);
            return NativeResult.scalar(.null);
        }
    }.call;
}

// date_create() and date_create_immutable(): false for a string that doesn't parse
fn createAs(comptime func: []const u8, comptime class: []const u8) NativeFn {
    return struct {
        fn call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
            const p = Args.init(ctx, func, args);
            const input = try p.optStr(0, "datetime", "now");
            const zone = try zoneArg(ctx, p, 1, "timezone");
            const instant = (try resolveDateWith(ctx, input, null, zone, false)) orelse return NativeResult.scalar(.{ .bool = false });
            const obj = try ctx.createObject(class);
            try storeInstant(ctx, obj, instant.ts, instant.us, &instant.zone);
            return NativeResult.borrowed(.{ .object = obj });
        }
    }.call;
}

// createFromFormat() and its procedural aliases: the object is of the class
// the static call named
fn createFromFormatAs(comptime func: []const u8, comptime class: []const u8) NativeFn {
    return struct {
        fn call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
            const p = Args.init(ctx, func, args);
            const format = try p.str(0, "format");
            const input = try p.str(1, "datetime");
            try rejectNulBytes(ctx, func, 2, "datetime", input);
            const zone = try zoneArg(ctx, p, 2, "timezone");
            const instant = (try resolveDateWith(ctx, input, format, zone, false)) orelse return NativeResult.scalar(.{ .bool = false });
            const obj = try ctx.createObject(staticClass(ctx, class));
            try storeInstant(ctx, obj, instant.ts, instant.us, &instant.zone);
            return NativeResult.borrowed(.{ .object = obj });
        }
    }.call;
}

// createFromImmutable(), createFromMutable(), createFromInterface(): a copy of
// another date object's time in the called class
fn createFromObjectAs(comptime func: []const u8, comptime arg_class: []const u8, comptime class: []const u8) NativeFn {
    return struct {
        fn call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
            const src = try Args.init(ctx, func, args).object(0, "object", arg_class);
            const ts = try instantOf(ctx, src);
            const obj = try ctx.createObject(staticClass(ctx, class));
            try storeInstant(ctx, obj, ts, objMicros(src), &objZoneOr(ctx, src));
            return NativeResult.borrowed(.{ .object = obj });
        }
    }.call;
}

// createFromTimestamp(): an int or float timestamp, in +00:00
fn createFromTimestampAs(comptime func: []const u8, comptime class: []const u8) NativeFn {
    return struct {
        fn call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
            const p = Args.init(ctx, func, args);
            var v = args[0];
            if (v == .string or v == .bool or v == .null or v == .undef) {
                if (v == .string and Value.isNumericString(v.string.bytes())) {
                    const f = Value.toFloat(v);
                    const n = Value.toInt(v);
                    v = if (f == @trunc(f) and @abs(f) < 9.2e18 and std.mem.indexOfAny(u8, v.string.bytes(), ".eE") == null) .{ .int = n } else .{ .float = f };
                } else if (v == .bool) {
                    v = .{ .int = @intFromBool(v.bool) };
                } else if (v == .null or v == .undef) {
                    _ = try p.long(0, "timestamp");
                    v = .{ .int = 0 };
                } else return p.typeError(0, "timestamp", "int|float");
            } else if (v != .int and v != .float) return p.typeError(0, "timestamp", "int|float");
            var sec: i64 = 0;
            var usec: i64 = 0;
            if (v == .int) {
                sec = v.int;
            } else {
                const ts = v.float;
                const whole = @trunc(ts);
                const range = std.fmt.allocPrint(ctx.allocator, "{s}(): Argument #1 ($timestamp) must be a finite number between {d} and {d}.999999, {s} given", .{ func, std.math.minInt(i64), std.math.maxInt(i64), fmtG(ts) }) catch return error.OutOfMemory;
                defer ctx.allocator.free(range);
                if (std.math.isNan(whole) or !(whole >= -9223372036854775808.0 and whole < 9223372036854775808.0)) {
                    try ctx.vm.setPendingException("DateRangeError", range);
                    return error.RuntimeError;
                }
                sec = @intFromFloat(whole);
                usec = @intFromFloat(@round(@rem(ts, 1) * 1000000));
                if (@abs(usec) == 1000000) {
                    sec += if (usec > 0) 1 else -1;
                    usec = 0;
                }
                if (usec < 0) {
                    if (sec == std.math.minInt(i64)) {
                        try ctx.vm.setPendingException("DateRangeError", range);
                        return error.RuntimeError;
                    }
                    sec -= 1;
                    usec += 1000000;
                }
            }
            const obj = try ctx.createObject(staticClass(ctx, class));
            const zone = ParseZone.of("+00:00", false);
            try storeInstant(ctx, obj, sec, usec, &zone);
            return NativeResult.borrowed(.{ .object = obj });
        }
    }.call;
}

// printf's %g, as php's messages print a float
fn fmtG(f: f64) []const u8 {
    const S = struct {
        threadlocal var buf: [64]u8 = undefined;
    };
    return @import("formatted_print.zig").gcvt(f, 6, '.', 'e', &S.buf);
}

// ---- the operations, for DateTime's methods, DateTimeImmutable's (on a
// clone) and the procedural functions ----

const Mode = enum { mutable, immutable, procedural };
// false makes a procedural function return false
const DateOp = fn (*NativeContext, *PhpObject, Args, Mode) RuntimeError!bool;

fn dateMethod(comptime func: []const u8, comptime op: DateOp, comptime mode: Mode) NativeFn {
    return struct {
        fn call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
            const this = getThis(ctx) orelse return NativeResult.scalar(.null);
            const p = Args.init(ctx, func, args);
            const target = if (mode == .immutable) try cloneDateObject(ctx, this) else this;
            _ = try op(ctx, target, p, mode);
            return NativeResult.borrowed(.{ .object = target });
        }
    }.call;
}

fn dateFunction(comptime func: []const u8, comptime op: DateOp) NativeFn {
    return struct {
        fn call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
            const obj = try Args.init(ctx, func, args).object(0, "object", "DateTime");
            var p = Args.init(ctx, func, args[1..]);
            p.shift = 1;
            if (!try op(ctx, obj, p, .procedural)) return NativeResult.scalar(.{ .bool = false });
            return NativeResult.borrowed(.{ .object = obj });
        }
    }.call;
}

fn modifyOp(ctx: *NativeContext, obj: *PhpObject, p: Args, mode: Mode) RuntimeError!bool {
    const modifier = try p.str(0, "modifier");
    _ = try instantOf(ctx, obj);
    var prefix_buf: [64]u8 = undefined;
    const prefix = std.fmt.bufPrint(&prefix_buf, "{s}(): ", .{p.func}) catch "";
    return modifyDateObject(ctx, obj, modifier, prefix, mode != .procedural);
}

fn addOp(ctx: *NativeContext, obj: *PhpObject, p: Args, _: Mode) RuntimeError!bool {
    const iv = try p.object(0, "interval", "DateInterval");
    var t = try timeOf(ctx, obj);
    const spec = try intervalSpec(ctx, try intervalOf(ctx, iv));
    if (spec.wall) dp.addWall(&t, &spec.rel, spec.invert, 1, parse_db) else dp.add(&t, &spec.rel, spec.invert, parse_db);
    try storeTime(ctx, obj, &t);
    return true;
}

// a weekday or special interval can't be subtracted: the methods throw,
// date_sub() warns and leaves the date as it was
fn subOp(ctx: *NativeContext, obj: *PhpObject, p: Args, mode: Mode) RuntimeError!bool {
    const iv = try p.object(0, "interval", "DateInterval");
    var t = try timeOf(ctx, obj);
    const spec = try intervalSpec(ctx, try intervalOf(ctx, iv));
    if (spec.rel.have_weekday_relative or spec.rel.have_special_relative) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): Only non-special relative time specifications are supported for subtraction", .{p.func});
        defer ctx.allocator.free(msg);
        if (mode == .procedural) {
            try ctx.vm.emitWarning(msg);
            return true;
        }
        try ctx.vm.setPendingException("DateInvalidOperationException", msg);
        return error.RuntimeError;
    }
    if (spec.wall) dp.addWall(&t, &spec.rel, spec.invert, -1, parse_db) else dp.sub(&t, &spec.rel, spec.invert, parse_db);
    try storeTime(ctx, obj, &t);
    return true;
}

fn setTimezoneOp(ctx: *NativeContext, obj: *PhpObject, p: Args, _: Mode) RuntimeError!bool {
    const tz = try p.object(0, "timezone", "DateTimeZone");
    _ = try instantOf(ctx, obj);
    if (objZone(tz)) |zone| try setObjZone(ctx, obj, &zone);
    return true;
}

fn setTimeOp(ctx: *NativeContext, obj: *PhpObject, p: Args, _: Mode) RuntimeError!bool {
    const h = try p.long(0, "hour");
    const i = try p.long(1, "minute");
    const s = try p.optLong(2, "second", 0);
    const us = try p.optLong(3, "microsecond", 0);
    var t = try timeOf(ctx, obj);
    t.h = h;
    t.i = i;
    t.s = s;
    t.us = us;
    dp.updateTs(&t, null, parse_db);
    try storeTime(ctx, obj, &t);
    return true;
}

fn setDateOp(ctx: *NativeContext, obj: *PhpObject, p: Args, _: Mode) RuntimeError!bool {
    const y = try p.long(0, "year");
    const m = try p.long(1, "month");
    const d = try p.long(2, "day");
    var t = try timeOf(ctx, obj);
    t.y = y;
    t.m = m;
    t.d = d;
    dp.updateTs(&t, null, parse_db);
    try storeTime(ctx, obj, &t);
    return true;
}

fn setISODateOp(ctx: *NativeContext, obj: *PhpObject, p: Args, _: Mode) RuntimeError!bool {
    const y = try p.long(0, "year");
    const w = try p.long(1, "week");
    const d = try p.optLong(2, "dayOfWeek", 1);
    var t = try timeOf(ctx, obj);
    t.y = y;
    t.m = 1;
    t.d = 1;
    t.relative = .{};
    t.relative.d = dp.daynrFromWeeknr(y, w, d);
    t.have_relative = true;
    dp.updateTs(&t, null, parse_db);
    try storeTime(ctx, obj, &t);
    return true;
}

fn setTimestampOp(ctx: *NativeContext, obj: *PhpObject, p: Args, _: Mode) RuntimeError!bool {
    const ts = try p.long(0, "timestamp");
    _ = try instantOf(ctx, obj);
    try storeInstant(ctx, obj, ts, 0, &objZoneOr(ctx, obj));
    return true;
}

fn setMicrosecondOp(ctx: *NativeContext, obj: *PhpObject, p: Args, _: Mode) RuntimeError!bool {
    const us = try p.long(0, "microsecond");
    if (us < 0 or us > 999999) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): Argument #1 ($microsecond) must be between 0 and 999999, {d} given", .{ p.func, us });
        defer ctx.allocator.free(msg);
        try ctx.vm.setPendingException("DateRangeError", msg);
        return error.RuntimeError;
    }
    _ = try instantOf(ctx, obj);
    try obj.set(ctx.allocator, "__microseconds", .{ .int = us });
    return true;
}

const dtModify = dateMethod("DateTime::modify", modifyOp, .mutable);
const dtAdd = dateMethod("DateTime::add", addOp, .mutable);
const dtSub = dateMethod("DateTime::sub", subOp, .mutable);
const dtSetTimezone = dateMethod("DateTime::setTimezone", setTimezoneOp, .mutable);
const dtSetTime = dateMethod("DateTime::setTime", setTimeOp, .mutable);
const dtSetDate = dateMethod("DateTime::setDate", setDateOp, .mutable);
const dtSetISODate = dateMethod("DateTime::setISODate", setISODateOp, .mutable);
const dtSetTimestamp = dateMethod("DateTime::setTimestamp", setTimestampOp, .mutable);
const dtSetMicrosecond = dateMethod("DateTime::setMicrosecond", setMicrosecondOp, .mutable);
const dtiModify = dateMethod("DateTimeImmutable::modify", modifyOp, .immutable);
const dtiAdd = dateMethod("DateTimeImmutable::add", addOp, .immutable);
const dtiSub = dateMethod("DateTimeImmutable::sub", subOp, .immutable);
const dtiSetTimezone = dateMethod("DateTimeImmutable::setTimezone", setTimezoneOp, .immutable);
const dtiSetTime = dateMethod("DateTimeImmutable::setTime", setTimeOp, .immutable);
const dtiSetDate = dateMethod("DateTimeImmutable::setDate", setDateOp, .immutable);
const dtiSetISODate = dateMethod("DateTimeImmutable::setISODate", setISODateOp, .immutable);
const dtiSetTimestamp = dateMethod("DateTimeImmutable::setTimestamp", setTimestampOp, .immutable);
const dtiSetMicrosecond = dateMethod("DateTimeImmutable::setMicrosecond", setMicrosecondOp, .immutable);
const native_date_modify = dateFunction("date_modify", modifyOp);
const native_date_add = dateFunction("date_add", addOp);
const native_date_sub = dateFunction("date_sub", subOp);
const native_date_timezone_set = dateFunction("date_timezone_set", setTimezoneOp);
const native_date_time_set = dateFunction("date_time_set", setTimeOp);
const native_date_date_set = dateFunction("date_date_set", setDateOp);
const native_date_isodate_set = dateFunction("date_isodate_set", setISODateOp);
const native_date_timestamp_set = dateFunction("date_timestamp_set", setTimestampOp);

// ---- what DateTimeInterface reads ----

fn formatImpl(ctx: *NativeContext, obj: *PhpObject, p: Args) RuntimeError!NativeResult {
    const format = try p.str(0, "format");
    const ts = try instantOf(ctx, obj);
    return formatIn(ctx, ts, objMicros(obj), &objZoneOr(ctx, obj), format);
}

fn getTimestampImpl(ctx: *NativeContext, obj: *PhpObject, _: Args) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = try instantOf(ctx, obj) });
}

fn getTimezoneImpl(ctx: *NativeContext, obj: *PhpObject, _: Args) RuntimeError!NativeResult {
    _ = try instantOf(ctx, obj);
    const tz_obj = try ctx.createObject("DateTimeZone");
    try setObjZone(ctx, tz_obj, &objZoneOr(ctx, obj));
    return NativeResult.borrowed(.{ .object = tz_obj });
}

fn getOffsetImpl(ctx: *NativeContext, obj: *PhpObject, _: Args) RuntimeError!NativeResult {
    const ts = try instantOf(ctx, obj);
    return NativeResult.scalar(.{ .int = objZoneOr(ctx, obj).totalOffset(ctx.allocator, ts) });
}

fn getMicrosecondImpl(ctx: *NativeContext, obj: *PhpObject, _: Args) RuntimeError!NativeResult {
    _ = try instantOf(ctx, obj);
    return NativeResult.scalar(.{ .int = objMicros(obj) });
}

fn diffImpl(ctx: *NativeContext, obj: *PhpObject, p: Args) RuntimeError!NativeResult {
    const other = try p.object(0, "targetObject", "DateTimeInterface");
    const absolute = try p.boolean(1, "absolute", false);
    const one = try timeOf(ctx, obj);
    const two = try timeOf(ctx, other);
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
    try markInterval(ctx, interval);
    return NativeResult.borrowed(.{ .object = interval });
}

const dtFormat = objMethod("DateTime::format", formatImpl);
const dtGetTimestamp = objMethod("DateTime::getTimestamp", getTimestampImpl);
const dtGetTimezone = objMethod("DateTime::getTimezone", getTimezoneImpl);
const dtGetOffset = objMethod("DateTime::getOffset", getOffsetImpl);
const dtGetMicrosecond = objMethod("DateTime::getMicrosecond", getMicrosecondImpl);
const dtDiff = objMethod("DateTime::diff", diffImpl);
const dtiFormat = objMethod("DateTimeImmutable::format", formatImpl);
const dtiGetTimestamp = objMethod("DateTimeImmutable::getTimestamp", getTimestampImpl);
const dtiGetTimezone = objMethod("DateTimeImmutable::getTimezone", getTimezoneImpl);
const dtiGetOffset = objMethod("DateTimeImmutable::getOffset", getOffsetImpl);
const dtiGetMicrosecond = objMethod("DateTimeImmutable::getMicrosecond", getMicrosecondImpl);
const dtiDiff = objMethod("DateTimeImmutable::diff", diffImpl);
const native_date_format = objFunction("date_format", "DateTimeInterface", formatImpl);
const native_date_timestamp_get = objFunction("date_timestamp_get", "DateTimeInterface", getTimestampImpl);
const native_date_timezone_get = objFunction("date_timezone_get", "DateTimeInterface", getTimezoneImpl);
const native_date_offset_get = objFunction("date_offset_get", "DateTimeInterface", getOffsetImpl);
const native_date_diff = objFunction("date_diff", "DateTimeInterface", diffImpl);

const dtConstruct = constructAs("DateTime");
const dtiConstruct = constructAs("DateTimeImmutable");
const native_date_create = createAs("date_create", "DateTime");
const native_date_create_immutable = createAs("date_create_immutable", "DateTimeImmutable");
const dtCreateFromFormat = createFromFormatAs("DateTime::createFromFormat", "DateTime");
const dtiCreateFromFormat = createFromFormatAs("DateTimeImmutable::createFromFormat", "DateTimeImmutable");
const native_date_create_from_format = createFromFormatAs("date_create_from_format", "DateTime");
const native_date_create_immutable_from_format = createFromFormatAs("date_create_immutable_from_format", "DateTimeImmutable");
const dtCreateFromImmutable = createFromObjectAs("DateTime::createFromImmutable", "DateTimeImmutable", "DateTime");
const dtCreateFromInterface = createFromObjectAs("DateTime::createFromInterface", "DateTimeInterface", "DateTime");
const dtiCreateFromMutable = createFromObjectAs("DateTimeImmutable::createFromMutable", "DateTime", "DateTimeImmutable");
const dtiCreateFromInterface = createFromObjectAs("DateTimeImmutable::createFromInterface", "DateTimeInterface", "DateTimeImmutable");
const dtCreateFromTimestamp = createFromTimestampAs("DateTime::createFromTimestamp", "DateTime");
const dtiCreateFromTimestamp = createFromTimestampAs("DateTimeImmutable::createFromTimestamp", "DateTimeImmutable");

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
    const name = try Args.init(ctx, "DateTimeZone::__construct", args).str(0, "timezone");
    try rejectNulBytes(ctx, "DateTimeZone::__construct", 1, "timezone", name);
    const zone = (try timezoneInitialize(ctx, name, "DateTimeZone::__construct(): ", .throw_)) orelse return error.RuntimeError;
    try setObjZone(ctx, obj, &zone);
    return NativeResult.scalar(.null);
}

// timezone_initialize: a zone string read the way the date parser reads one,
// so "cest" is the abbreviation CEST, "+0530" the offset +05:30, and anything
// left over makes it a bad timezone
const Report = enum { throw_, warn, silent };

fn timezoneInitialize(ctx: *NativeContext, name: []const u8, prefix: []const u8, report: Report) RuntimeError!?ParseZone {
    const zp = dp.parseZoneString(name, parse_db);
    var what: ?[]const u8 = null;
    if (zp.time.z >= 100 * 3600 or zp.time.z <= -100 * 3600) {
        what = "Timezone offset is out of range";
    } else if (zp.not_found or zp.rest != 0 or std.mem.indexOfScalar(u8, name, 0) != null) {
        what = "Unknown or bad timezone";
    }
    if (what) |w| {
        if (report == .silent) return null;
        const msg = std.fmt.allocPrint(ctx.allocator, "{s}{s} ({s})", .{ prefix, w, name }) catch return error.OutOfMemory;
        defer ctx.allocator.free(msg);
        if (report == .throw_) {
            try ctx.vm.setPendingException("DateInvalidTimeZoneException", msg);
        } else {
            try ctx.vm.emitWarning(msg);
        }
        return null;
    }
    return ParseZone.ofTime(&zp.time);
}

const tz_groups = [_]struct { bit: i64, prefix: []const u8 }{
    .{ .bit = 0x001, .prefix = "Africa/" },
    .{ .bit = 0x002, .prefix = "America/" },
    .{ .bit = 0x004, .prefix = "Antarctica/" },
    .{ .bit = 0x008, .prefix = "Arctic/" },
    .{ .bit = 0x010, .prefix = "Asia/" },
    .{ .bit = 0x020, .prefix = "Atlantic/" },
    .{ .bit = 0x040, .prefix = "Australia/" },
    .{ .bit = 0x080, .prefix = "Europe/" },
    .{ .bit = 0x100, .prefix = "Indian/" },
    .{ .bit = 0x200, .prefix = "Pacific/" },
    .{ .bit = 0x400, .prefix = "UTC" },
};
const tz_group_all_w_bc: i64 = 0x0FFF;
const tz_per_country: i64 = 0x1000;

fn tzIdAllowed(id: []const u8, what: i64) bool {
    for (tz_groups) |g| {
        if (what & g.bit != 0 and std.ascii.startsWithIgnoreCase(id, g.prefix)) return true;
    }
    return false;
}

// timezone_identifiers_list() and DateTimeZone::listIdentifiers()
fn listIdentifiersAs(ctx: *NativeContext, args: []const Value, func: []const u8) RuntimeError!NativeResult {
    const p = string_ports.Args.init(ctx, func, args);
    const what: i64 = if (p.has(0)) try p.long(0, "timezoneGroup") else 0x07FF;
    const country = try p.strOrNull(1, "countryCode");
    if (what == tz_per_country and (country == null or country.?.len != 2)) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): Argument #2 ($countryCode) must be a two-letter ISO 3166-1 compatible country code when argument #1 ($timezoneGroup) is DateTimeZone::PER_COUNTRY", .{func});
        defer ctx.allocator.free(msg);
        try ctx.vm.setPendingException("ValueError", msg);
        return error.RuntimeError;
    }
    const arr = try ctx.createArray();
    var it = tzdb.identifiers();
    while (it.next()) |id| {
        const take = if (what == tz_per_country)
            id.country_code[0] == country.?[0] and id.country_code[1] == country.?[1]
        else
            what == tz_group_all_w_bc or (tzIdAllowed(id.name, what) and id.canonical);
        if (take) try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(id.name) });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn dtzListIdentifiers(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return listIdentifiersAs(ctx, args, "DateTimeZone::listIdentifiers");
}

fn native_timezone_identifiers_list(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return listIdentifiersAs(ctx, args, "timezone_identifiers_list");
}

// timezone_abbreviations_list(): timelib's abbreviation table, grouped by name
fn dtzListAbbreviations(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    for (tz_abbr_table.entries) |e| {
        const key: PhpArray.Key = .{ .string = Value.String.borrowed(e.abbr) };
        var list = arr.get(key);
        if (list != .array) {
            list = .{ .array = try ctx.createArray() };
            try arr.set(ctx.allocator, key, list);
        }
        const entry = try ctx.createArray();
        try entry.set(ctx.allocator, .{ .string = Value.String.borrowed("dst") }, .{ .bool = e.dst });
        try entry.set(ctx.allocator, .{ .string = Value.String.borrowed("offset") }, .{ .int = e.offset });
        try entry.set(ctx.allocator, .{ .string = Value.String.borrowed("timezone_id") }, if (e.id) |id| .{ .string = Value.String.borrowed(id) } else .null);
        try list.array.append(ctx.allocator, .{ .array = entry });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

// timezone_name_from_abbr(): timelib's abbr_search
fn native_timezone_name_from_abbr(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = string_ports.Args.init(ctx, "timezone_name_from_abbr", args);
    const abbr = try p.str(0, "abbr");
    const offset: i64 = if (p.has(1)) try p.long(1, "utcOffset") else -1;
    const isdst: i64 = if (p.has(2)) try p.long(2, "isDST") else -1;
    const id = dp.abbrSearchFull(abbr, offset, isdst) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.copyString(ctx.allocator, id);
}

fn native_timezone_version_get(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.copyString(ctx.allocator, tzdb.version());
}

// ---- methods and their procedural aliases ----

const Args = string_ports.Args;
const NativeFn = fn (*NativeContext, []const Value) RuntimeError!NativeResult;
const ObjImpl = fn (*NativeContext, *PhpObject, Args) RuntimeError!NativeResult;

// a method: `func` names it in messages ("DateTimeZone::getOffset")
fn objMethod(comptime func: []const u8, comptime impl: ObjImpl) NativeFn {
    return struct {
        fn call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
            const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
            return impl(ctx, obj, Args.init(ctx, func, args));
        }
    }.call;
}

// the procedural alias of a method: the object comes first and must be of
// `class`, and the method's arguments follow it
fn objFunction(comptime func: []const u8, comptime class: []const u8, comptime impl: ObjImpl) NativeFn {
    return struct {
        fn call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
            const obj = try Args.init(ctx, func, args).object(0, "object", class);
            var rest = Args.init(ctx, func, args[1..]);
            rest.shift = 1;
            return impl(ctx, obj, rest);
        }
    }.call;
}

// date_throw_uninitialized_error: a subclass whose constructor never ran the
// parent's is named with the internal class it inherits
fn throwUninitialized(ctx: *NativeContext, class_name: []const u8) RuntimeError {
    const vm = ctx.vm;
    const own = vm.declaredClassName(class_name);
    var msg: []u8 = undefined;
    const cls = vm.classes.get(own);
    if (cls == null or cls.?.is_internal) {
        msg = try std.fmt.allocPrint(ctx.allocator, "Object of type {s} has not been correctly initialized by calling parent::__construct() in its constructor", .{own});
    } else {
        var base = own;
        var cur = cls.?;
        while (!cur.is_internal) {
            const parent = cur.parent orelse break;
            base = vm.declaredClassName(parent);
            cur = vm.classes.get(base) orelse break;
        }
        msg = if (!cur.is_internal)
            try std.fmt.allocPrint(ctx.allocator, "Object of type {s} not been correctly initialized by calling parent::__construct() in its constructor", .{own})
        else
            try std.fmt.allocPrint(ctx.allocator, "Object of type {s} (inheriting {s}) has not been correctly initialized by calling parent::__construct() in its constructor", .{ own, base });
    }
    defer ctx.allocator.free(msg);
    try vm.setPendingException("DateObjectError", msg);
    return error.RuntimeError;
}

// a DateTimeZone's zone, or DateObjectError when it was never initialized
fn zoneOf(ctx: *NativeContext, obj: *PhpObject) RuntimeError!ParseZone {
    return objZone(obj) orelse throwUninitialized(ctx, obj.class_name);
}

// a date object's instant, or DateObjectError when it was never initialized
fn instantOf(ctx: *NativeContext, obj: *PhpObject) RuntimeError!i64 {
    const v = obj.get("__timestamp");
    if (v == .null) return throwUninitialized(ctx, obj.class_name);
    return Value.toInt(v);
}

fn tzGetName(ctx: *NativeContext, obj: *PhpObject, _: Args) RuntimeError!NativeResult {
    _ = try zoneOf(ctx, obj);
    return NativeResult.shareString(obj.get("__timezone").string);
}

fn tzGetOffset(ctx: *NativeContext, obj: *PhpObject, p: Args) RuntimeError!NativeResult {
    const zone = try zoneOf(ctx, obj);
    const dt = try p.object(0, "datetime", "DateTimeInterface");
    const ts = try instantOf(ctx, dt);
    return NativeResult.scalar(.{ .int = zone.totalOffset(ctx.allocator, ts) });
}

fn tzGetLocation(ctx: *NativeContext, obj: *PhpObject, _: Args) RuntimeError!NativeResult {
    const zone = try zoneOf(ctx, obj);
    if (zone.kind != dp.ZONETYPE_ID) return NativeResult.scalar(.{ .bool = false });
    const inf = tzdb.info(zone.name()) orelse return NativeResult.scalar(.{ .bool = false });
    const loc = inf.location;
    const arr = try ctx.createArray();
    const cc_len = std.mem.indexOfScalar(u8, &loc.country_code, 0) orelse 2;
    try putAssocStr(ctx, arr, "country_code", loc.country_code[0..cc_len]);
    try putAssoc(ctx, arr, "latitude", .{ .float = loc.latitude });
    try putAssoc(ctx, arr, "longitude", .{ .float = loc.longitude });
    try putAssocStr(ctx, arr, "comments", loc.comments);
    return NativeResult.borrowed(.{ .array = arr });
}

fn putTransition(ctx: *NativeContext, out: *PhpArray, inf: *const tzdb.Info, ts: i64, t: tzdb.TType) RuntimeError!void {
    const e = try ctx.createArray();
    try putAssoc(ctx, e, "ts", .{ .int = ts });
    const time = try formatGmt(ctx, ts, "x-m-d\\TH:i:sP");
    defer if (time.value == .string) time.value.string.release();
    try putAssoc(ctx, e, "time", time.value);
    try putAssoc(ctx, e, "offset", .{ .int = t.offset });
    try putAssoc(ctx, e, "isdst", .{ .bool = t.isdst });
    try putAssocStr(ctx, e, "abbr", inf.abbr(t));
    try out.append(ctx.allocator, .{ .array = e });
}

// timezone_transitions_get: the listed transitions from the zone's data, then
// those its posix rule gives for the years after the last one
fn tzGetTransitions(ctx: *NativeContext, obj: *PhpObject, p: Args) RuntimeError!NativeResult {
    const zone = try zoneOf(ctx, obj);
    const min = std.math.minInt(i64);
    const begin: i64 = if (p.has(0)) try p.long(0, "timestampBegin") else min;
    const end: i64 = if (p.has(1)) try p.long(1, "timestampEnd") else std.math.maxInt(i32);
    if (zone.kind != dp.ZONETYPE_ID) return NativeResult.scalar(.{ .bool = false });
    const inf = tzdb.info(zone.name()) orelse return NativeResult.scalar(.{ .bool = false });
    const out = try ctx.createArray();
    const result = NativeResult.borrowed(.{ .array = out });
    const n = inf.trans.len;
    var first: usize = 0;
    var found = false;
    if (begin == min) {
        try putTransition(ctx, out, inf, begin, inf.types[0]);
        found = true;
    } else {
        while (first < n) : (first += 1) {
            if (inf.trans[first] > begin) {
                if (first > 0) {
                    try putTransition(ctx, out, inf, begin, inf.types[inf.trans_idx[first - 1]]);
                } else {
                    try putTransition(ctx, out, inf, begin, inf.types[0]);
                }
                found = true;
                break;
            }
        }
    }
    const rule = if (inf.posix) |r| (if (r.dst_end != null) r else null) else null;
    if (!found) {
        if (n > 0) {
            if (rule != null) {
                const f = inf.fetch(begin) orelse return result;
                try putTransition(ctx, out, inf, begin, f.t);
            } else {
                try putTransition(ctx, out, inf, begin, inf.types[inf.trans_idx[n - 1]]);
            }
        } else {
            try putTransition(ctx, out, inf, begin, inf.types[0]);
        }
    } else {
        for (first..n) |i| {
            if (inf.trans[i] >= end) return result;
            try putTransition(ctx, out, inf, inf.trans[i], inf.types[inf.trans_idx[i]]);
        }
    }
    if (rule != null and n > 0) {
        const last = inf.trans[n - 1];
        const start_y = tzdb.yearOf(last);
        const end_y = tzdb.yearOf(end);
        var y = start_y;
        while (y <= end_y) : (y += 1) {
            var tr = tzdb.Info.Transitions{};
            inf.transitionsForYear(y, &tr);
            for (0..tr.count) |j| {
                const t = tr.times[j];
                if (t <= last or t < begin) continue;
                if (t > end) return result;
                try putTransition(ctx, out, inf, t, inf.types[tr.types[j]]);
            }
        }
    }
    return result;
}

const dtzGetName = objMethod("DateTimeZone::getName", tzGetName);
const dtzGetOffset = objMethod("DateTimeZone::getOffset", tzGetOffset);
const dtzGetLocation = objMethod("DateTimeZone::getLocation", tzGetLocation);
const dtzGetTransitions = objMethod("DateTimeZone::getTransitions", tzGetTransitions);
const native_timezone_name_get = objFunction("timezone_name_get", "DateTimeZone", tzGetName);
const native_timezone_offset_get = objFunction("timezone_offset_get", "DateTimeZone", tzGetOffset);
const native_timezone_location_get = objFunction("timezone_location_get", "DateTimeZone", tzGetLocation);
const native_timezone_transitions_get = objFunction("timezone_transitions_get", "DateTimeZone", tzGetTransitions);

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

// the local time of an instant in the default zone (timelib_unixtime2local)
fn defaultLocal(ctx: *NativeContext, ts: i64) date_format.Local {
    return localOf(ts, 0, &defaultZone(ctx));
}

// date() and gmdate(): the timestamp is optional and nullable
fn dateAs(ctx: *NativeContext, args: []const Value, comptime func: []const u8, localtime: bool) RuntimeError!NativeResult {
    const p = string_ports.Args.init(ctx, func, args);
    const format = try p.str(0, "format");
    const ts = (try p.longOrNull(1, "timestamp")) orelse platform.timestamp();
    return if (localtime) formatIn(ctx, ts, 0, &defaultZone(ctx), format) else formatGmt(ctx, ts, format);
}

fn native_date(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return dateAs(ctx, args, "date", true);
}

fn native_gmdate(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return dateAs(ctx, args, "gmdate", false);
}

// php_mktime: fields not given come from now, a two-digit year is read as
// 1970-2069, and the result is resolved in the default zone (or utc)
fn mktimeAs(ctx: *NativeContext, args: []const Value, comptime func: []const u8, gmt: bool) RuntimeError!NativeResult {
    const p = string_ports.Args.init(ctx, func, args);
    const hour = try p.long(0, "hour");
    const minute = try p.longOrNull(1, "minute");
    const second = try p.longOrNull(2, "second");
    const month = try p.longOrNull(3, "month");
    const day = try p.longOrNull(4, "day");
    const year = try p.longOrNull(5, "year");
    const now = platform.timestamp();
    const zone = defaultZone(ctx);
    var t = if (gmt) blk: {
        var g = dp.Time{};
        var l = date_format.Local{ .y = 0, .m = 1, .d = 1, .h = 0, .i = 0, .s = 0, .sse = now };
        date_format.fieldsAt(now, 0, &l);
        g.y = l.y;
        g.m = l.m;
        g.d = l.d;
        g.h = l.h;
        g.i = l.i;
        g.s = l.s;
        g.us = 0;
        g.z = 0;
        g.dst = 0;
        break :blk g;
    } else wallTime(ctx.allocator, now, 0, &zone);
    t.h = hour;
    if (minute) |v| t.i = v;
    if (second) |v| t.s = v;
    if (month) |v| t.m = v;
    if (day) |v| t.d = v;
    if (year) |v| {
        t.y = if (v >= 0 and v < 70) v + 2000 else if (v >= 70 and v <= 100) v + 1900 else v;
    }
    dp.updateTs(&t, if (gmt) null else zone.name(), parse_db);
    return NativeResult.scalar(.{ .int = t.sse });
}

fn native_mktime(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return mktimeAs(ctx, args, "mktime", false);
}

fn native_gmmktime(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return mktimeAs(ctx, args, "gmmktime", true);
}

fn native_getdate(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = string_ports.Args.init(ctx, "getdate", args);
    const ts = (try p.longOrNull(0, "timestamp")) orelse platform.timestamp();
    const t = defaultLocal(ctx, ts);
    const weekdays = [_][]const u8{ "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" };
    const months = [_][]const u8{ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };
    const arr = try ctx.createArray();
    const ints = [_]struct { []const u8, i64 }{
        .{ "seconds", t.s },
        .{ "minutes", t.i },
        .{ "hours", t.h },
        .{ "mday", t.d },
        .{ "wday", dp.dayOfWeek(t.y, t.m, t.d) },
        .{ "mon", t.m },
        .{ "year", t.y },
        .{ "yday", dp.dayOfYear(t.y, t.m, t.d) },
    };
    for (ints) |f| try putAssoc(ctx, arr, f[0], .{ .int = f[1] });
    try putAssoc(ctx, arr, "weekday", .{ .string = Value.String.borrowed(weekdays[@intCast(dp.dayOfWeek(t.y, t.m, t.d))]) });
    try putAssoc(ctx, arr, "month", .{ .string = Value.String.borrowed(months[@intCast(std.math.clamp(t.m, 1, 12) - 1)]) });
    try arr.set(ctx.allocator, .{ .int = 0 }, .{ .int = ts });
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_localtime(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = string_ports.Args.init(ctx, "localtime", args);
    const ts = (try p.longOrNull(0, "timestamp")) orelse platform.timestamp();
    const assoc = try p.boolean(1, "associative", false);
    const t = defaultLocal(ctx, ts);
    const fields = [_]struct { []const u8, i64 }{
        .{ "tm_sec", t.s },
        .{ "tm_min", t.i },
        .{ "tm_hour", t.h },
        .{ "tm_mday", t.d },
        .{ "tm_mon", t.m - 1 },
        .{ "tm_year", t.y - 1900 },
        .{ "tm_wday", dp.dayOfWeek(t.y, t.m, t.d) },
        .{ "tm_yday", dp.dayOfYear(t.y, t.m, t.d) },
        .{ "tm_isdst", @intFromBool(t.is_dst) },
    };
    const arr = try ctx.createArray();
    for (fields) |f| {
        if (assoc) try putAssoc(ctx, arr, f[0], .{ .int = f[1] }) else try arr.append(ctx.allocator, .{ .int = f[1] });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

// php_idate: one format character, the result through a c int
fn native_idate(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = string_ports.Args.init(ctx, "idate", args);
    const format = try p.str(0, "format");
    const ts = (try p.longOrNull(1, "timestamp")) orelse platform.timestamp();
    if (format.len != 1) {
        try ctx.vm.emitWarning("idate(): idate format is one char");
        return NativeResult.scalar(.{ .bool = false });
    }
    const t = defaultLocal(ctx, ts);
    var iso_week: i64 = 0;
    var iso_year: i64 = 0;
    dp.isoWeekFromDate(t.y, t.m, t.d, &iso_week, &iso_year);
    const v: i64 = switch (format[0]) {
        'd', 'j' => t.d,
        'N' => dp.isoDayOfWeek(t.y, t.m, t.d),
        'w' => dp.dayOfWeek(t.y, t.m, t.d),
        'z' => dp.dayOfYear(t.y, t.m, t.d),
        'W' => iso_week,
        'm', 'n' => t.m,
        't' => dp.daysInMonth(t.y, t.m),
        'L' => @intFromBool(dp.isLeap(t.y)),
        'y' => @rem(t.y, 100),
        'Y' => t.y,
        'o' => iso_year,
        'B' => blk: {
            var beat: i64 = (@rem(ts, 86400) + 3600) * 10;
            if (beat < 0) beat += 864000;
            break :blk @rem(@divTrunc(beat, 864), 1000);
        },
        'g', 'h' => if (@rem(t.h, 12) != 0) @rem(t.h, 12) else 12,
        'H', 'G' => t.h,
        'i' => t.i,
        's' => t.s,
        'I' => @intFromBool(t.is_dst),
        'Z' => t.offset,
        'U' => ts,
        else => -1,
    };
    // php reports -1 as an unknown format character, whatever produced it
    const r: i32 = @truncate(v);
    if (r == -1) {
        try ctx.vm.emitWarning("idate(): Unrecognized date format token");
        return NativeResult.scalar(.{ .bool = false });
    }
    return NativeResult.scalar(.{ .int = r });
}

fn native_strtotime(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "strtotime", args);
    const input = try p.str(0, "datetime");
    const base = (try p.longOrNull(1, "baseTimestamp")) orelse platform.timestamp();
    if (input.len == 0) return NativeResult.scalar(.{ .bool = false });
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

// ---- zones, read from php's bundled database (tzdb.zig) ----

// an offset zone's name ("+05:30", "-0800")
fn fixedOffsetOf(name: []const u8) ?i32 {
    if (name.len == 0 or (name[0] != '+' and name[0] != '-')) return null;
    if (parseFixedOffset(name)) |o| return o;
    if (parseTimezoneOffset(name)) |o| return @intCast(o);
    return null;
}

// the offset in effect in a zone id, utc for one the database lacks
fn idOffset(name: []const u8, utc_ts: i64) struct { offset: i32, is_dst: bool } {
    const f = zoneFetch(name, utc_ts) orelse return .{ .offset = 0, .is_dst = false };
    return .{ .offset = f.t.offset, .is_dst = f.t.isdst };
}

fn zoneFetch(name: []const u8, utc_ts: i64) ?tzdb.Info.Fetched {
    const inf = tzdb.info(name) orelse return null;
    return inf.fetch(utc_ts);
}

pub fn tzOffsetForName(allocator: Allocator, name: []const u8, utc_ts: i64) i32 {
    _ = allocator;
    if (abbrZone(name)) |hit| return @intCast(hit.offset);
    if (fixedOffsetOf(name)) |o| return o;
    const f = zoneFetch(name, utc_ts) orelse return 0;
    return f.t.offset;
}

pub fn tzIsDstForName(allocator: Allocator, name: []const u8, utc_ts: i64) bool {
    _ = allocator;
    if (abbrZone(name)) |hit| return hit.dst;
    if (fixedOffsetOf(name) != null) return false;
    const f = zoneFetch(name, utc_ts) orelse return false;
    return f.t.isdst;
}

// the offset in effect at a wall-clock time (seconds as if the wall clock were
// utc), resolved the way timelib resolves a time without a zone of its own
pub fn tzOffsetForWallByName(allocator: Allocator, name: []const u8, wall_ts: i64) i32 {
    _ = allocator;
    if (abbrZone(name)) |hit| return @intCast(hit.offset);
    if (fixedOffsetOf(name)) |o| return o;
    if (!tzdb.isValid(name)) return 0;
    return @intCast(wall_ts -% dp.utcOfWall(wall_ts, name, parse_db));
}

// the abbreviation in effect (caller frees), or null for an unknown zone
pub fn tzAbbrevForName(allocator: Allocator, name: []const u8, utc_ts: i64) ?[]const u8 {
    if (abbrZone(name) != null) return std.ascii.allocUpperString(allocator, name) catch null;
    if (fixedOffsetOf(name) != null) return allocator.dupe(u8, name) catch null;
    const inf = tzdb.info(name) orelse return null;
    const f = inf.fetch(utc_ts) orelse return null;
    return allocator.dupe(u8, inf.abbr(f.t)) catch null;
}

// timelib_timezone_id_is_valid
pub fn tzIsKnown(allocator: Allocator, name: []const u8) bool {
    _ = allocator;
    return tzdb.isValid(name);
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

fn native_timezone_open(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const name = try Args.init(ctx, "timezone_open", args).str(0, "timezone");
    try rejectNulBytes(ctx, "timezone_open", 1, "timezone", name);
    const zone = (try timezoneInitialize(ctx, name, "timezone_open(): ", .warn)) orelse return NativeResult.scalar(.{ .bool = false });
    const obj = try ctx.createObject("DateTimeZone");
    try setObjZone(ctx, obj, &zone);
    return NativeResult.borrowed(.{ .object = obj });
}

fn native_tz_get(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return try NativeResult.copyString(ctx.allocator, ctx.vm.default_tz_name);
}

fn isLeapYear(y: i64) bool {
    return (@mod(y, 4) == 0 and @mod(y, 100) != 0) or @mod(y, 400) == 0;
}

// ---- the date string parser (date_parse.zig) wired to zphp's zones ----

// ---- DateInterval ----

// a timelib time for an ISO 8601 date (always utc)
fn isoTime(d: iso_interval.Date) dp.Time {
    var t = dp.Time{};
    t.y = d.y;
    t.m = d.m;
    t.d = d.d;
    t.h = if (d.h == iso_interval.unset) 0 else d.h;
    t.i = if (d.i == iso_interval.unset) 0 else d.i;
    t.s = if (d.s == iso_interval.unset) 0 else d.s;
    t.us = 0;
    t.zone_type = dp.ZONETYPE_OFFSET;
    t.z = 0;
    t.dst = 0;
    t.have_zone = 1;
    return t;
}

fn putRelFields(ctx: *NativeContext, obj: *PhpObject, y: i64, m: i64, d: i64, h: i64, i: i64, s: i64, us: i64, invert: bool, days: ?i64) RuntimeError!void {
    try obj.set(ctx.allocator, "y", .{ .int = y });
    try obj.set(ctx.allocator, "m", .{ .int = m });
    try obj.set(ctx.allocator, "d", .{ .int = d });
    try obj.set(ctx.allocator, "h", .{ .int = h });
    try obj.set(ctx.allocator, "i", .{ .int = i });
    try obj.set(ctx.allocator, "s", .{ .int = s });
    try obj.set(ctx.allocator, "f", .{ .float = @as(f64, @floatFromInt(us)) / 1000000.0 });
    try obj.set(ctx.allocator, "invert", .{ .int = @intFromBool(invert) });
    try obj.set(ctx.allocator, "days", if (days) |n| .{ .int = n } else .{ .bool = false });
    try obj.set(ctx.allocator, "from_string", .{ .bool = false });
}

// date_interval_initialize: an ISO 8601 duration, or the difference between
// the two dates of an ISO 8601 interval
fn diConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const spec = try Args.init(ctx, "DateInterval::__construct", args).str(0, "duration");
    const parsed = iso_interval.parse(spec);
    if (parsed.errors > 0) return throwFmt(ctx, "DateMalformedIntervalStringException", "Unknown or bad format ({s})", .{spec});
    if (parsed.period) |per| {
        try putRelFields(ctx, obj, per.y, per.m, per.d, per.h, per.i, per.s, 0, false, null);
    } else if (parsed.begin != null and parsed.end != null) {
        var b = isoTime(parsed.begin.?);
        var e = isoTime(parsed.end.?);
        dp.updateTs(&b, null, parse_db);
        dp.updateTs(&e, null, parse_db);
        const rt = dp.diff(&b, &e, parse_db);
        try putRelFields(ctx, obj, rt.y, rt.m, rt.d, rt.h, rt.i, rt.s, rt.us, rt.invert, rt.days);
    } else {
        return throwFmt(ctx, "DateMalformedIntervalStringException", "Failed to parse interval ({s})", .{spec});
    }
    // intervals from a duration add hours, minutes, and seconds as elapsed
    // time (timelib_add_wall); the others add on the wall clock
    try obj.set(ctx.allocator, "__wall", .{ .bool = true });
    try markInterval(ctx, obj);
    return NativeResult.scalar(.null);
}

fn throwFmt(ctx: *NativeContext, class: []const u8, comptime fmt: []const u8, fargs: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, fargs);
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException(class, msg);
    return error.RuntimeError;
}

fn diCreateFromDateString(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return intervalFromDateString(ctx, args, true);
}

fn native_date_interval_create_from_date_string(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return intervalFromDateString(ctx, args, false);
}

// date_interval_create_from_date_string: the relative part of a date string.
// a parse error or a date, time, or zone in the string throws from the method
// and warns from the function
fn intervalFromDateString(ctx: *NativeContext, args: []const Value, throws: bool) RuntimeError!NativeResult {
    const func = if (throws) "DateInterval::createFromDateString" else "date_interval_create_from_date_string";
    const input = try Args.init(ctx, func, args).str(0, "datetime");
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
    try markInterval(ctx, obj);
    return NativeResult.borrowed(.{ .object = obj });
}

// an interval made from a date string: its relative part, and the string,
// which is what php shows and serializes
fn storeStringInterval(ctx: *NativeContext, obj: *PhpObject, input: []const u8, r: *const dp.Rel) RuntimeError!void {
    try putRelFields(ctx, obj, r.y, r.m, r.d, r.h, r.i, r.s, r.us, false, null);
    try obj.set(ctx.allocator, "from_string", .{ .bool = true });
    try obj.setCopiedString(ctx.allocator, "__date_string", input);
}

const interval_fields = [_][]const u8{ "y", "m", "d", "h", "i", "s", "f", "invert", "days", "from_string" };

fn isIntervalField(key: PhpArray.Key) bool {
    if (key != .string) return false;
    for (interval_fields) |name| if (std.mem.eql(u8, key.string.bytes(), name)) return true;
    return std.mem.eql(u8, key.string.bytes(), "date_string");
}

fn intervalInitialized(obj: *PhpObject) bool {
    return obj.get("__init") == .bool;
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
// handler builds them; an interval whose constructor never ran has no fields
fn intervalProperties(ctx: *NativeContext, obj: *PhpObject, _: object_properties.Purpose) RuntimeError!?*PhpArray {
    const own = try object_properties.ownTable(ctx.vm, obj);
    const table = try ctx.vm.allocArray();
    for (own.entries.items) |entry| if (!isIntervalField(entry.key)) try table.set(ctx.allocator, entry.key, entry.value);
    if (intervalInitialized(obj)) try putIntervalFields(ctx, obj, table);
    return table;
}

fn intervalSerialize(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    _ = try intervalOf(ctx, obj);
    const out = try ctx.createArray();
    try putIntervalFields(ctx, obj, out);
    const own = try object_properties.ownTable(ctx.vm, obj);
    for (own.entries.items) |entry| if (!isIntervalField(entry.key) and !out.contains(entry.key)) try out.set(ctx.allocator, entry.key, entry.value);
    return NativeResult.borrowed(.{ .array = out });
}

fn hashField(data: *const PhpArray, name: []const u8) ?Value {
    const key: PhpArray.Key = .{ .string = Value.String.borrowed(name) };
    if (!data.contains(key)) return null;
    return data.get(key);
}

// php_date_interval_initialize_from_hash: a date string is parsed again;
// otherwise each field is read with php's default (-1 for a missing one), and
// an interval with no civil_or_wall adds on the wall clock's civil rules
fn initializeIntervalFromHash(ctx: *NativeContext, obj: *PhpObject, data: *const PhpArray) RuntimeError!void {
    if (hashField(data, "date_string")) |date_string| if (date_string == .string) {
        const input = date_string.string.bytes();
        var p = try parseDate(ctx, input);
        defer p.deinit(ctx.allocator);
        if (p.errors.items.len > 0) {
            const e = p.errors.items[0];
            return throwFmt(ctx, "Error", "Unknown or bad format ({s}) at position {d} ({c}) while unserializing: {s}", .{ input, e.pos, if (e.char == 0) ' ' else e.char, e.msg });
        }
        try storeStringInterval(ctx, obj, input, &p.time.relative);
        try obj.set(ctx.allocator, "__wall", .{ .bool = false });
        try markInterval(ctx, obj);
        return;
    };
    for ([_][]const u8{ "y", "m", "d", "h", "i", "s" }) |name| {
        const v = hashField(data, name);
        try obj.set(ctx.allocator, name, .{ .int = if (v != null and isScalarField(v.?)) v.?.toInt() else -1 });
    }
    const us: i64 = if (hashField(data, "f")) |f| Value.dvalToLval(Value.toFloat(f) * 1000000.0) else 0;
    try obj.set(ctx.allocator, "f", .{ .float = @as(f64, @floatFromInt(us)) / 1000000.0 });
    const invert = hashField(data, "invert");
    try obj.set(ctx.allocator, "invert", .{ .int = if (invert != null and isScalarField(invert.?)) invert.?.toInt() else 0 });
    const days = hashField(data, "days");
    const days_value: Value = if (days == null) .{ .int = -1 } else if (days.? == .bool and !days.?.bool) .{ .bool = false } else if (isScalarField(days.?)) .{ .int = days.?.toInt() } else .{ .int = -1 };
    try obj.set(ctx.allocator, "days", days_value);
    try obj.set(ctx.allocator, "from_string", .{ .bool = false });
    const civil_or_wall = hashField(data, "civil_or_wall");
    try obj.set(ctx.allocator, "__wall", .{ .bool = civil_or_wall != null and civil_or_wall.?.toInt() == 2 });
    try markInterval(ctx, obj);
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
    const data = try arrayArg(ctx, "DateInterval::__unserialize", args, "data");
    try initializeIntervalFromHash(ctx, obj, data);
    try restoreCustomProperties(ctx, obj, data, &.{ "date_string", "from_string", "y", "m", "d", "h", "i", "s", "f", "invert", "days" });
    return NativeResult.scalar(.null);
}

fn intervalSetState(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const data = try arrayArg(ctx, "DateInterval::__set_state", args, "array");
    const obj = try ctx.createObject("DateInterval");
    try initializeIntervalFromHash(ctx, obj, data);
    return NativeResult.borrowed(.{ .object = obj });
}

// __wakeup rebuilds the interval from the object's own properties
fn intervalWakeup(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const own = try object_properties.ownTable(ctx.vm, obj);
    if (obj.get("__date_string") == .string and !own.contains(.{ .string = Value.String.borrowed("date_string") })) {
        try own.set(ctx.allocator, .{ .string = Value.String.borrowed("date_string") }, obj.get("__date_string"));
    }
    try initializeIntervalFromHash(ctx, obj, own);
    return NativeResult.scalar(.null);
}

// date_interval_format
fn intervalFormatImpl(ctx: *NativeContext, obj: *PhpObject, p: Args) RuntimeError!NativeResult {
    const fmt = try p.str(0, "format");
    _ = try intervalOf(ctx, obj);
    const f = obj.get("f");
    // diff() keeps whole microseconds, which f can hold a hair under
    const us: i64 = if (f == .float) Value.dvalToLval(@round(f.float * 1_000_000.0)) else Value.toInt(f);
    const days = obj.get("days");
    const fields = struct { y: i64, m: i64, d: i64, h: i64, i: i64, s: i64 }{
        .y = Value.toInt(obj.get("y")),
        .m = Value.toInt(obj.get("m")),
        .d = Value.toInt(obj.get("d")),
        .h = Value.toInt(obj.get("h")),
        .i = Value.toInt(obj.get("i")),
        .s = Value.toInt(obj.get("s")),
    };
    const invert = Value.toInt(obj.get("invert")) != 0;
    const a = ctx.allocator;
    var out = std.ArrayListUnmanaged(u8).empty;
    defer out.deinit(a);
    var spec = false;
    for (fmt) |c| {
        if (!spec) {
            if (c == '%') spec = true else try out.append(a, c);
            continue;
        }
        spec = false;
        // c's (int) casts for all but the seconds and microseconds
        const int32 = struct {
            fn cast(v: i64) i64 {
                return @as(i32, @truncate(v));
            }
        }.cast;
        switch (c) {
            'Y' => try date_format.padded(&out, a, int32(fields.y), 2),
            'y' => try out.print(a, "{d}", .{int32(fields.y)}),
            'M' => try date_format.padded(&out, a, int32(fields.m), 2),
            'm' => try out.print(a, "{d}", .{int32(fields.m)}),
            'D' => try date_format.padded(&out, a, int32(fields.d), 2),
            'd' => try out.print(a, "{d}", .{int32(fields.d)}),
            'H' => try date_format.padded(&out, a, int32(fields.h), 2),
            'h' => try out.print(a, "{d}", .{int32(fields.h)}),
            'I' => try date_format.padded(&out, a, int32(fields.i), 2),
            'i' => try out.print(a, "{d}", .{int32(fields.i)}),
            'S' => try date_format.padded(&out, a, fields.s, 2),
            's' => try out.print(a, "{d}", .{fields.s}),
            'F' => try date_format.padded(&out, a, us, 6),
            'f' => try out.print(a, "{d}", .{us}),
            'a' => if (days == .int and int32(days.int) != dp.UNSET) try out.print(a, "{d}", .{int32(days.int)}) else try out.appendSlice(a, "(unknown)"),
            'r' => if (invert) try out.append(a, '-'),
            'R' => try out.append(a, if (invert) '-' else '+'),
            '%' => try out.append(a, '%'),
            else => {
                try out.append(a, '%');
                try out.append(a, c);
            },
        }
    }
    return NativeResult.takeString(try Value.String.adopt(a, try out.toOwnedSlice(a)));
}

const diFormat = objMethod("DateInterval::format", intervalFormatImpl);
const native_date_interval_format = objFunction("date_interval_format", "DateInterval", intervalFormatImpl);

const dp = @import("date_parse.zig");

// a zone id is matched case-insensitively and keeps the spelling it was given,
// as timelib_tzinfo_ctor does
fn dbLookupId(name: []const u8, out: *[64]u8) ?[]const u8 {
    if (name.len == 0 or name.len > out.len) return null;
    if (!tzdb.isValid(name)) return null;
    @memcpy(out[0..name.len], name);
    return out[0..name.len];
}

fn dbOffsetInfo(id: []const u8, ts: i64) ?dp.OffsetInfo {
    const f = zoneFetch(id, ts) orelse return null;
    return .{ .offset = f.t.offset, .transition_time = f.transition, .is_dst = f.t.isdst };
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

    fn totalOffset(self: *const ParseZone, _: Allocator, ts: i64) i64 {
        return switch (self.kind) {
            dp.ZONETYPE_OFFSET => self.z,
            dp.ZONETYPE_ABBR => self.z + self.dst * 3600,
            else => idOffset(self.name(), ts).offset,
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
    const secs = @mod(wall, 86400);
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
            t.dst = if (idOffset(zone.name(), ts).is_dst) 1 else 0;
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

fn recordLastErrors(ctx: *NativeContext, p: *const dp.Parsed) RuntimeError!void {
    const rec = &ctx.vm.last_dt;
    rec.clear();
    for (p.warnings.items) |w| try rec.addWarning(ctx.vm.allocator, w.pos, w.msg);
    for (p.errors.items) |e| try rec.addError(ctx.vm.allocator, e.pos, e.msg);
    rec.set = rec.warning_count > 0 or rec.error_count > 0;
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

pub fn internZoneName(name: []const u8) []const u8 {
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
    try setObjZone(ctx, obj, zone);
    // a missing __microseconds reads as 0
    if (us != 0 or obj.get("__microseconds") != .null) try obj.set(ctx.allocator, "__microseconds", .{ .int = us });
}

// php_date_initialize: the constructors and date_create(). a parse error
// throws when `throws` is set (the constructors) and otherwise only makes the
// call fail. tz_arg is the DateTimeZone argument's zone name
const Instant = struct { ts: i64, us: i64, zone: ParseZone };

fn resolveDate(ctx: *NativeContext, input: []const u8, tz_arg: ?ParseZone, throws: bool) RuntimeError!?Instant {
    return resolveDateWith(ctx, input, null, tz_arg, throws);
}

// with a format, the string is read by timelib_parse_from_format and unset
// time fields come from now instead of midnight (createFromFormat)
fn resolveDateWith(ctx: *NativeContext, input_arg: []const u8, format: ?[]const u8, tz_arg: ?ParseZone, throws: bool) RuntimeError!?Instant {
    const input = if (input_arg.len == 0 and format == null) "now" else input_arg;
    var p = if (format) |f|
        dp.parseFromFormat(ctx.allocator, f, input, parse_db) catch return error.OutOfMemory
    else
        try parseDate(ctx, input);
    defer p.deinit(ctx.allocator);
    try recordLastErrors(ctx, &p);
    if (p.errors.items.len > 0) {
        if (throws) {
            const msg = try parseFailure(ctx, "", input, &p);
            defer ctx.allocator.free(msg);
            try ctx.vm.setPendingException("DateMalformedStringException", msg);
        }
        return null;
    }
    const zone = if (tz_arg) |z|
        z
    else if (p.time.zone_type == dp.ZONETYPE_ID and p.time.id() != null)
        ParseZone.of(p.time.id().?, true)
    else
        defaultZone(ctx);
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
    try recordLastErrors(ctx, &p);
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
    const zone = objZoneOr(ctx, obj);
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
    const zone = defaultZone(ctx);
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
    try putAssoc(ctx, arr, "warnings", .{ .array = try messagesArray(ctx, rec.warnings.items) });
    try putAssoc(ctx, arr, "error_count", .{ .int = rec.error_count });
    try putAssoc(ctx, arr, "errors", .{ .array = try messagesArray(ctx, rec.errors.items) });
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
    defer rec.deinit(ctx.allocator);
    for (p.warnings.items) |w| try rec.addWarning(ctx.allocator, w.pos, w.msg);
    for (p.errors.items) |e| try rec.addError(ctx.allocator, e.pos, e.msg);
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
