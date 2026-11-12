const std = @import("std");
const sys = @import("../sys.zig");
const paths = @import("../paths.zig");
const platform = @import("../platform.zig");
const VM = @import("vm.zig").VM;
const bundle = @import("../bundle.zig");

pub const default_include_path = if (platform.is_windows) ".;C:\\php\\pear" else ".:/usr/local/lib/php";
const list_separator: u8 = if (platform.is_windows) ';' else ':';

// the entries of an include_path as php_resolve_path walks them: a stream
// wrapper's url ("test://x") keeps the colon after its scheme
const PathEntries = struct {
    rest: ?[]const u8,

    fn next(self: *PathEntries) ?[]const u8 {
        const all = self.rest orelse return null;
        var p: usize = 0;
        while (p < all.len and (std.ascii.isAlphanumeric(all[p]) or all[p] == '+' or all[p] == '-' or all[p] == '.')) p += 1;
        var from: usize = 0;
        if (p > 1 and p + 2 < all.len and all[p] == ':' and all[p + 1] == '/' and all[p + 2] == '/') {
            // .:// or ..:// is not a stream wrapper
            if (!(p == 2 and all[0] == '.' and all[1] == '.')) from = p + 3;
        }
        if (std.mem.indexOfScalarPos(u8, all, from, list_separator)) |end| {
            self.rest = all[end + 1 ..];
            return all[0..end];
        }
        self.rest = null;
        return all;
    }
};

pub fn includePath(vm: *const VM) []const u8 {
    return vm.ini_settings.get("include_path") orelse default_include_path;
}

// zend_resolve_path: a path that names its own location (absolute, or led by
// ./ or ../) resolves against the working directory alone; any other tries
// each include_path entry, then the directory of the running file. the result
// is the file's canonical path, interned for the life of the VM, so every
// spelling of one file is one entry for require_once and get_included_files
pub fn resolve(vm: *VM, path: []const u8) error{OutOfMemory}!?[]const u8 {
    if (path.len == 0 or std.mem.indexOfScalar(u8, path, 0) != null) return null;
    if (hasScheme(path)) return try intern(vm, path);
    if (namesOwnLocation(path)) return canonical(vm, path);
    var entries = PathEntries{ .rest = includePath(vm) };
    while (entries.next()) |entry| {
        if (entry.len == 0) continue;
        if (hasScheme(entry)) {
            // a stream wrapper's entry: the wrapper's url_stat says whether
            // the file is there
            const trypath = try std.fmt.allocPrint(vm.allocator, "{s}/{s}", .{ entry, path });
            defer vm.allocator.free(trypath);
            if (@import("../stdlib/filesystem.zig").wrapperUrlExists(vm, trypath)) return try intern(vm, trypath);
            continue;
        }
        if (try joined(vm, entry, path)) |found| return found;
    }
    const running = std.fs.path.dirname(vm.frameFile(vm.frame_count -| 1)) orelse return null;
    return joined(vm, running, path);
}

// the canonical path of an existing regular file: its directory through the
// per-VM realpath cache plus one lstat, or a full realpath when the file is
// itself a symlink
pub fn canonical(vm: *VM, path: []const u8) error{OutOfMemory}!?[]const u8 {
    if (try existing(vm, path)) |found| return found;
    // php opens the candidate with its dots folded by name when the os cannot
    // walk it, so a missing directory before a `..` does not hide the file
    if (!paths.hasDotSegment(path)) return null;
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    return existing(vm, paths.expand(&buf, path) orelse return null);
}

fn existing(vm: *VM, path: []const u8) error{OutOfMemory}!?[]const u8 {
    var packed_buf: [std.fs.max_path_bytes]u8 = undefined;
    if (bundle.filePath(&packed_buf, path)) |packed_path| return try intern(vm, packed_path);
    const base = std.fs.path.basename(path);
    if (base.len > 0 and !std.mem.eql(u8, base, ".") and !std.mem.eql(u8, base, "..")) {
        const real_dir = realDir(vm, std.fs.path.dirname(path) orelse ".") orelse return null;
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const abs = join(&buf, real_dir, base) orelse return null;
        switch (entryKind(abs)) {
            .file => return try intern(vm, abs),
            .symlink => {},
            .other => return null,
        }
    }
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = platform.realpath(path, &buf) catch return null;
    if (entryKind(real) != .file) return null;
    return try intern(vm, real);
}

fn joined(vm: *VM, dir: []const u8, path: []const u8) error{OutOfMemory}!?[]const u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    return canonical(vm, join(&buf, dir, path) orelse return null);
}

fn join(buf: []u8, dir: []const u8, name: []const u8) ?[]const u8 {
    const sep: []const u8 = if (dir.len > 0 and std.fs.path.isSep(dir[dir.len - 1])) "" else std.fs.path.sep_str;
    return std.fmt.bufPrint(buf, "{s}{s}{s}", .{ dir, sep, name }) catch null;
}

pub fn hasScheme(path: []const u8) bool {
    const end = std.mem.indexOf(u8, path, "://") orelse return false;
    // a drive letter is not a scheme
    if (end < 2) return false;
    for (path[0..end]) |c| {
        if (!(std.ascii.isAlphanumeric(c) or c == '+' or c == '-' or c == '.')) return false;
    }
    return true;
}

fn namesOwnLocation(path: []const u8) bool {
    return std.fs.path.isAbsolute(path) or ledBy(path, ".") or ledBy(path, "..");
}

fn ledBy(path: []const u8, dots: []const u8) bool {
    return path.len > dots.len and std.mem.startsWith(u8, path, dots) and std.fs.path.isSep(path[dots.len]);
}

const EntryKind = enum { file, symlink, other };

fn entryKind(path: []const u8) EntryKind {
    if (platform.is_windows) {
        const st = std.Io.Dir.cwd().statFile(platform.io, path, .{}) catch return .other;
        return if (st.kind == .file) .file else .other;
    }
    return switch (sys.lstatKind(path) catch return .other) {
        .file => .file,
        .sym_link => .symlink,
        else => .other,
    };
}

// directories are canonicalized once per VM; chdir clears the cache because
// relative keys name a different directory afterwards
pub fn realDir(vm: *VM, dir: []const u8) ?[]const u8 {
    if (vm.realdir_cache.get(dir)) |real| return real;
    const real = platform.realpathAlloc(vm.allocator, dir) catch return null;
    const key = vm.allocator.dupe(u8, dir) catch {
        vm.allocator.free(real);
        return null;
    };
    vm.realdir_cache.put(vm.allocator, key, real) catch {
        vm.allocator.free(key);
        vm.allocator.free(real);
        return null;
    };
    return real;
}

pub fn intern(vm: *VM, path: []const u8) error{OutOfMemory}![]const u8 {
    const interned = &vm.ic.?.include_paths;
    const gop = try interned.getOrPut(vm.allocator, path);
    if (!gop.found_existing) {
        gop.key_ptr.* = vm.allocator.dupe(u8, path) catch |err| {
            interned.removeByPtr(gop.key_ptr);
            return err;
        };
    }
    return gop.key_ptr.*;
}

test "schemes and self-locating paths" {
    try std.testing.expect(hasScheme("phar://a.phar/x.php"));
    try std.testing.expect(!hasScheme("C://x"));
    try std.testing.expect(!hasScheme("dir/x.php"));
    try std.testing.expect(namesOwnLocation("./x.php"));
    try std.testing.expect(namesOwnLocation("../x.php"));
    try std.testing.expect(!namesOwnLocation(".hidden.php"));
    try std.testing.expect(!namesOwnLocation("x.php"));
}
