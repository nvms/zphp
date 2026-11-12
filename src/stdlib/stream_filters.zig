// stream filters: php's bucket brigades (main/streams/filter.c), the
// standard filters (ext/standard/filters.c: string.rot13/toupper/tolower,
// convert.*, consumed, dechunk), zlib.inflate/deflate (ext/zlib/zlib_filter.c)
// and user filters (ext/standard/user_filters.c: php_user_filter,
// StreamBucket, stream_bucket_* and stream_filter_*)
const std = @import("std");
const Allocator = std.mem.Allocator;
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const PhpObject = value_mod.PhpObject;
const PhpArray = value_mod.PhpArray;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const ClassDef = vm_mod.ClassDef;
const NativeContext = vm_mod.NativeContext;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const streams = @import("streams.zig");
const fs = @import("filesystem.zig");
const zlib = @import("c_zlib");

const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const Flags = enum(u2) { normal = 0, flush_inc = 1, flush_close = 2 };
pub const Status = enum(u2) { err_fatal = 0, feed_me = 1, pass_on = 2 };

pub const Bucket = struct {
    allocator: Allocator,
    buf: []u8,
    refcount: u32 = 1,
    brigade: ?*Brigade = null,
    prev: ?*Bucket = null,
    next: ?*Bucket = null,

    pub fn create(a: Allocator, data: []const u8) RuntimeError!*Bucket {
        return adopt(a, try a.dupe(u8, data));
    }

    pub fn adopt(a: Allocator, owned: []u8) RuntimeError!*Bucket {
        const b = a.create(Bucket) catch |err| {
            a.free(owned);
            return err;
        };
        b.* = .{ .allocator = a, .buf = owned };
        return b;
    }

    pub fn bytes(self: *const Bucket) []u8 {
        return self.buf;
    }

    pub fn unlink(self: *Bucket) void {
        const brigade = self.brigade orelse return;
        if (self.prev) |p| p.next = self.next else brigade.head = self.next;
        if (self.next) |n| n.prev = self.prev else brigade.tail = self.prev;
        self.brigade = null;
        self.prev = null;
        self.next = null;
    }

    pub fn delref(self: *Bucket) void {
        self.refcount -= 1;
        if (self.refcount == 0) {
            self.allocator.free(self.buf);
            self.allocator.destroy(self);
        }
    }

    pub fn resize(self: *Bucket, len: usize) RuntimeError!void {
        self.buf = try self.allocator.realloc(self.buf, len);
    }
};

// php_stream_bucket_make_writeable: the bucket off its brigade, copied when
// something else still holds it
pub fn makeWriteable(bucket: *Bucket) RuntimeError!*Bucket {
    bucket.unlink();
    if (bucket.refcount == 1) return bucket;
    const copy = try Bucket.create(bucket.allocator, bucket.buf);
    bucket.delref();
    return copy;
}

pub const Brigade = struct {
    head: ?*Bucket = null,
    tail: ?*Bucket = null,

    pub fn append(self: *Brigade, b: *Bucket) RuntimeError!void {
        if (self.tail == b) return;
        b.prev = self.tail;
        b.next = null;
        if (self.tail) |t| t.next = b else self.head = b;
        self.tail = b;
        b.brigade = self;
    }

    pub fn prepend(self: *Brigade, b: *Bucket) void {
        b.prev = null;
        b.next = self.head;
        if (self.head) |h| h.prev = b else self.tail = b;
        self.head = b;
        b.brigade = self;
    }

    pub fn clear(self: *Brigade) void {
        while (self.head) |b| {
            b.unlink();
            b.delref();
        }
    }
};

pub const Chain = struct {
    head: ?*Filter = null,
    tail: ?*Filter = null,
    read: bool = false,
    owner: ?*PhpObject = null,
};

pub const Filter = struct {
    allocator: Allocator,
    name: []u8,
    impl: Impl,
    chain: ?*Chain = null,
    prev: ?*Filter = null,
    next: ?*Filter = null,
    resource: ?*PhpObject = null,

    fn destroy(self: *Filter) void {
        switch (self.impl) {
            .convert => |c| {
                c.deinit(self.allocator);
                self.allocator.destroy(c);
            },
            .zlib_inflate, .zlib_deflate => |z| {
                if (self.impl == .zlib_deflate) _ = zlib.deflateEnd(&z.strm) else if (!z.finished) _ = zlib.inflateEnd(&z.strm);
                self.allocator.destroy(z);
            },
            else => {},
        }
        self.allocator.free(self.name);
        self.allocator.destroy(self);
    }
};

pub const Impl = union(enum) {
    rot13,
    toupper,
    tolower,
    convert: *Convert,
    consumed: struct { consumed: i64 = 0, offset: ?i64 = null },
    dechunk: Dechunk,
    zlib_inflate: *ZlibData,
    zlib_deflate: *ZlibData,
    // the php_user_filter object, retained
    user: *PhpObject,
};

// --- running chains ----------------------------------------------------------

pub const RunResult = struct {
    status: Status,
    output: *Brigade,
    other: *Brigade,

    pub fn discardOutput(self: RunResult) void {
        self.output.clear();
        self.other.clear();
    }
};

// winds the brigade through the chain from `start`: each filter's output is
// the next one's input. consumed is reported by the chain's first filter
pub fn runChain(ctx: *NativeContext, stream_obj: *PhpObject, chain: *Chain, start: ?*Filter, in: *Brigade, out: *Brigade, consumed: ?*usize, flags: Flags) RuntimeError!RunResult {
    var inp = in;
    var outp = out;
    var status: Status = .err_fatal;
    var current = start;
    while (current) |f| : (current = f.next) {
        status = try apply(ctx, stream_obj, f, inp, outp, if (f == chain.head) consumed else null, flags);
        // a filter that threw: the buckets go and the call raises it
        if (ctx.vm.pending_exception != null) {
            inp.clear();
            outp.clear();
            return error.RuntimeError;
        }
        if (status != .pass_on) break;
        const swap = inp;
        inp = outp;
        outp = swap;
        outp.* = .{};
    }
    if (status == .pass_on) return .{ .status = status, .output = inp, .other = outp };
    return .{ .status = status, .output = outp, .other = inp };
}

fn apply(ctx: *NativeContext, stream_obj: *PhpObject, f: *Filter, in: *Brigade, out: *Brigade, consumed: ?*usize, flags: Flags) RuntimeError!Status {
    switch (f.impl) {
        .rot13, .toupper, .tolower => {
            var total: usize = 0;
            while (in.head) |head| {
                const b = try makeWriteable(head);
                for (b.buf) |*c| c.* = switch (f.impl) {
                    .rot13 => switch (c.*) {
                        'a'...'m', 'A'...'M' => c.* + 13,
                        'n'...'z', 'N'...'Z' => c.* - 13,
                        else => c.*,
                    },
                    .toupper => std.ascii.toUpper(c.*),
                    else => std.ascii.toLower(c.*),
                };
                total += b.buf.len;
                try out.append(b);
            }
            if (consumed) |p| p.* = total;
            return .pass_on;
        },
        .convert => |c| return convertFilter(ctx, c, f, in, out, consumed, flags),
        .consumed => |*data| {
            if (data.offset == null) data.offset = try streams.tell(ctx, stream_obj);
            var total: usize = 0;
            while (in.head) |b| {
                b.unlink();
                total += b.buf.len;
                try out.append(b);
            }
            if (consumed) |p| p.* = total;
            if (flags == .flush_close) _ = try streams.seek(ctx, stream_obj, data.offset.? + data.consumed, 0);
            data.consumed += @intCast(total);
            return .pass_on;
        },
        .dechunk => |*data| {
            var total: usize = 0;
            while (in.head) |head| {
                const b = try makeWriteable(head);
                total += b.buf.len;
                const n = data.run(b.buf);
                try b.resize(n);
                try out.append(b);
            }
            if (consumed) |p| p.* = total;
            return .pass_on;
        },
        .zlib_inflate => |z| return zlibInflate(ctx, z, in, out, consumed, flags),
        .zlib_deflate => |z| return zlibDeflate(ctx, z, in, out, consumed, flags),
        .user => |obj| return userFilter(ctx, stream_obj, f, obj, in, out, consumed, flags),
    }
}

// --- creating filters --------------------------------------------------------

const builtin_factories = [_][]const u8{ "zlib.*", "string.rot13", "string.toupper", "string.tolower", "convert.*", "consumed", "dechunk" };

fn builtinFactory(name: []const u8) ?[]const u8 {
    for (builtin_factories) |f| if (std.mem.eql(u8, f, name)) return f;
    return null;
}

pub fn registeredFilters(vm: *VM, out: *PhpArray, a: Allocator) !void {
    for (builtin_factories) |f| try out.append(a, .{ .string = Value.String.borrowed(f) });
    for (vm.stream_filters_user.keys()) |k| try out.appendCopiedString(a, k);
}

const Factory = union(enum) { builtin: []const u8, user: []const u8 };

