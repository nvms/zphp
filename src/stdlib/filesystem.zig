const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const phar = @import("phar.zig");
const zlib = @cImport(@cInclude("zlib.h"));

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
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
    .{ "readdir", native_readdir },
    .{ "closedir", native_closedir },
    .{ "rewinddir", native_rewinddir },
    .{ "file", native_file },
    .{ "readfile", native_readfile },
    .{ "is_readable", native_is_readable },
    .{ "is_writable", native_is_writable },
    .{ "is_writeable", native_is_writable },
    .{ "filesize", native_filesize },
    .{ "filemtime", native_filemtime },
    .{ "filetype", native_filetype },
    .{ "fileinode", native_fileinode },
    .{ "fopen", native_fopen },
    .{ "fclose", native_fclose },
    .{ "fread", native_fread },
    .{ "fwrite", native_fwrite },
    .{ "fputs", native_fwrite },
    .{ "fpassthru", native_fpassthru },
    .{ "fgets", native_fgets },
    .{ "fgetc", native_fgetc },
    .{ "feof", native_feof },
    .{ "fseek", native_fseek },
    .{ "ftell", native_ftell },
    .{ "rewind", native_rewind },
    .{ "fflush", native_fflush },
    .{ "ftruncate", native_ftruncate },
    .{ "flock", native_flock },
    .{ "fgetcsv", native_fgetcsv },
    .{ "fputcsv", native_fputcsv },
    .{ "stream_get_meta_data", stream_get_meta_data },
    .{ "stream_get_wrappers", stream_get_wrappers },
    .{ "stream_wrapper_register", stream_wrapper_register },
    .{ "stream_wrapper_unregister", stream_wrapper_unregister },
    .{ "stream_wrapper_restore", stream_wrapper_restore },
    .{ "fstat", native_fstat },
    .{ "stream_get_contents", stream_get_contents },
    .{ "stream_copy_to_stream", stream_copy_to_stream },
    .{ "touch", native_touch },
    .{ "chmod", native_chmod },
    .{ "stat", native_stat },
    .{ "chdir", native_chdir },
    .{ "stream_resolve_include_path", native_stream_resolve_include_path },
    .{ "stream_isatty", native_stream_isatty },
    .{ "stream_set_chunk_size", native_stream_set_chunk_size },
    .{ "stream_set_read_buffer", native_stream_set_buffer },
    .{ "stream_set_write_buffer", native_stream_set_buffer },
    .{ "clearstatcache", native_clearstatcache },
    .{ "tempnam", native_tempnam },
    .{ "tmpfile", native_tmpfile },
    .{ "umask", native_umask },
    .{ "fileperms", native_fileperms },
    .{ "fileowner", native_fileowner },
    .{ "filegroup", native_filegroup },
    .{ "is_link", native_is_link },
    .{ "readlink", native_readlink },
    .{ "symlink", native_symlink },
    .{ "link", native_link },
    .{ "lstat", native_lstat },
    .{ "popen", native_popen },
    .{ "pclose", native_pclose },
    .{ "proc_open", native_proc_open },
    .{ "proc_close", native_proc_close },
    .{ "proc_get_status", native_proc_get_status },
    .{ "proc_terminate", native_proc_terminate },
    .{ "stream_set_blocking", native_stream_set_blocking },
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

pub fn register(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "FileHandle" };
    try def.methods.put(a, "__toString", .{ .name = "__toString", .arity = 0 });
    try vm.classes.put(a, "FileHandle", def);

    inline for (.{ .{ "STDIN", 0, "r" }, .{ "STDOUT", 1, "w" }, .{ "STDERR", 2, "w" } }) |spec| {
        const obj = try a.create(PhpObject);
        obj.* = .{ .class_name = "FileHandle" };
        try obj.set(a, "__fd", .{ .int = spec[1] });
        try obj.set(a, "__open", .{ .bool = true });
        try obj.set(a, "__mode", .{ .string = spec[2] });
        try vm.objects.append(a, obj);
        try vm.php_constants.put(a, spec[0], .{ .object = obj });
    }
}

fn getFileHandle(obj: *PhpObject) ?std.fs.File {
    const v = obj.get("__fd");
    if (v != .int or v.int < 0) return null;
    return std.fs.File{ .handle = @intCast(v.int) };
}

fn getBufferBacking(obj: *PhpObject) ?[]const u8 {
    const v = obj.get("__buffer");
    if (v != .string) return null;
    return v.string;
}

fn getBufferPos(obj: *PhpObject) usize {
    const v = obj.get("__pos");
    if (v != .int or v.int < 0) return 0;
    return @intCast(v.int);
}

fn setBufferPos(obj: *PhpObject, pos: usize) void {
    obj.properties.put(std.heap.page_allocator, "__pos", .{ .int = @intCast(pos) }) catch {};
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
    var buf = std.ArrayListUnmanaged(u8){};
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

fn base64DecodeBytes(a: Allocator, s: []const u8) !?[]u8 {
    var clean = std.ArrayListUnmanaged(u8){};
    defer clean.deinit(a);
    for (s) |c| {
        if (c == ' ' or c == '\n' or c == '\r' or c == '\t') continue;
        try clean.append(a, c);
    }
    const decoder = std.base64.standard.Decoder;
    const dest_len = decoder.calcSizeForSlice(clean.items) catch return null;
    const out = try a.alloc(u8, dest_len);
    decoder.decode(out, clean.items) catch {
        a.free(out);
        return null;
    };
    return out;
}

const PharResolved = struct {
    archive_path: []const u8, // slice into input - not owned
    internal_path: []const u8, // slice into input - not owned
};

// resolves "phar:///abs/path/to/file.phar/internal/dir/file.txt" by walking
// path components from longest to shortest until one names a real file on disk.
// PHP allows phars without a .phar extension, so we can't shortcut on suffix
fn resolvePharPath(path: []const u8) ?PharResolved {
    if (!std.mem.startsWith(u8, path, "phar://")) return null;
    const tail = path[7..];
    var split: usize = tail.len;
    while (split > 0) {
        // find the next slash from the right
        while (split > 0 and tail[split - 1] != '/') split -= 1;
        if (split == 0) break;
        const candidate = tail[0 .. split - 1];
        const stat = std.fs.cwd().statFile(candidate) catch {
            split -= 1;
            continue;
        };
        if (stat.kind == .file) {
            return .{ .archive_path = candidate, .internal_path = tail[split..] };
        }
        split -= 1;
    }
    // try the whole tail as an archive (no internal path)
    if (std.fs.cwd().statFile(tail)) |st| {
        if (st.kind == .file) return .{ .archive_path = tail, .internal_path = "" };
    } else |_| {}
    return null;
}

// loads and parses a phar from disk. caller owns returned bytes and must
// also call phar.deinit on the returned Phar with the same allocator
const PharLoaded = struct {
    bytes: []u8,
    parsed: phar.Phar,
};

fn loadPhar(a: Allocator, archive_path: []const u8) !PharLoaded {
    const bytes = try std.fs.cwd().readFileAlloc(a, archive_path, 256 * 1024 * 1024);
    errdefer a.free(bytes);
    const parsed = try phar.parse(a, bytes);
    return .{ .bytes = bytes, .parsed = parsed };
}

fn freePhar(a: Allocator, loaded: *PharLoaded) void {
    loaded.parsed.deinit(a);
    a.free(loaded.bytes);
}

// returns the raw decoded contents of the file at internal_path, or null if missing
fn readPharEntry(a: Allocator, archive_path: []const u8, internal_path: []const u8) !?[]u8 {
    var loaded = loadPhar(a, archive_path) catch return null;
    defer freePhar(a, &loaded);
    const entry = loaded.parsed.lookup(internal_path) orelse return null;
    return try phar.extract(a, &loaded.parsed, entry);
}

// parses "data://[mediatype][;base64],<data>" into the decoded byte payload.
// returns null on malformed input (no comma, bad base64)
fn parseDataUri(a: Allocator, path: []const u8) !?[]u8 {
    if (!std.mem.startsWith(u8, path, "data://")) return null;
    const rest = path[7..];
    const comma = std.mem.indexOfScalar(u8, rest, ',') orelse return null;
    const meta = rest[0..comma];
    const data = rest[comma + 1 ..];
    const is_base64 = std.mem.endsWith(u8, meta, ";base64");
    const decoded = try percentDecode(a, data);
    if (!is_base64) return decoded;
    defer a.free(decoded);
    return try base64DecodeBytes(a, decoded);
}

pub fn cleanupHandles(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    for (objects.items) |obj| {
        if (std.mem.eql(u8, obj.class_name, "FileHandle")) {
            const open = obj.get("__open");
            if (open == .bool and open.bool) {
                if (getFileHandle(obj)) |file| {
                    // never close stdin/stdout/stderr - they belong to the host
                    if (file.handle > 2) {
                        // use raw syscall to avoid panic on invalid fd
                        _ = std.posix.system.close(file.handle);
                    }
                }
                obj.properties.put(std.heap.page_allocator, "__open", .{ .bool = false }) catch {};
            }
        }
    }
}

// file read/write

const c_curl = @cImport({
    @cInclude("curl/curl.h");
});

var curl_global_init_done: bool = false;

const CurlWriteData = struct {
    allocator: Allocator,
    buffer: std.ArrayListUnmanaged(u8),
};

fn curlWriteCallback(data: [*]u8, size: usize, nmemb: usize, userdata: *anyopaque) callconv(.c) usize {
    const total = size * nmemb;
    const wd: *CurlWriteData = @ptrCast(@alignCast(userdata));
    wd.buffer.appendSlice(wd.allocator, data[0..total]) catch return 0;
    return total;
}

fn fetchUrl(ctx: *NativeContext, url: []const u8) RuntimeError!Value {
    if (!curl_global_init_done) {
        _ = c_curl.curl_global_init(c_curl.CURL_GLOBAL_DEFAULT);
        curl_global_init_done = true;
    }

    const handle = c_curl.curl_easy_init() orelse return .{ .bool = false };
    defer c_curl.curl_easy_cleanup(handle);

    var url_buf: [8192]u8 = undefined;
    if (url.len >= url_buf.len) return .{ .bool = false };
    @memcpy(url_buf[0..url.len], url);
    url_buf[url.len] = 0;

    _ = c_curl.curl_easy_setopt(handle, c_curl.CURLOPT_URL, &url_buf);
    _ = c_curl.curl_easy_setopt(handle, c_curl.CURLOPT_FOLLOWLOCATION, @as(c_long, 1));
    _ = c_curl.curl_easy_setopt(handle, c_curl.CURLOPT_MAXREDIRS, @as(c_long, 10));

    var wd = CurlWriteData{
        .allocator = ctx.allocator,
        .buffer = .{},
    };
    defer wd.buffer.deinit(wd.allocator);

    _ = c_curl.curl_easy_setopt(handle, c_curl.CURLOPT_WRITEFUNCTION, @as(?*const fn ([*]u8, usize, usize, *anyopaque) callconv(.c) usize, &curlWriteCallback));
    _ = c_curl.curl_easy_setopt(handle, c_curl.CURLOPT_WRITEDATA, @as(*anyopaque, @ptrCast(&wd)));

    const result = c_curl.curl_easy_perform(handle);
    if (result != c_curl.CURLE_OK) return .{ .bool = false };

    const content = try ctx.createString(wd.buffer.items);
    return .{ .string = content };
}

fn native_file_get_contents(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const path = args[0].string;
    if (userWrapperFor(ctx.vm, path)) |class_name| {
        const opened = (try dispatchUserOpen(ctx, class_name, path, "rb")) orelse return Value{ .bool = false };
        const fh = opened.object;
        const wrapper = fileHandleWrapper(fh) orelse return .{ .bool = false };
        var buf = std.ArrayListUnmanaged(u8){};
        defer buf.deinit(ctx.allocator);
        while (true) {
            const chunk = try ctx.callMethod(wrapper, "stream_read", &[_]Value{.{ .int = 8192 }});
            if (chunk != .string or chunk.string.len == 0) break;
            try buf.appendSlice(ctx.allocator, chunk.string);
        }
        if (ctx.vm.hasMethod(fh.class_name, "stream_close") or ctx.vm.hasMethod(wrapper.class_name, "stream_close")) {
            _ = try ctx.callMethod(wrapper, "stream_close", &.{});
        }
        const owned = try buf.toOwnedSlice(ctx.allocator);
        try ctx.strings.append(ctx.allocator, owned);
        return .{ .string = owned };
    }
    if (extractScheme(path)) |s| {
        if (isBuiltinWrapper(s) and isWrapperUnregistered(ctx.vm, s)) return .{ .bool = false };
    }
    if (std.mem.eql(u8, path, "php://input")) {
        const body_val = ctx.vm.request_vars.get("__raw_body") orelse return .{ .string = "" };
        if (body_val == .string) return body_val;
        return .{ .string = "" };
    }
    if (std.mem.eql(u8, path, "php://stdin")) {
        const stdin = std.fs.File{ .handle = 0 };
        const data = stdin.readToEndAlloc(ctx.allocator, 1024 * 1024 * 64) catch return Value{ .bool = false };
        try ctx.strings.append(ctx.allocator, data);
        return .{ .string = data };
    }
    if (std.mem.eql(u8, path, "php://stdout") or std.mem.eql(u8, path, "php://output") or std.mem.eql(u8, path, "php://stderr")) {
        return .{ .string = "" };
    }
    if (std.mem.startsWith(u8, path, "data://")) {
        const payload = (parseDataUri(ctx.allocator, path) catch return Value{ .bool = false }) orelse return Value{ .bool = false };
        try ctx.strings.append(ctx.allocator, payload);
        return .{ .string = payload };
    }
    if (std.mem.startsWith(u8, path, "phar://")) {
        const r = resolvePharPath(path) orelse return .{ .bool = false };
        const payload = (readPharEntry(ctx.allocator, r.archive_path, r.internal_path) catch return Value{ .bool = false }) orelse return Value{ .bool = false };
        try ctx.strings.append(ctx.allocator, payload);
        return .{ .string = payload };
    }
    if (std.mem.startsWith(u8, path, ZLIB_PREFIX)) {
        const decoded = readZlibFile(ctx.allocator, path) catch return Value{ .bool = false };
        try ctx.strings.append(ctx.allocator, decoded);
        return .{ .string = decoded };
    }
    if (path.len > 7 and (std.mem.startsWith(u8, path, "http://") or std.mem.startsWith(u8, path, "https://"))) {
        return fetchUrl(ctx, path);
    }
    const content = std.fs.cwd().readFileAlloc(ctx.allocator, path, 1024 * 1024 * 64) catch return Value{ .bool = false };
    try ctx.strings.append(ctx.allocator, content);

    // optional offset (4th arg) and length (5th arg)
    if (args.len >= 4 and args[3] != .null) {
        const total_i: i64 = @intCast(content.len);
        var offset = Value.toInt(args[3]);
        if (offset < 0) offset = @max(0, total_i + offset);
        if (offset > total_i) offset = total_i;
        const ustart: usize = @intCast(offset);
        const have_len = args.len >= 5 and args[4] != .null;
        const length: i64 = if (have_len) Value.toInt(args[4]) else total_i - offset;
        if (length < 0) return .{ .bool = false };
        const end = @min(content.len, ustart + @as(usize, @intCast(length)));
        const slice = try ctx.allocator.dupe(u8, content[ustart..end]);
        try ctx.strings.append(ctx.allocator, slice);
        return .{ .string = slice };
    }

    return .{ .string = content };
}

fn native_file_put_contents(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string) return .{ .bool = false };
    const path = args[0].string;
    const data = if (args[1] == .string) args[1].string else blk: {
        var buf = std.ArrayListUnmanaged(u8){};
        try args[1].format(&buf, ctx.allocator);
        const s = try buf.toOwnedSlice(ctx.allocator);
        try ctx.strings.append(ctx.allocator, s);
        break :blk s;
    };
    if (userWrapperFor(ctx.vm, path)) |class_name| {
        const opened = (try dispatchUserOpen(ctx, class_name, path, "wb")) orelse return Value{ .bool = false };
        const wrapper = fileHandleWrapper(opened.object) orelse return .{ .bool = false };
        const written = try ctx.callMethod(wrapper, "stream_write", &[_]Value{.{ .string = data }});
        if (ctx.vm.hasMethod(wrapper.class_name, "stream_close")) {
            _ = try ctx.callMethod(wrapper, "stream_close", &.{});
        }
        if (written != .int) return .{ .bool = false };
        return .{ .int = written.int };
    }
    if (extractScheme(path)) |s| {
        if (isBuiltinWrapper(s) and isWrapperUnregistered(ctx.vm, s)) return .{ .bool = false };
    }
    if (std.mem.eql(u8, path, "php://stdout") or std.mem.eql(u8, path, "php://output")) {
        try ctx.vm.output.appendSlice(ctx.allocator, data);
        return .{ .int = @intCast(data.len) };
    }
    if (std.mem.eql(u8, path, "php://stderr")) {
        if (ctx.vm.output.items.len > 0) {
            const stdout = std.fs.File{ .handle = 1 };
            _ = stdout.write(ctx.vm.output.items) catch {};
            ctx.vm.output.clearRetainingCapacity();
        }
        const stderr = std.fs.File{ .handle = 2 };
        const n = stderr.write(data) catch return Value{ .bool = false };
        return .{ .int = @intCast(n) };
    }
    if (std.mem.startsWith(u8, path, ZLIB_PREFIX)) {
        writeZlibFile(ctx.allocator, path, data) catch return Value{ .bool = false };
        return .{ .int = @intCast(data.len) };
    }
    const flags: i64 = if (args.len >= 3) Value.toInt(args[2]) else 0;
    const append = (flags & 8) != 0; // FILE_APPEND = 8
    if (append) {
        const file = std.fs.cwd().openFile(path, .{ .mode = .write_only }) catch {
            std.fs.cwd().writeFile(.{ .sub_path = path, .data = data }) catch return Value{ .bool = false };
            return .{ .int = @intCast(data.len) };
        };
        defer file.close();
        file.seekFromEnd(0) catch return Value{ .bool = false };
        _ = file.write(data) catch return Value{ .bool = false };
    } else {
        std.fs.cwd().writeFile(.{ .sub_path = path, .data = data }) catch return Value{ .bool = false };
    }
    return .{ .int = @intCast(data.len) };
}

