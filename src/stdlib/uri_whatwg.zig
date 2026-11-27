// a port of lexbor 2.7.0's url module (lexbor/url/url.c as php 8.6.0 ships
// it, its patches applied), with its punycode (lexbor/punycode) and the idna
// processing of lexbor/unicode/idna.c. lexbor's own unicode tables are not
// carried: the mapping and nfc step of its idna comes from icu's "uts46"
// normalizer, which is the same idna mapping table composed with nfc
// (disallowed code points come out as U+FFFD there, ignored ones vanish)
//
// lexbor works on pointers into its input and its own buffers, and php reads
// a validation error's context as a c string from that pointer. positions here
// are indices into the buffer being parsed, and a log entry copies the bytes
// from its position to the first nul of that buffer, which is what php reads
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const SchemeType = enum(u8) { undef, unknown, http, https, ws, wss, ftp, file };
pub const HostType = enum(u8) { undef, domain, @"opaque", ipv4, ipv6, empty };

var empty_storage: [0]u8 = .{};

pub const Host = struct {
    type: HostType = .undef,
    ipv4: u32 = 0,
    ipv6: [8]u16 = @splat(0),
    // the domain or the opaque host
    str: []u8 = &empty_storage,
};

pub const Url = struct {
    scheme_name: []u8 = &empty_storage,
    scheme_type: SchemeType = .undef,
    host: Host = .{},
    username: []u8 = &empty_storage,
    password: []u8 = &empty_storage,
    port: u16 = 0,
    has_port: bool = false,
    // lxb_url_path_t: the serialized path, its segment count, the opaque flag
    path_str: []u8 = &empty_storage,
    path_length: usize = 0,
    path_opaque: bool = false,
    // lexbor's path.str.data == NULL, which some of its path code tests
    path_null: bool = true,
    // null is lexbor's data == NULL
    query: ?[]u8 = null,
    fragment: ?[]u8 = null,

    pub fn deinit(self: *Url, a: Allocator) void {
        a.free(self.scheme_name);
        a.free(self.host.str);
        a.free(self.username);
        a.free(self.password);
        a.free(self.path_str);
        if (self.query) |q| a.free(q);
        if (self.fragment) |f| a.free(f);
        self.* = .{};
    }

    // lxb_url_clone
    pub fn clone(self: *const Url, a: Allocator) !Url {
        var out: Url = .{};
        errdefer out.deinit(a);
        out.scheme_type = self.scheme_type;
        out.scheme_name = try a.dupe(u8, self.scheme_name);
        out.username = try a.dupe(u8, self.username);
        out.password = try a.dupe(u8, self.password);
        try hostCopy(a, &self.host, &out.host);
        out.port = self.port;
        out.has_port = self.has_port;
        try pathCopy(a, self, &out);
        out.query = try dupeOpt(a, self.query);
        out.fragment = try dupeOpt(a, self.fragment);
        return out;
    }
};

// a url as lexbor_mraw_calloc makes it, which php's builder starts from
pub fn empty(a: Allocator) Url {
    _ = a;
    return .{};
}

pub const ErrorType = enum(u8) {
    domain_to_ascii,
    domain_to_unicode,
    domain_invalid_code_point,
    host_invalid_code_point,
    ipv4_empty_part,
    ipv4_too_many_parts,
    ipv4_non_numeric_part,
    ipv4_non_decimal_part,
    ipv4_out_of_range_part,
    ipv6_unclosed,
    ipv6_invalid_compression,
    ipv6_too_many_pieces,
    ipv6_multiple_compression,
    ipv6_invalid_code_point,
    ipv6_too_few_pieces,
    ipv4_in_ipv6_too_many_pieces,
    ipv4_in_ipv6_invalid_code_point,
    ipv4_in_ipv6_out_of_range_part,
    ipv4_in_ipv6_too_few_parts,
    invalid_url_unit,
    special_scheme_missing_following_solidus,
    missing_scheme_non_relative_url,
    invalid_reverse_solidus,
    invalid_credentials,
    host_missing,
    port_out_of_range,
    port_invalid,
    file_invalid_windows_drive_letter,
    file_invalid_windows_drive_letter_host,
};

pub const LogEntry = struct {
    type: ErrorType,
    context: []u8,
};

pub const State = enum {
    undef,
    scheme_start,
    scheme,
    no_scheme,
    special_relative_or_authority,
    path_or_authority,
    relative,
    relative_slash,
    special_authority_slashes,
    special_authority_ignore_slashes,
    authority,
    host,
    hostname,
    port,
    file,
    file_slash,
    file_host,
    path_start,
    path,
    opaque_path,
    query,
    fragment,
};

// lexbor frees an ipv4 host's domain string right after parsing it, while
// the log still points into it; the next allocation of the parse (the path)
// may take the freed block from mraw's cache and overwrite what php later
// reads. this keeps what's needed to reproduce that
const Dangling = struct {
    block: []u8,
    refs: std.ArrayList(Ref) = .empty,
    decided: bool = false,
    reused: bool = false,

    const Ref = struct { index: usize, offset: usize };
};

pub const Parser = struct {
    a: Allocator,
    log: std.ArrayList(LogEntry) = .empty,
    dangling: ?Dangling = null,

    pub fn init(a: Allocator) Parser {
        return .{ .a = a };
    }

    pub fn clean(self: *Parser) void {
        for (self.log.items) |e| self.a.free(e.context);
        self.log.clearRetainingCapacity();
        self.dropDangling();
    }

    pub fn deinit(self: *Parser) void {
        self.clean();
        self.log.deinit(self.a);
    }

    fn dropDangling(self: *Parser) void {
        if (self.dangling) |*d| {
            self.a.free(d.block);
            d.refs.deinit(self.a);
            self.dangling = null;
        }
    }

    // lxb_url_log_append: the context is the c string at pos
    fn logAt(self: *Parser, buf: []const u8, pos: usize, t: ErrorType) !void {
        const rest = if (pos < buf.len) buf[pos..] else buf[buf.len..];
        const ctx = try self.a.dupe(u8, std.mem.sliceTo(rest, 0));
        errdefer self.a.free(ctx);
        try self.log.append(self.a, .{ .type = t, .context = ctx });
    }
};

pub const Map = struct {
    pub const c0: u8 = 0x01;
    pub const fragment: u8 = 0x02;
    pub const query: u8 = 0x04;
    pub const special_query: u8 = 0x08;
    pub const path: u8 = 0x10;
    pub const userinfo: u8 = 0x20;
    pub const component: u8 = 0x40;
    pub const x_www_form: u8 = 0x80;
};

const scheme_res = [_]struct { name: []const u8, port: u16, type: SchemeType }{
    .{ .name = "#undef", .port = 0, .type = .undef },
    .{ .name = "#unknown", .port = 0, .type = .unknown },
    .{ .name = "http", .port = 80, .type = .http },
    .{ .name = "https", .port = 443, .type = .https },
    .{ .name = "ws", .port = 80, .type = .ws },
    .{ .name = "wss", .port = 443, .type = .wss },
    .{ .name = "ftp", .port = 21, .type = .ftp },
    .{ .name = "file", .port = 0, .type = .file },
};

const decode_error: u32 = 0x1FFFFF;
const max_codepoint: u32 = 0x10FFFF;

// ---- character tables ---------------------------------------------------

fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}

fn isAlnum(c: u8) bool {
    return isAlpha(c) or (c >= '0' and c <= '9');
}

fn hexVal(c: u8) u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => 0xff,
    };
}

fn numVal(c: u8) u8 {
    return if (c >= '0' and c <= '9') c - '0' else 0xff;
}

fn octVal(c: u8) u8 {
    return if (c >= '0' and c <= '7') c - '0' else 0xff;
}

const hex_upper = "0123456789ABCDEF";

fn isWindowsLetter(c: u8) bool {
    return isAlpha(c);
}

// ---- utf-8 (lexbor's "valid" decoders, which don't check continuations) --

fn decodeValid(data: []const u8, pos: *usize, end: usize) u32 {
    const p = pos.*;
    const c = data[p];
    if (c < 0x80) {
        pos.* += 1;
        return c;
    } else if (c & 0xe0 == 0xc0) {
        if (end - p < 2) {
            pos.* = end;
            return decode_error;
        }
        pos.* += 2;
        return (@as(u32, c ^ (0xC0 & c)) << 6) | (data[p + 1] ^ (0x80 & data[p + 1]));
    } else if (c & 0xf0 == 0xe0) {
        if (end - p < 3) {
            pos.* = end;
            return decode_error;
        }
        pos.* += 3;
        return (@as(u32, c ^ (0xE0 & c)) << 12) | (@as(u32, data[p + 1] ^ (0x80 & data[p + 1])) << 6) | (data[p + 2] ^ (0x80 & data[p + 2]));
    } else if (c & 0xf8 == 0xf0) {
        if (end - p < 4) {
            pos.* = end;
            return decode_error;
        }
        pos.* += 4;
        return (@as(u32, c ^ (0xF0 & c)) << 18) | (@as(u32, data[p + 1] ^ (0x80 & data[p + 1])) << 12) |
            (@as(u32, data[p + 2] ^ (0x80 & data[p + 2])) << 6) | (data[p + 3] ^ (0x80 & data[p + 3]));
    }
    pos.* += 1;
    return decode_error;
}

fn decodeValidReverse(data: []const u8, end_pos: *usize, begin: usize) u32 {
    const e = end_pos.*;
    var p = e;
    while (p > begin) {
        p -= 1;
        const c = data[p];
        if (c < 0x80) {
            end_pos.* = p;
            return c;
        } else if (c & 0xe0 == 0xc0) {
            end_pos.* = p;
            if (e - p < 2) return decode_error;
            return (@as(u32, c ^ (0xC0 & c)) << 6) | (data[p + 1] ^ (0x80 & data[p + 1]));
        } else if (c & 0xf0 == 0xe0) {
            end_pos.* = p;
            if (e - p < 3) return decode_error;
            return (@as(u32, c ^ (0xE0 & c)) << 12) | (@as(u32, data[p + 1] ^ (0x80 & data[p + 1])) << 6) | (data[p + 2] ^ (0x80 & data[p + 2]));
        } else if (c & 0xf8 == 0xf0) {
            end_pos.* = p;
            if (e - p < 4) return decode_error;
            return (@as(u32, c ^ (0xF0 & c)) << 18) | (@as(u32, data[p + 1] ^ (0x80 & data[p + 1])) << 12) |
                (@as(u32, data[p + 2] ^ (0x80 & data[p + 2])) << 6) | (data[p + 3] ^ (0x80 & data[p + 3]));
        } else if (e - p >= 4) {
            break;
        }
    }
    end_pos.* = p;
    return decode_error;
}

fn utf8Length(cp: u32) u8 {
    if (cp < 0x80) return 1;
    if (cp < 0x800) return 2;
    if (cp < 0x10000) return 3;
    if (cp < 0x110000) return 4;
    return 0;
}

// lxb_encoding_encode_utf_8_single, which encodes surrogates too
fn appendUtf8(a: Allocator, out: *std.ArrayList(u8), cp: u32) !void {
    if (cp < 0x80) {
        try out.append(a, @intCast(cp));
    } else if (cp < 0x800) {
        try out.appendSlice(a, &.{ @intCast(0xC0 | (cp >> 6)), @intCast(0x80 | (cp & 0x3F)) });
    } else if (cp < 0x10000) {
        try out.appendSlice(a, &.{ @intCast(0xE0 | (cp >> 12)), @intCast(0x80 | ((cp >> 6) & 0x3F)), @intCast(0x80 | (cp & 0x3F)) });
    } else if (cp < 0x110000) {
        try out.appendSlice(a, &.{ @intCast(0xF0 | (cp >> 18)), @intCast(0x80 | ((cp >> 12) & 0x3F)), @intCast(0x80 | ((cp >> 6) & 0x3F)), @intCast(0x80 | (cp & 0x3F)) });
    }
}

