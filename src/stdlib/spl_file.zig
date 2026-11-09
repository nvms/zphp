const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeResult = vm_mod.NativeResult;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;

const csv = @import("csv.zig");
const filesystem = @import("filesystem.zig");

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
        "__construct", "rewind",        "valid",         "current",        "key",           "next",
        "fgets",       "fgetcsv",       "fputcsv",       "fread",          "fwrite",        "fseek",
        "ftell",       "feof",          "fgetc",         "fpassthru",      "fflush",        "ftruncate",
        "flock",       "getCsvControl", "setCsvControl", "getCurrentLine", "getMaxLineLen", "setMaxLineLen",
        "setFlags",    "getFlags",      "seek",          "hasChildren",    "getChildren",   "eof",
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
    try sfo_def.constants.put(a, "DROP_NEW_LINE", .{ .int = FLAG_DROP_NEW_LINE });
    try sfo_def.constants.put(a, "READ_AHEAD", .{ .int = FLAG_READ_AHEAD });
    try sfo_def.constants.put(a, "SKIP_EMPTY", .{ .int = FLAG_SKIP_EMPTY });
    try sfo_def.constants.put(a, "READ_CSV", .{ .int = FLAG_READ_CSV });
    try vm.classes.put(a, "SplFileObject", sfo_def);

    try vm.native_fns.put(a, "SplFileObject::__construct", sfoConstruct);
    try vm.native_fns.put(a, "SplFileObject::rewind", sfoRewind);
    try vm.native_fns.put(a, "SplFileObject::valid", sfoValid);
    try vm.native_fns.put(a, "SplFileObject::current", sfoCurrent);
    try vm.native_fns.put(a, "SplFileObject::key", sfoKey);
    try vm.native_fns.put(a, "SplFileObject::next", sfoNext);
    try vm.native_fns.put(a, "SplFileObject::fgets", sfoFgets);
    try vm.native_fns.put(a, "SplFileObject::fgetcsv", csv.splFgetcsv);
    try vm.native_fns.put(a, "SplFileObject::fputcsv", csv.splFputcsv);
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
    try vm.native_fns.put(a, "SplFileObject::getCsvControl", csv.splGetCsvControl);
    try vm.native_fns.put(a, "SplFileObject::setCsvControl", csv.splSetCsvControl);
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

fn getHandle(obj: *PhpObject) ?Value {
    const fh = obj.get("__sfo_fh");
    if (fh == .resource) return fh;
    return null;
}

fn defaultCsvControl(ctx: *NativeContext) RuntimeError!*PhpArray {
    const arr = try ctx.createArray();
    try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(",") });
    try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("\"") });
    try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("\\") });
    return arr;
}

fn sfoConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    const mode: Value = if (args.len >= 2 and args[1] == .string) args[1] else .{ .string = Value.String.borrowed("r") };
    const fh = try ctx.vm.callByName("fopen", &.{ args[0], mode });
    if (fh != .resource) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "SplFileObject::__construct(): Failed to open stream: {s}", .{args[0].string.bytes()});
        defer ctx.allocator.free(msg);
        if (try ctx.vm.throwBuiltinException("RuntimeException", msg)) return NativeResult.scalar(.null);
        return error.RuntimeError;
    }
    try obj.set(ctx.allocator, "__sfo_fh", fh);
    try obj.set(ctx.allocator, "__pathname", args[0]);
    try obj.set(ctx.allocator, "__sfo_line", .{ .int = 0 });
    try obj.set(ctx.allocator, "__sfo_flags", .{ .int = 0 });
    try obj.set(ctx.allocator, "__sfo_max", .{ .int = 0 });
    try obj.set(ctx.allocator, "__sfo_csv", .{ .array = try defaultCsvControl(ctx) });
    try obj.set(ctx.allocator, "__sfo_current", .null);
    return NativeResult.scalar(.null);
}

fn stfoConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = getThis(ctx) orelse return NativeResult.scalar(.null);
    var path_buf: [64]u8 = undefined;
    const path = if (args.len >= 1 and args[0] != .null) blk: {
        const max = Value.toInt(args[0]);
        const s = std.fmt.bufPrint(&path_buf, "php://temp/maxmemory:{d}", .{max}) catch "php://temp";
        break :blk s;
    } else "php://temp";
    const path_str = try Value.String.create(ctx.allocator, path);
    defer path_str.release();
    return sfoConstruct(ctx, &.{ .{ .string = path_str }, .{ .string = Value.String.borrowed("w+") } });
}

