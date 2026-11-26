// zlib's output compression (ext/zlib/zlib.c): the "zlib output compression"
// handler that zlib.output_compression starts, its ob_gzhandler alias, and
// the legacy ob_gzhandler() function. the coding comes from the request's
// Accept-Encoding, read from $_SERVER once it names gzip or deflate
const std = @import("std");
const zlib = @import("c_zlib");
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const Value = @import("../runtime/value.zig").Value;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const handler_name = "zlib output compression";

// PHP_ZLIB_ENCODING_GZIP and _DEFLATE, the window bits deflateInit2 takes
pub const coding_gzip: u8 = 0x1f;
pub const coding_deflate: u8 = 0x0f;

// php_output.h's handler operations
const op_start: i64 = 1;
const op_clean: i64 = 2;
const op_flush: i64 = 4;
const op_final: i64 = 8;

// PHP_OUTPUT_HANDLER_DEFAULT_SIZE
pub const default_size: usize = 0x4000;

pub const entries = .{
    .{ "ob_gzhandler", native_ob_gzhandler },
    .{ "zlib_get_coding_type", native_zlib_get_coding_type },
};

// php_zlib_context for output: the deflate stream and the input it has not
// consumed yet
pub const Context = struct {
    strm: zlib.z_stream = std.mem.zeroes(zlib.z_stream),
    // deflateInit2 ran and deflateEnd hasn't
    live: bool = false,
    pending: std.ArrayListUnmanaged(u8) = .empty,

    fn end(self: *Context) void {
        if (self.live) _ = zlib.deflateEnd(&self.strm);
        self.live = false;
    }

    pub fn destroy(self: *Context, a: std.mem.Allocator) void {
        self.end();
        self.pending.deinit(a);
        a.destroy(self);
    }
};

// php_zlib_output_encoding: 0 while the request asks for neither coding
pub fn encoding(vm: *VM) u8 {
    if (vm.zlib_coding != 0) return vm.zlib_coding;
    if (vm.response_headers_dropped) return 0;
    const server = vm.request_vars.get("$_SERVER") orelse return 0;
    if (server != .array) return 0;
    const enc = server.array.get(.{ .string = Value.String.borrowed("HTTP_ACCEPT_ENCODING") });
    if (enc != .string) return 0;
    const text = enc.string.bytes();
    if (std.mem.indexOf(u8, text, "gzip") != null) {
        vm.zlib_coding = coding_gzip;
    } else if (std.mem.indexOf(u8, text, "deflate") != null) {
        vm.zlib_coding = coding_deflate;
    }
    return vm.zlib_coding;
}

fn compressionLevel(vm: *VM) c_int {
    const text = std.mem.trim(u8, vm.iniText("zlib.output_compression_level"), " \t");
    const n = std.fmt.parseInt(c_int, text, 10) catch return -1;
    return n;
}

fn init(vm: *VM, ctx: *Context) bool {
    ctx.end();
    if (zlib.deflateInit2_(&ctx.strm, compressionLevel(vm), zlib.Z_DEFLATED, vm.zlib_coding, 9, zlib.Z_DEFAULT_STRATEGY, zlib.zlibVersion(), @sizeOf(zlib.z_stream)) != zlib.Z_OK) return false;
    ctx.live = true;
    return true;
}

// PHP_ZLIB_BUFFER_SIZE_GUESS
fn sizeGuess(n: usize) usize {
    return @as(usize, @intFromFloat(@as(f64, @floatFromInt(n)) * 1.015)) + 10 + 8 + 4 + 1;
}

// php_zlib_output_handler_ex: false for FAILURE. out gets the compressed
// bytes (owned), possibly none
pub fn handlerEx(vm: *VM, ctx: *Context, op: i64, input: []const u8, out: *?[]u8) RuntimeError!bool {
    const a = vm.allocator;
    if (op & op_start != 0 and !init(vm, ctx)) return false;
    if (op & op_clean != 0) {
        ctx.end();
        if (op & op_final != 0) return true;
        if (!init(vm, ctx)) return false;
        ctx.pending.clearRetainingCapacity();
        return true;
    }
    try ctx.pending.appendSlice(a, input);
    const buf = try a.alloc(u8, sizeGuess(input.len));
    var keep = false;
    defer if (!keep) a.free(buf);
    ctx.strm.avail_in = @intCast(ctx.pending.items.len);
    ctx.strm.next_in = ctx.pending.items.ptr;
    ctx.strm.avail_out = @intCast(buf.len);
    ctx.strm.next_out = buf.ptr;
    const flags: c_int = if (op & op_final != 0) zlib.Z_FINISH else if (op & op_flush != 0) zlib.Z_FULL_FLUSH else zlib.Z_SYNC_FLUSH;
    // a stream deflateEnd already closed (a failed or finished level) fails
    if (!ctx.live) return false;
    switch (zlib.deflate(&ctx.strm, flags)) {
        zlib.Z_OK, zlib.Z_STREAM_END => |rc| {
            if (rc == zlib.Z_OK and flags == zlib.Z_FINISH) {
                ctx.end();
                return false;
            }
            const left: usize = ctx.strm.avail_in;
            const done = ctx.pending.items.len - left;
            std.mem.copyForwards(u8, ctx.pending.items[0..left], ctx.pending.items[done..]);
            ctx.pending.shrinkRetainingCapacity(left);
            const produced = buf.len - ctx.strm.avail_out;
            keep = true;
            out.* = a.realloc(buf, produced) catch buf[0..produced];
        },
        else => {
            ctx.end();
            return false;
        },
    }
    if (op & op_final != 0) ctx.end();
    return true;
}

