// php's ext/json: json_encode (json_encoder.c), json_decode and
// json_validate (the re2c scanner json_scanner.re and the bison grammar
// json_parser.y, here a scanner and a recursive descent parser that read
// tokens where php's LALR parser does, so the first error it meets and its
// code are php's), and json_last_error / json_last_error_msg
const std = @import("std");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const PhpArray = value_mod.PhpArray;
const PhpObject = value_mod.PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const NativeResult = vm_mod.NativeResult;
const RuntimeError = error{ RuntimeError, OutOfMemory };
const object_properties = @import("../runtime/object_properties.zig");
const Args = @import("string_ports.zig").Args;
const html = @import("html.zig");

const HEX_TAG: i64 = 1 << 0;
const HEX_AMP: i64 = 1 << 1;
const HEX_APOS: i64 = 1 << 2;
const HEX_QUOT: i64 = 1 << 3;
const FORCE_OBJECT: i64 = 1 << 4;
const NUMERIC_CHECK: i64 = 1 << 5;
const UNESCAPED_SLASHES: i64 = 1 << 6;
const PRETTY_PRINT: i64 = 1 << 7;
const UNESCAPED_UNICODE: i64 = 1 << 8;
const PARTIAL_OUTPUT_ON_ERROR: i64 = 1 << 9;
const PRESERVE_ZERO_FRACTION: i64 = 1 << 10;
const UNESCAPED_LINE_TERMINATORS: i64 = 1 << 11;
const OBJECT_AS_ARRAY: i64 = 1 << 0;
const BIGINT_AS_STRING: i64 = 1 << 1;
const INVALID_UTF8_IGNORE: i64 = 1 << 20;
const INVALID_UTF8_SUBSTITUTE: i64 = 1 << 21;
const THROW_ON_ERROR: i64 = 1 << 22;

const default_depth = 512;

const ErrorCode = enum(i64) {
    none = 0,
    depth,
    state_mismatch,
    ctrl_char,
    syntax,
    utf8,
    recursion,
    inf_or_nan,
    unsupported_type,
    invalid_property_name,
    utf16,
    non_backed_enum,

    fn message(self: ErrorCode) []const u8 {
        return switch (self) {
            .none => "No error",
            .depth => "Maximum stack depth exceeded",
            .state_mismatch => "State mismatch (invalid or malformed JSON)",
            .ctrl_char => "Control character error, possibly incorrectly encoded",
            .syntax => "Syntax error",
            .utf8 => "Malformed UTF-8 characters, possibly incorrectly encoded",
            .recursion => "Recursion detected",
            .inf_or_nan => "Inf and NaN cannot be JSON encoded",
            .unsupported_type => "Type is not supported",
            .invalid_property_name => "The decoded property name is invalid",
            .utf16 => "Single unpaired UTF-16 surrogate in unicode escape",
            .non_backed_enum => "Non-backed enums have no default serialization",
        };
    }
};

// JSON_G(error_code)
threadlocal var last_error: ErrorCode = .none;

pub const entries = .{
    .{ "json_encode", json_encode },
    .{ "json_decode", json_decode },
    .{ "json_last_error", native_json_last_error },
    .{ "json_last_error_msg", native_json_last_error_msg },
    .{ "json_validate", json_validate },
};

fn throwJsonException(ctx: *NativeContext, code: ErrorCode) RuntimeError {
    try ctx.vm.setPendingException("JsonException", code.message());
    // the exception's code is the json error code
    if (ctx.vm.pending_exception) |exc| if (exc == .object) try exc.object.set(ctx.allocator, "code", .{ .int = @backingInt(code) });
    return error.RuntimeError;
}

fn throwValueError(ctx: *NativeContext, comptime fmt: []const u8, args: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("ValueError", msg);
    return error.RuntimeError;
}

// ---------------------------------------------------------------------------
// encoding

const Recursion = value_mod.Recursion;

