const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const std = @import("std");
const sys = @import("../sys.zig");
const paths = @import("../paths.zig");
const platform = @import("../platform.zig");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const value_mod = @import("../runtime/value.zig");
const network = @import("network.zig");
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const phar = @import("phar.zig");
const phar_path = @import("phar_path.zig");
const includes = @import("../runtime/includes.zig");
const bundle = @import("../bundle.zig");
const zlib = @import("c_zlib");
const csv = @import("csv.zig");
const html = @import("html.zig");
const types = @import("types.zig");

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = common_entries ++ (if (platform.is_windows) @import("filesystem_win.zig").entries else posix_entries);

// natives that are posix calls here and something else on windows
const posix_entries = .{
    .{ "chown", native_chown },
    .{ "chgrp", native_chgrp },
    .{ "lchown", native_lchown },
    .{ "lchgrp", native_lchgrp },
    .{ "umask", native_umask },
    .{ "fileowner", native_fileowner },
    .{ "filegroup", native_filegroup },
    .{ "is_link", native_is_link },
    .{ "symlink", native_symlink },
    .{ "link", native_link },
    .{ "stat", native_stat },
    .{ "lstat", native_lstat },
    .{ "flock", native_flock },
    .{ "popen", native_popen },
    .{ "pclose", native_pclose },
    .{ "proc_open", native_proc_open },
    .{ "proc_close", native_proc_close },
    .{ "proc_get_status", native_proc_get_status },
    .{ "proc_terminate", native_proc_terminate },
    .{ "stream_set_blocking", native_stream_set_blocking },
};

const common_entries = .{
    .{ "gzcompress", native_gzcompress },
    .{ "gzuncompress", native_gzuncompress },
    .{ "gzdeflate", native_gzdeflate },
    .{ "gzinflate", native_gzinflate },
    .{ "gzencode", native_gzencode },
    .{ "gzdecode", native_gzdecode },
    .{ "file_get_contents", native_file_get_contents },
    .{ "file_put_contents", native_file_put_contents },
    .{ "file_exists", native_file_exists },
    .{ "is_file", native_is_file },
    .{ "is_dir", native_is_dir },
    .{ "basename", native_basename },
    .{ "dirname", native_dirname },
    .{ "pathinfo", native_pathinfo },
    .{ "realpath", native_realpath },
    .{ "mkdir", native_mkdir },
    .{ "rmdir", native_rmdir },
    .{ "unlink", native_unlink },
    .{ "copy", native_copy },
    .{ "rename", native_rename },
    .{ "glob", native_glob },
    .{ "fnmatch", native_fnmatch },
    .{ "scandir", native_scandir },
    .{ "opendir", native_opendir },
    .{ "dir", native_dir },
    .{ "readdir", native_readdir },
    .{ "closedir", native_closedir },
    .{ "rewinddir", native_rewinddir },
    .{ "file", native_file },
    .{ "readfile", native_readfile },
    .{ "is_readable", native_is_readable },
    .{ "is_executable", native_is_executable },
    .{ "is_writable", native_is_writable },
    .{ "is_writeable", native_is_writable },
    .{ "filesize", native_filesize },
    .{ "filemtime", native_filemtime },
    .{ "fileatime", native_fileatime },
    .{ "filectime", native_filectime },
    .{ "filetype", native_filetype },
    .{ "fileinode", native_fileinode },
    .{ "fopen", native_fopen },
    .{ "gzopen", native_gzopen },
    .{ "gzwrite", native_fwrite },
    .{ "gzputs", native_fwrite },
    .{ "gzread", native_fread },
    .{ "gzgets", native_fgets },
    .{ "gzgetc", native_fgetc },
    .{ "gzeof", native_feof },
    .{ "gzclose", native_fclose },
    .{ "gzrewind", native_rewind },
    .{ "gzseek", native_fseek },
    .{ "gztell", native_ftell },
    .{ "gzpassthru", native_fpassthru },
    .{ "gzfile", native_gzfile },
    .{ "fclose", native_fclose },
    .{ "fread", native_fread },
    .{ "fwrite", native_fwrite },
    .{ "fputs", native_fwrite },
    .{ "fpassthru", native_fpassthru },
    .{ "fgets", native_fgets },
    .{ "stream_get_line", native_stream_get_line },
    .{ "fgetc", native_fgetc },
    .{ "feof", native_feof },
    .{ "fseek", native_fseek },
    .{ "ftell", native_ftell },
    .{ "rewind", native_rewind },
    .{ "fflush", native_fflush },
    .{ "ftruncate", native_ftruncate },
    .{ "fgetcsv", csv.fgetcsv },
    .{ "fputcsv", csv.fputcsv },
    .{ "stream_get_meta_data", stream_get_meta_data },
    .{ "stream_get_wrappers", stream_get_wrappers },
    .{ "stream_wrapper_register", stream_wrapper_register },
    .{ "stream_wrapper_unregister", stream_wrapper_unregister },
    .{ "stream_wrapper_restore", stream_wrapper_restore },
    .{ "fstat", native_fstat },
    .{ "stream_get_contents", stream_get_contents },
    .{ "stream_copy_to_stream", stream_copy_to_stream },
    .{ "stream_filter_register", native_stream_filter_register },
    .{ "stream_filter_append", native_stream_filter_append },
    .{ "stream_filter_prepend", native_stream_filter_append },
    .{ "stream_filter_remove", native_noop_true },
    .{ "stream_get_filters", native_stream_get_filters },
    .{ "stream_get_transports", native_stream_get_transports },
    .{ "touch", native_touch },
    .{ "chmod", native_chmod },
    .{ "chdir", native_chdir },
    .{ "stream_resolve_include_path", native_stream_resolve_include_path },
    .{ "stream_is_local", native_stream_is_local },
    .{ "stream_isatty", native_stream_isatty },
    .{ "stream_supports_lock", native_stream_supports_lock },
    .{ "stream_set_chunk_size", native_stream_set_chunk_size },
    .{ "stream_set_read_buffer", native_stream_set_buffer },
    .{ "stream_set_write_buffer", native_stream_set_buffer },
    .{ "clearstatcache", native_clearstatcache },
    .{ "tmpfile", native_tmpfile },
    .{ "fileperms", native_fileperms },
    .{ "readlink", native_readlink },
    .{ "socket_set_blocking", native_stream_set_blocking },
    .{ "stream_set_timeout", native_stream_set_timeout },
    .{ "socket_set_timeout", native_stream_set_timeout },
    .{ "stream_set_read_buffer", native_stream_set_read_buffer },
    .{ "stream_set_write_buffer", native_stream_set_write_buffer },
    .{ "mime_content_type", native_mime_content_type },
    .{ "disk_free_space", native_disk_free_space },
    .{ "diskfreespace", native_disk_free_space },
    .{ "disk_total_space", native_disk_total_space },
    .{ "linkinfo", native_linkinfo },
    .{ "finfo_open", native_finfo_open },
    .{ "finfo_file", native_finfo_file },
    .{ "finfo_buffer", native_finfo_buffer },
    .{ "finfo_close", native_finfo_close },
};

// file handle management - store handles in PhpObjects with class "FileHandle"

fn cleanupPoolableHandle(obj: *PhpObject) bool {
    cleanupHandle(obj);
    if (obj.get("__proc_ref") == .resource) return false;
    const fd = obj.get("__fd");
    return fd != .int or fd.int > 2;
}

fn cleanupClosedProcess(obj: *PhpObject) bool {
    const running = obj.get("__running");
    return running == .bool and !running.bool;
}

pub fn register(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "FileHandle", .native_cleanup = cleanupPoolableHandle };
    try def.methods.put(a, "__toString", .{ .name = "__toString", .arity = 0 });
    try vm.classes.put(a, "FileHandle", def);
    try vm.classes.put(a, "ProcessResource", ClassDef{ .name = "ProcessResource", .native_cleanup = cleanupClosedProcess });

    // finfo as an OO wrapper around finfo_* functions
    var finfo_def = ClassDef{ .name = "finfo" };
    try finfo_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 2 });
    try finfo_def.methods.put(a, "file", .{ .name = "file", .arity = 3 });
    try finfo_def.methods.put(a, "buffer", .{ .name = "buffer", .arity = 3 });
    try finfo_def.methods.put(a, "set_flags", .{ .name = "set_flags", .arity = 1 });
    try vm.classes.put(a, "finfo", finfo_def);
    try vm.native_fns.put(a, "finfo::__construct", finfoConstruct);
    try vm.native_fns.put(a, "finfo::file", finfoFile);
    try vm.native_fns.put(a, "finfo::buffer", finfoBuffer);
    try vm.native_fns.put(a, "finfo::set_flags", finfoNoop);

    // Directory class returned by dir() - thin OO wrapper. methods delegate
    // to the underlying DirectoryHandle stored in the 'handle' property. php
    // 8.5 made it final and only dir() creates one
    var dir_def = ClassDef{ .name = "Directory", .is_final = true, .uncloneable = true };
    try dir_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 0 });
    // readonly and uninitialized until dir() fills them in
    try dir_def.properties.append(a, .{ .name = "path", .default = .null, .is_readonly = true, .type_str = "string" });
    try dir_def.properties.append(a, .{ .name = "handle", .default = .null, .is_readonly = true, .type_str = "mixed" });
    try dir_def.methods.put(a, "read", .{ .name = "read", .arity = 0 });
    try dir_def.methods.put(a, "rewind", .{ .name = "rewind", .arity = 0 });
    try dir_def.methods.put(a, "close", .{ .name = "close", .arity = 0 });
    try vm.classes.put(a, "Directory", dir_def);
    try vm.native_fns.put(a, "Directory::__construct", directoryConstruct);
    try vm.native_fns.put(a, "Directory::read", directoryRead);
    try vm.native_fns.put(a, "Directory::rewind", directoryRewind);
    try vm.native_fns.put(a, "Directory::close", directoryClose);

    inline for (.{ .{ "STDIN", 0, "r" }, .{ "STDOUT", 1, "w" }, .{ "STDERR", 2, "w" } }) |spec| {
        const obj = try vm.newResource("FileHandle");
        try obj.set(a, "__fd", .{ .int = spec[1] });
        try obj.set(a, "__open", .{ .bool = true });
        try obj.set(a, "__mode", .{ .string = Value.String.borrowed(spec[2]) });
        try vm.php_constants.put(a, spec[0], .{ .resource = obj });
    }
}

fn isNetStream(obj: *PhpObject) bool {
    const net = obj.get("__net");
    return net == .bool and net.bool;
}

// a socket is a handle of its own on windows, not a crt descriptor
fn getFileHandle(obj: *PhpObject) ?std.Io.File {
    const v = obj.get("__fd");
    if (v != .int or v.int < 0) return null;
    if (platform.is_windows and isNetStream(obj)) return platform.fileFromHandle(platform.socketFromInt(v.int) orelse return null);
    return platform.fileFromFd(v.int);
}

// how a stream's bytes move. sockets go through recv and send: on windows a
// socket read with ReadFile ignores the socket's non-blocking mode, so a
// non-blocking read with nothing pending would never return
const StreamIo = struct {
    file: std.Io.File,
    socket: bool,

    fn read(self: StreamIo, dest: []u8) anyerror!usize {
        if (self.socket) return sys.recv(self.sock(), dest, 0);
        return platform.read(self.file, dest);
    }

    fn write(self: StreamIo, data: []const u8) anyerror!usize {
        if (self.socket) return sys.send(self.sock(), data, 0);
        return platform.write(self.file, data);
    }

    fn sock(self: StreamIo) std.posix.socket_t {
        return if (platform.is_windows) @ptrCast(self.file.handle) else self.file.handle;
    }
};

fn streamIo(obj: *PhpObject) ?StreamIo {
    return .{ .file = getFileHandle(obj) orelse return null, .socket = isNetStream(obj) };
}

fn getBufferBacking(obj: *PhpObject) ?[]const u8 {
    const v = obj.get("__buffer");
    if (v != .string) return null;
    return v.string.bytes();
}

fn getBufferPos(obj: *PhpObject) usize {
    const v = obj.get("__pos");
    if (v != .int or v.int < 0) return 0;
    return @intCast(v.int);
}

fn setBufferPos(obj: *PhpObject, pos: usize) void {
    // mutate the existing entry to avoid allocator mismatch (the properties
    // map was allocated by the VM allocator; we don't have access here)
    if (obj.properties.getPtr("__pos")) |slot| {
        slot.* = .{ .int = @intCast(pos) };
    }
}

fn hexNibble(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

fn percentDecode(a: Allocator, s: []const u8) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8).empty;
    errdefer buf.deinit(a);
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '%' and i + 2 < s.len) {
            const hi = hexNibble(s[i + 1]);
            const lo = hexNibble(s[i + 2]);
            if (hi != null and lo != null) {
                try buf.append(a, (hi.? << 4) | lo.?);
                i += 3;
                continue;
            }
        }
        try buf.append(a, s[i]);
        i += 1;
    }
    return try buf.toOwnedSlice(a);
}

// php_base64_decode_ex in strict mode: whitespace is skipped, any other
// character outside the alphabet or misplaced padding fails
fn base64DecodeStrict(a: Allocator, s: []const u8) !?[]u8 {
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(a);
    var acc: u32 = 0;
    var count: usize = 0;
    var padding: usize = 0;
    for (s) |c| {
        if (c == '=') {
            padding += 1;
            continue;
        }
        const v: u32 = switch (c) {
            'A'...'Z' => c - 'A',
            'a'...'z' => c - 'a' + 26,
            '0'...'9' => c - '0' + 52,
            '+' => 62,
            '/' => 63,
            ' ', '\t', '\r', '\n' => continue,
            else => {
                out.deinit(a);
                return null;
            },
        };
        if (padding > 0) {
            out.deinit(a);
            return null;
        }
        acc = (acc << 6) | v;
        count += 1;
        if (count % 4 == 0) {
            try out.appendSlice(a, &.{ @truncate(acc >> 16), @truncate(acc >> 8), @truncate(acc) });
            acc = 0;
        }
    }
    const rest = count % 4;
    if (rest == 1 or (padding > 0 and (padding > 2 or (count + padding) % 4 != 0))) {
        out.deinit(a);
        return null;
    }
    if (rest == 2) try out.append(a, @truncate(acc >> 4));
    if (rest == 3) try out.appendSlice(a, &.{ @truncate(acc >> 10), @truncate(acc >> 2) });
    return try out.toOwnedSlice(a);
}

fn resolvePharPathWithCtx(path: []const u8, ctx: ?*NativeContext) ?phar_path.Resolved {
    const aliases: ?*const phar_path.AliasMap = if (ctx) |c| &c.vm.phar_aliases else null;
    return phar_path.resolve(path, aliases);
}

// loads and parses a phar from disk. caller owns returned bytes and must
// also call phar.deinit on the returned Phar with the same allocator
const PharLoaded = struct {
    bytes: []u8,
    parsed: phar.Phar,
};

fn loadPhar(a: Allocator, archive_path: []const u8) !PharLoaded {
    const bytes = try bundle.readFileAlloc(a, archive_path, 256 * 1024 * 1024);
    errdefer a.free(bytes);
    const parsed = try phar.parse(a, bytes);
    return .{ .bytes = bytes, .parsed = parsed };
}

fn freePhar(a: Allocator, loaded: *PharLoaded) void {
    loaded.parsed.deinit(a);
    a.free(loaded.bytes);
}

// returns the raw decoded contents of the file at internal_path, or null if missing
fn normalizePharInternalPath(a: Allocator, internal_path: []const u8) ![]u8 {
    return phar_path.normalizeInternal(a, internal_path);
}

fn readPharEntry(a: Allocator, archive_path: []const u8, internal_path: []const u8) !?[]u8 {
    var loaded = loadPhar(a, archive_path) catch return null;
    defer freePhar(a, &loaded);
    const normalized = try normalizePharInternalPath(a, internal_path);
    defer a.free(normalized);
    const entry = loaded.parsed.lookup(normalized) orelse return null;
    return try phar.extract(a, &loaded.parsed, entry);
}

const DataUriError = error{ NoComma, IllegalMediaType, IllegalParameter, IllegalUrl, UnableToDecode, OutOfMemory };

// the reason php's rfc2397 wrapper gives for refusing a data: url
fn dataUriErrorText(err: DataUriError) []const u8 {
    return switch (err) {
        error.NoComma => "rfc2397: no comma in URL",
        error.IllegalMediaType => "rfc2397: illegal media type",
        error.IllegalParameter => "rfc2397: illegal parameter",
        error.IllegalUrl => "rfc2397: illegal URL",
        error.UnableToDecode => "rfc2397: unable to decode",
        error.OutOfMemory => "Out of memory",
    };
}

// the decoded payload of "data:[//][mediatype][;param=value]*[;base64],<data>",
// validated as php's rfc2397 wrapper does
fn parseDataUri(a: Allocator, path: []const u8) DataUriError![]u8 {
    var rest = path["data:".len..];
    if (std.mem.startsWith(u8, rest, "//")) rest = rest[2..];
    const comma = std.mem.indexOfScalar(u8, rest, ',') orelse return error.NoComma;
    var meta = rest[0..comma];
    const data = rest[comma + 1 ..];
    var is_base64 = false;
    if (meta.len > 0) {
        const semi = std.mem.indexOfScalar(u8, meta, ';');
        const sep = std.mem.indexOfScalar(u8, meta, '/');
        if (semi == null and sep == null) return error.IllegalMediaType;
        if (semi == null) {
            meta = "";
        } else if (sep != null and sep.? < semi.?) {
            meta = meta[semi.?..];
        } else if (semi.? != 0 or !std.mem.eql(u8, meta, ";base64")) {
            return error.IllegalMediaType;
        }
        // parameters, and possibly ";base64" last
        while (meta.len > 0 and meta[0] == ';') {
            meta = meta[1..];
            const eq = std.mem.indexOfScalar(u8, meta, '=');
            const next = std.mem.indexOfScalar(u8, meta, ';');
            if (eq == null or (next != null and next.? < eq.?)) {
                if (!std.mem.eql(u8, meta, "base64")) return error.IllegalParameter;
                is_base64 = true;
                meta = "";
                break;
            }
            meta = if (next) |n| meta[n..] else "";
        }
        if (meta.len > 0) return error.IllegalUrl;
    }
    if (is_base64) return (try base64DecodeStrict(a, data)) orelse error.UnableToDecode;
    return percentDecode(a, data);
}

pub fn cleanupHandle(obj: *PhpObject) void {
    if (obj.pooled or !std.mem.eql(u8, obj.class_name, "FileHandle")) return;
    if (obj.get("__proc_ref") == .resource) return;
    const fd = obj.get("__fd");
    if (fd == .int and fd.int <= 2) return;
    const open = obj.get("__open");
    if (open == .bool and open.bool) {
        if (getFileHandle(obj)) |file| {
            if (!platform.isStdio(file)) platform.closeFd(fd.int);
        }
        if (obj.properties.getPtr("__open")) |slot| slot.* = .{ .bool = false };
    }
}

pub fn cleanupHandles(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    for (objects.items) |obj| cleanupHandle(obj);
}

// php opens streams through a context, making the default one the first time
// a call has none, and numbers every stream it opens, even one the call
// closes again before returning. these keep resource ids in step with php
fn useContext(ctx: *NativeContext, args: []const Value, index: usize) RuntimeError!void {
    _ = try network.streamContext(ctx, if (index < args.len) args[index] else null);
}

fn transientStreams(ctx: *NativeContext, count: usize) void {
    for (0..count) |_| ctx.vm.skipResourceId();
}

pub const StreamArg = struct {
    func: []const u8,
    index: usize = 0,
    param: []const u8 = "stream",
    // readdir and friends want a directory stream in particular
    directory: bool = false,
};

// the open stream a native takes at spec.index. php throws a TypeError for
// a value that is not a resource and for one that is closed or is not a stream
pub fn streamArg(ctx: *NativeContext, args: []const Value, comptime spec: StreamArg) RuntimeError!*PhpObject {
    const v: Value = if (spec.index < args.len) args[spec.index] else .null;
    const prefix = spec.func ++ "(): Argument #" ++ std.fmt.comptimePrint("{d}", .{spec.index + 1}) ++ " ($" ++ spec.param ++ ") must be ";
    if (v != .resource) return throwStreamArg(ctx, prefix ++ "of type resource, {s} given", .{v.valueName()});
    const r = v.resource;
    const is_stream = std.mem.eql(u8, r.class_name, "FileHandle") or std.mem.eql(u8, r.class_name, "DirectoryHandle");
    if (!is_stream or value_mod.resourceClosed(r)) return throwStreamArg(ctx, prefix ++ "an open stream resource", .{});
    if (spec.directory and !std.mem.eql(u8, r.class_name, "DirectoryHandle")) return throwStreamArg(ctx, prefix ++ "a valid Directory resource", .{});
    return r;
}

// the live process a proc_* native takes; a closed one is php's TypeError
pub fn processArg(ctx: *NativeContext, args: []const Value, comptime func: []const u8) RuntimeError!*PhpObject {
    const v: Value = if (args.len > 0) args[0] else .null;
    if (v != .resource) return throwStreamArg(ctx, func ++ "(): Argument #1 ($process) must be of type resource, {s} given", .{v.typeName()});
    const r = v.resource;
    if (!std.mem.eql(u8, r.class_name, "ProcessResource") or value_mod.resourceClosed(r)) return throwStreamArg(ctx, func ++ "(): supplied resource is not a valid process resource", .{});
    return r;
}

fn throwStreamArg(ctx: *NativeContext, comptime fmt: []const u8, args: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("TypeError", msg);
    return error.RuntimeError;
}

fn warn(ctx: *NativeContext, comptime fmt: []const u8, args: anytype) RuntimeError!void {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    try ctx.vm.emitWarning(msg);
}

fn notice(ctx: *NativeContext, comptime fmt: []const u8, args: anytype) RuntimeError!void {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    try ctx.vm.raiseError(8, msg);
}

fn throwValueError(ctx: *NativeContext, comptime fmt: []const u8, args: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("ValueError", msg);
    return error.RuntimeError;
}

// a string parameter as php's weak-mode parsing takes it: scalars and
// stringable objects convert, null is deprecated, anything else is a
// TypeError. a path (Z_PARAM_PATH) must also be free of nul bytes
fn strArg(ctx: *NativeContext, args: []const Value, comptime func: []const u8, comptime index: usize, comptime param: []const u8, comptime path: bool) RuntimeError![]const u8 {
    const bytes = try (html.Params{ .ctx = ctx, .func = func, .args = args }).string(index, param, "");
    if (path and std.mem.indexOfScalar(u8, bytes, 0) != null) {
        return throwValueError(ctx, func ++ "(): Argument #" ++ std.fmt.comptimePrint("{d}", .{index + 1}) ++ " ($" ++ param ++ ") must not contain any null bytes", .{});
    }
    return bytes;
}

// an int parameter as php's weak-mode parsing takes it
fn intArg(ctx: *NativeContext, args: []const Value, comptime func: []const u8, comptime index: usize, comptime param: []const u8, default: i64) RuntimeError!i64 {
    return (html.Params{ .ctx = ctx, .func = func, .args = args }).int(index, param, default);
}

// php's notice when a read or write on a plain descriptor fails: the
// running function, the byte count it asked for, and errno with its text
fn ioFailure(ctx: *NativeContext, comptime what: []const u8, count: usize, err: anyerror) RuntimeError!void {
    const code: i64, const text: []const u8 = switch (err) {
        error.NotOpenForReading, error.NotOpenForWriting => .{ 9, "Bad file descriptor" },
        error.IsDir => .{ 21, "Is a directory" },
        error.BrokenPipe => .{ 32, "Broken pipe" },
        error.NoSpaceLeft => .{ 28, "No space left on device" },
        error.DiskQuota => .{ 122, "Disk quota exceeded" },
        error.FileTooBig => .{ 27, "File too large" },
        else => .{ 5, "Input/output error" },
    };
    try notice(ctx, "{s}(): " ++ what ++ " of {d} bytes failed with errno={d} {s}", .{ ctx.call_name orelse "fread", count, code, text });
}

// php fills a stream's read buffer a chunk at a time, and that chunk is the
// count its read failure notice names
const read_chunk: usize = 8192;

