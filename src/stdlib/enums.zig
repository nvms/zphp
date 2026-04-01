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

pub fn enumFrom(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return error.RuntimeError;
    const enum_name = enumClassFromCallName(ctx) orelse return error.RuntimeError;
    const def = ctx.vm.classes.get(enum_name) orelse return error.RuntimeError;
    var iter = def.static_props.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.* == .object) {
            const case_val = entry.value_ptr.*.object.get("value");
            if (Value.identical(case_val, args[0])) return entry.value_ptr.*;
        }
    }
    const arg_str = if (args[0] == .string) args[0].string else if (args[0] == .int) "int" else "value";
    const msg = std.fmt.allocPrint(ctx.allocator, "{s} is not a valid backing value for enum \"{s}\"", .{ arg_str, enum_name }) catch return error.RuntimeError;
    try ctx.vm.strings.append(ctx.allocator, msg);
    const obj = try ctx.allocator.create(@import("../runtime/value.zig").PhpObject);
    obj.* = .{ .class_name = "ValueError" };
    try obj.set(ctx.allocator, "message", .{ .string = msg });
    try obj.set(ctx.allocator, "code", .{ .int = 0 });
    try ctx.vm.objects.append(ctx.allocator, obj);
    ctx.vm.pending_exception = .{ .object = obj };
    return error.RuntimeError;
}

pub fn enumTryFrom(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .null;
    const enum_name = enumClassFromCallName(ctx) orelse return .null;
    const def = ctx.vm.classes.get(enum_name) orelse return .null;
    var iter = def.static_props.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.* == .object) {
            const case_val = entry.value_ptr.*.object.get("value");
            if (Value.identical(case_val, args[0])) return entry.value_ptr.*;
        }
    }
    return .null;
}