const Encoder = struct {
    buf: std.ArrayListUnmanaged(u8) = .empty,
    a: std.mem.Allocator,
    vm: *VM,
    depth: i64 = 0,
    max_depth: i64,
    error_code: ErrorCode = .none,

    fn append(self: *Encoder, bytes: []const u8) RuntimeError!void {
        try self.buf.appendSlice(self.a, bytes);
    }

    fn appendByte(self: *Encoder, c: u8) RuntimeError!void {
        try self.buf.append(self.a, c);
    }

    // smart_str_append_long
    fn appendLong(self: *Encoder, i: i64) RuntimeError!void {
        var tmp: [24]u8 = undefined;
        var at: usize = tmp.len;
        var u: u64 = @abs(i);
        while (true) {
            at -= 1;
            tmp[at] = @intCast('0' + u % 10);
            u /= 10;
            if (u == 0) break;
        }
        if (i < 0) {
            at -= 1;
            tmp[at] = '-';
        }
        try self.append(tmp[at..]);
    }

    fn prettyChar(self: *Encoder, options: i64, c: u8) RuntimeError!void {
        if (options & PRETTY_PRINT != 0) try self.appendByte(c);
    }

    fn prettyIndent(self: *Encoder, options: i64) RuntimeError!void {
        if (options & PRETTY_PRINT == 0) return;
        var i: i64 = 0;
        while (i < self.depth) : (i += 1) try self.append("    ");
    }

    // php_json_encode_double
    fn double(self: *Encoder, d: f64, options: i64) RuntimeError!void {
        var tmp: [1100]u8 = undefined;
        const sp = value_mod.hooks().serialize_precision;
        const text = @import("formatted_print.zig").gcvt(d, sp, '.', 'e', &tmp);
        try self.append(text);
        if (options & PRESERVE_ZERO_FRACTION != 0 and std.mem.indexOfScalar(u8, text, '.') == null) try self.append(".0");
    }

    // php_json_encode_zval: false is php's FAILURE; a thrown exception is
    // error.RuntimeError
    fn zval(self: *Encoder, val: Value, options: i64) RuntimeError!bool {
        switch (val) {
            .null, .undef => try self.append("null"),
            .bool => |b| try self.append(if (b) "true" else "false"),
            .int => |i| try self.appendLong(i),
            .float => |d| {
                if (std.math.isNan(d) or std.math.isInf(d)) {
                    self.error_code = .inf_or_nan;
                    try self.appendByte('0');
                } else {
                    try self.double(d, options);
                }
            },
            .string => |s| return self.escapeString(s.bytes(), options),
            .array => |arr| return self.array(arr, options),
            .object => |proxy| return self.object(proxy, options),
            // a generator or fiber has no properties to list
            .generator, .fiber => return self.emptyObject(options),
            .resource => {
                self.error_code = .unsupported_type;
                if (options & PARTIAL_OUTPUT_ON_ERROR != 0) try self.append("null");
                return false;
            },
        }
        return true;
    }

    fn stackExhausted(self: *Encoder, options: i64) RuntimeError!bool {
        if (!vm_mod.stack_limit.overflowed()) return false;
        self.error_code = .depth;
        if (options & PARTIAL_OUTPUT_ON_ERROR != 0) try self.append("null");
        return true;
    }

    // the end of php_json_encode_array: the depth error is found once the
    // container's contents are written
    fn closeContainer(self: *Encoder, options: i64, need_comma: bool, close: u8) RuntimeError!bool {
        if (self.depth > self.max_depth) {
            self.error_code = .depth;
            if (options & PARTIAL_OUTPUT_ON_ERROR == 0) return false;
        }
        self.depth -= 1;
        if (need_comma) {
            try self.prettyChar(options, '\n');
            try self.prettyIndent(options);
        }
        try self.appendByte(close);
        return true;
    }

    fn emptyObject(self: *Encoder, options: i64) RuntimeError!bool {
        if (try self.stackExhausted(options)) return false;
        try self.appendByte('{');
        self.depth += 1;
        return self.closeContainer(options, false, '}');
    }

    fn array(self: *Encoder, arr: *PhpArray, options: i64) RuntimeError!bool {
        if (try self.stackExhausted(options)) return false;
        if (arr.recursion & Recursion.gc != 0) {
            self.error_code = .recursion;
            try self.append("null");
            return false;
        }
        arr.recursion |= Recursion.gc;
        defer arr.recursion &= ~Recursion.gc;
        const as_object = options & FORCE_OBJECT != 0 or !isList(arr);
        try self.appendByte(if (as_object) '{' else '[');
        self.depth += 1;
        var need_comma = false;
        var i: usize = 0;
        while (i < arr.entries.items.len) : (i += 1) {
            const entry = arr.entries.items[i];
            const v = if (entry.ref) |cell| cell.* else entry.value;
            if (need_comma) try self.appendByte(',') else need_comma = true;
            try self.prettyChar(options, '\n');
            try self.prettyIndent(options);
            if (as_object) {
                switch (entry.key) {
                    .string => |k| try self.key(k.bytes(), options),
                    .int => |n| {
                        try self.appendByte('"');
                        try self.appendLong(n);
                        try self.appendByte('"');
                    },
                }
                try self.appendByte(':');
                try self.prettyChar(options, ' ');
            }
            if (!try self.zval(v, options) and options & PARTIAL_OUTPUT_ON_ERROR == 0) return false;
        }
        return self.closeContainer(options, need_comma, if (as_object) '}' else ']');
    }

    // a key is escaped without the numeric check; with partial output an
    // invalid one becomes ""
    fn key(self: *Encoder, k: []const u8, options: i64) RuntimeError!void {
        if (!try self.escapeString(k, options & ~NUMERIC_CHECK)) {
            if (options & PARTIAL_OUTPUT_ON_ERROR != 0) {
                self.buf.items.len -= 4;
                try self.append("\"\"");
            }
        }
    }

    fn object(self: *Encoder, proxy: *PhpObject, options: i64) RuntimeError!bool {
        const vm = self.vm;
        try vm.triggerLazyInit(proxy);
        if (vm.pending_exception != null) return error.RuntimeError;
        const obj = proxy.storage();
        if (vm.isInstanceOf(obj.class_name, "JsonSerializable")) return self.serializable(obj, options);
        if (vm.classes.get(obj.class_name)) |cd| if (cd.is_enum) {
            if (cd.backed_type == .none) {
                self.error_code = .non_backed_enum;
                try self.appendByte('0');
                return false;
            }
            return self.zval(obj.get("value"), options);
        };
        if (std.mem.eql(u8, obj.class_name, "SimpleXMLElement")) {
            // simplexml's json table: attributes under "@attributes",
            // same-named children grouped
            var nctx = vm.makeContext(null);
            if (@import("simplexml.zig").elementToJsonValue(&nctx, obj) catch null) |built| {
                return self.zval(built, options);
            }
        }
        if (std.mem.eql(u8, obj.class_name, "SplFixedArray")) {
            const data = obj.get("__data");
            if (data == .array) return self.zval(data, options);
        }
        return self.objectProperties(obj, options);
    }

    // php_json_encode_array for an object: its json property table
    fn objectProperties(self: *Encoder, obj: *PhpObject, options: i64) RuntimeError!bool {
        if (try self.stackExhausted(options)) return false;
        if (obj.recursion & Recursion.gc != 0) {
            self.error_code = .recursion;
            try self.append("null");
            return false;
        }
        obj.recursion |= Recursion.gc;
        defer obj.recursion &= ~Recursion.gc;
        var listing = try object_properties.list(self.vm, obj, .json, self.a);
        defer listing.deinit(self.a);
        const holder = listing.takeHolder();
        defer object_properties.releaseHolder(self.vm, holder);
        if (self.vm.pending_exception != null) return error.RuntimeError;
        try self.appendByte('{');
        self.depth += 1;
        var need_comma = false;
        for (listing.items.items) |prop| {
            if (prop.visibility != .public) continue;
            if (need_comma) try self.appendByte(',') else need_comma = true;
            try self.prettyChar(options, '\n');
            try self.prettyIndent(options);
            switch (prop.key) {
                .name => |name| try self.key(name, options),
                .int => |n| {
                    try self.appendByte('"');
                    try self.appendLong(n);
                    try self.appendByte('"');
                },
            }
            try self.appendByte(':');
            try self.prettyChar(options, ' ');
            if (!try self.zval(prop.value, options) and options & PARTIAL_OUTPUT_ON_ERROR == 0) return false;
        }
        return self.closeContainer(options, need_comma, '}');
    }

    // php_json_encode_serializable_object
    fn serializable(self: *Encoder, obj: *PhpObject, options: i64) RuntimeError!bool {
        if (obj.recursion & Recursion.json != 0) {
            self.error_code = .recursion;
            if (options & PARTIAL_OUTPUT_ON_ERROR != 0) try self.append("null");
            return false;
        }
        obj.recursion |= Recursion.json;
        var guarded = true;
        defer if (guarded) {
            obj.recursion &= ~Recursion.json;
        };
        const result = self.vm.callMethod(obj, "jsonSerialize", &.{}) catch return error.RuntimeError;
        // an object that serializes to itself is encoded by its properties,
        // with the guard already lifted
        if (result == .object and result.object.storage() == obj) {
            obj.recursion &= ~Recursion.json;
            guarded = false;
            return self.objectProperties(obj, options);
        }
        return self.zval(result, options);
    }

    // which bytes php_json_escape_string can't copy as they are
    const special = blk: {
        var t: [256]bool = @splat(false);
        for (0..0x20) |c| t[c] = true;
        for ("\"&'/<>\\") |c| t[c] = true;
        for (0x80..0x100) |c| t[c] = true;
        break :blk t;
    };

    // php_json_escape_string
    fn escapeString(self: *Encoder, s_in: []const u8, options: i64) RuntimeError!bool {
        if (s_in.len == 0) {
            try self.append("\"\"");
            return true;
        }
        if (options & NUMERIC_CHECK != 0) if (numericValue(s_in)) |n| switch (n) {
            .int => |i| {
                try self.appendLong(i);
                return true;
            },
            .float => |d| if (!std.math.isNan(d) and !std.math.isInf(d)) {
                try self.double(d, options);
                return true;
            },
            else => {},
        };
        const checkpoint = self.buf.items.len;
        const s = s_in;
        var pos: usize = 0;
        while (pos < s.len and !special[s[pos]]) pos += 1;
        try self.buf.ensureUnusedCapacity(self.a, s.len + 2);
        self.buf.appendAssumeCapacity('"');
        if (pos == s.len) {
            // nothing to escape, the common case
            self.buf.appendSliceAssumeCapacity(s);
            self.buf.appendAssumeCapacity('"');
            return true;
        }
        var start: usize = 0;
        while (pos < s.len) {
            const c = s[pos];
            if (!special[c]) {
                pos += 1;
                continue;
            }
            if (pos > start) try self.append(s[start..pos]);
            if (c >= 0x80) {
                var next = pos;
                const cp = html.nextUtf8Char(s, &next);
                if (cp == null) {
                    if (options & INVALID_UTF8_IGNORE != 0) {
                        // dropped
                    } else if (options & INVALID_UTF8_SUBSTITUTE != 0) {
                        try self.append(if (options & UNESCAPED_UNICODE != 0) "\xef\xbf\xbd" else "\\ufffd");
                    } else {
                        self.buf.items.len = checkpoint;
                        self.error_code = .utf8;
                        if (options & PARTIAL_OUTPUT_ON_ERROR != 0) try self.append("null");
                        return false;
                    }
                } else {
                    const us = cp.?;
                    if (options & UNESCAPED_UNICODE != 0 and (options & UNESCAPED_LINE_TERMINATORS != 0 or us < 0x2028 or us > 0x2029)) {
                        try self.append(s[pos..next]);
                    } else if (us >= 0x10000) {
                        const v = us - 0x10000;
                        try self.unicodeEscape(@intCast((v >> 10) | 0xd800));
                        try self.unicodeEscape(@intCast((v & 0x3ff) | 0xdc00));
                    } else {
                        try self.unicodeEscape(@intCast(us));
                    }
                }
                pos = next;
                start = pos;
                continue;
            }
            switch (c) {
                '"' => try self.append(if (options & HEX_QUOT != 0) "\\u0022" else "\\\""),
                '\\' => try self.append("\\\\"),
                '/' => try self.append(if (options & UNESCAPED_SLASHES != 0) "/" else "\\/"),
                0x08 => try self.append("\\b"),
                0x0c => try self.append("\\f"),
                '\n' => try self.append("\\n"),
                '\r' => try self.append("\\r"),
                '\t' => try self.append("\\t"),
                '<' => try self.append(if (options & HEX_TAG != 0) "\\u003C" else "<"),
                '>' => try self.append(if (options & HEX_TAG != 0) "\\u003E" else ">"),
                '&' => try self.append(if (options & HEX_AMP != 0) "\\u0026" else "&"),
                '\'' => try self.append(if (options & HEX_APOS != 0) "\\u0027" else "'"),
                else => try self.unicodeEscape(c),
            }
            pos += 1;
            start = pos;
        }
        if (pos > start) try self.append(s[start..pos]);
        try self.appendByte('"');
        return true;
    }

    fn unicodeEscape(self: *Encoder, us: u16) RuntimeError!void {
        const digits = "0123456789abcdef";
        const out = [6]u8{ '\\', 'u', digits[(us >> 12) & 0xf], digits[(us >> 8) & 0xf], digits[(us >> 4) & 0xf], digits[us & 0xf] };
        try self.append(&out);
    }
};

