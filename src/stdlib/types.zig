const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const std = @import("std");
const class_names = @import("../runtime/class_names.zig");
const callables = @import("../runtime/callables.zig");
const object_properties = @import("../runtime/object_properties.zig");
const paths = @import("../paths.zig");
const php_version = @import("../php_version.zig");
const bundle = @import("../bundle.zig");
const platform = @import("../platform.zig");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const value_mod = @import("../runtime/value.zig");
const VM = @import("../runtime/vm.zig").VM;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const ClassDef = @import("../runtime/vm.zig").ClassDef;
const includes = @import("../runtime/includes.zig");
const spl_iterator_classes = @import("spl_iterator_classes.zig");
const open_basedir = @import("open_basedir.zig");
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "count", count },
    .{ "strlen", strlen },
    .{ "intval", intval },
    .{ "floatval", floatval },
    .{ "doubleval", floatval },
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
    .{ "get_mangled_object_vars", native_get_mangled_object_vars },
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
    .{ "ignore_user_abort", native_ignore_user_abort },
    .{ "getmxrr", native_getmxrr },
    .{ "header_register_callback", native_noop_true },
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
    .{ "memory_get_peak_usage", native_memory_get_peak_usage },
    .{ "memory_reset_peak_usage", native_memory_reset_peak_usage },
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
    .{ "register_tick_function", native_register_tick_function },
    .{ "unregister_tick_function", native_unregister_tick_function },
    .{ "error_reporting", native_error_reporting },
    .{ "error_get_last", native_error_get_last },
    .{ "error_clear_last", native_error_clear_last },
    .{ "get_include_path", native_get_include_path },
    .{ "set_include_path", native_set_include_path },
    .{ "trigger_error", native_trigger_error },
    .{ "user_error", native_trigger_error },
    .{ "error_log", native_error_log },
    .{ "__zphp_match_unhandled_msg", native_match_unhandled_msg },
    .{ "class_alias", native_class_alias },
    .{ "assert", native_assert },
    .{ "assert_options", native_assert_options },
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
    .{ "nl_langinfo", native_nl_langinfo },
    .{ "func_get_args", native_func_get_args },
    .{ "func_num_args", native_func_num_args },
    .{ "func_get_arg", native_func_get_arg },
    .{ "interface_exists", native_interface_exists },
    .{ "enum_exists", native_enum_exists },
    .{ "iterator_to_array", spl_iterator_classes.iteratorToArray },
    .{ "iterator_count", spl_iterator_classes.iteratorCount },
    .{ "iterator_apply", spl_iterator_classes.iteratorApplyFn },
    .{ "filter_var", native_filter_var },
    .{ "filter_id", native_filter_id },
    .{ "filter_list", native_filter_list },
    .{ "filter_has_var", native_filter_has_var },
    .{ "filter_input", native_filter_input },
    .{ "filter_input_array", native_filter_input_array },
    .{ "filter_var_array", native_filter_var_array },
    .{ "is_resource", native_is_resource },
    .{ "get_resource_type", native_get_resource_type },
    .{ "get_resources", native_get_resources },
    .{ "get_resource_id", native_get_resource_id },
};

fn native_define(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    if (ctx.vm.php_constants.contains(args[0].string.bytes())) {
        _ = try ctx.vm.defineConstant(args[0].string.bytes(), args[1]);
        return NativeResult.scalar(.{ .bool = false });
    }
    const name = try ctx.createString(args[0].string.bytes());
    try ctx.vm.user_constants.put(ctx.allocator, name, {});
    _ = try ctx.vm.defineConstant(name, args[1]);
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
        if (ctx.vm.pending_exception != null) return error.RuntimeError;
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn native_constant(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.null);
    const name = args[0].string.bytes();
    if (ctx.vm.php_constants.get(name)) |v| {
        try ctx.vm.warnDeprecatedConstant(name);
        return NativeResult.share(v);
    }
    if (std.mem.indexOf(u8, name, "::")) |sep| {
        const class_name = name[0..sep];
        const prop_name = name[sep + 2 ..];
        if (ctx.vm.traits.contains(class_name)) {
            const msg = try std.fmt.allocPrint(ctx.allocator, "Cannot access trait constant {s}::{s} directly", .{ ctx.vm.declaredClassName(class_name), prop_name });
            defer ctx.allocator.free(msg);
            try ctx.vm.setPendingException("Error", msg);
            return error.RuntimeError;
        }
        const found = ctx.vm.getClassConstant(class_name, prop_name);
        if (found == null and ctx.vm.pending_exception != null) return error.RuntimeError;
        if (found) |v| {
            try ctx.vm.checkClassConstantAccess(class_name, prop_name);
            _ = try ctx.vm.warnDeprecatedClassConstant(class_name, prop_name);
            return NativeResult.share(v);
        }
    }
    const msg = try std.fmt.allocPrint(ctx.allocator, "Undefined constant \"{s}\"", .{name});
    defer ctx.allocator.free(msg);
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

// PHP's type-name used in TypeError messages: 'string', 'int', 'float',
// 'array', 'true', 'false', 'null', or the class name for objects
pub fn phpTypeName(v: Value) []const u8 {
    return v.valueName();
}

// php warns when an object without a numeric conversion is cast to a number
fn warnObjectToNumber(ctx: *NativeContext, v: Value, comptime target: []const u8) RuntimeError!void {
    if (v != .object or @import("../runtime/value.zig").nativeCast(v.object, .number) != null) return;
    const msg = try std.fmt.allocPrint(ctx.allocator, "Object of class {s} could not be converted to " ++ target, .{v.object.class_name});
    defer ctx.allocator.free(msg);
    try ctx.vm.emitWarning(msg);
}

extern fn strtoll(s: [*:0]const u8, end: ?*[*:0]u8, base: c_int) c_longlong;

// php's intval(): zval_get_long for base 10 or a non-string, else c's
// strtol in that base, after php's own handling of a 0b prefix
fn intval(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const base = if (args.len >= 2) try @import("string_ports.zig").Args.init(ctx, "intval", args).long(1, "base") else 10;
    if (args[0] != .string or base == 10) {
        try warnObjectToNumber(ctx, args[0], "int");
        // PHP: intval(array) is 0 for empty array, 1 for non-empty
        if (args[0] == .array) {
            return NativeResult.scalar(.{ .int = if (args[0].array.entries.items.len == 0) @as(i64, 0) else @as(i64, 1) });
        }
        return NativeResult.scalar(.{ .int = Value.toInt(args[0]) });
    }
    var s = args[0].string.bytes();
    // c strings end at a nul
    if (std.mem.indexOfScalar(u8, s, 0)) |nul| s = s[0..nul];
    const a = ctx.allocator;
    if (base == 0 or base == 2) {
        var t = s;
        while (t.len > 0 and (t[0] == ' ' or (t[0] >= '\t' and t[0] <= '\r'))) t = t[1..];
        // three bytes or more cover "0b#" and "-0b"
        if (t.len > 2) {
            const offset: usize = if (t[0] == '-' or t[0] == '+') 1 else 0;
            if (t[offset] == '0' and (t[offset + 1] == 'b' or t[offset + 1] == 'B')) {
                const tmp = try a.allocSentinel(u8, t.len - 2, 0);
                defer a.free(tmp);
                if (offset == 1) tmp[0] = t[0];
                @memcpy(tmp[offset..], t[offset + 2 ..]);
                return NativeResult.scalar(.{ .int = strtoll(tmp.ptr, null, 2) });
            }
        }
    }
    const z = try a.dupeSentinel(u8, s, 0);
    defer a.free(z);
    // c's strtol takes bases 2 to 36, and 0; any other yields 0
    if (base != 0 and (base < 2 or base > 36)) return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = strtoll(z.ptr, null, @intCast(base)) });
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
        // zval_get_string: an object without __toString can't be one
        const msg = try std.fmt.allocPrint(ctx.allocator, "Object of class {s} could not be converted to string", .{@import("../runtime/class_names.zig").display(obj.class_name)});
        defer ctx.allocator.free(msg);
        try ctx.vm.setPendingException("Error", msg);
        return error.RuntimeError;
    }
    if (args[0] == .array) try ctx.vm.emitWarning("Array to string conversion");
    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);
    try args[0].format(&buf, ctx.allocator);
    const s = try buf.toOwnedSlice(ctx.allocator);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, s));
}

