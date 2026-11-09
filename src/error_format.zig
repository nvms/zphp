const std = @import("std");
const Chunk = @import("pipeline/bytecode.zig").Chunk;
const Ast = @import("pipeline/ast.zig").Ast;
const Value = @import("runtime/value.zig").Value;
const PhpObject = @import("runtime/value.zig").PhpObject;
const php_syntax = @import("pipeline/php_syntax.zig");
const VM = @import("runtime/vm.zig").VM;
const Diagnostic = @import("pipeline/compiler.zig").Diagnostic;
const class_names = @import("runtime/class_names.zig");

const Writer = std.ArrayListUnmanaged(u8);

fn write(buf: *Writer, alloc: std.mem.Allocator, data: []const u8) void {
    buf.appendSlice(alloc, data) catch {};
}

fn writeFmt(buf: *Writer, alloc: std.mem.Allocator, comptime fmt: []const u8, args: anytype) void {
    buf.print(alloc, fmt, args) catch {};
}

fn displayPath(file_path: []const u8) []const u8 {
    if (file_path.len == 0) return "<input>";
    return file_path;
}

pub const SyntaxError = php_syntax.SyntaxError;

// the source's first syntax error as php reports it. php's scanner words the
// heredoc and cast errors itself; the rest come from php's grammar, and an
// error only zphp's parser sees is named at the token where it stopped. the
// caller owns the message
pub fn syntaxError(alloc: std.mem.Allocator, ast: *const Ast) !SyntaxError {
    const err = if (ast.errors.len > 0) ast.errors[0] else return .{ .message = try alloc.dupe(u8, "syntax error"), .line = 0 };
    const tok = ast.tokens[err.token];
    const line = Chunk.locationFromOffset(ast.source, tok.start).line + err.line_delta;
    switch (err.tag) {
        .heredoc_mixed_indentation => return .{ .message = try alloc.dupe(u8, "Invalid indentation - tabs and spaces cannot be mixed"), .line = line },
        .heredoc_body_indentation => return .{ .message = try std.fmt.allocPrint(alloc, "Invalid body indentation level (expecting an indentation level of at least {d})", .{err.detail}), .line = line },
        .real_cast_removed => return .{ .message = try alloc.dupe(u8, "The (real) cast has been removed, use (float) instead"), .line = line },
        else => {},
    }
    if (try php_syntax.diagnose(alloc, ast.source)) |found| return found;
    return .{ .message = try php_syntax.unexpectedAt(alloc, ast.source, tok.start), .line = line };
}

// the error-log line php writes for a file that fails to parse or compile:
// its syntax error when the ast has one, else the compile diagnostic. the
// caller owns the result
pub fn compileFailureLog(alloc: std.mem.Allocator, ast: *const Ast, diag: ?Diagnostic, path: []const u8) ![]u8 {
    if (ast.errors.len > 0) {
        const found = try syntaxError(alloc, ast);
        defer alloc.free(found.message);
        return std.fmt.allocPrint(alloc, "PHP Parse error:  {s} in {s} on line {d}\n", .{ found.message, displayPath(path), found.line });
    }
    const d = diag orelse return alloc.dupe(u8, "PHP Fatal error:  compile error\n");
    return std.fmt.allocPrint(alloc, "PHP Fatal error:  {s} in {s} on line {d}\n", .{ d.message(), displayPath(path), compileErrorLine(ast, d) });
}

pub fn compileErrorLine(ast: *const Ast, diag: Diagnostic) i64 {
    return @intCast(Chunk.locationFromOffset(ast.source, ast.tokens[diag.token].start).line);
}

// an error_msg that carries php's own prefix and is printed as it is
pub fn hasFatalPrefix(msg: []const u8) bool {
    return std.mem.startsWith(u8, msg, "PHP ") or std.mem.startsWith(u8, msg, "Fatal error:") or std.mem.startsWith(u8, msg, "\nFatal error:");
}

