const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const ClassDef = @import("../runtime/vm.zig").ClassDef;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "count", count },
    .{ "strlen", strlen },
    .{ "intval", intval },
    .{ "floatval", floatval },
    .{ "strval", strval },
    .{ "gettype", gettype },
    .{ "get_debug_type", get_debug_type },
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
    .{ "get_defined_constants", native_get_defined_constants },
    .{ "is_object", is_object },
    .{ "get_class", get_class },
    .{ "get_called_class", get_called_class },
    .{ "class_exists", class_exists },
    .{ "method_exists", method_exists },
    .{ "property_exists", property_exists },
    .{ "is_callable", native_is_callable },
    .{ "settype", native_settype },
    .{ "call_user_func", native_call_user_func },
    .{ "call_user_func_array", native_call_user_func_array },
    .{ "function_exists", native_function_exists },
    .{ "get_object_vars", native_get_object_vars },
    .{ "get_class_methods", native_get_class_methods },
    .{ "get_class_vars", native_get_class_vars },
    .{ "get_parent_class", native_get_parent_class },
    .{ "is_a", native_is_a },
    .{ "is_subclass_of", native_is_subclass_of },
    .{ "spl_object_id", native_spl_object_id },
    .{ "exit", native_exit },
    .{ "die", native_exit },
    .{ "version_compare", native_version_compare },
    .{ "php_sapi_name", native_php_sapi_name },
    .{ "php_version", native_php_version },
    .{ "phpversion", native_php_version },
    .{ "getmypid", native_getmypid },
    .{ "getmyuid", native_getmyuid },
    .{ "getmygid", native_getmygid },
    .{ "getmyinode", native_noop_zero },
    .{ "ini_get", native_ini_get },
    .{ "get_cfg_var", native_get_cfg_var },
    .{ "ini_set", native_ini_set },
    .{ "extension_loaded", native_extension_loaded },
    .{ "get_included_files", native_get_included_files },
    .{ "get_required_files", native_get_included_files },
    .{ "memory_get_usage", native_memory_get_usage },
    .{ "memory_get_peak_usage", native_memory_get_usage },
    .{ "gc_enabled", native_noop_true },
    .{ "gc_disable", native_noop_null },
    .{ "gc_enable", native_noop_null },
    .{ "gc_collect_cycles", native_noop_zero },
    .{ "set_error_handler", native_set_error_handler },
    .{ "set_exception_handler", native_set_exception_handler },
    .{ "restore_error_handler", native_restore_error_handler },
    .{ "restore_exception_handler", native_noop_true },
    .{ "register_shutdown_function", native_register_shutdown_function },
    .{ "error_reporting", native_error_reporting },
    .{ "error_get_last", native_error_get_last },
    .{ "error_clear_last", native_noop_null },
    .{ "get_include_path", native_get_include_path },
    .{ "set_include_path", native_set_include_path },
    .{ "restore_include_path", native_noop_null },
    .{ "trigger_error", native_trigger_error },
    .{ "user_error", native_trigger_error },
    .{ "class_alias", native_class_alias },
    .{ "assert", native_assert },
    .{ "spl_autoload_register", native_spl_autoload_register },
    .{ "spl_autoload_unregister", native_spl_autoload_unregister },
    .{ "spl_autoload_functions", native_spl_autoload_functions },
    .{ "spl_object_hash", native_spl_object_hash },
    .{ "is_scalar", is_scalar },
    .{ "is_iterable", is_iterable },
    .{ "is_countable", is_countable },
    .{ "ctype_alpha", ctype_alpha },
    .{ "ctype_digit", ctype_digit },
    .{ "ctype_alnum", ctype_alnum },
    .{ "ctype_space", ctype_space },
    .{ "ctype_upper", ctype_upper },
    .{ "ctype_lower", ctype_lower },
    .{ "ctype_xdigit", ctype_xdigit },
    .{ "ctype_print", ctype_print },
    .{ "ctype_punct", ctype_punct },
    .{ "ctype_cntrl", ctype_cntrl },
    .{ "ctype_graph", ctype_graph },
    .{ "func_get_args", native_func_get_args },
    .{ "func_num_args", native_func_num_args },
    .{ "func_get_arg", native_func_get_arg },
    .{ "interface_exists", native_interface_exists },
    .{ "enum_exists", native_enum_exists },
    .{ "class_implements", native_class_implements },
    .{ "class_parents", native_class_parents },
    .{ "class_uses", native_class_uses },
    .{ "iterator_to_array", native_iterator_to_array },
    .{ "iterator_count", native_iterator_count },
    .{ "iterator_apply", native_iterator_apply },
    .{ "filter_var", native_filter_var },
    .{ "is_resource", native_is_resource },
    .{ "get_resource_type", native_get_resource_type },
    .{ "token_get_all", native_token_get_all },
    .{ "token_name", native_token_name },
};

fn native_define(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string) return .{ .bool = false };
    if (ctx.vm.php_constants.contains(args[0].string)) return .{ .bool = false };
    try ctx.vm.user_constants.put(ctx.allocator, args[0].string, {});
    try ctx.vm.php_constants.put(ctx.allocator, args[0].string, args[1]);
    return .{ .bool = true };
}

fn native_defined(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const name = args[0].string;
    if (ctx.vm.php_constants.contains(name)) return .{ .bool = true };
    if (std.mem.indexOf(u8, name, "::")) |sep| {
        const class_name = name[0..sep];
        const prop_name = name[sep + 2 ..];
        if (ctx.vm.getStaticProp(class_name, prop_name) != null) return .{ .bool = true };
    }
    return .{ .bool = false };
}

fn native_constant(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .null;
    const name = args[0].string;
    if (ctx.vm.php_constants.get(name)) |v| return v;
    if (std.mem.indexOf(u8, name, "::")) |sep| {
        const class_name = name[0..sep];
        const prop_name = name[sep + 2 ..];
        if (ctx.vm.getStaticProp(class_name, prop_name)) |v| return v;
    }
    const msg = try std.fmt.allocPrint(ctx.allocator, "Undefined constant \"{s}\"", .{name});
    try ctx.strings.append(ctx.allocator, msg);
    try ctx.vm.setPendingException("Error", msg);
    return error.RuntimeError;
}

fn native_get_defined_constants(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const categorize = args.len >= 1 and args[0].isTruthy();
    if (categorize) {
        const root = try ctx.createArray();
        const internal = try ctx.createArray();
        const user = try ctx.createArray();
        var it = ctx.vm.php_constants.iterator();
        while (it.next()) |entry| {
            const name = entry.key_ptr.*;
            if (ctx.vm.user_constants.contains(name)) {
                try user.set(ctx.allocator, .{ .string = name }, entry.value_ptr.*);
            } else {
                try internal.set(ctx.allocator, .{ .string = name }, entry.value_ptr.*);
            }
        }
        try root.set(ctx.allocator, .{ .string = "Core" }, .{ .array = internal });
        try root.set(ctx.allocator, .{ .string = "user" }, .{ .array = user });
        return .{ .array = root };
    }
    const flat = try ctx.createArray();
    var it = ctx.vm.php_constants.iterator();
    while (it.next()) |entry| {
        try flat.set(ctx.allocator, .{ .string = entry.key_ptr.* }, entry.value_ptr.*);
    }
    return .{ .array = flat };
}

fn countRecursive(a: *const PhpArray) i64 {
    var total: i64 = a.length();
    for (a.entries.items) |entry| {
        if (entry.value == .array) {
            total += countRecursive(entry.value.array);
        }
    }
    return total;
}

fn count(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
    const recursive = args.len >= 2 and args[1] == .int and args[1].int == 1;
    return switch (args[0]) {
        .array => |a| .{ .int = if (recursive) countRecursive(a) else a.length() },
        .object => |obj| {
            if (ctx.vm.hasMethod(obj.class_name, "count")) {
                return ctx.vm.callMethod(obj, "count", &.{}) catch .{ .int = 1 };
            }
            return .{ .int = 1 };
        },
        else => .{ .int = 1 },
    };
}

fn intval(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
    if (args.len >= 2 and args[1] == .int and args[1].int != 10 and args[0] == .string) {
        var base: u8 = @intCast(@max(0, @min(36, args[1].int)));
        var s = std.mem.trim(u8, args[0].string, " \t\n\r");
        var negative = false;
        if (s.len > 0 and (s[0] == '-' or s[0] == '+')) {
            negative = s[0] == '-';
            s = s[1..];
        }
        // base 0 means auto-detect from prefix: 0x = hex, 0b = binary, 0 = octal
        if (base == 0) {
            if (s.len >= 2 and s[0] == '0' and (s[1] == 'x' or s[1] == 'X')) {
                base = 16;
                s = s[2..];
            } else if (s.len >= 2 and s[0] == '0' and (s[1] == 'b' or s[1] == 'B')) {
                base = 2;
                s = s[2..];
            } else if (s.len >= 1 and s[0] == '0') {
                base = 8;
                s = s[1..];
            } else {
                base = 10;
            }
        } else {
            if (base == 16 and s.len >= 2 and s[0] == '0' and (s[1] == 'x' or s[1] == 'X')) s = s[2..];
            if (base == 8 and s.len >= 1 and s[0] == '0') s = s[1..];
            if (base == 2 and s.len >= 2 and s[0] == '0' and (s[1] == 'b' or s[1] == 'B')) s = s[2..];
        }
        if (base < 2) base = 10;
        const v = std.fmt.parseInt(i64, s, base) catch 0;
        return .{ .int = if (negative) -v else v };
    }
    // PHP: intval(array) is 0 for empty array, 1 for non-empty
    if (args[0] == .array) {
        return .{ .int = if (args[0].array.entries.items.len == 0) @as(i64, 0) else @as(i64, 1) };
    }
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
        .string => |s| if (std.mem.startsWith(u8, s, "__closure_")) "object" else "string",
        .array => "array",
        .object => |o| if (std.mem.eql(u8, o.class_name, "FileHandle")) "resource" else "object",
        .generator, .fiber => "object",
    } };
}