fn native_file_exists(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const path = args[0].string;
    if (userWrapperFor(ctx.vm, path)) |class_name| {
        const arr = try dispatchUserStat(ctx, class_name, path, 0);
        return .{ .bool = arr != null };
    }
    if (extractScheme(path)) |s| {
        if (isBuiltinWrapper(s) and isWrapperUnregistered(ctx.vm, s)) return .{ .bool = false };
    }
    if (std.mem.startsWith(u8, path, "phar://")) {
        const r = resolvePharPath(path) orelse return .{ .bool = false };
        if (r.internal_path.len == 0) return .{ .bool = true }; // archive itself
        var loaded = loadPhar(ctx.allocator, r.archive_path) catch return Value{ .bool = false };
        defer freePhar(ctx.allocator, &loaded);
        if (loaded.parsed.lookup(r.internal_path) != null) return .{ .bool = true };
        return .{ .bool = loaded.parsed.isDir(r.internal_path) };
    }
    if (std.mem.startsWith(u8, path, ZLIB_PREFIX)) {
        std.fs.cwd().access(path[ZLIB_PREFIX.len..], .{}) catch return Value{ .bool = false };
        return .{ .bool = true };
    }
    std.fs.cwd().access(path, .{}) catch return Value{ .bool = false };
    return .{ .bool = true };
}

fn native_is_file(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const path = args[0].string;
    if (userWrapperFor(ctx.vm, path)) |class_name| {
        const arr = (try dispatchUserStat(ctx, class_name, path, 0)) orelse return .{ .bool = false };
        const mode_v = arr.get(.{ .string = "mode" });
        if (mode_v != .int) return .{ .bool = false };
        return .{ .bool = (mode_v.int & 0o170000) == 0o100000 };
    }
    if (extractScheme(path)) |s| {
        if (isBuiltinWrapper(s) and isWrapperUnregistered(ctx.vm, s)) return .{ .bool = false };
    }
    if (std.mem.startsWith(u8, path, "phar://")) {
        const r = resolvePharPath(path) orelse return .{ .bool = false };
        if (r.internal_path.len == 0) return .{ .bool = true };
        var loaded = loadPhar(ctx.allocator, r.archive_path) catch return Value{ .bool = false };
        defer freePhar(ctx.allocator, &loaded);
        return .{ .bool = loaded.parsed.lookup(r.internal_path) != null };
    }
    if (std.mem.startsWith(u8, path, ZLIB_PREFIX)) {
        const stat = std.fs.cwd().statFile(path[ZLIB_PREFIX.len..]) catch return Value{ .bool = false };
        return .{ .bool = stat.kind == .file };
    }
    const stat = std.fs.cwd().statFile(path) catch return Value{ .bool = false };
    return .{ .bool = stat.kind == .file };
}

fn native_is_dir(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const path = args[0].string;
    if (userWrapperFor(ctx.vm, path)) |class_name| {
        const arr = (try dispatchUserStat(ctx, class_name, path, 0)) orelse return .{ .bool = false };
        const mode_v = arr.get(.{ .string = "mode" });
        if (mode_v != .int) return .{ .bool = false };
        return .{ .bool = (mode_v.int & 0o170000) == 0o040000 };
    }
    if (extractScheme(path)) |s| {
        if (isBuiltinWrapper(s) and isWrapperUnregistered(ctx.vm, s)) return .{ .bool = false };
    }
    if (std.mem.startsWith(u8, path, "phar://")) {
        const r = resolvePharPath(path) orelse return .{ .bool = false };
        if (r.internal_path.len == 0) return .{ .bool = false }; // the archive is a file, not a dir
        var loaded = loadPhar(ctx.allocator, r.archive_path) catch return Value{ .bool = false };
        defer freePhar(ctx.allocator, &loaded);
        return .{ .bool = loaded.parsed.isDir(r.internal_path) };
    }
    var dir = std.fs.cwd().openDir(path, .{}) catch return Value{ .bool = false };
    dir.close();
    return .{ .bool = true };
}

fn native_basename(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .string = "" };
    var path = args[0].string;
    const suffix = if (args.len >= 2 and args[1] == .string) args[1].string else "";
    // PHP strips trailing slashes before extracting the last segment
    while (path.len > 1 and path[path.len - 1] == '/') path = path[0 .. path.len - 1];
    var name: []const u8 = path;
    if (std.mem.lastIndexOf(u8, path, "/")) |pos| {
        name = path[pos + 1 ..];
    }
    if (suffix.len > 0 and name.len > suffix.len and std.mem.endsWith(u8, name, suffix)) {
        name = name[0 .. name.len - suffix.len];
    }
    return .{ .string = try ctx.createString(name) };
}