fn gettype(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("NULL");
    return switch (args[0]) {
        .null, .undef => NativeResult.literal("NULL"),
        .bool => NativeResult.literal("boolean"),
        .int => NativeResult.literal("integer"),
        .float => NativeResult.literal("double"),
        .string => NativeResult.literal("string"),
        .array => NativeResult.literal("array"),
        .object, .generator, .fiber => NativeResult.literal("object"),
        .resource => |r| if (value_mod.resourceClosed(r)) NativeResult.literal("resource (closed)") else NativeResult.literal("resource"),
    };
}

fn get_debug_type(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("null");
    return switch (args[0]) {
        .null, .undef => NativeResult.literal("null"),
        .bool => NativeResult.literal("bool"),
        .int => NativeResult.literal("int"),
        .float => NativeResult.literal("float"),
        .string => NativeResult.literal("string"),
        .array => NativeResult.literal("array"),
        .object => |o| try NativeResult.copyString(ctx.allocator, class_names.display(o.class_name)),
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
    return NativeResult.scalar(.{ .bool = args[0] == .string });
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
        .string => |s| NativeResult.scalar(.{ .int = @intCast(s.bytes().len) }),
        .int => |i| blk: {
            var buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch break :blk NativeResult.scalar(.{ .int = 0 });
            break :blk NativeResult.scalar(.{ .int = @intCast(s.len) });
        },
        // a float as php turns it into a string, with the precision ini
        .float => NativeResult.scalar(.{ .int = @intCast((try ctx.vm.transientFormatted(args[0])).bytes().len) }),
        .bool => |b| NativeResult.scalar(.{ .int = if (b) 1 else 0 }),
        .null => NativeResult.scalar(.{ .int = 0 }),
        .object => |obj| blk: {
            if (ctx.vm.hasMethod(obj.class_name, "__toString")) {
                const result = try ctx.vm.callMethod(obj, "__toString", &.{});
                if (result == .string) break :blk NativeResult.scalar(.{ .int = @intCast(result.string.bytes().len) });
            }
            // object without __toString: PHP throws TypeError with the class name
            const msg = try std.fmt.allocPrint(ctx.allocator, "strlen(): Argument #1 ($string) must be of type string, {s} given", .{phpTypeName(args[0])});
            defer ctx.allocator.free(msg);
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
    return NativeResult.scalar(.{ .bool = false });
}

fn is_scalar(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{
        .bool = switch (args[0]) {
            .int, .float, .bool, .string => true,
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

fn native_nl_langinfo(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = args;
    return NativeResult.literal("");
}

fn isPunct(c: u8) bool {
    return std.ascii.isPrint(c) and !std.ascii.isAlphanumeric(c) and c != ' ';
}
fn isGraph(c: u8) bool {
    return std.ascii.isPrint(c) and c != ' ';
}

fn get_class(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) {
        // php 8.3+: the class of the calling scope, deprecated
        const scope = ctx.vm.currentDefiningClass() orelse {
            try ctx.vm.setPendingException("Error", "get_class() without arguments must be called from within a class");
            return error.RuntimeError;
        };
        try ctx.vm.raiseError(8192, "Calling get_class() without arguments is deprecated");
        if (ctx.vm.pending_exception != null) return error.RuntimeError;
        return NativeResult.copyString(ctx.allocator, ctx.vm.declaredClassName(scope));
    }
    if (args[0] == .object) return NativeResult.copyString(ctx.allocator, args[0].object.class_name);
    if (args[0] == .generator) return NativeResult.literal("Generator");
    if (args[0] == .fiber) return NativeResult.literal("Fiber");
    return throwObjectArg(ctx, "get_class", args[0]);
}

// zend_get_called_scope: the calling function's own class scope only
fn get_called_class(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const frame = ctx.vm.currentFrame();
    if (frame.called_class) |cc| return NativeResult.copyString(ctx.allocator, cc);
    if (ctx.vm.currentThis()) |this| if (this == .object) return NativeResult.copyString(ctx.allocator, this.object.class_name);
    try ctx.vm.setPendingException("Error", "get_called_class() must be called from within a class");
    return error.RuntimeError;
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

fn class_exists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const raw = args[0].string.bytes();
    const name = if (raw.len > 0 and raw[0] == '\\') raw[1..] else raw;
    if (std.ascii.eqlIgnoreCase(name, "stdClass") or std.ascii.eqlIgnoreCase(name, "Attribute")) return NativeResult.scalar(.{ .bool = true });
    if (std.ascii.eqlIgnoreCase(name, "Closure") or std.ascii.eqlIgnoreCase(name, "Generator") or std.ascii.eqlIgnoreCase(name, "Fiber")) return NativeResult.scalar(.{ .bool = true });
    if (ctx.vm.interfaces.contains(name)) return NativeResult.scalar(.{ .bool = false });
    if (ctx.vm.traits.contains(name)) return NativeResult.scalar(.{ .bool = false });
    if (ctx.vm.classes.contains(name)) return NativeResult.scalar(.{ .bool = true });
    const autoload = args.len < 2 or !(args[1] == .bool and !args[1].bool);
    if (autoload and ctx.vm.autoload_callbacks.items.len > 0) {
        try ctx.vm.tryAutoload(name);
        return NativeResult.scalar(.{ .bool = ctx.vm.classes.contains(name) and !ctx.vm.interfaces.contains(name) });
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn method_exists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
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
            // the methods map ignores case and keeps the declared spelling
            if (cls.methods.getEntry(method_name)) |entry| {
                canonical_method = entry.key_ptr.*;
                if (entry.value_ptr.visibility == .private) private_at_this_class = true;
            }
        }
        // ancestor private methods are not visible from a subclass
        if (depth > 0 and private_at_this_class) {
            // skip this class's match; continue up
        } else {
            const full = class_names.memberKey(&buf, cn, canonical_method);
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
        // spl_array_has_property: under ARRAY_AS_PROPS, an element
        if (try @import("spl.zig").propertyAsElementExists(ctx, obj, args[1])) |found| return NativeResult.scalar(.{ .bool = found });
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

// php's is_callable: zend_is_callable_ex against the calling scope (its
// deprecations included), or only the shape of the value with
// $syntax_only; $callable_name is always set, as zend_get_callable_name_ex
// names the value
fn native_is_callable(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const val = args[0];
    const syntax_only = args.len > 1 and args[1].isTruthy();
    if (args.len >= 3) {
        var name: std.ArrayListUnmanaged(u8) = .empty;
        defer name.deinit(ctx.allocator);
        try callableName(ctx, val, &name);
        const owned = try Value.String.create(ctx.allocator, name.items);
        defer owned.release();
        ctx.setCallerVar(2, args.len, .{ .string = owned });
    }
    if (syntax_only) {
        const ok = switch (val) {
            .string => true,
            .object => |o| std.mem.eql(u8, o.class_name, "Closure") or ctx.vm.hasMethod(o.class_name, "__invoke"),
            .array => |arr| blk: {
                if (arr.entries.items.len != 2) break :blk false;
                const target = arr.get(.{ .int = 0 });
                const method = arr.get(.{ .int = 1 });
                break :blk (target == .string or target == .object) and method == .string;
            },
            else => false,
        };
        return NativeResult.scalar(.{ .bool = ok });
    }
    if (val != .string and val != .array and val != .object) return NativeResult.scalar(.{ .bool = false });
    const resolution = try callables.resolveCallback(ctx.vm, val, .{});
    if (ctx.vm.pending_exception != null) return error.RuntimeError;
    return NativeResult.scalar(.{ .bool = resolution == .callee });
}

// zend_get_callable_name_ex
fn callableName(ctx: *NativeContext, val: Value, out: *std.ArrayListUnmanaged(u8)) RuntimeError!void {
    const a = ctx.allocator;
    switch (val) {
        .string => |s| try out.appendSlice(a, s.bytes()),
        .array => |arr| {
            const target = arr.get(.{ .int = 0 });
            const method = arr.get(.{ .int = 1 });
            if (arr.entries.items.len != 2 or !arr.contains(.{ .int = 0 }) or method != .string) return out.appendSlice(a, "Array");
            switch (target) {
                .string => |s| try out.print(a, "{s}::{s}", .{ s.bytes(), method.string.bytes() }),
                .object => |o| try out.print(a, "{s}::{s}", .{ o.class_name, method.string.bytes() }),
                else => try out.appendSlice(a, "Array"),
            }
        },
        .object => |o| {
            if (std.mem.eql(u8, o.class_name, "Closure")) {
                var name_buf: [512]u8 = undefined;
                return out.appendSlice(a, closureCallableName(ctx, o, &name_buf));
            }
            try out.print(a, "{s}::__invoke", .{o.class_name});
        },
        .generator, .fiber => try out.print(a, "{s}::__invoke", .{if (val == .generator) "Generator" else "Fiber"}),
        .resource => |r| try out.print(a, "Resource id #{d}", .{r.id}),
        .float => {
            if (std.math.isNan(val.float)) try ctx.vm.emitWarning("unexpected NAN value was coerced to string");
            try out.appendSlice(a, (try ctx.vm.transientFormatted(val)).bytes());
        },
        else => try val.format(out, a),
    }
}

fn closureCallableName(ctx: *NativeContext, closure: *value_mod.PhpObject, buf: []u8) []const u8 {
    if (closure.closureName()) |instance| {
        const func = ctx.vm.functions.get(instance) orelse return "{closure}";
        return if (func.display_name.len > 0) func.display_name else "{closure}";
    }
    const callable = closure.get("__callable");
    return switch (callable) {
        .string => |s| s.bytes(),
        .object => |o| std.fmt.bufPrint(buf, "{s}::__invoke", .{o.class_name}) catch "{closure}",
        .array => |arr| blk: {
            if (arr.entries.items.len != 2) break :blk "{closure}";
            const target = arr.entries.items[0].value;
            const method = arr.entries.items[1].value;
            if (method != .string) break :blk "{closure}";
            const class = switch (target) {
                .object => |o| o.class_name,
                .string => |cs| cs.bytes(),
                else => break :blk "{closure}",
            };
            break :blk std.fmt.bufPrint(buf, "{s}::{s}", .{ class, method.string.bytes() }) catch "{closure}";
        },
        else => "{closure}",
    };
}

// the ignore_user_abort directive before the call, which a bool given sets
fn native_ignore_user_abort(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const current = ctx.vm.ini_settings.get("ignore_user_abort") orelse "0";
    const previous = std.fmt.parseInt(i64, std.mem.trim(u8, current, " "), 10) catch @as(i64, if (std.ascii.eqlIgnoreCase(current, "on") or std.ascii.eqlIgnoreCase(current, "true") or std.ascii.eqlIgnoreCase(current, "yes")) 1 else 0);
    if (args.len >= 1 and args[0] != .null) _ = try ctx.vm.setIni("ignore_user_abort", if (args[0].isTruthy()) "1" else "0");
    return NativeResult.scalar(.{ .int = previous });
}

fn native_settype(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.null);
    if (args.len < 2 or args[1] != .string) return NativeResult.share(args[0]);
    const type_name = args[1].string.bytes();
    const val = args[0];
    const is = struct {
        fn f(name: []const u8, comptime want: []const u8) bool {
            return std.ascii.eqlIgnoreCase(name, want);
        }
    }.f;
    if (is(type_name, "int") or is(type_name, "integer")) {
        // convert_to_long: an object without a numeric form warns and is 1
        if (val == .object and @import("../runtime/value.zig").nativeCast(val.object, .int) == null) {
            try warnObjectToNumber(ctx, val, "int");
            return NativeResult.scalar(.{ .int = 1 });
        }
        return NativeResult.scalar(.{ .int = Value.toInt(val) });
    }
    if (is(type_name, "float") or is(type_name, "double")) {
        if (val == .object and @import("../runtime/value.zig").nativeCast(val.object, .float) == null) {
            try warnObjectToNumber(ctx, val, "float");
            return NativeResult.scalar(.{ .float = 1 });
        }
        // convert_to_double: an array is 1.0 when it has elements
        if (val == .array) return NativeResult.scalar(.{ .float = if (val.array.entries.items.len > 0) 1 else 0 });
        return NativeResult.scalar(.{ .float = Value.toFloat(val) });
    }
    if (is(type_name, "string")) {
        if (val == .string) return NativeResult.share(val);
        if (val == .array) try ctx.vm.emitWarning("Array to string conversion");
        // __toString, or php's "could not be converted to string" Error
        if (val == .object) {
            const text = try ctx.vm.objectString(val.object);
            return if (text.owner != null) NativeResult.takeString(text) else NativeResult.shareString(text);
        }
        var buf = std.ArrayListUnmanaged(u8).empty;
        defer buf.deinit(ctx.allocator);
        try val.format(&buf, ctx.allocator);
        const s = try buf.toOwnedSlice(ctx.allocator);
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, s));
    }
    if (is(type_name, "bool") or is(type_name, "boolean"))
        return NativeResult.scalar(.{ .bool = val.isTruthy() });
    if (is(type_name, "null"))
        return NativeResult.scalar(.null);
    if (is(type_name, "array")) {
        if (val == .array) return NativeResult.share(val);
        return NativeResult.borrowed(try ctx.vm.castToArray(val));
    }
    if (is(type_name, "object")) {
        if (val == .object) return NativeResult.share(val);
        return NativeResult.borrowed(try ctx.vm.castToObject(val));
    }
    if (is(type_name, "resource")) {
        try ctx.vm.setPendingException("ValueError", "Cannot convert to resource type");
        return error.RuntimeError;
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
    var buf: [16]Value = undefined;
    const call_args = try ctx.argsFromArray(arr, &buf);
    defer ctx.freeArgs(call_args, &buf);
    return NativeResult.share(try ctx.invokeCallable(args[0], call_args));
}

fn native_function_exists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = ctx.vm.functionExists(args[0].string.bytes()) });
}

fn native_get_object_vars(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(Value{ .bool = false });
    return NativeResult.borrowed(.{ .array = try getObjectVars(ctx, args[0].object) });
}

// the properties of an object the running code's class can see
pub fn getObjectVars(ctx: *NativeContext, object: *PhpObject) RuntimeError!*PhpArray {
    try ctx.vm.triggerLazyInit(object);
    const obj = object.storage();
    var arr = try ctx.createArray();

    // the caller's class scope, bound closures included; natives run inline,
    // so the caller is the current frame
    const caller_class: ?[]const u8 = ctx.vm.currentDefiningClass();
    const can_see_protected = caller_class != null and isInClassHierarchy(ctx.vm, caller_class.?, obj.class_name);

    // the object's own properties, as php's get_properties gives them: never
    // unset or uninitialized ones
    var listing: object_properties.Listing = .{};
    defer listing.deinit(ctx.allocator);
    try object_properties.appendOwn(ctx.vm, obj, .array_cast, &listing, ctx.allocator);
    try object_properties.applyHooks(ctx.vm, obj, &listing, ctx.allocator, .{ .scope = caller_class });
    defer object_properties.releaseHolder(ctx.vm, listing.takeHolder());
    for (listing.items.items) |prop| {
        if (prop.visibility == .private and (caller_class == null or !std.mem.eql(u8, caller_class.?, prop.declaring))) continue;
        if (prop.visibility == .protected and !can_see_protected) continue;
        if (prop.declared) {
            try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(prop.key.name) }, prop.value);
        } else {
            try arr.setCopiedKey(ctx.allocator, prop.key.name, prop.value);
        }
    }
    return arr;
}

