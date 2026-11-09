// sscanf and fscanf, ported from php-src's ext/standard/scanf.c (itself
// derived from tcl's scan command). the format is validated up front, then
// scanned against the input; both are treated as C strings, so a NUL byte
// ends either one
const std = @import("std");
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const Value = @import("../runtime/value.zig").Value;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const value_mod = @import("../runtime/value.zig");
const RuntimeError = error{ RuntimeError, OutOfMemory };
const stringParam = @import("strings.zig").stringParam;
const phpTypeName = @import("types.zig").phpTypeName;

pub const entries = .{
    .{ "sscanf", native_sscanf },
    .{ "fscanf", native_fscanf },
};

// scanf.h
const SCAN_MAX_ARGS = 0xFF;
const SCAN_ERROR_EOF: i64 = -1;

const SCAN_NOSKIP: u32 = 0x1;
const SCAN_SUPPRESS: u32 = 0x2;
const SCAN_UNSIGNED: u32 = 0x4;
const SCAN_WIDTH: u32 = 0x8;
const SCAN_SIGNOK: u32 = 0x10;
const SCAN_NODIGITS: u32 = 0x20;
const SCAN_NOZERO: u32 = 0x40;
const SCAN_XOK: u32 = 0x80;
const SCAN_PTOK: u32 = 0x100;
const SCAN_EXPOK: u32 = 0x200;

// the bytes up to the first NUL, with reads past the end giving NUL the way
// walking a C string would
const CStr = struct {
    s: []const u8,

    fn init(bytes: []const u8) CStr {
        const n = std.mem.indexOfScalar(u8, bytes, 0) orelse bytes.len;
        return .{ .s = bytes[0..n] };
    }

    fn at(self: CStr, i: usize) u8 {
        return if (i < self.s.len) self.s[i] else 0;
    }
};

fn isSpace(c: u8) bool {
    return c == ' ' or (c >= '\t' and c <= '\r');
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

// ZEND_STRTOUL over a run of digits starting at i (the callers have checked
// the first one): saturates at ULONG_MAX, returns the value and the index
// after the digits
fn strtoulDigits(f: CStr, i: usize) struct { value: u64, end: usize } {
    var v: u64 = 0;
    var overflow = false;
    var j = i;
    while (isDigit(f.at(j))) : (j += 1) {
        const m = @mulWithOverflow(v, 10);
        const a = @addWithOverflow(m[0], @as(u64, f.at(j) - '0'));
        if (m[1] != 0 or a[1] != 0) overflow = true;
        v = a[0];
    }
    return .{ .value = if (overflow) std.math.maxInt(u64) else v, .end = j };
}

fn digitValue(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'z' => c - 'a' + 10,
        'A'...'Z' => c - 'A' + 10,
        else => null,
    };
}

// strtoll / strtoull over the scanned number buffer. the buffer holds an
// optional sign, an optional 0x for base 16, then digits valid in the base
fn parseInteger(buf: []const u8, base: u8, unsigned: bool) i64 {
    var i: usize = 0;
    var neg = false;
    if (i < buf.len and (buf[i] == '+' or buf[i] == '-')) {
        neg = buf[i] == '-';
        i += 1;
    }
    if (base == 16 and i + 1 < buf.len and buf[i] == '0' and (buf[i + 1] == 'x' or buf[i + 1] == 'X')) {
        if (i + 2 < buf.len and digitValue(buf[i + 2]) != null and digitValue(buf[i + 2]).? < 16) i += 2;
    }
    var mag: u64 = 0;
    var overflow = false;
    while (i < buf.len) : (i += 1) {
        const d = digitValue(buf[i]) orelse break;
        if (d >= base) break;
        const m = @mulWithOverflow(mag, @as(u64, base));
        const a = @addWithOverflow(m[0], @as(u64, d));
        if (m[1] != 0 or a[1] != 0) overflow = true;
        mag = a[0];
    }
    if (unsigned) {
        if (overflow) return -1; // ULONG_MAX
        const u: u64 = if (neg) 0 -% mag else mag;
        return @bitCast(u);
    }
    if (neg) {
        if (overflow or mag > @as(u64, 1) << 63) return std.math.minInt(i64);
        return @bitCast(0 -% mag);
    }
    if (overflow or mag > std.math.maxInt(i64)) return std.math.maxInt(i64);
    return @intCast(mag);
}

