// a port of uriparser 1.0.3 (the char variant), the rfc 3986 parser php's
// ext/uri wraps for Uri\Rfc3986\Uri. it covers what uri_parser_rfc3986.c
// calls: parsing, strict reference resolution, syntax normalization,
// recomposition, copying, the component setters and the well-formedness
// checks. text ranges become owned slices: null is an absent range, "" a
// present but empty one (uriparser's SafeToPointTo), and the path is the
// segment list in order
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const HostData = union(enum) {
    none,
    ip4: [4]u8,
    ip6: [16]u8,
    // the text is host_text, as uriparser's hostData.ipFuture mirrors hostText
    ip_future,
};

pub const Error = error{ Syntax, AddBaseRelBase, SetUserInfoHostNotSet, SetHostPortSet, SetHostUserInfoSet, SetPortHostNotSet, OutOfMemory };

// the URI_NORMALIZE_* bits
pub const normalize_scheme: u32 = 1 << 0;
pub const normalize_user_info: u32 = 1 << 1;
pub const normalize_host: u32 = 1 << 2;
pub const normalize_path: u32 = 1 << 3;
pub const normalize_query: u32 = 1 << 4;
pub const normalize_fragment: u32 = 1 << 5;
pub const normalize_port: u32 = 1 << 6;

pub const Uri = struct {
    scheme: ?[]u8 = null,
    user_info: ?[]u8 = null,
    host_text: ?[]u8 = null,
    host_data: HostData = .none,
    port_text: ?[]u8 = null,
    segments: std.ArrayListUnmanaged([]u8) = .empty,
    query: ?[]u8 = null,
    fragment: ?[]u8 = null,
    absolute_path: bool = false,

    pub fn deinit(self: *Uri, a: Allocator) void {
        freeOpt(a, self.scheme);
        freeOpt(a, self.user_info);
        freeOpt(a, self.host_text);
        freeOpt(a, self.port_text);
        freePath(a, self);
        self.segments.deinit(a);
        freeOpt(a, self.query);
        freeOpt(a, self.fragment);
        self.* = .{};
    }

    pub fn clone(self: *const Uri, a: Allocator) Error!Uri {
        var out = Uri{ .host_data = self.host_data, .absolute_path = self.absolute_path };
        errdefer out.deinit(a);
        out.scheme = try dupOpt(a, self.scheme);
        out.user_info = try dupOpt(a, self.user_info);
        out.host_text = try dupOpt(a, self.host_text);
        out.port_text = try dupOpt(a, self.port_text);
        try out.segments.ensureTotalCapacity(a, self.segments.items.len);
        for (self.segments.items) |s| out.segments.appendAssumeCapacity(try a.dupe(u8, s));
        out.query = try dupOpt(a, self.query);
        out.fragment = try dupOpt(a, self.fragment);
        return out;
    }

    // uriHasHostA: ipFuture isn't checked, its text is in hostText anyway
    pub fn hasHost(self: *const Uri) bool {
        return self.host_text != null or self.host_data == .ip4 or self.host_data == .ip6;
    }
};

fn freeOpt(a: Allocator, s: ?[]u8) void {
    if (s) |v| a.free(v);
}

fn dupOpt(a: Allocator, s: ?[]const u8) Error!?[]u8 {
    return if (s) |v| try a.dupe(u8, v) else null;
}

fn freePath(a: Allocator, uri: *Uri) void {
    for (uri.segments.items) |s| a.free(s);
    uri.segments.clearRetainingCapacity();
}

fn replace(a: Allocator, slot: *?[]u8, v: ?[]const u8) Error!void {
    const new = try dupOpt(a, v);
    freeOpt(a, slot.*);
    slot.* = new;
}

// ---- character sets (UriSets.h) ----

fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isHexdig(c: u8) bool {
    return isDigit(c) or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}

fn isSubDelim(c: u8) bool {
    return switch (c) {
        '!', '$', '&', '\'', '(', ')', '*', '+', ',', ';', '=' => true,
        else => false,
    };
}

fn isUnreserved(c: u8) bool {
    return isAlpha(c) or isDigit(c) or c == '-' or c == '.' or c == '_' or c == '~';
}

fn isPcharNoPct(c: u8) bool {
    return isUnreserved(c) or isSubDelim(c) or c == ':' or c == '@';
}

fn isPchar(c: u8) bool {
    return isPcharNoPct(c) or c == '%';
}

fn hexdigToInt(c: u8) u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => 0,
    };
}

fn hexToLetter(v: u8, upper: bool) u8 {
    if (v < 10) return '0' + v;
    return (if (upper) @as(u8, 'A') else 'a') + (v - 10);
}

// ---- the parser (UriParse.c) ----

const Range = struct {
    first: ?usize = null,
    after: ?usize = null,

    fn set(self: Range) bool {
        return self.first != null and self.after != null;
    }
};

