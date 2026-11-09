const std = @import("std");
const bundle = @import("../bundle.zig");
const filesystem = @import("filesystem.zig");
const platform = @import("../platform.zig");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const spl = @import("spl.zig");
const VM = vm_mod.VM;
const NativeResult = vm_mod.NativeResult;
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

    var outer_iter = vm_mod.InterfaceDef{ .name = "OuterIterator" };
    outer_iter.parent = "Iterator";
    try outer_iter.methods.append(a, "getInnerIterator");
    try vm.interfaces.put(a, "OuterIterator", outer_iter);

    var seekable_iter = vm_mod.InterfaceDef{ .name = "SeekableIterator" };
    seekable_iter.parent = "Iterator";
    try seekable_iter.methods.append(a, "seek");
    try vm.interfaces.put(a, "SeekableIterator", seekable_iter);

    // SplFileInfo
    var fi_def = ClassDef{ .name = "SplFileInfo" };
    for ([_][]const u8{
        "__construct", "getFilename", "getExtension", "getBasename",
        "getPathname", "getPath",     "getRealPath",  "getSize",
        "isDir",       "isFile",      "isLink",       "isReadable",
        "isWritable",  "getMTime",    "getCTime",     "getATime",
        "getType",     "__toString",  "openFile",
    }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "__construct")) 1 else if (std.mem.eql(u8, m, "openFile")) 1 else 0;
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
    try vm.native_fns.put(a, "SplFileInfo::openFile", fiOpenFile);

    // DirectoryIterator
    var di_def = ClassDef{ .name = "DirectoryIterator" };
    di_def.parent = "SplFileInfo";
    try di_def.interfaces.append(a, "SeekableIterator");
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

    // FilesystemIterator (DirectoryIterator with SKIP_DOTS by default)
    var fsi_def = ClassDef{ .name = "FilesystemIterator" };
    fsi_def.parent = "DirectoryIterator";
    try fsi_def.interfaces.append(a, "Iterator");
    for ([_][]const u8{
        "__construct", "rewind", "current", "key", "next", "valid",
    }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "__construct")) 2 else 0;
        try fsi_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try fsi_def.constants.put(a, "CURRENT_AS_PATHNAME", .{ .int = 0x0020 });
    try fsi_def.constants.put(a, "CURRENT_AS_FILEINFO", .{ .int = 0x0000 });
    try fsi_def.constants.put(a, "CURRENT_AS_SELF", .{ .int = 0x0010 });
    try fsi_def.constants.put(a, "KEY_AS_PATHNAME", .{ .int = 0x0000 });
    try fsi_def.constants.put(a, "KEY_AS_FILENAME", .{ .int = 0x0100 });
    try fsi_def.constants.put(a, "FOLLOW_SYMLINKS", .{ .int = 0x0200 });
    try fsi_def.constants.put(a, "SKIP_DOTS", .{ .int = 0x1000 });
    try fsi_def.constants.put(a, "UNIX_PATHS", .{ .int = 0x2000 });
    try vm.classes.put(a, "FilesystemIterator", fsi_def);
    try vm.native_fns.put(a, "FilesystemIterator::__construct", fsiConstruct);
    try vm.native_fns.put(a, "FilesystemIterator::rewind", diRewind);
    try vm.native_fns.put(a, "FilesystemIterator::current", diCurrent);
    try vm.native_fns.put(a, "FilesystemIterator::key", diKey);
    try vm.native_fns.put(a, "FilesystemIterator::next", diNext);
    try vm.native_fns.put(a, "FilesystemIterator::valid", diValid);

    // RecursiveDirectoryIterator
    var rdi_def = ClassDef{ .name = "RecursiveDirectoryIterator" };
    rdi_def.parent = "DirectoryIterator";
    try rdi_def.interfaces.append(a, "RecursiveIterator");
    for ([_][]const u8{
        "__construct", "hasChildren", "getChildren", "getSubPath", "getSubPathname",
        "rewind",      "current",     "key",         "next",       "valid",
    }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "__construct")) 2 else 0;
        try rdi_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try rdi_def.constants.put(a, "SKIP_DOTS", .{ .int = 0x1000 });
    try rdi_def.constants.put(a, "FOLLOW_SYMLINKS", .{ .int = 0x0200 });
    try rdi_def.constants.put(a, "CURRENT_AS_PATHNAME", .{ .int = 0x0020 });
    try rdi_def.constants.put(a, "CURRENT_AS_SELF", .{ .int = 0x0010 });
    try rdi_def.constants.put(a, "UNIX_PATHS", .{ .int = 0x2000 });
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

    // MultipleIterator
    var mi_def = ClassDef{ .name = "MultipleIterator" };
    try mi_def.interfaces.append(a, "Iterator");
    for ([_][]const u8{ "__construct", "attachIterator", "detachIterator", "containsIterator", "countIterators", "rewind", "valid", "current", "key", "next", "getFlags", "setFlags" }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "attachIterator")) 2 else if (std.mem.eql(u8, m, "detachIterator") or std.mem.eql(u8, m, "containsIterator") or std.mem.eql(u8, m, "setFlags")) 1 else 0;
        try mi_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try mi_def.constants.put(a, "MIT_NEED_ANY", .{ .int = 0 });
    try mi_def.constants.put(a, "MIT_NEED_ALL", .{ .int = 1 });
    try mi_def.constants.put(a, "MIT_KEYS_NUMERIC", .{ .int = 0 });
    try mi_def.constants.put(a, "MIT_KEYS_ASSOC", .{ .int = 2 });
    try vm.classes.put(a, "MultipleIterator", mi_def);
    try vm.native_fns.put(a, "MultipleIterator::__construct", miConstruct);
    try vm.native_fns.put(a, "MultipleIterator::attachIterator", miAttach);
    try vm.native_fns.put(a, "MultipleIterator::detachIterator", miDetach);
    try vm.native_fns.put(a, "MultipleIterator::containsIterator", miContains);
    try vm.native_fns.put(a, "MultipleIterator::countIterators", miCountIterators);
    try vm.native_fns.put(a, "MultipleIterator::rewind", miRewind);
    try vm.native_fns.put(a, "MultipleIterator::valid", miValid);
    try vm.native_fns.put(a, "MultipleIterator::current", miCurrent);
    try vm.native_fns.put(a, "MultipleIterator::key", miKey);
    try vm.native_fns.put(a, "MultipleIterator::next", miNext);
    try vm.native_fns.put(a, "MultipleIterator::getFlags", miGetFlags);
    try vm.native_fns.put(a, "MultipleIterator::setFlags", miSetFlags);

    // RecursiveArrayIterator (extends ArrayIterator, adds hasChildren/getChildren)
    var rai_def = ClassDef{ .name = "RecursiveArrayIterator" };
    rai_def.parent = "ArrayIterator";
    try rai_def.interfaces.append(a, "RecursiveIterator");
    try rai_def.methods.put(a, "hasChildren", .{ .name = "hasChildren", .arity = 0 });
    try rai_def.methods.put(a, "getChildren", .{ .name = "getChildren", .arity = 0 });
    try rai_def.constants.put(a, "CHILD_ARRAYS_ONLY", .{ .int = CHILD_ARRAYS_ONLY });
    try vm.classes.put(a, "RecursiveArrayIterator", rai_def);
    try vm.native_fns.put(a, "RecursiveArrayIterator::hasChildren", raiHasChildren);
    try vm.native_fns.put(a, "RecursiveArrayIterator::getChildren", raiGetChildren);

    // GlobIterator (extends DirectoryIterator behaviorally; backed by glob results)
    var gi_def = ClassDef{ .name = "GlobIterator" };
    gi_def.parent = "SplFileInfo";
    try gi_def.interfaces.append(a, "Iterator");
    try gi_def.interfaces.append(a, "Countable");
    for ([_][]const u8{ "__construct", "rewind", "valid", "current", "key", "next", "count" }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "__construct")) 2 else 0;
        try gi_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try vm.classes.put(a, "GlobIterator", gi_def);
    try vm.native_fns.put(a, "GlobIterator::__construct", giConstruct);
    try vm.native_fns.put(a, "GlobIterator::rewind", giRewind);
    try vm.native_fns.put(a, "GlobIterator::valid", giValid);
    try vm.native_fns.put(a, "GlobIterator::current", giCurrent);
    try vm.native_fns.put(a, "GlobIterator::key", giKey);
    try vm.native_fns.put(a, "GlobIterator::next", giNext);
    try vm.native_fns.put(a, "GlobIterator::count", giCount);

    try @import("spl_iterator_classes.zig").register(vm, a);
}

