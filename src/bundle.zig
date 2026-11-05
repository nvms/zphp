const std = @import("std");
const sync = @import("sync.zig");
const platform = @import("platform.zig");
const Allocator = std.mem.Allocator;
const paths = @import("paths.zig");
const absolute = paths.absolute;
const normalize = paths.normalize;

// an application's file tree packed into a standalone executable. every file
// under the build root is kept (a php file also as bytecode), and at run time
// the tree is mounted under the directory the executable lives in, the way a
// union mount stacks a writable layer on a read-only one: a path the disk
// holds is the disk's, a packed file is copied up to the disk before anything
// edits it, and a packed path the program removes stays hidden until exit

const pack_magic = "ZPHPBNDL";
const pack_version: u32 = 1;
const trailer_magic = "ZPHPBDL\x00";
const trailer_size = trailer_magic.len + 16;

pub const Kind = enum(u8) { file = 0, php = 1 };

pub const Entry = struct {
    kind: Kind,
    mtime: i64,
    source: []const u8,
    // empty when a php file did not compile at build time; it is compiled from
    // source when included, which reports the error as php would
    bytecode: []const u8 = "",
};

pub const Bundle = struct {
    allocator: Allocator,
    blob: []u8,
    // where the tree was packed from; compiled paths start with it
    build_root: []const u8,
    // the entry script, relative to the root
    entry: []const u8,
    // where the tree is mounted at run time, in the platform's own form
    mount: []const u8,
    // the mount normalized for matching paths against it
    mount_key: []const u8,
    files: std.StringHashMapUnmanaged(Entry) = .{},
    // every directory (relative, "" is the root) and the names directly in it
    dirs: std.StringHashMapUnmanaged(std.ArrayListUnmanaged([]const u8)) = .{},
    // relative paths built for directories, owned here
    dir_names: std.ArrayListUnmanaged([]u8) = .empty,
    // packed paths the program removed, owned here; worker threads share the
    // bundle, so the set is locked and the count lets lookups skip it
    hidden: std.StringHashMapUnmanaged(void) = .{},
    hidden_count: std.atomic.Value(usize) = .init(0),
    hidden_lock: sync.Mutex = .{},

    pub fn deinit(self: *Bundle) void {
        var keys = self.hidden.keyIterator();
        while (keys.next()) |key| self.allocator.free(key.*);
        self.hidden.deinit(self.allocator);
        var lists = self.dirs.valueIterator();
        while (lists.next()) |list| list.deinit(self.allocator);
        self.dirs.deinit(self.allocator);
        for (self.dir_names.items) |name| self.allocator.free(name);
        self.dir_names.deinit(self.allocator);
        self.files.deinit(self.allocator);
        self.allocator.free(self.mount);
        self.allocator.free(self.mount_key);
        self.allocator.free(self.blob);
        self.allocator.destroy(self);
    }

    // the path relative to the mount, '/'-separated with `.` and `..`
    // folded, or null when the path is outside the mount
    pub fn relative(self: *const Bundle, buf: []u8, path: []const u8) ?[]const u8 {
        const normal = normalize(buf, path) orelse return null;
        const mount = self.mount_key;
        if (normal.len == mount.len and pathsEqual(normal, mount)) return normal[0..0];
        if (normal.len <= mount.len or !pathsEqual(normal[0..mount.len], mount)) return null;
        if (mount.len > 0 and mount[mount.len - 1] == '/') return normal[mount.len..];
        if (normal[mount.len] != '/') return null;
        return normal[mount.len + 1 ..];
    }

    // the absolute path a packed relative path has at run time, with the
    // platform's separators
    pub fn mounted(self: *const Bundle, buf: []u8, rel: []const u8) ?[]const u8 {
        if (rel.len == 0) return std.fmt.bufPrint(buf, "{s}", .{self.mount}) catch null;
        const sep: []const u8 = if (self.mount.len > 0 and std.fs.path.isSep(self.mount[self.mount.len - 1])) "" else std.fs.path.sep_str;
        const out = std.fmt.bufPrint(buf, "{s}{s}{s}", .{ self.mount, sep, rel }) catch return null;
        if (std.fs.path.sep != '/') std.mem.replaceScalar(u8, out[self.mount.len..], '/', std.fs.path.sep);
        return out;
    }

    // a removed path, or one inside a removed directory
    fn isHidden(self: *Bundle, rel: []const u8) bool {
        if (self.hidden_count.load(.acquire) == 0) return false;
        self.hidden_lock.lock();
        defer self.hidden_lock.unlock();
        var prefix = rel;
        while (true) {
            if (self.hidden.contains(prefix)) return true;
            const cut = std.mem.lastIndexOfScalar(u8, prefix, '/') orelse return false;
            prefix = prefix[0..cut];
        }
    }

    fn hide(self: *Bundle, rel: []const u8) !void {
        self.hidden_lock.lock();
        defer self.hidden_lock.unlock();
        if (self.hidden.contains(rel)) return;
        const owned = try self.allocator.dupe(u8, rel);
        errdefer self.allocator.free(owned);
        try self.hidden.put(self.allocator, owned, {});
        _ = self.hidden_count.fetchAdd(1, .release);
    }

    fn addFile(self: *Bundle, rel: []const u8, entry: Entry) !void {
        try self.files.put(self.allocator, rel, entry);
        var child = rel;
        while (true) {
            const cut = std.mem.lastIndexOfScalar(u8, child, '/');
            const parent = if (cut) |c| child[0..c] else "";
            const name = if (cut) |c| child[c + 1 ..] else child;
            const gop = try self.dirs.getOrPut(self.allocator, parent);
            const existed = gop.found_existing;
            if (!existed) {
                const owned = try self.allocator.dupe(u8, parent);
                errdefer self.allocator.free(owned);
                try self.dir_names.append(self.allocator, owned);
                gop.key_ptr.* = owned;
                gop.value_ptr.* = .empty;
            }
            try gop.value_ptr.append(self.allocator, name);
            if (existed or parent.len == 0) break;
            child = parent;
        }
    }
};