fn get_debug_type(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "null" };
    return .{ .string = switch (args[0]) {
        .null => "null",
        .bool => "bool",
        .int => "int",
        .float => "float",
        .string => |s| if (std.mem.startsWith(u8, s, "__closure_")) "Closure" else "string",
        .array => "array",
        .object => |o| o.class_name,
        .generator => "Generator",
        .fiber => "Fiber",
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
    if (args.len == 0) return .{ .bool = false };
    if (args[0] != .string) return .{ .bool = false };
    return .{ .bool = !std.mem.startsWith(u8, args[0].string, "__closure_") };
}

fn is_bool(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return .{ .bool = args.len > 0 and args[0] == .bool };
}

fn is_numeric(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    return .{ .bool = switch (args[0]) {
        .int, .float => true,
        .string => |s| blk: {
            // trim leading/trailing whitespace (PHP 8 accepts it)
            var trimmed = s;
            while (trimmed.len > 0 and (trimmed[0] == ' ' or trimmed[0] == '\t' or trimmed[0] == '\n' or trimmed[0] == '\r')) trimmed = trimmed[1..];
            while (trimmed.len > 0 and (trimmed[trimmed.len - 1] == ' ' or trimmed[trimmed.len - 1] == '\t' or trimmed[trimmed.len - 1] == '\n' or trimmed[trimmed.len - 1] == '\r')) trimmed = trimmed[0 .. trimmed.len - 1];
            if (trimmed.len == 0) break :blk false;
            var start: usize = 0;
            if (trimmed[0] == '+' or trimmed[0] == '-') start = 1;
            if (start >= trimmed.len) break :blk false;
            if (trimmed.len > start + 1 and trimmed[start] == '0') {
                const next = trimmed[start + 1];
                if (next == 'x' or next == 'X' or next == 'o' or next == 'O' or next == 'b' or next == 'B')
                    break :blk false;
            }
            break :blk if (std.fmt.parseFloat(f64, trimmed)) |_| true else |_| false;
        },
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
    if (args.len == 0) return .{ .bool = false };
    if (args[0] == .object) return .{ .bool = true };
    if (args[0] == .generator) return .{ .bool = true };
    if (args[0] == .fiber) return .{ .bool = true };
    if (args[0] == .string and std.mem.startsWith(u8, args[0].string, "__closure_")) return .{ .bool = true };
    return .{ .bool = false };
}

fn is_scalar(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    return .{ .bool = switch (args[0]) {
        .int, .float, .string, .bool => true,
        else => false,
    } };
}

fn is_iterable(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    return .{ .bool = switch (args[0]) {
        .array, .generator => true,
        else => false,
    } };
}

fn is_countable(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    return .{ .bool = args[0] == .array };
}

fn ctypeCheck(args: []const Value, comptime pred: fn (u8) bool) Value {
    if (args.len == 0) return .{ .bool = false };
    // PHP 8.1+: int args in [-128, 255] are interpreted as a single ASCII char
    // (negative gets +256). Other ints are interpreted as the decimal string.
    if (args[0] == .int) {
        const i = args[0].int;
        if (i >= -128 and i <= 255) {
            const code: u8 = if (i < 0) @intCast(i + 256) else @intCast(i);
            return .{ .bool = pred(code) };
        }
        var buf: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return Value{ .bool = false };
        for (s) |c| if (!pred(c)) return Value{ .bool = false };
        return .{ .bool = true };
    }
    if (args[0] != .string) return .{ .bool = false };
    const s = args[0].string;
    if (s.len == 0) return .{ .bool = false };
    for (s) |c| {
        if (!pred(c)) return .{ .bool = false };
    }
    return .{ .bool = true };
}

fn ctype_alpha(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return ctypeCheck(args, std.ascii.isAlphabetic);
}
fn ctype_digit(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return ctypeCheck(args, std.ascii.isDigit);
}
fn ctype_alnum(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return ctypeCheck(args, std.ascii.isAlphanumeric);
}
fn ctype_space(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return ctypeCheck(args, std.ascii.isWhitespace);
}
fn ctype_upper(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return ctypeCheck(args, std.ascii.isUpper);
}
fn ctype_lower(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return ctypeCheck(args, std.ascii.isLower);
}
fn ctype_xdigit(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return ctypeCheck(args, std.ascii.isHex);
}
fn ctype_print(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return ctypeCheck(args, std.ascii.isPrint);
}
fn ctype_punct(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return ctypeCheck(args, isPunct);
}
fn ctype_cntrl(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return ctypeCheck(args, std.ascii.isControl);
}
fn ctype_graph(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return ctypeCheck(args, isGraph);
}

fn isPunct(c: u8) bool {
    return std.ascii.isPrint(c) and !std.ascii.isAlphanumeric(c) and c != ' ';
}
fn isGraph(c: u8) bool {
    return std.ascii.isPrint(c) and c != ' ';
}

fn get_class(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) {
        const this_val = ctx.vm.currentFrame().vars.get("$this") orelse return Value{ .bool = false };
        if (this_val != .object) return .{ .bool = false };
        return .{ .string = this_val.object.class_name };
    }
    if (args[0] == .object) return .{ .string = args[0].object.class_name };
    if (args[0] == .generator) return .{ .string = "Generator" };
    if (args[0] == .fiber) return .{ .string = "Fiber" };
    if (args[0] == .string and std.mem.startsWith(u8, args[0].string, "__closure_")) return .{ .string = "Closure" };
    return .{ .bool = false };
}

fn get_called_class(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    var i = ctx.vm.frame_count;
    while (i > 0) {
        i -= 1;
        if (ctx.vm.frames[i].called_class) |cc| return .{ .string = cc };
    }
    return .{ .bool = false };
}

fn class_exists(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const name = args[0].string;
    if (std.mem.eql(u8, name, "stdClass") or std.mem.eql(u8, name, "Attribute")) return .{ .bool = true };
    if (ctx.vm.classes.contains(name)) return .{ .bool = true };
    const autoload = args.len < 2 or !(args[1] == .bool and !args[1].bool);
    if (autoload and ctx.vm.autoload_callbacks.items.len > 0) {
        try ctx.vm.tryAutoload(name);
        return .{ .bool = ctx.vm.classes.contains(name) };
    }
    return .{ .bool = false };
}

fn method_exists(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[1] != .string) return .{ .bool = false };
    var current: ?[]const u8 = if (args[0] == .object)
        args[0].object.class_name
    else if (args[0] == .generator)
        "Generator"
    else if (args[0] == .fiber)
        "Fiber"
    else if (args[0] == .string)
        args[0].string
    else
        return Value{ .bool = false };
    const method_name = args[1].string;
    // Generator and Fiber are not registered as ClassDef. Hardcode their
    // method tables so method_exists works on tagged values and "Generator"/"Fiber" strings.
    if (std.mem.eql(u8, current.?, "Generator")) {
        const gen_methods = [_][]const u8{ "current", "key", "next", "rewind", "send", "throw", "getReturn", "valid" };
        for (gen_methods) |m| if (std.mem.eql(u8, m, method_name)) return .{ .bool = true };
        return .{ .bool = false };
    }
    if (std.mem.eql(u8, current.?, "Fiber")) {
        const fiber_methods = [_][]const u8{ "start", "resume", "throw", "getReturn", "isStarted", "isSuspended", "isRunning", "isTerminated", "suspend", "getCurrent" };
        for (fiber_methods) |m| if (std.mem.eql(u8, m, method_name)) return .{ .bool = true };
        return .{ .bool = false };
    }
    var buf: [256]u8 = undefined;
    var depth: usize = 0;
    while (current) |cn| {
        var private_at_this_class = false;
        if (ctx.vm.classes.get(cn)) |cls| {
            if (cls.methods.get(method_name)) |info| {
                if (info.visibility == .private) private_at_this_class = true;
            }
        }
        // ancestor private methods are not visible from a subclass
        if (depth > 0 and private_at_this_class) {
            // skip this class's match; continue up
        } else {
            const full = std.fmt.bufPrint(&buf, "{s}::{s}", .{ cn, method_name }) catch return Value{ .bool = false };
            if (ctx.vm.native_fns.contains(full)) return .{ .bool = true };
            if (ctx.vm.functions.contains(full)) return .{ .bool = true };
            if (ctx.vm.classes.get(cn)) |cls| {
                if (cls.methods.contains(method_name)) return .{ .bool = true };
            }
        }
        if (ctx.vm.classes.get(cn)) |cls| {
            current = cls.parent;
        } else {
            ctx.vm.tryAutoload(cn) catch {};
            if (ctx.vm.classes.get(cn)) |cls| {
                current = cls.parent;
            } else break;
        }
        depth += 1;
    }
    return .{ .bool = false };
}

fn property_exists(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[1] != .string) return .{ .bool = false };
    const prop_name = args[1].string;
    if (args[0] == .object) {
        const obj = args[0].object;
        if (obj.getSlotIndex(prop_name) != null) return .{ .bool = true };
        return .{ .bool = obj.properties.contains(prop_name) };
    }
    if (args[0] == .string) {
        const class_name = args[0].string;
        if (ctx.vm.classes.get(class_name)) |cls| {
            if (cls.slot_layout) |layout| {
                for (layout.names) |name| {
                    if (std.mem.eql(u8, name, prop_name)) return .{ .bool = true };
                }
            }
        }
        return .{ .bool = false };
    }
    return .{ .bool = false };
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
    if (val == .object) {
        return .{ .bool = ctx.vm.hasMethod(val.object.class_name, "__invoke") };
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
    if (args.len < 2 or args[1] != .string) return args[0];
    const type_name = args[1].string;
    const val = args[0];
    if (std.mem.eql(u8, type_name, "int") or std.mem.eql(u8, type_name, "integer"))
        return .{ .int = Value.toInt(val) };
    if (std.mem.eql(u8, type_name, "float") or std.mem.eql(u8, type_name, "double"))
        return .{ .float = Value.toFloat(val) };
    if (std.mem.eql(u8, type_name, "string")) {
        if (val == .string) return val;
        var buf = std.ArrayListUnmanaged(u8){};
        try val.format(&buf, ctx.allocator);
        const s = try buf.toOwnedSlice(ctx.allocator);
        try ctx.strings.append(ctx.allocator, s);
        return .{ .string = s };
    }
    if (std.mem.eql(u8, type_name, "bool") or std.mem.eql(u8, type_name, "boolean"))
        return .{ .bool = val.isTruthy() };
    if (std.mem.eql(u8, type_name, "null"))
        return .null;
    if (std.mem.eql(u8, type_name, "array")) {
        if (val == .array) return val;
        if (val == .object) {
            const obj = val.object;
            const arr = try ctx.allocator.create(PhpArray);
            arr.* = .{};
            try ctx.arrays.append(ctx.allocator, arr);
            if (obj.slot_layout) |layout| {
                if (obj.slots) |slots| {
                    for (layout.names, 0..) |name, i| {
                        if (i < slots.len) try arr.set(ctx.allocator, .{ .string = name }, slots[i]);
                    }
                }
            }
            var dyn_iter = obj.properties.iterator();
            while (dyn_iter.next()) |entry| {
                try arr.set(ctx.allocator, .{ .string = entry.key_ptr.* }, entry.value_ptr.*);
            }
            return .{ .array = arr };
        }
        const arr = try ctx.allocator.create(PhpArray);
        arr.* = .{};
        try arr.append(ctx.allocator, val);
        try ctx.arrays.append(ctx.allocator, arr);
        return .{ .array = arr };
    }
    if (std.mem.eql(u8, type_name, "object")) {
        if (val == .object) return val;
        const obj = try ctx.allocator.create(PhpObject);
        obj.* = .{ .class_name = "stdClass" };
        try ctx.vm.objects.append(ctx.allocator, obj);
        if (val == .array) {
            for (val.array.entries.items) |entry| {
                if (entry.key == .string) {
                    try obj.set(ctx.allocator, entry.key.string, entry.value);
                } else {
                    var key_buf: [32]u8 = undefined;
                    const ks = std.fmt.bufPrint(&key_buf, "{d}", .{entry.key.int}) catch continue;
                    const key_str = try ctx.createString(ks);
                    try obj.set(ctx.allocator, key_str, entry.value);
                }
            }
        } else if (val != .null) {
            try obj.set(ctx.allocator, "scalar", val);
        }
        return .{ .object = obj };
    }
    try ctx.vm.setPendingException("ValueError", "settype(): Argument #2 ($type) must be a valid type");
    return error.RuntimeError;
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

fn native_get_object_vars(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return Value{ .bool = false };
    const obj = args[0].object;
    var arr = try ctx.createArray();

    // Determine caller's class scope via the calling frame's function name (which is
    // "Class::method" for methods and a plain name for free functions).
    const caller_class: ?[]const u8 = blk: {
        // natives run inline, so the caller is the current frame
        if (ctx.vm.frame_count < 1) break :blk null;
        const caller_frame = ctx.vm.frames[ctx.vm.frame_count - 1];
        const cf = caller_frame.func orelse break :blk null;
        const sep = std.mem.indexOf(u8, cf.name, "::") orelse break :blk null;
        break :blk cf.name[0..sep];
    };
    const can_see_protected = caller_class != null and isInClassHierarchy(ctx.vm, caller_class.?, obj.class_name);

    if (obj.slot_layout) |layout| {
        if (obj.slots) |slots| {
            for (layout.names, 0..) |name, i| {
                if (name.len > 1 and name[0] == '_' and name[1] == '_') continue;
                const vis = propVisibilityWithParents(ctx.vm, obj.class_name, name);
                // private: caller must be the declaring class
                if (vis == .private) {
                    const decl = propDeclaringClass(ctx.vm, obj.class_name, name);
                    if (caller_class == null or decl == null or !std.mem.eql(u8, caller_class.?, decl.?)) continue;
                }
                if (vis == .protected and !can_see_protected) continue;
                try arr.set(ctx.allocator, .{ .string = name }, slots[i]);
            }
        }
    }
    var iter = obj.properties.iterator();
    while (iter.next()) |entry| {
        const name = entry.key_ptr.*;
        if (name.len > 1 and name[0] == '_' and name[1] == '_') continue;
        const vis = propVisibilityWithParents(ctx.vm, obj.class_name, name);
        if (vis == .private) {
            const decl = propDeclaringClass(ctx.vm, obj.class_name, name);
            if (caller_class == null or decl == null or !std.mem.eql(u8, caller_class.?, decl.?)) continue;
        }
        if (vis == .protected and !can_see_protected) continue;
        try arr.set(ctx.allocator, .{ .string = name }, entry.value_ptr.*);
    }
    return .{ .array = arr };
}

fn propVisibility(class_def: ?@import("../runtime/vm.zig").ClassDef, name: []const u8) @import("../runtime/vm.zig").ClassDef.Visibility {
    const cls = class_def orelse return .public;
    for (cls.properties.items) |pdef| {
        if (std.mem.eql(u8, pdef.name, name)) return pdef.visibility;
    }
    return .public;
}

fn propVisibilityWithParents(vm: *@import("../runtime/vm.zig").VM, class_name: []const u8, name: []const u8) @import("../runtime/vm.zig").ClassDef.Visibility {
    var current_name = class_name;
    while (true) {
        const cls = vm.classes.get(current_name) orelse return .public;
        for (cls.properties.items) |pdef| {
            if (std.mem.eql(u8, pdef.name, name)) return pdef.visibility;
        }
        const parent = cls.parent orelse return .public;
        current_name = parent;
    }
}

fn propDeclaringClass(vm: *@import("../runtime/vm.zig").VM, class_name: []const u8, name: []const u8) ?[]const u8 {
    var current_name = class_name;
    while (true) {
        const cls = vm.classes.get(current_name) orelse return null;
        for (cls.properties.items) |pdef| {
            if (std.mem.eql(u8, pdef.name, name)) return current_name;
        }
        current_name = cls.parent orelse return null;
    }
}

fn isInClassHierarchy(vm: *@import("../runtime/vm.zig").VM, candidate: []const u8, target: []const u8) bool {
    if (std.mem.eql(u8, candidate, target)) return true;
    // walk target's ancestors (candidate is an ancestor of target)
    var current = vm.classes.get(target) orelse return false;
    while (current.parent) |p| {
        if (std.mem.eql(u8, p, candidate)) return true;
        current = vm.classes.get(p) orelse break;
    }
    // walk candidate's ancestors (candidate is a descendant of target)
    var c = vm.classes.get(candidate) orelse return false;
    while (c.parent) |p| {
        if (std.mem.eql(u8, p, target)) return true;
        c = vm.classes.get(p) orelse break;
    }
    return false;
}

fn native_get_class_methods(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return Value{ .bool = false };
    const class_name = if (args[0] == .object)
        args[0].object.class_name
    else if (args[0] == .generator)
        "Generator"
    else if (args[0] == .fiber)
        "Fiber"
    else if (args[0] == .string)
        args[0].string
    else
        return Value{ .bool = false };

    if (std.mem.eql(u8, class_name, "Generator")) {
        var arr = try ctx.createArray();
        const methods = [_][]const u8{ "rewind", "valid", "current", "key", "next", "send", "throw", "getReturn", "__debugInfo" };
        for (methods) |m| try arr.append(ctx.allocator, .{ .string = m });
        return .{ .array = arr };
    }
    if (std.mem.eql(u8, class_name, "Fiber")) {
        var arr = try ctx.createArray();
        const methods = [_][]const u8{ "__construct", "start", "resume", "throw", "isStarted", "isSuspended", "isRunning", "isTerminated", "getReturn", "getCurrent", "suspend" };
        for (methods) |m| try arr.append(ctx.allocator, .{ .string = m });
        return .{ .array = arr };
    }

    // visibility: caller in same class sees all; subclass sees public+protected;
    // outside sees only public. ancestor private methods don't appear regardless.
    const caller = ctx.vm.currentDefiningClass();
    var arr = try ctx.createArray();
    var seen = std.StringHashMapUnmanaged(void){};
    defer seen.deinit(ctx.allocator);
    var current: ?[]const u8 = class_name;
    var depth: usize = 0;
    while (current) |cn| {
        if (ctx.vm.classes.get(cn)) |cls| {
            var iter = cls.methods.iterator();
            while (iter.next()) |entry| {
                const info = entry.value_ptr.*;
                if (depth > 0 and info.visibility == .private) continue;
                const visible = switch (info.visibility) {
                    .public => true,
                    .protected => caller != null and isInClassChain(ctx.vm, caller.?, class_name),
                    .private => caller != null and std.mem.eql(u8, caller.?, cn),
                };
                if (!visible) continue;
                if (!seen.contains(entry.key_ptr.*)) {
                    try seen.put(ctx.allocator, entry.key_ptr.*, {});
                    try arr.append(ctx.allocator, .{ .string = entry.key_ptr.* });
                }
            }
            current = cls.parent;
        } else break;
        depth += 1;
    }
    return .{ .array = arr };
}

fn isInClassChain(vm: *@import("../runtime/vm.zig").VM, a: []const u8, b: []const u8) bool {
    if (std.mem.eql(u8, a, b)) return true;
    var current: ?[]const u8 = a;
    while (current) |cn| {
        if (std.mem.eql(u8, cn, b)) return true;
        current = if (vm.classes.get(cn)) |cls| cls.parent else null;
    }
    current = b;
    while (current) |cn| {
        if (std.mem.eql(u8, cn, a)) return true;
        current = if (vm.classes.get(cn)) |cls| cls.parent else null;
    }
    return false;
}

fn native_get_class_vars(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return Value{ .bool = false };
    const class_name = args[0].string;
    const cls = ctx.vm.classes.get(class_name) orelse return Value{ .bool = false };
    const caller = ctx.vm.currentDefiningClass();
    var arr = try ctx.createArray();
    for (cls.properties.items) |prop| {
        const visible = switch (prop.visibility) {
            .public => true,
            .protected => caller != null and isInClassChain(ctx.vm, caller.?, class_name),
            .private => caller != null and std.mem.eql(u8, caller.?, class_name),
        };
        if (!visible) continue;
        try arr.set(ctx.allocator, .{ .string = prop.name }, prop.default);
    }
    // PHP's get_class_vars also includes static properties
    var sit = cls.static_props.iterator();
    while (sit.next()) |e| {
        // class constants are also stored in static_props; skip them
        if (cls.constant_names.contains(e.key_ptr.*)) continue;
        try arr.set(ctx.allocator, .{ .string = e.key_ptr.* }, e.value_ptr.*);
    }
    return .{ .array = arr };
}

fn native_get_parent_class(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return Value{ .bool = false };
    const class_name = if (args[0] == .object)
        args[0].object.class_name
    else if (args[0] == .string)
        args[0].string
    else
        return Value{ .bool = false };
    const cls = ctx.vm.classes.get(class_name) orelse return Value{ .bool = false };
    if (cls.parent) |p| return Value{ .string = p };
    return Value{ .bool = false };
}

fn native_is_a(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[1] != .string) return .{ .bool = false };
    if (args[0] == .generator) {
        const t = args[1].string;
        return .{ .bool = std.mem.eql(u8, t, "Generator") or std.mem.eql(u8, t, "Iterator") or std.mem.eql(u8, t, "Traversable") };
    }
    if (args[0] == .fiber) return .{ .bool = std.mem.eql(u8, args[1].string, "Fiber") };
    const class_name = if (args[0] == .object)
        args[0].object.class_name
    else if (args[0] == .string)
        args[0].string
    else
        return Value{ .bool = false };
    return .{ .bool = ctx.vm.isInstanceOf(class_name, args[1].string) };
}

fn native_is_subclass_of(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[1] != .string) return .{ .bool = false };
    if (args[0] == .generator) {
        const t = args[1].string;
        return .{ .bool = std.mem.eql(u8, t, "Iterator") or std.mem.eql(u8, t, "Traversable") };
    }
    if (args[0] == .fiber) return .{ .bool = false };
    const class_name = if (args[0] == .object)
        args[0].object.class_name
    else if (args[0] == .string)
        args[0].string
    else
        return Value{ .bool = false };
    // is_subclass_of returns false if same class, only true for actual subclasses
    if (std.mem.eql(u8, class_name, args[1].string)) return .{ .bool = false };
    return .{ .bool = ctx.vm.isInstanceOf(class_name, args[1].string) };
}