// ==========================================
// helpers
// ==========================================

fn getThis(ctx: *NativeContext) ?*PhpObject {
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

fn objGetStr(obj: *PhpObject, key: []const u8) []const u8 {
    const v = obj.get(key);
    if (v == .string) return v.string.bytes();
    return "";
}

fn objGetInt(obj: *PhpObject, key: []const u8) i64 {
    const v = obj.get(key);
    if (v == .int) return v.int;
    return 0;
}

fn createFileInfoObj(ctx: *NativeContext, pathname: []const u8) !*PhpObject {
    const obj = try ctx.createObject("SplFileInfo");
    const path = try Value.String.create(ctx.allocator, pathname);
    defer path.release();
    try obj.set(ctx.allocator, "__pathname", .{ .string = path });
    return obj;
}

fn lastSep(path: []const u8) ?usize {
    var i = path.len;
    while (i > 0) : (i -= 1) if (platform.isSep(path[i - 1])) return i - 1;
    return null;
}

fn basename(path: []const u8) []const u8 {
    if (lastSep(path)) |idx| {
        return path[idx + 1 ..];
    }
    return path;
}

fn dirname(path: []const u8) []const u8 {
    if (lastSep(path)) |idx| {
        if (idx == 0) return platform.sep_str;
        return path[0..idx];
    }
    return ".";
}

fn statPath(spelled: []const u8) ?std.Io.File.Stat {
    var os_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = bundle.osPath(&os_buf, spelled);
    if (bundle.find(path)) |hit| return packedStat(hit);
    if (!std.fs.path.isAbsolute(path)) return std.Io.Dir.cwd().statFile(platform.io, path, .{}) catch null;
    const file = std.Io.Dir.openFileAbsolute(platform.io, path, .{}) catch {
        var dir = std.Io.Dir.openDirAbsolute(platform.io, path, .{}) catch return null;
        defer dir.close(platform.io);
        return dir.stat(platform.io) catch null;
    };
    defer file.close(platform.io);
    return file.stat(platform.io) catch null;
}

// a file or directory of the executable's packed application, read-only
fn packedStat(hit: bundle.Hit) std.Io.File.Stat {
    const mtime: std.Io.Timestamp = .{ .nanoseconds = switch (hit) {
        .file => |entry| @as(i96, entry.mtime) * std.time.ns_per_s,
        .dir => 0,
    } };
    return .{
        .inode = 0,
        .nlink = 1,
        .size = switch (hit) {
            .file => |entry| entry.source.len,
            .dir => 0,
        },
        .permissions = platform.permissionsFromMode(if (hit == .file) 0o444 else 0o555),
        .kind = if (hit == .file) .file else .directory,
        .atime = mtime,
        .mtime = mtime,
        .ctime = mtime,
        .block_size = 1,
    };
}

// ==========================================
// SplFileInfo
// ==========================================

fn fiConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__pathname", args[0]);
    return NativeResult.scalar(.null);
}

