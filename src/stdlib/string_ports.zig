// string functions ported from php's ext/standard/string.c and
// Zend/zend_builtin_functions.c: argument parsing as php's
// ZEND_PARSE_PARAMETERS does it, and the functions' own edge cases

const std = @import("std");
const platform = @import("../platform.zig");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const vm_mod = @import("../runtime/vm.zig");
const array_diff = @import("array_diff.zig");
const array_sort = @import("array_sort.zig");
const strings = @import("strings.zig");
const phpTypeName = @import("types.zig").phpTypeName;
const native_params = @import("native_params.zig");
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
    .{ "strcmp", native_strcmp },
    .{ "strcasecmp", native_strcasecmp },
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
    .{ "str_pad", native_str_pad },
    .{ "str_increment", native_str_increment },
    .{ "str_decrement", native_str_decrement },
    .{ "nl2br", native_nl2br },
    .{ "wordwrap", native_wordwrap },
    .{ "substr_replace", native_substr_replace },
    .{ "ord", native_ord },
    .{ "chr", native_chr },
    .{ "count_chars", native_count_chars },
    .{ "explode", native_explode },
    .{ "soundex", native_soundex },
    .{ "str_word_count", native_str_word_count },
    .{ "convert_uuencode", native_convert_uuencode },
    .{ "convert_uudecode", native_convert_uudecode },
    .{ "quoted_printable_encode", native_quoted_printable_encode },
    .{ "metaphone", native_metaphone },
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

