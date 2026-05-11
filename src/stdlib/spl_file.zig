const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

const FLAG_DROP_NEW_LINE: i64 = 1;
const FLAG_READ_AHEAD: i64 = 2;
const FLAG_SKIP_EMPTY: i64 = 4;
const FLAG_READ_CSV: i64 = 8;

pub fn register(vm: *VM, a: Allocator) !void {
    var sfo_def = ClassDef{ .name = "SplFileObject" };
    sfo_def.parent = "SplFileInfo";
    try sfo_def.interfaces.append(a, "RecursiveIterator");
    try sfo_def.interfaces.append(a, "SeekableIterator");
    for ([_][]const u8{
        "__construct", "rewind",         "valid",         "current",      "key",          "next",
        "fgets",       "fgetcsv",        "fputcsv",       "fread",        "fwrite",       "fseek",
        "ftell",       "feof",           "fgetc",         "fpassthru",    "fflush",       "ftruncate",
        "flock",       "getCsvControl",  "setCsvControl", "getCurrentLine", "getMaxLineLen", "setMaxLineLen",
        "setFlags",    "getFlags",       "seek",          "hasChildren",  "getChildren",  "eof",
    }) |m| {
        const arity: u8 = blk: {
            if (std.mem.eql(u8, m, "__construct")) break :blk 4;
            if (std.mem.eql(u8, m, "fgetcsv") or std.mem.eql(u8, m, "setCsvControl") or std.mem.eql(u8, m, "fputcsv")) break :blk 5;
            if (std.mem.eql(u8, m, "fwrite")) break :blk 2;
            if (std.mem.eql(u8, m, "fread") or std.mem.eql(u8, m, "ftruncate") or std.mem.eql(u8, m, "flock") or
                std.mem.eql(u8, m, "setMaxLineLen") or std.mem.eql(u8, m, "setFlags") or std.mem.eql(u8, m, "seek")) break :blk 1;
            if (std.mem.eql(u8, m, "fseek")) break :blk 2;
            break :blk 0;
        };
        try sfo_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try sfo_def.static_props.put(a, "DROP_NEW_LINE", .{ .int = FLAG_DROP_NEW_LINE });
    try sfo_def.static_props.put(a, "READ_AHEAD", .{ .int = FLAG_READ_AHEAD });
    try sfo_def.static_props.put(a, "SKIP_EMPTY", .{ .int = FLAG_SKIP_EMPTY });
    try sfo_def.static_props.put(a, "READ_CSV", .{ .int = FLAG_READ_CSV });
    try vm.classes.put(a, "SplFileObject", sfo_def);

    try vm.native_fns.put(a, "SplFileObject::__construct", sfoConstruct);
    try vm.native_fns.put(a, "SplFileObject::rewind", sfoRewind);
    try vm.native_fns.put(a, "SplFileObject::valid", sfoValid);
    try vm.native_fns.put(a, "SplFileObject::current", sfoCurrent);
    try vm.native_fns.put(a, "SplFileObject::key", sfoKey);
    try vm.native_fns.put(a, "SplFileObject::next", sfoNext);
    try vm.native_fns.put(a, "SplFileObject::fgets", sfoFgets);
    try vm.native_fns.put(a, "SplFileObject::fgetcsv", sfoFgetcsv);
    try vm.native_fns.put(a, "SplFileObject::fputcsv", sfoFputcsv);
    try vm.native_fns.put(a, "SplFileObject::fread", sfoFread);
    try vm.native_fns.put(a, "SplFileObject::fwrite", sfoFwrite);
    try vm.native_fns.put(a, "SplFileObject::fseek", sfoFseek);
    try vm.native_fns.put(a, "SplFileObject::ftell", sfoFtell);
    try vm.native_fns.put(a, "SplFileObject::feof", sfoFeof);
    try vm.native_fns.put(a, "SplFileObject::eof", sfoFeof);
    try vm.native_fns.put(a, "SplFileObject::fgetc", sfoFgetc);
    try vm.native_fns.put(a, "SplFileObject::fpassthru", sfoFpassthru);
    try vm.native_fns.put(a, "SplFileObject::fflush", sfoFflush);
    try vm.native_fns.put(a, "SplFileObject::ftruncate", sfoFtruncate);
    try vm.native_fns.put(a, "SplFileObject::flock", sfoFlock);
    try vm.native_fns.put(a, "SplFileObject::getCsvControl", sfoGetCsvControl);
    try vm.native_fns.put(a, "SplFileObject::setCsvControl", sfoSetCsvControl);
    try vm.native_fns.put(a, "SplFileObject::getCurrentLine", sfoFgets);
    try vm.native_fns.put(a, "SplFileObject::getMaxLineLen", sfoGetMaxLineLen);
    try vm.native_fns.put(a, "SplFileObject::setMaxLineLen", sfoSetMaxLineLen);
    try vm.native_fns.put(a, "SplFileObject::setFlags", sfoSetFlags);
    try vm.native_fns.put(a, "SplFileObject::getFlags", sfoGetFlags);
    try vm.native_fns.put(a, "SplFileObject::seek", sfoSeek);
    try vm.native_fns.put(a, "SplFileObject::hasChildren", sfoHasChildren);
    try vm.native_fns.put(a, "SplFileObject::getChildren", sfoGetChildren);

    // SplTempFileObject - in-memory temp file; takes optional maxMemory size
    var stfo_def = ClassDef{ .name = "SplTempFileObject" };
    stfo_def.parent = "SplFileObject";
    try stfo_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try vm.classes.put(a, "SplTempFileObject", stfo_def);
    try vm.native_fns.put(a, "SplTempFileObject::__construct", stfoConstruct);
}

fn getThis(ctx: *NativeContext) ?*PhpObject {
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

fn objGetInt(obj: *PhpObject, key: []const u8) i64 {
    const v = obj.get(key);
    if (v == .int) return v.int;
    return 0;
}

fn createString(ctx: *NativeContext, s: []const u8) ![]const u8 {
    const copy = try ctx.allocator.dupe(u8, s);
    try ctx.vm.strings.append(ctx.allocator, copy);
    return copy;
}

fn getHandle(obj: *PhpObject) ?Value {
    const fh = obj.get("__sfo_fh");
    if (fh == .object) return fh;
    return null;
}

fn defaultCsvControl(ctx: *NativeContext) RuntimeError!*PhpArray {
    const arr = try ctx.allocator.create(PhpArray);
    arr.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, arr);
    try arr.append(ctx.allocator, .{ .string = "," });
    try arr.append(ctx.allocator, .{ .string = "\"" });
    try arr.append(ctx.allocator, .{ .string = "\\" });
    return arr;
}

fn sfoConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len < 1 or args[0] != .string) return .null;
    const mode: Value = if (args.len >= 2 and args[1] == .string) args[1] else .{ .string = "r" };
    const fh = try ctx.vm.callByName("fopen", &.{ args[0], mode });
    if (fh != .object) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "SplFileObject::__construct(): Failed to open stream: {s}", .{args[0].string});
        try ctx.vm.strings.append(ctx.allocator, msg);
        if (try ctx.vm.throwBuiltinException("RuntimeException", msg)) return .null;
        return error.RuntimeError;
    }
    try obj.set(ctx.allocator, "__sfo_fh", fh);
    try obj.set(ctx.allocator, "__pathname", .{ .string = try createString(ctx, args[0].string) });
    try obj.set(ctx.allocator, "__sfo_line", .{ .int = 0 });
    try obj.set(ctx.allocator, "__sfo_flags", .{ .int = 0 });
    try obj.set(ctx.allocator, "__sfo_max", .{ .int = 0 });
    try obj.set(ctx.allocator, "__sfo_csv", .{ .array = try defaultCsvControl(ctx) });
    try obj.set(ctx.allocator, "__sfo_current", .null);
    return .null;
}

