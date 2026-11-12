// php's ext/spl/spl_directory.c: SplFileInfo, DirectoryIterator,
// FilesystemIterator, RecursiveDirectoryIterator, GlobIterator,
// SplFileObject and SplTempFileObject.
//
// php keeps one spl_filesystem_object per instance; zphp keeps its fields in
// hidden properties (see `F` below). a directory is read when it is opened
// (its names and entry types snapshot in order, "." and ".." first), and the
// read pointer walks that list as php_stream_readdir would walk the
// directory. a file object wraps an ordinary stream resource, so every
// stream php can open works the same way here
const std = @import("std");
const builtin = @import("builtin");
const bundle = @import("../bundle.zig");
const sys = @import("../sys.zig");
const platform = @import("../platform.zig");
const object_properties = @import("../runtime/object_properties.zig");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const PhpArray = value_mod.PhpArray;
const PhpObject = value_mod.PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeResult = vm_mod.NativeResult;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const filesystem = @import("filesystem.zig");
const csv = @import("csv.zig");
const scanf = @import("scanf.zig");
const sic = @import("spl_iterator_classes.zig");

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

// spl_directory.h
const DROP_NEW_LINE: i64 = 0x1;
const READ_AHEAD: i64 = 0x2;
const SKIP_EMPTY: i64 = 0x4;
const READ_CSV: i64 = 0x8;
const FILE_OBJECT_MASK: i64 = 0xF;

const CURRENT_AS_FILEINFO: i64 = 0x0;
const CURRENT_AS_SELF: i64 = 0x10;
const CURRENT_AS_PATHNAME: i64 = 0x20;
const CURRENT_MODE_MASK: i64 = 0xF0;
const KEY_AS_PATHNAME: i64 = 0x0;
const KEY_AS_FILENAME: i64 = 0x100;
const KEY_MODE_MASK: i64 = 0xF00;
const NEW_CURRENT_AND_KEY: i64 = KEY_AS_FILENAME | CURRENT_AS_FILEINFO;
const SKIPDOTS: i64 = 0x1000;
const UNIXPATHS: i64 = 0x2000;
const FOLLOW_SYMLINKS: i64 = 0x4000;
const OTHERS_MASK: i64 = 0x7000;

const DIT_CTOR_FLAGS: i64 = 0x1;
const DIT_CTOR_GLOB: i64 = 0x2;

// readdir's d_type
const DT_UNKNOWN: i64 = 0;
const DT_DIR: i64 = 4;
const DT_REG: i64 = 8;
const DT_LNK: i64 = 10;

const Type = enum(i64) { info = 0, dir = 1, file = 2 };

// the hidden properties of an spl_filesystem_object
const F = struct {
    const type_ = "__fs_type";
    const path = "__fs_path";
    const file_name = "__fs_file_name";
    const orig_path = "__fs_orig_path";
    const flags = "__fs_flags";
    const file_class = "__fs_file_class";
    const info_class = "__fs_info_class";
    // a directory: its names and entry types, the read pointer, whether it
    // is open, the entry index and the current entry
    const names = "__fs_names";
    const dtypes = "__fs_dtypes";
    const rpos = "__fs_rpos";
    const dirp = "__fs_dirp";
    const index = "__fs_index";
    const d_name = "__fs_d_name";
    const d_type = "__fs_d_type";
    // a glob:// directory: the full paths it matched and the directory of
    // the entry last read
    const glob = "__fs_glob";
    const glob_paths = "__fs_glob_paths";
    const glob_path = "__fs_glob_path";
    const sub_path = "__fs_sub_path";
    // a file
    const stream = "__fs_stream";
    const open_mode = "__fs_open_mode";
    const current_line = "__fs_current_line";
    const current_zval = "__fs_current_zval";
    const line_num = "__fs_line_num";
    const max_line_len = "__fs_max_line_len";
    const delimiter = "__fs_delimiter";
    const enclosure = "__fs_enclosure";
    const escape = "__fs_escape";
    const escape_default = "__fs_escape_default";
};

// ==========================================
// registration
// ==========================================

const MethodSpec = struct { []const u8, vm_mod.NativeFn };

fn registerClass(vm: *VM, a: Allocator, def: ClassDef, comptime name: []const u8, comptime methods: []const MethodSpec) !void {
    var d = def;
    inline for (methods) |m| {
        try d.methods.put(a, m[0], .{ .name = m[0], .arity = 0 });
        try vm.native_fns.put(a, name ++ "::" ++ m[0], m[1]);
    }
    try vm.classes.put(a, name, d);
}

pub fn register(vm: *VM, a: Allocator) !void {
    var fi = ClassDef{ .name = "SplFileInfo" };
    try fi.interfaces.append(a, "Stringable");
    try registerClass(vm, a, fi, "SplFileInfo", &.{
        .{ "__construct", fiConstruct },     .{ "getPath", fiGetPath },
        .{ "getFilename", fiGetFilename },   .{ "getExtension", fiGetExtension },
        .{ "getBasename", fiGetBasename },   .{ "getPathname", fiGetPathname },
        .{ "getPerms", fiGetPerms },         .{ "getInode", fiGetInode },
        .{ "getSize", fiGetSize },           .{ "getOwner", fiGetOwner },
        .{ "getGroup", fiGetGroup },         .{ "getATime", fiGetATime },
        .{ "getMTime", fiGetMTime },         .{ "getCTime", fiGetCTime },
        .{ "getType", fiGetType },           .{ "isWritable", fiIsWritable },
        .{ "isReadable", fiIsReadable },     .{ "isExecutable", fiIsExecutable },
        .{ "isFile", fiIsFile },             .{ "isDir", fiIsDir },
        .{ "isLink", fiIsLink },             .{ "getLinkTarget", fiGetLinkTarget },
        .{ "getRealPath", fiGetRealPath },   .{ "getFileInfo", fiGetFileInfo },
        .{ "getPathInfo", fiGetPathInfo },   .{ "openFile", fiOpenFile },
        .{ "setFileClass", fiSetFileClass }, .{ "setInfoClass", fiSetInfoClass },
        .{ "__toString", fiGetPathname },    .{ "__debugInfo", fiDebugInfo },
        .{ "_bad_state_ex", fiBadStateEx },
    });
    if (vm.classes.getPtr("SplFileInfo")) |def| if (def.methods.getPtr("_bad_state_ex")) |m| {
        m.is_final = true;
    };

    var di = ClassDef{ .name = "DirectoryIterator", .parent = "SplFileInfo" };
    try di.interfaces.append(a, "SeekableIterator");
    try registerClass(vm, a, di, "DirectoryIterator", &.{
        .{ "__construct", diConstruct },     .{ "getFilename", diGetFilename },
        .{ "getExtension", diGetExtension }, .{ "getBasename", diGetBasename },
        .{ "isDot", diIsDot },               .{ "rewind", diRewind },
        .{ "valid", diValid },               .{ "key", diKey },
        .{ "current", diCurrent },           .{ "next", diNext },
        .{ "seek", diSeek },                 .{ "__toString", diGetFilename },
    });

    var fsi = ClassDef{ .name = "FilesystemIterator", .parent = "DirectoryIterator" };
    inline for (.{
        .{ "CURRENT_MODE_MASK", CURRENT_MODE_MASK },     .{ "CURRENT_AS_PATHNAME", CURRENT_AS_PATHNAME },
        .{ "CURRENT_AS_FILEINFO", CURRENT_AS_FILEINFO }, .{ "CURRENT_AS_SELF", CURRENT_AS_SELF },
        .{ "KEY_MODE_MASK", KEY_MODE_MASK },             .{ "KEY_AS_PATHNAME", KEY_AS_PATHNAME },
        .{ "FOLLOW_SYMLINKS", FOLLOW_SYMLINKS },         .{ "KEY_AS_FILENAME", KEY_AS_FILENAME },
        .{ "NEW_CURRENT_AND_KEY", NEW_CURRENT_AND_KEY }, .{ "OTHER_MODE_MASK", OTHERS_MASK },
        .{ "SKIP_DOTS", SKIPDOTS },                      .{ "UNIX_PATHS", UNIXPATHS },
    }) |c| {
        try fsi.constants.put(a, c[0], .{ .int = c[1] });
        try fsi.constant_order.append(a, c[0]);
    }
    try registerClass(vm, a, fsi, "FilesystemIterator", &.{
        .{ "__construct", fsiConstruct }, .{ "rewind", fsiRewind },
        .{ "key", fsiKey },               .{ "current", fsiCurrent },
        .{ "getFlags", fsiGetFlags },     .{ "setFlags", fsiSetFlags },
    });

    var rdi = ClassDef{ .name = "RecursiveDirectoryIterator", .parent = "FilesystemIterator" };
    try rdi.interfaces.append(a, "RecursiveIterator");
    try registerClass(vm, a, rdi, "RecursiveDirectoryIterator", &.{
        .{ "__construct", rdiConstruct },         .{ "hasChildren", rdiHasChildren },
        .{ "getChildren", rdiGetChildren },       .{ "getSubPath", rdiGetSubPath },
        .{ "getSubPathname", rdiGetSubPathname },
    });

    var gi = ClassDef{ .name = "GlobIterator", .parent = "FilesystemIterator", .uncloneable = true };
    try gi.interfaces.append(a, "Countable");
    try registerClass(vm, a, gi, "GlobIterator", &.{
        .{ "__construct", giConstruct }, .{ "count", giCount },
    });

    var sfo = ClassDef{ .name = "SplFileObject", .parent = "SplFileInfo", .uncloneable = true };
    try sfo.interfaces.append(a, "RecursiveIterator");
    try sfo.interfaces.append(a, "SeekableIterator");
    inline for (.{ .{ "DROP_NEW_LINE", DROP_NEW_LINE }, .{ "READ_AHEAD", READ_AHEAD }, .{ "SKIP_EMPTY", SKIP_EMPTY }, .{ "READ_CSV", READ_CSV } }) |c| {
        try sfo.constants.put(a, c[0], .{ .int = c[1] });
        try sfo.constant_order.append(a, c[0]);
    }
    try registerClass(vm, a, sfo, "SplFileObject", &.{
        .{ "__construct", sfoConstruct },       .{ "rewind", sfoRewind },
        .{ "eof", sfoEof },                     .{ "valid", sfoValid },
        .{ "fgets", sfoFgets },                 .{ "fread", sfoFread },
        .{ "fgetcsv", sfoFgetcsv },             .{ "fputcsv", sfoFputcsv },
        .{ "setCsvControl", sfoSetCsvControl }, .{ "getCsvControl", sfoGetCsvControl },
        .{ "flock", sfoFlock },                 .{ "fflush", sfoFflush },
        .{ "ftell", sfoFtell },                 .{ "fseek", sfoFseek },
        .{ "fgetc", sfoFgetc },                 .{ "fpassthru", sfoFpassthru },
        .{ "fscanf", sfoFscanf },               .{ "fwrite", sfoFwrite },
        .{ "fstat", sfoFstat },                 .{ "ftruncate", sfoFtruncate },
        .{ "current", sfoCurrent },             .{ "key", sfoKey },
        .{ "next", sfoNext },                   .{ "setFlags", sfoSetFlags },
        .{ "getFlags", sfoGetFlags },           .{ "setMaxLineLen", sfoSetMaxLineLen },
        .{ "getMaxLineLen", sfoGetMaxLineLen }, .{ "hasChildren", sfoHasChildren },
        .{ "getChildren", sfoGetChildren },     .{ "seek", sfoSeek },
        .{ "getCurrentLine", sfoFgets },        .{ "__toString", sfoToString },
    });

    const stfo = ClassDef{ .name = "SplTempFileObject", .parent = "SplFileObject", .uncloneable = true };
    try registerClass(vm, a, stfo, "SplTempFileObject", &.{.{ "__construct", stfoConstruct }});
}