// is_numeric_string without errors: an int, a float, or null
fn numericValue(s: []const u8) ?Value {
    if (!Value.isNumericString(s)) return null;
    const trimmed = std.mem.trim(u8, s, " \t\n\r\x0b\x0c");
    if (std.mem.indexOfAny(u8, trimmed, ".eE") == null) {
        if (std.fmt.parseInt(i64, trimmed, 10)) |i| return .{ .int = i } else |_| {}
    }
    return .{ .float = Value.toFloat(.{ .string = Value.String.borrowed(trimmed) }) };
}

// zend_array_is_list
fn isList(arr: *const PhpArray) bool {
    for (arr.entries.items, 0..) |entry, idx| {
        if (entry.key != .int or entry.key.int != @as(i64, @intCast(idx))) return false;
    }
    return true;
}

fn json_encode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "json_encode", args);
    const value: Value = if (args.len > 0) args[0] else .null;
    const options = try p.optLong(1, "flags", 0);
    const depth = try p.optLong(2, "depth", default_depth);
    var enc: Encoder = .{ .a = ctx.allocator, .vm = ctx.vm, .max_depth = @as(i32, @truncate(depth)) };
    defer enc.buf.deinit(ctx.allocator);
    try enc.buf.ensureTotalCapacity(ctx.allocator, 128);
    _ = try enc.zval(value, options);
    if (options & THROW_ON_ERROR == 0 or options & PARTIAL_OUTPUT_ON_ERROR != 0) {
        last_error = enc.error_code;
        if (enc.error_code != .none and options & PARTIAL_OUTPUT_ON_ERROR == 0) return NativeResult.scalar(.{ .bool = false });
    } else if (enc.error_code != .none) {
        return throwJsonException(ctx, enc.error_code);
    }
    const out = try enc.buf.toOwnedSlice(ctx.allocator);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

