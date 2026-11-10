// php's csv reader and writer (ext/standard/file.c php_fgetcsv and
// php_fputcsv), shared by fgetcsv, fputcsv, str_getcsv and SplFileObject
const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const NativeContext = vm_mod.NativeContext;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const filesystem = @import("filesystem.zig");
const types = @import("types.zig");
const coerceToString = @import("strings.zig").coerceToString;
const formatFloat = @import("output.zig").formatFloat;

const RuntimeError = error{ RuntimeError, OutOfMemory };

const e_warning = 2;
const e_deprecated = 8192;

// PHP_CSV_NO_ESCAPE: an empty $escape turns escaping off
pub const no_escape: i32 = -1;

const mblen = @import("locale.zig").mblen;

// the character length php's loops step by at buf[pos] (a nul is one byte)
fn incLen(buf: []const u8, pos: usize, limit: usize) i32 {
    if (pos >= limit) return 0;
    if (buf[pos] == 0) return 1;
    return mblen(buf[pos..limit]);
}

fn isSpace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == 0x0b or c == 0x0c;
}

// php_fgetcsv_lookup_trailing_spaces: where the line ending (\n, \r or
// \r\n) at the end of buf starts
fn lookupTrailingSpaces(buf: []const u8) usize {
    var last: [2]u8 = .{ 0, 0 };
    var pos: usize = 0;
    while (pos < buf.len) {
        var inc = if (buf[pos] == 0) 1 else mblen(buf[pos..]);
        switch (inc) {
            -2, -1 => inc = 1,
            0 => break,
            else => {
                last[0] = last[1];
                last[1] = buf[pos];
            },
        }
        pos += @intCast(inc);
    }
    switch (last[1]) {
        '\n' => return if (last[0] == '\r') pos - 2 else pos - 1,
        '\r' => return pos - 1,
        else => return pos,
    }
}

// where an enclosed field that runs past the end of a line gets its next
// line from: a stream, or nothing for str_getcsv
pub const LineSource = struct {
    ctx: *NativeContext,
    stream: *PhpObject,

    fn next(self: LineSource) RuntimeError!?[]u8 {
        return filesystem.streamReadLine(self.ctx, self.stream, std.math.maxInt(usize));
    }
};

// a line held with two nul bytes past its end: php reads the terminating
// nul of its buffer, and one byte beyond it in one path (gh-12151)
const Line = struct {
    bytes: []u8,
    len: usize,

    fn init(ctx: *NativeContext, data: []const u8) RuntimeError!Line {
        const bytes = try ctx.allocator.alloc(u8, data.len + 2);
        @memcpy(bytes[0..data.len], data);
        bytes[data.len] = 0;
        bytes[data.len + 1] = 0;
        return .{ .bytes = bytes, .len = data.len };
    }

    fn at(self: Line, pos: usize) u8 {
        return if (pos < self.bytes.len) self.bytes[pos] else 0;
    }
};