// spl_filesystem_file_read_line: the next line (or csv record) as current;
// false when the stream was already at its end. a line read at the end is ""
fn readOneLine(ctx: *NativeContext, obj: *PhpObject) RuntimeError!void {
    const fh = getHandle(obj) orelse {
        try obj.set(ctx.allocator, "__sfo_current", .{ .bool = false });
        return;
    };
    const flags = objGetInt(obj, "__sfo_flags");
    const max = objGetInt(obj, "__sfo_max");
    const max_len: usize = if (max > 0) @intCast(max) else 0;
    if ((flags & FLAG_READ_CSV) != 0) {
        const control = csv.Control.load(obj);
        if ((try csv.splReadCsv(ctx, obj, fh.resource, control.delimiter, control.enclosure, control.escape)) == null) {
            try obj.set(ctx.allocator, "__sfo_current", .{ .bool = false });
        }
        return;
    }
    var counts = csv.hasCurrent(obj);
    while (true) {
        const eof = try ctx.vm.callByName("feof", &.{fh});
        if (eof == .bool and eof.bool) {
            try obj.set(ctx.allocator, "__sfo_current", .{ .bool = false });
            return;
        }
        const raw = (try filesystem.streamReadLine(ctx, fh.resource, if (max_len > 0) max_len else std.math.maxInt(usize))) orelse try ctx.allocator.alloc(u8, 0);
        defer ctx.allocator.free(raw);
        // php counts the read as moving on only when a line was current;
        // lines SKIP_EMPTY passes over drop it first
        if (counts) try obj.set(ctx.allocator, "__sfo_line", .{ .int = objGetInt(obj, "__sfo_line") + 1 });
        counts = false;
        var line: []const u8 = raw;
        if ((flags & FLAG_DROP_NEW_LINE) != 0 and line.len > 0 and line[line.len - 1] == '\n') {
            line = line[0 .. line.len - 1];
            if (line.len > 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];
        }
        if ((flags & FLAG_SKIP_EMPTY) != 0 and line.len == 0) continue;
        const str = try Value.String.create(ctx.allocator, line);
        defer str.release();
        try obj.set(ctx.allocator, "__sfo_current", .{ .string = str });
        return;
    }
}

fn sfoRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const fh = getHandle(obj) orelse return NativeResult.scalar(.null);
    _ = try ctx.vm.callByName("fseek", &.{ fh, .{ .int = 0 } });
    try obj.set(ctx.allocator, "__sfo_line", .{ .int = 0 });
    // mark current as "unread" so the first current()/valid() call lazily fetches
    try obj.set(ctx.allocator, "__sfo_current", .null);
    return NativeResult.scalar(.null);
}

fn ensureCurrent(ctx: *NativeContext, obj: *@import("../runtime/value.zig").PhpObject) !void {
    const cur = obj.get("__sfo_current");
    if (cur == .null) try readOneLine(ctx, obj);
}

fn sfoValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    // without READ_AHEAD php asks the stream, not the line
    if ((objGetInt(obj, "__sfo_flags") & FLAG_READ_AHEAD) == 0) {
        const fh = getHandle(obj) orelse return NativeResult.scalar(.{ .bool = false });
        const eof = try ctx.vm.callByName("feof", &.{fh});
        return NativeResult.scalar(.{ .bool = !(eof == .bool and eof.bool) });
    }
    try ensureCurrent(ctx, obj);
    const cur = obj.get("__sfo_current");
    if (cur == .bool and !cur.bool) return NativeResult.scalar(.{ .bool = false });
    if (cur == .null) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn sfoCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    try ensureCurrent(ctx, obj);
    return NativeResult.share(obj.get("__sfo_current"));
}

fn sfoKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = objGetInt(obj, "__sfo_line") });
}

fn sfoNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    // the next line is read now under READ_AHEAD, else lazily by current()
    try obj.set(ctx.allocator, "__sfo_current", .null);
    if ((objGetInt(obj, "__sfo_flags") & FLAG_READ_AHEAD) != 0) try readOneLine(ctx, obj);
    try obj.set(ctx.allocator, "__sfo_line", .{ .int = objGetInt(obj, "__sfo_line") + 1 });
    return NativeResult.scalar(.null);
}

fn sfoFgets(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const fh = getHandle(obj) orelse return NativeResult.scalar(.{ .bool = false });
    try obj.set(ctx.allocator, "__sfo_line", .{ .int = objGetInt(obj, "__sfo_line") + 1 });
    return NativeResult.share(try ctx.vm.callByName("fgets", &.{fh}));
}

fn sfoFread(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const fh = getHandle(obj) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 1) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.share(try ctx.vm.callByName("fread", &.{ fh, args[0] }));
}

