const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const std = @import("std");
const platform = @import("../platform.zig");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const phar = @import("phar.zig");
const phar_path = @import("phar_path.zig");
const zlib = @cImport(@cInclude("zlib.h"));

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = common_entries ++ (if (platform.is_windows) @import("filesystem_win.zig").entries else posix_entries);

// natives that are posix calls here and something else on windows
const posix_entries = .{
    .{ "chown", native_chown },
    .{ "chgrp", native_chgrp },
    .{ "lchown", native_chown },
    .{ "lchgrp", native_chgrp },
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
    .{ "tempnam", native_tempnam },
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
    if (obj.get("__proc_ref") == .object) return false;
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
    // to the underlying DirectoryHandle stored in the 'handle' property
    var dir_def = ClassDef{ .name = "Directory" };
    try dir_def.properties.append(a, .{ .name = "path", .default = .{ .string = Value.String.borrowed("") } });
    try dir_def.properties.append(a, .{ .name = "handle", .default = .null });
    try dir_def.methods.put(a, "read", .{ .name = "read", .arity = 0 });
    try dir_def.methods.put(a, "rewind", .{ .name = "rewind", .arity = 0 });
    try dir_def.methods.put(a, "close", .{ .name = "close", .arity = 0 });
    try vm.classes.put(a, "Directory", dir_def);
    try vm.native_fns.put(a, "Directory::read", directoryRead);
    try vm.native_fns.put(a, "Directory::rewind", directoryRewind);
    try vm.native_fns.put(a, "Directory::close", directoryClose);

    inline for (.{ .{ "STDIN", 0, "r" }, .{ "STDOUT", 1, "w" }, .{ "STDERR", 2, "w" } }) |spec| {
        const obj = try a.create(PhpObject);
        obj.* = .{ .class_name = "FileHandle" };
        try obj.set(a, "__fd", .{ .int = spec[1] });
        try obj.set(a, "__open", .{ .bool = true });
        try obj.set(a, "__mode", .{ .string = Value.String.borrowed(spec[2]) });
        try vm.objects.append(a, obj);
        try vm.php_constants.put(a, spec[0], .{ .object = obj });
    }
}

fn isNetStream(obj: *PhpObject) bool {
    const net = obj.get("__net");
    return net == .bool and net.bool;
}

// a socket is a handle of its own on windows, not a crt descriptor
fn getFileHandle(obj: *PhpObject) ?std.fs.File {
    const v = obj.get("__fd");
    if (v != .int or v.int < 0) return null;
    if (platform.is_windows and isNetStream(obj)) return .{ .handle = platform.socketFromInt(v.int) orelse return null };
    return platform.fileFromFd(v.int);
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

// parses "data://[mediatype][;base64],<data>" into the decoded byte payload.
// returns null on malformed input (no comma, bad base64)
fn parseDataUri(a: Allocator, path: []const u8) !?[]u8 {
    // PHP accepts both "data:" (RFC 2397) and the "data://" stream-wrapper form
    const rest: []const u8 = if (std.mem.startsWith(u8, path, "data://"))
        path[7..]
    else if (std.mem.startsWith(u8, path, "data:"))
        path[5..]
    else
        return null;
    const comma = std.mem.indexOfScalar(u8, rest, ',') orelse return null;
    const meta = rest[0..comma];
    const data = rest[comma + 1 ..];
    const is_base64 = std.mem.endsWith(u8, meta, ";base64");
    const decoded = try percentDecode(a, data);
    if (!is_base64) return decoded;
    defer a.free(decoded);
    return try base64DecodeBytes(a, decoded);
}

pub fn cleanupHandle(obj: *PhpObject) void {
    if (obj.pooled or !std.mem.eql(u8, obj.class_name, "FileHandle")) return;
    if (obj.get("__proc_ref") == .object) return;
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

// file read/write

const c_curl = @cImport({
    @cInclude("curl/curl.h");
});

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
        .buffer = .{},
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
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    var path = args[0].string.bytes();
    if (std.mem.startsWith(u8, path, "file://")) path = path[7..];
    if (userWrapperFor(ctx.vm, path)) |class_name| {
        const opened = (try dispatchUserOpen(ctx, class_name, path, "rb")) orelse return NativeResult.scalar(.{ .bool = false });
        const fh = opened.object;
        const wrapper = fileHandleWrapper(fh) orelse return NativeResult.scalar(.{ .bool = false });
        var buf = std.ArrayListUnmanaged(u8){};
        defer buf.deinit(ctx.allocator);
        while (true) {
            const chunk = try ctx.callMethod(wrapper, "stream_read", &[_]Value{.{ .int = 8192 }});
            if (chunk != .string or chunk.string.bytes().len == 0) break;
            try buf.appendSlice(ctx.allocator, chunk.string.bytes());
        }
        if (ctx.vm.hasMethod(fh.class_name, "stream_close") or ctx.vm.hasMethod(wrapper.class_name, "stream_close")) {
            _ = try ctx.callMethod(wrapper, "stream_close", &.{});
        }
        const owned = try buf.toOwnedSlice(ctx.allocator);
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, owned));
    }
    if (extractScheme(path)) |s| {
        if (isBuiltinWrapper(s) and isWrapperUnregistered(ctx.vm, s)) return NativeResult.scalar(.{ .bool = false });
    }
    if (std.mem.eql(u8, path, "php://input")) {
        const body_val = ctx.vm.request_vars.get("__raw_body") orelse return NativeResult.literal("");
        if (body_val == .string) return NativeResult.share(body_val);
        return NativeResult.literal("");
    }
    if (std.mem.eql(u8, path, "php://stdin")) {
        const stdin = std.fs.File.stdin();
        const data = stdin.readToEndAlloc(ctx.allocator, 1024 * 1024 * 64) catch return NativeResult.scalar(.{ .bool = false });
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, data));
    }
    if (std.mem.eql(u8, path, "php://stdout") or std.mem.eql(u8, path, "php://output") or std.mem.eql(u8, path, "php://stderr")) {
        return NativeResult.literal("");
    }
    if (std.mem.startsWith(u8, path, "data:")) {
        const payload = (parseDataUri(ctx.allocator, path) catch return NativeResult.scalar(.{ .bool = false })) orelse return NativeResult.scalar(.{ .bool = false });
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, payload));
    }
    if (std.mem.startsWith(u8, path, "phar://")) {
        const r = resolvePharPathWithCtx(path, ctx) orelse return NativeResult.scalar(.{ .bool = false });
        const payload = (readPharEntry(ctx.allocator, r.archive_path, r.internal_path) catch return NativeResult.scalar(.{ .bool = false })) orelse return NativeResult.scalar(.{ .bool = false });
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, payload));
    }
    if (std.mem.startsWith(u8, path, ZLIB_PREFIX)) {
        const decoded = readZlibFile(ctx.allocator, path) catch return NativeResult.scalar(.{ .bool = false });
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, decoded));
    }
    if (path.len > 7 and (std.mem.startsWith(u8, path, "http://") or std.mem.startsWith(u8, path, "https://"))) {
        return fetchUrl(ctx, path);
    }
    const content = std.fs.cwd().readFileAlloc(ctx.allocator, path, 1024 * 1024 * 64) catch return NativeResult.scalar(.{ .bool = false });

    // optional offset (4th arg) and length (5th arg)
    if (args.len >= 4 and args[3] != .null) {
        defer ctx.allocator.free(content);
        const total_i: i64 = @intCast(content.len);
        var offset = Value.toInt(args[3]);
        if (offset < 0) offset = @max(0, total_i + offset);
        if (offset > total_i) offset = total_i;
        const ustart: usize = @intCast(offset);
        const have_len = args.len >= 5 and args[4] != .null;
        const length: i64 = if (have_len) Value.toInt(args[4]) else total_i - offset;
        if (length < 0) return NativeResult.scalar(.{ .bool = false });
        const finish = @min(content.len, ustart + @as(usize, @intCast(length)));
        return try NativeResult.copyString(ctx.allocator, content[ustart..finish]);
    }

    const owned = Value.String.adopt(ctx.allocator, content) catch |err| {
        ctx.allocator.free(content);
        return err;
    };
    return NativeResult.takeString(owned);
}

