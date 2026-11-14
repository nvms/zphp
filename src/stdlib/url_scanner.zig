// php's url_scanner_ex.re: the url rewriter behind output_add_rewrite_var()
// and session.use_trans_sid. an output handler scans html for the tags the
// ini setting names (url_rewriter.tags, session.trans_sid_tags) and appends
// the rewrite variables to their urls, and a hidden input after each <form>.
// the scanner keeps what it can't decide yet (a tag cut by a chunk boundary)
// for the next chunk, and hands it over unchanged when the output is flushed
const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const VM = @import("../runtime/vm.zig").VM;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const url = @import("url.zig");
const RuntimeError = error{ RuntimeError, OutOfMemory };

const List = std.ArrayListUnmanaged(u8);

pub const Kind = enum(u2) { output = 1, session = 2 };

const State = enum { plain, tag, next_arg, arg, before_val, val };

// url_adapt_state_ex_t
pub const Ctx = struct {
    // the variables: "name=value" joined by arg_separator.output, and the
    // hidden inputs a form gets
    url_app: List = .empty,
    form_app: List = .empty,
    active: bool = false,
    buf: List = .empty,
    result: List = .empty,
    tag: List = .empty,
    arg: List = .empty,
    val: List = .empty,
    attr_val: List = .empty,
    // the attribute of the current tag whose url is rewritten
    lookup: List = .empty,
    state: State = .plain,
    tag_is_form: bool = false,
    attr_is_action: bool = false,

    pub fn deinit(self: *Ctx, a: std.mem.Allocator) void {
        inline for (.{ "url_app", "form_app", "buf", "result", "tag", "arg", "val", "attr_val", "lookup" }) |field| @field(self, field).deinit(a);
        self.* = .{};
    }
};

pub const entries = .{
    .{ "output_add_rewrite_var", native_output_add_rewrite_var },
    .{ "output_reset_rewrite_vars", native_output_reset_rewrite_vars },
};

fn ctxOf(vm: *VM, kind: Kind) *Ctx {
    return &vm.url_scanners[@intFromEnum(kind) - 1];
}

fn ini(vm: *VM, name: []const u8, default: []const u8) []const u8 {
    return vm.ini_settings.get(name) orelse @import("../ini_config.zig").get(name) orelse default;
}

fn separator(vm: *VM) []const u8 {
    return ini(vm, "arg_separator.output", "&");
}

const default_session_tags = "a=href,area=href,frame=src,form=";

fn tagsSetting(vm: *VM, kind: Kind) []const u8 {
    return switch (kind) {
        .output => ini(vm, "url_rewriter.tags", "form="),
        .session => ini(vm, "session.trans_sid_tags", default_session_tags),
    };
}

fn hostsSetting(vm: *VM, kind: Kind) []const u8 {
    return switch (kind) {
        .output => ini(vm, "url_rewriter.hosts", ""),
        .session => ini(vm, "session.trans_sid_hosts", ""),
    };
}

// php_ini_on_update_tags: "tag=attribute" pairs split at commas, the tag
// lowercased; the attribute of the tag named (lowercase), or null
fn lookupTag(vm: *VM, kind: Kind, tag: []const u8) ?[]const u8 {
    var it = std.mem.tokenizeScalar(u8, tagsSetting(vm, kind), ',');
    var found: ?[]const u8 = null;
    while (it.next()) |pair| {
        const eq = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
        // zend_hash_add keeps the first of repeated tags
        if (found == null and std.ascii.eqlIgnoreCase(pair[0..eq], tag)) found = pair[eq + 1 ..];
    }
    return found;
}

// php_ini_on_update_hosts: the allowed hosts, lowercased; host as given
fn hostAllowed(vm: *VM, kind: Kind, host: []const u8, ignore_case: bool) bool {
    var it = std.mem.tokenizeScalar(u8, hostsSetting(vm, kind), ',');
    while (it.next()) |allowed| {
        if (ignore_case) {
            if (std.ascii.eqlIgnoreCase(allowed, host)) return true;
        } else {
            // the table holds lowercased names and is searched as written
            if (allowed.len != host.len) continue;
            for (allowed, host) |x, y| {
                if (std.ascii.toLower(x) != y) break;
            } else return true;
        }
    }
    return false;
}

fn hostsEmpty(vm: *VM, kind: Kind) bool {
    var it = std.mem.tokenizeScalar(u8, hostsSetting(vm, kind), ',');
    return it.next() == null;
}

fn isHttp(scheme: []const u8) bool {
    return std.ascii.eqlIgnoreCase(scheme, "http") or std.ascii.eqlIgnoreCase(scheme, "https");
}

