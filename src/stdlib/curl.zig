const std = @import("std");
const sync = @import("../sync.zig");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const RuntimeError = error{ RuntimeError, OutOfMemory };

const c = @import("c_curl");
const array_diff = @import("array_diff.zig");
const value_mod = @import("../runtime/value.zig");
const fs = @import("filesystem.zig");
const streams = @import("streams.zig");
const platform = @import("../platform.zig");
const sys = @import("../sys.zig");

pub const entries = .{
    .{ "curl_init", curlInit },
    .{ "curl_setopt", curlSetopt },
    .{ "curl_setopt_array", curlSetoptArray },
    .{ "curl_exec", curlExec },
    .{ "curl_close", curlClose },
    .{ "curl_error", curlError },
    .{ "curl_errno", curlErrno },
    .{ "curl_getinfo", curlGetinfo },
    .{ "curl_reset", curlReset },
    .{ "curl_version", curlVersion },
    .{ "curl_strerror", curlStrerror },
    .{ "curl_escape", curlEscape },
    .{ "curl_unescape", curlUnescape },
    .{ "curl_share_init", curlShareInit },
    .{ "curl_share_close", curlShareClose },
    .{ "curl_share_setopt", curlShareSetopt },
    .{ "curl_share_errno", curlShareErrno },
    .{ "curl_share_strerror", curlShareStrerror },
    // curl_multi_* - real concurrent transfers via libcurl's multi interface
    .{ "curl_multi_init", curlMultiInit },
    .{ "curl_multi_add_handle", curlMultiAddHandle },
    .{ "curl_copy_handle", curlCopyHandle },
    .{ "curl_multi_remove_handle", curlMultiRemoveHandle },
    .{ "curl_multi_exec", curlMultiExec },
    .{ "curl_multi_select", curlMultiSelect },
    .{ "curl_multi_getcontent", curlMultiGetcontent },
    .{ "curl_multi_info_read", curlMultiInfoRead },
    .{ "curl_multi_close", curlMultiClose },
    .{ "curl_multi_strerror", curlMultiStrerror },
    .{ "curl_multi_errno", curlMultiErrno },
    .{ "curl_multi_get_handles", curlMultiGetHandles },
    .{ "curl_multi_setopt", curlMultiSetopt },
    .{ "curl_file_create", curlFileCreate },
};

var global_init = sync.once(globalInit);

fn ensureGlobalInit() void {
    global_init.call();
}

fn globalInit() void {
    _ = c.curl_global_init(c.CURL_GLOBAL_DEFAULT);
}

fn getHandle(obj: *PhpObject) ?*c.CURL {
    return obj.native.get(c.CURL, .curl);
}

fn getEasyShare(obj: *PhpObject) ?*ShareState {
    return obj.native.getExtra(ShareState, .curl);
}

// the header and other string lists a handle passes to libcurl, which reads
// them during the transfer, so they live until the option is set again or
// the handle goes
const SlistSet = struct {
    lists: [slist_options.len]?*c.struct_curl_slist = @splat(null),
};

fn getSlists(obj: *PhpObject) ?*SlistSet {
    return obj.native.getAux(SlistSet, .curl);
}

fn freeSlist(obj: *PhpObject) void {
    if (getSlists(obj)) |set| {
        for (set.lists) |list| if (list) |sl| c.curl_slist_free_all(sl);
        std.heap.c_allocator.destroy(set);
        obj.native.aux = 0;
    }
}

fn slistIndex(option: i64) ?usize {
    inline for (slist_options, 0..) |name, i| {
        if (comptime @hasDecl(c, name)) {
            if (option == @field(c, name)) return i;
        }
    }
    return null;
}

fn slistOptionId(index: usize) c_uint {
    inline for (slist_options, 0..) |name, i| {
        if (comptime @hasDecl(c, name)) {
            if (index == i) return @intCast(@field(c, name));
        }
    }
    unreachable;
}

fn cloneHandle(_: *VM, src: *PhpObject, copy: *PhpObject) bool {
    const handle = getHandle(src) orelse return false;
    const dup = c.curl_easy_duphandle(handle) orelse return false;
    copy.native = .{ .kind = .curl, .ptr = @intFromPtr(dup) };
    // the duplicate points at the original's lists, which are freed with the
    // original, so it gets its own copies
    if (getSlists(src)) |set| {
        const fresh_set = std.heap.c_allocator.create(SlistSet) catch {
            c.curl_easy_cleanup(dup);
            copy.native = .{};
            return false;
        };
        fresh_set.* = .{};
        copy.native.aux = @intFromPtr(fresh_set);
        for (set.lists, 0..) |list, i| {
            var fresh: ?*c.struct_curl_slist = null;
            var node: ?*c.struct_curl_slist = list;
            while (node) |item| : (node = item.next) {
                fresh = c.curl_slist_append(fresh, item.data) orelse {
                    if (fresh) |f| c.curl_slist_free_all(f);
                    freeSlist(copy);
                    c.curl_easy_cleanup(dup);
                    copy.native = .{};
                    return false;
                };
            }
            fresh_set.lists[i] = fresh;
            if (fresh != null) _ = c.curl_easy_setopt(dup, slistOptionId(i), fresh);
        }
    }
    return true;
}

fn getThis(ctx: *NativeContext) ?*PhpObject {
    if (ctx.vm.frame_count == 0) return null;
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

fn getThisObj(args: []const Value) ?*PhpObject {
    if (args.len == 0) return null;
    if (args[0] != .object) return null;
    return args[0].object;
}

// libcurl copies every string option it is handed (post fields go through
// CURLOPT_COPYPOSTFIELDS), so a copy that lives for the call is enough
fn dupeZ(ctx: *NativeContext, s: []const u8) ![:0]const u8 {
    return ctx.vm.transientZ(s);
}

fn curlInit(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    ensureGlobalInit();

    const handle = c.curl_easy_init() orelse return NativeResult.scalar(.{ .bool = false });

    const obj = try ctx.createObject("CurlHandle");
    obj.native = .{ .kind = .curl, .ptr = @intFromPtr(handle) };
    try obj.set(ctx.allocator, "__error", .{ .string = Value.String.borrowed("") });
    try obj.set(ctx.allocator, "__errno", .{ .int = 0 });
    try obj.set(ctx.allocator, "__return_transfer", .{ .bool = false });
    try obj.set(ctx.allocator, "__header_out", .{ .bool = false });
    try obj.set(ctx.allocator, "__http_code", .{ .int = 0 });

    if (args.len > 0 and args[0] == .string) {
        const url_z = try dupeZ(ctx, args[0].string.bytes());
        _ = c.curl_easy_setopt(handle, c.CURLOPT_URL, url_z.ptr);
    }

    return NativeResult.borrowed(.{ .object = obj });
}

fn curlSetopt(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 3) return NativeResult.scalar(.{ .bool = false });
    const obj = getThisObj(args) orelse return NativeResult.scalar(.{ .bool = false });
    const handle = getHandle(obj) orelse return NativeResult.scalar(.{ .bool = false });
    if (args[1] != .int) return NativeResult.scalar(.{ .bool = false });
    const option = args[1].int;
    return applySetopt(ctx, handle, obj, option, args[2]);
}

fn applySetopt(ctx: *NativeContext, handle: *c.CURL, obj: *PhpObject, option: i64, value: Value) RuntimeError!NativeResult {
    if (option == c.CURLOPT_SHARE) {
        // PHP ignores non-share values (including null); they do not detach.
        if (value != .object or !std.mem.eql(u8, value.object.class_name, "CurlShareHandle")) return NativeResult.scalar(.{ .bool = true });
        const share = getShareState(value.object) orelse return NativeResult.scalar(.{ .bool = false });
        const code = c.curl_easy_setopt(handle, c.CURLOPT_SHARE, share.handle);
        if (code == c.CURLE_OK) {
            // Native references outlive PHP wrappers, including request sweeping
            // in allocation order. reset preserves libcurl's share association.
            share.refs += 1;
            releaseEasyShare(obj);
            obj.native.extra = @intFromPtr(share);
        }
        try obj.set(ctx.allocator, "__errno", .{ .int = @intCast(code) });
        return NativeResult.scalar(.{ .bool = code == c.CURLE_OK });
    }
    // the php callables libcurl's callbacks run (curlExec installs them)
    // the write handler has one method: the last of RETURNTRANSFER and
    // WRITEFUNCTION wins, and clearing the function goes back to stdout
    if (option == c.CURLOPT_WRITEFUNCTION) {
        try obj.set(ctx.allocator, "__write_user", .{ .bool = value != .null });
        try obj.set(ctx.allocator, "__file_stream", .null);
        if (value == .null) try obj.set(ctx.allocator, "__return_transfer", .{ .bool = false });
        return setCallback(ctx, obj, "__write_function", value);
    }
    if (option == c.CURLOPT_HEADERFUNCTION) {
        if (value != .null) try obj.set(ctx.allocator, "__header_stream", .null);
        return setCallback(ctx, obj, "__header_function", value);
    }
    if (option == c.CURLOPT_FILE or option == c.CURLOPT_WRITEHEADER or option == c.CURLOPT_INFILE or option == c.CURLOPT_STDERR) {
        return setStreamOption(ctx, obj, option, value);
    }

    // CURLOPT_RETURNTRANSFER - PHP-specific, not a real libcurl option
    if (option == 19913) {
        try obj.set(ctx.allocator, "__return_transfer", .{ .bool = value.isTruthy() });
        try obj.set(ctx.allocator, "__write_user", .{ .bool = false });
        try obj.set(ctx.allocator, "__file_stream", .null);
        return NativeResult.scalar(.{ .bool = true });
    }
    // backward compatibility only
    if (option == 19914 or option == c.CURLOPT_DNS_USE_GLOBAL_CACHE) return NativeResult.scalar(.{ .bool = true });
    if (option == -1) { // CURLOPT_SAFE_UPLOAD
        if (!value.isTruthy()) {
            try ctx.vm.setPendingException("ValueError", "curl_setopt(): Disabling safe uploads is no longer supported");
            return error.RuntimeError;
        }
        return NativeResult.scalar(.{ .bool = true });
    }
    if (option == c.CURLOPT_PRIVATE) {
        try obj.set(ctx.allocator, "__private", value);
        return NativeResult.scalar(.{ .bool = true });
    }

    if (option == c.CURLOPT_SSL_VERIFYHOST and value.toInt() == 1) {
        try ctx.vm.raiseError(8, "curl_setopt(): CURLOPT_SSL_VERIFYHOST no longer accepts the value 1, value 2 will be used instead");
        return setoptResult(ctx, obj, c.curl_easy_setopt(handle, c.CURLOPT_SSL_VERIFYHOST, @as(c_long, 2)));
    }
    if (option == c.CURLOPT_POSTREDIR) {
        return setoptResult(ctx, obj, c.curl_easy_setopt(handle, c.CURLOPT_POSTREDIR, @as(c_long, @truncate(value.toInt() & c.CURL_REDIR_POST_ALL))));
    }
    if (optionIn(&long_options, option)) {
        return setoptResult(ctx, obj, c.curl_easy_setopt(handle, @intCast(option), @as(c_long, @truncate(value.toInt()))));
    }
    if (optionIn(&off_t_options, option)) {
        return setoptResult(ctx, obj, c.curl_easy_setopt(handle, @intCast(option), @as(c.curl_off_t, value.toInt())));
    }
    if (option == c.CURLOPT_URL or optionIn(&string_options, option) or optionIn(&nullable_string_options, option)) {
        if (value == .null and optionIn(&nullable_string_options, option)) {
            return setoptResult(ctx, obj, c.curl_easy_setopt(handle, @intCast(option), @as(?[*:0]const u8, null)));
        }
        var buf: [64]u8 = undefined;
        const text = try array_diff.tmpString(ctx, value, &buf);
        defer text.release(ctx);
        // php_curl_option_str
        if (std.mem.indexOfScalar(u8, text.bytes, 0) != null) {
            // php 8.6 names the option (php_curl_option_get_name)
            const opt = c.curl_easy_option_by_id(@intCast(option));
            const name: []const u8 = if (opt != null and opt.*.name != null) std.mem.span(opt.*.name) else "UNKNOWN_OPTION";
            const msg = try std.fmt.allocPrint(ctx.allocator, "curl_setopt(): cURL option CURLOPT_{s} must not contain any null bytes", .{name});
            defer ctx.allocator.free(msg);
            try ctx.vm.setPendingException("ValueError", msg);
            return error.RuntimeError;
        }
        const z = try dupeZ(ctx, text.bytes);
        return setoptResult(ctx, obj, c.curl_easy_setopt(handle, @intCast(option), z.ptr));
    }
    if (optionIn(&blob_options, option)) {
        var buf: [64]u8 = undefined;
        const text = try array_diff.tmpString(ctx, value, &buf);
        defer text.release(ctx);
        var blob = c.struct_curl_blob{ .data = @ptrCast(@constCast(text.bytes.ptr)), .len = text.bytes.len, .flags = c.CURL_BLOB_COPY };
        return setoptResult(ctx, obj, c.curl_easy_setopt(handle, @intCast(option), &blob));
    }
    if (slistIndex(option)) |index| {
        if (value != .array) {
            const name = slist_options[index];
            const msg = try std.fmt.allocPrint(ctx.allocator, "curl_setopt(): The {s} option must have an array value", .{name});
            defer ctx.allocator.free(msg);
            try ctx.vm.setPendingException("TypeError", msg);
            return error.RuntimeError;
        }
        var slist: ?*c.struct_curl_slist = null;
        for (value.array.entries.items) |entry| {
            var buf: [64]u8 = undefined;
            const text = try array_diff.tmpString(ctx, entry.value, &buf);
            defer text.release(ctx);
            const z = try dupeZ(ctx, text.bytes);
            slist = c.curl_slist_append(slist, z.ptr) orelse {
                if (slist) |sl| c.curl_slist_free_all(sl);
                try ctx.vm.emitWarning("curl_setopt(): Could not build curl_slist");
                return NativeResult.scalar(.{ .bool = false });
            };
        }
        const set = getSlists(obj) orelse blk: {
            const fresh = try std.heap.c_allocator.create(SlistSet);
            fresh.* = .{};
            obj.native.aux = @intFromPtr(fresh);
            break :blk fresh;
        };
        const code = c.curl_easy_setopt(handle, @intCast(option), slist);
        if (set.lists[index]) |old| c.curl_slist_free_all(old);
        set.lists[index] = slist;
        return setoptResult(ctx, obj, code);
    }

    // CURLOPT_POSTFIELDS
    if (option == c.CURLOPT_POSTFIELDS) {
        const s = switch (value) {
            .string => value.string.bytes(),
            else => return NativeResult.scalar(.{ .bool = false }),
        };
        const len_code: c_uint = @intCast(c.curl_easy_setopt(handle, c.CURLOPT_POSTFIELDSIZE, @as(c_long, @intCast(s.len))));
        if (len_code != c.CURLE_OK) return NativeResult.scalar(.{ .bool = false });
        const z = try dupeZ(ctx, s);
        const code: c_uint = @intCast(c.curl_easy_setopt(handle, c.CURLOPT_COPYPOSTFIELDS, z.ptr));
        return NativeResult.scalar(.{ .bool = code == c.CURLE_OK });
    }

    // CURLINFO_HEADER_OUT (debug)
    if (option == c.CURLINFO_HEADER_OUT) {
        const v = value.isTruthy();
        try obj.set(ctx.allocator, "__header_out", .{ .bool = v });
        if (v) {
            const code: c_uint = @intCast(c.curl_easy_setopt(handle, c.CURLOPT_VERBOSE, @as(c_long, 1)));
            _ = code;
        }
        return NativeResult.scalar(.{ .bool = true });
    }

    // PHP throws ValueError for unrecognized CURLOPT_* constants
    try ctx.vm.setPendingException("ValueError", "curl_setopt(): Argument #2 ($option) is not a valid cURL option");
    return error.RuntimeError;
}

fn optionIn(comptime list: []const []const u8, option: i64) bool {
    inline for (list) |name| {
        if (comptime @hasDecl(c, name)) {
            if (option == @field(c, name)) return true;
        }
    }
    return false;
}

// CURLOPT_FILE, _WRITEHEADER, _INFILE and _STDERR take a stream (null
// resets the handler). php casts it to a FILE*: curl's bytes go straight
// to a plain file's descriptor, past the stream's own position, and through
// the stream's operations for anything else
fn setStreamOption(ctx: *NativeContext, obj: *PhpObject, option: i64, value: Value) RuntimeError!NativeResult {
    const slot: []const u8 = if (option == c.CURLOPT_FILE) "__file_stream" else if (option == c.CURLOPT_WRITEHEADER) "__header_stream" else if (option == c.CURLOPT_INFILE) "__infile_stream" else "__stderr_stream";
    const name: []const u8 = if (option == c.CURLOPT_FILE) "CURLOPT_FILE" else if (option == c.CURLOPT_WRITEHEADER) "CURLOPT_WRITEHEADER" else "CURLOPT_STDERR";
    if (value == .null) {
        try obj.set(ctx.allocator, slot, .null);
        return NativeResult.scalar(.{ .bool = true });
    }
    // zend_fetch_resource2_ex
    if (value != .resource) {
        try ctx.vm.setPendingException("TypeError", "curl_setopt(): supplied argument is not a valid File-Handle resource");
        return error.RuntimeError;
    }
    const res = value.resource;
    const is_stream = std.mem.eql(u8, res.class_name, "FileHandle") or std.mem.eql(u8, res.class_name, "DirectoryHandle");
    if (!is_stream or value_mod.resourceClosed(res)) {
        try ctx.vm.setPendingException("TypeError", "curl_setopt(): supplied resource is not a valid File-Handle resource");
        return error.RuntimeError;
    }
    if (option != c.CURLOPT_INFILE) {
        const mode_v = res.get("__mode");
        const mode: []const u8 = if (mode_v == .string) mode_v.string.bytes() else "r";
        const writable = mode.len == 0 or mode[0] != 'r' or (mode.len > 1 and mode[1] == '+');
        if (!writable) {
            const msg = try std.fmt.allocPrint(ctx.allocator, "curl_setopt(): The file handle provided for {s} must be writable", .{name});
            defer ctx.allocator.free(msg);
            try ctx.vm.setPendingException("ValueError", msg);
            return error.RuntimeError;
        }
    }
    try obj.set(ctx.allocator, slot, value);
    if (option == c.CURLOPT_FILE) {
        try obj.set(ctx.allocator, "__write_user", .{ .bool = false });
        try obj.set(ctx.allocator, "__return_transfer", .{ .bool = false });
    }
    if (option == c.CURLOPT_WRITEHEADER) try obj.set(ctx.allocator, "__header_function", .null);
    return NativeResult.scalar(.{ .bool = true });
}

fn streamSlot(obj: *PhpObject, slot: []const u8) ?*PhpObject {
    const v = obj.get(slot);
    return if (v == .resource) v.resource else null;
}

// _php_curl_verify_handlers: a stream closed since it was set is dropped
fn verifyHandlers(ctx: *NativeContext, obj: *PhpObject) RuntimeError!void {
    inline for (.{
        .{ "__stderr_stream", "CURLOPT_STDERR resource has gone away, resetting to stderr" },
        .{ "__infile_stream", "CURLOPT_INFILE resource has gone away, resetting to default" },
        .{ "__header_stream", "CURLOPT_WRITEHEADER resource has gone away, resetting to default" },
        .{ "__file_stream", "CURLOPT_FILE resource has gone away, resetting to default" },
    }) |entry| {
        if (streamSlot(obj, entry[0])) |res| if (value_mod.resourceClosed(res)) {
            try ctx.vm.emitWarning("curl_exec(): " ++ entry[1]);
            try obj.set(ctx.allocator, entry[0], .null);
        };
    }
}

// a plain file (or pipe) stream's descriptor, which the FILE* php casts to
// writes through directly
fn rawDescriptor(res: *PhpObject) ?std.posix.fd_t {
    if (fs.isNetStream(res)) return null;
    if (streams.backend(res) != .fd) return null;
    const fd = res.get("__fd");
    return if (fd == .int and fd.int >= 0) @intCast(fd.int) else null;
}

fn writeToStream(ctx: *NativeContext, res: *PhpObject, data: []const u8) usize {
    if (value_mod.resourceClosed(res)) return 0;
    if (!platform.is_windows) if (rawDescriptor(res)) |fd| {
        var done: usize = 0;
        while (done < data.len) {
            const n = sys.write(fd, data[done..]) catch break;
            if (n == 0) break;
            done += n;
        }
        return done;
    };
    const n = streams.write(ctx, res, data) catch return 0;
    return if (n < 0) 0 else @intCast(n);
}

fn readFromStream(ctx: *NativeContext, res: *PhpObject, dest: []u8) usize {
    if (value_mod.resourceClosed(res)) return 0;
    if (!platform.is_windows) if (rawDescriptor(res)) |fd| {
        return std.posix.read(fd, dest) catch 0;
    };
    const n = streams.read(ctx, res, dest) catch return 0;
    return if (n < 0) 0 else @intCast(n);
}