fn native_file_put_contents(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const path = args[0].string.bytes();
    const data = if (args[1] == .string) args[1].string.bytes() else if (args[1] == .array) blk: {
        // PHP writes an array argument as its elements concatenated, like
        // implode('', $array) - each element coerced to string
        var buf = std.ArrayListUnmanaged(u8){};
        for (args[1].array.entries.items) |entry| {
            try entry.value.format(&buf, ctx.allocator);
        }
        const s = try buf.toOwnedSlice(ctx.allocator);
        try ctx.strings.append(ctx.allocator, s);
        break :blk s;
    } else blk: {
        var buf = std.ArrayListUnmanaged(u8){};
        try args[1].format(&buf, ctx.allocator);
        const s = try buf.toOwnedSlice(ctx.allocator);
        try ctx.strings.append(ctx.allocator, s);
        break :blk s;
    };
    if (userWrapperFor(ctx.vm, path)) |class_name| {
        const opened = (try dispatchUserOpen(ctx, class_name, path, "wb")) orelse return NativeResult.scalar(.{ .bool = false });
        const wrapper = fileHandleWrapper(opened.object) orelse return NativeResult.scalar(.{ .bool = false });
        const written = try ctx.callMethod(wrapper, "stream_write", &[_]Value{.{ .string = Value.String.borrowed(data) }});
        if (ctx.vm.hasMethod(wrapper.class_name, "stream_close")) {
            _ = try ctx.callMethod(wrapper, "stream_close", &.{});
        }
        if (written != .int) return NativeResult.scalar(.{ .bool = false });
        return NativeResult.scalar(.{ .int = written.int });
    }
    if (extractScheme(path)) |s| {
        if (isBuiltinWrapper(s) and isWrapperUnregistered(ctx.vm, s)) return NativeResult.scalar(.{ .bool = false });
    }
    if (std.mem.eql(u8, path, "php://stdout") or std.mem.eql(u8, path, "php://output")) {
        try ctx.vm.output.appendSlice(ctx.allocator, data);
        return NativeResult.scalar(.{ .int = @intCast(data.len) });
    }
    if (std.mem.eql(u8, path, "php://stderr")) {
        if (ctx.vm.output.items.len > 0) {
            const stdout = std.fs.File.stdout();
            _ = stdout.write(ctx.vm.output.items) catch {};
            ctx.vm.output.clearRetainingCapacity();
        }
        const stderr = std.fs.File.stderr();
        const n = stderr.write(data) catch return NativeResult.scalar(.{ .bool = false });
        return NativeResult.scalar(.{ .int = @intCast(n) });
    }
    if (std.mem.startsWith(u8, path, ZLIB_PREFIX)) {
        writeZlibFile(ctx.allocator, path, data) catch return NativeResult.scalar(.{ .bool = false });
        return NativeResult.scalar(.{ .int = @intCast(data.len) });
    }
    const flags: i64 = if (args.len >= 3) Value.toInt(args[2]) else 0;
    const append = (flags & 8) != 0; // FILE_APPEND = 8
    if (append) {
        const file = std.fs.cwd().openFile(path, .{ .mode = .write_only }) catch {
            std.fs.cwd().writeFile(.{ .sub_path = path, .data = data }) catch return NativeResult.scalar(.{ .bool = false });
            return NativeResult.scalar(.{ .int = @intCast(data.len) });
        };
        defer file.close();
        file.seekFromEnd(0) catch return NativeResult.scalar(.{ .bool = false });
        _ = file.write(data) catch return NativeResult.scalar(.{ .bool = false });
    } else {
        std.fs.cwd().writeFile(.{ .sub_path = path, .data = data }) catch return NativeResult.scalar(.{ .bool = false });
    }
    return NativeResult.scalar(.{ .int = @intCast(data.len) });
}

fn native_file_exists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const path = args[0].string.bytes();
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
        std.fs.cwd().access(path[ZLIB_PREFIX.len..], .{}) catch return NativeResult.scalar(Value{ .bool = false });
        return NativeResult.scalar(.{ .bool = true });
    }
    std.fs.cwd().access(path, .{}) catch return NativeResult.scalar(Value{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn native_is_file(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    const path = if (args[0] == .string) args[0].string.bytes() else if (args[0] == .object and ctx.vm.hasMethod(args[0].object.class_name, "__toString")) try ctx.vm.objectToString(args[0].object) else return NativeResult.scalar(.{ .bool = false });
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
        const stat = std.fs.cwd().statFile(path[ZLIB_PREFIX.len..]) catch return NativeResult.scalar(Value{ .bool = false });
        return NativeResult.scalar(.{ .bool = stat.kind == .file });
    }
    const stat = std.fs.cwd().statFile(path) catch return NativeResult.scalar(Value{ .bool = false });
    return NativeResult.scalar(.{ .bool = stat.kind == .file });
}

fn native_is_dir(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    const path = if (args[0] == .string) args[0].string.bytes() else if (args[0] == .object and ctx.vm.hasMethod(args[0].object.class_name, "__toString")) try ctx.vm.objectToString(args[0].object) else return NativeResult.scalar(.{ .bool = false });
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
    var dir = std.fs.cwd().openDir(path, .{}) catch return NativeResult.scalar(Value{ .bool = false });
    dir.close();
    return NativeResult.scalar(.{ .bool = true });
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
        (if (pos == 0) platform.sep_str else try ctx.createString(path[0..pos]))
    else
        ".";
    const base: []const u8 = if (lastSep(path)) |pos| try ctx.createString(path[pos + 1 ..]) else path;
    const has_dot = std.mem.lastIndexOf(u8, base, ".") != null;
    const dot_pos: usize = if (has_dot) std.mem.lastIndexOf(u8, base, ".").? else 0;
    const ext: []const u8 = if (has_dot) try ctx.createString(base[dot_pos + 1 ..]) else "";
    const filename: []const u8 = if (has_dot) try ctx.createString(base[0..dot_pos]) else base;

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
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("dirname") }, .{ .string = Value.String.borrowed(try ctx.createString(dir)) });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("basename") }, .{ .string = Value.String.borrowed(try ctx.createString(base)) });
    if (has_dot) {
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("extension") }, .{ .string = Value.String.borrowed(try ctx.createString(ext)) });
    }
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("filename") }, .{ .string = Value.String.borrowed(try ctx.createString(filename)) });
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_realpath(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const resolved = std.fs.cwd().realpath(args[0].string.bytes(), &buf) catch return NativeResult.scalar(Value{ .bool = false });
    return NativeResult.copyString(ctx.allocator, resolved);
}

// directory operations

