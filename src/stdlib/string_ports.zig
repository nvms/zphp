// string functions ported from php's ext/standard/string.c and
// Zend/zend_builtin_functions.c: argument parsing as php's
// ZEND_PARSE_PARAMETERS does it, and the functions' own edge cases

const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const vm_mod = @import("../runtime/vm.zig");
const array_diff = @import("array_diff.zig");
const array_sort = @import("array_sort.zig");
const strings = @import("strings.zig");
const phpTypeName = @import("types.zig").phpTypeName;
const NativeContext = vm_mod.NativeContext;
const NativeResult = vm_mod.NativeResult;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "trim", native_trim },
    .{ "ltrim", native_ltrim },
    .{ "rtrim", native_rtrim },
    .{ "chop", native_chop },
    .{ "addcslashes", native_addcslashes },
    .{ "stripslashes", native_stripslashes },
    .{ "stripcslashes", native_stripcslashes },
    .{ "strtok", native_strtok },
    .{ "strtr", native_strtr },
    .{ "str_replace", native_str_replace },
    .{ "str_ireplace", native_str_ireplace },
    .{ "implode", native_implode },
    .{ "join", native_join },
    .{ "strnatcmp", native_strnatcmp },
    .{ "strnatcasecmp", native_strnatcasecmp },
    .{ "strncmp", native_strncmp },
    .{ "strncasecmp", native_strncasecmp },
    .{ "substr_count", native_substr_count },
    .{ "substr_compare", native_substr_compare },
    .{ "strpbrk", native_strpbrk },
    .{ "strrchr", native_strrchr },
    .{ "strstr", native_strstr },
    .{ "strchr", native_strchr },
    .{ "stristr", native_stristr },
    .{ "strpos", native_strpos },
    .{ "stripos", native_stripos },
    .{ "strrpos", native_strrpos },
    .{ "strripos", native_strripos },
    .{ "ucwords", native_ucwords },
    .{ "chunk_split", native_chunk_split },
};

const e_warning = 2;
const e_deprecated = 8192;

fn throwFmt(ctx: *NativeContext, class: []const u8, comptime fmt: []const u8, args: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException(class, msg);
    return error.RuntimeError;
}

pub fn warnFmt(ctx: *NativeContext, comptime fmt: []const u8, args: anytype) RuntimeError!void {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    try ctx.vm.emitWarning(msg);
}

// php_error_docref's E_WARNING: the message after the function's name
pub fn docref(ctx: *NativeContext, func: []const u8, msg: []const u8) RuntimeError!void {
    return warnFmt(ctx, "{s}(): {s}", .{ func, msg });
}

fn isClosure(v: Value) bool {
    return v == .string and std.mem.startsWith(u8, v.string.bytes(), "__closure_");
}