// SAVE_CURL_ERROR
fn setoptResult(ctx: *NativeContext, obj: *PhpObject, code: c.CURLcode) RuntimeError!NativeResult {
    try obj.set(ctx.allocator, "__errno", .{ .int = @intCast(code) });
    return NativeResult.scalar(.{ .bool = code == c.CURLE_OK });
}

// HANDLE_CURL_OPTION_CALLABLE: null clears the callback
fn setCallback(ctx: *NativeContext, obj: *PhpObject, slot: []const u8, value: Value) RuntimeError!NativeResult {
    try obj.set(ctx.allocator, slot, value);
    return NativeResult.scalar(.{ .bool = true });
}

fn curlSetoptArray(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.scalar(.{ .bool = false });
    const obj = getThisObj(args) orelse return NativeResult.scalar(.{ .bool = false });
    const handle = getHandle(obj) orelse return NativeResult.scalar(.{ .bool = false });
    if (args[1] != .array) return NativeResult.scalar(.{ .bool = false });

    for (args[1].array.entries.items) |entry| {
        if (entry.key != .int) continue;
        const result = try applySetopt(ctx, handle, obj, entry.key.int, entry.value);
        if (result.value == .bool and !result.value.bool) return NativeResult.scalar(.{ .bool = false });
    }
    return NativeResult.scalar(.{ .bool = true });
}

const WriteCallbackData = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayListUnmanaged(u8),
};

fn writeCallback(data: [*]u8, size: usize, nmemb: usize, userdata: *anyopaque) callconv(.c) usize {
    const total = size * nmemb;
    const cb_data: *WriteCallbackData = @ptrCast(@alignCast(userdata));
    cb_data.buffer.appendSlice(cb_data.allocator, data[0..total]) catch return 0;
    return total;
}

// what curl_exec's libcurl callbacks need: php's curl_write and
// curl_write_header
const Transfer = struct {
    ctx: *NativeContext,
    obj: *PhpObject,
    write_fn: Value,
    header_fn: Value,
    return_transfer: bool,
    file_stream: ?*PhpObject = null,
    header_stream: ?*PhpObject = null,
    infile_stream: ?*PhpObject = null,
    stderr_stream: ?*PhpObject = null,
    buffer: std.ArrayListUnmanaged(u8) = .empty,
    failed: bool = false,

    // calls fn($handle, $data) and returns its result as php's zval_get_long;
    // once a callback has thrown, the rest of the transfer calls nothing
    fn call(self: *Transfer, callable: Value, data: []const u8) usize {
        if (self.failed or self.ctx.vm.pending_exception != null) return data.len;
        const str = Value.String.create(self.ctx.allocator, data) catch {
            self.failed = true;
            return 0;
        };
        defer str.release();
        const result = self.ctx.invokeCallable(callable, &.{ .{ .object = self.obj }, .{ .string = str } }) catch {
            self.failed = true;
            return data.len;
        };
        const n = result.toInt();
        return if (n < 0) std.math.maxInt(usize) else @intCast(n);
    }
};

fn transferWrite(data: [*]u8, size: usize, nmemb: usize, userdata: *anyopaque) callconv(.c) usize {
    const total = size * nmemb;
    const t: *Transfer = @ptrCast(@alignCast(userdata));
    if (t.write_fn != .null) return t.call(t.write_fn, data[0..total]);
    if (t.file_stream) |res| return writeToStream(t.ctx, res, data[0..total]);
    if (t.return_transfer) {
        t.buffer.appendSlice(t.ctx.allocator, data[0..total]) catch return 0;
    } else {
        // PHP_CURL_STDOUT goes through php's output layer
        t.ctx.vm.output.appendSlice(t.ctx.vm.allocator, data[0..total]) catch return 0;
    }
    return total;
}

fn transferHeader(data: [*]u8, size: usize, nmemb: usize, userdata: *anyopaque) callconv(.c) usize {
    const total = size * nmemb;
    const t: *Transfer = @ptrCast(@alignCast(userdata));
    if (t.header_stream) |res| return writeToStream(t.ctx, res, data[0..total]);
    return t.call(t.header_fn, data[0..total]);
}

// curl_read's PHP_CURL_DIRECT: the INFILE stream, or nothing without one
fn transferRead(data: [*]u8, size: usize, nmemb: usize, userdata: *anyopaque) callconv(.c) usize {
    const t: *Transfer = @ptrCast(@alignCast(userdata));
    const res = t.infile_stream orelse return 0;
    return readFromStream(t.ctx, res, data[0 .. size * nmemb]);
}

// the FILE* libcurl writes its verbose output to, over the STDERR stream:
// a plain file's descriptor, or (glibc and musl) a cookie stream through
// the stream's operations
const CookieIo = extern struct {
    read: ?*const anyopaque = null,
    write: ?*const fn (?*anyopaque, [*]const u8, usize) callconv(.c) isize,
    seek: ?*const anyopaque = null,
    close: ?*const anyopaque = null,
};
extern "c" fn fopencookie(cookie: ?*anyopaque, mode: [*:0]const u8, funcs: CookieIo) ?*anyopaque;
extern "c" fn fdopen(fd: c_int, mode: [*:0]const u8) ?*anyopaque;
extern "c" fn fclose(file: ?*anyopaque) c_int;

fn cookieWrite(cookie: ?*anyopaque, data: [*]const u8, len: usize) callconv(.c) isize {
    const t: *Transfer = @ptrCast(@alignCast(cookie orelse return -1));
    const res = t.stderr_stream orelse return -1;
    return @intCast(writeToStream(t.ctx, res, data[0..len]));
}

fn openStderrFile(t: *Transfer) ?*anyopaque {
    if (platform.is_windows) return null;
    const res = t.stderr_stream orelse return null;
    if (rawDescriptor(res)) |fd| {
        const copy = std.c.dup(fd);
        if (copy < 0) return null;
        return fdopen(copy, "a") orelse {
            sys.close(copy);
            return null;
        };
    }
    if (comptime @import("builtin").os.tag != .linux) return null;
    return fopencookie(t, "a", .{ .write = &cookieWrite });
}

const CurlCallback = ?*const fn ([*]u8, usize, usize, *anyopaque) callconv(.c) usize;

fn callbackValue(obj: *PhpObject, name: []const u8) Value {
    const v = obj.get(name);
    return if (v == .undef) .null else v;
}

fn curlExec(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    const obj = getThisObj(args) orelse return NativeResult.scalar(.{ .bool = false });
    const handle = getHandle(obj) orelse return NativeResult.scalar(.{ .bool = false });

    try verifyHandlers(ctx, obj);
    const return_transfer_v = obj.get("__return_transfer");
    var transfer = Transfer{
        .ctx = ctx,
        .obj = obj,
        .write_fn = if (obj.get("__write_user") == .bool and obj.get("__write_user").bool) callbackValue(obj, "__write_function") else .null,
        .header_fn = callbackValue(obj, "__header_function"),
        .return_transfer = return_transfer_v == .bool and return_transfer_v.bool,
        .file_stream = streamSlot(obj, "__file_stream"),
        .header_stream = streamSlot(obj, "__header_stream"),
        .infile_stream = streamSlot(obj, "__infile_stream"),
        .stderr_stream = streamSlot(obj, "__stderr_stream"),
    };
    defer transfer.buffer.deinit(ctx.allocator);

    _ = c.curl_easy_setopt(handle, c.CURLOPT_WRITEFUNCTION, @as(CurlCallback, &transferWrite));
    _ = c.curl_easy_setopt(handle, c.CURLOPT_WRITEDATA, @as(*anyopaque, @ptrCast(&transfer)));
    _ = c.curl_easy_setopt(handle, c.CURLOPT_READFUNCTION, @as(CurlCallback, &transferRead));
    _ = c.curl_easy_setopt(handle, c.CURLOPT_READDATA, @as(*anyopaque, @ptrCast(&transfer)));
    const stderr_file = openStderrFile(&transfer);
    if (stderr_file) |f| _ = c.curl_easy_setopt(handle, c.CURLOPT_STDERR, f);
    defer if (stderr_file) |f| {
        _ = c.curl_easy_setopt(handle, c.CURLOPT_STDERR, @as(?*anyopaque, null));
        _ = fclose(f);
    };
    if (transfer.header_fn != .null or transfer.header_stream != null) {
        _ = c.curl_easy_setopt(handle, c.CURLOPT_HEADERFUNCTION, @as(CurlCallback, &transferHeader));
        _ = c.curl_easy_setopt(handle, c.CURLOPT_HEADERDATA, @as(*anyopaque, @ptrCast(&transfer)));
    } else {
        _ = c.curl_easy_setopt(handle, c.CURLOPT_HEADERFUNCTION, @as(CurlCallback, null));
        _ = c.curl_easy_setopt(handle, c.CURLOPT_HEADERDATA, @as(?*anyopaque, null));
    }

    const result = c.curl_easy_perform(handle);
    // the callbacks' state lives on this stack frame
    _ = c.curl_easy_setopt(handle, c.CURLOPT_WRITEDATA, @as(?*anyopaque, null));
    _ = c.curl_easy_setopt(handle, c.CURLOPT_HEADERDATA, @as(?*anyopaque, null));
    _ = c.curl_easy_setopt(handle, c.CURLOPT_WRITEFUNCTION, @as(CurlCallback, null));
    _ = c.curl_easy_setopt(handle, c.CURLOPT_HEADERFUNCTION, @as(CurlCallback, null));
    _ = c.curl_easy_setopt(handle, c.CURLOPT_READDATA, @as(?*anyopaque, null));
    _ = c.curl_easy_setopt(handle, c.CURLOPT_READFUNCTION, @as(CurlCallback, null));
    if (ctx.vm.pending_exception != null) return error.RuntimeError;

    // store error info
    if (result != c.CURLE_OK) {
        const err_msg = c.curl_easy_strerror(result);
        const msg = std.mem.span(err_msg);
        try obj.setCopiedString(ctx.allocator, "__error", msg);
        try obj.set(ctx.allocator, "__errno", .{ .int = @intCast(result) });
        return NativeResult.scalar(.{ .bool = false });
    }

    try obj.set(ctx.allocator, "__error", .{ .string = Value.String.borrowed("") });
    try obj.set(ctx.allocator, "__errno", .{ .int = 0 });

    // store http code
    var http_code: c_long = 0;
    _ = c.curl_easy_getinfo(handle, c.CURLINFO_RESPONSE_CODE, &http_code);
    try obj.set(ctx.allocator, "__http_code", .{ .int = @intCast(http_code) });

    if (transfer.return_transfer and transfer.write_fn == .null) {
        const str = try Value.String.create(ctx.allocator, transfer.buffer.items);
        return NativeResult.takeString(str);
    }

    return NativeResult.scalar(.{ .bool = true });
}

fn curlClose(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = ctx;
    if (args.len == 0) return NativeResult.scalar(.null);
    const obj = getThisObj(args) orelse return NativeResult.scalar(.null);
    cleanupHandle(obj);
    return NativeResult.scalar(.null);
}

pub fn cleanupHandle(obj: *PhpObject) void {
    if (obj.pooled) return;
    freeSlist(obj);
    if (getHandle(obj)) |handle| {
        c.curl_easy_cleanup(handle);
        releaseEasyShare(obj);
        obj.native.ptr = 0;
    }
}

fn curlError(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.literal("");
    const obj = getThisObj(args) orelse return NativeResult.literal("");
    return NativeResult.share(obj.get("__error"));
}

fn curlErrno(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .int = 0 });
    const obj = getThisObj(args) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.share(obj.get("__errno"));
}

fn curlGetinfo(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = false });
    const obj = getThisObj(args) orelse return NativeResult.scalar(.{ .bool = false });
    const handle = getHandle(obj) orelse return NativeResult.scalar(.{ .bool = false });

    // no specific option - return all info as array
    if (args.len < 2 or args[1] == .null) {
        return getAllInfo(ctx, handle);
    }

    if (args[1] != .int) return NativeResult.scalar(.{ .bool = false });
    const option = args[1].int;
    if (option == c.CURLINFO_PRIVATE) {
        const data = obj.get("__private");
        return if (data == .undef) NativeResult.scalar(.{ .bool = false }) else NativeResult.share(data);
    }
    return getInfoOption(ctx, handle, option);
}

fn getInfoOption(ctx: *NativeContext, handle: *c.CURL, option: i64) RuntimeError!NativeResult {
    if (option == c.CURLINFO_COOKIELIST) {
        var list: ?*c.struct_curl_slist = null;
        if (c.curl_easy_getinfo(handle, c.CURLINFO_COOKIELIST, &list) != c.CURLE_OK) return NativeResult.scalar(.{ .bool = false });
        defer c.curl_slist_free_all(list);
        const arr = try ctx.createArray();
        var node = list;
        while (node) |item| : (node = item.next) {
            try arr.appendCopiedString(ctx.allocator, std.mem.span(item.data));
        }
        return NativeResult.borrowed(.{ .array = arr });
    }
    // string info types
    if (option == c.CURLINFO_EFFECTIVE_URL or
        option == c.CURLINFO_CONTENT_TYPE or
        option == c.CURLINFO_REDIRECT_URL or
        option == c.CURLINFO_PRIMARY_IP or
        option == c.CURLINFO_LOCAL_IP or
        option == c.CURLINFO_SCHEME)
    {
        var ptr: [*c]u8 = null;
        const code: c_uint = @intCast(c.curl_easy_getinfo(handle, @intCast(option), &ptr));
        if (code != c.CURLE_OK or ptr == null) return NativeResult.scalar(.{ .bool = false });
        const s = std.mem.span(ptr);
        const owned = try Value.String.create(ctx.allocator, s);
        return NativeResult.takeString(owned);
    }

    // long info types
    if (option == c.CURLINFO_RESPONSE_CODE or
        option == c.CURLINFO_HTTP_CONNECTCODE or
        option == c.CURLINFO_FILETIME or
        option == c.CURLINFO_REDIRECT_COUNT or
        option == c.CURLINFO_HEADER_SIZE or
        option == c.CURLINFO_REQUEST_SIZE or
        option == c.CURLINFO_SSL_VERIFYRESULT or
        option == c.CURLINFO_PRIMARY_PORT or
        option == c.CURLINFO_LOCAL_PORT)
    {
        var val: c_long = 0;
        const code: c_uint = @intCast(c.curl_easy_getinfo(handle, @intCast(option), &val));
        if (code != c.CURLE_OK) return NativeResult.scalar(.{ .bool = false });
        return NativeResult.scalar(.{ .int = @intCast(val) });
    }

    // double info types
    if (option == c.CURLINFO_TOTAL_TIME or
        option == c.CURLINFO_NAMELOOKUP_TIME or
        option == c.CURLINFO_CONNECT_TIME or
        option == c.CURLINFO_PRETRANSFER_TIME or
        option == c.CURLINFO_STARTTRANSFER_TIME or
        option == c.CURLINFO_REDIRECT_TIME or
        option == c.CURLINFO_SIZE_UPLOAD_T or
        option == c.CURLINFO_SIZE_DOWNLOAD_T or
        option == c.CURLINFO_SPEED_UPLOAD_T or
        option == c.CURLINFO_SPEED_DOWNLOAD_T or
        option == c.CURLINFO_CONTENT_LENGTH_DOWNLOAD or
        option == c.CURLINFO_CONTENT_LENGTH_UPLOAD)
    {
        var val: f64 = 0;
        const code: c_uint = @intCast(c.curl_easy_getinfo(handle, @intCast(option), &val));
        if (code != c.CURLE_OK) return NativeResult.scalar(.{ .bool = false });
        return NativeResult.scalar(.{ .float = val });
    }

    return NativeResult.scalar(.{ .bool = false });
}

fn getAllInfo(ctx: *NativeContext, handle: *c.CURL) RuntimeError!NativeResult {
    const arr = try ctx.createArray();

    var url_ptr: [*c]u8 = null;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_EFFECTIVE_URL, &url_ptr) == c.CURLE_OK) {
        if (url_ptr != null) {
            try arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("url") }, std.mem.span(url_ptr));
        }
    }

    var content_type_ptr: [*c]u8 = null;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_CONTENT_TYPE, &content_type_ptr) == c.CURLE_OK) {
        if (content_type_ptr != null) {
            try arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("content_type") }, std.mem.span(content_type_ptr));
        } else {
            try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("content_type") }, .null);
        }
    }

    var http_code: c_long = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_RESPONSE_CODE, &http_code) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("http_code") }, .{ .int = @intCast(http_code) });

    var header_size: c_long = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_HEADER_SIZE, &header_size) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("header_size") }, .{ .int = @intCast(header_size) });

    var request_size: c_long = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_REQUEST_SIZE, &request_size) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("request_size") }, .{ .int = @intCast(request_size) });

    var redirect_count: c_long = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_REDIRECT_COUNT, &redirect_count) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("redirect_count") }, .{ .int = @intCast(redirect_count) });

    var total_time: f64 = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_TOTAL_TIME, &total_time) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("total_time") }, .{ .float = total_time });

    var namelookup_time: f64 = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_NAMELOOKUP_TIME, &namelookup_time) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("namelookup_time") }, .{ .float = namelookup_time });

    var connect_time: f64 = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_CONNECT_TIME, &connect_time) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("connect_time") }, .{ .float = connect_time });

    var pretransfer_time: f64 = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_PRETRANSFER_TIME, &pretransfer_time) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("pretransfer_time") }, .{ .float = pretransfer_time });

    var starttransfer_time: f64 = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_STARTTRANSFER_TIME, &starttransfer_time) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("starttransfer_time") }, .{ .float = starttransfer_time });

    var redirect_time: f64 = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_REDIRECT_TIME, &redirect_time) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("redirect_time") }, .{ .float = redirect_time });

    var primary_ip_ptr: [*c]u8 = null;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_PRIMARY_IP, &primary_ip_ptr) == c.CURLE_OK) {
        if (primary_ip_ptr != null) {
            try arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("primary_ip") }, std.mem.span(primary_ip_ptr));
        }
    }

    var primary_port: c_long = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_PRIMARY_PORT, &primary_port) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("primary_port") }, .{ .int = @intCast(primary_port) });

    var ssl_verify: c_long = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_SSL_VERIFYRESULT, &ssl_verify) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("ssl_verify_result") }, .{ .int = @intCast(ssl_verify) });

    var scheme_ptr: [*c]u8 = null;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_SCHEME, &scheme_ptr) == c.CURLE_OK) {
        if (scheme_ptr != null) {
            try arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("scheme") }, std.mem.span(scheme_ptr));
        }
    }

    var redirect_url_ptr: [*c]u8 = null;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_REDIRECT_URL, &redirect_url_ptr) == c.CURLE_OK) {
        if (redirect_url_ptr != null) {
            try arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("redirect_url") }, std.mem.span(redirect_url_ptr));
        } else {
            try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("redirect_url") }, .{ .string = Value.String.borrowed("") });
        }
    }

    var local_ip_ptr: [*c]u8 = null;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_LOCAL_IP, &local_ip_ptr) == c.CURLE_OK) {
        if (local_ip_ptr != null) {
            try arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("local_ip") }, std.mem.span(local_ip_ptr));
        }
    }

    var local_port: c_long = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_LOCAL_PORT, &local_port) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("local_port") }, .{ .int = @intCast(local_port) });

    var filetime: c_long = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_FILETIME, &filetime) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("filetime") }, .{ .int = @intCast(filetime) });

    var http_version: c_long = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_HTTP_VERSION, &http_version) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("http_version") }, .{ .int = @intCast(http_version) });

    var protocol: c_long = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_PROTOCOL, &protocol) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("protocol") }, .{ .int = @intCast(protocol) });

    var num_connects: c_long = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_NUM_CONNECTS, &num_connects) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("num_connects") }, .{ .int = @intCast(num_connects) });

    var os_errno: c_long = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_OS_ERRNO, &os_errno) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("os_errno") }, .{ .int = @intCast(os_errno) });

    var size_upload: f64 = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_SIZE_UPLOAD_T, &size_upload) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("size_upload") }, .{ .float = size_upload });

    var size_download: f64 = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_SIZE_DOWNLOAD_T, &size_download) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("size_download") }, .{ .float = size_download });

    var speed_download: f64 = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_SPEED_DOWNLOAD_T, &speed_download) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("speed_download") }, .{ .float = speed_download });

    var speed_upload: f64 = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_SPEED_UPLOAD_T, &speed_upload) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("speed_upload") }, .{ .float = speed_upload });

    var download_cl: f64 = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_CONTENT_LENGTH_DOWNLOAD_T, &download_cl) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("download_content_length") }, .{ .float = download_cl });

    var upload_cl: f64 = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_CONTENT_LENGTH_UPLOAD_T, &upload_cl) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("upload_content_length") }, .{ .float = upload_cl });

    var appconnect_time: f64 = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_APPCONNECT_TIME, &appconnect_time) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("appconnect_time") }, .{ .float = appconnect_time });

    // _us variants (microsecond integer versions, present since libcurl 7.61.0)
    var ttot_us: c_long = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_TOTAL_TIME_T, &ttot_us) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("total_time_us") }, .{ .int = @intCast(ttot_us) });
    var nl_us: c_long = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_NAMELOOKUP_TIME_T, &nl_us) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("namelookup_time_us") }, .{ .int = @intCast(nl_us) });
    var conn_us: c_long = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_CONNECT_TIME_T, &conn_us) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("connect_time_us") }, .{ .int = @intCast(conn_us) });
    var pre_us: c_long = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_PRETRANSFER_TIME_T, &pre_us) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("pretransfer_time_us") }, .{ .int = @intCast(pre_us) });
    var start_us: c_long = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_STARTTRANSFER_TIME_T, &start_us) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("starttransfer_time_us") }, .{ .int = @intCast(start_us) });
    var redirect_us: c_long = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_REDIRECT_TIME_T, &redirect_us) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("redirect_time_us") }, .{ .int = @intCast(redirect_us) });
    var appc_us: c_long = 0;
    if (c.curl_easy_getinfo(handle, c.CURLINFO_APPCONNECT_TIME_T, &appc_us) == c.CURLE_OK)
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("appconnect_time_us") }, .{ .int = @intCast(appc_us) });

    return NativeResult.borrowed(.{ .array = arr });
}