fn native_mkdir(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const path = args[0].string.bytes();
    const recursive = args.len >= 3 and args[2].isTruthy();
    if (recursive) {
        std.fs.cwd().makePath(path) catch return NativeResult.scalar(Value{ .bool = false });
    } else {
        std.fs.cwd().makeDir(path) catch return NativeResult.scalar(Value{ .bool = false });
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn native_rmdir(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    std.fs.cwd().deleteDir(args[0].string.bytes()) catch return NativeResult.scalar(Value{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn native_unlink(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const path = args[0].string.bytes();
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
    std.fs.cwd().deleteFile(path) catch return NativeResult.scalar(Value{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn native_copy(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const source = if (args[0] == .string) args[0].string.bytes() else if (args[0] == .object and ctx.vm.hasMethod(args[0].object.class_name, "__toString")) try ctx.vm.objectToString(args[0].object) else return NativeResult.scalar(.{ .bool = false });
    std.fs.cwd().copyFile(source, std.fs.cwd(), args[1].string.bytes(), .{}) catch return NativeResult.scalar(Value{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn native_rename(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    std.fs.cwd().rename(args[0].string.bytes(), args[1].string.bytes()) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

// directory listing

fn native_scandir(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    // SCANDIR_SORT_ASCENDING=0, _DESCENDING=1, _NONE=2
    const order: i64 = if (args.len >= 2 and args[1] == .int) args[1].int else 0;
    var dir = std.fs.cwd().openDir(args[0].string.bytes(), .{ .iterate = true }) catch return NativeResult.scalar(.{ .bool = false });
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
    for (names.items) |n| try result.append(ctx.allocator, .{ .string = Value.String.borrowed(n) });
    return NativeResult.borrowed(.{ .array = result });
}

// dir($path) returns a Directory object with path, handle, and read/rewind/
// close methods that delegate to the underlying DirectoryHandle. PHP's
// 'Directory' is a thin OO wrapper around opendir/readdir/rewinddir/closedir
fn native_dir(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const handle = (try native_opendir(ctx, args)).value;
    if (handle != .object) return NativeResult.scalar(.{ .bool = false });
    const obj = try ctx.createObject("Directory");
    try obj.set(ctx.allocator, "path", .{ .string = args[0].string });
    try obj.set(ctx.allocator, "handle", handle);
    return NativeResult.borrowed(.{ .object = obj });
}

fn directoryRead(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = ctx.vm.currentFrame().vars.get("$this") orelse return NativeResult.scalar(.{ .bool = false });
    if (this != .object) return NativeResult.scalar(.{ .bool = false });
    const h = this.object.get("handle");
    if (h != .object) return NativeResult.scalar(.{ .bool = false });
    return native_readdir(ctx, &.{h});
}

fn directoryRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = ctx.vm.currentFrame().vars.get("$this") orelse return NativeResult.scalar(.null);
    if (this != .object) return NativeResult.scalar(.null);
    const h = this.object.get("handle");
    if (h != .object) return NativeResult.scalar(.null);
    return native_rewinddir(ctx, &.{h});
}

fn directoryClose(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = ctx.vm.currentFrame().vars.get("$this") orelse return NativeResult.scalar(.null);
    if (this != .object) return NativeResult.scalar(.null);
    const h = this.object.get("handle");
    if (h != .object) return NativeResult.scalar(.null);
    return native_closedir(ctx, &.{h});
}

fn native_opendir(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    var dir = std.fs.cwd().openDir(args[0].string.bytes(), .{ .iterate = true }) catch return NativeResult.scalar(.{ .bool = false });
    defer dir.close();
    const names_arr = try ctx.allocator.create(PhpArray);
    names_arr.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, names_arr);
    try names_arr.append(ctx.allocator, .{ .string = Value.String.borrowed(".") });
    try names_arr.append(ctx.allocator, .{ .string = Value.String.borrowed("..") });
    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        const name = try ctx.createString(entry.name);
        try names_arr.append(ctx.allocator, .{ .string = Value.String.borrowed(name) });
    }
    const obj = try ctx.allocator.create(PhpObject);
    obj.* = .{ .class_name = "DirectoryHandle" };
    try obj.set(ctx.allocator, "__entries", .{ .array = names_arr });
    try obj.set(ctx.allocator, "__pos", .{ .int = 0 });
    try obj.set(ctx.allocator, "__open", .{ .bool = true });
    try ctx.vm.objects.append(ctx.allocator, obj);
    return NativeResult.borrowed(.{ .object = obj });
}

fn native_readdir(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const obj = args[0].object;
    const open = obj.get("__open");
    if (open != .bool or !open.bool) return NativeResult.scalar(.{ .bool = false });
    const dir_entries = obj.get("__entries");
    if (dir_entries != .array) return NativeResult.scalar(.{ .bool = false });
    const pos = Value.toInt(obj.get("__pos"));
    if (pos < 0 or pos >= dir_entries.array.length()) return NativeResult.scalar(.{ .bool = false });
    const entry = dir_entries.array.entries.items[@intCast(pos)].value;
    try obj.set(ctx.allocator, "__pos", .{ .int = pos + 1 });
    return NativeResult.share(entry);
}

fn native_closedir(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.null);
    const obj = args[0].object;
    try obj.set(ctx.allocator, "__open", .{ .bool = false });
    return NativeResult.scalar(.null);
}

fn native_rewinddir(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.null);
    const obj = args[0].object;
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
        try result.append(ctx.allocator, .{ .string = Value.String.borrowed(try ctx.createString(pattern)) });
    }
    _ = GLOB_ONLYDIR;
    return NativeResult.borrowed(.{ .array = result });
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
        try result.append(ctx.allocator, .{ .string = Value.String.borrowed(try ctx.createString(full)) });
    }
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
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    if (std.mem.startsWith(u8, args[0].string.bytes(), "phar://")) return native_is_file(ctx, args);
    std.fs.cwd().access(args[0].string.bytes(), .{ .mode = .read_only }) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn native_is_writable(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const path = args[0].string.bytes();
    std.fs.cwd().access(path, .{ .mode = .write_only }) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = !platform.isReadOnly(path) });
}

fn native_is_executable(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const path = args[0].string.bytes();
    if (platform.is_windows) {
        std.fs.cwd().access(path, .{}) catch return NativeResult.scalar(.{ .bool = false });
        const ext = std.fs.path.extension(path);
        inline for (.{ ".exe", ".bat", ".cmd", ".com" }) |e| if (std.ascii.eqlIgnoreCase(ext, e)) return NativeResult.scalar(.{ .bool = true });
        return NativeResult.scalar(.{ .bool = false });
    }
    std.posix.access(path, std.posix.X_OK) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn native_filesize(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const stat = platform.statPath(args[0].string.bytes()) catch return NativeResult.scalar(Value{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(stat.size) });
}

fn native_filemtime(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const stat = platform.statPath(args[0].string.bytes()) catch return NativeResult.scalar(Value{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(@divFloor(stat.mtime, 1_000_000_000)) });
}

fn native_fileatime(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const stat = platform.statPath(args[0].string.bytes()) catch return NativeResult.scalar(Value{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(@divFloor(stat.atime, 1_000_000_000)) });
}

fn native_filectime(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const stat = platform.statPath(args[0].string.bytes()) catch return NativeResult.scalar(Value{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(@divFloor(stat.ctime, 1_000_000_000)) });
}

fn native_fileinode(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const stat = platform.statPath(args[0].string.bytes()) catch return NativeResult.scalar(Value{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(stat.inode) });
}

fn native_filetype(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const stat = platform.statPath(args[0].string.bytes()) catch {
        // might be a directory
        var dir = std.fs.cwd().openDir(args[0].string.bytes(), .{}) catch return NativeResult.scalar(.{ .bool = false });
        dir.close();
        return NativeResult.literal("dir");
    };
    return try NativeResult.copyString(ctx.allocator, switch (stat.kind) {
        .file => "file",
        .directory => "dir",
        .sym_link => "link",
        else => "unknown",
    });
}

// read file into array of lines

fn native_file(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const content = std.fs.cwd().readFileAlloc(ctx.allocator, args[0].string.bytes(), 1024 * 1024 * 64) catch return NativeResult.scalar(.{ .bool = false });
    try ctx.strings.append(ctx.allocator, content);

    const flags: i64 = if (args.len >= 2) Value.toInt(args[1]) else 0;
    const ignore_newlines = (flags & 2) != 0; // FILE_IGNORE_NEW_LINES = 2
    // PHP: FILE_SKIP_EMPTY_LINES only takes effect when combined with FILE_IGNORE_NEW_LINES
    const skip_empty = (flags & 4) != 0 and ignore_newlines;

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
            try result.append(ctx.allocator, .{ .string = Value.String.borrowed(line) });
            start = i + 1;
        }
    }
    if (start < content.len) {
        const remaining = content[start..];
        if (!skip_empty or remaining.len > 0) {
            const line = try ctx.createString(remaining);
            try result.append(ctx.allocator, .{ .string = Value.String.borrowed(line) });
        }
    }
    return NativeResult.borrowed(.{ .array = result });
}

fn native_readfile(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const content = std.fs.cwd().readFileAlloc(ctx.allocator, args[0].string.bytes(), 1024 * 1024 * 64) catch return NativeResult.scalar(.{ .bool = false });
    defer ctx.allocator.free(content);
    try ctx.vm.output.appendSlice(ctx.allocator, content);
    return NativeResult.scalar(.{ .int = @intCast(content.len) });
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
    try ctx.strings.append(ctx.allocator, wrapped);
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
    const path = if (args[0] == .string) args[0].string.bytes() else if (args[0] == .object and ctx.vm.hasMethod(args[0].object.class_name, "__toString")) try ctx.vm.objectToString(args[0].object) else return NativeResult.scalar(.{ .bool = false });
    const mode = args[1].string.bytes();

    if (userWrapperFor(ctx.vm, path)) |class_name| {
        return NativeResult.borrowed((try dispatchUserOpen(ctx, class_name, path, mode)) orelse Value{ .bool = false });
    }
    if (extractScheme(path)) |s| {
        if (isBuiltinWrapper(s) and isWrapperUnregistered(ctx.vm, s)) return NativeResult.scalar(.{ .bool = false });
    }

    if (std.mem.eql(u8, path, "php://stdout") or std.mem.eql(u8, path, "php://output")) {
        const obj = try ctx.createObject("FileHandle");
        try obj.set(ctx.allocator, "__fd", .{ .int = 1 });
        try obj.set(ctx.allocator, "__open", .{ .bool = true });
        try obj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed("w") });
        return NativeResult.borrowed(.{ .object = obj });
    }
    if (std.mem.eql(u8, path, "php://stderr")) {
        const obj = try ctx.createObject("FileHandle");
        try obj.set(ctx.allocator, "__fd", .{ .int = 2 });
        try obj.set(ctx.allocator, "__open", .{ .bool = true });
        try obj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed("w") });
        return NativeResult.borrowed(.{ .object = obj });
    }
    if (std.mem.eql(u8, path, "php://stdin")) {
        const obj = try ctx.createObject("FileHandle");
        try obj.set(ctx.allocator, "__fd", .{ .int = 0 });
        try obj.set(ctx.allocator, "__open", .{ .bool = true });
        try obj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed("r") });
        return NativeResult.borrowed(.{ .object = obj });
    }
    if (std.mem.eql(u8, path, "php://input")) {
        const body_val = ctx.vm.request_vars.get("__raw_body");
        const body: []const u8 = if (body_val != null and body_val.? == .string) body_val.?.string.bytes() else "";
        const obj = try ctx.createObject("FileHandle");
        try obj.set(ctx.allocator, "__buffer", .{ .string = Value.String.borrowed(body) });
        try obj.set(ctx.allocator, "__pos", .{ .int = 0 });
        try obj.set(ctx.allocator, "__open", .{ .bool = true });
        try obj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed("r") });
        return NativeResult.borrowed(.{ .object = obj });
    }
    if (std.mem.startsWith(u8, path, "data:")) {
        const payload = (parseDataUri(ctx.allocator, path) catch return NativeResult.scalar(.{ .bool = false })) orelse return NativeResult.scalar(.{ .bool = false });
        try ctx.strings.append(ctx.allocator, payload);
        const obj = try ctx.createObject("FileHandle");
        try obj.set(ctx.allocator, "__buffer", .{ .string = Value.String.borrowed(payload) });
        try obj.set(ctx.allocator, "__pos", .{ .int = 0 });
        try obj.set(ctx.allocator, "__open", .{ .bool = true });
        try obj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed("r") });
        return NativeResult.borrowed(.{ .object = obj });
    }
    if (std.mem.startsWith(u8, path, "phar://")) {
        const r = resolvePharPathWithCtx(path, ctx) orelse return NativeResult.scalar(.{ .bool = false });
        const payload = (readPharEntry(ctx.allocator, r.archive_path, r.internal_path) catch return NativeResult.scalar(.{ .bool = false })) orelse return NativeResult.scalar(.{ .bool = false });
        try ctx.strings.append(ctx.allocator, payload);
        const obj = try ctx.createObject("FileHandle");
        try obj.set(ctx.allocator, "__buffer", .{ .string = Value.String.borrowed(payload) });
        try obj.set(ctx.allocator, "__pos", .{ .int = 0 });
        try obj.set(ctx.allocator, "__open", .{ .bool = true });
        try obj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed("r") });
        return NativeResult.borrowed(.{ .object = obj });
    }
    if (std.mem.startsWith(u8, path, ZLIB_PREFIX)) {
        const is_write = mode.len >= 1 and (mode[0] == 'w' or mode[0] == 'a' or mode[0] == 'x');
        const obj = try ctx.createObject("FileHandle");
        try obj.set(ctx.allocator, "__open", .{ .bool = true });
        try obj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed(mode) });
        try obj.set(ctx.allocator, "__zlib_path", .{ .string = Value.String.borrowed(try ctx.createString(path)) });
        if (is_write) {
            try obj.set(ctx.allocator, "__zlib_writing", .{ .bool = true });
            try obj.set(ctx.allocator, "__buffer", .{ .string = Value.String.borrowed("") });
            try obj.set(ctx.allocator, "__pos", .{ .int = 0 });
        } else {
            const decoded = readZlibFile(ctx.allocator, path) catch {
                obj.set(ctx.allocator, "__open", .{ .bool = false }) catch {};
                return NativeResult.scalar(.{ .bool = false });
            };
            try ctx.strings.append(ctx.allocator, decoded);
            try obj.set(ctx.allocator, "__buffer", .{ .string = Value.String.borrowed(decoded) });
            try obj.set(ctx.allocator, "__pos", .{ .int = 0 });
        }
        return NativeResult.borrowed(.{ .object = obj });
    }

    const is_memory_stream = std.mem.startsWith(u8, path, "php://temp") or std.mem.startsWith(u8, path, "php://memory");
    const file = if (is_memory_stream) blk: {
        const tmp = std.fmt.allocPrint(ctx.allocator, "{s}{c}zphp_{d}", .{ platform.tempDir(), std.fs.path.sep, @as(u64, @truncate(@as(u128, @bitCast(std.time.nanoTimestamp()))))}) catch return NativeResult.scalar(.{ .bool = false });
        defer ctx.allocator.free(tmp);
        const f = std.fs.cwd().createFile(tmp, .{ .read = true, .truncate = true }) catch return NativeResult.scalar(.{ .bool = false });
        std.fs.cwd().deleteFile(tmp) catch {};
        break :blk f;
    } else openWithMode(path, mode) catch |err| {
        const reason = openErrorReason(err);
        const msg = std.fmt.allocPrint(ctx.allocator, "fopen({s}): Failed to open stream: {s}", .{ path, reason }) catch return NativeResult.scalar(.{ .bool = false });
        ctx.vm.strings.append(ctx.allocator, msg) catch {};
        ctx.vm.emitWarning(msg);
        return NativeResult.scalar(.{ .bool = false });
    };

    const obj = try ctx.createObject("FileHandle");
    try obj.set(ctx.allocator, "__fd", .{ .int = platform.fdFromFile(file) });
    try obj.set(ctx.allocator, "__open", .{ .bool = true });
    try obj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed(mode) });
    try obj.set(ctx.allocator, "__path", .{ .string = Value.String.borrowed(try ctx.createString(path)) });
    if (is_memory_stream) try obj.set(ctx.allocator, "__peek_eof", .{ .bool = true });
    return NativeResult.borrowed(.{ .object = obj });
}

