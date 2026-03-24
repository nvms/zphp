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

pub fn resolvePackage(allocator: Allocator, name: []const u8, constraint: []const u8) !?LockEntry {
    _ = constraint;

    // query packagist API
    const url = try std.fmt.allocPrint(allocator, "https://repo.packagist.org/p2/{s}.json", .{name});
    defer allocator.free(url);

    const body = httpGet(allocator, url) catch return null;
    defer allocator.free(body);

    const parsed = json.parseFromSlice(json.Value, allocator, body, .{}) catch return null;
    defer parsed.deinit();

    if (parsed.value != .object) return null;
    const root = parsed.value.object;

    // get packages.name array
    if (root.get("packages")) |pkgs| {
        if (pkgs != .object) return null;
        if (pkgs.object.get(name)) |versions| {
            if (versions != .array) return null;
            if (versions.array.items.len == 0) return null;

            // first entry is the latest version
            const latest = versions.array.items[0];
            if (latest != .object) return null;

            var entry = LockEntry{
                .name = try allocator.dupe(u8, name),
                .version = "",
                .dist_url = "",
            };

            if (latest.object.get("version")) |v| {
                if (v == .string) entry.version = try allocator.dupe(u8, v.string);
            }

            if (latest.object.get("dist")) |dist| {
                if (dist == .object) {
                    if (dist.object.get("url")) |u| {
                        if (u == .string) entry.dist_url = try allocator.dupe(u8, u.string);
                    }
                    if (dist.object.get("shasum")) |s| {
                        if (s == .string) entry.dist_sha = try allocator.dupe(u8, s.string);
                    }
                }
            }

            // parse autoload psr-4 from package metadata
            if (latest.object.get("autoload")) |al| {
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

            return entry;
        }
    }

    return null;
}

pub fn downloadPackage(allocator: Allocator, entry: *const LockEntry) !void {
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
            var sub_dir = dir.openDir(sub, .{ .iterate = true }) catch return;
            defer sub_dir.close();

            var sub_iter = sub_dir.iterate();
            while (sub_iter.next() catch null) |file_entry| {
                const name = allocator.dupe(u8, file_entry.name) catch continue;
                defer allocator.free(name);
                sub_dir.rename(name, dir, name) catch continue;
            }
            dir.deleteDir(sub) catch {};
        }
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
        try buf.appendSlice(allocator, entry.key_ptr.*);
        try buf.appendSlice(allocator, "' => '");
        try buf.appendSlice(allocator, entry.value_ptr.*);
        try buf.appendSlice(allocator, "',\n");
    }

    // vendor autoload
    for (entries) |entry| {
        var it = entry.autoload_psr4.iterator();
        while (it.next()) |e| {
            try buf.appendSlice(allocator, "        '");
            try buf.appendSlice(allocator, e.key_ptr.*);
            try buf.appendSlice(allocator, "' => 'vendor/");
            try buf.appendSlice(allocator, entry.name);
            try buf.appendSlice(allocator, "/");
            try buf.appendSlice(allocator, e.value_ptr.*);
            try buf.appendSlice(allocator, "',\n");
        }
    }

    try buf.appendSlice(allocator, "    ];\n");
    try buf.appendSlice(allocator,
        \\    foreach ($map as $prefix => $dir) {
        \\        $len = strlen($prefix);
        \\        if (strncmp($prefix, $class, $len) === 0) {
        \\            $relative = substr($class, $len);
        \\            $file = $dir . str_replace('\\', '/', $relative) . '.php';
        \\            if (file_exists($file)) {
        \\                require $file;
        \\                return;
        \\            }
        \\        }
        \\    }
        \\});
        \\
    );

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

    // skip php version constraint
    if (composer.require.fetchRemove("php")) |removed| {
        allocator.free(removed.key);
        allocator.free(removed.value);
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
    var resolved: usize = 0;

    var it = composer.require.iterator();
    while (it.next()) |entry| {
        resolved += 1;
        tui.progress(resolved, pkg_count, entry.key_ptr.*);
        const lock_entry = try resolvePackage(allocator, entry.key_ptr.*, entry.value_ptr.*);
        if (lock_entry) |le| {
            try entries.append(allocator, le);
        } else {
            tui.blank();
            tui.warn(entry.key_ptr.*);
        }
    }
    tui.progressDone(entries.items.len, "packages resolved");

    tui.blank();
    tui.header("downloading");
    for (entries.items, 0..) |*entry, i| {
        tui.progress(i + 1, entries.items.len, entry.name);
        try downloadPackage(allocator, entry);
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

    const entry = try resolvePackage(allocator, name, "*") orelse {
        tui.err("package not found on packagist");
        return;
    };

    tui.item(entry.name, entry.version);
    tui.step("downloading", entry.name);
    try downloadPackage(allocator, &entry);

    // update composer.json
    const source = std.fs.cwd().readFileAlloc(allocator, "composer.json", 1024 * 1024) catch {
        // create a new composer.json
        var buf = std.ArrayListUnmanaged(u8){};
        defer buf.deinit(allocator);
        try buf.appendSlice(allocator, "{\n  \"require\": {\n    \"");
        try buf.appendSlice(allocator, name);
        try buf.appendSlice(allocator, "\": \"^");
        // extract major.minor from version
        const ver = if (entry.version.len > 0 and entry.version[0] == 'v') entry.version[1..] else entry.version;
        try buf.appendSlice(allocator, ver);
        try buf.appendSlice(allocator, "\"\n  }\n}\n");
        std.fs.cwd().writeFile(.{ .sub_path = "composer.json", .data = buf.items }) catch {};
        tui.success("created composer.json");
        return;
    };
    defer allocator.free(source);

    // re-run full install to regenerate lock and autoloader
    var entries_list = std.ArrayListUnmanaged(LockEntry){};
    defer entries_list.deinit(allocator);
    try entries_list.append(allocator, entry);

    // read existing lock entries
    if (try readLockFile(allocator)) |existing| {
        for (existing) |e| try entries_list.append(allocator, e);
    }

    var composer = try parseComposerJson(allocator, source);
    try generateAutoloader(allocator, entries_list.items, &composer.autoload_psr4);
    try writeLockFile(allocator, entries_list.items);

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