// curl_copy_handle: a clone of the handle with its options and state
fn curlCopyHandle(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const src = getThisObj(args) orelse return NativeResult.scalar(.{ .bool = false });
    if (getHandle(src) == null) return NativeResult.scalar(.{ .bool = false });
    const copy = try ctx.createObject("CurlHandle");
    var it = src.properties.iterator();
    while (it.next()) |entry| try copy.set(ctx.allocator, entry.key_ptr.*, entry.value_ptr.*);
    if (!cloneHandle(ctx.vm, src, copy)) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.borrowed(.{ .object = copy });
}

fn curlReset(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.null);
    const obj = getThisObj(args) orelse return NativeResult.scalar(.null);
    const handle = getHandle(obj) orelse return NativeResult.scalar(.null);
    c.curl_easy_reset(handle);
    try obj.set(ctx.allocator, "__return_transfer", .{ .bool = false });
    try obj.set(ctx.allocator, "__header_out", .{ .bool = false });
    try obj.set(ctx.allocator, "__error", .{ .string = Value.String.borrowed("") });
    try obj.set(ctx.allocator, "__errno", .{ .int = 0 });
    try obj.set(ctx.allocator, "__http_code", .{ .int = 0 });
    for ([_][]const u8{ "__write_function", "__header_function", "__private", "__file_stream", "__header_stream", "__infile_stream", "__stderr_stream" }) |name| {
        if (obj.get(name) != .undef) try obj.set(ctx.allocator, name, .null);
    }
    freeSlist(obj);
    return NativeResult.scalar(.null);
}

fn curlStrerror(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .int) return NativeResult.scalar(.null);
    const code: c_uint = @intCast(args[0].int);
    const msg = c.curl_easy_strerror(code);
    if (msg == null) return NativeResult.scalar(.null);
    const span = std.mem.span(msg);
    const owned = try ctx.allocator.dupe(u8, span);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, owned));
}

// Separate native ownership keeps shares alive even when their PHP wrapper is
// swept before an attached easy handle. No VM layout or GC changes are needed.
const ShareState = struct {
    handle: *c.CURLSH,
    refs: usize = 1,
    errno: c_uint = c.CURLSHE_OK,
};

fn getShareState(obj: *PhpObject) ?*ShareState {
    return obj.native.get(ShareState, .curl_share);
}

fn releaseShare(state: *ShareState) void {
    state.refs -= 1;
    if (state.refs == 0) {
        _ = c.curl_share_cleanup(state.handle);
        std.heap.page_allocator.destroy(state);
    }
}

fn releaseEasyShare(obj: *PhpObject) void {
    if (getEasyShare(obj)) |state| {
        obj.native.extra = 0;
        releaseShare(state);
    }
}

fn cleanupShare(obj: *PhpObject) bool {
    if (obj.pooled) return true;
    if (getShareState(obj)) |state| {
        obj.native.ptr = 0;
        releaseShare(state);
    }
    return true;
}

fn requireShare(ctx: *NativeContext, args: []const Value, name: []const u8) RuntimeError!*ShareState {
    if (args.len > 0 and args[0] == .object and std.mem.eql(u8, args[0].object.class_name, "CurlShareHandle")) {
        if (getShareState(args[0].object)) |state| return state;
    }
    const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): Argument #1 ($share_handle) must be of type CurlShareHandle", .{name});
    try ctx.vm.setPendingException("TypeError", msg);
    return error.RuntimeError;
}

fn curlShareInit(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    ensureGlobalInit();
    const handle = c.curl_share_init() orelse return NativeResult.scalar(.{ .bool = false });
    errdefer _ = c.curl_share_cleanup(handle);
    const state = try std.heap.page_allocator.create(ShareState);
    errdefer std.heap.page_allocator.destroy(state);
    const obj = try ctx.createObject("CurlShareHandle");
    state.* = .{ .handle = handle };
    obj.native = .{ .kind = .curl_share, .ptr = @intFromPtr(state) };
    return NativeResult.borrowed(.{ .object = obj });
}

fn curlShareClose(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // Like PHP 8, close is a validated no-op; destruction owns cleanup.
    _ = try requireShare(ctx, args, "curl_share_close");
    return NativeResult.scalar(.null);
}

fn curlShareSetopt(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const state = try requireShare(ctx, args, "curl_share_setopt");
    if (args.len < 3) return NativeResult.scalar(.{ .bool = false });
    const option = Value.toInt(args[1]);
    if (option != c.CURLSHOPT_SHARE and option != c.CURLSHOPT_UNSHARE) {
        state.errno = c.CURLSHE_BAD_OPTION;
        try ctx.vm.setPendingException("ValueError", "curl_share_setopt(): Argument #2 ($option) is not a valid cURL share option");
        return error.RuntimeError;
    }
    const data: c_int = @truncate(Value.toInt(args[2]));
    state.errno = @intCast(c.curl_share_setopt(state.handle, @as(c_uint, @intCast(option)), data));
    return NativeResult.scalar(.{ .bool = state.errno == c.CURLSHE_OK });
}

fn curlShareErrno(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = (try requireShare(ctx, args, "curl_share_errno")).errno });
}

fn curlShareStrerror(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.null);
    const code: c_uint = @bitCast(@as(c_int, @truncate(Value.toInt(args[0]))));
    const msg = c.curl_share_strerror(code);
    if (msg == null) return NativeResult.scalar(.null);
    return try NativeResult.copyString(ctx.allocator, std.mem.span(msg));
}

// ---------------- curl_multi ----------------
// each easy handle added to a multi handle gets a heap-allocated
// WriteCallbackData so its response body survives from add_handle through
// curl_multi_getcontent. the WCB pointers live in a side table keyed by the
// easy CURL*. The side table and callback buffers use page_allocator;
// PhpObject property maps instead belong to the VM allocator.

var multi_wcb_table: std.AutoHashMapUnmanaged(usize, *WriteCallbackData) = .{};
var multi_wcb_mutex: sync.Mutex = .{};

fn getMultiHandle(obj: *PhpObject) ?*c.CURLM {
    return obj.native.get(c.CURLM, .curl_multi);
}

fn curlMultiInit(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    ensureGlobalInit();
    const mh = c.curl_multi_init() orelse return NativeResult.scalar(.{ .bool = false });
    const obj = try ctx.createObject("CurlMultiHandle");
    obj.native = .{ .kind = .curl_multi, .ptr = @intFromPtr(mh) };
    return NativeResult.borrowed(.{ .object = obj });
}

// the CurlHandle objects a multi handle holds, in the order they were added,
// kept on the multi object so curl_multi_get_handles and curl_multi_info_read
// can hand them back
fn multiHandles(ctx: *NativeContext, multi: *PhpObject) !*PhpArray {
    const existing = multi.get("__handles");
    if (existing == .array) return existing.array;
    const arr = try ctx.vm.allocArray();
    try multi.set(ctx.allocator, "__handles", .{ .array = arr });
    return arr;
}

// the key of a CurlHandle in the multi handle's list
fn multiHandleKey(list: *PhpArray, handle: *PhpObject) ?PhpArray.Key {
    for (list.entries.items) |entry| {
        if (entry.value == .object and entry.value.object == handle) return entry.key;
    }
    return null;
}

fn curlMultiGetHandles(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.null);
    const out = try ctx.createArray();
    for ((try multiHandles(ctx, args[0].object)).entries.items) |entry| try out.append(ctx.allocator, entry.value);
    return NativeResult.borrowed(.{ .array = out });
}

fn curlMultiAddHandle(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .object or args[1] != .object) return NativeResult.scalar(.{ .int = 1 });
    const mh = getMultiHandle(args[0].object) orelse return NativeResult.scalar(.{ .int = 1 });
    const easy = getHandle(args[1].object) orelse return NativeResult.scalar(.{ .int = 1 });
    // attach a persistent write buffer so getcontent() can read it later
    const return_transfer_v = args[1].object.get("__return_transfer");
    if (return_transfer_v == .bool and return_transfer_v.bool) {
        const wcb = std.heap.page_allocator.create(WriteCallbackData) catch return NativeResult.scalar(.{ .int = 1 });
        wcb.* = .{ .allocator = std.heap.page_allocator, .buffer = .empty };
        multi_wcb_mutex.lock();
        defer multi_wcb_mutex.unlock();
        multi_wcb_table.put(std.heap.page_allocator, @intFromPtr(easy), wcb) catch {
            wcb.buffer.deinit(wcb.allocator);
            std.heap.page_allocator.destroy(wcb);
            return NativeResult.scalar(.{ .int = 1 });
        };
        _ = c.curl_easy_setopt(easy, c.CURLOPT_WRITEFUNCTION, @as(?*const fn ([*]u8, usize, usize, *anyopaque) callconv(.c) usize, &writeCallback));
        _ = c.curl_easy_setopt(easy, c.CURLOPT_WRITEDATA, @as(*anyopaque, @ptrCast(wcb)));
    }
    const code = c.curl_multi_add_handle(mh, easy);
    if (code == c.CURLM_OK) try (try multiHandles(ctx, args[0].object)).append(ctx.allocator, args[1]);
    return NativeResult.scalar(.{ .int = @intCast(code) });
}

fn freeMultiWcb(easy: *c.CURL) void {
    multi_wcb_mutex.lock();
    defer multi_wcb_mutex.unlock();
    if (multi_wcb_table.fetchRemove(@intFromPtr(easy))) |kv| {
        kv.value.buffer.deinit(kv.value.allocator);
        std.heap.page_allocator.destroy(kv.value);
    }
}

fn curlMultiRemoveHandle(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .object or args[1] != .object) return NativeResult.scalar(.{ .int = 1 });
    const mh = getMultiHandle(args[0].object) orelse return NativeResult.scalar(.{ .int = 1 });
    const easy = getHandle(args[1].object) orelse return NativeResult.scalar(.{ .int = 1 });
    const code = c.curl_multi_remove_handle(mh, easy);
    freeMultiWcb(easy);
    const list = try multiHandles(ctx, args[0].object);
    if (multiHandleKey(list, args[1].object)) |key| ctx.vm.arrayRemoveOwned(list, key);
    return NativeResult.scalar(.{ .int = @intCast(code) });
}

fn curlMultiExec(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.{ .int = 1 });
    const mh = getMultiHandle(args[0].object) orelse return NativeResult.scalar(.{ .int = 1 });
    var still_running: c_int = 0;
    const code = c.curl_multi_perform(mh, &still_running);
    // 2nd arg is by-ref: write the still-running count back
    if (args.len >= 2) {
        ctx.setCallerVar(1, args.len, .{ .int = @intCast(still_running) });
    }
    return NativeResult.scalar(.{ .int = @intCast(code) });
}

fn curlMultiSelect(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.{ .int = -1 });
    const mh = getMultiHandle(args[0].object) orelse return NativeResult.scalar(.{ .int = -1 });
    const timeout_ms: c_int = if (args.len >= 2) blk: {
        const secs: f64 = switch (args[1]) {
            .float => |f| f,
            .int => |i| @floatFromInt(i),
            else => 1.0,
        };
        break :blk @intCast(std.math.clamp(Value.dvalToLval(secs * 1000.0), std.math.minInt(c_int), std.math.maxInt(c_int)));
    } else 1000;
    var numfds: c_int = 0;
    const code = c.curl_multi_poll(mh, null, 0, timeout_ms, &numfds);
    if (code != c.CURLM_OK) return NativeResult.scalar(.{ .int = -1 });
    return NativeResult.scalar(.{ .int = @intCast(numfds) });
}

fn curlMultiGetcontent(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.null);
    const easy = getHandle(args[0].object) orelse return NativeResult.scalar(.null);
    multi_wcb_mutex.lock();
    defer multi_wcb_mutex.unlock();
    const wcb = multi_wcb_table.get(@intFromPtr(easy)) orelse return NativeResult.scalar(.null);
    const str = try Value.String.create(ctx.allocator, wcb.buffer.items);
    return NativeResult.takeString(str);
}

fn curlMultiInfoRead(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const mh = getMultiHandle(args[0].object) orelse return NativeResult.scalar(.{ .bool = false });
    var msgs_in_queue: c_int = 0;
    const msg = c.curl_multi_info_read(mh, &msgs_in_queue);
    if (msg == null) return NativeResult.scalar(.{ .bool = false });
    const arr = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("msg") }, .{ .int = @intCast(msg.*.msg) });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("result") }, .{ .int = @intCast(msg.*.data.result) });
    // the finished transfer's CurlHandle, which callers compare by identity
    for ((try multiHandles(ctx, args[0].object)).entries.items) |entry| {
        if (entry.value == .object and getHandle(entry.value.object) == msg.*.easy_handle) {
            try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("handle") }, entry.value);
            break;
        }
    }
    if (args.len >= 2) {
        ctx.setCallerVar(1, args.len, .{ .int = @intCast(msgs_in_queue) });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn curlMultiClose(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.null);
    const mh = getMultiHandle(args[0].object) orelse return NativeResult.scalar(.null);
    _ = c.curl_multi_cleanup(mh);
    args[0].object.native.ptr = 0;
    return NativeResult.scalar(.null);
}

fn curlMultiStrerror(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .int) return NativeResult.scalar(.null);
    const msg = c.curl_multi_strerror(@intCast(args[0].int));
    const str = try Value.String.create(ctx.allocator, std.mem.span(msg));
    return NativeResult.takeString(str);
}

fn curlMultiErrno(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = 0 });
}

fn curlMultiSetopt(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // CURLMOPT_* options (pipelining, max connections, etc.) are accepted but
    // not all are wired - libcurl tolerates the defaults for correctness
    return NativeResult.scalar(.{ .bool = true });
}

// ---------------- CURLFile ----------------
// PHP exposes name/mime/postname as public properties; the getters/setters
// just read/write those. curl_setopt(CURLOPT_POSTFIELDS) detects a CURLFile
// inside an array and builds a multipart body

fn curlFileConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const name: []const u8 = if (args.len >= 1 and args[0] == .string) args[0].string.bytes() else "";
    const mime: []const u8 = if (args.len >= 2 and args[1] == .string) args[1].string.bytes() else "";
    const postname: []const u8 = if (args.len >= 3 and args[2] == .string) args[2].string.bytes() else "";
    try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(name) });
    try obj.set(ctx.allocator, "mime", .{ .string = Value.String.borrowed(mime) });
    try obj.set(ctx.allocator, "postname", .{ .string = Value.String.borrowed(postname) });
    return NativeResult.scalar(.null);
}

fn curlFileGetFilename(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(obj.get("name"));
}

fn curlFileGetMimeType(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(obj.get("mime"));
}

fn curlFileGetPostFilename(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(obj.get("postname"));
}

fn curlFileSetMimeType(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len >= 1 and args[0] == .string) try obj.set(ctx.allocator, "mime", args[0]);
    return NativeResult.scalar(.null);
}

fn curlFileSetPostFilename(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len >= 1 and args[0] == .string) try obj.set(ctx.allocator, "postname", args[0]);
    return NativeResult.scalar(.null);
}

fn curlFileCreate(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = try ctx.createObject("CURLFile");
    const name: []const u8 = if (args.len >= 1 and args[0] == .string) args[0].string.bytes() else "";
    const mime: []const u8 = if (args.len >= 2 and args[1] == .string) args[1].string.bytes() else "";
    const postname: []const u8 = if (args.len >= 3 and args[2] == .string) args[2].string.bytes() else "";
    try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(name) });
    try obj.set(ctx.allocator, "mime", .{ .string = Value.String.borrowed(mime) });
    try obj.set(ctx.allocator, "postname", .{ .string = Value.String.borrowed(postname) });
    return NativeResult.borrowed(.{ .object = obj });
}

fn curlEscape(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    if (args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const handle = getHandle(args[0].object) orelse return NativeResult.scalar(.{ .bool = false });
    const s = args[1].string.bytes();
    const encoded = c.curl_easy_escape(handle, s.ptr, @intCast(s.len));
    if (encoded == null) return NativeResult.scalar(.{ .bool = false });
    defer c.curl_free(encoded);
    const span = std.mem.span(encoded);
    const owned = try ctx.allocator.dupe(u8, span);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, owned));
}

fn curlUnescape(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    if (args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const handle = getHandle(args[0].object) orelse return NativeResult.scalar(.{ .bool = false });
    const s = args[1].string.bytes();
    var out_len: c_int = 0;
    const decoded = c.curl_easy_unescape(handle, s.ptr, @intCast(s.len), &out_len);
    if (decoded == null) return NativeResult.scalar(.{ .bool = false });
    defer c.curl_free(decoded);
    const slice = decoded[0..@as(usize, @intCast(out_len))];
    const owned = try ctx.allocator.dupe(u8, slice);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, owned));
}

fn curlVersion(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const info = c.curl_version_info(c.CURLVERSION_NOW) orelse return NativeResult.scalar(.{ .bool = false });
    const arr = try ctx.createArray();

    // PHP emits in this exact order. include every key it does so
    // is_array+key checks line up
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("version_number") }, .{ .int = @intCast(info.*.version_num) });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("age") }, .{ .int = @intCast(info.*.age) });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("features") }, .{ .int = @intCast(info.*.features) });

    // feature_list - empty array unless we wanted to translate bitmask names
    const fl = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("feature_list") }, .{ .array = fl });

    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("ssl_version_number") }, .{ .int = 0 });

    if (info.*.version) |ver| {
        try arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("version") }, std.mem.span(ver));
    }
    if (info.*.host) |host| {
        try arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("host") }, std.mem.span(host));
    }
    if (info.*.ssl_version) |ssl| {
        try arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("ssl_version") }, std.mem.span(ssl));
    }
    if (info.*.libz_version) |zlib| {
        try arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("libz_version") }, std.mem.span(zlib));
    }

    // protocols list - populate from null-terminated list of strings
    const protocols_arr = try ctx.createArray();
    if (info.*.protocols) |protos| {
        var i: usize = 0;
        while (protos[i] != null) : (i += 1) {
            try protocols_arr.setCopiedString(ctx.allocator, .{ .int = @intCast(i) }, std.mem.span(protos[i]));
        }
    }
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("protocols") }, .{ .array = protocols_arr });

    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("ares") }, .{ .string = Value.String.borrowed("") });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("ares_num") }, .{ .int = 0 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("libidn") }, .{ .string = Value.String.borrowed("") });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("iconv_ver_num") }, .{ .int = 0 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("libssh_version") }, .{ .string = Value.String.borrowed("") });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("brotli_ver_num") }, .{ .int = 0 });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("brotli_version") }, .{ .string = Value.String.borrowed("") });

    return NativeResult.borrowed(.{ .array = arr });
}

fn cleanupPoolable(obj: *PhpObject) bool {
    cleanupHandle(obj);
    return true;
}