fn native_spl_object_id(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return Value{ .int = 0 };
    if (args[0] == .object) return .{ .int = @intCast(@intFromPtr(args[0].object)) };
    if (args[0] == .generator) return .{ .int = @intCast(@intFromPtr(args[0].generator)) };
    if (args[0] == .fiber) return .{ .int = @intCast(@intFromPtr(args[0].fiber)) };
    return Value{ .int = 0 };
}

fn native_exit(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len > 0) {
        if (args[0] == .string) {
            try ctx.vm.output.appendSlice(ctx.allocator, args[0].string);
        } else if (args[0] == .int) {
            // integer exit code - don't output, just set
        }
    }
    ctx.vm.exit_requested = true;
    return error.RuntimeError;
}

const VersionToken = struct {
    is_num: bool,
    num: i64 = 0,
    tag_weight: i64 = 0, // dev=-4 alpha=-3 beta=-2 rc=-1 none=0 pl=1
};

fn tagWeight(s: []const u8) i64 {
    if (s.len == 0) return 0;
    var buf: [10]u8 = undefined;
    const len = @min(s.len, 10);
    for (0..len) |i| buf[i] = std.ascii.toLower(s[i]);
    const lower = buf[0..len];
    if (std.mem.eql(u8, lower, "dev")) return -4;
    if (std.mem.eql(u8, lower, "alpha") or std.mem.eql(u8, lower, "a")) return -3;
    if (std.mem.eql(u8, lower, "beta") or std.mem.eql(u8, lower, "b")) return -2;
    if (std.mem.startsWith(u8, lower, "rc")) return -1;
    if (std.mem.eql(u8, lower, "pl") or std.mem.eql(u8, lower, "p")) return 1;
    return -3; // unknown tags treated as alpha
}

