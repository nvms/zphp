const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
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
    .{ "var_dump", var_dump },
    .{ "print_r", print_r },
    .{ "boolval", boolval },
    .{ "define", native_define },
    .{ "defined", native_defined },
    .{ "constant", native_constant },
    .{ "var_export", native_var_export },
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

fn count(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
    return switch (args[0]) {
        .array => |a| .{ .int = a.length() },
        else => .{ .int = 1 },
    };
}

fn intval(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .int = 0 };
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
        .object, .generator => "object",
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

fn var_dump(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    for (args) |arg| try varDumpValue(ctx, arg, 0);
    return .null;
}

fn varDumpValue(ctx: *NativeContext, val: Value, depth: usize) !void {
    const out = &ctx.vm.output;
    const a = ctx.allocator;
    const indent = depth * 2;
    switch (val) {
        .null => {
            try appendIndent(out, a, indent);
            try out.appendSlice(a, "NULL\n");
        },
        .bool => |b| {
            try appendIndent(out, a, indent);
            try out.appendSlice(a, if (b) "bool(true)\n" else "bool(false)\n");
        },
        .int => |i| {
            try appendIndent(out, a, indent);
            try out.appendSlice(a, "int(");
            var tmp: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return;
            try out.appendSlice(a, s);
            try out.appendSlice(a, ")\n");
        },
        .float => |f| {
            try appendIndent(out, a, indent);
            try out.appendSlice(a, "float(");
            var tmp: [64]u8 = undefined;
            const s = formatFloat(&tmp, f);
            try out.appendSlice(a, s);
            try out.appendSlice(a, ")\n");
        },
        .string => |s| {
            try appendIndent(out, a, indent);
            try out.appendSlice(a, "string(");
            var tmp: [32]u8 = undefined;
            const len_s = std.fmt.bufPrint(&tmp, "{d}", .{s.len}) catch return;
            try out.appendSlice(a, len_s);
            try out.appendSlice(a, ") \"");
            try out.appendSlice(a, s);
            try out.appendSlice(a, "\"\n");
        },
        .array => |arr| {
            try appendIndent(out, a, indent);
            try out.appendSlice(a, "array(");
            var tmp: [32]u8 = undefined;
            const len_s = std.fmt.bufPrint(&tmp, "{d}", .{arr.entries.items.len}) catch return;
            try out.appendSlice(a, len_s);
            try out.appendSlice(a, ") {\n");
            for (arr.entries.items) |entry| {
                try appendIndent(out, a, indent + 2);
                switch (entry.key) {
                    .int => |ki| {
                        try out.appendSlice(a, "[");
                        const ks = std.fmt.bufPrint(&tmp, "{d}", .{ki}) catch return;
                        try out.appendSlice(a, ks);
                        try out.appendSlice(a, "]=>\n");
                    },
                    .string => |ks| {
                        try out.appendSlice(a, "[\"");
                        try out.appendSlice(a, ks);
                        try out.appendSlice(a, "\"]=>\n");
                    },
                }
                try varDumpValue(ctx, entry.value, depth + 1);
            }
            try appendIndent(out, a, indent);
            try out.appendSlice(a, "}\n");
        },
        .object => |obj| {
            try appendIndent(out, a, indent);
            try out.appendSlice(a, "object(");
            try out.appendSlice(a, obj.class_name);
            try out.appendSlice(a, ")#1 (0) {\n");
            try appendIndent(out, a, indent);
            try out.appendSlice(a, "}\n");
        },
        .generator => {
            try appendIndent(out, a, indent);
            try out.appendSlice(a, "object(Generator)#1 (0) {\n");
            try appendIndent(out, a, indent);
            try out.appendSlice(a, "}\n");
        },
    }
}

fn print_r(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .null;
    const return_str = args.len >= 2 and args[1].isTruthy();
    if (return_str) {
        var buf = std.ArrayListUnmanaged(u8){};
        try printRValue(ctx.allocator, &buf, args[0], 0);
        const s = try buf.toOwnedSlice(ctx.allocator);
        try ctx.strings.append(ctx.allocator, s);
        return .{ .string = s };
    }
    try printRValue(ctx.allocator, &ctx.vm.output, args[0], 0);
    return .{ .bool = true };
}

fn printRValue(a: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8), val: Value, depth: usize) !void {
    switch (val) {
        .null => {},
        .bool => |b| if (b) try out.appendSlice(a, "1"),
        .int => |i| {
            var tmp: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return;
            try out.appendSlice(a, s);
        },
        .float => |f| {
            var tmp: [64]u8 = undefined;
            const s = formatFloat(&tmp, f);
            try out.appendSlice(a, s);
        },
        .string => |s| try out.appendSlice(a, s),
        .array => |arr| {
            try out.appendSlice(a, "Array\n");
            try appendIndent(out, a, depth * 4);
            try out.appendSlice(a, "(\n");
            for (arr.entries.items) |entry| {
                try appendIndent(out, a, (depth + 1) * 4);
                switch (entry.key) {
                    .int => |ki| {
                        try out.appendSlice(a, "[");
                        var tmp: [32]u8 = undefined;
                        const ks = std.fmt.bufPrint(&tmp, "{d}", .{ki}) catch return;
                        try out.appendSlice(a, ks);
                        try out.appendSlice(a, "] => ");
                    },
                    .string => |ks| {
                        try out.appendSlice(a, "[");
                        try out.appendSlice(a, ks);
                        try out.appendSlice(a, "] => ");
                    },
                }
                if (entry.value == .array) {
                    try printRValue(a, out, entry.value, depth + 2);
                } else {
                    try printRValue(a, out, entry.value, depth + 1);
                    try out.appendSlice(a, "\n");
                }
            }
            try appendIndent(out, a, depth * 4);
            try out.appendSlice(a, ")\n");
        },
        .object => |obj| {
            try out.appendSlice(a, obj.class_name);
            try out.appendSlice(a, " Object\n");
            try appendIndent(out, a, depth * 4);
            try out.appendSlice(a, "(\n");
            try appendIndent(out, a, depth * 4);
            try out.appendSlice(a, ")\n");
        },
        .generator => {
            try out.appendSlice(a, "Generator Object\n");
            try appendIndent(out, a, depth * 4);
            try out.appendSlice(a, "(\n");
            try appendIndent(out, a, depth * 4);
            try out.appendSlice(a, ")\n");
        },
    }
}

