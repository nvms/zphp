const std = @import("std");
const Value = @import("value.zig").Value;
const PhpObject = @import("value.zig").PhpObject;
const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub fn register(vm: *VM, a: Allocator) !void {
    // Exception base class
    var exc_def = ClassDef{ .name = "Exception" };
    try exc_def.properties.append(a, .{ .name = "message", .default = .{ .string = "" } });
    try exc_def.properties.append(a, .{ .name = "code", .default = .{ .int = 0 } });
    try exc_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 2 });
    try exc_def.methods.put(a, "getMessage", .{ .name = "getMessage", .arity = 0 });
    try exc_def.methods.put(a, "getCode", .{ .name = "getCode", .arity = 0 });
    try vm.classes.put(a, "Exception", exc_def);

    try vm.native_fns.put(a, "Exception::__construct", exceptionConstruct);
    try vm.native_fns.put(a, "Exception::getMessage", exceptionGetMessage);
    try vm.native_fns.put(a, "Exception::getCode", exceptionGetCode);

    // standard exception subclasses
    const subclasses = .{
        .{ "RuntimeException", "Exception" },
        .{ "InvalidArgumentException", "Exception" },
        .{ "LogicException", "Exception" },
        .{ "BadMethodCallException", "LogicException" },
        .{ "OverflowException", "RuntimeException" },
        .{ "TypeError", "Exception" },
        .{ "RangeException", "RuntimeException" },
        .{ "UnexpectedValueException", "RuntimeException" },
        .{ "LengthException", "LogicException" },
        .{ "DomainException", "LogicException" },
        .{ "OutOfRangeException", "RuntimeException" },
        .{ "OutOfBoundsException", "RuntimeException" },
        .{ "UnderflowException", "RuntimeException" },
        .{ "ArithmeticError", "Exception" },
        .{ "DivisionByZeroError", "ArithmeticError" },
    };

    inline for (subclasses) |entry| {
        var def = ClassDef{ .name = entry[0] };
        def.parent = entry[1];
        try vm.classes.put(a, entry[0], def);
    }
}

fn exceptionConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const this_val = ctx.vm.currentFrame().vars.get("$this") orelse return .null;
    if (this_val != .object) return .null;
    const obj = this_val.object;
    if (args.len >= 1) try obj.set(ctx.allocator, "message", args[0]);
    if (args.len >= 2) try obj.set(ctx.allocator, "code", args[1]);
    return .null;
}

fn exceptionGetMessage(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this_val = ctx.vm.currentFrame().vars.get("$this") orelse return .null;
    if (this_val != .object) return .null;
    return this_val.object.get("message");
}

fn exceptionGetCode(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this_val = ctx.vm.currentFrame().vars.get("$this") orelse return .null;
    if (this_val != .object) return .null;
    return this_val.object.get("code");
}
