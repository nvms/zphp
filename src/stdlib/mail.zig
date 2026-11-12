// php's ext/standard/mail.c: mail() hands the message to sendmail_path
// through the shell, as popen() does
const std = @import("std");
const builtin = @import("builtin");
const platform = @import("../platform.zig");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const Args = @import("string_ports.zig").Args;
const fs = @import("filesystem.zig");
const phpTypeName = @import("types.zig").phpTypeName;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const entries = .{
    .{ "mail", native_mail },
};

pub const default_sendmail_path = "/usr/sbin/sendmail -t -i";

// the mail.* entries and sendmail_path are PHP_INI_SYSTEM|PHP_INI_PERDIR:
// ini_set() can't change them
pub fn isSystemIni(name: []const u8) bool {
    const names = [_][]const u8{ "sendmail_path", "mail.log", "mail.add_x_header", "mail.force_extra_parameters", "mail.mixed_lf_and_crlf", "mail.cr_lf_mode" };
    for (names) |n| if (std.mem.eql(u8, n, name)) return true;
    return false;
}

fn ini(ctx: *NativeContext, name: []const u8) ?[]const u8 {
    return ctx.vm.ini_settings.get(name);
}

fn iniBool(ctx: *NativeContext, name: []const u8) bool {
    const v = ini(ctx, name) orelse return false;
    if (std.ascii.eqlIgnoreCase(v, "true") or std.ascii.eqlIgnoreCase(v, "yes") or std.ascii.eqlIgnoreCase(v, "on")) return true;
    return (std.fmt.parseInt(i64, std.mem.trim(u8, v, " "), 10) catch 0) != 0;
}

// php formats header names with %s, which ends at a nul byte
fn cstr(s: []const u8) []const u8 {
    return s[0 .. std.mem.indexOfScalar(u8, s, 0) orelse s.len];
}

fn throw(ctx: *NativeContext, class: []const u8, comptime fmt: []const u8, args: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException(class, msg);
    return error.RuntimeError;
}

const HeaderValueError = enum { none, lf_only, cr_only, crlf, nul };

fn checkFieldValue(v: []const u8) HeaderValueError {
    var i: usize = 0;
    while (i < v.len) {
        if (v[i] == '\r') {
            if (i + 1 >= v.len or v[i + 1] != '\n') return .cr_only;
            if (v.len - i >= 3 and (v[i + 2] == ' ' or v[i + 2] == '\t')) {
                i += 3;
                continue;
            }
            return .crlf;
        }
        if (v[i] == '\n') {
            if (v.len - i >= 2 and (v[i + 1] == ' ' or v[i + 1] == '\t')) {
                i += 2;
                continue;
            }
            return .lf_only;
        }
        if (v[i] == 0) return .nul;
        i += 1;
    }
    return .none;
}

fn checkFieldName(k: []const u8) bool {
    for (k) |c| if (c < 33 or c > 126 or c == ':') return false;
    return true;
}

fn buildElem(ctx: *NativeContext, out: *std.ArrayListUnmanaged(u8), key: []const u8, val: Value) RuntimeError!void {
    switch (val) {
        .string => |s| {
            if (!checkFieldName(key)) return throw(ctx, "ValueError", "Header name \"{s}\" contains invalid characters", .{cstr(key)});
            switch (checkFieldValue(s.bytes())) {
                .none => {},
                .lf_only => return throw(ctx, "ValueError", "Header \"{s}\" contains LF character that is not allowed in the header", .{cstr(key)}),
                .cr_only => return throw(ctx, "ValueError", "Header \"{s}\" contains CR character that is not allowed in the header", .{cstr(key)}),
                .crlf => return throw(ctx, "ValueError", "Header \"{s}\" contains CRLF characters that are used as a line separator and are not allowed in the header", .{cstr(key)}),
                .nul => return throw(ctx, "ValueError", "Header \"{s}\" contains NULL character that is not allowed in the header", .{cstr(key)}),
            }
            try out.appendSlice(ctx.allocator, key);
            try out.appendSlice(ctx.allocator, ": ");
            // smart_str_appends: the value as a c string
            const bytes = s.bytes();
            try out.appendSlice(ctx.allocator, bytes[0 .. std.mem.indexOfScalar(u8, bytes, 0) orelse bytes.len]);
            try out.appendSlice(ctx.allocator, "\r\n");
        },
        .array => |arr| try buildElems(ctx, out, key, arr),
        else => return throw(ctx, "TypeError", "Header \"{s}\" must be of type array|string, {s} given", .{ cstr(key), phpTypeName(val) }),
    }
}

