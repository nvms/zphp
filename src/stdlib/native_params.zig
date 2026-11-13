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

pub fn get(name: []const u8) ?Signature {
    return zphp_only.get(name) orelse generated.map.get(name);
}