// the running executable's pack, set at startup
pub var active: ?*Bundle = null;

pub const Hit = union(enum) { file: Entry, dir };

// a path under the mount: relative to it, and on disk with `.` and `..`
// folded, the way the pack spells it
const Located = struct {
    bundle: *Bundle,
    rel: []const u8,
    disk: []const u8,
};

const PathBufs = struct {
    abs: [std.fs.max_path_bytes]u8 = undefined,
    rel: [std.fs.max_path_bytes]u8 = undefined,
    disk: [std.fs.max_path_bytes]u8 = undefined,
};

fn locate(bufs: *PathBufs, path: []const u8) ?Located {
    const packed_app = active orelse return null;
    const abs = absolute(&bufs.abs, path) orelse return null;
    const rel = packed_app.relative(&bufs.rel, abs) orelse return null;
    if (paths.hasDotSegment(abs) and !traversable(abs)) return null;
    const disk = packed_app.mounted(&bufs.disk, rel) orelse return null;
    return .{ .bundle = packed_app, .rel = rel, .disk = disk };
}

// what the pack serves at a path: nothing when the disk holds the path or the
// program removed it
pub fn find(path: []const u8) ?Hit {
    var bufs: PathBufs = .{};
    const at = locate(&bufs, path) orelse return null;
    return visible(at);
}

fn visible(at: Located) ?Hit {
    const hit = packedAt(at.bundle, at.rel) orelse return null;
    if (at.bundle.isHidden(at.rel)) return null;
    if (onDisk(at.disk)) return null;
    return hit;
}

fn packedAt(packed_app: *const Bundle, rel: []const u8) ?Hit {
    if (packed_app.files.get(rel)) |entry| return .{ .file = entry };
    if (packed_app.dirs.contains(rel)) return .dir;
    return null;
}

