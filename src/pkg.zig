const std = @import("std");
const tui = @import("tui.zig");

const Allocator = std.mem.Allocator;
const json = std.json;

pub const ComposerJson = struct {
    name: ?[]const u8 = null,
    require: std.StringHashMapUnmanaged([]const u8) = .{},
    require_dev: std.StringHashMapUnmanaged([]const u8) = .{},
    autoload_psr4: std.StringHashMapUnmanaged([]const u8) = .{},
    allocator: Allocator = undefined,

    pub fn deinit(self: *ComposerJson) void {
        if (self.name) |n| self.allocator.free(n);
        var it = self.require.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.require.deinit(self.allocator);
        var it2 = self.require_dev.iterator();
        while (it2.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.require_dev.deinit(self.allocator);
        // psr4 keys/values are from parsed json, don't double-free
        self.autoload_psr4.deinit(self.allocator);
    }
};

pub const LockEntry = struct {
    name: []const u8,
    version: []const u8,
    dist_url: []const u8,
    dist_sha: []const u8 = "",
    autoload_psr4: std.StringHashMapUnmanaged([]const u8) = .{},
    autoload_files: std.ArrayListUnmanaged([]const u8) = .{},
};

pub fn parseComposerJson(allocator: Allocator, source: []const u8) !ComposerJson {
    var result = ComposerJson{ .allocator = allocator };
    const parsed = try json.parseFromSlice(json.Value, allocator, source, .{});
    defer parsed.deinit();
    const root = parsed.value;

    if (root != .object) return result;
    const obj = root.object;

    if (obj.get("name")) |n| {
        if (n == .string) result.name = try allocator.dupe(u8, n.string);
    }

    if (obj.get("require")) |req| {
        if (req == .object) {
            var it = req.object.iterator();
            while (it.next()) |entry| {
                const key = try allocator.dupe(u8, entry.key_ptr.*);
                const val = if (entry.value_ptr.* == .string) try allocator.dupe(u8, entry.value_ptr.string) else try allocator.dupe(u8, "*");
                try result.require.put(allocator, key, val);
            }
        }
    }

    if (obj.get("require-dev")) |req| {
        if (req == .object) {
            var it = req.object.iterator();
            while (it.next()) |entry| {
                const key = try allocator.dupe(u8, entry.key_ptr.*);
                const val = if (entry.value_ptr.* == .string) try allocator.dupe(u8, entry.value_ptr.string) else try allocator.dupe(u8, "*");
                try result.require_dev.put(allocator, key, val);
            }
        }
    }

    if (obj.get("autoload")) |al| {
        if (al == .object) {
            if (al.object.get("psr-4")) |psr4| {
                if (psr4 == .object) {
                    var it = psr4.object.iterator();
                    while (it.next()) |entry| {
                        const key = try allocator.dupe(u8, entry.key_ptr.*);
                        const val = if (entry.value_ptr.* == .string) try allocator.dupe(u8, entry.value_ptr.string) else try allocator.dupe(u8, "src/");
                        try result.autoload_psr4.put(allocator, key, val);
                    }
                }
            }
        }
    }

    return result;
}

pub fn downloadPackage(allocator: Allocator, entry: *LockEntry) !void {
    if (entry.dist_url.len == 0) return;

    const vendor_dir = try std.fmt.allocPrint(allocator, "vendor/{s}", .{entry.name});
    defer allocator.free(vendor_dir);

    try std.fs.cwd().makePath(vendor_dir);

    const zip_data = try httpGet(allocator, entry.dist_url);
    defer allocator.free(zip_data);

    const safe_name = try std.mem.replaceOwned(u8, allocator, entry.name, "/", "--");
    defer allocator.free(safe_name);
    const zip_path = try std.fmt.allocPrint(allocator, "vendor/{s}.zip", .{safe_name});
    defer allocator.free(zip_path);

    try std.fs.cwd().writeFile(.{ .sub_path = zip_path, .data = zip_data });

    var child = std.process.Child.init(&.{ "unzip", "-o", "-q", zip_path, "-d", vendor_dir }, allocator);
    const term = try child.spawnAndWait();
    if (term.Exited != 0) return error.RuntimeError;

    // clean up zip (non-critical, ok to ignore)
    std.fs.cwd().deleteFile(zip_path) catch {};

    try moveNestedDir(allocator, vendor_dir);
}

fn moveNestedDir(allocator: Allocator, vendor_dir: []const u8) !void {
    var dir = std.fs.cwd().openDir(vendor_dir, .{ .iterate = true }) catch return;
    defer dir.close();

    var iter = dir.iterate();
    var subdir_name: ?[]const u8 = null;
    var count: usize = 0;
    while (try iter.next()) |entry| {
        count += 1;
        if (entry.kind == .directory and count == 1) {
            subdir_name = try allocator.dupe(u8, entry.name);
        }
    }

    // if there's exactly one subdirectory, move its contents up
    if (count == 1) {
        if (subdir_name) |sub| {
            defer allocator.free(sub);
            const src = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ vendor_dir, sub });
            defer allocator.free(src);

            var sub_dir = std.fs.cwd().openDir(src, .{ .iterate = true }) catch return error.RuntimeError;
            defer sub_dir.close();

            var sub_iter = sub_dir.iterate();
            while (try sub_iter.next()) |file_entry| {
                const old_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ src, file_entry.name });
                defer allocator.free(old_path);
                const new_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ vendor_dir, file_entry.name });
                defer allocator.free(new_path);
                std.fs.cwd().rename(old_path, new_path) catch continue;
            }
            std.fs.cwd().deleteDir(src) catch {};
        }
    }
}