pub fn register(vm: *VM, a: std.mem.Allocator) !void {
    var curl_def = ClassDef{ .name = "CurlHandle", .is_final = true, .native_cleanup = cleanupPoolable, .native_clone = cloneHandle };
    try vm.classes.put(a, "CurlHandle", curl_def);
    _ = &curl_def;

    var share_def = ClassDef{ .name = "CurlShareHandle", .is_final = true, .native_cleanup = cleanupShare };
    try vm.classes.put(a, "CurlShareHandle", share_def);
    _ = &share_def;

    var mh_def = ClassDef{ .name = "CurlMultiHandle", .is_final = true };
    try vm.classes.put(a, "CurlMultiHandle", mh_def);
    _ = &mh_def;

    // CURLFile - multipart upload descriptor. plain-data class with native
    // accessor methods; the constructor stores filename/mime/postname and
    // curl_setopt(CURLOPT_POSTFIELDS) recognizes it for multipart bodies
    var cf_def = ClassDef{ .name = "CURLFile" };
    try cf_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 3 });
    try cf_def.methods.put(a, "getFilename", .{ .name = "getFilename", .arity = 0 });
    try cf_def.methods.put(a, "getMimeType", .{ .name = "getMimeType", .arity = 0 });
    try cf_def.methods.put(a, "getPostFilename", .{ .name = "getPostFilename", .arity = 0 });
    try cf_def.methods.put(a, "setMimeType", .{ .name = "setMimeType", .arity = 1 });
    try cf_def.methods.put(a, "setPostFilename", .{ .name = "setPostFilename", .arity = 1 });
    try vm.classes.put(a, "CURLFile", cf_def);
    try vm.native_fns.put(a, "CURLFile::__construct", curlFileConstruct);
    try vm.native_fns.put(a, "CURLFile::getFilename", curlFileGetFilename);
    try vm.native_fns.put(a, "CURLFile::getMimeType", curlFileGetMimeType);
    try vm.native_fns.put(a, "CURLFile::getPostFilename", curlFileGetPostFilename);
    try vm.native_fns.put(a, "CURLFile::setMimeType", curlFileSetMimeType);
    try vm.native_fns.put(a, "CURLFile::setPostFilename", curlFileSetPostFilename);

    try vm.php_constants.put(a, "CURLM_OK", .{ .int = 0 });
    try vm.php_constants.put(a, "CURLM_BAD_HANDLE", .{ .int = 1 });
    try vm.php_constants.put(a, "CURLM_BAD_EASY_HANDLE", .{ .int = 2 });
    try vm.php_constants.put(a, "CURLM_OUT_OF_MEMORY", .{ .int = 3 });
    try vm.php_constants.put(a, "CURLM_INTERNAL_ERROR", .{ .int = 4 });
    try vm.php_constants.put(a, "CURLM_CALL_MULTI_PERFORM", .{ .int = -1 });
    try vm.php_constants.put(a, "CURLMOPT_PIPELINING", .{ .int = 3 });
    try vm.php_constants.put(a, "CURLPIPE_NOTHING", .{ .int = 0 });
    try vm.php_constants.put(a, "CURLPIPE_HTTP1", .{ .int = 1 });
    try vm.php_constants.put(a, "CURLPIPE_MULTIPLEX", .{ .int = 2 });
    try vm.php_constants.put(a, "CURLMOPT_MAX_HOST_CONNECTIONS", .{ .int = 7 });
    try vm.php_constants.put(a, "CURLSHOPT_SHARE", .{ .int = 1 });
    try vm.php_constants.put(a, "CURL_LOCK_DATA_COOKIE", .{ .int = 2 });
    try vm.php_constants.put(a, "CURL_LOCK_DATA_DNS", .{ .int = 3 });
    try vm.php_constants.put(a, "CURL_LOCK_DATA_SSL_SESSION", .{ .int = 4 });

    inline for (.{ "CURLSHOPT_UNSHARE", "CURL_LOCK_DATA_CONNECT", "CURL_LOCK_DATA_PSL", "CURLOPT_SHARE", "CURLOPT_COOKIELIST", "CURLINFO_COOKIELIST" }) |name| {
        try vm.php_constants.put(a, name, .{ .int = @field(c, name) });
    }

    // CURLOPT constants
    try vm.php_constants.put(a, "CURLOPT_URL", .{ .int = c.CURLOPT_URL });
    try vm.php_constants.put(a, "CURLOPT_PORT", .{ .int = c.CURLOPT_PORT });
    try vm.php_constants.put(a, "CURLOPT_RETURNTRANSFER", .{ .int = 19913 });
    try vm.php_constants.put(a, "CURLOPT_FOLLOWLOCATION", .{ .int = c.CURLOPT_FOLLOWLOCATION });
    try vm.php_constants.put(a, "CURLOPT_MAXREDIRS", .{ .int = c.CURLOPT_MAXREDIRS });
    try vm.php_constants.put(a, "CURLOPT_POST", .{ .int = c.CURLOPT_POST });
    try vm.php_constants.put(a, "CURLOPT_POSTFIELDS", .{ .int = c.CURLOPT_POSTFIELDS });
    try vm.php_constants.put(a, "CURLOPT_HTTPHEADER", .{ .int = c.CURLOPT_HTTPHEADER });
    try vm.php_constants.put(a, "CURLOPT_USERAGENT", .{ .int = c.CURLOPT_USERAGENT });
    try vm.php_constants.put(a, "CURLOPT_REFERER", .{ .int = c.CURLOPT_REFERER });
    try vm.php_constants.put(a, "CURLOPT_COOKIE", .{ .int = c.CURLOPT_COOKIE });
    try vm.php_constants.put(a, "CURLOPT_COOKIEFILE", .{ .int = c.CURLOPT_COOKIEFILE });
    try vm.php_constants.put(a, "CURLOPT_COOKIEJAR", .{ .int = c.CURLOPT_COOKIEJAR });
    try vm.php_constants.put(a, "CURLOPT_USERPWD", .{ .int = c.CURLOPT_USERPWD });
    try vm.php_constants.put(a, "CURLOPT_TIMEOUT", .{ .int = c.CURLOPT_TIMEOUT });
    try vm.php_constants.put(a, "CURLOPT_TIMEOUT_MS", .{ .int = c.CURLOPT_TIMEOUT_MS });
    try vm.php_constants.put(a, "CURLOPT_CONNECTTIMEOUT", .{ .int = c.CURLOPT_CONNECTTIMEOUT });
    try vm.php_constants.put(a, "CURLOPT_CONNECTTIMEOUT_MS", .{ .int = c.CURLOPT_CONNECTTIMEOUT_MS });
    try vm.php_constants.put(a, "CURLOPT_SSL_VERIFYPEER", .{ .int = c.CURLOPT_SSL_VERIFYPEER });
    try vm.php_constants.put(a, "CURLOPT_SSL_VERIFYHOST", .{ .int = c.CURLOPT_SSL_VERIFYHOST });
    try vm.php_constants.put(a, "CURLOPT_CUSTOMREQUEST", .{ .int = c.CURLOPT_CUSTOMREQUEST });
    try vm.php_constants.put(a, "CURLOPT_HEADER", .{ .int = c.CURLOPT_HEADER });
    try vm.php_constants.put(a, "CURLOPT_NOBODY", .{ .int = c.CURLOPT_NOBODY });
    try vm.php_constants.put(a, "CURLOPT_PUT", .{ .int = c.CURLOPT_PUT });
    try vm.php_constants.put(a, "CURLOPT_HTTPGET", .{ .int = c.CURLOPT_HTTPGET });
    try vm.php_constants.put(a, "CURLOPT_UPLOAD", .{ .int = c.CURLOPT_UPLOAD });
    try vm.php_constants.put(a, "CURLOPT_ENCODING", .{ .int = c.CURLOPT_ENCODING });
    try vm.php_constants.put(a, "CURLOPT_VERBOSE", .{ .int = c.CURLOPT_VERBOSE });
    try vm.php_constants.put(a, "CURLOPT_FAILONERROR", .{ .int = c.CURLOPT_FAILONERROR });
    try vm.php_constants.put(a, "CURLOPT_FRESH_CONNECT", .{ .int = c.CURLOPT_FRESH_CONNECT });
    try vm.php_constants.put(a, "CURLOPT_FORBID_REUSE", .{ .int = c.CURLOPT_FORBID_REUSE });
    try vm.php_constants.put(a, "CURLOPT_TCP_NODELAY", .{ .int = c.CURLOPT_TCP_NODELAY });
    try vm.php_constants.put(a, "CURLOPT_PROXY", .{ .int = c.CURLOPT_PROXY });
    try vm.php_constants.put(a, "CURLOPT_PROXYPORT", .{ .int = c.CURLOPT_PROXYPORT });
    try vm.php_constants.put(a, "CURLOPT_PROXYTYPE", .{ .int = c.CURLOPT_PROXYTYPE });
    try vm.php_constants.put(a, "CURLOPT_PROXYUSERPWD", .{ .int = c.CURLOPT_PROXYUSERPWD });
    try vm.php_constants.put(a, "CURLOPT_HTTPAUTH", .{ .int = c.CURLOPT_HTTPAUTH });
    try vm.php_constants.put(a, "CURLOPT_SSLVERSION", .{ .int = c.CURLOPT_SSLVERSION });
    try vm.php_constants.put(a, "CURLOPT_CAINFO", .{ .int = c.CURLOPT_CAINFO });
    try vm.php_constants.put(a, "CURLOPT_CAPATH", .{ .int = c.CURLOPT_CAPATH });
    try vm.php_constants.put(a, "CURLOPT_SSLCERT", .{ .int = c.CURLOPT_SSLCERT });
    try vm.php_constants.put(a, "CURLOPT_SSLKEY", .{ .int = c.CURLOPT_SSLKEY });
    try vm.php_constants.put(a, "CURLOPT_SSLKEYPASSWD", .{ .int = c.CURLOPT_KEYPASSWD });
    try vm.php_constants.put(a, "CURLOPT_RANGE", .{ .int = c.CURLOPT_RANGE });
    try vm.php_constants.put(a, "CURLOPT_INTERFACE", .{ .int = c.CURLOPT_INTERFACE });
    try vm.php_constants.put(a, "CURLOPT_UNIX_SOCKET_PATH", .{ .int = c.CURLOPT_UNIX_SOCKET_PATH });

    // CURLINFO constants
    try vm.php_constants.put(a, "CURLINFO_EFFECTIVE_URL", .{ .int = c.CURLINFO_EFFECTIVE_URL });
    try vm.php_constants.put(a, "CURLINFO_HTTP_CODE", .{ .int = c.CURLINFO_RESPONSE_CODE });
    try vm.php_constants.put(a, "CURLINFO_RESPONSE_CODE", .{ .int = c.CURLINFO_RESPONSE_CODE });
    try vm.php_constants.put(a, "CURLINFO_CONTENT_TYPE", .{ .int = c.CURLINFO_CONTENT_TYPE });
    try vm.php_constants.put(a, "CURLINFO_HEADER_SIZE", .{ .int = c.CURLINFO_HEADER_SIZE });
    try vm.php_constants.put(a, "CURLINFO_REQUEST_SIZE", .{ .int = c.CURLINFO_REQUEST_SIZE });
    try vm.php_constants.put(a, "CURLINFO_REDIRECT_COUNT", .{ .int = c.CURLINFO_REDIRECT_COUNT });
    try vm.php_constants.put(a, "CURLINFO_REDIRECT_URL", .{ .int = c.CURLINFO_REDIRECT_URL });
    try vm.php_constants.put(a, "CURLINFO_TOTAL_TIME", .{ .int = c.CURLINFO_TOTAL_TIME });
    try vm.php_constants.put(a, "CURLINFO_NAMELOOKUP_TIME", .{ .int = c.CURLINFO_NAMELOOKUP_TIME });
    try vm.php_constants.put(a, "CURLINFO_CONNECT_TIME", .{ .int = c.CURLINFO_CONNECT_TIME });
    try vm.php_constants.put(a, "CURLINFO_PRETRANSFER_TIME", .{ .int = c.CURLINFO_PRETRANSFER_TIME });
    try vm.php_constants.put(a, "CURLINFO_STARTTRANSFER_TIME", .{ .int = c.CURLINFO_STARTTRANSFER_TIME });
    try vm.php_constants.put(a, "CURLINFO_REDIRECT_TIME", .{ .int = c.CURLINFO_REDIRECT_TIME });
    try vm.php_constants.put(a, "CURLINFO_PRIMARY_IP", .{ .int = c.CURLINFO_PRIMARY_IP });
    try vm.php_constants.put(a, "CURLINFO_PRIMARY_PORT", .{ .int = c.CURLINFO_PRIMARY_PORT });
    try vm.php_constants.put(a, "CURLINFO_SSL_VERIFYRESULT", .{ .int = c.CURLINFO_SSL_VERIFYRESULT });
    try vm.php_constants.put(a, "CURLINFO_CONTENT_LENGTH_DOWNLOAD", .{ .int = c.CURLINFO_CONTENT_LENGTH_DOWNLOAD });
    try vm.php_constants.put(a, "CURLINFO_CONTENT_LENGTH_UPLOAD", .{ .int = c.CURLINFO_CONTENT_LENGTH_UPLOAD });
    try vm.php_constants.put(a, "CURLINFO_SCHEME", .{ .int = c.CURLINFO_SCHEME });
    try vm.php_constants.put(a, "CURLINFO_HEADER_OUT", .{ .int = c.CURLINFO_HEADER_OUT });

    // CURLAUTH constants
    try vm.php_constants.put(a, "CURLAUTH_BASIC", .{ .int = c.CURLAUTH_BASIC });
    try vm.php_constants.put(a, "CURLAUTH_DIGEST", .{ .int = c.CURLAUTH_DIGEST });
    try vm.php_constants.put(a, "CURLAUTH_BEARER", .{ .int = c.CURLAUTH_BEARER });

    // CURL_HTTP_VERSION constants
    try vm.php_constants.put(a, "CURL_HTTP_VERSION_NONE", .{ .int = 0 });
    try vm.php_constants.put(a, "CURL_HTTP_VERSION_1_0", .{ .int = 1 });
    try vm.php_constants.put(a, "CURL_HTTP_VERSION_1_1", .{ .int = 2 });
    try vm.php_constants.put(a, "CURL_HTTP_VERSION_2_0", .{ .int = 3 });

    // error code constants
    try vm.php_constants.put(a, "CURLE_OK", .{ .int = c.CURLE_OK });
    try vm.php_constants.put(a, "CURLE_UNSUPPORTED_PROTOCOL", .{ .int = c.CURLE_UNSUPPORTED_PROTOCOL });
    try vm.php_constants.put(a, "CURLE_URL_MALFORMAT", .{ .int = c.CURLE_URL_MALFORMAT });
    try vm.php_constants.put(a, "CURLE_COULDNT_RESOLVE_HOST", .{ .int = c.CURLE_COULDNT_RESOLVE_HOST });
    try vm.php_constants.put(a, "CURLE_COULDNT_CONNECT", .{ .int = c.CURLE_COULDNT_CONNECT });
    try vm.php_constants.put(a, "CURLE_OPERATION_TIMEDOUT", .{ .int = c.CURLE_OPERATION_TIMEDOUT });
    try vm.php_constants.put(a, "CURLE_SSL_CONNECT_ERROR", .{ .int = c.CURLE_SSL_CONNECT_ERROR });

    // the rest of php's constants, where the libcurl headers define them
    @setEvalBranchQuota(200000);
    inline for (php_curl_constants) |entry| {
        if (comptime curlConstantValue(entry[1])) |value| {
            if (!vm.php_constants.contains(entry[0])) try vm.php_constants.put(a, entry[0], .{ .int = value });
        }
    }
}

fn curlConstantValue(comptime name: []const u8) ?i64 {
    @setEvalBranchQuota(10000);
    // php's own (ext/curl/curl_private.h)
    if (std.mem.eql(u8, name, "CURLOPT_RETURNTRANSFER")) return 19913;
    if (std.mem.eql(u8, name, "CURLOPT_BINARYTRANSFER")) return 19914;
    if (std.mem.eql(u8, name, "CURLOPT_SAFE_UPLOAD")) return -1;
    if (!@hasDecl(c, name)) return null;
    const v = @field(c, name);
    return switch (@typeInfo(@TypeOf(v))) {
        // php stores the C value as a zend_long
        .comptime_int => if (v > std.math.maxInt(i64)) @bitCast(@as(u64, v)) else v,
        .int => |info| if (info.signedness == .unsigned and info.bits == 64) @bitCast(@as(u64, v)) else @intCast(v),
        .@"enum" => @intFromEnum(v),
        else => null,
    };
}