fn isNoncharacter(cp: u32) bool {
    if (cp >= 0xFDD0 and cp <= 0xFDEF) return true;
    return cp & 0xFFFE == 0xFFFE and cp <= 0x10FFFF;
}

fn isUrlCodepoint(cp: u32) bool {
    if (cp >= 0x00A0 and cp <= 0x1FFFFF) {
        if (cp >= 0xD800 and cp <= 0xDFFF) return false;
        return !(cp > 0x10FFFF or isNoncharacter(cp));
    }
    return codepoint_alphanumeric[@as(u8, @truncate(cp))] != 0xff;
}

// ---- small string helpers --------------------------------------------------

fn appendBytes(a: Allocator, s: *[]u8, bytes: []const u8) !void {
    const old = s.len;
    s.* = try a.realloc(s.*, old + bytes.len);
    @memcpy(s.*[old..], bytes);
}

fn appendOpt(a: Allocator, s: *?[]u8, bytes: []const u8) !void {
    if (s.* == null) s.* = try a.alloc(u8, 0);
    try appendBytes(a, &s.*.?, bytes);
}

fn setBytes(a: Allocator, s: *[]u8, bytes: []const u8) !void {
    const n = try a.dupe(u8, bytes);
    a.free(s.*);
    s.* = n;
}

fn dupeOpt(a: Allocator, s: ?[]const u8) !?[]u8 {
    return if (s) |v| try a.dupe(u8, v) else null;
}

fn clearOpt(a: Allocator, s: *?[]u8) void {
    if (s.*) |v| a.free(v);
    s.* = null;
}

fn clearStr(a: Allocator, s: *[]u8) void {
    a.free(s.*);
    s.* = &empty_storage;
}

fn alignUp(n: usize) usize {
    return (n + 7) & ~@as(usize, 7);
}

// lxb_url_percent_encode_after_utf_8, appending to what out already holds
fn percentEncodeInto(a: Allocator, out: *std.ArrayList(u8), data: []const u8, map: *const [256]u8, mask: u8, space_as_plus: bool) !void {
    for (data) |c| {
        if (space_as_plus and c == ' ') {
            try out.append(a, '+');
        } else if (map[c] & mask != 0) {
            try out.appendSlice(a, &.{ '%', hex_upper[c >> 4], hex_upper[c & 0xf] });
        } else {
            try out.append(a, c);
        }
    }
}

fn percentEncodeStr(a: Allocator, s: *[]u8, data: []const u8, mask: u8) !void {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(a);
    try percentEncodeInto(a, &out, data, &url_map, mask, false);
    try appendBytes(a, s, out.items);
}

fn percentEncodeOpt(a: Allocator, s: *?[]u8, data: []const u8, mask: u8) !void {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(a);
    try percentEncodeInto(a, &out, data, &url_map, mask, false);
    try appendOpt(a, s, out.items);
}

pub fn percentEncodingMap() [256]u8 {
    return url_map;
}

pub fn percentEncodeUtf8(a: Allocator, data: []const u8, map: *const [256]u8, mask: u8, space_as_plus: bool) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    try percentEncodeInto(a, &out, data, map, mask, space_as_plus);
    return out.toOwnedSlice(a);
}

// ---- url pieces --------------------------------------------------------------

pub fn isSpecial(url: *const Url) bool {
    return url.scheme_type != .unknown;
}

fn schemeIsSpecial(t: SchemeType) bool {
    return t != .unknown;
}

fn schemeEqual(first: *const Url, second: *const Url) bool {
    if (first.scheme_type != second.scheme_type) return false;
    if (first.scheme_type == .unknown) return std.mem.eql(u8, first.scheme_name, second.scheme_name);
    return true;
}

fn schemeFind(data: []const u8) usize {
    var i: usize = @backingInt(SchemeType.unknown) + 1;
    while (i < scheme_res.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(scheme_res[i].name, data)) return i;
    }
    return @backingInt(SchemeType.unknown);
}

fn includesCredentials(url: *const Url) bool {
    return url.username.len != 0 or url.password.len != 0;
}

fn hostIsEmpty(host: *const Host) bool {
    return switch (host.type) {
        .empty => true,
        .domain, .@"opaque" => host.str.len == 0,
        else => false,
    };
}

fn cannotHaveUserPassPort(url: *const Url) bool {
    return hostIsEmpty(&url.host) or url.host.type == .undef or url.scheme_type == .file;
}

fn hostSetEmpty(a: Allocator, host: *Host) void {
    clearStr(a, &host.str);
    host.type = .empty;
}

fn hostCopy(a: Allocator, src: *const Host, dst: *Host) !void {
    const s = switch (src.type) {
        .domain, .@"opaque" => try a.dupe(u8, src.str),
        else => &empty_storage,
    };
    a.free(dst.str);
    dst.* = .{ .type = src.type, .ipv4 = src.ipv4, .ipv6 = src.ipv6, .str = s };
}

fn hostEq(host: *const Host, data: []const u8) bool {
    return (host.type == .domain or host.type == .@"opaque") and std.mem.eql(u8, host.str, data);
}

pub fn pathSetNull(url: *Url, a: Allocator) void {
    if (url.path_null) return;
    clearStr(a, &url.path_str);
    url.path_null = true;
    url.path_length = 0;
    url.path_opaque = false;
}

pub fn querySetNull(url: *Url, a: Allocator) void {
    clearOpt(a, &url.query);
}

pub fn fragmentSetNull(url: *Url, a: Allocator) void {
    clearOpt(a, &url.fragment);
}

fn pathCopy(a: Allocator, src: *const Url, dst: *Url) !void {
    if (!dst.path_null) pathSetNull(dst, a);
    dst.path_opaque = src.path_opaque;
    if (src.path_null) return;
    dst.path_length = src.path_length;
    dst.path_str = try a.dupe(u8, src.path_str);
    dst.path_null = false;
}

fn pathShorten(a: Allocator, url: *Url) !void {
    const str = url.path_str;
    if (url.scheme_type == .file and url.path_length == 1) {
        if (str.len >= 3 and isWindowsLetter(str[1]) and str[2] == ':') return;
    }
    if (url.path_length == 0 or url.path_null) return;
    url.path_length -= 1;
    var p = str.len;
    while (p > 0) {
        p -= 1;
        if (str[p] == '/') break;
    }
    url.path_str = try a.realloc(url.path_str, p);
}

fn startsWindowsDriveLetter(d: []const u8) bool {
    if (d.len < 2) return false;
    if (!isWindowsLetter(d[0]) or (d[1] != ':' and d[1] != '|')) return false;
    if (d.len > 2 and !(d[2] == '/' or d[2] == '\\' or d[2] == '?' or d[2] == '#')) return false;
    return true;
}

fn isWindowsDriveLetter(d: []const u8) bool {
    return d.len >= 2 and isWindowsLetter(d[0]) and (d[1] == ':' or d[1] == '|');
}

fn isNormalizedWindowsDriveLetter(d: []const u8) bool {
    return d.len >= 2 and isWindowsLetter(d[0]) and d[1] == ':';
}

// lxb_url_path_part_by_index
fn pathPartByIndex(url: *const Url, index_in: usize) ?[]const u8 {
    var index = index_in;
    const data = url.path_str;
    var begin: usize = 0;
    for (data, 0..) |c, i| {
        if (c == '/') {
            if (index == 0) return data[begin..i];
            index -= 1;
            begin = i + 1;
        }
    }
    return null;
}

// ---- the parser -----------------------------------------------------------------

const Ctx = struct {
    p: *Parser,
    a: Allocator,
    url: *Url,
    base: ?*const Url,
    src: []const u8,
    override: State,

    fn log(self: *Ctx, pos: usize, t: ErrorType) !void {
        try self.p.logAt(self.src, pos, t);
    }

    fn special(self: *Ctx) bool {
        return isSpecial(self.url);
    }

    // the first allocation of a fresh path string decides whether it took
    // the block a freed ipv4 domain left. mraw's cache hands out an exact
    // size first, and by the time php parses a url it holds blocks of the
    // small sizes, so only a request of the domain block's own size takes it
    fn notePathAlloc(self: *Ctx, size: usize) void {
        if (self.p.dangling) |*d| {
            if (d.decided) return;
            d.decided = true;
            d.reused = alignUp(size) == d.block.len;
        }
    }

    fn pathAppend(self: *Ctx, data: []const u8) !void {
        if (self.url.path_null) {
            self.notePathAlloc(data.len + 2);
            self.url.path_null = false;
        }
        const old = self.url.path_str.len;
        self.url.path_str = try self.a.realloc(self.url.path_str, old + data.len + 1);
        self.url.path_str[old] = '/';
        @memcpy(self.url.path_str[old + 1 ..], data);
    }

    fn pathAppendWoSlash(self: *Ctx, data: []const u8) !void {
        if (self.url.path_null) {
            self.notePathAlloc(data.len + 1);
            self.url.path_null = false;
        }
        try appendBytes(self.a, &self.url.path_str, data);
    }
};

// lxb_url_leading_trailing
fn leadingTrailing(p: *Parser, data: []const u8, start: *usize, end: *usize) !void {
    var pos: usize = 0;
    var e: usize = data.len;
    while (pos < e) {
        const c = data[pos];
        if (c > 0x1F and c < 0x80 and c != 0x20) break;
        if (c >= 0x80) {
            const tmp = pos;
            const cp = decodeValid(data, &pos, e);
            if (cp > 0x1F and cp != decode_error) {
                pos = tmp;
                break;
            }
            continue;
        }
        pos += 1;
    }
    if (pos != 0) try p.logAt(data, 0, .invalid_url_unit);
    while (e > pos) {
        const tmp = e;
        const cp = decodeValidReverse(data, &e, pos);
        if (cp > 0x1F and cp != 0x20 and cp != decode_error) {
            e = tmp;
            break;
        }
    }
    if (e != data.len) try p.logAt(data, e, .invalid_url_unit);
    start.* = pos;
    end.* = e;
}

// lexbor_parse_basic_h. fresh is lxb_url_parse's url == NULL: a new url and
// the leading and trailing c0 controls and spaces trimmed
fn parseBasicH(p: *Parser, url: *Url, base: ?*const Url, input: []const u8, override: State, fresh: bool) !bool {
    const a = p.a;
    var start: usize = 0;
    var stop: usize = input.len;
    if (fresh) try leadingTrailing(p, input, &start, &stop);

    // lxb_url_remove_tab_newline: the first one is logged where it stands in
    // the input; the rest of the parse reads a copy without them
    var src: []const u8 = input;
    var owned: ?[]u8 = null;
    defer if (owned) |o| a.free(o);
    var first_tab: ?usize = null;
    for (input[start..stop], start..) |c, i| {
        if (c == '\n' or c == '\r' or c == '\t') {
            first_tab = i;
            break;
        }
    }
    if (first_tab) |ft| {
        try p.logAt(input, ft, .invalid_url_unit);
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(a);
        try buf.appendSlice(a, input[start..ft]);
        for (input[ft + 1 .. stop]) |c| {
            if (c == '\n' or c == '\r' or c == '\t') continue;
            try buf.append(a, c);
        }
        owned = try buf.toOwnedSlice(a);
        src = owned.?;
        start = 0;
        stop = src.len;
    }

    var ctx: Ctx = .{ .p = p, .a = a, .url = url, .base = base, .src = src, .override = override };
    defer settleDangling(p, url);
    return run(&ctx, start, stop);
}

// what php reads through log entries that point into a freed ipv4 domain
fn settleDangling(p: *Parser, url: *const Url) void {
    const d = &(p.dangling orelse return);
    if (d.reused) {
        const n = @min(url.path_str.len, d.block.len);
        @memcpy(d.block[0..n], url.path_str[0..n]);
        if (n < d.block.len) d.block[n] = 0;
    }
    for (d.refs.items) |r| {
        if (r.index >= p.log.items.len) continue;
        const rest = if (r.offset < d.block.len) d.block[r.offset..] else d.block[d.block.len..];
        const ctx = p.a.dupe(u8, std.mem.sliceTo(rest, 0)) catch continue;
        p.a.free(p.log.items[r.index].context);
        p.log.items[r.index].context = ctx;
    }
    p.dropDangling();
}

