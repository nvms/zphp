const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub fn register(vm: *VM, a: Allocator) !void {
    var exc_def = ClassDef{ .name = "Exception" };
    try exc_def.properties.append(a, .{ .name = "message", .default = .{ .string = "" } });
    try exc_def.properties.append(a, .{ .name = "code", .default = .{ .int = 0 } });
    try exc_def.properties.append(a, .{ .name = "previous", .default = .null });
    try exc_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 3 });
    try exc_def.methods.put(a, "getMessage", .{ .name = "getMessage", .arity = 0 });
    try exc_def.methods.put(a, "getCode", .{ .name = "getCode", .arity = 0 });
    try exc_def.methods.put(a, "getPrevious", .{ .name = "getPrevious", .arity = 0 });
    try vm.classes.put(a, "Exception", exc_def);

    try vm.native_fns.put(a, "Exception::__construct", exceptionConstruct);
    try vm.native_fns.put(a, "Exception::getMessage", exceptionGetMessage);
    try vm.native_fns.put(a, "Exception::getCode", exceptionGetCode);
    try vm.native_fns.put(a, "Exception::getPrevious", exceptionGetPrevious);

    // hierarchy validated against PHP 8.5 (php -r 'new ReflectionClass(...)->getParentClass()')
    // note: in PHP, Error and Exception are separate (both implement Throwable).
    // zphp uses Error -> Exception as simplification so catch(Exception) catches both.
    const subclasses = .{
        .{ "RuntimeException", "Exception" },
        .{ "LogicException", "Exception" },
        .{ "InvalidArgumentException", "LogicException" },
        .{ "BadFunctionCallException", "LogicException" },
        .{ "BadMethodCallException", "BadFunctionCallException" },
        .{ "LengthException", "LogicException" },
        .{ "DomainException", "LogicException" },
        .{ "OutOfRangeException", "LogicException" },
        .{ "OverflowException", "RuntimeException" },
        .{ "RangeException", "RuntimeException" },
        .{ "UnexpectedValueException", "RuntimeException" },
        .{ "OutOfBoundsException", "RuntimeException" },
        .{ "UnderflowException", "RuntimeException" },
        .{ "PDOException", "RuntimeException" },
        .{ "JsonException", "Exception" },
        .{ "Error", "Exception" },
        .{ "TypeError", "Error" },
        .{ "ArithmeticError", "Error" },
        .{ "DivisionByZeroError", "ArithmeticError" },
        .{ "AssertionError", "Error" },
        .{ "FiberError", "Error" },
        .{ "ValueError", "Error" },
        .{ "UnhandledMatchError", "Error" },
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
    if (args.len >= 3) try obj.set(ctx.allocator, "previous", args[2]);
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

fn exceptionGetPrevious(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this_val = ctx.vm.currentFrame().vars.get("$this") orelse return .null;
    if (this_val != .object) return .null;
    return this_val.object.get("previous");
}