// the object's own property table with (array)'s mangled keys, whatever the
// scope, and without what a class's get_properties_for adds (SplFixedArray's
// elements, ArrayObject's storage)
fn native_get_mangled_object_vars(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len != 1) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "get_mangled_object_vars() expects exactly 1 argument, {d} given", .{args.len});
        defer ctx.allocator.free(msg);
        try ctx.vm.setPendingException("ArgumentCountError", msg);
        return error.RuntimeError;
    }
    if (args[0] != .object) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "get_mangled_object_vars(): Argument #1 ($object) must be of type object, {s} given", .{phpTypeName(args[0])});
        defer ctx.allocator.free(msg);
        try ctx.vm.setPendingException("TypeError", msg);
        return error.RuntimeError;
    }
    const obj = args[0].object.storage();
    var listing: object_properties.Listing = .{};
    defer listing.deinit(ctx.allocator);
    try object_properties.appendOwn(ctx.vm, obj, .array_cast, &listing, ctx.allocator);
    const arr = try ctx.createArray();
    for (listing.items.items) |p| try object_properties.setMangled(ctx.vm, arr, p.key.name, p.visibility, p.declaring, p.value);
    return NativeResult.borrowed(.{ .array = arr });
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
        // a virtual property has no default to list
        if (prop.is_virtual and ctx.vm.propertyIsVirtual(class_name, prop.name)) continue;
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(prop.name) }, prop.default);
    }
    // PHP's get_class_vars also includes static properties
    var sit = cls.static_props.iterator();
    while (sit.next()) |e| {
        // class constants are also stored in static_props; skip them
        if (cls.constants.contains(e.key_ptr.*)) continue;
        const static_visible = switch (cls.static_prop_visibility.get(e.key_ptr.*) orelse .public) {
            .public => true,
            .protected => caller != null and isInClassChain(ctx.vm, caller.?, class_name),
            .private => caller != null and std.mem.eql(u8, caller.?, class_name),
        };
        if (!static_visible) continue;
        // an uninitialized typed static property lists as null
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(e.key_ptr.*) }, if (e.value_ptr.* == .undef) .null else e.value_ptr.*);
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
        if (args[0].object.id == 0) args[0].object.id = try ctx.vm.allocHandle();
        return NativeResult.scalar(.{ .int = @intCast(args[0].object.id) });
    }
    if (args[0] == .generator) return NativeResult.scalar(.{ .int = args[0].generator.handle });
    if (args[0] == .fiber) return NativeResult.scalar(.{ .int = args[0].fiber.handle });
    return throwObjectArg(ctx, "spl_object_id", args[0]);
}

