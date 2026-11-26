// php's realpath cache and the path resolution behind it, a port of
// Zend/zend_virtual_cwd.c (tsrm_realpath, virtual_file_ex, tsrm_realpath_r)
// for posix. each resolved absolute path is remembered for realpath_cache_ttl
// seconds, so realpath() keeps answering with what it found until the entry
// expires or clearstatcache(true), unlink, rename or rmdir drop it. windows
// resolves through the os and keeps no cache
const std = @import("std");
const platform = @import("../platform.zig");
const sys = @import("../sys.zig");
const VM = @import("../runtime/vm.zig").VM;

// MAXPATHLEN on linux and macos
pub const max_path: usize = 4096;
const link_max = 32;
const n_buckets = 1024;
// sizeof(realpath_cache_bucket) on 64-bit posix
const bucket_overhead: i64 = 48;

pub const Bucket = struct {
    key: u64,
    path: []u8,
    realpath: []u8,
    // realpath is path itself (php stores it once)
    same: bool,
    is_dir: bool,
    expires: i64,
    next: ?*Bucket,

    fn size(self: *const Bucket) i64 {
        const own: i64 = bucket_overhead + @as(i64, @intCast(self.path.len)) + 1;
        return if (self.same) own else own + @as(i64, @intCast(self.realpath.len)) + 1;
    }
};

// CWDG(realpath_cache): per thread, as php's ZTS globals are
threadlocal var buckets: [n_buckets]?*Bucket = @splat(null);
threadlocal var cache_size: i64 = 0;

const a = std.heap.c_allocator;

const Mode = enum { expand, filepath, realpath };

const Limits = struct { size_limit: i64, ttl: i64 };

fn iniValue(vm: *VM, name: []const u8) ?[]const u8 {
    return vm.ini_settings.get(name) orelse @import("../ini_config.zig").get(name);
}

// zend_atol: a number with an optional K, M or G
fn parseSize(text: []const u8) i64 {
    const t = std.mem.trim(u8, text, " \t");
    var end: usize = 0;
    if (end < t.len and (t[end] == '-' or t[end] == '+')) end += 1;
    while (end < t.len and std.ascii.isDigit(t[end])) end += 1;
    var n = std.fmt.parseInt(i64, t[0..end], 10) catch 0;
    if (end < t.len) switch (t[end]) {
        'k', 'K' => n *%= 1024,
        'm', 'M' => n *%= 1024 * 1024,
        'g', 'G' => n *%= 1024 * 1024 * 1024,
        else => {},
    };
    return n;
}

fn limits(vm: *VM) Limits {
    // an open_basedir turns the cache off (php_request_startup)
    if (iniValue(vm, "open_basedir")) |ob| if (ob.len > 0) return .{ .size_limit = 0, .ttl = 0 };
    return .{
        .size_limit = parseSize(iniValue(vm, "realpath_cache_size") orelse "4096K"),
        .ttl = parseSize(iniValue(vm, "realpath_cache_ttl") orelse "120"),
    };
}

fn now() i64 {
    return @intCast(@divFloor(platform.nanoTimestamp(), std.time.ns_per_s));
}

pub fn key(path: []const u8) u64 {
    var h: u64 = 2166136261;
    for (path) |c| {
        h *%= 16777619;
        h ^= c;
    }
    return h;
}

fn freeBucket(b: *Bucket) void {
    cache_size -= b.size();
    a.free(b.path);
    if (!b.same) a.free(b.realpath);
    a.destroy(b);
}

// realpath_cache_clean
pub fn clean() void {
    for (&buckets) |*head| {
        while (head.*) |b| {
            head.* = b.next;
            freeBucket(b);
        }
    }
    cache_size = 0;
}

// realpath_cache_del
pub fn del(path: []const u8) void {
    const k = key(path);
    var link = &buckets[k % n_buckets];
    while (link.*) |b| {
        if (b.key == k and std.mem.eql(u8, b.path, path)) {
            link.* = b.next;
            freeBucket(b);
            return;
        }
        link = &b.next;
    }
}