// every constant php's curl extension defines (ext/curl/curl_arginfo.h),
// with the libcurl name its value comes from
const php_curl_constants = [_][2][]const u8{
    .{ "CURLOPT_AUTOREFERER", "CURLOPT_AUTOREFERER" },
    .{ "CURLOPT_BINARYTRANSFER", "CURLOPT_BINARYTRANSFER" },
    .{ "CURLOPT_BUFFERSIZE", "CURLOPT_BUFFERSIZE" },
    .{ "CURLOPT_CAINFO", "CURLOPT_CAINFO" },
    .{ "CURLOPT_CAPATH", "CURLOPT_CAPATH" },
    .{ "CURLOPT_CONNECTTIMEOUT", "CURLOPT_CONNECTTIMEOUT" },
    .{ "CURLOPT_COOKIE", "CURLOPT_COOKIE" },
    .{ "CURLOPT_COOKIEFILE", "CURLOPT_COOKIEFILE" },
    .{ "CURLOPT_COOKIEJAR", "CURLOPT_COOKIEJAR" },
    .{ "CURLOPT_COOKIESESSION", "CURLOPT_COOKIESESSION" },
    .{ "CURLOPT_CRLF", "CURLOPT_CRLF" },
    .{ "CURLOPT_CUSTOMREQUEST", "CURLOPT_CUSTOMREQUEST" },
    .{ "CURLOPT_DNS_CACHE_TIMEOUT", "CURLOPT_DNS_CACHE_TIMEOUT" },
    .{ "CURLOPT_DNS_USE_GLOBAL_CACHE", "CURLOPT_DNS_USE_GLOBAL_CACHE" },
    .{ "CURLOPT_EGDSOCKET", "CURLOPT_EGDSOCKET" },
    .{ "CURLOPT_ENCODING", "CURLOPT_ACCEPT_ENCODING" },
    .{ "CURLOPT_FAILONERROR", "CURLOPT_FAILONERROR" },
    .{ "CURLOPT_FILE", "CURLOPT_FILE" },
    .{ "CURLOPT_FILETIME", "CURLOPT_FILETIME" },
    .{ "CURLOPT_FOLLOWLOCATION", "CURLOPT_FOLLOWLOCATION" },
    .{ "CURLOPT_FORBID_REUSE", "CURLOPT_FORBID_REUSE" },
    .{ "CURLOPT_FRESH_CONNECT", "CURLOPT_FRESH_CONNECT" },
    .{ "CURLOPT_FTPAPPEND", "CURLOPT_FTPAPPEND" },
    .{ "CURLOPT_FTPLISTONLY", "CURLOPT_FTPLISTONLY" },
    .{ "CURLOPT_FTPPORT", "CURLOPT_FTPPORT" },
    .{ "CURLOPT_FTP_USE_EPRT", "CURLOPT_FTP_USE_EPRT" },
    .{ "CURLOPT_FTP_USE_EPSV", "CURLOPT_FTP_USE_EPSV" },
    .{ "CURLOPT_HEADER", "CURLOPT_HEADER" },
    .{ "CURLOPT_HEADERFUNCTION", "CURLOPT_HEADERFUNCTION" },
    .{ "CURLOPT_HTTP200ALIASES", "CURLOPT_HTTP200ALIASES" },
    .{ "CURLOPT_HTTPGET", "CURLOPT_HTTPGET" },
    .{ "CURLOPT_HTTPHEADER", "CURLOPT_HTTPHEADER" },
    .{ "CURLOPT_HTTPPROXYTUNNEL", "CURLOPT_HTTPPROXYTUNNEL" },
    .{ "CURLOPT_HTTP_VERSION", "CURLOPT_HTTP_VERSION" },
    .{ "CURLOPT_INFILE", "CURLOPT_INFILE" },
    .{ "CURLOPT_INFILESIZE", "CURLOPT_INFILESIZE" },
    .{ "CURLOPT_INFILESIZE_LARGE", "CURLOPT_INFILESIZE_LARGE" },
    .{ "CURLOPT_INTERFACE", "CURLOPT_INTERFACE" },
    .{ "CURLOPT_KRB4LEVEL", "CURLOPT_KRB4LEVEL" },
    .{ "CURLOPT_LOW_SPEED_LIMIT", "CURLOPT_LOW_SPEED_LIMIT" },
    .{ "CURLOPT_LOW_SPEED_TIME", "CURLOPT_LOW_SPEED_TIME" },
    .{ "CURLOPT_MAXCONNECTS", "CURLOPT_MAXCONNECTS" },
    .{ "CURLOPT_MAXREDIRS", "CURLOPT_MAXREDIRS" },
    .{ "CURLOPT_NETRC", "CURLOPT_NETRC" },
    .{ "CURLOPT_NOBODY", "CURLOPT_NOBODY" },
    .{ "CURLOPT_NOPROGRESS", "CURLOPT_NOPROGRESS" },
    .{ "CURLOPT_NOSIGNAL", "CURLOPT_NOSIGNAL" },
    .{ "CURLOPT_PORT", "CURLOPT_PORT" },
    .{ "CURLOPT_POST", "CURLOPT_POST" },
    .{ "CURLOPT_POSTFIELDS", "CURLOPT_POSTFIELDS" },
    .{ "CURLOPT_POSTQUOTE", "CURLOPT_POSTQUOTE" },
    .{ "CURLOPT_PREQUOTE", "CURLOPT_PREQUOTE" },
    .{ "CURLOPT_PRIVATE", "CURLOPT_PRIVATE" },
    .{ "CURLOPT_PROGRESSFUNCTION", "CURLOPT_PROGRESSFUNCTION" },
    .{ "CURLOPT_PROXY", "CURLOPT_PROXY" },
    .{ "CURLOPT_PROXYPORT", "CURLOPT_PROXYPORT" },
    .{ "CURLOPT_PROXYTYPE", "CURLOPT_PROXYTYPE" },
    .{ "CURLOPT_PROXYUSERPWD", "CURLOPT_PROXYUSERPWD" },
    .{ "CURLOPT_PUT", "CURLOPT_PUT" },
    .{ "CURLOPT_QUOTE", "CURLOPT_QUOTE" },
    .{ "CURLOPT_RANDOM_FILE", "CURLOPT_RANDOM_FILE" },
    .{ "CURLOPT_RANGE", "CURLOPT_RANGE" },
    .{ "CURLOPT_READDATA", "CURLOPT_READDATA" },
    .{ "CURLOPT_READFUNCTION", "CURLOPT_READFUNCTION" },
    .{ "CURLOPT_REFERER", "CURLOPT_REFERER" },
    .{ "CURLOPT_RESUME_FROM", "CURLOPT_RESUME_FROM" },
    .{ "CURLOPT_RETURNTRANSFER", "CURLOPT_RETURNTRANSFER" },
    .{ "CURLOPT_SHARE", "CURLOPT_SHARE" },
    .{ "CURLOPT_SSLCERT", "CURLOPT_SSLCERT" },
    .{ "CURLOPT_SSLCERTPASSWD", "CURLOPT_SSLCERTPASSWD" },
    .{ "CURLOPT_SSLCERTTYPE", "CURLOPT_SSLCERTTYPE" },
    .{ "CURLOPT_SSLENGINE", "CURLOPT_SSLENGINE" },
    .{ "CURLOPT_SSLENGINE_DEFAULT", "CURLOPT_SSLENGINE_DEFAULT" },
    .{ "CURLOPT_SSLKEY", "CURLOPT_SSLKEY" },
    .{ "CURLOPT_SSLKEYPASSWD", "CURLOPT_SSLKEYPASSWD" },
    .{ "CURLOPT_SSLKEYTYPE", "CURLOPT_SSLKEYTYPE" },
    .{ "CURLOPT_SSLVERSION", "CURLOPT_SSLVERSION" },
    .{ "CURLOPT_SSL_CIPHER_LIST", "CURLOPT_SSL_CIPHER_LIST" },
    .{ "CURLOPT_SSL_VERIFYHOST", "CURLOPT_SSL_VERIFYHOST" },
    .{ "CURLOPT_SSL_VERIFYPEER", "CURLOPT_SSL_VERIFYPEER" },
    .{ "CURLOPT_STDERR", "CURLOPT_STDERR" },
    .{ "CURLOPT_TCP_KEEPCNT", "CURLOPT_TCP_KEEPCNT" },
    .{ "CURLOPT_TELNETOPTIONS", "CURLOPT_TELNETOPTIONS" },
    .{ "CURLOPT_TIMECONDITION", "CURLOPT_TIMECONDITION" },
    .{ "CURLOPT_TIMEOUT", "CURLOPT_TIMEOUT" },
    .{ "CURLOPT_TIMEVALUE", "CURLOPT_TIMEVALUE" },
    .{ "CURLOPT_TRANSFERTEXT", "CURLOPT_TRANSFERTEXT" },
    .{ "CURLOPT_UNRESTRICTED_AUTH", "CURLOPT_UNRESTRICTED_AUTH" },
    .{ "CURLOPT_UPLOAD", "CURLOPT_UPLOAD" },
    .{ "CURLOPT_URL", "CURLOPT_URL" },
    .{ "CURLOPT_USERAGENT", "CURLOPT_USERAGENT" },
    .{ "CURLOPT_USERPWD", "CURLOPT_USERPWD" },
    .{ "CURLOPT_VERBOSE", "CURLOPT_VERBOSE" },
    .{ "CURLOPT_WRITEFUNCTION", "CURLOPT_WRITEFUNCTION" },
    .{ "CURLOPT_WRITEHEADER", "CURLOPT_WRITEHEADER" },
    .{ "CURLOPT_XFERINFOFUNCTION", "CURLOPT_XFERINFOFUNCTION" },
    .{ "CURLOPT_DEBUGFUNCTION", "CURLOPT_DEBUGFUNCTION" },
    .{ "CURLFOLLOW_ALL", "CURLFOLLOW_ALL" },
    .{ "CURLFOLLOW_OBEYCODE", "CURLFOLLOW_OBEYCODE" },
    .{ "CURLFOLLOW_FIRSTONLY", "CURLFOLLOW_FIRSTONLY" },
    .{ "CURLINFO_TEXT", "CURLINFO_TEXT" },
    .{ "CURLINFO_HEADER_IN", "CURLINFO_HEADER_IN" },
    .{ "CURLINFO_DATA_IN", "CURLINFO_DATA_IN" },
    .{ "CURLINFO_DATA_OUT", "CURLINFO_DATA_OUT" },
    .{ "CURLINFO_SSL_DATA_OUT", "CURLINFO_SSL_DATA_OUT" },
    .{ "CURLINFO_SSL_DATA_IN", "CURLINFO_SSL_DATA_IN" },
    .{ "CURLE_ABORTED_BY_CALLBACK", "CURLE_ABORTED_BY_CALLBACK" },
    .{ "CURLE_BAD_CALLING_ORDER", "CURLE_BAD_CALLING_ORDER" },
    .{ "CURLE_BAD_CONTENT_ENCODING", "CURLE_BAD_CONTENT_ENCODING" },
    .{ "CURLE_BAD_DOWNLOAD_RESUME", "CURLE_BAD_DOWNLOAD_RESUME" },
    .{ "CURLE_BAD_FUNCTION_ARGUMENT", "CURLE_BAD_FUNCTION_ARGUMENT" },
    .{ "CURLE_BAD_PASSWORD_ENTERED", "CURLE_BAD_PASSWORD_ENTERED" },
    .{ "CURLE_COULDNT_CONNECT", "CURLE_COULDNT_CONNECT" },
    .{ "CURLE_COULDNT_RESOLVE_HOST", "CURLE_COULDNT_RESOLVE_HOST" },
    .{ "CURLE_COULDNT_RESOLVE_PROXY", "CURLE_COULDNT_RESOLVE_PROXY" },
    .{ "CURLE_FAILED_INIT", "CURLE_FAILED_INIT" },
    .{ "CURLE_FILE_COULDNT_READ_FILE", "CURLE_FILE_COULDNT_READ_FILE" },
    .{ "CURLE_FTP_ACCESS_DENIED", "CURLE_FTP_ACCESS_DENIED" },
    .{ "CURLE_FTP_BAD_DOWNLOAD_RESUME", "CURLE_FTP_BAD_DOWNLOAD_RESUME" },
    .{ "CURLE_FTP_CANT_GET_HOST", "CURLE_FTP_CANT_GET_HOST" },
    .{ "CURLE_FTP_CANT_RECONNECT", "CURLE_FTP_CANT_RECONNECT" },
    .{ "CURLE_FTP_COULDNT_GET_SIZE", "CURLE_FTP_COULDNT_GET_SIZE" },
    .{ "CURLE_FTP_COULDNT_RETR_FILE", "CURLE_FTP_COULDNT_RETR_FILE" },
    .{ "CURLE_FTP_COULDNT_SET_ASCII", "CURLE_FTP_COULDNT_SET_ASCII" },
    .{ "CURLE_FTP_COULDNT_SET_BINARY", "CURLE_FTP_COULDNT_SET_BINARY" },
    .{ "CURLE_FTP_COULDNT_STOR_FILE", "CURLE_FTP_COULDNT_STOR_FILE" },
    .{ "CURLE_FTP_COULDNT_USE_REST", "CURLE_FTP_COULDNT_USE_REST" },
    .{ "CURLE_FTP_PARTIAL_FILE", "CURLE_FTP_PARTIAL_FILE" },
    .{ "CURLE_FTP_PORT_FAILED", "CURLE_FTP_PORT_FAILED" },
    .{ "CURLE_FTP_QUOTE_ERROR", "CURLE_FTP_QUOTE_ERROR" },
    .{ "CURLE_FTP_USER_PASSWORD_INCORRECT", "CURLE_FTP_USER_PASSWORD_INCORRECT" },
    .{ "CURLE_FTP_WEIRD_227_FORMAT", "CURLE_FTP_WEIRD_227_FORMAT" },
    .{ "CURLE_FTP_WEIRD_PASS_REPLY", "CURLE_FTP_WEIRD_PASS_REPLY" },
    .{ "CURLE_FTP_WEIRD_PASV_REPLY", "CURLE_FTP_WEIRD_PASV_REPLY" },
    .{ "CURLE_FTP_WEIRD_SERVER_REPLY", "CURLE_FTP_WEIRD_SERVER_REPLY" },
    .{ "CURLE_FTP_WEIRD_USER_REPLY", "CURLE_FTP_WEIRD_USER_REPLY" },
    .{ "CURLE_FTP_WRITE_ERROR", "CURLE_FTP_WRITE_ERROR" },
    .{ "CURLE_FUNCTION_NOT_FOUND", "CURLE_FUNCTION_NOT_FOUND" },
    .{ "CURLE_GOT_NOTHING", "CURLE_GOT_NOTHING" },
    .{ "CURLE_HTTP_NOT_FOUND", "CURLE_HTTP_NOT_FOUND" },
    .{ "CURLE_HTTP_PORT_FAILED", "CURLE_HTTP_PORT_FAILED" },
    .{ "CURLE_HTTP_POST_ERROR", "CURLE_HTTP_POST_ERROR" },
    .{ "CURLE_HTTP_RANGE_ERROR", "CURLE_HTTP_RANGE_ERROR" },
    .{ "CURLE_HTTP_RETURNED_ERROR", "CURLE_HTTP_RETURNED_ERROR" },
    .{ "CURLE_LDAP_CANNOT_BIND", "CURLE_LDAP_CANNOT_BIND" },
    .{ "CURLE_LDAP_SEARCH_FAILED", "CURLE_LDAP_SEARCH_FAILED" },
    .{ "CURLE_LIBRARY_NOT_FOUND", "CURLE_LIBRARY_NOT_FOUND" },
    .{ "CURLE_MALFORMAT_USER", "CURLE_MALFORMAT_USER" },
    .{ "CURLE_OBSOLETE", "CURLE_OBSOLETE" },
    .{ "CURLE_OK", "CURLE_OK" },
    .{ "CURLE_OPERATION_TIMEDOUT", "CURLE_OPERATION_TIMEDOUT" },
    .{ "CURLE_OPERATION_TIMEOUTED", "CURLE_OPERATION_TIMEOUTED" },
    .{ "CURLE_OUT_OF_MEMORY", "CURLE_OUT_OF_MEMORY" },
    .{ "CURLE_PARTIAL_FILE", "CURLE_PARTIAL_FILE" },
    .{ "CURLE_READ_ERROR", "CURLE_READ_ERROR" },
    .{ "CURLE_RECV_ERROR", "CURLE_RECV_ERROR" },
    .{ "CURLE_SEND_ERROR", "CURLE_SEND_ERROR" },
    .{ "CURLE_SHARE_IN_USE", "CURLE_SHARE_IN_USE" },
    .{ "CURLE_SSL_CACERT", "CURLE_SSL_CACERT" },
    .{ "CURLE_SSL_CERTPROBLEM", "CURLE_SSL_CERTPROBLEM" },
    .{ "CURLE_SSL_CIPHER", "CURLE_SSL_CIPHER" },
    .{ "CURLE_SSL_CONNECT_ERROR", "CURLE_SSL_CONNECT_ERROR" },
    .{ "CURLE_SSL_ENGINE_NOTFOUND", "CURLE_SSL_ENGINE_NOTFOUND" },
    .{ "CURLE_SSL_ENGINE_SETFAILED", "CURLE_SSL_ENGINE_SETFAILED" },
    .{ "CURLE_SSL_PEER_CERTIFICATE", "CURLE_SSL_PEER_CERTIFICATE" },
    .{ "CURLE_SSL_PINNEDPUBKEYNOTMATCH", "CURLE_SSL_PINNEDPUBKEYNOTMATCH" },
    .{ "CURLE_TELNET_OPTION_SYNTAX", "CURLE_TELNET_OPTION_SYNTAX" },
    .{ "CURLE_TOO_MANY_REDIRECTS", "CURLE_TOO_MANY_REDIRECTS" },
    .{ "CURLE_UNKNOWN_TELNET_OPTION", "CURLE_UNKNOWN_TELNET_OPTION" },
    .{ "CURLE_UNSUPPORTED_PROTOCOL", "CURLE_UNSUPPORTED_PROTOCOL" },
    .{ "CURLE_URL_MALFORMAT", "CURLE_URL_MALFORMAT" },
    .{ "CURLE_URL_MALFORMAT_USER", "CURLE_URL_MALFORMAT_USER" },
    .{ "CURLE_WRITE_ERROR", "CURLE_WRITE_ERROR" },
    .{ "CURLINFO_CONNECT_TIME", "CURLINFO_CONNECT_TIME" },
    .{ "CURLINFO_CONTENT_LENGTH_DOWNLOAD", "CURLINFO_CONTENT_LENGTH_DOWNLOAD" },
    .{ "CURLINFO_CONTENT_LENGTH_UPLOAD", "CURLINFO_CONTENT_LENGTH_UPLOAD" },
    .{ "CURLINFO_CONTENT_TYPE", "CURLINFO_CONTENT_TYPE" },
    .{ "CURLINFO_EFFECTIVE_URL", "CURLINFO_EFFECTIVE_URL" },
    .{ "CURLINFO_FILETIME", "CURLINFO_FILETIME" },
    .{ "CURLINFO_HEADER_OUT", "CURLINFO_HEADER_OUT" },
    .{ "CURLINFO_HEADER_SIZE", "CURLINFO_HEADER_SIZE" },
    .{ "CURLINFO_HTTP_CODE", "CURLINFO_HTTP_CODE" },
    .{ "CURLINFO_LASTONE", "CURLINFO_LASTONE" },
    .{ "CURLINFO_NAMELOOKUP_TIME", "CURLINFO_NAMELOOKUP_TIME" },
    .{ "CURLINFO_PRETRANSFER_TIME", "CURLINFO_PRETRANSFER_TIME" },
    .{ "CURLINFO_PRIVATE", "CURLINFO_PRIVATE" },
    .{ "CURLINFO_REDIRECT_COUNT", "CURLINFO_REDIRECT_COUNT" },
    .{ "CURLINFO_REDIRECT_TIME", "CURLINFO_REDIRECT_TIME" },
    .{ "CURLINFO_REQUEST_SIZE", "CURLINFO_REQUEST_SIZE" },
    .{ "CURLINFO_SIZE_DOWNLOAD", "CURLINFO_SIZE_DOWNLOAD" },
    .{ "CURLINFO_SIZE_UPLOAD", "CURLINFO_SIZE_UPLOAD" },
    .{ "CURLINFO_SPEED_DOWNLOAD", "CURLINFO_SPEED_DOWNLOAD" },
    .{ "CURLINFO_SPEED_UPLOAD", "CURLINFO_SPEED_UPLOAD" },
    .{ "CURLINFO_SSL_VERIFYRESULT", "CURLINFO_SSL_VERIFYRESULT" },
    .{ "CURLINFO_STARTTRANSFER_TIME", "CURLINFO_STARTTRANSFER_TIME" },
    .{ "CURLINFO_TOTAL_TIME", "CURLINFO_TOTAL_TIME" },
    .{ "CURLINFO_EFFECTIVE_METHOD", "CURLINFO_EFFECTIVE_METHOD" },
    .{ "CURLINFO_CAPATH", "CURLINFO_CAPATH" },
    .{ "CURLINFO_CAINFO", "CURLINFO_CAINFO" },
    .{ "CURLINFO_HTTPAUTH_USED", "CURLINFO_HTTPAUTH_USED" },
    .{ "CURLINFO_PROXYAUTH_USED", "CURLINFO_PROXYAUTH_USED" },
    .{ "CURLMSG_DONE", "CURLMSG_DONE" },
    .{ "CURLVERSION_NOW", "CURLVERSION_NOW" },
    .{ "CURLM_BAD_EASY_HANDLE", "CURLM_BAD_EASY_HANDLE" },
    .{ "CURLM_BAD_HANDLE", "CURLM_BAD_HANDLE" },
    .{ "CURLM_CALL_MULTI_PERFORM", "CURLM_CALL_MULTI_PERFORM" },
    .{ "CURLM_INTERNAL_ERROR", "CURLM_INTERNAL_ERROR" },
    .{ "CURLM_OK", "CURLM_OK" },
    .{ "CURLM_OUT_OF_MEMORY", "CURLM_OUT_OF_MEMORY" },
    .{ "CURLM_ADDED_ALREADY", "CURLM_ADDED_ALREADY" },
    .{ "CURLPROXY_HTTP", "CURLPROXY_HTTP" },
    .{ "CURLPROXY_SOCKS4", "CURLPROXY_SOCKS4" },
    .{ "CURLPROXY_SOCKS5", "CURLPROXY_SOCKS5" },
    .{ "CURLSHOPT_NONE", "CURLSHOPT_NONE" },
    .{ "CURLSHOPT_SHARE", "CURLSHOPT_SHARE" },
    .{ "CURLSHOPT_UNSHARE", "CURLSHOPT_UNSHARE" },
    .{ "CURL_HTTP_VERSION_1_0", "CURL_HTTP_VERSION_1_0" },
    .{ "CURL_HTTP_VERSION_1_1", "CURL_HTTP_VERSION_1_1" },
    .{ "CURL_HTTP_VERSION_NONE", "CURL_HTTP_VERSION_NONE" },
    .{ "CURL_LOCK_DATA_COOKIE", "CURL_LOCK_DATA_COOKIE" },
    .{ "CURL_LOCK_DATA_DNS", "CURL_LOCK_DATA_DNS" },
    .{ "CURL_LOCK_DATA_SSL_SESSION", "CURL_LOCK_DATA_SSL_SESSION" },
    .{ "CURL_NETRC_IGNORED", "CURL_NETRC_IGNORED" },
    .{ "CURL_NETRC_OPTIONAL", "CURL_NETRC_OPTIONAL" },
    .{ "CURL_NETRC_REQUIRED", "CURL_NETRC_REQUIRED" },
    .{ "CURL_SSLVERSION_DEFAULT", "CURL_SSLVERSION_DEFAULT" },
    .{ "CURL_SSLVERSION_SSLv2", "CURL_SSLVERSION_SSLv2" },
    .{ "CURL_SSLVERSION_SSLv3", "CURL_SSLVERSION_SSLv3" },
    .{ "CURL_SSLVERSION_TLSv1", "CURL_SSLVERSION_TLSv1" },
    .{ "CURL_TIMECOND_IFMODSINCE", "CURL_TIMECOND_IFMODSINCE" },
    .{ "CURL_TIMECOND_IFUNMODSINCE", "CURL_TIMECOND_IFUNMODSINCE" },
    .{ "CURL_TIMECOND_LASTMOD", "CURL_TIMECOND_LASTMOD" },
    .{ "CURL_TIMECOND_NONE", "CURL_TIMECOND_NONE" },
    .{ "CURL_VERSION_ASYNCHDNS", "CURL_VERSION_ASYNCHDNS" },
    .{ "CURL_VERSION_CONV", "CURL_VERSION_CONV" },
    .{ "CURL_VERSION_DEBUG", "CURL_VERSION_DEBUG" },
    .{ "CURL_VERSION_GSSNEGOTIATE", "CURL_VERSION_GSSNEGOTIATE" },
    .{ "CURL_VERSION_IDN", "CURL_VERSION_IDN" },
    .{ "CURL_VERSION_IPV6", "CURL_VERSION_IPV6" },
    .{ "CURL_VERSION_KERBEROS4", "CURL_VERSION_KERBEROS4" },
    .{ "CURL_VERSION_LARGEFILE", "CURL_VERSION_LARGEFILE" },
    .{ "CURL_VERSION_LIBZ", "CURL_VERSION_LIBZ" },
    .{ "CURL_VERSION_NTLM", "CURL_VERSION_NTLM" },
    .{ "CURL_VERSION_SPNEGO", "CURL_VERSION_SPNEGO" },
    .{ "CURL_VERSION_SSL", "CURL_VERSION_SSL" },
    .{ "CURL_VERSION_SSPI", "CURL_VERSION_SSPI" },
    .{ "CURLOPT_HTTPAUTH", "CURLOPT_HTTPAUTH" },
    .{ "CURLAUTH_ANY", "CURLAUTH_ANY" },
    .{ "CURLAUTH_ANYSAFE", "CURLAUTH_ANYSAFE" },
    .{ "CURLAUTH_BASIC", "CURLAUTH_BASIC" },
    .{ "CURLAUTH_DIGEST", "CURLAUTH_DIGEST" },
    .{ "CURLAUTH_GSSNEGOTIATE", "CURLAUTH_GSSNEGOTIATE" },
    .{ "CURLAUTH_NONE", "CURLAUTH_NONE" },
    .{ "CURLAUTH_NTLM", "CURLAUTH_NTLM" },
    .{ "CURLINFO_HTTP_CONNECTCODE", "CURLINFO_HTTP_CONNECTCODE" },
    .{ "CURLOPT_FTP_CREATE_MISSING_DIRS", "CURLOPT_FTP_CREATE_MISSING_DIRS" },
    .{ "CURLOPT_PROXYAUTH", "CURLOPT_PROXYAUTH" },
    .{ "CURLE_FILESIZE_EXCEEDED", "CURLE_FILESIZE_EXCEEDED" },
    .{ "CURLE_LDAP_INVALID_URL", "CURLE_LDAP_INVALID_URL" },
    .{ "CURLINFO_HTTPAUTH_AVAIL", "CURLINFO_HTTPAUTH_AVAIL" },
    .{ "CURLINFO_RESPONSE_CODE", "CURLINFO_RESPONSE_CODE" },
    .{ "CURLINFO_PROXYAUTH_AVAIL", "CURLINFO_PROXYAUTH_AVAIL" },
    .{ "CURLOPT_FTP_RESPONSE_TIMEOUT", "CURLOPT_SERVER_RESPONSE_TIMEOUT" },
    .{ "CURLOPT_SERVER_RESPONSE_TIMEOUT", "CURLOPT_SERVER_RESPONSE_TIMEOUT" },
    .{ "CURLOPT_IPRESOLVE", "CURLOPT_IPRESOLVE" },
    .{ "CURLOPT_MAXFILESIZE", "CURLOPT_MAXFILESIZE" },
    .{ "CURL_IPRESOLVE_V4", "CURL_IPRESOLVE_V4" },
    .{ "CURL_IPRESOLVE_V6", "CURL_IPRESOLVE_V6" },
    .{ "CURL_IPRESOLVE_WHATEVER", "CURL_IPRESOLVE_WHATEVER" },
    .{ "CURLE_FTP_SSL_FAILED", "CURLE_FTP_SSL_FAILED" },
    .{ "CURLFTPSSL_ALL", "CURLFTPSSL_ALL" },
    .{ "CURLFTPSSL_CONTROL", "CURLFTPSSL_CONTROL" },
    .{ "CURLFTPSSL_NONE", "CURLFTPSSL_NONE" },
    .{ "CURLFTPSSL_TRY", "CURLFTPSSL_TRY" },
    .{ "CURLOPT_FTP_SSL", "CURLOPT_FTP_SSL" },
    .{ "CURLOPT_NETRC_FILE", "CURLOPT_NETRC_FILE" },
    .{ "CURLOPT_MAXFILESIZE_LARGE", "CURLOPT_MAXFILESIZE_LARGE" },
    .{ "CURLOPT_TCP_NODELAY", "CURLOPT_TCP_NODELAY" },
    .{ "CURLFTPAUTH_DEFAULT", "CURLFTPAUTH_DEFAULT" },
    .{ "CURLFTPAUTH_SSL", "CURLFTPAUTH_SSL" },
    .{ "CURLFTPAUTH_TLS", "CURLFTPAUTH_TLS" },
    .{ "CURLOPT_FTPSSLAUTH", "CURLOPT_FTPSSLAUTH" },
    .{ "CURLOPT_FTP_ACCOUNT", "CURLOPT_FTP_ACCOUNT" },
    .{ "CURLINFO_OS_ERRNO", "CURLINFO_OS_ERRNO" },
    .{ "CURLINFO_NUM_CONNECTS", "CURLINFO_NUM_CONNECTS" },
    .{ "CURLINFO_SSL_ENGINES", "CURLINFO_SSL_ENGINES" },
    .{ "CURLINFO_COOKIELIST", "CURLINFO_COOKIELIST" },
    .{ "CURLOPT_COOKIELIST", "CURLOPT_COOKIELIST" },
    .{ "CURLOPT_IGNORE_CONTENT_LENGTH", "CURLOPT_IGNORE_CONTENT_LENGTH" },
    .{ "CURLOPT_FTP_SKIP_PASV_IP", "CURLOPT_FTP_SKIP_PASV_IP" },
    .{ "CURLOPT_FTP_FILEMETHOD", "CURLOPT_FTP_FILEMETHOD" },
    .{ "CURLOPT_CONNECT_ONLY", "CURLOPT_CONNECT_ONLY" },
    .{ "CURLOPT_LOCALPORT", "CURLOPT_LOCALPORT" },
    .{ "CURLOPT_LOCALPORTRANGE", "CURLOPT_LOCALPORTRANGE" },
    .{ "CURLFTPMETHOD_DEFAULT", "CURLFTPMETHOD_DEFAULT" },
    .{ "CURLFTPMETHOD_MULTICWD", "CURLFTPMETHOD_MULTICWD" },
    .{ "CURLFTPMETHOD_NOCWD", "CURLFTPMETHOD_NOCWD" },
    .{ "CURLFTPMETHOD_SINGLECWD", "CURLFTPMETHOD_SINGLECWD" },
    .{ "CURLINFO_FTP_ENTRY_PATH", "CURLINFO_FTP_ENTRY_PATH" },
    .{ "CURLOPT_FTP_ALTERNATIVE_TO_USER", "CURLOPT_FTP_ALTERNATIVE_TO_USER" },
    .{ "CURLOPT_MAX_RECV_SPEED_LARGE", "CURLOPT_MAX_RECV_SPEED_LARGE" },
    .{ "CURLOPT_MAX_SEND_SPEED_LARGE", "CURLOPT_MAX_SEND_SPEED_LARGE" },
    .{ "CURLE_SSL_CACERT_BADFILE", "CURLE_SSL_CACERT_BADFILE" },
    .{ "CURLOPT_SSL_SESSIONID_CACHE", "CURLOPT_SSL_SESSIONID_CACHE" },
    .{ "CURLMOPT_PIPELINING", "CURLMOPT_PIPELINING" },
    .{ "CURLE_SSH", "CURLE_SSH" },
    .{ "CURLOPT_FTP_SSL_CCC", "CURLOPT_FTP_SSL_CCC" },
    .{ "CURLOPT_SSH_AUTH_TYPES", "CURLOPT_SSH_AUTH_TYPES" },
    .{ "CURLOPT_SSH_PRIVATE_KEYFILE", "CURLOPT_SSH_PRIVATE_KEYFILE" },
    .{ "CURLOPT_SSH_PUBLIC_KEYFILE", "CURLOPT_SSH_PUBLIC_KEYFILE" },
    .{ "CURLFTPSSL_CCC_ACTIVE", "CURLFTPSSL_CCC_ACTIVE" },
    .{ "CURLFTPSSL_CCC_NONE", "CURLFTPSSL_CCC_NONE" },
    .{ "CURLFTPSSL_CCC_PASSIVE", "CURLFTPSSL_CCC_PASSIVE" },
    .{ "CURLOPT_CONNECTTIMEOUT_MS", "CURLOPT_CONNECTTIMEOUT_MS" },
    .{ "CURLOPT_HTTP_CONTENT_DECODING", "CURLOPT_HTTP_CONTENT_DECODING" },
    .{ "CURLOPT_HTTP_TRANSFER_DECODING", "CURLOPT_HTTP_TRANSFER_DECODING" },
    .{ "CURLOPT_TIMEOUT_MS", "CURLOPT_TIMEOUT_MS" },
    .{ "CURLMOPT_MAXCONNECTS", "CURLMOPT_MAXCONNECTS" },
    .{ "CURLOPT_KRBLEVEL", "CURLOPT_KRBLEVEL" },
    .{ "CURLOPT_NEW_DIRECTORY_PERMS", "CURLOPT_NEW_DIRECTORY_PERMS" },
    .{ "CURLOPT_NEW_FILE_PERMS", "CURLOPT_NEW_FILE_PERMS" },
    .{ "CURLOPT_APPEND", "CURLOPT_APPEND" },
    .{ "CURLOPT_DIRLISTONLY", "CURLOPT_DIRLISTONLY" },
    .{ "CURLOPT_USE_SSL", "CURLOPT_USE_SSL" },
    .{ "CURLUSESSL_ALL", "CURLUSESSL_ALL" },
    .{ "CURLUSESSL_CONTROL", "CURLUSESSL_CONTROL" },
    .{ "CURLUSESSL_NONE", "CURLUSESSL_NONE" },
    .{ "CURLUSESSL_TRY", "CURLUSESSL_TRY" },
    .{ "CURLOPT_SSH_HOST_PUBLIC_KEY_MD5", "CURLOPT_SSH_HOST_PUBLIC_KEY_MD5" },
    .{ "CURLOPT_PROXY_TRANSFER_MODE", "CURLOPT_PROXY_TRANSFER_MODE" },
    .{ "CURLPAUSE_ALL", "CURLPAUSE_ALL" },
    .{ "CURLPAUSE_CONT", "CURLPAUSE_CONT" },
    .{ "CURLPAUSE_RECV", "CURLPAUSE_RECV" },
    .{ "CURLPAUSE_RECV_CONT", "CURLPAUSE_RECV_CONT" },
    .{ "CURLPAUSE_SEND", "CURLPAUSE_SEND" },
    .{ "CURLPAUSE_SEND_CONT", "CURLPAUSE_SEND_CONT" },
    .{ "CURL_READFUNC_PAUSE", "CURL_READFUNC_PAUSE" },
    .{ "CURL_WRITEFUNC_PAUSE", "CURL_WRITEFUNC_PAUSE" },
    .{ "CURLPROXY_SOCKS4A", "CURLPROXY_SOCKS4A" },
    .{ "CURLPROXY_SOCKS5_HOSTNAME", "CURLPROXY_SOCKS5_HOSTNAME" },
    .{ "CURLINFO_REDIRECT_URL", "CURLINFO_REDIRECT_URL" },
    .{ "CURLINFO_APPCONNECT_TIME", "CURLINFO_APPCONNECT_TIME" },
    .{ "CURLINFO_PRIMARY_IP", "CURLINFO_PRIMARY_IP" },
    .{ "CURLOPT_ADDRESS_SCOPE", "CURLOPT_ADDRESS_SCOPE" },
    .{ "CURLOPT_CRLFILE", "CURLOPT_CRLFILE" },
    .{ "CURLOPT_ISSUERCERT", "CURLOPT_ISSUERCERT" },
    .{ "CURLOPT_KEYPASSWD", "CURLOPT_KEYPASSWD" },
    .{ "CURLSSH_AUTH_ANY", "CURLSSH_AUTH_ANY" },
    .{ "CURLSSH_AUTH_DEFAULT", "CURLSSH_AUTH_DEFAULT" },
    .{ "CURLSSH_AUTH_HOST", "CURLSSH_AUTH_HOST" },
    .{ "CURLSSH_AUTH_KEYBOARD", "CURLSSH_AUTH_KEYBOARD" },
    .{ "CURLSSH_AUTH_NONE", "CURLSSH_AUTH_NONE" },
    .{ "CURLSSH_AUTH_PASSWORD", "CURLSSH_AUTH_PASSWORD" },
    .{ "CURLSSH_AUTH_PUBLICKEY", "CURLSSH_AUTH_PUBLICKEY" },
    .{ "CURLINFO_CERTINFO", "CURLINFO_CERTINFO" },
    .{ "CURLOPT_CERTINFO", "CURLOPT_CERTINFO" },
    .{ "CURLOPT_PASSWORD", "CURLOPT_PASSWORD" },
    .{ "CURLOPT_POSTREDIR", "CURLOPT_POSTREDIR" },
    .{ "CURLOPT_PROXYPASSWORD", "CURLOPT_PROXYPASSWORD" },
    .{ "CURLOPT_PROXYUSERNAME", "CURLOPT_PROXYUSERNAME" },
    .{ "CURLOPT_USERNAME", "CURLOPT_USERNAME" },
    .{ "CURL_REDIR_POST_301", "CURL_REDIR_POST_301" },
    .{ "CURL_REDIR_POST_302", "CURL_REDIR_POST_302" },
    .{ "CURL_REDIR_POST_ALL", "CURL_REDIR_POST_ALL" },
    .{ "CURLAUTH_DIGEST_IE", "CURLAUTH_DIGEST_IE" },
    .{ "CURLINFO_CONDITION_UNMET", "CURLINFO_CONDITION_UNMET" },
    .{ "CURLOPT_NOPROXY", "CURLOPT_NOPROXY" },
    .{ "CURLOPT_PROTOCOLS", "CURLOPT_PROTOCOLS" },
    .{ "CURLOPT_REDIR_PROTOCOLS", "CURLOPT_REDIR_PROTOCOLS" },
    .{ "CURLOPT_SOCKS5_GSSAPI_NEC", "CURLOPT_SOCKS5_GSSAPI_NEC" },
    .{ "CURLOPT_SOCKS5_GSSAPI_SERVICE", "CURLOPT_SOCKS5_GSSAPI_SERVICE" },
    .{ "CURLOPT_TFTP_BLKSIZE", "CURLOPT_TFTP_BLKSIZE" },
    .{ "CURLPROTO_ALL", "CURLPROTO_ALL" },
    .{ "CURLPROTO_DICT", "CURLPROTO_DICT" },
    .{ "CURLPROTO_FILE", "CURLPROTO_FILE" },
    .{ "CURLPROTO_FTP", "CURLPROTO_FTP" },
    .{ "CURLPROTO_FTPS", "CURLPROTO_FTPS" },
    .{ "CURLPROTO_HTTP", "CURLPROTO_HTTP" },
    .{ "CURLPROTO_HTTPS", "CURLPROTO_HTTPS" },
    .{ "CURLPROTO_LDAP", "CURLPROTO_LDAP" },
    .{ "CURLPROTO_LDAPS", "CURLPROTO_LDAPS" },
    .{ "CURLPROTO_SCP", "CURLPROTO_SCP" },
    .{ "CURLPROTO_SFTP", "CURLPROTO_SFTP" },
    .{ "CURLPROTO_TELNET", "CURLPROTO_TELNET" },
    .{ "CURLPROTO_TFTP", "CURLPROTO_TFTP" },
    .{ "CURLPROXY_HTTP_1_0", "CURLPROXY_HTTP_1_0" },
    .{ "CURLFTP_CREATE_DIR", "CURLFTP_CREATE_DIR" },
    .{ "CURLFTP_CREATE_DIR_NONE", "CURLFTP_CREATE_DIR_NONE" },
    .{ "CURLFTP_CREATE_DIR_RETRY", "CURLFTP_CREATE_DIR_RETRY" },
    .{ "CURL_VERSION_CURLDEBUG", "CURL_VERSION_CURLDEBUG" },
    .{ "CURLOPT_SSH_KNOWNHOSTS", "CURLOPT_SSH_KNOWNHOSTS" },
    .{ "CURLKHMATCH_OK", "CURLKHMATCH_OK" },
    .{ "CURLKHMATCH_MISMATCH", "CURLKHMATCH_MISMATCH" },
    .{ "CURLKHMATCH_MISSING", "CURLKHMATCH_MISSING" },
    .{ "CURLKHMATCH_LAST", "CURLKHMATCH_LAST" },
    .{ "CURLINFO_RTSP_CLIENT_CSEQ", "CURLINFO_RTSP_CLIENT_CSEQ" },
    .{ "CURLINFO_RTSP_CSEQ_RECV", "CURLINFO_RTSP_CSEQ_RECV" },
    .{ "CURLINFO_RTSP_SERVER_CSEQ", "CURLINFO_RTSP_SERVER_CSEQ" },
    .{ "CURLINFO_RTSP_SESSION_ID", "CURLINFO_RTSP_SESSION_ID" },
    .{ "CURLOPT_FTP_USE_PRET", "CURLOPT_FTP_USE_PRET" },
    .{ "CURLOPT_MAIL_FROM", "CURLOPT_MAIL_FROM" },
    .{ "CURLOPT_MAIL_RCPT", "CURLOPT_MAIL_RCPT" },
    .{ "CURLOPT_RTSP_CLIENT_CSEQ", "CURLOPT_RTSP_CLIENT_CSEQ" },
    .{ "CURLOPT_RTSP_REQUEST", "CURLOPT_RTSP_REQUEST" },
    .{ "CURLOPT_RTSP_SERVER_CSEQ", "CURLOPT_RTSP_SERVER_CSEQ" },
    .{ "CURLOPT_RTSP_SESSION_ID", "CURLOPT_RTSP_SESSION_ID" },
    .{ "CURLOPT_RTSP_STREAM_URI", "CURLOPT_RTSP_STREAM_URI" },
    .{ "CURLOPT_RTSP_TRANSPORT", "CURLOPT_RTSP_TRANSPORT" },
    .{ "CURLPROTO_IMAP", "CURLPROTO_IMAP" },
    .{ "CURLPROTO_IMAPS", "CURLPROTO_IMAPS" },
    .{ "CURLPROTO_POP3", "CURLPROTO_POP3" },
    .{ "CURLPROTO_POP3S", "CURLPROTO_POP3S" },
    .{ "CURLPROTO_RTSP", "CURLPROTO_RTSP" },
    .{ "CURLPROTO_SMTP", "CURLPROTO_SMTP" },
    .{ "CURLPROTO_SMTPS", "CURLPROTO_SMTPS" },
    .{ "CURL_RTSPREQ_ANNOUNCE", "CURL_RTSPREQ_ANNOUNCE" },
    .{ "CURL_RTSPREQ_DESCRIBE", "CURL_RTSPREQ_DESCRIBE" },
    .{ "CURL_RTSPREQ_GET_PARAMETER", "CURL_RTSPREQ_GET_PARAMETER" },
    .{ "CURL_RTSPREQ_OPTIONS", "CURL_RTSPREQ_OPTIONS" },
    .{ "CURL_RTSPREQ_PAUSE", "CURL_RTSPREQ_PAUSE" },
    .{ "CURL_RTSPREQ_PLAY", "CURL_RTSPREQ_PLAY" },
    .{ "CURL_RTSPREQ_RECEIVE", "CURL_RTSPREQ_RECEIVE" },
    .{ "CURL_RTSPREQ_RECORD", "CURL_RTSPREQ_RECORD" },
    .{ "CURL_RTSPREQ_SET_PARAMETER", "CURL_RTSPREQ_SET_PARAMETER" },
    .{ "CURL_RTSPREQ_SETUP", "CURL_RTSPREQ_SETUP" },
    .{ "CURL_RTSPREQ_TEARDOWN", "CURL_RTSPREQ_TEARDOWN" },
    .{ "CURLINFO_LOCAL_IP", "CURLINFO_LOCAL_IP" },
    .{ "CURLINFO_LOCAL_PORT", "CURLINFO_LOCAL_PORT" },
    .{ "CURLINFO_PRIMARY_PORT", "CURLINFO_PRIMARY_PORT" },
    .{ "CURLOPT_FNMATCH_FUNCTION", "CURLOPT_FNMATCH_FUNCTION" },
    .{ "CURLOPT_WILDCARDMATCH", "CURLOPT_WILDCARDMATCH" },
    .{ "CURLPROTO_RTMP", "CURLPROTO_RTMP" },
    .{ "CURLPROTO_RTMPE", "CURLPROTO_RTMPE" },
    .{ "CURLPROTO_RTMPS", "CURLPROTO_RTMPS" },
    .{ "CURLPROTO_RTMPT", "CURLPROTO_RTMPT" },
    .{ "CURLPROTO_RTMPTE", "CURLPROTO_RTMPTE" },
    .{ "CURLPROTO_RTMPTS", "CURLPROTO_RTMPTS" },
    .{ "CURL_FNMATCHFUNC_FAIL", "CURL_FNMATCHFUNC_FAIL" },
    .{ "CURL_FNMATCHFUNC_MATCH", "CURL_FNMATCHFUNC_MATCH" },
    .{ "CURL_FNMATCHFUNC_NOMATCH", "CURL_FNMATCHFUNC_NOMATCH" },
    .{ "CURLPROTO_GOPHER", "CURLPROTO_GOPHER" },
    .{ "CURLAUTH_ONLY", "CURLAUTH_ONLY" },
    .{ "CURLOPT_RESOLVE", "CURLOPT_RESOLVE" },
    .{ "CURLOPT_TLSAUTH_PASSWORD", "CURLOPT_TLSAUTH_PASSWORD" },
    .{ "CURLOPT_TLSAUTH_TYPE", "CURLOPT_TLSAUTH_TYPE" },
    .{ "CURLOPT_TLSAUTH_USERNAME", "CURLOPT_TLSAUTH_USERNAME" },
    .{ "CURL_TLSAUTH_SRP", "CURL_TLSAUTH_SRP" },
    .{ "CURL_VERSION_TLSAUTH_SRP", "CURL_VERSION_TLSAUTH_SRP" },
    .{ "CURLOPT_ACCEPT_ENCODING", "CURLOPT_ACCEPT_ENCODING" },
    .{ "CURLOPT_TRANSFER_ENCODING", "CURLOPT_TRANSFER_ENCODING" },
    .{ "CURLAUTH_NTLM_WB", "CURLAUTH_NTLM_WB" },
    .{ "CURLGSSAPI_DELEGATION_FLAG", "CURLGSSAPI_DELEGATION_FLAG" },
    .{ "CURLGSSAPI_DELEGATION_POLICY_FLAG", "CURLGSSAPI_DELEGATION_POLICY_FLAG" },
    .{ "CURLOPT_GSSAPI_DELEGATION", "CURLOPT_GSSAPI_DELEGATION" },
    .{ "CURL_VERSION_NTLM_WB", "CURL_VERSION_NTLM_WB" },
    .{ "CURLOPT_ACCEPTTIMEOUT_MS", "CURLOPT_ACCEPTTIMEOUT_MS" },
    .{ "CURLOPT_DNS_SERVERS", "CURLOPT_DNS_SERVERS" },
    .{ "CURLOPT_MAIL_AUTH", "CURLOPT_MAIL_AUTH" },
    .{ "CURLOPT_SSL_OPTIONS", "CURLOPT_SSL_OPTIONS" },
    .{ "CURLOPT_TCP_KEEPALIVE", "CURLOPT_TCP_KEEPALIVE" },
    .{ "CURLOPT_TCP_KEEPIDLE", "CURLOPT_TCP_KEEPIDLE" },
    .{ "CURLOPT_TCP_KEEPINTVL", "CURLOPT_TCP_KEEPINTVL" },
    .{ "CURLSSLOPT_ALLOW_BEAST", "CURLSSLOPT_ALLOW_BEAST" },
    .{ "CURL_REDIR_POST_303", "CURL_REDIR_POST_303" },
    .{ "CURLSSH_AUTH_AGENT", "CURLSSH_AUTH_AGENT" },
    .{ "CURLMOPT_CHUNK_LENGTH_PENALTY_SIZE", "CURLMOPT_CHUNK_LENGTH_PENALTY_SIZE" },
    .{ "CURLMOPT_CONTENT_LENGTH_PENALTY_SIZE", "CURLMOPT_CONTENT_LENGTH_PENALTY_SIZE" },
    .{ "CURLMOPT_MAX_HOST_CONNECTIONS", "CURLMOPT_MAX_HOST_CONNECTIONS" },
    .{ "CURLMOPT_MAX_PIPELINE_LENGTH", "CURLMOPT_MAX_PIPELINE_LENGTH" },
    .{ "CURLMOPT_MAX_TOTAL_CONNECTIONS", "CURLMOPT_MAX_TOTAL_CONNECTIONS" },
    .{ "CURLOPT_SASL_IR", "CURLOPT_SASL_IR" },
    .{ "CURLOPT_DNS_INTERFACE", "CURLOPT_DNS_INTERFACE" },
    .{ "CURLOPT_DNS_LOCAL_IP4", "CURLOPT_DNS_LOCAL_IP4" },
    .{ "CURLOPT_DNS_LOCAL_IP6", "CURLOPT_DNS_LOCAL_IP6" },
    .{ "CURLOPT_XOAUTH2_BEARER", "CURLOPT_XOAUTH2_BEARER" },
    .{ "CURL_HTTP_VERSION_2_0", "CURL_HTTP_VERSION_2_0" },
    .{ "CURL_VERSION_HTTP2", "CURL_VERSION_HTTP2" },
    .{ "CURLOPT_LOGIN_OPTIONS", "CURLOPT_LOGIN_OPTIONS" },
    .{ "CURL_SSLVERSION_TLSv1_0", "CURL_SSLVERSION_TLSv1_0" },
    .{ "CURL_SSLVERSION_TLSv1_1", "CURL_SSLVERSION_TLSv1_1" },
    .{ "CURL_SSLVERSION_TLSv1_2", "CURL_SSLVERSION_TLSv1_2" },
    .{ "CURLOPT_EXPECT_100_TIMEOUT_MS", "CURLOPT_EXPECT_100_TIMEOUT_MS" },
    .{ "CURLOPT_SSL_ENABLE_ALPN", "CURLOPT_SSL_ENABLE_ALPN" },
    .{ "CURLOPT_SSL_ENABLE_NPN", "CURLOPT_SSL_ENABLE_NPN" },
    .{ "CURLHEADER_SEPARATE", "CURLHEADER_SEPARATE" },
    .{ "CURLHEADER_UNIFIED", "CURLHEADER_UNIFIED" },
    .{ "CURLOPT_HEADEROPT", "CURLOPT_HEADEROPT" },
    .{ "CURLOPT_PROXYHEADER", "CURLOPT_PROXYHEADER" },
    .{ "CURLAUTH_NEGOTIATE", "CURLAUTH_NEGOTIATE" },
    .{ "CURL_VERSION_GSSAPI", "CURL_VERSION_GSSAPI" },
    .{ "CURLOPT_PINNEDPUBLICKEY", "CURLOPT_PINNEDPUBLICKEY" },
    .{ "CURLOPT_UNIX_SOCKET_PATH", "CURLOPT_UNIX_SOCKET_PATH" },
    .{ "CURLPROTO_SMB", "CURLPROTO_SMB" },
    .{ "CURLPROTO_SMBS", "CURLPROTO_SMBS" },
    .{ "CURL_VERSION_KERBEROS5", "CURL_VERSION_KERBEROS5" },
    .{ "CURL_VERSION_UNIX_SOCKETS", "CURL_VERSION_UNIX_SOCKETS" },
    .{ "CURLOPT_SSL_VERIFYSTATUS", "CURLOPT_SSL_VERIFYSTATUS" },
    .{ "CURLOPT_PATH_AS_IS", "CURLOPT_PATH_AS_IS" },
    .{ "CURLOPT_SSL_FALSESTART", "CURLOPT_SSL_FALSESTART" },
    .{ "CURL_HTTP_VERSION_2", "CURL_HTTP_VERSION_2" },
    .{ "CURLOPT_PIPEWAIT", "CURLOPT_PIPEWAIT" },
    .{ "CURLOPT_PROXY_SERVICE_NAME", "CURLOPT_PROXY_SERVICE_NAME" },
    .{ "CURLOPT_SERVICE_NAME", "CURLOPT_SERVICE_NAME" },
    .{ "CURLPIPE_NOTHING", "CURLPIPE_NOTHING" },
    .{ "CURLPIPE_HTTP1", "CURLPIPE_HTTP1" },
    .{ "CURLPIPE_MULTIPLEX", "CURLPIPE_MULTIPLEX" },
    .{ "CURLSSLOPT_NO_REVOKE", "CURLSSLOPT_NO_REVOKE" },
    .{ "CURLOPT_DEFAULT_PROTOCOL", "CURLOPT_DEFAULT_PROTOCOL" },
    .{ "CURLOPT_STREAM_WEIGHT", "CURLOPT_STREAM_WEIGHT" },
    .{ "CURLMOPT_PUSHFUNCTION", "CURLMOPT_PUSHFUNCTION" },
    .{ "CURL_PUSH_OK", "CURL_PUSH_OK" },
    .{ "CURL_PUSH_DENY", "CURL_PUSH_DENY" },
    .{ "CURL_HTTP_VERSION_2TLS", "CURL_HTTP_VERSION_2TLS" },
    .{ "CURL_VERSION_PSL", "CURL_VERSION_PSL" },
    .{ "CURLOPT_TFTP_NO_OPTIONS", "CURLOPT_TFTP_NO_OPTIONS" },
    .{ "CURL_HTTP_VERSION_2_PRIOR_KNOWLEDGE", "CURL_HTTP_VERSION_2_PRIOR_KNOWLEDGE" },
    .{ "CURLOPT_CONNECT_TO", "CURLOPT_CONNECT_TO" },
    .{ "CURLOPT_TCP_FASTOPEN", "CURLOPT_TCP_FASTOPEN" },
    .{ "CURLINFO_HTTP_VERSION", "CURLINFO_HTTP_VERSION" },
    .{ "CURLE_WEIRD_SERVER_REPLY", "CURLE_WEIRD_SERVER_REPLY" },
    .{ "CURLOPT_KEEP_SENDING_ON_ERROR", "CURLOPT_KEEP_SENDING_ON_ERROR" },
    .{ "CURL_SSLVERSION_TLSv1_3", "CURL_SSLVERSION_TLSv1_3" },
    .{ "CURL_VERSION_HTTPS_PROXY", "CURL_VERSION_HTTPS_PROXY" },
    .{ "CURLINFO_PROTOCOL", "CURLINFO_PROTOCOL" },
    .{ "CURLINFO_PROXY_SSL_VERIFYRESULT", "CURLINFO_PROXY_SSL_VERIFYRESULT" },
    .{ "CURLINFO_SCHEME", "CURLINFO_SCHEME" },
    .{ "CURLOPT_PRE_PROXY", "CURLOPT_PRE_PROXY" },
    .{ "CURLOPT_PROXY_CAINFO", "CURLOPT_PROXY_CAINFO" },
    .{ "CURLOPT_PROXY_CAPATH", "CURLOPT_PROXY_CAPATH" },
    .{ "CURLOPT_PROXY_CRLFILE", "CURLOPT_PROXY_CRLFILE" },
    .{ "CURLOPT_PROXY_KEYPASSWD", "CURLOPT_PROXY_KEYPASSWD" },
    .{ "CURLOPT_PROXY_PINNEDPUBLICKEY", "CURLOPT_PROXY_PINNEDPUBLICKEY" },
    .{ "CURLOPT_PROXY_SSL_CIPHER_LIST", "CURLOPT_PROXY_SSL_CIPHER_LIST" },
    .{ "CURLOPT_PROXY_SSL_OPTIONS", "CURLOPT_PROXY_SSL_OPTIONS" },
    .{ "CURLOPT_PROXY_SSL_VERIFYHOST", "CURLOPT_PROXY_SSL_VERIFYHOST" },
    .{ "CURLOPT_PROXY_SSL_VERIFYPEER", "CURLOPT_PROXY_SSL_VERIFYPEER" },
    .{ "CURLOPT_PROXY_SSLCERT", "CURLOPT_PROXY_SSLCERT" },
    .{ "CURLOPT_PROXY_SSLCERTTYPE", "CURLOPT_PROXY_SSLCERTTYPE" },
    .{ "CURLOPT_PROXY_SSLKEY", "CURLOPT_PROXY_SSLKEY" },
    .{ "CURLOPT_PROXY_SSLKEYTYPE", "CURLOPT_PROXY_SSLKEYTYPE" },
    .{ "CURLOPT_PROXY_SSLVERSION", "CURLOPT_PROXY_SSLVERSION" },
    .{ "CURLOPT_PROXY_TLSAUTH_PASSWORD", "CURLOPT_PROXY_TLSAUTH_PASSWORD" },
    .{ "CURLOPT_PROXY_TLSAUTH_TYPE", "CURLOPT_PROXY_TLSAUTH_TYPE" },
    .{ "CURLOPT_PROXY_TLSAUTH_USERNAME", "CURLOPT_PROXY_TLSAUTH_USERNAME" },
    .{ "CURLPROXY_HTTPS", "CURLPROXY_HTTPS" },
    .{ "CURL_MAX_READ_SIZE", "CURL_MAX_READ_SIZE" },
    .{ "CURLOPT_ABSTRACT_UNIX_SOCKET", "CURLOPT_ABSTRACT_UNIX_SOCKET" },
    .{ "CURL_SSLVERSION_MAX_DEFAULT", "CURL_SSLVERSION_MAX_DEFAULT" },
    .{ "CURL_SSLVERSION_MAX_NONE", "CURL_SSLVERSION_MAX_NONE" },
    .{ "CURL_SSLVERSION_MAX_TLSv1_0", "CURL_SSLVERSION_MAX_TLSv1_0" },
    .{ "CURL_SSLVERSION_MAX_TLSv1_1", "CURL_SSLVERSION_MAX_TLSv1_1" },
    .{ "CURL_SSLVERSION_MAX_TLSv1_2", "CURL_SSLVERSION_MAX_TLSv1_2" },
    .{ "CURL_SSLVERSION_MAX_TLSv1_3", "CURL_SSLVERSION_MAX_TLSv1_3" },
    .{ "CURLOPT_SUPPRESS_CONNECT_HEADERS", "CURLOPT_SUPPRESS_CONNECT_HEADERS" },
    .{ "CURLAUTH_GSSAPI", "CURLAUTH_GSSAPI" },
    .{ "CURLINFO_CONTENT_LENGTH_DOWNLOAD_T", "CURLINFO_CONTENT_LENGTH_DOWNLOAD_T" },
    .{ "CURLINFO_CONTENT_LENGTH_UPLOAD_T", "CURLINFO_CONTENT_LENGTH_UPLOAD_T" },
    .{ "CURLINFO_SIZE_DOWNLOAD_T", "CURLINFO_SIZE_DOWNLOAD_T" },
    .{ "CURLINFO_SIZE_UPLOAD_T", "CURLINFO_SIZE_UPLOAD_T" },
    .{ "CURLINFO_SPEED_DOWNLOAD_T", "CURLINFO_SPEED_DOWNLOAD_T" },
    .{ "CURLINFO_SPEED_UPLOAD_T", "CURLINFO_SPEED_UPLOAD_T" },
    .{ "CURLOPT_REQUEST_TARGET", "CURLOPT_REQUEST_TARGET" },
    .{ "CURLOPT_SOCKS5_AUTH", "CURLOPT_SOCKS5_AUTH" },
    .{ "CURLOPT_SSH_COMPRESSION", "CURLOPT_SSH_COMPRESSION" },
    .{ "CURL_VERSION_MULTI_SSL", "CURL_VERSION_MULTI_SSL" },
    .{ "CURL_VERSION_BROTLI", "CURL_VERSION_BROTLI" },
    .{ "CURL_LOCK_DATA_CONNECT", "CURL_LOCK_DATA_CONNECT" },
    .{ "CURLSSH_AUTH_GSSAPI", "CURLSSH_AUTH_GSSAPI" },
    .{ "CURLINFO_FILETIME_T", "CURLINFO_FILETIME_T" },
    .{ "CURLOPT_HAPPY_EYEBALLS_TIMEOUT_MS", "CURLOPT_HAPPY_EYEBALLS_TIMEOUT_MS" },
    .{ "CURLOPT_TIMEVALUE_LARGE", "CURLOPT_TIMEVALUE_LARGE" },
    .{ "CURLOPT_DNS_SHUFFLE_ADDRESSES", "CURLOPT_DNS_SHUFFLE_ADDRESSES" },
    .{ "CURLOPT_HAPROXYPROTOCOL", "CURLOPT_HAPROXYPROTOCOL" },
    .{ "CURL_LOCK_DATA_PSL", "CURL_LOCK_DATA_PSL" },
    .{ "CURLAUTH_BEARER", "CURLAUTH_BEARER" },
    .{ "CURLINFO_QUEUE_TIME_T", "CURLINFO_QUEUE_TIME_T" },
    .{ "CURLINFO_APPCONNECT_TIME_T", "CURLINFO_APPCONNECT_TIME_T" },
    .{ "CURLINFO_CONNECT_TIME_T", "CURLINFO_CONNECT_TIME_T" },
    .{ "CURLINFO_NAMELOOKUP_TIME_T", "CURLINFO_NAMELOOKUP_TIME_T" },
    .{ "CURLINFO_PRETRANSFER_TIME_T", "CURLINFO_PRETRANSFER_TIME_T" },
    .{ "CURLINFO_REDIRECT_TIME_T", "CURLINFO_REDIRECT_TIME_T" },
    .{ "CURLINFO_STARTTRANSFER_TIME_T", "CURLINFO_STARTTRANSFER_TIME_T" },
    .{ "CURLINFO_TOTAL_TIME_T", "CURLINFO_TOTAL_TIME_T" },
    .{ "CURLINFO_USED_PROXY", "CURLINFO_USED_PROXY" },
    .{ "CURLINFO_POSTTRANSFER_TIME_T", "CURLINFO_POSTTRANSFER_TIME_T" },
    .{ "CURLINFO_CONN_ID", "CURLINFO_CONN_ID" },
    .{ "CURLOPT_DISALLOW_USERNAME_IN_URL", "CURLOPT_DISALLOW_USERNAME_IN_URL" },
    .{ "CURLOPT_PROXY_TLS13_CIPHERS", "CURLOPT_PROXY_TLS13_CIPHERS" },
    .{ "CURLOPT_TLS13_CIPHERS", "CURLOPT_TLS13_CIPHERS" },
    .{ "CURLOPT_DOH_URL", "CURLOPT_DOH_URL" },
    .{ "CURLOPT_UPKEEP_INTERVAL_MS", "CURLOPT_UPKEEP_INTERVAL_MS" },
    .{ "CURLOPT_UPLOAD_BUFFERSIZE", "CURLOPT_UPLOAD_BUFFERSIZE" },
    .{ "CURLOPT_HTTP09_ALLOWED", "CURLOPT_HTTP09_ALLOWED" },
    .{ "CURLALTSVC_H1", "CURLALTSVC_H1" },
    .{ "CURLALTSVC_H2", "CURLALTSVC_H2" },
    .{ "CURLALTSVC_H3", "CURLALTSVC_H3" },
    .{ "CURLALTSVC_READONLYFILE", "CURLALTSVC_READONLYFILE" },
    .{ "CURLOPT_ALTSVC", "CURLOPT_ALTSVC" },
    .{ "CURLOPT_ALTSVC_CTRL", "CURLOPT_ALTSVC_CTRL" },
    .{ "CURL_VERSION_ALTSVC", "CURL_VERSION_ALTSVC" },
    .{ "CURLOPT_MAXAGE_CONN", "CURLOPT_MAXAGE_CONN" },
    .{ "CURLOPT_SASL_AUTHZID", "CURLOPT_SASL_AUTHZID" },
    .{ "CURL_VERSION_HTTP3", "CURL_VERSION_HTTP3" },
    .{ "CURLINFO_RETRY_AFTER", "CURLINFO_RETRY_AFTER" },
    .{ "CURL_HTTP_VERSION_3", "CURL_HTTP_VERSION_3" },
    .{ "CURLMOPT_MAX_CONCURRENT_STREAMS", "CURLMOPT_MAX_CONCURRENT_STREAMS" },
    .{ "CURLSSLOPT_NO_PARTIALCHAIN", "CURLSSLOPT_NO_PARTIALCHAIN" },
    .{ "CURLOPT_MAIL_RCPT_ALLLOWFAILS", "CURLOPT_MAIL_RCPT_ALLLOWFAILS" },
    .{ "CURLSSLOPT_REVOKE_BEST_EFFORT", "CURLSSLOPT_REVOKE_BEST_EFFORT" },
    .{ "CURLOPT_ISSUERCERT_BLOB", "CURLOPT_ISSUERCERT_BLOB" },
    .{ "CURLOPT_PROXY_ISSUERCERT", "CURLOPT_PROXY_ISSUERCERT" },
    .{ "CURLOPT_PROXY_ISSUERCERT_BLOB", "CURLOPT_PROXY_ISSUERCERT_BLOB" },
    .{ "CURLOPT_PROXY_SSLCERT_BLOB", "CURLOPT_PROXY_SSLCERT_BLOB" },
    .{ "CURLOPT_PROXY_SSLKEY_BLOB", "CURLOPT_PROXY_SSLKEY_BLOB" },
    .{ "CURLOPT_SSLCERT_BLOB", "CURLOPT_SSLCERT_BLOB" },
    .{ "CURLOPT_SSLKEY_BLOB", "CURLOPT_SSLKEY_BLOB" },
    .{ "CURLPROTO_MQTT", "CURLPROTO_MQTT" },
    .{ "CURLSSLOPT_NATIVE_CA", "CURLSSLOPT_NATIVE_CA" },
    .{ "CURL_VERSION_UNICODE", "CURL_VERSION_UNICODE" },
    .{ "CURL_VERSION_ZSTD", "CURL_VERSION_ZSTD" },
    .{ "CURLE_PROXY", "CURLE_PROXY" },
    .{ "CURLINFO_PROXY_ERROR", "CURLINFO_PROXY_ERROR" },
    .{ "CURLOPT_SSL_EC_CURVES", "CURLOPT_SSL_EC_CURVES" },
    .{ "CURLOPT_SSL_SIGNATURE_ALGORITHMS", "CURLOPT_SSL_SIGNATURE_ALGORITHMS" },
    .{ "CURLPX_BAD_ADDRESS_TYPE", "CURLPX_BAD_ADDRESS_TYPE" },
    .{ "CURLPX_BAD_VERSION", "CURLPX_BAD_VERSION" },
    .{ "CURLPX_CLOSED", "CURLPX_CLOSED" },
    .{ "CURLPX_GSSAPI", "CURLPX_GSSAPI" },
    .{ "CURLPX_GSSAPI_PERMSG", "CURLPX_GSSAPI_PERMSG" },
    .{ "CURLPX_GSSAPI_PROTECTION", "CURLPX_GSSAPI_PROTECTION" },
    .{ "CURLPX_IDENTD", "CURLPX_IDENTD" },
    .{ "CURLPX_IDENTD_DIFFER", "CURLPX_IDENTD_DIFFER" },
    .{ "CURLPX_LONG_HOSTNAME", "CURLPX_LONG_HOSTNAME" },
    .{ "CURLPX_LONG_PASSWD", "CURLPX_LONG_PASSWD" },
    .{ "CURLPX_LONG_USER", "CURLPX_LONG_USER" },
    .{ "CURLPX_NO_AUTH", "CURLPX_NO_AUTH" },
    .{ "CURLPX_OK", "CURLPX_OK" },
    .{ "CURLPX_RECV_ADDRESS", "CURLPX_RECV_ADDRESS" },
    .{ "CURLPX_RECV_AUTH", "CURLPX_RECV_AUTH" },
    .{ "CURLPX_RECV_CONNECT", "CURLPX_RECV_CONNECT" },
    .{ "CURLPX_RECV_REQACK", "CURLPX_RECV_REQACK" },
    .{ "CURLPX_REPLY_ADDRESS_TYPE_NOT_SUPPORTED", "CURLPX_REPLY_ADDRESS_TYPE_NOT_SUPPORTED" },
    .{ "CURLPX_REPLY_COMMAND_NOT_SUPPORTED", "CURLPX_REPLY_COMMAND_NOT_SUPPORTED" },
    .{ "CURLPX_REPLY_CONNECTION_REFUSED", "CURLPX_REPLY_CONNECTION_REFUSED" },
    .{ "CURLPX_REPLY_GENERAL_SERVER_FAILURE", "CURLPX_REPLY_GENERAL_SERVER_FAILURE" },
    .{ "CURLPX_REPLY_HOST_UNREACHABLE", "CURLPX_REPLY_HOST_UNREACHABLE" },
    .{ "CURLPX_REPLY_NETWORK_UNREACHABLE", "CURLPX_REPLY_NETWORK_UNREACHABLE" },
    .{ "CURLPX_REPLY_NOT_ALLOWED", "CURLPX_REPLY_NOT_ALLOWED" },
    .{ "CURLPX_REPLY_TTL_EXPIRED", "CURLPX_REPLY_TTL_EXPIRED" },
    .{ "CURLPX_REPLY_UNASSIGNED", "CURLPX_REPLY_UNASSIGNED" },
    .{ "CURLPX_REQUEST_FAILED", "CURLPX_REQUEST_FAILED" },
    .{ "CURLPX_RESOLVE_HOST", "CURLPX_RESOLVE_HOST" },
    .{ "CURLPX_SEND_AUTH", "CURLPX_SEND_AUTH" },
    .{ "CURLPX_SEND_CONNECT", "CURLPX_SEND_CONNECT" },
    .{ "CURLPX_SEND_REQUEST", "CURLPX_SEND_REQUEST" },
    .{ "CURLPX_UNKNOWN_FAIL", "CURLPX_UNKNOWN_FAIL" },
    .{ "CURLPX_UNKNOWN_MODE", "CURLPX_UNKNOWN_MODE" },
    .{ "CURLPX_USER_REJECTED", "CURLPX_USER_REJECTED" },
    .{ "CURLHSTS_ENABLE", "CURLHSTS_ENABLE" },
    .{ "CURLHSTS_READONLYFILE", "CURLHSTS_READONLYFILE" },
    .{ "CURLOPT_HSTS", "CURLOPT_HSTS" },
    .{ "CURLOPT_HSTS_CTRL", "CURLOPT_HSTS_CTRL" },
    .{ "CURL_VERSION_HSTS", "CURL_VERSION_HSTS" },
    .{ "CURLAUTH_AWS_SIGV4", "CURLAUTH_AWS_SIGV4" },
    .{ "CURLOPT_AWS_SIGV4", "CURLOPT_AWS_SIGV4" },
    .{ "CURLINFO_REFERER", "CURLINFO_REFERER" },
    .{ "CURLOPT_DOH_SSL_VERIFYHOST", "CURLOPT_DOH_SSL_VERIFYHOST" },
    .{ "CURLOPT_DOH_SSL_VERIFYPEER", "CURLOPT_DOH_SSL_VERIFYPEER" },
    .{ "CURLOPT_DOH_SSL_VERIFYSTATUS", "CURLOPT_DOH_SSL_VERIFYSTATUS" },
    .{ "CURL_VERSION_GSASL", "CURL_VERSION_GSASL" },
    .{ "CURLOPT_CAINFO_BLOB", "CURLOPT_CAINFO_BLOB" },
    .{ "CURLOPT_PROXY_CAINFO_BLOB", "CURLOPT_PROXY_CAINFO_BLOB" },
    .{ "CURLSSLOPT_AUTO_CLIENT_CERT", "CURLSSLOPT_AUTO_CLIENT_CERT" },
    .{ "CURLOPT_MAXLIFETIME_CONN", "CURLOPT_MAXLIFETIME_CONN" },
    .{ "CURLOPT_SSH_HOST_PUBLIC_KEY_SHA256", "CURLOPT_SSH_HOST_PUBLIC_KEY_SHA256" },
    .{ "CURLOPT_PREREQFUNCTION", "CURLOPT_PREREQFUNCTION" },
    .{ "CURL_PREREQFUNC_OK", "CURL_PREREQFUNC_OK" },
    .{ "CURL_PREREQFUNC_ABORT", "CURL_PREREQFUNC_ABORT" },
    .{ "CURLOPT_MIME_OPTIONS", "CURLOPT_MIME_OPTIONS" },
    .{ "CURLMIMEOPT_FORMESCAPE", "CURLMIMEOPT_FORMESCAPE" },
    .{ "CURLOPT_SSH_HOSTKEYFUNCTION", "CURLOPT_SSH_HOSTKEYFUNCTION" },
    .{ "CURLOPT_PROTOCOLS_STR", "CURLOPT_PROTOCOLS_STR" },
    .{ "CURLOPT_REDIR_PROTOCOLS_STR", "CURLOPT_REDIR_PROTOCOLS_STR" },
    .{ "CURLOPT_WS_OPTIONS", "CURLOPT_WS_OPTIONS" },
    .{ "CURLWS_RAW_MODE", "CURLWS_RAW_MODE" },
    .{ "CURLOPT_CA_CACHE_TIMEOUT", "CURLOPT_CA_CACHE_TIMEOUT" },
    .{ "CURLOPT_QUICK_EXIT", "CURLOPT_QUICK_EXIT" },
    .{ "CURL_HTTP_VERSION_3ONLY", "CURL_HTTP_VERSION_3ONLY" },
    .{ "CURLOPT_SAFE_UPLOAD", "CURLOPT_SAFE_UPLOAD" },
};

