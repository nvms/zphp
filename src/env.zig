const std = @import("std");
const c = @cImport(@cInclude("stdlib.h"));
const Value = @import("runtime/value.zig").Value;
const PhpArray = @import("runtime/value.zig").PhpArray;
const VM = @import("runtime/vm.zig").VM;

pub fn loadEnvFile(allocator: std.mem.Allocator) void {
    const content = std.fs.cwd().readFileAlloc(allocator, ".env", 1024 * 1024) catch return;
    defer allocator.free(content);
    var iter = std.mem.splitScalar(u8, content, '\n');
    while (iter.next()) |raw_line| {
        const line = std.mem.trimRight(u8, raw_line, "\r");
        if (line.len == 0 or line[0] == '#') continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " \t");
        if (key.len == 0) continue;
        var val = std.mem.trim(u8, line[eq + 1 ..], " \t");
        if (val.len >= 2) {
            if ((val[0] == '"' and val[val.len - 1] == '"') or
                (val[0] == '\'' and val[val.len - 1] == '\''))
            {
                val = val[1 .. val.len - 1];
            }
        }
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
