const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const value_mod = @import("../runtime/value.zig");
const class_names = @import("../runtime/class_names.zig");
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const ClassDef = @import("../runtime/vm.zig").ClassDef;
const object_properties = @import("../runtime/object_properties.zig");
const RuntimeError = error{ RuntimeError, OutOfMemory };

// recursion is detected with php's protection flags on the array or object
// itself (value.Recursion), so a dump nested in a __debugInfo or jsonSerialize
// sees what the outer one is inside. an object whose class uses guards has a
// flag per kind of walk; any other object, like an array, has the one flag
// every walk shares
const Recursion = value_mod.Recursion;

fn objectFlag(vm: ?*@import("../runtime/vm.zig").VM, obj: *value_mod.PhpObject, kind: u8) u8 {
    if (vm) |v| if (v.usesRecursionGuards(obj)) return kind;
    return Recursion.gc;
}

fn walking(v: Value, flag: u8) bool {
    return switch (v) {
        .array => |arr| arr.recursion & flag != 0,
        .object => |obj| obj.recursion & flag != 0,
        else => false,
    };
}

pub const entries = .{
    .{ "var_dump", var_dump },
    .{ "print_r", print_r },
    .{ "var_export", var_export },
    .{ "debug_zval_dump", debug_zval_dump },
};

// php's php_debug_zval_dump: var_dump's layout with each refcounted value's
// reference count, "interned" for strings and arrays php never counts, and
// "packed" for list-shaped arrays. the counts are zphp's own, less the holds
// this native call takes on its arguments; where zphp's model of sharing
// differs from php's, so do they
fn debug_zval_dump(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (ctx.vm.hasPendingReleases()) ctx.vm.drainPendingDestruct();
    for (args) |arg| try debugZvalDump(ctx, arg, 1, true);
    return NativeResult.scalar(.null);
}

// the holds the call takes on an argument beyond the one php counts for it,
// measured against php for an argument read from a variable (a temporary
// object or string shows one more than php does)
const call_holds_scalar: u32 = 1;
const call_holds_array: u32 = 1;

fn dumpIndent(out: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, level: usize) !void {
    if (level > 1) try appendIndent(out, a, level - 1);
}

fn isPacked(arr: *value_mod.PhpArray) bool {
    var last: i64 = -1;
    for (arr.entries.items) |entry| {
        if (entry.key != .int or entry.key.int <= last) return false;
        last = entry.key.int;
    }
    return true;
}

