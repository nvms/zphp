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

pub fn register(vm: *VM, a: Allocator) !void {
    // RecursiveIterator interface
    var rec_iter = vm_mod.InterfaceDef{ .name = "RecursiveIterator" };
    rec_iter.parent = "Iterator";
    try rec_iter.methods.append(a, "hasChildren");
    try rec_iter.methods.append(a, "getChildren");
    try vm.interfaces.put(a, "RecursiveIterator", rec_iter);

    // SplFileInfo
    var fi_def = ClassDef{ .name = "SplFileInfo" };
    for ([_][]const u8{
        "__construct", "getFilename", "getExtension", "getBasename",
        "getPathname", "getPath", "getRealPath", "getSize",
        "isDir", "isFile", "isLink", "isReadable", "isWritable",
        "getMTime", "getCTime", "getATime", "getType", "__toString",
    }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "__construct")) 1 else 0;
        try fi_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try vm.classes.put(a, "SplFileInfo", fi_def);

    try vm.native_fns.put(a, "SplFileInfo::__construct", fiConstruct);
    try vm.native_fns.put(a, "SplFileInfo::getFilename", fiGetFilename);
    try vm.native_fns.put(a, "SplFileInfo::getExtension", fiGetExtension);
    try vm.native_fns.put(a, "SplFileInfo::getBasename", fiGetBasename);
    try vm.native_fns.put(a, "SplFileInfo::getPathname", fiGetPathname);
    try vm.native_fns.put(a, "SplFileInfo::getPath", fiGetPath);
    try vm.native_fns.put(a, "SplFileInfo::getRealPath", fiGetRealPath);
    try vm.native_fns.put(a, "SplFileInfo::getSize", fiGetSize);
    try vm.native_fns.put(a, "SplFileInfo::isDir", fiIsDir);
    try vm.native_fns.put(a, "SplFileInfo::isFile", fiIsFile);
    try vm.native_fns.put(a, "SplFileInfo::isLink", fiIsLink);
    try vm.native_fns.put(a, "SplFileInfo::isReadable", fiIsReadable);
    try vm.native_fns.put(a, "SplFileInfo::isWritable", fiIsWritable);
    try vm.native_fns.put(a, "SplFileInfo::getMTime", fiGetMTime);
    try vm.native_fns.put(a, "SplFileInfo::getCTime", fiGetCTime);
    try vm.native_fns.put(a, "SplFileInfo::getATime", fiGetATime);
    try vm.native_fns.put(a, "SplFileInfo::getType", fiGetType);
    try vm.native_fns.put(a, "SplFileInfo::__toString", fiToString);

    // DirectoryIterator
    var di_def = ClassDef{ .name = "DirectoryIterator" };
    di_def.parent = "SplFileInfo";
    try di_def.interfaces.append(a, "Iterator");
    for ([_][]const u8{
        "__construct", "rewind", "current", "key", "next", "valid", "isDot",
    }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "__construct")) 1 else 0;
        try di_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try vm.classes.put(a, "DirectoryIterator", di_def);

    try vm.native_fns.put(a, "DirectoryIterator::__construct", diConstruct);
    try vm.native_fns.put(a, "DirectoryIterator::rewind", diRewind);
    try vm.native_fns.put(a, "DirectoryIterator::current", diCurrent);
    try vm.native_fns.put(a, "DirectoryIterator::key", diKey);
    try vm.native_fns.put(a, "DirectoryIterator::next", diNext);
    try vm.native_fns.put(a, "DirectoryIterator::valid", diValid);
    try vm.native_fns.put(a, "DirectoryIterator::isDot", diIsDot);

    // RecursiveDirectoryIterator
    var rdi_def = ClassDef{ .name = "RecursiveDirectoryIterator" };
    rdi_def.parent = "DirectoryIterator";
    try rdi_def.interfaces.append(a, "RecursiveIterator");
    for ([_][]const u8{
        "__construct", "hasChildren", "getChildren", "getSubPath", "getSubPathname",
        "rewind", "current", "key", "next", "valid",
    }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "__construct")) 2 else 0;
        try rdi_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try rdi_def.static_props.put(a, "SKIP_DOTS", .{ .int = 0x1000 });
    try rdi_def.static_props.put(a, "FOLLOW_SYMLINKS", .{ .int = 0x0200 });
    try rdi_def.static_props.put(a, "CURRENT_AS_PATHNAME", .{ .int = 0x0020 });
    try rdi_def.static_props.put(a, "CURRENT_AS_SELF", .{ .int = 0x0010 });
    try rdi_def.static_props.put(a, "UNIX_PATHS", .{ .int = 0x2000 });
    try vm.classes.put(a, "RecursiveDirectoryIterator", rdi_def);

    try vm.native_fns.put(a, "RecursiveDirectoryIterator::__construct", rdiConstruct);
    try vm.native_fns.put(a, "RecursiveDirectoryIterator::hasChildren", rdiHasChildren);
    try vm.native_fns.put(a, "RecursiveDirectoryIterator::getChildren", rdiGetChildren);
    try vm.native_fns.put(a, "RecursiveDirectoryIterator::getSubPath", rdiGetSubPath);
    try vm.native_fns.put(a, "RecursiveDirectoryIterator::getSubPathname", rdiGetSubPathname);
    try vm.native_fns.put(a, "RecursiveDirectoryIterator::rewind", rdiRewind);
    try vm.native_fns.put(a, "RecursiveDirectoryIterator::current", rdiCurrent);
    try vm.native_fns.put(a, "RecursiveDirectoryIterator::key", rdiKey);
    try vm.native_fns.put(a, "RecursiveDirectoryIterator::next", rdiNext);
    try vm.native_fns.put(a, "RecursiveDirectoryIterator::valid", rdiValid);

    // FilterIterator (abstract - stores inner iterator, delegates with accept() filtering)
    var filter_def = ClassDef{ .name = "FilterIterator" };
    try filter_def.interfaces.append(a, "Iterator");
    for ([_][]const u8{
        "__construct", "rewind", "current", "key", "next", "valid", "getInnerIterator",
    }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "__construct")) 1 else 0;
        try filter_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try vm.classes.put(a, "FilterIterator", filter_def);

    try vm.native_fns.put(a, "FilterIterator::__construct", filterConstruct);
    try vm.native_fns.put(a, "FilterIterator::rewind", filterRewind);
    try vm.native_fns.put(a, "FilterIterator::current", filterCurrent);
    try vm.native_fns.put(a, "FilterIterator::key", filterKey);
    try vm.native_fns.put(a, "FilterIterator::next", filterNext);
    try vm.native_fns.put(a, "FilterIterator::valid", filterValid);
    try vm.native_fns.put(a, "FilterIterator::getInnerIterator", filterGetInner);

    // RecursiveIteratorIterator
    var rii_def = ClassDef{ .name = "RecursiveIteratorIterator" };
    try rii_def.interfaces.append(a, "Iterator");
    for ([_][]const u8{
        "__construct", "rewind", "current", "key", "next", "valid", "getDepth",
        "getInnerIterator", "getSubIterator",
    }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "__construct")) 2 else 0;
        try rii_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try rii_def.static_props.put(a, "LEAVES_ONLY", .{ .int = 0 });
    try rii_def.static_props.put(a, "SELF_FIRST", .{ .int = 1 });
    try rii_def.static_props.put(a, "CHILD_FIRST", .{ .int = 2 });
    try vm.classes.put(a, "RecursiveIteratorIterator", rii_def);

    try vm.native_fns.put(a, "RecursiveIteratorIterator::__construct", riiConstruct);
    try vm.native_fns.put(a, "RecursiveIteratorIterator::rewind", riiRewind);
    try vm.native_fns.put(a, "RecursiveIteratorIterator::current", riiCurrent);
    try vm.native_fns.put(a, "RecursiveIteratorIterator::key", riiKey);
    try vm.native_fns.put(a, "RecursiveIteratorIterator::next", riiNext);
    try vm.native_fns.put(a, "RecursiveIteratorIterator::valid", riiValid);
    try vm.native_fns.put(a, "RecursiveIteratorIterator::getDepth", riiGetDepth);
    try vm.native_fns.put(a, "RecursiveIteratorIterator::getInnerIterator", riiGetInner);
    try vm.native_fns.put(a, "RecursiveIteratorIterator::getSubIterator", riiGetSubIterator);
}