fn native_dirname(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .string = "" };
    var path = args[0].string;
    var levels: i64 = if (args.len >= 2) Value.toInt(args[1]) else 1;
    if (levels <= 0) return .{ .string = try ctx.createString(path) };
    while (levels > 0) : (levels -= 1) {
        while (path.len > 1 and path[path.len - 1] == '/') path = path[0 .. path.len - 1];
        if (std.mem.lastIndexOf(u8, path, "/")) |pos| {
            if (pos == 0) {
                path = "/";
                break;
            }
            path = path[0..pos];
        } else {
            path = ".";
            break;
        }
    }
    return .{ .string = try ctx.createString(path) };
}

fn native_pathinfo(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .null;
    const path = args[0].string;

    const dir: []const u8 = if (std.mem.lastIndexOf(u8, path, "/")) |pos|
        (if (pos == 0) "/" else try ctx.createString(path[0..pos]))
    else
        ".";
    const base: []const u8 = if (std.mem.lastIndexOf(u8, path, "/")) |pos| try ctx.createString(path[pos + 1 ..]) else path;
    const has_dot = std.mem.lastIndexOf(u8, base, ".") != null;
    const dot_pos: usize = if (has_dot) std.mem.lastIndexOf(u8, base, ".").? else 0;
    const ext: []const u8 = if (has_dot) try ctx.createString(base[dot_pos + 1 ..]) else "";
    const filename: []const u8 = if (has_dot) try ctx.createString(base[0..dot_pos]) else base;

    if (args.len >= 2 and args[1] == .int) {
        const flag = args[1].int;
        return switch (flag) {
            1 => .{ .string = dir },
            2 => .{ .string = base },
            4 => .{ .string = ext },
            8 => .{ .string = filename },
            else => .null,
        };
    }

    var arr = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .string = "dirname" }, .{ .string = dir });
    try arr.set(ctx.allocator, .{ .string = "basename" }, .{ .string = base });
    if (has_dot) {
        try arr.set(ctx.allocator, .{ .string = "extension" }, .{ .string = ext });
    }
    try arr.set(ctx.allocator, .{ .string = "filename" }, .{ .string = filename });
    return .{ .array = arr };
}

fn native_realpath(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const resolved = std.fs.cwd().realpath(args[0].string, &buf) catch return Value{ .bool = false };
    return .{ .string = try ctx.createString(resolved) };
}

// directory operations

fn native_mkdir(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const path = args[0].string;
    const recursive = args.len >= 3 and args[2].isTruthy();
    if (recursive) {
        std.fs.cwd().makePath(path) catch return Value{ .bool = false };
    } else {
        std.fs.cwd().makeDir(path) catch return Value{ .bool = false };
    }
    return .{ .bool = true };
}

fn native_rmdir(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    std.fs.cwd().deleteDir(args[0].string) catch return Value{ .bool = false };
    return .{ .bool = true };
}

fn native_unlink(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const path = args[0].string;
    if (userWrapperFor(ctx.vm, path)) |class_name| {
        if (!ctx.vm.hasMethod(class_name, "unlink")) return .{ .bool = false };
        const wrapper = try ctx.createObject(class_name);
        if (ctx.vm.hasMethod(class_name, "__construct")) {
            _ = try ctx.callMethod(wrapper, "__construct", &.{});
        }
        const result = try ctx.callMethod(wrapper, "unlink", &[_]Value{.{ .string = path }});
        return .{ .bool = result.isTruthy() };
    }
    if (extractScheme(path)) |s| {
        if (isBuiltinWrapper(s) and isWrapperUnregistered(ctx.vm, s)) return .{ .bool = false };
    }
    std.fs.cwd().deleteFile(path) catch return Value{ .bool = false };
    return .{ .bool = true };
}

fn native_copy(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    std.fs.cwd().copyFile(args[0].string, std.fs.cwd(), args[1].string, .{}) catch return Value{ .bool = false };
    return .{ .bool = true };
}

fn native_rename(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    std.fs.cwd().rename(args[0].string, args[1].string) catch return Value{ .bool = false };
    return .{ .bool = true };
}

// directory listing

fn native_scandir(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    // SCANDIR_SORT_ASCENDING=0, _DESCENDING=1, _NONE=2
    const order: i64 = if (args.len >= 2 and args[1] == .int) args[1].int else 0;
    var dir = std.fs.cwd().openDir(args[0].string, .{ .iterate = true }) catch return Value{ .bool = false };
    defer dir.close();

    var names = std.ArrayListUnmanaged([]const u8){};
    defer names.deinit(ctx.allocator);
    try names.append(ctx.allocator, ".");
    try names.append(ctx.allocator, "..");

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        const name = try ctx.createString(entry.name);
        try names.append(ctx.allocator, name);
    }

    if (order == 0 or order == 1) {
        const lessAsc = struct {
            fn f(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.order(u8, a, b) == .lt;
            }
        }.f;
        const lessDesc = struct {
            fn f(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.order(u8, a, b) == .gt;
            }
        }.f;
        if (order == 0) std.mem.sort([]const u8, names.items, {}, lessAsc) else std.mem.sort([]const u8, names.items, {}, lessDesc);
    }

    var result = try ctx.createArray();
    for (names.items) |n| try result.append(ctx.allocator, .{ .string = n });
    return .{ .array = result };
}

fn native_opendir(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    var dir = std.fs.cwd().openDir(args[0].string, .{ .iterate = true }) catch return Value{ .bool = false };
    defer dir.close();
    const names_arr = try ctx.allocator.create(PhpArray);
    names_arr.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, names_arr);
    try names_arr.append(ctx.allocator, .{ .string = "." });
    try names_arr.append(ctx.allocator, .{ .string = ".." });
    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        const name = try ctx.createString(entry.name);
        try names_arr.append(ctx.allocator, .{ .string = name });
    }
    const obj = try ctx.allocator.create(PhpObject);
    obj.* = .{ .class_name = "DirectoryHandle" };
    try obj.set(ctx.allocator, "__entries", .{ .array = names_arr });
    try obj.set(ctx.allocator, "__pos", .{ .int = 0 });
    try obj.set(ctx.allocator, "__open", .{ .bool = true });
    try ctx.vm.objects.append(ctx.allocator, obj);
    return .{ .object = obj };
}

fn native_readdir(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .{ .bool = false };
    const obj = args[0].object;
    const open = obj.get("__open");
    if (open != .bool or !open.bool) return .{ .bool = false };
    const dir_entries = obj.get("__entries");
    if (dir_entries != .array) return .{ .bool = false };
    const pos = Value.toInt(obj.get("__pos"));
    if (pos < 0 or pos >= dir_entries.array.length()) return .{ .bool = false };
    const entry = dir_entries.array.entries.items[@intCast(pos)].value;
    try obj.set(ctx.allocator, "__pos", .{ .int = pos + 1 });
    return entry;
}

fn native_closedir(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .null;
    const obj = args[0].object;
    try obj.set(ctx.allocator, "__open", .{ .bool = false });
    return .null;
}

fn native_rewinddir(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .null;
    const obj = args[0].object;
    try obj.set(ctx.allocator, "__pos", .{ .int = 0 });
    return .null;
}

fn native_fnmatch(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const flags: i64 = if (args.len >= 3) Value.toInt(args[2]) else 0;
    return .{ .bool = globMatchFlags(args[0].string, args[1].string, flags) };
}

fn native_glob(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const pattern = args[0].string;
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
                return .{ .array = result };
            }
        }
    }

    try globAppend(ctx, result, pattern, flags);
    if ((flags & GLOB_NOSORT) == 0) sortArrayValues(result);
    _ = GLOB_ONLYDIR;
    return .{ .array = result };
}

fn globAppend(ctx: *NativeContext, result: *PhpArray, pattern: []const u8, flags: i64) !void {
    const GLOB_ONLYDIR: i64 = 1073741824;
    const GLOB_MARK: i64 = 8;
    const FNM_PERIOD: i64 = 4;
    const dir_path = if (std.mem.lastIndexOf(u8, pattern, "/")) |pos| pattern[0..pos] else ".";
    const file_pattern = if (std.mem.lastIndexOf(u8, pattern, "/")) |pos| pattern[pos + 1 ..] else pattern;
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
    defer dir.close();
    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        // glob excludes dotfiles unless the pattern explicitly starts with '.'
        if (!globMatchFlags(file_pattern, entry.name, FNM_PERIOD)) continue;
        if ((flags & GLOB_ONLYDIR) != 0 and entry.kind != .directory) continue;
        var path_buf: [4096]u8 = undefined;
        const slash: []const u8 = if ((flags & GLOB_MARK) != 0 and entry.kind == .directory) "/" else "";
        const full = std.fmt.bufPrint(&path_buf, "{s}/{s}{s}", .{ dir_path, entry.name, slash }) catch continue;
        try result.append(ctx.allocator, .{ .string = try ctx.createString(full) });
    }
}