fn fiGetFilename(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const path = objGetStr(obj, "__pathname");
    return NativeResult.copyString(ctx.allocator, basename(path));
}

fn fiGetExtension(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const name = basename(objGetStr(obj, "__pathname"));
    if (std.mem.lastIndexOfScalar(u8, name, '.')) |idx| {
        return NativeResult.copyString(ctx.allocator, name[idx + 1 ..]);
    }
    return NativeResult.literal("");
}

fn fiGetBasename(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    var name = basename(objGetStr(obj, "__pathname"));
    if (args.len >= 1 and args[0] == .string) {
        const suffix = args[0].string.bytes();
        if (std.mem.endsWith(u8, name, suffix)) {
            name = name[0 .. name.len - suffix.len];
        }
    }
    return NativeResult.copyString(ctx.allocator, name);
}

fn fiGetPathname(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(obj.get("__pathname"));
}

fn fiGetPath(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.copyString(ctx.allocator, dirname(objGetStr(obj, "__pathname")));
}

fn fiGetRealPath(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const path = objGetStr(obj, "__pathname");
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    if (bundle.canonicalPath(&buf, path)) |packed_path| return NativeResult.copyString(ctx.allocator, packed_path);
    const real = platform.realpath(path, &buf) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.copyString(ctx.allocator, real);
}

fn fiGetSize(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const stat = statPath(objGetStr(obj, "__pathname")) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = @intCast(stat.size) });
}

fn fiIsDir(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const path = objGetStr(obj, "__pathname");
    const stat = statPath(path) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = stat.kind == .directory });
}

fn fiIsFile(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const path = objGetStr(obj, "__pathname");
    const stat = statPath(path) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = stat.kind == .file });
}

fn fiIsLink(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const path = objGetStr(obj, "__pathname");
    const stat = statPath(path) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = stat.kind == .sym_link });
}

fn fiIsReadable(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = true });
}

fn fiIsWritable(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = true });
}

fn fiGetMTime(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const stat = statPath(objGetStr(obj, "__pathname")) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = @intCast(@divTrunc(stat.mtime.nanoseconds, std.time.ns_per_s)) });
}

fn fiGetCTime(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const stat = statPath(objGetStr(obj, "__pathname")) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = @intCast(@divTrunc(stat.ctime.nanoseconds, std.time.ns_per_s)) });
}