fn readLocalAutoload(allocator: Allocator, entry: *LockEntry) !void {
    const path = try std.fmt.allocPrint(allocator, "vendor/{s}/composer.json", .{entry.name});
    defer allocator.free(path);
    const data = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch return;
    defer allocator.free(data);
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, data, .{}) catch return;
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return;
    const al = root.object.get("autoload") orelse return;
    if (al != .object) return;

    if (al.object.get("psr-4")) |psr4| {
        if (psr4 == .object) {
            var it = psr4.object.iterator();
            while (it.next()) |e| {
                if (!entry.autoload_psr4.contains(e.key_ptr.*)) {
                    const k = try allocator.dupe(u8, e.key_ptr.*);
                    const v = if (e.value_ptr.* == .string) try allocator.dupe(u8, e.value_ptr.string) else try allocator.dupe(u8, "src/");
                    try entry.autoload_psr4.put(allocator, k, v);
                }
            }
        }
    }

    if (al.object.get("files")) |files| {
        if (files == .array) {
            for (files.array.items) |item| {
                if (item == .string) {
                    try entry.autoload_files.append(allocator, try allocator.dupe(u8, item.string));
                }
            }
        }
    }
}

fn appendPhpEscaped(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, s: []const u8) !void {
    for (s) |c| {
        if (c == '\\' or c == '\'') {
            try buf.append(allocator, '\\');
        }
        try buf.append(allocator, c);
    }
}

pub fn generateAutoloader(allocator: Allocator, entries: []const LockEntry, project_psr4: *std.StringHashMapUnmanaged([]const u8)) !void {
    std.fs.cwd().makePath("vendor") catch {};

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, "<?php\n");
    try buf.appendSlice(allocator, "spl_autoload_register(function ($class) {\n");
    try buf.appendSlice(allocator, "    $map = [\n");

    // project autoload
    var proj_it = project_psr4.iterator();
    while (proj_it.next()) |entry| {
        try buf.appendSlice(allocator, "        '");
        try appendPhpEscaped(&buf, allocator, entry.key_ptr.*);
        try buf.appendSlice(allocator, "' => ['");
        try appendPhpEscaped(&buf, allocator, entry.value_ptr.*);
        try buf.appendSlice(allocator, "'],\n");
    }

    // vendor autoload - collect dirs per namespace prefix
    var ns_dirs = std.StringHashMapUnmanaged(std.ArrayListUnmanaged([]const u8)){};
    for (entries) |entry| {
        var it = entry.autoload_psr4.iterator();
        while (it.next()) |e| {
            const dir = try std.fmt.allocPrint(allocator, "vendor/{s}/{s}", .{ entry.name, e.value_ptr.* });
            const gop = try ns_dirs.getOrPut(allocator, e.key_ptr.*);
            if (!gop.found_existing) gop.value_ptr.* = .{};
            try gop.value_ptr.append(allocator, dir);
        }
    }

    var ns_it = ns_dirs.iterator();
    while (ns_it.next()) |entry| {
        try buf.appendSlice(allocator, "        '");
        try appendPhpEscaped(&buf, allocator, entry.key_ptr.*);
        try buf.appendSlice(allocator, "' => [");
        for (entry.value_ptr.items, 0..) |dir, i| {
            if (i > 0) try buf.appendSlice(allocator, ", ");
            try buf.appendSlice(allocator, "'");
            try appendPhpEscaped(&buf, allocator, dir);
            try buf.appendSlice(allocator, "'");
        }
        try buf.appendSlice(allocator, "],\n");
    }

    try buf.appendSlice(allocator, "    ];\n");
    try buf.appendSlice(allocator,
        \\    foreach ($map as $prefix => $dirs) {
        \\        $len = strlen($prefix);
        \\        if (strncmp($prefix, $class, $len) === 0) {
        \\            $relative = substr($class, $len);
        \\            foreach ($dirs as $dir) {
        \\                $file = $dir . '/' . str_replace('\\', '/', $relative) . '.php';
        \\                if (file_exists($file)) {
        \\                    require $file;
        \\                    return;
        \\                }
        \\            }
        \\        }
        \\    }
        \\});
        \\
    );

    // files autoload - unconditional requires
    for (entries) |entry| {
        for (entry.autoload_files.items) |file| {
            try buf.appendSlice(allocator, "require_once 'vendor/");
            try buf.appendSlice(allocator, entry.name);
            try buf.appendSlice(allocator, "/");
            try appendPhpEscaped(&buf, allocator, file);
            try buf.appendSlice(allocator, "';\n");
        }
    }

    std.fs.cwd().writeFile(.{ .sub_path = "vendor/autoload.php", .data = buf.items }) catch {};
}