// ==========================================
// helpers
// ==========================================

fn getThis(ctx: *NativeContext) ?*PhpObject {
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

fn createString(ctx: *NativeContext, s: []const u8) ![]const u8 {
    const copy = try ctx.allocator.dupe(u8, s);
    try ctx.vm.strings.append(ctx.allocator, copy);
    return copy;
}

fn objGetStr(obj: *PhpObject, key: []const u8) []const u8 {
    const v = obj.get(key);
    if (v == .string) return v.string;
    return "";
}

fn objGetInt(obj: *PhpObject, key: []const u8) i64 {
    const v = obj.get(key);
    if (v == .int) return v.int;
    return 0;
}

fn createFileInfoObj(ctx: *NativeContext, pathname: []const u8) !*PhpObject {
    const obj = try ctx.allocator.create(PhpObject);
    obj.* = .{ .class_name = "SplFileInfo" };
    try ctx.vm.objects.append(ctx.allocator, obj);
    try obj.set(ctx.allocator, "__pathname", .{ .string = try createString(ctx, pathname) });
    return obj;
}

fn basename(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, path, '/')) |idx| {
        return path[idx + 1 ..];
    }
    return path;
}

fn dirname(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, path, '/')) |idx| {
        if (idx == 0) return "/";
        return path[0..idx];
    }
    return ".";
}

