const NativeResult = @import("../runtime/native_result.zig").NativeResult;
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
    var throwable = vm_mod.InterfaceDef{ .name = "Throwable", .parent = "Stringable" };
    try throwable.parents.append(a, "Stringable");
    try throwable.methods.append(a, "getMessage");
    try throwable.methods.append(a, "getCode");
    try throwable.methods.append(a, "getPrevious");
    try throwable.methods.append(a, "getTrace");
    try throwable.methods.append(a, "getTraceAsString");
    try vm.interfaces.put(a, "Throwable", throwable);

    const trace_default = try vm.allocArray();

    var exc_def = ClassDef{ .name = "Exception" };
    try exc_def.properties.append(a, .{ .name = "message", .default = .{ .string = Value.String.borrowed("") } });
    try exc_def.properties.append(a, .{ .name = "code", .default = .{ .int = 0 } });
    try exc_def.properties.append(a, .{ .name = "previous", .default = .null });
    try exc_def.properties.append(a, .{ .name = "file", .default = .{ .string = Value.String.borrowed("") } });
    try exc_def.properties.append(a, .{ .name = "line", .default = .{ .int = 0 } });
    try exc_def.properties.append(a, .{ .name = "trace", .has_default = true, .type_str = "array", .visibility = .private, .default = .{ .array = trace_default } });
    exc_def.slot_layout = try vm.buildSlotLayout(&exc_def);
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
    try err_def.properties.append(a, .{ .name = "message", .default = .{ .string = Value.String.borrowed("") } });
    try err_def.properties.append(a, .{ .name = "code", .default = .{ .int = 0 } });
    try err_def.properties.append(a, .{ .name = "previous", .default = .null });
    try err_def.properties.append(a, .{ .name = "file", .default = .{ .string = Value.String.borrowed("") } });
    try err_def.properties.append(a, .{ .name = "line", .default = .{ .int = 0 } });
    try err_def.properties.append(a, .{ .name = "trace", .has_default = true, .type_str = "array", .visibility = .private, .default = .{ .array = trace_default } });
    err_def.slot_layout = try vm.buildSlotLayout(&err_def);
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
        .{ "DOMException", "Exception" },
        .{ "TypeError", "Error" },
        .{ "ArgumentCountError", "TypeError" },
        .{ "ArithmeticError", "Error" },
        .{ "DivisionByZeroError", "ArithmeticError" },
        .{ "AssertionError", "Error" },
        .{ "FiberError", "Error" },
        .{ "ValueError", "Error" },
        .{ "UnhandledMatchError", "Error" },
        .{ "CompileError", "Error" },
        .{ "ParseError", "CompileError" },
        // PHP 8.3 date hierarchy: DateError -> Error; the three concrete
        // subclasses extend it. add the legacy DateInvalidOperationException
        // alias (PHP 8.2) at the same level
        .{ "DateError", "Error" },
        .{ "DateObjectError", "DateError" },
        .{ "DateRangeError", "DateError" },
        .{ "DateException", "Exception" },
        .{ "DateInvalidTimeZoneException", "DateException" },
        .{ "DateInvalidOperationException", "DateException" },
        .{ "DateMalformedStringException", "DateException" },
        .{ "DateMalformedIntervalStringException", "DateException" },
        .{ "DateMalformedPeriodStringException", "DateException" },
        .{ "SodiumException", "Exception" },
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

fn errorExceptionConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this_val = ctx.vm.currentFrame().vars.get("$this") orelse return NativeResult.scalar(.null);
    if (this_val != .object) return NativeResult.scalar(.null);
    const obj = this_val.object;
    if (args.len >= 1) try obj.set(ctx.allocator, "message", args[0]);
    if (args.len >= 2) try obj.set(ctx.allocator, "code", args[1]);
    if (args.len >= 3) try obj.set(ctx.allocator, "severity", args[2]);
    if (args.len >= 4) try obj.set(ctx.allocator, "file", args[3]);
    if (args.len >= 5) try obj.set(ctx.allocator, "line", args[4]);
    if (args.len >= 6) try obj.set(ctx.allocator, "previous", args[5]);
    return NativeResult.scalar(.null);
}