pub fn writeLockFile(allocator: Allocator, entries: []const LockEntry) !void {
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, "{\n  \"packages\": [\n");

    for (entries, 0..) |entry, i| {
        if (i > 0) try buf.appendSlice(allocator, ",\n");
        try buf.appendSlice(allocator, "    {\n");
        try buf.appendSlice(allocator, "      \"name\": \"");
        try buf.appendSlice(allocator, entry.name);
        try buf.appendSlice(allocator, "\",\n      \"version\": \"");
        try buf.appendSlice(allocator, entry.version);
        try buf.appendSlice(allocator, "\",\n      \"dist\": \"");
        try buf.appendSlice(allocator, entry.dist_url);
        try buf.appendSlice(allocator, "\"\n    }");
    }

    try buf.appendSlice(allocator, "\n  ]\n}\n");
    std.fs.cwd().writeFile(.{ .sub_path = "zphp.lock", .data = buf.items }) catch {};
}

pub fn readLockFile(allocator: Allocator) !?[]LockEntry {
    const source = std.fs.cwd().readFileAlloc(allocator, "zphp.lock", 1024 * 1024) catch return null;
    defer allocator.free(source);

    const parsed = json.parseFromSlice(json.Value, allocator, source, .{}) catch return null;
    defer parsed.deinit();

    if (parsed.value != .object) return null;
    const root = parsed.value.object;
    const pkgs = root.get("packages") orelse return null;
    if (pkgs != .array) return null;

    var entries = std.ArrayListUnmanaged(LockEntry){};
    for (pkgs.array.items) |item| {
        if (item != .object) continue;
        var entry = LockEntry{
            .name = "",
            .version = "",
            .dist_url = "",
        };
        if (item.object.get("name")) |n| {
            if (n == .string) entry.name = try allocator.dupe(u8, n.string);
        }
        if (item.object.get("version")) |v| {
            if (v == .string) entry.version = try allocator.dupe(u8, v.string);
        }
        if (item.object.get("dist")) |d| {
            if (d == .string) entry.dist_url = try allocator.dupe(u8, d.string);
        }
        try entries.append(allocator, entry);
    }

    return try entries.toOwnedSlice(allocator);
}

fn httpGet(allocator: Allocator, url: []const u8) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "curl", "-sfL", url },
        .max_output_bytes = 50 * 1024 * 1024,
    });
    defer allocator.free(result.stderr);
    if (result.term.Exited != 0) {
        allocator.free(result.stdout);
        return error.HttpError;
    }
    return result.stdout;
}

// semver

const SemVer = struct {
    major: u32 = 0,
    minor: u32 = 0,
    patch: u32 = 0,
    valid: bool = true,

    fn gte(self: SemVer, other: SemVer) bool {
        if (self.major != other.major) return self.major > other.major;
        if (self.minor != other.minor) return self.minor > other.minor;
        return self.patch >= other.patch;
    }

    fn lt(self: SemVer, other: SemVer) bool {
        return !self.gte(other);
    }
};

fn parseSemVer(version: []const u8) SemVer {
    var ver = version;
    if (ver.len > 0 and ver[0] == 'v') ver = ver[1..];

    // reject dev versions
    if (std.mem.startsWith(u8, ver, "dev-")) return .{ .valid = false };
    if (std.mem.endsWith(u8, ver, "-dev")) return .{ .valid = false };

    var result = SemVer{};
    var parts: [3][]const u8 = .{ "", "", "" };
    var pi: usize = 0;
    var start: usize = 0;
    for (ver, 0..) |c, i| {
        if (c == '.') {
            if (pi < 3) parts[pi] = ver[start..i];
            pi += 1;
            start = i + 1;
        } else if (c == '-' or c == '+') {
            // pre-release or build metadata - take what we have and stop
            if (pi < 3) parts[pi] = ver[start..i];
            pi = 3;
            break;
        }
    }
    if (pi < 3) parts[pi] = ver[start..];

    result.major = std.fmt.parseInt(u32, parts[0], 10) catch return .{ .valid = false };
    if (parts[1].len > 0) result.minor = std.fmt.parseInt(u32, parts[1], 10) catch return .{ .valid = false };
    if (parts[2].len > 0) result.patch = std.fmt.parseInt(u32, parts[2], 10) catch return .{ .valid = false };

    return result;
}

const Constraint = struct {
    kind: enum { any, exact, caret, tilde, range },
    min: SemVer = .{},
    max: SemVer = .{},
    min_inclusive: bool = true,
    max_inclusive: bool = false,
};