fn statPath(path: []const u8) ?std.fs.File.Stat {
    const file = std.fs.openFileAbsolute(path, .{}) catch {
        var dir = std.fs.openDirAbsolute(path, .{}) catch return null;
        defer dir.close();
        return dir.stat() catch null;
    };
    defer file.close();
    return file.stat() catch null;
}

// ==========================================
// SplFileInfo
// ==========================================

fn fiConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len < 1 or args[0] != .string) return .null;
    try obj.set(ctx.allocator, "__pathname", .{ .string = try createString(ctx, args[0].string) });
    return .null;
}

fn fiGetFilename(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const path = objGetStr(obj, "__pathname");
    return .{ .string = try createString(ctx, basename(path)) };
}

fn fiGetExtension(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const name = basename(objGetStr(obj, "__pathname"));
    if (std.mem.lastIndexOfScalar(u8, name, '.')) |idx| {
        return .{ .string = try createString(ctx, name[idx + 1 ..]) };
    }
    return .{ .string = "" };
}

fn fiGetBasename(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    var name = basename(objGetStr(obj, "__pathname"));
    if (args.len >= 1 and args[0] == .string) {
        const suffix = args[0].string;
        if (std.mem.endsWith(u8, name, suffix)) {
            name = name[0 .. name.len - suffix.len];
        }
    }
    return .{ .string = try createString(ctx, name) };
}

fn fiGetPathname(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    return .{ .string = objGetStr(obj, "__pathname") };
}

fn fiGetPath(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    return .{ .string = try createString(ctx, dirname(objGetStr(obj, "__pathname"))) };
}

fn fiGetRealPath(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const path = objGetStr(obj, "__pathname");
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = std.fs.cwd().realpath(path, &buf) catch return .{ .bool = false };
    return .{ .string = try createString(ctx, real) };
}

fn fiGetSize(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const stat = statPath(objGetStr(obj, "__pathname")) orelse return .{ .int = 0 };
    return .{ .int = @intCast(stat.size) };
}