// ---------------------------------------------------------------------------
// decoding

const Token = enum { lbrace, rbrace, lbracket, rbracket, colon, comma, null_, true_, false_, int, double, string, eoi, err };

const Parser = struct {
    ctx: *NativeContext,
    s: []const u8,
    cursor: usize = 0,
    options: i64,
    depth: i64 = 1,
    max_depth: i64,
    validate: bool,
    errcode: ErrorCode = .none,
    // the scanned token's value: an int, a float, or a string the parser
    // takes over
    value: Value = .null,
    scratch: std.ArrayListUnmanaged(u8) = .empty,

    fn at(self: *const Parser, i: usize) u8 {
        return if (i < self.s.len) self.s[i] else 0;
    }

    fn fail(self: *Parser, code: ErrorCode) Token {
        self.errcode = code;
        return .err;
    }

    // php_json_scan
    fn scan(self: *Parser) RuntimeError!Token {
        self.value = .null;
        while (true) {
            const start = self.cursor;
            const c = self.at(start);
            switch (c) {
                ' ', '\t', '\r', '\n' => {
                    self.cursor += 1;
                    continue;
                },
                '{' => return self.single(.lbrace),
                '}' => return self.single(.rbrace),
                '[' => return self.single(.lbracket),
                ']' => return self.single(.rbracket),
                ':' => return self.single(.colon),
                ',' => return self.single(.comma),
                '"' => return self.string(),
                '-', '0'...'9' => return self.number(),
                0 => {
                    if (start >= self.s.len) {
                        self.cursor = start + 1;
                        return .eoi;
                    }
                    return self.fail(.ctrl_char);
                },
                else => {
                    if (std.mem.startsWith(u8, self.s[start..], "null")) return self.literal(.null_, 4);
                    if (std.mem.startsWith(u8, self.s[start..], "true")) return self.literal(.true_, 4);
                    if (std.mem.startsWith(u8, self.s[start..], "false")) return self.literal(.false_, 5);
                    if (c < 0x20) return self.fail(.ctrl_char);
                    if (utf8Len(self.s, start) != 0) return self.fail(.syntax);
                    return self.fail(.utf8);
                },
            }
        }
    }

    fn single(self: *Parser, t: Token) Token {
        self.cursor += 1;
        return t;
    }

    fn literal(self: *Parser, t: Token, len: usize) Token {
        self.cursor += len;
        return t;
    }

    // INT, FLOAT and EXP; a "-" that starts none of them is the UTF8 rule's
    // syntax error
    fn number(self: *Parser) RuntimeError!Token {
        const start = self.cursor;
        var i = start;
        const negative = self.at(i) == '-';
        if (negative) i += 1;
        if (self.at(i) == '0') {
            i += 1;
        } else if (self.at(i) >= '1' and self.at(i) <= '9') {
            while (std.ascii.isDigit(self.at(i))) i += 1;
        } else {
            return self.fail(.syntax);
        }
        var is_double = false;
        if (self.at(i) == '.' and std.ascii.isDigit(self.at(i + 1))) {
            i += 1;
            while (std.ascii.isDigit(self.at(i))) i += 1;
            is_double = true;
        }
        if (self.at(i) == 'e' or self.at(i) == 'E') {
            var j = i + 1;
            if (self.at(j) == '+' or self.at(j) == '-') j += 1;
            if (std.ascii.isDigit(self.at(j))) {
                while (std.ascii.isDigit(self.at(j))) j += 1;
                i = j;
                is_double = true;
            }
        }
        self.cursor = i;
        const text = self.s[start..i];
        if (is_double) {
            self.value = .{ .float = std.fmt.parseFloat(f64, text) catch 0 };
            return .double;
        }
        // PHP_JSON_INT_MAX_LENGTH: 19 digits may still fit in a long
        const digits = text.len - @intFromBool(negative);
        var bigint = false;
        if (digits >= 19) {
            if (digits == 19) {
                const cmp = std.mem.order(u8, text[@intFromBool(negative)..], "9223372036854775808");
                if (!(cmp == .lt or (cmp == .eq and negative))) bigint = true;
            } else bigint = true;
        }
        if (!bigint) {
            self.value = .{ .int = std.fmt.parseInt(i64, text, 10) catch 0 };
            return .int;
        }
        if (self.options & BIGINT_AS_STRING != 0) {
            if (!self.validate) self.value = .{ .string = try Value.String.create(self.ctx.allocator, text) };
            return .string;
        }
        self.value = .{ .float = std.fmt.parseFloat(f64, text) catch 0 };
        return .double;
    }

    // a string: escapes, \u sequences and invalid utf-8 checked in the order
    // php's first pass (STR_P1) meets them
    fn string(self: *Parser) RuntimeError!Token {
        var i = self.cursor + 1;
        const body_start = i;
        var plain = true;
        while (true) {
            const c = self.at(i);
            if (c == '"') break;
            if (c < 0x20) return self.fail(.ctrl_char);
            if (c == '\\') {
                plain = false;
                const e = self.at(i + 1);
                if (e == 'u') {
                    const cp = hex4(self.s, i + 2) orelse return self.fail(.syntax);
                    if (cp >= 0xd800 and cp <= 0xdfff) {
                        if (cp <= 0xdbff and self.at(i + 6) == '\\' and self.at(i + 7) == 'u') {
                            if (hex4(self.s, i + 8)) |lo| if (lo >= 0xdc00 and lo <= 0xdfff) {
                                i += 12;
                                continue;
                            };
                        }
                        return self.fail(.utf16);
                    }
                    i += 6;
                    continue;
                }
                switch (e) {
                    '"', '\\', '/', 'b', 'f', 'n', 'r', 't' => {
                        i += 2;
                        continue;
                    },
                    else => return self.fail(.syntax),
                }
            }
            if (c < 0x80) {
                i += 1;
                continue;
            }
            const n = utf8Len(self.s, i);
            if (n != 0) {
                i += n;
                continue;
            }
            if (self.options & (INVALID_UTF8_IGNORE | INVALID_UTF8_SUBSTITUTE) == 0) return self.fail(.utf8);
            plain = false;
            i += 1;
        }
        self.cursor = i + 1;
        if (self.validate) return .string;
        const body = self.s[body_start..i];
        if (plain) {
            self.value = .{ .string = try Value.String.create(self.ctx.allocator, body) };
            return .string;
        }
        // the second pass (STR_P2): unescape, and drop or replace invalid
        // bytes
        const a = self.ctx.allocator;
        self.scratch.clearRetainingCapacity();
        var j: usize = 0;
        while (j < body.len) {
            const c = body[j];
            if (c == '\\') {
                const e = body[j + 1];
                if (e == 'u') {
                    const cp = hex4(body, j + 2).?;
                    if (cp >= 0xd800 and cp <= 0xdbff) {
                        const lo = hex4(body, j + 8).?;
                        const u: u32 = ((@as(u32, cp) & 0x3ff) << 10) + (@as(u32, lo) & 0x3ff) + 0x10000;
                        try self.scratch.appendSlice(a, &.{ @intCast(0xf0 | (u >> 18)), @intCast(0x80 | ((u >> 12) & 0x3f)), @intCast(0x80 | ((u >> 6) & 0x3f)), @intCast(0x80 | (u & 0x3f)) });
                        j += 12;
                    } else {
                        if (cp < 0x80) {
                            try self.scratch.append(a, @intCast(cp));
                        } else if (cp < 0x800) {
                            try self.scratch.appendSlice(a, &.{ @intCast(0xc0 | (cp >> 6)), @intCast(0x80 | (cp & 0x3f)) });
                        } else {
                            try self.scratch.appendSlice(a, &.{ @intCast(0xe0 | (cp >> 12)), @intCast(0x80 | ((cp >> 6) & 0x3f)), @intCast(0x80 | (cp & 0x3f)) });
                        }
                        j += 6;
                    }
                    continue;
                }
                try self.scratch.append(a, switch (e) {
                    'b' => 0x08,
                    'f' => 0x0c,
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    else => e,
                });
                j += 2;
                continue;
            }
            if (c < 0x80) {
                try self.scratch.append(a, c);
                j += 1;
                continue;
            }
            const n = utf8Len(body, j);
            if (n != 0) {
                try self.scratch.appendSlice(a, body[j..][0..n]);
                j += n;
                continue;
            }
            if (self.options & INVALID_UTF8_SUBSTITUTE != 0) try self.scratch.appendSlice(a, "\xef\xbf\xbd");
            j += 1;
        }
        self.value = .{ .string = try Value.String.create(a, self.scratch.items) };
        return .string;
    }

    fn dropValue(self: *Parser) void {
        if (self.value == .string) self.value.string.release();
        self.value = .null;
    }

    fn syntaxError(self: *Parser) void {
        if (self.errcode == .none) self.errcode = .syntax;
    }

    // value: object | array | a scalar token. returns null after an error
    fn parseValue(self: *Parser, t: Token) RuntimeError!?Value {
        switch (t) {
            .lbrace => return self.parseObject(),
            .lbracket => return self.parseArray(),
            .string, .int, .double => {
                const v = self.value;
                self.value = .null;
                return v;
            },
            .null_ => return .null,
            .true_ => return .{ .bool = true },
            .false_ => return .{ .bool = false },
            else => {
                self.dropValue();
                self.syntaxError();
                return null;
            },
        }
    }

    // PHP_JSON_DEPTH_INC, checked before the next token is read
    fn enter(self: *Parser) bool {
        if (self.max_depth != 0 and self.depth >= self.max_depth) {
            self.errcode = .depth;
            return false;
        }
        if (vm_mod.stack_limit.overflowed()) {
            self.errcode = .depth;
            return false;
        }
        self.depth += 1;
        return true;
    }

    fn discard(self: *Parser, v: Value) void {
        if (v == .string) v.string.release() else self.ctx.vm.discardOrphan(v);
    }

    fn parseArray(self: *Parser) RuntimeError!?Value {
        if (!self.enter()) return null;
        var arr: ?*PhpArray = null;
        errdefer if (arr) |x| self.discard(.{ .array = x });
        var t = try self.scan();
        if (t != .rbracket and t != .rbrace) {
            while (true) {
                const v = (try self.parseValue(t)) orelse {
                    if (arr) |x| self.discard(.{ .array = x });
                    return null;
                };
                if (!self.validate) {
                    if (arr == null) arr = try self.ctx.createArray();
                    try arr.?.append(self.ctx.allocator, v);
                    if (v == .string) v.string.release();
                }
                t = try self.scan();
                if (t != .comma) break;
                t = try self.scan();
            }
        }
        if (t == .rbracket) {
            self.depth -= 1;
            if (self.validate) return .null;
            return .{ .array = arr orelse try self.ctx.createArray() };
        }
        if (t == .rbrace) {
            self.errcode = .state_mismatch;
        } else {
            self.dropValue();
            self.syntaxError();
        }
        if (arr) |x| self.discard(.{ .array = x });
        return null;
    }

    fn parseObject(self: *Parser) RuntimeError!?Value {
        if (!self.enter()) return null;
        const assoc = self.options & OBJECT_AS_ARRAY != 0;
        var container: ?Value = null;
        errdefer if (container) |cv| self.discard(cv);
        var t = try self.scan();
        if (t != .rbrace and t != .rbracket) {
            while (true) {
                if (t != .string) {
                    self.dropValue();
                    self.syntaxError();
                    break;
                }
                const key_value = self.value;
                self.value = .null;
                defer if (key_value == .string) key_value.string.release();
                t = try self.scan();
                if (t != .colon) {
                    self.dropValue();
                    self.syntaxError();
                    break;
                }
                const v = (try self.parseValue(try self.scan())) orelse break;
                if (!self.validate) {
                    defer if (v == .string) v.string.release();
                    // php makes the object once its first member's value is
                    // parsed, so objects nested there are numbered before it
                    if (container == null) container = if (assoc) .{ .array = try self.ctx.createArray() } else .{ .object = try self.ctx.vm.allocObject(.{ .class_name = "stdClass" }) };
                    if (!try self.update(container.?, key_value.string, v)) {
                        // a string is released by the defer above
                        if (v != .string) self.ctx.vm.discardOrphan(v);
                        break;
                    }
                }
                t = try self.scan();
                if (t != .comma) {
                    if (t == .rbrace) {
                        self.depth -= 1;
                        if (self.validate) return .null;
                        return container.?;
                    }
                    if (t == .rbracket) {
                        self.errcode = .state_mismatch;
                    } else {
                        self.dropValue();
                        self.syntaxError();
                    }
                    break;
                }
                t = try self.scan();
            }
            if (container) |cv| self.discard(cv);
            return null;
        }
        if (t == .rbracket) {
            self.errcode = .state_mismatch;
            return null;
        }
        self.depth -= 1;
        if (self.validate) return .null;
        if (assoc) return .{ .array = try self.ctx.createArray() };
        return .{ .object = try self.ctx.vm.allocObject(.{ .class_name = "stdClass" }) };
    }

    // php_json_parser_object_update
    fn update(self: *Parser, container: Value, k: Value.String, v: Value) RuntimeError!bool {
        const name = k.bytes();
        if (container == .array) {
            var array_key = symtableKey(name);
            if (array_key == .string) array_key.string = k;
            try self.ctx.vm.arraySetOwned(container.array, array_key, v);
            return true;
        }
        if (name.len > 0 and name[0] == 0) {
            self.errcode = .invalid_property_name;
            return false;
        }
        try container.object.set(self.ctx.allocator, name, v);
        return true;
    }

    // start: value EOI
    fn parse(self: *Parser) RuntimeError!?Value {
        defer self.scratch.deinit(self.ctx.allocator);
        const v = (try self.parseValue(try self.scan())) orelse return null;
        const t = try self.scan();
        if (t != .eoi) {
            self.dropValue();
            self.syntaxError();
            self.discard(v);
            return null;
        }
        return v;
    }
};