// php's argument parsing for one call: weak-mode coercions, the null
// deprecation, and TypeErrors worded as zend_parse_parameters words them
pub const Args = struct {
    ctx: *NativeContext,
    func: []const u8,
    args: []const Value,
    // added to positions in messages: a procedural alias passes its object
    // first, so the method's argument #1 is the function's #2
    shift: usize = 0,

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
        return throwFmt(self.ctx, "TypeError", "{s}(): Argument #{d} (${s}) must be of type {s}, {s} given", .{ self.func, index + 1 + self.shift, name, expected, if (index < self.args.len) phpTypeName(self.args[index]) else "null" });
    }

    pub fn valueError(self: Args, index: usize, name: []const u8, comptime text: []const u8) RuntimeError {
        return throwFmt(self.ctx, "ValueError", "{s}(): Argument #{d} (${s}) " ++ text, .{ self.func, index + 1 + self.shift, name });
    }

    // php names the type the parameter declares, not the one parsed
    fn nullDeprecated(self: Args, index: usize, name: []const u8, expected: []const u8) RuntimeError!void {
        var declared = expected;
        if (native_params.get(self.func)) |sig| {
            if (index + self.shift < sig.params.len and sig.params[index + self.shift].type.len > 0) declared = sig.params[index + self.shift].type;
        }
        const msg = try std.fmt.allocPrint(self.ctx.allocator, "{s}(): Passing null to parameter #{d} (${s}) of type {s} is deprecated", .{ self.func, index + 1 + self.shift, name, declared });
        defer self.ctx.allocator.free(msg);
        try self.ctx.vm.raiseError(e_deprecated, msg);
    }

    // Z_PARAM_STR, typed as `expected` in messages
    pub fn strAs(self: Args, index: usize, name: []const u8, expected: []const u8) RuntimeError![]const u8 {
        const v = self.args[index];
        switch (v) {
            .string => return v.string.bytes(),
            .null, .undef => if (!self.strict()) {
                try self.nullDeprecated(index, name, expected);
                return "";
            },
            .int, .float, .bool => if (!self.strict()) {
                // zend_double_to_str
                if (v == .float and std.math.isNan(v.float)) try self.ctx.vm.emitWarning("unexpected NAN value was coerced to string");
                return strings.coerceToString(self.ctx, v);
            },
            .object => |o| if (self.ctx.vm.hasMethod(o.class_name, "__toString")) return self.ctx.vm.objectToString(o),
            else => {},
        }
        return self.typeError(index, name, expected);
    }

    pub fn str(self: Args, index: usize, name: []const u8) RuntimeError![]const u8 {
        return self.strAs(index, name, "string");
    }

    // Z_PARAM_PATH: a string without nul bytes
    pub fn path(self: Args, index: usize, name: []const u8) RuntimeError![]const u8 {
        const s = try self.str(index, name);
        if (std.mem.indexOfScalar(u8, s, 0) != null) return self.valueError(index, name, "must not contain any null bytes");
        return s;
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
                if (Value.isNumericString(bytes)) {
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
                var tmp: [64]u8 = undefined;
                break :blk try std.fmt.allocPrint(self.ctx.allocator, "Implicit conversion from float {s} to int loses precision", .{@import("output.zig").formatFloat(&tmp, f)});
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

    // Z_PARAM_OBJECT_OF_CLASS
    pub fn object(self: Args, index: usize, name: []const u8, class: []const u8) RuntimeError!*@import("../runtime/value.zig").PhpObject {
        const v = if (index < self.args.len) self.args[index] else Value.null;
        if (v == .object and self.ctx.vm.isInstanceOf(v.object.class_name, class)) return v.object;
        return self.typeError(index, name, class);
    }

    // Z_PARAM_OBJECT_OF_CLASS_OR_NULL; the expected type reads "?Class"
    pub fn objectOrNull(self: Args, index: usize, name: []const u8, comptime class: []const u8) RuntimeError!?*@import("../runtime/value.zig").PhpObject {
        if (index >= self.args.len) return null;
        const v = self.args[index];
        if (v == .null or v == .undef) return null;
        if (v == .object and self.ctx.vm.isInstanceOf(v.object.class_name, class)) return v.object;
        return self.typeError(index, name, "?" ++ class);
    }

    // Z_PARAM_DOUBLE_OR_NULL
    pub fn doubleOrNull(self: Args, index: usize, name: []const u8) RuntimeError!?f64 {
        if (index >= self.args.len) return null;
        const v = self.args[index];
        if (v == .null or v == .undef) return null;
        return switch (v) {
            .float => |f| f,
            .int => |i| @floatFromInt(i),
            .bool => |b| if (!self.strict()) @as(f64, if (b) 1 else 0) else self.typeError(index, name, "?float"),
            .string => |s| if (!self.strict() and Value.isNumericString(s.bytes())) Value.toFloat(v) else self.typeError(index, name, "?float"),
            else => self.typeError(index, name, "?float"),
        };
    }

    // Z_PARAM_NUMBER (zend_parse_arg_number_slow): an int or a float, a
    // numeric string read as the one it spells
    pub fn number(self: Args, index: usize, name: []const u8) RuntimeError!Value {
        const v = self.args[index];
        switch (v) {
            .int, .float => return v,
            .null, .undef => if (!self.strict()) {
                try self.nullDeprecated(index, name, "int|float");
                return .{ .int = 0 };
            },
            .bool => |b| if (!self.strict()) return .{ .int = @intFromBool(b) },
            .string => |s| if (!self.strict()) {
                const bytes = s.bytes();
                if (Value.isNumericString(bytes)) {
                    const trimmed = std.mem.trim(u8, bytes, " \t\n\r\x0b\x0c");
                    if (std.mem.indexOfAny(u8, trimmed, ".eE") == null) {
                        if (std.fmt.parseInt(i64, trimmed, 10)) |i| return .{ .int = i } else |_| {}
                    }
                    return .{ .float = Value.toFloat(v) };
                }
            },
            else => {},
        }
        return self.typeError(index, name, "int|float");
    }

    // Z_PARAM_DOUBLE (zend_parse_arg_double_weak)
    pub fn double(self: Args, index: usize, name: []const u8) RuntimeError!f64 {
        const v = self.args[index];
        switch (v) {
            .float => |f| return f,
            .int => |i| return @floatFromInt(i),
            .null, .undef => if (!self.strict()) {
                try self.nullDeprecated(index, name, "float");
                return 0;
            },
            .bool => |b| if (!self.strict()) return if (b) 1 else 0,
            .string => |s| if (!self.strict() and Value.isNumericString(s.bytes())) return Value.toFloat(v),
            else => {},
        }
        return self.typeError(index, name, "float");
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
            .string => if (!self.strict()) return v.isTruthy(),
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
        .string => return v.string.bytes(),
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
    const first: Args.ArrayOrStr = if (args.len >= 2 and std.mem.eql(u8, func, "implode")) .{ .string = try p.str(0, "separator") } else try p.arrayOrStr(0, "separator");
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

extern "c" fn memcmp(a: [*]const u8, b: [*]const u8, n: usize) c_int;

// php hands memcmp's own result back from strcmp and strncmp, whatever
// magnitude the c library gives it, so this asks the same library. php's
// windows builds use microsoft's runtime, whose memcmp gives only the sign,
// where zphp links mingw's
fn libcMemcmp(a: []const u8, b: []const u8, n: usize) i64 {
    if (n == 0) return 0;
    const r = memcmp(a.ptr, b.ptr, n);
    if (platform.is_windows) return std.math.sign(r);
    return r;
}

// the first difference of the lowercased bytes, as zend_binary_strcasecmp
// computes it
fn foldedDifference(a: []const u8, b: []const u8, n: usize) i64 {
    for (a[0..n], b[0..n]) |x, y| {
        const cx = std.ascii.toLower(x);
        const cy = std.ascii.toLower(y);
        if (cx != cy) return @as(i64, cx) - @as(i64, cy);
    }
    return 0;
}

// zend_binary_strcmp / zend_binary_strcasecmp
pub fn binaryStrcmp(a: []const u8, b: []const u8, fold: bool) i64 {
    const n = @min(a.len, b.len);
    const r = if (fold) foldedDifference(a, b, n) else libcMemcmp(a, b, n);
    return if (r != 0) r else threeWay(a.len, b.len);
}

// zend_binary_strncmp / zend_binary_strncasecmp
pub fn binaryStrncmp(a: []const u8, b: []const u8, length: usize, fold: bool) i64 {
    const n = @min(length, @min(a.len, b.len));
    const r = if (fold) foldedDifference(a, b, n) else libcMemcmp(a, b, n);
    return if (r != 0) r else threeWay(@min(length, a.len), @min(length, b.len));
}

fn native_strcmp(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "strcmp", args);
    return NativeResult.scalar(.{ .int = binaryStrcmp(try p.str(0, "string1"), try p.str(1, "string2"), false) });
}

fn native_strcasecmp(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "strcasecmp", args);
    return NativeResult.scalar(.{ .int = binaryStrcmp(try p.str(0, "string1"), try p.str(1, "string2"), true) });
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

fn native_str_pad(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "str_pad", args);
    const input = try p.str(0, "string");
    const pad_length = try p.long(1, "length");
    const pad = try p.optStr(2, "pad_string", " ");
    const pad_type = try p.optLong(3, "pad_type", 1);
    if (pad_length < 0 or pad_length <= input.len) return NativeResult.copyString(ctx.allocator, input);
    if (pad.len == 0) return p.valueError(2, "pad_string", "must not be empty");
    if (pad_type < 0 or pad_type > 2) return p.valueError(3, "pad_type", "must be STR_PAD_LEFT, STR_PAD_RIGHT, or STR_PAD_BOTH");
    const num: usize = @as(usize, @intCast(pad_length)) - input.len;
    const left: usize = switch (pad_type) {
        0 => num,
        2 => num / 2,
        else => 0,
    };
    const out = try ctx.allocator.alloc(u8, @intCast(pad_length));
    for (0..left) |i| out[i] = pad[i % pad.len];
    @memcpy(out[left .. left + input.len], input);
    for (0..num - left) |i| out[left + input.len + i] = pad[i % pad.len];
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

fn alnumCheck(p: Args, s: []const u8) RuntimeError!void {
    if (s.len == 0) return p.valueError(0, "string", "must not be empty");
    for (s) |c| {
        if (!std.ascii.isAlphanumeric(c)) return p.valueError(0, "string", "must be composed only of alphanumeric ASCII characters");
    }
}

fn native_str_increment(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "str_increment", args);
    const s = try p.str(0, "string");
    try alnumCheck(p, s);
    const buf = try ctx.allocator.alloc(u8, s.len + 1);
    defer ctx.allocator.free(buf);
    @memcpy(buf[1..], s);
    var pos = s.len;
    var carry = false;
    while (true) {
        const c = buf[pos];
        if (c != 'z' and c != 'Z' and c != '9') {
            carry = false;
            buf[pos] += 1;
        } else {
            carry = true;
            buf[pos] = if (c == '9') '0' else c - 25;
        }
        if (!carry or pos == 1) break;
        pos -= 1;
    }
    if (carry) {
        buf[0] = if (buf[1] == '0') '1' else buf[1];
        return NativeResult.copyString(ctx.allocator, buf);
    }
    return NativeResult.copyString(ctx.allocator, buf[1..]);
}

fn native_str_decrement(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "str_decrement", args);
    const s = try p.str(0, "string");
    try alnumCheck(p, s);
    if (s[0] == '0') return throwFmt(ctx, "ValueError", "str_decrement(): Argument #1 ($string) \"{s}\" is out of decrement range", .{s});
    const buf = try ctx.allocator.dupe(u8, s);
    defer ctx.allocator.free(buf);
    var pos = s.len - 1;
    var carry = false;
    while (true) {
        const c = buf[pos];
        if (c != 'a' and c != 'A' and c != '0') {
            carry = false;
            buf[pos] -= 1;
        } else {
            carry = true;
            buf[pos] = if (c == '0') '9' else c + 25;
        }
        if (!carry or pos == 0) break;
        pos -= 1;
    }
    if (carry or (buf[0] == '0' and buf.len > 1)) {
        if (buf.len == 1) return throwFmt(ctx, "ValueError", "str_decrement(): Argument #1 ($string) \"{s}\" is out of decrement range", .{s});
        return NativeResult.copyString(ctx.allocator, buf[1..]);
    }
    return NativeResult.copyString(ctx.allocator, buf);
}