fn openErrorReason(err: anyerror) []const u8 {
    return switch (err) {
        error.FileNotFound => "No such file or directory",
        error.PathAlreadyExists => "File exists",
        error.AccessDenied, error.PermissionDenied => "Permission denied",
        error.IsDir => "Is a directory",
        error.NotDir => "Not a directory",
        error.NameTooLong => "File name too long",
        error.SymLinkLoop => "Too many levels of symbolic links",
        error.NoSpaceLeft => "No space left on device",
        error.ReadOnlyFileSystem => "Read-only file system",
        else => "Unknown error",
    };
}

pub fn openWithMode(path: []const u8, mode: []const u8) !std.fs.File {
    if (mode.len == 0) return error.RuntimeError;
    const has_plus = mode.len > 1 and (mode[1] == '+' or (mode.len > 2 and mode[2] == '+'));
    return switch (mode[0]) {
        'r' => std.fs.cwd().openFile(path, .{ .mode = if (has_plus) .read_write else .read_only }),
        'w' => blk: {
            const file = std.fs.cwd().createFile(path, .{ .truncate = true, .read = has_plus }) catch |err| break :blk err;
            break :blk file;
        },
        'a' => blk: {
            break :blk platform.openAppend(path, has_plus);
        },
        'x' => std.fs.cwd().createFile(path, .{ .exclusive = true, .read = has_plus }),
        'c' => blk: {
            // PHP 'c'/'c+' mode: open for writing without truncating; create
            // if it doesn't exist. position is at 0 regardless of existing
            // content (so a subsequent fwrite overwrites from the start)
            const file = std.fs.cwd().openFile(path, .{ .mode = if (has_plus) .read_write else .write_only }) catch
                std.fs.cwd().createFile(path, .{ .read = has_plus, .truncate = false }) catch |err| break :blk err;
            break :blk file;
        },
        else => error.RuntimeError,
    };
}

fn native_fclose(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const obj = args[0].object;
    if (!std.mem.eql(u8, obj.class_name, "FileHandle")) return NativeResult.scalar(.{ .bool = false });
    const open = obj.get("__open");
    if (open != .bool or !open.bool) {
        try ctx.vm.setPendingException("TypeError", "fclose(): Argument #1 ($stream) must be an open stream resource");
        return error.RuntimeError;
    }
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
    if (proc_ref == .object and proc_role == .int) {
        if (ctx.vm.lookupProcChild(proc_ref.object)) |pc| {
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
        obj.properties.put(std.heap.page_allocator, "__popen_cmd", .null) catch {};
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
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.{ .int = 0 });
    var total: i64 = 0;
    const chunk: i64 = 4096;
    while (true) {
        const result = ctx.vm.callByName("fread", &.{ args[0], .{ .int = chunk } }) catch break;
        if (result != .string or result.string.bytes().len == 0) break;
        try ctx.vm.output.appendSlice(ctx.allocator, result.string.bytes());
        total += @intCast(result.string.bytes().len);
        if (result.string.bytes().len < @as(usize, @intCast(chunk))) break;
    }
    return NativeResult.scalar(.{ .int = total });
}

fn native_fread(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .object or args[1] != .int) return NativeResult.scalar(.{ .bool = false });
    const obj = args[0].object;
    if (std.mem.eql(u8, obj.class_name, "FileHandle")) {
        const open = obj.get("__open");
        if (open != .bool or !open.bool) {
            try ctx.vm.setPendingException("TypeError", "fread(): Argument #1 ($stream) must be an open stream resource");
            return error.RuntimeError;
        }
    }
    if (args[1].int <= 0) {
        try ctx.vm.setPendingException("ValueError", "fread(): Argument #2 ($length) must be greater than 0");
        return error.RuntimeError;
    }
    const length: usize = @intCast(args[1].int);
    if (fileHandleWrapper(obj)) |wrapper| {
        const result = try ctx.callMethod(wrapper, "stream_read", &[_]Value{.{ .int = @intCast(length) }});
        if (result == .string) return NativeResult.share(result);
        return NativeResult.literal("");
    }
    if (getBufferBacking(obj)) |buffer| {
        const pos = getBufferPos(obj);
        if (pos >= buffer.len) return NativeResult.literal("");
        const end = @min(pos + length, buffer.len);
        const slice = try ctx.allocator.dupe(u8, buffer[pos..end]);
        setBufferPos(obj, end);
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, slice));
    }
    const file = getFileHandle(obj) orelse return NativeResult.scalar(.{ .bool = false });

    const buf = try ctx.allocator.alloc(u8, length);
    const n = file.read(buf) catch |err| {
        ctx.allocator.free(buf);
        // non-blocking stream with nothing buffered yet reads as "" in php, not a hard failure
        if (err == error.WouldBlock) return NativeResult.literal("");
        return NativeResult.scalar(.{ .bool = false });
    };
    if (n == 0) {
        ctx.allocator.free(buf);
        try obj.set(ctx.allocator, "__eof", .{ .bool = true });
        return NativeResult.literal("");
    }
    if (n < length) try obj.set(ctx.allocator, "__eof", .{ .bool = true });
    // shrink to actual read size
    if (n < length) {
        const exact = try ctx.allocator.alloc(u8, n);
        @memcpy(exact, buf[0..n]);
        ctx.allocator.free(buf);
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, exact));
    }
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, buf));
}

fn native_fwrite(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .object or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = args[0].object;
    if (std.mem.eql(u8, obj.class_name, "FileHandle")) {
        const open = obj.get("__open");
        if (open != .bool or !open.bool) {
            try ctx.vm.setPendingException("TypeError", "fwrite(): Argument #1 ($stream) must be an open stream resource");
            return error.RuntimeError;
        }
    }
    var data = args[1].string.bytes();
    if (args.len >= 3 and args[2] == .int) {
        const lim: i64 = args[2].int;
        if (lim >= 0 and @as(usize, @intCast(lim)) < data.len) data = data[0..@intCast(lim)];
    }
    if (fileHandleWrapper(obj)) |wrapper| {
        const result = try ctx.callMethod(wrapper, "stream_write", &[_]Value{.{ .string = Value.String.borrowed(data) }});
        if (result == .int) return NativeResult.scalar(result);
        return NativeResult.scalar(.{ .int = 0 });
    }
    if (isZlibWriting(obj) or obj.get("__popen_cmd") == .string) {
        const cur = obj.get("__buffer");
        const cur_str: []const u8 = if (cur == .string) cur.string.bytes() else "";
        const combined = try ctx.allocator.alloc(u8, cur_str.len + data.len);
        @memcpy(combined[0..cur_str.len], cur_str);
        @memcpy(combined[cur_str.len..], data);
        try ctx.strings.append(ctx.allocator, combined);
        try obj.set(ctx.allocator, "__buffer", .{ .string = Value.String.borrowed(combined) });
        return NativeResult.scalar(.{ .int = @intCast(data.len) });
    }
    const file = getFileHandle(obj) orelse return NativeResult.scalar(.{ .bool = false });
    // 'a' / 'a+' modes: writes always append, regardless of where the read cursor is
    const mode_v = obj.get("__mode");
    if (mode_v == .string and mode_v.string.bytes().len > 0 and mode_v.string.bytes()[0] == 'a') {
        file.seekFromEnd(0) catch {};
    }
    // route php://stdout and php://output through the VM output buffer so the order
    // matches echo. for php://stderr, flush the buffer first so anything echo'd before
    // this call lands before our stderr write
    if (platform.isStdout(file)) {
        try ctx.vm.output.appendSlice(ctx.allocator, data);
        return NativeResult.scalar(.{ .int = @intCast(data.len) });
    }
    if (platform.isStderr(file)) {
        if (ctx.vm.output.items.len > 0) {
            const stdout = std.fs.File.stdout();
            _ = stdout.write(ctx.vm.output.items) catch {};
            ctx.vm.output.clearRetainingCapacity();
        }
    }
    const written = file.write(data) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(written) });
}