// php_fgetcsv: the fields of the record starting at first_line, reading
// further lines from source while an enclosure is open. null for a blank
// line (callers turn it into [null])
pub fn parse(ctx: *NativeContext, source: ?LineSource, delimiter: u8, enclosure: u8, escape: i32, first_line: []const u8) RuntimeError!?*PhpArray {
    const a = ctx.allocator;
    @import("locale.zig").mbReset();
    var line = try Line.init(ctx, first_line);
    defer a.free(line.bytes);

    var bptr: usize = 0;
    var limit = lookupTrailingSpaces(line.bytes[0..line.len]);
    var line_end = limit;
    var line_end_len = line.len - limit;

    var temp = std.ArrayListUnmanaged(u8).empty;
    defer temp.deinit(a);

    const values = try ctx.createArray();
    errdefer ctx.vm.discardOrphan(.{ .array = values });

    var first_field = true;
    var inc_len: i32 = 0;
    while (true) {
        temp.clearRetainingCapacity();

        inc_len = incLen(line.bytes, bptr, limit);
        if (inc_len == 1) {
            var tmp = bptr;
            while (line.at(tmp) != delimiter and isSpace(line.at(tmp))) tmp += 1;
            if (line.at(tmp) == enclosure and tmp < limit) bptr = tmp;
        }

        if (first_field and bptr == line_end) {
            ctx.vm.discardOrphan(.{ .array = values });
            return null;
        }
        first_field = false;

        var comp_end: usize = 0;
        if (inc_len != 0 and line.at(bptr) == enclosure) {
            // an enclosed field
            var state: u8 = 0;
            bptr += 1;
            var hunk_begin = bptr;

            enclosed: while (true) {
                switch (inc_len) {
                    0 => switch (state) {
                        2 => {
                            try temp.appendSlice(a, line.bytes[hunk_begin .. bptr - 1]);
                            hunk_begin = bptr;
                            break :enclosed;
                        },
                        else => {
                            if (state == 1) {
                                try temp.appendSlice(a, line.bytes[hunk_begin..bptr]);
                                hunk_begin = bptr;
                            }
                            if (hunk_begin != line_end) {
                                try temp.appendSlice(a, line.bytes[hunk_begin..bptr]);
                                hunk_begin = bptr;
                            }
                            // the line end belongs to the field
                            try temp.appendSlice(a, line.bytes[line_end .. line_end + line_end_len]);

                            const next_line: ?[]u8 = if (source) |s| try s.next() else null;
                            const more = next_line orelse {
                                // an unterminated enclosure takes the rest of the data
                                if (bptr > limit) {
                                    if (hunk_begin == bptr) hunk_begin -= 1;
                                    bptr -= 1;
                                }
                                break :enclosed;
                            };
                            defer a.free(more);
                            const replacement = try Line.init(ctx, more);
                            a.free(line.bytes);
                            line = replacement;
                            bptr = 0;
                            hunk_begin = 0;
                            limit = lookupTrailingSpaces(line.bytes[0..line.len]);
                            line_end = limit;
                            line_end_len = line.len - limit;
                            state = 0;
                        },
                    },
                    -2, -1, 1 => switch (state) {
                        1 => {
                            // escaped
                            bptr += 1;
                            state = 0;
                        },
                        2 => {
                            if (line.at(bptr) != enclosure) {
                                // the closing enclosure
                                try temp.appendSlice(a, line.bytes[hunk_begin .. bptr - 1]);
                                hunk_begin = bptr;
                                break :enclosed;
                            }
                            // a doubled enclosure
                            try temp.appendSlice(a, line.bytes[hunk_begin..bptr]);
                            bptr += 1;
                            hunk_begin = bptr;
                            state = 0;
                        },
                        else => {
                            if (line.at(bptr) == enclosure) {
                                state = 2;
                            } else if (escape != no_escape and line.at(bptr) == @as(u8, @intCast(escape))) {
                                state = 1;
                            }
                            bptr += 1;
                        },
                    },
                    else => switch (state) {
                        2 => {
                            try temp.appendSlice(a, line.bytes[hunk_begin .. bptr - 1]);
                            hunk_begin = bptr;
                            break :enclosed;
                        },
                        1 => {
                            bptr += @intCast(inc_len);
                            try temp.appendSlice(a, line.bytes[hunk_begin..bptr]);
                            hunk_begin = bptr;
                            state = 0;
                        },
                        else => bptr += @intCast(inc_len),
                    },
                }
                inc_len = incLen(line.bytes, bptr, limit);
            }

            // what follows the closing enclosure up to the delimiter
            while (true) {
                switch (inc_len) {
                    0 => break,
                    -2, -1 => {
                        inc_len = 1;
                        if (line.at(bptr) == delimiter) break;
                    },
                    1 => if (line.at(bptr) == delimiter) break,
                    else => {},
                }
                bptr += @intCast(inc_len);
                inc_len = incLen(line.bytes, bptr, limit);
            }
            try temp.appendSlice(a, line.bytes[hunk_begin..bptr]);
            bptr += @intCast(inc_len);
            comp_end = temp.items.len;
        } else {
            // a field without enclosure
            const hunk_begin = bptr;
            while (true) {
                switch (inc_len) {
                    0 => break,
                    -2, -1 => {
                        inc_len = 1;
                        if (line.at(bptr) == delimiter) break;
                    },
                    1 => if (line.at(bptr) == delimiter) break,
                    else => {},
                }
                bptr += @intCast(inc_len);
                inc_len = incLen(line.bytes, bptr, limit);
            }
            try temp.appendSlice(a, line.bytes[hunk_begin..bptr]);
            comp_end = lookupTrailingSpaces(temp.items);
            if (line.at(bptr) == delimiter) bptr += 1;
        }

        try values.appendCopiedString(a, temp.items[0..comp_end]);
        if (inc_len <= 0) break;
    }
    return values;
}