// php's argument parsing for one call: weak-mode coercions, the null
// deprecation, and TypeErrors worded as zend_parse_parameters words them
pub const Args = struct {
    ctx: *NativeContext,
    func: []const u8,
    args: []const Value,

    pub fn init(ctx: *NativeContext, func: []const u8, args: []const Value) Args {
        return .{ .ctx = ctx, .func = func, .args = args };
    }

    fn strict(self: Args) bool {
        return self.ctx.vm.topFrameStrict();
    }

    pub fn has(self: Args, index: usize) bool {
        return index < self.args.len;
    }

    pub fn typeError(self: Args, index: usize, name: []const u8, expected: []const u8) RuntimeError {
        return throwFmt(self.ctx, "TypeError", "{s}(): Argument #{d} (${s}) must be of type {s}, {s} given", .{ self.func, index + 1, name, expected, phpTypeName(self.args[index]) });
    }

    pub fn valueError(self: Args, index: usize, name: []const u8, comptime text: []const u8) RuntimeError {
        return throwFmt(self.ctx, "ValueError", "{s}(): Argument #{d} (${s}) " ++ text, .{ self.func, index + 1, name });
    }

    fn nullDeprecated(self: Args, index: usize, name: []const u8, expected: []const u8) RuntimeError!void {
        const msg = try std.fmt.allocPrint(self.ctx.allocator, "{s}(): Passing null to parameter #{d} (${s}) of type {s} is deprecated", .{ self.func, index + 1, name, expected });
        defer self.ctx.allocator.free(msg);
        try self.ctx.vm.raiseError(e_deprecated, msg);
    }

    // Z_PARAM_STR, typed as `expected` in messages
    pub fn strAs(self: Args, index: usize, name: []const u8, expected: []const u8) RuntimeError![]const u8 {
        const v = self.args[index];
        switch (v) {
            .string => if (!isClosure(v)) return v.string.bytes(),
            .null, .undef => if (!self.strict()) {
                try self.nullDeprecated(index, name, expected);
                return "";
            },
            .int, .float, .bool => if (!self.strict()) return strings.coerceToString(self.ctx, v),
            .object => |o| if (self.ctx.vm.hasMethod(o.class_name, "__toString")) return self.ctx.vm.objectToString(o),
            else => {},
        }
        return self.typeError(index, name, expected);
    }

    pub fn str(self: Args, index: usize, name: []const u8) RuntimeError![]const u8 {
        return self.strAs(index, name, "string");
    }

    pub fn optStr(self: Args, index: usize, name: []const u8, default: []const u8) RuntimeError![]const u8 {
        if (index >= self.args.len) return default;
        return self.str(index, name);
    }

    // Z_PARAM_STR_OR_NULL
    pub fn strOrNull(self: Args, index: usize, name: []const u8) RuntimeError!?[]const u8 {
        if (index >= self.args.len) return null;
        const v = self.args[index];
        if (v == .null or v == .undef) return null;
        return try self.strAs(index, name, "?string");
    }

    pub fn longAs(self: Args, index: usize, name: []const u8, expected: []const u8) RuntimeError!i64 {
        const v = self.args[index];
        switch (v) {
            .int => |i| return i,
            .null, .undef => if (!self.strict()) {
                try self.nullDeprecated(index, name, expected);
                return 0;
            },
            .bool => |b| if (!self.strict()) return @intFromBool(b),
            .float => |f| if (!self.strict()) return self.floatToLong(index, name, expected, f, false),
            .string => |s| if (!self.strict()) {
                const bytes = s.bytes();
                if (Value.isNumericString(bytes) and !isClosure(v)) {
                    const trimmed = std.mem.trim(u8, bytes, " \t\n\r\x0b\x0c");
                    if (std.fmt.parseInt(i64, trimmed, 10)) |i| return i else |_| {}
                    return self.floatToLong(index, name, expected, Value.toFloat(v), true);
                }
            },
            else => {},
        }
        return self.typeError(index, name, expected);
    }

    fn floatToLong(self: Args, index: usize, name: []const u8, expected: []const u8, f: f64, from_string: bool) RuntimeError!i64 {
        if (!Value.floatFitsInt(f)) return self.typeError(index, name, expected);
        if (f != @trunc(f)) {
            const msg = if (from_string)
                try std.fmt.allocPrint(self.ctx.allocator, "Implicit conversion from float-string \"{s}\" to int loses precision", .{self.args[index].string.bytes()})
            else blk: {
                const shown = try self.ctx.vm.transientFormatted(.{ .float = f });
                break :blk try std.fmt.allocPrint(self.ctx.allocator, "Implicit conversion from float {s} to int loses precision", .{shown.bytes()});
            };
            defer self.ctx.allocator.free(msg);
            try self.ctx.vm.raiseError(e_deprecated, msg);
            if (self.ctx.vm.pending_exception != null) return error.RuntimeError;
        }
        return @intFromFloat(@trunc(f));
    }

    pub fn long(self: Args, index: usize, name: []const u8) RuntimeError!i64 {
        return self.longAs(index, name, "int");
    }

    pub fn optLong(self: Args, index: usize, name: []const u8, default: i64) RuntimeError!i64 {
        if (index >= self.args.len) return default;
        return self.long(index, name);
    }

    // Z_PARAM_LONG_OR_NULL
    pub fn longOrNull(self: Args, index: usize, name: []const u8) RuntimeError!?i64 {
        if (index >= self.args.len) return null;
        const v = self.args[index];
        if (v == .null or v == .undef) return null;
        return try self.longAs(index, name, "?int");
    }

    pub fn boolean(self: Args, index: usize, name: []const u8, default: bool) RuntimeError!bool {
        if (index >= self.args.len) return default;
        const v = self.args[index];
        switch (v) {
            .bool => |b| return b,
            .null, .undef => if (!self.strict()) {
                try self.nullDeprecated(index, name, "bool");
                return false;
            },
            .int, .float => if (!self.strict()) return v.isTruthy(),
            .string => if (!self.strict() and !isClosure(v)) return v.isTruthy(),
            else => {},
        }
        return self.typeError(index, name, "bool");
    }

    pub const ArrayOrStr = union(enum) { array: *PhpArray, string: []const u8 };

    // Z_PARAM_ARRAY_HT_OR_STR
    pub fn arrayOrStr(self: Args, index: usize, name: []const u8) RuntimeError!ArrayOrStr {
        const v = self.args[index];
        if (v == .array) return .{ .array = v.array };
        return .{ .string = try self.strAs(index, name, "array|string") };
    }
};

// zval_get_string for an element: the bytes of v as php converts it, kept
// alive by the transient pool or the value itself
fn elementString(ctx: *NativeContext, v_in: Value) RuntimeError![]const u8 {
    const v = v_in;
    switch (v) {
        .string => if (!isClosure(v)) return v.string.bytes(),
        .array => {
            try ctx.vm.emitWarning("Array to string conversion");
            return "Array";
        },
        else => {},
    }
    var buf: [128]u8 = undefined;
    const s = try array_diff.tmpString(ctx, v, &buf);
    defer s.release(ctx);
    return (try ctx.vm.transientBytes(s.bytes)).bytes();
}

fn entryValue(entry: PhpArray.Entry) Value {
    return if (entry.ref) |cell| cell.* else entry.value;
}

