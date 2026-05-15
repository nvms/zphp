const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub fn register(vm: *VM, a: Allocator) !void {
    try vm.classes.put(a, "XMLParser", ClassDef{ .name = "XMLParser" });

    try vm.native_fns.put(a, "xml_parser_create", create);
    try vm.native_fns.put(a, "xml_parser_create_ns", createNs);
    try vm.native_fns.put(a, "xml_set_element_handler", setElementHandler);
    try vm.native_fns.put(a, "xml_set_character_data_handler", setCharHandler);
    try vm.native_fns.put(a, "xml_set_default_handler", setDefaultHandler);
    try vm.native_fns.put(a, "xml_set_processing_instruction_handler", setPiHandler);
    try vm.native_fns.put(a, "xml_set_object", setObject);
    try vm.native_fns.put(a, "xml_parser_set_option", setOption);
    try vm.native_fns.put(a, "xml_parser_get_option", getOption);
    try vm.native_fns.put(a, "xml_parse", xmlParse);
    try vm.native_fns.put(a, "xml_parse_into_struct", xmlParse); // approximate
    try vm.native_fns.put(a, "xml_parser_free", parserFree);
    try vm.native_fns.put(a, "xml_get_error_code", getErrorCode);
    try vm.native_fns.put(a, "xml_error_string", errorString);
    try vm.native_fns.put(a, "xml_get_current_line_number", getCurrentLine);
    try vm.native_fns.put(a, "xml_get_current_column_number", getCurrentCol);
    try vm.native_fns.put(a, "xml_get_current_byte_index", getCurrentByte);

    try vm.php_constants.put(a, "XML_OPTION_CASE_FOLDING", .{ .int = 1 });
    try vm.php_constants.put(a, "XML_OPTION_TARGET_ENCODING", .{ .int = 2 });
    try vm.php_constants.put(a, "XML_OPTION_SKIP_TAGSTART", .{ .int = 3 });
    try vm.php_constants.put(a, "XML_OPTION_SKIP_WHITE", .{ .int = 4 });
    try vm.php_constants.put(a, "XML_ERROR_NONE", .{ .int = 0 });
    try vm.php_constants.put(a, "XML_ERROR_NO_MEMORY", .{ .int = 1 });
    try vm.php_constants.put(a, "XML_ERROR_SYNTAX", .{ .int = 2 });
    try vm.php_constants.put(a, "XML_ERROR_INVALID_TOKEN", .{ .int = 4 });
}

fn dupString(ctx: *NativeContext, s: []const u8) ![]const u8 {
    const owned = try ctx.allocator.dupe(u8, s);
    try ctx.vm.strings.append(ctx.allocator, owned);
    return owned;
}

fn create(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = try ctx.allocator.create(PhpObject);
    obj.* = .{ .class_name = "XMLParser" };
    try obj.set(ctx.allocator, "__case_fold", .{ .bool = true });
    try obj.set(ctx.allocator, "__skip_white", .{ .bool = false });
    try obj.set(ctx.allocator, "__line", .{ .int = 1 });
    try obj.set(ctx.allocator, "__col", .{ .int = 0 });
    try obj.set(ctx.allocator, "__byte", .{ .int = 0 });
    try obj.set(ctx.allocator, "__error", .{ .int = 0 });
    try ctx.vm.objects.append(ctx.allocator, obj);
    return .{ .object = obj };
}

fn createNs(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return create(ctx, args);
}

fn parserObj(args: []const Value) ?*PhpObject {
    if (args.len == 0 or args[0] != .object) return null;
    return args[0].object;
}

fn setElementHandler(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const p = parserObj(args) orelse return .{ .bool = false };
    if (args.len >= 2) try p.set(ctx.allocator, "__start_handler", args[1]);
    if (args.len >= 3) try p.set(ctx.allocator, "__end_handler", args[2]);
    return .{ .bool = true };
}

fn setCharHandler(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const p = parserObj(args) orelse return .{ .bool = false };
    if (args.len >= 2) try p.set(ctx.allocator, "__char_handler", args[1]);
    return .{ .bool = true };
}

fn setDefaultHandler(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const p = parserObj(args) orelse return .{ .bool = false };
    if (args.len >= 2) try p.set(ctx.allocator, "__default_handler", args[1]);
    return .{ .bool = true };
}

fn setPiHandler(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const p = parserObj(args) orelse return .{ .bool = false };
    if (args.len >= 2) try p.set(ctx.allocator, "__pi_handler", args[1]);
    return .{ .bool = true };
}