fn buildElems(ctx: *NativeContext, out: *std.ArrayListUnmanaged(u8), key: []const u8, arr: *PhpArray) RuntimeError!void {
    for (arr.entries.items) |entry| {
        if (entry.key == .string) return throw(ctx, "TypeError", "Header \"{s}\" must only contain numeric keys, \"{s}\" found", .{ cstr(key), cstr(entry.key.string.bytes()) });
        const v = entry.value;
        if (v != .string) return throw(ctx, "TypeError", "Header \"{s}\" must only contain values of type string, {s} found", .{ cstr(key), phpTypeName(v) });
        try buildElem(ctx, out, key, v);
    }
}

// php_mail_build_headers
fn buildHeaders(ctx: *NativeContext, headers: *PhpArray) RuntimeError![]u8 {
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(ctx.allocator);
    const single = [_][]const u8{ "orig-date", "from", "sender", "reply-to", "cc", "bcc", "message-id", "references", "in-reply-to" };
    for (headers.entries.items) |entry| {
        if (entry.key != .string) return throw(ctx, "TypeError", "Header name cannot be numeric, {d} given", .{entry.key.int});
        const key = entry.key.string.bytes();
        const val = entry.value;
        if (std.ascii.eqlIgnoreCase(key, "to")) return throw(ctx, "ValueError", "The additional headers cannot contain the \"To\" header", .{});
        if (std.ascii.eqlIgnoreCase(key, "subject")) return throw(ctx, "ValueError", "The additional headers cannot contain the \"Subject\" header", .{});
        var target: ?[]const u8 = null;
        for (single) |name| if (std.ascii.eqlIgnoreCase(key, name)) {
            target = name;
        };
        switch (val) {
            .string => try buildElem(ctx, &out, key, val),
            .array => |arr| {
                if (target) |t| return throw(ctx, "TypeError", "Header \"{s}\" must be of type string, array given", .{t});
                try buildElems(ctx, &out, key, arr);
            },
            else => return throw(ctx, "TypeError", "Header \"{s}\" must be of type array|string, {s} given", .{ cstr(key), phpTypeName(val) }),
        }
    }
    if (out.items.len >= 2) out.items.len -= 2;
    return out.toOwnedSlice(ctx.allocator);
}

// trailing whitespace dropped, control characters turned into spaces except
// a folded line's CRLF + whitespace
fn sanitizeField(a: std.mem.Allocator, field: []const u8) ![]u8 {
    // the c string ends at its first nul (Z_PARAM_PATH already refused one)
    var len = field.len;
    while (len > 0 and std.ascii.isWhitespace(field[len - 1])) len -= 1;
    const out = try a.dupe(u8, field[0..len]);
    var i: usize = 0;
    while (i < out.len) : (i += 1) {
        if (out[i] < 0x20 or out[i] == 0x7f) {
            if (out[i] == '\r' and i + 2 < out.len and out[i + 1] == '\n' and (out[i + 2] == ' ' or out[i + 2] == '\t')) {
                i += 2;
                while (i + 1 < out.len and (out[i + 1] == ' ' or out[i + 1] == '\t')) i += 1;
                continue;
            }
            out[i] = ' ';
        }
    }
    return out;
}

// php_mail_detect_multiple_crlf
fn detectMultipleCrlf(hdr: []const u8) bool {
    if (hdr.len == 0) return false;
    if (hdr[0] < 33 or hdr[0] > 126 or hdr[0] == ':') return true;
    const at = struct {
        fn f(s: []const u8, i: usize) u8 {
            return if (i < s.len) s[i] else 0;
        }
    }.f;
    var i: usize = 0;
    while (i < hdr.len) {
        if (hdr[i] == '\r') {
            const n1 = at(hdr, i + 1);
            const n2 = at(hdr, i + 2);
            if (n1 == 0 or n1 == '\r' or (n1 == '\n' and (n2 == 0 or n2 == '\n' or n2 == '\r'))) return true;
            i += 2;
        } else if (hdr[i] == '\n') {
            const n1 = at(hdr, i + 1);
            if (n1 == 0 or n1 == '\r' or n1 == '\n') return true;
            i += 2;
        } else i += 1;
    }
    return false;
}