fn onDisk(abs: []const u8) bool {
    std.Io.Dir.cwd().access(platform.io, abs, .{}) catch |err| return err != error.FileNotFound;
    return true;
}

pub const ChildKind = enum { file, dir };
pub const Child = struct { name: []const u8, kind: ChildKind };

// the names a packed directory still shows, whatever the disk also holds
pub const Listing = struct {
    bundle: *Bundle,
    names: []const []const u8,
    index: usize = 0,
    rel_buf: [std.fs.max_path_bytes]u8 = undefined,
    rel_len: usize,

    pub fn next(self: *Listing) ?Child {
        while (self.index < self.names.len) {
            const name = self.names[self.index];
            self.index += 1;
            var buf: [std.fs.max_path_bytes]u8 = undefined;
            const rel = childPath(&buf, self.rel_buf[0..self.rel_len], name) orelse continue;
            if (self.bundle.isHidden(rel)) continue;
            const kind: ChildKind = if (self.bundle.files.contains(rel)) .file else .dir;
            return .{ .name = name, .kind = kind };
        }
        return null;
    }
};

pub fn listDir(path: []const u8) ?Listing {
    var bufs: PathBufs = .{};
    const at = locate(&bufs, path) orelse return null;
    const list = at.bundle.dirs.getPtr(at.rel) orelse return null;
    if (at.bundle.isHidden(at.rel)) return null;
    var listing = Listing{ .bundle = at.bundle, .names = list.items, .rel_len = at.rel.len };
    @memcpy(listing.rel_buf[0..at.rel.len], at.rel);
    return listing;
}

fn childPath(buf: []u8, dir: []const u8, name: []const u8) ?[]const u8 {
    if (dir.len == 0) return std.fmt.bufPrint(buf, "{s}", .{name}) catch null;
    return std.fmt.bufPrint(buf, "{s}/{s}", .{ dir, name }) catch null;
}

// the normalized absolute form of a path the pack serves, for realpath
pub fn canonicalPath(buf: []u8, path: []const u8) ?[]const u8 {
    var bufs: PathBufs = .{};
    const at = locate(&bufs, path) orelse return null;
    _ = visible(at) orelse return null;
    return at.bundle.mounted(buf, at.rel);
}

// the path the os should see for an operation that resolves it itself (stat,
// listing, rename, mkdir): under the mount, a `..` passes a directory only the
// pack holds as it would a real one, so the path is folded when every
// directory before a `..` exists in the pack or on disk. anything else, the
// os answers as it would for the spelled path
pub fn osPath(buf: []u8, path: []const u8) []const u8 {
    const packed_app = active orelse return path;
    if (!paths.hasDotSegment(path) or paths.hasScheme(path)) return path;
    var bufs: PathBufs = .{};
    const abs = absolute(&bufs.abs, path) orelse return path;
    _ = packed_app.relative(&bufs.rel, abs) orelse return path;
    if (!traversable(abs)) return path;
    return paths.expand(buf, abs) orelse path;
}

// every directory a `..` in the path steps out of exists in the union
fn traversable(abs: []const u8) bool {
    var prefix: [std.fs.max_path_bytes]u8 = undefined;
    var it = std.mem.tokenizeAny(u8, abs, "/\\");
    var end: usize = if (abs.len >= 2 and abs[1] == ':') 2 else 0;
    @memcpy(prefix[0..end], abs[0..end]);
    if (end == 2) _ = it.next();
    while (it.next()) |segment| {
        if (std.mem.eql(u8, segment, "..") and !unionDir(prefix[0..end])) return false;
        if (end + 1 + segment.len > prefix.len) return false;
        prefix[end] = '/';
        @memcpy(prefix[end + 1 .. end + 1 + segment.len], segment);
        end += 1 + segment.len;
    }
    return true;
}