fn tokenizeVersion(s: []const u8, out: *[16]VersionToken) usize {
    var tok_count: usize = 0;
    var i: usize = 0;
    while (i < s.len and tok_count < 16) {
        if (s[i] == '.' or s[i] == '-' or s[i] == '_') {
            i += 1;
            continue;
        }
        if (std.ascii.isDigit(s[i])) {
            var end = i + 1;
            while (end < s.len and std.ascii.isDigit(s[end])) end += 1;
            out[tok_count] = .{ .is_num = true, .num = std.fmt.parseInt(i64, s[i..end], 10) catch 0 };
            tok_count += 1;
            i = end;
        } else {
            var end = i + 1;
            while (end < s.len and std.ascii.isAlphabetic(s[end])) end += 1;
            out[tok_count] = .{ .is_num = false, .tag_weight = tagWeight(s[i..end]) };
            tok_count += 1;
            i = end;
        }
    }
    return tok_count;
}

fn native_version_compare(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .null;
    const v1 = args[0].string;
    const v2 = args[1].string;

    var toks1: [16]VersionToken = undefined;
    var toks2: [16]VersionToken = undefined;
    const count1 = tokenizeVersion(v1, &toks1);
    const count2 = tokenizeVersion(v2, &toks2);

    const max_parts = @max(count1, count2);
    var cmp: i64 = 0;
    for (0..max_parts) |j| {
        const has_a = j < count1;
        const has_b = j < count2;
        if (!has_a and !has_b) break;

        if (has_a and !has_b) {
            if (toks1[j].is_num) { cmp = 1; break; } else {
                // tag vs implicit release: tag < release
                if (toks1[j].tag_weight < 0) { cmp = -1; break; }
                if (toks1[j].tag_weight > 0) { cmp = 1; break; }
            }
        }
        if (!has_a and has_b) {
            if (toks2[j].is_num) { cmp = -1; break; } else {
                if (toks2[j].tag_weight < 0) { cmp = 1; break; }
                if (toks2[j].tag_weight > 0) { cmp = -1; break; }
            }
        }
        if (has_a and has_b) {
            const a = toks1[j];
            const b = toks2[j];
            if (a.is_num and b.is_num) {
                if (a.num < b.num) { cmp = -1; break; }
                if (a.num > b.num) { cmp = 1; break; }
            } else if (!a.is_num and !b.is_num) {
                if (a.tag_weight < b.tag_weight) { cmp = -1; break; }
                if (a.tag_weight > b.tag_weight) { cmp = 1; break; }
            } else {
                // num vs tag: in PHP context, a number part > a tag part
                if (a.is_num) { cmp = 1; break; } else { cmp = -1; break; }
            }
        }
    }

    if (args.len >= 3 and args[2] == .string) {
        const op = args[2].string;
        const result = if (std.mem.eql(u8, op, "<") or std.mem.eql(u8, op, "lt"))
            cmp < 0
        else if (std.mem.eql(u8, op, "<=") or std.mem.eql(u8, op, "le"))
            cmp <= 0
        else if (std.mem.eql(u8, op, ">") or std.mem.eql(u8, op, "gt"))
            cmp > 0
        else if (std.mem.eql(u8, op, ">=") or std.mem.eql(u8, op, "ge"))
            cmp >= 0
        else if (std.mem.eql(u8, op, "==") or std.mem.eql(u8, op, "=") or std.mem.eql(u8, op, "eq"))
            cmp == 0
        else if (std.mem.eql(u8, op, "!=") or std.mem.eql(u8, op, "ne") or std.mem.eql(u8, op, "<>"))
            cmp != 0
        else
            false;
        return .{ .bool = result };
    }

    _ = ctx;
    return .{ .int = cmp };
}

fn native_php_sapi_name(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .string = "cli" };
}

fn native_php_version(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .string = "8.4.0" };
}

fn native_getmypid(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = @intCast(std.c.getpid()) };
}

fn native_getmyuid(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = @intCast(std.c.getuid()) };
}

extern "c" fn getgid() c_uint;

