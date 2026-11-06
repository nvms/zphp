const std = @import("std");
const Chunk = @import("pipeline/bytecode.zig").Chunk;
const SourceLocation = @import("pipeline/bytecode.zig").SourceLocation;
const Ast = @import("pipeline/ast.zig").Ast;
const Token = @import("pipeline/token.zig").Token;
const Value = @import("runtime/value.zig").Value;
const VM = @import("runtime/vm.zig").VM;
const Diagnostic = @import("pipeline/compiler.zig").Diagnostic;

const Writer = std.ArrayListUnmanaged(u8);

fn write(buf: *Writer, alloc: std.mem.Allocator, data: []const u8) void {
    buf.appendSlice(alloc, data) catch {};
}

fn writeFmt(buf: *Writer, alloc: std.mem.Allocator, comptime fmt: []const u8, args: anytype) void {
    buf.print(alloc, fmt, args) catch {};
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
    var buf: Writer = .empty;
    const path = displayPath(file_path);

    for (ast.errors) |err| {
        const tok = ast.tokens[err.token];
        var loc = Chunk.locationFromOffset(ast.source, tok.start);
        const token_len: u32 = tok.end - tok.start;
        loc.line += err.line_delta;

        const message = heredocMessage(alloc, err) orelse errorTagMessage(err.tag);
        writeFmt(&buf, alloc, "\nParse error: {s} in {s} on line {d}\n\n", .{ message, path, loc.line });
        if (err.line_delta == 0) writeSourceSnippet(&buf, alloc, ast.source, loc, token_len);
    }

    return buf.items;
}

// the first syntax error in php's wording: syntax error, unexpected token
// "}", expecting ";". the caller owns the returned bytes
pub fn parseErrorSummary(alloc: std.mem.Allocator, ast: *const Ast) ![]u8 {
    if (ast.errors.len == 0) return alloc.dupe(u8, "syntax error");
    const err = ast.errors[0];
    switch (err.tag) {
        .heredoc_mixed_indentation => return alloc.dupe(u8, "Invalid indentation - tabs and spaces cannot be mixed"),
        .heredoc_body_indentation => return std.fmt.allocPrint(alloc, "Invalid body indentation level (expecting an indentation level of at least {d})", .{err.detail}),
        else => {},
    }
    const tok = ast.tokens[err.token];
    const lexeme = ast.source[tok.start..tok.end];
    const expecting: ?[]const u8 = switch (err.tag) {
        .expected_expression => "expression",
        .expected_semicolon => "\";\"",
        .expected_r_paren => "\")\"",
        .expected_r_brace => "\"}\"",
        .expected_r_bracket => "\"]\"",
        .expected_identifier => "identifier",
        .expected_variable => "variable",
        .expected_colon => "\":\"",
        .unexpected_token => null,
        .real_cast_removed => return alloc.dupe(u8, "The (real) cast has been removed, use (float) instead"),
        .void_cast_misplaced => return alloc.dupe(u8, "syntax error, unexpected token \"(void)\""),
        .heredoc_mixed_indentation, .heredoc_body_indentation => unreachable,
    };
    if (lexeme.len == 0) {
        if (expecting) |e| return std.fmt.allocPrint(alloc, "syntax error, unexpected end of file, expecting {s}", .{e});
        return alloc.dupe(u8, "syntax error, unexpected end of file");
    }
    if (expecting) |e| return std.fmt.allocPrint(alloc, "syntax error, unexpected token \"{s}\", expecting {s}", .{ lexeme, e });
    return std.fmt.allocPrint(alloc, "syntax error, unexpected token \"{s}\"", .{lexeme});
}

// a compile-time fatal in the script being run, reported like a parse error
pub fn formatCompileError(alloc: std.mem.Allocator, ast: *const Ast, file_path: []const u8, diag: Diagnostic) []const u8 {
    var buf: Writer = .empty;
    const tok = ast.tokens[diag.token];
    const loc = Chunk.locationFromOffset(ast.source, tok.start);
    writeFmt(&buf, alloc, "\nFatal error: {s} in {s} on line {d}\n\n", .{ diag.message(), displayPath(file_path), loc.line });
    writeSourceSnippet(&buf, alloc, ast.source, loc, tok.end - tok.start);
    return buf.items;
}

pub fn compileErrorLine(ast: *const Ast, diag: Diagnostic) i64 {
    return @intCast(Chunk.locationFromOffset(ast.source, ast.tokens[diag.token].start).line);
}