fn run(ctx: *Ctx, data: usize, end: usize) !bool {
    const a = ctx.a;
    const url = ctx.url;
    const base = ctx.base;
    const src = ctx.src;
    const override = ctx.override;
    var p: usize = data;
    var state: State = if (override != .undef) override else .scheme_start;
    var inside_bracket = false;
    var begin: usize = 0;

    while (true) {
        switch (state) {
            .scheme_start, .scheme => {
                if (state == .scheme_start) {
                    if (p >= end or !isAlpha(src[p])) {
                        if (override == .undef) {
                            state = .no_scheme;
                            continue;
                        }
                        return false;
                    }
                }
                while (true) {
                    p += 1;
                    if (!(p < end and (isAlnum(src[p]) or src[p] == '+' or src[p] == '-' or src[p] == '.'))) break;
                }
                if (p >= end or src[p] != ':') {
                    if (override == .undef) {
                        p = data;
                        state = .no_scheme;
                        continue;
                    } else if (p < end or override != .scheme_start) {
                        return false;
                    }
                }
                const schm = scheme_res[schemeFind(src[data..p])];
                if (override != .undef) {
                    if (isSpecial(url) != schemeIsSpecial(schm.type)) return true;
                    if (url.has_port or includesCredentials(url)) {
                        if (schm.type == .file) return true;
                    }
                    if (url.scheme_type == .file and url.host.type == .empty) return true;
                }
                url.scheme_type = schm.type;
                const lower = try a.alloc(u8, p - data);
                for (src[data..p], 0..) |c, i| lower[i] = std.ascii.toLower(c);
                a.free(url.scheme_name);
                url.scheme_name = lower;
                p += 1;
                if (override != .undef) {
                    if (url.has_port and url.port == schm.port) {
                        url.port = 0;
                        url.has_port = false;
                    }
                    return true;
                }
                if (schm.type == .file) {
                    if (end - p < 2 or src[p] != '/' or src[p + 1] != '/') {
                        try ctx.log(p, .special_scheme_missing_following_solidus);
                    }
                    state = .file;
                    continue;
                }
                if (schemeIsSpecial(schm.type)) {
                    state = if (base != null and schemeEqual(url, base.?)) .special_relative_or_authority else .special_authority_slashes;
                    continue;
                }
                if (p < end and src[p] == '/') {
                    p += 1;
                    state = .path_or_authority;
                    continue;
                }
                pathSetNull(url, a);
                state = .opaque_path;
            },
            .no_scheme => {
                const b = base orelse return failNonRelative(ctx, p);
                if (b.path_opaque) {
                    if (p >= end or src[p] != '#') return failNonRelative(ctx, p);
                    p += 1;
                    try schemeCopy(a, b, url);
                    try pathCopy(a, b, url);
                    try strCopyOpt(a, b.query, &url.query);
                    fragmentSetNull(url, a);
                    state = .fragment;
                    continue;
                }
                state = if (b.scheme_type != .file) .relative else .file;
            },
            .special_relative_or_authority => {
                if (end > p and end - p > 1 and src[p] == '/' and src[p + 1] == '/') {
                    p += 2;
                    state = .special_authority_ignore_slashes;
                    continue;
                }
                try ctx.log(p, .special_scheme_missing_following_solidus);
                state = .relative;
            },
            .path_or_authority => {
                if (p < end and src[p] == '/') {
                    p += 1;
                    state = .authority;
                } else {
                    state = .path;
                }
            },
            .relative => {
                const b = base.?;
                try schemeCopy(a, b, url);
                if (end > p) {
                    if (src[p] == '/') {
                        p += 1;
                        state = .relative_slash;
                        continue;
                    }
                    if (isSpecial(url) and src[p] == '\\') {
                        p += 1;
                        try ctx.log(p, .invalid_reverse_solidus);
                        state = .relative_slash;
                        continue;
                    }
                }
                try setBytes(a, &url.username, b.username);
                try setBytes(a, &url.password, b.password);
                try hostCopy(a, &b.host, &url.host);
                if (b.has_port) {
                    url.port = b.port;
                    url.has_port = true;
                }
                try pathCopy(a, b, url);
                try strCopyOpt(a, b.query, &url.query);
                if (end <= p) return true;
                if (src[p] == '?') {
                    p += 1;
                    clearOpt(a, &url.query);
                    state = .query;
                    continue;
                }
                if (src[p] == '#') {
                    p += 1;
                    clearOpt(a, &url.fragment);
                    state = .fragment;
                    continue;
                }
                clearOpt(a, &url.query);
                try pathShorten(a, url);
                state = .path;
            },
            .relative_slash => {
                const b = base.?;
                const c: u8 = if (end > p) src[p] else 0;
                if (isSpecial(url) and (c == '/' or c == '\\')) {
                    if (c == '\\') try ctx.log(p, .invalid_reverse_solidus);
                    p += 1;
                    state = .special_authority_ignore_slashes;
                    continue;
                }
                if (c == '/') {
                    p += 1;
                    state = .authority;
                    continue;
                }
                try setBytes(a, &url.username, b.username);
                try setBytes(a, &url.password, b.password);
                try hostCopy(a, &b.host, &url.host);
                if (b.has_port) {
                    url.port = b.port;
                    url.has_port = true;
                }
                state = .path;
            },
            .special_authority_slashes => {
                state = .special_authority_ignore_slashes;
                if (end > p and end - p > 1 and src[p] == '/' and src[p + 1] == '/') {
                    p += 2;
                } else {
                    try ctx.log(p, .special_scheme_missing_following_solidus);
                }
            },
            .special_authority_ignore_slashes => {
                if (p >= end or (src[p] != '/' and src[p] != '\\')) {
                    state = .authority;
                    continue;
                }
                try ctx.log(p, .special_scheme_missing_following_solidus);
                p += 1;
            },
            .authority => {
                begin = p;
                var pswd: ?usize = null;
                var at_sign = false;
                authority: while (p < end) {
                    const c = src[p];
                    switch (c) {
                        '@' => {
                            try ctx.log(p, .invalid_credentials);
                            if (p == begin) {
                                at_sign = true;
                            } else {
                                const tmp = if (pswd) |pw| pw - 1 else p;
                                if (tmp > begin) try percentEncodeStr(a, &url.username, src[begin..tmp], Map.userinfo);
                                if (pswd) |pw| {
                                    if (p > pw) {
                                        try percentEncodeStr(a, &url.password, src[pw..p], Map.userinfo);
                                        pswd = p;
                                    }
                                }
                                at_sign = true;
                                begin = p;
                            }
                        },
                        ':' => {
                            if (pswd == null) pswd = p + 1;
                        },
                        '/', '\\', '?', '#' => {
                            if (c == '\\' and !isSpecial(url)) {
                                p += 1;
                                continue :authority;
                            }
                            break :authority;
                        },
                        else => {},
                    }
                    p += 1;
                }
                if (at_sign) {
                    if (begin == p or begin + 1 == p) {
                        try ctx.log(p, .host_missing);
                        return false;
                    }
                    begin += 1;
                }
                p = begin;
                state = .host;
            },
            .host, .hostname => {
                begin = p;
                if (override != .undef and url.scheme_type == .file) {
                    state = .file_host;
                    continue;
                }
                var opt: u8 = if (!isSpecial(url)) host_opt_not_special else 0;
                host: while (p < end) : (p += 1) {
                    const c = src[p];
                    switch (c) {
                        '/', '?', '#' => break :host,
                        '\\' => {
                            if (!isSpecial(url)) continue :host;
                            break :host;
                        },
                        ':' => {
                            if (inside_bracket) continue :host;
                            if (p == begin) return failHost(ctx, p);
                            if (override == .hostname) return false;
                            if (!try hostParse(ctx, begin, p, &url.host, opt)) return false;
                            p += 1;
                            state = .port;
                            break :host;
                        },
                        '[' => inside_bracket = true,
                        ']' => inside_bracket = false,
                        '%' => opt |= host_opt_decode,
                        'X', 'x' => {
                            if (p + 4 <= end and (src[p + 1] == 'n' or src[p + 1] == 'N') and src[p + 2] == '-' and src[p + 3] == '-') {
                                opt |= host_opt_idna;
                                p += 3;
                            }
                        },
                        else => {
                            if (c >= 0x80) opt |= host_opt_idna;
                        },
                    }
                }
                if (state == .port) continue;
                if (begin == p and isSpecial(url)) return failHost(ctx, p);
                if (override != .undef and begin == p and (includesCredentials(url) or url.has_port)) return true;
                if (!try hostParse(ctx, begin, p, &url.host, opt)) return false;
                if (override != .undef) return true;
                state = .path_start;
            },
            .port => {
                begin = p;
                while (true) {
                    const c: u8 = if (p < end) src[p] else 0;
                    if (c >= '0' and c <= '9') {
                        p += 1;
                        continue;
                    }
                    if (p >= end or c == '/' or c == '?' or c == '#' or (isSpecial(url) and c == '\\') or override != .undef) {
                        if (begin == p) {
                            if (override != .undef) return false;
                            state = .path_start;
                            break;
                        }
                        var port: u32 = 0;
                        while (begin < p) {
                            port = numVal(src[begin]) + port * 10;
                            begin += 1;
                            if (port > 65535) {
                                try ctx.log(p, .port_out_of_range);
                                return false;
                            }
                        }
                        if (!isSpecial(url) or scheme_res[@backingInt(url.scheme_type)].port != port) {
                            url.port = @intCast(port);
                            url.has_port = true;
                        } else {
                            url.port = 0;
                            url.has_port = false;
                        }
                        if (override != .undef) return true;
                        state = .path_start;
                        break;
                    }
                    try ctx.log(p, .port_invalid);
                    return false;
                }
            },
            .file => {
                try setBytes(a, &url.scheme_name, "file");
                url.scheme_type = .file;
                hostSetEmpty(a, &url.host);
                const c: u8 = if (p < end) src[p] else 0;
                if (c == '/' or c == '\\') {
                    if (c == '\\') try ctx.log(p, .invalid_reverse_solidus);
                    p += 1;
                    state = .file_slash;
                    continue;
                }
                if (base) |b| if (b.scheme_type == .file) {
                    try hostCopy(a, &b.host, &url.host);
                    try pathCopy(a, b, url);
                    try strCopyOpt(a, b.query, &url.query);
                    if (c == '?') {
                        p += 1;
                        clearOpt(a, &url.query);
                        state = .query;
                        continue;
                    }
                    if (c == '#') {
                        p += 1;
                        clearOpt(a, &url.fragment);
                        state = .fragment;
                        continue;
                    }
                    if (p >= end) return true;
                    clearOpt(a, &url.query);
                    if (!startsWindowsDriveLetter(src[p..end])) {
                        try pathShorten(a, url);
                    } else {
                        try ctx.log(p, .file_invalid_windows_drive_letter);
                        pathSetNull(url, a);
                    }
                };
                state = .path;
            },
            .file_slash => {
                const c: u8 = if (p < end) src[p] else 0;
                if (c == '/' or c == '\\') {
                    if (c == '\\') try ctx.log(p, .invalid_reverse_solidus);
                    p += 1;
                    state = .file_host;
                    continue;
                }
                if (base) |b| if (b.scheme_type == .file) {
                    try hostCopy(a, &b.host, &url.host);
                    if (!startsWindowsDriveLetter(src[p..end]) and !b.path_opaque and b.path_length >= 1) {
                        const idx: usize = if (b.path_str.len > 0 and b.path_str[0] == '/') 1 else 0;
                        if (pathPartByIndex(b, idx)) |part| {
                            if (isNormalizedWindowsDriveLetter(part)) {
                                const len = (@intFromPtr(part.ptr) - @intFromPtr(b.path_str.ptr)) + part.len;
                                try ctx.pathAppendWoSlash(b.path_str[0..len]);
                                url.path_length += 1;
                            }
                        }
                    }
                };
                state = .path;
            },
            .file_host => {
                begin = p;
                var opt: u8 = if (!isSpecial(url)) host_opt_not_special else 0;
                while (p < end) {
                    switch (src[p]) {
                        '/', '\\', '?', '#' => break,
                        '%' => {
                            p += 1;
                            opt |= host_opt_decode;
                        },
                        'X', 'x' => {
                            if (p + 4 <= end and (src[p + 1] == 'n' or src[p + 1] == 'N') and src[p + 2] == '-' and src[p + 3] == '-') {
                                opt |= host_opt_idna;
                                p += 3;
                            }
                            p += 1;
                        },
                        else => |c| {
                            if (c >= 0x80) opt |= host_opt_idna;
                            p += 1;
                        },
                    }
                }
                if (override == .undef and p - begin == 2 and isWindowsDriveLetter(src[begin..p])) {
                    try ctx.log(begin, .file_invalid_windows_drive_letter_host);
                    p = begin;
                    state = .path;
                    continue;
                }
                if (p == begin) {
                    hostSetEmpty(a, &url.host);
                    if (override != .undef) return true;
                    state = .path_start;
                    continue;
                }
                if (!try hostParse(ctx, begin, p, &url.host, opt)) return false;
                if (hostEq(&url.host, "localhost")) hostSetEmpty(a, &url.host);
                if (override != .undef) return true;
                state = .path_start;
            },
            .path_start => {
                const c: u8 = if (p < end) src[p] else 0;
                if (isSpecial(url)) {
                    if (c == '\\') {
                        try ctx.log(p, .invalid_reverse_solidus);
                        p += 1;
                    } else if (c == '/') {
                        p += 1;
                    }
                    state = .path;
                    continue;
                }
                if (override == .undef) {
                    if (c == '?') {
                        p += 1;
                        state = .query;
                        continue;
                    }
                    if (c == '#') {
                        p += 1;
                        state = .fragment;
                        continue;
                    }
                }
                if (p < end) {
                    if (c == '/') p += 1;
                    state = .path;
                    continue;
                }
                if (override != .undef and url.host.type == .undef) {
                    try ctx.pathAppend("");
                    url.path_length += 1;
                }
                return true;
            },
            .path => {
                p = try pathFastPath(ctx, p, end, override == .undef);
                if (p >= end) return true;
                switch (src[p]) {
                    '?' => {
                        p += 1;
                        state = .query;
                    },
                    '#' => {
                        p += 1;
                        state = .fragment;
                    },
                    else => {},
                }
            },
            .opaque_path => {
                begin = p;
                url.path_opaque = true;
                while (true) {
                    if (p >= end) {
                        var tmp: std.ArrayList(u8) = .empty;
                        defer tmp.deinit(a);
                        try percentEncodeInto(a, &tmp, src[begin..p], &url_map, Map.c0, false);
                        try ctx.pathAppendWoSlash(tmp.items);
                        return true;
                    }
                    const c = src[p];
                    if (c == '#' or c == '?') {
                        var tmp: std.ArrayList(u8) = .empty;
                        defer tmp.deinit(a);
                        try percentEncodeInto(a, &tmp, src[begin..p], &url_map, Map.c0, false);
                        // only the space right before a query or fragment is encoded
                        if (p > begin and src[p - 1] == ' ') {
                            tmp.items.len -= 1;
                            try tmp.appendSlice(a, "%20");
                        }
                        try ctx.pathAppendWoSlash(tmp.items);
                        p += 1;
                        state = if (c == '#') .fragment else .query;
                        break;
                    }
                    const tmp = p;
                    const cp = decodeValid(src, &p, end);
                    if (badUnit(src, cp, p, end)) try ctx.log(tmp, .invalid_url_unit);
                }
            },
            .query => {
                begin = p;
                while (true) {
                    if (p >= end or (override == .undef and src[p] == '#')) {
                        const mask = if (isSpecial(url)) Map.special_query else Map.query;
                        try percentEncodeOpt(a, &url.query, src[begin..p], mask);
                        if (p < end) {
                            p += 1;
                            state = .fragment;
                            break;
                        }
                        return true;
                    }
                    const tmp = p;
                    const cp = decodeValid(src, &p, end);
                    if (badUnit(src, cp, p, end)) try ctx.log(tmp, .invalid_url_unit);
                }
            },
            .fragment => {
                begin = p;
                while (p < end) {
                    const tmp = p;
                    const cp = decodeValid(src, &p, end);
                    if (badUnit(src, cp, p, end)) try ctx.log(tmp, .invalid_url_unit);
                }
                try percentEncodeOpt(a, &url.fragment, src[begin..p], Map.fragment);
                return true;
            },
            .undef => return false,
        }
    }
}

