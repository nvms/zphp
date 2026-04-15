const std = @import("std");
const Chunk = @import("pipeline/bytecode.zig").Chunk;
const SourceLocation = @import("pipeline/bytecode.zig").SourceLocation;
const Ast = @import("pipeline/ast.zig").Ast;
const Token = @import("pipeline/token.zig").Token;
const Value = @import("runtime/value.zig").Value;
const VM = @import("runtime/vm.zig").VM;

const Writer = std.ArrayListUnmanaged(u8);

fn write(buf: *Writer, alloc: std.mem.Allocator, data: []const u8) void {
    buf.appendSlice(alloc, data) catch {};
}

fn writeFmt(buf: *Writer, alloc: std.mem.Allocator, comptime fmt: []const u8, args: anytype) void {
    std.fmt.format(buf.writer(alloc), fmt, args) catch {};
}

fn writeSourceSnippet(buf: *Writer, alloc: std.mem.Allocator, source: []const u8, loc: SourceLocation, highlight_len: u32) void {
    // bytecode mode has empty source and loc.column == 0. nothing to render,
    // and `loc.column - 1` would overflow a u32 below
    if (source.len == 0 or loc.column == 0) return;

    const gutter_width = digitCount(loc.line + 1);

    if (loc.line > 1) {
        if (findLineByNumber(source, loc.line - 1)) |prev| {
            writeGutterLine(buf, alloc, gutter_width, loc.line - 1, prev);
        }
    }

    const current_line_text = source[loc.line_start..loc.line_end];
    writeGutterLine(buf, alloc, gutter_width, loc.line, current_line_text);

    writeGutterBlank(buf, alloc, gutter_width);
    for (0..loc.column - 1) |i| {
        const ch = if (loc.line_start + i < source.len and source[loc.line_start + i] == '\t') @as(u8, '\t') else @as(u8, ' ');
        buf.append(alloc, ch) catch {};
    }
    const caret_len = @max(1, highlight_len);
    for (0..caret_len) |_| buf.append(alloc, '^') catch {};
    write(buf, alloc, "\n");

    if (loc.line_end < source.len) {
        if (findLineByNumber(source, loc.line + 1)) |next| {
            writeGutterLine(buf, alloc, gutter_width, loc.line + 1, next);
        }
    }
}

fn writeGutterLine(buf: *Writer, alloc: std.mem.Allocator, gutter_width: u32, line_num: u32, text: []const u8) void {
    // strip trailing \r so CRLF source files don't emit a literal CR that the
    // terminal interprets as a carriage return, overwriting the gutter
    var trimmed = text;
    if (trimmed.len > 0 and trimmed[trimmed.len - 1] == '\r') {
        trimmed = trimmed[0 .. trimmed.len - 1];
    }
    writeFmt(buf, alloc, " {d: >[1]} | ", .{ line_num, gutter_width });
    write(buf, alloc, trimmed);
    write(buf, alloc, "\n");
}

fn writeGutterBlank(buf: *Writer, alloc: std.mem.Allocator, gutter_width: u32) void {
    for (0..gutter_width + 2) |_| buf.append(alloc, ' ') catch {};
    write(buf, alloc, "| ");
}

fn findLineByNumber(source: []const u8, target_line: u32) ?[]const u8 {
    var line: u32 = 1;
    var start: usize = 0;
    for (source, 0..) |c, i| {
        if (c == '\n') {
            if (line == target_line) return source[start..i];
            line += 1;
            start = i + 1;
        }
    }
    if (line == target_line and start <= source.len) return source[start..];
    return null;
}

fn digitCount(n: u32) u32 {
    if (n == 0) return 1;
    var v = n;
    var count: u32 = 0;
    while (v > 0) : (v /= 10) count += 1;
    return count;
}

fn displayPath(file_path: []const u8) []const u8 {
    if (file_path.len == 0) return "<input>";
    return file_path;
}

pub fn formatParseErrors(alloc: std.mem.Allocator, ast: *const Ast, file_path: []const u8) []const u8 {
    var buf: Writer = .{};
    const path = displayPath(file_path);

    for (ast.errors) |err| {
        const tok = ast.tokens[err.token];
        const loc = Chunk.locationFromOffset(ast.source, tok.start);
        const token_len: u32 = tok.end - tok.start;

        writeFmt(&buf, alloc, "\nParse error: {s} in {s} on line {d}\n\n", .{ errorTagMessage(err.tag), path, loc.line });
        writeSourceSnippet(&buf, alloc, ast.source, loc, token_len);
    }

    return buf.items;
}

fn errorTagMessage(tag: Ast.Error.Tag) []const u8 {
    return switch (tag) {
        .expected_expression => "expected expression",
        .expected_semicolon => "expected ';'",
        .expected_r_paren => "expected ')'",
        .expected_r_brace => "expected '}'",
        .expected_r_bracket => "expected ']'",
        .expected_identifier => "expected identifier",
        .expected_variable => "expected variable",
        .expected_colon => "expected ':'",
        .unexpected_token => "unexpected token",
    };
}