fn findFactory(vm: *VM, name: []const u8) ?Factory {
    if (vm.stream_filters_user.get(name)) |class| return .{ .user = class };
    if (builtinFactory(name)) |b| return .{ .builtin = b };
    return null;
}

// php_stream_filter_create: the exact name, then wildcards from the last
// dot back ("a.b.c", "a.b.*", "a.*")
pub fn create(ctx: *NativeContext, name: []const u8, params: ?Value) RuntimeError!?*Filter {
    var factory_found = false;
    var filter: ?*Filter = null;
    if (findFactory(ctx.vm, name)) |factory| {
        factory_found = true;
        filter = try createWith(ctx, factory, name, params);
    } else if (std.mem.lastIndexOfScalar(u8, name, '.') != null) {
        var wild: std.ArrayListUnmanaged(u8) = .empty;
        defer wild.deinit(ctx.allocator);
        var prefix_len = std.mem.lastIndexOfScalar(u8, name, '.').?;
        while (filter == null) {
            wild.clearRetainingCapacity();
            try wild.appendSlice(ctx.allocator, name[0..prefix_len]);
            try wild.appendSlice(ctx.allocator, ".*");
            if (findFactory(ctx.vm, wild.items)) |factory| {
                factory_found = true;
                filter = try createWith(ctx, factory, name, params);
            }
            prefix_len = std.mem.lastIndexOfScalar(u8, name[0..prefix_len], '.') orelse break;
        }
    }
    if (filter == null) {
        if (!factory_found)
            try fs.warnDocref(ctx, "Unable to locate filter \"{s}\"", .{name})
        else
            try fs.warnDocref(ctx, "Unable to create or locate filter \"{s}\"", .{name});
    }
    return filter;
}

fn newFilter(ctx: *NativeContext, name: []const u8, impl: Impl) RuntimeError!*Filter {
    const f = try ctx.allocator.create(Filter);
    f.* = .{ .allocator = ctx.allocator, .name = try ctx.allocator.dupe(u8, name), .impl = impl };
    return f;
}

fn createWith(ctx: *NativeContext, factory: Factory, name: []const u8, params: ?Value) RuntimeError!?*Filter {
    switch (factory) {
        .user => |class| return createUserFilter(ctx, name, class, params),
        .builtin => |b| {
            if (std.mem.eql(u8, b, "string.rot13")) return try newFilter(ctx, name, .rot13);
            if (std.mem.eql(u8, b, "string.toupper")) return try newFilter(ctx, name, .toupper);
            if (std.mem.eql(u8, b, "string.tolower")) return try newFilter(ctx, name, .tolower);
            if (std.mem.eql(u8, b, "consumed")) {
                if (!std.ascii.eqlIgnoreCase(name, "consumed")) return null;
                return try newFilter(ctx, name, .{ .consumed = .{} });
            }
            if (std.mem.eql(u8, b, "dechunk")) {
                if (!std.ascii.eqlIgnoreCase(name, "dechunk")) return null;
                return try newFilter(ctx, name, .{ .dechunk = .{} });
            }
            if (std.mem.eql(u8, b, "convert.*")) return createConvert(ctx, name, params);
            if (std.mem.eql(u8, b, "zlib.*")) return createZlib(ctx, name, params);
            return null;
        },
    }
}

// --- chains on a stream ------------------------------------------------------

pub fn prepend(chain: *Chain, f: *Filter) void {
    f.next = chain.head;
    f.prev = null;
    if (chain.head) |h| h.prev = f else chain.tail = f;
    chain.head = f;
    f.chain = chain;
}

// php_stream_filter_append_ex: false when the filter failed on the data
// already buffered (the filter stays on the chain; the caller removes it)
pub fn append(ctx: *NativeContext, stream_obj: *PhpObject, chain: *Chain, f: *Filter) RuntimeError!bool {
    f.prev = chain.tail;
    f.next = null;
    if (chain.tail) |t| t.next = f else chain.head = f;
    chain.tail = f;
    f.chain = chain;
    const s = streams.get(stream_obj) orelse return true;
    if (!chain.read or s.writepos - s.readpos == 0) return true;
    var brig_in: Brigade = .{};
    var brig_out: Brigade = .{};
    try brig_in.append(try Bucket.create(s.allocator, s.readbuf[s.readpos..s.writepos]));
    var consumed: usize = 0;
    var status = try apply(ctx, stream_obj, f, &brig_in, &brig_out, &consumed, .normal);
    if (s.readpos + consumed > s.writepos) status = .err_fatal;
    switch (status) {
        .err_fatal => {
            brig_in.clear();
            brig_out.clear();
            try fs.warnDocref(ctx, "Filter failed to process pre-buffered data", .{});
            return false;
        },
        .feed_me => {
            s.readpos = 0;
            s.writepos = 0;
            brig_out.clear();
        },
        .pass_on => {
            s.readpos = 0;
            s.writepos = 0;
            while (brig_out.head) |b| {
                b.unlink();
                defer b.delref();
                if (s.readbuf.len - s.writepos < b.buf.len) {
                    const newlen = s.readbuf.len + b.buf.len;
                    s.readbuf = if (s.readbuf.len == 0) try s.allocator.alloc(u8, newlen) else try s.allocator.realloc(s.readbuf, newlen);
                }
                @memcpy(s.readbuf[s.writepos..][0..b.buf.len], b.buf);
                s.writepos += b.buf.len;
            }
        },
    }
    return true;
}

// php_stream_filter_remove: off its chain; the resource closes; the filter
// is freed (a user filter's onClose runs)
pub fn remove(ctx: *NativeContext, f: *Filter) RuntimeError!void {
    unlinkFilter(f);
    if (f.resource) |r| {
        closeResource(ctx.allocator, r);
        f.resource = null;
        ctx.vm.releaseValue(.{ .resource = r });
    }
    try free(ctx, f);
}

fn unlinkFilter(f: *Filter) void {
    const chain = f.chain orelse return;
    if (f.prev) |p| p.next = f.next else chain.head = f.next;
    if (f.next) |n| n.prev = f.prev else chain.tail = f.prev;
    f.chain = null;
    f.prev = null;
    f.next = null;
}

fn closeResource(a: Allocator, r: *PhpObject) void {
    r.native = .{};
    r.set(a, "__open", .{ .bool = false }) catch {};
}

fn free(ctx: *NativeContext, f: *Filter) RuntimeError!void {
    switch (f.impl) {
        .user => |obj| {
            defer {
                ctx.vm.releaseValue(.{ .object = obj });
                f.destroy();
            }
            _ = try callIfExists(ctx, obj, "onClose", &.{});
        },
        else => f.destroy(),
    }
}

pub fn removeAll(ctx: *NativeContext, chain: *Chain) RuntimeError!void {
    while (chain.head) |f| try remove(ctx, f);
}

// the memory of a stream's filters when the stream itself goes, with no
// php code left to run
pub fn releaseChain(chain: *Chain) void {
    while (chain.head) |f| {
        unlinkFilter(f);
        if (f.resource) |r| closeResource(f.allocator, r);
        f.destroy();
    }
}

// _php_stream_filter_flush: pushes what the filter holds through the rest
// of its chain into the read buffer or out to the stream
pub fn flushFilter(ctx: *NativeContext, f: *Filter, finish: bool) RuntimeError!bool {
    const chain = f.chain orelse return false;
    const stream_obj = chain.owner orelse return false;
    var brig_a: Brigade = .{};
    var brig_b: Brigade = .{};
    var inp = &brig_a;
    var outp = &brig_b;
    var flags: Flags = if (finish) .flush_close else .flush_inc;
    var current: ?*Filter = f;
    while (current) |cur| : (current = cur.next) {
        const status = try apply(ctx, stream_obj, cur, inp, outp, null, flags);
        if (status == .feed_me) return true;
        if (status == .err_fatal) return false;
        const t = inp;
        inp = outp;
        outp = t;
        outp.* = .{};
        flags = .normal;
    }
    var flushed: usize = 0;
    var it = inp.head;
    while (it) |b| : (it = b.next) flushed += b.buf.len;
    if (flushed == 0) return true;
    const s = streams.get(stream_obj) orelse return true;
    if (chain.read) {
        if (s.readpos > 0) {
            const avail = s.writepos - s.readpos;
            std.mem.copyForwards(u8, s.readbuf[0..avail], s.readbuf[s.readpos..s.writepos]);
            s.writepos = avail;
            s.readpos = 0;
        }
        if (flushed > s.readbuf.len - s.writepos) {
            const newlen = s.writepos + flushed + s.chunk_size;
            s.readbuf = if (s.readbuf.len == 0) try s.allocator.alloc(u8, newlen) else try s.allocator.realloc(s.readbuf, newlen);
        }
        while (inp.head) |b| {
            b.unlink();
            defer b.delref();
            @memcpy(s.readbuf[s.writepos..][0..b.buf.len], b.buf);
            s.writepos += b.buf.len;
        }
    } else {
        while (inp.head) |b| {
            b.unlink();
            defer b.delref();
            const n = try streams.rawWrite(ctx, stream_obj, s, b.buf);
            if (n > 0) s.position += n;
        }
    }
    return true;
}