// ==========================================
// state
// ==========================================

fn str(obj: *PhpObject, comptime key: []const u8) ?[]const u8 {
    const v = obj.get(key);
    return if (v == .string) v.string.bytes() else null;
}

fn int(obj: *PhpObject, comptime key: []const u8) i64 {
    const v = obj.get(key);
    return if (v == .int) v.int else 0;
}

fn flag(obj: *PhpObject, comptime key: []const u8) bool {
    const v = obj.get(key);
    return v == .bool and v.bool;
}

fn setStr(ctx: *NativeContext, obj: *PhpObject, comptime key: []const u8, bytes: ?[]const u8) RuntimeError!void {
    if (bytes) |b| try obj.setCopiedString(ctx.allocator, key, b) else try obj.set(ctx.allocator, key, .null);
}

fn setInt(ctx: *NativeContext, obj: *PhpObject, comptime key: []const u8, n: i64) RuntimeError!void {
    try obj.set(ctx.allocator, key, .{ .int = n });
}

fn setBool(ctx: *NativeContext, obj: *PhpObject, comptime key: []const u8, b: bool) RuntimeError!void {
    try obj.set(ctx.allocator, key, .{ .bool = b });
}

fn typeOf(obj: *PhpObject) Type {
    return @fromBackingInt(@intCast(int(obj, F.type_)));
}

fn flags(obj: *PhpObject) i64 {
    return int(obj, F.flags);
}

fn fileClass(obj: *PhpObject) []const u8 {
    return str(obj, F.file_class) orelse "SplFileObject";
}

fn infoClass(obj: *PhpObject) []const u8 {
    return str(obj, F.info_class) orelse "SplFileInfo";
}

fn dName(obj: *PhpObject) []const u8 {
    return str(obj, F.d_name) orelse "";
}

fn dirOpen(obj: *PhpObject) bool {
    return flag(obj, F.dirp);
}

fn streamOf(obj: *PhpObject) ?*PhpObject {
    const v = obj.get(F.stream);
    if (v != .resource) return null;
    if (value_mod.resourceClosed(v.resource)) return null;
    return v.resource;
}

fn this(ctx: *NativeContext) RuntimeError!*PhpObject {
    return sic.thisObj(ctx) orelse {
        try sic.raise(ctx, "Error", "Object not initialized", .{});
        return error.RuntimeError;
    };
}

// a php function run as part of the method, the way an internal function
// calls another's C implementation: it gets no frame of its own, so a
// trace made inside it shows the method. .undef when it throws
fn internalCall(ctx: *NativeContext, comptime func: []const u8, args: []const Value) RuntimeError!Value {
    if (sic.pending(ctx)) return .undef;
    const native = ctx.vm.native_fns.get(func) orelse ctx.vm.disabled_natives.get(func) orelse unreachable;
    // the function names itself in its warnings, as when php code calls it
    const saved_name = ctx.call_name;
    ctx.call_name = func;
    defer ctx.call_name = saved_name;
    const r = native.call(ctx, args) catch |err| {
        if (sic.pending(ctx)) return .undef;
        return err;
    };
    if (r.value == .string) {
        defer r.value.string.release();
        return .{ .string = Value.String.borrowed(try ctx.createString(r.value.string.bytes())) };
    }
    return r.value;
}

fn throwNow(ctx: *NativeContext, class: []const u8, comptime fmt: []const u8, args: anytype) RuntimeError!NativeResult {
    return sic.throwNow(ctx, class, fmt, args);
}

fn noArgs(ctx: *NativeContext, label: []const u8, args: []const Value) RuntimeError!void {
    if (!try sic.argCount(ctx, label, args.len, 0, 0)) return error.RuntimeError;
}

fn isSlash(c: u8) bool {
    return platform.isSep(c);
}

fn slashFor(obj: *PhpObject) u8 {
    return if (flags(obj) & UNIXPATHS != 0) '/' else platform.sep_str[0];
}

// "P": a path string without NUL bytes
fn argPath(ctx: *NativeContext, label: []const u8, args: []const Value, i: usize, pname: []const u8) RuntimeError!Value.String {
    const s = (try sic.argString(ctx, label, args, i, pname)) orelse return error.RuntimeError;
    if (std.mem.indexOfScalar(u8, s.bytes(), 0) != null) {
        s.release();
        try sic.raise(ctx, "ValueError", "{s}(): Argument #{d} (${s}) must not contain any null bytes", .{ label, i + 1, pname });
        return error.RuntimeError;
    }
    return s;
}

fn argLong(ctx: *NativeContext, label: []const u8, args: []const Value, i: usize, pname: []const u8, default: i64) RuntimeError!i64 {
    return (try sic.argLong(ctx, label, args, i, pname, default)) orelse error.RuntimeError;
}

// "b"
fn argBool(ctx: *NativeContext, label: []const u8, args: []const Value, i: usize, pname: []const u8, default: bool) RuntimeError!bool {
    if (i >= args.len) return default;
    const v = args[i];
    switch (v) {
        .bool => |b| return b,
        .int, .float, .string => return v.isTruthy(),
        .null => {
            const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): Passing null to parameter #{d} (${s}) of type bool is deprecated", .{ label, i + 1, pname });
            defer ctx.allocator.free(msg);
            try ctx.vm.raiseError(VM.E_DEPRECATED, msg);
            return false;
        },
        else => {},
    }
    try sic.typeError(ctx, label, i + 1, pname, "bool", v);
    return error.RuntimeError;
}

// "s" or "S", the string's bytes for the duration of the call
fn argStr(ctx: *NativeContext, label: []const u8, args: []const Value, i: usize, pname: []const u8) RuntimeError![]const u8 {
    const s = (try sic.argString(ctx, label, args, i, pname)) orelse return error.RuntimeError;
    defer s.release();
    return ctx.createString(s.bytes());
}

// "C": a class derived from base, autoloaded when unknown
fn argClass(ctx: *NativeContext, label: []const u8, args: []const Value, i: usize, pname: []const u8, base: []const u8, nullable: bool) RuntimeError!?[]const u8 {
    const v = args[i];
    if (nullable and v == .null) return null;
    if (v != .string) {
        try sic.typeError(ctx, label, i + 1, pname, if (nullable) "?string" else "string", v);
        return error.RuntimeError;
    }
    const name = v.string.bytes();
    ctx.vm.tryAutoload(name) catch |err| if (ctx.vm.pending_exception == null) return err;
    if (ctx.vm.pending_exception != null) return error.RuntimeError;
    if (ctx.vm.classes.getKey(name)) |declared| if (ctx.vm.isInstanceOf(declared, base)) return declared;
    try sic.raise(ctx, "TypeError", "{s}(): Argument #{d} (${s}) must be a class name derived from {s}{s}, {s} given", .{ label, i + 1, pname, base, if (nullable) " or null" else "", name });
    return error.RuntimeError;
}

// spl_filesystem_object_get_path
fn getPath(obj: *PhpObject) ?[]const u8 {
    if (typeOf(obj) == .dir and flag(obj, F.glob) and dirOpen(obj)) {
        const p = str(obj, F.glob_path) orelse return null;
        return if (p.len == 0) null else p;
    }
    return str(obj, F.path);
}

// spl_filesystem_object_get_file_name
fn ensureFileName(ctx: *NativeContext, obj: *PhpObject) RuntimeError!void {
    if (str(obj, F.file_name) != null) return;
    switch (typeOf(obj)) {
        .info, .file => {
            try sic.raise(ctx, "Error", "Object not initialized", .{});
            return error.RuntimeError;
        },
        .dir => {
            const name = dName(obj);
            const path = getPath(obj) orelse return setStr(ctx, obj, F.file_name, name);
            const joined = try std.fmt.allocPrint(ctx.allocator, "{s}{c}{s}", .{ path, slashFor(obj), name });
            defer ctx.allocator.free(joined);
            try setStr(ctx, obj, F.file_name, joined);
        },
    }
}

// spl_filesystem_object_get_pathname
fn getPathname(ctx: *NativeContext, obj: *PhpObject) RuntimeError!?[]const u8 {
    switch (typeOf(obj)) {
        .info, .file => return str(obj, F.file_name),
        .dir => {
            if (dName(obj).len == 0) return null;
            try ensureFileName(ctx, obj);
            return str(obj, F.file_name);
        },
    }
}

// the file name without its path: the part after "path/", or all of it
fn shortName(obj: *PhpObject, file_name: []const u8) []const u8 {
    const path = getPath(obj) orelse return file_name;
    if (path.len > 0 and path.len < file_name.len) return file_name[path.len + 1 ..];
    return file_name;
}

