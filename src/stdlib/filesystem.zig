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

pub const entries = .{
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
    .{ "scandir", native_scandir },
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
    .{ "fstat", native_fstat },
    .{ "stream_get_contents", stream_get_contents },
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
    .{ "umask", native_umask },
    .{ "fileperms", native_fileperms },
    .{ "is_link", native_is_link },
    .{ "readlink", native_readlink },
};

// file handle management - store handles in PhpObjects with class "FileHandle"

pub fn register(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "FileHandle" };
    try def.methods.put(a, "__toString", .{ .name = "__toString", .arity = 0 });
    try vm.classes.put(a, "FileHandle", def);
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
    if (path.len > 7 and (std.mem.startsWith(u8, path, "http://") or std.mem.startsWith(u8, path, "https://"))) {
        return fetchUrl(ctx, path);
    }
    const content = std.fs.cwd().readFileAlloc(ctx.allocator, path, 1024 * 1024 * 64) catch return Value{ .bool = false };
    try ctx.strings.append(ctx.allocator, content);
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

fn native_file_exists(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    std.fs.cwd().access(args[0].string, .{}) catch return Value{ .bool = false };
    return .{ .bool = true };
}

fn native_is_file(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const stat = std.fs.cwd().statFile(args[0].string) catch return Value{ .bool = false };
    return .{ .bool = stat.kind == .file };
}

fn native_is_dir(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    var dir = std.fs.cwd().openDir(args[0].string, .{}) catch return Value{ .bool = false };
    dir.close();
    return .{ .bool = true };
}

fn native_basename(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .string = "" };
    const path = args[0].string;
    const suffix = if (args.len >= 2 and args[1] == .string) args[1].string else "";
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
    const path = args[0].string;
    if (std.mem.lastIndexOf(u8, path, "/")) |pos| {
        if (pos == 0) return .{ .string = "/" };
        return .{ .string = try ctx.createString(path[0..pos]) };
    }
    return .{ .string = "." };
}

fn native_pathinfo(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .null;
    const path = args[0].string;
    var arr = try ctx.createArray();

    const dir = if (std.mem.lastIndexOf(u8, path, "/")) |pos| blk: {
        break :blk if (pos == 0) "/" else try ctx.createString(path[0..pos]);
    } else ".";
    try arr.set(ctx.allocator, .{ .string = "dirname" }, .{ .string = dir });

    const base = if (std.mem.lastIndexOf(u8, path, "/")) |pos| try ctx.createString(path[pos + 1 ..]) else path;
    try arr.set(ctx.allocator, .{ .string = "basename" }, .{ .string = base });

    if (std.mem.lastIndexOf(u8, base, ".")) |dot| {
        try arr.set(ctx.allocator, .{ .string = "extension" }, .{ .string = try ctx.createString(base[dot + 1 ..]) });
        try arr.set(ctx.allocator, .{ .string = "filename" }, .{ .string = try ctx.createString(base[0..dot]) });
    } else {
        try arr.set(ctx.allocator, .{ .string = "extension" }, .{ .string = "" });
        try arr.set(ctx.allocator, .{ .string = "filename" }, .{ .string = base });
    }
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

fn native_unlink(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    std.fs.cwd().deleteFile(args[0].string) catch return Value{ .bool = false };
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
    var dir = std.fs.cwd().openDir(args[0].string, .{ .iterate = true }) catch return Value{ .bool = false };
    defer dir.close();

    var result = try ctx.createArray();
    try result.append(ctx.allocator, .{ .string = "." });
    try result.append(ctx.allocator, .{ .string = ".." });

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        const name = try ctx.createString(entry.name);
        try result.append(ctx.allocator, .{ .string = name });
    }
    return .{ .array = result };
}

fn native_glob(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const pattern = args[0].string;

    // extract directory and file pattern from glob
    const dir_path = if (std.mem.lastIndexOf(u8, pattern, "/")) |pos| pattern[0..pos] else ".";
    const file_pattern = if (std.mem.lastIndexOf(u8, pattern, "/")) |pos| pattern[pos + 1 ..] else pattern;

    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return Value{ .array = try ctx.createArray() };
    defer dir.close();

    var result = try ctx.createArray();
    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (globMatch(file_pattern, entry.name)) {
            var path_buf: [4096]u8 = undefined;
            const full = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ dir_path, entry.name }) catch continue;
            try result.append(ctx.allocator, .{ .string = try ctx.createString(full) });
        }
    }
    return .{ .array = result };
}