// --- convert.* -----------------------------------------------------------------

const ConvErr = enum { success, unknown, too_big, invalid_seq, unexpected_eos, more };

pub const Convert = struct {
    mode: Mode,
    lbchars: ?[]u8 = null,
    line_len: u32 = 0,
    line_ccnt: u32 = 0,
    // base64-encode
    erem: [3]u8 = undefined,
    erem_len: usize = 0,
    // base64-decode
    urem: u32 = 0,
    urem_nbits: u32 = 0,
    ustat: u32 = 0,
    eos: bool = false,
    // quoted-printable
    opts: u32 = 0,
    lb_ptr: u32 = 0,
    lb_cnt: u32 = 0,
    scan_stat: u32 = 0,
    next_char: u32 = 0,
    stub: [128]u8 = undefined,
    stub_len: usize = 0,

    const Mode = enum { b64_encode, b64_decode, qp_encode, qp_decode };
    const OPT_BINARY: u32 = 1;
    const OPT_FORCE_ENCODE_FIRST: u32 = 2;

    fn deinit(self: *Convert, a: Allocator) void {
        if (self.lbchars) |l| a.free(l);
    }

    fn lb(self: *const Convert) []const u8 {
        return self.lbchars orelse "";
    }

    // the converter step: input from in (null for the final flush), output
    // into out; both advance past what was used
    fn convert(self: *Convert, in: ?*[]const u8, out: *[]u8) ConvErr {
        return switch (self.mode) {
            .b64_encode => if (in) |p| self.b64Encode(p, out) else self.b64EncodeFlush(out),
            .b64_decode => if (in) |p| self.b64Decode(p, out) else if (self.eos or self.urem_nbits == 0) .success else .unexpected_eos,
            .qp_encode => if (in) |p| self.qpEncode(p, out) else .success,
            .qp_decode => if (in) |p| self.qpDecode(p, out) else if (self.scan_stat != 0) .unexpected_eos else .success,
        };
    }

    const b64_enc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    fn put(out: *[]u8, c: u8) void {
        out.*[0] = c;
        out.* = out.*[1..];
    }

    fn putSlice(out: *[]u8, s: []const u8) void {
        @memcpy(out.*[0..s.len], s);
        out.* = out.*[s.len..];
    }

    fn b64EncodeFlush(self: *Convert, out: *[]u8) ConvErr {
        var line_ccnt = self.line_ccnt;
        defer self.line_ccnt = line_ccnt;
        if (self.erem_len == 0) return .success;
        if (line_ccnt < 4 and self.lbchars != null) {
            if (out.len < self.lb().len) return .too_big;
            putSlice(out, self.lb());
            line_ccnt = self.line_len;
        }
        if (out.len < 4) return .too_big;
        const e = self.erem;
        put(out, b64_enc[e[0] >> 2]);
        if (self.erem_len == 1) {
            put(out, b64_enc[(e[0] << 4) & 0x3f]);
            put(out, '=');
        } else {
            put(out, b64_enc[((e[0] << 4) | (e[1] >> 4)) & 0x3f]);
            put(out, b64_enc[(e[1] << 2) & 0x3f]);
        }
        put(out, '=');
        self.erem_len = 0;
        line_ccnt -%= 4;
        return .success;
    }

    fn b64Encode(self: *Convert, in: *[]const u8, out: *[]u8) ConvErr {
        var ps = in.*;
        var line_ccnt = self.line_ccnt;
        var err: ConvErr = .success;
        defer {
            in.* = ps;
            self.line_ccnt = line_ccnt;
        }
        switch (self.erem_len) {
            1 => if (ps.len >= 2) {
                if (line_ccnt < 4 and self.lbchars != null) {
                    if (out.len < self.lb().len) return .too_big;
                    putSlice(out, self.lb());
                    line_ccnt = self.line_len;
                }
                if (out.len < 4) return .too_big;
                const e0 = self.erem[0];
                put(out, b64_enc[e0 >> 2]);
                put(out, b64_enc[((e0 << 4) | (ps[0] >> 4)) & 0x3f]);
                put(out, b64_enc[((ps[0] << 2) | (ps[1] >> 6)) & 0x3f]);
                put(out, b64_enc[ps[1] & 0x3f]);
                ps = ps[2..];
                self.erem_len = 0;
                line_ccnt -%= 4;
            },
            2 => if (ps.len >= 1) {
                if (self.line_ccnt < 4 and self.lbchars != null) {
                    if (out.len < self.lb().len) return .too_big;
                    putSlice(out, self.lb());
                    line_ccnt = self.line_len;
                }
                if (out.len < 4) return .too_big;
                const e = self.erem;
                put(out, b64_enc[e[0] >> 2]);
                put(out, b64_enc[((e[0] << 4) | (e[1] >> 4)) & 0x3f]);
                put(out, b64_enc[((e[1] << 2) | (ps[0] >> 6)) & 0x3f]);
                put(out, b64_enc[ps[0] & 0x3f]);
                ps = ps[1..];
                self.erem_len = 0;
                line_ccnt -%= 4;
            },
            else => {},
        }
        while (ps.len >= 3) {
            if (line_ccnt < 4 and self.lbchars != null) {
                if (out.len < self.lb().len) {
                    err = .too_big;
                    return err;
                }
                putSlice(out, self.lb());
                line_ccnt = self.line_len;
            }
            if (out.len < 4) return .too_big;
            put(out, b64_enc[ps[0] >> 2]);
            put(out, b64_enc[((ps[0] << 4) | (ps[1] >> 4)) & 0x3f]);
            put(out, b64_enc[((ps[1] << 2) | (ps[2] >> 6)) & 0x3f]);
            put(out, b64_enc[ps[2] & 0x3f]);
            ps = ps[3..];
            line_ccnt -%= 4;
        }
        for (ps) |c| {
            self.erem[self.erem_len] = c;
            self.erem_len += 1;
        }
        ps = ps[ps.len..];
        return err;
    }

    fn b64Dec(c: u8) u32 {
        return switch (c) {
            'A'...'Z' => c - 'A',
            'a'...'z' => c - 'a' + 26,
            '0'...'9' => c - '0' + 52,
            '+' => 62,
            '/' => 63,
            '=' => 128,
            else => 64,
        };
    }

    fn bmask(n: u32) u32 {
        return @as(u32, 0xffff) >> @intCast(16 - n);
    }

    fn b64Decode(self: *Convert, in: *[]const u8, out: *[]u8) ConvErr {
        var err: ConvErr = .success;
        var ps = in.*;
        var urem = self.urem;
        var urem_nbits = self.urem_nbits;
        var ustat = self.ustat;
        var pack: u32 = 0;
        var pack_bcnt: u32 = 8;
        while (true) {
            if (pack_bcnt >= urem_nbits) {
                pack_bcnt -= urem_nbits;
                pack |= urem << @intCast(pack_bcnt);
                urem_nbits = 0;
            } else {
                urem_nbits -= pack_bcnt;
                pack |= urem >> @intCast(urem_nbits);
                urem &= bmask(urem_nbits);
                pack_bcnt = 0;
            }
            if (pack_bcnt > 0) {
                if (ps.len < 1) break;
                const i = b64Dec(ps[0]);
                ps = ps[1..];
                ustat |= i & 0x80;
                if (i & 0xc0 == 0) {
                    if (ustat != 0) {
                        err = .invalid_seq;
                        break;
                    }
                    if (6 <= pack_bcnt) {
                        pack_bcnt -= 6;
                        pack |= i << @intCast(pack_bcnt);
                        urem = 0;
                    } else {
                        urem_nbits = 6 - pack_bcnt;
                        pack |= i >> @intCast(urem_nbits);
                        urem = i & bmask(urem_nbits);
                        pack_bcnt = 0;
                    }
                } else if (ustat != 0) {
                    if (pack_bcnt == 8 or pack_bcnt == 2) {
                        err = .invalid_seq;
                        break;
                    }
                    self.eos = true;
                }
            }
            if ((pack_bcnt | ustat) == 0) {
                if (out.len < 1) {
                    err = .too_big;
                    break;
                }
                put(out, @truncate(pack));
                pack = 0;
                pack_bcnt = 8;
            }
        }
        if (urem_nbits >= pack_bcnt) {
            urem |= pack << @intCast(urem_nbits - pack_bcnt);
        } else {
            urem |= pack >> @intCast(pack_bcnt - urem_nbits);
        }
        urem_nbits += 8 - pack_bcnt;
        self.urem = urem;
        self.urem_nbits = urem_nbits;
        self.ustat = ustat;
        in.* = ps;
        return err;
    }

    fn qpEncode(self: *Convert, in: *[]const u8, out: *[]u8) ConvErr {
        const digits = "0123456789ABCDEF";
        var err: ConvErr = .success;
        var ps = in.*;
        var line_ccnt = self.line_ccnt;
        var lb_ptr = self.lb_ptr;
        var lb_cnt = self.lb_cnt;
        var trail_ws: u32 = 0;
        const opts = self.opts;
        const lbchars = self.lb();
        const has_lb = self.lbchars != null;
        while (true) {
            if (opts & OPT_BINARY == 0 and has_lb and lbchars.len > 0) {
                if (ps.len > 0 and ps[0] == lbchars[lb_cnt]) {
                    lb_cnt += 1;
                    if (lb_cnt >= lbchars.len) {
                        if (out.len < lb_cnt) {
                            lb_cnt -= 1;
                            err = .too_big;
                            break;
                        }
                        putSlice(out, lbchars[0..lb_cnt]);
                        line_ccnt = self.line_len;
                        lb_ptr = 0;
                        lb_cnt = 0;
                    }
                    ps = ps[1..];
                    continue;
                }
            }
            if (lb_ptr >= lb_cnt and ps.len == 0) break;
            const c: u32 = if (lb_ptr < lb_cnt) lbchars[lb_ptr] else ps[0];
            const consume = struct {
                fn f(p: *[]const u8, ptr: *u32, cnt: *u32) void {
                    if (ptr.* < cnt.*) {
                        ptr.* += 1;
                    } else {
                        cnt.* = 0;
                        ptr.* = 0;
                        p.* = p.*[1..];
                    }
                }
            }.f;
            if (opts & OPT_BINARY == 0 and trail_ws == 0 and (c == '\t' or c == ' ')) {
                if (line_ccnt < 2 and has_lb) {
                    if (out.len < lbchars.len + 1) {
                        err = .too_big;
                        break;
                    }
                    put(out, '=');
                    putSlice(out, lbchars);
                    line_ccnt = self.line_len;
                } else {
                    if (out.len < 1) {
                        err = .too_big;
                        break;
                    }
                    if (has_lb) {
                        var lb_cnt2: usize = 0;
                        trail_ws = 1;
                        var j: usize = ps.len -| 1;
                        var k: usize = 0;
                        while (j > 0) : ({
                            j -= 1;
                            k += 1;
                        }) {
                            const ch = ps[k];
                            if (ch == lbchars[lb_cnt2]) {
                                lb_cnt2 += 1;
                                if (lb_cnt2 >= lbchars.len) break;
                            } else if (lb_cnt2 != 0 or (ch != '\t' and ch != ' ')) {
                                trail_ws = 0;
                                break;
                            } else {
                                trail_ws += 1;
                            }
                        }
                    }
                    if (trail_ws == 0) {
                        put(out, @intCast(c));
                        line_ccnt -%= 1;
                        consume(&ps, &lb_ptr, &lb_cnt);
                    }
                }
            } else if ((opts & OPT_FORCE_ENCODE_FIRST == 0 or line_ccnt < self.line_len) and ((c >= 33 and c <= 60) or (c >= 62 and c <= 126))) {
                if (line_ccnt < 2 and has_lb) {
                    if (out.len < lbchars.len + 1) {
                        err = .too_big;
                        break;
                    }
                    put(out, '=');
                    putSlice(out, lbchars);
                    line_ccnt = self.line_len;
                }
                if (out.len < 1) {
                    err = .too_big;
                    break;
                }
                put(out, @intCast(c));
                line_ccnt -%= 1;
                consume(&ps, &lb_ptr, &lb_cnt);
            } else {
                if (line_ccnt < 4 and has_lb) {
                    if (out.len < lbchars.len + 1) {
                        err = .too_big;
                        break;
                    }
                    put(out, '=');
                    putSlice(out, lbchars);
                    line_ccnt = self.line_len;
                }
                if (out.len < 3) {
                    err = .too_big;
                    break;
                }
                put(out, '=');
                put(out, digits[c >> 4]);
                put(out, digits[c & 0x0f]);
                line_ccnt -%= 3;
                if (trail_ws > 0) trail_ws -= 1;
                consume(&ps, &lb_ptr, &lb_cnt);
            }
        }
        in.* = ps;
        self.line_ccnt = line_ccnt;
        self.lb_ptr = lb_ptr;
        self.lb_cnt = lb_cnt;
        return err;
    }

    fn qpDecode(self: *Convert, in: *[]const u8, out: *[]u8) ConvErr {
        var err: ConvErr = .success;
        var ps = in.*;
        var lb_ptr = self.lb_ptr;
        var lb_cnt = self.lb_cnt;
        var scan_stat = self.scan_stat;
        var next_char = self.next_char;
        const lbchars = self.lb();
        const has_lb = self.lbchars != null;
        loop: while (true) {
            switch (scan_stat) {
                0 => {
                    if (ps.len == 0) break :loop;
                    if (ps[0] == '=') {
                        scan_stat = 1;
                    } else {
                        if (out.len < 1) {
                            err = .too_big;
                            break :loop;
                        }
                        put(out, ps[0]);
                    }
                    ps = ps[1..];
                },
                1, 2, 3 => {
                    if (scan_stat == 1) {
                        if (ps.len == 0) break :loop;
                        if (ps[0] == ' ' or ps[0] == '\t') {
                            scan_stat = 4;
                            ps = ps[1..];
                            continue :loop;
                        } else if (!has_lb and lb_cnt == 0 and ps[0] == '\r') {
                            lb_cnt += 1;
                            scan_stat = 5;
                            ps = ps[1..];
                            continue :loop;
                        } else if (!has_lb and lb_cnt == 0 and ps[0] == '\n') {
                            lb_cnt = 0;
                            lb_ptr = 0;
                            scan_stat = 0;
                            ps = ps[1..];
                            continue :loop;
                        } else if (lb_cnt < lbchars.len and ps[0] == lbchars[lb_cnt]) {
                            lb_cnt += 1;
                            scan_stat = 5;
                            ps = ps[1..];
                            continue :loop;
                        }
                    }
                    if (scan_stat != 3) {
                        if (ps.len == 0) break :loop;
                        if (!std.ascii.isHex(ps[0])) {
                            err = .invalid_seq;
                            break :loop;
                        }
                        const ch = ps[0];
                        next_char = (next_char << 4) | (if (ch >= 'a') ch - 0x57 else if (ch >= 'A') ch - 0x37 else ch - 0x30);
                        scan_stat += 1;
                        ps = ps[1..];
                        if (scan_stat != 3) continue :loop;
                    }
                    if (out.len < 1) {
                        err = .too_big;
                        break :loop;
                    }
                    put(out, @truncate(next_char));
                    scan_stat = 0;
                },
                4 => {
                    if (ps.len == 0) break :loop;
                    if (lb_cnt < lbchars.len and ps[0] == lbchars[lb_cnt]) {
                        lb_cnt += 1;
                        scan_stat = 5;
                    } else if (ps[0] != '\t' and ps[0] != ' ') {
                        err = .invalid_seq;
                        break :loop;
                    }
                    ps = ps[1..];
                },
                5 => {
                    if (ps.len == 0) break :loop;
                    if (!has_lb and lb_cnt == 1 and ps[0] == '\n') {
                        lb_cnt = 0;
                        lb_ptr = 0;
                        scan_stat = 0;
                        ps = ps[1..];
                    } else if (!has_lb and lb_cnt > 0) {
                        lb_cnt = 0;
                        lb_ptr = 0;
                        scan_stat = 0;
                    } else if (lb_cnt >= lbchars.len) {
                        lb_cnt = 0;
                        lb_ptr = 0;
                        scan_stat = 0;
                    } else if (ps[0] == lbchars[lb_cnt]) {
                        lb_cnt += 1;
                        ps = ps[1..];
                    } else {
                        scan_stat = 6;
                    }
                },
                else => {
                    if (lb_ptr < lb_cnt) {
                        if (out.len < 1) {
                            err = .too_big;
                            break :loop;
                        }
                        put(out, lbchars[lb_ptr]);
                        lb_ptr += 1;
                    } else {
                        scan_stat = 0;
                        lb_cnt = 0;
                        lb_ptr = 0;
                    }
                },
            }
        }
        in.* = ps;
        self.scan_stat = scan_stat;
        self.lb_ptr = lb_ptr;
        self.lb_cnt = lb_cnt;
        self.next_char = next_char;
        return err;
    }
};