fn debugZvalDump(ctx: *NativeContext, val: Value, level: usize, top: bool) RuntimeError!void {
    const out = &ctx.vm.output;
    const a = ctx.allocator;
    try dumpIndent(out, a, level);
    switch (val) {
        .null, .undef => try out.appendSlice(a, "NULL\n"),
        .bool => |b| try out.appendSlice(a, if (b) "bool(true)\n" else "bool(false)\n"),
        .int => |i| try out.print(a, "int({d})\n", .{i}),
        .float => |f| {
            var tmp: [64]u8 = undefined;
            try out.print(a, "float({s})\n", .{formatSerializedFloat(&tmp, f)});
        },
        .string => |s| {
            try out.print(a, "string({d}) \"", .{s.len});
            try out.appendSlice(a, s.bytes());
            // php interns literals and every string of at most one byte
            if (s.owner) |owner| if (s.len > 1) {
                const rc = if (top) owner.refcount -| call_holds_scalar else owner.refcount;
                try out.print(a, "\" refcount({d})\n", .{@max(rc, 1)});
                return;
            };
            try out.appendSlice(a, "\" interned\n");
        },
        .array => |arr| {
            if (arr.recursion & Recursion.gc != 0) {
                try out.appendSlice(a, "*RECURSION*\n");
                return;
            }
            const count = arr.entries.items.len;
            const packed_text: []const u8 = if (isPacked(arr)) "packed " else "";
            if (count == 0) {
                try out.appendSlice(a, "array(0) interned {\n");
            } else {
                const rc = if (top) arr.refcount -| call_holds_array else arr.refcount;
                try out.print(a, "array({d}) {s}refcount({d}){{\n", .{ count, packed_text, @max(rc, 1) });
            }
            arr.recursion |= Recursion.gc;
            defer arr.recursion &= ~Recursion.gc;
            for (arr.entries.items) |entry| {
                try appendIndent(out, a, level + 1);
                switch (entry.key) {
                    .int => |ki| try out.print(a, "[{d}]=>\n", .{ki}),
                    .string => |ks| {
                        try out.appendSlice(a, "[\"");
                        try out.appendSlice(a, ks.bytes());
                        try out.appendSlice(a, "\"]=>\n");
                    },
                }
                if (entry.ref) |cell| {
                    try dumpReference(ctx, cell, cell.*, level + 2);
                } else {
                    try debugZvalDump(ctx, entry.value, level + 2, false);
                }
            }
            try dumpIndent(out, a, level);
            try out.appendSlice(a, "}\n");
        },
        .object => |obj| {
            const flag = objectFlag(ctx.vm, obj, Recursion.debug);
            if (obj.recursion & flag != 0) {
                try out.appendSlice(a, "*RECURSION*\n");
                return;
            }
            obj.recursion |= flag;
            defer obj.recursion &= ~flag;
            const rc = if (top) obj.refcount -| call_holds_scalar else obj.refcount;
            if (ctx.vm.classes.get(obj.class_name)) |cls_def| if (cls_def.is_enum) {
                try out.print(a, "enum({s}::{s})\n", .{ obj.class_name, obj.get("name").string.bytes() });
                return;
            };
            var listing = try object_properties.list(ctx.vm, obj, .debug, a);
            defer listing.deinit(a);
            const holder = listing.takeHolder();
            defer object_properties.releaseHolder(ctx.vm, holder);
            var shown: usize = 0;
            for (listing.items.items) |prop| shown += @intFromBool(prop.uninitialized == null);
            try out.appendSlice(a, object_properties.lazyPrefix(obj));
            try out.print(a, "object({s})#{d} ({d}) refcount({d}){{\n", .{ class_names.display(obj.class_name), obj.id, shown, @max(rc, 1) });
            for (listing.items.items) |prop| {
                try appendIndent(out, a, level + 1);
                switch (prop.key) {
                    .int => |ki| try out.print(a, "[{d}]=>\n", .{ki}),
                    .name => |name| try emitDumpKey(out, a, name, prop.declaring, prop.visibility),
                }
                if (prop.uninitialized) |type_str| {
                    try appendIndent(out, a, level + 1);
                    try out.print(a, "uninitialized({s})\n", .{type_str});
                    continue;
                }
                const cell = switch (prop.key) {
                    .name => |name| propertyCell(ctx, obj, name),
                    .int => null,
                };
                if (cell) |c| {
                    try dumpReference(ctx, c, prop.value, level + 2);
                } else {
                    try debugZvalDump(ctx, prop.value, level + 2, false);
                }
            }
            try dumpIndent(out, a, level);
            try out.appendSlice(a, "}\n");
        },
        .generator => |g| try out.print(a, "object(Generator)#{d} (0) refcount({d}){{\n}}\n", .{ g.handle, 1 }),
        .fiber => |f| try out.print(a, "object(Fiber)#{d} (0) refcount({d}){{\n}}\n", .{ f.handle, 1 }),
        .resource => |r| {
            const rc = if (top) r.refcount -| call_holds_scalar else r.refcount;
            try out.print(a, "resource({d}) of type ({s}) refcount({d})\n", .{ r.id, value_mod.resourceTypeName(r), @max(rc, 1) });
        },
    }
}

