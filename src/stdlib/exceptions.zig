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
    var throwable = vm_mod.InterfaceDef{ .name = "Throwable" };
    try throwable.methods.append(a, "getMessage");
    try throwable.methods.append(a, "getCode");
    try throwable.methods.append(a, "getPrevious");
    try throwable.methods.append(a, "getTrace");
    try throwable.methods.append(a, "getTraceAsString");
    try vm.interfaces.put(a, "Throwable", throwable);

    var exc_def = ClassDef{ .name = "Exception" };
    try exc_def.properties.append(a, .{ .name = "message", .default = .{ .string = "" } });
    try exc_def.properties.append(a, .{ .name = "code", .default = .{ .int = 0 } });
    try exc_def.properties.append(a, .{ .name = "previous", .default = .null });
    try exc_def.properties.append(a, .{ .name = "file", .default = .{ .string = "" } });
    try exc_def.properties.append(a, .{ .name = "line", .default = .{ .int = 0 } });
    try exc_def.interfaces.append(a, "Throwable");
    try exc_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 3 });
    try exc_def.methods.put(a, "getMessage", .{ .name = "getMessage", .arity = 0 });
    try exc_def.methods.put(a, "getCode", .{ .name = "getCode", .arity = 0 });
    try exc_def.methods.put(a, "getPrevious", .{ .name = "getPrevious", .arity = 0 });
    try exc_def.methods.put(a, "getFile", .{ .name = "getFile", .arity = 0 });
    try exc_def.methods.put(a, "getLine", .{ .name = "getLine", .arity = 0 });
    try exc_def.methods.put(a, "getTrace", .{ .name = "getTrace", .arity = 0 });
    try exc_def.methods.put(a, "getTraceAsString", .{ .name = "getTraceAsString", .arity = 0 });
    try vm.classes.put(a, "Exception", exc_def);

    try vm.native_fns.put(a, "Exception::__construct", exceptionConstruct);
    try vm.native_fns.put(a, "Exception::getMessage", exceptionGetMessage);
    try vm.native_fns.put(a, "Exception::getCode", exceptionGetCode);
    try vm.native_fns.put(a, "Exception::getPrevious", exceptionGetPrevious);
    try vm.native_fns.put(a, "Exception::getFile", exceptionGetFile);
    try vm.native_fns.put(a, "Exception::getLine", exceptionGetLine);
    try vm.native_fns.put(a, "Exception::getTrace", exceptionGetTrace);
    try vm.native_fns.put(a, "Exception::getTraceAsString", exceptionGetTraceAsString);

    var err_def = ClassDef{ .name = "Error" };
    try err_def.properties.append(a, .{ .name = "message", .default = .{ .string = "" } });
    try err_def.properties.append(a, .{ .name = "code", .default = .{ .int = 0 } });
    try err_def.properties.append(a, .{ .name = "previous", .default = .null });
    try err_def.properties.append(a, .{ .name = "file", .default = .{ .string = "" } });
    try err_def.properties.append(a, .{ .name = "line", .default = .{ .int = 0 } });
    try err_def.interfaces.append(a, "Throwable");
    try err_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 3 });
    try err_def.methods.put(a, "getMessage", .{ .name = "getMessage", .arity = 0 });
    try err_def.methods.put(a, "getCode", .{ .name = "getCode", .arity = 0 });
    try err_def.methods.put(a, "getPrevious", .{ .name = "getPrevious", .arity = 0 });
    try err_def.methods.put(a, "getFile", .{ .name = "getFile", .arity = 0 });
    try err_def.methods.put(a, "getLine", .{ .name = "getLine", .arity = 0 });
    try err_def.methods.put(a, "getTrace", .{ .name = "getTrace", .arity = 0 });
    try err_def.methods.put(a, "getTraceAsString", .{ .name = "getTraceAsString", .arity = 0 });
    try vm.classes.put(a, "Error", err_def);

    try vm.native_fns.put(a, "Error::__construct", exceptionConstruct);
    try vm.native_fns.put(a, "Error::getMessage", exceptionGetMessage);
    try vm.native_fns.put(a, "Error::getCode", exceptionGetCode);
    try vm.native_fns.put(a, "Error::getPrevious", exceptionGetPrevious);
    try vm.native_fns.put(a, "Error::getFile", exceptionGetFile);
    try vm.native_fns.put(a, "Error::getLine", exceptionGetLine);
    try vm.native_fns.put(a, "Error::getTrace", exceptionGetTrace);
    try vm.native_fns.put(a, "Error::getTraceAsString", exceptionGetTraceAsString);

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
    try obj.set(ctx.allocator, "file", .{ .string = ctx.vm.file_path });
    if (ctx.vm.frame_count > 1) {
        const caller = ctx.vm.frames[ctx.vm.frame_count - 2];
        const ip = if (caller.ip > 0) caller.ip - 1 else 0;
        if (caller.chunk.getSourceLocation(ip, ctx.vm.source)) |loc| {
            try obj.set(ctx.allocator, "line", .{ .int = @as(i64, @intCast(loc.line)) });
        }
    }
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

fn exceptionGetFile(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this_val = ctx.vm.currentFrame().vars.get("$this") orelse return .null;
    if (this_val != .object) return .null;
    const v = this_val.object.get("file");
    return if (v == .string) v else .{ .string = "" };
}

fn exceptionGetLine(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this_val = ctx.vm.currentFrame().vars.get("$this") orelse return .null;
    if (this_val != .object) return .null;
    const v = this_val.object.get("line");
    return if (v == .int) v else .{ .int = 0 };
}

fn exceptionGetTrace(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const PhpArray = @import("../runtime/value.zig").PhpArray;
    const arr = try ctx.vm.allocator.create(PhpArray);
    arr.* = .{};
    try ctx.vm.arrays.append(ctx.vm.allocator, arr);
    return .{ .array = arr };
}

fn exceptionGetTraceAsString(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .string = "" };
}
