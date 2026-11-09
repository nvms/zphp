// php class, interface, and trait names are case-insensitive (ascii only), so
// the maps keyed by them hash and compare folded names. the key keeps the
// spelling of the declaration, which is the name php reports back

const std = @import("std");
const sync = @import("../sync.zig");

pub const Context = struct {
    pub fn hash(_: Context, name: []const u8) u64 {
        var buf: [256]u8 = undefined;
        if (name.len <= buf.len) return std.hash.Wyhash.hash(0, fold(buf[0..name.len], name));
        var h = std.hash.Wyhash.init(0);
        var i: usize = 0;
        while (i < name.len) : (i += buf.len) {
            const n = @min(buf.len, name.len - i);
            h.update(fold(buf[0..n], name[i .. i + n]));
        }
        return h.final();
    }

    pub fn eql(_: Context, a: []const u8, b: []const u8) bool {
        // names are almost always written the way they were declared
        return a.len == b.len and (std.mem.eql(u8, a, b) or std.ascii.eqlIgnoreCase(a, b));
    }
};

// ascii lowercase of src into dst, eight bytes at a time
fn fold(dst: []u8, src: []const u8) []const u8 {
    const ones: u64 = 0x0101010101010101;
    const high: u64 = 0x8080808080808080;
    var i: usize = 0;
    while (i + 8 <= src.len) : (i += 8) {
        const w = std.mem.readInt(u64, src[i..][0..8], .little);
        const low7 = w & ~high;
        // high bit of each byte: at least 'A', and above 'Z', among ascii bytes
        const ge_a = low7 + ones * (0x80 - 'A');
        const gt_z = low7 + ones * (0x80 - 'Z' - 1);
        const upper = ge_a & ~gt_z & ~w & high;
        std.mem.writeInt(u64, dst[i..][0..8], w | (upper >> 2), .little);
    }
    while (i < src.len) : (i += 1) dst[i] = std.ascii.toLower(src[i]);
    return dst[0..src.len];
}

// php names an anonymous class `<parent, first interface or class>@anonymous`,
// a NUL, then the file, line and runtime definition number it was declared at
pub fn isAnonymous(name: []const u8) bool {
    return std.mem.indexOf(u8, name, anonymous_marker) != null;
}

const anonymous_marker = "@anonymous\x00";

// a class name as php prints it in messages and dumps: as a C string, which
// ends at an anonymous class's NUL
pub fn display(name: []const u8) []const u8 {
    return name[0 .. std.mem.indexOfScalar(u8, name, 0) orelse name.len];
}

// a message zphp formatted with class names in it, the way php's printf-style
// formatting writes it: each anonymous class name stops at its NUL. null when
// it names no anonymous class
pub fn stripAnonymous(allocator: std.mem.Allocator, msg: []const u8) !?[]u8 {
    var at = std.mem.indexOf(u8, msg, anonymous_marker) orelse return null;
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(allocator);
    var copied: usize = 0;
    while (true) {
        const nul = at + anonymous_marker.len - 1;
        if (anonymousSuffixEnd(msg, nul + 1)) |end| {
            try out.appendSlice(allocator, msg[copied..nul]);
            copied = end;
            at = end;
        } else at = nul + 1;
        at = std.mem.indexOfPos(u8, msg, at, anonymous_marker) orelse break;
    }
    try out.appendSlice(allocator, msg[copied..]);
    return try out.toOwnedSlice(allocator);
}

// the end of `<file>:<line>$<hex>` starting at `from`. a file may hold `:`
// and `$` itself, so the first `:digits$hex` run counts
fn anonymousSuffixEnd(msg: []const u8, from: usize) ?usize {
    var i = from;
    while (std.mem.indexOfScalarPos(u8, msg, i, ':')) |colon| : (i = colon + 1) {
        var j = colon + 1;
        while (j < msg.len and std.ascii.isDigit(msg[j])) j += 1;
        if (j == colon + 1 or j >= msg.len or msg[j] != '$') continue;
        var k = j + 1;
        while (k < msg.len and std.ascii.isHex(msg[k]) and !std.ascii.isUpper(msg[k])) k += 1;
        if (k > j + 1) return k;
    }
    return null;
}

// "Class::member", the key methods, static variables and constants are found
// under, written to `buf`. a key too long for it (an anonymous class's name
// carries its file path) is kept in a process-wide table instead, so lookups
// of long names work without every caller allocating. "" when out of memory
pub fn memberKey(buf: []u8, class: []const u8, member: []const u8) []const u8 {
    const len = class.len + 2 + member.len;
    if (len <= buf.len) {
        @memcpy(buf[0..class.len], class);
        @memcpy(buf[class.len..][0..2], "::");
        @memcpy(buf[class.len + 2 ..][0..member.len], member);
        return buf[0..len];
    }
    return longMemberKey(class, member) catch "";
}

var long_keys_lock: sync.Mutex = .{};
var long_keys_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var long_keys: std.StringHashMapUnmanaged(void) = .{};
var long_keys_scratch: std.ArrayListUnmanaged(u8) = .empty;