fn parseConstraint(raw: []const u8) Constraint {
    var s = std.mem.trim(u8, raw, " ");
    if (s.len == 0 or std.mem.eql(u8, s, "*")) return .{ .kind = .any };

    // caret: ^1.2.3 -> >=1.2.3 <2.0.0
    if (s[0] == '^') {
        const ver = parseSemVer(s[1..]);
        if (!ver.valid) return .{ .kind = .any };
        var max = SemVer{};
        if (ver.major > 0) {
            max.major = ver.major + 1;
        } else if (ver.minor > 0) {
            max.minor = ver.minor + 1;
        } else {
            max.patch = ver.patch + 1;
        }
        return .{ .kind = .caret, .min = ver, .max = max };
    }

    // tilde: ~1.2.3 -> >=1.2.3 <1.3.0, ~1.2 -> >=1.2.0 <1.3.0
    if (s[0] == '~') {
        const ver = parseSemVer(s[1..]);
        if (!ver.valid) return .{ .kind = .any };
        return .{ .kind = .tilde, .min = ver, .max = .{ .major = ver.major, .minor = ver.minor + 1 } };
    }

    // range: >=1.0 <2.0 (space separated)
    if (std.mem.startsWith(u8, s, ">=")) {
        const rest = s[2..];
        // check for space-separated upper bound
        if (std.mem.indexOf(u8, rest, " <")) |pos| {
            const min_str = std.mem.trim(u8, rest[0..pos], " ");
            const max_str = std.mem.trim(u8, rest[pos + 2 ..], " ");
            const min_ver = parseSemVer(min_str);
            const max_ver = parseSemVer(max_str);
            if (min_ver.valid and max_ver.valid) {
                return .{ .kind = .range, .min = min_ver, .max = max_ver };
            }
        }
        // just >=X.Y.Z with no upper bound
        const min_ver = parseSemVer(std.mem.trim(u8, rest, " "));
        if (min_ver.valid) {
            return .{ .kind = .range, .min = min_ver, .max = .{ .major = std.math.maxInt(u32) }, .max_inclusive = true };
        }
        return .{ .kind = .any };
    }

    // wildcard: 1.0.*, 1.*
    if (std.mem.endsWith(u8, s, ".*")) {
        const prefix = s[0 .. s.len - 2];
        // could be "1" or "1.0"
        if (std.mem.indexOf(u8, prefix, ".")) |dot| {
            const major = std.fmt.parseInt(u32, prefix[0..dot], 10) catch return .{ .kind = .any };
            const minor = std.fmt.parseInt(u32, prefix[dot + 1 ..], 10) catch return .{ .kind = .any };
            return .{ .kind = .range, .min = .{ .major = major, .minor = minor }, .max = .{ .major = major, .minor = minor + 1 } };
        } else {
            const major = std.fmt.parseInt(u32, prefix, 10) catch return .{ .kind = .any };
            return .{ .kind = .range, .min = .{ .major = major }, .max = .{ .major = major + 1 } };
        }
    }

    // exact version or composer "||" ranges - for now treat || as picking from any
    if (std.mem.indexOf(u8, s, "||")) |_| {
        return .{ .kind = .any };
    }

    // exact version
    const ver = parseSemVer(s);
    if (ver.valid) return .{ .kind = .exact, .min = ver, .max = ver, .max_inclusive = true };

    return .{ .kind = .any };
}

fn satisfiesConstraint(constraint: Constraint, version: SemVer) bool {
    if (!version.valid) return false;
    return switch (constraint.kind) {
        .any => true,
        .exact => version.major == constraint.min.major and version.minor == constraint.min.minor and version.patch == constraint.min.patch,
        .caret, .tilde, .range => blk: {
            if (!version.gte(constraint.min)) break :blk false;
            if (constraint.max_inclusive) {
                break :blk !version.gte(.{ .major = constraint.max.major, .minor = constraint.max.minor, .patch = constraint.max.patch + 1 });
            }
            break :blk version.lt(constraint.max);
        },
    };
}

// resolves a package, picking the best version matching the constraint.
// also extracts transitive require entries from the chosen version.
const ResolveResult = struct {
    entry: LockEntry,
    requires: std.StringHashMapUnmanaged([]const u8),
};