fn add(lim: Limits, path: []const u8, resolved: []const u8, is_dir: bool, t: i64) void {
    const same = std.mem.eql(u8, path, resolved);
    var need: i64 = bucket_overhead + @as(i64, @intCast(path.len)) + 1;
    if (!same) need += @as(i64, @intCast(resolved.len)) + 1;
    if (cache_size + need > lim.size_limit) return;
    const b = a.create(Bucket) catch return;
    const p = a.dupe(u8, path) catch {
        a.destroy(b);
        return;
    };
    const r = if (same) p else a.dupe(u8, resolved) catch {
        a.free(p);
        a.destroy(b);
        return;
    };
    const k = key(path);
    b.* = .{ .key = k, .path = p, .realpath = r, .same = same, .is_dir = is_dir, .expires = t + lim.ttl, .next = buckets[k % n_buckets] };
    buckets[k % n_buckets] = b;
    cache_size += need;
}

fn find(lim: Limits, path: []const u8, t: i64) ?*Bucket {
    const k = key(path);
    var link = &buckets[k % n_buckets];
    while (link.*) |b| {
        if (lim.ttl != 0 and b.expires < t) {
            link.* = b.next;
            freeBucket(b);
        } else if (b.key == k and std.mem.eql(u8, b.path, path)) {
            return b;
        } else link = &b.next;
    }
    return null;
}

pub fn size() i64 {
    return cache_size;
}

// the buckets in php's order, for realpath_cache_get
pub const Iterator = struct {
    index: usize = 0,
    cur: ?*Bucket = null,

    pub fn next(self: *Iterator) ?*const Bucket {
        while (self.cur == null) {
            if (self.index >= n_buckets) return null;
            self.cur = buckets[self.index];
            self.index += 1;
        }
        const b = self.cur.?;
        self.cur = b.next;
        return b;
    }
};

const Resolve = struct {
    lim: Limits,
    ll: u32 = 0,
    t: i64,
};

// tsrm_realpath_r: resolves path[0..len] in place, returning its new length
// or null where php returns (size_t)-1
fn realpathR(r: *Resolve, path: *[max_path]u8, start: usize, len_in: usize, use_realpath: Mode, is_dir_in: bool, link_is_dir: ?*bool) ?usize {
    var len = len_in;
    var is_dir = is_dir_in;
    while (true) {
        if (len <= start) {
            if (link_is_dir) |l| l.* = true;
            return start;
        }
        var i = len;
        while (i > start and path[i - 1] != '/') i -= 1;

        if (i == len or (i + 1 == len and path[i] == '.')) {
            // remove double slashes and '.'
            len = if (i > 0) i - 1 else 0;
            is_dir = true;
            continue;
        } else if (i + 2 == len and path[i] == '.' and path[i + 1] == '.') {
            // remove '..' and the directory before it
            is_dir = true;
            if (link_is_dir) |l| l.* = true;
            if (i <= start + 1) return if (start != 0) start else len;
            const j0 = realpathR(r, path, start, i - 1, use_realpath, true, null) orelse return null;
            if (j0 > start) {
                var j = j0 - 1;
                while (j > start and path[j] != '/') j -= 1;
                if (start == 0) {
                    // a leading '..' of a relative path stays
                    if (j == 0 and path[0] == '.' and path[1] == '.' and path[2] == '/') {
                        path[3] = '.';
                        path[4] = '.';
                        path[5] = '/';
                        j = 5;
                    } else if (j > 0 and path[j + 1] == '.' and path[j + 2] == '.' and path[j + 3] == '/') {
                        j += 4;
                        path[j] = '.';
                        j += 1;
                        path[j] = '.';
                        j += 1;
                        path[j] = '/';
                    }
                }
                return j;
            } else if (start == 0 and j0 == 0) {
                path[0] = '.';
                path[1] = '.';
                path[2] = '/';
                return 2;
            }
            return j0;
        }

        path[len] = 0;
        var save = use_realpath != .expand;

        if (start != 0 and save and r.lim.size_limit != 0) {
            // cache lookup for an absolute path
            if (r.t == 0) r.t = now();
            if (find(r.lim, path[0..len], r.t)) |b| {
                if (is_dir and !b.is_dir) return null;
                if (link_is_dir) |l| l.* = b.is_dir;
                @memcpy(path[0..b.realpath.len], b.realpath);
                path[b.realpath.len] = 0;
                return b.realpath.len;
            }
        }

        var mode: u32 = 0;
        if (save) {
            if (sys.lstat(path[0..len])) |st| {
                mode = st.mode;
            } else |_| {
                // not found: realpath fails, the others go on without caching
                if (use_realpath == .realpath) return null;
                save = false;
            }
        }

        var tmp: [max_path]u8 = undefined;
        @memcpy(tmp[0 .. len + 1], path[0 .. len + 1]);
        var directory = false;
        var j: usize = undefined;

        if (save and mode & std.posix.S.IFMT == std.posix.S.IFLNK) {
            r.ll += 1;
            if (r.ll > link_max) return null;
            const n = std.Io.Dir.cwd().readLink(platform.io, tmp[0..len], path[0 .. max_path - 1]) catch return null;
            path[n] = 0;
            if (n > 0 and path[0] == '/') {
                j = realpathR(r, path, 1, n, use_realpath, is_dir, &directory) orelse return null;
            } else {
                if (i == 0 or i + n >= max_path - 1) return null;
                std.mem.copyBackwards(u8, path[i .. i + n + 1], path[0 .. n + 1]);
                @memcpy(path[0 .. i - 1], tmp[0 .. i - 1]);
                path[i - 1] = '/';
                j = realpathR(r, path, start, i + n, use_realpath, is_dir, &directory) orelse return null;
            }
            if (link_is_dir) |l| l.* = directory;
        } else {
            if (save) {
                directory = mode & std.posix.S.IFMT == std.posix.S.IFDIR;
                if (link_is_dir) |l| l.* = directory;
                if (is_dir and !directory) return null;
            }
            if (i <= start + 1) {
                j = start;
            } else {
                // some leading directories may be inaccessible
                j = realpathR(r, path, start, i - 1, if (save) .filepath else use_realpath, true, null) orelse return null;
                if (j > start) {
                    path[j] = '/';
                    j += 1;
                }
            }
            if (j + len >= max_path - 1 + i) return null;
            @memcpy(path[j .. j + len - i + 1], tmp[i .. len + 1]);
            j += len - i;
        }

        if (save and start != 0 and r.lim.size_limit != 0) add(r.lim, tmp[0..len], path[0..j], directory, r.t);
        return j;
    }
}