fn setObject(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const p = parserObj(args) orelse return .{ .bool = false };
    if (args.len >= 2 and args[1] == .object) try p.set(ctx.allocator, "__bound_object", args[1]);
    return .{ .bool = true };
}

fn setOption(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const p = parserObj(args) orelse return .{ .bool = false };
    if (args.len < 3) return .{ .bool = false };
    const opt: i64 = Value.toInt(args[1]);
    switch (opt) {
        1 => try p.set(ctx.allocator, "__case_fold", .{ .bool = Value.isTruthy(args[2]) }),
        4 => try p.set(ctx.allocator, "__skip_white", .{ .bool = Value.isTruthy(args[2]) }),
        else => {},
    }
    return .{ .bool = true };
}

fn getOption(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const p = parserObj(args) orelse return .{ .bool = false };
    if (args.len < 2) return .{ .bool = false };
    const opt: i64 = Value.toInt(args[1]);
    return switch (opt) {
        1 => .{ .bool = (p.get("__case_fold") == .bool and p.get("__case_fold").bool) },
        4 => .{ .bool = (p.get("__skip_white") == .bool and p.get("__skip_white").bool) },
        else => .{ .bool = false },
    };
}

fn parserFree(_: *NativeContext, _: []const Value) RuntimeError!Value {
    // arena-based memory; nothing to free explicitly
    return .{ .bool = true };
}

fn getErrorCode(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const p = parserObj(args) orelse return .{ .int = 0 };
    return p.get("__error");
}

fn errorString(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0) return .{ .string = "" };
    const code: i64 = Value.toInt(args[0]);
    return .{ .string = switch (code) {
        0 => "No error",
        1 => "Out of memory",
        2 => "Syntax error",
        4 => "Invalid token",
        else => "Unknown error",
    } };
}

fn getCurrentLine(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const p = parserObj(args) orelse return .{ .int = 0 };
    return p.get("__line");
}

fn getCurrentCol(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const p = parserObj(args) orelse return .{ .int = 0 };
    return p.get("__col");
}

fn getCurrentByte(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const p = parserObj(args) orelse return .{ .int = 0 };
    return p.get("__byte");
}

const ParseState = struct {
    parser: *PhpObject,
    src: []const u8,
    pos: usize = 0,
    line: i64 = 1,
    col: i64 = 0,
    case_fold: bool = true,
    skip_white: bool = false,

    fn peek(self: *const ParseState) ?u8 {
        return if (self.pos < self.src.len) self.src[self.pos] else null;
    }
    fn advance(self: *ParseState) ?u8 {
        if (self.pos >= self.src.len) return null;
        const c = self.src[self.pos];
        self.pos += 1;
        if (c == '\n') { self.line += 1; self.col = 0; } else self.col += 1;
        return c;
    }
    fn startsWith(self: *const ParseState, s: []const u8) bool {
        if (self.pos + s.len > self.src.len) return false;
        return std.mem.eql(u8, self.src[self.pos..self.pos + s.len], s);
    }
};