// the text php prints for a failed filesystem call, strerror(errno) as glibc
// words it, from the error std reports for that errno
pub fn errorText(err: anyerror) []const u8 {
    return switch (err) {
        error.FileNotFound => "No such file or directory",
        error.PathAlreadyExists => "File exists",
        error.AccessDenied => "Permission denied",
        error.PermissionDenied => "Operation not permitted",
        error.IsDir => "Is a directory",
        error.NotDir => "Not a directory",
        error.DirNotEmpty => "Directory not empty",
        error.NameTooLong => "File name too long",
        error.SymLinkLoop => "Too many levels of symbolic links",
        error.NoSpaceLeft => "No space left on device",
        error.DiskQuota => "Disk quota exceeded",
        error.ReadOnlyFileSystem => "Read-only file system",
        error.FileBusy, error.DeviceBusy => "Device or resource busy",
        error.CrossDevice => "Invalid cross-device link",
        error.LinkQuotaExceeded => "Too many links",
        error.NotLink, error.InvalidArgument, error.BadPathName => "Invalid argument",
        error.NoDevice => "No such device",
        error.SystemResources => "Cannot allocate memory",
        error.ProcessFdQuotaExceeded => "Too many open files",
        error.FileTooBig => "File too large",
        else => "Unknown error",
    };
}

// file read/write

const c_curl = @import("c_curl");

var curl_global_init_done: bool = false;

const CurlWriteData = struct {
    allocator: Allocator,
    buffer: std.ArrayListUnmanaged(u8),
};

const CurlHeaderData = struct {
    ctx: *NativeContext,
    headers: *PhpArray,
    in_1xx: bool = false,
    oom: bool = false,
};

fn parseHttpStatus(line: []const u8) ?u16 {
    var it = std.mem.tokenizeScalar(u8, line, ' ');
    _ = it.next() orelse return null;
    const code_str = it.next() orelse return null;
    return std.fmt.parseInt(u16, code_str, 10) catch null;
}

fn curlWriteCallback(data: [*]u8, size: usize, nmemb: usize, userdata: *anyopaque) callconv(.c) usize {
    const total = size * nmemb;
    const wd: *CurlWriteData = @ptrCast(@alignCast(userdata));
    wd.buffer.appendSlice(wd.allocator, data[0..total]) catch return 0;
    return total;
}

fn curlHeaderCallback(data: [*]u8, size: usize, nmemb: usize, userdata: *anyopaque) callconv(.c) usize {
    const total = std.math.mul(usize, size, nmemb) catch return 0;
    const hd: *CurlHeaderData = @ptrCast(@alignCast(userdata));
    const raw = std.mem.trimEnd(u8, data[0..total], "\r\n");
    const status = std.mem.startsWith(u8, raw, "HTTP/");
    if (status) {
        const code = parseHttpStatus(raw) orelse return total;
        hd.in_1xx = code >= 100 and code < 200 and code != 101;
    }
    if (hd.in_1xx) return total;
    const line = if (status) raw else std.mem.trimEnd(u8, raw, " \t");
    if (line.len == 0) return total;
    const owned = Value.String.create(hd.ctx.allocator, line) catch {
        hd.oom = true;
        return 0;
    };
    defer owned.release();
    hd.headers.append(hd.ctx.allocator, .{ .string = owned }) catch {
        hd.oom = true;
        return 0;
    };
    return total;
}

fn fetchUrl(ctx: *NativeContext, url: []const u8) RuntimeError!NativeResult {
    if (ctx.vm.last_http_response_headers) |previous| ctx.vm.arrayRelease(previous);
    ctx.vm.last_http_response_headers = null;

    // Note: process-local curl_global_init is safe under zphp serve's fork-based worker model.
    if (!curl_global_init_done) {
        _ = c_curl.curl_global_init(c_curl.CURL_GLOBAL_DEFAULT);
        curl_global_init_done = true;
    }

    const handle = c_curl.curl_easy_init() orelse return NativeResult.scalar(.{ .bool = false });
    defer c_curl.curl_easy_cleanup(handle);

    var url_buf: [8192]u8 = undefined;
    if (url.len >= url_buf.len) return NativeResult.scalar(.{ .bool = false });
    @memcpy(url_buf[0..url.len], url);
    url_buf[url.len] = 0;

    _ = c_curl.curl_easy_setopt(handle, c_curl.CURLOPT_URL, &url_buf);
    _ = c_curl.curl_easy_setopt(handle, c_curl.CURLOPT_FOLLOWLOCATION, @as(c_long, 1));
    _ = c_curl.curl_easy_setopt(handle, c_curl.CURLOPT_MAXREDIRS, @as(c_long, 20));

    var wd = CurlWriteData{
        .allocator = ctx.allocator,
        .buffer = .empty,
    };
    defer wd.buffer.deinit(wd.allocator);

    const headers_arr = ctx.createArray() catch return NativeResult.scalar(.{ .bool = false });
    @import("../runtime/vm.zig").VM.arrayRetain(headers_arr);
    defer ctx.vm.arrayRelease(headers_arr);
    var hd = CurlHeaderData{
        .ctx = ctx,
        .headers = headers_arr,
    };

    _ = c_curl.curl_easy_setopt(handle, c_curl.CURLOPT_WRITEFUNCTION, @as(?*const fn ([*]u8, usize, usize, *anyopaque) callconv(.c) usize, &curlWriteCallback));
    _ = c_curl.curl_easy_setopt(handle, c_curl.CURLOPT_WRITEDATA, @as(*anyopaque, @ptrCast(&wd)));
    _ = c_curl.curl_easy_setopt(handle, c_curl.CURLOPT_HEADERFUNCTION, @as(?*const fn ([*]u8, usize, usize, *anyopaque) callconv(.c) usize, &curlHeaderCallback));
    _ = c_curl.curl_easy_setopt(handle, c_curl.CURLOPT_HEADERDATA, @as(*anyopaque, @ptrCast(&hd)));

    const result = c_curl.curl_easy_perform(handle);
    if (!hd.oom and headers_arr.entries.items.len > 0) {
        @import("../runtime/vm.zig").VM.arrayRetain(headers_arr);
        ctx.vm.last_http_response_headers = headers_arr;
    }
    if (result != c_curl.CURLE_OK) return NativeResult.scalar(.{ .bool = false });

    const body = try wd.buffer.toOwnedSlice(wd.allocator);
    errdefer wd.allocator.free(body);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, body));
}

fn native_file_get_contents(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const filename = try strArg(ctx, args, "file_get_contents", 0, "filename", true);
    const use_include_path = args.len > 1 and args[1].isTruthy();
    const offset = try intArg(ctx, args, "file_get_contents", 3, "offset", 0);
    const have_len = args.len >= 5 and args[4] != .null;
    const length: i64 = if (have_len) try intArg(ctx, args, "file_get_contents", 4, "length", 0) else 0;
    if (length < 0) return throwValueError(ctx, "file_get_contents(): Argument #5 ($length) must be greater than or equal to 0", .{});
    try useContext(ctx, args, 2);
    const path = try includePathLookup(ctx, filename, use_include_path);
    const content = (try readPathAs(ctx, path, "file_get_contents")) orelse return NativeResult.scalar(.{ .bool = false });
    transientStreams(ctx, 1);
    if (offset == 0 and !have_len) return NativeResult.takeString(content);

    defer content.release();
    const bytes = content.bytes();
    const total: i64 = @intCast(bytes.len);
    // a positive offset seeks from the start (past the end reads nothing), a
    // negative one from the end, and seeking before the start fails
    const start: i64 = if (offset >= 0) @min(offset, total) else total + offset;
    if (start < 0) {
        try warn(ctx, "file_get_contents(): Failed to seek to position {d} in the stream", .{offset});
        return NativeResult.scalar(.{ .bool = false });
    }
    const ustart: usize = @intCast(start);
    const finish = if (have_len) @min(bytes.len, ustart +| @as(usize, @intCast(length))) else bytes.len;
    return try NativeResult.copyString(ctx.allocator, bytes[ustart..finish]);
}

// the whole contents behind a path, through whichever wrapper serves it (user
// wrappers, php://, data:, phar://, compress.zlib://, http(s)://, plain files);
// null when it cannot be opened. the caller owns the returned reference
pub fn readPath(ctx: *NativeContext, raw_path: []const u8) RuntimeError!?Value.String {
    return readPathAs(ctx, raw_path, null);
}

// readPath for a php function that reports, as php's stream opener does, why
// the path could not be opened (func names it in the warning)
pub fn readPathAs(ctx: *NativeContext, raw_path: []const u8, comptime func: ?[]const u8) RuntimeError!?Value.String {
    var path = raw_path;
    if (func != null and path.len == 0) return throwValueError(ctx, "Path must not be empty", .{});
    if (std.mem.startsWith(u8, path, "file://")) path = path[7..];
    if (userWrapperFor(ctx.vm, path)) |class_name| {
        const opened = (try dispatchUserOpen(ctx, class_name, path, "rb")) orelse return null;
        const fh = opened.resource;
        const wrapper = fileHandleWrapper(fh) orelse return null;
        var buf = std.ArrayListUnmanaged(u8).empty;
        defer buf.deinit(ctx.allocator);
        while (true) {
            const chunk = try ctx.callMethod(wrapper, "stream_read", &[_]Value{.{ .int = 8192 }});
            if (chunk != .string or chunk.string.bytes().len == 0) break;
            try buf.appendSlice(ctx.allocator, chunk.string.bytes());
        }
        if (ctx.vm.hasMethod(fh.class_name, "stream_close") or ctx.vm.hasMethod(wrapper.class_name, "stream_close")) {
            _ = try ctx.callMethod(wrapper, "stream_close", &.{});
        }
        return try Value.String.adopt(ctx.allocator, try buf.toOwnedSlice(ctx.allocator));
    }
    if (extractScheme(path)) |s| {
        if (isBuiltinWrapper(s) and isWrapperUnregistered(ctx.vm, s)) return null;
    }
    if (std.mem.eql(u8, path, "php://input")) {
        const body_val = ctx.vm.request_vars.get("__raw_body") orelse return try Value.String.create(ctx.allocator, "");
        if (body_val != .string) return try Value.String.create(ctx.allocator, "");
        // the request body may be a borrowed slice; the caller needs a reference it owns
        if (body_val.string.owner == null) return try Value.String.create(ctx.allocator, body_val.string.bytes());
        body_val.string.retain();
        return body_val.string;
    }
    if (std.mem.eql(u8, path, "php://stdin")) {
        const data = platform.readToEndAlloc(std.Io.File.stdin(), ctx.allocator, std.math.maxInt(usize)) catch return null;
        return try Value.String.adopt(ctx.allocator, data);
    }
    if (std.mem.eql(u8, path, "php://stdout") or std.mem.eql(u8, path, "php://output") or std.mem.eql(u8, path, "php://stderr")) {
        return try Value.String.create(ctx.allocator, "");
    }
    if (std.mem.startsWith(u8, path, "data:")) {
        const payload = parseDataUri(ctx.allocator, path) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            if (func) |name| try warn(ctx, name ++ "({s}): Failed to open stream: {s}", .{ path, dataUriErrorText(err) });
            return null;
        };
        return try Value.String.adopt(ctx.allocator, payload);
    }
    if (std.mem.startsWith(u8, path, "phar://")) {
        const r = resolvePharPathWithCtx(path, ctx) orelse return null;
        const payload = (readPharEntry(ctx.allocator, r.archive_path, r.internal_path) catch return null) orelse return null;
        return try Value.String.adopt(ctx.allocator, payload);
    }
    if (std.mem.startsWith(u8, path, ZLIB_PREFIX)) {
        const decoded = readZlibFile(ctx.allocator, path) catch return null;
        return try Value.String.adopt(ctx.allocator, decoded);
    }
    if (path.len > 7 and (std.mem.startsWith(u8, path, "http://") or std.mem.startsWith(u8, path, "https://"))) {
        const fetched = try fetchUrl(ctx, path);
        return if (fetched.value == .string) fetched.value.string else null;
    }
    const content = bundle.readFileAlloc(ctx.allocator, path, std.math.maxInt(usize)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            const name = func orelse return null;
            if (err == error.IsDir) {
                // a directory opens, and the read is what fails
                const chunk: i64 = 8192;
                const size: i64 = if (std.mem.eql(u8, name, "file_get_contents")) (if (plainStat(path, false)) |st| st.size else 0) else 0;
                try notice(ctx, name ++ "(): Read of {d} bytes failed with errno=21 Is a directory", .{if (size > 0) size + chunk else chunk});
                return try Value.String.create(ctx.allocator, "");
            }
            try warn(ctx, name ++ "({s}): Failed to open stream: {s}", .{ raw_path, errorText(err) });
            return null;
        },
    };
    return Value.String.adopt(ctx.allocator, content) catch |err| {
        ctx.allocator.free(content);
        return err;
    };
}

fn native_file_put_contents(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    try useContext(ctx, args, 3);
    const result = try putContents(ctx, args);
    if (result.value == .int) transientStreams(ctx, 1);
    return result;
}

fn putContents(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const spelled_path = args[0].string.bytes();
    var formatted = std.ArrayListUnmanaged(u8).empty;
    defer formatted.deinit(ctx.allocator);
    const data = if (args[1] == .string) args[1].string.bytes() else if (args[1] == .array) blk: {
        // PHP writes an array argument as its elements concatenated, like
        // implode('', $array) - each element coerced to string
        for (args[1].array.entries.items) |entry| try entry.value.format(&formatted, ctx.allocator);
        break :blk formatted.items;
    } else blk: {
        try args[1].format(&formatted, ctx.allocator);
        break :blk formatted.items;
    };
    if (userWrapperFor(ctx.vm, spelled_path)) |class_name| {
        const opened = (try dispatchUserOpen(ctx, class_name, spelled_path, "wb")) orelse return NativeResult.scalar(.{ .bool = false });
        const wrapper = fileHandleWrapper(opened.resource) orelse return NativeResult.scalar(.{ .bool = false });
        const written = try ctx.callMethod(wrapper, "stream_write", &[_]Value{.{ .string = Value.String.borrowed(data) }});
        if (ctx.vm.hasMethod(wrapper.class_name, "stream_close")) {
            _ = try ctx.callMethod(wrapper, "stream_close", &.{});
        }
        if (written != .int) return NativeResult.scalar(.{ .bool = false });
        return NativeResult.scalar(.{ .int = written.int });
    }
    if (extractScheme(spelled_path)) |s| {
        if (isBuiltinWrapper(s) and isWrapperUnregistered(ctx.vm, s)) return NativeResult.scalar(.{ .bool = false });
    }
    if (std.mem.eql(u8, spelled_path, "php://stdout") or std.mem.eql(u8, spelled_path, "php://output")) {
        try ctx.vm.output.appendSlice(ctx.allocator, data);
        return NativeResult.scalar(.{ .int = @intCast(data.len) });
    }
    if (std.mem.eql(u8, spelled_path, "php://stderr")) {
        ctx.vm.flushOutputToStdout();
        const stderr = std.Io.File.stderr();
        const n = platform.write(stderr, data) catch return NativeResult.scalar(.{ .bool = false });
        return NativeResult.scalar(.{ .int = @intCast(n) });
    }
    if (std.mem.startsWith(u8, spelled_path, ZLIB_PREFIX)) {
        writeZlibFile(ctx.allocator, spelled_path, data) catch return NativeResult.scalar(.{ .bool = false });
        return NativeResult.scalar(.{ .int = @intCast(data.len) });
    }
    const flags: i64 = if (args.len >= 3) Value.toInt(args[2]) else 0;
    const append = (flags & 8) != 0; // FILE_APPEND = 8
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = paths.streamPath(&path_buf, spelled_path);
    bundle.prepareWrite(path, if (append) .edit else .create);
    if (append) {
        const file = std.Io.Dir.cwd().openFile(platform.io, path, .{ .mode = .write_only }) catch {
            std.Io.Dir.cwd().writeFile(platform.io, .{ .sub_path = path, .data = data }) catch return NativeResult.scalar(.{ .bool = false });
            return NativeResult.scalar(.{ .int = @intCast(data.len) });
        };
        defer file.close(platform.io);
        platform.seekFromEnd(file, 0) catch return NativeResult.scalar(.{ .bool = false });
        _ = platform.write(file, data) catch return NativeResult.scalar(.{ .bool = false });
    } else {
        std.Io.Dir.cwd().writeFile(platform.io, .{ .sub_path = path, .data = data }) catch return NativeResult.scalar(.{ .bool = false });
    }
    return NativeResult.scalar(.{ .int = @intCast(data.len) });
}

fn native_file_exists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const spelled = try strArg(ctx, args, "file_exists", 0, "filename", false);
    if (!usablePath(spelled)) return NativeResult.scalar(.{ .bool = false });
    var os_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = bundle.osPath(&os_buf, spelled);
    if (userWrapperFor(ctx.vm, path)) |class_name| {
        const arr = try dispatchUserStat(ctx, class_name, path, 0);
        return NativeResult.scalar(.{ .bool = arr != null });
    }
    if (extractScheme(path)) |s| {
        if (isBuiltinWrapper(s) and isWrapperUnregistered(ctx.vm, s)) return NativeResult.scalar(.{ .bool = false });
    }
    if (std.mem.startsWith(u8, path, "phar://")) {
        const r = resolvePharPathWithCtx(path, ctx) orelse return NativeResult.scalar(.{ .bool = false });
        if (r.internal_path.len == 0) return NativeResult.scalar(.{ .bool = true }); // archive itself
        var loaded = loadPhar(ctx.allocator, r.archive_path) catch return NativeResult.scalar(Value{ .bool = false });
        defer freePhar(ctx.allocator, &loaded);
        const normalized = normalizePharInternalPath(ctx.allocator, r.internal_path) catch return NativeResult.scalar(.{ .bool = false });
        defer ctx.allocator.free(normalized);
        if (loaded.parsed.lookup(normalized) != null) return NativeResult.scalar(.{ .bool = true });
        return NativeResult.scalar(.{ .bool = loaded.parsed.isDir(normalized) });
    }
    if (std.mem.startsWith(u8, path, ZLIB_PREFIX)) {
        std.Io.Dir.cwd().access(platform.io, path[ZLIB_PREFIX.len..], .{}) catch return NativeResult.scalar(Value{ .bool = false });
        return NativeResult.scalar(.{ .bool = true });
    }
    if (bundle.find(path) != null) return NativeResult.scalar(.{ .bool = true });
    std.Io.Dir.cwd().access(platform.io, path, .{}) catch return NativeResult.scalar(Value{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn native_is_file(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    var os_buf: [std.fs.max_path_bytes]u8 = undefined;
    const spelled = try strArg(ctx, args, "is_file", 0, "filename", false);
    if (!usablePath(spelled)) return NativeResult.scalar(.{ .bool = false });
    const path = bundle.osPath(&os_buf, spelled);
    if (userWrapperFor(ctx.vm, path)) |class_name| {
        const arr = (try dispatchUserStat(ctx, class_name, path, 0)) orelse return NativeResult.scalar(.{ .bool = false });
        const mode_v = arr.get(.{ .string = Value.String.borrowed("mode") });
        if (mode_v != .int) return NativeResult.scalar(.{ .bool = false });
        return NativeResult.scalar(.{ .bool = (mode_v.int & 0o170000) == 0o100000 });
    }
    if (extractScheme(path)) |s| {
        if (isBuiltinWrapper(s) and isWrapperUnregistered(ctx.vm, s)) return NativeResult.scalar(.{ .bool = false });
    }
    if (std.mem.startsWith(u8, path, "phar://")) {
        const r = resolvePharPathWithCtx(path, ctx) orelse return NativeResult.scalar(.{ .bool = false });
        if (r.internal_path.len == 0) return NativeResult.scalar(.{ .bool = true });
        var loaded = loadPhar(ctx.allocator, r.archive_path) catch return NativeResult.scalar(Value{ .bool = false });
        defer freePhar(ctx.allocator, &loaded);
        const normalized = normalizePharInternalPath(ctx.allocator, r.internal_path) catch return NativeResult.scalar(.{ .bool = false });
        defer ctx.allocator.free(normalized);
        return NativeResult.scalar(.{ .bool = loaded.parsed.lookup(normalized) != null });
    }
    if (std.mem.startsWith(u8, path, ZLIB_PREFIX)) {
        const stat = std.Io.Dir.cwd().statFile(platform.io, path[ZLIB_PREFIX.len..], .{}) catch return NativeResult.scalar(Value{ .bool = false });
        return NativeResult.scalar(.{ .bool = stat.kind == .file });
    }
    if (bundle.find(path)) |hit| return NativeResult.scalar(.{ .bool = hit == .file });
    const stat = std.Io.Dir.cwd().statFile(platform.io, path, .{}) catch return NativeResult.scalar(Value{ .bool = false });
    return NativeResult.scalar(.{ .bool = stat.kind == .file });
}

fn native_is_dir(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    var os_buf: [std.fs.max_path_bytes]u8 = undefined;
    const spelled = try strArg(ctx, args, "is_dir", 0, "filename", false);
    if (!usablePath(spelled)) return NativeResult.scalar(.{ .bool = false });
    const path = bundle.osPath(&os_buf, spelled);
    if (userWrapperFor(ctx.vm, path)) |class_name| {
        const arr = (try dispatchUserStat(ctx, class_name, path, 0)) orelse return NativeResult.scalar(.{ .bool = false });
        const mode_v = arr.get(.{ .string = Value.String.borrowed("mode") });
        if (mode_v != .int) return NativeResult.scalar(.{ .bool = false });
        return NativeResult.scalar(.{ .bool = (mode_v.int & 0o170000) == 0o040000 });
    }
    if (extractScheme(path)) |s| {
        if (isBuiltinWrapper(s) and isWrapperUnregistered(ctx.vm, s)) return NativeResult.scalar(.{ .bool = false });
    }
    if (std.mem.startsWith(u8, path, "phar://")) {
        const r = resolvePharPathWithCtx(path, ctx) orelse return NativeResult.scalar(.{ .bool = false });
        if (r.internal_path.len == 0) return NativeResult.scalar(.{ .bool = false }); // the archive is a file, not a dir
        var loaded = loadPhar(ctx.allocator, r.archive_path) catch return NativeResult.scalar(Value{ .bool = false });
        defer freePhar(ctx.allocator, &loaded);
        const normalized = normalizePharInternalPath(ctx.allocator, r.internal_path) catch return NativeResult.scalar(.{ .bool = false });
        defer ctx.allocator.free(normalized);
        return NativeResult.scalar(.{ .bool = loaded.parsed.isDir(normalized) });
    }
    if (bundle.find(path)) |hit| if (hit == .dir) return NativeResult.scalar(.{ .bool = true });
    var dir = std.Io.Dir.cwd().openDir(platform.io, path, .{}) catch return NativeResult.scalar(Value{ .bool = false });
    dir.close(platform.io);
    return NativeResult.scalar(.{ .bool = true });
}

// an empty path or one with a nul byte names nothing; the exists-style
// checks answer false for it without a warning
fn usablePath(path: []const u8) bool {
    return path.len > 0 and std.mem.indexOfScalar(u8, path, 0) == null;
}

// the last path separator; windows accepts both kinds
fn lastSep(path: []const u8) ?usize {
    var i = path.len;
    while (i > 0) : (i -= 1) if (platform.isSep(path[i - 1])) return i - 1;
    return null;
}

fn native_basename(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.literal("");
    var path = args[0].string.bytes();
    const suffix = if (args.len >= 2 and args[1] == .string) args[1].string.bytes() else "";
    // PHP strips trailing slashes before extracting the last segment
    while (path.len > 1 and platform.isSep(path[path.len - 1])) path = path[0 .. path.len - 1];
    var name: []const u8 = path;
    if (lastSep(path)) |pos| {
        name = path[pos + 1 ..];
    }
    if (suffix.len > 0 and name.len > suffix.len and std.mem.endsWith(u8, name, suffix)) {
        name = name[0 .. name.len - suffix.len];
    }
    return NativeResult.copyString(ctx.allocator, name);
}

fn native_dirname(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.literal("");
    var path = args[0].string.bytes();
    if (path.len == 0) return NativeResult.literal("");
    var levels: i64 = if (args.len >= 2) Value.toInt(args[1]) else 1;
    if (levels <= 0) return NativeResult.copyString(ctx.allocator, path);
    while (levels > 0) : (levels -= 1) {
        while (path.len > 1 and platform.isSep(path[path.len - 1])) path = path[0 .. path.len - 1];
        if (lastSep(path)) |pos| {
            if (pos == 0) {
                path = platform.sep_str;
                break;
            }
            path = path[0..pos];
        } else {
            path = ".";
            break;
        }
    }
    return NativeResult.copyString(ctx.allocator, path);
}

fn native_pathinfo(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.null);
    // PHP strips trailing slashes from the input before splitting (so
    // pathinfo("/a/b/") yields dirname=/a, basename=b, matching basename())
    var path = args[0].string.bytes();
    while (path.len > 1 and platform.isSep(path[path.len - 1])) path = path[0 .. path.len - 1];

    const dir: []const u8 = if (lastSep(path)) |pos|
        (if (pos == 0) platform.sep_str else path[0..pos])
    else
        ".";
    const base: []const u8 = if (lastSep(path)) |pos| path[pos + 1 ..] else path;
    const has_dot = std.mem.lastIndexOf(u8, base, ".") != null;
    const dot_pos: usize = if (has_dot) std.mem.lastIndexOf(u8, base, ".").? else 0;
    const ext: []const u8 = if (has_dot) base[dot_pos + 1 ..] else "";
    const filename: []const u8 = if (has_dot) base[0..dot_pos] else base;

    if (args.len >= 2 and args[1] == .int) {
        const flag = args[1].int;
        return switch (flag) {
            1 => try NativeResult.copyString(ctx.allocator, dir),
            2 => try NativeResult.copyString(ctx.allocator, base),
            4 => try NativeResult.copyString(ctx.allocator, ext),
            8 => try NativeResult.copyString(ctx.allocator, filename),
            else => NativeResult.scalar(.null),
        };
    }

    var arr = try ctx.createArray();
    try arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("dirname") }, dir);
    try arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("basename") }, base);
    if (has_dot) {
        try arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("extension") }, ext);
    }
    try arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("filename") }, filename);
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_realpath(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const given = try strArg(ctx, args, "realpath", 0, "path", true);
    // an empty path resolves the working directory, as "." does
    const spelled = if (given.len == 0) "." else given;
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    var os_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = bundle.osPath(&os_buf, spelled);
    if (bundle.canonicalPath(&buf, path)) |packed_path| return NativeResult.copyString(ctx.allocator, packed_path);
    const resolved = platform.realpath(spelled, &buf) catch return NativeResult.scalar(Value{ .bool = false });
    return NativeResult.copyString(ctx.allocator, resolved);
}