fn longMemberKey(class: []const u8, member: []const u8) ![]const u8 {
    long_keys_lock.lock();
    defer long_keys_lock.unlock();
    const a = long_keys_arena.allocator();
    long_keys_scratch.clearRetainingCapacity();
    try long_keys_scratch.appendSlice(a, class);
    try long_keys_scratch.appendSlice(a, "::");
    try long_keys_scratch.appendSlice(a, member);
    if (long_keys.getKey(long_keys_scratch.items)) |kept| return kept;
    const kept = try a.dupe(u8, long_keys_scratch.items);
    try long_keys.put(a, kept, {});
    return kept;
}

test "member keys of any length" {
    var buf: [16]u8 = undefined;
    try std.testing.expectEqualStrings("A::b", memberKey(&buf, "A", "b"));
    const long = "class@anonymous\x00/a/very/long/path.php:3$0";
    const key = memberKey(&buf, long, "method");
    try std.testing.expectEqualStrings(long ++ "::method", key);
    try std.testing.expectEqual(key.ptr, memberKey(&buf, long, "method").ptr);
}

test "anonymous class names print up to their NUL" {
    const a = std.testing.allocator;
    const name = "Foo@anonymous\x00/tmp/a:b.php:12$1f";
    try std.testing.expect(isAnonymous(name));
    try std.testing.expect(!isAnonymous("Foo"));
    try std.testing.expectEqualStrings("Foo@anonymous", display(name));
    const msg = try stripAnonymous(a, "Call to " ++ name ++ "::f() on class@anonymous\x00x.php:3$0");
    defer if (msg) |m| a.free(m);
    try std.testing.expectEqualStrings("Call to Foo@anonymous::f() on class@anonymous", msg.?);
    try std.testing.expect((try stripAnonymous(a, "plain")) == null);
}

pub fn Map(comptime V: type) type {
    return std.HashMapUnmanaged([]const u8, V, Context, std.hash_map.default_max_load_percentage);
}

// method names ignore case as well, except property hook entries
// (prop$hook_get), which follow their property's case-sensitive name
pub const MethodContext = struct {
    pub fn hash(_: MethodContext, name: []const u8) u64 {
        if (std.mem.indexOfScalar(u8, name, '$') != null) return std.hash.Wyhash.hash(0, name);
        return (Context{}).hash(name);
    }

    pub fn eql(_: MethodContext, a: []const u8, b: []const u8) bool {
        if (a.len != b.len) return false;
        if (std.mem.eql(u8, a, b)) return true;
        return std.mem.indexOfScalar(u8, a, '$') == null and std.ascii.eqlIgnoreCase(a, b);
    }
};

pub fn MethodMap(comptime V: type) type {
    return std.HashMapUnmanaged([]const u8, V, MethodContext, std.hash_map.default_max_load_percentage);
}

test "lookups ignore ascii case and keep the declared spelling" {
    const a = std.testing.allocator;
    var m: Map(u8) = .{};
    defer m.deinit(a);
    try m.put(a, "Foo\\BarBaz", 1);
    try std.testing.expectEqual(@as(?u8, 1), m.get("foo\\barbaz"));
    try std.testing.expectEqual(@as(?u8, 1), m.get("FOO\\BARBAZ"));
    try std.testing.expectEqualStrings("Foo\\BarBaz", m.getKey("foo\\BARBAZ").?);
    try std.testing.expect(m.get("Foo\\BarBa") == null);
    // names longer than the fold buffer hash the same in any case
    const long = "Very\\Long\\Namespace\\Path\\That\\Exceeds\\The\\Sixty\\Four\\Byte\\Buffer\\ClassName";
    try m.put(a, long, 2);
    var upper: [long.len]u8 = undefined;
    _ = std.ascii.upperString(&upper, long);
    try std.testing.expectEqual(@as(?u8, 2), m.get(&upper));
    // non-ascii bytes compare exactly, as in php
    try m.put(a, "Ünicode", 3);
    try std.testing.expect(m.get("ünicode") == null);
}

test "method names ignore case, hook entries don't" {
    const a = std.testing.allocator;
    var m: MethodMap(u8) = .{};
    defer m.deinit(a);
    try m.put(a, "getName", 1);
    try m.put(a, "name$hook_get", 2);
    try m.put(a, "Name$hook_get", 3);
    try std.testing.expectEqual(@as(?u8, 1), m.get("GETNAME"));
    try std.testing.expectEqualStrings("getName", m.getKey("getname").?);
    try std.testing.expectEqual(@as(?u8, 2), m.get("name$hook_get"));
    try std.testing.expectEqual(@as(?u8, 3), m.get("Name$hook_get"));
    try std.testing.expect(m.get("NAME$hook_get") == null);
}

test "fold lowercases exactly the ascii capitals" {
    var src: [256]u8 = undefined;
    for (&src, 0..) |*c, i| c.* = @intCast(i);
    var dst: [256]u8 = undefined;
    // every byte value, at every offset within the eight-byte words
    for (0..8) |shift| {
        const folded = fold(dst[0 .. 256 - shift], src[shift..]);
        for (folded, src[shift..]) |got, c| try std.testing.expectEqual(std.ascii.toLower(c), got);
    }
}