fn throwObjectArg(ctx: *NativeContext, comptime func: []const u8, v: Value) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, func ++ "(): Argument #1 ($object) must be of type object, {s} given", .{v.valueName()});
    defer ctx.allocator.free(msg);
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
    return NativeResult.literal(php_version.string);
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
    if (std.mem.eql(u8, name, "date.default_latitude")) return "31.7667";
    if (std.mem.eql(u8, name, "date.default_longitude")) return "35.2333";
    if (std.mem.eql(u8, name, "date.sunrise_zenith")) return "90.833333";
    if (std.mem.eql(u8, name, "date.sunset_zenith")) return "90.833333";
    // PHP CLI default is "-1" (no limit); web SAPI default is "128M"
    if (std.mem.eql(u8, name, "memory_limit")) return "128M";
    if (std.mem.eql(u8, name, "max_memory_limit")) return "-1";
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
    if (std.mem.eql(u8, name, "pcre.backtrack_limit")) return "1000000";
    if (std.mem.eql(u8, name, "pcre.recursion_limit")) return "100000";
    if (std.mem.eql(u8, name, "pcre.jit")) return "1";
    if (std.mem.eql(u8, name, "serialize_precision")) return "-1";
    if (std.mem.eql(u8, name, "unserialize_callback_func")) return "";
    if (std.mem.eql(u8, name, "unserialize_max_depth")) return "4096";
    if (std.mem.eql(u8, name, "ignore_user_abort")) return "0";
    if (std.mem.eql(u8, name, "docref_root")) return "";
    if (std.mem.eql(u8, name, "docref_ext")) return "";
    if (std.mem.eql(u8, name, "user_agent")) return "";
    if (std.mem.eql(u8, name, "open_basedir")) return "";
    if (std.mem.eql(u8, name, "include_path")) return includes.default_include_path;
    if (std.mem.eql(u8, name, "log_errors")) return "1";
    if (std.mem.eql(u8, name, "fatal_error_backtraces")) return "1";
    if (std.mem.eql(u8, name, "error_log")) return "";
    if (std.mem.eql(u8, name, "html_errors")) return "0";
    if (std.mem.eql(u8, name, "max_execution_time")) return "0";
    // one log copy on stderr and no display copy: php with display_errors=0
    // and log_errors=1, the setting the compatibility runners pin php to
    if (std.mem.eql(u8, name, "display_errors")) return "0";
    if (std.mem.eql(u8, name, "error_reporting")) return "30719";
    if (std.mem.eql(u8, name, "zend.assertions")) return "1";
    if (std.mem.eql(u8, name, "zend.enable_gc")) return "1";
    if (std.mem.eql(u8, name, "fiber.stack_size")) return "";
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
    switch (args[1]) {
        .array, .object, .resource, .generator, .fiber => {
            try ctx.vm.setPendingException("TypeError", "ini_set(): Argument #2 ($value) must be of type string|int|float|bool|null");
            return error.RuntimeError;
        },
        else => {},
    }
    // PHP rejects unknown directives. Only allow known names.
    const previous: []const u8 = if (ctx.vm.ini_settings.get(name)) |s| s else if (iniDefault(name)) |d| d else return NativeResult.scalar(Value{ .bool = false });
    // max_memory_limit can only be set at startup
    if (std.mem.eql(u8, name, "max_memory_limit")) return NativeResult.scalar(Value{ .bool = false });
    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);
    try args[1].format(&buf, ctx.allocator);
    // php's OnUpdateFiberStackSize
    if (std.mem.eql(u8, name, "fiber.stack_size") and @import("../runtime/memory.zig").parseQuantity(buf.items).value < 0) {
        try ctx.vm.emitWarning("fiber.stack_size must be a positive number");
        return NativeResult.scalar(Value{ .bool = false });
    }
    if (std.mem.eql(u8, name, "memory_limit")) {
        const requested = @import("../runtime/memory.zig").parseQuantity(buf.items).value;
        if (ctx.vm.memoryLimitCap(requested)) |cap| {
            if (requested >= 0) {
                const msg = try std.fmt.allocPrint(ctx.allocator, "Failed to set memory_limit to {d} bytes. Setting to max_memory_limit instead (currently: {d} bytes)", .{ requested, cap.bytes });
                defer ctx.allocator.free(msg);
                try ctx.vm.emitWarning(msg);
            }
            buf.clearRetainingCapacity();
            try buf.appendSlice(ctx.allocator, cap.text);
        }
        if (!try setMemoryLimit(ctx, buf.items)) return NativeResult.scalar(Value{ .bool = false });
    }
    // php's OnUpdate_date_timezone: an id its database lacks is refused
    const is_tz = std.mem.eql(u8, name, "date.timezone");
    if (is_tz and !@import("tzdb.zig").isValid(buf.items)) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "ini_set(): Invalid date.timezone value '{s}', using '{s}' instead", .{ buf.items, previous });
        defer ctx.allocator.free(msg);
        try ctx.vm.emitWarning(msg);
        return NativeResult.scalar(Value{ .bool = false });
    }
    // php's OnUpdateBaseDir: at run time open_basedir may only tighten, and
    // is stored with each entry expanded
    if (std.mem.eql(u8, name, "open_basedir")) {
        const narrowed = (try open_basedir.tightened(ctx.vm, buf.items)) orelse return NativeResult.scalar(Value{ .bool = false });
        defer ctx.allocator.free(narrowed);
        buf.clearRetainingCapacity();
        try buf.appendSlice(ctx.allocator, narrowed);
    }
    // php's OnUpdateErrorLog and OnUpdateMailLog check the file at run time
    if ((std.mem.eql(u8, name, "error_log") and !std.mem.eql(u8, buf.items, "syslog") or std.mem.eql(u8, name, "mail.log")) and buf.items.len > 0) {
        if (!try open_basedir.allows(ctx.vm, "ini_set", buf.items)) return NativeResult.scalar(Value{ .bool = false });
    }
    const result = try NativeResult.copyString(ctx.allocator, previous);
    const new_val = try ctx.vm.setIni(name, buf.items);
    // the ini value is the default zone unless the script set one
    if (is_tz and ctx.vm.default_tz_name.ptr != &ctx.vm.default_tz_buf) ctx.vm.default_tz_name = @import("datetime.zig").internZoneName(new_val);
    // a few ini directives map directly to live VM state. mirror them now so
    // userland `ini_set('max_execution_time', '5')` actually arms the deadline
    if (std.mem.eql(u8, name, "max_execution_time")) {
        const seconds = std.fmt.parseInt(i64, std.mem.trim(u8, new_val, " \t\r\n"), 10) catch 0;
        ctx.vm.setExecutionLimit(seconds);
    }
    if (std.mem.eql(u8, name, "zend.enable_gc")) ctx.vm.syncGcEnabled();
    if (std.mem.eql(u8, name, "precision") or std.mem.eql(u8, name, "serialize_precision")) ctx.vm.syncFloatPrecision();
    return result;
}