fn xmlParse(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .object) return .{ .int = 0 };
    const parser = args[0].object;
    const data = if (args[1] == .string) args[1].string else return .{ .int = 0 };
    const is_final = args.len < 3 or Value.isTruthy(args[2]);
    _ = is_final;

    var st = ParseState{
        .parser = parser,
        .src = data,
        .case_fold = parser.get("__case_fold") == .bool and parser.get("__case_fold").bool,
        .skip_white = parser.get("__skip_white") == .bool and parser.get("__skip_white").bool,
    };

    var text_buf: std.ArrayListUnmanaged(u8) = .{};
    defer text_buf.deinit(ctx.allocator);

    while (st.pos < st.src.len) {
        if (st.peek() == '<') {
            if (text_buf.items.len > 0) {
                try flushText(ctx, &st, text_buf.items);
                text_buf.clearRetainingCapacity();
            }
            if (st.startsWith("<?")) {
                // PI or xml decl - skip until ?>
                while (st.pos < st.src.len and !st.startsWith("?>")) _ = st.advance();
                if (st.startsWith("?>")) { _ = st.advance(); _ = st.advance(); }
                continue;
            }
            if (st.startsWith("<!--")) {
                _ = st.advance(); _ = st.advance(); _ = st.advance(); _ = st.advance();
                while (st.pos < st.src.len and !st.startsWith("-->")) _ = st.advance();
                if (st.startsWith("-->")) { _ = st.advance(); _ = st.advance(); _ = st.advance(); }
                continue;
            }
            if (st.startsWith("<![CDATA[")) {
                var i: usize = 0;
                while (i < 9) : (i += 1) _ = st.advance();
                const cdata_start = st.pos;
                while (st.pos < st.src.len and !st.startsWith("]]>")) _ = st.advance();
                const cdata = st.src[cdata_start..st.pos];
                if (cdata.len > 0) try flushText(ctx, &st, cdata);
                if (st.startsWith("]]>")) { _ = st.advance(); _ = st.advance(); _ = st.advance(); }
                continue;
            }
            if (st.startsWith("<!")) {
                while (st.pos < st.src.len and st.peek() != '>') _ = st.advance();
                _ = st.advance();
                continue;
            }
            if (st.startsWith("</")) {
                _ = st.advance(); _ = st.advance();
                const name_start = st.pos;
                while (st.pos < st.src.len) {
                    const c = st.peek().?;
                    if (c == '>' or std.ascii.isWhitespace(c)) break;
                    _ = st.advance();
                }
                const name = st.src[name_start..st.pos];
                while (st.pos < st.src.len and st.peek() != '>') _ = st.advance();
                _ = st.advance();
                const folded = try foldName(ctx, name, st.case_fold);
                try invokeEnd(ctx, &st, folded);
                continue;
            }
            // start tag
            _ = st.advance(); // <
            const name_start = st.pos;
            while (st.pos < st.src.len) {
                const c = st.peek().?;
                if (c == '>' or c == '/' or std.ascii.isWhitespace(c)) break;
                _ = st.advance();
            }
            const name = st.src[name_start..st.pos];
            const folded = try foldName(ctx, name, st.case_fold);

            const attrs = try ctx.createArray();
            while (st.pos < st.src.len) {
                while (st.pos < st.src.len and std.ascii.isWhitespace(st.peek().?)) _ = st.advance();
                if (st.pos >= st.src.len) break;
                const ch = st.peek().?;
                if (ch == '>' or ch == '/') break;
                const an_start = st.pos;
                while (st.pos < st.src.len) {
                    const c2 = st.peek().?;
                    if (c2 == '=' or std.ascii.isWhitespace(c2) or c2 == '>' or c2 == '/') break;
                    _ = st.advance();
                }
                const aname = st.src[an_start..st.pos];
                while (st.pos < st.src.len and std.ascii.isWhitespace(st.peek().?)) _ = st.advance();
                if (st.peek() == '=') {
                    _ = st.advance();
                    while (st.pos < st.src.len and std.ascii.isWhitespace(st.peek().?)) _ = st.advance();
                    var quote: u8 = 0;
                    if (st.peek() == '"' or st.peek() == '\'') {
                        quote = st.peek().?;
                        _ = st.advance();
                    }
                    const av_start = st.pos;
                    while (st.pos < st.src.len) {
                        const c3 = st.peek().?;
                        if ((quote != 0 and c3 == quote) or (quote == 0 and (std.ascii.isWhitespace(c3) or c3 == '>' or c3 == '/'))) break;
                        _ = st.advance();
                    }
                    const raw_val = st.src[av_start..st.pos];
                    if (quote != 0) _ = st.advance();
                    const folded_an = try foldName(ctx, aname, st.case_fold);
                    const unesc = try unescapeEntities(ctx, raw_val);
                    try attrs.set(ctx.allocator, .{ .string = folded_an }, .{ .string = unesc });
                } else if (aname.len > 0) {
                    const folded_an = try foldName(ctx, aname, st.case_fold);
                    try attrs.set(ctx.allocator, .{ .string = folded_an }, .{ .string = "" });
                } else {
                    break;
                }
            }

            const self_close = st.peek() == '/';
            if (self_close) _ = st.advance();
            if (st.peek() == '>') _ = st.advance();

            try invokeStart(ctx, &st, folded, attrs);
            if (self_close) try invokeEnd(ctx, &st, folded);
            continue;
        }
        const c = st.advance().?;
        try text_buf.append(ctx.allocator, c);
    }
    if (text_buf.items.len > 0) try flushText(ctx, &st, text_buf.items);

    try parser.set(ctx.allocator, "__line", .{ .int = st.line });
    try parser.set(ctx.allocator, "__col", .{ .int = st.col });
    try parser.set(ctx.allocator, "__byte", .{ .int = @intCast(st.pos) });
    return .{ .int = 1 };
}

