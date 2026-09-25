const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const std = @import("std");
const platform = @import("../platform.zig");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const value_mod = @import("../runtime/value.zig");
const VM = @import("../runtime/vm.zig").VM;
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
    .{ "get_declared_classes", native_get_declared_classes },
    .{ "get_declared_interfaces", native_get_declared_interfaces },
    .{ "get_declared_traits", native_get_declared_traits },
    .{ "method_exists", method_exists },
    .{ "property_exists", property_exists },
    .{ "is_callable", native_is_callable },
    .{ "settype", native_settype },
    .{ "call_user_func", native_call_user_func },
    .{ "forward_static_call", native_call_user_func },
    .{ "forward_static_call_array", native_call_user_func_array },
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
    .{ "get_current_user", native_get_current_user },
    .{ "getmyinode", native_noop_zero },
    .{ "ini_get", native_ini_get },
    .{ "ini_get_all", native_ini_get_all },
    .{ "ini_restore", native_ini_restore },
    .{ "get_cfg_var", native_get_cfg_var },
    .{ "ini_set", native_ini_set },
    .{ "ini_alter", native_ini_set },
    .{ "opcache_compile_file", native_noop_true },
    .{ "opcache_get_status", native_opcache_get_status },
    .{ "opcache_get_configuration", native_opcache_get_configuration },
    .{ "opcache_invalidate", native_noop_true },
    .{ "opcache_is_script_cached", native_noop_false },
    .{ "opcache_reset", native_noop_true },
    .{ "ignore_user_abort", native_noop_zero },
    .{ "strftime", native_strftime },
    .{ "gmstrftime", native_gmstrftime },
    .{ "getmxrr", native_getmxrr },
    .{ "header_register_callback", native_noop_true },
    .{ "spl_autoload_call", native_spl_autoload_call },
    .{ "spl_classes", native_spl_classes },
    .{ "iconv_mime_decode", native_iconv_mime_decode },
    .{ "iconv_mime_decode_headers", native_iconv_mime_decode_headers },
    .{ "iconv_mime_encode", native_iconv_mime_encode },
    .{ "gc_status", native_gc_status },
    .{ "gc_mem_caches", native_noop_zero },
    .{ "highlight_string", native_highlight_string },
    .{ "highlight_file", native_highlight_file },
    .{ "extension_loaded", native_extension_loaded },
    .{ "get_loaded_extensions", native_get_loaded_extensions },
    .{ "get_extension_funcs", native_get_extension_funcs },
    .{ "get_included_files", native_get_included_files },
    .{ "get_required_files", native_get_included_files },
    .{ "memory_get_usage", native_memory_get_usage },
    .{ "memory_get_peak_usage", native_memory_get_usage },
    .{ "memory_reset_peak_usage", native_noop_null },
    .{ "eval", native_eval },
    .{ "gc_enabled", native_gc_enabled },
    .{ "gc_disable", native_gc_disable },
    .{ "gc_enable", native_gc_enable },
    .{ "gc_collect_cycles", native_gc_collect_cycles },
    .{ "set_error_handler", native_set_error_handler },
    .{ "set_exception_handler", native_set_exception_handler },
    .{ "restore_error_handler", native_restore_error_handler },
    .{ "restore_exception_handler", native_restore_exception_handler },
    .{ "get_error_handler", native_get_error_handler },
    .{ "get_exception_handler", native_get_exception_handler },
    .{ "register_shutdown_function", native_register_shutdown_function },
    .{ "error_reporting", native_error_reporting },
    .{ "error_get_last", native_error_get_last },
    .{ "error_clear_last", native_error_clear_last },
    .{ "get_include_path", native_get_include_path },
    .{ "set_include_path", native_set_include_path },
    .{ "restore_include_path", native_noop_null },
    .{ "trigger_error", native_trigger_error },
    .{ "user_error", native_trigger_error },
    .{ "error_log", native_error_log },
    .{ "__zphp_match_unhandled_msg", native_match_unhandled_msg },
    .{ "class_alias", native_class_alias },
    .{ "assert", native_assert },
    .{ "assert_options", native_assert_options },
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
    .{ "setlocale", native_setlocale },
    .{ "localeconv", native_localeconv },
    .{ "nl_langinfo", native_nl_langinfo },
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
    .{ "filter_id", native_filter_id },
    .{ "filter_list", native_filter_list },
    .{ "filter_has_var", native_filter_has_var },
    .{ "filter_input", native_filter_input },
    .{ "filter_input_array", native_filter_input_array },
    .{ "filter_var_array", native_filter_var_array },
    .{ "is_resource", native_is_resource },
    .{ "get_resource_type", native_get_resource_type },
    .{ "get_resource_id", native_get_resource_id },
};

fn native_define(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    if (ctx.vm.php_constants.contains(args[0].string.bytes())) return NativeResult.scalar(.{ .bool = false });
    const name = try ctx.createString(args[0].string.bytes());
    try ctx.vm.user_constants.put(ctx.allocator, name, {});
    try ctx.vm.php_constants.put(ctx.allocator, name, args[1]);
    VM.retainValue(args[1]);
    return NativeResult.scalar(.{ .bool = true });
}

fn native_defined(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const name = args[0].string.bytes();
    if (ctx.vm.php_constants.contains(name)) return NativeResult.scalar(.{ .bool = true });
    // PHP treats leading-backslash and no-leading-backslash equivalently
    // for fully qualified constant lookups: defined('\M\PI') == defined('M\PI')
    if (name.len > 0 and name[0] == '\\') {
        if (ctx.vm.php_constants.contains(name[1..])) return NativeResult.scalar(.{ .bool = true });
    }
    if (std.mem.indexOf(u8, name, "::")) |sep| {
        const class_name = name[0..sep];
        const prop_name = name[sep + 2 ..];
        if (ctx.vm.getClassConstant(class_name, prop_name) != null) return NativeResult.scalar(.{ .bool = true });
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn native_constant(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.null);
    const name = args[0].string.bytes();
    if (ctx.vm.php_constants.get(name)) |v| {
        return NativeResult.share(v);
    }
    if (std.mem.indexOf(u8, name, "::")) |sep| {
        const class_name = name[0..sep];
        const prop_name = name[sep + 2 ..];
        if (ctx.vm.getClassConstant(class_name, prop_name)) |v| {
            return NativeResult.share(v);
        }
    }
    const msg = try std.fmt.allocPrint(ctx.allocator, "Undefined constant \"{s}\"", .{name});
    try ctx.strings.append(ctx.allocator, msg);
    try ctx.vm.setPendingException("Error", msg);
    return error.RuntimeError;
}

fn native_get_defined_constants(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const categorize = args.len >= 1 and args[0].isTruthy();
    if (categorize) {
        const root = try ctx.createArray();
        const internal = try ctx.createArray();
        const user = try ctx.createArray();
        var it = ctx.vm.php_constants.iterator();
        while (it.next()) |entry| {
            const name = entry.key_ptr.*;
            if (ctx.vm.user_constants.contains(name)) {
                try user.set(ctx.allocator, .{ .string = Value.String.borrowed(name) }, entry.value_ptr.*);
            } else {
                try internal.set(ctx.allocator, .{ .string = Value.String.borrowed(name) }, entry.value_ptr.*);
            }
        }
        try root.set(ctx.allocator, .{ .string = Value.String.borrowed("Core") }, .{ .array = internal });
        try root.set(ctx.allocator, .{ .string = Value.String.borrowed("user") }, .{ .array = user });
        return NativeResult.borrowed(.{ .array = root });
    }
    const flat = try ctx.createArray();
    var it = ctx.vm.php_constants.iterator();
    while (it.next()) |entry| {
        try flat.set(ctx.allocator, .{ .string = Value.String.borrowed(entry.key_ptr.*) }, entry.value_ptr.*);
    }
    return NativeResult.borrowed(.{ .array = flat });
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

fn count(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .int = 0 });
    const recursive = args.len >= 2 and args[1] == .int and args[1].int == 1;
    return switch (args[0]) {
        .array => |a| NativeResult.scalar(.{ .int = if (recursive) countRecursive(a) else a.length() }),
        .object => |obj| {
            if (ctx.vm.hasMethod(obj.class_name, "count")) {
                return NativeResult.share(try ctx.vm.callMethod(obj, "count", &.{}));
            }
            const msg = try std.fmt.allocPrint(ctx.allocator, "count(): Argument #1 ($value) must be of type Countable|array, {s} given", .{phpTypeName(args[0])});
            try ctx.vm.strings.append(ctx.allocator, msg);
            try ctx.vm.setPendingException("TypeError", msg);
            return error.RuntimeError;
        },
        else => {
            const msg = try std.fmt.allocPrint(ctx.allocator, "count(): Argument #1 ($value) must be of type Countable|array, {s} given", .{phpTypeName(args[0])});
            try ctx.vm.strings.append(ctx.allocator, msg);
            try ctx.vm.setPendingException("TypeError", msg);
            return error.RuntimeError;
        },
    };
}

// PHP's type-name used in TypeError messages: 'string', 'int', 'float',
// 'array', 'true', 'false', 'null', or the class name for objects.
// closures live as strings tagged with the '__closure_' prefix in zphp
pub fn phpTypeName(v: Value) []const u8 {
    if (v == .string and std.mem.startsWith(u8, v.string.bytes(), "__closure_")) return "Closure";
    return v.valueName();
}

// php warns when an object without a numeric conversion is cast to a number
fn warnObjectToNumber(ctx: *NativeContext, v: Value, comptime target: []const u8) RuntimeError!void {
    if (v != .object or @import("../runtime/value.zig").nativeCast(v.object, .number) != null) return;
    const msg = try std.fmt.allocPrint(ctx.allocator, "Object of class {s} could not be converted to " ++ target, .{v.object.class_name});
    try ctx.strings.append(ctx.allocator, msg);
    try ctx.vm.emitWarning(msg);
}

fn intval(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .int = 0 });
    try warnObjectToNumber(ctx, args[0], "int");
    if (args.len >= 2 and args[1] == .int and args[1].int != 10 and args[0] == .string) {
        var base: u8 = @intCast(@max(0, @min(36, args[1].int)));
        var s = std.mem.trim(u8, args[0].string.bytes(), " \t\n\r");
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
        var end: usize = 0;
        while (end < s.len) : (end += 1) {
            const c = s[end];
            const digit: u8 = if (c >= '0' and c <= '9') c - '0' else if (c >= 'a' and c <= 'z') 10 + (c - 'a') else if (c >= 'A' and c <= 'Z') 10 + (c - 'A') else 255;
            if (digit >= base) break;
        }
        const v = if (end == 0) @as(i64, 0) else (std.fmt.parseInt(i64, s[0..end], base) catch 0);
        return NativeResult.scalar(.{ .int = if (negative) -v else v });
    }
    // PHP: intval(array) is 0 for empty array, 1 for non-empty
    if (args[0] == .array) {
        return NativeResult.scalar(.{ .int = if (args[0].array.entries.items.len == 0) @as(i64, 0) else @as(i64, 1) });
    }
    return NativeResult.scalar(.{ .int = Value.toInt(args[0]) });
}

fn floatval(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .float = 0.0 });
    try warnObjectToNumber(ctx, args[0], "float");
    return NativeResult.scalar(.{ .float = Value.toFloat(args[0]) });
}

fn strval(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    if (args[0] == .string) return NativeResult.share(args[0]);
    // PHP's strval on an object dispatches through __toString. Without this,
    // we'd print "Object" instead of the user-defined string form
    if (args[0] == .object) {
        const obj = args[0].object;
        if (ctx.vm.hasMethod(obj.class_name, "__toString")) {
            const r = try ctx.vm.callMethod(obj, "__toString", &.{});
            if (r == .string) return NativeResult.share(r);
        }
    }
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(ctx.allocator);
    try args[0].format(&buf, ctx.allocator);
    const s = try buf.toOwnedSlice(ctx.allocator);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, s));
}

fn gettype(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("NULL");
    return switch (args[0]) {
        .null => NativeResult.literal("NULL"),
        .bool => NativeResult.literal("boolean"),
        .int => NativeResult.literal("integer"),
        .float => NativeResult.literal("double"),
        .string => |s| if (std.mem.startsWith(u8, s.bytes(), "__closure_")) NativeResult.literal("object") else NativeResult.literal("string"),
        .array => NativeResult.literal("array"),
        .object, .generator, .fiber => NativeResult.literal("object"),
        .resource => |r| if (value_mod.resourceClosed(r)) NativeResult.literal("resource (closed)") else NativeResult.literal("resource"),
    };
}

fn get_debug_type(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("null");
    return switch (args[0]) {
        .null => NativeResult.literal("null"),
        .bool => NativeResult.literal("bool"),
        .int => NativeResult.literal("int"),
        .float => NativeResult.literal("float"),
        .string => |s| if (std.mem.startsWith(u8, s.bytes(), "__closure_")) NativeResult.literal("Closure") else NativeResult.literal("string"),
        .array => NativeResult.literal("array"),
        .object => |o| try NativeResult.copyString(ctx.allocator, o.class_name),
        .generator => NativeResult.literal("Generator"),
        .fiber => NativeResult.literal("Fiber"),
        .resource => |r| if (value_mod.resourceClosed(r))
            NativeResult.literal("resource (closed)")
        else
            NativeResult.takeString(try Value.String.adopt(ctx.allocator, try std.fmt.allocPrint(ctx.allocator, "resource ({s})", .{value_mod.resourceTypeName(r)}))),
    };
}

fn is_array(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = args.len > 0 and args[0] == .array });
}

fn is_null(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = args.len == 0 or args[0] == .null });
}

fn is_int(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = args.len > 0 and args[0] == .int });
}

fn is_float(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = args.len > 0 and args[0] == .float });
}

fn is_string(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    if (args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = !std.mem.startsWith(u8, args[0].string.bytes(), "__closure_") });
}

fn is_bool(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = args.len > 0 and args[0] == .bool });
}

fn is_numeric(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = switch (args[0]) {
        .int, .float => true,
        .string => |s| isNumericString(s.bytes()),
        else => false,
    } });
}

// PHP's is_numeric: optional sign, digits, optional fractional/exponent.
// Rejects Inf, NaN, hex/octal/binary literals, underscores - even though
// std.fmt.parseFloat accepts some of those
fn isNumericString(input: []const u8) bool {
    var s = input;
    while (s.len > 0 and (s[0] == ' ' or s[0] == '\t' or s[0] == '\n' or s[0] == '\r' or s[0] == '\x0b' or s[0] == '\x0c')) s = s[1..];
    while (s.len > 0 and (s[s.len - 1] == ' ' or s[s.len - 1] == '\t' or s[s.len - 1] == '\n' or s[s.len - 1] == '\r' or s[s.len - 1] == '\x0b' or s[s.len - 1] == '\x0c')) s = s[0 .. s.len - 1];
    if (s.len == 0) return false;

    var i: usize = 0;
    if (s[0] == '+' or s[0] == '-') i = 1;
    if (i >= s.len) return false;

    var int_digits: usize = 0;
    while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) int_digits += 1;

    var frac_digits: usize = 0;
    if (i < s.len and s[i] == '.') {
        i += 1;
        while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) frac_digits += 1;
    }
    if (int_digits == 0 and frac_digits == 0) return false;

    if (i < s.len and (s[i] == 'e' or s[i] == 'E')) {
        i += 1;
        if (i < s.len and (s[i] == '+' or s[i] == '-')) i += 1;
        var exp_digits: usize = 0;
        while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) exp_digits += 1;
        if (exp_digits == 0) return false;
    }
    return i == s.len;
}