pub const SUPPORTED_EXTENSIONS = [_][]const u8{
    "Core",      "standard",   "SPL",       "json",      "pcre",
    "PDO",       "pdo_sqlite", "pdo_mysql", "pdo_pgsql", "session",
    "mbstring",  "ctype",      "filter",    "hash",      "iconv",
    "tokenizer", "Reflection", "date",      "openssl",   "curl",
    "sodium",    "ldap",       "ftp",       "gd",        "gmp",
    "bcmath",    "libxml",     "dom",       "SimpleXML", "xml",
    "xmlreader", "xmlwriter",  "intl",      "fileinfo",  "Phar",
    "soap",      "zlib",       "posix",     "pcntl",     "random",
};

fn native_extension_loaded(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const name = args[0].string.bytes();
    for (SUPPORTED_EXTENSIONS) |s| {
        if (std.ascii.eqlIgnoreCase(name, s)) return NativeResult.scalar(.{ .bool = true });
    }
    // also accept the historic "datetime" alias for "date"
    if (std.ascii.eqlIgnoreCase(name, "datetime")) return NativeResult.scalar(.{ .bool = true });
    return NativeResult.scalar(.{ .bool = @import("../extension.zig").isLoaded(name) });
}

fn native_get_loaded_extensions(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    for (SUPPORTED_EXTENSIONS) |s| try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(s) });
    for (@import("../extension.zig").loaded()) |ext| try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(ext.name) });
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_get_extension_funcs(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const name = args[0].string.bytes();
    // the functions zphp has of the extension, by php's map of which
    // extension declares each; false for an extension that isn't loaded or
    // declares none
    const loaded = for (SUPPORTED_EXTENSIONS) |s| {
        if (std.ascii.eqlIgnoreCase(name, s)) break true;
    } else false;
    if (!loaded) return NativeResult.scalar(.{ .bool = false });
    const arr = try ctx.createArray();
    const extensions = @import("extensions_generated.zig");
    for (extensions.functions.keys(), extensions.functions.values()) |fname, owner| {
        if (!std.ascii.eqlIgnoreCase(owner, name)) continue;
        const canonical = ctx.vm.canonicalFunctionName(fname) orelse continue;
        try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(canonical) });
    }
    if (arr.entries.items.len == 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_get_included_files(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    var arr = try ctx.createArray();
    for (ctx.vm.ic.?.included.keys()) |path| {
        try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(path) });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

// register_tick_function: the callback and its arguments run on each tick
fn native_register_tick_function(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    const extra = try ctx.allocator.alloc(Value, args.len - 1);
    errdefer ctx.allocator.free(extra);
    @memcpy(extra, args[1..]);
    ctx.vm.tick_function_ids += 1;
    try ctx.vm.tick_functions.append(ctx.allocator, .{ .callable = args[0], .args = extra, .id = ctx.vm.tick_function_ids });
    VM.retainValue(args[0]);
    for (extra) |v| VM.retainValue(v);
    return NativeResult.scalar(.{ .bool = true });
}

// unregister_tick_function: the first registration of the same callable
// goes, unless it is running
fn native_unregister_tick_function(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.null);
    const list = &ctx.vm.tick_functions;
    for (list.items, 0..) |entry, i| {
        if (!sameCallable(entry.callable, args[0])) continue;
        if (entry.calling) {
            try ctx.vm.setPendingException("Error", "Registered tick function cannot be unregistered while it is being executed");
            return error.RuntimeError;
        }
        const removed = list.orderedRemove(i);
        ctx.vm.releaseValue(removed.callable);
        for (removed.args) |v| ctx.vm.releaseValue(v);
        ctx.allocator.free(removed.args);
        break;
    }
    return NativeResult.scalar(.null);
}