// the code point test the query, fragment and opaque path states log by
fn badUnit(src: []const u8, cp: u32, p: usize, end: usize) bool {
    if (!isUrlCodepoint(cp) and cp != '%') return true;
    return cp == '%' and (end - p < 2 or hexVal(src[p]) == 0xff or hexVal(src[p + 1]) == 0xff);
}

fn failNonRelative(ctx: *Ctx, p: usize) !bool {
    try ctx.log(p, .missing_scheme_non_relative_url);
    return false;
}

fn failHost(ctx: *Ctx, p: usize) !bool {
    try ctx.log(p, .host_missing);
    return false;
}

fn schemeCopy(a: Allocator, src: *const Url, dst: *Url) !void {
    dst.scheme_type = src.scheme_type;
    try setBytes(a, &dst.scheme_name, src.scheme_name);
}

fn strCopyOpt(a: Allocator, src: ?[]const u8, dst: *?[]u8) !void {
    const n = try dupeOpt(a, src);
    clearOpt(a, dst);
    dst.* = n;
}

// ---- path ------------------------------------------------------------------------

fn pathFastPath(ctx: *Ctx, start: usize, end: usize, bqs: bool) !usize {
    const url = ctx.url;
    const src = ctx.src;
    var p = start;
    var begin = start;
    var last = start;
    var count = url.path_length;
    var slow = false;

    while (p < end) : (p += 1) {
        const c = src[p];
        if (path_map[c] == 0) continue;
        if (c == '/') {
            count += 1;
            last = p + 1;
        } else if (c == '%') {
            if (end - p < 3 or hexVal(src[p + 1]) == 0xff or hexVal(src[p + 2]) == 0xff) {
                // reprocess the segment without skipping delimiters
                slow = true;
                break;
            } else if (src[p + 1] == '2' and (src[p + 2] == 'e' or src[p + 2] == 'E') and
                (p == begin or src[p - 1] == '/' or (src[p - 1] == '\\' and ctx.special())))
            {
                url.path_length = count;
                try pathTryDot(ctx, &begin, &last, &p, end, bqs);
                count = url.path_length;
            } else {
                p += 2;
            }
        } else if ((c == '?' or c == '#') and bqs) {
            break;
        } else if (c == '\\' and ctx.special()) {
            count += 1;
            try ctx.log(p, .invalid_reverse_solidus);
            try ctx.pathAppend(src[begin..p]);
            begin = p + 1;
            last = p + 1;
        } else if (c == '.') {
            if (p == begin or src[p - 1] == '/' or (src[p - 1] == '\\' and ctx.special())) {
                url.path_length = count;
                try pathTryDot(ctx, &begin, &last, &p, end, bqs);
                count = url.path_length;
            }
        } else {
            slow = true;
            break;
        }
    }

    if (!slow) {
        try ctx.pathAppend(src[begin..p]);
        url.path_length = count + 1;
        return p;
    }

    url.path_length = count;
    if (last > begin) try ctx.pathAppend(src[begin .. last - 1]);
    return pathSlowPath(ctx, last, end, bqs);
}

fn pathSlowPath(ctx: *Ctx, start: usize, end: usize, bqs: bool) !usize {
    const a = ctx.a;
    const url = ctx.url;
    const src = ctx.src;
    var sbuf: std.ArrayList(u8) = .empty;
    defer sbuf.deinit(a);

    if (url.path_str.len != 0) {
        try sbuf.appendSlice(a, url.path_str);
        url.path_str = try a.realloc(url.path_str, 0);
    }
    try sbuf.append(a, '/');
    var last = sbuf.items.len;
    var count = url.path_length;
    var p = start;

    while (p < end) {
        const c = src[p];
        if (c >= 0x80) {
            const tmp = p;
            const cp = decodeValid(src, &p, end);
            if (!isUrlCodepoint(cp)) try ctx.log(tmp, .invalid_url_unit);
            for (src[tmp..p]) |b| try sbuf.appendSlice(a, &.{ '%', hex_upper[b >> 4], hex_upper[b & 0xf] });
            continue;
        }
        if (c == '/') {
            try sbuf.append(a, '/');
            fixWindowsDrive(url, sbuf.items, last, count);
            count += 1;
            last = sbuf.items.len;
        } else if (c == '\\' and ctx.special()) {
            try ctx.log(p, .invalid_reverse_solidus);
            try sbuf.append(a, '/');
            fixWindowsDrive(url, sbuf.items, last, count);
            count += 1;
            last = sbuf.items.len;
        } else if ((c == '?' or c == '#') and bqs) {
            break;
        } else if (url_map[c] & Map.path != 0) {
            try sbuf.appendSlice(a, &.{ '%', hex_upper[c >> 4], hex_upper[c & 0xf] });
            try ctx.log(p, .invalid_url_unit);
        } else if (c == '.') {
            if (last == sbuf.items.len) {
                var tmp = try pathDotCount(ctx, p, end, &sbuf, &last, &count, bqs);
                if (tmp != p) {
                    // skip '/' or '\', but leave '?' and '#' to the loop
                    if (tmp < end and src[tmp] != '?' and src[tmp] != '#') tmp += 1;
                    p = tmp;
                    continue;
                }
            }
            try sbuf.append(a, '.');
        } else if (c == '%') {
            if (end - p < 3 or hexVal(src[p + 1]) == 0xff or hexVal(src[p + 2]) == 0xff) {
                try ctx.log(p, .invalid_url_unit);
            } else if (src[p + 1] == '2' and (src[p + 2] == 'e' or src[p + 2] == 'E') and last == sbuf.items.len) {
                var tmp = try pathDotCount(ctx, p, end, &sbuf, &last, &count, bqs);
                if (tmp != p) {
                    if (tmp < end and src[tmp] != '?' and src[tmp] != '#') tmp += 1;
                    p = tmp;
                    continue;
                }
            }
            try sbuf.append(a, '%');
        } else {
            if (codepoint_alphanumeric[c] == 0xff) try ctx.log(p, .invalid_url_unit);
            try sbuf.append(a, c);
        }
        p += 1;
    }

    fixWindowsDrive(url, sbuf.items, last, count);
    url.path_length = count + 1;
    try ctx.pathAppendWoSlash(sbuf.items);
    return p;
}

// lxb_url_path_try_dot: a "." or ".." segment the fast path meets
fn pathTryDot(ctx: *Ctx, begin: *usize, last: *usize, start: *usize, end: usize, bqs: bool) !void {
    const src = ctx.src;
    var p = start.*;
    var count: u32 = 0;
    while (p < end) : (p += 1) {
        const c = src[p];
        if (c == '/' or (c == '\\' and ctx.special()) or ((c == '?' or c == '#') and bqs)) {
            break;
        } else if (c == '.') {
            count += 1;
        } else if (c == '%') {
            if (p + 3 <= end and src[p + 1] == '2' and (src[p + 2] == 'e' or src[p + 2] == 'E')) {
                count += 1;
            } else {
                return;
            }
            p += 2;
        } else {
            return;
        }
    }
    if (count == 0 or count > 2) return;
    if (start.* > begin.*) try ctx.pathAppend(src[begin.* .. start.* - 1]);
    if (count == 2) try pathShorten(ctx.a, ctx.url);
    if (p >= end) {
        // the caller appends the trailing empty segment
        start.* = end - 1;
        begin.* = end;
        last.* = end;
        return;
    }
    if (src[p] == '?' or src[p] == '#') {
        start.* = p - 1;
        begin.* = p;
        last.* = p;
        return;
    }
    if (src[p] == '\\') try ctx.log(p, .invalid_reverse_solidus);
    start.* = p;
    begin.* = p + 1;
    last.* = begin.*;
}