// php_charmask: the characters a list names, with a..b ranges; a malformed
// range warns and leaves its dots as plain characters
pub fn charmask(ctx: *NativeContext, func: []const u8, input: []const u8) RuntimeError![256]bool {
    var mask: [256]bool = @splat(false);
    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        const c = input[i];
        if (i + 3 < input.len and input[i + 1] == '.' and input[i + 2] == '.' and input[i + 3] >= c) {
            var x: usize = c;
            while (x <= input[i + 3]) : (x += 1) mask[x] = true;
            i += 3;
        } else if (i + 1 < input.len and input[i] == '.' and input[i + 1] == '.') {
            if (i == 0) {
                try docref(ctx, func, "Invalid '..'-range, no character to the left of '..'");
            } else if (i + 2 >= input.len) {
                try docref(ctx, func, "Invalid '..'-range, no character to the right of '..'");
            } else if (input[i - 1] > input[i + 2]) {
                try docref(ctx, func, "Invalid '..'-range, '..'-range needs to be incrementing");
            } else {
                try docref(ctx, func, "Invalid '..'-range");
            }
        } else {
            mask[c] = true;
        }
    }
    return mask;
}

// php_trim_int: mode 1 left, 2 right, 3 both
fn phpTrim(ctx: *NativeContext, s: []const u8, what: ?[]const u8, mode: u2, func: []const u8) RuntimeError![]const u8 {
    var start: usize = 0;
    var end: usize = s.len;
    if (what) |w| {
        if (w.len == 1) {
            if (mode & 1 != 0) while (start != end and s[start] == w[0]) : (start += 1) {};
            if (mode & 2 != 0) while (start != end and s[end - 1] == w[0]) : (end -= 1) {};
        } else {
            const mask = try charmask(ctx, func, w);
            if (mode & 1 != 0) while (start != end and mask[s[start]]) : (start += 1) {};
            if (mode & 2 != 0) while (start != end and mask[s[end - 1]]) : (end -= 1) {};
        }
    } else {
        const ws = struct {
            fn f(c: u8) bool {
                return c == ' ' or c == '\n' or c == '\r' or c == '\t' or c == 0x0b or c == 0;
            }
        }.f;
        if (mode & 1 != 0) while (start != end and ws(s[start])) : (start += 1) {};
        if (mode & 2 != 0) while (start != end and ws(s[end - 1])) : (end -= 1) {};
    }
    return s[start..end];
}

fn doTrim(ctx: *NativeContext, comptime func: []const u8, args: []const Value, mode: u2) RuntimeError!NativeResult {
    const p = Args.init(ctx, func, args);
    const s = try p.str(0, "string");
    const what: ?[]const u8 = if (p.has(1)) try p.str(1, "characters") else null;
    const trimmed = try phpTrim(ctx, s, what, mode, func);
    if (trimmed.len == s.len and args[0] == .string) return NativeResult.shareString(args[0].string);
    return NativeResult.copyString(ctx.allocator, trimmed);
}

fn native_trim(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return doTrim(ctx, "trim", args, 3);
}

fn native_ltrim(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return doTrim(ctx, "ltrim", args, 1);
}

fn native_rtrim(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return doTrim(ctx, "rtrim", args, 2);
}

fn native_chop(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return doTrim(ctx, "chop", args, 2);
}

fn native_addcslashes(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "addcslashes", args);
    const s = try p.str(0, "string");
    const what = try p.str(1, "characters");
    if (s.len == 0) return NativeResult.literal("");
    if (what.len == 0) return NativeResult.copyString(ctx.allocator, s);
    const flags = try charmask(ctx, "addcslashes", what);
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(ctx.allocator);
    for (s) |c| {
        if (flags[c]) {
            if (c < 32 or c > 126) {
                try out.append(ctx.allocator, '\\');
                switch (c) {
                    '\n' => try out.append(ctx.allocator, 'n'),
                    '\t' => try out.append(ctx.allocator, 't'),
                    '\r' => try out.append(ctx.allocator, 'r'),
                    7 => try out.append(ctx.allocator, 'a'),
                    0x0b => try out.append(ctx.allocator, 'v'),
                    8 => try out.append(ctx.allocator, 'b'),
                    0x0c => try out.append(ctx.allocator, 'f'),
                    else => try out.print(ctx.allocator, "{o:0>3}", .{c}),
                }
                continue;
            }
            try out.append(ctx.allocator, '\\');
        }
        try out.append(ctx.allocator, c);
    }
    return NativeResult.copyString(ctx.allocator, out.items);
}

fn native_stripslashes(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "stripslashes", args);
    const s = try p.str(0, "string");
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(ctx.allocator);
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '\\') {
            i += 1;
            if (i < s.len) {
                try out.append(ctx.allocator, if (s[i] == '0') 0 else s[i]);
                i += 1;
            }
        } else {
            try out.append(ctx.allocator, s[i]);
            i += 1;
        }
    }
    return NativeResult.copyString(ctx.allocator, out.items);
}