fn native_getmygid(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = @intCast(getgid()) };
}

fn native_get_cfg_var(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return Value{ .bool = false };
}

fn iniDefault(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "date.timezone")) return "UTC";
    // PHP CLI default is "-1" (no limit); web SAPI default is "128M"
    if (std.mem.eql(u8, name, "memory_limit")) return "-1";
    if (std.mem.eql(u8, name, "max_execution_time")) return "0";
    if (std.mem.eql(u8, name, "display_errors")) return "1";
    if (std.mem.eql(u8, name, "error_reporting")) return "30719";
    if (std.mem.eql(u8, name, "zend.assertions")) return "1";
    if (std.mem.eql(u8, name, "assert.active")) return "1";
    if (std.mem.eql(u8, name, "assert.exception")) return "0";
    if (std.mem.eql(u8, name, "assert.bail")) return "0";
    if (std.mem.eql(u8, name, "assert.warning")) return "1";
    if (std.mem.eql(u8, name, "assert.callback")) return "";
    return null;
}

fn native_ini_get(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return Value{ .bool = false };
    const name = args[0].string;
    if (ctx.vm.ini_settings.get(name)) |stored| return .{ .string = stored };
    if (iniDefault(name)) |def| return .{ .string = def };
    return Value{ .bool = false };
}

fn native_ini_set(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string) return Value{ .bool = false };
    const name = args[0].string;
    // PHP rejects unknown directives. Only allow known names.
    const previous: []const u8 = if (ctx.vm.ini_settings.get(name)) |s| s else if (iniDefault(name)) |d| d else return Value{ .bool = false };
    var buf = std.ArrayListUnmanaged(u8){};
    try args[1].format(&buf, ctx.allocator);
    const new_val = try buf.toOwnedSlice(ctx.allocator);
    try ctx.vm.strings.append(ctx.allocator, new_val);
    const owned_name = try ctx.allocator.dupe(u8, name);
    try ctx.vm.strings.append(ctx.allocator, owned_name);
    try ctx.vm.ini_settings.put(ctx.allocator, owned_name, new_val);
    return .{ .string = previous };
}

fn native_extension_loaded(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const name = args[0].string;
    if (std.mem.eql(u8, name, "json")) return .{ .bool = true };
    if (std.mem.eql(u8, name, "pcre")) return .{ .bool = true };
    if (std.mem.eql(u8, name, "pdo")) return .{ .bool = true };
    if (std.mem.eql(u8, name, "pdo_sqlite")) return .{ .bool = true };
    if (std.mem.eql(u8, name, "pdo_mysql")) return .{ .bool = true };
    if (std.mem.eql(u8, name, "pdo_pgsql")) return .{ .bool = true };
    if (std.mem.eql(u8, name, "session")) return .{ .bool = true };
    if (std.mem.eql(u8, name, "mbstring")) return .{ .bool = true };
    return .{ .bool = false };
}

fn native_get_included_files(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    var arr = try ctx.createArray();
    var iter = ctx.vm.loaded_files.iterator();
    while (iter.next()) |entry| {
        try arr.append(ctx.allocator, .{ .string = entry.key_ptr.* });
    }
    return .{ .array = arr };
}

fn native_register_shutdown_function(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .null;
    try ctx.vm.shutdown_callbacks.append(ctx.allocator, args[0]);
    return .null;
}

fn native_memory_get_usage(_: *NativeContext, _: []const Value) RuntimeError!Value {
    // zphp uses an arena/request allocator and doesn't track byte-accurate
    // process RSS; report a small non-zero stub so callers that gate on >0
    // (the common pattern) keep working
    return .{ .int = 1024 };
}

fn native_set_error_handler(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const prev = ctx.vm.user_error_handler orelse Value.null;
    ctx.vm.prev_error_handler = ctx.vm.user_error_handler;
    if (args.len > 0 and args[0] != .null) {
        ctx.vm.user_error_handler = args[0];
    } else {
        ctx.vm.user_error_handler = null;
    }
    return prev;
}

fn native_set_exception_handler(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    _ = ctx;
    _ = args;
    return .null;
}

fn native_restore_error_handler(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    ctx.vm.user_error_handler = ctx.vm.prev_error_handler;
    ctx.vm.prev_error_handler = null;
    return .{ .bool = true };
}

fn native_assert(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = true };
    if (args[0].isTruthy()) return .{ .bool = true };
    // assert.exception default varies; honor the ini if user explicitly enables.
    // Many frameworks (Laravel/Symfony) call assert() at runtime expecting no
    // side effects in production; throwing here causes hard-to-debug 500s.
    const ae = ctx.vm.ini_settings.get("assert.exception") orelse "0";
    if (std.mem.eql(u8, ae, "1")) {
        const msg: []const u8 = blk: {
            if (args.len >= 2) {
                if (args[1] == .string) break :blk args[1].string;
                if (args[1] == .object) {
                    ctx.vm.pending_exception = args[1];
                    return error.RuntimeError;
                }
            }
            break :blk "assert(false)";
        };
        try ctx.vm.setPendingException("AssertionError", msg);
        return error.RuntimeError;
    }
    return .{ .bool = false };
}

fn native_noop_true(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = true };
}

fn native_noop_null(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .null;
}

fn native_noop_zero(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = 0 };
}

fn native_get_include_path(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .string = "." };
}

fn native_set_include_path(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .string = "." };
}

fn native_error_reporting(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const prev = ctx.vm.error_reporting_level;
    if (args.len > 0) {
        ctx.vm.error_reporting_level = Value.toInt(args[0]);
    }
    return .{ .int = prev };
}

fn native_trigger_error(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const message = args[0].string;
    const errno: i64 = if (args.len >= 2) Value.toInt(args[1]) else 1024; // E_USER_NOTICE

    if (errno == 256) {
        const dep_msg = "Passing E_USER_ERROR to trigger_error() is deprecated since 8.4, throw an exception or call exit with a string message instead";
        if (ctx.vm.user_error_handler) |handler| {
            const ip0 = if (ctx.vm.frame_count > 0) ctx.vm.currentFrame().ip else 0;
            const line0: i64 = if (ctx.vm.frame_count > 0)
                if (ctx.vm.currentChunk().getSourceLocation(if (ip0 > 0) ip0 - 1 else 0, ctx.vm.source)) |loc| @intCast(loc.line) else 0
            else
                0;
            const args_dep = &[_]Value{ .{ .int = 8192 }, .{ .string = dep_msg }, .{ .string = ctx.vm.file_path }, .{ .int = line0 } };
            _ = try ctx.invokeCallable(handler, args_dep);
        }
    }

    const ip = if (ctx.vm.frame_count > 0) ctx.vm.currentFrame().ip else 0;
    const line: i64 = if (ctx.vm.frame_count > 0)
        if (ctx.vm.currentChunk().getSourceLocation(if (ip > 0) ip - 1 else 0, ctx.vm.source)) |loc| @intCast(loc.line) else 0
    else
        0;
    const file = ctx.vm.file_path;

    ctx.vm.last_error_type = errno;
    ctx.vm.last_error_message = ctx.allocator.dupe(u8, message) catch message;
    ctx.vm.strings.append(ctx.allocator, ctx.vm.last_error_message) catch {};
    ctx.vm.last_error_file = file;
    ctx.vm.last_error_line = line;

    if (ctx.vm.user_error_handler) |handler| {
        const call_args = &[_]Value{
            .{ .int = errno },
            .{ .string = message },
            .{ .string = file },
            .{ .int = line },
        };
        _ = try ctx.invokeCallable(handler, call_args);
        return .{ .bool = true };
    }

    if (ctx.vm.error_silenced_depth == 0) {
        const label = errnoLabel(errno);
        // flush any pending stdout so the merged 2>&1 ordering matches PHP
        if (ctx.vm.output.items.len > 0) {
            const stdout_file = std.fs.File{ .handle = 1 };
            _ = stdout_file.write(ctx.vm.output.items) catch {};
            ctx.vm.output.clearRetainingCapacity();
        }
        const stderr_text = std.fmt.allocPrint(ctx.allocator, "PHP {s}:  {s} in {s} on line {d}\n", .{ label, message, file, line }) catch return Value{ .bool = true };
        try ctx.vm.strings.append(ctx.allocator, stderr_text);
        const stderr_file = std.fs.File{ .handle = 2 };
        _ = stderr_file.write(stderr_text) catch {};
        const stdout_text = std.fmt.allocPrint(ctx.allocator, "\n{s}: {s} in {s} on line {d}\n", .{ label, message, file, line }) catch return Value{ .bool = true };
        try ctx.vm.strings.append(ctx.allocator, stdout_text);
        try ctx.vm.output.appendSlice(ctx.allocator, stdout_text);
    }
    return .{ .bool = true };
}

fn errnoLabel(errno: i64) []const u8 {
    return switch (errno) {
        1, 256 => "Fatal error",
        2, 512 => "Warning",
        4 => "Parse error",
        8, 1024 => "Notice",
        16 => "Core error",
        32 => "Core warning",
        64 => "Compile error",
        128 => "Compile warning",
        2048 => "Strict standards",
        4096 => "Recoverable fatal error",
        8192, 16384 => "Deprecated",
        else => "Notice",
    };
}

fn native_error_get_last(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    if (ctx.vm.last_error_type == 0) return .null;
    var arr = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .string = "type" }, .{ .int = ctx.vm.last_error_type });
    try arr.set(ctx.allocator, .{ .string = "message" }, .{ .string = ctx.vm.last_error_message });
    try arr.set(ctx.allocator, .{ .string = "file" }, .{ .string = ctx.vm.last_error_file });
    try arr.set(ctx.allocator, .{ .string = "line" }, .{ .int = ctx.vm.last_error_line });
    return .{ .array = arr };
}

