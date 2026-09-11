// php.ini support: one file read at startup into a process-lifetime list of
// directives, applied to every VM at the start of each request beneath the
// request-scoped ini_set layer. `extension=` lines load extensions through
// the same loader as --extension
const std = @import("std");
const platform = @import("platform.zig");
const vm_mod = @import("runtime/vm.zig");
const VM = vm_mod.VM;
const RuntimeError = vm_mod.RuntimeError;
const extension = @import("extension.zig");

pub const Directive = struct { name: []const u8, value: []const u8 };

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var directives: std.ArrayListUnmanaged(Directive) = .{};
var loaded_file: ?[]const u8 = null;
var extension_dir: ?[]const u8 = null;

fn persistent() std.mem.Allocator {
    return arena.allocator();
}

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("zphp: " ++ fmt ++ "\n", args);
    std.process.exit(1);
}

pub fn loadedFile() ?[]const u8 {
    return loaded_file;
}

pub fn all() []const Directive {
    return directives.items;
}

pub fn get(name: []const u8) ?[]const u8 {
    var found: ?[]const u8 = null;
    for (directives.items) |d| if (std.mem.eql(u8, d.name, name)) {
        found = d.value;
    };
    return found;
}

// `zphp --ini=PATH` names the file; otherwise ZPHP_INI, then php.ini in the
// working directory, the way php-cli looks next to where it runs. an
// explicit path must exist; the discovered ones are optional
pub fn discover(explicit: ?[]const u8) void {
    if (explicit) |path| return load(path, true);
    if (platform.getenv("ZPHP_INI")) |path| return load(path, true);
    load("php.ini", false);
}

pub fn load(path: []const u8, required: bool) void {
    const bytes = std.fs.cwd().readFileAlloc(persistent(), path, 16 << 20) catch |err| {
        if (required) fail("ini file '{s}': {s}", .{ path, @errorName(err) });
        return;
    };
    loaded_file = std.fs.cwd().realpathAlloc(persistent(), path) catch persistent().dupe(u8, path) catch fail("out of memory", .{});
    parse(bytes, path);
}

// `-d name=value` on the command line, applied after the file
pub fn define(assignment: []const u8) void {
    const eq = std.mem.indexOfScalar(u8, assignment, '=') orelse {
        add(std.mem.trim(u8, assignment, " \t"), "1");
        return;
    };
    add(std.mem.trim(u8, assignment[0..eq], " \t"), cook(std.mem.trim(u8, assignment[eq + 1 ..], " \t")));
}

fn add(name: []const u8, value: []const u8) void {
    if (name.len == 0) return;
    if (std.mem.eql(u8, name, "extension")) {
        loadExtensionDirective(value);
        return;
    }
    if (std.mem.eql(u8, name, "zend_extension")) return;
    if (std.mem.eql(u8, name, "extension_dir")) extension_dir = value;
    directives.append(persistent(), .{ .name = name, .value = value }) catch fail("out of memory", .{});
}

fn parse(bytes: []const u8, path: []const u8) void {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    var line_no: usize = 0;
    while (lines.next()) |raw| {
        line_no += 1;
        var line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == ';' or line[0] == '#' or line[0] == '[') continue;
        line = stripComment(line);
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse fail("ini file '{s}' line {d}: expected name = value", .{ path, line_no });
        const name = std.mem.trim(u8, line[0..eq], " \t");
        const value = std.mem.trim(u8, line[eq + 1 ..], " \t");
        add(persistent().dupe(u8, name) catch fail("out of memory", .{}), cook(value));
    }
}

// a ; outside quotes starts a comment
fn stripComment(line: []const u8) []const u8 {
    var quoted = false;
    for (line, 0..) |ch, i| {
        if (ch == '"') quoted = !quoted;
        if (ch == ';' and !quoted) return std.mem.trim(u8, line[0..i], " \t");
    }
    return line;
}