// spl_filesystem_info_set_filename
fn setFilename(ctx: *NativeContext, obj: *PhpObject, path: []const u8) RuntimeError!void {
    var len = path.len;
    if (len > 1 and isSlash(path[len - 1])) {
        while (len > 1 and isSlash(path[len - 1])) len -= 1;
    }
    try setStr(ctx, obj, F.file_name, path[0..len]);
    while (len > 1 and !isSlash(path[len - 1])) len -= 1;
    if (len > 0) len -= 1;
    try setStr(ctx, obj, F.path, path[0..len]);
}

// ==========================================
// directories
// ==========================================

fn isDot(name: []const u8) bool {
    return std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..");
}

// spl_filesystem_dir_read
fn dirRead(ctx: *NativeContext, obj: *PhpObject) RuntimeError!void {
    try obj.set(ctx.allocator, F.file_name, .null);
    const names_v = obj.get(F.names);
    const pos: usize = @intCast(@max(int(obj, F.rpos), 0));
    if (!dirOpen(obj) or names_v != .array or pos >= names_v.array.length()) {
        try setStr(ctx, obj, F.d_name, "");
        if (flag(obj, F.glob)) try obj.set(ctx.allocator, F.glob_path, .null);
        return;
    }
    const name = names_v.array.entries.items[pos].value;
    try obj.set(ctx.allocator, F.d_name, name);
    const types_v = obj.get(F.dtypes);
    const t: i64 = if (types_v == .array and pos < types_v.array.length()) Value.toInt(types_v.array.entries.items[pos].value) else DT_UNKNOWN;
    try setInt(ctx, obj, F.d_type, t);
    if (flag(obj, F.glob)) {
        const paths_v = obj.get(F.glob_paths);
        if (paths_v == .array and pos < paths_v.array.length()) {
            const full = paths_v.array.entries.items[pos].value;
            if (full == .string) try setStr(ctx, obj, F.glob_path, globDir(full.string.bytes()));
        }
    }
    try setInt(ctx, obj, F.rpos, @intCast(pos + 1));
}

fn dirReadSkipping(ctx: *NativeContext, obj: *PhpObject, skip_dots: bool) RuntimeError!void {
    while (true) {
        try dirRead(ctx, obj);
        if (!(skip_dots and isDot(dName(obj)))) return;
    }
}

// php_glob_stream_path_split: what precedes the last slash, or that slash
// alone at the root
fn globDir(path: []const u8) []const u8 {
    const pos = std.mem.lastIndexOfScalar(u8, path, '/') orelse return "";
    return if (pos == 0) path[0..1] else path[0..pos];
}

fn appendEntry(ctx: *NativeContext, names: *PhpArray, dtypes: *PhpArray, name: []const u8, t: i64) RuntimeError!void {
    try names.appendCopiedString(ctx.allocator, name);
    try dtypes.append(ctx.allocator, .{ .int = t });
}

fn kindType(kind: std.Io.File.Kind) i64 {
    return switch (kind) {
        .directory => DT_DIR,
        .file => DT_REG,
        .sym_link => DT_LNK,
        else => DT_UNKNOWN,
    };
}

// the entries php_stream_opendir would read: false when the directory
// cannot be opened, with the reason
const Listed = union(enum) { ok, failed: []const u8 };

fn listDirectory(ctx: *NativeContext, path: []const u8, names: *PhpArray, dtypes: *PhpArray) RuntimeError!Listed {
    var os_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = bundle.osPath(&os_buf, path);
    var listing = bundle.listDir(dir_path);
    var failure: []const u8 = "No such file or directory";
    var dir_opt: ?std.Io.Dir = std.Io.Dir.cwd().openDir(platform.io, dir_path, .{ .iterate = true }) catch |err| blk: {
        failure = filesystem.errorText(err);
        break :blk null;
    };
    defer if (dir_opt) |*d| d.close(platform.io);
    if (listing == null and dir_opt == null) return .{ .failed = failure };
    try appendEntry(ctx, names, dtypes, ".", DT_DIR);
    try appendEntry(ctx, names, dtypes, "..", DT_DIR);
    if (dir_opt) |*dir| {
        var iter = dir.iterate();
        while (iter.next(platform.io) catch null) |entry| try appendEntry(ctx, names, dtypes, entry.name, kindType(entry.kind));
    }
    if (listing) |*packed_names| while (packed_names.next()) |child| {
        if (dir_opt) |dir| if (filesystem.dirHas(dir, child.name)) continue;
        try appendEntry(ctx, names, dtypes, child.name, if (child.kind == .dir) DT_DIR else DT_REG);
    };
    return .ok;
}

// spl_filesystem_dir_open. label names the method for the open failure
fn dirOpenPath(ctx: *NativeContext, obj: *PhpObject, path: []const u8, label: []const u8) RuntimeError!void {
    const skip_dots = flags(obj) & SKIPDOTS != 0;
    try setInt(ctx, obj, F.type_, @backingInt(Type.dir));
    const names = try ctx.createArray();
    const dtypes = try ctx.createArray();
    var opened = false;
    if (std.mem.startsWith(u8, path, "glob://")) {
        try setBool(ctx, obj, F.glob, true);
        const pattern = path["glob://".len..];
        const matched = internalCall(ctx, "glob", &[_]Value{.{ .string = Value.String.borrowed(pattern) }}) catch |err| return err;
        const paths = try ctx.createArray();
        if (matched == .array) {
            for (matched.array.entries.items) |e| {
                if (e.value != .string) continue;
                const full = e.value.string.bytes();
                try paths.appendCopiedString(ctx.allocator, full);
                const base = if (std.mem.lastIndexOfScalar(u8, full, '/')) |p| full[p + 1 ..] else full;
                try appendEntry(ctx, names, dtypes, base, DT_UNKNOWN);
            }
        }
        try obj.set(ctx.allocator, F.glob_paths, .{ .array = paths });
        // the stream starts out with the directory of its first match, or
        // of the pattern when nothing matched
        const first: []const u8 = if (paths.length() > 0) paths.entries.items[0].value.string.bytes() else pattern;
        try setStr(ctx, obj, F.glob_path, globDir(first));
        opened = ctx.vm.pending_exception == null;
    } else {
        switch (try listDirectory(ctx, path, names, dtypes)) {
            .ok => opened = true,
            .failed => |reason| {
                try sic.raise(ctx, "UnexpectedValueException", "{s}({s}): Failed to open directory: {s}", .{ label, path, reason });
            },
        }
    }
    try obj.set(ctx.allocator, F.names, .{ .array = names });
    try obj.set(ctx.allocator, F.dtypes, .{ .array = dtypes });
    try setInt(ctx, obj, F.rpos, 0);
    try setBool(ctx, obj, F.dirp, opened);
    if (path.len > 1 and isSlash(path[path.len - 1])) {
        try setStr(ctx, obj, F.path, path[0 .. path.len - 1]);
    } else {
        try setStr(ctx, obj, F.path, path);
    }
    try setInt(ctx, obj, F.index, 0);
    if (ctx.vm.pending_exception != null or !opened) {
        try setStr(ctx, obj, F.d_name, "");
        return;
    }
    try dirReadSkipping(ctx, obj, skip_dots);
}

fn dirRewindStream(ctx: *NativeContext, obj: *PhpObject) RuntimeError!void {
    try setInt(ctx, obj, F.rpos, 0);
    if (flag(obj, F.glob)) try obj.set(ctx.allocator, F.glob_path, .null);
}

fn requireDir(ctx: *NativeContext, obj: *PhpObject) RuntimeError!void {
    if (dirOpen(obj)) return;
    try sic.raise(ctx, "Error", "Object not initialized", .{});
    return error.RuntimeError;
}

// spl_filesystem_object_construct
fn dirConstruct(ctx: *NativeContext, args: []const Value, label: []const u8, ctor_flags: i64) RuntimeError!NativeResult {
    const obj = try this(ctx);
    var f: i64 = ctor_flags & ~DIT_CTOR_FLAGS;
    const path_s = blk: {
        if (ctor_flags & DIT_CTOR_FLAGS != 0) {
            f |= KEY_AS_PATHNAME | CURRENT_AS_FILEINFO;
            if (!try sic.argCount(ctx, label, args.len, 1, 2)) return error.RuntimeError;
            const p = try argPath(ctx, label, args, 0, if (ctor_flags & DIT_CTOR_GLOB != 0) "pattern" else "directory");
            if (args.len > 1) {
                f = argLong(ctx, label, args, 1, "flags", 0) catch |err| {
                    p.release();
                    return err;
                };
            }
            break :blk p;
        }
        f |= KEY_AS_PATHNAME | CURRENT_AS_SELF;
        if (!try sic.argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
        break :blk try argPath(ctx, label, args, 0, "directory");
    };
    defer path_s.release();
    const path = path_s.bytes();
    if (path.len == 0) {
        return throwNow(ctx, "ValueError", "{s}(): Argument #1 (${s}) must not be empty", .{ label, if (ctor_flags & DIT_CTOR_GLOB != 0) "pattern" else "directory" });
    }
    if (str(obj, F.path) != null) return throwNow(ctx, "Error", "Directory object is already initialized", .{});
    try setInt(ctx, obj, F.flags, f);
    if (ctor_flags & DIT_CTOR_GLOB != 0 and !std.mem.startsWith(u8, path, "glob://")) {
        const g = try std.fmt.allocPrint(ctx.allocator, "glob://{s}", .{path});
        defer ctx.allocator.free(g);
        try dirOpenPath(ctx, obj, g, label);
    } else {
        try dirOpenPath(ctx, obj, path, label);
    }
    return sic.finishNull(ctx);
}

fn diConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return dirConstruct(ctx, args, "DirectoryIterator::__construct", 0);
}

fn fsiConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return dirConstruct(ctx, args, "FilesystemIterator::__construct", DIT_CTOR_FLAGS | SKIPDOTS);
}

fn rdiConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return dirConstruct(ctx, args, "RecursiveDirectoryIterator::__construct", DIT_CTOR_FLAGS);
}

fn giConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return dirConstruct(ctx, args, "GlobIterator::__construct", DIT_CTOR_FLAGS | DIT_CTOR_GLOB);
}