// the parse keeps uriparser's pointer-based state as offsets into the input,
// so the intermediate resets ("not a scheme", "not a host") work as in C
const Parser = struct {
    s: []const u8,
    a: Allocator,
    scheme: Range = .{},
    user_info: Range = .{},
    host_text: Range = .{},
    ip4: ?[4]u8 = null,
    ip6: ?[16]u8 = null,
    ip_future: Range = .{},
    port: Range = .{},
    query: Range = .{},
    fragment: Range = .{},
    absolute_path: bool = false,
    segs: std.ArrayListUnmanaged(Range) = .empty,

    fn n(self: *const Parser) usize {
        return self.s.len;
    }

    fn hasHost(self: *const Parser) bool {
        return self.host_text.first != null or self.ip4 != null or self.ip6 != null;
    }

    fn pushSeg(self: *Parser, first: ?usize, after: usize) Error!void {
        // a pathless SEGMENT BOTH from the abused scheme pointer is always set
        const f = first orelse after;
        try self.segs.append(self.a, .{ .first = f, .after = after });
    }

    // FixEmptyTrailSegment over the parse state
    fn fixEmptyTrailSegment(self: *Parser) void {
        if (!self.absolute_path and !self.hasHost() and self.segs.items.len == 1) {
            const s = self.segs.items[0];
            if (s.first.? == s.after.?) self.segs.clearRetainingCapacity();
        }
    }

    fn authority(self: *Parser, first: usize) Error!usize {
        if (first >= self.n()) {
            self.host_text = .{ .first = 0, .after = 0 };
            return self.n();
        }
        const c = self.s[first];
        if (c == '[') {
            const after_lit = try self.ipLit2(first + 1);
            self.host_text.first = first + 1;
            return self.authorityTwo(after_lit);
        }
        if (isPchar(c)) {
            self.user_info.first = first;
            return self.ownHostUserInfoNz(first);
        }
        self.host_text = .{ .first = 0, .after = 0 };
        return first;
    }

    fn authorityTwo(self: *Parser, first: usize) Error!usize {
        if (first >= self.n()) return self.n();
        if (self.s[first] == ':') {
            const after_port = self.portDigits(first + 1);
            self.port = .{ .first = first + 1, .after = after_port };
            return after_port;
        }
        return first;
    }

    fn hexZero(self: *Parser, first_in: usize) usize {
        var first = first_in;
        while (first < self.n() and isHexdig(self.s[first])) first += 1;
        return first;
    }

    fn hierPart(self: *Parser, first: usize) Error!usize {
        if (first >= self.n()) return self.n();
        const c = self.s[first];
        if (isPchar(c)) return self.pathRootless(first);
        if (c == '/') return self.partHelperTwo(first + 1);
        return first;
    }

    fn ipFutLoop(self: *Parser, first_in: usize) Error!usize {
        var first = first_in;
        while (first < self.n()) {
            const c = self.s[first];
            if (c == ':' or isSubDelim(c) or isUnreserved(c)) first += 1 else break;
        }
        if (first == first_in) return error.Syntax;
        return first;
    }

    fn ipFuture(self: *Parser, first: usize) Error!usize {
        if (first >= self.n()) return error.Syntax;
        if (self.n() - first < 2) return error.Syntax;
        if (!isHexdig(self.s[first + 1])) return error.Syntax;
        const after_hex = self.hexZero(first + 2);
        if (after_hex >= self.n()) return error.Syntax;
        if (self.s[after_hex] != '.') return error.Syntax;
        self.host_text.first = first;
        self.ip_future.first = first;
        const after_loop = try self.ipFutLoop(after_hex + 1);
        self.host_text.after = after_loop;
        self.ip_future.after = after_loop;
        return after_loop;
    }

    fn ipLit2(self: *Parser, first: usize) Error!usize {
        if (first >= self.n()) return error.Syntax;
        const c = self.s[first];
        if (c == 'v' or c == 'V') {
            const after = try self.ipFuture(first);
            if (after >= self.n()) return error.Syntax;
            if (self.s[after] != ']') return error.Syntax;
            return after + 1;
        }
        if (c == ':' or c == ']' or isHexdig(c)) {
            self.ip6 = @splat(0);
            return self.ipv6Address2(first);
        }
        return error.Syntax;
    }

    fn ipv6Address2(self: *Parser, first_in: usize) Error!usize {
        const s = self.s;
        const n_ = self.n();
        const data = &self.ip6.?;
        var first = first_in;
        var zipper_ever: bool = false;
        var quads_done: usize = 0;
        var digit_count: usize = 0;
        var digit_history: [4]u8 = undefined;
        var ip4_octets_done: usize = 0;
        var quads_after_zipper: [14]u8 = undefined;
        var quads_after_zipper_count: usize = 0;
        while (true) {
            if (first >= n_) return error.Syntax;
            if (ip4_octets_done > 0) {
                // the rest of an embedded ipv4 address
                while (true) {
                    const c = s[first];
                    switch (c) {
                        '0'...'9' => {
                            if (digit_count == 4) return error.Syntax;
                            digit_history[digit_count] = c - '0';
                            digit_count += 1;
                        },
                        '.' => {
                            if (ip4_octets_done == 4 or digit_count == 0 or digit_count == 4) return error.Syntax;
                            if (digit_count > 1 and digit_history[0] == 0) return error.Syntax;
                            if (digit_count == 3 and octetTooLarge(digit_history)) return error.Syntax;
                            data[16 - 4 + ip4_octets_done] = octetValue(digit_history, digit_count);
                            digit_count = 0;
                            ip4_octets_done += 1;
                        },
                        ']' => {
                            if (ip4_octets_done != 3 or digit_count == 0 or digit_count == 4) return error.Syntax;
                            if (digit_count > 1 and digit_history[0] == 0) return error.Syntax;
                            if (digit_count == 3 and octetTooLarge(digit_history)) return error.Syntax;
                            self.host_text.after = first;
                            const len = 2 * quads_after_zipper_count;
                            @memcpy(data[16 - 4 - len .. 16 - 4], quads_after_zipper[0..len]);
                            data[16 - 4 + 3] = octetValue(digit_history, digit_count);
                            return first + 1;
                        },
                        else => return error.Syntax,
                    }
                    first += 1;
                    if (first >= n_) return error.Syntax;
                }
            } else {
                var letter_among = false;
                var walking = true;
                while (walking) {
                    const c = s[first];
                    switch (c) {
                        'a'...'f', 'A'...'F' => {
                            letter_among = true;
                            if (digit_count == 4) return error.Syntax;
                            digit_history[digit_count] = hexdigToInt(c);
                            digit_count += 1;
                        },
                        '0'...'9' => {
                            if (digit_count == 4) return error.Syntax;
                            digit_history[digit_count] = c - '0';
                            digit_count += 1;
                        },
                        ':' => {
                            var set_zipper = false;
                            if (digit_count > 0) {
                                if (zipper_ever) {
                                    writeQuad(digit_history, digit_count, quads_after_zipper[2 * quads_after_zipper_count ..][0..2]);
                                    quads_after_zipper_count += 1;
                                } else {
                                    writeQuad(digit_history, digit_count, data[2 * quads_done ..][0..2]);
                                }
                                quads_done += 1;
                                digit_count = 0;
                            }
                            letter_among = false;
                            if (quads_done >= 8 - @as(usize, @intFromBool(zipper_ever))) return error.Syntax;
                            if (n_ - first < 2) return error.Syntax;
                            if (s[first + 1] == ':') {
                                const reset_offset = 2 * (quads_done + @as(usize, @intFromBool(digit_count > 0)));
                                first += 1;
                                if (zipper_ever) return error.Syntax;
                                @memset(data[reset_offset..], 0);
                                set_zipper = true;
                                if (n_ - first < 2) return error.Syntax;
                                if (s[first + 1] == ':') return error.Syntax;
                            } else if (quads_done == 0 or s[first + 1] == ']') {
                                return error.Syntax;
                            }
                            if (set_zipper) zipper_ever = true;
                        },
                        '.' => {
                            if (quads_done + @as(usize, @intFromBool(zipper_ever)) > 6 or (!zipper_ever and quads_done < 6) or letter_among or digit_count == 0 or digit_count == 4) return error.Syntax;
                            if (digit_count > 1 and digit_history[0] == 0) return error.Syntax;
                            if (digit_count == 3 and octetTooLarge(digit_history)) return error.Syntax;
                            data[16 - 4] = octetValue(digit_history, digit_count);
                            digit_count = 0;
                            ip4_octets_done = 1;
                            walking = false;
                        },
                        ']' => {
                            if (!zipper_ever and !(quads_done == 7 and digit_count > 0)) return error.Syntax;
                            if (digit_count > 0) {
                                if (zipper_ever) {
                                    if (quads_done >= 7) return error.Syntax;
                                    writeQuad(digit_history, digit_count, quads_after_zipper[2 * quads_after_zipper_count ..][0..2]);
                                    quads_after_zipper_count += 1;
                                } else {
                                    writeQuad(digit_history, digit_count, data[2 * quads_done ..][0..2]);
                                }
                            }
                            const len = 2 * quads_after_zipper_count;
                            @memcpy(data[16 - len ..], quads_after_zipper[0..len]);
                            self.host_text.after = first;
                            return first + 1;
                        },
                        else => return error.Syntax,
                    }
                    first += 1;
                    if (first >= n_) return error.Syntax;
                }
            }
        }
    }

    fn mustBeSegmentNzNc(self: *Parser, first_in: usize) Error!usize {
        var first = first_in;
        while (true) {
            if (first >= self.n()) {
                try self.pushSeg(self.scheme.first, first);
                self.scheme.first = null;
                return self.n();
            }
            const c = self.s[first];
            if (c == '%') {
                first = try self.pctEncoded(first);
            } else if (c == '@' or isSubDelim(c) or isUnreserved(c)) {
                first += 1;
            } else if (c == '/') {
                try self.pushSeg(self.scheme.first, first);
                self.scheme.first = null;
                const after_segment = try self.segment(first + 1);
                try self.pushSeg(first + 1, after_segment);
                const after_slash_segs = try self.zeroMoreSlashSegs(after_segment);
                return self.uriTail(after_slash_segs);
            } else {
                try self.pushSeg(self.scheme.first, first);
                self.scheme.first = null;
                return self.uriTail(first);
            }
        }
    }

    fn onExitOwnHost2(self: *Parser, first: usize) void {
        self.host_text.after = first;
        self.checkIp4();
    }

    // valid ipv4 or just a regname?
    fn checkIp4(self: *Parser) void {
        var out: [4]u8 = undefined;
        const f = self.host_text.first orelse return;
        const t = self.host_text.after orelse return;
        self.ip4 = if (t >= f and parseIpFourAddress(&out, self.s[f..t])) out else null;
    }

    fn ownHost(self: *Parser, first: usize) Error!usize {
        if (first >= self.n()) {
            self.host_text.after = self.n();
            return self.n();
        }
        if (self.s[first] == '[') {
            const after_lit = try self.ipLit2(first + 1);
            self.host_text.first = first + 1;
            return self.authorityTwo(after_lit);
        }
        return self.ownHost2(first);
    }

    fn ownHost2(self: *Parser, first_in: usize) Error!usize {
        var first = first_in;
        while (true) {
            if (first >= self.n()) {
                self.onExitOwnHost2(first);
                return self.n();
            }
            const c = self.s[first];
            if (c == '%' or isSubDelim(c) or isUnreserved(c)) {
                first = try self.pctSubUnres(first);
            } else {
                self.onExitOwnHost2(first);
                return self.authorityTwo(first);
            }
        }
    }

    fn onExitOwnHostUserInfo(self: *Parser, first: usize) void {
        self.host_text.first = self.user_info.first;
        self.user_info.first = null;
        self.host_text.after = first;
        self.checkIp4();
    }

    fn ownHostUserInfoNz(self: *Parser, first_in: usize) Error!usize {
        var first = first_in;
        while (first < self.n()) {
            const c = self.s[first];
            if (c == '%' or isSubDelim(c) or isUnreserved(c)) {
                first = try self.pctSubUnres(first);
            } else break;
        }
        if (first < self.n()) {
            switch (self.s[first]) {
                ':' => {
                    self.host_text.after = first;
                    self.port.first = first + 1;
                    return self.ownPortUserInfo(first + 1);
                },
                '@' => {
                    self.user_info.after = first;
                    self.host_text.first = first + 1;
                    return self.ownHost(first + 1);
                },
                else => {},
            }
        }
        if (first == first_in) return error.Syntax;
        self.onExitOwnHostUserInfo(first);
        return first;
    }

    fn onExitOwnPortUserInfo(self: *Parser, first: usize) void {
        self.host_text.first = self.user_info.first;
        self.user_info.first = null;
        self.port.after = first;
        self.checkIp4();
    }

    fn ownPortUserInfo(self: *Parser, first_in: usize) Error!usize {
        var first = first_in;
        while (true) {
            if (first >= self.n()) {
                self.onExitOwnPortUserInfo(first);
                return self.n();
            }
            const c = self.s[first];
            if (isSubDelim(c) or c == '-' or c == '.' or c == '_' or c == '~' or c == ':' or isAlpha(c)) {
                self.host_text.after = null;
                self.port.first = null;
                return self.ownUserInfo(first + 1);
            } else if (isDigit(c)) {
                first += 1;
            } else if (c == '%') {
                self.port.first = null;
                const after_pct = try self.pctEncoded(first);
                return self.ownUserInfo(after_pct);
            } else if (c == '@') {
                self.host_text.after = null;
                self.port.first = null;
                self.user_info.after = first;
                self.host_text.first = first + 1;
                return self.ownHost(first + 1);
            } else {
                self.onExitOwnPortUserInfo(first);
                return first;
            }
        }
    }

    fn ownUserInfo(self: *Parser, first_in: usize) Error!usize {
        var first = first_in;
        while (true) {
            if (first >= self.n()) return error.Syntax;
            const c = self.s[first];
            if (c == '%' or isSubDelim(c) or isUnreserved(c)) {
                first = try self.pctSubUnres(first);
            } else if (c == ':') {
                first += 1;
            } else if (c == '@') {
                self.user_info.after = first;
                self.host_text.first = first + 1;
                return self.ownHost(first + 1);
            } else return error.Syntax;
        }
    }

    fn partHelperTwo(self: *Parser, first: usize) Error!usize {
        if (first >= self.n()) {
            self.absolute_path = true;
            return self.n();
        }
        if (self.s[first] == '/') {
            const after_authority = try self.authority(first + 1);
            const after_path = try self.pathAbsEmpty(after_authority);
            self.fixEmptyTrailSegment();
            return after_path;
        }
        self.absolute_path = true;
        return self.pathAbsNoLeadSlash(first);
    }

    fn pathAbsEmpty(self: *Parser, first_in: usize) Error!usize {
        var first = first_in;
        while (first < self.n() and self.s[first] == '/') {
            const after_segment = try self.segment(first + 1);
            try self.pushSeg(first + 1, after_segment);
            first = after_segment;
        }
        return if (first >= self.n()) self.n() else first;
    }

    fn pathAbsNoLeadSlash(self: *Parser, first: usize) Error!usize {
        if (first >= self.n()) return self.n();
        if (isPchar(self.s[first])) {
            const after = try self.segmentNz(first);
            try self.pushSeg(first, after);
            return self.zeroMoreSlashSegs(after);
        }
        return first;
    }

    fn pathRootless(self: *Parser, first: usize) Error!usize {
        const after = try self.segmentNz(first);
        try self.pushSeg(first, after);
        return self.zeroMoreSlashSegs(after);
    }

    fn pchar(self: *Parser, first: usize) Error!usize {
        if (first >= self.n()) return error.Syntax;
        const c = self.s[first];
        if (c == '%') return self.pctEncoded(first);
        if (isPcharNoPct(c)) return first + 1;
        return error.Syntax;
    }

    fn pctEncoded(self: *Parser, first: usize) Error!usize {
        if (first >= self.n()) return error.Syntax;
        if (self.n() - first < 2) return error.Syntax;
        if (!isHexdig(self.s[first + 1])) return error.Syntax;
        if (self.n() - first < 3) return error.Syntax;
        if (!isHexdig(self.s[first + 2])) return error.Syntax;
        return first + 3;
    }

    fn pctSubUnres(self: *Parser, first: usize) Error!usize {
        if (first >= self.n()) return error.Syntax;
        const c = self.s[first];
        if (c == '%') return self.pctEncoded(first);
        if (isSubDelim(c) or isUnreserved(c)) return first + 1;
        return error.Syntax;
    }

    fn portDigits(self: *Parser, first_in: usize) usize {
        var first = first_in;
        while (first < self.n() and isDigit(self.s[first])) first += 1;
        return first;
    }

    fn queryFrag(self: *Parser, first_in: usize) Error!usize {
        var first = first_in;
        while (first < self.n()) {
            const c = self.s[first];
            if (isPchar(c)) {
                first = try self.pchar(first);
            } else if (c == '/' or c == '?') {
                first += 1;
            } else return first;
        }
        return self.n();
    }

    fn segment(self: *Parser, first_in: usize) Error!usize {
        var first = first_in;
        while (first < self.n()) {
            if (isPchar(self.s[first])) first = try self.pchar(first) else return first;
        }
        return self.n();
    }

    fn segmentNz(self: *Parser, first: usize) Error!usize {
        const after = try self.pchar(first);
        return self.segment(after);
    }

    fn segmentNzNcOrScheme2(self: *Parser, first_in: usize) Error!usize {
        var first = first_in;
        while (true) {
            if (first >= self.n()) {
                try self.pushSeg(self.scheme.first, first);
                self.scheme.first = null;
                return self.n();
            }
            const c = self.s[first];
            switch (c) {
                '.', '+', '-', 'a'...'z', 'A'...'Z', '0'...'9' => first += 1,
                '%' => {
                    const after = try self.pctEncoded(first);
                    return self.mustBeSegmentNzNc(after);
                },
                '!', '$', '&', '(', ')', '*', ',', ';', '@', '_', '~', '=', '\'' => return self.mustBeSegmentNzNc(first + 1),
                '/' => {
                    const after_segment = try self.segment(first + 1);
                    try self.pushSeg(self.scheme.first, first);
                    self.scheme.first = null;
                    try self.pushSeg(first + 1, after_segment);
                    const after_slash_segs = try self.zeroMoreSlashSegs(after_segment);
                    return self.uriTail(after_slash_segs);
                },
                ':' => {
                    const after_hier = self.hierPart(first + 1);
                    self.scheme.after = first;
                    return self.uriTail(try after_hier);
                },
                else => {
                    try self.pushSeg(self.scheme.first, first);
                    self.scheme.first = null;
                    return self.uriTail(first);
                },
            }
        }
    }

    fn uriReference(self: *Parser, first: usize) Error!usize {
        if (first >= self.n()) return self.n();
        const c = self.s[first];
        if (isAlpha(c)) {
            self.scheme.first = first;
            return self.segmentNzNcOrScheme2(first + 1);
        }
        if (isDigit(c) or isSubDelim(c) or c == '.' or c == '_' or c == '~' or c == '-' or c == '@') {
            // segment begin, abusing the scheme pointer as uriparser does
            self.scheme.first = first;
            return self.mustBeSegmentNzNc(first + 1);
        }
        if (c == '%') {
            const after = try self.pctEncoded(first);
            self.scheme.first = first;
            return self.mustBeSegmentNzNc(after);
        }
        if (c == '/') {
            const after = try self.partHelperTwo(first + 1);
            return self.uriTail(after);
        }
        return self.uriTail(first);
    }

    fn uriTail(self: *Parser, first: usize) Error!usize {
        if (first >= self.n()) return self.n();
        switch (self.s[first]) {
            '#' => {
                const after = try self.queryFrag(first + 1);
                self.fragment = .{ .first = first + 1, .after = after };
                return after;
            },
            '?' => {
                const after = try self.queryFrag(first + 1);
                self.query = .{ .first = first + 1, .after = after };
                return self.uriTailTwo(after);
            },
            else => return first,
        }
    }

    fn uriTailTwo(self: *Parser, first: usize) Error!usize {
        if (first >= self.n()) return self.n();
        if (self.s[first] == '#') {
            const after = try self.queryFrag(first + 1);
            self.fragment = .{ .first = first + 1, .after = after };
            return after;
        }
        return first;
    }

    fn zeroMoreSlashSegs(self: *Parser, first: usize) Error!usize {
        return self.pathAbsEmpty(first);
    }

    fn take(self: *Parser, r: Range) Error!?[]u8 {
        if (!r.set()) return null;
        return try self.a.dupe(u8, self.s[r.first.?..r.after.?]);
    }

    fn toUri(self: *Parser) Error!Uri {
        var out = Uri{ .absolute_path = self.absolute_path };
        errdefer out.deinit(self.a);
        out.scheme = try self.take(self.scheme);
        out.user_info = try self.take(self.user_info);
        out.host_text = try self.take(self.host_text);
        if (self.ip4) |v| {
            out.host_data = .{ .ip4 = v };
        } else if (self.ip6) |v| {
            out.host_data = .{ .ip6 = v };
        } else if (self.ip_future.set()) {
            out.host_data = .ip_future;
        }
        out.port_text = try self.take(self.port);
        try out.segments.ensureTotalCapacity(self.a, self.segs.items.len);
        for (self.segs.items) |r| out.segments.appendAssumeCapacity((try self.take(r)).?);
        out.query = try self.take(self.query);
        out.fragment = try self.take(self.fragment);
        return out;
    }
};