fn native_stripcslashes(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "stripcslashes", args);
    const s = try p.str(0, "string");
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(ctx.allocator);
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '\\' and i + 1 < s.len) {
            i += 1;
            switch (s[i]) {
                'n' => try out.append(ctx.allocator, '\n'),
                'r' => try out.append(ctx.allocator, '\r'),
                'a' => try out.append(ctx.allocator, 7),
                't' => try out.append(ctx.allocator, '\t'),
                'v' => try out.append(ctx.allocator, 0x0b),
                'b' => try out.append(ctx.allocator, 8),
                'f' => try out.append(ctx.allocator, 0x0c),
                '\\' => try out.append(ctx.allocator, '\\'),
                else => {
                    if (s[i] == 'x' and i + 1 < s.len and std.ascii.isHex(s[i + 1])) {
                        var n: u8 = std.fmt.charToDigit(s[i + 1], 16) catch 0;
                        i += 1;
                        if (i + 1 < s.len and std.ascii.isHex(s[i + 1])) {
                            n = n * 16 + (std.fmt.charToDigit(s[i + 1], 16) catch 0);
                            i += 1;
                        }
                        try out.append(ctx.allocator, n);
                        continue;
                    }
                    var digits: usize = 0;
                    var n: u32 = 0;
                    while (i < s.len and s[i] >= '0' and s[i] <= '7' and digits < 3) : (i += 1) {
                        n = n * 8 + (s[i] - '0');
                        digits += 1;
                    }
                    if (digits > 0) {
                        try out.append(ctx.allocator, @truncate(n));
                        i -= 1;
                    } else {
                        try out.append(ctx.allocator, s[i]);
                    }
                },
            }
        } else {
            try out.append(ctx.allocator, s[i]);
        }
    }
    return NativeResult.copyString(ctx.allocator, out.items);
}

fn native_strtok(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "strtok", args);
    const str = try p.str(0, "string");
    const tok_arg = try p.strOrNull(1, "token");
    const vm = ctx.vm;
    var tok: []const u8 = undefined;
    if (tok_arg) |t| {
        vm.setStrtokState(try ctx.allocator.dupe(u8, str));
        vm.strtok_pos = 0;
        tok = t;
    } else {
        tok = str;
    }
    const s = vm.strtok_state orelse {
        try docref(ctx, "strtok", "Both arguments must be provided when starting tokenization");
        return NativeResult.scalar(.{ .bool = false });
    };
    var pos = vm.strtok_pos;
    if (pos >= s.len) return NativeResult.scalar(.{ .bool = false });
    var table: [256]bool = @splat(false);
    for (tok) |c| table[c] = true;
    const start = pos;
    var skipped: usize = 0;
    while (table[s[pos]]) {
        pos += 1;
        if (pos >= s.len) {
            vm.setStrtokState(null);
            return NativeResult.scalar(.{ .bool = false });
        }
        skipped += 1;
    }
    pos += 1;
    while (pos < s.len and !table[s[pos]]) pos += 1;
    const token = s[start + skipped .. pos];
    vm.strtok_pos = pos + 1;
    return NativeResult.copyString(ctx.allocator, token);
}

// php_char_to_str_ex: every occurrence of one byte replaced
fn charToStr(ctx: *NativeContext, out: *std.ArrayListUnmanaged(u8), s: []const u8, from: u8, to: []const u8, case_sensitive: bool) RuntimeError!i64 {
    var count: i64 = 0;
    const lc = std.ascii.toLower(from);
    for (s) |c| {
        const hit = if (case_sensitive) c == from else std.ascii.toLower(c) == lc;
        if (hit) {
            count += 1;
            try out.appendSlice(ctx.allocator, to);
        } else try out.append(ctx.allocator, c);
    }
    return count;
}

// php_str_to_str_ex and php_str_to_str_i_ex: left to right, without overlaps
fn strToStr(ctx: *NativeContext, out: *std.ArrayListUnmanaged(u8), s: []const u8, needle: []const u8, to: []const u8, case_sensitive: bool) RuntimeError!i64 {
    var count: i64 = 0;
    var i: usize = 0;
    while (i < s.len) {
        const found = if (case_sensitive) std.mem.indexOfPos(u8, s, i, needle) else indexOfIgnoreCasePos(s, i, needle);
        const at = found orelse break;
        try out.appendSlice(ctx.allocator, s[i..at]);
        try out.appendSlice(ctx.allocator, to);
        i = at + needle.len;
        count += 1;
    }
    try out.appendSlice(ctx.allocator, s[i..]);
    return count;
}

fn indexOfIgnoreCasePos(s: []const u8, start: usize, needle: []const u8) ?usize {
    if (needle.len > s.len) return null;
    var i = start;
    while (i + needle.len <= s.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(s[i .. i + needle.len], needle)) return i;
    }
    return null;
}