// a component as php_url_parse_ex copies it, control characters made '_'
fn appendPart(a: std.mem.Allocator, dest: *List, part: []const u8) !void {
    const at = dest.items.len;
    try dest.appendSlice(a, part);
    url.replaceControlChars(dest.items[at..]);
}

// append_modified_url
fn appendModifiedUrl(vm: *VM, kind: Kind, src: []const u8, dest: *List, url_app: []const u8) !void {
    const a = vm.allocator;
    const parts = url.parse(src) orelse return dest.appendSlice(a, src);
    // "#mark" stays as it is
    if (parts.fragment != null and src.len > 0 and src[0] == '#') return dest.appendSlice(a, src);
    if (parts.scheme) |scheme| if (!isHttp(scheme)) return dest.appendSlice(a, src);
    if (parts.host) |host| if (!hostAllowed(vm, kind, host, true)) return dest.appendSlice(a, src);
    if (parts.path == null and parts.query == null and parts.fragment == null) {
        try dest.appendSlice(a, src);
        try dest.appendSlice(a, "/?");
        return dest.appendSlice(a, url_app);
    }
    if (parts.scheme) |scheme| {
        try appendPart(a, dest, scheme);
        try dest.appendSlice(a, "://");
    } else if (src.len > 1 and src[0] == '/' and src[1] == '/') {
        try dest.appendSlice(a, "//");
    }
    if (parts.user) |user| {
        try appendPart(a, dest, user);
        if (parts.pass) |pass| {
            try appendPart(a, dest, pass);
            try dest.append(a, ':');
        }
        try dest.append(a, '@');
    }
    if (parts.host) |host| try appendPart(a, dest, host);
    if (parts.port != 0) try dest.print(a, ":{d}", .{parts.port});
    if (parts.path) |path| try appendPart(a, dest, path);
    try dest.append(a, '?');
    if (parts.query) |query| {
        try appendPart(a, dest, query);
        try dest.appendSlice(a, separator(vm));
    }
    try dest.appendSlice(a, url_app);
    if (parts.fragment) |fragment| {
        try dest.append(a, '#');
        try appendPart(a, dest, fragment);
    }
}

// check_http_host: the host matches $_SERVER['HTTP_HOST'] without its port
fn matchesHttpHost(vm: *VM, host: []const u8) bool {
    const server = vm.request_vars.get("$_SERVER") orelse return false;
    if (server != .array) return false;
    const given = server.array.get(.{ .string = Value.String.borrowed("HTTP_HOST") });
    if (given != .string) return false;
    var name = given.string.bytes();
    if (std.mem.indexOfScalar(u8, name, ':')) |colon| name = name[0..colon];
    if (std.mem.indexOfScalar(u8, name, 0)) |nul| name = name[0..nul];
    return std.ascii.eqlIgnoreCase(name, host);
}

// check_host_whitelist for a form's action
fn formHostAllowed(vm: *VM, kind: Kind, ctx: *Ctx) bool {
    if (ctx.attr_val.items.len == 0) return true;
    const parts = url.parse(ctx.attr_val.items) orelse return false;
    if (parts.scheme) |scheme| if (!isHttp(scheme)) return false;
    const host = parts.host orelse return true;
    if (hostsEmpty(vm, kind) and matchesHttpHost(vm, host)) return true;
    return hostAllowed(vm, kind, host, false);
}