// BuildCharSet + CharInSet: php compares the set's members as (signed) chars,
// so a range reaching past 0x7f wraps the way it does there
fn buildCharSet(f: CStr, start_at: usize, set: *[256]bool) usize {
    var format = start_at;
    var exclude = false;
    var ch = format;
    if (f.at(ch) == '^') {
        exclude = true;
        format += 1;
    }
    var members: [256]bool = @splat(false);

    ch = format;
    format += 1;
    var start: u8 = f.at(ch);
    if (f.at(ch) == ']' or f.at(ch) == '-') {
        members[f.at(ch)] = true;
        ch = format;
        format += 1;
    }
    while (f.at(ch) != ']') {
        if (f.at(format) == '-') {
            // maybe the first character of a range, so don't add it yet
            start = f.at(ch);
        } else if (f.at(ch) == '-') {
            if (f.at(format) == ']') {
                // a trailing dash is literal, along with the char before it
                members[start] = true;
                members['-'] = true;
            } else {
                ch = format;
                format += 1;
                const a: i8 = @bitCast(start);
                const b: i8 = @bitCast(f.at(ch));
                const lo = @min(a, b);
                const hi = @max(a, b);
                for (0..256) |c| {
                    const sc: i8 = @bitCast(@as(u8, @intCast(c)));
                    if (lo <= sc and sc <= hi) members[c] = true;
                }
            }
        } else {
            members[f.at(ch)] = true;
        }
        ch = format;
        format += 1;
    }
    for (0..256) |c| set[c] = members[c] != exclude;
    return format;
}

fn valueError(ctx: *NativeContext, msg: []const u8) RuntimeError {
    try ctx.vm.setPendingException("ValueError", msg);
    return error.RuntimeError;
}