fn resolveWithConstraint(allocator: Allocator, name: []const u8, constraint_str: []const u8) !?ResolveResult {
    const url = try std.fmt.allocPrint(allocator, "https://repo.packagist.org/p2/{s}.json", .{name});
    defer allocator.free(url);

    const body = httpGet(allocator, url) catch return null;
    defer allocator.free(body);

    const parsed = json.parseFromSlice(json.Value, allocator, body, .{}) catch return null;
    defer parsed.deinit();

    if (parsed.value != .object) return null;
    const root = parsed.value.object;

    const pkgs = root.get("packages") orelse return null;
    if (pkgs != .object) return null;
    const versions = pkgs.object.get(name) orelse return null;
    if (versions != .array) return null;
    if (versions.array.items.len == 0) return null;

    const constraint = parseConstraint(constraint_str);

    for (versions.array.items) |ver_obj| {
        if (ver_obj != .object) continue;

        const ver_str_val = ver_obj.object.get("version") orelse continue;
        if (ver_str_val != .string) continue;
        const ver_str = ver_str_val.string;

        const sv = parseSemVer(ver_str);
        if (!sv.valid) continue;
        if (!satisfiesConstraint(constraint, sv)) continue;

        var entry = LockEntry{
            .name = try allocator.dupe(u8, name),
            .version = try allocator.dupe(u8, ver_str),
            .dist_url = "",
        };

        if (ver_obj.object.get("dist")) |dist| {
            if (dist == .object) {
                if (dist.object.get("url")) |u| {
                    if (u == .string) entry.dist_url = try allocator.dupe(u8, u.string);
                }
                if (dist.object.get("shasum")) |s| {
                    if (s == .string) entry.dist_sha = try allocator.dupe(u8, s.string);
                }
            }
        }

        if (ver_obj.object.get("autoload")) |al| {
            if (al == .object) {
                if (al.object.get("psr-4")) |psr4| {
                    if (psr4 == .object) {
                        var it = psr4.object.iterator();
                        while (it.next()) |e| {
                            const k = try allocator.dupe(u8, e.key_ptr.*);
                            const v2 = if (e.value_ptr.* == .string) try allocator.dupe(u8, e.value_ptr.string) else try allocator.dupe(u8, "src/");
                            try entry.autoload_psr4.put(allocator, k, v2);
                        }
                    }
                }
            }
        }

        // extract require for transitive resolution
        var requires = std.StringHashMapUnmanaged([]const u8){};
        if (ver_obj.object.get("require")) |req| {
            if (req == .object) {
                var it = req.object.iterator();
                while (it.next()) |e| {
                    const dep_name = e.key_ptr.*;
                    // skip php runtime and extension constraints
                    if (std.mem.eql(u8, dep_name, "php") or std.mem.startsWith(u8, dep_name, "ext-")) continue;
                    const k = try allocator.dupe(u8, dep_name);
                    const v = if (e.value_ptr.* == .string) try allocator.dupe(u8, e.value_ptr.string) else try allocator.dupe(u8, "*");
                    try requires.put(allocator, k, v);
                }
            }
        }

        return .{ .entry = entry, .requires = requires };
    }

    return null;
}

const ResolveError = struct {
    package: []const u8,
    required_by: []const u8,
    constraint: []const u8,
    existing_version: []const u8,
};

fn resolveAll(
    allocator: Allocator,
    direct_deps: *std.StringHashMapUnmanaged([]const u8),
    entries: *std.ArrayListUnmanaged(LockEntry),
    errors: *std.ArrayListUnmanaged(ResolveError),
) !void {
    // resolved_map: name -> index into entries
    var resolved_map = std.StringHashMapUnmanaged(usize){};
    defer resolved_map.deinit(allocator);

    // stack for BFS: (name, constraint, required_by)
    const QueueItem = struct { name: []const u8, constraint: []const u8, required_by: []const u8 };
    var queue = std.ArrayListUnmanaged(QueueItem){};
    defer queue.deinit(allocator);

    // seed with direct deps
    var it = direct_deps.iterator();
    while (it.next()) |entry| {
        try queue.append(allocator, .{
            .name = entry.key_ptr.*,
            .constraint = entry.value_ptr.*,
            .required_by = "composer.json",
        });
    }

    var qi: usize = 0;
    while (qi < queue.items.len) : (qi += 1) {
        const item = queue.items[qi];

        if (resolved_map.get(item.name)) |idx| {
            // already resolved - check if existing version satisfies new constraint
            const existing = entries.items[idx];
            const c = parseConstraint(item.constraint);
            const sv = parseSemVer(existing.version);
            if (!satisfiesConstraint(c, sv)) {
                try errors.append(allocator, .{
                    .package = try allocator.dupe(u8, item.name),
                    .required_by = try allocator.dupe(u8, item.required_by),
                    .constraint = try allocator.dupe(u8, item.constraint),
                    .existing_version = try allocator.dupe(u8, existing.version),
                });
            }
            continue;
        }

        const result = try resolveWithConstraint(allocator, item.name, item.constraint);
        if (result) |r| {
            const idx = entries.items.len;
            try entries.append(allocator, r.entry);
            try resolved_map.put(allocator, entries.items[idx].name, idx);

            // enqueue transitive deps
            var dep_it = r.requires.iterator();
            while (dep_it.next()) |dep| {
                try queue.append(allocator, .{
                    .name = dep.key_ptr.*,
                    .constraint = dep.value_ptr.*,
                    .required_by = entries.items[idx].name,
                });
            }
            // keep the requires map alive - keys/values are used by queue items
        } else {
            tui.blank();
            tui.warn(item.name);
        }
    }
}

// commands