fn fiIsDir(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const path = objGetStr(obj, "__pathname");
    const stat = statPath(path) orelse return .{ .bool = false };
    return .{ .bool = stat.kind == .directory };
}

fn fiIsFile(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const path = objGetStr(obj, "__pathname");
    const stat = statPath(path) orelse return .{ .bool = false };
    return .{ .bool = stat.kind == .file };
}

fn fiIsLink(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const path = objGetStr(obj, "__pathname");
    const stat = statPath(path) orelse return .{ .bool = false };
    return .{ .bool = stat.kind == .sym_link };
}

fn fiIsReadable(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = true };
}

fn fiIsWritable(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = true };
}

fn fiGetMTime(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    const stat = statPath(objGetStr(obj, "__pathname")) orelse return .{ .int = 0 };
    return .{ .int = @intCast(@divTrunc(stat.mtime, std.time.ns_per_s)) };
}

fn fiGetCTime(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    const stat = statPath(objGetStr(obj, "__pathname")) orelse return .{ .int = 0 };
    return .{ .int = @intCast(@divTrunc(stat.ctime, std.time.ns_per_s)) };
}

fn fiGetATime(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    const stat = statPath(objGetStr(obj, "__pathname")) orelse return .{ .int = 0 };
    return .{ .int = @intCast(@divTrunc(stat.atime, std.time.ns_per_s)) };
}

fn fiGetType(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .string = "unknown" };
    const stat = statPath(objGetStr(obj, "__pathname")) orelse return .{ .string = "unknown" };
    return .{ .string = switch (stat.kind) {
        .directory => "dir",
        .file => "file",
        .sym_link => "link",
        else => "unknown",
    } };
}

fn fiToString(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .string = "" };
    return .{ .string = objGetStr(obj, "__pathname") };
}

// ==========================================
// DirectoryIterator
// ==========================================

fn diConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len < 1 or args[0] != .string) return .null;
    const path = args[0].string;
    try obj.set(ctx.allocator, "__di_path", .{ .string = try createString(ctx, path) });
    try obj.set(ctx.allocator, "__di_idx", .{ .int = 0 });

    const entries = try loadDirectoryEntries(ctx, path, 0);
    try obj.set(ctx.allocator, "__di_entries", .{ .array = entries });
    try syncCurrentEntry(ctx, obj);
    return .null;
}

const SKIP_DOTS: i64 = 0x1000;

fn loadDirectoryEntries(ctx: *NativeContext, path: []const u8, flags: i64) RuntimeError!*PhpArray {
    const arr = try ctx.allocator.create(PhpArray);
    arr.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, arr);

    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return arr;
    defer dir.close();

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        const skip_dots = (flags & SKIP_DOTS) != 0;
        if (skip_dots and (std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, ".."))) continue;

        const full = try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ path, entry.name });
        try ctx.vm.strings.append(ctx.allocator, full);

        const is_dir: bool = entry.kind == .directory;
        const entry_arr = try ctx.allocator.create(PhpArray);
        entry_arr.* = .{};
        try ctx.vm.arrays.append(ctx.allocator, entry_arr);
        try entry_arr.set(ctx.allocator, .{ .string = "name" }, .{ .string = try createString(ctx, entry.name) });
        try entry_arr.set(ctx.allocator, .{ .string = "path" }, .{ .string = full });
        try entry_arr.set(ctx.allocator, .{ .string = "is_dir" }, .{ .bool = is_dir });

        try arr.append(ctx.allocator, .{ .array = entry_arr });
    }
    return arr;
}

fn syncCurrentEntry(ctx: *NativeContext, obj: *PhpObject) !void {
    const entries = if (obj.get("__di_entries") == .array) obj.get("__di_entries").array else return;
    const idx: usize = @intCast(@max(0, objGetInt(obj, "__di_idx")));
    if (idx >= entries.length()) return;
    const entry = entries.get(.{ .int = @intCast(idx) });
    if (entry != .array) return;
    const path_val = entry.array.get(.{ .string = "path" });
    if (path_val == .string) {
        try obj.set(ctx.allocator, "__pathname", .{ .string = path_val.string });
    }
}