fn fiGetATime(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const stat = statPath(objGetStr(obj, "__pathname")) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = @intCast(@divTrunc((stat.atime orelse stat.mtime).nanoseconds, std.time.ns_per_s)) });
}

fn fiGetType(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.literal("unknown");
    const stat = statPath(objGetStr(obj, "__pathname")) orelse return NativeResult.literal("unknown");
    return switch (stat.kind) {
        .directory => NativeResult.literal("dir"),
        .file => NativeResult.literal("file"),
        .sym_link => NativeResult.literal("link"),
        else => NativeResult.literal("unknown"),
    };
}

fn fiToString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.literal("");
    return NativeResult.share(obj.get("__pathname"));
}

fn fiOpenFile(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const path = objGetStr(this, "__pathname");
    const mode: Value = if (args.len >= 1 and args[0] == .string) args[0] else .{ .string = Value.String.borrowed("r") };
    const obj = try ctx.createObject("SplFileObject");
    _ = try ctx.vm.callMethod(obj, "__construct", &.{ .{ .string = Value.String.borrowed(path) }, mode });
    return NativeResult.borrowed(.{ .object = obj });
}

// ==========================================
// DirectoryIterator
// ==========================================

fn diConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    const path = args[0].string.bytes();
    try obj.set(ctx.allocator, "__di_path", args[0]);
    try obj.set(ctx.allocator, "__di_idx", .{ .int = 0 });

    const entries = try loadDirectoryEntries(ctx, path, 0);
    try obj.set(ctx.allocator, "__di_entries", .{ .array = entries });
    try syncCurrentEntry(ctx, obj);
    return NativeResult.scalar(.null);
}

const SKIP_DOTS: i64 = 0x1000;

fn loadDirectoryEntries(ctx: *NativeContext, path: []const u8, flags: i64) RuntimeError!*PhpArray {
    const arr = try ctx.createArray();

    // the disk and the executable's packed application both contribute, a
    // name once
    var os_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = bundle.osPath(&os_buf, path);
    var listing = bundle.listDir(dir_path);
    var dir_opt: ?std.Io.Dir = std.Io.Dir.cwd().openDir(platform.io, dir_path, .{ .iterate = true }) catch null;
    defer if (dir_opt) |*d| d.close(platform.io);
    if (listing == null and dir_opt == null) return arr;

    const skip_dots = (flags & SKIP_DOTS) != 0;
    if (!skip_dots) {
        inline for (.{ ".", ".." }) |dot_name| try appendDirectoryEntry(ctx, arr, .{ .dir = path, .name = dot_name, .is_dir = true });
    }
    if (dir_opt) |*dir| {
        var iter = dir.iterate();
        while (iter.next(platform.io) catch null) |entry| {
            if (skip_dots and (std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, ".."))) continue;
            try appendDirectoryEntry(ctx, arr, .{ .dir = path, .name = entry.name, .is_dir = entry.kind == .directory });
        }
    }
    if (listing) |*packed_names| while (packed_names.next()) |child| {
        if (dir_opt) |dir| if (filesystem.dirHas(dir, child.name)) continue;
        try appendDirectoryEntry(ctx, arr, .{ .dir = path, .name = child.name, .is_dir = child.kind == .dir });
    };
    return arr;
}

const DirectoryEntry = struct { dir: []const u8, name: []const u8, is_dir: bool };

fn appendDirectoryEntry(ctx: *NativeContext, arr: *PhpArray, entry: DirectoryEntry) RuntimeError!void {
    const full = try std.fmt.allocPrint(ctx.allocator, "{s}{s}{s}", .{ entry.dir, platform.sep_str, entry.name });
    const full_owned = try Value.String.adopt(ctx.allocator, full);
    defer full_owned.release();
    const entry_arr = try ctx.createArray();
    try entry_arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("name") }, entry.name);
    try entry_arr.set(ctx.allocator, .{ .string = Value.String.borrowed("path") }, .{ .string = full_owned });
    try entry_arr.set(ctx.allocator, .{ .string = Value.String.borrowed("is_dir") }, .{ .bool = entry.is_dir });
    try arr.append(ctx.allocator, .{ .array = entry_arr });
}

fn syncCurrentEntry(ctx: *NativeContext, obj: *PhpObject) !void {
    const entries = if (obj.get("__di_entries") == .array) obj.get("__di_entries").array else return;
    const idx: usize = @intCast(@max(0, objGetInt(obj, "__di_idx")));
    if (idx >= entries.length()) return;
    const entry = entries.get(.{ .int = @intCast(idx) });
    if (entry != .array) return;
    const path_val = entry.array.get(.{ .string = Value.String.borrowed("path") });
    if (path_val == .string) {
        try obj.set(ctx.allocator, "__pathname", path_val);
    }
}