// directory operations

fn native_mkdir(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const spelled = try strArg(ctx, args, "mkdir", 0, "directory", true);
    const mode_arg = try intArg(ctx, args, "mkdir", 1, "permissions", 0o777);
    const recursive = args.len >= 3 and args[2].isTruthy();
    try useContext(ctx, args, 3);
    var os_buf: [std.fs.max_path_bytes]u8 = undefined;
    var path = bundle.osPath(&os_buf, spelled);
    if (std.ascii.startsWithIgnoreCase(path, "file://")) path = path[7..];
    if (bundle.find(path) != null) {
        try warn(ctx, "mkdir(): File exists", .{});
        return NativeResult.scalar(.{ .bool = false });
    }
    bundle.prepareWrite(path, .create);
    makeDirectory(path, @truncate(@as(u64, @bitCast(mode_arg))), recursive) catch |err| {
        try warn(ctx, "mkdir(): {s}", .{errorText(err)});
        return NativeResult.scalar(.{ .bool = false });
    };
    return NativeResult.scalar(.{ .bool = true });
}

fn makeDirectory(path: []const u8, mode: u32, recursive: bool) !void {
    if (path.len == 0) return error.FileNotFound;
    if (platform.is_windows) {
        if (!recursive) return std.Io.Dir.cwd().createDir(platform.io, path, .default_dir);
        // makePath succeeds on an existing directory; php's mkdir fails
        if (std.Io.Dir.cwd().access(platform.io, path, .{})) |_| return error.PathAlreadyExists else |_| {}
        return std.Io.Dir.cwd().createDirPath(platform.io, path);
    }
    // std.fs creates directories as 0755, php passes $mode (default 0777)
    // through to mkdir(2) and lets the umask narrow it
    const m: std.posix.mode_t = @intCast(mode & 0o7777);
    if (recursive) return makePathMode(path, m);
    return sys.mkdir(path, m);
}

// every missing directory along the path gets the same mode, as in php. an
// existing parent is fine, an existing final directory fails like mkdir(2)
fn makePathMode(path: []const u8, mode: std.posix.mode_t) !void {
    const full = std.mem.trimEnd(u8, path, "/");
    if (full.len == 0) return error.PathAlreadyExists;
    var end: usize = 0;
    while (end < full.len) {
        end = std.mem.indexOfScalarPos(u8, full, end + 1, '/') orelse full.len;
        sys.mkdir(full[0..end], mode) catch |err| switch (err) {
            error.PathAlreadyExists => if (end == full.len) return err,
            else => return err,
        };
    }
}

fn native_rmdir(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const spelled = try strArg(ctx, args, "rmdir", 0, "directory", true);
    try useContext(ctx, args, 1);
    var os_buf: [std.fs.max_path_bytes]u8 = undefined;
    var path = bundle.osPath(&os_buf, spelled);
    if (std.ascii.startsWithIgnoreCase(path, "file://")) path = path[7..];
    removeDirectory(path) catch |err| {
        try warn(ctx, "rmdir({s}): {s}", .{ path, errorText(err) });
        return NativeResult.scalar(.{ .bool = false });
    };
    return NativeResult.scalar(.{ .bool = true });
}

fn removeDirectory(path: []const u8) !void {
    if (path.len == 0) return error.FileNotFound;
    if (bundle.listDir(path)) |listing| {
        var packed_names = listing;
        if (packed_names.next() != null) return error.DirNotEmpty;
    }
    std.Io.Dir.cwd().deleteDir(platform.io, path) catch |err| {
        if (err == error.FileNotFound and bundle.find(path) != null and bundle.remove(path)) return;
        return err;
    };
    _ = bundle.remove(path);
}

fn native_unlink(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const spelled = try strArg(ctx, args, "unlink", 0, "filename", true);
    try useContext(ctx, args, 1);
    var os_buf: [std.fs.max_path_bytes]u8 = undefined;
    var path = bundle.osPath(&os_buf, spelled);
    if (userWrapperFor(ctx.vm, path)) |class_name| {
        if (!ctx.vm.hasMethod(class_name, "unlink")) return NativeResult.scalar(.{ .bool = false });
        const wrapper = try ctx.createObject(class_name);
        if (ctx.vm.hasMethod(class_name, "__construct")) {
            _ = try ctx.callMethod(wrapper, "__construct", &.{});
        }
        const result = try ctx.callMethod(wrapper, "unlink", &[_]Value{args[0]});
        return NativeResult.scalar(.{ .bool = result.isTruthy() });
    }
    if (extractScheme(path)) |s| {
        if (isBuiltinWrapper(s) and isWrapperUnregistered(ctx.vm, s)) return NativeResult.scalar(.{ .bool = false });
    }
    if (std.ascii.startsWithIgnoreCase(path, "file://")) path = path[7..];
    deletePath(path) catch |err| {
        try warn(ctx, "unlink({s}): {s}", .{ path, errorText(err) });
        return NativeResult.scalar(.{ .bool = false });
    };
    return NativeResult.scalar(.{ .bool = true });
}

// deletes a file, hiding a packed copy the executable's application holds
pub fn unlinkPath(path: []const u8) NativeResult {
    deletePath(path) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn deletePath(path: []const u8) !void {
    if (path.len == 0) return error.FileNotFound;
    std.Io.Dir.cwd().deleteFile(platform.io, path) catch |err| {
        if (err == error.FileNotFound and packedFileAt(path) and bundle.remove(path)) return;
        return err;
    };
    _ = bundle.remove(path);
}

fn packedFileAt(path: []const u8) bool {
    const hit = bundle.find(path) orelse return false;
    return hit == .file;
}

fn native_copy(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const spelled_source = try strArg(ctx, args, "copy", 0, "from", true);
    const spelled_dest = try strArg(ctx, args, "copy", 1, "to", true);
    try useContext(ctx, args, 2);
    var source_buf: [std.fs.max_path_bytes]u8 = undefined;
    var dest_buf: [std.fs.max_path_bytes]u8 = undefined;
    var source = paths.streamPath(&source_buf, spelled_source);
    var dest = paths.streamPath(&dest_buf, spelled_dest);
    if (std.ascii.startsWithIgnoreCase(source, "file://")) source = source[7..];
    if (std.ascii.startsWithIgnoreCase(dest, "file://")) dest = dest[7..];

    // php_copy_file_ctx: a directory on either side is refused, and a file
    // copied onto itself fails quietly
    const plain_source = !paths.hasScheme(source);
    const source_stat: ?WrapperStat = if (bundle.find(source)) |hit| packedStat(hit) else if (plain_source and source.len > 0) plainStat(source, false) else null;
    if (source_stat) |st| if (st.mode & 0o170000 == 0o040000) {
        try warn(ctx, "copy(): The first argument to copy() function cannot be a directory", .{});
        return NativeResult.scalar(.{ .bool = false });
    };
    if (paths.hasScheme(dest)) return NativeResult.scalar(.{ .bool = false });
    const dest_stat: ?WrapperStat = if (dest.len > 0) plainStat(dest, false) else null;
    if (dest_stat) |st| if (st.mode & 0o170000 == 0o040000) {
        try warn(ctx, "copy(): The second argument to copy() function cannot be a directory", .{});
        return NativeResult.scalar(.{ .bool = false });
    };
    if (source_stat != null and dest_stat != null and source_stat.?.ino != 0 and source_stat.?.ino == dest_stat.?.ino and source_stat.?.dev == dest_stat.?.dev) {
        return NativeResult.scalar(.{ .bool = false });
    }

    // the source opens first, then the destination is created or truncated
    var wrapped: ?Value.String = null;
    defer if (wrapped) |w| w.release();
    var source_file: ?std.Io.File = null;
    defer if (source_file) |f| f.close(platform.io);
    try requirePath(ctx, source);
    if (bundle.find(source)) |hit| switch (hit) {
        .file => |entry| wrapped = try Value.String.create(ctx.allocator, entry.source),
        .dir => unreachable,
    } else if (!plain_source) {
        wrapped = (try readPath(ctx, source)) orelse {
            try warn(ctx, "copy({s}): Failed to open stream: operation failed", .{source});
            return NativeResult.scalar(.{ .bool = false });
        };
    } else {
        source_file = openPlain(source) catch |err| {
            try warn(ctx, "copy({s}): Failed to open stream: {s}", .{ source, errorText(err) });
            return NativeResult.scalar(.{ .bool = false });
        };
    }
    transientStreams(ctx, 1);
    try requirePath(ctx, dest);
    bundle.prepareWrite(dest, .create);
    const dest_file = createPlain(dest) catch |err| {
        try warn(ctx, "copy({s}): Failed to open stream: {s}", .{ dest, errorText(err) });
        return NativeResult.scalar(.{ .bool = false });
    };
    defer dest_file.close(platform.io);
    transientStreams(ctx, 1);
    if (wrapped) |w| {
        platform.writeAll(dest_file, w.bytes()) catch return NativeResult.scalar(.{ .bool = false });
    } else {
        var buf: [64 * 1024]u8 = undefined;
        while (true) {
            const n = platform.read(source_file.?, &buf) catch return NativeResult.scalar(.{ .bool = false });
            if (n == 0) break;
            platform.writeAll(dest_file, buf[0..n]) catch return NativeResult.scalar(.{ .bool = false });
        }
    }
    return NativeResult.scalar(.{ .bool = true });
}

// php's stream opener refuses an empty path outright
fn requirePath(ctx: *NativeContext, path: []const u8) RuntimeError!void {
    if (path.len == 0) return throwValueError(ctx, "Path must not be empty", .{});
}

// a plain file opened for reading; an empty path names nothing
fn openPlain(path: []const u8) !std.Io.File {
    if (path.len == 0) return error.FileNotFound;
    return std.Io.Dir.cwd().openFile(platform.io, path, .{});
}

// a plain file created or truncated for writing, mode "wb"
fn createPlain(path: []const u8) !std.Io.File {
    if (path.len == 0) return error.FileNotFound;
    return std.Io.Dir.cwd().createFile(platform.io, path, .{ .truncate = true });
}

fn native_rename(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const spelled_from = try strArg(ctx, args, "rename", 0, "from", true);
    const spelled_to = try strArg(ctx, args, "rename", 1, "to", true);
    try useContext(ctx, args, 2);
    var os_buf: [std.fs.max_path_bytes]u8 = undefined;
    var to_buf: [std.fs.max_path_bytes]u8 = undefined;
    var from = bundle.osPath(&os_buf, spelled_from);
    var to = bundle.osPath(&to_buf, spelled_to);
    if (std.ascii.startsWithIgnoreCase(from, "file://")) from = from[7..];
    if (std.ascii.startsWithIgnoreCase(to, "file://")) to = to[7..];
    bundle.prepareWrite(to, .create);
    bundle.prepareWrite(from, .edit);
    renamePath(from, to) catch |err| {
        try warn(ctx, "rename({s},{s}): {s}", .{ from, to, errorText(err) });
        return NativeResult.scalar(.{ .bool = false });
    };
    _ = bundle.remove(from);
    return NativeResult.scalar(.{ .bool = true });
}

fn renamePath(from: []const u8, to: []const u8) !void {
    if (from.len == 0 or to.len == 0) return error.FileNotFound;
    std.Io.Dir.cwd().rename(from, std.Io.Dir.cwd(), to, platform.io) catch |err| {
        // across filesystems php copies the file and removes the original
        if (err != error.CrossDevice) return err;
        try std.Io.Dir.cwd().copyFile(from, std.Io.Dir.cwd(), to, platform.io, .{});
        try std.Io.Dir.cwd().deleteFile(platform.io, from);
    };
}

// directory listing

fn native_scandir(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    // SCANDIR_SORT_ASCENDING=0, _DESCENDING=1, _NONE=2
    const order: i64 = if (args.len >= 2 and args[1] == .int) args[1].int else 0;
    var names = std.ArrayListUnmanaged(Value.String).empty;
    defer names.deinit(ctx.allocator);
    defer for (names.items) |name| name.release();
    if (!try directoryNames(ctx, args[0].string.bytes(), &names)) return NativeResult.scalar(.{ .bool = false });
    transientStreams(ctx, 1);

    if (order == 0 or order == 1) {
        const lessAsc = struct {
            fn f(_: void, a: Value.String, b: Value.String) bool {
                return std.mem.order(u8, a.bytes(), b.bytes()) == .lt;
            }
        }.f;
        const lessDesc = struct {
            fn f(_: void, a: Value.String, b: Value.String) bool {
                return std.mem.order(u8, a.bytes(), b.bytes()) == .gt;
            }
        }.f;
        if (order == 0) std.mem.sort(Value.String, names.items, {}, lessAsc) else std.mem.sort(Value.String, names.items, {}, lessDesc);
    }

    var result = try ctx.createArray();
    for (names.items) |n| try result.append(ctx.allocator, .{ .string = n });
    return NativeResult.borrowed(.{ .array = result });
}

// the names in a directory, `.` and `..` first: the disk and the executable's
// packed application both contribute, a name once; false when neither has the
// directory
fn directoryNames(ctx: *NativeContext, path: []const u8, names: *std.ArrayListUnmanaged(Value.String)) RuntimeError!bool {
    var os_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = bundle.osPath(&os_buf, path);
    var listing = bundle.listDir(dir_path);
    var dir_opt: ?std.Io.Dir = std.Io.Dir.cwd().openDir(platform.io, dir_path, .{ .iterate = true }) catch null;
    defer if (dir_opt) |*d| d.close(platform.io);
    if (listing == null and dir_opt == null) return false;
    try names.append(ctx.allocator, Value.String.borrowed("."));
    try names.append(ctx.allocator, Value.String.borrowed(".."));
    if (dir_opt) |*dir| {
        var iter = dir.iterate();
        while (iter.next(platform.io) catch null) |entry| try appendName(ctx, names, entry.name);
    }
    if (listing) |*packed_names| while (packed_names.next()) |child| {
        if (dir_opt) |dir| if (dirHas(dir, child.name)) continue;
        try appendName(ctx, names, child.name);
    };
    return true;
}

pub fn dirHas(dir: std.Io.Dir, name: []const u8) bool {
    dir.access(platform.io, name, .{}) catch |err| return err != error.FileNotFound;
    return true;
}

fn appendName(ctx: *NativeContext, names: *std.ArrayListUnmanaged(Value.String), bytes: []const u8) RuntimeError!void {
    const name = try Value.String.create(ctx.allocator, bytes);
    names.append(ctx.allocator, name) catch |err| {
        name.release();
        return err;
    };
}

// dir($path) returns a Directory object with path, handle, and read/rewind/
// close methods that delegate to the underlying DirectoryHandle. PHP's
// 'Directory' is a thin OO wrapper around opendir/readdir/rewinddir/closedir
fn directoryConstruct(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    try ctx.vm.setPendingException("Error", "Cannot directly construct Directory, use dir() instead");
    return error.RuntimeError;
}

fn native_dir(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const handle = (try native_opendir(ctx, args)).value;
    if (handle != .resource) return NativeResult.scalar(.{ .bool = false });
    const obj = try ctx.createObject("Directory");
    try obj.set(ctx.allocator, "path", .{ .string = args[0].string });
    try obj.set(ctx.allocator, "handle", handle);
    return NativeResult.borrowed(.{ .object = obj });
}

fn directoryRead(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = ctx.vm.currentFrame().vars.get("$this") orelse return NativeResult.scalar(.{ .bool = false });
    if (this != .object) return NativeResult.scalar(.{ .bool = false });
    const h = this.object.get("handle");
    if (h != .resource) return NativeResult.scalar(.{ .bool = false });
    return native_readdir(ctx, &.{h});
}

fn directoryRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = ctx.vm.currentFrame().vars.get("$this") orelse return NativeResult.scalar(.null);
    if (this != .object) return NativeResult.scalar(.null);
    const h = this.object.get("handle");
    if (h != .resource) return NativeResult.scalar(.null);
    return native_rewinddir(ctx, &.{h});
}

fn directoryClose(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = ctx.vm.currentFrame().vars.get("$this") orelse return NativeResult.scalar(.null);
    if (this != .object) return NativeResult.scalar(.null);
    const h = this.object.get("handle");
    if (h != .resource) return NativeResult.scalar(.null);
    return native_closedir(ctx, &.{h});
}

fn native_opendir(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    try useContext(ctx, args, 1);
    var names = std.ArrayListUnmanaged(Value.String).empty;
    defer names.deinit(ctx.allocator);
    defer for (names.items) |name| name.release();
    if (!try directoryNames(ctx, args[0].string.bytes(), &names)) return NativeResult.scalar(.{ .bool = false });
    const names_arr = try ctx.vm.allocArray();
    for (names.items) |name| try names_arr.append(ctx.allocator, .{ .string = name });
    const obj = try ctx.createResource("DirectoryHandle");
    try obj.set(ctx.allocator, "__entries", .{ .array = names_arr });
    try obj.set(ctx.allocator, "__pos", .{ .int = 0 });
    try obj.set(ctx.allocator, "__open", .{ .bool = true });
    ctx.vm.rememberLastDirectory(obj);
    return NativeResult.borrowed(.{ .resource = obj });
}

// the directory a dir function acts on: its argument, or the directory
// opened last when it has none
fn dirArg(ctx: *NativeContext, args: []const Value, comptime func: []const u8) RuntimeError!*PhpObject {
    if (args.len == 0 or args[0] == .null) {
        const last = ctx.vm.last_directory orelse return throwStreamArg(ctx, "No resource supplied", .{});
        if (value_mod.resourceClosed(last)) return throwStreamArg(ctx, func ++ "(): Argument #1 ($dir_handle) must be an open stream resource", .{});
        return last;
    }
    return streamArg(ctx, args, .{ .func = func, .param = "dir_handle", .directory = true });
}

fn native_readdir(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try dirArg(ctx, args, "readdir");
    const dir_entries = obj.get("__entries");
    if (dir_entries != .array) return NativeResult.scalar(.{ .bool = false });
    const pos = Value.toInt(obj.get("__pos"));
    if (pos < 0 or pos >= dir_entries.array.length()) return NativeResult.scalar(.{ .bool = false });
    const entry = dir_entries.array.entries.items[@intCast(pos)].value;
    try obj.set(ctx.allocator, "__pos", .{ .int = pos + 1 });
    return NativeResult.share(entry);
}

fn native_closedir(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try dirArg(ctx, args, "closedir");
    try obj.set(ctx.allocator, "__open", .{ .bool = false });
    if (ctx.vm.last_directory == obj) ctx.vm.forgetLastDirectory();
    return NativeResult.scalar(.null);
}

fn native_rewinddir(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try dirArg(ctx, args, "rewinddir");
    try obj.set(ctx.allocator, "__pos", .{ .int = 0 });
    return NativeResult.scalar(.null);
}

fn native_fnmatch(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const flags: i64 = if (args.len >= 3) Value.toInt(args[2]) else 0;
    return NativeResult.scalar(.{ .bool = globMatchFlags(args[0].string.bytes(), args[1].string.bytes(), flags) });
}

fn native_glob(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const pattern = args[0].string.bytes();
    const flags: i64 = if (args.len >= 2 and args[1] == .int) args[1].int else 0;
    const GLOB_BRACE: i64 = 128;
    const GLOB_ONLYDIR: i64 = 1073741824;
    const GLOB_NOSORT: i64 = 32;

    const result = try ctx.createArray();

    if ((flags & GLOB_BRACE) != 0) {
        if (std.mem.indexOfScalar(u8, pattern, '{')) |open| {
            if (std.mem.indexOfScalarPos(u8, pattern, open, '}')) |close| {
                const prefix = pattern[0..open];
                const suffix = pattern[close + 1 ..];
                const inner = pattern[open + 1 .. close];
                var it = std.mem.splitScalar(u8, inner, ',');
                while (it.next()) |alt| {
                    const expanded = try std.fmt.allocPrint(ctx.allocator, "{s}{s}{s}", .{ prefix, alt, suffix });
                    defer ctx.allocator.free(expanded);
                    try globAppend(ctx, result, expanded, flags);
                }
                if ((flags & GLOB_NOSORT) == 0) sortArrayValues(result);
                return NativeResult.borrowed(.{ .array = result });
            }
        }
    }

    try globAppend(ctx, result, pattern, flags);
    if ((flags & GLOB_NOSORT) == 0) sortArrayValues(result);
    // GLOB_NOCHECK: when no entries matched, return the literal pattern in
    // a single-element array instead of an empty array
    const GLOB_NOCHECK: i64 = 16;
    if (result.entries.items.len == 0 and (flags & GLOB_NOCHECK) != 0) {
        try result.appendCopiedString(ctx.allocator, pattern);
    }
    _ = GLOB_ONLYDIR;
    return NativeResult.borrowed(.{ .array = result });
}

fn globAppend(ctx: *NativeContext, result: *PhpArray, pattern: []const u8, flags: i64) !void {
    const dir_path = if (std.mem.lastIndexOf(u8, pattern, "/")) |pos| pattern[0..pos] else ".";
    const file_pattern = if (std.mem.lastIndexOf(u8, pattern, "/")) |pos| pattern[pos + 1 ..] else pattern;
    var os_buf: [std.fs.max_path_bytes]u8 = undefined;
    const os_dir = bundle.osPath(&os_buf, dir_path);
    var dir_opt: ?std.Io.Dir = std.Io.Dir.cwd().openDir(platform.io, os_dir, .{ .iterate = true }) catch null;
    defer if (dir_opt) |*d| d.close(platform.io);
    if (dir_opt) |*dir| {
        var iter = dir.iterate();
        while (iter.next(platform.io) catch null) |entry| {
            try globAppendEntry(ctx, result, .{ .dir_path = dir_path, .pattern = file_pattern, .name = entry.name, .is_dir = entry.kind == .directory, .flags = flags });
        }
    }
    // the executable's packed application contributes what the disk lacks
    var listing = bundle.listDir(os_dir) orelse return;
    while (listing.next()) |child| {
        if (dir_opt) |dir| if (dirHas(dir, child.name)) continue;
        try globAppendEntry(ctx, result, .{ .dir_path = dir_path, .pattern = file_pattern, .name = child.name, .is_dir = child.kind == .dir, .flags = flags });
    }
}

const GlobEntry = struct { dir_path: []const u8, pattern: []const u8, name: []const u8, is_dir: bool, flags: i64 };