fn sortArrayValues(arr: *PhpArray) void {
    const items = arr.entries.items;
    const Entry = PhpArray.Entry;
    std.sort.pdq(Entry, items, {}, struct {
        fn lt(_: void, a: Entry, b: Entry) bool {
            if (a.value != .string or b.value != .string) return false;
            return std.mem.order(u8, a.value.string, b.value.string) == .lt;
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

fn native_is_readable(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    std.fs.cwd().access(args[0].string, .{ .mode = .read_only }) catch return Value{ .bool = false };
    return .{ .bool = true };
}

fn native_is_writable(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const path = args[0].string;
    std.posix.access(path, std.posix.W_OK) catch return Value{ .bool = false };
    return .{ .bool = true };
}

fn native_filesize(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const stat = std.fs.cwd().statFile(args[0].string) catch return Value{ .bool = false };
    return .{ .int = @intCast(stat.size) };
}

fn native_filemtime(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const stat = std.fs.cwd().statFile(args[0].string) catch return Value{ .bool = false };
    return .{ .int = @intCast(@divFloor(stat.mtime, 1_000_000_000)) };
}

fn native_fileinode(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const stat = std.fs.cwd().statFile(args[0].string) catch return Value{ .bool = false };
    return .{ .int = @intCast(stat.inode) };
}

fn native_filetype(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const stat = std.fs.cwd().statFile(args[0].string) catch {
        // might be a directory
        var dir = std.fs.cwd().openDir(args[0].string, .{}) catch return Value{ .bool = false };
        dir.close();
        return .{ .string = "dir" };
    };
    return .{ .string = switch (stat.kind) {
        .file => "file",
        .directory => "dir",
        .sym_link => "link",
        else => "unknown",
    } };
}

// read file into array of lines

fn native_file(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const content = std.fs.cwd().readFileAlloc(ctx.allocator, args[0].string, 1024 * 1024 * 64) catch return Value{ .bool = false };
    try ctx.strings.append(ctx.allocator, content);

    const flags: i64 = if (args.len >= 2) Value.toInt(args[1]) else 0;
    const ignore_newlines = (flags & 2) != 0; // FILE_IGNORE_NEW_LINES = 2
    const skip_empty = (flags & 4) != 0; // FILE_SKIP_EMPTY_LINES = 4

    var result = try ctx.createArray();
    var start: usize = 0;
    for (content, 0..) |c, i| {
        if (c == '\n') {
            const end = if (ignore_newlines) i else i + 1;
            const line_data = content[start..end];
            if (skip_empty and (line_data.len == 0 or (line_data.len == 1 and (line_data[0] == '\n' or line_data[0] == '\r')))) {
                start = i + 1;
                continue;
            }
            const line = try ctx.createString(line_data);
            try result.append(ctx.allocator, .{ .string = line });
            start = i + 1;
        }
    }
    if (start < content.len) {
        const remaining = content[start..];
        if (!skip_empty or remaining.len > 0) {
            const line = try ctx.createString(remaining);
            try result.append(ctx.allocator, .{ .string = line });
        }
    }
    return .{ .array = result };
}

fn native_readfile(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const content = std.fs.cwd().readFileAlloc(ctx.allocator, args[0].string, 1024 * 1024 * 64) catch return Value{ .bool = false };
    defer ctx.allocator.free(content);
    try ctx.vm.output.appendSlice(ctx.allocator, content);
    return .{ .int = @intCast(content.len) };
}

// file handle operations (fopen/fclose/fread/fwrite/fgets/feof/fseek/ftell)

fn native_fopen(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const path = args[0].string;
    const mode = args[1].string;

    if (userWrapperFor(ctx.vm, path)) |class_name| {
        return (try dispatchUserOpen(ctx, class_name, path, mode)) orelse Value{ .bool = false };
    }
    if (extractScheme(path)) |s| {
        if (isBuiltinWrapper(s) and isWrapperUnregistered(ctx.vm, s)) return .{ .bool = false };
    }

    if (std.mem.eql(u8, path, "php://stdout") or std.mem.eql(u8, path, "php://output")) {
        const obj = try ctx.allocator.create(PhpObject);
        obj.* = .{ .class_name = "FileHandle" };
        try obj.set(ctx.allocator, "__fd", .{ .int = 1 });
        try obj.set(ctx.allocator, "__open", .{ .bool = true });
        try obj.set(ctx.allocator, "__mode", .{ .string = "w" });
        try ctx.vm.objects.append(ctx.allocator, obj);
        return .{ .object = obj };
    }
    if (std.mem.eql(u8, path, "php://stderr")) {
        const obj = try ctx.allocator.create(PhpObject);
        obj.* = .{ .class_name = "FileHandle" };
        try obj.set(ctx.allocator, "__fd", .{ .int = 2 });
        try obj.set(ctx.allocator, "__open", .{ .bool = true });
        try obj.set(ctx.allocator, "__mode", .{ .string = "w" });
        try ctx.vm.objects.append(ctx.allocator, obj);
        return .{ .object = obj };
    }
    if (std.mem.eql(u8, path, "php://stdin")) {
        const obj = try ctx.allocator.create(PhpObject);
        obj.* = .{ .class_name = "FileHandle" };
        try obj.set(ctx.allocator, "__fd", .{ .int = 0 });
        try obj.set(ctx.allocator, "__open", .{ .bool = true });
        try obj.set(ctx.allocator, "__mode", .{ .string = "r" });
        try ctx.vm.objects.append(ctx.allocator, obj);
        return .{ .object = obj };
    }
    if (std.mem.eql(u8, path, "php://input")) {
        const body_val = ctx.vm.request_vars.get("__raw_body");
        const body: []const u8 = if (body_val != null and body_val.? == .string) body_val.?.string else "";
        const obj = try ctx.allocator.create(PhpObject);
        obj.* = .{ .class_name = "FileHandle" };
        try obj.set(ctx.allocator, "__buffer", .{ .string = body });
        try obj.set(ctx.allocator, "__pos", .{ .int = 0 });
        try obj.set(ctx.allocator, "__open", .{ .bool = true });
        try obj.set(ctx.allocator, "__mode", .{ .string = "r" });
        try ctx.vm.objects.append(ctx.allocator, obj);
        return .{ .object = obj };
    }
    if (std.mem.startsWith(u8, path, "data://")) {
        const payload = (parseDataUri(ctx.allocator, path) catch return Value{ .bool = false }) orelse return Value{ .bool = false };
        try ctx.strings.append(ctx.allocator, payload);
        const obj = try ctx.allocator.create(PhpObject);
        obj.* = .{ .class_name = "FileHandle" };
        try obj.set(ctx.allocator, "__buffer", .{ .string = payload });
        try obj.set(ctx.allocator, "__pos", .{ .int = 0 });
        try obj.set(ctx.allocator, "__open", .{ .bool = true });
        try obj.set(ctx.allocator, "__mode", .{ .string = "r" });
        try ctx.vm.objects.append(ctx.allocator, obj);
        return .{ .object = obj };
    }
    if (std.mem.startsWith(u8, path, "phar://")) {
        const r = resolvePharPath(path) orelse return .{ .bool = false };
        const payload = (readPharEntry(ctx.allocator, r.archive_path, r.internal_path) catch return Value{ .bool = false }) orelse return Value{ .bool = false };
        try ctx.strings.append(ctx.allocator, payload);
        const obj = try ctx.allocator.create(PhpObject);
        obj.* = .{ .class_name = "FileHandle" };
        try obj.set(ctx.allocator, "__buffer", .{ .string = payload });
        try obj.set(ctx.allocator, "__pos", .{ .int = 0 });
        try obj.set(ctx.allocator, "__open", .{ .bool = true });
        try obj.set(ctx.allocator, "__mode", .{ .string = "r" });
        try ctx.vm.objects.append(ctx.allocator, obj);
        return .{ .object = obj };
    }
    if (std.mem.startsWith(u8, path, ZLIB_PREFIX)) {
        const is_write = mode.len >= 1 and (mode[0] == 'w' or mode[0] == 'a' or mode[0] == 'x');
        const obj = try ctx.allocator.create(PhpObject);
        obj.* = .{ .class_name = "FileHandle" };
        try obj.set(ctx.allocator, "__open", .{ .bool = true });
        try obj.set(ctx.allocator, "__mode", .{ .string = mode });
        try obj.set(ctx.allocator, "__zlib_path", .{ .string = try ctx.createString(path) });
        try ctx.vm.objects.append(ctx.allocator, obj);
        if (is_write) {
            try obj.set(ctx.allocator, "__zlib_writing", .{ .bool = true });
            try obj.set(ctx.allocator, "__buffer", .{ .string = "" });
            try obj.set(ctx.allocator, "__pos", .{ .int = 0 });
        } else {
            const decoded = readZlibFile(ctx.allocator, path) catch {
                obj.set(ctx.allocator, "__open", .{ .bool = false }) catch {};
                return .{ .bool = false };
            };
            try ctx.strings.append(ctx.allocator, decoded);
            try obj.set(ctx.allocator, "__buffer", .{ .string = decoded });
            try obj.set(ctx.allocator, "__pos", .{ .int = 0 });
        }
        return .{ .object = obj };
    }

    const file = if (std.mem.eql(u8, path, "php://temp") or std.mem.eql(u8, path, "php://memory")) blk: {
        const tmp = std.fmt.allocPrint(ctx.allocator, "/tmp/zphp_{d}", .{@as(u64, @truncate(@as(u128, @bitCast(std.time.nanoTimestamp()))))}) catch return Value{ .bool = false };
        defer ctx.allocator.free(tmp);
        const f = std.fs.cwd().createFile(tmp, .{ .read = true, .truncate = true }) catch return Value{ .bool = false };
        std.fs.cwd().deleteFile(tmp) catch {};
        break :blk f;
    } else
        openWithMode(path, mode) catch return Value{ .bool = false };

    const obj = try ctx.allocator.create(PhpObject);
    obj.* = .{ .class_name = "FileHandle" };
    try obj.set(ctx.allocator, "__fd", .{ .int = @intCast(file.handle) });
    try obj.set(ctx.allocator, "__open", .{ .bool = true });
    try obj.set(ctx.allocator, "__mode", .{ .string = mode });
    try obj.set(ctx.allocator, "__path", .{ .string = try ctx.createString(path) });
    try ctx.vm.objects.append(ctx.allocator, obj);
    return .{ .object = obj };
}

fn openWithMode(path: []const u8, mode: []const u8) !std.fs.File {
    if (mode.len == 0) return error.RuntimeError;
    const has_plus = mode.len > 1 and (mode[1] == '+' or (mode.len > 2 and mode[2] == '+'));
    return switch (mode[0]) {
        'r' => std.fs.cwd().openFile(path, .{ .mode = if (has_plus) .read_write else .read_only }),
        'w' => blk: {
            const file = std.fs.cwd().createFile(path, .{ .truncate = true, .read = has_plus }) catch |err| break :blk err;
            break :blk file;
        },
        'a' => blk: {
            const file = std.fs.cwd().openFile(path, .{ .mode = if (has_plus) .read_write else .write_only }) catch
                std.fs.cwd().createFile(path, .{ .read = has_plus }) catch |err| break :blk err;
            file.seekFromEnd(0) catch {};
            break :blk file;
        },
        'x' => std.fs.cwd().createFile(path, .{ .exclusive = true, .read = has_plus }),
        else => error.RuntimeError,
    };
}

fn native_fclose(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .{ .bool = false };
    const obj = args[0].object;
    if (!std.mem.eql(u8, obj.class_name, "FileHandle")) return .{ .bool = false };
    const open = obj.get("__open");
    if (open != .bool or !open.bool) {
        try ctx.vm.setPendingException("TypeError", "fclose(): Argument #1 ($stream) must be an open stream resource");
        return error.RuntimeError;
    }
    if (fileHandleWrapper(obj)) |wrapper| {
        if (ctx.vm.hasMethod(wrapper.class_name, "stream_close")) {
            _ = try ctx.callMethod(wrapper, "stream_close", &.{});
        }
        obj.properties.put(std.heap.page_allocator, "__open", .{ .bool = false }) catch {};
        return .{ .bool = true };
    }
    const popen_cmd = obj.get("__popen_cmd");
    if (popen_cmd == .string) {
        const buf_v_p = obj.get("__buffer");
        const data: []const u8 = if (buf_v_p == .string) buf_v_p.string else "";
        if (runShellCapture(ctx.allocator, popen_cmd.string, data)) |r| {
            ctx.allocator.free(r.stdout);
            ctx.allocator.free(r.stderr);
        } else |_| {}
        obj.properties.put(std.heap.page_allocator, "__open", .{ .bool = false }) catch {};
        obj.properties.put(std.heap.page_allocator, "__popen_cmd", .null) catch {};
        return .{ .bool = true };
    }
    if (isZlibWriting(obj)) {
        const path_v = obj.get("__zlib_path");
        const buf_v = obj.get("__buffer");
        if (path_v == .string and buf_v == .string) {
            writeZlibFile(ctx.allocator, path_v.string, buf_v.string) catch {
                obj.properties.put(std.heap.page_allocator, "__open", .{ .bool = false }) catch {};
                return .{ .bool = false };
            };
        }
        obj.properties.put(std.heap.page_allocator, "__open", .{ .bool = false }) catch {};
        return .{ .bool = true };
    }
    if (getFileHandle(obj)) |file| {
        // never close stdin/stdout/stderr - they're shared with the host process
        if (file.handle > 2) file.close();
    }
    obj.properties.put(std.heap.page_allocator, "__open", .{ .bool = false }) catch {};
    return .{ .bool = true };
}

fn isZlibWriting(obj: *PhpObject) bool {
    const v = obj.get("__zlib_writing");
    return v == .bool and v.bool;
}

fn native_fpassthru(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .{ .int = 0 };
    var total: i64 = 0;
    const chunk: i64 = 4096;
    while (true) {
        const result = ctx.vm.callByName("fread", &.{ args[0], .{ .int = chunk } }) catch break;
        if (result != .string or result.string.len == 0) break;
        try ctx.vm.output.appendSlice(ctx.allocator, result.string);
        total += @intCast(result.string.len);
        if (result.string.len < @as(usize, @intCast(chunk))) break;
    }
    return .{ .int = total };
}

fn native_fread(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .object or args[1] != .int) return .{ .bool = false };
    const obj = args[0].object;
    if (std.mem.eql(u8, obj.class_name, "FileHandle")) {
        const open = obj.get("__open");
        if (open != .bool or !open.bool) {
            try ctx.vm.setPendingException("TypeError", "fread(): Argument #1 ($stream) must be an open stream resource");
            return error.RuntimeError;
        }
    }
    const length: usize = @intCast(@max(args[1].int, 0));
    if (length == 0) return .{ .string = "" };
    if (fileHandleWrapper(obj)) |wrapper| {
        const result = try ctx.callMethod(wrapper, "stream_read", &[_]Value{.{ .int = @intCast(length) }});
        if (result == .string) return result;
        return .{ .string = "" };
    }
    if (getBufferBacking(obj)) |buffer| {
        const pos = getBufferPos(obj);
        if (pos >= buffer.len) return .{ .string = "" };
        const end = @min(pos + length, buffer.len);
        const slice = try ctx.allocator.dupe(u8, buffer[pos..end]);
        try ctx.strings.append(ctx.allocator, slice);
        setBufferPos(obj, end);
        return .{ .string = slice };
    }
    const file = getFileHandle(obj) orelse return Value{ .bool = false };

    const buf = try ctx.allocator.alloc(u8, length);
    const n = file.read(buf) catch {
        ctx.allocator.free(buf);
        return .{ .bool = false };
    };
    if (n == 0) {
        ctx.allocator.free(buf);
        return .{ .string = "" };
    }
    // shrink to actual read size
    if (n < length) {
        const exact = try ctx.allocator.alloc(u8, n);
        @memcpy(exact, buf[0..n]);
        ctx.allocator.free(buf);
        try ctx.strings.append(ctx.allocator, exact);
        return .{ .string = exact };
    }
    try ctx.strings.append(ctx.allocator, buf);
    return .{ .string = buf };
}

fn native_fwrite(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .object or args[1] != .string) return .{ .bool = false };
    const obj = args[0].object;
    if (std.mem.eql(u8, obj.class_name, "FileHandle")) {
        const open = obj.get("__open");
        if (open != .bool or !open.bool) {
            try ctx.vm.setPendingException("TypeError", "fwrite(): Argument #1 ($stream) must be an open stream resource");
            return error.RuntimeError;
        }
    }
    const data = args[1].string;
    if (fileHandleWrapper(obj)) |wrapper| {
        const result = try ctx.callMethod(wrapper, "stream_write", &[_]Value{.{ .string = data }});
        if (result == .int) return result;
        return .{ .int = 0 };
    }
    if (isZlibWriting(obj) or obj.get("__popen_cmd") == .string) {
        const cur = obj.get("__buffer");
        const cur_str: []const u8 = if (cur == .string) cur.string else "";
        const combined = try ctx.allocator.alloc(u8, cur_str.len + data.len);
        @memcpy(combined[0..cur_str.len], cur_str);
        @memcpy(combined[cur_str.len..], data);
        try ctx.strings.append(ctx.allocator, combined);
        try obj.set(ctx.allocator, "__buffer", .{ .string = combined });
        return .{ .int = @intCast(data.len) };
    }
    const file = getFileHandle(obj) orelse return Value{ .bool = false };
    // route php://stdout and php://output through the VM output buffer so the order
    // matches echo. for php://stderr, flush the buffer first so anything echo'd before
    // this call lands before our stderr write
    if (file.handle == 1) {
        try ctx.vm.output.appendSlice(ctx.allocator, data);
        return .{ .int = @intCast(data.len) };
    }
    if (file.handle == 2) {
        if (ctx.vm.output.items.len > 0) {
            const stdout = std.fs.File{ .handle = 1 };
            _ = stdout.write(ctx.vm.output.items) catch {};
            ctx.vm.output.clearRetainingCapacity();
        }
    }
    const written = file.write(data) catch return Value{ .bool = false };
    return .{ .int = @intCast(written) };
}

fn native_fgets(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .{ .bool = false };
    const obj = args[0].object;
    const max_len: usize = if (args.len >= 2 and args[1] == .int) @intCast(@max(args[1].int, 1)) else 1024;
    if (getBufferBacking(obj)) |buffer| {
        const pos = getBufferPos(obj);
        if (pos >= buffer.len) return .{ .bool = false };
        var end = pos;
        while (end < buffer.len and end - pos < max_len) {
            const c = buffer[end];
            end += 1;
            if (c == '\n') break;
        }
        const slice = try ctx.allocator.dupe(u8, buffer[pos..end]);
        try ctx.strings.append(ctx.allocator, slice);
        setBufferPos(obj, end);
        return .{ .string = slice };
    }
    const file = getFileHandle(obj) orelse return Value{ .bool = false };

    var buf = std.ArrayListUnmanaged(u8){};
    var byte: [1]u8 = undefined;
    while (buf.items.len < max_len) {
        const n = file.read(&byte) catch break;
        if (n == 0) break;
        try buf.append(ctx.allocator, byte[0]);
        if (byte[0] == '\n') break;
    }
    if (buf.items.len == 0) return .{ .bool = false };
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn native_fgetc(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .{ .bool = false };
    const file = getFileHandle(args[0].object) orelse return Value{ .bool = false };
    var byte: [1]u8 = undefined;
    const n = file.read(&byte) catch return Value{ .bool = false };
    if (n == 0) return .{ .bool = false };
    const result = try ctx.allocator.dupe(u8, byte[0..1]);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn native_feof(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .{ .bool = true };
    const obj = args[0].object;
    if (std.mem.eql(u8, obj.class_name, "FileHandle")) {
        const open = obj.get("__open");
        if (open != .bool or !open.bool) {
            try ctx.vm.setPendingException("TypeError", "feof(): Argument #1 ($stream) must be an open stream resource");
            return error.RuntimeError;
        }
    }
    if (fileHandleWrapper(obj)) |wrapper| {
        if (!ctx.vm.hasMethod(wrapper.class_name, "stream_eof")) return .{ .bool = false };
        const result = try ctx.callMethod(wrapper, "stream_eof", &.{});
        return .{ .bool = result.isTruthy() };
    }
    if (getBufferBacking(obj)) |buffer| {
        return .{ .bool = getBufferPos(obj) >= buffer.len };
    }
    const file = getFileHandle(obj) orelse return Value{ .bool = true };
    // peek one byte to check EOF
    var byte: [1]u8 = undefined;
    const n = file.read(&byte) catch return Value{ .bool = true };
    if (n == 0) return .{ .bool = true };
    // put the byte back by seeking backwards
    file.seekBy(-1) catch {};
    return .{ .bool = false };
}

fn native_fseek(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .object or args[1] != .int) return .{ .int = -1 };
    const obj = args[0].object;
    const offset = args[1].int;
    const whence: u2 = if (args.len >= 3 and args[2] == .int) blk: {
        break :blk switch (args[2].int) {
            1 => 1, // SEEK_CUR
            2 => 2, // SEEK_END
            else => 0, // SEEK_SET
        };
    } else 0;
    if (fileHandleWrapper(obj)) |wrapper| {
        if (!ctx.vm.hasMethod(wrapper.class_name, "stream_seek")) return .{ .int = -1 };
        const result = try ctx.callMethod(wrapper, "stream_seek", &[_]Value{ .{ .int = offset }, .{ .int = whence } });
        return .{ .int = if (result.isTruthy()) 0 else -1 };
    }
    if (getBufferBacking(obj)) |buffer| {
        const new_pos: i64 = switch (whence) {
            0 => offset,
            1 => @as(i64, @intCast(getBufferPos(obj))) + offset,
            2 => @as(i64, @intCast(buffer.len)) + offset,
            else => return .{ .int = -1 },
        };
        if (new_pos < 0) return .{ .int = -1 };
        setBufferPos(obj, @intCast(new_pos));
        return .{ .int = 0 };
    }
    const file = getFileHandle(obj) orelse return Value{ .int = -1 };
    switch (whence) {
        0 => file.seekTo(@intCast(offset)) catch return Value{ .int = -1 },
        1 => file.seekBy(offset) catch return Value{ .int = -1 },
        2 => file.seekFromEnd(offset) catch return Value{ .int = -1 },
        else => return .{ .int = -1 },
    }
    return .{ .int = 0 };
}

fn native_ftell(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .{ .bool = false };
    const obj = args[0].object;
    if (fileHandleWrapper(obj)) |wrapper| {
        if (!ctx.vm.hasMethod(wrapper.class_name, "stream_tell")) return .{ .bool = false };
        const result = try ctx.callMethod(wrapper, "stream_tell", &.{});
        if (result == .int) return result;
        return .{ .bool = false };
    }
    if (getBufferBacking(obj) != null) {
        return .{ .int = @intCast(getBufferPos(obj)) };
    }
    const file = getFileHandle(obj) orelse return Value{ .bool = false };
    const pos = file.getPos() catch return Value{ .bool = false };
    return .{ .int = @intCast(pos) };
}

fn native_rewind(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .{ .bool = false };
    const obj = args[0].object;
    if (fileHandleWrapper(obj)) |wrapper| {
        if (!ctx.vm.hasMethod(wrapper.class_name, "stream_seek")) return .{ .bool = false };
        const result = try ctx.callMethod(wrapper, "stream_seek", &[_]Value{ .{ .int = 0 }, .{ .int = 0 } });
        return .{ .bool = result.isTruthy() };
    }
    if (getBufferBacking(obj) != null) {
        setBufferPos(obj, 0);
        return .{ .bool = true };
    }
    const file = getFileHandle(obj) orelse return Value{ .bool = false };
    file.seekTo(0) catch return Value{ .bool = false };
    return .{ .bool = true };
}

fn native_fflush(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .{ .bool = false };
    // zig files are unbuffered at our level, this is a no-op
    _ = getFileHandle(args[0].object) orelse return Value{ .bool = false };
    return .{ .bool = true };
}

fn native_ftruncate(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .object or args[1] != .int) return .{ .bool = false };
    const file = getFileHandle(args[0].object) orelse return Value{ .bool = false };
    const size: u64 = @intCast(@max(args[1].int, 0));
    file.setEndPos(size) catch return Value{ .bool = false };
    return .{ .bool = true };
}

fn native_flock(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .object or args[1] != .int) return .{ .bool = false };
    const file = getFileHandle(args[0].object) orelse return Value{ .bool = false };
    const op: i32 = @intCast(args[1].int & 0xff);
    std.posix.flock(file.handle, op) catch return Value{ .bool = false };
    return .{ .bool = true };
}

fn stream_get_meta_data(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .{ .bool = false };
    const obj = args[0].object;
    const mode_val = obj.get("__mode");
    const mode = if (mode_val == .string) mode_val.string else "r";
    const path_val = obj.get("__path");
    const uri = if (path_val == .string) path_val.string else "";
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
            stream_type = "STDIO";
        } else if (std.mem.eql(u8, scheme, "data")) {
            wrapper_type = "RFC2397";
            stream_type = "RFC2397";
        } else {
            wrapper_type = scheme;
            stream_type = scheme;
        }
    }
    const result = try ctx.createArray();
    try result.set(ctx.allocator, .{ .string = "timed_out" }, .{ .bool = false });
    try result.set(ctx.allocator, .{ .string = "blocked" }, .{ .bool = true });
    try result.set(ctx.allocator, .{ .string = "eof" }, .{ .bool = false });
    try result.set(ctx.allocator, .{ .string = "wrapper_type" }, .{ .string = wrapper_type });
    try result.set(ctx.allocator, .{ .string = "stream_type" }, .{ .string = stream_type });
    try result.set(ctx.allocator, .{ .string = "mode" }, .{ .string = mode });
    try result.set(ctx.allocator, .{ .string = "unread_bytes" }, .{ .int = 0 });
    try result.set(ctx.allocator, .{ .string = "seekable" }, .{ .bool = true });
    try result.set(ctx.allocator, .{ .string = "uri" }, .{ .string = uri });
    return .{ .array = result };
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
    var out = std.ArrayListUnmanaged(u8){};
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