fn octetTooLarge(d: [4]u8) bool {
    return @as(u32, d[0]) * 100 + @as(u32, d[1]) * 10 + d[2] > 255;
}

fn octetValue(d: [4]u8, count: usize) u8 {
    return switch (count) {
        1 => d[0],
        2 => 10 * d[0] + d[1],
        else => @intCast(@as(u32, d[0]) * 100 + @as(u32, d[1]) * 10 + d[2]),
    };
}

fn writeQuad(d: [4]u8, count: usize, out: *[2]u8) void {
    switch (count) {
        1 => out.* = .{ 0, d[0] },
        2 => out.* = .{ 0, 16 * d[0] + d[1] },
        3 => out.* = .{ d[0], 16 * d[1] + d[2] },
        else => out.* = .{ 16 * d[0] + d[1], 16 * d[2] + d[3] },
    }
}

// uriParseSingleUriExMmA followed by uriMakeOwnerMmA
pub fn parse(a: Allocator, text: []const u8) Error!Uri {
    var p = Parser{ .s = text, .a = a };
    defer p.segs.deinit(a);
    const after = try p.uriReference(0);
    if (after != text.len) return error.Syntax;
    return p.toUri();
}

// ---- ipv4 (UriIp4.c) ----

// the dec-octet grammar, greedy as uriparser's state machine
fn decOctet(s: []const u8, first: usize, value: *u8) ?usize {
    if (first >= s.len) return null;
    const c = s[first];
    if (c == '0') {
        value.* = 0;
        return first + 1;
    }
    if (!isDigit(c)) return null;
    var v: u32 = c - '0';
    var i = first + 1;
    if (c == '1') {
        if (i < s.len and isDigit(s[i])) {
            v = v * 10 + (s[i] - '0');
            i += 1;
            if (i < s.len and isDigit(s[i])) {
                v = v * 10 + (s[i] - '0');
                i += 1;
            }
        }
    } else if (c == '2') {
        if (i < s.len) {
            const d = s[i];
            if (d >= '0' and d <= '4') {
                v = v * 10 + (d - '0');
                i += 1;
                if (i < s.len and isDigit(s[i])) {
                    v = v * 10 + (s[i] - '0');
                    i += 1;
                }
            } else if (d == '5') {
                v = 25;
                i += 1;
                if (i < s.len and s[i] >= '0' and s[i] <= '5') {
                    v = v * 10 + (s[i] - '0');
                    i += 1;
                }
            } else if (isDigit(d)) {
                v = v * 10 + (d - '0');
                i += 1;
            }
        }
    } else {
        if (i < s.len and isDigit(s[i])) {
            v = v * 10 + (s[i] - '0');
            i += 1;
        }
    }
    value.* = @intCast(v);
    return i;
}