fn globAppendEntry(ctx: *NativeContext, result: *PhpArray, entry: GlobEntry) !void {
    const GLOB_ONLYDIR: i64 = 1073741824;
    const GLOB_MARK: i64 = 8;
    const FNM_PERIOD: i64 = 4;
    // glob excludes dotfiles unless the pattern explicitly starts with '.'
    if (!globMatchFlags(entry.pattern, entry.name, FNM_PERIOD)) return;
    if ((entry.flags & GLOB_ONLYDIR) != 0 and !entry.is_dir) return;
    var path_buf: [4096]u8 = undefined;
    const slash: []const u8 = if ((entry.flags & GLOB_MARK) != 0 and entry.is_dir) "/" else "";
    const full = std.fmt.bufPrint(&path_buf, "{s}/{s}{s}", .{ entry.dir_path, entry.name, slash }) catch return;
    try result.appendCopiedString(ctx.allocator, full);
}

fn sortArrayValues(arr: *PhpArray) void {
    const items = arr.entries.items;
    const Entry = PhpArray.Entry;
    std.sort.pdq(Entry, items, {}, struct {
        fn lt(_: void, a: Entry, b: Entry) bool {
            if (a.value != .string or b.value != .string) return false;
            return std.mem.order(u8, a.value.string.bytes(), b.value.string.bytes()) == .lt;
        }
    }.lt);
    for (items, 0..) |*entry, i| entry.key = .{ .int = @intCast(i) };
}

fn globMatch(pattern: []const u8, name: []const u8) bool {
    return globMatchFlags(pattern, name, 0);
}

fn globMatchFlags(pattern: []const u8, name: []const u8, flags: i64) bool {
    const FNM_PATHNAME: i64 = 2;
    const FNM_PERIOD: i64 = 4;
    const FNM_CASEFOLD: i64 = 16;
    const casefold = (flags & FNM_CASEFOLD) != 0;
    const pathname = (flags & FNM_PATHNAME) != 0;
    const period = (flags & FNM_PERIOD) != 0;

    // FNM_PERIOD: a leading '.' must be matched explicitly (not by * ? or [class])
    if (period and name.len > 0 and name[0] == '.') {
        if (pattern.len == 0 or pattern[0] != '.') return false;
    }

    const eq = struct {
        fn f(a: u8, b: u8, ci: bool) bool {
            if (a == b) return true;
            if (!ci) return false;
            const al = if (a >= 'A' and a <= 'Z') a + 32 else a;
            const bl = if (b >= 'A' and b <= 'Z') b + 32 else b;
            return al == bl;
        }
    }.f;

    var pi: usize = 0;
    var ni: usize = 0;
    var star_pi: ?usize = null;
    var star_ni: ?usize = null;

    while (ni < name.len or pi < pattern.len) {
        if (pi < pattern.len and pattern[pi] == '*') {
            star_pi = pi;
            star_ni = ni;
            pi += 1;
            continue;
        }
        if (pi < pattern.len and ni < name.len) {
            // FNM_PATHNAME: '/' in name must be matched literally; * and ? don't cross it
            if (pathname and name[ni] == '/' and pattern[pi] != '/') {
                // fall through to backtrack
            } else if (pattern[pi] == '?' or eq(pattern[pi], name[ni], casefold)) {
                pi += 1;
                ni += 1;
                continue;
            } else if (pattern[pi] == '[') {
                if (std.mem.indexOfScalarPos(u8, pattern, pi + 1, ']')) |close| {
                    var negate = false;
                    var class_start = pi + 1;
                    if (class_start < close and (pattern[class_start] == '!' or pattern[class_start] == '^')) {
                        negate = true;
                        class_start += 1;
                    }
                    const c = name[ni];
                    var matched = false;
                    var k = class_start;
                    while (k < close) {
                        if (k + 2 < close and pattern[k + 1] == '-') {
                            const lo = pattern[k];
                            const hi = pattern[k + 2];
                            if (c >= lo and c <= hi) matched = true;
                            if (casefold) {
                                const cl = if (c >= 'A' and c <= 'Z') c + 32 else c;
                                if (cl >= lo and cl <= hi) matched = true;
                            }
                            k += 3;
                        } else {
                            if (eq(pattern[k], c, casefold)) matched = true;
                            k += 1;
                        }
                    }
                    if (matched != negate) {
                        pi = close + 1;
                        ni += 1;
                        continue;
                    }
                }
            }
        }
        if (star_pi) |sp| {
            pi = sp + 1;
            star_ni.? += 1;
            ni = star_ni.?;
            if (ni > name.len) return false;
            continue;
        }
        return false;
    }
    return true;
}

// file info

fn native_is_readable(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const spelled = try strArg(ctx, args, "is_readable", 0, "filename", false);
    if (!usablePath(spelled)) return NativeResult.scalar(.{ .bool = false });
    if (std.mem.startsWith(u8, spelled, "phar://")) return native_is_file(ctx, args);
    var os_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = bundle.osPath(&os_buf, spelled);
    if (bundle.find(path) != null) return NativeResult.scalar(.{ .bool = true });
    std.Io.Dir.cwd().access(platform.io, path, .{ .read = true }) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn native_is_writable(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const spelled = try strArg(ctx, args, "is_writable", 0, "filename", false);
    if (!usablePath(spelled)) return NativeResult.scalar(.{ .bool = false });
    var os_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = bundle.osPath(&os_buf, spelled);
    if (bundle.find(path) != null) return NativeResult.scalar(.{ .bool = writableAncestor(path) });
    std.Io.Dir.cwd().access(platform.io, path, .{ .write = true }) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = !platform.isReadOnly(path) });
}

// a packed path is writable where its copy would go: the nearest directory
// above it that the disk holds
fn writableAncestor(path: []const u8) bool {
    var dir = std.fs.path.dirname(path) orelse ".";
    while (true) {
        std.Io.Dir.cwd().access(platform.io, dir, .{ .write = true }) catch |err| {
            if (err != error.FileNotFound) return false;
            dir = std.fs.path.dirname(dir) orelse return false;
            continue;
        };
        return !platform.isReadOnly(dir);
    }
}

fn native_is_executable(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const spelled = try strArg(ctx, args, "is_executable", 0, "filename", false);
    if (!usablePath(spelled)) return NativeResult.scalar(.{ .bool = false });
    const path = spelled;
    if (platform.is_windows) {
        std.Io.Dir.cwd().access(platform.io, path, .{}) catch return NativeResult.scalar(.{ .bool = false });
        const ext = std.fs.path.extension(path);
        inline for (.{ ".exe", ".bat", ".cmd", ".com" }) |e| if (std.ascii.eqlIgnoreCase(ext, e)) return NativeResult.scalar(.{ .bool = true });
        return NativeResult.scalar(.{ .bool = false });
    }
    sys.access(path, std.posix.X_OK) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

// what stat() reports for a path served by a stream wrapper; plain files
// keep the full struct stat path in native_stat
const WrapperStat = struct {
    dev: i64 = 0,
    ino: i64 = 0,
    mode: i64,
    nlink: i64 = 1,
    uid: i64 = 0,
    gid: i64 = 0,
    rdev: i64 = -1,
    size: i64,
    atime: i64,
    mtime: i64,
    ctime: i64,
    blksize: i64 = -1,
    blocks: i64 = -1,
};

fn statField(arr: *PhpArray, comptime name: []const u8, index: i64) i64 {
    const named = arr.get(.{ .string = Value.String.borrowed(name) });
    if (named == .int) return named.int;
    const positional = arr.get(.{ .int = index });
    return if (positional == .int) positional.int else 0;
}

// the stat of a path behind a user wrapper, phar://, or compress.zlib://;
// null when the path does not use one, `missing` when it does not exist
const StatLookup = union(enum) { not_wrapped, missing, found: WrapperStat };

// packed files are read-only, their writes going to a copy on disk
fn packedStat(hit: bundle.Hit) WrapperStat {
    return switch (hit) {
        .file => |entry| .{ .mode = 0o100444, .size = @intCast(entry.source.len), .atime = entry.mtime, .mtime = entry.mtime, .ctime = entry.mtime },
        .dir => .{ .mode = 0o040555, .size = 0, .atime = 0, .mtime = 0, .ctime = 0 },
    };
}

fn statWrapped(ctx: *NativeContext, path: []const u8) RuntimeError!StatLookup {
    if (bundle.find(path)) |hit| return .{ .found = packedStat(hit) };
    if (userWrapperFor(ctx.vm, path)) |class_name| {
        const arr = (try dispatchUserStat(ctx, class_name, path, 0)) orelse return .missing;
        return .{ .found = .{
            .dev = statField(arr, "dev", 0),
            .ino = statField(arr, "ino", 1),
            .mode = statField(arr, "mode", 2),
            .nlink = statField(arr, "nlink", 3),
            .uid = statField(arr, "uid", 4),
            .gid = statField(arr, "gid", 5),
            .rdev = statField(arr, "rdev", 6),
            .size = statField(arr, "size", 7),
            .atime = statField(arr, "atime", 8),
            .mtime = statField(arr, "mtime", 9),
            .ctime = statField(arr, "ctime", 10),
            .blksize = statField(arr, "blksize", 11),
            .blocks = statField(arr, "blocks", 12),
        } };
    }
    if (std.mem.startsWith(u8, path, "phar://")) {
        const r = resolvePharPathWithCtx(path, ctx) orelse return .missing;
        const archive = platform.statPath(r.archive_path) catch return .missing;
        const archive_mtime: i64 = @intCast(@divFloor(archive.mtime.nanoseconds, 1_000_000_000));
        const dir = WrapperStat{ .mode = 0o040555, .size = 0, .atime = archive_mtime, .mtime = archive_mtime, .ctime = archive_mtime };
        if (r.internal_path.len == 0) return .{ .found = dir };
        var loaded = loadPhar(ctx.allocator, r.archive_path) catch return .missing;
        defer freePhar(ctx.allocator, &loaded);
        const normalized = normalizePharInternalPath(ctx.allocator, r.internal_path) catch return .missing;
        defer ctx.allocator.free(normalized);
        if (loaded.parsed.lookup(normalized)) |entry| {
            const t: i64 = entry.timestamp;
            // php reports entries without write bits under its default phar.readonly
            return .{ .found = .{ .mode = 0o100000 | @as(i64, entry.flags & 0o555), .size = entry.uncompressed_size, .atime = t, .mtime = t, .ctime = t } };
        }
        if (loaded.parsed.isDir(normalized)) return .{ .found = dir };
        return .missing;
    }
    if (std.mem.startsWith(u8, path, ZLIB_PREFIX)) {
        const st = platform.statPath(path[ZLIB_PREFIX.len..]) catch return .missing;
        const sec = struct {
            fn of(ts: std.Io.Timestamp) i64 {
                return @intCast(@divFloor(ts.nanoseconds, 1_000_000_000));
            }
        }.of;
        return .{ .found = .{ .mode = 0o100644, .size = @intCast(st.size), .atime = sec(st.atime orelse st.mtime), .mtime = sec(st.mtime), .ctime = sec(st.ctime) } };
    }
    return .not_wrapped;
}

fn fromSysStat(st: sys.Stat) WrapperStat {
    return .{
        .dev = @bitCast(st.dev),
        .ino = @bitCast(st.ino),
        .mode = st.mode,
        .nlink = @bitCast(st.nlink),
        .uid = st.uid,
        .gid = st.gid,
        .rdev = @bitCast(st.rdev),
        .size = st.size,
        .atime = st.atime,
        .mtime = st.mtime,
        .ctime = st.ctime,
        .blksize = st.blksize,
        .blocks = st.blocks,
    };
}

// the stat of a plain path; lstat when link is set. windows reports no
// owner, inode, or block accounting
fn plainStat(path: []const u8, link: bool) ?WrapperStat {
    if (platform.is_windows) {
        const st = platform.statPath(path) catch return null;
        const sec = struct {
            fn of(ts: std.Io.Timestamp) i64 {
                return @intCast(@divFloor(ts.nanoseconds, 1_000_000_000));
            }
        }.of;
        return .{ .mode = platform.modeOf(st), .size = @intCast(st.size), .rdev = 0, .atime = sec(st.atime orelse st.mtime), .mtime = sec(st.mtime), .ctime = sec(st.ctime) };
    } else {
        return fromSysStat((if (link) sys.lstat(path) else sys.stat(path)) catch return null);
    }
}

// php_stat: the stat of a path through whichever wrapper serves it, or null
// with php's "stat failed" warning (an empty name fails quietly)
fn phpStat(ctx: *NativeContext, spelled: []const u8, comptime fn_name: []const u8, comptime link: bool) RuntimeError!?WrapperStat {
    if (spelled.len == 0) return null;
    if (std.mem.indexOfScalar(u8, spelled, 0) != null) {
        try warn(ctx, fn_name ++ "(): Filename contains null byte", .{});
        return null;
    }
    var os_buf: [std.fs.max_path_bytes]u8 = undefined;
    var path = bundle.osPath(&os_buf, spelled);
    if (std.ascii.startsWithIgnoreCase(path, "file://")) path = path[7..];
    const found: ?WrapperStat = switch (try statWrapped(ctx, path)) {
        .found => |st| st,
        .missing => null,
        .not_wrapped => plainStat(path, link),
    };
    if (found == null) try warn(ctx, fn_name ++ "(): " ++ (if (link) "Lstat" else "stat") ++ " failed for {s}", .{spelled});
    return found;
}

const StatField = enum { size, atime, mtime, ctime, ino, mode, uid, gid };

// filesize, fileinode, fileperms and the rest: one field of the path's stat
fn statOne(ctx: *NativeContext, args: []const Value, comptime field: StatField, comptime fn_name: []const u8) RuntimeError!NativeResult {
    const st = (try phpStat(ctx, try strArg(ctx, args, fn_name, 0, "filename", false), fn_name, false)) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @field(st, @tagName(field)) });
}

fn native_filesize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return statOne(ctx, args, .size, "filesize");
}

fn native_filemtime(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return statOne(ctx, args, .mtime, "filemtime");
}

fn native_fileatime(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return statOne(ctx, args, .atime, "fileatime");
}

fn native_filectime(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return statOne(ctx, args, .ctime, "filectime");
}

fn native_fileinode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return statOne(ctx, args, .ino, "fileinode");
}

fn native_filetype(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const st = (try phpStat(ctx, try strArg(ctx, args, "filetype", 0, "filename", false), "filetype", true)) orelse return NativeResult.scalar(.{ .bool = false });
    const name: []const u8 = switch (st.mode & 0o170000) {
        0o120000 => "link",
        0o010000 => "fifo",
        0o020000 => "char",
        0o040000 => "dir",
        0o060000 => "block",
        0o100000 => "file",
        0o140000 => "socket",
        else => {
            try notice(ctx, "filetype(): Unknown file type ({d})", .{st.mode & 0o170000});
            return NativeResult.literal("unknown");
        },
    };
    return .{ .value = .{ .string = Value.String.borrowed(name) } };
}

// read file into array of lines

fn native_file(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const filename = try strArg(ctx, args, "file", 0, "filename", true);
    const flags = try intArg(ctx, args, "file", 1, "flags", 0);
    // FILE_USE_INCLUDE_PATH | FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES | FILE_NO_DEFAULT_CONTEXT
    if (flags & ~@as(i64, 23) != 0) return throwValueError(ctx, "file(): Argument #2 ($flags) must be a valid flag value", .{});
    try useContext(ctx, args, 2);
    const path = try includePathLookup(ctx, filename, (flags & FILE_USE_INCLUDE_PATH) != 0);
    const content = (try readPathAs(ctx, path, "file")) orelse return NativeResult.scalar(.{ .bool = false });
    defer content.release();
    transientStreams(ctx, 1);
    const ignore_newlines = (flags & FILE_IGNORE_NEW_LINES) != 0;
    // FILE_SKIP_EMPTY_LINES only takes effect together with FILE_IGNORE_NEW_LINES
    const skip_empty = (flags & FILE_SKIP_EMPTY_LINES) != 0 and ignore_newlines;

    const result = try ctx.createArray();
    var lines = std.mem.splitScalar(u8, content.bytes(), '\n');
    while (lines.next()) |line| {
        const last = lines.index == null;
        if (last and line.len == 0) break;
        if (!ignore_newlines) {
            try appendOwnedString(ctx, result, if (last) line else line.ptr[0 .. line.len + 1]);
            continue;
        }
        const text = if (!last and std.mem.endsWith(u8, line, "\r")) line[0 .. line.len - 1] else line;
        if (skip_empty and text.len == 0) continue;
        try appendOwnedString(ctx, result, text);
    }
    return NativeResult.borrowed(.{ .array = result });
}

fn native_readfile(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const filename = try strArg(ctx, args, "readfile", 0, "filename", true);
    try useContext(ctx, args, 2);
    const path = try includePathLookup(ctx, filename, args.len > 1 and args[1].isTruthy());
    const content = (try readPathAs(ctx, path, "readfile")) orelse return NativeResult.scalar(.{ .bool = false });
    defer content.release();
    transientStreams(ctx, 1);
    try ctx.vm.output.appendSlice(ctx.allocator, content.bytes());
    return NativeResult.scalar(.{ .int = @intCast(content.bytes().len) });
}

const FILE_USE_INCLUDE_PATH: i64 = 1;
const FILE_IGNORE_NEW_LINES: i64 = 2;
const FILE_SKIP_EMPTY_LINES: i64 = 4;

// FILE_USE_INCLUDE_PATH: a plain name is looked up the way include looks it
// up, and one include cannot find is opened as given
pub fn includePathLookup(ctx: *NativeContext, path: []const u8, use: bool) RuntimeError![]const u8 {
    if (!use or includes.hasScheme(path)) return path;
    return (try includes.resolve(ctx.vm, path)) orelse path;
}

// file handle operations (fopen/fclose/fread/fwrite/fgets/feof/fseek/ftell)

fn native_gzopen(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // gzopen($path, $mode) opens a gzipped file with transparent compression.
    // route through fopen with the compress.zlib stream wrapper so a single
    // backend handles read/write, seek, eof, etc
    if (args.len < 2 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const path = args[0].string.bytes();
    if (std.mem.startsWith(u8, path, "compress.zlib://")) {
        return native_fopen(ctx, args);
    }
    const wrapped = try std.fmt.allocPrint(ctx.allocator, "compress.zlib://{s}", .{path});
    defer ctx.allocator.free(wrapped);
    var new_args: [4]Value = undefined;
    new_args[0] = .{ .string = Value.String.borrowed(wrapped) };
    var i: usize = 1;
    while (i < args.len and i < new_args.len) : (i += 1) new_args[i] = args[i];
    return native_fopen(ctx, new_args[0..i]);
}

fn appendOwnedString(ctx: *NativeContext, arr: *PhpArray, bytes: []const u8) !void {
    const s = try Value.String.create(ctx.allocator, bytes);
    defer s.release();
    try arr.append(ctx.allocator, .{ .string = s });
}

fn native_gzfile(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // gzfile($path) reads the whole gzipped file and returns an array of lines
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const path = args[0].string.bytes();
    const wrapped = try std.fmt.allocPrint(ctx.allocator, "compress.zlib://{s}", .{path});
    defer ctx.allocator.free(wrapped);
    var fgc_args = [_]Value{.{ .string = Value.String.borrowed(wrapped) }};
    const contents_val = (try native_file_get_contents(ctx, &fgc_args)).value;
    if (contents_val != .string) return NativeResult.scalar(.{ .bool = false });
    defer contents_val.string.release();
    const arr = try ctx.createArray();
    const contents = contents_val.string.bytes();
    var start: usize = 0;
    var pos: usize = 0;
    while (pos < contents.len) : (pos += 1) {
        if (contents[pos] == '\n') {
            try appendOwnedString(ctx, arr, contents[start .. pos + 1]);
            start = pos + 1;
        }
    }
    if (start < contents.len) try appendOwnedString(ctx, arr, contents[start..]);
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_fopen(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const given_path = if (args[0] == .string) args[0].string.bytes() else if (args[0] == .object and ctx.vm.hasMethod(args[0].object.class_name, "__toString")) try ctx.vm.objectToString(args[0].object) else return NativeResult.scalar(.{ .bool = false });
    const mode = args[1].string.bytes();
    try useContext(ctx, args, 3);
    const reading = mode.len > 0 and mode[0] == 'r' and std.mem.indexOfScalar(u8, mode, '+') == null;
    const path = try includePathLookup(ctx, given_path, reading and args.len > 2 and args[2].isTruthy());

    if (userWrapperFor(ctx.vm, path)) |class_name| {
        return NativeResult.borrowed((try dispatchUserOpen(ctx, class_name, path, mode)) orelse Value{ .bool = false });
    }
    if (extractScheme(path)) |s| {
        if (isBuiltinWrapper(s) and isWrapperUnregistered(ctx.vm, s)) return NativeResult.scalar(.{ .bool = false });
    }

    if (std.mem.eql(u8, path, "php://stdout") or std.mem.eql(u8, path, "php://output")) {
        const obj = try ctx.createResource("FileHandle");
        try obj.set(ctx.allocator, "__fd", .{ .int = 1 });
        try obj.set(ctx.allocator, "__open", .{ .bool = true });
        try obj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed("w") });
        return NativeResult.borrowed(.{ .resource = obj });
    }
    if (std.mem.eql(u8, path, "php://stderr")) {
        const obj = try ctx.createResource("FileHandle");
        try obj.set(ctx.allocator, "__fd", .{ .int = 2 });
        try obj.set(ctx.allocator, "__open", .{ .bool = true });
        try obj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed("w") });
        return NativeResult.borrowed(.{ .resource = obj });
    }
    if (std.mem.eql(u8, path, "php://stdin")) {
        const obj = try ctx.createResource("FileHandle");
        try obj.set(ctx.allocator, "__fd", .{ .int = 0 });
        try obj.set(ctx.allocator, "__open", .{ .bool = true });
        try obj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed("r") });
        return NativeResult.borrowed(.{ .resource = obj });
    }
    if (std.mem.eql(u8, path, "php://input")) {
        const body_val = ctx.vm.request_vars.get("__raw_body");
        const body: []const u8 = if (body_val != null and body_val.? == .string) body_val.?.string.bytes() else "";
        const obj = try ctx.createResource("FileHandle");
        try obj.set(ctx.allocator, "__buffer", .{ .string = Value.String.borrowed(body) });
        try obj.set(ctx.allocator, "__pos", .{ .int = 0 });
        try obj.set(ctx.allocator, "__open", .{ .bool = true });
        try obj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed("r") });
        return NativeResult.borrowed(.{ .resource = obj });
    }
    if (std.mem.startsWith(u8, path, "data:")) {
        const payload = parseDataUri(ctx.allocator, path) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            try warn(ctx, "fopen({s}): Failed to open stream: {s}", .{ path, dataUriErrorText(err) });
            return NativeResult.scalar(.{ .bool = false });
        };
        const obj = try ctx.createResource("FileHandle");
        try setAdoptedBuffer(ctx, obj, payload);
        try obj.set(ctx.allocator, "__pos", .{ .int = 0 });
        try obj.set(ctx.allocator, "__open", .{ .bool = true });
        try obj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed("r") });
        return NativeResult.borrowed(.{ .resource = obj });
    }
    if (std.mem.startsWith(u8, path, "phar://")) {
        const r = resolvePharPathWithCtx(path, ctx) orelse return NativeResult.scalar(.{ .bool = false });
        const payload = (readPharEntry(ctx.allocator, r.archive_path, r.internal_path) catch return NativeResult.scalar(.{ .bool = false })) orelse return NativeResult.scalar(.{ .bool = false });
        const obj = try ctx.createResource("FileHandle");
        try setAdoptedBuffer(ctx, obj, payload);
        try obj.set(ctx.allocator, "__pos", .{ .int = 0 });
        try obj.set(ctx.allocator, "__open", .{ .bool = true });
        try obj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed("r") });
        return NativeResult.borrowed(.{ .resource = obj });
    }
    if (std.mem.startsWith(u8, path, ZLIB_PREFIX)) {
        const is_write = mode.len >= 1 and (mode[0] == 'w' or mode[0] == 'a' or mode[0] == 'x');
        const obj = try ctx.createResource("FileHandle");
        try obj.set(ctx.allocator, "__open", .{ .bool = true });
        try obj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed(mode) });
        try obj.setCopiedString(ctx.allocator, "__zlib_path", path);
        if (is_write) {
            try obj.set(ctx.allocator, "__zlib_writing", .{ .bool = true });
            try obj.set(ctx.allocator, "__buffer", .{ .string = Value.String.borrowed("") });
            try obj.set(ctx.allocator, "__pos", .{ .int = 0 });
        } else {
            const decoded = readZlibFile(ctx.allocator, path) catch {
                obj.set(ctx.allocator, "__open", .{ .bool = false }) catch {};
                return NativeResult.scalar(.{ .bool = false });
            };
            try setAdoptedBuffer(ctx, obj, decoded);
            try obj.set(ctx.allocator, "__pos", .{ .int = 0 });
        }
        return NativeResult.borrowed(.{ .resource = obj });
    }

    const is_memory_stream = std.mem.startsWith(u8, path, "php://temp") or std.mem.startsWith(u8, path, "php://memory");
    const file = if (is_memory_stream)
        anonymousFile() orelse return NativeResult.scalar(.{ .bool = false })
    else
        openWithMode(path, mode) catch |err| {
            const reason = errorText(err);
            const msg = std.fmt.allocPrint(ctx.allocator, "fopen({s}): Failed to open stream: {s}", .{ path, reason }) catch return NativeResult.scalar(.{ .bool = false });
            defer ctx.allocator.free(msg);
            try ctx.vm.emitWarning(msg);
            return NativeResult.scalar(.{ .bool = false });
        };

    const obj = try ctx.createResource("FileHandle");
    try obj.set(ctx.allocator, "__fd", .{ .int = platform.fdFromFile(file) });
    try obj.set(ctx.allocator, "__open", .{ .bool = true });
    try obj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed(mode) });
    try obj.setCopiedString(ctx.allocator, "__path", path);
    if (is_memory_stream) try obj.set(ctx.allocator, "__peek_eof", .{ .bool = true });
    return NativeResult.borrowed(.{ .resource = obj });
}