const Scan = struct {
    vm: *VM,
    kind: Kind,
    ctx: *Ctx,
    data: []const u8,
    cursor: usize = 0,
    start: usize = 0,

    fn a(self: *Scan) std.mem.Allocator {
        return self.vm.allocator;
    }

    fn passthru(self: *Scan) !void {
        try self.ctx.result.appendSlice(self.a(), self.data[self.start..self.cursor]);
    }

    fn handleTag(self: *Scan) !void {
        const ctx = self.ctx;
        ctx.tag.clearRetainingCapacity();
        for (self.data[self.start..self.cursor]) |c| try ctx.tag.append(self.a(), std.ascii.toLower(c));
        if (lookupTag(self.vm, self.kind, ctx.tag.items)) |attr| {
            ctx.lookup.clearRetainingCapacity();
            try ctx.lookup.appendSlice(self.a(), attr);
            ctx.tag_is_form = std.mem.eql(u8, ctx.tag.items, "form");
            ctx.state = .next_arg;
        } else ctx.state = .plain;
    }

    fn handleArg(self: *Scan) !void {
        const ctx = self.ctx;
        ctx.arg.clearRetainingCapacity();
        try ctx.arg.appendSlice(self.a(), self.data[self.start..self.cursor]);
        // strncasecmp over the argument's length: a prefix of "action" counts
        ctx.attr_is_action = ctx.tag_is_form and ctx.arg.items.len <= "action".len and std.ascii.eqlIgnoreCase(ctx.arg.items, "action"[0..ctx.arg.items.len]);
    }

    fn handleForm(self: *Scan) !void {
        const ctx = self.ctx;
        if (ctx.form_app.items.len == 0) return;
        if (!std.mem.eql(u8, ctx.tag.items, "form")) return;
        if (!formHostAllowed(self.vm, self.kind, ctx)) return;
        try ctx.result.appendSlice(self.a(), ctx.form_app.items);
    }

    fn handleVal(self: *Scan, quotes: usize, quote: u8) !void {
        const ctx = self.ctx;
        const value = self.data[self.start + quotes .. self.cursor - quotes];
        ctx.val.clearRetainingCapacity();
        try ctx.val.appendSlice(self.a(), value);
        if (ctx.tag_is_form and ctx.attr_is_action) {
            ctx.attr_val.clearRetainingCapacity();
            try ctx.attr_val.appendSlice(self.a(), value);
        }
        // tag_arg
        const rewrite = std.ascii.eqlIgnoreCase(ctx.arg.items, ctx.lookup.items);
        if (quotes > 0) try ctx.result.append(self.a(), quote);
        if (rewrite) {
            try appendModifiedUrl(self.vm, self.kind, ctx.val.items, &ctx.result, ctx.url_app.items);
        } else {
            try ctx.result.appendSlice(self.a(), ctx.val.items);
        }
        if (quotes > 0) try ctx.result.append(self.a(), quote);
    }

    fn left(self: *Scan) usize {
        return self.data.len - self.cursor;
    }

    fn isAlpha(c: u8) bool {
        return std.ascii.isAlphabetic(c);
    }

    // the states of xx_mainloop; false when the scan stops for more input,
    // which is kept from `start` on
    fn run(self: *Scan) !void {
        const ctx = self.ctx;
        while (true) {
            self.start = self.cursor;
            switch (ctx.state) {
                .plain => {
                    if (self.left() < 1) return;
                    if (self.data[self.cursor] == '<') {
                        self.cursor += 1;
                        try self.passthru();
                        ctx.state = .tag;
                        continue;
                    }
                    while (self.cursor < self.data.len and self.data[self.cursor] != '<') self.cursor += 1;
                    if (self.cursor == self.data.len) return;
                    try self.passthru();
                },
                .tag => {
                    if (self.left() < 1) return;
                    const c = self.data[self.cursor];
                    if (isAlpha(c) or c == ':') {
                        while (self.cursor < self.data.len and (isAlpha(self.data[self.cursor]) or self.data[self.cursor] == ':')) self.cursor += 1;
                        if (self.cursor == self.data.len) return;
                        try self.handleTag();
                        try self.passthru();
                    } else {
                        self.cursor += 1;
                        try self.passthru();
                        ctx.state = .plain;
                    }
                },
                .next_arg => {
                    if (self.left() < 2) return;
                    const c = self.data[self.cursor];
                    switch (c) {
                        '\t', '\n', 0x0b, '\r', ' ' => {
                            while (self.cursor < self.data.len and switch (self.data[self.cursor]) {
                                '\t', '\n', 0x0b, '\r', ' ' => true,
                                else => false,
                            }) self.cursor += 1;
                            if (self.cursor == self.data.len) return;
                            try self.passthru();
                        },
                        '/', '>' => {
                            if (c == '/' and self.data[self.cursor + 1] != '>') {
                                self.cursor += 1;
                                try self.passthru();
                                ctx.state = .plain;
                                continue;
                            }
                            self.cursor += if (c == '/') 2 else 1;
                            try self.passthru();
                            try self.handleForm();
                            ctx.state = .plain;
                        },
                        else => {
                            if (isAlpha(c)) {
                                ctx.state = .arg;
                                continue;
                            }
                            self.cursor += 1;
                            try self.passthru();
                            ctx.state = .plain;
                        },
                    }
                },
                .arg => {
                    if (self.left() < 1) return;
                    if (isAlpha(self.data[self.cursor])) {
                        self.cursor += 1;
                        while (self.cursor < self.data.len and (isAlpha(self.data[self.cursor]) or self.data[self.cursor] == '-')) self.cursor += 1;
                        if (self.cursor == self.data.len) return;
                        try self.passthru();
                        try self.handleArg();
                        ctx.state = .before_val;
                    } else {
                        self.cursor += 1;
                        try self.passthru();
                        ctx.state = .next_arg;
                    }
                },
                .before_val => {
                    if (self.left() < 2) return;
                    // [ ]* "=" [ ]*, else back to the arguments unconsumed
                    var i = self.cursor;
                    while (i < self.data.len and self.data[i] == ' ') i += 1;
                    if (i == self.data.len) return;
                    if (self.data[i] != '=') {
                        ctx.state = .next_arg;
                        continue;
                    }
                    i += 1;
                    while (i < self.data.len and self.data[i] == ' ') i += 1;
                    if (i == self.data.len) return;
                    self.cursor = i;
                    try self.passthru();
                    ctx.state = .val;
                },
                .val => {
                    if (self.left() < 2) return;
                    const c = self.data[self.cursor];
                    if (c == '"' or c == '\'') {
                        var i = self.cursor + 1;
                        while (i < self.data.len and self.data[i] != c and self.data[i] != '>') i += 1;
                        if (i == self.data.len) return;
                        if (self.data[i] == c) {
                            self.cursor = i + 1;
                            try self.handleVal(1, c);
                        } else {
                            self.cursor += 1;
                            try self.passthru();
                        }
                        ctx.state = .next_arg;
                        continue;
                    }
                    const unquoted = struct {
                        fn in(ch: u8) bool {
                            return switch (ch) {
                                ' ', '\r', '\t', '\n', '>', '\'', '"' => false,
                                else => true,
                            };
                        }
                    }.in;
                    if (unquoted(c)) {
                        while (self.cursor < self.data.len and unquoted(self.data[self.cursor])) self.cursor += 1;
                        if (self.cursor == self.data.len) return;
                        try self.handleVal(0, ' ');
                    } else {
                        self.cursor += 1;
                        try self.passthru();
                    }
                    ctx.state = .next_arg;
                },
            }
        }
    }
};