// lxb_url_path_dot_count: the same for the slow path's buffer
fn pathDotCount(ctx: *Ctx, start: usize, end: usize, sbuf: *std.ArrayList(u8), last: *usize, path_count: *usize, bqs: bool) !usize {
    const src = ctx.src;
    var p = start;
    var count: u32 = 0;
    while (p < end) : (p += 1) {
        const c = src[p];
        if (c == '/' or (c == '\\' and ctx.special()) or ((c == '?' or c == '#') and bqs)) {
            break;
        } else if (c == '.') {
            count += 1;
        } else if (c == '%') {
            if (p + 3 <= end and src[p + 1] == '2' and (src[p + 2] == 'e' or src[p + 2] == 'E')) {
                count += 1;
            } else {
                return start;
            }
            p += 2;
        } else {
            return start;
        }
    }
    if (count == 0 or count > 2) return start;
    if (p < end and src[p] == '\\') try ctx.log(p, .invalid_reverse_solidus);
    const items = sbuf.items;
    if (ctx.url.scheme_type == .file and path_count.* == 1 and last.* >= 2 and
        isNormalizedWindowsDriveLetter(items[1 .. last.* - 1]))
    {
        return p;
    }
    if (count == 2 and path_count.* > 0) {
        path_count.* -= 1;
        var last_p = last.* - 1;
        while (last_p > 0) {
            last_p -= 1;
            if (items[last_p] == '/') {
                sbuf.items.len = last_p + 1;
                break;
            }
        }
        last.* = sbuf.items.len;
    }
    return p;
}

fn fixWindowsDrive(url: *const Url, buf: []u8, seg: usize, count: usize) void {
    const cur = buf.len;
    if (url.scheme_type == .file and count == 0 and
        ((cur - seg == 3 and buf[cur - 1] == '/') or cur - seg == 2) and
        isWindowsDriveLetter(buf[seg..cur]))
    {
        buf[seg + 1] = ':';
    }
}

// ---- hosts ---------------------------------------------------------------------

const host_opt_not_special: u8 = 1 << 0;
const host_opt_decode: u8 = 1 << 1;
const host_opt_idna: u8 = 1 << 2;

fn hostParse(ctx: *Ctx, data: usize, end: usize, host: *Host, opt_in: u8) !bool {
    const a = ctx.a;
    const src = ctx.src;
    var opt = opt_in;

    if (data < end and src[data] == '[') {
        if (src[end - 1] != ']') {
            try ctx.log(end - 1, .ipv6_unclosed);
            return false;
        }
        clearStr(a, &host.str);
        host.type = .ipv6;
        return ipv6Parse(ctx.p, src, data + 1, end - 1, &host.ipv6);
    }
    if (opt & host_opt_not_special != 0) return opaqueHostParse(ctx, data, end, host);

    // the mraw block the domain lives in, for the freed-domain emulation
    var cap = alignUp(end - data + 2);
    var domain: []u8 = undefined;
    if (opt & host_opt_decode != 0) {
        domain = try percentDecode(a, src[data..end], &opt);
    } else if (opt & host_opt_idna != 0) {
        domain = try a.dupe(u8, src[data..end]);
    } else {
        domain = try a.alloc(u8, end - data);
        for (src[data..end], 0..) |c, i| domain[i] = std.ascii.toLower(c);
    }
    a.free(host.str);
    host.str = domain;

    if (opt & host_opt_idna != 0) {
        const ascii = (try idnaConvert(a, host.str, .ascii)) orelse return false;
        if (ascii.len + 1 > cap) cap = alignUp(ascii.len + 1);
        a.free(host.str);
        host.str = ascii;
    }
    if (host.str.len == 0) return false;

    for (host.str, 0..) |c, i| {
        if (c < 128 and forbidden_domain_cp[c] != 0xff) {
            try ctx.p.logAt(host.str, i, .domain_invalid_code_point);
            return false;
        }
    }

    if (isIpv4(host.str)) {
        var refs: std.ArrayList(Dangling.Ref) = .empty;
        defer refs.deinit(a);
        var ip: u32 = 0;
        const ok = try ipv4Parse(ctx.p, host.str, &ip, &refs);
        if (ok and refs.items.len > 0) {
            ctx.p.dropDangling();
            const block = try a.alloc(u8, @max(cap, host.str.len + 1));
            @memset(block, 0);
            @memcpy(block[0..host.str.len], host.str);
            ctx.p.dangling = .{ .block = block };
            ctx.p.dangling.?.refs = refs;
            refs = .empty;
        }
        clearStr(a, &host.str);
        if (!ok) return false;
        host.ipv4 = ip;
        host.type = .ipv4;
        return true;
    }
    host.type = .domain;
    return true;
}

fn opaqueHostParse(ctx: *Ctx, data: usize, end: usize, host: *Host) !bool {
    const a = ctx.a;
    if (data == end) {
        hostSetEmpty(a, host);
        return true;
    }
    for (ctx.src[data..end], data..) |c, i| {
        if (c < 128 and forbidden_host_cp[c] != 0xff) {
            try ctx.log(i, .host_invalid_code_point);
            return false;
        }
    }
    host.type = .@"opaque";
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(a);
    try percentEncodeInto(a, &out, ctx.src[data..end], &url_map, Map.c0, false);
    try setBytes(a, &host.str, out.items);
    return true;
}

fn percentDecode(a: Allocator, data: []const u8, opt: *u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    var p: usize = 0;
    while (p < data.len) {
        var c = data[p];
        p += 1;
        if (c != '%') {
            try out.append(a, c);
            continue;
        }
        if (p + 2 <= data.len and hexVal(data[p]) != 0xff and hexVal(data[p + 1]) != 0xff) {
            c = hexVal(data[p]) << 4 | hexVal(data[p + 1]);
            p += 2;
            if (c >= 0x80) opt.* |= host_opt_idna;
        }
        try out.append(a, c);
    }
    return out.toOwnedSlice(a);
}

const NumberStatus = enum { ok, warning, err };

fn ipv4NumberParse(d: []const u8, data_in: usize, end: usize, num: *u64) NumberStatus {
    var data = data_in;
    if (data >= end) {
        num.* = 0;
        return .err;
    }
    var r: u64 = 10;
    var map: *const fn (u8) u8 = &numVal;
    var status: NumberStatus = .ok;
    if (data + 1 < end and d[data] == '0') {
        if (d[data + 1] == 'x' or d[data + 1] == 'X') {
            data += 2;
            r = 16;
            map = &hexVal;
        } else {
            data += 1;
            r = 8;
            map = &octVal;
        }
        if (data >= end) {
            num.* = 0;
            return .warning;
        }
        status = .warning;
    }
    var n: u64 = 0;
    while (data < end) {
        const c = d[data];
        data += 1;
        const v = map(c);
        if (v == 0xff) {
            num.* = 0;
            return .err;
        }
        n = v + n * r;
        if (n > std.math.maxInt(u32)) break;
    }
    num.* = n;
    return status;
}

fn isIpv4(d: []const u8) bool {
    if (d.len == 0) return false;
    var end = d.len;
    var p = end;
    var isit = true;
    var first = true;
    while (true) {
        p -= 1;
        const c = d[p];
        if (hexVal(c) == 0xff) {
            if (c == '.') {
                if (p == end - 1) {
                    if (first) {
                        end = p;
                        first = false;
                        if (p > 0) continue;
                        break;
                    }
                    return false;
                }
                p += 1;
                break;
            } else if (c != 'x' and c != 'X') {
                return false;
            }
        }
        if (c < '0' or c > '9') isit = false;
        if (!(p > 0)) break;
    }
    if (p == end) return false;
    if (isit) return true;
    var num: u64 = 0;
    return ipv4NumberParse(d, p, end, &num) != .err;
}

fn ipv4Log(p: *Parser, d: []const u8, pos: usize, t: ErrorType, refs: *std.ArrayList(Dangling.Ref)) !void {
    try refs.append(p.a, .{ .index = p.log.items.len, .offset = pos });
    try p.logAt(d, pos, t);
}

fn ipv4Append(p: *Parser, d: []const u8, begin: usize, end: usize, parts: *[5]u64, i: usize, refs: *std.ArrayList(Dangling.Ref)) !bool {
    const status = ipv4NumberParse(d, begin, end, &parts[i]);
    if (status == .err) {
        try ipv4Log(p, d, begin, .ipv4_non_numeric_part, refs);
        return false;
    }
    if (status == .warning) try ipv4Log(p, d, begin, .ipv4_non_decimal_part, refs);
    // lexbor never records which part was out of range (its out_of stays -1)
    if (parts[i] > 255) try ipv4Log(p, d, begin, .ipv4_out_of_range_part, refs);
    return true;
}

fn ipv4Parse(p: *Parser, d: []const u8, out: *u32, refs: *std.ArrayList(Dangling.Ref)) !bool {
    const st = [_]u64{ 0, 256, 65536, 16777216, 4294967296, 0 };
    if (d.len == 0) return false;
    var i: usize = 0;
    var pos: usize = 0;
    var begin: usize = 0;
    var parts: [5]u64 = @splat(0);
    while (pos < d.len) : (pos += 1) {
        if (d[pos] == '.') {
            if (i == 4) {
                try ipv4Log(p, d, begin, .ipv4_too_many_parts, refs);
                return false;
            }
            i += 1;
            if (!try ipv4Append(p, d, begin, pos, &parts, i, refs)) return false;
            begin = pos + 1;
        }
    }
    if (begin < pos) {
        if (i == 4) {
            try ipv4Log(p, d, begin, .ipv4_too_many_parts, refs);
            return false;
        }
        i += 1;
        if (!try ipv4Append(p, d, begin, pos, &parts, i, refs)) return false;
    } else if (d[pos - 1] == '.') {
        try ipv4Log(p, d, begin, .ipv4_empty_part, refs);
    }
    if (parts[i] >= st[5 - i]) return false;
    var ip: u64 = parts[i];
    i -= 1;
    var j: usize = 1;
    while (j <= i) : (j += 1) {
        if (parts[j] > 255) return false;
        ip += parts[j] * st[4 - j];
    }
    out.* = @truncate(ip);
    return true;
}

fn ipv6Parse(p: *Parser, src: []const u8, data: usize, end: usize, ipv6: *[8]u16) !bool {
    ipv6.* = @splat(0);
    var piece: usize = 0;
    var compress: ?usize = null;
    var pos = data;
    var err_type: ErrorType = undefined;

    fail: {
        if (pos < end) {
            if (src[pos] == ':') {
                if (pos + 1 >= end or src[pos + 1] != ':') {
                    if (pos + 1 < end) pos += 1;
                    err_type = .ipv6_invalid_compression;
                    break :fail;
                }
                pos += 2;
                piece += 1;
                compress = piece;
            }
            while (pos < end) {
                if (piece == 8) {
                    err_type = .ipv6_too_many_pieces;
                    break :fail;
                }
                if (src[pos] == ':') {
                    if (compress != null) {
                        err_type = .ipv6_multiple_compression;
                        break :fail;
                    }
                    pos += 1;
                    piece += 1;
                    compress = piece;
                    continue;
                }
                var num: u16 = 0;
                var i: usize = 0;
                while (i < 4 and pos < end) {
                    const c = hexVal(src[pos]);
                    if (c == 0xff) break;
                    num = num << 4 | c;
                    pos += 1;
                    i += 1;
                }
                if (pos >= end) {
                    ipv6[piece] = num;
                    piece += 1;
                    break;
                }
                if (src[pos] == '.') {
                    if (i == 0) {
                        err_type = .ipv4_in_ipv6_invalid_code_point;
                        break :fail;
                    }
                    pos -= i;
                    if (piece > 6) {
                        err_type = .ipv4_in_ipv6_too_many_pieces;
                        break :fail;
                    }
                    return ipv4InIpv6Parse(p, src, pos, end, ipv6, piece, compress);
                }
                if (src[pos] == ':') {
                    pos += 1;
                    if (pos >= end) {
                        err_type = .ipv6_invalid_code_point;
                        break :fail;
                    }
                } else if (pos < end) {
                    err_type = .ipv6_invalid_code_point;
                    break :fail;
                }
                ipv6[piece] = num;
                piece += 1;
            }
        }
        return ipv6Done(p, src, pos, ipv6, piece, compress);
    }
    try p.logAt(src, pos, err_type);
    return false;
}

