const std = @import("std");
const platform = @import("platform.zig");

// a path against the working directory when it is relative
pub fn absolute(buf: []u8, path: []const u8) ?[]const u8 {
    if (std.fs.path.isAbsolute(path)) return path;
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = platform.getCwd(&cwd_buf) catch return null;
    return std.fmt.bufPrint(buf, "{s}{s}{s}", .{ cwd, std.fs.path.sep_str, path }) catch null;
}

// an absolute path with separators as '/', `.` dropped and `..` folded; null
// for a relative path or one that does not fit
pub fn normalize(buf: []u8, path: []const u8) ?[]u8 {
    if (!std.fs.path.isAbsolute(path)) return null;
    var len: usize = 0;
    var start: usize = 0;
    // keep a drive prefix as written
    if (path.len >= 2 and path[1] == ':') start = 2;
    if (start > 0) {
        if (start > buf.len) return null;
        @memcpy(buf[0..start], path[0..start]);
        len = start;
    }
    var it = std.mem.tokenizeAny(u8, path[start..], "/\\");
    while (it.next()) |segment| {
        if (std.mem.eql(u8, segment, ".")) continue;
        if (std.mem.eql(u8, segment, "..")) {
            while (len > start and buf[len - 1] != '/') len -= 1;
            if (len > start) len -= 1;
            continue;
        }
        if (len + 1 + segment.len > buf.len) return null;
        buf[len] = '/';
        @memcpy(buf[len + 1 .. len + 1 + segment.len], segment);
        len += 1 + segment.len;
    }
    if (len == start) {
        if (len + 1 > buf.len) return null;
        buf[len] = '/';
        len += 1;
    }
    return buf[0..len];
}

// php's expand_filepath, what its stream opens hand the os: the path made
// absolute against the working directory with `.` and `..` folded by name, so
// a missing directory before a `..` does not stop the open. null for a unc
// path or one that does not fit
pub fn expand(buf: []u8, path: []const u8) ?[]const u8 {
    if (path.len >= 2 and std.fs.path.isSep(path[0]) and std.fs.path.isSep(path[1])) return null;
    var abs_buf: [std.fs.max_path_bytes]u8 = undefined;
    const abs = absolute(&abs_buf, path) orelse return null;
    const out = normalize(buf, abs) orelse return null;
    if (std.fs.path.sep != '/') std.mem.replaceScalar(u8, out, '/', std.fs.path.sep);
    return out;
}

// the path php's stream opens hand the os: the spelled path, or its expansion
// when it has dots to fold
pub fn streamPath(buf: []u8, path: []const u8) []const u8 {
    if (!hasDotSegment(path) or hasScheme(path)) return path;
    return expand(buf, path) orelse path;
}

// a url-style path (php://, phar://, http://) belongs to its wrapper
pub fn hasScheme(path: []const u8) bool {
    return std.mem.indexOf(u8, path, "://") != null;
}

// whether a path spells a `.` or `..` segment
pub fn hasDotSegment(path: []const u8) bool {
    var it = std.mem.tokenizeAny(u8, path, "/\\");
    while (it.next()) |segment| {
        if (std.mem.eql(u8, segment, ".") or std.mem.eql(u8, segment, "..")) return true;
    }
    return false;
}

test "normalize folds dots and separators" {
    var buf: [128]u8 = undefined;
    try std.testing.expectEqualStrings("/a/c", normalize(&buf, "/a/./b/../c").?);
    try std.testing.expectEqualStrings("/", normalize(&buf, "/..").?);
    try std.testing.expectEqualStrings("/a/b", normalize(&buf, "/a//b/").?);
    try std.testing.expect(normalize(&buf, "rel/path") == null);
}

test "expand folds past directories that do not exist" {
    var buf: [256]u8 = undefined;
    const out = expand(&buf, "/a/missing/../b/./c").?;
    try std.testing.expectEqualStrings(if (std.fs.path.sep == '/') "/a/b/c" else "\\a\\b\\c", out);
    try std.testing.expect(hasDotSegment("x/../y"));
    try std.testing.expect(!hasDotSegment("x/.y/..z"));
}