fn native_fgets(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const obj = args[0].object;
    // PHP: fgets($f, length) reads up to length-1 bytes
    const max_len: usize = if (args.len >= 2 and args[1] == .int) @intCast(@max(args[1].int - 1, 1)) else 1024;
    if (getBufferBacking(obj)) |buffer| {
        const pos = getBufferPos(obj);
        if (pos >= buffer.len) return NativeResult.scalar(.{ .bool = false });
        var end = pos;
        while (end < buffer.len and end - pos < max_len) {
            const c = buffer[end];
            end += 1;
            if (c == '\n') break;
        }
        const slice = try ctx.allocator.dupe(u8, buffer[pos..end]);
        setBufferPos(obj, end);
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, slice));
    }
    const file = getFileHandle(obj) orelse return NativeResult.scalar(.{ .bool = false });

    var buf = std.ArrayListUnmanaged(u8){};
    var byte: [1]u8 = undefined;
    var hit_eof = false;
    while (buf.items.len < max_len) {
        const n = file.read(&byte) catch break;
        if (n == 0) {
            hit_eof = true;
            break;
        }
        try buf.append(ctx.allocator, byte[0]);
        if (byte[0] == '\n') break;
    }
    if (hit_eof) try obj.set(ctx.allocator, "__eof", .{ .bool = true });
    if (buf.items.len == 0) return NativeResult.scalar(.{ .bool = false });
    const result = try buf.toOwnedSlice(ctx.allocator);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result));
}

fn native_stream_get_line(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // stream_get_line(handle, length[, ending]) - reads up to length bytes,
    // stopping when `ending` is encountered (consumed but not returned) or EOF
    if (args.len < 2 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const obj = args[0].object;
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
    const file = getFileHandle(obj) orelse return NativeResult.scalar(.{ .bool = false });

    var buf = std.ArrayListUnmanaged(u8){};
    var byte: [1]u8 = undefined;
    var matched: usize = 0;
    while (buf.items.len + matched < cap) {
        const n = file.read(&byte) catch break;
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
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const obj = args[0].object;
    const file = getFileHandle(obj) orelse return NativeResult.scalar(.{ .bool = false });
    var byte: [1]u8 = undefined;
    const n = file.read(&byte) catch return NativeResult.scalar(.{ .bool = false });
    if (n == 0) {
        try obj.set(ctx.allocator, "__eof", .{ .bool = true });
        return NativeResult.scalar(.{ .bool = false });
    }
    const result = try ctx.allocator.dupe(u8, byte[0..1]);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result));
}

fn native_feof(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.{ .bool = true });
    const obj = args[0].object;
    if (std.mem.eql(u8, obj.class_name, "FileHandle")) {
        const open = obj.get("__open");
        if (open != .bool or !open.bool) {
            try ctx.vm.setPendingException("TypeError", "feof(): Argument #1 ($stream) must be an open stream resource");
            return error.RuntimeError;
        }
    }
    if (fileHandleWrapper(obj)) |wrapper| {
        if (!ctx.vm.hasMethod(wrapper.class_name, "stream_eof")) return NativeResult.scalar(.{ .bool = false });
        const result = try ctx.callMethod(wrapper, "stream_eof", &.{});
        return NativeResult.scalar(.{ .bool = result.isTruthy() });
    }
    if (getBufferBacking(obj)) |buffer| {
        return NativeResult.scalar(.{ .bool = getBufferPos(obj) >= buffer.len });
    }
    const file = getFileHandle(obj) orelse return NativeResult.scalar(.{ .bool = true });
    // memory/temp streams use peek-ahead semantics (PHP behavior for those streams)
    const peek_eof = obj.get("__peek_eof");
    if (peek_eof == .bool and peek_eof.bool) {
        var byte: [1]u8 = undefined;
        const n = file.read(&byte) catch return NativeResult.scalar(.{ .bool = true });
        if (n == 0) return NativeResult.scalar(.{ .bool = true });
        file.seekBy(-1) catch {};
        return NativeResult.scalar(.{ .bool = false });
    }
    // PHP file semantics: feof becomes true only after a read attempt returned 0
    const eof = obj.get("__eof");
    return NativeResult.scalar(.{ .bool = eof == .bool and eof.bool });
}

fn native_fseek(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .object or args[1] != .int) return NativeResult.scalar(.{ .int = -1 });
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
        0 => file.seekTo(@intCast(offset)) catch return NativeResult.scalar(.{ .int = -1 }),
        1 => file.seekBy(offset) catch return NativeResult.scalar(.{ .int = -1 }),
        2 => file.seekFromEnd(offset) catch return NativeResult.scalar(.{ .int = -1 }),
        else => return NativeResult.scalar(.{ .int = -1 }),
    }
    try obj.set(ctx.allocator, "__eof", .{ .bool = false });
    return NativeResult.scalar(.{ .int = 0 });
}

fn native_ftell(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const obj = args[0].object;
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
    const pos = file.getPos() catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(pos) });
}

fn native_rewind(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const obj = args[0].object;
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
    file.seekTo(0) catch return NativeResult.scalar(.{ .bool = false });
    try obj.set(ctx.allocator, "__eof", .{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn native_fflush(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    // zig files are unbuffered at our level, this is a no-op
    _ = getFileHandle(args[0].object) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn native_ftruncate(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .object or args[1] != .int) return NativeResult.scalar(.{ .bool = false });
    const file = getFileHandle(args[0].object) orelse return NativeResult.scalar(.{ .bool = false });
    const size: u64 = @intCast(@max(args[1].int, 0));
    file.setEndPos(size) catch return NativeResult.scalar(.{ .bool = false });
    // for php://memory / php://temp, snap the cursor to the new end rather than
    // leaving it past EOF where subsequent writes would create null-padded holes
    const path = args[0].object.get("__path");
    if (path == .string and (std.mem.startsWith(u8, path.string.bytes(), "php://memory") or std.mem.startsWith(u8, path.string.bytes(), "php://temp"))) {
        const cur = file.getPos() catch 0;
        if (cur > size) file.seekTo(size) catch {};
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn native_flock(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .object or args[1] != .int) return NativeResult.scalar(.{ .bool = false });
    const file = getFileHandle(args[0].object) orelse return NativeResult.scalar(.{ .bool = false });
    // PHP renumbers the lock op constants: LOCK_SH=1, LOCK_EX=2, LOCK_UN=3,
    // LOCK_NB=4. translate to the OS values (LOCK_SH=1, LOCK_EX=2, LOCK_NB=4,
    // LOCK_UN=8) before handing to flock(2)
    const php_op = args[1].int;
    const non_block: i32 = if ((php_op & 4) != 0) 4 else 0;
    const base = php_op & 0x3;
    const os_base: i32 = switch (base) {
        1 => 1, // LOCK_SH
        2 => 2, // LOCK_EX
        3 => 8, // LOCK_UN
        else => 0,
    };
    std.posix.flock(file.handle, os_base | non_block) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn stream_get_meta_data(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const obj = args[0].object;
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
    const result = try ctx.createArray();
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("timed_out") }, .{ .bool = false });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("blocked") }, .{ .bool = true });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("eof") }, .{ .bool = false });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("wrapper_type") }, .{ .string = Value.String.borrowed(wrapper_type) });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("stream_type") }, .{ .string = Value.String.borrowed(stream_type) });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("mode") }, .{ .string = Value.String.borrowed(mode) });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("unread_bytes") }, .{ .int = 0 });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("seekable") }, .{ .bool = true });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("uri") }, .{ .string = Value.String.borrowed(uri) });
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
        .{ .string = Value.String.borrowed(path) },
        .{ .string = Value.String.borrowed(mode) },
        .{ .int = 0 },
        .null,
    };
    const ok = try ctx.callMethod(wrapper, "stream_open", &open_args);
    if (!ok.isTruthy()) return null;
    const fh = try ctx.createObject("FileHandle");
    try fh.set(ctx.allocator, "__wrapper_obj", .{ .object = wrapper });
    try fh.set(ctx.allocator, "__open", .{ .bool = true });
    try fh.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed(mode) });
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
    while (it.next()) |k| try result.append(ctx.allocator, .{ .string = Value.String.borrowed(k.*) });
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
        ctx.vm.tryAutoload(class_name) catch return NativeResult.scalar(.{ .bool = false });
        if (!ctx.vm.classes.contains(class_name)) return NativeResult.scalar(.{ .bool = false });
    }
    const proto_owned = try ctx.createString(protocol);
    const class_owned = try ctx.createString(class_name);
    try ctx.vm.stream_wrappers_user.put(ctx.allocator, proto_owned, class_owned);
    return NativeResult.scalar(.{ .bool = true });
}

fn stream_wrapper_unregister(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const protocol = args[0].string.bytes();
    if (ctx.vm.stream_wrappers_user.fetchRemove(protocol) != null) return NativeResult.scalar(.{ .bool = true });
    if (!isBuiltinWrapper(protocol)) return NativeResult.scalar(.{ .bool = false });
    if (ctx.vm.stream_wrappers_unregistered.contains(protocol)) return NativeResult.scalar(.{ .bool = false });
    const proto_owned = try ctx.createString(protocol);
    try ctx.vm.stream_wrappers_unregistered.put(ctx.allocator, proto_owned, {});
    return NativeResult.scalar(.{ .bool = true });
}