pub fn openWithMode(spelled: []const u8, mode: []const u8) !std.Io.File {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = paths.streamPath(&path_buf, spelled);
    if (mode.len == 0) return error.RuntimeError;
    const has_plus = mode.len > 1 and (mode[1] == '+' or (mode.len > 2 and mode[2] == '+'));
    if (mode[0] == 'r' and !has_plus) {
        if (bundle.find(path)) |hit| return switch (hit) {
            .file => |entry| packedFile(entry.source) orelse error.SystemResources,
            .dir => error.IsDir,
        };
    } else {
        if (mode[0] == 'x' and bundle.find(path) != null) return error.PathAlreadyExists;
        bundle.prepareWrite(path, if (mode[0] == 'w' or mode[0] == 'x') .create else .edit);
    }
    return switch (mode[0]) {
        'r' => std.Io.Dir.cwd().openFile(platform.io, path, .{ .mode = if (has_plus) .read_write else .read_only }),
        'w' => blk: {
            const file = std.Io.Dir.cwd().createFile(platform.io, path, .{ .truncate = true, .read = has_plus }) catch |err| break :blk err;
            break :blk file;
        },
        'a' => blk: {
            break :blk platform.openAppend(path, has_plus);
        },
        'x' => std.Io.Dir.cwd().createFile(platform.io, path, .{ .exclusive = true, .read = has_plus }),
        'c' => blk: {
            // PHP 'c'/'c+' mode: open for writing without truncating; create
            // if it doesn't exist. position is at 0 regardless of existing
            // content (so a subsequent fwrite overwrites from the start)
            const file = std.Io.Dir.cwd().openFile(platform.io, path, .{ .mode = if (has_plus) .read_write else .write_only }) catch
                std.Io.Dir.cwd().createFile(platform.io, path, .{ .read = has_plus, .truncate = false }) catch |err| break :blk err;
            break :blk file;
        },
        else => error.RuntimeError,
    };
}

fn native_fclose(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try streamArg(ctx, args, .{ .func = "fclose" });
    if (!std.mem.eql(u8, obj.class_name, "FileHandle")) return NativeResult.scalar(.{ .bool = false });
    if (fileHandleWrapper(obj)) |wrapper| {
        if (ctx.vm.hasMethod(wrapper.class_name, "stream_close")) {
            _ = try ctx.callMethod(wrapper, "stream_close", &.{});
        }
        obj.set(ctx.allocator, "__open", .{ .bool = false }) catch {};
        return NativeResult.scalar(.{ .bool = true });
    }
    // closing a proc_open pipe: close our fd and detach it from the live child so
    // proc_close's wait() (cleanupStreams) won't double-close the same fd. closing
    // the stdin pipe also signals EOF to the child. each fd is owned exactly once
    const proc_ref = obj.get("__proc_ref");
    const proc_role = obj.get("__proc_role");
    if (proc_ref == .resource and proc_role == .int) {
        if (ctx.vm.lookupProcChild(proc_ref.resource)) |pc| {
            for (pc.pipe_fds.items) |*pipe| {
                if (pipe.role == proc_role.int and pipe.fd != -1) {
                    platform.closeFd(pipe.fd);
                    pipe.fd = -1;
                    break;
                }
            }
        }
        obj.set(ctx.allocator, "__fd", .{ .int = -1 }) catch {};
        obj.set(ctx.allocator, "__open", .{ .bool = false }) catch {};
        return NativeResult.scalar(.{ .bool = true });
    }
    const popen_cmd = obj.get("__popen_cmd");
    if (popen_cmd == .string) {
        const buf_v_p = obj.get("__buffer");
        const data: []const u8 = if (buf_v_p == .string) buf_v_p.string.bytes() else "";
        if (runShellCapture(ctx.allocator, popen_cmd.string.bytes(), data)) |r| {
            ctx.allocator.free(r.stdout);
            ctx.allocator.free(r.stderr);
        } else |_| {}
        obj.set(ctx.allocator, "__open", .{ .bool = false }) catch {};
        obj.set(ctx.allocator, "__popen_cmd", .null) catch {};
        return NativeResult.scalar(.{ .bool = true });
    }
    if (isZlibWriting(obj)) {
        const path_v = obj.get("__zlib_path");
        const buf_v = obj.get("__buffer");
        if (path_v == .string and buf_v == .string) {
            writeZlibFile(ctx.allocator, path_v.string.bytes(), buf_v.string.bytes()) catch {
                obj.set(ctx.allocator, "__open", .{ .bool = false }) catch {};
                return NativeResult.scalar(.{ .bool = false });
            };
        }
        obj.set(ctx.allocator, "__open", .{ .bool = false }) catch {};
        return NativeResult.scalar(.{ .bool = true });
    }
    if (getFileHandle(obj)) |file| {
        // never close stdin/stdout/stderr - they're shared with the host process
        if (isNetStream(obj)) {
            platform.closeSocket(obj.get("__fd").int);
        } else if (!platform.isStdio(file)) {
            platform.closeFile(file, obj.get("__fd").int);
        }
    }
    obj.set(ctx.allocator, "__open", .{ .bool = false }) catch {};
    return NativeResult.scalar(.{ .bool = true });
}

fn isZlibWriting(obj: *PhpObject) bool {
    const v = obj.get("__zlib_writing");
    return v == .bool and v.bool;
}

fn native_fpassthru(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try streamArg(ctx, args, .{ .func = "fpassthru" });
    var total: i64 = 0;
    var buf: [read_chunk]u8 = undefined;
    while (true) {
        // a stream that cannot be read at all passes -1 through
        const n = (try streamReadInto(ctx, obj, &buf)) orelse return NativeResult.scalar(.{ .int = if (total == 0) -1 else total });
        if (n == 0) break;
        try ctx.vm.output.appendSlice(ctx.allocator, buf[0..n]);
        total += @intCast(n);
    }
    return NativeResult.scalar(.{ .int = total });
}

fn native_fread(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try streamArg(ctx, args, .{ .func = "fread" });
    if (args.len < 2 or args[1] != .int) return NativeResult.scalar(.{ .bool = false });
    if (args[1].int <= 0) {
        try ctx.vm.setPendingException("ValueError", "fread(): Argument #2 ($length) must be greater than 0");
        return error.RuntimeError;
    }
    const buf = try ctx.allocator.alloc(u8, @intCast(args[1].int));
    const n = (try streamReadInto(ctx, obj, buf)) orelse {
        ctx.allocator.free(buf);
        return NativeResult.scalar(.{ .bool = false });
    };
    if (n == 0) {
        ctx.allocator.free(buf);
        return NativeResult.literal("");
    }
    const exact = ctx.allocator.realloc(buf, n) catch {
        ctx.allocator.free(buf);
        return error.OutOfMemory;
    };
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, exact));
}

// one read into dest: the byte count (0 at eof or when a non-blocking stream
// has nothing yet), or null when the stream cannot be read
fn isRegularFd(file: std.Io.File) bool {
    const stat = file.stat(platform.io) catch return false;
    return stat.kind == .file;
}

pub fn streamReadInto(ctx: *NativeContext, obj: *PhpObject, dest: []u8) RuntimeError!?usize {
    if (fileHandleWrapper(obj)) |wrapper| {
        const result = try ctx.callMethod(wrapper, "stream_read", &[_]Value{.{ .int = @intCast(dest.len) }});
        if (result != .string) return 0;
        const n = @min(result.string.bytes().len, dest.len);
        @memcpy(dest[0..n], result.string.bytes()[0..n]);
        return n;
    }
    if (getBufferBacking(obj)) |buffer| {
        const pos = getBufferPos(obj);
        if (pos >= buffer.len) return 0;
        const n = @min(dest.len, buffer.len - pos);
        @memcpy(dest[0..n], buffer[pos..][0..n]);
        setBufferPos(obj, pos + n);
        return n;
    }
    const io = streamIo(obj) orelse return null;
    const n = io.read(dest) catch |err| {
        // non-blocking stream with nothing buffered yet reads as "" in php, not a hard failure
        if (err == error.WouldBlock) return 0;
        if (!io.socket) try ioFailure(ctx, "Read", @max(read_chunk, dest.len), err);
        return null;
    };
    // a short read ends a regular file; a pipe or socket has only reached
    // the end when the read comes back empty
    if (n == 0 or (n < dest.len and !io.socket and isRegularFd(io.file))) try obj.set(ctx.allocator, "__eof", .{ .bool = true });
    return n;
}

fn native_fwrite(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try streamArg(ctx, args, .{ .func = "fwrite" });
    var data = try @import("strings.zig").stringParam(ctx, "fwrite", args, 1, "data");
    if (args.len >= 3 and args[2] != .null) {
        // a length of zero or less writes nothing
        const lim = try intArg(ctx, args, "fwrite", 2, "length", 0);
        if (lim <= 0) return NativeResult.scalar(.{ .int = 0 });
        if (@as(u64, @intCast(lim)) < data.len) data = data[0..@intCast(lim)];
    }
    if (data.len == 0) return NativeResult.scalar(.{ .int = 0 });
    const written = (try streamWrite(ctx, obj, data)) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(written) });
}

// one write of data: the byte count, or null when the stream cannot be written
pub fn streamWrite(ctx: *NativeContext, obj: *PhpObject, data: []const u8) RuntimeError!?usize {
    if (fileHandleWrapper(obj)) |wrapper| {
        const result = try ctx.callMethod(wrapper, "stream_write", &[_]Value{.{ .string = Value.String.borrowed(data) }});
        return if (result == .int and result.int >= 0) @intCast(result.int) else 0;
    }
    if (isZlibWriting(obj) or obj.get("__popen_cmd") == .string) {
        const cur = obj.get("__buffer");
        const cur_str: []const u8 = if (cur == .string) cur.string.bytes() else "";
        const combined = try ctx.allocator.alloc(u8, cur_str.len + data.len);
        @memcpy(combined[0..cur_str.len], cur_str);
        @memcpy(combined[cur_str.len..], data);
        try setAdoptedBuffer(ctx, obj, combined);
        return data.len;
    }
    const io = streamIo(obj) orelse return null;
    const file = io.file;
    const mode_v = obj.get("__mode");
    // php://memory and php://temp opened without w, a or + are read-only
    if (obj.get("__peek_eof") == .bool and mode_v == .string and std.mem.indexOfAny(u8, mode_v.string.bytes(), "wa+") == null) return null;
    // 'a' / 'a+' modes: writes always append, regardless of where the read cursor is
    if (mode_v == .string and mode_v.string.bytes().len > 0 and mode_v.string.bytes()[0] == 'a') {
        platform.seekFromEnd(file, 0) catch {};
    }
    // route php://stdout and php://output through the VM output buffer so the order
    // matches echo. for php://stderr, flush the buffer first so anything echo'd before
    // this call lands before our stderr write
    if (platform.isStdout(file)) {
        try ctx.vm.output.appendSlice(ctx.allocator, data);
        return data.len;
    }
    if (platform.isStderr(file)) ctx.vm.flushOutputToStdout();
    // a blocking stream takes all of it; a non-blocking one what fits now
    var written: usize = 0;
    while (written < data.len) {
        const n = io.write(data[written..]) catch |err| {
            if (err == error.WouldBlock) break;
            if (written > 0) break;
            if (!io.socket) try ioFailure(ctx, "Write", data.len, err);
            return null;
        };
        if (n == 0) break;
        written += n;
    }
    return written;
}

fn native_fgets(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try streamArg(ctx, args, .{ .func = "fgets" });
    // PHP: fgets($f, length) reads up to length-1 bytes
    const have_length = args.len >= 2 and args[1] != .null;
    const length = if (have_length) try intArg(ctx, args, "fgets", 1, "length", 0) else 0;
    if (have_length and length <= 0) return throwValueError(ctx, "fgets(): Argument #2 ($length) must be greater than 0", .{});
    // without a length the whole line comes back, however long
    const max_len: usize = if (have_length) @intCast(length - 1) else std.math.maxInt(usize);
    if (max_len == 0) return NativeResult.scalar(.{ .bool = false });
    const line = (try readLine(ctx, obj, max_len)) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.takeString(line);
}

// php_stream_get_line as a string value, or null at eof
pub fn readLine(ctx: *NativeContext, obj: *PhpObject, max_len: usize) RuntimeError!?Value.String {
    const line = (try streamReadLine(ctx, obj, max_len)) orelse return null;
    return try Value.String.adopt(ctx.allocator, line);
}

// the next line of a stream through its newline, at most max_len bytes,
// owned by the caller; null at the end of the stream. a failed read warns
// with php's errno notice, naming the calling function
pub fn streamReadLine(ctx: *NativeContext, obj: *PhpObject, max_len: usize) RuntimeError!?[]u8 {
    if (getBufferBacking(obj)) |buffer| {
        const pos = getBufferPos(obj);
        if (pos >= buffer.len) return null;
        var end = pos;
        while (end < buffer.len and end - pos < max_len) {
            const c = buffer[end];
            end += 1;
            if (c == '\n') break;
        }
        const slice = try ctx.allocator.dupe(u8, buffer[pos..end]);
        setBufferPos(obj, end);
        return slice;
    }
    const io = streamIo(obj) orelse return null;

    var buf = std.ArrayListUnmanaged(u8).empty;
    errdefer buf.deinit(ctx.allocator);
    var byte: [1]u8 = undefined;
    var hit_eof = false;
    while (buf.items.len < max_len) {
        const n = io.read(&byte) catch |err| {
            if (!io.socket and buf.items.len == 0) try ioFailure(ctx, "Read", read_chunk, err);
            break;
        };
        if (n == 0) {
            hit_eof = true;
            break;
        }
        try buf.append(ctx.allocator, byte[0]);
        if (byte[0] == '\n') break;
    }
    if (hit_eof) try obj.set(ctx.allocator, "__eof", .{ .bool = true });
    if (buf.items.len == 0) {
        buf.deinit(ctx.allocator);
        return null;
    }
    return try buf.toOwnedSlice(ctx.allocator);
}

fn native_stream_get_line(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // stream_get_line(handle, length[, ending]) - reads up to length bytes,
    // stopping when `ending` is encountered (consumed but not returned) or EOF
    const obj = try streamArg(ctx, args, .{ .func = "stream_get_line" });
    if (args.len < 2) return NativeResult.scalar(.{ .bool = false });
    const max_len: usize = @intCast(@max(Value.toInt(args[1]), 0));
    const ending = if (args.len >= 3 and args[2] == .string) args[2].string.bytes() else "";
    const cap = if (max_len == 0) std.math.maxInt(usize) else max_len;

    if (getBufferBacking(obj)) |buffer| {
        const pos = getBufferPos(obj);
        if (pos >= buffer.len) return NativeResult.scalar(.{ .bool = false });
        var end = pos;
        var hit_delim_at: ?usize = null;
        while (end < buffer.len and end - pos < cap) {
            if (ending.len > 0 and end + ending.len <= buffer.len and std.mem.eql(u8, buffer[end .. end + ending.len], ending)) {
                hit_delim_at = end;
                break;
            }
            end += 1;
        }
        const out_end = hit_delim_at orelse end;
        const slice = try ctx.allocator.dupe(u8, buffer[pos..out_end]);
        const new_pos = if (hit_delim_at) |d| d + ending.len else end;
        setBufferPos(obj, new_pos);
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, slice));
    }
    const io = streamIo(obj) orelse return NativeResult.scalar(.{ .bool = false });

    var buf = std.ArrayListUnmanaged(u8).empty;
    var byte: [1]u8 = undefined;
    var matched: usize = 0;
    while (buf.items.len + matched < cap) {
        const n = io.read(&byte) catch break;
        if (n == 0) {
            try obj.set(ctx.allocator, "__eof", .{ .bool = true });
            break;
        }
        if (ending.len > 0 and byte[0] == ending[matched]) {
            matched += 1;
            if (matched == ending.len) break;
        } else {
            if (matched > 0) {
                try buf.appendSlice(ctx.allocator, ending[0..matched]);
                matched = 0;
                if (byte[0] == ending[0] and ending.len > 0) {
                    matched = 1;
                    continue;
                }
            }
            try buf.append(ctx.allocator, byte[0]);
        }
    }
    if (buf.items.len == 0 and matched == 0) return NativeResult.scalar(.{ .bool = false });
    const result = try buf.toOwnedSlice(ctx.allocator);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result));
}

fn native_fgetc(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try streamArg(ctx, args, .{ .func = "fgetc" });
    const io = streamIo(obj) orelse return NativeResult.scalar(.{ .bool = false });
    var byte: [1]u8 = undefined;
    const n = io.read(&byte) catch |err| {
        if (!io.socket) try ioFailure(ctx, "Read", read_chunk, err);
        return NativeResult.scalar(.{ .bool = false });
    };
    if (n == 0) {
        try obj.set(ctx.allocator, "__eof", .{ .bool = true });
        return NativeResult.scalar(.{ .bool = false });
    }
    const result = try ctx.allocator.dupe(u8, byte[0..1]);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result));
}

fn native_feof(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try streamArg(ctx, args, .{ .func = "feof" });
    if (fileHandleWrapper(obj)) |wrapper| {
        if (!ctx.vm.hasMethod(wrapper.class_name, "stream_eof")) return NativeResult.scalar(.{ .bool = false });
        const result = try ctx.callMethod(wrapper, "stream_eof", &.{});
        return NativeResult.scalar(.{ .bool = result.isTruthy() });
    }
    if (getBufferBacking(obj)) |buffer| {
        return NativeResult.scalar(.{ .bool = getBufferPos(obj) >= buffer.len });
    }
    const io = streamIo(obj) orelse return NativeResult.scalar(.{ .bool = true });
    // memory/temp streams use peek-ahead semantics (PHP behavior for those streams)
    const peek_eof = obj.get("__peek_eof");
    if (peek_eof == .bool and peek_eof.bool) {
        var byte: [1]u8 = undefined;
        const n = io.read(&byte) catch return NativeResult.scalar(.{ .bool = true });
        if (n == 0) return NativeResult.scalar(.{ .bool = true });
        platform.seekBy(io.file, -1) catch {};
        return NativeResult.scalar(.{ .bool = false });
    }
    // PHP file semantics: feof becomes true only after a read attempt returned 0
    const eof = obj.get("__eof");
    return NativeResult.scalar(.{ .bool = eof == .bool and eof.bool });
}

fn native_fseek(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try streamArg(ctx, args, .{ .func = "fseek" });
    if (args.len < 2 or args[1] != .int) return NativeResult.scalar(.{ .int = -1 });
    const offset = args[1].int;
    // SEEK_SET, SEEK_CUR, SEEK_END; lseek(2) refuses any other whence
    const whence_arg: i64 = if (args.len >= 3) Value.toInt(args[2]) else 0;
    if (whence_arg < 0 or whence_arg > 2) return NativeResult.scalar(.{ .int = -1 });
    const whence: u2 = @intCast(whence_arg);
    if (fileHandleWrapper(obj)) |wrapper| {
        if (!ctx.vm.hasMethod(wrapper.class_name, "stream_seek")) return NativeResult.scalar(.{ .int = -1 });
        const result = try ctx.callMethod(wrapper, "stream_seek", &[_]Value{ .{ .int = offset }, .{ .int = whence } });
        return NativeResult.scalar(.{ .int = if (result.isTruthy()) 0 else -1 });
    }
    if (getBufferBacking(obj)) |buffer| {
        const new_pos: i64 = switch (whence) {
            0 => offset,
            1 => @as(i64, @intCast(getBufferPos(obj))) + offset,
            2 => @as(i64, @intCast(buffer.len)) + offset,
            else => return NativeResult.scalar(.{ .int = -1 }),
        };
        if (new_pos < 0) return NativeResult.scalar(.{ .int = -1 });
        setBufferPos(obj, @intCast(new_pos));
        return NativeResult.scalar(.{ .int = 0 });
    }
    const file = getFileHandle(obj) orelse return NativeResult.scalar(.{ .int = -1 });
    switch (whence) {
        0 => platform.seekTo(file, @intCast(offset)) catch return NativeResult.scalar(.{ .int = -1 }),
        1 => platform.seekBy(file, offset) catch return NativeResult.scalar(.{ .int = -1 }),
        2 => platform.seekFromEnd(file, offset) catch return NativeResult.scalar(.{ .int = -1 }),
        else => return NativeResult.scalar(.{ .int = -1 }),
    }
    try obj.set(ctx.allocator, "__eof", .{ .bool = false });
    return NativeResult.scalar(.{ .int = 0 });
}

fn native_ftell(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try streamArg(ctx, args, .{ .func = "ftell" });
    if (fileHandleWrapper(obj)) |wrapper| {
        if (!ctx.vm.hasMethod(wrapper.class_name, "stream_tell")) return NativeResult.scalar(.{ .bool = false });
        const result = try ctx.callMethod(wrapper, "stream_tell", &.{});
        if (result == .int) return NativeResult.share(result);
        return NativeResult.scalar(.{ .bool = false });
    }
    if (getBufferBacking(obj) != null) {
        return NativeResult.scalar(.{ .int = @intCast(getBufferPos(obj)) });
    }
    const file = getFileHandle(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const pos = platform.getPos(file) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(pos) });
}