fn native_gzcompress(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const out = zlibEncodeWindow(ctx.allocator, args[0].string, 15) catch return .{ .bool = false };
    try ctx.vm.strings.append(ctx.allocator, out);
    return .{ .string = out };
}

fn native_gzuncompress(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const out = zlibDecodeWindow(ctx.allocator, args[0].string, 15) catch return .{ .bool = false };
    try ctx.vm.strings.append(ctx.allocator, out);
    return .{ .string = out };
}

fn native_gzdeflate(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const out = zlibEncodeWindow(ctx.allocator, args[0].string, -15) catch return .{ .bool = false };
    try ctx.vm.strings.append(ctx.allocator, out);
    return .{ .string = out };
}

fn native_gzinflate(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const out = zlibDecodeWindow(ctx.allocator, args[0].string, -15) catch return .{ .bool = false };
    try ctx.vm.strings.append(ctx.allocator, out);
    return .{ .string = out };
}

fn native_gzencode(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const out = zlibEncodeWindow(ctx.allocator, args[0].string, 15 + 16) catch return .{ .bool = false };
    try ctx.vm.strings.append(ctx.allocator, out);
    return .{ .string = out };
}

fn native_gzdecode(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const out = zlibDecodeWindow(ctx.allocator, args[0].string, 15 + 32) catch return .{ .bool = false };
    try ctx.vm.strings.append(ctx.allocator, out);
    return .{ .string = out };
}