// a reference's holders: the slots bound to its cell, less the last
// returned reference zphp keeps that php has already let go
fn dumpReference(ctx: *NativeContext, cell: *Value, inner: Value, level: usize) RuntimeError!void {
    const out = &ctx.vm.output;
    const a = ctx.allocator;
    var holders = value_mod.cellOf(cell).binders;
    if (ctx.vm.last_return_ref == cell) holders -|= 1;
    try dumpIndent(out, a, level);
    try out.print(a, "reference refcount({d}) {{\n", .{@max(holders, 1)});
    try debugZvalDump(ctx, inner, level + 2, false);
    try dumpIndent(out, a, level);
    try out.appendSlice(a, "}\n");
}

// the reference cell a property is bound to, if any
fn propertyCell(ctx: *NativeContext, obj: *value_mod.PhpObject, name: []const u8) ?*Value {
    const index = ctx.vm.ref_index orelse return null;
    const cells = index.prop_rev.get(.{ .object = obj, .class_name = "", .prop_name = name }) orelse return null;
    if (cells.items.len == 0) return null;
    return cells.items[0];
}

fn var_dump(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // php has already freed what the last statements dropped, so a reference
    // that lost its other holders shows unmarked
    if (ctx.vm.hasPendingReleases()) ctx.vm.drainPendingDestruct();
    for (args) |arg| try varDumpValue(ctx, arg, 0);
    return NativeResult.scalar(.null);
}

fn varDumpValue(ctx: *NativeContext, val: Value, depth: usize) !void {
    return varDumpMarked(ctx, val, depth, "");
}

