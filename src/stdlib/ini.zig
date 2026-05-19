const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "parse_ini_string", native_parse_ini_string },
    .{ "parse_ini_file", native_parse_ini_file },
};

const ScannerMode = enum(u2) { normal = 0, raw = 1, typed = 2 };

fn native_parse_ini_string(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const input = args[0].string;
    const process_sections = if (args.len >= 2) Value.isTruthy(args[1]) else false;
    const mode = parseMode(if (args.len >= 3) args[2] else .{ .int = 0 });
    return parseIni(ctx, input, process_sections, mode);
}

fn native_parse_ini_file(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const path = args[0].string;
    const content = std.fs.cwd().readFileAlloc(ctx.allocator, path, 1024 * 1024 * 64) catch return Value{ .bool = false };
    try ctx.strings.append(ctx.allocator, content);
    const process_sections = if (args.len >= 2) Value.isTruthy(args[1]) else false;
    const mode = parseMode(if (args.len >= 3) args[2] else .{ .int = 0 });
    return parseIni(ctx, content, process_sections, mode);
}

fn parseMode(v: Value) ScannerMode {
    const i = Value.toInt(v);
    return switch (i) {
        1 => .raw,
        2 => .typed,
        else => .normal,
    };
}

fn parseIni(ctx: *NativeContext, input: []const u8, process_sections: bool, mode: ScannerMode) RuntimeError!Value {
    var result = try ctx.createArray();
    var current_section: ?*PhpArray = null;

    var pos: usize = 0;
    while (pos < input.len) {
        const line_start = pos;
        while (pos < input.len and input[pos] != '\n') pos += 1;
        var line = input[line_start..pos];
        if (pos < input.len) pos += 1;

        // strip \r
        if (line.len > 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];

        line = trimSpaces(line);
        if (line.len == 0 or line[0] == ';' or line[0] == '#') continue;

        // section header
        if (line[0] == '[') {
            if (std.mem.indexOfScalar(u8, line, ']')) |end| {
                if (process_sections) {
                    const section_name = line[1..end];
                    const section_arr = try ctx.createArray();
                    try result.set(ctx.allocator, .{ .string = section_name }, .{ .array = section_arr });
                    current_section = section_arr;
                }
            } else {
                return .{ .bool = false };
            }
            continue;
        }

        // key = value
        if (std.mem.indexOfScalar(u8, line, '=')) |eq_pos| {
            const raw_key = trimSpaces(line[0..eq_pos]);
            const raw_val = trimSpaces(if (eq_pos + 1 < line.len) line[eq_pos + 1 ..] else "");

            const value = processValue(ctx, raw_val, mode);
            const target = if (process_sections and current_section != null) current_section.? else result;

            if (isArrayKey(raw_key)) {
                try setArrayKey(ctx, target, raw_key, value);
            } else {
                try target.set(ctx.allocator, .{ .string = raw_key }, value);
            }
        }
    }

    return .{ .array = result };
}

fn processValue(ctx: *NativeContext, raw: []const u8, mode: ScannerMode) Value {
    if (raw.len == 0) return .{ .string = "" };

    // strip quotes
    if (raw.len >= 2 and ((raw[0] == '"' and raw[raw.len - 1] == '"') or (raw[0] == '\'' and raw[raw.len - 1] == '\''))) {
        return .{ .string = raw[1 .. raw.len - 1] };
    }

    // strip inline comments (unquoted values only)
    var val = raw;
    if (std.mem.indexOfScalar(u8, val, ';')) |sc| {
        if (sc > 0 and val[sc - 1] == ' ') {
            val = trimSpaces(val[0 .. sc - 1]);
        }
    }

    if (mode == .raw) return .{ .string = val };

    // normal + typed modes: substitute bare PHP constants (PHP_INT_MAX,
    // user-defined via define(), etc.) - identifier-shaped values match
    // against vm.php_constants then vm.user_constants
    if (looksLikeIdentifier(val)) {
        if (ctx.vm.php_constants.get(val)) |cv| {
            if (mode == .typed) return cv;
            // normal mode: coerce to string representation
            return constToString(ctx, cv);
        }
        if (ctx.vm.user_constants.contains(val)) {
            if (ctx.vm.php_constants.get(val)) |cv| {
                if (mode == .typed) return cv;
                return constToString(ctx, cv);
            }
        }
    }

    if (mode == .typed) {
        if (isBoolTrue(val)) return .{ .bool = true };
        if (isBoolFalse(val)) return .{ .bool = false };
        if (isNull(val)) return .null;
        if (parseInteger(val)) |i| return .{ .int = i };
        if (parseFloat(val)) |f| return .{ .float = f };
        return .{ .string = val };
    }

    // normal mode: booleans become "1"/""
    if (isBoolTrue(val)) return .{ .string = "1" };
    if (isBoolFalse(val)) return .{ .string = "" };
    return .{ .string = val };
}