fn errorExceptionGetSeverity(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this_val = ctx.vm.currentFrame().vars.get("$this") orelse return NativeResult.scalar(.{ .int = 0 });
    if (this_val != .object) return NativeResult.scalar(.{ .int = 0 });
    const sev = this_val.object.get("severity");
    return NativeResult.scalar(if (sev == .int) sev else .{ .int = 0 });
}

fn exceptionConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this_val = ctx.vm.currentFrame().vars.get("$this") orelse return NativeResult.scalar(.null);
    if (this_val != .object) return NativeResult.scalar(.null);
    const obj = this_val.object;
    if (args.len >= 1) try obj.set(ctx.allocator, "message", args[0]);
    if (args.len >= 2) try obj.set(ctx.allocator, "code", args[1]);
    if (args.len >= 3) try obj.set(ctx.allocator, "previous", args[2]);
    return NativeResult.scalar(.null);
}

fn exceptionGetMessage(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this_val = ctx.vm.currentFrame().vars.get("$this") orelse return NativeResult.scalar(.null);
    if (this_val != .object) return NativeResult.scalar(.null);
    const message = this_val.object.get("message");
    return if (message == .string) NativeResult.shareString(message.string) else NativeResult.borrowed(message);
}

// php's Exception::__toString: the throwable and each previous one, the
// innermost first and every later one after "Next"
fn exceptionToString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this_val = ctx.vm.currentFrame().vars.get("$this") orelse return NativeResult.literal("");
    if (this_val != .object) return NativeResult.literal("");
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, try describe(ctx, this_val.object)));
}

// what php prints after "Uncaught ": the pending throwable's __toString, a
// user override included. when __toString throws, what it threw becomes the
// pending throwable and is described instead. null when nothing is pending
// or __toString returns no string. the caller owns the text
pub fn uncaughtDescription(vm: *VM, allocator: std.mem.Allocator) ?[]u8 {
    var engine = vm.engineCall();
    vm.native_call = &engine;
    defer vm.native_call = engine.outer;
    var attempts: usize = 0;
    while (attempts < 8) : (attempts += 1) {
        const exc = vm.pending_exception orelse return null;
        if (exc != .object) return null;
        vm.pending_exception = null;
        const result = vm.callMethod(exc.object, "__toString", &.{}) catch {
            if (vm.pending_exception != null) {
                vm.stackRelease(exc);
                continue;
            }
            vm.pending_exception = exc;
            return null;
        };
        vm.pending_exception = exc;
        if (result != .string) return null;
        return allocator.dupe(u8, result.string.bytes()) catch null;
    }
    return null;
}

pub fn describe(ctx: *NativeContext, throwable: *PhpObject) RuntimeError![]u8 {
    var text: []u8 = try ctx.allocator.alloc(u8, 0);
    errdefer ctx.allocator.free(text);
    var current: Value = .{ .object = throwable };
    while (current == .object and ctx.vm.isInstanceOf(current.object.class_name, "Throwable")) {
        const e = current.object;
        const trace = try traceString(ctx, e);
        defer ctx.allocator.free(trace);
        const message = e.get("message");
        const message_text = if (message == .string) message.string.bytes() else "";
        const file = e.get("file");
        const line = e.get("line");
        const where = .{ if (file == .string) file.string.bytes() else "", if (line == .int) line.int else 0 };
        const next: []const u8 = if (text.len > 0) "\n\nNext " else "";
        const described = if (message_text.len > 0)
            try std.fmt.allocPrint(ctx.allocator, "{s}: {s} in {s}:{d}\nStack trace:\n{s}{s}{s}", .{ e.class_name, message_text, where[0], where[1], trace, next, text })
        else
            try std.fmt.allocPrint(ctx.allocator, "{s} in {s}:{d}\nStack trace:\n{s}{s}{s}", .{ e.class_name, where[0], where[1], trace, next, text });
        ctx.allocator.free(text);
        text = described;
        current = e.get("previous");
    }
    return text;
}

fn exceptionGetCode(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this_val = ctx.vm.currentFrame().vars.get("$this") orelse return NativeResult.scalar(.null);
    if (this_val != .object) return NativeResult.scalar(.null);
    const value = this_val.object.get("code");
    return if (value == .string) NativeResult.shareString(value.string) else NativeResult.borrowed(value);
}