// php_bc_fgetcsv_empty_line: a blank line reads as [null]
fn emptyLine(ctx: *NativeContext) RuntimeError!*PhpArray {
    const values = try ctx.createArray();
    try values.append(ctx.allocator, .null);
    return values;
}

fn parseOrEmpty(ctx: *NativeContext, source: ?LineSource, delimiter: u8, enclosure: u8, escape: i32, line: []const u8) RuntimeError!*PhpArray {
    return (try parse(ctx, source, delimiter, enclosure, escape, line)) orelse try emptyLine(ctx);
}

// php_fputcsv: one record, fields enclosed where they need it, ending in eol
pub fn format(ctx: *NativeContext, out: *std.ArrayListUnmanaged(u8), fields: *PhpArray, delimiter: u8, enclosure: u8, escape: i32, eol: ?[]const u8) RuntimeError!void {
    const a = ctx.allocator;
    var scratch = std.ArrayListUnmanaged(u8).empty;
    defer scratch.deinit(a);
    const count = fields.entries.items.len;
    for (fields.entries.items, 0..) |entry, i| {
        scratch.clearRetainingCapacity();
        const field: []const u8 = switch (entry.value) {
            .string => |s| s.bytes(),
            .object => |o| try ctx.vm.objectToString(o),
            else => |v| blk: {
                if (v == .array) try ctx.vm.emitWarning("Array to string conversion");
                try v.format(&scratch, a);
                break :blk scratch.items;
            },
        };
        const needs_enclosure = std.mem.indexOfScalar(u8, field, delimiter) != null or
            std.mem.indexOfScalar(u8, field, enclosure) != null or
            (escape != no_escape and std.mem.indexOfScalar(u8, field, @intCast(escape)) != null) or
            std.mem.indexOfAny(u8, field, "\n\r\t ") != null;
        if (needs_enclosure) {
            try out.append(a, enclosure);
            var escaped = false;
            for (field) |c| {
                if (escape != no_escape and c == @as(u8, @intCast(escape))) {
                    escaped = true;
                } else if (!escaped and c == enclosure) {
                    try out.append(a, enclosure);
                } else {
                    escaped = false;
                }
                try out.append(a, c);
            }
            try out.append(a, enclosure);
        } else {
            try out.appendSlice(a, field);
        }
        if (i + 1 != count) try out.append(a, delimiter);
    }
    try out.appendSlice(a, eol orelse "\n");
}