fn diRewind(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "DirectoryIterator::rewind", args);
    try requireDir(ctx, obj);
    try setInt(ctx, obj, F.index, 0);
    try dirRewindStream(ctx, obj);
    try dirRead(ctx, obj);
    return NativeResult.scalar(.null);
}

fn diKey(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "DirectoryIterator::key", args);
    try requireDir(ctx, obj);
    return NativeResult.scalar(.{ .int = int(obj, F.index) });
}

fn diCurrent(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "DirectoryIterator::current", args);
    try requireDir(ctx, obj);
    return NativeResult.borrowed(.{ .object = obj });
}

fn diNext(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "DirectoryIterator::next", args);
    try requireDir(ctx, obj);
    try setInt(ctx, obj, F.index, int(obj, F.index) + 1);
    try dirReadSkipping(ctx, obj, flags(obj) & SKIPDOTS != 0);
    try obj.set(ctx.allocator, F.file_name, .null);
    return NativeResult.scalar(.null);
}

fn diSeek(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    if (!try sic.argCount(ctx, "DirectoryIterator::seek", args.len, 1, 1)) return error.RuntimeError;
    const pos = try argLong(ctx, "DirectoryIterator::seek", args, 0, "offset", 0);
    try requireDir(ctx, obj);
    if (int(obj, F.index) > pos) {
        _ = try sic.callOn(ctx, obj, "rewind", &.{});
        if (sic.pending(ctx)) return error.RuntimeError;
    }
    while (int(obj, F.index) < pos) {
        const r = try sic.callOn(ctx, obj, "valid", &.{});
        if (sic.pending(ctx)) return error.RuntimeError;
        if (!r.isTruthy()) return throwNow(ctx, "OutOfBoundsException", "Seek position {d} is out of range", .{pos});
        _ = try sic.callOn(ctx, obj, "next", &.{});
        if (sic.pending(ctx)) return error.RuntimeError;
    }
    return NativeResult.scalar(.null);
}

fn diValid(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "DirectoryIterator::valid", args);
    try requireDir(ctx, obj);
    return NativeResult.scalar(.{ .bool = dName(obj).len != 0 });
}

fn diGetFilename(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "DirectoryIterator::getFilename", args);
    try requireDir(ctx, obj);
    return NativeResult.copyString(ctx.allocator, dName(obj));
}

fn extensionOf(name: []const u8) []const u8 {
    const base = filesystem.phpBasename(name, "");
    const dot = std.mem.lastIndexOfScalar(u8, base, '.') orelse return "";
    return base[dot + 1 ..];
}

fn diGetExtension(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "DirectoryIterator::getExtension", args);
    try requireDir(ctx, obj);
    return NativeResult.copyString(ctx.allocator, extensionOf(dName(obj)));
}

fn diGetBasename(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "DirectoryIterator::getBasename";
    if (!try sic.argCount(ctx, label, args.len, 0, 1)) return error.RuntimeError;
    const suffix = if (args.len > 0) try argStr(ctx, label, args, 0, "suffix") else "";
    try requireDir(ctx, obj);
    return NativeResult.copyString(ctx.allocator, filesystem.phpBasename(dName(obj), suffix));
}

fn diIsDot(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "DirectoryIterator::isDot", args);
    try requireDir(ctx, obj);
    return NativeResult.scalar(.{ .bool = isDot(dName(obj)) });
}

fn fsiRewind(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "FilesystemIterator::rewind", args);
    try setInt(ctx, obj, F.index, 0);
    if (dirOpen(obj)) try dirRewindStream(ctx, obj);
    try dirReadSkipping(ctx, obj, flags(obj) & SKIPDOTS != 0);
    return NativeResult.scalar(.null);
}

fn fsiKey(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "FilesystemIterator::key", args);
    if (flags(obj) & KEY_MODE_MASK == KEY_AS_FILENAME) return NativeResult.copyString(ctx.allocator, dName(obj));
    try ensureFileName(ctx, obj);
    return NativeResult.share(obj.get(F.file_name));
}

fn fsiCurrent(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "FilesystemIterator::current", args);
    const mode = flags(obj) & CURRENT_MODE_MASK;
    if (mode == CURRENT_AS_PATHNAME) {
        try ensureFileName(ctx, obj);
        return NativeResult.share(obj.get(F.file_name));
    }
    if (mode == CURRENT_AS_FILEINFO) {
        try ensureFileName(ctx, obj);
        const info = try createInfoFrom(ctx, obj, null);
        return sic.finish(ctx, NativeResult.borrowed(info));
    }
    return NativeResult.borrowed(.{ .object = obj });
}

fn fsiGetFlags(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "FilesystemIterator::getFlags", args);
    return NativeResult.scalar(.{ .int = flags(obj) & (KEY_MODE_MASK | CURRENT_MODE_MASK | OTHERS_MASK) });
}

fn fsiSetFlags(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "FilesystemIterator::setFlags";
    if (!try sic.argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const f = try argLong(ctx, label, args, 0, "flags", 0);
    const mask = KEY_MODE_MASK | CURRENT_MODE_MASK | OTHERS_MASK;
    try setInt(ctx, obj, F.flags, (flags(obj) & ~mask) | (f & mask));
    return NativeResult.scalar(.null);
}

fn rdiHasChildren(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "RecursiveDirectoryIterator::hasChildren";
    if (!try sic.argCount(ctx, label, args.len, 0, 1)) return error.RuntimeError;
    const allow_links = try argBool(ctx, label, args, 0, "allowLinks", false);
    const name = dName(obj);
    if (name.len == 0 or isDot(name)) return NativeResult.scalar(.{ .bool = false });
    const t = int(obj, F.d_type);
    if (t == DT_DIR) return NativeResult.scalar(.{ .bool = true });
    if (t == DT_REG) return NativeResult.scalar(.{ .bool = false });
    try ensureFileName(ctx, obj);
    const file_name = str(obj, F.file_name) orelse "";
    const lst = try statLink(ctx, file_name);
    const mode = lst orelse return NativeResult.scalar(.{ .bool = false });
    const S_IFMT: u32 = 0o170000;
    if (mode & S_IFMT != 0o120000) return NativeResult.scalar(.{ .bool = mode & S_IFMT == 0o040000 });
    if (!allow_links and flags(obj) & FOLLOW_SYMLINKS == 0) return NativeResult.scalar(.{ .bool = false });
    const r = try statCall(ctx, "is_dir", file_name);
    return NativeResult.scalar(.{ .bool = r.isTruthy() });
}

// php_stat(FS_LPERMS): the link's own mode, null when it cannot be read
fn statLink(ctx: *NativeContext, path: []const u8) RuntimeError!?u32 {
    const r = try statCall(ctx, "lstat", path);
    if (r != .array) return null;
    const m = r.array.get(.{ .string = Value.String.borrowed("mode") });
    return if (m == .int) @intCast(m.int) else null;
}

fn statCall(ctx: *NativeContext, comptime func: []const u8, path: []const u8) RuntimeError!Value {
    const saved = ctx.vm.error_silenced_depth;
    ctx.vm.error_silenced_depth += 1;
    defer ctx.vm.error_silenced_depth = saved;
    return internalCall(ctx, func, &[_]Value{.{ .string = Value.String.borrowed(path) }});
}

fn rdiGetChildren(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "RecursiveDirectoryIterator::getChildren", args);
    try ensureFileName(ctx, obj);
    const file_name = obj.get(F.file_name);
    const child_v = try sic.construct(ctx, obj.class_name, &.{ file_name, .{ .int = flags(obj) } });
    if (child_v != .object) return error.RuntimeError;
    const child = child_v.object;
    const name = dName(obj);
    if (str(obj, F.sub_path)) |sub| if (sub.len > 0) {
        const joined = try std.fmt.allocPrint(ctx.allocator, "{s}{c}{s}", .{ sub, slashFor(obj), name });
        defer ctx.allocator.free(joined);
        try setStr(ctx, child, F.sub_path, joined);
    } else try setStr(ctx, child, F.sub_path, name) else try setStr(ctx, child, F.sub_path, name);
    try child.set(ctx.allocator, F.info_class, obj.get(F.info_class));
    try child.set(ctx.allocator, F.file_class, obj.get(F.file_class));
    return NativeResult.borrowed(child_v);
}

fn rdiGetSubPath(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "RecursiveDirectoryIterator::getSubPath", args);
    return NativeResult.copyString(ctx.allocator, str(obj, F.sub_path) orelse "");
}

fn rdiGetSubPathname(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "RecursiveDirectoryIterator::getSubPathname", args);
    if (str(obj, F.sub_path)) |sub| {
        const joined = try std.fmt.allocPrint(ctx.allocator, "{s}{c}{s}", .{ sub, slashFor(obj), dName(obj) });
        defer ctx.allocator.free(joined);
        return NativeResult.copyString(ctx.allocator, joined);
    }
    return NativeResult.copyString(ctx.allocator, dName(obj));
}

fn giCount(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "GlobIterator::count", args);
    if (typeOf(obj) == .dir and flag(obj, F.glob) and dirOpen(obj)) {
        const names = obj.get(F.names);
        return NativeResult.scalar(.{ .int = if (names == .array) @intCast(names.array.length()) else 0 });
    }
    return throwNow(ctx, "Error", "GlobIterator is not initialized", .{});
}

// ==========================================
// SplFileInfo
// ==========================================

fn fiConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplFileInfo::__construct";
    if (!try sic.argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const path = try argPath(ctx, label, args, 0, "filename");
    defer path.release();
    try setFilename(ctx, obj, path.bytes());
    return NativeResult.scalar(.null);
}

fn fiGetPath(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFileInfo::getPath", args);
    return NativeResult.copyString(ctx.allocator, getPath(obj) orelse "");
}

fn requireFileName(ctx: *NativeContext, obj: *PhpObject) RuntimeError![]const u8 {
    return str(obj, F.file_name) orelse {
        try sic.raise(ctx, "Error", "Object not initialized", .{});
        return error.RuntimeError;
    };
}

fn fiGetFilename(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFileInfo::getFilename", args);
    const file_name = try requireFileName(ctx, obj);
    return NativeResult.copyString(ctx.allocator, shortName(obj, file_name));
}

