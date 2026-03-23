const std = @import("std");
const posix = std.posix;

const STDERR = posix.STDERR_FILENO;

// colors
const reset = "\x1b[0m";
const bold = "\x1b[1m";
const dim = "\x1b[2m";
const green = "\x1b[32m";
const yellow = "\x1b[33m";
const blue = "\x1b[34m";
const magenta = "\x1b[35m";
const cyan = "\x1b[36m";
const red = "\x1b[31m";
const bold_green = "\x1b[1;32m";
const bold_cyan = "\x1b[1;36m";
const bold_red = "\x1b[1;31m";
const bold_yellow = "\x1b[1;33m";
const bold_white = "\x1b[1;37m";

pub fn write(msg: []const u8) void {
    _ = posix.write(STDERR, msg) catch {};
}

pub fn writeColor(color: []const u8, msg: []const u8) void {
    write(color);
    write(msg);
    write(reset);
}

pub fn header(label: []const u8) void {
    write(bold_green);
    write(label);
    write(reset);
    write("\n");
}

pub fn step(label: []const u8, detail: []const u8) void {
    write("  ");
    write(bold_cyan);
    write(label);
    write(reset);
    write(" ");
    write(detail);
    write("\n");
}

pub fn item(name: []const u8, version: []const u8) void {
    write("  ");
    write(cyan);
    write(name);
    write(reset);
    write(" ");
    write(dim);
    write(version);
    write(reset);
    write("\n");
}

pub fn success(msg: []const u8) void {
    write(bold_green);
    write("  done");
    write(reset);
    write(" ");
    write(msg);
    write("\n");
}

pub fn err(msg: []const u8) void {
    write(bold_red);
    write("  error");
    write(reset);
    write(" ");
    write(msg);
    write("\n");
}

pub fn warn(msg: []const u8) void {
    write(bold_yellow);
    write("  warn");
    write(reset);
    write(" ");
    write(msg);
    write("\n");
}

pub fn progress(current: usize, total: usize, name: []const u8) void {
    write("\r  ");
    write(dim);
    var buf: [32]u8 = undefined;
    const counter = std.fmt.bufPrint(&buf, "[{d}/{d}]", .{ current, total }) catch "?";
    write(counter);
    write(reset);
    write(" ");
    write(name);
    // clear rest of line
    write("\x1b[K");
}

pub fn progressDone(total: usize, label: []const u8) void {
    write("\r");
    write(bold_green);
    write("  done");
    write(reset);
    write(" ");
    var buf: [64]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "{d} {s}", .{ total, label }) catch "?";
    write(msg);
    write("\x1b[K\n");
}

pub fn timing(label: []const u8, ms: u64) void {
    write("  ");
    write(dim);
    write(label);
    write(" in ");
    var buf: [32]u8 = undefined;
    if (ms < 1000) {
        const s = std.fmt.bufPrint(&buf, "{d}ms", .{ms}) catch "?";
        write(s);
    } else {
        const secs = @as(f64, @floatFromInt(ms)) / 1000.0;
        const s = std.fmt.bufPrint(&buf, "{d:.1}s", .{secs}) catch "?";
        write(s);
    }
    write(reset);
    write("\n");
}

pub fn blank() void {
    write("\n");
}

pub fn heading(text: []const u8) void {
    write(bold_white);
    write(text);
    write(reset);
    write("\n");
}

pub fn tableRow(col1: []const u8, col2: []const u8, col3: []const u8) void {
    write("  ");
    write(cyan);
    write(col1);
    write(reset);
    // pad to 40 chars
    var pad: usize = if (col1.len < 38) 38 - col1.len else 2;
    while (pad > 0) : (pad -= 1) write(" ");
    write(dim);
    write(col2);
    write(reset);
    if (col3.len > 0) {
        var pad2: usize = if (col2.len < 14) 14 - col2.len else 2;
        while (pad2 > 0) : (pad2 -= 1) write(" ");
        write(dim);
        write(col3);
        write(reset);
    }
    write("\n");
}