// php's parameter parsing for these functions: weak-mode coercion of
// scalars, or a TypeError in strict mode and for what cannot convert
const Params = struct {
    ctx: *NativeContext,
    func: []const u8,
    args: []const Value,
    names: []const []const u8,

    fn given(self: Params, index: usize) bool {
        return index < self.args.len;
    }

    fn typeError(self: Params, index: usize, expected: []const u8) RuntimeError {
        const msg = try std.fmt.allocPrint(self.ctx.allocator, "{s}(): Argument #{d} (${s}) must be of type {s}, {s} given", .{ self.func, index + 1, self.names[index], expected, types.phpTypeName(self.args[index]) });
        defer self.ctx.allocator.free(msg);
        try self.ctx.vm.setPendingException("TypeError", msg);
        return error.RuntimeError;
    }

    fn valueError(self: Params, index: usize, comptime fmt: []const u8, fmt_args: anytype) RuntimeError {
        const detail = try std.fmt.allocPrint(self.ctx.allocator, fmt, fmt_args);
        defer self.ctx.allocator.free(detail);
        const msg = try std.fmt.allocPrint(self.ctx.allocator, "{s}(): Argument #{d} (${s}) {s}", .{ self.func, index + 1, self.names[index], detail });
        defer self.ctx.allocator.free(msg);
        try self.ctx.vm.setPendingException("ValueError", msg);
        return error.RuntimeError;
    }

    fn raise(self: Params, level: i64, comptime fmt: []const u8, fmt_args: anytype) RuntimeError!void {
        const msg = try std.fmt.allocPrint(self.ctx.allocator, fmt, fmt_args);
        defer self.ctx.allocator.free(msg);
        try self.ctx.vm.raiseError(level, msg);
        if (self.ctx.vm.pending_exception != null) return error.RuntimeError;
    }

    // a string parameter; null when it was not passed
    fn string(self: Params, index: usize) RuntimeError!?[]const u8 {
        return self.typedString(index, "string");
    }

    // a ?string parameter; null when it was not passed or is null
    fn optionalString(self: Params, index: usize) RuntimeError!?[]const u8 {
        if (!self.given(index)) return null;
        if (self.args[index] == .null or self.args[index] == .undef) return null;
        return self.typedString(index, "?string");
    }

    fn typedString(self: Params, index: usize, expected: []const u8) RuntimeError!?[]const u8 {
        if (!self.given(index)) return null;
        const v = self.args[index];
        if (v == .string and !std.mem.startsWith(u8, v.string.bytes(), "__closure_")) return v.string.bytes();
        const strict = self.ctx.vm.topFrameStrict();
        switch (v) {
            .null, .undef => {
                if (strict) return self.typeError(index, expected);
                try self.raise(e_deprecated, "{s}(): Passing null to parameter #{d} (${s}) of type string is deprecated", .{ self.func, index + 1, self.names[index] });
                return "";
            },
            .int, .float, .bool => {
                if (strict) return self.typeError(index, expected);
                return try coerceToString(self.ctx, v);
            },
            .object => |o| {
                if (!self.ctx.vm.hasMethod(o.class_name, "__toString")) return self.typeError(index, expected);
                return try self.ctx.vm.objectToString(o);
            },
            else => return self.typeError(index, expected),
        }
    }

    // a ?int parameter; null when it was not passed or is null
    fn optionalInt(self: Params, index: usize) RuntimeError!?i64 {
        if (!self.given(index)) return null;
        const v = self.args[index];
        if (v == .int) return v.int;
        if (v == .null or v == .undef) return null;
        if (self.ctx.vm.topFrameStrict()) return self.typeError(index, "?int");
        switch (v) {
            .bool => |b| return @intFromBool(b),
            .float => |f| return try self.floatToInt(index, f, null),
            .string => |s| {
                const bytes = s.bytes();
                const trimmed = std.mem.trim(u8, bytes, " \t\n\r\x0b\x0c");
                if (Value.isNumericString(bytes)) {
                    if (std.fmt.parseInt(i64, trimmed, 10)) |i| return i else |_| {}
                    return try self.floatToInt(index, Value.toFloat(v), bytes);
                }
                // a leading number with trailing data is taken with a warning
                const prefix = numericPrefix(bytes);
                if (prefix.len == 0) return self.typeError(index, "?int");
                try self.raise(e_warning, "A non-numeric value encountered", .{});
                const pv: Value = .{ .string = Value.String.borrowed(prefix) };
                if (std.fmt.parseInt(i64, std.mem.trim(u8, prefix, " \t\n\r\x0b\x0c"), 10)) |i| return i else |_| {}
                return try self.floatToInt(index, Value.toFloat(pv), null);
            },
            else => return self.typeError(index, "?int"),
        }
    }

    fn floatToInt(self: Params, index: usize, f: f64, from_string: ?[]const u8) RuntimeError!i64 {
        if (!Value.floatFitsInt(f)) return self.typeError(index, "?int");
        if (f != @trunc(f)) {
            if (from_string) |s| {
                try self.raise(e_deprecated, "Implicit conversion from float-string \"{s}\" to int loses precision", .{s});
            } else {
                var tmp: [64]u8 = undefined;
                try self.raise(e_deprecated, "Implicit conversion from float {s} to int loses precision", .{formatFloat(&tmp, f)});
            }
        }
        return @intFromFloat(@trunc(f));
    }

    // an array parameter
    fn array(self: Params, index: usize) RuntimeError!*PhpArray {
        const v: Value = if (self.given(index)) self.args[index] else .null;
        if (v == .array) return v.array;
        return self.typeError(index, "array");
    }
};

// the leading numeric part of a string ("12" of "12abc")
fn numericPrefix(s: []const u8) []const u8 {
    var i: usize = 0;
    while (i < s.len and (s[i] == ' ' or s[i] == '\t' or s[i] == '\n' or s[i] == '\r' or s[i] == 0x0b or s[i] == 0x0c)) i += 1;
    var end = s.len;
    while (end > i) : (end -= 1) {
        if (Value.isNumericString(s[0..end])) return s[0..end];
    }
    return "";
}