fn stfoConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    _ = getThis(ctx) orelse return .null;
    var path_buf: [64]u8 = undefined;
    const path = if (args.len >= 1 and args[0] != .null) blk: {
        const max = Value.toInt(args[0]);
        const s = std.fmt.bufPrint(&path_buf, "php://temp/maxmemory:{d}", .{max}) catch "php://temp";
        break :blk s;
    } else "php://temp";
    const path_str = try createString(ctx, path);
    return sfoConstruct(ctx, &.{ .{ .string = path_str }, .{ .string = "w+" } });
}

fn readOneLine(ctx: *NativeContext, obj: *PhpObject) RuntimeError!void {
    const fh = getHandle(obj) orelse {
        try obj.set(ctx.allocator, "__sfo_current", .{ .bool = false });
        return;
    };
    const flags = objGetInt(obj, "__sfo_flags");
    while (true) {
        var line: Value = undefined;
        if ((flags & FLAG_READ_CSV) != 0) {
            const csv_v = obj.get("__sfo_csv");
            const sep_v: Value = if (csv_v == .array) csv_v.array.get(.{ .int = 0 }) else .{ .string = "," };
            const enc_v: Value = if (csv_v == .array) csv_v.array.get(.{ .int = 1 }) else .{ .string = "\"" };
            const esc_v: Value = if (csv_v == .array) csv_v.array.get(.{ .int = 2 }) else .{ .string = "\\" };
            line = try ctx.vm.callByName("fgetcsv", &.{ fh, .{ .int = 0 }, sep_v, enc_v, esc_v });
        } else {
            line = try ctx.vm.callByName("fgets", &.{fh});
        }
        if (line == .bool and !line.bool) {
            try obj.set(ctx.allocator, "__sfo_current", .{ .bool = false });
            return;
        }
        if ((flags & FLAG_READ_CSV) == 0 and (flags & FLAG_DROP_NEW_LINE) != 0 and line == .string) {
            var s = line.string;
            while (s.len > 0 and (s[s.len - 1] == '\n' or s[s.len - 1] == '\r')) s = s[0 .. s.len - 1];
            line = .{ .string = try createString(ctx, s) };
        }
        if ((flags & FLAG_SKIP_EMPTY) != 0) {
            const is_empty = blk: {
                if (line == .string) break :blk line.string.len == 0;
                if (line == .array) {
                    if (line.array.length() == 0) break :blk true;
                    if (line.array.length() == 1) {
                        const only = line.array.get(.{ .int = 0 });
                        if (only == .null or (only == .string and only.string.len == 0)) break :blk true;
                    }
                }
                break :blk false;
            };
            if (is_empty) {
                try obj.set(ctx.allocator, "__sfo_line", .{ .int = objGetInt(obj, "__sfo_line") + 1 });
                continue;
            }
        }
        try obj.set(ctx.allocator, "__sfo_current", line);
        return;
    }
}