fn native_isset(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = args[0] != .null });
}

fn native_empty(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = true });
    return NativeResult.scalar(.{ .bool = !args[0].isTruthy() });
}

fn strlen(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .int = 0 });
    return switch (args[0]) {
        .string => |s| blk: {
            // closures live as '__closure_<id>' strings in zphp; treat them
            // as object-class Closure for the TypeError, matching PHP
            if (std.mem.startsWith(u8, s.bytes(), "__closure_")) {
                const msg = try std.fmt.allocPrint(ctx.allocator, "strlen(): Argument #1 ($string) must be of type string, Closure given", .{});
                try ctx.vm.strings.append(ctx.allocator, msg);
                try ctx.vm.setPendingException("TypeError", msg);
                break :blk error.RuntimeError;
            }
            break :blk NativeResult.scalar(.{ .int = @intCast(s.bytes().len) });
        },
        .int => |i| blk: {
            var buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch break :blk NativeResult.scalar(.{ .int = 0 });
            break :blk NativeResult.scalar(.{ .int = @intCast(s.len) });
        },
        .float => |f| blk: {
            var buf: [64]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{f}) catch break :blk NativeResult.scalar(.{ .int = 0 });
            break :blk NativeResult.scalar(.{ .int = @intCast(s.len) });
        },
        .bool => |b| NativeResult.scalar(.{ .int = if (b) 1 else 0 }),
        .null => NativeResult.scalar(.{ .int = 0 }),
        .object => |obj| blk: {
            if (ctx.vm.hasMethod(obj.class_name, "__toString")) {
                const result = try ctx.vm.callMethod(obj, "__toString", &.{});
                if (result == .string) break :blk NativeResult.scalar(.{ .int = @intCast(result.string.bytes().len) });
            }
            // object without __toString: PHP throws TypeError with the class name
            const msg = try std.fmt.allocPrint(ctx.allocator, "strlen(): Argument #1 ($string) must be of type string, {s} given", .{phpTypeName(args[0])});
            try ctx.vm.strings.append(ctx.allocator, msg);
            try ctx.vm.setPendingException("TypeError", msg);
            break :blk error.RuntimeError;
        },
        .array => blk: {
            try ctx.vm.setPendingException("TypeError", "strlen(): Argument #1 ($string) must be of type string, array given");
            break :blk error.RuntimeError;
        },
        else => NativeResult.scalar(.{ .int = 0 }),
    };
}

fn boolval(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = args[0].isTruthy() });
}

fn is_object(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    if (args[0] == .object) return NativeResult.scalar(.{ .bool = true });
    if (args[0] == .generator) return NativeResult.scalar(.{ .bool = true });
    if (args[0] == .fiber) return NativeResult.scalar(.{ .bool = true });
    if (args[0] == .string and std.mem.startsWith(u8, args[0].string.bytes(), "__closure_")) return NativeResult.scalar(.{ .bool = true });
    return NativeResult.scalar(.{ .bool = false });
}

fn is_scalar(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{
        .bool = switch (args[0]) {
            .int, .float, .bool => true,
            // closures are stored as a Value.string with a "__closure_" prefix;
            // PHP treats Closure as an object, not a scalar
            .string => |s| !std.mem.startsWith(u8, s.bytes(), "__closure_"),
            else => false,
        },
    });
}

fn is_iterable(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    if (args[0] == .array or args[0] == .generator) return NativeResult.scalar(.{ .bool = true });
    if (args[0] == .object) {
        const cn = args[0].object.class_name;
        if (ctx.vm.isInstanceOf(cn, "Traversable")) return NativeResult.scalar(.{ .bool = true });
        if (ctx.vm.isInstanceOf(cn, "Iterator")) return NativeResult.scalar(.{ .bool = true });
        if (ctx.vm.isInstanceOf(cn, "IteratorAggregate")) return NativeResult.scalar(.{ .bool = true });
        if (ctx.vm.hasMethod(cn, "getIterator")) return NativeResult.scalar(.{ .bool = true });
        if (ctx.vm.hasMethod(cn, "current") and ctx.vm.hasMethod(cn, "next")) return NativeResult.scalar(.{ .bool = true });
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn is_countable(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    if (args[0] == .array) return NativeResult.scalar(.{ .bool = true });
    if (args[0] == .object) {
        const cn = args[0].object.class_name;
        if (ctx.vm.isInstanceOf(cn, "Countable")) return NativeResult.scalar(.{ .bool = true });
        if (ctx.vm.hasMethod(cn, "count")) return NativeResult.scalar(.{ .bool = true });
    }
    return NativeResult.scalar(.{ .bool = false });
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
    const s = args[0].string.bytes();
    if (s.len == 0) return .{ .bool = false };
    for (s) |c| {
        if (!pred(c)) return .{ .bool = false };
    }
    return .{ .bool = true };
}

fn ctype_alpha(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(ctypeCheck(args, std.ascii.isAlphabetic));
}
fn ctype_digit(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(ctypeCheck(args, std.ascii.isDigit));
}
fn ctype_alnum(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(ctypeCheck(args, std.ascii.isAlphanumeric));
}
fn ctype_space(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(ctypeCheck(args, std.ascii.isWhitespace));
}
fn ctype_upper(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(ctypeCheck(args, std.ascii.isUpper));
}
fn ctype_lower(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(ctypeCheck(args, std.ascii.isLower));
}
fn ctype_xdigit(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(ctypeCheck(args, std.ascii.isHex));
}
fn ctype_print(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(ctypeCheck(args, std.ascii.isPrint));
}
fn ctype_punct(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(ctypeCheck(args, isPunct));
}
fn ctype_cntrl(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(ctypeCheck(args, std.ascii.isControl));
}
fn ctype_graph(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(ctypeCheck(args, isGraph));
}

// PHP's setlocale wraps libc setlocale. zphp doesn't actually flip the process
// locale (libc setlocale isn't thread-safe and can cause surprising interactions
// with intl/ICU), but applications use the return value to detect whether a
// locale was accepted. return the requested locale string verbatim, or the
// previous locale when querying with "0"
var current_locale: [128]u8 = [_]u8{0} ** 128;
var current_locale_len: usize = 1;
var current_locale_initialized: bool = false;

fn ensureLocaleInit() void {
    if (current_locale_initialized) return;
    current_locale[0] = 'C';
    current_locale_len = 1;
    current_locale_initialized = true;
}

fn native_setlocale(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    ensureLocaleInit();
    // PHP: setlocale($category, ...$locales). first arg is category (int)
    if (args.len < 1) return NativeResult.copyString(ctx.allocator, current_locale[0..current_locale_len]);

    // collect candidate locale strings from args 1..n. each may be a string or an
    // array (variadic / array form). first one that "works" wins; "0" queries
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        switch (args[i]) {
            .string => |s| {
                if (std.mem.eql(u8, s.bytes(), "0")) {
                    return NativeResult.copyString(ctx.allocator, current_locale[0..current_locale_len]);
                }
                // accept the string verbatim. empty string maps to "C"
                const new = if (s.bytes().len == 0) "C" else s.bytes();
                if (new.len <= current_locale.len) {
                    @memcpy(current_locale[0..new.len], new);
                    current_locale_len = new.len;
                }
                return NativeResult.copyString(ctx.allocator, new);
            },
            .array => |arr| {
                for (arr.entries.items) |e| {
                    if (e.value != .string) continue;
                    const s = e.value.string.bytes();
                    if (s.len == 0) continue;
                    if (s.len <= current_locale.len) {
                        @memcpy(current_locale[0..s.len], s);
                        current_locale_len = s.len;
                    }
                    return NativeResult.copyString(ctx.allocator, s);
                }
            },
            else => continue,
        }
    }
    // no acceptable locale provided
    return NativeResult.scalar(.{ .bool = false });
}

// minimal localeconv: returns a default "C" locale info array. real apps use
// this for currency formatting fallbacks; the intl extension is the real path
fn native_localeconv(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    const empty = "";
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("decimal_point") }, .{ .string = Value.String.borrowed(".") });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("thousands_sep") }, .{ .string = Value.String.borrowed(empty) });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("int_curr_symbol") }, .{ .string = Value.String.borrowed(empty) });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("currency_symbol") }, .{ .string = Value.String.borrowed(empty) });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("mon_decimal_point") }, .{ .string = Value.String.borrowed(empty) });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("mon_thousands_sep") }, .{ .string = Value.String.borrowed(empty) });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("positive_sign") }, .{ .string = Value.String.borrowed(empty) });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("negative_sign") }, .{ .string = Value.String.borrowed(empty) });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("int_frac_digits") }, .{ .int = 127 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("frac_digits") }, .{ .int = 127 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("p_cs_precedes") }, .{ .int = 127 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("p_sep_by_space") }, .{ .int = 127 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("n_cs_precedes") }, .{ .int = 127 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("n_sep_by_space") }, .{ .int = 127 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("p_sign_posn") }, .{ .int = 127 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("n_sign_posn") }, .{ .int = 127 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("grouping") }, .{ .array = try ctx.createArray() });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("mon_grouping") }, .{ .array = try ctx.createArray() });
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_nl_langinfo(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = args;
    return NativeResult.literal("");
}

fn dupString(ctx: *NativeContext, s: []const u8) ![]const u8 {
    const owned = try ctx.allocator.dupe(u8, s);
    try ctx.strings.append(ctx.allocator, owned);
    return owned;
}

fn isPunct(c: u8) bool {
    return std.ascii.isPrint(c) and !std.ascii.isAlphanumeric(c) and c != ' ';
}
fn isGraph(c: u8) bool {
    return std.ascii.isPrint(c) and c != ' ';
}

fn get_class(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) {
        const this_val = ctx.vm.currentFrame().vars.get("$this") orelse return NativeResult.scalar(Value{ .bool = false });
        if (this_val != .object) return NativeResult.scalar(.{ .bool = false });
        return NativeResult.copyString(ctx.allocator, this_val.object.class_name);
    }
    if (args[0] == .object) return NativeResult.copyString(ctx.allocator, args[0].object.class_name);
    if (args[0] == .generator) return NativeResult.literal("Generator");
    if (args[0] == .fiber) return NativeResult.literal("Fiber");
    if (args[0] == .string and std.mem.startsWith(u8, args[0].string.bytes(), "__closure_")) return NativeResult.literal("Closure");
    return throwObjectArg(ctx, "get_class", args[0]);
}