// ValidateFormat: checks the format is well formed and that the conversions
// account for exactly the variables passed. returns the number of results
fn validateFormat(ctx: *NativeContext, f: CStr, num_vars: usize) RuntimeError!usize {
    var nassign = std.ArrayListUnmanaged(u32).empty;
    defer nassign.deinit(ctx.allocator);
    try nassign.appendNTimes(ctx.allocator, 0, @max(num_vars, 16));

    var got_xpg = false;
    var got_sequential = false;
    var xpg_size: usize = 0;
    var obj_index: usize = 0;
    var format: usize = 0;

    while (f.at(format) != 0) {
        var ch = format;
        format += 1;
        var flags: u32 = 0;
        if (f.at(ch) != '%') continue;
        ch = format;
        format += 1;
        if (f.at(ch) == '%') continue;

        xpg: {
            if (f.at(ch) == '*') {
                flags |= SCAN_SUPPRESS;
                ch = format;
                format += 1;
                break :xpg;
            }
            if (isDigit(f.at(ch))) {
                // an XPG3 %n$ position; they can't be mixed with plain ones
                const r = strtoulDigits(f, format - 1);
                if (f.at(r.end) == '$') {
                    format = r.end + 1;
                    ch = format;
                    format += 1;
                    got_xpg = true;
                    if (got_sequential) return valueError(ctx, "cannot mix \"%\" and \"%n$\" conversion specifiers");
                    // php keeps the position in an int
                    const value: i32 = @bitCast(@as(u32, @truncate(r.value)));
                    if (value < 1 or (num_vars != 0 and value > num_vars)) return badIndex(ctx, got_xpg);
                    if (num_vars == 0) {
                        if (value > SCAN_MAX_ARGS) return badIndex(ctx, got_xpg);
                        xpg_size = @max(xpg_size, @as(usize, @intCast(value)));
                    }
                    obj_index = @intCast(value - 1);
                    break :xpg;
                }
            }
            got_sequential = true;
            if (got_xpg) return valueError(ctx, "cannot mix \"%\" and \"%n$\" conversion specifiers");
        }

        if (isDigit(f.at(ch))) {
            format = strtoulDigits(f, format - 1).end;
            flags |= SCAN_WIDTH;
            ch = format;
            format += 1;
        }
        // size modifiers are ignored
        if (f.at(ch) == 'l' or f.at(ch) == 'L' or f.at(ch) == 'h') {
            ch = format;
            format += 1;
        }

        if (flags & SCAN_SUPPRESS == 0 and num_vars != 0 and obj_index >= num_vars) return badIndex(ctx, got_xpg);

        switch (f.at(ch)) {
            'n', 'd', 'D', 'i', 'o', 'x', 'X', 'u', 'f', 'e', 'E', 'g', 's', 'c' => {},
            '[' => {
                if (f.at(format) == 0) return valueError(ctx, "Unmatched [ in format string");
                ch = format;
                format += 1;
                if (f.at(ch) == '^') {
                    if (f.at(format) == 0) return valueError(ctx, "Unmatched [ in format string");
                    ch = format;
                    format += 1;
                }
                if (f.at(ch) == ']') {
                    if (f.at(format) == 0) return valueError(ctx, "Unmatched [ in format string");
                    ch = format;
                    format += 1;
                }
                while (f.at(ch) != ']') {
                    if (f.at(format) == 0) return valueError(ctx, "Unmatched [ in format string");
                    ch = format;
                    format += 1;
                }
            },
            else => |c| {
                // php formats the message with %c, and a NUL ends it there
                const msg = if (c == 0)
                    try ctx.allocator.dupe(u8, "Bad scan conversion character \"")
                else
                    try std.fmt.allocPrint(ctx.allocator, "Bad scan conversion character \"{c}\"", .{c});
                defer ctx.allocator.free(msg);
                return valueError(ctx, msg);
            },
        }

        if (flags & SCAN_SUPPRESS == 0) {
            if (obj_index >= nassign.items.len) {
                const grow_to = if (xpg_size != 0) @max(xpg_size, obj_index + 1) else nassign.items.len + 16;
                try nassign.appendNTimes(ctx.allocator, 0, grow_to - nassign.items.len);
            }
            nassign.items[obj_index] += 1;
            obj_index += 1;
        }
    }

    const total = if (num_vars != 0) num_vars else if (xpg_size != 0) xpg_size else obj_index;
    for (0..total) |i| {
        const n = if (i < nassign.items.len) nassign.items[i] else 0;
        if (n > 1) return valueError(ctx, "Variable is assigned by multiple \"%n$\" conversion specifiers");
        if (xpg_size == 0 and n == 0) return valueError(ctx, "Variable is not assigned by any conversion specifiers");
    }
    return total;
}

fn badIndex(ctx: *NativeContext, got_xpg: bool) RuntimeError {
    if (got_xpg) return valueError(ctx, "\"%n$\" argument index out of range");
    return valueError(ctx, "Different numbers of variable names and field specifiers");
}

// where the scanned values go: the caller's variables or the result array
const Sink = struct {
    ctx: *NativeContext,
    num_vars: usize,
    arg_offset: usize,
    arg_count: usize,
    slots: []Value,

    fn put(self: *Sink, index: usize, v: Value) void {
        if (self.num_vars != 0) {
            self.ctx.setCallerVar(self.arg_offset + index, self.arg_count, v);
            if (v == .string) v.string.release();
        } else {
            if (index >= self.slots.len) {
                if (v == .string) v.string.release();
                return;
            }
            const old = self.slots[index];
            if (old == .string) old.string.release();
            self.slots[index] = v;
        }
    }

    fn putString(self: *Sink, index: usize, bytes: []const u8) !void {
        self.put(index, .{ .string = try Value.String.create(self.ctx.allocator, bytes) });
    }
};