fn fsiConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    const path = args[0].string.bytes();
    try obj.set(ctx.allocator, "__di_path", args[0]);
    try obj.set(ctx.allocator, "__di_idx", .{ .int = 0 });
    // FilesystemIterator skips dots by default
    const entries = try loadDirectoryEntries(ctx, path, SKIP_DOTS);
    try obj.set(ctx.allocator, "__di_entries", .{ .array = entries });
    try syncCurrentEntry(ctx, obj);
    return NativeResult.scalar(.null);
}

fn diRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__di_idx", .{ .int = 0 });
    try syncCurrentEntry(ctx, obj);
    return NativeResult.scalar(.null);
}

fn diCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // PHP's DirectoryIterator::current() returns the iterator itself
    // so methods like isDot(), getFilename(), getPathname() work on $entry
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const entries = if (obj.get("__di_entries") == .array) obj.get("__di_entries").array else return NativeResult.scalar(.null);
    const idx: usize = @intCast(@max(0, objGetInt(obj, "__di_idx")));
    if (idx >= entries.length()) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.borrowed(.{ .object = obj });
}

fn diKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.scalar(.{ .int = objGetInt(obj, "__di_idx") });
}

fn diNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const idx = objGetInt(obj, "__di_idx");
    try obj.set(ctx.allocator, "__di_idx", .{ .int = idx + 1 });
    try syncCurrentEntry(ctx, obj);
    return NativeResult.scalar(.null);
}

fn diValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const entries = if (obj.get("__di_entries") == .array) obj.get("__di_entries").array else return NativeResult.scalar(.{ .bool = false });
    const idx: usize = @intCast(@max(0, objGetInt(obj, "__di_idx")));
    return NativeResult.scalar(.{ .bool = idx < entries.length() });
}

fn diIsDot(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const entries = if (obj.get("__di_entries") == .array) obj.get("__di_entries").array else return NativeResult.scalar(.{ .bool = false });
    const idx: usize = @intCast(@max(0, objGetInt(obj, "__di_idx")));
    if (idx >= entries.length()) return NativeResult.scalar(.{ .bool = false });
    const entry = entries.get(.{ .int = @intCast(idx) });
    if (entry != .array) return NativeResult.scalar(.{ .bool = false });
    const name = entry.array.get(.{ .string = Value.String.borrowed("name") });
    if (name != .string) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = std.mem.eql(u8, name.string.bytes(), ".") or std.mem.eql(u8, name.string.bytes(), "..") });
}

// ==========================================
// RecursiveDirectoryIterator
// ==========================================

fn rdiConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    const path = args[0].string.bytes();
    const flags: i64 = if (args.len >= 2) Value.toInt(args[1]) else 0;

    try obj.set(ctx.allocator, "__di_path", args[0]);
    try obj.set(ctx.allocator, "__di_flags", .{ .int = flags });
    try obj.set(ctx.allocator, "__di_idx", .{ .int = 0 });
    try obj.set(ctx.allocator, "__pathname", args[0]);
    try obj.set(ctx.allocator, "__rdi_root", args[0]);

    const entries = try loadDirectoryEntries(ctx, path, flags);
    try obj.set(ctx.allocator, "__di_entries", .{ .array = entries });
    try syncCurrentEntry(ctx, obj);
    return NativeResult.scalar(.null);
}

fn rdiGetCurrentEntry(obj: *PhpObject) ?*PhpArray {
    const entries = if (obj.get("__di_entries") == .array) obj.get("__di_entries").array else return null;
    const idx: usize = @intCast(@max(0, objGetInt(obj, "__di_idx")));
    if (idx >= entries.length()) return null;
    const entry = entries.get(.{ .int = @intCast(idx) });
    if (entry != .array) return null;
    return entry.array;
}

fn rdiHasChildren(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const entry = rdiGetCurrentEntry(obj) orelse return NativeResult.scalar(.{ .bool = false });
    // php never recurses into . and ..
    const name = entry.get(.{ .string = Value.String.borrowed("name") });
    if (name == .string and (std.mem.eql(u8, name.string.bytes(), ".") or std.mem.eql(u8, name.string.bytes(), ".."))) return NativeResult.scalar(.{ .bool = false });
    const is_dir = entry.get(.{ .string = Value.String.borrowed("is_dir") });
    return NativeResult.scalar(.{ .bool = is_dir == .bool and is_dir.bool });
}