fn parseIpFourAddress(out: *[4]u8, s: []const u8) bool {
    if (s.len == 0) return false;
    var pos: usize = 0;
    for (0..4) |k| {
        const after = decOctet(s, pos, &out[k]) orelse return false;
        if (k < 3) {
            if (after >= s.len or s[after] != '.') return false;
            pos = after + 1;
        } else if (after != s.len) return false;
    }
    return true;
}

// ---- common path helpers (UriCommon.c) ----

fn removeDotSegments(a: Allocator, uri: *Uri, relative: bool) Error!void {
    const segs = &uri.segments;
    if (segs.items.len == 0) return;
    var i: usize = 0;
    while (i < segs.items.len) {
        var remove = false;
        const seg = segs.items[i];
        if (seg.len == 1 and seg[0] == '.') {
            remove = true;
            if (i == 0 and segs.items.len > 1) {
                const next = segs.items[1];
                if (next.len == 0 and !uri.hasHost()) {
                    // "/.//" must keep its dot
                    remove = false;
                } else if (relative and std.mem.indexOfScalar(u8, next, ':') != null) {
                    // "./withcolon:" too
                    remove = false;
                }
            }
            if (remove) {
                if (i + 1 < segs.items.len) {
                    a.free(segs.orderedRemove(i));
                    continue;
                }
                // the last segment
                if (i == 0 and !uri.hasHost()) {
                    a.free(segs.orderedRemove(0));
                } else {
                    // an empty segment stands for the trailing slash
                    a.free(segs.items[i]);
                    segs.items[i] = try a.alloc(u8, 0);
                }
                return;
            }
        } else if (seg.len == 2 and seg[0] == '.' and seg[1] == '.') {
            remove = true;
            if (relative) {
                if (i == 0) {
                    remove = false;
                } else {
                    const prev = segs.items[i - 1];
                    // keep "a/../../b" from becoming "b"
                    if (prev.len == 2 and prev[0] == '.' and prev[1] == '.') remove = false;
                }
            }
            if (remove) {
                if (i > 0) {
                    if (i > 1) {
                        const was_last = i + 1 == segs.items.len;
                        a.free(segs.orderedRemove(i));
                        a.free(segs.orderedRemove(i - 1));
                        if (was_last) {
                            const empty = try a.alloc(u8, 0);
                            segs.append(a, empty) catch |e| {
                                a.free(empty);
                                return e;
                            };
                            return;
                        }
                        i -= 1;
                        continue;
                    }
                    // prev is the first segment
                    if (i + 1 < segs.items.len) {
                        a.free(segs.orderedRemove(1));
                        a.free(segs.orderedRemove(0));
                        i = 0;
                        continue;
                    }
                    a.free(segs.orderedRemove(1));
                    a.free(segs.items[0]);
                    segs.items[0] = try a.alloc(u8, 0);
                    return;
                }
                // the first segment
                if (segs.items.len > 1) {
                    a.free(segs.orderedRemove(0));
                    continue;
                }
                if (uri.absolute_path) {
                    a.free(segs.orderedRemove(0));
                } else {
                    a.free(segs.items[0]);
                    segs.items[0] = try a.alloc(u8, 0);
                }
                return;
            }
        }
        if (!remove) i += 1;
    }
}

fn fixEmptyTrailSegment(a: Allocator, uri: *Uri) void {
    if (!uri.absolute_path and !uri.hasHost() and uri.segments.items.len == 1 and uri.segments.items[0].len == 0) {
        freePath(a, uri);
    }
}

fn prependDotSegment(a: Allocator, uri: *Uri) Error!void {
    const dot = try a.dupe(u8, ".");
    uri.segments.insert(a, 0, dot) catch |e| {
        a.free(dot);
        return e;
    };
}

// a path whose first segment is empty would read as an authority
fn fixAmbiguity(a: Allocator, uri: *Uri) Error!void {
    const segs = uri.segments.items;
    const case1 = uri.absolute_path and segs.len > 0 and segs[0].len == 0;
    const case2 = !uri.absolute_path and segs.len > 1 and segs[0].len == 0 and segs[1].len == 0;
    if (case1 or case2) try prependDotSegment(a, uri);
}

// a first segment with a colon would read as a scheme
fn fixPathNoScheme(a: Allocator, uri: *Uri) Error!void {
    if (uri.absolute_path or uri.segments.items.len == 0 or uri.scheme != null or uri.hasHost()) return;
    if (std.mem.indexOfScalar(u8, uri.segments.items[0], ':') == null) return;
    try prependDotSegment(a, uri);
}