fn optString(ctx: *NativeContext, opts: ?*PhpArray, key: []const u8) RuntimeError!?[]u8 {
    const arr = opts orelse return null;
    const v = arr.get(.{ .string = Value.String.borrowed(key) });
    if (v == .null and !arr.contains(.{ .string = Value.String.borrowed(key) })) return null;
    return try toOwnedString(ctx, v);
}

fn optUint(opts: ?*PhpArray, key: []const u8) u32 {
    const arr = opts orelse return 0;
    if (!arr.contains(.{ .string = Value.String.borrowed(key) })) return 0;
    const n = Value.toInt(arr.get(.{ .string = Value.String.borrowed(key) }));
    return if (n < 0) 0 else @truncate(@as(u64, @intCast(n)));
}

fn optBool(opts: ?*PhpArray, key: []const u8) bool {
    const arr = opts orelse return false;
    return arr.get(.{ .string = Value.String.borrowed(key) }).isTruthy();
}

pub fn toOwnedString(ctx: *NativeContext, v: Value) RuntimeError![]u8 {
    switch (v) {
        .string => |s| return ctx.allocator.dupe(u8, s.bytes()),
        .object => |o| return ctx.allocator.dupe(u8, try ctx.vm.objectToString(o)),
        else => {
            var buf: std.ArrayListUnmanaged(u8) = .empty;
            errdefer buf.deinit(ctx.allocator);
            try v.format(&buf, ctx.allocator);
            return buf.toOwnedSlice(ctx.allocator);
        },
    }
}