fn native_class_alias(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const original = args[0].string;
    const alias = args[1].string;
    const autoload = if (args.len >= 3) args[2].isTruthy() else true;
    if (autoload and !ctx.vm.classes.contains(original)) {
        ctx.vm.tryAutoload(original) catch return Value{ .bool = false };
    }
    if (ctx.vm.classes.get(original)) |cls| {
        var alias_def = ClassDef{ .name = alias, .parent = original };
        // copy interfaces
        for (cls.interfaces.items) |iface| {
            try alias_def.interfaces.append(ctx.allocator, iface);
        }
        try ctx.vm.classes.put(ctx.allocator, alias, alias_def);
        // copy method info so hasMethod and method visibility checks work
        var method_iter = cls.methods.iterator();
        while (method_iter.next()) |entry| {
            var alias_class = ctx.vm.classes.getPtr(alias) orelse continue;
            try alias_class.methods.put(ctx.allocator, entry.key_ptr.*, entry.value_ptr.*);
        }
        // don't register alias::method in functions map - resolveMethod walks
        // the parent chain and must find the original class name for correct
        // private visibility checks in currentDefiningClass
        return .{ .bool = true };
    }
    return .{ .bool = false };
}

fn native_spl_autoload_register(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    try ctx.vm.autoload_callbacks.append(ctx.allocator, args[0]);
    return .{ .bool = true };
}

fn native_spl_autoload_functions(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    var arr = try ctx.allocator.create(PhpArray);
    arr.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, arr);
    for (ctx.vm.autoload_callbacks.items) |cb| {
        try arr.append(ctx.allocator, cb);
    }
    return .{ .array = arr };
}

fn native_spl_autoload_unregister(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    const target = args[0];
    var i: usize = 0;
    while (i < ctx.vm.autoload_callbacks.items.len) {
        const cb = ctx.vm.autoload_callbacks.items[i];
        if (callablesEqual(cb, target)) {
            _ = ctx.vm.autoload_callbacks.orderedRemove(i);
        } else {
            i += 1;
        }
    }
    return .{ .bool = true };
}

fn callablesEqual(a: Value, b: Value) bool {
    if (a == .string and b == .string) return std.mem.eql(u8, a.string, b.string);
    if (a == .array and b == .array) {
        const aa = a.array;
        const ba = b.array;
        if (aa.entries.items.len != ba.entries.items.len) return false;
        for (aa.entries.items, ba.entries.items) |ae, be| {
            if (ae.value == .string and be.value == .string) {
                if (!std.mem.eql(u8, ae.value.string, be.value.string)) return false;
            } else return false;
        }
        return true;
    }
    return false;
}

fn getFrameParamValue(frame: anytype, slot_names: []const []const u8, param: []const u8) Value {
    for (slot_names, 0..) |sn, i| {
        if (std.mem.eql(u8, sn, param)) {
            if (i < frame.locals.len) return frame.locals[i];
            break;
        }
    }
    return frame.vars.get(param) orelse .null;
}

fn native_func_get_args(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const arr = try ctx.createArray();

    if (ctx.vm.getFrameArgs()) |saved_args| {
        for (saved_args) |val| {
            try arr.append(ctx.allocator, val);
        }
        return .{ .array = arr };
    }

    const frame = ctx.vm.currentFrame();
    const func = frame.func orelse return .{ .array = arr };
    const slot_names = func.slot_names;
    const actual_ac: usize = if (ctx.vm.getFrameArgCount()) |ac| ac else func.arity;

    if (func.is_variadic) {
        const fixed: usize = func.arity - 1;
        for (0..@min(actual_ac, fixed)) |i| {
            const val = getFrameParamValue(frame, slot_names, func.params[i]);
            try arr.append(ctx.allocator, val);
        }
        const variadic_val = getFrameParamValue(frame, slot_names, func.params[fixed]);
        if (variadic_val == .array) {
            for (variadic_val.array.entries.items) |entry| {
                try arr.append(ctx.allocator, entry.value);
            }
        }
    } else {
        for (0..@min(actual_ac, func.arity)) |i| {
            const val = getFrameParamValue(frame, slot_names, func.params[i]);
            try arr.append(ctx.allocator, val);
        }
    }
    return .{ .array = arr };
}

fn native_func_num_args(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const frame = ctx.vm.currentFrame();
    const func = frame.func orelse return .{ .int = 0 };

    if (ctx.vm.getFrameArgCount()) |ac| return .{ .int = @intCast(ac) };

    if (func.is_variadic) {
        const fixed: usize = func.arity - 1;
        var total: i64 = @intCast(fixed);
        const slot_names = func.slot_names;
        const variadic_val = getFrameParamValue(frame, slot_names, func.params[fixed]);
        if (variadic_val == .array) {
            total += variadic_val.array.length();
        }
        return .{ .int = total };
    }
    return .{ .int = @intCast(func.arity) };
}

fn native_func_get_arg(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    const idx = Value.toInt(args[0]);
    if (idx < 0) return .{ .bool = false };
    const index: usize = @intCast(idx);

    if (ctx.vm.getFrameArgs()) |saved_args| {
        if (index < saved_args.len) return saved_args[index];
        return .{ .bool = false };
    }

    const frame = ctx.vm.currentFrame();
    const func = frame.func orelse return .{ .bool = false };
    const slot_names = func.slot_names;

    if (func.is_variadic) {
        const fixed: usize = func.arity - 1;
        if (index < fixed) {
            return getFrameParamValue(frame, slot_names, func.params[index]);
        }
        const variadic_val = getFrameParamValue(frame, slot_names, func.params[fixed]);
        if (variadic_val == .array) {
            const vi: i64 = @intCast(index - fixed);
            const result = variadic_val.array.get(.{ .int = vi });
            if (result != .null) return result;
        }
        return .{ .bool = false };
    }

    if (index >= func.arity) return .{ .bool = false };
    return getFrameParamValue(frame, slot_names, func.params[index]);
}

fn native_interface_exists(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const name = args[0].string;
    if (ctx.vm.interfaces.contains(name)) return .{ .bool = true };
    const autoload = if (args.len > 1 and args[1] == .bool) args[1].bool else true;
    if (autoload) {
        ctx.vm.tryAutoload(name) catch {};
        return .{ .bool = ctx.vm.interfaces.contains(name) };
    }
    return .{ .bool = false };
}

fn native_enum_exists(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const name = args[0].string;
    if (ctx.vm.classes.get(name)) |cls| {
        if (cls.is_enum) return .{ .bool = true };
    }
    const autoload = if (args.len > 1 and args[1] == .bool) args[1].bool else true;
    if (autoload) {
        ctx.vm.tryAutoload(name) catch {};
        if (ctx.vm.classes.get(name)) |cls| {
            return .{ .bool = cls.is_enum };
        }
    }
    return .{ .bool = false };
}

fn native_class_implements(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    const class_name = if (args[0] == .object)
        args[0].object.class_name
    else if (args[0] == .string)
        args[0].string
    else
        return Value{ .bool = false };

    const cls = ctx.vm.classes.get(class_name) orelse return Value{ .bool = false };

    var result = try ctx.createArray();
    var queue = std.ArrayListUnmanaged([]const u8){};
    defer queue.deinit(ctx.allocator);
    for (cls.interfaces.items) |iface| try queue.append(ctx.allocator, iface);

    var parent = cls.parent;
    while (parent) |p| {
        const pcls = ctx.vm.classes.get(p) orelse break;
        for (pcls.interfaces.items) |iface| try queue.append(ctx.allocator, iface);
        parent = pcls.parent;
    }

    var i: usize = 0;
    while (i < queue.items.len) : (i += 1) {
        const iface = queue.items[i];
        if (result.get(.{ .string = iface }) != .null) continue;
        try result.set(ctx.allocator, .{ .string = iface }, .{ .string = iface });
        if (ctx.vm.classes.get(iface)) |idef| {
            for (idef.interfaces.items) |sub| try queue.append(ctx.allocator, sub);
        }
    }

    return .{ .array = result };
}

fn native_class_parents(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    const class_name = if (args[0] == .object)
        args[0].object.class_name
    else if (args[0] == .string)
        args[0].string
    else
        return Value{ .bool = false };

    const cls = ctx.vm.classes.get(class_name) orelse {
        try ctx.vm.tryAutoload(class_name);
        if (ctx.vm.classes.get(class_name) == null) return Value{ .bool = false };
        return native_class_parents(ctx, args);
    };

    var result = try ctx.createArray();
    var parent = cls.parent;
    while (parent) |p| {
        try result.set(ctx.allocator, .{ .string = p }, .{ .string = p });
        const pcls = ctx.vm.classes.get(p) orelse break;
        parent = pcls.parent;
    }

    return .{ .array = result };
}

fn native_class_uses(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    const class_name = if (args[0] == .object)
        args[0].object.class_name
    else if (args[0] == .string)
        args[0].string
    else
        return Value{ .bool = false };

    const cls = ctx.vm.classes.get(class_name) orelse {
        try ctx.vm.tryAutoload(class_name);
        if (ctx.vm.classes.get(class_name) == null) return Value{ .bool = false };
        return native_class_uses(ctx, args);
    };

    var result = try ctx.createArray();
    for (cls.used_traits.items) |trait| {
        try result.set(ctx.allocator, .{ .string = trait }, .{ .string = trait });
    }
    return .{ .array = result };
}