// php_sscanf_internal. vars are the by-reference arguments, which start at
// args[arg_offset]
fn scan(ctx: *NativeContext, input: []const u8, format_bytes: []const u8, args: []const Value, arg_offset: usize) RuntimeError!NativeResult {
    const f = CStr.init(format_bytes);
    const s = CStr.init(input);
    const num_vars = args.len - arg_offset;

    const total_vars = try validateFormat(ctx, f, num_vars);

    const slots = try ctx.allocator.alloc(Value, if (num_vars == 0) total_vars else 0);
    @memset(slots, .null);
    var sink = Sink{ .ctx = ctx, .num_vars = num_vars, .arg_offset = arg_offset, .arg_count = args.len, .slots = slots };
    defer {
        for (slots) |v| if (v == .string) v.string.release();
        ctx.allocator.free(slots);
    }

    var obj_index: usize = 0;
    var string: usize = 0;
    var format: usize = 0;
    var nconversions: i64 = 0;
    var underflow = false;
    var op: u8 = 0;
    var base: u8 = 0;
    var unsigned_fn = false;
    var buf: [64]u8 = undefined;

    scanning: while (f.at(format) != 0) {
        var ch = format;
        format += 1;
        var flags: u32 = 0;

        // whitespace in the format skips whitespace in the input
        if (isSpace(f.at(ch))) {
            while (isSpace(s.at(string))) string += 1;
            continue;
        }

        literal: {
            if (f.at(ch) != '%') break :literal;
            ch = format;
            format += 1;
            if (f.at(ch) == '%') break :literal;

            if (f.at(ch) == '*') {
                flags |= SCAN_SUPPRESS;
                ch = format;
                format += 1;
            } else if (isDigit(f.at(ch))) {
                const r = strtoulDigits(f, format - 1);
                if (f.at(r.end) == '$') {
                    format = r.end + 1;
                    ch = format;
                    format += 1;
                    const value: i32 = @bitCast(@as(u32, @truncate(r.value)));
                    obj_index = @intCast(value - 1);
                }
            }

            var width: u64 = 0;
            if (isDigit(f.at(ch))) {
                const r = strtoulDigits(f, format - 1);
                width = r.value;
                format = r.end;
                ch = format;
                format += 1;
            }
            if (f.at(ch) == 'l' or f.at(ch) == 'L' or f.at(ch) == 'h') {
                ch = format;
                format += 1;
            }

            switch (f.at(ch)) {
                'n' => {
                    if (flags & SCAN_SUPPRESS == 0) {
                        sink.put(obj_index, .{ .int = @intCast(string) });
                        obj_index += 1;
                    }
                    nconversions += 1;
                    continue :scanning;
                },
                'd', 'D' => {
                    op = 'i';
                    base = 10;
                    unsigned_fn = false;
                },
                'i' => {
                    op = 'i';
                    base = 0;
                    unsigned_fn = false;
                },
                'o' => {
                    op = 'i';
                    base = 8;
                    unsigned_fn = false;
                },
                'x', 'X' => {
                    op = 'i';
                    base = 16;
                    unsigned_fn = false;
                },
                'u' => {
                    op = 'i';
                    base = 10;
                    flags |= SCAN_UNSIGNED;
                    unsigned_fn = true;
                },
                'f', 'e', 'E', 'g' => op = 'f',
                's' => op = 's',
                'c' => {
                    op = 's';
                    flags |= SCAN_NOSKIP;
                    if (width == 0) width = 1;
                },
                '[' => {
                    op = '[';
                    flags |= SCAN_NOSKIP;
                },
                else => {},
            }

            // every conversion from here on needs input
            if (s.at(string) == 0) {
                underflow = true;
                break :scanning;
            }
            if (flags & SCAN_NOSKIP == 0) {
                while (isSpace(s.at(string))) string += 1;
                if (s.at(string) == 0) {
                    underflow = true;
                    break :scanning;
                }
            }

            switch (op) {
                's' => {
                    // up to width characters or whitespace (%c stops there too)
                    if (width == 0) width = std.math.maxInt(u64);
                    var end = string;
                    while (s.at(end) != 0) {
                        if (isSpace(s.at(end))) break;
                        end += 1;
                        width -= 1;
                        if (width == 0) break;
                    }
                    if (flags & SCAN_SUPPRESS == 0) {
                        try sink.putString(obj_index, s.s[string..end]);
                        obj_index += 1;
                    }
                    string = end;
                },
                '[' => {
                    if (width == 0) width = std.math.maxInt(u64);
                    var set: [256]bool = undefined;
                    format = buildCharSet(f, format, &set);
                    var end = string;
                    while (s.at(end) != 0) {
                        if (!set[s.at(end)]) break;
                        end += 1;
                        width -= 1;
                        if (width == 0) break;
                    }
                    // nothing matched the set, stop
                    if (end == string) break :scanning;
                    if (flags & SCAN_SUPPRESS == 0) {
                        try sink.putString(obj_index, s.s[string..end]);
                        obj_index += 1;
                    }
                    string = end;
                },
                'i' => {
                    if (width == 0 or width > buf.len - 1) width = buf.len - 1;
                    flags |= SCAN_SIGNOK | SCAN_NODIGITS | SCAN_NOZERO;
                    var end: usize = 0;
                    while (width > 0) : (width -= 1) {
                        const c = s.at(string);
                        const accept = switch (c) {
                            // a leading 0 means base 8, or 16 if an x follows
                            '0' => blk: {
                                if (base == 16) flags |= SCAN_XOK;
                                if (base == 0) {
                                    base = 8;
                                    flags |= SCAN_XOK;
                                }
                                if (flags & SCAN_NOZERO != 0) {
                                    flags &= ~(SCAN_SIGNOK | SCAN_NODIGITS | SCAN_NOZERO);
                                } else {
                                    flags &= ~(SCAN_SIGNOK | SCAN_XOK | SCAN_NODIGITS);
                                }
                                break :blk true;
                            },
                            '1'...'7' => blk: {
                                if (base == 0) base = 10;
                                flags &= ~(SCAN_SIGNOK | SCAN_XOK | SCAN_NODIGITS);
                                break :blk true;
                            },
                            '8', '9' => blk: {
                                if (base == 0) base = 10;
                                if (base <= 8) break :blk false;
                                flags &= ~(SCAN_SIGNOK | SCAN_XOK | SCAN_NODIGITS);
                                break :blk true;
                            },
                            'A'...'F', 'a'...'f' => blk: {
                                if (base <= 10) break :blk false;
                                flags &= ~(SCAN_SIGNOK | SCAN_XOK | SCAN_NODIGITS);
                                break :blk true;
                            },
                            '+', '-' => blk: {
                                if (flags & SCAN_SIGNOK == 0) break :blk false;
                                flags &= ~SCAN_SIGNOK;
                                break :blk true;
                            },
                            'x', 'X' => blk: {
                                if (flags & SCAN_XOK == 0 or end != 1) break :blk false;
                                base = 16;
                                flags &= ~SCAN_XOK;
                                break :blk true;
                            },
                            else => false,
                        };
                        if (!accept) break;
                        buf[end] = c;
                        end += 1;
                        string += 1;
                        if (s.at(string) == 0) break;
                    }

                    // back up over a lone sign or a trailing x after a 0
                    if (flags & SCAN_NODIGITS != 0) {
                        if (s.at(string) == 0) underflow = true;
                        break :scanning;
                    } else if (buf[end - 1] == 'x' or buf[end - 1] == 'X') {
                        end -= 1;
                        string -= 1;
                    }

                    if (flags & SCAN_SUPPRESS == 0) {
                        const value = parseInteger(buf[0..end], base, unsigned_fn);
                        if (flags & SCAN_UNSIGNED != 0 and value < 0) {
                            // too big for a php int, so it comes back as a string
                            var tmp: [32]u8 = undefined;
                            const text = std.fmt.bufPrint(&tmp, "{d}", .{@as(u64, @bitCast(value))}) catch unreachable;
                            try sink.putString(obj_index, text);
                        } else {
                            sink.put(obj_index, .{ .int = value });
                        }
                        obj_index += 1;
                    }
                },
                'f' => {
                    if (width == 0 or width > buf.len - 1) width = buf.len - 1;
                    flags |= SCAN_SIGNOK | SCAN_NODIGITS | SCAN_PTOK | SCAN_EXPOK;
                    var end: usize = 0;
                    while (width > 0) : (width -= 1) {
                        const c = s.at(string);
                        const accept = switch (c) {
                            '0'...'9' => blk: {
                                flags &= ~(SCAN_SIGNOK | SCAN_NODIGITS);
                                break :blk true;
                            },
                            '+', '-' => blk: {
                                if (flags & SCAN_SIGNOK == 0) break :blk false;
                                flags &= ~SCAN_SIGNOK;
                                break :blk true;
                            },
                            '.' => blk: {
                                if (flags & SCAN_PTOK == 0) break :blk false;
                                flags &= ~(SCAN_SIGNOK | SCAN_PTOK);
                                break :blk true;
                            },
                            // an exponent needs a digit before it
                            'e', 'E' => blk: {
                                if (flags & (SCAN_NODIGITS | SCAN_EXPOK) != SCAN_EXPOK) break :blk false;
                                flags = (flags & ~(SCAN_EXPOK | SCAN_PTOK)) | SCAN_SIGNOK | SCAN_NODIGITS;
                                break :blk true;
                            },
                            else => false,
                        };
                        if (!accept) break;
                        buf[end] = c;
                        end += 1;
                        string += 1;
                        if (s.at(string) == 0) break;
                    }

                    if (flags & SCAN_NODIGITS != 0) {
                        if (flags & SCAN_EXPOK != 0) {
                            // no digits at all
                            if (s.at(string) == 0) underflow = true;
                            break :scanning;
                        }
                        // a bad exponent: back up over the e and maybe a sign
                        end -= 1;
                        string -= 1;
                        if (buf[end] != 'e' and buf[end] != 'E') {
                            end -= 1;
                            string -= 1;
                        }
                    }

                    if (flags & SCAN_SUPPRESS == 0) {
                        const d = std.fmt.parseFloat(f64, buf[0..end]) catch 0.0;
                        sink.put(obj_index, .{ .float = d });
                        obj_index += 1;
                    }
                },
                else => {},
            }
            nconversions += 1;
            continue :scanning;
        }

        // a literal character (or %%) must match the input
        if (s.at(string) == 0) {
            underflow = true;
            break :scanning;
        }
        const sch = s.at(string);
        string += 1;
        if (f.at(ch) != sch) break :scanning;
    }

    if (underflow and nconversions == 0) {
        if (num_vars != 0) return NativeResult.scalar(.{ .int = SCAN_ERROR_EOF });
        return NativeResult.scalar(.null);
    }
    if (num_vars != 0) return NativeResult.scalar(.{ .int = nconversions });

    var arr = try ctx.createArray();
    for (slots) |v| try arr.append(ctx.allocator, v);
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_sscanf(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const input = try stringParam(ctx, "sscanf", args, 0, "string");
    const format = try stringParam(ctx, "sscanf", args, 1, "format");
    return scan(ctx, input, format, args, 2);
}

fn native_fscanf(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const v: Value = if (args.len > 0) args[0] else .null;
    if (v != .resource) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "fscanf(): Argument #1 ($stream) must be of type resource, {s} given", .{phpTypeName(v)});
        defer ctx.allocator.free(msg);
        try ctx.vm.setPendingException("TypeError", msg);
        return error.RuntimeError;
    }
    const format = try stringParam(ctx, "fscanf", args, 1, "format");
    const r = v.resource;
    const is_stream = std.mem.eql(u8, r.class_name, "FileHandle") or std.mem.eql(u8, r.class_name, "DirectoryHandle");
    if (!is_stream or value_mod.resourceClosed(r)) {
        try ctx.vm.setPendingException("TypeError", "fscanf(): supplied resource is not a valid File-Handle resource");
        return error.RuntimeError;
    }

    const line = (try @import("filesystem.zig").readLine(ctx, r, std.math.maxInt(usize))) orelse
        return NativeResult.scalar(.{ .bool = false });
    defer line.release();
    return scan(ctx, line.bytes(), format, args, 2);
}
