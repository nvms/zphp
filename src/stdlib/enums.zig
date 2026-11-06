const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

fn enumClassFromCallName(ctx: *NativeContext) ?[]const u8 {
    const name = ctx.call_name orelse return null;
    if (std.mem.indexOf(u8, name, "::")) |sep| return name[0..sep];
    return null;
}

pub fn enumCases(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const enum_name = enumClassFromCallName(ctx) orelse return error.RuntimeError;
    const def = ctx.vm.classes.get(enum_name) orelse return error.RuntimeError;
    var arr = try ctx.createArray();
    for (def.case_order.items) |name| {
        if (def.constants.get(name)) |val| {
            try arr.append(ctx.allocator, ctx.vm.enumCase(val));
        }
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn coerceForLookup(ctx: *NativeContext, def_backed: anytype, arg: Value) !Value {
    return switch (def_backed) {
        .int_type => switch (arg) {
            .int => arg,
            .bool => |b| .{ .int = if (b) 1 else 0 },
            .null => .{ .int = 0 },
            .float => |f| .{ .int = @intFromFloat(f) },
            .string => |s| blk: {
                const i = std.fmt.parseInt(i64, s.bytes(), 10) catch break :blk arg;
                break :blk .{ .int = i };
            },
            else => arg,
        },
        .string_type => switch (arg) {
            .string => arg,
            .bool => |b| .{ .string = Value.String.borrowed(if (b) "1" else "0") },
            .null => .{ .string = Value.String.borrowed("0") },
            .int => .{ .string = try ctx.vm.transientFormatted(arg) },
            .float => |f| blk: {
                // the int|string parameter takes an integral-range float as
                // an int (truncating), anything else as its string form
                var buf: std.ArrayListUnmanaged(u8) = .empty;
                defer buf.deinit(ctx.allocator);
                if (Value.floatFitsInt(f)) {
                    try buf.print(ctx.allocator, "{d}", .{@as(i64, @intFromFloat(f))});
                } else try arg.format(&buf, ctx.allocator);
                break :blk .{ .string = try ctx.vm.transientAdopted(try buf.toOwnedSlice(ctx.allocator)) };
            },
            else => arg,
        },
        else => arg,
    };
}

fn throwBuiltin(ctx: *NativeContext, class: []const u8, msg: []const u8) RuntimeError!Value {
    _ = try ctx.vm.throwBuiltinException(class, msg);
    return error.RuntimeError;
}

fn argDisplayString(ctx: *NativeContext, arg: Value) ![]const u8 {
    return switch (arg) {
        .string => |s| (try ctx.vm.transientAdopted(try std.fmt.allocPrint(ctx.allocator, "\"{s}\"", .{s.bytes()}))).bytes(),
        .int => (try ctx.vm.transientFormatted(arg)).bytes(),
        else => "value",
    };
}

fn isNumericIntStr(s: []const u8) bool {
    if (s.len == 0) return false;
    var i: usize = 0;
    if (s[0] == '+' or s[0] == '-') i = 1;
    if (i >= s.len) return false;
    while (i < s.len) : (i += 1) {
        if (s[i] < '0' or s[i] > '9') return false;
    }
    return true;
}

fn checkEnumArgType(ctx: *NativeContext, backed: anytype, enum_name: []const u8, fn_name: []const u8, arg: Value) RuntimeError!?Value {
    const want: []const u8 = switch (backed) {
        .int_type => "int",
        .string_type => "string|int",
        else => return null,
    };
    const ok: bool = switch (backed) {
        // PHP coerces scalars+null; only array/object/resource are rejected
        .int_type => arg == .int or (arg == .float and Value.floatFitsInt(arg.float)) or arg == .bool or arg == .null or (arg == .string and isNumericIntStr(arg.string.bytes())),
        .string_type => arg == .string or arg == .int or arg == .float or arg == .bool or arg == .null,
        else => true,
    };
    if (ok) return null;
    const msg = try std.fmt.allocPrint(ctx.allocator, "{s}::{s}(): Argument #1 ($value) must be of type {s}, {s} given", .{ enum_name, fn_name, want, arg.typeName() });
    defer ctx.allocator.free(msg);
    _ = try throwBuiltin(ctx, "TypeError", msg);
    return null;
}

pub fn enumFrom(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return error.RuntimeError;
    const enum_name = enumClassFromCallName(ctx) orelse return error.RuntimeError;
    const def = ctx.vm.classes.get(enum_name) orelse return error.RuntimeError;
    if (try checkEnumArgType(ctx, def.backed_type, enum_name, "from", args[0])) |err_val| return NativeResult.borrowed(err_val);
    const lookup = try coerceForLookup(ctx, def.backed_type, args[0]);
    var iter = def.constants.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.* == .object) {
            const case_val = entry.value_ptr.*.object.get("value");
            if (Value.identical(case_val, lookup)) return NativeResult.borrowed(ctx.vm.enumCase(entry.value_ptr.*));
        }
    }
    const arg_str = try argDisplayString(ctx, lookup);
    const msg = try std.fmt.allocPrint(ctx.allocator, "{s} is not a valid backing value for enum {s}", .{ arg_str, enum_name });
    defer ctx.allocator.free(msg);
    _ = try throwBuiltin(ctx, "ValueError", msg);
    unreachable;
}

pub fn enumTryFrom(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.null);
    const enum_name = enumClassFromCallName(ctx) orelse return NativeResult.scalar(.null);
    const def = ctx.vm.classes.get(enum_name) orelse return NativeResult.scalar(.null);
    if (try checkEnumArgType(ctx, def.backed_type, enum_name, "tryFrom", args[0])) |err_val| return NativeResult.borrowed(err_val);
    const lookup = try coerceForLookup(ctx, def.backed_type, args[0]);
    var iter = def.constants.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.* == .object) {
            const case_val = entry.value_ptr.*.object.get("value");
            if (Value.identical(case_val, lookup)) return NativeResult.borrowed(ctx.vm.enumCase(entry.value_ptr.*));
        }
    }
    return NativeResult.scalar(.null);
}