fn fiGetExtension(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFileInfo::getExtension", args);
    const file_name = try requireFileName(ctx, obj);
    return NativeResult.copyString(ctx.allocator, extensionOf(shortName(obj, file_name)));
}

fn fiGetBasename(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplFileInfo::getBasename";
    if (!try sic.argCount(ctx, label, args.len, 0, 1)) return error.RuntimeError;
    const suffix = if (args.len > 0) try argStr(ctx, label, args, 0, "suffix") else "";
    const file_name = try requireFileName(ctx, obj);
    return NativeResult.copyString(ctx.allocator, filesystem.phpBasename(shortName(obj, file_name), suffix));
}

fn fiGetPathname(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFileInfo::getPathname", args);
    const p = (try getPathname(ctx, obj)) orelse return NativeResult.literal("");
    return NativeResult.copyString(ctx.allocator, p);
}

// FileInfoFunction: php_stat on the file name, its warnings thrown as
// RuntimeException under the method's name
fn statInfo(ctx: *NativeContext, args: []const Value, comptime method: []const u8, comptime func: []const u8) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplFileInfo::" ++ method;
    try noArgs(ctx, label, args);
    try ensureFileName(ctx, obj);
    const file_name = str(obj, F.file_name) orelse "";
    const saved = ctx.vm.eh_throw;
    ctx.vm.eh_throw = .{ .class = "RuntimeException", .from = func ++ "(", .to = label ++ "(" };
    defer ctx.vm.eh_throw = saved;
    const r = try internalCall(ctx, func, &[_]Value{.{ .string = Value.String.borrowed(file_name) }});
    if (sic.pending(ctx)) return error.RuntimeError;
    return NativeResult.share(r);
}

fn fiGetPerms(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return statInfo(ctx, args, "getPerms", "fileperms");
}
fn fiGetInode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return statInfo(ctx, args, "getInode", "fileinode");
}
fn fiGetSize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return statInfo(ctx, args, "getSize", "filesize");
}
fn fiGetOwner(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return statInfo(ctx, args, "getOwner", "fileowner");
}
fn fiGetGroup(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return statInfo(ctx, args, "getGroup", "filegroup");
}
fn fiGetATime(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return statInfo(ctx, args, "getATime", "fileatime");
}
fn fiGetMTime(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return statInfo(ctx, args, "getMTime", "filemtime");
}
fn fiGetCTime(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return statInfo(ctx, args, "getCTime", "filectime");
}
fn fiGetType(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return statInfo(ctx, args, "getType", "filetype");
}
fn fiIsWritable(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return statInfo(ctx, args, "isWritable", "is_writable");
}
fn fiIsReadable(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return statInfo(ctx, args, "isReadable", "is_readable");
}
fn fiIsExecutable(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return statInfo(ctx, args, "isExecutable", "is_executable");
}
fn fiIsFile(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return statInfo(ctx, args, "isFile", "is_file");
}
fn fiIsDir(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return statInfo(ctx, args, "isDir", "is_dir");
}
fn fiIsLink(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return statInfo(ctx, args, "isLink", "is_link");
}

extern "c" fn readlink(path: [*:0]const u8, buf: [*]u8, size: usize) isize;

fn fiGetLinkTarget(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFileInfo::getLinkTarget", args);
    if (str(obj, F.file_name) == null) try ensureFileName(ctx, obj);
    const file_name = str(obj, F.file_name) orelse return throwNow(ctx, "ValueError", "Filename must not be empty", .{});
    if (builtin.os.tag == .windows) return throwNow(ctx, "RuntimeException", "Unable to read link {s}, error: {s}", .{ file_name, "Function not implemented" });
    const path = if (std.fs.path.isAbsolute(file_name)) file_name else blk: {
        var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
        const cwd = platform.getCwd(&cwd_buf) catch {
            try ctx.vm.emitWarning("SplFileInfo::getLinkTarget(): No such file or directory");
            return NativeResult.scalar(.{ .bool = false });
        };
        const joined = try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ cwd, file_name });
        defer ctx.allocator.free(joined);
        break :blk try ctx.createString(joined);
    };
    const z = try ctx.allocator.dupeSentinel(u8, path, 0);
    defer ctx.allocator.free(z);
    var out: [std.fs.max_path_bytes]u8 = undefined;
    const n = readlink(z.ptr, &out, out.len - 1);
    if (n < 0) return throwNow(ctx, "RuntimeException", "Unable to read link {s}, error: {s}", .{ file_name, sys.errnoText() });
    return NativeResult.copyString(ctx.allocator, out[0..@intCast(n)]);
}

fn fiGetRealPath(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFileInfo::getRealPath", args);
    if (typeOf(obj) == .dir and str(obj, F.file_name) == null and dName(obj).len > 0) try ensureFileName(ctx, obj);
    const filename = str(obj, F.orig_path) orelse str(obj, F.file_name) orelse return NativeResult.scalar(.{ .bool = false });
    const r = try internalCall(ctx, "realpath", &[_]Value{.{ .string = Value.String.borrowed(filename) }});
    if (sic.pending(ctx)) return error.RuntimeError;
    return NativeResult.share(r);
}

// spl_filesystem_object_create_info
fn createInfo(ctx: *NativeContext, file_path: []const u8, class: []const u8) RuntimeError!Value {
    if (constructorIsOwn(ctx.vm, class, "SplFileInfo")) {
        const o = try ctx.createObject(class);
        try setFilename(ctx, o, file_path);
        return .{ .object = o };
    }
    const path_s = try Value.String.create(ctx.allocator, file_path);
    defer path_s.release();
    return sic.construct(ctx, class, &.{.{ .string = path_s }});
}

// the class's constructor is base's own (ce->constructor->common.scope)
fn constructorIsOwn(vm: *VM, class: []const u8, base: []const u8) bool {
    const full = vm.resolveMethod(class, "__construct") catch return false;
    const sep = std.mem.indexOf(u8, full, "::") orelse return false;
    return std.ascii.eqlIgnoreCase(full[0..sep], base);
}

// spl_filesystem_object_create_type(SPL_FS_INFO)
fn createInfoFrom(ctx: *NativeContext, source: *PhpObject, class: ?[]const u8) RuntimeError!Value {
    if (typeOf(source) == .dir and dName(source).len == 0) {
        try sic.raise(ctx, "RuntimeException", "Could not open file", .{});
        return .undef;
    }
    const ce = class orelse infoClass(source);
    try ensureFileName(ctx, source);
    const file_name = str(source, F.file_name) orelse "";
    if (!constructorIsOwn(ctx.vm, ce, "SplFileInfo")) {
        const s = try Value.String.create(ctx.allocator, file_name);
        defer s.release();
        return sic.construct(ctx, ce, &.{.{ .string = s }});
    }
    const o = try ctx.createObject(ce);
    try setStr(ctx, o, F.file_name, file_name);
    try setStr(ctx, o, F.path, getPath(source));
    return .{ .object = o };
}

fn fiGetFileInfo(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplFileInfo::getFileInfo";
    if (!try sic.argCount(ctx, label, args.len, 0, 1)) return error.RuntimeError;
    const ce = if (args.len > 0) try argClass(ctx, label, args, 0, "class", "SplFileInfo", true) else null;
    const r = try createInfoFrom(ctx, obj, ce);
    return sic.finish(ctx, NativeResult.borrowed(r));
}

fn fiGetPathInfo(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplFileInfo::getPathInfo";
    if (!try sic.argCount(ctx, label, args.len, 0, 1)) return error.RuntimeError;
    const ce = (if (args.len > 0) try argClass(ctx, label, args, 0, "class", "SplFileInfo", true) else null) orelse infoClass(obj);
    const path = (try getPathname(ctx, obj)) orelse return NativeResult.scalar(.null);
    if (path.len == 0) return NativeResult.scalar(.null);
    const dir = try ctx.createString(filesystem.phpDirname(path));
    const r = try createInfo(ctx, dir, ce);
    return sic.finish(ctx, NativeResult.borrowed(r));
}

fn fiOpenFile(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplFileInfo::openFile";
    if (typeOf(obj) == .dir and dName(obj).len == 0) return throwNow(ctx, "RuntimeException", "Could not open file", .{});
    if (!try sic.argCount(ctx, label, args.len, 0, 3)) return error.RuntimeError;
    const mode = if (args.len > 0) try argStr(ctx, label, args, 0, "mode") else "r";
    const use_include_path = try argBool(ctx, label, args, 1, "useIncludePath", false);
    const context: Value = if (args.len > 2) args[2] else .null;
    if (context != .null and context != .resource) {
        try sic.typeError(ctx, label, 3, "context", "resource or null", context);
        return error.RuntimeError;
    }
    const ce = fileClass(obj);
    try ensureFileName(ctx, obj);
    const file_name = str(obj, F.file_name) orelse "";
    const name_s = try Value.String.create(ctx.allocator, file_name);
    defer name_s.release();
    const mode_s = try Value.String.create(ctx.allocator, mode);
    defer mode_s.release();
    if (!constructorIsOwn(ctx.vm, ce, "SplFileObject")) {
        const r = try sic.construct(ctx, ce, &.{ .{ .string = name_s }, .{ .string = mode_s } });
        return sic.finish(ctx, NativeResult.borrowed(r));
    }
    const o = try ctx.createObject(ce);
    try setStr(ctx, o, F.file_name, file_name);
    try setStr(ctx, o, F.path, getPath(obj));
    try setStr(ctx, o, F.open_mode, mode);
    try fileOpen(ctx, o, use_include_path, context, label);
    if (sic.pending(ctx)) return error.RuntimeError;
    return NativeResult.borrowed(.{ .object = o });
}

fn fiSetFileClass(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplFileInfo::setFileClass";
    if (!try sic.argCount(ctx, label, args.len, 0, 1)) return error.RuntimeError;
    const ce = if (args.len > 0) (try argClass(ctx, label, args, 0, "class", "SplFileObject", false)).? else "SplFileObject";
    try setStr(ctx, obj, F.file_class, ce);
    return NativeResult.scalar(.null);
}

