const std = @import("std");
const generated = @import("native_params_generated.zig");

// the signature of a native function or method, which natives do not declare
// themselves: named arguments are placed by it, a skipped optional parameter
// receives its default, and reflection reports it. natives php shares come
// from php's own reflection (scripts/gen-php-metadata); the ones only zphp
// has are below

pub const Default = union(enum) {
    required,
    // optional, but php does not publish the value, so it cannot be skipped
    unknown,
    null,
    bool: bool,
    int: i64,
    float: f64,
    string: []const u8,
    empty_array,
    class_constant: struct { class: []const u8, name: []const u8 },
};

pub const Param = struct {
    name: []const u8,
    default: Default = .required,
    variadic: bool = false,
    by_ref: bool = false,
    // as php prints it: "int", "?array", "array|string|null"; empty when untyped
    type: []const u8 = "",
    // the constant the default was written as (STR_PAD_RIGHT), for reflection
    default_constant: []const u8 = "",
};

pub const Signature = struct {
    params: []const Param,
    returns: []const u8 = "",
    // php 8.1+ internal methods that user subclasses may still override
    // with a different return type
    tentative_returns: []const u8 = "",
    is_static: bool = false,
};

const zphp_only = std.StaticStringMap(Signature).initComptime(.{
    // Closure's methods php's reflection doesn't list, which take named
    // arguments on to the closure
    .{ "Closure::__invoke", Signature{ .params = &[_]Param{.{ .name = "args", .variadic = true, .type = "mixed" }}, .returns = "mixed" } },
    .{ "Closure::call", Signature{ .params = &[_]Param{ .{ .name = "newThis", .type = "object" }, .{ .name = "args", .variadic = true, .type = "mixed" } }, .returns = "mixed" } },
    .{ "Zphp\\Pool::__construct", Signature{ .params = &[_]Param{ .{ .name = "workers", .default = .null, .type = "?int" }, .{ .name = "bootstrap", .default = .null, .type = "?string" }, .{ .name = "queue", .default = .null, .type = "?int" } }, .returns = "" } },
    .{ "Zphp\\Pool::submit", Signature{ .params = &[_]Param{ .{ .name = "callable", .type = "Closure|array|string" }, .{ .name = "args", .default = .empty_array, .type = "array" } }, .returns = "Zphp\\Future" } },
    .{ "Zphp\\Pool::trySubmit", Signature{ .params = &[_]Param{ .{ .name = "callable", .type = "Closure|array|string" }, .{ .name = "args", .default = .empty_array, .type = "array" } }, .returns = "?Zphp\\Future" } },
    .{ "Zphp\\Pool::collect", Signature{ .params = &[_]Param{ .{ .name = "timeout", .default = .null, .type = "int|float|null" } }, .returns = "?Zphp\\Future" } },
    .{ "Zphp\\Pool::shutdown", Signature{ .params = &[_]Param{ .{ .name = "timeout", .default = .null, .type = "int|float|null" } }, .returns = "bool" } },
    .{ "Zphp\\Future::await", Signature{ .params = &[_]Param{ .{ .name = "timeout", .default = .null, .type = "int|float|null" } }, .returns = "mixed" } },
    .{ "Zphp\\Channel::__construct", Signature{ .params = &[_]Param{ .{ .name = "capacity", .default = .{ .int = 1 }, .type = "int" } }, .returns = "" } },
    .{ "Zphp\\Channel::send", Signature{ .params = &[_]Param{ .{ .name = "value", .type = "mixed" }, .{ .name = "timeout", .default = .null, .type = "int|float|null" } }, .returns = "void" } },
    .{ "Zphp\\Channel::trySend", Signature{ .params = &[_]Param{ .{ .name = "value", .type = "mixed" } }, .returns = "bool" } },
    .{ "Zphp\\Channel::recv", Signature{ .params = &[_]Param{ .{ .name = "timeout", .default = .null, .type = "int|float|null" } }, .returns = "mixed" } },
    .{ "Zphp\\select", Signature{ .params = &[_]Param{ .{ .name = "sources", .type = "array" }, .{ .name = "timeout", .default = .null, .type = "int|float|null" } }, .returns = "?array" } },
    .{ "Zphp\\Buffer::__construct", Signature{ .params = &[_]Param{ .{ .name = "length", .type = "int" } }, .returns = "" } },
    .{ "Zphp\\Buffer::fromString", Signature{ .params = &[_]Param{ .{ .name = "bytes", .type = "string" } }, .returns = "Zphp\\Buffer" } },
    .{ "Zphp\\Buffer::slice", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" }, .{ .name = "length", .default = .null, .type = "?int" } }, .returns = "Zphp\\Buffer" } },
    .{ "Zphp\\Buffer::write", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" }, .{ .name = "data", .type = "Zphp\\Buffer|string" } }, .returns = "void" } },
    .{ "Zphp\\Buffer::readFrom", Signature{ .params = &[_]Param{ .{ .name = "stream", .type = "mixed" } }, .returns = "int|false" } },
    .{ "Zphp\\Buffer::writeTo", Signature{ .params = &[_]Param{ .{ .name = "stream", .type = "mixed" } }, .returns = "int|false" } },
    .{ "Zphp\\Buffer::readInt8", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" } }, .returns = "int" } },
    .{ "Zphp\\Buffer::writeInt8", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" }, .{ .name = "value", .type = "int" } }, .returns = "void" } },
    .{ "Zphp\\Buffer::readUInt8", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" } }, .returns = "int" } },
    .{ "Zphp\\Buffer::writeUInt8", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" }, .{ .name = "value", .type = "int" } }, .returns = "void" } },
    .{ "Zphp\\Buffer::readInt16LE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" } }, .returns = "int" } },
    .{ "Zphp\\Buffer::writeInt16LE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" }, .{ .name = "value", .type = "int" } }, .returns = "void" } },
    .{ "Zphp\\Buffer::readInt16BE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" } }, .returns = "int" } },
    .{ "Zphp\\Buffer::writeInt16BE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" }, .{ .name = "value", .type = "int" } }, .returns = "void" } },
    .{ "Zphp\\Buffer::readUInt16LE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" } }, .returns = "int" } },
    .{ "Zphp\\Buffer::writeUInt16LE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" }, .{ .name = "value", .type = "int" } }, .returns = "void" } },
    .{ "Zphp\\Buffer::readUInt16BE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" } }, .returns = "int" } },
    .{ "Zphp\\Buffer::writeUInt16BE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" }, .{ .name = "value", .type = "int" } }, .returns = "void" } },
    .{ "Zphp\\Buffer::readInt32LE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" } }, .returns = "int" } },
    .{ "Zphp\\Buffer::writeInt32LE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" }, .{ .name = "value", .type = "int" } }, .returns = "void" } },
    .{ "Zphp\\Buffer::readInt32BE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" } }, .returns = "int" } },
    .{ "Zphp\\Buffer::writeInt32BE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" }, .{ .name = "value", .type = "int" } }, .returns = "void" } },
    .{ "Zphp\\Buffer::readUInt32LE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" } }, .returns = "int" } },
    .{ "Zphp\\Buffer::writeUInt32LE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" }, .{ .name = "value", .type = "int" } }, .returns = "void" } },
    .{ "Zphp\\Buffer::readUInt32BE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" } }, .returns = "int" } },
    .{ "Zphp\\Buffer::writeUInt32BE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" }, .{ .name = "value", .type = "int" } }, .returns = "void" } },
    .{ "Zphp\\Buffer::readInt64LE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" } }, .returns = "int" } },
    .{ "Zphp\\Buffer::writeInt64LE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" }, .{ .name = "value", .type = "int" } }, .returns = "void" } },
    .{ "Zphp\\Buffer::readInt64BE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" } }, .returns = "int" } },
    .{ "Zphp\\Buffer::writeInt64BE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" }, .{ .name = "value", .type = "int" } }, .returns = "void" } },
    .{ "Zphp\\Buffer::readFloat32LE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" } }, .returns = "float" } },
    .{ "Zphp\\Buffer::writeFloat32LE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" }, .{ .name = "value", .type = "int|float" } }, .returns = "void" } },
    .{ "Zphp\\Buffer::readFloat32BE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" } }, .returns = "float" } },
    .{ "Zphp\\Buffer::writeFloat32BE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" }, .{ .name = "value", .type = "int|float" } }, .returns = "void" } },
    .{ "Zphp\\Buffer::readFloat64LE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" } }, .returns = "float" } },
    .{ "Zphp\\Buffer::writeFloat64LE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" }, .{ .name = "value", .type = "int|float" } }, .returns = "void" } },
    .{ "Zphp\\Buffer::readFloat64BE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" } }, .returns = "float" } },
    .{ "Zphp\\Buffer::writeFloat64BE", Signature{ .params = &[_]Param{ .{ .name = "offset", .type = "int" }, .{ .name = "value", .type = "int|float" } }, .returns = "void" } },
});