pub fn formatRuntimeError(alloc: std.mem.Allocator, vm: *const VM) []const u8 {
    var buf: Writer = .{};

    if (vm.pending_exception) |exc| {
        formatUncaughtException(&buf, alloc, vm, exc);
    } else if (vm.error_msg) |msg| {
        write(&buf, alloc, msg);
        appendLocationContext(&buf, alloc, vm);
    } else {
        write(&buf, alloc, "Fatal error: unknown runtime error");
        appendLocationContext(&buf, alloc, vm);
    }

    return buf.items;
}

fn formatUncaughtException(buf: *Writer, alloc: std.mem.Allocator, vm: *const VM, exc: Value) void {
    var class_name: []const u8 = "Exception";
    var message: []const u8 = "";

    if (exc == .object) {
        class_name = exc.object.class_name;
        const msg = exc.object.get("message");
        if (msg == .string) message = msg.string;
    } else if (exc == .string) {
        message = exc.string;
    }

    const frame_idx = if (vm.frame_count > 0) vm.frame_count - 1 else 0;
    const frame = &vm.frames[frame_idx];
    const ip = if (frame.ip > 0) frame.ip - 1 else 0;
    const source = vm.source;
    const path = displayPath(vm.file_path);

    if (frame.chunk.getSourceLocation(ip, source)) |loc| {
        writeFmt(buf, alloc, "\nFatal error: Uncaught {s}: {s} in {s} on line {d}\n\n", .{ class_name, message, path, loc.line });
        const token_len: u32 = estimateTokenLength(source, loc);
        writeSourceSnippet(buf, alloc, source, loc, token_len);
    } else {
        writeFmt(buf, alloc, "\nFatal error: Uncaught {s}: {s} in {s}\n", .{ class_name, message, path });
    }

    write(buf, alloc, "\nStack trace:\n");
    writeStackTrace(buf, alloc, vm);

    if (frame.chunk.getSourceLocation(ip, source)) |loc| {
        writeFmt(buf, alloc, "  thrown in {s} on line {d}\n", .{ path, loc.line });
    } else {
        writeFmt(buf, alloc, "  thrown in {s}\n", .{path});
    }
}

fn appendLocationContext(buf: *Writer, alloc: std.mem.Allocator, vm: *const VM) void {
    if (vm.frame_count == 0) {
        write(buf, alloc, "\n");
        return;
    }
    const frame = &vm.frames[vm.frame_count - 1];
    const ip = if (frame.ip > 0) frame.ip - 1 else 0;
    const source = vm.source;
    const path = displayPath(vm.file_path);

    if (frame.chunk.getSourceLocation(ip, source)) |loc| {
        writeFmt(buf, alloc, " in {s} on line {d}\n\n", .{ path, loc.line });
        const token_len: u32 = estimateTokenLength(source, loc);
        writeSourceSnippet(buf, alloc, source, loc, token_len);
        if (vm.frame_count > 1) {
            write(buf, alloc, "\nStack trace:\n");
            writeStackTrace(buf, alloc, vm);
        }
    } else {
        writeFmt(buf, alloc, " in {s}\n", .{path});
    }
}

fn writeStackTrace(buf: *Writer, alloc: std.mem.Allocator, vm: *const VM) void {
    if (vm.frame_count == 0) return;
    const source = vm.source;
    const path = displayPath(vm.file_path);
    var depth: u32 = 0;

    // each entry shows where frame[i] was called from (frame[i-1]'s IP)
    var i: usize = vm.frame_count - 1;
    while (i >= 1) : ({
        i -= 1;
        depth += 1;
    }) {
        const frame = &vm.frames[i];
        const func_name = if (frame.func) |f| f.name else "{main}";
        const caller = &vm.frames[i - 1];
        const caller_ip = if (caller.ip > 0) caller.ip - 1 else 0;

        if (caller.chunk.getSourceLocation(caller_ip, source)) |loc| {
            writeFmt(buf, alloc, "#{d} {s}({d}): {s}()\n", .{ depth, path, loc.line, func_name });
        } else {
            writeFmt(buf, alloc, "#{d} {s}: {s}()\n", .{ depth, path, func_name });
        }
    }

    writeFmt(buf, alloc, "#{d} {{main}}\n", .{depth});
}

fn estimateTokenLength(source: []const u8, loc: SourceLocation) u32 {
    // bytecode mode has empty source and column == 0, which would underflow below
    if (source.len == 0 or loc.column == 0) return 1;
    const start = loc.line_start + loc.column - 1;
    if (start >= source.len) return 1;

    const c = source[start];
    if (c == '$' or isIdentStart(c)) {
        var end = start + 1;
        while (end < source.len and isIdentChar(source[end])) end += 1;
        return @intCast(end - start);
    }
    if (c == '"' or c == '\'') return 1;
    return 1;
}

fn isIdentStart(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

fn isIdentChar(c: u8) bool {
    return isIdentStart(c) or (c >= '0' and c <= '9');
}