// a single-character separator or enclosure argument, checked after all
// the arguments were parsed
fn singleChar(p: Params, index: usize, given: ?[]const u8, default: u8) RuntimeError!u8 {
    const s = given orelse return default;
    if (s.len != 1) return p.valueError(index, "must be a single character", .{});
    return s[0];
}

// php_csv_handle_escape_argument: the escape character, no_escape for an
// empty string, or the backslash with a deprecation when none was passed
fn escapeArgument(p: Params, index: usize, given: ?[]const u8) RuntimeError!i32 {
    const s = given orelse {
        try p.raise(e_deprecated, "{s}(): the $escape parameter must be provided as its default value will change", .{p.func});
        return '\\';
    };
    if (s.len > 1) return p.valueError(index, "must be empty or a single character", .{});
    if (s.len == 0) return no_escape;
    return s[0];
}

// a csv control character as php's getCsvControl shows it (a nul reads as
// an empty string)
fn charString(c: u8) []const u8 {
    const table = comptime blk: {
        var t: [256][1]u8 = undefined;
        for (0..256) |i| t[i] = .{@intCast(i)};
        break :blk t;
    };
    return if (c == 0) "" else &table[c];
}

const max_length: i64 = std.math.maxInt(i64) - 1;

pub fn fgetcsv(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const stream = try filesystem.streamArg(ctx, args, .{ .func = "fgetcsv" });
    const p = Params{ .ctx = ctx, .func = "fgetcsv", .args = args, .names = &.{ "stream", "length", "separator", "enclosure", "escape" } };
    var length = try p.optionalInt(1);
    const delimiter_arg = try p.string(2);
    const enclosure_arg = try p.string(3);
    const escape_arg = try p.string(4);
    const delimiter = try singleChar(p, 2, delimiter_arg, ',');
    const enclosure = try singleChar(p, 3, enclosure_arg, '"');
    const escape = try escapeArgument(p, 4, escape_arg);

    if (length != null and length.? == 0) length = null;
    if (length) |len| if (len < 0 or len > max_length) return p.valueError(1, "must be between 0 and {d}", .{max_length});

    const max: usize = if (length) |len| @intCast(len) else std.math.maxInt(usize);
    // php allocates the whole line buffer up front, so memory_limit refuses
    // a length it cannot hold before anything is read
    if (length) |len| ctx.allocator.free(try ctx.allocator.alloc(u8, @as(usize, @intCast(len)) + 1));
    const line = (try filesystem.streamReadLine(ctx, stream, max)) orelse return NativeResult.scalar(.{ .bool = false });
    defer ctx.allocator.free(line);
    const values = try parseOrEmpty(ctx, .{ .ctx = ctx, .stream = stream }, delimiter, enclosure, escape, line);
    return NativeResult.borrowed(.{ .array = values });
}

pub fn fputcsv(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const stream = try filesystem.streamArg(ctx, args, .{ .func = "fputcsv" });
    const p = Params{ .ctx = ctx, .func = "fputcsv", .args = args, .names = &.{ "stream", "fields", "separator", "enclosure", "escape", "eol" } };
    const fields = try p.array(1);
    const delimiter_arg = try p.string(2);
    const enclosure_arg = try p.string(3);
    const escape_arg = try p.string(4);
    const eol = try p.optionalString(5);
    const delimiter = try singleChar(p, 2, delimiter_arg, ',');
    const enclosure = try singleChar(p, 3, enclosure_arg, '"');
    const escape = try escapeArgument(p, 4, escape_arg);
    return write(ctx, stream, fields, delimiter, enclosure, escape, eol);
}

fn write(ctx: *NativeContext, stream: *PhpObject, fields: *PhpArray, delimiter: u8, enclosure: u8, escape: i32, eol: ?[]const u8) RuntimeError!NativeResult {
    var out = std.ArrayListUnmanaged(u8).empty;
    defer out.deinit(ctx.allocator);
    try format(ctx, &out, fields, delimiter, enclosure, escape, eol);
    const written = (try filesystem.streamWrite(ctx, stream, out.items)) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(written) });
}

pub fn str_getcsv(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Params{ .ctx = ctx, .func = "str_getcsv", .args = args, .names = &.{ "string", "separator", "enclosure", "escape" } };
    const string = (try p.string(0)) orelse "";
    const delimiter_arg = try p.string(1);
    const enclosure_arg = try p.string(2);
    const escape_arg = try p.string(3);
    const delimiter = try singleChar(p, 1, delimiter_arg, ',');
    const enclosure = try singleChar(p, 2, enclosure_arg, '"');
    const escape = try escapeArgument(p, 3, escape_arg);
    const values = try parseOrEmpty(ctx, null, delimiter, enclosure, escape, string);
    return NativeResult.borrowed(.{ .array = values });
}

