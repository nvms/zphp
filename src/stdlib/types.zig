const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
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
    .{ "ini_get", native_ini_get },
    .{ "ini_set", native_ini_set },
    .{ "extension_loaded", native_extension_loaded },
    .{ "get_included_files", native_get_included_files },
    .{ "get_required_files", native_get_included_files },
    .{ "memory_get_usage", native_memory_get_usage },
    .{ "memory_get_peak_usage", native_memory_get_usage },
    .{ "set_error_handler", native_set_error_handler },
    .{ "set_exception_handler", native_set_exception_handler },
    .{ "restore_error_handler", native_noop_true },
    .{ "restore_exception_handler", native_noop_true },
    .{ "error_reporting", native_error_reporting },
    .{ "trigger_error", native_trigger_error },
    .{ "user_error", native_trigger_error },
    .{ "class_alias", native_class_alias },
    .{ "spl_autoload_register", native_spl_autoload_register },
    .{ "spl_autoload_unregister", native_spl_autoload_unregister },
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

fn count(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
    return switch (args[0]) {
        .array => |a| .{ .int = a.length() },
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
        const base: u8 = @intCast(@max(2, @min(36, args[1].int)));
        var s = std.mem.trim(u8, args[0].string, " \t\n\r");
        if (base == 16 and s.len >= 2 and s[0] == '0' and (s[1] == 'x' or s[1] == 'X')) s = s[2..];
        if (base == 8 and s.len >= 1 and s[0] == '0') s = s[1..];
        if (base == 2 and s.len >= 2 and s[0] == '0' and (s[1] == 'b' or s[1] == 'B')) s = s[2..];
        return .{ .int = std.fmt.parseInt(i64, s, base) catch 0 };
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
        const arr = try ctx.allocator.create(PhpArray);
        arr.* = .{};
        try arr.append(ctx.allocator, val);
        try ctx.arrays.append(ctx.allocator, arr);
        return .{ .array = arr };
    }
    return val;
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
    var iter = obj.properties.iterator();
    while (iter.next()) |entry| {
        if (entry.key_ptr.*.len > 0 and entry.key_ptr.*[0] == '_' and entry.key_ptr.*.len > 1 and entry.key_ptr.*[1] == '_') continue;
        try arr.set(ctx.allocator, .{ .string = entry.key_ptr.* }, entry.value_ptr.*);
    }
    return .{ .array = arr };
}

fn native_get_class_methods(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return Value{ .bool = false };
    const class_name = if (args[0] == .object)
        args[0].object.class_name
    else if (args[0] == .string)
        args[0].string
    else
        return Value{ .bool = false };

    var arr = try ctx.createArray();
    var seen = std.StringHashMapUnmanaged(void){};
    defer seen.deinit(ctx.allocator);
    var current: ?[]const u8 = class_name;
    while (current) |cn| {
        if (ctx.vm.classes.get(cn)) |cls| {
            var iter = cls.methods.iterator();
            while (iter.next()) |entry| {
                if (!seen.contains(entry.key_ptr.*)) {
                    try seen.put(ctx.allocator, entry.key_ptr.*, {});
                    try arr.append(ctx.allocator, .{ .string = entry.key_ptr.* });
                }
            }
            current = cls.parent;
        } else break;
    }
    return .{ .array = arr };
}