pub fn install(allocator: Allocator) !void {
    const start = std.time.milliTimestamp();

    const source = std.fs.cwd().readFileAlloc(allocator, "composer.json", 1024 * 1024) catch {
        tui.err("no composer.json found");
        return;
    };
    defer allocator.free(source);

    var composer = try parseComposerJson(allocator, source);
    defer composer.deinit();

    // skip php runtime and extension constraints
    if (composer.require.fetchRemove("php")) |removed| {
        allocator.free(removed.key);
        allocator.free(removed.value);
    }
    var skip_keys = std.ArrayListUnmanaged([]const u8){};
    defer skip_keys.deinit(allocator);
    {
        var kit = composer.require.iterator();
        while (kit.next()) |entry| {
            if (std.mem.startsWith(u8, entry.key_ptr.*, "ext-")) {
                try skip_keys.append(allocator, entry.key_ptr.*);
            }
        }
    }
    for (skip_keys.items) |key| {
        if (composer.require.fetchRemove(key)) |removed| {
            allocator.free(removed.key);
            allocator.free(removed.value);
        }
    }

    const pkg_count = composer.require.count();
    if (pkg_count == 0) {
        tui.success("no packages to install");
        return;
    }

    tui.blank();
    tui.header("resolving dependencies");

    var entries = std.ArrayListUnmanaged(LockEntry){};
    defer {
        for (entries.items) |*e| {
            allocator.free(e.name);
            allocator.free(e.version);
            allocator.free(e.dist_url);
            if (e.dist_sha.len > 0) allocator.free(e.dist_sha);
            var psr4_it = e.autoload_psr4.iterator();
            while (psr4_it.next()) |p| {
                allocator.free(p.key_ptr.*);
                allocator.free(p.value_ptr.*);
            }
            e.autoload_psr4.deinit(allocator);
        }
        entries.deinit(allocator);
    }

    var conflicts = std.ArrayListUnmanaged(ResolveError){};
    defer conflicts.deinit(allocator);

    try resolveAll(allocator, &composer.require, &entries, &conflicts);
    tui.progressDone(entries.items.len, "packages resolved");

    if (conflicts.items.len > 0) {
        tui.blank();
        tui.header("conflicts");
        for (conflicts.items) |c| {
            const msg = std.fmt.allocPrint(allocator, "{s} requires {s} {s}, but {s} is already resolved", .{ c.required_by, c.package, c.constraint, c.existing_version }) catch continue;
            defer allocator.free(msg);
            tui.err(msg);
        }
        tui.blank();
        return;
    }

    tui.blank();
    tui.header("downloading");
    for (entries.items, 0..) |*entry, i| {
        tui.progress(i + 1, entries.items.len, entry.name);
        try downloadPackage(allocator, entry);
        try readLocalAutoload(allocator, entry);
    }
    tui.progressDone(entries.items.len, "packages downloaded");

    tui.blank();
    tui.header("generating autoloader");
    try generateAutoloader(allocator, entries.items, &composer.autoload_psr4);
    try writeLockFile(allocator, entries.items);
    tui.success("vendor/autoload.php");

    const elapsed: u64 = @intCast(std.time.milliTimestamp() - start);
    tui.blank();
    tui.timing("installed", elapsed);
    tui.blank();
}

pub fn packages(allocator: Allocator) !void {
    const entries = try readLockFile(allocator) orelse {
        tui.err("no zphp.lock found - run zphp install first");
        return;
    };

    tui.blank();
    tui.heading("  installed packages");
    tui.blank();

    for (entries) |entry| {
        tui.tableRow(entry.name, entry.version, "");
    }

    tui.blank();
    var buf: [32]u8 = undefined;
    const count_str = std.fmt.bufPrint(&buf, "{d} packages", .{entries.len}) catch "?";
    tui.success(count_str);
    tui.blank();
}

pub fn add(allocator: Allocator, name: []const u8) !void {
    tui.blank();
    tui.header("adding");
    tui.step("resolving", name);

    var deps = std.StringHashMapUnmanaged([]const u8){};
    defer deps.deinit(allocator);
    const name_dupe = try allocator.dupe(u8, name);
    const star = try allocator.dupe(u8, "*");
    try deps.put(allocator, name_dupe, star);

    var entries = std.ArrayListUnmanaged(LockEntry){};
    defer entries.deinit(allocator);

    var conflicts = std.ArrayListUnmanaged(ResolveError){};
    defer conflicts.deinit(allocator);

    try resolveAll(allocator, &deps, &entries, &conflicts);

    if (entries.items.len == 0) {
        tui.err("package not found on packagist");
        return;
    }

    if (conflicts.items.len > 0) {
        for (conflicts.items) |c| {
            const msg = std.fmt.allocPrint(allocator, "{s} requires {s} {s}, but {s} is already resolved", .{ c.required_by, c.package, c.constraint, c.existing_version }) catch continue;
            defer allocator.free(msg);
            tui.err(msg);
        }
        return;
    }

    for (entries.items) |*entry| {
        tui.item(entry.name, entry.version);
    }

    tui.blank();
    tui.header("downloading");
    for (entries.items, 0..) |*entry, i| {
        tui.progress(i + 1, entries.items.len, entry.name);
        try downloadPackage(allocator, entry);
        try readLocalAutoload(allocator, entry);
    }
    tui.progressDone(entries.items.len, "packages downloaded");

    // update composer.json
    const source = std.fs.cwd().readFileAlloc(allocator, "composer.json", 1024 * 1024) catch {
        var buf = std.ArrayListUnmanaged(u8){};
        defer buf.deinit(allocator);
        try buf.appendSlice(allocator, "{\n  \"require\": {\n    \"");
        try buf.appendSlice(allocator, name);
        try buf.appendSlice(allocator, "\": \"^");
        const ver = if (entries.items[0].version.len > 0 and entries.items[0].version[0] == 'v') entries.items[0].version[1..] else entries.items[0].version;
        try buf.appendSlice(allocator, ver);
        try buf.appendSlice(allocator, "\"\n  }\n}\n");
        std.fs.cwd().writeFile(.{ .sub_path = "composer.json", .data = buf.items }) catch {};
        tui.success("created composer.json");

        var empty_psr4 = std.StringHashMapUnmanaged([]const u8){};
        try generateAutoloader(allocator, entries.items, &empty_psr4);
        try writeLockFile(allocator, entries.items);
        tui.success("updated zphp.lock");
        tui.blank();
        return;
    };
    defer allocator.free(source);

    // merge with existing lock entries (avoid duplicates)
    var all_entries = std.ArrayListUnmanaged(LockEntry){};
    defer all_entries.deinit(allocator);

    for (entries.items) |e| try all_entries.append(allocator, e);

    if (try readLockFile(allocator)) |existing| {
        for (existing) |e| {
            var already = false;
            for (all_entries.items) |a| {
                if (std.mem.eql(u8, a.name, e.name)) {
                    already = true;
                    break;
                }
            }
            if (!already) try all_entries.append(allocator, e);
        }
    }

    var composer = try parseComposerJson(allocator, source);
    try generateAutoloader(allocator, all_entries.items, &composer.autoload_psr4);
    try writeLockFile(allocator, all_entries.items);

    tui.success("updated zphp.lock");
    tui.blank();
}