pub fn cleanupResources(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    for (objects.items) |obj| {
        switch (obj.native.kind) {
            .curl => cleanupHandle(obj),
            .curl_share => _ = cleanupShare(obj),
            else => {},
        }
    }
}

test "curl property growth across native contexts and allocation-free cleanup" {
    const a = std.testing.allocator;
    const vm = try VM.initOnHeap(a);
    defer a.destroy(vm);
    defer vm.deinit();
    var init_ctx = vm.makeContext("curl_init");
    const easy = (try curlInit(&init_ctx, &.{})).value;
    var later_ctx = vm.makeContext("curl_setopt");
    const headers = try later_ctx.createArray();
    try headers.append(later_ctx.allocator, .{ .string = Value.String.borrowed("X-Allocator-Test: yes") });
    _ = try curlSetopt(&later_ctx, &.{ easy, .{ .int = c.CURLOPT_HTTPHEADER }, .{ .array = headers } });
    // Fill to an exact capacity boundary, growing repeatedly using a later
    // context. put(existing_key) would reserve count + 1 at this boundary.
    var keys: [256][32]u8 = undefined;
    const initial_capacity = easy.object.properties.capacity();
    var i: usize = 0;
    while (easy.object.properties.capacity() <= initial_capacity or
        easy.object.properties.count() < easy.object.properties.capacity()) : (i += 1)
    {
        const key = try std.fmt.bufPrint(&keys[i], "test_property_{d}", .{i});
        try easy.object.set(later_ctx.allocator, key, .{ .int = @intCast(i) });
    }
    const capacity = easy.object.properties.capacity();
    _ = try curlClose(&later_ctx, &.{easy});
    try std.testing.expectEqual(capacity, easy.object.properties.capacity());
    try std.testing.expectEqual(@as(usize, 0), easy.object.native.ptr);
    cleanupHandle(easy.object);

    const multi = (try curlMultiInit(&init_ctx, &.{})).value;
    i = 0;
    while (multi.object.properties.count() < multi.object.properties.capacity()) : (i += 1) {
        const key = try std.fmt.bufPrint(&keys[128 + i], "multi_property_{d}", .{i});
        try multi.object.set(later_ctx.allocator, key, .null);
    }
    const multi_capacity = multi.object.properties.capacity();
    _ = try curlMultiClose(&later_ctx, &.{multi});
    try std.testing.expectEqual(multi_capacity, multi.object.properties.capacity());
    _ = try curlMultiClose(&later_ctx, &.{multi});
}