fn native_nl2br(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "nl2br", args);
    const s = try p.str(0, "string");
    const xhtml = try p.boolean(1, "use_xhtml", true);
    const br: []const u8 = if (xhtml) "<br />" else "<br>";
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(ctx.allocator);
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (c == '\r' or c == '\n') {
            try out.appendSlice(ctx.allocator, br);
            const next: u8 = if (i + 1 < s.len) s[i + 1] else 0;
            if ((c == '\r' and next == '\n') or (c == '\n' and next == '\r')) {
                try out.append(ctx.allocator, c);
                i += 1;
            }
            try out.append(ctx.allocator, s[i]);
        } else try out.append(ctx.allocator, c);
    }
    return NativeResult.copyString(ctx.allocator, out.items);
}

fn native_wordwrap(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "wordwrap", args);
    const text = try p.str(0, "string");
    const linelength = try p.optLong(1, "width", 75);
    const brk = try p.optStr(2, "break", "\n");
    const docut = try p.boolean(3, "cut_long_words", false);
    if (text.len == 0) return NativeResult.literal("");
    if (brk.len == 0) return p.valueError(2, "break", "must not be empty");
    if (linelength == 0 and docut) return p.valueError(3, "cut_long_words", "cannot be true when argument #2 ($width) is 0");
    const len: i64 = @intCast(text.len);
    if (brk.len == 1 and !docut) {
        const out = try ctx.allocator.dupe(u8, text);
        var laststart: i64 = 0;
        var lastspace: i64 = 0;
        var current: i64 = 0;
        while (current < len) : (current += 1) {
            const c = text[@intCast(current)];
            if (c == brk[0]) {
                laststart = current + 1;
                lastspace = current + 1;
            } else if (c == ' ') {
                if (current - laststart >= linelength) {
                    out[@intCast(current)] = brk[0];
                    laststart = current + 1;
                }
                lastspace = current;
            } else if (current - laststart >= linelength and laststart != lastspace) {
                out[@intCast(lastspace)] = brk[0];
                laststart = lastspace + 1;
            }
        }
        return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
    }
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(ctx.allocator);
    var laststart: i64 = 0;
    var lastspace: i64 = 0;
    var current: i64 = 0;
    while (current < len) : (current += 1) {
        const cu: usize = @intCast(current);
        const ls: usize = @intCast(laststart);
        if (text[cu] == brk[0] and cu + brk.len <= text.len and std.mem.eql(u8, text[cu .. cu + brk.len], brk)) {
            try out.appendSlice(ctx.allocator, text[ls .. cu + brk.len]);
            current += @as(i64, @intCast(brk.len)) - 1;
            laststart = current + 1;
            lastspace = current + 1;
        } else if (text[cu] == ' ') {
            if (current - laststart >= linelength) {
                try out.appendSlice(ctx.allocator, text[ls..cu]);
                try out.appendSlice(ctx.allocator, brk);
                laststart = current + 1;
            }
            lastspace = current;
        } else if (current - laststart >= linelength and docut and laststart >= lastspace) {
            try out.appendSlice(ctx.allocator, text[ls..cu]);
            try out.appendSlice(ctx.allocator, brk);
            laststart = current;
            lastspace = current;
        } else if (current - laststart >= linelength and laststart < lastspace) {
            try out.appendSlice(ctx.allocator, text[ls..@intCast(lastspace)]);
            try out.appendSlice(ctx.allocator, brk);
            laststart = lastspace + 1;
            lastspace = laststart;
        }
    }
    if (laststart != current) try out.appendSlice(ctx.allocator, text[@intCast(laststart)..@intCast(current)]);
    return NativeResult.copyString(ctx.allocator, out.items);
}