pub fn remove(allocator: Allocator, name: []const u8) !void {
    tui.blank();
    tui.step("removing", name);

    // remove vendor directory
    const vendor_dir = try std.fmt.allocPrint(allocator, "vendor/{s}", .{name});
    defer allocator.free(vendor_dir);
    std.fs.cwd().deleteTree(vendor_dir) catch {};

    // update lock file
    const existing = try readLockFile(allocator) orelse {
        tui.err("no zphp.lock found");
        return;
    };

    var entries = std.ArrayListUnmanaged(LockEntry){};
    defer entries.deinit(allocator);
    for (existing) |entry| {
        if (!std.mem.eql(u8, entry.name, name)) {
            try entries.append(allocator, entry);
        }
    }

    const source = std.fs.cwd().readFileAlloc(allocator, "composer.json", 1024 * 1024) catch "";
    var composer = if (source.len > 0) try parseComposerJson(allocator, source) else ComposerJson{};

    try generateAutoloader(allocator, entries.items, &composer.autoload_psr4);
    try writeLockFile(allocator, entries.items);

    tui.success("removed");
    tui.blank();
}

// unit tests

test "parseSemVer basic" {
    const v = parseSemVer("1.2.3");
    try std.testing.expect(v.valid);
    try std.testing.expectEqual(@as(u32, 1), v.major);
    try std.testing.expectEqual(@as(u32, 2), v.minor);
    try std.testing.expectEqual(@as(u32, 3), v.patch);
}

test "parseSemVer leading v" {
    const v = parseSemVer("v2.5.0");
    try std.testing.expect(v.valid);
    try std.testing.expectEqual(@as(u32, 2), v.major);
    try std.testing.expectEqual(@as(u32, 5), v.minor);
}

test "parseSemVer dev versions" {
    try std.testing.expect(!parseSemVer("dev-main").valid);
    try std.testing.expect(!parseSemVer("1.0.0-dev").valid);
}

test "parseSemVer pre-release" {
    const v = parseSemVer("2.0.0-beta.1");
    try std.testing.expect(v.valid);
    try std.testing.expectEqual(@as(u32, 2), v.major);
    try std.testing.expectEqual(@as(u32, 0), v.minor);
    try std.testing.expectEqual(@as(u32, 0), v.patch);
}

test "parseSemVer two-part" {
    const v = parseSemVer("3.1");
    try std.testing.expect(v.valid);
    try std.testing.expectEqual(@as(u32, 3), v.major);
    try std.testing.expectEqual(@as(u32, 1), v.minor);
    try std.testing.expectEqual(@as(u32, 0), v.patch);
}

test "caret constraint" {
    const c = parseConstraint("^1.2.3");
    try std.testing.expect(c.kind == .caret);

    try std.testing.expect(satisfiesConstraint(c, parseSemVer("1.2.3")));
    try std.testing.expect(satisfiesConstraint(c, parseSemVer("1.9.0")));
    try std.testing.expect(!satisfiesConstraint(c, parseSemVer("2.0.0")));
    try std.testing.expect(!satisfiesConstraint(c, parseSemVer("1.2.2")));
    try std.testing.expect(!satisfiesConstraint(c, parseSemVer("0.9.0")));
}