// marker is "&" for a value a reference still shares with another holder
fn varDumpMarked(ctx: *NativeContext, val: Value, depth: usize, marker: []const u8) RuntimeError!void {
    const out = &ctx.vm.output;
    const a = ctx.allocator;
    const indent = depth * 2;
    switch (val) {
        .null, .undef => {
            try appendIndent(out, a, indent);
            try out.appendSlice(a, marker);
            try out.appendSlice(a, "NULL\n");
        },
        .bool => |b| {
            try appendIndent(out, a, indent);
            try out.appendSlice(a, marker);
            try out.appendSlice(a, if (b) "bool(true)\n" else "bool(false)\n");
        },
        .int => |i| {
            try appendIndent(out, a, indent);
            try out.appendSlice(a, marker);
            try out.appendSlice(a, "int(");
            var tmp: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return;
            try out.appendSlice(a, s);
            try out.appendSlice(a, ")\n");
        },
        .float => |f| {
            try appendIndent(out, a, indent);
            try out.appendSlice(a, marker);
            try out.appendSlice(a, "float(");
            var tmp: [64]u8 = undefined;
            const s = formatSerializedFloat(&tmp, f);
            try out.appendSlice(a, s);
            try out.appendSlice(a, ")\n");
        },
        .string => |s| {
            try appendIndent(out, a, indent);
            try out.appendSlice(a, marker);
            try out.appendSlice(a, "string(");
            var tmp: [32]u8 = undefined;
            const len_s = std.fmt.bufPrint(&tmp, "{d}", .{s.bytes().len}) catch return;
            try out.appendSlice(a, len_s);
            try out.appendSlice(a, ") \"");
            try out.appendSlice(a, s.bytes());
            try out.appendSlice(a, "\"\n");
        },
        .array => |arr| {
            if (arr.recursion & Recursion.gc != 0) {
                try appendIndent(out, a, indent);
                try out.appendSlice(a, "*RECURSION*\n");
                return;
            }
            arr.recursion |= Recursion.gc;
            defer arr.recursion &= ~Recursion.gc;

            try appendIndent(out, a, indent);
            try out.appendSlice(a, marker);
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
                        try out.appendSlice(a, ks.bytes());
                        try out.appendSlice(a, "\"]=>\n");
                    },
                }
                const shared = if (entry.ref) |cell| referenceShared(ctx, cell) else false;
                try varDumpMarked(ctx, entry.value, depth + 1, if (shared) "&" else "");
            }
            try appendIndent(out, a, indent);
            try out.appendSlice(a, "}\n");
        },
        .object => |obj| {
            const flag = objectFlag(ctx.vm, obj, Recursion.debug);
            if (obj.recursion & flag != 0) {
                try appendIndent(out, a, indent);
                try out.appendSlice(a, "*RECURSION*\n");
                return;
            }
            obj.recursion |= flag;
            defer obj.recursion &= ~flag;

            // PHP enum cases dump as `enum(ClassName::CaseName)\n`
            if (ctx.vm.classes.get(obj.class_name)) |cls_def| {
                if (cls_def.is_enum) {
                    const name_v = obj.get("name");
                    if (name_v == .string) {
                        try appendIndent(out, a, indent);
                        try out.appendSlice(a, marker);
                        try out.appendSlice(a, "enum(");
                        try out.appendSlice(a, obj.class_name);
                        try out.appendSlice(a, "::");
                        try out.appendSlice(a, name_v.string.bytes());
                        try out.appendSlice(a, ")\n");
                        return;
                    }
                }
            }

            var listing = try object_properties.list(ctx.vm, obj, .debug, a);
            defer listing.deinit(a);

            try appendIndent(out, a, indent);
            try out.appendSlice(a, marker);
            try out.appendSlice(a, object_properties.lazyPrefix(obj));
            try out.appendSlice(a, "object(");
            try out.appendSlice(a, class_names.display(obj.class_name));
            var initialized: usize = 0;
            for (listing.items.items) |prop| initialized += @intFromBool(prop.uninitialized == null);
            try out.print(a, ")#{d} ({d}) {{\n", .{ obj.id, initialized });
            for (listing.items.items) |prop| {
                try appendIndent(out, a, indent + 2);
                switch (prop.key) {
                    .int => |ki| try out.print(a, "[{d}]=>\n", .{ki}),
                    .name => |name| try emitDumpKey(out, a, name, prop.declaring, prop.visibility),
                }
                if (prop.uninitialized) |type_str| {
                    try appendIndent(out, a, indent + 2);
                    try out.print(a, "uninitialized({s})\n", .{type_str});
                    continue;
                }
                const shared = prop.shared or switch (prop.key) {
                    .name => |name| propertyReferenced(ctx, obj, name),
                    .int => false,
                };
                try varDumpMarked(ctx, prop.value, depth + 1, if (shared) "&" else "");
            }

            try appendIndent(out, a, indent);
            try out.appendSlice(a, "}\n");
        },
        .generator => |g| {
            try appendIndent(out, a, indent);
            try out.appendSlice(a, marker);
            try out.print(a, "object(Generator)#{d} (1) {{\n", .{g.handle});
            try appendIndent(out, a, indent + 2);
            try out.appendSlice(a, "[\"function\"]=>\n");
            try appendIndent(out, a, indent + 2);
            try out.appendSlice(a, "string(");
            var tmp: [32]u8 = undefined;
            const fname = try ctx.vm.generatorFunctionName(g);
            const len_s = std.fmt.bufPrint(&tmp, "{d}", .{fname.len}) catch return;
            try out.appendSlice(a, len_s);
            try out.appendSlice(a, ") \"");
            try out.appendSlice(a, fname);
            try out.appendSlice(a, "\"\n");
            try appendIndent(out, a, indent);
            try out.appendSlice(a, "}\n");
        },
        .fiber => |f| {
            try appendIndent(out, a, indent);
            try out.appendSlice(a, marker);
            try out.print(a, "object(Fiber)#{d} (0) {{\n", .{f.handle});
            try appendIndent(out, a, indent);
            try out.appendSlice(a, "}\n");
        },
        .resource => |r| {
            try appendIndent(out, a, indent);
            try out.appendSlice(a, marker);
            try out.print(a, "resource({d}) of type ({s})\n", .{ r.id, value_mod.resourceTypeName(r) });
        },
    }
}