fn foldName(ctx: *NativeContext, name: []const u8, case_fold: bool) ![]const u8 {
    if (!case_fold) return try dupString(ctx, name);
    const buf = try ctx.allocator.alloc(u8, name.len);
    for (name, 0..) |c, i| buf[i] = std.ascii.toUpper(c);
    try ctx.vm.strings.append(ctx.allocator, buf);
    return buf;
}

fn unescapeEntities(ctx: *NativeContext, s: []const u8) ![]const u8 {
    if (std.mem.indexOfScalar(u8, s, '&') == null) return try dupString(ctx, s);
    var out: std.ArrayListUnmanaged(u8) = .{};
    errdefer out.deinit(ctx.allocator);
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '&') {
            if (i + 5 <= s.len and std.mem.eql(u8, s[i..i+5], "&amp;")) { try out.append(ctx.allocator, '&'); i += 5; continue; }
            if (i + 4 <= s.len and std.mem.eql(u8, s[i..i+4], "&lt;")) { try out.append(ctx.allocator, '<'); i += 4; continue; }
            if (i + 4 <= s.len and std.mem.eql(u8, s[i..i+4], "&gt;")) { try out.append(ctx.allocator, '>'); i += 4; continue; }
            if (i + 6 <= s.len and std.mem.eql(u8, s[i..i+6], "&quot;")) { try out.append(ctx.allocator, '"'); i += 6; continue; }
            if (i + 6 <= s.len and std.mem.eql(u8, s[i..i+6], "&apos;")) { try out.append(ctx.allocator, '\''); i += 6; continue; }
        }
        try out.append(ctx.allocator, s[i]);
        i += 1;
    }
    const owned = try out.toOwnedSlice(ctx.allocator);
    try ctx.vm.strings.append(ctx.allocator, owned);
    return owned;
}

fn invokeStart(ctx: *NativeContext, st: *ParseState, name: []const u8, attrs: *PhpArray) !void {
    const handler = st.parser.get("__start_handler");
    if (handler == .null or (handler == .bool and !handler.bool)) return;
    var args = [_]Value{
        .{ .object = st.parser },
        .{ .string = name },
        .{ .array = attrs },
    };
    _ = invokeCallable(ctx, st.parser, handler, args[0..]) catch {};
}

fn invokeEnd(ctx: *NativeContext, st: *ParseState, name: []const u8) !void {
    const handler = st.parser.get("__end_handler");
    if (handler == .null or (handler == .bool and !handler.bool)) return;
    var args = [_]Value{
        .{ .object = st.parser },
        .{ .string = name },
    };
    _ = invokeCallable(ctx, st.parser, handler, args[0..]) catch {};
}

fn flushText(ctx: *NativeContext, st: *ParseState, raw: []const u8) !void {
    const handler = st.parser.get("__char_handler");
    if (handler == .null or (handler == .bool and !handler.bool)) return;
    const decoded = try unescapeEntities(ctx, raw);
    if (st.skip_white) {
        var all_ws = true;
        for (decoded) |c| {
            if (!std.ascii.isWhitespace(c)) { all_ws = false; break; }
        }
        if (all_ws) return;
    }
    var args = [_]Value{
        .{ .object = st.parser },
        .{ .string = decoded },
    };
    _ = invokeCallable(ctx, st.parser, handler, args[0..]) catch {};
}

fn invokeCallable(ctx: *NativeContext, parser: *PhpObject, callable: Value, args: []Value) !Value {
    const bound = parser.get("__bound_object");
    if (bound == .object and callable == .string) {
        return try ctx.vm.callMethod(bound.object, callable.string, args);
    }
    if (callable == .string) {
        return try ctx.vm.callByName(callable.string, args);
    }
    if (callable == .object) {
        return try ctx.vm.callMethod(callable.object, "__invoke", args);
    }
    if (callable == .array) {
        const arr = callable.array;
        if (arr.entries.items.len >= 2) {
            const tgt = arr.entries.items[0].value;
            const mname = arr.entries.items[1].value;
            if (mname == .string) {
                if (tgt == .object) return try ctx.vm.callMethod(tgt.object, mname.string, args);
                if (tgt == .string) {
                    var buf: [256]u8 = undefined;
                    const full = std.fmt.bufPrint(&buf, "{s}::{s}", .{ tgt.string, mname.string }) catch return .null;
                    return try ctx.vm.callByName(full, args);
                }
            }
        }
    }
    return .null;
}

pub fn cleanupResources(_: anytype) void {}
