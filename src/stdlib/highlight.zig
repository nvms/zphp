// Zend/zend_highlight.c over the php-exact tokenizer: highlight_file,
// show_source, highlight_string and php_strip_whitespace
const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const Args = @import("string_ports.zig").Args;
const tokenizer = @import("tokenizer.zig");
const t = @import("tokens_generated.zig");
const fs = @import("filesystem.zig");
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "highlight_file", native_highlight_file },
    .{ "show_source", native_highlight_file },
    .{ "highlight_string", native_highlight_string },
    .{ "php_strip_whitespace", native_php_strip_whitespace },
};

const Colors = struct { string: []const u8, comment: []const u8, keyword: []const u8, default: []const u8, html: []const u8 };

fn colors(ctx: *NativeContext) Colors {
    const get = struct {
        fn f(c: *NativeContext, name: []const u8, default: []const u8) []const u8 {
            return c.vm.ini_settings.get(name) orelse default;
        }
    }.f;
    return .{
        .string = get(ctx, "highlight.string", "#DD0000"),
        .comment = get(ctx, "highlight.comment", "#FF8000"),
        .keyword = get(ctx, "highlight.keyword", "#007700"),
        .default = get(ctx, "highlight.default", "#0000BB"),
        .html = get(ctx, "highlight.html", "#000000"),
    };
}

// zend_html_puts
fn htmlPuts(a: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8), s: []const u8) !void {
    for (s) |c| switch (c) {
        '<' => try out.appendSlice(a, "&lt;"),
        '>' => try out.appendSlice(a, "&gt;"),
        '&' => try out.appendSlice(a, "&amp;"),
        '\t' => try out.appendSlice(a, "    "),
        else => try out.append(a, c),
    };
}

// the tokens lex_scan hands back with a value; any other token that isn't
// one of the named groups is a keyword
fn hasValue(id: i64) bool {
    return switch (id) {
        t.T_STRING, t.T_NAME_QUALIFIED, t.T_NAME_FULLY_QUALIFIED, t.T_NAME_RELATIVE, t.T_STRING_VARNAME, t.T_VARIABLE, t.T_CONSTANT_ENCAPSED_STRING, t.T_DNUMBER, t.T_LNUMBER, t.T_ENCAPSED_AND_WHITESPACE, t.T_INLINE_HTML, t.T_NUM_STRING => true,
        else => false,
    };
}

// zend_highlight
pub fn highlight(ctx: *NativeContext, src: []const u8, out: *std.ArrayListUnmanaged(u8)) RuntimeError!void {
    const a = ctx.allocator;
    const c = colors(ctx);
    const tokens = tokenizer.tokenize(a, src, shortOpenTag(ctx)) catch return error.RuntimeError;
    defer a.free(tokens);
    var last: []const u8 = c.html;
    try out.print(a, "<pre><code style=\"color: {s}\">", .{last});
    for (tokens) |tok| {
        const next: []const u8 = switch (tok.id) {
            t.T_INLINE_HTML => c.html,
            t.T_COMMENT, t.T_DOC_COMMENT => c.comment,
            t.T_OPEN_TAG, t.T_OPEN_TAG_WITH_ECHO, t.T_CLOSE_TAG, t.T_LINE, t.T_FILE, t.T_DIR, t.T_TRAIT_C, t.T_METHOD_C, t.T_FUNC_C, t.T_PROPERTY_C, t.T_NS_C, t.T_CLASS_C => c.default,
            '"', t.T_ENCAPSED_AND_WHITESPACE, t.T_CONSTANT_ENCAPSED_STRING => c.string,
            t.T_WHITESPACE => {
                try htmlPuts(a, out, tok.text);
                continue;
            },
            else => if (hasValue(tok.id)) c.default else c.keyword,
        };
        // colors are compared as the pointers php keeps
        if (last.ptr != next.ptr) {
            if (last.ptr != c.html.ptr) try out.appendSlice(a, "</span>");
            last = next;
            if (last.ptr != c.html.ptr) try out.print(a, "<span style=\"color: {s}\">", .{last});
        }
        try htmlPuts(a, out, tok.text);
    }
    if (last.ptr != c.html.ptr) try out.appendSlice(a, "</span>");
    try out.appendSlice(a, "</code></pre>");
}

