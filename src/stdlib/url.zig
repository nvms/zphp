// php's url.c: php_url_parse_ex2, the parser behind parse_url()
const std = @import("std");

pub const Url = struct {
    scheme: ?[]const u8 = null,
    user: ?[]const u8 = null,
    pass: ?[]const u8 = null,
    host: ?[]const u8 = null,
    // php keeps the port as an unsigned short and has_port beside it; a
    // port of 0 doesn't count as "already seen" when the host part is read
    port: u16 = 0,
    has_port: bool = false,
    path: ?[]const u8 = null,
    query: ?[]const u8 = null,
    fragment: ?[]const u8 = null,
};

fn strcspn(str: []const u8, s: usize, e: usize, chars: []const u8) usize {
    var end = e;
    for (chars) |c| {
        if (std.mem.indexOfScalar(u8, str[s..end], c)) |i| end = s + i;
    }
    return end;
}

fn isSchemeChar(c: u8) bool {
    return std.ascii.isAlphabetic(c) or std.ascii.isDigit(c) or c == '+' or c == '.' or c == '-';
}

// ZEND_STRTOL over at most five bytes, then php's 0..65535 check; null
// when strtol reads no digits or the value is out of range
fn readPort(buf: []const u8) ?u16 {
    var i: usize = 0;
    while (i < buf.len and (buf[i] == ' ' or (buf[i] >= '\t' and buf[i] <= '\r'))) i += 1;
    var negative = false;
    if (i < buf.len and (buf[i] == '+' or buf[i] == '-')) {
        negative = buf[i] == '-';
        i += 1;
    }
    const start = i;
    var n: u32 = 0;
    while (i < buf.len and std.ascii.isDigit(buf[i])) : (i += 1) n = n * 10 + (buf[i] - '0');
    if (i == start) return null;
    if (negative and n != 0) return null;
    if (n > 65535) return null;
    return @intCast(n);
}

const Step = enum { scheme, parse_port, parse_host, just_path };

// the components are slices of `str`; php_replace_controlchars is left to
// the caller (`replaceControlChars`)
pub fn parse(str: []const u8) ?Url {
    var ret = Url{};
    var s: usize = 0;
    const ue: usize = str.len;
    var e: usize = 0;
    var p: usize = 0;

    var step: Step = .scheme;
    if (std.mem.indexOfScalar(u8, str, ':')) |colon| {
        e = colon;
        if (colon != 0) {
            step = .scheme;
        } else {
            step = .parse_port;
        }
    } else if (s + 1 < ue and str[s] == '/' and str[s + 1] == '/') {
        s += 2;
        step = .parse_host;
    } else {
        step = .just_path;
    }

    if (step == .scheme) scheme: {
        p = s;
        while (p < e) : (p += 1) {
            if (!isSchemeChar(str[p])) {
                if (e + 1 < ue and e < strcspn(str, s, ue, "?#")) {
                    step = .parse_port;
                } else if (s + 1 < ue and str[s] == '/' and str[s + 1] == '/') {
                    s += 2;
                    step = .parse_host;
                } else {
                    step = .just_path;
                }
                break :scheme;
            }
        }
        if (e + 1 == ue) {
            ret.scheme = str[s..e];
            return ret;
        }
        if (str[e + 1] != '/') {
            p = e + 1;
            while (p < ue and std.ascii.isDigit(str[p])) p += 1;
            if ((p == ue or str[p] == '/') and p - e < 7) {
                step = .parse_port;
                break :scheme;
            }
            ret.scheme = str[s..e];
            s = e + 1;
            step = .just_path;
            break :scheme;
        }
        ret.scheme = str[s..e];
        if (e + 2 < ue and str[e + 2] == '/') {
            s = e + 3;
            if (std.ascii.eqlIgnoreCase(ret.scheme.?, "file")) {
                if (e + 3 < ue and str[e + 3] == '/') {
                    // windows drive letters as in file:///c:/somedir/file.txt
                    if (e + 5 < ue and str[e + 5] == ':') s = e + 4;
                    step = .just_path;
                    break :scheme;
                }
            }
            step = .parse_host;
        } else {
            s = e + 1;
            step = .just_path;
        }
    }

    if (step == .parse_port) {
        p = e + 1;
        var pp = p;
        while (pp < ue and pp - p < 6 and std.ascii.isDigit(str[pp])) pp += 1;
        if (pp - p > 0 and pp - p < 6 and (pp == ue or str[pp] == '/')) {
            const port = readPort(str[p..pp]) orelse return null;
            ret.has_port = true;
            ret.port = port;
            if (s + 1 < ue and str[s] == '/' and str[s + 1] == '/') s += 2;
            step = .parse_host;
        } else if (p == pp and pp == ue) {
            return null;
        } else if (s + 1 < ue and str[s] == '/' and str[s + 1] == '/') {
            s += 2;
            step = .parse_host;
        } else {
            step = .just_path;
        }
    }

    if (step == .parse_host) host: {
        e = strcspn(str, s, ue, "/?#");
        if (std.mem.lastIndexOfScalar(u8, str[s..e], '@')) |at_rel| {
            const at = s + at_rel;
            if (std.mem.indexOfScalar(u8, str[s..at], ':')) |c_rel| {
                ret.user = str[s .. s + c_rel];
                ret.pass = str[s + c_rel + 1 .. at];
            } else {
                ret.user = str[s..at];
            }
            s = at + 1;
        }
        var colon: ?usize = null;
        if (!(s < ue and str[s] == '[' and e > 0 and str[e - 1] == ']')) {
            if (s <= e) {
                if (std.mem.lastIndexOfScalar(u8, str[s..e], ':')) |c_rel| colon = s + c_rel;
            }
        }
        if (colon) |c| {
            p = c;
            if (ret.port == 0) {
                const ps = c + 1;
                if (e - ps > 5) return null;
                if (e - ps > 0) {
                    const port = readPort(str[ps..e]) orelse return null;
                    ret.has_port = true;
                    ret.port = port;
                }
            }
        } else {
            p = e;
        }
        if (p <= s) return null;
        ret.host = str[s..p];
        if (e == ue) return ret;
        s = e;
        break :host;
    }

    // just_path
    e = ue;
    if (std.mem.indexOfScalar(u8, str[s..e], '#')) |h_rel| {
        const after = s + h_rel + 1;
        ret.fragment = str[after..e];
        e = after - 1;
    }
    if (std.mem.indexOfScalar(u8, str[s..e], '?')) |q_rel| {
        const after = s + q_rel + 1;
        ret.query = str[after..e];
        e = after - 1;
    }
    if (s < e or s == ue) ret.path = str[s..e];
    return ret;
}

// php_replace_controlchars: iscntrl bytes become '_'
pub fn replaceControlChars(bytes: []u8) void {
    for (bytes) |*c| {
        if (c.* < 0x20 or c.* == 0x7f) c.* = '_';
    }
}
