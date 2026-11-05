const std = @import("std");
const platform = @import("platform.zig");
const Allocator = std.mem.Allocator;
const bundle = @import("bundle.zig");
const parser = @import("pipeline/parser.zig");
const compiler = @import("pipeline/compiler.zig");
const bytecode_format = @import("bytecode_format.zig");

// `zphp build --compile`: the running executable with the application's file
// tree appended. the tree is every file under the root, a php file also as
// bytecode compiled at its build path, so the executable runs without the
// source directory

pub const Options = struct {
    entry: []const u8,
    // the directory to pack; defaults to the nearest directory holding a
    // composer.json above the entry, else the entry's directory
    root: ?[]const u8 = null,
    // paths relative to the root that are left out, directories included
    excludes: []const []const u8 = &.{},
    // defaults to the entry's name without its extension, in the working directory
    out: ?[]const u8 = null,
};

pub const Summary = struct {
    out: []const u8,
    root: []const u8,
    files: usize,
    compiled: usize,
    bytes: usize,
};

// directory names never packed: version control and javascript dependencies
const skipped_dirs = [_][]const u8{ ".git", "node_modules" };

pub fn build(allocator: Allocator, options: Options) !Summary {
    const entry = try platform.realpathAlloc(allocator, options.entry);
    defer allocator.free(entry);
    const root = if (options.root) |r| try platform.realpathAlloc(allocator, r) else try projectRoot(allocator, entry);
    errdefer allocator.free(root);
    const entry_rel = relativeTo(root, entry) orelse return error.EntryOutsideRoot;

    const out = if (options.out) |o| try allocator.dupe(u8, o) else try allocator.dupe(u8, std.fs.path.stem(entry));
    errdefer allocator.free(out);
    const out_abs = try std.fs.path.resolve(allocator, &.{out});
    defer allocator.free(out_abs);

    const entry_portable = try portable(allocator, entry_rel);
    defer allocator.free(entry_portable);
    var writer = try bundle.Writer.init(allocator, root, entry_portable);
    defer writer.deinit();

    var dir = try std.Io.Dir.openDirAbsolute(platform.io, root, .{ .iterate = true });
    defer dir.close(platform.io);
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    var files: usize = 0;
    var compiled: usize = 0;
    var bytes: usize = 0;
    // the executable runs from the directory the tree mounts over, so a name
    // it shares with a top-level entry would hide that entry
    var top_level = std.BufSet.init(allocator);
    defer top_level.deinit();
    while (try walker.next(platform.io)) |item| {
        if (skipped(item.path, options.excludes)) continue;
        const kind = if (item.kind == .sym_link) (item.dir.statFile(platform.io, item.basename, .{}) catch continue).kind else item.kind;
        if (kind != .file) continue;
        const abs = try std.fs.path.join(allocator, &.{ root, item.path });
        defer allocator.free(abs);
        if (std.mem.eql(u8, abs, out_abs)) continue;
        const stat = try item.dir.statFile(platform.io, item.basename, .{});
        const source = try item.dir.readFileAlloc(platform.io, item.basename, allocator, .limited(std.math.maxInt(u32)));
        defer allocator.free(source);
        const rel = try portable(allocator, item.path);
        defer allocator.free(rel);
        const mtime: i64 = @intCast(@divFloor(stat.mtime.nanoseconds, std.time.ns_per_s));
        if (std.mem.eql(u8, std.fs.path.extension(item.basename), ".php")) {
            const code = try compileFile(allocator, source, abs);
            defer if (code) |c| allocator.free(c);
            if (code != null) compiled += 1;
            try writer.add(rel, .{ .kind = .php, .mtime = mtime, .source = source, .bytecode = code orelse "" });
        } else {
            try writer.add(rel, .{ .kind = .file, .mtime = mtime, .source = source });
        }
        files += 1;
        bytes += source.len;
        var segments = std.mem.tokenizeAny(u8, item.path, "/\\");
        if (segments.next()) |first| try top_level.insert(first);
    }
    if (top_level.contains(std.fs.path.basename(out_abs))) return error.OutputShadowsPack;

    const exe = try platform.selfExePathAlloc(allocator);
    defer allocator.free(exe);
    try bundle.writeExecutable(allocator, exe, writer.finish(), out);
    return .{ .out = out, .root = root, .files = files, .compiled = compiled, .bytes = bytes };
}

// bytecode for a php file at its build path, or null when it does not
// compile; the executable then compiles it from source when it is included,
// which reports the error where php would
fn compileFile(allocator: Allocator, source: []const u8, path: []const u8) !?[]u8 {
    var ast = try parser.parse(allocator, source);
    defer ast.deinit();
    if (ast.errors.len > 0) return null;
    var result = compiler.compileWithOrigin(&ast, allocator, .{ .file_path = path }) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => return null,
    };
    defer result.deinit();
    return bytecode_format.serialize(allocator, &result) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => null,
    };
}

fn projectRoot(allocator: Allocator, entry: []const u8) ![]u8 {
    const start = std.fs.path.dirname(entry) orelse return allocator.dupe(u8, entry);
    var dir: ?[]const u8 = start;
    while (dir) |d| : (dir = std.fs.path.dirname(d)) {
        const manifest = try std.fs.path.join(allocator, &.{ d, "composer.json" });
        defer allocator.free(manifest);
        std.Io.Dir.accessAbsolute(platform.io, manifest, .{}) catch continue;
        return allocator.dupe(u8, d);
    }
    return allocator.dupe(u8, start);
}

fn relativeTo(root: []const u8, path: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, path, root) or path.len <= root.len) return null;
    if (!std.fs.path.isSep(path[root.len])) return null;
    return path[root.len + 1 ..];
}

// a packed path is '/'-separated whatever the build platform
fn portable(allocator: Allocator, rel: []const u8) ![]u8 {
    const copy = try allocator.dupe(u8, rel);
    std.mem.replaceScalar(u8, copy, '\\', '/');
    return copy;
}

fn skipped(rel: []const u8, excludes: []const []const u8) bool {
    var segments = std.mem.tokenizeAny(u8, rel, "/\\");
    while (segments.next()) |segment| {
        for (skipped_dirs) |name| if (std.mem.eql(u8, segment, name)) return true;
    }
    for (excludes) |raw| {
        const exclude = std.mem.trim(u8, raw, "/\\");
        if (exclude.len == 0) continue;
        if (!std.mem.startsWith(u8, rel, exclude)) continue;
        if (rel.len == exclude.len or std.fs.path.isSep(rel[exclude.len])) return true;
    }
    return false;
}

test "excludes match whole path segments" {
    try std.testing.expect(skipped("storage/logs/a.log", &.{"storage/logs"}));
    try std.testing.expect(skipped("storage", &.{"storage/"}));
    try std.testing.expect(!skipped("storage-old/a", &.{"storage"}));
    try std.testing.expect(skipped("vendor/pkg/node_modules/x.js", &.{}));
    try std.testing.expect(!skipped("src/git.php", &.{}));
}