fn hex4(s: []const u8, i: usize) ?u16 {
    if (i + 4 > s.len) return null;
    var v: u16 = 0;
    for (s[i..][0..4]) |c| {
        const d: u16 = switch (c) {
            '0'...'9' => c - '0',
            'a'...'f' => c - 'a' + 10,
            'A'...'F' => c - 'A' + 10,
            else => return null,
        };
        v = v << 4 | d;
    }
    return v;
}

// the length of the well-formed utf-8 sequence at s[i] (the scanner's
// UTF8 rule), 0 when there is none
fn utf8Len(s: []const u8, i: usize) usize {
    const at = struct {
        fn f(b: []const u8, k: usize) u8 {
            return if (k < b.len) b[k] else 0;
        }
    }.f;
    const c = at(s, i);
    const trail = struct {
        fn f(b: u8) bool {
            return b >= 0x80 and b <= 0xbf;
        }
    }.f;
    if (c < 0x80) return 1;
    if (c >= 0xc2 and c <= 0xdf) return if (trail(at(s, i + 1))) 2 else 0;
    if (c >= 0xe0 and c <= 0xef) {
        const c1 = at(s, i + 1);
        const ok1 = switch (c) {
            0xe0 => c1 >= 0xa0 and c1 <= 0xbf,
            0xed => c1 >= 0x80 and c1 <= 0x9f,
            else => trail(c1),
        };
        return if (ok1 and trail(at(s, i + 2))) 3 else 0;
    }
    if (c >= 0xf0 and c <= 0xf4) {
        const c1 = at(s, i + 1);
        const ok1 = switch (c) {
            0xf0 => c1 >= 0x90 and c1 <= 0xbf,
            0xf4 => c1 >= 0x80 and c1 <= 0x8f,
            else => trail(c1),
        };
        return if (ok1 and trail(at(s, i + 2)) and trail(at(s, i + 3))) 4 else 0;
    }
    return 0;
}