fn sameCallable(a: Value, b: Value) bool {
    return switch (a) {
        .string => |s| b == .string and std.ascii.eqlIgnoreCase(std.mem.trimStart(u8, s.bytes(), "\\"), std.mem.trimStart(u8, b.string.bytes(), "\\")),
        .object => |o| b == .object and b.object == o,
        .array => |arr| blk: {
            if (b != .array or arr.entries.items.len != 2 or b.array.entries.items.len != 2) break :blk false;
            break :blk sameCallable(arr.entries.items[0].value, b.array.entries.items[0].value) and sameCallable(arr.entries.items[1].value, b.array.entries.items[1].value);
        },
        else => false,
    };
}

fn native_register_shutdown_function(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.null);
    const extra = try ctx.allocator.alloc(Value, args.len - 1);
    errdefer ctx.allocator.free(extra);
    @memcpy(extra, args[1..]);
    try ctx.vm.shutdown_callbacks.append(ctx.allocator, .{ .callable = args[0], .args = extra });
    VM.retainValue(args[0]);
    for (extra) |v| VM.retainValue(v);
    return NativeResult.scalar(.null);
}

fn native_memory_get_usage(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const used = if (ctx.vm.memory) |m| m.usage() else 0;
    const real = args.len > 0 and args[0].isTruthy();
    return NativeResult.scalar(.{ .int = @intCast(if (real) VM.realMemoryUsage(used) else used) });
}

fn native_memory_get_peak_usage(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const peak = if (ctx.vm.memory) |m| m.peakUsage() else 0;
    const real = args.len > 0 and args[0].isTruthy();
    return NativeResult.scalar(.{ .int = @intCast(if (real) VM.realMemoryUsage(peak) else peak) });
}

fn native_memory_reset_peak_usage(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    if (ctx.vm.memory) |m| m.resetPeak();
    return NativeResult.scalar(.null);
}