// url_adapt_ext: the scanned output, the undecided rest kept unless the
// output is being flushed
fn adapt(vm: *VM, kind: Kind, input: []const u8, flush: bool) ![]u8 {
    const ctx = ctxOf(vm, kind);
    const a = vm.allocator;
    try ctx.buf.appendSlice(a, input);
    const data = try a.dupe(u8, ctx.buf.items);
    defer a.free(data);
    var scan: Scan = .{ .vm = vm, .kind = kind, .ctx = ctx, .data = data };
    try scan.run();
    ctx.buf.clearRetainingCapacity();
    try ctx.buf.appendSlice(a, data[scan.start..]);
    if (flush) {
        try ctx.result.appendSlice(a, ctx.buf.items);
        ctx.buf.clearAndFree(a);
        ctx.val.clearAndFree(a);
        ctx.attr_val.clearAndFree(a);
    }
    return ctx.result.toOwnedSlice(a);
}

// php_url_scanner_session_handler_impl, the handler's run over its buffer.
// flush is set for a flush or the final call
pub fn handle(vm: *VM, kind: Kind, input: []const u8, flush: bool) ![]u8 {
    const ctx = ctxOf(vm, kind);
    if (ctx.url_app.items.len != 0) return adapt(vm, kind, input, flush);
    const a = vm.allocator;
    var out: List = .empty;
    errdefer out.deinit(a);
    try out.appendSlice(a, ctx.buf.items);
    try out.appendSlice(a, input);
    ctx.buf.clearAndFree(a);
    ctx.result.clearAndFree(a);
    return out.toOwnedSlice(a);
}

fn rawUrlEncode(a: std.mem.Allocator, out: *List, s: []const u8) !void {
    const hex = "0123456789ABCDEF";
    for (s) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
            try out.append(a, c);
        } else {
            try out.appendSlice(a, &.{ '%', hex[c >> 4], hex[c & 0x0f] });
        }
    }
}

// php_escape_html_entities_ex with ENT_QUOTES|ENT_SUBSTITUTE, no double encoding
fn htmlEscape(ctx: *NativeContext, out: *List, s: []const u8) !void {
    var escaped: List = .empty;
    defer escaped.deinit(ctx.allocator);
    if (try @import("html.zig").escapeHtmlEntities(ctx, "output_add_rewrite_var", s, false, 3 | 8, null, false, &escaped)) {
        try out.appendSlice(ctx.vm.allocator, escaped.items);
    }
}

