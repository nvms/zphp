// phar://archive-or-alias/entry split into the archive on disk and the entry
// inside it. the archive is the longest prefix that names a file, so phars
// without a .phar suffix resolve, and both separators count so an archive
// under a windows path resolves too
const std = @import("std");
const platform = @import("../platform.zig");

pub const prefix = "phar://";

pub const AliasMap = std.StringHashMapUnmanaged([]const u8);

pub const Resolved = struct {
    archive_path: []const u8,
    internal_path: []const u8,
};

pub fn resolve(path: []const u8, aliases: ?*const AliasMap) ?Resolved {
    if (!std.mem.startsWith(u8, path, prefix)) return null;
    const tail = path[prefix.len..];
    if (aliases) |map| {
        if (resolveAlias(tail, map)) |r| return r;
    }
    return resolveArchive(tail);
}

fn resolveAlias(tail: []const u8, aliases: *const AliasMap) ?Resolved {
    const sep = firstSep(tail) orelse tail.len;
    const archive = aliases.get(tail[0..sep]) orelse return null;
    const internal = if (sep < tail.len) tail[sep + 1 ..] else "";
    return .{ .archive_path = archive, .internal_path = internal };
}

fn resolveArchive(tail: []const u8) ?Resolved {
    var end = tail.len;
    while (lastSepBefore(tail, end)) |sep| : (end = sep) {
        if (isFile(tail[0..sep])) return .{ .archive_path = tail[0..sep], .internal_path = tail[sep + 1 ..] };
    }
    if (isFile(tail)) return .{ .archive_path = tail, .internal_path = "" };
    return null;
}

fn firstSep(s: []const u8) ?usize {
    for (s, 0..) |c, i| if (platform.isSep(c)) return i;
    return null;
}

fn lastSepBefore(s: []const u8, end: usize) ?usize {
    var i = end;
    while (i > 0) : (i -= 1) if (platform.isSep(s[i - 1])) return i - 1;
    return null;
}

fn isFile(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .file;
}

// entry names inside a phar always use '/', and php resolves '.' and '..'
// against the archive root, so "lib/../data/x" and a backslash path both
// map to their canonical entry
pub fn normalizeInternal(a: std.mem.Allocator, internal: []const u8) ![]u8 {
    var segments: std.ArrayListUnmanaged([]const u8) = .{};
    defer segments.deinit(a);
    var start: usize = 0;
    var i: usize = 0;
    while (i <= internal.len) : (i += 1) {
        if (i < internal.len and !platform.isSep(internal[i])) continue;
        try pushSegment(a, &segments, internal[start..i]);
        start = i + 1;
    }
    return std.mem.join(a, "/", segments.items);
}

fn pushSegment(a: std.mem.Allocator, segments: *std.ArrayListUnmanaged([]const u8), segment: []const u8) !void {
    if (segment.len == 0 or std.mem.eql(u8, segment, ".")) return;
    if (std.mem.eql(u8, segment, "..")) {
        _ = segments.pop();
        return;
    }
    try segments.append(a, segment);
}

test "normalizeInternal resolves dot segments against the root" {
    const a = std.testing.allocator;
    const cases = [_]struct { in: []const u8, out: []const u8 }{
        .{ .in = "lib/../data/config.json", .out = "data/config.json" },
        .{ .in = "a/./b//c", .out = "a/b/c" },
        .{ .in = "../../readme.md", .out = "readme.md" },
        .{ .in = "lib/", .out = "lib" },
        .{ .in = "", .out = "" },
    };
    for (cases) |case| {
        const got = try normalizeInternal(a, case.in);
        defer a.free(got);
        try std.testing.expectEqualStrings(case.out, got);
    }
}

test "resolve splits on the longest prefix that is a file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "a.phar", .data = "x" });
    const a = std.testing.allocator;
    const base = try tmp.dir.realpathAlloc(a, "a.phar");
    defer a.free(base);
    const path = try std.mem.concat(a, u8, &.{ prefix, base, "/lib/util.php" });
    defer a.free(path);
    const r = resolve(path, null) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(base, r.archive_path);
    try std.testing.expectEqualStrings("lib/util.php", r.internal_path);
    const whole = try std.mem.concat(a, u8, &.{ prefix, base });
    defer a.free(whole);
    const w = resolve(whole, null) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("", w.internal_path);
    try std.testing.expect(resolve("phar:///nope/x.phar/f", null) == null);
}

test "resolve prefers a registered alias" {
    const a = std.testing.allocator;
    var aliases: AliasMap = .{};
    defer aliases.deinit(a);
    try aliases.put(a, "app", "/opt/app.phar");
    const r = resolve("phar://app/src/main.php", &aliases) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("/opt/app.phar", r.archive_path);
    try std.testing.expectEqualStrings("src/main.php", r.internal_path);
    const bare = resolve("phar://app", &aliases) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("", bare.internal_path);
}