fn createConvert(ctx: *NativeContext, name: []const u8, params: ?Value) RuntimeError!?*Filter {
    if (params) |p| if (p != .array) {
        try fs.warnDocref(ctx, "Stream filter ({s}): invalid filter parameter", .{name});
        return null;
    };
    const dot = std.mem.indexOfScalar(u8, name, '.') orelse return null;
    const kind = name[dot + 1 ..];
    const mode: Convert.Mode = if (std.ascii.eqlIgnoreCase(kind, "base64-encode"))
        .b64_encode
    else if (std.ascii.eqlIgnoreCase(kind, "base64-decode"))
        .b64_decode
    else if (std.ascii.eqlIgnoreCase(kind, "quoted-printable-encode"))
        .qp_encode
    else if (std.ascii.eqlIgnoreCase(kind, "quoted-printable-decode"))
        .qp_decode
    else
        return null;
    const opts: ?*PhpArray = if (params) |p| p.array else null;
    const c = try ctx.allocator.create(Convert);
    c.* = .{ .mode = mode };
    errdefer {
        c.deinit(ctx.allocator);
        ctx.allocator.destroy(c);
    }
    switch (mode) {
        .b64_encode, .qp_encode => if (opts != null) {
            var lbchars = try optString(ctx, opts, "line-break-chars");
            const line_len = optUint(opts, "line-length");
            if (line_len < 4) {
                if (lbchars) |l| ctx.allocator.free(l);
                lbchars = null;
            } else if (lbchars == null) {
                lbchars = try ctx.allocator.dupe(u8, "\r\n");
            }
            if (mode == .qp_encode) {
                if (optBool(opts, "binary")) c.opts |= Convert.OPT_BINARY;
                if (optBool(opts, "force-encode-first")) c.opts |= Convert.OPT_FORCE_ENCODE_FIRST;
            }
            if (lbchars) |l| {
                c.lbchars = l;
                c.line_len = line_len;
                c.line_ccnt = line_len;
            }
        },
        .qp_decode => if (opts != null) {
            c.lbchars = try optString(ctx, opts, "line-break-chars");
        },
        .b64_decode => {},
    }
    return try newFilter(ctx, name, .{ .convert = c });
}

// strfilter_convert_append_bucket: converts one input (null to flush) into
// buckets, growing the output buffer as the converter asks
fn convertAppend(ctx: *NativeContext, c: *Convert, f: *Filter, out: *Brigade, input: ?[]const u8, consumed: *usize) RuntimeError!bool {
    const a = ctx.allocator;
    const initial: usize = if (input) |i| i.len else 64;
    var buf_size = initial;
    var buf = try a.alloc(u8, buf_size);
    var used: usize = 0;
    var ps: []const u8 = input orelse "";
    var icnt: usize = if (input != null) ps.len else 1;
    errdefer a.free(buf);

    if (c.stub_len > 0) {
        var pt: []const u8 = c.stub[0..c.stub_len];
        while (pt.len > 0) {
            var o = buf[used..];
            const err = c.convert(&pt, &o);
            used = buf_size - o.len;
            switch (err) {
                .invalid_seq => {
                    try fs.warnDocref(ctx, "Stream filter ({s}): invalid byte sequence", .{f.name});
                    a.free(buf);
                    return false;
                },
                .more => {
                    if (input != null and icnt > 0) {
                        if (c.stub_len >= c.stub.len) {
                            try fs.warnDocref(ctx, "Stream filter ({s}): insufficient buffer", .{f.name});
                            a.free(buf);
                            return false;
                        }
                        c.stub[c.stub_len] = ps[0];
                        c.stub_len += 1;
                        ps = ps[1..];
                        icnt -= 1;
                        pt = c.stub[0..c.stub_len];
                    } else {
                        pt = pt[pt.len..];
                        break;
                    }
                },
                .unexpected_eos => {
                    try fs.warnDocref(ctx, "Stream filter ({s}): unexpected end of stream", .{f.name});
                    a.free(buf);
                    return false;
                },
                .too_big => {
                    buf_size <<= 1;
                    buf = try a.realloc(buf, buf_size);
                },
                .unknown => {
                    try fs.warnDocref(ctx, "Stream filter ({s}): unknown error", .{f.name});
                    a.free(buf);
                    return false;
                },
                .success => {},
            }
        }
        std.mem.copyForwards(u8, c.stub[0..pt.len], pt);
        c.stub_len = pt.len;
    }

    while (icnt > 0) {
        var o = buf[used..];
        const err = if (input == null) c.convert(null, &o) else c.convert(&ps, &o);
        used = buf_size - o.len;
        if (input != null) icnt = ps.len;
        switch (err) {
            .invalid_seq => {
                try fs.warnDocref(ctx, "Stream filter ({s}): invalid byte sequence", .{f.name});
                a.free(buf);
                return false;
            },
            .more => {
                if (input != null) {
                    if (icnt > c.stub.len) {
                        try fs.warnDocref(ctx, "Stream filter ({s}): insufficient buffer", .{f.name});
                        a.free(buf);
                        return false;
                    }
                    @memcpy(c.stub[0..icnt], ps);
                    c.stub_len = icnt;
                    ps = ps[icnt..];
                    icnt = 0;
                } else {
                    try fs.warnDocref(ctx, "Stream filter ({s}): unexpected octet values", .{f.name});
                    a.free(buf);
                    return false;
                }
            },
            .too_big => {
                buf_size <<= 1;
                buf = try a.realloc(buf, buf_size);
            },
            .unknown => {
                try fs.warnDocref(ctx, "Stream filter ({s}): unknown error", .{f.name});
                a.free(buf);
                return false;
            },
            // php's loop has no case for it: the flush just ends
            .unexpected_eos, .success => if (input == null) {
                icnt = 0;
            },
        }
    }
    if (used > 0) {
        buf = try a.realloc(buf, used);
        try out.append(try Bucket.adopt(a, buf));
    } else {
        a.free(buf);
    }
    consumed.* += (if (input) |i| i.len else 0) - icnt;
    return true;
}

fn convertFilter(ctx: *NativeContext, c: *Convert, f: *Filter, in: *Brigade, out: *Brigade, consumed: ?*usize, flags: Flags) RuntimeError!Status {
    var total: usize = 0;
    while (in.head) |b| {
        b.unlink();
        defer b.delref();
        if (!try convertAppend(ctx, c, f, out, b.buf, &total)) return .err_fatal;
    }
    if (flags == .flush_close) {
        if (!try convertAppend(ctx, c, f, out, null, &total)) return .err_fatal;
    }
    if (consumed) |p| p.* = total;
    return .pass_on;
}

// --- dechunk -------------------------------------------------------------------

const Dechunk = struct {
    chunk_size: usize = 0,
    state: State = .size_start,

    const State = enum { size_start, size, size_ext, size_cr, size_lf, body, body_cr, body_lf, trailer, err };

    fn hexDigit(c: u8) ?usize {
        return switch (c) {
            '0'...'9' => c - '0',
            'A'...'F' => c - 'A' + 10,
            'a'...'f' => c - 'a' + 10,
            else => null,
        };
    }

    // php_dechunk: decodes buf in place, returning the decoded length
    fn run(self: *Dechunk, buf: []u8) usize {
        var p: usize = 0;
        const end = buf.len;
        var out: usize = 0;
        while (p < end) {
            sw: switch (self.state) {
                .size_start, .size => {
                    if (self.state == .size_start) self.chunk_size = 0;
                    while (p < end) {
                        const digit = hexDigit(buf[p]) orelse {
                            if (self.state == .size_start) {
                                self.state = .err;
                            } else {
                                self.state = .size_ext;
                            }
                            break;
                        };
                        if (self.chunk_size > std.math.maxInt(usize) / 16) {
                            self.state = .err;
                            break;
                        }
                        self.chunk_size = self.chunk_size * 16 + digit;
                        self.state = .size;
                        p += 1;
                    }
                    if (self.state == .err) break :sw;
                    if (p == end) return out;
                    continue :sw .size_ext;
                },
                .size_ext => {
                    while (p < end and buf[p] != '\r' and buf[p] != '\n') p += 1;
                    if (p == end) return out;
                    continue :sw .size_cr;
                },
                .size_cr => {
                    if (buf[p] == '\r') {
                        p += 1;
                        if (p == end) {
                            self.state = .size_lf;
                            return out;
                        }
                    }
                    continue :sw .size_lf;
                },
                .size_lf => {
                    if (buf[p] == '\n') {
                        p += 1;
                        if (self.chunk_size == 0) {
                            self.state = .trailer;
                            break :sw;
                        } else if (p == end) {
                            self.state = .body;
                            return out;
                        }
                    } else {
                        self.state = .err;
                        break :sw;
                    }
                    continue :sw .body;
                },
                .body => {
                    if (end - p >= self.chunk_size) {
                        std.mem.copyForwards(u8, buf[out..][0..self.chunk_size], buf[p..][0..self.chunk_size]);
                        out += self.chunk_size;
                        p += self.chunk_size;
                        if (p == end) {
                            self.state = .body_cr;
                            return out;
                        }
                    } else {
                        std.mem.copyForwards(u8, buf[out..][0 .. end - p], buf[p..end]);
                        self.chunk_size -= end - p;
                        self.state = .body;
                        out += end - p;
                        return out;
                    }
                    continue :sw .body_cr;
                },
                .body_cr => {
                    if (buf[p] == '\r') {
                        p += 1;
                        if (p == end) {
                            self.state = .body_lf;
                            return out;
                        }
                    }
                    continue :sw .body_lf;
                },
                .body_lf => {
                    if (buf[p] == '\n') {
                        p += 1;
                        self.state = .size_start;
                    } else {
                        self.state = .err;
                    }
                },
                .trailer => p = end,
                .err => {
                    std.mem.copyForwards(u8, buf[out..][0 .. end - p], buf[p..end]);
                    out += end - p;
                    return out;
                },
            }
        }
        return out;
    }
};