fn unionDir(path: []const u8) bool {
    if (path.len == 0) return true;
    if (find(path)) |hit| return hit == .dir;
    var dir = std.Io.Dir.cwd().openDir(platform.io, path, .{}) catch return false;
    dir.close(platform.io);
    return true;
}

// the mounted path of a file the pack serves, for the include resolver
pub fn filePath(buf: []u8, path: []const u8) ?[]const u8 {
    var bufs: PathBufs = .{};
    const at = locate(&bufs, path) orelse return null;
    const hit = visible(at) orelse return null;
    if (hit != .file) return null;
    return at.bundle.mounted(buf, at.rel);
}

// the bytes of a file the pack serves; they live as long as the process
pub fn packedSource(path: []const u8) ?[]const u8 {
    const hit = find(path) orelse return null;
    return switch (hit) {
        .file => |entry| entry.source,
        .dir => null,
    };
}

// a file's bytes as php's stream opens read them: from the pack when it serves
// the path, else from the disk
pub fn readFileAlloc(allocator: Allocator, spelled: []const u8, max_bytes: usize) ![]u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = paths.streamPath(&buf, spelled);
    if (find(path)) |hit| switch (hit) {
        .file => |entry| {
            if (entry.source.len > max_bytes) return error.FileTooBig;
            return allocator.dupe(u8, entry.source);
        },
        .dir => return error.IsDir,
    };
    return std.Io.Dir.cwd().readFileAlloc(platform.io, path, allocator, .limited(max_bytes));
}

pub const WriteMode = enum {
    // the write replaces whatever is at the path
    create,
    // the write keeps what is at the path: appends, in-place edits, metadata
    edit,
};

// readies the disk for a write to a path under the mount: the packed
// directories above it are created, and for an edit a packed file (or every
// file of a packed directory) is copied up with its build mtime. failures are
// left for the write itself to report
pub fn prepareWrite(path: []const u8, mode: WriteMode) void {
    var bufs: PathBufs = .{};
    const at = locate(&bufs, path) orelse return;
    if (std.fs.path.dirname(at.disk)) |parent| ensureDir(parent);
    if (mode == .edit) copyUp(at);
}

// a directory the pack serves is made on disk too, for what needs a real one
// (a working directory, a place to create files); its files stay packed
pub fn ensureDir(path: []const u8) void {
    var bufs: PathBufs = .{};
    const at = locate(&bufs, path) orelse return;
    const hit = visible(at) orelse return;
    if (hit == .dir) std.Io.Dir.cwd().createDirPath(platform.io, at.disk) catch {};
}

fn copyUp(at: Located) void {
    const hit = visible(at) orelse return;
    switch (hit) {
        .file => |entry| writeCopy(at.disk, entry),
        .dir => {
            std.Io.Dir.cwd().createDirPath(platform.io, at.disk) catch return;
            var it = at.bundle.files.iterator();
            while (it.next()) |item| {
                const rel = item.key_ptr.*;
                if (!inside(rel, at.rel)) continue;
                var bufs: PathBufs = .{};
                const abs = at.bundle.mounted(&bufs.abs, rel) orelse continue;
                if (at.bundle.isHidden(rel) or onDisk(abs)) continue;
                if (std.fs.path.dirname(abs)) |parent| std.Io.Dir.cwd().createDirPath(platform.io, parent) catch continue;
                writeCopy(abs, item.value_ptr.*);
            }
        },
    }
}

fn inside(rel: []const u8, dir: []const u8) bool {
    if (dir.len == 0) return true;
    return rel.len > dir.len + 1 and std.mem.startsWith(u8, rel, dir) and rel[dir.len] == '/';
}

