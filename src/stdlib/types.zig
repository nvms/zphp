const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "count", count },
    .{ "strlen", strlen },
    .{ "intval", intval },
    .{ "floatval", floatval },
    .{ "strval", strval },
    .{ "gettype", gettype },
    .{ "is_array", is_array },
    .{ "is_null", is_null },
    .{ "is_int", is_int },
    .{ "is_integer", is_int },
    .{ "is_long", is_int },
    .{ "is_float", is_float },
    .{ "is_double", is_float },
    .{ "is_string", is_string },
    .{ "is_bool", is_bool },
    .{ "is_numeric", is_numeric },
    .{ "isset", native_isset },
    .{ "empty", native_empty },
    .{ "boolval", boolval },
    .{ "define", native_define },
    .{ "defined", native_defined },
    .{ "constant", native_constant },
    .{ "is_object", is_object },
    .{ "get_class", get_class },
    .{ "class_exists", class_exists },
    .{ "method_exists", method_exists },
    .{ "property_exists", property_exists },
    .{ "is_callable", native_is_callable },
    .{ "settype", native_settype },
    .{ "call_user_func", native_call_user_func },
    .{ "call_user_func_array", native_call_user_func_array },
    .{ "function_exists", native_function_exists },
};

fn native_define(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string) return .{ .bool = false };
    try ctx.vm.php_constants.put(ctx.allocator, args[0].string, args[1]);
    return .{ .bool = true };
}

fn native_defined(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    return .{ .bool = ctx.vm.php_constants.contains(args[0].string) };
}

fn native_constant(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .null;
    return ctx.vm.php_constants.get(args[0].string) orelse .null;
}

fn count(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
    return switch (args[0]) {
        .array => |a| .{ .int = a.length() },
        else => .{ .int = 1 },
    };
}

fn intval(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
    return .{ .int = Value.toInt(args[0]) };
}

fn floatval(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .float = 0.0 };
    return .{ .float = Value.toFloat(args[0]) };
}

fn strval(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    if (args[0] == .string) return args[0];
    var buf = std.ArrayListUnmanaged(u8){};
    try args[0].format(&buf, ctx.allocator);
    const s = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, s);
    return .{ .string = s };
}

fn gettype(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "NULL" };
    return .{ .string = switch (args[0]) {
        .null => "NULL",
        .bool => "boolean",
        .int => "integer",
        .float => "double",
        .string => "string",
        .array => "array",
        .object, .generator, .fiber => "object",
    } };
}

fn is_array(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return .{ .bool = args.len > 0 and args[0] == .array };
}

fn is_null(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return .{ .bool = args.len == 0 or args[0] == .null };
}

fn is_int(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return .{ .bool = args.len > 0 and args[0] == .int };
}

fn is_float(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return .{ .bool = args.len > 0 and args[0] == .float };
}

fn is_string(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return .{ .bool = args.len > 0 and args[0] == .string };
}

fn is_bool(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return .{ .bool = args.len > 0 and args[0] == .bool };
}

fn is_numeric(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    return .{ .bool = switch (args[0]) {
        .int, .float => true,
        .string => |s| if (std.fmt.parseFloat(f64, s)) |_| true else |_| false,
        else => false,
    } };
}

fn native_isset(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    return .{ .bool = args[0] != .null };
}

fn native_empty(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = true };
    return .{ .bool = !args[0].isTruthy() };
}

fn strlen(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
    return switch (args[0]) {
        .string => |s| .{ .int = @intCast(s.len) },
        else => .{ .int = 0 },
    };
}


fn boolval(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    return .{ .bool = args[0].isTruthy() };
}

fn is_object(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return .{ .bool = args.len > 0 and args[0] == .object };
}

fn get_class(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) {
        const this_val = ctx.vm.currentFrame().vars.get("$this") orelse return Value{ .bool = false };
        if (this_val != .object) return .{ .bool = false };
        return .{ .string = this_val.object.class_name };
    }
    if (args[0] != .object) return .{ .bool = false };
    return .{ .string = args[0].object.class_name };
}

fn class_exists(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    return .{ .bool = ctx.vm.classes.contains(args[0].string) };
}