// zend_symtable_update's key: a decimal integer string becomes an int key
fn symtableKey(s: []const u8) PhpArray.Key {
    const as_string: PhpArray.Key = .{ .string = Value.String.borrowed(s) };
    if (s.len == 0) return as_string;
    var i: usize = 0;
    if (s[0] == '-') {
        if (s.len == 1) return as_string;
        i = 1;
    }
    if (s[i] == '0') {
        if (s.len - i != 1 or i == 1) return as_string;
    } else if (s[i] < '1' or s[i] > '9') {
        return as_string;
    }
    for (s[i + 1 ..]) |c| if (c < '0' or c > '9') return as_string;
    const v = std.fmt.parseInt(i64, s, 10) catch return as_string;
    return .{ .int = v };
}

fn json_decode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "json_decode", args);
    const s = try p.str(0, "json");
    const assoc_arg: ?Value = if (args.len > 1 and args[1] != .null and args[1] != .undef) args[1] else null;
    const assoc = if (assoc_arg != null) try p.boolean(1, "associative", false) else false;
    const depth = try p.optLong(2, "depth", default_depth);
    var options = try p.optLong(3, "flags", 0);
    if (options & THROW_ON_ERROR == 0) last_error = .none;
    if (s.len == 0) {
        if (options & THROW_ON_ERROR != 0) return throwJsonException(ctx, .syntax);
        last_error = .syntax;
        return NativeResult.scalar(.null);
    }
    if (depth <= 0) return throwValueError(ctx, "json_decode(): Argument #3 ($depth) must be greater than 0", .{});
    if (depth > std.math.maxInt(i32)) return throwValueError(ctx, "json_decode(): Argument #3 ($depth) must be less than {d}", .{std.math.maxInt(i32)});
    // the bool $associative wins over JSON_OBJECT_AS_ARRAY
    if (assoc_arg != null) {
        if (assoc) options |= OBJECT_AS_ARRAY else options &= ~OBJECT_AS_ARRAY;
    }
    var parser: Parser = .{ .ctx = ctx, .s = s, .options = options, .max_depth = depth, .validate = false };
    const result = (try parser.parse()) orelse {
        if (options & THROW_ON_ERROR != 0) return throwJsonException(ctx, parser.errcode);
        last_error = parser.errcode;
        return NativeResult.scalar(.null);
    };
    if (result == .string) return NativeResult.takeString(result.string);
    return NativeResult.borrowed(result);
}

fn json_validate(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "json_validate", args);
    const s = try p.str(0, "json");
    const depth = try p.optLong(1, "depth", default_depth);
    const options = try p.optLong(2, "flags", 0);
    if (options != 0 and options != INVALID_UTF8_IGNORE) return throwValueError(ctx, "json_validate(): Argument #3 ($flags) must be a valid flag (allowed flags: JSON_INVALID_UTF8_IGNORE)", .{});
    if (s.len == 0) {
        last_error = .syntax;
        return NativeResult.scalar(.{ .bool = false });
    }
    last_error = .none;
    if (depth <= 0) return throwValueError(ctx, "json_validate(): Argument #2 ($depth) must be greater than 0", .{});
    if (depth > std.math.maxInt(i32)) return throwValueError(ctx, "json_validate(): Argument #2 ($depth) must be less than {d}", .{std.math.maxInt(i32)});
    var parser: Parser = .{ .ctx = ctx, .s = s, .options = options, .max_depth = depth, .validate = true };
    if (try parser.parse() == null) {
        last_error = parser.errcode;
        return NativeResult.scalar(.{ .bool = false });
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn native_json_last_error(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = @backingInt(last_error) });
}

fn native_json_last_error_msg(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.copyString(ctx.allocator, last_error.message());
}