fn native_rewind(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try streamArg(ctx, args, .{ .func = "rewind" });
    if (fileHandleWrapper(obj)) |wrapper| {
        if (!ctx.vm.hasMethod(wrapper.class_name, "stream_seek")) return NativeResult.scalar(.{ .bool = false });
        const result = try ctx.callMethod(wrapper, "stream_seek", &[_]Value{ .{ .int = 0 }, .{ .int = 0 } });
        return NativeResult.scalar(.{ .bool = result.isTruthy() });
    }
    if (getBufferBacking(obj) != null) {
        setBufferPos(obj, 0);
        return NativeResult.scalar(.{ .bool = true });
    }
    const file = getFileHandle(obj) orelse return NativeResult.scalar(.{ .bool = false });
    platform.seekTo(file, 0) catch return NativeResult.scalar(.{ .bool = false });
    try obj.set(ctx.allocator, "__eof", .{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn native_fflush(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try streamArg(ctx, args, .{ .func = "fflush" });
    // zig files are unbuffered at our level, this is a no-op
    _ = getFileHandle(obj) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn native_ftruncate(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try streamArg(ctx, args, .{ .func = "ftruncate" });
    const size_arg = try intArg(ctx, args, "ftruncate", 1, "size", 0);
    if (size_arg < 0) return throwValueError(ctx, "ftruncate(): Argument #2 ($size) must be greater than or equal to 0", .{});
    const file = getFileHandle(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const size: u64 = @intCast(size_arg);
    file.setLength(platform.io, size) catch return NativeResult.scalar(.{ .bool = false });
    // for php://memory / php://temp, snap the cursor to the new end rather than
    // leaving it past EOF where subsequent writes would create null-padded holes
    const path = obj.get("__path");
    if (path == .string and (std.mem.startsWith(u8, path.string.bytes(), "php://memory") or std.mem.startsWith(u8, path.string.bytes(), "php://temp"))) {
        const cur = platform.getPos(file) catch 0;
        if (cur > size) platform.seekTo(file, size) catch {};
    }
    return NativeResult.scalar(.{ .bool = true });
}

// php_flock_common: the operation must name LOCK_SH, LOCK_EX, or LOCK_UN
// (LOCK_NB may be or'ed in), and $would_block starts out 0. returns the
// operation's lock kind (1 shared, 2 exclusive, 3 unlock) and whether it
// must not block
pub fn flockOperation(ctx: *NativeContext, args: []const Value) RuntimeError!struct { kind: i64, non_block: bool } {
    const operation = try intArg(ctx, args, "flock", 1, "operation", 0);
    const kind = operation & 3;
    if (kind < 1) return throwValueError(ctx, "flock(): Argument #2 ($operation) must be one of LOCK_SH, LOCK_EX, or LOCK_UN", .{});
    if (args.len >= 3) ctx.setCallerVar(2, args.len, .{ .int = 0 });
    return .{ .kind = kind, .non_block = (operation & 4) != 0 };
}

fn native_flock(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try streamArg(ctx, args, .{ .func = "flock" });
    const op = try flockOperation(ctx, args);
    const file = getFileHandle(obj) orelse return NativeResult.scalar(.{ .bool = false });
    if (getBufferBacking(obj) != null) return NativeResult.scalar(.{ .bool = false });
    // flock(2) numbers them LOCK_SH=1, LOCK_EX=2, LOCK_UN=8, LOCK_NB=4
    const os_op: i32 = @as(i32, switch (op.kind) {
        1 => 1,
        2 => 2,
        else => 8,
    }) | @as(i32, if (op.non_block) 4 else 0);
    sys.flock(file.handle, os_op) catch |err| {
        if (err == error.WouldBlock and args.len >= 3) ctx.setCallerVar(2, args.len, .{ .int = 1 });
        return NativeResult.scalar(.{ .bool = false });
    };
    return NativeResult.scalar(.{ .bool = true });
}

// memory streams and regular files seek; pipes and terminals do not
fn isSeekable(obj: *PhpObject) bool {
    if (getBufferBacking(obj) != null) return true;
    const file = getFileHandle(obj) orelse return false;
    const stat = file.stat(platform.io) catch return false;
    return stat.kind == .file;
}

fn stream_get_meta_data(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try streamArg(ctx, args, .{ .func = "stream_get_meta_data" });
    const mode_val = obj.get("__mode");
    const mode = if (mode_val == .string) mode_val.string.bytes() else "r";
    const path_val = obj.get("__path");
    const uri = if (path_val == .string) path_val.string.bytes() else "";
    // derive wrapper_type/stream_type from the URI scheme
    var wrapper_type: []const u8 = "plainfile";
    var stream_type: []const u8 = "STDIO";
    if (std.mem.indexOf(u8, uri, "://")) |colon| {
        const scheme = uri[0..colon];
        if (std.mem.eql(u8, scheme, "http") or std.mem.eql(u8, scheme, "https")) {
            wrapper_type = "http";
            stream_type = "tcp_socket/ssl";
        } else if (std.mem.eql(u8, scheme, "php")) {
            wrapper_type = "PHP";
            const rest = uri[colon + 3 ..];
            if (std.mem.startsWith(u8, rest, "memory") or std.mem.startsWith(u8, rest, "temp")) {
                stream_type = "MEMORY";
            } else if (std.mem.startsWith(u8, rest, "stdin") or std.mem.startsWith(u8, rest, "stdout") or std.mem.startsWith(u8, rest, "stderr") or std.mem.startsWith(u8, rest, "input") or std.mem.startsWith(u8, rest, "output")) {
                stream_type = "STDIO";
            } else {
                stream_type = "STDIO";
            }
        } else if (std.mem.eql(u8, scheme, "data")) {
            wrapper_type = "RFC2397";
            stream_type = "RFC2397";
        } else {
            wrapper_type = scheme;
            stream_type = scheme;
        }
    }
    // sockets have no wrapper and name their address; process pipes have
    // neither a wrapper nor a uri
    const is_socket = obj.get("__net") == .bool and obj.get("__net").bool;
    const is_pipe = obj.get("__proc_ref") != .null;
    if (is_socket) {
        const sock_type = obj.get("__sock_type");
        stream_type = if (sock_type == .string) sock_type.string.bytes() else "generic_socket";
    }
    const blocking = obj.get("__blocking");
    const eof = obj.get("__eof");
    const result = try ctx.createArray();
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("timed_out") }, .{ .bool = false });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("blocked") }, .{ .bool = !(blocking == .bool and !blocking.bool) });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("eof") }, .{ .bool = eof == .bool and eof.bool });
    if (!is_socket and !is_pipe) try result.set(ctx.allocator, .{ .string = Value.String.borrowed("wrapper_type") }, .{ .string = Value.String.borrowed(wrapper_type) });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("stream_type") }, .{ .string = Value.String.borrowed(stream_type) });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("mode") }, .{ .string = Value.String.borrowed(mode) });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("unread_bytes") }, .{ .int = 0 });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("seekable") }, .{ .bool = !is_socket and !is_pipe and isSeekable(obj) });
    if (!is_pipe and (!is_socket or uri.len > 0)) try result.set(ctx.allocator, .{ .string = Value.String.borrowed("uri") }, .{ .string = Value.String.borrowed(uri) });
    return NativeResult.borrowed(.{ .array = result });
}

const builtin_wrappers = [_][]const u8{ "https", "php", "file", "data", "http", "phar", "compress.zlib" };

const ZLIB_PREFIX = "compress.zlib://";

// gzip-decode bytes. accepts both gzip-wrapped and zlib-wrapped streams via
// auto-detection (windowBits=15+32). caller owns the returned buffer
fn zlibDecodeWindow(a: Allocator, input: []const u8, window_bits: c_int) ![]u8 {
    if (input.len == 0) return try a.alloc(u8, 0);
    var stream: zlib.z_stream = std.mem.zeroes(zlib.z_stream);
    if (zlib.inflateInit2_(&stream, window_bits, zlib.zlibVersion(), @sizeOf(zlib.z_stream)) != zlib.Z_OK) {
        return error.InflateInitFailed;
    }
    defer _ = zlib.inflateEnd(&stream);
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(a);
    stream.next_in = @constCast(input.ptr);
    stream.avail_in = @intCast(input.len);
    var chunk: [16 * 1024]u8 = undefined;
    while (true) {
        stream.next_out = &chunk;
        stream.avail_out = chunk.len;
        const rc = zlib.inflate(&stream, zlib.Z_NO_FLUSH);
        const produced = chunk.len - stream.avail_out;
        if (produced > 0) try out.appendSlice(a, chunk[0..produced]);
        if (rc == zlib.Z_STREAM_END) break;
        if (rc != zlib.Z_OK) return error.CorruptCompressedData;
        if (stream.avail_in == 0 and produced == 0) break;
    }
    return try out.toOwnedSlice(a);
}

fn zlibEncodeWindow(a: Allocator, input: []const u8, window_bits: c_int) ![]u8 {
    var stream: zlib.z_stream = std.mem.zeroes(zlib.z_stream);
    if (zlib.deflateInit2_(
        &stream,
        zlib.Z_DEFAULT_COMPRESSION,
        zlib.Z_DEFLATED,
        window_bits,
        8,
        zlib.Z_DEFAULT_STRATEGY,
        zlib.zlibVersion(),
        @sizeOf(zlib.z_stream),
    ) != zlib.Z_OK) {
        return error.DeflateInitFailed;
    }
    defer _ = zlib.deflateEnd(&stream);
    const bound = zlib.deflateBound(&stream, @intCast(input.len));
    const out = try a.alloc(u8, bound + 32);
    errdefer a.free(out);
    stream.next_in = @constCast(input.ptr);
    stream.avail_in = @intCast(input.len);
    stream.next_out = out.ptr;
    stream.avail_out = @intCast(out.len);
    const rc = zlib.deflate(&stream, zlib.Z_FINISH);
    if (rc != zlib.Z_STREAM_END) return error.DeflateFailed;
    return try a.realloc(out, stream.total_out);
}

fn native_gzcompress(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const out = zlibEncodeWindow(ctx.allocator, args[0].string.bytes(), 15) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

fn native_gzuncompress(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const out = zlibDecodeWindow(ctx.allocator, args[0].string.bytes(), 15) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

fn native_gzdeflate(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const out = zlibEncodeWindow(ctx.allocator, args[0].string.bytes(), -15) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

fn native_gzinflate(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const out = zlibDecodeWindow(ctx.allocator, args[0].string.bytes(), -15) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

fn native_gzencode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const out = zlibEncodeWindow(ctx.allocator, args[0].string.bytes(), 15 + 16) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

fn native_gzdecode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const out = zlibDecodeWindow(ctx.allocator, args[0].string.bytes(), 15 + 32) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

fn gzipDecode(a: Allocator, input: []const u8) ![]u8 {
    if (input.len == 0) return try a.alloc(u8, 0);
    var stream: zlib.z_stream = std.mem.zeroes(zlib.z_stream);
    if (zlib.inflateInit2_(&stream, 15 + 32, zlib.zlibVersion(), @sizeOf(zlib.z_stream)) != zlib.Z_OK) {
        return error.InflateInitFailed;
    }
    defer _ = zlib.inflateEnd(&stream);

    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(a);

    stream.next_in = @constCast(input.ptr);
    stream.avail_in = @intCast(input.len);

    var chunk: [16 * 1024]u8 = undefined;
    while (true) {
        stream.next_out = &chunk;
        stream.avail_out = chunk.len;
        const rc = zlib.inflate(&stream, zlib.Z_NO_FLUSH);
        const produced = chunk.len - stream.avail_out;
        if (produced > 0) try out.appendSlice(a, chunk[0..produced]);
        if (rc == zlib.Z_STREAM_END) break;
        if (rc != zlib.Z_OK) return error.CorruptCompressedData;
        if (stream.avail_in == 0 and produced == 0) break;
    }

    return try out.toOwnedSlice(a);
}

// gzip-encode bytes (gzip format, default compression). caller owns the buffer
fn gzipEncode(a: Allocator, input: []const u8) ![]u8 {
    var stream: zlib.z_stream = std.mem.zeroes(zlib.z_stream);
    if (zlib.deflateInit2_(
        &stream,
        zlib.Z_DEFAULT_COMPRESSION,
        zlib.Z_DEFLATED,
        15 + 16, // gzip wrapper
        8,
        zlib.Z_DEFAULT_STRATEGY,
        zlib.zlibVersion(),
        @sizeOf(zlib.z_stream),
    ) != zlib.Z_OK) {
        return error.DeflateInitFailed;
    }
    defer _ = zlib.deflateEnd(&stream);

    const bound = zlib.deflateBound(&stream, @intCast(input.len));
    const out = try a.alloc(u8, bound + 32);
    errdefer a.free(out);

    stream.next_in = @constCast(input.ptr);
    stream.avail_in = @intCast(input.len);
    stream.next_out = out.ptr;
    stream.avail_out = @intCast(out.len);

    const rc = zlib.deflate(&stream, zlib.Z_FINISH);
    if (rc != zlib.Z_STREAM_END) return error.DeflateFailed;

    return try a.realloc(out, stream.total_out);
}

// reads a `compress.zlib://` path's underlying file and inflates it. returns
// owned bytes on success. caller registers them with vm.strings if needed
fn readZlibFile(a: Allocator, path: []const u8) ![]u8 {
    const inner = path[ZLIB_PREFIX.len..];
    const raw = try bundle.readFileAlloc(a, inner, 1024 * 1024 * 256);
    defer a.free(raw);
    return try gzipDecode(a, raw);
}

// gzip-encodes data and writes it to the path under `compress.zlib://`
fn writeZlibFile(a: Allocator, path: []const u8, data: []const u8) !void {
    const inner = path[ZLIB_PREFIX.len..];
    const encoded = try gzipEncode(a, data);
    defer a.free(encoded);
    try std.Io.Dir.cwd().writeFile(platform.io, .{ .sub_path = inner, .data = encoded });
}

fn isBuiltinWrapper(p: []const u8) bool {
    for (builtin_wrappers) |w| {
        if (std.mem.eql(u8, w, p)) return true;
    }
    return false;
}

// extracts "phar" from "phar://something". returns null if no scheme.
fn extractScheme(path: []const u8) ?[]const u8 {
    const idx = std.mem.indexOf(u8, path, "://") orelse return null;
    return path[0..idx];
}

// returns true if the protocol's builtin handling has been suppressed via
// stream_wrapper_unregister. user-registered wrappers always dispatch first
// regardless of this flag
fn isWrapperUnregistered(vm: *VM, scheme: []const u8) bool {
    return vm.stream_wrappers_unregistered.contains(scheme);
}

// returns the user wrapper class name registered for the path's scheme, or null
fn userWrapperFor(vm: *VM, path: []const u8) ?[]const u8 {
    const scheme = extractScheme(path) orelse return null;
    return vm.stream_wrappers_user.get(scheme);
}

// instantiates a user wrapper class, calls __construct() if defined, then
// stream_open(path, mode, options=0, opened_path=null). returns a FileHandle
// PhpObject with __wrapper_obj pointing at the wrapper instance. returns null
// if stream_open returned false or threw
fn dispatchUserOpen(ctx: *NativeContext, class_name: []const u8, path: []const u8, mode: []const u8) RuntimeError!?Value {
    const wrapper = try ctx.createObject(class_name);
    if (ctx.vm.hasMethod(class_name, "__construct")) {
        _ = try ctx.callMethod(wrapper, "__construct", &.{});
    }
    const open_args = [_]Value{
        .{ .string = Value.String.borrowed(path) },
        .{ .string = Value.String.borrowed(mode) },
        .{ .int = 0 },
        .null,
    };
    const ok = try ctx.callMethod(wrapper, "stream_open", &open_args);
    if (!ok.isTruthy()) return null;
    const fh = try ctx.createResource("FileHandle");
    try fh.set(ctx.allocator, "__wrapper_obj", .{ .object = wrapper });
    try fh.set(ctx.allocator, "__open", .{ .bool = true });
    try fh.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed(mode) });
    return Value{ .resource = fh };
}

// returns the wrapper instance attached to a FileHandle, if any
fn fileHandleWrapper(obj: *PhpObject) ?*PhpObject {
    const v = obj.get("__wrapper_obj");
    if (v != .object) return null;
    return v.object;
}

// calls $wrapper->url_stat(path, flags) for a registered user wrapper. returns
// the array result, or null on failure / not implemented
fn dispatchUserStat(ctx: *NativeContext, class_name: []const u8, path: []const u8, flags: i64) RuntimeError!?*PhpArray {
    if (!ctx.vm.hasMethod(class_name, "url_stat")) return null;
    const wrapper = try ctx.createObject(class_name);
    if (ctx.vm.hasMethod(class_name, "__construct")) {
        _ = try ctx.callMethod(wrapper, "__construct", &.{});
    }
    const stat_args = [_]Value{ .{ .string = Value.String.borrowed(path) }, .{ .int = flags } };
    const result = try ctx.callMethod(wrapper, "url_stat", &stat_args);
    if (result != .array) return null;
    return result.array;
}

fn stream_get_wrappers(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const result = try ctx.createArray();
    for (builtin_wrappers) |w| {
        if (ctx.vm.stream_wrappers_unregistered.contains(w)) continue;
        try result.append(ctx.allocator, .{ .string = Value.String.borrowed(w) });
    }
    var it = ctx.vm.stream_wrappers_user.keyIterator();
    while (it.next()) |k| try result.appendCopiedString(ctx.allocator, k.*);
    return NativeResult.borrowed(.{ .array = result });
}

fn stream_wrapper_register(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const protocol = args[0].string.bytes();
    const class_name = args[1].string.bytes();
    if (protocol.len == 0) return NativeResult.scalar(.{ .bool = false });
    // already registered (builtin still active or user wrapper present)
    const builtin_active = isBuiltinWrapper(protocol) and !ctx.vm.stream_wrappers_unregistered.contains(protocol);
    if (builtin_active or ctx.vm.stream_wrappers_user.contains(protocol)) return NativeResult.scalar(.{ .bool = false });
    if (!ctx.vm.classes.contains(class_name)) {
        try ctx.vm.tryAutoload(class_name);
        if (!ctx.vm.classes.contains(class_name)) return NativeResult.scalar(.{ .bool = false });
    }
    try ctx.vm.stream_wrappers_user.ensureUnusedCapacity(ctx.allocator, 1);
    const proto_owned = try ctx.allocator.dupe(u8, protocol);
    errdefer ctx.allocator.free(proto_owned);
    const class_owned = try ctx.allocator.dupe(u8, class_name);
    ctx.vm.stream_wrappers_user.putAssumeCapacityNoClobber(proto_owned, class_owned);
    return NativeResult.scalar(.{ .bool = true });
}

fn stream_wrapper_unregister(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const protocol = args[0].string.bytes();
    if (ctx.vm.stream_wrappers_user.fetchRemove(protocol)) |kv| {
        ctx.allocator.free(kv.key);
        ctx.allocator.free(kv.value);
        return NativeResult.scalar(.{ .bool = true });
    }
    if (!isBuiltinWrapper(protocol)) return NativeResult.scalar(.{ .bool = false });
    if (ctx.vm.stream_wrappers_unregistered.contains(protocol)) return NativeResult.scalar(.{ .bool = false });
    try ctx.vm.stream_wrappers_unregistered.ensureUnusedCapacity(ctx.allocator, 1);
    ctx.vm.stream_wrappers_unregistered.putAssumeCapacityNoClobber(try ctx.allocator.dupe(u8, protocol), {});
    return NativeResult.scalar(.{ .bool = true });
}

fn stream_wrapper_restore(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const protocol = args[0].string.bytes();
    if (!isBuiltinWrapper(protocol)) return NativeResult.scalar(.{ .bool = false });
    const kv = ctx.vm.stream_wrappers_unregistered.fetchRemove(protocol) orelse return NativeResult.scalar(.{ .bool = true });
    ctx.allocator.free(kv.key);
    return NativeResult.scalar(.{ .bool = true });
}

fn native_noop_true(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = true });
}

fn native_stream_filter_register(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // accept the registration silently; user-defined filters aren't dispatched
    // through our stream layer, but returning true lets feature-detection
    // codepaths in libraries proceed
    return NativeResult.scalar(.{ .bool = true });
}

fn native_stream_filter_append(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // return a stub resource-like value so the caller can later pass it to
    // stream_filter_remove without erroring
    return NativeResult.scalar(.{ .int = 1 });
}

fn native_stream_get_filters(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    const names = [_][]const u8{ "string.rot13", "string.toupper", "string.tolower", "convert.base64-encode", "convert.base64-decode", "zlib.deflate", "zlib.inflate" };
    for (names) |n| try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(n) });
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_stream_get_transports(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    const names = [_][]const u8{ "tcp", "udp", "unix", "udg", "ssl", "tls", "tlsv1.2", "tlsv1.3" };
    for (names) |n| try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(n) });
    return NativeResult.borrowed(.{ .array = arr });
}

fn stream_copy_to_stream(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = try streamArg(ctx, args, .{ .func = "stream_copy_to_stream", .param = "from" });
    _ = try streamArg(ctx, args, .{ .func = "stream_copy_to_stream", .index = 1, .param = "to" });
    const length: i64 = if (args.len >= 3 and args[2] != .null) Value.toInt(args[2]) else -1;
    const offset: i64 = if (args.len >= 4 and args[3] != .null) Value.toInt(args[3]) else 0;

    var src_args: [3]Value = .{ args[0], .{ .int = if (length < 0) -1 else length }, .{ .int = offset } };
    const data_v = (try stream_get_contents(ctx, src_args[0..3])).value;
    if (data_v != .string) return NativeResult.scalar(.{ .bool = false });
    defer data_v.string.release();

    var write_args: [2]Value = .{ args[1], data_v };
    return native_fwrite(ctx, write_args[0..2]);
}

fn stream_get_contents(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try streamArg(ctx, args, .{ .func = "stream_get_contents" });
    // length: -1 (or null) means read until EOF; non-negative means cap
    const length: i64 = if (args.len >= 2 and args[1] == .int) args[1].int else -1;
    // offset: -1 (default) means start at current position; >=0 means seek
    const offset: i64 = if (args.len >= 3 and args[2] == .int) args[2].int else -1;

    if (getBufferBacking(obj)) |buffer| {
        if (offset >= 0) setBufferPos(obj, @intCast(offset));
        const pos = getBufferPos(obj);
        if (pos >= buffer.len) return NativeResult.literal("");
        const remaining = buffer[pos..];
        const take = if (length >= 0) @min(@as(usize, @intCast(length)), remaining.len) else remaining.len;
        setBufferPos(obj, pos + take);
        return try NativeResult.copyString(ctx.allocator, remaining[0..take]);
    }
    const io = streamIo(obj) orelse return NativeResult.scalar(.{ .bool = false });
    if (offset >= 0) {
        platform.seekTo(io.file, @intCast(offset)) catch return NativeResult.scalar(.{ .bool = false });
    }
    // until the length, the end, or (non-blocking) nothing more for now
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(ctx.allocator);
    var chunk: [8192]u8 = undefined;
    while (length < 0 or out.items.len < @as(usize, @intCast(length))) {
        const want = if (length < 0) chunk.len else @min(chunk.len, @as(usize, @intCast(length)) - out.items.len);
        const n = io.read(chunk[0..want]) catch |err| {
            if (err == error.WouldBlock) break;
            if (out.items.len > 0) break;
            return NativeResult.scalar(.{ .bool = false });
        };
        if (n == 0) {
            try obj.set(ctx.allocator, "__eof", .{ .bool = true });
            break;
        }
        try out.appendSlice(ctx.allocator, chunk[0..n]);
    }
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, try out.toOwnedSlice(ctx.allocator)));
}

fn native_fstat(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try streamArg(ctx, args, .{ .func = "fstat" });
    const file = getFileHandle(obj) orelse return NativeResult.scalar(.{ .bool = false });
    if (!platform.is_windows) {
        const st = sys.fstat(file.handle) catch return NativeResult.scalar(.{ .bool = false });
        return NativeResult.borrowed(.{ .array = try wrapperStatArray(ctx, fromSysStat(st)) });
    }
    const stat = file.stat(platform.io) catch return NativeResult.scalar(.{ .bool = false });
    const sec = struct {
        fn of(ts: std.Io.Timestamp) i64 {
            return @intCast(@divFloor(ts.nanoseconds, 1_000_000_000));
        }
    }.of;
    return NativeResult.borrowed(.{ .array = try wrapperStatArray(ctx, .{ .mode = platform.modeOf(stat), .size = @intCast(stat.size), .rdev = 0, .atime = sec(stat.atime orelse stat.mtime), .mtime = sec(stat.mtime), .ctime = sec(stat.ctime) }) });
}

fn native_touch(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const filename = try strArg(ctx, args, "touch", 0, "filename", true);
    const mtime_null = args.len < 2 or args[1] == .null;
    const atime_null = args.len < 3 or args[2] == .null;
    const mtime: i64 = if (mtime_null) 0 else try intArg(ctx, args, "touch", 1, "mtime", 0);
    const atime: i64 = if (atime_null) mtime else try intArg(ctx, args, "touch", 2, "atime", 0);
    if (filename.len == 0) return NativeResult.scalar(.{ .bool = false });
    if (mtime_null and !atime_null) return throwValueError(ctx, "touch(): Argument #2 ($mtime) cannot be null when argument #3 ($atime) is an integer", .{});
    var os_buf: [std.fs.max_path_bytes]u8 = undefined;
    var path = bundle.osPath(&os_buf, filename);
    if (std.ascii.startsWithIgnoreCase(path, "file://")) path = path[7..];
    bundle.prepareWrite(path, .edit);

    // create the file if it doesn't exist already
    if (std.Io.Dir.cwd().access(platform.io, path, .{})) |_| {} else |_| {
        const created = std.Io.Dir.cwd().createFile(platform.io, path, .{ .truncate = true }) catch |err| {
            try warn(ctx, "touch(): Unable to create file {s} because {s}", .{ filename, errorText(err) });
            return NativeResult.scalar(.{ .bool = false });
        };
        created.close(platform.io);
    }

    const stamp = struct {
        fn of(seconds: i64) std.Io.File.SetTimestamp {
            return .{ .new = .{ .nanoseconds = @as(i96, seconds) * std.time.ns_per_s } };
        }
    }.of;
    const modify: std.Io.File.SetTimestamp = if (mtime_null) .now else stamp(mtime);
    const access: std.Io.File.SetTimestamp = if (mtime_null) .now else stamp(atime);
    if (platform.is_windows) {
        // std sets a path's times only through an open handle there
        const f = std.Io.Dir.cwd().openFile(platform.io, path, .{ .mode = .write_only }) catch return NativeResult.scalar(.{ .bool = true });
        defer f.close(platform.io);
        f.setTimestamps(platform.io, .{ .access_timestamp = access, .modify_timestamp = modify }) catch {};
        return NativeResult.scalar(.{ .bool = true });
    }
    // utime(2) on the path: setting the current time needs only ownership or
    // write permission, and directories take it too
    std.Io.Dir.cwd().setTimestamps(platform.io, path, .{ .access_timestamp = access, .modify_timestamp = modify }) catch |err| {
        try warn(ctx, "touch(): Utime failed: {s}", .{errorText(err)});
        return NativeResult.scalar(.{ .bool = false });
    };
    return NativeResult.scalar(.{ .bool = true });
}