// ini_set('memory_limit', ...): php's quantity diagnostics, and a limit below
// what is already in use is refused. false when refused
fn setMemoryLimit(ctx: *NativeContext, text: []const u8) RuntimeError!bool {
    const memory = @import("../runtime/memory.zig");
    const q = memory.parseQuantity(text);
    if (q.problem) |problem| {
        const trimmed = std.mem.trim(u8, text, " \t\n\r");
        const msg = switch (problem) {
            .no_digits => try std.fmt.allocPrint(ctx.allocator, "Invalid \"memory_limit\" setting. Invalid quantity \"{s}\": no valid leading digits, interpreting as \"0\" for backwards compatibility", .{trimmed}),
            .unknown_multiplier => |u| try std.fmt.allocPrint(ctx.allocator, "Invalid \"memory_limit\" setting. Invalid quantity \"{s}\": unknown multiplier \"{c}\", interpreting as \"{s}\" for backwards compatibility", .{ trimmed, u.multiplier, u.used }),
            .out_of_range => try std.fmt.allocPrint(ctx.allocator, "Invalid \"memory_limit\" setting. Invalid quantity \"{s}\": value is out of range, using overflow result for backwards compatibility", .{trimmed}),
        };
        defer ctx.allocator.free(msg);
        try ctx.vm.emitWarning(msg);
    }
    const account = ctx.vm.memory orelse return true;
    if (q.value >= 0) {
        const in_use = VM.realMemoryUsage(account.usage());
        if (@as(u64, @intCast(q.value)) < in_use) {
            const msg = try std.fmt.allocPrint(ctx.allocator, "Failed to set memory limit to {d} bytes (Current memory usage is {d} bytes)", .{ q.value, in_use });
            defer ctx.allocator.free(msg);
            try ctx.vm.emitWarning(msg);
            return false;
        }
        account.limit = @intCast(q.value);
    } else account.limit = 0;
    return true;
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
        ctx.vm.raise(args[1]);
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
            _ = try ctx.vm.setIni(key, s);
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

// php's gc_enable()/gc_disable() set zend.enable_gc
fn native_gc_disable(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    _ = try ctx.vm.setIni("zend.enable_gc", "0");
    ctx.vm.gc_enabled = false;
    return NativeResult.scalar(.null);
}

fn native_gc_enable(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    _ = try ctx.vm.setIni("zend.enable_gc", "1");
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
    try ctx.vm.restoreIni(name);
    if (std.mem.eql(u8, name, "memory_limit")) ctx.vm.applyConfiguredMemoryLimit(false);
    if (std.mem.eql(u8, name, "zend.enable_gc")) ctx.vm.syncGcEnabled();
    if (std.mem.eql(u8, name, "precision") or std.mem.eql(u8, name, "serialize_precision")) ctx.vm.syncFloatPrecision();
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

fn native_getmxrr(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // empty MX array, return false (no records found) - matches PHP behavior
    // when MX query fails. tools that branch on this still work.
    _ = ctx;
    return NativeResult.scalar(.{ .bool = false });
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

fn native_get_include_path(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.copyString(ctx.allocator, includes.includePath(ctx.vm));
}

fn native_set_include_path(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    try args[0].format(&buf, ctx.allocator);
    if (buf.items.len == 0) return NativeResult.scalar(.{ .bool = false });
    const previous = try NativeResult.copyString(ctx.allocator, includes.includePath(ctx.vm));
    _ = try ctx.vm.setIni("include_path", buf.items);
    return previous;
}

fn native_error_reporting(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // inside @ php's error_reporting is the level with only the fatal errors
    // left (BEGIN_SILENCE), which an error handler reads to tell it apart
    const fatal_only: i64 = 1 | 16 | 64 | 256 | 4096 | 4;
    const prev = if (ctx.vm.error_silenced_depth > 0) ctx.vm.error_reporting_level & fatal_only else ctx.vm.error_reporting_level;
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
    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);
    try buf.appendSlice(ctx.allocator, "Unhandled match case ");
    switch (v) {
        .int => |i| try buf.print(ctx.allocator, "{d}", .{i}),
        .float => try v.format(&buf, ctx.allocator),
        .bool => |b| try buf.appendSlice(ctx.allocator, if (b) "true" else "false"),
        .null, .undef => try buf.appendSlice(ctx.allocator, "null"),
        .string => |s| {
            try buf.append(ctx.allocator, '\'');
            try buf.appendSlice(ctx.allocator, s.bytes());
            try buf.append(ctx.allocator, '\'');
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
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const path = paths.streamPath(&path_buf, args[2].string.bytes());
            if (open_basedir.setting(ctx.vm) != null and !paths.hasScheme(path) and !try open_basedir.allows(ctx.vm, "error_log", path)) {
                const msg = try std.fmt.allocPrint(ctx.allocator, "error_log({s}): Failed to open stream: Operation not permitted", .{args[2].string.bytes()});
                defer ctx.allocator.free(msg);
                try ctx.vm.emitWarning(msg);
                return NativeResult.scalar(.{ .bool = false });
            }
            bundle.prepareWrite(path, .edit);
            const f = std.Io.Dir.cwd().createFile(platform.io, path, .{ .truncate = false }) catch return NativeResult.scalar(.{ .bool = false });
            defer f.close(platform.io);
            platform.seekFromEnd(f, 0) catch {};
            platform.writeAll(f, message) catch return NativeResult.scalar(.{ .bool = false });
            return NativeResult.scalar(.{ .bool = true });
        },
        else => {
            // type 0 (system logger) / 4 (SAPI) - PHP's CLI SAPI writes to
            // stderr with a trailing newline. flush buffered stdout first so
            // the merged stream order matches PHP's unbuffered CLI stdout
            const vm = ctx.vm;
            vm.flushOutputToStdout();
            const line = try std.fmt.allocPrint(ctx.allocator, "{s}\n", .{message});
            defer ctx.allocator.free(line);
            vm.writeLog(line);
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
    try ctx.vm.raiseMessageAt(level, args[0].string.bytes(), ctx.vm.currentSourcePosition());
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
    const written = args[0].string.bytes();
    const original = if (written.len > 0 and written[0] == '\\') written[1..] else written;
    const alias = args[1].string.bytes();
    const autoload = if (args.len >= 3) args[2].isTruthy() else true;
    {
        // zend_register_class_alias_ex: a reserved alias is a compile error
        const bare = if (alias.len > 0 and alias[0] == '\\') alias[1..] else alias;
        if (@import("../pipeline/compiler_class.zig").isReservedClassName(bare)) {
            const lower = try std.ascii.allocLowerString(ctx.allocator, bare);
            defer ctx.allocator.free(lower);
            const msg = try std.fmt.allocPrint(ctx.allocator, "Cannot use \"{s}\" as a class alias as it is reserved", .{lower});
            defer ctx.allocator.free(msg);
            return ctx.vm.raiseFatal(msg);
        }
    }
    if (autoload and !ctx.vm.classes.contains(original)) {
        try ctx.vm.tryAutoload(original);
    }
    if (ctx.vm.classes.get(original)) |cls| {
        const taken = ctx.vm.classes.contains(alias) or ctx.vm.interfaces.contains(alias) or ctx.vm.traits.contains(alias);
        if (if (taken) try ctx.vm.redeclarationMessageAs(cls.alias_of orelse cls.name, alias) else null) |msg| {
            defer ctx.allocator.free(msg);
            try ctx.vm.emitWarning(msg);
            return NativeResult.scalar(.{ .bool = false });
        }
        var alias_def = ClassDef{ .name = alias, .parent = original, .alias_of = cls.alias_of orelse cls.name, .is_internal = cls.is_internal };
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

// a parameter's current value (php reads the CV, so a parameter the function
// changed shows its new value); an unset one is null
fn getFrameParamValue(frame: anytype, slot_names: []const []const u8, param: []const u8) Value {
    if (frame.ref_slots.get(param)) |cell| return if (cell.* == .undef) .null else cell.*;
    for (slot_names, 0..) |sn, i| {
        if (std.mem.eql(u8, sn, param)) {
            if (i < frame.locals.len) return if (frame.locals[i] == .undef) .null else frame.locals[i];
            break;
        }
    }
    const v = frame.vars.get(param) orelse return .null;
    return if (v == .undef) .null else v;
}

// php's ZEND_CALL_CODE check: the arguments functions need a function frame
fn requireFunctionFrame(ctx: *NativeContext, comptime msg: []const u8) RuntimeError!*const @import("../pipeline/bytecode.zig").ObjFunction {
    if (ctx.vm.currentFrame().func) |func| return func;
    try ctx.vm.setPendingException("Error", msg);
    return error.RuntimeError;
}

fn native_func_get_args(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const declared = try requireFunctionFrame(ctx, "func_get_args() cannot be called from the global scope");
    const arr = try ctx.createArray();

    // a resumed generator's frame has no saved arguments: its parameters
    // hold them
    const in_generator = ctx.vm.currentFrame().generator != null;
    if (if (in_generator) null else ctx.vm.getFrameArgs()) |saved_args| {
        // declared parameters as they are now, the extra ones as passed
        const frame = ctx.vm.currentFrame();
        const fixed: usize = if (declared.is_variadic) declared.arity - 1 else declared.arity;
        for (saved_args, 0..) |val, i| {
            try arr.append(ctx.allocator, if (i < fixed and i < declared.params.len) getFrameParamValue(frame, declared.slot_names, declared.params[i]) else val);
        }
        return NativeResult.borrowed(.{ .array = arr });
    }

    const frame = ctx.vm.currentFrame();
    const func = frame.func orelse return NativeResult.borrowed(.{ .array = arr });
    const slot_names = func.slot_names;
    const actual_ac: usize = if (in_generator) func.arity else if (ctx.vm.getFrameArgCount()) |ac| ac else func.arity;

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
        if (frame.generator) |gen| for (gen.extra_args.items) |extra| try arr.append(ctx.allocator, extra);
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_func_num_args(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const frame = ctx.vm.currentFrame();
    const func = try requireFunctionFrame(ctx, "func_num_args() must be called from a function context");

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
    const idx = try (@import("html.zig").Params{ .ctx = ctx, .func = "func_get_arg", .args = args }).int(0, "position", 0);
    if (idx < 0) {
        try ctx.vm.setPendingException("ValueError", "func_get_arg(): Argument #1 ($position) must be greater than or equal to 0");
        return error.RuntimeError;
    }
    const declared = try requireFunctionFrame(ctx, "func_get_arg() cannot be called from the global scope");
    const index: usize = @intCast(idx);
    const passed: usize = if (ctx.vm.getFrameArgCount()) |ac| ac else declared.arity;
    if (index >= passed) {
        try ctx.vm.setPendingException("ValueError", "func_get_arg(): Argument #1 ($position) must be less than the number of the arguments passed to the currently executed function");
        return error.RuntimeError;
    }

    if (ctx.vm.getFrameArgs()) |saved_args| {
        const fixed: usize = if (declared.is_variadic) declared.arity - 1 else declared.arity;
        if (index < fixed and index < declared.params.len) return NativeResult.share(getFrameParamValue(ctx.vm.currentFrame(), declared.slot_names, declared.params[index]));
        if (index < saved_args.len) return NativeResult.share(saved_args[index]);
        return NativeResult.scalar(.null);
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
            var str_buf = std.ArrayListUnmanaged(u8).empty;
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
            var cleaned = std.ArrayListUnmanaged(u8).empty;
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
            var int_buf: [32]u8 = undefined;
            const s = if (value == .string) value.string.bytes() else if (value == .int) std.fmt.bufPrint(&int_buf, "{d}", .{value.int}) catch unreachable else return NativeResult.share(fail_default);
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
            var buf = std.ArrayListUnmanaged(u8).empty;
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
            var buf = std.ArrayListUnmanaged(u8).empty;
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
            var buf = std.ArrayListUnmanaged(u8).empty;
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
            var buf = std.ArrayListUnmanaged(u8).empty;
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
            var buf = std.ArrayListUnmanaged(u8).empty;
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
    var buf = std.ArrayListUnmanaged(u8).empty;
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
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("TypeError", msg);
    return error.RuntimeError;
}

fn native_spl_object_hash(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    var id: u64 = 0;
    switch (args[0]) {
        .object => |o| {
            if (o.id == 0) o.id = try ctx.vm.allocHandle();
            id = o.id;
        },
        .generator => |g| id = g.handle,
        .fiber => |f| id = f.handle,
        else => return throwObjectArg(ctx, "spl_object_hash", args[0]),
    }
    // PHP format: 16 hex chars of id, then 16 zeros
    const hash = try std.fmt.allocPrint(ctx.allocator, "{x:0>16}0000000000000000", .{id});
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, hash));
}

// php's php_count_recursive: an array met again inside its own count warns
// and counts as nothing
fn countRecursive(ctx: *NativeContext, func: []const u8, a: *PhpArray) RuntimeError!i64 {
    const Recursion = @import("../runtime/value.zig").Recursion;
    if (a.recursion & Recursion.gc != 0) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): Recursion detected", .{func});
        defer ctx.allocator.free(msg);
        try ctx.vm.emitWarning(msg);
        return 0;
    }
    a.recursion |= Recursion.gc;
    defer a.recursion &= ~Recursion.gc;
    var total: i64 = a.length();
    var i: usize = 0;
    while (i < a.entries.items.len) : (i += 1) {
        const entry = a.entries.items[i];
        const v = if (entry.ref) |cell| cell.* else entry.value;
        if (v == .array) total += try countRecursive(ctx, func, v.array);
    }
    return total;
}

// count() and sizeof()
pub fn countAs(ctx: *NativeContext, func: []const u8, args: []const Value) RuntimeError!NativeResult {
    const params = @import("html.zig").Params{ .ctx = ctx, .func = func, .args = args };
    const mode = try params.int(1, "mode", 0);
    if (mode != 0 and mode != 1) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): Argument #2 ($mode) must be either COUNT_NORMAL or COUNT_RECURSIVE", .{func});
        defer ctx.allocator.free(msg);
        try ctx.vm.setPendingException("ValueError", msg);
        return error.RuntimeError;
    }
    switch (args[0]) {
        .array => |a| return NativeResult.scalar(.{ .int = if (mode == 1) try countRecursive(ctx, func, a) else a.length() }),
        .object => |obj| if (ctx.vm.isInstanceOf(obj.class_name, "Countable") and ctx.vm.hasMethod(obj.class_name, "count")) {
            const r = try ctx.vm.callMethod(obj, "count", &.{});
            // zval_get_long: an object without a cast warns and counts as 1
            if (r == .object and @import("../runtime/value.zig").nativeCast(r.object, .int) == null) {
                const m = try std.fmt.allocPrint(ctx.allocator, "Object of class {s} could not be converted to int", .{r.object.class_name});
                defer ctx.allocator.free(m);
                try ctx.vm.emitWarning(m);
            }
            return NativeResult.scalar(.{ .int = switch (r) {
                .int => |n| n,
                .float => |f| if (Value.floatFitsInt(f)) @intFromFloat(@trunc(f)) else 0,
                else => Value.toInt(r),
            } });
        },
        else => {},
    }
    const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): Argument #1 ($value) must be of type Countable|array, {s} given", .{ func, phpTypeName(args[0]) });
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("TypeError", msg);
    return error.RuntimeError;
}

fn count(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return countAs(ctx, "count", args);
}

// get_resources(?string $type = null): the live resources by id, of one
// type when asked ("Unknown" for the closed ones)
fn native_get_resources(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = @import("html.zig").Params{ .ctx = ctx, .func = "get_resources", .args = args };
    const want: ?[]const u8 = if (args.len > 0 and args[0] != .null) try p.string(0, "type", "") else null;
    if (want) |t| {
        // the resource types php registers (zend_fetch_list_dtor_id), and the
        // closed ones
        const known = [_][]const u8{ "Unknown", "stream", "persistent stream", "stream-context", "stream filter", "process", "userfilter.bucket brigade", "userfilter.bucket", "stream_wrapper" };
        var valid = false;
        for (known) |k| if (std.mem.eql(u8, k, t)) {
            valid = true;
        };
        if (!valid) {
            try ctx.vm.setPendingException("ValueError", "get_resources(): Argument #1 ($type) must be a valid resource type");
            return error.RuntimeError;
        }
    }
    var live: std.ArrayListUnmanaged(*PhpObject) = .empty;
    defer live.deinit(ctx.allocator);
    for (ctx.vm.objects.items) |obj| {
        if (!obj.resource or obj.pooled or obj.destructed or obj.id == 0) continue;
        if (want) |t| if (!std.mem.eql(u8, value_mod.resourceTypeName(obj), t)) continue;
        try live.append(ctx.allocator, obj);
    }
    std.mem.sort(*PhpObject, live.items, {}, struct {
        fn lt(_: void, a: *PhpObject, b: *PhpObject) bool {
            return a.id < b.id;
        }
    }.lt);
    const arr = try ctx.createArray();
    for (live.items) |obj| try arr.set(ctx.allocator, .{ .int = obj.id }, .{ .resource = obj });
    return NativeResult.borrowed(.{ .array = arr });
}