fn rdiGetChildren(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const entry = rdiGetCurrentEntry(obj) orelse return NativeResult.scalar(.null);
    const path_val = entry.get(.{ .string = Value.String.borrowed("path") });
    if (path_val != .string) return NativeResult.scalar(.null);
    const flags = objGetInt(obj, "__di_flags");

    const child = try ctx.createObject(obj.class_name);
    try child.set(ctx.allocator, "__di_path", .{ .string = path_val.string });
    try child.set(ctx.allocator, "__di_flags", .{ .int = flags });
    try child.set(ctx.allocator, "__di_idx", .{ .int = 0 });
    try child.set(ctx.allocator, "__pathname", .{ .string = path_val.string });
    const root = obj.get("rootPath");
    if (root != .null) try child.set(ctx.allocator, "rootPath", root);
    const rdi_root = obj.get("__rdi_root");
    if (rdi_root != .null) try child.set(ctx.allocator, "__rdi_root", rdi_root);
    try child.set(ctx.allocator, "subPath", .null);

    const entries = try loadDirectoryEntries(ctx, path_val.string.bytes(), flags);
    try child.set(ctx.allocator, "__di_entries", .{ .array = entries });
    try syncCurrentEntry(ctx, child);

    return NativeResult.borrowed(.{ .object = child });
}

fn rdiGetSubPath(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.literal("");
    // subpath is relative path from root to current directory
    const path = objGetStr(obj, "__di_path");
    const root = objGetStr(obj, "__rdi_root");
    if (root.len > 0 and std.mem.startsWith(u8, path, root)) {
        var sub = path[root.len..];
        if (sub.len > 0 and sub[0] == '/') sub = sub[1..];
        return NativeResult.copyString(ctx.allocator, sub);
    }
    return NativeResult.literal("");
}

fn rdiGetSubPathname(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.literal("");
    const entry = rdiGetCurrentEntry(obj) orelse return NativeResult.literal("");
    const name = entry.get(.{ .string = Value.String.borrowed("name") });
    const sub_result = try rdiGetSubPath(ctx, &.{});
    const sub_path = sub_result.value;
    defer if (sub_path == .string) sub_path.string.release();
    if (sub_path != .string or sub_path.string.bytes().len == 0) {
        if (name == .string) return NativeResult.shareString(name.string);
        return NativeResult.literal("");
    }
    if (name != .string) return NativeResult.share(sub_path);
    const result = try std.fmt.allocPrint(ctx.allocator, "{s}{s}{s}", .{ sub_path.string.bytes(), platform.sep_str, name.string.bytes() });
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result));
}

fn rdiRewind(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return diRewind(ctx, args);
}

fn rdiCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const entry = rdiGetCurrentEntry(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const path_val = entry.get(.{ .string = Value.String.borrowed("path") });
    if (path_val != .string) return NativeResult.scalar(.null);
    const fi = try createFileInfoObj(ctx, path_val.string.bytes());
    return NativeResult.borrowed(.{ .object = fi });
}

fn rdiKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.literal("");
    const entry = rdiGetCurrentEntry(obj) orelse return NativeResult.literal("");
    const path_val = entry.get(.{ .string = Value.String.borrowed("path") });
    if (path_val != .string) return NativeResult.literal("");
    return NativeResult.share(path_val);
}

fn rdiNext(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return diNext(ctx, args);
}

fn rdiValid(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return diValid(ctx, args);
}

// ==========================================
// MultipleIterator
// ==========================================

fn miConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const flags: i64 = if (args.len >= 1) Value.toInt(args[0]) else 1;
    try obj.set(ctx.allocator, "__mi_flags", .{ .int = flags });
    const iters = try ctx.createArray();
    const keys = try ctx.createArray();
    try obj.set(ctx.allocator, "__mi_iters", .{ .array = iters });
    try obj.set(ctx.allocator, "__mi_keys", .{ .array = keys });
    return NativeResult.scalar(.null);
}

fn miAttach(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    if (args[0] != .object and args[0] != .generator) return NativeResult.scalar(.null);
    const iters_v = obj.get("__mi_iters");
    const keys_v = obj.get("__mi_keys");
    if (iters_v != .array or keys_v != .array) return NativeResult.scalar(.null);
    try iters_v.array.append(ctx.allocator, args[0]);
    if (args.len >= 2 and (args[1] == .string or args[1] == .int)) {
        try keys_v.array.append(ctx.allocator, args[1]);
    } else {
        try keys_v.array.append(ctx.allocator, .null);
    }
    return NativeResult.scalar(.null);
}

fn miDetach(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.null);
    const iters_v = obj.get("__mi_iters");
    const keys_v = obj.get("__mi_keys");
    if (iters_v != .array or keys_v != .array) return NativeResult.scalar(.null);
    var i: usize = 0;
    while (i < iters_v.array.entries.items.len) : (i += 1) {
        const e = iters_v.array.entries.items[i];
        if (e.value == .object and e.value.object == args[0].object) {
            _ = iters_v.array.entries.orderedRemove(i);
            if (i < keys_v.array.entries.items.len) _ = keys_v.array.entries.orderedRemove(i);
            return NativeResult.scalar(.null);
        }
    }
    return NativeResult.scalar(.null);
}