const ArrayOrLong = union(enum) { array: *PhpArray, long: i64, none };

fn arrayOrLong(p: Args, index: usize, name: []const u8, nullable: bool) RuntimeError!ArrayOrLong {
    if (index >= p.args.len) return .none;
    const v = p.args[index];
    if (v == .array) return .{ .array = v.array };
    if (nullable and (v == .null or v == .undef)) return .none;
    return .{ .long = try p.longAs(index, name, if (nullable) "array|int|null" else "array|int") };
}

// the next element of a parallel array in substr_replace
fn nextElement(arr: *PhpArray, idx: *usize) ?Value {
    if (idx.* >= arr.entries.items.len) return null;
    const v = entryValue(arr.entries.items[idx.*]);
    idx.* += 1;
    return v;
}

fn native_substr_replace(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "substr_replace", args);
    const str = try p.arrayOrStr(0, "string");
    const repl = try p.arrayOrStr(1, "replace");
    const from = try arrayOrLong(p, 2, "offset", false);
    const length = try arrayOrLong(p, 3, "length", true);
    switch (str) {
        .string => |s| {
            if (from == .array) return throwFmt(ctx, "TypeError", "substr_replace(): Argument #3 ($offset) cannot be an array when working on a single string", .{});
            if (length == .array) return throwFmt(ctx, "TypeError", "substr_replace(): Argument #4 ($length) cannot be an array when working on a single string", .{});
            const slen: i64 = @intCast(s.len);
            var l: i64 = if (length == .long) length.long else slen;
            var f = from.long;
            if (f < 0) {
                f = @max(0, slen + f);
            } else if (f > slen) f = slen;
            if (l < 0) l = @max(0, (slen - f) + l);
            if (l > slen) l = slen;
            if (f + l > slen) l = slen - f;
            const r: []const u8 = switch (repl) {
                .string => |r| r,
                .array => |arr| blk: {
                    var idx: usize = 0;
                    break :blk if (nextElement(arr, &idx)) |v| try elementString(ctx, v) else "";
                },
            };
            const fu: usize = @intCast(f);
            const lu: usize = @intCast(l);
            var out: std.ArrayListUnmanaged(u8) = .empty;
            defer out.deinit(ctx.allocator);
            try out.appendSlice(ctx.allocator, s[0..fu]);
            try out.appendSlice(ctx.allocator, r);
            try out.appendSlice(ctx.allocator, s[fu + lu ..]);
            return NativeResult.copyString(ctx.allocator, out.items);
        },
        .array => |arr| {
            const result = try ctx.createArray();
            var from_idx: usize = 0;
            var len_idx: usize = 0;
            var repl_idx: usize = 0;
            for (arr.entries.items) |entry| {
                const orig = try elementString(ctx, entryValue(entry));
                const olen: i64 = @intCast(orig.len);
                var f: i64 = switch (from) {
                    .array => |fa| if (nextElement(fa, &from_idx)) |v| Value.toInt(v) else 0,
                    .long => |n| n,
                    .none => 0,
                };
                if (f < 0) {
                    f = @max(0, olen + f);
                } else if (f > olen) f = olen;
                var l: i64 = switch (length) {
                    .array => |la| if (nextElement(la, &len_idx)) |v| Value.toInt(v) else olen,
                    .long => |n| n,
                    .none => olen,
                };
                if (l < 0) l = @max(0, (olen - f) + l);
                if (f + l > olen) l = olen - f;
                const r: []const u8 = switch (repl) {
                    .string => |r| r,
                    .array => |ra| if (nextElement(ra, &repl_idx)) |v| try elementString(ctx, v) else "",
                };
                const fu: usize = @intCast(f);
                const lu: usize = @intCast(l);
                var out: std.ArrayListUnmanaged(u8) = .empty;
                defer out.deinit(ctx.allocator);
                try out.appendSlice(ctx.allocator, orig[0..fu]);
                try out.appendSlice(ctx.allocator, r);
                try out.appendSlice(ctx.allocator, orig[fu + lu ..]);
                const piece = try Value.String.create(ctx.allocator, out.items);
                defer piece.release();
                try result.set(ctx.allocator, entry.key, .{ .string = piece });
            }
            return NativeResult.borrowed(.{ .array = result });
        },
    }
}