fn writeCopy(abs: []const u8, entry: Entry) void {
    const file = std.Io.Dir.cwd().createFile(platform.io, abs, .{ .exclusive = true }) catch return;
    defer file.close(platform.io);
    platform.writeAll(file, entry.source) catch return;
    const ts: std.Io.Timestamp = .{ .nanoseconds = @as(i96, entry.mtime) * std.time.ns_per_s };
    file.setTimestamps(platform.io, .{ .access_timestamp = .{ .new = ts }, .modify_timestamp = .{ .new = ts } }) catch {};
}

// hides what the pack holds at a path the program removed; true when the
// path is now gone, the pack having held it
pub fn remove(path: []const u8) bool {
    var bufs: PathBufs = .{};
    const at = locate(&bufs, path) orelse return false;
    _ = packedAt(at.bundle, at.rel) orelse return false;
    at.bundle.hide(at.rel) catch return false;
    return !onDisk(at.disk);
}

fn pathsEqual(a: []const u8, b: []const u8) bool {
    if (@import("builtin").os.tag == .windows) return std.ascii.eqlIgnoreCase(a, b);
    return std.mem.eql(u8, a, b);
}

// ---------------------------------------------------------------------------
// writing

pub const Writer = struct {
    allocator: Allocator,
    out: std.ArrayListUnmanaged(u8) = .empty,
    count: u32 = 0,
    count_at: usize = 0,

    pub fn init(allocator: Allocator, build_root: []const u8, entry: []const u8) !Writer {
        var w = Writer{ .allocator = allocator };
        errdefer w.out.deinit(allocator);
        try w.out.appendSlice(allocator, pack_magic);
        try w.int(u32, pack_version);
        try w.bytes(build_root);
        try w.bytes(entry);
        w.count_at = w.out.items.len;
        try w.int(u32, 0);
        return w;
    }

    pub fn deinit(self: *Writer) void {
        self.out.deinit(self.allocator);
    }

    pub fn add(self: *Writer, rel: []const u8, entry: Entry) !void {
        try self.bytes(rel);
        try self.out.append(self.allocator, @intFromEnum(entry.kind));
        try self.int(i64, entry.mtime);
        try self.bytes(entry.source);
        try self.bytes(entry.bytecode);
        self.count += 1;
    }

    pub fn finish(self: *Writer) []const u8 {
        std.mem.writeInt(u32, self.out.items[self.count_at..][0..4], self.count, .little);
        return self.out.items;
    }

    fn int(self: *Writer, comptime T: type, value: T) !void {
        var raw: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(T, &raw, value, .little);
        try self.out.appendSlice(self.allocator, &raw);
    }

    fn bytes(self: *Writer, data: []const u8) !void {
        try self.int(u64, data.len);
        try self.out.appendSlice(self.allocator, data);
    }
};

// the executable at exe_path with the pack appended, written to out_path
pub fn writeExecutable(allocator: Allocator, exe_path: []const u8, pack: []const u8, out_path: []const u8) !void {
    const exe = try std.Io.Dir.cwd().readFileAlloc(platform.io, exe_path, allocator, .limited(1 << 30));
    defer allocator.free(exe);
    const out = try std.Io.Dir.cwd().createFile(platform.io, out_path, .{ .permissions = platform.permissionsFromMode(0o755) });
    defer out.close(platform.io);
    try platform.writeAll(out, exe);
    try platform.writeAll(out, pack);
    var trailer: [trailer_size]u8 = undefined;
    @memcpy(trailer[0..trailer_magic.len], trailer_magic);
    std.mem.writeInt(u64, trailer[trailer_magic.len..][0..8], exe.len, .little);
    std.mem.writeInt(u64, trailer[trailer_magic.len + 8 ..][0..8], pack.len, .little);
    try platform.writeAll(out, &trailer);
}

// ---------------------------------------------------------------------------
// reading

pub const ParseError = error{ InvalidPack, OutOfMemory };