fn ensureThatPathIsNotMistakenForHost(a: Allocator, uri: *Uri) Error!void {
    const segs = uri.segments.items;
    if (uri.hasHost() or !uri.absolute_path or segs.len < 2 or segs[0].len != 0) return;
    try prependDotSegment(a, uri);
}

fn copyAuthority(a: Allocator, dest: *Uri, src: *const Uri) Error!void {
    dest.user_info = try dupOpt(a, src.user_info);
    dest.host_text = try dupOpt(a, src.host_text);
    dest.host_data = src.host_data;
    dest.port_text = try dupOpt(a, src.port_text);
}

fn copyPath(a: Allocator, dest: *Uri, src: *const Uri) Error!void {
    freePath(a, dest);
    try dest.segments.ensureTotalCapacity(a, src.segments.items.len);
    for (src.segments.items) |s| dest.segments.appendAssumeCapacity(try a.dupe(u8, s));
    dest.absolute_path = src.absolute_path;
}

// ---- reference resolution (UriResolve.c) ----

// the last segment of the base ("" for a trailing slash) is replaced
fn mergePath(a: Allocator, dest: *Uri, rel: *const Uri) Error!void {
    const rs = rel.segments.items;
    if (rs.len == 0) return;
    if (dest.segments.items.len == 0) try dest.segments.append(a, try a.alloc(u8, 0));
    const last = &dest.segments.items[dest.segments.items.len - 1];
    const first = try a.dupe(u8, rs[0]);
    a.free(last.*);
    last.* = first;
    for (rs[1..]) |s| {
        const dup = try a.dupe(u8, s);
        dest.segments.append(a, dup) catch |e| {
            a.free(dup);
            return e;
        };
    }
}

fn resolveAbsolutePathFlag(a: Allocator, uri: *Uri) Error!void {
    if (uri.hasHost() and uri.absolute_path) {
        if (uri.segments.items.len == 0) try uri.segments.append(a, try a.alloc(u8, 0));
        uri.absolute_path = false;
    }
}

// uriAddBaseUriExMmA with URI_RESOLVE_STRICTLY
pub fn addBase(a: Allocator, rel: *const Uri, base: *const Uri) Error!Uri {
    if (base.scheme == null) return error.AddBaseRelBase;
    var dest = Uri{};
    errdefer dest.deinit(a);
    if (rel.scheme != null) {
        dest.scheme = try dupOpt(a, rel.scheme);
        try copyAuthority(a, &dest, rel);
        try copyPath(a, &dest, rel);
        try removeDotSegments(a, &dest, false);
        dest.query = try dupOpt(a, rel.query);
    } else {
        if (rel.hasHost()) {
            try copyAuthority(a, &dest, rel);
            try copyPath(a, &dest, rel);
            try removeDotSegments(a, &dest, false);
            dest.query = try dupOpt(a, rel.query);
        } else {
            try copyAuthority(a, &dest, base);
            if (rel.segments.items.len == 0 and !rel.absolute_path) {
                try copyPath(a, &dest, base);
                dest.query = try dupOpt(a, if (rel.query != null) rel.query else base.query);
            } else {
                if (rel.absolute_path) {
                    try copyPath(a, &dest, rel);
                    try resolveAbsolutePathFlag(a, &dest);
                    try removeDotSegments(a, &dest, false);
                } else {
                    try copyPath(a, &dest, base);
                    try mergePath(a, &dest, rel);
                    try removeDotSegments(a, &dest, false);
                    try fixAmbiguity(a, &dest);
                }
                dest.query = try dupOpt(a, rel.query);
            }
            fixEmptyTrailSegment(a, &dest);
        }
        dest.scheme = try dupOpt(a, base.scheme);
    }
    dest.fragment = try dupOpt(a, rel.fragment);
    return dest;
}

// ---- normalization (UriNormalize.c) ----

fn containsUppercase(s: ?[]const u8) bool {
    const v = s orelse return false;
    for (v) |c| if (c >= 'A' and c <= 'Z') return true;
    return false;
}

// lowercase percent hex or a percent-encoded unreserved character
fn containsUglyPercentEncoding(s: ?[]const u8) bool {
    const v = s orelse return false;
    var i: usize = 0;
    while (i + 2 < v.len) : (i += 1) {
        if (v[i] != '%') continue;
        if ((v[i + 1] >= 'a' and v[i + 1] <= 'f') or (v[i + 2] >= 'a' and v[i + 2] <= 'f')) return true;
        if (isUnreserved(16 * hexdigToInt(v[i + 1]) + hexdigToInt(v[i + 2]))) return true;
    }
    return false;
}

fn lowercaseInplace(s: []u8) void {
    for (s) |*c| if (c.* >= 'A' and c.* <= 'Z') {
        c.* += 'a' - 'A';
    };
}

fn lowercaseInplaceExceptPercentEncoding(s: []u8) void {
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] >= 'A' and s[i] <= 'Z') {
            s[i] += 'a' - 'A';
        } else if (s[i] == '%') {
            if (i + 3 >= s.len) return;
            i += 2;
        }
    }
}

// decodes percent-encoded unreserved characters and uppercases the rest;
// the last two characters are copied as they are
fn fixPercentEncoding(s: []u8) usize {
    var w: usize = 0;
    var i: usize = 0;
    while (i + 2 < s.len) : (i += 1) {
        if (s[i] != '%') {
            s[w] = s[i];
            w += 1;
            continue;
        }
        const left = hexdigToInt(s[i + 1]);
        const right = hexdigToInt(s[i + 2]);
        const code = 16 * left + right;
        if (isUnreserved(code)) {
            s[w] = code;
            w += 1;
        } else {
            s[w] = '%';
            s[w + 1] = hexToLetter(left, true);
            s[w + 2] = hexToLetter(right, true);
            w += 3;
        }
        i += 2;
    }
    while (i < s.len) : (i += 1) {
        s[w] = s[i];
        w += 1;
    }
    return w;
}

fn fixPercentEncodingOwned(a: Allocator, slot: *[]u8) Error!void {
    const len = fixPercentEncoding(slot.*);
    if (len == slot.len) return;
    const shorter = try a.dupe(u8, slot.*[0..len]);
    a.free(slot.*);
    slot.* = shorter;
}

pub fn normalizationMaskRequired(uri: *const Uri) u32 {
    var mask: u32 = 0;
    if (containsUppercase(uri.scheme)) mask |= normalize_scheme;
    if (containsUppercase(uri.host_text) or containsUglyPercentEncoding(uri.host_text)) mask |= normalize_host;
    if (uri.port_text) |p| {
        if (p.len > 1 and p[0] == '0') mask |= normalize_port;
    }
    if (containsUglyPercentEncoding(uri.user_info)) mask |= normalize_user_info;
    for (uri.segments.items) |s| {
        if (s.len == 0) continue;
        if ((s.len == 1 and s[0] == '.') or (s.len == 2 and s[0] == '.' and s[1] == '.') or containsUglyPercentEncoding(s)) {
            mask |= normalize_path;
            break;
        }
    }
    if (containsUglyPercentEncoding(uri.query)) mask |= normalize_query;
    if (containsUglyPercentEncoding(uri.fragment)) mask |= normalize_fragment;
    return mask;
}

pub fn normalize(a: Allocator, uri: *Uri, mask: u32) Error!void {
    if (mask == 0) return;
    if (mask & normalize_scheme != 0) {
        if (uri.scheme) |s| lowercaseInplace(s);
    }
    if (mask & normalize_host != 0) {
        if (uri.host_data == .ip_future) {
            if (uri.host_text) |h| lowercaseInplace(h);
        } else if (uri.host_text != null and uri.host_data != .ip4) {
            try fixPercentEncodingOwned(a, &uri.host_text.?);
            lowercaseInplaceExceptPercentEncoding(uri.host_text.?);
        }
    }
    if (mask & normalize_port != 0) {
        if (uri.port_text) |p| {
            if (p.len > 0) {
                var k: usize = 0;
                while (k < p.len and p[k] == '0') k += 1;
                if (k == p.len) k -= 1;
                if (k > 0) {
                    const shorter = try a.dupe(u8, p[k..]);
                    a.free(p);
                    uri.port_text = shorter;
                }
            }
        }
    }
    if (mask & normalize_user_info != 0) {
        if (uri.user_info != null) try fixPercentEncodingOwned(a, &uri.user_info.?);
    }
    if (mask & normalize_path != 0) {
        const relative = uri.scheme == null and !uri.absolute_path;
        for (uri.segments.items) |*s| try fixPercentEncodingOwned(a, s);
        try removeDotSegments(a, uri, relative);
        fixEmptyTrailSegment(a, uri);
    }
    if (mask & normalize_query != 0) {
        if (uri.query != null) try fixPercentEncodingOwned(a, &uri.query.?);
    }
    if (mask & normalize_fragment != 0) {
        if (uri.fragment != null) try fixPercentEncodingOwned(a, &uri.fragment.?);
    }
}

