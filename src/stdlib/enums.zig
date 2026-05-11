const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

fn enumClassFromCallName(ctx: *NativeContext) ?[]const u8 {
    const name = ctx.call_name orelse return null;
    if (std.mem.indexOf(u8, name, "::")) |sep| return name[0..sep];
    return null;
}

pub fn enumCases(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const enum_name = enumClassFromCallName(ctx) orelse return error.RuntimeError;
    const def = ctx.vm.classes.get(enum_name) orelse return error.RuntimeError;
    var arr = try ctx.createArray();
    for (def.case_order.items) |name| {
        if (def.static_props.get(name)) |val| {
            try arr.append(ctx.allocator, val);
        }
    }
    return .{ .array = arr };
}

fn coerceForLookup(ctx: *NativeContext, def_backed: anytype, arg: Value) !Value {
    return switch (def_backed) {
        .int_type => switch (arg) {
            .int => arg,
            .string => |s| blk: {
                const i = std.fmt.parseInt(i64, s, 10) catch break :blk arg;
                break :blk .{ .int = i };
            },
            else => arg,
        },
        .string_type => switch (arg) {
            .string => arg,
            .int => |n| blk: {
                const s = try std.fmt.allocPrint(ctx.allocator, "{d}", .{n});
                try ctx.vm.strings.append(ctx.allocator, s);
                break :blk .{ .string = s };
            },
            else => arg,
        },
        else => arg,
    };
}

fn throwBuiltin(ctx: *NativeContext, class: []const u8, msg: []const u8) RuntimeError!Value {
    const obj = try ctx.allocator.create(@import("../runtime/value.zig").PhpObject);
    obj.* = .{ .class_name = class };
    try obj.set(ctx.allocator, "message", .{ .string = msg });
    try obj.set(ctx.allocator, "code", .{ .int = 0 });
    try ctx.vm.objects.append(ctx.allocator, obj);
    ctx.vm.pending_exception = .{ .object = obj };
    return error.RuntimeError;
}

fn argDisplayString(ctx: *NativeContext, arg: Value) ![]const u8 {
    return switch (arg) {
        .string => |s| blk: {
            const out = try std.fmt.allocPrint(ctx.allocator, "\"{s}\"", .{s});
            try ctx.vm.strings.append(ctx.allocator, out);
            break :blk out;
        },
        .int => |n| blk: {
            const s = try std.fmt.allocPrint(ctx.allocator, "{d}", .{n});
            try ctx.vm.strings.append(ctx.allocator, s);
            break :blk s;
        },
        else => "value",
    };
}

fn valueTypeName(v: Value) []const u8 {
    return switch (v) {
        .int => "int",
        .float => "float",
        .string => "string",
        .bool => "bool",
        .null => "null",
        .array => "array",
        .object => "object",
        else => "value",
    };
}

fn isNumericIntStr(s: []const u8) bool {
    if (s.len == 0) return false;
    var i: usize = 0;
    if (s[0] == '+' or s[0] == '-') i = 1;
    if (i >= s.len) return false;
    while (i < s.len) : (i += 1) {
        if (s[i] < '0' or s[i] > '9') return false;
    }
    return true;
}

fn checkEnumArgType(ctx: *NativeContext, backed: anytype, enum_name: []const u8, fn_name: []const u8, arg: Value) RuntimeError!?Value {
    const want: []const u8 = switch (backed) {
        .int_type => "int",
        .string_type => "string",
        else => return null,
    };
    const ok: bool = switch (backed) {
        .int_type => arg == .int or arg == .float or (arg == .string and isNumericIntStr(arg.string)),
        .string_type => arg == .string or arg == .int,
        else => true,
    };
    if (ok) return null;
    const msg = try std.fmt.allocPrint(ctx.allocator, "{s}::{s}(): Argument #1 ($value) must be of type {s}, {s} given", .{ enum_name, fn_name, want, valueTypeName(arg) });
    try ctx.vm.strings.append(ctx.allocator, msg);
    _ = try throwBuiltin(ctx, "TypeError", msg);
    return null;
}

pub fn enumFrom(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return error.RuntimeError;
    const enum_name = enumClassFromCallName(ctx) orelse return error.RuntimeError;
    const def = ctx.vm.classes.get(enum_name) orelse return error.RuntimeError;
    if (try checkEnumArgType(ctx, def.backed_type, enum_name, "from", args[0])) |err_val| return err_val;
    const lookup = try coerceForLookup(ctx, def.backed_type, args[0]);
    var iter = def.static_props.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.* == .object) {
            const case_val = entry.value_ptr.*.object.get("value");
            if (Value.identical(case_val, lookup)) return entry.value_ptr.*;
        }
    }
    const arg_str = try argDisplayString(ctx, args[0]);
    const msg = try std.fmt.allocPrint(ctx.allocator, "{s} is not a valid backing value for enum {s}", .{ arg_str, enum_name });
    try ctx.vm.strings.append(ctx.allocator, msg);
    return throwBuiltin(ctx, "ValueError", msg);
}

pub fn enumTryFrom(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .null;
    const enum_name = enumClassFromCallName(ctx) orelse return .null;
    const def = ctx.vm.classes.get(enum_name) orelse return .null;
    if (try checkEnumArgType(ctx, def.backed_type, enum_name, "tryFrom", args[0])) |err_val| return err_val;
    const lookup = try coerceForLookup(ctx, def.backed_type, args[0]);
    var iter = def.static_props.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.* == .object) {
            const case_val = entry.value_ptr.*.object.get("value");
            if (Value.identical(case_val, lookup)) return entry.value_ptr.*;
        }
    }
    return .null;
}