fn fiSetInfoClass(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplFileInfo::setInfoClass";
    if (!try sic.argCount(ctx, label, args.len, 0, 1)) return error.RuntimeError;
    const ce = if (args.len > 0) (try argClass(ctx, label, args, 0, "class", "SplFileInfo", false)).? else "SplFileInfo";
    try setStr(ctx, obj, F.info_class, ce);
    return NativeResult.scalar(.null);
}

// spl_filesystem_object_get_debug_info
fn debugTable(ctx: *NativeContext, obj: *PhpObject) RuntimeError!*PhpArray {
    const vm = ctx.vm;
    const t = try object_properties.ownTable(vm, obj);
    const path_name = (try getPathname(ctx, obj)) orelse "";
    try object_properties.setMangled(vm, t, "pathName", .private, "SplFileInfo", .{ .string = try strValue(ctx, path_name) });
    if (str(obj, F.file_name)) |file_name| {
        try object_properties.setMangled(vm, t, "fileName", .private, "SplFileInfo", .{ .string = try strValue(ctx, shortName(obj, file_name)) });
    }
    switch (typeOf(obj)) {
        .dir => {
            const glob: Value = if (flag(obj, F.glob) and dirOpen(obj)) .{ .string = try strValue(ctx, str(obj, F.path) orelse "") } else .{ .bool = false };
            try object_properties.setMangled(vm, t, "glob", .private, "DirectoryIterator", glob);
            try object_properties.setMangled(vm, t, "subPathName", .private, "RecursiveDirectoryIterator", .{ .string = try strValue(ctx, str(obj, F.sub_path) orelse "") });
        },
        .file => {
            try object_properties.setMangled(vm, t, "openMode", .private, "SplFileObject", .{ .string = try strValue(ctx, str(obj, F.open_mode) orelse "") });
            const d = [_]u8{@intCast(int(obj, F.delimiter))};
            const e = [_]u8{@intCast(int(obj, F.enclosure))};
            try object_properties.setMangled(vm, t, "delimiter", .private, "SplFileObject", .{ .string = try strValue(ctx, &d) });
            try object_properties.setMangled(vm, t, "enclosure", .private, "SplFileObject", .{ .string = try strValue(ctx, &e) });
        },
        .info => {},
    }
    return t;
}

// a string the context releases once the call is over
fn strValue(ctx: *NativeContext, bytes: []const u8) RuntimeError!Value.String {
    return Value.String.borrowed(try ctx.createString(bytes));
}

fn fiDebugInfo(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFileInfo::__debugInfo", args);
    const t = try debugTable(ctx, obj);
    return NativeResult.borrowed(.{ .array = t });
}

fn fiBadStateEx(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    try noArgs(ctx, "SplFileInfo::_bad_state_ex", args);
    return throwNow(ctx, "Error", "The parent constructor was not called: the object is in an invalid state", .{});
}

// ==========================================
// SplFileObject
// ==========================================

// spl_filesystem_file_open. the file name and open mode are already set
fn fileOpen(ctx: *NativeContext, obj: *PhpObject, use_include_path: bool, context: Value, label: []const u8) RuntimeError!void {
    try setInt(ctx, obj, F.type_, @backingInt(Type.file));
    const file_name = str(obj, F.file_name) orelse "";
    const mode = str(obj, F.open_mode) orelse "r";
    const is_dir = try statCall(ctx, "is_dir", file_name);
    if (is_dir == .bool and is_dir.bool) {
        try obj.set(ctx.allocator, F.open_mode, .null);
        try obj.set(ctx.allocator, F.file_name, .null);
        try sic.raise(ctx, "LogicException", "Cannot use SplFileObject with directories", .{});
        return;
    }
    const resolved = try ctx.createString(try filesystem.includePathLookup(ctx, file_name, use_include_path));
    const saved = ctx.vm.eh_throw;
    const to = try std.fmt.allocPrint(ctx.allocator, "{s}(", .{label});
    defer ctx.allocator.free(to);
    ctx.vm.eh_throw = .{ .class = "RuntimeException", .from = "fopen(", .to = to };
    const opened = blk: {
        defer ctx.vm.eh_throw = saved;
        var call_args = [_]Value{ .{ .string = Value.String.borrowed(resolved) }, .{ .string = Value.String.borrowed(mode) }, .{ .bool = false }, context };
        break :blk try internalCall(ctx, "fopen", @as([]const Value, if (context == .null) call_args[0..2] else &call_args));
    };
    if (file_name.len == 0 or opened != .resource) {
        if (!sic.pending(ctx)) try sic.raise(ctx, "RuntimeException", "Cannot open file '{s}'", .{file_name});
        try obj.set(ctx.allocator, F.open_mode, .null);
        try obj.set(ctx.allocator, F.file_name, .null);
        return;
    }
    try obj.set(ctx.allocator, F.stream, opened);
    opened.resource.set(ctx.allocator, "__no_fclose", .{ .bool = true }) catch {};
    if (file_name.len > 1 and isSlash(file_name[file_name.len - 1])) {
        try setStr(ctx, obj, F.file_name, file_name[0 .. file_name.len - 1]);
    }
    try setStr(ctx, obj, F.orig_path, resolved);
    try setInt(ctx, obj, F.delimiter, ',');
    try setInt(ctx, obj, F.enclosure, '"');
    try setInt(ctx, obj, F.escape, '\\');
    try setBool(ctx, obj, F.escape_default, true);
}

fn requireStream(ctx: *NativeContext, obj: *PhpObject) RuntimeError!*PhpObject {
    return streamOf(obj) orelse {
        try sic.raise(ctx, "Error", "Object not initialized", .{});
        return error.RuntimeError;
    };
}

fn freeLine(ctx: *NativeContext, obj: *PhpObject) RuntimeError!void {
    try obj.set(ctx.allocator, F.current_line, .null);
    try obj.set(ctx.allocator, F.current_zval, .null);
}

fn hasLine(obj: *PhpObject) bool {
    return obj.get(F.current_line) == .string;
}

fn hasZval(obj: *PhpObject) bool {
    return obj.get(F.current_zval) == .array;
}

fn streamEof(ctx: *NativeContext, stream: *PhpObject) RuntimeError!bool {
    const r = try internalCall(ctx, "feof", &[_]Value{.{ .resource = stream }});
    return r == .bool and r.bool;
}

fn cannotRead(ctx: *NativeContext, obj: *PhpObject) RuntimeError!void {
    try sic.raise(ctx, "RuntimeException", "Cannot read from file {s}", .{str(obj, F.file_name) orelse ""});
}

// spl_filesystem_file_read_ex: false on failure
fn readEx(ctx: *NativeContext, obj: *PhpObject, silent: bool, line_add: i64, is_csv: bool) RuntimeError!bool {
    try freeLine(ctx, obj);
    const stream = try requireStream(ctx, obj);
    if (try streamEof(ctx, stream)) {
        if (!silent) try cannotRead(ctx, obj);
        return false;
    }
    const max = int(obj, F.max_line_len);
    const line = (try filesystem.streamReadLine(ctx, stream, if (max > 0) @intCast(max) else std.math.maxInt(usize))) orelse try ctx.allocator.alloc(u8, 0);
    defer ctx.allocator.free(line);
    var len = line.len;
    if (!is_csv and flags(obj) & DROP_NEW_LINE != 0) {
        if (len > 0 and line[len - 1] == '\n') {
            len -= 1;
            if (len > 0 and line[len - 1] == '\r') len -= 1;
        }
    }
    try setStr(ctx, obj, F.current_line, line[0..len]);
    try setInt(ctx, obj, F.line_num, int(obj, F.line_num) + line_add);
    return true;
}

fn read(ctx: *NativeContext, obj: *PhpObject, silent: bool, is_csv: bool) RuntimeError!bool {
    return readEx(ctx, obj, silent, if (hasLine(obj)) 1 else 0, is_csv);
}

fn isLineEmpty(obj: *PhpObject) bool {
    const line = str(obj, F.current_line) orelse "";
    if (line.len == 0) return true;
    const f = flags(obj);
    return f & READ_CSV != 0 and f & DROP_NEW_LINE != 0 and (std.mem.eql(u8, line, "\n") or std.mem.eql(u8, line, "\r\n"));
}

// spl_filesystem_file_read_csv: the record, or null on failure
fn readCsv(ctx: *NativeContext, obj: *PhpObject, delimiter: u8, enclosure: u8, escape: i32, silent: bool) RuntimeError!?*PhpArray {
    while (true) {
        if (!try read(ctx, obj, silent, true)) return null;
        if (!(isLineEmpty(obj) and flags(obj) & SKIP_EMPTY != 0)) break;
    }
    const stream = try requireStream(ctx, obj);
    const line = try ctx.createString(str(obj, F.current_line) orelse "");
    const values = try csv.parseOrEmpty(ctx, .{ .ctx = ctx, .stream = stream }, delimiter, enclosure, escape, line);
    try obj.set(ctx.allocator, F.current_zval, .{ .array = values });
    return values;
}

fn csvEscape(obj: *PhpObject) i32 {
    return @intCast(int(obj, F.escape));
}

// spl_filesystem_file_read_line_ex
fn readLineEx(ctx: *NativeContext, obj: *PhpObject, silent: bool) RuntimeError!bool {
    if (flags(obj) & READ_CSV != 0) {
        return (try readCsv(ctx, obj, @intCast(int(obj, F.delimiter)), @intCast(int(obj, F.enclosure)), csvEscape(obj), silent)) != null;
    }
    if (sic.userMethod(ctx.vm, obj.class_name, "getCurrentLine")) {
        try freeLine(ctx, obj);
        const stream = try requireStream(ctx, obj);
        if (try streamEof(ctx, stream)) {
            if (!silent) try cannotRead(ctx, obj);
            return false;
        }
        const r = try sic.callOn(ctx, obj, "getCurrentLine", &.{});
        if (r == .undef or sic.pending(ctx)) return false;
        if (r != .string) {
            try sic.raise(ctx, "TypeError", "{s}::getCurrentLine(): Return value must be of type string, {s} returned", .{ obj.class_name, r.valueName() });
            return false;
        }
        if (hasLine(obj) or hasZval(obj)) try setInt(ctx, obj, F.line_num, int(obj, F.line_num) + 1);
        try freeLine(ctx, obj);
        try obj.set(ctx.allocator, F.current_line, r);
        return true;
    }
    return read(ctx, obj, silent, false);
}