fn native_get_class_vars(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return Value{ .bool = false };
    const class_name = args[0].string;
    const cls = ctx.vm.classes.get(class_name) orelse return Value{ .bool = false };
    var arr = try ctx.createArray();
    for (cls.properties.items) |prop| {
        try arr.set(ctx.allocator, .{ .string = prop.name }, prop.default);
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
    if (args.len == 0 or args[0] != .object) return Value{ .int = 0 };
    return .{ .int = @intCast(@intFromPtr(args[0].object)) };
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

fn parseVersionPart(s: []const u8) i64 {
    return std.fmt.parseInt(i64, s, 10) catch 0;
}

fn native_version_compare(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .null;
    const v1 = args[0].string;
    const v2 = args[1].string;

    var parts1: [8]i64 = .{ -1, -1, -1, -1, -1, -1, -1, -1 };
    var parts2: [8]i64 = .{ -1, -1, -1, -1, -1, -1, -1, -1 };

    var count1: usize = 0;
    var iter1 = std.mem.splitScalar(u8, v1, '.');
    while (iter1.next()) |part| {
        if (count1 >= 8) break;
        parts1[count1] = parseVersionPart(part);
        count1 += 1;
    }
    var count2: usize = 0;
    var iter2 = std.mem.splitScalar(u8, v2, '.');
    while (iter2.next()) |part| {
        if (count2 >= 8) break;
        parts2[count2] = parseVersionPart(part);
        count2 += 1;
    }

    const max_parts = @max(count1, count2);
    var cmp: i64 = 0;
    for (0..max_parts) |j| {
        const a = if (j < count1) parts1[j] else @as(i64, -1);
        const b = if (j < count2) parts2[j] else @as(i64, -1);
        if (a < b) { cmp = -1; break; }
        if (a > b) { cmp = 1; break; }
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
        else if (std.mem.eql(u8, op, "==") or std.mem.eql(u8, op, "eq"))
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

fn native_ini_get(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return Value{ .bool = false };
    const name = args[0].string;
    if (std.mem.eql(u8, name, "date.timezone")) return .{ .string = "UTC" };
    if (std.mem.eql(u8, name, "memory_limit")) return .{ .string = "-1" };
    if (std.mem.eql(u8, name, "max_execution_time")) return .{ .string = "0" };
    if (std.mem.eql(u8, name, "display_errors")) return .{ .string = "1" };
    if (std.mem.eql(u8, name, "error_reporting")) return .{ .string = "32767" };
    return Value{ .bool = false };
}

fn native_ini_set(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string) return Value{ .bool = false };
    // no-op, return the "old" value
    return .{ .string = "" };
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

fn native_memory_get_usage(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = 0 };
}

fn native_set_error_handler(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .null;
}

fn native_set_exception_handler(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .null;
}

fn native_noop_true(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = true };
}

fn native_error_reporting(_: *NativeContext, args: []const Value) RuntimeError!Value {
    _ = args;
    return .{ .int = 32767 };
}

fn native_trigger_error(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    try ctx.vm.output.appendSlice(ctx.allocator, args[0].string);
    return .{ .bool = true };
}

fn native_class_alias(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const original = args[0].string;
    const alias = args[1].string;
    if (ctx.vm.classes.get(original)) |cls| {
        // create an empty alias class that inherits everything from the original
        const VM = @import("../runtime/vm.zig").VM;
        _ = VM;
        const ClassDef = @import("../runtime/vm.zig").ClassDef;
        var alias_def = ClassDef{ .name = alias, .parent = original };
        // copy interfaces
        for (cls.interfaces.items) |iface| {
            try alias_def.interfaces.append(ctx.allocator, iface);
        }
        try ctx.vm.classes.put(ctx.allocator, alias, alias_def);
        // register aliased methods so ClassName::method lookups work
        var method_iter = cls.methods.iterator();
        while (method_iter.next()) |entry| {
            const method_name = entry.key_ptr.*;
            var orig_buf: [256]u8 = undefined;
            const orig_full = std.fmt.bufPrint(&orig_buf, "{s}::{s}", .{ original, method_name }) catch continue;
            if (ctx.vm.functions.get(orig_full)) |func| {
                var alias_buf: [256]u8 = undefined;
                const alias_full = std.fmt.bufPrint(&alias_buf, "{s}::{s}", .{ alias, method_name }) catch continue;
                const key = try ctx.allocator.dupe(u8, alias_full);
                try ctx.strings.append(ctx.allocator, key);
                try ctx.vm.functions.put(ctx.allocator, key, func);
            }
            if (ctx.vm.native_fns.get(orig_full)) |native| {
                var alias_buf: [256]u8 = undefined;
                const alias_full = std.fmt.bufPrint(&alias_buf, "{s}::{s}", .{ alias, method_name }) catch continue;
                const key = try ctx.allocator.dupe(u8, alias_full);
                try ctx.strings.append(ctx.allocator, key);
                try ctx.vm.native_fns.put(ctx.allocator, key, native);
            }
        }
        return .{ .bool = true };
    }
    return .{ .bool = false };
}

fn native_spl_autoload_register(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    try ctx.vm.autoload_callbacks.append(ctx.allocator, args[0]);
    return .{ .bool = true };
}

fn native_spl_autoload_unregister(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    const target = args[0];
    var i: usize = 0;
    while (i < ctx.vm.autoload_callbacks.items.len) {
        const cb = ctx.vm.autoload_callbacks.items[i];
        const match = if (cb == .string and target == .string)
            std.mem.eql(u8, cb.string, target.string)
        else
            false;
        if (match) {
            _ = ctx.vm.autoload_callbacks.orderedRemove(i);
        } else {
            i += 1;
        }
    }
    return .{ .bool = true };
}