// SplFileObject's csv state: separator, enclosure, escape (no_escape when
// empty) and whether the escape is still the default one
pub const Control = struct {
    delimiter: u8 = ',',
    enclosure: u8 = '"',
    escape: i32 = '\\',
    escape_default: bool = true,

    pub fn load(obj: *PhpObject) Control {
        var c = Control{};
        const v = obj.get("__sfo_csv");
        if (v != .array) return c;
        const arr = v.array;
        const d = arr.get(.{ .int = 0 });
        if (d == .string and d.string.bytes().len == 1) c.delimiter = d.string.bytes()[0];
        const e = arr.get(.{ .int = 1 });
        if (e == .string and e.string.bytes().len == 1) c.enclosure = e.string.bytes()[0];
        const x = arr.get(.{ .int = 2 });
        if (x == .string) c.escape = if (x.string.bytes().len == 0) no_escape else x.string.bytes()[0];
        const dflt = arr.get(.{ .int = 3 });
        c.escape_default = !(dflt == .bool and !dflt.bool);
        return c;
    }

    pub fn store(self: Control, ctx: *NativeContext, obj: *PhpObject) RuntimeError!void {
        const arr = try ctx.createArray();
        const delimiter = [_]u8{self.delimiter};
        const enclosure = [_]u8{self.enclosure};
        const escape = [_]u8{if (self.escape == no_escape) 0 else @intCast(self.escape)};
        try arr.appendCopiedString(ctx.allocator, &delimiter);
        try arr.appendCopiedString(ctx.allocator, &enclosure);
        try arr.appendCopiedString(ctx.allocator, if (self.escape == no_escape) "" else &escape);
        try arr.append(ctx.allocator, .{ .bool = self.escape_default });
        try obj.set(ctx.allocator, "__sfo_csv", .{ .array = arr });
    }
};

// spl_csv_enclosure_param_handling
fn splEscape(p: Params, index: usize, given: ?[]const u8, control: Control) RuntimeError!i32 {
    if (given != null) return escapeArgument(p, index, given);
    if (control.escape_default) {
        try p.raise(e_deprecated, "{s}(): the $escape parameter must be provided, as its default value will change, either explicitly or via SplFileObject::setCsvControl()", .{p.func});
    }
    return control.escape;
}

const flag_drop_new_line: i64 = 1;
const flag_skip_empty: i64 = 4;
const flag_read_csv: i64 = 8;

// whether the object holds a current line (php's current_line or
// current_zval); a read then counts as moving to the next line
pub fn hasCurrent(obj: *PhpObject) bool {
    const v = obj.get("__sfo_current");
    return !(v == .null or (v == .bool and !v.bool));
}

// spl_filesystem_file_read_csv: the next record of the file, skipping lines
// that are empty when SKIP_EMPTY is set (with DROP_NEW_LINE, a bare line
// ending counts as empty). it becomes the current element: the record under
// READ_CSV, the line it started on otherwise. null at the end of the file
pub fn splReadCsv(ctx: *NativeContext, obj: *PhpObject, stream: *PhpObject, delimiter: u8, enclosure: u8, escape: i32) RuntimeError!?*PhpArray {
    const flags = splFlags(obj);
    const max = splMaxLineLen(obj);
    var counts = hasCurrent(obj);
    while (true) {
        try obj.set(ctx.allocator, "__sfo_current", .null);
        const eof = try ctx.vm.callByName("feof", &.{.{ .resource = stream }});
        if (eof == .bool and eof.bool) return null;
        const line = (try filesystem.streamReadLine(ctx, stream, if (max > 0) max else std.math.maxInt(usize))) orelse try ctx.allocator.alloc(u8, 0);
        defer ctx.allocator.free(line);
        if (counts) try obj.set(ctx.allocator, "__sfo_line", .{ .int = lineNumber(obj) + 1 });
        counts = true;
        const empty = line.len == 0 or (flags & flag_drop_new_line != 0 and (std.mem.eql(u8, line, "\n") or std.mem.eql(u8, line, "\r\n")));
        if (flags & flag_skip_empty != 0 and empty) continue;
        const values = try parseOrEmpty(ctx, .{ .ctx = ctx, .stream = stream }, delimiter, enclosure, escape, line);
        if (flags & flag_read_csv != 0) {
            try obj.set(ctx.allocator, "__sfo_current", .{ .array = values });
        } else {
            const str = try Value.String.create(ctx.allocator, line);
            defer str.release();
            try obj.set(ctx.allocator, "__sfo_current", .{ .string = str });
        }
        return values;
    }
}