fn globMatch(pattern: []const u8, name: []const u8) bool {
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
            if (pattern[pi] == '?' or pattern[pi] == name[ni]) {
                pi += 1;
                ni += 1;
                continue;
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
    try ctx.vm.objects.append(ctx.allocator, obj);
    return .{ .object = obj };
}

fn openWithMode(path: []const u8, mode: []const u8) !std.fs.File {
    if (mode.len == 0) return error.RuntimeError;
    return switch (mode[0]) {
        'r' => std.fs.cwd().openFile(path, .{ .mode = if (mode.len > 1 and mode[1] == '+') .read_write else .read_only }),
        'w' => blk: {
            const file = std.fs.cwd().createFile(path, .{ .truncate = true }) catch |err| break :blk err;
            break :blk file;
        },
        'a' => blk: {
            const file = std.fs.cwd().openFile(path, .{ .mode = .write_only }) catch
                std.fs.cwd().createFile(path, .{}) catch |err| break :blk err;
            file.seekFromEnd(0) catch {};
            break :blk file;
        },
        'x' => std.fs.cwd().createFile(path, .{ .exclusive = true }),
        else => error.RuntimeError,
    };
}

fn native_fclose(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .{ .bool = false };
    const obj = args[0].object;
    if (!std.mem.eql(u8, obj.class_name, "FileHandle")) return .{ .bool = false };
    const open = obj.get("__open");
    if (open != .bool or !open.bool) return .{ .bool = false };
    if (getFileHandle(obj)) |file| {
        // never close stdin/stdout/stderr - they're shared with the host process
        if (file.handle > 2) file.close();
    }
    obj.properties.put(std.heap.page_allocator, "__open", .{ .bool = false }) catch {};
    return .{ .bool = true };
}

fn native_fread(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .object or args[1] != .int) return .{ .bool = false };
    const obj = args[0].object;
    const length: usize = @intCast(@max(args[1].int, 0));
    if (length == 0) return .{ .string = "" };
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
    const data = args[1].string;
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

fn native_feof(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .{ .bool = true };
    const obj = args[0].object;
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

fn native_fseek(_: *NativeContext, args: []const Value) RuntimeError!Value {
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

fn native_ftell(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .{ .bool = false };
    const obj = args[0].object;
    if (getBufferBacking(obj) != null) {
        return .{ .int = @intCast(getBufferPos(obj)) };
    }
    const file = getFileHandle(obj) orelse return Value{ .bool = false };
    const pos = file.getPos() catch return Value{ .bool = false };
    return .{ .int = @intCast(pos) };
}

fn native_rewind(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .{ .bool = false };
    const obj = args[0].object;
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
    const result = try ctx.createArray();
    try result.set(ctx.allocator, .{ .string = "timed_out" }, .{ .bool = false });
    try result.set(ctx.allocator, .{ .string = "blocked" }, .{ .bool = true });
    try result.set(ctx.allocator, .{ .string = "eof" }, .{ .bool = false });
    try result.set(ctx.allocator, .{ .string = "stream_type" }, .{ .string = "STDIO" });
    try result.set(ctx.allocator, .{ .string = "mode" }, .{ .string = mode });
    try result.set(ctx.allocator, .{ .string = "unread_bytes" }, .{ .int = 0 });
    try result.set(ctx.allocator, .{ .string = "seekable" }, .{ .bool = true });
    try result.set(ctx.allocator, .{ .string = "uri" }, .{ .string = "" });
    return .{ .array = result };
}

fn stream_get_wrappers(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const result = try ctx.createArray();
    const wrappers = [_][]const u8{ "https", "php", "file", "data", "http" };
    for (wrappers) |w| try result.append(ctx.allocator, .{ .string = w });
    return .{ .array = result };
}

fn stream_get_contents(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .object) return .{ .bool = false };
    const file = getFileHandle(args[0].object) orelse return Value{ .bool = false };
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
    // args: handle, [length], [delimiter], [enclosure], [escape]
    const delimiter: u8 = if (args.len >= 3 and args[2] == .string and args[2].string.len > 0) args[2].string[0] else ',';
    const enclosure: u8 = if (args.len >= 4 and args[3] == .string and args[3].string.len > 0) args[3].string[0] else '"';

    // read a line
    var line = std.ArrayListUnmanaged(u8){};
    var byte: [1]u8 = undefined;
    while (line.items.len < 65536) {
        const n = file.read(&byte) catch break;
        if (n == 0) break;
        try line.append(ctx.allocator, byte[0]);
        if (byte[0] == '\n') break;
    }
    if (line.items.len == 0) return .{ .bool = false };

    // register the line buffer for cleanup
    const line_owned = try line.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, line_owned);

    // trim trailing newline
    var raw = line_owned;
    if (raw.len > 0 and raw[raw.len - 1] == '\n') raw = raw[0 .. raw.len - 1];
    if (raw.len > 0 and raw[raw.len - 1] == '\r') raw = raw[0 .. raw.len - 1];

    // parse CSV fields
    var result = try ctx.createArray();
    var field = std.ArrayListUnmanaged(u8){};
    var in_quotes = false;
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
            if (c == enclosure) {
                in_quotes = true;
            } else if (c == delimiter) {
                const s = try field.toOwnedSlice(ctx.allocator);
                try ctx.strings.append(ctx.allocator, s);
                try result.append(ctx.allocator, .{ .string = s });
            } else {
                try field.append(ctx.allocator, c);
            }
        }
    }
    // last field
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

    var buf = std.ArrayListUnmanaged(u8){};
    for (arr.entries.items, 0..) |entry, i| {
        if (i > 0) try buf.append(ctx.allocator, delimiter);
        const val = switch (entry.value) {
            .string => |sv| sv,
            .int => |iv| blk: {
                const tmp = try std.fmt.allocPrint(ctx.allocator, "{d}", .{iv});
                try ctx.strings.append(ctx.allocator, tmp);
                break :blk tmp;
            },
            .float => |fv| blk: {
                const tmp = try std.fmt.allocPrint(ctx.allocator, "{d}", .{fv});
                try ctx.strings.append(ctx.allocator, tmp);
                break :blk tmp;
            },
            else => "",
        };

        var needs_quote = false;
        for (val) |c| {
            if (c == delimiter or c == enclosure or c == '\n' or c == '\r' or c == ' ' or c == '\t') {
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

    const file = std.fs.cwd().openFile(path, .{}) catch
        return Value{ .bool = false };
    defer file.close();
    const stat = file.stat() catch return Value{ .bool = false };

    var result = try ctx.createArray();
    const size: i64 = @intCast(stat.size);
    const atime: i64 = @intCast(@divTrunc(stat.atime, 1_000_000_000));
    const mtime: i64 = @intCast(@divTrunc(stat.mtime, 1_000_000_000));
    const ctime: i64 = @intCast(@divTrunc(stat.ctime, 1_000_000_000));

    // numeric indices (PHP stat format)
    try result.append(ctx.allocator, .{ .int = 0 }); // 0: dev
    try result.append(ctx.allocator, .{ .int = 0 }); // 1: ino
    try result.append(ctx.allocator, .{ .int = 0 }); // 2: mode
    try result.append(ctx.allocator, .{ .int = 1 }); // 3: nlink
    try result.append(ctx.allocator, .{ .int = 0 }); // 4: uid
    try result.append(ctx.allocator, .{ .int = 0 }); // 5: gid
    try result.append(ctx.allocator, .{ .int = 0 }); // 6: rdev
    try result.append(ctx.allocator, .{ .int = size }); // 7: size
    try result.append(ctx.allocator, .{ .int = atime }); // 8: atime
    try result.append(ctx.allocator, .{ .int = mtime }); // 9: mtime
    try result.append(ctx.allocator, .{ .int = ctime }); // 10: ctime
    try result.append(ctx.allocator, .{ .int = -1 }); // 11: blksize
    try result.append(ctx.allocator, .{ .int = -1 }); // 12: blocks

    // named keys
    try result.set(ctx.allocator, .{ .string = "dev" }, .{ .int = 0 });
    try result.set(ctx.allocator, .{ .string = "ino" }, .{ .int = 0 });
    try result.set(ctx.allocator, .{ .string = "mode" }, .{ .int = 0 });
    try result.set(ctx.allocator, .{ .string = "nlink" }, .{ .int = 1 });
    try result.set(ctx.allocator, .{ .string = "uid" }, .{ .int = 0 });
    try result.set(ctx.allocator, .{ .string = "gid" }, .{ .int = 0 });
    try result.set(ctx.allocator, .{ .string = "rdev" }, .{ .int = 0 });
    try result.set(ctx.allocator, .{ .string = "size" }, .{ .int = size });
    try result.set(ctx.allocator, .{ .string = "atime" }, .{ .int = atime });
    try result.set(ctx.allocator, .{ .string = "mtime" }, .{ .int = mtime });
    try result.set(ctx.allocator, .{ .string = "ctime" }, .{ .int = ctime });
    try result.set(ctx.allocator, .{ .string = "blksize" }, .{ .int = -1 });
    try result.set(ctx.allocator, .{ .string = "blocks" }, .{ .int = -1 });

    return .{ .array = result };
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

fn native_is_link(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const stat = std.fs.cwd().statFile(args[0].string) catch return Value{ .bool = false };
    return .{ .bool = stat.kind == .sym_link };
}

fn native_readlink(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const target = std.fs.cwd().readLink(args[0].string, &buf) catch return Value{ .bool = false };
    const result = ctx.vm.allocator.dupe(u8, target) catch return .{ .bool = false };
    try ctx.vm.strings.append(ctx.vm.allocator, result);
    return .{ .string = result };
}

fn native_tempnam(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const dir = if (args.len > 0 and args[0] == .string) args[0].string else "/tmp";
    const prefix = if (args.len > 1 and args[1] == .string) args[1].string else "tmp";
    const result = std.fmt.allocPrint(ctx.vm.allocator, "{s}/{s}{d}", .{ dir, prefix, std.time.nanoTimestamp() }) catch return .{ .bool = false };
    try ctx.vm.strings.append(ctx.vm.allocator, result);
    return .{ .string = result };
}