// php_zlib_output_handler, for a level: false for FAILURE (the level's
// bytes pass below unchanged and it is disabled). once it sent its headers
// the level becomes immutable (PHP_OUTPUT_HANDLER_HOOK_IMMUTABLE: neither
// cleanable nor removable)
pub fn levelHandler(vm: *VM, ctx: *Context, level_started: bool, op: i64, input: []const u8, out: *?[]u8, immutable: *bool) RuntimeError!bool {
    if (encoding(vm) == 0) {
        // "Vary: Accept-Encoding" goes only with compressed content, or
        // unless the whole buffer is discarded
        if (op & op_start != 0 and op != (op_start | op_clean | op_final)) try addHeader(vm, "Vary: Accept-Encoding", false);
        return false;
    }
    if (!try handlerEx(vm, ctx, op, input, out)) return false;
    if (op & op_clean == 0 or (op & op_start != 0 and op & op_final == 0)) {
        // only run this once
        if (!level_started) {
            try vm.noteTopLevelOutput();
            if (vm.headers_sent or !compressionOn(vm)) {
                ctx.end();
                freeOut(vm, out);
                return false;
            }
            try addHeader(vm, if (vm.zlib_coding == coding_gzip) "Content-Encoding: gzip" else "Content-Encoding: deflate", true);
            try addHeader(vm, "Vary: Accept-Encoding", false);
            immutable.* = true;
        }
    }
    return true;
}

fn freeOut(vm: *VM, out: *?[]u8) void {
    if (out.*) |o| vm.allocator.free(o);
    out.* = null;
}

// ZLIBG(output_compression): set by the ini, or by an ob_gzhandler level
pub fn compressionOn(vm: *VM) bool {
    return vm.zlib_output_compression != 0;
}

// sapi_add_header_ex: under serve the header goes out with the response;
// the cli keeps none, but warns as header() does once output started
fn addHeader(vm: *VM, header: []const u8, replace: bool) RuntimeError!void {
    try @import("http.zig").addSapiHeader(vm, header, replace);
}

// the "zlib.output_compression" ini value as OnUpdate_zlib_output_compression
// reads it: off, on (1), or a quantity
pub fn parseCompression(text: []const u8) i64 {
    const t = std.mem.trim(u8, text, " \t");
    if (std.ascii.eqlIgnoreCase(t, "off") or t.len == 0) return 0;
    if (std.ascii.eqlIgnoreCase(t, "on")) return 1;
    return @import("../runtime/memory.zig").parseQuantity(t).value;
}

fn native_ob_gzhandler(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const vm = ctx.vm;
    const params = @import("html.zig").Params{ .ctx = ctx, .func = "ob_gzhandler", .args = args };
    const data = try params.string(0, "data", "");
    const flags = try params.int(1, "flags", 0);
    const coding = encoding(vm);
    if (coding == 0) return NativeResult.scalar(.{ .bool = false });
    if (flags & op_start != 0) {
        try addHeader(vm, if (coding == coding_gzip) "Content-Encoding: gzip" else "Content-Encoding: deflate", true);
        try addHeader(vm, "Vary: Accept-Encoding", false);
    }
    const zctx = vm.ob_gzhandler_ctx orelse blk: {
        const made = try vm.allocator.create(Context);
        made.* = .{};
        vm.ob_gzhandler_ctx = made;
        break :blk made;
    };
    var out: ?[]u8 = null;
    defer freeOut(vm, &out);
    if (!try handlerEx(vm, zctx, flags, data, &out)) {
        zctx.destroy(vm.allocator);
        vm.ob_gzhandler_ctx = null;
        return NativeResult.scalar(.{ .bool = false });
    }
    return NativeResult.copyString(ctx.allocator, out orelse "");
}

// the coding the request was found to accept, without looking for it
fn native_zlib_get_coding_type(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return switch (ctx.vm.zlib_coding) {
        coding_gzip => NativeResult.literal("gzip"),
        coding_deflate => NativeResult.literal("deflate"),
        else => NativeResult.scalar(.{ .bool = false }),
    };
}

// zlib's RINIT, once the request's $_SERVER exists
pub fn requestStartup(vm: *VM) RuntimeError!void {
    vm.zlib_coding = 0;
    vm.zlib_output_compression = parseCompression(vm.iniText("zlib.output_compression"));
    try startCompression(vm);
}

// php_zlib_output_compression_start, at the request's start (and when
// zlib.output_compression is turned on at runtime): the compression level,
// when the request accepts a coding. then zlib.output_handler on top
pub fn startCompression(vm: *VM) RuntimeError!void {
    switch (vm.zlib_output_compression) {
        0 => return,
        1 => vm.zlib_output_compression = default_size,
        else => {},
    }
    if (encoding(vm) == 0) return;
    const chunk: usize = @intCast(@max(vm.zlib_output_compression, 0));
    const output_control = @import("output_control.zig");
    if (!try output_control.startZlib(vm, handler_name, chunk, output_control.std_flags)) return;
    const user = vm.iniText("zlib.output_handler");
    if (user.len == 0) return;
    var ctx = vm.makeContext(null);
    const name = try Value.String.create(vm.allocator, user);
    defer name.release();
    try output_control.startUser(&ctx, .{ .string = name }, chunk, output_control.std_flags);
}