// virtual_file_ex with CWD_REALPATH against a working directory (empty when
// getcwd failed)
fn virtualFileEx(lim: Limits, cwd: []const u8, path: []const u8, out: *[max_path]u8) ?[]const u8 {
    if (path.len == 0 or path.len >= max_path - 1) return null;
    var start: usize = 1;
    var len = path.len;
    if (path[0] != '/') {
        if (cwd.len == 0) {
            // resolve the relative path as it is
            start = 0;
            @memcpy(out[0..len], path);
        } else {
            if (len + cwd.len + 1 >= max_path - 1) return null;
            @memcpy(out[0..cwd.len], cwd);
            if (cwd[cwd.len - 1] == '/') {
                @memcpy(out[cwd.len..][0..len], path);
                len += cwd.len;
            } else {
                out[cwd.len] = '/';
                @memcpy(out[cwd.len + 1 ..][0..len], path);
                len += cwd.len + 1;
            }
        }
    } else @memcpy(out[0..len], path);
    out[len] = 0;
    var r: Resolve = .{ .lim = lim, .t = if (lim.ttl != 0) 0 else -1 };
    len = realpathR(&r, out, start, len, .realpath, false, null) orelse return null;
    if (start == 0 and len == 0) {
        out[0] = '.';
        len = 1;
    }
    return out[0..len];
}

// tsrm_realpath: what realpath() answers, or null for false
pub fn realpath(vm: *VM, path: []const u8, out: *[max_path]u8) ?[]const u8 {
    const lim = limits(vm);
    var cwd_buf: [max_path]u8 = undefined;
    const cwd = platform.getCwd(&cwd_buf) catch "";
    // realpath("") is the working directory
    if (path.len == 0) return virtualFileEx(lim, "", cwd, out);
    if (path[0] != '/') return virtualFileEx(lim, cwd, path, out);
    return virtualFileEx(lim, "", path, out);
}