fn sfoFwrite(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const fh = getHandle(obj) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 1) return NativeResult.scalar(.{ .bool = false });
    if (args.len >= 2) return NativeResult.share(try ctx.vm.callByName("fwrite", &.{ fh, args[0], args[1] }));
    return NativeResult.share(try ctx.vm.callByName("fwrite", &.{ fh, args[0] }));
}

fn sfoFseek(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = -1 });
    const fh = getHandle(obj) orelse return NativeResult.scalar(.{ .int = -1 });
    if (args.len < 1) return NativeResult.scalar(.{ .int = -1 });
    const whence: Value = if (args.len >= 2) args[1] else .{ .int = 0 };
    return NativeResult.share(try ctx.vm.callByName("fseek", &.{ fh, args[0], whence }));
}

fn sfoFtell(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const fh = getHandle(obj) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.share(try ctx.vm.callByName("ftell", &.{fh}));
}

fn sfoFeof(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = true });
    const fh = getHandle(obj) orelse return NativeResult.scalar(.{ .bool = true });
    return NativeResult.share(try ctx.vm.callByName("feof", &.{fh}));
}

fn sfoFgetc(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const fh = getHandle(obj) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.share(try ctx.vm.callByName("fgetc", &.{fh}));
}

fn sfoFpassthru(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const fh = getHandle(obj) orelse return NativeResult.scalar(.{ .int = 0 });
    if (ctx.vm.native_fns.get("fpassthru")) |_| return NativeResult.share(try ctx.vm.callByName("fpassthru", &.{fh}));
    var total: i64 = 0;
    while (true) {
        const chunk = try ctx.vm.callByName("fread", &.{ fh, .{ .int = 8192 } });
        if (chunk != .string or chunk.string.bytes().len == 0) break;
        try ctx.vm.output.appendSlice(ctx.allocator, chunk.string.bytes());
        total += @intCast(chunk.string.bytes().len);
    }
    return NativeResult.scalar(.{ .int = total });
}

fn sfoFflush(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const fh = getHandle(obj) orelse return NativeResult.scalar(.{ .bool = false });
    if (ctx.vm.native_fns.get("fflush")) |_| return NativeResult.share(try ctx.vm.callByName("fflush", &.{fh}));
    return NativeResult.scalar(.{ .bool = true });
}

fn sfoFtruncate(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const fh = getHandle(obj) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 1) return NativeResult.scalar(.{ .bool = false });
    if (ctx.vm.native_fns.get("ftruncate")) |_| return NativeResult.share(try ctx.vm.callByName("ftruncate", &.{ fh, args[0] }));
    return NativeResult.scalar(.{ .bool = false });
}

fn sfoFlock(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const fh = getHandle(obj) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 1) return NativeResult.scalar(.{ .bool = false });
    if (ctx.vm.native_fns.get("flock")) |_| return NativeResult.share(try ctx.vm.callByName("flock", &.{ fh, args[0] }));
    return NativeResult.scalar(.{ .bool = true });
}

fn sfoGetMaxLineLen(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = objGetInt(obj, "__sfo_max") });
}

fn sfoSetMaxLineLen(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__sfo_max", .{ .int = Value.toInt(args[0]) });
    return NativeResult.scalar(.null);
}

fn sfoGetFlags(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = objGetInt(obj, "__sfo_flags") });
}

fn sfoSetFlags(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__sfo_flags", .{ .int = Value.toInt(args[0]) });
    return NativeResult.scalar(.null);
}

fn sfoSeek(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    const target = Value.toInt(args[0]);
    if (target < 0) {
        try ctx.vm.setPendingException("ValueError", "SplFileObject::seek(): Argument #1 ($line) must be greater than or equal to 0");
        return error.RuntimeError;
    }
    _ = try sfoRewind(ctx, &.{});
    const read_ahead = (objGetInt(obj, "__sfo_flags") & FLAG_READ_AHEAD) != 0;
    if (read_ahead) try readOneLine(ctx, obj);
    // php's spl_filesystem_file_seek: read target lines, stopping at the end
    var i: i64 = 0;
    while (i < target) : (i += 1) {
        try readOneLine(ctx, obj);
        const cur = obj.get("__sfo_current");
        if (cur == .bool and !cur.bool) return NativeResult.scalar(.null);
    }
    if (target > 0 and !read_ahead) {
        try obj.set(ctx.allocator, "__sfo_line", .{ .int = objGetInt(obj, "__sfo_line") + 1 });
        try obj.set(ctx.allocator, "__sfo_current", .null);
    }
    return NativeResult.scalar(.null);
}

fn sfoHasChildren(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = false });
}

fn sfoGetChildren(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.null);
}