// --- zlib.* --------------------------------------------------------------------

const ZlibData = struct {
    strm: zlib.z_stream,
    inbuf: [0x8000]u8 = undefined,
    outbuf: [0x8000]u8 = undefined,
    finished: bool = false,
};

const MAX_WBITS = 15;

fn createZlib(ctx: *NativeContext, name: []const u8, params: ?Value) RuntimeError!?*Filter {
    const z = try ctx.allocator.create(ZlibData);
    z.* = .{ .strm = std.mem.zeroes(zlib.z_stream) };
    z.strm.avail_out = z.outbuf.len;
    z.strm.next_out = &z.outbuf;
    z.strm.next_in = &z.inbuf;
    z.strm.avail_in = 0;
    z.strm.data_type = zlib.Z_ASCII;
    var status: c_int = zlib.Z_DATA_ERROR;
    var deflating = false;
    if (std.ascii.eqlIgnoreCase(name, "zlib.inflate")) {
        var window: c_int = -MAX_WBITS;
        if (params) |p| if (p == .array or p == .object) {
            if (hashGet(p, "window")) |w| {
                const tmp = Value.toInt(w);
                if (tmp < -MAX_WBITS or tmp > MAX_WBITS + 32) {
                    try fs.warnDocref(ctx, "Invalid parameter given for window size ({d})", .{tmp});
                } else window = @intCast(tmp);
            }
        };
        status = zlib.inflateInit2_(&z.strm, window, zlib.zlibVersion(), @sizeOf(zlib.z_stream));
    } else if (std.ascii.eqlIgnoreCase(name, "zlib.deflate")) {
        deflating = true;
        var level: c_int = zlib.Z_DEFAULT_COMPRESSION;
        var window: c_int = -MAX_WBITS;
        var mem_level: c_int = 9;
        if (params) |p| {
            var level_value: ?i64 = null;
            switch (p) {
                .array, .object => {
                    if (hashGet(p, "memory")) |m| {
                        const tmp = Value.toInt(m);
                        if (tmp < 1 or tmp > 9) try fs.warnDocref(ctx, "Invalid parameter given for memory level ({d})", .{tmp}) else mem_level = @intCast(tmp);
                    }
                    if (hashGet(p, "window")) |w| {
                        const tmp = Value.toInt(w);
                        if (tmp < -MAX_WBITS or tmp > MAX_WBITS + 16) try fs.warnDocref(ctx, "Invalid parameter given for window size ({d})", .{tmp}) else window = @intCast(tmp);
                    }
                    if (hashGet(p, "level")) |l| level_value = Value.toInt(l);
                },
                .string, .float, .int => level_value = Value.toInt(p),
                else => try fs.warnDocref(ctx, "Invalid filter parameter, ignored", .{}),
            }
            if (level_value) |tmp| {
                if (tmp < -1 or tmp > 9) try fs.warnDocref(ctx, "Invalid compression level specified. ({d})", .{tmp}) else level = @intCast(tmp);
            }
        }
        status = zlib.deflateInit2_(&z.strm, level, zlib.Z_DEFLATED, window, mem_level, 0, zlib.zlibVersion(), @sizeOf(zlib.z_stream));
        z.finished = true;
    }
    if (status != zlib.Z_OK) {
        ctx.allocator.destroy(z);
        return null;
    }
    return try newFilter(ctx, name, if (deflating) .{ .zlib_deflate = z } else .{ .zlib_inflate = z });
}

fn hashGet(v: Value, key: []const u8) ?Value {
    const k: PhpArray.Key = .{ .string = Value.String.borrowed(key) };
    switch (v) {
        .array => |arr| return if (arr.contains(k)) arr.get(k) else null,
        .object => |o| return if (o.properties.get(key)) |p| p else null,
        else => return null,
    }
}

fn zlibOut(a: Allocator, z: *ZlibData, out: *Brigade) RuntimeError!bool {
    if (z.strm.avail_out < z.outbuf.len) {
        const len = z.outbuf.len - z.strm.avail_out;
        try out.append(try Bucket.create(a, z.outbuf[0..len]));
        z.strm.avail_out = z.outbuf.len;
        z.strm.next_out = &z.outbuf;
        return true;
    }
    return false;
}

fn zlibInflate(ctx: *NativeContext, z: *ZlibData, in: *Brigade, out: *Brigade, consumed: ?*usize, flags: Flags) RuntimeError!Status {
    var exit_status: Status = .feed_me;
    var total: usize = 0;
    while (in.head) |head| {
        const b = try makeWriteable(head);
        var bin: usize = 0;
        while (bin < b.buf.len and !z.finished) {
            var desired: usize = @min(b.buf.len - bin, z.inbuf.len);
            @memcpy(z.inbuf[0..desired], b.buf[bin..][0..desired]);
            z.strm.next_in = &z.inbuf;
            z.strm.avail_in = @intCast(desired);
            const status = zlib.inflate(&z.strm, if (flags == .flush_close) zlib.Z_FINISH else zlib.Z_SYNC_FLUSH);
            if (status == zlib.Z_STREAM_END) {
                _ = zlib.inflateEnd(&z.strm);
                z.finished = true;
                exit_status = .pass_on;
            } else if (status != zlib.Z_OK and status != zlib.Z_BUF_ERROR) {
                try fs.noticeDocref(ctx, "zlib: {s}", .{std.mem.span(zlib.zError(status))});
                b.delref();
                z.strm.next_in = &z.inbuf;
                z.strm.avail_in = 0;
                return .err_fatal;
            }
            desired -= z.strm.avail_in;
            z.strm.next_in = &z.inbuf;
            z.strm.avail_in = 0;
            bin += desired;
            if (try zlibOut(ctx.allocator, z, out)) exit_status = .pass_on;
        }
        total += b.buf.len;
        b.delref();
    }
    if (!z.finished and flags == .flush_close) {
        var status: c_int = zlib.Z_OK;
        while (status == zlib.Z_OK) {
            status = zlib.inflate(&z.strm, zlib.Z_FINISH);
            if (try zlibOut(ctx.allocator, z, out)) exit_status = .pass_on;
        }
    }
    if (consumed) |p| p.* = total;
    return exit_status;
}

fn zlibDeflate(ctx: *NativeContext, z: *ZlibData, in: *Brigade, out: *Brigade, consumed: ?*usize, flags: Flags) RuntimeError!Status {
    var exit_status: Status = .feed_me;
    var total: usize = 0;
    while (in.head) |head| {
        const b = try makeWriteable(head);
        var bin: usize = 0;
        while (bin < b.buf.len) {
            var desired: usize = @min(b.buf.len - bin, z.inbuf.len);
            @memcpy(z.inbuf[0..desired], b.buf[bin..][0..desired]);
            z.strm.next_in = &z.inbuf;
            z.strm.avail_in = @intCast(desired);
            const flush_mode: c_int = switch (flags) {
                .flush_close => zlib.Z_FULL_FLUSH,
                .flush_inc => zlib.Z_SYNC_FLUSH,
                .normal => zlib.Z_NO_FLUSH,
            };
            z.finished = flush_mode != zlib.Z_NO_FLUSH;
            if (zlib.deflate(&z.strm, flush_mode) != zlib.Z_OK) {
                b.delref();
                return .err_fatal;
            }
            desired -= z.strm.avail_in;
            z.strm.next_in = &z.inbuf;
            z.strm.avail_in = 0;
            bin += desired;
            if (try zlibOut(ctx.allocator, z, out)) exit_status = .pass_on;
        }
        total += b.buf.len;
        b.delref();
    }
    if (flags == .flush_close or (flags == .flush_inc and !z.finished)) {
        var status: c_int = zlib.Z_OK;
        while (status == zlib.Z_OK) {
            status = zlib.deflate(&z.strm, if (flags == .flush_close) zlib.Z_FINISH else zlib.Z_SYNC_FLUSH);
            z.finished = true;
            if (try zlibOut(ctx.allocator, z, out)) exit_status = .pass_on;
        }
    }
    if (consumed) |p| p.* = total;
    return exit_status;
}