// php's option groups (ext/curl/interface.c, _php_curl_setopt)
const long_options = [_][]const u8{
    "CURLOPT_SSL_VERIFYHOST",
    "CURLOPT_AUTOREFERER",
    "CURLOPT_BUFFERSIZE",
    "CURLOPT_CONNECTTIMEOUT",
    "CURLOPT_COOKIESESSION",
    "CURLOPT_CRLF",
    "CURLOPT_DNS_CACHE_TIMEOUT",
    "CURLOPT_FAILONERROR",
    "CURLOPT_FILETIME",
    "CURLOPT_FORBID_REUSE",
    "CURLOPT_FRESH_CONNECT",
    "CURLOPT_FTP_USE_EPRT",
    "CURLOPT_FTP_USE_EPSV",
    "CURLOPT_HEADER",
    "CURLOPT_HTTPGET",
    "CURLOPT_HTTPPROXYTUNNEL",
    "CURLOPT_HTTP_VERSION",
    "CURLOPT_INFILESIZE",
    "CURLOPT_LOW_SPEED_LIMIT",
    "CURLOPT_LOW_SPEED_TIME",
    "CURLOPT_MAXCONNECTS",
    "CURLOPT_MAXREDIRS",
    "CURLOPT_NETRC",
    "CURLOPT_NOBODY",
    "CURLOPT_NOPROGRESS",
    "CURLOPT_NOSIGNAL",
    "CURLOPT_PORT",
    "CURLOPT_POST",
    "CURLOPT_PROXYPORT",
    "CURLOPT_PROXYTYPE",
    "CURLOPT_PUT",
    "CURLOPT_RESUME_FROM",
    "CURLOPT_SSLVERSION",
    "CURLOPT_SSL_VERIFYPEER",
    "CURLOPT_TIMECONDITION",
    "CURLOPT_TIMEOUT",
    "CURLOPT_TIMEVALUE",
    "CURLOPT_TRANSFERTEXT",
    "CURLOPT_UNRESTRICTED_AUTH",
    "CURLOPT_UPLOAD",
    "CURLOPT_VERBOSE",
    "CURLOPT_HTTPAUTH",
    "CURLOPT_FTP_CREATE_MISSING_DIRS",
    "CURLOPT_PROXYAUTH",
    "CURLOPT_SERVER_RESPONSE_TIMEOUT",
    "CURLOPT_IPRESOLVE",
    "CURLOPT_MAXFILESIZE",
    "CURLOPT_TCP_NODELAY",
    "CURLOPT_FTPSSLAUTH",
    "CURLOPT_IGNORE_CONTENT_LENGTH",
    "CURLOPT_FTP_SKIP_PASV_IP",
    "CURLOPT_FTP_FILEMETHOD",
    "CURLOPT_CONNECT_ONLY",
    "CURLOPT_LOCALPORT",
    "CURLOPT_LOCALPORTRANGE",
    "CURLOPT_SSL_SESSIONID_CACHE",
    "CURLOPT_FTP_SSL_CCC",
    "CURLOPT_SSH_AUTH_TYPES",
    "CURLOPT_CONNECTTIMEOUT_MS",
    "CURLOPT_HTTP_CONTENT_DECODING",
    "CURLOPT_HTTP_TRANSFER_DECODING",
    "CURLOPT_TIMEOUT_MS",
    "CURLOPT_NEW_DIRECTORY_PERMS",
    "CURLOPT_NEW_FILE_PERMS",
    "CURLOPT_USE_SSL",
    "CURLOPT_APPEND",
    "CURLOPT_DIRLISTONLY",
    "CURLOPT_PROXY_TRANSFER_MODE",
    "CURLOPT_ADDRESS_SCOPE",
    "CURLOPT_CERTINFO",
    "CURLOPT_PROTOCOLS",
    "CURLOPT_REDIR_PROTOCOLS",
    "CURLOPT_SOCKS5_GSSAPI_NEC",
    "CURLOPT_TFTP_BLKSIZE",
    "CURLOPT_FTP_USE_PRET",
    "CURLOPT_RTSP_CLIENT_CSEQ",
    "CURLOPT_RTSP_REQUEST",
    "CURLOPT_RTSP_SERVER_CSEQ",
    "CURLOPT_WILDCARDMATCH",
    "CURLOPT_GSSAPI_DELEGATION",
    "CURLOPT_ACCEPTTIMEOUT_MS",
    "CURLOPT_SSL_OPTIONS",
    "CURLOPT_TCP_KEEPALIVE",
    "CURLOPT_TCP_KEEPIDLE",
    "CURLOPT_TCP_KEEPINTVL",
    "CURLOPT_SASL_IR",
    "CURLOPT_EXPECT_100_TIMEOUT_MS",
    "CURLOPT_SSL_ENABLE_ALPN",
    "CURLOPT_SSL_ENABLE_NPN",
    "CURLOPT_HEADEROPT",
    "CURLOPT_SSL_VERIFYSTATUS",
    "CURLOPT_PATH_AS_IS",
    "CURLOPT_SSL_FALSESTART",
    "CURLOPT_PIPEWAIT",
    "CURLOPT_STREAM_WEIGHT",
    "CURLOPT_TFTP_NO_OPTIONS",
    "CURLOPT_TCP_FASTOPEN",
    "CURLOPT_KEEP_SENDING_ON_ERROR",
    "CURLOPT_PROXY_SSL_OPTIONS",
    "CURLOPT_PROXY_SSL_VERIFYHOST",
    "CURLOPT_PROXY_SSL_VERIFYPEER",
    "CURLOPT_PROXY_SSLVERSION",
    "CURLOPT_SUPPRESS_CONNECT_HEADERS",
    "CURLOPT_SOCKS5_AUTH",
    "CURLOPT_SSH_COMPRESSION",
    "CURLOPT_HAPPY_EYEBALLS_TIMEOUT_MS",
    "CURLOPT_DNS_SHUFFLE_ADDRESSES",
    "CURLOPT_HAPROXYPROTOCOL",
    "CURLOPT_DISALLOW_USERNAME_IN_URL",
    "CURLOPT_UPKEEP_INTERVAL_MS",
    "CURLOPT_UPLOAD_BUFFERSIZE",
    "CURLOPT_HTTP09_ALLOWED",
    "CURLOPT_ALTSVC_CTRL",
    "CURLOPT_MAXAGE_CONN",
    "CURLOPT_MAIL_RCPT_ALLLOWFAILS",
    "CURLOPT_HSTS_CTRL",
    "CURLOPT_DOH_SSL_VERIFYHOST",
    "CURLOPT_DOH_SSL_VERIFYPEER",
    "CURLOPT_DOH_SSL_VERIFYSTATUS",
    "CURLOPT_MAXLIFETIME_CONN",
    "CURLOPT_MIME_OPTIONS",
    "CURLOPT_WS_OPTIONS",
    "CURLOPT_CA_CACHE_TIMEOUT",
    "CURLOPT_QUICK_EXIT",
    "CURLOPT_TCP_KEEPCNT",
    "CURLOPT_FOLLOWLOCATION",
};
const string_options = [_][]const u8{
    "CURLOPT_CAINFO",
    "CURLOPT_CAPATH",
    "CURLOPT_COOKIE",
    "CURLOPT_EGDSOCKET",
    "CURLOPT_INTERFACE",
    "CURLOPT_PROXY",
    "CURLOPT_PROXYUSERPWD",
    "CURLOPT_REFERER",
    "CURLOPT_SSLCERTTYPE",
    "CURLOPT_SSLENGINE",
    "CURLOPT_SSLENGINE_DEFAULT",
    "CURLOPT_SSLKEY",
    "CURLOPT_SSLKEYPASSWD",
    "CURLOPT_SSLKEYTYPE",
    "CURLOPT_SSL_CIPHER_LIST",
    "CURLOPT_USERAGENT",
    "CURLOPT_COOKIELIST",
    "CURLOPT_FTP_ALTERNATIVE_TO_USER",
    "CURLOPT_SSH_HOST_PUBLIC_KEY_MD5",
    "CURLOPT_PROXYPASSWORD",
    "CURLOPT_PROXYUSERNAME",
    "CURLOPT_NOPROXY",
    "CURLOPT_SOCKS5_GSSAPI_SERVICE",
    "CURLOPT_MAIL_FROM",
    "CURLOPT_RTSP_STREAM_URI",
    "CURLOPT_RTSP_TRANSPORT",
    "CURLOPT_TLSAUTH_TYPE",
    "CURLOPT_TLSAUTH_PASSWORD",
    "CURLOPT_TLSAUTH_USERNAME",
    "CURLOPT_TRANSFER_ENCODING",
    "CURLOPT_DNS_SERVERS",
    "CURLOPT_MAIL_AUTH",
    "CURLOPT_LOGIN_OPTIONS",
    "CURLOPT_PINNEDPUBLICKEY",
    "CURLOPT_PROXY_SERVICE_NAME",
    "CURLOPT_SERVICE_NAME",
    "CURLOPT_DEFAULT_PROTOCOL",
    "CURLOPT_PRE_PROXY",
    "CURLOPT_PROXY_CAINFO",
    "CURLOPT_PROXY_CAPATH",
    "CURLOPT_PROXY_CRLFILE",
    "CURLOPT_PROXY_KEYPASSWD",
    "CURLOPT_PROXY_PINNEDPUBLICKEY",
    "CURLOPT_PROXY_SSL_CIPHER_LIST",
    "CURLOPT_PROXY_SSLCERT",
    "CURLOPT_PROXY_SSLCERTTYPE",
    "CURLOPT_PROXY_SSLKEY",
    "CURLOPT_PROXY_SSLKEYTYPE",
    "CURLOPT_PROXY_TLSAUTH_PASSWORD",
    "CURLOPT_PROXY_TLSAUTH_TYPE",
    "CURLOPT_PROXY_TLSAUTH_USERNAME",
    "CURLOPT_ABSTRACT_UNIX_SOCKET",
    "CURLOPT_REQUEST_TARGET",
    "CURLOPT_PROXY_TLS13_CIPHERS",
    "CURLOPT_TLS13_CIPHERS",
    "CURLOPT_ALTSVC",
    "CURLOPT_SASL_AUTHZID",
    "CURLOPT_PROXY_ISSUERCERT",
    "CURLOPT_SSL_EC_CURVES",
    "CURLOPT_AWS_SIGV4",
    "CURLOPT_SSH_HOST_PUBLIC_KEY_SHA256",
    "CURLOPT_PROTOCOLS_STR",
    "CURLOPT_REDIR_PROTOCOLS_STR",
    "CURLOPT_COOKIEFILE",
    "CURLOPT_COOKIEJAR",
    "CURLOPT_RANDOM_FILE",
    "CURLOPT_SSLCERT",
    "CURLOPT_NETRC_FILE",
    "CURLOPT_SSH_PRIVATE_KEYFILE",
    "CURLOPT_SSH_PUBLIC_KEYFILE",
    "CURLOPT_CRLFILE",
    "CURLOPT_ISSUERCERT",
    "CURLOPT_SSH_KNOWNHOSTS",
};
const nullable_string_options = [_][]const u8{
    "CURLOPT_CUSTOMREQUEST",
    "CURLOPT_FTPPORT",
    "CURLOPT_RANGE",
    "CURLOPT_FTP_ACCOUNT",
    "CURLOPT_RTSP_SESSION_ID",
    "CURLOPT_ACCEPT_ENCODING",
    "CURLOPT_DNS_INTERFACE",
    "CURLOPT_DNS_LOCAL_IP4",
    "CURLOPT_DNS_LOCAL_IP6",
    "CURLOPT_XOAUTH2_BEARER",
    "CURLOPT_UNIX_SOCKET_PATH",
    "CURLOPT_DOH_URL",
    "CURLOPT_HSTS",
    "CURLOPT_KRBLEVEL",
    "CURLOPT_USERPWD",
    "CURLOPT_USERNAME",
    "CURLOPT_PASSWORD",
    "CURLOPT_SSL_SIGNATURE_ALGORITHMS",
};
const slist_options = [_][]const u8{
    "CURLOPT_HTTP200ALIASES",
    "CURLOPT_HTTPHEADER",
    "CURLOPT_POSTQUOTE",
    "CURLOPT_PREQUOTE",
    "CURLOPT_QUOTE",
    "CURLOPT_TELNETOPTIONS",
    "CURLOPT_MAIL_RCPT",
    "CURLOPT_RESOLVE",
    "CURLOPT_PROXYHEADER",
    "CURLOPT_CONNECT_TO",
};
const off_t_options = [_][]const u8{
    "CURLOPT_INFILESIZE_LARGE",
    "CURLOPT_MAX_RECV_SPEED_LARGE",
    "CURLOPT_MAX_SEND_SPEED_LARGE",
    "CURLOPT_MAXFILESIZE_LARGE",
    "CURLOPT_TIMEVALUE_LARGE",
};
const blob_options = [_][]const u8{
    "CURLOPT_ISSUERCERT_BLOB",
    "CURLOPT_PROXY_ISSUERCERT_BLOB",
    "CURLOPT_PROXY_SSLCERT_BLOB",
    "CURLOPT_PROXY_SSLKEY_BLOB",
    "CURLOPT_SSLCERT_BLOB",
    "CURLOPT_SSLKEY_BLOB",
    "CURLOPT_CAINFO_BLOB",
    "CURLOPT_PROXY_CAINFO_BLOB",
};
