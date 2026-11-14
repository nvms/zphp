// get_browser(): a port of php's ext/standard/browscap.c. the file the
// browscap ini setting names is read once per vm (raw ini scanning, the
// parser callback of browscap.c) and matched with php's wildcard matcher
const std = @import("std");
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const VM = @import("../runtime/vm.zig").VM;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "get_browser", native_get_browser },
};

const num_contains = 5;
const default_section = "Default Browser Capability Settings";

const Kv = struct { key: []const u8, value: []const u8 };

const Entry = struct {
    pattern: []const u8,
    parent: ?[]const u8 = null,
    kv_start: u32,
    kv_end: u32,
    contains_start: [num_contains]u16 = @splat(0),
    contains_len: [num_contains]u8 = @splat(0),
    prefix_len: u8 = 0,
};

// what a browscap file holds: the sections in file order (a repeated
// section replaces the earlier one in its place, as zend_hash_update does),
// and their key/value pairs
pub const Data = struct {
    arena: std.heap.ArenaAllocator,
    filename: []const u8,
    entries: std.ArrayListUnmanaged(Entry) = .empty,
    index: std.StringHashMapUnmanaged(u32) = .{},
    kv: std.ArrayListUnmanaged(Kv) = .empty,

    fn find(self: *const Data, pattern: []const u8) ?*const Entry {
        const i = self.index.get(pattern) orelse return null;
        return &self.entries.items[i];
    }
};

// php_browscap_parser_cb
pub const Reader = struct {
    data: *Data,
    current: ?u32 = null,

    fn a(self: *Reader) std.mem.Allocator {
        return self.data.arena.allocator();
    }

    pub fn section(self: *Reader, raw: []const u8) !void {
        if (raw.len > std.math.maxInt(u16)) return;
        const pattern = try self.a().dupe(u8, raw);
        var new_entry: Entry = .{ .pattern = pattern, .kv_start = @intCast(self.data.kv.items.len), .kv_end = @intCast(self.data.kv.items.len) };
        new_entry.prefix_len = @intCast(@min(prefixLen(pattern), std.math.maxInt(u8)));
        var pos: usize = new_entry.prefix_len;
        for (0..num_contains) |i| pos = computeContains(pattern, pos, &new_entry.contains_start[i], &new_entry.contains_len[i]);
        const gop = try self.data.index.getOrPut(self.a(), pattern);
        if (gop.found_existing) {
            self.data.entries.items[gop.value_ptr.*] = new_entry;
        } else {
            gop.value_ptr.* = @intCast(self.data.entries.items.len);
            try self.data.entries.append(self.a(), new_entry);
        }
        self.current = gop.value_ptr.*;
    }

    pub fn entry(self: *Reader, key: []const u8, raw_value: []const u8) !void {
        const at = self.current orelse return;
        // true/false settings
        const value: []const u8 = if (eqlAny(raw_value, &.{ "on", "yes", "true" }))
            "1"
        else if (eqlAny(raw_value, &.{ "no", "off", "none", "false" }))
            ""
        else
            try self.a().dupe(u8, raw_value);
        const current = &self.data.entries.items[at];
        if (std.ascii.eqlIgnoreCase(key, "parent")) {
            current.parent = value;
            return;
        }
        const lower = try self.a().alloc(u8, key.len);
        _ = std.ascii.lowerString(lower, key);
        try self.data.kv.append(self.a(), .{ .key = lower, .value = value });
        current.kv_end = @intCast(self.data.kv.items.len);
    }
};

fn eqlAny(s: []const u8, words: []const []const u8) bool {
    for (words) |w| if (std.ascii.eqlIgnoreCase(s, w)) return true;
    return false;
}

fn isPlaceholder(c: u8) bool {
    return c == '?' or c == '*';
}

// browscap_compute_prefix_len: the part before any wildcard
fn prefixLen(pattern: []const u8) usize {
    for (pattern, 0..) |c, i| if (isPlaceholder(c)) return i;
    return pattern.len;
}

// browscap_compute_contains
fn computeContains(pattern: []const u8, start_pos: usize, start: *u16, len: *u8) usize {
    var i = start_pos;
    while (i < pattern.len) : (i += 1) {
        if (!isPlaceholder(pattern[i])) {
            // a single literal character is skipped for something longer
            if (i + 1 < pattern.len and !isPlaceholder(pattern[i + 1])) break;
        }
    }
    start.* = @intCast(@min(i, std.math.maxInt(u16)));
    while (i < pattern.len) : (i += 1) {
        if (isPlaceholder(pattern[i])) break;
    }
    len.* = @intCast(@min(i - start.*, std.math.maxInt(u8)));
    return i;
}