fn stream_wrapper_restore(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const protocol = args[0].string.bytes();
    if (!isBuiltinWrapper(protocol)) return NativeResult.scalar(.{ .bool = false });
    if (!ctx.vm.stream_wrappers_unregistered.contains(protocol)) return NativeResult.scalar(.{ .bool = true });
    _ = ctx.vm.stream_wrappers_unregistered.remove(protocol);
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
    if (args.len < 2 or args[0] != .object or args[1] != .object) return NativeResult.scalar(.{ .bool = false });
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
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const obj = args[0].object;
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
    const file = getFileHandle(obj) orelse return NativeResult.scalar(.{ .bool = false });
    if (offset >= 0) {
        file.seekTo(@intCast(offset)) catch return NativeResult.scalar(.{ .bool = false });
    }
    if (length >= 0) {
        const cap: usize = @intCast(length);
        const buf = ctx.allocator.alloc(u8, cap) catch return NativeResult.scalar(.{ .bool = false });
        const n = file.read(buf) catch {
            ctx.allocator.free(buf);
            return NativeResult.scalar(.{ .bool = false });
        };
        if (n < cap) {
            const result = try Value.String.create(ctx.allocator, buf[0..n]);
            ctx.allocator.free(buf);
            return NativeResult.takeString(result);
        }
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, buf));
    }
    const buf = file.readToEndAlloc(ctx.allocator, 10 * 1024 * 1024) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, buf));
}

fn native_fstat(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const file = getFileHandle(args[0].object) orelse return NativeResult.scalar(.{ .bool = false });
    const stat = file.stat() catch return NativeResult.scalar(.{ .bool = false });
    const result = try ctx.createArray();
    const mode: i64 = @intCast(platform.modeOf(stat));
    const size: i64 = @intCast(stat.size);
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("mode") }, .{ .int = mode });
    try result.set(ctx.allocator, .{ .string = Value.String.borrowed("size") }, .{ .int = size });
    try result.set(ctx.allocator, .{ .int = 2 }, .{ .int = mode });
    try result.set(ctx.allocator, .{ .int = 7 }, .{ .int = size });
    return NativeResult.borrowed(.{ .array = result });
}

fn native_fgetcsv(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const obj = args[0].object;
    const file = getFileHandle(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const delimiter: u8 = if (args.len >= 3 and args[2] == .string and args[2].string.bytes().len > 0) args[2].string.bytes()[0] else ',';
    const enclosure: u8 = if (args.len >= 4 and args[3] == .string and args[3].string.bytes().len > 0) args[3].string.bytes()[0] else '"';

    // read a CSV record, honoring quoted-field embedded newlines
    var line = std.ArrayListUnmanaged(u8){};
    var byte: [1]u8 = undefined;
    var in_quotes = false;
    var got_any = false;
    while (true) {
        const n = file.read(&byte) catch break;
        if (n == 0) {
            try obj.set(ctx.allocator, "__eof", .{ .bool = true });
            break;
        }
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
    if (!got_any) return NativeResult.scalar(.{ .bool = false });

    const line_owned = try line.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, line_owned);

    var raw = line_owned;
    if (raw.len > 0 and raw[raw.len - 1] == '\n') raw = raw[0 .. raw.len - 1];
    if (raw.len > 0 and raw[raw.len - 1] == '\r') raw = raw[0 .. raw.len - 1];

    return parseCsvRecord(ctx, raw, delimiter, enclosure);
}

fn parseCsvRecord(ctx: *NativeContext, raw: []const u8, delimiter: u8, enclosure: u8) !NativeResult {
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
                try result.append(ctx.allocator, .{ .string = Value.String.borrowed(s) });
                at_field_start = true;
            } else {
                try field.append(ctx.allocator, c);
                at_field_start = false;
            }
        }
    }
    const s = try field.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, s);
    try result.append(ctx.allocator, .{ .string = Value.String.borrowed(s) });
    return NativeResult.borrowed(.{ .array = result });
}

fn native_fputcsv(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .object or args[1] != .array) return NativeResult.scalar(.{ .bool = false });
    const file = getFileHandle(args[0].object) orelse return NativeResult.scalar(.{ .bool = false });
    const arr = args[1].array;
    const delimiter: u8 = if (args.len >= 3 and args[2] == .string and args[2].string.bytes().len > 0) args[2].string.bytes()[0] else ',';
    const enclosure: u8 = if (args.len >= 4 and args[3] == .string and args[3].string.bytes().len > 0) args[3].string.bytes()[0] else '"';
    const escape: ?u8 = if (args.len >= 5 and args[4] == .string and args[4].string.bytes().len > 0) args[4].string.bytes()[0] else null;

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

    const written = file.write(buf.items) catch return NativeResult.scalar(.{ .bool = false });
    const owned = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, owned);
    return NativeResult.scalar(.{ .int = @intCast(written) });
}

fn native_touch(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const path = args[0].string.bytes();

    // create the file if it doesn't already exist, then fall through to the
    // timestamp-application path so explicit mtime/atime args take effect
    // regardless of whether the file pre-existed
    const created = std.fs.cwd().createFile(path, .{ .exclusive = true }) catch |err| switch (err) {
        error.PathAlreadyExists => null,
        else => return NativeResult.scalar(.{ .bool = false }),
    };
    if (created) |c| c.close();

    const f = std.fs.cwd().openFile(path, .{ .mode = .write_only }) catch return NativeResult.scalar(.{ .bool = false });
    defer f.close();
    const now: i128 = std.time.nanoTimestamp();
    const mtime: i128 = if (args.len >= 2 and args[1] != .null)
        @as(i128, Value.toInt(args[1])) * 1_000_000_000
    else
        now;
    const atime: i128 = if (args.len >= 3 and args[2] != .null)
        @as(i128, Value.toInt(args[2])) * 1_000_000_000
    else
        mtime;
    f.updateTimes(atime, mtime) catch return NativeResult.scalar(.{ .bool = true });
    return NativeResult.scalar(.{ .bool = true });
}

fn native_chmod(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // windows keeps only a read-only bit: no write permission sets it
    if (platform.is_windows) return windowsChmod(args);
    return posixChmod(ctx, args);
}

fn windowsChmod(args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const mode = Value.toInt(args[1]);
    return NativeResult.scalar(.{ .bool = platform.setReadOnly(args[0].string.bytes(), (mode & 0o222) == 0) });
}

fn posixChmod(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const path = args[0].string.bytes();
    const mode_val = Value.toInt(args[1]);
    if (mode_val < 0) return NativeResult.scalar(.{ .bool = false });
    const mode: std.posix.mode_t = @intCast(mode_val);

    const file = std.fs.cwd().openFile(path, .{ .mode = .read_write }) catch
        return NativeResult.scalar(.{ .bool = false });
    defer file.close();
    file.chmod(mode) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

// chown / chgrp: accept either a numeric uid/gid or a name and pass to the
// posix chown(2) syscall. silently degrade to false on failure (most failures
// are EPERM when not root)
fn native_chown(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const path = args[0].string.bytes();
    var path_z: [std.fs.max_path_bytes:0]u8 = undefined;
    if (path.len >= path_z.len) return NativeResult.scalar(.{ .bool = false });
    @memcpy(path_z[0..path.len], path);
    path_z[path.len] = 0;
    const uid: std.c.uid_t = if (args[1] == .int) @intCast(args[1].int) else blk: {
        if (args[1] != .string) return NativeResult.scalar(.{ .bool = false });
        const name_z = try dupZ(ctx, args[1].string.bytes());
        const pw = std.c.getpwnam(name_z.ptr) orelse return NativeResult.scalar(.{ .bool = false });
        break :blk pw.uid;
    };
    if (chown_extern(@ptrCast(&path_z), uid, std.math.maxInt(std.c.gid_t)) != 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn native_chgrp(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const path = args[0].string.bytes();
    var path_z: [std.fs.max_path_bytes:0]u8 = undefined;
    if (path.len >= path_z.len) return NativeResult.scalar(.{ .bool = false });
    @memcpy(path_z[0..path.len], path);
    path_z[path.len] = 0;
    const gid: std.c.gid_t = if (args[1] == .int) @intCast(args[1].int) else blk: {
        if (args[1] != .string) return NativeResult.scalar(.{ .bool = false });
        const name_z = try dupZ(ctx, args[1].string.bytes());
        const gr = std.c.getgrnam(name_z.ptr) orelse return NativeResult.scalar(.{ .bool = false });
        break :blk gr.gid;
    };
    if (chown_extern(@ptrCast(&path_z), std.math.maxInt(std.c.uid_t), gid) != 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

extern "c" fn chown(path: [*:0]const u8, owner: std.c.uid_t, group: std.c.gid_t) c_int;
fn chown_extern(p: [*:0]const u8, o: std.c.uid_t, g: std.c.gid_t) c_int {
    return chown(p, o, g);
}

fn dupZ(ctx: *NativeContext, s: []const u8) ![:0]u8 {
    const z = try ctx.allocator.alloc(u8, s.len + 1);
    @memcpy(z[0..s.len], s);
    z[s.len] = 0;
    try ctx.strings.append(ctx.allocator, z);
    return z[0..s.len :0];
}

fn native_stat(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const path = args[0].string.bytes();
    var pbuf: [std.fs.max_path_bytes:0]u8 = undefined;
    if (path.len >= pbuf.len) return NativeResult.scalar(.{ .bool = false });
    @memcpy(pbuf[0..path.len], path);
    pbuf[path.len] = 0;
    var st: std.c.Stat = undefined;
    if (std.c.stat(&pbuf, &st) != 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.borrowed(.{ .array = try buildStatArray(ctx, &st) });
}

fn native_chdir(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const path = args[0].string.bytes();
    var dir = std.fs.cwd().openDir(path, .{}) catch return NativeResult.scalar(.{ .bool = false });
    defer dir.close();
    dir.setAsCwd() catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn native_stream_is_local(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const scheme = extractScheme(args[0].string.bytes()) orelse return NativeResult.scalar(.{ .bool = true });
    return NativeResult.scalar(.{ .bool = std.mem.eql(u8, scheme, "file") or std.mem.eql(u8, scheme, "phar") });
}

fn native_stream_resolve_include_path(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const path = args[0].string.bytes();
    std.fs.cwd().access(path, .{}) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.shareString(args[0].string);
}

fn native_stream_isatty(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const obj = args[0].object;
    if (!std.mem.eql(u8, obj.class_name, "FileHandle")) return NativeResult.scalar(.{ .bool = false });
    const fd_val = obj.get("__fd");
    if (fd_val != .int) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = platform.isatty(fd_val.int) });
}

fn native_clearstatcache(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.null);
}

fn native_stream_supports_lock(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // local file streams (FileHandle backed by an fd from open()) support
    // flock; in-memory streams (php://memory, php://temp), HTTP/curl-backed
    // streams, and other non-fd wrappers do not. detect by inspecting the
    // path: anything starting with 'php://', 'http://', 'https://', 'data:',
    // 'ftp://' is a non-fd stream
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const obj = args[0].object;
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

fn native_fileperms(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const stat = platform.statPath(args[0].string.bytes()) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(platform.modeOf(stat)) });
}

extern "c" fn lstat(noalias path: [*:0]const u8, noalias buf: *std.c.Stat) c_int;

fn native_fileowner(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const path = args[0].string.bytes();
    var pbuf: [std.fs.max_path_bytes:0]u8 = undefined;
    if (path.len >= pbuf.len) return NativeResult.scalar(.{ .bool = false });
    @memcpy(pbuf[0..path.len], path);
    pbuf[path.len] = 0;
    var st: std.c.Stat = undefined;
    if (std.c.stat(&pbuf, &st) != 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(st.uid) });
}

fn native_filegroup(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const path = args[0].string.bytes();
    var pbuf: [std.fs.max_path_bytes:0]u8 = undefined;
    if (path.len >= pbuf.len) return NativeResult.scalar(.{ .bool = false });
    @memcpy(pbuf[0..path.len], path);
    pbuf[path.len] = 0;
    var st: std.c.Stat = undefined;
    if (std.c.stat(&pbuf, &st) != 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(st.gid) });
}

fn native_is_link(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const path = args[0].string.bytes();
    var pbuf: [std.fs.max_path_bytes:0]u8 = undefined;
    if (path.len >= pbuf.len) return NativeResult.scalar(.{ .bool = false });
    @memcpy(pbuf[0..path.len], path);
    pbuf[path.len] = 0;
    var st: std.c.Stat = undefined;
    if (lstat(&pbuf, &st) != 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = (st.mode & 0o170000) == 0o120000 });
}