fn diRewind(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    try obj.set(ctx.allocator, "__di_idx", .{ .int = 0 });
    try syncCurrentEntry(ctx, obj);
    return .null;
}

fn diCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const entries = if (obj.get("__di_entries") == .array) obj.get("__di_entries").array else return .null;
    const idx: usize = @intCast(@max(0, objGetInt(obj, "__di_idx")));
    if (idx >= entries.length()) return .{ .bool = false };
    const entry = entries.get(.{ .int = @intCast(idx) });
    if (entry != .array) return .null;
    const path_val = entry.array.get(.{ .string = "path" });
    if (path_val != .string) return .null;

    const fi = try createFileInfoObj(ctx, path_val.string);
    return .{ .object = fi };
}

fn diKey(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    return .{ .int = objGetInt(obj, "__di_idx") };
}

fn diNext(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const idx = objGetInt(obj, "__di_idx");
    try obj.set(ctx.allocator, "__di_idx", .{ .int = idx + 1 });
    try syncCurrentEntry(ctx, obj);
    return .null;
}

fn diValid(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const entries = if (obj.get("__di_entries") == .array) obj.get("__di_entries").array else return .{ .bool = false };
    const idx: usize = @intCast(@max(0, objGetInt(obj, "__di_idx")));
    return .{ .bool = idx < entries.length() };
}

fn diIsDot(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const entries = if (obj.get("__di_entries") == .array) obj.get("__di_entries").array else return .{ .bool = false };
    const idx: usize = @intCast(@max(0, objGetInt(obj, "__di_idx")));
    if (idx >= entries.length()) return .{ .bool = false };
    const entry = entries.get(.{ .int = @intCast(idx) });
    if (entry != .array) return .{ .bool = false };
    const name = entry.array.get(.{ .string = "name" });
    if (name != .string) return .{ .bool = false };
    return .{ .bool = std.mem.eql(u8, name.string, ".") or std.mem.eql(u8, name.string, "..") };
}

// ==========================================
// RecursiveDirectoryIterator
// ==========================================

fn rdiConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len < 1 or args[0] != .string) return .null;
    const path = args[0].string;
    const flags: i64 = if (args.len >= 2) Value.toInt(args[1]) else 0;

    try obj.set(ctx.allocator, "__di_path", .{ .string = try createString(ctx, path) });
    try obj.set(ctx.allocator, "__di_flags", .{ .int = flags });
    try obj.set(ctx.allocator, "__di_idx", .{ .int = 0 });
    try obj.set(ctx.allocator, "__pathname", .{ .string = try createString(ctx, path) });

    const entries = try loadDirectoryEntries(ctx, path, flags);
    try obj.set(ctx.allocator, "__di_entries", .{ .array = entries });
    try syncCurrentEntry(ctx, obj);
    return .null;
}

fn rdiGetCurrentEntry(obj: *PhpObject) ?*PhpArray {
    const entries = if (obj.get("__di_entries") == .array) obj.get("__di_entries").array else return null;
    const idx: usize = @intCast(@max(0, objGetInt(obj, "__di_idx")));
    if (idx >= entries.length()) return null;
    const entry = entries.get(.{ .int = @intCast(idx) });
    if (entry != .array) return null;
    return entry.array;
}

fn rdiHasChildren(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const entry = rdiGetCurrentEntry(obj) orelse return .{ .bool = false };
    const is_dir = entry.get(.{ .string = "is_dir" });
    return .{ .bool = is_dir == .bool and is_dir.bool };
}