// the pack appended to the executable at exe_path, mounted at mount; null when
// there is none
pub fn load(allocator: Allocator, exe_path: []const u8, mount: []const u8) ParseError!?*Bundle {
    const file = std.Io.Dir.cwd().openFile(platform.io, exe_path, .{}) catch return null;
    defer file.close(platform.io);
    const size = platform.getEndPos(file) catch return null;
    if (size < trailer_size) return null;
    var trailer: [trailer_size]u8 = undefined;
    platform.seekTo(file, size - trailer_size) catch return null;
    if ((platform.readAll(file, &trailer) catch return null) != trailer_size) return null;
    if (!std.mem.eql(u8, trailer[0..trailer_magic.len], trailer_magic)) return null;
    const offset = std.mem.readInt(u64, trailer[trailer_magic.len..][0..8], .little);
    const len = std.mem.readInt(u64, trailer[trailer_magic.len + 8 ..][0..8], .little);
    if (offset + len + trailer_size > size) return error.InvalidPack;
    const blob = try allocator.alloc(u8, @intCast(len));
    errdefer allocator.free(blob);
    platform.seekTo(file, offset) catch return error.InvalidPack;
    if ((platform.readAll(file, blob) catch return error.InvalidPack) != len) return error.InvalidPack;
    return try parse(allocator, blob, mount);
}

// takes ownership of blob
pub fn parse(allocator: Allocator, blob: []u8, mount: []const u8) ParseError!*Bundle {
    var key_buf: [std.fs.max_path_bytes]u8 = undefined;
    const key = normalize(&key_buf, mount) orelse return error.InvalidPack;
    const self = try allocator.create(Bundle);
    const owned_mount = allocator.dupe(u8, mount) catch |err| {
        allocator.destroy(self);
        return err;
    };
    const owned_key = allocator.dupe(u8, key) catch |err| {
        allocator.free(owned_mount);
        allocator.destroy(self);
        return err;
    };
    self.* = .{ .allocator = allocator, .blob = blob, .build_root = "", .entry = "", .mount = owned_mount, .mount_key = owned_key };
    errdefer self.deinit();
    var r = Reader{ .data = blob };
    if (!std.mem.eql(u8, try r.take(pack_magic.len), pack_magic)) return error.InvalidPack;
    if (try r.int(u32) != pack_version) return error.InvalidPack;
    self.build_root = try r.bytes();
    self.entry = try r.bytes();
    const count = try r.int(u32);
    try self.dirs.put(allocator, "", .empty);
    for (0..count) |_| {
        const rel = try r.bytes();
        const kind_byte = (try r.take(1))[0];
        const kind: Kind = switch (kind_byte) {
            0 => .file,
            1 => .php,
            else => return error.InvalidPack,
        };
        const mtime = try r.int(i64);
        const source = try r.bytes();
        const bytecode = try r.bytes();
        try self.addFile(rel, .{ .kind = kind, .mtime = mtime, .source = source, .bytecode = bytecode });
    }
    return self;
}

const Reader = struct {
    data: []const u8,
    pos: usize = 0,

    fn take(self: *Reader, n: usize) ParseError![]const u8 {
        if (self.pos + n > self.data.len) return error.InvalidPack;
        defer self.pos += n;
        return self.data[self.pos .. self.pos + n];
    }

    fn int(self: *Reader, comptime T: type) ParseError!T {
        return std.mem.readInt(T, (try self.take(@sizeOf(T)))[0..@sizeOf(T)], .little);
    }

    fn bytes(self: *Reader) ParseError![]const u8 {
        const n = try self.int(u64);
        return self.take(@intCast(n));
    }
};