test "caret constraint 0.x" {
    const c = parseConstraint("^0.2.0");
    try std.testing.expect(satisfiesConstraint(c, parseSemVer("0.2.0")));
    try std.testing.expect(satisfiesConstraint(c, parseSemVer("0.2.5")));
    try std.testing.expect(!satisfiesConstraint(c, parseSemVer("0.3.0")));
}

test "tilde constraint" {
    const c = parseConstraint("~1.2.3");
    try std.testing.expect(c.kind == .tilde);

    try std.testing.expect(satisfiesConstraint(c, parseSemVer("1.2.3")));
    try std.testing.expect(satisfiesConstraint(c, parseSemVer("1.2.9")));
    try std.testing.expect(!satisfiesConstraint(c, parseSemVer("1.3.0")));
    try std.testing.expect(!satisfiesConstraint(c, parseSemVer("1.2.2")));
}

test "wildcard constraint" {
    const c = parseConstraint("1.0.*");
    try std.testing.expect(satisfiesConstraint(c, parseSemVer("1.0.0")));
    try std.testing.expect(satisfiesConstraint(c, parseSemVer("1.0.99")));
    try std.testing.expect(!satisfiesConstraint(c, parseSemVer("1.1.0")));
}

test "range constraint" {
    const c = parseConstraint(">=1.0.0 <2.0.0");
    try std.testing.expect(satisfiesConstraint(c, parseSemVer("1.0.0")));
    try std.testing.expect(satisfiesConstraint(c, parseSemVer("1.5.3")));
    try std.testing.expect(!satisfiesConstraint(c, parseSemVer("2.0.0")));
    try std.testing.expect(!satisfiesConstraint(c, parseSemVer("0.9.0")));
}

test "exact constraint" {
    const c = parseConstraint("1.2.3");
    try std.testing.expect(c.kind == .exact);
    try std.testing.expect(satisfiesConstraint(c, parseSemVer("1.2.3")));
    try std.testing.expect(!satisfiesConstraint(c, parseSemVer("1.2.4")));
}

test "any constraint" {
    const c = parseConstraint("*");
    try std.testing.expect(c.kind == .any);
    try std.testing.expect(satisfiesConstraint(c, parseSemVer("999.0.0")));
}

test "caret two-part version" {
    // ^3.0 is common in composer - means >=3.0.0 <4.0.0
    const c = parseConstraint("^3.0");
    try std.testing.expect(satisfiesConstraint(c, parseSemVer("3.0.0")));
    try std.testing.expect(satisfiesConstraint(c, parseSemVer("3.7.2")));
    try std.testing.expect(!satisfiesConstraint(c, parseSemVer("4.0.0")));
    try std.testing.expect(!satisfiesConstraint(c, parseSemVer("2.9.9")));
}

test "version with build metadata" {
    const v = parseSemVer("1.5.0+build.123");
    try std.testing.expect(v.valid);
    try std.testing.expectEqual(@as(u32, 1), v.major);
    try std.testing.expectEqual(@as(u32, 5), v.minor);
    try std.testing.expectEqual(@as(u32, 0), v.patch);
}

test "leading v with constraint" {
    // packagist versions often have leading v
    const c = parseConstraint("^3.0");
    try std.testing.expect(satisfiesConstraint(c, parseSemVer("v3.5.1")));
    try std.testing.expect(!satisfiesConstraint(c, parseSemVer("v4.0.0")));
}

test "dev versions rejected by constraint" {
    const c = parseConstraint("^1.0");
    try std.testing.expect(!satisfiesConstraint(c, parseSemVer("dev-main")));
    try std.testing.expect(!satisfiesConstraint(c, parseSemVer("1.0.0-dev")));
}

test "wildcard major" {
    const c = parseConstraint("2.*");
    try std.testing.expect(satisfiesConstraint(c, parseSemVer("2.0.0")));
    try std.testing.expect(satisfiesConstraint(c, parseSemVer("2.99.99")));
    try std.testing.expect(!satisfiesConstraint(c, parseSemVer("3.0.0")));
    try std.testing.expect(!satisfiesConstraint(c, parseSemVer("1.9.9")));
}

test "or constraint falls back to any" {
    const c = parseConstraint("^1.0 || ^2.0");
    try std.testing.expect(c.kind == .any);
}

test "gte only constraint" {
    const c = parseConstraint(">=2.0.0");
    try std.testing.expect(satisfiesConstraint(c, parseSemVer("2.0.0")));
    try std.testing.expect(satisfiesConstraint(c, parseSemVer("99.0.0")));
    try std.testing.expect(!satisfiesConstraint(c, parseSemVer("1.9.9")));
}

test "empty constraint is any" {
    const c = parseConstraint("");
    try std.testing.expect(c.kind == .any);
}

test "parseComposerJson with require" {
    const src =
        \\{"require":{"psr/log":"^3.0","monolog/monolog":"^3.5"}}
    ;
    var cj = try parseComposerJson(std.testing.allocator, src);
    defer cj.deinit();

    try std.testing.expectEqual(@as(u32, 2), cj.require.count());
    try std.testing.expect(cj.require.get("psr/log") != null);
    try std.testing.expect(cj.require.get("monolog/monolog") != null);
}