pub fn parseErrorLine(ast: *const Ast) i64 {
    if (ast.errors.len == 0) return 0;
    const err = ast.errors[0];
    return @intCast(Chunk.locationFromOffset(ast.source, ast.tokens[err.token].start).line + err.line_delta);
}

// a heredoc's indentation errors, worded as php words them; null for
// every other error
fn heredocMessage(alloc: std.mem.Allocator, err: Ast.Error) ?[]const u8 {
    return switch (err.tag) {
        .heredoc_mixed_indentation => "Invalid indentation - tabs and spaces cannot be mixed",
        .heredoc_body_indentation => std.fmt.allocPrint(alloc, "Invalid body indentation level (expecting an indentation level of at least {d})", .{err.detail}) catch null,
        else => null,
    };
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
        .real_cast_removed => "The (real) cast has been removed, use (float) instead",
        .void_cast_misplaced => "syntax error, unexpected token \"(void)\"",
        .heredoc_mixed_indentation => "Invalid indentation - tabs and spaces cannot be mixed",
        .heredoc_body_indentation => "Invalid body indentation level",
    };
}

pub fn formatRuntimeError(alloc: std.mem.Allocator, vm: *const VM) []const u8 {
    var buf: Writer = .empty;

    if (vm.error_msg) |msg| {
        // some error_msg values already have a leading 'Fatal error:' or
        // similar prefix (set via setErrorMsg("Fatal error: ..."). detect
        // and pass through; otherwise treat as a bare message and add PHP's
        // 'PHP Fatal error:' prefix + 'in {path} on line N' suffix
        if (std.mem.startsWith(u8, msg, "PHP ") or std.mem.startsWith(u8, msg, "Fatal error:") or std.mem.startsWith(u8, msg, "\nFatal error:")) {
            write(&buf, alloc, msg);
            appendLocationContext(&buf, alloc, vm);
        } else {
            writeFmt(&buf, alloc, "PHP Fatal error:  {s}", .{msg});
            appendPhpLocationLine(&buf, alloc, vm);
            write(&buf, alloc, "Stack trace:\n");
            writeStackTrace(&buf, alloc, vm);
        }
    } else {
        write(&buf, alloc, "Fatal error: unknown runtime error");
        appendLocationContext(&buf, alloc, vm);
    }

    return buf.items;
}

// minimal PHP-format trailing 'in {path} on line N' line for bare fatals
// (no source snippet, no stack trace - matches 'PHP Fatal error:' output)
fn appendPhpLocationLine(buf: *Writer, alloc: std.mem.Allocator, vm: *const VM) void {
    if (vm.frame_count == 0) {
        write(buf, alloc, "\n");
        return;
    }
    const frame = &vm.frames[vm.frame_count - 1];
    const ip = if (frame.ip > 0) frame.ip - 1 else 0;
    const path = displayPath(vm.file_path);
    if (vm.sourceLocation(frame.chunk, ip)) |loc| {
        writeFmt(buf, alloc, " in {s} on line {d}\n", .{ path, loc.line });
    } else {
        writeFmt(buf, alloc, " in {s}\n", .{path});
    }
}

pub const Copy = enum { log, display };

// one copy of php's report for the pending uncaught exception: the log copy
// ("PHP Fatal error:  ...") or the display copy ("Fatal error: ..."); the
// caller routes each per log_errors and display_errors. description is the
// throwable's __toString (exceptions.uncaughtDescription), which runs php and
// so is computed by the caller. the caller owns the result
pub fn formatUncaught(alloc: std.mem.Allocator, vm: *const VM, copy: Copy, description: ?[]const u8) []const u8 {
    var buf: Writer = .empty;
    if (vm.pending_exception) |exc| formatUncaughtException(&buf, alloc, vm, exc, .{ .copy = copy, .description = description });
    return buf.toOwnedSlice(alloc) catch "";
}

const UncaughtReport = struct { copy: Copy, description: ?[]const u8 };