fn trimHeaders(s: []const u8) []const u8 {
    // php_trim(headers, NULL, 0, 2): right trim of " \t\n\r\v\0"
    var end = s.len;
    while (end > 0 and std.mem.indexOfScalar(u8, " \t\n\r\x0b\x00", s[end - 1]) != null) end -= 1;
    return s[0..end];
}

extern "c" fn strsignal(sig: c_int) ?[*:0]const u8;
extern "c" fn getuid() c_uint;

fn native_mail(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const a = ctx.allocator;
    const p = Args.init(ctx, "mail", args);
    const to = try p.str(0, "to");
    if (std.mem.indexOfScalar(u8, to, 0) != null) return p.valueError(0, "to", "must not contain any null bytes");
    const subject = try p.str(1, "subject");
    if (std.mem.indexOfScalar(u8, subject, 0) != null) return p.valueError(1, "subject", "must not contain any null bytes");
    const message = try p.str(2, "message");
    if (std.mem.indexOfScalar(u8, message, 0) != null) return p.valueError(2, "message", "must not contain any null bytes");

    var headers_owned: ?[]u8 = null;
    defer if (headers_owned) |h| a.free(h);
    var headers: ?[]const u8 = null;
    if (args.len > 3) {
        switch (args[3]) {
            .array => |arr| {
                headers_owned = try buildHeaders(ctx, arr);
                headers = headers_owned;
            },
            else => {
                const h = try p.strAs(3, "additional_headers", "array|string");
                if (std.mem.indexOfScalar(u8, h, 0) != null) return p.valueError(3, "additional_headers", "must not contain any null bytes");
                headers = trimHeaders(h);
            },
        }
    }
    var extra: ?[]const u8 = null;
    if (args.len > 4) {
        const e = try p.str(4, "additional_params");
        if (std.mem.indexOfScalar(u8, e, 0) != null) return p.valueError(4, "additional_params", "must not contain any null bytes");
        extra = e;
    }

    const to_r = try sanitizeField(a, to);
    defer a.free(to_r);
    const subject_r = try sanitizeField(a, subject);
    defer a.free(subject_r);

    var extra_cmd: ?[]const u8 = null;
    defer if (extra_cmd) |e| a.free(e);
    const forced = ini(ctx, "mail.force_extra_parameters");
    if (forced != null and forced.?.len > 0) {
        extra_cmd = try escapeShellCmd(ctx, forced.?);
    } else if (extra) |e| {
        extra_cmd = try escapeShellCmd(ctx, e);
    }

    const hdr: ?[]const u8 = if (headers != null and headers.?.len > 0) headers else null;
    return NativeResult.scalar(.{ .bool = try phpMail(ctx, to_r, subject_r, message, hdr, extra_cmd) });
}

fn escapeShellCmd(ctx: *NativeContext, s: []const u8) RuntimeError![]u8 {
    const r = try ctx.vm.callByName("escapeshellcmd", &.{.{ .string = Value.String.borrowed(s) }});
    return ctx.allocator.dupe(u8, if (r == .string) r.string.bytes() else "");
}