// a property a reference still shares with another holder
fn propertyReferenced(ctx: *NativeContext, obj: *value_mod.PhpObject, name: []const u8) bool {
    const index = ctx.vm.ref_index orelse return false;
    const cells = index.prop_rev.get(.{ .object = obj, .class_name = "", .prop_name = name }) orelse return false;
    for (cells.items) |cell| if (referenceShared(ctx, cell)) return true;
    return false;
}

// a reference with a holder besides the one asking. the last reference a
// function returned stays held until the next one replaces it, which php
// would already have freed
fn referenceShared(ctx: *NativeContext, cell: *Value) bool {
    var holders = value_mod.cellOf(cell).binders;
    if (ctx.vm.last_return_ref == cell) holders -= 1;
    return holders > 1;
}

fn print_r(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.null);
    const return_str = args.len >= 2 and args[1].isTruthy();
    if (return_str) {
        var buf = std.ArrayListUnmanaged(u8).empty;
        defer buf.deinit(ctx.allocator);
        try printRValueImpl(ctx.allocator, &buf, args[0], 0, ctx.vm);
        const s = try buf.toOwnedSlice(ctx.allocator);
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, s));
    }
    try printRValueImpl(ctx.allocator, &ctx.vm.output, args[0], 0, ctx.vm);
    return NativeResult.scalar(.{ .bool = true });
}

fn printRValue(a: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8), val: Value, depth: usize) !void {
    return printRValueImpl(a, out, val, depth, null);
}

fn printRValueImpl(a: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8), val: Value, depth: usize, vm: ?*@import("../runtime/vm.zig").VM) !void {
    switch (val) {
        .null, .undef => {},
        .bool => |b| if (b) try out.appendSlice(a, "1"),
        .int => |i| {
            var tmp: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return;
            try out.appendSlice(a, s);
        },
        .float => try val.format(out, a),
        .string => |s| {
            try out.appendSlice(a, s.bytes());
        },
        .array => |arr| {
            if (arr.recursion & Recursion.gc != 0) {
                try out.appendSlice(a, "Array\n *RECURSION*");
                return;
            }
            arr.recursion |= Recursion.gc;
            defer arr.recursion &= ~Recursion.gc;

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
                        try out.appendSlice(a, ks.bytes());
                        try out.appendSlice(a, "] => ");
                    },
                }
                const nested = entry.value == .array or entry.value == .object;
                try printRValueImpl(a, out, entry.value, depth + if (nested) @as(usize, 2) else 1, vm);
                try out.appendSlice(a, "\n");
            }
            try appendIndent(out, a, depth * 4);
            try out.appendSlice(a, ")\n");
        },
        .object => |obj| {
            const flag = objectFlag(vm, obj, Recursion.debug);
            if (obj.recursion & flag != 0) {
                try out.appendSlice(a, class_names.display(obj.class_name));
                try out.appendSlice(a, " Object\n *RECURSION*");
                return;
            }
            obj.recursion |= flag;
            defer obj.recursion &= ~flag;

            try out.appendSlice(a, class_names.display(obj.class_name));
            // enums print as "ClassName Enum:type" (or "ClassName Enum" for non-backed)
            var label: []const u8 = " Object\n";
            if (vm) |v| {
                if (v.classes.get(obj.class_name)) |cls| {
                    if (cls.is_enum) {
                        label = switch (cls.backed_type) {
                            .int_type => " Enum:int\n",
                            .string_type => " Enum:string\n",
                            .none => " Enum\n",
                        };
                    }
                }
            }
            try out.appendSlice(a, label);
            try appendIndent(out, a, depth * 4);
            try out.appendSlice(a, "(\n");

            if (vm) |v| {
                var listing = try object_properties.list(v, obj, .debug, a);
                defer listing.deinit(a);
                for (listing.items.items) |prop| {
                    if (prop.uninitialized != null) continue;
                    try appendIndent(out, a, (depth + 1) * 4);
                    switch (prop.key) {
                        .int => |ki| try out.print(a, "[{d}", .{ki}),
                        .name => |name| {
                            try out.print(a, "[{s}", .{name});
                            switch (prop.visibility) {
                                .public => {},
                                .protected => try out.appendSlice(a, ":protected"),
                                .private => try out.print(a, ":{s}:private", .{class_names.display(prop.declaring)}),
                            }
                        },
                    }
                    try out.appendSlice(a, "] => ");
                    const nested = prop.value == .array or prop.value == .object;
                    try printRValueImpl(a, out, prop.value, depth + if (nested) @as(usize, 2) else 1, vm);
                    try out.appendSlice(a, "\n");
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
        .resource => try val.format(out, a),
    }
}

fn var_export(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.null);
    const return_str = args.len >= 2 and args[1].isTruthy();
    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(ctx.allocator);
    try varExportValue(ctx.allocator, &buf, args[0], 0, ctx);
    if (return_str) {
        const s = try buf.toOwnedSlice(ctx.allocator);
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, s));
    }
    try ctx.vm.output.appendSlice(ctx.allocator, buf.items);
    return NativeResult.scalar(.null);
}