// php methods the generator, which reads php's reflection of the methods
// zphp registered when it last ran, has not seen yet
const php_stub = std.StaticStringMap(Signature).initComptime(.{
    .{ "hebrev", Signature{ .params = &[_]Param{ .{ .name = "string", .type = "string" }, .{ .name = "max_chars_per_line", .default = .{ .int = 0 }, .type = "int" } }, .returns = "string" } },
    .{ "get_meta_tags", Signature{ .params = &[_]Param{ .{ .name = "filename", .type = "string" }, .{ .name = "use_include_path", .default = .{ .bool = false }, .type = "bool" } }, .returns = "array|false" } },
    .{ "ReflectionEnumUnitCase::getEnum", Signature{ .params = &[_]Param{}, .returns = "ReflectionEnum" } },
    .{ "ArrayObject::__debugInfo", Signature{ .params = &[_]Param{}, .tentative_returns = "array" } },
    .{ "ArrayIterator::__debugInfo", Signature{ .params = &[_]Param{}, .tentative_returns = "array" } },
    .{ "ReflectionAttribute::__toString", Signature{ .params = &[_]Param{}, .returns = "string" } },
    .{ "ReflectionClassConstant::__toString", Signature{ .params = &[_]Param{}, .returns = "string" } },
    .{ "ReflectionProperty::__toString", Signature{ .params = &[_]Param{}, .returns = "string" } },
    .{ "ReflectionParameter::__toString", Signature{ .params = &[_]Param{}, .returns = "string" } },
    .{ "ReflectionMethod::__toString", Signature{ .params = &[_]Param{}, .returns = "string" } },
    .{ "ReflectionFunction::__toString", Signature{ .params = &[_]Param{}, .returns = "string" } },
    .{ "ReflectionClass::__toString", Signature{ .params = &[_]Param{}, .returns = "string" } },
    .{ "ReflectionClass::__clone", Signature{ .params = &[_]Param{}, .returns = "void" } },
    .{ "ReflectionFunctionAbstract::__clone", Signature{ .params = &[_]Param{}, .returns = "void" } },
    .{ "ReflectionParameter::__clone", Signature{ .params = &[_]Param{}, .returns = "void" } },
    .{ "ReflectionType::__clone", Signature{ .params = &[_]Param{}, .returns = "void" } },
    .{ "ReflectionProperty::__clone", Signature{ .params = &[_]Param{}, .returns = "void" } },
    .{ "ReflectionClassConstant::__clone", Signature{ .params = &[_]Param{}, .returns = "void" } },
    .{ "ReflectionExtension::__clone", Signature{ .params = &[_]Param{}, .returns = "void" } },
    .{ "ReflectionZendExtension::__clone", Signature{ .params = &[_]Param{}, .returns = "void" } },
    .{ "ReflectionReference::__clone", Signature{ .params = &[_]Param{}, .returns = "void" } },
    .{ "ReflectionAttribute::__clone", Signature{ .params = &[_]Param{}, .returns = "void" } },
    .{ "Exception::__clone", Signature{ .params = &[_]Param{}, .returns = "void" } },
    .{ "Error::__clone", Signature{ .params = &[_]Param{}, .returns = "void" } },
    .{ "Exception::__wakeup", Signature{ .params = &[_]Param{}, .tentative_returns = "void" } },
    .{ "Error::__wakeup", Signature{ .params = &[_]Param{}, .tentative_returns = "void" } },
    .{ "date_sunrise", Signature{ .params = &[_]Param{ .{ .name = "timestamp", .type = "int" }, .{ .name = "returnFormat", .default = .{ .int = 1 }, .default_constant = "SUNFUNCS_RET_STRING", .type = "int" }, .{ .name = "latitude", .default = .null, .type = "?float" }, .{ .name = "longitude", .default = .null, .type = "?float" }, .{ .name = "zenith", .default = .null, .type = "?float" }, .{ .name = "utcOffset", .default = .null, .type = "?float" } }, .returns = "string|int|float|false" } },
    .{ "date_sunset", Signature{ .params = &[_]Param{ .{ .name = "timestamp", .type = "int" }, .{ .name = "returnFormat", .default = .{ .int = 1 }, .default_constant = "SUNFUNCS_RET_STRING", .type = "int" }, .{ .name = "latitude", .default = .null, .type = "?float" }, .{ .name = "longitude", .default = .null, .type = "?float" }, .{ .name = "zenith", .default = .null, .type = "?float" }, .{ .name = "utcOffset", .default = .null, .type = "?float" } }, .returns = "string|int|float|false" } },
    .{ "date_sun_info", Signature{ .params = &[_]Param{ .{ .name = "timestamp", .type = "int" }, .{ .name = "latitude", .type = "float" }, .{ .name = "longitude", .type = "float" } }, .returns = "array" } },
    .{ "show_source", Signature{ .params = &[_]Param{ .{ .name = "filename", .type = "string" }, .{ .name = "return", .default = .{ .bool = false }, .type = "bool" } }, .returns = "string|bool" } },
    .{ "timezone_name_from_abbr", Signature{ .params = &[_]Param{ .{ .name = "abbr", .type = "string" }, .{ .name = "utcOffset", .default = .{ .int = -1 }, .type = "int" }, .{ .name = "isDST", .default = .{ .int = -1 }, .type = "int" } }, .returns = "string|false" } },
});

