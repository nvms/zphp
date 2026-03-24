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
    var iter = def.static_props.iterator();
    while (iter.next()) |entry| {
        try arr.append(ctx.allocator, entry.value_ptr.*);
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