fn get_called_class(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    var i = ctx.vm.frame_count;
    while (i > 0) {
        i -= 1;
        if (ctx.vm.frames[i].called_class) |cc| return NativeResult.copyString(ctx.allocator, cc);
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn native_get_declared_classes(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    var it = ctx.vm.classes.iterator();
    while (it.next()) |e| {
        try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(e.key_ptr.*) });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_get_declared_interfaces(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    var it = ctx.vm.interfaces.iterator();
    while (it.next()) |e| {
        try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(e.key_ptr.*) });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_get_declared_traits(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    var it = ctx.vm.traits.iterator();
    while (it.next()) |e| {
        try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(e.key_ptr.*) });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn classExistsCaseInsensitive(ctx: *NativeContext, name: []const u8) bool {
    if (ctx.vm.classes.contains(name)) return true;
    var it = ctx.vm.classes.iterator();
    while (it.next()) |e| {
        if (std.ascii.eqlIgnoreCase(e.key_ptr.*, name)) return true;
    }
    return false;
}

fn class_exists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const raw = args[0].string.bytes();
    const name = if (raw.len > 0 and raw[0] == '\\') raw[1..] else raw;
    if (std.ascii.eqlIgnoreCase(name, "stdClass") or std.ascii.eqlIgnoreCase(name, "Attribute")) return NativeResult.scalar(.{ .bool = true });
    if (std.ascii.eqlIgnoreCase(name, "Closure") or std.ascii.eqlIgnoreCase(name, "Generator") or std.ascii.eqlIgnoreCase(name, "Fiber")) return NativeResult.scalar(.{ .bool = true });
    if (ctx.vm.interfaces.contains(name)) return NativeResult.scalar(.{ .bool = false });
    if (ctx.vm.traits.contains(name)) return NativeResult.scalar(.{ .bool = false });
    if (classExistsCaseInsensitive(ctx, name)) return NativeResult.scalar(.{ .bool = true });
    const autoload = args.len < 2 or !(args[1] == .bool and !args[1].bool);
    if (autoload and ctx.vm.autoload_callbacks.items.len > 0) {
        try ctx.vm.tryAutoload(name);
        return NativeResult.scalar(.{ .bool = classExistsCaseInsensitive(ctx, name) and !ctx.vm.interfaces.contains(name) });
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn method_exists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    // closures (stored as unique name strings) report themselves as the
    // 'Closure' class. they always have __invoke + the public Closure API
    if (args[0] == .string and std.mem.startsWith(u8, args[0].string.bytes(), "__closure_")) {
        const m = args[1].string.bytes();
        const closure_methods = [_][]const u8{ "__invoke", "bindTo", "bind", "call", "fromCallable", "getClosureScopeClass", "getClosureThis", "getClosureCalledClass", "getClosureUsedVariables" };
        for (closure_methods) |cm| if (std.ascii.eqlIgnoreCase(cm, m)) return NativeResult.scalar(.{ .bool = true });
        return NativeResult.scalar(.{ .bool = false });
    }
    var current: ?[]const u8 = if (args[0] == .object)
        args[0].object.class_name
    else if (args[0] == .generator)
        "Generator"
    else if (args[0] == .fiber)
        "Fiber"
    else if (args[0] == .string)
        args[0].string.bytes()
    else {
        try ctx.vm.setPendingException("TypeError", "method_exists(): Argument #1 ($object_or_class) must be of type object|string");
        return error.RuntimeError;
    };
    const method_name = args[1].string.bytes();
    // Generator and Fiber are not registered as ClassDef. Hardcode their
    // method tables so method_exists works on tagged values and "Generator"/"Fiber" strings.
    if (std.mem.eql(u8, current.?, "Generator")) {
        const gen_methods = [_][]const u8{ "current", "key", "next", "rewind", "send", "throw", "getReturn", "valid" };
        for (gen_methods) |m| if (std.ascii.eqlIgnoreCase(m, method_name)) return NativeResult.scalar(.{ .bool = true });
        return NativeResult.scalar(.{ .bool = false });
    }
    if (std.mem.eql(u8, current.?, "Fiber")) {
        const fiber_methods = [_][]const u8{ "start", "resume", "throw", "getReturn", "isStarted", "isSuspended", "isRunning", "isTerminated", "suspend", "getCurrent" };
        for (fiber_methods) |m| if (std.ascii.eqlIgnoreCase(m, method_name)) return NativeResult.scalar(.{ .bool = true });
        return NativeResult.scalar(.{ .bool = false });
    }
    var buf: [256]u8 = undefined;
    var depth: usize = 0;
    while (current) |cn| {
        var canonical_method = method_name;
        var private_at_this_class = false;
        if (ctx.vm.classes.get(cn)) |cls| {
            var methods = cls.methods.iterator();
            while (methods.next()) |entry| {
                if (std.ascii.eqlIgnoreCase(entry.key_ptr.*, method_name)) {
                    canonical_method = entry.key_ptr.*;
                    if (entry.value_ptr.visibility == .private) private_at_this_class = true;
                    break;
                }
            }
        }
        // ancestor private methods are not visible from a subclass
        if (depth > 0 and private_at_this_class) {
            // skip this class's match; continue up
        } else {
            const full = std.fmt.bufPrint(&buf, "{s}::{s}", .{ cn, canonical_method }) catch return NativeResult.scalar(Value{ .bool = false });
            if (ctx.vm.native_fns.contains(full)) return NativeResult.scalar(.{ .bool = true });
            if (ctx.vm.functions.contains(full)) return NativeResult.scalar(.{ .bool = true });
            if (!std.mem.eql(u8, canonical_method, method_name)) return NativeResult.scalar(.{ .bool = true });
        }
        if (ctx.vm.classes.get(cn)) |cls| {
            current = cls.parent;
        } else {
            try ctx.vm.tryAutoload(cn);
            if (ctx.vm.classes.get(cn)) |cls| {
                current = cls.parent;
            } else break;
        }
        depth += 1;
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn property_exists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const prop_name = args[1].string.bytes();
    if (args[0] == .object) {
        const obj = args[0].object;
        if (obj.getSlotIndex(prop_name) != null) return NativeResult.scalar(.{ .bool = true });
        if (obj.properties.contains(prop_name)) return NativeResult.scalar(.{ .bool = true });
        // a static property (or a declared instance property not yet
        // materialized) of the object's class or an ancestor also counts
        var current: ?[]const u8 = obj.class_name;
        while (current) |name| {
            const cls = ctx.vm.classes.get(name) orelse break;
            if (cls.static_props.contains(prop_name)) return NativeResult.scalar(.{ .bool = true });
            for (cls.properties.items) |p| {
                if (std.mem.eql(u8, p.name, prop_name)) return NativeResult.scalar(.{ .bool = true });
            }
            current = cls.parent;
        }
        return NativeResult.scalar(.{ .bool = false });
    }
    if (args[0] == .string) {
        const raw = args[0].string.bytes();
        const class_name = if (raw.len > 0 and raw[0] == '\\') raw[1..] else raw;
        var is_own = true;
        var current: ?[]const u8 = class_name;
        while (current) |name| {
            const cls = ctx.vm.classes.get(name) orelse break;
            for (cls.properties.items) |p| {
                if (std.mem.eql(u8, p.name, prop_name)) {
                    if (!is_own and p.visibility == .private) break;
                    return NativeResult.scalar(.{ .bool = true });
                }
            }
            if (cls.static_props.get(prop_name)) |_| {
                const vis = cls.static_prop_visibility.get(prop_name) orelse @as(ClassDef.Visibility, .public);
                if (is_own or vis != .private) return NativeResult.scalar(.{ .bool = true });
            }
            current = cls.parent;
            is_own = false;
        }
        return NativeResult.scalar(.{ .bool = false });
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn native_is_callable(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    const val = args[0];
    const syntax_only = args.len > 1 and args[1].isTruthy();
    // PHP's 3rd by-ref param receives the resolved callable name on success
    // (or its string form). populated regardless of return value so caller
    // code can inspect failed resolution attempts too
    const fillName = struct {
        fn run(c: *NativeContext, a: []const Value, name_str: []const u8) void {
            if (a.len < 3) return;
            const owned = c.allocator.dupe(u8, name_str) catch return;
            c.vm.strings.append(c.allocator, owned) catch {};
            c.setCallerVar(2, a.len, .{ .string = Value.String.borrowed(owned) });
        }
    }.run;
    if (val == .string) {
        const raw = val.string.bytes();
        const name = if (raw.len > 0 and raw[0] == '\\') raw[1..] else raw;
        fillName(ctx, args, name);
        if (syntax_only) return NativeResult.scalar(.{ .bool = true });
        return NativeResult.scalar(.{ .bool = ctx.vm.isValueCallable(val) });
    }
    if (val == .object) {
        if (std.mem.eql(u8, val.object.class_name, "Closure")) return NativeResult.scalar(.{ .bool = true });
        var buf: [256]u8 = undefined;
        const full = std.fmt.bufPrint(&buf, "{s}::__invoke", .{val.object.class_name}) catch "";
        fillName(ctx, args, full);
        return NativeResult.scalar(.{ .bool = ctx.vm.hasMethod(val.object.class_name, "__invoke") });
    }
    if (val == .array) {
        const arr = val.array;
        if (arr.entries.items.len != 2) return NativeResult.scalar(.{ .bool = false });
        const target = arr.entries.items[0].value;
        const method_val = arr.entries.items[1].value;
        if (method_val != .string) return NativeResult.scalar(.{ .bool = false });
        const method = method_val.string.bytes();
        const raw_class = if (target == .object)
            target.object.class_name
        else if (target == .string)
            target.string.bytes()
        else
            return NativeResult.scalar(.{ .bool = false });
        const class_name = if (raw_class.len > 0 and raw_class[0] == '\\') raw_class[1..] else raw_class;
        {
            var name_buf: [256]u8 = undefined;
            const resolved = std.fmt.bufPrint(&name_buf, "{s}::{s}", .{ class_name, method }) catch "";
            fillName(ctx, args, resolved);
        }
        if (syntax_only) return NativeResult.scalar(.{ .bool = true });
        return NativeResult.scalar(.{ .bool = ctx.vm.isValueCallable(val) });
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn native_settype(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.null);
    if (args.len < 2 or args[1] != .string) return NativeResult.share(args[0]);
    const type_name = args[1].string.bytes();
    const val = args[0];
    if (std.mem.eql(u8, type_name, "int") or std.mem.eql(u8, type_name, "integer"))
        return NativeResult.scalar(.{ .int = Value.toInt(val) });
    if (std.mem.eql(u8, type_name, "float") or std.mem.eql(u8, type_name, "double"))
        return NativeResult.scalar(.{ .float = Value.toFloat(val) });
    if (std.mem.eql(u8, type_name, "string")) {
        if (val == .string) return NativeResult.share(val);
        if (val == .array) try ctx.vm.emitWarning("Array to string conversion");
        var buf = std.ArrayListUnmanaged(u8){};
        defer buf.deinit(ctx.allocator);
        try val.format(&buf, ctx.allocator);
        const s = try buf.toOwnedSlice(ctx.allocator);
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, s));
    }
    if (std.mem.eql(u8, type_name, "bool") or std.mem.eql(u8, type_name, "boolean"))
        return NativeResult.scalar(.{ .bool = val.isTruthy() });
    if (std.mem.eql(u8, type_name, "null"))
        return NativeResult.scalar(.null);
    if (std.mem.eql(u8, type_name, "array")) {
        if (val == .array) return NativeResult.share(val);
        return NativeResult.borrowed(try ctx.vm.castToArray(val));
    }
    if (std.mem.eql(u8, type_name, "object")) {
        if (val == .object) return NativeResult.share(val);
        return NativeResult.borrowed(try ctx.vm.castToObject(val));
    }
    try ctx.vm.setPendingException("ValueError", "settype(): Argument #2 ($type) must be a valid type");
    return error.RuntimeError;
}

fn native_call_user_func(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.null);
    return NativeResult.share(try ctx.invokeCallable(args[0], args[1..]));
}

fn native_call_user_func_array(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.scalar(.null);
    if (args[1] != .array) return NativeResult.share(try ctx.invokeCallable(args[0], &.{}));
    const arr = args[1].array;
    var call_args: [16]Value = undefined;
    const count_val: usize = @min(16, arr.entries.items.len);
    for (0..count_val) |i| call_args[i] = arr.entries.items[i].value;
    return NativeResult.share(try ctx.invokeCallable(args[0], call_args[0..count_val]));
}

fn native_function_exists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = ctx.vm.functionExists(args[0].string.bytes()) });
}

fn native_get_object_vars(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // closures are stored as name strings and report as 'object'/'Closure'
    // but have no user-visible properties - return empty array per PHP
    if (args.len > 0 and args[0] == .string and std.mem.startsWith(u8, args[0].string.bytes(), "__closure_")) {
        const empty = try ctx.createArray();
        return NativeResult.borrowed(.{ .array = empty });
    }
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(Value{ .bool = false });
    try ctx.vm.triggerLazyInit(args[0].object);
    const obj = args[0].object.storage();
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
                try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(name) }, slots[i]);
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
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(name) }, entry.value_ptr.*);
    }
    return NativeResult.borrowed(.{ .array = arr });
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

fn native_get_class_methods(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(Value{ .bool = false });
    // closures (stored as name strings) report the standard Closure API
    if (args[0] == .string and std.mem.startsWith(u8, args[0].string.bytes(), "__closure_")) {
        var arr = try ctx.createArray();
        const methods = [_][]const u8{ "bind", "bindTo", "call", "fromCallable", "__invoke" };
        for (methods) |m| try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(m) });
        return NativeResult.borrowed(.{ .array = arr });
    }
    const class_name = if (args[0] == .object)
        args[0].object.class_name
    else if (args[0] == .generator)
        "Generator"
    else if (args[0] == .fiber)
        "Fiber"
    else if (args[0] == .string)
        args[0].string.bytes()
    else
        return NativeResult.scalar(Value{ .bool = false });

    if (std.mem.eql(u8, class_name, "Generator")) {
        var arr = try ctx.createArray();
        const methods = [_][]const u8{ "rewind", "valid", "current", "key", "next", "send", "throw", "getReturn", "__debugInfo" };
        for (methods) |m| try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(m) });
        return NativeResult.borrowed(.{ .array = arr });
    }
    if (std.mem.eql(u8, class_name, "Fiber")) {
        var arr = try ctx.createArray();
        const methods = [_][]const u8{ "__construct", "start", "resume", "throw", "isStarted", "isSuspended", "isRunning", "isTerminated", "getReturn", "getCurrent", "suspend" };
        for (methods) |m| try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(m) });
        return NativeResult.borrowed(.{ .array = arr });
    }

    // visibility: caller in same class sees all; subclass sees public+protected;
    // outside sees only public. ancestor private methods don't appear regardless.
    const caller = ctx.vm.currentDefiningClass();
    const arr = try ctx.createArray();
    var seen = std.StringHashMapUnmanaged(void){};
    defer seen.deinit(ctx.allocator);
    var current: ?[]const u8 = class_name;
    var depth: usize = 0;
    while (current) |cn| {
        if (ctx.vm.classes.get(cn)) |cls| {
            const emit = struct {
                fn run(c: *NativeContext, a: *@import("../runtime/value.zig").PhpArray, s: *std.StringHashMapUnmanaged(void), name: []const u8, info: anytype, d: usize, cnn: []const u8, clsn: []const u8, callr: ?[]const u8) !void {
                    if (std.mem.indexOf(u8, name, "$hook_") != null) return;
                    if (d > 0 and info.visibility == .private) return;
                    const visible = switch (info.visibility) {
                        .public => true,
                        .protected => callr != null and isInClassChain(c.vm, callr.?, clsn),
                        .private => callr != null and std.mem.eql(u8, callr.?, cnn),
                    };
                    if (!visible) return;
                    if (s.contains(name)) return;
                    try s.put(c.allocator, name, {});
                    try a.append(c.allocator, .{ .string = Value.String.borrowed(name) });
                }
            }.run;
            // declaration order when available, hash order as fallback
            if (cls.method_order.items.len > 0) {
                for (cls.method_order.items) |mname| {
                    const info = cls.methods.get(mname) orelse continue;
                    try emit(ctx, arr, &seen, mname, info, depth, cn, class_name, caller);
                }
            } else {
                var iter = cls.methods.iterator();
                while (iter.next()) |entry| {
                    try emit(ctx, arr, &seen, entry.key_ptr.*, entry.value_ptr.*, depth, cn, class_name, caller);
                }
            }
            current = cls.parent;
        } else break;
        depth += 1;
    }
    return NativeResult.borrowed(.{ .array = arr });
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

fn native_get_class_vars(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(Value{ .bool = false });
    const raw = args[0].string.bytes();
    const class_name = if (raw.len > 0 and raw[0] == '\\') raw[1..] else raw;
    try ctx.vm.resolveClassDefaults(class_name);
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.scalar(Value{ .bool = false });
    const caller = ctx.vm.currentDefiningClass();
    var arr = try ctx.createArray();
    for (cls.properties.items) |prop| {
        const visible = switch (prop.visibility) {
            .public => true,
            .protected => caller != null and isInClassChain(ctx.vm, caller.?, class_name),
            .private => caller != null and std.mem.eql(u8, caller.?, class_name),
        };
        if (!visible) continue;
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(prop.name) }, prop.default);
    }
    // PHP's get_class_vars also includes static properties
    var sit = cls.static_props.iterator();
    while (sit.next()) |e| {
        // class constants are also stored in static_props; skip them
        if (cls.constants.contains(e.key_ptr.*)) continue;
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(e.key_ptr.*) }, e.value_ptr.*);
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_get_parent_class(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) {
        // no-arg form: use the calling class
        const caller = ctx.vm.currentDefiningClass() orelse return NativeResult.scalar(Value{ .bool = false });
        const cls = ctx.vm.classes.get(caller) orelse return NativeResult.scalar(Value{ .bool = false });
        if (cls.parent) |p| return NativeResult.copyString(ctx.allocator, p);
        return NativeResult.scalar(Value{ .bool = false });
    }
    // closures (string-form) report as Closure with no parent
    if (args[0] == .string and std.mem.startsWith(u8, args[0].string.bytes(), "__closure_")) {
        return NativeResult.scalar(Value{ .bool = false });
    }
    const raw = if (args[0] == .object)
        args[0].object.class_name
    else if (args[0] == .string)
        args[0].string.bytes()
    else
        return NativeResult.scalar(Value{ .bool = false });
    const class_name = if (raw.len > 0 and raw[0] == '\\') raw[1..] else raw;
    if (ctx.vm.traits.contains(class_name) or ctx.vm.interfaces.contains(class_name)) return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.get(class_name) orelse {
        try ctx.vm.setPendingException("TypeError", "get_parent_class(): Argument #1 ($object_or_class) must be an object or a valid class name");
        return error.RuntimeError;
    };
    if (cls.parent) |p| return NativeResult.copyString(ctx.allocator, p);
    return NativeResult.scalar(Value{ .bool = false });
}