fn gzipDecode(a: Allocator, input: []const u8) ![]u8 {
    if (input.len == 0) return try a.alloc(u8, 0);
    var stream: zlib.z_stream = std.mem.zeroes(zlib.z_stream);
    if (zlib.inflateInit2_(&stream, 15 + 32, zlib.zlibVersion(), @sizeOf(zlib.z_stream)) != zlib.Z_OK) {
        return error.InflateInitFailed;
    }
    defer _ = zlib.inflateEnd(&stream);

    var out = std.ArrayListUnmanaged(u8){};
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
    const raw = try std.fs.cwd().readFileAlloc(a, inner, 1024 * 1024 * 256);
    defer a.free(raw);
    return try gzipDecode(a, raw);
}

// gzip-encodes data and writes it to the path under `compress.zlib://`
fn writeZlibFile(a: Allocator, path: []const u8, data: []const u8) !void {
    const inner = path[ZLIB_PREFIX.len..];
    const encoded = try gzipEncode(a, data);
    defer a.free(encoded);
    try std.fs.cwd().writeFile(.{ .sub_path = inner, .data = encoded });
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
        .{ .string = path },
        .{ .string = mode },
        .{ .int = 0 },
        .null,
    };
    const ok = try ctx.callMethod(wrapper, "stream_open", &open_args);
    if (!ok.isTruthy()) return null;
    const fh = try ctx.allocator.create(PhpObject);
    fh.* = .{ .class_name = "FileHandle" };
    try fh.set(ctx.allocator, "__wrapper_obj", .{ .object = wrapper });
    try fh.set(ctx.allocator, "__open", .{ .bool = true });
    try fh.set(ctx.allocator, "__mode", .{ .string = mode });
    try ctx.vm.objects.append(ctx.allocator, fh);
    return Value{ .object = fh };
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
    const stat_args = [_]Value{ .{ .string = path }, .{ .int = flags } };
    const result = try ctx.callMethod(wrapper, "url_stat", &stat_args);
    if (result != .array) return null;
    return result.array;
}

fn stream_get_wrappers(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const result = try ctx.createArray();
    for (builtin_wrappers) |w| {
        if (ctx.vm.stream_wrappers_unregistered.contains(w)) continue;
        try result.append(ctx.allocator, .{ .string = w });
    }
    var it = ctx.vm.stream_wrappers_user.keyIterator();
    while (it.next()) |k| try result.append(ctx.allocator, .{ .string = k.* });
    return .{ .array = result };
}

fn stream_wrapper_register(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const protocol = args[0].string;
    const class_name = args[1].string;
    if (protocol.len == 0) return .{ .bool = false };
    // already registered (builtin still active or user wrapper present)
    const builtin_active = isBuiltinWrapper(protocol) and !ctx.vm.stream_wrappers_unregistered.contains(protocol);
    if (builtin_active or ctx.vm.stream_wrappers_user.contains(protocol)) return .{ .bool = false };
    if (!ctx.vm.classes.contains(class_name)) {
        ctx.vm.tryAutoload(class_name) catch return Value{ .bool = false };
        if (!ctx.vm.classes.contains(class_name)) return .{ .bool = false };
    }
    const proto_owned = try ctx.createString(protocol);
    const class_owned = try ctx.createString(class_name);
    try ctx.vm.stream_wrappers_user.put(ctx.allocator, proto_owned, class_owned);
    return .{ .bool = true };
}

fn stream_wrapper_unregister(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const protocol = args[0].string;
    if (ctx.vm.stream_wrappers_user.fetchRemove(protocol) != null) return .{ .bool = true };
    if (!isBuiltinWrapper(protocol)) return .{ .bool = false };
    if (ctx.vm.stream_wrappers_unregistered.contains(protocol)) return .{ .bool = false };
    const proto_owned = try ctx.createString(protocol);
    try ctx.vm.stream_wrappers_unregistered.put(ctx.allocator, proto_owned, {});
    return .{ .bool = true };
}

fn stream_wrapper_restore(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const protocol = args[0].string;
    if (!isBuiltinWrapper(protocol)) return .{ .bool = false };
    if (!ctx.vm.stream_wrappers_unregistered.contains(protocol)) return .{ .bool = true };
    _ = ctx.vm.stream_wrappers_unregistered.remove(protocol);
    return .{ .bool = true };
}

fn stream_copy_to_stream(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .object or args[1] != .object) return .{ .bool = false };
    const length: i64 = if (args.len >= 3 and args[2] != .null) Value.toInt(args[2]) else -1;
    const offset: i64 = if (args.len >= 4 and args[3] != .null) Value.toInt(args[3]) else 0;

    var src_args: [3]Value = .{ args[0], .{ .int = if (length < 0) -1 else length }, .{ .int = offset } };
    const data_v = try stream_get_contents(ctx, src_args[0..3]);
    const data: []const u8 = if (data_v == .string) data_v.string else return Value{ .bool = false };

    var write_args: [2]Value = .{ args[1], .{ .string = data } };
    const written = try native_fwrite(ctx, write_args[0..2]);
    return written;
}

fn stream_get_contents(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .{ .bool = false };
    const obj = args[0].object;
    // length: -1 (or null) means read until EOF; non-negative means cap
    const length: i64 = if (args.len >= 2 and args[1] == .int) args[1].int else -1;
    // offset: -1 (default) means start at current position; >=0 means seek
    const offset: i64 = if (args.len >= 3 and args[2] == .int) args[2].int else -1;

    if (getBufferBacking(obj)) |buffer| {
        if (offset >= 0) setBufferPos(obj, @intCast(offset));
        const pos = getBufferPos(obj);
        if (pos >= buffer.len) return .{ .string = "" };
        const remaining = buffer[pos..];
        const take = if (length >= 0) @min(@as(usize, @intCast(length)), remaining.len) else remaining.len;
        setBufferPos(obj, pos + take);
        return .{ .string = try ctx.createString(remaining[0..take]) };
    }
    const file = getFileHandle(obj) orelse return Value{ .bool = false };
    if (offset >= 0) {
        file.seekTo(@intCast(offset)) catch return Value{ .bool = false };
    }
    if (length >= 0) {
        const cap: usize = @intCast(length);
        const buf = ctx.allocator.alloc(u8, cap) catch return Value{ .bool = false };
        const n = file.read(buf) catch {
            ctx.allocator.free(buf);
            return Value{ .bool = false };
        };
        if (n < cap) {
            const result = try ctx.createString(buf[0..n]);
            ctx.allocator.free(buf);
            return .{ .string = result };
        }
        try ctx.strings.append(ctx.allocator, buf);
        return .{ .string = buf };
    }
    const buf = file.readToEndAlloc(ctx.allocator, 10 * 1024 * 1024) catch return Value{ .bool = false };
    try ctx.strings.append(ctx.allocator, buf);
    return .{ .string = buf };
}

fn native_fstat(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .{ .bool = false };
    const file = getFileHandle(args[0].object) orelse return Value{ .bool = false };
    const stat = std.posix.fstat(file.handle) catch return Value{ .bool = false };
    const result = try ctx.createArray();
    const mode: i64 = @intCast(stat.mode);
    const size: i64 = @intCast(stat.size);
    try result.set(ctx.allocator, .{ .string = "mode" }, .{ .int = mode });
    try result.set(ctx.allocator, .{ .string = "size" }, .{ .int = size });
    try result.set(ctx.allocator, .{ .int = 2 }, .{ .int = mode });
    try result.set(ctx.allocator, .{ .int = 7 }, .{ .int = size });
    return .{ .array = result };
}

fn native_fgetcsv(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .{ .bool = false };
    const file = getFileHandle(args[0].object) orelse return Value{ .bool = false };
    const delimiter: u8 = if (args.len >= 3 and args[2] == .string and args[2].string.len > 0) args[2].string[0] else ',';
    const enclosure: u8 = if (args.len >= 4 and args[3] == .string and args[3].string.len > 0) args[3].string[0] else '"';

    // read a CSV record, honoring quoted-field embedded newlines
    var line = std.ArrayListUnmanaged(u8){};
    var byte: [1]u8 = undefined;
    var in_quotes = false;
    var got_any = false;
    while (true) {
        const n = file.read(&byte) catch break;
        if (n == 0) break;
        got_any = true;
        const c = byte[0];
        try line.append(ctx.allocator, c);
        if (c == enclosure) {
            if (in_quotes) {
                // peek next byte for `""` escape
                var peek: [1]u8 = undefined;
                const np = file.read(&peek) catch 0;
                if (np == 1) {
                    try line.append(ctx.allocator, peek[0]);
                    if (peek[0] != enclosure) {
                        in_quotes = false;
                        if (peek[0] == '\n') break;
                    }
                } else {
                    in_quotes = false;
                    break;
                }
            } else {
                in_quotes = true;
            }
        } else if (c == '\n' and !in_quotes) {
            break;
        }
    }
    if (!got_any) return .{ .bool = false };

    const line_owned = try line.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, line_owned);

    var raw = line_owned;
    if (raw.len > 0 and raw[raw.len - 1] == '\n') raw = raw[0 .. raw.len - 1];
    if (raw.len > 0 and raw[raw.len - 1] == '\r') raw = raw[0 .. raw.len - 1];

    return parseCsvRecord(ctx, raw, delimiter, enclosure);
}