fn native_iterator_to_array(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .array = try ctx.createArray() };

    if (args[0] == .array) return args[0];
    const preserve_keys = if (args.len > 1 and args[1] == .bool) args[1].bool else true;

    if (args[0] == .generator) {
        const gen = args[0].generator;
        const arr = try ctx.createArray();

        if (gen.state == .created) try ctx.vm.resumeGenerator(gen, .null);

        while (gen.state != .completed) {
            if (preserve_keys) {
                try arr.set(ctx.allocator, switch (gen.current_key) {
                    .int => |i| .{ .int = i },
                    .string => |s| .{ .string = s },
                    else => .{ .int = arr.length() },
                }, gen.current_value);
            } else {
                try arr.append(ctx.allocator, gen.current_value);
            }
            try ctx.vm.resumeGenerator(gen, .null);
        }
        return .{ .array = arr };
    }

    if (args[0] == .object) {
        const obj = args[0].object;
        const arr = try ctx.createArray();
        const is_iterator = ctx.vm.isInstanceOf(obj.class_name, "Iterator");
        const is_aggregate = !is_iterator and ctx.vm.isInstanceOf(obj.class_name, "IteratorAggregate");
        if (is_aggregate and ctx.vm.hasMethod(obj.class_name, "getIterator")) {
            const inner_v = try ctx.vm.callMethod(obj, "getIterator", &.{});
            var inner_args: [2]Value = undefined;
            inner_args[0] = inner_v;
            var n: usize = 1;
            if (args.len > 1) { inner_args[1] = args[1]; n = 2; }
            return native_iterator_to_array(ctx, inner_args[0..n]);
        }
        if (!is_iterator) return .{ .array = arr };
        if (!ctx.vm.hasMethod(obj.class_name, "rewind")) return .{ .array = arr };
        _ = try ctx.vm.callMethod(obj, "rewind", &.{});
        var valid_v = try ctx.vm.callMethod(obj, "valid", &.{});
        while (valid_v.isTruthy()) {
            const cur = try ctx.vm.callMethod(obj, "current", &.{});
            if (preserve_keys) {
                const key = try ctx.vm.callMethod(obj, "key", &.{});
                try arr.set(ctx.allocator, switch (key) {
                    .int => |i| .{ .int = i },
                    .string => |s| .{ .string = s },
                    else => .{ .int = arr.length() },
                }, cur);
            } else {
                try arr.append(ctx.allocator, cur);
            }
            _ = try ctx.vm.callMethod(obj, "next", &.{});
            valid_v = try ctx.vm.callMethod(obj, "valid", &.{});
        }
        return .{ .array = arr };
    }

    return .{ .array = try ctx.createArray() };
}

fn native_iterator_count(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };

    if (args[0] == .array) return .{ .int = args[0].array.length() };

    if (args[0] == .generator) {
        const gen = args[0].generator;
        var n: i64 = 0;

        if (gen.state == .created) try ctx.vm.resumeGenerator(gen, .null);

        while (gen.state != .completed) {
            n += 1;
            try ctx.vm.resumeGenerator(gen, .null);
        }
        return .{ .int = n };
    }

    return .{ .int = 0 };
}

fn native_iterator_apply(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return .{ .int = 0 };

    var call_args: []const Value = &.{};
    if (args.len >= 3 and args[2] == .array) {
        const arr = args[2].array;
        const tmp = try ctx.allocator.alloc(Value, arr.entries.items.len);
        for (arr.entries.items, 0..) |entry, i| tmp[i] = entry.value;
        call_args = tmp;
    }

    if (args[0] == .generator) {
        const gen = args[0].generator;
        if (gen.state == .created) try ctx.vm.resumeGenerator(gen, .null);
        var n: i64 = 0;
        while (gen.state != .completed) {
            const r = try ctx.invokeCallable(args[1], call_args);
            if (!r.isTruthy()) break;
            n += 1;
            try ctx.vm.resumeGenerator(gen, .null);
        }
        return .{ .int = n };
    }

    if (args[0] == .array) {
        var n: i64 = 0;
        for (args[0].array.entries.items) |_| {
            const r = try ctx.invokeCallable(args[1], call_args);
            if (!r.isTruthy()) break;
            n += 1;
        }
        return .{ .int = n };
    }

    return .{ .int = 0 };
}

fn native_filter_var(_ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return .{ .bool = false };
    const value = args[0];

    if (args.len < 2) return value;

    const filter = if (args[1] == .int) args[1].int else return .{ .bool = false };
    const flags: i64 = if (args.len > 2 and args[2] == .int) args[2].int else 0;

    switch (filter) {
        275 => { // FILTER_VALIDATE_IP
            const s = if (value == .string) value.string else return .{ .bool = false };
            const ipv4_only = (flags & 1048576) != 0;
            const ipv6_only = (flags & 2097152) != 0;
            if (!ipv6_only) {
                if (isValidIPv4(s)) return value;
                if (ipv4_only) return .{ .bool = false };
            }
            if (!ipv4_only) {
                if (isValidIPv6(s)) return value;
            }
            return .{ .bool = false };
        },
        274 => { // FILTER_VALIDATE_EMAIL
            const s = if (value == .string) value.string else return .{ .bool = false };
            if (std.mem.indexOf(u8, s, "@")) |at| {
                if (at > 0 and at < s.len - 1 and std.mem.indexOf(u8, s[at + 1 ..], ".") != null) return value;
            }
            return .{ .bool = false };
        },
        273 => { // FILTER_VALIDATE_URL
            const s = if (value == .string) value.string else return .{ .bool = false };
            if (std.mem.startsWith(u8, s, "http://") or std.mem.startsWith(u8, s, "https://") or std.mem.startsWith(u8, s, "ftp://")) return value;
            return .{ .bool = false };
        },
        257 => { // FILTER_VALIDATE_INT
            if (value == .int) return value;
            if (value == .float) return value;
            const s = if (value == .string) value.string else return .{ .bool = false };
            const trimmed = std.mem.trim(u8, s, " ");
            const n = std.fmt.parseInt(i64, trimmed, 10) catch return .{ .bool = false };
            return .{ .int = n };
        },
        259 => { // FILTER_VALIDATE_FLOAT
            if (value == .float or value == .int) return value;
            const s = if (value == .string) value.string else return .{ .bool = false };
            const f = std.fmt.parseFloat(f64, std.mem.trim(u8, s, " ")) catch return .{ .bool = false };
            return .{ .float = f };
        },
        258 => { // FILTER_VALIDATE_BOOLEAN
            if (value == .bool) return value;
            if (value == .int) return .{ .bool = value.int != 0 };
            const s = if (value == .string) value.string else return .{ .bool = false };
            if (std.mem.eql(u8, s, "true") or std.mem.eql(u8, s, "1") or std.mem.eql(u8, s, "yes") or std.mem.eql(u8, s, "on")) return .{ .bool = true };
            if (std.mem.eql(u8, s, "false") or std.mem.eql(u8, s, "0") or std.mem.eql(u8, s, "no") or std.mem.eql(u8, s, "off") or s.len == 0) return .{ .bool = false };
            // PHP returns false for invalid input (NULL only with FILTER_NULL_ON_FAILURE flag)
            return .{ .bool = false };
        },
        515 => { // FILTER_SANITIZE_SPECIAL_CHARS
            const s = if (value == .string) value.string else return .{ .bool = false };
            return .{ .string = try sanitizeSpecialChars(_ctx, s) };
        },
        517 => { // FILTER_SANITIZE_EMAIL
            const s = if (value == .string) value.string else return .{ .bool = false };
            var buf = std.ArrayListUnmanaged(u8){};
            for (s) |c| {
                if (std.ascii.isAlphanumeric(c) or c == '@' or c == '.' or c == '!' or c == '#' or
                    c == '$' or c == '%' or c == '&' or c == '\'' or c == '*' or c == '+' or
                    c == '-' or c == '/' or c == '=' or c == '?' or c == '^' or c == '_' or
                    c == '`' or c == '{' or c == '|' or c == '}' or c == '~' or c == '[' or c == ']') {
                    try buf.append(_ctx.allocator, c);
                }
            }
            const out = try buf.toOwnedSlice(_ctx.allocator);
            try _ctx.strings.append(_ctx.allocator, out);
            return .{ .string = out };
        },
        else => return value,
    }
}

fn sanitizeSpecialChars(ctx: *NativeContext, s: []const u8) ![]const u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    for (s) |c| {
        switch (c) {
            '<' => try buf.appendSlice(ctx.allocator, "&#60;"),
            '>' => try buf.appendSlice(ctx.allocator, "&#62;"),
            '&' => try buf.appendSlice(ctx.allocator, "&#38;"),
            '"' => try buf.appendSlice(ctx.allocator, "&#34;"),
            '\'' => try buf.appendSlice(ctx.allocator, "&#39;"),
            else => {
                if (c < 32) {
                    var tmp: [8]u8 = undefined;
                    const n = std.fmt.bufPrint(&tmp, "&#{d};", .{c}) catch continue;
                    try buf.appendSlice(ctx.allocator, n);
                } else {
                    try buf.append(ctx.allocator, c);
                }
            },
        }
    }
    const out = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, out);
    return out;
}

fn isValidIPv4(s: []const u8) bool {
    var parts: u8 = 0;
    var it = std.mem.splitScalar(u8, s, '.');
    while (it.next()) |part| {
        if (part.len == 0 or part.len > 3) return false;
        const n = std.fmt.parseUnsigned(u8, part, 10) catch return false;
        _ = n;
        parts += 1;
    }
    return parts == 4;
}