fn sfoRewind(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const fh = getHandle(obj) orelse return .null;
    _ = try ctx.vm.callByName("fseek", &.{ fh, .{ .int = 0 } });
    try obj.set(ctx.allocator, "__sfo_line", .{ .int = 0 });
    // mark current as "unread" so the first current()/valid() call lazily fetches
    try obj.set(ctx.allocator, "__sfo_current", .null);
    return .null;
}

fn ensureCurrent(ctx: *NativeContext, obj: *@import("../runtime/value.zig").PhpObject) !void {
    const cur = obj.get("__sfo_current");
    if (cur == .null) try readOneLine(ctx, obj);
}

fn sfoValid(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    try ensureCurrent(ctx, obj);
    const cur = obj.get("__sfo_current");
    if (cur == .bool and !cur.bool) return .{ .bool = false };
    if (cur == .null) return .{ .bool = false };
    return .{ .bool = true };
}

fn sfoCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    try ensureCurrent(ctx, obj);
    return obj.get("__sfo_current");
}

fn sfoKey(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    return .{ .int = objGetInt(obj, "__sfo_line") };
}

fn sfoNext(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    try obj.set(ctx.allocator, "__sfo_line", .{ .int = objGetInt(obj, "__sfo_line") + 1 });
    try readOneLine(ctx, obj);
    return .null;
}

fn sfoFgets(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const fh = getHandle(obj) orelse return .{ .bool = false };
    try obj.set(ctx.allocator, "__sfo_line", .{ .int = objGetInt(obj, "__sfo_line") + 1 });
    return ctx.vm.callByName("fgets", &.{fh});
}

fn sfoFgetcsv(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const fh = getHandle(obj) orelse return .{ .bool = false };
    const csv_v = obj.get("__sfo_csv");
    const sep: Value = if (args.len >= 1 and args[0] == .string) args[0] else if (csv_v == .array) csv_v.array.get(.{ .int = 0 }) else .{ .string = "," };
    const enc: Value = if (args.len >= 2 and args[1] == .string) args[1] else if (csv_v == .array) csv_v.array.get(.{ .int = 1 }) else .{ .string = "\"" };
    const esc: Value = if (args.len >= 3 and args[2] == .string) args[2] else if (csv_v == .array) csv_v.array.get(.{ .int = 2 }) else .{ .string = "\\" };
    try obj.set(ctx.allocator, "__sfo_line", .{ .int = objGetInt(obj, "__sfo_line") + 1 });
    return ctx.vm.callByName("fgetcsv", &.{ fh, .{ .int = 0 }, sep, enc, esc });
}

fn sfoFputcsv(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const fh = getHandle(obj) orelse return .{ .bool = false };
    if (args.len < 1 or args[0] != .array) return .{ .bool = false };
    const csv_v = obj.get("__sfo_csv");
    const sep: Value = if (args.len >= 2 and args[1] == .string) args[1] else if (csv_v == .array) csv_v.array.get(.{ .int = 0 }) else .{ .string = "," };
    const enc: Value = if (args.len >= 3 and args[2] == .string) args[2] else if (csv_v == .array) csv_v.array.get(.{ .int = 1 }) else .{ .string = "\"" };
    const esc: Value = if (args.len >= 4 and args[3] == .string) args[3] else if (csv_v == .array) csv_v.array.get(.{ .int = 2 }) else .{ .string = "\\" };
    const eol: Value = if (args.len >= 5 and args[4] == .string) args[4] else .{ .string = "\n" };
    return ctx.vm.callByName("fputcsv", &.{ fh, args[0], sep, enc, esc, eol });
}

