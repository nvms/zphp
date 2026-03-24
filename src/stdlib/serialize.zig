const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "serialize", native_serialize },
    .{ "unserialize", native_unserialize },
    .{ "json_last_error", native_json_last_error },
    .{ "json_last_error_msg", native_json_last_error_msg },
};

fn native_serialize(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    var buf = std.ArrayListUnmanaged(u8){};
    try serializeValue(&buf, ctx.allocator, args[0]);
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn serializeValue(buf: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, val: Value) !void {
    switch (val) {
        .null => try buf.appendSlice(a, "N;"),
        .bool => |b| {
            try buf.appendSlice(a, if (b) "b:1;" else "b:0;");
        },
        .int => |i| {
            try buf.appendSlice(a, "i:");
            var tmp: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return;
            try buf.appendSlice(a, s);
            try buf.append(a, ';');
        },
        .float => |f| {
            try buf.appendSlice(a, "d:");
            var tmp: [64]u8 = undefined;
            const s = std.fmt.bufPrint(&tmp, "{d}", .{f}) catch return;
            try buf.appendSlice(a, s);
            try buf.append(a, ';');
        },
        .string => |str| {
            try buf.appendSlice(a, "s:");
            var tmp: [20]u8 = undefined;
            const len_s = std.fmt.bufPrint(&tmp, "{d}", .{str.len}) catch return;
            try buf.appendSlice(a, len_s);
            try buf.appendSlice(a, ":\"");
            try buf.appendSlice(a, str);
            try buf.appendSlice(a, "\";");
        },
        .array => |arr| {
            try buf.appendSlice(a, "a:");
            var tmp: [20]u8 = undefined;
            const len_s = std.fmt.bufPrint(&tmp, "{d}", .{arr.entries.items.len}) catch return;
            try buf.appendSlice(a, len_s);
            try buf.appendSlice(a, ":{");
            for (arr.entries.items) |entry| {
                switch (entry.key) {
                    .int => |i| {
                        try buf.appendSlice(a, "i:");
                        const ki = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return;
                        try buf.appendSlice(a, ki);
                        try buf.append(a, ';');
                    },
                    .string => |s| {
                        try buf.appendSlice(a, "s:");
                        const ks = std.fmt.bufPrint(&tmp, "{d}", .{s.len}) catch return;
                        try buf.appendSlice(a, ks);
                        try buf.appendSlice(a, ":\"");
                        try buf.appendSlice(a, s);
                        try buf.appendSlice(a, "\";");
                    },
                }
                try serializeValue(buf, a, entry.value);
            }
            try buf.append(a, '}');
        },
        .object => |obj| {
            try buf.appendSlice(a, "O:");
            var tmp: [20]u8 = undefined;
            const nl = std.fmt.bufPrint(&tmp, "{d}", .{obj.class_name.len}) catch return;
            try buf.appendSlice(a, nl);
            try buf.appendSlice(a, ":\"");
            try buf.appendSlice(a, obj.class_name);
            try buf.appendSlice(a, "\":");
            const count = obj.properties.count();
            const cl = std.fmt.bufPrint(&tmp, "{d}", .{count}) catch return;
            try buf.appendSlice(a, cl);
            try buf.appendSlice(a, ":{");
            var iter = obj.properties.iterator();
            while (iter.next()) |entry| {
                const k = entry.key_ptr.*;
                try buf.appendSlice(a, "s:");
                const ks = std.fmt.bufPrint(&tmp, "{d}", .{k.len}) catch return;
                try buf.appendSlice(a, ks);
                try buf.appendSlice(a, ":\"");
                try buf.appendSlice(a, k);
                try buf.appendSlice(a, "\";");
                try serializeValue(buf, a, entry.value_ptr.*);
            }
            try buf.append(a, '}');
        },
        else => try buf.appendSlice(a, "N;"),
    }
}

fn native_unserialize(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return Value{ .bool = false };
    const s = args[0].string;
    const result = unserializeValue(ctx, s, 0) catch return Value{ .bool = false };
    return result.value;
}

const ParseResult = struct {
    value: Value,
    pos: usize,
};

fn unserializeValue(ctx: *NativeContext, s: []const u8, pos: usize) !ParseResult {
    if (pos >= s.len) return error.RuntimeError;

    switch (s[pos]) {
        'N' => {
            if (pos + 1 < s.len and s[pos + 1] == ';') {
                return .{ .value = .null, .pos = pos + 2 };
            }
            return error.RuntimeError;
        },
        'b' => {
            if (pos + 3 < s.len and s[pos + 1] == ':' and s[pos + 3] == ';') {
                return .{ .value = .{ .bool = s[pos + 2] == '1' }, .pos = pos + 4 };
            }
            return error.RuntimeError;
        },
        'i' => {
            if (pos + 2 >= s.len or s[pos + 1] != ':') return error.RuntimeError;
            const start = pos + 2;
            const end = std.mem.indexOfPos(u8, s, start, ";") orelse return error.RuntimeError;
            const i = std.fmt.parseInt(i64, s[start..end], 10) catch return error.RuntimeError;
            return .{ .value = .{ .int = i }, .pos = end + 1 };
        },
        'd' => {
            if (pos + 2 >= s.len or s[pos + 1] != ':') return error.RuntimeError;
            const start = pos + 2;
            const end = std.mem.indexOfPos(u8, s, start, ";") orelse return error.RuntimeError;
            const f = std.fmt.parseFloat(f64, s[start..end]) catch return error.RuntimeError;
            return .{ .value = .{ .float = f }, .pos = end + 1 };
        },
        's' => {
            const r = try parseString(s, pos);
            return .{ .value = .{ .string = try ctx.createString(r.str) }, .pos = r.pos };
        },
        'a' => {
            if (pos + 2 >= s.len or s[pos + 1] != ':') return error.RuntimeError;
            const count_start = pos + 2;
            const colon = std.mem.indexOfPos(u8, s, count_start, ":") orelse return error.RuntimeError;
            const count = std.fmt.parseInt(usize, s[count_start..colon], 10) catch return error.RuntimeError;
            if (colon + 1 >= s.len or s[colon + 1] != '{') return error.RuntimeError;
            var p = colon + 2;
            var arr = try ctx.createArray();
            for (0..count) |_| {
                const key_result = try unserializeValue(ctx, s, p);
                p = key_result.pos;
                const val_result = try unserializeValue(ctx, s, p);
                p = val_result.pos;
                const key: PhpArray.Key = switch (key_result.value) {
                    .int => |i| .{ .int = i },
                    .string => |str| .{ .string = str },
                    else => .{ .int = 0 },
                };
                try arr.set(ctx.allocator, key, val_result.value);
            }
            if (p < s.len and s[p] == '}') p += 1;
            return .{ .value = .{ .array = arr }, .pos = p };
        },
        'O' => {
            // object unserialization: create a plain object with the class name
            if (pos + 2 >= s.len or s[pos + 1] != ':') return error.RuntimeError;
            const name_result = try parseString(s, pos + 2 - 2);
            // re-parse: O:len:"name":count:{...}
            const colon1 = std.mem.indexOfPos(u8, s, pos + 2, ":") orelse return error.RuntimeError;
            const name_len = std.fmt.parseInt(usize, s[pos + 2 .. colon1], 10) catch return error.RuntimeError;
            if (colon1 + 2 + name_len + 1 >= s.len) return error.RuntimeError;
            const class_name = s[colon1 + 2 .. colon1 + 2 + name_len];
            _ = name_result;
            var p = colon1 + 2 + name_len + 2; // past closing quote and colon
            const count_end = std.mem.indexOfPos(u8, s, p, ":") orelse return error.RuntimeError;
            const prop_count = std.fmt.parseInt(usize, s[p..count_end], 10) catch return error.RuntimeError;
            if (count_end + 1 >= s.len or s[count_end + 1] != '{') return error.RuntimeError;
            p = count_end + 2;

            const obj = try ctx.allocator.create(@import("../runtime/value.zig").PhpObject);
            obj.* = .{ .class_name = class_name };

            for (0..prop_count) |_| {
                const key_result = try unserializeValue(ctx, s, p);
                p = key_result.pos;
                const val_result = try unserializeValue(ctx, s, p);
                p = val_result.pos;
                if (key_result.value == .string) {
                    try obj.set(ctx.allocator, key_result.value.string, val_result.value);
                }
            }
            if (p < s.len and s[p] == '}') p += 1;
            return .{ .value = .{ .object = obj }, .pos = p };
        },
        else => return error.RuntimeError,
    }
}

const StringResult = struct { str: []const u8, pos: usize };

fn parseString(s: []const u8, pos: usize) !StringResult {
    // s:LEN:"...";
    if (pos + 2 >= s.len or s[pos + 1] != ':') return error.RuntimeError;
    const len_start = pos + 2;
    const colon = std.mem.indexOfPos(u8, s, len_start, ":") orelse return error.RuntimeError;
    const str_len = std.fmt.parseInt(usize, s[len_start..colon], 10) catch return error.RuntimeError;
    if (colon + 1 >= s.len or s[colon + 1] != '"') return error.RuntimeError;
    const str_start = colon + 2;
    if (str_start + str_len > s.len) return error.RuntimeError;
    const str = s[str_start .. str_start + str_len];
    const end = str_start + str_len;
    if (end + 1 >= s.len or s[end] != '"' or s[end + 1] != ';') return error.RuntimeError;
    return .{ .str = str, .pos = end + 2 };
}

fn native_json_last_error(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = 0 };
}

fn native_json_last_error_msg(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .string = "No error" };
}