fn parseCsvRecord(ctx: *NativeContext, raw: []const u8, delimiter: u8, enclosure: u8) !Value {
    var result = try ctx.createArray();
    var field = std.ArrayListUnmanaged(u8){};
    var in_quotes = false;
    var at_field_start = true;
    var i: usize = 0;
    while (i < raw.len) : (i += 1) {
        const c = raw[i];
        if (in_quotes) {
            if (c == enclosure) {
                if (i + 1 < raw.len and raw[i + 1] == enclosure) {
                    try field.append(ctx.allocator, enclosure);
                    i += 1;
                } else {
                    in_quotes = false;
                }
            } else {
                try field.append(ctx.allocator, c);
            }
        } else {
            if (c == enclosure and at_field_start) {
                in_quotes = true;
                at_field_start = false;
            } else if (c == delimiter) {
                const s = try field.toOwnedSlice(ctx.allocator);
                try ctx.strings.append(ctx.allocator, s);
                try result.append(ctx.allocator, .{ .string = s });
                at_field_start = true;
            } else {
                try field.append(ctx.allocator, c);
                at_field_start = false;
            }
        }
    }
    const s = try field.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, s);
    try result.append(ctx.allocator, .{ .string = s });
    return .{ .array = result };
}

fn native_fputcsv(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .object or args[1] != .array) return .{ .bool = false };
    const file = getFileHandle(args[0].object) orelse return Value{ .bool = false };
    const arr = args[1].array;
    const delimiter: u8 = if (args.len >= 3 and args[2] == .string and args[2].string.len > 0) args[2].string[0] else ',';
    const enclosure: u8 = if (args.len >= 4 and args[3] == .string and args[3].string.len > 0) args[3].string[0] else '"';
    const escape: ?u8 = if (args.len >= 5 and args[4] == .string and args[4].string.len > 0) args[4].string[0] else null;

    var buf = std.ArrayListUnmanaged(u8){};
    for (arr.entries.items, 0..) |entry, i| {
        if (i > 0) try buf.append(ctx.allocator, delimiter);
        var tmp_buf = std.ArrayListUnmanaged(u8){};
        defer tmp_buf.deinit(ctx.allocator);
        try entry.value.format(&tmp_buf, ctx.allocator);
        const val = tmp_buf.items;

        var needs_quote = false;
        for (val) |c| {
            if (c == delimiter or c == enclosure or c == '\n' or c == '\r' or c == ' ' or c == '\t' or (escape != null and c == escape.?)) {
                needs_quote = true;
                break;
            }
        }

        if (needs_quote) {
            try buf.append(ctx.allocator, enclosure);
            for (val) |c| {
                if (c == enclosure) try buf.append(ctx.allocator, enclosure);
                try buf.append(ctx.allocator, c);
            }
            try buf.append(ctx.allocator, enclosure);
        } else {
            try buf.appendSlice(ctx.allocator, val);
        }
    }
    try buf.append(ctx.allocator, '\n');

    const written = file.write(buf.items) catch return Value{ .bool = false };
    const owned = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, owned);
    return .{ .int = @intCast(written) };
}

fn native_touch(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const path = args[0].string;

    // if file doesn't exist, create it
    const file = std.fs.cwd().createFile(path, .{ .exclusive = true }) catch |err| switch (err) {
        error.PathAlreadyExists => {
            // file exists - update access and modification times
            if (args.len >= 2 and args[1] != .null) {
                const mtime: i128 = @as(i128, Value.toInt(args[1])) * 1_000_000_000;
                const f = std.fs.cwd().openFile(path, .{ .mode = .write_only }) catch return Value{ .bool = false };
                defer f.close();
                const atime = if (args.len >= 3 and args[2] != .null) @as(i128, Value.toInt(args[2])) * 1_000_000_000 else mtime;
                f.updateTimes(atime, mtime) catch return Value{ .bool = true };
            }
            return .{ .bool = true };
        },
        else => return .{ .bool = false },
    };
    file.close();
    return .{ .bool = true };
}

fn native_chmod(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string) return .{ .bool = false };
    const path = args[0].string;
    const mode_val = Value.toInt(args[1]);
    if (mode_val < 0) return .{ .bool = false };
    const mode: std.posix.mode_t = @intCast(mode_val);

    const file = std.fs.cwd().openFile(path, .{ .mode = .read_write }) catch
        return Value{ .bool = false };
    defer file.close();
    file.chmod(mode) catch return Value{ .bool = false };
    return .{ .bool = true };
}

fn native_stat(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const path = args[0].string;
    var pbuf: [std.fs.max_path_bytes:0]u8 = undefined;
    if (path.len >= pbuf.len) return .{ .bool = false };
    @memcpy(pbuf[0..path.len], path);
    pbuf[path.len] = 0;
    var st: std.c.Stat = undefined;
    if (std.c.stat(&pbuf, &st) != 0) return .{ .bool = false };
    return .{ .array = try buildStatArray(ctx, &st) };
}

fn native_chdir(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const path = args[0].string;
    var dir = std.fs.cwd().openDir(path, .{}) catch return Value{ .bool = false };
    defer dir.close();
    std.posix.fchdir(dir.fd) catch return Value{ .bool = false };
    return .{ .bool = true };
}

fn native_stream_resolve_include_path(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const path = args[0].string;
    std.fs.cwd().access(path, .{}) catch return .{ .bool = false };
    return .{ .string = path };
}

fn native_stream_isatty(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .{ .bool = false };
    const obj = args[0].object;
    if (!std.mem.eql(u8, obj.class_name, "FileHandle")) return .{ .bool = false };
    const fd_val = obj.get("__fd");
    if (fd_val != .int) return .{ .bool = false };
    const fd: std.posix.fd_t = @intCast(fd_val.int);
    return .{ .bool = std.posix.isatty(fd) };
}

fn native_clearstatcache(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .null;
}

fn native_stream_set_chunk_size(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = 8192 };
}

fn native_stream_set_buffer(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = 0 };
}

fn native_umask(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len > 0 and args[0] == .int) {
        const old = std.c.umask(@intCast(args[0].int));
        return .{ .int = @intCast(old) };
    }
    const current = std.c.umask(0o022);
    _ = std.c.umask(current);
    return .{ .int = @intCast(current) };
}

fn native_fileperms(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const stat = std.fs.cwd().statFile(args[0].string) catch return Value{ .bool = false };
    return .{ .int = @intCast(stat.mode) };
}

extern "c" fn lstat(noalias path: [*:0]const u8, noalias buf: *std.c.Stat) c_int;

fn native_fileowner(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const path = args[0].string;
    var pbuf: [std.fs.max_path_bytes:0]u8 = undefined;
    if (path.len >= pbuf.len) return .{ .bool = false };
    @memcpy(pbuf[0..path.len], path);
    pbuf[path.len] = 0;
    var st: std.c.Stat = undefined;
    if (std.c.stat(&pbuf, &st) != 0) return .{ .bool = false };
    return .{ .int = @intCast(st.uid) };
}

fn native_filegroup(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const path = args[0].string;
    var pbuf: [std.fs.max_path_bytes:0]u8 = undefined;
    if (path.len >= pbuf.len) return .{ .bool = false };
    @memcpy(pbuf[0..path.len], path);
    pbuf[path.len] = 0;
    var st: std.c.Stat = undefined;
    if (std.c.stat(&pbuf, &st) != 0) return .{ .bool = false };
    return .{ .int = @intCast(st.gid) };
}

fn native_is_link(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const path = args[0].string;
    var pbuf: [std.fs.max_path_bytes:0]u8 = undefined;
    if (path.len >= pbuf.len) return .{ .bool = false };
    @memcpy(pbuf[0..path.len], path);
    pbuf[path.len] = 0;
    var st: std.c.Stat = undefined;
    if (lstat(&pbuf, &st) != 0) return .{ .bool = false };
    return .{ .bool = (st.mode & 0o170000) == 0o120000 };
}

fn native_symlink(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    var t: [std.fs.max_path_bytes:0]u8 = undefined;
    var l: [std.fs.max_path_bytes:0]u8 = undefined;
    const target = args[0].string;
    const linkpath = args[1].string;
    if (target.len >= t.len or linkpath.len >= l.len) return .{ .bool = false };
    @memcpy(t[0..target.len], target);
    t[target.len] = 0;
    @memcpy(l[0..linkpath.len], linkpath);
    l[linkpath.len] = 0;
    return .{ .bool = std.c.symlink(&t, &l) == 0 };
}

fn native_link(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    var t: [std.fs.max_path_bytes:0]u8 = undefined;
    var l: [std.fs.max_path_bytes:0]u8 = undefined;
    const target = args[0].string;
    const linkpath = args[1].string;
    if (target.len >= t.len or linkpath.len >= l.len) return .{ .bool = false };
    @memcpy(t[0..target.len], target);
    t[target.len] = 0;
    @memcpy(l[0..linkpath.len], linkpath);
    l[linkpath.len] = 0;
    return .{ .bool = std.c.link(&t, &l) == 0 };
}

fn buildStatArray(ctx: *NativeContext, st: *const std.c.Stat) !*PhpArray {
    var arr = try ctx.createArray();
    const dev: i64 = @intCast(st.dev);
    const ino: i64 = @intCast(st.ino);
    const mode: i64 = @intCast(st.mode);
    const nlink: i64 = @intCast(st.nlink);
    const uid: i64 = @intCast(st.uid);
    const gid: i64 = @intCast(st.gid);
    const size: i64 = @intCast(st.size);
    const atime: i64 = @intCast(st.atime().sec);
    const mtime: i64 = @intCast(st.mtime().sec);
    const ctime: i64 = @intCast(st.ctime().sec);
    const blksize: i64 = @intCast(st.blksize);
    const blocks: i64 = @intCast(st.blocks);
    const pairs = [_]struct { name: []const u8, val: i64 }{
        .{ .name = "dev", .val = dev }, .{ .name = "ino", .val = ino },
        .{ .name = "mode", .val = mode }, .{ .name = "nlink", .val = nlink },
        .{ .name = "uid", .val = uid }, .{ .name = "gid", .val = gid },
        .{ .name = "rdev", .val = 0 }, .{ .name = "size", .val = size },
        .{ .name = "atime", .val = atime }, .{ .name = "mtime", .val = mtime },
        .{ .name = "ctime", .val = ctime }, .{ .name = "blksize", .val = blksize },
        .{ .name = "blocks", .val = blocks },
    };
    for (pairs, 0..) |p, i| {
        try arr.set(ctx.allocator, .{ .int = @intCast(i) }, .{ .int = p.val });
        try arr.set(ctx.allocator, .{ .string = p.name }, .{ .int = p.val });
    }
    return arr;
}

fn native_lstat(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const path = args[0].string;
    var pbuf: [std.fs.max_path_bytes:0]u8 = undefined;
    if (path.len >= pbuf.len) return .{ .bool = false };
    @memcpy(pbuf[0..path.len], path);
    pbuf[path.len] = 0;
    var st: std.c.Stat = undefined;
    if (lstat(&pbuf, &st) != 0) return .{ .bool = false };
    return .{ .array = try buildStatArray(ctx, &st) };
}

fn native_readlink(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const target = std.fs.cwd().readLink(args[0].string, &buf) catch return Value{ .bool = false };
    const result = ctx.vm.allocator.dupe(u8, target) catch return .{ .bool = false };
    try ctx.vm.strings.append(ctx.vm.allocator, result);
    return .{ .string = result };
}

fn native_tmpfile(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const dir = std.posix.getenv("TMPDIR") orelse "/tmp";
    const path = std.fmt.allocPrint(ctx.vm.allocator, "{s}/zphp_tmpfile_{d}_{d}", .{ dir, std.time.nanoTimestamp(), std.crypto.random.int(u32) }) catch return .{ .bool = false };
    try ctx.vm.strings.append(ctx.vm.allocator, path);
    var open_args: [2]Value = .{ .{ .string = path }, .{ .string = "w+b" } };
    const handle = try native_fopen(ctx, open_args[0..2]);
    return handle;
}