// the stub defaults that are expressions of constants, which reflection's
// string form prints as written
pub fn defaultExpression(func: []const u8, param: []const u8) ?[]const u8 {
    const html = [_][]const u8{ "htmlspecialchars", "htmlspecialchars_decode", "html_entity_decode", "htmlentities", "get_html_translation_table" };
    if (std.mem.eql(u8, param, "flags")) {
        for (html) |f| if (std.ascii.eqlIgnoreCase(func, f)) return "ENT_QUOTES | ENT_SUBSTITUTE | ENT_HTML401";
        if (std.ascii.eqlIgnoreCase(func, "stream_socket_server")) return "STREAM_SERVER_BIND | STREAM_SERVER_LISTEN";
    }
    return null;
}

pub fn get(name: []const u8) ?Signature {
    return zphp_only.get(name) orelse generated.map.get(name) orelse php_stub.get(name) orelse inheritedSignature(name);
}

// the generated map lists a method under every class that has it; an
// abstract parent's own declaration reads the same from a subclass
fn inheritedSignature(name: []const u8) ?Signature {
    const pairs = [_][2][]const u8{
        .{ "ReflectionFunctionAbstract::", "ReflectionFunction::" },
        .{ "ReflectionFunctionAbstract::", "ReflectionMethod::" },
        .{ "ReflectionType::", "ReflectionNamedType::" },
    };
    for (pairs) |pair| {
        if (!std.mem.startsWith(u8, name, pair[0])) continue;
        var buf: [128]u8 = undefined;
        const method = name[pair[0].len..];
        if (pair[1].len + method.len > buf.len) return null;
        @memcpy(buf[0..pair[1].len], pair[1]);
        @memcpy(buf[pair[1].len..][0..method.len], method);
        const child = buf[0 .. pair[1].len + method.len];
        if (generated.map.get(child) orelse php_stub.get(child)) |sig| return sig;
    }
    return null;
}