fn native_is_a(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const raw_target = args[1].string.bytes();
    const target = if (raw_target.len > 0 and raw_target[0] == '\\') raw_target[1..] else raw_target;
    if (args[0] == .generator) {
        return NativeResult.scalar(.{ .bool = std.mem.eql(u8, target, "Generator") or std.mem.eql(u8, target, "Iterator") or std.mem.eql(u8, target, "Traversable") });
    }
    if (args[0] == .fiber) return NativeResult.scalar(.{ .bool = std.mem.eql(u8, target, "Fiber") });
    // closures stored as unique name strings present as object/Closure
    if (args[0] == .string and std.mem.startsWith(u8, args[0].string.bytes(), "__closure_")) {
        return NativeResult.scalar(.{ .bool = std.mem.eql(u8, target, "Closure") });
    }
    if (args[0] == .string) {
        // string arg requires explicit allow_string=true (3rd arg)
        const allow_string = args.len >= 3 and args[2].isTruthy();
        if (!allow_string) return NativeResult.scalar(.{ .bool = false });
        return NativeResult.scalar(.{ .bool = ctx.vm.isInstanceOf(args[0].string.bytes(), target) });
    }
    const class_name = if (args[0] == .object) args[0].object.class_name else return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = ctx.vm.isInstanceOf(class_name, target) });
}

fn native_is_subclass_of(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    if (args[0] == .generator) {
        const t = args[1].string.bytes();
        return NativeResult.scalar(.{ .bool = std.mem.eql(u8, t, "Iterator") or std.mem.eql(u8, t, "Traversable") });
    }
    if (args[0] == .fiber) return NativeResult.scalar(.{ .bool = false });
    const class_name = if (args[0] == .object)
        args[0].object.class_name
    else if (args[0] == .string)
        args[0].string.bytes()
    else
        return NativeResult.scalar(Value{ .bool = false });
    const target_name = args[1].string.bytes();
    try ctx.vm.tryAutoload(class_name);
    try ctx.vm.tryAutoload(target_name);
    // is_subclass_of returns false if same class, only true for actual subclasses
    if (std.mem.eql(u8, class_name, target_name)) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = ctx.vm.isInstanceOf(class_name, target_name) });
}

fn native_spl_object_id(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(Value{ .int = 0 });
    if (args[0] == .object) {
        if (args[0].object.id == 0) {
            ctx.vm.next_object_id += 1;
            args[0].object.id = ctx.vm.next_object_id;
        }
        return NativeResult.scalar(.{ .int = @intCast(args[0].object.id) });
    }
    if (args[0] == .generator) return NativeResult.scalar(.{ .int = @intCast(@intFromPtr(args[0].generator)) });
    if (args[0] == .fiber) return NativeResult.scalar(.{ .int = @intCast(@intFromPtr(args[0].fiber)) });
    // closures stored as unique name strings - mirror spl_object_hash by
    // using the string's pointer as the id
    if (args[0] == .string and std.mem.startsWith(u8, args[0].string.bytes(), "__closure_")) {
        return NativeResult.scalar(.{ .int = @intCast(@intFromPtr(args[0].string.bytes().ptr)) });
    }
    return throwObjectArg(ctx, "spl_object_id", args[0]);
}

fn throwObjectArg(ctx: *NativeContext, comptime func: []const u8, v: Value) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, func ++ "(): Argument #1 ($object) must be of type object, {s} given", .{v.valueName()});
    try ctx.strings.append(ctx.allocator, msg);
    try ctx.vm.setPendingException("TypeError", msg);
    return error.RuntimeError;
}

fn native_exit(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len > 0) {
        if (args[0] == .string) {
            try ctx.vm.output.appendSlice(ctx.allocator, args[0].string.bytes());
        } else if (args[0] == .int) {
            // PHP truncates to u8 ([0,255]) for the process exit status
            const code: i64 = args[0].int;
            ctx.vm.exit_code = @intCast(@as(i64, @mod(code, 256)));
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

fn native_version_compare(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.null);
    const v1 = args[0].string.bytes();
    const v2 = args[1].string.bytes();

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
            if (toks1[j].is_num) {
                cmp = 1;
                break;
            } else {
                // tag vs implicit release: tag < release
                if (toks1[j].tag_weight < 0) {
                    cmp = -1;
                    break;
                }
                if (toks1[j].tag_weight > 0) {
                    cmp = 1;
                    break;
                }
            }
        }
        if (!has_a and has_b) {
            if (toks2[j].is_num) {
                cmp = -1;
                break;
            } else {
                if (toks2[j].tag_weight < 0) {
                    cmp = 1;
                    break;
                }
                if (toks2[j].tag_weight > 0) {
                    cmp = -1;
                    break;
                }
            }
        }
        if (has_a and has_b) {
            const a = toks1[j];
            const b = toks2[j];
            if (a.is_num and b.is_num) {
                if (a.num < b.num) {
                    cmp = -1;
                    break;
                }
                if (a.num > b.num) {
                    cmp = 1;
                    break;
                }
            } else if (!a.is_num and !b.is_num) {
                if (a.tag_weight < b.tag_weight) {
                    cmp = -1;
                    break;
                }
                if (a.tag_weight > b.tag_weight) {
                    cmp = 1;
                    break;
                }
            } else {
                // num vs tag: in PHP context, a number part > a tag part
                if (a.is_num) {
                    cmp = 1;
                    break;
                } else {
                    cmp = -1;
                    break;
                }
            }
        }
    }

    if (args.len >= 3 and args[2] == .string) {
        const op = args[2].string.bytes();
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
        return NativeResult.scalar(.{ .bool = result });
    }

    _ = ctx;
    return NativeResult.scalar(.{ .int = cmp });
}

fn native_php_sapi_name(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.literal("cli");
}

fn native_php_version(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.literal("8.4.1");
}

fn native_getmypid(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = platform.getpid() });
}

fn native_getmyuid(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = if (platform.is_windows) 0 else @intCast(std.c.getuid()) });
}

extern "c" fn getgid() c_uint;

fn native_getmygid(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = if (platform.is_windows) 0 else @intCast(getgid()) });
}

// a value from the loaded configuration (php.ini and -d), whether or not any
// extension registers the directive; cfg_file_path names the ini file itself
fn native_get_cfg_var(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(Value{ .bool = false });
    const ini_config = @import("../ini_config.zig");
    const name = args[0].string.bytes();
    if (std.mem.eql(u8, name, "cfg_file_path")) return NativeResult.copyString(ctx.allocator, ini_config.loadedFile() orelse return NativeResult.scalar(Value{ .bool = false }));
    const value = ini_config.get(name) orelse return NativeResult.scalar(Value{ .bool = false });
    return NativeResult.copyString(ctx.allocator, value);
}

extern "c" fn getlogin() ?[*:0]const u8;

fn native_get_current_user(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // PHP returns the owner of the running script. for the CLI that's the
    // current process user; for SAPIs without that distinction, it's the
    // login. fall back to USER / LOGNAME env vars when the syscall returns
    // null (containers where /etc/passwd has no matching uid)
    if (getlogin()) |raw| {
        const span = std.mem.span(raw);
        if (span.len > 0) {
            return NativeResult.copyString(ctx.allocator, span);
        }
    }
    inline for ([_][]const u8{ "USER", "LOGNAME" }) |key| {
        if (platform.getenv(key)) |val| {
            if (val.len > 0) {
                return NativeResult.copyString(ctx.allocator, val);
            }
        }
    }
    return NativeResult.literal("");
}

fn iniDefault(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "date.timezone")) return "UTC";
    // PHP CLI default is "-1" (no limit); web SAPI default is "128M"
    if (std.mem.eql(u8, name, "memory_limit")) return "128M";
    if (std.mem.eql(u8, name, "post_max_size")) return "8M";
    if (std.mem.eql(u8, name, "upload_max_filesize")) return "2M";
    if (std.mem.eql(u8, name, "max_input_time")) return "-1";
    if (std.mem.eql(u8, name, "max_file_uploads")) return "20";
    if (std.mem.eql(u8, name, "default_charset")) return "UTF-8";
    if (std.mem.eql(u8, name, "default_mimetype")) return "text/html";
    if (std.mem.eql(u8, name, "session.save_handler")) return "files";
    if (std.mem.eql(u8, name, "session.save_path")) return "";
    if (std.mem.eql(u8, name, "session.gc_maxlifetime")) return "1440";
    if (std.mem.eql(u8, name, "session.cookie_lifetime")) return "0";
    if (std.mem.eql(u8, name, "session.use_cookies")) return "1";
    if (std.mem.eql(u8, name, "session.cookie_httponly")) return "";
    if (std.mem.eql(u8, name, "session.cookie_secure")) return "";
    if (std.mem.eql(u8, name, "session.cookie_samesite")) return "";
    if (std.mem.eql(u8, name, "date.default_latitude")) return "31.7667";
    if (std.mem.eql(u8, name, "date.default_longitude")) return "35.2333";
    if (std.mem.eql(u8, name, "precision")) return "14";
    if (std.mem.eql(u8, name, "serialize_precision")) return "-1";
    if (std.mem.eql(u8, name, "open_basedir")) return "";
    if (std.mem.eql(u8, name, "include_path")) return ".:/usr/local/lib/php";
    if (std.mem.eql(u8, name, "log_errors")) return "1";
    if (std.mem.eql(u8, name, "error_log")) return "";
    if (std.mem.eql(u8, name, "html_errors")) return "0";
    if (std.mem.eql(u8, name, "max_execution_time")) return "0";
    // 'stderr' matches PHP CLI's actual default in 8.0+. log_errors emission
    // still goes to stderr; the bare display copy is suppressed because
    // display_errors=STDERR collapses into the log stream. userland
    // 'ini_set(display_errors, 1)' opts back into the dual-stream behavior of
    // display_errors=STDOUT (display copy on stdout, log copy on stderr).
    // displayErrorsEnabled treats this default + 0/Off as "no display copy"
    if (std.mem.eql(u8, name, "display_errors")) return "stderr";
    if (std.mem.eql(u8, name, "error_reporting")) return "30719";
    if (std.mem.eql(u8, name, "zend.assertions")) return "1";
    if (std.mem.eql(u8, name, "assert.active")) return "1";
    if (std.mem.eql(u8, name, "assert.exception")) return "0";
    if (std.mem.eql(u8, name, "assert.bail")) return "0";
    if (std.mem.eql(u8, name, "assert.warning")) return "1";
    if (std.mem.eql(u8, name, "assert.callback")) return "";
    return null;
}

fn native_ini_get(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(Value{ .bool = false });
    const name = args[0].string.bytes();
    if (ctx.vm.ini_settings.get(name)) |stored| return NativeResult.copyString(ctx.allocator, stored);
    if (iniDefault(name)) |def| return NativeResult.copyString(ctx.allocator, def);
    return NativeResult.scalar(Value{ .bool = false });
}

fn native_ini_set(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string) return NativeResult.scalar(Value{ .bool = false });
    const name = args[0].string.bytes();
    // PHP rejects unknown directives. Only allow known names.
    const previous: []const u8 = if (ctx.vm.ini_settings.get(name)) |s| s else if (iniDefault(name)) |d| d else return NativeResult.scalar(Value{ .bool = false });
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(ctx.allocator);
    try args[1].format(&buf, ctx.allocator);
    const new_val = try buf.toOwnedSlice(ctx.allocator);
    try ctx.vm.strings.append(ctx.allocator, new_val);
    const owned_name = try ctx.allocator.dupe(u8, name);
    try ctx.vm.strings.append(ctx.allocator, owned_name);
    try ctx.vm.ini_settings.put(ctx.allocator, owned_name, new_val);
    // a few ini directives map directly to live VM state. mirror them now so
    // userland `ini_set('max_execution_time', '5')` actually arms the deadline
    if (std.mem.eql(u8, name, "max_execution_time")) {
        const seconds = std.fmt.parseInt(i64, std.mem.trim(u8, new_val, " \t\r\n"), 10) catch 0;
        ctx.vm.setExecutionLimit(seconds);
    }
    return NativeResult.copyString(ctx.allocator, previous);
}

// generated from compatibility/extensions.json by scripts/compat-manifest.
// being listed means present, not php-compatible; the manifest records that
const BuiltinExtension = @import("extensions_generated.zig").Extension;
const builtin_extensions = @import("extensions_generated.zig").extensions;

fn builtinExtension(name: []const u8) ?*const BuiltinExtension {
    for (&builtin_extensions) |*ext| {
        if (ext.unix_only and platform.is_windows) continue;
        if (std.ascii.eqlIgnoreCase(name, ext.name)) return ext;
    }
    return null;
}

fn native_extension_loaded(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const name = args[0].string.bytes();
    if (builtinExtension(name) != null) return NativeResult.scalar(.{ .bool = true });
    // also accept the historic "datetime" alias for "date"
    if (std.ascii.eqlIgnoreCase(name, "datetime")) return NativeResult.scalar(.{ .bool = true });
    return NativeResult.scalar(.{ .bool = @import("../extension.zig").isLoaded(name) });
}

fn native_get_loaded_extensions(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    for (&builtin_extensions) |*ext| {
        if (ext.unix_only and platform.is_windows) continue;
        try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(ext.name) });
    }
    for (@import("../extension.zig").loaded()) |ext| try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(ext.name) });
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_get_extension_funcs(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const name = args[0].string.bytes();
    // php looks up exactly "zend" as Core, and answers false for an extension
    // it does not know or that registers no functions
    if (builtinExtension(if (std.ascii.eqlIgnoreCase(name, "zend")) "Core" else name)) |ext| {
        if (ext.functions.len == 0) return NativeResult.scalar(.{ .bool = false });
        const arr = try ctx.createArray();
        for (ext.functions) |f| try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(f) });
        return NativeResult.borrowed(.{ .array = arr });
    }
    for (@import("../extension.zig").loaded()) |ext| {
        if (!std.ascii.eqlIgnoreCase(name, ext.name)) continue;
        if (ext.functions.items.len == 0) return NativeResult.scalar(.{ .bool = false });
        const arr = try ctx.createArray();
        for (ext.functions.items) |f| try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(f.name) });
        return NativeResult.borrowed(.{ .array = arr });
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn native_get_included_files(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    var arr = try ctx.createArray();
    var iter = ctx.vm.loaded_files.iterator();
    while (iter.next()) |entry| {
        try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(entry.key_ptr.*) });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_register_shutdown_function(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.null);
    try ctx.vm.shutdown_callbacks.append(ctx.allocator, args[0]);
    VM.retainValue(args[0]);
    return NativeResult.scalar(.null);
}

fn native_memory_get_usage(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // pull current process RSS via getrusage. PHP distinguishes "current" from
    // "peak" usage; zphp's arena doesn't track byte-accurate current bytes per
    // call, so we report the OS-level resident-set peak. matches the common
    // "did memory grow?" check and stays monotonic, while giving a value that's
    // proportional to actual usage (unlike the previous 1024-byte stub)
    return NativeResult.scalar(.{ .int = platform.peakRss() });
}

fn native_set_error_handler(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const prev = ctx.vm.user_error_handler orelse Value.null;
    if (ctx.vm.user_error_handler) |h| {
        try ctx.vm.error_handler_stack.append(ctx.allocator, .{ .handler = h, .mask = ctx.vm.user_error_handler_mask });
    }
    if (args.len > 0 and args[0] != .null) {
        VM.retainValue(args[0]);
        ctx.vm.user_error_handler = args[0];
    } else {
        ctx.vm.user_error_handler = null;
    }
    ctx.vm.user_error_handler_mask = if (args.len >= 2 and args[1] == .int) args[1].int else -1;
    return NativeResult.share(prev);
}