fn varExportString(a: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8), s: []const u8) !void {
    // fast path: no nulls -> single quoted literal
    var has_null = false;
    for (s) |c| {
        if (c == 0) {
            has_null = true;
            break;
        }
    }
    if (!has_null) {
        try out.append(a, '\'');
        for (s) |c| {
            if (c == '\'') try out.appendSlice(a, "\\'") else if (c == '\\') try out.appendSlice(a, "\\\\") else try out.append(a, c);
        }
        try out.append(a, '\'');
        return;
    }
    // PHP splits on \0 and emits each segment as a single-quoted chunk,
    // joined by ` . "\0" . `. empty segments still emit '', so a string of
    // just "\0" renders as '' . "\0" . ''
    var i: usize = 0;
    var first_chunk = true;
    while (true) {
        var j = i;
        while (j < s.len and s[j] != 0) : (j += 1) {}
        if (!first_chunk) try out.appendSlice(a, " . \"\\0\" . ");
        first_chunk = false;
        try out.append(a, '\'');
        for (s[i..j]) |c| {
            if (c == '\'') try out.appendSlice(a, "\\'") else if (c == '\\') try out.appendSlice(a, "\\\\") else try out.append(a, c);
        }
        try out.append(a, '\'');
        if (j >= s.len) break;
        i = j + 1;
    }
}