fn native_symlink(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    var t: [std.fs.max_path_bytes:0]u8 = undefined;
    var l: [std.fs.max_path_bytes:0]u8 = undefined;
    const target = args[0].string.bytes();
    const linkpath = args[1].string.bytes();
    if (target.len >= t.len or linkpath.len >= l.len) return NativeResult.scalar(.{ .bool = false });
    @memcpy(t[0..target.len], target);
    t[target.len] = 0;
    @memcpy(l[0..linkpath.len], linkpath);
    l[linkpath.len] = 0;
    return NativeResult.scalar(.{ .bool = std.c.symlink(&t, &l) == 0 });
}

fn native_link(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    var t: [std.fs.max_path_bytes:0]u8 = undefined;
    var l: [std.fs.max_path_bytes:0]u8 = undefined;
    const target = args[0].string.bytes();
    const linkpath = args[1].string.bytes();
    if (target.len >= t.len or linkpath.len >= l.len) return NativeResult.scalar(.{ .bool = false });
    @memcpy(t[0..target.len], target);
    t[target.len] = 0;
    @memcpy(l[0..linkpath.len], linkpath);
    l[linkpath.len] = 0;
    return NativeResult.scalar(.{ .bool = std.c.link(&t, &l) == 0 });
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
        .{ .name = "dev", .val = dev },       .{ .name = "ino", .val = ino },
        .{ .name = "mode", .val = mode },     .{ .name = "nlink", .val = nlink },
        .{ .name = "uid", .val = uid },       .{ .name = "gid", .val = gid },
        .{ .name = "rdev", .val = 0 },        .{ .name = "size", .val = size },
        .{ .name = "atime", .val = atime },   .{ .name = "mtime", .val = mtime },
        .{ .name = "ctime", .val = ctime },   .{ .name = "blksize", .val = blksize },
        .{ .name = "blocks", .val = blocks },
    };
    for (pairs, 0..) |p, i| {
        try arr.set(ctx.allocator, .{ .int = @intCast(i) }, .{ .int = p.val });
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(p.name) }, .{ .int = p.val });
    }
    return arr;
}

fn native_lstat(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const path = args[0].string.bytes();
    var pbuf: [std.fs.max_path_bytes:0]u8 = undefined;
    if (path.len >= pbuf.len) return NativeResult.scalar(.{ .bool = false });
    @memcpy(pbuf[0..path.len], path);
    pbuf[path.len] = 0;
    var st: std.c.Stat = undefined;
    if (lstat(&pbuf, &st) != 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.borrowed(.{ .array = try buildStatArray(ctx, &st) });
}

fn native_readlink(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const target = std.fs.cwd().readLink(args[0].string.bytes(), &buf) catch return NativeResult.scalar(.{ .bool = false });
    return try NativeResult.copyString(ctx.allocator, target);
}

fn native_tmpfile(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const dir = platform.tempDir();
    const path = std.fmt.allocPrint(ctx.vm.allocator, "{s}/zphp_tmpfile_{d}_{d}", .{ dir, std.time.nanoTimestamp(), std.crypto.random.int(u32) }) catch return NativeResult.scalar(.{ .bool = false });
    try ctx.vm.strings.append(ctx.vm.allocator, path);
    var open_args: [2]Value = .{ .{ .string = Value.String.borrowed(path) }, .{ .string = Value.String.borrowed("w+b") } };
    const handle = try native_fopen(ctx, open_args[0..2]);
    return handle;
}

fn native_tempnam(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const dir = if (args.len > 0 and args[0] == .string) args[0].string.bytes() else platform.tempDir();
    const prefix = if (args.len > 1 and args[1] == .string) args[1].string.bytes() else "tmp";
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
            return NativeResult.takeString(try Value.String.adopt(ctx.vm.allocator, candidate));
        } else |_| {
            ctx.vm.allocator.free(candidate);
        }
    }
    return NativeResult.scalar(.{ .bool = false });
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
    if (vm.output.items.len == 0) return;
    const stdout = std.fs.File.stdout();
    _ = stdout.write(vm.output.items) catch {};
    vm.output.clearRetainingCapacity();
}

fn runShellWith(
    allocator: std.mem.Allocator,
    command: []const u8,
    stdin_data: ?[]const u8,
    stdout_b: StdioBehavior,
    stderr_b: StdioBehavior,
) !ShellResult {
    const argv = platform.shellArgv(command);
    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = if (stdin_data != null) .Pipe else .Ignore;
    child.stdout_behavior = if (stdout_b == .capture) .Pipe else .Inherit;
    child.stderr_behavior = if (stderr_b == .capture) .Pipe else .Inherit;
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
    if (stdout_b == .capture or stderr_b == .capture) {
        try child.collectOutput(allocator, &stdout_buf, &stderr_buf, 64 * 1024 * 1024);
    }
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
    const obj = try ctx.createObject("FileHandle");
    try obj.set(ctx.allocator, "__buffer", .{ .string = Value.String.borrowed(data) });
    try obj.set(ctx.allocator, "__pos", .{ .int = 0 });
    try obj.set(ctx.allocator, "__open", .{ .bool = true });
    try obj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed("r") });
    return obj;
}

fn makePopenWriteHandle(ctx: *NativeContext, command: []const u8) !*PhpObject {
    const obj = try ctx.createObject("FileHandle");
    const cmd_copy = try ctx.allocator.dupe(u8, command);
    try ctx.vm.strings.append(ctx.allocator, cmd_copy);
    try obj.set(ctx.allocator, "__popen_cmd", .{ .string = Value.String.borrowed(cmd_copy) });
    try obj.set(ctx.allocator, "__buffer", .{ .string = Value.String.borrowed("") });
    try obj.set(ctx.allocator, "__pos", .{ .int = 0 });
    try obj.set(ctx.allocator, "__open", .{ .bool = true });
    try obj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed("w") });
    return obj;
}

pub fn native_popen(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const cmd = args[0].string.bytes();
    const mode = args[1].string.bytes();
    if (mode.len > 0 and (mode[0] == 'r')) {
        const result = runShellCapture(ctx.allocator, cmd, null) catch return NativeResult.scalar(.{ .bool = false });
        ctx.allocator.free(result.stderr);
        try ctx.vm.strings.append(ctx.allocator, result.stdout);
        const obj = try makeReadBufferHandle(ctx, result.stdout);
        try obj.set(ctx.allocator, "__popen_exit", .{ .int = result.exit });
        return NativeResult.borrowed(.{ .object = obj });
    }
    if (mode.len > 0 and (mode[0] == 'w')) {
        const obj = try makePopenWriteHandle(ctx, cmd);
        return NativeResult.borrowed(.{ .object = obj });
    }
    return NativeResult.scalar(.{ .bool = false });
}

pub fn native_pclose(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.{ .int = -1 });
    const obj = args[0].object;
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
    const flags = std.posix.fcntl(fd, 1, 0) catch return;
    _ = std.posix.fcntl(fd, 2, flags | 1) catch {};
}

fn procChildDup(src: std.posix.fd_t, target: std.posix.fd_t, err_fd: std.posix.fd_t) void {
    std.posix.dup2(src, target) catch |e| procChildFail(err_fd, e);
}