fn native_chmod(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const spelled = try strArg(ctx, args, "chmod", 0, "filename", true);
    const mode = try intArg(ctx, args, "chmod", 1, "permissions", 0);
    var os_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = bundle.osPath(&os_buf, spelled);
    bundle.prepareWrite(path, .edit);
    if (platform.is_windows) {
        // windows keeps only a read-only bit: no write permission sets it
        if (platform.setReadOnly(path, (mode & 0o222) == 0)) return NativeResult.scalar(.{ .bool = true });
        try warn(ctx, "chmod(): No such file or directory", .{});
        return NativeResult.scalar(.{ .bool = false });
    }
    // chmod(2) on the path, as php does: opening it first would refuse a
    // directory or a file without read and write permission
    const path_z = std.posix.toPosixPath(path) catch {
        try warn(ctx, "chmod(): File name too long", .{});
        return NativeResult.scalar(.{ .bool = false });
    };
    if (std.c.chmod(&path_z, @truncate(@as(u64, @bitCast(mode)))) != 0) {
        try warn(ctx, "chmod(): {s}", .{sys.errnoText()});
        return NativeResult.scalar(.{ .bool = false });
    }
    return NativeResult.scalar(.{ .bool = true });
}

// chown, chgrp, lchown, lchgrp: a numeric id or a user or group name,
// handed to chown(2) or lchown(2), with php's warnings when that fails
fn native_chown(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return changeOwner(ctx, args, "chown", false, false);
}

fn native_chgrp(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return changeOwner(ctx, args, "chgrp", true, false);
}

fn native_lchown(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return changeOwner(ctx, args, "lchown", false, true);
}

fn native_lchgrp(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return changeOwner(ctx, args, "lchgrp", true, true);
}

extern "c" fn chown(path: [*:0]const u8, owner: std.c.uid_t, group: std.c.gid_t) c_int;
extern "c" fn lchown(path: [*:0]const u8, owner: std.c.uid_t, group: std.c.gid_t) c_int;

fn changeOwner(ctx: *NativeContext, args: []const Value, comptime func: []const u8, comptime group: bool, comptime link: bool) RuntimeError!NativeResult {
    const filename = try strArg(ctx, args, func, 0, "filename", true);
    const param = if (group) "group" else "user";
    const id_arg: Value = if (args.len > 1) args[1] else .null;
    // string|int: a name, or an id
    const name: ?[]const u8 = switch (id_arg) {
        .string => |str| str.bytes(),
        .int, .bool, .float => null,
        else => return throwStreamArg(ctx, func ++ "(): Argument #2 ($" ++ param ++ ") must be of type string|int, {s} given", .{types.phpTypeName(id_arg)}),
    };
    var os_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = bundle.osPath(&os_buf, filename);
    const id: u32 = if (name) |n| blk: {
        const name_z = try ctx.allocator.dupeSentinel(u8, n, 0);
        defer ctx.allocator.free(name_z);
        if (group) {
            if (std.c.getgrnam(name_z.ptr)) |gr| break :blk gr.gid;
        } else {
            if (std.c.getpwnam(name_z.ptr)) |pw| break :blk pw.uid;
        }
        try warn(ctx, func ++ "(): Unable to find " ++ (if (group) "gid" else "uid") ++ " for {s}", .{n});
        return NativeResult.scalar(.{ .bool = false });
    } else @truncate(@as(u64, @bitCast(Value.toInt(id_arg))));
    bundle.prepareWrite(path, .edit);
    const path_z = std.posix.toPosixPath(path) catch return linkFailure(ctx, func, "File name too long");
    const keep = std.math.maxInt(u32);
    const uid: std.c.uid_t = if (group) keep else id;
    const gid: std.c.gid_t = if (group) id else keep;
    const rc = if (link) lchown(&path_z, uid, gid) else chown(&path_z, uid, gid);
    if (rc != 0) return linkFailure(ctx, func, sys.errnoText());
    return NativeResult.scalar(.{ .bool = true });
}

fn native_stat(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const st = (try phpStat(ctx, try strArg(ctx, args, "stat", 0, "filename", false), "stat", false)) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.borrowed(.{ .array = try wrapperStatArray(ctx, st) });
}

fn native_chdir(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    var os_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = bundle.osPath(&os_buf, args[0].string.bytes());
    bundle.ensureDir(path);
    var dir = std.Io.Dir.cwd().openDir(platform.io, path, .{}) catch return NativeResult.scalar(.{ .bool = false });
    defer dir.close(platform.io);
    std.process.setCurrentDir(platform.io, dir) catch return NativeResult.scalar(.{ .bool = false });
    ctx.vm.clearRealDirCache();
    return NativeResult.scalar(.{ .bool = true });
}

fn native_stream_is_local(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const scheme = extractScheme(args[0].string.bytes()) orelse return NativeResult.scalar(.{ .bool = true });
    return NativeResult.scalar(.{ .bool = std.mem.eql(u8, scheme, "file") or std.mem.eql(u8, scheme, "phar") });
}

fn native_stream_resolve_include_path(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const found = try includes.resolve(ctx.vm, args[0].string.bytes()) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.copyString(ctx.allocator, found);
}

fn native_stream_isatty(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try streamArg(ctx, args, .{ .func = "stream_isatty" });
    if (!std.mem.eql(u8, obj.class_name, "FileHandle")) return NativeResult.scalar(.{ .bool = false });
    const fd_val = obj.get("__fd");
    if (fd_val != .int) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = platform.isatty(fd_val.int) });
}

fn native_clearstatcache(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.null);
}

fn native_stream_supports_lock(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // local file streams (FileHandle backed by an fd from open()) support
    // flock; in-memory streams (php://memory, php://temp), HTTP/curl-backed
    // streams, and other non-fd wrappers do not. detect by inspecting the
    // path: anything starting with 'php://', 'http://', 'https://', 'data:',
    // 'ftp://' is a non-fd stream
    const obj = try streamArg(ctx, args, .{ .func = "stream_supports_lock" });
    if (!std.mem.eql(u8, obj.class_name, "FileHandle")) return NativeResult.scalar(.{ .bool = false });
    const path_v = obj.get("__path");
    if (path_v != .string) return NativeResult.scalar(.{ .bool = true });
    const p = path_v.string.bytes();
    if (std.mem.startsWith(u8, p, "php://") or
        std.mem.startsWith(u8, p, "http://") or
        std.mem.startsWith(u8, p, "https://") or
        std.mem.startsWith(u8, p, "ftp://") or
        std.mem.startsWith(u8, p, "data:")) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn native_stream_set_chunk_size(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = 8192 });
}

fn native_stream_set_buffer(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = 0 });
}

fn native_umask(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len > 0 and args[0] == .int) {
        const old = std.c.umask(@intCast(args[0].int));
        return NativeResult.scalar(.{ .int = @intCast(old) });
    }
    const current = std.c.umask(0o022);
    _ = std.c.umask(current);
    return NativeResult.scalar(.{ .int = @intCast(current) });
}

fn native_fileperms(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return statOne(ctx, args, .mode, "fileperms");
}

fn native_fileowner(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return statOne(ctx, args, .uid, "fileowner");
}

fn native_filegroup(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return statOne(ctx, args, .gid, "filegroup");
}

fn native_is_link(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const spelled = try strArg(ctx, args, "is_link", 0, "filename", false);
    if (!usablePath(spelled)) return NativeResult.scalar(.{ .bool = false });
    const path = spelled;
    const st = sys.lstat(path) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = (st.mode & 0o170000) == 0o120000 });
}

fn native_symlink(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const target = try strArg(ctx, args, "symlink", 0, "target", true);
    const link_arg = try strArg(ctx, args, "symlink", 1, "link", true);
    // the link is made where the expanded path says; the target is stored as
    // given, relative to the link
    var os_buf: [std.fs.max_path_bytes]u8 = undefined;
    var link_buf: [std.fs.max_path_bytes]u8 = undefined;
    const linkpath = if (link_arg.len == 0) null else paths.expand(&link_buf, bundle.osPath(&os_buf, link_arg));
    if (linkpath == null or target.len == 0) {
        try warn(ctx, "symlink(): No such file or directory", .{});
        return NativeResult.scalar(.{ .bool = false });
    }
    bundle.prepareWrite(linkpath.?, .create);
    const t = std.posix.toPosixPath(target) catch return linkFailure(ctx, "symlink", "File name too long");
    const l = std.posix.toPosixPath(linkpath.?) catch return linkFailure(ctx, "symlink", "File name too long");
    if (std.c.symlink(&t, &l) != 0) return linkFailure(ctx, "symlink", sys.errnoText());
    return NativeResult.scalar(.{ .bool = true });
}

fn native_link(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const target_arg = try strArg(ctx, args, "link", 0, "target", true);
    const link_arg = try strArg(ctx, args, "link", 1, "link", true);
    if (target_arg.len == 0 or link_arg.len == 0) {
        try warn(ctx, "link(): No such file or directory", .{});
        return NativeResult.scalar(.{ .bool = false });
    }
    var target_buf: [std.fs.max_path_bytes]u8 = undefined;
    const target = bundle.osPath(&target_buf, target_arg);
    var os_buf: [std.fs.max_path_bytes]u8 = undefined;
    const linkpath = bundle.osPath(&os_buf, link_arg);
    bundle.prepareWrite(target, .edit);
    bundle.prepareWrite(linkpath, .create);
    const t = std.posix.toPosixPath(target) catch return linkFailure(ctx, "link", "File name too long");
    const l = std.posix.toPosixPath(linkpath) catch return linkFailure(ctx, "link", "File name too long");
    if (std.c.link(&t, &l) != 0) return linkFailure(ctx, "link", sys.errnoText());
    return NativeResult.scalar(.{ .bool = true });
}

fn linkFailure(ctx: *NativeContext, comptime func: []const u8, reason: []const u8) RuntimeError!NativeResult {
    try warn(ctx, func ++ "(): {s}", .{reason});
    return NativeResult.scalar(.{ .bool = false });
}

fn wrapperStatArray(ctx: *NativeContext, st: WrapperStat) !*PhpArray {
    const arr = try ctx.createArray();
    const names = [_][]const u8{ "dev", "ino", "mode", "nlink", "uid", "gid", "rdev", "size", "atime", "mtime", "ctime", "blksize", "blocks" };
    inline for (names, 0..) |name, i| try arr.set(ctx.allocator, .{ .int = @intCast(i) }, .{ .int = @field(st, name) });
    inline for (names) |name| try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(name) }, .{ .int = @field(st, name) });
    return arr;
}

fn native_lstat(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const st = (try phpStat(ctx, try strArg(ctx, args, "lstat", 0, "filename", false), "lstat", true)) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.borrowed(.{ .array = try wrapperStatArray(ctx, st) });
}

fn native_readlink(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const path = try strArg(ctx, args, "readlink", 0, "path", true);
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = (if (path.len == 0) error.FileNotFound else std.Io.Dir.cwd().readLink(platform.io, path, &buf)) catch |err| {
        try warn(ctx, "readlink(): {s}", .{errorText(err)});
        return NativeResult.scalar(.{ .bool = false });
    };
    return try NativeResult.copyString(ctx.allocator, buf[0..len]);
}

fn native_tmpfile(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const file = anonymousFile() orelse return NativeResult.scalar(.{ .bool = false });
    const obj = try ctx.createResource("FileHandle");
    try obj.set(ctx.allocator, "__fd", .{ .int = platform.fdFromFile(file) });
    try obj.set(ctx.allocator, "__open", .{ .bool = true });
    try obj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed("r+b") });
    return NativeResult.borrowed(.{ .resource = obj });
}

// a file of the executable's packed application, opened for reading: an
// anonymous file holding its bytes, so every stream function works on it
fn packedFile(bytes: []const u8) ?std.Io.File {
    const file = anonymousFile() orelse return null;
    platform.writeAll(file, bytes) catch {
        file.close(platform.io);
        return null;
    };
    platform.seekTo(file, 0) catch {
        file.close(platform.io);
        return null;
    };
    return file;
}

// a read-write file with no name left on disk, so it vanishes with its fd;
// backs tmpfile() and php://memory and php://temp
fn anonymousFile() ?std.Io.File {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp = std.fmt.bufPrint(&buf, "{s}{c}zphp_{d}_{d}", .{ platform.tempDir(), std.fs.path.sep, @as(u64, @truncate(@as(u128, @bitCast(platform.nanoTimestamp())))), platform.random.int(u32) }) catch return null;
    const file = std.Io.Dir.cwd().createFile(platform.io, tmp, .{ .read = true, .truncate = true, .exclusive = true }) catch return null;
    std.Io.Dir.cwd().deleteFile(platform.io, tmp) catch {};
    return file;
}

const StdioBehavior = enum { capture, inherit };
const ShellResult = struct { stdout: []u8, stderr: []u8, exit: i64 };

fn runShellCapture(allocator: std.mem.Allocator, command: []const u8, stdin_data: ?[]const u8) !ShellResult {
    return runShellWith(allocator, command, stdin_data, .capture, .capture);
}

// child process runner with per-stream behavior. capture pipes the stream and
// returns it; inherit forwards to the parent's fds (matches popen('w') where
// PHP's child writes straight to the terminal)
// caller hook so callers with access to a VM can flush its output buffer
// before spawning a child with inherited stdout/stderr. without flushing, any
// preceding echo'd text lands AFTER the child's output because the child
// writes directly to fd 1 while echo still sits in vm.output
fn flushVmOutputForInheritedChild(vm: *@import("../runtime/vm.zig").VM, stdout_b: StdioBehavior, stderr_b: StdioBehavior) void {
    if (stdout_b == .capture and stderr_b == .capture) return;
    vm.flushOutputToStdout();
}

fn runShellWith(
    allocator: std.mem.Allocator,
    command: []const u8,
    stdin_data: ?[]const u8,
    stdout_b: StdioBehavior,
    stderr_b: StdioBehavior,
) !ShellResult {
    const argv = platform.shellArgv(command);
    const result = try platform.runChild(allocator, &argv, .{
        .stdin_data = stdin_data,
        .stdin = .ignore,
        .stdout = if (stdout_b == .capture) .pipe else .inherit,
        .stderr = if (stderr_b == .capture) .pipe else .inherit,
    });
    const stdout = result.stdout;
    const stderr = result.stderr;
    const exit = platform.exitStatus(result.term);
    return .{ .stdout = stdout, .stderr = stderr, .exit = exit };
}

// takes ownership of data
// a handle's in-memory contents, taking ownership of bytes
fn setAdoptedBuffer(ctx: *NativeContext, obj: *PhpObject, bytes: []u8) !void {
    const owned = try Value.String.adopt(ctx.allocator, bytes);
    defer owned.release();
    try obj.set(ctx.allocator, "__buffer", .{ .string = owned });
}

fn makeReadBufferHandle(ctx: *NativeContext, data: []u8) !*PhpObject {
    errdefer ctx.allocator.free(data);
    const obj = try ctx.createResource("FileHandle");
    try setAdoptedBuffer(ctx, obj, data);
    try obj.set(ctx.allocator, "__pos", .{ .int = 0 });
    try obj.set(ctx.allocator, "__open", .{ .bool = true });
    try obj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed("r") });
    return obj;
}

fn makePopenWriteHandle(ctx: *NativeContext, command: []const u8) !*PhpObject {
    const obj = try ctx.createResource("FileHandle");
    const cmd_str = try Value.String.create(ctx.allocator, command);
    defer cmd_str.release();
    try obj.set(ctx.allocator, "__popen_cmd", .{ .string = cmd_str });
    try obj.set(ctx.allocator, "__buffer", .{ .string = Value.String.borrowed("") });
    try obj.set(ctx.allocator, "__pos", .{ .int = 0 });
    try obj.set(ctx.allocator, "__open", .{ .bool = true });
    try obj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed("w") });
    return obj;
}

pub fn native_popen(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const cmd = try strArg(ctx, args, "popen", 0, "command", true);
    const mode = try strArg(ctx, args, "popen", 1, "mode", false);
    // posix popen takes no 'b'; php drops the first one and accepts only
    // what is left of "r", "rb", "w", "wb"
    var mode_buf: [3]u8 = undefined;
    var posix_mode: []const u8 = mode;
    if (!platform.is_windows and mode.len <= mode_buf.len) {
        if (std.mem.indexOfScalar(u8, mode, 'b')) |b| {
            @memcpy(mode_buf[0..b], mode[0..b]);
            @memcpy(mode_buf[b .. mode.len - 1], mode[b + 1 ..]);
            posix_mode = mode_buf[0 .. mode.len - 1];
        }
    }
    const valid = switch (posix_mode.len) {
        0 => true,
        1 => posix_mode[0] == 'r' or posix_mode[0] == 'w',
        2 => std.mem.eql(u8, posix_mode, "rb") or std.mem.eql(u8, posix_mode, "wb"),
        else => false,
    };
    if (!valid) return throwValueError(ctx, "popen(): Argument #2 ($mode) must be one of \"r\", \"rb\", \"w\", or \"wb\"", .{});
    if (mode.len > 0 and (mode[0] == 'r')) {
        const result = runShellCapture(ctx.allocator, cmd, null) catch return NativeResult.scalar(.{ .bool = false });
        ctx.allocator.free(result.stderr);
        const obj = try makeReadBufferHandle(ctx, result.stdout);
        try obj.set(ctx.allocator, "__popen_exit", .{ .int = result.exit });
        return NativeResult.borrowed(.{ .resource = obj });
    }
    if (mode.len > 0 and (mode[0] == 'w')) {
        const obj = try makePopenWriteHandle(ctx, cmd);
        return NativeResult.borrowed(.{ .resource = obj });
    }
    return NativeResult.scalar(.{ .bool = false });
}

pub fn native_pclose(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try streamArg(ctx, args, .{ .func = "pclose", .param = "handle" });
    const cmd_v = obj.get("__popen_cmd");
    if (cmd_v == .string) {
        const buf_v = obj.get("__buffer");
        const stdin_data: []const u8 = if (buf_v == .string) buf_v.string.bytes() else "";
        // popen('w') inherits the parent's stdout/stderr - children output goes
        // straight to the terminal, matching PHP
        flushVmOutputForInheritedChild(ctx.vm, .inherit, .inherit);
        const result = runShellWith(ctx.allocator, cmd_v.string.bytes(), stdin_data, .inherit, .inherit) catch {
            obj.set(ctx.allocator, "__open", .{ .bool = false }) catch {};
            return NativeResult.scalar(.{ .int = -1 });
        };
        ctx.allocator.free(result.stdout);
        ctx.allocator.free(result.stderr);
        obj.set(ctx.allocator, "__open", .{ .bool = false }) catch {};
        return NativeResult.scalar(.{ .int = result.exit });
    }
    const exit_v = obj.get("__popen_exit");
    obj.set(ctx.allocator, "__open", .{ .bool = false }) catch {};
    if (exit_v == .int) return NativeResult.scalar(.{ .int = exit_v.int });
    return NativeResult.scalar(.{ .int = 0 });
}

const FdDesc = union(enum) {
    inherit,
    pipe_r,
    pipe_w,
    socket,
    pty,
    file: struct { path: []const u8, mode: []const u8 },
    redirect: std.posix.fd_t,
};

const ProcDesc = struct { role: i64, action: FdDesc };
const PreparedDesc = struct {
    role: i64,
    action: FdDesc,
    parent_fd: std.posix.fd_t = -1,
    child_fd: std.posix.fd_t = -1,
    aux_fd: std.posix.fd_t = -1,
};
const ProcSpawn = struct {
    pid: std.posix.pid_t,
    pipe_fds: std.ArrayListUnmanaged(@import("../runtime/vm.zig").ProcPipe),
};

extern fn openpty(master: *c_int, slave: *c_int, name: ?[*]u8, termp: ?*anyopaque, winp: ?*anyopaque) c_int;

fn setCloexec(fd: std.posix.fd_t) void {
    const flags = sys.fcntl(fd, 1, 0) catch return;
    _ = sys.fcntl(fd, 2, flags | 1) catch {};
}

fn procChildDup(src: std.posix.fd_t, target: std.posix.fd_t, err_fd: std.posix.fd_t) void {
    sys.dup2(src, target) catch |e| procChildFail(err_fd, e);
}

// the child reports why exec failed as an error code; errors outside the
// exec/chdir set collapse to ProcSpawnFailed
const SpawnError = error{ FileNotFound, AccessDenied, NotDir, InvalidExe, IsDir, NameTooLong, ProcSpawnFailed };

fn spawnFailure(code: u64) SpawnError {
    const err = @errorFromInt(@as(@Int(.unsigned, @bitSizeOf(anyerror)), @intCast(code)));
    return switch (err) {
        error.FileNotFound => error.FileNotFound,
        error.AccessDenied => error.AccessDenied,
        error.NotDir => error.NotDir,
        error.InvalidExe => error.InvalidExe,
        error.IsDir => error.IsDir,
        error.NameTooLong => error.NameTooLong,
        else => error.ProcSpawnFailed,
    };
}

fn spawnFailureMessage(err: anyerror) []const u8 {
    return switch (err) {
        error.FileNotFound => "No such file or directory",
        error.AccessDenied => "Permission denied",
        error.NotDir => "Not a directory",
        error.InvalidExe => "Exec format error",
        error.IsDir => "Is a directory",
        error.NameTooLong => "File name too long",
        else => "Unknown error",
    };
}

fn procChildFail(err_fd: std.posix.fd_t, err: anyerror) noreturn {
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, @intFromError(err), .little);
    _ = sys.write(err_fd, &buf) catch {};
    std.c._exit(1);
}

fn closePrepared(descs: []PreparedDesc) void {
    for (descs) |*d| {
        if (d.parent_fd != -1) sys.close(d.parent_fd);
        if (d.child_fd != -1) sys.close(d.child_fd);
        if (d.aux_fd != -1) sys.close(d.aux_fd);
        d.parent_fd = -1;
        d.child_fd = -1;
        d.aux_fd = -1;
    }
}

// a string runs through /bin/sh -c; an array is an argv run directly,
// found on PATH like execvp, with no shell in between
const ProcCommand = union(enum) { shell: []const u8, argv: []const []const u8 };