fn varExportValue(a: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8), val: Value, depth: usize, ctx: *NativeContext) !void {
    switch (val) {
        .null, .undef => try out.appendSlice(a, "NULL"),
        .bool => |b| try out.appendSlice(a, if (b) "true" else "false"),
        .int => |i| {
            if (i == std.math.minInt(i64)) {
                try out.appendSlice(a, "-9223372036854775807-1");
            } else {
                var tmp: [32]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{d}", .{i}) catch return;
                try out.appendSlice(a, s);
            }
        },
        .float => |f| {
            var tmp: [64]u8 = undefined;
            if (std.math.isNan(f)) {
                try out.appendSlice(a, "NAN");
            } else if (std.math.isInf(f)) {
                try out.appendSlice(a, if (f > 0) "INF" else "-INF");
            } else {
                // smart_str_append_double with zero_frac: a float always
                // reads back as one
                const s = formatSerializedFloat(&tmp, f);
                try out.appendSlice(a, s);
                if (std.mem.indexOfAny(u8, s, ".eE") == null) try out.appendSlice(a, ".0");
            }
        },
        .string => |s| {
            try varExportString(a, out, s.bytes());
        },
        .array => |arr| {
            if (arr.recursion & Recursion.gc != 0) {
                try out.appendSlice(a, "NULL");
                try ctx.vm.emitWarning("var_export does not handle circular references");
                return;
            }
            arr.recursion |= Recursion.gc;
            defer arr.recursion &= ~Recursion.gc;
            try out.appendSlice(a, "array (\n");
            for (arr.entries.items) |entry| {
                for (0..(depth + 1) * 2) |_| try out.append(a, ' ');
                switch (entry.key) {
                    .int => |ki| {
                        var tmp: [32]u8 = undefined;
                        const ks = std.fmt.bufPrint(&tmp, "{d}", .{ki}) catch return;
                        try out.appendSlice(a, ks);
                    },
                    .string => |ks| try varExportString(a, out, ks.bytes()),
                }
                try out.appendSlice(a, " => ");
                const ev_recurses = switch (entry.value) {
                    .array => walking(entry.value, Recursion.gc),
                    .object => |oo| walking(entry.value, objectFlag(ctx.vm, oo, Recursion.export_)),
                    else => false,
                };
                if ((entry.value == .array or entry.value == .object) and !ev_recurses) {
                    try out.append(a, '\n');
                    for (0..(depth + 1) * 2) |_| try out.append(a, ' ');
                }
                try varExportValue(a, out, entry.value, depth + 1, ctx);
                try out.appendSlice(a, ",\n");
            }
            for (0..depth * 2) |_| try out.append(a, ' ');
            try out.append(a, ')');
        },
        .object => |obj| {
            const flag = objectFlag(ctx.vm, obj, Recursion.export_);
            if (obj.recursion & flag != 0) {
                try out.appendSlice(a, "NULL");
                try ctx.vm.emitWarning("var_export does not handle circular references");
                return;
            }
            obj.recursion |= flag;
            defer obj.recursion &= ~flag;
            if (ctx.vm.classes.get(obj.class_name)) |cls| {
                if (cls.is_enum) {
                    const case_name = obj.get("name");
                    if (case_name == .string) {
                        try out.append(a, '\\');
                        try out.appendSlice(a, obj.class_name);
                        try out.appendSlice(a, "::");
                        try out.appendSlice(a, case_name.string.bytes());
                        return;
                    }
                }
            }
            const is_std = std.mem.eql(u8, obj.class_name, "stdClass");
            if (is_std) {
                try out.appendSlice(a, "(object) array(\n");
            } else {
                try out.append(a, '\\');
                try out.appendSlice(a, obj.class_name);
                try out.appendSlice(a, "::__set_state(array(\n");
            }
            const item_indent = (depth + 1) * 2 + 1;
            var listing = try object_properties.list(ctx.vm, obj, .var_export, a);
            defer listing.deinit(a);
            defer object_properties.releaseHolder(ctx.vm, listing.takeHolder());
            for (listing.items.items) |prop| {
                for (0..item_indent) |_| try out.append(a, ' ');
                switch (prop.key) {
                    .int => |ki| try out.print(a, "{d}", .{ki}),
                    .name => |name| try varExportString(a, out, name),
                }
                try out.appendSlice(a, " => ");
                const seen = switch (prop.value) {
                    .array => walking(prop.value, Recursion.gc),
                    .object => |oo| walking(prop.value, objectFlag(ctx.vm, oo, Recursion.export_)),
                    else => false,
                };
                if ((prop.value == .array or prop.value == .object) and !seen) {
                    try out.append(a, '\n');
                    for (0..(depth + 1) * 2) |_| try out.append(a, ' ');
                }
                try varExportValue(a, out, prop.value, depth + 1, ctx);
                try out.appendSlice(a, ",\n");
            }
            for (0..depth * 2) |_| try out.append(a, ' ');
            if (is_std) {
                try out.append(a, ')');
            } else {
                try out.appendSlice(a, "))");
            }
        },
        .generator, .fiber => try out.appendSlice(a, "(object)"),
        .resource => try out.appendSlice(a, "NULL"),
    }
}