// one subject through php_str_replace_in_subject
fn replaceInSubject(ctx: *NativeContext, search: Args.ArrayOrStr, replace: Args.ArrayOrStr, subject: []const u8, case_sensitive: bool, count: *i64) RuntimeError![]const u8 {
    if (subject.len == 0) return "";
    var current = subject;
    var scratch: std.ArrayListUnmanaged(u8) = .empty;
    defer scratch.deinit(ctx.allocator);
    switch (search) {
        .string => |needle| {
            if (needle.len == 0) return subject;
            const to = replace.string;
            if (needle.len == 1)
                count.* += try charToStr(ctx, &scratch, current, needle[0], to, case_sensitive)
            else
                count.* += try strToStr(ctx, &scratch, current, needle, to, case_sensitive);
            return (try ctx.vm.transientBytes(scratch.items)).bytes();
        },
        .array => |search_arr| {
            var replace_idx: usize = 0;
            for (search_arr.entries.items) |entry| {
                const needle = try elementString(ctx, entryValue(entry));
                var to: []const u8 = "";
                switch (replace) {
                    .string => |r| to = r,
                    .array => |rarr| if (replace_idx < rarr.entries.items.len) {
                        to = try elementString(ctx, entryValue(rarr.entries.items[replace_idx]));
                        replace_idx += 1;
                    },
                }
                if (needle.len == 0) continue;
                scratch.clearRetainingCapacity();
                const n = if (needle.len == 1)
                    try charToStr(ctx, &scratch, current, needle[0], to, case_sensitive)
                else
                    try strToStr(ctx, &scratch, current, needle, to, case_sensitive);
                count.* += n;
                if (n > 0) current = (try ctx.vm.transientBytes(scratch.items)).bytes();
                if (current.len == 0) return "";
            }
            return current;
        },
    }
}

fn strReplace(ctx: *NativeContext, comptime func: []const u8, args: []const Value, case_sensitive: bool) RuntimeError!NativeResult {
    const p = Args.init(ctx, func, args);
    const search = try p.arrayOrStr(0, "search");
    const replace = try p.arrayOrStr(1, "replace");
    if (search == .string and replace == .array)
        return throwFmt(ctx, "TypeError", func ++ "(): Argument #2 ($replace) must be of type string when argument #1 ($search) is a string", .{});
    const subject = try p.arrayOrStr(2, "subject");
    var count: i64 = 0;
    const result: NativeResult = switch (subject) {
        .string => |s| blk: {
            const out = try replaceInSubject(ctx, search, replace, s, case_sensitive, &count);
            if (args[2] == .string and out.ptr == s.ptr and out.len == s.len) break :blk NativeResult.shareString(args[2].string);
            break :blk try NativeResult.copyString(ctx.allocator, out);
        },
        .array => |arr| blk: {
            const out = try ctx.createArray();
            for (arr.entries.items) |entry| {
                const s = try elementString(ctx, entryValue(entry));
                const replaced = try replaceInSubject(ctx, search, replace, s, case_sensitive, &count);
                const str = try Value.String.create(ctx.allocator, replaced);
                defer str.release();
                try out.set(ctx.allocator, entry.key, .{ .string = str });
            }
            break :blk NativeResult.borrowed(.{ .array = out });
        },
    };
    if (args.len >= 4) ctx.setCallerVar(3, args.len, .{ .int = count });
    return result;
}

fn native_str_replace(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return strReplace(ctx, "str_replace", args, true);
}

fn native_str_ireplace(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return strReplace(ctx, "str_ireplace", args, false);
}

fn strtrArray(ctx: *NativeContext, str: []const u8, pats: *PhpArray) RuntimeError![]const u8 {
    const items = pats.entries.items;
    if (items.len == 0) return str;
    if (items.len == 1) {
        const entry = items[0];
        var key_buf: [24]u8 = undefined;
        const key = switch (entry.key) {
            .string => |k| k.bytes(),
            .int => |i| std.fmt.bufPrint(&key_buf, "{d}", .{i}) catch unreachable,
        };
        const to = try elementString(ctx, entryValue(entry));
        if (key.len == 0) {
            try docref(ctx, "strtr", "Ignoring replacement of empty string");
            return str;
        }
        var out: std.ArrayListUnmanaged(u8) = .empty;
        defer out.deinit(ctx.allocator);
        _ = if (key.len == 1) try charToStr(ctx, &out, str, key[0], to, true) else try strToStr(ctx, &out, str, key, to, true);
        return (try ctx.vm.transientBytes(out.items)).bytes();
    }
    // php_strtr_array_ex: the longest key that matches at each position
    var minlen: usize = 128 * 1024;
    var maxlen: usize = 0;
    var keys: std.StringHashMapUnmanaged(usize) = .empty;
    defer keys.deinit(ctx.allocator);
    var num_keys: std.ArrayListUnmanaged([]u8) = .empty;
    defer {
        for (num_keys.items) |k| ctx.allocator.free(k);
        num_keys.deinit(ctx.allocator);
    }
    var lengths: std.DynamicBitSetUnmanaged = try .initEmpty(ctx.allocator, str.len + 1);
    defer lengths.deinit(ctx.allocator);
    for (items) |entry| if (entry.key == .string) {
        const len = entry.key.string.bytes().len;
        if (len == 0) {
            try docref(ctx, "strtr", "Ignoring replacement of empty string");
            continue;
        }
        if (len > str.len) continue;
        maxlen = @max(maxlen, len);
        minlen = @min(minlen, len);
        lengths.set(len);
    };
    for (items, 0..) |entry, i| {
        const key: []const u8 = switch (entry.key) {
            .string => |k| k.bytes(),
            .int => |n| blk: {
                const text = try std.fmt.allocPrint(ctx.allocator, "{d}", .{n});
                try num_keys.append(ctx.allocator, text);
                if (text.len > str.len) continue;
                maxlen = @max(maxlen, text.len);
                minlen = @min(minlen, text.len);
                lengths.set(text.len);
                break :blk text;
            },
        };
        if (key.len > str.len) continue;
        const gop = try keys.getOrPut(ctx.allocator, key);
        if (!gop.found_existing) gop.value_ptr.* = i;
    }
    if (minlen > maxlen) return str;
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(ctx.allocator);
    var replaced = false;
    var old_pos: usize = 0;
    var pos: usize = 0;
    while (pos + minlen <= str.len) {
        var len = @min(maxlen, str.len - pos);
        while (len >= minlen) : (len -= 1) {
            if (!lengths.isSet(len)) continue;
            if (keys.get(str[pos .. pos + len])) |idx| {
                const to = try elementString(ctx, entryValue(pats.entries.items[idx]));
                try out.appendSlice(ctx.allocator, str[old_pos..pos]);
                try out.appendSlice(ctx.allocator, to);
                replaced = true;
                old_pos = pos + len;
                pos = old_pos - 1;
                break;
            }
        }
        pos += 1;
    }
    if (!replaced) return str;
    try out.appendSlice(ctx.allocator, str[old_pos..]);
    return (try ctx.vm.transientBytes(out.items)).bytes();
}