fn native_tempnam(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const dir = if (args.len > 0 and args[0] == .string) args[0].string else "/tmp";
    const prefix = if (args.len > 1 and args[1] == .string) args[1].string else "tmp";
    var rng = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp() & 0x7fff_ffff_ffff_ffff));
    const r = rng.random();
    var attempt: u8 = 0;
    while (attempt < 16) : (attempt += 1) {
        var buf: [16]u8 = undefined;
        const hex = "0123456789abcdef";
        for (&buf) |*b| b.* = hex[r.uintLessThan(u8, 16)];
        const candidate = std.fmt.allocPrint(ctx.vm.allocator, "{s}/{s}{s}", .{ dir, prefix, &buf }) catch continue;
        if (std.fs.cwd().createFile(candidate, .{ .exclusive = true, .mode = 0o600 })) |file| {
            file.close();
            try ctx.vm.strings.append(ctx.vm.allocator, candidate);
            return .{ .string = candidate };
        } else |_| {
            ctx.vm.allocator.free(candidate);
        }
    }
    return .{ .bool = false };
}


fn runShellCapture(allocator: std.mem.Allocator, command: []const u8, stdin_data: ?[]const u8) !struct { stdout: []u8, stderr: []u8, exit: i64 } {
    var child = std.process.Child.init(&.{ "/bin/sh", "-c", command }, allocator);
    child.stdin_behavior = if (stdin_data != null) .Pipe else .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();
    if (stdin_data) |data| {
        if (child.stdin) |*stdin_file| {
            _ = stdin_file.writeAll(data) catch {};
            stdin_file.close();
            child.stdin = null;
        }
    }
    var stdout_buf = std.ArrayListUnmanaged(u8){};
    var stderr_buf = std.ArrayListUnmanaged(u8){};
    try child.collectOutput(allocator, &stdout_buf, &stderr_buf, 64 * 1024 * 1024);
    const term = try child.wait();
    const stdout = try stdout_buf.toOwnedSlice(allocator);
    const stderr = try stderr_buf.toOwnedSlice(allocator);
    const exit: i64 = switch (term) {
        .Exited => |c| @intCast(c),
        .Signal => |c| @as(i64, @intCast(c)) + 128,
        else => -1,
    };
    return .{ .stdout = stdout, .stderr = stderr, .exit = exit };
}

fn makeReadBufferHandle(ctx: *NativeContext, data: []const u8) !*PhpObject {
    const obj = try ctx.allocator.create(PhpObject);
    obj.* = .{ .class_name = "FileHandle" };
    try ctx.vm.objects.append(ctx.allocator, obj);
    try obj.set(ctx.allocator, "__buffer", .{ .string = data });
    try obj.set(ctx.allocator, "__pos", .{ .int = 0 });
    try obj.set(ctx.allocator, "__open", .{ .bool = true });
    try obj.set(ctx.allocator, "__mode", .{ .string = "r" });
    return obj;
}

fn makePopenWriteHandle(ctx: *NativeContext, command: []const u8) !*PhpObject {
    const obj = try ctx.allocator.create(PhpObject);
    obj.* = .{ .class_name = "FileHandle" };
    try ctx.vm.objects.append(ctx.allocator, obj);
    const cmd_copy = try ctx.allocator.dupe(u8, command);
    try ctx.vm.strings.append(ctx.allocator, cmd_copy);
    try obj.set(ctx.allocator, "__popen_cmd", .{ .string = cmd_copy });
    try obj.set(ctx.allocator, "__buffer", .{ .string = "" });
    try obj.set(ctx.allocator, "__pos", .{ .int = 0 });
    try obj.set(ctx.allocator, "__open", .{ .bool = true });
    try obj.set(ctx.allocator, "__mode", .{ .string = "w" });
    return obj;
}

fn native_popen(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const cmd = args[0].string;
    const mode = args[1].string;
    if (mode.len > 0 and (mode[0] == 'r')) {
        const result = runShellCapture(ctx.allocator, cmd, null) catch return .{ .bool = false };
        ctx.allocator.free(result.stderr);
        try ctx.vm.strings.append(ctx.allocator, result.stdout);
        const obj = try makeReadBufferHandle(ctx, result.stdout);
        try obj.set(ctx.allocator, "__popen_exit", .{ .int = result.exit });
        return .{ .object = obj };
    }
    if (mode.len > 0 and (mode[0] == 'w')) {
        const obj = try makePopenWriteHandle(ctx, cmd);
        return .{ .object = obj };
    }
    return .{ .bool = false };
}

fn native_pclose(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .{ .int = -1 };
    const obj = args[0].object;
    const cmd_v = obj.get("__popen_cmd");
    if (cmd_v == .string) {
        const buf_v = obj.get("__buffer");
        const stdin_data: []const u8 = if (buf_v == .string) buf_v.string else "";
        const result = runShellCapture(ctx.allocator, cmd_v.string, stdin_data) catch {
            obj.properties.put(std.heap.page_allocator, "__open", .{ .bool = false }) catch {};
            return .{ .int = -1 };
        };
        ctx.allocator.free(result.stdout);
        ctx.allocator.free(result.stderr);
        obj.properties.put(std.heap.page_allocator, "__open", .{ .bool = false }) catch {};
        return .{ .int = result.exit };
    }
    const exit_v = obj.get("__popen_exit");
    obj.properties.put(std.heap.page_allocator, "__open", .{ .bool = false }) catch {};
    if (exit_v == .int) return .{ .int = exit_v.int };
    return .{ .int = 0 };
}

fn native_proc_open(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[0] != .string) return .{ .bool = false };
    const cmd = args[0].string;
    const result = runShellCapture(ctx.allocator, cmd, null) catch return .{ .bool = false };
    try ctx.vm.strings.append(ctx.allocator, result.stdout);
    try ctx.vm.strings.append(ctx.allocator, result.stderr);

    if (args[2] == .array) {
        const pipes = args[2].array;
        // stdin (write-only no-op handle - process already ran)
        const stdin_obj = try ctx.allocator.create(PhpObject);
        stdin_obj.* = .{ .class_name = "FileHandle" };
        try ctx.vm.objects.append(ctx.allocator, stdin_obj);
        try stdin_obj.set(ctx.allocator, "__buffer", .{ .string = "" });
        try stdin_obj.set(ctx.allocator, "__pos", .{ .int = 0 });
        try stdin_obj.set(ctx.allocator, "__open", .{ .bool = true });
        try stdin_obj.set(ctx.allocator, "__mode", .{ .string = "w" });
        try pipes.set(ctx.allocator, .{ .int = 0 }, .{ .object = stdin_obj });
        try pipes.set(ctx.allocator, .{ .int = 1 }, .{ .object = try makeReadBufferHandle(ctx, result.stdout) });
        try pipes.set(ctx.allocator, .{ .int = 2 }, .{ .object = try makeReadBufferHandle(ctx, result.stderr) });
    }

    const proc = try ctx.allocator.create(PhpObject);
    proc.* = .{ .class_name = "ProcessResource" };
    try ctx.vm.objects.append(ctx.allocator, proc);
    try proc.set(ctx.allocator, "__cmd", .{ .string = try ctx.vm.allocator.dupe(u8, cmd) });
    try proc.set(ctx.allocator, "__exit", .{ .int = result.exit });
    try proc.set(ctx.allocator, "__running", .{ .bool = false });
    try ctx.vm.strings.append(ctx.allocator, proc.get("__cmd").string);
    return .{ .object = proc };
}

fn native_proc_close(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .{ .int = -1 };
    const obj = args[0].object;
    const exit = obj.get("__exit");
    if (exit == .int) return .{ .int = exit.int };
    return .{ .int = 0 };
}

fn native_proc_get_status(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .{ .bool = false };
    const obj = args[0].object;
    const result = try ctx.allocator.create(PhpArray);
    result.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, result);
    const cmd = obj.get("__cmd");
    const exit = obj.get("__exit");
    try result.set(ctx.allocator, .{ .string = "command" }, if (cmd == .string) cmd else .{ .string = "" });
    try result.set(ctx.allocator, .{ .string = "pid" }, .{ .int = 0 });
    try result.set(ctx.allocator, .{ .string = "running" }, .{ .bool = false });
    try result.set(ctx.allocator, .{ .string = "signaled" }, .{ .bool = false });
    try result.set(ctx.allocator, .{ .string = "stopped" }, .{ .bool = false });
    try result.set(ctx.allocator, .{ .string = "exitcode" }, if (exit == .int) exit else .{ .int = 0 });
    try result.set(ctx.allocator, .{ .string = "termsig" }, .{ .int = 0 });
    try result.set(ctx.allocator, .{ .string = "stopsig" }, .{ .int = 0 });
    return .{ .array = result };
}

fn native_proc_terminate(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = true };
}

fn native_stream_set_blocking(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = true };
}

fn native_stream_set_timeout(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = true };
}

fn native_stream_set_read_buffer(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = 0 };
}

fn native_stream_set_write_buffer(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = 0 };
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
    if (data.len >= 5 and std.mem.eql(u8, data[0..5], "<?xml")) return "application/xml";
    if (data.len >= 5 and std.mem.eql(u8, data[0..5], "<?php")) return "text/x-php";
    return null;
}

fn native_mime_content_type(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const path = args[0].string;
    const file = std.fs.cwd().openFile(path, .{}) catch {
        return .{ .string = try ctx.createString(mimeFromExt(path)) };
    };
    defer file.close();
    var buf: [16]u8 = undefined;
    const n = file.read(&buf) catch return .{ .string = try ctx.createString(mimeFromExt(path)) };
    if (detectMimeFromBytes(buf[0..n])) |m| return .{ .string = try ctx.createString(m) };
    return .{ .string = try ctx.createString(mimeFromExt(path)) };
}

const c_statvfs = @cImport({
    @cInclude("sys/statvfs.h");
});

fn native_disk_free_space(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const path_z = try ctx.allocator.allocSentinel(u8, args[0].string.len, 0);
    defer ctx.allocator.free(path_z);
    @memcpy(path_z[0..args[0].string.len], args[0].string);
    var st: c_statvfs.struct_statvfs = undefined;
    if (c_statvfs.statvfs(path_z, &st) != 0) return .{ .bool = false };
    return .{ .float = @floatFromInt(@as(u64, st.f_bavail) * @as(u64, st.f_frsize)) };
}

fn native_disk_total_space(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const path_z = try ctx.allocator.allocSentinel(u8, args[0].string.len, 0);
    defer ctx.allocator.free(path_z);
    @memcpy(path_z[0..args[0].string.len], args[0].string);
    var st: c_statvfs.struct_statvfs = undefined;
    if (c_statvfs.statvfs(path_z, &st) != 0) return .{ .bool = false };
    return .{ .float = @floatFromInt(@as(u64, st.f_blocks) * @as(u64, st.f_frsize)) };
}

fn native_linkinfo(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .int = -1 };
    const stat = std.fs.cwd().statFile(args[0].string) catch return .{ .int = -1 };
    return .{ .int = @intCast(stat.inode) };
}

fn native_finfo_open(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = try ctx.allocator.create(PhpObject);
    obj.* = .{ .class_name = "finfo" };
    try ctx.vm.objects.append(ctx.allocator, obj);
    return .{ .object = obj };
}

fn native_finfo_file(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[1] != .string) return .{ .bool = false };
    return native_mime_content_type(ctx, &.{args[1]});
}

fn native_finfo_buffer(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[1] != .string) return .{ .bool = false };
    if (detectMimeFromBytes(args[1].string)) |m| return .{ .string = try ctx.createString(m) };
    return .{ .string = "application/octet-stream" };
}

fn native_finfo_close(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = true };
}