fn appendIndent(out: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, n: usize) !void {
    for (0..n) |_| try out.append(a, ' ');
}

fn formatFloat(tmp: *[64]u8, f: f64) []const u8 {
    if (std.math.isNan(f)) return "NAN";
    if (std.math.isInf(f)) return if (f > 0) "INF" else "-INF";
    if (f == @trunc(f) and @abs(f) < 1e15) {
        const i: i64 = @intFromFloat(f);
        return std.fmt.bufPrint(tmp, "{d}", .{i}) catch "0";
    }
    return std.fmt.bufPrint(tmp, "{d}", .{f}) catch "0";
}

fn boolval(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .bool = false };
    return .{ .bool = args[0].isTruthy() };
}

fn is_object(_: *NativeContext, args: []const Value) RuntimeError!Value {
    return .{ .bool = args.len > 0 and args[0] == .object };
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
    if (args.len < 2 or args[1] != .string) return .{ .bool = false };
    const type_name = args[1].string;
    const val = args[0];
    const converted: Value = if (std.mem.eql(u8, type_name, "int") or std.mem.eql(u8, type_name, "integer"))
        .{ .int = Value.toInt(val) }
    else if (std.mem.eql(u8, type_name, "float") or std.mem.eql(u8, type_name, "double"))
        .{ .float = Value.toFloat(val) }
    else if (std.mem.eql(u8, type_name, "string"))
        blk: {
            if (val == .string) break :blk val;
            var buf = std.ArrayListUnmanaged(u8){};
            try val.format(&buf, ctx.allocator);
            const s = try buf.toOwnedSlice(ctx.allocator);
            try ctx.strings.append(ctx.allocator, s);
            break :blk Value{ .string = s };
        }
    else if (std.mem.eql(u8, type_name, "bool") or std.mem.eql(u8, type_name, "boolean"))
        .{ .bool = val.isTruthy() }
    else if (std.mem.eql(u8, type_name, "null"))
        .null
    else
        return Value{ .bool = false };
    _ = converted;
    return .{ .bool = true };
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

fn native_var_export(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .null;
    const return_str = args.len >= 2 and args[1].isTruthy();
    var buf = std.ArrayListUnmanaged(u8){};
    try varExportValue(ctx.allocator, &buf, args[0], 0);
    if (return_str) {
        const s = try buf.toOwnedSlice(ctx.allocator);
        try ctx.strings.append(ctx.allocator, s);
        return .{ .string = s };
    }
    try ctx.vm.output.appendSlice(ctx.allocator, buf.items);
    buf.deinit(ctx.allocator);
    return .null;
}

fn varExportValue(a: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8), val: Value, depth: usize) !void {
    switch (val) {
        .null => try out.appendSlice(a, "NULL"),
        .bool => |b| try out.appendSlice(a, if (b) "true" else "false"),
        .int => |i| {
            var tmp: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return;
            try out.appendSlice(a, s);
        },
        .float => |f| {
            var tmp: [64]u8 = undefined;
            if (f == @trunc(f) and @abs(f) < 1e15) {
                const i: i64 = @intFromFloat(f);
                const s = std.fmt.bufPrint(&tmp, "{d}.0", .{i}) catch return;
                try out.appendSlice(a, s);
            } else {
                const s = std.fmt.bufPrint(&tmp, "{d}", .{f}) catch return;
                try out.appendSlice(a, s);
            }
        },
        .string => |s| {
            try out.append(a, '\'');
            for (s) |c| {
                if (c == '\'') {
                    try out.appendSlice(a, "\\'");
                } else if (c == '\\') {
                    try out.appendSlice(a, "\\\\");
                } else {
                    try out.append(a, c);
                }
            }
            try out.append(a, '\'');
        },
        .array => |arr| {
            try out.appendSlice(a, "array (\n");
            for (arr.entries.items) |entry| {
                for (0..(depth + 1) * 2) |_| try out.append(a, ' ');
                switch (entry.key) {
                    .int => |ki| {
                        var tmp: [32]u8 = undefined;
                        const ks = std.fmt.bufPrint(&tmp, "{d}", .{ki}) catch return;
                        try out.appendSlice(a, ks);
                    },
                    .string => |ks| {
                        try out.append(a, '\'');
                        try out.appendSlice(a, ks);
                        try out.append(a, '\'');
                    },
                }
                try out.appendSlice(a, " => ");
                try varExportValue(a, out, entry.value, depth + 1);
                try out.appendSlice(a, ",\n");
            }
            for (0..depth * 2) |_| try out.append(a, ' ');
            try out.append(a, ')');
        },
        .object => try out.appendSlice(a, "(object)"),
        .generator => try out.appendSlice(a, "(object)"),
    }
}