fn native_strtr(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "strtr", args);
    if (args.len <= 2) {
        const str = try p.str(0, "string");
        if (args[1] != .array) return p.typeError(1, "from", "array");
        if (str.len == 0) return NativeResult.literal("");
        const pats = args[1].array;
        const out = try strtrArray(ctx, str, pats);
        if (out.ptr == str.ptr and out.len == str.len and args[0] == .string) return NativeResult.shareString(args[0].string);
        return NativeResult.copyString(ctx.allocator, out);
    }
    const str = try p.str(0, "string");
    const from = try p.str(1, "from");
    const to = try p.str(2, "to");
    if (str.len == 0) return NativeResult.literal("");
    const n = @min(from.len, to.len);
    if (n == 0) return NativeResult.copyString(ctx.allocator, str);
    var xlat: [256]u8 = undefined;
    for (&xlat, 0..) |*x, i| x.* = @intCast(i);
    for (from[0..n], to[0..n]) |f, t| xlat[f] = t;
    const out = try ctx.allocator.alloc(u8, str.len);
    for (str, 0..) |c, i| out[i] = xlat[c];
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

fn implodeWith(ctx: *NativeContext, glue: []const u8, pieces: *PhpArray) RuntimeError!NativeResult {
    const items = pieces.entries.items;
    if (items.len == 0) return NativeResult.literal("");
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(ctx.allocator);
    var i: usize = 0;
    while (i < pieces.entries.items.len) : (i += 1) {
        if (i > 0) try out.appendSlice(ctx.allocator, glue);
        try out.appendSlice(ctx.allocator, try elementString(ctx, entryValue(pieces.entries.items[i])));
    }
    return NativeResult.copyString(ctx.allocator, out.items);
}

fn implode(ctx: *NativeContext, func: []const u8, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, func, args);
    // a direct call with two arguments is php's frameless implode, which
    // takes the separator as a string first
    const first: Args.ArrayOrStr = if (args.len >= 2) .{ .string = try p.str(0, "separator") } else try p.arrayOrStr(0, "separator");
    var pieces: ?*PhpArray = null;
    if (args.len >= 2) switch (args[1]) {
        .array => |a| pieces = a,
        .null, .undef => {},
        else => return p.typeError(1, "array", "?array"),
    };
    if (pieces) |arr| {
        if (first == .array) return throwFmt(ctx, "TypeError", "{s}(): Argument #1 ($separator) must be of type string, array given", .{func});
        return implodeWith(ctx, first.string, arr);
    }
    if (first == .string) return throwFmt(ctx, "TypeError", "{s}(): If argument #1 ($separator) is of type string, argument #2 ($array) must be of type array, null given", .{func});
    return implodeWith(ctx, "", first.array);
}

fn native_implode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return implode(ctx, "implode", args);
}

fn native_join(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return implode(ctx, "join", args);
}

fn native_strnatcmp(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "strnatcmp", args);
    const a = try p.str(0, "string1");
    const b = try p.str(1, "string2");
    return NativeResult.scalar(.{ .int = array_sort.strnatcmp(a, b, false) });
}

fn native_strnatcasecmp(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "strnatcasecmp", args);
    const a = try p.str(0, "string1");
    const b = try p.str(1, "string2");
    return NativeResult.scalar(.{ .int = array_sort.strnatcmp(a, b, true) });
}

fn threeWay(a: usize, b: usize) i64 {
    return if (a == b) 0 else if (a < b) -1 else 1;
}

// zend_binary_strncmp / zend_binary_strncasecmp
pub fn binaryStrncmp(a: []const u8, b: []const u8, length: usize, fold: bool) i64 {
    const n = @min(length, @min(a.len, b.len));
    for (a[0..n], b[0..n]) |x, y| {
        const cx = if (fold) std.ascii.toLower(x) else x;
        const cy = if (fold) std.ascii.toLower(y) else y;
        if (cx != cy) return @as(i64, cx) - @as(i64, cy);
    }
    return threeWay(@min(length, a.len), @min(length, b.len));
}