fn rdiGetChildren(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const entry = rdiGetCurrentEntry(obj) orelse return .null;
    const path_val = entry.get(.{ .string = "path" });
    if (path_val != .string) return .null;
    const flags = objGetInt(obj, "__di_flags");

    const child = try ctx.allocator.create(PhpObject);
    child.* = .{ .class_name = obj.class_name };
    try ctx.vm.objects.append(ctx.allocator, child);
    try child.set(ctx.allocator, "__di_path", .{ .string = path_val.string });
    try child.set(ctx.allocator, "__di_flags", .{ .int = flags });
    try child.set(ctx.allocator, "__di_idx", .{ .int = 0 });
    try child.set(ctx.allocator, "__pathname", .{ .string = path_val.string });

    const entries = try loadDirectoryEntries(ctx, path_val.string, flags);
    try child.set(ctx.allocator, "__di_entries", .{ .array = entries });

    ctx.vm.initObjectProperties(child, child.class_name) catch {};

    return .{ .object = child };
}

fn rdiGetSubPath(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .string = "" };
    // subpath is relative path from root to current directory
    const path = objGetStr(obj, "__di_path");
    const root = objGetStr(obj, "__rdi_root");
    if (root.len > 0 and std.mem.startsWith(u8, path, root)) {
        var sub = path[root.len..];
        if (sub.len > 0 and sub[0] == '/') sub = sub[1..];
        return .{ .string = try createString(ctx, sub) };
    }
    return .{ .string = "" };
}

fn rdiGetSubPathname(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .string = "" };
    const entry = rdiGetCurrentEntry(obj) orelse return .{ .string = "" };
    const name = entry.get(.{ .string = "name" });
    const sub_path = try rdiGetSubPath(ctx, &.{});
    if (sub_path != .string or sub_path.string.len == 0) {
        if (name == .string) return .{ .string = name.string };
        return .{ .string = "" };
    }
    if (name != .string) return sub_path;
    const result = try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ sub_path.string, name.string });
    try ctx.vm.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn rdiRewind(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return diRewind(ctx, args);
}

fn rdiCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const entry = rdiGetCurrentEntry(obj) orelse return .{ .bool = false };
    const path_val = entry.get(.{ .string = "path" });
    if (path_val != .string) return .null;
    const fi = try createFileInfoObj(ctx, path_val.string);
    return .{ .object = fi };
}

fn rdiKey(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .string = "" };
    const entry = rdiGetCurrentEntry(obj) orelse return .{ .string = "" };
    const path_val = entry.get(.{ .string = "path" });
    if (path_val != .string) return .{ .string = "" };
    return path_val;
}

fn rdiNext(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return diNext(ctx, args);
}

fn rdiValid(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return diValid(ctx, args);
}

// ==========================================
// FilterIterator
// ==========================================

fn filterConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len < 1 or args[0] != .object) return .null;
    try obj.set(ctx.allocator, "__fi_inner", args[0]);
    return .null;
}

fn filterGetInnerIterator(obj: *PhpObject) ?*PhpObject {
    const v = obj.get("__fi_inner");
    if (v == .object) return v.object;
    return null;
}

fn filterRewind(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const inner = filterGetInnerIterator(obj) orelse return .null;
    _ = try ctx.vm.callMethod(inner, "rewind", &.{});
    // advance to first accepted element
    try filterAdvanceToAccepted(ctx, obj, inner);
    return .null;
}

fn filterAdvanceToAccepted(ctx: *NativeContext, obj: *PhpObject, inner: *PhpObject) !void {
    while (true) {
        const valid = try ctx.vm.callMethod(inner, "valid", &.{});
        if (!valid.isTruthy()) break;
        const accepted = try ctx.vm.callMethod(obj, "accept", &.{});
        if (accepted.isTruthy()) break;
        _ = try ctx.vm.callMethod(inner, "next", &.{});
    }
}

fn filterCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const inner = filterGetInnerIterator(obj) orelse return .null;
    return ctx.vm.callMethod(inner, "current", &.{});
}

fn filterKey(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const inner = filterGetInnerIterator(obj) orelse return .null;
    return ctx.vm.callMethod(inner, "key", &.{});
}