fn ipv6Done(p: *Parser, src: []const u8, pos: usize, ipv6: *[8]u16, piece: usize, compress: ?usize) !bool {
    if (compress) |cmp| {
        var num = piece - cmp;
        var i: usize = 7;
        while (i != 0 and num > 0) {
            const idx = cmp + num - 1;
            const swap = ipv6[idx];
            ipv6[idx] = ipv6[i];
            ipv6[i] = swap;
            i -= 1;
            num -= 1;
        }
    } else if (piece != 8) {
        try p.logAt(src, pos, .ipv6_too_few_pieces);
        return false;
    }
    return true;
}

fn ipv4InIpv6Parse(p: *Parser, src: []const u8, start: usize, end: usize, ipv6: *[8]u16, piece_in: usize, compress: ?usize) !bool {
    var piece = piece_in;
    var seen: u32 = 0;
    var pos = start;
    var err_type: ErrorType = undefined;
    fail: {
        while (pos < end) {
            var ipv4: i32 = -1;
            if (seen > 0) {
                if (src[pos] == '.' and seen < 4) {
                    pos += 1;
                    if (pos >= end) break;
                } else {
                    err_type = .ipv4_in_ipv6_invalid_code_point;
                    break :fail;
                }
            }
            while (true) {
                const c = src[pos];
                if (c < '0' or c > '9') {
                    if (ipv4 == -1) {
                        err_type = .ipv4_in_ipv6_invalid_code_point;
                        break :fail;
                    }
                    break;
                }
                if (ipv4 == -1) {
                    ipv4 = c - '0';
                } else if (ipv4 == 0) {
                    err_type = .ipv4_in_ipv6_invalid_code_point;
                    break :fail;
                } else {
                    ipv4 = ipv4 * 10 + (c - '0');
                }
                if (ipv4 > 255) {
                    err_type = .ipv4_in_ipv6_out_of_range_part;
                    break :fail;
                }
                pos += 1;
                if (!(pos < end)) break;
            }
            ipv6[piece] = ipv6[piece] *% 0x100 +% @as(u16, @intCast(ipv4));
            seen += 1;
            if (seen == 2 or seen == 4) piece += 1;
        }
        if (seen != 4) {
            err_type = .ipv4_in_ipv6_too_few_parts;
            break :fail;
        }
        return ipv6Done(p, src, pos, ipv6, piece, compress);
    }
    try p.logAt(src, pos, err_type);
    return false;
}

// ---- idna --------------------------------------------------------------------

const UErrorCode = c_int;
const UNORM2_COMPOSE: i32 = 0;
const U_BUFFER_OVERFLOW_ERROR: UErrorCode = 15;

extern fn zphp_unorm2_getInstance(pkg: ?[*:0]const u8, name: [*:0]const u8, mode: i32, err: *UErrorCode) ?*const anyopaque;
extern fn zphp_unorm2_normalize(n: *const anyopaque, src: [*]const u16, src_len: i32, dest: [*]u16, cap: i32, err: *UErrorCode) i32;

fn uts46Normalizer() ?*const anyopaque {
    var e: UErrorCode = 0;
    const n = zphp_unorm2_getInstance(null, "uts46", UNORM2_COMPOSE, &e);
    if (e > 0) return null;
    return n;
}

// the idna mapping table and nfc, through icu's uts46 normalizer; a
// surrogate (which lexbor's lax decoder can produce) is disallowed
fn uts46Map(a: Allocator, cps: []const u32) !?[]u32 {
    const norm = uts46Normalizer() orelse return null;
    var utf16: std.ArrayList(u16) = .empty;
    defer utf16.deinit(a);
    for (cps) |cp| {
        if ((cp >= 0xD800 and cp <= 0xDFFF) or cp > 0x10FFFF) {
            try utf16.append(a, 0xFFFD);
        } else if (cp >= 0x10000) {
            const v = cp - 0x10000;
            try utf16.appendSlice(a, &.{ @intCast(0xD800 + (v >> 10)), @intCast(0xDC00 + (v & 0x3FF)) });
        } else {
            try utf16.append(a, @intCast(cp));
        }
    }
    var cap: usize = utf16.items.len * 3 + 16;
    var dest = try a.alloc(u16, cap);
    defer a.free(dest);
    var e: UErrorCode = 0;
    var n = zphp_unorm2_normalize(norm, utf16.items.ptr, @intCast(utf16.items.len), dest.ptr, @intCast(cap), &e);
    if (e == U_BUFFER_OVERFLOW_ERROR) {
        cap = @intCast(n);
        dest = try a.realloc(dest, cap);
        e = 0;
        n = zphp_unorm2_normalize(norm, utf16.items.ptr, @intCast(utf16.items.len), dest.ptr, @intCast(cap), &e);
    }
    if (e > 0) return null;
    var out: std.ArrayList(u32) = .empty;
    errdefer out.deinit(a);
    var i: usize = 0;
    const len: usize = @intCast(n);
    while (i < len) : (i += 1) {
        const u = dest[i];
        if (u >= 0xD800 and u <= 0xDBFF and i + 1 < len and dest[i + 1] >= 0xDC00 and dest[i + 1] <= 0xDFFF) {
            try out.append(a, 0x10000 + ((@as(u32, u) - 0xD800) << 10) + (dest[i + 1] - 0xDC00));
            i += 1;
        } else {
            try out.append(a, u);
        }
    }
    return try out.toOwnedSlice(a);
}

// lexbor's idna types VALID and DEVIATION, the two a label may hold
fn isValidOrDeviation(cp: u32) bool {
    switch (cp) {
        0x00DF, 0x03C2, 0x200C, 0x200D => return true,
        0xFFFD => return false,
        else => {},
    }
    if (cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF)) return false;
    const norm = uts46Normalizer() orelse return false;
    var src: [2]u16 = undefined;
    var len: i32 = 1;
    if (cp >= 0x10000) {
        const v = cp - 0x10000;
        src = .{ @intCast(0xD800 + (v >> 10)), @intCast(0xDC00 + (v & 0x3FF)) };
        len = 2;
    } else {
        src[0] = @intCast(cp);
    }
    var dest: [32]u16 = undefined;
    var e: UErrorCode = 0;
    const n = zphp_unorm2_normalize(norm, &src, len, &dest, dest.len, &e);
    if (e > 0 or n != len) return false;
    return dest[0] == src[0] and (len == 1 or dest[1] == src[1]);
}

fn startsXn(label: []const u32) bool {
    return label.len >= 4 and (label[0] == 'x' or label[0] == 'X') and (label[1] == 'n' or label[1] == 'N') and
        label[2] == '-' and label[3] == '-';
}

// lxb_unicode_idna_validity_criteria_cp without CheckHyphens, which lexbor's
// url doesn't ask for (its CheckBidi and CheckJoiners flags do nothing)
fn validityCriteria(label: []const u32) bool {
    if (startsXn(label)) return false;
    for (label) |cp| {
        if (cp == '.') return false;
        if (!isValidOrDeviation(cp)) return false;
    }
    return true;
}

const IdnaMode = enum { ascii, unicode };

// lxb_unicode_idna_to_ascii / lxb_unicode_idna_to_unicode; null is failure
fn idnaConvert(a: Allocator, data: []const u8, mode: IdnaMode) !?[]u8 {
    var decoded: std.ArrayList(u32) = .empty;
    defer decoded.deinit(a);
    var i: usize = 0;
    while (i < data.len) {
        const cp = decodeValid(data, &i, data.len);
        if (cp > max_codepoint) return null;
        try decoded.append(a, cp);
    }
    const cps = (try uts46Map(a, decoded.items)) orelse return null;
    defer a.free(cps);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    var start: usize = 0;
    for (cps, 0..) |cp, k| {
        if (cp == '.') {
            if (!try idnaLabel(a, &out, cps[start..k], mode)) {
                out.deinit(a);
                return null;
            }
            start = k + 1;
        }
    }
    if (cps.len > start or (cps.len >= 1 and cps[cps.len - 1] == '.')) {
        if (!try idnaLabel(a, &out, cps[start..], mode)) {
            out.deinit(a);
            return null;
        }
    }
    // remove the last full stop
    if (out.items.len > 0) out.items.len -= 1;
    return try out.toOwnedSlice(a);
}

fn idnaLabel(a: Allocator, out: *std.ArrayList(u8), label: []const u32, mode: IdnaMode) !bool {
    if (startsXn(label)) {
        // a label that doesn't decode falls to the validity test, which its
        // xn-- prefix fails
        const dec = (try punycodeDecode(a, label[4..])) orelse return false;
        defer a.free(dec);
        if (!validityCriteria(dec)) return false;
        return idnaEmit(a, out, dec, mode);
    }
    if (!validityCriteria(label)) return false;
    return idnaEmit(a, out, label, mode);
}

fn idnaEmit(a: Allocator, out: *std.ArrayList(u8), label: []const u32, mode: IdnaMode) !bool {
    switch (mode) {
        .ascii => {
            var enc = (try punycodeEncode(a, label)) orelse return false;
            defer enc.bytes.deinit(a);
            if (!enc.unchanged) try out.appendSlice(a, "xn--");
            try out.appendSlice(a, enc.bytes.items);
        },
        .unicode => {
            for (label) |cp| if (utf8Length(cp) == 0) return false;
            for (label) |cp| try appendUtf8(a, out, cp);
        },
    }
    try out.append(a, '.');
    return true;
}

// ---- punycode ------------------------------------------------------------------

const puny_base: u64 = 36;
const puny_tmin: u64 = 1;
const puny_tmax: u64 = 26;
const puny_skew: u64 = 38;
const puny_damp: u64 = 700;
const uint32_max: u64 = std.math.maxInt(u32);

fn punyEncodeDigit(d: u64) u8 {
    return @intCast(d + 22 + 75 * @as(u64, @intFromBool(d < 26)));
}

fn punyDecodeDigit(cp: u32) u64 {
    if (cp -% 48 < 10) return cp -% 22;
    if (cp -% 65 < 26) return cp -% 65;
    if (cp -% 97 < 26) return cp -% 97;
    return puny_base;
}

fn punyAdapt(delta_in: u64, numpoints: u64, firsttime: bool) u64 {
    var delta = if (firsttime) delta_in / puny_damp else delta_in >> 1;
    delta += delta / numpoints;
    var k: u64 = 0;
    while (delta > ((puny_base - puny_tmin) * puny_tmax) / 2) : (k += puny_base) {
        delta /= puny_base - puny_tmin;
    }
    return k + (puny_base - puny_tmin + 1) * delta / (delta + puny_skew);
}

fn punyT(k: u64, bias: u64) u64 {
    if (k <= bias) return puny_tmin;
    if (k >= bias + puny_tmax) return puny_tmax;
    return k - bias;
}

const Encoded = struct { bytes: std.ArrayList(u8), unchanged: bool };