fn miContains(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const iters_v = obj.get("__mi_iters");
    if (iters_v != .array) return NativeResult.scalar(.{ .bool = false });
    for (iters_v.array.entries.items) |e| {
        if (e.value == .object and e.value.object == args[0].object) return NativeResult.scalar(.{ .bool = true });
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn miCountIterators(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const iters_v = obj.get("__mi_iters");
    if (iters_v != .array) return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = iters_v.array.length() });
}

fn miCallValid(ctx: *NativeContext, v: Value) !bool {
    if (v == .object) {
        const r = try ctx.vm.callMethod(v.object, "valid", &.{});
        return r.isTruthy();
    } else if (v == .generator) {
        return v.generator.state != .completed;
    }
    return false;
}

fn miCallCurrent(ctx: *NativeContext, v: Value) !Value {
    if (v == .object) return try ctx.vm.callMethod(v.object, "current", &.{});
    if (v == .generator) return v.generator.current_value;
    return .null;
}

fn miCallKey(ctx: *NativeContext, v: Value) !Value {
    if (v == .object) return try ctx.vm.callMethod(v.object, "key", &.{});
    if (v == .generator) return v.generator.current_key;
    return .null;
}

fn miCallNext(ctx: *NativeContext, v: Value) !void {
    if (v == .object) {
        _ = try ctx.vm.callMethod(v.object, "next", &.{});
    } else if (v == .generator) {
        try ctx.vm.resumeGenerator(v.generator, .null);
    }
}

fn miCallRewind(ctx: *NativeContext, v: Value) !void {
    if (v == .object) {
        _ = try ctx.vm.callMethod(v.object, "rewind", &.{});
    } else if (v == .generator) {
        // generator auto-starts on first valid()/current() call; if not yet
        // started, kick it off so current/key are populated
        if (v.generator.state == .created) try ctx.vm.resumeGenerator(v.generator, .null);
    }
}

fn miRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const iters_v = obj.get("__mi_iters");
    if (iters_v != .array) return NativeResult.scalar(.null);
    for (iters_v.array.entries.items) |e| try miCallRewind(ctx, e.value);
    return NativeResult.scalar(.null);
}

fn miValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const iters_v = obj.get("__mi_iters");
    if (iters_v != .array or iters_v.array.length() == 0) return NativeResult.scalar(.{ .bool = false });
    const flags = objGetInt(obj, "__mi_flags");
    const need_all = (flags & 1) != 0;
    var any: bool = false;
    var all: bool = true;
    for (iters_v.array.entries.items) |e| {
        if (try miCallValid(ctx, e.value)) any = true else all = false;
    }
    return NativeResult.scalar(.{ .bool = if (need_all) all else any });
}

fn miCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const iters_v = obj.get("__mi_iters");
    const keys_v = obj.get("__mi_keys");
    if (iters_v != .array) return NativeResult.scalar(.null);
    const flags = objGetInt(obj, "__mi_flags");
    const assoc = (flags & 2) != 0;
    const result = try ctx.createArray();
    var idx: i64 = 0;
    for (iters_v.array.entries.items, 0..) |e, i| {
        var v: Value = .null;
        if (try miCallValid(ctx, e.value)) v = try miCallCurrent(ctx, e.value);
        if (assoc and keys_v == .array and i < keys_v.array.entries.items.len) {
            const k = keys_v.array.entries.items[i].value;
            if (k == .string) try result.set(ctx.allocator, .{ .string = k.string }, v) else try result.append(ctx.allocator, v);
        } else {
            try result.set(ctx.allocator, .{ .int = idx }, v);
            idx += 1;
        }
    }
    return NativeResult.borrowed(.{ .array = result });
}

fn miKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const iters_v = obj.get("__mi_iters");
    const keys_v = obj.get("__mi_keys");
    if (iters_v != .array) return NativeResult.scalar(.null);
    const flags = objGetInt(obj, "__mi_flags");
    const assoc = (flags & 2) != 0;
    const result = try ctx.createArray();
    var idx: i64 = 0;
    for (iters_v.array.entries.items, 0..) |e, i| {
        var v: Value = .null;
        if (try miCallValid(ctx, e.value)) v = try miCallKey(ctx, e.value);
        if (assoc and keys_v == .array and i < keys_v.array.entries.items.len) {
            const k = keys_v.array.entries.items[i].value;
            if (k == .string) try result.set(ctx.allocator, .{ .string = k.string }, v) else try result.append(ctx.allocator, v);
        } else {
            try result.set(ctx.allocator, .{ .int = idx }, v);
            idx += 1;
        }
    }
    return NativeResult.borrowed(.{ .array = result });
}