fn native_error_clear_last(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    ctx.vm.clearLastError();
    return NativeResult.scalar(.null);
}

fn native_set_exception_handler(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // push onto stack so restore_exception_handler can pop later. PHP
    // exposes a real LIFO of installed handlers - code that inventories the
    // active handlers by repeatedly calling set then restore spins forever
    // without true pop semantics
    const prev = ctx.vm.user_exception_handler orelse Value.null;
    try ctx.vm.exception_handler_stack.append(ctx.allocator, ctx.vm.user_exception_handler);
    if (args.len > 0 and args[0] != .null) {
        VM.retainValue(args[0]);
        ctx.vm.user_exception_handler = args[0];
    } else {
        ctx.vm.user_exception_handler = null;
    }
    return NativeResult.share(prev);
}

fn native_get_error_handler(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.share(ctx.vm.user_error_handler orelse Value.null);
}

fn native_get_exception_handler(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.share(ctx.vm.user_exception_handler orelse Value.null);
}

fn native_eval(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    return NativeResult.transfer(try ctx.vm.evalSource(args[0].string.bytes()));
}

fn native_restore_exception_handler(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    if (ctx.vm.user_exception_handler) |h| ctx.vm.releaseValue(h);
    if (ctx.vm.exception_handler_stack.items.len > 0) {
        ctx.vm.user_exception_handler = ctx.vm.exception_handler_stack.pop().?;
    } else {
        ctx.vm.user_exception_handler = null;
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn native_restore_error_handler(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    if (ctx.vm.user_error_handler) |h| ctx.vm.releaseValue(h);
    if (ctx.vm.error_handler_stack.items.len > 0) {
        const entry = ctx.vm.error_handler_stack.pop().?;
        ctx.vm.user_error_handler = entry.handler;
        ctx.vm.user_error_handler_mask = entry.mask;
    } else {
        ctx.vm.user_error_handler = null;
        ctx.vm.user_error_handler_mask = -1;
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn native_assert(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = true });
    const active = ctx.vm.ini_settings.get("assert.active") orelse "1";
    if (std.mem.eql(u8, active, "0")) return NativeResult.scalar(.{ .bool = true });
    if (args[0].isTruthy()) return NativeResult.scalar(.{ .bool = true });
    // a Throwable as the 2nd arg is always thrown on failure, regardless of assert.exception
    if (args.len >= 2 and args[1] == .object) {
        ctx.vm.pending_exception = args[1];
        return error.RuntimeError;
    }
    if (ctx.vm.ini_callbacks.get("assert.callback")) |cb| {
        const file = ctx.vm.file_path;
        const line: i64 = 0;
        const expr: []const u8 = "assert(false)";
        var cb_args = [_]Value{ .{ .string = Value.String.borrowed(file) }, .{ .int = line }, .{ .string = Value.String.borrowed(expr) } };
        _ = ctx.invokeCallable(cb, &cb_args) catch {};
    }
    const ae = ctx.vm.ini_settings.get("assert.exception") orelse "0";
    if (std.mem.eql(u8, ae, "1")) {
        const msg: []const u8 = if (args.len >= 2 and args[1] == .string) args[1].string.bytes() else "assert(false)";
        try ctx.vm.setPendingException("AssertionError", msg);
        return error.RuntimeError;
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn native_noop_true(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = true });
}

fn native_assert_options(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    const opt = Value.toInt(args[0]);
    const key: []const u8 = switch (opt) {
        1 => "assert.active",
        2 => "assert.callback",
        3 => "assert.bail",
        4 => "assert.warning",
        5 => "assert.quiet_eval",
        6 => "assert.exception",
        else => return NativeResult.scalar(.{ .bool = false }),
    };

    // get previous value (defaults match PHP: ACTIVE=1, EXCEPTION=1, others=0)
    var prev: Value = .{ .int = 0 };
    if (opt == 2) {
        if (ctx.vm.ini_callbacks.get("assert.callback")) |cb| {
            prev = cb;
        }
    } else {
        const default_v: i64 = if (opt == 1 or opt == 6) 1 else 0;
        var buf: [4]u8 = undefined;
        const default_s = std.fmt.bufPrint(&buf, "{d}", .{default_v}) catch "0";
        const s = ctx.vm.ini_settings.get(key) orelse default_s;
        prev = .{ .int = std.fmt.parseInt(i64, s, 10) catch 0 };
    }

    const result = NativeResult.share(prev);
    errdefer if (result.value == .string) result.value.string.release();
    if (args.len >= 2) {
        if (opt == 2) {
            VM.retainValue(args[1]);
            if (ctx.vm.ini_callbacks.get("assert.callback")) |old| ctx.vm.releaseValue(old);
            try ctx.vm.ini_callbacks.put(ctx.allocator, "assert.callback", args[1]);
        } else {
            var buf: [32]u8 = undefined;
            const v = Value.toInt(args[1]);
            const s = std.fmt.bufPrint(&buf, "{d}", .{v}) catch return result;
            const owned = try ctx.allocator.dupe(u8, s);
            try ctx.vm.strings.append(ctx.allocator, owned);
            const key_owned = try ctx.allocator.dupe(u8, key);
            try ctx.vm.strings.append(ctx.allocator, key_owned);
            try ctx.vm.ini_settings.put(ctx.allocator, key_owned, owned);
        }
    }
    return result;
}

fn native_noop_null(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.null);
}

fn native_noop_zero(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = 0 });
}

fn native_gc_enabled(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = ctx.vm.gc_enabled });
}

fn native_gc_disable(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    ctx.vm.gc_enabled = false;
    return NativeResult.scalar(.null);
}

fn native_gc_enable(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    ctx.vm.gc_enabled = true;
    return NativeResult.scalar(.null);
}

fn native_gc_collect_cycles(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const collected = ctx.vm.collectCycles();
    return NativeResult.scalar(.{ .int = @intCast(collected) });
}

fn native_noop_false(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = false });
}

fn native_ini_get_all(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // returns an empty array - PHP returns a dict of all settings, but most
    // userland code just iterates it or queries specific keys (use ini_get)
    return NativeResult.borrowed(.{ .array = try ctx.createArray() });
}

fn native_ini_restore(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.null);
    const name = args[0].string.bytes();
    _ = ctx.vm.ini_settings.remove(name);
    if (@import("../ini_config.zig").get(name)) |configured| {
        const owned_name = try ctx.allocator.dupe(u8, name);
        try ctx.vm.strings.append(ctx.allocator, owned_name);
        try ctx.vm.ini_settings.put(ctx.allocator, owned_name, configured);
    }
    return NativeResult.scalar(.null);
}

fn native_opcache_get_status(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("opcache_enabled") }, .{ .bool = false });
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_opcache_get_configuration(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    const directives = try ctx.createArray();
    try directives.set(ctx.allocator, .{ .string = Value.String.borrowed("opcache.enable") }, .{ .bool = false });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("directives") }, .{ .array = directives });
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_gc_status(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // PHP 8.3+ adds several GC introspection keys (application_time,
    // collector_time, etc.). emit the full key set so callers that read
    // them via array access don't see undefined-index notices
    const arr = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("running") }, .{ .bool = false });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("protected") }, .{ .bool = false });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("full") }, .{ .bool = false });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("runs") }, .{ .int = @intCast(ctx.vm.gc_runs) });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("collected") }, .{ .int = @intCast(ctx.vm.gc_collected) });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("threshold") }, .{ .int = @intCast(ctx.vm.gc_threshold) });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("buffer_size") }, .{ .int = 16384 });
    const roots = ctx.vm.cycle_candidates.items.len + ctx.vm.cycle_array_candidates.items.len;
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("roots") }, .{ .int = @intCast(roots) });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("application_time") }, .{ .float = 0 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("collector_time") }, .{ .float = 0 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("destructor_time") }, .{ .float = 0 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("free_time") }, .{ .float = 0 });
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_highlight_string(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // PHP returns syntax-highlighted HTML; we return false (PHP errors on bad input
    // also return false, so this is safe as a "no-op" while still being callable)
    if (args.len >= 2 and args[1] == .bool and args[1].bool) {
        if (args.len >= 1 and args[0] == .string) return NativeResult.share(args[0]);
        return NativeResult.literal("");
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn native_highlight_file(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = true });
}

fn native_strftime(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // strftime is deprecated since 8.1; we delegate to date() with a best-effort
    // format remap for the most common specifiers
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const fmt = args[0].string.bytes();
    const ts: Value = if (args.len >= 2) args[1] else try ctx.vm.callByName("time", &.{});
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(ctx.allocator);
    var i: usize = 0;
    while (i < fmt.len) : (i += 1) {
        if (fmt[i] != '%' or i + 1 >= fmt.len) {
            try buf.append(ctx.allocator, fmt[i]);
            continue;
        }
        i += 1;
        const mapped: []const u8 = switch (fmt[i]) {
            'Y' => "Y",
            'y' => "y",
            'm' => "m",
            'd' => "d",
            'H' => "H",
            'M' => "i",
            'S' => "s",
            'p' => "A",
            'P' => "a",
            'A' => "l",
            'a' => "D",
            'B' => "F",
            'b', 'h' => "M",
            'e' => "j",
            'j' => "z",
            'n' => "\n",
            't' => "\t",
            's' => "U",
            'u' => "N",
            'w' => "w",
            'z' => "O",
            'Z' => "T",
            '%' => "%%",
            else => continue,
        };
        const r = try ctx.vm.callByName("date", &.{ .{ .string = Value.String.borrowed(mapped) }, ts });
        if (r == .string) try buf.appendSlice(ctx.allocator, r.string.bytes());
    }
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, try buf.toOwnedSlice(ctx.allocator)));
}

fn native_gmstrftime(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return native_strftime(ctx, args);
}

fn native_getmxrr(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // empty MX array, return false (no records found) - matches PHP behavior
    // when MX query fails. tools that branch on this still work.
    _ = ctx;
    return NativeResult.scalar(.{ .bool = false });
}

fn native_spl_autoload_call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    const name = args[0].string.bytes();
    var i: usize = 0;
    while (i < ctx.vm.autoload_callbacks.items.len) : (i += 1) {
        const cb = ctx.vm.autoload_callbacks.items[i];
        _ = ctx.invokeCallable(cb, &.{.{ .string = Value.String.borrowed(name) }}) catch {};
        if (ctx.vm.classes.contains(name)) break;
    }
    return NativeResult.scalar(.null);
}

fn native_spl_classes(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    const names = [_][]const u8{
        "AppendIterator",                  "ArrayIterator",              "ArrayObject",              "BadFunctionCallException",
        "BadMethodCallException",          "CachingIterator",            "CallbackFilterIterator",   "DirectoryIterator",
        "DomainException",                 "EmptyIterator",              "FilesystemIterator",       "FilterIterator",
        "GlobIterator",                    "InfiniteIterator",           "InvalidArgumentException", "IteratorIterator",
        "LengthException",                 "LimitIterator",              "LogicException",           "MultipleIterator",
        "NoRewindIterator",                "OuterIterator",              "OutOfBoundsException",     "OutOfRangeException",
        "OverflowException",               "ParentIterator",             "RangeException",           "RecursiveArrayIterator",
        "RecursiveCallbackFilterIterator", "RecursiveDirectoryIterator", "RecursiveFilterIterator",  "RecursiveIterator",
        "RecursiveIteratorIterator",       "RecursiveRegexIterator",     "RecursiveTreeIterator",    "RegexIterator",
        "RuntimeException",                "SeekableIterator",           "SplDoublyLinkedList",      "SplFileInfo",
        "SplFileObject",                   "SplFixedArray",              "SplHeap",                  "SplMinHeap",
        "SplMaxHeap",                      "SplObjectStorage",           "SplPriorityQueue",         "SplQueue",
        "SplStack",                        "SplTempFileObject",          "UnderflowException",       "UnexpectedValueException",
    };
    for (names) |n| try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(n) }, .{ .string = Value.String.borrowed(n) });
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_iconv_mime_decode(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // best-effort: return the input as-is, ignoring mime encoding
    if (args.len == 0 or args[0] != .string) return NativeResult.literal("");
    return NativeResult.share(args[0]);
}

fn native_iconv_mime_decode_headers(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    return NativeResult.borrowed(.{ .array = try ctx.createArray() });
}

fn native_iconv_mime_encode(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // best-effort: emit "Header: value" unencoded
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.share(args[1]);
}

fn native_get_include_path(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.literal(".");
}

fn native_set_include_path(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.literal(".");
}

fn native_error_reporting(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const prev = ctx.vm.error_reporting_level;
    if (args.len > 0) {
        ctx.vm.error_reporting_level = Value.toInt(args[0]);
    }
    return NativeResult.scalar(.{ .int = prev });
}

// runtime helper emitted by the compiler for match-without-default. produces
// the message body PHP's UnhandledMatchError uses:
//   int/float/bool/null  -> "Unhandled match case 99"
//   string               -> "Unhandled match case 'hello'"
//   array/object         -> "Unhandled match case of type array" / "...stdClass"
fn native_match_unhandled_msg(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const v = if (args.len > 0) args[0] else Value{ .null = {} };
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(ctx.allocator);
    try buf.appendSlice(ctx.allocator, "Unhandled match case ");
    switch (v) {
        .int => |i| try std.fmt.format(buf.writer(ctx.allocator), "{d}", .{i}),
        .float => try v.format(&buf, ctx.allocator),
        .bool => |b| try buf.appendSlice(ctx.allocator, if (b) "true" else "false"),
        .null => try buf.appendSlice(ctx.allocator, "null"),
        .string => |s| {
            // closures stored as Value.string with a __closure_ prefix are objects
            if (std.mem.startsWith(u8, s.bytes(), "__closure_")) {
                try buf.appendSlice(ctx.allocator, "of type Closure");
            } else {
                try buf.append(ctx.allocator, '\'');
                try buf.appendSlice(ctx.allocator, s.bytes());
                try buf.append(ctx.allocator, '\'');
            }
        },
        .array => try buf.appendSlice(ctx.allocator, "of type array"),
        .object => |o| {
            try buf.appendSlice(ctx.allocator, "of type ");
            try buf.appendSlice(ctx.allocator, o.class_name);
        },
        .generator => try buf.appendSlice(ctx.allocator, "of type Generator"),
        .fiber => try buf.appendSlice(ctx.allocator, "of type Fiber"),
        .resource => try buf.appendSlice(ctx.allocator, "of type resource"),
    }
    const owned = try buf.toOwnedSlice(ctx.allocator);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, owned));
}

