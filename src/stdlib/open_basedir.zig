// open_basedir: php's php_check_open_basedir_ex and php_check_specific_open_basedir
// (main/fopen_wrappers.c). a path is allowed when the deepest part of it that
// exists, symlinks resolved, lies inside one of the listed directories; "."
// names the working directory at the time of the check
const std = @import("std");
const platform = @import("../platform.zig");
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;

const RuntimeError = error{ RuntimeError, OutOfMemory };

// php's MAXPATHLEN
pub const max_path: usize = if (platform.is_windows) 260 else 4096;
const list_separator: u8 = if (platform.is_windows) ';' else ':';
const slash: u8 = if (platform.is_windows) '\\' else '/';

// the directive's current value, null when it restricts nothing
pub fn setting(vm: *const VM) ?[]const u8 {
    const value = vm.ini_settings.get("open_basedir") orelse @import("../ini_config.zig").get("open_basedir") orelse return null;
    return if (value.len == 0) null else value;
}

// php_check_open_basedir: true when the path may be used. a refusal warns
// "<func>(): open_basedir restriction in effect..." as php_error_docref does
pub fn allows(vm: *VM, func: []const u8, path: []const u8) RuntimeError!bool {
    return check(vm, func, path, true);
}

// php_check_open_basedir_ex
pub fn check(vm: *VM, func: []const u8, path: []const u8, warn: bool) RuntimeError!bool {
    const list = setting(vm) orelse return true;
    if (path.len > max_path - 1) {
        const msg = try std.fmt.allocPrint(vm.allocator, "{s}(): File name is longer than the maximum allowed path length on this platform ({d}): {s}", .{ func, max_path, path });
        defer vm.allocator.free(msg);
        try vm.emitWarning(msg);
        return false;
    }
    var it = std.mem.splitScalar(u8, list, list_separator);
    while (it.next()) |basedir| {
        if (basedir.len == 0) continue;
        if (within(basedir, path)) return true;
    }
    if (warn) {
        const msg = try std.fmt.allocPrint(vm.allocator, "{s}(): open_basedir restriction in effect. File({s}) is not within the allowed path(s): ({s})", .{ func, path, list });
        defer vm.allocator.free(msg);
        try vm.emitWarning(msg);
    }
    return false;
}

// php_check_specific_open_basedir
pub fn within(basedir: []const u8, path: []const u8) bool {
    if (path.len > max_path - 1) return false;
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    // basedir "." is the working directory
    const local_basedir = if (std.mem.eql(u8, basedir, ".")) (platform.getCwd(&cwd_buf) catch basedir) else basedir;

    // the deepest existing ancestor, resolved. a broken symlink at the end
    // counts as its target
    var tmp_buf: [std.fs.max_path_bytes]u8 = undefined;
    var tmp: []u8 = expand(path, &tmp_buf) orelse return false;
    var resolved_buf: [std.fs.max_path_bytes + 1]u8 = undefined;
    var resolved: []const u8 = undefined;
    var nesting: usize = 0;
    while (true) {
        if (platform.realpath(tmp, resolved_buf[0..std.fs.max_path_bytes])) |r| {
            resolved = r;
            break;
        } else |_| {}
        if (nesting == 0 and !platform.is_windows) {
            var link_buf: [std.fs.max_path_bytes]u8 = undefined;
            if (std.Io.Dir.cwd().readLink(platform.io, tmp, &link_buf)) |n| {
                @memcpy(tmp_buf[0..n], link_buf[0..n]);
                tmp = tmp_buf[0..n];
            } else |_| {}
        }
        const last = std.mem.lastIndexOfScalar(u8, tmp, slash) orelse return false;
        if (last == 0) {
            // nothing below the root exists: libc leaves the failed path
            @memcpy(resolved_buf[0..tmp.len], tmp);
            resolved = resolved_buf[0..tmp.len];
            break;
        }
        tmp = tmp[0..last];
        nesting += 1;
    }

    var base_buf: [std.fs.max_path_bytes + 1]u8 = undefined;
    var base: []const u8 = expand(local_basedir, base_buf[0..std.fs.max_path_bytes]) orelse return false;
    // a basedir is a directory: compare with a trailing separator
    if (base[base.len - 1] != slash) {
        base_buf[base.len] = slash;
        base = base_buf[0 .. base.len + 1];
    }

    if (startsWith(resolved, base)) return true;
    // "/openbasedir/" and "/openbasedir" are the same directory
    return base.len == resolved.len + 1 and startsWith(base, resolved);
}

