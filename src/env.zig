const std = @import("std");
const c = @cImport(@cInclude("stdlib.h"));
const Value = @import("runtime/value.zig").Value;
const PhpArray = @import("runtime/value.zig").PhpArray;
const VM = @import("runtime/vm.zig").VM;

pub fn loadEnvFile(allocator: std.mem.Allocator) void {
    const content = std.fs.cwd().readFileAlloc(allocator, ".env", 1024 * 1024) catch return;
    defer allocator.free(content);

    var i: usize = 0;
    while (i < content.len) {
        // skip leading whitespace and blank lines
        while (i < content.len and (content[i] == ' ' or content[i] == '\t' or content[i] == '\r' or content[i] == '\n')) i += 1;
        if (i >= content.len) break;

        // full-line comment
        if (content[i] == '#') {
            while (i < content.len and content[i] != '\n') i += 1;
            continue;
        }

        // optional `export ` prefix (shell-style dotenv files)
        if (i + 7 <= content.len and std.mem.eql(u8, content[i .. i + 7], "export ")) {
            i += 7;
            while (i < content.len and (content[i] == ' ' or content[i] == '\t')) i += 1;
        }

        // key runs to `=` or end of line
        const key_start = i;
        while (i < content.len and content[i] != '=' and content[i] != '\n') i += 1;
        if (i >= content.len or content[i] == '\n') {
            if (i < content.len) i += 1;
            continue;
        }
        const key = std.mem.trimRight(u8, content[key_start..i], " \t");
        i += 1; // skip =
        if (key.len == 0) {
            while (i < content.len and content[i] != '\n') i += 1;
            if (i < content.len) i += 1;
            continue;
        }

        // skip spaces before the value (not newlines)
        while (i < content.len and (content[i] == ' ' or content[i] == '\t')) i += 1;

        var val_start: usize = i;
        var val_end: usize = i;

        if (i < content.len and (content[i] == '"' or content[i] == '\'')) {
            // quoted value - may span newlines for things like PEM keys
            const quote = content[i];
            i += 1;
            val_start = i;
            while (i < content.len and content[i] != quote) {
                // allow `\"` inside double-quoted values to avoid terminating early
                if (content[i] == '\\' and quote == '"' and i + 1 < content.len) {
                    i += 2;
                } else {
                    i += 1;
                }
            }
            val_end = i;
            if (i < content.len) i += 1; // consume closing quote
            // discard anything after the closing quote up to end-of-line (inline comment, etc.)
            while (i < content.len and content[i] != '\n') i += 1;
        } else {
            // unquoted: end at newline or at a `#` preceded by whitespace (inline comment)
            while (i < content.len and content[i] != '\n') {
                if (content[i] == '#' and (i == val_start or content[i - 1] == ' ' or content[i - 1] == '\t')) break;
                i += 1;
            }
            val_end = i;
            // trim trailing whitespace (including CR on DOS line endings)
            while (val_end > val_start and (content[val_end - 1] == ' ' or content[val_end - 1] == '\t' or content[val_end - 1] == '\r')) {
                val_end -= 1;
            }
            // consume the rest of the line (comment tail)
            while (i < content.len and content[i] != '\n') i += 1;
        }

        if (i < content.len) i += 1; // skip newline

        const val = content[val_start..val_end];

        const key_z = allocator.dupeZ(u8, key) catch continue;
        defer allocator.free(key_z);
        const val_z = allocator.dupeZ(u8, val) catch continue;
        defer allocator.free(val_z);
        _ = c.setenv(key_z.ptr, val_z.ptr, 0);
    }
}

pub const EnvSnapshot = struct {
    env_arr: *PhpArray,
    allocator: std.mem.Allocator,

    pub fn capture(a: std.mem.Allocator) ?EnvSnapshot {
        const arr = a.create(PhpArray) catch return null;
        arr.* = .{};
        const env_map = std.process.getEnvMap(a) catch return .{ .env_arr = arr, .allocator = a };
        defer @constCast(&env_map).deinit();
        var iter = env_map.iterator();
        while (iter.next()) |entry| {
            const key = a.dupe(u8, entry.key_ptr.*) catch continue;
            const val = a.dupe(u8, entry.value_ptr.*) catch continue;
            arr.set(a, .{ .string = key }, .{ .string = val }) catch continue;
        }
        return .{ .env_arr = arr, .allocator = a };
    }

    pub fn deinit(self: *EnvSnapshot) void {
        for (self.env_arr.entries.items) |entry| {
            if (entry.key == .string) self.allocator.free(entry.key.string);
            if (entry.value == .string) self.allocator.free(entry.value.string);
        }
        self.env_arr.deinit(self.allocator);
        self.allocator.destroy(self.env_arr);
    }
};

pub fn populateEnvSuperglobal(vm: *VM, a: std.mem.Allocator, snapshot: ?*const EnvSnapshot) !void {
    if (snapshot) |snap| {
        try vm.request_vars.put(a, "$_ENV", .{ .array = snap.env_arr });
        return;
    }

    const env_arr = try a.create(PhpArray);
    env_arr.* = .{};
    try vm.arrays.append(a, env_arr);

    const env_map = std.process.getEnvMap(a) catch {
        try vm.request_vars.put(a, "$_ENV", .{ .array = env_arr });
        return;
    };
    defer @constCast(&env_map).deinit();
    var iter = env_map.iterator();
    while (iter.next()) |entry| {
        const key_owned = try a.dupe(u8, entry.key_ptr.*);
        try vm.strings.append(a, key_owned);
        const val_owned = try a.dupe(u8, entry.value_ptr.*);
        try vm.strings.append(a, val_owned);
        try env_arr.set(a, .{ .string = key_owned }, .{ .string = val_owned });
    }

    try vm.request_vars.put(a, "$_ENV", .{ .array = env_arr });
}