pub fn formatRuntimeError(alloc: std.mem.Allocator, vm: *const VM) []const u8 {
    var buf: Writer = .empty;

    if (vm.error_msg) |raw_msg| {
        // the engine's messages name classes with %s, which stops at an
        // anonymous class's NUL
        const stripped = class_names.stripAnonymous(alloc, raw_msg) catch null;
        defer if (stripped) |s| alloc.free(s);
        const msg = stripped orelse raw_msg;
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
            if (vm.fatalErrorBacktraces()) {
                write(&buf, alloc, "Stack trace:\n");
                writeStackTrace(&buf, alloc, vm);
            }
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

    // an uncaught ParseError or CompileError prints the way php reports a
    // syntax error or compile-time fatal: at the exception's own file and line
    if (exc == .object and (std.mem.eql(u8, class_name, "ParseError") or std.mem.eql(u8, class_name, "CompileError"))) {
        const file_v = exc.object.get("file");
        const line_v = exc.object.get("line");
        const where = displayPath(if (file_v == .string) file_v.string.bytes() else path_raw);
        const line: i64 = if (line_v == .int) line_v.int else 0;
        const parse = std.mem.eql(u8, class_name, "ParseError");
        const label: []const u8 = if (parse) "Parse error" else "Fatal error";
        writeFmt(buf, alloc, "{s}{s}{s}{s} in {s} on line {d}\n", .{ lead, label, gap, message, where, line });
        if (!parse) writeFatalTrace(buf, alloc, vm, exc.object);
        return;
    }

    // uncatchable fatals (e.g. execution-time exceeded) are formatted as
    // bare fatals without the "Uncaught Class:" prefix or stack trace - this
    // matches how PHP prints `Maximum execution time of N seconds exceeded`
    if (vm.uncatchable_fatal) {
        const file_v = if (exc == .object) exc.object.get("file") else Value.null;
        const line_v = if (exc == .object) exc.object.get("line") else Value.null;
        if (file_v == .string and file_v.string.bytes().len > 0 and line_v == .int) {
            writeFmt(buf, alloc, "{s}Fatal error{s}{s} in {s} on line {d}\n", .{ lead, gap, message, file_v.string.bytes(), line_v.int });
        } else if (vm.sourceLocation(frame.chunk, ip)) |loc| {
            writeFmt(buf, alloc, "{s}Fatal error{s}{s} in {s} on line {d}\n", .{ lead, gap, message, path, loc.line });
        } else {
            writeFmt(buf, alloc, "{s}Fatal error{s}{s} in {s}\n", .{ lead, gap, message, path });
        }
        if (exc == .object) writeFatalTrace(buf, alloc, vm, exc.object);
        return;
    }

    // php prints the throwable's own string form and where it was thrown, both
    // taken from the object: the frames that threw it may be long gone
    if (exc == .object) {
        const file_v = exc.object.get("file");
        const line_v = exc.object.get("line");
        const where = displayPath(if (file_v == .string) file_v.string.bytes() else "");
        const line: i64 = if (line_v == .int) line_v.int else 0;
        const description = report.description orelse "";
        // the log formats the description with %s, which ends at a NUL, the
        // "thrown in" after it included; the display writes it whole
        if (copy == .log) if (std.mem.indexOfScalar(u8, description, 0)) |nul| {
            writeFmt(buf, alloc, "{s}Fatal error{s}Uncaught {s} in {s} on line {d}\n", .{ lead, gap, description[0..nul], where, line });
            return;
        };
        writeFmt(buf, alloc, "{s}Fatal error{s}Uncaught {s}\n  thrown in {s} on line {d}\n", .{ lead, gap, description, where, line });
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

// php 8.5's "Stack trace:" after a fatal error, from the stack the error
// recorded, unless fatal_error_backtraces is off
fn writeFatalTrace(buf: *Writer, alloc: std.mem.Allocator, vm: *const VM, err: *const PhpObject) void {
    if (!vm.fatalErrorBacktraces()) return;
    // a compile error php's parser raises
    if (err.get("__no_trace") == .bool) return;
    write(buf, alloc, "Stack trace:\n");
    writeTrace(buf, alloc, err.getForScope("trace", vm.exceptionTraceScope(err)));
    write(buf, alloc, "\n");
}

fn appendLocationContext(buf: *Writer, alloc: std.mem.Allocator, vm: *const VM) void {
    if (vm.frame_count == 0) {
        write(buf, alloc, "\n");
        return;
    }
    const frame = &vm.frames[vm.frame_count - 1];
    const ip = if (frame.ip > 0) frame.ip - 1 else 0;
    const path = displayPath(framePath(frame, vm));
    if (vm.sourceLocation(frame.chunk, ip)) |loc| {
        writeFmt(buf, alloc, " in {s} on line {d}\n", .{ path, loc.line });
    } else {
        writeFmt(buf, alloc, " in {s}\n", .{path});
    }
    if (!vm.fatalErrorBacktraces()) return;
    write(buf, alloc, "Stack trace:\n");
    writeStackTrace(buf, alloc, vm);
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
        writeFmt(buf, alloc, "{s}{s}{s}(", .{ class_names.display(class), type_str, method });
    } else if (frame.called_class) |cls| {
        const type_str: []const u8 = if (func.is_static) "::" else "->";
        writeFmt(buf, alloc, "{s}{s}{s}(", .{ class_names.display(cls), type_str, func.name });
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
        .object => |o| writeFmt(buf, alloc, "Object({s})", .{class_names.display(o.class_name)}),
        .generator => write(buf, alloc, "Object(Generator)"),
        .fiber => write(buf, alloc, "Object(Fiber)"),
        else => write(buf, alloc, "?"),
    }
}

// a throwable's trace array as getTraceAsString() prints it, ending with the
// {main} line and no newline
pub fn writeTrace(buf: *Writer, alloc: std.mem.Allocator, trace: Value) void {
    if (trace != .array) {
        write(buf, alloc, "#0 {main}");
        return;
    }
    for (trace.array.entries.items, 0..) |entry, i| {
        if (entry.value != .array) continue;
        const e = entry.value.array;
        const fn_s = stringField(e, "function") orelse "?";
        const class_s = class_names.display(stringField(e, "class") orelse "");
        const type_s = stringField(e, "type") orelse "";
        const file_s = stringField(e, "file") orelse "";
        const line_v = e.get(.{ .string = Value.String.borrowed("line") });
        const line_n: i64 = if (line_v == .int) line_v.int else 0;
        // a frame with no file/line was called from an internal function
        // (a native dispatched the user callback) - PHP renders these as
        // `[internal function]` instead of the synthesized `(0)` location
        if (file_s.len == 0 and line_n == 0) {
            writeFmt(buf, alloc, "#{d} [internal function]: {s}{s}{s}(", .{ i, class_s, type_s, fn_s });
        } else {
            writeFmt(buf, alloc, "#{d} {s}({d}): {s}{s}{s}(", .{ i, file_s, line_n, class_s, type_s, fn_s });
        }
        const args_v = e.get(.{ .string = Value.String.borrowed("args") });
        if (args_v == .array) {
            for (args_v.array.entries.items, 0..) |arg_entry, ai| {
                if (ai > 0) write(buf, alloc, ", ");
                writeTraceArg(buf, alloc, arg_entry.value);
            }
        }
        write(buf, alloc, ")\n");
    }
    writeFmt(buf, alloc, "#{d} {{main}}", .{trace.array.entries.items.len});
}

fn stringField(arr: anytype, key: []const u8) ?[]const u8 {
    const v = arr.get(.{ .string = Value.String.borrowed(key) });
    return if (v == .string) v.string.bytes() else null;
}