fn native_ord(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "ord", args);
    const s = try p.str(0, "character");
    if (s.len != 1) {
        const msg = if (s.len == 0) "ord(): Providing an empty string is deprecated" else "ord(): Providing a string that is not one byte long is deprecated. Use ord($str[0]) instead";
        try ctx.vm.raiseError(e_deprecated, msg);
        if (ctx.vm.pending_exception != null) return error.RuntimeError;
    }
    return NativeResult.scalar(.{ .int = if (s.len > 0) s[0] else 0 });
}

fn native_chr(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "chr", args);
    const c = try p.long(0, "codepoint");
    if (c < 0 or c > 255) {
        try ctx.vm.raiseError(e_deprecated, "chr(): Providing a value not in-between 0 and 255 is deprecated, this is because a byte value must be in the [0, 255] interval. The value used will be constrained using % 256");
        if (ctx.vm.pending_exception != null) return error.RuntimeError;
    }
    const byte: u8 = @intCast(c & 0xff);
    return NativeResult.copyString(ctx.allocator, &.{byte});
}

fn native_count_chars(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "count_chars", args);
    const s = try p.str(0, "string");
    const mode = try p.optLong(1, "mode", 0);
    if (mode < 0 or mode > 4) return p.valueError(1, "mode", "must be between 0 and 4 (inclusive)");
    var counts: [256]i64 = @splat(0);
    for (s) |c| counts[c] += 1;
    if (mode >= 3) {
        var out: [256]u8 = undefined;
        var n: usize = 0;
        for (counts, 0..) |count, i| {
            if ((mode == 3) == (count != 0)) {
                out[n] = @intCast(i);
                n += 1;
            }
        }
        return NativeResult.copyString(ctx.allocator, out[0..n]);
    }
    const arr = try ctx.createArray();
    for (counts, 0..) |count, i| {
        const keep = switch (mode) {
            1 => count != 0,
            2 => count == 0,
            else => true,
        };
        if (keep) try arr.set(ctx.allocator, .{ .int = @intCast(i) }, .{ .int = count });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_explode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "explode", args);
    const delim = try p.str(0, "separator");
    const str = try p.str(1, "string");
    const limit = try p.optLong(2, "limit", std.math.maxInt(i64));
    if (delim.len == 0) return p.valueError(0, "separator", "must not be empty");
    const arr = try ctx.createArray();
    if (str.len == 0) {
        if (limit >= 0) try appendPiece(ctx, arr, "");
        return NativeResult.borrowed(.{ .array = arr });
    }
    if (limit > 1) {
        var p1: usize = 0;
        var remaining = limit;
        var found = std.mem.indexOfPos(u8, str, 0, delim);
        if (found == null) {
            try appendPiece(ctx, arr, str);
        } else {
            while (found) |p2| {
                try appendPiece(ctx, arr, str[p1..p2]);
                p1 = p2 + delim.len;
                found = std.mem.indexOfPos(u8, str, p1, delim);
                remaining -= 1;
                if (remaining <= 1) break;
            }
            try appendPiece(ctx, arr, str[p1..]);
        }
    } else if (limit < 0) {
        var positions: std.ArrayListUnmanaged(usize) = .empty;
        defer positions.deinit(ctx.allocator);
        var found = std.mem.indexOfPos(u8, str, 0, delim);
        if (found != null) {
            try positions.append(ctx.allocator, 0);
            while (found) |p2| {
                const next = p2 + delim.len;
                try positions.append(ctx.allocator, next);
                found = std.mem.indexOfPos(u8, str, next, delim);
            }
            const n: i64 = @as(i64, @intCast(positions.items.len)) + limit;
            var i: usize = 0;
            while (@as(i64, @intCast(i)) < n) : (i += 1) {
                try appendPiece(ctx, arr, str[positions.items[i] .. positions.items[i + 1] - delim.len]);
            }
        }
    } else {
        try appendPiece(ctx, arr, str);
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn appendPiece(ctx: *NativeContext, arr: *PhpArray, bytes: []const u8) RuntimeError!void {
    const piece = try Value.String.create(ctx.allocator, bytes);
    defer piece.release();
    try arr.append(ctx.allocator, .{ .string = piece });
}

fn native_soundex(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "soundex", args);
    const s = try p.str(0, "string");
    const table = [26]u8{ 0, '1', '2', '3', 0, '1', '2', 0, 0, '2', '2', '4', '5', '5', 0, '1', '2', '6', '2', '3', 0, '1', 0, '2', 0, '2' };
    var out: [4]u8 = undefined;
    var small: usize = 0;
    var last: u8 = 0xff;
    for (s) |raw| {
        if (small >= 4) break;
        const code = std.ascii.toUpper(raw);
        if (code < 'A' or code > 'Z') continue;
        if (small == 0) {
            out[0] = code;
            small = 1;
            last = table[code - 'A'];
        } else {
            const mapped = table[code - 'A'];
            if (mapped != last) {
                if (mapped != 0) {
                    out[small] = mapped;
                    small += 1;
                }
                last = mapped;
            }
        }
    }
    while (small < 4) : (small += 1) out[small] = '0';
    return NativeResult.copyString(ctx.allocator, &out);
}