fn minimumLength(e: *const Entry) usize {
    var len: usize = e.prefix_len;
    for (e.contains_len) |l| len += l;
    return len;
}

// browscap_convert_pattern: the regex php reports for a pattern
fn convertPattern(buf: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, pattern: []const u8) !void {
    try buf.appendSlice(alloc, "~^");
    for (pattern) |c| switch (c) {
        '?' => try buf.append(alloc, '.'),
        '*' => try buf.appendSlice(alloc, ".*"),
        '.', '\\', '(', ')', '~', '+' => {
            try buf.append(alloc, '\\');
            try buf.append(alloc, c);
        },
        else => try buf.append(alloc, std.ascii.toLower(c)),
    };
    try buf.appendSlice(alloc, "$~");
}

// browscap_match_string_wildcard
fn matchWildcard(s: []const u8, pattern: []const u8) bool {
    var p: usize = 0;
    var i: usize = 0;
    var restore_p: ?usize = null;
    var restore_s: usize = 0;
    while (i < s.len) {
        const pc: u8 = if (p < pattern.len) pattern[p] else 0;
        if (p < pattern.len and pc == '*') {
            p += 1;
            while (p < pattern.len and pattern[p] == '*') p += 1;
            if (p == pattern.len) return true;
            if (pattern[p] != '?') {
                while (i < s.len and s[i] != pattern[p]) i += 1;
            }
            restore_p = p;
            restore_s = i;
            continue;
        } else if (p < pattern.len and (pc == s[i] or pc == '?')) {
            p += 1;
            i += 1;
            if (p == pattern.len) {
                if (i == s.len) return true;
            } else continue;
        }
        if (restore_p) |rp| {
            p = rp;
            restore_s += 1;
            i = restore_s;
        } else return false;
    }
    while (p < pattern.len and pattern[p] == '*') p += 1;
    return p == pattern.len;
}

// browser_reg_compare: true when the search is over (an exact match)
fn regCompare(e: *const Entry, agent: []const u8, lower_pattern: []const u8, found: *?*const Entry, prev_len: *usize) bool {
    var cur: usize = e.prefix_len;
    for (0..num_contains) |i| {
        const len = e.contains_len[i];
        if (len == 0) continue;
        const needle = lower_pattern[e.contains_start[i]..][0..len];
        const at = std.mem.indexOf(u8, agent[@min(cur, agent.len)..], needle) orelse return false;
        cur += at + len;
    }
    if (std.mem.eql(u8, agent, lower_pattern)) {
        found.* = e;
        return true;
    }
    if (matchWildcard(agent[e.prefix_len..], lower_pattern[e.prefix_len..])) {
        var curr_len: usize = e.prefix_len;
        for (e.pattern[e.prefix_len..]) |c| {
            if (!isPlaceholder(c)) curr_len += 1;
        }
        if (found.* == null or prev_len.* < curr_len) {
            found.* = e;
            prev_len.* = curr_len;
        }
    }
    return false;
}

fn load(vm: *VM, ctx: *NativeContext, filename: []const u8) RuntimeError!?*Data {
    if (vm.browscap) |opaque_data| {
        const data: *Data = @ptrCast(@alignCast(opaque_data));
        if (std.mem.eql(u8, data.filename, filename)) return data;
        deinit(vm);
    }
    const content = std.Io.Dir.cwd().readFileAlloc(@import("../platform.zig").io, filename, vm.allocator, .unlimited) catch return null;
    defer vm.allocator.free(content);
    const data = try vm.allocator.create(Data);
    data.* = .{ .arena = std.heap.ArenaAllocator.init(vm.allocator), .filename = "" };
    data.filename = try data.arena.allocator().dupe(u8, filename);
    vm.browscap = data;
    var reader: Reader = .{ .data = data };
    try @import("ini.zig").parseBrowscap(ctx, content, filename, &reader);
    return data;
}

pub fn deinit(vm: *VM) void {
    const opaque_data = vm.browscap orelse return;
    const data: *Data = @ptrCast(@alignCast(opaque_data));
    data.arena.deinit();
    vm.allocator.destroy(data);
    vm.browscap = null;
}