fn strncmpCommon(ctx: *NativeContext, comptime func: []const u8, args: []const Value, fold: bool) RuntimeError!NativeResult {
    const p = Args.init(ctx, func, args);
    const a = try p.str(0, "string1");
    const b = try p.str(1, "string2");
    const len = try p.long(2, "length");
    if (len < 0) return p.valueError(2, "length", "must be greater than or equal to 0");
    return NativeResult.scalar(.{ .int = binaryStrncmp(a, b, @intCast(len), fold) });
}

fn native_strncmp(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return strncmpCommon(ctx, "strncmp", args, false);
}

fn native_strncasecmp(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return strncmpCommon(ctx, "strncasecmp", args, true);
}

fn native_substr_count(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "substr_count", args);
    const haystack_all = try p.str(0, "haystack");
    const needle = try p.str(1, "needle");
    var offset = try p.optLong(2, "offset", 0);
    const length_arg = try p.longOrNull(3, "length");
    if (needle.len == 0) return p.valueError(1, "needle", "must not be empty");
    var haystack = haystack_all;
    if (offset != 0) {
        if (offset < 0) offset += @intCast(haystack.len);
        if (offset < 0 or offset > haystack.len) return p.valueError(2, "offset", "must be contained in argument #1 ($haystack)");
        haystack = haystack[@intCast(offset)..];
    }
    var length: i64 = @intCast(haystack.len);
    if (length_arg) |l| {
        length = l;
        if (length < 0) length += @intCast(haystack.len);
        if (length < 0 or length > haystack.len) return p.valueError(3, "length", "must be contained in argument #1 ($haystack)");
    }
    const region = haystack[0..@intCast(length)];
    var count: i64 = 0;
    if (needle.len == 1) {
        for (region) |c| {
            if (c == needle[0]) count += 1;
        }
    } else {
        var i: usize = 0;
        while (std.mem.indexOfPos(u8, region, i, needle)) |at| {
            count += 1;
            i = at + needle.len;
        }
    }
    return NativeResult.scalar(.{ .int = count });
}

fn native_substr_compare(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "substr_compare", args);
    const s1 = try p.str(0, "haystack");
    const s2 = try p.str(1, "needle");
    var offset = try p.long(2, "offset");
    const len_arg = try p.longOrNull(3, "length");
    const case_insensitive = try p.boolean(4, "case_insensitive", false);
    var len: i64 = 0;
    if (len_arg) |l| {
        len = l;
        if (len <= 0) {
            if (len == 0) return NativeResult.scalar(.{ .int = 0 });
            return p.valueError(3, "length", "must be greater than or equal to 0");
        }
    }
    if (offset < 0) offset = @max(0, @as(i64, @intCast(s1.len)) + offset);
    if (offset > s1.len) return p.valueError(2, "offset", "must be contained in argument #1 ($haystack)");
    const rest = s1[@intCast(offset)..];
    const cmp_len: usize = if (len != 0) @intCast(len) else @max(s2.len, rest.len);
    return NativeResult.scalar(.{ .int = binaryStrncmp(rest, s2, cmp_len, case_insensitive) });
}

fn native_strpbrk(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "strpbrk", args);
    const haystack = try p.str(0, "string");
    const list = try p.str(1, "characters");
    if (list.len == 0) return p.valueError(1, "characters", "must be a non-empty string");
    for (haystack, 0..) |c, i| {
        if (std.mem.indexOfScalar(u8, list, c) != null) return NativeResult.copyString(ctx.allocator, haystack[i..]);
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn native_strrchr(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "strrchr", args);
    const haystack = try p.str(0, "haystack");
    const needle = try p.str(1, "needle");
    const before = try p.boolean(2, "before_needle", false);
    // an empty needle searches for its terminating nul
    const c: u8 = if (needle.len > 0) needle[0] else 0;
    const at = std.mem.lastIndexOfScalar(u8, haystack, c) orelse return NativeResult.scalar(.{ .bool = false });
    if (before) return NativeResult.copyString(ctx.allocator, haystack[0..at]);
    return NativeResult.copyString(ctx.allocator, haystack[at..]);
}

fn strstrCommon(ctx: *NativeContext, comptime func: []const u8, args: []const Value, fold: bool) RuntimeError!NativeResult {
    const p = Args.init(ctx, func, args);
    const haystack = try p.str(0, "haystack");
    const needle = try p.str(1, "needle");
    const before = try p.boolean(2, "before_needle", false);
    const found = (if (fold) indexOfIgnoreCasePos(haystack, 0, needle) else std.mem.indexOf(u8, haystack, needle)) orelse return NativeResult.scalar(.{ .bool = false });
    if (before) return NativeResult.copyString(ctx.allocator, haystack[0..found]);
    return NativeResult.copyString(ctx.allocator, haystack[found..]);
}

fn native_strstr(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return strstrCommon(ctx, "strstr", args, false);
}

fn native_strchr(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return strstrCommon(ctx, "strchr", args, false);
}