fn readLine(ctx: *NativeContext, obj: *PhpObject, silent: bool) RuntimeError!bool {
    var ok = try readLineEx(ctx, obj, silent);
    while (flags(obj) & SKIP_EMPTY != 0 and ok and isLineEmpty(obj)) {
        try freeLine(ctx, obj);
        ok = try readLineEx(ctx, obj, silent);
    }
    return ok;
}

// spl_filesystem_file_rewind
fn fileRewind(ctx: *NativeContext, obj: *PhpObject) RuntimeError!void {
    const stream = try requireStream(ctx, obj);
    const r = try internalCall(ctx, "rewind", &[_]Value{.{ .resource = stream }});
    if (sic.pending(ctx)) return error.RuntimeError;
    if (r == .bool and !r.bool) {
        try sic.raise(ctx, "RuntimeException", "Cannot rewind file {s}", .{str(obj, F.file_name) orelse ""});
        return error.RuntimeError;
    }
    try freeLine(ctx, obj);
    try setInt(ctx, obj, F.line_num, 0);
    if (flags(obj) & READ_AHEAD != 0) _ = try readLine(ctx, obj, true);
}

fn sfoConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplFileObject::__construct";
    if (!try sic.argCount(ctx, label, args.len, 1, 4)) return error.RuntimeError;
    const name = try argPath(ctx, label, args, 0, "filename");
    defer name.release();
    const mode = if (args.len > 1) try argStr(ctx, label, args, 1, "mode") else "r";
    const use_include_path = try argBool(ctx, label, args, 2, "useIncludePath", false);
    const context: Value = if (args.len > 3) args[3] else .null;
    if (context != .null and context != .resource) {
        try sic.typeError(ctx, label, 4, "context", "resource or null", context);
        return error.RuntimeError;
    }
    if (streamOf(obj) != null) return throwNow(ctx, "Error", "Cannot call constructor twice", .{});
    try setStr(ctx, obj, F.open_mode, mode);
    try setStr(ctx, obj, F.file_name, name.bytes());
    try fileOpen(ctx, obj, use_include_path, context, label);
    if (sic.pending(ctx)) return error.RuntimeError;
    const orig = str(obj, F.orig_path) orelse "";
    var len = orig.len;
    if (len > 1 and isSlash(orig[len - 1])) len -= 1;
    while (len > 1 and !isSlash(orig[len - 1])) len -= 1;
    if (len > 0) len -= 1;
    try setStr(ctx, obj, F.path, orig[0..len]);
    return NativeResult.scalar(.null);
}

fn stfoConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplTempFileObject::__construct";
    if (!try sic.argCount(ctx, label, args.len, 0, 1)) return error.RuntimeError;
    const max_memory = try argLong(ctx, label, args, 0, "maxMemory", 2 * 1024 * 1024);
    if (streamOf(obj) != null) return throwNow(ctx, "Error", "Cannot call constructor twice", .{});
    const file_name = if (max_memory < 0)
        "php://memory"
    else if (args.len > 0)
        try std.fmt.allocPrint(ctx.allocator, "php://temp/maxmemory:{d}", .{max_memory})
    else
        "php://temp";
    defer if (max_memory >= 0 and args.len > 0) ctx.allocator.free(file_name);
    try setStr(ctx, obj, F.file_name, file_name);
    try setStr(ctx, obj, F.open_mode, "wb");
    try fileOpen(ctx, obj, false, .null, label);
    if (sic.pending(ctx)) return error.RuntimeError;
    try setStr(ctx, obj, F.path, "");
    return NativeResult.scalar(.null);
}

fn sfoRewind(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFileObject::rewind", args);
    try fileRewind(ctx, obj);
    return sic.finishNull(ctx);
}

fn sfoEof(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFileObject::eof", args);
    const stream = try requireStream(ctx, obj);
    return NativeResult.scalar(.{ .bool = try streamEof(ctx, stream) });
}

fn sfoValid(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFileObject::valid", args);
    if (flags(obj) & READ_AHEAD != 0) return NativeResult.scalar(.{ .bool = hasLine(obj) or hasZval(obj) });
    const stream = streamOf(obj) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = !try streamEof(ctx, stream) });
}

fn sfoFgets(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFileObject::fgets", args);
    _ = try requireStream(ctx, obj);
    if (!try readEx(ctx, obj, false, 1, false)) return error.RuntimeError;
    return NativeResult.share(obj.get(F.current_line));
}

fn sfoCurrent(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFileObject::current", args);
    _ = try requireStream(ctx, obj);
    if (!hasLine(obj) and !hasZval(obj)) _ = try readLine(ctx, obj, true);
    if (sic.pending(ctx)) return error.RuntimeError;
    if (hasLine(obj) and (flags(obj) & READ_CSV == 0 or !hasZval(obj))) return NativeResult.share(obj.get(F.current_line));
    if (hasZval(obj)) return NativeResult.borrowed(obj.get(F.current_zval));
    return NativeResult.scalar(.{ .bool = false });
}

fn sfoKey(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFileObject::key", args);
    return NativeResult.scalar(.{ .int = int(obj, F.line_num) });
}

fn sfoNext(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFileObject::next", args);
    _ = try requireStream(ctx, obj);
    try freeLine(ctx, obj);
    if (flags(obj) & READ_AHEAD != 0) _ = try readLine(ctx, obj, true);
    try setInt(ctx, obj, F.line_num, int(obj, F.line_num) + 1);
    return sic.finishNull(ctx);
}

fn sfoSetFlags(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplFileObject::setFlags";
    if (!try sic.argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    try setInt(ctx, obj, F.flags, try argLong(ctx, label, args, 0, "flags", 0));
    return NativeResult.scalar(.null);
}

fn sfoGetFlags(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFileObject::getFlags", args);
    return NativeResult.scalar(.{ .int = flags(obj) & FILE_OBJECT_MASK });
}

fn sfoSetMaxLineLen(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplFileObject::setMaxLineLen";
    if (!try sic.argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const n = try argLong(ctx, label, args, 0, "maxLength", 0);
    if (n < 0) return throwNow(ctx, "ValueError", "{s}(): Argument #1 ($maxLength) must be greater than or equal to 0", .{label});
    try setInt(ctx, obj, F.max_line_len, n);
    return NativeResult.scalar(.null);
}

fn sfoGetMaxLineLen(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFileObject::getMaxLineLen", args);
    return NativeResult.scalar(.{ .int = int(obj, F.max_line_len) });
}

fn sfoHasChildren(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = try this(ctx);
    try noArgs(ctx, "SplFileObject::hasChildren", args);
    return NativeResult.scalar(.{ .bool = false });
}

fn sfoGetChildren(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = try this(ctx);
    try noArgs(ctx, "SplFileObject::getChildren", args);
    return NativeResult.scalar(.null);
}

// a csv separator or enclosure argument: one character
fn csvChar(ctx: *NativeContext, label: []const u8, args: []const Value, i: usize, pname: []const u8, n: usize) RuntimeError!?u8 {
    if (i >= args.len) return null;
    const s = try argStr(ctx, label, args, i, pname);
    if (s.len != 1) {
        try sic.raise(ctx, "ValueError", "{s}(): Argument #{d} (${s}) must be a single character", .{ label, n, pname });
        return error.RuntimeError;
    }
    return s[0];
}

// php_csv_handle_escape_argument
fn csvEscapeArg(ctx: *NativeContext, label: []const u8, s: []const u8, n: usize) RuntimeError!i32 {
    if (s.len > 1) {
        try sic.raise(ctx, "ValueError", "{s}(): Argument #{d} ($escape) must be empty or a single character", .{ label, n });
        return error.RuntimeError;
    }
    if (s.len == 0) return csv.no_escape;
    return s[0];
}

// spl_csv_enclosure_param_handling
fn csvEscapeParam(ctx: *NativeContext, obj: *PhpObject, label: []const u8, args: []const Value, i: usize) RuntimeError!i32 {
    if (i >= args.len) {
        if (flag(obj, F.escape_default)) {
            const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): the $escape parameter must be provided, as its default value will change, either explicitly or via SplFileObject::setCsvControl()", .{label});
            defer ctx.allocator.free(msg);
            try ctx.vm.raiseError(VM.E_DEPRECATED, msg);
            if (sic.pending(ctx)) return error.RuntimeError;
        }
        return csvEscape(obj);
    }
    return csvEscapeArg(ctx, label, try argStr(ctx, label, args, i, "escape"), i + 1);
}

fn sfoFgetcsv(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplFileObject::fgetcsv";
    if (!try sic.argCount(ctx, label, args.len, 0, 3)) return error.RuntimeError;
    const d_arg = if (args.len > 0) try argStr(ctx, label, args, 0, "separator") else null;
    const e_arg = if (args.len > 1) try argStr(ctx, label, args, 1, "enclosure") else null;
    const x_arg = if (args.len > 2) try argStr(ctx, label, args, 2, "escape") else null;
    _ = try requireStream(ctx, obj);
    var delimiter: u8 = @intCast(int(obj, F.delimiter));
    var enclosure: u8 = @intCast(int(obj, F.enclosure));
    if (d_arg) |d| {
        if (d.len != 1) return throwNow(ctx, "ValueError", "{s}(): Argument #1 ($separator) must be a single character", .{label});
        delimiter = d[0];
    }
    if (e_arg) |e| {
        if (e.len != 1) return throwNow(ctx, "ValueError", "{s}(): Argument #2 ($enclosure) must be a single character", .{label});
        enclosure = e[0];
    }
    const escape = if (x_arg) |x| try csvEscapeArg(ctx, label, x, 3) else try csvEscapeParam(ctx, obj, label, args, 2);
    const values = (try readCsv(ctx, obj, delimiter, enclosure, escape, true)) orelse return sic.finish(ctx, NativeResult.scalar(.{ .bool = false }));
    return NativeResult.borrowed(.{ .array = values });
}

fn sfoFputcsv(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplFileObject::fputcsv";
    if (!try sic.argCount(ctx, label, args.len, 1, 5)) return error.RuntimeError;
    if (args[0] != .array) {
        try sic.typeError(ctx, label, 1, "fields", "array", args[0]);
        return error.RuntimeError;
    }
    const d_arg = if (args.len > 1) try argStr(ctx, label, args, 1, "separator") else null;
    const e_arg = if (args.len > 2) try argStr(ctx, label, args, 2, "enclosure") else null;
    const x_arg = if (args.len > 3) try argStr(ctx, label, args, 3, "escape") else null;
    const eol = if (args.len > 4) try argStr(ctx, label, args, 4, "eol") else null;
    const stream = try requireStream(ctx, obj);
    var delimiter: u8 = @intCast(int(obj, F.delimiter));
    var enclosure: u8 = @intCast(int(obj, F.enclosure));
    if (d_arg) |d| {
        if (d.len != 1) return throwNow(ctx, "ValueError", "{s}(): Argument #2 ($separator) must be a single character", .{label});
        delimiter = d[0];
    }
    if (e_arg) |e| {
        if (e.len != 1) return throwNow(ctx, "ValueError", "{s}(): Argument #3 ($enclosure) must be a single character", .{label});
        enclosure = e[0];
    }
    const escape = if (x_arg) |x| try csvEscapeArg(ctx, label, x, 4) else try csvEscapeParam(ctx, obj, label, args, 3);
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(ctx.allocator);
    try csv.format(ctx, &out, args[0].array, delimiter, enclosure, escape, eol);
    if (sic.pending(ctx)) return error.RuntimeError;
    const written = (try filesystem.streamWrite(ctx, stream, out.items)) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(written) });
}