// lxb_punycode_encode_cp
fn punycodeEncode(a: Allocator, cps: []const u32) !?Encoded {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    for (cps) |cp| if (cp < 0x80) try out.append(a, @intCast(cp));
    const b: u64 = out.items.len;
    var handled: u64 = b;
    if (handled >= cps.len) return .{ .bytes = out, .unchanged = true };
    if (b > 0) try out.append(a, '-');

    var n: u64 = 0x80;
    var bias: u64 = 72;
    var delta: u64 = 0;
    while (handled < cps.len) {
        var m: u64 = uint32_max;
        for (cps) |cp| {
            if (cp >= n and cp < m) m = cp;
        }
        const h = handled + 1;
        if (m - n > (uint32_max -% delta) / h) {
            out.deinit(a);
            return null;
        }
        delta += (m - n) * h;
        n = m;
        for (cps) |cp| {
            if (cp < n) delta +%= 1;
            if (cp == n) {
                var q = delta;
                var k: u64 = puny_base;
                while (true) : (k += puny_base) {
                    const t = punyT(k, bias);
                    if (q < t) break;
                    try out.append(a, punyEncodeDigit(t + (q - t) % (puny_base - t)));
                    q = (q - t) / (puny_base - t);
                }
                const hh = handled;
                try out.append(a, punyEncodeDigit(q));
                bias = punyAdapt(delta, hh + 1, hh == b);
                delta = 0;
                handled += 1;
            }
        }
        delta += 1;
        n += 1;
    }
    return .{ .bytes = out, .unchanged = false };
}

// lxb_punycode_decode_cp
fn punycodeDecode(a: Allocator, data: []const u32) !?[]u32 {
    var out: std.ArrayList(u32) = .empty;
    errdefer out.deinit(a);
    var delimiter: usize = data.len;
    while (delimiter != 0) {
        delimiter -= 1;
        if (data[delimiter] == '-') break;
    }
    for (data[0..delimiter]) |cp| {
        if (cp >= 0x80) {
            out.deinit(a);
            return null;
        }
        try out.append(a, cp);
    }
    var i: u64 = 0;
    var n: u64 = 0x80;
    var bias: u64 = 72;
    var in: usize = if (delimiter != 0) delimiter + 1 else 0;
    while (in < data.len) {
        const oldi = i;
        var w: u64 = 1;
        var k: u64 = puny_base;
        while (true) : (k += puny_base) {
            if (in >= data.len) {
                out.deinit(a);
                return null;
            }
            const digit = punyDecodeDigit(data[in]);
            in += 1;
            if (digit >= puny_base or digit > (uint32_max - i) / w) {
                out.deinit(a);
                return null;
            }
            i += digit * w;
            const t = punyT(k, bias);
            if (digit < t) break;
            if (w > uint32_max / (puny_base - t)) {
                out.deinit(a);
                return null;
            }
            w *= puny_base - t;
        }
        const h: u64 = out.items.len + 1;
        bias = punyAdapt(i - oldi, h, oldi == 0);
        if (i / h > uint32_max - n) {
            out.deinit(a);
            return null;
        }
        n += i / h;
        i %= h;
        try out.insert(a, @intCast(i), @intCast(n));
        i += 1;
    }
    return try out.toOwnedSlice(a);
}

// ---- serialization ----------------------------------------------------------------

fn writeDecimal(a: Allocator, out: *std.ArrayList(u8), v: u64) !void {
    var buf: [24]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{v}) catch unreachable;
    try out.appendSlice(a, s);
}

fn writeIpv4(a: Allocator, out: *std.ArrayList(u8), v: u32) !void {
    try writeDecimal(a, out, @as(u8, @truncate(v >> 24)));
    try out.append(a, '.');
    try writeDecimal(a, out, @as(u8, @truncate(v >> 16)));
    try out.append(a, '.');
    try writeDecimal(a, out, @as(u8, @truncate(v >> 8)));
    try out.append(a, '.');
    try writeDecimal(a, out, @as(u8, @truncate(v)));
}

fn writeIpv6(a: Allocator, out: *std.ArrayList(u8), ipv6: [8]u16) !void {
    var count: usize = 0;
    var tmp_count: usize = @intFromBool(ipv6[0] == 0);
    var compress: ?usize = null;
    var tmp_compress: usize = 0;
    var i: usize = 1;
    while (i < 8) : (i += 1) {
        if (ipv6[i] == 0) {
            if (ipv6[i - 1] == 0) {
                tmp_count += 1;
            } else {
                tmp_count = 1;
                tmp_compress = i;
            }
        } else if (tmp_count > count) {
            compress = tmp_compress;
            count = tmp_count;
        }
    }
    if (tmp_count > count) {
        compress = tmp_compress;
        count = tmp_count;
    }
    if (compress != null and compress.? == 1 and ipv6[0] == 0) compress = 0;
    if (count < 2) compress = null;

    var ignore = false;
    i = 0;
    while (i < 8) : (i += 1) {
        if (ignore) {
            if (ipv6[i] == 0) continue;
            ignore = false;
        }
        if (compress != null and compress.? == i) {
            try out.append(a, ':');
            if (i == 0) try out.append(a, ':');
            i += count - 1;
            ignore = true;
            continue;
        }
        var buf: [8]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{x}", .{ipv6[i]}) catch unreachable;
        try out.appendSlice(a, s);
        if (i != 7) try out.append(a, ':');
    }
}

fn writeHost(a: Allocator, out: *std.ArrayList(u8), host: *const Host) !void {
    switch (host.type) {
        .domain, .@"opaque" => try out.appendSlice(a, host.str),
        .ipv4 => try writeIpv4(a, out, host.ipv4),
        .ipv6 => {
            try out.append(a, '[');
            try writeIpv6(a, out, host.ipv6);
            try out.append(a, ']');
        },
        else => {},
    }
}

pub fn serializeHostIpv4(a: Allocator, v: u32) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    try writeIpv4(a, &out, v);
    return out.toOwnedSlice(a);
}

pub fn serializeHostIpv6(a: Allocator, v: [8]u16) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    try writeIpv6(a, &out, v);
    return out.toOwnedSlice(a);
}

pub fn serializeHost(a: Allocator, host: *const Host) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    try writeHost(a, &out, host);
    return out.toOwnedSlice(a);
}

// the host's unicode form (lxb_url_serialize_host_unicode); null when idna
// fails, where lexbor writes nothing
pub fn hostToUnicode(a: Allocator, host: *const Host) !?[]u8 {
    if (host.type != .domain and host.type != .@"opaque") return try serializeHost(a, host);
    return idnaConvert(a, host.str, .unicode);
}

// what php's getUnicodeHost() reads: an empty string when idna fails
pub fn serializeHostUnicode(a: Allocator, host: *const Host) ![]u8 {
    return (try hostToUnicode(a, host)) orelse try a.alloc(u8, 0);
}

fn serializeBody(a: Allocator, url: *const Url, unicode: bool, exclude_fragment: bool) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    try out.appendSlice(a, url.scheme_name);
    try out.append(a, ':');
    if (url.host.type != .undef) {
        try out.appendSlice(a, "//");
        if (includesCredentials(url)) {
            try out.appendSlice(a, url.username);
            if (url.password.len != 0) {
                try out.append(a, ':');
                try out.appendSlice(a, url.password);
            }
            try out.append(a, '@');
        }
        if (unicode and (url.host.type == .domain or url.host.type == .@"opaque")) {
            // lexbor stops at a host idna can't convert and php keeps what
            // was written before it
            const h = (try idnaConvert(a, url.host.str, .unicode)) orelse return out.toOwnedSlice(a);
            defer a.free(h);
            try out.appendSlice(a, h);
        } else {
            try writeHost(a, &out, &url.host);
        }
        if (url.has_port) {
            try out.append(a, ':');
            try writeDecimal(a, &out, url.port);
        }
    } else if (!url.path_opaque and url.path_str.len > 1 and url.path_str[0] == '/' and url.path_str[1] == '/') {
        try out.appendSlice(a, "/.");
    }
    try out.appendSlice(a, url.path_str);
    if (url.query) |q| {
        try out.append(a, '?');
        try out.appendSlice(a, q);
    }
    if (!exclude_fragment) if (url.fragment) |f| {
        try out.append(a, '#');
        try out.appendSlice(a, f);
    };
    return out.toOwnedSlice(a);
}

pub fn serialize(a: Allocator, url: *const Url, exclude_fragment: bool) ![]u8 {
    return serializeBody(a, url, false, exclude_fragment);
}

pub fn serializeIdna(a: Allocator, url: *const Url, exclude_fragment: bool) ![]u8 {
    return serializeBody(a, url, true, exclude_fragment);
}

// ---- entry points ---------------------------------------------------------------

// lxb_url_parse
pub fn parse(p: *Parser, base: ?*const Url, input: []const u8) !?Url {
    var url: Url = .{};
    const ok = parseBasicH(p, &url, base, input, .undef, true) catch |e| {
        url.deinit(p.a);
        return e;
    };
    if (!ok) {
        url.deinit(p.a);
        return null;
    }
    return url;
}

// lxb_url_parse_basic on an existing url, which a failure leaves as far as
// the parse got
pub fn parseBasic(p: *Parser, url: *Url, base: ?*const Url, input: []const u8, state: State) !bool {
    return parseBasicH(p, url, base, input, state, false);
}

pub fn parseHostIpv6(p: *Parser, input: []const u8, out: *[8]u16) !bool {
    if (input.len > 0 and input[0] == '[') {
        if (input[input.len - 1] != ']') {
            try p.logAt(input, input.len - 1, .ipv6_unclosed);
            return false;
        }
        return ipv6Parse(p, input, 1, input.len - 1, out);
    }
    return ipv6Parse(p, input, 0, input.len, out);
}

pub fn protocolSet(p: *Parser, url: *Url, v: []const u8) !bool {
    return parseBasicH(p, url, null, v, .scheme_start, false);
}

pub fn usernameSet(a: Allocator, url: *Url, v: []const u8) !bool {
    if (cannotHaveUserPassPort(url)) return true;
    if (v.len == 0) {
        clearStr(a, &url.username);
        return true;
    }
    const enc = try percentEncodeUtf8(a, v, &url_map, Map.userinfo, false);
    a.free(url.username);
    url.username = enc;
    return true;
}

pub fn passwordSet(a: Allocator, url: *Url, v: []const u8) !bool {
    if (cannotHaveUserPassPort(url)) return true;
    if (v.len == 0) {
        clearStr(a, &url.password);
        return true;
    }
    const enc = try percentEncodeUtf8(a, v, &url_map, Map.userinfo, false);
    a.free(url.password);
    url.password = enc;
    return true;
}

pub fn hostSet(p: *Parser, url: *Url, v: []const u8) !bool {
    return hostSetH(p, url, v, .host);
}

pub fn hostnameSet(p: *Parser, url: *Url, v: []const u8) !bool {
    return hostSetH(p, url, v, .hostname);
}

fn hostSetH(p: *Parser, url: *Url, v: []const u8, override: State) !bool {
    if (url.path_opaque) return true;
    const old = url.host;
    url.host = .{};
    const ok = parseBasicH(p, url, null, v, override, false) catch |e| {
        p.a.free(url.host.str);
        url.host = old;
        return e;
    };
    if (!ok or (override == .hostname and url.host.type == .undef)) {
        p.a.free(url.host.str);
        url.host = old;
    } else {
        p.a.free(old.str);
    }
    return ok;
}

pub fn portSet(p: *Parser, url: *Url, v: []const u8) !bool {
    if (cannotHaveUserPassPort(url)) return true;
    if (v.len == 0) {
        url.port = 0;
        url.has_port = false;
        return true;
    }
    return parseBasicH(p, url, null, v, .port, false);
}

pub fn pathnameSet(p: *Parser, url: *Url, v: []const u8) !bool {
    if (url.path_opaque) return true;
    url.path_length = 0;
    url.path_str = try p.a.realloc(url.path_str, 0);
    return parseBasicH(p, url, null, v, .path_start, false);
}

pub fn searchSet(p: *Parser, url: *Url, v: []const u8) !bool {
    clearOpt(p.a, &url.query);
    if (v.len == 0) return true;
    const s = if (v[0] == '?') v[1..] else v;
    return parseBasicH(p, url, null, s, .query, false);
}