fn filterNext(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const inner = filterGetInnerIterator(obj) orelse return .null;
    _ = try ctx.vm.callMethod(inner, "next", &.{});
    try filterAdvanceToAccepted(ctx, obj, inner);
    return .null;
}

fn filterValid(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const inner = filterGetInnerIterator(obj) orelse return .{ .bool = false };
    return ctx.vm.callMethod(inner, "valid", &.{});
}

fn filterGetInner(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const inner = filterGetInnerIterator(obj) orelse return .null;
    return .{ .object = inner };
}

// ==========================================
// RecursiveIteratorIterator
// ==========================================

// stores a stack of iterators to flatten recursive iteration
// mode: 0=LEAVES_ONLY, 1=SELF_FIRST, 2=CHILD_FIRST

fn riiConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len < 1 or args[0] != .object) return .null;
    const mode: i64 = if (args.len >= 2) Value.toInt(args[1]) else 0;

    try obj.set(ctx.allocator, "__rii_mode", .{ .int = mode });
    try obj.set(ctx.allocator, "__rii_depth", .{ .int = 0 });

    // store iterator stack as an array of objects
    const stack = try ctx.allocator.create(PhpArray);
    stack.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, stack);
    try stack.append(ctx.allocator, args[0]);
    try obj.set(ctx.allocator, "__rii_stack", .{ .array = stack });
    try obj.set(ctx.allocator, "__rii_valid", .{ .bool = false });

    return .null;
}

fn riiGetStack(obj: *PhpObject) ?*PhpArray {
    const v = obj.get("__rii_stack");
    if (v == .array) return v.array;
    return null;
}

fn riiCurrentIterator(obj: *PhpObject) ?*PhpObject {
    const stack = riiGetStack(obj) orelse return null;
    if (stack.length() == 0) return null;
    const top = stack.get(.{ .int = @as(i64, @intCast(stack.length())) - 1 });
    if (top == .object) return top.object;
    return null;
}

fn riiRewind(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const stack = riiGetStack(obj) orelse return .null;

    // reset stack to just the root iterator
    if (stack.length() == 0) return .null;
    const root = stack.get(.{ .int = 0 });
    stack.entries.items.len = 0;
    stack.next_int_key = 0;
    try stack.append(ctx.allocator, root);
    try obj.set(ctx.allocator, "__rii_depth", .{ .int = 0 });

    if (root != .object) return .null;
    _ = try ctx.vm.callMethod(root.object, "rewind", &.{});

    const valid = try ctx.vm.callMethod(root.object, "valid", &.{});
    try obj.set(ctx.allocator, "__rii_valid", valid);

    if (valid.isTruthy()) {
        const mode = objGetInt(obj, "__rii_mode");
        if (mode == 1) {
            // SELF_FIRST: current iterator valid, check if we can descend
            // but first yield the current item
        } else {
            // LEAVES_ONLY or CHILD_FIRST: descend into children first
            try riiDescend(ctx, obj);
        }
    }
    return .null;
}

fn riiDescend(ctx: *NativeContext, obj: *PhpObject) !void {
    const mode = objGetInt(obj, "__rii_mode");
    const stack = riiGetStack(obj) orelse return;

    while (true) {
        const iter_obj = riiCurrentIterator(obj) orelse return;
        const valid = try ctx.vm.callMethod(iter_obj, "valid", &.{});
        if (!valid.isTruthy()) return;

        const has_children = ctx.vm.callMethod(iter_obj, "hasChildren", &.{}) catch Value{ .bool = false };
        if (!has_children.isTruthy()) {
            if (mode == 1) {
                // SELF_FIRST: already yielding this item
            }
            return;
        }

        const children = ctx.vm.callMethod(iter_obj, "getChildren", &.{}) catch return;
        if (children != .object) return;

        _ = try ctx.vm.callMethod(children.object, "rewind", &.{});
        const child_valid = try ctx.vm.callMethod(children.object, "valid", &.{});
        if (!child_valid.isTruthy()) return;

        try stack.append(ctx.allocator, children);
        const depth = objGetInt(obj, "__rii_depth");
        try obj.set(ctx.allocator, "__rii_depth", .{ .int = depth + 1 });

        if (mode == 1) {
            // SELF_FIRST: check if this child can descend further
            continue;
        }
    }
}