fn native_stristr(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return strstrCommon(ctx, "stristr", args, true);
}

fn strposCommon(ctx: *NativeContext, comptime func: []const u8, args: []const Value, fold: bool) RuntimeError!NativeResult {
    const p = Args.init(ctx, func, args);
    const haystack = try p.str(0, "haystack");
    const needle = try p.str(1, "needle");
    var offset = try p.optLong(2, "offset", 0);
    if (offset < 0) offset += @intCast(haystack.len);
    if (offset < 0 or offset > haystack.len) return p.valueError(2, "offset", "must be contained in argument #1 ($haystack)");
    const start: usize = @intCast(offset);
    const found = (if (fold) indexOfIgnoreCasePos(haystack, start, needle) else std.mem.indexOfPos(u8, haystack, start, needle)) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(found) });
}

fn native_strpos(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return strposCommon(ctx, "strpos", args, false);
}

fn native_stripos(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return strposCommon(ctx, "stripos", args, true);
}

// zend_memnrstr over haystack[p..e]
fn lastIndexIn(haystack: []const u8, p: usize, e: usize, needle: []const u8, fold: bool) ?usize {
    if (needle.len == 0) return e;
    if (e < p or needle.len > e - p) return null;
    var i = e - needle.len + 1;
    while (i > p) {
        i -= 1;
        const window = haystack[i .. i + needle.len];
        if (if (fold) std.ascii.eqlIgnoreCase(window, needle) else std.mem.eql(u8, window, needle)) return i;
    }
    return null;
}

fn strrposCommon(ctx: *NativeContext, comptime func: []const u8, args: []const Value, fold: bool) RuntimeError!NativeResult {
    const p = Args.init(ctx, func, args);
    const haystack = try p.str(0, "haystack");
    const needle = try p.str(1, "needle");
    const offset = try p.optLong(2, "offset", 0);
    const hlen = haystack.len;
    if (fold and needle.len == 1) {
        // php's single-byte shortcut, with its own idea of the result
        var start: usize = 0;
        var e: i64 = undefined;
        if (offset >= 0) {
            if (offset > hlen) return p.valueError(2, "offset", "must be contained in argument #1 ($haystack)");
            start = @intCast(offset);
            e = @as(i64, @intCast(hlen)) - 1;
        } else {
            if (offset < -std.math.maxInt(i64) or -offset > hlen) return p.valueError(2, "offset", "must be contained in argument #1 ($haystack)");
            e = @as(i64, @intCast(hlen)) + offset;
        }
        const lowered = std.ascii.toLower(needle[0]);
        while (e >= @as(i64, @intCast(start))) : (e -= 1) {
            if (std.ascii.toLower(haystack[@intCast(e)]) == lowered) {
                return NativeResult.scalar(.{ .int = e - @as(i64, @intCast(start)) + (if (offset > 0) offset else 0) });
            }
        }
        return NativeResult.scalar(.{ .bool = false });
    }
    var start: usize = 0;
    var end: usize = hlen;
    if (offset >= 0) {
        if (offset > hlen) return p.valueError(2, "offset", "must be contained in argument #1 ($haystack)");
        start = @intCast(offset);
    } else {
        if (offset < -std.math.maxInt(i64) or -offset > hlen) return p.valueError(2, "offset", "must be contained in argument #1 ($haystack)");
        const back: usize = @intCast(-offset);
        if (back >= needle.len) end = hlen - back + needle.len;
    }
    const found = lastIndexIn(haystack, start, end, needle, fold) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(found) });
}

fn native_strrpos(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return strrposCommon(ctx, "strrpos", args, false);
}

fn native_strripos(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return strrposCommon(ctx, "strripos", args, true);
}

fn native_ucwords(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "ucwords", args);
    const s = try p.str(0, "string");
    const delims = try p.optStr(1, "separators", " \t\r\n\x0c\x0b");
    if (s.len == 0) return NativeResult.literal("");
    const mask = try charmask(ctx, "ucwords", delims);
    const out = try ctx.allocator.dupe(u8, s);
    out[0] = std.ascii.toUpper(out[0]);
    var i: usize = 0;
    while (i + 1 < out.len) : (i += 1) {
        if (mask[out[i]]) out[i + 1] = std.ascii.toUpper(out[i + 1]);
    }
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

fn native_chunk_split(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "chunk_split", args);
    const s = try p.str(0, "string");
    const chunklen = try p.optLong(1, "length", 76);
    const end = try p.optStr(2, "separator", "\r\n");
    if (chunklen <= 0) return p.valueError(1, "length", "must be greater than 0");
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(ctx.allocator);
    if (chunklen > s.len) {
        try out.appendSlice(ctx.allocator, s);
        try out.appendSlice(ctx.allocator, end);
        return NativeResult.copyString(ctx.allocator, out.items);
    }
    if (s.len == 0) return NativeResult.literal("");
    const n: usize = @intCast(chunklen);
    var i: usize = 0;
    while (i < s.len) : (i += n) {
        try out.appendSlice(ctx.allocator, s[i..@min(s.len, i + n)]);
        try out.appendSlice(ctx.allocator, end);
    }
    return NativeResult.copyString(ctx.allocator, out.items);
}