fn native_error_log(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const message = args[0].string.bytes();
    const msg_type: i64 = if (args.len >= 2) Value.toInt(args[1]) else 0;
    switch (msg_type) {
        3 => {
            // append to the file named by arg #3
            if (args.len < 3 or args[2] != .string) return NativeResult.scalar(.{ .bool = false });
            const path = args[2].string.bytes();
            const f = std.fs.cwd().createFile(path, .{ .truncate = false }) catch return NativeResult.scalar(.{ .bool = false });
            defer f.close();
            f.seekFromEnd(0) catch {};
            f.writeAll(message) catch return NativeResult.scalar(.{ .bool = false });
            return NativeResult.scalar(.{ .bool = true });
        },
        else => {
            // type 0 (system logger) / 4 (SAPI) - PHP's CLI SAPI writes to
            // stderr with a trailing newline. flush buffered stdout first so
            // the merged stream order matches PHP's unbuffered CLI stdout
            const vm = ctx.vm;
            if (vm.output.items.len > 0) {
                const stdout_file = std.fs.File.stdout();
                _ = stdout_file.write(vm.output.items) catch {};
                vm.output.clearRetainingCapacity();
            }
            const stderr_file = std.fs.File.stderr();
            stderr_file.writeAll(message) catch return NativeResult.scalar(.{ .bool = false });
            stderr_file.writeAll("\n") catch {};
            return NativeResult.scalar(.{ .bool = true });
        },
    }
}

fn native_trigger_error(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const level: i64 = if (args.len >= 2) Value.toInt(args[1]) else 1024;
    switch (level) {
        256, 512, 1024, 16384 => {},
        else => {
            try ctx.vm.setPendingException("ValueError", "trigger_error(): Argument #2 ($error_level) must be one of E_USER_ERROR, E_USER_WARNING, E_USER_NOTICE, or E_USER_DEPRECATED");
            return error.RuntimeError;
        },
    }
    if (level == 256) try ctx.vm.raiseError(8192, "Passing E_USER_ERROR to trigger_error() is deprecated since 8.4, throw an exception or call exit with a string message instead");
    try ctx.vm.raiseError(level, args[0].string.bytes());
    return NativeResult.scalar(.{ .bool = true });
}