fn sfoSetCsvControl(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplFileObject::setCsvControl";
    if (!try sic.argCount(ctx, label, args.len, 0, 3)) return error.RuntimeError;
    const delimiter = (try csvChar(ctx, label, args, 0, "separator", 1)) orelse ',';
    const enclosure = (try csvChar(ctx, label, args, 1, "enclosure", 2)) orelse '"';
    const escape = if (args.len > 2) try csvEscapeArg(ctx, label, try argStr(ctx, label, args, 2, "escape"), 3) else blk: {
        const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): the $escape parameter must be provided as its default value will change", .{label});
        defer ctx.allocator.free(msg);
        try ctx.vm.raiseError(VM.E_DEPRECATED, msg);
        if (sic.pending(ctx)) return error.RuntimeError;
        break :blk '\\';
    };
    if (args.len > 2) try setBool(ctx, obj, F.escape_default, false);
    try setInt(ctx, obj, F.delimiter, delimiter);
    try setInt(ctx, obj, F.enclosure, enclosure);
    try setInt(ctx, obj, F.escape, escape);
    return NativeResult.scalar(.null);
}

fn sfoGetCsvControl(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFileObject::getCsvControl", args);
    const arr = try ctx.createArray();
    const d = [_]u8{@intCast(int(obj, F.delimiter))};
    const e = [_]u8{@intCast(int(obj, F.enclosure))};
    try arr.appendCopiedString(ctx.allocator, &d);
    try arr.appendCopiedString(ctx.allocator, &e);
    const x = csvEscape(obj);
    if (x == csv.no_escape) {
        try arr.appendCopiedString(ctx.allocator, "");
    } else {
        const xs = [_]u8{@intCast(x)};
        try arr.appendCopiedString(ctx.allocator, &xs);
    }
    return NativeResult.borrowed(.{ .array = arr });
}

// a stream function called with the object's stream in front of args
fn streamCall(ctx: *NativeContext, obj: *PhpObject, comptime func: []const u8, args: []const Value) RuntimeError!Value {
    const stream = try requireStream(ctx, obj);
    var buf: [4]Value = undefined;
    buf[0] = .{ .resource = stream };
    for (args, 0..) |v, i| buf[i + 1] = v;
    const r = try internalCall(ctx, func, @as([]const Value, buf[0 .. args.len + 1]));
    if (sic.pending(ctx)) return error.RuntimeError;
    return r;
}

fn sfoFlock(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplFileObject::flock";
    if (!try sic.argCount(ctx, label, args.len, 1, 2)) return error.RuntimeError;
    const op = try argLong(ctx, label, args, 0, "operation", 0);
    _ = try requireStream(ctx, obj);
    const act = op & 3;
    if (act < 1 or act > 3) return throwNow(ctx, "ValueError", "{s}(): Argument #1 ($operation) must be one of LOCK_SH, LOCK_EX, or LOCK_UN", .{label});
    const r = try streamCall(ctx, obj, "flock", &.{.{ .int = op }});
    if (args.len > 1) ctx.setCallerVar(1, args.len, .{ .int = if (r == .bool and !r.bool and op & 4 != 0) 1 else 0 });
    return NativeResult.share(r);
}

fn sfoFflush(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFileObject::fflush", args);
    return NativeResult.share(try streamCall(ctx, obj, "fflush", &.{}));
}

fn sfoFtell(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFileObject::ftell", args);
    return NativeResult.share(try streamCall(ctx, obj, "ftell", &.{}));
}

fn sfoFseek(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplFileObject::fseek";
    if (!try sic.argCount(ctx, label, args.len, 1, 2)) return error.RuntimeError;
    const pos = try argLong(ctx, label, args, 0, "offset", 0);
    const whence = try argLong(ctx, label, args, 1, "whence", 0);
    _ = try requireStream(ctx, obj);
    try freeLine(ctx, obj);
    return NativeResult.share(try streamCall(ctx, obj, "fseek", &.{ .{ .int = pos }, .{ .int = whence } }));
}

fn sfoFgetc(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFileObject::fgetc", args);
    _ = try requireStream(ctx, obj);
    try freeLine(ctx, obj);
    const r = try streamCall(ctx, obj, "fgetc", &.{});
    if (r == .string and std.mem.eql(u8, r.string.bytes(), "\n")) try setInt(ctx, obj, F.line_num, int(obj, F.line_num) + 1);
    return NativeResult.share(r);
}

fn sfoFpassthru(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFileObject::fpassthru", args);
    return NativeResult.share(try streamCall(ctx, obj, "fpassthru", &.{}));
}

fn sfoFscanf(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplFileObject::fscanf";
    if (args.len < 1) {
        try sic.raise(ctx, "ArgumentCountError", "{s}() expects at least 1 argument, 0 given", .{label});
        return error.RuntimeError;
    }
    const format = try argStr(ctx, label, args, 0, "format");
    _ = try requireStream(ctx, obj);
    if (!try read(ctx, obj, false, false)) return error.RuntimeError;
    const line = try ctx.createString(str(obj, F.current_line) orelse "");
    return scanf.scan(ctx, line, format, args, 1);
}

fn sfoFwrite(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplFileObject::fwrite";
    if (!try sic.argCount(ctx, label, args.len, 1, 2)) return error.RuntimeError;
    var data = try argStr(ctx, label, args, 0, "data");
    if (args.len > 1 and args[1] != .null) {
        const length = try argLong(ctx, label, args, 1, "length", 0);
        data = if (length >= 0) data[0..@min(@as(usize, @intCast(length)), data.len)] else data[0..0];
    }
    const stream = try requireStream(ctx, obj);
    if (data.len == 0) return NativeResult.scalar(.{ .int = 0 });
    const written = (try filesystem.streamWrite(ctx, stream, data)) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(written) });
}

fn sfoFread(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplFileObject::fread";
    if (!try sic.argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const length = try argLong(ctx, label, args, 0, "length", 0);
    _ = try requireStream(ctx, obj);
    if (length <= 0) return throwNow(ctx, "ValueError", "{s}(): Argument #1 ($length) must be greater than 0", .{label});
    return NativeResult.share(try streamCall(ctx, obj, "fread", &.{.{ .int = length }}));
}

fn sfoFstat(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFileObject::fstat", args);
    return NativeResult.share(try streamCall(ctx, obj, "fstat", &.{}));
}

fn sfoFtruncate(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplFileObject::ftruncate";
    if (!try sic.argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const size = try argLong(ctx, label, args, 0, "size", 0);
    const stream = try requireStream(ctx, obj);
    if (size < 0) return throwNow(ctx, "ValueError", "{s}(): Argument #1 ($size) must be greater than or equal to 0", .{label});
    if (!truncatable(stream)) return throwNow(ctx, "LogicException", "Can't truncate file {s}", .{str(obj, F.file_name) orelse ""});
    return NativeResult.share(try streamCall(ctx, obj, "ftruncate", &.{.{ .int = size }}));
}

// php_stream_truncate_supported: plain files and memory streams
fn truncatable(stream: *PhpObject) bool {
    if (@import("streams.zig").memoryOf(stream) != null) return true;
    const fd = stream.get("__fd");
    if (fd != .int) return false;
    if (fd.int <= 2 and stream.get("__path") != .string) return false;
    const p = stream.get("__path");
    if (p == .string and std.mem.startsWith(u8, p.string.bytes(), "php://") and !std.mem.startsWith(u8, p.string.bytes(), "php://temp") and !std.mem.startsWith(u8, p.string.bytes(), "php://memory")) return false;
    return true;
}

fn sfoSeek(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    const label = "SplFileObject::seek";
    if (!try sic.argCount(ctx, label, args.len, 1, 1)) return error.RuntimeError;
    const line_pos = try argLong(ctx, label, args, 0, "line", 0);
    _ = try requireStream(ctx, obj);
    if (line_pos < 0) return throwNow(ctx, "ValueError", "{s}(): Argument #1 ($line) must be greater than or equal to 0", .{label});
    try fileRewind(ctx, obj);
    var i: i64 = 0;
    while (i < line_pos) : (i += 1) {
        if (!try readLine(ctx, obj, true)) return sic.finishNull(ctx);
    }
    if (line_pos > 0 and flags(obj) & READ_AHEAD == 0) {
        try setInt(ctx, obj, F.line_num, int(obj, F.line_num) + 1);
        try freeLine(ctx, obj);
    }
    return sic.finishNull(ctx);
}

fn sfoToString(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try this(ctx);
    try noArgs(ctx, "SplFileObject::__toString", args);
    _ = try requireStream(ctx, obj);
    if (!hasLine(obj)) {
        if (!try readLine(ctx, obj, false)) return error.RuntimeError;
    }
    return NativeResult.share(obj.get(F.current_line));
}