// --- user filters --------------------------------------------------------------

// zend_call_method_if_exists: the method, or __call; null when neither
pub fn callIfExists(ctx: *NativeContext, obj: *PhpObject, method: []const u8, args: []const Value) RuntimeError!?Value {
    if (ctx.vm.hasMethod(obj.class_name, method)) return try ctx.vm.callMethod(obj, method, args);
    if (ctx.vm.hasMethod(obj.class_name, "__call")) {
        const arr = try ctx.createArray();
        for (args) |a| try arr.append(ctx.allocator, a);
        return try ctx.vm.callMethod(obj, "__call", &.{ .{ .string = Value.String.borrowed(method) }, .{ .array = arr } });
    }
    return null;
}

fn createUserFilter(ctx: *NativeContext, name: []const u8, class_arg: []const u8, params: ?Value) RuntimeError!?*Filter {
    var class = class_arg;
    if (!ctx.vm.classes.contains(class)) {
        try ctx.vm.tryAutoload(class);
        if (!ctx.vm.classes.contains(class)) {
            try fs.warnDocref(ctx, "User-filter \"{s}\" requires class \"{s}\", but that class is not defined", .{ name, class });
            return null;
        }
    }
    class = ctx.vm.declaredClassName(class);
    // an object whose defaults fail to evaluate is no filter; the exception
    // waits for the caller
    const obj = ctx.createObject(class) catch |err| {
        if (err == error.RuntimeError and ctx.vm.pending_exception != null) return null;
        return err;
    };
    obj.retain();
    var keep = false;
    defer if (!keep) ctx.vm.releaseValue(.{ .object = obj });
    try obj.setCopiedString(ctx.allocator, "filtername", name);
    try obj.set(ctx.allocator, "params", params orelse .null);
    const ret = try callIfExists(ctx, obj, "onCreate", &.{});
    if (ret) |r| if (r == .bool and !r.bool) return null;
    keep = true;
    return try newFilter(ctx, name, .{ .user = obj });
}

fn userFilter(ctx: *NativeContext, stream_obj: *PhpObject, f: *Filter, obj: *PhpObject, in: *Brigade, out: *Brigade, consumed: ?*usize, flags: Flags) RuntimeError!Status {
    _ = f;
    const s = streams.get(stream_obj);
    if (s) |st| st.busy += 1;
    defer if (s) |st| {
        st.busy -= 1;
    };
    const has_stream = obj.properties.contains("stream") or ctx.vm.classDeclaresProperty(obj.class_name, "stream");
    if (has_stream) {
        // a stream on its way out (freed, or closed at shutdown) is no stream
        const stream_value: Value = if (streams.at_shutdown or value_mod.resourceClosed(stream_obj)) .null else .{ .resource = stream_obj };
        if (!try assignStreamProperty(ctx, obj, stream_value)) {
            if (in.head != null) try fs.warnDocref(ctx, "Unprocessed filter buckets remaining on input brigade", .{});
            return .err_fatal;
        }
    }
    const in_res = try brigadeResource(ctx, in);
    const out_res = try brigadeResource(ctx, out);
    defer {
        in_res.native = .{};
        out_res.native = .{};
    }
    var args = [_]Value{ .{ .resource = in_res }, .{ .resource = out_res }, if (consumed) |p| .{ .int = @intCast(p.*) } else .null, .{ .bool = flags == .flush_close } };
    var ret: Status = .err_fatal;
    const result = try ctx.vm.callMethodRef(obj, "filter", &args);
    ret = switch (Value.toInt(result)) {
        0 => .err_fatal,
        1 => .feed_me,
        2 => .pass_on,
        else => .err_fatal,
    };
    if (consumed) |p| {
        const n = Value.toInt(args[2]);
        p.* = if (n < 0) 0 else @intCast(n);
    }
    if (in.head != null) try fs.warnDocref(ctx, "Unprocessed filter buckets remaining on input brigade", .{});
    if (has_stream) _ = try assignStreamProperty(ctx, obj, .null);
    return ret;
}

// the filter's $stream: written as the filter's own class would, so a
// typed property refuses a resource with php's TypeError
fn assignStreamProperty(ctx: *NativeContext, obj: *PhpObject, v: Value) RuntimeError!bool {
    return assignTypedProperty(ctx, obj, "stream", v);
}

// a property php's engine writes for an object (add_property_*): the
// declared type is checked as php's write does, false with the TypeError
// pending when it refuses the value
pub fn assignTypedProperty(ctx: *NativeContext, obj: *PhpObject, comptime name: []const u8, v: Value) RuntimeError!bool {
    const vr = ctx.vm.findPropertyVisibility(obj.class_name, name);
    if (vr.declared and vr.type_str.len > 0 and v != .null) {
        if (try ctx.vm.propertyTypeAccepts(v, vr.type_str, vr.defining_class, false) == null) {
            const shown = try ctx.vm.propertyTypeText(vr.type_str, vr.defining_class);
            const msg = try std.fmt.allocPrint(ctx.allocator, "Cannot assign {s} to property {s}::$" ++ name ++ " of type {s}", .{ v.typeName(), ctx.vm.declaredClassName(vr.defining_class), shown });
            defer ctx.allocator.free(msg);
            try ctx.vm.setPendingException("TypeError", msg);
            return false;
        }
    }
    try obj.setForScope(ctx.allocator, name, v, if (vr.declared) vr.defining_class else null);
    return true;
}

fn brigadeResource(ctx: *NativeContext, brigade: *Brigade) RuntimeError!*PhpObject {
    const r = try ctx.createResource("StreamBrigade");
    r.native = .{ .kind = .stream_brigade, .ptr = @intFromPtr(brigade) };
    return r;
}

fn bucketResource(ctx: *NativeContext, bucket: *Bucket) RuntimeError!*PhpObject {
    const r = try ctx.createResource("StreamBucketResource");
    r.native = .{ .kind = .stream_bucket, .ptr = @intFromPtr(bucket) };
    return r;
}

fn cleanupBucketResource(obj: *PhpObject) bool {
    if (obj.native.get(Bucket, .stream_bucket)) |b| b.delref();
    obj.native = .{};
    return true;
}

fn cleanupBrigadeResource(obj: *PhpObject) bool {
    obj.native = .{};
    return true;
}

fn cleanupFilterResource(obj: *PhpObject) bool {
    obj.native = .{};
    return true;
}

// a StreamBucket object for the bucket: its resource, data and lengths
fn bucketObject(ctx: *NativeContext, bucket: *Bucket) RuntimeError!*PhpObject {
    const res = try bucketResource(ctx, bucket);
    const obj = try ctx.createObject("StreamBucket");
    try obj.set(ctx.allocator, "bucket", .{ .resource = res });
    try obj.setCopiedString(ctx.allocator, "data", bucket.buf);
    try obj.set(ctx.allocator, "datalen", .{ .int = @intCast(bucket.buf.len) });
    try obj.set(ctx.allocator, "dataLength", .{ .int = @intCast(bucket.buf.len) });
    return obj;
}

fn brigadeArg(ctx: *NativeContext, args: []const Value, comptime func: []const u8) RuntimeError!?*Brigade {
    const v: Value = if (args.len > 0) args[0] else .null;
    if (v != .resource) return throwType(ctx, func ++ "(): Argument #1 ($brigade) must be of type resource, {s} given", .{v.valueName()});
    if (v.resource.native.get(Brigade, .stream_brigade)) |b| return b;
    return throwType(ctx, func ++ "(): supplied resource is not a valid userfilter.bucket brigade resource", .{});
}

fn throwType(ctx: *NativeContext, comptime fmt: []const u8, args: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("TypeError", msg);
    return error.RuntimeError;
}

fn native_stream_bucket_make_writeable(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const brigade = (try brigadeArg(ctx, args, "stream_bucket_make_writeable")).?;
    const head = brigade.head orelse return NativeResult.scalar(.null);
    const bucket = try makeWriteable(head);
    return NativeResult.borrowed(.{ .object = try bucketObject(ctx, bucket) });
}