fn sfoFread(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const fh = getHandle(obj) orelse return .{ .bool = false };
    if (args.len < 1) return .{ .bool = false };
    return ctx.vm.callByName("fread", &.{ fh, args[0] });
}

fn sfoFwrite(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const fh = getHandle(obj) orelse return .{ .bool = false };
    if (args.len < 1) return .{ .bool = false };
    if (args.len >= 2) return ctx.vm.callByName("fwrite", &.{ fh, args[0], args[1] });
    return ctx.vm.callByName("fwrite", &.{ fh, args[0] });
}

fn sfoFseek(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = -1 };
    const fh = getHandle(obj) orelse return .{ .int = -1 };
    if (args.len < 1) return .{ .int = -1 };
    const whence: Value = if (args.len >= 2) args[1] else .{ .int = 0 };
    return ctx.vm.callByName("fseek", &.{ fh, args[0], whence });
}

fn sfoFtell(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const fh = getHandle(obj) orelse return .{ .bool = false };
    return ctx.vm.callByName("ftell", &.{fh});
}

fn sfoFeof(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = true };
    const fh = getHandle(obj) orelse return .{ .bool = true };
    return ctx.vm.callByName("feof", &.{fh});
}

fn sfoFgetc(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const fh = getHandle(obj) orelse return .{ .bool = false };
    return ctx.vm.callByName("fgetc", &.{fh});
}

fn sfoFpassthru(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    const fh = getHandle(obj) orelse return .{ .int = 0 };
    if (ctx.vm.native_fns.get("fpassthru")) |_| return ctx.vm.callByName("fpassthru", &.{fh});
    var total: i64 = 0;
    while (true) {
        const chunk = try ctx.vm.callByName("fread", &.{ fh, .{ .int = 8192 } });
        if (chunk != .string or chunk.string.len == 0) break;
        try ctx.vm.output.appendSlice(ctx.allocator, chunk.string);
        total += @intCast(chunk.string.len);
    }
    return .{ .int = total };
}

fn sfoFflush(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const fh = getHandle(obj) orelse return .{ .bool = false };
    if (ctx.vm.native_fns.get("fflush")) |_| return ctx.vm.callByName("fflush", &.{fh});
    return .{ .bool = true };
}

fn sfoFtruncate(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const fh = getHandle(obj) orelse return .{ .bool = false };
    if (args.len < 1) return .{ .bool = false };
    if (ctx.vm.native_fns.get("ftruncate")) |_| return ctx.vm.callByName("ftruncate", &.{ fh, args[0] });
    return .{ .bool = false };
}

fn sfoFlock(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const fh = getHandle(obj) orelse return .{ .bool = false };
    if (args.len < 1) return .{ .bool = false };
    if (ctx.vm.native_fns.get("flock")) |_| return ctx.vm.callByName("flock", &.{ fh, args[0] });
    return .{ .bool = true };
}

fn sfoGetCsvControl(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    return obj.get("__sfo_csv");
}

fn sfoSetCsvControl(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = try ctx.allocator.create(PhpArray);
    arr.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, arr);
    const sep: Value = if (args.len >= 1 and args[0] == .string) args[0] else .{ .string = "," };
    const enc: Value = if (args.len >= 2 and args[1] == .string) args[1] else .{ .string = "\"" };
    const esc: Value = if (args.len >= 3 and args[2] == .string) args[2] else .{ .string = "\\" };
    try arr.append(ctx.allocator, sep);
    try arr.append(ctx.allocator, enc);
    try arr.append(ctx.allocator, esc);
    try obj.set(ctx.allocator, "__sfo_csv", .{ .array = arr });
    return .null;
}

fn sfoGetMaxLineLen(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    return .{ .int = objGetInt(obj, "__sfo_max") };
}

fn sfoSetMaxLineLen(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len < 1) return .null;
    try obj.set(ctx.allocator, "__sfo_max", .{ .int = Value.toInt(args[0]) });
    return .null;
}

fn sfoGetFlags(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    return .{ .int = objGetInt(obj, "__sfo_flags") };
}

fn sfoSetFlags(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len < 1) return .null;
    try obj.set(ctx.allocator, "__sfo_flags", .{ .int = Value.toInt(args[0]) });
    return .null;
}

fn sfoSeek(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len < 1) return .null;
    const target = Value.toInt(args[0]);
    _ = try sfoRewind(ctx, &.{});
    // populate line 0 first (rewind no longer pre-reads); then next() to advance
    try ensureCurrent(ctx, obj);
    while (objGetInt(obj, "__sfo_line") < target) {
        const cur = obj.get("__sfo_current");
        if (cur == .bool and !cur.bool) break;
        _ = try sfoNext(ctx, &.{});
    }
    return .null;
}

fn sfoHasChildren(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = false };
}

fn sfoGetChildren(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .null;
}