fn phpMail(ctx: *NativeContext, to: []const u8, subject: []const u8, message_full: []const u8, headers: ?[]const u8, extra_cmd: ?[]const u8) RuntimeError!bool {
    const a = ctx.allocator;
    const message = message_full[0 .. std.mem.indexOfScalar(u8, message_full, 0) orelse message_full.len];
    var hdr: ?[]const u8 = headers;

    const mail_log = ini(ctx, "mail.log") orelse "";
    if (mail_log.len > 0) {
        const pos = ctx.vm.currentSourcePosition();
        const logline = try std.fmt.allocPrint(a, "mail() on [{s}:{d}]: To: {s} -- Headers: {s} -- Subject: {s}", .{ pos.file, pos.line, to, hdr orelse "", subject });
        defer a.free(logline);
        if (hdr != null) {
            for (logline) |*c| if (c.* == '\r' or c.* == '\n') {
                c.* = ' ';
            };
        }
        if (std.mem.eql(u8, mail_log, "syslog")) {
            try @import("syslog.zig").log(ctx, 5, logline);
        } else {
            const date = try ctx.vm.callByName("date", &.{.{ .string = Value.String.borrowed("d-M-Y H:i:s e") }});
            const eol = if (platform.is_windows) "\r\n" else "\n";
            const line = try std.fmt.allocPrint(a, "[{s}] {s}{s}", .{ if (date == .string) date.string.bytes() else "", logline, eol });
            defer a.free(line);
            if (try fs.openStreamValue(ctx, mail_log, "a", null)) |stream| {
                stream.resource.retain();
                defer ctx.vm.releaseValue(stream);
                _ = try @import("streams.zig").write(ctx, stream.resource, line);
                _ = try fs.closeStream(ctx, stream.resource);
            }
        }
    }
    if (ctx.vm.pending_exception != null) return error.RuntimeError;

    const mode = ini(ctx, "mail.cr_lf_mode");
    const line_sep: []const u8 = if (mode != null and !std.mem.eql(u8, mode.?, "crlf"))
        (if (platform.is_windows and std.mem.eql(u8, mode.?, "os")) "\r\n" else "\n")
    else if (iniBool(ctx, "mail.mixed_lf_and_crlf")) "\n" else "\r\n";

    var ahdr: ?[]u8 = null;
    defer if (ahdr) |h| a.free(h);
    if (iniBool(ctx, "mail.add_x_header")) {
        const file = ctx.vm.currentSourcePosition().file;
        const base = std.fs.path.basename(file);
        const uid: i64 = if (platform.is_windows) 0 else getuid();
        ahdr = if (headers != null and headers.?.len > 0)
            try std.fmt.allocPrint(a, "X-PHP-Originating-Script: {d}:{s}{s}{s}", .{ uid, base, line_sep, headers.? })
        else
            try std.fmt.allocPrint(a, "X-PHP-Originating-Script: {d}:{s}", .{ uid, base });
        hdr = ahdr;
    }

    if (hdr != null and detectMultipleCrlf(hdr.?)) {
        try fs.warnDocref(ctx, "Multiple or malformed newlines found in additional_header", .{});
        return false;
    }

    const sendmail_path = ini(ctx, "sendmail_path") orelse default_sendmail_path;
    if (sendmail_path.len == 0) return false;
    const cmd = if (extra_cmd) |e| try std.fmt.allocPrint(a, "{s} {s}", .{ sendmail_path, e }) else try a.dupe(u8, sendmail_path);
    defer a.free(cmd);

    var input = std.ArrayListUnmanaged(u8).empty;
    defer input.deinit(a);
    try input.print(a, "To: {s}{s}", .{ to, line_sep });
    try input.print(a, "Subject: {s}{s}", .{ subject, line_sep });
    if (hdr) |h| try input.print(a, "{s}{s}", .{ h, line_sep });
    try input.appendSlice(a, line_sep);
    if (mode != null and std.mem.eql(u8, mode.?, "lf")) {
        var i: usize = 0;
        while (i < message.len) : (i += 1) {
            if (i + 1 < message.len and message[i] == '\r' and message[i + 1] == '\n') {
                try input.append(a, '\n');
                i += 1;
            } else try input.append(a, message[i]);
        }
    } else try input.appendSlice(a, message);
    try input.appendSlice(a, line_sep);

    // the child writes to the same stdout and stderr
    ctx.vm.flushOutputToStdout();
    const argv = platform.shellArgv(cmd);
    const result = platform.runChild(a, &argv, .{
        .stdin_data = input.items,
        .stdin = .ignore,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch {
        try fs.warnDocref(ctx, "Could not execute mail delivery program '{s}'", .{sendmail_path});
        return false;
    };
    a.free(result.stdout);
    a.free(result.stderr);
    switch (result.term) {
        .exited => |code| {
            // EX_OK and EX_TEMPFAIL count as sent
            if (code != 0 and code != 75) {
                try fs.warnDocref(ctx, "Sendmail exited with non-zero exit code {d}", .{code});
                return false;
            }
            return true;
        },
        .signal => |sig| {
            const n: c_int = @intCast(@backingInt(sig));
            const name: []const u8 = if (builtin.os.tag == .windows) "" else if (strsignal(n)) |s| std.mem.span(s) else "";
            try fs.warnDocref(ctx, "Sendmail killed by signal {d} ({s})", .{ n, name });
            return false;
        },
        else => {
            try fs.warnDocref(ctx, "Sendmail did not exit", .{});
            return false;
        },
    }
}