// php_url_scanner_add_var_impl: the first variable starts the handler
pub fn addVar(native: *NativeContext, kind: Kind, name: []const u8, value: []const u8, encode: bool) !void {
    const vm = native.vm;
    const a = vm.allocator;
    const ctx = ctxOf(vm, kind);
    var should_start = false;
    if (!ctx.active) {
        ctx.buf.clearRetainingCapacity();
        ctx.result.clearRetainingCapacity();
        ctx.tag.clearRetainingCapacity();
        ctx.arg.clearRetainingCapacity();
        ctx.val.clearRetainingCapacity();
        ctx.attr_val.clearRetainingCapacity();
        ctx.state = .plain;
        ctx.tag_is_form = false;
        ctx.attr_is_action = false;
        ctx.active = true;
        should_start = true;
    }
    if (ctx.url_app.items.len != 0) try ctx.url_app.appendSlice(a, separator(vm));
    if (encode) {
        try rawUrlEncode(a, &ctx.url_app, name);
        try ctx.url_app.append(a, '=');
        try rawUrlEncode(a, &ctx.url_app, value);
        try ctx.form_app.appendSlice(a, "<input type=\"hidden\" name=\"");
        try htmlEscape(native, &ctx.form_app, name);
        try ctx.form_app.appendSlice(a, "\" value=\"");
        try htmlEscape(native, &ctx.form_app, value);
    } else {
        try ctx.url_app.appendSlice(a, name);
        try ctx.url_app.append(a, '=');
        try ctx.url_app.appendSlice(a, value);
        try ctx.form_app.appendSlice(a, "<input type=\"hidden\" name=\"");
        try ctx.form_app.appendSlice(a, name);
        try ctx.form_app.appendSlice(a, "\" value=\"");
        try ctx.form_app.appendSlice(a, value);
    }
    try ctx.form_app.appendSlice(a, "\" />");
    if (should_start) try @import("output_control.zig").startRewriter(vm, kind);
}

pub fn resetVars(vm: *VM, kind: Kind) void {
    const ctx = ctxOf(vm, kind);
    ctx.form_app.clearRetainingCapacity();
    ctx.url_app.clearRetainingCapacity();
}

// php_url_scanner_reset_var_impl: drops one variable (encoded as addVar
// encodes it) from the url and form appendices
pub fn resetVar(native: *NativeContext, kind: Kind, name: []const u8) !void {
    const vm = native.vm;
    const a = vm.allocator;
    const ctx = ctxOf(vm, kind);
    if (ctx.url_app.items.len == 0) return;
    var sname: List = .empty;
    defer sname.deinit(a);
    try rawUrlEncode(a, &sname, name);
    try sname.append(a, '=');
    var hname: List = .empty;
    defer hname.deinit(a);
    try hname.appendSlice(a, "<input type=\"hidden\" name=\"");
    try htmlEscape(native, &hname, name);
    try hname.appendSlice(a, "\" value=\"");
    const sep = separator(vm);
    var start = std.mem.indexOf(u8, ctx.url_app.items, sname.items) orelse return;
    var end = start + sname.items.len;
    var sep_removed = false;
    while (end < ctx.url_app.items.len) {
        if (std.mem.startsWith(u8, ctx.url_app.items[end..], sep)) {
            end += sep.len;
            sep_removed = true;
            break;
        }
        end += 1;
    }
    if (end - start == ctx.url_app.items.len) return resetVars(vm, kind);
    if (!sep_removed and start >= sep.len and std.mem.eql(u8, ctx.url_app.items[start - sep.len .. start], sep)) start -= sep.len;
    ctx.url_app.replaceRangeAssumeCapacity(start, end - start, &.{});
    const fstart = std.mem.indexOf(u8, ctx.form_app.items, hname.items) orelse return resetVars(vm, kind);
    var fend = fstart + hname.items.len;
    while (fend < ctx.form_app.items.len) {
        if (ctx.form_app.items[fend] == '>') {
            fend += 1;
            break;
        }
        fend += 1;
    }
    ctx.form_app.replaceRangeAssumeCapacity(fstart, fend - fstart, &.{});
}

fn native_output_add_rewrite_var(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const params = @import("html.zig").Params{ .ctx = ctx, .func = "output_add_rewrite_var", .args = args };
    const name = try params.string(0, "name", "");
    const value = try params.string(1, "value", "");
    try addVar(ctx, .output, name, value, true);
    return NativeResult.scalar(.{ .bool = true });
}

fn native_output_reset_rewrite_vars(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    resetVars(ctx.vm, .output);
    return NativeResult.scalar(.{ .bool = true });
}