// ---- recomposition (UriRecompose.c) ----

pub fn toString(a: Allocator, uri: *const Uri) Error![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(a);
    if (uri.scheme) |s| {
        try out.appendSlice(a, s);
        try out.append(a, ':');
    }
    const has_host = uri.hasHost();
    if (has_host) {
        try out.appendSlice(a, "//");
        if (uri.user_info) |u| {
            try out.appendSlice(a, u);
            try out.append(a, '@');
        }
        switch (uri.host_data) {
            .ip4 => |b| {
                for (b, 0..) |v, i| {
                    var buf: [3]u8 = undefined;
                    try out.appendSlice(a, std.fmt.bufPrint(&buf, "{d}", .{v}) catch unreachable);
                    if (i < 3) try out.append(a, '.');
                }
            },
            .ip6 => |b| {
                // uriparser writes the binary form, every quad in full
                try out.append(a, '[');
                for (b, 0..) |v, i| {
                    try out.append(a, hexToLetter(v / 16, false));
                    try out.append(a, hexToLetter(v % 16, false));
                    if (i & 1 == 1 and i < 15) try out.append(a, ':');
                }
                try out.append(a, ']');
            },
            .ip_future => {
                try out.append(a, '[');
                try out.appendSlice(a, uri.host_text orelse "");
                try out.append(a, ']');
            },
            .none => if (uri.host_text) |h| try out.appendSlice(a, h),
        }
        if (uri.port_text) |p| {
            try out.append(a, ':');
            try out.appendSlice(a, p);
        }
    }
    if (uri.absolute_path or (uri.segments.items.len > 0 and has_host)) try out.append(a, '/');
    for (uri.segments.items, 0..) |s, i| {
        try out.appendSlice(a, s);
        if (i + 1 < uri.segments.items.len) try out.append(a, '/');
    }
    if (uri.query) |q| {
        try out.append(a, '?');
        try out.appendSlice(a, q);
    }
    if (uri.fragment) |f| {
        try out.append(a, '#');
        try out.appendSlice(a, f);
    }
    return out.toOwnedSlice(a);
}

// ---- well-formedness checks (UriSet*.c) ----

pub fn isWellFormedScheme(s: []const u8) bool {
    if (s.len == 0 or !isAlpha(s[0])) return false;
    for (s[1..]) |c| {
        if (!(isAlpha(c) or isDigit(c) or c == '+' or c == '-' or c == '.')) return false;
    }
    return true;
}

// the shared loop: the allowed characters plus valid percent-encodings
fn wellFormedWith(s: []const u8, comptime allowed: fn (u8) bool) bool {
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (c == '%') {
            if (s.len - i < 3) return false;
            if (!isHexdig(s[i + 1]) or !isHexdig(s[i + 2])) return false;
            i += 2;
        } else if (!allowed(c)) return false;
    }
    return true;
}

fn userInfoChar(c: u8) bool {
    return isUnreserved(c) or isSubDelim(c) or c == ':';
}

fn regNameChar(c: u8) bool {
    return isUnreserved(c) or isSubDelim(c);
}

fn queryChar(c: u8) bool {
    return isPcharNoPct(c) or c == '/' or c == '?';
}

fn pathChar(c: u8) bool {
    return isPcharNoPct(c) or c == '/';
}

pub fn isWellFormedUserInfo(s: []const u8) bool {
    return wellFormedWith(s, userInfoChar);
}

pub fn isWellFormedHostRegName(s: []const u8) bool {
    return wellFormedWith(s, regNameChar);
}

pub fn isWellFormedQuery(s: []const u8) bool {
    return wellFormedWith(s, queryChar);
}

pub fn isWellFormedFragment(s: []const u8) bool {
    return wellFormedWith(s, queryChar);
}

pub fn isWellFormedPath(s: []const u8, has_host: bool) bool {
    if (has_host and (s.len == 0 or s[0] != '/')) return false;
    return wellFormedWith(s, pathChar);
}

pub fn isWellFormedPort(s: []const u8) bool {
    for (s) |c| if (!isDigit(c)) return false;
    return true;
}

pub fn isWellFormedHostIp4(s: []const u8) bool {
    var out: [4]u8 = undefined;
    return parseIpFourAddress(&out, s);
}

// ParseIpSixAddressMm: the text parsed as the host of "//[...]"
fn parseIpSix(s: []const u8) ?[16]u8 {
    if (s.len > 0 and (s[0] == 'v' or s[0] == 'V')) return null;
    // 8 full quads plus 7 colons
    if (s.len > 8 * 4 + 7) return null;
    var buf: [3 + 39 + 1]u8 = undefined;
    @memcpy(buf[0..3], "//[");
    @memcpy(buf[3 .. 3 + s.len], s);
    buf[3 + s.len] = ']';
    var gpa_buf: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&gpa_buf);
    var uri = parse(fba.allocator(), buf[0 .. 4 + s.len]) catch return null;
    defer uri.deinit(fba.allocator());
    return switch (uri.host_data) {
        .ip6 => |b| b,
        else => null,
    };
}

pub fn isWellFormedHostIp6(s: []const u8) bool {
    return parseIpSix(s) != null;
}

pub fn isWellFormedHostIpFuture(s: []const u8) bool {
    if (s.len > 0 and s[0] != 'v' and s[0] != 'V') return false;
    const a = std.heap.page_allocator;
    const candidate = std.mem.concat(a, u8, &.{ "//[", s, "]" }) catch return false;
    defer a.free(candidate);
    var uri = parse(a, candidate) catch return false;
    defer uri.deinit(a);
    return uri.host_data == .ip_future;
}

// ---- setters ----

pub fn setScheme(a: Allocator, uri: *Uri, v: ?[]const u8) Error!void {
    if (v) |s| if (!isWellFormedScheme(s)) return error.Syntax;
    try replace(a, &uri.scheme, v);
    // without a scheme, a colon in the first segment needs disambiguation
    if (v == null) try fixPathNoScheme(a, uri);
}

pub fn setUserInfo(a: Allocator, uri: *Uri, v: ?[]const u8) Error!void {
    if (v) |s| {
        if (!uri.hasHost()) return error.SetUserInfoHostNotSet;
        if (!isWellFormedUserInfo(s)) return error.Syntax;
    }
    try replace(a, &uri.user_info, v);
}

pub fn setPortText(a: Allocator, uri: *Uri, v: ?[]const u8) Error!void {
    if (v) |s| {
        if (!uri.hasHost()) return error.SetPortHostNotSet;
        if (!isWellFormedPort(s)) return error.Syntax;
    }
    try replace(a, &uri.port_text, v);
}

pub fn setQuery(a: Allocator, uri: *Uri, v: ?[]const u8) Error!void {
    if (v) |s| if (!isWellFormedQuery(s)) return error.Syntax;
    try replace(a, &uri.query, v);
}

pub fn setFragment(a: Allocator, uri: *Uri, v: ?[]const u8) Error!void {
    if (v) |s| if (!isWellFormedFragment(s)) return error.Syntax;
    try replace(a, &uri.fragment, v);
}

pub fn setPath(a: Allocator, uri: *Uri, v: ?[]const u8) Error!void {
    if (v) |s| if (!isWellFormedPath(s, uri.hasHost())) return error.Syntax;
    freePath(a, uri);
    uri.absolute_path = false;
    const text = v orelse return;
    var p = text;
    if (uri.hasHost()) {
        // the leading slash is the separator after the authority
        p = text[1..];
    } else if (p.len == 0) {
        return;
    }
    // parse the path as the one of "///..." to get uriparser's segments
    const candidate = try std.mem.concat(a, u8, &.{ "///", p });
    defer a.free(candidate);
    var temp = try parse(a, candidate);
    defer temp.deinit(a);
    std.mem.swap(std.ArrayListUnmanaged([]u8), &uri.segments, &temp.segments);
    uri.absolute_path = false;
    // without a host a leading empty segment is the absolute path flag
    if (!uri.hasHost() and uri.segments.items.len > 0 and uri.segments.items[0].len == 0) {
        a.free(uri.segments.orderedRemove(0));
        uri.absolute_path = true;
    }
    try fixPathNoScheme(a, uri);
    try ensureThatPathIsNotMistakenForHost(a, uri);
}