fn riiCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const iter_obj = riiCurrentIterator(obj) orelse return .null;
    return ctx.vm.callMethod(iter_obj, "current", &.{});
}

fn riiKey(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const iter_obj = riiCurrentIterator(obj) orelse return .null;
    return ctx.vm.callMethod(iter_obj, "key", &.{});
}

fn riiNext(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    try riiAdvance(ctx, obj);
    return .null;
}

fn riiAdvance(ctx: *NativeContext, obj: *PhpObject) !void {
    const stack = riiGetStack(obj) orelse return;
    const mode = objGetInt(obj, "__rii_mode");

    if (mode == 1) {
        // SELF_FIRST: try to descend into children first
        const iter_obj = riiCurrentIterator(obj) orelse return;
        const has_children = ctx.vm.callMethod(iter_obj, "hasChildren", &.{}) catch Value{ .bool = false };
        if (has_children.isTruthy()) {
            const children = ctx.vm.callMethod(iter_obj, "getChildren", &.{}) catch {
                try riiAdvanceFlat(ctx, obj, stack);
                return;
            };
            if (children == .object) {
                _ = try ctx.vm.callMethod(children.object, "rewind", &.{});
                const child_valid = try ctx.vm.callMethod(children.object, "valid", &.{});
                if (child_valid.isTruthy()) {
                    try stack.append(ctx.allocator, children);
                    const depth = objGetInt(obj, "__rii_depth");
                    try obj.set(ctx.allocator, "__rii_depth", .{ .int = depth + 1 });
                    try obj.set(ctx.allocator, "__rii_valid", .{ .bool = true });
                    return;
                }
            }
        }
    }

    try riiAdvanceFlat(ctx, obj, stack);
}

fn riiAdvanceFlat(ctx: *NativeContext, obj: *PhpObject, stack: *PhpArray) !void {
    // advance current iterator
    while (stack.length() > 0) {
        const iter_val = stack.get(.{ .int = @as(i64, @intCast(stack.length())) - 1 });
        if (iter_val != .object) break;
        _ = try ctx.vm.callMethod(iter_val.object, "next", &.{});
        const valid = try ctx.vm.callMethod(iter_val.object, "valid", &.{});
        if (valid.isTruthy()) {
            try obj.set(ctx.allocator, "__rii_valid", .{ .bool = true });
            const mode = objGetInt(obj, "__rii_mode");
            if (mode != 1) {
                try riiDescend(ctx, obj);
            }
            return;
        }
        // pop exhausted iterator
        if (stack.entries.items.len > 1) {
            stack.entries.items.len -= 1;
            stack.next_int_key -= 1;
            const depth = objGetInt(obj, "__rii_depth");
            try obj.set(ctx.allocator, "__rii_depth", .{ .int = @max(0, depth - 1) });
        } else {
            break;
        }
    }
    try obj.set(ctx.allocator, "__rii_valid", .{ .bool = false });
}

fn riiValid(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    return obj.get("__rii_valid");
}

fn riiGetDepth(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    return .{ .int = objGetInt(obj, "__rii_depth") };
}

fn riiGetInner(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const iter_obj = riiCurrentIterator(obj) orelse return .null;
    return .{ .object = iter_obj };
}

fn riiGetSubIterator(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const stack = riiGetStack(obj) orelse return .null;
    const depth: usize = if (args.len >= 1) @intCast(@max(0, Value.toInt(args[0]))) else @intCast(@max(0, objGetInt(obj, "__rii_depth")));
    if (depth >= stack.length()) return .null;
    return stack.get(.{ .int = @intCast(depth) });
}