fn startsWith(haystack: []const u8, prefix: []const u8) bool {
    if (haystack.len < prefix.len) return false;
    if (platform.is_windows) return std.ascii.eqlIgnoreCase(haystack[0..prefix.len], prefix);
    return std.mem.eql(u8, haystack[0..prefix.len], prefix);
}

// expand_filepath: the absolute form of a path against the working
// directory, with "." and ".." segments and repeated separators folded and
// the part that exists resolved through its symlinks
pub fn expand(path: []const u8, out: []u8) ?[]u8 {
    if (path.len == 0) return null;
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd: []const u8 = if (std.fs.path.isAbsolute(path)) "" else platform.getCwd(&cwd_buf) catch return null;
    var drive: []const u8 = "";
    var segments: [1024][]const u8 = undefined;
    var count: usize = 0;
    for ([_][]const u8{ cwd, path }) |part| {
        var rest = part;
        if (platform.is_windows and rest.len >= 2 and rest[1] == ':') {
            drive = rest[0..2];
            rest = rest[2..];
        }
        var it = std.mem.tokenizeAny(u8, rest, if (platform.is_windows) "/\\" else "/");
        while (it.next()) |seg| {
            if (std.mem.eql(u8, seg, ".")) continue;
            if (std.mem.eql(u8, seg, "..")) {
                if (count > 0) count -= 1;
                continue;
            }
            if (count == segments.len) return null;
            segments[count] = seg;
            count += 1;
        }
    }
    var len: usize = 0;
    if (drive.len + 1 > out.len) return null;
    @memcpy(out[0..drive.len], drive);
    len = drive.len;
    out[len] = slash;
    len += 1;
    for (segments[0..count], 0..) |seg, i| {
        if (i > 0) {
            if (len + 1 > out.len) return null;
            out[len] = slash;
            len += 1;
        }
        if (len + seg.len > out.len) return null;
        @memcpy(out[len .. len + seg.len], seg);
        len += seg.len;
    }
    // resolve the longest prefix that exists through its symlinks
    var kept = count;
    while (kept > 0) : (kept -= 1) {
        var probe_len: usize = drive.len + 1;
        for (segments[0..kept], 0..) |seg, i| probe_len += seg.len + @intFromBool(i > 0);
        var real_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = platform.realpath(out[0..probe_len], &real_buf) catch continue;
        const rest_len = len - probe_len;
        if (real.len + rest_len > out.len) return null;
        var tail_buf: [std.fs.max_path_bytes]u8 = undefined;
        @memcpy(tail_buf[0..rest_len], out[probe_len..len]);
        @memcpy(out[real.len .. real.len + rest_len], tail_buf[0..rest_len]);
        @memcpy(out[0..real.len], real);
        return out[0 .. real.len + rest_len];
    }
    return out[0..len];
}

// OnUpdateBaseDir at run time: a new value must be at least as restrictive
// as the current one. returns the value to store (each entry expanded), or
// null when the change is refused
pub fn tightened(vm: *VM, new_value: []const u8) RuntimeError!?[]u8 {
    if (setting(vm) == null) return try vm.allocator.dupe(u8, new_value);
    if (new_value.len == 0) return null;
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(vm.allocator);
    var it = std.mem.splitScalar(u8, new_value, list_separator);
    while (it.next()) |entry| {
        if (entry.len == 0) continue;
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const resolved = expand(entry, &buf) orelse {
            out.deinit(vm.allocator);
            return null;
        };
        if (!try check(vm, "ini_set", resolved, false)) {
            out.deinit(vm.allocator);
            return null;
        }
        if (out.items.len > 0) try out.append(vm.allocator, list_separator);
        try out.appendSlice(vm.allocator, resolved);
    }
    return try out.toOwnedSlice(vm.allocator);
}