fn appendIndent(out: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, n: usize) !void {
    for (0..n) |_| try out.append(a, ' ');
}

fn emitDumpKey(out: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, name: []const u8, class_name: []const u8, vis: ClassDef.Visibility) !void {
    try out.appendSlice(a, "[\"");
    try out.appendSlice(a, name);
    try out.append(a, '"');
    switch (vis) {
        .public => {},
        .protected => try out.appendSlice(a, ":protected"),
        .private => {
            try out.appendSlice(a, ":\"");
            try out.appendSlice(a, class_names.display(class_name));
            try out.appendSlice(a, "\":private");
        },
    }
    try out.appendSlice(a, "]=>\n");
}

// serialize_precision -1: zend_gcvt in mode 0, the shortest round-trip
// digits, in exponent form past 17 integer digits or below 1e-4
// a float as var_dump and var_export show it: %.*H with serialize_precision
pub fn formatSerializedFloat(tmp: *[64]u8, f: f64) []const u8 {
    const sp = @import("../runtime/value.zig").hooks().serialize_precision;
    if (sp == -1 or std.math.isNan(f) or std.math.isInf(f)) return formatFloat(tmp, f);
    // php prints as many digits as the ini asks for (zend_gcvt has room for
    // a double's full expansion); past what tmp holds they go to a buffer of
    // that size, which the caller uses before formatting another
    if (sp > 40) return @import("formatted_print.zig").gcvt(f, sp, '.', 'E', &wide_float_buf);
    return @import("formatted_print.zig").gcvt(f, if (sp == 0) 1 else sp, '.', 'E', tmp);
}

threadlocal var wide_float_buf: [1100]u8 = undefined;

pub fn formatFloat(tmp: *[64]u8, f: f64) []const u8 {
    if (std.math.isNan(f)) return "NAN";
    if (std.math.isInf(f)) return if (f > 0) "INF" else "-INF";
    return @import("formatted_print.zig").gcvt(f, -1, '.', 'E', tmp);
}

fn formatScientific(buf: *[64]u8, f: f64) []const u8 {
    // Use Zig's {e} which yields exact round-trip mantissa, then reshape to PHP style.
    var src_buf: [64]u8 = undefined;
    const src = std.fmt.bufPrint(&src_buf, "{e}", .{f}) catch return "0";
    // Format is like "1e100", "1.234e-7", "-1.5e+10", etc. Find 'e'.
    const e_idx = std.mem.indexOfScalar(u8, src, 'e') orelse return std.fmt.bufPrint(buf, "{d}", .{f}) catch "0";
    var mant = src[0..e_idx];
    const exp_part = src[e_idx + 1 ..];
    // Trim trailing zeros after decimal point, but keep at least one digit after the dot.
    if (std.mem.indexOfScalar(u8, mant, '.')) |dot| {
        var end = mant.len;
        while (end > dot + 2 and mant[end - 1] == '0') end -= 1;
        mant = mant[0..end];
    }
    // Ensure mantissa has a decimal part (PHP always shows "1.0E+...").
    var mant_with_dot_buf: [64]u8 = undefined;
    var mant_out: []const u8 = mant;
    if (std.mem.indexOfScalar(u8, mant, '.') == null) {
        mant_out = std.fmt.bufPrint(&mant_with_dot_buf, "{s}.0", .{mant}) catch mant;
    }
    // Normalize exponent sign + drop leading zeros but keep at least one digit.
    var exp_sign: u8 = '+';
    var exp_digits = exp_part;
    if (exp_digits.len > 0 and (exp_digits[0] == '+' or exp_digits[0] == '-')) {
        exp_sign = exp_digits[0];
        exp_digits = exp_digits[1..];
    }
    while (exp_digits.len > 1 and exp_digits[0] == '0') exp_digits = exp_digits[1..];
    return std.fmt.bufPrint(buf, "{s}E{c}{s}", .{ mant_out, exp_sign, exp_digits }) catch "0";
}