fn exceptionGetPrevious(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this_val = ctx.vm.currentFrame().vars.get("$this") orelse return NativeResult.scalar(.null);
    if (this_val != .object) return NativeResult.scalar(.null);
    return NativeResult.borrowed(this_val.object.get("previous"));
}

fn exceptionGetFile(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this_val = ctx.vm.currentFrame().vars.get("$this") orelse return NativeResult.scalar(.null);
    if (this_val != .object) return NativeResult.scalar(.null);
    const v = this_val.object.get("file");
    return if (v == .string) NativeResult.shareString(v.string) else NativeResult.literal("");
}

fn exceptionGetLine(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this_val = ctx.vm.currentFrame().vars.get("$this") orelse return NativeResult.scalar(.null);
    if (this_val != .object) return NativeResult.scalar(.null);
    const v = this_val.object.get("line");
    return NativeResult.scalar(if (v == .int) v else .{ .int = 0 });
}

fn exceptionGetTrace(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this_val = ctx.vm.currentFrame().vars.get("$this") orelse {
        const arr = try ctx.vm.allocArray();
        return NativeResult.borrowed(.{ .array = arr });
    };
    if (this_val == .object) {
        const t = this_val.object.getForScope("trace", ctx.vm.exceptionTraceScope(this_val.object));
        if (t == .array) return NativeResult.borrowed(t);
    }
    const arr = try ctx.vm.allocArray();
    return NativeResult.borrowed(.{ .array = arr });
}

fn exceptionGetTraceAsString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this_val = ctx.vm.currentFrame().vars.get("$this") orelse return NativeResult.literal("");
    if (this_val != .object) return NativeResult.literal("");
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, try traceString(ctx, this_val.object)));
}

fn traceString(ctx: *NativeContext, throwable: *PhpObject) RuntimeError![]u8 {
    const t = throwable.getForScope("trace", ctx.vm.exceptionTraceScope(throwable));
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(ctx.allocator);
    if (t == .array) {
        for (t.array.entries.items, 0..) |entry, i| {
            if (entry.value != .array) continue;
            const e = entry.value.array;
            const fn_v = e.get(.{ .string = Value.String.borrowed("function") });
            const line_v = e.get(.{ .string = Value.String.borrowed("line") });
            const file_v = e.get(.{ .string = Value.String.borrowed("file") });
            const class_v = e.get(.{ .string = Value.String.borrowed("class") });
            const type_v = e.get(.{ .string = Value.String.borrowed("type") });
            const fn_s = if (fn_v == .string) fn_v.string.bytes() else "?";
            const class_s = if (class_v == .string) class_v.string.bytes() else "";
            const type_s = if (type_v == .string) type_v.string.bytes() else "";
            const file_s = if (file_v == .string) file_v.string.bytes() else "";
            const line_n: i64 = if (line_v == .int) line_v.int else 0;
            // a frame with no file/line was called from an internal function
            // (a native dispatched the user callback) - PHP renders these as
            // `[internal function]` instead of the synthesized `(0)` location
            if (file_s.len == 0 and line_n == 0) {
                try buf.print(ctx.allocator, "#{d} [internal function]: {s}{s}{s}(", .{ i, class_s, type_s, fn_s });
            } else {
                try buf.print(ctx.allocator, "#{d} {s}({d}): {s}{s}{s}(", .{ i, file_s, line_n, class_s, type_s, fn_s });
            }
            const args_v = e.get(.{ .string = Value.String.borrowed("args") });
            if (args_v == .array) {
                for (args_v.array.entries.items, 0..) |arg_entry, ai| {
                    if (ai > 0) try buf.appendSlice(ctx.allocator, ", ");
                    @import("../error_format.zig").writeTraceArg(&buf, ctx.allocator, arg_entry.value);
                }
            }
            try buf.appendSlice(ctx.allocator, ")\n");
        }
        const n = t.array.entries.items.len;
        try buf.print(ctx.allocator, "#{d} {{main}}", .{n});
    } else {
        try buf.appendSlice(ctx.allocator, "#0 {main}");
    }
    return buf.toOwnedSlice(ctx.allocator);
}