test "a pack round-trips and answers path queries under its mount" {
    const a = std.testing.allocator;
    var w = try Writer.init(a, "/build/app", "public/index.php");
    defer w.deinit();
    try w.add("public/index.php", .{ .kind = .php, .mtime = 7, .source = "<?php echo 1;", .bytecode = "BC" });
    try w.add("config/app.php", .{ .kind = .php, .mtime = 8, .source = "<?php return [];" });
    try w.add(".env", .{ .kind = .file, .mtime = 9, .source = "A=1" });
    const pack = try a.dupe(u8, w.finish());
    const b = try parse(a, pack, "/nonexistent-zphp-mount/app");
    defer b.deinit();
    active = b;
    defer active = null;
    try std.testing.expectEqualStrings("/build/app", b.build_root);
    try std.testing.expectEqualStrings("public/index.php", b.entry);
    try std.testing.expectEqualStrings("BC", find("/nonexistent-zphp-mount/app/public/index.php").?.file.bytecode);
    try std.testing.expectEqualStrings("A=1", find("/nonexistent-zphp-mount/app/./config/../.env").?.file.source);
    try std.testing.expect(find("/nonexistent-zphp-mount/app/missing.php") == null);
    try std.testing.expect(find("/nonexistent-zphp-mount/other/.env") == null);
    try std.testing.expect(find("/nonexistent-zphp-mount/app").? == .dir);
    try std.testing.expect(find("/nonexistent-zphp-mount/app/config/").? == .dir);
    var listing = listDir("/nonexistent-zphp-mount/app").?;
    var count: usize = 0;
    while (listing.next()) |_| count += 1;
    try std.testing.expectEqual(@as(usize, 3), count);
    var buf: [256]u8 = undefined;
    const sep = std.fs.path.sep_str;
    try std.testing.expectEqualStrings("/nonexistent-zphp-mount/app" ++ sep ++ "config" ++ sep ++ "app.php", b.mounted(&buf, "config/app.php").?);

    try std.testing.expect(remove("/nonexistent-zphp-mount/app/config/app.php"));
    try std.testing.expect(find("/nonexistent-zphp-mount/app/config/app.php") == null);
    try std.testing.expect(remove("/nonexistent-zphp-mount/app/public"));
    try std.testing.expect(find("/nonexistent-zphp-mount/app/public/index.php") == null);
    listing = listDir("/nonexistent-zphp-mount/app").?;
    count = 0;
    while (listing.next()) |_| count += 1;
    try std.testing.expectEqual(@as(usize, 2), count);
}

test "the disk shadows the pack and edits copy packed files up" {
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const mount = try tmp.dir.realPathFileAlloc(platform.io, ".", a);
    defer a.free(mount);
    var w = try Writer.init(a, "/build/app", "main.php");
    defer w.deinit();
    try w.add("main.php", .{ .kind = .php, .mtime = 1000, .source = "<?php" });
    try w.add("logs/app.log", .{ .kind = .file, .mtime = 1000, .source = "packed\n" });
    try w.add("cache/views/a.php", .{ .kind = .file, .mtime = 1000, .source = "old" });
    const b = try parse(a, try a.dupe(u8, w.finish()), mount);
    defer b.deinit();
    active = b;
    defer active = null;

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const log = b.mounted(&path_buf, "logs/app.log").?;
    prepareWrite(log, .edit);
    const copied = try tmp.dir.readFileAlloc(platform.io, "logs/app.log", a, .limited(64));
    defer a.free(copied);
    try std.testing.expectEqualStrings("packed\n", copied);
    try std.testing.expectEqual(@as(i96, 1000 * std.time.ns_per_s), (try tmp.dir.statFile(platform.io, "logs/app.log", .{})).mtime.nanoseconds);
    try std.testing.expect(find(log) == null);

    var view_buf: [std.fs.max_path_bytes]u8 = undefined;
    const view = b.mounted(&view_buf, "cache/views/a.php").?;
    prepareWrite(view, .create);
    try tmp.dir.writeFile(platform.io, .{ .sub_path = "cache/views/a.php", .data = "new" });
    try std.testing.expect(find(view) == null);
    try tmp.dir.deleteFile(platform.io, "cache/views/a.php");
    try std.testing.expect(find(view) != null);
    try std.testing.expect(remove(view));
    try std.testing.expect(find(view) == null);
}