fn miNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const iters_v = obj.get("__mi_iters");
    if (iters_v != .array) return NativeResult.scalar(.null);
    for (iters_v.array.entries.items) |e| try miCallNext(ctx, e.value);
    return NativeResult.scalar(.null);
}

fn miGetFlags(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = objGetInt(obj, "__mi_flags") });
}

fn miSetFlags(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__mi_flags", .{ .int = Value.toInt(args[0]) });
    return NativeResult.scalar(.null);
}

// ==========================================
// RecursiveArrayIterator
// ==========================================

// RecursiveArrayIterator::CHILD_ARRAYS_ONLY
const CHILD_ARRAYS_ONLY = 4;

fn raiHasChildren(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const cur = try spl.iteratorCurrent(ctx, obj) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = cur == .array or (cur == .object and spl.iteratorFlags(obj) & CHILD_ARRAYS_ONLY == 0) });
}

// an object element that is already one of these iterators is the child
// itself; any other element becomes the storage of a new one
fn raiGetChildren(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const cur = try spl.iteratorCurrent(ctx, obj) orelse return NativeResult.scalar(.null);
    if (cur == .object) {
        if (spl.iteratorFlags(obj) & CHILD_ARRAYS_ONLY != 0) return NativeResult.scalar(.null);
        if (ctx.vm.isInstanceOf(cur.object.class_name, obj.class_name)) return NativeResult.share(cur);
    }
    const child = try ctx.createObject(obj.class_name);
    _ = try ctx.vm.callMethod(child, "__construct", &.{ cur, .{ .int = spl.iteratorFlags(obj) } });
    return NativeResult.borrowed(.{ .object = child });
}

// ==========================================
// GlobIterator
// ==========================================

fn giConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__gi_pattern", args[0]);
    const result = try ctx.vm.callByName("glob", &.{args[0]});
    if (result == .array) {
        try obj.set(ctx.allocator, "__gi_results", result);
    } else {
        const empty = try ctx.vm.allocArray();
        try obj.set(ctx.allocator, "__gi_results", .{ .array = empty });
    }
    try obj.set(ctx.allocator, "__gi_pos", .{ .int = 0 });
    return NativeResult.scalar(.null);
}

fn giRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__gi_pos", .{ .int = 0 });
    const results = obj.get("__gi_results");
    if (results == .array and results.array.length() > 0) {
        const path = results.array.get(.{ .int = 0 });
        if (path == .string) {
            try obj.set(ctx.allocator, "__pathname", path);
        }
    }
    return NativeResult.scalar(.null);
}

fn giValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const results = obj.get("__gi_results");
    if (results != .array) return NativeResult.scalar(.{ .bool = false });
    const pos = objGetInt(obj, "__gi_pos");
    return NativeResult.scalar(.{ .bool = pos < results.array.length() });
}

fn giCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const results = obj.get("__gi_results");
    if (results != .array) return NativeResult.scalar(.null);
    const pos = objGetInt(obj, "__gi_pos");
    if (pos < 0 or pos >= results.array.length()) return NativeResult.scalar(.null);
    const path = results.array.get(.{ .int = pos });
    if (path != .string) return NativeResult.scalar(.null);
    const fi = try createFileInfoObj(ctx, path.string.bytes());
    fi.class_name = "GlobIterator";
    return NativeResult.borrowed(.{ .object = fi });
}

fn giKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const results = obj.get("__gi_results");
    if (results != .array) return NativeResult.scalar(.{ .int = 0 });
    const pos = objGetInt(obj, "__gi_pos");
    if (pos < 0 or pos >= results.array.length()) return NativeResult.scalar(.{ .int = 0 });
    const path = results.array.get(.{ .int = pos });
    if (path == .string) return NativeResult.share(path);
    return NativeResult.scalar(.{ .int = pos });
}

fn giNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const pos = objGetInt(obj, "__gi_pos");
    try obj.set(ctx.allocator, "__gi_pos", .{ .int = pos + 1 });
    const results = obj.get("__gi_results");
    if (results == .array and pos + 1 < results.array.length()) {
        const path = results.array.get(.{ .int = pos + 1 });
        if (path == .string) {
            try obj.set(ctx.allocator, "__pathname", path);
        }
    }
    return NativeResult.scalar(.null);
}

fn giCount(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const results = obj.get("__gi_results");
    if (results != .array) return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = results.array.length() });
}