fn isValidIPv6(s: []const u8) bool {
    if (s.len < 2) return false;
    var groups: u8 = 0;
    var has_double_colon = false;
    var it = std.mem.splitSequence(u8, s, ":");
    while (it.next()) |part| {
        if (part.len == 0) {
            if (has_double_colon) continue;
            has_double_colon = true;
            groups += 1;
            continue;
        }
        if (part.len > 4) return false;
        for (part) |c| {
            if (!std.ascii.isHex(c)) return false;
        }
        groups += 1;
    }
    if (has_double_colon) return groups <= 8;
    return groups == 8;
}

fn native_is_resource(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return .{ .bool = false };
    return .{ .bool = args[0] == .object and isResourceObject(args[0].object.class_name) };
}

fn native_get_resource_type(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return .{ .bool = false };
    if (args[0] == .object) {
        const cn = args[0].object.class_name;
        // map zphp internal class names to PHP-canonical resource type strings
        if (std.mem.eql(u8, cn, "FileHandle")) return .{ .string = "stream" };
        if (std.mem.eql(u8, cn, "StreamContext")) return .{ .string = "stream-context" };
        if (std.mem.eql(u8, cn, "CurlHandle")) return .{ .string = "curl" };
        if (std.mem.eql(u8, cn, "GdImage")) return .{ .string = "gd" };
        return .{ .string = cn };
    }
    return .{ .bool = false };
}

fn isResourceObject(name: []const u8) bool {
    return std.mem.eql(u8, name, "__stream") or
        std.mem.eql(u8, name, "__file") or
        std.mem.eql(u8, name, "__curl") or
        std.mem.eql(u8, name, "FileHandle");
}

fn native_spl_object_hash(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    const ptr: usize = switch (args[0]) {
        .object => |o| @intFromPtr(o),
        .generator => |g| @intFromPtr(g),
        .fiber => |f| @intFromPtr(f),
        else => return .{ .bool = false },
    };
    const hash = std.fmt.allocPrint(ctx.allocator, "{x:0>32}", .{ptr}) catch return .{ .bool = false };
    ctx.vm.strings.append(ctx.allocator, hash) catch {};
    return .{ .string = hash };
}

const T_INLINE_HTML: i64 = 312;
const T_OPEN_TAG: i64 = 379;
const T_OPEN_TAG_WITH_ECHO: i64 = 380;
const T_CLOSE_TAG: i64 = 381;
const T_WHITESPACE: i64 = 382;
const T_VARIABLE: i64 = 309;
const T_STRING: i64 = 310;
const T_LNUMBER: i64 = 311;
const T_DNUMBER: i64 = 313;
const T_CONSTANT_ENCAPSED_STRING: i64 = 314;
const T_COMMENT: i64 = 393;
const T_DOC_COMMENT: i64 = 394;

fn makeToken(ctx: *NativeContext, id: i64, text: []const u8, line: i64) RuntimeError!Value {
    const arr = try ctx.createArray();
    try arr.append(ctx.allocator, .{ .int = id });
    const s = try std.fmt.allocPrint(ctx.allocator, "{s}", .{text});
    try ctx.strings.append(ctx.allocator, s);
    try arr.append(ctx.allocator, .{ .string = s });
    try arr.append(ctx.allocator, .{ .int = line });
    return .{ .array = arr };
}

fn native_token_get_all(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .array = try ctx.createArray() };
    const input = args[0].string;
    const result = try ctx.createArray();
    var pos: usize = 0;
    var line: i64 = 1;
    var in_php = false;

    while (pos < input.len) {
        if (!in_php) {
            if (std.mem.startsWith(u8, input[pos..], "<?=")) {
                if (pos > 0) {
                    const html_start = blk: {
                        var s: usize = 0;
                        var found_start = false;
                        for (0..pos) |i| {
                            if (!found_start) { s = i; found_start = true; }
                        }
                        break :blk if (found_start) s else 0;
                    };
                    _ = html_start;
                }
                try result.append(ctx.allocator, try makeToken(ctx, T_OPEN_TAG_WITH_ECHO, "<?=", line));
                pos += 3;
                in_php = true;
            } else if (std.mem.startsWith(u8, input[pos..], "<?php")) {
                const tag_end = pos + 5;
                const has_ws = tag_end < input.len and (input[tag_end] == ' ' or input[tag_end] == '\n' or input[tag_end] == '\r' or input[tag_end] == '\t');
                if (has_ws) {
                    const tag_text = if (input[tag_end] == '\n') "<?php\n" else "<?php ";
                    try result.append(ctx.allocator, try makeToken(ctx, T_OPEN_TAG, tag_text, line));
                    if (input[tag_end] == '\n') line += 1;
                    pos = tag_end + 1;
                } else {
                    try result.append(ctx.allocator, try makeToken(ctx, T_OPEN_TAG, "<?php ", line));
                    pos = tag_end;
                }
                in_php = true;
            } else {
                // collect inline HTML until next <?
                const start = pos;
                while (pos < input.len) {
                    if (std.mem.startsWith(u8, input[pos..], "<?")) break;
                    if (input[pos] == '\n') line += 1;
                    pos += 1;
                }
                if (pos > start) {
                    try result.append(ctx.allocator, try makeToken(ctx, T_INLINE_HTML, input[start..pos], line));
                }
            }
        } else {
            // inside PHP code
            if (std.mem.startsWith(u8, input[pos..], "?>")) {
                try result.append(ctx.allocator, try makeToken(ctx, T_CLOSE_TAG, "?>", line));
                pos += 2;
                in_php = false;
            } else if (input[pos] == ' ' or input[pos] == '\t' or input[pos] == '\n' or input[pos] == '\r') {
                const start = pos;
                while (pos < input.len and (input[pos] == ' ' or input[pos] == '\t' or input[pos] == '\n' or input[pos] == '\r')) {
                    if (input[pos] == '\n') line += 1;
                    pos += 1;
                }
                try result.append(ctx.allocator, try makeToken(ctx, T_WHITESPACE, input[start..pos], line));
            } else if (input[pos] == '$' and pos + 1 < input.len and (std.ascii.isAlphabetic(input[pos + 1]) or input[pos + 1] == '_')) {
                const start = pos;
                pos += 1;
                while (pos < input.len and (std.ascii.isAlphanumeric(input[pos]) or input[pos] == '_')) pos += 1;
                try result.append(ctx.allocator, try makeToken(ctx, T_VARIABLE, input[start..pos], line));
            } else if (input[pos] == '\'' or input[pos] == '"') {
                const quote = input[pos];
                const start = pos;
                pos += 1;
                while (pos < input.len) {
                    if (input[pos] == '\\' and pos + 1 < input.len) {
                        pos += 2;
                        continue;
                    }
                    if (input[pos] == '\n') line += 1;
                    if (input[pos] == quote) { pos += 1; break; }
                    pos += 1;
                }
                try result.append(ctx.allocator, try makeToken(ctx, T_CONSTANT_ENCAPSED_STRING, input[start..pos], line));
            } else if (input[pos] == '/' and pos + 1 < input.len and input[pos + 1] == '/') {
                const start = pos;
                while (pos < input.len and input[pos] != '\n') pos += 1;
                try result.append(ctx.allocator, try makeToken(ctx, T_COMMENT, input[start..pos], line));
            } else if (input[pos] == '/' and pos + 1 < input.len and input[pos + 1] == '*') {
                const start = pos;
                const is_doc = pos + 2 < input.len and input[pos + 2] == '*';
                pos += 2;
                while (pos + 1 < input.len) {
                    if (input[pos] == '\n') line += 1;
                    if (input[pos] == '*' and input[pos + 1] == '/') { pos += 2; break; }
                    pos += 1;
                }
                try result.append(ctx.allocator, try makeToken(ctx, if (is_doc) T_DOC_COMMENT else T_COMMENT, input[start..pos], line));
            } else if (std.ascii.isDigit(input[pos])) {
                const start = pos;
                while (pos < input.len and (std.ascii.isDigit(input[pos]) or input[pos] == '.')) pos += 1;
                const has_dot = std.mem.indexOfScalar(u8, input[start..pos], '.') != null;
                try result.append(ctx.allocator, try makeToken(ctx, if (has_dot) T_DNUMBER else T_LNUMBER, input[start..pos], line));
            } else if (std.ascii.isAlphabetic(input[pos]) or input[pos] == '_') {
                const start = pos;
                while (pos < input.len and (std.ascii.isAlphanumeric(input[pos]) or input[pos] == '_')) pos += 1;
                try result.append(ctx.allocator, try makeToken(ctx, T_STRING, input[start..pos], line));
            } else {
                // single character token returned as string
                const s = try std.fmt.allocPrint(ctx.allocator, "{c}", .{input[pos]});
                try ctx.strings.append(ctx.allocator, s);
                try result.append(ctx.allocator, .{ .string = s });
                pos += 1;
            }
        }
    }
    return .{ .array = result };
}

fn native_token_name(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .int) return .{ .string = "UNKNOWN" };
    return .{ .string = switch (args[0].int) {
        312 => "T_INLINE_HTML",
        379 => "T_OPEN_TAG",
        380 => "T_OPEN_TAG_WITH_ECHO",
        381 => "T_CLOSE_TAG",
        382 => "T_WHITESPACE",
        309 => "T_VARIABLE",
        310 => "T_STRING",
        311 => "T_LNUMBER",
        313 => "T_DNUMBER",
        314 => "T_CONSTANT_ENCAPSED_STRING",
        393 => "T_COMMENT",
        394 => "T_DOC_COMMENT",
        else => "UNKNOWN",
    } };
}