fn formatUncaughtException(buf: *Writer, alloc: std.mem.Allocator, vm: *const VM, exc: Value, report: UncaughtReport) void {
    const copy = report.copy;
    var class_name: []const u8 = "Exception";
    var message: []const u8 = "";

    if (exc == .object) {
        class_name = exc.object.class_name;
        const msg = exc.object.get("message");
        if (msg == .string) message = msg.string.bytes();
    } else if (exc == .string) {
        message = exc.string.bytes();
    }

    const frame_idx = if (vm.frame_count > 0) vm.frame_count - 1 else 0;
    const frame = &vm.frames[frame_idx];
    const ip = if (frame.ip > 0) frame.ip - 1 else 0;
    // prefer the frame's own file - functions defined in required files
    // should report their own file path, not the top-level script's
    const frame_path: []const u8 = if (frame.func) |fn_| fn_.file_path else "";
    const path_raw: []const u8 = if (frame_path.len > 0) frame_path else vm.file_path;
    const path = displayPath(path_raw);
    const lead: []const u8 = if (copy == .log) "PHP " else "";
    const gap: []const u8 = if (copy == .log) ":  " else ": ";

    // an uncaught ParseError prints the way php reports a syntax error: at
    // the exception's own file and line, with no stack trace
    if (exc == .object and (std.mem.eql(u8, class_name, "ParseError") or std.mem.eql(u8, class_name, "CompileError"))) {
        const file_v = exc.object.get("file");
        const line_v = exc.object.get("line");
        const where = displayPath(if (file_v == .string) file_v.string.bytes() else path_raw);
        const line: i64 = if (line_v == .int) line_v.int else 0;
        const label: []const u8 = if (std.mem.eql(u8, class_name, "ParseError")) "Parse error" else "Fatal error";
        writeFmt(buf, alloc, "{s}{s}{s}{s} in {s} on line {d}\n", .{ lead, label, gap, message, where, line });
        return;
    }

    // uncatchable fatals (e.g. execution-time exceeded) are formatted as
    // bare fatals without the "Uncaught Class:" prefix or stack trace - this
    // matches how PHP prints `Maximum execution time of N seconds exceeded`
    if (vm.uncatchable_fatal) {
        if (vm.sourceLocation(frame.chunk, ip)) |loc| {
            writeFmt(buf, alloc, "{s}Fatal error{s}{s} in {s} on line {d}\n", .{ lead, gap, message, path, loc.line });
        } else {
            writeFmt(buf, alloc, "{s}Fatal error{s}{s} in {s}\n", .{ lead, gap, message, path });
        }
        return;
    }

    // php prints the throwable's own string form and where it was thrown, both
    // taken from the object: the frames that threw it may be long gone
    if (exc == .object) {
        const file_v = exc.object.get("file");
        const line_v = exc.object.get("line");
        const where = displayPath(if (file_v == .string) file_v.string.bytes() else "");
        const line: i64 = if (line_v == .int) line_v.int else 0;
        writeFmt(buf, alloc, "{s}Fatal error{s}Uncaught {s}\n  thrown in {s} on line {d}\n", .{ lead, gap, report.description orelse "", where, line });
        return;
    }

    // the header uses 'in {path}:{line}' (the exception format, not the
    // 'on line N' fatal format). no source-line snippet - the stack trace
    // names the site
    const maybe_loc = vm.sourceLocation(frame.chunk, ip);
    if (maybe_loc) |loc| {
        writeFmt(buf, alloc, "{s}Fatal error{s}Uncaught {s}: {s} in {s}:{d}\n", .{ lead, gap, class_name, message, path, loc.line });
    } else {
        writeFmt(buf, alloc, "{s}Fatal error{s}Uncaught {s}: {s} in {s}\n", .{ lead, gap, class_name, message, path });
    }
    write(buf, alloc, "Stack trace:\n");
    writeStackTrace(buf, alloc, vm);
    if (maybe_loc) |loc| {
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
    const source = vm.chunkSource(frame.chunk);
    const path = displayPath(framePath(frame, vm));

    if (vm.sourceLocation(frame.chunk, ip)) |loc| {
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


    var depth: u32 = 0;

    var i: usize = vm.frame_count - 1;
    while (i >= 1) : ({
        i -= 1;
        depth += 1;
    }) {
        const frame = &vm.frames[i];
        const caller = &vm.frames[i - 1];
        const caller_ip = if (caller.ip > 0) caller.ip - 1 else 0;

        const caller_path = framePath(caller, vm);
        const display = displayPath(caller_path);

        write(buf, alloc, "#");
        writeFmt(buf, alloc, "{d} ", .{depth});
        if (vm.sourceLocation(caller.chunk, caller_ip)) |loc| {
            writeFmt(buf, alloc, "{s}({d}): ", .{ display, loc.line });
        } else {
            writeFmt(buf, alloc, "{s}: ", .{display});
        }
        writeFrameCallee(buf, alloc, vm, frame, i);
        write(buf, alloc, "\n");
    }

    writeFmt(buf, alloc, "#{d} {{main}}\n", .{depth});
}

fn framePath(frame: anytype, vm: *const VM) []const u8 {
    if (frame.script_path.len > 0) return frame.script_path;
    if (frame.func) |f| if (f.file_path.len > 0) return f.file_path;
    return vm.file_path;
}

fn writeFrameCallee(buf: *Writer, alloc: std.mem.Allocator, vm: *const VM, frame: anytype, frame_idx: usize) void {
    const func = frame.func orelse {
        write(buf, alloc, "{main}()");
        return;
    };
    // method names are stored as "Class::method"; split on the separator and
    // pick the call-type from the function's static flag. instance dispatch
    // through fnames stored without the prefix falls back to called_class
    if (std.mem.indexOf(u8, func.name, "::")) |sep| {
        const class = func.name[0..sep];
        const method = func.name[sep + 2 ..];
        const type_str: []const u8 = if (func.is_static) "::" else "->";
        writeFmt(buf, alloc, "{s}{s}{s}(", .{ class, type_str, method });
    } else if (frame.called_class) |cls| {
        const type_str: []const u8 = if (func.is_static) "::" else "->";
        writeFmt(buf, alloc, "{s}{s}{s}(", .{ cls, type_str, func.name });
    } else {
        writeFmt(buf, alloc, "{s}(", .{func.name});
    }
    writeFrameArgs(buf, alloc, vm, frame_idx);
    write(buf, alloc, ")");
}

fn writeFrameArgs(buf: *Writer, alloc: std.mem.Allocator, vm: *const VM, frame_idx: usize) void {
    const ic = vm.ic orelse return;
    if (frame_idx >= ic.arg_counts.len) return;
    const ac = ic.arg_counts[frame_idx];
    if (ac == 0xFF) return;
    const offset: usize = ic.fga_offsets[frame_idx];
    const arg_count: usize = ac;
    if (offset + arg_count > ic.fga_buf.len) return;
    for (0..arg_count) |a| {
        if (a > 0) write(buf, alloc, ", ");
        writeTraceArg(buf, alloc, ic.fga_buf[offset + a]);
    }
}

// a call argument the way php's traces show it: quoted strings cut to 15
// bytes, Array and Object(Class) placeholders, scalars as they are
// php's smart_str_append_escaped: backslashes and control bytes escaped,
// anything outside printable ascii as \xHH
fn writeEscaped(buf: *Writer, alloc: std.mem.Allocator, bytes: []const u8) void {
    for (bytes) |c| switch (c) {
        '\n' => write(buf, alloc, "\\n"),
        '\r' => write(buf, alloc, "\\r"),
        '\t' => write(buf, alloc, "\\t"),
        0x0c => write(buf, alloc, "\\f"),
        0x0b => write(buf, alloc, "\\v"),
        0x1b => write(buf, alloc, "\\e"),
        '\\' => write(buf, alloc, "\\\\"),
        else => if (c < 32 or c > 126) writeFmt(buf, alloc, "\\x{X:0>2}", .{c}) else writeFmt(buf, alloc, "{c}", .{c}),
    };
}

pub fn writeTraceArg(buf: *Writer, alloc: std.mem.Allocator, v: Value) void {
    switch (v) {
        .null => write(buf, alloc, "NULL"),
        .bool => |b| write(buf, alloc, if (b) "true" else "false"),
        .int => |n| writeFmt(buf, alloc, "{d}", .{n}),
        .float => |f| writeFmt(buf, alloc, "{d}", .{f}),
        .string => |s| {
            // a closure passed as a callable is its synthetic name in zphp
            if (std.mem.startsWith(u8, s.bytes(), "__closure_")) {
                write(buf, alloc, "Object(Closure)");
            } else {
                const bytes = s.bytes();
                write(buf, alloc, "'");
                writeEscaped(buf, alloc, bytes[0..@min(bytes.len, 15)]);
                write(buf, alloc, if (bytes.len > 15) "...'" else "'");
            }
        },
        .array => write(buf, alloc, "Array"),
        .object => |o| writeFmt(buf, alloc, "Object({s})", .{o.class_name}),
        else => write(buf, alloc, "?"),
    }
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