fn native_str_word_count(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "str_word_count", args);
    const s = try p.str(0, "string");
    const format = try p.optLong(1, "format", 0);
    const char_list = try p.strOrNull(2, "characters");
    switch (format) {
        0 => if (s.len == 0) return NativeResult.scalar(.{ .int = 0 }),
        1, 2 => if (s.len == 0) return NativeResult.borrowed(.{ .array = try ctx.createArray() }),
        else => return p.valueError(1, "format", "must be a valid format value"),
    }
    var ch: [256]bool = @splat(false);
    if (char_list) |list| ch = try charmask(ctx, "str_word_count", list);
    const listed = char_list != null;
    var pos: usize = 0;
    var e: usize = s.len;
    if ((s[0] == '\'' and (!listed or !ch['\''])) or (s[0] == '-' and (!listed or !ch['-']))) pos += 1;
    if (s[e - 1] == '-' and (!listed or !ch['-'])) e -= 1;
    const arr: ?*PhpArray = if (format != 0) try ctx.createArray() else null;
    var count: i64 = 0;
    while (pos < e) {
        const start = pos;
        while (pos < e and (std.ascii.isAlphabetic(s[pos]) or (listed and ch[s[pos]]) or s[pos] == '\'' or s[pos] == '-')) pos += 1;
        if (pos > start) {
            if (arr) |a| {
                const word = try Value.String.create(ctx.allocator, s[start..pos]);
                defer word.release();
                if (format == 1) try a.append(ctx.allocator, .{ .string = word }) else try a.set(ctx.allocator, .{ .int = @intCast(start) }, .{ .string = word });
            } else count += 1;
        }
        pos += 1;
    }
    if (arr) |a| return NativeResult.borrowed(.{ .array = a });
    return NativeResult.scalar(.{ .int = count });
}

fn uuEnc(c: u8) u8 {
    return if (c != 0) (c & 0o77) + ' ' else '`';
}

fn uuDec(c: u8) u8 {
    return (c -% ' ') & 0o77;
}

// php_uuencode; reads past the end see the string's terminating nul
fn uuencode(allocator: std.mem.Allocator, src: []const u8, out: *std.ArrayListUnmanaged(u8)) !void {
    const at = struct {
        fn f(b: []const u8, i: usize) u8 {
            return if (i < b.len) b[i] else 0;
        }
    }.f;
    var len: usize = 45;
    var s: usize = 0;
    const e = src.len;
    while (s + 3 < e) {
        var ee = s + len;
        if (ee > e) {
            ee = e;
            len = ee - s;
            if (len % 3 != 0) ee = s + (len / 3) * 3;
        }
        try out.append(allocator, uuEnc(@intCast(len)));
        while (s < ee) : (s += 3) {
            try out.append(allocator, uuEnc(at(src, s) >> 2));
            try out.append(allocator, uuEnc(((at(src, s) << 4) & 0o60) | ((at(src, s + 1) >> 4) & 0o17)));
            try out.append(allocator, uuEnc(((at(src, s + 1) << 2) & 0o74) | ((at(src, s + 2) >> 6) & 0o3)));
            try out.append(allocator, uuEnc(at(src, s + 2) & 0o77));
        }
        if (len == 45) try out.append(allocator, '\n');
    }
    if (s < e) {
        if (len == 45) {
            try out.append(allocator, uuEnc(@intCast(e - s)));
            len = 0;
        }
        try out.append(allocator, uuEnc(at(src, s) >> 2));
        try out.append(allocator, uuEnc(((at(src, s) << 4) & 0o60) | ((at(src, s + 1) >> 4) & 0o17)));
        try out.append(allocator, if (e - s > 1) uuEnc(((at(src, s + 1) << 2) & 0o74) | ((at(src, s + 2) >> 6) & 0o3)) else uuEnc(0));
        try out.append(allocator, if (e - s > 2) uuEnc(at(src, s + 2) & 0o77) else uuEnc(0));
    }
    if (len < 45) try out.append(allocator, '\n');
    try out.append(allocator, uuEnc(0));
    try out.append(allocator, '\n');
}

