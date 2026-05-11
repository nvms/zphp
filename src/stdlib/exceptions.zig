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
    try exc_def.methods.put(a, "__toString", .{ .name = "__toString", .arity = 0 });
    try exc_def.interfaces.append(a, "Stringable");
    try vm.classes.put(a, "Exception", exc_def);

    try vm.native_fns.put(a, "Exception::__construct", exceptionConstruct);
    try vm.native_fns.put(a, "Exception::getMessage", exceptionGetMessage);
    try vm.native_fns.put(a, "Exception::getCode", exceptionGetCode);
    try vm.native_fns.put(a, "Exception::getPrevious", exceptionGetPrevious);
    try vm.native_fns.put(a, "Exception::getFile", exceptionGetFile);
    try vm.native_fns.put(a, "Exception::getLine", exceptionGetLine);
    try vm.native_fns.put(a, "Exception::getTrace", exceptionGetTrace);
    try vm.native_fns.put(a, "Exception::getTraceAsString", exceptionGetTraceAsString);
    try vm.native_fns.put(a, "Exception::__toString", exceptionToString);

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
    try err_def.methods.put(a, "__toString", .{ .name = "__toString", .arity = 0 });
    try err_def.interfaces.append(a, "Stringable");
    try vm.classes.put(a, "Error", err_def);

    try vm.native_fns.put(a, "Error::__construct", exceptionConstruct);
    try vm.native_fns.put(a, "Error::getMessage", exceptionGetMessage);
    try vm.native_fns.put(a, "Error::getCode", exceptionGetCode);
    try vm.native_fns.put(a, "Error::getPrevious", exceptionGetPrevious);
    try vm.native_fns.put(a, "Error::getFile", exceptionGetFile);
    try vm.native_fns.put(a, "Error::getLine", exceptionGetLine);
    try vm.native_fns.put(a, "Error::getTrace", exceptionGetTrace);
    try vm.native_fns.put(a, "Error::getTraceAsString", exceptionGetTraceAsString);
    try vm.native_fns.put(a, "Error::__toString", exceptionToString);

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

    // ErrorException: extends Exception, adds $severity + getSeverity()
    var ee_def = ClassDef{ .name = "ErrorException" };
    ee_def.parent = "Exception";
    try ee_def.properties.append(a, .{ .name = "severity", .default = .{ .int = 0 } });
    try ee_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 0 });
    try ee_def.methods.put(a, "getSeverity", .{ .name = "getSeverity", .arity = 0 });
    try vm.classes.put(a, "ErrorException", ee_def);
    try vm.native_fns.put(a, "ErrorException::__construct", errorExceptionConstruct);
    try vm.native_fns.put(a, "ErrorException::getSeverity", errorExceptionGetSeverity);
}

fn errorExceptionConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const this_val = ctx.vm.currentFrame().vars.get("$this") orelse return .null;
    if (this_val != .object) return .null;
    const obj = this_val.object;
    if (args.len >= 1) try obj.set(ctx.allocator, "message", args[0]);
    if (args.len >= 2) try obj.set(ctx.allocator, "code", args[1]);
    if (args.len >= 3) try obj.set(ctx.allocator, "severity", args[2]);
    if (args.len >= 4) try obj.set(ctx.allocator, "file", args[3]);
    if (args.len >= 5) try obj.set(ctx.allocator, "line", args[4]);
    if (args.len >= 6) try obj.set(ctx.allocator, "previous", args[5]);
    return .null;
}

fn errorExceptionGetSeverity(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this_val = ctx.vm.currentFrame().vars.get("$this") orelse return .{ .int = 0 };
    if (this_val != .object) return .{ .int = 0 };
    const sev = this_val.object.get("severity");
    return if (sev == .int) sev else .{ .int = 0 };
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

fn exceptionToString(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this_val = ctx.vm.currentFrame().vars.get("$this") orelse return .{ .string = "" };
    if (this_val != .object) return .{ .string = "" };
    const obj = this_val.object;
    const msg = obj.get("message");
    const msg_str = if (msg == .string) msg.string else "";
    const file = obj.get("file");
    const file_str = if (file == .string) file.string else "";
    const line = obj.get("line");
    const line_int = if (line == .int) line.int else 0;
    const s = try std.fmt.allocPrint(ctx.allocator, "{s}: {s} in {s}:{d}\nStack trace:\n#0 {{main}}", .{ obj.class_name, msg_str, file_str, line_int });
    try ctx.vm.strings.append(ctx.allocator, s);
    return .{ .string = s };
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