fn splThis(ctx: *NativeContext) ?*PhpObject {
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

fn splStream(ctx: *NativeContext, obj: *PhpObject) RuntimeError!*PhpObject {
    const fh = obj.get("__sfo_fh");
    if (fh == .resource) return fh.resource;
    try ctx.vm.setPendingException("Error", "Object not initialized");
    return error.RuntimeError;
}

fn splFlags(obj: *PhpObject) i64 {
    const v = obj.get("__sfo_flags");
    return if (v == .int) v.int else 0;
}

fn splMaxLineLen(obj: *PhpObject) usize {
    const v = obj.get("__sfo_max");
    return if (v == .int and v.int > 0) @intCast(v.int) else 0;
}

pub fn splFgetcsv(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = splThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const p = Params{ .ctx = ctx, .func = "SplFileObject::fgetcsv", .args = args, .names = &.{ "separator", "enclosure", "escape" } };
    const control = Control.load(obj);
    const delimiter_arg = try p.string(0);
    const enclosure_arg = try p.string(1);
    const escape_arg = try p.string(2);
    const stream = try splStream(ctx, obj);
    const delimiter = try singleChar(p, 0, delimiter_arg, control.delimiter);
    const enclosure = try singleChar(p, 1, enclosure_arg, control.enclosure);
    const escape = try splEscape(p, 2, escape_arg, control);
    const values = (try splReadCsv(ctx, obj, stream, delimiter, enclosure, escape)) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.borrowed(.{ .array = values });
}

fn lineNumber(obj: *PhpObject) i64 {
    const v = obj.get("__sfo_line");
    return if (v == .int) v.int else 0;
}

pub fn splFputcsv(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = splThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const p = Params{ .ctx = ctx, .func = "SplFileObject::fputcsv", .args = args, .names = &.{ "fields", "separator", "enclosure", "escape", "eol" } };
    const control = Control.load(obj);
    const fields = try p.array(0);
    const delimiter_arg = try p.string(1);
    const enclosure_arg = try p.string(2);
    const escape_arg = try p.string(3);
    const eol = try p.string(4);
    const stream = try splStream(ctx, obj);
    const delimiter = try singleChar(p, 1, delimiter_arg, control.delimiter);
    const enclosure = try singleChar(p, 2, enclosure_arg, control.enclosure);
    const escape = try splEscape(p, 3, escape_arg, control);
    return write(ctx, stream, fields, delimiter, enclosure, escape, eol);
}

pub fn splSetCsvControl(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = splThis(ctx) orelse return NativeResult.scalar(.null);
    const p = Params{ .ctx = ctx, .func = "SplFileObject::setCsvControl", .args = args, .names = &.{ "separator", "enclosure", "escape" } };
    var control = Control.load(obj);
    const delimiter_arg = try p.string(0);
    const enclosure_arg = try p.string(1);
    const escape_arg = try p.string(2);
    const delimiter = try singleChar(p, 0, delimiter_arg, ',');
    const enclosure = try singleChar(p, 1, enclosure_arg, '"');
    const escape = try escapeArgument(p, 2, escape_arg);
    if (escape_arg != null) control.escape_default = false;
    control.delimiter = delimiter;
    control.enclosure = enclosure;
    control.escape = escape;
    try control.store(ctx, obj);
    return NativeResult.scalar(.null);
}

pub fn splGetCsvControl(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = splThis(ctx) orelse return NativeResult.scalar(.null);
    const control = Control.load(obj);
    const arr = try ctx.createArray();
    try arr.appendCopiedString(ctx.allocator, charString(control.delimiter));
    try arr.appendCopiedString(ctx.allocator, charString(control.enclosure));
    try arr.appendCopiedString(ctx.allocator, if (control.escape == no_escape) "" else charString(@intCast(control.escape)));
    return NativeResult.borrowed(.{ .array = arr });
}