const HostType = enum { ip4, ip6, ip_future, reg_name };

pub fn setHostAuto(a: Allocator, uri: *Uri, v: ?[]const u8) Error!void {
    const s = v orelse return internalSetHost(a, uri, .reg_name, null);
    if (s.len == 0) return internalSetHost(a, uri, .reg_name, s);
    if (s[0] == '[') {
        if (s.len < 2 or s[s.len - 1] != ']') return error.Syntax;
        const inner = s[1 .. s.len - 1];
        if (inner.len == 0) return error.Syntax;
        const t: HostType = if (inner[0] == 'v' or inner[0] == 'V') .ip_future else .ip6;
        return internalSetHost(a, uri, t, inner);
    }
    if (isWellFormedHostIp4(s)) return internalSetHost(a, uri, .ip4, s);
    return internalSetHost(a, uri, .reg_name, s);
}

fn internalSetHost(a: Allocator, uri: *Uri, t: HostType, v: ?[]const u8) Error!void {
    var ip6: [16]u8 = undefined;
    if (v) |s| {
        switch (t) {
            .ip4 => if (!isWellFormedHostIp4(s)) return error.Syntax,
            .ip6 => ip6 = parseIpSix(s) orelse return error.Syntax,
            .ip_future => if (!isWellFormedHostIpFuture(s)) return error.Syntax,
            .reg_name => if (!isWellFormedHostRegName(s)) return error.Syntax,
        }
    } else {
        // no userinfo or port without a host
        if (uri.user_info != null) return error.SetHostUserInfoSet;
        if (uri.port_text != null) return error.SetHostPortSet;
    }
    const had_host = uri.hasHost();
    const new = try dupOpt(a, v);
    freeOpt(a, uri.host_text);
    uri.host_text = null;
    uri.host_data = .none;
    if (new == null) {
        if (had_host) {
            if (uri.segments.items.len > 0) uri.absolute_path = true;
            try ensureThatPathIsNotMistakenForHost(a, uri);
        }
        return;
    }
    uri.host_text = new;
    // always false for uris with a host
    uri.absolute_path = false;
    switch (t) {
        .ip4 => {
            var b: [4]u8 = undefined;
            _ = parseIpFourAddress(&b, new.?);
            uri.host_data = .{ .ip4 = b };
        },
        .ip6 => uri.host_data = .{ .ip6 = ip6 },
        .ip_future => uri.host_data = .ip_future,
        .reg_name => {},
    }
}

// ---- tests ----

const testing = std.testing;

fn roundTrip(text: []const u8) ![]u8 {
    var u = try parse(testing.allocator, text);
    defer u.deinit(testing.allocator);
    return toString(testing.allocator, &u);
}

fn expectRoundTrip(text: []const u8, expected: []const u8) !void {
    const s = try roundTrip(text);
    defer testing.allocator.free(s);
    try testing.expectEqualStrings(expected, s);
}

fn normalized(text: []const u8) ![]u8 {
    var u = try parse(testing.allocator, text);
    defer u.deinit(testing.allocator);
    try normalize(testing.allocator, &u, normalizationMaskRequired(&u));
    return toString(testing.allocator, &u);
}

fn expectNormalized(text: []const u8, expected: []const u8) !void {
    const s = try normalized(text);
    defer testing.allocator.free(s);
    try testing.expectEqualStrings(expected, s);
}

fn expectResolved(base: []const u8, rel: []const u8, expected: []const u8) !void {
    const a = testing.allocator;
    var b = try parse(a, base);
    defer b.deinit(a);
    var r = try parse(a, rel);
    defer r.deinit(a);
    var res = try addBase(a, &r, &b);
    defer res.deinit(a);
    const s = try toString(a, &res);
    defer a.free(s);
    try testing.expectEqualStrings(expected, s);
}

test "parse components" {
    const a = testing.allocator;
    var u = try parse(a, "https://user:pass@EXAMPLE.com:8080/a/../b?q=1#f");
    defer u.deinit(a);
    try testing.expectEqualStrings("https", u.scheme.?);
    try testing.expectEqualStrings("user:pass", u.user_info.?);
    try testing.expectEqualStrings("EXAMPLE.com", u.host_text.?);
    try testing.expectEqualStrings("8080", u.port_text.?);
    try testing.expectEqual(@as(usize, 3), u.segments.items.len);
    try testing.expectEqualStrings("q=1", u.query.?);
    try testing.expectEqualStrings("f", u.fragment.?);
    try testing.expect(!u.absolute_path);
}

test "empty and absent ranges" {
    const a = testing.allocator;
    var u = try parse(a, "http://h?#");
    defer u.deinit(a);
    try testing.expectEqualStrings("", u.query.?);
    try testing.expectEqualStrings("", u.fragment.?);
    try testing.expectEqual(@as(usize, 0), u.segments.items.len);
    var v = try parse(a, "//");
    defer v.deinit(a);
    try testing.expectEqualStrings("", v.host_text.?);
    try testing.expect(v.scheme == null);
    var w = try parse(a, "http://h/");
    defer w.deinit(a);
    try testing.expectEqual(@as(usize, 1), w.segments.items.len);
    try testing.expectEqual(@as(usize, 0), w.segments.items[0].len);
    var x = try parse(a, "");
    defer x.deinit(a);
    try testing.expect(x.host_text == null and x.segments.items.len == 0);
    var y = try parse(a, "/");
    defer y.deinit(a);
    try testing.expect(y.absolute_path and y.segments.items.len == 0);
    var z = try parse(a, "http://u@h:");
    defer z.deinit(a);
    try testing.expectEqualStrings("", z.port_text.?);
    try testing.expectEqualStrings("u", z.user_info.?);
}

test "hosts" {
    const a = testing.allocator;
    var u = try parse(a, "http://1.2.3.4.5/");
    defer u.deinit(a);
    try testing.expect(u.host_data == .none);
    var v = try parse(a, "http://1.2.3.4/");
    defer v.deinit(a);
    try testing.expect(v.host_data == .ip4);
    var w = try parse(a, "http://01.2.3.4/");
    defer w.deinit(a);
    try testing.expect(w.host_data == .none);
    var x = try parse(a, "http://[V1.x]:8/");
    defer x.deinit(a);
    try testing.expect(x.host_data == .ip_future);
    try testing.expectEqualStrings("V1.x", x.host_text.?);
    var y = try parse(a, "//[::FFFF:1.2.3.4]");
    defer y.deinit(a);
    try testing.expectEqualStrings("::FFFF:1.2.3.4", y.host_text.?);
    try testing.expectError(error.Syntax, parse(a, "http://[::1"));
    try testing.expectError(error.Syntax, parse(a, "http://[1:2:3:4:5:6:7:8:9]"));
    try testing.expectError(error.Syntax, parse(a, "http://[::1::]"));
    try testing.expectError(error.Syntax, parse(a, "http://[fe80::1%25eth0]"));
    try testing.expectError(error.Syntax, parse(a, "http://éxample.com"));
    try testing.expectError(error.Syntax, parse(a, "http://a b"));
    try testing.expectError(error.Syntax, parse(a, "a\x00b"));
    try testing.expectError(error.Syntax, parse(a, ":"));
    try testing.expectError(error.Syntax, parse(a, "http://h:12a/"));
}

test "recomposition" {
    try expectRoundTrip("http://[::1]/x", "http://[0000:0000:0000:0000:0000:0000:0000:0001]/x");
    try expectRoundTrip("//[::FFFF:1.2.3.4]", "//[0000:0000:0000:0000:0000:ffff:0102:0304]");
    try expectRoundTrip("http://[V1.x]:8/", "http://[V1.x]:8/");
    try expectRoundTrip("https://user:pass@EXAMPLE.com:8080/a/../b?q=1#f", "https://user:pass@EXAMPLE.com:8080/a/../b?q=1#f");
    try expectRoundTrip("mailto:a@b", "mailto:a@b");
    try expectRoundTrip("a/b/c", "a/b/c");
    try expectRoundTrip("//u:p@h:1", "//u:p@h:1");
    try expectRoundTrip("file:///etc", "file:///etc");
    try expectRoundTrip("http://h", "http://h");
}