fn procChildFail(err_fd: std.posix.fd_t, err: anyerror) noreturn {
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, @intFromError(err), .little);
    _ = std.posix.write(err_fd, &buf) catch {};
    std.c._exit(1);
}

fn closePrepared(descs: []PreparedDesc) void {
    for (descs) |*d| {
        if (d.parent_fd != -1) std.posix.close(d.parent_fd);
        if (d.child_fd != -1) std.posix.close(d.child_fd);
        if (d.aux_fd != -1) std.posix.close(d.aux_fd);
        d.parent_fd = -1;
        d.child_fd = -1;
        d.aux_fd = -1;
    }
}

fn forkExecDesc(allocator: std.mem.Allocator, cmd: []const u8, specs: []const ProcDesc, cwd: ?[]const u8) !ProcSpawn {
    const cloexec: std.posix.O = .{ .CLOEXEC = true };
    const prepared = try allocator.alloc(PreparedDesc, specs.len);
    defer allocator.free(prepared);
    for (specs, 0..) |spec, i| prepared[i] = .{ .role = spec.role, .action = spec.action };
    errdefer closePrepared(prepared);

    for (prepared) |*d| switch (d.action) {
        .pipe_r, .pipe_w => {
            const pair = try std.posix.pipe2(cloexec);
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

    const xrep = try std.posix.pipe2(cloexec);
    errdefer {
        std.posix.close(xrep[0]);
        std.posix.close(xrep[1]);
    }
    const cmdz = try allocator.dupeZ(u8, cmd);
    defer allocator.free(cmdz);
    var argv = [_:null]?[*:0]const u8{ "/bin/sh", "-c", cmdz.ptr };
    const envp: [*:null]const ?[*:0]const u8 = @ptrCast(std.c.environ);

    const pid = try std.posix.fork();
    if (pid == 0) {
        if (cwd) |dir| {
            const dirz = allocator.dupeZ(u8, dir) catch procChildFail(xrep[1], error.OutOfMemory);
            if (std.c.chdir(dirz.ptr) != 0) procChildFail(xrep[1], error.ProcSpawnFailed);
        }
        for (prepared) |d| if (d.parent_fd != -1) std.posix.close(d.parent_fd);
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
            if (!is_target) std.posix.close(d.child_fd);
        }
        const e = std.posix.execveZ("/bin/sh", &argv, envp);
        procChildFail(xrep[1], e);
    }

    std.posix.close(xrep[1]);
    for (prepared) |*d| {
        if (d.child_fd != -1) std.posix.close(d.child_fd);
        d.child_fd = -1;
    }
    var buf: [8]u8 = undefined;
    const got = std.posix.read(xrep[0], &buf) catch 0;
    std.posix.close(xrep[0]);
    if (got > 0) {
        _ = std.posix.waitpid(pid, 0);
        return error.ProcSpawnFailed;
    }

    var pipes: std.ArrayListUnmanaged(@import("../runtime/vm.zig").ProcPipe) = .{};
    errdefer pipes.deinit(allocator);
    for (prepared) |*d| if (d.parent_fd != -1) {
        try pipes.append(allocator, .{ .role = d.role, .fd = d.parent_fd });
        d.parent_fd = -1;
    };
    return .{ .pid = pid, .pipe_fds = pipes };
}

fn native_proc_open(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 3 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const cmd = args[0].string.bytes();

    const proc = try ctx.createObject("ProcessResource");
    const cmd_copy = try ctx.vm.allocator.dupe(u8, cmd);
    try ctx.vm.strings.append(ctx.allocator, cmd_copy);
    try proc.set(ctx.allocator, "__cmd", .{ .string = Value.String.borrowed(cmd_copy) });
    try proc.set(ctx.allocator, "__exit", .{ .int = 0 });
    try proc.set(ctx.allocator, "__running", .{ .bool = true });

    var descs: std.ArrayListUnmanaged(ProcDesc) = .{};
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
            } else if (v == .object) {
                const fdv = v.object.get("__fd");
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
    if (inherits_out and ctx.vm.output.items.len > 0) {
        const stdout = std.fs.File.stdout();
        _ = stdout.write(ctx.vm.output.items) catch {};
        ctx.vm.output.clearRetainingCapacity();
    }

    // spawn the child live now (php spawns at proc_open, not at first read) via
    // fork/exec. the pid + parent-side pipe fds live in vm.proc_children keyed by
    // proc, so proc_close waitpid's the pid and reset/deinit reaps it. each pipe fd
    // becomes __fd on a FileHandle so fread/fwrite/stream_select use real live fds;
    // each is closed EXACTLY once: by fclose (clears pipe_fds[role]) or proc_close/reap
    const child_cwd: ?[]const u8 = if (args.len >= 4 and args[3] == .string) args[3].string.bytes() else null;
    const spawned = forkExecDesc(ctx.vm.allocator, cmd_copy, descs.items, child_cwd) catch {
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
    const pipes = try ctx.allocator.create(PhpArray);
    pipes.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, pipes);
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
            const fobj = try ctx.allocator.create(PhpObject);
            fobj.* = .{ .class_name = "FileHandle" };
            try ctx.vm.objects.append(ctx.allocator, fobj);
            try fobj.set(ctx.allocator, "__open", .{ .bool = true });
            try fobj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed(m) });
            try fobj.set(ctx.allocator, "__fd", .{ .int = @intCast(parent_fd) });
            try fobj.set(ctx.allocator, "__proc_ref", .{ .object = proc });
            try fobj.set(ctx.allocator, "__proc_role", .{ .int = desc.role });
            try pipes.set(ctx.allocator, .{ .int = desc.role }, .{ .object = fobj });
        }
    }

    ctx.setCallerVar(2, args.len, .{ .array = pipes });
    return NativeResult.borrowed(.{ .object = proc });
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
        const sig: i64 = @intCast(PosixW.TERMSIG(status));
        proc.set(ctx.allocator, "__exit", .{ .int = sig + 128 }) catch {};
        proc.set(ctx.allocator, "__termsig", .{ .int = sig }) catch {};
        proc.set(ctx.allocator, "__signaled", .{ .bool = true }) catch {};
    } else {
        proc.set(ctx.allocator, "__exit", .{ .int = -1 }) catch {};
    }
}

fn native_proc_close(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.{ .int = -1 });
    const obj = args[0].object;
    const pc = ctx.vm.lookupProcChild(obj) orelse {
        // already finalized (or spawn failed) - return the cached exit
        const cached = obj.get("__exit");
        return NativeResult.scalar(.{ .int = if (cached == .int) cached.int else 0 });
    };
    // close stdin first so the child sees EOF and can finish
    for (pc.pipe_fds.items) |*pipe| if (pipe.role == 0 and pipe.fd != -1) {
        std.posix.close(pipe.fd);
        pipe.fd = -1;
    };
    if (!pc.reaped) {
        // a prior proc_get_status may have already reaped via WNOHANG; if not, do a
        // blocking wait now (exactly one waitpid per pid - ECHILD is unreachable)
        const res = std.posix.waitpid(pc.pid, 0);
        cacheProcTerm(ctx, obj, res.status);
    }
    // close any parent-side fds the script didn't fclose
    for (pc.pipe_fds.items) |*pipe| if (pipe.fd != -1) {
        std.posix.close(pipe.fd);
        pipe.fd = -1;
    };
    pc.pipe_fds.deinit(ctx.allocator);
    ctx.vm.removeProcChild(obj);
    const exit = obj.get("__exit");
    return NativeResult.scalar(.{ .int = if (exit == .int) exit.int else 0 });
}

fn native_proc_get_status(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const obj = args[0].object;
    // non-blocking liveness poll. if the child has exited, reap the zombie (mark
    // .reaped so proc_close/reap won't wait again -> ECHILD) and cache the exit,
    // but leave the pipe fds + *Child intact: the script may still read buffered
    // output, and proc_close finalizes the fds
    var running = false;
    if (ctx.vm.lookupProcChild(obj)) |pc| {
        if (!pc.reaped) {
            const res = std.posix.waitpid(pc.pid, PosixW.NOHANG);
            if (res.pid == 0) {
                running = true;
            } else {
                pc.reaped = true;
                cacheProcTerm(ctx, obj, res.status);
            }
        }
    }
    const result = try ctx.allocator.create(PhpArray);
    result.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, result);
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
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const sig: u8 = if (args.len >= 2 and args[1] == .int) @intCast(args[1].int) else std.posix.SIG.TERM;
    if (ctx.vm.lookupProcChild(args[0].object)) |pc| {
        std.posix.kill(pc.pid, sig) catch return NativeResult.scalar(.{ .bool = false });
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn native_stream_set_blocking(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const fd = args[0].object.get("__fd");
    if (fd != .int) return NativeResult.scalar(.{ .bool = false });
    const descriptor = platform.socketFromInt(fd.int) orelse return NativeResult.scalar(.{ .bool = false });
    platform.setNonBlocking(descriptor, !args[1].isTruthy()) catch return NativeResult.scalar(.{ .bool = false });
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
    const file = std.fs.cwd().openFile(path, .{}) catch {
        return try NativeResult.copyString(ctx.allocator, mimeFromExt(path));
    };
    defer file.close();
    var buf: [16]u8 = undefined;
    const n = file.read(&buf) catch return try NativeResult.copyString(ctx.allocator, mimeFromExt(path));
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

fn native_linkinfo(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .int = -1 });
    const stat = platform.statPath(args[0].string.bytes()) catch return NativeResult.scalar(.{ .int = -1 });
    return NativeResult.scalar(.{ .int = @intCast(stat.inode) });
}

fn native_finfo_open(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = try ctx.allocator.create(PhpObject);
    obj.* = .{ .class_name = "finfo" };
    try ctx.vm.objects.append(ctx.allocator, obj);
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
