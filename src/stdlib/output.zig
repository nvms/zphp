const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "var_dump", var_dump },
    .{ "print_r", print_r },
    .{ "var_export", var_export },
};

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
        .generator, .fiber => {
            try appendIndent(out, a, indent);
            try out.appendSlice(a, if (val == .generator) "object(Generator)#1 (0) {\n" else "object(Fiber)#1 (0) {\n");
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
            if (obj.slot_layout) |layout| {
                if (obj.slots) |slots| {
                    for (layout.names, 0..) |name, i| {
                        if (i < slots.len) {
                            try appendIndent(out, a, (depth + 1) * 4);
                            try out.appendSlice(a, "[");
                            try out.appendSlice(a, name);
                            try out.appendSlice(a, "] => ");
                            if (slots[i] == .array) {
                                try printRValue(a, out, slots[i], depth + 2);
                            } else {
                                try printRValue(a, out, slots[i], depth + 1);
                                try out.appendSlice(a, "\n");
                            }
                        }
                    }
                }
            }
            var dyn_iter = obj.properties.iterator();
            while (dyn_iter.next()) |entry| {
                var in_slots = false;
                if (obj.slot_layout) |layout| {
                    for (layout.names) |sn| {
                        if (std.mem.eql(u8, sn, entry.key_ptr.*)) { in_slots = true; break; }
                    }
                }
                if (!in_slots) {
                    try appendIndent(out, a, (depth + 1) * 4);
                    try out.appendSlice(a, "[");
                    try out.appendSlice(a, entry.key_ptr.*);
                    try out.appendSlice(a, "] => ");
                    if (entry.value_ptr.* == .array) {
                        try printRValue(a, out, entry.value_ptr.*, depth + 2);
                    } else {
                        try printRValue(a, out, entry.value_ptr.*, depth + 1);
                        try out.appendSlice(a, "\n");
                    }
                }
            }
            try appendIndent(out, a, depth * 4);
            try out.appendSlice(a, ")\n");
        },
        .generator, .fiber => {
            try out.appendSlice(a, if (val == .generator) "Generator Object\n" else "Fiber Object\n");
            try appendIndent(out, a, depth * 4);
            try out.appendSlice(a, "(\n");
            try appendIndent(out, a, depth * 4);
            try out.appendSlice(a, ")\n");
        },
    }
}

fn var_export(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
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
        .object => |obj| {
            try out.appendSlice(a, "(object) array(\n");
            if (obj.slot_layout) |layout| {
                if (obj.slots) |slots| {
                    for (layout.names, 0..) |name, i| {
                        if (i < slots.len) {
                            for (0..(depth + 1) * 2) |_| try out.append(a, ' ');
                            try out.append(a, '\'');
                            try out.appendSlice(a, name);
                            try out.append(a, '\'');
                            try out.appendSlice(a, " => ");
                            try varExportValue(a, out, slots[i], depth + 1);
                            try out.appendSlice(a, ",\n");
                        }
                    }
                }
            }
            var dyn_iter = obj.properties.iterator();
            while (dyn_iter.next()) |entry| {
                var in_slots = false;
                if (obj.slot_layout) |layout| {
                    for (layout.names) |sn| {
                        if (std.mem.eql(u8, sn, entry.key_ptr.*)) { in_slots = true; break; }
                    }
                }
                if (!in_slots) {
                    for (0..(depth + 1) * 2) |_| try out.append(a, ' ');
                    try out.append(a, '\'');
                    try out.appendSlice(a, entry.key_ptr.*);
                    try out.append(a, '\'');
                    try out.appendSlice(a, " => ");
                    try varExportValue(a, out, entry.value_ptr.*, depth + 1);
                    try out.appendSlice(a, ",\n");
                }
            }
            for (0..depth * 2) |_| try out.append(a, ' ');
            try out.append(a, ')');
        },
        .generator, .fiber => try out.appendSlice(a, "(object)"),
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