test "normalization" {
    try expectNormalized("https://user:pass@EXAMPLE.com:8080/a/../b?q=1#f", "https://user:pass@example.com:8080/b?q=1#f");
    try expectNormalized("HTTP://h/%7euser/%2a%41", "http://h/~user/%2AA");
    try expectNormalized("http://h:0080/", "http://h:80/");
    try expectNormalized("http://h:000/", "http://h:0/");
    try expectNormalized("http://[V1.X]/", "http://[v1.x]/");
    try expectNormalized("http://h/a/./b/../c/.", "http://h/a/c/");
    try expectNormalized("http://h/..", "http://h/");
    try expectNormalized("a/../../b", "../b");
    try expectNormalized("./a:b", "./a:b");
    try expectNormalized("/.//a", "/.//a");
    try expectNormalized("http://h/%2e%2E/x", "http://h/x");
}

test "reference resolution, rfc 3986 5.4" {
    const base = "http://a/b/c/d;p?q";
    const cases = [_][2][]const u8{
        .{ "g:h", "g:h" },                        .{ "g", "http://a/b/c/g" },               .{ "./g", "http://a/b/c/g" },
        .{ "g/", "http://a/b/c/g/" },             .{ "/g", "http://a/g" },                  .{ "//g", "http://g" },
        .{ "?y", "http://a/b/c/d;p?y" },          .{ "g?y", "http://a/b/c/g?y" },           .{ "#s", "http://a/b/c/d;p?q#s" },
        .{ "g#s", "http://a/b/c/g#s" },           .{ "g?y#s", "http://a/b/c/g?y#s" },       .{ ";x", "http://a/b/c/;x" },
        .{ "g;x", "http://a/b/c/g;x" },           .{ "", "http://a/b/c/d;p?q" },            .{ ".", "http://a/b/c/" },
        .{ "./", "http://a/b/c/" },               .{ "..", "http://a/b/" },                 .{ "../", "http://a/b/" },
        .{ "../g", "http://a/b/g" },              .{ "../..", "http://a/" },                .{ "../../", "http://a/" },
        .{ "../../g", "http://a/g" },             .{ "../../../g", "http://a/g" },          .{ "../../../../g", "http://a/g" },
        .{ "/./g", "http://a/g" },                .{ "/../g", "http://a/g" },               .{ "g.", "http://a/b/c/g." },
        .{ ".g", "http://a/b/c/.g" },             .{ "g..", "http://a/b/c/g.." },           .{ "..g", "http://a/b/c/..g" },
        .{ "./../g", "http://a/b/g" },            .{ "./g/.", "http://a/b/c/g/" },          .{ "g/./h", "http://a/b/c/g/h" },
        .{ "g/../h", "http://a/b/c/h" },          .{ "g;x=1/./y", "http://a/b/c/g;x=1/y" }, .{ "g;x=1/../y", "http://a/b/c/y" },
        .{ "g?y/./x", "http://a/b/c/g?y/./x" },   .{ "g?y/../x", "http://a/b/c/g?y/../x" }, .{ "g#s/./x", "http://a/b/c/g#s/./x" },
        .{ "g#s/../x", "http://a/b/c/g#s/../x" }, .{ "http:g", "http:g" },
    };
    for (cases) |c| try expectResolved(base, c[1 - 1], c[1]);
}

test "relative base is refused" {
    const a = testing.allocator;
    var b = try parse(a, "/a");
    defer b.deinit(a);
    var r = try parse(a, "b");
    defer r.deinit(a);
    try testing.expectError(error.AddBaseRelBase, addBase(a, &r, &b));
}

test "setters" {
    const a = testing.allocator;
    var u = try parse(a, "http://h/a");
    defer u.deinit(a);
    try testing.expectError(error.Syntax, setScheme(a, &u, ""));
    try testing.expectError(error.Syntax, setScheme(a, &u, "1a"));
    try setScheme(a, &u, "HTTPS");
    try testing.expectError(error.Syntax, setPortText(a, &u, "-1"));
    try setPortText(a, &u, "8080");
    try testing.expectError(error.SetHostPortSet, setHostAuto(a, &u, null));
    try setPortText(a, &u, null);
    try setUserInfo(a, &u, "us:er");
    try testing.expectError(error.SetHostUserInfoSet, setHostAuto(a, &u, null));
    try setUserInfo(a, &u, null);
    try setHostAuto(a, &u, null);
    const s1 = try toString(a, &u);
    defer a.free(s1);
    try testing.expectEqualStrings("HTTPS:/a", s1);
    try testing.expectError(error.SetUserInfoHostNotSet, setUserInfo(a, &u, "x"));
    try testing.expectError(error.SetPortHostNotSet, setPortText(a, &u, "1"));
    try setHostAuto(a, &u, "[::1]");
    try testing.expect(u.host_data == .ip6);
    try testing.expectError(error.Syntax, setHostAuto(a, &u, "[::1"));
    try testing.expectError(error.Syntax, setHostAuto(a, &u, "[vx]"));
    try setHostAuto(a, &u, "[v1.a]");
    try testing.expect(u.host_data == .ip_future);
    try setHostAuto(a, &u, "1.2.3.4");
    try testing.expect(u.host_data == .ip4);
    try testing.expectError(error.Syntax, setHostAuto(a, &u, "a b"));
    try testing.expectError(error.Syntax, setPath(a, &u, "a"));
    try setPath(a, &u, "/x//y");
    const s2 = try toString(a, &u);
    defer a.free(s2);
    try testing.expectEqualStrings("HTTPS://1.2.3.4/x//y", s2);
    try testing.expectError(error.Syntax, setQuery(a, &u, "a#b"));
    try setQuery(a, &u, "");
    try setFragment(a, &u, "f?/");
    const s3 = try toString(a, &u);
    defer a.free(s3);
    try testing.expectEqualStrings("HTTPS://1.2.3.4/x//y?#f?/", s3);
}

test "path disambiguation" {
    const a = testing.allocator;
    var u = try parse(a, "a");
    defer u.deinit(a);
    try setPath(a, &u, "b:c");
    const s1 = try toString(a, &u);
    defer a.free(s1);
    try testing.expectEqualStrings("./b:c", s1);
    try setPath(a, &u, "//x");
    const s2 = try toString(a, &u);
    defer a.free(s2);
    try testing.expectEqualStrings("/.//x", s2);
    var v = try parse(a, "s:b:c");
    defer v.deinit(a);
    try setScheme(a, &v, null);
    const s3 = try toString(a, &v);
    defer a.free(s3);
    try testing.expectEqualStrings("./b:c", s3);
    var w = try parse(a, "http://h//a");
    defer w.deinit(a);
    try setHostAuto(a, &w, null);
    const s4 = try toString(a, &w);
    defer a.free(s4);
    try testing.expectEqualStrings("http:/.//a", s4);
}

test "well-formed checks" {
    try testing.expect(isWellFormedHostIp6("::1"));
    try testing.expect(!isWellFormedHostIp6("0000:0000:0000:0000:0000:ffff:255.255.255.255"));
    try testing.expect(isWellFormedHostIp6("::ffff:255.255.255.255"));
    try testing.expect(!isWellFormedHostIp6("v1.x"));
    try testing.expect(isWellFormedHostIpFuture("v1.x"));
    try testing.expect(!isWellFormedHostIpFuture("::1"));
    try testing.expect(!isWellFormedHostIpFuture("vx"));
    try testing.expect(!isWellFormedHostIpFuture("v1.x]:80"));
    try testing.expect(!isWellFormedHostIp6("::1]x"));
    try testing.expect(!isWellFormedHostIp6(""));
    try testing.expect(isWellFormedHostIp4("255.255.255.255"));
    try testing.expect(!isWellFormedHostIp4("256.1.1.1"));
    try testing.expect(!isWellFormedHostIp4("1.1.1"));
    try testing.expect(isWellFormedPort(""));
    try testing.expect(isWellFormedPath("", false));
    try testing.expect(!isWellFormedPath("", true));
    try testing.expect(!isWellFormedUserInfo("a@b"));
    try testing.expect(!isWellFormedQuery("%2"));
    try testing.expect(isWellFormedFragment("%2f"));
}