fn attachBucket(ctx: *NativeContext, args: []const Value, comptime func: []const u8, at_end: bool) RuntimeError!NativeResult {
    const brigade = (try brigadeArg(ctx, args, func)).?;
    const v: Value = if (args.len > 1) args[1] else .null;
    if (v != .object or !ctx.vm.isInstanceOf(v.object.class_name, "StreamBucket"))
        return throwType(ctx, func ++ "(): Argument #2 ($bucket) must be of type StreamBucket, {s} given", .{v.valueName()});
    const obj = v.object;
    const res = obj.get("bucket");
    if (res != .resource) return throwType(ctx, func ++ "(): Argument #2 ($bucket) must be of type resource, {s} given", .{res.valueName()});
    var bucket = res.resource.native.get(Bucket, .stream_bucket) orelse
        return throwType(ctx, func ++ "(): supplied resource is not a valid userfilter.bucket resource", .{});
    const data = obj.rawForScope("data", null);
    if (data == .undef or obj.isUnset("data")) {
        try ctx.vm.setPendingException("Error", "Typed property StreamBucket::$data must not be accessed before initialization");
        return error.RuntimeError;
    }
    if (data == .string) {
        if (!std.mem.eql(u8, bucket.buf, data.string.bytes())) {
            try bucket.resize(data.string.bytes().len);
            @memcpy(bucket.buf, data.string.bytes());
        }
    }
    if (bucket.brigade != null) bucket.unlink() else bucket.refcount += 1;
    if (at_end) try brigade.append(bucket) else brigade.prepend(bucket);
    _ = &bucket;
    return NativeResult.scalar(.null);
}

fn native_stream_bucket_append(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return attachBucket(ctx, args, "stream_bucket_append", true);
}

fn native_stream_bucket_prepend(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return attachBucket(ctx, args, "stream_bucket_prepend", false);
}

fn native_stream_bucket_new(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = try fs.streamArg(ctx, args, .{ .func = "stream_bucket_new" });
    const data = try @import("strings.zig").stringParam(ctx, "stream_bucket_new", args, 1, "buffer");
    const bucket = try Bucket.create(ctx.allocator, data);
    return NativeResult.borrowed(.{ .object = try bucketObject(ctx, bucket) });
}

fn native_stream_get_filters(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    try registeredFilters(ctx.vm, arr, ctx.allocator);
    return NativeResult.borrowed(.{ .array = arr });
}

fn native_stream_filter_register(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const p = @import("html.zig").Params{ .ctx = ctx, .func = "stream_filter_register", .args = args };
    const name = try p.string(0, "filter_name", "");
    const class = try p.string(1, "class", "");
    if (name.len == 0) {
        try ctx.vm.setPendingException("ValueError", "stream_filter_register(): Argument #1 ($filter_name) must be a non-empty string");
        return error.RuntimeError;
    }
    if (class.len == 0) {
        try ctx.vm.setPendingException("ValueError", "stream_filter_register(): Argument #2 ($class) must be a non-empty string");
        return error.RuntimeError;
    }
    const map = &ctx.vm.stream_filters_user;
    if (map.contains(name) or builtinFactory(name) != null) return NativeResult.scalar(.{ .bool = false });
    try map.put(ctx.allocator, try ctx.allocator.dupe(u8, name), try ctx.allocator.dupe(u8, class));
    return NativeResult.scalar(.{ .bool = true });
}

const STREAM_FILTER_READ: i64 = 1;
const STREAM_FILTER_WRITE: i64 = 2;

fn applyFilter(ctx: *NativeContext, args: []const Value, comptime func: []const u8, at_end: bool) RuntimeError!NativeResult {
    const stream_obj = try fs.streamArg(ctx, args, .{ .func = func });
    const p = @import("html.zig").Params{ .ctx = ctx, .func = func, .args = args };
    const name = try p.string(1, "filter_name", "");
    var read_write = try p.int(2, "mode", 0);
    const params: ?Value = if (args.len > 3) args[3] else null;
    const s = try streams.of(ctx, stream_obj);
    if (read_write & 3 == 0) {
        const mode_v = stream_obj.get("__mode");
        const mode = if (mode_v == .string) mode_v.string.bytes() else "r";
        if (std.mem.indexOfAny(u8, mode, "r+") != null) read_write |= STREAM_FILTER_READ;
        if (std.mem.indexOfAny(u8, mode, "w+a") != null) read_write |= STREAM_FILTER_WRITE;
    }
    var last: ?*Filter = null;
    if (read_write & STREAM_FILTER_READ != 0) {
        const f = (try create(ctx, name, params)) orelse return NativeResult.scalar(.{ .bool = false });
        if (at_end) {
            if (!try append(ctx, stream_obj, &s.readfilters, f)) {
                try remove(ctx, f);
                return NativeResult.scalar(.{ .bool = false });
            }
        } else prepend(&s.readfilters, f);
        last = f;
    }
    if (read_write & STREAM_FILTER_WRITE != 0) {
        const f = (try create(ctx, name, params)) orelse return NativeResult.scalar(.{ .bool = false });
        if (at_end) {
            if (!try append(ctx, stream_obj, &s.writefilters, f)) {
                try remove(ctx, f);
                return NativeResult.scalar(.{ .bool = false });
            }
        } else prepend(&s.writefilters, f);
        last = f;
    }
    const f = last orelse return NativeResult.scalar(.{ .bool = false });
    const res = try ctx.createResource("StreamFilter");
    res.native = .{ .kind = .stream_filter, .ptr = @intFromPtr(f) };
    // the stream holds the resource as long as the filter lives
    res.retain();
    f.resource = res;
    return NativeResult.borrowed(.{ .resource = res });
}

fn native_stream_filter_append(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return applyFilter(ctx, args, "stream_filter_append", true);
}

fn native_stream_filter_prepend(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return applyFilter(ctx, args, "stream_filter_prepend", false);
}

fn native_stream_filter_remove(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const v: Value = if (args.len > 0) args[0] else .null;
    if (v != .resource) return throwType(ctx, "stream_filter_remove(): Argument #1 ($stream_filter) must be of type resource, {s} given", .{v.valueName()});
    const f = v.resource.native.get(Filter, .stream_filter) orelse
        return throwType(ctx, "stream_filter_remove(): supplied resource is not a valid stream filter resource", .{});
    if (!try flushFilter(ctx, f, true)) {
        try fs.warnDocref(ctx, "Unable to flush filter, not removing", .{});
        return NativeResult.scalar(.{ .bool = false });
    }
    try remove(ctx, f);
    return NativeResult.scalar(.{ .bool = true });
}

pub const entries = .{
    .{ "stream_bucket_make_writeable", native_stream_bucket_make_writeable },
    .{ "stream_bucket_append", native_stream_bucket_append },
    .{ "stream_bucket_prepend", native_stream_bucket_prepend },
    .{ "stream_bucket_new", native_stream_bucket_new },
    .{ "stream_get_filters", native_stream_get_filters },
    .{ "stream_filter_register", native_stream_filter_register },
    .{ "stream_filter_append", native_stream_filter_append },
    .{ "stream_filter_prepend", native_stream_filter_prepend },
    .{ "stream_filter_remove", native_stream_filter_remove },
};

fn filterMethod(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    _ = ctx;
    return NativeResult.scalar(.{ .int = 0 });
}

fn onCreateMethod(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = true });
}

fn onCloseMethod(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.null);
}

pub fn register(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "php_user_filter" };
    try def.properties.append(a, .{ .name = "filtername", .default = .{ .string = Value.String.borrowed("") }, .has_default = true, .type_str = "string" });
    try def.properties.append(a, .{ .name = "params", .default = .{ .string = Value.String.borrowed("") }, .has_default = true, .type_str = "mixed" });
    try def.properties.append(a, .{ .name = "stream", .default = .null, .has_default = true });
    try def.methods.put(a, "filter", .{ .name = "filter", .arity = 4 });
    try def.methods.put(a, "onCreate", .{ .name = "onCreate", .arity = 0 });
    try def.methods.put(a, "onClose", .{ .name = "onClose", .arity = 0 });
    try vm.classes.put(a, "php_user_filter", def);
    try vm.native_fns.put(a, "php_user_filter::filter", filterMethod);
    try vm.native_fns.put(a, "php_user_filter::onCreate", onCreateMethod);
    try vm.native_fns.put(a, "php_user_filter::onClose", onCloseMethod);

    var bucket_def = ClassDef{ .name = "StreamBucket", .is_final = true };
    try bucket_def.properties.append(a, .{ .name = "bucket", .default = .null, .has_default = true });
    try bucket_def.properties.append(a, .{ .name = "data", .default = .null, .type_str = "string" });
    try bucket_def.properties.append(a, .{ .name = "datalen", .default = .null, .type_str = "int" });
    try bucket_def.properties.append(a, .{ .name = "dataLength", .default = .null, .type_str = "int" });
    try vm.classes.put(a, "StreamBucket", bucket_def);

    try vm.classes.put(a, "StreamFilter", ClassDef{ .name = "StreamFilter", .native_cleanup = cleanupFilterResource });
    try vm.classes.put(a, "StreamBrigade", ClassDef{ .name = "StreamBrigade", .native_cleanup = cleanupBrigadeResource });
    try vm.classes.put(a, "StreamBucketResource", ClassDef{ .name = "StreamBucketResource", .native_cleanup = cleanupBucketResource });
}