fn forkExecDesc(allocator: std.mem.Allocator, command: ProcCommand, specs: []const ProcDesc, cwd: ?[]const u8, env: ?[]const []const u8) !ProcSpawn {
    const prepared = try allocator.alloc(PreparedDesc, specs.len);
    defer allocator.free(prepared);
    for (specs, 0..) |spec, i| prepared[i] = .{ .role = spec.role, .action = spec.action };
    errdefer closePrepared(prepared);

    for (prepared) |*d| switch (d.action) {
        .pipe_r, .pipe_w => {
            const pair = try sys.pipeCloexec();
            if (d.action == .pipe_r) {
                d.child_fd = pair[0];
                d.parent_fd = pair[1];
            } else {
                d.child_fd = pair[1];
                d.parent_fd = pair[0];
            }
        },
        .socket => {
            var pair: [2]std.posix.fd_t = undefined;
            if (std.c.socketpair(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0, &pair) != 0) return error.ProcSpawnFailed;
            setCloexec(pair[0]);
            setCloexec(pair[1]);
            d.parent_fd = pair[0];
            d.child_fd = pair[1];
        },
        .pty => {
            var master: c_int = -1;
            var slave: c_int = -1;
            if (openpty(&master, &slave, null, null, null) != 0) return error.ProcSpawnFailed;
            setCloexec(master);
            setCloexec(slave);
            d.parent_fd = master;
            d.child_fd = slave;
        },
        .file => |f| {
            const file = try openWithMode(f.path, f.mode);
            setCloexec(file.handle);
            d.child_fd = file.handle;
        },
        .inherit, .redirect => {},
    };

    const xrep = try sys.pipeCloexec();
    var xrep_open = true;
    errdefer if (xrep_open) {
        sys.close(xrep[0]);
        sys.close(xrep[1]);
    };
    // everything the child needs is built before fork: allocating after it
    // is unsafe in a threaded process
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const argv: [:null]?[*:0]const u8 = switch (command) {
        .shell => |cmd| blk: {
            const list = try a.allocSentinel(?[*:0]const u8, 3, null);
            list[0] = "/bin/sh";
            list[1] = "-c";
            list[2] = (try a.dupeSentinel(u8, cmd, 0)).ptr;
            break :blk list;
        },
        .argv => |words| blk: {
            const list = try a.allocSentinel(?[*:0]const u8, words.len, null);
            for (words, 0..) |word, i| list[i] = (try a.dupeSentinel(u8, word, 0)).ptr;
            break :blk list;
        },
    };
    const envp: [*:null]const ?[*:0]const u8 = if (env) |vars| blk: {
        const list = try a.allocSentinel(?[*:0]const u8, vars.len, null);
        for (vars, 0..) |v, i| list[i] = (try a.dupeSentinel(u8, v, 0)).ptr;
        break :blk list.ptr;
    } else @ptrCast(std.c.environ);
    const cwdz: ?[:0]const u8 = if (cwd) |dir| try a.dupeSentinel(u8, dir, 0) else null;

    const pid = try sys.fork();
    if (pid == 0) {
        if (cwdz) |dirz| {
            sys.chdir(dirz.ptr) catch |err| procChildFail(xrep[1], err);
        }
        for (prepared) |d| if (d.parent_fd != -1) sys.close(d.parent_fd);
        for (prepared) |d| {
            const target: std.posix.fd_t = @intCast(d.role);
            switch (d.action) {
                .inherit => {},
                .pipe_r, .pipe_w, .socket, .pty, .file => procChildDup(d.child_fd, target, xrep[1]),
                .redirect => |src| procChildDup(src, target, xrep[1]),
            }
        }
        for (prepared) |d| {
            if (d.child_fd == -1) continue;
            var is_target = false;
            for (prepared) |other| if (d.child_fd == other.role) {
                is_target = true;
                break;
            };
            if (!is_target) sys.close(d.child_fd);
        }
        const e = switch (command) {
            .shell => sys.execve("/bin/sh", argv.ptr, envp),
            .argv => sys.execvpe(argv[0].?, argv.ptr, envp),
        };
        procChildFail(xrep[1], e);
    }

    xrep_open = false;
    sys.close(xrep[1]);
    for (prepared) |*d| {
        if (d.child_fd != -1) sys.close(d.child_fd);
        d.child_fd = -1;
    }
    var buf: [8]u8 = undefined;
    const got = std.posix.read(xrep[0], &buf) catch 0;
    sys.close(xrep[0]);
    if (got == buf.len) {
        _ = sys.waitpid(pid, 0);
        return spawnFailure(std.mem.readInt(u64, &buf, .little));
    }

    var pipes: std.ArrayListUnmanaged(@import("../runtime/vm.zig").ProcPipe) = .empty;
    errdefer pipes.deinit(allocator);
    for (prepared) |*d| if (d.parent_fd != -1) {
        try pipes.append(allocator, .{ .role = d.role, .fd = d.parent_fd });
        d.parent_fd = -1;
    };
    return .{ .pid = pid, .pipe_fds = pipes };
}

// a value as text for the rest of the native call
pub fn ownedText(ctx: *NativeContext, v: Value) RuntimeError![]const u8 {
    if (v == .string) return v.string.bytes();
    return (try ctx.vm.transientFormatted(v)).bytes();
}

fn native_proc_open(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 3 or (args[0] != .string and args[0] != .array)) return NativeResult.scalar(.{ .bool = false });
    var words: std.ArrayListUnmanaged([]const u8) = .empty;
    defer words.deinit(ctx.allocator);
    if (args[0] == .array) {
        for (args[0].array.entries.items) |entry| try words.append(ctx.allocator, try ownedText(ctx, entry.value));
        if (words.items.len == 0) {
            try ctx.vm.setPendingException("ValueError", "proc_open(): Argument #1 ($command) must not be empty");
            return error.RuntimeError;
        }
    }
    const cmd = if (args[0] == .string) args[0].string.bytes() else try std.mem.join(ctx.allocator, " ", words.items);
    defer if (args[0] == .array) ctx.allocator.free(cmd);
    var env_vars: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (env_vars.items) |v| ctx.allocator.free(v);
        env_vars.deinit(ctx.allocator);
    }
    const has_env = args.len >= 5 and args[4] == .array;
    if (has_env) for (args[4].array.entries.items) |entry| {
        const key = switch (entry.key) {
            .string => |k| k.bytes(),
            .int => continue,
        };
        try env_vars.append(ctx.allocator, try std.fmt.allocPrint(ctx.allocator, "{s}={s}", .{ key, try ownedText(ctx, entry.value) }));
    };

    // php numbers the process after its pipes
    const proc = try ctx.vm.allocResource("ProcessResource");
    const cmd_str = try Value.String.create(ctx.allocator, cmd);
    defer cmd_str.release();
    try proc.set(ctx.allocator, "__cmd", .{ .string = cmd_str });
    const cmd_copy = cmd_str.bytes();
    try proc.set(ctx.allocator, "__exit", .{ .int = 0 });
    try proc.set(ctx.allocator, "__running", .{ .bool = true });

    var descs: std.ArrayListUnmanaged(ProcDesc) = .empty;
    defer descs.deinit(ctx.allocator);
    if (args[1] == .array) {
        for (args[1].array.entries.items) |entry| {
            if (entry.key != .int or entry.key.int < 0) continue;
            const role = entry.key.int;
            const v = entry.value;
            var action: FdDesc = .inherit;
            if (v == .array) {
                const tag = v.array.get(.{ .int = 0 });
                if (tag != .string) continue;
                if (std.mem.eql(u8, tag.string.bytes(), "pipe")) {
                    const mode = v.array.get(.{ .int = 1 });
                    action = if (mode == .string and mode.string.bytes().len > 0 and mode.string.bytes()[0] == 'r') .pipe_r else .pipe_w;
                } else if (std.mem.eql(u8, tag.string.bytes(), "file")) {
                    const pathv = v.array.get(.{ .int = 1 });
                    const modev = v.array.get(.{ .int = 2 });
                    if (pathv != .string or modev != .string) continue;
                    action = .{ .file = .{ .path = pathv.string.bytes(), .mode = modev.string.bytes() } };
                } else if (std.mem.eql(u8, tag.string.bytes(), "socket")) {
                    action = .socket;
                } else if (std.mem.eql(u8, tag.string.bytes(), "pty")) {
                    action = .pty;
                } else continue;
            } else if (v == .resource) {
                const fdv = v.resource.get("__fd");
                if (fdv != .int or fdv.int < 0) continue;
                action = .{ .redirect = @intCast(fdv.int) };
            } else continue;
            try descs.append(ctx.allocator, .{ .role = role, .action = action });
        }
    }

    var stdout_specified = false;
    var stderr_specified = false;
    var stdout_inherit = true;
    var stderr_inherit = true;
    for (descs.items) |desc| {
        if (desc.role == 1) {
            stdout_specified = true;
            stdout_inherit = desc.action == .inherit;
        }
        if (desc.role == 2) {
            stderr_specified = true;
            stderr_inherit = desc.action == .inherit;
        }
    }
    const inherits_out = (!stdout_specified or stdout_inherit) or (!stderr_specified or stderr_inherit);
    if (inherits_out) ctx.vm.flushOutputToStdout();

    // spawn the child live now (php spawns at proc_open, not at first read) via
    // fork/exec. the pid + parent-side pipe fds live in vm.proc_children keyed by
    // proc, so proc_close waitpid's the pid and reset/deinit reaps it. each pipe fd
    // becomes __fd on a FileHandle so fread/fwrite/stream_select use real live fds;
    // each is closed EXACTLY once: by fclose (clears pipe_fds[role]) or proc_close/reap
    const child_cwd: ?[]const u8 = if (args.len >= 4 and args[3] == .string) args[3].string.bytes() else null;
    const command: ProcCommand = if (args[0] == .array) .{ .argv = words.items } else .{ .shell = cmd_copy };
    const spawned = forkExecDesc(ctx.vm.allocator, command, descs.items, child_cwd, if (has_env) env_vars.items else null) catch |err| {
        const msg = try std.fmt.allocPrint(ctx.allocator, "proc_open(): posix_spawn() failed: {s}", .{spawnFailureMessage(err)});
        defer ctx.allocator.free(msg);
        try ctx.vm.emitWarning(msg);
        try proc.set(ctx.allocator, "__pid", .{ .int = 0 });
        try proc.set(ctx.allocator, "__reaped", .{ .bool = true });
        try proc.set(ctx.allocator, "__running", .{ .bool = false });
        try proc.set(ctx.allocator, "__exit", .{ .int = -1 });
        return NativeResult.scalar(.{ .bool = false });
    };
    try ctx.vm.registerProcChild(proc, spawned.pid, spawned.pipe_fds);
    try proc.set(ctx.allocator, "__pid", .{ .int = @intCast(spawned.pid) });
    try proc.set(ctx.allocator, "__reaped", .{ .bool = false });

    // build $pipes: one FileHandle per pipe fd, in fd order. a pipe_r fd is a write
    // handle for the caller (we write the child's stdin); pipe_w is a read handle
    const pipes = try ctx.vm.allocArray();
    for (descs.items) |desc| {
        const pmode: ?[]const u8 = switch (desc.action) {
            .pipe_r => "w",
            .pipe_w => "r",
            .socket, .pty => "r+",
            else => null,
        };
        if (pmode) |m| {
            var parent_fd: std.posix.fd_t = -1;
            for (spawned.pipe_fds.items) |pipe| if (pipe.role == desc.role) {
                parent_fd = pipe.fd;
                break;
            };
            if (parent_fd == -1) continue;
            const fobj = try ctx.createResource("FileHandle");
            try fobj.set(ctx.allocator, "__open", .{ .bool = true });
            try fobj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed(m) });
            try fobj.set(ctx.allocator, "__fd", .{ .int = @intCast(parent_fd) });
            try fobj.set(ctx.allocator, "__proc_ref", .{ .resource = proc });
            try fobj.set(ctx.allocator, "__proc_role", .{ .int = desc.role });
            try pipes.set(ctx.allocator, .{ .int = desc.role }, .{ .resource = fobj });
            ctx.vm.adoptProcPipe(proc, desc.role, fobj);
        }
    }

    ctx.vm.numberResource(proc);
    ctx.setCallerVar(2, args.len, .{ .array = pipes });
    return NativeResult.borrowed(.{ .resource = proc });
}

const PosixW = std.posix.W;

// decode a waitpid status onto the proc object's cached fields. marks __reaped so
// no later wait() runs on the same (now-consumed) pid
fn cacheProcTerm(ctx: *NativeContext, proc: *PhpObject, status: u32) void {
    proc.set(ctx.allocator, "__reaped", .{ .bool = true }) catch {};
    proc.set(ctx.allocator, "__running", .{ .bool = false }) catch {};
    if (PosixW.IFEXITED(status)) {
        proc.set(ctx.allocator, "__exit", .{ .int = @intCast(PosixW.EXITSTATUS(status)) }) catch {};
    } else if (PosixW.IFSIGNALED(status)) {
        const sig: i64 = @intFromEnum(PosixW.TERMSIG(status));
        proc.set(ctx.allocator, "__exit", .{ .int = sig + 128 }) catch {};
        proc.set(ctx.allocator, "__termsig", .{ .int = sig }) catch {};
        proc.set(ctx.allocator, "__signaled", .{ .bool = true }) catch {};
    } else {
        proc.set(ctx.allocator, "__exit", .{ .int = -1 }) catch {};
    }
}

fn native_proc_close(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try processArg(ctx, args, "proc_close");
    try obj.set(ctx.allocator, "__open", .{ .bool = false });
    const pc = ctx.vm.lookupProcChild(obj) orelse {
        // already finalized (or spawn failed) - return the cached exit
        const cached = obj.get("__exit");
        return NativeResult.scalar(.{ .int = if (cached == .int) cached.int else 0 });
    };
    // close stdin first so the child sees EOF and can finish
    for (pc.pipe_fds.items) |*pipe| if (pipe.role == 0) pipe.close();
    if (!pc.reaped) {
        // a prior proc_get_status may have already reaped via WNOHANG; if not, do a
        // blocking wait now (exactly one waitpid per pid - ECHILD is unreachable)
        const res = sys.waitpid(pc.pid, 0);
        cacheProcTerm(ctx, obj, res.status);
    }
    ctx.vm.closeProcChild(obj);
    const exit = obj.get("__exit");
    return NativeResult.scalar(.{ .int = if (exit == .int) exit.int else 0 });
}

fn native_proc_get_status(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try processArg(ctx, args, "proc_get_status");
    // non-blocking liveness poll. if the child has exited, reap the zombie (mark
    // .reaped so proc_close/reap won't wait again -> ECHILD) and cache the exit,
    // but leave the pipe fds + *Child intact: the script may still read buffered
    // output, and proc_close finalizes the fds
    var running = false;
    if (ctx.vm.lookupProcChild(obj)) |pc| {
        if (!pc.reaped) {
            const res = sys.waitpid(pc.pid, PosixW.NOHANG);
            if (res.pid == 0) {
                running = true;
            } else {
                pc.reaped = true;
                cacheProcTerm(ctx, obj, res.status);
            }
        }
    }
    const result = try ctx.vm.allocArray();
    const cmd = obj.get("__cmd");
    const exit = obj.get("__exit");
    const pid = obj.get("__pid");
    const signaled = obj.get("__signaled");
    const termsig = obj.get("__termsig");
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("command") }, if (cmd == .string) cmd else .{ .string = Value.String.borrowed("") });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("pid") }, if (pid == .int) pid else .{ .int = 0 });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("running") }, .{ .bool = running });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("signaled") }, .{ .bool = signaled == .bool and signaled.bool });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("stopped") }, .{ .bool = false });
    // exitcode is only meaningful once the process has terminated
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("exitcode") }, if (!running and exit == .int) exit else .{ .int = -1 });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("termsig") }, if (termsig == .int) termsig else .{ .int = 0 });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("stopsig") }, .{ .int = 0 });
    return NativeResult.borrowed(.{ .array = result });
}

fn native_proc_terminate(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const proc = try processArg(ctx, args, "proc_terminate");
    const sig: std.posix.SIG = if (args.len >= 2 and args[1] == .int) @enumFromInt(args[1].int) else .TERM;
    if (ctx.vm.lookupProcChild(proc)) |pc| {
        std.posix.kill(pc.pid, sig) catch return NativeResult.scalar(.{ .bool = false });
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn native_stream_set_blocking(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try streamArg(ctx, args, .{ .func = "stream_set_blocking" });
    if (args.len < 2) return NativeResult.scalar(.{ .bool = false });
    const fd = obj.get("__fd");
    if (fd != .int) return NativeResult.scalar(.{ .bool = false });
    const descriptor = platform.socketFromInt(fd.int) orelse return NativeResult.scalar(.{ .bool = false });
    platform.setNonBlocking(descriptor, !args[1].isTruthy()) catch return NativeResult.scalar(.{ .bool = false });
    try obj.set(ctx.allocator, "__blocking", .{ .bool = args[1].isTruthy() });
    return NativeResult.scalar(.{ .bool = true });
}

fn native_stream_set_timeout(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = true });
}

fn native_stream_set_read_buffer(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = 0 });
}

fn native_stream_set_write_buffer(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = 0 });
}

const MimeEntry = struct { ext: []const u8, mime: []const u8 };
const mime_table = [_]MimeEntry{
    .{ .ext = "html", .mime = "text/html" },
    .{ .ext = "htm", .mime = "text/html" },
    .{ .ext = "css", .mime = "text/css" },
    .{ .ext = "js", .mime = "application/javascript" },
    .{ .ext = "mjs", .mime = "application/javascript" },
    .{ .ext = "json", .mime = "application/json" },
    .{ .ext = "xml", .mime = "application/xml" },
    .{ .ext = "txt", .mime = "text/plain" },
    .{ .ext = "md", .mime = "text/markdown" },
    .{ .ext = "csv", .mime = "text/csv" },
    .{ .ext = "yml", .mime = "application/yaml" },
    .{ .ext = "yaml", .mime = "application/yaml" },
    .{ .ext = "png", .mime = "image/png" },
    .{ .ext = "jpg", .mime = "image/jpeg" },
    .{ .ext = "jpeg", .mime = "image/jpeg" },
    .{ .ext = "gif", .mime = "image/gif" },
    .{ .ext = "webp", .mime = "image/webp" },
    .{ .ext = "svg", .mime = "image/svg+xml" },
    .{ .ext = "ico", .mime = "image/x-icon" },
    .{ .ext = "bmp", .mime = "image/bmp" },
    .{ .ext = "tiff", .mime = "image/tiff" },
    .{ .ext = "pdf", .mime = "application/pdf" },
    .{ .ext = "zip", .mime = "application/zip" },
    .{ .ext = "tar", .mime = "application/x-tar" },
    .{ .ext = "gz", .mime = "application/gzip" },
    .{ .ext = "bz2", .mime = "application/x-bzip2" },
    .{ .ext = "7z", .mime = "application/x-7z-compressed" },
    .{ .ext = "rar", .mime = "application/vnd.rar" },
    .{ .ext = "mp3", .mime = "audio/mpeg" },
    .{ .ext = "wav", .mime = "audio/wav" },
    .{ .ext = "ogg", .mime = "audio/ogg" },
    .{ .ext = "flac", .mime = "audio/flac" },
    .{ .ext = "mp4", .mime = "video/mp4" },
    .{ .ext = "webm", .mime = "video/webm" },
    .{ .ext = "mov", .mime = "video/quicktime" },
    .{ .ext = "avi", .mime = "video/x-msvideo" },
    .{ .ext = "doc", .mime = "application/msword" },
    .{ .ext = "docx", .mime = "application/vnd.openxmlformats-officedocument.wordprocessingml.document" },
    .{ .ext = "xls", .mime = "application/vnd.ms-excel" },
    .{ .ext = "xlsx", .mime = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" },
    .{ .ext = "ppt", .mime = "application/vnd.ms-powerpoint" },
    .{ .ext = "pptx", .mime = "application/vnd.openxmlformats-officedocument.presentationml.presentation" },
    .{ .ext = "ttf", .mime = "font/ttf" },
    .{ .ext = "otf", .mime = "font/otf" },
    .{ .ext = "woff", .mime = "font/woff" },
    .{ .ext = "woff2", .mime = "font/woff2" },
    .{ .ext = "wasm", .mime = "application/wasm" },
    .{ .ext = "phar", .mime = "application/x-php" },
    .{ .ext = "php", .mime = "application/x-php" },
};

fn mimeFromExt(path: []const u8) []const u8 {
    const dot = std.mem.lastIndexOfScalar(u8, path, '.') orelse return "application/octet-stream";
    const ext = path[dot + 1 ..];
    var lower_buf: [16]u8 = undefined;
    if (ext.len > lower_buf.len) return "application/octet-stream";
    for (ext, 0..) |c, i| lower_buf[i] = std.ascii.toLower(c);
    const lower = lower_buf[0..ext.len];
    for (mime_table) |entry| {
        if (std.mem.eql(u8, entry.ext, lower)) return entry.mime;
    }
    return "application/octet-stream";
}

fn detectMimeFromBytes(data: []const u8) ?[]const u8 {
    if (data.len >= 8 and std.mem.eql(u8, data[0..8], "\x89PNG\r\n\x1a\n")) return "image/png";
    if (data.len >= 3 and std.mem.eql(u8, data[0..3], "\xff\xd8\xff")) return "image/jpeg";
    if (data.len >= 6 and (std.mem.eql(u8, data[0..6], "GIF87a") or std.mem.eql(u8, data[0..6], "GIF89a"))) return "image/gif";
    if (data.len >= 4 and std.mem.eql(u8, data[0..4], "%PDF")) return "application/pdf";
    if (data.len >= 4 and std.mem.eql(u8, data[0..4], "PK\x03\x04")) return "application/zip";
    if (data.len >= 2 and std.mem.eql(u8, data[0..2], "\x1f\x8b")) return "application/gzip";
    if (data.len >= 4 and std.mem.eql(u8, data[0..4], "RIFF") and data.len >= 12 and std.mem.eql(u8, data[8..12], "WEBP")) return "image/webp";
    if (data.len >= 5 and std.mem.eql(u8, data[0..5], "<?xml")) return "text/xml";
    if (data.len >= 5 and std.mem.eql(u8, data[0..5], "<?php")) return "text/x-php";
    // text heuristic: all bytes printable ASCII or common whitespace
    if (data.len > 0) {
        for (data) |b| {
            if (b == '\t' or b == '\n' or b == '\r') continue;
            if (b < 0x20 or b > 0x7e) return null;
        }
        return "text/plain";
    }
    return null;
}

fn native_mime_content_type(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const path = args[0].string.bytes();
    const file = openWithMode(path, "r") catch {
        return try NativeResult.copyString(ctx.allocator, mimeFromExt(path));
    };
    defer file.close(platform.io);
    var buf: [16]u8 = undefined;
    const n = platform.read(file, &buf) catch return try NativeResult.copyString(ctx.allocator, mimeFromExt(path));
    if (detectMimeFromBytes(buf[0..n])) |m| return try NativeResult.copyString(ctx.allocator, m);
    return try NativeResult.copyString(ctx.allocator, mimeFromExt(path));
}

extern fn zphp_disk_space(path: [*:0]const u8, free_bytes: *u64, total_bytes: *u64) c_int;

fn native_disk_free_space(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const path_z = try ctx.allocator.allocSentinel(u8, args[0].string.bytes().len, 0);
    defer ctx.allocator.free(path_z);
    @memcpy(path_z[0..args[0].string.bytes().len], args[0].string.bytes());
    var free_bytes: u64 = 0;
    var total_bytes: u64 = 0;
    if (zphp_disk_space(path_z, &free_bytes, &total_bytes) != 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .float = @floatFromInt(free_bytes) });
}

fn native_disk_total_space(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const path_z = try ctx.allocator.allocSentinel(u8, args[0].string.bytes().len, 0);
    defer ctx.allocator.free(path_z);
    @memcpy(path_z[0..args[0].string.bytes().len], args[0].string.bytes());
    var free_bytes: u64 = 0;
    var total_bytes: u64 = 0;
    if (zphp_disk_space(path_z, &free_bytes, &total_bytes) != 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .float = @floatFromInt(total_bytes) });
}

// the device of the link itself, -1 with a warning when it cannot be lstat'ed
fn native_linkinfo(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const path = try strArg(ctx, args, "linkinfo", 0, "path", true);
    if (platform.is_windows) {
        const st = (if (path.len == 0) error.FileNotFound else platform.statPath(path)) catch |err| {
            try warn(ctx, "linkinfo(): {s}", .{errorText(err)});
            return NativeResult.scalar(.{ .int = -1 });
        };
        return NativeResult.scalar(.{ .int = @intCast(st.inode) });
    }
    const st = sys.lstat(path) catch {
        try warn(ctx, "linkinfo(): {s}", .{sys.errnoText()});
        return NativeResult.scalar(.{ .int = -1 });
    };
    return NativeResult.scalar(.{ .int = @bitCast(st.dev) });
}

fn native_finfo_open(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = try ctx.vm.allocObject(.{ .class_name = "finfo" });
    return NativeResult.borrowed(.{ .object = obj });
}

fn native_finfo_file(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    return native_mime_content_type(ctx, &.{args[1]});
}

fn native_finfo_buffer(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    if (detectMimeFromBytes(args[1].string.bytes())) |m| return try NativeResult.copyString(ctx.allocator, m);
    return NativeResult.literal("application/octet-stream");
}

fn native_finfo_close(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = true });
}

fn finfoConstruct(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.null);
}

fn finfoFile(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    return native_mime_content_type(ctx, args[0..1]);
}

fn finfoBuffer(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    if (detectMimeFromBytes(args[0].string.bytes())) |m| return try NativeResult.copyString(ctx.allocator, m);
    return NativeResult.literal("application/octet-stream");
}

fn finfoNoop(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = true });
}