// php_uudecode; false when the data is not uuencoded
fn uudecode(allocator: std.mem.Allocator, src: []const u8, out: *std.ArrayListUnmanaged(u8)) !bool {
    if (src.len == 0) return false;
    const at = struct {
        fn f(b: []const u8, i: usize) u8 {
            return if (i < b.len) b[i] else 0;
        }
    }.f;
    var total: usize = 0;
    var s: usize = 0;
    const e = src.len;
    while (s < e) {
        const len: usize = uuDec(src[s]);
        s += 1;
        if (len == 0) break;
        if (len > src.len) return false;
        total += len;
        const ee = s + (if (len == 45) 60 else @as(usize, @intFromFloat(@floor(@as(f64, @floatFromInt(len)) * 1.33))));
        if (ee > e) return false;
        while (s < ee) : (s += 4) {
            if (s + 4 > e) return false;
            try out.append(allocator, uuDec(src[s]) << 2 | uuDec(src[s + 1]) >> 4);
            try out.append(allocator, uuDec(src[s + 1]) << 4 | uuDec(src[s + 2]) >> 2);
            try out.append(allocator, uuDec(src[s + 2]) << 6 | uuDec(src[s + 3]));
        }
        if (len < 45) break;
        s += 1;
    }
    if (total > out.items.len) {
        try out.append(allocator, uuDec(at(src, s)) << 2 | uuDec(at(src, s + 1)) >> 4);
        if (total > 1) {
            try out.append(allocator, uuDec(at(src, s + 1)) << 4 | uuDec(at(src, s + 2)) >> 2);
            if (total > 2) try out.append(allocator, uuDec(at(src, s + 2)) << 6 | uuDec(at(src, s + 3)));
        }
    }
    // the length the lines declare, which can be shorter than what was decoded
    if (total < out.items.len) out.shrinkRetainingCapacity(total);
    while (out.items.len < total) try out.append(allocator, 0);
    return true;
}

fn native_convert_uuencode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "convert_uuencode", args);
    const s = try p.str(0, "string");
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(ctx.allocator);
    try uuencode(ctx.allocator, s, &out);
    return NativeResult.copyString(ctx.allocator, out.items);
}

fn native_convert_uudecode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "convert_uudecode", args);
    const s = try p.str(0, "string");
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(ctx.allocator);
    if (!try uudecode(ctx.allocator, s, &out)) {
        try docref(ctx, "convert_uudecode", "Argument #1 ($data) is not a valid uuencoded string");
        return NativeResult.scalar(.{ .bool = false });
    }
    return NativeResult.copyString(ctx.allocator, out.items);
}

// php_quot_print_encode: lines of at most 75 characters, never splitting a
// utf-8 sequence; reads past the end see the terminating nul
fn native_quoted_printable_encode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "quoted_printable_encode", args);
    const str = try p.str(0, "string");
    if (str.len == 0) return NativeResult.literal("");
    const maxl = 75;
    const hex = "0123456789ABCDEF";
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(ctx.allocator);
    var lp: usize = 0;
    var i: usize = 0;
    while (i < str.len) {
        const c = str[i];
        i += 1;
        const next: u8 = if (i < str.len) str[i] else 0;
        if (c == '\r' and next == '\n' and i < str.len) {
            try out.appendSlice(ctx.allocator, "\r\n");
            i += 1;
            lp = 0;
        } else if (c < 0x20 or c == 0x7f or c & 0x80 != 0 or c == '=' or (c == ' ' and next == '\r')) {
            lp += 3;
            if ((lp > maxl and c <= 0x7f) or
                (c > 0x7f and c <= 0xdf and lp + 3 > maxl) or
                (c > 0xdf and c <= 0xef and lp + 6 > maxl) or
                (c > 0xef and c <= 0xf4 and lp + 9 > maxl))
            {
                try out.appendSlice(ctx.allocator, "=\r\n");
                lp = 3;
            }
            try out.append(ctx.allocator, '=');
            try out.append(ctx.allocator, hex[c >> 4]);
            try out.append(ctx.allocator, hex[c & 0xf]);
        } else {
            lp += 1;
            if (lp > maxl) {
                try out.appendSlice(ctx.allocator, "=\r\n");
                lp = 1;
            }
            try out.append(ctx.allocator, c);
        }
    }
    return NativeResult.copyString(ctx.allocator, out.items);
}

// php's metaphone (ext/standard/metaphone.c, Michael G Schwern's code),
// with the word read as a c string
fn native_metaphone(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "metaphone", args);
    const raw = try p.str(0, "string");
    const max_phonemes = try p.optLong(1, "max_phonemes", 0);
    if (max_phonemes < 0) return p.valueError(1, "max_phonemes", "must be greater than or equal to 0");
    const word = if (std.mem.indexOfScalar(u8, raw, 0)) |nul| raw[0..nul] else raw;
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(ctx.allocator);
    try metaphone(ctx.allocator, word, @intCast(max_phonemes), &out);
    return NativeResult.copyString(ctx.allocator, out.items);
}

const metaphone_codes = [26]u8{ 1, 16, 4, 16, 9, 2, 4, 16, 9, 2, 0, 2, 2, 2, 1, 4, 0, 2, 4, 4, 1, 0, 0, 0, 8, 0 };

fn mpEncode(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') metaphone_codes[c - 'A'] else 0;
}