fn looksLikeIdentifier(s: []const u8) bool {
    if (s.len == 0) return false;
    const c = s[0];
    if (!((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or c == '_')) return false;
    for (s[1..]) |ch| {
        const ok = (ch >= 'A' and ch <= 'Z') or (ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9') or ch == '_';
        if (!ok) return false;
    }
    return true;
}

fn constToString(ctx: *NativeContext, v: Value) Value {
    switch (v) {
        .string => return v,
        .int => |i| {
            const s = std.fmt.allocPrint(ctx.allocator, "{d}", .{i}) catch return .{ .string = "" };
            ctx.strings.append(ctx.allocator, s) catch {};
            return .{ .string = s };
        },
        .float => |f| {
            const s = std.fmt.allocPrint(ctx.allocator, "{d}", .{f}) catch return .{ .string = "" };
            ctx.strings.append(ctx.allocator, s) catch {};
            return .{ .string = s };
        },
        .bool => |b| return .{ .string = if (b) "1" else "" },
        .null => return .{ .string = "" },
        else => return .{ .string = "" },
    }
}

fn isBoolTrue(s: []const u8) bool {
    return eqlIgnoreCase(s, "true") or eqlIgnoreCase(s, "on") or eqlIgnoreCase(s, "yes");
}

fn isBoolFalse(s: []const u8) bool {
    return eqlIgnoreCase(s, "false") or eqlIgnoreCase(s, "off") or eqlIgnoreCase(s, "no") or
        eqlIgnoreCase(s, "none") or eqlIgnoreCase(s, "null");
}

fn isNull(s: []const u8) bool {
    return eqlIgnoreCase(s, "null") or eqlIgnoreCase(s, "none");
}

fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (std.ascii.toLower(ca) != std.ascii.toLower(cb)) return false;
    }
    return true;
}

fn parseInteger(s: []const u8) ?i64 {
    return std.fmt.parseInt(i64, s, 10) catch null;
}

fn parseFloat(s: []const u8) ?f64 {
    if (std.mem.indexOfScalar(u8, s, '.') == null) return null;
    return std.fmt.parseFloat(f64, s) catch null;
}

fn isArrayKey(key: []const u8) bool {
    return std.mem.indexOf(u8, key, "[") != null;
}

fn setArrayKey(ctx: *NativeContext, target: *PhpArray, key: []const u8, value: Value) RuntimeError!void {
    const bracket = std.mem.indexOfScalar(u8, key, '[') orelse return;
    const base = key[0..bracket];
    const inner_start = bracket + 1;
    const inner_end = std.mem.indexOfScalar(u8, key[inner_start..], ']') orelse return;
    const inner = key[inner_start .. inner_start + inner_end];

    var arr: *PhpArray = undefined;
    const existing = target.get(.{ .string = base });
    if (existing == .array) {
        arr = existing.array;
    } else {
        arr = try ctx.createArray();
        try target.set(ctx.allocator, .{ .string = base }, .{ .array = arr });
    }

    if (inner.len == 0) {
        try arr.append(ctx.allocator, value);
    } else {
        try arr.set(ctx.allocator, .{ .string = inner }, value);
    }
}

fn trimSpaces(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and (s[start] == ' ' or s[start] == '\t')) start += 1;
    var end = s.len;
    while (end > start and (s[end - 1] == ' ' or s[end - 1] == '\t')) end -= 1;
    return s[start..end];
}
