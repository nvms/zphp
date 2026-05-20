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
    if (frame.chunk.getSourceLocation(ip, vm.source)) |loc| {
        writeFmt(buf, alloc, " in {s} on line {d}\n", .{ path, loc.line });
    } else {
        writeFmt(buf, alloc, " in {s}\n", .{path});
    }
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
    // prefer the frame's own file - functions defined in required files
    // should report their own file path, not the top-level script's
    const frame_path: []const u8 = if (frame.func) |fn_| fn_.file_path else "";
    const path_raw: []const u8 = if (frame_path.len > 0) frame_path else vm.file_path;
    const path = displayPath(path_raw);
    // when the frame is in a different file from vm.source, the lines table
    // for that chunk holds byte offsets into the FILE's source, not vm.source.
    // load the file once for accurate line resolution; fall back to vm.source
    var loaded_source: []const u8 = "";
    var source: []const u8 = vm.source;
    if (frame_path.len > 0 and !std.mem.eql(u8, frame_path, vm.file_path)) {
        if (std.fs.cwd().readFileAlloc(alloc, frame_path, 8 * 1024 * 1024)) |contents| {
            loaded_source = contents;
            source = contents;
        } else |_| {}
    }
    defer if (loaded_source.len > 0) alloc.free(loaded_source);

    // uncatchable fatals (e.g. execution-time exceeded) are formatted as
    // bare fatals without the "Uncaught Class:" prefix or stack trace - this
    // matches how PHP prints `Maximum execution time of N seconds exceeded`
    if (vm.uncatchable_fatal) {
        if (frame.chunk.getSourceLocation(ip, source)) |loc| {
            writeFmt(buf, alloc, "\nFatal error: {s} in {s} on line {d}\n", .{ message, path, loc.line });
        } else {
            writeFmt(buf, alloc, "\nFatal error: {s} in {s}\n", .{ message, path });
        }
        return;
    }

    // PHP emits the log_errors copy with the 'PHP ' prefix always; the bare
    // 'Fatal error:' display copy is emitted only when display_errors is on.
    // header uses 'in {path}:{line}' (the exception format, not the 'on line N'
    // fatal format). no source-line snippet - the stack trace names the site
    const maybe_loc = frame.chunk.getSourceLocation(ip, source);
    const display_on = vm.displayErrorsEnabled();
    var blocks: u8 = 0;
    while (blocks < 2) : (blocks += 1) {
        if (blocks == 1 and !display_on) break;
        const prefix: []const u8 = if (blocks == 0) "PHP Fatal error:  Uncaught" else "Fatal error: Uncaught";
        if (blocks == 1) write(buf, alloc, "\n");
        if (maybe_loc) |loc| {
            writeFmt(buf, alloc, "{s} {s}: {s} in {s}:{d}\n", .{ prefix, class_name, message, path, loc.line });
        } else {
            writeFmt(buf, alloc, "{s} {s}: {s} in {s}\n", .{ prefix, class_name, message, path });
        }
        write(buf, alloc, "Stack trace:\n");
        writeStackTrace(buf, alloc, vm);
        if (maybe_loc) |loc| {
            writeFmt(buf, alloc, "  thrown in {s} on line {d}\n", .{ path, loc.line });
        } else {
            writeFmt(buf, alloc, "  thrown in {s}\n", .{path});
        }
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

    // cache loaded file contents so multi-frame traces don't reload the same
    // file repeatedly. each entry's source is the caller frame's file (not
    // vm.source) because the caller's bytecode-to-line table only resolves
    // correctly against the source it was compiled from
    var source_cache: std.StringHashMapUnmanaged([]const u8) = .{};
    defer {
        var it = source_cache.valueIterator();
        while (it.next()) |v| if (v.*.len > 0) alloc.free(v.*);
        source_cache.deinit(alloc);
    }

    var depth: u32 = 0;
    // synthetic depth-0 frame for the throwing native (e.g. random_bytes(-1))
    // when an uncaught exception originated from a native call. matches PHP
    // which always includes the native in the stack trace at #0
    if (vm.pending_native_name) |nname| {
        const top = &vm.frames[vm.frame_count - 1];
        const top_ip = if (top.ip > 0) top.ip - 1 else 0;
        const top_path = framePath(top, vm);
        const top_source = resolveSource(alloc, &source_cache, top_path, vm);
        const top_display = displayPath(top_path);
        write(buf, alloc, "#");
        writeFmt(buf, alloc, "{d} ", .{depth});
        if (top.chunk.getSourceLocation(top_ip, top_source)) |loc| {
            writeFmt(buf, alloc, "{s}({d}): ", .{ top_display, loc.line });
        } else {
            writeFmt(buf, alloc, "{s}: ", .{top_display});
        }
        // instance-method natives render 'Class->method'; static / plain
        // functions keep the stored 'Class::method' / 'func' form
        if (vm.pending_native_is_instance) {
            if (std.mem.indexOf(u8, nname, "::")) |sep| {
                writeFmt(buf, alloc, "{s}->{s}(", .{ nname[0..sep], nname[sep + 2 ..] });
            } else {
                writeFmt(buf, alloc, "{s}(", .{nname});
            }
        } else {
            writeFmt(buf, alloc, "{s}(", .{nname});
        }
        for (vm.pending_native_args, 0..) |a, ai| {
            if (ai > 0) write(buf, alloc, ", ");
            writeArgValue(buf, alloc, a);
        }
        write(buf, alloc, ")\n");
        depth += 1;
    }

    var i: usize = vm.frame_count - 1;
    while (i >= 1) : ({
        i -= 1;
        depth += 1;
    }) {
        const frame = &vm.frames[i];
        const caller = &vm.frames[i - 1];
        const caller_ip = if (caller.ip > 0) caller.ip - 1 else 0;

        const caller_path = framePath(caller, vm);
        const caller_source = resolveSource(alloc, &source_cache, caller_path, vm);
        const display = displayPath(caller_path);

        write(buf, alloc, "#");
        writeFmt(buf, alloc, "{d} ", .{depth});
        if (caller.chunk.getSourceLocation(caller_ip, caller_source)) |loc| {
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

fn resolveSource(alloc: std.mem.Allocator, cache: *std.StringHashMapUnmanaged([]const u8), path: []const u8, vm: *const VM) []const u8 {
    if (std.mem.eql(u8, path, vm.file_path)) return vm.source;
    if (cache.get(path)) |hit| return hit;
    var loaded: []const u8 = "";
    if (std.fs.cwd().readFileAlloc(alloc, path, 8 * 1024 * 1024)) |contents| {
        loaded = contents;
    } else |_| {}
    cache.put(alloc, path, loaded) catch {};
    return loaded;
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
        writeArgValue(buf, alloc, ic.fga_buf[offset + a]);
    }
}

fn writeArgValue(buf: *Writer, alloc: std.mem.Allocator, v: Value) void {
    switch (v) {
        .null => write(buf, alloc, "NULL"),
        .bool => |b| write(buf, alloc, if (b) "true" else "false"),
        .int => |n| writeFmt(buf, alloc, "{d}", .{n}),
        .float => |f| writeFmt(buf, alloc, "{d}", .{f}),
        .string => |s| {
            // PHP truncates long strings to 15 chars + '...'
            if (s.len <= 15) {
                writeFmt(buf, alloc, "'{s}'", .{s});
            } else {
                writeFmt(buf, alloc, "'{s}...'", .{s[0..15]});
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