fn metaphone(allocator: std.mem.Allocator, word: []const u8, max_phonemes: usize, out: *std.ArrayListUnmanaged(u8)) !void {
    const W = struct {
        w: []const u8,
        fn raw(self: @This(), i: usize) u8 {
            return if (i < self.w.len) self.w[i] else 0;
        }
        fn up(self: @This(), i: usize) u8 {
            return std.ascii.toUpper(self.raw(i));
        }
        fn back(self: @This(), i: usize, n: usize) u8 {
            return if (i >= n) std.ascii.toUpper(self.w[i - n]) else 0;
        }
        fn afterNext(self: @This(), i: usize) u8 {
            return if (self.raw(i + 1) != 0) self.up(i + 2) else 0;
        }
        fn ahead(self: @This(), i: usize, n: usize) u8 {
            var idx: usize = 0;
            while (self.raw(i + idx) != 0 and idx < n) idx += 1;
            return std.ascii.toUpper(self.raw(i + idx));
        }
    };
    const w = W{ .w = word };
    const isvowel = struct {
        fn f(c: u8) bool {
            return mpEncode(c) & 1 != 0;
        }
    }.f;
    var i: usize = 0;
    while (!std.ascii.isAlphabetic(w.raw(i))) : (i += 1) {
        if (w.raw(i) == 0) return;
    }
    const first = w.up(i);
    switch (first) {
        'A' => if (w.up(i + 1) == 'E') {
            try out.append(allocator, 'E');
            i += 2;
        } else {
            try out.append(allocator, 'A');
            i += 1;
        },
        'G', 'K', 'P' => if (w.up(i + 1) == 'N') {
            try out.append(allocator, 'N');
            i += 2;
        },
        'W' => {
            const next = w.up(i + 1);
            if (next == 'R') {
                try out.append(allocator, 'R');
                i += 2;
            } else if (next == 'H' or isvowel(next)) {
                try out.append(allocator, 'W');
                i += 2;
            }
        },
        'X' => {
            try out.append(allocator, 'S');
            i += 1;
        },
        'E', 'I', 'O', 'U' => {
            try out.append(allocator, first);
            i += 1;
        },
        else => {},
    }
    while (w.raw(i) != 0 and (max_phonemes == 0 or out.items.len < max_phonemes)) : (i += 1) {
        var skip: usize = 0;
        if (!std.ascii.isAlphabetic(w.raw(i))) continue;
        const c = w.up(i);
        const prev = w.back(i, 1);
        if (c == prev and c != 'C') continue;
        switch (c) {
            'B' => if (prev != 'M') try out.append(allocator, 'B'),
            'C' => {
                const next = w.up(i + 1);
                if (mpEncode(next) & 8 != 0) {
                    if (next == 'I' and w.afterNext(i) == 'A') {
                        try out.append(allocator, 'X');
                    } else if (prev != 'S') try out.append(allocator, 'S');
                } else if (next == 'H') {
                    try out.append(allocator, 'X');
                    skip += 1;
                } else try out.append(allocator, 'K');
            },
            'D' => if (w.up(i + 1) == 'G' and mpEncode(w.afterNext(i)) & 8 != 0) {
                try out.append(allocator, 'J');
                skip += 1;
            } else try out.append(allocator, 'T'),
            'G' => {
                const next = w.up(i + 1);
                if (next == 'H') {
                    if (!(mpEncode(w.back(i, 3)) & 16 != 0 or w.back(i, 4) == 'H')) {
                        try out.append(allocator, 'F');
                        skip += 1;
                    }
                } else if (next == 'N') {
                    const after = w.afterNext(i);
                    if (!(!std.ascii.isAlphabetic(after) or (after == 'E' and w.ahead(i, 3) == 'D'))) try out.append(allocator, 'K');
                } else if (mpEncode(next) & 8 != 0 and prev != 'G') {
                    try out.append(allocator, 'J');
                } else try out.append(allocator, 'K');
            },
            'H' => if (isvowel(w.up(i + 1)) and mpEncode(prev) & 4 == 0) try out.append(allocator, 'H'),
            'K' => if (prev != 'C') try out.append(allocator, 'K'),
            'P' => try out.append(allocator, if (w.up(i + 1) == 'H') 'F' else 'P'),
            'Q' => try out.append(allocator, 'K'),
            'S' => {
                const next = w.up(i + 1);
                if (next == 'I' and (w.afterNext(i) == 'O' or w.afterNext(i) == 'A')) {
                    try out.append(allocator, 'X');
                } else if (next == 'H') {
                    try out.append(allocator, 'X');
                    skip += 1;
                } else try out.append(allocator, 'S');
            },
            'T' => {
                const next = w.up(i + 1);
                if (next == 'I' and (w.afterNext(i) == 'O' or w.afterNext(i) == 'A')) {
                    try out.append(allocator, 'X');
                } else if (next == 'H') {
                    try out.append(allocator, '0');
                    skip += 1;
                } else if (!(next == 'C' and w.afterNext(i) == 'H')) try out.append(allocator, 'T');
            },
            'V' => try out.append(allocator, 'F'),
            'W' => if (isvowel(w.up(i + 1))) try out.append(allocator, 'W'),
            'X' => try out.appendSlice(allocator, "KS"),
            'Y' => if (isvowel(w.up(i + 1))) try out.append(allocator, 'Y'),
            'Z' => try out.append(allocator, 'S'),
            'F', 'J', 'L', 'M', 'N', 'R' => try out.append(allocator, c),
            else => {},
        }
        i += skip;
    }
}