fn native_error_get_last(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    if (ctx.vm.last_error_type == 0) return NativeResult.scalar(.null);
    var arr = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("type") }, .{ .int = ctx.vm.last_error_type });
    const message = try Value.String.create(ctx.allocator, ctx.vm.last_error_message);
    defer message.release();
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("message") }, .{ .string = message });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("file") }, .{ .string = Value.String.borrowed(ctx.vm.last_error_file) });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("line") }, .{ .int = ctx.vm.last_error_line });
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_class_alias(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const original = args[0].string.bytes();
    const alias = args[1].string.bytes();
    const autoload = if (args.len >= 3) args[2].isTruthy() else true;
    if (autoload and !ctx.vm.classes.contains(original)) {
        try ctx.vm.tryAutoload(original);
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
        return NativeResult.scalar(.{ .bool = true });
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn native_spl_autoload_register(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    try ctx.vm.autoload_callbacks.append(ctx.allocator, args[0]);
    VM.retainValue(args[0]);
    return NativeResult.scalar(.{ .bool = true });
}

fn native_spl_autoload_functions(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    for (ctx.vm.autoload_callbacks.items) |cb| {
        try arr.append(ctx.allocator, cb);
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_spl_autoload_unregister(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    const target = args[0];
    var i: usize = 0;
    while (i < ctx.vm.autoload_callbacks.items.len) {
        const cb = ctx.vm.autoload_callbacks.items[i];
        if (callablesEqual(cb, target)) {
            ctx.vm.releaseValue(cb);
            _ = ctx.vm.autoload_callbacks.orderedRemove(i);
        } else {
            i += 1;
        }
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn callablesEqual(a: Value, b: Value) bool {
    if (a == .string and b == .string) return std.mem.eql(u8, a.string.bytes(), b.string.bytes());
    if (a == .array and b == .array) {
        const aa = a.array;
        const ba = b.array;
        if (aa.entries.items.len != ba.entries.items.len) return false;
        for (aa.entries.items, ba.entries.items) |ae, be| {
            if (ae.value == .string and be.value == .string) {
                if (!std.mem.eql(u8, ae.value.string.bytes(), be.value.string.bytes())) continue;
            } else if (ae.value == .object and be.value == .object) {
                if (ae.value.object != be.value.object) return false;
            } else return false;
        }
        return true;
    }
    if (a == .object and b == .object) return a.object == b.object;
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

fn native_func_get_args(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();

    if (ctx.vm.getFrameArgs()) |saved_args| {
        for (saved_args) |val| {
            try arr.append(ctx.allocator, val);
        }
        return NativeResult.borrowed(.{ .array = arr });
    }

    const frame = ctx.vm.currentFrame();
    const func = frame.func orelse return NativeResult.borrowed(.{ .array = arr });
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
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_func_num_args(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const frame = ctx.vm.currentFrame();
    const func = frame.func orelse return NativeResult.scalar(.{ .int = 0 });

    if (ctx.vm.getFrameArgCount()) |ac| return NativeResult.scalar(.{ .int = @intCast(ac) });

    if (func.is_variadic) {
        const fixed: usize = func.arity - 1;
        var total: i64 = @intCast(fixed);
        const slot_names = func.slot_names;
        const variadic_val = getFrameParamValue(frame, slot_names, func.params[fixed]);
        if (variadic_val == .array) {
            total += variadic_val.array.length();
        }
        return NativeResult.scalar(.{ .int = total });
    }
    return NativeResult.scalar(.{ .int = @intCast(func.arity) });
}

fn native_func_get_arg(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    const idx = Value.toInt(args[0]);
    if (idx < 0) return NativeResult.scalar(.{ .bool = false });
    const index: usize = @intCast(idx);

    if (ctx.vm.getFrameArgs()) |saved_args| {
        if (index < saved_args.len) return NativeResult.share(saved_args[index]);
        return NativeResult.scalar(.{ .bool = false });
    }

    const frame = ctx.vm.currentFrame();
    const func = frame.func orelse return NativeResult.scalar(.{ .bool = false });
    const slot_names = func.slot_names;

    if (func.is_variadic) {
        const fixed: usize = func.arity - 1;
        if (index < fixed) {
            return NativeResult.share(getFrameParamValue(frame, slot_names, func.params[index]));
        }
        const variadic_val = getFrameParamValue(frame, slot_names, func.params[fixed]);
        if (variadic_val == .array) {
            const vi: i64 = @intCast(index - fixed);
            const result = variadic_val.array.get(.{ .int = vi });
            if (result != .null) return NativeResult.share(result);
        }
        return NativeResult.scalar(.{ .bool = false });
    }

    if (index >= func.arity) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.share(getFrameParamValue(frame, slot_names, func.params[index]));
}

fn native_interface_exists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const raw = args[0].string.bytes();
    const name = if (raw.len > 0 and raw[0] == '\\') raw[1..] else raw;
    if (ctx.vm.interfaces.contains(name)) return NativeResult.scalar(.{ .bool = true });
    const autoload = if (args.len > 1 and args[1] == .bool) args[1].bool else true;
    if (autoload) {
        try ctx.vm.tryAutoload(name);
        return NativeResult.scalar(.{ .bool = ctx.vm.interfaces.contains(name) });
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn native_enum_exists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const name = args[0].string.bytes();
    if (ctx.vm.classes.get(name)) |cls| {
        if (cls.is_enum) return NativeResult.scalar(.{ .bool = true });
    }
    const autoload = if (args.len > 1 and args[1] == .bool) args[1].bool else true;
    if (autoload) {
        try ctx.vm.tryAutoload(name);
        if (ctx.vm.classes.get(name)) |cls| {
            return NativeResult.scalar(.{ .bool = cls.is_enum });
        }
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn native_class_implements(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    const raw = if (args[0] == .object)
        args[0].object.class_name
    else if (args[0] == .string)
        args[0].string.bytes()
    else
        return NativeResult.scalar(Value{ .bool = false });
    const class_name = if (raw.len > 0 and raw[0] == '\\') raw[1..] else raw;

    const cls = ctx.vm.classes.get(class_name);
    const interface = ctx.vm.interfaces.get(class_name);
    if (cls == null and interface == null and !ctx.vm.traits.contains(class_name)) return NativeResult.scalar(.{ .bool = false });

    var result = try ctx.createArray();
    var queue = std.ArrayListUnmanaged([]const u8){};
    defer queue.deinit(ctx.allocator);
    if (interface) |def| {
        for (def.parents.items) |parent| try queue.append(ctx.allocator, parent);
        if (def.parents.items.len == 0) {
            if (def.parent) |parent| try queue.append(ctx.allocator, parent);
        }
    }
    // PHP enumerates direct interfaces in declaration order, but interfaces
    // reached via parent traversal in REVERSE declaration order. mimic both
    if (cls) |def| {
        for (def.interfaces.items) |iface| try queue.append(ctx.allocator, iface);
    }

    var parent = if (cls) |def| def.parent else null;
    while (parent) |p| {
        const pcls = ctx.vm.classes.get(p) orelse break;
        var pi = pcls.interfaces.items.len;
        while (pi > 0) {
            pi -= 1;
            try queue.append(ctx.allocator, pcls.interfaces.items[pi]);
        }
        parent = pcls.parent;
    }

    var i: usize = 0;
    while (i < queue.items.len) : (i += 1) {
        const iface = queue.items[i];
        if (result.get(.{ .string = Value.String.borrowed(iface) }) != .null) continue;
        try result.set(ctx.allocator, .{ .string = Value.String.borrowed(iface) }, .{ .string = Value.String.borrowed(iface) });
        if (!ctx.vm.interfaces.contains(iface)) {
            if (ctx.vm.classes.get(iface)) |idef| {
                for (idef.interfaces.items) |sub| try queue.append(ctx.allocator, sub);
            }
        }
        if (ctx.vm.interfaces.get(iface)) |idef| {
            if (idef.parents.items.len == 0) {
                if (idef.parent) |p| try queue.append(ctx.allocator, p);
            }
            var pi = idef.parents.items.len;
            while (pi > 0) {
                pi -= 1;
                try queue.append(ctx.allocator, idef.parents.items[pi]);
            }
        }
    }

    return NativeResult.borrowed(.{ .array = result });
}

fn native_class_parents(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    const raw = if (args[0] == .object)
        args[0].object.class_name
    else if (args[0] == .string)
        args[0].string.bytes()
    else
        return NativeResult.scalar(Value{ .bool = false });
    const class_name = if (raw.len > 0 and raw[0] == '\\') raw[1..] else raw;

    // an interface has no parent classes
    if (ctx.vm.interfaces.contains(class_name)) return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const cls = ctx.vm.classes.get(class_name) orelse {
        try ctx.vm.tryAutoload(class_name);
        if (ctx.vm.classes.get(class_name) == null and !ctx.vm.interfaces.contains(class_name)) return NativeResult.scalar(Value{ .bool = false });
        const normalized = [_]Value{.{ .string = Value.String.borrowed(class_name) }};
        return native_class_parents(ctx, &normalized);
    };

    var result = try ctx.createArray();
    var parent = cls.parent;
    while (parent) |p| {
        try result.set(ctx.allocator, .{ .string = Value.String.borrowed(p) }, .{ .string = Value.String.borrowed(p) });
        const pcls = ctx.vm.classes.get(p) orelse break;
        parent = pcls.parent;
    }

    return NativeResult.borrowed(.{ .array = result });
}

fn native_class_uses(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    const raw = if (args[0] == .object)
        args[0].object.class_name
    else if (args[0] == .string)
        args[0].string.bytes()
    else
        return NativeResult.scalar(Value{ .bool = false });
    const class_name = if (raw.len > 0 and raw[0] == '\\') raw[1..] else raw;

    if (!ctx.vm.classes.contains(class_name) and !ctx.vm.traits.contains(class_name) and !ctx.vm.interfaces.contains(class_name)) {
        if (args.len < 2 or args[1].isTruthy()) try ctx.vm.tryAutoload(class_name);
        if (!ctx.vm.classes.contains(class_name) and !ctx.vm.traits.contains(class_name) and !ctx.vm.interfaces.contains(class_name)) return NativeResult.scalar(.{ .bool = false });
    }
    const used_traits = if (ctx.vm.classes.get(class_name)) |cls|
        cls.used_traits.items
    else
        ctx.vm.trait_uses.get(class_name) orelse &.{};

    var result = try ctx.createArray();
    for (used_traits) |trait| {
        try result.set(ctx.allocator, .{ .string = Value.String.borrowed(trait) }, .{ .string = Value.String.borrowed(trait) });
    }
    return NativeResult.borrowed(.{ .array = result });
}

fn native_iterator_to_array(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.borrowed(.{ .array = try ctx.createArray() });

    if (args[0] == .array) return NativeResult.borrowed(args[0]);
    const preserve_keys = if (args.len > 1 and args[1] == .bool) args[1].bool else true;

    if (args[0] == .generator) {
        const gen = args[0].generator;
        const arr = try ctx.createArray();

        if (gen.state == .created) try ctx.vm.resumeGenerator(gen, .null);

        while (gen.state != .completed) {
            if (preserve_keys) {
                try ctx.vm.arraySetOwned(arr, switch (gen.current_key) {
                    .int => |i| .{ .int = i },
                    .string => |s| .{ .string = s },
                    else => .{ .int = arr.length() },
                }, gen.current_value);
            } else {
                try arr.append(ctx.allocator, gen.current_value);
            }
            try ctx.vm.resumeGenerator(gen, .null);
        }
        return NativeResult.borrowed(.{ .array = arr });
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
            if (args.len > 1) {
                inner_args[1] = args[1];
                n = 2;
            }
            return native_iterator_to_array(ctx, inner_args[0..n]);
        }
        const has_traversal = ctx.vm.hasMethod(obj.class_name, "rewind") and ctx.vm.hasMethod(obj.class_name, "valid") and ctx.vm.hasMethod(obj.class_name, "current");
        if (!is_iterator and !has_traversal) return NativeResult.borrowed(.{ .array = arr });
        if (!ctx.vm.hasMethod(obj.class_name, "rewind")) return NativeResult.borrowed(.{ .array = arr });
        _ = try ctx.vm.callMethod(obj, "rewind", &.{});
        var valid_v = try ctx.vm.callMethod(obj, "valid", &.{});
        while (valid_v.isTruthy()) {
            const cur = try ctx.vm.callMethod(obj, "current", &.{});
            if (cur == .string) cur.string.retain();
            defer if (cur == .string) cur.string.release();
            if (preserve_keys) {
                const key = try ctx.vm.callMethod(obj, "key", &.{});
                try ctx.vm.arraySetOwned(arr, switch (key) {
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
        return NativeResult.borrowed(.{ .array = arr });
    }

    return NativeResult.borrowed(.{ .array = try ctx.createArray() });
}

fn native_iterator_count(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .int = 0 });

    if (args[0] == .array) return NativeResult.scalar(.{ .int = args[0].array.length() });

    if (args[0] == .generator) {
        const gen = args[0].generator;
        var n: i64 = 0;

        if (gen.state == .created) try ctx.vm.resumeGenerator(gen, .null);

        while (gen.state != .completed) {
            n += 1;
            try ctx.vm.resumeGenerator(gen, .null);
        }
        return NativeResult.scalar(.{ .int = n });
    }

    if (args[0] == .object) {
        var obj = args[0].object;
        if (ctx.vm.hasMethod(obj.class_name, "getIterator")) {
            const inner = try ctx.vm.callMethod(obj, "getIterator", &.{});
            if (inner == .object) obj = inner.object;
            if (inner == .generator) {
                const gen = inner.generator;
                var n: i64 = 0;
                if (gen.state == .created) try ctx.vm.resumeGenerator(gen, .null);
                while (gen.state != .completed) {
                    n += 1;
                    try ctx.vm.resumeGenerator(gen, .null);
                }
                return NativeResult.scalar(.{ .int = n });
            }
        }
        if (!ctx.vm.hasMethod(obj.class_name, "rewind")) return NativeResult.scalar(.{ .int = 0 });
        _ = try ctx.vm.callMethod(obj, "rewind", &.{});
        var n: i64 = 0;
        while (true) {
            const valid = try ctx.vm.callMethod(obj, "valid", &.{});
            if (!valid.isTruthy()) break;
            n += 1;
            _ = try ctx.vm.callMethod(obj, "next", &.{});
        }
        return NativeResult.scalar(.{ .int = n });
    }

    return NativeResult.scalar(.{ .int = 0 });
}

fn native_iterator_apply(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.scalar(.{ .int = 0 });

    var tmp_buf: ?[]Value = null;
    defer if (tmp_buf) |b| ctx.allocator.free(b);
    var call_args: []const Value = &.{};
    if (args.len >= 3 and args[2] == .array) {
        const arr = args[2].array;
        const tmp = try ctx.allocator.alloc(Value, arr.entries.items.len);
        for (arr.entries.items, 0..) |entry, i| tmp[i] = entry.value;
        tmp_buf = tmp;
        call_args = tmp;
    }

    if (args[0] == .generator) {
        const gen = args[0].generator;
        if (gen.state == .created) try ctx.vm.resumeGenerator(gen, .null);
        var n: i64 = 0;
        while (gen.state != .completed) {
            const r = try ctx.invokeCallable(args[1], call_args);
            n += 1;
            if (!r.isTruthy()) break;
            try ctx.vm.resumeGenerator(gen, .null);
        }
        return NativeResult.scalar(.{ .int = n });
    }

    if (args[0] == .array) {
        var n: i64 = 0;
        for (args[0].array.entries.items) |_| {
            const r = try ctx.invokeCallable(args[1], call_args);
            n += 1;
            if (!r.isTruthy()) break;
        }
        return NativeResult.scalar(.{ .int = n });
    }

    if (args[0] == .object) {
        const obj = args[0].object;
        // try IteratorAggregate first
        if (ctx.vm.hasMethod(obj.class_name, "getIterator")) {
            const inner = try ctx.vm.callMethod(obj, "getIterator", &.{});
            if (inner == .object) {
                const inner_args = [_]Value{args[1]} ++ .{};
                _ = inner_args;
                const new_args: [3]Value = .{ inner, args[1], if (args.len >= 3) args[2] else Value.null };
                return native_iterator_apply(ctx, new_args[0..if (args.len >= 3) 3 else 2]);
            }
            if (inner == .generator) {
                const new_args: [3]Value = .{ inner, args[1], if (args.len >= 3) args[2] else Value.null };
                return native_iterator_apply(ctx, new_args[0..if (args.len >= 3) 3 else 2]);
            }
        }
        // Iterator protocol
        if (ctx.vm.hasMethod(obj.class_name, "rewind")) {
            _ = try ctx.vm.callMethod(obj, "rewind", &.{});
            var n: i64 = 0;
            while (true) {
                const valid = try ctx.vm.callMethod(obj, "valid", &.{});
                if (!valid.isTruthy()) break;
                const r = try ctx.invokeCallable(args[1], call_args);
                n += 1;
                if (!r.isTruthy()) break;
                _ = try ctx.vm.callMethod(obj, "next", &.{});
            }
            return NativeResult.scalar(.{ .int = n });
        }
    }

    return NativeResult.scalar(.{ .int = 0 });
}

fn native_filter_id(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const name = args[0].string.bytes();
    // PHP's filter_id maps a filter name to its numeric ID (matches the
    // FILTER_VALIDATE_*/FILTER_SANITIZE_* / FILTER_DEFAULT constants)
    const Pair = struct { name: []const u8, id: i64 };
    const filters = [_]Pair{
        .{ .name = "int", .id = 257 },
        .{ .name = "boolean", .id = 258 },
        .{ .name = "float", .id = 259 },
        .{ .name = "validate_regexp", .id = 272 },
        .{ .name = "validate_domain", .id = 277 },
        .{ .name = "validate_url", .id = 273 },
        .{ .name = "validate_email", .id = 274 },
        .{ .name = "validate_ip", .id = 275 },
        .{ .name = "validate_mac", .id = 276 },
        .{ .name = "string", .id = 262 },
        .{ .name = "stripped", .id = 513 },
        .{ .name = "encoded", .id = 514 },
        .{ .name = "special_chars", .id = 515 },
        .{ .name = "full_special_chars", .id = 522 },
        .{ .name = "unsafe_raw", .id = 516 },
        .{ .name = "email", .id = 517 },
        .{ .name = "url", .id = 518 },
        .{ .name = "number_int", .id = 519 },
        .{ .name = "number_float", .id = 520 },
        .{ .name = "add_slashes", .id = 523 },
        .{ .name = "unsafe_html", .id = 521 },
        .{ .name = "callback", .id = 1024 },
    };
    for (filters) |f| if (std.mem.eql(u8, f.name, name)) return NativeResult.scalar(.{ .int = f.id });
    return NativeResult.scalar(.{ .bool = false });
}

fn native_filter_list(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    const names = [_][]const u8{
        "int",          "boolean",        "float",         "validate_regexp",    "validate_domain",
        "validate_url", "validate_email", "validate_ip",   "validate_mac",       "string",
        "stripped",     "encoded",        "special_chars", "full_special_chars", "unsafe_raw",
        "email",        "url",            "number_int",    "number_float",       "add_slashes",
        "callback",
    };
    var i: usize = 0;
    while (i < names.len) : (i += 1) {
        try arr.set(ctx.allocator, .{ .int = @intCast(i) }, .{ .string = Value.String.borrowed(names[i]) });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_filter_has_var(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // filter_has_var inspects INPUT_* superglobals which zphp populates per
    // request. for the CLI / generic context, returning false is the safest
    // PHP-compatible answer
    return NativeResult.scalar(.{ .bool = false });
}

fn native_filter_input(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // CLI / no-request context: no INPUT_* values to read, return null
    return NativeResult.scalar(.null);
}

fn native_filter_input_array(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.null);
}

fn native_filter_var_array(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .array) return NativeResult.scalar(.{ .bool = false });
    const data = args[0].array;
    const result = try ctx.createArray();
    if (args.len < 2 or args[1] != .array) {
        for (data.entries.items) |entry| try result.set(ctx.allocator, entry.key, entry.value);
        return NativeResult.borrowed(.{ .array = result });
    }
    const rules = args[1].array;
    for (rules.entries.items) |rule_entry| {
        const key = rule_entry.key;
        const data_v = data.get(key);
        const sub_args = [_]Value{ data_v, rule_entry.value };
        const filtered = try native_filter_var(ctx, &sub_args);
        defer if (filtered.value == .string) filtered.value.string.release();
        try result.set(ctx.allocator, key, filtered.value);
    }
    return NativeResult.borrowed(.{ .array = result });
}

// validates the integer part of a thousands-separated number: an optional
// sign, then \d{1,3}(,\d{3})* - and no ',' anywhere after the decimal point
fn validThousandGrouping(s: []const u8) bool {
    var i: usize = 0;
    if (i < s.len and (s[i] == '+' or s[i] == '-')) i += 1;
    var int_end = i;
    while (int_end < s.len and s[int_end] != '.' and s[int_end] != 'e' and s[int_end] != 'E') int_end += 1;
    const int_part = s[i..int_end];
    if (int_part.len == 0) return false;
    var first = true;
    var it = std.mem.splitScalar(u8, int_part, ',');
    while (it.next()) |group| {
        if (group.len == 0) return false;
        for (group) |c| if (!std.ascii.isDigit(c)) return false;
        if (first) {
            if (group.len > 3) return false;
            first = false;
        } else {
            if (group.len != 3) return false;
        }
    }
    if (int_end < s.len) {
        for (s[int_end..]) |c| if (c == ',') return false;
    }
    return true;
}

fn native_filter_var(_ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1) return NativeResult.scalar(.{ .bool = false });
    const value = args[0];

    if (args.len < 2) return NativeResult.share(value);

    const filter = if (args[1] == .int) args[1].int else return NativeResult.scalar(.{ .bool = false });
    const flags: i64 = if (args.len > 2 and args[2] == .int) args[2].int else 0;

    // resolve options array if 3rd arg is array: ["options" => [...], "flags" => ...]
    var opts_arr: ?*PhpArray = null;
    var opt_flags: i64 = 0;
    var default_val: ?Value = null;
    if (args.len > 2 and args[2] == .array) {
        const top = args[2].array;
        const fl = top.get(.{ .string = Value.String.borrowed("flags") });
        if (fl == .int) opt_flags = fl.int;
        const o = top.get(.{ .string = Value.String.borrowed("options") });
        if (o == .array) {
            opts_arr = o.array;
            const dv = o.array.get(.{ .string = Value.String.borrowed("default") });
            if (dv != .null) default_val = dv;
        }
    }
    const eff_flags = flags | opt_flags;
    const fail_default = default_val orelse Value{ .bool = false };

    // FILTER_REQUIRE_ARRAY (0x1000000): input must be an array; apply filter
    // to each element and return an array. FILTER_FORCE_ARRAY (0x2000000):
    // wrap scalar in single-element array, then apply per-element
    const require_array = (eff_flags & 0x01000000) != 0; // FILTER_REQUIRE_ARRAY
    const force_array = (eff_flags & 0x04000000) != 0; // FILTER_FORCE_ARRAY
    if (require_array or force_array) {
        if (value != .array) {
            if (require_array) return NativeResult.share(fail_default);
            // force_array wraps scalar
            const out = try _ctx.createArray();
            const single_flags = eff_flags & ~@as(i64, 0x05000000);
            const sub_args = [_]Value{ value, args[1], .{ .int = single_flags } };
            const filtered = try native_filter_var(_ctx, &sub_args);
            defer if (filtered.value == .string) filtered.value.string.release();
            try out.append(_ctx.allocator, filtered.value);
            return NativeResult.borrowed(.{ .array = out });
        }
        const out = try _ctx.createArray();
        const single_flags = eff_flags & ~@as(i64, 0x05000000);
        for (value.array.entries.items) |e| {
            const sub_args = [_]Value{ e.value, args[1], .{ .int = single_flags } };
            const filtered = try native_filter_var(_ctx, &sub_args);
            defer if (filtered.value == .string) filtered.value.string.release();
            try out.set(_ctx.allocator, switch (e.key) {
                .int => |i| .{ .int = i },
                .string => |s| .{ .string = s },
            }, filtered.value);
        }
        return NativeResult.borrowed(.{ .array = out });
    }

    switch (filter) {
        275 => { // FILTER_VALIDATE_IP
            const s = if (value == .string) value.string.bytes() else return NativeResult.scalar(.{ .bool = false });
            const ipv4_only = (flags & 1048576) != 0;
            const ipv6_only = (flags & 2097152) != 0;
            const no_priv = (flags & 8388608) != 0;
            const no_res = (flags & 4194304) != 0;
            if (!ipv6_only and isValidIPv4(s)) {
                if (no_priv and isPrivateIPv4(s)) return NativeResult.scalar(.{ .bool = false });
                if (no_res and isReservedIPv4(s)) return NativeResult.scalar(.{ .bool = false });
                return NativeResult.share(value);
            }
            if (ipv4_only) return NativeResult.scalar(.{ .bool = false });
            if (!ipv4_only and isValidIPv6(s)) return NativeResult.share(value);
            return NativeResult.scalar(.{ .bool = false });
        },
        274 => { // FILTER_VALIDATE_EMAIL
            const s = if (value == .string) value.string.bytes() else return NativeResult.scalar(.{ .bool = false });
            if (std.mem.indexOf(u8, s, "@")) |at| {
                if (at > 0 and at < s.len - 1 and std.mem.indexOf(u8, s[at + 1 ..], ".") != null) return NativeResult.share(value);
            }
            return NativeResult.scalar(.{ .bool = false });
        },
        273 => { // FILTER_VALIDATE_URL
            const s = if (value == .string) value.string.bytes() else return NativeResult.scalar(.{ .bool = false });
            if (std.mem.startsWith(u8, s, "http://") or std.mem.startsWith(u8, s, "https://") or std.mem.startsWith(u8, s, "ftp://")) return NativeResult.share(value);
            return NativeResult.scalar(.{ .bool = false });
        },
        257 => { // FILTER_VALIDATE_INT
            const allow_octal = (eff_flags & 1) != 0; // FILTER_FLAG_ALLOW_OCTAL
            const allow_hex = (eff_flags & 2) != 0; // FILTER_FLAG_ALLOW_HEX
            var str_buf = std.ArrayListUnmanaged(u8){};
            defer str_buf.deinit(_ctx.allocator);
            const n: i64 = blk: {
                if (value == .int) break :blk value.int;
                // PHP stringifies a non-string scalar then applies the string
                // filter: true->"1"->1, false->""->fail, 3.0->"3"->3, 3.7->fail
                const s: []const u8 = if (value == .string) value.string.bytes() else sblk: {
                    if (value == .bool or value == .float) {
                        value.format(&str_buf, _ctx.allocator) catch return NativeResult.share(fail_default);
                        break :sblk str_buf.items;
                    }
                    return NativeResult.share(fail_default);
                };
                const trimmed = std.mem.trim(u8, s, " \t\n\r");
                if (trimmed.len == 0) return NativeResult.share(fail_default);
                // optional sign
                var rest = trimmed;
                var sign: i64 = 1;
                if (rest[0] == '+') {
                    rest = rest[1..];
                } else if (rest[0] == '-') {
                    sign = -1;
                    rest = rest[1..];
                }
                if (rest.len == 0) return NativeResult.share(fail_default);
                // hex with ALLOW_HEX
                if (allow_hex and rest.len > 2 and rest[0] == '0' and (rest[1] == 'x' or rest[1] == 'X')) {
                    const v = std.fmt.parseInt(i64, rest[2..], 16) catch return NativeResult.share(fail_default);
                    break :blk sign * v;
                }
                // octal with ALLOW_OCTAL, "0o" prefix
                if (allow_octal and rest.len > 2 and rest[0] == '0' and (rest[1] == 'o' or rest[1] == 'O')) {
                    const v = std.fmt.parseInt(i64, rest[2..], 8) catch return NativeResult.share(fail_default);
                    break :blk sign * v;
                }
                // octal with ALLOW_OCTAL ("0" prefix)
                if (allow_octal and rest.len > 1 and rest[0] == '0' and std.ascii.isDigit(rest[1])) {
                    const v = std.fmt.parseInt(i64, rest[1..], 8) catch return NativeResult.share(fail_default);
                    break :blk sign * v;
                }
                // default: decimal, reject leading-zero ints (except plain "0")
                if (rest.len > 1 and rest[0] == '0') return NativeResult.share(fail_default);
                if (!std.ascii.isDigit(rest[0])) return NativeResult.share(fail_default);
                const parsed = std.fmt.parseInt(i64, rest, 10) catch return NativeResult.share(fail_default);
                break :blk sign * parsed;
            };
            if (opts_arr) |opts| {
                const min_v = opts.get(.{ .string = Value.String.borrowed("min_range") });
                if (min_v != .null and n < Value.toInt(min_v)) return NativeResult.share(fail_default);
                const max_v = opts.get(.{ .string = Value.String.borrowed("max_range") });
                if (max_v != .null and n > Value.toInt(max_v)) return NativeResult.share(fail_default);
            }
            return NativeResult.scalar(.{ .int = n });
        },
        259 => { // FILTER_VALIDATE_FLOAT
            if (value == .float or value == .int) return NativeResult.share(value);
            const s = if (value == .string) value.string.bytes() else return NativeResult.scalar(.{ .bool = false });
            const trimmed = std.mem.trim(u8, s, " ");
            var parse_src: []const u8 = trimmed;
            var cleaned = std.ArrayListUnmanaged(u8){};
            defer cleaned.deinit(_ctx.allocator);
            if (std.mem.indexOfScalar(u8, trimmed, ',') != null) {
                // a ',' is only valid with FILTER_FLAG_ALLOW_THOUSAND, and only
                // as a \d{1,3}(,\d{3})* grouping in the integer part
                if ((eff_flags & 8192) == 0) return NativeResult.scalar(.{ .bool = false });
                if (!validThousandGrouping(trimmed)) return NativeResult.scalar(.{ .bool = false });
                for (trimmed) |c| {
                    if (c != ',') cleaned.append(_ctx.allocator, c) catch return NativeResult.scalar(.{ .bool = false });
                }
                parse_src = cleaned.items;
            }
            const f = std.fmt.parseFloat(f64, parse_src) catch return NativeResult.scalar(.{ .bool = false });
            return NativeResult.scalar(.{ .float = f });
        },
        258 => { // FILTER_VALIDATE_BOOLEAN
            const null_on_fail = (eff_flags & 134217728) != 0; // FILTER_NULL_ON_FAILURE
            const fail_val: Value = if (null_on_fail) .null else .{ .bool = false };
            if (value == .bool) return NativeResult.share(value);
            if (value == .int) return NativeResult.scalar(.{ .bool = value.int != 0 });
            const s = if (value == .string) value.string.bytes() else return NativeResult.share(fail_val);
            if (std.mem.eql(u8, s, "true") or std.mem.eql(u8, s, "1") or std.mem.eql(u8, s, "yes") or std.mem.eql(u8, s, "on")) return NativeResult.scalar(.{ .bool = true });
            if (std.mem.eql(u8, s, "false") or std.mem.eql(u8, s, "0") or std.mem.eql(u8, s, "no") or std.mem.eql(u8, s, "off")) return NativeResult.scalar(.{ .bool = false });
            return NativeResult.share(fail_val);
        },
        272 => { // FILTER_VALIDATE_REGEXP
            const s = if (value == .string) value.string.bytes() else if (value == .int) (try _ctx.createString(blk: {
                var b: [32]u8 = undefined;
                break :blk std.fmt.bufPrint(&b, "{d}", .{value.int}) catch "";
            })) else return NativeResult.share(fail_default);
            if (opts_arr) |opts| {
                const re_v = opts.get(.{ .string = Value.String.borrowed("regexp") });
                if (re_v == .string) {
                    const r = _ctx.vm.callByName("preg_match", &.{ re_v, .{ .string = Value.String.borrowed(s) } }) catch return NativeResult.share(fail_default);
                    if (r == .int and r.int > 0) return NativeResult.share(value);
                }
            }
            return NativeResult.share(fail_default);
        },
        277 => { // FILTER_VALIDATE_DOMAIN
            const s = if (value == .string) value.string.bytes() else return NativeResult.share(fail_default);
            if (s.len == 0 or s.len > 253) return NativeResult.share(fail_default);
            const strict = (eff_flags & 1048576) != 0; // FILTER_FLAG_HOSTNAME
            if (strict) {
                for (s) |c| {
                    if (!std.ascii.isAlphanumeric(c) and c != '.' and c != '-') return NativeResult.share(fail_default);
                }
            }
            return NativeResult.share(value);
        },
        276 => { // FILTER_VALIDATE_MAC
            const s = if (value == .string) value.string.bytes() else return NativeResult.share(fail_default);
            // colon: 6 hex pairs separated by ":" or "-", or 3 quads of 4 hex separated by "."
            const HexHelpers = struct {
                fn isHex(c: u8) bool {
                    return std.ascii.isHex(c);
                }
            };
            const parts_colon: usize = std.mem.count(u8, s, ":") + 1;
            const parts_dash: usize = std.mem.count(u8, s, "-") + 1;
            const parts_dot: usize = std.mem.count(u8, s, ".") + 1;
            if (parts_colon == 6 or parts_dash == 6) {
                const sep: u8 = if (parts_colon == 6) ':' else '-';
                var it = std.mem.splitScalar(u8, s, sep);
                var n: usize = 0;
                while (it.next()) |p| {
                    if (p.len != 2) return NativeResult.share(fail_default);
                    if (!HexHelpers.isHex(p[0]) or !HexHelpers.isHex(p[1])) return NativeResult.share(fail_default);
                    n += 1;
                }
                if (n == 6) return NativeResult.share(value);
                return NativeResult.share(fail_default);
            }
            if (parts_dot == 3) {
                var it = std.mem.splitScalar(u8, s, '.');
                var n: usize = 0;
                while (it.next()) |p| {
                    if (p.len != 4) return NativeResult.share(fail_default);
                    for (p) |c| if (!HexHelpers.isHex(c)) return NativeResult.share(fail_default);
                    n += 1;
                }
                if (n == 3) return NativeResult.share(value);
            }
            return NativeResult.share(fail_default);
        },
        519 => { // FILTER_SANITIZE_NUMBER_INT
            const s = if (value == .string) value.string.bytes() else return NativeResult.share(fail_default);
            var buf = std.ArrayListUnmanaged(u8){};
            defer buf.deinit(_ctx.allocator);
            for (s) |c| {
                if (std.ascii.isDigit(c) or c == '+' or c == '-') try buf.append(_ctx.allocator, c);
            }
            const out = try buf.toOwnedSlice(_ctx.allocator);
            return NativeResult.takeString(try Value.String.adopt(_ctx.allocator, out));
        },
        520 => { // FILTER_SANITIZE_NUMBER_FLOAT
            const s = if (value == .string) value.string.bytes() else return NativeResult.share(fail_default);
            const allow_frac = (eff_flags & 4096) != 0;
            const allow_thou = (eff_flags & 8192) != 0;
            const allow_sci = (eff_flags & 16384) != 0;
            var buf = std.ArrayListUnmanaged(u8){};
            defer buf.deinit(_ctx.allocator);
            for (s) |c| {
                if (std.ascii.isDigit(c) or c == '+' or c == '-') {
                    try buf.append(_ctx.allocator, c);
                } else if (c == '.' and allow_frac) {
                    try buf.append(_ctx.allocator, c);
                } else if (c == ',' and allow_thou) {
                    try buf.append(_ctx.allocator, c);
                } else if ((c == 'e' or c == 'E') and allow_sci) {
                    try buf.append(_ctx.allocator, c);
                }
            }
            const out = try buf.toOwnedSlice(_ctx.allocator);
            return NativeResult.takeString(try Value.String.adopt(_ctx.allocator, out));
        },
        515 => { // FILTER_SANITIZE_SPECIAL_CHARS
            const s = if (value == .string) value.string.bytes() else return NativeResult.scalar(.{ .bool = false });
            return NativeResult.takeString(try sanitizeSpecialChars(_ctx, s));
        },
        522 => { // FILTER_SANITIZE_FULL_SPECIAL_CHARS
            const s = if (value == .string) value.string.bytes() else return NativeResult.scalar(.{ .bool = false });
            var buf = std.ArrayListUnmanaged(u8){};
            defer buf.deinit(_ctx.allocator);
            for (s) |c| {
                switch (c) {
                    '<' => try buf.appendSlice(_ctx.allocator, "&lt;"),
                    '>' => try buf.appendSlice(_ctx.allocator, "&gt;"),
                    '&' => try buf.appendSlice(_ctx.allocator, "&amp;"),
                    '"' => try buf.appendSlice(_ctx.allocator, "&quot;"),
                    '\'' => try buf.appendSlice(_ctx.allocator, "&#039;"),
                    else => try buf.append(_ctx.allocator, c),
                }
            }
            const out = try buf.toOwnedSlice(_ctx.allocator);
            return NativeResult.takeString(try Value.String.adopt(_ctx.allocator, out));
        },
        518 => { // FILTER_SANITIZE_URL
            const s = if (value == .string) value.string.bytes() else return NativeResult.scalar(.{ .bool = false });
            var buf = std.ArrayListUnmanaged(u8){};
            defer buf.deinit(_ctx.allocator);
            for (s) |c| {
                // PHP strips all chars except a-zA-Z0-9 and the URL-reserved set
                if (std.ascii.isAlphanumeric(c)) {
                    try buf.append(_ctx.allocator, c);
                    continue;
                }
                switch (c) {
                    '$', '-', '_', '.', '+', '!', '*', '\'', '(', ')', ',', '{', '}', '|', '\\', '^', '~', '[', ']', '`', '<', '>', '#', '%', '"', ';', '/', '?', ':', '@', '&', '=' => try buf.append(_ctx.allocator, c),
                    else => {},
                }
            }
            const out = try buf.toOwnedSlice(_ctx.allocator);
            return NativeResult.takeString(try Value.String.adopt(_ctx.allocator, out));
        },
        517 => { // FILTER_SANITIZE_EMAIL
            const s = if (value == .string) value.string.bytes() else return NativeResult.scalar(.{ .bool = false });
            var buf = std.ArrayListUnmanaged(u8){};
            defer buf.deinit(_ctx.allocator);
            for (s) |c| {
                if (std.ascii.isAlphanumeric(c) or c == '@' or c == '.' or c == '!' or c == '#' or
                    c == '$' or c == '%' or c == '&' or c == '\'' or c == '*' or c == '+' or
                    c == '-' or c == '/' or c == '=' or c == '?' or c == '^' or c == '_' or
                    c == '`' or c == '{' or c == '|' or c == '}' or c == '~' or c == '[' or c == ']')
                {
                    try buf.append(_ctx.allocator, c);
                }
            }
            const out = try buf.toOwnedSlice(_ctx.allocator);
            return NativeResult.takeString(try Value.String.adopt(_ctx.allocator, out));
        },
        1024 => { // FILTER_CALLBACK
            // options is the callable; PHP invokes it with the value and uses
            // the return as the result. unlike other filters, FILTER_CALLBACK
            // doesn't have a fail_default fallback - the callback's return is
            // what comes back (even if null/false)
            if (args.len > 2 and args[2] == .array) {
                const top = args[2].array;
                const o = top.get(.{ .string = Value.String.borrowed("options") });
                if (o != .null) {
                    return NativeResult.share(_ctx.invokeCallable(o, &.{value}) catch return NativeResult.scalar(.{ .bool = false }));
                }
            }
            return NativeResult.scalar(.{ .bool = false });
        },
        else => return NativeResult.share(value),
    }
}

fn sanitizeSpecialChars(ctx: *NativeContext, s: []const u8) !Value.String {
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(ctx.allocator);
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
    return Value.String.adopt(ctx.allocator, out);
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

fn parseIPv4Octets(s: []const u8) ?[4]u8 {
    var out: [4]u8 = .{ 0, 0, 0, 0 };
    var it = std.mem.splitScalar(u8, s, '.');
    var i: usize = 0;
    while (it.next()) |part| : (i += 1) {
        if (i >= 4) return null;
        const n = std.fmt.parseInt(u16, part, 10) catch return null;
        if (n > 255) return null;
        out[i] = @intCast(n);
    }
    if (i != 4) return null;
    return out;
}

fn isPrivateIPv4(s: []const u8) bool {
    const o = parseIPv4Octets(s) orelse return false;
    if (o[0] == 10) return true;
    if (o[0] == 172 and o[1] >= 16 and o[1] <= 31) return true;
    if (o[0] == 192 and o[1] == 168) return true;
    return false;
}

fn isReservedIPv4(s: []const u8) bool {
    const o = parseIPv4Octets(s) orelse return false;
    if (o[0] == 0) return true;
    if (o[0] == 127) return true;
    if (o[0] >= 224) return true;
    if (o[0] == 169 and o[1] == 254) return true;
    return false;
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

fn native_is_resource(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const open = args.len > 0 and args[0] == .resource and !value_mod.resourceClosed(args[0].resource);
    return NativeResult.scalar(.{ .bool = open });
}

fn native_get_resource_type(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const r = try resourceArg(ctx, "get_resource_type", args);
    return NativeResult.copyString(ctx.allocator, value_mod.resourceTypeName(r));
}

fn native_get_resource_id(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const r = try resourceArg(ctx, "get_resource_id", args);
    return NativeResult.scalar(.{ .int = r.id });
}

fn resourceArg(ctx: *NativeContext, comptime name: []const u8, args: []const Value) RuntimeError!*PhpObject {
    const v: Value = if (args.len > 0) args[0] else .null;
    if (v == .resource) return v.resource;
    const msg = try std.fmt.allocPrint(ctx.allocator, name ++ "(): Argument #1 ($resource) must be of type resource, {s} given", .{v.typeName()});
    try ctx.strings.append(ctx.allocator, msg);
    try ctx.vm.setPendingException("TypeError", msg);
    return error.RuntimeError;
}

fn native_spl_object_hash(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    var id: u64 = 0;
    switch (args[0]) {
        .object => |o| {
            if (o.id == 0) {
                ctx.vm.next_object_id += 1;
                o.id = ctx.vm.next_object_id;
            }
            id = o.id;
        },
        .generator => |g| id = @intCast(@intFromPtr(g)),
        .fiber => |f| id = @intCast(@intFromPtr(f)),
        // closures are represented as unique name strings ("__closure_N_M"
        // or "__closure_bound_N"). use the string's pointer as the id so
        // every distinct closure instance gets a distinct hash
        .string => |s| {
            if (std.mem.startsWith(u8, s.bytes(), "__closure_")) {
                id = @intCast(@intFromPtr(s.bytes().ptr));
            } else {
                return throwObjectArg(ctx, "spl_object_hash", args[0]);
            }
        },
        else => return throwObjectArg(ctx, "spl_object_hash", args[0]),
    }
    // PHP format: 16 hex chars of id, then 16 zeros
    const hash = try std.fmt.allocPrint(ctx.allocator, "{x:0>16}0000000000000000", .{id});
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, hash));
}