fn native_get_browser(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const vm = ctx.vm;
    const setting = vm.ini_settings.get("browscap") orelse @import("../ini_config.zig").get("browscap") orelse "";
    if (setting.len == 0) {
        try vm.emitWarning("get_browser(): browscap ini directive not set");
        return NativeResult.scalar(.{ .bool = false });
    }
    const data = (try load(vm, ctx, setting)) orelse return NativeResult.scalar(.{ .bool = false });
    const return_array = args.len > 1 and args[1].isTruthy();

    var agent_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer agent_buf.deinit(ctx.allocator);
    if (args.len > 0 and args[0] != .null) {
        try args[0].format(&agent_buf, ctx.allocator);
    } else {
        const server = vm.request_vars.get("$_SERVER") orelse Value.null;
        const ua = if (server == .array) server.array.get(.{ .string = Value.String.borrowed("HTTP_USER_AGENT") }) else Value.null;
        if (ua == .null) {
            try vm.emitWarning("get_browser(): HTTP_USER_AGENT variable is not set, cannot determine user agent name");
            return NativeResult.scalar(.{ .bool = false });
        }
        try ua.format(&agent_buf, ctx.allocator);
    }
    const agent = agent_buf.items;
    for (agent) |*c| c.* = std.ascii.toLower(c.*);

    var found: ?*const Entry = data.find(agent);
    if (found == null) {
        var prev_len: usize = 0;
        var lower: std.ArrayListUnmanaged(u8) = .empty;
        defer lower.deinit(ctx.allocator);
        for (data.entries.items) |*e| {
            if (agent.len < minimumLength(e)) continue;
            var prefix_ok = true;
            for (0..e.prefix_len) |i| {
                if (agent[i] != std.ascii.toLower(e.pattern[i])) {
                    prefix_ok = false;
                    break;
                }
            }
            if (!prefix_ok) continue;
            lower.clearRetainingCapacity();
            try lower.ensureTotalCapacity(ctx.allocator, e.pattern.len);
            for (e.pattern) |c| lower.appendAssumeCapacity(std.ascii.toLower(c));
            if (regCompare(e, agent, lower.items, &found, &prev_len)) break;
        }
        if (found == null) found = data.find(default_section);
        if (found == null) return NativeResult.scalar(.{ .bool = false });
    }

    // browscap_entry_to_array, then each parent's settings not already there
    const arr = try ctx.createArray();
    const e = found.?;
    var regex: std.ArrayListUnmanaged(u8) = .empty;
    defer regex.deinit(ctx.allocator);
    try convertPattern(&regex, ctx.allocator, e.pattern);
    try put(ctx, arr, "browser_name_regex", regex.items, true);
    try put(ctx, arr, "browser_name_pattern", e.pattern, true);
    if (e.parent) |parent| try put(ctx, arr, "parent", parent, true);
    try addKvs(ctx, arr, data, e);
    var walk = e;
    var depth: usize = 0;
    while (walk.parent) |parent| : (depth += 1) {
        if (depth > data.entries.items.len) break;
        walk = data.find(parent) orelse break;
        try addKvs(ctx, arr, data, walk);
    }
    if (return_array) return NativeResult.borrowed(.{ .array = arr });

    const obj = try ctx.createObject("stdClass");
    for (arr.entries.items) |entry| {
        var num_buf: [24]u8 = undefined;
        const name: []const u8 = switch (entry.key) {
            .string => |k| k.bytes(),
            .int => |n| std.fmt.bufPrint(&num_buf, "{d}", .{n}) catch unreachable,
        };
        try obj.set(vm.allocator, name, entry.value);
    }
    vm.releaseUnheldArray(arr);
    return NativeResult.borrowed(.{ .object = obj });
}

fn addKvs(ctx: *NativeContext, arr: *PhpArray, data: *const Data, e: *const Entry) !void {
    for (data.kv.items[e.kv_start..e.kv_end]) |kv| try put(ctx, arr, kv.key, kv.value, false);
}

// zend_hash_add: a key already there keeps its value
fn put(ctx: *NativeContext, arr: *PhpArray, key: []const u8, value: []const u8, replace: bool) !void {
    const k = PhpArray.normalizeKey(.{ .string = Value.String.borrowed(key) });
    if (!replace and arr.contains(k)) return;
    const v = try Value.String.create(ctx.allocator, value);
    defer v.release();
    const owned_key: PhpArray.Key = if (k == .string) .{ .string = try Value.String.create(ctx.allocator, key) } else k;
    defer if (owned_key == .string) owned_key.string.release();
    try ctx.vm.arraySetOwned(arr, owned_key, .{ .string = v });
}