pub fn hashSet(p: *Parser, url: *Url, v: []const u8) !bool {
    clearOpt(p.a, &url.fragment);
    if (v.len == 0) return true;
    const s = if (v[0] == '#') v[1..] else v;
    return parseBasicH(p, url, null, s, .fragment, false);
}

// ---- tables -----------------------------------------------------------------------
const url_map = [256]u8{
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xfe, 0x80, 0xfe, 0xfc, 0xc0, 0x80, 0xc0, 0x88, 0x80, 0x80, 0x00, 0xc0, 0xc0, 0x00, 0x00, 0xe0,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xe0, 0xe0, 0xfe, 0xe0, 0xfe, 0xf0,
    0xe0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xe0, 0xe0, 0xe0, 0xf0, 0x00,
    0xf2, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xf0, 0xe0, 0xf0, 0x80, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
};
const path_map = [256]u8{
    0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02,
    0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02,
    0x01, 0x00, 0x01, 0x01, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x01,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x01,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x01, 0x02, 0x02, 0x00,
    0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x01, 0x00, 0x02,
    0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02,
    0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02,
    0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02,
    0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02,
    0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02,
    0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02,
    0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02,
    0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02,
};
const codepoint_alphanumeric = [160]u8{
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0x21, 0xff, 0xff, 0x24, 0xff, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x2b, 0x2c, 0x2d, 0x2e, 0x2f,
    0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x3b, 0xff, 0x3d, 0xff, 0x3f,
    0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x4b, 0x4c, 0x4d, 0x4e, 0x4f,
    0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0xff, 0xff, 0xff, 0xff, 0x5f,
    0xff, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x6b, 0x6c, 0x6d, 0x6e, 0x6f,
    0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0xff, 0xff, 0xff, 0x7e, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
};
const forbidden_domain_cp = [128]u8{
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
    0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f,
    0x20, 0xff, 0xff, 0x23, 0xff, 0x25, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x2f,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x3a, 0xff, 0x3c, 0xff, 0x3e, 0x3f,
    0x40, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x5b, 0x5c, 0x5d, 0x5e, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7c, 0xff, 0xff, 0x7f,
};
const forbidden_host_cp = [128]u8{
    0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x09, 0x0a, 0xff, 0xff, 0x0d, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0x20, 0xff, 0xff, 0x23, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x2f,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x3a, 0xff, 0x3c, 0xff, 0x3e, 0x3f,
    0x40, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x5b, 0x5c, 0x5d, 0x5e, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7c, 0xff, 0xff, 0xff,
};

// ---- tests (expectations from php 8.6.0) -------------------------------------------

const testing = std.testing;

fn expectParse(input: []const u8, base: ?[]const u8, ascii: ?[]const u8, unicode: ?[]const u8) !void {
    const a = testing.allocator;
    var p = Parser.init(a);
    defer p.deinit();
    var b: ?Url = null;
    defer if (b) |*x| x.deinit(a);
    if (base) |bs| b = (try parse(&p, null, bs)).?;
    var u = try parse(&p, if (b) |*x| x else null, input);
    defer if (u) |*x| x.deinit(a);
    if (ascii == null) return testing.expect(u == null);
    const s = try serialize(a, &u.?, false);
    defer a.free(s);
    try testing.expectEqualStrings(ascii.?, s);
    const us = try serializeIdna(a, &u.?, false);
    defer a.free(us);
    try testing.expectEqualStrings(unicode orelse ascii.?, us);
}

fn expectLog(input: []const u8, expected: []const struct { ErrorType, []const u8 }) !void {
    const a = testing.allocator;
    var p = Parser.init(a);
    defer p.deinit();
    var u = try parse(&p, null, input);
    defer if (u) |*x| x.deinit(a);
    try testing.expectEqual(expected.len, p.log.items.len);
    for (expected, p.log.items) |e, got| {
        try testing.expectEqual(e[0], got.type);
        try testing.expectEqualStrings(e[1], got.context);
    }
}

test "parsing and serialization" {
    try expectParse("https://EXAMPLE.com/a/../b", null, "https://example.com/b", null);
    try expectParse("http:a", null, "http://a/", null);
    try expectParse("http://a/b c?d e#f g", null, "http://a/b%20c?d%20e#f%20g", null);
    try expectParse("foo:bar baz?x", null, "foo:bar baz?x", null);
    try expectParse("https://a/./b/../c/%2e%2E/d", null, "https://a/d", null);
    try expectParse("http://EX%41MPLE.com/", null, "http://EXAMPLE.com/", "http://example.com/");
    try expectParse("foo://EXAMPLE/", null, "foo://EXAMPLE/", "foo://example/");
    try expectParse("non-spec:/.//p", null, "non-spec:/.//p", null);
    try expectParse("a", null, null, null);
    try expectParse("http://a:99999/", null, null, null);
}

test "hosts: ipv4, ipv6 and idna" {
    try expectParse("http://0x7f.1/", null, "http://127.0.0.1/", null);
    try expectParse("http://1.2.3.4./", null, "http://1.2.3.4/", null);
    try expectParse("http://256.1.1.1/", null, null, null);
    try expectParse("http://[::1.2.3.4]/", null, "http://[::102:304]/", null);
    try expectParse("http://[1:0:0:2::3:0]/", null, "http://[1::2:0:0:3:0]/", null);
    try expectParse("http://[1::2::3]/", null, null, null);
    try expectParse("http://\xc3\xa4.com/", null, "http://xn--4ca.com/", "http://\xc3\xa4.com/");
    try expectParse("https://fa\xc3\x9f.ExAmPlE/", null, "https://xn--fa-hia.example/", "https://fa\xc3\x9f.example/");
    try expectParse("http://xn--mnchen-3ya.de/", null, "http://xn--mnchen-3ya.de/", "http://m\xc3\xbcnchen.de/");
    try expectParse("http://xn--abc-/", null, "http://abc/", null);
    try expectParse("http://xn--.com/", null, "http://.com/", null);
    try expectParse("http://xn--zz/", null, null, null);
    try expectParse("http://\xe2\x92\xb6.com/", null, "http://a.com/", null);
    // an opaque host idna can't read leaves the unicode form at the host
    try expectParse("foo://u:p@xn--zz:8/p", null, "foo://u:p@xn--zz:8/p", "foo://u:p@");
}

test "file urls and resolution" {
    try expectParse("file:///C|/x", null, "file:///C:/x", null);
    try expectParse("file://C:/x", null, "file:///C:/x", null);
    try expectParse("file:///C:/../x", null, "file:///C:/x", null);
    try expectParse("file://localhost/x", null, "file:///x", null);
    try expectParse("../g", "http://a/b/c/d;p?q", "http://a/b/g", null);
    try expectParse("?y", "http://a/b/c/d;p?q", "http://a/b/c/d;p?y", null);
    try expectParse("#s", "mailto:a@b", "mailto:a@b#s", null);
    try expectParse("x", "mailto:a@b", null, null);
    try expectParse("/C:/y", "file://host/x/y", "file://host/C:/y", null);
}

test "validation errors and their contexts" {
    try expectLog(" http://a/ ", &.{ .{ .invalid_url_unit, " http://a/ " }, .{ .invalid_url_unit, " " } });
    try expectLog("\thttp://a\n/b\r", &.{ .{ .invalid_url_unit, "\thttp://a\n/b\r" }, .{ .invalid_url_unit, "\r" }, .{ .invalid_url_unit, "\n/b\r" } });
    try expectLog("http://user@/", &.{ .{ .invalid_credentials, "@/" }, .{ .host_missing, "/" } });
    try expectLog("http://a\xc2\xa0b.com/", &.{.{ .domain_invalid_code_point, " b.com" }});
    try expectLog("http://ex\xc3\xa4mple.com\x00/", &.{.{ .domain_invalid_code_point, "" }});
    try expectLog("http://[::1/", &.{.{ .ipv6_unclosed, "1/" }});
    try expectLog("http://1.2.3.4.5/", &.{.{ .ipv4_too_many_parts, "5" }});
    try expectLog("http://256.1.1.1/", &.{.{ .ipv4_out_of_range_part, "256.1.1.1" }});
    // the freed domain's block went to the path, so php reads "/" there
    try expectLog("http://0x7f.1/", &.{.{ .ipv4_non_decimal_part, "/" }});
    try expectLog("http://a/b\\c", &.{.{ .invalid_reverse_solidus, "\\c" }});
    try expectLog("file://C:/x", &.{.{ .file_invalid_windows_drive_letter_host, "C:/x" }});
    try expectLog("http://a/\x00x", &.{.{ .invalid_url_unit, "" }});
}

test "setters" {
    const a = testing.allocator;
    var p = Parser.init(a);
    defer p.deinit();
    var u = (try parse(&p, null, "https://user:pw@example.com:8080/a/b?q#f")).?;
    defer u.deinit(a);
    try testing.expect(try protocolSet(&p, &u, "http"));
    try testing.expect(try hostnameSet(&p, &u, "EXAMPLE.org"));
    try testing.expect(try portSet(&p, &u, "80"));
    try testing.expect(try pathnameSet(&p, &u, "/x y/../z"));
    try testing.expect(try searchSet(&p, &u, "?a b"));
    try testing.expect(try hashSet(&p, &u, ""));
    try testing.expect(try usernameSet(a, &u, "\xc3\xa4"));
    try testing.expect(!try portSet(&p, &u, "-1"));
    // a special url can't take a non-special scheme
    try testing.expect(try protocolSet(&p, &u, "foo"));
    const s = try serialize(a, &u, false);
    defer a.free(s);
    try testing.expectEqualStrings("http://%C3%A4:pw@example.org/z?a%20b", s);
}

test "builder primitives: an opaque path state with a delimiter" {
    const a = testing.allocator;
    var p = Parser.init(a);
    defer p.deinit();
    var u = empty(a);
    defer u.deinit(a);
    u.scheme_type = .unknown;
    try testing.expect(try protocolSet(&p, &u, "foo"));
    p.clean();
    try testing.expect(try parseBasic(&p, &u, null, "abc  ?", .opaque_path));
    try testing.expectEqual(@as(usize, 2), p.log.items.len);
    try testing.expectEqualStrings("  ?", p.log.items[0].context);
    try testing.expectEqualStrings(" ?", p.log.items[1].context);
    try testing.expect(try searchSet(&p, &u, "q"));
    const s = try serialize(a, &u, false);
    defer a.free(s);
    try testing.expectEqualStrings("foo:abc %20?q", s);

    var ip: [8]u16 = undefined;
    p.clean();
    try testing.expect(!try parseHostIpv6(&p, "[1::2::3]", &ip));
    try testing.expectEqual(ErrorType.ipv6_multiple_compression, p.log.items[0].type);
}

test "percent encoding sets" {
    const a = testing.allocator;
    var map = percentEncodingMap();
    map['%'] = 0xff;
    const r = try percentEncodeUtf8(a, "a b/c?d#e%\xc3\xa9", &map, Map.x_www_form, true);
    defer a.free(r);
    try testing.expectEqualStrings("a+b%2Fc%3Fd%23e%25%C3%A9", r);
    const q = try percentEncodeUtf8(a, "a b'\"#", &map, Map.special_query, false);
    defer a.free(q);
    try testing.expectEqualStrings("a%20b%27%22%23", q);
}

fn parseForOom(a: Allocator, input: []const u8) !void {
    var p = Parser.init(a);
    defer p.deinit();
    var u = (try parse(&p, null, input)) orelse return;
    defer u.deinit(a);
    var c = try u.clone(a);
    defer c.deinit(a);
    const s = try serializeIdna(a, &c, false);
    a.free(s);
}

test "allocation failures leak nothing" {
    const inputs = [_][]const u8{ " https://u:p@\xc3\xa4.Com:81/a/./b/../%2e/c d?q r#f g ", "http://0x7f.1/x\\y", "file:///C|/a/../b", "foo:a b ?c", "http://[::1.2.3.4]/" };
    for (inputs) |in| try testing.checkAllAllocationFailures(testing.allocator, parseForOom, .{in});
}