fn method_exists(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[1] != .string) return .{ .bool = false };
    const class_name = if (args[0] == .object)
        args[0].object.class_name
    else if (args[0] == .string)
        args[0].string
    else
        return Value{ .bool = false };
    const method_name = args[1].string;
    var buf: [256]u8 = undefined;
    const full = std.fmt.bufPrint(&buf, "{s}::{s}", .{ class_name, method_name }) catch return Value{ .bool = false };
    if (ctx.vm.native_fns.contains(full)) return .{ .bool = true };
    if (ctx.vm.functions.contains(full)) return .{ .bool = true };
    if (ctx.vm.classes.get(class_name)) |cls| {
        if (cls.parent) |parent| {
            const parent_full = std.fmt.bufPrint(&buf, "{s}::{s}", .{ parent, method_name }) catch return Value{ .bool = false };
            if (ctx.vm.native_fns.contains(parent_full)) return .{ .bool = true };
            if (ctx.vm.functions.contains(parent_full)) return .{ .bool = true };
        }
    }
    return .{ .bool = false };
}

fn property_exists(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[1] != .string) return .{ .bool = false };
    if (args[0] != .object) return .{ .bool = false };
    return .{ .bool = args[0].object.properties.contains(args[1].string) };
}

fn native_is_callable(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    const val = args[0];
    if (val == .string) {
        const name = val.string;
        if (ctx.vm.native_fns.contains(name)) return .{ .bool = true };
        if (ctx.vm.functions.contains(name)) return .{ .bool = true };
        return .{ .bool = false };
    }
    if (val == .array) {
        const arr = val.array;
        if (arr.entries.items.len != 2) return .{ .bool = false };
        const target = arr.entries.items[0].value;
        const method_val = arr.entries.items[1].value;
        if (method_val != .string) return .{ .bool = false };
        const method = method_val.string;
        const class_name = if (target == .object)
            target.object.class_name
        else if (target == .string)
            target.string
        else
            return .{ .bool = false };
        var buf: [256]u8 = undefined;
        const full = std.fmt.bufPrint(&buf, "{s}::{s}", .{ class_name, method }) catch return .{ .bool = false };
        if (ctx.vm.native_fns.contains(full)) return .{ .bool = true };
        if (ctx.vm.functions.contains(full)) return .{ .bool = true };
        return .{ .bool = false };
    }
    return .{ .bool = false };
}

fn native_settype(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[1] != .string) return .{ .bool = false };
    const type_name = args[1].string;
    const val = args[0];
    const converted: Value = if (std.mem.eql(u8, type_name, "int") or std.mem.eql(u8, type_name, "integer"))
        .{ .int = Value.toInt(val) }
    else if (std.mem.eql(u8, type_name, "float") or std.mem.eql(u8, type_name, "double"))
        .{ .float = Value.toFloat(val) }
    else if (std.mem.eql(u8, type_name, "string"))
        blk: {
            if (val == .string) break :blk val;
            var buf = std.ArrayListUnmanaged(u8){};
            try val.format(&buf, ctx.allocator);
            const s = try buf.toOwnedSlice(ctx.allocator);
            try ctx.strings.append(ctx.allocator, s);
            break :blk Value{ .string = s };
        }
    else if (std.mem.eql(u8, type_name, "bool") or std.mem.eql(u8, type_name, "boolean"))
        .{ .bool = val.isTruthy() }
    else if (std.mem.eql(u8, type_name, "null"))
        .null
    else
        return Value{ .bool = false };
    _ = converted;
    return .{ .bool = true };
}

fn native_call_user_func(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .null;
    return ctx.invokeCallable(args[0], args[1..]);
}

fn native_call_user_func_array(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .null;
    if (args[1] != .array) return ctx.invokeCallable(args[0], &.{});
    const arr = args[1].array;
    var call_args: [16]Value = undefined;
    const count_val: usize = @min(16, arr.entries.items.len);
    for (0..count_val) |i| call_args[i] = arr.entries.items[i].value;
    return ctx.invokeCallable(args[0], call_args[0..count_val]);
}

fn native_function_exists(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const name = args[0].string;
    if (ctx.vm.native_fns.contains(name)) return .{ .bool = true };
    if (ctx.vm.functions.contains(name)) return .{ .bool = true };
    return .{ .bool = false };
}