// zend_strip
pub fn strip(a: std.mem.Allocator, src: []const u8, short_open_tag: bool, out: *std.ArrayListUnmanaged(u8)) !void {
    const tokens = try tokenizer.tokenize(a, src, short_open_tag);
    defer a.free(tokens);
    var prev_space = false;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        const tok = tokens[i];
        switch (tok.id) {
            t.T_WHITESPACE => {
                if (!prev_space) {
                    try out.append(a, ' ');
                    prev_space = true;
                }
                continue;
            },
            t.T_COMMENT, t.T_DOC_COMMENT => continue,
            t.T_END_HEREDOC => {
                try out.appendSlice(a, tok.text);
                // the following newline or ;
                if (i + 1 < tokens.len) {
                    i += 1;
                    if (tokens[i].id != t.T_WHITESPACE) try out.appendSlice(a, tokens[i].text);
                }
                try out.append(a, '\n');
                prev_space = true;
                continue;
            },
            else => try out.appendSlice(a, tok.text),
        }
        prev_space = false;
    }
}

fn shortOpenTag(ctx: *NativeContext) bool {
    const v = ctx.vm.ini_settings.get("short_open_tag") orelse return true;
    return std.ascii.eqlIgnoreCase(v, "on") or std.ascii.eqlIgnoreCase(v, "true") or std.ascii.eqlIgnoreCase(v, "yes") or
        (std.fmt.parseInt(i64, std.mem.trim(u8, v, " "), 10) catch 0) != 0;
}

// the file's source as the language scanner opens it, with php's warning
fn readSource(ctx: *NativeContext, path: []const u8) RuntimeError!?[]u8 {
    // the scanner opens files as include does: a url wrapper needs
    // allow_url_include
    const colon = std.mem.indexOfScalar(u8, path, ':') orelse 0;
    const scheme = path[0..colon];
    const is_url = std.ascii.eqlIgnoreCase(scheme, "data") or std.ascii.eqlIgnoreCase(scheme, "http") or
        std.ascii.eqlIgnoreCase(scheme, "https") or std.ascii.eqlIgnoreCase(scheme, "ftp") or std.ascii.eqlIgnoreCase(scheme, "ftps");
    if (is_url and !ctx.vm.iniFlagOn("allow_url_include", "0")) {
        try fs.warnDocref(ctx, "{s}:// wrapper is disabled in the server configuration by allow_url_include=0", .{scheme});
        try fs.warnDocrefParam(ctx, path, "Failed to open stream: no suitable wrapper could be found", .{});
        return null;
    }
    const stream = (try fs.openStreamValue(ctx, path, "rb", null)) orelse return null;
    stream.resource.retain();
    defer ctx.vm.releaseValue(stream);
    const data = try @import("streams.zig").copyToMem(ctx, stream.resource, null);
    _ = try fs.closeStream(ctx, stream.resource);
    return data orelse try ctx.allocator.alloc(u8, 0);
}

fn emit(ctx: *NativeContext, bytes: []const u8) RuntimeError!void {
    try ctx.vm.output.appendSlice(ctx.allocator, bytes);
}

fn native_highlight_file(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const name = ctx.call_name orelse "highlight_file";
    const p = Args.init(ctx, name, args);
    const path = try p.path(0, "filename");
    const ret = try p.boolean(1, "return", false);
    const src = (try readSource(ctx, path)) orelse {
        try fs.warnDocref(ctx, "Failed opening '{s}' for highlighting", .{path});
        return NativeResult.scalar(.{ .bool = false });
    };
    defer ctx.allocator.free(src);
    var out = std.ArrayListUnmanaged(u8).empty;
    defer out.deinit(ctx.allocator);
    try highlight(ctx, src, &out);
    if (ret) return NativeResult.copyString(ctx.allocator, out.items);
    try emit(ctx, out.items);
    return NativeResult.scalar(.{ .bool = true });
}

fn native_highlight_string(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "highlight_string", args);
    const src = try p.str(0, "string");
    const ret = try p.boolean(1, "return", false);
    var out = std.ArrayListUnmanaged(u8).empty;
    defer out.deinit(ctx.allocator);
    try highlight(ctx, src, &out);
    if (ret) return NativeResult.copyString(ctx.allocator, out.items);
    try emit(ctx, out.items);
    return NativeResult.scalar(.{ .bool = true });
}

fn native_php_strip_whitespace(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = Args.init(ctx, "php_strip_whitespace", args);
    const path = try p.path(0, "filename");
    const src = (try readSource(ctx, path)) orelse return NativeResult.literal("");
    defer ctx.allocator.free(src);
    var out = std.ArrayListUnmanaged(u8).empty;
    defer out.deinit(ctx.allocator);
    strip(ctx.allocator, src, shortOpenTag(ctx), &out) catch return error.RuntimeError;
    return NativeResult.copyString(ctx.allocator, out.items);
}