// php's ini value rules: quotes are stripped, On/Yes/True become "1" and
// Off/No/None/False become "", ${VAR} expands from the environment, and an
// expression over E_* constants (E_ALL & ~E_DEPRECATED) is evaluated
fn cook(raw: []const u8) []const u8 {
    if (raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"') return expandEnv(raw[1 .. raw.len - 1]);
    if (raw.len == 0) return "";
    inline for (.{ "on", "yes", "true" }) |word| if (std.ascii.eqlIgnoreCase(raw, word)) return "1";
    inline for (.{ "off", "no", "none", "false", "null" }) |word| if (std.ascii.eqlIgnoreCase(raw, word)) return "";
    if (errorLevelExpression(raw)) |level| return std.fmt.allocPrint(persistent(), "{d}", .{level}) catch fail("out of memory", .{});
    return expandEnv(raw);
}

fn expandEnv(value: []const u8) []const u8 {
    if (std.mem.indexOf(u8, value, "${") == null) return persistent().dupe(u8, value) catch fail("out of memory", .{});
    var out = std.ArrayListUnmanaged(u8){};
    var i: usize = 0;
    while (i < value.len) {
        if (value[i] == '$' and i + 1 < value.len and value[i + 1] == '{') {
            if (std.mem.indexOfScalarPos(u8, value, i + 2, '}')) |close| {
                const var_name = value[i + 2 .. close];
                const name_z = persistent().dupeZ(u8, var_name) catch fail("out of memory", .{});
                if (platform.getenv(name_z)) |env| out.appendSlice(persistent(), env) catch fail("out of memory", .{});
                i = close + 1;
                continue;
            }
        }
        out.append(persistent(), value[i]) catch fail("out of memory", .{});
        i += 1;
    }
    return out.items;
}

const error_levels = [_]struct { name: []const u8, value: i64 }{
    .{ .name = "E_ERROR", .value = 1 },             .{ .name = "E_WARNING", .value = 2 },         .{ .name = "E_PARSE", .value = 4 },
    .{ .name = "E_NOTICE", .value = 8 },            .{ .name = "E_CORE_ERROR", .value = 16 },     .{ .name = "E_CORE_WARNING", .value = 32 },
    .{ .name = "E_COMPILE_ERROR", .value = 64 },    .{ .name = "E_COMPILE_WARNING", .value = 128 }, .{ .name = "E_USER_ERROR", .value = 256 },
    .{ .name = "E_USER_WARNING", .value = 512 },    .{ .name = "E_USER_NOTICE", .value = 1024 },   .{ .name = "E_STRICT", .value = 2048 },
    .{ .name = "E_RECOVERABLE_ERROR", .value = 4096 }, .{ .name = "E_DEPRECATED", .value = 8192 }, .{ .name = "E_USER_DEPRECATED", .value = 16384 },
    // php 8.4 dropped E_STRICT from E_ALL; this is also zphp's default level
    .{ .name = "E_ALL", .value = 30719 },
};

// grammar: expr = term (('|' | '&' | '^') term)*; term = '~' term | '(' expr ')' | E_NAME | integer
const LevelParser = struct {
    src: []const u8,
    pos: usize = 0,
    ok: bool = true,

    fn skip(self: *LevelParser) void {
        while (self.pos < self.src.len and (self.src[self.pos] == ' ' or self.src[self.pos] == '\t')) self.pos += 1;
    }

    fn expr(self: *LevelParser) i64 {
        var acc = self.term();
        while (true) {
            self.skip();
            if (self.pos >= self.src.len) return acc;
            const op = self.src[self.pos];
            if (op == ')') return acc;
            if (op != '|' and op != '&' and op != '^') {
                self.ok = false;
                return acc;
            }
            self.pos += 1;
            const rhs = self.term();
            acc = switch (op) {
                '|' => acc | rhs,
                '&' => acc & rhs,
                else => acc ^ rhs,
            };
        }
    }

    fn term(self: *LevelParser) i64 {
        self.skip();
        if (self.pos >= self.src.len) {
            self.ok = false;
            return 0;
        }
        const ch = self.src[self.pos];
        if (ch == '~') {
            self.pos += 1;
            return ~self.term();
        }
        if (ch == '(') {
            self.pos += 1;
            const inner = self.expr();
            self.skip();
            if (self.pos < self.src.len and self.src[self.pos] == ')') self.pos += 1 else self.ok = false;
            return inner;
        }
        const start = self.pos;
        while (self.pos < self.src.len and (std.ascii.isAlphanumeric(self.src[self.pos]) or self.src[self.pos] == '_')) self.pos += 1;
        const word = self.src[start..self.pos];
        if (word.len == 0) {
            self.ok = false;
            return 0;
        }
        if (std.fmt.parseInt(i64, word, 10)) |n| return n else |_| {}
        for (error_levels) |level| if (std.mem.eql(u8, level.name, word)) return level.value;
        self.ok = false;
        return 0;
    }
};

fn errorLevelExpression(raw: []const u8) ?i64 {
    if (std.mem.indexOf(u8, raw, "E_") == null) return null;
    var p = LevelParser{ .src = raw };
    const v = p.expr();
    if (!p.ok or p.pos != raw.len) return null;
    return v;
}

// extension=name resolves like php: a bare name lives in extension_dir (or
// next to the ini file) and gets the platform suffix
fn loadExtensionDirective(value: []const u8) void {
    if (value.len == 0) return;
    const has_dir = std.mem.indexOfScalar(u8, value, '/') != null;
    const suffix: []const u8 = switch (@import("builtin").os.tag) {
        .macos, .ios => ".dylib",
        .windows => ".dll",
        else => ".so",
    };
    const with_suffix = if (std.mem.indexOfScalar(u8, value, '.') == null) std.mem.concat(persistent(), u8, &.{ value, suffix }) catch fail("out of memory", .{}) else value;
    if (has_dir) return extension.loadDynamic(with_suffix);
    const dir = extension_dir orelse if (loaded_file) |f| std.fs.path.dirname(f) orelse "." else ".";
    const full = std.fs.path.join(persistent(), &.{ dir, with_suffix }) catch fail("out of memory", .{});
    extension.loadDynamic(full);
}

// seed the request layer and mirror the directives the VM keeps as state;
// runs at the top of every request, after reset cleared the previous one
pub fn applyToVm(vm: *VM) RuntimeError!void {
    for (directives.items) |d| {
        try vm.ini_settings.put(vm.allocator, d.name, d.value);
        if (std.mem.eql(u8, d.name, "error_reporting")) {
            vm.error_reporting_level = std.fmt.parseInt(i64, std.mem.trim(u8, d.value, " \t"), 10) catch vm.error_reporting_level;
        } else if (std.mem.eql(u8, d.name, "date.timezone")) {
            if (d.value.len > 0) vm.default_tz_name = d.value;
        } else if (std.mem.eql(u8, d.name, "max_execution_time")) {
            vm.setExecutionLimit(std.fmt.parseInt(i64, std.mem.trim(u8, d.value, " \t"), 10) catch 0);
        }
    }
}

test "ini values are cooked the way php cooks them" {
    try std.testing.expectEqualStrings("1", cook("On"));
    try std.testing.expectEqualStrings("", cook("Off"));
    try std.testing.expectEqualStrings("America/New_York", cook("\"America/New_York\""));
    try std.testing.expectEqualStrings("22527", cook("E_ALL & ~E_DEPRECATED"));
    try std.testing.expectEqualStrings("22519", cook("E_ALL & ~(E_NOTICE | E_DEPRECATED)"));
    try std.testing.expectEqualStrings("E_ALL &", cook("E_ALL &"));
    try std.testing.expectEqualStrings("E_ALL)", cook("E_ALL)"));
    try std.testing.expectEqualStrings("(E_ALL", cook("(E_ALL"));
    try std.testing.expectEqualStrings("256M", cook("256M"));
}

test "a semicolon outside quotes starts a comment" {
    try std.testing.expectEqualStrings("a = b", stripComment("a = b ; note"));
    try std.testing.expectEqualStrings("a = \"x;y\"", stripComment("a = \"x;y\""));
}
