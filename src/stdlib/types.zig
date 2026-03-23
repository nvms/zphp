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
        .object => "object",
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
